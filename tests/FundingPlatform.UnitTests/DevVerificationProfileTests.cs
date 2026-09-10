using System.Diagnostics;
using System.Text.Json.Nodes;
using FundingPlatform.Infrastructure.Persistence.Migrations;

namespace FundingPlatform.UnitTests;

public sealed class DevVerificationProfileTests
{
    [Theory]
    [InlineData("imports-only", false, true)]
    [InlineData("imports-only", true, false)]
    [InlineData("on-demand-imports", false, true)]
    [InlineData("on-demand-imports", true, false)]
    [InlineData("foundation", false, false)]
    [InlineData("foundation", true, true)]
    public async Task Blob_profiles_require_their_exact_CORS_boundary(string profile, bool uploads, bool expected)
    {
        var blob = Blob(uploads);
        Assert.Equal(expected, await Evaluate("documents_blob_valid", "documents_blob_json", profile, blob));
        blob["properties"]!["isVersioningEnabled"] = false;
        Assert.False(await Evaluate("documents_blob_valid", "documents_blob_json", profile, blob));
    }

    [Theory]
    [InlineData("imports-only", false, true)]
    [InlineData("imports-only", true, false)]
    [InlineData("on-demand-imports", false, true)]
    [InlineData("on-demand-imports", true, false)]
    [InlineData("foundation", false, false)]
    [InlineData("foundation", true, true)]
    public async Task Container_profiles_reject_public_or_unreviewed_storage(string profile, bool assets, bool expected)
    {
        var names = new List<string> { "dataprotection", "fp-source-incoming", "fp-source-quarantine", "fp-source-trusted" };
        if (assets) names.AddRange(["fp-project-incoming", "fp-project-quarantine", "fp-project-trusted"]);
        var containers = new JsonObject { ["value"] = new JsonArray(names.Select(name => (JsonNode)new JsonObject
            { ["name"] = name, ["properties"] = new JsonObject { ["publicAccess"] = "None" } }).ToArray()) };
        Assert.Equal(expected, await Evaluate("documents_containers_valid", "documents_containers_json", profile, containers));
        containers["value"]![0]!["properties"]!["publicAccess"] = "Blob";
        Assert.False(await Evaluate("documents_containers_valid", "documents_containers_json", profile, containers));
    }

    [Theory]
    [InlineData("imports-only", false, true)]
    [InlineData("imports-only", true, false)]
    [InlineData("on-demand-imports", false, true)]
    [InlineData("on-demand-imports", true, false)]
    [InlineData("foundation", false, false)]
    [InlineData("foundation", true, true)]
    public async Task Retention_profiles_reject_broader_deletion_or_missing_rules(string profile, bool assets, bool expected)
    {
        var rules = new JsonArray(Rule("delete-abandoned-source-uploads", ["fp-source-incoming/uploads/"], true, true));
        if (assets)
        {
            rules.Add(Rule("delete-abandoned-project-asset-uploads", ["fp-project-incoming/"], true, false));
            rules.Add(Rule("delete-project-asset-versions", ["fp-project-incoming/", "fp-project-quarantine/", "fp-project-trusted/"], false, true));
        }
        var lifecycle = new JsonObject { ["properties"] = new JsonObject { ["policy"] = new JsonObject { ["rules"] = rules } } };
        Assert.Equal(expected, await Evaluate("documents_lifecycle_valid", "documents_lifecycle_json", profile, lifecycle));
        rules[0]!["definition"]!["filters"]!["prefixMatch"] = new JsonArray("fp-source-trusted/");
        Assert.False(await Evaluate("documents_lifecycle_valid", "documents_lifecycle_json", profile, lifecycle));
    }

    [Fact]
    public void Code_release_explicitly_selects_on_demand_imports_without_changing_foundation_defaults()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var script = File.ReadAllText(Path.Combine(root, "infra", "scripts", "verify-dev.sh"));
        Assert.Contains("${AZURE_DEV_VERIFICATION_PROFILE:-foundation}", script, StringComparison.Ordinal);
        Assert.Contains("[[ \"$stage\" != 'base' ]]", script, StringComparison.Ordinal);
        Assert.Contains("ImportOutboxDispatcherFunction ImportQueueFunction ImportSchedulerFunction", script, StringComparison.Ordinal);
        Assert.Contains("Project assets must remain explicitly disabled in the worker", script, StringComparison.Ordinal);
        Assert.Contains("ImportWorkers__OnDemandOnly", script, StringComparison.Ordinal);
        Assert.Contains("ImportDispatch__ManagedIdentityClientId", script, StringComparison.Ordinal);
        foreach (var workflow in new[] { "api-dev.yml", "frontend-dev.yml" })
            Assert.Contains("AZURE_DEV_VERIFICATION_PROFILE: on-demand-imports", File.ReadAllText(Path.Combine(root, ".github", "workflows", workflow)), StringComparison.Ordinal);
        Assert.DoesNotContain("AZURE_DEV_VERIFICATION_PROFILE: on-demand-imports", File.ReadAllText(Path.Combine(root, ".github", "workflows", "infra-dev.yml")), StringComparison.Ordinal);
    }

    private static JsonObject Blob(bool uploads) => new()
    {
        ["properties"] = new JsonObject
        {
            ["isVersioningEnabled"] = true,
            ["deleteRetentionPolicy"] = new JsonObject { ["enabled"] = true, ["days"] = 14 },
            ["containerDeleteRetentionPolicy"] = new JsonObject { ["enabled"] = true, ["days"] = 14 },
            ["cors"] = new JsonObject { ["corsRules"] = uploads ? new JsonArray(new JsonObject
            {
                ["allowedOrigins"] = new JsonArray("https://preview.azurestaticapps.net"),
                ["allowedMethods"] = new JsonArray("PUT"),
                ["allowedHeaders"] = new JsonArray("content-type", "if-none-match", "x-ms-blob-type", "x-ms-client-request-id", "x-ms-version"),
                ["exposedHeaders"] = new JsonArray("etag", "x-ms-request-id", "x-ms-version-id"),
                ["maxAgeInSeconds"] = 300
            }) : new JsonArray() }
        }
    };

    private static JsonObject Rule(string name, string[] prefixes, bool baseBlob, bool versions)
    {
        var actions = new JsonObject();
        if (baseBlob) actions["baseBlob"] = new JsonObject { ["delete"] = new JsonObject { ["daysAfterModificationGreaterThan"] = 1 } };
        if (versions) actions["version"] = new JsonObject { ["delete"] = new JsonObject { ["daysAfterCreationGreaterThan"] = 14 } };
        return new JsonObject { ["name"] = name, ["enabled"] = true, ["type"] = "Lifecycle", ["definition"] = new JsonObject
        {
            ["actions"] = actions,
            ["filters"] = new JsonObject { ["blobTypes"] = new JsonArray("blockBlob"),
                ["prefixMatch"] = new JsonArray(prefixes.Select(value => (JsonNode?)JsonValue.Create(value)).ToArray()) }
        } };
    }

    private static async Task<bool> Evaluate(string assignment, string inputName, string profile, JsonNode input)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var script = File.ReadAllText(Path.Combine(root, "infra", "scripts", "verify-dev.sh"));
        var assignmentStart = script.IndexOf(assignment + "=", StringComparison.Ordinal);
        var queryStart = script.IndexOf("'\n", assignmentStart, StringComparison.Ordinal) + 2;
        var queryEnd = script.IndexOf("\n' <<<\"$" + inputName, queryStart, StringComparison.Ordinal);
        Assert.True(assignmentStart >= 0 && queryStart > assignmentStart && queryEnd > queryStart);
        var start = new ProcessStartInfo("jq") { RedirectStandardInput = true, RedirectStandardOutput = true,
            RedirectStandardError = true, UseShellExecute = false };
        foreach (var argument in new[] { "-r", "--arg", "origin", "https://preview.azurestaticapps.net", "--arg", "profile", profile, script[queryStart..queryEnd] })
            start.ArgumentList.Add(argument);
        using var process = Process.Start(start)!;
        var output = process.StandardOutput.ReadToEndAsync();
        var error = process.StandardError.ReadToEndAsync();
        await process.StandardInput.WriteAsync(input.ToJsonString());
        process.StandardInput.Close();
        await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(10));
        Assert.True(process.ExitCode == 0, await error);
        return bool.Parse((await output).Trim());
    }
}
