using OpenTelemetry.Resources;

namespace FundingPlatform.Infrastructure.Observability;

public static class TelemetryResourceIdentity
{
    public const string ApiServiceName = "FundingPlatform.Api";

    /// <summary>
    /// Applies the API's stable service name after Azure's resource detectors.
    /// The detector-provided replica identity and other resource attributes remain intact.
    /// </summary>
    public static void ConfigureApi(ResourceBuilder resourceBuilder)
    {
        ArgumentNullException.ThrowIfNull(resourceBuilder);
        // Dev leaves service.namespace unset; even an empty namespace would prefix the Azure role.
        resourceBuilder.AddService(
            ApiServiceName,
            autoGenerateServiceInstanceId: false);
    }
}
