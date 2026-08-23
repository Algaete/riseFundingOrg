using System.Data;
using System.Security.Cryptography;
using System.Text;
using Dapper;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Core.SourceDocuments;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.SourceDocuments;

public sealed class SqlSourceDocumentExtractionRepository(
    ISqlConnectionFactory connectionFactory) : ISourceDocumentExtractionRepository
{
    public async Task<SourceDocumentExtractionStartMutation> StartAsync(
        Guid adminUserId,
        Guid sourceDocumentId,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        string correlationId,
        SourceDocumentExtractionPolicy policy,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        var row = await QuerySingleAsync<StartRow>(
            "dbo.FundingPlatform_usp_SourceDocumentExtraction_AdminStart",
            "start source-document extraction",
            new
            {
                AdminUserPublicId = adminUserId,
                SourceDocumentPublicId = sourceDocumentId,
                ExpectedRowVersion = expectedRowVersion,
                IdempotencyKeyHash = idempotencyKeyHash,
                RequestHash = requestHash,
                CorrelationId = correlationId,
                policy.ParserCode,
                policy.ParserVersion,
                policy.ParserSettingsHash,
                policy.MaximumCharacters,
                policy.MaximumPages,
                policy.MaximumUtf8Bytes,
                policy.MaximumStackDepth,
                policy.MaximumBytes,
                NowUtc = nowUtc.UtcDateTime
            }, cancellationToken);
        return new SourceDocumentExtractionStartMutation(
            row.Succeeded,
            row.Code,
            sourceDocumentId,
            row.JobPublicId,
            EnumValue<SourceDocumentExtractionStatus>(row.ExtractionStatus),
            row.AttemptCount,
            row.MaxAttempts,
            row.DocumentRowVersion,
            row.WasReplay);
    }

    public async Task<IReadOnlyList<ScheduledSourceDocumentExtraction>> RequeueStrandedAsync(
        DateTimeOffset nowUtc,
        int batchSize,
        CancellationToken cancellationToken)
    {
        var rows = await QueryAsync<ScheduleRow>(
            "dbo.FundingPlatform_usp_SourceDocumentExtraction_RequeueStranded",
            "requeue stranded source-document extractions",
            new { NowUtc = nowUtc.UtcDateTime, BatchSize = batchSize },
            cancellationToken);
        return rows.Select(row => new ScheduledSourceDocumentExtraction(
            row.JobPublicId, row.SourceDocumentPublicId)).ToArray();
    }

    public async Task<SourceDocumentExtractionClaim?> ClaimAsync(
        Guid jobId,
        Guid leaseId,
        DateTimeOffset nowUtc,
        TimeSpan leaseDuration,
        CancellationToken cancellationToken)
    {
        var row = await QuerySingleAsync<ClaimRow>(
            "dbo.FundingPlatform_usp_SourceDocumentExtraction_Claim",
            "claim source-document extraction",
            new
            {
                JobPublicId = jobId,
                LeaseId = leaseId,
                LeaseSeconds = checked((int)leaseDuration.TotalSeconds),
                NowUtc = nowUtc.UtcDateTime
            }, cancellationToken);
        if (!row.Succeeded) return null;
        if (row.JobPublicId is null || row.SourceDocumentPublicId is null ||
            string.IsNullOrWhiteSpace(row.TrustedBlobContainer) ||
            string.IsNullOrWhiteSpace(row.TrustedBlobObjectName) ||
            string.IsNullOrWhiteSpace(row.TrustedBlobETag) ||
            row.ContentHash is not { Length: 32 } || row.ContentLength is null ||
            row.AttemptCount is null || row.MaxAttempts is null ||
            !string.Equals(row.MimeType, "application/pdf", StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(row.ParserCode, "fundingplatform-pdf-text", StringComparison.Ordinal) ||
            string.IsNullOrWhiteSpace(row.ParserVersion) ||
            row.ParserSettingsHash is not { Length: 32 } ||
            row.MaximumCharacters is null || row.MaximumPages is null ||
            row.MaximumUtf8Bytes is null || row.MaximumStackDepth is null ||
            row.MaximumBytes is null)
        {
            throw new SourceDocumentExtractionDataException(
                "materialize source-document extraction claim", -1);
        }

        return new SourceDocumentExtractionClaim(
            row.JobPublicId.Value,
            row.SourceDocumentPublicId.Value,
            leaseId,
            new ProtectedSourceDocumentLocation(
                row.TrustedBlobContainer, row.TrustedBlobObjectName),
            row.TrustedBlobETag,
            row.ContentHash,
            row.ContentLength.Value,
            row.AttemptCount.Value,
            row.MaxAttempts.Value,
            row.ParserCode!,
            row.ParserVersion!,
            row.ParserSettingsHash,
            row.MaximumCharacters.Value,
            row.MaximumPages.Value,
            row.MaximumUtf8Bytes.Value,
            row.MaximumStackDepth.Value,
            row.MaximumBytes.Value);
    }

    public async Task<bool> RenewLeaseAsync(
        Guid jobId,
        Guid leaseId,
        DateTimeOffset nowUtc,
        TimeSpan leaseDuration,
        CancellationToken cancellationToken)
    {
        var row = await QuerySingleAsync<MutationRow>(
            "dbo.FundingPlatform_usp_SourceDocumentExtraction_RenewLease",
            "renew source-document extraction lease",
            new
            {
                JobPublicId = jobId,
                LeaseId = leaseId,
                LeaseSeconds = checked((int)leaseDuration.TotalSeconds),
                NowUtc = nowUtc.UtcDateTime
            }, cancellationToken);
        return row.Succeeded;
    }

    public async Task RecordEvidenceAsync(
        Guid jobId,
        Guid leaseId,
        short ordinal,
        int? pageNumber,
        int startOffset,
        string excerpt,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(excerpt));
        var row = await QuerySingleAsync<MutationRow>(
            "dbo.FundingPlatform_usp_SourceDocumentExtraction_RecordEvidence",
            "record source-document extraction evidence",
            new
            {
                JobPublicId = jobId,
                LeaseId = leaseId,
                Ordinal = ordinal,
                PageNumber = pageNumber,
                StartOffset = startOffset,
                CharacterLength = excerpt.Length,
                Excerpt = excerpt,
                EvidenceHash = hash,
                NowUtc = nowUtc.UtcDateTime
            }, cancellationToken);
        EnsureMutation(row, jobId);
    }

    public async Task CompleteAsync(
        Guid jobId,
        Guid leaseId,
        string extractedText,
        byte[] extractedTextHash,
        int pageCount,
        int characterCount,
        bool wasTruncated,
        DateTimeOffset completedAtUtc,
        CancellationToken cancellationToken)
    {
        if (Encoding.UTF8.GetByteCount(extractedText) > 2_097_152 ||
            extractedTextHash is not { Length: 32 } || pageCount < 1 ||
            characterCount != extractedText.Length)
            throw new ArgumentException("Extracted source-document text is outside durable limits.");
        var row = await QuerySingleAsync<MutationRow>(
            "dbo.FundingPlatform_usp_SourceDocumentExtraction_Complete",
            "complete source-document extraction",
            new
            {
                JobPublicId = jobId,
                LeaseId = leaseId,
                ExtractedText = extractedText,
                ExtractedTextHash = extractedTextHash,
                PageCount = pageCount,
                CharacterCount = characterCount,
                CompletedWithErrors = wasTruncated,
                CompletedAtUtc = completedAtUtc.UtcDateTime
            }, cancellationToken);
        EnsureMutation(row, jobId);
    }

    public async Task FailAsync(
        Guid jobId,
        Guid leaseId,
        string errorCode,
        string safeMessage,
        bool retryable,
        DateTimeOffset failedAtUtc,
        CancellationToken cancellationToken)
    {
        var row = await QuerySingleAsync<MutationRow>(
            "dbo.FundingPlatform_usp_SourceDocumentExtraction_Fail",
            "fail source-document extraction",
            new
            {
                JobPublicId = jobId,
                LeaseId = leaseId,
                ErrorCode = errorCode,
                SanitizedMessage = safeMessage,
                IsRetryable = retryable,
                FailedAtUtc = failedAtUtc.UtcDateTime
            }, cancellationToken);
        EnsureMutation(row, jobId);
    }

    public async Task<SourceDocumentExtractionAdminView?> GetLatestAsync(
        Guid adminUserId,
        Guid sourceDocumentId,
        CancellationToken cancellationToken)
    {
        var row = await QuerySingleOrDefaultAsync<AdminGetRow>(
            "dbo.FundingPlatform_usp_SourceDocumentExtraction_AdminGet",
            "get source-document extraction",
            new
            {
                AdminUserPublicId = adminUserId,
                SourceDocumentPublicId = sourceDocumentId
            }, cancellationToken);
        if (row is null || row.SourceDocumentPublicId == Guid.Empty ||
            row.DocumentRowVersion is not { Length: 8 }) return null;
        return new SourceDocumentExtractionAdminView(
            row.SourceDocumentPublicId,
            row.JobPublicId,
            row.ExtractionStatus.HasValue
                ? (SourceDocumentExtractionStatus)row.ExtractionStatus.Value
                : SourceDocumentExtractionStatus.NotStarted,
            row.ParserCode,
            row.ParserVersion,
            row.AttemptCount ?? 0,
            row.MaxAttempts ?? 0,
            row.PageCount,
            row.CharacterCount,
            row.CompletedWithErrors,
            row.EvidenceCount,
            row.ErrorCount,
            row.TextPreview,
            row.LastErrorCode,
            ToUtc(row.CreatedAtUtc),
            ToUtc(row.StartedAtUtc),
            ToUtc(row.CompletedAtUtc),
            ToUtc(row.UpdatedAtUtc),
            row.JobRowVersion,
            row.DocumentRowVersion,
            row.IsContentRedacted,
            ToUtc(row.RedactedAtUtc),
            row.IsSecurityRevoked);
    }

    public async Task<SourceDocumentExtractionEvidencePage> ListEvidenceAsync(
        Guid adminUserId,
        Guid jobId,
        int page,
        int pageSize,
        CancellationToken cancellationToken)
    {
        var rows = await QueryAsync<EvidenceRow>(
            "dbo.FundingPlatform_usp_SourceDocumentExtractionEvidence_AdminList",
            "list source-document extraction evidence",
            new
            {
                AdminUserPublicId = adminUserId,
                JobPublicId = jobId,
                Page = page,
                PageSize = pageSize
            }, cancellationToken);
        return new SourceDocumentExtractionEvidencePage(
            rows.Select(row => new SourceDocumentExtractionEvidence(
                row.EvidencePublicId,
                row.Ordinal,
                row.PageNumber,
                row.StartOffset,
                row.CharacterLength,
                row.Excerpt,
                Utc(row.CreatedAtUtc))).ToArray(),
            page,
            pageSize,
            rows.FirstOrDefault()?.TotalCount ?? 0);
    }

    private static void EnsureMutation(MutationRow row, Guid jobId)
    {
        if (row.Succeeded) return;
        if (row.Code is "lease-lost" or "not-claimable" or "stale-lease")
            throw new SourceDocumentExtractionLeaseLostException(jobId);
        throw new SourceDocumentExtractionDataException(
            "apply source-document extraction mutation", -1);
    }

    private async Task<T> QuerySingleAsync<T>(
        string procedure,
        string operation,
        object parameters,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            return await connection.QuerySingleAsync<T>(new CommandDefinition(
                procedure, parameters, commandType: CommandType.StoredProcedure,
                commandTimeout: 30, cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw new SourceDocumentExtractionDataException(
                operation, exception.Number, exception);
        }
    }

    private async Task<IReadOnlyList<T>> QueryAsync<T>(
        string procedure,
        string operation,
        object parameters,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            return (await connection.QueryAsync<T>(new CommandDefinition(
                procedure, parameters, commandType: CommandType.StoredProcedure,
                commandTimeout: 30, cancellationToken: cancellationToken))).AsList();
        }
        catch (SqlException exception)
        {
            throw new SourceDocumentExtractionDataException(
                operation, exception.Number, exception);
        }
    }

    private async Task<T?> QuerySingleOrDefaultAsync<T>(
        string procedure,
        string operation,
        object parameters,
        CancellationToken cancellationToken) where T : class
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            return await connection.QuerySingleOrDefaultAsync<T>(new CommandDefinition(
                procedure, parameters, commandType: CommandType.StoredProcedure,
                commandTimeout: 30, cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw new SourceDocumentExtractionDataException(
                operation, exception.Number, exception);
        }
    }

    private static DateTimeOffset Utc(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static DateTimeOffset? ToUtc(DateTime? value) =>
        value.HasValue ? Utc(value.Value) : null;

    private static TEnum? EnumValue<TEnum>(byte? value) where TEnum : struct, Enum =>
        value.HasValue ? (TEnum)Enum.ToObject(typeof(TEnum), value.Value) : null;

    private sealed class StartRow : MutationRow
    {
        public Guid? JobPublicId { get; init; }
        public byte? ExtractionStatus { get; init; }
        public short? AttemptCount { get; init; }
        public short? MaxAttempts { get; init; }
        public byte[]? JobRowVersion { get; init; }
        public byte[]? DocumentRowVersion { get; init; }
        public bool WasReplay { get; init; }
    }

    private sealed class ScheduleRow
    {
        public Guid JobPublicId { get; init; }
        public Guid SourceDocumentPublicId { get; init; }
    }

    private sealed class ClaimRow : MutationRow
    {
        public Guid? JobPublicId { get; init; }
        public Guid? SourceDocumentPublicId { get; init; }
        public string? TrustedBlobContainer { get; init; }
        public string? TrustedBlobObjectName { get; init; }
        public string? TrustedBlobETag { get; init; }
        public byte[]? ContentHash { get; init; }
        public long? ContentLength { get; init; }
        public string? MimeType { get; init; }
        public string? ParserCode { get; init; }
        public string? ParserVersion { get; init; }
        public byte[]? ParserSettingsHash { get; init; }
        public int? MaximumCharacters { get; init; }
        public int? MaximumPages { get; init; }
        public int? MaximumUtf8Bytes { get; init; }
        public int? MaximumStackDepth { get; init; }
        public long? MaximumBytes { get; init; }
        public short? AttemptCount { get; init; }
        public short? MaxAttempts { get; init; }
    }

    private sealed class AdminGetRow
    {
        public Guid? JobPublicId { get; init; }
        public Guid SourceDocumentPublicId { get; init; }
        public byte? ExtractionStatus { get; init; }
        public string? ParserCode { get; init; }
        public string? ParserVersion { get; init; }
        public short? AttemptCount { get; init; }
        public short? MaxAttempts { get; init; }
        public int? PageCount { get; init; }
        public int? CharacterCount { get; init; }
        public bool? CompletedWithErrors { get; init; }
        public int EvidenceCount { get; init; }
        public int ErrorCount { get; init; }
        public string? TextPreview { get; init; }
        public string? LastErrorCode { get; init; }
        public DateTime? CreatedAtUtc { get; init; }
        public DateTime? StartedAtUtc { get; init; }
        public DateTime? CompletedAtUtc { get; init; }
        public DateTime? UpdatedAtUtc { get; init; }
        public byte[]? JobRowVersion { get; init; }
        public byte[]? DocumentRowVersion { get; init; }
        public bool IsContentRedacted { get; init; }
        public DateTime? RedactedAtUtc { get; init; }
        public bool IsSecurityRevoked { get; init; }
    }

    private sealed class EvidenceRow
    {
        public Guid EvidencePublicId { get; init; }
        public short Ordinal { get; init; }
        public int? PageNumber { get; init; }
        public int StartOffset { get; init; }
        public int CharacterLength { get; init; }
        public string Excerpt { get; init; } = string.Empty;
        public DateTime CreatedAtUtc { get; init; }
        public long TotalCount { get; init; }
    }

    private class MutationRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = string.Empty;
    }
}
