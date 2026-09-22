using System.Text.RegularExpressions;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class DevGeographicSampleTests
{
    private static string Read(string path) => File.ReadAllText(Path.Combine(SolutionRootLocator.Find(), path));

    [Fact]
    public void Explicit_sample_is_valid_azure_sql_and_is_not_an_automatic_migration()
    {
        var script = Read("database/Fixtures/dev-geographic-matching.sql");
        _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(new StringReader(script), out var errors);
        Assert.Empty(errors);
        Assert.DoesNotContain(SqlScriptCatalog.DiscoverMigrations(SolutionRootLocator.Find()),
            migration => migration.FileName.Contains("dev-geographic", StringComparison.Ordinal));
        Assert.Contains("DB_NAME() <> N'risefunding-dev' OR @@TRANCOUNT = 0", script);
        Assert.Contains("@Mode IN (N'verify',N'disable')", script);
        Assert.Contains("Partial, renamed or foreign sample detected", script);
    }

    [Fact]
    public void Sample_never_mutates_authentication_or_deletes_history()
    {
        var script = Read("database/Fixtures/dev-geographic-matching.sql");
        Assert.DoesNotMatch(new Regex(@"\b(?:INSERT(?:\s+INTO)?|UPDATE|DELETE(?:\s+FROM)?)\s+dbo\.FundingPlatform_(?:Users|UserRoles|Roles|RefreshTokens|UserAuthenticatorKeys|UserMfaChallenges)\b", RegexOptions.IgnoreCase), script);
        Assert.DoesNotMatch(new Regex(@"\b(?:DELETE\s+FROM|DROP\s+TABLE|TRUNCATE\s+TABLE)\b", RegexOptions.IgnoreCase), script);
        Assert.Contains("AllowRequests=0", script);
        Assert.Contains("ProviderCode IS NULL", script);
        Assert.Contains("TEST · DATOS DE PRUEBA · ", script);
        Assert.DoesNotContain("@gmail.com", script);
    }

    [Fact]
    public void Sample_source_identity_uses_utf8_like_editorial_updates()
    {
        var script = Read("database/Fixtures/dev-geographic-matching.sql");
        Assert.Contains("CONVERT(VARBINARY(MAX),CONVERT(VARCHAR(MAX),f.Slug COLLATE Latin1_General_100_BIN2_UTF8))", script);
        Assert.DoesNotContain("HASHBYTES('SHA2_256',f.Slug)", script);
    }

    [Fact]
    public void Forward_repair_is_valid_sql_and_only_rewrites_known_legacy_test_hashes()
    {
        var script = Read("database/Migrations/059_dev_sample_source_identity.sql");
        _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(new StringReader(script), out var errors);
        Assert.Empty(errors);
        Assert.Contains("70510000-0000-4000-8000-000000000101", script);
        Assert.Contains("70510000-0000-4000-8000-000000000102", script);
        Assert.Contains("o.PublicId=f.PublicId AND o.Slug=f.Slug AND o.Title=f.Title", script);
        Assert.Contains("s.ProviderType=0 AND s.ProviderCode IS NULL", script);
        Assert.Contains("JSON_VALUE(s.ConfigurationJson,'$.sample')=N'dev-geographic-sample-v1'", script);
        Assert.Contains("l.SourceItemKeyHash=HASHBYTES('SHA2_256',l.ExternalId)", script);
        Assert.Contains("Latin1_General_100_BIN2_UTF8", script);
        Assert.Contains("otherLink.Id<>c.LinkId", script);
        Assert.Contains("THROW 56090", script);
        Assert.Single(Regex.Matches(script, @"\bUPDATE\b", RegexOptions.IgnoreCase));
        Assert.Contains("UPDATE l SET SourceItemKeyHash=c.ExpectedHash", script);
        var smoke = Read("database/Tests/059_dev_sample_source_identity_smoke.sql");
        _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(new StringReader(smoke), out errors);
        Assert.Empty(errors);
        Assert.DoesNotMatch(new Regex(@"\b(?:UPDATE|DELETE|INSERT|MERGE|COMMIT)\b", RegexOptions.IgnoreCase), smoke);
    }

    [Fact]
    public void Source_identity_diagnostic_is_read_only_and_requires_exact_target()
    {
        var cli = Read("tools/FundingPlatform.DatabaseMigrator/Program.cs");
        var start = cli.IndexOf("static async Task<int> CheckSourceIdentitiesAsync", StringComparison.Ordinal);
        var end = cli.IndexOf("static ", start + 1, StringComparison.Ordinal);
        var diagnostic = end < 0 ? cli[start..] : cli[start..end];
        Assert.Contains("requireExpectedServer: true", diagnostic);
        Assert.Contains("COUNT_BIG(*)", diagnostic);
        Assert.DoesNotMatch(new Regex(@"\b(?:UPDATE|INSERT|DELETE|MERGE|COMMIT)\b", RegexOptions.IgnoreCase), diagnostic);
        Assert.Contains("--check-source-identities", Read("infra/scripts/check-dev-database.sh"));
    }

    [Fact]
    public void Cli_requires_exact_dev_target_and_explicit_confirmation_before_commit()
    {
        var cli = Read("tools/FundingPlatform.AdminCli/DevGeographicSample.cs");
        Assert.Contains("WRITE-DEV-TEST-DATA", cli);
        Assert.Contains("sql-rf-dev-ag26rf01-centralus.database.windows.net", cli);
        Assert.Contains("requireExpectedServer: true", cli);
        Assert.Contains("transaction.RollbackAsync", cli);
        Assert.Contains("FundingPlatform_usp_ProjectMatchingRun_Create", cli);
        Assert.Contains("new GapRecommendationService", cli);
        Assert.DoesNotContain("DevGeographicSample", Read("src/FundingPlatform.Api/Program.cs"));
        Assert.DoesNotContain("DevGeographicSample", Read("src/FundingPlatform.Workers/Program.cs"));
    }
}
