using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class ProjectAssetDefenderMigrationTests
{
    [Fact]
    public void Migration_and_smoke_are_discoverable_forward_only_and_azure_sql_valid()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root)
            .Single(script => script.Sequence == 37);
        var smoke = SqlScriptCatalog.DiscoverTests(root)
            .Single(script => script.Sequence == 37);
        var migrationSql = Read(root, "database", "Migrations", migration.FileName);
        var smokeSql = Read(root, "database", "Tests", smoke.FileName);

        Assert.Equal("project_asset_defender_pipeline", migration.Name);
        Assert.Equal("project_asset_defender_pipeline_smoke", smoke.Name);
        Assert.Equal(13, migration.Batches.Count);
        Assert.Single(smoke.Batches);
        AssertValidAzureSql(migration.FileName, migration.Batches);
        AssertValidAzureSql(smoke.FileName, smoke.Batches);
        Assert.Contains("requires migrations 001-036", migrationSql,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("DROP TABLE", migrationSql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("TRUNCATE TABLE", migrationSql, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("ROLLBACK TRANSACTION FP_Smoke037", smokeSql,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Trust_and_receipts_are_workload_scoped_and_data_minimized()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var sql = Read(root, "database", "Migrations",
            "037_project_asset_defender_pipeline.sql");
        var receipts = Between(
            sql,
            "CREATE TABLE dbo.FundingPlatform_ProjectAssetDefenderReceipts",
            "CREATE INDEX FundingPlatform_IX_ProjectAssetDefenderReceipts_Asset");
        var sourceReceipt = Procedure(sql,
            "FundingPlatform_usp_SourceDocumentDefenderReceipt_Record");
        var projectReceipt = Procedure(sql,
            "FundingPlatform_usp_ProjectAssetDefenderReceipt_Record");

        Assert.Contains("ADD WorkloadKind TINYINT", sql, StringComparison.Ordinal);
        Assert.Contains("CHECK (WorkloadKind IN (1, 2))", sql, StringComparison.Ordinal);
        Assert.Contains("UNIQUE (WorkloadKind, Provider, TenantId", sql,
            StringComparison.Ordinal);
        Assert.Contains("UNIQUE (Id, WorkloadKind)", sql, StringComparison.Ordinal);
        Assert.Contains("FOREIGN KEY (TrustPolicyId, WorkloadKind)", receipts,
            StringComparison.Ordinal);
        Assert.Contains("CHECK (Provider = 1 AND WorkloadKind = 2)", receipts,
            StringComparison.Ordinal);
        Assert.DoesNotContain("PayloadJson", receipts, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("MalwareNames", receipts, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Sas", receipts, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("WHERE WorkloadKind = 1 AND Provider = 1", sourceReceipt,
            StringComparison.Ordinal);
        Assert.Contains("WHERE WorkloadKind = 2 AND Provider = 1", projectReceipt,
            StringComparison.Ordinal);
        Assert.Contains("Raw Event Grid payloads, SAS values and malware names are deliberately excluded",
            sql, StringComparison.Ordinal);
    }

    [Fact]
    public void Scan_transitions_revoke_exact_versions_and_watchdog_is_fail_closed()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var sql = Read(root, "database", "Migrations",
            "037_project_asset_defender_pipeline.sql");
        var apply = Procedure(sql, "FundingPlatform_usp_ProjectAsset_ApplyScanResult");
        var watchdog = Procedure(sql, "FundingPlatform_usp_ProjectAssetScan_WatchdogTimeout");

        Assert.Contains("(@ScanProvider = 1 AND @TrustedBlobVersionId IS NULL)", apply,
            StringComparison.Ordinal);
        Assert.Contains("@StoredStorageStatus = 2", apply, StringComparison.Ordinal);
        Assert.Contains("@StoredScanStatus = 1", apply, StringComparison.Ordinal);
        Assert.Contains("@ToStatus IN (2, 3, 4)", apply, StringComparison.Ordinal);
        Assert.Contains("TrustedBlobContainer = NULL", apply, StringComparison.Ordinal);
        Assert.Contains("TrustedBlobVersionId = NULL", apply, StringComparison.Ordinal);
        Assert.Contains("IsCover = 0", apply, StringComparison.Ordinal);
        Assert.Contains("RevokedTrustedBlobVersionId", apply, StringComparison.Ordinal);
        Assert.Contains("N'ProjectAssetScanTrustRevoked'", apply, StringComparison.Ordinal);
        Assert.DoesNotContain("@ProjectId AS projectId", apply, StringComparison.OrdinalIgnoreCase);

        Assert.Contains("assets.ScanProvider = 1", watchdog, StringComparison.Ordinal);
        Assert.Contains("assets.StorageStatus = 1", watchdog, StringComparison.Ordinal);
        Assert.Contains("assets.ScanStatus = 0", watchdog, StringComparison.Ordinal);
        Assert.Contains("N'ProjectAssetScanTimedOut'", watchdog, StringComparison.Ordinal);
        Assert.Contains("ReportedContentHash IS NULL", sql, StringComparison.Ordinal);
    }

    [Fact]
    public void Project_asset_outbox_facts_are_terminalized_by_a_closed_non_command_sink()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var sql = Read(root, "database", "Migrations",
            "037_project_asset_defender_pipeline.sql");
        var sink = Procedure(sql, "FundingPlatform_usp_OutboxAuditEvents_Acknowledge");
        var eventTypes = new[]
        {
            "ProjectAssetUploadIntentCreated",
            "ProjectAssetUploadIntentRejected",
            "ProjectAssetFinalized",
            "ProjectAssetQuarantined",
            "ProjectAssetScanCompleted",
            "ProjectAssetMetadataUpdated",
            "ProjectAssetsReordered",
            "ProjectAssetDeleted",
            "ProjectAssetScanTrustRevoked",
            "ProjectAssetScanTimedOut"
        };

        Assert.Contains("FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre037", sql,
            StringComparison.Ordinal);
        Assert.All(eventTypes, eventType =>
            Assert.Contains($"N'{eventType}'", sink, StringComparison.Ordinal));
        Assert.Contains("OPENJSON(PayloadJson)", sink, StringComparison.Ordinal);
        Assert.Contains("projects.Id = TRY_CONVERT(BIGINT, messages.AggregateId)", sink,
            StringComparison.Ordinal);
        Assert.Contains("projects.PublicId = TRY_CONVERT(UNIQUEIDENTIFIER", sink,
            StringComparison.Ordinal);
        Assert.DoesNotContain("ImportRunRequested", sink, StringComparison.Ordinal);
        Assert.DoesNotContain("SourceDocumentExtractionRequested", sink,
            StringComparison.Ordinal);
        Assert.Contains("SET @AcknowledgedCount = @PreviousCount + @CurrentCount", sink,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Only_the_general_worker_receives_the_three_new_pipeline_procedures()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var sql = Read(root, "database", "Migrations",
            "037_project_asset_defender_pipeline.sql");
        var grants = sql[sql.IndexOf(
            "GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Record",
            StringComparison.Ordinal)..];

        Assert.Equal(3, Count(grants, "GRANT EXECUTE ON OBJECT::"));
        Assert.Equal(3, Count(grants, "TO FundingPlatform_GeneralWorkerRole;"));
        Assert.DoesNotContain("TO FundingPlatform_ApiRuntimeRole;", grants,
            StringComparison.Ordinal);
        Assert.Contains("worker procedures must not be API callable", grants,
            StringComparison.Ordinal);
        Assert.Contains(")) <> 162", grants, StringComparison.Ordinal);
        Assert.Contains(")) <> 53", grants, StringComparison.Ordinal);
    }

    private static string Procedure(string sql, string name)
    {
        var create = $"CREATE PROCEDURE dbo.{name}";
        var createOrAlter = $"CREATE OR ALTER PROCEDURE dbo.{name}";
        var start = sql.LastIndexOf(createOrAlter, StringComparison.Ordinal);
        if (start < 0) start = sql.LastIndexOf(create, StringComparison.Ordinal);
        Assert.True(start >= 0, $"Procedure {name} was not found.");
        var end = sql.IndexOf("\nGO\n", start, StringComparison.Ordinal);
        Assert.True(end > start, $"Procedure {name} has no batch boundary.");
        return sql[start..end];
    }

    private static string Between(string value, string startToken, string endToken)
    {
        var start = value.IndexOf(startToken, StringComparison.Ordinal);
        var end = value.IndexOf(endToken, start, StringComparison.Ordinal);
        Assert.True(start >= 0 && end > start,
            $"Could not extract SQL section {startToken} -> {endToken}.");
        return value[start..end];
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
