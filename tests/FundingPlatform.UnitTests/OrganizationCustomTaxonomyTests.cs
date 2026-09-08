using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class OrganizationCustomTaxonomyTests
{
    [Fact]
    public void Migration_and_smoke_are_discoverable_forward_only_and_azure_sql_valid()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root)
            .Single(script => script.Sequence == 35);
        var smoke = SqlScriptCatalog.DiscoverTests(root)
            .Single(script => script.Sequence == 35);
        var migrationSql = Read(root, "database", "Migrations", migration.FileName);
        var smokeSql = Read(root, "database", "Tests", smoke.FileName);

        Assert.Equal("organization_custom_taxonomy", migration.Name);
        Assert.Equal("organization_custom_taxonomy_smoke", smoke.Name);
        Assert.Equal(4, migration.Batches.Count);
        Assert.Single(smoke.Batches);
        AssertValidAzureSql(migration.FileName, migration.Batches);
        AssertValidAzureSql(smoke.FileName, smoke.Batches);
        Assert.DoesNotContain("DROP TABLE", migrationSql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("TRUNCATE TABLE", migrationSql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("GRANT EXECUTE", migrationSql, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("requires migrations 001-034", migrationSql,
            StringComparison.OrdinalIgnoreCase);
        Assert.Equal(3, Count(migrationSql, "CREATE OR ALTER PROCEDURE"));
    }

    [Fact]
    public void Storage_is_tenant_scoped_private_and_bounded()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = Read(root, "database", "Migrations",
            "035_organization_custom_taxonomy.sql");
        var smoke = Read(root, "database", "Tests",
            "035_organization_custom_taxonomy_smoke.sql");

        Assert.Contains("OrganizationId BIGINT NOT NULL", migration, StringComparison.Ordinal);
        Assert.Contains("Kind TINYINT NOT NULL", migration, StringComparison.Ordinal);
        Assert.Contains("CHECK (Kind BETWEEN 1 AND 4)", migration, StringComparison.Ordinal);
        Assert.Contains("UNIQUE (OrganizationId, Kind, NormalizedName)", migration,
            StringComparison.Ordinal);
        Assert.Contains("UNIQUE (OrganizationId, Kind, Name)", migration,
            StringComparison.Ordinal);
        Assert.Contains("NormalizedName COLLATE Latin1_General_100_CI_AI_SC =\n" +
                        "                       Name COLLATE Latin1_General_100_CI_AI_SC",
            migration, StringComparison.Ordinal);
        Assert.Contains("JSON_VALUE(item.[value], N'$.normalizedName') COLLATE Latin1_General_100_CI_AI_SC <>\n" +
                        "                  JSON_VALUE(item.[value], N'$.name') COLLATE Latin1_General_100_CI_AI_SC",
            migration, StringComparison.Ordinal);
        Assert.Contains("ON DELETE CASCADE", migration, StringComparison.Ordinal);
        Assert.Contains("HAVING COUNT_BIG(1) > 5", migration, StringComparison.Ordinal);
        Assert.Contains("COUNT_BIG(1) FROM OPENJSON(@CustomTaxonomyValuesJson)) > 20",
            migration, StringComparison.Ordinal);
        Assert.Contains("DATALENGTH(@CustomTaxonomyValuesJson) > 65536", migration,
            StringComparison.Ordinal);
        Assert.Contains("must not receive direct custom taxonomy table access", smoke,
            StringComparison.Ordinal);
        Assert.Contains("N'Economía circular'", smoke, StringComparison.Ordinal);
        Assert.Contains("N'ECONOMIA CIRCULAR'", smoke, StringComparison.Ordinal);
        Assert.Contains("EXEC dbo.FundingPlatform_usp_Organization_GetProfile", smoke,
            StringComparison.Ordinal);
        Assert.DoesNotContain("FundingPlatform_usp_ProjectMatchingRun_Create", migration,
            StringComparison.Ordinal);
        Assert.DoesNotContain("FundingPlatform_Tags", migration, StringComparison.Ordinal);
    }

    [Fact]
    public void Rolling_contract_preserves_old_clients_and_complete_snapshots()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = Read(root, "database", "Migrations",
            "035_organization_custom_taxonomy.sql");
        var repository = Read(root, "src", "FundingPlatform.Infrastructure", "Persistence",
            "Organizations", "SqlOrganizationRepository.cs");

        Assert.Equal(2, Count(migration,
            "@CustomTaxonomyValuesJson NVARCHAR(MAX) = NULL"));
        Assert.Equal(2, Count(migration,
            "@PreviousFunderTypeIdsJson NVARCHAR(1000) = NULL,\n    @CustomTaxonomyValuesJson NVARCHAR(MAX) = NULL\nAS"));
        Assert.Contains("THROW 51013", migration, StringComparison.Ordinal);
        Assert.Contains("THROW 51014", migration, StringComparison.Ordinal);
        Assert.Contains("$.customTaxonomyValues", migration, StringComparison.Ordinal);
        Assert.Contains("SELECT Kind, Name, NormalizedName", migration, StringComparison.Ordinal);
        Assert.True(migration.IndexOf("SELECT FundingExperienceTypeId AS Id", StringComparison.Ordinal) <
                    migration.IndexOf("SELECT Kind, Name, NormalizedName", StringComparison.Ordinal));
        Assert.Contains("Latin1_General_100_CI_AI_SC", migration, StringComparison.Ordinal);
        Assert.Contains("name = value.Name", repository, StringComparison.Ordinal);
        Assert.Contains("normalizedName = value.NormalizedName", repository,
            StringComparison.Ordinal);
        Assert.DoesNotContain("UpdateProfileByPublicIdV2", migration, StringComparison.Ordinal);

        var updateStart = migration.IndexOf(
            "CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Organization_UpdateProfile\n",
            StringComparison.Ordinal);
        var updateEnd = migration.IndexOf("\nGO\n", updateStart, StringComparison.Ordinal);
        var update = migration[updateStart..updateEnd];
        var authorization = update.IndexOf("Role = 1 AND MembershipStatus = 1", StringComparison.Ordinal);
        var legacyGuard = update.IndexOf("THROW 51013", StringComparison.Ordinal);
        var mutation = update.IndexOf("UPDATE dbo.FundingPlatform_Organizations", StringComparison.Ordinal);
        Assert.True(authorization >= 0 && authorization < legacyGuard && legacyGuard < mutation,
            "Administrator authorization must precede the legacy guard and every mutation.");
    }

    private static string Read(string root, params string[] parts) =>
        File.ReadAllText(Path.Combine([root, .. parts]));

    private static int Count(string value, string token) =>
        (value.Length - value.Replace(token, string.Empty, StringComparison.Ordinal).Length) /
        token.Length;

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
