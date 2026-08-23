using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Core.SourceDocuments;

namespace FundingPlatform.UnitTests;

public sealed class DefenderEventGridServiceTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 8, 22, 18, 0, 0, TimeSpan.Zero);
    private static readonly Guid DocumentId =
        Guid.Parse("11111111-1111-1111-1111-111111111111");
    private static readonly Guid ReceiptId =
        Guid.Parse("22222222-2222-2222-2222-222222222222");
    private static readonly byte[] Pdf = "%PDF-1.4\n%%EOF\n"u8.ToArray();
    private static readonly byte[] ContentHash = SHA256.HashData(Pdf);
    private static readonly ProtectedBlobLocation Quarantine =
        new("fp-source-quarantine", "uploads/test.pdf");

    [Fact]
    public async Task Finalize_dependency_failure_returns_retry_after_scan_was_applied()
    {
        var receipts = new FakeReceipts { FinalizeFails = true };
        var documents = new FakeDocuments(new SourceDocumentMutation(
            true, "scan-result-applied", SourceDocumentPublicId: DocumentId));
        var blobs = new FakeBlobs();
        var service = CreateService(receipts, documents, blobs);

        var result = await service.HandleAsync(
            Event("Malicious"), "Notification", "defender-results", Caller(),
            CancellationToken.None);

        Assert.Equal(DefenderEventGridOutcome.Retry, result.Outcome);
        Assert.Equal("scan-finalization-unavailable", result.Code);
        Assert.Equal(1, documents.ApplyCalls);
        Assert.Equal(1, receipts.FinalizeCalls);
    }

    [Fact]
    public async Task Permanent_mutation_conflict_is_finalized_and_not_retried_forever()
    {
        var receipts = new FakeReceipts();
        var documents = new FakeDocuments(new SourceDocumentMutation(
            false, "invalid-transition", SourceDocumentPublicId: DocumentId));
        var service = CreateService(receipts, documents, new FakeBlobs());

        var result = await service.HandleAsync(
            Event("Malicious"), "Notification", "defender-results", Caller(),
            CancellationToken.None);

        Assert.Equal(DefenderEventGridOutcome.Rejected, result.Outcome);
        Assert.Equal("invalid-transition", result.Code);
        Assert.Equal(1, receipts.FinalizeCalls);
        Assert.False(receipts.FinalizedApplied);
    }

    [Fact]
    public async Task Superseding_malicious_event_retries_until_exact_trusted_blob_is_deleted()
    {
        var receipts = new FakeReceipts();
        var revoked = new ProtectedBlobLocation("fp-source-trusted", "uploads/test.pdf");
        var documents = new FakeDocuments(new SourceDocumentMutation(
            true,
            "scan-result-superseded",
            SourceDocumentPublicId: DocumentId,
            RevokedTrustedLocation: revoked,
            RevokedTrustedETag: "\"trusted-etag\""));
        var blobs = new FakeBlobs { DeleteFails = true };
        var service = CreateService(receipts, documents, blobs);

        var first = await service.HandleAsync(
            Event("Malicious"), "Notification", "defender-results", Caller(),
            CancellationToken.None);

        Assert.Equal(DefenderEventGridOutcome.Retry, first.Outcome);
        Assert.Equal(0, receipts.FinalizeCalls);
        Assert.Equal("fp-source-trusted", blobs.DeletedLocation!.Container);
        Assert.Equal("\"trusted-etag\"", blobs.DeletedETag);

        blobs.DeleteFails = false;
        var replay = await service.HandleAsync(
            Event("Malicious"), "Notification", "defender-results", Caller(),
            CancellationToken.None);

        Assert.Equal(DefenderEventGridOutcome.Applied, replay.Outcome);
        Assert.Equal("scan-result-superseded", replay.Code);
        Assert.Equal(1, receipts.FinalizeCalls);
        Assert.True(receipts.FinalizedApplied);
    }

    [Fact]
    public async Task Official_not_scanned_casing_is_accepted_without_sha256()
    {
        var receipts = new FakeReceipts();
        var documents = new FakeDocuments(new SourceDocumentMutation(
            true, "scan-result-applied", SourceDocumentPublicId: DocumentId));
        var service = CreateService(receipts, documents, new FakeBlobs());

        var result = await service.HandleAsync(
            Event("Not Scanned", includeHash: false),
            "Notification", "defender-results", Caller(), CancellationToken.None);

        Assert.Equal(DefenderEventGridOutcome.Applied, result.Outcome);
        Assert.Equal(SourceDocumentScanStatus.Failed, documents.Status);
    }

    [Fact]
    public async Task Clean_copy_losing_to_malicious_compare_and_set_is_deleted_before_ack()
    {
        var receipts = new FakeReceipts();
        var documents = new FakeDocuments(new SourceDocumentMutation(
            false,
            "invalid-transition",
            SourceDocumentPublicId: DocumentId,
            StorageStatus: SourceDocumentStorageStatus.Quarantined,
            ScanStatus: SourceDocumentScanStatus.Malicious));
        var blobs = new FakeBlobs();
        var service = CreateService(receipts, documents, blobs);

        var result = await service.HandleAsync(
            Event("No threats found"), "Notification", "defender-results", Caller(),
            CancellationToken.None);

        Assert.Equal(DefenderEventGridOutcome.Rejected, result.Outcome);
        Assert.NotNull(blobs.DeletedLocation);
        Assert.Equal("fp-source-trusted", blobs.DeletedLocation!.Container);
        Assert.Equal("\"trusted-etag\"", blobs.DeletedETag);
        Assert.Equal(1, receipts.FinalizeCalls);
        Assert.False(receipts.FinalizedApplied);
    }

    [Fact]
    public async Task Retention_winning_after_receipt_acceptance_is_terminally_ignored()
    {
        var receipts = new FakeReceipts();
        var documents = new FakeDocuments(new SourceDocumentMutation(
            true,
            "content-retention-ignored",
            SourceDocumentPublicId: DocumentId,
            StorageStatus: SourceDocumentStorageStatus.Quarantined,
            ScanStatus: SourceDocumentScanStatus.Pending));
        var service = CreateService(receipts, documents, new FakeBlobs());

        var result = await service.HandleAsync(
            Event("Malicious"), "Notification", "defender-results", Caller(),
            CancellationToken.None);

        Assert.Equal(DefenderEventGridOutcome.Rejected, result.Outcome);
        Assert.Equal("content-retention-ignored", result.Code);
        Assert.Equal(1, receipts.FinalizeCalls);
        Assert.False(receipts.FinalizedApplied);
    }

    private static DefenderEventGridService CreateService(
        FakeReceipts receipts,
        FakeDocuments documents,
        FakeBlobs blobs) => new(
            receipts,
            documents,
            blobs,
            new DefenderEventGridPolicy(
                "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourcegroups/rg/providers/microsoft.eventgrid/systemtopics/defender",
                "defender-results",
                "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourcegroups/rg/providers/microsoft.storage/storageaccounts/account",
                new Uri("https://account.blob.core.windows.net"),
                "fp-source-quarantine",
                "fp-source-trusted",
                1_048_576,
                TimeSpan.FromMinutes(5)),
            new FixedTimeProvider(Now));

    private static EventGridCaller Caller() => new(
        Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
        Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
        Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc"));

    private static byte[] Event(string scanResult, bool includeHash = true)
    {
        var details = includeHash
            ? new Dictionary<string, object?> { ["sha256"] = Convert.ToHexString(ContentHash) }
            : new Dictionary<string, object?>();
        return JsonSerializer.SerializeToUtf8Bytes(new[]
        {
            new
            {
                id = "defender-event-1",
                topic = "/subscriptions/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA/resourceGroups/rg/providers/Microsoft.EventGrid/systemtopics/defender",
                subject = "/storageAccounts/account/containers/fp-source-quarantine/blobs/uploads/test.pdf",
                eventType = "Microsoft.Security.MalwareScanningResult",
                eventTime = Now,
                dataVersion = "1.0",
                data = new
                {
                    blobUri = "https://account.blob.core.windows.net/fp-source-quarantine/uploads/test.pdf",
                    eTag = "0x1",
                    scanResultType = scanResult,
                    scanFinishedTimeUtc = Now,
                    scanResultDetails = details
                }
            }
        });
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private sealed class FakeReceipts : IDefenderScanReceiptRepository
    {
        public bool FinalizeFails { get; init; }
        public int RecordCalls { get; private set; }
        public int FinalizeCalls { get; private set; }
        public bool FinalizedApplied { get; private set; }

        public Task<DefenderReceiptWork> RecordAsync(
            string eventGridEventId,
            byte[] payloadHash,
            EventGridCaller caller,
            string eventSubscriptionName,
            string topicResourceId,
            string storageAccountResourceId,
            string blobHost,
            ProtectedBlobLocation quarantineLocation,
            string blobETag,
            byte[]? reportedContentHash,
            SourceDocumentScanStatus status,
            string resultCode,
            DateTimeOffset occurredAtUtc,
            DateTimeOffset receivedAtUtc,
            CancellationToken cancellationToken)
        {
            RecordCalls++;
            return Task.FromResult(new DefenderReceiptWork(
                true,
                RecordCalls == 1 ? "accepted" : "replayed-accepted",
                ReceiptId,
                DocumentId,
                SourceDocumentScanProvider.MicrosoftDefender,
                Quarantine,
                "\"0x1\"",
                ContentHash,
                Pdf.Length,
                "application/pdf",
                RecordCalls > 1));
        }

        public Task FinalizeAsync(
            Guid receiptId,
            byte[] payloadHash,
            bool applied,
            string outcomeCode,
            DateTimeOffset finalizedAtUtc,
            CancellationToken cancellationToken)
        {
            FinalizeCalls++;
            FinalizedApplied = applied;
            return FinalizeFails
                ? Task.FromException(new SourceDocumentDataException("finalize", -1))
                : Task.CompletedTask;
        }
    }

    private sealed class FakeDocuments(SourceDocumentMutation mutation) : ISourceDocumentRepository
    {
        public int ApplyCalls { get; private set; }
        public SourceDocumentScanStatus? Status { get; private set; }

        public Task<SourceDocumentMutation> ApplyScanResultAsync(
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
            CancellationToken cancellationToken)
        {
            ApplyCalls++;
            Status = status;
            return Task.FromResult(mutation);
        }

        public Task<SourceDocumentMutation> CreateUploadIntentAsync(Guid a, int b, string c, string d, long e, long f, ProtectedBlobLocation g, ProtectedBlobLocation h, byte[] i, DateTimeOffset j, CancellationToken k) => throw new NotSupportedException();
        public Task<SourceDocumentFinalizeWork> AcquireFinalizeAsync(Guid a, Guid b, byte[] c, Guid d, DateTimeOffset e, CancellationToken f) => throw new NotSupportedException();
        public Task<SourceDocumentMutation> ReleaseFinalizeAsync(Guid a, Guid b, Guid c, string d, CancellationToken e) => throw new NotSupportedException();
        public Task<SourceDocumentMutation> RejectFinalizeAsync(Guid a, Guid b, Guid c, string d, CancellationToken e) => throw new NotSupportedException();
        public Task<SourceDocumentMutation> CompleteUploadIntentAsync(Guid a, Guid b, Guid c, long d, byte[] e, SourceDocumentScanProvider f, CancellationToken g) => throw new NotSupportedException();
        public Task<SourceDocumentMutation> MarkQuarantinedAsync(Guid a, Guid b, SourceBlobReceipt c, CancellationToken d) => throw new NotSupportedException();
        public Task<SourceDocumentRetryMutation> RetryScanAsync(Guid a, Guid b, byte[] c, byte[] d, byte[] e, CancellationToken f) => throw new NotSupportedException();
        public Task<SourceDocumentScanWork> AcquireScanWorkAsync(Guid a, Guid b, byte[] c, CancellationToken d) => throw new NotSupportedException();
        public Task<SourceDocumentUploadIntent?> GetUploadIntentAsync(Guid a, Guid b, CancellationToken c) => throw new NotSupportedException();
        public Task<SourceDocument?> GetSourceDocumentAsync(Guid a, Guid b, CancellationToken c) => throw new NotSupportedException();
    }

    private sealed class FakeBlobs : ISourceDocumentBlobStore
    {
        public bool DeleteFails { get; set; }
        public ProtectedBlobLocation? DeletedLocation { get; private set; }
        public string? DeletedETag { get; private set; }

        public Task<SourceBlobRead> OpenReadAsync(
            ProtectedBlobLocation source,
            string? expectedETag,
            CancellationToken cancellationToken) => Task.FromResult(new SourceBlobRead(
                new MemoryStream(Pdf, writable: false), Pdf.Length, "application/pdf",
                "\"0x1\"", null));

        public Task DeleteIfMatchAsync(
            ProtectedBlobLocation location,
            string? expectedETag,
            CancellationToken cancellationToken)
        {
            DeletedLocation = location;
            DeletedETag = expectedETag;
            return DeleteFails
                ? Task.FromException(new SourceDocumentStorageException(
                    "delete", "azure-storage-failed", 503))
                : Task.CompletedTask;
        }

        public Task<SourceBlobReceipt?> GetVerifiedReceiptAsync(
            ProtectedBlobLocation location,
            long expectedLength,
            byte[] expectedContentHash,
            CancellationToken cancellationToken) =>
            Task.FromResult<SourceBlobReceipt?>(null);

        public Task<SourceBlobReceipt> EnsureCopyAsync(ProtectedBlobLocation a, string b, ProtectedBlobLocation c, long d, byte[] e, CancellationToken f) => Task.FromResult(new SourceBlobReceipt("\"trusted-etag\"", null));
        public Task<SourceDocumentUploadGrant> CreateUploadGrantAsync(ProtectedBlobLocation a, DateTimeOffset b, CancellationToken c) => throw new NotSupportedException();
    }
}
