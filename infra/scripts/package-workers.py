#!/usr/bin/env python3
"""Build and verify deterministic, credential-free Azure Functions ZIP packages."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile


FIXED_ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)
FIXED_FILE_MODE = 0o100644 << 16
SOURCE_REVISION_PATTERN = re.compile(r"^[0-9a-f]{40}$")
MAX_ARCHIVE_BYTES = 256 * 1024 * 1024


class PackagingError(RuntimeError):
    pass


PROJECTS = (
    {
        "key": "general-workers",
        "project": "src/FundingPlatform.Workers/FundingPlatform.Workers.csproj",
        "assembly": "FundingPlatform.Workers.dll",
        "functions": {
            "AiExplanationProcessingFunction": "timerTrigger",
            "AlertDeliveryFunction": "timerTrigger",
            "AlertScheduleFunction": "timerTrigger",
            "BillingReconciliationFunction": "timerTrigger",
            "BillingWebhookProcessingFunction": "timerTrigger",
            "ContentRetentionFunction": "timerTrigger",
            "DefenderEventGridFunction": "httpTrigger",
            "DefenderScanWatchdogFunction": "timerTrigger",
            "HealthFunction": "httpTrigger",
            "ImportOutboxDispatcherFunction": "timerTrigger",
            "ImportQueueFunction": "queueTrigger",
            "ImportSchedulerFunction": "timerTrigger",
            "SemanticProcessingFunction": "timerTrigger",
            "SourceDocumentContentRetentionFunction": "timerTrigger",
        },
    },
    {
        "key": "extraction-workers",
        "project": (
            "src/FundingPlatform.ExtractionWorkers/"
            "FundingPlatform.ExtractionWorkers.csproj"
        ),
        "assembly": "FundingPlatform.ExtractionWorkers.dll",
        "functions": {
            "SourceDocumentExtractionQueueFunction": "queueTrigger",
            "SourceDocumentExtractionWatchdogFunction": "timerTrigger",
        },
    },
)


def repository_root() -> Path:
    return Path(__file__).resolve().parents[2]


def sha256_bytes(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path, description: str):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise PackagingError(f"{description} is not valid UTF-8 JSON") from error


def validate_source_revision(value: str) -> str:
    if not SOURCE_REVISION_PATTERN.fullmatch(value):
        raise PackagingError("source revision must be exactly 40 lowercase hexadecimal characters")
    return value


def resolve_dotnet(root: Path, explicit: str | None) -> str:
    if explicit:
        candidate = Path(explicit).expanduser()
        if not candidate.is_absolute():
            candidate = (Path.cwd() / candidate).resolve()
        if not candidate.is_file() or not os.access(candidate, os.X_OK):
            raise PackagingError("the explicit dotnet executable is unavailable")
        return str(candidate)

    repository_sdk = root / ".dotnet" / "dotnet"
    if repository_sdk.is_file() and os.access(repository_sdk, os.X_OK):
        return str(repository_sdk)
    executable = shutil.which("dotnet")
    if executable:
        return executable
    raise PackagingError("dotnet was not found on PATH or in the repository SDK directory")


def ensure_empty_output_directory(path: Path, root: Path) -> Path:
    resolved = path.expanduser().resolve()
    forbidden_targets = {Path("/").resolve(), root.resolve(), root.parent.resolve()}
    if resolved in forbidden_targets:
        raise PackagingError("refusing to use a broad output directory")
    if resolved.exists() and (not resolved.is_dir() or any(resolved.iterdir())):
        raise PackagingError("output directory must be absent or empty")
    resolved.mkdir(parents=True, exist_ok=True)
    return resolved


def publish_project(dotnet: str, root: Path, spec: dict, output: Path) -> None:
    command = [
        dotnet,
        "publish",
        spec["project"],
        "--configuration",
        "Release",
        "--no-restore",
        "--output",
        str(output),
        "--disable-build-servers",
        "-p:UseAppHost=false",
        "-p:ContinuousIntegrationBuild=true",
        "-p:DebugSymbols=false",
        "-p:DebugType=None",
    ]
    environment = os.environ.copy()
    environment.update(
        {
            "DOTNET_CLI_DO_NOT_USE_MSBUILD_SERVER": "1",
            "DOTNET_CLI_TELEMETRY_OPTOUT": "1",
            "DOTNET_NOLOGO": "1",
            "DOTNET_SKIP_FIRST_TIME_EXPERIENCE": "1",
        }
    )
    subprocess.run(command, cwd=root, env=environment, check=True)


def relative_files(directory: Path) -> list[tuple[PurePosixPath, Path]]:
    result: list[tuple[PurePosixPath, Path]] = []
    for path in sorted(directory.rglob("*"), key=lambda item: item.as_posix()):
        if path.is_symlink():
            raise PackagingError("published output must not contain symbolic links")
        if path.is_file():
            relative = PurePosixPath(path.relative_to(directory).as_posix())
            if relative.is_absolute() or ".." in relative.parts:
                raise PackagingError("published output contains an unsafe path")
            result.append((relative, path))
    if not result:
        raise PackagingError("dotnet publish produced no files")
    return result


def sensitive_path_reason(relative: PurePosixPath) -> str | None:
    name = relative.name.lower()
    if name in {
        "local.settings.json",
        "local.settings.example.json",
        "secrets.json",
        "appsettings.development.json",
        "appsettings.local.json",
    }:
        return "local or development configuration"
    if name == ".env" or name.startswith(".env."):
        return "environment file"
    if relative.suffix.lower() in {".pfx", ".p12", ".pem", ".key", ".user"}:
        return "credential-bearing file type"
    if relative.suffix.lower() in {".cs", ".csproj", ".sln", ".map"}:
        return "source or source-map file"
    return None


def validate_trigger_contract(spec: dict, function: dict) -> None:
    function_name = function.get("name")
    bindings = function.get("bindings")
    if not isinstance(bindings, list) or not bindings:
        raise PackagingError(f"{function_name} has no generated bindings")
    input_triggers = [
        binding
        for binding in bindings
        if isinstance(binding, dict)
        and str(binding.get("direction", "")).lower() == "in"
        and str(binding.get("type", "")).endswith("Trigger")
    ]
    if len(input_triggers) != 1:
        raise PackagingError(f"{function_name} must expose exactly one input trigger")
    trigger = input_triggers[0]
    expected_type = spec["functions"][function_name]
    if trigger.get("type") != expected_type:
        raise PackagingError(f"{function_name} generated an unexpected trigger type")

    expected_values = {
        "HealthFunction": {
            "authLevel": "Anonymous",
            "methods": ["get"],
            "route": "health",
        },
        "DefenderEventGridFunction": {
            "authLevel": "Anonymous",
            "methods": ["post"],
            "route": "webhooks/defender-storage",
        },
        "ImportQueueFunction": {
            "connection": "AzureWebJobsStorage",
            "queueName": "imports",
        },
        "SourceDocumentExtractionQueueFunction": {
            "connection": "DocumentExtractionQueueStorage",
            "queueName": "document-extractions",
        },
    }.get(function_name, {})
    for key, expected in expected_values.items():
        if trigger.get(key) != expected:
            raise PackagingError(f"{function_name} generated an unexpected {key}")


def validate_published_output(root: Path, spec: dict, directory: Path) -> list[tuple[PurePosixPath, Path]]:
    files = relative_files(directory)
    paths = {relative.as_posix(): path for relative, path in files}
    assembly = spec["assembly"]
    required = {
        "extensions.json",
        "functions.metadata",
        "host.json",
        "worker.config.json",
        assembly,
        assembly.removesuffix(".dll") + ".deps.json",
        assembly.removesuffix(".dll") + ".runtimeconfig.json",
        ".azurefunctions/Microsoft.Azure.Functions.Worker.Extensions.dll",
    }
    missing = sorted(required - paths.keys())
    if missing:
        raise PackagingError(f"{spec['key']} is missing required publish files: {', '.join(missing)}")

    for relative, _ in files:
        reason = sensitive_path_reason(relative)
        if reason:
            raise PackagingError(f"{spec['key']} contains {reason}: {relative.as_posix()}")

    source_host = root / Path(spec["project"]).parent / "host.json"
    if sha256_file(source_host) != sha256_file(paths["host.json"]):
        raise PackagingError(f"{spec['key']} does not contain its exact governed host.json")
    host = load_json(paths["host.json"], f"{spec['key']} host.json")
    if host.get("version") != "2.0":
        raise PackagingError(f"{spec['key']} host.json must target Functions host version 2.0")

    worker = load_json(paths["worker.config.json"], f"{spec['key']} worker.config.json")
    description = worker.get("description") if isinstance(worker, dict) else None
    if not isinstance(description, dict) or any(
        (
            description.get("language") != "dotnet-isolated",
            description.get("defaultExecutablePath") != "dotnet",
            description.get("defaultWorkerPath") != assembly,
        )
    ):
        raise PackagingError(f"{spec['key']} generated an invalid isolated worker configuration")

    runtime = load_json(
        paths[assembly.removesuffix(".dll") + ".runtimeconfig.json"],
        f"{spec['key']} runtimeconfig",
    )
    runtime_options = runtime.get("runtimeOptions") if isinstance(runtime, dict) else None
    if not isinstance(runtime_options, dict) or runtime_options.get("tfm") != "net10.0":
        raise PackagingError(f"{spec['key']} did not publish for net10.0")
    load_json(paths[assembly.removesuffix(".dll") + ".deps.json"], f"{spec['key']} deps.json")

    metadata = load_json(paths["functions.metadata"], f"{spec['key']} functions.metadata")
    if not isinstance(metadata, list) or not all(isinstance(item, dict) for item in metadata):
        raise PackagingError(f"{spec['key']} generated invalid function metadata")
    names = [item.get("name") for item in metadata]
    if len(names) != len(set(names)) or set(names) != set(spec["functions"]):
        raise PackagingError(f"{spec['key']} generated an unexpected function set")
    for function in metadata:
        if function.get("scriptFile") != assembly or function.get("language") != "dotnet-isolated":
            raise PackagingError(f"{function.get('name')} does not target the expected worker assembly")
        entry_point = function.get("entryPoint")
        expected_namespace = assembly.removesuffix(".dll") + ".Functions."
        if not isinstance(entry_point, str) or not entry_point.startswith(expected_namespace):
            raise PackagingError(f"{function.get('name')} generated an unexpected entry point")
        validate_trigger_contract(spec, function)

    extensions = load_json(paths["extensions.json"], f"{spec['key']} extensions.json")
    extension_items = extensions.get("extensions") if isinstance(extensions, dict) else None
    if not isinstance(extension_items, list) or not extension_items:
        raise PackagingError(f"{spec['key']} generated no host extensions")
    for extension in extension_items:
        hint = extension.get("hintPath") if isinstance(extension, dict) else None
        if not isinstance(hint, str) or not hint.startswith("./") or hint[2:] not in paths:
            raise PackagingError(f"{spec['key']} generated an unresolved extension hint")

    # Portable PDBs are useful during local builds but are deliberately omitted from deployment.
    return [(relative, path) for relative, path in files if relative.suffix.lower() != ".pdb"]


def create_deterministic_zip(files: list[tuple[PurePosixPath, Path]], archive: Path) -> list[dict]:
    manifest_files: list[dict] = []
    with zipfile.ZipFile(archive, mode="w", compression=zipfile.ZIP_STORED, allowZip64=True) as bundle:
        for relative, path in sorted(files, key=lambda item: item[0].as_posix()):
            content = path.read_bytes()
            info = zipfile.ZipInfo(relative.as_posix(), date_time=FIXED_ZIP_TIMESTAMP)
            info.create_system = 3
            info.compress_type = zipfile.ZIP_STORED
            info.external_attr = FIXED_FILE_MODE
            bundle.writestr(info, content)
            manifest_files.append(
                {
                    "path": relative.as_posix(),
                    "sha256": sha256_bytes(content),
                    "size": len(content),
                }
            )
    if archive.stat().st_size > MAX_ARCHIVE_BYTES:
        raise PackagingError(f"{archive.name} exceeds the bounded package size")
    return manifest_files


def write_manifest(path: Path, spec: dict, revision: str, archive: Path, files: list[dict]) -> None:
    document = {
        "application": spec["key"],
        "archive": archive.name,
        "archiveBytes": archive.stat().st_size,
        "archiveFormat": "zip-stored-fixed-metadata-v1",
        "archiveSha256": sha256_file(archive),
        "assembly": spec["assembly"],
        "fileCount": len(files),
        "files": files,
        "functions": sorted(spec["functions"]),
        "project": spec["project"],
        "schemaVersion": 1,
        "sourceRevision": revision,
        "targetFramework": "net10.0",
    }
    path.write_text(
        json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def artifact_names() -> set[str]:
    names = {"SHA256SUMS"}
    for spec in PROJECTS:
        names.add(f"{spec['key']}.zip")
        names.add(f"{spec['key']}.manifest.json")
    return names


def write_checksums(directory: Path) -> None:
    targets = sorted(path for path in directory.iterdir() if path.name != "SHA256SUMS")
    lines = [f"{sha256_file(path)}  {path.name}" for path in targets if path.is_file()]
    (directory / "SHA256SUMS").write_text("\n".join(lines) + "\n", encoding="ascii")


def parse_checksums(directory: Path) -> dict[str, str]:
    checksum_path = directory / "SHA256SUMS"
    try:
        lines = checksum_path.read_text(encoding="ascii").splitlines()
    except (OSError, UnicodeDecodeError) as error:
        raise PackagingError("SHA256SUMS is unavailable or invalid") from error
    result: dict[str, str] = {}
    for line in lines:
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9._-]+)", line)
        if not match or match.group(2) in result:
            raise PackagingError("SHA256SUMS has an invalid or duplicate entry")
        result[match.group(2)] = match.group(1)
    return result


def safe_zip_names(bundle: zipfile.ZipFile) -> list[str]:
    names = bundle.namelist()
    if len(names) != len(set(names)):
        raise PackagingError("archive contains duplicate paths")
    for info in bundle.infolist():
        path = PurePosixPath(info.filename)
        if path.is_absolute() or ".." in path.parts or info.is_dir():
            raise PackagingError("archive contains an unsafe or unexpected path")
        if info.date_time != FIXED_ZIP_TIMESTAMP or info.compress_type != zipfile.ZIP_STORED:
            raise PackagingError("archive metadata is not deterministic")
        if info.external_attr != FIXED_FILE_MODE:
            raise PackagingError("archive file mode is not deterministic")
        if sensitive_path_reason(path) or path.suffix.lower() == ".pdb":
            raise PackagingError("archive contains a forbidden deployment file")
    return names


def verify_artifacts(directory: Path, expected_revision: str) -> None:
    if not directory.is_dir():
        raise PackagingError("artifact directory does not exist")
    actual_names = {path.name for path in directory.iterdir() if path.is_file()}
    if actual_names != artifact_names() or any(path.is_dir() for path in directory.iterdir()):
        raise PackagingError("artifact directory contains a missing or unexpected entry")

    checksums = parse_checksums(directory)
    expected_checksum_names = artifact_names() - {"SHA256SUMS"}
    if set(checksums) != expected_checksum_names:
        raise PackagingError("SHA256SUMS does not cover the exact artifact set")
    for name, expected_hash in checksums.items():
        if sha256_file(directory / name) != expected_hash:
            raise PackagingError(f"checksum verification failed for {name}")

    root = repository_root()
    with tempfile.TemporaryDirectory(prefix="rf-functions-verify-") as temporary:
        temporary_root = Path(temporary)
        for spec in PROJECTS:
            archive = directory / f"{spec['key']}.zip"
            manifest_path = directory / f"{spec['key']}.manifest.json"
            manifest = load_json(manifest_path, f"{spec['key']} manifest")
            if not isinstance(manifest, dict) or any(
                (
                    manifest.get("schemaVersion") != 1,
                    manifest.get("sourceRevision") != expected_revision,
                    manifest.get("archive") != archive.name,
                    manifest.get("archiveSha256") != sha256_file(archive),
                    manifest.get("archiveBytes") != archive.stat().st_size,
                    manifest.get("application") != spec["key"],
                    manifest.get("assembly") != spec["assembly"],
                    manifest.get("project") != spec["project"],
                    manifest.get("targetFramework") != "net10.0",
                    manifest.get("functions") != sorted(spec["functions"]),
                )
            ):
                raise PackagingError(f"{spec['key']} manifest contract is invalid")

            extract_directory = temporary_root / spec["key"]
            extract_directory.mkdir()
            with zipfile.ZipFile(archive, mode="r") as bundle:
                names = safe_zip_names(bundle)
                if bundle.testzip() is not None:
                    raise PackagingError(f"{archive.name} failed its ZIP integrity check")
                bundle.extractall(extract_directory)

            manifest_files = manifest.get("files")
            if not isinstance(manifest_files, list) or manifest.get("fileCount") != len(manifest_files):
                raise PackagingError(f"{spec['key']} manifest file inventory is invalid")
            inventory = {
                item.get("path"): item
                for item in manifest_files
                if isinstance(item, dict) and isinstance(item.get("path"), str)
            }
            if len(inventory) != len(manifest_files) or set(inventory) != set(names):
                raise PackagingError(f"{spec['key']} manifest does not match its archive")
            for name, item in inventory.items():
                content = (extract_directory / PurePosixPath(name)).read_bytes()
                if item.get("size") != len(content) or item.get("sha256") != sha256_bytes(content):
                    raise PackagingError(f"{spec['key']} file inventory check failed for {name}")
            validate_published_output(root, spec, extract_directory)


def build_artifacts(output: Path, revision: str, dotnet: str) -> None:
    root = repository_root()
    output = ensure_empty_output_directory(output, root)
    with tempfile.TemporaryDirectory(prefix="rf-functions-build-") as temporary:
        temporary_root = Path(temporary)
        artifact_stage = temporary_root / "artifacts"
        artifact_stage.mkdir()
        for spec in PROJECTS:
            publish_directory = temporary_root / f"publish-{spec['key']}"
            publish_project(dotnet, root, spec, publish_directory)
            files = validate_published_output(root, spec, publish_directory)
            archive = artifact_stage / f"{spec['key']}.zip"
            inventory = create_deterministic_zip(files, archive)
            write_manifest(
                artifact_stage / f"{spec['key']}.manifest.json",
                spec,
                revision,
                archive,
                inventory,
            )
        write_checksums(artifact_stage)
        verify_artifacts(artifact_stage, revision)
        for path in sorted(artifact_stage.iterdir(), key=lambda item: item.name):
            shutil.copyfile(path, output / path.name)
    verify_artifacts(output, revision)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    build = subparsers.add_parser("build", help="publish, validate and package both worker apps")
    build.add_argument("--output-directory", required=True, type=Path)
    build.add_argument("--source-revision", required=True)
    build.add_argument("--dotnet")
    verify = subparsers.add_parser("verify", help="independently verify a packaged artifact set")
    verify.add_argument("--artifact-directory", required=True, type=Path)
    verify.add_argument("--source-revision", required=True)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        revision = validate_source_revision(arguments.source_revision)
        if arguments.command == "build":
            root = repository_root()
            dotnet = resolve_dotnet(root, arguments.dotnet)
            build_artifacts(arguments.output_directory, revision, dotnet)
            print(f"Worker packages built and verified for {revision}.")
        else:
            verify_artifacts(arguments.artifact_directory.resolve(), revision)
            print(f"Worker packages verified for {revision}.")
        return 0
    except (PackagingError, OSError, subprocess.CalledProcessError) as error:
        print(f"Worker packaging failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
