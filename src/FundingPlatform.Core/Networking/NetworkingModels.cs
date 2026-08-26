namespace FundingPlatform.Core.Networking;

public enum ConnectionPurpose : byte
{
    Partnership = 0,
    Expertise = 1,
    GeographicReach = 2,
    ConsortiumExploration = 3
}

public enum OrganizationConnectionStatus : byte
{
    Pending = 0,
    Accepted = 1,
    Rejected = 2,
    Cancelled = 3,
    Blocked = 4
}

public enum ConnectionDirection : byte
{
    All = 0,
    Incoming = 1,
    Outgoing = 2
}

public enum DirectoryConnectionState : byte
{
    None = 0,
    PendingOutgoing = 1,
    PendingIncoming = 2,
    Connected = 3
}

public sealed record NetworkingPreference(
    bool Exists,
    bool IsDiscoverable,
    bool AllowRequests,
    DateTimeOffset? CreatedAtUtc,
    DateTimeOffset? UpdatedAtUtc,
    string? ETag);

public sealed record NetworkCatalogItem<TId>(TId Id, string Code, string Name);

public sealed record NetworkDirectoryFilters(
    string? Query,
    IReadOnlyList<short> CountryIds,
    IReadOnlyList<int> CategoryIds,
    IReadOnlyList<int> ProjectTypeIds,
    int PageNumber,
    int PageSize);

public sealed record NetworkDirectoryOrganization(
    Guid PublicId,
    string Name,
    string? Description,
    string? WebsiteUrl,
    NetworkCatalogItem<short> HomeCountry,
    NetworkCatalogItem<short> OrganizationType,
    int VisibleProjectCount,
    bool AllowsRequests,
    Guid? ConnectionPublicId,
    DirectoryConnectionState ConnectionState,
    IReadOnlyList<NetworkCatalogItem<int>> Categories,
    IReadOnlyList<NetworkCatalogItem<int>> ProjectTypes);

public sealed record NetworkDirectoryPage(
    IReadOnlyList<NetworkDirectoryOrganization> Items,
    long TotalCount,
    int PageNumber,
    int PageSize);

public sealed record OrganizationConnection(
    Guid PublicId,
    ConnectionDirection Direction,
    OrganizationConnectionStatus Status,
    ConnectionPurpose Purpose,
    string Message,
    Guid CounterpartyOrganizationPublicId,
    string CounterpartyOrganizationName,
    bool CounterpartyIsPublic,
    Guid? RequesterProjectPublicId,
    string? RequesterProjectSlug,
    string? RequesterProjectTitle,
    bool CanRespond,
    bool CanCancel,
    bool CanBlock,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    DateTimeOffset? ActionedAtUtc,
    string ETag);

public sealed record OrganizationConnectionPage(
    IReadOnlyList<OrganizationConnection> Items,
    long TotalCount,
    int PageNumber,
    int PageSize);

public enum NetworkingMutationOutcome
{
    Created,
    Updated,
    Replay,
    NotFound,
    Forbidden,
    ValidationFailed,
    PreconditionRequired,
    PreconditionFailed,
    IdempotencyConflict,
    AlreadyExists,
    NetworkingDisabled,
    RateLimited,
    InvalidTransition
}

public sealed record NetworkingPreferenceMutation(
    NetworkingMutationOutcome Outcome,
    NetworkingPreference? Preference = null);

public sealed record OrganizationConnectionMutation(
    NetworkingMutationOutcome Outcome,
    OrganizationConnection? Connection = null,
    IReadOnlyDictionary<string, string[]>? Errors = null);
