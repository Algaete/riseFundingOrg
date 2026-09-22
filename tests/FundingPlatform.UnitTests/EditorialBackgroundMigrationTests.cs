using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class EditorialBackgroundMigrationTests
{
    [Theory]
    [InlineData(54)]
    [InlineData(55)]
    public void Migration_and_transactional_smoke_parse_as_Azure_SQL(int sequence)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root).Single(s => s.Sequence == sequence);
        var smoke = SqlScriptCatalog.DiscoverTests(root).Single(s => s.Sequence == sequence);
        foreach (var batch in migration.Batches.Concat(smoke.Batches))
        {
            using var reader = new StringReader(batch);
            _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(reader, out var errors);
            Assert.True(errors.Count == 0, string.Join("; ", errors.Select(e => $"{e.Line}: {e.Message}")));
        }
        var sql = File.ReadAllText(Path.Combine(root, "database", "Migrations", migration.FileName));
        Assert.DoesNotContain("GRANT ", sql);
        Assert.DoesNotContain("DISABLE TRIGGER", sql);
        if (sequence == 54)
        {
            Assert.Contains("Code = N'OTHER'", sql);
            Assert.Contains("@OtherCategoryDescription NVARCHAR(MAX)", sql); // validate before column truncation
            Assert.Contains("DATALENGTH(@OtherCategoryDescription) > 400", sql);
            Assert.Contains("OtherCategoryDescription = @OtherCategoryDescription", sql);
            Assert.Contains("Other category must be selected, specified and match its version snapshot", sql);
            Assert.Contains("FundingPlatform_fn_AdminAccessState", sql);
            Assert.Contains("FundingPlatform_usp_FunderWorkspace_Assert", sql);
            Assert.Contains("FundingPlatform_FundingOpportunityVersions", sql);
            Assert.Contains("@ExpectedRowVersion", sql);
            Assert.Contains("@IdempotencyKeyHash", sql);
            Assert.Contains("FundingPlatform_ifn_FundingOpportunityPublicReady()", sql);
        }
        else
        {
            Assert.Contains("Active organization administrator membership is required", sql);
            Assert.Contains("Only draft or rejected project content can be edited", sql);
            Assert.Contains("WHERE Id = @ProjectId AND RowVersion = @ExpectedRowVersion", sql);
            Assert.Contains("Project enrichment must match its version snapshot", sql);
            Assert.Contains("Legacy update cannot erase project background", sql);
            Assert.Contains("FundingPlatform_fn_ProjectBackgroundIsValid(JSON_QUERY(@EnrichmentJson", sql);
            Assert.Contains("DATALENGTH([value]) > 6000", sql);
            Assert.Contains("ROUND(TRY_CONVERT", sql);
            Assert.Contains("FundingPlatform_ifn_ProjectMarketplaceReady()", sql);
            Assert.Contains("AS background", sql);
        }
        var smokeSql = File.ReadAllText(Path.Combine(root, "database", "Tests", smoke.FileName));
        Assert.Contains("ROLLBACK TRANSACTION", smokeSql);
        Assert.Contains("example.invalid", smokeSql);
    }
}
