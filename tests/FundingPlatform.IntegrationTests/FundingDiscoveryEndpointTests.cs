using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Core.Collaboration;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;
public sealed class FundingDiscoveryEndpointTests(ApiFactory factory) : IClassFixture<ApiFactory>
{
    [Theory]
    [InlineData(false, null)][InlineData(false, "es")][InlineData(false, "en")]
    [InlineData(true, null)][InlineData(true, "es")][InlineData(true, "en")]
    public async Task Discovery_localizes_only_enabled_published_page_without_changing_filters(bool enabled, string? locale)
    {
        var id = Guid.NewGuid();
        var classification = new FundingDiscoveryData(2, false, true, "https://example.invalid/evidence");
        var repository = new Repository { Items = [new(id, "original", "Original", "Summary", "Source",
            "https://example.invalid", DateTimeOffset.UtcNow, 100, 200, "AUD", new(2027,1,1), classification, 5)] };
        var translations = new SummaryRepository();
        await using var app = factory.WithWebHostBuilder(builder => builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<IFundingDiscoveryRepository>(); services.AddSingleton<IFundingDiscoveryRepository>(repository);
            services.RemoveAll<IFundingTranslationRepository>(); services.AddSingleton<IFundingTranslationRepository>(translations);
            services.RemoveAll<FundingTranslationOptions>(); services.AddSingleton(new FundingTranslationOptions { Enabled = enabled });
        }));
        using var client = app.CreateClient();
        using var response = await client.GetAsync("/api/v1/funding-discovery?query=agua&countryId=152&page=2&pageSize=12&languageId=1&includeReviewedTranslations="
            + (!enabled).ToString().ToLowerInvariant() + (locale is null ? "" : "&locale=" + locale));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var result = await response.Content.ReadFromJsonAsync<FundingDiscoveryPage>();
        Assert.Equal(enabled && locale is not null ? "Traducido" : "Original", result!.Items[0].Title);
        Assert.Equal(classification, result.Items[0].Classification);
        Assert.Equal("AUD", result.Items[0].Currency);
        Assert.Equal(id, result.Items[0].Id);
        Assert.Equal(2, result.Page);
        Assert.Equal("agua", repository.Filters!.Query);
        Assert.Equal((short)152, repository.Filters.CountryId);
        Assert.Equal((short)1, repository.Filters.LanguageId);
        Assert.Equal(enabled, repository.IncludeReviewedTranslations);
        Assert.Equal(enabled && locale is not null ? 1 : 0, translations.Calls);
        Assert.Equal(!enabled && locale is null, response.Headers.CacheControl!.Public);
    }

    private sealed class SummaryRepository : IFundingTranslationRepository
    {
        public int Calls { get; private set; }
        public Task<IReadOnlyList<FundingSummaryTranslation>> GetPublishedSummariesAsync(IReadOnlyList<FundingTranslationReference> references, string language, CancellationToken token)
        {
            Calls++;
            Assert.Equal(5, Assert.Single(references).SourceContentVersion);
            return Task.FromResult<IReadOnlyList<FundingSummaryTranslation>>([new(references[0].OpportunityId, language, 5, 1, true, "Traducido", "Resumen")]);
        }
        public Task<FundingTranslation?> GetAdminAsync(Guid actor, Guid id, string language, CancellationToken token) => throw new NotSupportedException();
        public Task<FundingTranslation?> GetPublishedAsync(Guid id, string language, int version, CancellationToken token) => throw new NotSupportedException();
        public Task<FundingTranslation> SaveAsync(Guid actor, Guid id, string language, FundingTranslationWrite data, byte[] version, CancellationToken token) => throw new NotSupportedException();
    }

    [Theory]
    [InlineData("?funderKind=1&requiresConsortium=false&languageId=1", 200)]
    [InlineData("?page=0", 400)]
    [InlineData("?minimumAmount=1", 400)]
    [InlineData("?funderKind=7", 400)]
    [InlineData("?closingFrom=2027-02-01&closingTo=2027-01-01", 400)]
    [InlineData("?locale=fr", 400)]
    [InlineData("?locale=es&locale=en", 400)]
    public async Task Public_filters_are_bound_and_validated_before_storage(string query, int status)
    {
        var repository = new Repository();
        await using var app = factory.WithWebHostBuilder(builder => builder.ConfigureTestServices(services =>
        { services.RemoveAll<IFundingDiscoveryRepository>(); services.AddSingleton<IFundingDiscoveryRepository>(repository); }));
        using var client = app.CreateClient();
        using var response = await client.GetAsync("/api/v1/funding-discovery" + query);
        Assert.Equal(status, (int)response.StatusCode);
        Assert.Equal(status == 200 ? 1 : 0, repository.Reads);
        if (status == 200) { Assert.False(repository.Filters!.RequiresConsortium); Assert.Equal((short)1, repository.Filters.LanguageId); Assert.True(response.Headers.CacheControl!.Public); }
    }
    [Theory]
    [InlineData(null, false, true, 401)]
    [InlineData("Professional", true, true, 403)]
    [InlineData("Admin", false, true, 403)]
    [InlineData("Admin", true, false, 428)]
    [InlineData("Admin", true, true, 200)]
    public async Task Confirming_requires_admin_mfa_concurrency_and_idempotency(string? role, bool mfa, bool headers, int status)
    {
        var repository = new Repository();
        await using var app = factory.WithWebHostBuilder(builder => builder.ConfigureTestServices(services =>
        { services.RemoveAll<IFundingDiscoveryRepository>(); services.AddSingleton<IFundingDiscoveryRepository>(repository); }));
        using var client = app.CreateClient();
        if (role is not null)
        {
            var now = DateTimeOffset.UtcNow;
            var actor = Guid.NewGuid().ToString();
            var token = new JwtSecurityToken("https://testing.fundingplatform.local", "FundingPlatform.Tests",
                [new(JwtRegisteredClaimNames.Sub, actor), new(ClaimTypes.NameIdentifier, actor), new(ClaimTypes.Role, role), new("auth_level", "full"), new("amr", mfa ? "mfa" : "pwd"), new("auth_time", now.ToUnixTimeSeconds().ToString())],
                now.AddMinutes(-1).UtcDateTime, now.AddMinutes(10).UtcDateTime, new SigningCredentials(new SymmetricSecurityKey(new byte[64]), SecurityAlgorithms.HmacSha512));
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", new JwtSecurityTokenHandler().WriteToken(token));
        }
        if (headers) { client.DefaultRequestHeaders.TryAddWithoutValidation("If-None-Match", "*"); client.DefaultRequestHeaders.Add("Idempotency-Key", "discovery-review-123456789"); }
        using var response = await client.PutAsJsonAsync("/api/v1/admin/funding-discovery/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", new FundingDiscoveryReview(1,
            new(1, null, null, "https://official.example/fund", new(PartnerGeographyScope.Specific, [826], ["EU"], PartnerGeographyCatalog.Version))));
        Assert.Equal((HttpStatusCode)status, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        Assert.Equal(status == 200 ? 1 : 0, repository.Writes);
    }

    [Theory]
    [InlineData("{\"scope\":2,\"countryIds\":[],\"regionCodes\":[]}")]
    [InlineData("{\"scope\":1,\"countryIds\":[250],\"regionCodes\":[]}")]
    [InlineData("{\"scope\":2,\"countryIds\":null,\"regionCodes\":[]}")]
    [InlineData("{\"scope\":2,\"countryIds\":[250,250],\"regionCodes\":[]}")]
    [InlineData("{\"scope\":2,\"countryIds\":[],\"regionCodes\":[\"Schengen\"]}")]
    [InlineData("{\"scope\":2,\"countryIds\":[],\"regionCodes\":[\"EU\"],\"catalogVersion\":\"old\"}")]
    public async Task Malformed_partner_geography_never_reaches_storage(string geography)
    {
        var repository = new Repository();
        await using var app = factory.WithWebHostBuilder(builder => builder.ConfigureTestServices(services =>
        { services.RemoveAll<IFundingDiscoveryRepository>(); services.AddSingleton<IFundingDiscoveryRepository>(repository); }));
        using var client = app.CreateClient();
        var actor = Guid.NewGuid().ToString(); var now = DateTimeOffset.UtcNow;
        var jwt = new JwtSecurityToken("https://testing.fundingplatform.local", "FundingPlatform.Tests",
            [new(JwtRegisteredClaimNames.Sub, actor), new(ClaimTypes.NameIdentifier, actor), new(ClaimTypes.Role, "Admin"), new("auth_level", "full"),
                new("amr", "mfa"), new("auth_time", now.ToUnixTimeSeconds().ToString())], now.AddMinutes(-1).UtcDateTime, now.AddMinutes(10).UtcDateTime,
            new SigningCredentials(new SymmetricSecurityKey(new byte[64]), SecurityAlgorithms.HmacSha512));
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", new JwtSecurityTokenHandler().WriteToken(jwt));
        client.DefaultRequestHeaders.TryAddWithoutValidation("If-None-Match", "*"); client.DefaultRequestHeaders.Add("Idempotency-Key", "geography-invalid-123456789");
        using var body = new StringContent("{\"contentVersion\":1,\"data\":{\"funderKind\":1,\"evidenceUrl\":\"https://example.invalid/terms\",\"partnerGeography\":" + geography + "}}", System.Text.Encoding.UTF8, "application/json");
        using var response = await client.PutAsync("/api/v1/admin/funding-discovery/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", body);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode); Assert.Equal(0, repository.Writes);
    }
    private sealed class Repository : IFundingDiscoveryRepository
    {
        public int Reads, Writes; public FundingDiscoveryFilters? Filters;
        public bool IncludeReviewedTranslations;
        public IReadOnlyList<FundingDiscoveryItem> Items { get; init; } = [];
        public Task<FundingDiscoveryPage> SearchAsync(FundingDiscoveryFilters filters, CancellationToken token, bool includeReviewedTranslations = false) { Reads++; Filters = filters; IncludeReviewedTranslations = includeReviewedTranslations; return Task.FromResult(new FundingDiscoveryPage(Items, Items.Count, filters.Page, filters.PageSize)); }
        public Task<FundingDiscoveryAdmin?> GetAsync(Guid actor, Guid id, CancellationToken token) => Task.FromResult<FundingDiscoveryAdmin?>(null);
        public Task<CollaborationWriteResult> ReviewAsync(Guid actor, Guid id, FundingDiscoveryReview data, byte[]? version, byte[] keyHash, byte[] requestHash, CancellationToken token) { Writes++; return Task.FromResult(new CollaborationWriteResult(id, "\"0102030405060708\"", false)); }
    }
}
