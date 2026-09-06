using FundingPlatform.Workers.Configuration;

namespace FundingPlatform.UnitTests;

public sealed class DefenderEventGridStartupOptionsTests
{
    [Fact]
    public void Hosted_interlock_uses_canonical_azure_functions_setting_names()
    {
        Assert.Equal(
            "AzureWebJobs.DefenderEventGridFunction.Disabled",
            DefenderEventGridOptions.EventGridFunctionDisabledSetting);
        Assert.Equal(
            "AzureWebJobs.DefenderScanWatchdogFunction.Disabled",
            DefenderEventGridOptions.ScanWatchdogFunctionDisabledSetting);
    }

    [Theory]
    [InlineData("Development")]
    [InlineData("development")]
    [InlineData("Testing")]
    [InlineData("TESTING")]
    public void Disabled_in_local_environments_does_not_require_host_switches(
        string environmentName)
    {
        Assert.True(DefenderEventGridOptions.IsValid(
            new DefenderEventGridOptions(), environmentName));
    }

    [Theory]
    [InlineData("Production")]
    [InlineData("Staging")]
    [InlineData("Preview")]
    public void Disabled_in_hosted_environments_requires_both_exact_host_switches(
        string environmentName)
    {
        Assert.True(DefenderEventGridOptions.IsValid(
            new DefenderEventGridOptions(),
            environmentName,
            eventGridFunctionDisabled: "true",
            scanWatchdogFunctionDisabled: "true"));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("false")]
    [InlineData("True")]
    [InlineData("TRUE")]
    [InlineData(" true")]
    [InlineData("true ")]
    [InlineData("1")]
    [InlineData("yes")]
    public void Disabled_in_production_rejects_non_exact_event_grid_switch(string? value)
    {
        Assert.False(DefenderEventGridOptions.IsValid(
            new DefenderEventGridOptions(),
            "Production",
            eventGridFunctionDisabled: value,
            scanWatchdogFunctionDisabled: "true"));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("false")]
    [InlineData("True")]
    [InlineData("TRUE")]
    [InlineData(" true")]
    [InlineData("true ")]
    [InlineData("1")]
    [InlineData("yes")]
    public void Disabled_in_production_rejects_non_exact_watchdog_switch(string? value)
    {
        Assert.False(DefenderEventGridOptions.IsValid(
            new DefenderEventGridOptions(),
            "Production",
            eventGridFunctionDisabled: "true",
            scanWatchdogFunctionDisabled: value));
    }

    [Fact]
    public void Enabled_in_production_keeps_full_validation_even_when_functions_are_disabled()
    {
        var invalid = CompleteEnabledOptions();
        invalid.AllowedCallerObjectId = string.Empty;

        Assert.False(DefenderEventGridOptions.IsValid(
            invalid,
            "Production",
            BlobServiceUri,
            eventGridFunctionDisabled: "true",
            scanWatchdogFunctionDisabled: "true"));
    }

    [Fact]
    public void Enabled_in_production_does_not_depend_on_disabled_function_switches()
    {
        Assert.True(DefenderEventGridOptions.IsValid(
            CompleteEnabledOptions(),
            "Production",
            BlobServiceUri,
            eventGridFunctionDisabled: null,
            scanWatchdogFunctionDisabled: "false"));
    }

    private const string BlobServiceUri =
        "https://fpongdev1234.blob.core.windows.net";

    private static DefenderEventGridOptions CompleteEnabledOptions() => new()
    {
        Enabled = true,
        TenantId = "11111111-1111-1111-1111-111111111111",
        Audience = "api://22222222-2222-2222-2222-222222222222",
        AllowedCallerApplicationId = "33333333-3333-3333-3333-333333333333",
        AllowedCallerObjectId = "44444444-4444-4444-4444-444444444444",
        ExpectedTopicResourceId =
            "/subscriptions/55555555-5555-5555-5555-555555555555/resourceGroups/rg/providers/Microsoft.EventGrid/systemtopics/defender",
        ExpectedSubscriptionName = "defender-malware-results",
        StorageAccountResourceId =
            "/subscriptions/55555555-5555-5555-5555-555555555555/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/fpongdev1234",
        PendingScanTimeoutMinutes = 240,
        WatchdogBatchSize = 25
    };
}
