using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Core.Identity;

namespace FundingPlatform.IntegrationTests;

public sealed partial class FundingEditorialEndpointTests
{
    private readonly FakeTranslationRepository translations = new();
    private static string TranslationPath => $"/api/v1/admin/funding-opportunities/{OpportunityId}/translations/es";

    [Fact]
    public async Task Translation_requires_authentication_role_and_mfa()
    {
        using var anonymous = await client.GetAsync(TranslationPath);
        Assert.Equal(HttpStatusCode.Unauthorized, anonymous.StatusCode);
        using var request = AuthenticatedRequest(HttpMethod.Get, TranslationPath, PlatformRoles.Admin, false);
        using var noMfa = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Forbidden, noMfa.StatusCode);
        using var memberRequest = AuthenticatedRequest(HttpMethod.Get, TranslationPath, "OrganizationOwner", true);
        using var member = await client.SendAsync(memberRequest);
        Assert.Equal(HttpStatusCode.Forbidden, member.StatusCode);
        Assert.Equal(0, translations.Calls);
    }

    [Theory]
    [InlineData(null, 3, false, 428)]
    [InlineData(CurrentETag, 2, false, 412)]
    [InlineData(NextETag, 3, false, 412)]
    [InlineData(CurrentETag, 3, true, 400)]
    public async Task Translation_rejects_missing_or_stale_versions_and_incomplete_review(string? eTag, int version, bool reviewed, int status)
    {
        opportunities.Details = TranslationOriginal();
        using var request = TranslationRequest(eTag, new(version, 0, reviewed, new("Título")));
        using var response = await client.SendAsync(request);
        Assert.Equal(status, (int)response.StatusCode);
        Assert.Equal(0, translations.Calls);
    }

    [Fact]
    public async Task Translation_saves_normalized_complete_review_and_preserves_concurrency_conflict()
    {
        opportunities.Details = TranslationOriginal();
        using var request = TranslationRequest(CurrentETag, new(3, 0, true, new(" Título ", " Resumen ", " Descripción ")));
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(translations.Saved!.Reviewed);
        Assert.Equal("Título", translations.Saved.Text!.Title);
        Assert.Equal(Convert.FromHexString("0102030405060708"), translations.SourceVersion);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        translations.Error = 56032;
        using var repeated = TranslationRequest(CurrentETag, new(3, 0, false, new("Título")));
        using var conflict = await client.SendAsync(repeated);
        Assert.Equal(HttpStatusCode.PreconditionFailed, conflict.StatusCode);
    }

    [Fact]
    public async Task Public_detail_selects_locale_without_changing_original_and_never_reads_for_missing_fund()
    {
        publicOpportunities.Published = new(OpportunityId,"original","Original","Description","Summary","Sponsor",
            null,"https://example.invalid/apply","AUD",100,500,null,null,null,null,null,null,"Source",null,"REF",DateTimeOffset.UtcNow,100,[],3,
            OtherCategoryDescription: "Área descrita por el editor", CoverKey: "nature-v1");
        translations.Value = new("es",3,1,true,new("Traducido","Resumen","Descripción"),DateTimeOffset.UtcNow);
        using var translated = await client.GetAsync("/api/v1/funding-opportunities/original?locale=es");
        Assert.Equal(HttpStatusCode.OK, translated.StatusCode);
        using var body = JsonDocument.Parse(await translated.Content.ReadAsStringAsync());
        Assert.Equal("Traducido", body.RootElement.GetProperty("title").GetString());
        Assert.Equal("AUD", body.RootElement.GetProperty("currency").GetString());
        Assert.Equal("nature-v1", body.RootElement.GetProperty("coverKey").GetString());
        Assert.Equal("Área descrita por el editor", body.RootElement.GetProperty("otherCategoryDescription").GetString());
        Assert.Equal("translated", body.RootElement.GetProperty("localization").GetProperty("status").GetString());
        Assert.Contains("no-store", translated.Headers.CacheControl?.ToString());
        using var original = await client.GetAsync("/api/v1/funding-opportunities/original");
        using var originalBody = JsonDocument.Parse(await original.Content.ReadAsStringAsync());
        Assert.Equal("Original", originalBody.RootElement.GetProperty("title").GetString());
        Assert.Equal(1, translations.Calls);
        publicOpportunities.Published = null;
        using var missing = await client.GetAsync("/api/v1/funding-opportunities/original?locale=es");
        Assert.Equal(HttpStatusCode.NotFound, missing.StatusCode);
        using var invalid = await client.GetAsync("/api/v1/funding-opportunities/original?locale=xx");
        Assert.Equal(HttpStatusCode.BadRequest, invalid.StatusCode);
        Assert.Equal(1, translations.Calls);
    }

    private static HttpRequestMessage TranslationRequest(string? eTag, FundingTranslationWrite data)
    {
        var request = AuthenticatedRequest(HttpMethod.Put, TranslationPath, PlatformRoles.Admin, true);
        if (eTag != null) request.Headers.TryAddWithoutValidation("If-Match", eTag);
        request.Content = JsonContent.Create(data);
        return request;
    }
    private static FundingOpportunityAdminDetails TranslationOriginal()
    {
        var data = new FundingOpportunityEditorialData("Original","Summary","Description","Sponsor",null,null,[],1,null,"https://example.invalid",null,null,
            null,null,null,FundingAmountStatus.Unknown,null,null,null,null,FundingDeadlineType.Unknown,FundingDeadlinePrecision.Unknown,
            null,null,null,null,null,null,null,null,null,null,null,null,null,FundingGeographicScope.Unknown,FundingRemoteApplication.Unknown,null,[],[],[],[],[]);
        return new(OpportunityId,"original",data,FundingPublicationStatus.Draft,true,3,100,DateTimeOffset.UtcNow,DateTimeOffset.UtcNow,
            Convert.FromHexString("0102030405060708"),[],[],[],null,null,null,null,null);
    }
    private sealed class FakeTranslationRepository : IFundingTranslationRepository
    {
        public int SummaryCalls { get; private set; }
        public IReadOnlyList<FundingTranslationReference>? SummaryReferences { get; private set; }
        public IReadOnlyList<FundingSummaryTranslation> Summaries { get; set; } = [];
        public Task<IReadOnlyList<FundingSummaryTranslation>> GetPublishedSummariesAsync(IReadOnlyList<FundingTranslationReference> references, string language, CancellationToken token)
        { SummaryCalls++; SummaryReferences = references; return Task.FromResult(Summaries); }
        public int Calls { get; private set; }
        public FundingTranslation? Value { get; set; }
        public FundingTranslationWrite? Saved { get; private set; }
        public byte[]? SourceVersion { get; private set; }
        public int? Error { get; set; }
        public Task<FundingTranslation?> GetAdminAsync(Guid actor, Guid id, string language, CancellationToken token)
        { Calls++; return Task.FromResult(Value); }
        public Task<FundingTranslation?> GetPublishedAsync(Guid id, string language, int version, CancellationToken token)
        { Calls++; return Task.FromResult(Value); }
        public Task<FundingTranslation> SaveAsync(Guid actor, Guid id, string language, FundingTranslationWrite data, byte[] rowVersion, CancellationToken token)
        {
            Calls++; Saved = data; SourceVersion = rowVersion;
            if (Error is int code) throw new FundingTranslationDataException(code, new Exception());
            return Task.FromResult(new FundingTranslation(language,data.SourceContentVersion,data.ExpectedRevision+1,data.Reviewed,data.Text!,DateTimeOffset.UtcNow));
        }
    }
}
