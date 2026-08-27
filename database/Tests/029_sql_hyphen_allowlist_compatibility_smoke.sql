/* Transactional smoke for the forward-only SQL hyphen allowlist hotfix. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @SemanticConfigurationConstraint NVARCHAR(MAX) =
    (SELECT definition FROM sys.check_constraints
     WHERE name = N'FundingPlatform_CK_SemanticConfigurations_Text'
       AND parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_SemanticConfigurations'));
DECLARE @EvaluationSetConstraint NVARCHAR(MAX) =
    (SELECT definition FROM sys.check_constraints
     WHERE name = N'FundingPlatform_CK_SemanticEvaluationSets_Text'
       AND parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_SemanticEvaluationSets'));
DECLARE @ProviderPolicyConstraint NVARCHAR(MAX) =
    (SELECT definition FROM sys.check_constraints
     WHERE name = N'FundingPlatform_CK_AiProviderGovernancePolicies_Text'
       AND parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_AiProviderGovernancePolicies'));
DECLARE @ExplanationConstraint NVARCHAR(MAX) =
    (SELECT definition FROM sys.check_constraints
     WHERE name = N'FundingPlatform_CK_AiExplanationConfigurations_Text'
       AND parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_AiExplanationConfigurations'));

IF @SemanticConfigurationConstraint IS NULL
   OR CHARINDEX(N'%[^-a-z0-9._]%', @SemanticConfigurationConstraint) = 0
   OR CHARINDEX(N'%[^-A-Za-z0-9._]%', @SemanticConfigurationConstraint) = 0
   OR CHARINDEX(N'%[^a-z0-9._-]%', @SemanticConfigurationConstraint) > 0
   OR CHARINDEX(N'%[^A-Za-z0-9._-]%', @SemanticConfigurationConstraint) > 0
   OR @EvaluationSetConstraint IS NULL
   OR CHARINDEX(N'%[^-a-z0-9._]%', @EvaluationSetConstraint) = 0
   OR CHARINDEX(N'%[^a-z0-9._-]%', @EvaluationSetConstraint) > 0
   OR @ProviderPolicyConstraint IS NULL
   OR CHARINDEX(N'%[^-a-z0-9._]%', @ProviderPolicyConstraint) = 0
   OR CHARINDEX(N'%[^-A-Za-z0-9._]%', @ProviderPolicyConstraint) = 0
   OR CHARINDEX(N'%[^a-z0-9._-]%', @ProviderPolicyConstraint) > 0
   OR CHARINDEX(N'%[^A-Za-z0-9._-]%', @ProviderPolicyConstraint) > 0
   OR @ExplanationConstraint IS NULL
   OR CHARINDEX(N'%[^-a-z0-9._]%', @ExplanationConstraint) = 0
   OR CHARINDEX(N'%[^a-z0-9._-]%', @ExplanationConstraint) > 0
    THROW 55020, N'One or more persisted hyphen allowlists remain ambiguous.', 1;

IF EXISTS
   (SELECT 1
    FROM (VALUES
        (N'FundingPlatform_CK_SemanticConfigurations_Text',
         OBJECT_ID(N'dbo.FundingPlatform_SemanticConfigurations')),
        (N'FundingPlatform_CK_SemanticEvaluationSets_Text',
         OBJECT_ID(N'dbo.FundingPlatform_SemanticEvaluationSets')),
        (N'FundingPlatform_CK_AiProviderGovernancePolicies_Text',
         OBJECT_ID(N'dbo.FundingPlatform_AiProviderGovernancePolicies')),
        (N'FundingPlatform_CK_AiExplanationConfigurations_Text',
         OBJECT_ID(N'dbo.FundingPlatform_AiExplanationConfigurations'))
    ) AS expected(ConstraintName, ParentObjectId)
    LEFT JOIN sys.check_constraints AS constraints
      ON constraints.name = expected.ConstraintName
     AND constraints.parent_object_id = expected.ParentObjectId
    WHERE constraints.object_id IS NULL
       OR constraints.is_disabled <> 0
       OR constraints.is_not_trusted <> 0)
    THROW 55024, N'One or more corrected allowlist constraints are not trusted.', 1;

DECLARE @SemanticCreateDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_SemanticEvaluationRun_Create'));
DECLARE @EmbeddingClaimDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_SemanticEmbeddingJob_Claim'));
DECLARE @EvaluationClaimDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_SemanticEvaluationRun_Claim'));
DECLARE @AlertFailDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_AlertDelivery_Fail'));
DECLARE @OrganizationCreateDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_OrganizationConnection_Create'));
DECLARE @OrganizationActionDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_OrganizationConnection_Action'));
DECLARE @LegacyPreWriteRollbackToken NVARCHAR(50) = N'BEGIN ROLLBACK; SELECT';
DECLARE @SafePreWriteCommitToken NVARCHAR(50) = N'BEGIN COMMIT; SELECT';
DECLARE @OrganizationCreateCommitCount INT = CASE
    WHEN @OrganizationCreateDefinition IS NULL THEN -1
    ELSE (DATALENGTH(@OrganizationCreateDefinition) -
          DATALENGTH(REPLACE(@OrganizationCreateDefinition,
                             @SafePreWriteCommitToken, N''))) /
         DATALENGTH(@SafePreWriteCommitToken)
END;
DECLARE @OrganizationActionCommitCount INT = CASE
    WHEN @OrganizationActionDefinition IS NULL THEN -1
    ELSE (DATALENGTH(@OrganizationActionDefinition) -
          DATALENGTH(REPLACE(@OrganizationActionDefinition,
                             @SafePreWriteCommitToken, N''))) /
         DATALENGTH(@SafePreWriteCommitToken)
END;

IF @SemanticCreateDefinition IS NULL
   OR CHARINDEX(N'%[^-A-Za-z0-9._]%', @SemanticCreateDefinition) = 0
   OR CHARINDEX(N'%[^A-Za-z0-9._-]%', @SemanticCreateDefinition) > 0
   OR @EmbeddingClaimDefinition IS NULL
   OR CHARINDEX(N'%[^-A-Za-z0-9._]%', @EmbeddingClaimDefinition) = 0
   OR CHARINDEX(N'%[^A-Za-z0-9._-]%', @EmbeddingClaimDefinition) > 0
   OR @EvaluationClaimDefinition IS NULL
   OR CHARINDEX(N'%[^-A-Za-z0-9._]%', @EvaluationClaimDefinition) = 0
   OR CHARINDEX(N'%[^A-Za-z0-9._-]%', @EvaluationClaimDefinition) > 0
   OR @AlertFailDefinition IS NULL
   OR CHARINDEX(N'%[^-a-z0-9]%', @AlertFailDefinition) = 0
   OR CHARINDEX(N'%[^a-z0-9-]%', @AlertFailDefinition) > 0
    THROW 55021, N'One or more procedure hyphen allowlists remain ambiguous.', 1;

IF @OrganizationCreateDefinition IS NULL
   OR @OrganizationActionDefinition IS NULL
   OR CHARINDEX(@LegacyPreWriteRollbackToken, @OrganizationCreateDefinition) > 0
   OR CHARINDEX(@LegacyPreWriteRollbackToken, @OrganizationActionDefinition) > 0
   OR @OrganizationCreateCommitCount <> 7
   OR @OrganizationActionCommitCount <> 3
    THROW 55025, N'Organization connection pre-write outcomes are not ambient-transaction safe.', 1;

DECLARE @SemanticSubjectGuardDefinition NVARCHAR(MAX) = OBJECT_DEFINITION
    (OBJECT_ID(N'dbo.FundingPlatform_tr_SemanticEvaluationItems_SubjectGuard'));
IF NOT EXISTS
   (SELECT 1
    FROM sys.triggers
    WHERE object_id =
          OBJECT_ID(N'dbo.FundingPlatform_tr_SemanticEvaluationItems_SubjectGuard')
      AND parent_id = OBJECT_ID(N'dbo.FundingPlatform_SemanticEvaluationItems')
      AND is_disabled = 0
      AND is_instead_of_trigger = 1)
   OR @SemanticSubjectGuardDefinition IS NULL
   OR CHARINDEX(N'INSTEAD OF INSERT', @SemanticSubjectGuardDefinition) = 0
    THROW 55026, N'The semantic evaluation subject guard is not pre-mutation.', 1;

DECLARE @ProviderImmutableDefinition NVARCHAR(MAX) = OBJECT_DEFINITION
    (OBJECT_ID(N'dbo.FundingPlatform_tr_AiProviderGovernancePolicies_Immutable'));
IF NOT EXISTS
   (SELECT 1
    FROM sys.triggers
    WHERE object_id =
          OBJECT_ID(N'dbo.FundingPlatform_tr_AiProviderGovernancePolicies_Immutable')
      AND parent_id = OBJECT_ID(N'dbo.FundingPlatform_AiProviderGovernancePolicies')
      AND is_disabled = 0
      AND is_instead_of_trigger = 0)
   OR @ProviderImmutableDefinition IS NULL
   OR CHARINDEX(N'FundingPlatform_AiExplanationConfigurations',
                @ProviderImmutableDefinition) = 0
    THROW 55027, N'The provider immutability guard omits active explanation dependencies.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke029;

BEGIN TRY
    DECLARE @Suffix NVARCHAR(16) =
        LOWER(LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 16));
    DECLARE @Code NVARCHAR(50) = N'smoke-029_a.b-' + @Suffix;
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

    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_SemanticConfigurations WHERE Code = @Code)
        THROW 55022, N'An intended hyphenated semantic contract was rejected.', 1;

    DECLARE @InvalidCode NVARCHAR(50) = N'invalid/' + @Suffix;
    DECLARE @InvalidFingerprint BINARY(32) = CONVERT(BINARY(32), HASHBYTES
    (
        'SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
        (@InvalidCode, N'|1|development-deterministic|lexical-hash-1536-v1|1536|matching|',
         N'project-semantic-v1|opportunity-semantic-v1|semantic-text-v1|1|',
         N'cosine-linear-shadow-v1|8192|8|3|0.000000|1.000000|1'))
    ));
    DECLARE @InvalidCharacterError INT = 0;
    DECLARE @InvalidCharacterMessage NVARCHAR(2048) = N'';
    SET XACT_ABORT OFF;
    BEGIN TRY
        INSERT INTO dbo.FundingPlatform_SemanticConfigurations
            (Code, Version, ProviderCode, ModelCode, Dimensions, PurposeCode,
             ProjectTemplateVersion, OpportunityTemplateVersion, NormalizationVersion,
             DistanceMetric, CalibrationVersion, MaximumInputUtf8Bytes, MaximumBatchSize,
             MaximumAttempts, MaximumCostUsdPerEmbedding, MonthlyBudgetUsd,
             ConfigurationFingerprint, IsLocalFake, IsActive, PublishedAtUtc, CreatedAtUtc)
        VALUES
            (@InvalidCode, 1, N'development-deterministic', N'lexical-hash-1536-v1', 1536,
             N'matching', N'project-semantic-v1', N'opportunity-semantic-v1',
             N'semantic-text-v1', 1, N'cosine-linear-shadow-v1', 8192, 8, 3,
             0.000000, 1.000000, @InvalidFingerprint, 1, 0, @NowUtc, @NowUtc);
    END TRY
    BEGIN CATCH
        SET @InvalidCharacterError = ERROR_NUMBER();
        SET @InvalidCharacterMessage = ERROR_MESSAGE();
    END CATCH;
    SET XACT_ABORT ON;

    IF @InvalidCharacterError <> 547 OR XACT_STATE() <> 1
       OR CHARINDEX(N'FundingPlatform_CK_SemanticConfigurations_Text',
                    @InvalidCharacterMessage) = 0
        THROW 55023, N'The corrected allowlist accepted a forbidden character.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke029;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FP_Smoke029;
    THROW;
END CATCH;

SELECT N'SQL hyphen allowlist compatibility smoke passed.' AS Result;
GO
