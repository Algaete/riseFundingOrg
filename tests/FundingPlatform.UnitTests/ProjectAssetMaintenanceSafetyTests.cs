using FundingPlatform.Infrastructure.Persistence.Migrations;
using FundingPlatform.Infrastructure.ProjectAssets.Configuration;
using FundingPlatform.Workers.Configuration;
using FundingPlatform.Workers.Functions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;

namespace FundingPlatform.UnitTests;

public sealed class ProjectAssetMaintenanceSafetyTests
{
    [Fact]
    public async Task Enabled_uploads_cannot_start_SQL_polling_by_default()
    {
        var maintenance = Options.Create(new ProjectAssetMaintenanceOptions());
        Assert.False(maintenance.Value.AllowSqlPolling);
        // Null services deliberately prove neither timer reaches SQL or Blob storage.
        await new ProjectAssetDefenderScanWatchdogFunction(null!,
            Options.Create(new ProjectAssetDefenderWorkerOptions { Enabled = true }), maintenance,
            NullLogger<ProjectAssetDefenderScanWatchdogFunction>.Instance)
            .RunAsync(null!, CancellationToken.None);
        await new ProjectAssetContentRetentionFunction(null!,
            Options.Create(new ContentRetentionOptions()),
            Options.Create(new ProjectAssetOptions { Enabled = true }), maintenance,
            NullLogger<ProjectAssetContentRetentionFunction>.Instance)
            .RunAsync(null!, CancellationToken.None);
    }

    [Fact]
    public async Task SQL_polling_opt_in_does_not_enable_disabled_uploads()
    {
        var maintenance = Options.Create(new ProjectAssetMaintenanceOptions { AllowSqlPolling = true });
        await new ProjectAssetDefenderScanWatchdogFunction(null!,
            Options.Create(new ProjectAssetDefenderWorkerOptions()), maintenance,
            NullLogger<ProjectAssetDefenderScanWatchdogFunction>.Instance)
            .RunAsync(null!, CancellationToken.None);
        await new ProjectAssetContentRetentionFunction(null!,
            Options.Create(new ContentRetentionOptions()), Options.Create(new ProjectAssetOptions()),
            maintenance, NullLogger<ProjectAssetContentRetentionFunction>.Instance)
            .RunAsync(null!, CancellationToken.None);
    }

    [Theory]
    [InlineData("true", true)]
    [InlineData("false", false)]
    [InlineData(null, false)]
    public void Polling_requires_its_own_configuration_not_the_import_flag(string? value, bool expected)
    {
        var settings = new Dictionary<string, string?> { ["ImportWorkers:OnDemandOnly"] = "false" };
        if (value is not null) settings["ProjectAssetMaintenance:AllowSqlPolling"] = value;
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(settings).Build();
        var options = new ProjectAssetMaintenanceOptions();
        configuration.GetSection(ProjectAssetMaintenanceOptions.SectionName).Bind(options);
        Assert.Equal(expected, options.AllowSqlPolling);
    }

    [Fact]
    public void Infrastructure_and_local_example_keep_the_cost_interlock_off()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        Assert.Contains("ProjectAssetMaintenance__AllowSqlPolling: 'false'",
            File.ReadAllText(Path.Combine(root, "infra", "modules", "environment.bicep")));
        Assert.Contains("\"ProjectAssetMaintenance__AllowSqlPolling\": \"false\"",
            File.ReadAllText(Path.Combine(root, "src", "FundingPlatform.Workers", "local.settings.example.json")));
    }
}
