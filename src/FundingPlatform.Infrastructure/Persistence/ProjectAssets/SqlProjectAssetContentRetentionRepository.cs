using System.Data;
using Dapper;
using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.ProjectAssets;

public sealed class SqlProjectAssetContentRetentionRepository(
    ISqlConnectionFactory connectionFactory) : IProjectAssetContentRetentionRepository
{
    public async Task<IReadOnlyList<ProjectAssetContentRetentionClaim>> ClaimAsync(
        int batchSize, Guid leaseId, TimeSpan leaseDuration, DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        ValidateUtc(nowUtc);
        if (batchSize is < 1 or > 100 || leaseId == Guid.Empty ||
            leaseDuration.TotalSeconds is < 30 or > 3600 ||
            leaseDuration.TotalSeconds != Math.Truncate(leaseDuration.TotalSeconds))
            throw new ArgumentOutOfRangeException(nameof(batchSize));
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var rows = await connection.QueryAsync<ClaimRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_ProjectAssetContentRetention_Claim",
                new { BatchSize = batchSize, LeaseId = leaseId,
                    LeaseSeconds = (int)leaseDuration.TotalSeconds, NowUtc = nowUtc.UtcDateTime },
                commandType: CommandType.StoredProcedure, commandTimeout: 60,
                cancellationToken: cancellationToken));
            return rows.Select(row => new ProjectAssetContentRetentionClaim
            {
                TaskPublicId = row.TaskPublicId,
                ProjectAssetPublicId = row.ProjectAssetPublicId,
                BlobKind = (ProjectAssetContentRetentionBlobKind)row.BlobKind,
                Location = new ProtectedProjectAssetBlobLocation(row.BlobContainer, row.BlobObjectName),
                BlobETag = row.BlobETag, BlobVersionId = row.BlobVersionId,
                MimeType = row.MimeType, ContentLength = row.ContentLength,
                ContentHash = row.ContentHash, SourceContentHash = row.SourceContentHash,
                ProcessingVersion = row.ProcessingVersion,
                RetentionUntilUtc = Utc(row.RetentionUntilUtc),
                AttemptCount = row.AttemptCount, MaxAttempts = row.MaxAttempts,
                LeaseUntilUtc = Utc(row.LeaseUntilUtc), IdentityHash = row.IdentityHash
            }).ToArray();
        }
        catch (SqlException exception)
        {
            throw new ProjectAssetDataException("claim project asset retention", exception.Number, exception);
        }
    }

    public Task<ProjectAssetContentRetentionMutation> CompleteAsync(
        Guid taskPublicId, Guid leaseId, byte[] identityHash, DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        ValidateMutation(taskPublicId, leaseId, identityHash, nowUtc);
        return MutateAsync("dbo.FundingPlatform_usp_ProjectAssetContentRetention_Complete",
            new { TaskPublicId = taskPublicId, LeaseId = leaseId, IdentityHash = identityHash,
                NowUtc = nowUtc.UtcDateTime }, cancellationToken);
    }

    public Task<ProjectAssetContentRetentionMutation> FailAsync(
        Guid taskPublicId, Guid leaseId, byte[] identityHash, string errorCode,
        bool isRetryable, DateTimeOffset nowUtc, CancellationToken cancellationToken)
    {
        ValidateMutation(taskPublicId, leaseId, identityHash, nowUtc);
        ArgumentException.ThrowIfNullOrWhiteSpace(errorCode);
        return MutateAsync("dbo.FundingPlatform_usp_ProjectAssetContentRetention_Fail",
            new { TaskPublicId = taskPublicId, LeaseId = leaseId, IdentityHash = identityHash,
                ErrorCode = errorCode, IsRetryable = isRetryable, NowUtc = nowUtc.UtcDateTime },
            cancellationToken);
    }

    private async Task<ProjectAssetContentRetentionMutation> MutateAsync(
        string procedure, object parameters, CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<MutationRow>(new CommandDefinition(
                procedure, parameters, commandType: CommandType.StoredProcedure,
                commandTimeout: 30, cancellationToken: cancellationToken));
            return new ProjectAssetContentRetentionMutation(row.Succeeded, row.Code,
                row.ContentDeletedAtUtc is { } deleted ? Utc(deleted) : null,
                row.NextAttemptAtUtc is { } next ? Utc(next) : null,
                row.AttemptCount, row.MaxAttempts, row.WasReplay);
        }
        catch (SqlException exception)
        {
            throw new ProjectAssetDataException("update project asset retention", exception.Number, exception);
        }
    }

    private static void ValidateMutation(Guid task, Guid lease, byte[] hash, DateTimeOffset now)
    {
        ValidateUtc(now);
        if (task == Guid.Empty || lease == Guid.Empty || hash is not { Length: 32 })
            throw new ArgumentException("Retention mutation requires an exact task, lease and identity.");
    }

    private static void ValidateUtc(DateTimeOffset value)
    {
        if (value.Offset != TimeSpan.Zero)
            throw new ArgumentException("Retention timestamps must be UTC.", nameof(value));
    }

    private static DateTimeOffset Utc(DateTime value) => new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private sealed class ClaimRow
    {
        public Guid TaskPublicId { get; init; }
        public Guid? ProjectAssetPublicId { get; init; }
        public byte BlobKind { get; init; }
        public string BlobContainer { get; init; } = string.Empty;
        public string BlobObjectName { get; init; } = string.Empty;
        public string BlobETag { get; init; } = string.Empty;
        public string? BlobVersionId { get; init; }
        public string MimeType { get; init; } = string.Empty;
        public long ContentLength { get; init; }
        public byte[] ContentHash { get; init; } = [];
        public byte[]? SourceContentHash { get; init; }
        public string? ProcessingVersion { get; init; }
        public DateTime RetentionUntilUtc { get; init; }
        public short AttemptCount { get; init; }
        public short MaxAttempts { get; init; }
        public DateTime LeaseUntilUtc { get; init; }
        public byte[] IdentityHash { get; init; } = [];
    }

    private sealed class MutationRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = string.Empty;
        public DateTime? ContentDeletedAtUtc { get; init; }
        public DateTime? NextAttemptAtUtc { get; init; }
        public short? AttemptCount { get; init; }
        public short? MaxAttempts { get; init; }
        public bool WasReplay { get; init; }
    }
}
