using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;
public sealed class FundingDiscoveryTests
{
    [Theory]
    [InlineData(0, null, 1)]
    [InlineData(25, "USD", 0)]
    [InlineData(-1, "USD", 1)]
    public void Amounts_require_currency_and_valid_bounds(decimal minimum, string? currency, int errors)
        => Assert.Equal(errors, FundingDiscoveryRules.Validate(new FundingDiscoveryFilters(MinimumAmount: minimum, Currency: currency)).Count);
    [Fact]
    public void Unknown_is_not_no_and_review_needs_evidence()
    {
        Assert.Empty(FundingDiscoveryRules.Validate(new FundingDiscoveryReview(1, new(null, null, null, "https://official.example/fund"))));
        Assert.NotEmpty(FundingDiscoveryRules.Validate(new FundingDiscoveryReview(1, new(7, false, false, "https://official.example/fund"))));
        Assert.NotEmpty(FundingDiscoveryRules.Validate(new FundingDiscoveryReview(1, new(1, false, false, null))));
        Assert.NotEmpty(FundingDiscoveryRules.Validate(new FundingDiscoveryFilters(ClosingFrom: new(2027, 2, 1), ClosingTo: new(2027, 1, 1))));
    }
    [Fact]
    public void Classification_is_admin_confirmed_version_bound_audited_and_filters_before_paging()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var script = SqlScriptCatalog.DiscoverMigrations(root).Single(s => s.Sequence == 45);
        foreach (var batch in script.Batches)
        {
            _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(new StringReader(batch), out var errors);
            Assert.True(errors.Count == 0, string.Join("; ", errors.Select(e => e.Message)));
        }
        var sql = string.Join("\n", script.Batches);
        Assert.Contains("metadata.ContentVersion = p.ContentVersion", sql);
        Assert.Contains("FundingPlatform_ifn_FundingOpportunityPublicReady()", sql);
        Assert.Contains("FundingPlatform_usp_AdminActor_Lock", sql);
        Assert.Contains("IF @PreviousHash <> @RequestHash", sql);
        Assert.Contains("@PreviousVersion <> @ExpectedVersion", sql);
        Assert.Contains("LanguageId = @Language", sql);
        Assert.Contains("INSERT dbo.FundingPlatform_FundingDiscoveryReviews", sql);
        Assert.DoesNotContain("SET PublicationStatus", sql);
        Assert.DoesNotContain("GRANT SELECT", sql);
    }
}
