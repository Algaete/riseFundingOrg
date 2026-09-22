using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class FundingTranslationSqlVerifierTests
{
    [Fact]
    public void Fixtures_parse_and_require_an_existing_transaction_without_committing()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var sql = File.ReadAllText(Path.Combine(root, "database", "Fixtures", "funding_translation_contract.sql"));
        using var reader = new StringReader(sql);
        new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(reader, out var errors);
        Assert.True(errors.Count == 0, string.Join("; ", errors.Select(x => x.Message)));
        Assert.Contains("IF @@TRANCOUNT = 0 THROW", sql);
        Assert.DoesNotContain("COMMIT", sql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("DELETE", sql, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("@Tag", sql);
        Assert.Contains("@example.invalid", sql);
        foreach (var scenario in new[] { "title", "summary", "draft", "stale", "inactive" })
            Assert.Contains("N'" + scenario + "'", sql);
    }

    [Fact]
    public void Inactive_fixtures_preserve_the_database_archive_constraint()
    {
        var root = SolutionRootLocator.Find();
        var fixture = File.ReadAllText(Path.Combine(root, "database", "Fixtures", "funding_translation_contract.sql"));
        Assert.Contains("CASE WHEN @Active=0 THEN 4 ELSE 2 END", fixture);
        var smoke = string.Join('\n', SqlScriptCatalog.DiscoverTests(root).Single(s => s.Sequence == 58).Batches);
        Assert.Contains("SET IsActive = 0, PublicationStatus = 4 WHERE Id = @Id", smoke);
    }

    [Fact]
    public void Real_contract_verifier_is_wired_only_to_transactional_test_hook()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var program = File.ReadAllText(Path.Combine(root, "tools", "FundingPlatform.DatabaseMigrator", "Program.cs"));
        var verifier = File.ReadAllText(Path.Combine(root, "src", "FundingPlatform.Infrastructure", "Persistence", "Migrations", "FundingTranslationSqlVerifier.cs"));
        Assert.Contains("migration.Sequence == 58", program);
        Assert.Contains("FundingTranslationSqlVerifier.VerifyAsync", program);
        Assert.Contains("transaction.Connection != connection", verifier);
        Assert.Contains("QueryMultipleAsync", verifier);
        Assert.Contains("ReadSingleAsync<long>", verifier);
        Assert.Contains("ReadAsync<SummaryRow>", verifier);
        Assert.Contains("ReadAsync<FundingSummaryTranslation>", verifier);
        Assert.Contains("!result.IsConsumed", verifier);
        Assert.DoesNotContain("CommitAsync", verifier);
        Assert.DoesNotContain("CreateConnection", verifier);
    }
}
