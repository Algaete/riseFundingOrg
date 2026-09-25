using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class OrganizationVerificationMigrationTests
{
    [Theory]
    [InlineData("Migrations", "063_organization_verification.sql")]
    [InlineData("Tests", "063_organization_verification_smoke.sql")]
    public void Sql_parses_without_connecting_to_a_database(string folder, string name)
    {
        using var reader = new StringReader(Read(folder, name));
        new TSql170Parser(true).Parse(reader, out var errors);
        Assert.Empty(errors.Select(error => $"{error.Line}:{error.Column}: {error.Message}"));
    }

    [Fact]
    public void Verification_is_private_versioned_audited_and_does_not_change_access()
    {
        var sql = Read("Migrations", "063_organization_verification.sql");
        foreach (var clause in new[]
        {
            "FundingPlatform_fn_AdminAccessState", "FundingPlatform_usp_AdminActor_Lock",
            "FROM dbo.FundingPlatform_Organizations WITH (UPDLOCK, HOLDLOCK)",
            "@Revision <> @ExpectedRevision OR @ProfileVersion <> @ExpectedProfileVersion",
            "v.ReviewedProfileVersion = o.ProfileVersion", "v.Status IN (1, 2)",
            "FundingPlatform_OrganizationVerificationHistory", "TOP (50)", "INCLUDE_NULL_VALUES",
            "FOR JSON PATH, INCLUDE_NULL_VALUES), N'[]')) AS history",
            "@Reason NVARCHAR(MAX)", "DATALENGTH(@Reason) > 4000", "@VerificationStatus TINYINT = NULL"
        }) Assert.Contains(clause, sql, StringComparison.Ordinal);
        Assert.DoesNotContain("UPDATE dbo.FundingPlatform_Organizations", sql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("UPDATE dbo.FundingPlatform_OrganizationVerificationHistory", sql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("DELETE", sql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("GRANT SELECT", sql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("TO FundingPlatform_GeneralWorkerRole", sql, StringComparison.Ordinal);
        Assert.Equal(2, sql.Split("GRANT EXECUTE ON OBJECT::", StringSplitOptions.None).Length - 1);
    }

    [Fact]
    public void Smoke_reverts_synthetic_decisions_and_exercises_profile_changes()
    {
        var sql = Read("Tests", "063_organization_verification_smoke.sql");
        Assert.Contains("example.invalid", sql);
        Assert.Contains("ROLLBACK TRANSACTION FP_Smoke063", sql);
        Assert.Contains("RowVersion = @OriginalRowVersion", sql);
        Assert.Contains("$.needsReverification", sql);
        Assert.Contains("$.history", sql);
        Assert.DoesNotContain("COMMIT", sql, StringComparison.OrdinalIgnoreCase);
    }

    private static string Read(string folder, string file) => File.ReadAllText(Path.Combine(
        SolutionRootLocator.Find(AppContext.BaseDirectory), "database", folder, file));
}
