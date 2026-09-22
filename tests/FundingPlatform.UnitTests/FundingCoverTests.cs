using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.Validation;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class FundingCoverTests
{
    [Theory]
    [InlineData(null, true)]
    [InlineData("auto", true)]
    [InlineData("nature-v1", true)]
    [InlineData("education-v1", true)]
    [InlineData("community-v1", true)]
    [InlineData("research-v1", true)]
    [InlineData("Nature-v1", false)]
    [InlineData("", false)]
    [InlineData("nature-v1 ", false)]
    [InlineData("../image.jpg", false)]
    [InlineData("https://example.invalid/photo.jpg", false)]
    [InlineData("data:image/svg+xml,abc", false)]
    [InlineData("__proto__", false)]
    public void Cover_is_a_versioned_library_key_not_a_URL(string? key, bool valid)
    {
        Assert.Equal(valid, FundingCoverRules.IsSupported(key));
        var errors = new FieldValidationErrors();
        FundingCoverRules.Validate(key, errors);
        if (valid) Assert.Empty(errors);
        else Assert.Equal("funding-cover-invalid", Assert.Single(errors.Issues["coverKey"]).Code);
    }

    [Fact]
    public void Migration_and_smoke_parse_without_changing_editorial_security_contracts()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root).Single(s => s.Sequence == 56);
        var smoke = SqlScriptCatalog.DiscoverTests(root).Single(s => s.Sequence == 56);
        foreach (var batch in migration.Batches.Concat(smoke.Batches))
        {
            using var reader = new StringReader(batch);
            _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(reader, out var errors);
            Assert.True(errors.Count == 0, string.Join("; ", errors.Select(e => $"{e.Line}: {e.Message}")));
        }
        var sql = File.ReadAllText(Path.Combine(root, "database", "Migrations", migration.FileName));
        foreach (var guard in new[] { "FundingPlatform_fn_AdminAccessState", "FundingPlatform_usp_FunderWorkspace_Assert",
            "@ExpectedRowVersion", "@IdempotencyKeyHash", "FundingPlatform_FundingOpportunityVersions",
            "WITH EXECUTE AS OWNER", "FundingPlatform_ifn_FundingOpportunityPublicReady()",
            "cover-selection-required", "@CoverKey NVARCHAR(MAX)", "$.coverKey", "DATALENGTH(@CoverKey) > 80" })
            Assert.Contains(guard, sql);
        Assert.DoesNotContain("GRANT ", sql);
        Assert.DoesNotContain("DISABLE TRIGGER", sql);
        foreach (var key in new[] { "nature-v1", "education-v1", "community-v1", "research-v1" })
        {
            Assert.True(FundingCoverRules.IsSupported(key));
            Assert.Contains($"N'{key}'", sql);
            Assert.True(File.Exists(Path.Combine(root, "frontend/funding-platform-web/public/images/funding-covers", key + ".jpg")));
        }
        var smokeSql = File.ReadAllText(Path.Combine(root, "database", "Tests", smoke.FileName));
        Assert.Contains("ROLLBACK TRANSACTION", smokeSql);
        Assert.Contains("cover-selection-required", smokeSql);
        Assert.Contains("WasReplay = 1", smokeSql);
    }
}
