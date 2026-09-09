using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class OrganizationFundingExperienceTypesTests
{
    [Fact]
    public void Migration_and_smoke_are_discoverable_forward_only_and_azure_sql_valid()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root)
            .Single(script => script.Sequence == 34);
        var smoke = SqlScriptCatalog.DiscoverTests(root)
            .Single(script => script.Sequence == 34);
        var migrationSql = File.ReadAllText(Path.Combine(
            root, "database", "Migrations", migration.FileName));
        var smokeSql = File.ReadAllText(Path.Combine(
            root, "database", "Tests", smoke.FileName));

        Assert.Equal("organization_funding_experience_types", migration.Name);
        Assert.Equal("organization_funding_experience_types_smoke", smoke.Name);
        Assert.Equal(5, migration.Batches.Count);
        Assert.Single(smoke.Batches);
        AssertValidAzureSql(migration.FileName, migration.Batches);
        AssertValidAzureSql(smoke.FileName, smoke.Batches);
        Assert.DoesNotContain("DROP TABLE", migrationSql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("TRUNCATE TABLE", migrationSql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("GRANT EXECUTE", migrationSql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("UpdateProfileByPublicIdV2", migrationSql, StringComparison.Ordinal);
        Assert.Contains("@PreviousFunderTypeIdsJson NVARCHAR(1000) = NULL", migrationSql,
            StringComparison.Ordinal);
        Assert.Contains("THROW 51011", migrationSql, StringComparison.Ordinal);
        Assert.Contains("Latin1_General_100_BIN2_UTF8", migrationSql, StringComparison.Ordinal);
        Assert.Contains("fundingExperienceTypeIds", migrationSql, StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_ApiRuntimeRole", smokeSql, StringComparison.Ordinal);
        Assert.Contains("ROLLBACK TRANSACTION FP_Smoke034", smokeSql, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("GOVERNMENTS_PUBLIC_FUNDS", "Gobiernos / fondos públicos")]
    [InlineData("FOUNDATIONS_GRANTMAKERS", "Fundaciones / grantmakers")]
    [InlineData("MULTILATERAL_ORGANIZATIONS", "Organismos multilaterales")]
    [InlineData("INTERNATIONAL_COOPERATION", "Cooperación internacional")]
    [InlineData("COMPANIES", "Empresas")]
    [InlineData("PHILANTHROPISTS", "Filántropos")]
    public void Migration_contains_each_stable_funding_experience_choice(string code, string name)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migrationSql = File.ReadAllText(Path.Combine(root, "database", "Migrations",
            "034_organization_funding_experience_types.sql"));

        Assert.Contains($"N'{code}'", migrationSql, StringComparison.Ordinal);
        Assert.Contains($"N'{name}'", migrationSql, StringComparison.Ordinal);
    }

    private static void AssertValidAzureSql(string fileName, IReadOnlyList<string> batches)
    {
        for (var index = 0; index < batches.Count; index++)
        {
            var parser = new TSql170Parser(true, SqlEngineType.SqlAzure);
            using var reader = new StringReader(batches[index]);
            _ = parser.Parse(reader, out var errors);
            Assert.True(errors.Count == 0,
                $"{fileName} batch {index + 1} is not valid Azure SQL: " +
                string.Join("; ", errors.Select(error =>
                    $"SQL{error.Number} line {error.Line}, column {error.Column}: {error.Message}")));
        }
    }
}
