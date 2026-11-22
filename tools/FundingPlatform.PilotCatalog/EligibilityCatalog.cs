using System.Text.Json;
using Dapper;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.Data.SqlClient;

internal static class EligibilityCatalog
{
    internal const string Confirmation = "PUBLISH-THREE-NEW-REVIEW-SEVEN-AND-ACTIVATE-ELIGIBILITY-V3";

    internal static async Task<int> RunAsync(string mode)
    {
        var local = mode == "--verify-eligibility-local";
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
        if (mode == "--apply-eligibility" && Environment.GetEnvironmentVariable("RF_CATALOG_ELIGIBILITY_CONFIRMATION") != Confirmation)
            return 64;
        var root = SolutionRootLocator.Find();
        var sql = await File.ReadAllTextAsync(Path.Combine(root, "database/Curation/chile-eligibility-catalog.sql"));
        var json = await File.ReadAllTextAsync(Path.Combine(root, "database/Curation/chile-eligibility-catalog-2026-11.json"));
        await using var connection = new SqlConnection(settings.ConnectionString);
        try { await connection.OpenAsync(); }
        catch (SqlException error) { Console.Error.WriteLine($"Catalog connection failed: SQL {error.Number}."); return 1; }
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync();
        try
        {
            if (local) await Seed(connection, transaction, root);
            var result = await connection.QuerySingleAsync<BatchResult>(sql, new { CatalogJson = json }, transaction, commandTimeout: 90);
            if (local)
            {
                if (result != new BatchResult(3, 7, 0)) throw new InvalidOperationException("Unexpected catalog counts.");
                var replay = await connection.QuerySingleAsync<BatchResult>(sql, new { CatalogJson = json }, transaction, commandTimeout: 90);
                if (replay != new BatchResult(0, 0, 10)) throw new InvalidOperationException("Catalog replay was not idempotent.");
                await connection.ExecuteAsync("""
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_MatchingProfiles WHERE EngineVersion=N'deterministic-sql-v3' AND IsActive=1)
                      THROW 57040,N'Catalog did not activate v3.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c3332026-0000-4000-8000-000000000002' AND FundingTypeId=5 AND MaxAmount=1500
                      AND JSON_VALUE(EligibilityPolicyJson,'$.projectBudgetLimit.amount') IS NULL)
                      THROW 57041,N'Equipment request was confused with project total budget.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c3332026-0000-4000-8000-000000000003'
                      AND Currency='CLP' AND MaxAmount=2000000 AND CloseAtUtc='2026-11-23T02:59:00')
                      THROW 57042,N'ITI amount or timezone is incorrect.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions r JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=r.FundingOpportunityId
                      WHERE o.PublicId='c3332026-0000-4000-8000-000000000003' AND r.RegionId=2)
                      THROW 57043,N'ITI must be scoped to Tarapaca.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c1112026-0000-4000-8000-000000000002'
                      AND JSON_VALUE(EligibilityPolicyJson,'$.projectBudgetLimit.amount')=N'10000'
                      AND JSON_VALUE(EligibilityPolicyJson,'$.projectBudgetLimit.inclusive')=N'false'
                      AND JSON_VALUE(EligibilityPolicyJson,'$.organizationAnnualBudgetLimit.amount')=N'50000')
                      THROW 57044,N'Pollination strict budget limits were lost.',1;
                    """, transaction: transaction);
                // Historical SQL acceptance must also work after the catalog activates v3.
                foreach (var test in SqlScriptCatalog.DiscoverTests(root).Where(x => x.Sequence is 13 or 20 or 32 or 64 or 65))
                    foreach (var batch in test.Batches)
                        await connection.ExecuteAsync(batch, transaction: transaction, commandTimeout: 120);
                if (await connection.ExecuteScalarAsync<string>("SELECT EngineVersion FROM dbo.FundingPlatform_MatchingProfiles WHERE IsActive=1", transaction: transaction) != "deterministic-sql-v3")
                    throw new InvalidOperationException("Smoke test changed the deployed active profile.");
            }
            if (mode == "--apply-eligibility") await transaction.CommitAsync();
            else await transaction.RollbackAsync();
            Console.WriteLine(JsonSerializer.Serialize(new { mode, result, committed = mode == "--apply-eligibility" }));
            if (local)
            {
                await using var stale = (SqlTransaction)await connection.BeginTransactionAsync();
                await Seed(connection, stale, root);
                await connection.ExecuteAsync("UPDATE dbo.FundingPlatform_FundingOpportunities SET ContentVersion=3 WHERE PublicId='c1112026-0000-4000-8000-000000000001';", transaction: stale);
                try
                {
                    await connection.QuerySingleAsync<BatchResult>(sql, new { CatalogJson = json }, stale);
                    throw new InvalidOperationException("Concurrent editorial changes were overwritten.");
                }
                catch (SqlException error) when (error.Number == 56914)
                {
                    if (await connection.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c3332026-0000-4000-8000-000000000001';", transaction: stale) != 0)
                        throw new InvalidOperationException("Rejected batch inserted data.");
                    await stale.RollbackAsync();
                }
                Console.WriteLine("Local catalog checks passed: readiness, replay, exact versions, strict caps, equipment type, timezone, region, active v3 and historical SQL smoke rollback.");
            }
            return 0;
        }
        catch (SqlException error)
        {
            if (transaction.Connection is not null) await transaction.RollbackAsync();
            Console.Error.WriteLine($"Catalog aborted: SQL {error.Number}, line {error.LineNumber}.");
            return 1;
        }
    }

    internal static async Task Seed(SqlConnection connection, SqlTransaction transaction, string root)
    {
        await ExpansionCatalog.SeedLocalFixture(connection, transaction, root);
        // Reproduce the exact deployed legacy encoding, then exercise the forward repair twice.
        await connection.ExecuteAsync("""
            UPDATE l SET SourceItemKeyHash=HASHBYTES('SHA2_256',l.ExternalId),CanonicalUrlHash=HASHBYTES('SHA2_256',l.SourceUrl)
            FROM dbo.FundingPlatform_FundingOpportunitySourceLinks l JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=l.FundingOpportunityId
            WHERE o.PublicId IN('c1112026-0000-4000-8000-000000000001','c1112026-0000-4000-8000-000000000002','c1112026-0000-4000-8000-000000000003');
            """, transaction: transaction);
        var repair = await File.ReadAllTextAsync(Path.Combine(root, "database/Migrations/065_pilot_source_identity_alignment.sql"));
        await connection.ExecuteAsync(repair, transaction: transaction);
        await connection.ExecuteAsync(repair, transaction: transaction);
        await connection.ExecuteAsync(await File.ReadAllTextAsync(Path.Combine(root, "database/Tests/065_pilot_source_identity_alignment_smoke.sql")), transaction: transaction);

        await connection.QuerySingleAsync(await File.ReadAllTextAsync(Path.Combine(root, "database/Curation/chile-catalog-expansion.sql")),
            new { CatalogJson = await File.ReadAllTextAsync(Path.Combine(root, "database/Curation/chile-catalog-expansion-2026-11.json")) }, transaction);
    }

    private sealed record BatchResult(int InsertedCount, int UpdatedCount, int AlreadyAppliedCount);
}
