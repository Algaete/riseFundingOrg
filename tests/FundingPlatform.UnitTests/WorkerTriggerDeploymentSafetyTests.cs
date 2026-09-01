using FundingPlatform.Infrastructure.Persistence.Migrations;
using System.Text.RegularExpressions;

namespace FundingPlatform.UnitTests;

public sealed partial class WorkerTriggerDeploymentSafetyTests
{
    [Fact]
    public void Every_deployed_worker_function_is_disabled_by_literal_dev_app_setting()
    {
        var generalFunctions = DiscoverFunctionNames("FundingPlatform.Workers");
        var extractionFunctions = DiscoverFunctionNames("FundingPlatform.ExtractionWorkers");
        var environment = Read("infra", "modules", "environment.bicep");
        var generalSettings = Slice(
            environment,
            "module generalWorker './flex-function.bicep'",
            "module extractionWorker './flex-function.bicep'");
        var extractionSettings = Slice(
            environment,
            "module extractionWorker './flex-function.bicep'",
            "module environmentRbac './environment-rbac.bicep'");

        Assert.Equal(14, generalFunctions.Count);
        Assert.Equal(2, extractionFunctions.Count);
        AssertExactDisabledSettings(generalSettings, generalFunctions);
        AssertExactDisabledSettings(extractionSettings, extractionFunctions);
        Assert.DoesNotContain(".Disabled': 'false'", environment, StringComparison.Ordinal);
        Assert.DoesNotContain("workerTriggersEnabled", environment, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Local_worker_examples_are_also_inert_by_default()
    {
        AssertExactDisabledSettings(
            Read("src", "FundingPlatform.Workers", "local.settings.example.json"),
            DiscoverFunctionNames("FundingPlatform.Workers"));
        AssertExactDisabledSettings(
            Read("src", "FundingPlatform.ExtractionWorkers", "local.settings.example.json"),
            DiscoverFunctionNames("FundingPlatform.ExtractionWorkers"));
    }

    [Fact]
    public void Flex_module_preserves_caller_supplied_function_disable_settings()
    {
        var functionModule = Read("infra", "modules", "flex-function.bicep");

        Assert.Contains("var additionalAppSettings = [for setting in items(appSettings)",
            functionModule, StringComparison.Ordinal);
        Assert.Contains("appSettings: concat(additionalAppSettings, [", functionModule,
            StringComparison.Ordinal);
        Assert.DoesNotContain("AzureWebJobs.", functionModule, StringComparison.Ordinal);
    }

    private static IReadOnlyList<string> DiscoverFunctionNames(string projectName)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var functionsDirectory = Path.Combine(root, "src", projectName, "Functions");
        var source = string.Join('\n', Directory.EnumerateFiles(functionsDirectory, "*.cs")
            .Order(StringComparer.Ordinal)
            .Select(File.ReadAllText));
        var declarations = FunctionAttributeRegex().Matches(source);
        var names = NamedFunctionAttributeRegex().Matches(source)
            .Cast<Match>()
            .Select(match => match.Groups["name"].Value)
            .Order(StringComparer.Ordinal)
            .ToArray();

        Assert.Equal(declarations.Count, names.Length);
        Assert.Equal(names.Length, names.Distinct(StringComparer.Ordinal).Count());
        return names;
    }

    private static void AssertExactDisabledSettings(
        string configuration,
        IReadOnlyCollection<string> functionNames)
    {
        var configuredSettings = DisabledSettingRegex().Matches(configuration)
            .Cast<Match>()
            .ToArray();
        Assert.All(configuredSettings,
            match => Assert.Equal("true", match.Groups["value"].Value));
        var configuredNames = configuredSettings
            .Select(match => match.Groups["name"].Value)
            .Order(StringComparer.Ordinal)
            .ToArray();
        var expectedNames = functionNames.Order(StringComparer.Ordinal).ToArray();

        Assert.Equal(expectedNames, configuredNames);
    }

    private static string Slice(string value, string startMarker, string endMarker)
    {
        var start = value.IndexOf(startMarker, StringComparison.Ordinal);
        var end = value.IndexOf(endMarker, start + startMarker.Length,
            StringComparison.Ordinal);
        Assert.True(start >= 0 && end > start);
        return value[start..end];
    }

    private static string Read(params string[] parts)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        return File.ReadAllText(Path.Combine([root, .. parts]));
    }

    [GeneratedRegex(@"\[\s*Function\s*\(")]
    private static partial Regex FunctionAttributeRegex();

    [GeneratedRegex(
        @"\[\s*Function\s*\(\s*nameof\s*\(\s*(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*\)\s*\)\s*\]")]
    private static partial Regex NamedFunctionAttributeRegex();

    [GeneratedRegex(
        "[\"']AzureWebJobs\\.(?<name>[A-Za-z_][A-Za-z0-9_]*)\\.Disabled[\"']\\s*:\\s*[\"'](?<value>true|false)[\"']")]
    private static partial Regex DisabledSettingRegex();
}
