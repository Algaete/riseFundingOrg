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
