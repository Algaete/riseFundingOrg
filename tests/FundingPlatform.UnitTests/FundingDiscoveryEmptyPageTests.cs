using System.Text.Json;
using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.UnitTests;

public sealed class FundingDiscoveryEmptyPageTests
{
    [Theory]
    [InlineData("{\"totalCount\":0,\"page\":1,\"pageSize\":20}")]
    [InlineData("{\"items\":null,\"totalCount\":0,\"page\":1,\"pageSize\":20}")]
    [InlineData("{\"items\":[],\"totalCount\":0,\"page\":1,\"pageSize\":20}")]
    public void EmptySqlProjectionKeepsAnArrayForLocalizationAndPublicClients(string sqlJson)
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        var page = JsonSerializer.Deserialize<FundingDiscoveryPage>(sqlJson, options)!;
        Assert.Empty(page.Items);
        using var output = JsonDocument.Parse(JsonSerializer.Serialize(page, options));
        Assert.Equal(JsonValueKind.Array, output.RootElement.GetProperty("items").ValueKind);
        Assert.Equal(0, page.TotalCount);
    }
}
