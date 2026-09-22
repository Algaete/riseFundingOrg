using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using FundingPlatform.Core.Identity;

namespace FundingPlatform.IntegrationTests;

public sealed partial class FundingEditorialEndpointTests
{
    [Fact]
    public async Task Public_catalog_returns_cover_for_new_and_legacy_records()
    {
        var item = new FundingPlatform.Core.FundingOpportunities.FundingOpportunitySummary(OpportunityId,
            "test", "Test", null, "Funder", null, null, null, null, null, "Source", null, DateTimeOffset.UtcNow, 50,
            CoverKey: "education-v1");
        publicOpportunities.PublishedItems = [item, item with { CoverKey = null }];
        using var response = await client.GetAsync("/api/v1/funding-opportunities");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("education-v1", body.RootElement.GetProperty("items")[0].GetProperty("coverKey").GetString());
        Assert.Equal(JsonValueKind.Null, body.RootElement.GetProperty("items")[1].GetProperty("coverKey").ValueKind);
    }

    [Theory]
    [InlineData(null, 200)]
    [InlineData("auto", 200)]
    [InlineData(" nature-v1 ", 200)]
    [InlineData("education-v1", 200)]
    [InlineData("community-v1", 200)]
    [InlineData("research-v1", 200)]
    [InlineData("https://example.invalid/image.jpg", 422)]
    [InlineData("../secret", 422)]
    [InlineData("Nature-v1", 422)]
    public async Task Cover_write_validates_and_versions_the_selected_key(string? key, int status)
    {
        using var request = CoverWrite(key);
        using var response = await client.SendAsync(request);
        Assert.Equal(status, (int)response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        if (status == 200)
        {
            Assert.Equal(key?.Trim(), opportunities.LastWrittenData!.CoverKey);
            using var snapshot = JsonDocument.Parse(opportunities.LastWrittenSnapshot!);
            Assert.Equal(key?.Trim(), snapshot.RootElement.GetProperty("coverKey").GetString());
        }
        else
        {
            Assert.Equal("funding-cover-invalid", body.RootElement.GetProperty("validationIssues")
                .GetProperty("coverKey")[0].GetProperty("code").GetString());
            Assert.Null(opportunities.LastWrittenData);
        }
    }

    [Fact]
    public async Task Cover_omission_from_legacy_client_returns_actionable_field_error()
    {
        opportunities.RequestPublicationResult = opportunities.RequestPublicationResult with
        { Succeeded = false, Code = "cover-selection-required" };
        using var request = CoverWrite(null);
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("funding-cover-required", body.RootElement.GetProperty("validationIssues")
            .GetProperty("coverKey")[0].GetProperty("code").GetString());
    }

    [Fact]
    public async Task Admin_detail_returns_selected_cover_to_reopen_editor()
    {
        var original = TranslationOriginal();
        opportunities.Details = original with { Data = original.Data with { CoverKey = "research-v1" } };
        using var request = AuthenticatedRequest(HttpMethod.Get,
            $"/api/v1/admin/funding-opportunities/{OpportunityId:D}", PlatformRoles.Admin, true);
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("research-v1", body.RootElement.GetProperty("coverKey").GetString());
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
    }

    private static HttpRequestMessage CoverWrite(string? key)
    {
        var request = AuthenticatedRequest(HttpMethod.Put,
            $"/api/v1/admin/funding-opportunities/{OpportunityId:D}", PlatformRoles.Admin, true);
        request.Headers.TryAddWithoutValidation("If-Match", CurrentETag);
        request.Headers.TryAddWithoutValidation("Idempotency-Key", "cover-update-test-0001");
        request.Content = JsonContent.Create(new { title = "Fondo de prueba", sponsorName = "Fundación Prueba",
            funders = new[] { new { funderId = FunderId, role = 1 } }, fundingSourceId = 7,
            sourceUrl = "https://example.org/fund", coverKey = key });
        return request;
    }
}
