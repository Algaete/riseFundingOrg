namespace FundingPlatform.Contracts.Projects;

// On PUT, omitted/null enrichment preserves the aggregate. {} explicitly clears it.
public sealed record ProjectEnrichmentContract(
    string? Problem = null,
    string? Solution = null,
    int? BeneficiaryCount = null,
    string? Locality = null,
    decimal? Latitude = null,
    decimal? Longitude = null,
    byte LocationVisibility = 0,
    IReadOnlyList<ProjectImpactIndicatorContract?>? ImpactIndicators = null,
    string? SoughtPartners = null,
    string? SoughtProfessionals = null,
    bool? SeekingConsortium = null);

public sealed record ProjectImpactIndicatorContract(
    string? Name = null,
    string? Unit = null,
    decimal? Baseline = null,
    decimal? Target = null);
