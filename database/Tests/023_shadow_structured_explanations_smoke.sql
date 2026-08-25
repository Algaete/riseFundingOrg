/* Transactional FASE 9B-B smoke: governed Structured Outputs control plane.
   It never calls OpenAI, commits no fixture and never changes 9A/9B-A output. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_AiExplanationConfigurations', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_AiExplanationRuns', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_AiExplanationJobs', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_AiExplanationBudgetReservations', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_AiExplanationUsageLedger', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_AiExplanationResults', N'U') IS NULL
    THROW 54501, N'FASE 9B-B explanation persistence is missing.', 1;

IF OBJECT_ID(N'dbo.FundingPlatform_fn_AiExplanationCanonicalInput', N'FN') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_fn_AiExplanationCitedRulesValid', N'FN') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ifn_AiExplanationConfigurationState', N'IF') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ifn_AiExplanationRunSummaries', N'IF') IS NULL
    THROW 54502, N'FASE 9B-B explanation functions are missing.', 1;

DECLARE @RequiredProcedures TABLE (Name SYSNAME NOT NULL PRIMARY KEY);
INSERT INTO @RequiredProcedures (Name) VALUES
    (N'FundingPlatform_usp_AiStructuredOutputProviderPolicy_AdminRegister'),
    (N'FundingPlatform_usp_AiExplanationConfiguration_AdminPublishOpenAi'),
    (N'FundingPlatform_usp_AiExplanationRun_Create'),
    (N'FundingPlatform_usp_AiExplanationJob_Claim'),
    (N'FundingPlatform_usp_AiExplanationJob_GetInput'),
    (N'FundingPlatform_usp_AiExplanationJob_RenewLease'),
    (N'FundingPlatform_usp_AiExplanationJob_Complete'),
    (N'FundingPlatform_usp_AiExplanationJob_Fail'),
    (N'FundingPlatform_usp_AiExplanationRun_AdminGet');
IF EXISTS
   (SELECT 1 FROM @RequiredProcedures
    WHERE OBJECT_ID(N'dbo.' + Name, N'P') IS NULL)
    THROW 54503, N'FASE 9B-B explanation procedures are incomplete.', 1;

DECLARE @RequiredTriggers TABLE (Name SYSNAME NOT NULL PRIMARY KEY);
INSERT INTO @RequiredTriggers (Name) VALUES
    (N'FundingPlatform_tr_AiExplanationConfigurations_Immutable'),
    (N'FundingPlatform_tr_AiExplanationRuns_Immutable'),
    (N'FundingPlatform_tr_AiExplanationJobs_SubjectGuard'),
    (N'FundingPlatform_tr_AiExplanationJobs_Immutable'),
    (N'FundingPlatform_tr_AiExplanationBudgetReservations_Guard'),
    (N'FundingPlatform_tr_AiExplanationUsageLedger_Immutable'),
    (N'FundingPlatform_tr_AiExplanationResults_Guard'),
    (N'FundingPlatform_tr_AiExplanationRunRequests_Immutable'),
    (N'FundingPlatform_tr_AiExplanationConfigRequests_Immutable');
IF EXISTS
   (SELECT 1 FROM @RequiredTriggers
    WHERE OBJECT_ID(N'dbo.' + Name, N'TR') IS NULL
       OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.' + Name, N'TR'))
          NOT LIKE N'%SET XACT_ABORT OFF%')
    THROW 54504, N'Explanation immutable guards are incomplete.', 1;

IF EXISTS
   (SELECT 1 FROM sys.columns
    WHERE object_id IN
          (OBJECT_ID(N'dbo.FundingPlatform_AiExplanationConfigurations'),
           OBJECT_ID(N'dbo.FundingPlatform_AiExplanationRuns'),
           OBJECT_ID(N'dbo.FundingPlatform_AiExplanationJobs'),
           OBJECT_ID(N'dbo.FundingPlatform_AiExplanationBudgetReservations'),
           OBJECT_ID(N'dbo.FundingPlatform_AiExplanationUsageLedger'),
           OBJECT_ID(N'dbo.FundingPlatform_AiExplanationResults'))
      AND (name LIKE N'%ApiKey%' OR name LIKE N'%Secret%'
           OR name LIKE N'%PromptText%' OR name LIKE N'%RawResponse%'
           OR name LIKE N'%CanonicalInput%'))
    THROW 54505, N'Explanation persistence contains a prohibited payload column.', 1;

IF dbo.FundingPlatform_fn_AiExplanationCitedRulesValid
   (N'["categories","geography"]') <> 1
   OR dbo.FundingPlatform_fn_AiExplanationCitedRulesValid
      (N'["geography","categories"]') <> 0
   OR dbo.FundingPlatform_fn_AiExplanationCitedRulesValid
      (N'["categories","categories"]') <> 0
   OR dbo.FundingPlatform_fn_AiExplanationCitedRulesValid(N'["not-a-rule"]') <> 0
    THROW 54506, N'Cited rule codes are not exact, unique and canonical.', 1;

IF DATABASE_PRINCIPAL_ID(N'FundingPlatform_SemanticWorkerRole') IS NULL
   OR DATABASE_PRINCIPAL_ID(N'FundingPlatform_SemanticAdminRole') IS NULL
   OR NOT EXISTS
      (SELECT 1 FROM sys.database_permissions
       WHERE grantee_principal_id =
             DATABASE_PRINCIPAL_ID(N'FundingPlatform_SemanticWorkerRole')
         AND major_id = OBJECT_ID(N'dbo.FundingPlatform_usp_AiExplanationJob_Claim')
         AND permission_name = N'EXECUTE' AND state = N'G')
   OR NOT EXISTS
      (SELECT 1 FROM sys.database_permissions
       WHERE grantee_principal_id =
             DATABASE_PRINCIPAL_ID(N'FundingPlatform_SemanticAdminRole')
         AND major_id = OBJECT_ID
             (N'dbo.FundingPlatform_usp_AiStructuredOutputProviderPolicy_AdminRegister')
         AND permission_name = N'EXECUTE' AND state = N'G')
   OR NOT EXISTS
      (SELECT 1 FROM sys.database_permissions
       WHERE grantee_principal_id =
             DATABASE_PRINCIPAL_ID(N'FundingPlatform_SemanticWorkerRole')
         AND major_id = OBJECT_ID(N'dbo.FundingPlatform_AiExplanationResults')
         AND permission_name = N'SELECT' AND state = N'D')
    THROW 54507, N'Explanation roles do not expose the exact SP-only surface.', 1;

DECLARE @GetInputDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_AiExplanationJob_GetInput'));
IF @GetInputDefinition NOT LIKE N'%ProviderPolicyFingerprint%'
   OR @GetInputDefinition NOT LIKE N'%ProviderCapability%'
   OR @GetInputDefinition NOT LIKE N'%MaximumProviderRetentionDays%'
   OR @GetInputDefinition NOT LIKE N'%OutputTokenCostUsdPerMillion%'
   OR @GetInputDefinition LIKE N'%ApiKey%'
    THROW 54508, N'Explanation input wire lacks governed provider metadata.', 1;

DECLARE @CompleteDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_AiExplanationJob_Complete'));
IF @CompleteDefinition NOT LIKE N'%@ExpectedProviderCode%'
   OR @CompleteDefinition NOT LIKE N'%@ExpectedModelCode%'
   OR @CompleteDefinition NOT LIKE N'%@ExpectedPromptVersion%'
   OR @CompleteDefinition NOT LIKE N'%@ExpectedOutputSchemaVersion%'
   OR @CompleteDefinition NOT LIKE N'%Completed explanation replay did not match%'
    THROW 54517, N'Completed output replay does not bind the exact provider contract.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @Suffix NVARCHAR(32) = REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N'');
    DECLARE @SuperAdminRoleId SMALLINT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_Roles
         WHERE NormalizedName = N'SUPERADMIN' ORDER BY Id);
    IF @SuperAdminRoleId IS NULL THROW 54509, N'The SuperAdmin role is required.', 1;
    DECLARE @AdminPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @AdminEmail NVARCHAR(320) =
        N'fase9bb-structured-' + @Suffix + N'@example.invalid';
    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@AdminPublicId, @AdminEmail, UPPER(@AdminEmail), N'9B-B smoke admin',
         N'not-a-credential', N'9bb-structured', 1, 1, 2, N'es-CL');
    DECLARE @AdminUserId BIGINT = SCOPE_IDENTITY();
    INSERT INTO dbo.FundingPlatform_UserRoles
        (UserId, RoleId, GrantedByUserId, CreatedAtUtc)
    VALUES (@AdminUserId, @SuperAdminRoleId, @AdminUserId, @NowUtc);

    DECLARE @DpaHash BINARY(32) =
        CONVERT(BINARY(32), HASHBYTES('SHA2_256', N'dpa-' + @Suffix));
    DECLARE @TermsHash BINARY(32) =
        CONVERT(BINARY(32), HASHBYTES('SHA2_256', N'terms-' + @Suffix));
    DECLARE @PolicyKeyHash BINARY(32) =
        CONVERT(BINARY(32), HASHBYTES('SHA2_256', N'policy-key-' + @Suffix));
    DECLARE @PolicyRequestHash BINARY(32) =
        CONVERT(BINARY(32), HASHBYTES('SHA2_256', N'policy-request-' + @Suffix));
    DECLARE @PolicyCode NVARCHAR(50) = N'structured-' + LEFT(@Suffix, 20);
    DECLARE @PolicyExpiresAtUtc DATETIME2(3) = DATEADD(DAY, 90, @NowUtc);
    DECLARE @PolicyOutput TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), WasReplay BIT, PublicId UNIQUEIDENTIFIER,
        PolicyVersion NVARCHAR(64), ProviderCode NVARCHAR(50), ModelCode NVARCHAR(128),
        Capability TINYINT, EndpointOrigin NVARCHAR(200), RetentionMode TINYINT,
        MaximumProviderRetentionDays SMALLINT, DataResidencyCode NVARCHAR(16),
        PolicyFingerprint BINARY(32), InputTokenCostUsdPerMillion DECIMAL(19,6),
        OutputTokenCostUsdPerMillion DECIMAL(19,6), ExternalProcessingAllowed BIT,
        IsActive BIT, ApprovedAtUtc DATETIME2(3), ExpiresAtUtc DATETIME2(3)
    );
    INSERT INTO @PolicyOutput
    EXEC dbo.FundingPlatform_usp_AiStructuredOutputProviderPolicy_AdminRegister
        @SuperAdminUserPublicId = @AdminPublicId, @Code = @PolicyCode, @Version = 1,
        @EndpointOrigin = N'https://api.openai.com', @DataResidencyCode = N'global',
        @DpaReferenceHash = @DpaHash, @TermsSnapshotHash = @TermsHash,
        @InputTokenCostUsdPerMillion = 2.000000,
        @OutputTokenCostUsdPerMillion = 10.000000,
        @ApprovedAtUtc = @NowUtc, @ExpiresAtUtc = @PolicyExpiresAtUtc,
        @IdempotencyKeyHash = @PolicyKeyHash, @RequestHash = @PolicyRequestHash,
        @NowUtc = @NowUtc;
    DECLARE @PolicyPublicId UNIQUEIDENTIFIER =
        (SELECT PublicId FROM @PolicyOutput WHERE Succeeded = 1 AND WasReplay = 0);
    DECLARE @PolicyFingerprint BINARY(32) =
        (SELECT PolicyFingerprint FROM @PolicyOutput WHERE PublicId = @PolicyPublicId);
    IF @PolicyPublicId IS NULL OR @PolicyFingerprint IS NULL
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_AiProviderGovernancePolicies AS policies
           CROSS APPLY dbo.FundingPlatform_ifn_AiProviderGovernancePolicyState(policies.Id)
               AS state
           WHERE policies.PublicId = @PolicyPublicId AND policies.Capability = 1
             AND policies.ProviderCode COLLATE Latin1_General_100_BIN2 =
                 N'openai' COLLATE Latin1_General_100_BIN2
             AND policies.ModelCode COLLATE Latin1_General_100_BIN2 =
                 N'gpt-5.6-sol' COLLATE Latin1_General_100_BIN2
             AND policies.RetentionMode = 2 AND policies.MaximumProviderRetentionDays = 0
             AND policies.PolicyFingerprint = state.CalculatedFingerprint)
        THROW 54510, N'Structured Outputs policy was not registered exactly.', 1;

    DELETE FROM @PolicyOutput;
    INSERT INTO @PolicyOutput
    EXEC dbo.FundingPlatform_usp_AiStructuredOutputProviderPolicy_AdminRegister
        @SuperAdminUserPublicId = @AdminPublicId, @Code = @PolicyCode, @Version = 1,
        @EndpointOrigin = N'https://api.openai.com', @DataResidencyCode = N'global',
        @DpaReferenceHash = @DpaHash, @TermsSnapshotHash = @TermsHash,
        @InputTokenCostUsdPerMillion = 2.000000,
        @OutputTokenCostUsdPerMillion = 10.000000,
        @ApprovedAtUtc = @NowUtc, @ExpiresAtUtc = @PolicyExpiresAtUtc,
        @IdempotencyKeyHash = @PolicyKeyHash, @RequestHash = @PolicyRequestHash,
        @NowUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @PolicyOutput
        WHERE PublicId = @PolicyPublicId AND WasReplay = 1 AND Code = N'replayed')
        THROW 54511, N'Structured policy replay was not exact.', 1;

    DECLARE @ConfigCode NVARCHAR(50) = N'explanation-' + LEFT(@Suffix, 20);
    DECLARE @ConfigKeyHash BINARY(32) =
        CONVERT(BINARY(32), HASHBYTES('SHA2_256', N'config-key-' + @Suffix));
    DECLARE @ConfigRequestHash BINARY(32) =
        CONVERT(BINARY(32), HASHBYTES('SHA2_256', N'config-request-' + @Suffix));
    DECLARE @ConfigOutput TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), WasReplay BIT, PublicId UNIQUEIDENTIFIER,
        ConfigurationVersion NVARCHAR(64), ProviderPolicyPublicId UNIQUEIDENTIFIER,
        ProviderPolicyFingerprint BINARY(32), ProviderCode NVARCHAR(50),
        ModelCode NVARCHAR(128), InputSchemaVersion NVARCHAR(50),
        OutputSchemaVersion NVARCHAR(50), PromptVersion NVARCHAR(50),
        PromptFingerprint BINARY(32), ResponseSchemaFingerprint BINARY(32),
        MaximumOutputTokens SMALLINT, MaximumCostUsdPerResult DECIMAL(19,6),
        MonthlyBudgetUsd DECIMAL(19,6), IsActive BIT, PublishedAtUtc DATETIME2(3)
    );
    INSERT INTO @ConfigOutput
    EXEC dbo.FundingPlatform_usp_AiExplanationConfiguration_AdminPublishOpenAi
        @SuperAdminUserPublicId = @AdminPublicId,
        @ProviderPolicyPublicId = @PolicyPublicId, @Code = @ConfigCode, @Version = 1,
        @MaximumOutputTokens = 512, @MaximumCostUsdPerResult = 0.100000,
        @MonthlyBudgetUsd = 10.000000, @IdempotencyKeyHash = @ConfigKeyHash,
        @RequestHash = @ConfigRequestHash, @NowUtc = @NowUtc;
    DECLARE @ConfigurationPublicId UNIQUEIDENTIFIER =
        (SELECT PublicId FROM @ConfigOutput WHERE Succeeded = 1 AND WasReplay = 0);
    IF @ConfigurationPublicId IS NULL
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_AiExplanationConfigurations AS configurations
           CROSS APPLY dbo.FundingPlatform_ifn_AiExplanationConfigurationState
               (configurations.Id) AS state
           WHERE configurations.PublicId = @ConfigurationPublicId
             AND configurations.ConfigurationFingerprint = state.CalculatedFingerprint
             AND configurations.ProviderCapability = 1
             AND configurations.PromptVersion = N'explanation-review-es-v1'
             AND configurations.IsActive = 1)
        THROW 54512, N'Explanation configuration was not published exactly.', 1;

    DELETE FROM @ConfigOutput;
    INSERT INTO @ConfigOutput
    EXEC dbo.FundingPlatform_usp_AiExplanationConfiguration_AdminPublishOpenAi
        @SuperAdminUserPublicId = @AdminPublicId,
        @ProviderPolicyPublicId = @PolicyPublicId, @Code = @ConfigCode, @Version = 1,
        @MaximumOutputTokens = 512, @MaximumCostUsdPerResult = 0.100000,
        @MonthlyBudgetUsd = 10.000000, @IdempotencyKeyHash = @ConfigKeyHash,
        @RequestHash = @ConfigRequestHash, @NowUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @ConfigOutput
        WHERE PublicId = @ConfigurationPublicId AND WasReplay = 1 AND Code = N'replayed')
        THROW 54513, N'Explanation configuration replay was not exact.', 1;

    DECLARE @RunOutput TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), WasReplay BIT, PublicId UNIQUEIDENTIFIER,
        SourceSemanticEvaluationRunPublicId UNIQUEIDENTIFIER, Status TINYINT,
        ExplanationConfigurationVersion NVARCHAR(64), ProviderCode NVARCHAR(50),
        ModelCode NVARCHAR(128), ItemCount SMALLINT, CompletedCount SMALLINT,
        FailedCount SMALLINT, TotalEstimatedCostUsd DECIMAL(19,6),
        CreatedAtUtc DATETIME2(3), CompletedAtUtc DATETIME2(3)
    );
    DECLARE @UnknownRun UNIQUEIDENTIFIER = NEWID();
    DECLARE @RunCountBefore BIGINT =
        (SELECT COUNT_BIG(*) FROM dbo.FundingPlatform_AiExplanationRuns);
    DECLARE @ConfigurationVersion NVARCHAR(64) =
        (SELECT ConfigurationVersion FROM @ConfigOutput);
    INSERT INTO @RunOutput
    EXEC dbo.FundingPlatform_usp_AiExplanationRun_Create
        @AdminUserPublicId = @AdminPublicId,
        @SourceSemanticEvaluationRunPublicId = @UnknownRun,
        @ExplanationConfigurationVersion = @ConfigurationVersion,
        @IdempotencyKeyHash =
            0x1111111111111111111111111111111111111111111111111111111111111111,
        @RequestHash =
            0x2222222222222222222222222222222222222222222222222222222222222222,
        @RuntimeEnabled = 0, @NowUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @RunOutput
        WHERE Succeeded = 0 AND Code = N'structured-outputs-disabled')
       OR (SELECT COUNT_BIG(*) FROM dbo.FundingPlatform_AiExplanationRuns) <>
          @RunCountBefore
        THROW 54514, N'Disabled runtime did not remain a no-write kill switch.', 1;

    DECLARE @ExpectedError INT = 0;
    BEGIN TRY
        UPDATE dbo.FundingPlatform_AiProviderGovernancePolicies
        SET IsActive = 0 WHERE PublicId = @PolicyPublicId;
    END TRY
    BEGIN CATCH SET @ExpectedError = ERROR_NUMBER(); END CATCH;
    IF @ExpectedError <> 54205 OR XACT_STATE() <> 1
        THROW 54515, N'Active explanation configuration did not protect its policy.', 1;

    DECLARE @NoMfaPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @NoMfaPolicyCode NVARCHAR(50) = N'no-mfa-' + LEFT(@Suffix, 20);
    DECLARE @NoMfaEmail NVARCHAR(320) =
        N'fase9bb-no-mfa-' + @Suffix + N'@example.invalid';
    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@NoMfaPublicId, @NoMfaEmail, UPPER(@NoMfaEmail), N'No MFA',
         N'not-a-credential', N'9bb-no-mfa', 1, 0, 2, N'es-CL');
    DECLARE @NoMfaUserId BIGINT = SCOPE_IDENTITY();
    INSERT INTO dbo.FundingPlatform_UserRoles
        (UserId, RoleId, GrantedByUserId, CreatedAtUtc)
    VALUES (@NoMfaUserId, @SuperAdminRoleId, @AdminUserId, @NowUtc);
    SET @ExpectedError = 0;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AiStructuredOutputProviderPolicy_AdminRegister
            @SuperAdminUserPublicId = @NoMfaPublicId,
            @Code = @NoMfaPolicyCode, @Version = 1,
            @EndpointOrigin = N'https://api.openai.com',
            @DataResidencyCode = N'global', @DpaReferenceHash = @DpaHash,
            @TermsSnapshotHash = @TermsHash,
            @InputTokenCostUsdPerMillion = 2.000000,
            @OutputTokenCostUsdPerMillion = 10.000000,
            @ApprovedAtUtc = @NowUtc, @ExpiresAtUtc = @PolicyExpiresAtUtc,
            @IdempotencyKeyHash =
                0x3333333333333333333333333333333333333333333333333333333333333333,
            @RequestHash =
                0x4444444444444444444444444444444444444444444444444444444444444444,
            @NowUtc = @NowUtc;
    END TRY
    BEGIN CATCH SET @ExpectedError = ERROR_NUMBER(); END CATCH;
    IF @ExpectedError <> 51602 OR XACT_STATE() <> 1
        THROW 54516, N'Structured policy publication did not require recent MFA.', 1;

    ROLLBACK TRANSACTION;
    SELECT N'FASE 9B-B Structured Outputs control-plane smoke passed.' AS Result;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
