using System.Security.Cryptography;
using System.Text.Json;
using FundingPlatform.Core.SourceDocuments;

namespace FundingPlatform.Application.SourceDocuments;

public sealed class DefenderEventGridService(
    IDefenderScanReceiptRepository receipts,
    ISourceDocumentRepository documents,
    ISourceDocumentBlobStore blobStore,
    DefenderEventGridPolicy policy,
    TimeProvider timeProvider)
{
    public async Task<DefenderEventGridResult> HandleAsync(
        ReadOnlyMemory<byte> payload,
        string? eventTypeHeader,
        string? subscriptionName,
        EventGridCaller caller,
        CancellationToken cancellationToken)
    {
        if (payload.Length is < 2 or > 65_536 ||
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
                if (!OriginEquals(eventType, "Microsoft.EventGrid.SubscriptionValidationEvent") ||
                    !item.TryGetProperty("data", out var validationData) ||
                    validationData.ValueKind != JsonValueKind.Object ||
                    !TryString(validationData, "validationCode", 128, out var validationCode))
                {
                    return Rejected("subscription-validation-rejected");
                }

                return new DefenderEventGridResult(
                    DefenderEventGridOutcome.ValidationHandshake,
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

    private async Task<DefenderEventGridResult> HandleScanAsync(
        JsonElement item,
        ReadOnlyMemory<byte> payload,
        EventGridCaller caller,
        CancellationToken cancellationToken)
    {
        if (!TryString(item, "id", 200, out var eventId) ||
            !TryString(item, "subject", 2048, out var subject) ||
            !TryString(item, "dataVersion", 20, out var dataVersion) ||
            !string.Equals(dataVersion, "1.0", StringComparison.Ordinal) ||
            !item.TryGetProperty("eventTime", out var eventTimeElement) ||
            !eventTimeElement.TryGetDateTimeOffset(out var eventTime) ||
            eventTime.Offset != TimeSpan.Zero ||
            eventTime > timeProvider.GetUtcNow().Add(policy.MaximumFutureClockSkew) ||
            !item.TryGetProperty("data", out var data) ||
            data.ValueKind != JsonValueKind.Object ||
            !TryString(data, "blobUri", 2048, out var blobUriText) ||
            !TryString(data, "eTag", 100, out var blobETag) ||
            !TryString(data, "scanResultType", 100, out var scanResult) ||
            !data.TryGetProperty("scanFinishedTimeUtc", out var finishedElement) ||
            !finishedElement.TryGetDateTimeOffset(out var finishedAt) ||
            finishedAt.Offset != TimeSpan.Zero ||
            finishedAt > timeProvider.GetUtcNow().Add(policy.MaximumFutureClockSkew) ||
            !BlobETagNormalizer.TryNormalize(blobETag, out var normalizedEventETag) ||
            !TryLocation(blobUriText, out var quarantineLocation) ||
            !SubjectMatches(subject, quarantineLocation!))
        {
            return Rejected("scan-event-invalid");
        }

        var (status, resultCode) = scanResult.ToLowerInvariant() switch
        {
            "no threats found" => (SourceDocumentScanStatus.Clean, "defender-clean"),
            "malicious" => (SourceDocumentScanStatus.Malicious, "defender-malicious"),
            "scan timed out" => (SourceDocumentScanStatus.TimedOut, "defender-timeout"),
            "error" or "not scanned" => (SourceDocumentScanStatus.Failed, "defender-failed"),
            _ => ((SourceDocumentScanStatus?)null, "defender-result-unsupported")
        };
        if (status is null) return Rejected(resultCode);

        byte[]? reportedHash = null;
        if (data.TryGetProperty("scanResultDetails", out var details) &&
            details.ValueKind == JsonValueKind.Object &&
            TryString(details, "sha256", 64, out var hashText) &&
            TryHash(hashText, out var parsedHash))
        {
            reportedHash = parsedHash;
        }
        if (status is SourceDocumentScanStatus.Clean or SourceDocumentScanStatus.Malicious &&
            reportedHash is null)
        {
            return Rejected("scan-content-hash-required");
        }

        var payloadHash = SHA256.HashData(payload.Span);
        DefenderReceiptWork work;
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
                timeProvider.GetUtcNow(),
                cancellationToken);
        }
        catch (SourceDocumentDataException)
        {
            return Retry("scan-receipt-unavailable");
        }

        if (work.Code == "replayed-applied")
        {
            return new DefenderEventGridResult(
                DefenderEventGridOutcome.Applied,
                work.Code,
                SourceDocumentId: work.SourceDocumentId);
        }
        if (work.Code is "replayed-ignored" or "replayed-rejected" || !work.Succeeded)
        {
            // SQL failures throw above. A returned non-success code is a durable policy/content
            // rejection and must not be converted into an endless Event Grid retry.
            return Rejected(work.Code);
        }
        if (work.Code is not ("accepted" or "replayed-accepted"))
        {
            return Rejected("scan-receipt-state-invalid");
        }

        if (work.ReceiptId is null || work.SourceDocumentId is null ||
            work.ScanProvider != SourceDocumentScanProvider.MicrosoftDefender ||
            work.QuarantineLocation is null || work.QuarantineETag is null ||
            work.ContentHash is not { Length: 32 } || work.ContentLength is null ||
            !string.Equals(work.MimeType, "application/pdf", StringComparison.OrdinalIgnoreCase))
        {
            return Retry("scan-receipt-materialization-invalid");
        }

        try
        {
            if (!SameLocation(work.QuarantineLocation, quarantineLocation!) ||
                !BlobETagNormalizer.TryNormalize(
                    work.QuarantineETag, out var normalizedStoredETag) ||
                !string.Equals(normalizedStoredETag, normalizedEventETag, StringComparison.Ordinal) ||
                (reportedHash is not null && !CryptographicOperations.FixedTimeEquals(
                    work.ContentHash, reportedHash)) ||
                work.ContentLength is < 1 || work.ContentLength > policy.MaximumBlobBytes)
            {
                return await FinalizeAsync(
                    work, payloadHash, applied: false, "scan-content-conflict",
                    Rejected("scan-content-conflict"));
            }

            await using (var blob = await blobStore.OpenReadAsync(
                             work.QuarantineLocation,
                             work.QuarantineETag,
                             cancellationToken))
            {
                var actualHash = await HashBoundedAsync(
                    blob, work.ContentLength.Value, policy.MaximumBlobBytes, cancellationToken);
                if (!CryptographicOperations.FixedTimeEquals(actualHash, work.ContentHash) ||
                    (reportedHash is not null && !CryptographicOperations.FixedTimeEquals(
                        actualHash, reportedHash)))
                {
                    return await FinalizeAsync(
                        work, payloadHash, applied: false, "scan-content-hash-mismatch",
                        Rejected("scan-content-hash-mismatch"));
                }
            }

            ProtectedBlobLocation? trustedLocation = null;
            SourceBlobReceipt? trustedReceipt = null;
            if (status == SourceDocumentScanStatus.Clean)
            {
                trustedLocation = new ProtectedBlobLocation(
                    policy.TrustedContainer, work.QuarantineLocation.ObjectName);
                trustedReceipt = await blobStore.EnsureCopyAsync(
                    work.QuarantineLocation,
                    work.QuarantineETag,
                    trustedLocation,
                    work.ContentLength.Value,
                    work.ContentHash,
                    cancellationToken);
            }

            var mutation = await documents.ApplyScanResultAsync(
                work.SourceDocumentId.Value,
                SourceDocumentScanProvider.MicrosoftDefender,
                eventId,
                payloadHash,
                work.QuarantineETag,
                reportedHash,
                status.Value,
                resultCode,
                trustedLocation,
                trustedReceipt,
                finishedAt,
                cancellationToken);

            // A Clean delivery copies before the SQL compare-and-set. If a
            // concurrent malicious result wins that transition, remove the
            // unreferenced trusted copy with its exact ETag before acknowledging
            // this event. Replays repeat the idempotent cleanup on storage failure.
            if (status == SourceDocumentScanStatus.Clean &&
                trustedLocation is not null && trustedReceipt is not null &&
                mutation.Code != "scan-result-applied" &&
                mutation.ScanStatus != SourceDocumentScanStatus.Clean)
            {
                if (!BlobETagNormalizer.TryNormalize(
                        trustedReceipt.ETag, out var copiedTrustedETag))
                {
                    return Retry("trusted-copy-materialization-invalid");
                }
                await blobStore.DeleteIfMatchAsync(
                    trustedLocation, copiedTrustedETag, cancellationToken);
                var orphanedCopy = await blobStore.GetVerifiedReceiptAsync(
                    trustedLocation,
                    work.ContentLength.Value,
                    work.ContentHash,
                    cancellationToken);
                if (orphanedCopy is not null)
                {
                    return Retry("trusted-copy-cleanup-incomplete");
                }
            }

            if (!mutation.Succeeded)
            {
                // Stored-procedure business outcomes are permanent for this immutable
                // Event Grid event. SQL/data transport failures throw and are retried.
                return await FinalizeAsync(
                    work,
                    payloadHash,
                    applied: false,
                    NormalizeMutationCode(mutation.Code),
                    Rejected(NormalizeMutationCode(mutation.Code)));
            }

            if (mutation.Code == "scan-result-superseded")
            {
                if (mutation.RevokedTrustedLocation is null ||
                    !BlobETagNormalizer.TryNormalize(
                        mutation.RevokedTrustedETag, out var revokedETag))
                {
                    return Retry("trusted-revocation-materialization-invalid");
                }

                await blobStore.DeleteIfMatchAsync(
                    mutation.RevokedTrustedLocation,
                    revokedETag,
                    cancellationToken);
                var remaining = await blobStore.GetVerifiedReceiptAsync(
                    mutation.RevokedTrustedLocation,
                    work.ContentLength.Value,
                    work.ContentHash,
                    cancellationToken);
                if (remaining is not null)
                {
                    return Retry("trusted-revocation-incomplete");
                }
            }

            var mutationApplied = mutation.Code is
                "scan-result-applied" or "scan-result-superseded";
            var terminalCode = NormalizeMutationCode(mutation.Code);
            var terminalResult = mutation.Code == "content-retention-ignored"
                ? Rejected(terminalCode)
                : new DefenderEventGridResult(
                    DefenderEventGridOutcome.Applied,
                    terminalCode,
                    SourceDocumentId: work.SourceDocumentId);
            return await FinalizeAsync(
                work,
                payloadHash,
                mutationApplied,
                terminalCode,
                terminalResult);
        }
        catch (SourceDocumentStorageException)
        {
            return Retry("scan-storage-unavailable");
        }
        catch (SourceDocumentDataException)
        {
            return Retry("scan-data-unavailable");
        }
        catch (InvalidDataException)
        {
            return await FinalizeAsync(
                work, payloadHash, applied: false, "scan-content-conflict",
                Rejected("scan-content-conflict"));
        }
    }

    private async Task<DefenderEventGridResult> FinalizeAsync(
        DefenderReceiptWork work,
        byte[] payloadHash,
        bool applied,
        string outcomeCode,
        DefenderEventGridResult terminalResult)
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
        catch (SourceDocumentDataException)
        {
            // Apply and copy are idempotent. Returning 503 keeps the accepted receipt
            // replayable until its durable terminal state can be recorded.
            return Retry("scan-finalization-unavailable");
        }
    }

    private static string NormalizeMutationCode(string? code) => code switch
    {
        "scan-result-applied" or "scan-result-superseded" or
            "scan-result-ignored" or "duplicate-scan-result" or
            "content-retention-ignored" or
            "stale-scan-result" or "terminal-scan-result-conflict" or
            "invalid-transition" or "event-conflict" or "provider-mismatch" or
            "blob-etag-mismatch" or "content-hash-mismatch" or
            "invalid-event-time" or "invalid-trusted-location" or
            "not-found" => code,
        _ => "scan-result-rejected"
    };

    private bool SubjectMatches(string subject, ProtectedBlobLocation location)
    {
        try
        {
            var account = policy.BlobServiceUri.Host.Split('.', 2)[0];
            var decoded = Uri.UnescapeDataString(subject.TrimStart('/'));
            var prefix = $"storageAccounts/{account}/containers/{location.Container}/blobs/";
            return decoded.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) &&
                   string.Equals(decoded[prefix.Length..], location.ObjectName,
                       StringComparison.Ordinal);
        }
        catch (UriFormatException)
        {
            return false;
        }
    }

    private bool TryLocation(string text, out ProtectedBlobLocation? location)
    {
        location = null;
        if (!Uri.TryCreate(text, UriKind.Absolute, out var uri) ||
            uri.Scheme != Uri.UriSchemeHttps || uri.Port != 443 ||
            !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment) ||
            !string.IsNullOrEmpty(uri.UserInfo) ||
            !string.Equals(uri.Host, policy.BlobServiceUri.Host, StringComparison.OrdinalIgnoreCase))
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
                objectName.Contains('\r') || objectName.Contains('\n'))
            {
                return false;
            }
            location = new ProtectedBlobLocation(container, objectName);
            return true;
        }
        catch (UriFormatException)
        {
            return false;
        }
    }

    private static async Task<byte[]> HashBoundedAsync(
        SourceBlobRead blob,
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
        if (total != expectedLength) throw new InvalidDataException("Blob length conflict.");
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

    private static bool SameLocation(ProtectedBlobLocation left, ProtectedBlobLocation right) =>
        string.Equals(left.Container, right.Container, StringComparison.Ordinal) &&
        string.Equals(left.ObjectName, right.ObjectName, StringComparison.Ordinal);

    private static bool OriginEquals(string? left, string? right) =>
        left is not null && right is not null &&
        string.Equals(left.Trim(), right.Trim(), StringComparison.OrdinalIgnoreCase);

    private static DefenderEventGridResult Rejected(string code) =>
        new(DefenderEventGridOutcome.Rejected, code);

    private static DefenderEventGridResult Retry(string code) =>
        new(DefenderEventGridOutcome.Retry, code);
}
