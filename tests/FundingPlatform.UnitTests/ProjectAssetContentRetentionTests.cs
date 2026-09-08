using System.Security.Cryptography;
using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using FundingPlatform.Infrastructure.ProjectAssets.Configuration;
using FundingPlatform.Workers.Configuration;
using FundingPlatform.Workers.Functions;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class ProjectAssetContentRetentionTests
{
    private static readonly DateTimeOffset Now = new(2026, 9, 8, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Completes_only_after_storage_confirms_absence_and_passes_exact_identity()
    {
        var claim = Claim();
        var repo = new Repository(claim);
        var storage = new Storage();
        var result = await new ProjectAssetContentRetentionService(repo, storage, new Clock())
            .RunAsync(25, TimeSpan.FromMinutes(15), default);
        Assert.Equal(new ProjectAssetContentRetentionRunResult(1, 1, 0, 0), result);
        Assert.Equal(claim.TaskPublicId, repo.CompletedTask);
        Assert.Equal(claim.IdentityHash, repo.CompletedHash);
        Assert.NotEqual(Guid.Empty, repo.Lease);
        Assert.Equal(claim.BlobVersionId, storage.Version);
        Assert.Equal(claim.ContentHash, storage.Hash);
    }

    [Theory]
    [InlineData("content-conflict", false, "blob-identity-conflict")]
    [InlineData("azure-storage-failed", true, "blob-deletion-unavailable")]
    [InlineData(null, true, "active-blob-version-remains")]
    public async Task Conflict_is_terminal_and_unavailable_storage_or_remaining_content_is_retryable(
        string? code, bool retryable, string recordedCode)
    {
        var repo = new Repository(Claim());
        var storage = new Storage { Error = code, Absent = false };
        var result = await new ProjectAssetContentRetentionService(repo, storage, new Clock())
            .RunAsync(25, TimeSpan.FromMinutes(15), default);
        Assert.Null(repo.CompletedTask);
        Assert.Equal(recordedCode, repo.Error);
        Assert.Equal(retryable, repo.Retryable);
        Assert.Equal(retryable ? 1 : 0, result.RetryScheduledCount);
        Assert.Equal(retryable ? 0 : 1, result.FailedCount);
    }

    [Fact]
    public async Task Malformed_or_expired_claim_never_reaches_storage()
    {
        var good = Claim();
        foreach (var bad in new[]
        {
            good with { BlobETag = "unquoted" },
            good with { BlobVersionId = "version?sig=secret" },
            good with { ContentHash = [1, 2] },
            good with { ProjectAssetPublicId = null },
            good with { MaxAttempts = 9 },
            good with { ContentLength = 26_214_401 },
            good with { LeaseUntilUtc = Now },
            good with { RetentionUntilUtc = Now.AddMinutes(1) },
            good with { BlobKind = (ProjectAssetContentRetentionBlobKind)99 },
            good with { Location = new("fp-project-quarantine", "../active.pdf") },
            good with { SourceContentHash = new byte[32] }
        })
        {
            var repo = new Repository(bad);
            var storage = new Storage();
            var result = await new ProjectAssetContentRetentionService(repo, storage, new Clock())
                .RunAsync(25, TimeSpan.FromMinutes(15), default);
            Assert.Equal(0, storage.Calls);
            Assert.Equal(1, result.FailedCount);
        }
    }

    [Fact]
    public async Task Cancellation_preserves_lease_for_recovery_without_recording_completion()
    {
        var repo = new Repository(Claim());
        var storage = new Storage();
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            new ProjectAssetContentRetentionService(repo, storage, new Clock())
                .RunAsync(25, TimeSpan.FromMinutes(15), cancellation.Token));
        Assert.Equal(0, storage.Calls);
        Assert.Null(repo.CompletedTask);
    }

    [Fact]
    public async Task Disabled_project_assets_make_timer_inert()
    {
        var repo = new Repository(Claim());
        var timer = new ProjectAssetContentRetentionFunction(
            new(repo, new Storage(), new Clock()), Options.Create(new ContentRetentionOptions()),
            Options.Create(new ProjectAssetOptions()), NullLogger<ProjectAssetContentRetentionFunction>.Instance);
        await timer.RunAsync(new TimerInfo(), default);
        Assert.Equal(Guid.Empty, repo.Lease);
    }

    [Fact]
    public void Sql_migration_and_transactional_smoke_parse_for_azure_sql()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var scripts = SqlScriptCatalog.DiscoverMigrations(root).Where(s => s.Sequence == 39)
            .Concat(SqlScriptCatalog.DiscoverTests(root).Where(s => s.Sequence is 27 or 37 or 38 or 39));
        foreach (var script in scripts)
        {
            foreach (var batch in script.Batches)
            {
                using var reader = new StringReader(batch);
                _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(reader, out var errors);
                Assert.True(errors.Count == 0, string.Join("; ", errors.Select(e =>
                    $"{script.FileName}:{e.Line}:{e.Column} {e.Message}")));
            }
        }
    }

    [Theory]
    [InlineData(0, 900, false)]
    [InlineData(101, 900, false)]
    [InlineData(25, 29, false)]
    [InlineData(25, 3601, false)]
    [InlineData(1, 30, true)]
    [InlineData(100, 3600, true)]
    public void Retention_configuration_is_bounded(int batch, int lease, bool valid)
    {
        var options = new ContentRetentionOptions { ProjectAssetBatchSize = batch, ProjectAssetLeaseSeconds = lease };
        Assert.Equal(valid, new ContentRetentionOptionsValidator().Validate(null, options).Succeeded);
    }

    internal static ProjectAssetContentRetentionClaim Claim() => new()
    {
        TaskPublicId = Guid.NewGuid(), ProjectAssetPublicId = Guid.NewGuid(),
        BlobKind = ProjectAssetContentRetentionBlobKind.Quarantine,
        Location = new("fp-project-quarantine", "11111111-1111-1111-1111-111111111111/22222222222222222222222222222222.pdf"),
        BlobETag = "\"expected\"", BlobVersionId = "exact-version", MimeType = "application/pdf",
        ContentLength = 123, ContentHash = SHA256.HashData("pdf"u8),
        IdentityHash = SHA256.HashData("identity"u8), RetentionUntilUtc = Now.AddDays(-1),
        LeaseUntilUtc = Now.AddMinutes(15), AttemptCount = 1, MaxAttempts = 8
    };

    private sealed class Clock : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => Now;
    }

    private sealed class Repository(ProjectAssetContentRetentionClaim claim) : IProjectAssetContentRetentionRepository
    {
        public Guid Lease { get; private set; }
        public Guid? CompletedTask { get; private set; }
        public byte[]? CompletedHash { get; private set; }
        public string? Error { get; private set; }
        public bool Retryable { get; private set; }
        public Task<IReadOnlyList<ProjectAssetContentRetentionClaim>> ClaimAsync(
            int batchSize, Guid leaseId, TimeSpan duration, DateTimeOffset now, CancellationToken token)
        {
            Lease = leaseId;
            return Task.FromResult<IReadOnlyList<ProjectAssetContentRetentionClaim>>([claim]);
        }
        public Task<ProjectAssetContentRetentionMutation> CompleteAsync(
            Guid task, Guid lease, byte[] hash, DateTimeOffset now, CancellationToken token)
        {
            Assert.Equal(Lease, lease);
            CompletedTask = task;
            CompletedHash = hash;
            return Task.FromResult(new ProjectAssetContentRetentionMutation(true, "completed"));
        }
        public Task<ProjectAssetContentRetentionMutation> FailAsync(
            Guid task, Guid lease, byte[] hash, string error, bool retryable, DateTimeOffset now, CancellationToken token)
        {
            Assert.Equal(Lease, lease);
            Assert.Equal(claim.IdentityHash, hash);
            Error = error;
            Retryable = retryable;
            return Task.FromResult(new ProjectAssetContentRetentionMutation(true, retryable ? "retry-scheduled" : "failed"));
        }
    }

    private sealed class Storage : IProjectAssetContentRetentionBlobStore
    {
        public string? Error { get; init; }
        public bool Absent { get; init; } = true;
        public int Calls { get; private set; }
        public string? Version { get; private set; }
        public byte[]? Hash { get; private set; }
        public Task<ProjectAssetBlobRetentionDeletion> RequestDeletionAsync(
            ProjectAssetContentRetentionBlobKind kind, ProtectedProjectAssetBlobLocation location,
            string etag, string? version, string mime, long length, byte[] hash,
            byte[]? sourceHash, string? processingVersion, CancellationToken token)
        {
            Calls++;
            Version = version;
            Hash = hash;
            return Error is null ? Task.FromResult(new ProjectAssetBlobRetentionDeletion(Absent)) :
                Task.FromException<ProjectAssetBlobRetentionDeletion>(new ProjectAssetStorageException("delete", Error, 409));
        }
    }
}
