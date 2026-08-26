using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using FundingPlatform.Infrastructure.Persistence.Migrations;

namespace FundingPlatform.UnitTests;

public sealed class RuntimeDatabaseRoleMigrationTests
{
    private const string ApiRole = "FundingPlatform_ApiRuntimeRole";
    private const string GeneralWorkerRole = "FundingPlatform_GeneralWorkerRole";

    [Fact]
    public void Runtime_procedure_allowlists_match_the_registered_host_repositories()
    {
        var migration = Read("database", "Migrations", "027_runtime_database_roles.sql");

        var expectedApi = ExtractProcedures(ApiRepositoryFiles)
            .Except(ApiExcludedProcedures, StringComparer.Ordinal)
            .Order(StringComparer.Ordinal)
            .ToArray();
        var expectedWorker = ExtractProcedures(GeneralWorkerRepositoryFiles)
            .Except(GeneralWorkerExcludedProcedures, StringComparer.Ordinal)
            .Order(StringComparer.Ordinal)
            .ToArray();

        var grantedApi = ExtractRoleProcedures(migration, ApiRole);
        var grantedWorker = ExtractRoleProcedures(migration, GeneralWorkerRole);

        Assert.Equal(116, expectedApi.Length);
        Assert.Equal(49, expectedWorker.Length);
        Assert.Equal(expectedApi, grantedApi);
        Assert.Equal(expectedWorker, grantedWorker);
    }

    [Fact]
    public void Api_direct_dml_and_table_type_permissions_are_exact_and_object_scoped()
    {
        var migration = Read("database", "Migrations", "027_runtime_database_roles.sql");

        var tablePermissions = Regex.Matches(
                migration,
                @"GRANT (?<permissions>[A-Z, ]+) ON OBJECT::dbo\.(?<object>FundingPlatform_[A-Za-z0-9_]+)\s+TO FundingPlatform_ApiRuntimeRole;",
                RegexOptions.CultureInvariant)
            .SelectMany(match => match.Groups["permissions"].Value
                .Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
                .Select(permission => $"{match.Groups["object"].Value}:{permission}"))
            .Order(StringComparer.Ordinal)
            .ToArray();

        string[] expectedTablePermissions =
        [
            "FundingPlatform_AuthenticationEvents:INSERT",
            "FundingPlatform_Roles:SELECT",
            "FundingPlatform_UserAuthenticatorKeys:INSERT",
            "FundingPlatform_UserAuthenticatorKeys:SELECT",
            "FundingPlatform_UserAuthenticatorKeys:UPDATE",
            "FundingPlatform_UserMfaChallenges:INSERT",
            "FundingPlatform_UserMfaChallenges:SELECT",
            "FundingPlatform_UserMfaChallenges:UPDATE",
            "FundingPlatform_UserRecoveryCodes:DELETE",
            "FundingPlatform_UserRecoveryCodes:INSERT",
            "FundingPlatform_UserRecoveryCodes:SELECT",
            "FundingPlatform_UserRecoveryCodes:UPDATE",
            "FundingPlatform_UserRoles:DELETE",
            "FundingPlatform_UserRoles:INSERT",
            "FundingPlatform_UserRoles:SELECT",
            "FundingPlatform_Users:INSERT",
            "FundingPlatform_Users:SELECT",
            "FundingPlatform_Users:UPDATE"
        ];
        Array.Sort(expectedTablePermissions, StringComparer.Ordinal);
        Assert.Equal(expectedTablePermissions, tablePermissions);

        var expectedTypes = ExtractTableTypes(ApiRepositoryFiles)
            .Order(StringComparer.Ordinal)
            .ToArray();
        var grantedTypes = Regex.Matches(
                migration,
                @"GRANT EXECUTE, REFERENCES ON TYPE::dbo\.(?<type>FundingPlatform_[A-Za-z0-9_]+)\s+TO FundingPlatform_ApiRuntimeRole;",
                RegexOptions.CultureInvariant)
            .Select(match => match.Groups["type"].Value)
            .Order(StringComparer.Ordinal)
            .ToArray();

        Assert.Equal(5, expectedTypes.Length);
        Assert.Equal(expectedTypes, grantedTypes);
        Assert.DoesNotContain("GRANT EXECUTE ON SCHEMA::", migration,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("GRANT SELECT ON SCHEMA::", migration,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("CREATE USER", migration, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("ALTER ROLE", migration, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("db_owner", migration, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("db_datareader", migration, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("db_datawriter", migration, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Runtime_role_smoke_is_transactional_effective_and_preserves_specialist_roles()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = File.ReadAllText(Path.Combine(
            root, "database", "Migrations", "027_runtime_database_roles.sql"));
        var smoke = File.ReadAllText(Path.Combine(
            root, "database", "Tests", "027_runtime_database_roles_smoke.sql"));
        var test = Assert.Single(
            SqlScriptCatalog.DiscoverTests(root), script => script.Sequence == 27);

        Assert.Single(GoBatchSplitter.Split(migration));
        Assert.Single(test.Batches);
        Assert.Contains("<> 116", smoke, StringComparison.Ordinal);
        Assert.Contains("<> 49", smoke, StringComparison.Ordinal);
        Assert.Contains("@ExpectedApiTablePermissions", smoke, StringComparison.Ordinal);
        Assert.Contains("@ExpectedApiTypePermissions", smoke, StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_ExtractionWorkerRole", smoke, StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_SemanticWorkerRole", smoke, StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_SemanticAdminRole", smoke, StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_AlertWorkerRole", smoke, StringComparison.Ordinal);
        Assert.Contains("sys.database_role_members", smoke, StringComparison.Ordinal);
        Assert.Contains("EXCEPT", smoke, StringComparison.Ordinal);
        Assert.Contains("execute_as_principal_id = -2", migration, StringComparison.Ordinal);
        Assert.Contains("execute_as_principal_id = -2", smoke, StringComparison.Ordinal);
        Assert.Contains(
            "0x" + ProcedureFingerprint(ExtractRoleProcedures(migration, ApiRole)),
            smoke,
            StringComparison.OrdinalIgnoreCase);
        Assert.Contains(
            "0x" + ProcedureFingerprint(ExtractRoleProcedures(migration, GeneralWorkerRole)),
            smoke,
            StringComparison.OrdinalIgnoreCase);
        Assert.Contains("WITHOUT LOGIN", smoke, StringComparison.Ordinal);
        Assert.Contains("EXECUTE AS USER", smoke, StringComparison.Ordinal);
        Assert.Contains("ROLLBACK TRANSACTION FP_Smoke027", smoke, StringComparison.Ordinal);
        Assert.DoesNotContain("FROM EXTERNAL PROVIDER", smoke,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("INSERT dbo.FundingPlatform_", smoke,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("UPDATE dbo.FundingPlatform_", smoke,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("DELETE FROM dbo.FundingPlatform_", smoke,
            StringComparison.OrdinalIgnoreCase);
    }

    private static string[] ExtractRoleProcedures(string migration, string roleName)
    {
        return Regex.Matches(
                migration,
                $@"\(N'{Regex.Escape(roleName)}', N'dbo', N'(?<procedure>FundingPlatform_usp_[A-Za-z0-9_]+)'\)",
                RegexOptions.CultureInvariant)
            .Select(match => match.Groups["procedure"].Value)
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal)
            .ToArray();
    }

    private static string ProcedureFingerprint(IEnumerable<string> procedureNames)
    {
        var material = string.Join(
            '\n',
            procedureNames.Order(StringComparer.Ordinal).Select(name => $"dbo.{name}"));
        return Convert.ToHexString(SHA256.HashData(Encoding.Unicode.GetBytes(material)));
    }

    private static HashSet<string> ExtractProcedures(IEnumerable<string[]> files)
    {
        return files
            .Select(parts => Read(parts))
            .SelectMany(source => Regex.Matches(
                    source,
                    @"dbo\.(?<procedure>FundingPlatform_usp_[A-Za-z0-9_]+)",
                    RegexOptions.CultureInvariant)
                .Select(match => match.Groups["procedure"].Value))
            .ToHashSet(StringComparer.Ordinal);
    }

    private static HashSet<string> ExtractTableTypes(IEnumerable<string[]> files)
    {
        return files
            .Select(parts => Read(parts))
            .SelectMany(source => Regex.Matches(
                    source,
                    @"AsTableValuedParameter\(""dbo\.(?<type>FundingPlatform_[A-Za-z0-9_]+)""\)",
                    RegexOptions.CultureInvariant)
                .Select(match => match.Groups["type"].Value))
            .ToHashSet(StringComparer.Ordinal);
    }

    private static string Read(params string[] parts)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        return File.ReadAllText(Path.Combine([root, .. parts]));
    }

    private static readonly string[][] ApiRepositoryFiles =
    [
        ["src", "FundingPlatform.Infrastructure", "Identity", "Persistence", "SqlAuthenticationRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "FundingOpportunities", "SqlFundingOpportunityRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "FundingOpportunities", "SqlFundingOpportunityWorkspaceRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Alerts", "SqlSavedSearchAlertRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "FundingOpportunities", "SqlFunderRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "FundingOpportunities", "SqlFundingOpportunityEditorialRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "FundingOpportunities", "SqlFundingDuplicateReviewRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "FundingOpportunities", "SqlFundingSourceAdminRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Imports", "SqlImportRunRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Organizations", "SqlOrganizationRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Projects", "SqlProjectRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Marketplace", "SqlMarketplaceRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Applications", "SqlFundingApplicationRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Networking", "SqlNetworkingRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Billing", "SqlBillingRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Matching", "SqlProjectMatchingRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Semantics", "SqlSemanticProcessingRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Semantics", "SqlSemanticEvaluationAdministrationRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Semantics", "SqlSemanticEvaluationProcessingRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Semantics", "SqlAiExplanationRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "SourceDocuments", "SqlSourceDocumentRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "SourceDocuments", "SqlSourceDocumentExtractionRepository.cs"]
    ];

    private static readonly string[][] GeneralWorkerRepositoryFiles =
    [
        ["src", "FundingPlatform.Infrastructure", "Persistence", "FundingOpportunities", "SqlFundingOpportunityRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "FundingOpportunities", "SqlFundingSourceAcquisitionAuthorizer.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Imports", "SqlImportRunRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Imports", "SqlImportOutboxRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Imports", "SqlContentRetentionRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "SourceDocuments", "SqlSourceDocumentContentRetentionRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "SourceDocuments", "SqlSourceDocumentRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "SourceDocuments", "SqlDefenderScanReceiptRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "SourceDocuments", "SqlDefenderScanWatchdogRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Semantics", "SqlSemanticProcessingRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Semantics", "SqlSemanticEvaluationAdministrationRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Semantics", "SqlSemanticEvaluationProcessingRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Semantics", "SqlAiExplanationRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Alerts", "SqlSavedSearchAlertRepository.cs"],
        ["src", "FundingPlatform.Infrastructure", "Persistence", "Billing", "SqlBillingRepository.cs"]
    ];

    private static readonly string[] ApiExcludedProcedures =
    [
        "FundingPlatform_usp_FundingOpportunity_StageExternal",
        "FundingPlatform_usp_AlertSchedule_Claim",
        "FundingPlatform_usp_AlertSchedule_Materialize",
        "FundingPlatform_usp_AlertDelivery_Claim",
        "FundingPlatform_usp_AlertDelivery_RenewLease",
        "FundingPlatform_usp_AlertDelivery_Complete",
        "FundingPlatform_usp_AlertDelivery_Fail",
        "FundingPlatform_usp_ImportRun_Scheduler_CreateDue",
        "FundingPlatform_usp_ImportRun_RequeueStranded",
        "FundingPlatform_usp_ImportRun_Claim",
        "FundingPlatform_usp_ImportRun_RenewLease",
        "FundingPlatform_usp_ImportRunItem_ListPending",
        "FundingPlatform_usp_RawFundingOpportunity_Record",
        "FundingPlatform_usp_ImportRunItem_Complete",
        "FundingPlatform_usp_ImportRunItem_Fail",
        "FundingPlatform_usp_ImportRun_Complete",
        "FundingPlatform_usp_ImportRun_Fail",
        "FundingPlatform_usp_PaymentWebhookEvent_Claim",
        "FundingPlatform_usp_PaymentWebhookEvent_Complete",
        "FundingPlatform_usp_Subscription_ReconciliationList",
        "FundingPlatform_usp_SemanticEmbeddingJob_Claim",
        "FundingPlatform_usp_SemanticEmbeddingJob_GetInput",
        "FundingPlatform_usp_SemanticEmbeddingJob_RenewLease",
        "FundingPlatform_usp_SemanticEmbeddingJob_Complete",
        "FundingPlatform_usp_SemanticEmbeddingJob_Fail",
        "FundingPlatform_usp_SemanticEvaluationRun_Claim",
        "FundingPlatform_usp_SemanticEvaluationRun_RenewLease",
        "FundingPlatform_usp_SemanticEvaluationRun_GetWork",
        "FundingPlatform_usp_SemanticEvaluationRun_Complete",
        "FundingPlatform_usp_SemanticEvaluationRun_Wait",
        "FundingPlatform_usp_SemanticEvaluationRun_Fail",
        "FundingPlatform_usp_AiExplanationJob_Claim",
        "FundingPlatform_usp_AiExplanationJob_GetInput",
        "FundingPlatform_usp_AiExplanationJob_RenewLease",
        "FundingPlatform_usp_AiExplanationJob_Complete",
        "FundingPlatform_usp_AiExplanationJob_Fail",
        "FundingPlatform_usp_SourceDocumentExtraction_Claim",
        "FundingPlatform_usp_SourceDocumentExtraction_RenewLease",
        "FundingPlatform_usp_SourceDocumentExtraction_RecordEvidence",
        "FundingPlatform_usp_SourceDocumentExtraction_Complete",
        "FundingPlatform_usp_SourceDocumentExtraction_Fail",
        "FundingPlatform_usp_SourceDocumentExtraction_RequeueStranded"
    ];

    private static readonly string[] GeneralWorkerExcludedProcedures =
    [
        "FundingPlatform_usp_FundingOpportunity_Public_List",
        "FundingPlatform_usp_FundingOpportunity_Public_GetBySlug",
        "FundingPlatform_usp_ImportRun_Admin_Create",
        "FundingPlatform_usp_ImportRun_Admin_List",
        "FundingPlatform_usp_ImportRun_Admin_Get",
        "FundingPlatform_usp_SavedSearch_List",
        "FundingPlatform_usp_SavedSearch_Get",
        "FundingPlatform_usp_SavedSearch_Create",
        "FundingPlatform_usp_SavedSearch_Update",
        "FundingPlatform_usp_SavedSearch_Delete",
        "FundingPlatform_usp_AlertSubscription_Put",
        "FundingPlatform_usp_AlertSubscription_Delete",
        "FundingPlatform_usp_AlertSubscription_Unsubscribe",
        "FundingPlatform_usp_NotificationLog_List",
        "FundingPlatform_usp_SubscriptionPlan_List",
        "FundingPlatform_usp_Subscription_GetCurrent",
        "FundingPlatform_usp_SubscriptionUsage_List",
        "FundingPlatform_usp_SubscriptionCheckout_Begin",
        "FundingPlatform_usp_SubscriptionCheckout_RecordProvider",
        "FundingPlatform_usp_SubscriptionCheckout_Get",
        "FundingPlatform_usp_Subscription_LifecycleBegin",
        "FundingPlatform_usp_PaymentWebhookEvent_Receive",
        "FundingPlatform_usp_AdminSubscription_List",
        "FundingPlatform_usp_AdminBillingDashboard_Get",
        "FundingPlatform_usp_SemanticEvaluationRun_Create",
        "FundingPlatform_usp_SemanticEvaluationRun_List",
        "FundingPlatform_usp_SemanticEvaluationRun_Get",
        "FundingPlatform_usp_SemanticEvaluationRun_Report",
        "FundingPlatform_usp_AiExplanationRun_Create",
        "FundingPlatform_usp_AiExplanationRun_AdminGet",
        "FundingPlatform_usp_SourceDocumentUploadIntent_Create",
        "FundingPlatform_usp_SourceDocumentUploadIntent_AcquireFinalize",
        "FundingPlatform_usp_SourceDocumentUploadIntent_ReleaseFinalize",
        "FundingPlatform_usp_SourceDocumentUploadIntent_RejectFinalize",
        "FundingPlatform_usp_SourceDocumentUploadIntent_Complete",
        "FundingPlatform_usp_SourceDocument_MarkQuarantined",
        "FundingPlatform_usp_SourceDocument_RetryScan",
        "FundingPlatform_usp_SourceDocument_AcquireScanWork",
        "FundingPlatform_usp_SourceDocumentUploadIntent_Get",
        "FundingPlatform_usp_SourceDocument_Get"
    ];
}
