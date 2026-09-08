namespace FundingPlatform.Contracts.ProjectAssets;

public sealed record CreateProjectAssetUploadIntentRequest(
    byte Kind,
    string? FileName,
    string? MimeType,
    long ContentLength);

public sealed record ProjectAssetUploadIntentCreatedResponse(
    Guid IntentId,
    byte Kind,
    byte Status,
    DateTimeOffset ExpiresAtUtc,
    long MaxContentLength,
    string UploadMethod,
    Uri UploadUrl,
    IReadOnlyDictionary<string, string> RequiredHeaders,
    string CompletionToken,
    string StatusUrl,
    string ETag,
    string ProjectETag,
    string SecurityNotice);

public sealed record CompleteProjectAssetUploadIntentRequest(string? CompletionToken);

public sealed record ProjectAssetUploadIntentResponse(
    Guid IntentId,
    Guid ProjectId,
    byte Kind,
    string FileName,
    string DeclaredMimeType,
    long ExpectedContentLength,
    long MaxContentLength,
    byte Status,
    DateTimeOffset ExpiresAtUtc,
    Guid? AssetId,
    byte? StorageStatus,
    byte? ScanStatus,
    byte? ScanProvider,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    string ETag);

public sealed record ProjectAssetResponse(
    Guid AssetId,
    byte Kind,
    string FileName,
    string DisplayName,
    string MimeType,
    long ContentLength,
    int? PixelWidth,
    int? PixelHeight,
    byte StorageStatus,
    byte ScanStatus,
    byte ScanProvider,
    string? ScanResultCode,
    short SortOrder,
    bool IsCover,
    string? AltText,
    string? Caption,
    bool IsReady,
    string? ContentUrl,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    string ETag);

public sealed record ProjectAssetCollectionResponse(
    Guid ProjectId,
    byte PublicationStatus,
    string ProjectETag,
    IReadOnlyList<ProjectAssetResponse> Items);

public sealed record ProjectAssetOperationResponse(
    string Code,
    Guid? IntentId,
    byte? IntentStatus,
    Guid? AssetId,
    byte? StorageStatus,
    byte? ScanStatus,
    byte? ScanProvider,
    string? IntentETag,
    string? AssetETag,
    string? ProjectETag,
    bool WasReplay);

public sealed record UpdateProjectAssetMetadataRequest(
    string? DisplayName,
    string? AltText,
    string? Caption,
    bool IsCover);

public sealed record ReorderProjectAssetsRequest(
    IReadOnlyList<ReorderProjectAssetItemRequest>? Items);

public sealed record ReorderProjectAssetItemRequest(
    Guid AssetId,
    string? ETag);
