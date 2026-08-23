using System.Text;
using FundingPlatform.Infrastructure.Persistence.Migrations;

namespace FundingPlatform.UnitTests;

public sealed class MigrationInfrastructureTests
{
    [Fact]
    public void Go_splitter_splits_only_a_standalone_line()
    {
        const string script = """
            SELECT 1;
              GO  
            SELECT 'GO';
            GOTO NextLabel;
            go -- not a standalone line
            NextLabel:
            SELECT 2;
            """;

        var batches = GoBatchSplitter.Split(script);

        Assert.Equal(2, batches.Count);
        Assert.Equal("SELECT 1;", batches[0]);
        Assert.Contains("SELECT 'GO';", batches[1]);
        Assert.Contains("go -- not a standalone line", batches[1]);
    }

    [Fact]
    public void Go_splitter_does_not_split_inside_multiline_strings_or_block_comments()
    {
        const string script = """
            SELECT 'first
            GO
            last';
            /* outer
               /* nested */
            GO
            */
            GO
            SELECT 2;
            """;

        var batches = GoBatchSplitter.Split(script);

        Assert.Equal(2, batches.Count);
        Assert.Contains("last';", batches[0]);
        Assert.Contains("GO", batches[0]);
        Assert.Equal("SELECT 2;", batches[1]);
    }

    [Fact]
    public void Go_splitter_does_not_split_inside_multiline_quoted_identifiers()
    {
        const string script = """
            SELECT "quoted
            GO
            identifier", [bracketed
            GO
            identifier];
            GO
            SELECT 2;
            """;

        var batches = GoBatchSplitter.Split(script);

        Assert.Equal(2, batches.Count);
        Assert.Contains("identifier];", batches[0]);
        Assert.Equal("SELECT 2;", batches[1]);
    }

    [Fact]
    public void Catalog_discovers_numbered_migrations_in_numeric_order_with_sha256()
    {
        using var repository = TemporaryMigrationRepository.Create();
        repository.WriteMigration("002_second.sql", "SELECT 2;");
        repository.WriteMigration("001_first.sql", "SELECT 1;\nGO\nSELECT 10;");

        var scripts = SqlScriptCatalog.DiscoverMigrations(repository.Root);

        Assert.Collection(
            scripts,
            first =>
            {
                Assert.Equal(1, first.Sequence);
                Assert.Equal("first", first.Name);
                Assert.Equal(2, first.Batches.Count);
                Assert.Equal(
                    SqlScriptCatalog.ComputeChecksum(Encoding.UTF8.GetBytes("SELECT 1;\nGO\nSELECT 10;")),
                    first.Checksum);
            },
            second => Assert.Equal(2, second.Sequence));
    }

    [Fact]
    public void Catalog_discovers_sql_tests_from_the_dedicated_directory()
    {
        using var repository = TemporaryMigrationRepository.Create(includeTests: true);
        repository.WriteTest("001_initial_schema_smoke.sql", "SELECT 1;");

        var tests = SqlScriptCatalog.DiscoverTests(repository.Root);

        var test = Assert.Single(tests);
        Assert.Equal(1, test.Sequence);
        Assert.Equal("initial_schema_smoke", test.Name);
    }

    [Fact]
    public void Catalog_discovers_non_transactional_provisioning_separately()
    {
        using var repository = TemporaryMigrationRepository.Create(includeProvisioning: true);
        repository.WriteProvisioning(
            "001_funding_opportunity_full_text.sql",
            "SELECT 1;\nGO\nSELECT 2;");

        var scripts = SqlScriptCatalog.DiscoverProvisioning(repository.Root);

        var script = Assert.Single(scripts);
        Assert.Equal(1, script.Sequence);
        Assert.Equal("funding_opportunity_full_text", script.Name);
        Assert.Equal(2, script.Batches.Count);
        Assert.Empty(SqlScriptCatalog.DiscoverMigrations(repository.Root));
    }

    [Fact]
    public void Full_text_provisioning_is_non_transactional_locked_and_drift_checked()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var script = File.ReadAllText(Path.Combine(
            root, "database", "Provisioning", "001_funding_opportunity_full_text.sql"));

        Assert.Contains("IF @@TRANCOUNT <> 0", script, StringComparison.Ordinal);
        Assert.Contains("Version = 18", script, StringComparison.Ordinal);
        Assert.Contains("WITH ACCENT_SENSITIVITY = OFF", script, StringComparison.Ordinal);
        Assert.Contains("CHANGE_TRACKING AUTO, STOPLIST = SYSTEM", script,
            StringComparison.Ordinal);
        Assert.Contains("has_crawl_completed = 1", script, StringComparison.Ordinal);
        Assert.Contains("TableFulltextFailCount", script, StringComparison.Ordinal);
        Assert.Contains("TableFullTextPopulateStatus') = 6", script, StringComparison.Ordinal);
        Assert.Contains("AUTHORIZATION dbo", script, StringComparison.Ordinal);
        Assert.Contains("object_id <> @PreflightObjectId", script, StringComparison.Ordinal);
        Assert.Contains("property_list_id IS NULL", script, StringComparison.Ordinal);
        Assert.Contains("statistical_semantics = 0", script, StringComparison.Ordinal);
    }

    [Fact]
    public void Funding_search_migration_keeps_security_freshness_and_wire_contracts_static()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var script = File.ReadAllText(Path.Combine(
            root, "database", "Migrations", "018_funding_search_and_favorites.sql"));

        Assert.DoesNotContain("CREATE FULLTEXT INDEX", script, StringComparison.Ordinal);
        Assert.Contains(
            "CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs",
            script,
            StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_FundingOpportunityTags", script, StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_FundingOpportunityOrganizationTypes", script,
            StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_FundingOpportunityLegalEntityTypes", script,
            StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_FundingOpportunityLanguages", script,
            StringComparison.Ordinal);
        Assert.Contains("WITH EXECUTE AS OWNER", script, StringComparison.Ordinal);
        Assert.Contains("FREETEXTTABLE", script, StringComparison.Ordinal);
        Assert.Contains("literal.TextRank", script, StringComparison.Ordinal);
        Assert.Contains("has_crawl_completed = 1", script, StringComparison.Ordinal);
        Assert.Contains("principal_id = DATABASE_PRINCIPAL_ID(N'dbo')", script,
            StringComparison.Ordinal);
        Assert.Contains("property_list_id IS NULL", script, StringComparison.Ordinal);
        Assert.Contains("statistical_semantics = 0", script, StringComparison.Ordinal);
        Assert.Contains("OR opportunities.GeographicScope = 2 OR EXISTS", script,
            StringComparison.Ordinal);
        Assert.Contains("@MatchedCount AS TotalCount, @SearchMode AS SearchMode", script,
            StringComparison.Ordinal);
        Assert.Contains("opportunities.Id DESC", script, StringComparison.Ordinal);
        Assert.Contains("links.EligibilityMode = 1", script, StringComparison.Ordinal);
        Assert.Contains("THEN opportunities.MaxAmount END", script, StringComparison.Ordinal);
        Assert.DoesNotContain(
            "THEN COALESCE(opportunities.MaxAmount, opportunities.MinAmount) END",
            script,
            StringComparison.Ordinal);
        Assert.Contains("opportunities.CloseAtUtc", script, StringComparison.Ordinal);
        Assert.Contains("opportunities.DeadlineType", script, StringComparison.Ordinal);
        Assert.Contains("opportunities.DeadlinePrecision", script, StringComparison.Ordinal);
        Assert.Contains("opportunities.ContentVersion", script, StringComparison.Ordinal);
        Assert.Contains("primarySource.ExternalId", script, StringComparison.Ordinal);
        Assert.Contains("AS PrimaryFunderPublicId", script, StringComparison.Ordinal);
    }

    [Fact]
    public void Full_text_runner_clears_uncertain_session_locks_and_inventories_catalogs()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var source = File.ReadAllText(Path.Combine(
            root,
            "src",
            "FundingPlatform.Infrastructure",
            "Persistence",
            "Migrations",
            "DatabaseMigrationRunner.cs"));

        Assert.Contains("FundingPlatform:DatabaseMigrations", source, StringComparison.Ordinal);
        Assert.Contains("FundingPlatform:FullTextProvisioning", source, StringComparison.Ordinal);
        Assert.Contains("SqlConnection.ClearPool(connection)", source, StringComparison.Ordinal);
        Assert.Contains("FULLTEXT_CATALOG", source, StringComparison.Ordinal);
        Assert.Contains("population-failed", source, StringComparison.Ordinal);
    }

    [Fact]
    public void Catalog_rejects_duplicate_sequences()
    {
        using var repository = TemporaryMigrationRepository.Create();
        repository.WriteMigration("001_first.sql", "SELECT 1;");
        repository.WriteMigration("001_second.sql", "SELECT 2;");

        var exception = Assert.Throws<MigrationException>(
            () => SqlScriptCatalog.DiscoverMigrations(repository.Root));

        Assert.Equal("duplicate_script_sequence", exception.Code);
        Assert.Equal("001", exception.Item);
    }

    [Theory]
    [InlineData("1_short.sql")]
    [InlineData("000_zero.sql")]
    [InlineData("001 bad.sql")]
    [InlineData("001_name.SQL")]
    public void Catalog_rejects_invalid_sql_file_names(string fileName)
    {
        using var repository = TemporaryMigrationRepository.Create();
        repository.WriteMigration(fileName, "SELECT 1;");

        var exception = Assert.Throws<MigrationException>(
            () => SqlScriptCatalog.DiscoverMigrations(repository.Root));

        Assert.Equal("invalid_script_name", exception.Code);
    }

    [Fact]
    public void Catalog_rejects_uppercase_sql_extension_on_case_sensitive_file_systems()
    {
        using var repository = TemporaryMigrationRepository.Create();
        repository.WriteMigration("001_name.SQL", "SELECT 1;");

        var exception = Assert.Throws<MigrationException>(
            () => SqlScriptCatalog.DiscoverMigrations(repository.Root));

        Assert.Equal("invalid_script_name", exception.Code);
    }

    [Fact]
    public void Solution_root_is_found_from_a_nested_directory()
    {
        using var repository = TemporaryMigrationRepository.Create();
        var nested = Path.Combine(repository.Root, "src", "nested");
        Directory.CreateDirectory(nested);

        Assert.Equal(repository.Root, SolutionRootLocator.Find(nested));
    }

    [Theory]
    [InlineData("res", true)]
    [InlineData("RES", true)]
    [InlineData(" res ", true)]
    [InlineData("master", false)]
    [InlineData(null, false)]
    public void Database_guard_accepts_only_res(string? databaseName, bool expected)
    {
        Assert.Equal(expected, MigrationSafety.IsExpectedDatabase(databaseName));
    }

    [Fact]
    public void Empty_history_rejects_prefixed_objects_but_ignores_only_history_table()
    {
        DatabaseObjectInfo[] objects =
        [
            new("USER_TABLE", MigrationSafety.HistoryTableName),
            new("PRIMARY_KEY_CONSTRAINT", MigrationSafety.HistoryPrimaryKeyName),
            new("USER_TABLE", "FundingPlatform_Organizations"),
            new("USER_DEFINED_TYPE", "FundingPlatform_BigIntIdList"),
            new("FULLTEXT_CATALOG", "FundingPlatform_FundingSearchCatalog")
        ];

        var collisions = MigrationSafety.FindBaselineCollisions(0, true, objects);

        Assert.Equal(3, collisions.Count);
        Assert.DoesNotContain(collisions, item => item.Name == MigrationSafety.HistoryTableName);
        Assert.DoesNotContain(collisions, item => item.Name == MigrationSafety.HistoryPrimaryKeyName);
    }

    [Fact]
    public void Empty_history_allows_exactly_its_table_and_primary_key_metadata()
    {
        DatabaseObjectInfo[] objects =
        [
            new("USER_TABLE", MigrationSafety.HistoryTableName),
            new("PRIMARY_KEY_CONSTRAINT", MigrationSafety.HistoryPrimaryKeyName)
        ];

        Assert.Empty(MigrationSafety.FindBaselineCollisions(0, true, objects));
    }

    [Fact]
    public void Missing_history_does_not_ignore_objects_that_reuse_metadata_names()
    {
        DatabaseObjectInfo[] objects =
        [
            new("USER_TABLE", MigrationSafety.HistoryTableName),
            new("PRIMARY_KEY_CONSTRAINT", MigrationSafety.HistoryPrimaryKeyName)
        ];

        Assert.Equal(2, MigrationSafety.FindBaselineCollisions(0, false, objects).Count);
    }

    [Fact]
    public void Existing_history_disables_baseline_collision_guard()
    {
        var collisions = MigrationSafety.FindBaselineCollisions(
            1,
            true,
            [new DatabaseObjectInfo("USER_TABLE", "FundingPlatform_Organizations")]);

        Assert.Empty(collisions);
    }

    [Fact]
    public void History_detects_a_changed_checksum()
    {
        var local = new SqlScript(1, "initial", "001_initial.sql", "new-checksum", ["SELECT 1;"]);
        var applied = new AppliedMigration(1, "initial", "old-checksum", DateTime.UtcNow);

        var item = Assert.Single(MigrationHistory.BuildStatus([local], [applied]));
        var exception = Assert.Throws<MigrationException>(
            () => MigrationHistory.EnsureConsistent([local], [applied]));

        Assert.Equal(MigrationState.ChecksumChanged, item.State);
        Assert.Equal("migration_checksum_changed", exception.Code);
        Assert.Equal("001", exception.Item);
    }

    [Fact]
    public void History_detects_an_applied_migration_missing_locally()
    {
        var applied = new AppliedMigration(2, "removed", "checksum", DateTime.UtcNow);

        var item = Assert.Single(MigrationHistory.BuildStatus([], [applied]));
        var exception = Assert.Throws<MigrationException>(
            () => MigrationHistory.EnsureConsistent([], [applied]));

        Assert.Equal(MigrationState.MissingLocalScript, item.State);
        Assert.Equal("applied_migration_missing_locally", exception.Code);
    }

    [Fact]
    public void Funding_editorial_public_SQL_is_fail_closed_and_external_import_never_autopublishes()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var script = File.ReadAllText(Path.Combine(
            root, "database", "Migrations", "010_funders_editorial_workflow.sql"));
        var publicList = ExtractProcedure(
            script, "dbo.FundingPlatform_usp_FundingOpportunity_Public_List");
        var publicDetail = ExtractProcedure(
            script, "dbo.FundingPlatform_usp_FundingOpportunity_Public_GetBySlug");
        var stageExternal = ExtractProcedure(
            script, "dbo.FundingPlatform_usp_FundingOpportunity_StageExternal");

        Assert.Contains(
            "opportunities.PublicationStatus = 2 AND opportunities.IsActive = 1",
            publicList,
            StringComparison.Ordinal);
        Assert.Contains(
            "opportunities.PublicationStatus = 2",
            publicDetail,
            StringComparison.Ordinal);
        Assert.Contains(
            "opportunities.IsActive = 1",
            publicDetail,
            StringComparison.Ordinal);
        Assert.Contains("FundingOpportunityStagedRevisions", stageExternal,
            StringComparison.Ordinal);
        Assert.Contains("published-protected", stageExternal, StringComparison.Ordinal);
        Assert.DoesNotContain("PublicationStatus = 2", stageExternal,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Governed_staging_requires_the_leased_source_id_and_provider_code()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var script = File.ReadAllText(Path.Combine(
            root, "database", "Migrations", "016_governed_document_extraction.sql"));
        const string marker =
            "CREATE PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_StageExternal";
        var start = script.IndexOf(marker, StringComparison.Ordinal);
        Assert.True(start >= 0, "Migration 016 is missing the governed staging wrapper.");
        var end = script.IndexOf("\nGO\n", start, StringComparison.Ordinal);
        Assert.True(end > start, "The governed staging wrapper is not batch-terminated.");
        var wrapper = script[start..end];

        Assert.Contains("@FundingSourceId INT", wrapper, StringComparison.Ordinal);
        Assert.Contains("@ExpectedProviderCode NVARCHAR(100)", wrapper,
            StringComparison.Ordinal);
        Assert.Contains("source-identity-mismatch", wrapper, StringComparison.Ordinal);
        Assert.Contains("AcquisitionPolicyFingerprint", wrapper, StringComparison.Ordinal);
        Assert.DoesNotContain("INSERT INTO dbo.FundingPlatform_FundingSources", wrapper,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Source_document_admin_detail_exposes_only_safe_retention_state()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var script = File.ReadAllText(Path.Combine(
            root, "database", "Migrations", "016_governed_document_extraction.sql"));
        var procedure = ExtractProcedure(
            script, "dbo.FundingPlatform_usp_SourceDocument_Get");

        Assert.Contains("documents.ContentRetentionStatus", procedure,
            StringComparison.Ordinal);
        Assert.Contains("documents.RetentionUntilUtc", procedure,
            StringComparison.Ordinal);
        Assert.Contains("documents.ContentDeletionRequestedAtUtc", procedure,
            StringComparison.Ordinal);
        Assert.Contains("documents.ContentRetentionLastErrorCode", procedure,
            StringComparison.Ordinal);
        Assert.DoesNotContain("TrustedBlobObjectName", procedure,
            StringComparison.Ordinal);
        Assert.DoesNotContain("documents.ContentHash", procedure,
            StringComparison.Ordinal);
        Assert.DoesNotContain("documents.BlobETag", procedure,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Funding_source_policy_operator_procedure_is_audited_and_hash_idempotent()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var script = File.ReadAllText(Path.Combine(
            root, "database", "Migrations", "016_governed_document_extraction.sql"));
        var procedure = ExtractProcedure(
            script, "dbo.FundingPlatform_usp_FundingSourceAcquisitionPolicy_Upsert");

        Assert.Contains("@SuperAdminUserPublicId UNIQUEIDENTIFIER", procedure,
            StringComparison.Ordinal);
        Assert.Contains("@AllowedHostsJson NVARCHAR(MAX)", procedure,
            StringComparison.Ordinal);
        Assert.Contains("@AllowedEndpointsJson NVARCHAR(MAX)", procedure,
            StringComparison.Ordinal);
        Assert.Contains("@IdempotencyKeyHash BINARY(32)", procedure,
            StringComparison.Ordinal);
        Assert.Contains("@RequestHash BINARY(32)", procedure,
            StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_usp_AdminActor_Lock", procedure,
            StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_FundingSourceAcquisitionPolicyEvents", procedure,
            StringComparison.Ordinal);
    }

    private static string ExtractProcedure(string script, string procedureName)
    {
        var start = script.IndexOf(
            $"CREATE OR ALTER PROCEDURE {procedureName}", StringComparison.Ordinal);
        Assert.True(start >= 0, $"Migration 010 is missing {procedureName}.");
        var end = script.IndexOf("\nGO\n", start, StringComparison.Ordinal);
        Assert.True(end > start, $"Migration 010 does not terminate {procedureName} with GO.");
        return script[start..end];
    }

    private sealed class TemporaryMigrationRepository : IDisposable
    {
        private TemporaryMigrationRepository(string root)
        {
            Root = root;
        }

        public string Root { get; }

        public static TemporaryMigrationRepository Create(
            bool includeTests = false,
            bool includeProvisioning = false)
        {
            var root = Path.Combine(Path.GetTempPath(), $"funding-migrations-{Guid.NewGuid():N}");
            Directory.CreateDirectory(Path.Combine(root, "database", "Migrations"));
            if (includeTests)
            {
                Directory.CreateDirectory(Path.Combine(root, "database", "Tests"));
            }
            if (includeProvisioning)
            {
                Directory.CreateDirectory(Path.Combine(root, "database", "Provisioning"));
            }

            File.WriteAllText(Path.Combine(root, SolutionRootLocator.SolutionFileName), string.Empty);
            return new TemporaryMigrationRepository(root);
        }

        public void WriteMigration(string fileName, string contents) =>
            File.WriteAllText(Path.Combine(Root, "database", "Migrations", fileName), contents);

        public void WriteTest(string fileName, string contents) =>
            File.WriteAllText(Path.Combine(Root, "database", "Tests", fileName), contents);

        public void WriteProvisioning(string fileName, string contents) =>
            File.WriteAllText(
                Path.Combine(Root, "database", "Provisioning", fileName), contents);

        public void Dispose() => Directory.Delete(Root, recursive: true);
    }
}
