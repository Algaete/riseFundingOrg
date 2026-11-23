using Dapper;
using Microsoft.Data.SqlClient;
using FundingPlatform.Infrastructure.Persistence.Migrations;
if (args.Length == 1 && args[0] is "--preview-scale" or "--apply-scale" or "--verify-scale-local")
    return await ScaleCatalog.RunAsync(args[0]);
if (args.Length == 1 && args[0] is "--preview-resume" or "--apply-resume" or "--verify-resume-local")
    return await ReviewedCatalog.RunAsync(args[0]);
if (args.Length == 1 && args[0] is "--preview-eligibility" or "--apply-eligibility" or "--verify-eligibility-local")
    return await EligibilityCatalog.RunAsync(args[0]);
if (args.Length == 1 && args[0] is "--preview-expansion" or "--apply-expansion" or "--verify-expansion-local" or "--inspect-expansion")
    return await ExpansionCatalog.RunAsync(args[0]);
if(args.Length!=1 || args[0] is not ("--preview" or "--apply")) return 64;
var settings=new SqlConnectionStringBuilder(Environment.GetEnvironmentVariable("AZURE_SQL_CONNECTION_STRING"));
if(settings.InitialCatalog!="risefunding-dev" || settings.DataSource!="tcp:sql-rf-dev-ag26rf01-centralus.database.windows.net,1433" || !settings.Encrypt || settings.TrustServerCertificate) return 64;
if(args[0]=="--apply" && Environment.GetEnvironmentVariable("RF_PILOT_CATALOG_CONFIRMATION")!="PUBLISH-THREE-REVIEWED-FUNDS-AND-WITHDRAW-TWO-SAMPLES") return 64;
var root=SolutionRootLocator.Find();
await using var connection=new SqlConnection(settings.ConnectionString);
await connection.OpenAsync();
await using var transaction=(SqlTransaction)await connection.BeginTransactionAsync();
try {
 var result=await connection.QuerySingleAsync(await File.ReadAllTextAsync(Path.Combine(root,"database/Curation/chile-pilot.sql")),new {CatalogJson=await File.ReadAllTextAsync(Path.Combine(root,"database/Curation/chile-pilot-2026-11.json"))},transaction,commandTimeout:60);
 if(args[0]=="--apply") await transaction.CommitAsync(); else await transaction.RollbackAsync();
 Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(new{mode=args[0],result}));return 0;
} catch(SqlException error){await transaction.RollbackAsync();Console.Error.WriteLine($"Catalog aborted: SQL {error.Number}, line {error.LineNumber}.");return 1;}
