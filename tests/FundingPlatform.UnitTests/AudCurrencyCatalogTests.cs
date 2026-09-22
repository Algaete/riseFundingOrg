using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class AudCurrencyCatalogTests
{
    [Fact]
    public void Migration_and_smoke_are_discoverable_valid_azure_sql()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root).Single(script => script.Sequence == 52);
        var smoke = SqlScriptCatalog.DiscoverTests(root).Single(script => script.Sequence == 52);
        Assert.Equal("aud_currency_catalog", migration.Name);
        Assert.Equal("aud_currency_catalog_smoke", smoke.Name);
        var parser = new TSql170Parser(true, SqlEngineType.SqlAzure);
        foreach (var batch in migration.Batches.Concat(smoke.Batches))
        {
            using var reader = new StringReader(batch);
            _ = parser.Parse(reader, out var errors);
            Assert.Empty(errors);
        }
    }

    [Fact]
    public void Migration_is_replay_safe_preserves_operator_decisions_and_adds_no_services_or_permissions()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var sql = File.ReadAllText(Path.Combine(root, "database", "Migrations", "052_aud_currency_catalog.sql"));
        Assert.Contains("MinorUnits <> 2", sql);
        Assert.Contains("SELECT 'AUD', N'Dólar australiano', 2", sql);
        Assert.Contains("WHERE NOT EXISTS", sql);
        Assert.DoesNotMatch(@"(?i)\b(UPDATE|DELETE|MERGE|DROP|ALTER|TRUNCATE|GRANT|COMMIT)\s+", sql);
        Assert.DoesNotContain("FundingPlatform_FundingSources", sql);
    }
}
