using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class OrganizationProfileCatalogExpansionTests
{
    [Fact]
    public void Migration_and_smoke_are_discoverable_forward_only_and_compatible()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root)
            .Single(script => script.Sequence == 31);
        var smoke = SqlScriptCatalog.DiscoverTests(root)
            .Single(script => script.Sequence == 31);
        var migrationSql = File.ReadAllText(Path.Combine(
            root, "database", "Migrations", migration.FileName));
        var smokeSql = File.ReadAllText(Path.Combine(
            root, "database", "Tests", smoke.FileName));

        Assert.Equal("organization_profile_catalog_expansion", migration.Name);
        Assert.Equal("organization_profile_catalog_expansion_smoke", smoke.Name);
        Assert.Single(migration.Batches);
        Assert.Single(smoke.Batches);
        AssertValidAzureSql(migration.FileName, migration.Batches);
        AssertValidAzureSql(smoke.FileName, smoke.Batches);
        Assert.Contains("legacy organization-size rows remain active", migrationSql,
            StringComparison.Ordinal);
        Assert.Contains("PROGRAM is", migrationSql, StringComparison.Ordinal);
        Assert.Contains("deliberately retained as an active legacy option", migrationSql,
            StringComparison.Ordinal);
        Assert.DoesNotContain("DELETE FROM", migrationSql,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("TRUNCATE TABLE", migrationSql,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("DROP TABLE", migrationSql,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("SET Code =", migrationSql,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("SET Id =", migrationSql,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("SET IsActive =", migrationSql,
            StringComparison.OrdinalIgnoreCase);
        Assert.Contains("ROLLBACK TRANSACTION FP_Smoke031", smokeSql,
            StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("EMPLOYEES_1_10")]
    [InlineData("EMPLOYEES_11_50")]
    [InlineData("EMPLOYEES_51_100")]
    [InlineData("EMPLOYEES_101_PLUS")]
    [InlineData("CLIMATE_CHANGE")]
    [InlineData("WATER_SANITATION")]
    [InlineData("AGRICULTURE_FOOD_SECURITY")]
    [InlineData("GENDER_EQUALITY")]
    [InlineData("PEACE_CONFLICT_HUMANITARIAN")]
    [InlineData("CITIES_HOUSING_TERRITORIAL")]
    [InlineData("SPORT_COMMUNITY_DEVELOPMENT")]
    [InlineData("RURAL_COMMUNITIES")]
    [InlineData("PEOPLE_IN_POVERTY_OR_VULNERABILITY")]
    [InlineData("ENTREPRENEURS_AND_SMALL_PRODUCERS")]
    [InlineData("COMMUNITY_DEVELOPMENT")]
    [InlineData("TRAINING_CAPACITY_DEVELOPMENT")]
    [InlineData("INNOVATION_TECHNOLOGY")]
    [InlineData("ENTREPRENEURSHIP_PRODUCTIVE_DEVELOPMENT")]
    [InlineData("ENVIRONMENTAL_CONSERVATION_RESTORATION")]
    [InlineData("DISASTER_RISK_PREVENTION_REDUCTION")]
    public void Migration_contains_each_new_profile_catalog_code(string code)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migrationSql = File.ReadAllText(Path.Combine(root, "database", "Migrations",
            "031_organization_profile_catalog_expansion.sql"));

        Assert.Contains($"N'{code}'", migrationSql, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("N'pt', N'Portugués'")]
    [InlineData("N'fr', N'Francés'")]
    [InlineData("N'und', N'Otro'")]
    [InlineData("N'OTHER', N'Otros'")]
    public void Migration_contains_the_new_language_and_other_choices(string seed)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migrationSql = File.ReadAllText(Path.Combine(root, "database", "Migrations",
            "031_organization_profile_catalog_expansion.sql"));

        Assert.Contains(seed, migrationSql, StringComparison.Ordinal);
    }

    [Fact]
    public void Smoke_covers_all_requested_catalog_families_and_historical_rows()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var smokeSql = File.ReadAllText(Path.Combine(root, "database", "Tests",
            "031_organization_profile_catalog_expansion_smoke.sql"));

        Assert.Contains("@ExpectedOrganizationSizes", smokeSql, StringComparison.Ordinal);
        Assert.Contains("@ExpectedCategories", smokeSql, StringComparison.Ordinal);
        Assert.Contains("@ExpectedBeneficiaries", smokeSql, StringComparison.Ordinal);
        Assert.Contains("@ExpectedProjectTypes", smokeSql, StringComparison.Ordinal);
        Assert.Contains("@ExpectedLanguages", smokeSql, StringComparison.Ordinal);
        Assert.Contains("Code = N'MICRO'", smokeSql, StringComparison.Ordinal);
        Assert.Contains("Code = N'SMALL'", smokeSql, StringComparison.Ordinal);
        Assert.Contains("Code = N'MEDIUM'", smokeSql, StringComparison.Ordinal);
        Assert.Contains("Code = N'LARGE'", smokeSql, StringComparison.Ordinal);
        Assert.Contains("Code = N'PROGRAM'", smokeSql, StringComparison.Ordinal);
    }

    private static void AssertValidAzureSql(string fileName, IReadOnlyList<string> batches)
    {
        for (var index = 0; index < batches.Count; index++)
        {
            var parser = new TSql170Parser(true, SqlEngineType.SqlAzure);
            using var reader = new StringReader(batches[index]);
            _ = parser.Parse(reader, out var errors);

            Assert.True(
                errors.Count == 0,
                $"{fileName} batch {index + 1} is not valid Azure SQL: " +
                string.Join(
                    "; ",
                    errors.Select(error =>
                        $"SQL{error.Number} line {error.Line}, column {error.Column}: " +
                        error.Message)));
        }
    }
}
