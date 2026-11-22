using System.Net;
using System.Text.Json;
using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.IntegrationTests;

public sealed partial class FundingEditorialEndpointTests
{
    [Theory]
    [InlineData(0, 0)]
    [InlineData(2, 0)]
    [InlineData(1, 2)]
    public async Task Public_catalog_preserves_unknown_rolling_and_exact_deadlines(int type, int precision)
    {
        DateTimeOffset? close = precision == 2 ? DateTimeOffset.Parse("2026-12-15T17:00:00Z") : null;
        publicOpportunities.PublishedItems = [new FundingOpportunitySummary(OpportunityId, "deadline", "Deadline", null,
            "Funder", "CLP", null, 1000000, null, precision == 2 ? new DateOnly(2026, 12, 15) : null,
            "Source", null, DateTimeOffset.UtcNow, 90, DeadlineType: type, DeadlinePrecision: precision,
            CloseAtUtc: close, DeadlineTimeZoneId: precision == 2 ? "America/Santiago" : null)];
        using var response = await client.GetAsync("/api/v1/funding-opportunities");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var item = json.RootElement.GetProperty("items")[0];
        Assert.Equal(type, item.GetProperty("deadlineType").GetInt32());
        Assert.Equal(precision, item.GetProperty("deadlinePrecision").GetInt32());
        Assert.Equal(close, item.GetProperty("closeAtUtc").ValueKind == JsonValueKind.Null ? null : item.GetProperty("closeAtUtc").GetDateTimeOffset());
    }

    [Fact]
    public async Task Public_detail_returns_deadline_timezone_and_restrictions()
    {
        publicOpportunities.Published = new(OpportunityId, "deadline", "Deadline", "Description", "Summary", "Funder",
            null, null, "CLP", null, 1000000, null, new DateOnly(2026, 12, 15), "Eligibility", null, null, null,
            "Source", null, null, DateTimeOffset.UtcNow, 90, DeadlineType: 1, DeadlinePrecision: 2,
            CloseAtUtc: DateTimeOffset.Parse("2026-12-15T17:00:00Z"), DeadlineTimeZoneId: "America/Santiago",
            Restrictions: "El grupo debía estar inscrito antes del cierre del registro.");
        using var response = await client.GetAsync("/api/v1/funding-opportunities/deadline");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("America/Santiago", json.RootElement.GetProperty("deadlineTimeZoneId").GetString());
        Assert.Equal(publicOpportunities.Published.Restrictions, json.RootElement.GetProperty("restrictions").GetString());
        Assert.Equal(publicOpportunities.Published.CloseAtUtc, json.RootElement.GetProperty("closeAtUtc").GetDateTimeOffset());
    }
}
