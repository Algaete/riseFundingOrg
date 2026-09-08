using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Core.ProjectAssets;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;

public sealed class ProjectAssetEndpointTests : IClassFixture<ApiFactory>, IDisposable
{
    private const string JwtIssuer = "https://testing.fundingplatform.local";
    private const string JwtAudience = "FundingPlatform.Tests";
    private const string CurrentProjectETag = "\"0102030405060708\"";
    private const string IntentETag = "\"1112131415161718\"";
    private const string AssetETag = "\"2122232425262728\"";
    private const string UpdatedProjectETag = "\"3132333435363738\"";

    private static readonly Guid UserId = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid OrganizationId = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid ProjectId = Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");
    private static readonly Guid IntentId = Guid.Parse("dddddddd-dddd-dddd-dddd-dddddddddddd");
    private static readonly Guid AssetId = Guid.Parse("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee");
    private static readonly byte[] SigningKey = new byte[64];
    private static readonly byte[] ProjectRowVersion = Convert.FromHexString("0102030405060708");
    private static readonly byte[] IntentRowVersion = Convert.FromHexString("1112131415161718");
    private static readonly byte[] AssetRowVersion = Convert.FromHexString("2122232425262728");
    private static readonly byte[] UpdatedProjectRowVersion = Convert.FromHexString("3132333435363738");
    private static readonly byte[] ContentHash = SHA256.HashData("project-asset"u8);

    private readonly ApiFactory factory;
    private readonly FakeRepository repository = new();
    private readonly FakeBlobStore blobs = new();
    private readonly FakeInspector inspector = new();
    private readonly FakeScanner scanner = new();
    private readonly FakeTokenService tokens = new();
    private readonly WebApplicationFactory<Program> application;
    private readonly HttpClient client;

    public ProjectAssetEndpointTests(ApiFactory factory)
    {
        this.factory = factory;
        application = BuildApplication(enableAssets: true);
        client = application.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
    }

    [Theory]
    [InlineData("GET", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/projects/cccccccc-cccc-cccc-cccc-cccccccccccc/assets")]
    [InlineData("POST", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/projects/cccccccc-cccc-cccc-cccc-cccccccccccc/asset-upload-intents")]
    [InlineData("GET", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/projects/cccccccc-cccc-cccc-cccc-cccccccccccc/asset-upload-intents/dddddddd-dddd-dddd-dddd-dddddddddddd")]
    [InlineData("POST", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/projects/cccccccc-cccc-cccc-cccc-cccccccccccc/asset-upload-intents/dddddddd-dddd-dddd-dddd-dddddddddddd/complete")]
    [InlineData("PATCH", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/projects/cccccccc-cccc-cccc-cccc-cccccccccccc/assets/eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")]
    [InlineData("PUT", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/projects/cccccccc-cccc-cccc-cccc-cccccccccccc/assets/order")]
    [InlineData("DELETE", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/projects/cccccccc-cccc-cccc-cccc-cccccccccccc/assets/eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")]
    [InlineData("GET", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/projects/cccccccc-cccc-cccc-cccc-cccccccccccc/assets/eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/content")]
    public async Task Project_asset_routes_require_a_full_authenticated_session(
        string method,
        string path)
    {
        using var response = await client.SendAsync(
            new HttpRequestMessage(new HttpMethod(method), path));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        AssertDependenciesWereNotCalled();
    }

    [Fact]
    public async Task Disabled_feature_returns_503_for_every_route_without_touching_dependencies()
    {
        using var disabledApplication = BuildApplication(enableAssets: false);
        using var disabledClient = disabledApplication.CreateClient(
            new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });
        var requests = new[]
        {
            AuthenticatedRequest(HttpMethod.Get, AssetsPath()),
            JsonRequest(HttpMethod.Post, $"{ProjectPath()}/asset-upload-intents", new
            {
                kind = (byte)ProjectAssetKind.Document,
                fileName = "evidence.pdf",
                mimeType = "application/pdf",
                contentLength = 1024
            }, CurrentProjectETag),
            AuthenticatedRequest(HttpMethod.Get, $"{ProjectPath()}/asset-upload-intents/{IntentId:D}"),
            JsonRequest(HttpMethod.Post,
                $"{ProjectPath()}/asset-upload-intents/{IntentId:D}/complete",
                new { completionToken = "valid-token" }),
            JsonRequest(HttpMethod.Patch, $"{AssetsPath()}/{AssetId:D}", new
            {
                displayName = "Evidence",
                altText = (string?)null,
                caption = (string?)null,
                isCover = false
            }, AssetETag, UpdatedProjectETag),
            JsonRequest(HttpMethod.Put, $"{AssetsPath()}/order", new { items = Array.Empty<object>() },
                CurrentProjectETag),
            AuthenticatedRequest(HttpMethod.Delete, $"{AssetsPath()}/{AssetId:D}",
                AssetETag, UpdatedProjectETag),
            AuthenticatedRequest(HttpMethod.Get, $"{AssetsPath()}/{AssetId:D}/content")
        };

        foreach (var request in requests)
        {
            using (request)
            using (var response = await disabledClient.SendAsync(request))
            {
                Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
            }
        }

        AssertDependenciesWereNotCalled();
    }

    [Fact]
    public async Task Create_requires_the_project_If_Match_header()
    {
        using var request = JsonRequest(
            HttpMethod.Post,
            $"{ProjectPath()}/asset-upload-intents",
            ValidCreatePayload());

        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal((HttpStatusCode)428, response.StatusCode);
        Assert.Equal(
            "https://fundingplatform.local/problems/project-if-match-required",
            problem.RootElement.GetProperty("type").GetString());
        AssertDependenciesWereNotCalled();
    }

    [Fact]
    public async Task Create_maps_a_stale_project_ETag_to_412()
    {
        repository.CreateResult = new ProjectAssetMutation(false, "project-etag-conflict");
        using var request = JsonRequest(
            HttpMethod.Post,
            $"{ProjectPath()}/asset-upload-intents",
            ValidCreatePayload(),
            CurrentProjectETag);

        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.PreconditionFailed, response.StatusCode);
        Assert.Equal(
            "https://fundingplatform.local/problems/project-etag-conflict",
            problem.RootElement.GetProperty("type").GetString());
        Assert.Equal(1, repository.CreateCalls);
        Assert.Equal(0, blobs.CreateGrantCalls);
    }

    [Fact]
    public async Task Create_returns_a_minimal_create_only_grant_and_both_concurrency_tokens()
    {
        repository.CreateResult = new ProjectAssetMutation(
            true,
            "created",
            IntentId,
            ProjectAssetUploadIntentStatus.Pending,
            IntentRowVersion: IntentRowVersion,
            ProjectRowVersion: UpdatedProjectRowVersion,
            ExpiresAtUtc: DateTimeOffset.UtcNow.AddMinutes(5));
        using var request = JsonRequest(
            HttpMethod.Post,
            $"{ProjectPath()}/asset-upload-intents",
            ValidCreatePayload(),
            CurrentProjectETag);

        using var response = await client.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();
        using var json = JsonDocument.Parse(body);
        var root = json.RootElement;

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal($"{ProjectPath()}/asset-upload-intents/{IntentId:D}",
            response.Headers.Location?.ToString());
        Assert.Equal(IntentETag, response.Headers.ETag?.Tag);
        Assert.Equal(UpdatedProjectETag,
            response.Headers.GetValues("X-Project-ETag").Single());
        Assert.Equal("PUT", root.GetProperty("uploadMethod").GetString());
        Assert.Equal("one-time-project-asset-token",
            root.GetProperty("completionToken").GetString());
        Assert.Equal(IntentETag, root.GetProperty("eTag").GetString());
        Assert.Equal(UpdatedProjectETag, root.GetProperty("projectETag").GetString());
        var headers = root.GetProperty("requiredHeaders");
        Assert.Equal("BlockBlob", headers.GetProperty("x-ms-blob-type").GetString());
        Assert.Equal("application/pdf", headers.GetProperty("Content-Type").GetString());
        Assert.Equal("*", headers.GetProperty("If-None-Match").GetString());
        AssertPropertySet(root,
            "completionToken", "eTag", "expiresAtUtc", "intentId", "kind",
            "maxContentLength", "projectETag", "requiredHeaders", "securityNotice",
            "status", "statusUrl", "uploadMethod", "uploadUrl");
        Assert.DoesNotContain("quarantine", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("trusted", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("contentHash", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("completionTokenHash", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("objectName", body, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(1, repository.CreateCalls);
        Assert.Equal(1, blobs.CreateGrantCalls);
        Assert.Equal(1, tokens.CreateCalls);
    }

    [Fact]
    public async Task Complete_with_an_invalid_token_returns_404_without_repository_or_blob_access()
    {
        using var request = JsonRequest(
            HttpMethod.Post,
            $"{ProjectPath()}/asset-upload-intents/{IntentId:D}/complete",
            new { completionToken = "invalid-token" });

        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal("https://fundingplatform.local/problems/invalid-token",
            problem.RootElement.GetProperty("type").GetString());
        Assert.Equal(1, tokens.TryHashCalls);
        Assert.Equal(0, repository.Calls);
        Assert.Equal(0, blobs.Calls);
    }

    [Fact]
    public async Task Complete_with_a_pending_scan_returns_202_retry_metadata_without_work_secrets()
    {
        PrepareFinalize(ProjectAssetScanStatus.Pending);
        using var request = JsonRequest(
            HttpMethod.Post,
            $"{ProjectPath()}/asset-upload-intents/{IntentId:D}/complete",
            new { completionToken = "valid-token" });

        using var response = await client.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();
        using var json = JsonDocument.Parse(body);

        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
        Assert.Equal($"{ProjectPath()}/asset-upload-intents/{IntentId:D}",
            response.Headers.Location?.ToString());
        Assert.Equal(TimeSpan.FromSeconds(2), response.Headers.RetryAfter?.Delta);
        Assert.Equal((byte)ProjectAssetScanStatus.Pending,
            json.RootElement.GetProperty("scanStatus").GetByte());
        Assert.Equal(UpdatedProjectETag,
            response.Headers.GetValues("X-Project-ETag").Single());
        Assert.DoesNotContain("container", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("objectName", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("contentHash", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("completionToken", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("sig=", body, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(1, inspector.Calls);
        Assert.Equal(1, scanner.Calls);
        Assert.Equal(1, blobs.EnsureCopyCalls);
        Assert.Equal(0, repository.ApplyScanCalls);
    }

    [Fact]
    public async Task Complete_with_a_clean_scan_returns_200_and_ready_metadata()
    {
        PrepareFinalize(ProjectAssetScanStatus.Clean);
        using var request = JsonRequest(
            HttpMethod.Post,
            $"{ProjectPath()}/asset-upload-intents/{IntentId:D}/complete",
            new { completionToken = "valid-token" });

        using var response = await client.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();
        using var json = JsonDocument.Parse(body);
        var root = json.RootElement;

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(AssetETag, response.Headers.ETag?.Tag);
        Assert.Equal(UpdatedProjectETag,
            response.Headers.GetValues("X-Project-ETag").Single());
        Assert.Equal(AssetId, root.GetProperty("assetId").GetGuid());
        Assert.Equal((byte)ProjectAssetStorageStatus.Trusted,
            root.GetProperty("storageStatus").GetByte());
        Assert.Equal((byte)ProjectAssetScanStatus.Clean,
            root.GetProperty("scanStatus").GetByte());
        Assert.DoesNotContain("container", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("objectName", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("contentHash", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("completionToken", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("sig=", body, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(1, inspector.Calls);
        Assert.Equal(1, scanner.Calls);
        Assert.Equal(2, blobs.EnsureCopyCalls);
        Assert.Equal(1, repository.ApplyScanCalls);
    }

    [Fact]
    public async Task Scan_completion_after_a_concurrent_delete_is_hidden_as_404()
    {
        PrepareFinalize(ProjectAssetScanStatus.Clean);
        repository.ApplyResult = new ProjectAssetMutation(
            false,
            "asset-deleted",
            AssetPublicId: AssetId);
        using var request = JsonRequest(
            HttpMethod.Post,
            $"{ProjectPath()}/asset-upload-intents/{IntentId:D}/complete",
            new { completionToken = "valid-token" });

        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal(
            "https://fundingplatform.local/problems/asset-deleted",
            problem.RootElement.GetProperty("type").GetString());
        Assert.Equal(1, repository.ApplyScanCalls);
    }

    [Fact]
    public async Task List_exposes_only_metadata_and_content_urls_for_clean_trusted_assets()
    {
        repository.Collection = new ProjectAssetCollection(
            ProjectId,
            PublicationStatus: 0,
            UpdatedProjectRowVersion,
            [
                Asset(
                    AssetId,
                    ProjectAssetKind.Document,
                    ProjectAssetStorageStatus.Trusted,
                    ProjectAssetScanStatus.Clean,
                    "evidence.pdf"),
                Asset(
                    Guid.Parse("ffffffff-ffff-ffff-ffff-ffffffffffff"),
                    ProjectAssetKind.Image,
                    ProjectAssetStorageStatus.Quarantined,
                    ProjectAssetScanStatus.Pending,
                    "pending.png")
            ]);
        using var request = AuthenticatedRequest(HttpMethod.Get, AssetsPath());

        using var response = await client.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();
        using var json = JsonDocument.Parse(body);
        var items = json.RootElement.GetProperty("items");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(UpdatedProjectETag, response.Headers.ETag?.Tag);
        Assert.Equal(UpdatedProjectETag,
            response.Headers.GetValues("X-Project-ETag").Single());
        Assert.True(items[0].GetProperty("isReady").GetBoolean());
        Assert.Equal($"{AssetsPath()}/{AssetId:D}/content",
            items[0].GetProperty("contentUrl").GetString());
        Assert.False(items[1].GetProperty("isReady").GetBoolean());
        Assert.Equal(JsonValueKind.Null, items[1].GetProperty("contentUrl").ValueKind);
        Assert.DoesNotContain("container", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("objectName", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("contentHash", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("blobETag", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("blobVersion", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("completionToken", body, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(1, repository.ListCalls);
        Assert.Equal(0, blobs.Calls);
    }

    [Fact]
    public async Task Patch_and_delete_require_both_asset_and_project_concurrency_headers()
    {
        foreach (var method in new[] { HttpMethod.Patch, HttpMethod.Delete })
        {
            using var missingAsset = MutationRequest(method);
            using var missingAssetResponse = await client.SendAsync(missingAsset);
            using var missingAssetProblem = JsonDocument.Parse(
                await missingAssetResponse.Content.ReadAsStringAsync());
            Assert.Equal((HttpStatusCode)428, missingAssetResponse.StatusCode);
            Assert.Equal("https://fundingplatform.local/problems/asset-if-match-required",
                missingAssetProblem.RootElement.GetProperty("type").GetString());

            using var missingProject = MutationRequest(method, AssetETag);
            using var missingProjectResponse = await client.SendAsync(missingProject);
            using var missingProjectProblem = JsonDocument.Parse(
                await missingProjectResponse.Content.ReadAsStringAsync());
            Assert.Equal((HttpStatusCode)428, missingProjectResponse.StatusCode);
            Assert.Equal("https://fundingplatform.local/problems/project-if-match-required",
                missingProjectProblem.RootElement.GetProperty("type").GetString());
        }

        Assert.Equal(0, repository.UpdateCalls);
        Assert.Equal(0, repository.DeleteCalls);
    }

    [Theory]
    [InlineData("PATCH", "asset-etag-conflict")]
    [InlineData("DELETE", "project-etag-conflict")]
    public async Task Stale_asset_or_project_ETags_return_412(string method, string code)
    {
        repository.UpdateResult = new ProjectAssetMutation(false, code, AssetPublicId: AssetId);
        repository.DeleteResult = new ProjectAssetMutation(false, code, AssetPublicId: AssetId);
        using var request = MutationRequest(new HttpMethod(method), AssetETag, UpdatedProjectETag);

        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.PreconditionFailed, response.StatusCode);
        Assert.Equal($"https://fundingplatform.local/problems/{code}",
            problem.RootElement.GetProperty("type").GetString());
    }

    [Fact]
    public async Task Pending_image_cannot_be_selected_as_the_project_cover()
    {
        repository.UpdateResult = new ProjectAssetMutation(
            false,
            "cover-image-not-ready",
            AssetPublicId: AssetId);
        using var request = MutationRequest(
            HttpMethod.Patch,
            AssetETag,
            UpdatedProjectETag);

        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal((HttpStatusCode)422, response.StatusCode);
        Assert.Equal(
            "https://fundingplatform.local/problems/cover-image-not-ready",
            problem.RootElement.GetProperty("type").GetString());
        Assert.Equal(1, repository.UpdateCalls);
    }

    [Fact]
    public async Task Content_for_an_asset_that_is_not_clean_and_trusted_is_hidden_as_404()
    {
        repository.TrustedContent = null;
        using var request = AuthenticatedRequest(
            HttpMethod.Get, $"{AssetsPath()}/{AssetId:D}/content");

        using var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal(1, repository.GetContentCalls);
        Assert.Equal(0, blobs.OpenReadCalls);
    }

    [Fact]
    public async Task Clean_PDF_content_is_an_attachment_with_nosniff_and_no_store()
    {
        var payload = "%PDF-1.7\nproject evidence\n%%EOF"u8.ToArray();
        repository.TrustedContent = new ProjectAssetTrustedContent(
            AssetId,
            ProjectAssetKind.Document,
            "evidence.pdf",
            "application/pdf",
            payload.Length,
            SHA256.HashData(payload),
            new ProtectedProjectAssetBlobLocation("fp-project-trusted", "private/evidence.pdf"),
            "\"trusted-etag\"",
            "trusted-version");
        blobs.OpenReadFactory = () => new ProjectAssetBlobRead(
            new MemoryStream(payload, writable: false),
            payload.Length,
            "application/pdf",
            "\"trusted-etag\"",
            "trusted-version");
        using var request = AuthenticatedRequest(
            HttpMethod.Get, $"{AssetsPath()}/{AssetId:D}/content");

        using var response = await client.SendAsync(request);
        var downloaded = await response.Content.ReadAsByteArrayAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/pdf", response.Content.Headers.ContentType?.MediaType);
        Assert.Equal("attachment", response.Content.Headers.ContentDisposition?.DispositionType);
        Assert.Equal("evidence.pdf",
            response.Content.Headers.ContentDisposition?.FileName?.Trim('"'));
        Assert.Equal("nosniff", response.Headers.GetValues("X-Content-Type-Options").Single());
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal("default-src 'none'; sandbox",
            response.Headers.GetValues("Content-Security-Policy").Single());
        Assert.Equal(payload, downloaded);
        Assert.Equal(1, repository.GetContentCalls);
        Assert.Equal(1, blobs.OpenReadCalls);
    }

    public void Dispose()
    {
        client.Dispose();
        application.Dispose();
    }

    private WebApplicationFactory<Program> BuildApplication(bool enableAssets) =>
        factory.WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IProjectAssetRepository>();
                services.RemoveAll<IProjectAssetBlobStore>();
                services.RemoveAll<IProjectAssetContentInspector>();
                services.RemoveAll<IProjectAssetScanner>();
                services.RemoveAll<IProjectAssetCompletionTokenService>();
                services.AddSingleton<IProjectAssetRepository>(repository);
                services.AddSingleton<IProjectAssetBlobStore>(blobs);
                services.AddSingleton<IProjectAssetContentInspector>(inspector);
                services.AddSingleton<IProjectAssetScanner>(scanner);
                services.AddSingleton<IProjectAssetCompletionTokenService>(tokens);
                if (enableAssets)
                {
                    services.RemoveAll<ProjectAssetPolicy>();
                    services.AddSingleton(EnabledPolicy());
                }
            }));

    private static ProjectAssetPolicy EnabledPolicy() => new(
        true,
        new Uri("https://testing.blob.core.windows.net"),
        "fp-project-incoming",
        "fp-project-quarantine",
        "fp-project-trusted",
        10_485_760,
        26_214_400,
        262_144_000,
        25_000_000,
        TimeSpan.FromMinutes(5),
        TimeSpan.FromSeconds(120),
        TimeSpan.FromSeconds(10),
        ProjectAssetScanProvider.DevelopmentFake);

    private void PrepareFinalize(ProjectAssetScanStatus scanStatus)
    {
        var incoming = new ProtectedProjectAssetBlobLocation(
            "fp-project-incoming", "private/evidence.pdf");
        var quarantine = new ProtectedProjectAssetBlobLocation(
            "fp-project-quarantine", "private/evidence.pdf");
        var trusted = new ProtectedProjectAssetBlobLocation(
            "fp-project-trusted", "private/evidence.pdf");
        repository.AcquireFactory = leaseId => new ProjectAssetFinalizeWork
        {
            Succeeded = true,
            Code = "acquired",
            IntentPublicId = IntentId,
            IntentStatus = ProjectAssetUploadIntentStatus.Finalizing,
            Kind = ProjectAssetKind.Document,
            OriginalFileName = "evidence.pdf",
            DeclaredMimeType = "application/pdf",
            ExpectedContentLength = 1024,
            MaxContentLength = 26_214_400,
            IncomingLocation = incoming,
            QuarantineLocation = quarantine,
            TrustedLocation = trusted,
            FinalizeLeaseId = leaseId,
            FinalizeLeaseUntilUtc = DateTimeOffset.UtcNow.AddMinutes(2),
            IntentRowVersion = IntentRowVersion,
            ProjectRowVersion = ProjectRowVersion
        };
        repository.CompleteResult = new ProjectAssetMutation(
            true,
            "completed",
            IntentId,
            ProjectAssetUploadIntentStatus.Completed,
            AssetId,
            ProjectAssetStorageStatus.AwaitingQuarantine,
            ProjectAssetScanStatus.Pending,
            ProjectAssetScanProvider.DevelopmentFake,
            IntentRowVersion,
            AssetRowVersion,
            UpdatedProjectRowVersion);
        repository.MarkResult = new ProjectAssetMutation(
            true,
            "quarantined",
            AssetPublicId: AssetId,
            StorageStatus: ProjectAssetStorageStatus.Quarantined,
            ScanStatus: ProjectAssetScanStatus.Pending,
            ScanProvider: ProjectAssetScanProvider.DevelopmentFake,
            AssetRowVersion: AssetRowVersion,
            ProjectRowVersion: UpdatedProjectRowVersion);
        repository.ApplyResult = new ProjectAssetMutation(
            true,
            "scan-result-applied",
            AssetPublicId: AssetId,
            StorageStatus: scanStatus == ProjectAssetScanStatus.Clean
                ? ProjectAssetStorageStatus.Trusted
                : ProjectAssetStorageStatus.Quarantined,
            ScanStatus: scanStatus,
            ScanProvider: ProjectAssetScanProvider.DevelopmentFake,
            AssetRowVersion: AssetRowVersion,
            ProjectRowVersion: UpdatedProjectRowVersion);
        blobs.OpenReadFactory = () => new ProjectAssetBlobRead(
            new MemoryStream("ignored-by-fake-inspector"u8.ToArray(), writable: false),
            1024,
            "application/pdf",
            "\"incoming-etag\"",
            "incoming-version");
        inspector.Result = new ProjectAssetInspection(
            true,
            ProjectAssetInspectionFailure.None,
            1024,
            ContentHash,
            "application/pdf");
        scanner.Status = scanStatus;
    }

    private static object ValidCreatePayload() => new
    {
        kind = (byte)ProjectAssetKind.Document,
        fileName = "evidence.pdf",
        mimeType = "application/pdf",
        contentLength = 1024
    };

    private static ProjectAsset Asset(
        Guid assetId,
        ProjectAssetKind kind,
        ProjectAssetStorageStatus storageStatus,
        ProjectAssetScanStatus scanStatus,
        string fileName) => new(
        assetId,
        kind,
        fileName,
        Path.GetFileNameWithoutExtension(fileName),
        kind == ProjectAssetKind.Document ? "application/pdf" : "image/png",
        1024,
        kind == ProjectAssetKind.Image ? 32 : null,
        kind == ProjectAssetKind.Image ? 32 : null,
        storageStatus,
        scanStatus,
        ProjectAssetScanProvider.DevelopmentFake,
        scanStatus == ProjectAssetScanStatus.Pending ? "scan-pending" : "clean",
        0,
        false,
        kind == ProjectAssetKind.Image ? "Preview" : null,
        null,
        DateTimeOffset.UtcNow.AddMinutes(-1),
        DateTimeOffset.UtcNow,
        AssetRowVersion);

    private static HttpRequestMessage MutationRequest(
        HttpMethod method,
        string? assetETag = null,
        string? projectETag = null)
    {
        if (method == HttpMethod.Patch)
        {
            return JsonRequest(method, $"{AssetsPath()}/{AssetId:D}", new
            {
                displayName = "Evidence",
                altText = (string?)null,
                caption = (string?)null,
                isCover = false
            }, assetETag, projectETag);
        }

        return AuthenticatedRequest(method, $"{AssetsPath()}/{AssetId:D}",
            assetETag, projectETag);
    }

    private static HttpRequestMessage JsonRequest(
        HttpMethod method,
        string path,
        object value,
        string? ifMatch = null,
        string? projectIfMatch = null)
    {
        var request = AuthenticatedRequest(method, path, ifMatch, projectIfMatch);
        request.Content = JsonContent.Create(value);
        return request;
    }

    private static HttpRequestMessage AuthenticatedRequest(
        HttpMethod method,
        string path,
        string? ifMatch = null,
        string? projectIfMatch = null)
    {
        var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", CreateJwt());
        if (ifMatch is not null)
            request.Headers.TryAddWithoutValidation("If-Match", ifMatch);
        if (projectIfMatch is not null)
            request.Headers.TryAddWithoutValidation("X-Project-If-Match", projectIfMatch);
        return request;
    }

    private static string CreateJwt()
    {
        var now = DateTime.UtcNow;
        var token = new JwtSecurityToken(
            JwtIssuer,
            JwtAudience,
            [
                new Claim(JwtRegisteredClaimNames.Sub, UserId.ToString("D")),
                new Claim(ClaimTypes.NameIdentifier, UserId.ToString("D")),
                new Claim("auth_level", "full")
            ],
            now.AddMinutes(-1),
            now.AddMinutes(10),
            new SigningCredentials(
                new SymmetricSecurityKey(SigningKey),
                SecurityAlgorithms.HmacSha512));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private void AssertDependenciesWereNotCalled()
    {
        Assert.Equal(0, repository.Calls);
        Assert.Equal(0, blobs.Calls);
        Assert.Equal(0, inspector.Calls);
        Assert.Equal(0, scanner.Calls);
        Assert.Equal(0, tokens.Calls);
    }

    private static void AssertPropertySet(JsonElement element, params string[] expectedProperties)
    {
        var actual = element.EnumerateObject()
            .Select(property => property.Name)
            .OrderBy(name => name, StringComparer.Ordinal)
            .ToArray();
        var expected = expectedProperties
            .OrderBy(name => name, StringComparer.Ordinal)
            .ToArray();
        Assert.Equal(expected, actual);
    }

    private static string ProjectPath() =>
        $"/api/v1/organizations/{OrganizationId:D}/projects/{ProjectId:D}";

    private static string AssetsPath() => $"{ProjectPath()}/assets";

    private sealed class FakeTokenService : IProjectAssetCompletionTokenService
    {
        public int CreateCalls { get; private set; }
        public int TryHashCalls { get; private set; }
        public int Calls => CreateCalls + TryHashCalls;

        public ProjectAssetCompletionSecret Create()
        {
            CreateCalls++;
            return new ProjectAssetCompletionSecret(
                "one-time-project-asset-token",
                SHA256.HashData("one-time-project-asset-token"u8));
        }

        public bool TryHash(string token, out byte[] hash)
        {
            TryHashCalls++;
            hash = SHA256.HashData(Encoding.UTF8.GetBytes(token));
            return token == "valid-token";
        }
    }

    private sealed class FakeInspector : IProjectAssetContentInspector
    {
        public int Calls { get; private set; }
        public ProjectAssetInspection Result { get; set; } = new(
            false, ProjectAssetInspectionFailure.InvalidFile, 0, null, null);

        public Task<ProjectAssetInspection> InspectAsync(
            ProjectAssetKind kind,
            ProjectAssetBlobRead source,
            long expectedLength,
            long maximumLength,
            int maximumImagePixels,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(Result);
        }
    }

    private sealed class FakeScanner : IProjectAssetScanner
    {
        public int Calls { get; private set; }
        public ProjectAssetScanStatus Status { get; set; } = ProjectAssetScanStatus.Pending;

        public Task<ProjectAssetScanObservation> ObserveAsync(
            Guid assetPublicId,
            ProtectedProjectAssetBlobLocation quarantineLocation,
            string quarantineETag,
            CancellationToken cancellationToken)
        {
            Calls++;
            var resultCode = Status == ProjectAssetScanStatus.Pending ? "scan-pending" : "clean";
            return Task.FromResult(new ProjectAssetScanObservation(
                Status,
                resultCode,
                $"test-{Status}",
                DateTimeOffset.UtcNow));
        }
    }

    private sealed class FakeBlobStore : IProjectAssetBlobStore
    {
        public int CreateGrantCalls { get; private set; }
        public int OpenReadCalls { get; private set; }
        public int EnsureCopyCalls { get; private set; }
        public int DeleteCalls { get; private set; }
        public int Calls => CreateGrantCalls + OpenReadCalls + EnsureCopyCalls + DeleteCalls;
        public Func<ProjectAssetBlobRead> OpenReadFactory { get; set; } = () =>
            new ProjectAssetBlobRead(
                new MemoryStream([]), 0, null, "\"empty\"", null);

        public Task<ProjectAssetUploadGrant> CreateUploadGrantAsync(
            ProtectedProjectAssetBlobLocation destination,
            string contentType,
            DateTimeOffset expiresAtUtc,
            CancellationToken cancellationToken)
        {
            CreateGrantCalls++;
            return Task.FromResult(new ProjectAssetUploadGrant(
                new Uri("https://testing.blob.core.windows.net/fp-project-incoming/upload.pdf?sp=cw&sig=redacted"),
                expiresAtUtc,
                new Dictionary<string, string>
                {
                    ["x-ms-blob-type"] = "BlockBlob",
                    ["Content-Type"] = contentType,
                    ["If-None-Match"] = "*"
                }));
        }

        public Task<ProjectAssetBlobRead> OpenReadAsync(
            ProtectedProjectAssetBlobLocation source,
            string? expectedETag,
            CancellationToken cancellationToken)
        {
            OpenReadCalls++;
            return Task.FromResult(OpenReadFactory());
        }

        public Task<ProjectAssetBlobReceipt> EnsureCopyAsync(
            ProtectedProjectAssetBlobLocation source,
            string sourceETag,
            ProtectedProjectAssetBlobLocation destination,
            string contentType,
            long expectedLength,
            byte[] expectedContentHash,
            CancellationToken cancellationToken)
        {
            EnsureCopyCalls++;
            return Task.FromResult(new ProjectAssetBlobReceipt(
                EnsureCopyCalls == 1 ? "\"quarantine-etag\"" : "\"trusted-etag\"",
                EnsureCopyCalls == 1 ? "quarantine-version" : "trusted-version"));
        }

        public Task DeleteIfMatchAsync(
            ProtectedProjectAssetBlobLocation location,
            string? expectedETag,
            CancellationToken cancellationToken)
        {
            DeleteCalls++;
            return Task.CompletedTask;
        }
    }

    private sealed class FakeRepository : IProjectAssetRepository
    {
        public int Calls { get; private set; }
        public int CreateCalls { get; private set; }
        public int ListCalls { get; private set; }
        public int UpdateCalls { get; private set; }
        public int DeleteCalls { get; private set; }
        public int GetContentCalls { get; private set; }
        public int ApplyScanCalls { get; private set; }

        public ProjectAssetMutation CreateResult { get; set; } =
            new(false, "invalid-asset");
        public Func<Guid, ProjectAssetFinalizeWork> AcquireFactory { get; set; } = _ => new()
        {
            Succeeded = false,
            Code = "upload-intent-not-found",
            IntentPublicId = IntentId
        };
        public ProjectAssetMutation CompleteResult { get; set; } =
            new(false, "invalid-transition");
        public ProjectAssetMutation MarkResult { get; set; } =
            new(false, "invalid-transition");
        public ProjectAssetMutation ApplyResult { get; set; } =
            new(false, "invalid-transition");
        public ProjectAssetMutation UpdateResult { get; set; } =
            new(false, "invalid-metadata");
        public ProjectAssetMutation DeleteResult { get; set; } =
            new(false, "invalid-asset");
        public ProjectAssetMutation ReorderResult { get; set; } =
            new(false, "invalid-order");
        public ProjectAssetCollection Collection { get; set; } = new(
            ProjectId, 0, ProjectRowVersion, []);
        public ProjectAssetUploadIntent? Intent { get; set; }
        public ProjectAssetTrustedContent? TrustedContent { get; set; }

        public Task<ProjectAssetMutation> CreateUploadIntentAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            byte[] expectedProjectRowVersion,
            ProjectAssetKind kind,
            string originalFileName,
            string declaredMimeType,
            long expectedContentLength,
            long maxContentLength,
            ProtectedProjectAssetBlobLocation incomingLocation,
            ProtectedProjectAssetBlobLocation quarantineLocation,
            ProtectedProjectAssetBlobLocation trustedLocation,
            byte[] completionTokenHash,
            DateTimeOffset expiresAtUtc,
            CancellationToken cancellationToken)
        {
            Calls++;
            CreateCalls++;
            return Task.FromResult(CreateResult);
        }

        public Task<ProjectAssetFinalizeWork> AcquireFinalizeAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid intentPublicId,
            byte[] completionTokenHash,
            Guid leaseId,
            DateTimeOffset leaseUntilUtc,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(AcquireFactory(leaseId));
        }

        public Task<ProjectAssetMutation> ReleaseFinalizeAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid intentPublicId,
            Guid leaseId,
            string errorCode,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(new ProjectAssetMutation(false, errorCode));
        }

        public Task<ProjectAssetMutation> RejectFinalizeAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid intentPublicId,
            Guid leaseId,
            string errorCode,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(new ProjectAssetMutation(
                true,
                errorCode,
                intentPublicId,
                ProjectAssetUploadIntentStatus.Rejected));
        }

        public Task<ProjectAssetMutation> CompleteUploadIntentAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid intentPublicId,
            Guid leaseId,
            byte[] expectedProjectRowVersion,
            string verifiedMimeType,
            long actualContentLength,
            byte[] contentHash,
            int? pixelWidth,
            int? pixelHeight,
            ProjectAssetScanProvider scanProvider,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(CompleteResult);
        }

        public Task<ProjectAssetMutation> MarkQuarantinedAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid assetPublicId,
            byte[] expectedAssetRowVersion,
            ProjectAssetBlobReceipt receipt,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(MarkResult);
        }

        public Task<ProjectAssetMutation> ApplyScanResultAsync(
            Guid assetPublicId,
            ProjectAssetScanProvider scanProvider,
            string providerEventId,
            byte[] payloadHash,
            string quarantineETag,
            byte[]? reportedContentHash,
            ProjectAssetScanStatus status,
            string resultCode,
            ProtectedProjectAssetBlobLocation? trustedLocation,
            ProjectAssetBlobReceipt? trustedReceipt,
            DateTimeOffset occurredAtUtc,
            CancellationToken cancellationToken)
        {
            Calls++;
            ApplyScanCalls++;
            return Task.FromResult(ApplyResult);
        }

        public Task<ProjectAssetCollection> ListAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            CancellationToken cancellationToken)
        {
            Calls++;
            ListCalls++;
            return Task.FromResult(Collection);
        }

        public Task<ProjectAssetUploadIntent?> GetUploadIntentAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid intentPublicId,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(Intent);
        }

        public Task<ProjectAssetTrustedContent?> GetTrustedContentAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid assetPublicId,
            CancellationToken cancellationToken)
        {
            Calls++;
            GetContentCalls++;
            return Task.FromResult(TrustedContent);
        }

        public Task<ProjectAssetMutation> UpdateMetadataAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid assetPublicId,
            byte[] expectedAssetRowVersion,
            byte[] expectedProjectRowVersion,
            ProjectAssetMetadata metadata,
            CancellationToken cancellationToken)
        {
            Calls++;
            UpdateCalls++;
            return Task.FromResult(UpdateResult);
        }

        public Task<ProjectAssetMutation> ReorderAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            byte[] expectedProjectRowVersion,
            IReadOnlyList<ProjectAssetOrderItem> items,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(ReorderResult);
        }

        public Task<ProjectAssetMutation> DeleteAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid assetPublicId,
            byte[] expectedAssetRowVersion,
            byte[] expectedProjectRowVersion,
            CancellationToken cancellationToken)
        {
            Calls++;
            DeleteCalls++;
            return Task.FromResult(DeleteResult);
        }
    }
}
