using FundingPlatform.Core.Validation;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Core.ProjectAssets;

namespace FundingPlatform.Application.ProjectAssets;

public sealed class ProjectAssetService(
    IProjectAssetRepository repository,
    IProjectAssetBlobStore blobStore,
    IProjectAssetContentInspector inspector,
    IProjectAssetScanner scanner,
    IProjectAssetTrustedContentPromoter promoter,
    IProjectAssetCompletionTokenService completionTokenService,
    ProjectAssetPolicy policy,
    TimeProvider timeProvider)
{
    public async Task<ProjectAssetCreateResult> CreateUploadIntentAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        byte[] expectedProjectRowVersion,
        ProjectAssetKind kind,
        string? fileName,
        string? mimeType,
        long contentLength,
        CancellationToken cancellationToken)
    {
        if (!policy.Enabled) return ProjectAssetCreateResult.Disabled();
        var normalizedMimeType = mimeType?.Trim().ToLowerInvariant();
        var errors = ValidateCreate(
            expectedProjectRowVersion, kind, fileName, normalizedMimeType, contentLength);
        if (errors.Count > 0)
            return ProjectAssetCreateResult.Invalid(MaximumFor(kind, normalizedMimeType), errors);

        var normalizedName = fileName!.Trim().Normalize(NormalizationForm.FormKC);
        var maximum = MaximumFor(kind, normalizedMimeType);
        var now = timeProvider.GetUtcNow();
        var expiresAt = now.Add(policy.UploadTimeToLive);
        var extension = CanonicalExtension(normalizedMimeType!);
        var randomLeaf = Convert.ToHexString(RandomNumberGenerator.GetBytes(16))
            .ToLowerInvariant();
        var objectName = string.Create(
            CultureInfo.InvariantCulture,
            $"{Guid.NewGuid():D}/{randomLeaf}{extension}");
        var incoming = new ProtectedProjectAssetBlobLocation(policy.IncomingContainer, objectName);
        var quarantine = new ProtectedProjectAssetBlobLocation(policy.QuarantineContainer, objectName);
        var trusted = new ProtectedProjectAssetBlobLocation(policy.TrustedContainer, objectName);
        var secret = completionTokenService.Create();

        ProjectAssetMutation mutation;
        try
        {
            mutation = await repository.CreateUploadIntentAsync(
                userPublicId,
                organizationPublicId,
                projectPublicId,
                expectedProjectRowVersion,
                kind,
                normalizedName,
                normalizedMimeType!,
                contentLength,
                maximum,
                incoming,
                quarantine,
                trusted,
                secret.Hash,
                expiresAt,
                cancellationToken);
        }
        catch (ProjectAssetDataException exception)
        {
            return CreateDataFailure(exception, maximum);
        }

        if (!mutation.Succeeded || mutation.IntentPublicId is null ||
            mutation.IntentStatus is null || mutation.ExpiresAtUtc is null ||
            mutation.IntentRowVersion is not { Length: 8 } ||
            mutation.ProjectRowVersion is not { Length: 8 })
            return ProjectAssetCreateResult.FromMutation(mutation, maximum);

        try
        {
            var grant = await blobStore.CreateUploadGrantAsync(
                incoming, normalizedMimeType!, mutation.ExpiresAtUtc.Value, cancellationToken);
            return new ProjectAssetCreateResult(
                ProjectAssetOutcome.Success,
                "created",
                mutation.IntentPublicId,
                kind,
                mutation.IntentStatus,
                mutation.ExpiresAtUtc,
                maximum,
                grant.UploadUri,
                grant.RequiredHeaders,
                secret.Token,
                mutation.IntentRowVersion,
                mutation.ProjectRowVersion);
        }
        catch (ProjectAssetStorageException)
        {
            // A completion token is never stored or reissued. The orphan intent expires.
            return new ProjectAssetCreateResult(
                ProjectAssetOutcome.Unavailable,
                "upload-grant-unavailable",
                MaxContentLength: maximum);
        }
    }

    public async Task<ProjectAssetOperationResult> CompleteUploadIntentAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid intentPublicId,
        string? completionToken,
        CancellationToken cancellationToken)
    {
        if (!policy.Enabled) return DisabledOperation(intentPublicId: intentPublicId);
        if (!completionTokenService.TryHash(completionToken ?? string.Empty, out var tokenHash))
            return new ProjectAssetOperationResult(
                ProjectAssetOutcome.NotFound, "invalid-token", IntentPublicId: intentPublicId);

        var leaseId = Guid.NewGuid();
        ProjectAssetFinalizeWork work;
        try
        {
            work = await repository.AcquireFinalizeAsync(
                userPublicId,
                organizationPublicId,
                projectPublicId,
                intentPublicId,
                tokenHash,
                leaseId,
                timeProvider.GetUtcNow().Add(policy.FinalizeLease),
                cancellationToken);
        }
        catch (ProjectAssetDataException exception)
        {
            return OperationDataFailure(exception, intentPublicId);
        }

        if (!work.Succeeded)
            return FromWork(MapCode(work.Code), work);
        if (work.Code == "finalizing")
            return FromWork(ProjectAssetOutcome.Processing, work);
        if (work.IntentStatus == ProjectAssetUploadIntentStatus.Completed)
        {
            try
            {
                return await ResumeCompletedAsync(
                    userPublicId, organizationPublicId, projectPublicId, work, cancellationToken);
            }
            catch (ProjectAssetStorageException exception)
            {
                return StorageFailure(exception, intentPublicId);
            }
            catch (ProjectAssetDataException exception)
            {
                return OperationDataFailure(exception, intentPublicId);
            }
        }

        if (work.Code != "acquired" || work.FinalizeLeaseId != leaseId ||
            work.IncomingLocation is null || work.QuarantineLocation is null ||
            work.TrustedLocation is null || work.ExpectedContentLength is null ||
            work.MaxContentLength is null || work.ProjectRowVersion is not { Length: 8 })
            return FromWork(ProjectAssetOutcome.Conflict, work, "invalid-finalize-work");

        try
        {
            await using var source = await blobStore.OpenReadAsync(
                work.IncomingLocation, null, cancellationToken);
            var inspection = await inspector.InspectAsync(
                work.Kind,
                source,
                work.ExpectedContentLength.Value,
                Math.Min(work.MaxContentLength.Value, MaximumFor(work.Kind)),
                policy.MaxImagePixels,
                cancellationToken);
            if (!inspection.IsValid || inspection.ContentHash is null ||
                string.IsNullOrWhiteSpace(inspection.VerifiedMimeType))
                return await RejectInvalidUploadAsync(
                    userPublicId,
                    organizationPublicId,
                    projectPublicId,
                    work,
                    leaseId,
                    source.ETag,
                    inspection.Failure,
                    cancellationToken);

            var completed = await repository.CompleteUploadIntentAsync(
                userPublicId,
                organizationPublicId,
                projectPublicId,
                intentPublicId,
                leaseId,
                work.ProjectRowVersion,
                inspection.VerifiedMimeType,
                inspection.ActualLength,
                inspection.ContentHash,
                inspection.PixelWidth,
                inspection.PixelHeight,
                policy.ScanProvider,
                cancellationToken);
            if (!completed.Succeeded || completed.AssetPublicId is null ||
                completed.AssetRowVersion is not { Length: 8 })
            {
                await ReleaseBestEffortAsync(
                    userPublicId, organizationPublicId, projectPublicId,
                    intentPublicId, leaseId, completed.Code);
                return FromMutation(completed);
            }

            return await QuarantineAndScanAsync(
                userPublicId,
                organizationPublicId,
                projectPublicId,
                work.Kind,
                work.IncomingLocation,
                source.ETag,
                work.QuarantineLocation,
                work.TrustedLocation,
                completed.AssetPublicId.Value,
                completed.AssetRowVersion,
                inspection.VerifiedMimeType,
                inspection.ActualLength,
                inspection.ContentHash,
                completed.ProjectRowVersion,
                cancellationToken);
        }
        catch (ProjectAssetStorageException exception)
        {
            await ReleaseBestEffortAsync(
                userPublicId, organizationPublicId, projectPublicId,
                intentPublicId, leaseId, exception.Code);
            return StorageFailure(exception, intentPublicId);
        }
        catch (ProjectAssetDataException exception)
        {
            return OperationDataFailure(exception, intentPublicId);
        }
    }

    public async Task<ProjectAssetReadResult<ProjectAssetCollection>> ListAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        CancellationToken cancellationToken)
    {
        if (!policy.Enabled) return ProjectAssetReadResult<ProjectAssetCollection>.Disabled();
        try
        {
            var collection = await repository.ListAsync(
                userPublicId, organizationPublicId, projectPublicId, cancellationToken);
            return new ProjectAssetReadResult<ProjectAssetCollection>(
                ProjectAssetOutcome.Success, "ok", collection);
        }
        catch (ProjectAssetDataException exception)
        {
            return ReadDataFailure<ProjectAssetCollection>(exception);
        }
    }

    public async Task<ProjectAssetReadResult<ProjectAssetUploadIntent>> GetUploadIntentAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid intentPublicId,
        CancellationToken cancellationToken)
    {
        if (!policy.Enabled) return ProjectAssetReadResult<ProjectAssetUploadIntent>.Disabled();
        try
        {
            var value = await repository.GetUploadIntentAsync(
                userPublicId, organizationPublicId, projectPublicId,
                intentPublicId, cancellationToken);
            return value is null
                ? new ProjectAssetReadResult<ProjectAssetUploadIntent>(
                    ProjectAssetOutcome.NotFound, "upload-intent-not-found")
                : new ProjectAssetReadResult<ProjectAssetUploadIntent>(
                    ProjectAssetOutcome.Success, "ok", value);
        }
        catch (ProjectAssetDataException exception)
        {
            return ReadDataFailure<ProjectAssetUploadIntent>(exception);
        }
    }

    public async Task<ProjectAssetOperationResult> UpdateMetadataAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid assetPublicId,
        byte[] expectedAssetRowVersion,
        byte[] expectedProjectRowVersion,
        ProjectAssetMetadata metadata,
        CancellationToken cancellationToken)
    {
        if (!policy.Enabled) return DisabledOperation(assetPublicId: assetPublicId);
        var normalized = metadata with
        {
            DisplayName = metadata.DisplayName?.Trim().Normalize(NormalizationForm.FormKC) ?? string.Empty,
            AltText = NormalizeOptional(metadata.AltText),
            Caption = NormalizeOptional(metadata.Caption)
        };
        var errors = ValidateMetadata(expectedAssetRowVersion, expectedProjectRowVersion, normalized);
        if (errors.Count > 0)
            return new ProjectAssetOperationResult(
                ProjectAssetOutcome.ValidationFailed, "invalid-metadata",
                AssetPublicId: assetPublicId, Errors: errors);
        try
        {
            return FromMutation(await repository.UpdateMetadataAsync(
                userPublicId,
                organizationPublicId,
                projectPublicId,
                assetPublicId,
                expectedAssetRowVersion,
                expectedProjectRowVersion,
                normalized,
                cancellationToken));
        }
        catch (ProjectAssetDataException exception)
        {
            return OperationDataFailure(exception, assetPublicId: assetPublicId);
        }
    }

    public async Task<ProjectAssetOperationResult> ReorderAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        byte[] expectedProjectRowVersion,
        IReadOnlyList<(Guid AssetPublicId, byte[] RowVersion)> items,
        CancellationToken cancellationToken)
    {
        if (!policy.Enabled) return DisabledOperation();
        var errors = new FieldValidationErrors();
        if (expectedProjectRowVersion.Length != 8)
            errors.Set("projectETag", "api-validation-149", "El ETag del proyecto no es válido.");
        if (items.Count > 12 || items.Select(item => item.AssetPublicId).Distinct().Count() != items.Count ||
            items.Any(item => item.AssetPublicId == Guid.Empty || item.RowVersion.Length != 8))
            errors.Set("items", "api-validation-150", "El orden debe contener hasta 12 adjuntos distintos con ETag válido.");
        if (errors.Count > 0)
            return new ProjectAssetOperationResult(
                ProjectAssetOutcome.ValidationFailed, "invalid-order", Errors: errors);
        var order = items.Select((item, index) => new ProjectAssetOrderItem(
            item.AssetPublicId, item.RowVersion, checked((short)index))).ToArray();
        try
        {
            return FromMutation(await repository.ReorderAsync(
                userPublicId,
                organizationPublicId,
                projectPublicId,
                expectedProjectRowVersion,
                order,
                cancellationToken));
        }
        catch (ProjectAssetDataException exception)
        {
            return OperationDataFailure(exception);
        }
    }

    public async Task<ProjectAssetOperationResult> DeleteAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid assetPublicId,
        byte[] expectedAssetRowVersion,
        byte[] expectedProjectRowVersion,
        CancellationToken cancellationToken)
    {
        if (!policy.Enabled) return DisabledOperation(assetPublicId: assetPublicId);
        if (expectedAssetRowVersion.Length != 8 || expectedProjectRowVersion.Length != 8)
            return new ProjectAssetOperationResult(
                ProjectAssetOutcome.ValidationFailed,
                "invalid-etag",
                AssetPublicId: assetPublicId,
                Errors: new FieldValidationErrors
                {
                    { "ifMatch", "api-validation-151", "Los ETag del adjunto y del proyecto son obligatorios." }
                });
        try
        {
            // SQL hides the record first. Physical blob retention cleanup is a separate worker concern.
            return FromMutation(await repository.DeleteAsync(
                userPublicId,
                organizationPublicId,
                projectPublicId,
                assetPublicId,
                expectedAssetRowVersion,
                expectedProjectRowVersion,
                cancellationToken));
        }
        catch (ProjectAssetDataException exception)
        {
            return OperationDataFailure(exception, assetPublicId: assetPublicId);
        }
    }

    public async Task<ProjectAssetContentResult> GetTrustedContentAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid assetPublicId,
        CancellationToken cancellationToken)
    {
        if (!policy.Enabled)
            return new ProjectAssetContentResult(ProjectAssetOutcome.Disabled, "project-assets-disabled");
        try
        {
            var claim = await repository.GetTrustedContentAsync(
                userPublicId, organizationPublicId, projectPublicId,
                assetPublicId, cancellationToken);
            if (claim is null)
                return new ProjectAssetContentResult(ProjectAssetOutcome.NotFound, "asset-content-not-found");
            var content = await blobStore.OpenReadAsync(
                claim.Location, claim.BlobETag, cancellationToken);
            if (content.ContentLength != claim.ContentLength ||
                !string.Equals(content.ContentType, claim.MimeType, StringComparison.OrdinalIgnoreCase))
            {
                await content.DisposeAsync();
                return new ProjectAssetContentResult(
                    ProjectAssetOutcome.Conflict, "trusted-content-conflict");
            }
            return new ProjectAssetContentResult(
                ProjectAssetOutcome.Success, "ok", claim, content);
        }
        catch (ProjectAssetStorageException)
        {
            return new ProjectAssetContentResult(
                ProjectAssetOutcome.Unavailable, "trusted-content-unavailable");
        }
        catch (ProjectAssetDataException exception)
        {
            var failure = ReadDataFailure<ProjectAssetTrustedContent>(exception);
            return new ProjectAssetContentResult(failure.Outcome, failure.Code);
        }
    }

    private async Task<ProjectAssetOperationResult> ResumeCompletedAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        ProjectAssetFinalizeWork work,
        CancellationToken cancellationToken)
    {
        if (work.AssetPublicId is null || work.AssetRowVersion is not { Length: 8 })
            return FromWork(ProjectAssetOutcome.Conflict, work, "invalid-completed-work");
        if (work.StorageStatus == ProjectAssetStorageStatus.Trusted &&
            work.ScanStatus == ProjectAssetScanStatus.Clean)
            return FromWork(ProjectAssetOutcome.Success, work, "ready");
        if (work.ScanStatus is ProjectAssetScanStatus.Malicious or
            ProjectAssetScanStatus.Failed or ProjectAssetScanStatus.TimedOut)
            return FromWork(ProjectAssetOutcome.Success, work, "scan-finished");
        if (work.IncomingLocation is null || work.QuarantineLocation is null ||
            work.TrustedLocation is null || work.ActualContentLength is null ||
            work.ContentHash is not { Length: 32 } ||
            string.IsNullOrWhiteSpace(work.VerifiedMimeType))
            return FromWork(ProjectAssetOutcome.Conflict, work, "invalid-resume-work");

        if (work.StorageStatus == ProjectAssetStorageStatus.AwaitingQuarantine)
        {
            await using var source = await blobStore.OpenReadAsync(
                work.IncomingLocation, null, cancellationToken);
            var inspection = await inspector.InspectAsync(
                work.Kind,
                source,
                work.ActualContentLength.Value,
                MaximumFor(work.Kind),
                policy.MaxImagePixels,
                cancellationToken);
            if (!inspection.IsValid || inspection.ContentHash is null ||
                !CryptographicOperations.FixedTimeEquals(inspection.ContentHash, work.ContentHash) ||
                !string.Equals(inspection.VerifiedMimeType, work.VerifiedMimeType,
                    StringComparison.OrdinalIgnoreCase))
                return FromWork(ProjectAssetOutcome.Conflict, work, "resume-content-conflict");
            return await QuarantineAndScanAsync(
                userPublicId,
                organizationPublicId,
                projectPublicId,
                work.Kind,
                work.IncomingLocation,
                source.ETag,
                work.QuarantineLocation,
                work.TrustedLocation,
                work.AssetPublicId.Value,
                work.AssetRowVersion,
                work.VerifiedMimeType,
                work.ActualContentLength.Value,
                work.ContentHash,
                null,
                cancellationToken,
                wasReplay: true);
        }

        if (work.StorageStatus != ProjectAssetStorageStatus.Quarantined ||
            string.IsNullOrWhiteSpace(work.QuarantineBlobETag))
            return FromWork(ProjectAssetOutcome.Conflict, work, "invalid-storage-state");
        return await ObserveAndApplyScanAsync(
            work.AssetPublicId.Value,
            work.Kind,
            work.QuarantineLocation,
            work.TrustedLocation,
            new ProjectAssetBlobReceipt(
                work.QuarantineBlobETag, work.QuarantineBlobVersionId),
            work.VerifiedMimeType,
            work.ActualContentLength.Value,
            work.ContentHash,
            null,
            cancellationToken,
            wasReplay: true);
    }

    private async Task<ProjectAssetOperationResult> QuarantineAndScanAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        ProjectAssetKind kind,
        ProtectedProjectAssetBlobLocation incomingLocation,
        string incomingETag,
        ProtectedProjectAssetBlobLocation quarantineLocation,
        ProtectedProjectAssetBlobLocation trustedLocation,
        Guid assetPublicId,
        byte[] assetRowVersion,
        string mimeType,
        long contentLength,
        byte[] contentHash,
        byte[]? projectRowVersion,
        CancellationToken cancellationToken,
        bool wasReplay = false)
    {
        var receipt = await blobStore.EnsureCopyAsync(
            incomingLocation,
            incomingETag,
            quarantineLocation,
            mimeType,
            contentLength,
            contentHash,
            cancellationToken);
        var marked = await repository.MarkQuarantinedAsync(
            userPublicId,
            organizationPublicId,
            projectPublicId,
            assetPublicId,
            assetRowVersion,
            receipt,
            cancellationToken);
        if (!marked.Succeeded || marked.AssetRowVersion is not { Length: 8 })
            return FromMutation(marked);
        await DeleteBestEffortAsync(incomingLocation, incomingETag);
        return await ObserveAndApplyScanAsync(
            assetPublicId,
            kind,
            quarantineLocation,
            trustedLocation,
            receipt,
            mimeType,
            contentLength,
            contentHash,
            marked.ProjectRowVersion ?? projectRowVersion,
            cancellationToken,
            wasReplay);
    }

    private async Task<ProjectAssetOperationResult> ObserveAndApplyScanAsync(
        Guid assetPublicId,
        ProjectAssetKind kind,
        ProtectedProjectAssetBlobLocation quarantineLocation,
        ProtectedProjectAssetBlobLocation trustedLocation,
        ProjectAssetBlobReceipt quarantineReceipt,
        string mimeType,
        long contentLength,
        byte[] contentHash,
        byte[]? projectRowVersion,
        CancellationToken cancellationToken,
        bool wasReplay = false)
    {
        var observation = await scanner.ObserveAsync(
            assetPublicId, quarantineLocation, quarantineReceipt.ETag, cancellationToken);
        if (observation.IsPending)
            return new ProjectAssetOperationResult(
                ProjectAssetOutcome.Processing,
                observation.ResultCode,
                AssetPublicId: assetPublicId,
                StorageStatus: ProjectAssetStorageStatus.Quarantined,
                ScanStatus: ProjectAssetScanStatus.Pending,
                ScanProvider: policy.ScanProvider,
                ProjectRowVersion: projectRowVersion,
                WasReplay: wasReplay);

        ProjectAssetTrustedBlob? trustedContent = null;
        var effectiveStatus = observation.Status;
        var effectiveResultCode = observation.ResultCode;
        if (observation.Status == ProjectAssetScanStatus.Clean)
        {
            var promotion = await promoter.PromoteAsync(
                new ProjectAssetTrustedContentRequest(
                    kind,
                    quarantineLocation,
                    quarantineReceipt.ETag,
                    trustedLocation,
                    mimeType,
                    contentLength,
                    contentHash,
                    MaximumFor(kind),
                    policy.MaxImagePixels),
                cancellationToken);
            if (promotion.IsRetryable)
                return new ProjectAssetOperationResult(
                    ProjectAssetOutcome.Unavailable,
                    promotion.Code,
                    AssetPublicId: assetPublicId,
                    StorageStatus: ProjectAssetStorageStatus.Quarantined,
                    ScanStatus: ProjectAssetScanStatus.Pending,
                    ScanProvider: policy.ScanProvider,
                    ProjectRowVersion: projectRowVersion,
                    WasReplay: wasReplay);
            if (!promotion.Succeeded)
            {
                if (!IsSanitizationRejectionCode(promotion.Code) ||
                    promotion.Content is not null)
                    return new ProjectAssetOperationResult(
                        ProjectAssetOutcome.Unavailable,
                        "trusted-promotion-materialization-invalid",
                        AssetPublicId: assetPublicId,
                        StorageStatus: ProjectAssetStorageStatus.Quarantined,
                        ScanStatus: ProjectAssetScanStatus.Pending,
                        ScanProvider: policy.ScanProvider,
                        ProjectRowVersion: projectRowVersion,
                        WasReplay: wasReplay);
                effectiveStatus = ProjectAssetScanStatus.Failed;
                effectiveResultCode = promotion.Code;
            }
            else if (promotion.Content is null ||
                     !SameLocation(promotion.Content.Location, trustedLocation) ||
                     !BlobETagNormalizer.TryNormalize(
                         promotion.Content.Receipt.ETag, out _) ||
                     !ProjectAssetTrustedContentRules.IsValid(
                         kind,
                         promotion.Content.Manifest,
                         mimeType,
                         contentLength,
                         contentHash,
                         MaximumFor(kind),
                         policy.MaxImagePixels))
            {
                return new ProjectAssetOperationResult(
                    ProjectAssetOutcome.Unavailable,
                    "trusted-promotion-materialization-invalid",
                    AssetPublicId: assetPublicId,
                    StorageStatus: ProjectAssetStorageStatus.Quarantined,
                    ScanStatus: ProjectAssetScanStatus.Pending,
                    ScanProvider: policy.ScanProvider,
                    ProjectRowVersion: projectRowVersion,
                    WasReplay: wasReplay);
            }
            else
            {
                trustedContent = promotion.Content;
            }
        }

        var payloadHash = SHA256.HashData(Encoding.UTF8.GetBytes(
            $"{assetPublicId:D}\n{observation.ObservationKey}\n{observation.ResultCode}\n" +
            $"{observation.Status}\n{quarantineReceipt.ETag}"));
        var mutation = await repository.ApplyScanResultAsync(
            assetPublicId,
            policy.ScanProvider,
            observation.ObservationKey,
            payloadHash,
            quarantineReceipt.ETag,
            contentHash,
            effectiveStatus,
            effectiveResultCode,
            trustedContent,
            observation.ObservedAtUtc,
            cancellationToken,
            observation.Status,
            observation.ResultCode);

        if (trustedContent is not null &&
            mutation.ScanStatus != ProjectAssetScanStatus.Clean)
        {
            var removed = await DeleteTrustedAndVerifyAsync(
                trustedContent, CancellationToken.None);
            if (!removed)
                return new ProjectAssetOperationResult(
                    ProjectAssetOutcome.Unavailable,
                    "trusted-promotion-cleanup-incomplete",
                    AssetPublicId: assetPublicId,
                    StorageStatus: mutation.StorageStatus,
                    ScanStatus: mutation.ScanStatus,
                    ScanProvider: mutation.ScanProvider,
                    AssetRowVersion: mutation.AssetRowVersion,
                    ProjectRowVersion: mutation.ProjectRowVersion ?? projectRowVersion,
                    WasReplay: mutation.WasReplay || wasReplay);
        }
        var result = FromMutation(mutation);
        return result with
        {
            ProjectRowVersion = result.ProjectRowVersion ?? projectRowVersion,
            WasReplay = result.WasReplay || wasReplay
        };
    }

    private async Task<bool> DeleteTrustedAndVerifyAsync(
        ProjectAssetTrustedBlob trusted,
        CancellationToken cancellationToken)
    {
        try
        {
            if (!BlobETagNormalizer.TryNormalize(
                    trusted.Receipt.ETag, out var normalizedTrustedETag))
                return false;

            await blobStore.DeleteIfMatchAsync(
                trusted.Location, normalizedTrustedETag, cancellationToken);
            if (!string.IsNullOrWhiteSpace(trusted.Receipt.VersionId))
            {
                await blobStore.DeleteVersionIfMatchAsync(
                    trusted.Location,
                    trusted.Receipt.VersionId,
                    normalizedTrustedETag,
                    cancellationToken);
                if (await blobStore.GetVerifiedVersionReceiptAsync(
                        trusted.Location,
                        trusted.Receipt.VersionId,
                        trusted.Manifest.MimeType,
                        trusted.Manifest.ContentLength,
                        trusted.Manifest.ContentHash,
                        cancellationToken) is not null)
                    return false;
            }
            return await blobStore.GetVerifiedReceiptAsync(
                trusted.Location,
                trusted.Manifest.MimeType,
                trusted.Manifest.ContentLength,
                trusted.Manifest.ContentHash,
                cancellationToken) is null;
        }
        catch (ProjectAssetStorageException)
        {
            return false;
        }
    }

    private static bool SameLocation(
        ProtectedProjectAssetBlobLocation left,
        ProtectedProjectAssetBlobLocation right) =>
        string.Equals(left.Container, right.Container, StringComparison.Ordinal) &&
        string.Equals(left.ObjectName, right.ObjectName, StringComparison.Ordinal);

    private static bool IsSanitizationRejectionCode(string code) => code is
        "image-format-rejected" or
        "image-decode-rejected" or
        "image-frame-count-rejected" or
        "image-dimensions-rejected" or
        "image-output-too-large";

    private async Task<ProjectAssetOperationResult> RejectInvalidUploadAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        ProjectAssetFinalizeWork work,
        Guid leaseId,
        string sourceETag,
        ProjectAssetInspectionFailure failure,
        CancellationToken cancellationToken)
    {
        var code = failure switch
        {
            ProjectAssetInspectionFailure.TooLarge => "file-too-large",
            ProjectAssetInspectionFailure.LengthMismatch => "length-mismatch",
            ProjectAssetInspectionFailure.InvalidContentType => "mime-mismatch",
            ProjectAssetInspectionFailure.ImageTooLarge => "image-pixel-limit",
            _ => "invalid-file-content"
        };
        var rejected = await repository.RejectFinalizeAsync(
            userPublicId,
            organizationPublicId,
            projectPublicId,
            work.IntentPublicId,
            leaseId,
            code,
            cancellationToken);
        if (!rejected.Succeeded ||
            rejected.IntentStatus != ProjectAssetUploadIntentStatus.Rejected ||
            !string.Equals(rejected.Code, "rejected", StringComparison.Ordinal))
            return FromMutation(rejected);
        await DeleteBestEffortAsync(work.IncomingLocation!, sourceETag);
        return new ProjectAssetOperationResult(
            ProjectAssetOutcome.ValidationFailed,
            code,
            IntentPublicId: work.IntentPublicId,
            IntentStatus: rejected.IntentStatus ?? ProjectAssetUploadIntentStatus.Rejected,
            IntentRowVersion: rejected.IntentRowVersion,
            ProjectRowVersion: rejected.ProjectRowVersion,
            Errors: new FieldValidationErrors
            {
                { "file", code, InspectionMessage(failure) }
            });
    }

    private FieldValidationErrors ValidateCreate(
        byte[] projectRowVersion,
        ProjectAssetKind kind,
        string? fileName,
        string? mimeType,
        long contentLength)
    {
        var errors = new FieldValidationErrors();
        if (projectRowVersion.Length != 8)
            errors.Set("projectETag", "api-validation-152", "El ETag del proyecto es obligatorio.");
        if (kind is not (ProjectAssetKind.Image or ProjectAssetKind.Document or ProjectAssetKind.Video))
            errors.Set("kind", "api-validation-153", "Sólo se admiten imágenes, PDF, texto UTF-8 y video MP4.");
        var normalizedName = fileName?.Trim().Normalize(NormalizationForm.FormKC);
        if (string.IsNullOrWhiteSpace(normalizedName) || normalizedName.Length > 260 ||
            normalizedName.Any(char.IsControl) || normalizedName.Contains('/') ||
            normalizedName.Contains('\\'))
            errors.Set("fileName", "api-validation-154", "Usa un nombre de archivo válido de hasta 260 caracteres.");
        if (!MimeMatchesName(kind, normalizedName, mimeType))
            errors.Set("mimeType", "api-validation-155", "La extensión y el tipo del archivo no coinciden o no están permitidos.");
        var maximum = MaximumFor(kind, mimeType);
        if (contentLength < 1 || contentLength > maximum)
            errors.Set("contentLength", "api-validation-156", $"El archivo debe pesar entre 1 byte y {maximum} bytes.", max: maximum);
        return errors;
    }

    private static FieldValidationErrors ValidateMetadata(
        byte[] assetRowVersion,
        byte[] projectRowVersion,
        ProjectAssetMetadata metadata)
    {
        var errors = new FieldValidationErrors();
        if (assetRowVersion.Length != 8 || projectRowVersion.Length != 8)
            errors.Set("ifMatch", "api-validation-151", "Los ETag del adjunto y del proyecto son obligatorios.");
        if (metadata.DisplayName.Length is < 1 or > 200)
            errors.Set("displayName", "api-validation-157", "El nombre visible debe tener entre 1 y 200 caracteres.");
        if (metadata.AltText?.Length > 300)
            errors.Set("altText", "api-validation-158", "El texto alternativo admite hasta 300 caracteres.");
        if (metadata.Caption?.Length > 1000)
            errors.Set("caption", "api-validation-159", "La descripción admite hasta 1000 caracteres.");
        if (metadata.IsCover && string.IsNullOrWhiteSpace(metadata.AltText))
            errors.Set("altText", "api-validation-160", "La portada necesita texto alternativo.");
        return errors;
    }

    private long MaximumFor(ProjectAssetKind kind, string? mimeType = null) => kind switch
    {
        ProjectAssetKind.Image => policy.MaxImageBytes,
        ProjectAssetKind.Document => mimeType == "text/plain" ? Math.Min(policy.MaxDocumentBytes, 1_048_576) : policy.MaxDocumentBytes,
        ProjectAssetKind.Video => policy.MaxDocumentBytes,
        _ => 0
    };

    private static bool MimeMatchesName(
        ProjectAssetKind kind,
        string? fileName,
        string? mimeType)
    {
        if (string.IsNullOrWhiteSpace(fileName) || string.IsNullOrWhiteSpace(mimeType)) return false;
        var extension = Path.GetExtension(fileName).ToLowerInvariant();
        return (kind, mimeType, extension) switch
        {
            (ProjectAssetKind.Image, "image/jpeg", ".jpg" or ".jpeg") => true,
            (ProjectAssetKind.Image, "image/png", ".png") => true,
            (ProjectAssetKind.Image, "image/webp", ".webp") => true,
            (ProjectAssetKind.Document, "application/pdf", ".pdf") => true,
            (ProjectAssetKind.Document, "text/plain", ".txt") => true,
            (ProjectAssetKind.Video, "video/mp4", ".mp4") => true,
            _ => false
        };
    }

    private static string CanonicalExtension(string mimeType) => mimeType switch
    {
        "image/jpeg" => ".jpg",
        "image/png" => ".png",
        "image/webp" => ".webp",
        "application/pdf" => ".pdf",
        "text/plain" => ".txt",
        "video/mp4" => ".mp4",
        _ => throw new ArgumentOutOfRangeException(nameof(mimeType))
    };

    private static string InspectionMessage(ProjectAssetInspectionFailure failure) => failure switch
    {
        ProjectAssetInspectionFailure.TooLarge => "El archivo supera el tamaño permitido.",
        ProjectAssetInspectionFailure.LengthMismatch => "El tamaño cargado no coincide con el declarado.",
        ProjectAssetInspectionFailure.InvalidContentType => "El tipo real del archivo no coincide.",
        ProjectAssetInspectionFailure.ImageTooLarge => "La imagen supera 25 millones de píxeles.",
        _ => "El contenido no corresponde a una imagen o PDF válido."
    };

    private static string? NormalizeOptional(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim().Normalize(NormalizationForm.FormKC);

    private static ProjectAssetCreateResult CreateDataFailure(
        ProjectAssetDataException exception,
        long maximum) => exception.DatabaseErrorNumber switch
        {
            55602 => new ProjectAssetCreateResult(
                ProjectAssetOutcome.Forbidden, "forbidden", MaxContentLength: maximum),
            55603 or 55604 => new ProjectAssetCreateResult(
                ProjectAssetOutcome.NotFound, "project-not-found", MaxContentLength: maximum),
            _ => new ProjectAssetCreateResult(
                ProjectAssetOutcome.Unavailable, "database-unavailable", MaxContentLength: maximum)
        };

    private static ProjectAssetOperationResult OperationDataFailure(
        ProjectAssetDataException exception,
        Guid? intentPublicId = null,
        Guid? assetPublicId = null) => exception.DatabaseErrorNumber switch
        {
            55602 => new ProjectAssetOperationResult(
                ProjectAssetOutcome.Forbidden, "forbidden", intentPublicId,
                AssetPublicId: assetPublicId),
            55603 or 55604 => new ProjectAssetOperationResult(
                ProjectAssetOutcome.NotFound, "not-found", intentPublicId,
                AssetPublicId: assetPublicId),
            55605 => new ProjectAssetOperationResult(
                ProjectAssetOutcome.Conflict, "project-etag-conflict", intentPublicId,
                AssetPublicId: assetPublicId),
            _ => new ProjectAssetOperationResult(
                ProjectAssetOutcome.Unavailable, "database-unavailable", intentPublicId,
                AssetPublicId: assetPublicId)
        };

    private static ProjectAssetOperationResult StorageFailure(
        ProjectAssetStorageException exception,
        Guid intentPublicId) => new(
        exception.Code == "blob-not-found"
            ? ProjectAssetOutcome.Conflict
            : ProjectAssetOutcome.Unavailable,
        exception.Code,
        IntentPublicId: intentPublicId);

    private static ProjectAssetReadResult<T> ReadDataFailure<T>(
        ProjectAssetDataException exception) => exception.DatabaseErrorNumber switch
        {
            55602 => new ProjectAssetReadResult<T>(ProjectAssetOutcome.Forbidden, "forbidden"),
            55603 or 55604 => new ProjectAssetReadResult<T>(ProjectAssetOutcome.NotFound, "not-found"),
            _ => new ProjectAssetReadResult<T>(
                ProjectAssetOutcome.Unavailable, "database-unavailable")
        };

    private static ProjectAssetOperationResult FromMutation(ProjectAssetMutation mutation) => new(
        mutation.Succeeded ? MapSuccessfulMutation(mutation) : MapCode(mutation.Code),
        mutation.Code,
        mutation.IntentPublicId,
        mutation.IntentStatus,
        mutation.AssetPublicId,
        mutation.StorageStatus,
        mutation.ScanStatus,
        mutation.ScanProvider,
        mutation.IntentRowVersion,
        mutation.AssetRowVersion,
        mutation.ProjectRowVersion,
        mutation.WasReplay);

    private static ProjectAssetOutcome MapSuccessfulMutation(ProjectAssetMutation mutation) =>
        mutation.ScanStatus == ProjectAssetScanStatus.Pending &&
        (mutation.StorageStatus is ProjectAssetStorageStatus.AwaitingQuarantine or
            ProjectAssetStorageStatus.Quarantined)
            ? ProjectAssetOutcome.Processing
            : ProjectAssetOutcome.Success;

    private static ProjectAssetOutcome MapCode(string code) => code switch
    {
        "project-assets-disabled" => ProjectAssetOutcome.Disabled,
        "project-not-found" or "asset-not-found" or "asset-deleted" or
            "upload-intent-not-found" or "not-found" or "invalid-token" or
            "content-unavailable" => ProjectAssetOutcome.NotFound,
        "forbidden" or "organization-admin-required" => ProjectAssetOutcome.Forbidden,
        "upload-intent-expired" or "expired" => ProjectAssetOutcome.Expired,
        "project-content-frozen" or "invalid-project-state" or "project-not-editable" =>
            ProjectAssetOutcome.InvalidState,
        "project-etag-conflict" or "asset-etag-conflict" or "etag-conflict" or
            "etag-mismatch" or "finalize-conflict" or "finalize-limit-reached" or
            "invalid-transition" or "invalid-state" or "content-conflict" or
            "completion-conflict" or "lease-conflict" or "lease-expired" or
            "asset-order-conflict" or "provider-event-conflict" or
            "trusted-destination-mismatch" or "provider-mismatch" or "hash-mismatch" or
            "rejected" => ProjectAssetOutcome.Conflict,
        "finalizing" or "finalize-busy" or "scan-pending" or "defender-result-pending" =>
            ProjectAssetOutcome.Processing,
        "invalid-asset" or "invalid-intent" or "invalid-order" or "invalid-metadata" or
            "invalid-lease" or "invalid-receipt" or "invalid-scan-result" or
            "verification-mismatch" or "asset-limit" or "image-limit" or
            "document-limit" or "pending-intent-limit" or "project-byte-limit" or
            "cover-alt-required" or "cover-image-required" or "cover-requires-image" or
            "cover-image-not-ready" =>
            ProjectAssetOutcome.ValidationFailed,
        _ => ProjectAssetOutcome.Unavailable
    };

    private static ProjectAssetOperationResult FromWork(
        ProjectAssetOutcome outcome,
        ProjectAssetFinalizeWork work,
        string? code = null) => new(
        outcome,
        code ?? work.Code,
        work.IntentPublicId,
        work.IntentStatus,
        work.AssetPublicId,
        work.StorageStatus,
        work.ScanStatus,
        work.ScanProvider,
        work.IntentRowVersion,
        work.AssetRowVersion,
        work.ProjectRowVersion,
        WasReplay: work.WasReplay);

    private static ProjectAssetOperationResult DisabledOperation(
        Guid? intentPublicId = null,
        Guid? assetPublicId = null) => new(
        ProjectAssetOutcome.Disabled,
        "project-assets-disabled",
        IntentPublicId: intentPublicId,
        AssetPublicId: assetPublicId);

    private async Task ReleaseBestEffortAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid intentPublicId,
        Guid leaseId,
        string errorCode)
    {
        try
        {
            await repository.ReleaseFinalizeAsync(
                userPublicId,
                organizationPublicId,
                projectPublicId,
                intentPublicId,
                leaseId,
                errorCode,
                CancellationToken.None);
        }
        catch
        {
            // Original storage failure is the useful result; an expired lease enables retry.
        }
    }

    private async Task DeleteBestEffortAsync(
        ProtectedProjectAssetBlobLocation location,
        string? expectedETag)
    {
        try
        {
            await blobStore.DeleteIfMatchAsync(location, expectedETag, CancellationToken.None);
        }
        catch
        {
            // Lifecycle cleanup removes abandoned incoming blobs.
        }
    }
}

public sealed record ProjectAssetCreateResult(
    ProjectAssetOutcome Outcome,
    string Code,
    Guid? IntentPublicId = null,
    ProjectAssetKind? Kind = null,
    ProjectAssetUploadIntentStatus? Status = null,
    DateTimeOffset? ExpiresAtUtc = null,
    long MaxContentLength = 0,
    Uri? UploadUri = null,
    IReadOnlyDictionary<string, string>? RequiredHeaders = null,
    string? CompletionToken = null,
    byte[]? IntentRowVersion = null,
    byte[]? ProjectRowVersion = null,
    IReadOnlyDictionary<string, string[]>? Errors = null)
{
    public static ProjectAssetCreateResult Disabled() => new(
        ProjectAssetOutcome.Disabled, "project-assets-disabled");

    public static ProjectAssetCreateResult Invalid(
        long maximum,
        IReadOnlyDictionary<string, string[]> errors) => new(
        ProjectAssetOutcome.ValidationFailed,
        "invalid-asset",
        MaxContentLength: maximum,
        Errors: errors);

    public static ProjectAssetCreateResult FromMutation(
        ProjectAssetMutation mutation,
        long maximum) => new(
        ProjectAssetServiceMap.Map(mutation.Code),
        mutation.Code,
        mutation.IntentPublicId,
        Status: mutation.IntentStatus,
        ExpiresAtUtc: mutation.ExpiresAtUtc,
        MaxContentLength: maximum,
        IntentRowVersion: mutation.IntentRowVersion,
        ProjectRowVersion: mutation.ProjectRowVersion);
}

public sealed record ProjectAssetReadResult<T>(
    ProjectAssetOutcome Outcome,
    string Code,
    T? Value = default)
{
    public static ProjectAssetReadResult<T> Disabled() => new(
        ProjectAssetOutcome.Disabled, "project-assets-disabled");
}

public sealed record ProjectAssetContentResult(
    ProjectAssetOutcome Outcome,
    string Code,
    ProjectAssetTrustedContent? Claim = null,
    ProjectAssetBlobRead? Content = null);

internal static class ProjectAssetServiceMap
{
    public static ProjectAssetOutcome Map(string code) => code switch
    {
        "project-not-found" or "asset-not-found" or "asset-deleted" or
            "upload-intent-not-found" or "not-found" => ProjectAssetOutcome.NotFound,
        "forbidden" or "organization-admin-required" => ProjectAssetOutcome.Forbidden,
        "upload-intent-expired" or "expired" => ProjectAssetOutcome.Expired,
        "project-content-frozen" or "invalid-project-state" or "project-not-editable" =>
            ProjectAssetOutcome.InvalidState,
        "project-etag-conflict" or "asset-etag-conflict" or "invalid-transition" or
            "etag-conflict" or "etag-mismatch" or "completion-conflict" or
            "lease-conflict" or "lease-expired" or "asset-order-conflict" =>
            ProjectAssetOutcome.Conflict,
        "invalid-asset" or "asset-limit" or "image-limit" or "document-limit" or
            "pending-intent-limit" or "project-byte-limit" or "cover-image-not-ready" =>
            ProjectAssetOutcome.ValidationFailed,
        _ => ProjectAssetOutcome.Unavailable
    };
}
