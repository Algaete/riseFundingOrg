using FundingPlatform.Core.ProjectAssets;

namespace FundingPlatform.Application.ProjectAssets;

public sealed record ProjectAssetPolicy(
    bool Enabled,
    Uri? BlobServiceUri,
    string IncomingContainer,
    string QuarantineContainer,
    string TrustedContainer,
    long MaxImageBytes,
    long MaxDocumentBytes,
    long MaxProjectBytes,
    int MaxImagePixels,
    TimeSpan UploadTimeToLive,
    TimeSpan FinalizeLease,
    TimeSpan ScanTimeout,
    ProjectAssetScanProvider ScanProvider);

public sealed class ProtectedProjectAssetBlobLocation(string container, string objectName)
{
    public string Container { get; } = container;
    public string ObjectName { get; } = objectName;

    public override string ToString() => "[protected project asset location]";
}

public sealed class ProjectAssetCompletionSecret(string token, byte[] hash)
{
    public string Token { get; } = token;
    public byte[] Hash { get; } = hash;

    public override string ToString() => "[redacted project asset completion secret]";
}

public sealed class ProjectAssetUploadGrant(
    Uri uploadUri,
    DateTimeOffset expiresAtUtc,
    IReadOnlyDictionary<string, string> requiredHeaders)
{
    public Uri UploadUri { get; } = uploadUri;
    public DateTimeOffset ExpiresAtUtc { get; } = expiresAtUtc;
    public IReadOnlyDictionary<string, string> RequiredHeaders { get; } = requiredHeaders;

    public override string ToString() => "[redacted project asset upload grant]";
}

public sealed class ProjectAssetBlobRead(
    Stream content,
    long contentLength,
    string? contentType,
    string eTag,
    string? versionId) : IAsyncDisposable
{
    public Stream Content { get; } = content;
    public long ContentLength { get; } = contentLength;
    public string? ContentType { get; } = contentType;
    public string ETag { get; } = eTag;
    public string? VersionId { get; } = versionId;

    public ValueTask DisposeAsync() => Content.DisposeAsync();

    public override string ToString() => "[protected project asset blob read]";
}

public sealed record ProjectAssetBlobReceipt(string ETag, string? VersionId);

public enum ProjectAssetInspectionFailure
{
    None,
    TooLarge,
    LengthMismatch,
    InvalidContentType,
    InvalidFile,
    ImageTooLarge
}

public sealed record ProjectAssetInspection(
    bool IsValid,
    ProjectAssetInspectionFailure Failure,
    long ActualLength,
    byte[]? ContentHash,
    string? VerifiedMimeType,
    int? PixelWidth = null,
    int? PixelHeight = null);

public sealed record ProjectAssetScanObservation(
    ProjectAssetScanStatus Status,
    string ResultCode,
    string ObservationKey,
    DateTimeOffset ObservedAtUtc)
{
    public bool IsPending => Status == ProjectAssetScanStatus.Pending;
}

public sealed class ProjectAssetFinalizeWork
{
    public bool Succeeded { get; init; }
    public string Code { get; init; } = string.Empty;
    public Guid IntentPublicId { get; init; }
    public ProjectAssetUploadIntentStatus IntentStatus { get; init; }
    public Guid? AssetPublicId { get; init; }
    public ProjectAssetKind Kind { get; init; }
    public string OriginalFileName { get; init; } = string.Empty;
    public string DeclaredMimeType { get; init; } = string.Empty;
    public long? ExpectedContentLength { get; init; }
    public long? MaxContentLength { get; init; }
    public ProtectedProjectAssetBlobLocation? IncomingLocation { get; init; }
    public ProtectedProjectAssetBlobLocation? QuarantineLocation { get; init; }
    public ProtectedProjectAssetBlobLocation? TrustedLocation { get; init; }
    public Guid? FinalizeLeaseId { get; init; }
    public DateTimeOffset? FinalizeLeaseUntilUtc { get; init; }
    public long? ActualContentLength { get; init; }
    public byte[]? ContentHash { get; init; }
    public string? VerifiedMimeType { get; init; }
    public string? QuarantineBlobETag { get; init; }
    public string? QuarantineBlobVersionId { get; init; }
    public ProjectAssetStorageStatus? StorageStatus { get; init; }
    public ProjectAssetScanStatus? ScanStatus { get; init; }
    public ProjectAssetScanProvider? ScanProvider { get; init; }
    public byte[]? AssetRowVersion { get; init; }
    public byte[]? IntentRowVersion { get; init; }
    public byte[]? ProjectRowVersion { get; init; }
    public bool WasReplay { get; init; }
}

public sealed record ProjectAssetTrustedContent(
    Guid AssetPublicId,
    ProjectAssetKind Kind,
    string FileName,
    string MimeType,
    long ContentLength,
    byte[] ContentHash,
    ProtectedProjectAssetBlobLocation Location,
    string BlobETag,
    string? BlobVersionId);

public interface IProjectAssetCompletionTokenService
{
    ProjectAssetCompletionSecret Create();
    bool TryHash(string token, out byte[] hash);
}

public interface IProjectAssetBlobStore
{
    Task<ProjectAssetUploadGrant> CreateUploadGrantAsync(
        ProtectedProjectAssetBlobLocation destination,
        string contentType,
        DateTimeOffset expiresAtUtc,
        CancellationToken cancellationToken);

    Task<ProjectAssetBlobRead> OpenReadAsync(
        ProtectedProjectAssetBlobLocation source,
        string? expectedETag,
        CancellationToken cancellationToken);

    Task<ProjectAssetBlobReceipt> EnsureCopyAsync(
        ProtectedProjectAssetBlobLocation source,
        string sourceETag,
        ProtectedProjectAssetBlobLocation destination,
        string contentType,
        long expectedLength,
        byte[] expectedContentHash,
        CancellationToken cancellationToken);

    Task DeleteIfMatchAsync(
        ProtectedProjectAssetBlobLocation location,
        string? expectedETag,
        CancellationToken cancellationToken);
}

public interface IProjectAssetContentInspector
{
    Task<ProjectAssetInspection> InspectAsync(
        ProjectAssetKind kind,
        ProjectAssetBlobRead source,
        long expectedLength,
        long maximumLength,
        int maximumImagePixels,
        CancellationToken cancellationToken);
}

public interface IProjectAssetScanner
{
    Task<ProjectAssetScanObservation> ObserveAsync(
        Guid assetPublicId,
        ProtectedProjectAssetBlobLocation quarantineLocation,
        string quarantineETag,
        CancellationToken cancellationToken);
}

public interface IProjectAssetRepository
{
    Task<ProjectAssetMutation> CreateUploadIntentAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        byte[] expectedProjectRowVersion,
        ProjectAssetKind kind,
        string originalFileName,
        string declaredMimeType,
        long expectedContentLength,
        long maxContentLength,
        ProtectedProjectAssetBlobLocation incomingLocation,
        ProtectedProjectAssetBlobLocation quarantineLocation,
        ProtectedProjectAssetBlobLocation trustedLocation,
        byte[] completionTokenHash,
        DateTimeOffset expiresAtUtc,
        CancellationToken cancellationToken);

    Task<ProjectAssetFinalizeWork> AcquireFinalizeAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid intentPublicId,
        byte[] completionTokenHash,
        Guid leaseId,
        DateTimeOffset leaseUntilUtc,
        CancellationToken cancellationToken);

    Task<ProjectAssetMutation> ReleaseFinalizeAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid intentPublicId,
        Guid leaseId,
        string errorCode,
        CancellationToken cancellationToken);

    Task<ProjectAssetMutation> RejectFinalizeAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid intentPublicId,
        Guid leaseId,
        string errorCode,
        CancellationToken cancellationToken);

    Task<ProjectAssetMutation> CompleteUploadIntentAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid intentPublicId,
        Guid leaseId,
        byte[] expectedProjectRowVersion,
        string verifiedMimeType,
        long actualContentLength,
        byte[] contentHash,
        int? pixelWidth,
        int? pixelHeight,
        ProjectAssetScanProvider scanProvider,
        CancellationToken cancellationToken);

    Task<ProjectAssetMutation> MarkQuarantinedAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid assetPublicId,
        byte[] expectedAssetRowVersion,
        ProjectAssetBlobReceipt receipt,
        CancellationToken cancellationToken);

    Task<ProjectAssetMutation> ApplyScanResultAsync(
        Guid assetPublicId,
        ProjectAssetScanProvider scanProvider,
        string providerEventId,
        byte[] payloadHash,
        string quarantineETag,
        byte[]? reportedContentHash,
        ProjectAssetScanStatus status,
        string resultCode,
        ProtectedProjectAssetBlobLocation? trustedLocation,
        ProjectAssetBlobReceipt? trustedReceipt,
        DateTimeOffset occurredAtUtc,
        CancellationToken cancellationToken);

    Task<ProjectAssetCollection> ListAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        CancellationToken cancellationToken);

    Task<ProjectAssetUploadIntent?> GetUploadIntentAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid intentPublicId,
        CancellationToken cancellationToken);

    Task<ProjectAssetTrustedContent?> GetTrustedContentAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid assetPublicId,
        CancellationToken cancellationToken);

    Task<ProjectAssetMutation> UpdateMetadataAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid assetPublicId,
        byte[] expectedAssetRowVersion,
        byte[] expectedProjectRowVersion,
        ProjectAssetMetadata metadata,
        CancellationToken cancellationToken);

    Task<ProjectAssetMutation> ReorderAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        byte[] expectedProjectRowVersion,
        IReadOnlyList<ProjectAssetOrderItem> items,
        CancellationToken cancellationToken);

    Task<ProjectAssetMutation> DeleteAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid assetPublicId,
        byte[] expectedAssetRowVersion,
        byte[] expectedProjectRowVersion,
        CancellationToken cancellationToken);
}

public sealed class ProjectAssetDataException(
    string operation,
    int databaseErrorNumber,
    Exception innerException) : Exception(
        $"Project asset data operation '{operation}' failed with database error {databaseErrorNumber}.",
        innerException)
{
    public string Operation { get; } = operation;
    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}

public sealed class ProjectAssetStorageException(
    string operation,
    string code,
    int status,
    Exception? innerException = null) : Exception(
        $"Project asset storage operation '{operation}' failed with code '{code}'.",
        innerException)
{
    public string Operation { get; } = operation;
    public string Code { get; } = code;
    public int Status { get; } = status;
}
