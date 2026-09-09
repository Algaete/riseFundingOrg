namespace FundingPlatform.Core.Projects;

public enum ProjectLocationVisibility : byte
{
    RegionOnly = 0,
    Locality = 1,
    ApproximatePoint = 2
}

/// <summary>Optional, versioned project content. Exact coordinates are never public.</summary>
public sealed record ProjectEnrichment(
    string? Problem = null,
    string? Solution = null,
    int? BeneficiaryCount = null,
    string? Locality = null,
    decimal? Latitude = null,
    decimal? Longitude = null,
    ProjectLocationVisibility LocationVisibility = ProjectLocationVisibility.RegionOnly,
    IReadOnlyList<ProjectImpactIndicator?>? ImpactIndicators = null,
    string? SoughtPartners = null,
    string? SoughtProfessionals = null,
    bool? SeekingConsortium = null)
{
    public ProjectEnrichment ForPublic() => this with
    {
        Locality = LocationVisibility is ProjectLocationVisibility.Locality or
            ProjectLocationVisibility.ApproximatePoint ? Locality : null,
        Latitude = LocationVisibility == ProjectLocationVisibility.ApproximatePoint &&
            Latitude is >= -90 and <= 90 && Longitude is >= -180 and <= 180
                ? decimal.Round(Latitude.Value, 2, MidpointRounding.AwayFromZero) : null,
        Longitude = LocationVisibility == ProjectLocationVisibility.ApproximatePoint &&
            Latitude is >= -90 and <= 90 && Longitude is >= -180 and <= 180
                ? decimal.Round(Longitude.Value, 2, MidpointRounding.AwayFromZero) : null
    };
}

public sealed record ProjectImpactIndicator(
    string? Name = null,
    string? Unit = null,
    decimal? Baseline = null,
    decimal? Target = null);
