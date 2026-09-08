using FundingPlatform.Infrastructure.ProjectAssets.Configuration;
using FundingPlatform.Workers.Configuration;

namespace FundingPlatform.UnitTests;

public sealed class ProjectAssetDefenderStartupOptionsTests
{
    [Fact]
    public void Disabled_local_configuration_is_inert_without_host_settings()
    {
        Assert.True(ProjectAssetDefenderWorkerOptions.IsValid(
            new ProjectAssetDefenderWorkerOptions(),
            "Development",
            new DefenderEventGridOptions(),
            new ProjectAssetOptions()));
    }

    [Fact]
    public void Disabled_hosted_configuration_requires_both_exact_disable_interlocks()
    {
        var options = new ProjectAssetDefenderWorkerOptions();

        Assert.False(ProjectAssetDefenderWorkerOptions.IsValid(
            options, "Production", new DefenderEventGridOptions(), new ProjectAssetOptions()));
        Assert.False(ProjectAssetDefenderWorkerOptions.IsValid(
            options, "Production", new DefenderEventGridOptions(), new ProjectAssetOptions(),
            "True", "true"));
        Assert.True(ProjectAssetDefenderWorkerOptions.IsValid(
            options, "Production", new DefenderEventGridOptions(), new ProjectAssetOptions(),
            "true", "true"));
    }

    [Fact]
    public void Enabled_pipeline_requires_shared_auth_project_assets_and_distinct_subscription()
    {
        var options = CompleteOptions();
        var shared = CompleteSharedOptions();
        var assets = CompleteProjectAssetOptions();

        Assert.True(ProjectAssetDefenderWorkerOptions.IsValid(
            options, "Production", shared, assets,
            "false", "false",
            imageSanitizationAvailable: true));

        shared.Enabled = false;
        Assert.False(ProjectAssetDefenderWorkerOptions.IsValid(
            options, "Production", shared, assets,
            "false", "false",
            imageSanitizationAvailable: true));
        shared.Enabled = true;

        assets.Enabled = false;
        Assert.False(ProjectAssetDefenderWorkerOptions.IsValid(
            options, "Production", shared, assets,
            "false", "false",
            imageSanitizationAvailable: true));
        assets.Enabled = true;

        assets.ScanMode = "DevelopmentFake";
        Assert.False(ProjectAssetDefenderWorkerOptions.IsValid(
            options, "Production", shared, assets,
            "false", "false",
            imageSanitizationAvailable: true));
        assets.ScanMode = "MicrosoftDefender";

        options.ExpectedSubscriptionName = shared.ExpectedSubscriptionName;
        Assert.False(ProjectAssetDefenderWorkerOptions.IsValid(
            options, "Production", shared, assets,
            "false", "false",
            imageSanitizationAvailable: true));
    }

    [Theory]
    [InlineData(null, null)]
    [InlineData("true", "false")]
    [InlineData("false", "true")]
    [InlineData("False", "false")]
    public void Enabled_pipeline_requires_both_exact_trigger_enable_interlocks(
        string? eventGridDisabled,
        string? watchdogDisabled)
    {
        Assert.False(ProjectAssetDefenderWorkerOptions.IsValid(
            CompleteOptions(),
            "Production",
            CompleteSharedOptions(),
            CompleteProjectAssetOptions(),
            eventGridDisabled,
            watchdogDisabled,
            imageSanitizationAvailable: true));
    }

    [Fact]
    public void Enabled_pipeline_is_blocked_until_image_sanitization_is_compiled_in()
    {
        Assert.False(ProjectAssetDefenderWorkerOptions.IsValid(
            CompleteOptions(),
            "Production",
            CompleteSharedOptions(),
            CompleteProjectAssetOptions()));
    }

    [Fact]
    public void Enabled_pipeline_requires_the_same_storage_account()
    {
        var assets = CompleteProjectAssetOptions();
        assets.BlobServiceUri = "https://different123.blob.core.windows.net";

        Assert.False(ProjectAssetDefenderWorkerOptions.IsValid(
            CompleteOptions(), "Production", CompleteSharedOptions(), assets,
            "false", "false",
            imageSanitizationAvailable: true));
    }

    [Fact]
    public void Policy_freezes_exact_project_asset_boundaries()
    {
        var options = CompleteOptions();
        var policy = options.ToPolicy(
            CompleteSharedOptions(), CompleteProjectAssetOptions());

        Assert.Equal("project-assets-defender", policy.ExpectedSubscriptionName);
        Assert.Equal("fp-project-quarantine", policy.QuarantineContainer);
        Assert.Equal("fp-project-trusted", policy.TrustedContainer);
        Assert.Equal(10_485_760, policy.MaxImageBytes);
        Assert.Equal(26_214_400, policy.MaxDocumentBytes);
        Assert.Equal(TimeSpan.FromMinutes(5), policy.MaximumFutureClockSkew);
    }

    private static ProjectAssetDefenderWorkerOptions CompleteOptions() => new()
    {
        Enabled = true,
        ExpectedSubscriptionName = "project-assets-defender",
        PendingScanTimeoutMinutes = 240,
        WatchdogBatchSize = 25
    };

    private static DefenderEventGridOptions CompleteSharedOptions() => new()
    {
        Enabled = true,
        TenantId = "82975d1b-72e5-49cd-ad96-1860a1402c50",
        Audience = "api://1d8921ee-2096-4b65-b559-a03f01c34ac8",
        AllowedCallerApplicationId = "65b57e7d-aa11-4052-be7d-f277a8129d36",
        AllowedCallerObjectId = "1737de60-e3bf-47f6-9024-33e66dc052de",
        ExpectedTopicResourceId =
            "/subscriptions/67e6c5a1-338f-4f15-bb76-bd2dd3b080ff/resourceGroups/rg/providers/Microsoft.EventGrid/topics/defender",
        ExpectedSubscriptionName = "source-documents-defender",
        StorageAccountResourceId =
            "/subscriptions/67e6c5a1-338f-4f15-bb76-bd2dd3b080ff/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/fpongdev1234"
    };

    private static ProjectAssetOptions CompleteProjectAssetOptions() => new()
    {
        Enabled = true,
        BlobServiceUri = "https://fpongdev1234.blob.core.windows.net",
        IncomingContainer = "fp-project-incoming",
        QuarantineContainer = "fp-project-quarantine",
        TrustedContainer = "fp-project-trusted",
        ScanMode = "MicrosoftDefender"
    };
}
