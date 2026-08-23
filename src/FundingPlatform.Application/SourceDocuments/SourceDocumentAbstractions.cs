using FundingPlatform.Core.SourceDocuments;

namespace FundingPlatform.Application.SourceDocuments;

public sealed record SourceDocumentPolicy(
    Uri BlobServiceUri,
    string IncomingContainer,
    string QuarantineContainer,
    string TrustedContainer,
    long MaxBytes,
    TimeSpan UploadTimeToLive,
    TimeSpan FinalizeLease,
    TimeSpan ScanTimeout,
    SourceDocumentScanProvider ScanProvider);

public sealed class ProtectedBlobLocation(string container, string objectName)
{
    public string Container { get; } = container;
    public string ObjectName { get; } = objectName;

    public override string ToString() => "[protected blob location]";
}

public sealed class SourceDocumentCompletionSecret(string token, byte[] hash)
{
    public string Token { get; } = token;
    public byte[] Hash { get; } = hash;

    public override string ToString() => "[redacted completion secret]";
}

public sealed class SourceDocumentUploadGrant(
    Uri uploadUri,
    DateTimeOffset expiresAtUtc,
    IReadOnlyDictionary<string, string> requiredHeaders)
{
    public Uri UploadUri { get; } = uploadUri;
    public DateTimeOffset ExpiresAtUtc { get; } = expiresAtUtc;
    public IReadOnlyDictionary<string, string> RequiredHeaders { get; } = requiredHeaders;

    public override string ToString() => "[redacted upload grant]";
}

public sealed class SourceBlobRead(
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

    public override string ToString() => "[protected blob read]";
}

public sealed record SourceBlobReceipt(string ETag, string? VersionId);

public enum SourceDocumentInspectionFailure
{
    None,
    TooLarge,
    LengthMismatch,
    InvalidContentType,
    InvalidPdf
}

public sealed record SourceDocumentInspection(
    bool IsValid,
    SourceDocumentInspectionFailure Failure,
    long ActualLength,
    byte[]? ContentHash,
    string? VerifiedMimeType);

public sealed record SourceDocumentScanObservation(
    SourceDocumentScanStatus Status,
    string ResultCode,
    string ObservationKey,
    DateTimeOffset ObservedAtUtc)
{
    public bool IsPending => Status == SourceDocumentScanStatus.Pending;
}

public interface ISourceDocumentCompletionTokenService
{
    SourceDocumentCompletionSecret Create();
    bool TryHash(string token, out byte[] hash);
}

public interface ISourceDocumentBlobStore
{
    Task<SourceDocumentUploadGrant> CreateUploadGrantAsync(
        ProtectedBlobLocation destination,
        DateTimeOffset expiresAtUtc,
        CancellationToken cancellationToken);

    Task<SourceBlobRead> OpenReadAsync(
        ProtectedBlobLocation source,
        string? expectedETag,
        CancellationToken cancellationToken);

    Task<SourceBlobReceipt> EnsureCopyAsync(
        ProtectedBlobLocation source,
        string sourceETag,
        ProtectedBlobLocation destination,
        long expectedLength,
        byte[] expectedContentHash,
        CancellationToken cancellationToken);

    Task<SourceBlobReceipt?> GetVerifiedReceiptAsync(
        ProtectedBlobLocation location,
        long expectedLength,
        byte[] expectedContentHash,
        CancellationToken cancellationToken);

    Task DeleteIfMatchAsync(
        ProtectedBlobLocation location,
        string? expectedETag,
        CancellationToken cancellationToken);

}

public interface ISourceDocumentContentInspector
{
    Task<SourceDocumentInspection> InspectPdfAsync(
        SourceBlobRead source,
        long expectedLength,
        long maximumLength,
        CancellationToken cancellationToken);
}

public interface ISourceDocumentScanner
{
    Task<SourceDocumentScanObservation> ObserveAsync(
        Guid sourceDocumentPublicId,
        short scanAttemptCount,
        ProtectedBlobLocation quarantineLocation,
        string quarantineETag,
        CancellationToken cancellationToken);
}

public interface ISourceDocumentRepository
{
    Task<SourceDocumentMutation> CreateUploadIntentAsync(
        Guid adminUserPublicId,
        int fundingSourceId,
        string originalFileName,
        string declaredMimeType,
        long expectedContentLength,
        long maxContentLength,
        ProtectedBlobLocation incomingLocation,
        ProtectedBlobLocation quarantineLocation,
        byte[] completionTokenHash,
        DateTimeOffset expiresAtUtc,
        CancellationToken cancellationToken);

    Task<SourceDocumentFinalizeWork> AcquireFinalizeAsync(
        Guid adminUserPublicId,
        Guid intentPublicId,
        byte[] completionTokenHash,
        Guid leaseId,
        DateTimeOffset leaseUntilUtc,
        CancellationToken cancellationToken);

    Task<SourceDocumentMutation> ReleaseFinalizeAsync(
        Guid adminUserPublicId,
        Guid intentPublicId,
        Guid leaseId,
        string errorCode,
        CancellationToken cancellationToken);

    Task<SourceDocumentMutation> RejectFinalizeAsync(
        Guid adminUserPublicId,
        Guid intentPublicId,
        Guid leaseId,
        string errorCode,
        CancellationToken cancellationToken);

    Task<SourceDocumentMutation> CompleteUploadIntentAsync(
        Guid adminUserPublicId,
        Guid intentPublicId,
        Guid leaseId,
        long actualContentLength,
        byte[] contentHash,
        SourceDocumentScanProvider scanProvider,
        CancellationToken cancellationToken);

    Task<SourceDocumentMutation> MarkQuarantinedAsync(
        Guid adminUserPublicId,
        Guid sourceDocumentPublicId,
        SourceBlobReceipt receipt,
        CancellationToken cancellationToken);

    Task<SourceDocumentMutation> ApplyScanResultAsync(
        Guid sourceDocumentPublicId,
        SourceDocumentScanProvider scanProvider,
        string providerEventId,
        byte[] payloadHash,
        string quarantineETag,
        byte[]? reportedContentHash,
        SourceDocumentScanStatus status,
        string resultCode,
        ProtectedBlobLocation? trustedLocation,
        SourceBlobReceipt? trustedReceipt,
        DateTimeOffset occurredAtUtc,
        CancellationToken cancellationToken);

    Task<SourceDocumentRetryMutation> RetryScanAsync(
        Guid adminUserPublicId,
        Guid sourceDocumentPublicId,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken);

    Task<SourceDocumentScanWork> AcquireScanWorkAsync(
        Guid adminUserPublicId,
        Guid sourceDocumentPublicId,
        byte[] expectedRowVersion,
        CancellationToken cancellationToken);

    Task<SourceDocumentUploadIntent?> GetUploadIntentAsync(
        Guid adminUserPublicId,
        Guid intentPublicId,
        CancellationToken cancellationToken);

    Task<SourceDocument?> GetSourceDocumentAsync(
        Guid adminUserPublicId,
        Guid sourceDocumentPublicId,
        CancellationToken cancellationToken);
}
