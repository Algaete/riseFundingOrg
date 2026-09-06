using System.Diagnostics;
using FundingPlatform.Infrastructure.Persistence.Migrations;

namespace FundingPlatform.UnitTests;

public sealed class DatabaseRestoreRunbookTests
{
    [Fact]
    public void Dev_pitr_script_is_scoped_confirmed_compute_bounded_and_non_destructive()
    {
        var script = Read("infra", "scripts", "restore-database-dev.sh");

        Assert.Contains("set -euo pipefail", script, StringComparison.Ordinal);
        Assert.Contains("validate|execute", script, StringComparison.Ordinal);
        Assert.Contains("AZURE_SUBSCRIPTION_ID", script, StringComparison.Ordinal);
        Assert.Contains("AZURE_TENANT_ID", script, StringComparison.Ordinal);
        Assert.Contains("AZURE_UNIQUE_SUFFIX", script, StringComparison.Ordinal);
        Assert.Contains("source_database\" != \"risefunding-dev", script,
            StringComparison.Ordinal);
        Assert.Contains("risefunding-dev-restore-${AZURE_UNIQUE_SUFFIX}", script,
            StringComparison.Ordinal);
        Assert.Contains("earliestRestoreDate", script, StringComparison.Ordinal);
        Assert.Contains("to_string(maxSizeBytes)", script, StringComparison.Ordinal);
        Assert.Contains("MAX-STORAGE-BYTES ${source_max_size_bytes}", script,
            StringComparison.Ordinal);
        Assert.Contains("does not declare total storage cost bounded", script,
            StringComparison.Ordinal);
        Assert.Contains("destination_count", script, StringComparison.Ordinal);
        Assert.Contains("RESTORE-DEV-DATABASE SUBSCRIPTION ${AZURE_SUBSCRIPTION_ID} TENANT ${AZURE_TENANT_ID} SOURCE ${expected_source_id} TO ${expected_destination_id} AT ${restore_point_utc}",
            script, StringComparison.Ordinal);
        Assert.Contains("if [[ \"$mode\" == \"validate\" ]]", script,
            StringComparison.Ordinal);
        Assert.Contains("az sql db restore", script, StringComparison.Ordinal);
        Assert.Contains("--compute-model Serverless", script, StringComparison.Ordinal);
        Assert.Contains("--auto-pause-delay 60", script, StringComparison.Ordinal);
        Assert.Contains("--backup-storage-redundancy Local", script,
            StringComparison.Ordinal);
        Assert.DoesNotContain("--no-wait", script, StringComparison.Ordinal);
        Assert.DoesNotContain("--yes", script, StringComparison.Ordinal);

        var destinationCheck = script.IndexOf("destination_count=", StringComparison.Ordinal);
        var validationExit = script.IndexOf("if [[ \"$mode\" == \"validate\" ]]",
            StringComparison.Ordinal);
        var restore = script.IndexOf("az sql db restore", StringComparison.Ordinal);
        Assert.True(destinationCheck >= 0 && destinationCheck < validationExit);
        Assert.True(validationExit < restore);

        var readOnlyCommands = new[]
        {
            "az account show",
            "az group show",
            "az sql server list",
            "az sql server show",
            "az sql db show",
            "az sql db list"
        };
        var allAllowedCommands = readOnlyCommands.Append("az sql db restore").ToArray();
        Assert.All(AzureCommands(script[..validationExit]), command =>
            Assert.True(readOnlyCommands.Any(allowed =>
                    command.StartsWith(allowed, StringComparison.Ordinal)),
                $"Unexpected Azure command before the validate exit: {command}"));
        Assert.All(AzureCommands(script), command =>
            Assert.True(allAllowedCommands.Any(allowed =>
                    command.StartsWith(allowed, StringComparison.Ordinal)),
                $"Unexpected Azure command: {command}"));
        Assert.Single(AzureCommands(script), command =>
            command.StartsWith("az sql db restore", StringComparison.Ordinal));
    }

    [Fact]
    public void Runbook_keeps_restore_validation_promotion_and_cleanup_separate()
    {
        var runbook = Read("docs", "runbooks", "database-restore.md");

        Assert.Contains("base temporal nueva", runbook, StringComparison.Ordinal);
        Assert.Contains("El modo `validate` es el dry-run", runbook,
            StringComparison.Ordinal);
        Assert.Contains("elimina ninguna base", runbook, StringComparison.Ordinal);
        Assert.Contains("Sin apuntar la API pública a la base restaurada", runbook,
            StringComparison.Ordinal);
        Assert.Contains("No reconstruirla desde variables", runbook,
            StringComparison.Ordinal);
        Assert.Contains("operación destructiva separada", runbook,
            StringComparison.Ordinal);
        Assert.Contains("no automatiza esa eliminación", runbook,
            StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("2025-01-01T03:04:05Z")]
    [InlineData("2025-01-01T03:04:05.313314+00:00")]
    public void Validate_accepts_only_the_supported_Azure_SQL_UTC_shapes(
        string earliestRestoreDate)
    {
        var result = RunValidateWithStub(earliestRestoreDate);

        Assert.Equal(0, result.ExitCode);
        Assert.Contains("Validation complete. No restore command was sent", result.StandardOutput,
            StringComparison.Ordinal);
        Assert.Contains("source max storage: 34359738368 bytes", result.StandardOutput,
            StringComparison.Ordinal);
        Assert.Contains("MAX-STORAGE-BYTES 34359738368", result.StandardOutput,
            StringComparison.Ordinal);
        Assert.DoesNotContain("RESTORE COMMAND CALLED", result.StandardError,
            StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("2025-01-01T03:04:05+01:00")]
    [InlineData("2025-01-01T03:04:05-03:00")]
    [InlineData("2025-01-01T03:04:05")]
    public void Validate_rejects_non_UTC_offsets_and_missing_timezones(
        string earliestRestoreDate)
    {
        var result = RunValidateWithStub(earliestRestoreDate);

        Assert.Equal(3, result.ExitCode);
        Assert.Contains("only Z or +00:00 are accepted", result.StandardError,
            StringComparison.Ordinal);
        Assert.DoesNotContain("RESTORE COMMAND CALLED", result.StandardError,
            StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("0")]
    [InlineData("unbounded")]
    public void Validate_rejects_an_unusable_source_storage_cap(string maxSizeBytes)
    {
        var result = RunValidateWithStub(
            "2025-01-01T03:04:05Z",
            maxSizeBytes);

        Assert.Equal(3, result.ExitCode);
        Assert.Contains("positive integer maxSizeBytes", result.StandardError,
            StringComparison.Ordinal);
        Assert.DoesNotContain("RESTORE COMMAND CALLED", result.StandardError,
            StringComparison.Ordinal);
    }

    private static string Read(params string[] parts)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        return File.ReadAllText(Path.Combine([root, .. parts]));
    }

    private static IReadOnlyList<string> AzureCommands(string script)
    {
        var commands = new List<string>();
        foreach (var line in script.Split('\n'))
        {
            if (line.Trim() == "for command in az date; do")
            {
                continue;
            }

            var index = line.IndexOf("az ", StringComparison.Ordinal);
            if (index >= 0)
            {
                commands.Add(line[index..].TrimEnd('"', ')'));
            }
        }

        return commands;
    }

    private static ProcessResult RunValidateWithStub(
        string earliestRestoreDate,
        string sourceMaxSizeBytes = "34359738368")
    {
        if (OperatingSystem.IsWindows())
            throw new PlatformNotSupportedException("The restore runbook requires Bash.");

        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var scriptPath = Path.Combine(root, "infra", "scripts", "restore-database-dev.sh");
        var stubDirectory = Path.Combine(
            Path.GetTempPath(),
            $"funding-restore-az-stub-{Guid.NewGuid():N}");
        Directory.CreateDirectory(stubDirectory);
        try
        {
            var azStubPath = Path.Combine(stubDirectory, "az");
            File.WriteAllText(azStubPath, """
                #!/usr/bin/env bash
                set -euo pipefail

                server="sql-rf-dev-${AZURE_UNIQUE_SUFFIX}-centralus"
                resource_group="rg-rf-dev-${AZURE_UNIQUE_SUFFIX}"
                resource_group_id="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${resource_group}"
                source_id="${resource_group_id}/providers/Microsoft.Sql/servers/${server}/databases/risefunding-dev"

                if [[ "${1:-} ${2:-}" == "account show" ]]; then
                  printf '%s|%s|Enabled\n' "$AZURE_SUBSCRIPTION_ID" "$AZURE_TENANT_ID"
                elif [[ "${1:-} ${2:-}" == "group show" ]]; then
                  printf '%s|%s|rise-funding-org|dev\n' "$resource_group_id" "$resource_group"
                elif [[ "${1:-} ${2:-} ${3:-}" == "sql server list" ]]; then
                  if [[ "$*" == *"length(@)"* ]]; then
                    printf '1\n'
                  else
                    printf '%s\n' "$server"
                  fi
                elif [[ "${1:-} ${2:-} ${3:-}" == "sql server show" ]]; then
                  printf '%s.database.windows.net\n' "$server"
                elif [[ "${1:-} ${2:-} ${3:-}" == "sql db show" ]]; then
                  printf '%s|risefunding-dev|Online|GP_S_Gen5_1|1|60|0.5|false|Local|%s|%s\n' \
                    "$source_id" "$STUB_MAX_SIZE_BYTES" "$STUB_EARLIEST_RESTORE_DATE"
                elif [[ "${1:-} ${2:-} ${3:-}" == "sql db list" ]]; then
                  printf '0\n'
                elif [[ "${1:-} ${2:-} ${3:-}" == "sql db restore" ]]; then
                  printf 'RESTORE COMMAND CALLED\n' >&2
                  exit 99
                else
                  printf 'Unexpected az stub arguments: %s\n' "$*" >&2
                  exit 98
                fi
                """);
            File.SetUnixFileMode(
                azStubPath,
                UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);

            var startInfo = new ProcessStartInfo
            {
                FileName = "/bin/bash",
                RedirectStandardError = true,
                RedirectStandardOutput = true,
                UseShellExecute = false
            };
            startInfo.ArgumentList.Add(scriptPath);
            startInfo.ArgumentList.Add("validate");
            startInfo.Environment["PATH"] =
                $"{stubDirectory}:{Environment.GetEnvironmentVariable("PATH")}";
            startInfo.Environment["AZURE_SUBSCRIPTION_ID"] =
                "11111111-1111-1111-1111-111111111111";
            startInfo.Environment["AZURE_TENANT_ID"] =
                "22222222-2222-2222-2222-222222222222";
            startInfo.Environment["AZURE_UNIQUE_SUFFIX"] = "abcdefgh";
            startInfo.Environment["RF_DEV_RESTORE_SOURCE_DATABASE"] = "risefunding-dev";
            startInfo.Environment["RF_DEV_RESTORE_DESTINATION"] =
                "risefunding-dev-restore-abcdefgh-20250102t030405z-abcd";
            startInfo.Environment["RF_DEV_RESTORE_POINT_UTC"] = "2025-01-02T03:04:05Z";
            startInfo.Environment["STUB_EARLIEST_RESTORE_DATE"] = earliestRestoreDate;
            startInfo.Environment["STUB_MAX_SIZE_BYTES"] = sourceMaxSizeBytes;

            using var process = Process.Start(startInfo) ??
                throw new InvalidOperationException("Could not start restore validation.");
            var outputTask = process.StandardOutput.ReadToEndAsync();
            var errorTask = process.StandardError.ReadToEndAsync();
            if (!process.WaitForExit(10_000))
            {
                process.Kill(entireProcessTree: true);
                throw new TimeoutException("Restore validation did not terminate within 10 seconds.");
            }

            return new ProcessResult(
                process.ExitCode,
                outputTask.GetAwaiter().GetResult(),
                errorTask.GetAwaiter().GetResult());
        }
        finally
        {
            Directory.Delete(stubDirectory, recursive: true);
        }
    }

    private sealed record ProcessResult(
        int ExitCode,
        string StandardOutput,
        string StandardError);
}
