using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.Data.SqlClient;

internal static class RegionalCatalog
{
    private const string Batch = "chile-catalog-regions-2026-11-23";
    private const string Confirmation = "CONFIRM-FAE-AND-MAPFRE-ALL-SIXTEEN-CHILE-REGIONS-20261123";

    internal static async Task<int> RunAsync(string mode)
    {
        var local = mode == "--verify-regions-local";
        var apply = mode == "--apply-regions";
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
        if (apply && Environment.GetEnvironmentVariable("RF_CATALOG_REGIONS_CONFIRMATION") != Confirmation) return 64;
        var root = SolutionRootLocator.Find();
        var folder = Path.Combine(root, "database/Curation");
        var json = await File.ReadAllTextAsync(Path.Combine(folder, Batch + ".json"));
        var sql = await File.ReadAllTextAsync(Path.Combine(folder, Batch + ".sql"));
        using var document = JsonDocument.Parse(json);
        var targets = document.RootElement.GetProperty("funds").EnumerateArray().Select(f => f.GetProperty("id").GetGuid()).ToArray();
        var targetSlugs = document.RootElement.GetProperty("funds").EnumerateArray().Select(f => f.GetProperty("slug").GetString()!).ToArray();
        await using var connection = new SqlConnection(settings.ConnectionString);
        try { await connection.OpenAsync(); }
        catch (SqlException error) { Console.Error.WriteLine($"Catalog connection failed: SQL {error.Number}."); return 1; }
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync();
        try
        {
            string[] prior = ["chile-eligibility-catalog-2026-11", "chile-reviewed-catalog-2026-11-22", "chile-catalog-scale-2026-11-22", "chile-catalog-next-2026-11-23"];
            var preserved = new List<Guid>();
            if (local) await EligibilityCatalog.Seed(connection, transaction, root);
            foreach (var name in prior)
            {
                var input = await File.ReadAllTextAsync(Path.Combine(folder, name + ".json"));
                using var data = JsonDocument.Parse(input);
                preserved.AddRange(data.RootElement.GetProperty("funds").EnumerateArray().Select(f => f.GetProperty("id").GetGuid()).Where(id => !targets.Contains(id)));
                if (local)
                {
                    var script = name == prior[0] ? "chile-eligibility-catalog" : name;
                    await connection.QuerySingleAsync(await File.ReadAllTextAsync(Path.Combine(folder, script + ".sql")), new { CatalogJson = input }, transaction);
                }
            }
            var before = await Snapshot(connection, transaction, preserved.ToArray());
            var originalTargets = await StableTargets(connection, transaction, targets);
            if (local)
            {
                var page = await Discovery(connection, transaction, 4);
                if (page.Intersect(targetSlugs).Any()) throw new InvalidOperationException("Regional regression fixture was not reproduced.");
            }
            var result = await connection.QuerySingleAsync<BatchResult>(sql, new { CatalogJson = json }, transaction, commandTimeout: 90);
            if (before != await Snapshot(connection, transaction, preserved.ToArray()) || originalTargets != await StableTargets(connection, transaction, targets))
                throw new InvalidOperationException("Regional review changed unrelated content or prior history.");
            if (local)
            {
                if (result != new BatchResult(0, 2, 0)) throw new InvalidOperationException("Unexpected correction counts.");
                var replay = await connection.QuerySingleAsync<BatchResult>(sql, new { CatalogJson = json }, transaction);
                if (replay != new BatchResult(0, 0, 2)) throw new InvalidOperationException("Regional replay changed the catalog.");
                for (var region = 1; region <= 16; region++)
                {
                    var slugs = await Discovery(connection, transaction, region);
                    if (!targetSlugs.All(slugs.Contains)) throw new InvalidOperationException($"Nationwide opportunity missing in region {region}.");
                    if (slugs.Contains("gef-comunidades-chile-2026") != (region is 4 or 10 or 13))
                        throw new InvalidOperationException("Unrelated GEF coverage broadened.");
                }
                await connection.ExecuteAsync("""
                    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId IN @targets AND ContentVersion=2)<>2
                      THROW 57420,N'Regional correction did not create version two.',1;
                    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunityRegions r JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=r.FundingOpportunityId WHERE o.PublicId IN @targets)<>32
                      THROW 57421,N'Regional coverage count differs.',1;
                    """, new { targets }, transaction);
                try
                {
                    await connection.QuerySingleAsync<BatchResult>(sql, new { CatalogJson = json.Replace("Cobertura nacional revisada", "Cobertura nacional alterada") }, transaction);
                    throw new InvalidOperationException("Changed regional replay was accepted.");
                }
                catch (SqlException error) when (error.Number == 57413) { }
            }
            if (apply) await transaction.CommitAsync(); else await transaction.RollbackAsync();
            Console.WriteLine(JsonSerializer.Serialize(new { mode, result, previousEntriesUnchanged = preserved.Count, originalTargetContentAndHistoryPreserved = true, committed = apply }));
            return 0;
        }
        catch (SqlException error)
        {
            if (transaction.Connection is not null) await transaction.RollbackAsync();
            Console.Error.WriteLine($"Regional review aborted: SQL {error.Number}, line {error.LineNumber}.");
            return 1;
        }
    }

    private static async Task<HashSet<string>> Discovery(SqlConnection connection, SqlTransaction transaction, int region)
    {
        var json = await connection.QuerySingleAsync<string>("dbo.FundingPlatform_usp_FundingDiscovery_Search",
            new { FiltersJson = JsonSerializer.Serialize(new { countryId = 152, regionId = region, onlyOpen = true, page = 1, pageSize = 50 }) },
            transaction, commandType: CommandType.StoredProcedure);
        using var document = JsonDocument.Parse(json);
        return document.RootElement.GetProperty("items").EnumerateArray().Select(item => item.GetProperty("slug").GetString()!).ToHashSet();
    }
    private static Task<string> Snapshot(SqlConnection connection, SqlTransaction transaction, Guid[] ids) =>
        connection.QuerySingleAsync<string>("""
            SELECT (SELECT o.*,JSON_QUERY((SELECT ContentVersion,ContentHash FROM dbo.FundingPlatform_FundingOpportunityVersions v
              WHERE v.FundingOpportunityId=o.Id ORDER BY ContentVersion FOR JSON PATH)) AS versions
              FROM dbo.FundingPlatform_FundingOpportunities o WHERE o.PublicId IN @ids ORDER BY o.PublicId FOR JSON PATH)
            """, new { ids }, transaction);
    private static Task<string> StableTargets(SqlConnection connection, SqlTransaction transaction, Guid[] ids) =>
        connection.QuerySingleAsync<string>("""
            SELECT (SELECT JSON_QUERY(JSON_MODIFY(JSON_MODIFY(JSON_MODIFY(JSON_MODIFY(JSON_MODIFY(
              (SELECT o.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),'$.ContentVersion',NULL),'$.ReviewedAtUtc',NULL),
              '$.LastVerifiedAtUtc',NULL),'$.UpdatedAtUtc',NULL),'$.RowVersion',NULL)) AS content,
              JSON_QUERY((SELECT SnapshotJson,ContentHash FROM dbo.FundingPlatform_FundingOpportunityVersions v
                WHERE v.FundingOpportunityId=o.Id AND ContentVersion=1 FOR JSON PATH)) AS originalVersion
              FROM dbo.FundingPlatform_FundingOpportunities o WHERE o.PublicId IN @ids ORDER BY o.PublicId FOR JSON PATH)
            """, new { ids }, transaction);
    private sealed record BatchResult(int InsertedCount, int UpdatedCount, int AlreadyAppliedCount);
}
