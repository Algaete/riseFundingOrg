/* Transactional FASE 9B-B smoke: governed OpenAI embedding boundary.
   It never calls a provider and rolls back every fixture. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_AiProviderGovernancePolicies', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_AiProviderGovernancePolicyRequests', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_SemanticConfigurationPublishRequests', N'U') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_SemanticConfigurations',
                 N'ProviderGovernancePolicyId') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_SemanticConfigurations',
                 N'ProviderCapability') IS NULL
    THROW 54301, N'FASE 9B-B governance tables or configuration columns are missing.', 1;

IF OBJECT_ID(N'dbo.FundingPlatform_ifn_AiProviderGovernancePolicyState', N'IF') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ifn_SemanticConfigurationState', N'IF') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_AiEmbeddingProviderPolicy_AdminRegister', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_SemanticConfiguration_AdminPublishOpenAi', N'P') IS NULL
    THROW 54302, N'FASE 9B-B governance functions or administrator procedures are missing.', 1;

IF OBJECT_ID(N'dbo.FundingPlatform_tr_AiProviderGovernancePolicies_Immutable', N'TR') IS NULL
   OR OBJECT_DEFINITION(
      OBJECT_ID(N'dbo.FundingPlatform_tr_AiProviderGovernancePolicies_Immutable'))
      NOT LIKE N'%SET XACT_ABORT OFF%'
   OR OBJECT_DEFINITION(
      OBJECT_ID(N'dbo.FundingPlatform_tr_SemanticConfigurations_Immutable'))
      NOT LIKE N'%ProviderGovernancePolicyId%'
    THROW 54303, N'FASE 9B-B immutable governance guards are incomplete.', 1;

IF EXISTS
   (SELECT 1
    FROM sys.columns
    WHERE object_id IN
          (OBJECT_ID(N'dbo.FundingPlatform_AiProviderGovernancePolicies'),
           OBJECT_ID(N'dbo.FundingPlatform_AiProviderGovernancePolicyRequests'),
           OBJECT_ID(N'dbo.FundingPlatform_SemanticConfigurationPublishRequests'))
      AND (name LIKE N'%ApiKey%' OR name LIKE N'%Secret%' OR name LIKE N'%Prompt%'
           OR name LIKE N'%RawResponse%' OR name LIKE N'%CanonicalInput%'))
    THROW 54304, N'Governance persistence must not contain credentials or provider payloads.', 1;

IF DATABASE_PRINCIPAL_ID(N'FundingPlatform_SemanticWorkerRole') IS NULL
   OR DATABASE_PRINCIPAL_ID(N'FundingPlatform_SemanticAdminRole') IS NULL
   OR NOT EXISTS
      (SELECT 1 FROM sys.database_permissions
       WHERE grantee_principal_id =
             DATABASE_PRINCIPAL_ID(N'FundingPlatform_SemanticAdminRole')
         AND major_id =
             OBJECT_ID(N'dbo.FundingPlatform_usp_AiEmbeddingProviderPolicy_AdminRegister')
         AND permission_name = N'EXECUTE' AND state = N'G')
   OR NOT EXISTS
      (SELECT 1 FROM sys.database_permissions
       WHERE grantee_principal_id =
             DATABASE_PRINCIPAL_ID(N'FundingPlatform_SemanticWorkerRole')
         AND major_id =
             OBJECT_ID(N'dbo.FundingPlatform_AiProviderGovernancePolicies')
         AND permission_name = N'SELECT' AND state = N'D')
    THROW 54305, N'Governed provider least-privilege permissions are incomplete.', 1;

DECLARE @GetInputDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_SemanticEmbeddingJob_GetInput'));
IF @GetInputDefinition NOT LIKE N'%ProviderPolicyFingerprint%'
   OR @GetInputDefinition NOT LIKE N'%ProviderEndpointOrigin%'
   OR @GetInputDefinition NOT LIKE N'%ProviderCapability%'
   OR @GetInputDefinition NOT LIKE N'%OutputTokenCostUsdPerMillion%'
   OR @GetInputDefinition NOT LIKE N'%MaximumProviderRetentionDays%'
   OR @GetInputDefinition NOT LIKE N'%ExternalProcessingAllowed%'
   OR @GetInputDefinition LIKE N'%ApiKey%'
    THROW 54306, N'Embedding input wire does not carry bounded governance metadata.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke022;
BEGIN TRY
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @Suffix NVARCHAR(32) =
        LOWER(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''));
    DECLARE @SuperAdminRoleId SMALLINT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_Roles
         WHERE NormalizedName = N'SUPERADMIN' ORDER BY Id);
    IF @SuperAdminRoleId IS NULL
        THROW 54307, N'The seeded SuperAdmin role is required.', 1;

    DECLARE @AdminPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @AdminEmail NVARCHAR(320) =
        N'fase9bb-admin-' + @Suffix + N'@example.invalid';
    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@AdminPublicId, @AdminEmail, UPPER(@AdminEmail), N'FASE 9B-B smoke admin',
         N'not-a-credential', N'fase9bb-smoke', 1, 1, 2, N'es-CL');
    DECLARE @AdminUserId BIGINT = SCOPE_IDENTITY();
    INSERT INTO dbo.FundingPlatform_UserRoles
        (UserId, RoleId, GrantedByUserId, CreatedAtUtc)
    VALUES (@AdminUserId, @SuperAdminRoleId, @AdminUserId, @NowUtc);

    /* A pre-022 local fake keeps its original fingerprint exactly. */
    DECLARE @FakeCode NVARCHAR(50) = N'legacy-fake-' + LEFT(@Suffix, 20);
    DECLARE @FakeFingerprint BINARY(32) = CONVERT(BINARY(32), HASHBYTES
    (
        'SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
        (
            @FakeCode, N'|', 1, N'|', N'development-deterministic', N'|',
            N'lexical-hash-1536-v1', N'|', 1536, N'|', N'matching', N'|',
            N'project-semantic-v1', N'|', N'opportunity-semantic-v1', N'|',
            N'semantic-text-v1', N'|', 1, N'|', N'cosine-linear-shadow-v1', N'|',
            8192, N'|', 8, N'|', 3, N'|', CONVERT(DECIMAL(19,6), 0), N'|',
            CONVERT(DECIMAL(19,6), 1), N'|', 1
        ))
    ));
    BEGIN TRY
        INSERT INTO dbo.FundingPlatform_SemanticConfigurations
            (Code, Version, ProviderCode, ModelCode, Dimensions, PurposeCode,
             ProjectTemplateVersion, OpportunityTemplateVersion, NormalizationVersion,
             DistanceMetric, CalibrationVersion, MaximumInputUtf8Bytes,
             MaximumBatchSize, MaximumAttempts, MaximumCostUsdPerEmbedding,
             MonthlyBudgetUsd, ConfigurationFingerprint, IsLocalFake, IsActive,
             PublishedAtUtc, CreatedAtUtc)
        VALUES
            (@FakeCode, 1, N'development-deterministic', N'lexical-hash-1536-v1',
             1536, N'matching', N'project-semantic-v1', N'opportunity-semantic-v1',
             N'semantic-text-v1', 1, N'cosine-linear-shadow-v1', 8192, 8, 3,
             0, 1, @FakeFingerprint, 1, 0, @NowUtc, @NowUtc);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 547
           AND ERROR_MESSAGE() LIKE N'%FundingPlatform_CK_SemanticConfigurations_FrozenContract%'
            THROW 54317, N'The legacy fake violated the frozen configuration contract.', 1;
        IF ERROR_NUMBER() = 547
           AND ERROR_MESSAGE() LIKE N'%FundingPlatform_CK_SemanticConfigurations_Bounds%'
            THROW 54318, N'The legacy fake violated semantic configuration bounds.', 1;
        IF ERROR_NUMBER() = 547
           AND ERROR_MESSAGE() LIKE N'%FundingPlatform_CK_SemanticConfigurations_Text%'
            THROW 54319, N'The legacy fake violated the repaired text allowlist.', 1;
        IF ERROR_NUMBER() = 547
           AND ERROR_MESSAGE() LIKE N'%FundingPlatform_CK_SemanticConfigurations_LocalFake%'
            THROW 54320, N'The legacy fake violated local-provider separation.', 1;
        IF ERROR_NUMBER() = 547
           AND ERROR_MESSAGE() LIKE N'%FundingPlatform_CK_SemanticConfigurations_GovernedProvider%'
            THROW 54321, N'The legacy fake violated governed-provider compatibility.', 1;
        THROW;
    END CATCH;
    DECLARE @FakeConfigurationId INT = SCOPE_IDENTITY();
    IF NOT EXISTS
       (SELECT 1
        FROM dbo.FundingPlatform_ifn_SemanticConfigurationState(@FakeConfigurationId)
        WHERE CalculatedFingerprint = @FakeFingerprint)
        THROW 54308, N'022 changed the frozen 021 local-fake fingerprint.', 1;

    DECLARE @DpaHash BINARY(32) =
        CONVERT(BINARY(32), HASHBYTES('SHA2_256', N'dpa-' + @Suffix));
    DECLARE @TermsHash BINARY(32) =
        CONVERT(BINARY(32), HASHBYTES('SHA2_256', N'terms-' + @Suffix));
    DECLARE @PolicyKeyHash BINARY(32) =
        CONVERT(BINARY(32), HASHBYTES('SHA2_256', N'policy-key-' + @Suffix));
    DECLARE @PolicyRequestHash BINARY(32) =
        CONVERT(BINARY(32), HASHBYTES('SHA2_256', N'policy-request-' + @Suffix));
    DECLARE @PolicyCode NVARCHAR(50) = N'openai-embedding-' + LEFT(@Suffix, 20);
    DECLARE @BadRegionCode NVARCHAR(50) = N'bad-region-' + LEFT(@Suffix, 20);
    DECLARE @ConfigurationCode NVARCHAR(50) = N'openai-shadow-' + LEFT(@Suffix, 20);
    DECLARE @NoMfaCode NVARCHAR(50) = N'no-mfa-' + LEFT(@Suffix, 20);
    DECLARE @PolicyExpiresAtUtc DATETIME2(3) = DATEADD(DAY, 90, @NowUtc);
    DECLARE @PolicyOutput TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), WasReplay BIT, PublicId UNIQUEIDENTIFIER,
        PolicyVersion NVARCHAR(64), ProviderCode NVARCHAR(50), ModelCode NVARCHAR(128),
        EndpointOrigin NVARCHAR(200), RetentionMode TINYINT,
        MaximumProviderRetentionDays SMALLINT, DataResidencyCode NVARCHAR(16),
        PolicyFingerprint BINARY(32), InputTokenCostUsdPerMillion DECIMAL(19,6),
        ExternalProcessingAllowed BIT, IsActive BIT,
        ApprovedAtUtc DATETIME2(3), ExpiresAtUtc DATETIME2(3)
    );
    INSERT INTO @PolicyOutput
    EXEC dbo.FundingPlatform_usp_AiEmbeddingProviderPolicy_AdminRegister
        @SuperAdminUserPublicId = @AdminPublicId,
        @Code = @PolicyCode,
        @Version = 1,
        @ModelCode = N'text-embedding-3-small',
        @EndpointOrigin = N'https://api.openai.com',
        @DataResidencyCode = N'global',
        @DpaReferenceHash = @DpaHash,
        @TermsSnapshotHash = @TermsHash,
        @InputTokenCostUsdPerMillion = 0.020000,
        @ApprovedAtUtc = @NowUtc,
        @ExpiresAtUtc = @PolicyExpiresAtUtc,
        @IdempotencyKeyHash = @PolicyKeyHash,
        @RequestHash = @PolicyRequestHash,
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
           WHERE policies.PublicId = @PolicyPublicId
             AND policies.PolicyFingerprint = state.CalculatedFingerprint
             AND policies.RetentionMode = 2
             AND policies.MaximumProviderRetentionDays = 0
             AND policies.ExternalProcessingAllowed = 1)
        THROW 54309, N'Governed embedding policy was not registered exactly.', 1;

    DELETE FROM @PolicyOutput;
    INSERT INTO @PolicyOutput
    EXEC dbo.FundingPlatform_usp_AiEmbeddingProviderPolicy_AdminRegister
        @SuperAdminUserPublicId = @AdminPublicId,
        @Code = @PolicyCode,
        @Version = 1,
        @ModelCode = N'text-embedding-3-small',
        @EndpointOrigin = N'https://api.openai.com',
        @DataResidencyCode = N'global',
        @DpaReferenceHash = @DpaHash,
        @TermsSnapshotHash = @TermsHash,
        @InputTokenCostUsdPerMillion = 0.020000,
        @ApprovedAtUtc = @NowUtc,
        @ExpiresAtUtc = @PolicyExpiresAtUtc,
        @IdempotencyKeyHash = @PolicyKeyHash,
        @RequestHash = @PolicyRequestHash,
        @NowUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @PolicyOutput
        WHERE PublicId = @PolicyPublicId AND WasReplay = 1 AND Code = N'replayed')
        THROW 54310, N'Governance policy replay was not exact and idempotent.', 1;

    DECLARE @ExpectedError INT = 0;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AiEmbeddingProviderPolicy_AdminRegister
            @SuperAdminUserPublicId = @AdminPublicId,
            @Code = @PolicyCode,
            @Version = 1,
            @ModelCode = N'text-embedding-3-small',
            @EndpointOrigin = N'https://api.openai.com',
            @DataResidencyCode = N'global',
            @DpaReferenceHash = @DpaHash,
            @TermsSnapshotHash = @TermsHash,
            @InputTokenCostUsdPerMillion = 0.020000,
            @ApprovedAtUtc = @NowUtc,
            @ExpiresAtUtc = @PolicyExpiresAtUtc,
            @IdempotencyKeyHash = @PolicyKeyHash,
            @RequestHash = 0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA,
            @NowUtc = @NowUtc;
    END TRY
    BEGIN CATCH SET @ExpectedError = ERROR_NUMBER(); END CATCH;
    IF @ExpectedError <> 54208 OR XACT_STATE() <> 1
        THROW 54311, N'Governance idempotency conflict did not fail safely.', 1;

    SET @ExpectedError = 0;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AiEmbeddingProviderPolicy_AdminRegister
            @SuperAdminUserPublicId = @AdminPublicId,
            @Code = @BadRegionCode,
            @Version = 1,
            @ModelCode = N'text-embedding-3-small',
            @EndpointOrigin = N'https://api.openai.com',
            @DataResidencyCode = N'eu',
            @DpaReferenceHash = @DpaHash,
            @TermsSnapshotHash = @TermsHash,
            @InputTokenCostUsdPerMillion = 0.020000,
            @ApprovedAtUtc = @NowUtc,
            @ExpiresAtUtc = @PolicyExpiresAtUtc,
            @IdempotencyKeyHash =
                0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB,
            @RequestHash =
                0xCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC,
            @NowUtc = @NowUtc;
    END TRY
    BEGIN CATCH SET @ExpectedError = ERROR_NUMBER(); END CATCH;
    IF @ExpectedError <> 54206 OR XACT_STATE() <> 1
        THROW 54312, N'Region/endpoint drift was not rejected before publication.', 1;

    DECLARE @ConfigOutput TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), WasReplay BIT, PublicId UNIQUEIDENTIFIER,
        ConfigurationVersion NVARCHAR(64), ProviderPolicyPublicId UNIQUEIDENTIFIER,
        ProviderPolicyFingerprint BINARY(32), ProviderCode NVARCHAR(50),
        ModelCode NVARCHAR(128), Dimensions SMALLINT, MaximumBatchSize TINYINT,
        MaximumCostUsdPerEmbedding DECIMAL(19,6), MonthlyBudgetUsd DECIMAL(19,6),
        IsActive BIT, PublishedAtUtc DATETIME2(3)
    );
    DECLARE @ConfigKeyHash BINARY(32) =
        CONVERT(BINARY(32), HASHBYTES('SHA2_256', N'config-key-' + @Suffix));
    DECLARE @ConfigRequestHash BINARY(32) =
        CONVERT(BINARY(32), HASHBYTES('SHA2_256', N'config-request-' + @Suffix));
    INSERT INTO @ConfigOutput
    EXEC dbo.FundingPlatform_usp_SemanticConfiguration_AdminPublishOpenAi
        @SuperAdminUserPublicId = @AdminPublicId,
        @ProviderPolicyPublicId = @PolicyPublicId,
        @Code = @ConfigurationCode,
        @Version = 1,
        @MaximumBatchSize = 8,
        @MaximumCostUsdPerEmbedding = 0.001000,
        @MonthlyBudgetUsd = 10.000000,
        @IdempotencyKeyHash = @ConfigKeyHash,
        @RequestHash = @ConfigRequestHash,
        @NowUtc = @NowUtc;
    DECLARE @ConfigurationPublicId UNIQUEIDENTIFIER =
        (SELECT PublicId FROM @ConfigOutput WHERE Succeeded = 1 AND WasReplay = 0);
    IF @ConfigurationPublicId IS NULL
       OR NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_SemanticConfigurations AS configurations
           CROSS APPLY dbo.FundingPlatform_ifn_SemanticConfigurationState(configurations.Id)
               AS state
           WHERE configurations.PublicId = @ConfigurationPublicId
             AND configurations.ProviderGovernancePolicyId =
                 (SELECT Id FROM dbo.FundingPlatform_AiProviderGovernancePolicies
                  WHERE PublicId = @PolicyPublicId)
             AND configurations.ConfigurationFingerprint = state.CalculatedFingerprint
             AND configurations.IsLocalFake = 0 AND configurations.IsActive = 1)
        THROW 54313, N'OpenAI semantic configuration was not published with exact governance.', 1;

    DELETE FROM @ConfigOutput;
    INSERT INTO @ConfigOutput
    EXEC dbo.FundingPlatform_usp_SemanticConfiguration_AdminPublishOpenAi
        @SuperAdminUserPublicId = @AdminPublicId,
        @ProviderPolicyPublicId = @PolicyPublicId,
        @Code = @ConfigurationCode,
        @Version = 1,
        @MaximumBatchSize = 8,
        @MaximumCostUsdPerEmbedding = 0.001000,
        @MonthlyBudgetUsd = 10.000000,
        @IdempotencyKeyHash = @ConfigKeyHash,
        @RequestHash = @ConfigRequestHash,
        @NowUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @ConfigOutput
        WHERE PublicId = @ConfigurationPublicId AND WasReplay = 1 AND Code = N'replayed')
        THROW 54314, N'Semantic configuration replay was not exact and idempotent.', 1;

    SAVE TRANSACTION FP_Smoke022PolicyGuard;
    SET @ExpectedError = 0;
    BEGIN TRY
        UPDATE dbo.FundingPlatform_AiProviderGovernancePolicies
        SET IsActive = 0 WHERE PublicId = @PolicyPublicId;
    END TRY
    BEGIN CATCH SET @ExpectedError = ERROR_NUMBER(); END CATCH;
    IF @ExpectedError <> 54205 OR XACT_STATE() <> 1
        THROW 54315, N'Active configuration did not protect its governance policy.', 1;
    ROLLBACK TRANSACTION FP_Smoke022PolicyGuard;
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_AiProviderGovernancePolicies
        WHERE PublicId = @PolicyPublicId AND IsActive = 1)
        THROW 54322, N'The rejected governance deactivation was not reverted.', 1;

    DECLARE @NoMfaPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @NoMfaEmail NVARCHAR(320) =
        N'fase9bb-no-mfa-' + @Suffix + N'@example.invalid';
    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@NoMfaPublicId, @NoMfaEmail, UPPER(@NoMfaEmail),
         N'FASE 9B-B no MFA', N'not-a-credential', N'fase9bb-no-mfa',
         1, 0, 2, N'es-CL');
    DECLARE @NoMfaUserId BIGINT = SCOPE_IDENTITY();
    INSERT INTO dbo.FundingPlatform_UserRoles
        (UserId, RoleId, GrantedByUserId, CreatedAtUtc)
    VALUES (@NoMfaUserId, @SuperAdminRoleId, @AdminUserId, @NowUtc);
    SET @ExpectedError = 0;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AiEmbeddingProviderPolicy_AdminRegister
            @SuperAdminUserPublicId = @NoMfaPublicId,
            @Code = @NoMfaCode,
            @Version = 1,
            @ModelCode = N'text-embedding-3-small',
            @EndpointOrigin = N'https://api.openai.com',
            @DataResidencyCode = N'global',
            @DpaReferenceHash = @DpaHash,
            @TermsSnapshotHash = @TermsHash,
            @InputTokenCostUsdPerMillion = 0.020000,
            @ApprovedAtUtc = @NowUtc,
            @ExpiresAtUtc = @PolicyExpiresAtUtc,
            @IdempotencyKeyHash =
                0xDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD,
            @RequestHash =
                0xEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE,
            @NowUtc = @NowUtc;
    END TRY
    BEGIN CATCH SET @ExpectedError = ERROR_NUMBER(); END CATCH;
    IF @ExpectedError <> 51602 OR XACT_STATE() <> 1
        THROW 54316, N'Governance publication did not require recent MFA.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke022;
    SELECT N'FASE 9B-B governed OpenAI provider smoke passed.' AS Result;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FP_Smoke022;
    THROW;
END CATCH;
