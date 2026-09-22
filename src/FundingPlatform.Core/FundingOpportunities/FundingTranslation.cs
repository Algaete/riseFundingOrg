namespace FundingPlatform.Core.FundingOpportunities;

// Presentation only: identifiers, sponsors, URLs, amounts, dates and eligibility
// classifications remain canonical and are never writable through a translation.
public sealed record FundingTranslationText(
    string? Title = null, string? Summary = null, string? Description = null,
    string? EligibilityDescription = null, string? Requirements = null, string? Objectives = null,
    string? AllowedActivities = null, string? ExcludedActivities = null, string? Restrictions = null,
    string? TargetOrganizationsDescription = null, string? TargetPopulationsDescription = null);

public sealed record FundingTranslation(
    string Language, int SourceContentVersion, int Revision, bool Reviewed,
    FundingTranslationText Text, DateTimeOffset UpdatedAtUtc);

public sealed record FundingTranslationWrite(
    int SourceContentVersion, int ExpectedRevision, bool Reviewed, FundingTranslationText? Text);

public sealed record FundingTranslationLocalization(string RequestedLanguage, string Status, int? Revision = null);

public sealed record FundingTranslationReference(Guid OpportunityId, int SourceContentVersion);
public sealed record FundingSummaryTranslation(Guid OpportunityId, string Language, int SourceContentVersion,
    int Revision, bool Reviewed, string? Title, string? Summary);
