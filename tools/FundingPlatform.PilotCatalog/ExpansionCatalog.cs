using System.Text.Json;
using Dapper;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.Data.SqlClient;

internal static class ExpansionCatalog
{
    internal const string Confirmation = "PUBLISH-FOUR-NEW-AND-CORRECT-FOUR-REVIEWED-FUNDS";

    internal static async Task<int> RunAsync(string mode)
    {
        var local = mode == "--verify-expansion-local";
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
        if (mode == "--apply-expansion" && Environment.GetEnvironmentVariable("RF_CATALOG_EXPANSION_CONFIRMATION") != Confirmation)
            return 64;

        var root = SolutionRootLocator.Find();
        var sql = await File.ReadAllTextAsync(Path.Combine(root, "database/Curation/chile-catalog-expansion.sql"));
        var json = await File.ReadAllTextAsync(Path.Combine(root, "database/Curation/chile-catalog-expansion-2026-11.json"));
        await using var connection = new SqlConnection(settings.ConnectionString);
        try { await connection.OpenAsync(); }
        catch (SqlException error)
        {
            Console.Error.WriteLine($"Catalog connection failed: SQL {error.Number}.");
            return 1;
        }
        if (mode == "--inspect-expansion")
        {
            var identities = await connection.QueryAsync("""
                SELECT PublicId,Name,WebsiteUrl,PublicationStatus,IsActive,ContentVersion
                FROM dbo.FundingPlatform_Funders WHERE NormalizedName IN
                  (N'FUNDACIÓN DESCÚBREME',N'MINISTERIO DEL MEDIO AMBIENTE',N'GLOBAL FUND FOR CHILDREN',
                   N'MINISTERIO DE LAS CULTURAS, LAS ARTES Y EL PATRIMONIO',N'NATIONAL INSTITUTE OF FOOD AND AGRICULTURE');
                """);
            Console.WriteLine(JsonSerializer.Serialize(identities));
            return 0;
        }
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync();
        try
        {
            if (local) await SeedLocalFixture(connection, transaction, root);
            var result = await connection.QuerySingleAsync<BatchResult>(sql, new { CatalogJson = json }, transaction, commandTimeout: 90);
            if (local)
            {
                if (result != new BatchResult(4, 4, 0)) throw new InvalidOperationException("Unexpected first apply counts.");
                var second = await connection.QuerySingleAsync<BatchResult>(sql, new { CatalogJson = json }, transaction, commandTimeout: 90);
                if (second != new BatchResult(0, 0, 8)) throw new InvalidOperationException("Repeat was not idempotent.");
                await connection.ExecuteAsync("""
                    IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
                      WHERE PublicId IN ('c1112026-0000-4000-8000-000000000001','c1112026-0000-4000-8000-000000000002','c1112026-0000-4000-8000-000000000003')
                        AND (MinimumOperatingYears IS NOT NULL OR RequiresPriorExperience IS NOT NULL))
                      THROW 56930,N'Unknown eligibility was invented.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c2222026-0000-4000-8000-000000000003'
                      AND DeadlineType=2 AND CloseDate IS NULL AND AmountStatus=2 AND RequiresLegalEntity IS NULL)
                      THROW 56931,N'EOI was misrepresented as a dated guaranteed grant.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c2222026-0000-4000-8000-000000000001'
                      AND Currency='CLP' AND MinAmount=7000000 AND MaxAmount=10000000 AND CloseAtUtc='2026-12-01T20:00:00')
                      THROW 56932,N'Local currency or deadline was altered.',1;
                    IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities o JOIN dbo.FundingPlatform_FundingOpportunityRegions r ON r.FundingOpportunityId=o.Id
                      WHERE o.PublicId='c2222026-0000-4000-8000-000000000001' AND r.RegionId IN(15,16))
                      THROW 56933,N'Excluded regions were broadened.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_Funders WHERE PublicId='c8ad4e91-28ad-f111-a6a7-000d3a912199' AND Name=N'Bureau of Emerging Threats')
                      THROW 56934,N'Shared legacy funder was altered.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_Funders WHERE PublicId='a528c3a2-6baa-f111-a6a7-3833c5d78f35' AND PublicationStatus=0 AND ContentVersion=2 AND WebsiteUrl=N'https://www.nifa.usda.gov')
                      THROW 56938,N'NIFA draft status was not preserved.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='e512d837-7ead-f111-a6a7-000d3a912199' AND PublicationStatus=4 AND IsActive=0)
                      THROW 56939,N'Out-of-scope opportunity was not archived.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityVersions v JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=v.FundingOpportunityId
                      WHERE o.PublicId='c1112026-0000-4000-8000-000000000001' AND v.ContentVersion=1)
                      THROW 56935,N'Prior version was lost.',1;
                    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities o JOIN dbo.FundingPlatform_FundingOpportunityFunders l ON l.FundingOpportunityId=o.Id AND l.Role=1 AND l.IsActive=1
                      JOIN dbo.FundingPlatform_Funders f ON f.Id=l.FunderId
                      WHERE o.PublicId='e512d837-7ead-f111-a6a7-000d3a912199' AND f.Name=N'National Institute of Food and Agriculture' AND f.WebsiteUrl=o.SponsorUrl)
                      THROW 56936,N'Primary funder correction failed.',1;
                    """, transaction: transaction);
            }
            if (mode == "--apply-expansion") await transaction.CommitAsync();
            else await transaction.RollbackAsync();
            Console.WriteLine(JsonSerializer.Serialize(new { mode, result, committed = mode == "--apply-expansion" }));
            if (local)
            {
                // A stale expected version must fail before touching even a new row.
                await using var stale = (SqlTransaction)await connection.BeginTransactionAsync();
                await SeedLocalFixture(connection, stale, root);
                await connection.ExecuteAsync("UPDATE dbo.FundingPlatform_FundingOpportunities SET ContentVersion=2 WHERE PublicId='c1112026-0000-4000-8000-000000000001';", transaction: stale);
                try
                {
                    await connection.QuerySingleAsync<BatchResult>(sql, new { CatalogJson = json }, stale);
                    throw new InvalidOperationException("Stale editorial version was overwritten.");
                }
                catch (SqlException error) when (error.Number == 56914)
                {
                    if (await connection.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='c2222026-0000-4000-8000-000000000001';", transaction: stale) != 0)
                        throw new InvalidOperationException("Rejected batch inserted data.");
                    await stale.RollbackAsync();
                }
                Console.WriteLine("Local checks passed: public readiness, idempotency, unknowns, EOI, currency, timezone, regions, funder identity, retained history, stale-version rejection. Fixtures rolled back.");
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

    internal static async Task SeedLocalFixture(SqlConnection connection, SqlTransaction transaction, string root)
    {
        await connection.ExecuteAsync(await File.ReadAllTextAsync(Path.Combine(root, "database/Curation/chile-pilot.sql")),
            new { CatalogJson = await File.ReadAllTextAsync(Path.Combine(root, "database/Curation/chile-pilot-2026-11.json")) }, transaction);
        await connection.ExecuteAsync("""
            IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId='e512d837-7ead-f111-a6a7-000d3a912199')
              THROW 56937,N'Local fixture already exists.',1;
            INSERT dbo.FundingPlatform_Funders(PublicId,Slug,Name,NormalizedName,PublicationStatus,ContentVersion,IsActive,CreatedAtUtc,UpdatedAtUtc)
            VALUES('a528c3a2-6baa-f111-a6a7-3833c5d78f35',N'catalog-check-existing-nifa',N'National Institute of Food and Agriculture',N'NATIONAL INSTITUTE OF FOOD AND AGRICULTURE',0,1,1,SYSUTCDATETIME(),SYSUTCDATETIME());
            INSERT dbo.FundingPlatform_FunderVersions(FunderId,ContentVersion,SnapshotJson,ContentHash,CreatedAtUtc)
            VALUES(SCOPE_IDENTITY(),1,N'{"fixture":true}',HASHBYTES('SHA2_256',N'{"fixture":true}'),SYSUTCDATETIME());
            DECLARE @FunderId bigint;
            SELECT @FunderId=Id FROM dbo.FundingPlatform_Funders WHERE PublicId='c8ad4e91-28ad-f111-a6a7-000d3a912199';
            IF @FunderId IS NULL
            BEGIN
              INSERT dbo.FundingPlatform_Funders(PublicId,Slug,Name,NormalizedName,PublicationStatus,PublishedAtUtc,ReviewedAtUtc,ContentVersion,IsActive,CreatedAtUtc,UpdatedAtUtc)
              VALUES('c8ad4e91-28ad-f111-a6a7-000d3a912199',N'catalog-check-legacy-funder',N'Bureau of Emerging Threats',N'BUREAU OF EMERGING THREATS',2,SYSUTCDATETIME(),SYSUTCDATETIME(),1,1,SYSUTCDATETIME(),SYSUTCDATETIME());
              SET @FunderId=SCOPE_IDENTITY();
            END;
            INSERT dbo.FundingPlatform_FundingOpportunities(PublicId,Slug,Title,Description,SponsorName,GeographicScope,PublicationStatus,PublishedAtUtc,ReviewedAtUtc,ContentVersion,IsActive)
            VALUES('e512d837-7ead-f111-a6a7-000d3a912199',N'grants-gov-363846-e83998fd',N'HSI fixture',N'Local fixture',N'National Institute of Food and Agriculture',2,2,SYSUTCDATETIME(),SYSUTCDATETIME(),3,1);
            DECLARE @Id bigint=SCOPE_IDENTITY();
            INSERT dbo.FundingPlatform_FundingOpportunityFunders(FundingOpportunityId,FunderId,Role,IsActive,CreatedAtUtc,UpdatedAtUtc) VALUES(@Id,@FunderId,1,1,SYSUTCDATETIME(),SYSUTCDATETIME());
            INSERT dbo.FundingPlatform_FundingOpportunityCategories VALUES(@Id,2,SYSUTCDATETIME());
            DECLARE @SourceId int=(SELECT MIN(Id) FROM dbo.FundingPlatform_FundingSources WHERE Name=N'Embajada del Japón en Chile');
            INSERT dbo.FundingPlatform_FundingOpportunitySourceLinks(FundingOpportunityId,FundingSourceId,ExternalId,SourceItemKeyHash,SourceUrl,CanonicalUrlHash,FirstSeenAtUtc,LastSeenAtUtc,IsPrimary,IsActive)
            VALUES(@Id,@SourceId,N'nifa-local-fixture',HASHBYTES('SHA2_256',CONVERT(VARCHAR(MAX),N'nifa-local-fixture' COLLATE Latin1_General_100_BIN2_UTF8)),N'https://www.nifa.usda.gov/grants',NULL,SYSUTCDATETIME(),SYSUTCDATETIME(),1,1);
            INSERT dbo.FundingPlatform_FundingFieldEvidence(FundingOpportunityId,FieldPath,ValueJson,ExtractionMethod,IsSelected,IsManualLock,CreatedAtUtc)
            SELECT @Id,p,N'{"status":"unknown"}',1,1,1,SYSUTCDATETIME() FROM(VALUES(N'/title'),(N'/description'),(N'/eligibilityDescription'),(N'/closeDate'))v(p);
            INSERT dbo.FundingPlatform_FundingOpportunityVersions(FundingOpportunityId,ContentVersion,SnapshotJson,ContentHash,CreatedAtUtc)
            VALUES(@Id,3,N'{"fixture":true}',HASHBYTES('SHA2_256',N'{"fixture":true}'),SYSUTCDATETIME());
            """, transaction: transaction);
    }

    private sealed record BatchResult(int InsertedCount, int UpdatedCount, int AlreadyAppliedCount);
}
