using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Core.SourceDocuments;
using FundingPlatform.Infrastructure.SourceDocuments.Configuration;
using FundingPlatform.Infrastructure.SourceDocuments.Cryptography;
using FundingPlatform.Infrastructure.SourceDocuments.Inspection;
using FundingPlatform.Infrastructure.SourceDocuments.Scanning;
using Microsoft.Extensions.Options;

namespace FundingPlatform.UnitTests;

public sealed class SourceDocumentSecurityTests
{
    private static readonly DateTimeOffset Now = new(2026, 8, 21, 12, 0, 0, TimeSpan.Zero);
    private static readonly Guid AdminId = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid IntentId = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid DocumentId = Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");
    private static readonly byte[] RowVersion = Convert.FromHexString("0102030405060708");
    private static readonly byte[] ContentHash = SHA256.HashData("pdf"u8);

    [Fact]
    public void Completion_tokens_are_strong_parseable_and_never_rendered()
    {
        var service = new SourceDocumentCompletionTokenService();

        var secret = service.Create();

        Assert.Equal(43, secret.Token.Length);
        Assert.True(service.TryHash(secret.Token, out var hash));
        Assert.Equal(secret.Hash, hash);
        Assert.Equal("[redacted completion secret]", secret.ToString());
        Assert.False(service.TryHash(secret.Token + "x", out _));
    }

    [Fact]
    public async Task Streaming_inspector_accepts_a_bounded_pdf_without_buffering_the_file()
    {
        var bytes = Encoding.ASCII.GetBytes("%PDF-1.7\n1 0 obj\n<<>>\nendobj\n%%EOF\n");
        await using var source = BlobRead(bytes, "application/pdf");

        var result = await new StreamingPdfContentInspector().InspectPdfAsync(
            source, bytes.Length, 1024, CancellationToken.None);

        Assert.True(result.IsValid);
        Assert.Equal(bytes.Length, result.ActualLength);
        Assert.Equal(SHA256.HashData(bytes), result.ContentHash);
    }

    [Theory]
    [InlineData("text/plain", "%PDF-1.7\n%%EOF\n", SourceDocumentInspectionFailure.InvalidContentType)]
    [InlineData("application/pdf", "not-a-pdf\n%%EOF\n", SourceDocumentInspectionFailure.InvalidPdf)]
    [InlineData("application/pdf", "%PDF-1.7\nmissing-eof", SourceDocumentInspectionFailure.InvalidPdf)]
    public async Task Streaming_inspector_fails_closed(
        string contentType,
        string content,
        SourceDocumentInspectionFailure expected)
    {
        var bytes = Encoding.ASCII.GetBytes(content);
        await using var source = BlobRead(bytes, contentType);

        var result = await new StreamingPdfContentInspector().InspectPdfAsync(
            source, bytes.Length, 1024, CancellationToken.None);

        Assert.False(result.IsValid);
        Assert.Equal(expected, result.Failure);
        Assert.Null(result.ContentHash);
    }

    [Fact]
    public async Task Production_scanner_never_trusts_mutable_blob_tags_in_phase_6()
    {
        var scanner = new ConfiguredSourceDocumentScanner(
            Options.Create(ValidOptions("MicrosoftDefender")),
            new FixedTimeProvider(Now));

        var result = await scanner.ObserveAsync(
            DocumentId,
            1,
            new ProtectedBlobLocation("fp-source-quarantine", "uploads/test.pdf"),
            "\"etag\"",
            CancellationToken.None);

        Assert.Equal(SourceDocumentScanStatus.Pending, result.Status);
        Assert.Equal("defender-eventgrid-required", result.ResultCode);
    }

    [Theory]
    [InlineData(SourceDocumentScanStatus.Clean, 1)]
    [InlineData(SourceDocumentScanStatus.Malicious, 0)]
    [InlineData(SourceDocumentScanStatus.Failed, 0)]
    [InlineData(SourceDocumentScanStatus.TimedOut, 0)]
    public async Task Completion_applies_each_fake_scan_outcome_and_only_clean_becomes_trusted(
        SourceDocumentScanStatus status,
        int expectedTrustedCopies)
    {
        var repository = PendingDocumentRepository();
        var blobs = new FakeBlobStore();
        var service = CreateService(repository, blobs, status);

        var result = await service.CompleteUploadIntentAsync(
            AdminId, IntentId, "valid-token", CancellationToken.None);

        Assert.Equal(SourceDocumentOutcome.Success, result.Outcome);
        Assert.Equal(status, result.ScanStatus);
        Assert.Equal(status, Assert.Single(repository.AppliedStatuses));
        Assert.Equal(expectedTrustedCopies, blobs.CopyCalls);
        Assert.Equal(
            status == SourceDocumentScanStatus.Clean
                ? SourceDocumentStorageStatus.Trusted
                : SourceDocumentStorageStatus.Quarantined,
            result.StorageStatus);
    }

    [Fact]
    public async Task Failed_scan_retry_acquires_private_work_and_reaches_clean_without_browser_token()
    {
        var repository = PendingDocumentRepository();
        repository.RetryMutation = new SourceDocumentRetryMutation(
            true, "scan-retry-requested", DocumentId,
            SourceDocumentStorageStatus.Quarantined, SourceDocumentScanStatus.Pending,
            SourceDocumentScanProvider.DevelopmentFake, 2, RowVersion, false);
        var blobs = new FakeBlobStore();
        var service = CreateService(repository, blobs, SourceDocumentScanStatus.Clean);

        var result = await service.RetryScanAsync(
            AdminId,
            DocumentId,
            RowVersion,
            "retry-document-0001",
            CancellationToken.None);

        Assert.Equal(SourceDocumentOutcome.Success, result.Outcome);
        Assert.Equal(SourceDocumentScanStatus.Clean, result.ScanStatus);
        Assert.Equal(1, repository.AcquireScanWorkCalls);
        Assert.Equal(1, repository.ApplyCalls);
        Assert.Equal(1, blobs.CopyCalls);
    }

    [Fact]
    public async Task Defender_retry_is_rejected_without_mutating_or_emitting_a_dead_command()
    {
        var repository = PendingDocumentRepository();
        var blobs = new FakeBlobStore();
        var service = CreateService(
            repository,
            blobs,
            SourceDocumentScanStatus.Clean,
            SourceDocumentScanProvider.MicrosoftDefender);

        var result = await service.RetryScanAsync(
            AdminId,
            DocumentId,
            RowVersion,
            "retry-document-0002",
            CancellationToken.None);

        Assert.Equal(SourceDocumentOutcome.Conflict, result.Outcome);
        Assert.Equal("defender-rescan-not-configured", result.Code);
        Assert.Equal(0, repository.RetryCalls);
        Assert.Equal(0, repository.AcquireScanWorkCalls);
    }

    [Fact]
    public void Production_rejects_development_fake_scanning()
    {
        Assert.False(SourceDocumentOptions.IsValid(
            ValidOptions("DevelopmentFake"), "Production"));
        Assert.True(SourceDocumentOptions.IsValid(
            ValidOptions("DevelopmentFake"), "Development"));
    }

    private static SourceDocumentService CreateService(
        FakeSourceDocumentRepository repository,
        FakeBlobStore blobs,
        SourceDocumentScanStatus scanResult,
        SourceDocumentScanProvider scanProvider = SourceDocumentScanProvider.DevelopmentFake)
    {
        var scanner = new SequenceScanner(scanResult);
        return new SourceDocumentService(
            repository,
            blobs,
            new StreamingPdfContentInspector(),
            scanner,
            new FakeTokenService(),
            Policy(scanProvider),
            new FixedTimeProvider(Now));
    }

    private static FakeSourceDocumentRepository PendingDocumentRepository()
    {
        var quarantine = new ProtectedBlobLocation(
            "fp-source-quarantine", "uploads/2026/08/21/document.pdf");
        return new FakeSourceDocumentRepository
        {
            FinalizeWork = new SourceDocumentFinalizeWork
            {
                Succeeded = true,
                Code = "completed",
                IntentPublicId = IntentId,
                IntentStatus = SourceDocumentUploadIntentStatus.Completed,
                SourceDocumentPublicId = DocumentId,
                QuarantineLocation = quarantine,
                ActualContentLength = 2048,
                ContentHash = ContentHash,
                BlobETag = "\"quarantine-etag\"",
                StorageStatus = SourceDocumentStorageStatus.Quarantined,
                ScanStatus = SourceDocumentScanStatus.Pending,
                ScanProvider = SourceDocumentScanProvider.DevelopmentFake,
                RowVersion = RowVersion
            },
            ScanWork = new SourceDocumentScanWork
            {
                Succeeded = true,
                Code = "acquired",
                SourceDocumentPublicId = DocumentId,
                QuarantineLocation = quarantine,
                ContentLength = 2048,
                ContentHash = ContentHash,
                BlobETag = "\"quarantine-etag\"",
                ScanProvider = SourceDocumentScanProvider.DevelopmentFake,
                ScanAttemptCount = 2,
                ScanStartedAtUtc = Now.AddSeconds(-1),
                CreatedAtUtc = Now.AddMinutes(-1),
                RowVersion = RowVersion
            },
            Document = Document(SourceDocumentScanStatus.Pending, 2)
        };
    }

    private static SourceDocument Document(SourceDocumentScanStatus status, short attempt) => new(
        DocumentId, 1, "Manual document upload", "document.pdf", "application/pdf", 2048,
        status == SourceDocumentScanStatus.Clean
            ? SourceDocumentStorageStatus.Trusted
            : SourceDocumentStorageStatus.Quarantined,
        status,
        SourceDocumentScanProvider.DevelopmentFake,
        false,
        attempt,
        null,
        Now.AddSeconds(-1),
        status == SourceDocumentScanStatus.Pending ? null : Now,
        0,
        AdminId,
        Now.AddMinutes(-1),
        Now,
        RowVersion);

    private static SourceBlobRead BlobRead(byte[] bytes, string contentType) => new(
        new MemoryStream(bytes, writable: false), bytes.Length, contentType, "\"etag\"", null);

    private static SourceDocumentPolicy Policy(
        SourceDocumentScanProvider scanProvider = SourceDocumentScanProvider.DevelopmentFake) => new(
        new Uri("https://testing.blob.core.windows.net"),
        "fp-source-incoming",
        "fp-source-quarantine",
        "fp-source-trusted",
        26_214_400,
        TimeSpan.FromMinutes(5),
        TimeSpan.FromMinutes(2),
        TimeSpan.FromSeconds(10),
        scanProvider);

    private static SourceDocumentOptions ValidOptions(string mode) => new()
    {
        BlobServiceUri = "https://testing.blob.core.windows.net",
        ScanMode = mode,
        DevelopmentFakeResult = "Clean"
    };

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private sealed class SequenceScanner(SourceDocumentScanStatus status) : ISourceDocumentScanner
    {
        public Task<SourceDocumentScanObservation> ObserveAsync(
            Guid sourceDocumentPublicId,
            short scanAttemptCount,
            ProtectedBlobLocation quarantineLocation,
            string quarantineETag,
            CancellationToken cancellationToken) => Task.FromResult(new SourceDocumentScanObservation(
                status,
                $"test-{status.ToString().ToLowerInvariant()}",
                $"test-{scanAttemptCount}-{status}",
                Now));
    }

    private sealed class FakeTokenService : ISourceDocumentCompletionTokenService
    {
        public SourceDocumentCompletionSecret Create() =>
            new("valid-token", SHA256.HashData("valid-token"u8));

        public bool TryHash(string token, out byte[] hash)
        {
            hash = SHA256.HashData(Encoding.UTF8.GetBytes(token));
            return token == "valid-token";
        }
    }

    private sealed class FakeBlobStore : ISourceDocumentBlobStore
    {
        public int CopyCalls { get; private set; }

        public Task<SourceDocumentUploadGrant> CreateUploadGrantAsync(
            ProtectedBlobLocation destination, DateTimeOffset expiresAtUtc,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<SourceBlobRead> OpenReadAsync(
            ProtectedBlobLocation source, string? expectedETag,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<SourceBlobReceipt> EnsureCopyAsync(
            ProtectedBlobLocation source, string sourceETag,
            ProtectedBlobLocation destination, long expectedLength,
            byte[] expectedContentHash, CancellationToken cancellationToken)
        {
            CopyCalls++;
            return Task.FromResult(new SourceBlobReceipt("\"trusted-etag\"", "version"));
        }

        public Task<SourceBlobReceipt?> GetVerifiedReceiptAsync(
            ProtectedBlobLocation location, long expectedLength,
            byte[] expectedContentHash, CancellationToken cancellationToken) =>
            Task.FromResult<SourceBlobReceipt?>(null);

        public Task DeleteIfMatchAsync(
            ProtectedBlobLocation location, string? expectedETag,
            CancellationToken cancellationToken) => Task.CompletedTask;

    }

    private sealed class FakeSourceDocumentRepository : ISourceDocumentRepository
    {
        public SourceDocumentFinalizeWork FinalizeWork { get; init; } = new();
        public SourceDocumentScanWork ScanWork { get; init; } = new();
        public SourceDocument Document { get; set; } = null!;
        public SourceDocumentRetryMutation RetryMutation { get; set; } = null!;
        public List<SourceDocumentScanStatus> AppliedStatuses { get; } = [];
        public int ApplyCalls { get; private set; }
        public int AcquireScanWorkCalls { get; private set; }
        public int RetryCalls { get; private set; }

        public Task<SourceDocumentFinalizeWork> AcquireFinalizeAsync(
            Guid adminUserPublicId, Guid intentPublicId, byte[] completionTokenHash,
            Guid leaseId, DateTimeOffset leaseUntilUtc, CancellationToken cancellationToken) =>
            Task.FromResult(FinalizeWork);

        public Task<SourceDocumentMutation> ApplyScanResultAsync(
            Guid sourceDocumentPublicId, SourceDocumentScanProvider scanProvider,
            string providerEventId, byte[] payloadHash, string quarantineETag,
            byte[]? reportedContentHash, SourceDocumentScanStatus status,
            string resultCode, ProtectedBlobLocation? trustedLocation,
            SourceBlobReceipt? trustedReceipt, DateTimeOffset occurredAtUtc,
            CancellationToken cancellationToken)
        {
            ApplyCalls++;
            AppliedStatuses.Add(status);
            Document = SourceDocumentSecurityTests.Document(status, Document.ScanAttemptCount);
            return Task.FromResult(new SourceDocumentMutation(
                true, "scan-result-applied",
                SourceDocumentPublicId: sourceDocumentPublicId,
                StorageStatus: Document.StorageStatus,
                ScanStatus: status,
                ScanProvider: scanProvider,
                RowVersion: RowVersion));
        }

        public Task<SourceDocumentScanWork> AcquireScanWorkAsync(
            Guid adminUserPublicId, Guid sourceDocumentPublicId,
            byte[] expectedRowVersion, CancellationToken cancellationToken)
        {
            AcquireScanWorkCalls++;
            return Task.FromResult(ScanWork);
        }

        public Task<SourceDocument?> GetSourceDocumentAsync(
            Guid adminUserPublicId, Guid sourceDocumentPublicId,
            CancellationToken cancellationToken) => Task.FromResult<SourceDocument?>(Document);

        public Task<SourceDocumentRetryMutation> RetryScanAsync(
            Guid adminUserPublicId, Guid sourceDocumentPublicId,
            byte[] expectedRowVersion, byte[] idempotencyKeyHash,
            byte[] requestHash, CancellationToken cancellationToken)
        {
            RetryCalls++;
            return Task.FromResult(RetryMutation);
        }

        public Task<SourceDocumentMutation> CreateUploadIntentAsync(
            Guid adminUserPublicId, int fundingSourceId, string originalFileName,
            string declaredMimeType, long expectedContentLength, long maxContentLength,
            ProtectedBlobLocation incomingLocation, ProtectedBlobLocation quarantineLocation,
            byte[] completionTokenHash, DateTimeOffset expiresAtUtc,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<SourceDocumentMutation> ReleaseFinalizeAsync(
            Guid adminUserPublicId, Guid intentPublicId, Guid leaseId,
            string errorCode, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<SourceDocumentMutation> RejectFinalizeAsync(
            Guid adminUserPublicId, Guid intentPublicId, Guid leaseId,
            string errorCode, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<SourceDocumentMutation> CompleteUploadIntentAsync(
            Guid adminUserPublicId, Guid intentPublicId, Guid leaseId,
            long actualContentLength, byte[] contentHash,
            SourceDocumentScanProvider scanProvider, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<SourceDocumentMutation> MarkQuarantinedAsync(
            Guid adminUserPublicId, Guid sourceDocumentPublicId,
            SourceBlobReceipt receipt, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<SourceDocumentUploadIntent?> GetUploadIntentAsync(
            Guid adminUserPublicId, Guid intentPublicId,
            CancellationToken cancellationToken) =>
            Task.FromResult<SourceDocumentUploadIntent?>(null);
    }
}
