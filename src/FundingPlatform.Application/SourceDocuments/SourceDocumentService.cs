using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Core.SourceDocuments;

namespace FundingPlatform.Application.SourceDocuments;

public sealed class SourceDocumentService(
    ISourceDocumentRepository repository,
    ISourceDocumentBlobStore blobStore,
    ISourceDocumentContentInspector inspector,
    ISourceDocumentScanner scanner,
    ISourceDocumentCompletionTokenService completionTokenService,
    SourceDocumentPolicy policy,
    TimeProvider timeProvider)
{
    private const string PdfMimeType = "application/pdf";
    private const string IncomingPrefix = "uploads/";

    public async Task<SourceDocumentCreateResult> CreateUploadIntentAsync(
        Guid adminUserPublicId,
        int fundingSourceId,
        string? fileName,
        string? mimeType,
        long contentLength,
        CancellationToken cancellationToken)
    {
        var errors = ValidateCreate(fundingSourceId, fileName, mimeType, contentLength);
        if (errors.Count > 0)
        {
            return new SourceDocumentCreateResult
            {
                Outcome = SourceDocumentOutcome.ValidationFailed,
                Code = "invalid-document",
                MaxContentLength = policy.MaxBytes,
                Errors = errors
            };
        }

        var normalizedName = fileName!.Trim().Normalize(NormalizationForm.FormKC);
        var now = timeProvider.GetUtcNow();
        var expiresAt = now.Add(policy.UploadTimeToLive);
        var objectKey = Convert.ToHexString(RandomNumberGenerator.GetBytes(24)).ToLowerInvariant();
        var objectName = string.Create(
            CultureInfo.InvariantCulture,
            $"{IncomingPrefix}{now:yyyy/MM/dd}/{objectKey}.pdf");
        var incoming = new ProtectedBlobLocation(policy.IncomingContainer, objectName);
        var quarantine = new ProtectedBlobLocation(policy.QuarantineContainer, objectName);
        var completionSecret = completionTokenService.Create();

        SourceDocumentMutation mutation;
        try
        {
            mutation = await repository.CreateUploadIntentAsync(
                adminUserPublicId,
                fundingSourceId,
                normalizedName,
                PdfMimeType,
                contentLength,
                policy.MaxBytes,
                incoming,
                quarantine,
                completionSecret.Hash,
                expiresAt,
                cancellationToken);
        }
        catch (SourceDocumentDataException exception)
        {
            return DataFailure(exception);
        }

        if (!mutation.Succeeded || mutation.IntentPublicId is null ||
            mutation.ExpiresAtUtc is null || mutation.RowVersion is not { Length: 8 })
        {
            return new SourceDocumentCreateResult
            {
                Outcome = MapOutcome(mutation.Code),
                Code = mutation.Code,
                MaxContentLength = policy.MaxBytes
            };
        }

        try
        {
            var grant = await blobStore.CreateUploadGrantAsync(
                incoming, mutation.ExpiresAtUtc.Value, cancellationToken);
            return new SourceDocumentCreateResult
            {
                Outcome = SourceDocumentOutcome.Success,
                Code = "created",
                IntentPublicId = mutation.IntentPublicId,
                Status = mutation.IntentStatus,
                ExpiresAtUtc = mutation.ExpiresAtUtc,
                MaxContentLength = policy.MaxBytes,
                UploadUri = grant.UploadUri,
                RequiredHeaders = grant.RequiredHeaders,
                CompletionToken = completionSecret.Token,
                RowVersion = mutation.RowVersion
            };
        }
        catch (SourceDocumentStorageException)
        {
            // The one-time token is deliberately not persisted or reissued. This intent expires.
            return new SourceDocumentCreateResult
            {
                Outcome = SourceDocumentOutcome.Unavailable,
                Code = "upload-grant-unavailable",
                MaxContentLength = policy.MaxBytes
            };
        }
    }

    public async Task<SourceDocumentOperationResult> CompleteUploadIntentAsync(
        Guid adminUserPublicId,
        Guid intentPublicId,
        string? completionToken,
        CancellationToken cancellationToken)
    {
        if (!completionTokenService.TryHash(completionToken ?? string.Empty, out var tokenHash))
        {
            return new SourceDocumentOperationResult(
                SourceDocumentOutcome.NotFound, "invalid-token", intentPublicId);
        }

        var leaseId = Guid.NewGuid();
        SourceDocumentFinalizeWork work;
        try
        {
            work = await repository.AcquireFinalizeAsync(
                adminUserPublicId,
                intentPublicId,
                tokenHash,
                leaseId,
                timeProvider.GetUtcNow().Add(policy.FinalizeLease),
                cancellationToken);
        }
        catch (SourceDocumentDataException exception)
        {
            return OperationDataFailure(exception, intentPublicId);
        }

        if (!work.Succeeded)
        {
            return new SourceDocumentOperationResult(
                MapOutcome(work.Code),
                work.Code,
                intentPublicId,
                work.IntentStatus,
                work.SourceDocumentPublicId,
                work.StorageStatus,
                work.ScanStatus,
                work.ScanProvider,
                RowVersion: work.RowVersion,
                WasReplay: work.WasReplay);
        }

        if (work.Code == "finalizing")
        {
            return FromWork(SourceDocumentOutcome.Processing, work);
        }

        if (work.IntentStatus == SourceDocumentUploadIntentStatus.Completed)
        {
            return await ResumeCompletedAsync(
                adminUserPublicId, work, cancellationToken);
        }

        if (work.Code != "acquired" || work.IncomingLocation is null ||
            work.QuarantineLocation is null || work.ExpectedContentLength is null ||
            work.MaxContentLength is null || work.FinalizeLeaseId != leaseId)
        {
            return FromWork(SourceDocumentOutcome.Conflict, work, "invalid-finalize-work");
        }

        try
        {
            await using var source = await blobStore.OpenReadAsync(
                work.IncomingLocation, null, cancellationToken);
            var inspection = await inspector.InspectPdfAsync(
                source,
                work.ExpectedContentLength.Value,
                Math.Min(work.MaxContentLength.Value, policy.MaxBytes),
                cancellationToken);
            if (!inspection.IsValid || inspection.ContentHash is null)
            {
                return await RejectInvalidUploadAsync(
                    adminUserPublicId,
                    intentPublicId,
                    leaseId,
                    work.IncomingLocation,
                    source.ETag,
                    inspection.Failure,
                    cancellationToken);
            }

            var completion = await repository.CompleteUploadIntentAsync(
                adminUserPublicId,
                intentPublicId,
                leaseId,
                inspection.ActualLength,
                inspection.ContentHash,
                policy.ScanProvider,
                cancellationToken);
            if (!completion.Succeeded || completion.SourceDocumentPublicId is null)
            {
                return FromMutation(completion);
            }

            var receipt = await blobStore.EnsureCopyAsync(
                work.IncomingLocation,
                source.ETag,
                work.QuarantineLocation,
                inspection.ActualLength,
                inspection.ContentHash,
                cancellationToken);
            var marked = await repository.MarkQuarantinedAsync(
                adminUserPublicId,
                completion.SourceDocumentPublicId.Value,
                receipt,
                cancellationToken);
            if (!marked.Succeeded)
            {
                return FromMutation(marked);
            }

            await DeleteBestEffortAsync(work.IncomingLocation, source.ETag);
            return await ObserveAndApplyScanAsync(
                adminUserPublicId,
                completion.SourceDocumentPublicId.Value,
                work.QuarantineLocation,
                receipt.ETag,
                inspection.ContentHash,
                cancellationToken);
        }
        catch (SourceDocumentStorageException exception)
        {
            if (exception.Code == "blob-not-found")
            {
                await ReleaseBestEffortAsync(
                    adminUserPublicId, intentPublicId, leaseId, "blob-not-found");
                return new SourceDocumentOperationResult(
                    SourceDocumentOutcome.Conflict, "blob-not-found", intentPublicId,
                    SourceDocumentUploadIntentStatus.Pending);
            }

            await ReleaseBestEffortAsync(
                adminUserPublicId, intentPublicId, leaseId, "storage-unavailable");
            return new SourceDocumentOperationResult(
                SourceDocumentOutcome.Unavailable, "storage-unavailable", intentPublicId);
        }
        catch (SourceDocumentDataException exception)
        {
            return OperationDataFailure(exception, intentPublicId);
        }
    }

    public async Task<SourceDocumentOperationResult> RetryScanAsync(
        Guid adminUserPublicId,
        Guid sourceDocumentPublicId,
        byte[] expectedRowVersion,
        string? idempotencyKey,
        CancellationToken cancellationToken)
    {
        var normalizedKey = idempotencyKey?.Trim();
        if (expectedRowVersion is not { Length: 8 } ||
            string.IsNullOrWhiteSpace(normalizedKey) ||
            normalizedKey.Length is < 8 or > 128 ||
            normalizedKey.Contains('\r') || normalizedKey.Contains('\n'))
        {
            return new SourceDocumentOperationResult(
                SourceDocumentOutcome.ValidationFailed,
                "invalid-retry",
                SourceDocumentPublicId: sourceDocumentPublicId,
                Errors: new Dictionary<string, string[]>
                {
                    ["request"] = ["If-Match e Idempotency-Key válidos son obligatorios."]
                });
        }

        if (policy.ScanProvider == SourceDocumentScanProvider.MicrosoftDefender)
        {
            // Defender on-demand rescanning is a separate preview API with extra
            // permissions and cost. Do not mutate the durable state to Pending when
            // no explicit requester exists to perform that operation.
            return new SourceDocumentOperationResult(
                SourceDocumentOutcome.Conflict,
                "defender-rescan-not-configured",
                SourceDocumentPublicId: sourceDocumentPublicId);
        }

        var keyHash = SHA256.HashData(Encoding.UTF8.GetBytes(normalizedKey));
        var requestHash = SHA256.HashData(Encoding.UTF8.GetBytes(
            $"RetrySourceDocumentScan\n{sourceDocumentPublicId:D}\n{Convert.ToHexString(expectedRowVersion)}"));
        try
        {
            var mutation = await repository.RetryScanAsync(
                adminUserPublicId,
                sourceDocumentPublicId,
                expectedRowVersion,
                keyHash,
                requestHash,
                cancellationToken);
            if (!mutation.Succeeded || mutation.RowVersion is not { Length: 8 })
            {
                return new SourceDocumentOperationResult(
                    MapOutcome(mutation.Code),
                    mutation.Code,
                    SourceDocumentPublicId: mutation.SourceDocumentPublicId,
                    StorageStatus: mutation.StorageStatus,
                    ScanStatus: mutation.ScanStatus,
                    ScanProvider: mutation.ScanProvider,
                    ScanAttemptCount: mutation.ScanAttemptCount,
                    RowVersion: mutation.RowVersion,
                    WasReplay: mutation.WasReplay);
            }

            var scanWork = await repository.AcquireScanWorkAsync(
                adminUserPublicId,
                sourceDocumentPublicId,
                mutation.RowVersion,
                cancellationToken);
            if (!scanWork.Succeeded || scanWork.QuarantineLocation is null ||
                scanWork.ContentHash is null || string.IsNullOrWhiteSpace(scanWork.BlobETag))
            {
                if (scanWork.Code is "etag-conflict" or "invalid-transition")
                {
                    var current = await GetSourceDocumentAsync(
                        adminUserPublicId, sourceDocumentPublicId, cancellationToken);
                    if (current.Value is not null &&
                        current.Value.ScanStatus != SourceDocumentScanStatus.Pending)
                        return FromDocument(current.Value, wasReplay: true);
                }

                return new SourceDocumentOperationResult(
                    MapOutcome(scanWork.Code),
                    scanWork.Code,
                    SourceDocumentPublicId: sourceDocumentPublicId,
                    RowVersion: scanWork.RowVersion,
                    WasReplay: mutation.WasReplay);
            }

            return await ObserveAndApplyScanAsync(
                adminUserPublicId,
                sourceDocumentPublicId,
                scanWork.QuarantineLocation,
                scanWork.BlobETag,
                scanWork.ContentHash,
                cancellationToken);
        }
        catch (SourceDocumentDataException exception)
        {
            return OperationDataFailure(exception, sourceDocumentPublicId: sourceDocumentPublicId);
        }
    }

    public async Task<SourceDocumentQueryResult<SourceDocumentUploadIntent>> GetUploadIntentAsync(
        Guid adminUserPublicId,
        Guid intentPublicId,
        CancellationToken cancellationToken)
    {
        try
        {
            var value = await repository.GetUploadIntentAsync(
                adminUserPublicId, intentPublicId, cancellationToken);
            return value is null
                ? new SourceDocumentQueryResult<SourceDocumentUploadIntent>(SourceDocumentOutcome.NotFound)
                : new SourceDocumentQueryResult<SourceDocumentUploadIntent>(SourceDocumentOutcome.Success, value);
        }
        catch (SourceDocumentDataException exception)
        {
            return new SourceDocumentQueryResult<SourceDocumentUploadIntent>(
                IsForbidden(exception) ? SourceDocumentOutcome.Forbidden : SourceDocumentOutcome.Unavailable);
        }
    }

    public async Task<SourceDocumentQueryResult<SourceDocument>> GetSourceDocumentAsync(
        Guid adminUserPublicId,
        Guid sourceDocumentPublicId,
        CancellationToken cancellationToken)
    {
        try
        {
            var value = await repository.GetSourceDocumentAsync(
                adminUserPublicId, sourceDocumentPublicId, cancellationToken);
            return value is null
                ? new SourceDocumentQueryResult<SourceDocument>(SourceDocumentOutcome.NotFound)
                : new SourceDocumentQueryResult<SourceDocument>(SourceDocumentOutcome.Success, value);
        }
        catch (SourceDocumentDataException exception)
        {
            return new SourceDocumentQueryResult<SourceDocument>(
                IsForbidden(exception) ? SourceDocumentOutcome.Forbidden : SourceDocumentOutcome.Unavailable);
        }
    }

    private async Task<SourceDocumentOperationResult> ResumeCompletedAsync(
        Guid adminUserPublicId,
        SourceDocumentFinalizeWork work,
        CancellationToken cancellationToken)
    {
        if (work.SourceDocumentPublicId is null)
            return FromWork(SourceDocumentOutcome.Conflict, work, "completion-conflict");

        if (work.ScanStatus is not SourceDocumentScanStatus.Pending)
        {
            var terminal = await GetSourceDocumentAsync(
                adminUserPublicId, work.SourceDocumentPublicId.Value, cancellationToken);
            return terminal.Value is null
                ? FromWork(terminal.Outcome, work)
                : FromDocument(terminal.Value, work.WasReplay);
        }

        if (work.QuarantineLocation is null || work.ContentHash is null ||
            work.ActualContentLength is null)
            return FromWork(SourceDocumentOutcome.Conflict, work, "invalid-resume-work");

        try
        {
            var quarantineReceipt = work.StorageStatus switch
            {
                SourceDocumentStorageStatus.Quarantined when !string.IsNullOrWhiteSpace(work.BlobETag) =>
                    new SourceBlobReceipt(work.BlobETag, work.BlobVersionId),
                SourceDocumentStorageStatus.AwaitingQuarantine => await EnsureQuarantineAfterCrashAsync(
                    work, cancellationToken),
                _ => null
            };
            if (quarantineReceipt is null)
                return FromWork(SourceDocumentOutcome.Conflict, work, "invalid-storage-state");

            if (work.StorageStatus == SourceDocumentStorageStatus.AwaitingQuarantine)
            {
                var marked = await repository.MarkQuarantinedAsync(
                    adminUserPublicId,
                    work.SourceDocumentPublicId.Value,
                    quarantineReceipt,
                    cancellationToken);
                if (!marked.Succeeded) return FromMutation(marked);
                if (work.IncomingLocation is not null)
                    await DeleteBestEffortAsync(work.IncomingLocation, null);
            }

            return await ObserveAndApplyScanAsync(
                adminUserPublicId,
                work.SourceDocumentPublicId.Value,
                work.QuarantineLocation,
                quarantineReceipt.ETag,
                work.ContentHash,
                cancellationToken);
        }
        catch (SourceDocumentStorageException)
        {
            return FromWork(SourceDocumentOutcome.Unavailable, work, "storage-unavailable");
        }
        catch (SourceDocumentDataException exception)
        {
            return OperationDataFailure(
                exception, work.IntentPublicId, work.SourceDocumentPublicId);
        }
    }

    private async Task<SourceBlobReceipt> EnsureQuarantineAfterCrashAsync(
        SourceDocumentFinalizeWork work,
        CancellationToken cancellationToken)
    {
        var existing = await blobStore.GetVerifiedReceiptAsync(
            work.QuarantineLocation!,
            work.ActualContentLength!.Value,
            work.ContentHash!,
            cancellationToken);
        if (existing is not null) return existing;
        if (work.IncomingLocation is null)
            throw new SourceDocumentStorageException("resume-copy", "blob-not-found", 404);

        await using var source = await blobStore.OpenReadAsync(
            work.IncomingLocation, null, cancellationToken);
        var inspection = await inspector.InspectPdfAsync(
            source,
            work.ActualContentLength.Value,
            Math.Min(work.MaxContentLength ?? policy.MaxBytes, policy.MaxBytes),
            cancellationToken);
        if (!inspection.IsValid || inspection.ContentHash is null ||
            !CryptographicOperations.FixedTimeEquals(inspection.ContentHash, work.ContentHash!))
            throw new SourceDocumentStorageException("resume-copy", "content-conflict", 409);

        return await blobStore.EnsureCopyAsync(
            work.IncomingLocation,
            source.ETag,
            work.QuarantineLocation!,
            work.ActualContentLength.Value,
            work.ContentHash!,
            cancellationToken);
    }

    private async Task<SourceDocumentOperationResult> ObserveAndApplyScanAsync(
        Guid adminUserPublicId,
        Guid sourceDocumentPublicId,
        ProtectedBlobLocation quarantineLocation,
        string quarantineETag,
        byte[] contentHash,
        CancellationToken cancellationToken)
    {
        var query = await GetSourceDocumentAsync(
            adminUserPublicId, sourceDocumentPublicId, cancellationToken);
        if (query.Value is null)
            return new SourceDocumentOperationResult(query.Outcome, "source-document-not-found",
                SourceDocumentPublicId: sourceDocumentPublicId);
        var document = query.Value;
        if (document.ScanStatus != SourceDocumentScanStatus.Pending)
            return FromDocument(document, wasReplay: true);

        SourceDocumentScanObservation observation;
        try
        {
            observation = await scanner.ObserveAsync(
                sourceDocumentPublicId,
                document.ScanAttemptCount,
                quarantineLocation,
                quarantineETag,
                cancellationToken);
        }
        catch (SourceDocumentStorageException)
        {
            observation = new SourceDocumentScanObservation(
                SourceDocumentScanStatus.Failed,
                "scanner-unavailable",
                "scanner-unavailable",
                timeProvider.GetUtcNow());
        }

        if (observation.IsPending)
        {
            var started = document.ScanStartedAtUtc ?? document.UpdatedAtUtc;
            if (timeProvider.GetUtcNow() - started < policy.ScanTimeout)
            {
                return new SourceDocumentOperationResult(
                    SourceDocumentOutcome.Processing,
                    "scan-pending",
                    SourceDocumentPublicId: sourceDocumentPublicId,
                    StorageStatus: document.StorageStatus,
                    ScanStatus: document.ScanStatus,
                    ScanProvider: document.ScanProvider,
                    ScanAttemptCount: document.ScanAttemptCount,
                    RowVersion: document.RowVersion);
            }

            observation = new SourceDocumentScanObservation(
                SourceDocumentScanStatus.TimedOut,
                "scan-timeout",
                $"timeout-{document.ScanAttemptCount}",
                timeProvider.GetUtcNow());
        }

        ProtectedBlobLocation? trustedLocation = null;
        SourceBlobReceipt? trustedReceipt = null;
        if (observation.Status == SourceDocumentScanStatus.Clean)
        {
            trustedLocation = new ProtectedBlobLocation(
                policy.TrustedContainer, quarantineLocation.ObjectName);
            try
            {
                trustedReceipt = await blobStore.EnsureCopyAsync(
                    quarantineLocation,
                    quarantineETag,
                    trustedLocation,
                    document.ContentLength,
                    contentHash,
                    cancellationToken);
            }
            catch (SourceDocumentStorageException)
            {
                return new SourceDocumentOperationResult(
                    SourceDocumentOutcome.Unavailable,
                    "trusted-copy-unavailable",
                    SourceDocumentPublicId: sourceDocumentPublicId,
                    StorageStatus: document.StorageStatus,
                    ScanStatus: document.ScanStatus,
                    ScanProvider: document.ScanProvider,
                    ScanAttemptCount: document.ScanAttemptCount,
                    RowVersion: document.RowVersion);
            }
        }

        var eventMaterial = string.Create(
            CultureInfo.InvariantCulture,
            $"{sourceDocumentPublicId:D}\n{document.ScanAttemptCount}\n{quarantineETag}\n{observation.Status}\n{observation.ObservationKey}");
        var payloadHash = SHA256.HashData(Encoding.UTF8.GetBytes(eventMaterial));
        var providerEventId = $"fp:{Convert.ToHexString(payloadHash).ToLowerInvariant()}";
        var now = timeProvider.GetUtcNow();
        var occurredAt = observation.ObservedAtUtc < document.CreatedAtUtc ||
                         observation.ObservedAtUtc > now.AddMinutes(4)
            ? now
            : observation.ObservedAtUtc;
        try
        {
            var applied = await repository.ApplyScanResultAsync(
                sourceDocumentPublicId,
                document.ScanProvider,
                providerEventId,
                payloadHash,
                quarantineETag,
                observation.Status is SourceDocumentScanStatus.Clean or SourceDocumentScanStatus.Malicious
                    ? contentHash
                    : null,
                observation.Status,
                NormalizeResultCode(observation.ResultCode),
                trustedLocation,
                trustedReceipt,
                occurredAt,
                cancellationToken);
            return FromMutation(applied, document.ScanAttemptCount);
        }
        catch (SourceDocumentDataException exception)
        {
            return OperationDataFailure(
                exception, sourceDocumentPublicId: sourceDocumentPublicId);
        }
    }

    private async Task<SourceDocumentOperationResult> RejectInvalidUploadAsync(
        Guid adminUserPublicId,
        Guid intentPublicId,
        Guid leaseId,
        ProtectedBlobLocation incomingLocation,
        string sourceETag,
        SourceDocumentInspectionFailure failure,
        CancellationToken cancellationToken)
    {
        var code = failure switch
        {
            SourceDocumentInspectionFailure.TooLarge => "file-too-large",
            SourceDocumentInspectionFailure.LengthMismatch => "length-mismatch",
            SourceDocumentInspectionFailure.InvalidContentType => "invalid-content-type",
            _ => "invalid-pdf"
        };
        var rejected = await repository.RejectFinalizeAsync(
            adminUserPublicId, intentPublicId, leaseId, code, cancellationToken);
        await DeleteBestEffortAsync(incomingLocation, sourceETag);
        return new SourceDocumentOperationResult(
            rejected.Succeeded ? SourceDocumentOutcome.ValidationFailed : MapOutcome(rejected.Code),
            code,
            intentPublicId,
            rejected.IntentStatus,
            RowVersion: rejected.RowVersion,
            WasReplay: rejected.WasReplay,
            Errors: new Dictionary<string, string[]>
            {
                ["file"] = ["El archivo no es un PDF válido o no coincide con la carga declarada."]
            });
    }

    private async Task ReleaseBestEffortAsync(
        Guid adminUserPublicId,
        Guid intentPublicId,
        Guid leaseId,
        string code)
    {
        try
        {
            await repository.ReleaseFinalizeAsync(
                adminUserPublicId, intentPublicId, leaseId, code, CancellationToken.None);
        }
        catch (SourceDocumentDataException)
        {
            // A bounded lease makes the operation retryable even when release cannot be persisted.
        }
    }

    private async Task DeleteBestEffortAsync(
        ProtectedBlobLocation location,
        string? expectedETag)
    {
        try
        {
            await blobStore.DeleteIfMatchAsync(location, expectedETag, CancellationToken.None);
        }
        catch (SourceDocumentStorageException)
        {
            // The account lifecycle policy removes abandoned incoming blobs after its grace period.
        }
    }

    private Dictionary<string, string[]> ValidateCreate(
        int fundingSourceId,
        string? fileName,
        string? mimeType,
        long contentLength)
    {
        var errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        if (fundingSourceId <= 0)
            errors["fundingSourceId"] = ["Selecciona una fuente habilitada."];
        var normalizedName = fileName?.Trim();
        if (string.IsNullOrWhiteSpace(normalizedName) || normalizedName.Length > 260 ||
            !normalizedName.EndsWith(".pdf", StringComparison.OrdinalIgnoreCase) ||
            normalizedName != Path.GetFileName(normalizedName) ||
            normalizedName.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)
            errors["fileName"] = ["El nombre debe identificar un archivo PDF y no incluir una ruta."];
        if (!string.Equals(mimeType?.Trim(), PdfMimeType, StringComparison.OrdinalIgnoreCase))
            errors["mimeType"] = ["Sólo se admite application/pdf."];
        if (contentLength < 1 || contentLength > policy.MaxBytes)
            errors["contentLength"] = [$"El PDF debe pesar entre 1 y {policy.MaxBytes} bytes."];
        return errors;
    }

    private static string NormalizeResultCode(string value)
    {
        var normalized = value.Trim();
        if (normalized.Length is < 1 or > 100 || normalized.Contains('\r') || normalized.Contains('\n'))
            return "scanner-result";
        return normalized;
    }

    private static SourceDocumentCreateResult DataFailure(SourceDocumentDataException exception) =>
        new()
        {
            Outcome = IsForbidden(exception)
                ? SourceDocumentOutcome.Forbidden
                : SourceDocumentOutcome.Unavailable,
            Code = IsForbidden(exception) ? "forbidden" : "data-unavailable"
        };

    private static SourceDocumentOperationResult OperationDataFailure(
        SourceDocumentDataException exception,
        Guid? intentPublicId = null,
        Guid? sourceDocumentPublicId = null) => new(
            IsForbidden(exception) ? SourceDocumentOutcome.Forbidden : SourceDocumentOutcome.Unavailable,
            IsForbidden(exception) ? "forbidden" : "data-unavailable",
            intentPublicId,
            SourceDocumentPublicId: sourceDocumentPublicId);

    private static bool IsForbidden(SourceDocumentDataException exception) =>
        exception.DatabaseErrorNumber is 51601 or 51602 or 51701 or 51702;

    private static SourceDocumentOutcome MapOutcome(string code) => code switch
    {
        "created" or "completed" or "quarantined" or "trusted" or
            "scan-result-applied" or "scan-retry-requested" or "released" =>
            SourceDocumentOutcome.Success,
        "finalizing" or "scan-pending" => SourceDocumentOutcome.Processing,
        "invalid-document" or "invalid-source" or "length-mismatch" =>
            SourceDocumentOutcome.ValidationFailed,
        "not-found" or "invalid-token" => SourceDocumentOutcome.NotFound,
        "expired" => SourceDocumentOutcome.Expired,
        "invalid-transition" or "rejected" => SourceDocumentOutcome.InvalidTransition,
        "retry-limit-reached" or "finalize-limit-reached" =>
            SourceDocumentOutcome.RetryLimitReached,
        "etag-conflict" => SourceDocumentOutcome.PreconditionFailed,
        "lease-conflict" or "lease-expired" or "completion-conflict" or
            "idempotency-conflict" or "event-conflict" or
            "blob-etag-mismatch" or "blob-receipt-conflict" or "content-hash-mismatch" or
            "provider-mismatch" => SourceDocumentOutcome.Conflict,
        _ => SourceDocumentOutcome.Unavailable
    };

    private static SourceDocumentOperationResult FromWork(
        SourceDocumentOutcome outcome,
        SourceDocumentFinalizeWork work,
        string? code = null) => new(
            outcome,
            code ?? work.Code,
            work.IntentPublicId,
            work.IntentStatus,
            work.SourceDocumentPublicId,
            work.StorageStatus,
            work.ScanStatus,
            work.ScanProvider,
            RowVersion: work.RowVersion,
            WasReplay: work.WasReplay);

    private static SourceDocumentOperationResult FromMutation(
        SourceDocumentMutation mutation,
        short? scanAttemptCount = null) => new(
            mutation.Succeeded ?
                mutation.ScanStatus == SourceDocumentScanStatus.Pending
                    ? SourceDocumentOutcome.Processing
                    : SourceDocumentOutcome.Success
                : MapOutcome(mutation.Code),
            mutation.Code,
            mutation.IntentPublicId,
            mutation.IntentStatus,
            mutation.SourceDocumentPublicId,
            mutation.StorageStatus,
            mutation.ScanStatus,
            mutation.ScanProvider,
            scanAttemptCount,
            mutation.RowVersion,
            mutation.WasReplay);

    private static SourceDocumentOperationResult FromDocument(
        SourceDocument document,
        bool wasReplay) => new(
            document.ScanStatus == SourceDocumentScanStatus.Pending
                ? SourceDocumentOutcome.Processing
                : SourceDocumentOutcome.Success,
            document.ScanStatus == SourceDocumentScanStatus.Pending
                ? "scan-pending"
                : "completed",
            SourceDocumentPublicId: document.SourceDocumentPublicId,
            StorageStatus: document.StorageStatus,
            ScanStatus: document.ScanStatus,
            ScanProvider: document.ScanProvider,
            ScanAttemptCount: document.ScanAttemptCount,
            RowVersion: document.RowVersion,
            WasReplay: wasReplay);
}
