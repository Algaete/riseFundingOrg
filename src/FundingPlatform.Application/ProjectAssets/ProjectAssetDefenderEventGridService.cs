using System.Security.Cryptography;
using System.Text.Json;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Core.ProjectAssets;

namespace FundingPlatform.Application.ProjectAssets;

public sealed class ProjectAssetDefenderEventGridService(
    IProjectAssetDefenderScanReceiptRepository receipts,
    IProjectAssetRepository assets,
    IProjectAssetBlobStore blobStore,
    IProjectAssetTrustedContentPromoter promoter,
    ProjectAssetDefenderEventGridPolicy policy,
    TimeProvider timeProvider)
{
    private const int MaximumPayloadBytes = 64 * 1024;

    public async Task<ProjectAssetDefenderEventGridResult> HandleAsync(
        ReadOnlyMemory<byte> payload,
        string? eventTypeHeader,
        string? subscriptionName,
        EventGridCaller caller,
        CancellationToken cancellationToken)
    {
        if (payload.Length is < 2 or > MaximumPayloadBytes ||
            !OriginEquals(subscriptionName, policy.ExpectedSubscriptionName))
        {
            return Rejected("event-envelope-rejected");
        }

        JsonDocument envelope;
        try
        {
            envelope = JsonDocument.Parse(payload, new JsonDocumentOptions
            {
                AllowTrailingCommas = false,
                CommentHandling = JsonCommentHandling.Disallow,
                MaxDepth = 12
            });
        }
        catch (JsonException)
        {
            return Rejected("event-json-invalid");
        }

        using (envelope)
        {
            if (envelope.RootElement.ValueKind != JsonValueKind.Array ||
                envelope.RootElement.GetArrayLength() != 1)
            {
                return Rejected("event-batch-invalid");
            }

            var item = envelope.RootElement[0];
            if (item.ValueKind != JsonValueKind.Object ||
                !TryString(item, "eventType", 200, out var eventType) ||
                !TryString(item, "topic", 1024, out var topic) ||
                !OriginEquals(topic, policy.ExpectedTopicResourceId))
            {
                return Rejected("event-origin-rejected");
            }

            if (OriginEquals(eventTypeHeader, "SubscriptionValidation"))
            {
                if (!OriginEquals(
                        eventType, "Microsoft.EventGrid.SubscriptionValidationEvent") ||
                    !item.TryGetProperty("data", out var validationData) ||
                    validationData.ValueKind != JsonValueKind.Object ||
                    !TryString(validationData, "validationCode", 128, out var validationCode))
                {
                    return Rejected("subscription-validation-rejected");
                }

                return new ProjectAssetDefenderEventGridResult(
                    ProjectAssetDefenderEventGridOutcome.ValidationHandshake,
                    "subscription-validated",
                    validationCode);
            }

            if (!OriginEquals(eventTypeHeader, "Notification") ||
                !OriginEquals(eventType, "Microsoft.Security.MalwareScanningResult"))
            {
                return Rejected("event-type-rejected");
            }

            return await HandleScanAsync(item, payload, caller, cancellationToken);
        }
    }

    private async Task<ProjectAssetDefenderEventGridResult> HandleScanAsync(
        JsonElement item,
        ReadOnlyMemory<byte> payload,
        EventGridCaller caller,
        CancellationToken cancellationToken)
    {
        var now = timeProvider.GetUtcNow();
        if (!TryString(item, "id", 200, out var eventId) ||
            !TryString(item, "subject", 2048, out var subject) ||
            !TryString(item, "dataVersion", 20, out var dataVersion) ||
            !string.Equals(dataVersion, "1.0", StringComparison.Ordinal) ||
            !item.TryGetProperty("eventTime", out var eventTimeElement) ||
            !eventTimeElement.TryGetDateTimeOffset(out var eventTime) ||
            eventTime.Offset != TimeSpan.Zero ||
            eventTime > now.Add(policy.MaximumFutureClockSkew) ||
            !item.TryGetProperty("data", out var data) ||
            data.ValueKind != JsonValueKind.Object ||
            !TryString(data, "blobUri", 2048, out var blobUriText) ||
            !TryString(data, "eTag", 100, out var blobETag) ||
            !TryString(data, "scanResultType", 100, out var scanResult) ||
            !data.TryGetProperty("scanFinishedTimeUtc", out var finishedElement) ||
            !finishedElement.TryGetDateTimeOffset(out var finishedAt) ||
            finishedAt.Offset != TimeSpan.Zero ||
            finishedAt > now.Add(policy.MaximumFutureClockSkew) ||
            !BlobETagNormalizer.TryNormalize(blobETag, out var normalizedEventETag) ||
            !TryLocation(blobUriText, out var quarantineLocation) ||
            !SubjectMatches(subject, quarantineLocation!))
        {
            return Rejected("scan-event-invalid");
        }

        var (status, resultCode) = scanResult.ToLowerInvariant() switch
        {
            "no threats found" => (ProjectAssetScanStatus.Clean, "defender-clean"),
            "malicious" => (ProjectAssetScanStatus.Malicious, "defender-malicious"),
            "scan timed out" => (ProjectAssetScanStatus.TimedOut, "defender-timeout"),
            "error" or "not scanned" =>
                (ProjectAssetScanStatus.Failed, "defender-failed"),
            _ => ((ProjectAssetScanStatus?)null, "defender-result-unsupported")
        };
        if (status is null) return Rejected(resultCode);

        var hashResult = ReadReportedHash(data);
        if (!hashResult.IsValid)
            return Rejected("scan-content-hash-invalid");
        var reportedHash = hashResult.Hash;
        if (status is ProjectAssetScanStatus.Clean or ProjectAssetScanStatus.Malicious)
        {
            if (reportedHash is null)
                return Rejected("scan-content-hash-required");
        }

        var payloadHash = SHA256.HashData(payload.Span);
        ProjectAssetDefenderReceiptWork work;
        try
        {
            work = await receipts.RecordAsync(
                eventId,
                payloadHash,
                caller,
                policy.ExpectedSubscriptionName,
                policy.ExpectedTopicResourceId,
                policy.StorageAccountResourceId,
                policy.BlobServiceUri.Host,
                quarantineLocation!,
                normalizedEventETag,
                reportedHash,
                status.Value,
                resultCode,
                finishedAt,
                now,
                cancellationToken);
        }
        catch (ProjectAssetDataException)
        {
            return Retry("scan-receipt-unavailable");
        }

        if (work.Code == "replayed-applied")
        {
            return new ProjectAssetDefenderEventGridResult(
                ProjectAssetDefenderEventGridOutcome.Applied,
                work.Code,
                ProjectAssetId: work.ProjectAssetId);
        }
        if (work.Code is "replayed-ignored" or "replayed-rejected" || !work.Succeeded)
            return Rejected(work.Code);
        if (work.Code is not ("accepted" or "replayed-accepted"))
            return Rejected("scan-receipt-state-invalid");

        if (!TryMaterialize(work, out var maximumLength))
            return Retry("scan-receipt-materialization-invalid");

        try
        {
            if (!SameLocation(work.QuarantineLocation!, quarantineLocation!) ||
                !BlobETagNormalizer.TryNormalize(
                    work.QuarantineETag, out var normalizedStoredETag) ||
                !string.Equals(normalizedStoredETag, normalizedEventETag, StringComparison.Ordinal) ||
                (reportedHash is not null && !CryptographicOperations.FixedTimeEquals(
                    work.ContentHash!, reportedHash)))
            {
                return await FinalizeAsync(
                    work,
                    payloadHash,
                    applied: false,
                    "scan-content-conflict",
                    Rejected("scan-content-conflict"));
            }

            await using (var blob = await blobStore.OpenReadAsync(
                             work.QuarantineLocation!,
                             work.QuarantineETag,
                             cancellationToken))
            {
                var actualHash = await HashBoundedAsync(
                    blob,
                    work.ContentLength!.Value,
                    maximumLength,
                    cancellationToken);
                if (!CryptographicOperations.FixedTimeEquals(actualHash, work.ContentHash!) ||
                    (reportedHash is not null && !CryptographicOperations.FixedTimeEquals(
                        actualHash, reportedHash)))
                {
                    return await FinalizeAsync(
                        work,
                        payloadHash,
                        applied: false,
                        "scan-content-hash-mismatch",
                        Rejected("scan-content-hash-mismatch"));
                }
            }

            ProjectAssetTrustedBlob? trustedContent = null;
            var effectiveStatus = status.Value;
            var effectiveResultCode = resultCode;
            if (status == ProjectAssetScanStatus.Clean)
            {
                var trustedLocation = new ProtectedProjectAssetBlobLocation(
                    policy.TrustedContainer, work.QuarantineLocation!.ObjectName);
                var promotion = await promoter.PromoteAsync(
                    new ProjectAssetTrustedContentRequest(
                        work.Kind!.Value,
                        work.QuarantineLocation,
                        work.QuarantineETag!,
                        trustedLocation,
                        work.MimeType!,
                        work.ContentLength!.Value,
                        work.ContentHash!,
                        maximumLength,
                        policy.MaxImagePixels),
                    cancellationToken);
                if (promotion.IsRetryable)
                    return Retry(NormalizePromotionCode(promotion.Code));
                if (!promotion.Succeeded)
                {
                    if (!IsSanitizationRejectionCode(promotion.Code) ||
                        promotion.Content is not null)
                        return Retry("trusted-promotion-materialization-invalid");
                    effectiveStatus = ProjectAssetScanStatus.Failed;
                    effectiveResultCode = promotion.Code;
                }
                else if (promotion.Content is null ||
                         !ValidTrustedContent(
                             promotion.Content,
                             work.Kind.Value,
                             trustedLocation,
                             work.MimeType!,
                             work.ContentLength!.Value,
                             work.ContentHash!,
                             maximumLength))
                {
                    return Retry("trusted-promotion-materialization-invalid");
                }
                else
                {
                    trustedContent = promotion.Content;
                }

                if (trustedContent is not null)
                {
                    if (!BlobETagNormalizer.TryNormalize(
                            trustedContent.Receipt.ETag, out var normalizedTrustedETag))
                        return Retry("trusted-promotion-materialization-invalid");
                    if (!IsSafeVersionId(trustedContent.Receipt.VersionId))
                    {
                        // Defender promotion requires Blob Versioning. If infrastructure is
                        // misconfigured, remove the unreferenced current blob and keep the
                        // receipt retryable instead of persisting trust that cannot be revoked.
                        await blobStore.DeleteIfMatchAsync(
                            trustedLocation, normalizedTrustedETag, cancellationToken);
                        var remaining = await blobStore.GetVerifiedReceiptAsync(
                            trustedLocation,
                            trustedContent.Manifest.MimeType,
                            trustedContent.Manifest.ContentLength,
                            trustedContent.Manifest.ContentHash,
                            cancellationToken);
                        return Retry(remaining is null
                            ? "trusted-promotion-materialization-invalid"
                            : "trusted-promotion-cleanup-incomplete");
                    }
                }
            }

            var mutation = await assets.ApplyScanResultAsync(
                work.ProjectAssetId!.Value,
                ProjectAssetScanProvider.MicrosoftDefender,
                eventId,
                payloadHash,
                work.QuarantineETag!,
                reportedHash,
                effectiveStatus,
                effectiveResultCode,
                trustedContent,
                finishedAt,
                cancellationToken,
                status.Value,
                resultCode);

            if (trustedContent is not null &&
                mutation.ScanStatus != ProjectAssetScanStatus.Clean)
            {
                var cleanup = await DeleteAndVerifyAsync(
                    trustedContent,
                    "trusted-copy",
                    cancellationToken);
                if (cleanup is not null) return cleanup;
            }

            if (!mutation.Succeeded)
            {
                var code = NormalizeMutationCode(mutation.Code);
                return await FinalizeAsync(
                    work, payloadHash, applied: false, code, Rejected(code));
            }

            if (IsSupersededCode(mutation.Code))
            {
                if (!TryRevokedTrustedContent(
                        mutation,
                        work.Kind!.Value,
                        work.QuarantineLocation!.ObjectName,
                        work.MimeType!,
                        work.ContentLength!.Value,
                        work.ContentHash!,
                        maximumLength,
                        out var revokedContent))
                {
                    return Retry("trusted-revocation-materialization-invalid");
                }

                var cleanup = await DeleteAndVerifyAsync(
                    revokedContent!,
                    "trusted-revocation",
                    cancellationToken);
                if (cleanup is not null) return cleanup;
            }

            var mutationApplied = IsAppliedCode(mutation.Code);
            var terminalCode = NormalizeMutationCode(mutation.Code);
            var terminalResult = new ProjectAssetDefenderEventGridResult(
                ProjectAssetDefenderEventGridOutcome.Applied,
                terminalCode,
                ProjectAssetId: work.ProjectAssetId);
            return await FinalizeAsync(
                work, payloadHash, mutationApplied, terminalCode, terminalResult);
        }
        catch (ProjectAssetStorageException)
        {
            return Retry("scan-storage-unavailable");
        }
        catch (ProjectAssetDataException)
        {
            return Retry("scan-data-unavailable");
        }
        catch (InvalidDataException)
        {
            return await FinalizeAsync(
                work,
                payloadHash,
                applied: false,
                "scan-content-conflict",
                Rejected("scan-content-conflict"));
        }
    }

    private async Task<ProjectAssetDefenderEventGridResult?> DeleteAndVerifyAsync(
        ProjectAssetTrustedBlob trusted,
        string codePrefix,
        CancellationToken cancellationToken)
    {
        if (!BlobETagNormalizer.TryNormalize(
                trusted.Receipt.ETag, out var normalizedETag) ||
            !IsSafeVersionId(trusted.Receipt.VersionId))
            return Retry($"{codePrefix}-materialization-invalid");
        await blobStore.DeleteIfMatchAsync(
            trusted.Location, normalizedETag, cancellationToken);
        await blobStore.DeleteVersionIfMatchAsync(
            trusted.Location,
            trusted.Receipt.VersionId!,
            normalizedETag,
            cancellationToken);
        var remaining = await blobStore.GetVerifiedReceiptAsync(
            trusted.Location,
            trusted.Manifest.MimeType,
            trusted.Manifest.ContentLength,
            trusted.Manifest.ContentHash,
            cancellationToken);
        var remainingVersion = await blobStore.GetVerifiedVersionReceiptAsync(
            trusted.Location,
            trusted.Receipt.VersionId!,
            trusted.Manifest.MimeType,
            trusted.Manifest.ContentLength,
            trusted.Manifest.ContentHash,
            cancellationToken);
        return remaining is null && remainingVersion is null
            ? null
            : Retry($"{codePrefix}-cleanup-incomplete");
    }

    private async Task<ProjectAssetDefenderEventGridResult> FinalizeAsync(
        ProjectAssetDefenderReceiptWork work,
        byte[] payloadHash,
        bool applied,
        string outcomeCode,
        ProjectAssetDefenderEventGridResult terminalResult)
    {
        try
        {
            await receipts.FinalizeAsync(
                work.ReceiptId!.Value,
                payloadHash,
                applied,
                outcomeCode,
                timeProvider.GetUtcNow(),
                CancellationToken.None);
            return terminalResult;
        }
        catch (ProjectAssetDataException)
        {
            return Retry("scan-finalization-unavailable");
        }
    }

    private bool TryMaterialize(
        ProjectAssetDefenderReceiptWork work,
        out long maximumLength)
    {
        maximumLength = work.Kind switch
        {
            ProjectAssetKind.Image => policy.MaxImageBytes,
            ProjectAssetKind.Document => policy.MaxDocumentBytes,
            _ => 0
        };
        return work.ReceiptId is not null &&
               work.ProjectAssetId is not null &&
               work.Kind is ProjectAssetKind.Image or ProjectAssetKind.Document &&
               work.ScanProvider == ProjectAssetScanProvider.MicrosoftDefender &&
               work.QuarantineLocation is not null &&
               work.QuarantineETag is not null &&
               work.ContentHash is { Length: 32 } &&
               work.ContentLength is >= 1 &&
               work.ContentLength <= maximumLength &&
               MimeMatchesKind(work.Kind.Value, work.MimeType);
    }

    private bool ValidTrustedContent(
        ProjectAssetTrustedBlob content,
        ProjectAssetKind kind,
        ProtectedProjectAssetBlobLocation expectedLocation,
        string sourceMimeType,
        long sourceContentLength,
        byte[] sourceContentHash,
        long maximumLength) =>
        SameLocation(content.Location, expectedLocation) &&
        BlobETagNormalizer.TryNormalize(content.Receipt.ETag, out _) &&
        ProjectAssetTrustedContentRules.IsValid(
            kind,
            content.Manifest,
            sourceMimeType,
            sourceContentLength,
            sourceContentHash,
            maximumLength,
            policy.MaxImagePixels);

    private static bool IsSanitizationRejectionCode(string code) => code is
        "image-format-rejected" or
        "image-decode-rejected" or
        "image-frame-count-rejected" or
        "image-dimensions-rejected" or
        "image-output-too-large";

    private static (bool IsValid, byte[]? Hash) ReadReportedHash(JsonElement data)
    {
        if (!data.TryGetProperty("scanResultDetails", out var details))
            return (true, null);
        if (details.ValueKind != JsonValueKind.Object)
            return (false, null);
        if (!details.TryGetProperty("sha256", out var hashElement))
            return (true, null);
        if (hashElement.ValueKind != JsonValueKind.String)
            return (false, null);
        var value = hashElement.GetString()?.Trim() ?? string.Empty;
        return TryHash(value, out var hash) ? (true, hash) : (false, null);
    }

    private static bool MimeMatchesKind(ProjectAssetKind kind, string? mimeType) => kind switch
    {
        ProjectAssetKind.Image => mimeType is not null &&
            (mimeType.Equals("image/jpeg", StringComparison.OrdinalIgnoreCase) ||
             mimeType.Equals("image/png", StringComparison.OrdinalIgnoreCase) ||
             mimeType.Equals("image/webp", StringComparison.OrdinalIgnoreCase)),
        ProjectAssetKind.Document =>
            string.Equals(mimeType, "application/pdf", StringComparison.OrdinalIgnoreCase),
        _ => false
    };

    private bool TryRevokedTrustedContent(
        ProjectAssetMutation mutation,
        ProjectAssetKind kind,
        string expectedObjectName,
        string sourceMimeType,
        long sourceContentLength,
        byte[] sourceContentHash,
        long maximumLength,
        out ProjectAssetTrustedBlob? content)
    {
        content = null;
        if (string.IsNullOrWhiteSpace(mutation.RevokedTrustedBlobContainer) ||
            string.IsNullOrWhiteSpace(mutation.RevokedTrustedBlobObjectName) ||
            string.IsNullOrWhiteSpace(mutation.RevokedTrustedBlobETag) ||
            !IsSafeVersionId(mutation.RevokedTrustedBlobVersionId) ||
            !string.Equals(
                mutation.RevokedTrustedBlobContainer,
                policy.TrustedContainer,
                StringComparison.Ordinal) ||
            !string.Equals(
                mutation.RevokedTrustedBlobObjectName,
                expectedObjectName,
                StringComparison.Ordinal) ||
            !TryRevokedManifest(
                mutation,
                kind,
                sourceMimeType,
                sourceContentLength,
                sourceContentHash,
                maximumLength,
                out var manifest))
            return false;
        content = new ProjectAssetTrustedBlob(
            new ProtectedProjectAssetBlobLocation(
                mutation.RevokedTrustedBlobContainer,
                mutation.RevokedTrustedBlobObjectName),
            new ProjectAssetBlobReceipt(
                mutation.RevokedTrustedBlobETag,
                mutation.RevokedTrustedBlobVersionId),
            manifest!);
        return true;
    }

    private bool TryRevokedManifest(
        ProjectAssetMutation mutation,
        ProjectAssetKind kind,
        string sourceMimeType,
        long sourceContentLength,
        byte[] sourceContentHash,
        long maximumLength,
        out ProjectAssetTrustedContentManifest? manifest)
    {
        manifest = null;
        if (string.IsNullOrWhiteSpace(mutation.RevokedTrustedMimeType) ||
            mutation.RevokedTrustedContentLength is not > 0 ||
            mutation.RevokedTrustedContentHash is not { Length: 32 } ||
            string.IsNullOrWhiteSpace(mutation.RevokedTrustedProcessingVersion) ||
            mutation.RevokedTrustedCreatedAtUtc is null)
            return false;
        var value = new ProjectAssetTrustedContentManifest(
            mutation.RevokedTrustedMimeType,
            mutation.RevokedTrustedContentLength.Value,
            mutation.RevokedTrustedContentHash,
            mutation.RevokedTrustedPixelWidth,
            mutation.RevokedTrustedPixelHeight,
            mutation.RevokedTrustedProcessingVersion);
        if (!ProjectAssetTrustedContentRules.IsValid(
                kind,
                value,
                sourceMimeType,
                sourceContentLength,
                sourceContentHash,
                maximumLength,
                policy.MaxImagePixels))
            return false;
        manifest = value;
        return true;
    }

    private static bool IsAppliedCode(string? code) =>
        code is "applied" or "scan-result-applied" or "scan-result-superseded";

    private static bool IsSupersededCode(string? code) =>
        code == "scan-result-superseded";

    private static string NormalizeMutationCode(string? code) => code switch
    {
        "applied" or "scan-result-applied" or "scan-result-superseded" or
            "scan-result-ignored" or "duplicate-scan-result" or
            "stale-scan-result" or "terminal-scan-result-conflict" or
            "invalid-transition" or "invalid-state" or "event-conflict" or
            "provider-event-conflict" or "provider-mismatch" or
            "blob-etag-mismatch" or "etag-mismatch" or
            "content-hash-mismatch" or "hash-mismatch" or
            "invalid-event-time" or "invalid-trusted-location" or
            "trusted-destination-mismatch" or "asset-deleted" or "not-found" => code,
        _ => "scan-result-rejected"
    };

    private static string NormalizePromotionCode(string? code) => code switch
    {
        "image-storage-retry" or
        "image-native-retry" or
        "image-processing-retry" or
        "pdf-storage-retry" => code,
        _ => "trusted-promotion-unavailable"
    };

    private bool SubjectMatches(
        string subject,
        ProtectedProjectAssetBlobLocation location)
    {
        try
        {
            var account = policy.BlobServiceUri.Host.Split('.', 2)[0];
            var decoded = Uri.UnescapeDataString(subject.TrimStart('/'));
            var prefix = $"storageAccounts/{account}/containers/{location.Container}/blobs/";
            return decoded.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) &&
                   string.Equals(
                       decoded[prefix.Length..], location.ObjectName, StringComparison.Ordinal);
        }
        catch (UriFormatException)
        {
            return false;
        }
    }

    private bool TryLocation(
        string text,
        out ProtectedProjectAssetBlobLocation? location)
    {
        location = null;
        if (!Uri.TryCreate(text, UriKind.Absolute, out var uri) ||
            uri.Scheme != Uri.UriSchemeHttps || uri.Port != 443 ||
            !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment) ||
            !string.IsNullOrEmpty(uri.UserInfo) ||
            !string.Equals(
                uri.Host, policy.BlobServiceUri.Host, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        try
        {
            var segments = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
            if (segments.Length < 2) return false;
            var container = Uri.UnescapeDataString(segments[0]);
            var objectName = string.Join('/', segments.Skip(1).Select(Uri.UnescapeDataString));
            if (!string.Equals(container, policy.QuarantineContainer, StringComparison.Ordinal) ||
                objectName.Length is < 1 or > 1024 || objectName.Contains('\0') ||
                objectName.Contains('\r') || objectName.Contains('\n') ||
                objectName.Contains('\\') || objectName.Contains('?') ||
                objectName.Contains('#'))
            {
                return false;
            }
            location = new ProtectedProjectAssetBlobLocation(container, objectName);
            return true;
        }
        catch (UriFormatException)
        {
            return false;
        }
    }

    private static async Task<byte[]> HashBoundedAsync(
        ProjectAssetBlobRead blob,
        long expectedLength,
        long maximumLength,
        CancellationToken cancellationToken)
    {
        if (blob.ContentLength != expectedLength || blob.ContentLength > maximumLength)
            throw new InvalidDataException("Blob length conflict.");
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        var buffer = new byte[64 * 1024];
        long total = 0;
        int read;
        while ((read = await blob.Content.ReadAsync(buffer, cancellationToken)) > 0)
        {
            total += read;
            if (total > expectedLength || total > maximumLength)
                throw new InvalidDataException("Blob length conflict.");
            hash.AppendData(buffer, 0, read);
        }
        if (total != expectedLength)
            throw new InvalidDataException("Blob length conflict.");
        return hash.GetHashAndReset();
    }

    private static bool TryString(
        JsonElement owner,
        string property,
        int maximumLength,
        out string value)
    {
        value = string.Empty;
        if (!owner.TryGetProperty(property, out var element) ||
            element.ValueKind != JsonValueKind.String)
            return false;
        value = element.GetString()?.Trim() ?? string.Empty;
        return value.Length is > 0 && value.Length <= maximumLength &&
               !value.Contains('\r') && !value.Contains('\n') && !value.Contains('\0');
    }

    private static bool TryHash(string value, out byte[] hash)
    {
        hash = [];
        try
        {
            if (value.Length != 64) return false;
            hash = Convert.FromHexString(value);
            return hash.Length == 32;
        }
        catch (FormatException)
        {
            return false;
        }
    }

    private static bool SameLocation(
        ProtectedProjectAssetBlobLocation left,
        ProtectedProjectAssetBlobLocation right) =>
        string.Equals(left.Container, right.Container, StringComparison.Ordinal) &&
        string.Equals(left.ObjectName, right.ObjectName, StringComparison.Ordinal);

    private static bool IsSafeVersionId(string? value) =>
        value is { Length: >= 1 and <= 200 } &&
        !value.Any(char.IsControl) &&
        !value.Contains('&') && !value.Contains('#') && !value.Contains('?');

    private static bool OriginEquals(string? left, string? right) =>
        left is not null && right is not null &&
        string.Equals(left.Trim(), right.Trim(), StringComparison.OrdinalIgnoreCase);

    private static ProjectAssetDefenderEventGridResult Rejected(string code) =>
        new(ProjectAssetDefenderEventGridOutcome.Rejected, code);

    private static ProjectAssetDefenderEventGridResult Retry(string code) =>
        new(ProjectAssetDefenderEventGridOutcome.Retry, code);
}
