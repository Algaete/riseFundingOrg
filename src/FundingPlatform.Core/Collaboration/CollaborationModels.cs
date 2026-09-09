namespace FundingPlatform.Core.Collaboration;

public sealed record ProfessionalProfileData(
    string DisplayName, string Headline, string? Biography, short? CountryId,
    IReadOnlyList<string>? Skills, IReadOnlyList<short>? LanguageIds,
    IReadOnlyList<int>? CategoryIds, bool IsDiscoverable = false, bool AllowsInvitations = false);
public sealed record ProfessionalProfile(Guid ProfileId, ProfessionalProfileData Data, string ETag, DateTimeOffset UpdatedAtUtc);
public sealed record ProfessionalDirectoryEntry(Guid ProfileId, ProfessionalProfileData Data);
public sealed record CollaborationPage<T>(IReadOnlyList<T> Items, long TotalCount, int Page, int PageSize);
public sealed record ProfessionalDirectoryFilters(string? Query = null, short? CountryId = null, int? CategoryId = null, int Page = 1, int PageSize = 20);

public enum ConsortiumStatus : byte { Forming = 0, Active = 1, Closed = 2 }
public enum ConsortiumParticipantKind : byte { Organization = 1, Professional = 2 }
public enum ConsortiumParticipantStatus : byte { Invited = 0, Accepted = 1, Rejected = 2, Cancelled = 3, Left = 4, Removed = 5 }
public sealed record ConsortiumCreateData(Guid ProjectId, string Name, string? Summary);
public sealed record ConsortiumUpdateData(string Name, string? Summary, ConsortiumStatus Status);
public sealed record ConsortiumInvitationData(ConsortiumParticipantKind Kind, Guid TargetId, string Contribution, string Message);
public sealed record ConsortiumSummary(Guid ConsortiumId, Guid ProjectId, string? ProjectTitle, string? ProjectSlug,
    bool ProjectIsPublic, string Name, string? Summary, Guid LeadOrganizationId, string LeadOrganizationName, ConsortiumStatus Status,
    bool CanManage, bool CanViewRoster, bool HasPendingInvitation, int AcceptedCount, string ETag, DateTimeOffset UpdatedAtUtc);
public sealed record ConsortiumParticipant(Guid ParticipantId, ConsortiumParticipantKind Kind, Guid TargetId,
    string DisplayName, string Contribution, string Message, ConsortiumParticipantStatus Status,
    bool CanRespond, bool CanLeave, bool CanCancel, bool CanRemove, string ETag, DateTimeOffset UpdatedAtUtc);
public sealed record ConsortiumDetails(ConsortiumSummary Consortium, IReadOnlyList<ConsortiumParticipant> Participants);
public sealed record CollaborationWriteResult(Guid EntityId, string ETag, bool WasReplay);

public static class ConsortiumStateMachine
{
    public static bool CanTransition(ConsortiumStatus current, ConsortiumStatus next, int acceptedCount) =>
        Enum.IsDefined(current) && Enum.IsDefined(next) && current != ConsortiumStatus.Closed &&
        (current == next || next == ConsortiumStatus.Closed ||
         current == ConsortiumStatus.Forming && next == ConsortiumStatus.Active && acceptedCount > 0);

    public static bool CanAct(ConsortiumParticipantStatus current, ConsortiumParticipantStatus action,
        bool isManager, bool isRecipient, bool isClosed) => action switch
    {
        ConsortiumParticipantStatus.Accepted => isRecipient && !isClosed && current == ConsortiumParticipantStatus.Invited,
        ConsortiumParticipantStatus.Rejected => isRecipient && current == ConsortiumParticipantStatus.Invited,
        ConsortiumParticipantStatus.Cancelled => isManager && current == ConsortiumParticipantStatus.Invited,
        ConsortiumParticipantStatus.Left => isRecipient && current == ConsortiumParticipantStatus.Accepted,
        ConsortiumParticipantStatus.Removed => isManager && current == ConsortiumParticipantStatus.Accepted,
        _ => false
    };
}
