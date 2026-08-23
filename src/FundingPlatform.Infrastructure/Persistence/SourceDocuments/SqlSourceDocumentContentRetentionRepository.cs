using System.Data;
using Dapper;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.SourceDocuments;

public sealed class SqlSourceDocumentContentRetentionRepository(
    ISqlConnectionFactory connectionFactory) : ISourceDocumentContentRetentionRepository
{
    public async Task<IReadOnlyList<SourceDocumentContentRetentionClaim>> ClaimAsync(
        int batchSize,
        Guid leaseId,
        TimeSpan leaseDuration,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        ValidateUtc(nowUtc);
        if (batchSize is < 1 or > 100 || leaseId == Guid.Empty ||
            leaseDuration < TimeSpan.FromSeconds(30) ||
            leaseDuration > TimeSpan.FromHours(1) ||
            leaseDuration.TotalSeconds != Math.Truncate(leaseDuration.TotalSeconds))
            throw new ArgumentOutOfRangeException(nameof(batchSize));

        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var rows = (await connection.QueryAsync<ClaimRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_SourceDocumentContentRetention_Claim",
                new
                {
                    BatchSize = batchSize,
                    LeaseId = leaseId,
                    LeaseSeconds = checked((int)leaseDuration.TotalSeconds),
                    NowUtc = nowUtc.UtcDateTime
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 60,
                cancellationToken: cancellationToken))).AsList();
            return rows.Select(MapClaim).ToArray();
        }
        catch (SqlException exception)
        {
            throw new SourceDocumentDataException(
                "claim source-document content retention", exception.Number);
        }
    }

    public Task<SourceDocumentContentRetentionMutation> CompleteAsync(
        Guid sourceDocumentId,
        Guid leaseId,
        bool quarantineDeletionRequested,
        bool trustedDeletionRequested,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken) => ExecuteMutationAsync(
            "dbo.FundingPlatform_usp_SourceDocumentContentRetention_Complete",
            "complete source-document content retention",
            new
            {
                SourceDocumentPublicId = sourceDocumentId,
                LeaseId = leaseId,
                QuarantineDeleted = quarantineDeletionRequested,
                TrustedDeleted = trustedDeletionRequested,
                NowUtc = ValidateUtc(nowUtc).UtcDateTime
            },
            cancellationToken);

    public Task<SourceDocumentContentRetentionMutation> FailAsync(
        Guid sourceDocumentId,
        Guid leaseId,
        string errorCode,
        bool isRetryable,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(errorCode);
        return ExecuteMutationAsync(
            "dbo.FundingPlatform_usp_SourceDocumentContentRetention_Fail",
            "fail source-document content retention",
            new
            {
                SourceDocumentPublicId = sourceDocumentId,
                LeaseId = leaseId,
                ErrorCode = errorCode,
                IsRetryable = isRetryable,
                NowUtc = ValidateUtc(nowUtc).UtcDateTime
            },
            cancellationToken);
    }

    private async Task<SourceDocumentContentRetentionMutation> ExecuteMutationAsync(
        string procedure,
        string operation,
        object parameters,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<MutationRow>(new CommandDefinition(
                procedure,
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            return new SourceDocumentContentRetentionMutation(
                row.Succeeded,
                NormalizeCode(row.Code),
                ToUtc(row.ContentDeletionRequestedAtUtc ?? row.ContentDeletedAtUtc),
                ToUtc(row.NextAttemptAtUtc),
                row.AttemptCount,
                row.MaxAttempts,
                row.WasReplay);
        }
        catch (SqlException exception)
        {
            throw new SourceDocumentDataException(operation, exception.Number);
        }
    }

    private static SourceDocumentContentRetentionClaim MapClaim(ClaimRow row)
    {
        if (row.SourceDocumentPublicId == Guid.Empty || row.FundingSourceId <= 0 ||
            row.ContentLength <= 0 || row.ContentHash.Length != 32 ||
            row.AttemptCount is < 1 || row.MaxAttempts < row.AttemptCount ||
            !ValidLocation(row.QuarantineBlobContainer, row.QuarantineBlobObjectName) ||
            !BlobETagNormalizer.TryNormalize(row.QuarantineBlobETag, out var quarantineETag) ||
            row.RequiresTrustedDelete != (row.TrustedBlobContainer is not null) ||
            (!row.RequiresTrustedDelete &&
                (row.TrustedBlobObjectName is not null || row.TrustedBlobETag is not null)) ||
            (row.RequiresTrustedDelete &&
                (!ValidLocation(row.TrustedBlobContainer, row.TrustedBlobObjectName) ||
                 !BlobETagNormalizer.TryNormalize(row.TrustedBlobETag, out _))))
            throw new InvalidOperationException(
                "SQL returned an invalid source-document retention claim.");

        ProtectedBlobLocation? trusted = null;
        string? trustedETag = null;
        if (row.RequiresTrustedDelete)
        {
            trusted = new ProtectedBlobLocation(
                row.TrustedBlobContainer!, row.TrustedBlobObjectName!);
            trustedETag = BlobETagNormalizer.NormalizeRequired(row.TrustedBlobETag!);
        }

        return new SourceDocumentContentRetentionClaim
        {
            SourceDocumentId = row.SourceDocumentPublicId,
            FundingSourceId = row.FundingSourceId,
            ContentHash = [.. row.ContentHash],
            ContentLength = row.ContentLength,
            QuarantineLocation = new ProtectedBlobLocation(
                row.QuarantineBlobContainer, row.QuarantineBlobObjectName),
            QuarantineETag = quarantineETag,
            TrustedLocation = trusted,
            TrustedETag = trustedETag,
            RetentionUntilUtc = Utc(row.RetentionUntilUtc),
            AttemptCount = row.AttemptCount,
            MaxAttempts = row.MaxAttempts,
            LeaseUntilUtc = Utc(row.LeaseUntilUtc)
        };
    }

    private static bool ValidLocation(string? container, string? objectName) =>
        container is { Length: >= 1 and <= 63 } &&
        !container.Any(char.IsControl) &&
        !container.Contains('/') &&
        objectName is { Length: >= 1 and <= 1024 } &&
        objectName[0] != '/' &&
        !objectName.Any(char.IsControl) &&
        !objectName.Contains('?') &&
        !objectName.Contains('#');

    private static DateTimeOffset ValidateUtc(DateTimeOffset value)
    {
        if (value.Offset != TimeSpan.Zero)
            throw new ArgumentException("The retention timestamp must be UTC.", nameof(value));
        return value;
    }

    private static DateTimeOffset? ToUtc(DateTime? value) => value.HasValue
        ? Utc(value.Value)
        : null;

    private static DateTimeOffset Utc(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static string NormalizeCode(string? code) =>
        string.IsNullOrWhiteSpace(code) ? "unknown" : code.Trim().ToLowerInvariant();

    private sealed class ClaimRow
    {
        public Guid SourceDocumentPublicId { get; init; }
        public int FundingSourceId { get; init; }
        public byte[] ContentHash { get; init; } = [];
        public long ContentLength { get; init; }
        public string QuarantineBlobContainer { get; init; } = string.Empty;
        public string QuarantineBlobObjectName { get; init; } = string.Empty;
        public string QuarantineBlobETag { get; init; } = string.Empty;
        public string? TrustedBlobContainer { get; init; }
        public string? TrustedBlobObjectName { get; init; }
        public string? TrustedBlobETag { get; init; }
        public DateTime RetentionUntilUtc { get; init; }
        public short AttemptCount { get; init; }
        public short MaxAttempts { get; init; }
        public DateTime LeaseUntilUtc { get; init; }
        public bool RequiresTrustedDelete { get; init; }
    }

    private sealed class MutationRow
    {
        public bool Succeeded { get; init; }
        public string? Code { get; init; }
        public DateTime? ContentDeletionRequestedAtUtc { get; init; }
        public DateTime? ContentDeletedAtUtc { get; init; }
        public DateTime? NextAttemptAtUtc { get; init; }
        public short? AttemptCount { get; init; }
        public short? MaxAttempts { get; init; }
        public bool WasReplay { get; init; }
    }
}
