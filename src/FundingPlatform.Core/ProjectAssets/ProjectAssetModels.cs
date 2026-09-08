namespace FundingPlatform.Core.ProjectAssets;

public enum ProjectAssetKind : byte
{
    Image = 0,
    Document = 1,
    Video = 2
}

public enum ProjectAssetUploadIntentStatus : byte
{
    Pending = 0,
    Finalizing = 1,
    Completed = 2,
    Expired = 3,
    Rejected = 4
}

public enum ProjectAssetStorageStatus : byte
{
    AwaitingQuarantine = 0,
    Quarantined = 1,
    Trusted = 2,
    Failed = 3
}

public enum ProjectAssetScanStatus : byte
{
    Pending = 0,
    Clean = 1,
    Malicious = 2,
    Failed = 3,
    TimedOut = 4
}

public enum ProjectAssetScanProvider : byte
{
    DevelopmentFake = 0,
    MicrosoftDefender = 1
}

public sealed record ProjectAsset(
    Guid PublicId,
    ProjectAssetKind Kind,
    string OriginalFileName,
    string DisplayName,
    string MimeType,
    long ContentLength,
    int? PixelWidth,
    int? PixelHeight,
    ProjectAssetStorageStatus StorageStatus,
    ProjectAssetScanStatus ScanStatus,
    ProjectAssetScanProvider ScanProvider,
    string? ScanResultCode,
    short SortOrder,
    bool IsCover,
    string? AltText,
    string? Caption,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    byte[] RowVersion)
{
    public bool IsReady =>
        StorageStatus == ProjectAssetStorageStatus.Trusted &&
        ScanStatus == ProjectAssetScanStatus.Clean;
}

public sealed record ProjectAssetCollection(
    Guid ProjectPublicId,
    byte PublicationStatus,
    byte[] ProjectRowVersion,
    IReadOnlyList<ProjectAsset> Items);

public sealed record ProjectAssetUploadIntent(
    Guid PublicId,
    Guid ProjectPublicId,
    ProjectAssetKind Kind,
    string OriginalFileName,
    string DeclaredMimeType,
    long ExpectedContentLength,
    long MaxContentLength,
    ProjectAssetUploadIntentStatus Status,
    DateTimeOffset ExpiresAtUtc,
    Guid? AssetPublicId,
    ProjectAssetStorageStatus? StorageStatus,
    ProjectAssetScanStatus? ScanStatus,
    ProjectAssetScanProvider? ScanProvider,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    byte[] RowVersion);

public sealed record ProjectAssetMutation(
    bool Succeeded,
    string Code,
    Guid? IntentPublicId = null,
    ProjectAssetUploadIntentStatus? IntentStatus = null,
    Guid? AssetPublicId = null,
    ProjectAssetStorageStatus? StorageStatus = null,
    ProjectAssetScanStatus? ScanStatus = null,
    ProjectAssetScanProvider? ScanProvider = null,
    byte[]? IntentRowVersion = null,
    byte[]? AssetRowVersion = null,
    byte[]? ProjectRowVersion = null,
    DateTimeOffset? ExpiresAtUtc = null,
    bool WasReplay = false,
    string? RevokedTrustedBlobContainer = null,
    string? RevokedTrustedBlobObjectName = null,
    string? RevokedTrustedBlobETag = null,
    string? RevokedTrustedBlobVersionId = null,
    string? RevokedTrustedMimeType = null,
    long? RevokedTrustedContentLength = null,
    byte[]? RevokedTrustedContentHash = null,
    int? RevokedTrustedPixelWidth = null,
    int? RevokedTrustedPixelHeight = null,
    string? RevokedTrustedProcessingVersion = null,
    DateTimeOffset? RevokedTrustedCreatedAtUtc = null);

public enum ProjectAssetOutcome
{
    Success,
    Processing,
    Disabled,
    ValidationFailed,
    NotFound,
    Forbidden,
    Conflict,
    InvalidState,
    Expired,
    Unavailable
}

public sealed record ProjectAssetOperationResult(
    ProjectAssetOutcome Outcome,
    string Code,
    Guid? IntentPublicId = null,
    ProjectAssetUploadIntentStatus? IntentStatus = null,
    Guid? AssetPublicId = null,
    ProjectAssetStorageStatus? StorageStatus = null,
    ProjectAssetScanStatus? ScanStatus = null,
    ProjectAssetScanProvider? ScanProvider = null,
    byte[]? IntentRowVersion = null,
    byte[]? AssetRowVersion = null,
    byte[]? ProjectRowVersion = null,
    bool WasReplay = false,
    IReadOnlyDictionary<string, string[]>? Errors = null);

public sealed record ProjectAssetMetadata(
    string DisplayName,
    string? AltText,
    string? Caption,
    bool IsCover);

public sealed record ProjectAssetOrderItem(
    Guid AssetPublicId,
    byte[] ExpectedRowVersion,
    short SortOrder);
