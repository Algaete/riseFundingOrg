using FundingPlatform.Application;
using FundingPlatform.Contracts;
using FundingPlatform.Core;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using System.Text.Json;

namespace FundingPlatform.UnitTests;

public sealed class ArchitectureSmokeTests
{
    [Fact]
    public void Project_markers_resolve_the_expected_assemblies()
    {
        Assert.Equal("FundingPlatform.Core", CoreAssembly.Reference.GetName().Name);
        Assert.Equal("FundingPlatform.Application", ApplicationAssembly.Reference.GetName().Name);
    }

    [Fact]
    public void Api_status_contract_has_value_semantics()
    {
        var first = new ApiStatusResponse("FundingPlatform.Api", "ok", "1.0.0");
        var second = new ApiStatusResponse("FundingPlatform.Api", "ok", "1.0.0");

        Assert.Equal(first, second);
    }

    [Fact]
    public void Worker_queue_visibility_outlasts_the_default_import_lease()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var json = File.ReadAllText(Path.Combine(
            root, "src", "FundingPlatform.Workers", "host.json"));
        using var document = JsonDocument.Parse(json);
        var value = document.RootElement
            .GetProperty("extensions")
            .GetProperty("queues")
            .GetProperty("visibilityTimeout")
            .GetString();
        var batchSize = document.RootElement
            .GetProperty("extensions")
            .GetProperty("queues")
            .GetProperty("batchSize")
            .GetInt32();
        var messageEncoding = document.RootElement
            .GetProperty("extensions")
            .GetProperty("queues")
            .GetProperty("messageEncoding")
            .GetString();

        Assert.True(TimeSpan.TryParse(value, out var visibilityTimeout));
        Assert.True(visibilityTimeout > TimeSpan.FromMinutes(30));
        Assert.Equal(1, batchSize);
        Assert.Equal("base64", messageEncoding);
    }
}
