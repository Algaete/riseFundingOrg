namespace FundingPlatform.Contracts.Organizations;

public sealed record OrganizationVerificationDecisionRequest(
    int? Status,
    string? Reason,
    int? ExpectedRevision,
    int? ExpectedProfileVersion);

public sealed record OrganizationVerificationResponse(
    Guid OrganizationPublicId,
    string Name,
    byte Status,
    byte RecordedStatus,
    int Revision,
    int ProfileVersion,
    int? ReviewedProfileVersion,
    DateTimeOffset? ReviewedAtUtc,
    Guid? ReviewedByUserPublicId,
    string? ReviewedByName,
    string? Reason,
    bool NeedsReverification,
    IReadOnlyList<OrganizationVerificationHistoryResponse> History);

public sealed record OrganizationVerificationHistoryResponse(
    int Revision,
    byte Status,
    int ProfileVersion,
    string Reason,
    DateTimeOffset ReviewedAtUtc,
    Guid ReviewedByUserPublicId,
    string? ReviewedByName);
