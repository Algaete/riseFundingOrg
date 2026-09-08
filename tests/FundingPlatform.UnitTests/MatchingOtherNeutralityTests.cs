using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class MatchingOtherNeutralityTests
{
    [Fact]
    public void Migration_and_smoke_are_discoverable_and_valid_Azure_sql()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root)
            .Single(script => script.Sequence == 32);
        var smoke = SqlScriptCatalog.DiscoverTests(root)
            .Single(script => script.Sequence == 32);

        Assert.Equal("matching_other_neutrality", migration.Name);
        Assert.Equal("matching_other_neutrality_smoke", smoke.Name);
        Assert.Single(migration.Batches);
        Assert.Single(smoke.Batches);
        AssertValidAzureSql(migration.FileName, migration.Batches);
        AssertValidAzureSql(smoke.FileName, smoke.Batches);
    }

    [Fact]
    public void Migration_versions_the_engine_profile_rules_and_policy_without_relabeling_history()
    {
        var migration = ReadMigration();

        Assert.Contains("N'deterministic-project-v1' AND Version = 1", migration,
            StringComparison.Ordinal);
        Assert.Contains("N'deterministic-project-v1', 2, N'deterministic-sql-v2'", migration,
            StringComparison.Ordinal);
        Assert.Contains("rules.HandlerVersion = N''v2''", migration,
            StringComparison.Ordinal);
        Assert.Contains("\"otherPolicy\":\"neutral-excluded\"", migration,
            StringComparison.Ordinal);
        Assert.Contains("SET IsActive = 0", migration, StringComparison.Ordinal);
        Assert.Contains("SET IsActive = 1", migration, StringComparison.Ordinal);
        Assert.DoesNotContain("UPDATE dbo.FundingPlatform_ProjectMatchingRuns", migration,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("UPDATE dbo.FundingPlatform_ProjectFundingMatchRuleResults", migration,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("UPDATE dbo.FundingPlatform_ProjectFundingMatches", migration,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("DELETE FROM dbo.FundingPlatform_ProjectMatchingRuns", migration,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("DELETE FROM dbo.FundingPlatform_ProjectFundingMatchRuleResults", migration,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("DELETE FROM dbo.FundingPlatform_ProjectFundingMatches", migration,
            StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Procedure_patch_filters_other_from_both_snapshot_sides_and_is_fail_closed()
    {
        var migration = ReadMigration();

        Assert.Equal(6, Count(migration, "Code <> N''OTHER''"));
        Assert.Contains("FundingOpportunityCategories AS links WITH (HOLDLOCK)", migration,
            StringComparison.Ordinal);
        Assert.Contains("FundingOpportunityBeneficiaryTypes AS links WITH (HOLDLOCK)", migration,
            StringComparison.Ordinal);
        Assert.Contains("FundingOpportunityProjectTypes AS links WITH (HOLDLOCK)", migration,
            StringComparison.Ordinal);
        Assert.Contains("ProjectCategories AS links WITH (HOLDLOCK)", migration,
            StringComparison.Ordinal);
        Assert.Contains("ProjectBeneficiaryTypes AS links WITH (HOLDLOCK)", migration,
            StringComparison.Ordinal);
        Assert.Contains("ProjectProjectTypes AS links WITH (HOLDLOCK)", migration,
            StringComparison.Ordinal);
        Assert.Contains("(@OldCount = @ExpectedCount AND @NewCount = 0)", migration,
            StringComparison.Ordinal);
        Assert.Contains("(@OldCount = 0 AND @NewCount = @ExpectedCount)", migration,
            StringComparison.Ordinal);
        Assert.Contains("@OldCount <> 0 OR @NewCount <> @ExpectedCount", migration,
            StringComparison.Ordinal);
        Assert.Contains("@CurrentHandlerCount <> 3", ReadSmoke(),
            StringComparison.Ordinal);
        Assert.Contains("@NeutralCount <> 6", ReadSmoke(), StringComparison.Ordinal);
        Assert.Contains("uses_ansi_nulls = 1", migration, StringComparison.Ordinal);
        Assert.Contains("uses_quoted_identifier = 1", migration, StringComparison.Ordinal);
        Assert.Contains("N'CREATE OR ALTER PROCEDURE'", migration, StringComparison.Ordinal);
    }

    [Fact]
    public void Migration_is_safe_to_reapply_after_the_v2_state_exists()
    {
        var migration = ReadMigration();

        Assert.Contains("WHERE NOT EXISTS", migration, StringComparison.Ordinal);
        Assert.Contains("@ExistingWeightCount NOT IN (0, 9)", migration,
            StringComparison.Ordinal);
        Assert.Contains("IF @ExistingWeightCount = 0", migration,
            StringComparison.Ordinal);
        Assert.Contains("OR (@OldCount = 0 AND @NewCount = @ExpectedCount)", migration,
            StringComparison.Ordinal);
        Assert.Contains("WHERE Id = @LegacyProfileId AND IsActive = 1", migration,
            StringComparison.Ordinal);
        Assert.Contains("WHERE Id = @NewProfileId AND IsActive = 0", migration,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Smoke_executes_an_only_other_fixture_as_unknown_zero_for_all_three_rules()
    {
        var smoke = ReadSmoke();

        Assert.Contains("VALUES (@ProjectId, @OtherCategoryId)", smoke,
            StringComparison.Ordinal);
        Assert.Contains("VALUES (@ProjectId, @OtherBeneficiaryId)", smoke,
            StringComparison.Ordinal);
        Assert.Contains("VALUES (@ProjectId, @OtherProjectTypeId)", smoke,
            StringComparison.Ordinal);
        Assert.Contains("VALUES (@OpportunityId, @OtherCategoryId)", smoke,
            StringComparison.Ordinal);
        Assert.Contains("VALUES (@OpportunityId, @OtherBeneficiaryId)", smoke,
            StringComparison.Ordinal);
        Assert.Contains("VALUES (@OpportunityId, @OtherProjectTypeId)", smoke,
            StringComparison.Ordinal);
        Assert.Contains("rules.Code IN (N'categories', N'beneficiaries', N'project_type')", smoke,
            StringComparison.Ordinal);
        Assert.Contains("results.Outcome = 3", smoke, StringComparison.Ordinal);
        Assert.Contains("results.DataState = 1", smoke, StringComparison.Ordinal);
        Assert.Contains("results.RawScore IS NULL", smoke, StringComparison.Ordinal);
        Assert.Contains("results.EffectiveScore = 0", smoke, StringComparison.Ordinal);
        Assert.Contains("results.WeightedPoints = 0", smoke, StringComparison.Ordinal);
        Assert.Contains("CompatibilityScore = 80", smoke, StringComparison.Ordinal);
        Assert.Contains("RuleScore = 80", smoke, StringComparison.Ordinal);
        Assert.Contains("EvidenceCoverage = 80", smoke, StringComparison.Ordinal);
    }

    [Fact]
    public void Smoke_keeps_the_v1_profile_and_handlers_auditable()
    {
        var smoke = ReadSmoke();

        Assert.Contains("EngineVersion = N'deterministic-sql-v1' AND IsActive = 0", smoke,
            StringComparison.Ordinal);
        Assert.Contains("rules.HandlerVersion = N'v1'", smoke,
            StringComparison.Ordinal);
        Assert.Contains("runs.MatchingProfileVersionSnapshot <> 1", smoke,
            StringComparison.Ordinal);
        Assert.Contains("runs.EngineVersionSnapshot <> N'deterministic-sql-v1'", smoke,
            StringComparison.Ordinal);
        Assert.Contains("MatchingProfileVersion = 2", smoke, StringComparison.Ordinal);
        Assert.Contains("EngineVersion = N'deterministic-sql-v2'", smoke,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Historical_matching_smoke_runs_against_the_single_active_engine_version()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var historicalSmoke = File.ReadAllText(Path.Combine(root, "database", "Tests",
            "020_deterministic_project_matching_smoke.sql"));

        Assert.Contains("WHEN 1 THEN N'v1' WHEN 2 THEN N'v2'", historicalSmoke,
            StringComparison.Ordinal);
        Assert.Contains("rules.HandlerVersion = @HandlerVersion", historicalSmoke,
            StringComparison.Ordinal);
        Assert.Contains("@ProfileVersion = 2 AND @EngineVersion = N'deterministic-sql-v2'",
            historicalSmoke, StringComparison.Ordinal);
        Assert.Contains("Version = 1", historicalSmoke, StringComparison.Ordinal);
        Assert.Contains("IsActive = 0", historicalSmoke, StringComparison.Ordinal);
        Assert.DoesNotContain(
            "Version = 1\n       AND EngineVersion = N'deterministic-sql-v1'\n" +
            "       AND UnknownPolicy = 1 AND Status = 2 AND IsActive = 1",
            historicalSmoke,
            StringComparison.Ordinal);
    }

    private static string ReadMigration()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        return File.ReadAllText(Path.Combine(root, "database", "Migrations",
            "032_matching_other_neutrality.sql"));
    }

    private static string ReadSmoke()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        return File.ReadAllText(Path.Combine(root, "database", "Tests",
            "032_matching_other_neutrality_smoke.sql"));
    }

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
