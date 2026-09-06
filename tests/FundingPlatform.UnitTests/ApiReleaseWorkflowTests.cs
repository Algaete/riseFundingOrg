using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using FundingPlatform.Infrastructure.Persistence.Migrations;

namespace FundingPlatform.UnitTests;

public sealed class ApiReleaseWorkflowTests
{
    private const string ReleaseSha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    private const string SubscriptionId = "11111111-1111-1111-1111-111111111111";
    private const string TenantId = "22222222-2222-2222-2222-222222222222";
    private const string ClientId = "33333333-3333-3333-3333-333333333333";
    private const string PrincipalId = "44444444-4444-4444-4444-444444444444";
    private const string ResourceGroup = "rg-rf-dev-abcdefgh";
    private const string ApiName = "ca-rf-dev-abcdefgh-api";
    private const string RegistryName = "crrfdevabcdefghaaaaaaaaaaaaa";
    private const string Digest = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    private const string ResourceGroupId = $"/subscriptions/{SubscriptionId}/resourceGroups/{ResourceGroup}";
    private const string IdentityName = "id-rf-dev-abcdefgh-api";
    private const string IdentityId = $"{ResourceGroupId}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{IdentityName}";

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task The_Azure_CLI_bootstrap_makes_git_available_before_invoking_the_release(
        bool gitInitiallyPresent)
    {
        if (OperatingSystem.IsWindows())
            throw new PlatformNotSupportedException("The API release workflow requires Bash.");

        var sourceRoot = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var workflow = File.ReadAllLines(Path.Combine(sourceRoot, ".github", "workflows", "api-dev.yml"));
        var marker = Array.FindIndex(workflow, line => line.Trim() == "inlineScript: |");
        Assert.True(marker >= 0, "The Azure CLI release step must expose its bootstrap script.");
        var markerIndent = workflow[marker].TakeWhile(char.IsWhiteSpace).Count();
        var body = workflow.Skip(marker + 1)
            .TakeWhile(line => string.IsNullOrWhiteSpace(line) ||
                line.TakeWhile(char.IsWhiteSpace).Count() > markerIndent).ToArray();
        var bodyIndent = body.Where(line => !string.IsNullOrWhiteSpace(line))
            .Min(line => line.TakeWhile(char.IsWhiteSpace).Count());
        var inlineScript = string.Join('\n', body.Select(line =>
            string.IsNullOrWhiteSpace(line) ? "" : line[bodyIndent..]));

        var stubRoot = Path.Combine(Path.GetTempPath(), $"funding-api-bootstrap-{Guid.NewGuid():N}");
        Directory.CreateDirectory(stubRoot);
        try
        {
            var bin = Directory.CreateDirectory(Path.Combine(stubRoot, "bin")).FullName;
            var scripts = Directory.CreateDirectory(Path.Combine(stubRoot, "infra", "scripts")).FullName;
            File.CreateSymbolicLink(Path.Combine(bin, "bash"), "/bin/bash");
            if (gitInitiallyPresent)
                WriteExecutable(Path.Combine(bin, "git"), "#!/bin/bash\nexit 0\n");
            WriteExecutable(Path.Combine(bin, "tdnf"), """
                #!/bin/bash
                set -euo pipefail
                printf '%s\n' "$*" >> "$STUB_REPO_ROOT/events"
                printf '#!/bin/bash\nexit 0\n' > "$STUB_REPO_ROOT/bin/git"
                /bin/chmod u+x "$STUB_REPO_ROOT/bin/git"
                """);
            WriteExecutable(Path.Combine(scripts, "deploy-api-dev.sh"), """
                #!/bin/bash
                set -euo pipefail
                command -v git >/dev/null
                printf 'deploy\n' >> "$STUB_REPO_ROOT/events"
                """);
            var startInfo = new ProcessStartInfo
            {
                FileName = "/bin/bash", WorkingDirectory = stubRoot,
                RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false
            };
            startInfo.ArgumentList.Add("-c");
            startInfo.ArgumentList.Add(inlineScript);
            // The isolated PATH intentionally models the Azure CLI image without
            // Git. Its package-manager double cannot install or contact anything.
            startInfo.Environment["PATH"] = bin;
            startInfo.Environment["STUB_REPO_ROOT"] = stubRoot;
            using var process = Process.Start(startInfo) ??
                throw new InvalidOperationException("Could not start the isolated release bootstrap.");
            var stdout = process.StandardOutput.ReadToEndAsync();
            var stderr = process.StandardError.ReadToEndAsync();
            try
            {
                await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5));
            }
            catch (TimeoutException)
            {
                process.Kill(entireProcessTree: true);
                throw new TimeoutException("The isolated release bootstrap exceeded five seconds.");
            }

            Assert.True(process.ExitCode == 0, await stderr);
            await stdout;
            Assert.Equal(gitInitiallyPresent ? ["deploy"] : new[] { "install -y git", "deploy" },
                File.ReadAllLines(Path.Combine(stubRoot, "events")));
        }
        finally
        {
            Directory.Delete(stubRoot, recursive: true);
        }
    }

    [Theory]
    [InlineData("AZURE_API_DEPLOY_CONFIRMATION", "")]
    [InlineData("GITHUB_SHA", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")]
    [InlineData("EXPECTED_RELEASE_SHA", "main")]
    [InlineData("GITHUB_REF", "refs/heads/feature")]
    [InlineData("AZURE_UNIQUE_SUFFIX", "production")]
    [InlineData("STUB_GIT_STATUS", " M src/FundingPlatform.Api/Program.cs")]
    public void Unapproved_or_ambiguous_releases_stop_before_contacting_Azure(
        string setting, string value)
    {
        var result = RunRelease(new Dictionary<string, string> { [setting] = value });

        Assert.NotEqual(0, result.ExitCode);
        Assert.Empty(result.AzureCommands);
        Assert.False(result.EnvironmentVerified);
    }

    [Fact]
    public void A_different_authenticated_subscription_cannot_build_or_deploy()
    {
        var result = RunRelease(new Dictionary<string, string>
        {
            ["STUB_SUBSCRIPTION_ID"] = "99999999-9999-9999-9999-999999999999"
        });

        Assert.Equal(3, result.ExitCode);
        Assert.Contains("different subscription or tenant", result.StandardError,
            StringComparison.Ordinal);
        Assert.All(result.AzureCommands, command =>
            Assert.Equal(new[] { "account", "show" }, command.Take(2)));
        Assert.False(result.EnvironmentVerified);
    }

    [Fact]
    public void An_API_outside_the_reviewed_identity_boundary_cannot_build_or_deploy()
    {
        var result = RunRelease(invalidApiIdentity: true);

        Assert.Equal(3, result.ExitCode);
        Assert.Empty(Mutations(result));
        Assert.False(result.EnvironmentVerified);
    }

    [Fact]
    public void Configuration_drift_during_the_build_stops_the_API_update()
    {
        var result = RunRelease(new Dictionary<string, string> { ["STUB_API_DRIFT"] = "true" });

        Assert.Equal(5, result.ExitCode);
        Assert.Contains("changed during the image build", result.StandardError,
            StringComparison.Ordinal);
        var mutation = Assert.Single(Mutations(result));
        Assert.Equal(new[] { "acr", "build" }, mutation.Take(2));
        Assert.False(result.EnvironmentVerified);
    }

    [Fact]
    public void A_reviewed_release_updates_only_the_existing_API_and_exact_telemetry_settings()
    {
        var result = RunRelease();

        Assert.True(result.ExitCode == 0, result.StandardError);
        var mutations = Mutations(result);
        Assert.Equal(2, mutations.Count);
        var build = mutations[0];
        Assert.Equal(new[] { "acr", "build" }, build.Take(2));
        Assert.Equal(RegistryName, Argument(build, "--registry"));
        Assert.Equal(ResourceGroup, Argument(build, "--resource-group"));
        Assert.Equal($"rise-funding-api:{ReleaseSha}", Argument(build, "--image"));
        Assert.Equal("src/FundingPlatform.Api/Dockerfile", Argument(build, "--file"));
        Assert.Equal("linux/amd64", Argument(build, "--platform"));

        var update = mutations[1];
        Assert.Equal(new[] { "containerapp", "update" }, update.Take(2));
        Assert.Equal(ResourceGroup, Argument(update, "--resource-group"));
        Assert.Equal(ApiName, Argument(update, "--name"));
        Assert.Equal("api", Argument(update, "--container-name"));
        Assert.Equal($"{RegistryName}.azurecr.io/rise-funding-api@{Digest}",
            Argument(update, "--image"));
        Assert.Equal(
            new[]
            {
                "OTEL_SERVICE_NAME=FundingPlatform.Api",
                "OTEL_DOTNET_EXPERIMENTAL_ASPNETCORE_DISABLE_URL_QUERY_REDACTION=false",
                "OTEL_DOTNET_EXPERIMENTAL_HTTPCLIENT_DISABLE_URL_QUERY_REDACTION=false"
            },
            update.Skip(Array.IndexOf(update, "--set-env-vars") + 1)
                .TakeWhile(argument => !argument.StartsWith("--", StringComparison.Ordinal)));
        Assert.DoesNotContain("--replace-env-vars", update);
        Assert.All(update.Where(argument => argument.StartsWith("--", StringComparison.Ordinal)),
            option => Assert.Contains(option, new[]
            {
                "--resource-group", "--name", "--container-name", "--image",
                "--set-env-vars", "--output", "--only-show-errors"
            }));
        Assert.True(result.EnvironmentVerified);
        Assert.Contains("API-only deployment and existing-environment verification completed",
            result.StandardOutput, StringComparison.Ordinal);
        Assert.DoesNotContain("fixture-private-connection", result.StandardOutput,
            StringComparison.Ordinal);
    }

    private static IReadOnlyList<string[]> Mutations(ProcessResult result) =>
        result.AzureCommands.Where(command =>
            !ReadOnlyCommands.Any(prefix => command.Take(prefix.Length).SequenceEqual(prefix)))
            .ToArray();

    private static readonly string[][] ReadOnlyCommands =
    [
        ["account", "show"], ["group", "show"], ["identity", "show"],
        ["acr", "list"], ["acr", "manifest", "show-metadata"], ["resource", "show"]
    ];

    private static string Argument(string[] command, string option)
    {
        var index = Array.IndexOf(command, option);
        Assert.True(index >= 0 && index + 1 < command.Length, $"Missing argument {option}");
        return command[index + 1];
    }

    private static ProcessResult RunRelease(
        IReadOnlyDictionary<string, string>? overrides = null,
        bool invalidApiIdentity = false)
    {
        if (OperatingSystem.IsWindows())
            throw new PlatformNotSupportedException("The API release workflow requires Bash.");

        var sourceRoot = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var stubRoot = Path.Combine(Path.GetTempPath(), $"funding-api-release-{Guid.NewGuid():N}");
        Directory.CreateDirectory(stubRoot);
        try
        {
            var scriptsDirectory = Directory.CreateDirectory(Path.Combine(stubRoot, "infra", "scripts"));
            var apiDirectory = Directory.CreateDirectory(Path.Combine(stubRoot, "src", "FundingPlatform.Api"));
            var binDirectory = Directory.CreateDirectory(Path.Combine(stubRoot, "bin"));
            var releasePath = Path.Combine(scriptsDirectory.FullName, "deploy-api-dev.sh");
            File.Copy(Path.Combine(sourceRoot, "infra", "scripts", "deploy-api-dev.sh"), releasePath);
            File.WriteAllText(Path.Combine(apiDirectory.FullName, "Dockerfile"), "# Isolated build-context fixture\n");
            File.WriteAllText(Path.Combine(stubRoot, ".dockerignore"), "bin\n");
            // The existing environment verifier has its own scope. This boundary
            // double checks that the release invokes it with the preserved scale.
            File.WriteAllText(Path.Combine(scriptsDirectory.FullName, "verify-dev.sh"), """
                #!/usr/bin/env bash
                set -euo pipefail
                [[ "$#" == 1 && "$1" == api && "$AZURE_API_MIN_REPLICAS" == 0 ]]
                printf 'verified\n' > "$STUB_REPO_ROOT/verified"
                """);
            WriteExecutable(Path.Combine(binDirectory.FullName, "git"), """
                #!/usr/bin/env bash
                set -euo pipefail
                if [[ "${1:-}" == -c ]]; then shift 2; fi
                case "$*" in
                  'rev-parse --show-toplevel') printf '%s\n' "$STUB_REPO_ROOT" ;;
                  'rev-parse HEAD') printf '%s\n' "$STUB_GIT_SHA" ;;
                  'status --porcelain --untracked-files=normal') printf '%s' "${STUB_GIT_STATUS:-}" ;;
                  *) printf 'Unexpected git command\n' >&2; exit 98 ;;
                esac
                """);
            WriteExecutable(Path.Combine(binDirectory.FullName, "az"), AzureStub);
            WriteAzureFixtures(stubRoot, invalidApiIdentity);

            var startInfo = new ProcessStartInfo
            {
                FileName = "/bin/bash",
                WorkingDirectory = stubRoot,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            };
            startInfo.ArgumentList.Add(releasePath);
            startInfo.Environment["PATH"] = $"{binDirectory.FullName}:{Environment.GetEnvironmentVariable("PATH")}";
            startInfo.Environment["AZURE_SUBSCRIPTION_ID"] = SubscriptionId;
            startInfo.Environment["AZURE_TENANT_ID"] = TenantId;
            startInfo.Environment["AZURE_UNIQUE_SUFFIX"] = "abcdefgh";
            startInfo.Environment["AZURE_SQL_LOCATION"] = "centralus";
            startInfo.Environment["EXPECTED_RELEASE_SHA"] = ReleaseSha;
            startInfo.Environment["GITHUB_SHA"] = ReleaseSha;
            startInfo.Environment["GITHUB_REF"] = "refs/heads/main";
            startInfo.Environment["AZURE_API_DEPLOY_CONFIRMATION"] = "DEPLOY-DEV-API";
            startInfo.Environment["STUB_REPO_ROOT"] = stubRoot;
            startInfo.Environment["STUB_GIT_SHA"] = ReleaseSha;
            startInfo.Environment["STUB_IMAGE_DIGEST"] = Digest;
            startInfo.Environment.Remove("GITHUB_STEP_SUMMARY");
            foreach (var pair in overrides ?? new Dictionary<string, string>())
                startInfo.Environment[pair.Key] = pair.Value;

            using var process = Process.Start(startInfo) ??
                throw new InvalidOperationException("Could not start the isolated API release.");
            var stdout = process.StandardOutput.ReadToEndAsync();
            var stderr = process.StandardError.ReadToEndAsync();
            if (!process.WaitForExit(20_000))
            {
                process.Kill(entireProcessTree: true);
                throw new TimeoutException("The isolated API release exceeded 20 seconds.");
            }

            var commandLog = Path.Combine(stubRoot, "azure-commands.jsonl");
            return new ProcessResult(process.ExitCode,
                stdout.GetAwaiter().GetResult(), stderr.GetAwaiter().GetResult(),
                File.Exists(commandLog)
                    ? File.ReadAllLines(commandLog).Select(line => JsonSerializer.Deserialize<string[]>(line)!).ToArray()
                    : [],
                File.Exists(Path.Combine(stubRoot, "verified")));
        }
        finally
        {
            Directory.Delete(stubRoot, recursive: true);
        }
    }

    private static void WriteAzureFixtures(string directory, bool invalidApiIdentity)
    {
        var tags = new Dictionary<string, string>
        {
            ["application"] = "rise-funding-org", ["environment"] = "dev",
            ["managedBy"] = "bicep", ["dataClassification"] = "confidential"
        };
        WriteJson("group.json", new
        {
            id = ResourceGroupId, name = ResourceGroup, tags,
            properties = new { provisioningState = "Succeeded" }
        });
        WriteJson("identity.json", new
        {
            id = IdentityId, name = IdentityName, type = "Microsoft.ManagedIdentity/userAssignedIdentities",
            tenantId = TenantId, clientId = ClientId, principalId = PrincipalId, tags
        });
        WriteJson("registries.json", new[]
        {
            new
            {
                id = $"{ResourceGroupId}/providers/Microsoft.ContainerRegistry/registries/{RegistryName}",
                name = RegistryName,
                loginServer = $"{RegistryName}.azurecr.io", provisioningState = "Succeeded",
                sku = new { name = "Basic" }, adminUserEnabled = false, anonymousPullEnabled = false,
                tags = new Dictionary<string, string>(tags) { ["boundary"] = "private-container-images" }
            }
        });
        var api = JsonSerializer.SerializeToNode(new
        {
            id = $"{ResourceGroupId}/providers/Microsoft.App/containerapps/{ApiName}",
            name = ApiName, type = "Microsoft.App/containerApps", location = "eastus", tags,
            identity = new
            {
                type = "UserAssigned",
                userAssignedIdentities = new Dictionary<string, object>
                {
                    [IdentityId.Replace("resourceGroups", "resourcegroups", StringComparison.Ordinal)] =
                        new { clientId = ClientId, principalId = PrincipalId }
                }
            },
            properties = new
            {
                managedEnvironmentId = $"{ResourceGroupId}/providers/Microsoft.App/managedEnvironments/cae-rf-dev-abcdefgh",
                provisioningState = "Succeeded", latestRevisionName = $"{ApiName}--old",
                latestReadyRevisionName = $"{ApiName}--old",
                configuration = new
                {
                    activeRevisionsMode = "Single",
                    ingress = new
                    {
                        external = true, allowInsecure = false, targetPort = 8080,
                        fqdn = $"{ApiName}.fixture.azurecontainerapps.io",
                        traffic = new[] { new { latestRevision = true, weight = 100 } }
                    },
                    registries = new[] { new { server = $"{RegistryName}.azurecr.io", identity = IdentityId } }
                },
                template = new
                {
                    revisionSuffix = "old", scale = new { minReplicas = 0, maxReplicas = 1 },
                    containers = new[]
                    {
                        new
                        {
                            name = "api", image = $"{RegistryName}.azurecr.io/rise-funding-api@sha256:{new string('a', 64)}",
                            resources = new { cpu = 0.25, memory = "0.5Gi" },
                            env = new[]
                            {
                                new { name = "ASPNETCORE_ENVIRONMENT", value = "Production" },
                                new { name = "AZURE_CLIENT_ID", value = invalidApiIdentity ? TenantId : ClientId },
                                new { name = "APPLICATIONINSIGHTS_CONNECTION_STRING", value = "fixture-private-connection" },
                                new { name = "APPLICATIONINSIGHTS_AUTHENTICATION_STRING", value = $"ClientId={ClientId};Authorization=AAD" },
                                new { name = "UNRELATED_SETTING", value = "preserve-me" }
                            }
                        }
                    }
                }
            }
        })!;
        WriteJson("api-before.json", api);
        var drifted = api.DeepClone();
        drifted["properties"]!["template"]!["containers"]![0]!["env"]![4]!["value"] = "externally-changed";
        WriteJson("api-drifted.json", drifted);
        var after = api.DeepClone();
        var properties = after["properties"]!;
        properties["latestRevisionName"] = $"{ApiName}--new";
        properties["latestReadyRevisionName"] = $"{ApiName}--new";
        properties["template"]!["revisionSuffix"] = "new";
        var container = properties["template"]!["containers"]![0]!;
        container["image"] = $"{RegistryName}.azurecr.io/rise-funding-api@{Digest}";
        var environment = container["env"]!.AsArray();
        environment.Add(new JsonObject { ["name"] = "OTEL_SERVICE_NAME", ["value"] = "FundingPlatform.Api" });
        environment.Add(new JsonObject { ["name"] = "OTEL_DOTNET_EXPERIMENTAL_ASPNETCORE_DISABLE_URL_QUERY_REDACTION", ["value"] = "false" });
        environment.Add(new JsonObject { ["name"] = "OTEL_DOTNET_EXPERIMENTAL_HTTPCLIENT_DISABLE_URL_QUERY_REDACTION", ["value"] = "false" });
        WriteJson("api-after.json", after);

        void WriteJson(string name, object value) =>
            File.WriteAllText(Path.Combine(directory, name), JsonSerializer.Serialize(value));
    }

    private static void WriteExecutable(string path, string content)
    {
        if (OperatingSystem.IsWindows())
            throw new PlatformNotSupportedException("The API release workflow requires Bash.");
        File.WriteAllText(path, content);
        File.SetUnixFileMode(path,
            UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
    }

    private const string AzureStub = """
        #!/usr/bin/env python3
        import json
        import os
        import pathlib
        import sys

        root = pathlib.Path(os.environ['STUB_REPO_ROOT'])
        args = sys.argv[1:]
        with (root / 'azure-commands.jsonl').open('a') as log:
            log.write(json.dumps(args) + '\n')

        def fixture(name):
            print((root / name).read_text())

        if args[:2] == ['account', 'show']:
            query = args[args.index('--query') + 1]
            if query == 'id':
                print(os.environ.get('STUB_SUBSCRIPTION_ID', os.environ['AZURE_SUBSCRIPTION_ID']))
            elif query == 'tenantId':
                print(os.environ['AZURE_TENANT_ID'])
            else:
                sys.exit(98)
        elif args[:2] == ['group', 'show']:
            fixture('group.json')
        elif args[:2] == ['identity', 'show']:
            fixture('identity.json')
        elif args[:2] == ['acr', 'list']:
            fixture('registries.json')
        elif args[:2] == ['resource', 'show']:
            if (root / 'updated').exists():
                fixture('api-after.json')
            elif os.environ.get('STUB_API_DRIFT') == 'true' and (root / 'built').exists():
                fixture('api-drifted.json')
            else:
                fixture('api-before.json')
        elif args[:2] == ['acr', 'build']:
            (root / 'built').touch()
        elif args[:3] == ['acr', 'manifest', 'show-metadata']:
            print(os.environ['STUB_IMAGE_DIGEST'])
        elif args[:2] == ['containerapp', 'update']:
            (root / 'updated').touch()
        else:
            print('Unexpected Azure command; stub refused it', file=sys.stderr)
            sys.exit(98)
        """;

    private sealed record ProcessResult(
        int ExitCode,
        string StandardOutput,
        string StandardError,
        IReadOnlyList<string[]> AzureCommands,
        bool EnvironmentVerified);
}
