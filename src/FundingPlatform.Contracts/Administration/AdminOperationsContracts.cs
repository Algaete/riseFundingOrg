namespace FundingPlatform.Contracts.Administration;

public sealed record AdminOrganizationSummaryResponse(
    Guid publicId,
    string name,
    string countryCode,
    string countryName,
    string organizationTypeName,
    byte profileStatus,
    decimal profileCompleteness,
    bool isActive,
    long memberCount,
    long projectCount,
    string planCode,
    string planName,
    byte? subscriptionStatus,
    DateTimeOffset createdAtUtc,
    DateTimeOffset updatedAtUtc);

public sealed record AdminOrganizationPageResponse(
    IReadOnlyList<AdminOrganizationSummaryResponse> items,
    long totalCount,
    int page,
    int pageSize);

public sealed record AdminOrganizationDetailResponse(
    Guid publicId,
    string name,
    string? legalName,
    string countryCode,
    string countryName,
    string organizationTypeName,
    string? legalEntityTypeName,
    string? organizationSizeName,
    int? establishedYear,
    string? websiteUrl,
    string? description,
    byte profileStatus,
    decimal profileCompleteness,
    int profileVersion,
    bool isActive,
    long memberCount,
    long adminMemberCount,
    long projectCount,
    long publishedProjectCount,
    string planCode,
    string planName,
    byte? subscriptionStatus,
    DateTimeOffset? currentPeriodEndUtc,
    DateTimeOffset createdAtUtc,
    DateTimeOffset updatedAtUtc);

public sealed record AdminOperationalErrorResponse(
    string id,
    string category,
    byte severity,
    string code,
    string message,
    bool isRetryable,
    DateTimeOffset occurredAtUtc,
    Guid? relatedResourcePublicId,
    string? sourceName);

public sealed record AdminOperationalErrorPageResponse(
    IReadOnlyList<AdminOperationalErrorResponse> items,
    long totalCount,
    int page,
    int pageSize);
