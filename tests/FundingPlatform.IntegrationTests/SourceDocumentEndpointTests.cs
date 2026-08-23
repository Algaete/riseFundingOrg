using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Core.Identity;
using FundingPlatform.Core.SourceDocuments;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;

public sealed class SourceDocumentEndpointTests : IClassFixture<ApiFactory>, IDisposable
{
    private const string JwtIssuer = "https://testing.fundingplatform.local";
    private const string JwtAudience = "FundingPlatform.Tests";
    private const string CurrentETag = "\"0102030405060708\"";
    private static readonly byte[] SigningKey = new byte[64];
    private static readonly byte[] RowVersion = Convert.FromHexString("0102030405060708");
    private static readonly byte[] ContentHash = SHA256.HashData("document"u8);
    private static readonly Guid UserId = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid IntentId = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid DocumentId = Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");

    private readonly FakeRepository repository = new();
    private readonly FakeBlobStore blobs = new();
    private readonly FakeScanner scanner = new();
    private readonly WebApplicationFactory<Program> application;
    private readonly HttpClient client;

    public SourceDocumentEndpointTests(ApiFactory factory)
    {
        application = factory.WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<ISourceDocumentRepository>();
                services.RemoveAll<ISourceDocumentBlobStore>();
                services.RemoveAll<ISourceDocumentScanner>();
                services.RemoveAll<ISourceDocumentCompletionTokenService>();
                services.AddSingleton<ISourceDocumentRepository>(repository);
                services.AddSingleton<ISourceDocumentBlobStore>(blobs);
                services.AddSingleton<ISourceDocumentScanner>(scanner);
                services.AddSingleton<ISourceDocumentCompletionTokenService, FakeTokenService>();
            }));
        client = application.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
    }

    [Theory]
    [InlineData("POST", "/api/v1/admin/source-document-upload-intents")]
    [InlineData("GET", "/api/v1/admin/source-document-upload-intents/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")]
    [InlineData("POST", "/api/v1/admin/source-document-upload-intents/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/complete")]
    [InlineData("GET", "/api/v1/admin/source-documents/cccccccc-cccc-cccc-cccc-cccccccccccc")]
    [InlineData("POST", "/api/v1/admin/source-documents/cccccccc-cccc-cccc-cccc-cccccccccccc/scan/retry")]
    public async Task Source_document_routes_are_admin_MFA_only_and_non_cacheable(
        string method,
        string path)
    {
        using var response = await client.SendAsync(
            new HttpRequestMessage(new HttpMethod(method), path));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
    }

    [Fact]
    public async Task Create_returns_canonical_status_location_and_exact_create_only_headers()
    {
        repository.CreateResult = new SourceDocumentMutation(
            true, "created", IntentId, SourceDocumentUploadIntentStatus.Pending,
            RowVersion: RowVersion, ExpiresAtUtc: DateTimeOffset.UtcNow.AddMinutes(5));
        using var request = AuthenticatedRequest(
            HttpMethod.Post, "/api/v1/admin/source-document-upload-intents");
        request.Content = JsonContent.Create(new
        {
            fundingSourceId = 1,
            fileName = "convocatoria.pdf",
            mimeType = "application/pdf",
            contentLength = 1024
        });

        using var response = await client.SendAsync(request);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal(
            $"/api/v1/admin/source-document-upload-intents/{IntentId:D}",
            response.Headers.Location?.ToString());
        Assert.Equal(CurrentETag, response.Headers.ETag?.Tag);
        Assert.Equal("PUT", json.RootElement.GetProperty("uploadMethod").GetString());
        var headers = json.RootElement.GetProperty("requiredHeaders");
        Assert.Equal("BlockBlob", headers.GetProperty("x-ms-blob-type").GetString());
        Assert.Equal("application/pdf", headers.GetProperty("Content-Type").GetString());
        Assert.Equal("*", headers.GetProperty("If-None-Match").GetString());
        Assert.Equal(
            $"/api/v1/admin/source-document-upload-intents/{IntentId:D}",
            json.RootElement.GetProperty("statusUrl").GetString());
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
    }

    [Fact]
    public async Task Complete_pending_returns_202_retry_headers_and_never_discloses_work_data()
    {
        PreparePendingDocument();
        scanner.Status = SourceDocumentScanStatus.Pending;
        using var request = AuthenticatedRequest(
            HttpMethod.Post,
            $"/api/v1/admin/source-document-upload-intents/{IntentId:D}/complete");
        request.Content = JsonContent.Create(new { completionToken = "valid-token" });

        using var response = await client.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
        Assert.Equal(
            $"/api/v1/admin/source-document-upload-intents/{IntentId:D}",
            response.Headers.Location?.ToString());
        Assert.Equal(TimeSpan.FromSeconds(2), response.Headers.RetryAfter?.Delta);
        Assert.DoesNotContain("container", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("objectName", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("contentHash", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("completionToken", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("sig=", body, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Retry_requires_ETag_and_idempotency_key_then_runs_private_scan_work()
    {
        PreparePendingDocument();
        repository.RetryResult = new SourceDocumentRetryMutation(
            true, "scan-retry-requested", DocumentId,
            SourceDocumentStorageStatus.Quarantined, SourceDocumentScanStatus.Pending,
            SourceDocumentScanProvider.DevelopmentFake, 2, RowVersion, false);
        scanner.Status = SourceDocumentScanStatus.Clean;
        using var missing = AuthenticatedRequest(
            HttpMethod.Post,
            $"/api/v1/admin/source-documents/{DocumentId:D}/scan/retry");

        using var missingResponse = await client.SendAsync(missing);
        Assert.Equal((HttpStatusCode)428, missingResponse.StatusCode);

        using var request = AuthenticatedRequest(
            HttpMethod.Post,
            $"/api/v1/admin/source-documents/{DocumentId:D}/scan/retry");
        request.Headers.TryAddWithoutValidation("If-Match", CurrentETag);
        request.Headers.TryAddWithoutValidation("Idempotency-Key", "retry-source-document-0001");
        using var response = await client.SendAsync(request);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal((byte)SourceDocumentScanStatus.Clean,
            json.RootElement.GetProperty("scanStatus").GetByte());
        Assert.Equal(1, repository.AcquireScanWorkCalls);
        Assert.Equal(1, repository.ApplyCalls);
        Assert.Equal(1, blobs.CopyCalls);
    }

    [Fact]
    public async Task Stale_retry_ETag_returns_412_not_a_generic_conflict()
    {
        repository.RetryResult = new SourceDocumentRetryMutation(
            false, "etag-conflict", DocumentId,
            SourceDocumentStorageStatus.Quarantined, SourceDocumentScanStatus.Failed,
            SourceDocumentScanProvider.DevelopmentFake, 1, RowVersion, false);
        using var request = AuthenticatedRequest(
            HttpMethod.Post,
            $"/api/v1/admin/source-documents/{DocumentId:D}/scan/retry");
        request.Headers.TryAddWithoutValidation("If-Match", CurrentETag);
        request.Headers.TryAddWithoutValidation("Idempotency-Key", "retry-source-document-0002");

        using var response = await client.SendAsync(request);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.PreconditionFailed, response.StatusCode);
        Assert.Equal(
            "https://fundingplatform.local/problems/source-document-etag-conflict",
            json.RootElement.GetProperty("type").GetString());
    }

    public void Dispose()
    {
        client.Dispose();
        application.Dispose();
    }

    private void PreparePendingDocument()
    {
        var location = new ProtectedBlobLocation(
            "fp-source-quarantine", "uploads/2026/08/21/document.pdf");
        repository.FinalizeWork = new SourceDocumentFinalizeWork
        {
            Succeeded = true,
            Code = "completed",
            IntentPublicId = IntentId,
            IntentStatus = SourceDocumentUploadIntentStatus.Completed,
            SourceDocumentPublicId = DocumentId,
            QuarantineLocation = location,
            ActualContentLength = 1024,
            ContentHash = ContentHash,
            BlobETag = "\"quarantine-etag\"",
            StorageStatus = SourceDocumentStorageStatus.Quarantined,
            ScanStatus = SourceDocumentScanStatus.Pending,
            ScanProvider = SourceDocumentScanProvider.DevelopmentFake,
            RowVersion = RowVersion,
            WasReplay = true
        };
        repository.ScanWork = new SourceDocumentScanWork
        {
            Succeeded = true,
            Code = "acquired",
            SourceDocumentPublicId = DocumentId,
            QuarantineLocation = location,
            ContentLength = 1024,
            ContentHash = ContentHash,
            BlobETag = "\"quarantine-etag\"",
            ScanProvider = SourceDocumentScanProvider.DevelopmentFake,
            ScanAttemptCount = 2,
            RowVersion = RowVersion
        };
        repository.Document = new SourceDocument(
            DocumentId, 1, "Manual document upload", "document.pdf", "application/pdf", 1024,
            SourceDocumentStorageStatus.Quarantined, SourceDocumentScanStatus.Pending,
            SourceDocumentScanProvider.DevelopmentFake, false, 2, null,
            DateTimeOffset.UtcNow, null, 0, UserId,
            DateTimeOffset.UtcNow.AddMinutes(-1), DateTimeOffset.UtcNow, RowVersion);
    }

    private static HttpRequestMessage AuthenticatedRequest(HttpMethod method, string path)
    {
        var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", CreateJwt());
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
                new Claim("auth_level", "full"),
                new Claim("amr", "mfa"),
                new Claim("auth_time", new DateTimeOffset(now).ToUnixTimeSeconds().ToString()),
                new Claim(ClaimTypes.Role, PlatformRoles.Admin)
            ],
            now.AddMinutes(-1),
            now.AddMinutes(10),
            new SigningCredentials(new SymmetricSecurityKey(SigningKey),
                SecurityAlgorithms.HmacSha512));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private sealed class FakeTokenService : ISourceDocumentCompletionTokenService
    {
        public SourceDocumentCompletionSecret Create() =>
            new("one-time-token", SHA256.HashData("one-time-token"u8));

        public bool TryHash(string token, out byte[] hash)
        {
            hash = SHA256.HashData(Encoding.UTF8.GetBytes(token));
            return token == "valid-token";
        }
    }

    private sealed class FakeScanner : ISourceDocumentScanner
    {
        public SourceDocumentScanStatus Status { get; set; } = SourceDocumentScanStatus.Pending;

        public Task<SourceDocumentScanObservation> ObserveAsync(
            Guid sourceDocumentPublicId, short scanAttemptCount,
            ProtectedBlobLocation quarantineLocation, string quarantineETag,
            CancellationToken cancellationToken) => Task.FromResult(new SourceDocumentScanObservation(
                Status, $"test-{Status}", $"test-{scanAttemptCount}-{Status}",
                DateTimeOffset.UtcNow));
    }

    private sealed class FakeBlobStore : ISourceDocumentBlobStore
    {
        public int CopyCalls { get; private set; }

        public Task<SourceDocumentUploadGrant> CreateUploadGrantAsync(
            ProtectedBlobLocation destination, DateTimeOffset expiresAtUtc,
            CancellationToken cancellationToken) => Task.FromResult(new SourceDocumentUploadGrant(
                new Uri("https://testing.blob.core.windows.net/fp-source-incoming/file.pdf?sig=redacted"),
                expiresAtUtc,
                new Dictionary<string, string>
                {
                    ["x-ms-blob-type"] = "BlockBlob",
                    ["Content-Type"] = "application/pdf",
                    ["If-None-Match"] = "*"
                }));

        public Task<SourceBlobReceipt> EnsureCopyAsync(
            ProtectedBlobLocation source, string sourceETag,
            ProtectedBlobLocation destination, long expectedLength,
            byte[] expectedContentHash, CancellationToken cancellationToken)
        {
            CopyCalls++;
            return Task.FromResult(new SourceBlobReceipt("\"trusted-etag\"", "version"));
        }

        public Task<SourceBlobRead> OpenReadAsync(
            ProtectedBlobLocation source, string? expectedETag,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<SourceBlobReceipt?> GetVerifiedReceiptAsync(
            ProtectedBlobLocation location, long expectedLength,
            byte[] expectedContentHash, CancellationToken cancellationToken) =>
            Task.FromResult<SourceBlobReceipt?>(null);
        public Task DeleteIfMatchAsync(
            ProtectedBlobLocation location, string? expectedETag,
            CancellationToken cancellationToken) => Task.CompletedTask;
    }

    private sealed class FakeRepository : ISourceDocumentRepository
    {
        public SourceDocumentMutation CreateResult { get; set; } =
            new(false, "invalid-document");
        public SourceDocumentFinalizeWork FinalizeWork { get; set; } = new();
        public SourceDocumentScanWork ScanWork { get; set; } = new();
        public SourceDocumentRetryMutation RetryResult { get; set; } =
            new(false, "invalid-transition", DocumentId, null, null, null, null, null, false);
        public SourceDocument Document { get; set; } = null!;
        public int AcquireScanWorkCalls { get; private set; }
        public int ApplyCalls { get; private set; }

        public Task<SourceDocumentMutation> CreateUploadIntentAsync(
            Guid adminUserPublicId, int fundingSourceId, string originalFileName,
            string declaredMimeType, long expectedContentLength, long maxContentLength,
            ProtectedBlobLocation incomingLocation, ProtectedBlobLocation quarantineLocation,
            byte[] completionTokenHash, DateTimeOffset expiresAtUtc,
            CancellationToken cancellationToken) => Task.FromResult(CreateResult);
        public Task<SourceDocumentFinalizeWork> AcquireFinalizeAsync(
            Guid adminUserPublicId, Guid intentPublicId, byte[] completionTokenHash,
            Guid leaseId, DateTimeOffset leaseUntilUtc,
            CancellationToken cancellationToken) => Task.FromResult(FinalizeWork);
        public Task<SourceDocumentRetryMutation> RetryScanAsync(
            Guid adminUserPublicId, Guid sourceDocumentPublicId,
            byte[] expectedRowVersion, byte[] idempotencyKeyHash,
            byte[] requestHash, CancellationToken cancellationToken) => Task.FromResult(RetryResult);
        public Task<SourceDocumentScanWork> AcquireScanWorkAsync(
            Guid adminUserPublicId, Guid sourceDocumentPublicId,
            byte[] expectedRowVersion, CancellationToken cancellationToken)
        {
            AcquireScanWorkCalls++;
            return Task.FromResult(ScanWork);
        }
        public Task<SourceDocument?> GetSourceDocumentAsync(
            Guid adminUserPublicId, Guid sourceDocumentPublicId,
            CancellationToken cancellationToken) => Task.FromResult<SourceDocument?>(Document);
        public Task<SourceDocumentMutation> ApplyScanResultAsync(
            Guid sourceDocumentPublicId, SourceDocumentScanProvider scanProvider,
            string providerEventId, byte[] payloadHash, string quarantineETag,
            byte[]? reportedContentHash, SourceDocumentScanStatus status,
            string resultCode, ProtectedBlobLocation? trustedLocation,
            SourceBlobReceipt? trustedReceipt, DateTimeOffset occurredAtUtc,
            CancellationToken cancellationToken)
        {
            ApplyCalls++;
            return Task.FromResult(new SourceDocumentMutation(
                true, "scan-result-applied", SourceDocumentPublicId: sourceDocumentPublicId,
                StorageStatus: status == SourceDocumentScanStatus.Clean
                    ? SourceDocumentStorageStatus.Trusted
                    : SourceDocumentStorageStatus.Quarantined,
                ScanStatus: status, ScanProvider: scanProvider, RowVersion: RowVersion));
        }
        public Task<SourceDocumentUploadIntent?> GetUploadIntentAsync(
            Guid adminUserPublicId, Guid intentPublicId,
            CancellationToken cancellationToken) => Task.FromResult<SourceDocumentUploadIntent?>(null);
        public Task<SourceDocumentMutation> ReleaseFinalizeAsync(
            Guid adminUserPublicId, Guid intentPublicId, Guid leaseId,
            string errorCode, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<SourceDocumentMutation> RejectFinalizeAsync(
            Guid adminUserPublicId, Guid intentPublicId, Guid leaseId,
            string errorCode, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<SourceDocumentMutation> CompleteUploadIntentAsync(
            Guid adminUserPublicId, Guid intentPublicId, Guid leaseId,
            long actualContentLength, byte[] contentHash,
            SourceDocumentScanProvider scanProvider,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<SourceDocumentMutation> MarkQuarantinedAsync(
            Guid adminUserPublicId, Guid sourceDocumentPublicId,
            SourceBlobReceipt receipt, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }
}
