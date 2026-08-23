namespace FundingPlatform.Core.FundingOpportunities;

public enum FundingPublicationStatus : byte
{
    Draft = 0,
    PendingReview = 1,
    Published = 2,
    Rejected = 3,
    Archived = 4
}

public enum FundingReviewDecision : byte
{
    Approve = 2,
    Reject = 3
}

public enum FundingEditorialAction
{
    SubmitReview,
    Approve,
    Reject,
    StartCorrection,
    Deactivate
}

public enum FunderOpportunityRole : byte
{
    Primary = 1,
    CoFunder = 2,
    Administrator = 3
}

public enum FundingAmountStatus : byte
{
    Unknown = 0,
    Specified = 1,
    NotDisclosed = 2
}

public enum FundingDeadlineType : byte
{
    Unknown = 0,
    Fixed = 1,
    Rolling = 2
}

public enum FundingDeadlinePrecision : byte
{
    Unknown = 0,
    Date = 1,
    DateTime = 2
}

public enum FundingGeographicScope : byte
{
    Unknown = 0,
    Specified = 1,
    Global = 2
}

public enum FundingRemoteApplication : byte
{
    Unknown = 0,
    No = 1,
    Yes = 2
}

public static class FundingEditorialStateMachine
{
    public static bool CanEdit(FundingPublicationStatus status) =>
        status is FundingPublicationStatus.Draft or FundingPublicationStatus.Rejected;

    public static bool CanSubmitReview(FundingPublicationStatus status) =>
        status is FundingPublicationStatus.Draft or FundingPublicationStatus.Rejected;

    public static bool CanReview(FundingPublicationStatus status) =>
        status == FundingPublicationStatus.PendingReview;

    public static bool CanStartCorrection(FundingPublicationStatus status) =>
        status == FundingPublicationStatus.Published;

    public static bool CanDeactivate(FundingPublicationStatus status) =>
        status != FundingPublicationStatus.Archived;
}

public sealed record FunderData(
    string Name,
    string? Description,
    string? WebsiteUrl,
    short? CountryId,
    IReadOnlyList<string> Aliases);

public sealed record PersistedFundingEntity(
    Guid PublicId,
    int ContentVersion,
    FundingPublicationStatus PublicationStatus,
    byte[] RowVersion);

public sealed record FunderSummary(
    Guid PublicId,
    string Slug,
    string Name,
    string? Description,
    string? WebsiteUrl,
    short? CountryId,
    string? CountryCode,
    string? CountryName,
    FundingPublicationStatus PublicationStatus,
    bool IsActive,
    int ContentVersion,
    DateTimeOffset UpdatedAtUtc,
    byte[] RowVersion);

public sealed record FunderDetails(
    Guid PublicId,
    string Slug,
    string Name,
    string? Description,
    string? WebsiteUrl,
    short? CountryId,
    string? CountryCode,
    string? CountryName,
    FundingPublicationStatus PublicationStatus,
    bool IsActive,
    int ContentVersion,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    byte[] RowVersion,
    IReadOnlyList<string> Aliases,
    DateTimeOffset? SubmittedAtUtc,
    DateTimeOffset? ReviewedAtUtc,
    Guid? ReviewedByUserPublicId,
    DateTimeOffset? PublishedAtUtc,
    string? RejectionReason,
    IReadOnlyList<FunderOpportunitySummary> Opportunities);

public sealed record FunderOpportunitySummary(
    Guid PublicId,
    string Slug,
    string Title,
    FunderOpportunityRole Role,
    FundingPublicationStatus PublicationStatus,
    bool IsActive);

public sealed record FunderPage(
    IReadOnlyList<FunderSummary> Items,
    long TotalCount,
    int PageNumber,
    int PageSize);

public sealed record PublicFunderSummary(
    Guid PublicId,
    string Slug,
    string Name,
    string? Description,
    string? WebsiteUrl,
    string? CountryCode,
    string? CountryName);

public sealed record PublicFunderDetails(
    Guid PublicId,
    string Slug,
    string Name,
    string? Description,
    string? WebsiteUrl,
    string? CountryCode,
    string? CountryName,
    IReadOnlyList<string> Aliases,
    DateTimeOffset PublishedAtUtc,
    IReadOnlyList<PublicFunderOpportunity> Opportunities);

public sealed record PublicFunderOpportunity(
    Guid PublicId,
    string Slug,
    string Title,
    string? Summary,
    string SponsorName,
    string? Currency,
    decimal? MinimumAmount,
    decimal? MaximumAmount,
    DateOnly? OpenDate,
    DateOnly? CloseDate,
    DateTimeOffset PublishedAtUtc);

public sealed record PublicFunderPage(
    IReadOnlyList<PublicFunderSummary> Items,
    long TotalCount,
    int PageNumber,
    int PageSize);

public sealed record FundingOpportunityFunder(
    Guid PublicId,
    string Slug,
    string Name,
    FunderOpportunityRole Role);

public sealed record FundingOpportunityFunderLink(
    Guid FunderPublicId,
    FunderOpportunityRole Role);

public sealed record FundingFieldEvidence(
    Guid PublicId,
    string FieldPath,
    string ValueJson,
    byte ExtractionMethod,
    string? EvidenceText,
    string? SourceLocator,
    decimal? Confidence,
    bool IsSelected,
    bool IsManualLock,
    Guid? CreatedByUserPublicId,
    DateTimeOffset CreatedAtUtc);

public sealed record FundingOpportunitySourceLink(
    int FundingSourceId,
    string SourceName,
    string? ExternalId,
    string SourceUrl,
    DateTimeOffset FirstSeenAtUtc,
    DateTimeOffset LastSeenAtUtc,
    bool IsPrimary,
    bool IsActive);

public sealed record FundingSourceAdminOption(
    int Id,
    string Name,
    byte ProviderType,
    string? BaseUrl,
    bool IsEnabled,
    string? ProviderCode = null,
    string ComplianceStatus = "unknown",
    DateTimeOffset? NextRunAtUtc = null,
    DateTimeOffset? LastSuccessfulRunAtUtc = null,
    byte LicenseStatus = 0,
    string? LicenseName = null,
    string? LicenseUrl = null,
    DateTimeOffset? LicenseReviewedAtUtc = null,
    DateTimeOffset? LicenseExpiresAtUtc = null,
    byte RobotsPolicyStatus = 0,
    DateTimeOffset? RobotsReviewedAtUtc = null,
    DateTimeOffset? RobotsExpiresAtUtc = null,
    int? RequestRateLimitPerMinute = null,
    int? MaximumResponseBytes = null,
    short? ContentRetentionDays = null,
    bool AllowedHostsRequired = false,
    int AcquisitionPolicyVersion = 1,
    int EnabledAllowedHostCount = 0,
    bool AcquisitionReady = false);

public sealed record FundingOpportunityEditorialData(
    string Title,
    string? Summary,
    string? Description,
    string SponsorName,
    string? SponsorUrl,
    string? ApplicationUrl,
    IReadOnlyList<FundingOpportunityFunderLink> Funders,
    int FundingSourceId,
    string? ExternalId,
    string SourceUrl,
    short? IssuerCountryId,
    short? FundingTypeId,
    string? Currency,
    decimal? MinimumAmount,
    decimal? MaximumAmount,
    FundingAmountStatus AmountStatus,
    DateOnly? OpenDate,
    DateOnly? CloseDate,
    DateTimeOffset? CloseAtUtc,
    string? DeadlineTimeZoneId,
    FundingDeadlineType DeadlineType,
    FundingDeadlinePrecision DeadlinePrecision,
    string? EligibilityDescription,
    string? Requirements,
    string? Objectives,
    string? AllowedActivities,
    string? ExcludedActivities,
    string? Restrictions,
    string? TargetOrganizationsDescription,
    string? TargetPopulationsDescription,
    short? MinimumOperatingYears,
    bool? RequiresLegalEntity,
    bool? RequiresPriorExperience,
    bool? RequiresCofunding,
    decimal? CofundingPercentage,
    FundingGeographicScope GeographicScope,
    FundingRemoteApplication RemoteApplication,
    DateTimeOffset? LastVerifiedAtUtc,
    IReadOnlyList<short> CountryIds,
    IReadOnlyList<int> RegionIds,
    IReadOnlyList<int> CategoryIds,
    IReadOnlyList<int> BeneficiaryTypeIds,
    IReadOnlyList<int> ProjectTypeIds);

public sealed record FundingOpportunityAdminSummary(
    Guid PublicId,
    string Slug,
    string Title,
    string? Summary,
    string SponsorName,
    FundingPublicationStatus PublicationStatus,
    bool IsActive,
    int ContentVersion,
    DateOnly? OpenDate,
    DateOnly? CloseDate,
    string? Currency,
    decimal? MinimumAmount,
    decimal? MaximumAmount,
    decimal DataQualityScore,
    string? SourceName,
    string? SourceUrl,
    DateTimeOffset? PublishedAtUtc,
    DateTimeOffset? LastVerifiedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    byte[] RowVersion);

public sealed record FundingOpportunityAdminDetails(
    Guid PublicId,
    string Slug,
    FundingOpportunityEditorialData Data,
    FundingPublicationStatus PublicationStatus,
    bool IsActive,
    int ContentVersion,
    decimal DataQualityScore,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    byte[] RowVersion,
    IReadOnlyList<FundingOpportunityFunder> Funders,
    IReadOnlyList<FundingFieldEvidence> Evidence,
    IReadOnlyList<FundingOpportunitySourceLink> SourceLinks,
    DateTimeOffset? SubmittedAtUtc,
    DateTimeOffset? ReviewedAtUtc,
    Guid? ReviewedByUserPublicId,
    DateTimeOffset? PublishedAtUtc,
    string? RejectionReason);

public sealed record FundingOpportunityAdminPage(
    IReadOnlyList<FundingOpportunityAdminSummary> Items,
    long TotalCount,
    int PageNumber,
    int PageSize);

public sealed record FundingReadinessIssue(
    string Code,
    string FieldPath,
    string Message);

public sealed record FundingEditorialMutation(
    bool Succeeded,
    string Code,
    Guid EntityPublicId,
    FundingPublicationStatus PublicationStatus,
    int ContentVersion,
    byte[] RowVersion,
    bool WasReplay,
    IReadOnlyList<FundingReadinessIssue> Issues,
    DateTimeOffset? SubmittedAtUtc = null,
    DateTimeOffset? ReviewedAtUtc = null,
    Guid? ReviewedByUserPublicId = null,
    DateTimeOffset? PublishedAtUtc = null,
    string? RejectionReason = null);
