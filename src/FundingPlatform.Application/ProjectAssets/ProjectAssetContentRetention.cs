using FundingPlatform.Application.SourceDocuments;

namespace FundingPlatform.Application.ProjectAssets;

public enum ProjectAssetContentRetentionBlobKind : byte
{
    Quarantine = 0,
    Trusted = 1
}

/// <summary>
/// A leased, immutable request to remove one exact project-asset blob
/// materialization. The identity hash is an opaque database-generated CAS token.
/// </summary>
public sealed record ProjectAssetContentRetentionClaim
{
    public required Guid TaskPublicId { get; init; }
    public Guid? ProjectAssetPublicId { get; init; }
    public required ProjectAssetContentRetentionBlobKind BlobKind { get; init; }
    public required ProtectedProjectAssetBlobLocation Location { get; init; }
    public required string BlobETag { get; init; }
    public string? BlobVersionId { get; init; }
    public required string MimeType { get; init; }
    public required long ContentLength { get; init; }
    public required byte[] ContentHash { get; init; }
    public byte[]? SourceContentHash { get; init; }
    public string? ProcessingVersion { get; init; }
    public required DateTimeOffset RetentionUntilUtc { get; init; }
    public required short AttemptCount { get; init; }
    public required short MaxAttempts { get; init; }
    public required DateTimeOffset LeaseUntilUtc { get; init; }
    public required byte[] IdentityHash { get; init; }

    public override string ToString() => "[protected project-asset retention claim]";
}

public sealed record ProjectAssetContentRetentionMutation(
    bool Succeeded,
    string Code,
    DateTimeOffset? ContentDeletedAtUtc = null,
    DateTimeOffset? NextAttemptAtUtc = null,
    short? AttemptCount = null,
    short? MaxAttempts = null,
    bool WasReplay = false);

public interface IProjectAssetContentRetentionRepository
{
    Task<IReadOnlyList<ProjectAssetContentRetentionClaim>> ClaimAsync(
        int batchSize,
        Guid leaseId,
        TimeSpan leaseDuration,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<ProjectAssetContentRetentionMutation> CompleteAsync(
        Guid taskPublicId,
        Guid leaseId,
        byte[] identityHash,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<ProjectAssetContentRetentionMutation> FailAsync(
        Guid taskPublicId,
        Guid leaseId,
        byte[] identityHash,
        string errorCode,
        bool isRetryable,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);
}

/// <summary>
/// Describes whether the exact claimed materialization is now unavailable.
/// Other versions at the same logical location may remain active.
/// </summary>
public sealed record ProjectAssetBlobRetentionDeletion(bool IsLogicallyUnavailable);

public interface IProjectAssetContentRetentionBlobStore
{
    Task<ProjectAssetBlobRetentionDeletion> RequestDeletionAsync(
        ProjectAssetContentRetentionBlobKind blobKind,
        ProtectedProjectAssetBlobLocation location,
        string expectedETag,
        string? expectedVersionId,
        string expectedMimeType,
        long expectedLength,
        byte[] expectedContentHash,
        byte[]? expectedSourceContentHash,
        string? expectedProcessingVersion,
        CancellationToken cancellationToken);
}

public sealed record ProjectAssetContentRetentionRunResult(
    int ClaimedCount,
    int CompletedCount,
    int RetryScheduledCount,
    int FailedCount);

public sealed class ProjectAssetContentRetentionService(
    IProjectAssetContentRetentionRepository repository,
    IProjectAssetContentRetentionBlobStore blobStore,
    TimeProvider timeProvider)
{
    public async Task<ProjectAssetContentRetentionRunResult> RunAsync(
        int batchSize,
        TimeSpan leaseDuration,
        CancellationToken cancellationToken)
    {
        if (batchSize is < 1 or > 100)
            throw new ArgumentOutOfRangeException(nameof(batchSize));
        if (leaseDuration < TimeSpan.FromSeconds(30) ||
            leaseDuration > TimeSpan.FromHours(1) ||
            leaseDuration.TotalSeconds != Math.Truncate(leaseDuration.TotalSeconds))
            throw new ArgumentOutOfRangeException(nameof(leaseDuration));

        var leaseId = Guid.NewGuid();
        var claims = await repository.ClaimAsync(
            batchSize,
            leaseId,
            leaseDuration,
            timeProvider.GetUtcNow(),
            cancellationToken);
        if (claims is null)
            throw new InvalidOperationException(
                "The retention repository returned an invalid claim collection.");

        var completed = 0;
        var retryScheduled = 0;
        var failed = 0;

        foreach (var claim in claims)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!TryMaterialize(claim, timeProvider.GetUtcNow(), out var normalizedETag))
            {
                if (CanRecordFailure(claim))
                    await RecordFailureAsync(
                        claim,
                        leaseId,
                        "retention-task-invalid",
                        isRetryable: false,
                        CancellationToken.None);
                failed++;
                continue;
            }

            try
            {
                var deletion = await blobStore.RequestDeletionAsync(
                    claim.BlobKind,
                    claim.Location,
                    normalizedETag,
                    claim.BlobVersionId,
                    claim.MimeType,
                    claim.ContentLength,
                    claim.ContentHash,
                    claim.SourceContentHash,
                    claim.ProcessingVersion,
                    cancellationToken);

                if (deletion is null)
                {
                    await RecordFailureAsync(
                        claim,
                        leaseId,
                        "blob-deletion-materialization-invalid",
                        isRetryable: false,
                        CancellationToken.None);
                    failed++;
                    continue;
                }

                if (!deletion.IsLogicallyUnavailable)
                {
                    if (await RecordFailureAsync(
                            claim,
                            leaseId,
                            "active-blob-version-remains",
                            isRetryable: true,
                            CancellationToken.None))
                        retryScheduled++;
                    else
                        failed++;
                    continue;
                }

                var completion = await repository.CompleteAsync(
                    claim.TaskPublicId,
                    leaseId,
                    claim.IdentityHash,
                    timeProvider.GetUtcNow(),
                    cancellationToken);
                if (completion.Succeeded && completion.Code == "completed")
                    completed++;
                else
                    failed++;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (ProjectAssetStorageException exception)
            {
                var isIdentityConflict = exception.Code is
                    "content-conflict" or "identity-conflict";
                if (await RecordFailureAsync(
                        claim,
                        leaseId,
                        isIdentityConflict
                            ? "blob-identity-conflict"
                            : "blob-deletion-unavailable",
                        isRetryable: !isIdentityConflict,
                        CancellationToken.None))
                    retryScheduled++;
                else
                    failed++;
            }
        }

        return new ProjectAssetContentRetentionRunResult(
            claims.Count, completed, retryScheduled, failed);
    }

    private static bool CanRecordFailure(ProjectAssetContentRetentionClaim? claim) =>
        claim is not null &&
        claim.TaskPublicId != Guid.Empty &&
        claim.IdentityHash is { Length: 32 };

    private async Task<bool> RecordFailureAsync(
        ProjectAssetContentRetentionClaim claim,
        Guid leaseId,
        string errorCode,
        bool isRetryable,
        CancellationToken cancellationToken)
    {
        var mutation = await repository.FailAsync(
            claim.TaskPublicId,
            leaseId,
            claim.IdentityHash,
            errorCode,
            isRetryable,
            timeProvider.GetUtcNow(),
            cancellationToken);
        return mutation.Succeeded && mutation.Code == "retry-scheduled";
    }

    private static bool TryMaterialize(
        ProjectAssetContentRetentionClaim? claim,
        DateTimeOffset nowUtc,
        out string normalizedETag)
    {
        normalizedETag = string.Empty;
        if (claim is null ||
            claim.TaskPublicId == Guid.Empty ||
            claim.ProjectAssetPublicId is null || claim.ProjectAssetPublicId == Guid.Empty ||
            !Enum.IsDefined(claim.BlobKind) ||
            claim.Location is null ||
            !IsSafeContainer(claim.Location.Container) ||
            !IsSafeObjectName(claim.Location.ObjectName, claim.MimeType) ||
            !BlobETagNormalizer.TryNormalize(claim.BlobETag, out normalizedETag) ||
            !string.Equals(claim.BlobETag, normalizedETag, StringComparison.Ordinal) ||
            !IsSafeVersionId(claim.BlobVersionId) ||
            !IsSupportedMimeType(claim.MimeType) ||
            claim.ContentLength < 1 ||
            claim.ContentLength > (claim.MimeType is "application/pdf" or "video/mp4" ? 26_214_400 : claim.MimeType == "text/plain" ? 1_048_576 : 10_485_760) ||
            claim.ContentHash is not { Length: 32 } ||
            claim.IdentityHash is not { Length: 32 } ||
            claim.RetentionUntilUtc.Offset != TimeSpan.Zero ||
            claim.RetentionUntilUtc > nowUtc ||
            claim.LeaseUntilUtc.Offset != TimeSpan.Zero ||
            claim.LeaseUntilUtc <= nowUtc ||
            claim.MaxAttempts != 8 ||
            claim.AttemptCount < 1 ||
            claim.AttemptCount > claim.MaxAttempts)
            return false;

        var hasSourceHash = claim.SourceContentHash is not null;
        var hasProcessingVersion = claim.ProcessingVersion is not null;
        if (hasSourceHash != hasProcessingVersion ||
            claim.SourceContentHash is not null and not { Length: 32 } ||
            !IsSafeProcessingVersion(claim.ProcessingVersion))
            return false;

        return claim.BlobKind switch
        {
            ProjectAssetContentRetentionBlobKind.Quarantine =>
                !hasSourceHash && !hasProcessingVersion,
            ProjectAssetContentRetentionBlobKind.Trusted => true,
            _ => false
        };
    }

    private static bool IsSafeContainer(string? value)
    {
        if (value is not { Length: >= 3 and <= 63 } ||
            value[0] == '-' || value[^1] == '-' || value.Contains("--", StringComparison.Ordinal))
            return false;
        return value.All(character =>
            character is >= 'a' and <= 'z' or >= '0' and <= '9' or '-');
    }

    private static bool IsSafeObjectName(string? value, string? mimeType)
    {
        if (value is not { Length: >= 1 and <= 1024 } ||
            value.Any(char.IsControl) ||
            value.Contains('\\') || value.Contains('?') ||
            value.Contains('#') || value.Contains('&') ||
            value.Length < 73 || value[36] != '/' || value[69] != '.' ||
            !Guid.TryParseExact(value[..36], "D", out _))
            return false;

        var leaf = value.AsSpan(37, 32);
        if (leaf.Contains('/') ||
            !leaf.ToString().All(character =>
                character is >= 'a' and <= 'f' or >= '0' and <= '9'))
            return false;

        var extension = value[69..];
        return mimeType switch
        {
            "image/jpeg" => extension is ".jpg" or ".jpeg",
            "image/png" => extension == ".png",
            "image/webp" => extension == ".webp",
            "application/pdf" => extension == ".pdf",
            "text/plain" => extension == ".txt",
            "video/mp4" => extension == ".mp4",
            _ => false
        };
    }

    private static bool IsSafeVersionId(string? value) =>
        value is null ||
        (value.Length is >= 1 and <= 200 &&
         string.Equals(value, value.Trim(), StringComparison.Ordinal) &&
         !value.Any(char.IsControl) &&
         !value.Contains('&') && !value.Contains('#') && !value.Contains('?'));

    private static bool IsSupportedMimeType(string? value) => value is
        "image/jpeg" or "image/png" or "image/webp" or "application/pdf" or "text/plain" or "video/mp4";

    private static bool IsSafeProcessingVersion(string? value) =>
        value is null ||
        (value.Length is >= 1 and <= 100 &&
         string.Equals(value, value.Trim(), StringComparison.Ordinal) &&
         !value.Any(char.IsControl));
}
