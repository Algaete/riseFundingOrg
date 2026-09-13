using System.Data;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.Matching;
using FundingPlatform.Core.Matching;
using FundingPlatform.Infrastructure.Configuration;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

// Operational fixture, never called by API/workers/startup or ordinary migrations.
internal static class DevGeographicSample
{
    private static readonly Guid Organization = Guid.Parse("70510000-0000-4000-8000-000000000001");
    private static readonly Guid Project = Guid.Parse("70510000-0000-4000-8000-000000000002");
    private static readonly Guid Eu = Guid.Parse("70510000-0000-4000-8000-000000000101");
    private static readonly Guid Europe = Guid.Parse("70510000-0000-4000-8000-000000000102");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public static async Task<int> RunAsync(string[] args, CancellationToken token)
    {
        if (args.Length != 1 || args[0] is not ("--preview" or "--apply" or "--verify" or "--disable"))
            throw new ArgumentException("Use dev-geographic-sample --preview|--apply|--verify|--disable.");
        var mode = args[0][2..];
        var writes = mode is "apply" or "disable";
        if (writes && Environment.GetEnvironmentVariable("RF_DEV_SAMPLE_CONFIRMATION") != "WRITE-DEV-TEST-DATA")
            throw new InvalidOperationException("Explicit WRITE-DEV-TEST-DATA confirmation required.");
        var owner = Environment.GetEnvironmentVariable("RF_DEV_SAMPLE_OWNER_EMAIL");
        if (string.IsNullOrWhiteSpace(owner) || owner.Length > 320)
            throw new InvalidOperationException("RF_DEV_SAMPLE_OWNER_EMAIL must identify the existing owner.");
        var factory = new SqlConnectionFactory(FundingPlatformConfiguration.CreateFromEnvironment());
        await new SqlDeploymentTargetVerifier(factory, "risefunding-dev",
            "sql-rf-dev-ag26rf01-centralus.database.windows.net", requireExpectedServer: true).VerifyAsync(token);
        await using var connection = factory.CreateConnection();
        await connection.OpenAsync(token);
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(token);
        try
        {
            using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("DevGeographicSample.sql")
                ?? throw new InvalidOperationException("Embedded dev fixture is missing.");
            using var reader = new StreamReader(stream);
            var sql = await reader.ReadToEndAsync(token);
            await connection.ExecuteAsync(new CommandDefinition(sql, new { Mode = mode, OwnerEmail = owner }, transaction,
                commandTimeout: 120, cancellationToken: token));
            if (mode == "disable")
            {
                await transaction.CommitAsync(token);
                Console.WriteLine("TEST sample disabled: 6 organizations, 1 private project, 2 funds, 1 funder and 1 manual source. History preserved; no deletion.");
                return 0;
            }
            var actor = await connection.QuerySingleAsync<Guid>(new CommandDefinition(
                "SELECT PublicId FROM dbo.FundingPlatform_Users WHERE NormalizedEmail=UPPER(LTRIM(RTRIM(@OwnerEmail))) AND Status=2 AND EmailConfirmed=1;",
                new { OwnerEmail = owner }, transaction, cancellationToken: token));
            var directoryJson = await connection.QuerySingleAsync<string>(new CommandDefinition(
                "dbo.FundingPlatform_usp_DiscoveryMatching_Context",
                new { UserPublicId = actor, SourceKind = (byte)1, SourcePublicId = Project, TargetKind = (byte)2 },
                transaction, commandType: CommandType.StoredProcedure, cancellationToken: token));
            var directory = JsonSerializer.Deserialize<DiscoveryMatchingContext>(directoryJson, Json)
                ?? throw new InvalidOperationException("Sample directory unavailable.");
            foreach (var opportunity in new[] { Eu, Europe })
            {
                var contextJson = await connection.QuerySingleAsync<string>(new CommandDefinition(
                    "dbo.FundingPlatform_usp_GapRecommendations_Context",
                    new { UserPublicId = actor, ProjectPublicId = Project, OpportunityPublicId = opportunity },
                    transaction, commandType: CommandType.StoredProcedure, cancellationToken: token));
                var context = JsonSerializer.Deserialize<GapRecommendationContext>(contextJson, Json)
                    ?? throw new InvalidOperationException("Sample funding unavailable.");
                // Actual SQL contexts + unchanged application filtering, including directory opt-in and access checks.
                var result = await new GapRecommendationService(new GapSnapshot(context), new DirectorySnapshot(directory))
                    .ReadAsync(actor, new(Project, opportunity), token);
                var candidates = result?.Items.Single(item => item.Code == "international-partner").Candidates;
                var countries = candidates?.Select(item => item.HomeCountryId).ToHashSet();
                var valid = result?.GeographyState == "specific" && candidates?.Count == 3 &&
                    (opportunity == Eu ? countries!.SetEquals(new int?[] { 250, 724, 276 })
                        : countries!.Contains(826) && !countries.Contains(840) && countries.All(id => id is 250 or 724 or 276 or 826));
                if (!valid || candidates!.Any(item => !item.Name.StartsWith("TEST · DATOS DE PRUEBA · ", StringComparison.Ordinal)))
                    throw new InvalidOperationException("Sample recommendation expectations failed; nothing committed. Inspect catalog/fixture edits before retrying.");
                Console.WriteLine($"TEST { (opportunity == Eu ? "EU" : "EUROPE") }: {string.Join(", ", countries!)}; 3 synthetic candidates; US excluded.");
            }
            if (mode is "apply" or "preview")
            {
                // Use the real, versioned deterministic calculator, never fabricated scores or a borrowed session.
                await connection.ExecuteAsync(new CommandDefinition("dbo.FundingPlatform_usp_ProjectMatchingRun_Create", new
                {
                    UserPublicId = actor, OrganizationPublicId = Organization, ProjectPublicId = Project,
                    IdempotencyKeyHash = SHA256.HashData(Encoding.UTF8.GetBytes("dev-geographic-sample-v1")),
                    RequestHash = SHA256.HashData(Encoding.UTF8.GetBytes($"project-matching-run-create-v1|{Organization:D}|{Project:D}")),
                    NowUtc = DateTime.UtcNow
                }, transaction, commandTimeout: 120, commandType: CommandType.StoredProcedure, cancellationToken: token));
            }
            var run = await connection.QuerySingleAsync<Guid>(new CommandDefinition("""
                SELECT TOP(1) r.PublicId FROM dbo.FundingPlatform_ProjectMatchingRuns r
                JOIN dbo.FundingPlatform_Projects p ON p.Id=r.ProjectId
                WHERE p.PublicId=@Project ORDER BY r.CreatedAtUtc DESC, r.Id DESC;
                """, new { Project }, transaction, cancellationToken: token));
            var matched = await connection.QuerySingleAsync<int>(new CommandDefinition("""
                SELECT COUNT(*) FROM dbo.FundingPlatform_ProjectFundingMatches m
                JOIN dbo.FundingPlatform_ProjectMatchingRuns r ON r.Id=m.MatchRunId
                JOIN dbo.FundingPlatform_FundingOpportunities f ON f.Id=m.FundingOpportunityId
                WHERE r.PublicId=@Run AND f.PublicId IN (@Eu,@Europe) AND m.Classification=0;
                """, new { Run = run, Eu, Europe }, transaction, cancellationToken: token));
            if (matched != 2) throw new InvalidOperationException("Both TEST funds must appear as compatible in the actual matching run; nothing committed.");
            if (writes) await transaction.CommitAsync(token);
            else await transaction.RollbackAsync(token);
            Console.WriteLine(writes ? "TEST sample committed; no real records or authentication settings changed." : "Checks passed; transaction rolled back (no persisted changes).");
            if (mode != "preview") Console.WriteLine($"https://salmon-glacier-0721afc0f.7.azurestaticapps.net/matching?organizationId={Organization}&projectId={Project}&runId={run}");
            return 0;
        }
        catch (SqlException error)
        {
            Console.Error.WriteLine($"Dev sample SQL failure: number={error.Number}, line={error.LineNumber}. No credentials logged; transaction not committed.");
            if (error.Number is >= 55980 and <= 55989) Console.Error.WriteLine(error.Message);
            throw new InvalidOperationException("Dev sample failed. No partial dataset was committed.");
        }
    }

    private sealed class GapSnapshot(GapRecommendationContext context) : IGapRecommendationRepository
    {
        public Task<GapRecommendationContext?> ReadAsync(Guid actor, GapRecommendationRequest request, CancellationToken token) => Task.FromResult<GapRecommendationContext?>(context);
    }
    private sealed class DirectorySnapshot(DiscoveryMatchingContext context) : IDiscoveryMatchingRepository
    {
        public Task<DiscoveryMatchingContext?> ReadAsync(Guid actor, DiscoveryMatchingRequest request, CancellationToken token) => Task.FromResult<DiscoveryMatchingContext?>(context);
    }
}
