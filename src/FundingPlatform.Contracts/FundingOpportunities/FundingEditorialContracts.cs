namespace FundingPlatform.Contracts.FundingOpportunities;

public sealed record FundingDuplicateDecisionRequest(
    string Decision,
    Guid? CanonicalOpportunityId,
    string Reason);

public sealed record FundingDuplicateCandidateListResponse(
    IReadOnlyList<FundingDuplicateCandidateSummaryResponse> Items,
    long TotalCount,
    int Page,
    int PageSize);

public sealed record FundingDuplicateCandidateSummaryResponse(
    Guid CandidateId,
    Guid CandidateOpportunityId,
    string CandidateTitle,
    string CandidateSponsor,
    Guid? SuggestedCanonicalOpportunityId,
    string? SuggestedCanonicalTitle,
    byte MatchKind,
    string MatchReasonCode,
    decimal Confidence,
    byte Status,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? DecidedAtUtc,
    string ETag);

public sealed record FundingDuplicateOpportunityPreviewResponse(
    Guid OpportunityId,
    string Title,
    string Sponsor,
    byte PublicationStatus);

public sealed record FundingDuplicateDecisionViewResponse(
    Guid DecisionId,
    byte Decision,
    Guid? CanonicalOpportunityId,
    string Reason,
    DateTimeOffset CreatedAtUtc);

public sealed record FundingDuplicateCandidateDetailResponse(
    Guid CandidateId,
    FundingDuplicateOpportunityPreviewResponse Candidate,
    FundingDuplicateOpportunityPreviewResponse? SuggestedCanonical,
    byte MatchKind,
    string MatchReasonCode,
    decimal Confidence,
    byte Status,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? DecidedAtUtc,
    FundingDuplicateDecisionViewResponse? Decision,
    string ETag);

public sealed record FundingDuplicateDecisionResponse(
    Guid CandidateId,
    Guid DecisionId,
    byte Status,
    byte Decision,
    Guid? CanonicalOpportunityId,
    DateTimeOffset? DecidedAtUtc,
    string ETag,
    bool WasReplay);

public sealed record FunderWriteRequest(
    string Name,
    string? Description,
    string? WebsiteUrl,
    short? CountryId,
    IReadOnlyList<string>? Aliases);

public sealed record FunderListResponse(
    IReadOnlyList<FunderAdminSummaryResponse> Items,
    long TotalCount,
    int Page,
    int PageSize);

public sealed record FunderAdminSummaryResponse(
    Guid FunderId,
    string Slug,
    string Name,
    string? Description,
    string? WebsiteUrl,
    short? CountryId,
    string? CountryCode,
    string? CountryName,
    byte PublicationStatus,
    bool IsActive,
    int ContentVersion,
    DateTimeOffset UpdatedAtUtc,
    string ETag);

public sealed record FunderAdminDetailResponse(
    Guid FunderId,
    string Slug,
    string Name,
    string? Description,
    string? WebsiteUrl,
    short? CountryId,
    string? CountryCode,
    string? CountryName,
    byte PublicationStatus,
    bool IsActive,
    int ContentVersion,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    string ETag,
    IReadOnlyList<string> Aliases,
    DateTimeOffset? SubmittedAtUtc,
    DateTimeOffset? ReviewedAtUtc,
    Guid? ReviewedByUserId,
    DateTimeOffset? PublishedAtUtc,
    string? RejectionReason,
    IReadOnlyList<FunderOpportunitySummaryResponse> Opportunities);

public sealed record FunderOpportunitySummaryResponse(
    Guid OpportunityId,
    string Slug,
    string Title,
    byte Role,
    byte PublicationStatus,
    bool IsActive);

public sealed record FundingOpportunityFunderWriteRequest(
    Guid FunderId,
    byte Role);

public sealed record FundingOpportunityWriteRequest(
    string Title,
    string? Summary,
    string? Description,
    string SponsorName,
    string? SponsorUrl,
    string? ApplicationUrl,
    IReadOnlyList<FundingOpportunityFunderWriteRequest>? Funders,
    int FundingSourceId,
    string? ExternalId,
    string SourceUrl,
    short? IssuerCountryId,
    short? FundingTypeId,
    string? Currency,
    decimal? MinimumAmount,
    decimal? MaximumAmount,
    byte? AmountStatus,
    DateOnly? OpenDate,
    DateOnly? CloseDate,
    DateTimeOffset? CloseAtUtc,
    string? DeadlineTimeZoneId,
    byte? DeadlineType,
    byte? DeadlinePrecision,
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
    byte? GeographicScope,
    byte? RemoteApplication,
    DateTimeOffset? LastVerifiedAtUtc,
    IReadOnlyList<short>? CountryIds,
    IReadOnlyList<int>? RegionIds,
    IReadOnlyList<int>? CategoryIds,
    IReadOnlyList<int>? BeneficiaryTypeIds,
    IReadOnlyList<int>? ProjectTypeIds);

public sealed record FundingOpportunityAdminListResponse(
    IReadOnlyList<FundingOpportunityAdminSummaryResponse> Items,
    long TotalCount,
    int Page,
    int PageSize);

public sealed record FundingOpportunityAdminSummaryResponse(
    Guid OpportunityId,
    string Slug,
    string Title,
    string? Summary,
    string SponsorName,
    byte PublicationStatus,
    bool IsActive,
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
    int ContentVersion,
    DateTimeOffset UpdatedAtUtc,
    string ETag);

public sealed record FundingOpportunityAdminDetailResponse(
    Guid OpportunityId,
    string Slug,
    string Title,
    string? Summary,
    string? Description,
    string SponsorName,
    string? SponsorUrl,
    string? ApplicationUrl,
    int FundingSourceId,
    string? ExternalId,
    string SourceUrl,
    short? IssuerCountryId,
    short? FundingTypeId,
    string? Currency,
    decimal? MinimumAmount,
    decimal? MaximumAmount,
    byte AmountStatus,
    DateOnly? OpenDate,
    DateOnly? CloseDate,
    DateTimeOffset? CloseAtUtc,
    string? DeadlineTimeZoneId,
    byte DeadlineType,
    byte DeadlinePrecision,
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
    byte GeographicScope,
    byte RemoteApplication,
    DateTimeOffset? LastVerifiedAtUtc,
    IReadOnlyList<short> CountryIds,
    IReadOnlyList<int> RegionIds,
    IReadOnlyList<int> CategoryIds,
    IReadOnlyList<int> BeneficiaryTypeIds,
    IReadOnlyList<int> ProjectTypeIds,
    IReadOnlyList<FundingOpportunityFunderResponse> Funders,
    IReadOnlyList<FundingFieldEvidenceResponse> Evidence,
    IReadOnlyList<FundingOpportunitySourceResponse> Sources,
    byte PublicationStatus,
    bool IsActive,
    int ContentVersion,
    decimal DataQualityScore,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    string ETag,
    DateTimeOffset? SubmittedAtUtc,
    DateTimeOffset? ReviewedAtUtc,
    Guid? ReviewedByUserId,
    DateTimeOffset? PublishedAtUtc,
    string? RejectionReason);

public sealed record FundingOpportunityFunderResponse(
    Guid FunderId,
    string Slug,
    string Name,
    byte Role);

public sealed record FundingFieldEvidenceResponse(
    Guid EvidenceId,
    string FieldPath,
    string ValueJson,
    byte ExtractionMethod,
    string? EvidenceText,
    string? SourceLocator,
    decimal? Confidence,
    bool IsSelected,
    bool IsManualLock,
    Guid? CreatedByUserId,
    DateTimeOffset CreatedAtUtc);

public sealed record FundingOpportunitySourceResponse(
    int FundingSourceId,
    string SourceName,
    string? ExternalId,
    string SourceUrl,
    DateTimeOffset FirstSeenAtUtc,
    DateTimeOffset LastSeenAtUtc,
    bool IsPrimary,
    bool IsActive);

public sealed record FundingEditorialReviewRequest(
    string Decision,
    string? Reason);

public sealed record FundingEditorialDeactivateRequest(string? Reason);

public sealed record FundingEditorialStartCorrectionRequest(string Reason);

public sealed record FundingEditorialMutationResponse(
    Guid EntityId,
    byte PublicationStatus,
    int ContentVersion,
    string ETag,
    bool WasReplay);

public sealed record PublicFunderListResponse(
    IReadOnlyList<PublicFunderSummaryResponse> Items,
    long TotalCount,
    int Page,
    int PageSize);

public sealed record PublicFunderSummaryResponse(
    Guid FunderId,
    string Slug,
    string Name,
    string? Description,
    string? WebsiteUrl,
    string? CountryCode,
    string? CountryName);

public sealed record PublicFunderDetailResponse(
    Guid FunderId,
    string Slug,
    string Name,
    string? Description,
    string? WebsiteUrl,
    string? CountryCode,
    string? CountryName,
    IReadOnlyList<string> Aliases,
    DateTimeOffset PublishedAtUtc,
    IReadOnlyList<PublicFunderOpportunityResponse> Opportunities);

public sealed record PublicFunderOpportunityResponse(
    Guid OpportunityId,
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

public sealed record FundingSourceAdminResponse(
    int Id,
    string Name,
    byte ProviderType,
    string? BaseUrl,
    bool IsEnabled,
    string? ProviderCode,
    string ComplianceStatus,
    DateTimeOffset? NextRunAtUtc,
    DateTimeOffset? LastSuccessfulRunAtUtc,
    byte LicenseStatus,
    string? LicenseName,
    string? LicenseUrl,
    DateTimeOffset? LicenseReviewedAtUtc,
    DateTimeOffset? LicenseExpiresAtUtc,
    byte RobotsPolicyStatus,
    DateTimeOffset? RobotsReviewedAtUtc,
    DateTimeOffset? RobotsExpiresAtUtc,
    int? RequestRateLimitPerMinute,
    int? MaximumResponseBytes,
    short? ContentRetentionDays,
    bool AllowedHostsRequired,
    int AcquisitionPolicyVersion,
    int EnabledAllowedHostCount,
    bool AcquisitionReady);
