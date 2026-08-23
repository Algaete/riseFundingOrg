namespace FundingPlatform.Core.FundingOpportunities;

public sealed record ExternalFundingOpportunity(
    string ProviderCode,
    string ExternalId,
    string ReferenceNumber,
    string Title,
    string SponsorName,
    string? Description,
    string? EligibilityDescription,
    string? FundingInstrument,
    string? FundingCategoriesDescription,
    DateOnly? OpenDate,
    DateOnly? CloseDate,
    decimal? MinimumAmount,
    decimal? MaximumAmount,
    bool? RequiresCofunding,
    string SourceUrl,
    string? ApplicationUrl,
    DateTimeOffset RetrievedAtUtc);
