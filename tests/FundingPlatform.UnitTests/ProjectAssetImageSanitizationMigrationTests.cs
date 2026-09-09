using System.Text.RegularExpressions;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class ProjectAssetImageSanitizationMigrationTests
{
    private static readonly string[] SanitizerTerminalCodes =
    [
        "image-decode-rejected",
        "image-dimensions-rejected",
        "image-format-rejected",
        "image-frame-count-rejected",
        "image-output-too-large"
    ];

    [Fact]
    public void Migration_and_smoke_are_discoverable_forward_only_and_azure_sql_valid()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root)
            .Single(script => script.Sequence == 38);
        var smoke = SqlScriptCatalog.DiscoverTests(root)
            .Single(script => script.Sequence == 38);
        var migrationSql = Read(root, "database", "Migrations", migration.FileName);
        var smokeSql = Read(root, "database", "Tests", smoke.FileName);

        Assert.Equal("project_asset_image_sanitization", migration.Name);
        Assert.Equal("project_asset_image_sanitization_smoke", smoke.Name);
        Assert.Equal(8, migration.Batches.Count);
        Assert.Single(smoke.Batches);
        AssertValidAzureSql(migration.FileName, migration.Batches);
        AssertValidAzureSql(smoke.FileName, smoke.Batches);
        Assert.Contains("requires migrations 001-037", migrationSql,
            StringComparison.OrdinalIgnoreCase);

        var forbiddenForwardOnlyStatements = new[]
        {
            "DROP TABLE", "DROP COLUMN", "DROP PROCEDURE", "DROP FUNCTION",
            "DROP VIEW", "TRUNCATE TABLE"
        };
        Assert.All(forbiddenForwardOnlyStatements, statement =>
            Assert.DoesNotContain(statement, migrationSql, StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain("DELETE FROM dbo.FundingPlatform_ProjectAssets", migrationSql,
            StringComparison.OrdinalIgnoreCase);
        Assert.Contains("ROLLBACK TRANSACTION FP_Smoke038", smokeSql,
            StringComparison.Ordinal);
        Assert.Contains(
            "EXEC dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Finalize",
            smokeSql, StringComparison.Ordinal);
        Assert.Contains("ReceiptStatus = 1 AND WasReplay = 1", smokeSql,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Trusted_bytes_have_a_separate_complete_manifest_and_server_owned_timestamp()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var sql = Read(root, "database", "Migrations",
            "038_project_asset_image_sanitization.sql");
        var apply = Procedure(sql, "FundingPlatform_usp_ProjectAsset_ApplyScanResult");
        var trustedRead = Procedure(sql, "FundingPlatform_usp_ProjectAsset_GetTrustedContent");
        var list = Procedure(sql, "FundingPlatform_usp_ProjectAsset_List");
        var applySignature = apply[..apply.IndexOf("AS\nBEGIN", StringComparison.Ordinal)];
        var trustedColumns = new[]
        {
            "TrustedMimeType NVARCHAR(100) NULL",
            "TrustedContentLength BIGINT NULL",
            "TrustedContentHash BINARY(32) NULL",
            "TrustedPixelWidth INT NULL",
            "TrustedPixelHeight INT NULL",
            "TrustedProcessingVersion NVARCHAR(100) NULL",
            "TrustedCreatedAtUtc DATETIME2(3) NULL"
        };

        Assert.All(trustedColumns, column =>
            Assert.Contains(column, sql, StringComparison.Ordinal));
        Assert.Contains("FundingPlatform_CK_ProjectAssets_TrustedManifest", sql,
            StringComparison.Ordinal);
        Assert.Contains("TrustedContentHash IS NOT NULL", sql, StringComparison.Ordinal);
        Assert.Contains("TrustedCreatedAtUtc >= CreatedAtUtc", sql, StringComparison.Ordinal);
        Assert.Contains("TrustedProcessingVersion = N'skia-4.151.2-image-v1'", sql.Replace("''", "'", StringComparison.Ordinal),
            StringComparison.Ordinal);
        Assert.Contains("TrustedProcessingVersion = N'pdf-copy-v1'", sql.Replace("''", "'", StringComparison.Ordinal),
            StringComparison.Ordinal);

        Assert.Contains("@TrustedContentHash BINARY(32) = NULL", applySignature,
            StringComparison.Ordinal);
        Assert.Contains("@TrustedMimeType NVARCHAR(100) = NULL", applySignature,
            StringComparison.Ordinal);
        Assert.DoesNotContain("@TrustedCreatedAtUtc", applySignature,
            StringComparison.Ordinal);
        Assert.Contains("TrustedCreatedAtUtc = CASE WHEN @ToStatus = 1", apply,
            StringComparison.Ordinal);
        Assert.Contains("THEN @NowUtc END", apply, StringComparison.Ordinal);

        Assert.Contains("@TrustedContentHash AS TrustedContentHash", trustedRead,
            StringComparison.Ordinal);
        Assert.Contains("@TrustedMimeType AS TrustedMimeType", trustedRead,
            StringComparison.Ordinal);
        Assert.Contains("@TrustedCreatedAtUtc AS TrustedCreatedAtUtc", trustedRead,
            StringComparison.Ordinal);
        Assert.Contains("TrustedProcessingVersion", list, StringComparison.Ordinal);
        Assert.DoesNotContain("TrustedBlobObjectName AS", list, StringComparison.Ordinal);
        Assert.DoesNotContain("TrustedContentHash AS", list, StringComparison.Ordinal);

        Assert.DoesNotContain("SET VerifiedMimeType =", sql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("SET ContentLength =", sql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("SET ContentHash =", sql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("SET PixelWidth =", sql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("SET PixelHeight =", sql, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Existing_pdfs_are_manifested_and_legacy_trusted_images_are_revoked_fail_closed()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root)
            .Single(script => script.Sequence == 38);
        // The backfill is compiled after ALTER TABLE so new columns resolve on Azure SQL.
        var backfill = migration.Batches[0].Replace("''", "'", StringComparison.Ordinal);

        Assert.Contains("SET TrustedMimeType = LOWER(VerifiedMimeType)", backfill,
            StringComparison.Ordinal);
        Assert.Contains("TrustedContentLength = ContentLength", backfill,
            StringComparison.Ordinal);
        Assert.Contains("TrustedContentHash = ContentHash", backfill,
            StringComparison.Ordinal);
        Assert.Contains("TrustedProcessingVersion = N'pdf-copy-v1'", backfill,
            StringComparison.Ordinal);
        Assert.Contains("WHERE StorageStatus = 2 AND ScanStatus = 1 AND Kind = 1", backfill,
            StringComparison.Ordinal);

        Assert.Contains("DECLARE @LegacyImages TABLE", backfill, StringComparison.Ordinal);
        Assert.Contains("ScanResultCode = N'legacy-image-unsanitized'", backfill,
            StringComparison.Ordinal);
        Assert.Contains("WHERE assets.StorageStatus = 2 AND assets.ScanStatus = 1 AND assets.Kind = 0",
            backfill, StringComparison.Ordinal);
        Assert.Contains("StorageStatus = 3", backfill, StringComparison.Ordinal);
        Assert.Contains("ScanStatus = 3", backfill, StringComparison.Ordinal);
        Assert.Contains("ScanCompletedAtUtc = @MigrationUtc", backfill,
            StringComparison.Ordinal);
        Assert.Contains("TrustedBlobContainer = NULL", backfill, StringComparison.Ordinal);
        Assert.Contains("TrustedContentHash = NULL", backfill, StringComparison.Ordinal);
        Assert.Contains("TrustedProcessingVersion = NULL", backfill, StringComparison.Ordinal);
        Assert.Contains("IsCover = 0", backfill, StringComparison.Ordinal);
        Assert.Contains("deleted.TrustedBlobVersionId", backfill, StringComparison.Ordinal);
        Assert.Contains("deleted.TrustedBlobETag", backfill, StringComparison.Ordinal);
        Assert.Contains("N'legacy-unsanitized-v0'", backfill, StringComparison.Ordinal);
        Assert.Contains("1, 3, 1, legacy.QuarantineBlobETag", backfill,
            StringComparison.Ordinal);
        Assert.Contains("legacy.ProviderResultCode", backfill, StringComparison.Ordinal);
        Assert.Contains("N'ProjectAssetLegacyTrustRevoked'", backfill,
            StringComparison.Ordinal);
        Assert.Contains("legacy.AssetPublicId AS assetPublicId", backfill,
            StringComparison.Ordinal);
        Assert.DoesNotContain("legacy.ProjectId AS projectId", backfill,
            StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Only_five_sanitizer_failures_can_derive_an_effective_terminal_result()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var sql = Read(root, "database", "Migrations",
            "038_project_asset_image_sanitization.sql");
        var apply = Procedure(sql, "FundingPlatform_usp_ProjectAsset_ApplyScanResult");
        var finalize = Procedure(sql,
            "FundingPlatform_usp_ProjectAssetDefenderReceipt_Finalize");
        var actualCodes = Regex.Matches(apply, @"N'(image-[a-z0-9-]+)'")
            .Select(match => match.Groups[1].Value)
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal)
            .ToArray();

        Assert.Equal(SanitizerTerminalCodes, actualCodes);
        Assert.Contains("@ProviderObservedStatus TINYINT = NULL", apply,
            StringComparison.Ordinal);
        Assert.Contains("@ProviderResultCode NVARCHAR(100) = NULL", apply,
            StringComparison.Ordinal);
        Assert.Contains("@ProviderObservedStatus = 1 AND @ToStatus = 3", apply,
            StringComparison.Ordinal);
        Assert.Contains("SET @IsDerivedSanitizerFailure = 1", apply,
            StringComparison.Ordinal);
        Assert.Contains("FromStatus, ToStatus, ProviderObservedStatus", apply,
            StringComparison.Ordinal);
        Assert.Contains("ResultCode, ProviderResultCode", apply,
            StringComparison.Ordinal);
        Assert.Contains("@ResultCode, @ProviderResultCode", apply,
            StringComparison.Ordinal);
        Assert.Contains("@IsDerivedSanitizerFailure = 1 AND @StoredKind <> 0", apply,
            StringComparison.Ordinal);
        Assert.Contains("receipts.ProviderEventId COLLATE Latin1_General_100_BIN2", apply,
            StringComparison.Ordinal);
        Assert.Contains("receipts.PayloadHash = @PayloadHash", apply,
            StringComparison.Ordinal);
        Assert.Contains("receipts.BlobETag COLLATE Latin1_General_100_BIN2", apply,
            StringComparison.Ordinal);
        Assert.Contains("receipts.ReportedContentHash = @ReportedContentHash", apply,
            StringComparison.Ordinal);
        Assert.Contains("receipts.ToStatus = @ProviderObservedStatus", apply,
            StringComparison.Ordinal);
        Assert.Contains("receipts.ResultCode = @ProviderResultCode", apply,
            StringComparison.Ordinal);
        Assert.Contains("receipts.OccurredAtUtc = @OccurredAtUtc", apply,
            StringComparison.Ordinal);

        Assert.Contains("ProviderObservedStatus = @StoredToStatus", finalize,
            StringComparison.Ordinal);
        Assert.Contains("ProviderResultCode COLLATE Latin1_General_100_BIN2 =",
            finalize, StringComparison.Ordinal);
        Assert.Contains("@StoredResultCode COLLATE Latin1_General_100_BIN2", finalize,
            StringComparison.Ordinal);
        Assert.DoesNotContain("AND ToStatus = @StoredToStatus AND ResultCode =",
            finalize, StringComparison.Ordinal);
    }

    [Fact]
    public void Exact_trusted_blob_and_manifest_are_captured_before_late_revocation()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var sql = Read(root, "database", "Migrations",
            "038_project_asset_image_sanitization.sql");
        var apply = Procedure(sql, "FundingPlatform_usp_ProjectAsset_ApplyScanResult");
        var revokedManifestColumns = new[]
        {
            "RevokedTrustedMimeType",
            "RevokedTrustedContentLength",
            "RevokedTrustedContentHash",
            "RevokedTrustedPixelWidth",
            "RevokedTrustedPixelHeight",
            "RevokedTrustedProcessingVersion",
            "RevokedTrustedCreatedAtUtc"
        };

        Assert.Contains("@RevokedVersionId = TrustedBlobVersionId", apply,
            StringComparison.Ordinal);
        Assert.Contains("OR @RevokedVersionId IS NULL", apply, StringComparison.Ordinal);
        Assert.All(revokedManifestColumns, column =>
            Assert.Contains(column, apply, StringComparison.Ordinal));
        Assert.Contains("TrustedBlobVersionId = NULL", apply, StringComparison.Ordinal);
        Assert.Contains("TrustedMimeType = NULL", apply, StringComparison.Ordinal);
        Assert.Contains("TrustedContentLength = NULL", apply, StringComparison.Ordinal);
        Assert.Contains("TrustedContentHash = NULL", apply, StringComparison.Ordinal);
        Assert.Contains("TrustedPixelWidth = NULL", apply, StringComparison.Ordinal);
        Assert.Contains("TrustedPixelHeight = NULL", apply, StringComparison.Ordinal);
        Assert.Contains("TrustedProcessingVersion = NULL", apply, StringComparison.Ordinal);
        Assert.Contains("TrustedCreatedAtUtc = NULL", apply, StringComparison.Ordinal);
        Assert.Contains("IsCover = 0", apply, StringComparison.Ordinal);
        Assert.Contains("N'ProjectAssetScanTrustRevoked'", apply, StringComparison.Ordinal);
        Assert.DoesNotContain("@ProjectId AS projectId", apply,
            StringComparison.OrdinalIgnoreCase);

        Assert.Contains("FROM dbo.FundingPlatform_ProjectAssetScanEvents AS superseding", apply,
            StringComparison.Ordinal);
        Assert.Contains("superseding.FromStatus = 1", apply, StringComparison.Ordinal);
        Assert.Contains("superseding.RevokedTrustedContentHash =", apply,
            StringComparison.Ordinal);
        Assert.Contains("@TrustedContentHash", apply, StringComparison.Ordinal);
        Assert.Contains("ResultCode COLLATE Latin1_General_100_BIN2 <>", sql,
            StringComparison.Ordinal);
        Assert.Contains("NULLIF(LTRIM(RTRIM(RevokedTrustedBlobVersionId)), N'')",
            sql.Replace("''", "'", StringComparison.Ordinal), StringComparison.Ordinal);
    }

    [Fact]
    public void Legacy_revocation_outbox_is_exact_non_command_and_permissions_do_not_expand()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var sql = Read(root, "database", "Migrations",
            "038_project_asset_image_sanitization.sql");
        var sink = Procedure(sql, "FundingPlatform_usp_OutboxAuditEvents_Acknowledge");
        var payloadFields = new[]
        {
            "eventId", "assetPublicId", "scanStatus", "storageStatus", "resultCode",
            "revokedTrustedBlobContainer", "revokedTrustedBlobObjectName",
            "revokedTrustedBlobETag", "revokedTrustedBlobVersionId",
            "revokedTrustedMimeType", "revokedTrustedContentLength",
            "revokedTrustedContentHashSha256", "revokedTrustedPixelWidth",
            "revokedTrustedPixelHeight", "revokedTrustedProcessingVersion",
            "revokedTrustedCreatedAtUtc"
        };

        Assert.Contains("FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre038", sql,
            StringComparison.Ordinal);
        Assert.Contains("N'ProjectAssetLegacyTrustRevoked'", sink,
            StringComparison.Ordinal);
        Assert.Contains("messages.AggregateType COLLATE Latin1_General_100_BIN2 = N'ProjectAsset'",
            sink, StringComparison.Ordinal);
        Assert.Contains("messages.MessageId = TRY_CONVERT(UNIQUEIDENTIFIER", sink,
            StringComparison.Ordinal);
        Assert.Contains("scanEvents.EventId = messages.MessageId", sink,
            StringComparison.Ordinal);
        Assert.Contains("(SELECT COUNT_BIG(1) FROM OPENJSON(messages.PayloadJson)) = 16",
            sink, StringComparison.Ordinal);
        Assert.Contains("GROUP BY fields.[key] COLLATE Latin1_General_100_BIN2", sink,
            StringComparison.Ordinal);
        Assert.Contains("HAVING COUNT_BIG(1) <> 1", sink, StringComparison.Ordinal);
        Assert.All(payloadFields, field =>
            Assert.Contains($"N'{field}'", sink, StringComparison.Ordinal));
        Assert.Contains("SET @AcknowledgedCount = @PreviousCount + @CurrentCount", sink,
            StringComparison.Ordinal);
        Assert.DoesNotContain("ImportRunRequested", sink, StringComparison.Ordinal);
        Assert.DoesNotContain("SourceDocumentExtractionRequested", sink,
            StringComparison.Ordinal);

        Assert.DoesNotContain("GRANT EXECUTE ON OBJECT::", sql,
            StringComparison.OrdinalIgnoreCase);
        Assert.Contains(")) <> 162", sql, StringComparison.Ordinal);
        Assert.Contains(")) <> 53", sql, StringComparison.Ordinal);
        Assert.Contains("must not have direct sanitization table access", sql,
            StringComparison.Ordinal);
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

    private static string Read(string root, params string[] parts) =>
        File.ReadAllText(Path.Combine([root, .. parts]));

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
