using System.Security.Cryptography;
using System.Text;
using System.Globalization;
using FundingPlatform.Core.SourceDocuments;

namespace FundingPlatform.Application.SourceDocuments;

public sealed class SourceDocumentExtractionAdminService(
    ISourceDocumentExtractionRepository repository,
    SourceDocumentExtractionPolicy policy,
    TimeProvider timeProvider)
{
    public async Task<SourceDocumentExtractionResult> StartAsync(
        Guid adminUserId,
        Guid sourceDocumentId,
        byte[] expectedRowVersion,
        string? idempotencyKey,
        string correlationId,
        CancellationToken cancellationToken)
    {
        var normalizedKey = idempotencyKey?.Trim();
        if (adminUserId == Guid.Empty || sourceDocumentId == Guid.Empty ||
            expectedRowVersion is not { Length: 8 } ||
            string.IsNullOrWhiteSpace(correlationId) || correlationId.Length > 100 ||
            string.IsNullOrWhiteSpace(normalizedKey) ||
            normalizedKey.Length is < 8 or > 128 ||
            normalizedKey.Contains('\r') || normalizedKey.Contains('\n'))
        {
            return new SourceDocumentExtractionResult(
                SourceDocumentExtractionOutcome.Invalid,
                "invalid-extraction-request",
                sourceDocumentId,
                Errors: new Dictionary<string, string[]>
                {
                    ["request"] = ["If-Match e Idempotency-Key válidos son obligatorios."]
                });
        }

        var keyHash = SHA256.HashData(Encoding.UTF8.GetBytes(normalizedKey));
        var requestHash = SHA256.HashData(Encoding.UTF8.GetBytes(string.Join('\n',
            "StartSourceDocumentExtraction/v1",
            sourceDocumentId.ToString("D"),
            Convert.ToHexString(expectedRowVersion),
            policy.ParserCode,
            policy.ParserVersion,
            Convert.ToHexString(policy.ParserSettingsHash),
            policy.MaximumCharacters.ToString(System.Globalization.CultureInfo.InvariantCulture),
            policy.MaximumPages.ToString(System.Globalization.CultureInfo.InvariantCulture),
            policy.MaximumUtf8Bytes.ToString(System.Globalization.CultureInfo.InvariantCulture),
            policy.MaximumStackDepth.ToString(System.Globalization.CultureInfo.InvariantCulture),
            policy.MaximumBytes.ToString(System.Globalization.CultureInfo.InvariantCulture))));
        try
        {
            var mutation = await repository.StartAsync(
                adminUserId,
                sourceDocumentId,
                expectedRowVersion,
                keyHash,
                requestHash,
                correlationId,
                policy,
                timeProvider.GetUtcNow(),
                cancellationToken);
            return new SourceDocumentExtractionResult(
                Map(mutation.Code, mutation.Succeeded),
                mutation.Code,
                mutation.SourceDocumentId,
                mutation.JobId,
                mutation.Status,
                mutation.AttemptCount,
                mutation.MaxAttempts,
                mutation.RowVersion,
                mutation.WasReplay);
        }
        catch (SourceDocumentExtractionDataException)
        {
            return new SourceDocumentExtractionResult(
                SourceDocumentExtractionOutcome.Unavailable,
                "extraction-data-unavailable",
                sourceDocumentId);
        }
    }

    public async Task<SourceDocumentExtractionReadResult> GetLatestAsync(
        Guid adminUserId,
        Guid sourceDocumentId,
        CancellationToken cancellationToken)
    {
        if (adminUserId == Guid.Empty || sourceDocumentId == Guid.Empty)
            return new(SourceDocumentExtractionOutcome.Invalid, "invalid-extraction-request");
        try
        {
            var value = await repository.GetLatestAsync(
                adminUserId, sourceDocumentId, cancellationToken);
            if (value is null)
                return new(SourceDocumentExtractionOutcome.NotFound, "source-document-not-found");
            return new(
                SourceDocumentExtractionOutcome.Success,
                "retrieved",
                value with
                {
                    TextPreview = value.IsContentRedacted || value.IsSecurityRevoked
                        ? null
                        : SanitizeReviewText(value.TextPreview, 4_000),
                    LastErrorCode = value.IsSecurityRevoked
                        ? "security-revoked"
                        : value.IsContentRedacted
                            ? "content-retention-redacted"
                            : value.LastErrorCode
                });
        }
        catch (SourceDocumentExtractionDataException)
        {
            return new(SourceDocumentExtractionOutcome.Unavailable, "extraction-data-unavailable");
        }
    }

    public async Task<SourceDocumentExtractionEvidenceReadResult> ListEvidenceAsync(
        Guid adminUserId,
        Guid jobId,
        int page,
        int pageSize,
        CancellationToken cancellationToken)
    {
        if (adminUserId == Guid.Empty || jobId == Guid.Empty || page < 1 ||
            pageSize is < 1 or > 100)
            return new(SourceDocumentExtractionOutcome.Invalid, "invalid-evidence-page");
        try
        {
            var value = await repository.ListEvidenceAsync(
                adminUserId, jobId, page, pageSize, cancellationToken);
            return new(
                SourceDocumentExtractionOutcome.Success,
                "retrieved",
                value with
                {
                    Items = value.Items.Select(item => item with
                    {
                        Excerpt = SanitizeReviewText(item.Excerpt, 2_000) ?? string.Empty
                    }).ToArray()
                });
        }
        catch (SourceDocumentExtractionDataException)
        {
            return new(SourceDocumentExtractionOutcome.Unavailable, "extraction-data-unavailable");
        }
    }

    private static string? SanitizeReviewText(string? value, int maximumLength)
    {
        if (value is null) return null;
        var result = new StringBuilder(Math.Min(value.Length, maximumLength));
        foreach (var rune in value.Normalize(NormalizationForm.FormKC).EnumerateRunes())
        {
            if (result.Length >= maximumLength) break;
            if (rune.Value is '\n' or '\t')
            {
                result.Append(rune.ToString());
                continue;
            }
            var category = Rune.GetUnicodeCategory(rune);
            if (category is UnicodeCategory.Control or UnicodeCategory.Format or
                UnicodeCategory.Surrogate or UnicodeCategory.PrivateUse or
                UnicodeCategory.OtherNotAssigned) continue;
            if (result.Length + rune.Utf16SequenceLength > maximumLength) break;
            result.Append(rune.ToString());
        }
        return result.ToString();
    }

    private static SourceDocumentExtractionOutcome Map(string code, bool succeeded)
    {
        if (succeeded) return SourceDocumentExtractionOutcome.Accepted;
        return code switch
        {
            "forbidden" => SourceDocumentExtractionOutcome.Forbidden,
            "not-found" => SourceDocumentExtractionOutcome.NotFound,
            "etag-conflict" => SourceDocumentExtractionOutcome.PreconditionFailed,
            "document-too-large-for-extraction" or "document-too-large" or
                "source-disabled" or "compliance-required" or "license-required" =>
                SourceDocumentExtractionOutcome.Invalid,
            "idempotency-conflict" or "invalid-transition" or "document-not-trusted" or
                "unsafe-document" or "already-started" or "retention-expired" =>
                SourceDocumentExtractionOutcome.Conflict,
            _ => SourceDocumentExtractionOutcome.Unavailable
        };
    }
}

public sealed class SourceDocumentExtractionWatchdogService(
    ISourceDocumentExtractionRepository repository,
    TimeProvider timeProvider)
{
    public async Task<int> RequeueStrandedAsync(
        int batchSize,
        CancellationToken cancellationToken)
    {
        if (batchSize is < 1 or > 100) throw new ArgumentOutOfRangeException(nameof(batchSize));
        var requeued = await repository.RequeueStrandedAsync(
            timeProvider.GetUtcNow(), batchSize, cancellationToken);
        return requeued.Count;
    }
}

public sealed class SourceDocumentExtractionProcessingService(
    ISourceDocumentExtractionRepository repository,
    ISourceDocumentExtractionBlobReader blobReader,
    ISourceDocumentTextExtractor extractor,
    SourceDocumentExtractionPolicy policy,
    TimeProvider timeProvider)
{
    public async Task<string> ProcessAsync(
        Guid jobId,
        CancellationToken cancellationToken)
    {
        if (jobId == Guid.Empty) return "invalid-job-id";
        var leaseId = Guid.NewGuid();
        var claim = await repository.ClaimAsync(
            jobId,
            leaseId,
            timeProvider.GetUtcNow(),
            policy.LeaseDuration,
            cancellationToken);
        if (claim is null) return "not-claimable";

        var settingsHash = SourceDocumentExtractionSettings.ComputeHash(
            claim.ParserCode,
            claim.ParserVersion,
            claim.MaximumCharacters,
            claim.MaximumPages,
            claim.MaximumUtf8Bytes,
            claim.MaximumStackDepth,
            claim.MaximumBytes);
        if (!string.Equals(claim.ParserCode, policy.ParserCode, StringComparison.Ordinal) ||
            !string.Equals(claim.ParserVersion, policy.ParserVersion, StringComparison.Ordinal) ||
            claim.ParserSettingsHash is not { Length: 32 } ||
            !CryptographicOperations.FixedTimeEquals(claim.ParserSettingsHash, settingsHash))
        {
            await repository.FailAsync(
                claim.JobId,
                claim.LeaseId,
                "parser-settings-mismatch",
                "El worker no coincide con la configuración durable del parser.",
                false,
                timeProvider.GetUtcNow(),
                cancellationToken);
            return "parser-settings-mismatch";
        }

        var effectivePolicy = policy with
        {
            MaximumCharacters = claim.MaximumCharacters,
            MaximumPages = claim.MaximumPages,
            MaximumUtf8Bytes = claim.MaximumUtf8Bytes,
            MaximumStackDepth = claim.MaximumStackDepth,
            MaximumBytes = claim.MaximumBytes,
            ParserSettingsHash = claim.ParserSettingsHash
        };

        await using var heartbeat = new ExtractionLeaseHeartbeat(
            repository, claim.JobId, leaseId, policy.LeaseDuration, timeProvider);
        using var timeout = new CancellationTokenSource(policy.Timeout);
        using var operation = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken, timeout.Token, heartbeat.LeaseLostToken);
        try
        {
            var location = new ProtectedBlobLocation(
                claim.TrustedLocation.Container,
                claim.TrustedLocation.ObjectName);
            await using var source = await blobReader.OpenTrustedReadAsync(
                location, claim.TrustedETag, operation.Token);
            if (source.ContentLength != claim.ContentLength ||
                source.ContentLength > claim.MaximumBytes)
            {
                await FailAsync(claim, "trusted-content-conflict", false, cancellationToken);
                return "trusted-content-conflict";
            }

            var extraction = await extractor.ExtractPdfAsync(
                source, effectivePolicy, operation.Token);
            if (!CryptographicOperations.FixedTimeEquals(
                    extraction.SourceContentHash, claim.ContentHash))
            {
                await FailAsync(claim, "trusted-content-hash-mismatch", false, cancellationToken);
                return "trusted-content-hash-mismatch";
            }

            await RecordBoundedEvidenceAsync(claim, extraction.Text, operation.Token);

            await repository.CompleteAsync(
                claim.JobId,
                leaseId,
                extraction.Text,
                extraction.ExtractedTextHash,
                extraction.PageCount,
                extraction.CharacterCount,
                extraction.CompletedWithErrors,
                timeProvider.GetUtcNow(),
                cancellationToken);
            return extraction.CharacterCount == 0
                ? "no-extractable-text"
                : extraction.WasTruncated ? "completed-with-limits" : "completed";
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (OperationCanceledException) when (heartbeat.LeaseLostToken.IsCancellationRequested)
        {
            throw new SourceDocumentExtractionLeaseLostException(claim.JobId);
        }
        catch (OperationCanceledException) when (timeout.IsCancellationRequested)
        {
            await FailAsync(claim, "extraction-timeout", true, CancellationToken.None);
            return "extraction-timeout";
        }
        catch (SourceDocumentStorageException)
        {
            await FailAsync(claim, "trusted-storage-unavailable", true, CancellationToken.None);
            return "trusted-storage-unavailable";
        }
        catch (Exception exception) when (exception is InvalidDataException or
                                          InvalidOperationException or FormatException or
                                          IndexOutOfRangeException or ArgumentException)
        {
            await FailAsync(claim, "pdf-extraction-rejected", false, CancellationToken.None);
            return "pdf-extraction-rejected";
        }
        finally
        {
            await heartbeat.StopAsync();
        }
    }

    private Task FailAsync(
        SourceDocumentExtractionClaim claim,
        string code,
        bool retryable,
        CancellationToken cancellationToken) => repository.FailAsync(
            claim.JobId,
            claim.LeaseId,
            code,
            retryable
                ? "La extracción no pudo completarse y se reintentará."
                : "El documento no pudo extraerse de forma segura.",
            retryable,
            timeProvider.GetUtcNow(),
            cancellationToken);

    private async Task RecordBoundedEvidenceAsync(
        SourceDocumentExtractionClaim claim,
        string text,
        CancellationToken cancellationToken)
    {
        const int excerptLength = 2_000;
        const int maximumEvidence = 25;
        for (var ordinal = 1; ordinal <= maximumEvidence; ordinal++)
        {
            var start = (ordinal - 1) * excerptLength;
            if (start >= text.Length) break;
            var length = Math.Min(excerptLength, text.Length - start);
            var excerpt = text.Substring(start, length);
            await repository.RecordEvidenceAsync(
                claim.JobId,
                claim.LeaseId,
                checked((short)ordinal),
                pageNumber: null,
                start,
                excerpt,
                timeProvider.GetUtcNow(),
                cancellationToken);
        }
    }
}

internal sealed class ExtractionLeaseHeartbeat : IAsyncDisposable
{
    private readonly ISourceDocumentExtractionRepository repository;
    private readonly Guid jobId;
    private readonly Guid leaseId;
    private readonly TimeSpan leaseDuration;
    private readonly TimeProvider timeProvider;
    private readonly CancellationTokenSource stop = new();
    private readonly CancellationTokenSource leaseLost = new();
    private readonly Task loop;

    public ExtractionLeaseHeartbeat(
        ISourceDocumentExtractionRepository repository,
        Guid jobId,
        Guid leaseId,
        TimeSpan leaseDuration,
        TimeProvider timeProvider)
    {
        this.repository = repository;
        this.jobId = jobId;
        this.leaseId = leaseId;
        this.leaseDuration = leaseDuration;
        this.timeProvider = timeProvider;
        loop = RunAsync();
    }

    public CancellationToken LeaseLostToken => leaseLost.Token;

    public async Task StopAsync()
    {
        if (!stop.IsCancellationRequested) stop.Cancel();
        try { await loop; }
        catch (OperationCanceledException) when (stop.IsCancellationRequested) { }
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync();
        stop.Dispose();
        leaseLost.Dispose();
    }

    private async Task RunAsync()
    {
        var interval = TimeSpan.FromSeconds(Math.Max(10, leaseDuration.TotalSeconds / 3));
        try
        {
            while (!stop.IsCancellationRequested)
            {
                await Task.Delay(interval, timeProvider, stop.Token);
                var renewed = await repository.RenewLeaseAsync(
                    jobId, leaseId, timeProvider.GetUtcNow(), leaseDuration, stop.Token);
                if (renewed) continue;
                leaseLost.Cancel();
                return;
            }
        }
        catch (OperationCanceledException) when (stop.IsCancellationRequested)
        {
            // Normal shutdown.
        }
        catch (Exception)
        {
            // A transient SQL failure means ownership can no longer be proven.
            // Cancel processing and let Queue Storage redeliver after the lease expires.
            leaseLost.Cancel();
        }
    }
}
