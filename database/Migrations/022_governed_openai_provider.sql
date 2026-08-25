/* FundingPlatform FASE 9B-B - governed external embedding provider.
   Requires 021. This migration stores no API key, prompt, canonical input or raw
   provider response. OpenAI remains disabled until an immutable ZDR policy and
   a linked semantic configuration are published through the audited boundary. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_SemanticConfigurations', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_SemanticEmbeddingJobs', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_SemanticEmbeddingJob_GetInput', N'P') IS NULL
    THROW 54201, N'FASE 9B-B requires migration 021 to be applied first.', 1;

CREATE TABLE dbo.FundingPlatform_AiProviderGovernancePolicies
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_AiProviderGovernancePolicies_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    Code NVARCHAR(50) NOT NULL,
    Version INT NOT NULL,
    ProviderCode NVARCHAR(50) NOT NULL,
    ModelCode NVARCHAR(128) NOT NULL,
    Capability TINYINT NOT NULL,
    EndpointOrigin NVARCHAR(200) NOT NULL,
    RetentionMode TINYINT NOT NULL,
    MaximumProviderRetentionDays SMALLINT NOT NULL,
    DataResidencyCode NVARCHAR(16) NOT NULL,
    DpaReferenceHash BINARY(32) NOT NULL,
    TermsSnapshotHash BINARY(32) NOT NULL,
    InputTokenCostUsdPerMillion DECIMAL(19,6) NOT NULL,
    OutputTokenCostUsdPerMillion DECIMAL(19,6) NOT NULL,
    PolicyFingerprint BINARY(32) NOT NULL,
    ExternalProcessingAllowed BIT NOT NULL,
    IsActive BIT NOT NULL,
    ApprovedByUserId BIGINT NOT NULL,
    ApprovedAtUtc DATETIME2(3) NOT NULL,
    ExpiresAtUtc DATETIME2(3) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_AiProviderGovernancePolicies PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_AiProviderGovernancePolicies_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_AiProviderGovernancePolicies_CodeVersion
        UNIQUE (Code, Version),
    CONSTRAINT FundingPlatform_UQ_AiProviderGovernancePolicies_Identity
        UNIQUE (Id, ProviderCode, ModelCode, Capability),
    CONSTRAINT FundingPlatform_FK_AiProviderGovernancePolicies_Approver
        FOREIGN KEY (ApprovedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_AiProviderGovernancePolicies_Contract CHECK
        (Version >= 1 AND Capability IN (0, 1, 2)
         AND RetentionMode IN (0, 1, 2)
         AND MaximumProviderRetentionDays BETWEEN 0 AND 30
         AND InputTokenCostUsdPerMillion BETWEEN 0 AND 1000
         AND OutputTokenCostUsdPerMillion BETWEEN 0 AND 1000
         AND ApprovedAtUtc <= CreatedAtUtc AND CreatedAtUtc < ExpiresAtUtc
         AND (ExternalProcessingAllowed = 0
              OR (ProviderCode COLLATE Latin1_General_100_BIN2 =
                      N'openai' COLLATE Latin1_General_100_BIN2
                  AND ModelCode COLLATE Latin1_General_100_BIN2 IN
                      (N'text-embedding-3-small', N'text-embedding-3-large')
                  AND Capability = 0 AND RetentionMode = 2
                  AND MaximumProviderRetentionDays = 0))),
    CONSTRAINT FundingPlatform_CK_AiProviderGovernancePolicies_Text CHECK
        (LEN(LTRIM(RTRIM(Code))) BETWEEN 1 AND 50
         AND LEN(CONCAT(Code, N'-v', Version)) <= 64
         AND Code NOT LIKE N'%[^a-z0-9._-]%' COLLATE Latin1_General_100_BIN2
         AND LEN(LTRIM(RTRIM(ProviderCode))) BETWEEN 1 AND 50
         AND LEN(LTRIM(RTRIM(ModelCode))) BETWEEN 1 AND 128
         AND ProviderCode NOT LIKE N'%[^A-Za-z0-9._-]%' COLLATE Latin1_General_100_BIN2
         AND ModelCode NOT LIKE N'%[^A-Za-z0-9._-]%' COLLATE Latin1_General_100_BIN2
         AND DATALENGTH(Code) = DATALENGTH(LTRIM(RTRIM(Code)))
         AND DATALENGTH(ProviderCode) = DATALENGTH(LTRIM(RTRIM(ProviderCode)))
         AND DATALENGTH(ModelCode) = DATALENGTH(LTRIM(RTRIM(ModelCode)))
         AND DataResidencyCode IN
             (N'global', N'us', N'eu', N'au', N'ca', N'jp', N'in', N'sg', N'kr', N'gb', N'ae')
         AND EndpointOrigin IN
             (N'https://api.openai.com', N'https://us.api.openai.com',
              N'https://eu.api.openai.com', N'https://au.api.openai.com',
              N'https://ca.api.openai.com', N'https://jp.api.openai.com',
              N'https://in.api.openai.com', N'https://sg.api.openai.com', N'https://kr.api.openai.com',
              N'https://gb.api.openai.com', N'https://ae.api.openai.com')
         AND ((DataResidencyCode COLLATE Latin1_General_100_BIN2 =
                   N'global' COLLATE Latin1_General_100_BIN2
               AND EndpointOrigin COLLATE Latin1_General_100_BIN2 =
                   N'https://api.openai.com' COLLATE Latin1_General_100_BIN2)
              OR EndpointOrigin COLLATE Latin1_General_100_BIN2 =
                 CONCAT(N'https://', DataResidencyCode, N'.api.openai.com')
                    COLLATE Latin1_General_100_BIN2))
);

CREATE TABLE dbo.FundingPlatform_AiProviderGovernancePolicyRequests
(
    UserId BIGINT NOT NULL,
    IdempotencyKeyHash BINARY(32) NOT NULL,
    RequestHash BINARY(32) NOT NULL,
    ProviderGovernancePolicyId BIGINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_AiProviderGovernancePolicyRequests
        PRIMARY KEY (UserId, IdempotencyKeyHash),
    CONSTRAINT FundingPlatform_FK_AiProviderGovernancePolicyRequests_User
        FOREIGN KEY (UserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_AiProviderGovernancePolicyRequests_Policy
        FOREIGN KEY (ProviderGovernancePolicyId)
        REFERENCES dbo.FundingPlatform_AiProviderGovernancePolicies (Id)
);

IF EXISTS
   (SELECT 1 FROM dbo.FundingPlatform_SemanticConfigurations WHERE IsLocalFake = 0)
    THROW 54202, N'Existing real semantic configurations must be reviewed before 022.', 1;

ALTER TABLE dbo.FundingPlatform_SemanticConfigurations
ADD ProviderGovernancePolicyId BIGINT NULL,
    ProviderCapability TINYINT NOT NULL
        CONSTRAINT FundingPlatform_DF_SemanticConfigurations_ProviderCapability DEFAULT (0);

ALTER TABLE dbo.FundingPlatform_SemanticConfigurations
ADD CONSTRAINT FundingPlatform_CK_SemanticConfigurations_GovernedProvider CHECK
    ((IsLocalFake = 1 AND ProviderGovernancePolicyId IS NULL AND ProviderCapability = 0)
     OR (IsLocalFake = 0 AND ProviderGovernancePolicyId IS NOT NULL
         AND ProviderCapability = 0)),
    CONSTRAINT FundingPlatform_FK_SemanticConfigurations_GovernedProvider
        FOREIGN KEY (ProviderGovernancePolicyId, ProviderCode, ModelCode, ProviderCapability)
        REFERENCES dbo.FundingPlatform_AiProviderGovernancePolicies
            (Id, ProviderCode, ModelCode, Capability);

CREATE TABLE dbo.FundingPlatform_SemanticConfigurationPublishRequests
(
    UserId BIGINT NOT NULL,
    IdempotencyKeyHash BINARY(32) NOT NULL,
    RequestHash BINARY(32) NOT NULL,
    SemanticConfigurationId INT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_SemanticConfigurationPublishRequests
        PRIMARY KEY (UserId, IdempotencyKeyHash),
    CONSTRAINT FundingPlatform_FK_SemanticConfigurationPublishRequests_User
        FOREIGN KEY (UserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_SemanticConfigurationPublishRequests_Configuration
        FOREIGN KEY (SemanticConfigurationId)
        REFERENCES dbo.FundingPlatform_SemanticConfigurations (Id)
);
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_AiProviderGovernancePolicyState
(
    @ProviderGovernancePolicyId BIGINT
)
RETURNS TABLE
AS
RETURN
(
    SELECT policies.Id,
           CONVERT(BINARY(32), HASHBYTES
           (
               'SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
               (
                   policies.Code, N'|', policies.Version, N'|',
                   policies.ProviderCode, N'|', policies.ModelCode, N'|',
                   policies.Capability, N'|', policies.EndpointOrigin, N'|',
                   policies.RetentionMode, N'|', policies.MaximumProviderRetentionDays, N'|',
                   policies.DataResidencyCode, N'|',
                   CONVERT(VARCHAR(64), policies.DpaReferenceHash, 2), N'|',
                   CONVERT(VARCHAR(64), policies.TermsSnapshotHash, 2), N'|',
                   policies.InputTokenCostUsdPerMillion, N'|',
                   policies.OutputTokenCostUsdPerMillion, N'|',
                   policies.ExternalProcessingAllowed, N'|',
                   CONVERT(NVARCHAR(33), policies.ApprovedAtUtc, 126), N'|',
                   CONVERT(NVARCHAR(33), policies.ExpiresAtUtc, 126)
               ))
           )) AS CalculatedFingerprint
    FROM dbo.FundingPlatform_AiProviderGovernancePolicies AS policies
    WHERE policies.Id = @ProviderGovernancePolicyId
);
GO

/* Preserve every 021 fake fingerprint byte-for-byte. Real configurations bind
   the exact immutable governance policy into their content address. */
CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_SemanticConfigurationState
(
    @SemanticConfigurationId INT
)
RETURNS TABLE
AS
RETURN
(
    SELECT configurations.Id,
           CONVERT(BINARY(32), HASHBYTES
           (
               'SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
               (
                   configurations.Code, N'|', configurations.Version, N'|',
                   configurations.ProviderCode, N'|', configurations.ModelCode, N'|',
                   configurations.Dimensions, N'|', configurations.PurposeCode, N'|',
                   configurations.ProjectTemplateVersion, N'|',
                   configurations.OpportunityTemplateVersion, N'|',
                   configurations.NormalizationVersion, N'|',
                   configurations.DistanceMetric, N'|', configurations.CalibrationVersion, N'|',
                   configurations.MaximumInputUtf8Bytes, N'|',
                   configurations.MaximumBatchSize, N'|', configurations.MaximumAttempts, N'|',
                   configurations.MaximumCostUsdPerEmbedding, N'|',
                   configurations.MonthlyBudgetUsd, N'|', configurations.IsLocalFake,
                   CASE WHEN configurations.IsLocalFake = 0 THEN CONCAT
                   (
                       N'|', configurations.ProviderCapability, N'|',
                       CONVERT(VARCHAR(64), policies.PolicyFingerprint, 2)
                   ) ELSE N'' END
               ))
           )) AS CalculatedFingerprint
    FROM dbo.FundingPlatform_SemanticConfigurations AS configurations
    LEFT JOIN dbo.FundingPlatform_AiProviderGovernancePolicies AS policies
        ON policies.Id = configurations.ProviderGovernancePolicyId
    WHERE configurations.Id = @SemanticConfigurationId
);
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_AiProviderGovernancePolicies_Immutable
ON dbo.FundingPlatform_AiProviderGovernancePolicies
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS
       (SELECT 1 FROM inserted
        OUTER APPLY dbo.FundingPlatform_ifn_AiProviderGovernancePolicyState(inserted.Id) AS state
        WHERE state.Id IS NULL OR inserted.PolicyFingerprint <> state.CalculatedFingerprint)
        THROW 54203, N'AI provider governance fingerprint must match all frozen fields.', 1;
    IF EXISTS (SELECT 1 FROM deleted WHERE NOT EXISTS
               (SELECT 1 FROM inserted WHERE inserted.Id = deleted.Id))
       OR EXISTS
          (SELECT 1 FROM inserted INNER JOIN deleted ON deleted.Id = inserted.Id
           WHERE inserted.PublicId <> deleted.PublicId
              OR inserted.Code COLLATE Latin1_General_100_BIN2 <>
                 deleted.Code COLLATE Latin1_General_100_BIN2
              OR inserted.Version <> deleted.Version
              OR inserted.ProviderCode COLLATE Latin1_General_100_BIN2 <>
                 deleted.ProviderCode COLLATE Latin1_General_100_BIN2
              OR inserted.ModelCode COLLATE Latin1_General_100_BIN2 <>
                 deleted.ModelCode COLLATE Latin1_General_100_BIN2
              OR inserted.Capability <> deleted.Capability
              OR inserted.EndpointOrigin COLLATE Latin1_General_100_BIN2 <>
                 deleted.EndpointOrigin COLLATE Latin1_General_100_BIN2
              OR inserted.RetentionMode <> deleted.RetentionMode
              OR inserted.MaximumProviderRetentionDays <> deleted.MaximumProviderRetentionDays
              OR inserted.DataResidencyCode COLLATE Latin1_General_100_BIN2 <>
                 deleted.DataResidencyCode COLLATE Latin1_General_100_BIN2
              OR inserted.DpaReferenceHash <> deleted.DpaReferenceHash
              OR inserted.TermsSnapshotHash <> deleted.TermsSnapshotHash
              OR inserted.InputTokenCostUsdPerMillion <> deleted.InputTokenCostUsdPerMillion
              OR inserted.OutputTokenCostUsdPerMillion <> deleted.OutputTokenCostUsdPerMillion
              OR inserted.PolicyFingerprint <> deleted.PolicyFingerprint
              OR inserted.ExternalProcessingAllowed <> deleted.ExternalProcessingAllowed
              OR inserted.ApprovedByUserId <> deleted.ApprovedByUserId
              OR inserted.ApprovedAtUtc <> deleted.ApprovedAtUtc
              OR inserted.ExpiresAtUtc <> deleted.ExpiresAtUtc
              OR inserted.CreatedAtUtc <> deleted.CreatedAtUtc
              OR (deleted.IsActive = 0 AND inserted.IsActive = 1))
        THROW 54204, N'Published AI provider governance is immutable and cannot be reactivated.', 1;
    IF EXISTS
       (SELECT 1 FROM inserted INNER JOIN deleted ON deleted.Id = inserted.Id
        WHERE deleted.IsActive = 1 AND inserted.IsActive = 0
          AND EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_SemanticConfigurations AS configurations
               WHERE configurations.ProviderGovernancePolicyId = inserted.Id
                 AND configurations.IsActive = 1))
        THROW 54205, N'Governance used by an active semantic configuration cannot be disabled.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticConfigurations_Immutable
ON dbo.FundingPlatform_SemanticConfigurations
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS
       (SELECT 1
        FROM inserted
        OUTER APPLY dbo.FundingPlatform_ifn_SemanticConfigurationState(inserted.Id) AS state
        WHERE state.Id IS NULL OR inserted.ConfigurationFingerprint <> state.CalculatedFingerprint)
        THROW 54103, N'Semantic configuration fingerprint must match every frozen field.', 1;
    IF EXISTS (SELECT 1 FROM deleted WHERE NOT EXISTS
               (SELECT 1 FROM inserted WHERE inserted.Id = deleted.Id))
       OR EXISTS
          (SELECT 1
           FROM inserted
           INNER JOIN deleted ON deleted.Id = inserted.Id
           WHERE inserted.PublicId <> deleted.PublicId OR inserted.Code <> deleted.Code
              OR inserted.Version <> deleted.Version
              OR inserted.ProviderCode <> deleted.ProviderCode
              OR inserted.ModelCode <> deleted.ModelCode
              OR inserted.ProviderGovernancePolicyId <> deleted.ProviderGovernancePolicyId
              OR (inserted.ProviderGovernancePolicyId IS NULL
                  AND deleted.ProviderGovernancePolicyId IS NOT NULL)
              OR (inserted.ProviderGovernancePolicyId IS NOT NULL
                  AND deleted.ProviderGovernancePolicyId IS NULL)
              OR inserted.ProviderCapability <> deleted.ProviderCapability
              OR inserted.Dimensions <> deleted.Dimensions
              OR inserted.PurposeCode <> deleted.PurposeCode
              OR inserted.ProjectTemplateVersion <> deleted.ProjectTemplateVersion
              OR inserted.OpportunityTemplateVersion <> deleted.OpportunityTemplateVersion
              OR inserted.NormalizationVersion <> deleted.NormalizationVersion
              OR inserted.DistanceMetric <> deleted.DistanceMetric
              OR inserted.CalibrationVersion <> deleted.CalibrationVersion
              OR inserted.MaximumInputUtf8Bytes <> deleted.MaximumInputUtf8Bytes
              OR inserted.MaximumBatchSize <> deleted.MaximumBatchSize
              OR inserted.MaximumAttempts <> deleted.MaximumAttempts
              OR inserted.MaximumCostUsdPerEmbedding <> deleted.MaximumCostUsdPerEmbedding
              OR inserted.MonthlyBudgetUsd <> deleted.MonthlyBudgetUsd
              OR inserted.ConfigurationFingerprint <> deleted.ConfigurationFingerprint
              OR inserted.IsLocalFake <> deleted.IsLocalFake
              OR inserted.PublishedAtUtc <> deleted.PublishedAtUtc
              OR inserted.CreatedAtUtc <> deleted.CreatedAtUtc
              OR (deleted.IsActive = 0 AND inserted.IsActive = 1))
        THROW 54102, N'Published semantic configuration is immutable and cannot be reactivated.', 1;
    IF EXISTS
       (SELECT 1
        FROM inserted INNER JOIN deleted ON deleted.Id = inserted.Id
        WHERE deleted.IsActive = 1 AND inserted.IsActive = 0
          AND (EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
              WHERE jobs.SemanticConfigurationId = inserted.Id AND jobs.Status IN (0, 1, 3))
           OR EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationRuns AS runs
              WHERE runs.SemanticConfigurationId = inserted.Id AND runs.Status IN (0, 1, 3))
           OR EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_SemanticBudgetReservations AS reservations
              WHERE reservations.SemanticConfigurationId = inserted.Id AND reservations.Status = 0)))
        THROW 54104, N'Active semantic work must finish before configuration deactivation.', 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AiEmbeddingProviderPolicy_AdminRegister
    @SuperAdminUserPublicId UNIQUEIDENTIFIER,
    @Code NVARCHAR(50),
    @Version INT,
    @ModelCode NVARCHAR(128),
    @EndpointOrigin NVARCHAR(200),
    @DataResidencyCode NVARCHAR(16),
    @DpaReferenceHash BINARY(32),
    @TermsSnapshotHash BINARY(32),
    @InputTokenCostUsdPerMillion DECIMAL(19,6),
    @ApprovedAtUtc DATETIME2(3),
    @ExpiresAtUtc DATETIME2(3),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF @SuperAdminUserPublicId IS NULL OR @NowUtc IS NULL
       OR @Code IS NULL OR @Version < 1
       OR @ModelCode NOT IN (N'text-embedding-3-small', N'text-embedding-3-large')
       OR @EndpointOrigin NOT IN
          (N'https://api.openai.com', N'https://us.api.openai.com',
           N'https://eu.api.openai.com', N'https://au.api.openai.com',
           N'https://ca.api.openai.com', N'https://jp.api.openai.com',
           N'https://in.api.openai.com', N'https://sg.api.openai.com', N'https://kr.api.openai.com',
           N'https://gb.api.openai.com', N'https://ae.api.openai.com')
       OR @DataResidencyCode NOT IN
          (N'global', N'us', N'eu', N'au', N'ca', N'jp', N'in', N'sg', N'kr', N'gb', N'ae')
       OR NOT
          ((@DataResidencyCode COLLATE Latin1_General_100_BIN2 =
                N'global' COLLATE Latin1_General_100_BIN2
            AND @EndpointOrigin COLLATE Latin1_General_100_BIN2 =
                N'https://api.openai.com' COLLATE Latin1_General_100_BIN2)
           OR @EndpointOrigin COLLATE Latin1_General_100_BIN2 =
              CONCAT(N'https://', @DataResidencyCode, N'.api.openai.com')
                COLLATE Latin1_General_100_BIN2)
       OR @DpaReferenceHash IS NULL OR DATALENGTH(@DpaReferenceHash) <> 32
       OR @TermsSnapshotHash IS NULL OR DATALENGTH(@TermsSnapshotHash) <> 32
       OR @InputTokenCostUsdPerMillion NOT BETWEEN 0 AND 1000
       OR @ApprovedAtUtc IS NULL OR @ApprovedAtUtc > @NowUtc
       OR @ExpiresAtUtc <= @NowUtc OR @ExpiresAtUtc > DATEADD(YEAR, 2, @NowUtc)
       OR @IdempotencyKeyHash IS NULL OR DATALENGTH(@IdempotencyKeyHash) <> 32
       OR @RequestHash IS NULL OR DATALENGTH(@RequestHash) <> 32
        THROW 54206, N'Complete bounded AI provider governance metadata is required.', 1;

    DECLARE @UserId BIGINT, @PolicyId BIGINT, @StoredHash BINARY(32), @WasReplay BIT = 0;
    DECLARE @Fingerprint BINARY(32) = CONVERT(BINARY(32), HASHBYTES
    (
        'SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
        (
            @Code, N'|', @Version, N'|', N'openai', N'|', @ModelCode, N'|',
            0, N'|', @EndpointOrigin, N'|', 2, N'|', 0, N'|',
            @DataResidencyCode, N'|', CONVERT(VARCHAR(64), @DpaReferenceHash, 2), N'|',
            CONVERT(VARCHAR(64), @TermsSnapshotHash, 2), N'|',
            @InputTokenCostUsdPerMillion, N'|', CONVERT(DECIMAL(19,6), 0), N'|',
            1, N'|', CONVERT(NVARCHAR(33), @ApprovedAtUtc, 126), N'|',
            CONVERT(NVARCHAR(33), @ExpiresAtUtc, 126)
        ))
    ));
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    IF @InitialTransactionCount = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE SAVE TRANSACTION FP_AiPolicyRegister;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId = @SuperAdminUserPublicId, @ActorUserId = @UserId OUTPUT;
        IF NOT EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_UserRoles AS userRoles
            INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
            WHERE userRoles.UserId = @UserId AND roles.NormalizedName = N'SUPERADMIN')
            THROW 54207, N'Active SuperAdmin role with MFA is required.', 1;

        SELECT @PolicyId = requests.ProviderGovernancePolicyId,
               @StoredHash = requests.RequestHash
        FROM dbo.FundingPlatform_AiProviderGovernancePolicyRequests AS requests
             WITH (UPDLOCK, HOLDLOCK)
        WHERE requests.UserId = @UserId AND requests.IdempotencyKeyHash = @IdempotencyKeyHash;
        IF @PolicyId IS NOT NULL
        BEGIN
            IF @StoredHash <> @RequestHash
                THROW 54208, N'Idempotency key was used for another governance request.', 1;
            SET @WasReplay = 1;
        END
        ELSE
        BEGIN
            INSERT INTO dbo.FundingPlatform_AiProviderGovernancePolicies
                (Code, Version, ProviderCode, ModelCode, Capability, EndpointOrigin,
                 RetentionMode, MaximumProviderRetentionDays, DataResidencyCode,
                 DpaReferenceHash, TermsSnapshotHash, InputTokenCostUsdPerMillion,
                 OutputTokenCostUsdPerMillion, PolicyFingerprint,
                 ExternalProcessingAllowed, IsActive, ApprovedByUserId,
                 ApprovedAtUtc, ExpiresAtUtc, CreatedAtUtc)
            VALUES
                (@Code, @Version, N'openai', @ModelCode, 0, @EndpointOrigin,
                 2, 0, @DataResidencyCode, @DpaReferenceHash, @TermsSnapshotHash,
                 @InputTokenCostUsdPerMillion, 0, @Fingerprint,
                 1, 1, @UserId, @ApprovedAtUtc, @ExpiresAtUtc, @NowUtc);
            SET @PolicyId = SCOPE_IDENTITY();
            INSERT INTO dbo.FundingPlatform_AiProviderGovernancePolicyRequests
                (UserId, IdempotencyKeyHash, RequestHash,
                 ProviderGovernancePolicyId, CreatedAtUtc)
            VALUES (@UserId, @IdempotencyKeyHash, @RequestHash, @PolicyId, @NowUtc);
        END;
        IF @StartedTransaction = 1 COMMIT TRANSACTION;
        SELECT CONVERT(BIT, 1) AS Succeeded,
               CASE WHEN @WasReplay = 1 THEN N'replayed' ELSE N'published' END AS Code,
               @WasReplay AS WasReplay, policies.PublicId,
               CONCAT(policies.Code, N'-v', policies.Version) AS PolicyVersion,
               policies.ProviderCode, policies.ModelCode, policies.EndpointOrigin,
               policies.RetentionMode, policies.MaximumProviderRetentionDays,
               policies.DataResidencyCode, policies.PolicyFingerprint,
               policies.InputTokenCostUsdPerMillion,
               policies.ExternalProcessingAllowed, policies.IsActive,
               policies.ApprovedAtUtc, policies.ExpiresAtUtc
        FROM dbo.FundingPlatform_AiProviderGovernancePolicies AS policies
        WHERE policies.Id = @PolicyId;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_AiPolicyRegister;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SemanticConfiguration_AdminPublishOpenAi
    @SuperAdminUserPublicId UNIQUEIDENTIFIER,
    @ProviderPolicyPublicId UNIQUEIDENTIFIER,
    @Code NVARCHAR(50),
    @Version INT,
    @MaximumBatchSize TINYINT,
    @MaximumCostUsdPerEmbedding DECIMAL(19,6),
    @MonthlyBudgetUsd DECIMAL(19,6),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF @SuperAdminUserPublicId IS NULL OR @ProviderPolicyPublicId IS NULL
       OR @Code IS NULL OR @Version < 1 OR @MaximumBatchSize NOT BETWEEN 1 AND 64
       OR @MaximumCostUsdPerEmbedding NOT BETWEEN 0.000001 AND 1
       OR @MonthlyBudgetUsd NOT BETWEEN @MaximumCostUsdPerEmbedding AND 10000
       OR @IdempotencyKeyHash IS NULL OR DATALENGTH(@IdempotencyKeyHash) <> 32
       OR @RequestHash IS NULL OR DATALENGTH(@RequestHash) <> 32 OR @NowUtc IS NULL
        THROW 54209, N'Complete bounded semantic configuration metadata is required.', 1;

    DECLARE @UserId BIGINT, @PolicyId BIGINT, @Provider NVARCHAR(50), @Model NVARCHAR(128);
    DECLARE @InputPrice DECIMAL(19,6), @ConfigurationId INT, @StoredHash BINARY(32);
    DECLARE @WasReplay BIT = 0, @Fingerprint BINARY(32), @ProviderPolicyFingerprint BINARY(32);
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    IF @InitialTransactionCount = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE SAVE TRANSACTION FP_AiConfigPublish;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId = @SuperAdminUserPublicId, @ActorUserId = @UserId OUTPUT;
        IF NOT EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_UserRoles AS userRoles
            INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
            WHERE userRoles.UserId = @UserId AND roles.NormalizedName = N'SUPERADMIN')
            THROW 54207, N'Active SuperAdmin role with MFA is required.', 1;

        SELECT @ConfigurationId = requests.SemanticConfigurationId,
               @StoredHash = requests.RequestHash
        FROM dbo.FundingPlatform_SemanticConfigurationPublishRequests AS requests
             WITH (UPDLOCK, HOLDLOCK)
        WHERE requests.UserId = @UserId AND requests.IdempotencyKeyHash = @IdempotencyKeyHash;
        IF @ConfigurationId IS NOT NULL
        BEGIN
            IF @StoredHash <> @RequestHash
                THROW 54210, N'Idempotency key was used for another configuration request.', 1;
            SET @WasReplay = 1;
        END
        ELSE
        BEGIN
            SELECT @PolicyId = policies.Id, @Provider = policies.ProviderCode,
                   @Model = policies.ModelCode,
                   @InputPrice = policies.InputTokenCostUsdPerMillion,
                   @ProviderPolicyFingerprint = policies.PolicyFingerprint
            FROM dbo.FundingPlatform_AiProviderGovernancePolicies AS policies
                 WITH (UPDLOCK, HOLDLOCK)
            CROSS APPLY dbo.FundingPlatform_ifn_AiProviderGovernancePolicyState(policies.Id) AS state
            WHERE policies.PublicId = @ProviderPolicyPublicId
              AND policies.Capability = 0 AND policies.IsActive = 1
              AND policies.ExternalProcessingAllowed = 1
              AND policies.RetentionMode = 2 AND policies.MaximumProviderRetentionDays = 0
              AND policies.ApprovedAtUtc <= @NowUtc AND policies.ExpiresAtUtc > @NowUtc
              AND policies.PolicyFingerprint = state.CalculatedFingerprint;
            IF @PolicyId IS NULL
                THROW 54211, N'Active exact provider governance policy was not found.', 1;
            DECLARE @WorstCost DECIMAL(19,6) =
                CEILING((8192 * @InputPrice / 1000000.0) * 1000000.0) / 1000000.0;
            IF @MaximumCostUsdPerEmbedding < @WorstCost
                THROW 54212, N'Maximum embedding cost is below the approved worst case.', 1;

            IF EXISTS
               (SELECT 1 FROM dbo.FundingPlatform_SemanticConfigurations AS configurations
                WHERE configurations.IsActive = 1
                  AND (EXISTS
                       (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
                        WHERE jobs.SemanticConfigurationId = configurations.Id
                          AND jobs.Status IN (0, 1, 3))
                       OR EXISTS
                       (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationRuns AS runs
                        WHERE runs.SemanticConfigurationId = configurations.Id
                          AND runs.Status IN (0, 1, 3))))
                THROW 54213, N'Active semantic work must finish before configuration replacement.', 1;
            UPDATE dbo.FundingPlatform_SemanticConfigurations
            SET IsActive = 0 WHERE IsActive = 1;

            SET @Fingerprint = CONVERT(BINARY(32), HASHBYTES
            (
                'SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
                (
                    @Code, N'|', @Version, N'|', @Provider, N'|', @Model, N'|',
                    1536, N'|', N'matching', N'|', N'project-semantic-v1', N'|',
                    N'opportunity-semantic-v1', N'|', N'semantic-text-v1', N'|',
                    1, N'|', N'cosine-linear-shadow-v1', N'|', 8192, N'|',
                    @MaximumBatchSize, N'|', 3, N'|', @MaximumCostUsdPerEmbedding,
                    N'|', @MonthlyBudgetUsd, N'|', 0, N'|', 0, N'|',
                    CONVERT(VARCHAR(64), @ProviderPolicyFingerprint, 2)
                ))
            ));
            INSERT INTO dbo.FundingPlatform_SemanticConfigurations
                (Code, Version, ProviderCode, ModelCode, Dimensions, PurposeCode,
                 ProjectTemplateVersion, OpportunityTemplateVersion, NormalizationVersion,
                 DistanceMetric, CalibrationVersion, MaximumInputUtf8Bytes,
                 MaximumBatchSize, MaximumAttempts, MaximumCostUsdPerEmbedding,
                 MonthlyBudgetUsd, ConfigurationFingerprint, IsLocalFake, IsActive,
                 PublishedAtUtc, CreatedAtUtc, ProviderGovernancePolicyId, ProviderCapability)
            VALUES
                (@Code, @Version, @Provider, @Model, 1536, N'matching',
                 N'project-semantic-v1', N'opportunity-semantic-v1', N'semantic-text-v1',
                 1, N'cosine-linear-shadow-v1', 8192, @MaximumBatchSize, 3,
                 @MaximumCostUsdPerEmbedding, @MonthlyBudgetUsd, @Fingerprint,
                 0, 1, @NowUtc, @NowUtc, @PolicyId, 0);
            SET @ConfigurationId = SCOPE_IDENTITY();
            INSERT INTO dbo.FundingPlatform_SemanticConfigurationPublishRequests
                (UserId, IdempotencyKeyHash, RequestHash, SemanticConfigurationId, CreatedAtUtc)
            VALUES (@UserId, @IdempotencyKeyHash, @RequestHash, @ConfigurationId, @NowUtc);
        END;
        IF @StartedTransaction = 1 COMMIT TRANSACTION;
        SELECT CONVERT(BIT, 1) AS Succeeded,
               CASE WHEN @WasReplay = 1 THEN N'replayed' ELSE N'published' END AS Code,
               @WasReplay AS WasReplay, configurations.PublicId,
               CONCAT(configurations.Code, N'-v', configurations.Version) AS ConfigurationVersion,
               policies.PublicId AS ProviderPolicyPublicId,
               policies.PolicyFingerprint AS ProviderPolicyFingerprint,
               configurations.ProviderCode, configurations.ModelCode,
               configurations.Dimensions, configurations.MaximumBatchSize,
               configurations.MaximumCostUsdPerEmbedding,
               configurations.MonthlyBudgetUsd, configurations.IsActive,
               configurations.PublishedAtUtc
        FROM dbo.FundingPlatform_SemanticConfigurations AS configurations
        INNER JOIN dbo.FundingPlatform_AiProviderGovernancePolicies AS policies
            ON policies.Id = configurations.ProviderGovernancePolicyId
        WHERE configurations.Id = @ConfigurationId;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_AiConfigPublish;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SemanticEmbeddingJob_GetInput
    @JobPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @JobPublicId IS NULL OR @LeaseId IS NULL OR @NowUtc IS NULL
        THROW 54110, N'Embedding job lease identity is required.', 1;
    DECLARE @JobId BIGINT, @SubjectType TINYINT, @SubjectPublicId UNIQUEIDENTIFIER;
    DECLARE @SubjectVersion INT, @SnapshotJson NVARCHAR(MAX), @ExpectedHash BINARY(32);
    DECLARE @PurposeCode NVARCHAR(32), @MaximumInputBytes SMALLINT, @ConfigValid BIT;
    DECLARE @ReservationId BIGINT, @ReservationExpiresAtUtc DATETIME2(3);
    DECLARE @IsLocalFake BIT, @PolicyPublicId UNIQUEIDENTIFIER, @PolicyVersion NVARCHAR(64);
    DECLARE @PolicyFingerprint BINARY(32), @EndpointOrigin NVARCHAR(200);
    DECLARE @ProviderCapability TINYINT, @RetentionMode TINYINT, @MaximumRetentionDays SMALLINT;
    DECLARE @DataResidencyCode NVARCHAR(16), @InputTokenPrice DECIMAL(19,6);
    DECLARE @OutputTokenPrice DECIMAL(19,6);
    DECLARE @PolicyApprovedAtUtc DATETIME2(3), @PolicyExpiresAtUtc DATETIME2(3);
    DECLARE @ExternalProcessingAllowed BIT;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @Started BIT = 0;
    IF @InitialTransactionCount = 0 BEGIN BEGIN TRANSACTION; SET @Started = 1; END
    ELSE SAVE TRANSACTION FP_SemanticGetInput;
    BEGIN TRY
        SELECT @JobId = jobs.Id, @SubjectType = jobs.SubjectType,
               @SubjectPublicId = CASE jobs.SubjectType WHEN 0 THEN projects.PublicId
                                                       ELSE opportunities.PublicId END,
               @SubjectVersion = CASE jobs.SubjectType WHEN 0 THEN jobs.ProjectVersion
                                                      ELSE jobs.FundingContentVersion END,
               @SnapshotJson = CASE jobs.SubjectType WHEN 0 THEN projectVersions.SnapshotJson
                                                    ELSE opportunityVersions.SnapshotJson END,
               @ExpectedHash = jobs.InputContentHash,
               @PurposeCode = configurations.PurposeCode,
               @MaximumInputBytes = configurations.MaximumInputUtf8Bytes,
               @IsLocalFake = configurations.IsLocalFake,
               @PolicyPublicId = policies.PublicId,
               @PolicyVersion = CONCAT(policies.Code, N'-v', policies.Version),
               @PolicyFingerprint = policies.PolicyFingerprint,
               @ProviderCapability = policies.Capability,
               @EndpointOrigin = policies.EndpointOrigin,
               @RetentionMode = policies.RetentionMode,
               @MaximumRetentionDays = policies.MaximumProviderRetentionDays,
               @DataResidencyCode = policies.DataResidencyCode,
               @InputTokenPrice = policies.InputTokenCostUsdPerMillion,
               @OutputTokenPrice = policies.OutputTokenCostUsdPerMillion,
               @PolicyApprovedAtUtc = policies.ApprovedAtUtc,
               @PolicyExpiresAtUtc = policies.ExpiresAtUtc,
               @ExternalProcessingAllowed = policies.ExternalProcessingAllowed,
               @ConfigValid = CASE
                   WHEN configurations.IsActive <> 1
                     OR configurations.ConfigurationFingerprint <> configState.CalculatedFingerprint
                     THEN 0
                   WHEN configurations.IsLocalFake = 1
                     AND configurations.ProviderGovernancePolicyId IS NULL THEN 1
                   WHEN configurations.IsLocalFake = 0
                     AND policies.Id IS NOT NULL AND policies.IsActive = 1
                     AND policies.ExternalProcessingAllowed = 1
                     AND policies.RetentionMode = 2
                     AND policies.MaximumProviderRetentionDays = 0
                     AND policies.ApprovedAtUtc <= @NowUtc AND policies.ExpiresAtUtc > @NowUtc
                     AND policies.PolicyFingerprint = policyState.CalculatedFingerprint THEN 1
                   ELSE 0 END
        FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_SemanticConfigurations AS configurations WITH (HOLDLOCK)
            ON configurations.Id = jobs.SemanticConfigurationId
           AND configurations.Version = jobs.SemanticConfigurationVersion
        CROSS APPLY dbo.FundingPlatform_ifn_SemanticConfigurationState(configurations.Id)
            AS configState
        LEFT JOIN dbo.FundingPlatform_AiProviderGovernancePolicies AS policies WITH (HOLDLOCK)
            ON policies.Id = configurations.ProviderGovernancePolicyId
           AND policies.ProviderCode = configurations.ProviderCode
           AND policies.ModelCode = configurations.ModelCode
           AND policies.Capability = configurations.ProviderCapability
        OUTER APPLY dbo.FundingPlatform_ifn_AiProviderGovernancePolicyState(policies.Id)
            AS policyState
        LEFT JOIN dbo.FundingPlatform_Projects AS projects ON projects.Id = jobs.ProjectId
        LEFT JOIN dbo.FundingPlatform_ProjectVersions AS projectVersions
            ON projectVersions.ProjectId = jobs.ProjectId
           AND projectVersions.ProjectVersion = jobs.ProjectVersion
        LEFT JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
            ON opportunities.Id = jobs.FundingOpportunityId
        LEFT JOIN dbo.FundingPlatform_FundingOpportunityVersions AS opportunityVersions
            ON opportunityVersions.FundingOpportunityId = jobs.FundingOpportunityId
           AND opportunityVersions.ContentVersion = jobs.FundingContentVersion
        WHERE jobs.PublicId = @JobPublicId AND jobs.Status = 1
          AND jobs.LeaseId = @LeaseId AND jobs.LeaseUntilUtc > @NowUtc;
        IF @JobId IS NULL
        BEGIN IF @Started = 1 COMMIT TRANSACTION; RETURN; END;
        SELECT @ReservationId = Id, @ReservationExpiresAtUtc = ExpiresAtUtc
        FROM dbo.FundingPlatform_SemanticBudgetReservations WITH (UPDLOCK, HOLDLOCK)
        WHERE EmbeddingJobId = @JobId AND LeaseId = @LeaseId AND Status = 0;

        DECLARE @CanonicalInputJson NVARCHAR(MAX) = CASE @SubjectType
            WHEN 0 THEN dbo.FundingPlatform_fn_ProjectSemanticCanonicalInput(@SnapshotJson)
            ELSE dbo.FundingPlatform_fn_OpportunitySemanticCanonicalInput(@SnapshotJson) END;
        DECLARE @RiskCode NVARCHAR(50) =
            dbo.FundingPlatform_fn_SemanticInputRiskCode(@CanonicalInputJson, @MaximumInputBytes);
        DECLARE @FailureCode NVARCHAR(50) = CASE
            WHEN @ConfigValid <> 1 OR @ReservationId IS NULL
                 OR @ReservationExpiresAtUtc <= @NowUtc OR @SnapshotJson IS NULL
                THEN N'stale-subject'
            WHEN @RiskCode IS NOT NULL THEN @RiskCode
            WHEN dbo.FundingPlatform_fn_SemanticInputHash(@CanonicalInputJson) <> @ExpectedHash
                THEN N'semantic-input-hash-mismatch' END;
        IF @FailureCode IS NOT NULL
        BEGIN
            UPDATE dbo.FundingPlatform_SemanticEmbeddingJobs
            SET Status = CASE WHEN @FailureCode = N'stale-subject' THEN 5 ELSE 4 END,
                LeaseId = NULL, LeaseOwnerHash = NULL, LeaseUntilUtc = NULL,
                ErrorCode = @FailureCode, CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc
            WHERE Id = @JobId;
            UPDATE dbo.FundingPlatform_SemanticBudgetReservations
            SET Status = 2, FinalizedAtUtc = @NowUtc
            WHERE Id = @ReservationId AND Status = 0;
            IF @Started = 1 COMMIT TRANSACTION;
            RETURN;
        END;
        IF @Started = 1 COMMIT TRANSACTION;
        SELECT @JobPublicId AS JobPublicId, @LeaseId AS LeaseId,
               @SubjectType AS SubjectType, @SubjectPublicId AS SubjectPublicId,
               @SubjectVersion AS SubjectVersion, @PurposeCode AS PurposeCode,
               @CanonicalInputJson AS CanonicalText, @ExpectedHash AS InputContentHash,
               CASE WHEN @IsLocalFake = 1 THEN NULL ELSE @PolicyPublicId END
                    AS ProviderPolicyPublicId,
               CASE WHEN @IsLocalFake = 1 THEN NULL ELSE @PolicyVersion END
                    AS ProviderPolicyVersion,
               CASE WHEN @IsLocalFake = 1 THEN NULL ELSE @PolicyFingerprint END
                    AS ProviderPolicyFingerprint,
               CASE WHEN @IsLocalFake = 1 THEN NULL ELSE @ProviderCapability END
                    AS ProviderCapability,
               CASE WHEN @IsLocalFake = 1 THEN NULL ELSE @EndpointOrigin END
                    AS ProviderEndpointOrigin,
               CASE WHEN @IsLocalFake = 1 THEN NULL ELSE @RetentionMode END AS RetentionMode,
               CASE WHEN @IsLocalFake = 1 THEN NULL ELSE @MaximumRetentionDays END
                    AS MaximumProviderRetentionDays,
               CASE WHEN @IsLocalFake = 1 THEN NULL ELSE @DataResidencyCode END
                    AS DataResidencyCode,
               CASE WHEN @IsLocalFake = 1 THEN NULL ELSE @InputTokenPrice END
                    AS InputTokenCostUsdPerMillion,
               CASE WHEN @IsLocalFake = 1 THEN NULL ELSE @OutputTokenPrice END
                    AS OutputTokenCostUsdPerMillion,
               CASE WHEN @IsLocalFake = 1 THEN NULL ELSE @PolicyApprovedAtUtc END AS ApprovedAtUtc,
               CASE WHEN @IsLocalFake = 1 THEN NULL ELSE @PolicyExpiresAtUtc END AS ExpiresAtUtc,
               CASE WHEN @IsLocalFake = 1 THEN NULL ELSE @ExternalProcessingAllowed END
                    AS ExternalProcessingAllowed;
    END TRY
    BEGIN CATCH
        IF @Started = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_SemanticGetInput;
        THROW;
    END CATCH;
END;
GO

GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_AiEmbeddingProviderPolicy_AdminRegister
    TO FundingPlatform_SemanticAdminRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SemanticConfiguration_AdminPublishOpenAi
    TO FundingPlatform_SemanticAdminRole;

DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiProviderGovernancePolicies
    TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiProviderGovernancePolicyRequests
    TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_SemanticConfigurationPublishRequests
    TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiProviderGovernancePolicies
    TO FundingPlatform_SemanticAdminRole;
DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiProviderGovernancePolicyRequests
    TO FundingPlatform_SemanticAdminRole;
DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_SemanticConfigurationPublishRequests
    TO FundingPlatform_SemanticAdminRole;
GO
