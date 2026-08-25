using FundingPlatform.Infrastructure.Persistence.Migrations;

namespace FundingPlatform.UnitTests;

public sealed class Phase9AArchitectureTests
{
    [Fact]
    public void Matching_boundary_is_project_first_private_bounded_and_server_versioned()
    {
        var endpoints = Read(
            "src",
            "FundingPlatform.Api",
            "Endpoints",
            "ProjectMatchingEndpoints.cs");
        var service = Read(
            "src",
            "FundingPlatform.Application",
            "Matching",
            "ProjectMatchingService.cs");
        var program = Read("src", "FundingPlatform.Api", "Program.cs");

        Assert.Contains(
            "/api/v1/organizations/{organizationId:guid}/projects/{projectId:guid}",
            endpoints,
            StringComparison.Ordinal);
        Assert.Contains("RequireAuthorization(\"full-session\")", endpoints, StringComparison.Ordinal);
        Assert.Contains("RequireRateLimiting(\"matching-run-create\")", endpoints, StringComparison.Ordinal);
        Assert.Contains("Idempotency-Key", endpoints, StringComparison.Ordinal);
        Assert.Contains("PermitLimit = 5", program, StringComparison.Ordinal);
        Assert.Contains("Window = TimeSpan.FromMinutes(10)", program, StringComparison.Ordinal);
        Assert.True(
            program.IndexOf("app.UseAuthorization();", StringComparison.Ordinal) <
            program.IndexOf("app.UseRateLimiter();", StringComparison.Ordinal));
        Assert.Contains("return $\"user:{userPublicId:D}\"", program, StringComparison.Ordinal);
        Assert.Contains("return $\"ip:", program, StringComparison.Ordinal);
        Assert.Contains("RequestContractVersion", service, StringComparison.Ordinal);
        Assert.DoesNotContain("matchingProfile", service, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("fundingOpportunity", service, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Wire_uses_compatibility_uncertainty_and_an_explicit_non_eligibility_disclaimer()
    {
        var models = Read(
            "src",
            "FundingPlatform.Core",
            "Matching",
            "ProjectMatchingModels.cs");
        var contracts = Read(
            "src",
            "FundingPlatform.Contracts",
            "Matching",
            "ProjectMatchingContracts.cs");
        var endpoints = Read(
            "src",
            "FundingPlatform.Api",
            "Endpoints",
            "ProjectMatchingEndpoints.cs");

        Assert.Contains("Compatible = 0", models, StringComparison.Ordinal);
        Assert.Contains("Incompatible = 1", models, StringComparison.Ordinal);
        Assert.Contains("InsufficientData = 2", models, StringComparison.Ordinal);
        Assert.Contains("decimal? CompatibilityScore", models, StringComparison.Ordinal);
        Assert.Contains("decimal? CompatibilityScore", contracts, StringComparison.Ordinal);
        Assert.Contains("bool IsCurrent", contracts, StringComparison.Ordinal);
        Assert.Contains("no confirma elegibilidad", endpoints, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Eligible", contracts, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Ineligible", contracts, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("TaxIdentifier", contracts, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Email", contracts, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Notes", contracts, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("InputFingerprint", contracts, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("CandidateSetFingerprint", contracts, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Dapper_materialization_is_explicit_and_drops_non_allowlisted_explanation_data()
    {
        var repository = Read(
            "src",
            "FundingPlatform.Infrastructure",
            "Persistence",
            "Matching",
            "SqlProjectMatchingRepository.cs");

        Assert.Contains("commandTimeout: 60", repository, StringComparison.Ordinal);
        Assert.Contains("TimeProvider timeProvider", repository, StringComparison.Ordinal);
        Assert.Contains("DbType.Guid", repository, StringComparison.Ordinal);
        Assert.Contains("DbType.DateTime2", repository, StringComparison.Ordinal);
        Assert.Contains("DbType.Binary, size: 32", repository, StringComparison.Ordinal);
        Assert.Contains("DateTime.SpecifyKind", repository, StringComparison.Ordinal);
        Assert.Contains("AllowedReasonCodes", repository, StringComparison.Ordinal);
        Assert.Contains("AllowedReasonParameterKeys", repository, StringComparison.Ordinal);
        Assert.Contains("AllowedEvidenceFields", repository, StringComparison.Ordinal);
        Assert.Contains("AllowedEvidenceValueCodes", repository, StringComparison.Ordinal);
        Assert.Contains("IsAllowedReasonParameterValue", repository, StringComparison.Ordinal);
        Assert.Contains(
            "row.DataState == (byte)MatchingDataState.Unknown",
            repository,
            StringComparison.Ordinal);
        Assert.Contains("versioned-snapshots", repository, StringComparison.Ordinal);
        Assert.Contains("Take(50)", repository, StringComparison.Ordinal);
        Assert.DoesNotContain("public DateTimeOffset", repository, StringComparison.Ordinal);
        Assert.DoesNotContain("OpenAI", repository, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Embedding", repository, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Phase_9a_backend_has_no_ai_embedding_or_worker_dependency()
    {
        var files = new[]
        {
            Read("src", "FundingPlatform.Application", "Matching", "ProjectMatchingService.cs"),
            Read("src", "FundingPlatform.Api", "Endpoints", "ProjectMatchingEndpoints.cs"),
            Read(
                "src",
                "FundingPlatform.Infrastructure",
                "Persistence",
                "Matching",
                "SqlProjectMatchingRepository.cs")
        };

        foreach (var source in files)
        {
            Assert.DoesNotContain("IAiService", source, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("OpenAI", source, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("Embedding", source, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("Queue", source, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("Worker", source, StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public void Phase_9a_sql_is_bounded_reproducible_tenant_safe_and_transactionally_smoked()
    {
        var migration = Read(
            "database", "Migrations", "020_deterministic_project_matching.sql");
        var smoke = Read(
            "database", "Tests", "020_deterministic_project_matching_smoke.sql");

        Assert.Contains("SELECT TOP (200) * INTO #Candidates", migration,
            StringComparison.Ordinal);
        Assert.Contains("ProjectSlugSnapshot", migration, StringComparison.Ordinal);
        Assert.Contains("ProjectTitleSnapshot", migration, StringComparison.Ordinal);
        Assert.Contains("RuleSetFingerprint", migration, StringComparison.Ordinal);
        Assert.Contains("CandidateSetFingerprint", migration, StringComparison.Ordinal);
        Assert.Contains("#CandidateLegalEntityTypes", migration, StringComparison.Ordinal);
        Assert.Contains("#MatchingProjectTypes", migration, StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_FK_ProjectMatchingRunRequests_RunTenantProject",
            migration, StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_tr_ProjectFundingMatches_SupersessionOnly",
            migration, StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_IX_ProjectMatchingRuns_ProjectInput",
            migration, StringComparison.Ordinal);
        Assert.Contains("FROM dbo.FundingPlatform_ProjectMatchingRuns AS newerRuns",
            migration, StringComparison.Ordinal);
        Assert.DoesNotContain("FundingPlatform_UQ_ProjectMatchingRuns_ProjectInput",
            migration, StringComparison.Ordinal);
        Assert.Contains("operating_years.not_required", migration, StringComparison.Ordinal);
        Assert.DoesNotContain("OpenAI", migration, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Embedding", migration, StringComparison.OrdinalIgnoreCase);

        Assert.Contains("BEGIN TRY", smoke, StringComparison.Ordinal);
        Assert.Contains("BEGIN CATCH", smoke, StringComparison.Ordinal);
        Assert.Contains("ROLLBACK TRANSACTION", smoke, StringComparison.Ordinal);
        Assert.Contains("Cross-tenant run request", smoke, StringComparison.Ordinal);
        Assert.Contains("Stale historical input did not replay", smoke,
            StringComparison.Ordinal);
        Assert.Contains("Live project rename/archive relabelled", smoke,
            StringComparison.Ordinal);
        Assert.Contains("Idempotency-key hash conflict", smoke,
            StringComparison.Ordinal);
    }

    private static string Read(params string[] parts)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        return File.ReadAllText(Path.Combine([root, .. parts]));
    }
}
