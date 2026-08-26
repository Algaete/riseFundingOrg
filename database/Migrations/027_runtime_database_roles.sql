/* FundingPlatform runtime database roles.
   This forward-only migration grants only the SQL surface used by the API and the
   general Functions host as of migrations 001-026. The isolated extraction host
   keeps FundingPlatform_ExtractionWorkerRole from 016. No database user or role
   membership is created here; deployment binds managed identities explicitly. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF EXISTS
   (
       SELECT 1
       FROM sys.database_principals
       WHERE name IN
             (N'FundingPlatform_ApiRuntimeRole', N'FundingPlatform_GeneralWorkerRole')
         AND type <> N'R'
   )
    THROW 54801, N'A runtime principal name is already used by a non-role principal.', 1;

IF DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole') IS NULL
    CREATE ROLE FundingPlatform_ApiRuntimeRole AUTHORIZATION dbo;
IF DATABASE_PRINCIPAL_ID(N'FundingPlatform_GeneralWorkerRole') IS NULL
    CREATE ROLE FundingPlatform_GeneralWorkerRole AUTHORIZATION dbo;

IF EXISTS
   (
       SELECT 1
       FROM sys.database_principals AS roles
       WHERE roles.name IN
             (N'FundingPlatform_ApiRuntimeRole', N'FundingPlatform_GeneralWorkerRole')
         AND (roles.type <> N'R'
              OR roles.owning_principal_id <> DATABASE_PRINCIPAL_ID(N'dbo'))
   )
    THROW 54802, N'Runtime roles must be database roles owned by dbo.', 1;

IF EXISTS
   (
       SELECT required.RoleName
       FROM (VALUES
           (N'FundingPlatform_ExtractionWorkerRole'),
           (N'FundingPlatform_SemanticWorkerRole'),
           (N'FundingPlatform_SemanticAdminRole'),
           (N'FundingPlatform_AlertWorkerRole')
       ) AS required(RoleName)
       WHERE NOT EXISTS
       (
           SELECT 1
           FROM sys.database_principals AS roles
           WHERE roles.name = required.RoleName
             AND roles.type = N'R'
       )
   )
    THROW 54803, N'Runtime roles require the existing specialist roles from 016, 021 and 024.', 1;

DECLARE @RuntimeProcedures TABLE
(
    RoleName SYSNAME NOT NULL,
    SchemaName SYSNAME NOT NULL,
    ProcedureName SYSNAME NOT NULL,
    PRIMARY KEY (RoleName, SchemaName, ProcedureName)
);

INSERT INTO @RuntimeProcedures (RoleName, SchemaName, ProcedureName)
VALUES
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_AdminBillingDashboard_Get'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_AdminSubscription_List'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_AiExplanationRun_AdminGet'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_AiExplanationRun_Create'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_AlertSubscription_Delete'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_AlertSubscription_Put'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_AlertSubscription_Unsubscribe'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Catalogs_GetForOrganizationProfile'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_ExternalAuthHandoff_Consume'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_ExternalIdentity_Complete'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_ExternalIdentity_Link'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Funder_Admin_Get'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Funder_Admin_List'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Funder_AdminReview'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Funder_Create'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Funder_Deactivate'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Funder_Public_GetBySlug'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Funder_Public_List'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Funder_RequestPublication'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Funder_StartCorrection'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Funder_Update'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingApplication_Create'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingApplication_Get'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingApplication_List'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingApplication_Update'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingOpportunity_Admin_Get'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingOpportunity_Admin_List'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingOpportunity_AdminReview'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingOpportunity_Create'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingOpportunity_Deactivate'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingOpportunity_Favorite_Delete'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingOpportunity_Favorite_List'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingOpportunity_Favorite_Put'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingOpportunity_OrganizationGet'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingOpportunity_OrganizationSearch'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingOpportunity_Public_GetBySlug'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingOpportunity_Public_List'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingOpportunity_RequestPublication'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingOpportunity_StartCorrection'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingOpportunity_Update'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingOpportunityDuplicateCandidate_AdminDecide'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingOpportunityDuplicateCandidate_AdminGet'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingOpportunityDuplicateCandidate_AdminList'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_FundingSource_AdminList'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_ImportRun_Admin_Create'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_ImportRun_Admin_Get'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_ImportRun_Admin_List'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_NotificationLog_List'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Organization_CreateForUser'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Organization_GetProfileByPublicId'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Organization_ListForUser'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Organization_UpdateProfileByPublicId'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_OrganizationCalendar_List'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_OrganizationConnection_Action'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_OrganizationConnection_Create'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_OrganizationConnection_Get'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_OrganizationConnection_List'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_OrganizationMarketplace_Get'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_OrganizationNetworkDirectory_Search'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_OrganizationNetworkingPreference_Get'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_OrganizationNetworkingPreference_Put'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_PaymentWebhookEvent_Receive'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Project_AdminReview'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Project_AdminReview_Get'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Project_AdminReviewQueue_List'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Project_Archive'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Project_Create'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Project_Get'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Project_List'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Project_Public_GetBySlug'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Project_RequestPublication'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Project_Update'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_ProjectMarketplace_GetBySlug'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_ProjectMarketplace_Search'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_ProjectMatchingRun_Create'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_ProjectMatchingRun_Get'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_ProjectMatchingRun_List'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_RefreshToken_Create'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_RefreshToken_RevokeFamily'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_RefreshToken_Rotate'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SavedSearch_Create'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SavedSearch_Delete'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SavedSearch_Get'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SavedSearch_List'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SavedSearch_Update'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SemanticEvaluationRun_Create'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SemanticEvaluationRun_Get'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SemanticEvaluationRun_List'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SemanticEvaluationRun_Report'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SourceDocument_AcquireScanWork'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SourceDocument_ApplyScanResult'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SourceDocument_Get'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SourceDocument_MarkQuarantined'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SourceDocument_RetryScan'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SourceDocumentExtraction_AdminGet'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SourceDocumentExtraction_AdminStart'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SourceDocumentExtractionEvidence_AdminList'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SourceDocumentUploadIntent_AcquireFinalize'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SourceDocumentUploadIntent_Complete'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SourceDocumentUploadIntent_Create'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SourceDocumentUploadIntent_Get'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SourceDocumentUploadIntent_RejectFinalize'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SourceDocumentUploadIntent_ReleaseFinalize'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Subscription_ApplyProviderSnapshot'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Subscription_GetCurrent'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_Subscription_LifecycleBegin'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SubscriptionCheckout_Begin'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SubscriptionCheckout_Get'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SubscriptionCheckout_RecordProvider'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SubscriptionPlan_List'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_SubscriptionUsage_List'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_User_InvalidateSessions'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_User_Register'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_User_ResetPassword'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_User_VerifyEmail'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_UserSecurityToken_Issue');

INSERT INTO @RuntimeProcedures (RoleName, SchemaName, ProcedureName)
VALUES
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_AiExplanationJob_Claim'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_AiExplanationJob_Complete'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_AiExplanationJob_Fail'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_AiExplanationJob_GetInput'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_AiExplanationJob_RenewLease'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_AlertDelivery_Claim'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_AlertDelivery_Complete'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_AlertDelivery_Fail'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_AlertDelivery_RenewLease'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_AlertSchedule_Claim'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_AlertSchedule_Materialize'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_ContentRetention_Enforce'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_FundingOpportunity_StageExternal'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_FundingSource_AcquisitionRequest_Authorize'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_ImportRun_Claim'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_ImportRun_Complete'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_ImportRun_Fail'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_ImportRun_RenewLease'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_ImportRun_RequeueStranded'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_ImportRun_Scheduler_CreateDue'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_ImportRunItem_Complete'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_ImportRunItem_Fail'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_ImportRunItem_ListPending'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_ImportRunOutbox_Claim'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_Outbox_Complete'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_Outbox_Release'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_PaymentWebhookEvent_Claim'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_PaymentWebhookEvent_Complete'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_RawFundingOpportunity_Record'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_SemanticEmbeddingJob_Claim'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_SemanticEmbeddingJob_Complete'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_SemanticEmbeddingJob_Fail'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_SemanticEmbeddingJob_GetInput'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_SemanticEmbeddingJob_RenewLease'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_SemanticEvaluationRun_Claim'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_SemanticEvaluationRun_Complete'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_SemanticEvaluationRun_Fail'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_SemanticEvaluationRun_GetWork'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_SemanticEvaluationRun_RenewLease'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_SemanticEvaluationRun_Wait'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_SourceDocument_ApplyScanResult'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_SourceDocumentContentRetention_Claim'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_SourceDocumentContentRetention_Complete'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_SourceDocumentContentRetention_Fail'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_SourceDocumentDefenderReceipt_Finalize'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_SourceDocumentDefenderReceipt_Record'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_SourceDocumentScan_WatchdogTimeout'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_Subscription_ApplyProviderSnapshot'),
    (N'FundingPlatform_GeneralWorkerRole', N'dbo', N'FundingPlatform_usp_Subscription_ReconciliationList');

IF (SELECT COUNT_BIG(1) FROM @RuntimeProcedures
    WHERE RoleName = N'FundingPlatform_ApiRuntimeRole') <> 116
   OR (SELECT COUNT_BIG(1) FROM @RuntimeProcedures
       WHERE RoleName = N'FundingPlatform_GeneralWorkerRole') <> 49
    THROW 54804, N'The runtime stored-procedure allowlist is incomplete.', 1;

IF EXISTS
   (
       SELECT 1
       FROM @RuntimeProcedures AS required
       WHERE OBJECT_ID(
                 QUOTENAME(required.SchemaName) + N'.' + QUOTENAME(required.ProcedureName),
                 N'P') IS NULL
   )
    THROW 54805, N'A required runtime stored procedure is missing.', 1;

/* Organization search is the only current runtime procedure that invokes
   dynamic full-text SQL. Its module context must remain OWNER so the runtime
   role never needs broad SELECT on the catalog tables. */
DECLARE @OrganizationSearchObjectId INT =
    OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch', N'P');
IF NOT EXISTS
   (
       SELECT 1
       FROM sys.sql_modules AS modules
       WHERE modules.object_id = @OrganizationSearchObjectId
         AND modules.execute_as_principal_id = -2
         AND modules.definition LIKE N'%sys.sp_executesql%'
         AND modules.definition LIKE N'%FREETEXTTABLE%'
   )
   OR NOT EXISTS
      (
          SELECT 1
          FROM sys.schemas AS schemas
          WHERE schemas.schema_id = SCHEMA_ID(N'dbo')
            AND schemas.principal_id = DATABASE_PRINCIPAL_ID(N'dbo')
      )
    THROW 54806, N'Organization search must retain its dbo-owned module context.', 1;

DECLARE @RoleName SYSNAME;
DECLARE @SchemaName SYSNAME;
DECLARE @ProcedureName SYSNAME;
DECLARE @GrantSql NVARCHAR(1000);
DECLARE RuntimeProcedureGrantCursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT RoleName, SchemaName, ProcedureName
    FROM @RuntimeProcedures
    ORDER BY RoleName, SchemaName, ProcedureName;

OPEN RuntimeProcedureGrantCursor;
FETCH NEXT FROM RuntimeProcedureGrantCursor
    INTO @RoleName, @SchemaName, @ProcedureName;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @GrantSql = N'GRANT EXECUTE ON OBJECT::'
        + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@ProcedureName)
        + N' TO ' + QUOTENAME(@RoleName) + N';';
    EXEC sys.sp_executesql @GrantSql;
    FETCH NEXT FROM RuntimeProcedureGrantCursor
        INTO @RoleName, @SchemaName, @ProcedureName;
END;
CLOSE RuntimeProcedureGrantCursor;
DEALLOCATE RuntimeProcedureGrantCursor;

/* ASP.NET Identity and MFA currently use direct SQL for these seven tables.
   SELECT is also required by SQL Server for every searched UPDATE/DELETE. */
GRANT SELECT, INSERT, UPDATE ON OBJECT::dbo.FundingPlatform_Users
    TO FundingPlatform_ApiRuntimeRole;
GRANT SELECT, INSERT, UPDATE ON OBJECT::dbo.FundingPlatform_UserAuthenticatorKeys
    TO FundingPlatform_ApiRuntimeRole;
GRANT SELECT, INSERT, DELETE ON OBJECT::dbo.FundingPlatform_UserRoles
    TO FundingPlatform_ApiRuntimeRole;
GRANT SELECT ON OBJECT::dbo.FundingPlatform_Roles
    TO FundingPlatform_ApiRuntimeRole;
GRANT SELECT, INSERT, UPDATE ON OBJECT::dbo.FundingPlatform_UserMfaChallenges
    TO FundingPlatform_ApiRuntimeRole;
GRANT SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_UserRecoveryCodes
    TO FundingPlatform_ApiRuntimeRole;
GRANT INSERT ON OBJECT::dbo.FundingPlatform_AuthenticationEvents
    TO FundingPlatform_ApiRuntimeRole;

/* A client that sends a table-valued parameter needs both permissions on the
   individual type. Schema-wide type permissions are intentionally avoided. */
IF TYPE_ID(N'dbo.FundingPlatform_SmallIntIdList') IS NULL
   OR TYPE_ID(N'dbo.FundingPlatform_IntIdList') IS NULL
   OR TYPE_ID(N'dbo.FundingPlatform_BigIntIdList') IS NULL
   OR TYPE_ID(N'dbo.FundingPlatform_GuidIdList') IS NULL
   OR TYPE_ID(N'dbo.FundingPlatform_OrganizationLanguageList') IS NULL
    THROW 54807, N'A required API table type is missing.', 1;

GRANT EXECUTE, REFERENCES ON TYPE::dbo.FundingPlatform_SmallIntIdList
    TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE, REFERENCES ON TYPE::dbo.FundingPlatform_IntIdList
    TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE, REFERENCES ON TYPE::dbo.FundingPlatform_BigIntIdList
    TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE, REFERENCES ON TYPE::dbo.FundingPlatform_GuidIdList
    TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE, REFERENCES ON TYPE::dbo.FundingPlatform_OrganizationLanguageList
    TO FundingPlatform_ApiRuntimeRole;

IF EXISTS
   (
       SELECT 1
       FROM @RuntimeProcedures AS expected
       WHERE NOT EXISTS
       (
           SELECT 1
           FROM sys.database_permissions AS permissions
           WHERE permissions.grantee_principal_id =
                 DATABASE_PRINCIPAL_ID(expected.RoleName)
             AND permissions.class = 1
             AND permissions.major_id = OBJECT_ID(
                 QUOTENAME(expected.SchemaName) + N'.' + QUOTENAME(expected.ProcedureName),
                 N'P')
             AND permissions.permission_name = N'EXECUTE'
             AND permissions.state = N'G'
       )
   )
   OR (SELECT COUNT_BIG(1)
       FROM sys.database_permissions
       WHERE grantee_principal_id =
             DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole')) <> 144
   OR (SELECT COUNT_BIG(1)
       FROM sys.database_permissions
       WHERE grantee_principal_id =
             DATABASE_PRINCIPAL_ID(N'FundingPlatform_GeneralWorkerRole')) <> 49
    THROW 54808, N'Runtime role permissions do not match the frozen allowlist.', 1;

/* Defense in depth: neither runtime role is nested in a fixed/broad role and
   this migration does not add users or any other role membership. */
IF EXISTS
   (
       SELECT 1
       FROM sys.database_role_members AS memberships
       WHERE memberships.member_principal_id IN
             (DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole'),
              DATABASE_PRINCIPAL_ID(N'FundingPlatform_GeneralWorkerRole'))
   )
    THROW 54809, N'Runtime roles must not inherit another database role.', 1;
