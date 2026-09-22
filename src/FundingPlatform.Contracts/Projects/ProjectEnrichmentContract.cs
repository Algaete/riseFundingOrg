namespace FundingPlatform.Contracts.Projects;

// On PUT, omitted/null enrichment preserves it. Omitted/null background also preserves
// that nested section; send background:{} to explicitly clear its text fields.
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
    bool? SeekingConsortium = null,
    ProjectBackgroundContract? Background = null);

public sealed record ProjectBackgroundContract(
    string? AdditionalInformation = null,
    string? TechnicalInformation = null,
    string? ExistingPartnerships = null,
    string? PreviousResults = null);

public sealed record ProjectImpactIndicatorContract(
    string? Name = null,
    string? Unit = null,
    decimal? Baseline = null,
    decimal? Target = null);
