namespace FundingPlatform.Contracts.Networking;

public sealed record NetworkingPreferenceResponse(
    bool Exists,
    bool IsDiscoverable,
    bool AllowRequests,
    DateTimeOffset? CreatedAtUtc,
    DateTimeOffset? UpdatedAtUtc,
    string? ETag);

public sealed record NetworkingPreferenceWriteRequest(
    bool IsDiscoverable,
    bool AllowRequests);

public sealed record NetworkCatalogItemResponse<TId>(TId Id, string Code, string Name);

public sealed record NetworkDirectoryOrganizationResponse(
    Guid Id,
    string Name,
    string? Description,
    string? WebsiteUrl,
    NetworkCatalogItemResponse<short> HomeCountry,
    NetworkCatalogItemResponse<short> OrganizationType,
    int VisibleProjectCount,
    bool AllowsRequests,
    Guid? ConnectionId,
    string ConnectionState,
    IReadOnlyList<NetworkCatalogItemResponse<int>> Categories,
    IReadOnlyList<NetworkCatalogItemResponse<int>> ProjectTypes);

public sealed record NetworkDirectoryPageResponse(
    IReadOnlyList<NetworkDirectoryOrganizationResponse> Items,
    long TotalCount,
    int Page,
    int PageSize);

public sealed record OrganizationConnectionCreateRequest(
    Guid RecipientOrganizationId,
    Guid? RequesterProjectId,
    string Purpose,
    string Message);

public sealed record OrganizationConnectionActionRequest(string Action);

public sealed record OrganizationConnectionResponse(
    Guid Id,
    string Direction,
    string Status,
    string Purpose,
    string Message,
    Guid CounterpartyOrganizationId,
    string CounterpartyOrganizationName,
    bool CounterpartyIsPublic,
    Guid? RequesterProjectId,
    string? RequesterProjectSlug,
    string? RequesterProjectTitle,
    bool CanRespond,
    bool CanCancel,
    bool CanBlock,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    DateTimeOffset? ActionedAtUtc,
    string ETag);

public sealed record OrganizationConnectionPageResponse(
    IReadOnlyList<OrganizationConnectionResponse> Items,
    long TotalCount,
    int Page,
    int PageSize);
