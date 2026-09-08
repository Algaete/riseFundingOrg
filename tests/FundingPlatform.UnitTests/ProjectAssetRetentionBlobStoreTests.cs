using Azure;
using Azure.Core.Pipeline;
using System.Net;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Infrastructure.ProjectAssets.Configuration;
using FundingPlatform.Infrastructure.ProjectAssets.Storage;

namespace FundingPlatform.UnitTests;

public sealed class ProjectAssetRetentionBlobStoreTests
{
    [Theory]
    [InlineData(true, true)]
    [InlineData(false, true)]
    [InlineData(true, false)]
    [InlineData(false, false)]
    public async Task Deletes_only_recorded_current_and_version_and_handles_missing_content(bool currentExists, bool versionExists)
    {
        var state = new State { CurrentExists = currentExists, VersionExists = versionExists };
        var result = await Delete(state);
        Assert.True(result.IsLogicallyUnavailable);
        Assert.Equal(currentExists ? 1 : 0, state.CurrentDeletes);
        Assert.Equal(versionExists ? 1 : 0, state.VersionDeletes);
        Assert.All(state.Conditions, condition => Assert.Equal("\"expected\"", condition));
        Assert.All(state.VersionRequests, version => Assert.Equal("exact-version", version));
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Legacy_unversioned_manifest_never_deletes_a_new_version(bool versioningEnabled)
    {
        var state = new State { ReturnedVersion = versioningEnabled ? "new-version" : null };
        var claim = ProjectAssetContentRetentionTests.Claim() with { BlobVersionId = null };
        if (versioningEnabled)
        {
            var error = await Assert.ThrowsAsync<ProjectAssetStorageException>(() => Delete(state, claim));
            Assert.Equal("content-conflict", error.Code);
            Assert.Equal(0, state.CurrentDeletes);
        }
        else
        {
            Assert.True((await Delete(state, claim)).IsLogicallyUnavailable);
            Assert.Equal(1, state.CurrentDeletes);
        }
        Assert.Empty(state.VersionRequests);
        Assert.Equal(0, state.VersionDeletes);
    }

    [Theory]
    [InlineData("remain-after-delete")]
    [InlineData("replace-after-delete")]
    public async Task Post_delete_verification_must_confirm_absence(string change)
    {
        var state = new State { Change = change };
        if (change == "replace-after-delete")
        {
            var error = await Assert.ThrowsAsync<ProjectAssetStorageException>(() => Delete(state));
            Assert.Equal("content-conflict", error.Code);
        }
        else Assert.False((await Delete(state)).IsLogicallyUnavailable);
        Assert.Equal(1, state.CurrentDeletes);
        Assert.Equal(1, state.VersionDeletes);
    }

    [Theory]
    [InlineData("etag")]
    [InlineData("hash")]
    [InlineData("length")]
    [InlineData("mime")]
    [InlineData("version")]
    [InlineData("snapshot")]
    public async Task Changed_identity_or_snapshot_conflict_does_not_delete_unclaimed_content(string change)
    {
        var state = new State { Change = change };
        var exception = await Assert.ThrowsAsync<ProjectAssetStorageException>(() => Delete(state));
        Assert.Equal(change == "snapshot" ? "azure-storage-failed" : "content-conflict", exception.Code);
        Assert.Equal(0, state.CurrentDeletes);
        Assert.Equal(0, state.VersionDeletes);
    }

    [Fact]
    public async Task Concurrent_replacement_during_delete_is_a_conflict_and_stops_version_deletion()
    {
        var state = new State { Change = "replace-on-delete" };
        var error = await Assert.ThrowsAsync<ProjectAssetStorageException>(() => Delete(state));
        Assert.Equal("content-conflict", error.Code);
        Assert.Equal(0, state.CurrentDeletes);
        Assert.Equal(0, state.VersionDeletes);
    }

    [Fact]
    public async Task Wrong_container_is_rejected_before_any_storage_operation()
    {
        var state = new State();
        var claim = ProjectAssetContentRetentionTests.Claim() with
        { Location = new("fp-source-trusted", ProjectAssetContentRetentionTests.Claim().Location.ObjectName) };
        var error = await Assert.ThrowsAsync<ProjectAssetStorageException>(() => Delete(state, claim));
        Assert.Equal("content-conflict", error.Code);
        Assert.Empty(state.Conditions);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Sanitized_content_requires_source_and_processing_metadata(bool correctMetadata)
    {
        var state = new State { SanitizedMetadata = correctMetadata };
        var claim = ProjectAssetContentRetentionTests.Claim() with
        {
            BlobKind = ProjectAssetContentRetentionBlobKind.Trusted,
            Location = new("fp-project-trusted", ProjectAssetContentRetentionTests.Claim().Location.ObjectName),
            SourceContentHash = new byte[32], ProcessingVersion = "skia-4.151.2-image-v1"
        };
        if (correctMetadata)
            Assert.True((await Delete(state, claim)).IsLogicallyUnavailable);
        else
        {
            var error = await Assert.ThrowsAsync<ProjectAssetStorageException>(() => Delete(state, claim));
            Assert.Equal("content-conflict", error.Code);
            Assert.Equal(0, state.CurrentDeletes);
        }
    }

    private static async Task<ProjectAssetBlobRetentionDeletion> Delete(
        State state, ProjectAssetContentRetentionClaim? claim = null)
    {
        claim ??= ProjectAssetContentRetentionTests.Claim();
        var options = new BlobClientOptions { Transport = new HttpClientTransport(new HttpClient(new Handler(state))) };
        options.Retry.MaxRetries = 0;
        var client = new BlobServiceClient(new Uri("https://retentiontest.blob.core.windows.net"), options);
        using var store = new AzureProjectAssetBlobStore(client, new ProjectAssetOptions(), TimeProvider.System);
        return await store.RequestDeletionAsync(claim.BlobKind, claim.Location,
            claim.BlobETag, claim.BlobVersionId, claim.MimeType, claim.ContentLength,
            claim.ContentHash, claim.SourceContentHash, claim.ProcessingVersion, default);
    }

    private sealed class State
    {
        public bool CurrentExists { get; set; } = true;
        public bool VersionExists { get; set; } = true;
        public bool SanitizedMetadata { get; init; }
        public string? ReturnedVersion { get; init; } = "exact-version";
        public string? Change { get; init; }
        public int CurrentDeletes { get; set; }
        public int VersionDeletes { get; set; }
        public List<string?> Conditions { get; } = [];
        public List<string?> VersionRequests { get; } = [];
    }

    private sealed class Handler(State state) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var isVersion = !string.IsNullOrEmpty(request.RequestUri!.Query);
            if (isVersion)
            {
                Assert.Equal("?versionid=exact-version", request.RequestUri.Query.ToLowerInvariant());
                state.VersionRequests.Add("exact-version");
            }
            var etag = request.Headers.IfMatch.SingleOrDefault()?.ToString();
            state.Conditions.Add(etag);
            var status = HttpStatusCode.OK;
            if (request.Method == HttpMethod.Head && state.Change == "replace-after-delete" &&
                state.CurrentDeletes > 0 && !isVersion)
                status = HttpStatusCode.PreconditionFailed;
            else if (!(isVersion ? state.VersionExists : state.CurrentExists))
                status = HttpStatusCode.NotFound;
            else if (state.Change == "etag" ||
                     (request.Method == HttpMethod.Delete && state.Change == "replace-on-delete"))
                status = HttpStatusCode.PreconditionFailed;
            else if (request.Method == HttpMethod.Delete && state.Change == "snapshot")
                status = HttpStatusCode.Conflict;
            else if (request.Method == HttpMethod.Delete)
            {
                Assert.False(request.Headers.Contains("x-ms-delete-snapshots"));
                Assert.Equal("\"expected\"", etag);
                if (isVersion) { state.VersionExists = state.Change == "remain-after-delete"; state.VersionDeletes++; }
                else { state.CurrentExists = state.Change == "remain-after-delete"; state.CurrentDeletes++; }
                status = HttpStatusCode.Accepted;
            }

            var response = new HttpResponseMessage(status)
            {
                RequestMessage = request,
                Content = new ByteArrayContent([])
            };
            if (status == HttpStatusCode.OK)
            {
                response.Headers.TryAddWithoutValidation("ETag", "\"expected\"");
                if (state.Change == "version" || state.ReturnedVersion is not null)
                    response.Headers.TryAddWithoutValidation("x-ms-version-id",
                        state.Change == "version" ? "unclaimed-version" : state.ReturnedVersion);
                response.Headers.TryAddWithoutValidation("x-ms-blob-type", "BlockBlob");
                response.Content.Headers.ContentLength = state.Change == "length" ? 124 : 123;
                response.Content.Headers.TryAddWithoutValidation("Content-Type",
                    state.Change == "mime" ? "text/html" : "application/pdf");
                response.Content.Headers.LastModified = DateTimeOffset.UtcNow;
                response.Headers.TryAddWithoutValidation("x-ms-meta-fp-content-sha256",
                    Convert.ToHexString(state.Change == "hash" ? new byte[32] :
                        ProjectAssetContentRetentionTests.Claim().ContentHash));
                if (state.SanitizedMetadata)
                {
                    response.Headers.TryAddWithoutValidation("x-ms-meta-fp-source-sha256",
                        Convert.ToHexString(new byte[32]));
                    response.Headers.TryAddWithoutValidation("x-ms-meta-fp-processing-version",
                        "skia-4.151.2-image-v1");
                }
            }
            else response.Headers.TryAddWithoutValidation("x-ms-error-code",
                status == HttpStatusCode.NotFound ? "BlobNotFound" : "ConditionNotMet");
            return Task.FromResult(response);
        }
    }
}
