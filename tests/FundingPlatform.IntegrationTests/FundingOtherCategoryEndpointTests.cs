using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using FundingPlatform.Core.Identity;

namespace FundingPlatform.IntegrationTests;

public sealed partial class FundingEditorialEndpointTests
{
    [Theory]
    [InlineData(true, "  Economía circular  ", 200, null)]
    [InlineData(false, null, 200, null)]
    [InlineData(true, " ", 422, "funding-other-category-required")]
    [InlineData(false, "Otra área", 422, "funding-other-category-unselected")]
    public async Task Other_category_update_enforces_selection_and_persists_normalized_text(
        bool selected, string? text, int status, string? code)
    {
        using var request = AuthenticatedRequest(HttpMethod.Put,
            $"/api/v1/admin/funding-opportunities/{OpportunityId:D}", PlatformRoles.Admin, true);
        request.Headers.TryAddWithoutValidation("If-Match", CurrentETag);
        request.Headers.TryAddWithoutValidation("Idempotency-Key", "other-category-update-01");
        request.Content = JsonContent.Create(new { title = "Fondo de prueba", sponsorName = "Fundación Prueba",
            funders = new[] { new { funderId = FunderId, role = 1 } }, fundingSourceId = 7,
            sourceUrl = "https://example.org/fund", categoryIds = selected ? new[] { 16 } : new[] { 1 },
            otherCategoryDescription = text });
        using var response = await client.SendAsync(request);
        Assert.Equal(status, (int)response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        if (status == 200)
        {
            Assert.Equal(text?.Trim(), opportunities.LastWrittenData!.OtherCategoryDescription);
            using var snapshot = JsonDocument.Parse(opportunities.LastWrittenSnapshot!);
            Assert.Equal(text?.Trim(), snapshot.RootElement.GetProperty("otherCategoryDescription").GetString());
        }
        else
        {
            Assert.Equal(code, body.RootElement.GetProperty("validationIssues")
                .GetProperty("otherCategoryDescription")[0].GetProperty("code").GetString());
            Assert.Null(opportunities.LastWrittenData);
        }
    }

    [Fact]
    public async Task Admin_details_return_the_editorial_other_description_for_reopening_the_form()
    {
        var original = TranslationOriginal();
        opportunities.Details = original with { Data = original.Data with { CategoryIds = [16], OtherCategoryDescription = "Economía circular" } };
        using var request = AuthenticatedRequest(HttpMethod.Get,
            $"/api/v1/admin/funding-opportunities/{OpportunityId:D}", PlatformRoles.Admin, true);
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("Economía circular", body.RootElement.GetProperty("otherCategoryDescription").GetString());
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
    }
}
