using FundingPlatform.Infrastructure.Observability;
using OpenTelemetry.Resources;

namespace FundingPlatform.UnitTests;

public sealed class TelemetryResourceIdentityTests
{
    [Fact]
    public void API_role_is_stable_after_Azure_detection_without_losing_the_replica_identity()
    {
        var builder = ResourceBuilder.CreateEmpty()
            .AddDetector(new AzureContainerAppDetectorFixture());

        TelemetryResourceIdentity.ConfigureApi(builder);

        var attributes = builder.Build().Attributes.ToDictionary(pair => pair.Key, pair => pair.Value);
        Assert.Equal("FundingPlatform.Api", attributes["service.name"]);
        Assert.Equal("fixture-api--revision-replica", attributes["service.instance.id"]);
        Assert.Equal("azure", attributes["cloud.provider"]);
        Assert.Equal("azure_container_apps", attributes["cloud.platform"]);
        Assert.DoesNotContain("service.namespace", attributes.Keys);
    }

    private sealed class AzureContainerAppDetectorFixture : IResourceDetector
    {
        public Resource Detect() => new(
        [
            new KeyValuePair<string, object>("service.name", "ca-rf-dev-fixture-api"),
            new KeyValuePair<string, object>("service.instance.id", "fixture-api--revision-replica"),
            new KeyValuePair<string, object>("cloud.provider", "azure"),
            new KeyValuePair<string, object>("cloud.platform", "azure_container_apps")
        ]);
    }
}
