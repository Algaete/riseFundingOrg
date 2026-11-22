using System.Text.Json;
using Dapper;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.Data.SqlClient;

internal static class ReviewedCatalog
{
    internal const string Confirmation = "PUBLISH-FIVE-REVIEWED-CHILE-OPPORTUNITIES-20261122";

    internal static async Task<int> RunAsync(string mode)
    {
        var local = mode == "--verify-resume-local";
        var apply = mode == "--apply-resume";
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
        if (apply && Environment.GetEnvironmentVariable("RF_CATALOG_REVIEWED_CONFIRMATION") != Confirmation) return 64;
        var root = SolutionRootLocator.Find();
        var sql = await File.ReadAllTextAsync(Path.Combine(root, "database/Curation/chile-reviewed-catalog-2026-11-22.sql"));
        var json = await File.ReadAllTextAsync(Path.Combine(root, "database/Curation/chile-reviewed-catalog-2026-11-22.json"));
        await using var connection = new SqlConnection(settings.ConnectionString);
        try { await connection.OpenAsync(); }
        catch (SqlException error) { Console.Error.WriteLine($"Catalog connection failed: SQL {error.Number}."); return 1; }
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync();
        try
        {
            if (local)
            {
                await EligibilityCatalog.Seed(connection, transaction, root);
                await connection.QuerySingleAsync(await File.ReadAllTextAsync(Path.Combine(root, "database/Curation/chile-eligibility-catalog.sql")),
                    new { CatalogJson = await File.ReadAllTextAsync(Path.Combine(root, "database/Curation/chile-eligibility-catalog-2026-11.json")) }, transaction);
            }
            var result = await connection.QuerySingleAsync<BatchResult>(sql, new { CatalogJson = json }, transaction, commandTimeout: 90);
            if (local)
            {
                if (result != new BatchResult(5, 0, 0)) throw new InvalidOperationException("Unexpected catalog counts.");
                var replay = await connection.QuerySingleAsync<BatchResult>(sql, new { CatalogJson = json }, transaction);
                if (replay != new BatchResult(0, 0, 5)) throw new InvalidOperationException("Replay changed the catalog.");
                using (var publicRows = await connection.QueryMultipleAsync(
                    "dbo.FundingPlatform_usp_FundingOpportunity_Public_List", new { PageSize = 100 }, transaction,
                    commandType: System.Data.CommandType.StoredProcedure))
                {
                    _ = await publicRows.ReadSingleAsync<long>();
                    var rows = (await publicRows.ReadAsync<PublicDeadline>()).ToDictionary(row => row.Slug);
                    if (rows["rufford-primer-fondo-conservacion"].DeadlineType != 2 ||
                        rows["sst-turismo-sostenible"].DeadlineType != 0 ||
                        rows["hawkwatch-rapaces-2026"].CloseAtUtc != new DateTime(2027, 1, 1, 6, 59, 0) ||
                        rows["fpa-forjadores-ambientales-2027"].DeadlineTimeZoneId != "America/Santiago")
                        throw new InvalidOperationException("Public SQL lost reviewed deadline fields.");
                }
                await connection.ExecuteAsync("""
                    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() p JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=p.FundingOpportunityId WHERE o.PublicId IN
                    ('c4442026-0000-4000-8000-000000000001','c4442026-0000-4000-8000-000000000002','c4442026-0000-4000-8000-000000000003','c4442026-0000-4000-8000-000000000004','c4442026-0000-4000-8000-000000000005'))<>5
                      THROW 57120,N'New opportunities are not ready.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c4442026-0000-4000-8000-000000000001' AND Currency='GBP' AND MaxAmount=7000 AND DeadlineType=2)
                      THROW 57121,N'Rufford first-stage amount or intake is incorrect.',1;
                    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId IN('c4442026-0000-4000-8000-000000000002','c4442026-0000-4000-8000-000000000003') AND DeadlineType=0 AND CloseDate IS NULL)<>2
                      THROW 57122,N'Unknown intake was promoted to open.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c4442026-0000-4000-8000-000000000005' AND CloseAtUtc='2026-12-15T17:00:00' AND MaxAmount=1000000 AND JSON_VALUE(EligibilityPolicyJson,'$.requiredCategoryIds[0]')='1')
                      THROW 57123,N'FPA deadline, amount or required focus is incorrect.',1;
                    IF (SELECT COUNT(DISTINCT l.FunderId) FROM dbo.FundingPlatform_FundingOpportunityFunders l JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=l.FundingOpportunityId WHERE o.PublicId IN('c2222026-0000-4000-8000-000000000002','c4442026-0000-4000-8000-000000000005') AND l.Role=1 AND l.IsActive=1)<>1
                      THROW 57124,N'MMA funder was duplicated.',1;
                    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingSources WHERE JSON_VALUE(ConfigurationJson,'$.curation')=N'chile-reviewed-catalog-2026-11-22' AND JSON_VALUE(ConfigurationJson,'$.manualOnly')=N'true' AND ScheduleCron IS NULL)<>5
                      THROW 57125,N'Unexpected automated source.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_MatchingProfiles WHERE IsActive=1 AND EngineVersion=N'deterministic-sql-v3')
                      THROW 57126,N'Matching profile changed.',1;
                    """, transaction: transaction);
                try
                {
                    await connection.QuerySingleAsync<BatchResult>(sql, new { CatalogJson = json.Replace("7000", "7001") }, transaction);
                    throw new InvalidOperationException("Changed replay was accepted.");
                }
                catch (SqlException error) when (error.Number == 56913) { }
            }
            if (apply) await transaction.CommitAsync(); else await transaction.RollbackAsync();
            Console.WriteLine(JsonSerializer.Serialize(new { mode, result, committed = apply }));
            return 0;
        }
        catch (SqlException error)
        {
            if (transaction.Connection is not null) await transaction.RollbackAsync();
            Console.Error.WriteLine($"Catalog aborted: SQL {error.Number}, line {error.LineNumber}.");
            return 1;
        }
    }

    private sealed record BatchResult(int InsertedCount, int UpdatedCount, int AlreadyAppliedCount);
    private sealed class PublicDeadline
    {
        public string Slug { get; init; } = "";
        public int DeadlineType { get; init; }
        public DateTime? CloseAtUtc { get; init; }
        public string? DeadlineTimeZoneId { get; init; }
    }
}
