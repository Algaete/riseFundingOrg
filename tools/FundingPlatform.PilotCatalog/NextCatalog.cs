using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.Data.SqlClient;

internal static class NextCatalog
{
    internal const string Confirmation = "PUBLISH-SIXTEEN-REVIEWED-CHILE-OPPORTUNITIES-20261123";
    private const string Batch = "chile-catalog-next-2026-11-23";

    internal static async Task<int> RunAsync(string mode)
    {
        var local = mode == "--verify-next-local";
        var apply = mode == "--apply-next";
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
        if (apply && Environment.GetEnvironmentVariable("RF_CATALOG_NEXT_CONFIRMATION") != Confirmation) return 64;

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
                foreach (var prior in new[] { "chile-eligibility-catalog", "chile-reviewed-catalog-2026-11-22", "chile-catalog-scale-2026-11-22" })
                {
                    var jsonName = prior == "chile-eligibility-catalog" ? prior + "-2026-11" : prior;
                    await connection.QuerySingleAsync(await File.ReadAllTextAsync(Path.Combine(folder, prior + ".sql")),
                        new { CatalogJson = await File.ReadAllTextAsync(Path.Combine(folder, jsonName + ".json")) }, transaction);
                }
            }

            // Read only the twenty-nine previously reviewed public catalog entries, never user profiles.
            var previousIds = new List<Guid>();
            foreach (var prior in new[] { "chile-eligibility-catalog-2026-11", "chile-reviewed-catalog-2026-11-22", "chile-catalog-scale-2026-11-22" })
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
                if (result != new BatchResult(16, 0, 0)) throw new InvalidOperationException("Unexpected catalog counts.");
                var replay = await connection.QuerySingleAsync<BatchResult>(sql, new { CatalogJson = json }, transaction);
                if (replay != new BatchResult(0, 0, 16)) throw new InvalidOperationException("Replay changed the catalog.");
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
                    if (count != 45) throw new InvalidOperationException("Unexpected public catalog total.");
                }
                await connection.ExecuteAsync("""
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c6662026-0000-4000-8000-000000000001' AND MaxAmount=10000000 AND CloseAtUtc='2026-12-03T18:00:00' AND Requirements LIKE N'%10%' AND EligibilityDescription LIKE N'%cinco%')
                      THROW 57320,N'FAE limits or school eligibility lost.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c6662026-0000-4000-8000-000000000003' AND Requirements LIKE N'%100.000%' AND FundingTypeId=2 AND MaxAmount=100000)
                      THROW 57321,N'MAPFRE capital threshold or award type lost.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c6662026-0000-4000-8000-000000000004' AND EligibilityDescription LIKE N'%51%' AND EligibilityDescription LIKE N'%cinco%' AND CloseAtUtc='2026-12-18T17:00:00' AND Restrictions LIKE N'%IA%')
                      THROW 57322,N'MoveNow control or AI restrictions lost.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c6662026-0000-4000-8000-000000000007' AND CloseAtUtc='2027-01-16T11:59:00' AND DeadlineTimeZoneId=N'Etc/GMT+12' AND Description LIKE N'%500%' AND Restrictions LIKE N'%IA%')
                      THROW 57323,N'Keeling cap or UTC date rollover lost.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c6662026-0000-4000-8000-000000000008' AND AmountStatus=0 AND MaxAmount IS NULL AND DeadlineType=2 AND FundingTypeId=2)
                      THROW 57324,N'Food Planet historical amount reused.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c6662026-0000-4000-8000-000000000009' AND MaxAmount=25000 AND Restrictions LIKE N'%5.000%' AND CloseAtUtc='2026-12-01T01:00:00')
                      THROW 57325,N'Box international capital limit lost.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c6662026-0000-4000-8000-000000000012' AND JSON_VALUE(EligibilityPolicyJson,'$.organizationAnnualBudgetLimit.amount')='350000' AND JSON_VALUE(EligibilityPolicyJson,'$.organizationAnnualBudgetLimit.inclusive')='false')
                      THROW 57326,N'Lush strict annual limit lost.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c6662026-0000-4000-8000-000000000014' AND MinimumOperatingYears=1 AND CloseAtUtc='2026-11-30T22:59:00' AND MaxAmount=10000)
                      THROW 57327,N'Terre portal deadline or NGO age lost.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c6662026-0000-4000-8000-000000000013' AND MaxAmount IS NULL AND Restrictions LIKE N'%exclusividad%' AND EligibilityDescription LIKE N'%1 de octubre%')
                      THROW 57330,N'SAVE THE NIGHT pool or eligibility was misrepresented.',1;
                    IF (SELECT COUNT(DISTINCT l.FunderId) FROM dbo.FundingPlatform_FundingOpportunityFunders l JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=l.FundingOpportunityId WHERE o.PublicId IN('c2222026-0000-4000-8000-000000000004','c6662026-0000-4000-8000-000000000001') AND l.Role=1 AND l.IsActive=1)<>1
                      THROW 57328,N'Culture Ministry funder was duplicated.',1;
                    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingSources WHERE JSON_VALUE(ConfigurationJson,'$.curation')=N'chile-catalog-next-2026-11-23' AND JSON_VALUE(ConfigurationJson,'$.manualOnly')=N'true' AND ScheduleCron IS NULL)<>16
                      THROW 57329,N'Unexpected automated source.',1;
                    """, transaction: transaction);
                try
                {
                    await connection.QuerySingleAsync<BatchResult>(sql, new { CatalogJson = json.Replace("10000000", "10000001") }, transaction);
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
