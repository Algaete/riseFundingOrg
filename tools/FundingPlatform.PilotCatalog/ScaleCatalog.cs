using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.Data.SqlClient;

internal static class ScaleCatalog
{
    internal const string Confirmation = "PUBLISH-FOURTEEN-REVIEWED-CHILE-OPPORTUNITIES-20261122";
    private const string Batch = "chile-catalog-scale-2026-11-22";

    internal static async Task<int> RunAsync(string mode)
    {
        var local = mode == "--verify-scale-local";
        var apply = mode == "--apply-scale";
        var settings = new SqlConnectionStringBuilder(Environment.GetEnvironmentVariable(
            local ? "RF_CATALOG_SQL_TEST_CONNECTION" : "AZURE_SQL_CONNECTION_STRING") ?? "");
        if (local)
        {
            if (settings.DataSource != "127.0.0.1,14363" || settings.InitialCatalog != "res" ||
                Environment.GetEnvironmentVariable("RF_CATALOG_SQL_TEST_CONFIRMATION") != "DISPOSABLE-LOCAL-SQL") return 64;
        }
        else if (settings.InitialCatalog != "risefunding-dev" ||
                 settings.DataSource != "tcp:sql-rf-dev-ag26rf01-centralus.database.windows.net,1433" ||
                 !settings.Encrypt || settings.TrustServerCertificate) return 64;
        if (apply && Environment.GetEnvironmentVariable("RF_CATALOG_SCALE_CONFIRMATION") != Confirmation) return 64;

        var root = SolutionRootLocator.Find();
        var folder = Path.Combine(root, "database/Curation");
        var sql = await File.ReadAllTextAsync(Path.Combine(folder, Batch + ".sql"));
        var json = await File.ReadAllTextAsync(Path.Combine(folder, Batch + ".json"));
        await using var connection = new SqlConnection(settings.ConnectionString);
        try { await connection.OpenAsync(); }
        catch (SqlException error) { Console.Error.WriteLine($"Catalog connection failed: SQL {error.Number}."); return 1; }
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync();
        try
        {
            if (local)
            {
                await EligibilityCatalog.Seed(connection, transaction, root);
                foreach (var prior in new[] { "chile-eligibility-catalog", "chile-reviewed-catalog-2026-11-22" })
                {
                    var jsonName = prior == "chile-eligibility-catalog" ? prior + "-2026-11" : prior;
                    await connection.QuerySingleAsync(await File.ReadAllTextAsync(Path.Combine(folder, prior + ".sql")),
                        new { CatalogJson = await File.ReadAllTextAsync(Path.Combine(folder, jsonName + ".json")) }, transaction);
                }
            }

            // Read only the fifteen previously reviewed public catalog entries, never user profiles.
            var previousIds = new List<Guid>();
            foreach (var prior in new[] { "chile-eligibility-catalog-2026-11", "chile-reviewed-catalog-2026-11-22" })
            {
                using var document = JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(folder, prior + ".json")));
                previousIds.AddRange(document.RootElement.GetProperty("funds").EnumerateArray()
                    .Select(fund => fund.GetProperty("id").GetGuid()));
            }
            var before = await PriorSnapshot(connection, transaction, previousIds);
            var result = await connection.QuerySingleAsync<BatchResult>(sql, new { CatalogJson = json }, transaction, commandTimeout: 90);
            if (before != await PriorSnapshot(connection, transaction, previousIds))
                throw new InvalidOperationException("Previously reviewed catalog changed.");
            if (local)
            {
                if (result != new BatchResult(14, 0, 0)) throw new InvalidOperationException("Unexpected catalog counts.");
                var replay = await connection.QuerySingleAsync<BatchResult>(sql, new { CatalogJson = json }, transaction);
                if (replay != new BatchResult(0, 0, 14)) throw new InvalidOperationException("Replay changed the catalog.");
                using (var publicRows = await connection.QueryMultipleAsync(
                    "dbo.FundingPlatform_usp_FundingOpportunity_Public_List", new { PageSize = 100 }, transaction,
                    commandType: CommandType.StoredProcedure))
                {
                    var count = await publicRows.ReadSingleAsync<long>();
                    var rows = (await publicRows.ReadAsync<PublicRow>()).ToDictionary(row => row.Slug);
                    using var document = JsonDocument.Parse(json);
                    foreach (var fund in document.RootElement.GetProperty("funds").EnumerateArray())
                    {
                        var row = rows[fund.GetProperty("slug").GetString()!];
                        var deadline = fund.GetProperty("closeUtc");
                        var expectedUtc = deadline.ValueKind == JsonValueKind.Null ? (DateTime?)null : deadline.GetDateTime();
                        if (row.DeadlineType != fund.GetProperty("deadlineType").GetInt32() ||
                            row.CloseAtUtc != expectedUtc || row.Currency != fund.GetProperty("currency").GetString())
                            throw new InvalidOperationException("Public SQL lost reviewed fields.");
                    }
                    if (count != 29) throw new InvalidOperationException("Unexpected public catalog total.");
                }
                await connection.ExecuteAsync("""
                    DECLARE @Gef BIGINT=(SELECT Id FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c5552026-0000-4000-8000-000000000001');
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE Id=@Gef AND MaxAmount=15000000 AND MinAmount=15000000 AND MinimumOperatingYears=1 AND RequiresPriorExperience=1 AND RequiresCofunding=1 AND CloseDate='2026-12-22' AND CloseAtUtc IS NULL AND DeadlinePrecision=1)
                      THROW 57220,N'GEF eligibility or uncertain hour lost.',1;
                    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunityRegions WHERE FundingOpportunityId=@Gef AND RegionId IN(4,10,13))<>3 OR (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunityRegions WHERE FundingOpportunityId=@Gef)<>3
                      THROW 57221,N'GEF region scope broadened.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c5552026-0000-4000-8000-000000000004' AND MaxAmount=25000 AND JSON_VALUE(EligibilityPolicyJson,'$.organizationAnnualBudgetLimit.amount')='100000' AND JSON_VALUE(EligibilityPolicyJson,'$.organizationAnnualBudgetLimit.inclusive')='false' AND JSON_VALUE(EligibilityPolicyJson,'$.requiredCategoryIds[0]')='6')
                      THROW 57222,N'ITF budget or first-grant eligibility lost.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c5552026-0000-4000-8000-000000000005' AND AmountStatus=0 AND MaxAmount IS NULL AND Restrictions LIKE N'%IA%')
                      THROW 57223,N'Sophie amount or AI restriction lost.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c5552026-0000-4000-8000-000000000013' AND DeadlineType=0 AND CloseDate IS NULL)
                      THROW 57224,N'Unconfirmed intake was promoted to open.',1;
                    IF (SELECT COUNT(DISTINCT l.FunderId) FROM dbo.FundingPlatform_FundingOpportunityFunders l JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=l.FundingOpportunityId WHERE o.PublicId IN('c2222026-0000-4000-8000-000000000002','c4442026-0000-4000-8000-000000000005','c5552026-0000-4000-8000-000000000001') AND l.Role=1 AND l.IsActive=1)<>1
                      THROW 57225,N'MMA funder was duplicated.',1;
                    IF (SELECT COUNT(DISTINCT l.FunderId) FROM dbo.FundingPlatform_FundingOpportunityFunders l JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=l.FundingOpportunityId WHERE o.PublicId IN('c5552026-0000-4000-8000-000000000010','c5552026-0000-4000-8000-000000000011') AND l.Role=1 AND l.IsActive=1)<>1
                      THROW 57226,N'EA Funds funder was duplicated.',1;
                    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingSources WHERE JSON_VALUE(ConfigurationJson,'$.curation')=N'chile-catalog-scale-2026-11-22' AND JSON_VALUE(ConfigurationJson,'$.manualOnly')=N'true' AND ScheduleCron IS NULL)<>14
                      THROW 57227,N'Unexpected automated source.',1;
                    """, transaction: transaction);
                try
                {
                    await connection.QuerySingleAsync<BatchResult>(sql, new { CatalogJson = json.Replace("15000000", "15000001") }, transaction);
                    throw new InvalidOperationException("Changed replay was accepted.");
                }
                catch (SqlException error) when (error.Number == 56913) { }
            }
            if (apply) await transaction.CommitAsync(); else await transaction.RollbackAsync();
            Console.WriteLine(JsonSerializer.Serialize(new { mode, result, previousEntriesUnchanged = previousIds.Count, committed = apply }));
            return 0;
        }
        catch (SqlException error)
        {
            if (transaction.Connection is not null) await transaction.RollbackAsync();
            Console.Error.WriteLine($"Catalog aborted: SQL {error.Number}, line {error.LineNumber}.");
            return 1;
        }
    }

    private static Task<string> PriorSnapshot(SqlConnection connection, SqlTransaction transaction, List<Guid> ids) =>
        connection.QuerySingleAsync<string>("""
            SELECT (SELECT o.*,JSON_QUERY((SELECT ContentVersion,ContentHash FROM dbo.FundingPlatform_FundingOpportunityVersions v
              WHERE v.FundingOpportunityId=o.Id ORDER BY ContentVersion FOR JSON PATH)) AS versions
              FROM dbo.FundingPlatform_FundingOpportunities o WHERE o.PublicId IN @ids ORDER BY o.PublicId FOR JSON PATH)
            """, new { ids }, transaction);

    private sealed record BatchResult(int InsertedCount, int UpdatedCount, int AlreadyAppliedCount);
    private sealed class PublicRow
    {
        public string Slug { get; init; } = "";
        public string? Currency { get; init; }
        public int DeadlineType { get; init; }
        public DateTime? CloseAtUtc { get; init; }
    }
}
