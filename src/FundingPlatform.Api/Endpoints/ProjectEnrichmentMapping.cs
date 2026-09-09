using FundingPlatform.Contracts.Projects;
using FundingPlatform.Core.Projects;

namespace FundingPlatform.Api.Endpoints;

internal static class ProjectEnrichmentMapping
{
    public static ProjectEnrichment? ToDomain(ProjectEnrichmentContract? value) => value is null ? null : new(
        value.Problem, value.Solution, value.BeneficiaryCount, value.Locality,
        value.Latitude, value.Longitude, (ProjectLocationVisibility)value.LocationVisibility,
        value.ImpactIndicators?.Select(item => item is null ? null : new ProjectImpactIndicator(
            item.Name, item.Unit, item.Baseline, item.Target)).ToArray(),
        value.SoughtPartners, value.SoughtProfessionals, value.SeekingConsortium);

    public static ProjectEnrichmentContract? ToContract(ProjectEnrichment? value, bool publicView = false)
    {
        if (value is null) return null;
        if (publicView) value = value.ForPublic();
        return new(value.Problem, value.Solution, value.BeneficiaryCount, value.Locality,
            value.Latitude, value.Longitude, (byte)value.LocationVisibility,
            value.ImpactIndicators?.Select(item => item is null ? null : new ProjectImpactIndicatorContract(
                item.Name, item.Unit, item.Baseline, item.Target)).ToArray() ?? [],
            value.SoughtPartners, value.SoughtProfessionals, value.SeekingConsortium);
    }
}
