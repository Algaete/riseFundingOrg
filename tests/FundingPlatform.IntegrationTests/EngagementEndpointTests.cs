using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using FundingPlatform.Application.Engagement;
using FundingPlatform.Application.Stories;
using FundingPlatform.Core.Engagement;
using FundingPlatform.Core.Stories;
using FundingPlatform.Infrastructure.Notifications;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;

public sealed class EngagementEndpointTests(ApiFactory factory) : IClassFixture<ApiFactory>
{
    private static readonly Guid Organization = Guid.NewGuid(), StoryId = Guid.NewGuid(), Actor = Guid.NewGuid();
    private static string Own => $"/api/v1/organizations/{Organization}/stories";
    private static StoryWrite Draft => new(0, new("Relato", null, "Un relato de trabajo con la comunidad.", "beneficiaries", null, null, null, null, true));
    private static InquiryInput Input => new(Guid.NewGuid(), "Ana", "ana@example.invalid", null, 152, "funding", null, null, null, null, "Necesitamos ayuda para nuestro proyecto.", true);
    private Microsoft.AspNetCore.Mvc.Testing.WebApplicationFactory<Program> App(Repository repo) => factory.WithWebHostBuilder(b => b.ConfigureTestServices(s =>
    {
        s.RemoveAll<IStoryRepository>(); s.RemoveAll<IInquiryRepository>(); s.RemoveAll<IInquiryTeamNotifier>();
        s.AddSingleton<IStoryRepository>(repo); s.AddSingleton<IInquiryRepository>(repo); s.AddSingleton<IInquiryTeamNotifier, DisabledInquiryTeamNotifier>();
    }));
    private static void Login(HttpClient client, string role = "OrganizationOwner", bool mfa = false)
    {
        var now = DateTimeOffset.UtcNow;
        var jwt = new JwtSecurityToken("https://testing.fundingplatform.local", "FundingPlatform.Tests",
            [new(JwtRegisteredClaimNames.Sub, Actor.ToString()), new(ClaimTypes.NameIdentifier, Actor.ToString()), new(ClaimTypes.Role, role), new("auth_level", "full"), new("amr", mfa ? "mfa" : "pwd"), new("auth_time", now.ToUnixTimeSeconds().ToString())],
            now.AddMinutes(-1).UtcDateTime, now.AddMinutes(10).UtcDateTime, new SigningCredentials(new SymmetricSecurityKey(new byte[64]), SecurityAlgorithms.HmacSha512));
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", new JwtSecurityTokenHandler().WriteToken(jwt));
    }
    [Theory]
    [InlineData(false)][InlineData(true)]
    public async Task Public_stories_read_only_public_projection_and_preserve_filters(bool nullItems)
    {
        var repo = new Repository { NullItems = nullItems }; await using var app = App(repo); using var client = app.CreateClient();
        using var response = await client.GetAsync($"/api/v1/stories?organizationId={Organization}&page=2");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode); Assert.Null(repo.Actor);
        Assert.Equal(Organization, repo.Organization); Assert.Equal(2, repo.Page);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(JsonValueKind.Array, body.RootElement.GetProperty("items").ValueKind);
        using var missing = await client.GetAsync($"/api/v1/stories/{StoryId}"); Assert.Equal(HttpStatusCode.NotFound, missing.StatusCode);
    }
    [Fact]
    public async Task Empty_private_inbox_returns_an_array_for_null_sql_items()
    {
        await using var app = App(new Repository { NullItems = true }); using var client = app.CreateClient(); Login(client, "Admin", true);
        using var response = await client.GetAsync("/api/v1/admin/inquiries");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(JsonValueKind.Array, body.RootElement.GetProperty("items").ValueKind);
    }
    [Fact]
    public async Task Anonymous_cannot_access_own_stories_or_mutate_them()
    {
        var repo = new Repository(); await using var app = App(repo); using var client = app.CreateClient();
        using var get = await client.GetAsync(Own); Assert.Equal(HttpStatusCode.Unauthorized, get.StatusCode);
        using var put = await client.PutAsJsonAsync($"{Own}/{StoryId}", Draft); Assert.Equal(HttpStatusCode.Unauthorized, put.StatusCode);
        using var publish = await client.PostAsJsonAsync($"{Own}/{StoryId}/publication", new StoryPublication(1, true, true, true));
        Assert.Equal(HttpStatusCode.Unauthorized, publish.StatusCode); Assert.Equal(0, repo.Writes);
    }
    [Theory]
    [InlineData(null, 204)][InlineData(56120, 404)][InlineData(56121, 409)][InlineData(56122, 422)]
    public async Task Draft_save_passes_authenticated_actor_and_normalized_content(int? error, int status)
    {
        var repo = new Repository { Error = error }; await using var app = App(repo); using var client = app.CreateClient(); Login(client);
        using var response = await client.PutAsJsonAsync($"{Own}/{StoryId}", Draft);
        Assert.Equal(status, (int)response.StatusCode); Assert.Equal(Actor, repo.Actor); Assert.Equal(Organization, repo.Organization);
        Assert.Empty(repo.StoryWrite!.Content!.CategoryIds!); Assert.DoesNotContain("private error", await response.Content.ReadAsStringAsync());
    }
    [Theory]
    [InlineData(0, true, true, 400)][InlineData(1, true, false, 400)][InlineData(1, false, false, 204)][InlineData(1, true, true, 204)]
    public async Task Publication_requires_revision_and_rights(int revision, bool publish, bool rights, int status)
    {
        var repo = new Repository(); await using var app = App(repo); using var client = app.CreateClient(); Login(client);
        using var response = await client.PostAsJsonAsync($"{Own}/{StoryId}/publication", new StoryPublication(revision, publish, rights, false));
        Assert.Equal(status, (int)response.StatusCode); Assert.Equal(status == 204 ? 1 : 0, repo.Writes);
    }
    [Fact]
    public async Task Contact_is_anonymous_but_receipt_never_returns_private_request_data()
    {
        var repo = new Repository(); await using var app = App(repo); using var client = app.CreateClient();
        using var response = await client.PostAsJsonAsync("/api/v1/inquiries", Input);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode); Assert.Equal(1, repo.Writes);
        var body = await response.Content.ReadAsStringAsync(); Assert.Contains("requestId", body); Assert.DoesNotContain("ana@", body);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
    }
    [Theory]
    [InlineData(false, null)][InlineData(true, "bot")]
    public async Task Missing_consent_and_honeypot_do_not_reach_storage(bool consent, string? website)
    {
        var repo = new Repository(); await using var app = App(repo); using var client = app.CreateClient();
        using var response = await client.PostAsJsonAsync("/api/v1/inquiries", Input with { ConsentToContact = consent, Website = website });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode); Assert.Equal(0, repo.Writes);
    }
    [Theory]
    [InlineData(null, false, 401)][InlineData("OrganizationOwner", true, 403)][InlineData("Admin", false, 403)][InlineData("Admin", true, 200)]
    public async Task Private_inbox_requires_platform_admin_with_mfa(string? role, bool mfa, int expected)
    {
        var repo = new Repository(); await using var app = App(repo); using var client = app.CreateClient(); if (role != null) Login(client, role, mfa);
        using var response = await client.GetAsync("/api/v1/admin/inquiries"); Assert.Equal(expected, (int)response.StatusCode);
        Assert.Equal(expected == 200 ? 1 : 0, repo.InquiryReads);
        if (expected == 200) Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
    }
    [Theory]
    [InlineData(56130, 409)][InlineData(56131, 429)][InlineData(56132, 422)]
    public async Task Contact_maps_sql_conflicts_limits_without_leaking_details(int error, int status)
    {
        var repo = new Repository { Error = error }; await using var app = App(repo); using var client = app.CreateClient();
        using var response = await client.PostAsJsonAsync("/api/v1/inquiries", Input);
        Assert.Equal(status, (int)response.StatusCode); Assert.DoesNotContain("private error", await response.Content.ReadAsStringAsync());
    }
    [Fact]
    public async Task Services_have_no_payment_or_fixed_price_contract()
    {
        await using var app = App(new Repository()); using var client = app.CreateClient();
        var codes = await client.GetFromJsonAsync<string[]>("/api/v1/services"); Assert.Equal(ProfessionalServices.Codes, codes);
        using var response = await client.PostAsJsonAsync("/api/v1/donations", new { amount = 10 }); Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }
    private sealed class Repository : IStoryRepository, IInquiryRepository
    {
        public bool NullItems;
        public int? Error; public int Writes, Page, InquiryReads; public Guid? Actor, Organization; public StoryWrite? StoryWrite;
        public Task<StoryPage> ListAsync(Guid? actor, Guid? organization, Guid? project, Guid? story, int page, CancellationToken token)
        { Actor = actor; Organization = organization; Page = page; return Task.FromResult(new StoryPage(NullItems ? null! : [], 0, page)); }
        public Task SaveAsync(Guid actor, Guid organization, Guid story, StoryWrite data, CancellationToken token)
        { Actor = actor; Organization = organization; StoryWrite = data; Writes++; if (Error is int e) throw new StoryDataException(e, new Exception("private error")); return Task.CompletedTask; }
        public Task PublishAsync(Guid actor, Guid organization, Guid story, StoryPublication data, CancellationToken token) { Writes++; return Task.CompletedTask; }
        public Task<InquiryReceipt> CaptureAsync(InquiryInput data, byte[] hash, CancellationToken token)
        { Writes++; if (Error is int e) throw new InquiryDataException(e, new Exception("private error")); return Task.FromResult(new InquiryReceipt(data.RequestId, false)); }
        public Task<InquiryPage> ListAsync(Guid actor, int page, CancellationToken token) { InquiryReads++; return Task.FromResult(new InquiryPage(NullItems ? null! : [], 0, page)); }
        public Task ReviewAsync(Guid actor, Guid id, InquiryReview data, CancellationToken token) => Task.CompletedTask;
        public Task<Inquiry?> ClaimNotificationAsync(Guid id, CancellationToken token) => throw new NotSupportedException();
        public Task FinishNotificationAsync(Guid id, bool accepted, CancellationToken token) => throw new NotSupportedException();
    }
}
