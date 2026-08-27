/* Transactional FASE 9B-A smoke: bounded embeddings and corpus-level shadow evaluation. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF EXISTS
   (SELECT required.Name
    FROM (VALUES
          (N'FundingPlatform_SemanticConfigurations'),
          (N'FundingPlatform_SemanticEvaluationSets'),
          (N'FundingPlatform_SemanticEvaluationCases'),
          (N'FundingPlatform_SemanticEmbeddingJobs'),
          (N'FundingPlatform_SemanticEmbeddings'),
          (N'FundingPlatform_SemanticBudgetReservations'),
          (N'FundingPlatform_SemanticUsageLedger'),
          (N'FundingPlatform_SemanticEvaluationRuns'),
          (N'FundingPlatform_SemanticEvaluationRunCases'),
          (N'FundingPlatform_SemanticEvaluationItems'),
          (N'FundingPlatform_SemanticEvaluationRunRequests')) AS required(Name)
    WHERE OBJECT_ID(N'dbo.' + required.Name, N'U') IS NULL)
    THROW 54201, N'FASE 9B-A tables are incomplete.', 1;

IF EXISTS
   (SELECT required.Name
    FROM (VALUES
          (N'FundingPlatform_fn_SemanticCanonicalIdArray', N'FN'),
          (N'FundingPlatform_fn_ProjectSemanticCanonicalInput', N'FN'),
          (N'FundingPlatform_fn_OpportunitySemanticCanonicalInput', N'FN'),
          (N'FundingPlatform_fn_SemanticInputHash', N'FN'),
          (N'FundingPlatform_fn_SemanticInputRiskCode', N'FN'),
          (N'FundingPlatform_ifn_SemanticConfigurationState', N'IF'),
          (N'FundingPlatform_ifn_SemanticEvaluationSetState', N'IF'),
          (N'FundingPlatform_ifn_SemanticEvaluationRunSummaries', N'IF')) AS required(Name, Kind)
    WHERE OBJECT_ID(N'dbo.' + required.Name, required.Kind) IS NULL)
    THROW 54202, N'FASE 9B-A canonical, fingerprint or report functions are incomplete.', 1;

IF EXISTS
   (SELECT required.Name
    FROM (VALUES
          (N'FundingPlatform_usp_SemanticEmbeddingJob_BackfillEnqueue'),
          (N'FundingPlatform_usp_SemanticEmbeddingJob_Claim'),
          (N'FundingPlatform_usp_SemanticEmbeddingJob_GetInput'),
          (N'FundingPlatform_usp_SemanticEmbeddingJob_RenewLease'),
          (N'FundingPlatform_usp_SemanticEmbeddingJob_Complete'),
          (N'FundingPlatform_usp_SemanticEmbeddingJob_Fail'),
          (N'FundingPlatform_usp_SemanticEvaluationRun_Create'),
          (N'FundingPlatform_usp_SemanticEvaluationRun_Claim'),
          (N'FundingPlatform_usp_SemanticEvaluationRun_RenewLease'),
          (N'FundingPlatform_usp_SemanticEvaluationRun_GetWork'),
          (N'FundingPlatform_usp_SemanticEvaluationRun_Complete'),
          (N'FundingPlatform_usp_SemanticEvaluationRun_Wait'),
          (N'FundingPlatform_usp_SemanticEvaluationRun_Fail'),
          (N'FundingPlatform_usp_SemanticEvaluationRun_List'),
          (N'FundingPlatform_usp_SemanticEvaluationRun_Get'),
          (N'FundingPlatform_usp_SemanticEvaluationRun_Report')) AS required(Name)
    WHERE OBJECT_ID(N'dbo.' + required.Name, N'P') IS NULL)
    THROW 54203, N'FASE 9B-A worker or administrator procedures are incomplete.', 1;

IF EXISTS
   (SELECT required.Name
    FROM (VALUES
          (N'FundingPlatform_tr_SemanticConfigurations_Immutable'),
          (N'FundingPlatform_tr_SemanticEvaluationSets_Immutable'),
          (N'FundingPlatform_tr_SemanticEvaluationCases_Immutable'),
          (N'FundingPlatform_tr_SemanticEvaluationCases_SubjectGuard'),
          (N'FundingPlatform_tr_SemanticEmbeddingJobs_SubjectGuard'),
          (N'FundingPlatform_tr_SemanticEmbeddingJobs_Lifecycle'),
          (N'FundingPlatform_tr_SemanticEmbeddings_SubjectGuard'),
          (N'FundingPlatform_tr_SemanticEmbeddings_SupersessionOnly'),
          (N'FundingPlatform_tr_SemanticBudgetReservations_Lifecycle'),
          (N'FundingPlatform_tr_SemanticBudgetReservations_SubjectGuard'),
          (N'FundingPlatform_tr_SemanticUsageLedger_Immutable'),
          (N'FundingPlatform_tr_SemanticEvaluationRuns_SubjectGuard'),
          (N'FundingPlatform_tr_SemanticEvaluationRuns_PromotionGuard'),
          (N'FundingPlatform_tr_SemanticEvaluationRuns_Lifecycle'),
          (N'FundingPlatform_tr_SemanticEvaluationRunCases_CopyGuard'),
          (N'FundingPlatform_tr_SemanticEvaluationRunCases_Immutable'),
          (N'FundingPlatform_tr_SemanticEvaluationItems_SubjectGuard'),
          (N'FundingPlatform_tr_SemanticEvaluationItems_Immutable'),
          (N'FundingPlatform_tr_SemanticEvaluationRunRequests_Immutable')) AS required(Name)
    WHERE OBJECT_ID(N'dbo.' + required.Name, N'TR') IS NULL
       OR COALESCE(OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + required.Name)), N'')
          NOT LIKE N'%SET XACT_ABORT OFF%')
    THROW 54204, N'FASE 9B-A immutable or fail-closed triggers are incomplete.', 1;

IF NOT EXISTS
   (SELECT 1
    FROM sys.triggers
    WHERE object_id =
          OBJECT_ID(N'dbo.FundingPlatform_tr_SemanticEvaluationItems_SubjectGuard')
      AND parent_id = OBJECT_ID(N'dbo.FundingPlatform_SemanticEvaluationItems')
      AND is_disabled = 0
      AND is_instead_of_trigger = 1)
    THROW 54262, N'The semantic item subject guard does not validate before mutation.', 1;

IF NOT EXISTS
   (SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.FundingPlatform_SemanticEmbeddings')
      AND name = N'Embedding' AND TYPE_NAME(user_type_id) = N'vector'
      AND vector_dimensions = 1536 AND vector_base_type = 0)
   OR COL_LENGTH(N'dbo.FundingPlatform_SemanticEmbeddings', N'CanonicalInputJson') IS NOT NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_SemanticEmbeddingJobs', N'CanonicalInputJson') IS NOT NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_SemanticEvaluationItems', N'Prompt') IS NOT NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_SemanticEvaluationItems', N'RawResponse') IS NOT NULL
    THROW 54205, N'Native vector or no-raw persistence contract drifted.', 1;

IF NOT EXISTS
   (SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.FundingPlatform_SemanticEvaluationRuns')
      AND name = N'FundingPlatform_UQ_SemanticEvaluationRuns_Active' AND is_unique = 1)
   OR NOT EXISTS
   (SELECT 1 FROM sys.index_columns AS indexColumns
    INNER JOIN sys.columns AS columns
        ON columns.object_id = indexColumns.object_id
       AND columns.column_id = indexColumns.column_id
    INNER JOIN sys.indexes AS indexes
        ON indexes.object_id = indexColumns.object_id
       AND indexes.index_id = indexColumns.index_id
    WHERE indexes.object_id = OBJECT_ID(N'dbo.FundingPlatform_SemanticEvaluationRuns')
      AND indexes.name = N'FundingPlatform_UQ_SemanticEvaluationRuns_Active'
      AND columns.name = N'ActiveSlot')
    THROW 54206, N'The global singleton semantic evaluation gate is missing.', 1;

IF DATABASE_PRINCIPAL_ID(N'FundingPlatform_SemanticWorkerRole') IS NULL
   OR DATABASE_PRINCIPAL_ID(N'FundingPlatform_SemanticAdminRole') IS NULL
   OR NOT EXISTS
      (SELECT 1 FROM sys.database_permissions AS permissions
       WHERE permissions.grantee_principal_id =
             DATABASE_PRINCIPAL_ID(N'FundingPlatform_SemanticWorkerRole')
         AND permissions.major_id =
             OBJECT_ID(N'dbo.FundingPlatform_usp_SemanticEmbeddingJob_Claim')
         AND permissions.permission_name = N'EXECUTE' AND permissions.state = N'G')
   OR NOT EXISTS
      (SELECT 1 FROM sys.database_permissions AS permissions
       WHERE permissions.grantee_principal_id =
             DATABASE_PRINCIPAL_ID(N'FundingPlatform_SemanticAdminRole')
         AND permissions.major_id =
             OBJECT_ID(N'dbo.FundingPlatform_usp_SemanticEvaluationRun_Report')
         AND permissions.permission_name = N'EXECUTE' AND permissions.state = N'G')
   OR NOT EXISTS
      (SELECT 1 FROM sys.database_permissions AS permissions
       WHERE permissions.grantee_principal_id =
             DATABASE_PRINCIPAL_ID(N'FundingPlatform_SemanticWorkerRole')
         AND permissions.major_id = OBJECT_ID(N'dbo.FundingPlatform_SemanticEmbeddings')
         AND permissions.permission_name = N'SELECT' AND permissions.state = N'D')
   OR NOT EXISTS
      (SELECT 1 FROM sys.database_permissions AS permissions
       WHERE permissions.grantee_principal_id =
             DATABASE_PRINCIPAL_ID(N'FundingPlatform_SemanticAdminRole')
         AND permissions.major_id = OBJECT_ID(N'dbo.FundingPlatform_SemanticEvaluationItems')
         AND permissions.permission_name = N'UPDATE' AND permissions.state = N'D')
    THROW 54218, N'Semantic worker/admin least-privilege roles or grants/denies are incomplete.', 1;

IF EXISTS
   (SELECT 1
    FROM (VALUES
          (N'PublicId'), (N'Status'), (N'EvaluationSetVersion'),
          (N'SemanticConfigurationVersion'), (N'ProviderCode'), (N'ModelCode'),
          (N'Dimensions'), (N'PurposeCode'), (N'NormalizationVersion'),
          (N'ProjectCount'), (N'OpportunityCount'), (N'PairCount'),
          (N'PrimaryCohortCount'), (N'EvaluatedCount'), (N'LabelledCount'),
          (N'CoveragePercentage'), (N'ProviderSuccessPercentage'), (N'RecallAt10'),
          (N'NormalizedDiscountedCumulativeGainAt10'),
          (N'BaselineNormalizedDiscountedCumulativeGainAt10'),
          (N'NormalizedDiscountedCumulativeGainDelta'),
          (N'MeanReciprocalRankAt10'), (N'MeanRankDelta'),
          (N'TotalEstimatedCostUsd'), (N'LatencyP95Milliseconds'),
          (N'HardGatePromotionCount'), (N'MeetsPromotionGate'),
          (N'CreatedAtUtc'), (N'StartedAtUtc'), (N'CompletedAtUtc'),
          (N'LastErrorCode')) AS required(Name)
    WHERE NOT EXISTS
       (SELECT 1 FROM sys.columns
        WHERE object_id = OBJECT_ID(N'dbo.FundingPlatform_ifn_SemanticEvaluationRunSummaries')
          AND name = required.Name))
    THROW 54207, N'Semantic administrator summary wire shape drifted.', 1;

DECLARE @ClaimDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_SemanticEmbeddingJob_Claim'));
DECLARE @CompleteDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_SemanticEvaluationRun_Complete'));
DECLARE @CreateDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_SemanticEvaluationRun_Create'));
DECLARE @BackfillDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_SemanticEmbeddingJob_BackfillEnqueue'));
DECLARE @FailureDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_SemanticEmbeddingJob_Fail'));
DECLARE @PromotionDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_tr_SemanticEvaluationRuns_PromotionGuard'));

IF @ClaimDefinition NOT LIKE N'%FundingPlatform:SemanticBudget%'
   OR @ClaimDefinition NOT LIKE N'%ExpiredReservations%'
   OR @ClaimDefinition NOT LIKE N'%N''charge-uncertain''%'
   OR @ClaimDefinition NOT LIKE N'%MaximumBatchSize%'
   OR @ClaimDefinition NOT LIKE N'%MaximumCostUsdPerEmbedding%'
   OR @ClaimDefinition NOT LIKE N'%@AvailableBudget >= @MaximumCost * @BatchSize%'
   OR @FailureDefinition NOT LIKE N'%@ProviderCallMayHaveBeenCharged%'
   OR @FailureDefinition NOT LIKE N'%Status = 1, ConsumedCostUsd = ReservedCostUsd%'
   OR @BackfillDefinition NOT LIKE N'%WITH (UPDLOCK, HOLDLOCK)%'
   OR @BackfillDefinition NOT LIKE N'%configurations.IsActive = 1%'
    THROW 54208, N'Lease, hard-budget, uncertain-charge or deactivation serialization drifted.', 1;

IF @CreateDefinition NOT LIKE N'%N''configuration-not-approved''%'
   OR @CreateDefinition NOT LIKE N'%N''eval-set-not-ready''%'
   OR @CreateDefinition NOT LIKE N'%N''budget-insufficient''%'
   OR @CreateDefinition NOT LIKE N'%FundingPlatform:SemanticEvaluation:Active%'
   OR @CreateDefinition NOT LIKE N'%FundingPlatform:SemanticBudget%'
   OR @CreateDefinition NOT LIKE N'%@ActualLabels NOT BETWEEN 300 AND 5000%'
   OR @CreateDefinition NOT LIKE N'%MIN(Split) <> MAX(Split)%'
   OR @CreateDefinition NOT LIKE N'%COUNT(DISTINCT ProjectId)%< 10%'
   OR @CreateDefinition NOT LIKE N'%Split = 1) < 100%'
   OR @CreateDefinition NOT LIKE N'%ProjectContentAddress%'
   OR @CreateDefinition LIKE N'%SemanticEvaluationRequested%'
    THROW 54209, N'Corpus readiness, idempotency, budget preflight or polling-only queue drifted.', 1;

IF @CompleteDefinition NOT LIKE N'%VECTOR_DISTANCE(''cosine''%'
   OR @CompleteDefinition NOT LIKE N'%PARTITION BY ready.ProjectMatchingRunId%'
   OR @CompleteDefinition NOT LIKE N'%ready.CosineDistance ASC%'
   OR @CompleteDefinition NOT LIKE N'%CASE ready.Classification WHEN 0 THEN 0 WHEN 2 THEN 1%'
   OR @CompleteDefinition NOT LIKE N'%matches.CloseDate%'
   OR @CompleteDefinition NOT LIKE N'%RelevanceLabel > 0%'
   OR @CompleteDefinition NOT LIKE N'%ledger.RecordedAtUtc >= @RunCreatedAtUtc%'
   OR @CompleteDefinition NOT LIKE N'%@AvailableSubjectCount%'
   OR @CompleteDefinition NOT LIKE N'%@EvaluatedCount = @PairCount%'
   OR @CompleteDefinition LIKE N'%UPDATE dbo.FundingPlatform_ProjectMatchingRuns%'
   OR @CompleteDefinition LIKE N'%UPDATE dbo.FundingPlatform_ProjectFundingMatches%'
    THROW 54210, N'Exact per-project shadow ranking, incremental cost or 9A isolation drifted.', 1;

IF @PromotionDefinition NOT LIKE N'%inserted.EvaluatedCount <> inserted.PairCount%'
   OR @PromotionDefinition NOT LIKE N'%inserted.CoveragePercentage < 95%'
   OR @PromotionDefinition NOT LIKE N'%inserted.SuccessPercentage < 99%'
   OR @PromotionDefinition NOT LIKE N'%inserted.RecallAt10 < 0.80%'
   OR @PromotionDefinition NOT LIKE N'%inserted.NdcgAt10 < 0.75%'
   OR @PromotionDefinition NOT LIKE N'%inserted.NdcgDelta < 0.05%'
   OR @PromotionDefinition NOT LIKE N'%inserted.HardFailPromotedCount <> 0%'
    THROW 54211, N'Exact full-corpus shadow promotion thresholds drifted.', 1;

DECLARE @NumericIds NVARCHAR(MAX) =
    dbo.FundingPlatform_fn_SemanticCanonicalIdArray(N'[2,1,2]');
DECLARE @ObjectIds NVARCHAR(MAX) =
    dbo.FundingPlatform_fn_SemanticCanonicalIdArray(N'[{"id":2},{"id":1},{"id":2}]');
IF @NumericIds <> N'[1,2]' OR @ObjectIds <> @NumericIds
   OR dbo.FundingPlatform_fn_SemanticCanonicalIdArray(N'[{"id":"bad"}]') IS NOT NULL
   OR dbo.FundingPlatform_fn_SemanticCanonicalIdArray(N'{"id":1}') IS NOT NULL
    THROW 54212, N'Canonical taxonomy normalization is not scalar/object stable and fail-closed.', 1;

DECLARE @ProjectCanonical NVARCHAR(MAX) = dbo.FundingPlatform_fn_ProjectSemanticCanonicalInput
(
    N'{"title":"A private person name","summary":"community work","description":"safe description",'
    + N'"status":1,"startDate":"2026-01-01","endDate":"2026-12-31",'
    + N'"budgetTotal":1000,"confirmedFunding":100,"currency":"CLP",'
    + N'"countryIds":[2,1,2],"regionIds":[{"id":2},{"id":1}],'
    + N'"categoryIds":[1],"beneficiaryTypeIds":[1],"projectTypeIds":[1]}'
);
IF @ProjectCanonical IS NULL OR ISJSON(@ProjectCanonical) <> 1
   OR JSON_VALUE(@ProjectCanonical, N'$.schemaVersion') <> N'semantic-input-v1'
   OR JSON_VALUE(@ProjectCanonical, N'$.normalizationVersion') <> N'semantic-text-v1'
   OR JSON_VALUE(@ProjectCanonical, N'$.title') IS NOT NULL
   OR @ProjectCanonical LIKE N'%A private person name%'
   OR JSON_QUERY(@ProjectCanonical, N'$.countryIds') <> N'[1,2]'
   OR JSON_QUERY(@ProjectCanonical, N'$.regionIds') <> N'[1,2]'
    THROW 54213, N'Project canonical input leaked title/private identity or became unstable.', 1;

IF dbo.FundingPlatform_fn_SemanticInputRiskCode
      (N'{"schemaVersion":"semantic-input-v1","description":"a@example.org"}', 8192)
      <> N'pii-email-detected'
   OR dbo.FundingPlatform_fn_SemanticInputRiskCode
      (N'{"schemaVersion":"semantic-input-v1","description":"https://example.org"}', 8192)
      <> N'pii-url-detected'
   OR dbo.FundingPlatform_fn_SemanticInputRiskCode
      (N'{"schemaVersion":"semantic-input-v1","description":"12345678-5"}', 8192)
      <> N'pii-rut-detected'
   OR dbo.FundingPlatform_fn_SemanticInputRiskCode
      (N'{"schemaVersion":"semantic-input-v1","description":"12.345.678-5"}', 8192)
      <> N'pii-rut-detected'
    THROW 54214, N'Pre-provider privacy screening drifted.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke021;
BEGIN TRY
    DECLARE @Suffix NVARCHAR(16) = LOWER(LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 16));
    DECLARE @Code NVARCHAR(50) = N'smoke-' + @Suffix;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @Fingerprint BINARY(32) = CONVERT(BINARY(32), HASHBYTES
    (
        'SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
        (@Code, N'|1|development-deterministic|lexical-hash-1536-v1|1536|matching|',
         N'project-semantic-v1|opportunity-semantic-v1|semantic-text-v1|1|',
         N'cosine-linear-shadow-v1|8192|8|3|0.000000|1.000000|1'))
    ));
    INSERT INTO dbo.FundingPlatform_SemanticConfigurations
        (Code, Version, ProviderCode, ModelCode, Dimensions, PurposeCode,
         ProjectTemplateVersion, OpportunityTemplateVersion, NormalizationVersion,
         DistanceMetric, CalibrationVersion, MaximumInputUtf8Bytes, MaximumBatchSize,
         MaximumAttempts, MaximumCostUsdPerEmbedding, MonthlyBudgetUsd,
         ConfigurationFingerprint, IsLocalFake, IsActive, PublishedAtUtc, CreatedAtUtc)
    VALUES
        (@Code, 1, N'development-deterministic', N'lexical-hash-1536-v1', 1536,
         N'matching', N'project-semantic-v1', N'opportunity-semantic-v1',
         N'semantic-text-v1', 1, N'cosine-linear-shadow-v1', 8192, 8, 3,
         0.000000, 1.000000, @Fingerprint, 1, 0, @NowUtc, @NowUtc);
    DECLARE @ConfigurationId INT = SCOPE_IDENTITY();
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ifn_SemanticConfigurationState(@ConfigurationId)
        WHERE CalculatedFingerprint = @Fingerprint)
        THROW 54215, N'Frozen semantic configuration fingerprint did not round-trip.', 1;

    DECLARE @MutationError INT = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        UPDATE dbo.FundingPlatform_SemanticConfigurations
        SET MaximumBatchSize = 9 WHERE Id = @ConfigurationId;
    END TRY
    BEGIN CATCH SET @MutationError = ERROR_NUMBER(); END CATCH;
    SET XACT_ABORT ON;
    IF @MutationError NOT IN (54102, 54103) OR XACT_STATE() <> 1
        THROW 54216, N'Published semantic configuration was mutable or doomed the transaction.', 1;

    SET @MutationError = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        INSERT INTO dbo.FundingPlatform_SemanticConfigurations
            (Code, Version, ProviderCode, ModelCode, Dimensions, PurposeCode,
             ProjectTemplateVersion, OpportunityTemplateVersion, NormalizationVersion,
             DistanceMetric, CalibrationVersion, MaximumInputUtf8Bytes, MaximumBatchSize,
             MaximumAttempts, MaximumCostUsdPerEmbedding, MonthlyBudgetUsd,
             ConfigurationFingerprint, IsLocalFake, IsActive, PublishedAtUtc, CreatedAtUtc)
        VALUES
            (N'bad-' + @Suffix, 1, N'development-deterministic', N'lexical-hash-1536-v1',
             1536, N'matching', N'project-semantic-v1', N'opportunity-semantic-v1',
             N'semantic-text-v1', 1, N'cosine-linear-shadow-v1', 8192, 8, 3,
             0.001000, 1.000000, 0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA,
             0, 0, @NowUtc, @NowUtc);
    END TRY
    BEGIN CATCH SET @MutationError = ERROR_NUMBER(); END CATCH;
    SET XACT_ABORT ON;
    IF @MutationError <> 547 OR XACT_STATE() <> 1
        THROW 54217, N'Local fake provider/model could be disguised as a real provider.', 1;

    SET @MutationError = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        INSERT INTO dbo.FundingPlatform_SemanticConfigurations
            (Code, Version, ProviderCode, ModelCode, Dimensions, PurposeCode,
             ProjectTemplateVersion, OpportunityTemplateVersion, NormalizationVersion,
             DistanceMetric, CalibrationVersion, MaximumInputUtf8Bytes, MaximumBatchSize,
             MaximumAttempts, MaximumCostUsdPerEmbedding, MonthlyBudgetUsd,
             ConfigurationFingerprint, IsLocalFake, IsActive, PublishedAtUtc, CreatedAtUtc)
        VALUES
            (N'bad-case-' + @Suffix, 1, N'Development-deterministic',
             N'lexical-hash-1536-v1', 1536, N'matching', N'project-semantic-v1',
             N'opportunity-semantic-v1', N'semantic-text-v1', 1,
             N'cosine-linear-shadow-v1', 8192, 8, 3, 0, 1,
             0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB,
             1, 0, @NowUtc, @NowUtc);
    END TRY
    BEGIN CATCH SET @MutationError = ERROR_NUMBER(); END CATCH;
    SET XACT_ABORT ON;
    IF @MutationError <> 547 OR XACT_STATE() <> 1
        THROW 54253, N'Case-drifted provider identity passed an ordinal contract check.', 1;

    SET @MutationError = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        INSERT INTO dbo.FundingPlatform_SemanticConfigurations
            (Code, Version, ProviderCode, ModelCode, Dimensions, PurposeCode,
             ProjectTemplateVersion, OpportunityTemplateVersion, NormalizationVersion,
             DistanceMetric, CalibrationVersion, MaximumInputUtf8Bytes, MaximumBatchSize,
             MaximumAttempts, MaximumCostUsdPerEmbedding, MonthlyBudgetUsd,
             ConfigurationFingerprint, IsLocalFake, IsActive, PublishedAtUtc, CreatedAtUtc)
        VALUES
            (N'bad-space-' + @Suffix, 1, N'development-deterministic',
             N'lexical-hash-1536-v1 ', 1536, N'matching', N'project-semantic-v1',
             N'opportunity-semantic-v1', N'semantic-text-v1', 1,
             N'cosine-linear-shadow-v1', 8192, 8, 3, 0, 1,
             0xCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC,
             1, 0, @NowUtc, @NowUtc);
    END TRY
    BEGIN CATCH SET @MutationError = ERROR_NUMBER(); END CATCH;
    SET XACT_ABORT ON;
    IF @MutationError <> 547 OR XACT_STATE() <> 1
        THROW 54254, N'Trailing-space model identity passed an exact contract check.', 1;

    SET @MutationError = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        INSERT INTO dbo.FundingPlatform_SemanticConfigurations
            (Code, Version, ProviderCode, ModelCode, Dimensions, PurposeCode,
             ProjectTemplateVersion, OpportunityTemplateVersion, NormalizationVersion,
             DistanceMetric, CalibrationVersion, MaximumInputUtf8Bytes, MaximumBatchSize,
             MaximumAttempts, MaximumCostUsdPerEmbedding, MonthlyBudgetUsd,
             ConfigurationFingerprint, IsLocalFake, IsActive, PublishedAtUtc, CreatedAtUtc)
        VALUES
            (N'bad-fake-cost-' + @Suffix, 1, N'development-deterministic',
             N'lexical-hash-1536-v1', 1536, N'matching', N'project-semantic-v1',
             N'opportunity-semantic-v1', N'semantic-text-v1', 1,
             N'cosine-linear-shadow-v1', 8192, 8, 3, 0.000001, 1,
             0xDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD,
             1, 0, @NowUtc, @NowUtc);
    END TRY
    BEGIN CATCH SET @MutationError = ERROR_NUMBER(); END CATCH;
    SET XACT_ABORT ON;
    IF @MutationError <> 547 OR XACT_STATE() <> 1
        THROW 54255, N'Local deterministic processing accepted a nonzero provider cost.', 1;

    /* Independent corpus fixture: 30 exact historical projects, 100 exact
       opportunity versions and 300 curated 9A matches across Dev/Test. */
    DECLARE @AdminRoleId SMALLINT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_Roles
         WHERE NormalizedName IN (N'ADMIN', N'SUPERADMIN') ORDER BY Id);
    DECLARE @OrganizationTypeId SMALLINT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_OrganizationTypes
         WHERE IsActive = 1 ORDER BY Id);
    DECLARE @LegalEntityTypeId SMALLINT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_LegalEntityTypes
         WHERE IsActive = 1 ORDER BY Id);
    DECLARE @MatchingProfileId INT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_MatchingProfiles
         WHERE Status = 2 AND IsActive = 1 ORDER BY Id);
    IF @AdminRoleId IS NULL OR @OrganizationTypeId IS NULL OR @MatchingProfileId IS NULL
        THROW 54219, N'Active admin, organization and 9A matching catalogs are required.', 1;

    DECLARE @AdminPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @AdminEmail NVARCHAR(320) = N'fase9b-admin-' + @Suffix + N'@example.invalid';
    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@AdminPublicId, @AdminEmail, UPPER(@AdminEmail), N'FASE 9B smoke admin',
         N'not-a-credential', N'fase9b-smoke', 1, 1, 2, N'es-CL');
    DECLARE @AdminUserId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @AdminPublicId);
    INSERT INTO dbo.FundingPlatform_UserRoles (UserId, RoleId, GrantedByUserId, CreatedAtUtc)
    VALUES (@AdminUserId, @AdminRoleId, @AdminUserId, @NowUtc);

    DECLARE @OrganizationPublicId UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.FundingPlatform_Organizations
        (PublicId, CreatedByUserId, Name, HomeCountryId, OrganizationTypeId,
         LegalEntityTypeId, PreviousFundingExperience, ProfileStatus,
         ProfileCompleteness, ProfileVersion, IsActive)
    VALUES
        (@OrganizationPublicId, @AdminUserId, N'FASE 9B smoke organization ' + @Suffix,
         152, @OrganizationTypeId, @LegalEntityTypeId, 2, 2, 100, 1, 1);
    DECLARE @OrganizationId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Organizations WHERE PublicId = @OrganizationPublicId);
    INSERT INTO dbo.FundingPlatform_OrganizationProfileVersions
        (OrganizationId, ProfileVersion, SnapshotJson, ContentHash,
         CreatedByUserId, CreatedAtUtc)
    VALUES
        (@OrganizationId, 1, N'{"schema":"semantic-smoke-org-v1"}',
         HASHBYTES('SHA2_256', N'semantic-smoke-org-' + @Suffix),
         @AdminUserId, @NowUtc);

    DECLARE @Projects TABLE
    (
        SequenceNumber INT NOT NULL PRIMARY KEY,
        ProjectId BIGINT NOT NULL,
        ProjectPublicId UNIQUEIDENTIFIER NOT NULL,
        ContentHash BINARY(32) NOT NULL
    );
    DECLARE @ProjectSequence INT = 1;
    WHILE @ProjectSequence <= 30
    BEGIN
        DECLARE @ProjectPublicId UNIQUEIDENTIFIER = NEWID();
        DECLARE @ProjectSnapshot NVARCHAR(MAX) = CONCAT
        (
            N'{"title":"private fixture ', @ProjectSequence,
            N'","summary":"community impact ', @ProjectSequence,
            N'","description":"safe community program","status":2,',
            N'"startDate":"2026-01-01","endDate":"2026-12-31",',
            N'"budgetTotal":1000,"confirmedFunding":100,"currency":"CLP",',
            N'"countryIds":[2,1,2],"regionIds":[],"categoryIds":[2,1],',
            N'"beneficiaryTypeIds":[1],"projectTypeIds":[1]}'
        );
        DECLARE @ProjectHash BINARY(32) =
            HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @ProjectSnapshot));
        INSERT INTO dbo.FundingPlatform_Projects
            (PublicId, OrganizationId, CreatedByUserId, Slug, Title, Summary,
             Description, ProjectStatus, PublicationStatus, ProjectVersion,
             IsActive, CreatedAtUtc, UpdatedAtUtc)
        VALUES
            (@ProjectPublicId, @OrganizationId, @AdminUserId,
             CONCAT(N'fase9b-p-', @ProjectSequence, N'-', @Suffix),
             CONCAT(N'Private fixture ', @ProjectSequence), N'Community impact',
             N'Safe community program', 2, 0, 1, 1, @NowUtc, @NowUtc);
        DECLARE @ProjectId BIGINT = SCOPE_IDENTITY();
        INSERT INTO dbo.FundingPlatform_ProjectVersions
            (ProjectId, ProjectVersion, SnapshotJson, ContentHash,
             CreatedByUserId, CreatedAtUtc)
        VALUES (@ProjectId, 1, @ProjectSnapshot, @ProjectHash, @AdminUserId, @NowUtc);
        INSERT INTO @Projects VALUES
            (@ProjectSequence, @ProjectId, @ProjectPublicId, @ProjectHash);
        SET @ProjectSequence += 1;
    END;

    DECLARE @Opportunities TABLE
    (
        SequenceNumber INT NOT NULL PRIMARY KEY,
        FundingOpportunityId BIGINT NOT NULL,
        OpportunityPublicId UNIQUEIDENTIFIER NOT NULL,
        ContentHash BINARY(32) NOT NULL
    );
    DECLARE @OpportunitySequence INT = 1;
    WHILE @OpportunitySequence <= 100
    BEGIN
        DECLARE @OpportunityPublicId UNIQUEIDENTIFIER = NEWID();
        DECLARE @OpportunitySnapshot NVARCHAR(MAX) = CONCAT
        (
            N'{"title":"Public fund ', @OpportunitySequence,
            N'","description":"public opportunity","summary":"public impact",',
            N'"sponsorName":"Public sponsor","currency":null,"minAmount":null,',
            N'"maxAmount":null,"eligibilityDescription":"registered organizations",',
            N'"requirements":"public requirements","objectives":"public objectives",',
            N'"allowedActivities":null,"excludedActivities":null,"restrictions":null,',
            N'"targetOrganizationsDescription":"nonprofits",',
            N'"targetPopulationsDescription":"communities","minimumOperatingYears":0,',
            N'"requiresLegalEntity":false,"requiresPriorExperience":false,',
            N'"requiresCofunding":false,"cofundingPercentage":null,"geographicScope":2,',
            N'"countryIds":[{"id":2},{"id":1},{"id":2}],"regionIds":[],',
            N'"categoryIds":[{"id":1}],"beneficiaryTypeIds":[{"id":1}],',
            N'"projectTypeIds":[{"id":1}]}'
        );
        DECLARE @OpportunityHash BINARY(32) =
            HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @OpportunitySnapshot));
        INSERT INTO dbo.FundingPlatform_FundingOpportunities
            (PublicId, Slug, Title, SponsorName, AmountStatus, DeadlineType,
             DeadlinePrecision, GeographicScope, RemoteApplication,
             PublicationStatus, DataQualityScore, ContentVersion, IsActive,
             CreatedAtUtc, UpdatedAtUtc)
        VALUES
            (@OpportunityPublicId,
             CONCAT(N'fase9b-o-', @OpportunitySequence, N'-', @Suffix),
             CONCAT(N'Public fund ', @OpportunitySequence), N'Public sponsor',
             0, 0, 0, 2, 1, 0, 100, 1, 1, @NowUtc, @NowUtc);
        DECLARE @OpportunityId BIGINT = SCOPE_IDENTITY();
        INSERT INTO dbo.FundingPlatform_FundingOpportunityVersions
            (FundingOpportunityId, ContentVersion, SnapshotJson, ContentHash,
             CreatedByUserId, CreatedAtUtc)
        VALUES
            (@OpportunityId, 1, @OpportunitySnapshot, @OpportunityHash,
             @AdminUserId, @NowUtc);
        INSERT INTO @Opportunities VALUES
            (@OpportunitySequence, @OpportunityId, @OpportunityPublicId, @OpportunityHash);
        SET @OpportunitySequence += 1;
    END;

    DECLARE @ProfileCode NVARCHAR(100), @ProfileVersion INT, @EngineVersion NVARCHAR(50);
    DECLARE @RuleSetFingerprint BINARY(32);
    SELECT @ProfileCode = Code, @ProfileVersion = Version, @EngineVersion = EngineVersion
    FROM dbo.FundingPlatform_MatchingProfiles WHERE Id = @MatchingProfileId;
    SELECT @RuleSetFingerprint = RuleSetFingerprint
    FROM dbo.FundingPlatform_ifn_MatchingProfileRuleSetFingerprint(@MatchingProfileId);
    DECLARE @Runs TABLE
    (
        ProjectSequence INT NOT NULL PRIMARY KEY,
        ProjectMatchingRunId BIGINT NOT NULL,
        ProjectId BIGINT NOT NULL
    );
    SET @ProjectSequence = 1;
    WHILE @ProjectSequence <= 30
    BEGIN
        SELECT @ProjectId = ProjectId FROM @Projects WHERE SequenceNumber = @ProjectSequence;
        INSERT INTO dbo.FundingPlatform_ProjectMatchingRuns
            (OrganizationId, ProjectId, ProjectSlugSnapshot, ProjectTitleSnapshot,
             MatchingProfileId, MatchingProfileCodeSnapshot,
             MatchingProfileVersionSnapshot, EngineVersionSnapshot, RuleSetFingerprint,
             ProjectVersion, OrganizationProfileVersion, InputFingerprint,
             CandidateSetFingerprint, CatalogSnapshotAtUtc, CalculationCalendarYear,
             TotalCandidateCount, ProcessedCandidateCount, CompatibleCount,
             IncompatibleCount, InsufficientDataCount, IsTruncated, Status,
             StartedAtUtc, CompletedAtUtc, CreatedAtUtc)
        VALUES
            (@OrganizationId, @ProjectId,
             CONCAT(N'fase9b-p-', @ProjectSequence, N'-', @Suffix),
             CONCAT(N'Private fixture ', @ProjectSequence), @MatchingProfileId,
             @ProfileCode, @ProfileVersion, @EngineVersion, @RuleSetFingerprint,
             1, 1, HASHBYTES('SHA2_256', CONCAT(N'input-', @ProjectSequence, @Suffix)),
             HASHBYTES('SHA2_256', CONCAT(N'catalog-', @ProjectSequence, @Suffix)),
             @NowUtc, 2026, 10, 10, 8, 1, 1, 0, 2, @NowUtc, @NowUtc, @NowUtc);
        DECLARE @MatchingRunId BIGINT = SCOPE_IDENTITY();
        INSERT INTO @Runs VALUES (@ProjectSequence, @MatchingRunId, @ProjectId);
        DECLARE @WithinProject INT = 1;
        WHILE @WithinProject <= 10
        BEGIN
            SET @OpportunitySequence = ((@ProjectSequence - 1) * 10 + @WithinProject - 1) % 100 + 1;
            SELECT @OpportunityId = FundingOpportunityId
            FROM @Opportunities WHERE SequenceNumber = @OpportunitySequence;
            DECLARE @Classification TINYINT = CASE @WithinProject WHEN 10 THEN 1
                                                                  WHEN 9 THEN 2 ELSE 0 END;
            INSERT INTO dbo.FundingPlatform_ProjectFundingMatches
                (OrganizationId, ProjectId, FundingOpportunityId, MatchRunId,
                 MatchingProfileId, ProjectVersion, OrganizationProfileVersion,
                 FundingContentVersion, OpportunitySlug, OpportunityTitle,
                 SponsorName, DeadlinePrecision, Classification, HardGateStatus,
                 CompatibilityScore, RuleScore, EvidenceCoverage, InputFingerprint,
                 IsCurrent, CalculatedAtUtc, SupersededAtUtc)
            VALUES
                (@OrganizationId, @ProjectId, @OpportunityId, @MatchingRunId,
                 @MatchingProfileId, 1, 1, 1,
                 CONCAT(N'fase9b-o-', @OpportunitySequence, N'-', @Suffix),
                 CONCAT(N'Public fund ', @OpportunitySequence), N'Public sponsor', 0,
                 @Classification, @Classification,
                 CASE WHEN @Classification = 1 THEN NULL
                      WHEN @Classification = 2 THEN 70 ELSE 100 - @WithinProject END,
                 CASE WHEN @Classification = 2 THEN 70 ELSE 100 - @WithinProject END,
                 CASE WHEN @Classification = 2 THEN 70 ELSE 100 END,
                 HASHBYTES('SHA2_256', CONCAT(N'match-', @ProjectSequence, N'-',
                                              @WithinProject, N'-', @Suffix)),
                 1, @NowUtc, NULL);
            SET @WithinProject += 1;
        END;
        SET @ProjectSequence += 1;
    END;

    DECLARE @Corpus TABLE
    (
        Ordinal INT NOT NULL PRIMARY KEY, CasePublicId UNIQUEIDENTIFIER NOT NULL,
        Split TINYINT NOT NULL, ProjectMatchingRunId BIGINT NOT NULL,
        ProjectFundingMatchId BIGINT NOT NULL, OrganizationId BIGINT NOT NULL,
        ProjectId BIGINT NOT NULL, ProjectVersion INT NOT NULL,
        FundingOpportunityId BIGINT NOT NULL, FundingContentVersion INT NOT NULL,
        ProjectContentHash BINARY(32) NOT NULL,
        OpportunityContentHash BINARY(32) NOT NULL,
        RelevanceLabel TINYINT NOT NULL, LabelProvenanceHash BINARY(32) NOT NULL
    );
    INSERT INTO @Corpus
    SELECT (projectSequenceSource.SequenceNumber - 1) * 10 + withinProject.SequenceNumber,
           NEWID(), CASE WHEN projectSequenceSource.SequenceNumber <= 15 THEN 0 ELSE 1 END,
           runs.ProjectMatchingRunId, matches.Id, @OrganizationId,
           projects.ProjectId, 1, opportunities.FundingOpportunityId, 1,
           projects.ContentHash, opportunities.ContentHash,
           CASE withinProject.SequenceNumber WHEN 1 THEN 2 WHEN 2 THEN 1 ELSE 0 END,
           HASHBYTES('SHA2_256', CONCAT(N'label-', projectSequenceSource.SequenceNumber,
                                        N'-', withinProject.SequenceNumber, N'-', @Suffix))
    FROM (SELECT SequenceNumber FROM @Projects) AS projectSequenceSource
    CROSS JOIN (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10)) AS withinProject(SequenceNumber)
    INNER JOIN @Projects AS projects
        ON projects.SequenceNumber = projectSequenceSource.SequenceNumber
    INNER JOIN @Runs AS runs
        ON runs.ProjectSequence = projectSequenceSource.SequenceNumber
    INNER JOIN @Opportunities AS opportunities
        ON opportunities.SequenceNumber =
           ((projectSequenceSource.SequenceNumber - 1) * 10 + withinProject.SequenceNumber - 1) % 100 + 1
    INNER JOIN dbo.FundingPlatform_ProjectFundingMatches AS matches
        ON matches.MatchRunId = runs.ProjectMatchingRunId
       AND matches.FundingOpportunityId = opportunities.FundingOpportunityId;

    DECLARE @ManifestHash BINARY(32);
    SELECT @ManifestHash = CONVERT(BINARY(32), HASHBYTES
        ('SHA2_256', CONVERT(VARBINARY(MAX), manifest.ManifestText)))
    FROM
    (
        SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT
        (
            corpus.Ordinal, N':', corpus.CasePublicId, N':', corpus.Split, N':',
            corpus.ProjectMatchingRunId, N':', corpus.ProjectFundingMatchId, N':',
            corpus.OrganizationId, N':', corpus.ProjectId, N':', corpus.ProjectVersion, N':',
            corpus.FundingOpportunityId, N':', corpus.FundingContentVersion, N':',
            CONVERT(VARCHAR(64), corpus.ProjectContentHash, 2), N':',
            CONVERT(VARCHAR(64), corpus.OpportunityContentHash, 2), N':',
            corpus.RelevanceLabel, N':', CONVERT(VARCHAR(64), corpus.LabelProvenanceHash, 2)
        )), N'|') WITHIN GROUP (ORDER BY corpus.Ordinal) AS ManifestText
        FROM @Corpus AS corpus
    ) AS manifest;
    DECLARE @EvaluationSetCode NVARCHAR(50) = N'smoke-set-' + @Suffix;
    INSERT INTO dbo.FundingPlatform_SemanticEvaluationSets
        (Code, Version, ManifestHash, ProvenanceCode, SplitPolicyVersion,
         DeclaredProjectCount, DeclaredOpportunityCount, DeclaredLabelCount,
         ReviewedByUserId, ReviewedAtUtc, CreatedAtUtc)
    VALUES
        (@EvaluationSetCode, 1, @ManifestHash, N'fase9b-smoke-reviewed', N'project-holdout-v1',
         30, 100, 300, @AdminUserId, @NowUtc, @NowUtc);
    DECLARE @EvaluationSetId INT = SCOPE_IDENTITY();
    INSERT INTO dbo.FundingPlatform_SemanticEvaluationCases
        (EvaluationSetId, Ordinal, CasePublicId, Split, ProjectMatchingRunId,
         ProjectFundingMatchId, OrganizationId, ProjectId, ProjectVersion,
         FundingOpportunityId, FundingContentVersion, ProjectContentHash,
         OpportunityContentHash, RelevanceLabel, LabelProvenanceHash, CreatedAtUtc)
    SELECT @EvaluationSetId, Ordinal, CasePublicId, Split, ProjectMatchingRunId,
           ProjectFundingMatchId, OrganizationId, ProjectId, ProjectVersion,
           FundingOpportunityId, FundingContentVersion, ProjectContentHash,
           OpportunityContentHash, RelevanceLabel, LabelProvenanceHash, @NowUtc
    FROM @Corpus;
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ifn_SemanticEvaluationSetState(@EvaluationSetId)
        WHERE ActualProjectCount = 30 AND ActualOpportunityCount = 100
          AND ActualLabelCount = 300 AND CalculatedManifestHash = @ManifestHash)
        THROW 54220, N'The independent 30/100/300 corpus manifest did not round-trip.', 1;

    DECLARE @ActiveCode NVARCHAR(50) = N'smoke-active-' + @Suffix;
    DECLARE @ActiveFingerprint BINARY(32) = CONVERT(BINARY(32), HASHBYTES
    (
        'SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
        (@ActiveCode, N'|1|development-deterministic|lexical-hash-1536-v1|1536|matching|',
         N'project-semantic-v1|opportunity-semantic-v1|semantic-text-v1|1|',
         N'cosine-linear-shadow-v1|8192|8|3|0.000000|1.000000|1'))
    ));
    INSERT INTO dbo.FundingPlatform_SemanticConfigurations
        (Code, Version, ProviderCode, ModelCode, Dimensions, PurposeCode,
         ProjectTemplateVersion, OpportunityTemplateVersion, NormalizationVersion,
         DistanceMetric, CalibrationVersion, MaximumInputUtf8Bytes, MaximumBatchSize,
         MaximumAttempts, MaximumCostUsdPerEmbedding, MonthlyBudgetUsd,
         ConfigurationFingerprint, IsLocalFake, IsActive, PublishedAtUtc, CreatedAtUtc)
    VALUES
        (@ActiveCode, 1, N'development-deterministic', N'lexical-hash-1536-v1', 1536,
         N'matching', N'project-semantic-v1', N'opportunity-semantic-v1',
         N'semantic-text-v1', 1, N'cosine-linear-shadow-v1', 8192, 8, 3,
         0.000000, 1.000000, @ActiveFingerprint, 1, 1, @NowUtc, @NowUtc);
    DECLARE @ActiveConfigurationId INT = SCOPE_IDENTITY();
    DECLARE @EvaluationSetVersion NVARCHAR(64) = CONCAT(@EvaluationSetCode, N'-v1');
    DECLARE @ConfigurationVersion NVARCHAR(64) = CONCAT(@ActiveCode, N'-v1');
    DECLARE @IdempotencyKey BINARY(32) = HASHBYTES('SHA2_256', N'create-key-' + @Suffix);
    DECLARE @RequestHash BINARY(32) = HASHBYTES('SHA2_256', N'create-request-' + @Suffix);

    DECLARE @CreateOutcome TABLE (Succeeded BIT, Code NVARCHAR(50), WasReplay BIT);
    INSERT INTO @CreateOutcome
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_Create
        @AdminUserPublicId = @AdminPublicId,
        @EvaluationSetVersion = @EvaluationSetVersion,
        @SemanticConfigurationVersion = @ConfigurationVersion,
        @IdempotencyKeyHash = 0x1111111111111111111111111111111111111111111111111111111111111111,
        @RequestHash = @RequestHash, @RuntimeEnabled = 0, @NowUtc = @NowUtc;
    IF NOT EXISTS (SELECT 1 FROM @CreateOutcome
                   WHERE Succeeded = 0 AND Code = N'semantic-processing-disabled')
       OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationRuns
                  WHERE SemanticConfigurationId = @ActiveConfigurationId)
        THROW 54221, N'Runtime-disabled new evaluation was persisted or misreported.', 1;

    DECLARE @CreateRows TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), WasReplay BIT,
        SemanticEvaluationRunId BIGINT, PublicId UNIQUEIDENTIFIER, Status TINYINT,
        EvaluationSetVersion NVARCHAR(64), SemanticConfigurationVersion NVARCHAR(64),
        ProviderCode NVARCHAR(50), ModelCode NVARCHAR(128), Dimensions SMALLINT,
        PurposeCode NVARCHAR(32), NormalizationVersion NVARCHAR(50),
        ProjectCount INT, OpportunityCount INT, PairCount INT, PrimaryCohortCount INT,
        EvaluatedCount INT, LabelledCount INT, CoveragePercentage DECIMAL(5,2),
        ProviderSuccessPercentage DECIMAL(5,2), RecallAt10 DECIMAL(7,6),
        NormalizedDiscountedCumulativeGainAt10 DECIMAL(7,6),
        BaselineNormalizedDiscountedCumulativeGainAt10 DECIMAL(7,6),
        NormalizedDiscountedCumulativeGainDelta DECIMAL(8,6),
        MeanReciprocalRankAt10 DECIMAL(7,6), MeanRankDelta DECIMAL(9,4),
        TotalEstimatedCostUsd DECIMAL(19,6), LatencyP95Milliseconds INT,
        HardGatePromotionCount INT, MeetsPromotionGate BIT,
        CreatedAtUtc DATETIME2(3), StartedAtUtc DATETIME2(3),
        CompletedAtUtc DATETIME2(3), LastErrorCode NVARCHAR(50)
    );
    INSERT INTO @CreateRows
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_Create
        @AdminUserPublicId = @AdminPublicId,
        @EvaluationSetVersion = @EvaluationSetVersion,
        @SemanticConfigurationVersion = @ConfigurationVersion,
        @IdempotencyKeyHash = @IdempotencyKey, @RequestHash = @RequestHash,
        @RuntimeEnabled = 1, @NowUtc = @NowUtc;
    DECLARE @EvaluationRunPublicId UNIQUEIDENTIFIER =
        (SELECT PublicId FROM @CreateRows WHERE Succeeded = 1 AND WasReplay = 0);
    DECLARE @EvaluationRunId BIGINT =
        (SELECT SemanticEvaluationRunId FROM @CreateRows WHERE PublicId = @EvaluationRunPublicId);
    IF @EvaluationRunId IS NULL
       OR NOT EXISTS (SELECT 1 FROM @CreateRows
                      WHERE Code = N'queued' AND ProjectCount = 30
                        AND OpportunityCount = 100 AND PairCount = 300
                        AND EvaluatedCount = 0 AND LabelledCount = 0)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SemanticEvaluationRunCases
           WHERE SemanticEvaluationRunId = @EvaluationRunId) <> 300
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SemanticEmbeddingJobs
           WHERE SemanticConfigurationId = @ActiveConfigurationId AND Status = 0) <> 130
        THROW 54222, N'Corpus Create did not freeze 300 cases and 130 ID-only subject jobs.', 1;

    DELETE FROM @CreateRows;
    DECLARE @ReplayNowUtc DATETIME2(3) = DATEADD(SECOND, 1, @NowUtc);
    INSERT INTO @CreateRows
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_Create
        @AdminUserPublicId = @AdminPublicId,
        @EvaluationSetVersion = @EvaluationSetVersion,
        @SemanticConfigurationVersion = @ConfigurationVersion,
        @IdempotencyKeyHash = @IdempotencyKey, @RequestHash = @RequestHash,
        @RuntimeEnabled = 0, @NowUtc = @ReplayNowUtc;
    IF NOT EXISTS (SELECT 1 FROM @CreateRows
                   WHERE PublicId = @EvaluationRunPublicId AND WasReplay = 1
                     AND Code = N'replayed')
        THROW 54223, N'Exact Create replay did not precede the runtime kill switch.', 1;

    DECLARE @EvaluationClaims TABLE
    (
        RunPublicId UNIQUEIDENTIFIER, LeaseId UNIQUEIDENTIFIER,
        SemanticConfigurationVersion NVARCHAR(64),
        SemanticConfigurationFingerprint BINARY(32), ProviderCode NVARCHAR(50),
        ModelCode NVARCHAR(128), PurposeCode NVARCHAR(32),
        NormalizationVersion NVARCHAR(50), ProjectTemplateVersion NVARCHAR(50),
        OpportunityTemplateVersion NVARCHAR(50), CalibrationVersion NVARCHAR(50),
        DistanceMetric TINYINT, MaximumAttempts TINYINT, Dimensions SMALLINT,
        PairCount INT, AttemptCount TINYINT
    );
    DECLARE @Poll INT = 1;
    WHILE @Poll <= 4
    BEGIN
        DECLARE @PollNowUtc DATETIME2(3) = DATEADD(SECOND, @Poll, @NowUtc);
        DELETE FROM @EvaluationClaims;
        INSERT INTO @EvaluationClaims
        EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_Claim
            @WorkerInstanceId = N'smoke-eval-worker', @BatchSize = 1,
            @LeaseSeconds = 300, @NowUtc = @PollNowUtc;
        IF EXISTS (SELECT 1 FROM @EvaluationClaims)
           OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationRuns
                      WHERE Id = @EvaluationRunId AND AttemptCount <> 0)
            THROW 54224, N'Embedding readiness polling consumed an evaluation attempt.', 1;
        SET @Poll += 1;
    END;

    DECLARE @VectorJson NVARCHAR(MAX);
    ;WITH numbers AS
    (
        SELECT TOP (1536) ROW_NUMBER() OVER (ORDER BY firstObject.object_id,
                                                      secondObject.object_id) AS Number
        FROM sys.all_objects AS firstObject
        CROSS JOIN sys.all_objects AS secondObject
    )
    SELECT @VectorJson = CONCAT(N'[', STRING_AGG
        (CONVERT(NVARCHAR(MAX), CASE WHEN Number = 1 THEN N'1.0' ELSE N'0.0' END), N',')
        WITHIN GROUP (ORDER BY Number), N']')
    FROM numbers;
    DECLARE @SmokeVector VECTOR(1536) = CAST(@VectorJson AS VECTOR(1536));

    DECLARE @EmbeddingClaims TABLE
    (
        JobPublicId UNIQUEIDENTIFIER, LeaseId UNIQUEIDENTIFIER,
        BudgetReservationPublicId UNIQUEIDENTIFIER, SubjectType TINYINT,
        SubjectPublicId UNIQUEIDENTIFIER, SubjectVersion INT,
        SemanticConfigurationVersion NVARCHAR(64),
        SemanticConfigurationFingerprint BINARY(32), ProviderCode NVARCHAR(50),
        ModelCode NVARCHAR(128), Dimensions SMALLINT, PurposeCode NVARCHAR(32),
        TemplateVersion NVARCHAR(50), NormalizationVersion NVARCHAR(50),
        MaximumInputUtf8Bytes SMALLINT, MaximumBatchSize TINYINT,
        MaximumAttempts TINYINT, MaximumCostUsdPerEmbedding DECIMAL(19,6),
        InputContentHash BINARY(32), AttemptCount TINYINT
    );
    DECLARE @InputRows TABLE
    (
        JobPublicId UNIQUEIDENTIFIER, LeaseId UNIQUEIDENTIFIER, SubjectType TINYINT,
        SubjectPublicId UNIQUEIDENTIFIER, SubjectVersion INT, PurposeCode NVARCHAR(32),
        CanonicalText NVARCHAR(MAX), InputContentHash BINARY(32),
        ProviderPolicyPublicId UNIQUEIDENTIFIER, ProviderPolicyVersion NVARCHAR(64),
        ProviderPolicyFingerprint BINARY(32), ProviderCapability TINYINT,
        ProviderEndpointOrigin NVARCHAR(200), RetentionMode TINYINT,
        MaximumProviderRetentionDays SMALLINT, DataResidencyCode NVARCHAR(16),
        InputTokenCostUsdPerMillion DECIMAL(19,6),
        OutputTokenCostUsdPerMillion DECIMAL(19,6),
        ApprovedAtUtc DATETIME2(3), ExpiresAtUtc DATETIME2(3),
        ExternalProcessingAllowed BIT
    );
    DECLARE @EmbeddingCompleteRows TABLE
        (EmbeddingPublicId UNIQUEIDENTIFIER, WasReplay BIT);
    DECLARE @RenewRows TABLE (Succeeded BIT, LeaseUntilUtc DATETIME2(3));
    DECLARE @FailureRows TABLE (Succeeded BIT, Code NVARCHAR(50));
    DECLARE @WorkerNowUtc DATETIME2(3) = DATEADD(MINUTE, 1, @NowUtc);
    DECLARE @LoopGuard INT = 0, @DidUncertainFailure BIT = 0;
    DECLARE @DidReleasedFailure BIT = 0, @DidRenew BIT = 0, @DidReplay BIT = 0;
    DECLARE @UncertainReservationPublicId UNIQUEIDENTIFIER;
    DECLARE @ReleasedReservationPublicId UNIQUEIDENTIFIER;

    WHILE EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddingJobs
        WHERE SemanticConfigurationId = @ActiveConfigurationId AND Status IN (0, 3))
    BEGIN
        SET @LoopGuard += 1;
        IF @LoopGuard > 300
            THROW 54225, N'Bounded embedding lifecycle did not converge.', 1;
        DELETE FROM @EmbeddingClaims;
        INSERT INTO @EmbeddingClaims
        EXEC dbo.FundingPlatform_usp_SemanticEmbeddingJob_Claim
            @WorkerInstanceId = N'smoke-embedding-worker', @BatchSize = 1,
            @LeaseSeconds = 300, @NowUtc = @WorkerNowUtc;
        IF NOT EXISTS (SELECT 1 FROM @EmbeddingClaims)
        BEGIN
            SET @WorkerNowUtc = DATEADD(SECOND, 31, @WorkerNowUtc);
            CONTINUE;
        END;

        DECLARE @JobPublicId UNIQUEIDENTIFIER, @JobLeaseId UNIQUEIDENTIFIER;
        DECLARE @BudgetReservationPublicId UNIQUEIDENTIFIER, @ClaimSubjectType TINYINT;
        DECLARE @ClaimProvider NVARCHAR(50), @ClaimModel NVARCHAR(128);
        DECLARE @ClaimTemplate NVARCHAR(50), @ClaimInputHash BINARY(32);
        SELECT @JobPublicId = JobPublicId, @JobLeaseId = LeaseId,
               @BudgetReservationPublicId = BudgetReservationPublicId,
               @ClaimSubjectType = SubjectType, @ClaimProvider = ProviderCode,
               @ClaimModel = ModelCode, @ClaimTemplate = TemplateVersion,
               @ClaimInputHash = InputContentHash
        FROM @EmbeddingClaims;
        IF NOT EXISTS
           (SELECT 1 FROM @EmbeddingClaims
            WHERE SemanticConfigurationVersion = @ConfigurationVersion
              AND SemanticConfigurationFingerprint = @ActiveFingerprint
              AND ProviderCode COLLATE Latin1_General_100_BIN2 =
                  N'development-deterministic' COLLATE Latin1_General_100_BIN2
              AND ModelCode COLLATE Latin1_General_100_BIN2 =
                  N'lexical-hash-1536-v1' COLLATE Latin1_General_100_BIN2
              AND Dimensions = 1536 AND PurposeCode = N'matching'
              AND NormalizationVersion = N'semantic-text-v1'
              AND TemplateVersion IN (N'project-semantic-v1', N'opportunity-semantic-v1')
              AND MaximumInputUtf8Bytes = 8192 AND MaximumBatchSize = 8
              AND MaximumAttempts = 3 AND MaximumCostUsdPerEmbedding = 0)
            THROW 54226, N'Embedding lease did not materialize the exact frozen configuration.', 1;

        DELETE FROM @InputRows;
        INSERT INTO @InputRows
        EXEC dbo.FundingPlatform_usp_SemanticEmbeddingJob_GetInput
            @JobPublicId = @JobPublicId, @LeaseId = @JobLeaseId,
            @NowUtc = @WorkerNowUtc;
        IF NOT EXISTS
           (SELECT 1 FROM @InputRows
            WHERE JobPublicId = @JobPublicId AND LeaseId = @JobLeaseId
              AND InputContentHash = @ClaimInputHash
              AND dbo.FundingPlatform_fn_SemanticInputHash(CanonicalText) = InputContentHash
              AND JSON_VALUE(CanonicalText, N'$.schemaVersion') = N'semantic-input-v1'
              AND ProviderPolicyPublicId IS NULL
              AND ProviderPolicyVersion IS NULL
              AND ProviderPolicyFingerprint IS NULL
              AND ProviderCapability IS NULL
              AND ProviderEndpointOrigin IS NULL
              AND RetentionMode IS NULL
              AND MaximumProviderRetentionDays IS NULL
              AND DataResidencyCode IS NULL
              AND InputTokenCostUsdPerMillion IS NULL
              AND OutputTokenCostUsdPerMillion IS NULL
              AND ApprovedAtUtc IS NULL AND ExpiresAtUtc IS NULL
              AND ExternalProcessingAllowed IS NULL)
            THROW 54226, N'Claimed input envelope did not revalidate its exact UTF-8 hash.', 1;
        IF @ClaimSubjectType = 0 AND EXISTS
           (SELECT 1 FROM @InputRows
            WHERE JSON_VALUE(CanonicalText, N'$.title') IS NOT NULL
               OR CanonicalText LIKE N'%Private fixture%')
            THROW 54227, N'Private project title leaked into the provider envelope.', 1;

        DELETE FROM @FailureRows;
        DECLARE @FailureAtUtc DATETIME2(3) = DATEADD(MILLISECOND, 1, @WorkerNowUtc);
        IF @DidUncertainFailure = 0
        BEGIN
            SET @UncertainReservationPublicId = @BudgetReservationPublicId;
            INSERT INTO @FailureRows
            EXEC dbo.FundingPlatform_usp_SemanticEmbeddingJob_Fail
                @JobPublicId = @JobPublicId, @LeaseId = @JobLeaseId,
                @ErrorCode = N'embedding-provider-timeout', @Retryable = 1,
                @ProviderCallMayHaveBeenCharged = 1,
                @FailedAtUtc = @FailureAtUtc;
            SET @DidUncertainFailure = 1;
            SET @WorkerNowUtc = DATEADD(MILLISECOND, 2, @WorkerNowUtc);
            CONTINUE;
        END;
        IF @DidReleasedFailure = 0
        BEGIN
            SET @ReleasedReservationPublicId = @BudgetReservationPublicId;
            INSERT INTO @FailureRows
            EXEC dbo.FundingPlatform_usp_SemanticEmbeddingJob_Fail
                @JobPublicId = @JobPublicId, @LeaseId = @JobLeaseId,
                @ErrorCode = N'embedding-provider-unavailable', @Retryable = 1,
                @ProviderCallMayHaveBeenCharged = 0,
                @FailedAtUtc = @FailureAtUtc;
            SET @DidReleasedFailure = 1;
            SET @WorkerNowUtc = DATEADD(MILLISECOND, 2, @WorkerNowUtc);
            CONTINUE;
        END;

        IF @DidRenew = 0
        BEGIN
            DECLARE @RenewNowUtc DATETIME2(3) = DATEADD(SECOND, 1, @WorkerNowUtc);
            DELETE FROM @RenewRows;
            INSERT INTO @RenewRows
            EXEC dbo.FundingPlatform_usp_SemanticEmbeddingJob_RenewLease
                @JobPublicId = @JobPublicId, @LeaseId = @JobLeaseId,
                @LeaseSeconds = 300, @NowUtc = @RenewNowUtc;
            IF NOT EXISTS (SELECT 1 FROM @RenewRows WHERE Succeeded = 1)
               OR NOT EXISTS
                  (SELECT 1
                   FROM dbo.FundingPlatform_SemanticBudgetReservations AS reservations
                   INNER JOIN dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
                       ON jobs.Id = reservations.EmbeddingJobId
                   WHERE jobs.PublicId = @JobPublicId AND jobs.LeaseId = @JobLeaseId
                     AND reservations.LeaseId = @JobLeaseId AND reservations.Status = 0
                     AND reservations.ExpiresAtUtc = jobs.LeaseUntilUtc)
                THROW 54228, N'Job and reservation leases were not renewed atomically.', 1;
            SET @DidRenew = 1;
        END;

        DECLARE @ProviderRequestHash BINARY(32) =
            HASHBYTES('SHA2_256', CONVERT(NVARCHAR(36), @JobPublicId));
        DECLARE @EmbeddingCompletedAtUtc DATETIME2(3) = DATEADD(SECOND, 2, @WorkerNowUtc);
        DELETE FROM @EmbeddingCompleteRows;
        INSERT INTO @EmbeddingCompleteRows
        EXEC dbo.FundingPlatform_usp_SemanticEmbeddingJob_Complete
            @JobPublicId = @JobPublicId, @LeaseId = @JobLeaseId,
            @BudgetReservationPublicId = @BudgetReservationPublicId,
            @ProviderCode = @ClaimProvider, @ModelCode = @ClaimModel,
            @TemplateVersion = @ClaimTemplate, @Embedding = @SmokeVector,
            @InputTokens = 10, @OutputTokens = 0, @EstimatedCostUsd = 0.000000,
            @ProviderRequestIdHash = @ProviderRequestHash, @LatencyMilliseconds = 5,
            @CompletedAtUtc = @EmbeddingCompletedAtUtc;
        IF NOT EXISTS (SELECT 1 FROM @EmbeddingCompleteRows WHERE WasReplay = 0)
            THROW 54229, N'Exact embedding completion did not persist one vector.', 1;

        IF @DidReplay = 0
        BEGIN
            DELETE FROM @EmbeddingCompleteRows;
            INSERT INTO @EmbeddingCompleteRows
            EXEC dbo.FundingPlatform_usp_SemanticEmbeddingJob_Complete
                @JobPublicId = @JobPublicId, @LeaseId = @JobLeaseId,
                @BudgetReservationPublicId = @BudgetReservationPublicId,
                @ProviderCode = @ClaimProvider, @ModelCode = @ClaimModel,
                @TemplateVersion = @ClaimTemplate, @Embedding = @SmokeVector,
                @InputTokens = 10, @OutputTokens = 0, @EstimatedCostUsd = 0.000000,
                @ProviderRequestIdHash = @ProviderRequestHash, @LatencyMilliseconds = 5,
                @CompletedAtUtc = @EmbeddingCompletedAtUtc;
            IF NOT EXISTS (SELECT 1 FROM @EmbeddingCompleteRows WHERE WasReplay = 1)
                THROW 54230, N'Exact embedding completion replay was not durable.', 1;
            SET @DidReplay = 1;
        END;
        SET @WorkerNowUtc = DATEADD(MILLISECOND, 5, @WorkerNowUtc);
    END;

    IF (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SemanticEmbeddingJobs
        WHERE SemanticConfigurationId = @ActiveConfigurationId AND Status = 2) <> 130
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SemanticEmbeddings
           WHERE SemanticConfigurationId = @ActiveConfigurationId) <> 130
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SemanticBudgetReservations AS reservations
           INNER JOIN dbo.FundingPlatform_SemanticUsageLedger AS ledger
               ON ledger.BudgetReservationId = reservations.Id
           WHERE reservations.PublicId = @UncertainReservationPublicId
             AND reservations.Status = 1 AND ledger.OutcomeCode = N'charge-uncertain'
             AND ledger.IsEstimatedUncertain = 1
             AND ledger.EstimatedCostUsd = reservations.ReservedCostUsd)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SemanticBudgetReservations
           WHERE PublicId = @ReleasedReservationPublicId AND Status = 2)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SemanticUsageLedger AS ledger
           INNER JOIN dbo.FundingPlatform_SemanticBudgetReservations AS reservations
               ON reservations.Id = ledger.BudgetReservationId
           WHERE reservations.PublicId = @ReleasedReservationPublicId)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SemanticBudgetReservations
           WHERE SemanticConfigurationId = @ActiveConfigurationId) <> 132
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SemanticUsageLedger
           WHERE SemanticConfigurationId = @ActiveConfigurationId) <> 131
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SemanticEmbeddingJobs
           WHERE SemanticConfigurationId = @ActiveConfigurationId
             AND AttemptCount = 2) <> 2
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SemanticUsageLedger
           WHERE SemanticConfigurationId = @ActiveConfigurationId
             AND EstimatedCostUsd <> 0)
        THROW 54231, N'Embedding success/retry/uncertain-charge/release history drifted.', 1;

    /* A forged item cannot substitute rounded or invented semantic output. */
    DECLARE @FirstCaseOrdinal INT, @FirstMatchId BIGINT;
    DECLARE @FirstProjectEmbeddingId BIGINT, @FirstOpportunityEmbeddingId BIGINT;
    SELECT TOP (1) @FirstCaseOrdinal = cases.CaseOrdinal,
           @FirstMatchId = cases.ProjectFundingMatchId,
           @FirstProjectEmbeddingId = projectEmbeddings.Id,
           @FirstOpportunityEmbeddingId = opportunityEmbeddings.Id
    FROM dbo.FundingPlatform_SemanticEvaluationRunCases AS cases
    INNER JOIN dbo.FundingPlatform_SemanticEmbeddings AS projectEmbeddings
        ON projectEmbeddings.ContentAddress = cases.ProjectContentAddress
    INNER JOIN dbo.FundingPlatform_SemanticEmbeddings AS opportunityEmbeddings
        ON opportunityEmbeddings.ContentAddress = cases.OpportunityContentAddress
    WHERE cases.SemanticEvaluationRunId = @EvaluationRunId
      AND cases.DatasetSplit = 0
    ORDER BY cases.CaseOrdinal;
    IF @FirstCaseOrdinal IS NULL OR @FirstMatchId IS NULL
       OR @FirstProjectEmbeddingId IS NULL OR @FirstOpportunityEmbeddingId IS NULL
        THROW 54259, N'Forged-output probe could not resolve an embedded corpus case.', 1;
    DECLARE @TamperError INT = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        INSERT INTO dbo.FundingPlatform_SemanticEvaluationItems
            (SemanticEvaluationRunId, CaseOrdinal, ProjectFundingMatchId,
             ProjectEmbeddingId, OpportunityEmbeddingId, CosineDistance,
             CosineSimilarity, SemanticScore, SemanticRank, DeterministicRank,
             RelevanceLabel, DatasetSplit, IsPrimaryCohort, CreatedAtUtc)
        SELECT @EvaluationRunId, @FirstCaseOrdinal, @FirstMatchId,
               @FirstProjectEmbeddingId, @FirstOpportunityEmbeddingId,
               1.00000000, 0.00000000, 1.00, NULL, NULL,
               cases.RelevanceLabel, cases.DatasetSplit, 0, @WorkerNowUtc
        FROM dbo.FundingPlatform_SemanticEvaluationRunCases AS cases
        WHERE cases.SemanticEvaluationRunId = @EvaluationRunId
          AND cases.CaseOrdinal = @FirstCaseOrdinal;
    END TRY
    BEGIN CATCH SET @TamperError = ERROR_NUMBER(); END CATCH;
    SET XACT_ABORT ON;
    IF @TamperError = 0
        THROW 54232, N'Forged semantic distance/score output was accepted.', 1;
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationItems
               WHERE SemanticEvaluationRunId = @EvaluationRunId)
        THROW 54261, N'Rejected forged semantic output remained persisted.', 1;
    IF @TamperError <> 54103 OR XACT_STATE() <> 1
        THROW 54260, N'Forged semantic output failed outside the exact subject guard.', 1;

    DELETE FROM @EvaluationClaims;
    INSERT INTO @EvaluationClaims
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_Claim
        @WorkerInstanceId = N'smoke-eval-worker', @BatchSize = 1,
        @LeaseSeconds = 300, @NowUtc = @WorkerNowUtc;
    DECLARE @EvaluationLeaseId UNIQUEIDENTIFIER =
        (SELECT LeaseId FROM @EvaluationClaims WHERE RunPublicId = @EvaluationRunPublicId);
    IF @EvaluationLeaseId IS NULL
       OR NOT EXISTS
          (SELECT 1 FROM @EvaluationClaims
           WHERE SemanticConfigurationVersion = @ConfigurationVersion
             AND SemanticConfigurationFingerprint = @ActiveFingerprint
             AND ProviderCode = N'development-deterministic'
             AND ModelCode = N'lexical-hash-1536-v1' AND PurposeCode = N'matching'
             AND NormalizationVersion = N'semantic-text-v1'
             AND ProjectTemplateVersion = N'project-semantic-v1'
             AND OpportunityTemplateVersion = N'opportunity-semantic-v1'
             AND CalibrationVersion = N'cosine-linear-shadow-v1'
             AND DistanceMetric = 1 AND MaximumAttempts = 3
             AND Dimensions = 1536 AND PairCount = 300 AND AttemptCount = 1)
        THROW 54233, N'Ready corpus did not claim one exact shadow-evaluation lease.', 1;

    DECLARE @EvaluationRenewRows TABLE (Succeeded BIT);
    INSERT INTO @EvaluationRenewRows
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_RenewLease
        @RunPublicId = @EvaluationRunPublicId, @LeaseId = @EvaluationLeaseId,
        @LeaseSeconds = 300, @NowUtc = @WorkerNowUtc;
    IF NOT EXISTS (SELECT 1 FROM @EvaluationRenewRows WHERE Succeeded = 1)
        THROW 54234, N'Shadow-evaluation lease renewal failed.', 1;

    DECLARE @WorkRows TABLE
    (
        RunPublicId UNIQUEIDENTIFIER, LeaseId UNIQUEIDENTIFIER, PairCount INT,
        ReadyPairCount BIGINT, PendingEmbeddingJobCount BIGINT,
        PermanentFailedEmbeddingJobCount BIGINT
    );
    INSERT INTO @WorkRows
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_GetWork
        @RunPublicId = @EvaluationRunPublicId, @LeaseId = @EvaluationLeaseId,
        @NowUtc = @WorkerNowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @WorkRows
        WHERE PairCount = 300 AND ReadyPairCount = 300
          AND PendingEmbeddingJobCount = 0 AND PermanentFailedEmbeddingJobCount = 0)
        THROW 54235, N'Full-cache shadow work readiness was misreported.', 1;

    DECLARE @MatchCountBefore BIGINT =
        (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_ProjectFundingMatches
         WHERE MatchRunId IN (SELECT ProjectMatchingRunId FROM @Corpus));
    DECLARE @MatchChecksumBefore INT =
        (SELECT CHECKSUM_AGG(BINARY_CHECKSUM
            (Id, Classification, HardGateStatus, CompatibilityScore, IsCurrent))
         FROM dbo.FundingPlatform_ProjectFundingMatches
         WHERE MatchRunId IN (SELECT ProjectMatchingRunId FROM @Corpus));
    DECLARE @EvaluationCompletedAtUtc DATETIME2(3) = DATEADD(SECOND, 2, @WorkerNowUtc);
    DECLARE @EvaluationCompleteRows TABLE (Succeeded BIT, WasReplay BIT, Code NVARCHAR(50));
    INSERT INTO @EvaluationCompleteRows
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_Complete
        @RunPublicId = @EvaluationRunPublicId, @LeaseId = @EvaluationLeaseId,
        @CompletedAtUtc = @EvaluationCompletedAtUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @EvaluationCompleteRows
        WHERE Succeeded = 1 AND WasReplay = 0 AND Code = N'completed')
        THROW 54236, N'Full shadow evaluation did not complete.', 1;

    DELETE FROM @EvaluationCompleteRows;
    INSERT INTO @EvaluationCompleteRows
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_Complete
        @RunPublicId = @EvaluationRunPublicId, @LeaseId = @EvaluationLeaseId,
        @CompletedAtUtc = @EvaluationCompletedAtUtc;
    IF NOT EXISTS (SELECT 1 FROM @EvaluationCompleteRows
                   WHERE Succeeded = 1 AND WasReplay = 1 AND Code = N'completed')
        THROW 54237, N'Exact completed shadow-evaluation replay was not durable.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationRuns
        WHERE Id = @EvaluationRunId AND Status = 2 AND EvaluatedCount = 300
          AND LabelledCount = 300 AND CoveragePercentage = 100
          AND SuccessPercentage = 100 AND TotalEstimatedCostUsd = 0
          AND P95LatencyMilliseconds = 5 AND IsPromotionEligible = 0
          AND RecallAt10 = 1.000000 AND NdcgAt10 = 1.000000
          AND BaselineNdcgAt10 = 1.000000 AND NdcgDelta = 0.000000
          AND MrrAt10 = 1.000000 AND MeanRankDelta = 0.0000
          AND HardFailPromotedCount = 15)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SemanticEvaluationItems
           WHERE SemanticEvaluationRunId = @EvaluationRunId) <> 300
       OR @MatchCountBefore <>
          (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_ProjectFundingMatches
           WHERE MatchRunId IN (SELECT ProjectMatchingRunId FROM @Corpus))
       OR @MatchChecksumBefore <>
          (SELECT CHECKSUM_AGG(BINARY_CHECKSUM
              (Id, Classification, HardGateStatus, CompatibilityScore, IsCurrent))
           FROM dbo.FundingPlatform_ProjectFundingMatches
           WHERE MatchRunId IN (SELECT ProjectMatchingRunId FROM @Corpus))
        THROW 54238, N'Full metrics, fake non-promotion or immutable 9A isolation drifted.', 1;

    IF EXISTS
       (SELECT 1
        FROM dbo.FundingPlatform_SemanticEvaluationItems AS insufficientItems
        INNER JOIN dbo.FundingPlatform_ProjectFundingMatches AS insufficientMatches
            ON insufficientMatches.Id = insufficientItems.ProjectFundingMatchId
        INNER JOIN dbo.FundingPlatform_SemanticEvaluationRunCases AS insufficientCases
            ON insufficientCases.SemanticEvaluationRunId = insufficientItems.SemanticEvaluationRunId
           AND insufficientCases.CaseOrdinal = insufficientItems.CaseOrdinal
        INNER JOIN dbo.FundingPlatform_SemanticEvaluationItems AS compatibleItems
            ON compatibleItems.SemanticEvaluationRunId = insufficientItems.SemanticEvaluationRunId
        INNER JOIN dbo.FundingPlatform_ProjectFundingMatches AS compatibleMatches
            ON compatibleMatches.Id = compatibleItems.ProjectFundingMatchId
        INNER JOIN dbo.FundingPlatform_SemanticEvaluationRunCases AS compatibleCases
            ON compatibleCases.SemanticEvaluationRunId = compatibleItems.SemanticEvaluationRunId
           AND compatibleCases.CaseOrdinal = compatibleItems.CaseOrdinal
           AND compatibleCases.ProjectMatchingRunId = insufficientCases.ProjectMatchingRunId
        WHERE insufficientItems.SemanticEvaluationRunId = @EvaluationRunId
          AND insufficientMatches.Classification = 2
          AND compatibleMatches.Classification = 0
          AND insufficientItems.SemanticRank < compatibleItems.SemanticRank)
        THROW 54239, N'Insufficient-data match ranked above a compatible match.', 1;

    /* Execute every safe administrator read surface, including the empty
       not-found shape; procedures expose only summaries/aggregates. */
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_List
        @AdminUserPublicId = @AdminPublicId, @PageNumber = 1, @PageSize = 20;
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_Get
        @AdminUserPublicId = @AdminPublicId, @RunPublicId = @EvaluationRunPublicId;
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_Report
        @AdminUserPublicId = @AdminPublicId, @RunPublicId = @EvaluationRunPublicId;
    DECLARE @MissingRunPublicId UNIQUEIDENTIFIER = NEWID();
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_Get
        @AdminUserPublicId = @AdminPublicId, @RunPublicId = @MissingRunPublicId;
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_Report
        @AdminUserPublicId = @AdminPublicId, @RunPublicId = @MissingRunPublicId;

    /* Second corpus replaces one Dev project with one new exact project. The
       100 opportunities and 29 project embeddings are cache hits; its sole new
       project job is terminally failed pre-call, yielding a 290/300 report. */
    SET @ProjectSequence = 31;
    SET @ProjectPublicId = NEWID();
    SET @ProjectSnapshot =
        N'{"title":"private fixture 31","summary":"community impact 31",'
        + N'"description":"safe community program","status":2,'
        + N'"startDate":"2026-01-01","endDate":"2026-12-31",'
        + N'"budgetTotal":1000,"confirmedFunding":100,"currency":"CLP",'
        + N'"countryIds":[1,2],"regionIds":[],"categoryIds":[1,2],'
        + N'"beneficiaryTypeIds":[1],"projectTypeIds":[1]}';
    SET @ProjectHash = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @ProjectSnapshot));
    INSERT INTO dbo.FundingPlatform_Projects
        (PublicId, OrganizationId, CreatedByUserId, Slug, Title, Summary,
         Description, ProjectStatus, PublicationStatus, ProjectVersion,
         IsActive, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@ProjectPublicId, @OrganizationId, @AdminUserId,
         N'fase9b-p-31-' + @Suffix, N'Private fixture 31', N'Community impact',
         N'Safe community program', 2, 0, 1, 1, @NowUtc, @NowUtc);
    SET @ProjectId = SCOPE_IDENTITY();
    INSERT INTO dbo.FundingPlatform_ProjectVersions
        (ProjectId, ProjectVersion, SnapshotJson, ContentHash,
         CreatedByUserId, CreatedAtUtc)
    VALUES (@ProjectId, 1, @ProjectSnapshot, @ProjectHash, @AdminUserId, @NowUtc);
    INSERT INTO @Projects VALUES (31, @ProjectId, @ProjectPublicId, @ProjectHash);

    INSERT INTO dbo.FundingPlatform_ProjectMatchingRuns
        (OrganizationId, ProjectId, ProjectSlugSnapshot, ProjectTitleSnapshot,
         MatchingProfileId, MatchingProfileCodeSnapshot,
         MatchingProfileVersionSnapshot, EngineVersionSnapshot, RuleSetFingerprint,
         ProjectVersion, OrganizationProfileVersion, InputFingerprint,
         CandidateSetFingerprint, CatalogSnapshotAtUtc, CalculationCalendarYear,
         TotalCandidateCount, ProcessedCandidateCount, CompatibleCount,
         IncompatibleCount, InsufficientDataCount, IsTruncated, Status,
         StartedAtUtc, CompletedAtUtc, CreatedAtUtc)
    VALUES
        (@OrganizationId, @ProjectId, N'fase9b-p-31-' + @Suffix,
         N'Private fixture 31', @MatchingProfileId, @ProfileCode, @ProfileVersion,
         @EngineVersion, @RuleSetFingerprint, 1, 1,
         HASHBYTES('SHA2_256', N'input-31-' + @Suffix),
         HASHBYTES('SHA2_256', N'catalog-31-' + @Suffix),
         @NowUtc, 2026, 10, 10, 8, 1, 1, 0, 2, @NowUtc, @NowUtc, @NowUtc);
    SET @MatchingRunId = SCOPE_IDENTITY();
    INSERT INTO @Runs VALUES (31, @MatchingRunId, @ProjectId);
    SET @WithinProject = 1;
    WHILE @WithinProject <= 10
    BEGIN
        SET @OpportunitySequence = @WithinProject;
        SELECT @OpportunityId = FundingOpportunityId
        FROM @Opportunities WHERE SequenceNumber = @OpportunitySequence;
        SET @Classification = CASE @WithinProject WHEN 10 THEN 1 WHEN 9 THEN 2 ELSE 0 END;
        INSERT INTO dbo.FundingPlatform_ProjectFundingMatches
            (OrganizationId, ProjectId, FundingOpportunityId, MatchRunId,
             MatchingProfileId, ProjectVersion, OrganizationProfileVersion,
             FundingContentVersion, OpportunitySlug, OpportunityTitle,
             SponsorName, DeadlinePrecision, Classification, HardGateStatus,
             CompatibilityScore, RuleScore, EvidenceCoverage, InputFingerprint,
             IsCurrent, CalculatedAtUtc, SupersededAtUtc)
        VALUES
            (@OrganizationId, @ProjectId, @OpportunityId, @MatchingRunId,
             @MatchingProfileId, 1, 1, 1,
             CONCAT(N'fase9b-o-', @OpportunitySequence, N'-', @Suffix),
             CONCAT(N'Public fund ', @OpportunitySequence), N'Public sponsor', 0,
             @Classification, @Classification,
             CASE WHEN @Classification = 1 THEN NULL
                  WHEN @Classification = 2 THEN 70 ELSE 100 - @WithinProject END,
             CASE WHEN @Classification = 2 THEN 70 ELSE 100 - @WithinProject END,
             CASE WHEN @Classification = 2 THEN 70 ELSE 100 END,
             HASHBYTES('SHA2_256', CONCAT(N'match-31-', @WithinProject, N'-', @Suffix)),
             1, @NowUtc, NULL);
        SET @WithinProject += 1;
    END;

    DECLARE @Corpus2 TABLE
    (
        Ordinal INT NOT NULL PRIMARY KEY, CasePublicId UNIQUEIDENTIFIER NOT NULL,
        Split TINYINT NOT NULL, ProjectMatchingRunId BIGINT NOT NULL,
        ProjectFundingMatchId BIGINT NOT NULL, OrganizationId BIGINT NOT NULL,
        ProjectId BIGINT NOT NULL, ProjectVersion INT NOT NULL,
        FundingOpportunityId BIGINT NOT NULL, FundingContentVersion INT NOT NULL,
        ProjectContentHash BINARY(32) NOT NULL,
        OpportunityContentHash BINARY(32) NOT NULL,
        RelevanceLabel TINYINT NOT NULL, LabelProvenanceHash BINARY(32) NOT NULL
    );
    DECLARE @RemovedProjectId BIGINT =
        (SELECT ProjectId FROM @Projects WHERE SequenceNumber = 1);
    INSERT INTO @Corpus2
    SELECT CONVERT(INT, ROW_NUMBER() OVER (ORDER BY corpus.Ordinal)), NEWID(), corpus.Split,
           corpus.ProjectMatchingRunId, corpus.ProjectFundingMatchId, corpus.OrganizationId,
           corpus.ProjectId, corpus.ProjectVersion, corpus.FundingOpportunityId,
           corpus.FundingContentVersion, corpus.ProjectContentHash,
           corpus.OpportunityContentHash, corpus.RelevanceLabel,
           HASHBYTES('SHA2_256', CONCAT(N'partial-copy-', corpus.Ordinal, N'-', @Suffix))
    FROM @Corpus AS corpus
    WHERE corpus.ProjectId <> @RemovedProjectId;
    INSERT INTO @Corpus2
    SELECT 290 + withinProject.SequenceNumber, NEWID(), 0, @MatchingRunId, matches.Id,
           @OrganizationId, @ProjectId, 1, opportunities.FundingOpportunityId, 1,
           @ProjectHash, opportunities.ContentHash,
           CASE withinProject.SequenceNumber WHEN 1 THEN 2 WHEN 2 THEN 1 ELSE 0 END,
           HASHBYTES('SHA2_256', CONCAT(N'partial-new-', withinProject.SequenceNumber,
                                        N'-', @Suffix))
    FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10)) AS withinProject(SequenceNumber)
    INNER JOIN @Opportunities AS opportunities
        ON opportunities.SequenceNumber = withinProject.SequenceNumber
    INNER JOIN dbo.FundingPlatform_ProjectFundingMatches AS matches
        ON matches.MatchRunId = @MatchingRunId
       AND matches.FundingOpportunityId = opportunities.FundingOpportunityId;

    DECLARE @ManifestHash2 BINARY(32);
    SELECT @ManifestHash2 = CONVERT(BINARY(32), HASHBYTES
        ('SHA2_256', CONVERT(VARBINARY(MAX), manifest.ManifestText)))
    FROM
    (
        SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT
        (
            corpus.Ordinal, N':', corpus.CasePublicId, N':', corpus.Split, N':',
            corpus.ProjectMatchingRunId, N':', corpus.ProjectFundingMatchId, N':',
            corpus.OrganizationId, N':', corpus.ProjectId, N':', corpus.ProjectVersion, N':',
            corpus.FundingOpportunityId, N':', corpus.FundingContentVersion, N':',
            CONVERT(VARCHAR(64), corpus.ProjectContentHash, 2), N':',
            CONVERT(VARCHAR(64), corpus.OpportunityContentHash, 2), N':',
            corpus.RelevanceLabel, N':', CONVERT(VARCHAR(64), corpus.LabelProvenanceHash, 2)
        )), N'|') WITHIN GROUP (ORDER BY corpus.Ordinal) AS ManifestText
        FROM @Corpus2 AS corpus
    ) AS manifest;
    DECLARE @EvaluationSetCode2 NVARCHAR(50) = N'smoke-partial-' + @Suffix;
    INSERT INTO dbo.FundingPlatform_SemanticEvaluationSets
        (Code, Version, ManifestHash, ProvenanceCode, SplitPolicyVersion,
         DeclaredProjectCount, DeclaredOpportunityCount, DeclaredLabelCount,
         ReviewedByUserId, ReviewedAtUtc, CreatedAtUtc)
    VALUES
        (@EvaluationSetCode2, 1, @ManifestHash2, N'fase9b-smoke-partial',
         N'project-holdout-v1', 30, 100, 300, @AdminUserId, @NowUtc, @NowUtc);
    DECLARE @EvaluationSetId2 INT = SCOPE_IDENTITY();
    INSERT INTO dbo.FundingPlatform_SemanticEvaluationCases
        (EvaluationSetId, Ordinal, CasePublicId, Split, ProjectMatchingRunId,
         ProjectFundingMatchId, OrganizationId, ProjectId, ProjectVersion,
         FundingOpportunityId, FundingContentVersion, ProjectContentHash,
         OpportunityContentHash, RelevanceLabel, LabelProvenanceHash, CreatedAtUtc)
    SELECT @EvaluationSetId2, Ordinal, CasePublicId, Split, ProjectMatchingRunId,
           ProjectFundingMatchId, OrganizationId, ProjectId, ProjectVersion,
           FundingOpportunityId, FundingContentVersion, ProjectContentHash,
           OpportunityContentHash, RelevanceLabel, LabelProvenanceHash, @NowUtc
    FROM @Corpus2;

    /* The first run records usage at its completion clock. Keep the synthetic
       worker clock monotonic so cached usage cannot be attributed to run two. */
    DECLARE @LatestPriorUsageAtUtc DATETIME2(3) =
       (SELECT MAX(RecordedAtUtc)
        FROM dbo.FundingPlatform_SemanticUsageLedger
        WHERE SemanticConfigurationId = @ActiveConfigurationId);
    IF @LatestPriorUsageAtUtc IS NOT NULL
       AND @WorkerNowUtc <= @LatestPriorUsageAtUtc
        SET @WorkerNowUtc = DATEADD(MILLISECOND, 1, @LatestPriorUsageAtUtc);

    DELETE FROM @CreateRows;
    DECLARE @PartialSetVersion NVARCHAR(64) = CONCAT(@EvaluationSetCode2, N'-v1');
    DECLARE @PartialKey BINARY(32) = HASHBYTES('SHA2_256', N'partial-key-' + @Suffix);
    DECLARE @PartialRequestHash BINARY(32) =
        HASHBYTES('SHA2_256', N'partial-request-' + @Suffix);
    INSERT INTO @CreateRows
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_Create
        @AdminUserPublicId = @AdminPublicId,
        @EvaluationSetVersion = @PartialSetVersion,
        @SemanticConfigurationVersion = @ConfigurationVersion,
        @IdempotencyKeyHash = @PartialKey, @RequestHash = @PartialRequestHash,
        @RuntimeEnabled = 1, @NowUtc = @WorkerNowUtc;
    DECLARE @PartialRunPublicId UNIQUEIDENTIFIER =
        (SELECT PublicId FROM @CreateRows WHERE Succeeded = 1 AND WasReplay = 0);
    DECLARE @PartialRunId BIGINT =
        (SELECT SemanticEvaluationRunId FROM @CreateRows WHERE PublicId = @PartialRunPublicId);
    IF @PartialRunId IS NULL
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SemanticEmbeddingJobs
           WHERE SemanticConfigurationId = @ActiveConfigurationId AND Status = 0) <> 1
        THROW 54240, N'Partial corpus did not reuse 129 cached subjects and queue one new project.', 1;

    DELETE FROM @EmbeddingClaims;
    INSERT INTO @EmbeddingClaims
    EXEC dbo.FundingPlatform_usp_SemanticEmbeddingJob_Claim
        @WorkerInstanceId = N'smoke-embedding-worker', @BatchSize = 1,
        @LeaseSeconds = 300, @NowUtc = @WorkerNowUtc;
    SELECT @JobPublicId = JobPublicId, @JobLeaseId = LeaseId
    FROM @EmbeddingClaims;
    DELETE FROM @FailureRows;
    INSERT INTO @FailureRows
    EXEC dbo.FundingPlatform_usp_SemanticEmbeddingJob_Fail
        @JobPublicId = @JobPublicId, @LeaseId = @JobLeaseId,
        @ErrorCode = N'embedding-provider-unavailable', @Retryable = 0,
        @ProviderCallMayHaveBeenCharged = 0, @FailedAtUtc = @WorkerNowUtc;
    IF NOT EXISTS (SELECT 1 FROM @FailureRows WHERE Code = N'permanent-failed')
        THROW 54241, N'Pre-call terminal input/provider failure did not close its project job.', 1;

    DELETE FROM @EvaluationClaims;
    INSERT INTO @EvaluationClaims
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_Claim
        @WorkerInstanceId = N'smoke-eval-worker', @BatchSize = 1,
        @LeaseSeconds = 300, @NowUtc = @WorkerNowUtc;
    DECLARE @PartialLeaseId UNIQUEIDENTIFIER =
        (SELECT LeaseId FROM @EvaluationClaims WHERE RunPublicId = @PartialRunPublicId);
    DELETE FROM @WorkRows;
    INSERT INTO @WorkRows
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_GetWork
        @RunPublicId = @PartialRunPublicId, @LeaseId = @PartialLeaseId,
        @NowUtc = @WorkerNowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @WorkRows
        WHERE PairCount = 300 AND ReadyPairCount = 290
          AND PendingEmbeddingJobCount = 0 AND PermanentFailedEmbeddingJobCount = 1)
        THROW 54242, N'Terminally missing embedding did not become partial-report readiness.', 1;
    DECLARE @PartialMatchCountBefore BIGINT =
        (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_ProjectFundingMatches
         WHERE MatchRunId IN (SELECT ProjectMatchingRunId FROM @Corpus2));
    DECLARE @PartialMatchChecksumBefore INT =
        (SELECT CHECKSUM_AGG(BINARY_CHECKSUM
            (Id, Classification, HardGateStatus, CompatibilityScore, IsCurrent))
         FROM dbo.FundingPlatform_ProjectFundingMatches
         WHERE MatchRunId IN (SELECT ProjectMatchingRunId FROM @Corpus2));
    DELETE FROM @EvaluationCompleteRows;
    SET @EvaluationCompletedAtUtc = DATEADD(SECOND, 2, @WorkerNowUtc);
    INSERT INTO @EvaluationCompleteRows
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_Complete
        @RunPublicId = @PartialRunPublicId, @LeaseId = @PartialLeaseId,
        @CompletedAtUtc = @EvaluationCompletedAtUtc;
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationRuns
        WHERE Id = @PartialRunId AND Status = 2 AND EvaluatedCount = 290
          AND LabelledCount = 290)
        THROW 54263, N'Partial report completion counts drifted.', 1;
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationRuns
        WHERE Id = @PartialRunId AND CoveragePercentage = 96.67)
        THROW 54264, N'Partial report coverage drifted.', 1;
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationRuns
        WHERE Id = @PartialRunId AND SuccessPercentage = 99.23)
        THROW 54265, N'Partial report provider-success metric drifted.', 1;
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationRuns
        WHERE Id = @PartialRunId AND TotalEstimatedCostUsd = 0)
        THROW 54266, N'Partial report estimated cost included unrelated work.', 1;
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationRuns
        WHERE Id = @PartialRunId AND P95LatencyMilliseconds = 0)
        THROW 54267, N'Partial report latency included unrelated work.', 1;
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationRuns
        WHERE Id = @PartialRunId AND IsPromotionEligible = 0)
        THROW 54268, N'Partial report became promotion eligible.', 1;
    IF (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SemanticEvaluationItems
        WHERE SemanticEvaluationRunId = @PartialRunId AND DatasetSplit = 0) <> 140
        THROW 54269, N'Partial report development-split item count drifted.', 1;
    IF (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SemanticEvaluationItems
        WHERE SemanticEvaluationRunId = @PartialRunId AND DatasetSplit = 1) <> 150
        THROW 54270, N'Partial report holdout-split item count drifted.', 1;
    IF @PartialMatchCountBefore <>
       (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_ProjectFundingMatches
        WHERE MatchRunId IN (SELECT ProjectMatchingRunId FROM @Corpus2))
        THROW 54271, N'Partial evaluation mutated deterministic match rows.', 1;
    IF @PartialMatchChecksumBefore <>
       (SELECT CHECKSUM_AGG(BINARY_CHECKSUM
           (Id, Classification, HardGateStatus, CompatibilityScore, IsCurrent))
        FROM dbo.FundingPlatform_ProjectFundingMatches
        WHERE MatchRunId IN (SELECT ProjectMatchingRunId FROM @Corpus2))
        THROW 54272, N'Partial evaluation mutated deterministic match content.', 1;
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_Report
        @AdminUserPublicId = @AdminPublicId, @RunPublicId = @PartialRunPublicId;

    /* Prove DENY + ownership chaining with users that have only one semantic
       database role. No login/user membership survives the transaction. */
    DECLARE @WorkerDatabaseUser SYSNAME = N'fp_sem_worker_' + @Suffix;
    DECLARE @AdminDatabaseUser SYSNAME = N'fp_sem_admin_' + @Suffix;
    DECLARE @PermissionSql NVARCHAR(MAX) =
        N'CREATE USER ' + QUOTENAME(@WorkerDatabaseUser) + N' WITHOUT LOGIN;'
        + N'ALTER ROLE FundingPlatform_SemanticWorkerRole ADD MEMBER '
        + QUOTENAME(@WorkerDatabaseUser) + N';'
        + N'CREATE USER ' + QUOTENAME(@AdminDatabaseUser) + N' WITHOUT LOGIN;'
        + N'ALTER ROLE FundingPlatform_SemanticAdminRole ADD MEMBER '
        + QUOTENAME(@AdminDatabaseUser) + N';';
    EXEC sys.sp_executesql @PermissionSql;

    SET @PermissionSql = N'
EXECUTE AS USER = N''' + REPLACE(@WorkerDatabaseUser, N'''', N'''''') + N''';
BEGIN TRY
    IF HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_usp_SemanticEmbeddingJob_Claim'',
                         N''OBJECT'', N''EXECUTE'') <> 1
       OR COALESCE(HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_usp_SemanticEvaluationRun_Create'',
                                     N''OBJECT'', N''EXECUTE''), 0) <> 0
       OR COALESCE(HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_usp_SemanticEvaluationRun_List'',
                                     N''OBJECT'', N''EXECUTE''), 0) <> 0
       OR COALESCE(HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_SemanticEmbeddings'',
                                     N''OBJECT'', N''SELECT''), 0) <> 0
       OR COALESCE(HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_SemanticEmbeddingJobs'',
                                     N''OBJECT'', N''UPDATE''), 0) <> 0
        THROW 54244, N''Worker role direct-data boundary failed.'', 1;
    EXEC dbo.FundingPlatform_usp_SemanticEmbeddingJob_Claim
        @WorkerInstanceId = N''permission-smoke-worker'', @BatchSize = 1,
        @LeaseSeconds = 300, @NowUtc = @PermissionNowUtc;
    REVERT;
END TRY
BEGIN CATCH
    REVERT;
    THROW;
END CATCH;';
    EXEC sys.sp_executesql @PermissionSql,
        N'@PermissionNowUtc DATETIME2(3)', @PermissionNowUtc = @WorkerNowUtc;

    SET @PermissionSql = N'
EXECUTE AS USER = N''' + REPLACE(@AdminDatabaseUser, N'''', N'''''') + N''';
BEGIN TRY
    IF HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_usp_SemanticEvaluationRun_List'',
                         N''OBJECT'', N''EXECUTE'') <> 1
       OR COALESCE(HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_usp_SemanticEmbeddingJob_Claim'',
                                     N''OBJECT'', N''EXECUTE''), 0) <> 0
       OR COALESCE(HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_usp_SemanticEmbeddingJob_Complete'',
                                     N''OBJECT'', N''EXECUTE''), 0) <> 0
       OR COALESCE(HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_SemanticEvaluationItems'',
                                     N''OBJECT'', N''SELECT''), 0) <> 0
       OR COALESCE(HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_SemanticEvaluationRuns'',
                                     N''OBJECT'', N''UPDATE''), 0) <> 0
        THROW 54245, N''Admin semantic role direct-data boundary failed.'', 1;
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_List
        @AdminUserPublicId = @PermissionAdminId, @PageNumber = 1, @PageSize = 2;
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_Get
        @AdminUserPublicId = @PermissionAdminId, @RunPublicId = @PermissionRunId;
    REVERT;
END TRY
BEGIN CATCH
    REVERT;
    THROW;
END CATCH;';
    EXEC sys.sp_executesql @PermissionSql,
        N'@PermissionAdminId UNIQUEIDENTIFIER, @PermissionRunId UNIQUEIDENTIFIER',
        @PermissionAdminId = @AdminPublicId, @PermissionRunId = @EvaluationRunPublicId;

    /* Terminal history and derived outputs remain immutable even for dbo; the
       application roles above cannot reach the tables at all. */
    SET @TamperError = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        UPDATE dbo.FundingPlatform_SemanticEvaluationItems
        SET SemanticScore = CASE WHEN SemanticScore = 100 THEN 99 ELSE 100 END
        WHERE SemanticEvaluationRunId = @EvaluationRunId AND CaseOrdinal = 1;
    END TRY
    BEGIN CATCH SET @TamperError = ERROR_NUMBER(); END CATCH;
    SET XACT_ABORT ON;
    IF @TamperError <> 54102 OR XACT_STATE() <> 1
        THROW 54246, N'Completed semantic item history was mutable.', 1;

    SET @TamperError = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        UPDATE dbo.FundingPlatform_SemanticEmbeddings
        SET EmbeddingHash = 0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
        WHERE Id = @FirstProjectEmbeddingId;
    END TRY
    BEGIN CATCH SET @TamperError = ERROR_NUMBER(); END CATCH;
    SET XACT_ABORT ON;
    IF @TamperError <> 54102 OR XACT_STATE() <> 1
        THROW 54247, N'Completed embedding/vector history was mutable.', 1;

    DECLARE @NoMfaPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @NoMfaEmail NVARCHAR(320) = N'fase9b-no-mfa-' + @Suffix + N'@example.invalid';
    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@NoMfaPublicId, @NoMfaEmail, UPPER(@NoMfaEmail), N'FASE 9B no MFA',
         N'not-a-credential', N'fase9b-no-mfa', 1, 0, 2, N'es-CL');
    DECLARE @NoMfaUserId BIGINT = SCOPE_IDENTITY();
    INSERT INTO dbo.FundingPlatform_UserRoles (UserId, RoleId, GrantedByUserId, CreatedAtUtc)
    VALUES (@NoMfaUserId, @AdminRoleId, @AdminUserId, @NowUtc);
    DECLARE @LockedActorId BIGINT, @MfaError INT = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId = @NoMfaPublicId, @ActorUserId = @LockedActorId OUTPUT;
    END TRY
    BEGIN CATCH SET @MfaError = ERROR_NUMBER(); END CATCH;
    SET XACT_ABORT ON;
    IF @MfaError <> 51602 OR XACT_STATE() <> 1
        THROW 54248, N'Admin-without-MFA defense in depth failed.', 1;

    /* Exact-key replay remains available after durable configuration shutdown. */
    UPDATE dbo.FundingPlatform_SemanticConfigurations
    SET IsActive = 0 WHERE Id = @ActiveConfigurationId;
    DELETE FROM @CreateRows;
    INSERT INTO @CreateRows
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_Create
        @AdminUserPublicId = @AdminPublicId,
        @EvaluationSetVersion = @EvaluationSetVersion,
        @SemanticConfigurationVersion = @ConfigurationVersion,
        @IdempotencyKeyHash = @IdempotencyKey, @RequestHash = @RequestHash,
        @RuntimeEnabled = 0, @NowUtc = @WorkerNowUtc;
    IF NOT EXISTS (SELECT 1 FROM @CreateRows
                   WHERE PublicId = @EvaluationRunPublicId AND WasReplay = 1)
        THROW 54249, N'Historical replay was blocked after configuration shutdown.', 1;

    /* A low real-provider cap must fail before creating any run or jobs. */
    DECLARE @LowBudgetCode NVARCHAR(50) = N'smoke-low-budget-' + @Suffix;
    DECLARE @LowBudgetPolicyCode NVARCHAR(50) = N'smoke-low-policy-' + @Suffix;
    DECLARE @LowBudgetPolicyExpiresAtUtc DATETIME2(3) = DATEADD(DAY, 90, @NowUtc);
    EXEC dbo.FundingPlatform_usp_AiEmbeddingProviderPolicy_AdminRegister
        @SuperAdminUserPublicId = @AdminPublicId,
        @Code = @LowBudgetPolicyCode,
        @Version = 1,
        @ModelCode = N'text-embedding-3-small',
        @EndpointOrigin = N'https://api.openai.com',
        @DataResidencyCode = N'global',
        @DpaReferenceHash =
            0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA,
        @TermsSnapshotHash =
            0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB,
        @InputTokenCostUsdPerMillion = 0.000000,
        @ApprovedAtUtc = @NowUtc,
        @ExpiresAtUtc = @LowBudgetPolicyExpiresAtUtc,
        @IdempotencyKeyHash =
            0xCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC,
        @RequestHash =
            0xDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD,
        @NowUtc = @NowUtc;
    DECLARE @LowBudgetPolicyPublicId UNIQUEIDENTIFIER =
       (SELECT PublicId
        FROM dbo.FundingPlatform_AiProviderGovernancePolicies
        WHERE Code = @LowBudgetPolicyCode AND Version = 1);

    EXEC dbo.FundingPlatform_usp_SemanticConfiguration_AdminPublishOpenAi
        @SuperAdminUserPublicId = @AdminPublicId,
        @ProviderPolicyPublicId = @LowBudgetPolicyPublicId,
        @Code = @LowBudgetCode,
        @Version = 1,
        @MaximumBatchSize = 8,
        @MaximumCostUsdPerEmbedding = 0.001000,
        @MonthlyBudgetUsd = 0.010000,
        @IdempotencyKeyHash =
            0xEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE,
        @RequestHash =
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
        @NowUtc = @NowUtc;
    DECLARE @LowBudgetConfigurationId INT =
       (SELECT Id FROM dbo.FundingPlatform_SemanticConfigurations
        WHERE Code = @LowBudgetCode AND Version = 1);
    DECLARE @LowBudgetVersion NVARCHAR(64) = CONCAT(@LowBudgetCode, N'-v1');
    IF @LowBudgetPolicyPublicId IS NULL OR @LowBudgetConfigurationId IS NULL
       OR @LowBudgetVersion IS NULL
        THROW 54273, N'Governed low-budget configuration fixture was not published.', 1;

    DECLARE @BackfillRows TABLE
        (ScannedCount BIGINT, QueuedCount BIGINT, RejectedCount BIGINT,
         ExistingCount BIGINT, NextAfterId BIGINT);
    DECLARE @AfterAllProjects BIGINT =
        (SELECT COALESCE(MAX(Id), 0) FROM dbo.FundingPlatform_Projects);
    INSERT INTO @BackfillRows
    EXEC dbo.FundingPlatform_usp_SemanticEmbeddingJob_BackfillEnqueue
        @UserPublicId = @AdminPublicId,
        @SemanticConfigurationVersion = @LowBudgetVersion,
        @SubjectType = 0, @AfterId = @AfterAllProjects, @BatchSize = 1,
        @AllowLocalFake = 0, @NowUtc = @WorkerNowUtc;
    IF NOT EXISTS (SELECT 1 FROM @BackfillRows
                   WHERE ScannedCount = 0 AND QueuedCount = 0 AND RejectedCount = 0)
        THROW 54250, N'Bounded polling-only backfill no-op contract drifted.', 1;

    DECLARE @BudgetKey BINARY(32) = HASHBYTES('SHA2_256', N'budget-key-' + @Suffix);
    DECLARE @BudgetRequestHash BINARY(32) =
        HASHBYTES('SHA2_256', N'budget-request-' + @Suffix);
    IF NOT EXISTS
       (SELECT 1
        FROM dbo.FundingPlatform_SemanticConfigurations AS configurations
        CROSS APPLY dbo.FundingPlatform_ifn_SemanticConfigurationState(configurations.Id)
            AS state
        WHERE configurations.Id = @LowBudgetConfigurationId
          AND configurations.IsActive = 1
          AND configurations.MaximumCostUsdPerEmbedding = 0.001000
          AND configurations.MonthlyBudgetUsd = 0.010000
          AND configurations.ConfigurationFingerprint = state.CalculatedFingerprint)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationRuns WHERE ActiveSlot = 1)
        THROW 54274, N'Governed low-budget preconditions drifted.', 1;

    /* The procedure rolls back its savepoint before returning this expected
       outcome. Execute directly because SQL Server forbids ROLLBACK inside
       INSERT...EXEC; the result row remains visible to the smoke caller. */
    EXEC dbo.FundingPlatform_usp_SemanticEvaluationRun_Create
        @AdminUserPublicId = @AdminPublicId,
        @EvaluationSetVersion = @EvaluationSetVersion,
        @SemanticConfigurationVersion = @LowBudgetVersion,
        @IdempotencyKeyHash = @BudgetKey,
        @RequestHash = @BudgetRequestHash,
        @RuntimeEnabled = 1, @NowUtc = @WorkerNowUtc;
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationRuns
                  WHERE SemanticConfigurationId = @LowBudgetConfigurationId)
       OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddingJobs
                  WHERE SemanticConfigurationId = @LowBudgetConfigurationId)
        THROW 54251, N'Insufficient monthly budget persisted work or blocked without an outcome.', 1;

    UPDATE dbo.FundingPlatform_SemanticConfigurations
    SET IsActive = 0
    WHERE Id = @LowBudgetConfigurationId;

    /* The minimum real-provider cost exercises the overflow-safe Claim path:
       its nominal monthly capacity is 10,000,000,000, larger than INT. */
    DECLARE @MinimumCostCode NVARCHAR(50) = N'smoke-min-cost-' + @Suffix;
    EXEC dbo.FundingPlatform_usp_SemanticConfiguration_AdminPublishOpenAi
        @SuperAdminUserPublicId = @AdminPublicId,
        @ProviderPolicyPublicId = @LowBudgetPolicyPublicId,
        @Code = @MinimumCostCode,
        @Version = 1,
        @MaximumBatchSize = 64,
        @MaximumCostUsdPerEmbedding = 0.000001,
        @MonthlyBudgetUsd = 10000.000000,
        @IdempotencyKeyHash =
            0x1212121212121212121212121212121212121212121212121212121212121212,
        @RequestHash =
            0x3434343434343434343434343434343434343434343434343434343434343434,
        @NowUtc = @NowUtc;
    DECLARE @MinimumCostConfigurationId INT =
       (SELECT Id FROM dbo.FundingPlatform_SemanticConfigurations
        WHERE Code = @MinimumCostCode AND Version = 1);
    DECLARE @MinimumCostFingerprint BINARY(32) =
       (SELECT ConfigurationFingerprint
        FROM dbo.FundingPlatform_SemanticConfigurations
        WHERE Id = @MinimumCostConfigurationId);
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ifn_SemanticConfigurationState(@MinimumCostConfigurationId)
        WHERE CalculatedFingerprint = @MinimumCostFingerprint)
        THROW 54252, N'Minimum-cost overflow boundary configuration did not round-trip.', 1;

    DECLARE @FirstFixtureProjectId BIGINT =
        (SELECT MIN(ProjectId) FROM @Projects WHERE SequenceNumber <= 30);
    DECLARE @MinimumCostVersion NVARCHAR(64) = CONCAT(@MinimumCostCode, N'-v1');
    DECLARE @MinimumCostAfterId BIGINT = @FirstFixtureProjectId - 1;
    DELETE FROM @BackfillRows;
    INSERT INTO @BackfillRows
    EXEC dbo.FundingPlatform_usp_SemanticEmbeddingJob_BackfillEnqueue
        @UserPublicId = @AdminPublicId,
        @SemanticConfigurationVersion = @MinimumCostVersion,
        @SubjectType = 0, @AfterId = @MinimumCostAfterId, @BatchSize = 1,
        @AllowLocalFake = 0, @NowUtc = @WorkerNowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @BackfillRows
        WHERE ScannedCount = 1 AND QueuedCount = 1 AND RejectedCount = 0
          AND ExistingCount = 0 AND NextAfterId = @FirstFixtureProjectId)
        THROW 54256, N'Minimum-cost boundary did not enqueue one exact project job.', 1;

    DELETE FROM @EmbeddingClaims;
    INSERT INTO @EmbeddingClaims
    EXEC dbo.FundingPlatform_usp_SemanticEmbeddingJob_Claim
        @WorkerInstanceId = N'smoke-overflow-worker', @BatchSize = 64,
        @LeaseSeconds = 300, @NowUtc = @WorkerNowUtc;
    IF (SELECT COUNT_BIG(1) FROM @EmbeddingClaims) <> 1
       OR NOT EXISTS
          (SELECT 1 FROM @EmbeddingClaims
           WHERE SemanticConfigurationVersion = @MinimumCostVersion
             AND MaximumBatchSize = 64 AND MaximumCostUsdPerEmbedding = 0.000001
             AND BudgetReservationPublicId IS NOT NULL)
        THROW 54257, N'Minimum-cost Claim overflowed or returned a drifted reservation.', 1;

    SELECT @JobPublicId = JobPublicId, @JobLeaseId = LeaseId
    FROM @EmbeddingClaims;
    DELETE FROM @FailureRows;
    INSERT INTO @FailureRows
    EXEC dbo.FundingPlatform_usp_SemanticEmbeddingJob_Fail
        @JobPublicId = @JobPublicId, @LeaseId = @JobLeaseId,
        @ErrorCode = N'semantic-job-invalid', @Retryable = 0,
        @ProviderCallMayHaveBeenCharged = 0, @FailedAtUtc = @WorkerNowUtc;
    IF NOT EXISTS (SELECT 1 FROM @FailureRows WHERE Code = N'permanent-failed')
       OR EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_SemanticBudgetReservations AS reservations
           WHERE reservations.SemanticConfigurationId = @MinimumCostConfigurationId
             AND reservations.Status <> 2)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SemanticUsageLedger
           WHERE SemanticConfigurationId = @MinimumCostConfigurationId)
        THROW 54258, N'Minimum-cost pre-call failure did not release budget without usage.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke021;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
    BEGIN
        IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
        ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke021;
    END;
    THROW;
END CATCH;

PRINT N'FASE 9B-A shadow semantic evaluation smoke passed.';
