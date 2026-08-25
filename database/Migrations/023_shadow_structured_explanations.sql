/* FundingPlatform FASE 9B-B - governed Structured Outputs in admin-only shadow mode.
   Requires 022. No prompt, canonical input or raw provider response is persisted.
   Results never update 9A matching, 9B-A ranking or client-visible data. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_AiProviderGovernancePolicies', N'U') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_SemanticConfigurations',
                 N'ProviderGovernancePolicyId') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_SemanticEvaluationItems', N'U') IS NULL
    THROW 54401, N'FASE 9B-B structured explanations require migrations 021 and 022.', 1;

ALTER TABLE dbo.FundingPlatform_AiProviderGovernancePolicies
DROP CONSTRAINT FundingPlatform_CK_AiProviderGovernancePolicies_Contract;

ALTER TABLE dbo.FundingPlatform_AiProviderGovernancePolicies
ADD CONSTRAINT FundingPlatform_CK_AiProviderGovernancePolicies_Contract CHECK
(
    Version >= 1 AND Capability IN (0, 1, 2)
    AND RetentionMode IN (0, 1, 2)
    AND MaximumProviderRetentionDays BETWEEN 0 AND 30
    AND InputTokenCostUsdPerMillion BETWEEN 0 AND 1000
    AND OutputTokenCostUsdPerMillion BETWEEN 0 AND 1000
    AND ApprovedAtUtc <= CreatedAtUtc AND CreatedAtUtc < ExpiresAtUtc
    AND
    (
        ExternalProcessingAllowed = 0
        OR
        (
            ProviderCode COLLATE Latin1_General_100_BIN2 =
                N'openai' COLLATE Latin1_General_100_BIN2
            AND RetentionMode = 2 AND MaximumProviderRetentionDays = 0
            AND
            (
                (Capability = 0
                 AND ModelCode COLLATE Latin1_General_100_BIN2 IN
                     (N'text-embedding-3-small', N'text-embedding-3-large')
                 AND OutputTokenCostUsdPerMillion = 0)
                OR
                (Capability = 1
                 AND ModelCode COLLATE Latin1_General_100_BIN2 =
                     N'gpt-5.6-sol' COLLATE Latin1_General_100_BIN2
                 AND InputTokenCostUsdPerMillion > 0
                 AND OutputTokenCostUsdPerMillion > 0)
            )
        )
    )
);

CREATE TABLE dbo.FundingPlatform_AiExplanationConfigurations
(
    Id INT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_AiExplanationConfigurations_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    Code NVARCHAR(50) NOT NULL,
    Version INT NOT NULL,
    ProviderGovernancePolicyId BIGINT NOT NULL,
    ProviderCode NVARCHAR(50) NOT NULL,
    ModelCode NVARCHAR(128) NOT NULL,
    ProviderCapability TINYINT NOT NULL,
    InputSchemaVersion NVARCHAR(50) NOT NULL,
    OutputSchemaVersion NVARCHAR(50) NOT NULL,
    PromptVersion NVARCHAR(50) NOT NULL,
    PromptFingerprint BINARY(32) NOT NULL,
    ResponseSchemaFingerprint BINARY(32) NOT NULL,
    MaximumInputUtf8Bytes SMALLINT NOT NULL,
    MaximumOutputTokens SMALLINT NOT NULL,
    MaximumAttempts TINYINT NOT NULL,
    MaximumCostUsdPerResult DECIMAL(19,6) NOT NULL,
    MonthlyBudgetUsd DECIMAL(19,6) NOT NULL,
    ConfigurationFingerprint BINARY(32) NOT NULL,
    IsActive BIT NOT NULL,
    PublishedAtUtc DATETIME2(3) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_AiExplanationConfigurations PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_AiExplanationConfigurations_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_AiExplanationConfigurations_CodeVersion
        UNIQUE (Code, Version),
    CONSTRAINT FundingPlatform_UQ_AiExplanationConfigurations_IdVersion
        UNIQUE (Id, Version),
    CONSTRAINT FundingPlatform_UQ_AiExplanationConfigurations_IdIdentity
        UNIQUE (Id, ProviderCode, ModelCode, ProviderCapability),
    CONSTRAINT FundingPlatform_FK_AiExplanationConfigurations_Governance
        FOREIGN KEY (ProviderGovernancePolicyId, ProviderCode, ModelCode, ProviderCapability)
        REFERENCES dbo.FundingPlatform_AiProviderGovernancePolicies
            (Id, ProviderCode, ModelCode, Capability),
    CONSTRAINT FundingPlatform_CK_AiExplanationConfigurations_Contract CHECK
        (Version >= 1
         AND ProviderCapability = 1
         AND ProviderCode COLLATE Latin1_General_100_BIN2 =
             N'openai' COLLATE Latin1_General_100_BIN2
         AND ModelCode COLLATE Latin1_General_100_BIN2 =
             N'gpt-5.6-sol' COLLATE Latin1_General_100_BIN2
         AND InputSchemaVersion = N'explanation-input-v1'
         AND OutputSchemaVersion = N'explanation-output-v1'
         AND PromptVersion = N'explanation-review-es-v1'
         AND MaximumInputUtf8Bytes = 8192
         AND MaximumOutputTokens BETWEEN 128 AND 1024
         AND MaximumAttempts BETWEEN 1 AND 3
         AND MaximumCostUsdPerResult BETWEEN 0.000001 AND 1
         AND MonthlyBudgetUsd BETWEEN MaximumCostUsdPerResult AND 10000
         AND PublishedAtUtc = CreatedAtUtc),
    CONSTRAINT FundingPlatform_CK_AiExplanationConfigurations_Text CHECK
        (LEN(LTRIM(RTRIM(Code))) BETWEEN 1 AND 50
         AND LEN(CONCAT(Code, N'-v', Version)) <= 64
         AND Code NOT LIKE N'%[^a-z0-9._-]%' COLLATE Latin1_General_100_BIN2
         AND DATALENGTH(Code) = DATALENGTH(LTRIM(RTRIM(Code))))
);

CREATE UNIQUE INDEX FundingPlatform_UQ_AiExplanationConfigurations_Active
    ON dbo.FundingPlatform_AiExplanationConfigurations (IsActive)
    WHERE IsActive = 1;

CREATE TABLE dbo.FundingPlatform_AiExplanationConfigurationPublishRequests
(
    UserId BIGINT NOT NULL,
    IdempotencyKeyHash BINARY(32) NOT NULL,
    RequestHash BINARY(32) NOT NULL,
    AiExplanationConfigurationId INT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_AiExplanationConfigurationPublishRequests
        PRIMARY KEY (UserId, IdempotencyKeyHash),
    CONSTRAINT FundingPlatform_FK_AiExplanationConfigurationPublishRequests_User
        FOREIGN KEY (UserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_AiExplanationConfigurationPublishRequests_Config
        FOREIGN KEY (AiExplanationConfigurationId)
        REFERENCES dbo.FundingPlatform_AiExplanationConfigurations (Id)
);

CREATE TABLE dbo.FundingPlatform_AiExplanationRuns
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_AiExplanationRuns_PublicId DEFAULT (NEWSEQUENTIALID()),
    SourceSemanticEvaluationRunId BIGINT NOT NULL,
    AiExplanationConfigurationId INT NOT NULL,
    AiExplanationConfigurationVersion INT NOT NULL,
    ConfigurationFingerprint BINARY(32) NOT NULL,
    Status TINYINT NOT NULL,
    ItemCount SMALLINT NOT NULL,
    CompletedCount SMALLINT NOT NULL,
    FailedCount SMALLINT NOT NULL,
    TotalEstimatedCostUsd DECIMAL(19,6) NULL,
    RequestedByUserId BIGINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CompletedAtUtc DATETIME2(3) NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    ActiveSlot AS (CASE WHEN Status = 0 THEN CONVERT(TINYINT, 1) END) PERSISTED,
    CONSTRAINT FundingPlatform_PK_AiExplanationRuns PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_AiExplanationRuns_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_AiExplanationRuns_IdSource
        UNIQUE (Id, SourceSemanticEvaluationRunId),
    CONSTRAINT FundingPlatform_UQ_AiExplanationRuns_IdRequester
        UNIQUE (Id, RequestedByUserId),
    CONSTRAINT FundingPlatform_FK_AiExplanationRuns_Source
        FOREIGN KEY (SourceSemanticEvaluationRunId)
        REFERENCES dbo.FundingPlatform_SemanticEvaluationRuns (Id),
    CONSTRAINT FundingPlatform_FK_AiExplanationRuns_Config
        FOREIGN KEY (AiExplanationConfigurationId, AiExplanationConfigurationVersion)
        REFERENCES dbo.FundingPlatform_AiExplanationConfigurations (Id, Version),
    CONSTRAINT FundingPlatform_FK_AiExplanationRuns_Requester
        FOREIGN KEY (RequestedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    /* 0 processing, 2 completed, 4 permanent failed. */
    CONSTRAINT FundingPlatform_CK_AiExplanationRuns_Status CHECK (Status IN (0, 2, 4)),
    CONSTRAINT FundingPlatform_CK_AiExplanationRuns_Counts CHECK
        (ItemCount BETWEEN 1 AND 300
         AND CompletedCount BETWEEN 0 AND ItemCount
         AND FailedCount BETWEEN 0 AND ItemCount
         AND CompletedCount + FailedCount <= ItemCount),
    CONSTRAINT FundingPlatform_CK_AiExplanationRuns_Terminal CHECK
        ((Status = 0 AND CompletedAtUtc IS NULL AND TotalEstimatedCostUsd IS NULL)
         OR (Status IN (2, 4) AND CompletedAtUtc IS NOT NULL
             AND TotalEstimatedCostUsd BETWEEN 0 AND 10000
             AND CompletedCount + FailedCount = ItemCount)),
    CONSTRAINT FundingPlatform_CK_AiExplanationRuns_Time CHECK
        (UpdatedAtUtc >= CreatedAtUtc
         AND (CompletedAtUtc IS NULL OR CompletedAtUtc >= CreatedAtUtc))
);

CREATE UNIQUE INDEX FundingPlatform_UQ_AiExplanationRuns_Active
    ON dbo.FundingPlatform_AiExplanationRuns (ActiveSlot)
    WHERE ActiveSlot = 1;

CREATE TABLE dbo.FundingPlatform_AiExplanationRunRequests
(
    UserId BIGINT NOT NULL,
    IdempotencyKeyHash BINARY(32) NOT NULL,
    RequestHash BINARY(32) NOT NULL,
    AiExplanationRunId BIGINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_AiExplanationRunRequests
        PRIMARY KEY (UserId, IdempotencyKeyHash),
    CONSTRAINT FundingPlatform_FK_AiExplanationRunRequests_User
        FOREIGN KEY (UserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_AiExplanationRunRequests_RunRequester
        FOREIGN KEY (AiExplanationRunId, UserId)
        REFERENCES dbo.FundingPlatform_AiExplanationRuns (Id, RequestedByUserId)
);

CREATE TABLE dbo.FundingPlatform_AiExplanationJobs
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_AiExplanationJobs_PublicId DEFAULT (NEWSEQUENTIALID()),
    AiExplanationRunId BIGINT NOT NULL,
    SourceSemanticEvaluationRunId BIGINT NOT NULL,
    CaseOrdinal INT NOT NULL,
    InputContentHash BINARY(32) NOT NULL,
    Status TINYINT NOT NULL,
    LeaseId UNIQUEIDENTIFIER NULL,
    LeaseOwnerHash BINARY(32) NULL,
    LeaseUntilUtc DATETIME2(3) NULL,
    AttemptCount TINYINT NOT NULL,
    NextAttemptAtUtc DATETIME2(3) NOT NULL,
    ErrorCode NVARCHAR(50) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    CompletedAtUtc DATETIME2(3) NULL,
    CONSTRAINT FundingPlatform_PK_AiExplanationJobs PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_AiExplanationJobs_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_AiExplanationJobs_RunCase
        UNIQUE (AiExplanationRunId, CaseOrdinal),
    CONSTRAINT FundingPlatform_UQ_AiExplanationJobs_IdRun
        UNIQUE (Id, AiExplanationRunId),
    CONSTRAINT FundingPlatform_FK_AiExplanationJobs_RunSource
        FOREIGN KEY (AiExplanationRunId, SourceSemanticEvaluationRunId)
        REFERENCES dbo.FundingPlatform_AiExplanationRuns
            (Id, SourceSemanticEvaluationRunId),
    CONSTRAINT FundingPlatform_FK_AiExplanationJobs_SourceItem
        FOREIGN KEY (SourceSemanticEvaluationRunId, CaseOrdinal)
        REFERENCES dbo.FundingPlatform_SemanticEvaluationItems
            (SemanticEvaluationRunId, CaseOrdinal),
    /* 0 queued, 1 processing, 2 succeeded, 3 retry scheduled, 4 permanent failed. */
    CONSTRAINT FundingPlatform_CK_AiExplanationJobs_Status CHECK (Status BETWEEN 0 AND 4),
    CONSTRAINT FundingPlatform_CK_AiExplanationJobs_Lease CHECK
        ((Status = 1 AND LeaseId IS NOT NULL AND LeaseOwnerHash IS NOT NULL
                     AND LeaseUntilUtc IS NOT NULL)
         OR (Status <> 1 AND LeaseId IS NULL AND LeaseOwnerHash IS NULL
                         AND LeaseUntilUtc IS NULL)),
    CONSTRAINT FundingPlatform_CK_AiExplanationJobs_Terminal CHECK
        ((Status IN (2, 4) AND CompletedAtUtc IS NOT NULL)
         OR (Status IN (0, 1, 3) AND CompletedAtUtc IS NULL)),
    CONSTRAINT FundingPlatform_CK_AiExplanationJobs_Error CHECK
        ((Status IN (0, 1, 2) AND ErrorCode IS NULL)
         OR (Status IN (3, 4) AND ErrorCode IN
             (N'explanation-provider-unavailable', N'explanation-provider-throttled',
              N'explanation-provider-timeout', N'explanation-provider-invalid-response',
              N'explanation-input-invalid', N'explanation-configuration-invalid',
              N'budget-exhausted', N'lease-expired', N'internal-error'))),
    CONSTRAINT FundingPlatform_CK_AiExplanationJobs_Time CHECK
        (AttemptCount BETWEEN 0 AND 3 AND UpdatedAtUtc >= CreatedAtUtc
         AND (CompletedAtUtc IS NULL OR CompletedAtUtc >= CreatedAtUtc))
);

CREATE INDEX FundingPlatform_IX_AiExplanationJobs_Claim
    ON dbo.FundingPlatform_AiExplanationJobs
       (Status, NextAttemptAtUtc, LeaseUntilUtc, AiExplanationRunId, Id);

CREATE TABLE dbo.FundingPlatform_AiExplanationBudgetReservations
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_AiExplanationBudgetReservations_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    AiExplanationConfigurationId INT NOT NULL,
    AiExplanationJobId BIGINT NOT NULL,
    BudgetMonth DATE NOT NULL,
    ReservedCostUsd DECIMAL(19,6) NOT NULL,
    ConsumedCostUsd DECIMAL(19,6) NULL,
    Status TINYINT NOT NULL,
    LeaseId UNIQUEIDENTIFIER NOT NULL,
    ExpiresAtUtc DATETIME2(3) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    FinalizedAtUtc DATETIME2(3) NULL,
    CONSTRAINT FundingPlatform_PK_AiExplanationBudgetReservations PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_AiExplanationBudgetReservations_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_AiExplanationBudgetReservations_JobLease
        UNIQUE (AiExplanationJobId, LeaseId),
    CONSTRAINT FundingPlatform_FK_AiExplanationBudgetReservations_Config
        FOREIGN KEY (AiExplanationConfigurationId)
        REFERENCES dbo.FundingPlatform_AiExplanationConfigurations (Id),
    CONSTRAINT FundingPlatform_FK_AiExplanationBudgetReservations_Job
        FOREIGN KEY (AiExplanationJobId)
        REFERENCES dbo.FundingPlatform_AiExplanationJobs (Id),
    /* 0 active, 1 consumed, 2 released, 3 expired-conservatively-consumed. */
    CONSTRAINT FundingPlatform_CK_AiExplanationBudgetReservations_State CHECK
        ((Status = 0 AND ConsumedCostUsd IS NULL AND FinalizedAtUtc IS NULL)
         OR (Status IN (1, 3) AND ConsumedCostUsd = ReservedCostUsd
                              AND FinalizedAtUtc IS NOT NULL)
         OR (Status = 2 AND ConsumedCostUsd IS NULL AND FinalizedAtUtc IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_AiExplanationBudgetReservations_Bounds CHECK
        (ReservedCostUsd BETWEEN 0.000001 AND 1
         AND ExpiresAtUtc > CreatedAtUtc
         AND (FinalizedAtUtc IS NULL OR FinalizedAtUtc >= CreatedAtUtc))
);

CREATE INDEX FundingPlatform_IX_AiExplanationBudgetReservations_Month
    ON dbo.FundingPlatform_AiExplanationBudgetReservations
       (AiExplanationConfigurationId, BudgetMonth, Status, ExpiresAtUtc)
    INCLUDE (ReservedCostUsd, ConsumedCostUsd);

CREATE TABLE dbo.FundingPlatform_AiExplanationUsageLedger
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    AiExplanationJobId BIGINT NOT NULL,
    BudgetReservationId BIGINT NOT NULL,
    AiExplanationConfigurationId INT NOT NULL,
    BudgetMonth DATE NOT NULL,
    InputTokens INT NULL,
    OutputTokens INT NULL,
    EstimatedCostUsd DECIMAL(19,6) NOT NULL,
    LatencyMilliseconds INT NOT NULL,
    OutcomeCode NVARCHAR(32) NOT NULL,
    IsEstimatedUncertain BIT NOT NULL,
    RecordedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_AiExplanationUsageLedger PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_AiExplanationUsageLedger_Reservation
        UNIQUE (BudgetReservationId),
    CONSTRAINT FundingPlatform_FK_AiExplanationUsageLedger_Job
        FOREIGN KEY (AiExplanationJobId) REFERENCES dbo.FundingPlatform_AiExplanationJobs (Id),
    CONSTRAINT FundingPlatform_FK_AiExplanationUsageLedger_Reservation
        FOREIGN KEY (BudgetReservationId)
        REFERENCES dbo.FundingPlatform_AiExplanationBudgetReservations (Id),
    CONSTRAINT FundingPlatform_FK_AiExplanationUsageLedger_Config
        FOREIGN KEY (AiExplanationConfigurationId)
        REFERENCES dbo.FundingPlatform_AiExplanationConfigurations (Id),
    CONSTRAINT FundingPlatform_CK_AiExplanationUsageLedger_Bounds CHECK
        ((InputTokens IS NULL OR InputTokens BETWEEN 0 AND 8192)
         AND (OutputTokens IS NULL OR OutputTokens BETWEEN 0 AND 1024)
         AND EstimatedCostUsd BETWEEN 0.000001 AND 1
         AND LatencyMilliseconds BETWEEN 0 AND 600000
         AND ((OutcomeCode = N'succeeded' AND IsEstimatedUncertain = 0)
              OR (OutcomeCode = N'charge-uncertain' AND IsEstimatedUncertain = 1)))
);

CREATE TABLE dbo.FundingPlatform_AiExplanationResults
(
    AiExplanationJobId BIGINT NOT NULL,
    AiExplanationRunId BIGINT NOT NULL,
    CaseOrdinal INT NOT NULL,
    Assessment TINYINT NOT NULL,
    Summary NVARCHAR(300) NOT NULL,
    PrimaryReasonCode NVARCHAR(64) NOT NULL,
    CitedRuleCodesJson NVARCHAR(1000) NOT NULL,
    OutputFingerprint BINARY(32) NOT NULL,
    ProviderRequestIdHash BINARY(32) NULL,
    InputTokens INT NOT NULL,
    OutputTokens INT NOT NULL,
    EstimatedCostUsd DECIMAL(19,6) NOT NULL,
    LatencyMilliseconds INT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_AiExplanationResults PRIMARY KEY (AiExplanationJobId),
    CONSTRAINT FundingPlatform_UQ_AiExplanationResults_RunCase
        UNIQUE (AiExplanationRunId, CaseOrdinal),
    CONSTRAINT FundingPlatform_FK_AiExplanationResults_JobRun
        FOREIGN KEY (AiExplanationJobId, AiExplanationRunId)
        REFERENCES dbo.FundingPlatform_AiExplanationJobs (Id, AiExplanationRunId),
    CONSTRAINT FundingPlatform_CK_AiExplanationResults_Contract CHECK
        (Assessment BETWEEN 0 AND 2
         AND LEN(LTRIM(RTRIM(Summary))) BETWEEN 1 AND 300
         AND DATALENGTH(Summary) = DATALENGTH(LTRIM(RTRIM(Summary)))
         AND PrimaryReasonCode IN
             (N'signals-aligned', N'semantic-high-hard-gate-conflict',
              N'semantic-low-structured-compatible',
              N'insufficient-structured-evidence')
         AND ((Assessment = 0 AND PrimaryReasonCode = N'signals-aligned')
              OR (Assessment = 1 AND PrimaryReasonCode IN
                  (N'semantic-high-hard-gate-conflict',
                   N'semantic-low-structured-compatible'))
              OR (Assessment = 2
                  AND PrimaryReasonCode = N'insufficient-structured-evidence'))
         AND ISJSON(CitedRuleCodesJson) = 1
         AND LEFT(LTRIM(CitedRuleCodesJson), 1) = N'['
         AND InputTokens BETWEEN 0 AND 8192
         AND OutputTokens BETWEEN 0 AND 1024
         AND EstimatedCostUsd BETWEEN 0.000001 AND 1
         AND LatencyMilliseconds BETWEEN 0 AND 600000)
);
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_fn_AiExplanationCitedRulesValid
(
    @CitedRuleCodesJson NVARCHAR(1000)
)
RETURNS BIT
AS
BEGIN
    IF @CitedRuleCodesJson IS NULL OR ISJSON(@CitedRuleCodesJson) <> 1
       OR LEFT(LTRIM(@CitedRuleCodesJson), 1) <> N'[' RETURN 0;
    DECLARE @Count INT = (SELECT COUNT(*) FROM OPENJSON(@CitedRuleCodesJson));
    IF @Count > 3 RETURN 0;
    IF EXISTS
       (SELECT 1 FROM OPENJSON(@CitedRuleCodesJson)
        WHERE [type] <> 1 OR [value] COLLATE Latin1_General_100_BIN2 NOT IN
              (N'geography', N'organization_type', N'legal_entity',
               N'operating_years', N'prior_experience', N'categories',
               N'beneficiaries', N'project_type', N'amount'))
        RETURN 0;
    IF @Count <>
       (SELECT COUNT(DISTINCT [value] COLLATE Latin1_General_100_BIN2)
        FROM OPENJSON(@CitedRuleCodesJson))
        RETURN 0;
    IF EXISTS
       (SELECT 1
        FROM OPENJSON(@CitedRuleCodesJson) AS currentRule
        INNER JOIN OPENJSON(@CitedRuleCodesJson) AS nextRule
            ON TRY_CONVERT(INT, nextRule.[key]) =
               TRY_CONVERT(INT, currentRule.[key]) + 1
        WHERE currentRule.[value] COLLATE Latin1_General_100_BIN2 >=
              nextRule.[value] COLLATE Latin1_General_100_BIN2)
        RETURN 0;
    RETURN 1;
END;
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_fn_AiExplanationCanonicalInput
(
    @SourceSemanticEvaluationRunId BIGINT,
    @CaseOrdinal INT
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @Rules NVARCHAR(MAX);
    SELECT @Rules = CONCAT(N'[', COALESCE(STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT
    (
        N'{"ruleCode":"', STRING_ESCAPE(rules.Code, 'json'),
        N'","outcome":', results.Outcome,
        N',"dataState":', results.DataState,
        N',"reasonCode":"', STRING_ESCAPE(results.ReasonCode, 'json'),
        N'","warning":', CASE results.IsWarning WHEN 1 THEN N'true' ELSE N'false' END,
        N'}'
    )), N',') WITHIN GROUP (ORDER BY rules.Code), N''), N']')
    FROM dbo.FundingPlatform_SemanticEvaluationRunCases AS runCases
    INNER JOIN dbo.FundingPlatform_ProjectFundingMatchRuleResults AS results
        ON results.MatchId = runCases.ProjectFundingMatchId
    INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
        ON rules.Id = results.MatchingRuleId
    WHERE runCases.SemanticEvaluationRunId = @SourceSemanticEvaluationRunId
      AND runCases.CaseOrdinal = @CaseOrdinal;

    DECLARE @Canonical NVARCHAR(MAX);
    SELECT @Canonical = CONCAT
    (
        N'{"schemaVersion":"explanation-input-v1"',
        N',"semanticScore":', CONVERT(NVARCHAR(30), items.SemanticScore),
        N',"cosineSimilarity":', CONVERT(NVARCHAR(30), items.CosineSimilarity),
        N',"semanticRank":', COALESCE(CONVERT(NVARCHAR(20), items.SemanticRank), N'null'),
        N',"deterministicRank":',
            COALESCE(CONVERT(NVARCHAR(20), items.DeterministicRank), N'null'),
        N',"classification":', matches.Classification,
        N',"hardGateStatus":', matches.HardGateStatus,
        N',"compatibilityScore":',
            COALESCE(CONVERT(NVARCHAR(30), matches.CompatibilityScore), N'null'),
        N',"ruleScore":', CONVERT(NVARCHAR(30), matches.RuleScore),
        N',"evidenceCoverage":', CONVERT(NVARCHAR(30), matches.EvidenceCoverage),
        N',"rules":', COALESCE(@Rules, N'[]'), N'}'
    )
    FROM dbo.FundingPlatform_SemanticEvaluationItems AS items
    INNER JOIN dbo.FundingPlatform_SemanticEvaluationRunCases AS runCases
        ON runCases.SemanticEvaluationRunId = items.SemanticEvaluationRunId
       AND runCases.CaseOrdinal = items.CaseOrdinal
    INNER JOIN dbo.FundingPlatform_ProjectFundingMatches AS matches
        ON matches.Id = runCases.ProjectFundingMatchId
    WHERE items.SemanticEvaluationRunId = @SourceSemanticEvaluationRunId
      AND items.CaseOrdinal = @CaseOrdinal;
    RETURN @Canonical;
END;
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_AiExplanationConfigurationState
(
    @AiExplanationConfigurationId INT
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
                   configurations.ProviderCapability, N'|',
                   configurations.InputSchemaVersion, N'|',
                   configurations.OutputSchemaVersion, N'|',
                   configurations.PromptVersion, N'|',
                   CONVERT(VARCHAR(64), configurations.PromptFingerprint, 2), N'|',
                   CONVERT(VARCHAR(64), configurations.ResponseSchemaFingerprint, 2), N'|',
                   configurations.MaximumInputUtf8Bytes, N'|',
                   configurations.MaximumOutputTokens, N'|',
                   configurations.MaximumAttempts, N'|',
                   configurations.MaximumCostUsdPerResult, N'|',
                   configurations.MonthlyBudgetUsd, N'|',
                   CONVERT(VARCHAR(64), policies.PolicyFingerprint, 2)
               ))
           )) AS CalculatedFingerprint
    FROM dbo.FundingPlatform_AiExplanationConfigurations AS configurations
    INNER JOIN dbo.FundingPlatform_AiProviderGovernancePolicies AS policies
        ON policies.Id = configurations.ProviderGovernancePolicyId
    WHERE configurations.Id = @AiExplanationConfigurationId
);
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_AiExplanationRunSummaries()
RETURNS TABLE
AS
RETURN
(
    SELECT runs.Id AS AiExplanationRunId, runs.PublicId,
           sourceRuns.PublicId AS SourceSemanticEvaluationRunPublicId,
           runs.Status,
           CONCAT(configurations.Code, N'-v', configurations.Version)
               AS ExplanationConfigurationVersion,
           configurations.ProviderCode, configurations.ModelCode,
           configurations.InputSchemaVersion, configurations.OutputSchemaVersion,
           configurations.PromptVersion, runs.ItemCount, runs.CompletedCount,
           runs.FailedCount, runs.TotalEstimatedCostUsd,
           runs.CreatedAtUtc, runs.CompletedAtUtc
    FROM dbo.FundingPlatform_AiExplanationRuns AS runs
    INNER JOIN dbo.FundingPlatform_SemanticEvaluationRuns AS sourceRuns
        ON sourceRuns.Id = runs.SourceSemanticEvaluationRunId
    INNER JOIN dbo.FundingPlatform_AiExplanationConfigurations AS configurations
        ON configurations.Id = runs.AiExplanationConfigurationId
       AND configurations.Version = runs.AiExplanationConfigurationVersion
);
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_AiExplanationConfigurations_Immutable
ON dbo.FundingPlatform_AiExplanationConfigurations
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS
       (SELECT 1 FROM inserted
        OUTER APPLY dbo.FundingPlatform_ifn_AiExplanationConfigurationState(inserted.Id)
            AS state
        WHERE state.Id IS NULL
           OR inserted.ConfigurationFingerprint <> state.CalculatedFingerprint)
        THROW 54402, N'Explanation configuration fingerprint is invalid.', 1;
    IF EXISTS (SELECT 1 FROM deleted WHERE NOT EXISTS
               (SELECT 1 FROM inserted WHERE inserted.Id = deleted.Id))
       OR EXISTS
          (SELECT 1 FROM inserted INNER JOIN deleted ON deleted.Id = inserted.Id
           WHERE inserted.PublicId <> deleted.PublicId
              OR inserted.Code COLLATE Latin1_General_100_BIN2 <>
                 deleted.Code COLLATE Latin1_General_100_BIN2
              OR inserted.Version <> deleted.Version
              OR inserted.ProviderGovernancePolicyId <> deleted.ProviderGovernancePolicyId
              OR inserted.ProviderCode COLLATE Latin1_General_100_BIN2 <>
                 deleted.ProviderCode COLLATE Latin1_General_100_BIN2
              OR inserted.ModelCode COLLATE Latin1_General_100_BIN2 <>
                 deleted.ModelCode COLLATE Latin1_General_100_BIN2
              OR inserted.ProviderCapability <> deleted.ProviderCapability
              OR inserted.InputSchemaVersion <> deleted.InputSchemaVersion
              OR inserted.OutputSchemaVersion <> deleted.OutputSchemaVersion
              OR inserted.PromptVersion <> deleted.PromptVersion
              OR inserted.PromptFingerprint <> deleted.PromptFingerprint
              OR inserted.ResponseSchemaFingerprint <> deleted.ResponseSchemaFingerprint
              OR inserted.MaximumInputUtf8Bytes <> deleted.MaximumInputUtf8Bytes
              OR inserted.MaximumOutputTokens <> deleted.MaximumOutputTokens
              OR inserted.MaximumAttempts <> deleted.MaximumAttempts
              OR inserted.MaximumCostUsdPerResult <> deleted.MaximumCostUsdPerResult
              OR inserted.MonthlyBudgetUsd <> deleted.MonthlyBudgetUsd
              OR inserted.ConfigurationFingerprint <> deleted.ConfigurationFingerprint
              OR inserted.PublishedAtUtc <> deleted.PublishedAtUtc
              OR inserted.CreatedAtUtc <> deleted.CreatedAtUtc
              OR (deleted.IsActive = 0 AND inserted.IsActive = 1))
        THROW 54403, N'Published explanation configuration is immutable.', 1;
    IF EXISTS
       (SELECT 1 FROM inserted INNER JOIN deleted ON deleted.Id = inserted.Id
        WHERE deleted.IsActive = 1 AND inserted.IsActive = 0
          AND (EXISTS
               (SELECT 1 FROM dbo.FundingPlatform_AiExplanationRuns AS runs
                WHERE runs.AiExplanationConfigurationId = inserted.Id AND runs.Status = 0)
               OR EXISTS
               (SELECT 1 FROM dbo.FundingPlatform_AiExplanationJobs AS jobs
                INNER JOIN dbo.FundingPlatform_AiExplanationRuns AS runs
                    ON runs.Id = jobs.AiExplanationRunId
                WHERE runs.AiExplanationConfigurationId = inserted.Id
                  AND jobs.Status IN (0, 1, 3))
               OR EXISTS
               (SELECT 1 FROM dbo.FundingPlatform_AiExplanationBudgetReservations AS reservations
                WHERE reservations.AiExplanationConfigurationId = inserted.Id
                  AND reservations.Status = 0)))
        THROW 54404, N'Explanation work must drain before configuration deactivation.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_AiExplanationRuns_Immutable
ON dbo.FundingPlatform_AiExplanationRuns
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted WHERE NOT EXISTS
               (SELECT 1 FROM inserted WHERE inserted.Id = deleted.Id))
       OR EXISTS
          (SELECT 1 FROM inserted INNER JOIN deleted ON deleted.Id = inserted.Id
           WHERE inserted.PublicId <> deleted.PublicId
              OR inserted.SourceSemanticEvaluationRunId <>
                 deleted.SourceSemanticEvaluationRunId
              OR inserted.AiExplanationConfigurationId <>
                 deleted.AiExplanationConfigurationId
              OR inserted.AiExplanationConfigurationVersion <>
                 deleted.AiExplanationConfigurationVersion
              OR inserted.ConfigurationFingerprint <> deleted.ConfigurationFingerprint
              OR inserted.ItemCount <> deleted.ItemCount
              OR inserted.RequestedByUserId <> deleted.RequestedByUserId
              OR inserted.CreatedAtUtc <> deleted.CreatedAtUtc
              OR deleted.Status <> 0
              OR inserted.Status NOT IN (2, 4))
        THROW 54405, N'Explanation runs are immutable except exact terminalization.', 1;
    IF EXISTS
       (SELECT 1 FROM inserted
        OUTER APPLY
        (
            SELECT COUNT_BIG(*) AS JobCount,
                   SUM(CASE jobs.Status WHEN 2 THEN 1 ELSE 0 END) AS CompletedCount,
                   SUM(CASE jobs.Status WHEN 4 THEN 1 ELSE 0 END) AS FailedCount
            FROM dbo.FundingPlatform_AiExplanationJobs AS jobs
            WHERE jobs.AiExplanationRunId = inserted.Id
        ) AS jobState
        OUTER APPLY
        (
            SELECT COALESCE(SUM(ledger.EstimatedCostUsd), 0) AS TotalCost
            FROM dbo.FundingPlatform_AiExplanationUsageLedger AS ledger
            INNER JOIN dbo.FundingPlatform_AiExplanationJobs AS jobs
                ON jobs.Id = ledger.AiExplanationJobId
            WHERE jobs.AiExplanationRunId = inserted.Id
        ) AS usageState
        WHERE inserted.Status IN (2, 4)
          AND (jobState.JobCount <> inserted.ItemCount
               OR jobState.CompletedCount <> inserted.CompletedCount
               OR jobState.FailedCount <> inserted.FailedCount
               OR inserted.CompletedCount + inserted.FailedCount <> inserted.ItemCount
               OR inserted.TotalEstimatedCostUsd <> usageState.TotalCost))
        THROW 54406, N'Explanation run terminal summary must match immutable jobs and usage.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_AiExplanationJobs_SubjectGuard
ON dbo.FundingPlatform_AiExplanationJobs
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS
       (SELECT 1 FROM inserted
        LEFT JOIN dbo.FundingPlatform_AiExplanationRuns AS runs
            ON runs.Id = inserted.AiExplanationRunId
           AND runs.SourceSemanticEvaluationRunId = inserted.SourceSemanticEvaluationRunId
        LEFT JOIN dbo.FundingPlatform_SemanticEvaluationRuns AS sourceRuns
            ON sourceRuns.Id = inserted.SourceSemanticEvaluationRunId
           AND sourceRuns.Status = 2
        LEFT JOIN dbo.FundingPlatform_SemanticEvaluationItems AS items
            ON items.SemanticEvaluationRunId = inserted.SourceSemanticEvaluationRunId
           AND items.CaseOrdinal = inserted.CaseOrdinal
           AND items.DatasetSplit = 1 AND items.IsPrimaryCohort = 1
        OUTER APPLY
        (SELECT dbo.FundingPlatform_fn_AiExplanationCanonicalInput
            (inserted.SourceSemanticEvaluationRunId, inserted.CaseOrdinal) AS CanonicalInput)
            AS canonical
        WHERE runs.Id IS NULL OR sourceRuns.Id IS NULL OR items.CaseOrdinal IS NULL
           OR canonical.CanonicalInput IS NULL
           OR dbo.FundingPlatform_fn_SemanticInputRiskCode(canonical.CanonicalInput, 8192)
              IS NOT NULL
           OR inserted.InputContentHash <>
              dbo.FundingPlatform_fn_SemanticInputHash(canonical.CanonicalInput))
        THROW 54407, N'Explanation job must bind a safe frozen shadow item.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_AiExplanationJobs_Immutable
ON dbo.FundingPlatform_AiExplanationJobs
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted WHERE NOT EXISTS
               (SELECT 1 FROM inserted WHERE inserted.Id = deleted.Id))
       OR EXISTS
          (SELECT 1 FROM inserted INNER JOIN deleted ON deleted.Id = inserted.Id
           WHERE inserted.PublicId <> deleted.PublicId
              OR inserted.AiExplanationRunId <> deleted.AiExplanationRunId
              OR inserted.SourceSemanticEvaluationRunId <>
                 deleted.SourceSemanticEvaluationRunId
              OR inserted.CaseOrdinal <> deleted.CaseOrdinal
              OR inserted.InputContentHash <> deleted.InputContentHash
              OR inserted.CreatedAtUtc <> deleted.CreatedAtUtc
              OR (deleted.Status = 2 AND inserted.Status <> 2)
              OR (deleted.Status = 4 AND inserted.Status <> 4))
        THROW 54408, N'Explanation job identity and terminal states are immutable.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_AiExplanationBudgetReservations_Guard
ON dbo.FundingPlatform_AiExplanationBudgetReservations
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted WHERE NOT EXISTS
               (SELECT 1 FROM inserted WHERE inserted.Id = deleted.Id))
       OR EXISTS
          (SELECT 1 FROM inserted
           LEFT JOIN dbo.FundingPlatform_AiExplanationJobs AS jobs
               ON jobs.Id = inserted.AiExplanationJobId
           LEFT JOIN dbo.FundingPlatform_AiExplanationRuns AS runs
               ON runs.Id = jobs.AiExplanationRunId
              AND runs.AiExplanationConfigurationId =
                  inserted.AiExplanationConfigurationId
           WHERE jobs.Id IS NULL OR runs.Id IS NULL)
       OR EXISTS
          (SELECT 1 FROM inserted INNER JOIN deleted ON deleted.Id = inserted.Id
           WHERE inserted.PublicId <> deleted.PublicId
              OR inserted.AiExplanationConfigurationId <>
                 deleted.AiExplanationConfigurationId
              OR inserted.AiExplanationJobId <> deleted.AiExplanationJobId
              OR inserted.BudgetMonth <> deleted.BudgetMonth
              OR inserted.ReservedCostUsd <> deleted.ReservedCostUsd
              OR inserted.LeaseId <> deleted.LeaseId
              OR inserted.CreatedAtUtc <> deleted.CreatedAtUtc
              OR NOT
                 (
                     (deleted.Status = 0 AND inserted.Status IN (1, 2, 3)
                      AND inserted.ExpiresAtUtc = deleted.ExpiresAtUtc)
                     OR
                     (deleted.Status = 0 AND inserted.Status = 0
                      AND inserted.ExpiresAtUtc > deleted.ExpiresAtUtc
                      AND inserted.ConsumedCostUsd IS NULL
                      AND inserted.FinalizedAtUtc IS NULL
                      AND EXISTS
                          (SELECT 1
                           FROM dbo.FundingPlatform_AiExplanationJobs AS renewedJob
                           WHERE renewedJob.Id = inserted.AiExplanationJobId
                             AND renewedJob.Status = 1
                             AND renewedJob.LeaseId = inserted.LeaseId
                             AND renewedJob.LeaseUntilUtc = inserted.ExpiresAtUtc))
                 ))
        THROW 54409, N'Explanation budget reservation identity or lifecycle is invalid.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_AiExplanationUsageLedger_Immutable
ON dbo.FundingPlatform_AiExplanationUsageLedger
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted)
        THROW 54410, N'Explanation usage ledger is immutable.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_AiExplanationResults_Guard
ON dbo.FundingPlatform_AiExplanationResults
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted)
        THROW 54411, N'Structured explanation results are immutable.', 1;
    IF EXISTS
       (SELECT 1 FROM inserted
        LEFT JOIN dbo.FundingPlatform_AiExplanationJobs AS jobs
            ON jobs.Id = inserted.AiExplanationJobId
           AND jobs.AiExplanationRunId = inserted.AiExplanationRunId
           AND jobs.CaseOrdinal = inserted.CaseOrdinal
        LEFT JOIN dbo.FundingPlatform_AiExplanationRuns AS runs
            ON runs.Id = jobs.AiExplanationRunId
        OUTER APPLY
        (SELECT CONVERT(BINARY(32), HASHBYTES
         (
             'SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
             (
                 inserted.Assessment, N'|', inserted.Summary, N'|',
                 inserted.PrimaryReasonCode, N'|', inserted.CitedRuleCodesJson, N'|',
                 CONVERT(VARCHAR(64), runs.ConfigurationFingerprint, 2)
             ))
         )) AS CalculatedFingerprint) AS state
        WHERE jobs.Id IS NULL
           OR dbo.FundingPlatform_fn_AiExplanationCitedRulesValid
              (inserted.CitedRuleCodesJson) <> 1
           OR EXISTS
              (SELECT 1 FROM OPENJSON(inserted.CitedRuleCodesJson) AS cited
               WHERE NOT EXISTS
               (SELECT 1
                FROM dbo.FundingPlatform_SemanticEvaluationRunCases AS runCases
                INNER JOIN dbo.FundingPlatform_ProjectFundingMatchRuleResults AS results
                    ON results.MatchId = runCases.ProjectFundingMatchId
                INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
                    ON rules.Id = results.MatchingRuleId
                WHERE runCases.SemanticEvaluationRunId =
                      jobs.SourceSemanticEvaluationRunId
                  AND runCases.CaseOrdinal = jobs.CaseOrdinal
                  AND rules.Code COLLATE Latin1_General_100_BIN2 =
                      cited.[value] COLLATE Latin1_General_100_BIN2))
           OR dbo.FundingPlatform_fn_SemanticInputRiskCode
              (CONCAT(N'{"summary":"', STRING_ESCAPE(inserted.Summary, 'json'), N'"}'), 2048)
              IS NOT NULL
           OR inserted.OutputFingerprint <> state.CalculatedFingerprint)
        THROW 54412, N'Structured explanation output is not safe or reproducible.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_AiExplanationRunRequests_Immutable
ON dbo.FundingPlatform_AiExplanationRunRequests
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted)
        THROW 54413, N'Explanation idempotency ledger is immutable.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_AiExplanationConfigRequests_Immutable
ON dbo.FundingPlatform_AiExplanationConfigurationPublishRequests
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted)
        THROW 54414, N'Explanation configuration request ledger is immutable.', 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AiStructuredOutputProviderPolicy_AdminRegister
    @SuperAdminUserPublicId UNIQUEIDENTIFIER,
    @Code NVARCHAR(50),
    @Version INT,
    @EndpointOrigin NVARCHAR(200),
    @DataResidencyCode NVARCHAR(16),
    @DpaReferenceHash BINARY(32),
    @TermsSnapshotHash BINARY(32),
    @InputTokenCostUsdPerMillion DECIMAL(19,6),
    @OutputTokenCostUsdPerMillion DECIMAL(19,6),
    @ApprovedAtUtc DATETIME2(3),
    @ExpiresAtUtc DATETIME2(3),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF @SuperAdminUserPublicId IS NULL OR @NowUtc IS NULL OR @Code IS NULL
       OR @Version < 1
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
       OR @InputTokenCostUsdPerMillion NOT BETWEEN 0.000001 AND 1000
       OR @OutputTokenCostUsdPerMillion NOT BETWEEN 0.000001 AND 1000
       OR @ApprovedAtUtc IS NULL OR @ApprovedAtUtc > @NowUtc
       OR @ExpiresAtUtc <= @NowUtc OR @ExpiresAtUtc > DATEADD(YEAR, 2, @NowUtc)
       OR @IdempotencyKeyHash IS NULL OR DATALENGTH(@IdempotencyKeyHash) <> 32
       OR @RequestHash IS NULL OR DATALENGTH(@RequestHash) <> 32
        THROW 54415, N'Complete bounded Structured Outputs governance is required.', 1;

    DECLARE @UserId BIGINT, @PolicyId BIGINT, @StoredHash BINARY(32), @WasReplay BIT = 0;
    DECLARE @Fingerprint BINARY(32) = CONVERT(BINARY(32), HASHBYTES
    (
        'SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
        (
            @Code, N'|', @Version, N'|', N'openai', N'|', N'gpt-5.6-sol', N'|',
            1, N'|', @EndpointOrigin, N'|', 2, N'|', 0, N'|',
            @DataResidencyCode, N'|', CONVERT(VARCHAR(64), @DpaReferenceHash, 2), N'|',
            CONVERT(VARCHAR(64), @TermsSnapshotHash, 2), N'|',
            @InputTokenCostUsdPerMillion, N'|', @OutputTokenCostUsdPerMillion, N'|',
            1, N'|', CONVERT(NVARCHAR(33), @ApprovedAtUtc, 126), N'|',
            CONVERT(NVARCHAR(33), @ExpiresAtUtc, 126)
        ))
    ));
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_AiStructuredPolicy;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId = @SuperAdminUserPublicId, @ActorUserId = @UserId OUTPUT;
        IF NOT EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_UserRoles AS userRoles
            INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
            WHERE userRoles.UserId = @UserId AND roles.NormalizedName = N'SUPERADMIN')
            THROW 54416, N'Active SuperAdmin role with MFA is required.', 1;
        SELECT @PolicyId = requests.ProviderGovernancePolicyId,
               @StoredHash = requests.RequestHash
        FROM dbo.FundingPlatform_AiProviderGovernancePolicyRequests AS requests
             WITH (UPDLOCK, HOLDLOCK)
        WHERE requests.UserId = @UserId AND requests.IdempotencyKeyHash = @IdempotencyKeyHash;
        IF @PolicyId IS NOT NULL
        BEGIN
            IF @StoredHash <> @RequestHash
                THROW 54417, N'Idempotency key belongs to another provider policy.', 1;
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
                (@Code, @Version, N'openai', N'gpt-5.6-sol', 1, @EndpointOrigin,
                 2, 0, @DataResidencyCode, @DpaReferenceHash, @TermsSnapshotHash,
                 @InputTokenCostUsdPerMillion, @OutputTokenCostUsdPerMillion,
                 @Fingerprint, 1, 1, @UserId, @ApprovedAtUtc, @ExpiresAtUtc, @NowUtc);
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
               policies.ProviderCode, policies.ModelCode, policies.Capability,
               policies.EndpointOrigin, policies.RetentionMode,
               policies.MaximumProviderRetentionDays, policies.DataResidencyCode,
               policies.PolicyFingerprint, policies.InputTokenCostUsdPerMillion,
               policies.OutputTokenCostUsdPerMillion,
               policies.ExternalProcessingAllowed, policies.IsActive,
               policies.ApprovedAtUtc, policies.ExpiresAtUtc
        FROM dbo.FundingPlatform_AiProviderGovernancePolicies AS policies
        WHERE policies.Id = @PolicyId;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_AiStructuredPolicy;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AiExplanationConfiguration_AdminPublishOpenAi
    @SuperAdminUserPublicId UNIQUEIDENTIFIER,
    @ProviderPolicyPublicId UNIQUEIDENTIFIER,
    @Code NVARCHAR(50),
    @Version INT,
    @MaximumOutputTokens SMALLINT,
    @MaximumCostUsdPerResult DECIMAL(19,6),
    @MonthlyBudgetUsd DECIMAL(19,6),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF @SuperAdminUserPublicId IS NULL OR @ProviderPolicyPublicId IS NULL
       OR @Code IS NULL OR @Version < 1 OR @MaximumOutputTokens NOT BETWEEN 128 AND 1024
       OR @MaximumCostUsdPerResult NOT BETWEEN 0.000001 AND 1
       OR @MonthlyBudgetUsd NOT BETWEEN @MaximumCostUsdPerResult AND 10000
       OR @IdempotencyKeyHash IS NULL OR DATALENGTH(@IdempotencyKeyHash) <> 32
       OR @RequestHash IS NULL OR DATALENGTH(@RequestHash) <> 32 OR @NowUtc IS NULL
        THROW 54418, N'Complete bounded explanation configuration is required.', 1;

    DECLARE @Prompt NVARCHAR(MAX) =
        N'Eres un auditor de compatibilidad orientativa. Usa solo el JSON provisto. No confirmes elegibilidad, no agregues hechos y no incluyas datos personales. Devuelve unicamente el esquema solicitado.';
    DECLARE @Schema NVARCHAR(MAX) =
        N'{"type":"object","properties":{"assessment":{"type":"string","enum":["aligned","conflict","insufficient"]},"summary":{"type":"string"},"primaryReasonCode":{"type":"string","enum":["signals-aligned","semantic-high-hard-gate-conflict","semantic-low-structured-compatible","insufficient-structured-evidence"]},"citedRuleCodes":{"type":"array","items":{"type":"string","enum":["geography","organization_type","legal_entity","operating_years","prior_experience","categories","beneficiaries","project_type","amount"]}}},"required":["assessment","summary","primaryReasonCode","citedRuleCodes"],"additionalProperties":false}';
    DECLARE @PromptFingerprint BINARY(32) =
        CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @Prompt)));
    DECLARE @SchemaFingerprint BINARY(32) =
        CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @Schema)));
    DECLARE @UserId BIGINT, @PolicyId BIGINT, @ConfigurationId INT;
    DECLARE @Provider NVARCHAR(50), @Model NVARCHAR(128), @PolicyFingerprint BINARY(32);
    DECLARE @InputPrice DECIMAL(19,6), @OutputPrice DECIMAL(19,6);
    DECLARE @StoredHash BINARY(32), @WasReplay BIT = 0, @Fingerprint BINARY(32);
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_AiExplanationConfig;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId = @SuperAdminUserPublicId, @ActorUserId = @UserId OUTPUT;
        IF NOT EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_UserRoles AS userRoles
            INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
            WHERE userRoles.UserId = @UserId AND roles.NormalizedName = N'SUPERADMIN')
            THROW 54416, N'Active SuperAdmin role with MFA is required.', 1;
        SELECT @ConfigurationId = requests.AiExplanationConfigurationId,
               @StoredHash = requests.RequestHash
        FROM dbo.FundingPlatform_AiExplanationConfigurationPublishRequests AS requests
             WITH (UPDLOCK, HOLDLOCK)
        WHERE requests.UserId = @UserId AND requests.IdempotencyKeyHash = @IdempotencyKeyHash;
        IF @ConfigurationId IS NOT NULL
        BEGIN
            IF @StoredHash <> @RequestHash
                THROW 54419, N'Idempotency key belongs to another explanation configuration.', 1;
            SET @WasReplay = 1;
        END
        ELSE
        BEGIN
            SELECT @PolicyId = policies.Id, @Provider = policies.ProviderCode,
                   @Model = policies.ModelCode, @PolicyFingerprint = policies.PolicyFingerprint,
                   @InputPrice = policies.InputTokenCostUsdPerMillion,
                   @OutputPrice = policies.OutputTokenCostUsdPerMillion
            FROM dbo.FundingPlatform_AiProviderGovernancePolicies AS policies
                 WITH (UPDLOCK, HOLDLOCK)
            CROSS APPLY dbo.FundingPlatform_ifn_AiProviderGovernancePolicyState(policies.Id)
                AS state
            WHERE policies.PublicId = @ProviderPolicyPublicId
              AND policies.Capability = 1 AND policies.IsActive = 1
              AND policies.ProviderCode COLLATE Latin1_General_100_BIN2 =
                  N'openai' COLLATE Latin1_General_100_BIN2
              AND policies.ModelCode COLLATE Latin1_General_100_BIN2 =
                  N'gpt-5.6-sol' COLLATE Latin1_General_100_BIN2
              AND policies.ExternalProcessingAllowed = 1
              AND policies.RetentionMode = 2 AND policies.MaximumProviderRetentionDays = 0
              AND policies.ApprovedAtUtc <= @NowUtc AND policies.ExpiresAtUtc > @NowUtc
              AND policies.PolicyFingerprint = state.CalculatedFingerprint;
            IF @PolicyId IS NULL
                THROW 54420, N'Active exact Structured Outputs governance was not found.', 1;
            DECLARE @WorstCost DECIMAL(19,6) = CEILING
            (
                ((8192 * @InputPrice + @MaximumOutputTokens * @OutputPrice) / 1000000.0)
                * 1000000.0
            ) / 1000000.0;
            IF @MaximumCostUsdPerResult < @WorstCost
                THROW 54421, N'Maximum explanation cost is below the approved worst case.', 1;
            IF EXISTS
               (SELECT 1 FROM dbo.FundingPlatform_AiExplanationRuns WHERE Status = 0)
                THROW 54422, N'Active explanation work must finish before replacement.', 1;
            UPDATE dbo.FundingPlatform_AiExplanationConfigurations
            SET IsActive = 0 WHERE IsActive = 1;
            SET @Fingerprint = CONVERT(BINARY(32), HASHBYTES
            (
                'SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
                (
                    @Code, N'|', @Version, N'|', @Provider, N'|', @Model, N'|', 1, N'|',
                    N'explanation-input-v1', N'|', N'explanation-output-v1', N'|',
                    N'explanation-review-es-v1', N'|',
                    CONVERT(VARCHAR(64), @PromptFingerprint, 2), N'|',
                    CONVERT(VARCHAR(64), @SchemaFingerprint, 2), N'|',
                    8192, N'|', @MaximumOutputTokens, N'|', 3, N'|',
                    @MaximumCostUsdPerResult, N'|', @MonthlyBudgetUsd, N'|',
                    CONVERT(VARCHAR(64), @PolicyFingerprint, 2)
                ))
            ));
            INSERT INTO dbo.FundingPlatform_AiExplanationConfigurations
                (Code, Version, ProviderGovernancePolicyId, ProviderCode, ModelCode,
                 ProviderCapability, InputSchemaVersion, OutputSchemaVersion,
                 PromptVersion, PromptFingerprint, ResponseSchemaFingerprint,
                 MaximumInputUtf8Bytes, MaximumOutputTokens, MaximumAttempts,
                 MaximumCostUsdPerResult, MonthlyBudgetUsd, ConfigurationFingerprint,
                 IsActive, PublishedAtUtc, CreatedAtUtc)
            VALUES
                (@Code, @Version, @PolicyId, @Provider, @Model, 1,
                 N'explanation-input-v1', N'explanation-output-v1',
                 N'explanation-review-es-v1', @PromptFingerprint, @SchemaFingerprint,
                 8192, @MaximumOutputTokens, 3, @MaximumCostUsdPerResult,
                 @MonthlyBudgetUsd, @Fingerprint, 1, @NowUtc, @NowUtc);
            SET @ConfigurationId = SCOPE_IDENTITY();
            INSERT INTO dbo.FundingPlatform_AiExplanationConfigurationPublishRequests
                (UserId, IdempotencyKeyHash, RequestHash,
                 AiExplanationConfigurationId, CreatedAtUtc)
            VALUES (@UserId, @IdempotencyKeyHash, @RequestHash, @ConfigurationId, @NowUtc);
        END;
        IF @StartedTransaction = 1 COMMIT TRANSACTION;
        SELECT CONVERT(BIT, 1) AS Succeeded,
               CASE WHEN @WasReplay = 1 THEN N'replayed' ELSE N'published' END AS Code,
               @WasReplay AS WasReplay, configurations.PublicId,
               CONCAT(configurations.Code, N'-v', configurations.Version)
                   AS ConfigurationVersion,
               policies.PublicId AS ProviderPolicyPublicId,
               policies.PolicyFingerprint AS ProviderPolicyFingerprint,
               configurations.ProviderCode, configurations.ModelCode,
               configurations.InputSchemaVersion, configurations.OutputSchemaVersion,
               configurations.PromptVersion, configurations.PromptFingerprint,
               configurations.ResponseSchemaFingerprint,
               configurations.MaximumOutputTokens,
               configurations.MaximumCostUsdPerResult,
               configurations.MonthlyBudgetUsd, configurations.IsActive,
               configurations.PublishedAtUtc
        FROM dbo.FundingPlatform_AiExplanationConfigurations AS configurations
        INNER JOIN dbo.FundingPlatform_AiProviderGovernancePolicies AS policies
            ON policies.Id = configurations.ProviderGovernancePolicyId
        WHERE configurations.Id = @ConfigurationId;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_AiExplanationConfig;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AiExplanationRun_TryFinalize
    @AiExplanationRunId BIGINT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_AiExplanationJobs
        WHERE AiExplanationRunId = @AiExplanationRunId AND Status IN (0, 1, 3))
        RETURN;
    DECLARE @Completed SMALLINT, @Failed SMALLINT, @Cost DECIMAL(19,6);
    SELECT @Completed = CONVERT(SMALLINT, SUM(CASE Status WHEN 2 THEN 1 ELSE 0 END)),
           @Failed = CONVERT(SMALLINT, SUM(CASE Status WHEN 4 THEN 1 ELSE 0 END))
    FROM dbo.FundingPlatform_AiExplanationJobs
    WHERE AiExplanationRunId = @AiExplanationRunId;
    SELECT @Cost = COALESCE(SUM(ledger.EstimatedCostUsd), 0)
    FROM dbo.FundingPlatform_AiExplanationUsageLedger AS ledger
    INNER JOIN dbo.FundingPlatform_AiExplanationJobs AS jobs
        ON jobs.Id = ledger.AiExplanationJobId
    WHERE jobs.AiExplanationRunId = @AiExplanationRunId;
    UPDATE dbo.FundingPlatform_AiExplanationRuns
    SET Status = CASE WHEN COALESCE(@Completed, 0) > 0 THEN 2 ELSE 4 END,
        CompletedCount = COALESCE(@Completed, 0),
        FailedCount = COALESCE(@Failed, 0),
        TotalEstimatedCostUsd = COALESCE(@Cost, 0),
        CompletedAtUtc = @NowUtc,
        UpdatedAtUtc = @NowUtc
    WHERE Id = @AiExplanationRunId AND Status = 0;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AiExplanationRun_Create
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @SourceSemanticEvaluationRunPublicId UNIQUEIDENTIFIER,
    @ExplanationConfigurationVersion NVARCHAR(64),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @RuntimeEnabled BIT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF @AdminUserPublicId IS NULL OR @SourceSemanticEvaluationRunPublicId IS NULL
       OR @ExplanationConfigurationVersion IS NULL
       OR LEN(@ExplanationConfigurationVersion) NOT BETWEEN 3 AND 64
       OR @IdempotencyKeyHash IS NULL OR DATALENGTH(@IdempotencyKeyHash) <> 32
       OR @RequestHash IS NULL OR DATALENGTH(@RequestHash) <> 32 OR @NowUtc IS NULL
        THROW 54423, N'Complete explanation run identity is required.', 1;
    DECLARE @UserId BIGINT, @RunId BIGINT, @StoredHash BINARY(32), @WasReplay BIT = 0;
    DECLARE @SourceRunId BIGINT, @ConfigurationId INT, @ConfigurationVersion INT;
    DECLARE @ConfigurationFingerprint BINARY(32), @MaximumCost DECIMAL(19,6);
    DECLARE @MonthlyBudget DECIMAL(19,6), @ItemCount SMALLINT, @MaximumAttempts TINYINT;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_AiExplanationCreate;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId = @AdminUserPublicId, @ActorUserId = @UserId OUTPUT;
        IF NOT EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_UserRoles AS userRoles
            INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
            WHERE userRoles.UserId = @UserId
              AND roles.NormalizedName IN (N'ADMIN', N'SUPERADMIN'))
            THROW 54424, N'Active Admin or SuperAdmin role with MFA is required.', 1;

        SELECT @RunId = requests.AiExplanationRunId, @StoredHash = requests.RequestHash
        FROM dbo.FundingPlatform_AiExplanationRunRequests AS requests WITH (UPDLOCK, HOLDLOCK)
        WHERE requests.UserId = @UserId AND requests.IdempotencyKeyHash = @IdempotencyKeyHash;
        IF @RunId IS NOT NULL
        BEGIN
            IF @StoredHash <> @RequestHash
                THROW 54425, N'Idempotency key belongs to another explanation run.', 1;
            SET @WasReplay = 1;
        END
        ELSE
        BEGIN
            IF ISNULL(@RuntimeEnabled, 0) <> 1
            BEGIN
                IF @StartedTransaction = 1 COMMIT TRANSACTION;
                SELECT CONVERT(BIT, 0) AS Succeeded,
                       N'structured-outputs-disabled' AS Code,
                       CONVERT(BIT, 0) AS WasReplay,
                       CONVERT(UNIQUEIDENTIFIER, NULL) AS PublicId,
                       CONVERT(UNIQUEIDENTIFIER, NULL) AS SourceSemanticEvaluationRunPublicId,
                       CONVERT(TINYINT, NULL) AS Status,
                       CONVERT(NVARCHAR(64), NULL) AS ExplanationConfigurationVersion,
                       CONVERT(NVARCHAR(50), NULL) AS ProviderCode,
                       CONVERT(NVARCHAR(128), NULL) AS ModelCode,
                       CONVERT(SMALLINT, NULL) AS ItemCount,
                       CONVERT(SMALLINT, NULL) AS CompletedCount,
                       CONVERT(SMALLINT, NULL) AS FailedCount,
                       CONVERT(DECIMAL(19,6), NULL) AS TotalEstimatedCostUsd,
                       CONVERT(DATETIME2(3), NULL) AS CreatedAtUtc,
                       CONVERT(DATETIME2(3), NULL) AS CompletedAtUtc;
                RETURN;
            END;
            SELECT @SourceRunId = sourceRuns.Id
            FROM dbo.FundingPlatform_SemanticEvaluationRuns AS sourceRuns WITH (HOLDLOCK)
            INNER JOIN dbo.FundingPlatform_SemanticConfigurations AS sourceConfigurations
                ON sourceConfigurations.Id = sourceRuns.SemanticConfigurationId
               AND sourceConfigurations.Version = sourceRuns.SemanticConfigurationVersion
               AND sourceConfigurations.ConfigurationFingerprint =
                   sourceRuns.ConfigurationFingerprint
               AND sourceConfigurations.IsLocalFake = 0
            WHERE sourceRuns.PublicId = @SourceSemanticEvaluationRunPublicId
              AND sourceRuns.Status = 2;
            SELECT @ConfigurationId = configurations.Id,
                   @ConfigurationVersion = configurations.Version,
                   @ConfigurationFingerprint = configurations.ConfigurationFingerprint,
                   @MaximumCost = configurations.MaximumCostUsdPerResult,
                   @MonthlyBudget = configurations.MonthlyBudgetUsd,
                   @MaximumAttempts = configurations.MaximumAttempts
            FROM dbo.FundingPlatform_AiExplanationConfigurations AS configurations
                 WITH (UPDLOCK, HOLDLOCK)
            CROSS APPLY dbo.FundingPlatform_ifn_AiExplanationConfigurationState
                (configurations.Id) AS state
            INNER JOIN dbo.FundingPlatform_AiProviderGovernancePolicies AS policies
                WITH (HOLDLOCK)
                ON policies.Id = configurations.ProviderGovernancePolicyId
            CROSS APPLY dbo.FundingPlatform_ifn_AiProviderGovernancePolicyState(policies.Id)
                AS policyState
            WHERE CONCAT(configurations.Code, N'-v', configurations.Version)
                    COLLATE Latin1_General_100_BIN2 =
                  @ExplanationConfigurationVersion COLLATE Latin1_General_100_BIN2
              AND configurations.IsActive = 1
              AND configurations.ConfigurationFingerprint = state.CalculatedFingerprint
              AND policies.IsActive = 1 AND policies.ExternalProcessingAllowed = 1
              AND policies.RetentionMode = 2 AND policies.MaximumProviderRetentionDays = 0
              AND policies.ApprovedAtUtc <= @NowUtc AND policies.ExpiresAtUtc > @NowUtc
              AND policies.PolicyFingerprint = policyState.CalculatedFingerprint;
            IF @SourceRunId IS NULL OR @ConfigurationId IS NULL
            BEGIN
                IF @StartedTransaction = 1 COMMIT TRANSACTION;
                SELECT CONVERT(BIT, 0) AS Succeeded,
                       N'source-or-configuration-not-ready' AS Code,
                       CONVERT(BIT, 0) AS WasReplay,
                       CONVERT(UNIQUEIDENTIFIER, NULL) AS PublicId,
                       CONVERT(UNIQUEIDENTIFIER, NULL) AS SourceSemanticEvaluationRunPublicId,
                       CONVERT(TINYINT, NULL) AS Status,
                       CONVERT(NVARCHAR(64), NULL) AS ExplanationConfigurationVersion,
                       CONVERT(NVARCHAR(50), NULL) AS ProviderCode,
                       CONVERT(NVARCHAR(128), NULL) AS ModelCode,
                       CONVERT(SMALLINT, NULL) AS ItemCount,
                       CONVERT(SMALLINT, NULL) AS CompletedCount,
                       CONVERT(SMALLINT, NULL) AS FailedCount,
                       CONVERT(DECIMAL(19,6), NULL) AS TotalEstimatedCostUsd,
                       CONVERT(DATETIME2(3), NULL) AS CreatedAtUtc,
                       CONVERT(DATETIME2(3), NULL) AS CompletedAtUtc;
                RETURN;
            END;
            IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_AiExplanationRuns WHERE Status = 0)
            BEGIN
                IF @StartedTransaction = 1 COMMIT TRANSACTION;
                SELECT CONVERT(BIT, 0) AS Succeeded, N'active-run-exists' AS Code,
                       CONVERT(BIT, 0) AS WasReplay,
                       CONVERT(UNIQUEIDENTIFIER, NULL) AS PublicId,
                       CONVERT(UNIQUEIDENTIFIER, NULL) AS SourceSemanticEvaluationRunPublicId,
                       CONVERT(TINYINT, NULL) AS Status,
                       CONVERT(NVARCHAR(64), NULL) AS ExplanationConfigurationVersion,
                       CONVERT(NVARCHAR(50), NULL) AS ProviderCode,
                       CONVERT(NVARCHAR(128), NULL) AS ModelCode,
                       CONVERT(SMALLINT, NULL) AS ItemCount,
                       CONVERT(SMALLINT, NULL) AS CompletedCount,
                       CONVERT(SMALLINT, NULL) AS FailedCount,
                       CONVERT(DECIMAL(19,6), NULL) AS TotalEstimatedCostUsd,
                       CONVERT(DATETIME2(3), NULL) AS CreatedAtUtc,
                       CONVERT(DATETIME2(3), NULL) AS CompletedAtUtc;
                RETURN;
            END;

            DECLARE @Candidates TABLE
            (
                CaseOrdinal INT NOT NULL PRIMARY KEY,
                InputContentHash BINARY(32) NULL
            );
            ;WITH ranked AS
            (
                SELECT items.CaseOrdinal, runCases.ProjectMatchingRunId,
                       items.SemanticRank,
                       ROW_NUMBER() OVER
                       (
                           PARTITION BY runCases.ProjectMatchingRunId
                           ORDER BY items.SemanticRank, items.CaseOrdinal
                       ) AS ProjectOrdinal
                FROM dbo.FundingPlatform_SemanticEvaluationItems AS items
                INNER JOIN dbo.FundingPlatform_SemanticEvaluationRunCases AS runCases
                    ON runCases.SemanticEvaluationRunId = items.SemanticEvaluationRunId
                   AND runCases.CaseOrdinal = items.CaseOrdinal
                WHERE items.SemanticEvaluationRunId = @SourceRunId
                  AND items.DatasetSplit = 1 AND items.IsPrimaryCohort = 1
                  AND items.SemanticRank IS NOT NULL
            )
            INSERT INTO @Candidates (CaseOrdinal, InputContentHash)
            SELECT TOP (300) ranked.CaseOrdinal,
                   CASE WHEN dbo.FundingPlatform_fn_SemanticInputRiskCode
                       (canonical.CanonicalInput, 8192) IS NULL
                   THEN dbo.FundingPlatform_fn_SemanticInputHash(canonical.CanonicalInput)
                   END
            FROM ranked
            CROSS APPLY
              (SELECT dbo.FundingPlatform_fn_AiExplanationCanonicalInput
                  (@SourceRunId, ranked.CaseOrdinal) AS CanonicalInput) AS canonical
            WHERE ranked.ProjectOrdinal <= 10
            ORDER BY ranked.ProjectMatchingRunId, ranked.SemanticRank, ranked.CaseOrdinal;
            SET @ItemCount = CONVERT(SMALLINT, (SELECT COUNT(*) FROM @Candidates));
            IF @ItemCount < 1 OR EXISTS
               (SELECT 1 FROM @Candidates WHERE InputContentHash IS NULL)
            BEGIN
                IF @StartedTransaction = 1 COMMIT TRANSACTION;
                SELECT CONVERT(BIT, 0) AS Succeeded, N'source-or-configuration-not-ready' AS Code,
                       CONVERT(BIT, 0) AS WasReplay,
                       CONVERT(UNIQUEIDENTIFIER, NULL) AS PublicId,
                       CONVERT(UNIQUEIDENTIFIER, NULL) AS SourceSemanticEvaluationRunPublicId,
                       CONVERT(TINYINT, NULL) AS Status,
                       CONVERT(NVARCHAR(64), NULL) AS ExplanationConfigurationVersion,
                       CONVERT(NVARCHAR(50), NULL) AS ProviderCode,
                       CONVERT(NVARCHAR(128), NULL) AS ModelCode,
                       CONVERT(SMALLINT, NULL) AS ItemCount,
                       CONVERT(SMALLINT, NULL) AS CompletedCount,
                       CONVERT(SMALLINT, NULL) AS FailedCount,
                       CONVERT(DECIMAL(19,6), NULL) AS TotalEstimatedCostUsd,
                       CONVERT(DATETIME2(3), NULL) AS CreatedAtUtc,
                       CONVERT(DATETIME2(3), NULL) AS CompletedAtUtc;
                RETURN;
            END;
            DECLARE @LockResult INT;
            EXEC @LockResult = sys.sp_getapplock
                @Resource = N'FundingPlatform:AiExplanationBudget',
                @LockMode = N'Exclusive', @LockOwner = N'Transaction',
                @LockTimeout = 10000;
            IF @LockResult < 0 THROW 54426, N'Explanation budget lock is unavailable.', 1;
            DECLARE @BudgetMonth DATE =
                DATEFROMPARTS(YEAR(@NowUtc), MONTH(@NowUtc), 1);
            DECLARE @Committed DECIMAL(19,6);
            SELECT @Committed = COALESCE(SUM
            (
                CASE reservations.Status WHEN 0 THEN reservations.ReservedCostUsd
                    ELSE reservations.ConsumedCostUsd END
            ), 0)
            FROM dbo.FundingPlatform_AiExplanationBudgetReservations AS reservations
            WHERE reservations.AiExplanationConfigurationId = @ConfigurationId
              AND reservations.BudgetMonth = @BudgetMonth
              AND reservations.Status IN (0, 1, 3);
            IF @Committed + @ItemCount * @MaximumCost * @MaximumAttempts > @MonthlyBudget
            BEGIN
                IF @StartedTransaction = 1 COMMIT TRANSACTION;
                SELECT CONVERT(BIT, 0) AS Succeeded, N'budget-insufficient' AS Code,
                       CONVERT(BIT, 0) AS WasReplay,
                       CONVERT(UNIQUEIDENTIFIER, NULL) AS PublicId,
                       CONVERT(UNIQUEIDENTIFIER, NULL) AS SourceSemanticEvaluationRunPublicId,
                       CONVERT(TINYINT, NULL) AS Status,
                       CONVERT(NVARCHAR(64), NULL) AS ExplanationConfigurationVersion,
                       CONVERT(NVARCHAR(50), NULL) AS ProviderCode,
                       CONVERT(NVARCHAR(128), NULL) AS ModelCode,
                       CONVERT(SMALLINT, NULL) AS ItemCount,
                       CONVERT(SMALLINT, NULL) AS CompletedCount,
                       CONVERT(SMALLINT, NULL) AS FailedCount,
                       CONVERT(DECIMAL(19,6), NULL) AS TotalEstimatedCostUsd,
                       CONVERT(DATETIME2(3), NULL) AS CreatedAtUtc,
                       CONVERT(DATETIME2(3), NULL) AS CompletedAtUtc;
                RETURN;
            END;
            INSERT INTO dbo.FundingPlatform_AiExplanationRuns
                (SourceSemanticEvaluationRunId, AiExplanationConfigurationId,
                 AiExplanationConfigurationVersion, ConfigurationFingerprint,
                 Status, ItemCount, CompletedCount, FailedCount, TotalEstimatedCostUsd,
                 RequestedByUserId, CreatedAtUtc, CompletedAtUtc, UpdatedAtUtc)
            VALUES
                (@SourceRunId, @ConfigurationId, @ConfigurationVersion,
                 @ConfigurationFingerprint, 0, @ItemCount, 0, 0, NULL,
                 @UserId, @NowUtc, NULL, @NowUtc);
            SET @RunId = SCOPE_IDENTITY();
            INSERT INTO dbo.FundingPlatform_AiExplanationJobs
                (AiExplanationRunId, SourceSemanticEvaluationRunId, CaseOrdinal,
                 InputContentHash, Status, LeaseId, LeaseOwnerHash, LeaseUntilUtc,
                 AttemptCount, NextAttemptAtUtc, ErrorCode,
                 CreatedAtUtc, UpdatedAtUtc, CompletedAtUtc)
            SELECT @RunId, @SourceRunId, candidates.CaseOrdinal,
                   candidates.InputContentHash, 0, NULL, NULL, NULL, 0, @NowUtc,
                   NULL, @NowUtc, @NowUtc, NULL
            FROM @Candidates AS candidates;
            INSERT INTO dbo.FundingPlatform_AiExplanationRunRequests
                (UserId, IdempotencyKeyHash, RequestHash, AiExplanationRunId, CreatedAtUtc)
            VALUES (@UserId, @IdempotencyKeyHash, @RequestHash, @RunId, @NowUtc);
        END;
        IF @StartedTransaction = 1 COMMIT TRANSACTION;
        SELECT CONVERT(BIT, 1) AS Succeeded,
               CASE WHEN @WasReplay = 1 THEN N'replayed' ELSE N'created' END AS Code,
               @WasReplay AS WasReplay, summaries.PublicId,
               summaries.SourceSemanticEvaluationRunPublicId, summaries.Status,
               summaries.ExplanationConfigurationVersion,
               summaries.ProviderCode, summaries.ModelCode,
               summaries.ItemCount, summaries.CompletedCount, summaries.FailedCount,
               summaries.TotalEstimatedCostUsd,
               summaries.CreatedAtUtc, summaries.CompletedAtUtc
        FROM dbo.FundingPlatform_ifn_AiExplanationRunSummaries() AS summaries
        WHERE summaries.AiExplanationRunId = @RunId;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_AiExplanationCreate;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AiExplanationJob_Claim
    @WorkerInstanceId NVARCHAR(100),
    @LeaseSeconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @WorkerInstanceId IS NULL OR LEN(LTRIM(RTRIM(@WorkerInstanceId))) NOT BETWEEN 1 AND 100
       OR @LeaseSeconds NOT BETWEEN 300 AND 1800 OR @NowUtc IS NULL
        THROW 54427, N'Bounded explanation worker identity and lease are required.', 1;
    DECLARE @OwnerHash BINARY(32) = CONVERT(BINARY(32), HASHBYTES
        ('SHA2_256', CONVERT(VARBINARY(MAX), @WorkerInstanceId)));
    DECLARE @LeaseId UNIQUEIDENTIFIER = NEWID();
    DECLARE @LeaseUntilUtc DATETIME2(3) = DATEADD(SECOND, @LeaseSeconds, @NowUtc);
    DECLARE @BudgetMonth DATE = DATEFROMPARTS(YEAR(@NowUtc), MONTH(@NowUtc), 1);
    DECLARE @JobId BIGINT, @RunId BIGINT, @ConfigId INT, @MaximumCost DECIMAL(19,6);
    DECLARE @MonthlyBudget DECIMAL(19,6), @Committed DECIMAL(19,6);
    BEGIN TRANSACTION;
    BEGIN TRY
        DECLARE @LockResult INT;
        EXEC @LockResult = sys.sp_getapplock
            @Resource = N'FundingPlatform:AiExplanationBudget',
            @LockMode = N'Exclusive', @LockOwner = N'Transaction', @LockTimeout = 10000;
        IF @LockResult < 0 THROW 54426, N'Explanation budget lock is unavailable.', 1;

        DECLARE @Expired TABLE
        (
            ReservationId BIGINT, JobId BIGINT, ConfigId INT,
            ReservedCost DECIMAL(19,6), BudgetMonth DATE
        );
        UPDATE reservations
        SET Status = 3, ConsumedCostUsd = reservations.ReservedCostUsd,
            FinalizedAtUtc = @NowUtc
        OUTPUT inserted.Id, inserted.AiExplanationJobId,
               inserted.AiExplanationConfigurationId,
               inserted.ReservedCostUsd, inserted.BudgetMonth
        INTO @Expired
        FROM dbo.FundingPlatform_AiExplanationBudgetReservations AS reservations
        WHERE reservations.Status = 0 AND reservations.ExpiresAtUtc <= @NowUtc;
        INSERT INTO dbo.FundingPlatform_AiExplanationUsageLedger
            (AiExplanationJobId, BudgetReservationId, AiExplanationConfigurationId,
             BudgetMonth, InputTokens, OutputTokens, EstimatedCostUsd,
             LatencyMilliseconds, OutcomeCode, IsEstimatedUncertain, RecordedAtUtc)
        SELECT expired.JobId, expired.ReservationId, expired.ConfigId,
               expired.BudgetMonth, NULL, NULL, expired.ReservedCost,
               0, N'charge-uncertain', 1, @NowUtc
        FROM @Expired AS expired
        WHERE NOT EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_AiExplanationUsageLedger
               WHERE BudgetReservationId = expired.ReservationId);
        UPDATE jobs
        SET Status = CASE WHEN jobs.AttemptCount < configurations.MaximumAttempts
                          THEN 3 ELSE 4 END,
            LeaseId = NULL, LeaseOwnerHash = NULL, LeaseUntilUtc = NULL,
            NextAttemptAtUtc = CASE WHEN jobs.AttemptCount < configurations.MaximumAttempts
                                    THEN DATEADD(SECOND, 60, @NowUtc) ELSE @NowUtc END,
            ErrorCode = N'lease-expired', UpdatedAtUtc = @NowUtc,
            CompletedAtUtc = CASE WHEN jobs.AttemptCount < configurations.MaximumAttempts
                                  THEN NULL ELSE @NowUtc END
        FROM dbo.FundingPlatform_AiExplanationJobs AS jobs
        INNER JOIN @Expired AS expired ON expired.JobId = jobs.Id
        INNER JOIN dbo.FundingPlatform_AiExplanationRuns AS runs
            ON runs.Id = jobs.AiExplanationRunId
        INNER JOIN dbo.FundingPlatform_AiExplanationConfigurations AS configurations
            ON configurations.Id = runs.AiExplanationConfigurationId
        WHERE jobs.Status = 1;
        DECLARE @ExpiredRunId BIGINT =
            (SELECT TOP (1) jobs.AiExplanationRunId
             FROM @Expired AS expired
             INNER JOIN dbo.FundingPlatform_AiExplanationJobs AS jobs
                 ON jobs.Id = expired.JobId
             ORDER BY jobs.AiExplanationRunId);
        IF @ExpiredRunId IS NOT NULL
            EXEC dbo.FundingPlatform_usp_AiExplanationRun_TryFinalize
                @AiExplanationRunId = @ExpiredRunId, @NowUtc = @NowUtc;

        SELECT TOP (1) @JobId = jobs.Id, @RunId = runs.Id,
               @ConfigId = configurations.Id,
               @MaximumCost = configurations.MaximumCostUsdPerResult,
               @MonthlyBudget = configurations.MonthlyBudgetUsd
        FROM dbo.FundingPlatform_AiExplanationJobs AS jobs WITH (UPDLOCK, READPAST)
        INNER JOIN dbo.FundingPlatform_AiExplanationRuns AS runs WITH (UPDLOCK)
            ON runs.Id = jobs.AiExplanationRunId AND runs.Status = 0
        INNER JOIN dbo.FundingPlatform_AiExplanationConfigurations AS configurations
            WITH (HOLDLOCK)
            ON configurations.Id = runs.AiExplanationConfigurationId
           AND configurations.Version = runs.AiExplanationConfigurationVersion
           AND configurations.ConfigurationFingerprint = runs.ConfigurationFingerprint
           AND configurations.IsActive = 1
        CROSS APPLY dbo.FundingPlatform_ifn_AiExplanationConfigurationState
            (configurations.Id) AS configState
        INNER JOIN dbo.FundingPlatform_AiProviderGovernancePolicies AS policies WITH (HOLDLOCK)
            ON policies.Id = configurations.ProviderGovernancePolicyId
           AND policies.IsActive = 1 AND policies.ExternalProcessingAllowed = 1
           AND policies.RetentionMode = 2 AND policies.MaximumProviderRetentionDays = 0
           AND policies.ApprovedAtUtc <= @NowUtc AND policies.ExpiresAtUtc > @NowUtc
        CROSS APPLY dbo.FundingPlatform_ifn_AiProviderGovernancePolicyState(policies.Id)
            AS policyState
        WHERE jobs.Status IN (0, 3) AND jobs.NextAttemptAtUtc <= @NowUtc
          AND configurations.ConfigurationFingerprint = configState.CalculatedFingerprint
          AND policies.PolicyFingerprint = policyState.CalculatedFingerprint
        ORDER BY jobs.NextAttemptAtUtc, jobs.Id;

        IF @JobId IS NOT NULL
        BEGIN
            SELECT @Committed = COALESCE(SUM
            (
                CASE reservations.Status WHEN 0 THEN reservations.ReservedCostUsd
                    ELSE reservations.ConsumedCostUsd END
            ), 0)
            FROM dbo.FundingPlatform_AiExplanationBudgetReservations AS reservations
            WHERE reservations.AiExplanationConfigurationId = @ConfigId
              AND reservations.BudgetMonth = @BudgetMonth
              AND reservations.Status IN (0, 1, 3);
            IF @Committed + @MaximumCost > @MonthlyBudget
            BEGIN
                UPDATE dbo.FundingPlatform_AiExplanationJobs
                SET Status = 4, ErrorCode = N'budget-exhausted',
                    CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc
                WHERE Id = @JobId AND Status IN (0, 3);
                EXEC dbo.FundingPlatform_usp_AiExplanationRun_TryFinalize
                    @AiExplanationRunId = @RunId, @NowUtc = @NowUtc;
                SET @JobId = NULL;
            END
            ELSE
            BEGIN
                UPDATE dbo.FundingPlatform_AiExplanationJobs
                SET Status = 1, LeaseId = @LeaseId, LeaseOwnerHash = @OwnerHash,
                    LeaseUntilUtc = @LeaseUntilUtc, AttemptCount = AttemptCount + 1,
                    ErrorCode = NULL, UpdatedAtUtc = @NowUtc
                WHERE Id = @JobId AND Status IN (0, 3);
                INSERT INTO dbo.FundingPlatform_AiExplanationBudgetReservations
                    (AiExplanationConfigurationId, AiExplanationJobId, BudgetMonth,
                     ReservedCostUsd, ConsumedCostUsd, Status, LeaseId,
                     ExpiresAtUtc, CreatedAtUtc, FinalizedAtUtc)
                VALUES
                    (@ConfigId, @JobId, @BudgetMonth, @MaximumCost, NULL, 0,
                     @LeaseId, @LeaseUntilUtc, @NowUtc, NULL);
            END;
        END;
        COMMIT TRANSACTION;
        IF @JobId IS NOT NULL
        SELECT jobs.PublicId AS JobPublicId, jobs.LeaseId,
               reservations.PublicId AS BudgetReservationPublicId,
               runs.PublicId AS ExplanationRunPublicId,
               CONCAT(configurations.Code, N'-v', configurations.Version)
                   AS ExplanationConfigurationVersion,
               configurations.ConfigurationFingerprint,
               configurations.ProviderCode, configurations.ModelCode,
               configurations.InputSchemaVersion, configurations.OutputSchemaVersion,
               configurations.PromptVersion, configurations.PromptFingerprint,
               configurations.ResponseSchemaFingerprint,
               configurations.MaximumInputUtf8Bytes,
               configurations.MaximumOutputTokens, configurations.MaximumAttempts,
               configurations.MaximumCostUsdPerResult,
               jobs.InputContentHash, jobs.AttemptCount
        FROM dbo.FundingPlatform_AiExplanationJobs AS jobs
        INNER JOIN dbo.FundingPlatform_AiExplanationRuns AS runs
            ON runs.Id = jobs.AiExplanationRunId
        INNER JOIN dbo.FundingPlatform_AiExplanationConfigurations AS configurations
            ON configurations.Id = runs.AiExplanationConfigurationId
        INNER JOIN dbo.FundingPlatform_AiExplanationBudgetReservations AS reservations
            ON reservations.AiExplanationJobId = jobs.Id
           AND reservations.LeaseId = jobs.LeaseId AND reservations.Status = 0
        WHERE jobs.Id = @JobId;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AiExplanationJob_GetInput
    @JobPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @JobPublicId IS NULL OR @LeaseId IS NULL OR @NowUtc IS NULL
        THROW 54428, N'Explanation job lease identity is required.', 1;
    DECLARE @JobId BIGINT, @RunId BIGINT, @SourceRunId BIGINT, @CaseOrdinal INT;
    DECLARE @ExpectedHash BINARY(32), @CanonicalInput NVARCHAR(MAX), @ConfigValid BIT;
    DECLARE @ReservationId BIGINT, @ReservationExpiresAtUtc DATETIME2(3);
    DECLARE @PolicyPublicId UNIQUEIDENTIFIER, @PolicyVersion NVARCHAR(64);
    DECLARE @PolicyFingerprint BINARY(32), @Capability TINYINT, @Endpoint NVARCHAR(200);
    DECLARE @RetentionMode TINYINT, @RetentionDays SMALLINT, @Residency NVARCHAR(16);
    DECLARE @InputPrice DECIMAL(19,6), @OutputPrice DECIMAL(19,6);
    DECLARE @ApprovedAtUtc DATETIME2(3), @ExpiresAtUtc DATETIME2(3), @Allowed BIT;
    BEGIN TRANSACTION;
    BEGIN TRY
        SELECT @JobId = jobs.Id, @RunId = runs.Id,
               @SourceRunId = jobs.SourceSemanticEvaluationRunId,
               @CaseOrdinal = jobs.CaseOrdinal, @ExpectedHash = jobs.InputContentHash,
               @PolicyPublicId = policies.PublicId,
               @PolicyVersion = CONCAT(policies.Code, N'-v', policies.Version),
               @PolicyFingerprint = policies.PolicyFingerprint,
               @Capability = policies.Capability, @Endpoint = policies.EndpointOrigin,
               @RetentionMode = policies.RetentionMode,
               @RetentionDays = policies.MaximumProviderRetentionDays,
               @Residency = policies.DataResidencyCode,
               @InputPrice = policies.InputTokenCostUsdPerMillion,
               @OutputPrice = policies.OutputTokenCostUsdPerMillion,
               @ApprovedAtUtc = policies.ApprovedAtUtc,
               @ExpiresAtUtc = policies.ExpiresAtUtc,
               @Allowed = policies.ExternalProcessingAllowed,
               @ConfigValid = CASE
                   WHEN configurations.IsActive = 1
                    AND configurations.ConfigurationFingerprint = configState.CalculatedFingerprint
                    AND policies.IsActive = 1 AND policies.ExternalProcessingAllowed = 1
                    AND policies.RetentionMode = 2
                    AND policies.MaximumProviderRetentionDays = 0
                    AND policies.ApprovedAtUtc <= @NowUtc
                    AND policies.ExpiresAtUtc > @NowUtc
                    AND policies.PolicyFingerprint = policyState.CalculatedFingerprint
                   THEN 1 ELSE 0 END
        FROM dbo.FundingPlatform_AiExplanationJobs AS jobs WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_AiExplanationRuns AS runs WITH (HOLDLOCK)
            ON runs.Id = jobs.AiExplanationRunId AND runs.Status = 0
        INNER JOIN dbo.FundingPlatform_AiExplanationConfigurations AS configurations
            WITH (HOLDLOCK)
            ON configurations.Id = runs.AiExplanationConfigurationId
           AND configurations.Version = runs.AiExplanationConfigurationVersion
           AND configurations.ConfigurationFingerprint = runs.ConfigurationFingerprint
        CROSS APPLY dbo.FundingPlatform_ifn_AiExplanationConfigurationState
            (configurations.Id) AS configState
        INNER JOIN dbo.FundingPlatform_AiProviderGovernancePolicies AS policies WITH (HOLDLOCK)
            ON policies.Id = configurations.ProviderGovernancePolicyId
           AND policies.ProviderCode = configurations.ProviderCode
           AND policies.ModelCode = configurations.ModelCode
           AND policies.Capability = configurations.ProviderCapability
        CROSS APPLY dbo.FundingPlatform_ifn_AiProviderGovernancePolicyState(policies.Id)
            AS policyState
        WHERE jobs.PublicId = @JobPublicId AND jobs.Status = 1
          AND jobs.LeaseId = @LeaseId AND jobs.LeaseUntilUtc > @NowUtc;
        IF @JobId IS NULL
        BEGIN COMMIT TRANSACTION; RETURN; END;
        SELECT @ReservationId = Id, @ReservationExpiresAtUtc = ExpiresAtUtc
        FROM dbo.FundingPlatform_AiExplanationBudgetReservations WITH (UPDLOCK, HOLDLOCK)
        WHERE AiExplanationJobId = @JobId AND LeaseId = @LeaseId AND Status = 0;
        SET @CanonicalInput =
            dbo.FundingPlatform_fn_AiExplanationCanonicalInput(@SourceRunId, @CaseOrdinal);
        DECLARE @FailureCode NVARCHAR(50) = CASE
            WHEN @ConfigValid <> 1 OR @ReservationId IS NULL
                 OR @ReservationExpiresAtUtc <= @NowUtc
                THEN N'explanation-configuration-invalid'
            WHEN dbo.FundingPlatform_fn_SemanticInputRiskCode(@CanonicalInput, 8192) IS NOT NULL
                THEN N'explanation-input-invalid'
            WHEN dbo.FundingPlatform_fn_SemanticInputHash(@CanonicalInput) <> @ExpectedHash
                THEN N'explanation-input-invalid' END;
        IF @FailureCode IS NOT NULL
        BEGIN
            UPDATE dbo.FundingPlatform_AiExplanationJobs
            SET Status = 4, LeaseId = NULL, LeaseOwnerHash = NULL, LeaseUntilUtc = NULL,
                ErrorCode = @FailureCode, CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc
            WHERE Id = @JobId;
            UPDATE dbo.FundingPlatform_AiExplanationBudgetReservations
            SET Status = 2, FinalizedAtUtc = @NowUtc
            WHERE Id = @ReservationId AND Status = 0;
            EXEC dbo.FundingPlatform_usp_AiExplanationRun_TryFinalize
                @AiExplanationRunId = @RunId, @NowUtc = @NowUtc;
            COMMIT TRANSACTION;
            RETURN;
        END;
        COMMIT TRANSACTION;
        SELECT @JobPublicId AS JobPublicId, @LeaseId AS LeaseId,
               @CanonicalInput AS CanonicalInputJson, @ExpectedHash AS InputContentHash,
               @PolicyPublicId AS ProviderPolicyPublicId,
               @PolicyVersion AS ProviderPolicyVersion,
               @PolicyFingerprint AS ProviderPolicyFingerprint,
               @Capability AS ProviderCapability, @Endpoint AS ProviderEndpointOrigin,
               @RetentionMode AS RetentionMode,
               @RetentionDays AS MaximumProviderRetentionDays,
               @Residency AS DataResidencyCode,
               @InputPrice AS InputTokenCostUsdPerMillion,
               @OutputPrice AS OutputTokenCostUsdPerMillion,
               @ApprovedAtUtc AS ApprovedAtUtc, @ExpiresAtUtc AS ExpiresAtUtc,
               @Allowed AS ExternalProcessingAllowed;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AiExplanationJob_RenewLease
    @JobPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @LeaseSeconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @JobPublicId IS NULL OR @LeaseId IS NULL
       OR @LeaseSeconds NOT BETWEEN 300 AND 1800 OR @NowUtc IS NULL
        THROW 54428, N'Explanation job lease identity is required.', 1;
    DECLARE @LeaseUntilUtc DATETIME2(3) = DATEADD(SECOND, @LeaseSeconds, @NowUtc);
    BEGIN TRANSACTION;
    BEGIN TRY
        UPDATE jobs
        SET LeaseUntilUtc = @LeaseUntilUtc, UpdatedAtUtc = @NowUtc
        FROM dbo.FundingPlatform_AiExplanationJobs AS jobs
        INNER JOIN dbo.FundingPlatform_AiExplanationRuns AS runs
            ON runs.Id = jobs.AiExplanationRunId AND runs.Status = 0
        INNER JOIN dbo.FundingPlatform_AiExplanationConfigurations AS configurations
            ON configurations.Id = runs.AiExplanationConfigurationId
           AND configurations.IsActive = 1
        WHERE jobs.PublicId = @JobPublicId AND jobs.Status = 1
          AND jobs.LeaseId = @LeaseId AND jobs.LeaseUntilUtc > @NowUtc;
        DECLARE @Succeeded BIT = CASE WHEN @@ROWCOUNT = 1 THEN 1 ELSE 0 END;
        IF @Succeeded = 1
            UPDATE reservations
            SET ExpiresAtUtc = @LeaseUntilUtc
            FROM dbo.FundingPlatform_AiExplanationBudgetReservations AS reservations
            INNER JOIN dbo.FundingPlatform_AiExplanationJobs AS jobs
                ON jobs.Id = reservations.AiExplanationJobId
            WHERE jobs.PublicId = @JobPublicId AND reservations.LeaseId = @LeaseId
              AND reservations.Status = 0 AND reservations.ExpiresAtUtc > @NowUtc;
        IF @Succeeded = 1 AND @@ROWCOUNT <> 1
            THROW 54429, N'Explanation budget reservation lease is missing.', 1;
        COMMIT TRANSACTION;
        SELECT @Succeeded AS Succeeded;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AiExplanationJob_Complete
    @JobPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @BudgetReservationPublicId UNIQUEIDENTIFIER,
    @ProviderCode NVARCHAR(50),
    @ModelCode NVARCHAR(128),
    @PromptVersion NVARCHAR(50),
    @OutputSchemaVersion NVARCHAR(50),
    @Assessment TINYINT,
    @Summary NVARCHAR(300),
    @PrimaryReasonCode NVARCHAR(64),
    @CitedRuleCodesJson NVARCHAR(1000),
    @OutputFingerprint BINARY(32),
    @ProviderRequestIdHash BINARY(32) = NULL,
    @InputTokens INT,
    @OutputTokens INT,
    @EstimatedCostUsd DECIMAL(19,6),
    @LatencyMilliseconds INT,
    @CompletedAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF @JobPublicId IS NULL OR @LeaseId IS NULL OR @BudgetReservationPublicId IS NULL
       OR @ProviderCode IS NULL OR @ModelCode IS NULL OR @PromptVersion IS NULL
       OR @OutputSchemaVersion IS NULL OR @Assessment NOT BETWEEN 0 AND 2
       OR @Summary IS NULL OR @PrimaryReasonCode IS NULL OR @CitedRuleCodesJson IS NULL
       OR @OutputFingerprint IS NULL OR DATALENGTH(@OutputFingerprint) <> 32
       OR (@ProviderRequestIdHash IS NOT NULL
           AND DATALENGTH(@ProviderRequestIdHash) <> 32)
       OR @InputTokens NOT BETWEEN 0 AND 8192
       OR @OutputTokens NOT BETWEEN 0 AND 1024
       OR @EstimatedCostUsd NOT BETWEEN 0.000001 AND 1
       OR @LatencyMilliseconds NOT BETWEEN 0 AND 600000 OR @CompletedAtUtc IS NULL
        THROW 54430, N'Complete bounded structured explanation output is required.', 1;
    DECLARE @JobId BIGINT, @RunId BIGINT, @ReservationId BIGINT;
    DECLARE @ConfigurationFingerprint BINARY(32), @ExpectedCost DECIMAL(19,6);
    DECLARE @InputPrice DECIMAL(19,6), @OutputPrice DECIMAL(19,6);
    DECLARE @MaximumCost DECIMAL(19,6), @BudgetMonth DATE;
    DECLARE @ExpectedProviderCode NVARCHAR(50), @ExpectedModelCode NVARCHAR(128);
    DECLARE @ExpectedPromptVersion NVARCHAR(50), @ExpectedOutputSchemaVersion NVARCHAR(50);
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_AiExplanationComplete;
    BEGIN TRY
        SELECT @JobId = jobs.Id, @RunId = runs.Id,
               @ConfigurationFingerprint = runs.ConfigurationFingerprint,
               @MaximumCost = configurations.MaximumCostUsdPerResult,
               @ExpectedProviderCode = configurations.ProviderCode,
               @ExpectedModelCode = configurations.ModelCode,
               @ExpectedPromptVersion = configurations.PromptVersion,
               @ExpectedOutputSchemaVersion = configurations.OutputSchemaVersion,
               @InputPrice = policies.InputTokenCostUsdPerMillion,
               @OutputPrice = policies.OutputTokenCostUsdPerMillion
        FROM dbo.FundingPlatform_AiExplanationJobs AS jobs WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_AiExplanationRuns AS runs WITH (UPDLOCK, HOLDLOCK)
            ON runs.Id = jobs.AiExplanationRunId
        INNER JOIN dbo.FundingPlatform_AiExplanationConfigurations AS configurations
            ON configurations.Id = runs.AiExplanationConfigurationId
           AND configurations.Version = runs.AiExplanationConfigurationVersion
        INNER JOIN dbo.FundingPlatform_AiProviderGovernancePolicies AS policies
            ON policies.Id = configurations.ProviderGovernancePolicyId
        WHERE jobs.PublicId = @JobPublicId;
        IF @JobId IS NULL THROW 54431, N'Explanation job was not found.', 1;
        SELECT @ReservationId = reservations.Id, @BudgetMonth = reservations.BudgetMonth
        FROM dbo.FundingPlatform_AiExplanationBudgetReservations AS reservations
        WHERE reservations.PublicId = @BudgetReservationPublicId
          AND reservations.AiExplanationJobId = @JobId
          AND reservations.LeaseId = @LeaseId;

        IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_AiExplanationJobs
                   WHERE Id = @JobId AND Status = 2)
        BEGIN
            IF @ReservationId IS NULL
               OR @ProviderCode COLLATE Latin1_General_100_BIN2 <>
                  @ExpectedProviderCode COLLATE Latin1_General_100_BIN2
               OR @ModelCode COLLATE Latin1_General_100_BIN2 <>
                  @ExpectedModelCode COLLATE Latin1_General_100_BIN2
               OR @PromptVersion COLLATE Latin1_General_100_BIN2 <>
                  @ExpectedPromptVersion COLLATE Latin1_General_100_BIN2
               OR @OutputSchemaVersion COLLATE Latin1_General_100_BIN2 <>
                  @ExpectedOutputSchemaVersion COLLATE Latin1_General_100_BIN2
               OR NOT EXISTS
               (SELECT 1
                FROM dbo.FundingPlatform_AiExplanationResults AS results
                INNER JOIN dbo.FundingPlatform_AiExplanationUsageLedger AS ledger
                    ON ledger.AiExplanationJobId = results.AiExplanationJobId
                   AND ledger.BudgetReservationId = @ReservationId
                WHERE results.AiExplanationJobId = @JobId
                  AND results.Assessment = @Assessment
                  AND results.Summary COLLATE Latin1_General_100_BIN2 =
                      @Summary COLLATE Latin1_General_100_BIN2
                  AND results.PrimaryReasonCode COLLATE Latin1_General_100_BIN2 =
                      @PrimaryReasonCode COLLATE Latin1_General_100_BIN2
                  AND results.CitedRuleCodesJson COLLATE Latin1_General_100_BIN2 =
                      @CitedRuleCodesJson COLLATE Latin1_General_100_BIN2
                  AND results.OutputFingerprint = @OutputFingerprint
                  AND ((results.ProviderRequestIdHash IS NULL
                        AND @ProviderRequestIdHash IS NULL)
                       OR results.ProviderRequestIdHash = @ProviderRequestIdHash)
                  AND results.InputTokens = @InputTokens
                  AND results.OutputTokens = @OutputTokens
                  AND results.EstimatedCostUsd = @EstimatedCostUsd
                  AND results.LatencyMilliseconds = @LatencyMilliseconds
                  AND ledger.OutcomeCode = N'succeeded'
                  AND ledger.EstimatedCostUsd = @EstimatedCostUsd)
                THROW 54432, N'Completed explanation replay did not match persisted output.', 1;
            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(BIT, 1) AS Succeeded, CONVERT(BIT, 1) AS WasReplay;
            RETURN;
        END;
        IF NOT EXISTS
           (SELECT 1
            FROM dbo.FundingPlatform_AiExplanationJobs AS jobs
            INNER JOIN dbo.FundingPlatform_AiExplanationRuns AS runs
                ON runs.Id = jobs.AiExplanationRunId AND runs.Status = 0
            INNER JOIN dbo.FundingPlatform_AiExplanationConfigurations AS configurations
                ON configurations.Id = runs.AiExplanationConfigurationId
               AND configurations.IsActive = 1
               AND configurations.ConfigurationFingerprint = runs.ConfigurationFingerprint
               AND configurations.ProviderCode COLLATE Latin1_General_100_BIN2 =
                   @ProviderCode COLLATE Latin1_General_100_BIN2
               AND configurations.ModelCode COLLATE Latin1_General_100_BIN2 =
                   @ModelCode COLLATE Latin1_General_100_BIN2
               AND configurations.PromptVersion COLLATE Latin1_General_100_BIN2 =
                   @PromptVersion COLLATE Latin1_General_100_BIN2
               AND configurations.OutputSchemaVersion COLLATE Latin1_General_100_BIN2 =
                   @OutputSchemaVersion COLLATE Latin1_General_100_BIN2
               AND @OutputTokens <= configurations.MaximumOutputTokens
            INNER JOIN dbo.FundingPlatform_AiProviderGovernancePolicies AS policies
                ON policies.Id = configurations.ProviderGovernancePolicyId
               AND policies.IsActive = 1 AND policies.ExternalProcessingAllowed = 1
               AND policies.ExpiresAtUtc > @CompletedAtUtc
            WHERE jobs.Id = @JobId AND jobs.Status = 1
              AND jobs.LeaseId = @LeaseId AND jobs.LeaseUntilUtc > @CompletedAtUtc)
            THROW 54433, N'Explanation lease or exact configuration is no longer valid.', 1;
        IF @ReservationId IS NULL OR NOT EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_AiExplanationBudgetReservations
            WHERE Id = @ReservationId AND Status = 0
              AND ExpiresAtUtc > @CompletedAtUtc
              AND ReservedCostUsd = @MaximumCost)
            THROW 54434, N'Active exact explanation budget reservation is required.', 1;
        SET @ExpectedCost = CEILING
        (
            ((@InputTokens * @InputPrice + @OutputTokens * @OutputPrice) / 1000000.0)
            * 1000000.0
        ) / 1000000.0;
        IF @EstimatedCostUsd <> @ExpectedCost OR @EstimatedCostUsd > @MaximumCost
            THROW 54435, N'Explanation provider cost does not match approved pricing.', 1;
        IF dbo.FundingPlatform_fn_AiExplanationCitedRulesValid(@CitedRuleCodesJson) <> 1
           OR dbo.FundingPlatform_fn_SemanticInputRiskCode
              (CONCAT(N'{"summary":"', STRING_ESCAPE(@Summary, 'json'), N'"}'), 2048)
              IS NOT NULL
            THROW 54436, N'Explanation output failed the safe structured contract.', 1;
        DECLARE @ExpectedOutputFingerprint BINARY(32) = CONVERT(BINARY(32), HASHBYTES
        (
            'SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
            (
                @Assessment, N'|', @Summary, N'|', @PrimaryReasonCode, N'|',
                @CitedRuleCodesJson, N'|',
                CONVERT(VARCHAR(64), @ConfigurationFingerprint, 2)
            ))
        ));
        IF @ExpectedOutputFingerprint <> @OutputFingerprint
            THROW 54437, N'Explanation output fingerprint is invalid.', 1;

        INSERT INTO dbo.FundingPlatform_AiExplanationResults
            (AiExplanationJobId, AiExplanationRunId, CaseOrdinal, Assessment, Summary,
             PrimaryReasonCode, CitedRuleCodesJson, OutputFingerprint,
             ProviderRequestIdHash, InputTokens, OutputTokens, EstimatedCostUsd,
             LatencyMilliseconds, CreatedAtUtc)
        SELECT jobs.Id, jobs.AiExplanationRunId, jobs.CaseOrdinal, @Assessment, @Summary,
               @PrimaryReasonCode, @CitedRuleCodesJson, @OutputFingerprint,
               @ProviderRequestIdHash, @InputTokens, @OutputTokens, @EstimatedCostUsd,
               @LatencyMilliseconds, @CompletedAtUtc
        FROM dbo.FundingPlatform_AiExplanationJobs AS jobs WHERE jobs.Id = @JobId;
        UPDATE dbo.FundingPlatform_AiExplanationBudgetReservations
        SET Status = 1, ConsumedCostUsd = ReservedCostUsd,
            FinalizedAtUtc = @CompletedAtUtc
        WHERE Id = @ReservationId AND Status = 0;
        INSERT INTO dbo.FundingPlatform_AiExplanationUsageLedger
            (AiExplanationJobId, BudgetReservationId, AiExplanationConfigurationId,
             BudgetMonth, InputTokens, OutputTokens, EstimatedCostUsd,
             LatencyMilliseconds, OutcomeCode, IsEstimatedUncertain, RecordedAtUtc)
        SELECT @JobId, @ReservationId, runs.AiExplanationConfigurationId,
               @BudgetMonth, @InputTokens, @OutputTokens, @EstimatedCostUsd,
               @LatencyMilliseconds, N'succeeded', 0, @CompletedAtUtc
        FROM dbo.FundingPlatform_AiExplanationRuns AS runs WHERE runs.Id = @RunId;
        UPDATE dbo.FundingPlatform_AiExplanationJobs
        SET Status = 2, LeaseId = NULL, LeaseOwnerHash = NULL, LeaseUntilUtc = NULL,
            ErrorCode = NULL, CompletedAtUtc = @CompletedAtUtc, UpdatedAtUtc = @CompletedAtUtc
        WHERE Id = @JobId AND Status = 1 AND LeaseId = @LeaseId;
        EXEC dbo.FundingPlatform_usp_AiExplanationRun_TryFinalize
            @AiExplanationRunId = @RunId, @NowUtc = @CompletedAtUtc;
        IF @StartedTransaction = 1 COMMIT TRANSACTION;
        SELECT CONVERT(BIT, 1) AS Succeeded, CONVERT(BIT, 0) AS WasReplay;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_AiExplanationComplete;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AiExplanationJob_Fail
    @JobPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @ErrorCode NVARCHAR(50),
    @Retryable BIT,
    @ProviderCallMayHaveBeenCharged BIT,
    @FailedAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @JobPublicId IS NULL OR @LeaseId IS NULL OR @FailedAtUtc IS NULL
       OR @ErrorCode NOT IN
          (N'explanation-provider-unavailable', N'explanation-provider-throttled',
           N'explanation-provider-timeout', N'explanation-provider-invalid-response',
           N'explanation-input-invalid', N'explanation-configuration-invalid',
           N'internal-error')
        THROW 54438, N'Bounded explanation failure metadata is required.', 1;
    DECLARE @JobId BIGINT, @RunId BIGINT, @ReservationId BIGINT;
    DECLARE @ConfigId INT, @BudgetMonth DATE, @ReservedCost DECIMAL(19,6);
    DECLARE @AttemptCount TINYINT, @MaximumAttempts TINYINT;
    BEGIN TRANSACTION;
    BEGIN TRY
        SELECT @JobId = jobs.Id, @RunId = runs.Id,
               @ConfigId = configurations.Id, @AttemptCount = jobs.AttemptCount,
               @MaximumAttempts = configurations.MaximumAttempts
        FROM dbo.FundingPlatform_AiExplanationJobs AS jobs WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_AiExplanationRuns AS runs WITH (UPDLOCK, HOLDLOCK)
            ON runs.Id = jobs.AiExplanationRunId AND runs.Status = 0
        INNER JOIN dbo.FundingPlatform_AiExplanationConfigurations AS configurations
            ON configurations.Id = runs.AiExplanationConfigurationId
        WHERE jobs.PublicId = @JobPublicId AND jobs.Status = 1
          AND jobs.LeaseId = @LeaseId AND jobs.LeaseUntilUtc > @FailedAtUtc;
        IF @JobId IS NULL
        BEGIN COMMIT TRANSACTION; SELECT CONVERT(BIT, 0) AS Succeeded; RETURN; END;
        SELECT @ReservationId = Id, @BudgetMonth = BudgetMonth,
               @ReservedCost = ReservedCostUsd
        FROM dbo.FundingPlatform_AiExplanationBudgetReservations WITH (UPDLOCK, HOLDLOCK)
        WHERE AiExplanationJobId = @JobId AND LeaseId = @LeaseId AND Status = 0;
        IF @ReservationId IS NULL THROW 54434, N'Active budget reservation is required.', 1;
        IF @ProviderCallMayHaveBeenCharged = 1
        BEGIN
            UPDATE dbo.FundingPlatform_AiExplanationBudgetReservations
            SET Status = 1, ConsumedCostUsd = ReservedCostUsd, FinalizedAtUtc = @FailedAtUtc
            WHERE Id = @ReservationId;
            INSERT INTO dbo.FundingPlatform_AiExplanationUsageLedger
                (AiExplanationJobId, BudgetReservationId, AiExplanationConfigurationId,
                 BudgetMonth, InputTokens, OutputTokens, EstimatedCostUsd,
                 LatencyMilliseconds, OutcomeCode, IsEstimatedUncertain, RecordedAtUtc)
            VALUES
                (@JobId, @ReservationId, @ConfigId, @BudgetMonth, NULL, NULL,
                 @ReservedCost, 0, N'charge-uncertain', 1, @FailedAtUtc);
        END
        ELSE
            UPDATE dbo.FundingPlatform_AiExplanationBudgetReservations
            SET Status = 2, FinalizedAtUtc = @FailedAtUtc WHERE Id = @ReservationId;
        DECLARE @WillRetry BIT =
            CASE WHEN @Retryable = 1 AND @AttemptCount < @MaximumAttempts THEN 1 ELSE 0 END;
        UPDATE dbo.FundingPlatform_AiExplanationJobs
        SET Status = CASE WHEN @WillRetry = 1 THEN 3 ELSE 4 END,
            LeaseId = NULL, LeaseOwnerHash = NULL, LeaseUntilUtc = NULL,
            NextAttemptAtUtc = CASE WHEN @WillRetry = 1
                THEN DATEADD(SECOND, 30 * POWER(2, @AttemptCount), @FailedAtUtc)
                ELSE @FailedAtUtc END,
            ErrorCode = @ErrorCode, UpdatedAtUtc = @FailedAtUtc,
            CompletedAtUtc = CASE WHEN @WillRetry = 1 THEN NULL ELSE @FailedAtUtc END
        WHERE Id = @JobId;
        IF @WillRetry = 0
            EXEC dbo.FundingPlatform_usp_AiExplanationRun_TryFinalize
                @AiExplanationRunId = @RunId, @NowUtc = @FailedAtUtc;
        COMMIT TRANSACTION;
        SELECT CONVERT(BIT, 1) AS Succeeded;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AiExplanationRun_AdminGet
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @RunPublicId UNIQUEIDENTIFIER,
    @PageNumber INT,
    @PageSize INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @AdminUserPublicId IS NULL OR @RunPublicId IS NULL
       OR @PageNumber NOT BETWEEN 1 AND 10000 OR @PageSize NOT BETWEEN 1 AND 50
        THROW 54439, N'Bounded explanation report query is required.', 1;
    DECLARE @UserId BIGINT, @RunId BIGINT;
    EXEC dbo.FundingPlatform_usp_AdminActor_Lock
        @AdminUserPublicId = @AdminUserPublicId, @ActorUserId = @UserId OUTPUT;
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_UserRoles AS userRoles
        INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
        WHERE userRoles.UserId = @UserId
          AND roles.NormalizedName IN (N'ADMIN', N'SUPERADMIN'))
        THROW 54424, N'Active Admin or SuperAdmin role with MFA is required.', 1;
    SET @RunId =
        (SELECT Id FROM dbo.FundingPlatform_AiExplanationRuns WHERE PublicId = @RunPublicId);
    IF @RunId IS NULL RETURN;
    SELECT summaries.PublicId, summaries.SourceSemanticEvaluationRunPublicId,
           summaries.Status, summaries.ExplanationConfigurationVersion,
           summaries.ProviderCode, summaries.ModelCode,
           summaries.InputSchemaVersion, summaries.OutputSchemaVersion,
           summaries.PromptVersion, summaries.ItemCount, summaries.CompletedCount,
           summaries.FailedCount, summaries.TotalEstimatedCostUsd,
           (SELECT COUNT(*) FROM dbo.FundingPlatform_AiExplanationResults
            WHERE AiExplanationRunId = @RunId) AS ResultCount,
           @PageNumber AS PageNumber, @PageSize AS PageSize,
           summaries.CreatedAtUtc, summaries.CompletedAtUtc
    FROM dbo.FundingPlatform_ifn_AiExplanationRunSummaries() AS summaries
    WHERE summaries.AiExplanationRunId = @RunId;
    SELECT results.CaseOrdinal, results.Assessment, results.Summary,
           results.PrimaryReasonCode, results.CitedRuleCodesJson,
           results.InputTokens, results.OutputTokens, results.EstimatedCostUsd,
           results.LatencyMilliseconds, results.CreatedAtUtc
    FROM dbo.FundingPlatform_AiExplanationResults AS results
    WHERE results.AiExplanationRunId = @RunId
    ORDER BY results.CaseOrdinal
    OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_AiStructuredOutputProviderPolicy_AdminRegister
    TO FundingPlatform_SemanticAdminRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_AiExplanationConfiguration_AdminPublishOpenAi
    TO FundingPlatform_SemanticAdminRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_AiExplanationRun_Create
    TO FundingPlatform_SemanticAdminRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_AiExplanationRun_AdminGet
    TO FundingPlatform_SemanticAdminRole;

GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_AiExplanationJob_Claim
    TO FundingPlatform_SemanticWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_AiExplanationJob_GetInput
    TO FundingPlatform_SemanticWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_AiExplanationJob_RenewLease
    TO FundingPlatform_SemanticWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_AiExplanationJob_Complete
    TO FundingPlatform_SemanticWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_AiExplanationJob_Fail
    TO FundingPlatform_SemanticWorkerRole;

DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiExplanationConfigurations
    TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiExplanationConfigurationPublishRequests
    TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiExplanationRuns TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiExplanationRunRequests TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiExplanationJobs TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiExplanationBudgetReservations
    TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiExplanationUsageLedger
    TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiExplanationResults TO FundingPlatform_SemanticWorkerRole;

DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiExplanationConfigurations
    TO FundingPlatform_SemanticAdminRole;
DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiExplanationConfigurationPublishRequests
    TO FundingPlatform_SemanticAdminRole;
DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiExplanationRuns TO FundingPlatform_SemanticAdminRole;
DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiExplanationRunRequests TO FundingPlatform_SemanticAdminRole;
DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiExplanationJobs TO FundingPlatform_SemanticAdminRole;
DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiExplanationBudgetReservations
    TO FundingPlatform_SemanticAdminRole;
DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiExplanationUsageLedger
    TO FundingPlatform_SemanticAdminRole;
DENY SELECT, INSERT, UPDATE, DELETE
    ON OBJECT::dbo.FundingPlatform_AiExplanationResults TO FundingPlatform_SemanticAdminRole;
GO
