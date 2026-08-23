namespace FundingPlatform.Core.FundingOpportunities;

/// <summary>
/// An immutable, source-faithful observation. RawJson is persisted before the
/// normalized opportunity is staged into the editorial workflow.
/// </summary>
public sealed record FundingSourceObservation(
    string ExternalId,
    string SourceUrl,
    string RawJson,
    byte[] ContentHash,
    DateTimeOffset RetrievedAtUtc,
    ExternalFundingOpportunity Opportunity,
    string MimeType = "application/json");
