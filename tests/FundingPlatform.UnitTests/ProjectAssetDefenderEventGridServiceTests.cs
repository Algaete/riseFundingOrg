using System.Security.Cryptography;
using System.Text.Json;
using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Core.ProjectAssets;
using FundingPlatform.Infrastructure.ProjectAssets.Storage;

namespace FundingPlatform.UnitTests;

public sealed class ProjectAssetDefenderEventGridServiceTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 9, 8, 18, 0, 0, TimeSpan.Zero);
    private static readonly Guid AssetId =
        Guid.Parse("11111111-1111-1111-1111-111111111111");
    private static readonly Guid ReceiptId =
        Guid.Parse("22222222-2222-2222-2222-222222222222");
    private static readonly byte[] Pdf = "%PDF-1.4\n%%EOF\n"u8.ToArray();
    private static readonly byte[] ContentHash = SHA256.HashData(Pdf);
    private static readonly ProtectedProjectAssetBlobLocation Quarantine =
        new("fp-project-quarantine", "uploads/test.pdf");

    [Fact]
    public async Task Validation_handshake_requires_the_exact_configured_topic()
    {
        var fixture = new Fixture();

        var accepted = await fixture.Service.HandleAsync(
            ValidationEvent(Topic),
            "SubscriptionValidation",
            "project-asset-defender-results",
            Caller(),
            CancellationToken.None);
        var rejected = await fixture.Service.HandleAsync(
            ValidationEvent(Topic + "/child"),
            "SubscriptionValidation",
            "project-asset-defender-results",
            Caller(),
            CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.ValidationHandshake, accepted.Outcome);
        Assert.Equal("validation-code", accepted.ValidationCode);
        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Rejected, rejected.Outcome);
        Assert.Equal("event-origin-rejected", rejected.Code);
        Assert.Empty(fixture.Trace);
    }

    [Fact]
    public async Task Payload_larger_than_64_KiB_is_rejected_before_parsing()
    {
        var fixture = new Fixture();

        var result = await fixture.Service.HandleAsync(
            new byte[(64 * 1024) + 1],
            "Notification",
            "project-asset-defender-results",
            Caller(),
            CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Rejected, result.Outcome);
        Assert.Equal("event-envelope-rejected", result.Code);
        Assert.Empty(fixture.Trace);
    }

    [Theory]
    [InlineData("No threats found")]
    [InlineData("Malicious")]
    public async Task Clean_and_malicious_results_require_a_SHA256(string scanResult)
    {
        var fixture = new Fixture();

        var result = await fixture.Service.HandleAsync(
            Event(scanResult, includeHash: false),
            "Notification",
            "project-asset-defender-results",
            Caller(),
            CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Rejected, result.Outcome);
        Assert.Equal("scan-content-hash-required", result.Code);
        Assert.Empty(fixture.Trace);
    }

    [Theory]
    [InlineData("Error", ProjectAssetScanStatus.Failed)]
    [InlineData("Not Scanned", ProjectAssetScanStatus.Failed)]
    [InlineData("Scan Timed Out", ProjectAssetScanStatus.TimedOut)]
    public async Task Failed_and_timed_out_results_accept_an_omitted_SHA256(
        string scanResult,
        ProjectAssetScanStatus expectedStatus)
    {
        var fixture = new Fixture();

        var result = await fixture.Service.HandleAsync(
            Event(scanResult, includeHash: false),
            "Notification",
            "project-asset-defender-results",
            Caller(),
            CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Applied, result.Outcome);
        Assert.Equal(expectedStatus, fixture.Assets.Status);
        Assert.Null(fixture.Receipts.ReportedHash);
    }

    [Theory]
    [InlineData("Error", ProjectAssetScanStatus.Failed)]
    [InlineData("Scan Timed Out", ProjectAssetScanStatus.TimedOut)]
    public async Task Failed_and_timed_out_results_verify_a_valid_optional_SHA256(
        string scanResult,
        ProjectAssetScanStatus expectedStatus)
    {
        var fixture = new Fixture();

        var result = await fixture.Service.HandleAsync(
            Event(scanResult),
            "Notification",
            "project-asset-defender-results",
            Caller(),
            CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Applied, result.Outcome);
        Assert.Equal(expectedStatus, fixture.Assets.Status);
        Assert.Equal(ContentHash, fixture.Receipts.ReportedHash);
    }

    [Fact]
    public async Task Present_but_malformed_SHA256_is_rejected()
    {
        var fixture = new Fixture();

        var result = await fixture.Service.HandleAsync(
            Event("Malicious", hash: "not-a-sha256"),
            "Notification",
            "project-asset-defender-results",
            Caller(),
            CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Rejected, result.Outcome);
        Assert.Equal("scan-content-hash-invalid", result.Code);
        Assert.Empty(fixture.Trace);
    }

    [Fact]
    public async Task Blob_host_container_and_subject_must_all_match_the_origin()
    {
        var fixture = new Fixture();
        var foreignHost = await fixture.Service.HandleAsync(
            Event("Malicious", blobUri:
                "https://other.blob.core.windows.net/fp-project-quarantine/uploads/test.pdf"),
            "Notification", "project-asset-defender-results", Caller(),
            CancellationToken.None);
        var foreignContainer = await fixture.Service.HandleAsync(
            Event("Malicious", blobUri:
                "https://account.blob.core.windows.net/other/uploads/test.pdf"),
            "Notification", "project-asset-defender-results", Caller(),
            CancellationToken.None);
        var mismatchedSubject = await fixture.Service.HandleAsync(
            Event("Malicious", subject:
                "/storageAccounts/account/containers/fp-project-quarantine/blobs/uploads/other.pdf"),
            "Notification", "project-asset-defender-results", Caller(),
            CancellationToken.None);

        Assert.All([foreignHost, foreignContainer, mismatchedSubject], result =>
        {
            Assert.Equal(ProjectAssetDefenderEventGridOutcome.Rejected, result.Outcome);
            Assert.Equal("scan-event-invalid", result.Code);
        });
        Assert.Empty(fixture.Trace);
    }

    [Fact]
    public async Task Receipt_dependency_failure_returns_retry_without_reading_content()
    {
        var fixture = new Fixture();
        fixture.Receipts.RecordFails = true;

        var result = await fixture.Service.HandleAsync(
            Event("Malicious"), "Notification", "project-asset-defender-results",
            Caller(), CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Retry, result.Outcome);
        Assert.Equal("scan-receipt-unavailable", result.Code);
        Assert.Equal(["record"], fixture.Trace);
    }

    [Fact]
    public async Task Durable_receipt_rejection_is_not_retried_forever()
    {
        var fixture = new Fixture();
        fixture.Receipts.Work = DefaultWork() with
        {
            Succeeded = false,
            Code = "blob-etag-mismatch"
        };

        var result = await fixture.Service.HandleAsync(
            Event("Malicious"), "Notification", "project-asset-defender-results",
            Caller(), CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Rejected, result.Outcome);
        Assert.Equal("blob-etag-mismatch", result.Code);
        Assert.Equal(["record"], fixture.Trace);
    }

    [Fact]
    public async Task Finalized_receipt_replay_skips_blob_and_database_mutation()
    {
        var fixture = new Fixture();
        fixture.Receipts.Work = DefaultWork() with { Code = "replayed-applied" };

        var result = await fixture.Service.HandleAsync(
            Event("Malicious"), "Notification", "project-asset-defender-results",
            Caller(), CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Applied, result.Outcome);
        Assert.Equal("replayed-applied", result.Code);
        Assert.Equal(AssetId, result.ProjectAssetId);
        Assert.Equal(["record"], fixture.Trace);
    }

    [Fact]
    public async Task Receipt_materialization_must_be_complete_and_kind_bounded()
    {
        var fixture = new Fixture();
        fixture.Receipts.Work = DefaultWork() with
        {
            Kind = ProjectAssetKind.Video,
            ContentLength = 1
        };

        var result = await fixture.Service.HandleAsync(
            Event("Malicious"), "Notification", "project-asset-defender-results",
            Caller(), CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Retry, result.Outcome);
        Assert.Equal("scan-receipt-materialization-invalid", result.Code);
        Assert.Equal(["record"], fixture.Trace);
    }

    [Fact]
    public async Task Receipt_and_event_ETag_conflict_is_durably_rejected()
    {
        var fixture = new Fixture();
        fixture.Receipts.Work = DefaultWork() with { QuarantineETag = "\"other\"" };

        var result = await fixture.Service.HandleAsync(
            Event("Malicious"), "Notification", "project-asset-defender-results",
            Caller(), CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Rejected, result.Outcome);
        Assert.Equal("scan-content-conflict", result.Code);
        Assert.Equal(["record", "finalize"], fixture.Trace);
        Assert.False(fixture.Receipts.FinalizedApplied);
    }

    [Fact]
    public async Task Content_is_rehashed_with_a_bounded_read_before_apply()
    {
        var fixture = new Fixture();
        fixture.Blobs.Bytes = "%PDF-1.4\nchanged\n%%EOF\n"u8.ToArray();
        fixture.Blobs.ReportedLength = Pdf.Length;

        var result = await fixture.Service.HandleAsync(
            Event("Malicious"), "Notification", "project-asset-defender-results",
            Caller(), CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Rejected, result.Outcome);
        Assert.Equal("scan-content-conflict", result.Code);
        Assert.Equal(["record", "open", "finalize"], fixture.Trace);
        Assert.Equal(0, fixture.Assets.ApplyCalls);
    }

    [Fact]
    public async Task Clean_PDF_follows_record_rehash_promote_apply_finalize_order()
    {
        var fixture = new Fixture();

        var result = await fixture.Service.HandleAsync(
            Event("No threats found"), "Notification", "project-asset-defender-results",
            Caller(), CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Applied, result.Outcome);
        Assert.Equal("scan-result-applied", result.Code);
        Assert.Equal(
            ["record", "open", "promote", "apply", "finalize"],
            fixture.Trace);
        Assert.NotNull(fixture.Assets.TrustedLocation);
        Assert.Equal("fp-project-trusted", fixture.Assets.TrustedLocation!.Container);
        Assert.True(fixture.Receipts.FinalizedApplied);
    }

    [Fact]
    public async Task Clean_image_fails_closed_until_sanitization_is_available()
    {
        var fixture = new Fixture();
        fixture.Receipts.Work = DefaultWork() with
        {
            Kind = ProjectAssetKind.Image,
            MimeType = "image/png"
        };
        fixture.Promoter.Result = new ProjectAssetTrustedContentPromotion(
            false, "image-sanitization-unavailable");

        var result = await fixture.Service.HandleAsync(
            Event("No threats found"), "Notification", "project-asset-defender-results",
            Caller(), CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Retry, result.Outcome);
        Assert.Equal("image-sanitization-unavailable", result.Code);
        Assert.Equal(["record", "open", "promote"], fixture.Trace);
        Assert.Equal(0, fixture.Assets.ApplyCalls);
        Assert.Equal(0, fixture.Receipts.FinalizeCalls);
    }

    [Fact]
    public async Task Clean_promotion_without_versioning_is_removed_and_never_applied()
    {
        var fixture = new Fixture();
        fixture.Promoter.Result = new ProjectAssetTrustedContentPromotion(
            true,
            "promoted",
            new ProjectAssetBlobReceipt("\"trusted-etag\"", null));

        var result = await fixture.Service.HandleAsync(
            Event("No threats found"), "Notification", "project-asset-defender-results",
            Caller(), CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Retry, result.Outcome);
        Assert.Equal("trusted-promotion-materialization-invalid", result.Code);
        Assert.Equal(
            ["record", "open", "promote", "delete", "verify"],
            fixture.Trace);
        Assert.Equal(0, fixture.Assets.ApplyCalls);
        Assert.Equal(0, fixture.Receipts.FinalizeCalls);
        Assert.Equal("\"trusted-etag\"", fixture.Blobs.DeletedETag);
        Assert.Null(fixture.Blobs.DeletedVersionId);
    }

    [Fact]
    public async Task Malicious_result_never_promotes_content()
    {
        var fixture = new Fixture();

        var result = await fixture.Service.HandleAsync(
            Event("Malicious"), "Notification", "project-asset-defender-results",
            Caller(), CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Applied, result.Outcome);
        Assert.Equal(["record", "open", "apply", "finalize"], fixture.Trace);
        Assert.Null(fixture.Assets.TrustedLocation);
    }

    [Fact]
    public async Task Clean_copy_losing_compare_and_set_is_removed_before_finalization()
    {
        var fixture = new Fixture();
        fixture.Assets.Mutation = new ProjectAssetMutation(
            false,
            "invalid-transition",
            AssetPublicId: AssetId,
            StorageStatus: ProjectAssetStorageStatus.Failed,
            ScanStatus: ProjectAssetScanStatus.Malicious);

        var result = await fixture.Service.HandleAsync(
            Event("No threats found"), "Notification", "project-asset-defender-results",
            Caller(), CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Rejected, result.Outcome);
        Assert.Equal("invalid-transition", result.Code);
        Assert.Equal(
            ["record", "open", "promote", "apply", "delete", "delete-version",
             "verify", "verify-version", "finalize"],
            fixture.Trace);
        Assert.False(fixture.Receipts.FinalizedApplied);
        Assert.Equal("\"trusted-etag\"", fixture.Blobs.DeletedETag);
        Assert.Equal("trusted-version", fixture.Blobs.DeletedVersionId);
    }

    [Fact]
    public async Task Replayed_clean_cannot_recreate_trusted_content_after_late_revocation()
    {
        var fixture = new Fixture();
        fixture.Assets.Mutation = new ProjectAssetMutation(
            true,
            "scan-result-applied",
            AssetPublicId: AssetId,
            StorageStatus: ProjectAssetStorageStatus.Failed,
            ScanStatus: ProjectAssetScanStatus.Malicious,
            WasReplay: true);

        var result = await fixture.Service.HandleAsync(
            Event("No threats found"), "Notification", "project-asset-defender-results",
            Caller(), CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Applied, result.Outcome);
        Assert.Equal("scan-result-applied", result.Code);
        Assert.Equal(
            ["record", "open", "promote", "apply", "delete", "delete-version",
             "verify", "verify-version", "finalize"],
            fixture.Trace);
        Assert.Equal("\"trusted-etag\"", fixture.Blobs.DeletedETag);
        Assert.Equal("trusted-version", fixture.Blobs.DeletedVersionId);
        Assert.True(fixture.Receipts.FinalizedApplied);
    }

    [Fact]
    public async Task Late_malicious_result_revokes_exact_trusted_content_before_acknowledgement()
    {
        var fixture = new Fixture();
        fixture.Assets.Mutation = new ProjectAssetMutation(
            true,
            "scan-result-superseded",
            AssetPublicId: AssetId,
            StorageStatus: ProjectAssetStorageStatus.Failed,
            ScanStatus: ProjectAssetScanStatus.Malicious,
            RevokedTrustedBlobContainer: "fp-project-trusted",
            RevokedTrustedBlobObjectName: "uploads/test.pdf",
            RevokedTrustedBlobETag: "trusted-etag",
            RevokedTrustedBlobVersionId: "trusted-version");

        var result = await fixture.Service.HandleAsync(
            Event("Malicious"), "Notification", "project-asset-defender-results",
            Caller(), CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Applied, result.Outcome);
        Assert.Equal("scan-result-superseded", result.Code);
        Assert.Equal(
            ["record", "open", "apply", "delete", "delete-version", "verify",
             "verify-version", "finalize"],
            fixture.Trace);
        Assert.Equal("\"trusted-etag\"", fixture.Blobs.DeletedETag);
        Assert.Equal("trusted-version", fixture.Blobs.DeletedVersionId);
        Assert.True(fixture.Receipts.FinalizedApplied);
    }

    [Fact]
    public async Task Revocation_is_retried_until_verified_absent()
    {
        var fixture = new Fixture();
        fixture.Assets.Mutation = new ProjectAssetMutation(
            true,
            "scan-result-superseded",
            AssetPublicId: AssetId,
            StorageStatus: ProjectAssetStorageStatus.Failed,
            ScanStatus: ProjectAssetScanStatus.Malicious,
            RevokedTrustedBlobContainer: "fp-project-trusted",
            RevokedTrustedBlobObjectName: "uploads/test.pdf",
            RevokedTrustedBlobETag: "\"trusted-etag\"",
            RevokedTrustedBlobVersionId: "trusted-version");
        fixture.Blobs.VerifiedVersionReceipt =
            new ProjectAssetBlobReceipt("\"trusted-etag\"", "trusted-version");

        var result = await fixture.Service.HandleAsync(
            Event("Malicious"), "Notification", "project-asset-defender-results",
            Caller(), CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Retry, result.Outcome);
        Assert.Equal("trusted-revocation-cleanup-incomplete", result.Code);
        Assert.Equal(0, fixture.Receipts.FinalizeCalls);
    }

    [Fact]
    public async Task Revocation_without_an_exact_version_id_fails_closed_before_deletion()
    {
        var fixture = new Fixture();
        fixture.Assets.Mutation = new ProjectAssetMutation(
            true,
            "scan-result-superseded",
            AssetPublicId: AssetId,
            StorageStatus: ProjectAssetStorageStatus.Failed,
            ScanStatus: ProjectAssetScanStatus.Malicious,
            RevokedTrustedBlobContainer: "fp-project-trusted",
            RevokedTrustedBlobObjectName: "uploads/test.pdf",
            RevokedTrustedBlobETag: "\"trusted-etag\"");

        var result = await fixture.Service.HandleAsync(
            Event("Malicious"), "Notification", "project-asset-defender-results",
            Caller(), CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Retry, result.Outcome);
        Assert.Equal("trusted-revocation-materialization-invalid", result.Code);
        Assert.DoesNotContain("delete", fixture.Trace);
        Assert.Equal(0, fixture.Receipts.FinalizeCalls);
    }

    [Fact]
    public async Task Revocation_cannot_delete_outside_the_exact_trusted_destination()
    {
        var fixture = new Fixture();
        fixture.Assets.Mutation = new ProjectAssetMutation(
            true,
            "scan-result-superseded",
            AssetPublicId: AssetId,
            StorageStatus: ProjectAssetStorageStatus.Failed,
            ScanStatus: ProjectAssetScanStatus.Malicious,
            RevokedTrustedBlobContainer: "other-container",
            RevokedTrustedBlobObjectName: "uploads/test.pdf",
            RevokedTrustedBlobETag: "\"trusted-etag\"");

        var result = await fixture.Service.HandleAsync(
            Event("Malicious"), "Notification", "project-asset-defender-results",
            Caller(), CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Retry, result.Outcome);
        Assert.Equal("trusted-revocation-materialization-invalid", result.Code);
        Assert.DoesNotContain("delete", fixture.Trace);
        Assert.Equal(0, fixture.Receipts.FinalizeCalls);
    }

    [Fact]
    public async Task Apply_data_failure_returns_retry_without_finalizing_receipt()
    {
        var fixture = new Fixture();
        fixture.Assets.ApplyFails = true;

        var result = await fixture.Service.HandleAsync(
            Event("Malicious"), "Notification", "project-asset-defender-results",
            Caller(), CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Retry, result.Outcome);
        Assert.Equal("scan-data-unavailable", result.Code);
        Assert.Equal(0, fixture.Receipts.FinalizeCalls);
    }

    [Fact]
    public async Task Finalize_dependency_failure_returns_retry_after_apply()
    {
        var fixture = new Fixture();
        fixture.Receipts.FinalizeFails = true;

        var result = await fixture.Service.HandleAsync(
            Event("Malicious"), "Notification", "project-asset-defender-results",
            Caller(), CancellationToken.None);

        Assert.Equal(ProjectAssetDefenderEventGridOutcome.Retry, result.Outcome);
        Assert.Equal("scan-finalization-unavailable", result.Code);
        Assert.Equal(1, fixture.Assets.ApplyCalls);
        Assert.Equal(1, fixture.Receipts.FinalizeCalls);
    }

    [Fact]
    public async Task Concrete_promoter_copies_only_PDF_documents()
    {
        var trace = new List<string>();
        var blobs = new FakeBlobs(trace);
        var subject = new ProjectAssetTrustedContentPromoter(blobs);
        var trusted = new ProtectedProjectAssetBlobLocation(
            "fp-project-trusted", "uploads/test.pdf");

        var document = await subject.PromoteAsync(
            ProjectAssetKind.Document,
            Quarantine,
            "\"0x1\"",
            trusted,
            "application/pdf",
            Pdf.Length,
            ContentHash,
            CancellationToken.None);
        var image = await subject.PromoteAsync(
            ProjectAssetKind.Image,
            Quarantine,
            "\"0x1\"",
            trusted,
            "image/png",
            Pdf.Length,
            ContentHash,
            CancellationToken.None);

        Assert.True(document.Succeeded);
        Assert.Equal("promoted", document.Code);
        Assert.Equal(["copy"], trace);
        Assert.False(image.Succeeded);
        Assert.Equal("image-sanitization-unavailable", image.Code);
    }

    [Fact]
    public async Task Watchdog_validates_bounds_and_uses_the_injected_clock()
    {
        var repository = new FakeWatchdog();
        var service = new ProjectAssetDefenderScanWatchdogService(
            repository, new FixedTimeProvider(Now));

        var result = await service.RunAsync(25, 300, CancellationToken.None);

        Assert.Empty(result);
        Assert.Equal(25, repository.BatchSize);
        Assert.Equal(18_000, repository.TimeoutSeconds);
        Assert.Equal(Now, repository.Now);
        await Assert.ThrowsAsync<ArgumentOutOfRangeException>(
            () => service.RunAsync(0, 300, CancellationToken.None));
        await Assert.ThrowsAsync<ArgumentOutOfRangeException>(
            () => service.RunAsync(25, 1_441, CancellationToken.None));
    }

    private const string Topic =
        "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourcegroups/rg/providers/microsoft.eventgrid/systemtopics/project-assets";

    private static EventGridCaller Caller() => new(
        Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
        Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
        Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc"));

    private static ProjectAssetDefenderReceiptWork DefaultWork() => new(
        true,
        "accepted",
        ReceiptId,
        AssetId,
        ProjectAssetKind.Document,
        ProjectAssetScanProvider.MicrosoftDefender,
        Quarantine,
        "\"0x1\"",
        ContentHash,
        Pdf.Length,
        "application/pdf",
        false);

    private static byte[] ValidationEvent(string topic) =>
        JsonSerializer.SerializeToUtf8Bytes(new[]
        {
            new
            {
                id = "validation-event",
                topic,
                eventType = "Microsoft.EventGrid.SubscriptionValidationEvent",
                data = new { validationCode = "validation-code" }
            }
        });

    private static byte[] Event(
        string scanResult,
        bool includeHash = true,
        string? hash = null,
        string? blobUri = null,
        string? subject = null)
    {
        var details = new Dictionary<string, object?>();
        if (includeHash)
            details["sha256"] = hash ?? Convert.ToHexString(ContentHash);
        return JsonSerializer.SerializeToUtf8Bytes(new[]
        {
            new
            {
                id = "project-asset-defender-event-1",
                topic = Topic.ToUpperInvariant(),
                subject = subject ??
                    "/storageAccounts/account/containers/fp-project-quarantine/blobs/uploads/test.pdf",
                eventType = "Microsoft.Security.MalwareScanningResult",
                eventTime = Now,
                dataVersion = "1.0",
                data = new
                {
                    blobUri = blobUri ??
                        "https://account.blob.core.windows.net/fp-project-quarantine/uploads/test.pdf",
                    eTag = "0x1",
                    scanResultType = scanResult,
                    scanFinishedTimeUtc = Now,
                    scanResultDetails = details
                }
            }
        });
    }

    private sealed class Fixture
    {
        public List<string> Trace { get; } = [];
        public FakeReceipts Receipts { get; }
        public FakeAssets Assets { get; }
        public FakeBlobs Blobs { get; }
        public FakePromoter Promoter { get; }
        public ProjectAssetDefenderEventGridService Service { get; }

        public Fixture()
        {
            Receipts = new FakeReceipts(Trace);
            Assets = new FakeAssets(Trace);
            Blobs = new FakeBlobs(Trace);
            Promoter = new FakePromoter(Trace);
            Service = new ProjectAssetDefenderEventGridService(
                Receipts,
                Assets,
                Blobs,
                Promoter,
                new ProjectAssetDefenderEventGridPolicy(
                    Topic,
                    "project-asset-defender-results",
                    "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourcegroups/rg/providers/microsoft.storage/storageaccounts/account",
                    new Uri("https://account.blob.core.windows.net"),
                    "fp-project-quarantine",
                    "fp-project-trusted",
                    10_485_760,
                    26_214_400,
                    TimeSpan.FromMinutes(5)),
                new FixedTimeProvider(Now));
        }
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private sealed class FakeReceipts(List<string> trace)
        : IProjectAssetDefenderScanReceiptRepository
    {
        public ProjectAssetDefenderReceiptWork Work { get; set; } = DefaultWork();
        public bool RecordFails { get; set; }
        public bool FinalizeFails { get; set; }
        public int FinalizeCalls { get; private set; }
        public bool FinalizedApplied { get; private set; }
        public byte[]? ReportedHash { get; private set; }

        public Task<ProjectAssetDefenderReceiptWork> RecordAsync(
            string eventGridEventId,
            byte[] payloadHash,
            EventGridCaller caller,
            string eventSubscriptionName,
            string topicResourceId,
            string storageAccountResourceId,
            string blobHost,
            ProtectedProjectAssetBlobLocation quarantineLocation,
            string blobETag,
            byte[]? reportedContentHash,
            ProjectAssetScanStatus status,
            string resultCode,
            DateTimeOffset occurredAtUtc,
            DateTimeOffset receivedAtUtc,
            CancellationToken cancellationToken)
        {
            trace.Add("record");
            ReportedHash = reportedContentHash;
            return RecordFails
                ? Task.FromException<ProjectAssetDefenderReceiptWork>(DataFailure("record"))
                : Task.FromResult(Work);
        }

        public Task FinalizeAsync(
            Guid receiptId,
            byte[] payloadHash,
            bool applied,
            string outcomeCode,
            DateTimeOffset finalizedAtUtc,
            CancellationToken cancellationToken)
        {
            trace.Add("finalize");
            FinalizeCalls++;
            FinalizedApplied = applied;
            return FinalizeFails
                ? Task.FromException(DataFailure("finalize"))
                : Task.CompletedTask;
        }
    }

    private sealed class FakeAssets(List<string> trace) : IProjectAssetRepository
    {
        public ProjectAssetMutation Mutation { get; set; } = new(
            true,
            "scan-result-applied",
            AssetPublicId: AssetId,
            ScanProvider: ProjectAssetScanProvider.MicrosoftDefender);
        public bool ApplyFails { get; set; }
        public int ApplyCalls { get; private set; }
        public ProjectAssetScanStatus? Status { get; private set; }
        public ProtectedProjectAssetBlobLocation? TrustedLocation { get; private set; }

        public Task<ProjectAssetMutation> ApplyScanResultAsync(
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
            CancellationToken cancellationToken)
        {
            trace.Add("apply");
            ApplyCalls++;
            Status = status;
            TrustedLocation = trustedLocation;
            if (ApplyFails) return Task.FromException<ProjectAssetMutation>(DataFailure("apply"));
            var storageStatus = status == ProjectAssetScanStatus.Clean
                ? ProjectAssetStorageStatus.Trusted
                : ProjectAssetStorageStatus.Failed;
            return Task.FromResult(Mutation with
            {
                StorageStatus = Mutation.StorageStatus ?? storageStatus,
                ScanStatus = Mutation.ScanStatus ?? status
            });
        }

        public Task<ProjectAssetMutation> CreateUploadIntentAsync(Guid a, Guid b, Guid c, byte[] d, ProjectAssetKind e, string f, string g, long h, long i, ProtectedProjectAssetBlobLocation j, ProtectedProjectAssetBlobLocation k, ProtectedProjectAssetBlobLocation l, byte[] m, DateTimeOffset n, CancellationToken o) => throw new NotSupportedException();
        public Task<ProjectAssetFinalizeWork> AcquireFinalizeAsync(Guid a, Guid b, Guid c, Guid d, byte[] e, Guid f, DateTimeOffset g, CancellationToken h) => throw new NotSupportedException();
        public Task<ProjectAssetMutation> ReleaseFinalizeAsync(Guid a, Guid b, Guid c, Guid d, Guid e, string f, CancellationToken g) => throw new NotSupportedException();
        public Task<ProjectAssetMutation> RejectFinalizeAsync(Guid a, Guid b, Guid c, Guid d, Guid e, string f, CancellationToken g) => throw new NotSupportedException();
        public Task<ProjectAssetMutation> CompleteUploadIntentAsync(Guid a, Guid b, Guid c, Guid d, Guid e, byte[] f, string g, long h, byte[] i, int? j, int? k, ProjectAssetScanProvider l, CancellationToken m) => throw new NotSupportedException();
        public Task<ProjectAssetMutation> MarkQuarantinedAsync(Guid a, Guid b, Guid c, Guid d, byte[] e, ProjectAssetBlobReceipt f, CancellationToken g) => throw new NotSupportedException();
        public Task<ProjectAssetCollection> ListAsync(Guid a, Guid b, Guid c, CancellationToken d) => throw new NotSupportedException();
        public Task<ProjectAssetUploadIntent?> GetUploadIntentAsync(Guid a, Guid b, Guid c, Guid d, CancellationToken e) => throw new NotSupportedException();
        public Task<ProjectAssetTrustedContent?> GetTrustedContentAsync(Guid a, Guid b, Guid c, Guid d, CancellationToken e) => throw new NotSupportedException();
        public Task<ProjectAssetMutation> UpdateMetadataAsync(Guid a, Guid b, Guid c, Guid d, byte[] e, byte[] f, ProjectAssetMetadata g, CancellationToken h) => throw new NotSupportedException();
        public Task<ProjectAssetMutation> ReorderAsync(Guid a, Guid b, Guid c, byte[] d, IReadOnlyList<ProjectAssetOrderItem> e, CancellationToken f) => throw new NotSupportedException();
        public Task<ProjectAssetMutation> DeleteAsync(Guid a, Guid b, Guid c, Guid d, byte[] e, byte[] f, CancellationToken g) => throw new NotSupportedException();
    }

    private sealed class FakeBlobs(List<string> trace) : IProjectAssetBlobStore
    {
        public byte[] Bytes { get; set; } = Pdf;
        public long? ReportedLength { get; set; }
        public ProjectAssetBlobReceipt? VerifiedReceipt { get; set; }
        public ProjectAssetBlobReceipt? VerifiedVersionReceipt { get; set; }
        public string? DeletedETag { get; private set; }
        public string? DeletedVersionId { get; private set; }

        public Task<ProjectAssetBlobRead> OpenReadAsync(
            ProtectedProjectAssetBlobLocation source,
            string? expectedETag,
            CancellationToken cancellationToken)
        {
            trace.Add("open");
            return Task.FromResult(new ProjectAssetBlobRead(
                new MemoryStream(Bytes, writable: false),
                ReportedLength ?? Bytes.Length,
                "application/pdf",
                "\"0x1\"",
                null));
        }

        public Task<ProjectAssetBlobReceipt> EnsureCopyAsync(
            ProtectedProjectAssetBlobLocation source,
            string sourceETag,
            ProtectedProjectAssetBlobLocation destination,
            string contentType,
            long expectedLength,
            byte[] expectedContentHash,
            CancellationToken cancellationToken)
        {
            trace.Add("copy");
            return Task.FromResult(
                new ProjectAssetBlobReceipt("\"trusted-etag\"", "trusted-version"));
        }

        public Task<ProjectAssetBlobReceipt?> GetVerifiedReceiptAsync(
            ProtectedProjectAssetBlobLocation location,
            string contentType,
            long expectedLength,
            byte[] expectedContentHash,
            CancellationToken cancellationToken)
        {
            trace.Add("verify");
            return Task.FromResult(VerifiedReceipt);
        }

        public Task<ProjectAssetBlobReceipt?> GetVerifiedVersionReceiptAsync(
            ProtectedProjectAssetBlobLocation location,
            string versionId,
            string contentType,
            long expectedLength,
            byte[] expectedContentHash,
            CancellationToken cancellationToken)
        {
            trace.Add("verify-version");
            return Task.FromResult(VerifiedVersionReceipt);
        }

        public Task DeleteIfMatchAsync(
            ProtectedProjectAssetBlobLocation location,
            string? expectedETag,
            CancellationToken cancellationToken)
        {
            trace.Add("delete");
            DeletedETag = expectedETag;
            return Task.CompletedTask;
        }

        public Task DeleteVersionIfMatchAsync(
            ProtectedProjectAssetBlobLocation location,
            string versionId,
            string expectedETag,
            CancellationToken cancellationToken)
        {
            trace.Add("delete-version");
            DeletedVersionId = versionId;
            DeletedETag = expectedETag;
            return Task.CompletedTask;
        }

        public Task<ProjectAssetUploadGrant> CreateUploadGrantAsync(ProtectedProjectAssetBlobLocation a, string b, DateTimeOffset c, CancellationToken d) => throw new NotSupportedException();
    }

    private sealed class FakePromoter(List<string> trace) : IProjectAssetTrustedContentPromoter
    {
        public ProjectAssetTrustedContentPromotion Result { get; set; } = new(
            true,
            "promoted",
            new ProjectAssetBlobReceipt("\"trusted-etag\"", "trusted-version"));

        public Task<ProjectAssetTrustedContentPromotion> PromoteAsync(
            ProjectAssetKind kind,
            ProtectedProjectAssetBlobLocation quarantineLocation,
            string quarantineETag,
            ProtectedProjectAssetBlobLocation trustedLocation,
            string contentType,
            long expectedLength,
            byte[] expectedContentHash,
            CancellationToken cancellationToken)
        {
            trace.Add("promote");
            return Task.FromResult(Result);
        }
    }

    private sealed class FakeWatchdog : IProjectAssetDefenderScanWatchdogRepository
    {
        public int BatchSize { get; private set; }
        public int TimeoutSeconds { get; private set; }
        public DateTimeOffset Now { get; private set; }

        public Task<IReadOnlyList<ProjectAssetDefenderScanWatchdogMutation>> TimeoutPendingAsync(
            int batchSize,
            int timeoutSeconds,
            DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
        {
            BatchSize = batchSize;
            TimeoutSeconds = timeoutSeconds;
            Now = nowUtc;
            return Task.FromResult<IReadOnlyList<ProjectAssetDefenderScanWatchdogMutation>>([]);
        }
    }

    private static ProjectAssetDataException DataFailure(string operation) => new(
        operation, -1, new InvalidOperationException("test data failure"));
}
