using System.Net;
using System.Text.Json;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Application.FundingOpportunities;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace FundingPlatform.IntegrationTests;

public sealed partial class FundingEditorialEndpointTests
{
    [Theory]
    [InlineData("es", "Traducido", 1)]
    [InlineData("en", "Original", 1)]
    [InlineData(null, "Original", 0)]
    public async Task Public_page_localizes_in_one_read_preserving_identity_and_canonical_fields(string? locale, string title, int calls)
    {
        var item = new FundingOpportunitySummary(OpportunityId, "original", "Original", "Summary", "Funder",
            "AUD", 100, 200, null, new(2027,1,1), "Source", "https://example.invalid", DateTimeOffset.UtcNow, 95, "nature-v1", 3);
        publicOpportunities.PublishedItems = [item, item with { PublicId = FunderId, Slug = "fallback" }];
        translations.Summaries = [new(OpportunityId, "es", 3, 7, true, "Traducido", "Resumen")];
        using var response = await client.GetAsync("/api/v1/funding-opportunities" + (locale is null ? "" : "?locale=" + locale));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(calls, translations.SummaryCalls);
        Assert.Equal(0, translations.Calls);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var first = body.RootElement.GetProperty("items")[0];
        Assert.Equal(title, first.GetProperty("title").GetString());
        Assert.Equal(OpportunityId, first.GetProperty("publicId").GetGuid());
        Assert.Equal("original", first.GetProperty("slug").GetString());
        Assert.Equal("AUD", first.GetProperty("currency").GetString());
        Assert.Equal(200, first.GetProperty("maximumAmount").GetDecimal());
        Assert.Equal("nature-v1", first.GetProperty("coverKey").GetString());
        Assert.Equal("Original", body.RootElement.GetProperty("items")[1].GetProperty("title").GetString());
        Assert.Equal(2, body.RootElement.GetProperty("totalCount").GetInt32());
        if (locale is not null)
        {
            Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
            Assert.Equal(locale, first.GetProperty("localization").GetProperty("requestedLanguage").GetString());
            Assert.Equal("original", body.RootElement.GetProperty("items")[1].GetProperty("localization").GetProperty("status").GetString());
            Assert.Equal(2, translations.SummaryReferences!.Count);
        }
        else Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
    }

    [Theory]
    [InlineData("fr")][InlineData("es-CL")][InlineData("ES")][InlineData("es&locale=en")]
    public async Task Invalid_list_locale_is_rejected_without_reading_translations(string locale)
    {
        using var response = await client.GetAsync("/api/v1/funding-opportunities?locale=" + locale);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(0, translations.SummaryCalls);
    }

    [Theory]
    [InlineData(false, null)][InlineData(false, "es")][InlineData(false, "en")]
    [InlineData(true, null)][InlineData(true, "es")][InlineData(true, "en")]
    public async Task Public_bilingual_search_is_server_gated_and_independent_of_presentation(bool enabled, string? locale)
    {
        await using var app = application.WithWebHostBuilder(builder => builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<FundingTranslationOptions>();
            services.AddSingleton(new FundingTranslationOptions { Enabled = enabled });
        }));
        using var http = app.CreateClient();
        // This extra parameter must not be able to enable/disable the server-side feature.
        using var response = await http.GetAsync("/api/v1/funding-opportunities?query=%20educaci%C3%B3n%20&pageNumber=2&pageSize=7&includeReviewedTranslations="
            + (!enabled).ToString().ToLowerInvariant() + (locale is null ? "" : "&locale=" + locale));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(enabled, publicOpportunities.IncludeReviewedTranslations);
        Assert.Equal("educación", publicOpportunities.LastSearchQuery);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(2, body.RootElement.GetProperty("pageNumber").GetInt32());
        Assert.Equal(7, body.RootElement.GetProperty("pageSize").GetInt32());
        Assert.Equal(0, translations.SummaryCalls); // Empty page never reads translation storage.
        Assert.Equal(!enabled && locale is null, response.Headers.CacheControl!.Public);
    }
}
