using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using FundingPlatform.Application.Projects;
using FundingPlatform.Core.Identity;
using FundingPlatform.Core.Projects;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;

public sealed class ProjectWorkflowEndpointTests : IClassFixture<ApiFactory>, IDisposable
{
    private const string JwtIssuer = "https://testing.fundingplatform.local";
    private const string JwtAudience = "FundingPlatform.Tests";
    private const string CurrentETag = "\"0102030405060708\"";
    private const string PublishedETag = "\"A1A2A3A4A5A6A7A8\"";

    private static readonly Guid UserId = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid OrganizationId = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid ProjectId = Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");
    private static readonly byte[] SigningKey = new byte[64];

    private readonly FakeProjectRepository repository = new();
    private readonly WebApplicationFactory<Program> application;
    private readonly HttpClient client;

    public ProjectWorkflowEndpointTests(ApiFactory factory)
    {
        application = factory.WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IProjectRepository>();
                services.AddSingleton<IProjectRepository>(repository);
            }));
        client = application.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
    }

    [Theory]
    [InlineData("POST", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/projects/cccccccc-cccc-cccc-cccc-cccccccccccc/publish")]
    [InlineData("POST", "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/projects/cccccccc-cccc-cccc-cccc-cccccccccccc/archive")]
    [InlineData("GET", "/api/v1/admin/projects/review-queue")]
    [InlineData("GET", "/api/v1/admin/projects/cccccccc-cccc-cccc-cccc-cccccccccccc")]
    [InlineData("POST", "/api/v1/admin/projects/cccccccc-cccc-cccc-cccc-cccccccccccc/reviews")]
    public async Task Tenant_workflow_and_admin_routes_reject_anonymous_requests(
        string method,
        string path)
    {
        using var request = new HttpRequestMessage(new HttpMethod(method), path);

        using var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal(0, repository.RequestPublicationCalls);
        Assert.Equal(0, repository.ListReviewQueueCalls);
        Assert.Equal(0, repository.GetReviewDetailsCalls);
        Assert.Equal(0, repository.ReviewCalls);
    }

    [Theory]
    [InlineData(false, true, "if-match-required")]
    [InlineData(true, false, "idempotency-key-required")]
    public async Task Publish_requires_concurrency_and_idempotency_headers(
        bool includeIfMatch,
        bool includeIdempotencyKey,
        string expectedProblemCode)
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Post,
            $"/api/v1/organizations/{OrganizationId:D}/projects/{ProjectId:D}/publish");
        if (includeIfMatch)
            request.Headers.TryAddWithoutValidation("If-Match", CurrentETag);
        if (includeIdempotencyKey)
            request.Headers.TryAddWithoutValidation("Idempotency-Key", "publish-request-0001");

        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal((HttpStatusCode)428, response.StatusCode);
        Assert.Equal(
            $"https://fundingplatform.local/problems/{expectedProblemCode}",
            problem.RootElement.GetProperty("type").GetString());
        Assert.Equal(0, repository.RequestPublicationCalls);
    }

    [Fact]
    public async Task Publish_returns_the_new_ETag_in_header_and_body()
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Post,
            $"/api/v1/organizations/{OrganizationId:D}/projects/{ProjectId:D}/publish");
        request.Headers.TryAddWithoutValidation("If-Match", CurrentETag);
        request.Headers.TryAddWithoutValidation("Idempotency-Key", "publish-request-0001");

        using var response = await client.SendAsync(request);
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var payload = document.RootElement;

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(PublishedETag, response.Headers.GetValues("ETag").Single());
        Assert.Equal(PublishedETag, payload.GetProperty("eTag").GetString());
        Assert.Equal(ProjectId, payload.GetProperty("projectId").GetGuid());
        Assert.Equal((byte)ProjectPublicationStatus.PendingReview,
            payload.GetProperty("publicationStatus").GetByte());
        Assert.Equal(87.5m, payload.GetProperty("completeness").GetDecimal());
        Assert.False(payload.GetProperty("wasReplay").GetBoolean());
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());

        Assert.Equal(1, repository.RequestPublicationCalls);
        Assert.Equal(UserId, repository.LastUserId);
        Assert.Equal(OrganizationId, repository.LastOrganizationId);
        Assert.Equal(ProjectId, repository.LastProjectId);
        Assert.Equal(Convert.FromHexString("0102030405060708"), repository.LastExpectedRowVersion);
        Assert.Equal(32, repository.LastIdempotencyKeyHash?.Length);
    }

    [Fact]
    public async Task Publish_maps_project_readiness_issues_to_a_422_problem()
    {
        repository.RequestPublicationResult = new ProjectWorkflowMutation(
            false,
            "project-not-ready",
            62.5m,
            ProjectId,
            ProjectPublicationStatus.Draft,
            null,
            null,
            null,
            null,
            null,
            Convert.FromHexString("0102030405060708"),
            false,
            [
                new ProjectReadinessIssue(
                    "budget-required",
                    "budgetTotal",
                    "El presupuesto total es obligatorio para publicar.")
            ]);
        using var request = AuthenticatedRequest(
            HttpMethod.Post,
            $"/api/v1/organizations/{OrganizationId:D}/projects/{ProjectId:D}/publish");
        request.Headers.TryAddWithoutValidation("If-Match", CurrentETag);
        request.Headers.TryAddWithoutValidation("Idempotency-Key", "publish-request-0002");

        using var response = await client.SendAsync(request);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.Equal(
            "https://fundingplatform.local/problems/project-not-ready",
            problem.RootElement.GetProperty("type").GetString());
        Assert.Equal(
            "El presupuesto total es obligatorio para publicar.",
            problem.RootElement.GetProperty("errors").GetProperty("budgetTotal")[0].GetString());
        Assert.Equal(1, repository.RequestPublicationCalls);
    }

    [Theory]
    [InlineData(null, true)]
    [InlineData(PlatformRoles.Admin, false)]
    public async Task Admin_queue_requires_both_an_admin_role_and_MFA(
        string? role,
        bool mfaAuthenticated)
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Get,
            "/api/v1/admin/projects/review-queue",
            role,
            mfaAuthenticated);

        using var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal(0, repository.ListReviewQueueCalls);
    }

    [Fact]
    public async Task Admin_with_role_and_MFA_can_read_a_non_cacheable_review_queue()
    {
        var submittedAt = new DateTimeOffset(2026, 8, 20, 12, 0, 0, TimeSpan.Zero);
        repository.ReviewQueueResult = new ProjectReviewQueuePage(
            [
                new ProjectReviewQueueItem(
                    ProjectId,
                    "agua-segura-rural",
                    "Agua segura rural",
                    "Acceso comunitario a agua potable.",
                    ProjectStatus.SeekingFunding,
                    ProjectPublicationStatus.PendingReview,
                    OrganizationId,
                    "Fundación Ejemplo",
                    87.5m,
                    submittedAt,
                    submittedAt.AddHours(1),
                    Convert.FromHexString("0102030405060708"))
            ],
            1,
            1,
            50);
        using var request = AuthenticatedRequest(
            HttpMethod.Get,
            "/api/v1/admin/projects/review-queue",
            PlatformRoles.Admin,
            mfaAuthenticated: true);

        using var response = await client.SendAsync(request);
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Contains("no-cache", response.Headers.Pragma.ToString());
        Assert.Equal(1, document.RootElement.GetProperty("totalCount").GetInt64());
        Assert.Equal(CurrentETag,
            document.RootElement.GetProperty("items")[0].GetProperty("eTag").GetString());
        Assert.Equal(1, repository.ListReviewQueueCalls);
        Assert.Equal(UserId, repository.LastUserId);
    }

    [Fact]
    public async Task Admin_review_detail_returns_ETag_without_organization_PII()
    {
        repository.ReviewDetailsResult = CreateReviewDetails();
        using var request = AuthenticatedRequest(
            HttpMethod.Get,
            $"/api/v1/admin/projects/{ProjectId:D}",
            PlatformRoles.Admin,
            mfaAuthenticated: true);

        using var response = await client.SendAsync(request);
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var payload = document.RootElement;

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(CurrentETag, response.Headers.GetValues("ETag").Single());
        Assert.Equal(CurrentETag, payload.GetProperty("eTag").GetString());
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal(1, repository.GetReviewDetailsCalls);

        AssertPropertySet(payload,
            "beneficiaryTypes",
            "budgetTotal",
            "categories",
            "completeness",
            "confirmedFunding",
            "countries",
            "currency",
            "description",
            "eTag",
            "endDate",
            "fundingGap",
            "organization",
            "projectId",
            "projectStatus",
            "projectTypes",
            "projectVersion",
            "publicationStatus",
            "regions",
            "slug",
            "startDate",
            "submittedAtUtc",
            "summary",
            "title",
            "updatedAtUtc");
        AssertPropertySet(payload.GetProperty("organization"), "name", "publicId", "websiteUrl");
        foreach (var piiField in new[]
                 {
                     "email", "phone", "contactName", "contactEmail", "contactPhone",
                     "taxId", "legalRepresentative", "address"
                 })
        {
            Assert.False(payload.TryGetProperty(piiField, out _));
            Assert.False(payload.GetProperty("organization").TryGetProperty(piiField, out _));
        }
    }

    [Theory]
    [InlineData("approve", ProjectReviewDecision.Approve, null)]
    [InlineData("reject", ProjectReviewDecision.Reject, "Falta respaldo presupuestario.")]
    public async Task Admin_review_forwards_the_decision_and_current_ETag(
        string decision,
        ProjectReviewDecision expectedDecision,
        string? reason)
    {
        using var request = AuthenticatedRequest(
            HttpMethod.Post,
            $"/api/v1/admin/projects/{ProjectId:D}/reviews",
            PlatformRoles.Admin,
            mfaAuthenticated: true);
        request.Content = JsonContent.Create(new { decision, reason });
        request.Headers.TryAddWithoutValidation("If-Match", CurrentETag);
        request.Headers.TryAddWithoutValidation("Idempotency-Key", "review-request-0001");

        using var response = await client.SendAsync(request);
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(PublishedETag, response.Headers.GetValues("ETag").Single());
        Assert.Equal(PublishedETag, document.RootElement.GetProperty("eTag").GetString());
        Assert.Equal(1, repository.ReviewCalls);
        Assert.Equal(expectedDecision, repository.LastReviewDecision);
        Assert.Equal(reason, repository.LastReviewReason);
        Assert.Equal(Convert.FromHexString("0102030405060708"),
            repository.LastReviewExpectedRowVersion);
    }

    [Fact]
    public async Task Public_project_exposes_only_the_safe_DTO_and_taxonomies_with_public_cache()
    {
        repository.PublishedProject = CreatePublishedProject();

        using var response = await client.GetAsync("/api/v1/projects/agua-segura-rural");
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var payload = document.RootElement;

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(response.Headers.CacheControl?.Public);
        Assert.Equal(TimeSpan.FromSeconds(60), response.Headers.CacheControl?.MaxAge);
        Assert.Equal("agua-segura-rural", repository.LastRequestedSlug);

        AssertPropertySet(payload,
            "beneficiaryTypes",
            "budgetTotal",
            "categories",
            "confirmedFunding",
            "countries",
            "currency",
            "description",
            "endDate",
            "fundingGap",
            "organization",
            "projectId",
            "projectStatus",
            "projectTypes",
            "publishedAtUtc",
            "regions",
            "slug",
            "startDate",
            "summary",
            "title");
        AssertPropertySet(payload.GetProperty("organization"), "name", "publicId", "websiteUrl");
        AssertPropertySet(payload.GetProperty("countries")[0], "code", "id", "name");
        AssertPropertySet(payload.GetProperty("regions")[0], "code", "countryId", "id", "name");
        AssertPropertySet(payload.GetProperty("categories")[0], "code", "id", "name");
        AssertPropertySet(payload.GetProperty("beneficiaryTypes")[0], "code", "id", "name");
        AssertPropertySet(payload.GetProperty("projectTypes")[0], "code", "id", "name");

        foreach (var internalField in new[]
                 {
                     "rowVersion", "eTag", "publicationStatus", "projectVersion",
                     "submittedAtUtc", "reviewedAtUtc", "reviewedByUserPublicId",
                     "rejectionReason", "organizationId", "contentHash"
                 })
        {
            Assert.False(payload.TryGetProperty(internalField, out _),
                $"The public response leaked internal field '{internalField}'.");
        }
    }

    [Fact]
    public async Task Public_project_rejects_an_oversized_slug_without_calling_the_repository()
    {
        var oversizedSlug = new string('a', 181);

        using var response = await client.GetAsync($"/api/v1/projects/{oversizedSlug}");
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        Assert.Equal(
            "https://fundingplatform.local/problems/published-project-not-found",
            problem.RootElement.GetProperty("type").GetString());
        Assert.Null(response.Headers.Location);
        Assert.Null(repository.LastRequestedSlug);
    }

    [Fact]
    public async Task OpenApi_contains_every_phase_5_project_route()
    {
        using var response = await client.GetAsync("/swagger/v1/swagger.json");
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var paths = document.RootElement.GetProperty("paths");
        var expectedOperations = new (string Path, string Method)[]
        {
            ("/api/v1/organizations/{organizationId}/projects/{projectId}/publish", "post"),
            ("/api/v1/organizations/{organizationId}/projects/{projectId}/archive", "post"),
            ("/api/v1/admin/projects/review-queue", "get"),
            ("/api/v1/admin/projects/{projectId}", "get"),
            ("/api/v1/admin/projects/{projectId}/reviews", "post"),
            ("/api/v1/projects/{slug}", "get")
        };

        foreach (var (path, method) in expectedOperations)
        {
            Assert.True(paths.TryGetProperty(path, out var pathItem),
                $"OpenAPI is missing path '{path}'.");
            Assert.True(pathItem.TryGetProperty(method, out _),
                $"OpenAPI path '{path}' is missing operation '{method}'.");
        }
    }

    public void Dispose()
    {
        client.Dispose();
        application.Dispose();
    }

    private static HttpRequestMessage AuthenticatedRequest(
        HttpMethod method,
        string path,
        string? role = null,
        bool mfaAuthenticated = false)
    {
        var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new AuthenticationHeaderValue(
            "Bearer",
            CreateJwt(role, mfaAuthenticated));
        return request;
    }

    private static string CreateJwt(string? role, bool mfaAuthenticated)
    {
        var now = DateTime.UtcNow;
        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, UserId.ToString("D")),
            new(ClaimTypes.NameIdentifier, UserId.ToString("D")),
            new("auth_level", "full"),
            new("amr", mfaAuthenticated ? "mfa" : "pwd"),
            new("auth_time", new DateTimeOffset(now).ToUnixTimeSeconds().ToString())
        };
        if (!string.IsNullOrWhiteSpace(role))
            claims.Add(new Claim(ClaimTypes.Role, role));

        var token = new JwtSecurityToken(
            JwtIssuer,
            JwtAudience,
            claims,
            notBefore: now.AddMinutes(-1),
            expires: now.AddMinutes(10),
            signingCredentials: new SigningCredentials(
                new SymmetricSecurityKey(SigningKey),
                SecurityAlgorithms.HmacSha512));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static PublicProjectDetails CreatePublishedProject() => new(
        ProjectId,
        "agua-segura-rural",
        "Agua segura rural",
        "Acceso comunitario a agua potable.",
        "Instalación y operación de sistemas de agua segura.",
        ProjectStatus.SeekingFunding,
        new DateOnly(2026, 9, 1),
        new DateOnly(2027, 8, 31),
        125_000_000m,
        25_000_000m,
        "CLP",
        100_000_000m,
        new DateTimeOffset(2026, 8, 20, 12, 0, 0, TimeSpan.Zero),
        new PublicProjectOrganization(
            OrganizationId,
            "Fundación Ejemplo",
            "https://fundacion.example"),
        [new PublicProjectTaxonomyItem(56, "CL", "Chile")],
        [new PublicProjectRegion(1310, 56, "CL-RM", "Región Metropolitana")],
        [new PublicProjectTaxonomyItem(10, "WATER", "Agua y saneamiento")],
        [new PublicProjectTaxonomyItem(20, "RURAL", "Comunidades rurales")],
        [new PublicProjectTaxonomyItem(30, "INFRA", "Infraestructura")]);

    private static ProjectReviewDetails CreateReviewDetails() => new(
        ProjectId,
        "agua-segura-rural",
        "Agua segura rural",
        "Acceso comunitario a agua potable.",
        "Instalación y operación de sistemas de agua segura.",
        ProjectStatus.SeekingFunding,
        ProjectPublicationStatus.PendingReview,
        new DateOnly(2026, 9, 1),
        new DateOnly(2027, 8, 31),
        125_000_000m,
        25_000_000m,
        "CLP",
        100_000_000m,
        3,
        87.5m,
        new DateTimeOffset(2026, 8, 20, 12, 0, 0, TimeSpan.Zero),
        new DateTimeOffset(2026, 8, 21, 12, 0, 0, TimeSpan.Zero),
        Convert.FromHexString("0102030405060708"),
        new PublicProjectOrganization(
            OrganizationId,
            "Fundación Ejemplo",
            "https://fundacion.example"),
        [new PublicProjectTaxonomyItem(56, "CL", "Chile")],
        [new PublicProjectRegion(1310, 56, "CL-RM", "Región Metropolitana")],
        [new PublicProjectTaxonomyItem(10, "WATER", "Agua y saneamiento")],
        [new PublicProjectTaxonomyItem(20, "RURAL", "Comunidades rurales")],
        [new PublicProjectTaxonomyItem(30, "INFRA", "Infraestructura")]);

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

    private sealed class FakeProjectRepository : IProjectRepository
    {
        public int RequestPublicationCalls { get; private set; }
        public int ListReviewQueueCalls { get; private set; }
        public int GetReviewDetailsCalls { get; private set; }
        public int ReviewCalls { get; private set; }
        public Guid? LastUserId { get; private set; }
        public Guid? LastOrganizationId { get; private set; }
        public Guid? LastProjectId { get; private set; }
        public byte[]? LastExpectedRowVersion { get; private set; }
        public byte[]? LastIdempotencyKeyHash { get; private set; }
        public ProjectReviewDecision? LastReviewDecision { get; private set; }
        public string? LastReviewReason { get; private set; }
        public byte[]? LastReviewExpectedRowVersion { get; private set; }
        public string? LastRequestedSlug { get; private set; }

        public ProjectWorkflowMutation? RequestPublicationResult { get; set; }
        public ProjectReviewQueuePage ReviewQueueResult { get; set; } = new([], 0, 1, 50);
        public ProjectReviewDetails? ReviewDetailsResult { get; set; }
        public PublicProjectDetails? PublishedProject { get; set; }

        public Task<ProjectWorkflowMutation> RequestPublicationAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            byte[] expectedRowVersion,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            CancellationToken cancellationToken)
        {
            RequestPublicationCalls++;
            LastUserId = userPublicId;
            LastOrganizationId = organizationPublicId;
            LastProjectId = projectPublicId;
            LastExpectedRowVersion = [.. expectedRowVersion];
            LastIdempotencyKeyHash = [.. idempotencyKeyHash];

            return Task.FromResult(RequestPublicationResult ?? new ProjectWorkflowMutation(
                true,
                "success",
                87.5m,
                projectPublicId,
                ProjectPublicationStatus.PendingReview,
                new DateTimeOffset(2026, 8, 21, 12, 0, 0, TimeSpan.Zero),
                null,
                null,
                null,
                null,
                Convert.FromHexString("A1A2A3A4A5A6A7A8"),
                false,
                []));
        }

        public Task<ProjectReviewQueuePage> ListReviewQueueAsync(
            Guid userPublicId,
            int pageNumber,
            int pageSize,
            CancellationToken cancellationToken)
        {
            ListReviewQueueCalls++;
            LastUserId = userPublicId;
            return Task.FromResult(ReviewQueueResult);
        }

        public Task<ProjectReviewDetails?> GetReviewDetailsAsync(
            Guid userPublicId,
            Guid projectPublicId,
            CancellationToken cancellationToken)
        {
            GetReviewDetailsCalls++;
            LastUserId = userPublicId;
            LastProjectId = projectPublicId;
            return Task.FromResult(ReviewDetailsResult);
        }

        public Task<PublicProjectDetails?> GetPublishedBySlugAsync(
            string slug,
            CancellationToken cancellationToken)
        {
            LastRequestedSlug = slug;
            return Task.FromResult(PublishedProject);
        }

        public Task<IReadOnlyList<ProjectSummary>> ListAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<ProjectDetails?> GetAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<PersistedProject> CreateAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            string slug,
            ProjectData project,
            string snapshotJson,
            byte[] contentHash,
            CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<PersistedProject> UpdateAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            byte[] expectedRowVersion,
            ProjectData project,
            string snapshotJson,
            byte[] contentHash,
            CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<ProjectWorkflowMutation> ArchiveAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            byte[] expectedRowVersion,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<ProjectWorkflowMutation> ReviewAsync(
            Guid userPublicId,
            Guid projectPublicId,
            ProjectReviewDecision decision,
            string? reason,
            byte[] expectedRowVersion,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            CancellationToken cancellationToken)
        {
            ReviewCalls++;
            LastUserId = userPublicId;
            LastProjectId = projectPublicId;
            LastReviewDecision = decision;
            LastReviewReason = reason;
            LastReviewExpectedRowVersion = [.. expectedRowVersion];

            return Task.FromResult(new ProjectWorkflowMutation(
                true,
                "success",
                100m,
                projectPublicId,
                decision == ProjectReviewDecision.Approve
                    ? ProjectPublicationStatus.Published
                    : ProjectPublicationStatus.Rejected,
                new DateTimeOffset(2026, 8, 20, 12, 0, 0, TimeSpan.Zero),
                decision == ProjectReviewDecision.Approve
                    ? new DateTimeOffset(2026, 8, 21, 12, 0, 0, TimeSpan.Zero)
                    : null,
                new DateTimeOffset(2026, 8, 21, 12, 0, 0, TimeSpan.Zero),
                userPublicId,
                decision == ProjectReviewDecision.Reject ? reason : null,
                Convert.FromHexString("A1A2A3A4A5A6A7A8"),
                false,
                []));
        }
    }
}
