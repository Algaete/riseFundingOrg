using FundingPlatform.Infrastructure.Persistence.Migrations;

namespace FundingPlatform.UnitTests;

public sealed class Phase9BArchitectureTests
{
    [Fact]
    public void Semantic_smoke_resolves_vector_from_the_user_type_identifier()
    {
        var smoke = Read(
            "database", "Tests", "021_shadow_semantic_evaluation_smoke.sql");

        Assert.Contains(
            "TYPE_NAME(user_type_id) = N'vector'",
            smoke,
            StringComparison.Ordinal);
        Assert.DoesNotContain(
            "TYPE_NAME(system_type_id) = N'vector'",
            smoke,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Semantic_smoke_consumes_the_final_governed_input_wire_shape()
    {
        var smoke = Read(
            "database", "Tests", "021_shadow_semantic_evaluation_smoke.sql");

        Assert.Contains("ProviderPolicyPublicId UNIQUEIDENTIFIER", smoke,
            StringComparison.Ordinal);
        Assert.Contains("ProviderPolicyFingerprint BINARY(32)", smoke,
            StringComparison.Ordinal);
        Assert.Contains("ExternalProcessingAllowed BIT", smoke,
            StringComparison.Ordinal);
        Assert.Contains("ProviderPolicyPublicId IS NULL", smoke,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Governed_provider_columns_exist_before_constraints_are_compiled()
    {
        var migration = Read(
            "database", "Migrations", "022_governed_openai_provider.sql");

        Assert.Contains(
            "FundingPlatform_DF_SemanticConfigurations_ProviderCapability DEFAULT (0);\nGO\n\n" +
            "ALTER TABLE dbo.FundingPlatform_SemanticConfigurations\n" +
            "ADD CONSTRAINT FundingPlatform_CK_SemanticConfigurations_GovernedProvider",
            migration,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Singleton_indexes_filter_on_physical_status_not_computed_columns()
    {
        var semantic = Read(
            "database", "Migrations", "021_shadow_semantic_evaluation.sql");
        var explanations = Read(
            "database", "Migrations", "023_shadow_structured_explanations.sql");

        Assert.Contains(
            "(ActiveSlot)\n    WHERE Status IN (0, 1, 3);",
            semantic,
            StringComparison.Ordinal);
        Assert.Contains(
            "(ActiveSlot)\n    WHERE Status = 0;",
            explanations,
            StringComparison.Ordinal);
        Assert.DoesNotContain(
            "(ActiveSlot)\n    WHERE ActiveSlot = 1;",
            semantic + explanations,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Structured_explanation_uses_the_semantic_run_fingerprint_column()
    {
        var explanations = Read(
            "database", "Migrations", "023_shadow_structured_explanations.sql");

        Assert.Contains(
            "sourceRuns.SemanticConfigurationFingerprint",
            explanations,
            StringComparison.Ordinal);
        Assert.DoesNotContain(
            "sourceRuns.ConfigurationFingerprint",
            explanations,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Admin_boundary_is_mfa_only_shadow_only_idempotent_and_not_client_configurable()
    {
        var endpoints = Read(
            "src", "FundingPlatform.Api", "Endpoints",
            "AdminSemanticEvaluationEndpoints.cs");
        var contracts = Read(
            "src", "FundingPlatform.Contracts", "Semantics",
            "SemanticEvaluationContracts.cs");
        var createContract = Between(
            contracts,
            "public sealed record CreateSemanticEvaluationRunRequest",
            "public sealed record SemanticEvaluationMetricsResponse");
        var program = Read("src", "FundingPlatform.Api", "Program.cs");

        Assert.Contains("/api/v1/admin/semantic-evaluation-runs", endpoints,
            StringComparison.Ordinal);
        Assert.Contains("/{runId:guid}/report", endpoints, StringComparison.Ordinal);
        Assert.Contains("MapGet(\"/{runId:guid}/report\", GetReportAsync)", endpoints,
            StringComparison.Ordinal);
        Assert.Contains("RequireAuthorization(\"admin-mfa\")", endpoints,
            StringComparison.Ordinal);
        Assert.Contains("Idempotency-Key", endpoints, StringComparison.Ordinal);
        Assert.Contains("modo sombra", endpoints, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("PermitLimit = 2", program, StringComparison.Ordinal);
        Assert.Contains("Window = TimeSpan.FromHours(1)", program, StringComparison.Ordinal);
        Assert.DoesNotContain("ProviderCode", createContract, StringComparison.Ordinal);
        Assert.DoesNotContain("ModelCode", createContract, StringComparison.Ordinal);
        Assert.DoesNotContain("Canonical", createContract, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Prompt", createContract, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Vector", createContract, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("SemanticEvaluationRunReportResponse", contracts,
            StringComparison.Ordinal);
        Assert.Contains("SemanticEvaluationSplitReportResponse", contracts,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Canonical_contract_is_cross_layer_bounded_private_and_taxonomy_stable()
    {
        var migration = Read(
            "database", "Migrations", "021_shadow_semantic_evaluation.sql");
        var policy = Read(
            "src", "FundingPlatform.Application", "Semantics",
            "SemanticInputPolicy.cs");
        var projectFunction = Between(
            migration,
            "CREATE OR ALTER FUNCTION dbo.FundingPlatform_fn_ProjectSemanticCanonicalInput",
            "CREATE OR ALTER FUNCTION dbo.FundingPlatform_fn_OpportunitySemanticCanonicalInput");
        var projectAllowlist = Between(
            policy,
            "private static readonly HashSet<string> ProjectProperties",
            "private static readonly HashSet<string> OpportunityProperties");

        Assert.Contains("semantic-input-v1", migration, StringComparison.Ordinal);
        Assert.Contains("semantic-input-v1", policy, StringComparison.Ordinal);
        Assert.Contains("Latin1_General_100_BIN2_UTF8", migration,
            StringComparison.Ordinal);
        Assert.Contains("MaximumInputUtf8Bytes = 8192", migration,
            StringComparison.Ordinal);
        Assert.Contains("IsCanonicalTaxonomyArray", policy, StringComparison.Ordinal);
        Assert.Contains("SELECT DISTINCT Id", migration, StringComparison.Ordinal);
        Assert.Contains("WITHIN GROUP (ORDER BY ids.Id)", migration,
            StringComparison.Ordinal);
        Assert.Contains("WHEN 5 THEN JSON_VALUE", migration, StringComparison.Ordinal);
        Assert.DoesNotContain("\"title\"", projectAllowlist, StringComparison.Ordinal);
        Assert.DoesNotContain("N',\"title\"", projectFunction, StringComparison.Ordinal);
        Assert.DoesNotContain("OrganizationProfile", policy, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("organizationName", projectFunction,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("slug", projectFunction, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("url", projectFunction, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Provider_is_exact_governed_and_hosted_api_keeps_9a_available()
    {
        var options = Read(
            "src", "FundingPlatform.Infrastructure", "Configuration",
            "SemanticOptions.cs");
        var aliases = Read(
            "src", "FundingPlatform.Infrastructure", "Configuration",
            "FundingPlatformConfiguration.cs");
        var api = Read("src", "FundingPlatform.Api", "Program.cs");
        var worker = Read("src", "FundingPlatform.Workers", "Program.cs");
        var fake = Read(
            "src", "FundingPlatform.Infrastructure", "Semantics",
            "DeterministicDevelopmentEmbeddingService.cs");
        var openAi = Read(
            "src", "FundingPlatform.Infrastructure", "Semantics",
            "OpenAiEmbeddingService.cs");
        var openAiOptions = Read(
            "src", "FundingPlatform.Infrastructure", "Configuration",
            "OpenAiProviderOptions.cs");

        Assert.DoesNotContain("ProviderCode", options, StringComparison.Ordinal);
        Assert.DoesNotContain("ModelCode", options, StringComparison.Ordinal);
        Assert.DoesNotContain("SEMANTIC_PROVIDER", aliases, StringComparison.Ordinal);
        Assert.DoesNotContain("SEMANTIC_MODEL", aliases, StringComparison.Ordinal);
        Assert.Contains("Bind(builder.Configuration.GetSection(SemanticOptions.SectionName))", api,
            StringComparison.Ordinal);
        Assert.DoesNotContain("configured with { Enabled = false }", api,
            StringComparison.Ordinal);
        Assert.Contains("SemanticWorkerOptionsValidator", worker,
            StringComparison.Ordinal);
        Assert.Contains("GovernedEmbeddingServiceRouter", worker, StringComparison.Ordinal);
        Assert.Contains("OpenAiEmbeddingService", worker, StringComparison.Ordinal);
        Assert.Contains("development-deterministic", fake, StringComparison.Ordinal);
        Assert.Contains("lexical-hash-1536-v1", fake, StringComparison.Ordinal);
        Assert.DoesNotContain("OpenAI", fake, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("HttpClient", fake, StringComparison.Ordinal);
        Assert.Contains("https://api.openai.com", openAiOptions, StringComparison.Ordinal);
        Assert.Contains("ZeroDataRetention", openAi, StringComparison.Ordinal);
        Assert.Contains("FixedTimeEquals", openAi, StringComparison.Ordinal);
        Assert.DoesNotContain("OPENAI_MODEL", aliases, StringComparison.Ordinal);
    }

    [Fact]
    public void Phase9bb_is_governed_disabled_shadow_only_and_never_writes_back()
    {
        var migration022 = Read(
            "database", "Migrations", "022_governed_openai_provider.sql");
        var migration023 = Read(
            "database", "Migrations", "023_shadow_structured_explanations.sql");
        var adapter = Read(
            "src", "FundingPlatform.Infrastructure", "Semantics",
            "OpenAiStructuredExplanationService.cs");
        var inputPolicy = Read(
            "src", "FundingPlatform.Application", "Semantics",
            "AiExplanationInputPolicy.cs");
        var endpoints = Read(
            "src", "FundingPlatform.Api", "Endpoints",
            "AdminAiExplanationEndpoints.cs");
        var env = Read(".env.example");

        Assert.Contains("ZeroDataRetention", adapter, StringComparison.Ordinal);
        Assert.Contains("store = false", adapter, StringComparison.Ordinal);
        Assert.Contains("json_schema", adapter, StringComparison.Ordinal);
        Assert.Contains("gpt-5.6-sol", adapter, StringComparison.Ordinal);
        Assert.Contains("FixedTimeEquals", adapter, StringComparison.Ordinal);
        Assert.Contains("RequiredStructuredOutputGovernanceFingerprint", adapter,
            StringComparison.Ordinal);
        Assert.Contains("HasExactOrderedProperties", inputPolicy,
            StringComparison.Ordinal);
        Assert.Contains("rules.GetArrayLength() != RuleCodes.Length", inputPolicy,
            StringComparison.Ordinal);
        Assert.Contains("ReasonCodes.Contains", inputPolicy, StringComparison.Ordinal);
        Assert.Contains("AiExplanationInputPolicy.IsCanonicalAndSafe", adapter,
            StringComparison.Ordinal);
        Assert.Contains("Capability = 1", migration023, StringComparison.Ordinal);
        Assert.Contains("RetentionMode = 2", migration023, StringComparison.Ordinal);
        Assert.Contains("MaximumProviderRetentionDays = 0", migration023,
            StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_SemanticWorkerRole", migration023,
            StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_SemanticAdminRole", migration023,
            StringComparison.Ordinal);
        Assert.Contains("DENY SELECT, INSERT, UPDATE, DELETE", migration023,
            StringComparison.Ordinal);
        Assert.DoesNotContain("ApiKey", migration022, StringComparison.OrdinalIgnoreCase);
        foreach (var table in new[]
                 {
                     "FundingPlatform_AiExplanationConfigurations",
                     "FundingPlatform_AiExplanationRuns",
                     "FundingPlatform_AiExplanationJobs",
                     "FundingPlatform_AiExplanationBudgetReservations",
                     "FundingPlatform_AiExplanationUsageLedger",
                     "FundingPlatform_AiExplanationResults"
                 })
        {
            var definition = CreateTable(migration023, table);
            Assert.DoesNotContain("RawResponse", definition,
                StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("CanonicalInput", definition,
                StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("PromptText", definition,
                StringComparison.OrdinalIgnoreCase);
        }
        Assert.DoesNotContain("UPDATE dbo.FundingPlatform_ProjectFundingMatches", migration023,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("UPDATE dbo.FundingPlatform_SemanticEvaluationItems", migration023,
            StringComparison.OrdinalIgnoreCase);
        Assert.Contains("/api/v1/admin/semantic-explanation-runs", endpoints,
            StringComparison.Ordinal);
        Assert.Contains("RequireAuthorization(\"admin-mfa\")", endpoints,
            StringComparison.Ordinal);
        Assert.Contains("AI_EXPLANATIONS_ENABLED=\"false\"", env,
            StringComparison.Ordinal);
        Assert.Contains("OPENAI_STRUCTURED_OUTPUTS_ENABLED=\"false\"", env,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Persistence_uses_native_vectors_safe_leases_budget_and_separate_shadow_results()
    {
        var migration = Read(
            "database", "Migrations", "021_shadow_semantic_evaluation.sql");
        var repository = Read(
            "src", "FundingPlatform.Infrastructure", "Persistence", "Semantics",
            "SqlSemanticProcessingRepository.cs");
        var administrationRepository = Read(
            "src", "FundingPlatform.Infrastructure", "Persistence", "Semantics",
            "SqlSemanticEvaluationAdministrationRepository.cs");
        var service = Read(
            "src", "FundingPlatform.Application", "Semantics",
            "SemanticProcessingService.cs");

        Assert.Contains("Embedding VECTOR(1536) NOT NULL", migration,
            StringComparison.Ordinal);
        Assert.Contains("VECTOR_DISTANCE('cosine'", migration, StringComparison.Ordinal);
        Assert.Contains("new SqlVector<float>", repository, StringComparison.Ordinal);
        Assert.DoesNotContain("VARBINARY(6144)", migration, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("ProviderCallMayHaveBeenCharged", migration,
            StringComparison.Ordinal);
        Assert.Contains("N'charge-uncertain'", migration, StringComparison.Ordinal);
        Assert.Contains("ExpiredReservations", migration, StringComparison.Ordinal);
        Assert.Contains("RenewEmbeddingJobLeaseAsync", service, StringComparison.Ordinal);
        Assert.Contains("ClaimEmbeddingJobsAsync(\n                workerInstanceId,\n                1,",
            service, StringComparison.Ordinal);
        Assert.Contains("TryCompleteEmbeddingAsync", service, StringComparison.Ordinal);
        Assert.Contains("TryCompleteShadowEvaluationAsync", service,
            StringComparison.Ordinal);
        Assert.Contains("configuration-not-approved", administrationRepository,
            StringComparison.Ordinal);
        Assert.Contains("eval-set-not-ready", administrationRepository,
            StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_usp_SemanticEvaluationRun_Report",
            administrationRepository, StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_usp_SemanticEvaluationRun_Report", migration,
            StringComparison.Ordinal);
        Assert.Contains("row.DatasetSplit > 1", administrationRepository,
            StringComparison.Ordinal);
        Assert.Contains("SemanticEvaluationItems", migration, StringComparison.Ordinal);
        Assert.DoesNotContain("UPDATE dbo.FundingPlatform_ProjectMatchingRuns", migration,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("UPDATE dbo.FundingPlatform_ProjectFundingMatches", migration,
            StringComparison.OrdinalIgnoreCase);

        foreach (var table in new[]
                 {
                     "FundingPlatform_SemanticEmbeddingJobs",
                     "FundingPlatform_SemanticEmbeddings",
                     "FundingPlatform_SemanticEvaluationRuns",
                     "FundingPlatform_SemanticEvaluationItems"
                 })
        {
            var definition = CreateTable(migration, table);
            Assert.DoesNotContain("CanonicalInput", definition,
                StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("Prompt", definition, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("RawResponse", definition,
                StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("SnapshotJson", definition,
                StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public void Metric_scales_and_corpus_gates_are_explicit()
    {
        var core = Read(
            "src", "FundingPlatform.Core", "Semantics", "SemanticModels.cs");
        var contracts = Read(
            "src", "FundingPlatform.Contracts", "Semantics",
            "SemanticEvaluationContracts.cs");
        var migration = Read(
            "database", "Migrations", "021_shadow_semantic_evaluation.sql");

        Assert.Contains("CoveragePercentage", core, StringComparison.Ordinal);
        Assert.Contains("ProviderSuccessPercentage", core, StringComparison.Ordinal);
        Assert.Contains("CoveragePercentage", contracts, StringComparison.Ordinal);
        Assert.Contains("ProviderSuccessPercentage", contracts, StringComparison.Ordinal);
        Assert.DoesNotContain("ProviderSuccessRate", core, StringComparison.Ordinal);
        Assert.Contains("DeclaredProjectCount >= 30", migration, StringComparison.Ordinal);
        Assert.Contains("DeclaredOpportunityCount BETWEEN 100 AND 5000", migration,
            StringComparison.Ordinal);
        Assert.Contains("DeclaredLabelCount BETWEEN 300 AND 5000", migration,
            StringComparison.Ordinal);
        Assert.Contains("PairCount BETWEEN 300 AND 5000", migration,
            StringComparison.Ordinal);
        Assert.Contains("CoveragePercentage BETWEEN 0 AND 100", migration,
            StringComparison.Ordinal);
        Assert.Contains("RecallAt10", migration, StringComparison.Ordinal);
        Assert.Contains("NdcgAt10", migration, StringComparison.Ordinal);
        Assert.Contains("MrrAt10", migration, StringComparison.Ordinal);
        Assert.Contains("HardFailPromotedCount <> 0", migration,
            StringComparison.Ordinal);
        Assert.Contains("AS SkippedStaleEmbeddingJobCount", migration,
            StringComparison.Ordinal);
        Assert.Contains("AS RejectedInputEmbeddingJobCount", migration,
            StringComparison.Ordinal);
        Assert.Contains("Status <> 5 OR ErrorCode = N'stale-subject'", migration,
            StringComparison.Ordinal);
        Assert.Contains("RejectedInputEmbeddingJobCount", contracts,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Sql_boundary_is_exact_least_privilege_and_budget_safe()
    {
        var migration = Read(
            "database", "Migrations", "021_shadow_semantic_evaluation.sql");

        Assert.Contains(
            "WHEN @AvailableBudget >= @MaximumCost * @BatchSize THEN @BatchSize",
            migration,
            StringComparison.Ordinal);
        Assert.Contains("IsLocalFake = 0 OR MaximumCostUsdPerEmbedding = 0",
            migration, StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_SemanticWorkerRole", migration,
            StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_SemanticAdminRole", migration,
            StringComparison.Ordinal);
        Assert.Contains("DENY SELECT, INSERT, UPDATE, DELETE", migration,
            StringComparison.Ordinal);
        Assert.Contains("ProviderCode COLLATE Latin1_General_100_BIN2",
            migration, StringComparison.Ordinal);
        Assert.Contains("ModelCode COLLATE Latin1_General_100_BIN2",
            migration, StringComparison.Ordinal);
        Assert.Contains("VECTOR_DISTANCE('cosine', inserted.Embedding, inserted.Embedding)",
            migration, StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_tr_SemanticEvaluationItems_SubjectGuard",
            migration, StringComparison.Ordinal);
        Assert.Contains("COUNT(DISTINCT ProjectId)", migration,
            StringComparison.Ordinal);
        Assert.Contains("Split = 1) < 100", migration,
            StringComparison.Ordinal);
        Assert.Contains("Split = 1 AND testCases.RelevanceLabel > 0", migration,
            StringComparison.Ordinal);
    }

    private static string CreateTable(string migration, string name)
    {
        var start = migration.IndexOf($"CREATE TABLE dbo.{name}", StringComparison.Ordinal);
        Assert.True(start >= 0, $"Missing table {name}.");
        var end = migration.IndexOf("\n);", start, StringComparison.Ordinal);
        Assert.True(end > start, $"Unterminated table {name}.");
        return migration[start..(end + 3)];
    }

    private static string Between(string source, string startMarker, string endMarker)
    {
        var start = source.IndexOf(startMarker, StringComparison.Ordinal);
        var end = source.IndexOf(endMarker, start + startMarker.Length,
            StringComparison.Ordinal);
        Assert.True(start >= 0 && end > start);
        return source[start..end];
    }

    private static string Read(params string[] parts)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        return File.ReadAllText(Path.Combine([root, .. parts]));
    }
}
