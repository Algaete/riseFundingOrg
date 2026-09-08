using FundingPlatform.Contracts.Projects;
using FundingPlatform.Core.Projects;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class ProjectImpactProfileTests
{
    [Fact]
    public void Migration_and_smoke_are_discoverable_and_valid_Azure_sql()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root)
            .Single(script => script.Sequence == 33);
        var smoke = SqlScriptCatalog.DiscoverTests(root)
            .Single(script => script.Sequence == 33);

        Assert.Equal("project_impact_profile", migration.Name);
        Assert.Equal("project_impact_profile_smoke", smoke.Name);
        Assert.NotEmpty(migration.Batches);
        Assert.NotEmpty(smoke.Batches);
        AssertValidAzureSql(migration.FileName, migration.Batches);
        AssertValidAzureSql(smoke.FileName, smoke.Batches);
    }

    [Fact]
    public void Project_stage_is_a_separate_nullable_six_value_dimension()
    {
        Assert.Equal(0, (byte)ProjectStage.IdeaOrDesign);
        Assert.Equal(1, (byte)ProjectStage.Pilot);
        Assert.Equal(2, (byte)ProjectStage.Implementation);
        Assert.Equal(3, (byte)ProjectStage.Scaling);
        Assert.Equal(4, (byte)ProjectStage.Consolidation);
        Assert.Equal(5, (byte)ProjectStage.Evaluation);
        Assert.Equal(7, Enum.GetValues<ProjectStatus>().Length);

        var migration = ReadMigration();
        Assert.Contains("ProjectStage TINYINT NULL", migration, StringComparison.Ordinal);
        Assert.Contains("ProjectStage IS NULL OR ProjectStage BETWEEN 0 AND 5", migration,
            StringComparison.Ordinal);
        Assert.DoesNotContain("UPDATE dbo.FundingPlatform_Projects SET ProjectStage", migration,
            StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Catalog_contains_exactly_the_17_stable_official_goal_codes()
    {
        var migration = ReadMigration();

        for (var goal = 1; goal <= 17; goal++)
        {
            Assert.Contains($"N'SDG_{goal:00}'", migration, StringComparison.Ordinal);
        }

        Assert.Equal(17, Count(migration, "N'SDG_"));
        Assert.Contains("N'Fin de la pobreza'", migration, StringComparison.Ordinal);
        Assert.Contains("N'Alianzas para lograr los objetivos'", migration,
            StringComparison.Ordinal);
        Assert.Contains("Result set 13: official UN Sustainable Development Goals", migration,
            StringComparison.Ordinal);
    }

    [Fact]
    public void V1_write_procedures_remain_callable_by_old_revisions_and_fail_closed_on_snapshot_loss()
    {
        var migration = ReadMigration();
        var repository = ReadRepository();

        Assert.Contains("@ProjectStage TINYINT = NULL", migration, StringComparison.Ordinal);
        Assert.Contains("@ProjectStageIsSpecified BIT = 0", migration, StringComparison.Ordinal);
        Assert.Contains("@SustainableDevelopmentGoalIdsJson NVARCHAR(1000) = NULL",
            migration, StringComparison.Ordinal);
        Assert.Contains("THROW 51411", migration, StringComparison.Ordinal);
        Assert.Contains("Legacy update cannot replace a project with impact data", migration,
            StringComparison.Ordinal);
        Assert.Equal(2, Count(migration,
            "CONVERT(NVARCHAR(11), TRY_CONVERT(INT, [value])) <> [value]"));
        Assert.Contains("SustainableDevelopmentGoalIdsJson", repository, StringComparison.Ordinal);
        Assert.Contains("ProjectStageIsSpecified", repository, StringComparison.Ordinal);
        Assert.DoesNotContain(
            "SustainableDevelopmentGoalIds\").AsTableValuedParameter",
            repository,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Project_write_request_keeps_the_pre_033_positional_constructor()
    {
        var legacyRequest = new ProjectWriteRequest(
            "Proyecto compatible", null, null, 2, null, null, null, null, null,
            [], [], [], [], []);

        Assert.Null(legacyRequest.SustainableDevelopmentGoalIds);
        Assert.Null(legacyRequest.ProjectStage);
    }

    [Fact]
    public void Smoke_versions_complete_impact_snapshots_and_checks_the_legacy_guard()
    {
        var smoke = ReadSmoke();

        Assert.Contains("projectStage\":1", smoke, StringComparison.Ordinal);
        Assert.Contains("sustainableDevelopmentGoalIds\":[1,13]", smoke,
            StringComparison.Ordinal);
        Assert.Contains("projectStage\":4", smoke, StringComparison.Ordinal);
        Assert.Contains("sustainableDevelopmentGoalIds\":[4,17]", smoke,
            StringComparison.Ordinal);
        Assert.Contains("@UpdateDefinition NOT LIKE N'%THROW 51411%'", smoke,
            StringComparison.Ordinal);
        Assert.Contains("SnapshotJson = @Snapshot2 AND ContentHash = @Hash2", smoke,
            StringComparison.Ordinal);
        Assert.Contains("ROLLBACK TRANSACTION FP_Smoke033", smoke, StringComparison.Ordinal);
    }

    private static string ReadMigration()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        return File.ReadAllText(Path.Combine(root, "database", "Migrations",
            "033_project_impact_profile.sql"));
    }

    private static string ReadSmoke()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        return File.ReadAllText(Path.Combine(root, "database", "Tests",
            "033_project_impact_profile_smoke.sql"));
    }

    private static string ReadRepository()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        return File.ReadAllText(Path.Combine(root, "src", "FundingPlatform.Infrastructure",
            "Persistence", "Projects", "SqlProjectRepository.cs"));
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
