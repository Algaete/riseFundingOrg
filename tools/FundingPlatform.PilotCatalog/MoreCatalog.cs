using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.Data.SqlClient;

internal static class MoreCatalog
{
    internal const string Confirmation = "PUBLISH-TEN-REVIEWED-CHILE-OPPORTUNITIES-20261124";
    private const string Batch = "chile-catalog-more-2026-11-24";

    internal static async Task<int> RunAsync(string mode)
    {
        var local = mode == "--verify-more-local";
        var apply = mode == "--apply-more";
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
        if (apply && Environment.GetEnvironmentVariable("RF_CATALOG_MORE_CONFIRMATION") != Confirmation) return 64;

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
                foreach (var prior in new[] { "chile-eligibility-catalog", "chile-reviewed-catalog-2026-11-22", "chile-catalog-scale-2026-11-22", "chile-catalog-next-2026-11-23" })
                {
                    var jsonName = prior == "chile-eligibility-catalog" ? prior + "-2026-11" : prior;
                    await connection.QuerySingleAsync(await File.ReadAllTextAsync(Path.Combine(folder, prior + ".sql")),
                        new { CatalogJson = await File.ReadAllTextAsync(Path.Combine(folder, jsonName + ".json")) }, transaction);
                }
                await connection.QuerySingleAsync(await File.ReadAllTextAsync(Path.Combine(folder, "chile-catalog-regions-2026-11-23.sql")),
                    new { CatalogJson = await File.ReadAllTextAsync(Path.Combine(folder, "chile-catalog-regions-2026-11-23.json")) }, transaction);
            }

            // Read only the forty-five previously reviewed public catalog entries, never user profiles.
            var previousIds = new List<Guid>();
            foreach (var prior in new[] { "chile-eligibility-catalog-2026-11", "chile-reviewed-catalog-2026-11-22", "chile-catalog-scale-2026-11-22", "chile-catalog-next-2026-11-23" })
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
                if (result != new BatchResult(10, 0, 0)) throw new InvalidOperationException("Unexpected catalog counts.");
                var replay = await connection.QuerySingleAsync<BatchResult>(sql, new { CatalogJson = json }, transaction);
                if (replay != new BatchResult(0, 0, 10)) throw new InvalidOperationException("Replay changed the catalog.");
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
                    if (count != 55) throw new InvalidOperationException("Unexpected public catalog total.");
                }
                await connection.ExecuteAsync("""
                    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId IN ('c7772026-0000-4000-8000-000000000002','c7772026-0000-4000-8000-000000000003') AND CloseAtUtc='2026-12-01T23:59:00' AND JSON_VALUE(EligibilityPolicyJson,'$.organizationAnnualBudgetLimit.amount') IS NULL AND Requirements LIKE N'%priori%')<>2
                      THROW 57520,N'Thrive deadline or nonbinding budget preference changed.',1;
                    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId IN ('c7772026-0000-4000-8000-000000000004','c7772026-0000-4000-8000-000000000009','c7772026-0000-4000-8000-000000000010') AND JSON_VALUE(EligibilityPolicyJson,'$.projectBudgetLimit.amount')='20000' AND JSON_VALUE(EligibilityPolicyJson,'$.projectBudgetLimit.inclusive')='true' AND Restrictions LIKE N'%IA%')<>3
                      THROW 57521,N'Actiefonds project cap or AI restriction lost.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c7772026-0000-4000-8000-000000000006' AND MinAmount=10000 AND MaxAmount=900000 AND Description LIKE N'%contrato%')
                      THROW 57522,N'OTF Internet Freedom range or contract terms lost.',1;
                    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId IN ('c7772026-0000-4000-8000-000000000005','c7772026-0000-4000-8000-000000000007','c7772026-0000-4000-8000-000000000008') AND AmountStatus=0 AND MinAmount IS NULL AND MaxAmount IS NULL)<>3
                      THROW 57523,N'Typical amount was converted into a hard funding limit.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c7772026-0000-4000-8000-000000000010' AND MaxAmount=250 AND Restrictions LIKE N'%última hora%')
                      THROW 57524,N'Urgent action scope or maximum lost.',1;
                    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingSources WHERE JSON_VALUE(ConfigurationJson,'$.curation')=N'chile-catalog-more-2026-11-24' AND JSON_VALUE(ConfigurationJson,'$.manualOnly')=N'true' AND ScheduleCron IS NULL)<>10
                      THROW 57525,N'Unexpected automated funding source.',1;
                    IF (SELECT COUNT(DISTINCT l.FunderId) FROM dbo.FundingPlatform_FundingOpportunityFunders l JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=l.FundingOpportunityId WHERE o.PublicId IN ('c7772026-0000-4000-8000-000000000004','c7772026-0000-4000-8000-000000000009','c7772026-0000-4000-8000-000000000010') AND l.Role=1 AND l.IsActive=1)<>1
                      THROW 57526,N'Actiefonds identity duplicated between its lines.',1;
                    IF (SELECT COUNT(DISTINCT l.FunderId) FROM dbo.FundingPlatform_FundingOpportunityFunders l JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=l.FundingOpportunityId WHERE o.PublicId IN ('c5552026-0000-4000-8000-000000000010','c5552026-0000-4000-8000-000000000011','c7772026-0000-4000-8000-000000000008') AND l.Role=1 AND l.IsActive=1)<>1
                      THROW 57527,N'Existing EA Funds identity was not reused.',1;
                    """, transaction: transaction);
                using var batchDocument = JsonDocument.Parse(json);
                var targets = batchDocument.RootElement.GetProperty("funds").EnumerateArray().Select(f => f.GetProperty("slug").GetString()!).ToHashSet();
                for (var region = 1; region <= 16; region++)
                {
                    var discovery = await connection.QuerySingleAsync<string>("dbo.FundingPlatform_usp_FundingDiscovery_Search",
                        new { FiltersJson = JsonSerializer.Serialize(new { countryId = 152, regionId = region, onlyOpen = true, page = 1, pageSize = 50 }) },
                        transaction, commandType: CommandType.StoredProcedure);
                    using var page = JsonDocument.Parse(discovery);
                    var slugs = page.RootElement.GetProperty("items").EnumerateArray().Select(i => i.GetProperty("slug").GetString()!).ToHashSet();
                    if (!targets.IsSubsetOf(slugs)) throw new InvalidOperationException($"New opportunity missing from region {region}.");
                    if (slugs.Contains("gef-comunidades-chile-2026") != (region is 4 or 10 or 13))
                        throw new InvalidOperationException("Existing GEF territorial restriction changed.");
                }
                try
                {
                    await connection.QuerySingleAsync<BatchResult>(sql, new { CatalogJson = json.Replace("900000", "900001") }, transaction);
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
