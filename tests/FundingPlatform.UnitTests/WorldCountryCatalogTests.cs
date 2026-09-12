using System.Text.RegularExpressions;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class WorldCountryCatalogTests
{
    private static string Read(string folder, string file) => File.ReadAllText(Path.Combine(
        SolutionRootLocator.Find(AppContext.BaseDirectory), "database", folder, file));

    [Theory]
    [InlineData("Migrations", "048_world_country_catalog.sql")]
    [InlineData("Tests", "048_world_country_catalog_smoke.sql")]
    public void Catalog_migration_and_smoke_are_valid_azure_sql(string folder, string file)
    {
        var batches = GoBatchSplitter.Split(Read(folder, file));
        Assert.Single(batches);
        var parser = new TSql170Parser(true, SqlEngineType.SqlAzure);
        using var reader = new StringReader(batches[0]);
        _ = parser.Parse(reader, out var errors);
        Assert.True(errors.Count == 0, string.Join("; ", errors.Select(error => $"{error.Line}: {error.Message}")));
    }

    [Fact]
    public void Catalog_has_249_unique_iso_identities_and_spanish_names()
    {
        var sql = Read("Migrations", "048_world_country_catalog.sql");
        var rows = Regex.Matches(sql, @"\((?<id>\d+), '(?<iso2>[A-Z]{2})', '(?<iso3>[A-Z]{3})', N'(?<name>(?:[^']|'')+)'\)");
        Assert.Equal(249, rows.Count);
        foreach (var column in new[] { "id", "iso2", "iso3" })
            Assert.Equal(249, rows.Select(row => row.Groups[column].Value).Distinct().Count());
        foreach (Match row in rows)
        {
            Assert.InRange(int.Parse(row.Groups["id"].Value), 1, 999);
            Assert.InRange(row.Groups["name"].Value.Replace("''", "'").Length, 1, 120);
        }
        foreach (var entry in new[] { "(152, 'CL', 'CHL', N'Chile')", "(840, 'US', 'USA', N'Estados Unidos de América')",
                     "(32, 'AR', 'ARG', N'Argentina')", "(392, 'JP', 'JPN', N'Japón')", "(710, 'ZA', 'ZAF', N'Sudáfrica')",
                     "(36, 'AU', 'AUS', N'Australia')", "(724, 'ES', 'ESP', N'España')", "(158, 'TW', 'TWN', N'Taiwán')" })
            Assert.Contains(entry, sql, StringComparison.Ordinal);
    }

    [Fact]
    public void Migration_is_additive_replay_safe_and_fails_closed_on_identity_collisions()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        Assert.Equal("world_country_catalog", SqlScriptCatalog.DiscoverMigrations(root).Single(s => s.Sequence == 48).Name);
        Assert.Equal("world_country_catalog_smoke", SqlScriptCatalog.DiscoverTests(root).Single(s => s.Sequence == 48).Name);
        var sql = Read("Migrations", "048_world_country_catalog.sql");
        Assert.Contains("Existing.Id = Seed.Id OR Existing.Iso2 = Seed.Iso2 OR Existing.Iso3 = Seed.Iso3", sql, StringComparison.Ordinal);
        Assert.True(sql.IndexOf("THROW 55582", StringComparison.Ordinal) < sql.IndexOf("INSERT INTO dbo.FundingPlatform_Countries", StringComparison.Ordinal));
        Assert.Contains("WHERE NOT EXISTS", sql, StringComparison.Ordinal);
        Assert.DoesNotMatch(@"(?i)\b(UPDATE|DELETE|MERGE|DROP|ALTER|TRUNCATE)\s+", sql);
        Assert.DoesNotContain("COMMIT TRANSACTION", sql, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Smoke_checks_every_identity_and_non_chilean_funder_create_update_without_publishing()
    {
        var sql = Read("Tests", "048_world_country_catalog_smoke.sql");
        Assert.Equal(249, Regex.Matches(sql, @"\(\d+, '[A-Z]{2}', '[A-Z]{3}'\)").Count);
        Assert.Contains("FundingPlatform_usp_Funder_Create", sql, StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_usp_Funder_Update", sql, StringComparison.Ordinal);
        Assert.Contains("@CountryId = 840", sql, StringComparison.Ordinal);
        Assert.Contains("@CountryId = 392", sql, StringComparison.Ordinal);
        Assert.Contains("PublicationStatus = 0", sql, StringComparison.Ordinal);
        Assert.Contains("ROLLBACK TRANSACTION FP_Smoke048", sql, StringComparison.Ordinal);
    }
}
