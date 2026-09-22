using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class FundingTranslationSearchTests
{
    [Fact]
    public void Migration_and_rollback_smoke_parse_for_Azure_SQL()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var scripts = new[] { SqlScriptCatalog.DiscoverMigrations(root).Single(x => x.Sequence == 58),
            SqlScriptCatalog.DiscoverTests(root).Single(x => x.Sequence == 58) };
        foreach (var batch in scripts.SelectMany(x => x.Batches))
        {
            using var reader = new StringReader(batch);
            new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(reader, out var errors);
            Assert.True(errors.Count == 0, string.Join("; ", errors.Select(x => x.Message)));
        }
        Assert.Contains("ROLLBACK TRANSACTION", string.Join('\n', scripts[1].Batches));
    }

    [Fact]
    public void Shared_matching_is_current_reviewed_public_literal_and_deduplicated()
    {
        var sql = Migration();
        var function = sql[..sql.IndexOf("CREATE OR ALTER PROCEDURE", StringComparison.Ordinal)];
        foreach (var guard in new[] { "t.Reviewed = 1", "t.SourceContentVersion = o.ContentVersion",
            "t.Language IN ('es','en')", "FundingPlatform_ifn_FundingOpportunityPublicReady()",
            "normalized.Query IS NOT NULL", "GROUP BY o.Id", "Latin1_General_100_CI_AI", "ESCAPE N'~'",
            "N'%', N'~%'", "N'_', N'~_'", "N'[', N'~['", "N'~', N'~~'", "text.Title IS NOT NULL",
            "o.Summary", "text.Summary IS NOT NULL" }) Assert.Contains(guard, function);
        Assert.DoesNotContain("$.description", function);
        Assert.DoesNotContain("GRANT ", sql);
        Assert.DoesNotContain("CREATE TABLE dbo.", sql);
    }

    [Theory]
    [InlineData("FundingOpportunity_Public_List")]
    [InlineData("FundingOpportunity_OrganizationSearch")]
    [InlineData("FundingDiscovery_Search")]
    public void Every_search_is_default_off_and_matches_before_paging(string name)
    {
        var sql = Migration();
        var start = sql.IndexOf("CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_" + name, StringComparison.Ordinal);
        var next = sql.IndexOf("CREATE OR ALTER PROCEDURE", start + 1, StringComparison.Ordinal);
        var procedure = sql[start..(next < 0 ? sql.Length : next)];
        Assert.Contains("@IncludeReviewedTranslations BIT = 0", procedure);
        Assert.Contains("IF @IncludeReviewedTranslations = 1", procedure);
        Assert.True(procedure.IndexOf("FundingPlatform_ifn_FundingTranslationSearch", StringComparison.Ordinal)
            < procedure.IndexOf("OFFSET ", StringComparison.Ordinal));
        if (name.EndsWith("Public_List", StringComparison.Ordinal))
            Assert.Equal(2, procedure.Split("OR EXISTS(SELECT 1 FROM @TranslationMatches t WHERE t.FundingOpportunityId = opportunities.Id)").Length - 1);
        if (name.EndsWith("OrganizationSearch", StringComparison.Ordinal))
        {
            Assert.Contains("WITH EXECUTE AS OWNER", procedure);
            Assert.Contains("memberships.MembershipStatus = 1", procedure);
            Assert.Contains("FREETEXTTABLE", procedure);
            Assert.Contains("IF @NormalizedQuery IS NOT NULL AND @FullTextReady = 0", procedure);
            Assert.True(procedure.IndexOf("INSERT @TranslatedRanks", StringComparison.Ordinal) < procedure.IndexOf("FREETEXTTABLE", StringComparison.Ordinal));
        }
        if (name.EndsWith("Discovery_Search", StringComparison.Ordinal))
            Assert.Contains("FundingPlatform_FundingOpportunityLanguages WHERE FundingOpportunityId = p.Id AND LanguageId = @Language", procedure);
    }

    private static string Migration() => string.Join('\n', SqlScriptCatalog.DiscoverMigrations(
        SolutionRootLocator.Find(AppContext.BaseDirectory)).Single(x => x.Sequence == 58).Batches);
}
