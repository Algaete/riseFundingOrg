namespace FundingPlatform.Core.Organizations;

/// <summary>
/// Private administrative review. This is independent of profile completeness
/// and does not grant or revoke any organization permission.
/// </summary>
public sealed record OrganizationVerification(
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
    IReadOnlyList<OrganizationVerificationHistoryEntry> History)
{
    // SQL JSON can omit an empty collection or return null. Always expose [].
    public IReadOnlyList<OrganizationVerificationHistoryEntry> History { get; init; } = History ?? [];

    public OrganizationVerification WithEffectiveStatus()
    {
        var stale = RecordedStatus != 0 && ReviewedProfileVersion != ProfileVersion;
        return this with { Status = stale ? (byte)0 : RecordedStatus, NeedsReverification = stale };
    }
}

public sealed record OrganizationVerificationHistoryEntry(
    int Revision,
    byte Status,
    int ProfileVersion,
    string Reason,
    DateTimeOffset ReviewedAtUtc,
    Guid ReviewedByUserPublicId,
    string? ReviewedByName);

public sealed record OrganizationVerificationDecision(
    int Status,
    string? Reason,
    int ExpectedRevision,
    int ExpectedProfileVersion);
