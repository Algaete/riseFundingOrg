using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace FundingPlatform.IntegrationTests;

public sealed partial class FundingEditorialEndpointTests
{
    private readonly FakeFunderRepository workspaceFunders = new();
    private readonly FakeOpportunityEditorialRepository workspaceOpportunities = new();

    [Theory]
    [InlineData("funders")]
    [InlineData("funding-opportunities")]
    [InlineData("funding-sources")]
    public async Task Workspace_rejects_anonymous_sessions(string area)
    {
        using var result = await client.GetAsync($"/api/v1/funder-workspace/{area}");
        Assert.Equal(HttpStatusCode.Unauthorized, result.StatusCode);
        Assert.Equal(0, workspaceFunders.Calls);
    }

    [Fact]
    public async Task Ordinary_member_uses_only_owner_scoped_repository()
    {
        using var request = AuthenticatedRequest(HttpMethod.Get, "/api/v1/funder-workspace/funders", "Professional");
        using var result = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, result.StatusCode);
        Assert.Equal(1, workspaceFunders.Calls);
        Assert.Equal(UserId, workspaceFunders.LastAdminUserId);
        Assert.Equal(0, funders.Calls);
        Assert.Contains("no-store", result.Headers.CacheControl!.ToString());
    }

    [Fact]
    public async Task Owner_create_stays_draft_and_returns_workspace_location()
    {
        using var request = AuthenticatedRequest(HttpMethod.Post, "/api/v1/funder-workspace/funders", "Professional");
        request.Headers.TryAddWithoutValidation("Idempotency-Key", "owner-create-profile-0001");
        request.Content = JsonContent.Create(new { name = "Fundación propia", websiteUrl = "https://example.invalid", countryId = 152 });
        using var result = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Created, result.StatusCode);
        Assert.Equal($"/api/v1/funder-workspace/funders/{FunderId:D}", result.Headers.Location!.ToString());
        using var body = JsonDocument.Parse(await result.Content.ReadAsStringAsync());
        Assert.Equal(0, body.RootElement.GetProperty("publicationStatus").GetInt32());
        Assert.Equal(1, workspaceFunders.CreateCalls);
        Assert.Equal(UserId, workspaceFunders.LastAdminUserId);
        Assert.Equal(0, funders.CreateCalls);
    }

    [Fact]
    public async Task Missing_owner_concurrency_headers_prevent_writes()
    {
        using var request = AuthenticatedRequest(HttpMethod.Put, $"/api/v1/funder-workspace/funders/{FunderId:D}", "Professional");
        request.Content = JsonContent.Create(new { name = "Fundación propia" });
        using var result = await client.SendAsync(request);
        Assert.Equal((HttpStatusCode)428, result.StatusCode);
        Assert.Equal(0, workspaceFunders.UpdateCalls);
    }

    [Fact]
    public async Task Database_ownership_denial_never_falls_back_to_admin_repository()
    {
        workspaceFunders.DenyAccess = true;
        using var request = AuthenticatedRequest(HttpMethod.Get, $"/api/v1/funder-workspace/funders/{FunderId:D}", "Professional");
        using var result = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Forbidden, result.StatusCode);
        Assert.Equal(0, funders.Calls);
        Assert.DoesNotContain("Workspace owner", await result.Content.ReadAsStringAsync());
    }

    [Theory]
    [InlineData("funders")]
    [InlineData("funding-opportunities")]
    public async Task Owner_has_no_review_endpoint_and_cannot_use_admin_review(string area)
    {
        using var owner = AuthenticatedRequest(HttpMethod.Post, $"/api/v1/funder-workspace/{area}/{FunderId:D}/reviews", "Professional");
        owner.Content = JsonContent.Create(new { decision = "approve" });
        using var ownerResult = await client.SendAsync(owner);
        Assert.Equal(HttpStatusCode.NotFound, ownerResult.StatusCode);
        using var admin = AuthenticatedRequest(HttpMethod.Post, $"/api/v1/admin/{area}/{FunderId:D}/reviews", "Professional");
        admin.Content = JsonContent.Create(new { decision = "approve" });
        using var adminResult = await client.SendAsync(admin);
        Assert.Equal(HttpStatusCode.Forbidden, adminResult.StatusCode);
    }
}
