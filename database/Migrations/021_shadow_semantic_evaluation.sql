/* FundingPlatform FASE 9B-A - bounded embeddings and shadow-only semantic evaluation.
   This forward-only migration depends on 019 and 020. It never changes a 9A score,
   classification or current flag, and it persists no prompt, canonical input or raw response. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_FundingApplications', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ProjectMatchingRuns', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ProjectFundingMatches', N'U') IS NULL
    THROW 54101, N'FASE 9B-A requires migrations 019 and 020 to be applied first.', 1;

CREATE TABLE dbo.FundingPlatform_SemanticConfigurations
(
    Id INT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_SemanticConfigurations_PublicId DEFAULT (NEWSEQUENTIALID()),
    Code NVARCHAR(50) NOT NULL,
    Version INT NOT NULL,
    ProviderCode NVARCHAR(50) NOT NULL,
    ModelCode NVARCHAR(128) NOT NULL,
    Dimensions SMALLINT NOT NULL,
    PurposeCode NVARCHAR(32) NOT NULL,
    ProjectTemplateVersion NVARCHAR(50) NOT NULL,
    OpportunityTemplateVersion NVARCHAR(50) NOT NULL,
    NormalizationVersion NVARCHAR(50) NOT NULL,
    DistanceMetric TINYINT NOT NULL,
    CalibrationVersion NVARCHAR(50) NOT NULL,
    MaximumInputUtf8Bytes SMALLINT NOT NULL,
    MaximumBatchSize TINYINT NOT NULL,
    MaximumAttempts TINYINT NOT NULL,
    MaximumCostUsdPerEmbedding DECIMAL(19,6) NOT NULL,
    MonthlyBudgetUsd DECIMAL(19,6) NOT NULL,
    ConfigurationFingerprint BINARY(32) NOT NULL,
    IsLocalFake BIT NOT NULL,
    IsActive BIT NOT NULL,
    PublishedAtUtc DATETIME2(3) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_SemanticConfigurations PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SemanticConfigurations_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_SemanticConfigurations_CodeVersion UNIQUE (Code, Version),
    CONSTRAINT FundingPlatform_UQ_SemanticConfigurations_IdVersion UNIQUE (Id, Version),
    CONSTRAINT FundingPlatform_CK_SemanticConfigurations_FrozenContract CHECK
        (Dimensions = 1536
         AND PurposeCode COLLATE Latin1_General_100_BIN2 =
             N'matching' COLLATE Latin1_General_100_BIN2
         AND ProjectTemplateVersion COLLATE Latin1_General_100_BIN2 =
             N'project-semantic-v1' COLLATE Latin1_General_100_BIN2
         AND OpportunityTemplateVersion COLLATE Latin1_General_100_BIN2 =
             N'opportunity-semantic-v1' COLLATE Latin1_General_100_BIN2
         AND NormalizationVersion COLLATE Latin1_General_100_BIN2 =
             N'semantic-text-v1' COLLATE Latin1_General_100_BIN2
         AND DistanceMetric = 1
         AND CalibrationVersion COLLATE Latin1_General_100_BIN2 =
             N'cosine-linear-shadow-v1' COLLATE Latin1_General_100_BIN2),
    CONSTRAINT FundingPlatform_CK_SemanticConfigurations_Bounds CHECK
        (Version >= 1 AND MaximumInputUtf8Bytes = 8192
         AND MaximumBatchSize BETWEEN 1 AND 64 AND MaximumAttempts = 3
         AND MaximumCostUsdPerEmbedding BETWEEN 0 AND 1
         AND MonthlyBudgetUsd BETWEEN MaximumCostUsdPerEmbedding AND 10000
         AND (IsLocalFake = 0 OR MaximumCostUsdPerEmbedding = 0)),
    CONSTRAINT FundingPlatform_CK_SemanticConfigurations_Text CHECK
        (LEN(LTRIM(RTRIM(Code))) BETWEEN 1 AND 50
         AND DATALENGTH(Code) = DATALENGTH(LTRIM(RTRIM(Code)))
         AND Code NOT LIKE N'%[^a-z0-9._-]%' COLLATE Latin1_General_100_BIN2
         AND LEN(LTRIM(RTRIM(ProviderCode))) BETWEEN 1 AND 50
         AND LEN(LTRIM(RTRIM(ModelCode))) BETWEEN 1 AND 128
         AND DATALENGTH(ProviderCode) = DATALENGTH(LTRIM(RTRIM(ProviderCode)))
         AND DATALENGTH(ModelCode) = DATALENGTH(LTRIM(RTRIM(ModelCode)))
         AND DATALENGTH(PurposeCode) = DATALENGTH(LTRIM(RTRIM(PurposeCode)))
         AND DATALENGTH(ProjectTemplateVersion) =
             DATALENGTH(LTRIM(RTRIM(ProjectTemplateVersion)))
         AND DATALENGTH(OpportunityTemplateVersion) =
             DATALENGTH(LTRIM(RTRIM(OpportunityTemplateVersion)))
         AND DATALENGTH(NormalizationVersion) =
             DATALENGTH(LTRIM(RTRIM(NormalizationVersion)))
         AND DATALENGTH(CalibrationVersion) =
             DATALENGTH(LTRIM(RTRIM(CalibrationVersion)))
         AND LEN(CONCAT(Code, N'-v', Version)) <= 64
         AND LEN(LTRIM(RTRIM(CalibrationVersion))) BETWEEN 1 AND 50
         AND ProviderCode NOT LIKE N'%[^A-Za-z0-9._-]%' COLLATE Latin1_General_100_BIN2
         AND ModelCode NOT LIKE N'%[^A-Za-z0-9._-]%' COLLATE Latin1_General_100_BIN2
         AND PurposeCode NOT LIKE N'%[^A-Za-z0-9._-]%' COLLATE Latin1_General_100_BIN2
         AND ProjectTemplateVersion NOT LIKE N'%[^A-Za-z0-9._-]%' COLLATE Latin1_General_100_BIN2
         AND OpportunityTemplateVersion NOT LIKE N'%[^A-Za-z0-9._-]%' COLLATE Latin1_General_100_BIN2
         AND NormalizationVersion NOT LIKE N'%[^A-Za-z0-9._-]%' COLLATE Latin1_General_100_BIN2
         AND CalibrationVersion NOT LIKE N'%[^A-Za-z0-9._-]%' COLLATE Latin1_General_100_BIN2)
    ,CONSTRAINT FundingPlatform_CK_SemanticConfigurations_LocalFake CHECK
        ((IsLocalFake = 1
          AND ProviderCode COLLATE Latin1_General_100_BIN2 =
              N'development-deterministic' COLLATE Latin1_General_100_BIN2
          AND ModelCode COLLATE Latin1_General_100_BIN2 =
              N'lexical-hash-1536-v1' COLLATE Latin1_General_100_BIN2)
         OR
         (IsLocalFake = 0 AND NOT
             (ProviderCode COLLATE Latin1_General_100_BIN2 =
                  N'development-deterministic' COLLATE Latin1_General_100_BIN2
              AND ModelCode COLLATE Latin1_General_100_BIN2 =
                  N'lexical-hash-1536-v1' COLLATE Latin1_General_100_BIN2)))
);

CREATE UNIQUE INDEX FundingPlatform_UQ_SemanticConfigurations_Active
    ON dbo.FundingPlatform_SemanticConfigurations (IsActive)
    WHERE IsActive = 1;

CREATE TABLE dbo.FundingPlatform_SemanticEvaluationSets
(
    Id INT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_SemanticEvaluationSets_PublicId DEFAULT (NEWSEQUENTIALID()),
    Code NVARCHAR(50) NOT NULL,
    Version INT NOT NULL,
    ManifestHash BINARY(32) NOT NULL,
    ProvenanceCode NVARCHAR(100) NOT NULL,
    SplitPolicyVersion NVARCHAR(50) NOT NULL,
    DeclaredProjectCount INT NOT NULL,
    DeclaredOpportunityCount INT NOT NULL,
    DeclaredLabelCount INT NOT NULL,
    ReviewedByUserId BIGINT NOT NULL,
    ReviewedAtUtc DATETIME2(3) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_SemanticEvaluationSets PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SemanticEvaluationSets_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_SemanticEvaluationSets_CodeVersion UNIQUE (Code, Version),
    CONSTRAINT FundingPlatform_FK_SemanticEvaluationSets_Reviewer
        FOREIGN KEY (ReviewedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_SemanticEvaluationSets_Bounds CHECK
        (Version >= 1 AND DeclaredProjectCount >= 30
         AND DeclaredProjectCount <= 5000
         AND DeclaredOpportunityCount BETWEEN 100 AND 5000
         AND DeclaredLabelCount BETWEEN 300 AND 5000),
    CONSTRAINT FundingPlatform_CK_SemanticEvaluationSets_Text CHECK
        (LEN(LTRIM(RTRIM(Code))) BETWEEN 1 AND 50
         AND Code NOT LIKE N'%[^a-z0-9._-]%' COLLATE Latin1_General_100_BIN2
         AND LEN(CONCAT(Code, N'-v', Version)) <= 64
         AND LEN(LTRIM(RTRIM(ProvenanceCode))) BETWEEN 1 AND 100
         AND LEN(LTRIM(RTRIM(SplitPolicyVersion))) BETWEEN 1 AND 50
         AND ReviewedAtUtc <= CreatedAtUtc)
);

CREATE TABLE dbo.FundingPlatform_SemanticEvaluationCases
(
    EvaluationSetId INT NOT NULL,
    Ordinal INT NOT NULL,
    CasePublicId UNIQUEIDENTIFIER NOT NULL,
    Split TINYINT NOT NULL,
    ProjectMatchingRunId BIGINT NOT NULL,
    ProjectFundingMatchId BIGINT NOT NULL,
    OrganizationId BIGINT NOT NULL,
    ProjectId BIGINT NOT NULL,
    ProjectVersion INT NOT NULL,
    FundingOpportunityId BIGINT NOT NULL,
    FundingContentVersion INT NOT NULL,
    ProjectContentHash BINARY(32) NOT NULL,
    OpportunityContentHash BINARY(32) NOT NULL,
    RelevanceLabel TINYINT NOT NULL,
    LabelProvenanceHash BINARY(32) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_SemanticEvaluationCases
        PRIMARY KEY (EvaluationSetId, Ordinal),
    CONSTRAINT FundingPlatform_UQ_SemanticEvaluationCases_PublicId UNIQUE (CasePublicId),
    CONSTRAINT FundingPlatform_UQ_SemanticEvaluationCases_Pair
        UNIQUE (EvaluationSetId, ProjectFundingMatchId),
    CONSTRAINT FundingPlatform_UQ_SemanticEvaluationCases_RunCase
        UNIQUE (EvaluationSetId, Ordinal, ProjectMatchingRunId, ProjectFundingMatchId),
    CONSTRAINT FundingPlatform_FK_SemanticEvaluationCases_Set
        FOREIGN KEY (EvaluationSetId) REFERENCES dbo.FundingPlatform_SemanticEvaluationSets (Id),
    CONSTRAINT FundingPlatform_FK_SemanticEvaluationCases_MatchingRun
        FOREIGN KEY (ProjectMatchingRunId, OrganizationId, ProjectId)
        REFERENCES dbo.FundingPlatform_ProjectMatchingRuns (Id, OrganizationId, ProjectId),
    CONSTRAINT FundingPlatform_FK_SemanticEvaluationCases_ProjectVersion
        FOREIGN KEY (ProjectId, ProjectVersion)
        REFERENCES dbo.FundingPlatform_ProjectVersions (ProjectId, ProjectVersion),
    CONSTRAINT FundingPlatform_FK_SemanticEvaluationCases_OpportunityVersion
        FOREIGN KEY (FundingOpportunityId, FundingContentVersion)
        REFERENCES dbo.FundingPlatform_FundingOpportunityVersions
            (FundingOpportunityId, ContentVersion),
    CONSTRAINT FundingPlatform_CK_SemanticEvaluationCases_Ordinal CHECK (Ordinal >= 1),
    /* 0=Dev, 1=Test. Labels: 0=Irrelevant, 1=Relevant, 2=HighlyRelevant. */
    CONSTRAINT FundingPlatform_CK_SemanticEvaluationCases_Enums CHECK
        (Split IN (0, 1) AND RelevanceLabel BETWEEN 0 AND 2)
);

CREATE INDEX FundingPlatform_IX_SemanticEvaluationCases_Lookup
    ON dbo.FundingPlatform_SemanticEvaluationCases
       (EvaluationSetId, ProjectContentHash, OpportunityContentHash)
    INCLUDE (Split, RelevanceLabel);

/* 021 adds only a relational identity index to immutable 020 history; no 9A row
   or scoring column is modified. It lets corpus cases bind a match and all of
   its frozen subject/version coordinates with one FK. */
CREATE UNIQUE INDEX FundingPlatform_UQ_ProjectFundingMatches_SemanticCaseIdentity
    ON dbo.FundingPlatform_ProjectFundingMatches
       (Id, MatchRunId, OrganizationId, ProjectId, ProjectVersion,
        FundingOpportunityId, FundingContentVersion);

ALTER TABLE dbo.FundingPlatform_SemanticEvaluationCases
ADD CONSTRAINT FundingPlatform_FK_SemanticEvaluationCases_MatchIdentity
    FOREIGN KEY (ProjectFundingMatchId, ProjectMatchingRunId, OrganizationId,
                 ProjectId, ProjectVersion, FundingOpportunityId, FundingContentVersion)
    REFERENCES dbo.FundingPlatform_ProjectFundingMatches
        (Id, MatchRunId, OrganizationId, ProjectId, ProjectVersion,
         FundingOpportunityId, FundingContentVersion);

CREATE TABLE dbo.FundingPlatform_SemanticEmbeddingJobs
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_SemanticEmbeddingJobs_PublicId DEFAULT (NEWSEQUENTIALID()),
    SemanticConfigurationId INT NOT NULL,
    SemanticConfigurationVersion INT NOT NULL,
    SubjectType TINYINT NOT NULL,
    OrganizationId BIGINT NULL,
    ProjectId BIGINT NULL,
    ProjectVersion INT NULL,
    FundingOpportunityId BIGINT NULL,
    FundingContentVersion INT NULL,
    SubjectContentHash BINARY(32) NOT NULL,
    InputContentHash BINARY(32) NOT NULL,
    ContentAddress BINARY(32) NOT NULL,
    JobGeneration SMALLINT NOT NULL,
    AllowHistorical BIT NOT NULL,
    Status TINYINT NOT NULL,
    AttemptCount TINYINT NOT NULL,
    MaximumAttempts TINYINT NOT NULL,
    NextAttemptAtUtc DATETIME2(3) NOT NULL,
    LeaseId UNIQUEIDENTIFIER NULL,
    LeaseOwnerHash BINARY(32) NULL,
    LeaseUntilUtc DATETIME2(3) NULL,
    ErrorCode NVARCHAR(50) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    StartedAtUtc DATETIME2(3) NULL,
    CompletedAtUtc DATETIME2(3) NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_SemanticEmbeddingJobs PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SemanticEmbeddingJobs_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_SemanticEmbeddingJobs_ContentAddressGeneration
        UNIQUE (ContentAddress, JobGeneration),
    CONSTRAINT FundingPlatform_UQ_SemanticEmbeddingJobs_IdSubject
        UNIQUE (Id, SubjectType, OrganizationId, ProjectId, ProjectVersion,
                FundingOpportunityId, FundingContentVersion),
    CONSTRAINT FundingPlatform_FK_SemanticEmbeddingJobs_Configuration
        FOREIGN KEY (SemanticConfigurationId, SemanticConfigurationVersion)
        REFERENCES dbo.FundingPlatform_SemanticConfigurations (Id, Version),
    CONSTRAINT FundingPlatform_FK_SemanticEmbeddingJobs_ProjectTenant
        FOREIGN KEY (ProjectId, OrganizationId)
        REFERENCES dbo.FundingPlatform_Projects (Id, OrganizationId),
    CONSTRAINT FundingPlatform_FK_SemanticEmbeddingJobs_ProjectVersion
        FOREIGN KEY (ProjectId, ProjectVersion)
        REFERENCES dbo.FundingPlatform_ProjectVersions (ProjectId, ProjectVersion),
    CONSTRAINT FundingPlatform_FK_SemanticEmbeddingJobs_OpportunityVersion
        FOREIGN KEY (FundingOpportunityId, FundingContentVersion)
        REFERENCES dbo.FundingPlatform_FundingOpportunityVersions
            (FundingOpportunityId, ContentVersion),
    /* 0 Project tenant-private, 1 Opportunity global. */
    CONSTRAINT FundingPlatform_CK_SemanticEmbeddingJobs_Subject CHECK
        ((SubjectType = 0 AND OrganizationId IS NOT NULL AND ProjectId IS NOT NULL
          AND ProjectVersion IS NOT NULL AND FundingOpportunityId IS NULL
          AND FundingContentVersion IS NULL)
         OR
         (SubjectType = 1 AND OrganizationId IS NULL AND ProjectId IS NULL
          AND ProjectVersion IS NULL AND FundingOpportunityId IS NOT NULL
          AND FundingContentVersion IS NOT NULL)),
    /* 0 Queued, 1 Processing, 2 Succeeded, 3 RetryScheduled,
       4 PermanentFailed, 5 SkippedStale. */
    CONSTRAINT FundingPlatform_CK_SemanticEmbeddingJobs_Status CHECK (Status BETWEEN 0 AND 5),
    CONSTRAINT FundingPlatform_CK_SemanticEmbeddingJobs_Attempts CHECK
        (JobGeneration BETWEEN 1 AND 32767
         AND MaximumAttempts BETWEEN 1 AND 3 AND AttemptCount BETWEEN 0 AND MaximumAttempts),
    CONSTRAINT FundingPlatform_CK_SemanticEmbeddingJobs_Lease CHECK
        ((Status = 1 AND LeaseId IS NOT NULL AND LeaseOwnerHash IS NOT NULL
                     AND LeaseUntilUtc IS NOT NULL)
         OR (Status <> 1 AND LeaseId IS NULL AND LeaseOwnerHash IS NULL
                         AND LeaseUntilUtc IS NULL)),
    CONSTRAINT FundingPlatform_CK_SemanticEmbeddingJobs_Terminal CHECK
        ((Status IN (2, 4, 5) AND CompletedAtUtc IS NOT NULL)
         OR (Status IN (0, 1, 3) AND CompletedAtUtc IS NULL)),
    CONSTRAINT FundingPlatform_CK_SemanticEmbeddingJobs_Error CHECK
        ((Status IN (3, 4, 5) AND ErrorCode IS NOT NULL)
         OR (Status IN (0, 1, 2) AND ErrorCode IS NULL)),
    CONSTRAINT FundingPlatform_CK_SemanticEmbeddingJobs_ErrorAllowlist CHECK
        (ErrorCode IS NULL OR ErrorCode IN
         (N'embedding-provider-timeout', N'embedding-provider-throttled',
          N'embedding-provider-unavailable', N'embedding-provider-invalid-response',
          N'semantic-job-invalid', N'semantic-input-invalid',
          N'semantic-input-hash-mismatch', N'semantic-input-privacy-rejected',
          N'budget-exhausted', N'stale-subject', N'input-rejected', N'invalid-canonical-input',
          N'input-too-large', N'pii-email-detected', N'pii-url-detected',
          N'pii-rut-detected', N'lease-expired', N'internal-error')),
    CONSTRAINT FundingPlatform_CK_SemanticEmbeddingJobs_SkippedStale CHECK
        (Status <> 5 OR ErrorCode = N'stale-subject'),
    CONSTRAINT FundingPlatform_CK_SemanticEmbeddingJobs_Times CHECK
        (CreatedAtUtc <= UpdatedAtUtc
         AND (StartedAtUtc IS NULL OR StartedAtUtc >= CreatedAtUtc)
         AND (CompletedAtUtc IS NULL OR CompletedAtUtc >= CreatedAtUtc))
);

CREATE INDEX FundingPlatform_IX_SemanticEmbeddingJobs_Claim
    ON dbo.FundingPlatform_SemanticEmbeddingJobs (Status, NextAttemptAtUtc, Id)
    INCLUDE (SemanticConfigurationId, AttemptCount, MaximumAttempts)
    WHERE Status IN (0, 3);

CREATE INDEX FundingPlatform_IX_SemanticEmbeddingJobs_Project
    ON dbo.FundingPlatform_SemanticEmbeddingJobs
       (OrganizationId, ProjectId, ProjectVersion, SemanticConfigurationId)
    INCLUDE (PublicId, Status, InputContentHash)
    WHERE SubjectType = 0;

CREATE INDEX FundingPlatform_IX_SemanticEmbeddingJobs_Opportunity
    ON dbo.FundingPlatform_SemanticEmbeddingJobs
       (FundingOpportunityId, FundingContentVersion, SemanticConfigurationId)
    INCLUDE (PublicId, Status, InputContentHash)
    WHERE SubjectType = 1;

CREATE TABLE dbo.FundingPlatform_SemanticEmbeddings
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_SemanticEmbeddings_PublicId DEFAULT (NEWSEQUENTIALID()),
    SourceJobId BIGINT NOT NULL,
    SemanticConfigurationId INT NOT NULL,
    SemanticConfigurationVersion INT NOT NULL,
    SubjectType TINYINT NOT NULL,
    OrganizationId BIGINT NULL,
    ProjectId BIGINT NULL,
    ProjectVersion INT NULL,
    FundingOpportunityId BIGINT NULL,
    FundingContentVersion INT NULL,
    SubjectContentHash BINARY(32) NOT NULL,
    InputContentHash BINARY(32) NOT NULL,
    ContentAddress BINARY(32) NOT NULL,
    EmbeddingVersion INT NOT NULL,
    ProviderCode NVARCHAR(50) NOT NULL,
    EffectiveModelCode NVARCHAR(128) NOT NULL,
    Dimensions SMALLINT NOT NULL,
    PurposeCode NVARCHAR(32) NOT NULL,
    TemplateVersion NVARCHAR(50) NOT NULL,
    NormalizationVersion NVARCHAR(50) NOT NULL,
    Embedding VECTOR(1536) NOT NULL,
    EmbeddingHash BINARY(32) NOT NULL,
    ProviderRequestIdHash BINARY(32) NULL,
    IsCurrent BIT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    RetiredAtUtc DATETIME2(3) NULL,
    CONSTRAINT FundingPlatform_PK_SemanticEmbeddings PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SemanticEmbeddings_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_SemanticEmbeddings_SourceJob UNIQUE (SourceJobId),
    CONSTRAINT FundingPlatform_UQ_SemanticEmbeddings_ContentAddress UNIQUE (ContentAddress),
    CONSTRAINT FundingPlatform_UQ_SemanticEmbeddings_IdSubject
        UNIQUE (Id, SubjectType, OrganizationId, ProjectId, ProjectVersion,
                FundingOpportunityId, FundingContentVersion),
    CONSTRAINT FundingPlatform_FK_SemanticEmbeddings_JobSubject
        FOREIGN KEY (SourceJobId, SubjectType, OrganizationId, ProjectId, ProjectVersion,
                     FundingOpportunityId, FundingContentVersion)
        REFERENCES dbo.FundingPlatform_SemanticEmbeddingJobs
            (Id, SubjectType, OrganizationId, ProjectId, ProjectVersion,
             FundingOpportunityId, FundingContentVersion),
    CONSTRAINT FundingPlatform_FK_SemanticEmbeddings_Configuration
        FOREIGN KEY (SemanticConfigurationId, SemanticConfigurationVersion)
        REFERENCES dbo.FundingPlatform_SemanticConfigurations (Id, Version),
    CONSTRAINT FundingPlatform_FK_SemanticEmbeddings_ProjectTenant
        FOREIGN KEY (ProjectId, OrganizationId)
        REFERENCES dbo.FundingPlatform_Projects (Id, OrganizationId),
    CONSTRAINT FundingPlatform_FK_SemanticEmbeddings_ProjectVersion
        FOREIGN KEY (ProjectId, ProjectVersion)
        REFERENCES dbo.FundingPlatform_ProjectVersions (ProjectId, ProjectVersion),
    CONSTRAINT FundingPlatform_FK_SemanticEmbeddings_OpportunityVersion
        FOREIGN KEY (FundingOpportunityId, FundingContentVersion)
        REFERENCES dbo.FundingPlatform_FundingOpportunityVersions
            (FundingOpportunityId, ContentVersion),
    CONSTRAINT FundingPlatform_CK_SemanticEmbeddings_Subject CHECK
        ((SubjectType = 0 AND OrganizationId IS NOT NULL AND ProjectId IS NOT NULL
          AND ProjectVersion IS NOT NULL AND FundingOpportunityId IS NULL
          AND FundingContentVersion IS NULL)
         OR
         (SubjectType = 1 AND OrganizationId IS NULL AND ProjectId IS NULL
          AND ProjectVersion IS NULL AND FundingOpportunityId IS NOT NULL
          AND FundingContentVersion IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_SemanticEmbeddings_FrozenContract CHECK
        (Dimensions = 1536 AND PurposeCode = N'matching'
         AND NormalizationVersion = N'semantic-text-v1'),
    CONSTRAINT FundingPlatform_CK_SemanticEmbeddings_Version CHECK (EmbeddingVersion >= 1),
    CONSTRAINT FundingPlatform_CK_SemanticEmbeddings_Current CHECK
        ((IsCurrent = 1 AND RetiredAtUtc IS NULL)
         OR (IsCurrent = 0 AND RetiredAtUtc IS NOT NULL AND RetiredAtUtc >= CreatedAtUtc))
);

CREATE UNIQUE INDEX FundingPlatform_UQ_SemanticEmbeddings_CurrentProject
    ON dbo.FundingPlatform_SemanticEmbeddings (ProjectId, SemanticConfigurationId)
    WHERE SubjectType = 0 AND IsCurrent = 1;

CREATE UNIQUE INDEX FundingPlatform_UQ_SemanticEmbeddings_CurrentOpportunity
    ON dbo.FundingPlatform_SemanticEmbeddings (FundingOpportunityId, SemanticConfigurationId)
    WHERE SubjectType = 1 AND IsCurrent = 1;

CREATE INDEX FundingPlatform_IX_SemanticEmbeddings_ProjectVersion
    ON dbo.FundingPlatform_SemanticEmbeddings
       (OrganizationId, ProjectId, ProjectVersion, SemanticConfigurationId)
    INCLUDE (PublicId, InputContentHash, IsCurrent);

CREATE INDEX FundingPlatform_IX_SemanticEmbeddings_OpportunityVersion
    ON dbo.FundingPlatform_SemanticEmbeddings
       (FundingOpportunityId, FundingContentVersion, SemanticConfigurationId)
    INCLUDE (PublicId, InputContentHash, IsCurrent);

CREATE TABLE dbo.FundingPlatform_SemanticBudgetReservations
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_SemanticBudgetReservations_PublicId DEFAULT (NEWSEQUENTIALID()),
    SemanticConfigurationId INT NOT NULL,
    EmbeddingJobId BIGINT NOT NULL,
    BudgetMonth DATE NOT NULL,
    ReservedCostUsd DECIMAL(19,6) NOT NULL,
    ConsumedCostUsd DECIMAL(19,6) NULL,
    Status TINYINT NOT NULL,
    LeaseId UNIQUEIDENTIFIER NOT NULL,
    ExpiresAtUtc DATETIME2(3) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    FinalizedAtUtc DATETIME2(3) NULL,
    CONSTRAINT FundingPlatform_PK_SemanticBudgetReservations PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SemanticBudgetReservations_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_SemanticBudgetReservations_JobLease
        UNIQUE (EmbeddingJobId, LeaseId),
    CONSTRAINT FundingPlatform_FK_SemanticBudgetReservations_Configuration
        FOREIGN KEY (SemanticConfigurationId)
        REFERENCES dbo.FundingPlatform_SemanticConfigurations (Id),
    CONSTRAINT FundingPlatform_FK_SemanticBudgetReservations_Job
        FOREIGN KEY (EmbeddingJobId)
        REFERENCES dbo.FundingPlatform_SemanticEmbeddingJobs (Id),
    /* 0 active, 1 consumed, 2 released, 3 expired. */
    CONSTRAINT FundingPlatform_CK_SemanticBudgetReservations_State CHECK
        ((Status = 0 AND ConsumedCostUsd IS NULL AND FinalizedAtUtc IS NULL)
         OR (Status = 1 AND ConsumedCostUsd BETWEEN 0 AND ReservedCostUsd
                        AND FinalizedAtUtc IS NOT NULL)
         OR (Status IN (2, 3) AND ConsumedCostUsd IS NULL
                             AND FinalizedAtUtc IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_SemanticBudgetReservations_Bounds CHECK
        (ReservedCostUsd BETWEEN 0 AND 1
         AND ExpiresAtUtc > CreatedAtUtc
         AND (FinalizedAtUtc IS NULL OR FinalizedAtUtc >= CreatedAtUtc))
);

CREATE INDEX FundingPlatform_IX_SemanticBudgetReservations_Month
    ON dbo.FundingPlatform_SemanticBudgetReservations
       (SemanticConfigurationId, BudgetMonth, Status, ExpiresAtUtc)
    INCLUDE (ReservedCostUsd, ConsumedCostUsd);

CREATE TABLE dbo.FundingPlatform_SemanticUsageLedger
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    EmbeddingJobId BIGINT NOT NULL,
    BudgetReservationId BIGINT NOT NULL,
    SemanticConfigurationId INT NOT NULL,
    OrganizationId BIGINT NULL,
    BudgetMonth DATE NOT NULL,
    InputTokens INT NULL,
    OutputTokens INT NULL,
    EstimatedCostUsd DECIMAL(19,6) NOT NULL,
    LatencyMilliseconds INT NOT NULL,
    OutcomeCode NVARCHAR(32) NOT NULL,
    IsEstimatedUncertain BIT NOT NULL,
    RecordedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_SemanticUsageLedger PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SemanticUsageLedger_Reservation UNIQUE (BudgetReservationId),
    CONSTRAINT FundingPlatform_FK_SemanticUsageLedger_Job
        FOREIGN KEY (EmbeddingJobId) REFERENCES dbo.FundingPlatform_SemanticEmbeddingJobs (Id),
    CONSTRAINT FundingPlatform_FK_SemanticUsageLedger_Reservation
        FOREIGN KEY (BudgetReservationId) REFERENCES dbo.FundingPlatform_SemanticBudgetReservations (Id),
    CONSTRAINT FundingPlatform_FK_SemanticUsageLedger_Configuration
        FOREIGN KEY (SemanticConfigurationId) REFERENCES dbo.FundingPlatform_SemanticConfigurations (Id),
    CONSTRAINT FundingPlatform_FK_SemanticUsageLedger_Organization
        FOREIGN KEY (OrganizationId) REFERENCES dbo.FundingPlatform_Organizations (Id),
    CONSTRAINT FundingPlatform_CK_SemanticUsageLedger_Bounds CHECK
        ((InputTokens IS NULL OR InputTokens BETWEEN 0 AND 8192)
         AND (OutputTokens IS NULL OR OutputTokens BETWEEN 0 AND 8192)
         AND EstimatedCostUsd BETWEEN 0 AND 1
         AND LatencyMilliseconds BETWEEN 0 AND 600000
         AND ((OutcomeCode = N'succeeded' AND IsEstimatedUncertain = 0)
              OR (OutcomeCode = N'charge-uncertain' AND IsEstimatedUncertain = 1)))
);

CREATE TABLE dbo.FundingPlatform_SemanticEvaluationRuns
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_SemanticEvaluationRuns_PublicId DEFAULT (NEWSEQUENTIALID()),
    SemanticConfigurationId INT NOT NULL,
    SemanticConfigurationVersion INT NOT NULL,
    EvaluationSetId INT NOT NULL,
    EvaluationSetVersion INT NOT NULL,
    SemanticConfigurationFingerprint BINARY(32) NOT NULL,
    EvaluationSetManifestHash BINARY(32) NOT NULL,
    Status TINYINT NOT NULL,
    ProjectCount INT NOT NULL,
    OpportunityCount INT NOT NULL,
    PairCount INT NOT NULL,
    PrimaryCohortCount INT NOT NULL,
    EvaluatedCount INT NOT NULL,
    LabelledCount INT NOT NULL,
    CoveragePercentage DECIMAL(5,2) NULL,
    SuccessPercentage DECIMAL(5,2) NULL,
    RecallAt10 DECIMAL(7,6) NULL,
    NdcgAt10 DECIMAL(7,6) NULL,
    BaselineNdcgAt10 DECIMAL(7,6) NULL,
    NdcgDelta DECIMAL(8,6) NULL,
    MrrAt10 DECIMAL(7,6) NULL,
    MeanRankDelta DECIMAL(9,4) NULL,
    TotalEstimatedCostUsd DECIMAL(19,6) NULL,
    P95LatencyMilliseconds INT NULL,
    HardFailPromotedCount INT NULL,
    IsPromotionEligible BIT NULL,
    CompletionLeaseId UNIQUEIDENTIFIER NULL,
    LeaseId UNIQUEIDENTIFIER NULL,
    LeaseOwnerHash BINARY(32) NULL,
    LeaseUntilUtc DATETIME2(3) NULL,
    AttemptCount TINYINT NOT NULL,
    NextAttemptAtUtc DATETIME2(3) NOT NULL,
    ErrorCode NVARCHAR(50) NULL,
    RequestedByUserId BIGINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    StartedAtUtc DATETIME2(3) NULL,
    CompletedAtUtc DATETIME2(3) NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    ActiveSlot AS (CASE WHEN Status IN (0, 1, 3) THEN CONVERT(TINYINT, 1) END) PERSISTED,
    CONSTRAINT FundingPlatform_PK_SemanticEvaluationRuns PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SemanticEvaluationRuns_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_SemanticEvaluationRuns_IdSet
        UNIQUE (Id, EvaluationSetId),
    CONSTRAINT FundingPlatform_UQ_SemanticEvaluationRuns_IdRequester
        UNIQUE (Id, RequestedByUserId),
    CONSTRAINT FundingPlatform_FK_SemanticEvaluationRuns_Configuration
        FOREIGN KEY (SemanticConfigurationId, SemanticConfigurationVersion)
        REFERENCES dbo.FundingPlatform_SemanticConfigurations (Id, Version),
    CONSTRAINT FundingPlatform_FK_SemanticEvaluationRuns_Set
        FOREIGN KEY (EvaluationSetId) REFERENCES dbo.FundingPlatform_SemanticEvaluationSets (Id),
    CONSTRAINT FundingPlatform_FK_SemanticEvaluationRuns_Requester
        FOREIGN KEY (RequestedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    /* 0 queued, 1 processing, 2 completed, 3 retry scheduled, 4 permanent failed. */
    CONSTRAINT FundingPlatform_CK_SemanticEvaluationRuns_Status CHECK (Status BETWEEN 0 AND 4),
    CONSTRAINT FundingPlatform_CK_SemanticEvaluationRuns_Counts CHECK
        (ProjectCount >= 30 AND OpportunityCount >= 100
         AND PairCount BETWEEN 300 AND 5000
         AND PrimaryCohortCount BETWEEN 0 AND PairCount
         AND EvaluatedCount BETWEEN 0 AND PairCount
         AND LabelledCount BETWEEN 0 AND EvaluatedCount),
    CONSTRAINT FundingPlatform_CK_SemanticEvaluationRuns_Lease CHECK
        ((Status = 1 AND LeaseId IS NOT NULL AND LeaseOwnerHash IS NOT NULL
                     AND LeaseUntilUtc IS NOT NULL)
         OR (Status <> 1 AND LeaseId IS NULL AND LeaseOwnerHash IS NULL
                         AND LeaseUntilUtc IS NULL)),
    CONSTRAINT FundingPlatform_CK_SemanticEvaluationRuns_Terminal CHECK
        ((Status = 2 AND CompletedAtUtc IS NOT NULL AND CompletionLeaseId IS NOT NULL)
         OR (Status = 4 AND CompletedAtUtc IS NOT NULL AND CompletionLeaseId IS NULL)
         OR (Status IN (0, 1, 3) AND CompletedAtUtc IS NULL AND CompletionLeaseId IS NULL)),
    CONSTRAINT FundingPlatform_CK_SemanticEvaluationRuns_Metrics CHECK
        ((Status <> 2 AND CoveragePercentage IS NULL AND SuccessPercentage IS NULL
                      AND RecallAt10 IS NULL AND NdcgAt10 IS NULL
                      AND BaselineNdcgAt10 IS NULL AND NdcgDelta IS NULL
                      AND MrrAt10 IS NULL
                      AND MeanRankDelta IS NULL AND TotalEstimatedCostUsd IS NULL
                      AND P95LatencyMilliseconds IS NULL AND HardFailPromotedCount IS NULL
                      AND IsPromotionEligible IS NULL)
         OR
         (Status = 2 AND CoveragePercentage IS NOT NULL
                     AND CoveragePercentage BETWEEN 0 AND 100
                     AND SuccessPercentage IS NOT NULL
                     AND SuccessPercentage BETWEEN 0 AND 100
                     AND RecallAt10 IS NOT NULL AND RecallAt10 BETWEEN 0 AND 1
                     AND NdcgAt10 IS NOT NULL AND NdcgAt10 BETWEEN 0 AND 1
                     AND BaselineNdcgAt10 IS NOT NULL AND BaselineNdcgAt10 BETWEEN 0 AND 1
                     AND NdcgDelta IS NOT NULL
                     AND NdcgDelta = NdcgAt10 - BaselineNdcgAt10
                     AND NdcgDelta BETWEEN -1 AND 1
                     AND MrrAt10 IS NOT NULL AND MrrAt10 BETWEEN 0 AND 1
                     AND MeanRankDelta IS NOT NULL AND MeanRankDelta BETWEEN -199 AND 199
                     AND TotalEstimatedCostUsd IS NOT NULL AND TotalEstimatedCostUsd >= 0
                     AND P95LatencyMilliseconds IS NOT NULL
                     AND P95LatencyMilliseconds BETWEEN 0 AND 600000
                     AND HardFailPromotedCount IS NOT NULL
                     AND HardFailPromotedCount BETWEEN 0 AND PairCount
                     AND IsPromotionEligible IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_SemanticEvaluationRuns_Attempts CHECK
        (AttemptCount BETWEEN 0 AND 3),
    CONSTRAINT FundingPlatform_CK_SemanticEvaluationRuns_Error CHECK
        ((Status IN (3, 4) AND ErrorCode IS NOT NULL)
         OR (Status IN (0, 1, 2) AND ErrorCode IS NULL)),
    CONSTRAINT FundingPlatform_CK_SemanticEvaluationRuns_ErrorAllowlist CHECK
        (ErrorCode IS NULL OR ErrorCode IN
         (N'semantic-configuration-invalid', N'semantic-work-invalid',
          N'semantic-embedding-permanent-failure', N'semantic-evaluation-error',
          N'lease-expired', N'internal-error')),
    CONSTRAINT FundingPlatform_CK_SemanticEvaluationRuns_Times CHECK
        (CreatedAtUtc <= UpdatedAtUtc
         AND (StartedAtUtc IS NULL OR StartedAtUtc >= CreatedAtUtc)
         AND (CompletedAtUtc IS NULL OR CompletedAtUtc >= CreatedAtUtc))
);

CREATE UNIQUE INDEX FundingPlatform_UQ_SemanticEvaluationRuns_Active
    ON dbo.FundingPlatform_SemanticEvaluationRuns
       (ActiveSlot)
    WHERE Status IN (0, 1, 3);

CREATE INDEX FundingPlatform_IX_SemanticEvaluationRuns_List
    ON dbo.FundingPlatform_SemanticEvaluationRuns (CreatedAtUtc DESC, Id DESC)
    INCLUDE (PublicId, Status, SemanticConfigurationId, EvaluationSetId, CompletedAtUtc);

CREATE INDEX FundingPlatform_IX_SemanticEvaluationRuns_Reproducible
    ON dbo.FundingPlatform_SemanticEvaluationRuns
       (SemanticConfigurationId, EvaluationSetId, CreatedAtUtc DESC, Id DESC)
    INCLUDE (PublicId, Status, SemanticConfigurationFingerprint, EvaluationSetManifestHash);

CREATE TABLE dbo.FundingPlatform_SemanticEvaluationRunCases
(
    SemanticEvaluationRunId BIGINT NOT NULL,
    EvaluationSetId INT NOT NULL,
    CaseOrdinal INT NOT NULL,
    ProjectMatchingRunId BIGINT NOT NULL,
    ProjectFundingMatchId BIGINT NOT NULL,
    OrganizationId BIGINT NOT NULL,
    ProjectId BIGINT NOT NULL,
    ProjectVersion INT NOT NULL,
    FundingOpportunityId BIGINT NOT NULL,
    FundingContentVersion INT NOT NULL,
    ProjectContentHash BINARY(32) NOT NULL,
    OpportunityContentHash BINARY(32) NOT NULL,
    ProjectInputContentHash BINARY(32) NOT NULL,
    OpportunityInputContentHash BINARY(32) NOT NULL,
    ProjectContentAddress BINARY(32) NOT NULL,
    OpportunityContentAddress BINARY(32) NOT NULL,
    DatasetSplit TINYINT NOT NULL,
    RelevanceLabel TINYINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_SemanticEvaluationRunCases
        PRIMARY KEY (SemanticEvaluationRunId, CaseOrdinal),
    CONSTRAINT FundingPlatform_UQ_SemanticEvaluationRunCases_Match
        UNIQUE (SemanticEvaluationRunId, ProjectFundingMatchId),
    CONSTRAINT FundingPlatform_UQ_SemanticEvaluationRunCases_ItemIdentity
        UNIQUE (SemanticEvaluationRunId, CaseOrdinal, ProjectFundingMatchId),
    CONSTRAINT FundingPlatform_FK_SemanticEvaluationRunCases_RunSet
        FOREIGN KEY (SemanticEvaluationRunId, EvaluationSetId)
        REFERENCES dbo.FundingPlatform_SemanticEvaluationRuns (Id, EvaluationSetId),
    CONSTRAINT FundingPlatform_FK_SemanticEvaluationRunCases_CorpusCase
        FOREIGN KEY (EvaluationSetId, CaseOrdinal, ProjectMatchingRunId, ProjectFundingMatchId)
        REFERENCES dbo.FundingPlatform_SemanticEvaluationCases
            (EvaluationSetId, Ordinal, ProjectMatchingRunId, ProjectFundingMatchId),
    CONSTRAINT FundingPlatform_FK_SemanticEvaluationRunCases_MatchIdentity
        FOREIGN KEY (ProjectFundingMatchId, ProjectMatchingRunId, OrganizationId,
                     ProjectId, ProjectVersion, FundingOpportunityId, FundingContentVersion)
        REFERENCES dbo.FundingPlatform_ProjectFundingMatches
            (Id, MatchRunId, OrganizationId, ProjectId, ProjectVersion,
             FundingOpportunityId, FundingContentVersion),
    CONSTRAINT FundingPlatform_CK_SemanticEvaluationRunCases_Enums CHECK
        (DatasetSplit IN (0, 1) AND RelevanceLabel BETWEEN 0 AND 2)
);

CREATE TABLE dbo.FundingPlatform_SemanticEvaluationItems
(
    SemanticEvaluationRunId BIGINT NOT NULL,
    CaseOrdinal INT NOT NULL,
    ProjectFundingMatchId BIGINT NOT NULL,
    ProjectEmbeddingId BIGINT NOT NULL,
    OpportunityEmbeddingId BIGINT NOT NULL,
    CosineDistance DECIMAL(9,8) NOT NULL,
    CosineSimilarity DECIMAL(9,8) NOT NULL,
    SemanticScore DECIMAL(5,2) NOT NULL,
    SemanticRank SMALLINT NULL,
    DeterministicRank SMALLINT NULL,
    RelevanceLabel TINYINT NOT NULL,
    DatasetSplit TINYINT NOT NULL,
    IsPrimaryCohort BIT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_SemanticEvaluationItems
        PRIMARY KEY (SemanticEvaluationRunId, CaseOrdinal),
    CONSTRAINT FundingPlatform_FK_SemanticEvaluationItems_RunCase
        FOREIGN KEY (SemanticEvaluationRunId, CaseOrdinal, ProjectFundingMatchId)
        REFERENCES dbo.FundingPlatform_SemanticEvaluationRunCases
            (SemanticEvaluationRunId, CaseOrdinal, ProjectFundingMatchId),
    CONSTRAINT FundingPlatform_FK_SemanticEvaluationItems_ProjectEmbedding
        FOREIGN KEY (ProjectEmbeddingId) REFERENCES dbo.FundingPlatform_SemanticEmbeddings (Id),
    CONSTRAINT FundingPlatform_FK_SemanticEvaluationItems_OpportunityEmbedding
        FOREIGN KEY (OpportunityEmbeddingId) REFERENCES dbo.FundingPlatform_SemanticEmbeddings (Id),
    CONSTRAINT FundingPlatform_CK_SemanticEvaluationItems_Scores CHECK
        (CosineDistance BETWEEN 0 AND 2 AND CosineSimilarity BETWEEN -1 AND 1
         AND ABS((1 - CosineDistance) - CosineSimilarity) <= 0.000001
         AND SemanticScore BETWEEN 0 AND 100),
    CONSTRAINT FundingPlatform_CK_SemanticEvaluationItems_Ranks CHECK
        ((IsPrimaryCohort = 1 AND SemanticRank BETWEEN 1 AND 200
                              AND DeterministicRank BETWEEN 1 AND 200)
         OR (IsPrimaryCohort = 0 AND SemanticRank IS NULL AND DeterministicRank IS NULL)),
    CONSTRAINT FundingPlatform_CK_SemanticEvaluationItems_Label CHECK
        (RelevanceLabel BETWEEN 0 AND 2 AND DatasetSplit IN (0, 1))
);

CREATE TABLE dbo.FundingPlatform_SemanticEvaluationRunRequests
(
    UserId BIGINT NOT NULL,
    IdempotencyKeyHash BINARY(32) NOT NULL,
    RequestHash BINARY(32) NOT NULL,
    SemanticEvaluationRunId BIGINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_SemanticEvaluationRunRequests
        PRIMARY KEY (UserId, IdempotencyKeyHash),
    CONSTRAINT FundingPlatform_FK_SemanticEvaluationRunRequests_User
        FOREIGN KEY (UserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_SemanticEvaluationRunRequests_RunRequester
        FOREIGN KEY (SemanticEvaluationRunId, UserId)
        REFERENCES dbo.FundingPlatform_SemanticEvaluationRuns (Id, RequestedByUserId)
);
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_fn_SemanticCanonicalIdArray
(
    @RawJson NVARCHAR(MAX)
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    IF @RawJson IS NULL RETURN N'[]';
    IF ISJSON(@RawJson) <> 1 OR LEFT(LTRIM(@RawJson), 1) <> N'[' RETURN NULL;
    DECLARE @Parsed TABLE (Ordinal INT NOT NULL, Id BIGINT NULL);
    INSERT INTO @Parsed (Ordinal, Id)
    SELECT CONVERT(INT, source.[key]),
           TRY_CONVERT(BIGINT, CASE source.[type]
               WHEN 2 THEN source.[value]
               WHEN 5 THEN JSON_VALUE(source.[value], N'$.id') END)
    FROM OPENJSON(@RawJson) AS source;
    IF EXISTS (SELECT 1 FROM @Parsed WHERE Id IS NULL OR Id <= 0) RETURN NULL;
    DECLARE @Canonical NVARCHAR(MAX);
    SELECT @Canonical = CONCAT(N'[', COALESCE
    (
        STRING_AGG(CONVERT(NVARCHAR(MAX), ids.Id), N',')
            WITHIN GROUP (ORDER BY ids.Id), N''
    ), N']')
    FROM (SELECT DISTINCT Id FROM @Parsed) AS ids;
    RETURN COALESCE(@Canonical, N'[]');
END;
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_fn_ProjectSemanticCanonicalInput
(
    @SnapshotJson NVARCHAR(MAX)
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @Title NVARCHAR(250), @Summary NVARCHAR(1000), @Description NVARCHAR(MAX);
    DECLARE @ProjectStatus TINYINT, @StartDate DATE, @EndDate DATE;
    DECLARE @BudgetTotal DECIMAL(19,4), @ConfirmedFunding DECIMAL(19,4), @Currency CHAR(3);
    DECLARE @CountryIds NVARCHAR(MAX), @RegionIds NVARCHAR(MAX), @CategoryIds NVARCHAR(MAX);
    DECLARE @BeneficiaryTypeIds NVARCHAR(MAX), @ProjectTypeIds NVARCHAR(MAX);
    SELECT @Title = source.Title, @Summary = source.Summary,
           @Description = source.Description, @ProjectStatus = source.ProjectStatus,
           @StartDate = source.StartDate, @EndDate = source.EndDate,
           @BudgetTotal = source.BudgetTotal, @ConfirmedFunding = source.ConfirmedFunding,
           @Currency = source.Currency, @CountryIds = source.CountryIds,
           @RegionIds = source.RegionIds, @CategoryIds = source.CategoryIds,
           @BeneficiaryTypeIds = source.BeneficiaryTypeIds,
           @ProjectTypeIds = source.ProjectTypeIds
    FROM OPENJSON(@SnapshotJson)
    WITH
    (
        Title NVARCHAR(250) N'$.title', Summary NVARCHAR(1000) N'$.summary',
        Description NVARCHAR(MAX) N'$.description', ProjectStatus TINYINT N'$.status',
        StartDate DATE N'$.startDate', EndDate DATE N'$.endDate',
        BudgetTotal DECIMAL(19,4) N'$.budgetTotal',
        ConfirmedFunding DECIMAL(19,4) N'$.confirmedFunding', Currency CHAR(3) N'$.currency',
        CountryIds NVARCHAR(MAX) N'$.countryIds' AS JSON,
        RegionIds NVARCHAR(MAX) N'$.regionIds' AS JSON,
        CategoryIds NVARCHAR(MAX) N'$.categoryIds' AS JSON,
        BeneficiaryTypeIds NVARCHAR(MAX) N'$.beneficiaryTypeIds' AS JSON,
        ProjectTypeIds NVARCHAR(MAX) N'$.projectTypeIds' AS JSON
    ) AS source;

    IF NULLIF(LTRIM(RTRIM(@Title)), N'') IS NULL RETURN NULL;
    SET @CountryIds = dbo.FundingPlatform_fn_SemanticCanonicalIdArray(@CountryIds);
    SET @RegionIds = dbo.FundingPlatform_fn_SemanticCanonicalIdArray(@RegionIds);
    SET @CategoryIds = dbo.FundingPlatform_fn_SemanticCanonicalIdArray(@CategoryIds);
    SET @BeneficiaryTypeIds = dbo.FundingPlatform_fn_SemanticCanonicalIdArray(@BeneficiaryTypeIds);
    SET @ProjectTypeIds = dbo.FundingPlatform_fn_SemanticCanonicalIdArray(@ProjectTypeIds);
    IF @CountryIds IS NULL OR @RegionIds IS NULL OR @CategoryIds IS NULL
       OR @BeneficiaryTypeIds IS NULL OR @ProjectTypeIds IS NULL RETURN NULL;
    RETURN CONCAT
    (
        N'{"schemaVersion":"semantic-input-v1","normalizationVersion":"semantic-text-v1"',
        N',"summary":', CASE WHEN @Summary IS NULL THEN N'null'
                             ELSE CONCAT(N'"', STRING_ESCAPE(@Summary, 'json'), N'"') END,
        N',"description":', CASE WHEN @Description IS NULL THEN N'null'
                                 ELSE CONCAT(N'"', STRING_ESCAPE(@Description, 'json'), N'"') END,
        N',"projectStatus":', COALESCE(CONVERT(NVARCHAR(3), @ProjectStatus), N'null'),
        N',"startDate":', CASE WHEN @StartDate IS NULL THEN N'null'
                               ELSE CONCAT(N'"', CONVERT(NVARCHAR(10), @StartDate, 23), N'"') END,
        N',"endDate":', CASE WHEN @EndDate IS NULL THEN N'null'
                             ELSE CONCAT(N'"', CONVERT(NVARCHAR(10), @EndDate, 23), N'"') END,
        N',"budgetTotal":', COALESCE(CONVERT(NVARCHAR(50), @BudgetTotal), N'null'),
        N',"confirmedFunding":', COALESCE(CONVERT(NVARCHAR(50), @ConfirmedFunding), N'null'),
        N',"currency":', CASE WHEN @Currency IS NULL THEN N'null'
                              ELSE CONCAT(N'"', @Currency, N'"') END,
        N',"countryIds":', COALESCE(@CountryIds, N'[]'),
        N',"regionIds":', COALESCE(@RegionIds, N'[]'),
        N',"categoryIds":', COALESCE(@CategoryIds, N'[]'),
        N',"beneficiaryTypeIds":', COALESCE(@BeneficiaryTypeIds, N'[]'),
        N',"projectTypeIds":', COALESCE(@ProjectTypeIds, N'[]'), N'}'
    );
END;
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_fn_OpportunitySemanticCanonicalInput
(
    @SnapshotJson NVARCHAR(MAX)
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @Title NVARCHAR(350), @Description NVARCHAR(MAX), @Summary NVARCHAR(2000);
    DECLARE @SponsorName NVARCHAR(300), @Currency CHAR(3), @MinAmount DECIMAL(19,4);
    DECLARE @MaxAmount DECIMAL(19,4), @Eligibility NVARCHAR(MAX), @Requirements NVARCHAR(MAX);
    DECLARE @Objectives NVARCHAR(MAX), @Allowed NVARCHAR(MAX), @Excluded NVARCHAR(MAX);
    DECLARE @Restrictions NVARCHAR(MAX), @TargetOrganizations NVARCHAR(2000), @TargetPopulations NVARCHAR(2000);
    DECLARE @MinimumYears SMALLINT, @RequiresLegal BIT, @RequiresExperience BIT;
    DECLARE @RequiresCofunding BIT, @Cofunding DECIMAL(5,2), @GeographicScope TINYINT;
    DECLARE @CountryIds NVARCHAR(MAX), @RegionIds NVARCHAR(MAX), @CategoryIds NVARCHAR(MAX);
    DECLARE @BeneficiaryTypeIds NVARCHAR(MAX), @ProjectTypeIds NVARCHAR(MAX);
    SELECT @Title = source.Title, @Description = source.Description,
           @Summary = source.Summary, @SponsorName = source.SponsorName,
           @Currency = source.Currency, @MinAmount = source.MinAmount,
           @MaxAmount = source.MaxAmount, @Eligibility = source.Eligibility,
           @Requirements = source.Requirements, @Objectives = source.Objectives,
           @Allowed = source.Allowed, @Excluded = source.Excluded,
           @Restrictions = source.Restrictions,
           @TargetOrganizations = source.TargetOrganizations,
           @TargetPopulations = source.TargetPopulations,
           @MinimumYears = source.MinimumYears, @RequiresLegal = source.RequiresLegal,
           @RequiresExperience = source.RequiresExperience,
           @RequiresCofunding = source.RequiresCofunding, @Cofunding = source.Cofunding,
           @GeographicScope = source.GeographicScope,
           @CountryIds = source.CountryIds, @RegionIds = source.RegionIds,
           @CategoryIds = source.CategoryIds, @BeneficiaryTypeIds = source.BeneficiaryTypeIds,
           @ProjectTypeIds = source.ProjectTypeIds
    FROM OPENJSON(@SnapshotJson)
    WITH
    (
        Title NVARCHAR(350) N'$.title', Description NVARCHAR(MAX) N'$.description',
        Summary NVARCHAR(2000) N'$.summary', SponsorName NVARCHAR(300) N'$.sponsorName',
        Currency CHAR(3) N'$.currency', MinAmount DECIMAL(19,4) N'$.minAmount',
        MaxAmount DECIMAL(19,4) N'$.maxAmount',
        Eligibility NVARCHAR(MAX) N'$.eligibilityDescription',
        Requirements NVARCHAR(MAX) N'$.requirements', Objectives NVARCHAR(MAX) N'$.objectives',
        Allowed NVARCHAR(MAX) N'$.allowedActivities', Excluded NVARCHAR(MAX) N'$.excludedActivities',
        Restrictions NVARCHAR(MAX) N'$.restrictions',
        TargetOrganizations NVARCHAR(2000) N'$.targetOrganizationsDescription',
        TargetPopulations NVARCHAR(2000) N'$.targetPopulationsDescription',
        MinimumYears SMALLINT N'$.minimumOperatingYears', RequiresLegal BIT N'$.requiresLegalEntity',
        RequiresExperience BIT N'$.requiresPriorExperience',
        RequiresCofunding BIT N'$.requiresCofunding', Cofunding DECIMAL(5,2) N'$.cofundingPercentage',
        GeographicScope TINYINT N'$.geographicScope',
        CountryIds NVARCHAR(MAX) N'$.countryIds' AS JSON,
        RegionIds NVARCHAR(MAX) N'$.regionIds' AS JSON,
        CategoryIds NVARCHAR(MAX) N'$.categoryIds' AS JSON,
        BeneficiaryTypeIds NVARCHAR(MAX) N'$.beneficiaryTypeIds' AS JSON,
        ProjectTypeIds NVARCHAR(MAX) N'$.projectTypeIds' AS JSON
    ) AS source;

    IF NULLIF(LTRIM(RTRIM(@Title)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@SponsorName)), N'') IS NULL RETURN NULL;
    SET @CountryIds = dbo.FundingPlatform_fn_SemanticCanonicalIdArray(@CountryIds);
    SET @RegionIds = dbo.FundingPlatform_fn_SemanticCanonicalIdArray(@RegionIds);
    SET @CategoryIds = dbo.FundingPlatform_fn_SemanticCanonicalIdArray(@CategoryIds);
    SET @BeneficiaryTypeIds = dbo.FundingPlatform_fn_SemanticCanonicalIdArray(@BeneficiaryTypeIds);
    SET @ProjectTypeIds = dbo.FundingPlatform_fn_SemanticCanonicalIdArray(@ProjectTypeIds);
    IF @CountryIds IS NULL OR @RegionIds IS NULL OR @CategoryIds IS NULL
       OR @BeneficiaryTypeIds IS NULL OR @ProjectTypeIds IS NULL RETURN NULL;
    RETURN CONCAT
    (
        N'{"schemaVersion":"semantic-input-v1","normalizationVersion":"semantic-text-v1"',
        N',"title":"', STRING_ESCAPE(@Title, 'json'), N'"',
        N',"description":', CASE WHEN @Description IS NULL THEN N'null' ELSE CONCAT(N'"', STRING_ESCAPE(@Description, 'json'), N'"') END,
        N',"summary":', CASE WHEN @Summary IS NULL THEN N'null' ELSE CONCAT(N'"', STRING_ESCAPE(@Summary, 'json'), N'"') END,
        N',"sponsorName":"', STRING_ESCAPE(@SponsorName, 'json'), N'"',
        N',"currency":', CASE WHEN @Currency IS NULL THEN N'null' ELSE CONCAT(N'"', @Currency, N'"') END,
        N',"minAmount":', COALESCE(CONVERT(NVARCHAR(50), @MinAmount), N'null'),
        N',"maxAmount":', COALESCE(CONVERT(NVARCHAR(50), @MaxAmount), N'null'),
        N',"eligibilityDescription":', CASE WHEN @Eligibility IS NULL THEN N'null' ELSE CONCAT(N'"', STRING_ESCAPE(@Eligibility, 'json'), N'"') END,
        N',"requirements":', CASE WHEN @Requirements IS NULL THEN N'null' ELSE CONCAT(N'"', STRING_ESCAPE(@Requirements, 'json'), N'"') END,
        N',"objectives":', CASE WHEN @Objectives IS NULL THEN N'null' ELSE CONCAT(N'"', STRING_ESCAPE(@Objectives, 'json'), N'"') END,
        N',"allowedActivities":', CASE WHEN @Allowed IS NULL THEN N'null' ELSE CONCAT(N'"', STRING_ESCAPE(@Allowed, 'json'), N'"') END,
        N',"excludedActivities":', CASE WHEN @Excluded IS NULL THEN N'null' ELSE CONCAT(N'"', STRING_ESCAPE(@Excluded, 'json'), N'"') END,
        N',"restrictions":', CASE WHEN @Restrictions IS NULL THEN N'null' ELSE CONCAT(N'"', STRING_ESCAPE(@Restrictions, 'json'), N'"') END,
        N',"targetOrganizationsDescription":', CASE WHEN @TargetOrganizations IS NULL THEN N'null' ELSE CONCAT(N'"', STRING_ESCAPE(@TargetOrganizations, 'json'), N'"') END,
        N',"targetPopulationsDescription":', CASE WHEN @TargetPopulations IS NULL THEN N'null' ELSE CONCAT(N'"', STRING_ESCAPE(@TargetPopulations, 'json'), N'"') END,
        N',"minimumOperatingYears":', COALESCE(CONVERT(NVARCHAR(10), @MinimumYears), N'null'),
        N',"requiresLegalEntity":', CASE @RequiresLegal WHEN 1 THEN N'true' WHEN 0 THEN N'false' ELSE N'null' END,
        N',"requiresPriorExperience":', CASE @RequiresExperience WHEN 1 THEN N'true' WHEN 0 THEN N'false' ELSE N'null' END,
        N',"requiresCofunding":', CASE @RequiresCofunding WHEN 1 THEN N'true' WHEN 0 THEN N'false' ELSE N'null' END,
        N',"cofundingPercentage":', COALESCE(CONVERT(NVARCHAR(20), @Cofunding), N'null'),
        N',"geographicScope":', COALESCE(CONVERT(NVARCHAR(3), @GeographicScope), N'null'),
        N',"countryIds":', COALESCE(@CountryIds, N'[]'),
        N',"regionIds":', COALESCE(@RegionIds, N'[]'),
        N',"categoryIds":', COALESCE(@CategoryIds, N'[]'),
        N',"beneficiaryTypeIds":', COALESCE(@BeneficiaryTypeIds, N'[]'),
        N',"projectTypeIds":', COALESCE(@ProjectTypeIds, N'[]'), N'}'
    );
END;
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_fn_SemanticInputHash
(
    @CanonicalInputJson NVARCHAR(MAX)
)
RETURNS BINARY(32)
AS
BEGIN
    RETURN CONVERT(BINARY(32), HASHBYTES
    (
        'SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
            @CanonicalInputJson COLLATE Latin1_General_100_BIN2_UTF8))
    ));
END;
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_fn_SemanticInputRiskCode
(
    @CanonicalInputJson NVARCHAR(MAX),
    @MaximumInputUtf8Bytes SMALLINT
)
RETURNS NVARCHAR(50)
AS
BEGIN
    IF @CanonicalInputJson IS NULL OR ISJSON(@CanonicalInputJson) <> 1
        RETURN N'invalid-canonical-input';
    IF DATALENGTH(CONVERT(VARCHAR(MAX),
       @CanonicalInputJson COLLATE Latin1_General_100_BIN2_UTF8)) > @MaximumInputUtf8Bytes
        RETURN N'input-too-large';
    /* Conservative private-data screen. Known identifier/URL fields are not allowlisted;
       free text containing an email, URL or Chilean RUT is rejected before provider access. */
    IF @CanonicalInputJson LIKE N'%_@_%._%' RETURN N'pii-email-detected';
    IF @CanonicalInputJson LIKE N'%http://%' OR @CanonicalInputJson LIKE N'%https://%'
       OR @CanonicalInputJson LIKE N'%www.%' RETURN N'pii-url-detected';
    IF @CanonicalInputJson LIKE N'%[0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9Kk]%'
       OR @CanonicalInputJson LIKE N'%[0-9][0-9].[0-9][0-9][0-9].[0-9][0-9][0-9]-[0-9Kk]%'
        RETURN N'pii-rut-detected';
    RETURN NULL;
END;
GO

/* Configuration, corpus, usage and completed outputs are historical records.
   A configuration can only be disabled; promotion requires a new version. */

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
                   configurations.MonthlyBudgetUsd, N'|', configurations.IsLocalFake
               ))
           )) AS CalculatedFingerprint
    FROM dbo.FundingPlatform_SemanticConfigurations AS configurations
    WHERE configurations.Id = @SemanticConfigurationId
);
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_SemanticEvaluationSetState
(
    @EvaluationSetId INT
)
RETURNS TABLE
AS
RETURN
(
    SELECT sets.Id,
           COUNT_BIG(cases.Ordinal) AS ActualLabelCount,
           COUNT_BIG(DISTINCT cases.ProjectId) AS ActualProjectCount,
           COUNT_BIG(DISTINCT cases.FundingOpportunityId) AS ActualOpportunityCount,
           CONVERT(BINARY(32), HASHBYTES
           (
               'SHA2_256', CONVERT(VARBINARY(MAX), COALESCE
               (
                   STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT
                   (
                       cases.Ordinal, N':', cases.CasePublicId, N':', cases.Split, N':',
                       cases.ProjectMatchingRunId, N':', cases.ProjectFundingMatchId, N':',
                       cases.OrganizationId, N':', cases.ProjectId, N':', cases.ProjectVersion, N':',
                       cases.FundingOpportunityId, N':', cases.FundingContentVersion, N':',
                       CONVERT(VARCHAR(64), cases.ProjectContentHash, 2), N':',
                       CONVERT(VARCHAR(64), cases.OpportunityContentHash, 2), N':',
                       cases.RelevanceLabel, N':',
                       CONVERT(VARCHAR(64), cases.LabelProvenanceHash, 2)
                   )), N'|') WITHIN GROUP (ORDER BY cases.Ordinal),
                   N'empty-evaluation-set'
               ))
           )) AS CalculatedManifestHash
    FROM dbo.FundingPlatform_SemanticEvaluationSets AS sets
    LEFT JOIN dbo.FundingPlatform_SemanticEvaluationCases AS cases
        ON cases.EvaluationSetId = sets.Id
    WHERE sets.Id = @EvaluationSetId
    GROUP BY sets.Id
);
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_SemanticEvaluationRunSummaries()
RETURNS TABLE
AS
RETURN
(
    SELECT runs.Id AS SemanticEvaluationRunId, runs.PublicId,
           runs.Status,
           CONCAT(sets.Code, N'-v', sets.Version) AS EvaluationSetVersion,
           CONCAT(configurations.Code, N'-v', configurations.Version)
                AS SemanticConfigurationVersion,
           configurations.ProviderCode, configurations.ModelCode,
           configurations.Dimensions, configurations.PurposeCode,
           configurations.NormalizationVersion,
           runs.ProjectCount, runs.OpportunityCount, runs.PairCount,
           runs.PrimaryCohortCount, runs.EvaluatedCount, runs.LabelledCount,
           runs.CoveragePercentage,
           runs.SuccessPercentage AS ProviderSuccessPercentage,
           runs.RecallAt10,
           runs.NdcgAt10 AS NormalizedDiscountedCumulativeGainAt10,
           runs.BaselineNdcgAt10 AS BaselineNormalizedDiscountedCumulativeGainAt10,
           runs.NdcgDelta AS NormalizedDiscountedCumulativeGainDelta,
           runs.MrrAt10 AS MeanReciprocalRankAt10,
           runs.MeanRankDelta, runs.TotalEstimatedCostUsd,
           runs.P95LatencyMilliseconds AS LatencyP95Milliseconds,
           runs.HardFailPromotedCount AS HardGatePromotionCount,
           runs.IsPromotionEligible AS MeetsPromotionGate,
           runs.CreatedAtUtc, runs.StartedAtUtc, runs.CompletedAtUtc,
           runs.ErrorCode AS LastErrorCode
    FROM dbo.FundingPlatform_SemanticEvaluationRuns AS runs
    INNER JOIN dbo.FundingPlatform_SemanticConfigurations AS configurations
        ON configurations.Id = runs.SemanticConfigurationId
       AND configurations.Version = runs.SemanticConfigurationVersion
    INNER JOIN dbo.FundingPlatform_SemanticEvaluationSets AS sets
        ON sets.Id = runs.EvaluationSetId AND sets.Version = runs.EvaluationSetVersion
);
GO


CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SemanticEmbeddingJob_BackfillEnqueue
    @UserPublicId UNIQUEIDENTIFIER,
    @SemanticConfigurationVersion NVARCHAR(64),
    @SubjectType TINYINT,
    @AfterId BIGINT = 0,
    @BatchSize INT = 64,
    @AllowLocalFake BIT = 0,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @UserPublicId IS NULL OR @NowUtc IS NULL OR @SubjectType NOT IN (0, 1)
       OR @AfterId < 0 OR @BatchSize NOT BETWEEN 1 AND 64
       OR @SemanticConfigurationVersion IS NULL
       OR LEN(@SemanticConfigurationVersion) NOT BETWEEN 3 AND 64
        THROW 54104, N'Bounded semantic backfill parameters are required.', 1;

    DECLARE @UserId BIGINT, @ConfigurationId INT, @ConfigurationVersion INT;
    DECLARE @ProviderCode NVARCHAR(50), @ModelCode NVARCHAR(128), @Dimensions SMALLINT;
    DECLARE @PurposeCode NVARCHAR(32), @ProjectTemplate NVARCHAR(50), @OpportunityTemplate NVARCHAR(50);
    DECLARE @Normalization NVARCHAR(50), @ConfigFingerprint BINARY(32), @MaximumAttempts TINYINT;
    DECLARE @MaximumInputBytes SMALLINT, @IsLocalFake BIT, @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @StartedTransaction BIT = 0;

    SELECT @UserId = users.Id
    FROM dbo.FundingPlatform_Users AS users
    WHERE users.PublicId = @UserPublicId AND users.Status = 2
      AND EXISTS
      (SELECT 1 FROM dbo.FundingPlatform_UserRoles AS userRoles
       INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
       WHERE userRoles.UserId = users.Id
         AND roles.NormalizedName IN (N'ADMIN', N'SUPERADMIN'));
    IF @UserId IS NULL THROW 54105, N'Active platform administrator is required.', 1;

    SELECT @ConfigurationId = configurations.Id,
           @ConfigurationVersion = configurations.Version,
           @ProviderCode = configurations.ProviderCode, @ModelCode = configurations.ModelCode,
           @Dimensions = configurations.Dimensions, @PurposeCode = configurations.PurposeCode,
           @ProjectTemplate = configurations.ProjectTemplateVersion,
           @OpportunityTemplate = configurations.OpportunityTemplateVersion,
           @Normalization = configurations.NormalizationVersion,
           @ConfigFingerprint = configurations.ConfigurationFingerprint,
           @MaximumAttempts = configurations.MaximumAttempts,
           @MaximumInputBytes = configurations.MaximumInputUtf8Bytes,
           @IsLocalFake = configurations.IsLocalFake
    FROM dbo.FundingPlatform_SemanticConfigurations AS configurations
    CROSS APPLY dbo.FundingPlatform_ifn_SemanticConfigurationState(configurations.Id) AS state
    WHERE CONCAT(configurations.Code, N'-v', configurations.Version) = @SemanticConfigurationVersion
      AND configurations.IsActive = 1
      AND configurations.ConfigurationFingerprint = state.CalculatedFingerprint;
    IF @ConfigurationId IS NULL THROW 54106, N'Active semantic configuration was not found or drifted.', 1;
    IF @IsLocalFake = 1 AND @AllowLocalFake <> 1
        THROW 54107, N'Local deterministic embeddings are disabled for this runtime.', 1;

    DECLARE @Inputs TABLE
    (
        SubjectIdentity BIGINT NOT NULL PRIMARY KEY,
        SubjectPublicId UNIQUEIDENTIFIER NOT NULL,
        OrganizationId BIGINT NULL,
        ProjectId BIGINT NULL,
        ProjectVersion INT NULL,
        FundingOpportunityId BIGINT NULL,
        FundingContentVersion INT NULL,
        SubjectContentHash BINARY(32) NOT NULL,
        CanonicalInputJson NVARCHAR(MAX) NULL
    );

    IF @SubjectType = 0
        INSERT INTO @Inputs
            (SubjectIdentity, SubjectPublicId, OrganizationId, ProjectId, ProjectVersion,
             FundingOpportunityId, FundingContentVersion, SubjectContentHash, CanonicalInputJson)
        SELECT TOP (@BatchSize) projects.Id, projects.PublicId, projects.OrganizationId,
               projects.Id, projects.ProjectVersion, NULL, NULL, versions.ContentHash,
               dbo.FundingPlatform_fn_ProjectSemanticCanonicalInput(versions.SnapshotJson)
        FROM dbo.FundingPlatform_Projects AS projects
        INNER JOIN dbo.FundingPlatform_Organizations AS organizations
            ON organizations.Id = projects.OrganizationId AND organizations.IsActive = 1
        INNER JOIN dbo.FundingPlatform_ProjectVersions AS versions
            ON versions.ProjectId = projects.Id AND versions.ProjectVersion = projects.ProjectVersion
        WHERE projects.Id > @AfterId AND projects.IsActive = 1
          AND projects.PublicationStatus <> 4
        ORDER BY projects.Id;
    ELSE
        INSERT INTO @Inputs
            (SubjectIdentity, SubjectPublicId, OrganizationId, ProjectId, ProjectVersion,
             FundingOpportunityId, FundingContentVersion, SubjectContentHash, CanonicalInputJson)
        SELECT TOP (@BatchSize) opportunities.Id, opportunities.PublicId, NULL, NULL, NULL,
               opportunities.Id, opportunities.ContentVersion, versions.ContentHash,
               dbo.FundingPlatform_fn_OpportunitySemanticCanonicalInput(versions.SnapshotJson)
        FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
        INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
            ON ready.FundingOpportunityId = opportunities.Id
        INNER JOIN dbo.FundingPlatform_FundingOpportunityVersions AS versions
            ON versions.FundingOpportunityId = opportunities.Id
           AND versions.ContentVersion = opportunities.ContentVersion
        WHERE opportunities.Id > @AfterId
        ORDER BY opportunities.Id;

    DECLARE @Prepared TABLE
    (
        SubjectIdentity BIGINT NOT NULL PRIMARY KEY,
        SubjectPublicId UNIQUEIDENTIFIER NOT NULL,
        OrganizationId BIGINT NULL, ProjectId BIGINT NULL, ProjectVersion INT NULL,
        FundingOpportunityId BIGINT NULL, FundingContentVersion INT NULL,
        SubjectContentHash BINARY(32) NOT NULL, InputContentHash BINARY(32) NOT NULL,
        ContentAddress BINARY(32) NOT NULL, RiskCode NVARCHAR(50) NULL
    );
    INSERT INTO @Prepared
    SELECT inputs.SubjectIdentity, inputs.SubjectPublicId, inputs.OrganizationId,
           inputs.ProjectId, inputs.ProjectVersion, inputs.FundingOpportunityId,
           inputs.FundingContentVersion, inputs.SubjectContentHash,
           effective.InputContentHash,
           CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
           (
               N'semantic-embedding-v1|', @SubjectType, N'|',
               COALESCE(CONVERT(NVARCHAR(30), inputs.OrganizationId), N'global'), N'|',
               COALESCE(CONVERT(NVARCHAR(30), inputs.ProjectId), N'-'), N'|',
               COALESCE(CONVERT(NVARCHAR(20), inputs.ProjectVersion), N'-'), N'|',
               COALESCE(CONVERT(NVARCHAR(30), inputs.FundingOpportunityId), N'-'), N'|',
               COALESCE(CONVERT(NVARCHAR(20), inputs.FundingContentVersion), N'-'), N'|',
               CONVERT(VARCHAR(64), inputs.SubjectContentHash, 2), N'|',
               CONVERT(VARCHAR(64), effective.InputContentHash, 2), N'|',
               @ProviderCode, N'|', @ModelCode, N'|', @Dimensions, N'|', @PurposeCode, N'|',
               CASE @SubjectType WHEN 0 THEN @ProjectTemplate ELSE @OpportunityTemplate END, N'|',
               @Normalization, N'|', @ConfigurationVersion, N'|',
               CONVERT(VARCHAR(64), @ConfigFingerprint, 2)
           )))),
           COALESCE(dbo.FundingPlatform_fn_SemanticInputRiskCode
               (inputs.CanonicalInputJson, @MaximumInputBytes),
               CASE WHEN calculated.InputContentHash IS NULL
                    THEN N'invalid-canonical-input' END)
    FROM @Inputs AS inputs
    CROSS APPLY
    (SELECT dbo.FundingPlatform_fn_SemanticInputHash(inputs.CanonicalInputJson)
            AS InputContentHash) AS calculated
    CROSS APPLY
    (SELECT COALESCE(calculated.InputContentHash,
        CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
        (N'invalid-semantic-input-v1|', @SubjectType, N'|', inputs.SubjectIdentity,
         N'|', CONVERT(VARCHAR(64), inputs.SubjectContentHash, 2), N'|',
         CONVERT(VARCHAR(64), @ConfigFingerprint, 2)))))) AS InputContentHash) AS effective
    ;

    DECLARE @Created TABLE
        (JobId BIGINT NOT NULL, JobPublicId UNIQUEIDENTIFIER NOT NULL, Status TINYINT NOT NULL);
    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_SemanticBackfill;
    BEGIN TRY
        DECLARE @LockedActorUserId BIGINT;
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId = @UserPublicId,
            @ActorUserId = @LockedActorUserId OUTPUT;
        IF @LockedActorUserId <> @UserId
            THROW 54105, N'Administrative actor changed while starting semantic backfill.', 1;
        IF NOT EXISTS
           (SELECT 1
            FROM dbo.FundingPlatform_SemanticConfigurations AS configurations
                 WITH (UPDLOCK, HOLDLOCK)
            CROSS APPLY dbo.FundingPlatform_ifn_SemanticConfigurationState
                (configurations.Id) AS state
            WHERE configurations.Id = @ConfigurationId
              AND configurations.Version = @ConfigurationVersion
              AND configurations.IsActive = 1
              AND configurations.ConfigurationFingerprint = @ConfigFingerprint
              AND configurations.ConfigurationFingerprint = state.CalculatedFingerprint)
            THROW 54106, N'Semantic configuration was deactivated or drifted before enqueue.', 1;

        INSERT INTO dbo.FundingPlatform_SemanticEmbeddingJobs
            (SemanticConfigurationId, SemanticConfigurationVersion, SubjectType,
             OrganizationId, ProjectId, ProjectVersion, FundingOpportunityId,
             FundingContentVersion, SubjectContentHash, InputContentHash, ContentAddress,
             JobGeneration, AllowHistorical, Status, AttemptCount, MaximumAttempts, NextAttemptAtUtc,
             ErrorCode, CreatedAtUtc, CompletedAtUtc, UpdatedAtUtc)
        OUTPUT inserted.Id, inserted.PublicId, inserted.Status
            INTO @Created (JobId, JobPublicId, Status)
        SELECT @ConfigurationId, @ConfigurationVersion, @SubjectType,
               prepared.OrganizationId, prepared.ProjectId, prepared.ProjectVersion,
               prepared.FundingOpportunityId, prepared.FundingContentVersion,
               prepared.SubjectContentHash, prepared.InputContentHash, prepared.ContentAddress,
               1, 0, CASE WHEN prepared.RiskCode IS NULL THEN 0 ELSE 4 END,
               0, @MaximumAttempts, @NowUtc, prepared.RiskCode, @NowUtc,
               CASE WHEN prepared.RiskCode IS NULL THEN NULL ELSE @NowUtc END, @NowUtc
        FROM @Prepared AS prepared
        WHERE NOT EXISTS
        (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS existing WITH (UPDLOCK, HOLDLOCK)
         WHERE existing.ContentAddress = prepared.ContentAddress)
          AND NOT EXISTS
        (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddings AS existing WITH (UPDLOCK, HOLDLOCK)
         WHERE existing.ContentAddress = prepared.ContentAddress);

        /* Semantic workers poll this durable SQL job table. No generic-outbox
           command is emitted because the 016 dispatcher does not route semantic work. */
        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_SemanticBackfill;
        THROW;
    END CATCH;

    SELECT COUNT_BIG(1) AS ScannedCount,
           (SELECT COUNT_BIG(1) FROM @Created WHERE Status = 0) AS QueuedCount,
           (SELECT COUNT_BIG(1) FROM @Created WHERE Status = 4) AS RejectedCount,
           COUNT_BIG(1) - (SELECT COUNT_BIG(1) FROM @Created) AS ExistingCount,
           COALESCE(MAX(SubjectIdentity), @AfterId) AS NextAfterId
    FROM @Inputs;
END;
GO


CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SemanticEvaluationRun_Create
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @EvaluationSetVersion NVARCHAR(64),
    @SemanticConfigurationVersion NVARCHAR(64),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @RuntimeEnabled BIT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @AdminUserPublicId IS NULL OR @NowUtc IS NULL OR @RuntimeEnabled IS NULL
       OR @IdempotencyKeyHash IS NULL OR @RequestHash IS NULL
       OR DATALENGTH(@IdempotencyKeyHash) <> 32 OR DATALENGTH(@RequestHash) <> 32
       OR @EvaluationSetVersion IS NULL OR LEN(@EvaluationSetVersion) NOT BETWEEN 3 AND 64
       OR @SemanticConfigurationVersion IS NULL
       OR LEN(@SemanticConfigurationVersion) NOT BETWEEN 3 AND 64
       OR @EvaluationSetVersion LIKE N'%[^A-Za-z0-9._-]%' COLLATE Latin1_General_100_BIN2
       OR @SemanticConfigurationVersion LIKE N'%[^A-Za-z0-9._-]%' COLLATE Latin1_General_100_BIN2
        THROW 54125, N'Valid semantic evaluation request metadata is required.', 1;

    DECLARE @UserId BIGINT, @RunId BIGINT, @StoredRequestHash BINARY(32), @WasReplay BIT = 0;
    DECLARE @ConfigurationId INT, @ConfigurationVersion INT, @ConfigFingerprint BINARY(32);
    DECLARE @Provider NVARCHAR(50), @Model NVARCHAR(128), @Dimensions SMALLINT;
    DECLARE @Purpose NVARCHAR(32), @ProjectTemplate NVARCHAR(50), @OpportunityTemplate NVARCHAR(50);
    DECLARE @Normalization NVARCHAR(50), @MaximumInputBytes SMALLINT, @MaximumAttempts TINYINT;
    DECLARE @MaximumCost DECIMAL(19,6), @MonthlyBudget DECIMAL(19,6);
    DECLARE @EvaluationSetId INT, @SetVersion INT, @ManifestHash BINARY(32);
    DECLARE @ActualProjects BIGINT, @ActualOpportunities BIGINT, @ActualLabels BIGINT;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @Started BIT = 0, @LockResult INT;
    IF @InitialTransactionCount = 0 BEGIN BEGIN TRANSACTION; SET @Started = 1; END
    ELSE SAVE TRANSACTION FP_SemanticEvalCreate;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId = @AdminUserPublicId, @ActorUserId = @UserId OUTPUT;

        SELECT @RunId = requests.SemanticEvaluationRunId,
               @StoredRequestHash = requests.RequestHash
        FROM dbo.FundingPlatform_SemanticEvaluationRunRequests AS requests
             WITH (UPDLOCK, HOLDLOCK)
        WHERE requests.UserId = @UserId AND requests.IdempotencyKeyHash = @IdempotencyKeyHash;
        IF @RunId IS NOT NULL
        BEGIN
            IF @StoredRequestHash <> @RequestHash
                THROW 54126, N'Idempotency key was already used with another semantic request.', 1;
            SET @WasReplay = 1;
            IF @Started = 1 COMMIT TRANSACTION;
            SELECT CONVERT(BIT, 1) AS Succeeded, N'replayed' AS Code,
                   @WasReplay AS WasReplay, summaries.*
            FROM dbo.FundingPlatform_ifn_SemanticEvaluationRunSummaries() AS summaries
            WHERE summaries.SemanticEvaluationRunId = @RunId;
            RETURN;
        END;

        IF @RuntimeEnabled <> 1
        BEGIN
            IF @Started = 1 COMMIT TRANSACTION;
            SELECT CONVERT(BIT, 0) AS Succeeded, N'semantic-processing-disabled' AS Code,
                   CONVERT(BIT, 0) AS WasReplay;
            RETURN;
        END;

        SELECT @ConfigurationId = configurations.Id,
               @ConfigurationVersion = configurations.Version,
               @ConfigFingerprint = configurations.ConfigurationFingerprint,
               @Provider = configurations.ProviderCode, @Model = configurations.ModelCode,
               @Dimensions = configurations.Dimensions, @Purpose = configurations.PurposeCode,
               @ProjectTemplate = configurations.ProjectTemplateVersion,
               @OpportunityTemplate = configurations.OpportunityTemplateVersion,
               @Normalization = configurations.NormalizationVersion,
               @MaximumInputBytes = configurations.MaximumInputUtf8Bytes,
               @MaximumAttempts = configurations.MaximumAttempts,
               @MaximumCost = configurations.MaximumCostUsdPerEmbedding,
               @MonthlyBudget = configurations.MonthlyBudgetUsd
        FROM dbo.FundingPlatform_SemanticConfigurations AS configurations WITH (UPDLOCK, HOLDLOCK)
        CROSS APPLY dbo.FundingPlatform_ifn_SemanticConfigurationState(configurations.Id) AS state
        WHERE CONCAT(configurations.Code, N'-v', configurations.Version) = @SemanticConfigurationVersion
          AND configurations.IsActive = 1
          AND configurations.ConfigurationFingerprint = state.CalculatedFingerprint;
        IF @ConfigurationId IS NULL
        BEGIN
            IF @Started = 1 COMMIT TRANSACTION;
            SELECT CONVERT(BIT, 0) AS Succeeded, N'configuration-not-approved' AS Code,
                   CONVERT(BIT, 0) AS WasReplay;
            RETURN;
        END;
        SELECT @EvaluationSetId = sets.Id, @SetVersion = sets.Version,
               @ManifestHash = sets.ManifestHash,
               @ActualProjects = state.ActualProjectCount,
               @ActualOpportunities = state.ActualOpportunityCount,
               @ActualLabels = state.ActualLabelCount
        FROM dbo.FundingPlatform_SemanticEvaluationSets AS sets WITH (UPDLOCK, HOLDLOCK)
        CROSS APPLY dbo.FundingPlatform_ifn_SemanticEvaluationSetState(sets.Id) AS state
        WHERE CONCAT(sets.Code, N'-v', sets.Version) = @EvaluationSetVersion
          AND sets.ManifestHash = state.CalculatedManifestHash
          AND sets.DeclaredProjectCount = state.ActualProjectCount
          AND sets.DeclaredOpportunityCount = state.ActualOpportunityCount
          AND sets.DeclaredLabelCount = state.ActualLabelCount;
        IF @EvaluationSetId IS NULL
        BEGIN
            IF @Started = 1 COMMIT TRANSACTION;
            SELECT CONVERT(BIT, 0) AS Succeeded, N'eval-set-not-ready' AS Code,
                   CONVERT(BIT, 0) AS WasReplay;
            RETURN;
        END;
        IF @ActualProjects NOT BETWEEN 30 AND 5000
           OR @ActualOpportunities NOT BETWEEN 100 AND 5000
           OR @ActualLabels NOT BETWEEN 300 AND 5000
        BEGIN
            IF @Started = 1 COMMIT TRANSACTION;
            SELECT CONVERT(BIT, 0) AS Succeeded, N'eval-set-not-ready' AS Code,
                   CONVERT(BIT, 0) AS WasReplay;
            RETURN;
        END;
        IF EXISTS
           (SELECT ProjectId FROM dbo.FundingPlatform_SemanticEvaluationCases
            WHERE EvaluationSetId = @EvaluationSetId
            GROUP BY ProjectId HAVING MIN(Split) <> MAX(Split))
           OR NOT EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationCases
               WHERE EvaluationSetId = @EvaluationSetId AND Split = 0)
           OR NOT EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationCases
               WHERE EvaluationSetId = @EvaluationSetId AND Split = 1)
           OR (SELECT COUNT(DISTINCT ProjectId)
               FROM dbo.FundingPlatform_SemanticEvaluationCases
               WHERE EvaluationSetId = @EvaluationSetId AND Split = 1) < 10
           OR (SELECT COUNT_BIG(1)
               FROM dbo.FundingPlatform_SemanticEvaluationCases
               WHERE EvaluationSetId = @EvaluationSetId AND Split = 1) < 100
           OR (SELECT COUNT_BIG(1)
               FROM dbo.FundingPlatform_SemanticEvaluationCases AS testCases
               INNER JOIN dbo.FundingPlatform_ProjectFundingMatches AS testMatches
                   ON testMatches.Id = testCases.ProjectFundingMatchId
               WHERE testCases.EvaluationSetId = @EvaluationSetId
                 AND testCases.Split = 1 AND testCases.RelevanceLabel > 0
                 AND testMatches.Classification <> 1) < 10
           OR NOT EXISTS
              (SELECT 1
               FROM dbo.FundingPlatform_SemanticEvaluationCases AS cases
               INNER JOIN dbo.FundingPlatform_ProjectFundingMatches AS matches
                   ON matches.Id = cases.ProjectFundingMatchId
               WHERE cases.EvaluationSetId = @EvaluationSetId AND cases.Split = 1
                 AND matches.Classification <> 1)
           OR EXISTS
              (SELECT cases.ProjectMatchingRunId
               FROM dbo.FundingPlatform_SemanticEvaluationCases AS cases
               INNER JOIN dbo.FundingPlatform_ProjectFundingMatches AS matches
                   ON matches.Id = cases.ProjectFundingMatchId
               WHERE cases.EvaluationSetId = @EvaluationSetId AND cases.Split = 1
               GROUP BY cases.ProjectMatchingRunId
               HAVING SUM(CASE WHEN cases.RelevanceLabel > 0
                                    AND matches.Classification <> 1 THEN 1 ELSE 0 END) = 0)
        BEGIN
            IF @Started = 1 COMMIT TRANSACTION;
            SELECT CONVERT(BIT, 0) AS Succeeded, N'eval-set-not-ready' AS Code,
                   CONVERT(BIT, 0) AS WasReplay;
            RETURN;
        END;

        EXEC @LockResult = sys.sp_getapplock
            @Resource = N'FundingPlatform:SemanticEvaluation:Active',
            @LockMode = N'Exclusive', @LockOwner = N'Transaction', @LockTimeout = 10000;
        IF @LockResult < 0 THROW 54128, N'Semantic evaluation singleton lock could not be acquired.', 1;
        IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationRuns WITH (UPDLOCK, HOLDLOCK)
                   WHERE ActiveSlot = 1)
        BEGIN
            IF @Started = 1 COMMIT TRANSACTION;
            SELECT CONVERT(BIT, 0) AS Succeeded, N'active-evaluation-exists' AS Code,
                   CONVERT(BIT, 0) AS WasReplay;
            RETURN;
        END;

        INSERT INTO dbo.FundingPlatform_SemanticEvaluationRuns
            (SemanticConfigurationId, SemanticConfigurationVersion,
             EvaluationSetId, EvaluationSetVersion, SemanticConfigurationFingerprint,
             EvaluationSetManifestHash, Status, ProjectCount, OpportunityCount,
             PairCount, PrimaryCohortCount, EvaluatedCount, LabelledCount,
             AttemptCount, NextAttemptAtUtc, RequestedByUserId,
             CreatedAtUtc, UpdatedAtUtc)
        SELECT @ConfigurationId, @ConfigurationVersion, @EvaluationSetId, @SetVersion,
               @ConfigFingerprint, @ManifestHash, 0, @ActualProjects, @ActualOpportunities,
               @ActualLabels,
               SUM(CASE WHEN cases.Split = 1 AND matches.Classification <> 1 THEN 1 ELSE 0 END),
               0, 0, 0, @NowUtc, @UserId, @NowUtc, @NowUtc
        FROM dbo.FundingPlatform_SemanticEvaluationCases AS cases
        INNER JOIN dbo.FundingPlatform_ProjectFundingMatches AS matches
            ON matches.Id = cases.ProjectFundingMatchId
        WHERE cases.EvaluationSetId = @EvaluationSetId;
        SET @RunId = CONVERT(BIGINT, SCOPE_IDENTITY());

        DECLARE @Subjects TABLE
        (
            SubjectType TINYINT NOT NULL, OrganizationId BIGINT NULL,
            ProjectId BIGINT NULL, ProjectVersion INT NULL,
            FundingOpportunityId BIGINT NULL, FundingContentVersion INT NULL,
            SubjectContentHash BINARY(32) NOT NULL, CanonicalInputJson NVARCHAR(MAX) NULL
        );
        INSERT INTO @Subjects
        SELECT 0, subjects.OrganizationId, subjects.ProjectId, subjects.ProjectVersion,
               NULL, NULL, subjects.ProjectContentHash,
               dbo.FundingPlatform_fn_ProjectSemanticCanonicalInput(versions.SnapshotJson)
        FROM (SELECT DISTINCT OrganizationId, ProjectId, ProjectVersion, ProjectContentHash
              FROM dbo.FundingPlatform_SemanticEvaluationCases
              WHERE EvaluationSetId = @EvaluationSetId) AS subjects
        INNER JOIN dbo.FundingPlatform_ProjectVersions AS versions
            ON versions.ProjectId = subjects.ProjectId
           AND versions.ProjectVersion = subjects.ProjectVersion;
        INSERT INTO @Subjects
        SELECT 1, NULL, NULL, NULL, subjects.FundingOpportunityId,
               subjects.FundingContentVersion, subjects.OpportunityContentHash,
               dbo.FundingPlatform_fn_OpportunitySemanticCanonicalInput(versions.SnapshotJson)
        FROM (SELECT DISTINCT FundingOpportunityId, FundingContentVersion, OpportunityContentHash
              FROM dbo.FundingPlatform_SemanticEvaluationCases
              WHERE EvaluationSetId = @EvaluationSetId) AS subjects
        INNER JOIN dbo.FundingPlatform_FundingOpportunityVersions AS versions
            ON versions.FundingOpportunityId = subjects.FundingOpportunityId
           AND versions.ContentVersion = subjects.FundingContentVersion;
        IF EXISTS
           (SELECT 1 FROM @Subjects
            WHERE dbo.FundingPlatform_fn_SemanticInputRiskCode
                (CanonicalInputJson, @MaximumInputBytes) IS NOT NULL)
        BEGIN
            IF @Started = 1 ROLLBACK TRANSACTION;
            ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
                ROLLBACK TRANSACTION FP_SemanticEvalCreate;
            SELECT CONVERT(BIT, 0) AS Succeeded, N'eval-set-not-ready' AS Code,
                   CONVERT(BIT, 0) AS WasReplay;
            RETURN;
        END;

        DECLARE @PreparedJobs TABLE
        (
            SubjectType TINYINT NOT NULL, OrganizationId BIGINT NULL,
            ProjectId BIGINT NULL, ProjectVersion INT NULL,
            FundingOpportunityId BIGINT NULL, FundingContentVersion INT NULL,
            SubjectContentHash BINARY(32) NOT NULL, InputContentHash BINARY(32) NOT NULL,
            ContentAddress BINARY(32) NOT NULL UNIQUE
        );
        INSERT INTO @PreparedJobs
        SELECT subjects.SubjectType, subjects.OrganizationId, subjects.ProjectId,
               subjects.ProjectVersion, subjects.FundingOpportunityId,
               subjects.FundingContentVersion, subjects.SubjectContentHash,
               calculated.InputHash,
               CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
               (
                   N'semantic-embedding-v1|', subjects.SubjectType, N'|',
                   COALESCE(CONVERT(NVARCHAR(30), subjects.OrganizationId), N'global'), N'|',
                   COALESCE(CONVERT(NVARCHAR(30), subjects.ProjectId), N'-'), N'|',
                   COALESCE(CONVERT(NVARCHAR(20), subjects.ProjectVersion), N'-'), N'|',
                   COALESCE(CONVERT(NVARCHAR(30), subjects.FundingOpportunityId), N'-'), N'|',
                   COALESCE(CONVERT(NVARCHAR(20), subjects.FundingContentVersion), N'-'), N'|',
                   CONVERT(VARCHAR(64), subjects.SubjectContentHash, 2), N'|',
                   CONVERT(VARCHAR(64), calculated.InputHash, 2), N'|',
                   @Provider, N'|', @Model, N'|', @Dimensions, N'|', @Purpose, N'|',
                   CASE subjects.SubjectType WHEN 0 THEN @ProjectTemplate ELSE @OpportunityTemplate END,
                   N'|', @Normalization, N'|', @ConfigurationVersion, N'|',
                   CONVERT(VARCHAR(64), @ConfigFingerprint, 2)
               ))))
        FROM @Subjects AS subjects
        CROSS APPLY (SELECT dbo.FundingPlatform_fn_SemanticInputHash
            (subjects.CanonicalInputJson) AS InputHash) AS calculated;

        DECLARE @BudgetLockResult INT;
        EXEC @BudgetLockResult = sys.sp_getapplock
            @Resource = N'FundingPlatform:SemanticBudget', @LockMode = N'Exclusive',
            @LockOwner = N'Transaction', @LockTimeout = 10000;
        IF @BudgetLockResult < 0
            THROW 54109, N'Semantic budget lock could not be acquired.', 1;
        DECLARE @BudgetMonth DATE = DATEFROMPARTS(YEAR(@NowUtc), MONTH(@NowUtc), 1);
        DECLARE @CommittedCost DECIMAL(19,6) = COALESCE
        (
            (SELECT SUM(CASE reservations.Status WHEN 0 THEN reservations.ReservedCostUsd
                                                 WHEN 1 THEN reservations.ConsumedCostUsd END)
             FROM dbo.FundingPlatform_SemanticBudgetReservations AS reservations
                  WITH (UPDLOCK, HOLDLOCK)
             WHERE reservations.SemanticConfigurationId = @ConfigurationId
               AND reservations.BudgetMonth = @BudgetMonth
               AND reservations.Status IN (0, 1)), 0
        );
        DECLARE @AdditionalWorstCaseCost DECIMAL(19,6) = COALESCE
        (
            (SELECT SUM(CONVERT(DECIMAL(19,6), @MaximumCost *
                CASE
                    WHEN embeddings.Id IS NOT NULL THEN 0
                    WHEN latest.Status IN (0, 1, 3)
                        THEN @MaximumAttempts - latest.AttemptCount
                    WHEN latest.Status = 5 AND latest.ErrorCode = N'stale-subject'
                        THEN @MaximumAttempts
                    WHEN latest.Id IS NULL THEN @MaximumAttempts
                    ELSE 0
                END))
             FROM @PreparedJobs AS prepared
             OUTER APPLY
             (SELECT TOP (1) existing.Id, existing.Status, existing.AttemptCount,
                            existing.ErrorCode
              FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS existing
                   WITH (UPDLOCK, HOLDLOCK)
              WHERE existing.ContentAddress = prepared.ContentAddress
              ORDER BY existing.JobGeneration DESC) AS latest
             OUTER APPLY
             (SELECT TOP (1) existing.Id
              FROM dbo.FundingPlatform_SemanticEmbeddings AS existing WITH (UPDLOCK, HOLDLOCK)
              WHERE existing.ContentAddress = prepared.ContentAddress) AS embeddings), 0
        );
        IF @CommittedCost + @AdditionalWorstCaseCost > @MonthlyBudget
        BEGIN
            IF @Started = 1 ROLLBACK TRANSACTION;
            ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
                ROLLBACK TRANSACTION FP_SemanticEvalCreate;
            SELECT CONVERT(BIT, 0) AS Succeeded, N'budget-insufficient' AS Code,
                   CONVERT(BIT, 0) AS WasReplay;
            RETURN;
        END;

        INSERT INTO dbo.FundingPlatform_SemanticEvaluationRunCases
            (SemanticEvaluationRunId, EvaluationSetId, CaseOrdinal,
             ProjectMatchingRunId, ProjectFundingMatchId, OrganizationId,
             ProjectId, ProjectVersion, FundingOpportunityId, FundingContentVersion,
             ProjectContentHash, OpportunityContentHash,
             ProjectInputContentHash, OpportunityInputContentHash,
             ProjectContentAddress, OpportunityContentAddress,
             DatasetSplit, RelevanceLabel, CreatedAtUtc)
        SELECT @RunId, cases.EvaluationSetId, cases.Ordinal,
               cases.ProjectMatchingRunId, cases.ProjectFundingMatchId, cases.OrganizationId,
               cases.ProjectId, cases.ProjectVersion, cases.FundingOpportunityId,
               cases.FundingContentVersion, cases.ProjectContentHash,
               cases.OpportunityContentHash, projectInputs.InputContentHash,
               opportunityInputs.InputContentHash, projectInputs.ContentAddress,
               opportunityInputs.ContentAddress, cases.Split, cases.RelevanceLabel, @NowUtc
        FROM dbo.FundingPlatform_SemanticEvaluationCases AS cases
        INNER JOIN @PreparedJobs AS projectInputs
            ON projectInputs.SubjectType = 0
           AND projectInputs.OrganizationId = cases.OrganizationId
           AND projectInputs.ProjectId = cases.ProjectId
           AND projectInputs.ProjectVersion = cases.ProjectVersion
           AND projectInputs.SubjectContentHash = cases.ProjectContentHash
        INNER JOIN @PreparedJobs AS opportunityInputs
            ON opportunityInputs.SubjectType = 1
           AND opportunityInputs.FundingOpportunityId = cases.FundingOpportunityId
           AND opportunityInputs.FundingContentVersion = cases.FundingContentVersion
           AND opportunityInputs.SubjectContentHash = cases.OpportunityContentHash
        WHERE cases.EvaluationSetId = @EvaluationSetId;
        IF @@ROWCOUNT <> @ActualLabels
            THROW 54129, N'Evaluation corpus could not freeze every exact semantic input address.', 1;

        INSERT INTO dbo.FundingPlatform_SemanticEmbeddingJobs
            (SemanticConfigurationId, SemanticConfigurationVersion, SubjectType,
             OrganizationId, ProjectId, ProjectVersion, FundingOpportunityId,
             FundingContentVersion, SubjectContentHash, InputContentHash, ContentAddress,
             JobGeneration, AllowHistorical, Status, AttemptCount, MaximumAttempts, NextAttemptAtUtc,
             CreatedAtUtc, UpdatedAtUtc)
        SELECT @ConfigurationId, @ConfigurationVersion, jobs.SubjectType,
               jobs.OrganizationId, jobs.ProjectId, jobs.ProjectVersion,
               jobs.FundingOpportunityId, jobs.FundingContentVersion,
               jobs.SubjectContentHash, jobs.InputContentHash, jobs.ContentAddress,
               generation.NextGeneration, 1, 0, 0, @MaximumAttempts, @NowUtc, @NowUtc, @NowUtc
        FROM @PreparedJobs AS jobs
        CROSS APPLY
        (SELECT CONVERT(SMALLINT, COALESCE(MAX(existing.JobGeneration), 0) + 1) AS NextGeneration
         FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS existing WITH (UPDLOCK, HOLDLOCK)
         WHERE existing.ContentAddress = jobs.ContentAddress) AS generation
        WHERE NOT EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS existing
                        WITH (UPDLOCK, HOLDLOCK)
               WHERE existing.ContentAddress = jobs.ContentAddress
                 AND (existing.Status <> 5 OR existing.ErrorCode <> N'stale-subject'))
          AND NOT EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddings AS existing
                        WITH (UPDLOCK, HOLDLOCK)
               WHERE existing.ContentAddress = jobs.ContentAddress);

        INSERT INTO dbo.FundingPlatform_SemanticEvaluationRunRequests
            (UserId, IdempotencyKeyHash, RequestHash, SemanticEvaluationRunId, CreatedAtUtc)
        VALUES (@UserId, @IdempotencyKeyHash, @RequestHash, @RunId, @NowUtc);

        IF @Started = 1 COMMIT TRANSACTION;
        SELECT CONVERT(BIT, 1) AS Succeeded, N'queued' AS Code,
               CONVERT(BIT, 0) AS WasReplay, summaries.*
        FROM dbo.FundingPlatform_ifn_SemanticEvaluationRunSummaries() AS summaries
        WHERE summaries.SemanticEvaluationRunId = @RunId;
    END TRY
    BEGIN CATCH
        IF @Started = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_SemanticEvalCreate;
        THROW;
    END CATCH;
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
        FROM inserted
        INNER JOIN deleted ON deleted.Id = inserted.Id
        WHERE deleted.IsActive = 1 AND inserted.IsActive = 0
          AND
          (EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
              WHERE jobs.SemanticConfigurationId = inserted.Id AND jobs.Status IN (0, 1, 3))
           OR EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationRuns AS runs
              WHERE runs.SemanticConfigurationId = inserted.Id AND runs.Status IN (0, 1, 3))
           OR EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_SemanticBudgetReservations AS reservations
              WHERE reservations.SemanticConfigurationId = inserted.Id AND reservations.Status = 0)))
        THROW 54102, N'Semantic configuration must drain all active jobs, evaluations and reservations before deactivation.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticEvaluationSets_Immutable
ON dbo.FundingPlatform_SemanticEvaluationSets
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted)
        THROW 54102, N'Reviewed semantic evaluation sets are immutable.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticEvaluationCases_Immutable
ON dbo.FundingPlatform_SemanticEvaluationCases
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted)
       OR EXISTS
          (SELECT 1
           FROM inserted
           WHERE EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationRuns AS runs
            WHERE runs.EvaluationSetId = inserted.EvaluationSetId))
        THROW 54102, N'Semantic evaluation cases are immutable after use.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticEvaluationCases_SubjectGuard
ON dbo.FundingPlatform_SemanticEvaluationCases
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS
       (SELECT 1
        FROM inserted
        LEFT JOIN dbo.FundingPlatform_ProjectMatchingRuns AS matchingRuns
            ON matchingRuns.Id = inserted.ProjectMatchingRunId
           AND matchingRuns.OrganizationId = inserted.OrganizationId
           AND matchingRuns.ProjectId = inserted.ProjectId
           AND matchingRuns.ProjectVersion = inserted.ProjectVersion
           AND matchingRuns.Status = 2
        LEFT JOIN dbo.FundingPlatform_ProjectFundingMatches AS matches
            ON matches.Id = inserted.ProjectFundingMatchId
           AND matches.MatchRunId = matchingRuns.Id
           AND matches.OrganizationId = inserted.OrganizationId
           AND matches.ProjectId = inserted.ProjectId
           AND matches.ProjectVersion = inserted.ProjectVersion
           AND matches.FundingOpportunityId = inserted.FundingOpportunityId
           AND matches.FundingContentVersion = inserted.FundingContentVersion
        LEFT JOIN dbo.FundingPlatform_ProjectVersions AS projectVersions
            ON projectVersions.ProjectId = inserted.ProjectId
           AND projectVersions.ProjectVersion = inserted.ProjectVersion
           AND projectVersions.ContentHash = inserted.ProjectContentHash
        LEFT JOIN dbo.FundingPlatform_FundingOpportunityVersions AS opportunityVersions
            ON opportunityVersions.FundingOpportunityId = inserted.FundingOpportunityId
           AND opportunityVersions.ContentVersion = inserted.FundingContentVersion
           AND opportunityVersions.ContentHash = inserted.OpportunityContentHash
        WHERE matchingRuns.Id IS NULL OR matches.Id IS NULL
           OR projectVersions.ProjectId IS NULL OR opportunityVersions.FundingOpportunityId IS NULL)
        THROW 54103, N'Evaluation case must bind exact completed 9A run, match, tenant, versions and content hashes.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticEmbeddings_SupersessionOnly
ON dbo.FundingPlatform_SemanticEmbeddings
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF UPDATE(Embedding)
       OR EXISTS (SELECT 1 FROM deleted WHERE NOT EXISTS
               (SELECT 1 FROM inserted WHERE inserted.Id = deleted.Id))
       OR EXISTS
          (SELECT 1
           FROM inserted
           INNER JOIN deleted ON deleted.Id = inserted.Id
           WHERE deleted.IsCurrent <> 1 OR deleted.RetiredAtUtc IS NOT NULL
              OR inserted.IsCurrent <> 0 OR inserted.RetiredAtUtc IS NULL
              OR inserted.RetiredAtUtc < deleted.CreatedAtUtc)
       OR EXISTS
          (SELECT Id, PublicId, SourceJobId, SemanticConfigurationId,
                  SemanticConfigurationVersion, SubjectType, OrganizationId,
                  ProjectId, ProjectVersion, FundingOpportunityId,
                  FundingContentVersion, SubjectContentHash, InputContentHash,
                  ContentAddress, EmbeddingVersion, ProviderCode,
                  EffectiveModelCode, Dimensions, PurposeCode, TemplateVersion,
                  NormalizationVersion, EmbeddingHash, ProviderRequestIdHash, CreatedAtUtc
           FROM inserted
           EXCEPT
           SELECT Id, PublicId, SourceJobId, SemanticConfigurationId,
                  SemanticConfigurationVersion, SubjectType, OrganizationId,
                  ProjectId, ProjectVersion, FundingOpportunityId,
                  FundingContentVersion, SubjectContentHash, InputContentHash,
                  ContentAddress, EmbeddingVersion, ProviderCode,
                  EffectiveModelCode, Dimensions, PurposeCode, TemplateVersion,
                  NormalizationVersion, EmbeddingHash, ProviderRequestIdHash, CreatedAtUtc
           FROM deleted)
       OR EXISTS
          (SELECT Id, PublicId, SourceJobId, SemanticConfigurationId,
                  SemanticConfigurationVersion, SubjectType, OrganizationId,
                  ProjectId, ProjectVersion, FundingOpportunityId,
                  FundingContentVersion, SubjectContentHash, InputContentHash,
                  ContentAddress, EmbeddingVersion, ProviderCode,
                  EffectiveModelCode, Dimensions, PurposeCode, TemplateVersion,
                  NormalizationVersion, EmbeddingHash, ProviderRequestIdHash, CreatedAtUtc
           FROM deleted
           EXCEPT
           SELECT Id, PublicId, SourceJobId, SemanticConfigurationId,
                  SemanticConfigurationVersion, SubjectType, OrganizationId,
                  ProjectId, ProjectVersion, FundingOpportunityId,
                  FundingContentVersion, SubjectContentHash, InputContentHash,
                  ContentAddress, EmbeddingVersion, ProviderCode,
                  EffectiveModelCode, Dimensions, PurposeCode, TemplateVersion,
                  NormalizationVersion, EmbeddingHash, ProviderRequestIdHash, CreatedAtUtc
           FROM inserted)
       /* VECTOR cannot participate in EXCEPT; its server-derived hash freezes it. */
        THROW 54102, N'Semantic embeddings are immutable except for exact one-way supersession.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticEmbeddings_SubjectGuard
ON dbo.FundingPlatform_SemanticEmbeddings
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS
       (SELECT 1
        FROM inserted
        LEFT JOIN dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
            ON jobs.Id = inserted.SourceJobId
           AND jobs.Status = 1
           AND jobs.SemanticConfigurationId = inserted.SemanticConfigurationId
           AND jobs.SemanticConfigurationVersion = inserted.SemanticConfigurationVersion
           AND jobs.SubjectType = inserted.SubjectType
           AND ISNULL(jobs.OrganizationId, -1) = ISNULL(inserted.OrganizationId, -1)
           AND ISNULL(jobs.ProjectId, -1) = ISNULL(inserted.ProjectId, -1)
           AND ISNULL(jobs.ProjectVersion, -1) = ISNULL(inserted.ProjectVersion, -1)
           AND ISNULL(jobs.FundingOpportunityId, -1) = ISNULL(inserted.FundingOpportunityId, -1)
           AND ISNULL(jobs.FundingContentVersion, -1) = ISNULL(inserted.FundingContentVersion, -1)
           AND jobs.SubjectContentHash = inserted.SubjectContentHash
           AND jobs.InputContentHash = inserted.InputContentHash
           AND jobs.ContentAddress = inserted.ContentAddress
        LEFT JOIN dbo.FundingPlatform_SemanticConfigurations AS configurations
            ON configurations.Id = inserted.SemanticConfigurationId
           AND configurations.Version = inserted.SemanticConfigurationVersion
           AND configurations.ProviderCode COLLATE Latin1_General_100_BIN2 =
               inserted.ProviderCode COLLATE Latin1_General_100_BIN2
           AND DATALENGTH(configurations.ProviderCode) = DATALENGTH(inserted.ProviderCode)
           AND configurations.ModelCode COLLATE Latin1_General_100_BIN2 =
               inserted.EffectiveModelCode COLLATE Latin1_General_100_BIN2
           AND DATALENGTH(configurations.ModelCode) = DATALENGTH(inserted.EffectiveModelCode)
           AND configurations.Dimensions = inserted.Dimensions
           AND configurations.PurposeCode COLLATE Latin1_General_100_BIN2 =
               inserted.PurposeCode COLLATE Latin1_General_100_BIN2
           AND DATALENGTH(configurations.PurposeCode) = DATALENGTH(inserted.PurposeCode)
           AND configurations.NormalizationVersion COLLATE Latin1_General_100_BIN2 =
               inserted.NormalizationVersion COLLATE Latin1_General_100_BIN2
           AND DATALENGTH(configurations.NormalizationVersion) =
               DATALENGTH(inserted.NormalizationVersion)
           AND ((inserted.SubjectType = 0
                 AND configurations.ProjectTemplateVersion COLLATE Latin1_General_100_BIN2 =
                     inserted.TemplateVersion COLLATE Latin1_General_100_BIN2
                 AND DATALENGTH(configurations.ProjectTemplateVersion) =
                     DATALENGTH(inserted.TemplateVersion))
                OR (inserted.SubjectType = 1
                    AND configurations.OpportunityTemplateVersion COLLATE Latin1_General_100_BIN2 =
                        inserted.TemplateVersion COLLATE Latin1_General_100_BIN2
                    AND DATALENGTH(configurations.OpportunityTemplateVersion) =
                        DATALENGTH(inserted.TemplateVersion)))
        OUTER APPLY
           (SELECT VECTOR_DISTANCE('cosine', inserted.Embedding, inserted.Embedding)
                AS SelfDistance) AS vectorState
        WHERE jobs.Id IS NULL OR configurations.Id IS NULL
           OR vectorState.SelfDistance IS NULL OR ABS(vectorState.SelfDistance) > 0.000001
           OR inserted.EmbeddingHash <>
              HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(NVARCHAR(MAX), inserted.Embedding))))
        THROW 54103, N'Embedding output must match its exact job, subject, configuration and server vector hash.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticUsageLedger_Immutable
ON dbo.FundingPlatform_SemanticUsageLedger
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted)
        THROW 54102, N'Semantic usage history is immutable.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticEvaluationItems_Immutable
ON dbo.FundingPlatform_SemanticEvaluationItems
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted)
        THROW 54102, N'Shadow semantic evaluation items are immutable.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticEvaluationRunCases_Immutable
ON dbo.FundingPlatform_SemanticEvaluationRunCases
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted)
        THROW 54102, N'Frozen semantic evaluation run cases are immutable.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticEvaluationRunCases_CopyGuard
ON dbo.FundingPlatform_SemanticEvaluationRunCases
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS
       (SELECT 1
        FROM inserted
        LEFT JOIN dbo.FundingPlatform_SemanticEvaluationRuns AS runs
            ON runs.Id = inserted.SemanticEvaluationRunId
           AND runs.EvaluationSetId = inserted.EvaluationSetId
        LEFT JOIN dbo.FundingPlatform_SemanticEvaluationCases AS cases
            ON cases.EvaluationSetId = inserted.EvaluationSetId
           AND cases.Ordinal = inserted.CaseOrdinal
           AND cases.ProjectMatchingRunId = inserted.ProjectMatchingRunId
           AND cases.ProjectFundingMatchId = inserted.ProjectFundingMatchId
           AND cases.OrganizationId = inserted.OrganizationId
           AND cases.ProjectId = inserted.ProjectId
           AND cases.ProjectVersion = inserted.ProjectVersion
           AND cases.FundingOpportunityId = inserted.FundingOpportunityId
           AND cases.FundingContentVersion = inserted.FundingContentVersion
           AND cases.ProjectContentHash = inserted.ProjectContentHash
           AND cases.OpportunityContentHash = inserted.OpportunityContentHash
           AND cases.Split = inserted.DatasetSplit
           AND cases.RelevanceLabel = inserted.RelevanceLabel
        LEFT JOIN dbo.FundingPlatform_SemanticConfigurations AS configurations
            ON configurations.Id = runs.SemanticConfigurationId
           AND configurations.Version = runs.SemanticConfigurationVersion
           AND configurations.ConfigurationFingerprint = runs.SemanticConfigurationFingerprint
        LEFT JOIN dbo.FundingPlatform_ProjectVersions AS projectVersions
            ON projectVersions.ProjectId = inserted.ProjectId
           AND projectVersions.ProjectVersion = inserted.ProjectVersion
           AND projectVersions.ContentHash = inserted.ProjectContentHash
        LEFT JOIN dbo.FundingPlatform_FundingOpportunityVersions AS opportunityVersions
            ON opportunityVersions.FundingOpportunityId = inserted.FundingOpportunityId
           AND opportunityVersions.ContentVersion = inserted.FundingContentVersion
           AND opportunityVersions.ContentHash = inserted.OpportunityContentHash
        OUTER APPLY
           (SELECT dbo.FundingPlatform_fn_SemanticInputHash
                (dbo.FundingPlatform_fn_ProjectSemanticCanonicalInput(projectVersions.SnapshotJson))
                AS InputHash) AS projectInput
        OUTER APPLY
           (SELECT dbo.FundingPlatform_fn_SemanticInputHash
                (dbo.FundingPlatform_fn_OpportunitySemanticCanonicalInput(opportunityVersions.SnapshotJson))
                AS InputHash) AS opportunityInput
        OUTER APPLY
           (SELECT CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
            (N'semantic-embedding-v1|0|', inserted.OrganizationId, N'|', inserted.ProjectId,
             N'|', inserted.ProjectVersion, N'|-|-|',
             CONVERT(VARCHAR(64), inserted.ProjectContentHash, 2), N'|',
             CONVERT(VARCHAR(64), projectInput.InputHash, 2), N'|',
             configurations.ProviderCode, N'|', configurations.ModelCode, N'|',
             configurations.Dimensions, N'|', configurations.PurposeCode, N'|',
             configurations.ProjectTemplateVersion, N'|', configurations.NormalizationVersion,
             N'|', configurations.Version, N'|',
             CONVERT(VARCHAR(64), configurations.ConfigurationFingerprint, 2))))) AS ContentAddress)
             AS projectAddress
        OUTER APPLY
           (SELECT CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
            (N'semantic-embedding-v1|1|global|-|-|', inserted.FundingOpportunityId,
             N'|', inserted.FundingContentVersion, N'|',
             CONVERT(VARCHAR(64), inserted.OpportunityContentHash, 2), N'|',
             CONVERT(VARCHAR(64), opportunityInput.InputHash, 2), N'|',
             configurations.ProviderCode, N'|', configurations.ModelCode, N'|',
             configurations.Dimensions, N'|', configurations.PurposeCode, N'|',
             configurations.OpportunityTemplateVersion, N'|', configurations.NormalizationVersion,
             N'|', configurations.Version, N'|',
             CONVERT(VARCHAR(64), configurations.ConfigurationFingerprint, 2))))) AS ContentAddress)
             AS opportunityAddress
        WHERE runs.Id IS NULL OR cases.EvaluationSetId IS NULL
           OR configurations.Id IS NULL OR projectVersions.ProjectId IS NULL
           OR opportunityVersions.FundingOpportunityId IS NULL
           OR projectInput.InputHash IS NULL OR opportunityInput.InputHash IS NULL
           OR projectAddress.ContentAddress IS NULL OR opportunityAddress.ContentAddress IS NULL
           OR inserted.ProjectInputContentHash <> projectInput.InputHash
           OR inserted.OpportunityInputContentHash <> opportunityInput.InputHash
           OR inserted.ProjectContentAddress <> projectAddress.ContentAddress
           OR inserted.OpportunityContentAddress <> opportunityAddress.ContentAddress)
        THROW 54103, N'Evaluation run case must be an exact immutable copy of its reviewed corpus case.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticEvaluationItems_SubjectGuard
ON dbo.FundingPlatform_SemanticEvaluationItems
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS
       (SELECT 1
        FROM inserted
        LEFT JOIN dbo.FundingPlatform_SemanticEvaluationRunCases AS runCases
            ON runCases.SemanticEvaluationRunId = inserted.SemanticEvaluationRunId
           AND runCases.CaseOrdinal = inserted.CaseOrdinal
           AND runCases.ProjectFundingMatchId = inserted.ProjectFundingMatchId
        LEFT JOIN dbo.FundingPlatform_SemanticEvaluationRuns AS evaluationRuns
            ON evaluationRuns.Id = runCases.SemanticEvaluationRunId
        LEFT JOIN dbo.FundingPlatform_ProjectFundingMatches AS matches
            ON matches.Id = runCases.ProjectFundingMatchId
        LEFT JOIN dbo.FundingPlatform_SemanticEmbeddings AS projectEmbeddings
            ON projectEmbeddings.Id = inserted.ProjectEmbeddingId
           AND projectEmbeddings.SemanticConfigurationId = evaluationRuns.SemanticConfigurationId
           AND projectEmbeddings.SubjectType = 0
           AND projectEmbeddings.OrganizationId = runCases.OrganizationId
           AND projectEmbeddings.ProjectId = runCases.ProjectId
           AND projectEmbeddings.ProjectVersion = runCases.ProjectVersion
           AND projectEmbeddings.SubjectContentHash = runCases.ProjectContentHash
           AND projectEmbeddings.InputContentHash = runCases.ProjectInputContentHash
           AND projectEmbeddings.ContentAddress = runCases.ProjectContentAddress
        LEFT JOIN dbo.FundingPlatform_SemanticEmbeddings AS opportunityEmbeddings
            ON opportunityEmbeddings.Id = inserted.OpportunityEmbeddingId
           AND opportunityEmbeddings.SemanticConfigurationId = evaluationRuns.SemanticConfigurationId
           AND opportunityEmbeddings.SubjectType = 1
           AND opportunityEmbeddings.OrganizationId IS NULL
           AND opportunityEmbeddings.FundingOpportunityId = runCases.FundingOpportunityId
           AND opportunityEmbeddings.FundingContentVersion = runCases.FundingContentVersion
           AND opportunityEmbeddings.SubjectContentHash = runCases.OpportunityContentHash
           AND opportunityEmbeddings.InputContentHash = runCases.OpportunityInputContentHash
           AND opportunityEmbeddings.ContentAddress = runCases.OpportunityContentAddress
        OUTER APPLY
           (SELECT VECTOR_DISTANCE('cosine', projectEmbeddings.Embedding,
                                             opportunityEmbeddings.Embedding) AS RawDistance)
             AS vectorDistance
        OUTER APPLY
           (SELECT CONVERT(DECIMAL(9,8),
               CASE WHEN vectorDistance.RawDistance < 0 THEN 0
                    WHEN vectorDistance.RawDistance > 2 THEN 2
                    ELSE vectorDistance.RawDistance END) AS ExpectedDistance)
             AS calculated
        WHERE runCases.SemanticEvaluationRunId IS NULL OR evaluationRuns.Id IS NULL
           OR projectEmbeddings.Id IS NULL OR opportunityEmbeddings.Id IS NULL
           OR calculated.ExpectedDistance IS NULL
           OR inserted.CosineDistance <> calculated.ExpectedDistance
           OR inserted.CosineSimilarity <>
              CONVERT(DECIMAL(9,8), 1 - calculated.ExpectedDistance)
           OR inserted.SemanticScore <>
              CONVERT(DECIMAL(5,2), (2 - calculated.ExpectedDistance) * 50)
           OR inserted.RelevanceLabel <> runCases.RelevanceLabel
           OR inserted.DatasetSplit <> runCases.DatasetSplit
           OR inserted.IsPrimaryCohort <>
              CASE WHEN runCases.DatasetSplit = 1 AND matches.Classification <> 1
                   THEN 1 ELSE 0 END)
        THROW 54103, N'Shadow item subjects, versions, tenant and configuration must match the frozen 9A run.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticBudgetReservations_SubjectGuard
ON dbo.FundingPlatform_SemanticBudgetReservations
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS
       (SELECT 1
        FROM inserted
        LEFT JOIN dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
            ON jobs.Id = inserted.EmbeddingJobId
           AND jobs.SemanticConfigurationId = inserted.SemanticConfigurationId
        WHERE jobs.Id IS NULL)
        THROW 54103, N'Budget reservation must match its embedding job configuration.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticBudgetReservations_Lifecycle
ON dbo.FundingPlatform_SemanticBudgetReservations
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted WHERE NOT EXISTS
               (SELECT 1 FROM inserted WHERE inserted.Id = deleted.Id))
       OR EXISTS
          (SELECT 1 FROM inserted INNER JOIN deleted ON deleted.Id = inserted.Id
           WHERE deleted.Status <> 0 OR inserted.Status NOT IN (0, 1, 2, 3)
              OR inserted.PublicId <> deleted.PublicId
              OR inserted.SemanticConfigurationId <> deleted.SemanticConfigurationId
              OR inserted.EmbeddingJobId <> deleted.EmbeddingJobId
              OR inserted.BudgetMonth <> deleted.BudgetMonth
              OR inserted.ReservedCostUsd <> deleted.ReservedCostUsd
              OR inserted.LeaseId <> deleted.LeaseId
              OR (inserted.Status = 0 AND inserted.ExpiresAtUtc < deleted.ExpiresAtUtc)
              OR (inserted.Status IN (1, 2, 3)
                  AND inserted.ExpiresAtUtc <> deleted.ExpiresAtUtc)
              OR inserted.CreatedAtUtc <> deleted.CreatedAtUtc)
        THROW 54102, N'Budget reservation identity and terminal state are immutable.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticUsageLedger_SubjectGuard
ON dbo.FundingPlatform_SemanticUsageLedger
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS
       (SELECT 1
        FROM inserted
        LEFT JOIN dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
            ON jobs.Id = inserted.EmbeddingJobId
           AND jobs.SemanticConfigurationId = inserted.SemanticConfigurationId
        LEFT JOIN dbo.FundingPlatform_SemanticBudgetReservations AS reservations
            ON reservations.Id = inserted.BudgetReservationId
           AND reservations.EmbeddingJobId = jobs.Id
           AND reservations.SemanticConfigurationId = jobs.SemanticConfigurationId
        WHERE jobs.Id IS NULL OR reservations.Id IS NULL
           OR reservations.Status <> 1
           OR reservations.ConsumedCostUsd <> inserted.EstimatedCostUsd
           OR reservations.BudgetMonth <> inserted.BudgetMonth
           OR (jobs.SubjectType = 0
               AND (inserted.OrganizationId IS NULL
                    OR inserted.OrganizationId <> jobs.OrganizationId))
           OR (jobs.SubjectType = 1 AND inserted.OrganizationId IS NOT NULL))
        THROW 54103, N'Semantic usage must match reservation, job, configuration and tenant scope.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticEvaluationRuns_PromotionGuard
ON dbo.FundingPlatform_SemanticEvaluationRuns
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS
       (SELECT 1
        FROM inserted
        INNER JOIN dbo.FundingPlatform_SemanticConfigurations AS configurations
            ON configurations.Id = inserted.SemanticConfigurationId
        WHERE inserted.IsPromotionEligible = 1
          AND (configurations.IsLocalFake = 1 OR inserted.Status <> 2
               OR inserted.EvaluatedCount <> inserted.PairCount
               OR inserted.CoveragePercentage IS NULL OR inserted.CoveragePercentage < 95
               OR inserted.SuccessPercentage IS NULL OR inserted.SuccessPercentage < 99
               OR inserted.RecallAt10 IS NULL OR inserted.RecallAt10 < 0.80
               OR inserted.NdcgAt10 IS NULL OR inserted.NdcgAt10 < 0.75
               OR inserted.NdcgDelta IS NULL OR inserted.NdcgDelta < 0.05
               OR inserted.HardFailPromotedCount IS NULL
               OR inserted.HardFailPromotedCount <> 0))
        THROW 54103, N'Local fake or below-gate shadow evaluations cannot be promotion eligible.', 1;
    IF EXISTS
       (SELECT 1 FROM inserted
        INNER JOIN dbo.FundingPlatform_SemanticConfigurations AS configurations
            ON configurations.Id = inserted.SemanticConfigurationId
        WHERE configurations.IsLocalFake = 1 AND inserted.IsPromotionEligible <> 0)
        THROW 54103, N'Local fake evaluations are explicitly non-promotable.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticEvaluationRuns_SubjectGuard
ON dbo.FundingPlatform_SemanticEvaluationRuns
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS
       (SELECT 1
        FROM inserted
        LEFT JOIN dbo.FundingPlatform_SemanticConfigurations AS configurations
            ON configurations.Id = inserted.SemanticConfigurationId
           AND configurations.Version = inserted.SemanticConfigurationVersion
        OUTER APPLY dbo.FundingPlatform_ifn_SemanticConfigurationState
            (inserted.SemanticConfigurationId) AS configState
        LEFT JOIN dbo.FundingPlatform_SemanticEvaluationSets AS sets
            ON sets.Id = inserted.EvaluationSetId AND sets.Version = inserted.EvaluationSetVersion
        OUTER APPLY dbo.FundingPlatform_ifn_SemanticEvaluationSetState
            (inserted.EvaluationSetId) AS setState
        WHERE configurations.Id IS NULL OR sets.Id IS NULL
           OR configurations.IsActive <> 1
           OR inserted.SemanticConfigurationFingerprint <> configurations.ConfigurationFingerprint
           OR configurations.ConfigurationFingerprint <> configState.CalculatedFingerprint
           OR inserted.EvaluationSetManifestHash <> sets.ManifestHash
           OR sets.ManifestHash <> setState.CalculatedManifestHash
           OR inserted.ProjectCount <> setState.ActualProjectCount
           OR inserted.OpportunityCount <> setState.ActualOpportunityCount
           OR inserted.PairCount <> setState.ActualLabelCount
           OR inserted.PrimaryCohortCount <>
              (SELECT COUNT(1)
               FROM dbo.FundingPlatform_SemanticEvaluationCases AS corpusCases
               INNER JOIN dbo.FundingPlatform_ProjectFundingMatches AS matches
                   ON matches.Id = corpusCases.ProjectFundingMatchId
               WHERE corpusCases.EvaluationSetId = inserted.EvaluationSetId
                 AND corpusCases.Split = 1 AND matches.Classification <> 1)
           OR sets.DeclaredProjectCount <> setState.ActualProjectCount
           OR sets.DeclaredOpportunityCount <> setState.ActualOpportunityCount
           OR sets.DeclaredLabelCount <> setState.ActualLabelCount
           OR NOT EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationCases AS corpusCases
               WHERE corpusCases.EvaluationSetId = inserted.EvaluationSetId
                 AND corpusCases.Split = 0)
           OR NOT EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationCases AS corpusCases
               WHERE corpusCases.EvaluationSetId = inserted.EvaluationSetId
                 AND corpusCases.Split = 1)
           OR (SELECT COUNT(DISTINCT corpusCases.ProjectId)
               FROM dbo.FundingPlatform_SemanticEvaluationCases AS corpusCases
               WHERE corpusCases.EvaluationSetId = inserted.EvaluationSetId
                 AND corpusCases.Split = 1) < 10
           OR (SELECT COUNT_BIG(1)
               FROM dbo.FundingPlatform_SemanticEvaluationCases AS corpusCases
               WHERE corpusCases.EvaluationSetId = inserted.EvaluationSetId
                 AND corpusCases.Split = 1) < 100
           OR (SELECT COUNT_BIG(1)
               FROM dbo.FundingPlatform_SemanticEvaluationCases AS corpusCases
               INNER JOIN dbo.FundingPlatform_ProjectFundingMatches AS corpusMatches
                   ON corpusMatches.Id = corpusCases.ProjectFundingMatchId
               WHERE corpusCases.EvaluationSetId = inserted.EvaluationSetId
                 AND corpusCases.Split = 1 AND corpusCases.RelevanceLabel > 0
                 AND corpusMatches.Classification <> 1) < 10
           OR EXISTS
              (SELECT corpusCases.ProjectId
               FROM dbo.FundingPlatform_SemanticEvaluationCases AS corpusCases
               WHERE corpusCases.EvaluationSetId = inserted.EvaluationSetId
               GROUP BY corpusCases.ProjectId HAVING MIN(corpusCases.Split) <> MAX(corpusCases.Split))
           OR EXISTS
              (SELECT corpusCases.ProjectMatchingRunId
               FROM dbo.FundingPlatform_SemanticEvaluationCases AS corpusCases
               INNER JOIN dbo.FundingPlatform_ProjectFundingMatches AS matches
                   ON matches.Id = corpusCases.ProjectFundingMatchId
               WHERE corpusCases.EvaluationSetId = inserted.EvaluationSetId
                 AND corpusCases.Split = 1
               GROUP BY corpusCases.ProjectMatchingRunId
               HAVING SUM(CASE WHEN corpusCases.RelevanceLabel > 0
                                    AND matches.Classification <> 1 THEN 1 ELSE 0 END) = 0))
        THROW 54103, N'Evaluation run must snapshot an exact reviewed corpus and semantic configuration.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticEvaluationRunRequests_Immutable
ON dbo.FundingPlatform_SemanticEvaluationRunRequests
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted)
        THROW 54102, N'Semantic evaluation idempotency history is immutable.', 1;
END;
GO

/* Identity fields never change. Terminal jobs/runs cannot change at all. Lifecycle
   writes remain possible only through the guarded stored procedures below. */
CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticEmbeddingJobs_SubjectGuard
ON dbo.FundingPlatform_SemanticEmbeddingJobs
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS
       (SELECT 1
        FROM inserted
        LEFT JOIN dbo.FundingPlatform_SemanticConfigurations AS configurations
            ON configurations.Id = inserted.SemanticConfigurationId
           AND configurations.Version = inserted.SemanticConfigurationVersion
        OUTER APPLY dbo.FundingPlatform_ifn_SemanticConfigurationState
            (inserted.SemanticConfigurationId) AS configState
        LEFT JOIN dbo.FundingPlatform_ProjectVersions AS projectVersions
            ON inserted.SubjectType = 0
           AND projectVersions.ProjectId = inserted.ProjectId
           AND projectVersions.ProjectVersion = inserted.ProjectVersion
        LEFT JOIN dbo.FundingPlatform_FundingOpportunityVersions AS opportunityVersions
            ON inserted.SubjectType = 1
           AND opportunityVersions.FundingOpportunityId = inserted.FundingOpportunityId
           AND opportunityVersions.ContentVersion = inserted.FundingContentVersion
        OUTER APPLY
           (SELECT CASE inserted.SubjectType
                WHEN 0 THEN dbo.FundingPlatform_fn_ProjectSemanticCanonicalInput
                    (projectVersions.SnapshotJson)
                ELSE dbo.FundingPlatform_fn_OpportunitySemanticCanonicalInput
                    (opportunityVersions.SnapshotJson) END AS CanonicalInput) AS canonical
        OUTER APPLY
           (SELECT dbo.FundingPlatform_fn_SemanticInputHash(canonical.CanonicalInput)
                AS CanonicalHash) AS calculated
        OUTER APPLY
           (SELECT COALESCE(calculated.CanonicalHash,
                CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
                (N'invalid-semantic-input-v1|', inserted.SubjectType, N'|',
                 CASE inserted.SubjectType WHEN 0 THEN inserted.ProjectId
                                           ELSE inserted.FundingOpportunityId END,
                 N'|', CONVERT(VARCHAR(64), inserted.SubjectContentHash, 2), N'|',
                 CONVERT(VARCHAR(64), configurations.ConfigurationFingerprint, 2))))))
                AS EffectiveInputHash,
              dbo.FundingPlatform_fn_SemanticInputRiskCode
                 (canonical.CanonicalInput, configurations.MaximumInputUtf8Bytes) AS RiskCode)
             AS expectedInput
        OUTER APPLY
           (SELECT CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
            (N'semantic-embedding-v1|', inserted.SubjectType, N'|',
             COALESCE(CONVERT(NVARCHAR(30), inserted.OrganizationId), N'global'), N'|',
             COALESCE(CONVERT(NVARCHAR(30), inserted.ProjectId), N'-'), N'|',
             COALESCE(CONVERT(NVARCHAR(20), inserted.ProjectVersion), N'-'), N'|',
             COALESCE(CONVERT(NVARCHAR(30), inserted.FundingOpportunityId), N'-'), N'|',
             COALESCE(CONVERT(NVARCHAR(20), inserted.FundingContentVersion), N'-'), N'|',
             CONVERT(VARCHAR(64), inserted.SubjectContentHash, 2), N'|',
             CONVERT(VARCHAR(64), expectedInput.EffectiveInputHash, 2), N'|',
             configurations.ProviderCode, N'|', configurations.ModelCode, N'|',
             configurations.Dimensions, N'|', configurations.PurposeCode, N'|',
             CASE inserted.SubjectType WHEN 0 THEN configurations.ProjectTemplateVersion
                                       ELSE configurations.OpportunityTemplateVersion END,
             N'|', configurations.NormalizationVersion, N'|', configurations.Version, N'|',
             CONVERT(VARCHAR(64), configurations.ConfigurationFingerprint, 2))))) AS ContentAddress)
             AS expectedAddress
        WHERE configurations.Id IS NULL OR configurations.IsActive <> 1 OR configState.Id IS NULL
           OR configurations.ConfigurationFingerprint <> configState.CalculatedFingerprint
           OR inserted.MaximumAttempts <> configurations.MaximumAttempts
           OR (inserted.SubjectType = 0 AND
              (projectVersions.ProjectId IS NULL
               OR projectVersions.ContentHash <> inserted.SubjectContentHash))
           OR (inserted.SubjectType = 1 AND
              (opportunityVersions.FundingOpportunityId IS NULL
               OR opportunityVersions.ContentHash <> inserted.SubjectContentHash))
           OR expectedInput.EffectiveInputHash IS NULL OR expectedAddress.ContentAddress IS NULL
           OR inserted.InputContentHash <> expectedInput.EffectiveInputHash
           OR inserted.ContentAddress <> expectedAddress.ContentAddress
           OR (expectedInput.RiskCode IS NULL AND
              (inserted.Status <> 0 OR inserted.ErrorCode IS NOT NULL))
           OR (expectedInput.RiskCode IS NOT NULL AND
              (inserted.Status <> 4 OR inserted.ErrorCode <> expectedInput.RiskCode)))
        THROW 54103, N'Embedding job must bind exact subject snapshot, canonical hash and frozen configuration.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticEmbeddingJobs_Lifecycle
ON dbo.FundingPlatform_SemanticEmbeddingJobs
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted WHERE NOT EXISTS
               (SELECT 1 FROM inserted WHERE inserted.Id = deleted.Id))
       OR EXISTS
          (SELECT 1 FROM inserted INNER JOIN deleted ON deleted.Id = inserted.Id
           WHERE deleted.Status IN (2, 4, 5)
              OR inserted.PublicId <> deleted.PublicId
              OR inserted.SemanticConfigurationId <> deleted.SemanticConfigurationId
              OR inserted.SemanticConfigurationVersion <> deleted.SemanticConfigurationVersion
              OR inserted.SubjectType <> deleted.SubjectType
              OR ISNULL(inserted.OrganizationId, -1) <> ISNULL(deleted.OrganizationId, -1)
              OR ISNULL(inserted.ProjectId, -1) <> ISNULL(deleted.ProjectId, -1)
              OR ISNULL(inserted.ProjectVersion, -1) <> ISNULL(deleted.ProjectVersion, -1)
              OR ISNULL(inserted.FundingOpportunityId, -1) <> ISNULL(deleted.FundingOpportunityId, -1)
              OR ISNULL(inserted.FundingContentVersion, -1) <> ISNULL(deleted.FundingContentVersion, -1)
              OR inserted.SubjectContentHash <> deleted.SubjectContentHash
              OR inserted.InputContentHash <> deleted.InputContentHash
              OR inserted.ContentAddress <> deleted.ContentAddress
              OR inserted.JobGeneration <> deleted.JobGeneration
              OR inserted.AllowHistorical <> deleted.AllowHistorical
              OR inserted.MaximumAttempts <> deleted.MaximumAttempts
              OR inserted.CreatedAtUtc <> deleted.CreatedAtUtc)
        THROW 54102, N'Semantic embedding job identity and terminal state are immutable.', 1;
    IF EXISTS
       (SELECT 1
        FROM inserted
        WHERE inserted.Status = 2
          AND NOT EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddings AS embeddings
               WHERE embeddings.SourceJobId = inserted.Id))
        THROW 54103, N'Succeeded semantic embedding job must own exactly one immutable vector.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticEvaluationRuns_Lifecycle
ON dbo.FundingPlatform_SemanticEvaluationRuns
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted WHERE NOT EXISTS
               (SELECT 1 FROM inserted WHERE inserted.Id = deleted.Id))
       OR EXISTS
          (SELECT 1 FROM inserted INNER JOIN deleted ON deleted.Id = inserted.Id
           WHERE deleted.Status IN (2, 4)
              OR inserted.PublicId <> deleted.PublicId
              OR inserted.SemanticConfigurationId <> deleted.SemanticConfigurationId
              OR inserted.SemanticConfigurationVersion <> deleted.SemanticConfigurationVersion
              OR inserted.EvaluationSetId <> deleted.EvaluationSetId
              OR inserted.EvaluationSetVersion <> deleted.EvaluationSetVersion
              OR inserted.SemanticConfigurationFingerprint <> deleted.SemanticConfigurationFingerprint
              OR inserted.EvaluationSetManifestHash <> deleted.EvaluationSetManifestHash
              OR inserted.ProjectCount <> deleted.ProjectCount
              OR inserted.OpportunityCount <> deleted.OpportunityCount
              OR inserted.PairCount <> deleted.PairCount
              OR inserted.PrimaryCohortCount <> deleted.PrimaryCohortCount
              OR inserted.RequestedByUserId <> deleted.RequestedByUserId
              OR inserted.CreatedAtUtc <> deleted.CreatedAtUtc)
        THROW 54102, N'Shadow semantic evaluation identity and terminal state are immutable.', 1;
END;
GO


CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SemanticEmbeddingJob_Claim
    @WorkerInstanceId NVARCHAR(128),
    @BatchSize INT,
    @LeaseSeconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @WorkerInstanceId IS NULL OR LEN(@WorkerInstanceId) NOT BETWEEN 1 AND 128
       OR @WorkerInstanceId LIKE N'%[^A-Za-z0-9._-]%' COLLATE Latin1_General_100_BIN2
       OR @BatchSize NOT BETWEEN 1 AND 64 OR @LeaseSeconds NOT BETWEEN 60 AND 1800
       OR @NowUtc IS NULL
        THROW 54108, N'Bounded semantic worker claim parameters are required.', 1;

    DECLARE @WorkerHash BINARY(32) = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @WorkerInstanceId));
    DECLARE @ConfigurationId INT, @ConfigurationVersion INT, @MaximumBatchSize TINYINT;
    DECLARE @MaximumCost DECIMAL(19,6), @MonthlyBudget DECIMAL(19,6);
    DECLARE @BudgetMonth DATE = DATEFROMPARTS(YEAR(@NowUtc), MONTH(@NowUtc), 1);
    DECLARE @LeaseUntilUtc DATETIME2(3) = DATEADD(SECOND, @LeaseSeconds, @NowUtc);
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @LockResult INT;

    SELECT @ConfigurationId = configurations.Id,
           @ConfigurationVersion = configurations.Version,
           @MaximumBatchSize = configurations.MaximumBatchSize,
           @MaximumCost = configurations.MaximumCostUsdPerEmbedding,
           @MonthlyBudget = configurations.MonthlyBudgetUsd
    FROM dbo.FundingPlatform_SemanticConfigurations AS configurations
    CROSS APPLY dbo.FundingPlatform_ifn_SemanticConfigurationState(configurations.Id) AS state
    WHERE configurations.IsActive = 1
      AND configurations.ConfigurationFingerprint = state.CalculatedFingerprint;
    IF @ConfigurationId IS NULL RETURN;
    IF @BatchSize > @MaximumBatchSize SET @BatchSize = @MaximumBatchSize;

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_SemanticClaim;
    BEGIN TRY
        EXEC @LockResult = sys.sp_getapplock
            @Resource = N'FundingPlatform:SemanticBudget', @LockMode = N'Exclusive',
            @LockOwner = N'Transaction', @LockTimeout = 10000;
        IF @LockResult < 0 THROW 54109, N'Semantic budget lock could not be acquired.', 1;

        DECLARE @ExpiredReservations TABLE
        (
            ReservationId BIGINT NOT NULL PRIMARY KEY, EmbeddingJobId BIGINT NOT NULL,
            SemanticConfigurationId INT NOT NULL, OrganizationId BIGINT NULL,
            BudgetMonth DATE NOT NULL, ReservedCostUsd DECIMAL(19,6) NOT NULL
        );
        INSERT INTO @ExpiredReservations
        SELECT reservations.Id, reservations.EmbeddingJobId,
               reservations.SemanticConfigurationId, jobs.OrganizationId,
               reservations.BudgetMonth, reservations.ReservedCostUsd
        FROM dbo.FundingPlatform_SemanticBudgetReservations AS reservations
             WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
            ON jobs.Id = reservations.EmbeddingJobId
        WHERE reservations.Status = 0 AND reservations.ExpiresAtUtc <= @NowUtc;
        UPDATE reservations
        SET Status = 1, ConsumedCostUsd = reservations.ReservedCostUsd,
            FinalizedAtUtc = @NowUtc
        FROM dbo.FundingPlatform_SemanticBudgetReservations AS reservations
        INNER JOIN @ExpiredReservations AS expired ON expired.ReservationId = reservations.Id;
        INSERT INTO dbo.FundingPlatform_SemanticUsageLedger
            (EmbeddingJobId, BudgetReservationId, SemanticConfigurationId, OrganizationId,
             BudgetMonth, InputTokens, OutputTokens, EstimatedCostUsd,
             LatencyMilliseconds, OutcomeCode, IsEstimatedUncertain, RecordedAtUtc)
        SELECT expired.EmbeddingJobId, expired.ReservationId,
               expired.SemanticConfigurationId, expired.OrganizationId,
               expired.BudgetMonth, NULL, NULL, expired.ReservedCostUsd,
               0, N'charge-uncertain', 1, @NowUtc
        FROM @ExpiredReservations AS expired;

        UPDATE jobs
        SET Status = CASE WHEN jobs.AttemptCount >= jobs.MaximumAttempts THEN 4 ELSE 3 END,
            NextAttemptAtUtc = @NowUtc, LeaseId = NULL, LeaseOwnerHash = NULL,
            LeaseUntilUtc = NULL, ErrorCode = N'lease-expired',
            CompletedAtUtc = CASE WHEN jobs.AttemptCount >= jobs.MaximumAttempts
                                  THEN @NowUtc END,
            UpdatedAtUtc = @NowUtc
        FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
        WHERE jobs.SemanticConfigurationId = @ConfigurationId AND jobs.Status = 1
          AND jobs.LeaseUntilUtc <= @NowUtc;

        /* Current backfill work is skipped before provider access after a version
           moves on. Historical jobs created for a frozen corpus remain valid. */
        UPDATE jobs
        SET Status = 5, ErrorCode = N'stale-subject', CompletedAtUtc = @NowUtc,
            UpdatedAtUtc = @NowUtc
        FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
        WHERE jobs.SemanticConfigurationId = @ConfigurationId
          AND jobs.Status IN (0, 3) AND jobs.AllowHistorical = 0
          AND NOT EXISTS
              (SELECT 1
               FROM dbo.FundingPlatform_SemanticEvaluationRuns AS evaluationRuns
               INNER JOIN dbo.FundingPlatform_SemanticEvaluationRunCases AS cases
                   ON cases.SemanticEvaluationRunId = evaluationRuns.Id
               WHERE evaluationRuns.SemanticConfigurationId = jobs.SemanticConfigurationId
                 AND evaluationRuns.Status IN (0, 1, 3)
                 AND ((jobs.SubjectType = 0
                       AND cases.OrganizationId = jobs.OrganizationId
                       AND cases.ProjectId = jobs.ProjectId
                       AND cases.ProjectVersion = jobs.ProjectVersion
                       AND cases.ProjectContentHash = jobs.SubjectContentHash
                       AND cases.ProjectInputContentHash = jobs.InputContentHash
                       AND cases.ProjectContentAddress = jobs.ContentAddress)
                      OR (jobs.SubjectType = 1
                          AND cases.FundingOpportunityId = jobs.FundingOpportunityId
                          AND cases.FundingContentVersion = jobs.FundingContentVersion
                          AND cases.OpportunityContentHash = jobs.SubjectContentHash
                          AND cases.OpportunityInputContentHash = jobs.InputContentHash
                          AND cases.OpportunityContentAddress = jobs.ContentAddress)))
          AND ((jobs.SubjectType = 0 AND NOT EXISTS
               (SELECT 1 FROM dbo.FundingPlatform_Projects AS projects
                WHERE projects.Id = jobs.ProjectId
                  AND projects.OrganizationId = jobs.OrganizationId
                  AND projects.ProjectVersion = jobs.ProjectVersion
                  AND projects.IsActive = 1 AND projects.PublicationStatus <> 4))
            OR (jobs.SubjectType = 1 AND NOT EXISTS
               (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
                INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
                    ON ready.FundingOpportunityId = opportunities.Id
                WHERE opportunities.Id = jobs.FundingOpportunityId
                  AND opportunities.ContentVersion = jobs.FundingContentVersion)));

        DECLARE @CommittedCost DECIMAL(19,6) = COALESCE
        (
            (SELECT SUM(CASE reservations.Status WHEN 0 THEN reservations.ReservedCostUsd
                                                 WHEN 1 THEN reservations.ConsumedCostUsd END)
             FROM dbo.FundingPlatform_SemanticBudgetReservations AS reservations WITH (UPDLOCK, HOLDLOCK)
             WHERE reservations.SemanticConfigurationId = @ConfigurationId
               AND reservations.BudgetMonth = @BudgetMonth
               AND reservations.Status IN (0, 1)), 0
        );
        DECLARE @AvailableBudget DECIMAL(19,6) = @MonthlyBudget - @CommittedCost;
        /* Cap before division/cast: the configured 0.000001 minimum can make
           the unbounded quotient exceed INT even though a claim is <=64. */
        DECLARE @Capacity INT = CASE
            WHEN @MaximumCost = 0 THEN @BatchSize
            WHEN @AvailableBudget < @MaximumCost THEN 0
            WHEN @AvailableBudget >= @MaximumCost * @BatchSize THEN @BatchSize
            ELSE CONVERT(INT, FLOOR(@AvailableBudget / @MaximumCost)) END;

        DECLARE @Claims TABLE
        (
            JobId BIGINT NOT NULL PRIMARY KEY,
            JobPublicId UNIQUEIDENTIFIER NOT NULL,
            LeaseId UNIQUEIDENTIFIER NOT NULL,
            AttemptCount TINYINT NOT NULL
        );
        INSERT INTO @Claims (JobId, JobPublicId, LeaseId, AttemptCount)
        SELECT TOP (@Capacity) jobs.Id, jobs.PublicId, NEWID(), jobs.AttemptCount + 1
        FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
             WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
        WHERE jobs.SemanticConfigurationId = @ConfigurationId
          AND jobs.Status IN (0, 3) AND jobs.NextAttemptAtUtc <= @NowUtc
          AND jobs.AttemptCount < jobs.MaximumAttempts
          AND
          (NOT EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationRuns AS activeRuns
               WHERE activeRuns.SemanticConfigurationId = @ConfigurationId
                 AND activeRuns.Status IN (0, 1, 3))
           OR EXISTS
              (SELECT 1
               FROM dbo.FundingPlatform_SemanticEvaluationRuns AS activeRuns
               INNER JOIN dbo.FundingPlatform_SemanticEvaluationRunCases AS cases
                   ON cases.SemanticEvaluationRunId = activeRuns.Id
               WHERE activeRuns.SemanticConfigurationId = @ConfigurationId
                 AND activeRuns.Status IN (0, 1, 3)
                 AND ((jobs.SubjectType = 0
                       AND cases.OrganizationId = jobs.OrganizationId
                       AND cases.ProjectId = jobs.ProjectId
                       AND cases.ProjectVersion = jobs.ProjectVersion
                       AND cases.ProjectContentHash = jobs.SubjectContentHash
                       AND cases.ProjectInputContentHash = jobs.InputContentHash
                       AND cases.ProjectContentAddress = jobs.ContentAddress)
                      OR (jobs.SubjectType = 1
                          AND cases.FundingOpportunityId = jobs.FundingOpportunityId
                          AND cases.FundingContentVersion = jobs.FundingContentVersion
                          AND cases.OpportunityContentHash = jobs.SubjectContentHash
                          AND cases.OpportunityInputContentHash = jobs.InputContentHash
                          AND cases.OpportunityContentAddress = jobs.ContentAddress))))
        ORDER BY jobs.NextAttemptAtUtc, jobs.Id;

        UPDATE jobs
        SET Status = 1, AttemptCount = claims.AttemptCount,
            LeaseId = claims.LeaseId, LeaseOwnerHash = @WorkerHash,
            LeaseUntilUtc = @LeaseUntilUtc,
            StartedAtUtc = COALESCE(jobs.StartedAtUtc, @NowUtc),
            ErrorCode = NULL, UpdatedAtUtc = @NowUtc
        FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
        INNER JOIN @Claims AS claims ON claims.JobId = jobs.Id;

        DECLARE @Reservations TABLE
            (JobId BIGINT NOT NULL PRIMARY KEY, ReservationPublicId UNIQUEIDENTIFIER NOT NULL);
        INSERT INTO dbo.FundingPlatform_SemanticBudgetReservations
            (SemanticConfigurationId, EmbeddingJobId, BudgetMonth, ReservedCostUsd,
             Status, LeaseId, ExpiresAtUtc, CreatedAtUtc)
        OUTPUT inserted.EmbeddingJobId, inserted.PublicId
            INTO @Reservations (JobId, ReservationPublicId)
        SELECT @ConfigurationId, claims.JobId, @BudgetMonth, @MaximumCost,
               0, claims.LeaseId, @LeaseUntilUtc, @NowUtc
        FROM @Claims AS claims;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;

        SELECT claims.JobPublicId, claims.LeaseId,
               reservations.ReservationPublicId AS BudgetReservationPublicId,
               jobs.SubjectType,
               CASE jobs.SubjectType WHEN 0 THEN projects.PublicId ELSE opportunities.PublicId END
                    AS SubjectPublicId,
               CASE jobs.SubjectType WHEN 0 THEN jobs.ProjectVersion
                                     ELSE jobs.FundingContentVersion END AS SubjectVersion,
               CONCAT(configurations.Code, N'-v', configurations.Version)
                    AS SemanticConfigurationVersion,
               configurations.ConfigurationFingerprint AS SemanticConfigurationFingerprint,
               configurations.ProviderCode, configurations.ModelCode,
               configurations.Dimensions, configurations.PurposeCode,
               CASE jobs.SubjectType WHEN 0 THEN configurations.ProjectTemplateVersion
                                     ELSE configurations.OpportunityTemplateVersion END AS TemplateVersion,
               configurations.NormalizationVersion,
               configurations.MaximumInputUtf8Bytes,
               configurations.MaximumBatchSize,
               configurations.MaximumAttempts,
               configurations.MaximumCostUsdPerEmbedding,
               jobs.InputContentHash, claims.AttemptCount
        FROM @Claims AS claims
        INNER JOIN @Reservations AS reservations ON reservations.JobId = claims.JobId
        INNER JOIN dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs ON jobs.Id = claims.JobId
        INNER JOIN dbo.FundingPlatform_SemanticConfigurations AS configurations
            ON configurations.Id = jobs.SemanticConfigurationId
        LEFT JOIN dbo.FundingPlatform_Projects AS projects ON projects.Id = jobs.ProjectId
        LEFT JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
            ON opportunities.Id = jobs.FundingOpportunityId
        ORDER BY jobs.Id;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_SemanticClaim;
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
               @ConfigValid = CASE WHEN configurations.IsActive = 1
                                         AND configurations.ConfigurationFingerprint = state.CalculatedFingerprint
                                    THEN 1 ELSE 0 END
        FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_SemanticConfigurations AS configurations WITH (HOLDLOCK)
            ON configurations.Id = jobs.SemanticConfigurationId
           AND configurations.Version = jobs.SemanticConfigurationVersion
        CROSS APPLY dbo.FundingPlatform_ifn_SemanticConfigurationState(configurations.Id) AS state
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
               @CanonicalInputJson AS CanonicalText, @ExpectedHash AS InputContentHash;
    END TRY
    BEGIN CATCH
        IF @Started = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_SemanticGetInput;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SemanticEmbeddingJob_RenewLease
    @JobPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @LeaseSeconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @JobPublicId IS NULL OR @LeaseId IS NULL OR @LeaseSeconds NOT BETWEEN 60 AND 1800
       OR @NowUtc IS NULL THROW 54113, N'Valid semantic lease renewal is required.', 1;
    DECLARE @LeaseUntilUtc DATETIME2(3) = DATEADD(SECOND, @LeaseSeconds, @NowUtc);
    DECLARE @JobId BIGINT, @InitialTransactionCount INT = @@TRANCOUNT, @Started BIT = 0;
    IF @InitialTransactionCount = 0 BEGIN BEGIN TRANSACTION; SET @Started = 1; END
    ELSE SAVE TRANSACTION FP_SemanticRenew;
    BEGIN TRY
        SELECT @JobId = Id FROM dbo.FundingPlatform_SemanticEmbeddingJobs WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @JobPublicId AND Status = 1 AND LeaseId = @LeaseId
          AND LeaseUntilUtc > @NowUtc;
        IF @JobId IS NOT NULL
        BEGIN
            UPDATE dbo.FundingPlatform_SemanticEmbeddingJobs
            SET LeaseUntilUtc = @LeaseUntilUtc, UpdatedAtUtc = @NowUtc WHERE Id = @JobId;
            UPDATE dbo.FundingPlatform_SemanticBudgetReservations
            SET ExpiresAtUtc = @LeaseUntilUtc
            WHERE EmbeddingJobId = @JobId AND LeaseId = @LeaseId AND Status = 0
              AND ExpiresAtUtc > @NowUtc;
            IF @@ROWCOUNT <> 1 THROW 54114, N'Active budget reservation was not renewed.', 1;
        END;
        IF @Started = 1 COMMIT TRANSACTION;
        SELECT CONVERT(BIT, CASE WHEN @JobId IS NULL THEN 0 ELSE 1 END) AS Succeeded,
               CASE WHEN @JobId IS NULL THEN NULL ELSE @LeaseUntilUtc END AS LeaseUntilUtc;
    END TRY
    BEGIN CATCH
        IF @Started = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_SemanticRenew;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SemanticEmbeddingJob_Complete
    @JobPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @BudgetReservationPublicId UNIQUEIDENTIFIER,
    @ProviderCode NVARCHAR(50),
    @ModelCode NVARCHAR(128),
    @TemplateVersion NVARCHAR(50),
    @Embedding VECTOR(1536),
    @InputTokens INT = NULL,
    @OutputTokens INT = NULL,
    @EstimatedCostUsd DECIMAL(19,6),
    @ProviderRequestIdHash BINARY(32) = NULL,
    @LatencyMilliseconds INT,
    @CompletedAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @JobPublicId IS NULL OR @LeaseId IS NULL OR @BudgetReservationPublicId IS NULL
       OR @Embedding IS NULL OR @CompletedAtUtc IS NULL
       OR @ProviderCode IS NULL OR @ModelCode IS NULL OR @TemplateVersion IS NULL
       OR DATALENGTH(@ProviderCode) <> DATALENGTH(LTRIM(RTRIM(@ProviderCode)))
       OR DATALENGTH(@ModelCode) <> DATALENGTH(LTRIM(RTRIM(@ModelCode)))
       OR DATALENGTH(@TemplateVersion) <> DATALENGTH(LTRIM(RTRIM(@TemplateVersion)))
       OR (@InputTokens IS NOT NULL AND @InputTokens NOT BETWEEN 0 AND 8192)
       OR (@OutputTokens IS NOT NULL AND @OutputTokens NOT BETWEEN 0 AND 8192)
       OR @EstimatedCostUsd NOT BETWEEN 0 AND 1
       OR (@ProviderRequestIdHash IS NOT NULL AND DATALENGTH(@ProviderRequestIdHash) <> 32)
       OR @LatencyMilliseconds NOT BETWEEN 0 AND 30000
        THROW 54115, N'Bounded semantic completion metadata is invalid.', 1;
    DECLARE @SelfDistance FLOAT = VECTOR_DISTANCE('cosine', @Embedding, @Embedding);
    IF @SelfDistance IS NULL OR ABS(@SelfDistance) > 0.000001
        THROW 54116, N'Semantic embedding must be a finite non-zero 1536-dimensional vector.', 1;

    DECLARE @JobId BIGINT, @Status TINYINT, @ConfigurationId INT, @ConfigurationVersion INT;
    DECLARE @SubjectType TINYINT, @OrganizationId BIGINT, @ProjectId BIGINT, @ProjectVersion INT;
    DECLARE @OpportunityId BIGINT, @FundingContentVersion INT, @SubjectHash BINARY(32);
    DECLARE @InputHash BINARY(32), @ContentAddress BINARY(32), @MaximumCost DECIMAL(19,6);
    DECLARE @ConfigProvider NVARCHAR(50), @ConfigModel NVARCHAR(128), @Purpose NVARCHAR(32);
    DECLARE @Normalization NVARCHAR(50), @ExpectedTemplate NVARCHAR(50), @Fingerprint BINARY(32);
    DECLARE @ReservationId BIGINT, @ReservedCost DECIMAL(19,6), @BudgetMonth DATE;
    DECLARE @EmbeddingId BIGINT, @EmbeddingPublicId UNIQUEIDENTIFIER, @IsCurrent BIT;
    DECLARE @EmbeddingVersion INT, @EmbeddingHash BINARY(32);
    DECLARE @PresentedEmbeddingHash BINARY(32) = HASHBYTES('SHA2_256',
        CONVERT(VARBINARY(MAX), CONVERT(NVARCHAR(MAX), @Embedding)));
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @Started BIT = 0;
    IF @InitialTransactionCount = 0 BEGIN BEGIN TRANSACTION; SET @Started = 1; END
    ELSE SAVE TRANSACTION FP_SemanticComplete;
    BEGIN TRY
        SELECT @JobId = jobs.Id, @Status = jobs.Status,
               @ConfigurationId = jobs.SemanticConfigurationId,
               @ConfigurationVersion = jobs.SemanticConfigurationVersion,
               @SubjectType = jobs.SubjectType, @OrganizationId = jobs.OrganizationId,
               @ProjectId = jobs.ProjectId, @ProjectVersion = jobs.ProjectVersion,
               @OpportunityId = jobs.FundingOpportunityId,
               @FundingContentVersion = jobs.FundingContentVersion,
               @SubjectHash = jobs.SubjectContentHash, @InputHash = jobs.InputContentHash,
               @ContentAddress = jobs.ContentAddress,
               @ConfigProvider = configurations.ProviderCode,
               @ConfigModel = configurations.ModelCode, @Purpose = configurations.PurposeCode,
               @Normalization = configurations.NormalizationVersion,
               @ExpectedTemplate = CASE jobs.SubjectType
                   WHEN 0 THEN configurations.ProjectTemplateVersion
                   ELSE configurations.OpportunityTemplateVersion END,
               @Fingerprint = configurations.ConfigurationFingerprint,
               @MaximumCost = configurations.MaximumCostUsdPerEmbedding
        FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_SemanticConfigurations AS configurations WITH (HOLDLOCK)
            ON configurations.Id = jobs.SemanticConfigurationId
           AND configurations.Version = jobs.SemanticConfigurationVersion
        CROSS APPLY dbo.FundingPlatform_ifn_SemanticConfigurationState(configurations.Id) AS state
        WHERE jobs.PublicId = @JobPublicId
          AND configurations.ConfigurationFingerprint = state.CalculatedFingerprint;
        IF @JobId IS NULL THROW 54117, N'Semantic job or configuration was not found.', 1;

        IF @Status = 2
        BEGIN
            SELECT @EmbeddingPublicId = embeddings.PublicId
            FROM dbo.FundingPlatform_SemanticEmbeddings AS embeddings
            INNER JOIN dbo.FundingPlatform_SemanticBudgetReservations AS reservations
                ON reservations.EmbeddingJobId = embeddings.SourceJobId
               AND reservations.PublicId = @BudgetReservationPublicId
               AND reservations.LeaseId = @LeaseId AND reservations.Status = 1
               AND reservations.ConsumedCostUsd = @EstimatedCostUsd
            INNER JOIN dbo.FundingPlatform_SemanticUsageLedger AS ledger
                ON ledger.BudgetReservationId = reservations.Id
               AND ledger.EmbeddingJobId = embeddings.SourceJobId
               AND ledger.OutcomeCode = N'succeeded' AND ledger.IsEstimatedUncertain = 0
               AND ledger.EstimatedCostUsd = @EstimatedCostUsd
               AND ledger.LatencyMilliseconds = @LatencyMilliseconds
               AND ((ledger.InputTokens = @InputTokens)
                    OR (ledger.InputTokens IS NULL AND @InputTokens IS NULL))
               AND ((ledger.OutputTokens = @OutputTokens)
                    OR (ledger.OutputTokens IS NULL AND @OutputTokens IS NULL))
            WHERE embeddings.SourceJobId = @JobId
              AND embeddings.ProviderCode COLLATE Latin1_General_100_BIN2 =
                  @ProviderCode COLLATE Latin1_General_100_BIN2
              AND DATALENGTH(embeddings.ProviderCode) = DATALENGTH(@ProviderCode)
              AND embeddings.EffectiveModelCode COLLATE Latin1_General_100_BIN2 =
                  @ModelCode COLLATE Latin1_General_100_BIN2
              AND DATALENGTH(embeddings.EffectiveModelCode) = DATALENGTH(@ModelCode)
              AND embeddings.TemplateVersion COLLATE Latin1_General_100_BIN2 =
                  @TemplateVersion COLLATE Latin1_General_100_BIN2
              AND DATALENGTH(embeddings.TemplateVersion) = DATALENGTH(@TemplateVersion)
              AND embeddings.EmbeddingHash = @PresentedEmbeddingHash
              AND ((embeddings.ProviderRequestIdHash = @ProviderRequestIdHash)
                   OR (embeddings.ProviderRequestIdHash IS NULL
                       AND @ProviderRequestIdHash IS NULL));
            IF @EmbeddingPublicId IS NULL
                THROW 54118, N'Completed semantic job replay payload conflicts with immutable output.', 1;
            IF @Started = 1 COMMIT TRANSACTION;
            SELECT @EmbeddingPublicId AS EmbeddingPublicId, CONVERT(BIT, 1) AS WasReplay;
            RETURN;
        END;
        IF @Status <> 1 OR NOT EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddingJobs
            WHERE Id = @JobId AND LeaseId = @LeaseId AND LeaseUntilUtc > @CompletedAtUtc)
            THROW 54119, N'Semantic completion lease is stale.', 1;
        IF @ProviderCode COLLATE Latin1_General_100_BIN2 <>
               @ConfigProvider COLLATE Latin1_General_100_BIN2
           OR DATALENGTH(@ProviderCode) <> DATALENGTH(@ConfigProvider)
           OR @ModelCode COLLATE Latin1_General_100_BIN2 <>
               @ConfigModel COLLATE Latin1_General_100_BIN2
           OR DATALENGTH(@ModelCode) <> DATALENGTH(@ConfigModel)
           OR @TemplateVersion COLLATE Latin1_General_100_BIN2 <>
               @ExpectedTemplate COLLATE Latin1_General_100_BIN2
           OR DATALENGTH(@TemplateVersion) <> DATALENGTH(@ExpectedTemplate)
           OR @EstimatedCostUsd > @MaximumCost
            THROW 54120, N'Semantic provider output does not match frozen configuration or cost bound.', 1;

        SELECT @ReservationId = Id, @ReservedCost = ReservedCostUsd, @BudgetMonth = BudgetMonth
        FROM dbo.FundingPlatform_SemanticBudgetReservations WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @BudgetReservationPublicId AND EmbeddingJobId = @JobId
          AND SemanticConfigurationId = @ConfigurationId AND LeaseId = @LeaseId
          AND Status = 0 AND ExpiresAtUtc > @CompletedAtUtc;
        IF @ReservationId IS NULL OR @EstimatedCostUsd > @ReservedCost
            THROW 54121, N'Active semantic budget reservation is required.', 1;

        DECLARE @SnapshotJson NVARCHAR(MAX), @StoredSubjectHash BINARY(32);
        IF @SubjectType = 0
            SELECT @SnapshotJson = versions.SnapshotJson, @StoredSubjectHash = versions.ContentHash,
                   @IsCurrent = CASE WHEN projects.ProjectVersion = @ProjectVersion
                                          AND projects.IsActive = 1
                                          AND projects.PublicationStatus <> 4 THEN 1 ELSE 0 END
            FROM dbo.FundingPlatform_ProjectVersions AS versions WITH (HOLDLOCK)
            INNER JOIN dbo.FundingPlatform_Projects AS projects WITH (HOLDLOCK)
                ON projects.Id = versions.ProjectId AND projects.OrganizationId = @OrganizationId
            WHERE versions.ProjectId = @ProjectId AND versions.ProjectVersion = @ProjectVersion;
        ELSE
            SELECT @SnapshotJson = versions.SnapshotJson, @StoredSubjectHash = versions.ContentHash,
                   @IsCurrent = CASE WHEN opportunities.ContentVersion = @FundingContentVersion
                                          AND ready.FundingOpportunityId IS NOT NULL
                                     THEN 1 ELSE 0 END
            FROM dbo.FundingPlatform_FundingOpportunityVersions AS versions WITH (HOLDLOCK)
            INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities WITH (HOLDLOCK)
                ON opportunities.Id = versions.FundingOpportunityId
            LEFT JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
                ON ready.FundingOpportunityId = opportunities.Id
            WHERE versions.FundingOpportunityId = @OpportunityId
              AND versions.ContentVersion = @FundingContentVersion;
        IF @StoredSubjectHash IS NULL OR @StoredSubjectHash <> @SubjectHash
            THROW 54122, N'Semantic subject version or content hash drifted.', 1;
        DECLARE @Canonical NVARCHAR(MAX) = CASE @SubjectType
            WHEN 0 THEN dbo.FundingPlatform_fn_ProjectSemanticCanonicalInput(@SnapshotJson)
            ELSE dbo.FundingPlatform_fn_OpportunitySemanticCanonicalInput(@SnapshotJson) END;
        IF dbo.FundingPlatform_fn_SemanticInputRiskCode(@Canonical, 8192) IS NOT NULL
           OR dbo.FundingPlatform_fn_SemanticInputHash(@Canonical) <> @InputHash
            THROW 54123, N'Semantic canonical input failed completion revalidation.', 1;

        SET @EmbeddingHash = @PresentedEmbeddingHash;
        SELECT @EmbeddingVersion = ISNULL(MAX(EmbeddingVersion), 0) + 1
        FROM dbo.FundingPlatform_SemanticEmbeddings WITH (UPDLOCK, HOLDLOCK)
        WHERE SemanticConfigurationId = @ConfigurationId
          AND ((@SubjectType = 0 AND ProjectId = @ProjectId)
               OR (@SubjectType = 1 AND FundingOpportunityId = @OpportunityId));

        IF @IsCurrent = 1
            UPDATE dbo.FundingPlatform_SemanticEmbeddings
            SET IsCurrent = 0, RetiredAtUtc = @CompletedAtUtc
            WHERE SemanticConfigurationId = @ConfigurationId AND IsCurrent = 1
              AND ((@SubjectType = 0 AND ProjectId = @ProjectId)
                   OR (@SubjectType = 1 AND FundingOpportunityId = @OpportunityId));

        DECLARE @InsertedEmbedding TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER);
        INSERT INTO dbo.FundingPlatform_SemanticEmbeddings
            (SourceJobId, SemanticConfigurationId, SemanticConfigurationVersion,
             SubjectType, OrganizationId, ProjectId, ProjectVersion,
             FundingOpportunityId, FundingContentVersion, SubjectContentHash,
             InputContentHash, ContentAddress, EmbeddingVersion, ProviderCode,
             EffectiveModelCode, Dimensions, PurposeCode, TemplateVersion,
             NormalizationVersion, Embedding, EmbeddingHash, ProviderRequestIdHash,
             IsCurrent, CreatedAtUtc, RetiredAtUtc)
        OUTPUT inserted.Id, inserted.PublicId INTO @InsertedEmbedding
        VALUES
            (@JobId, @ConfigurationId, @ConfigurationVersion, @SubjectType,
             @OrganizationId, @ProjectId, @ProjectVersion, @OpportunityId,
             @FundingContentVersion, @SubjectHash, @InputHash, @ContentAddress,
             @EmbeddingVersion, @ConfigProvider, @ConfigModel, 1536, @Purpose,
             @ExpectedTemplate, @Normalization, @Embedding, @EmbeddingHash,
             @ProviderRequestIdHash, @IsCurrent, @CompletedAtUtc,
             CASE WHEN @IsCurrent = 1 THEN NULL ELSE @CompletedAtUtc END);
        SELECT @EmbeddingId = Id, @EmbeddingPublicId = PublicId FROM @InsertedEmbedding;

        UPDATE dbo.FundingPlatform_SemanticBudgetReservations
        SET Status = 1, ConsumedCostUsd = @EstimatedCostUsd, FinalizedAtUtc = @CompletedAtUtc
        WHERE Id = @ReservationId;
        INSERT INTO dbo.FundingPlatform_SemanticUsageLedger
            (EmbeddingJobId, BudgetReservationId, SemanticConfigurationId, OrganizationId,
             BudgetMonth, InputTokens, OutputTokens, EstimatedCostUsd,
             LatencyMilliseconds, OutcomeCode, IsEstimatedUncertain, RecordedAtUtc)
        VALUES
            (@JobId, @ReservationId, @ConfigurationId, @OrganizationId, @BudgetMonth,
             @InputTokens, @OutputTokens, @EstimatedCostUsd, @LatencyMilliseconds,
             N'succeeded', 0, @CompletedAtUtc);
        UPDATE dbo.FundingPlatform_SemanticEmbeddingJobs
        SET Status = 2, LeaseId = NULL, LeaseOwnerHash = NULL, LeaseUntilUtc = NULL,
            ErrorCode = NULL, CompletedAtUtc = @CompletedAtUtc, UpdatedAtUtc = @CompletedAtUtc
        WHERE Id = @JobId;
        IF @Started = 1 COMMIT TRANSACTION;
        SELECT @EmbeddingPublicId AS EmbeddingPublicId, CONVERT(BIT, 0) AS WasReplay;
    END TRY
    BEGIN CATCH
        IF @Started = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_SemanticComplete;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SemanticEmbeddingJob_Fail
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
          (N'embedding-provider-timeout', N'embedding-provider-throttled',
           N'embedding-provider-unavailable', N'embedding-provider-invalid-response',
           N'semantic-job-invalid', N'semantic-input-invalid',
           N'semantic-input-hash-mismatch', N'semantic-input-privacy-rejected',
           N'internal-error')
       OR @Retryable IS NULL OR @ProviderCallMayHaveBeenCharged IS NULL
        THROW 54124, N'Sanitized semantic failure metadata is required.', 1;
    DECLARE @JobId BIGINT, @ConfigurationId INT, @OrganizationId BIGINT;
    DECLARE @AttemptCount TINYINT, @MaximumAttempts TINYINT, @ReservationId BIGINT;
    DECLARE @ReservedCost DECIMAL(19,6), @BudgetMonth DATE;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @Started BIT = 0;
    IF @InitialTransactionCount = 0 BEGIN BEGIN TRANSACTION; SET @Started = 1; END
    ELSE SAVE TRANSACTION FP_SemanticFail;
    BEGIN TRY
        SELECT @JobId = Id, @ConfigurationId = SemanticConfigurationId,
               @OrganizationId = OrganizationId, @AttemptCount = AttemptCount,
               @MaximumAttempts = MaximumAttempts
        FROM dbo.FundingPlatform_SemanticEmbeddingJobs WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @JobPublicId AND Status = 1 AND LeaseId = @LeaseId
          AND LeaseUntilUtc > @FailedAtUtc;
        IF @JobId IS NULL THROW 54119, N'Semantic failure lease is stale.', 1;
        SELECT @ReservationId = Id, @ReservedCost = ReservedCostUsd, @BudgetMonth = BudgetMonth
        FROM dbo.FundingPlatform_SemanticBudgetReservations WITH (UPDLOCK, HOLDLOCK)
        WHERE EmbeddingJobId = @JobId AND LeaseId = @LeaseId AND Status = 0
          AND ExpiresAtUtc > @FailedAtUtc;
        IF @ReservationId IS NULL THROW 54121, N'Active semantic budget reservation is required.', 1;

        IF @ProviderCallMayHaveBeenCharged = 1
        BEGIN
            UPDATE dbo.FundingPlatform_SemanticBudgetReservations
            SET Status = 1, ConsumedCostUsd = ReservedCostUsd, FinalizedAtUtc = @FailedAtUtc
            WHERE Id = @ReservationId;
            INSERT INTO dbo.FundingPlatform_SemanticUsageLedger
                (EmbeddingJobId, BudgetReservationId, SemanticConfigurationId, OrganizationId,
                 BudgetMonth, InputTokens, OutputTokens, EstimatedCostUsd,
                 LatencyMilliseconds, OutcomeCode, IsEstimatedUncertain, RecordedAtUtc)
            VALUES (@JobId, @ReservationId, @ConfigurationId, @OrganizationId,
                    @BudgetMonth, NULL, NULL, @ReservedCost, 0,
                    N'charge-uncertain', 1, @FailedAtUtc);
        END
        ELSE
            UPDATE dbo.FundingPlatform_SemanticBudgetReservations
            SET Status = 2, FinalizedAtUtc = @FailedAtUtc WHERE Id = @ReservationId;

        DECLARE @WillRetry BIT = CASE WHEN @Retryable = 1 AND @AttemptCount < @MaximumAttempts
                                     THEN 1 ELSE 0 END;
        UPDATE dbo.FundingPlatform_SemanticEmbeddingJobs
        SET Status = CASE WHEN @WillRetry = 1 THEN 3 ELSE 4 END,
            NextAttemptAtUtc = CASE WHEN @WillRetry = 1
                THEN DATEADD(SECOND, 30 * POWER(CONVERT(INT, 2), @AttemptCount - 1), @FailedAtUtc)
                ELSE NextAttemptAtUtc END,
            LeaseId = NULL, LeaseOwnerHash = NULL, LeaseUntilUtc = NULL,
            ErrorCode = @ErrorCode,
            CompletedAtUtc = CASE WHEN @WillRetry = 1 THEN NULL ELSE @FailedAtUtc END,
            UpdatedAtUtc = @FailedAtUtc
        WHERE Id = @JobId;
        IF @Started = 1 COMMIT TRANSACTION;
        SELECT CONVERT(BIT, 1) AS Succeeded,
               CASE WHEN @WillRetry = 1 THEN N'retry-scheduled' ELSE N'permanent-failed' END AS Code;
    END TRY
    BEGIN CATCH
        IF @Started = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_SemanticFail;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SemanticEvaluationRun_Claim
    @WorkerInstanceId NVARCHAR(128),
    @BatchSize INT,
    @LeaseSeconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @WorkerInstanceId IS NULL OR LEN(@WorkerInstanceId) NOT BETWEEN 1 AND 128
       OR @WorkerInstanceId LIKE N'%[^A-Za-z0-9._-]%' COLLATE Latin1_General_100_BIN2
       OR @BatchSize NOT BETWEEN 1 AND 64 OR @LeaseSeconds NOT BETWEEN 60 AND 1800
       OR @NowUtc IS NULL
        THROW 54130, N'Bounded semantic evaluation claim parameters are required.', 1;
    DECLARE @WorkerHash BINARY(32) = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @WorkerInstanceId));
    DECLARE @LeaseUntil DATETIME2(3) = DATEADD(SECOND, @LeaseSeconds, @NowUtc);
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @Started BIT = 0;
    IF @InitialTransactionCount = 0 BEGIN BEGIN TRANSACTION; SET @Started = 1; END
    ELSE SAVE TRANSACTION FP_SemanticEvalClaim;
    BEGIN TRY
        UPDATE runs
        SET Status = CASE WHEN runs.AttemptCount >= 3 THEN 4 ELSE 3 END,
            NextAttemptAtUtc = @NowUtc, LeaseId = NULL, LeaseOwnerHash = NULL,
            LeaseUntilUtc = NULL, ErrorCode = N'lease-expired',
            CompletedAtUtc = CASE WHEN runs.AttemptCount >= 3 THEN @NowUtc END,
            UpdatedAtUtc = @NowUtc
        FROM dbo.FundingPlatform_SemanticEvaluationRuns AS runs
        WHERE runs.Status = 1 AND runs.LeaseUntilUtc <= @NowUtc;

        UPDATE runs
        SET Status = 4, ErrorCode = N'semantic-configuration-invalid',
            CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc
        FROM dbo.FundingPlatform_SemanticEvaluationRuns AS runs
        LEFT JOIN dbo.FundingPlatform_SemanticConfigurations AS configurations
            ON configurations.Id = runs.SemanticConfigurationId
           AND configurations.Version = runs.SemanticConfigurationVersion
           AND configurations.IsActive = 1
        OUTER APPLY dbo.FundingPlatform_ifn_SemanticConfigurationState
            (runs.SemanticConfigurationId) AS state
        WHERE runs.Status IN (0, 3)
          AND (configurations.Id IS NULL
               OR configurations.ConfigurationFingerprint <> state.CalculatedFingerprint);

        DECLARE @Claims TABLE
            (RunId BIGINT NOT NULL PRIMARY KEY, RunPublicId UNIQUEIDENTIFIER NOT NULL,
             LeaseId UNIQUEIDENTIFIER NOT NULL, AttemptCount TINYINT NOT NULL);
        INSERT INTO @Claims
        SELECT TOP (@BatchSize) runs.Id, runs.PublicId, NEWID(), runs.AttemptCount + 1
        FROM dbo.FundingPlatform_SemanticEvaluationRuns AS runs
             WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
        WHERE runs.Status IN (0, 3) AND runs.NextAttemptAtUtc <= @NowUtc
          /* Readiness polling never consumes an evaluation attempt. A partial
             report is ready when every required embedding is success or terminal. */
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.FundingPlatform_SemanticEvaluationRunCases AS cases
              WHERE cases.SemanticEvaluationRunId = runs.Id
                AND
                (
                    (NOT EXISTS
                       (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddings AS embeddings
                        WHERE embeddings.SemanticConfigurationId = runs.SemanticConfigurationId
                          AND embeddings.SubjectType = 0
                          AND embeddings.OrganizationId = cases.OrganizationId
                          AND embeddings.ProjectId = cases.ProjectId
                          AND embeddings.ProjectVersion = cases.ProjectVersion
                          AND embeddings.SubjectContentHash = cases.ProjectContentHash
                          AND embeddings.InputContentHash = cases.ProjectInputContentHash
                          AND embeddings.ContentAddress = cases.ProjectContentAddress)
                     AND EXISTS
                       (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
                        WHERE jobs.SemanticConfigurationId = runs.SemanticConfigurationId
                          AND jobs.Status IN (0, 1, 3) AND jobs.SubjectType = 0
                          AND jobs.OrganizationId = cases.OrganizationId
                          AND jobs.ProjectId = cases.ProjectId
                          AND jobs.ProjectVersion = cases.ProjectVersion
                          AND jobs.SubjectContentHash = cases.ProjectContentHash
                          AND jobs.InputContentHash = cases.ProjectInputContentHash
                          AND jobs.ContentAddress = cases.ProjectContentAddress))
                    OR
                    (NOT EXISTS
                       (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddings AS embeddings
                        WHERE embeddings.SemanticConfigurationId = runs.SemanticConfigurationId
                          AND embeddings.SubjectType = 1
                          AND embeddings.FundingOpportunityId = cases.FundingOpportunityId
                          AND embeddings.FundingContentVersion = cases.FundingContentVersion
                          AND embeddings.SubjectContentHash = cases.OpportunityContentHash
                          AND embeddings.InputContentHash = cases.OpportunityInputContentHash
                          AND embeddings.ContentAddress = cases.OpportunityContentAddress)
                     AND EXISTS
                       (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
                        WHERE jobs.SemanticConfigurationId = runs.SemanticConfigurationId
                          AND jobs.Status IN (0, 1, 3) AND jobs.SubjectType = 1
                          AND jobs.FundingOpportunityId = cases.FundingOpportunityId
                          AND jobs.FundingContentVersion = cases.FundingContentVersion
                          AND jobs.SubjectContentHash = cases.OpportunityContentHash
                          AND jobs.InputContentHash = cases.OpportunityInputContentHash
                          AND jobs.ContentAddress = cases.OpportunityContentAddress))
                )
          )
        ORDER BY runs.NextAttemptAtUtc, runs.Id;

        UPDATE runs
        SET Status = 1, LeaseId = claims.LeaseId, LeaseOwnerHash = @WorkerHash,
            LeaseUntilUtc = @LeaseUntil, AttemptCount = claims.AttemptCount,
            StartedAtUtc = COALESCE(runs.StartedAtUtc, @NowUtc), ErrorCode = NULL,
            UpdatedAtUtc = @NowUtc
        FROM dbo.FundingPlatform_SemanticEvaluationRuns AS runs
        INNER JOIN @Claims AS claims ON claims.RunId = runs.Id;
        IF @Started = 1 COMMIT TRANSACTION;

        SELECT claims.RunPublicId, claims.LeaseId,
               CONCAT(configurations.Code, N'-v', configurations.Version)
                    AS SemanticConfigurationVersion,
               configurations.ConfigurationFingerprint AS SemanticConfigurationFingerprint,
               configurations.ProviderCode, configurations.ModelCode,
               configurations.PurposeCode, configurations.NormalizationVersion,
               configurations.ProjectTemplateVersion, configurations.OpportunityTemplateVersion,
               configurations.CalibrationVersion, configurations.DistanceMetric,
               configurations.MaximumAttempts, configurations.Dimensions,
               runs.PairCount, claims.AttemptCount
        FROM @Claims AS claims
        INNER JOIN dbo.FundingPlatform_SemanticEvaluationRuns AS runs ON runs.Id = claims.RunId
        INNER JOIN dbo.FundingPlatform_SemanticConfigurations AS configurations
            ON configurations.Id = runs.SemanticConfigurationId
        ORDER BY runs.Id;
    END TRY
    BEGIN CATCH
        IF @Started = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_SemanticEvalClaim;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SemanticEvaluationRun_RenewLease
    @RunPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @LeaseSeconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    IF @RunPublicId IS NULL OR @LeaseId IS NULL OR @LeaseSeconds NOT BETWEEN 60 AND 1800
       OR @NowUtc IS NULL THROW 54131, N'Valid semantic evaluation lease renewal is required.', 1;
    DECLARE @Until DATETIME2(3) = DATEADD(SECOND, @LeaseSeconds, @NowUtc);
    UPDATE dbo.FundingPlatform_SemanticEvaluationRuns
    SET LeaseUntilUtc = @Until, UpdatedAtUtc = @NowUtc
    WHERE PublicId = @RunPublicId AND Status = 1 AND LeaseId = @LeaseId
      AND LeaseUntilUtc > @NowUtc;
    SELECT CONVERT(BIT, CASE WHEN @@ROWCOUNT = 1 THEN 1 ELSE 0 END) AS Succeeded;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SemanticEvaluationRun_GetWork
    @RunPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @RunId BIGINT, @ConfigurationId INT, @PairCount INT;
    SELECT @RunId = Id, @ConfigurationId = SemanticConfigurationId, @PairCount = PairCount
    FROM dbo.FundingPlatform_SemanticEvaluationRuns
    WHERE PublicId = @RunPublicId AND Status = 1 AND LeaseId = @LeaseId
      AND LeaseUntilUtc > @NowUtc;
    IF @RunId IS NULL RETURN;
    ;WITH subjectJobs AS
    (
        SELECT DISTINCT jobs.Id, jobs.Status
        FROM dbo.FundingPlatform_SemanticEvaluationRunCases AS cases
        INNER JOIN dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
            ON jobs.SemanticConfigurationId = @ConfigurationId
           AND ((jobs.SubjectType = 0 AND jobs.OrganizationId = cases.OrganizationId
                AND jobs.ProjectId = cases.ProjectId AND jobs.ProjectVersion = cases.ProjectVersion
                 AND jobs.SubjectContentHash = cases.ProjectContentHash
                 AND jobs.InputContentHash = cases.ProjectInputContentHash
                 AND jobs.ContentAddress = cases.ProjectContentAddress)
                OR (jobs.SubjectType = 1 AND jobs.FundingOpportunityId = cases.FundingOpportunityId
                    AND jobs.FundingContentVersion = cases.FundingContentVersion
                    AND jobs.SubjectContentHash = cases.OpportunityContentHash
                    AND jobs.InputContentHash = cases.OpportunityInputContentHash
                    AND jobs.ContentAddress = cases.OpportunityContentAddress))
        WHERE cases.SemanticEvaluationRunId = @RunId
    ), ready AS
    (
        SELECT cases.CaseOrdinal
        FROM dbo.FundingPlatform_SemanticEvaluationRunCases AS cases
        WHERE cases.SemanticEvaluationRunId = @RunId
          AND EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddings AS embeddings
               WHERE embeddings.SemanticConfigurationId = @ConfigurationId
                 AND embeddings.SubjectType = 0
                 AND embeddings.OrganizationId = cases.OrganizationId
                 AND embeddings.ProjectId = cases.ProjectId
                 AND embeddings.ProjectVersion = cases.ProjectVersion
                 AND embeddings.SubjectContentHash = cases.ProjectContentHash
                 AND embeddings.InputContentHash = cases.ProjectInputContentHash
                 AND embeddings.ContentAddress = cases.ProjectContentAddress)
          AND EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddings AS embeddings
               WHERE embeddings.SemanticConfigurationId = @ConfigurationId
                 AND embeddings.SubjectType = 1
                 AND embeddings.FundingOpportunityId = cases.FundingOpportunityId
                 AND embeddings.FundingContentVersion = cases.FundingContentVersion
                 AND embeddings.SubjectContentHash = cases.OpportunityContentHash
                 AND embeddings.InputContentHash = cases.OpportunityInputContentHash
                 AND embeddings.ContentAddress = cases.OpportunityContentAddress)
    )
    SELECT @RunPublicId AS RunPublicId, @LeaseId AS LeaseId, @PairCount AS PairCount,
           (SELECT COUNT_BIG(1) FROM ready) AS ReadyPairCount,
           (SELECT COUNT_BIG(1) FROM subjectJobs WHERE Status IN (0, 1, 3))
                AS PendingEmbeddingJobCount,
           (SELECT COUNT_BIG(1) FROM subjectJobs WHERE Status IN (4, 5))
                AS PermanentFailedEmbeddingJobCount;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SemanticEvaluationRun_Complete
    @RunPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @CompletedAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @RunPublicId IS NULL OR @LeaseId IS NULL OR @CompletedAtUtc IS NULL
        THROW 54135, N'Exact semantic evaluation completion identity is required.', 1;

    DECLARE @RunId BIGINT, @ConfigurationId INT, @PairCount INT, @PrimaryCohortCount INT;
    DECLARE @IsLocalFake BIT, @RunStatus TINYINT, @ConfigValid BIT;
    DECLARE @RunCreatedAtUtc DATETIME2(3), @CompletionLeaseId UNIQUEIDENTIFIER;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @Started BIT = 0;
    IF @InitialTransactionCount = 0 BEGIN BEGIN TRANSACTION; SET @Started = 1; END
    ELSE SAVE TRANSACTION FP_SemanticEvalComplete;
    BEGIN TRY
        SELECT @RunId = runs.Id, @RunStatus = runs.Status,
               @ConfigurationId = runs.SemanticConfigurationId,
               @PairCount = runs.PairCount, @PrimaryCohortCount = runs.PrimaryCohortCount,
               @RunCreatedAtUtc = runs.CreatedAtUtc, @CompletionLeaseId = runs.CompletionLeaseId,
               @IsLocalFake = configurations.IsLocalFake,
               @ConfigValid = CASE WHEN configurations.IsActive = 1
                                         AND configurations.ConfigurationFingerprint =
                                             runs.SemanticConfigurationFingerprint
                                         AND configurations.ConfigurationFingerprint =
                                             state.CalculatedFingerprint
                                    THEN 1 ELSE 0 END
        FROM dbo.FundingPlatform_SemanticEvaluationRuns AS runs WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_SemanticConfigurations AS configurations WITH (HOLDLOCK)
            ON configurations.Id = runs.SemanticConfigurationId
           AND configurations.Version = runs.SemanticConfigurationVersion
        OUTER APPLY dbo.FundingPlatform_ifn_SemanticConfigurationState(configurations.Id) AS state
        WHERE runs.PublicId = @RunPublicId;
        IF @RunId IS NULL
            THROW 54136, N'Semantic evaluation run or frozen configuration was not found.', 1;
        IF @RunStatus = 2
        BEGIN
            IF @CompletionLeaseId <> @LeaseId
                THROW 54134, N'Semantic evaluation completion replay lease does not match.', 1;
            IF @Started = 1 COMMIT TRANSACTION;
            SELECT CONVERT(BIT, 1) AS Succeeded, CONVERT(BIT, 1) AS WasReplay,
                   N'completed' AS Code;
            RETURN;
        END;
        IF @ConfigValid <> 1
            THROW 54136, N'Semantic evaluation frozen configuration is inactive or drifted.', 1;
        IF @RunStatus <> 1 OR NOT EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_SemanticEvaluationRuns
            WHERE Id = @RunId AND LeaseId = @LeaseId AND LeaseUntilUtc > @CompletedAtUtc)
            THROW 54134, N'Semantic evaluation completion lease is stale.', 1;

        /* Readiness is evaluated per exact frozen content address. Missing terminal
           embeddings are reported as coverage/provider failures, never as engine failure. */
        IF EXISTS
           (SELECT 1
            FROM dbo.FundingPlatform_SemanticEvaluationRunCases AS cases
            WHERE cases.SemanticEvaluationRunId = @RunId
              AND
              (((NOT EXISTS
                    (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddings AS embeddings
                     WHERE embeddings.ContentAddress = cases.ProjectContentAddress))
                 AND EXISTS
                    (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
                     WHERE jobs.ContentAddress = cases.ProjectContentAddress
                       AND jobs.Status IN (0, 1, 3)))
                OR
               ((NOT EXISTS
                    (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddings AS embeddings
                     WHERE embeddings.ContentAddress = cases.OpportunityContentAddress))
                 AND EXISTS
                    (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
                     WHERE jobs.ContentAddress = cases.OpportunityContentAddress
                       AND jobs.Status IN (0, 1, 3)))))
            THROW 54137, N'Semantic evaluation embeddings are still pending.', 1;

        DECLARE @Ready TABLE
        (
            CaseOrdinal INT NOT NULL PRIMARY KEY,
            ProjectMatchingRunId BIGINT NOT NULL,
            ProjectFundingMatchId BIGINT NOT NULL,
            FundingOpportunityId BIGINT NOT NULL,
            Classification TINYINT NOT NULL,
            CompatibilityScore DECIMAL(5,2) NULL,
            DatasetSplit TINYINT NOT NULL,
            RelevanceLabel TINYINT NOT NULL,
            ProjectEmbeddingId BIGINT NOT NULL,
            OpportunityEmbeddingId BIGINT NOT NULL,
            CosineDistance DECIMAL(9,8) NOT NULL,
            CosineSimilarity DECIMAL(9,8) NOT NULL,
            SemanticScore DECIMAL(5,2) NOT NULL
        );
        INSERT INTO @Ready
        SELECT cases.CaseOrdinal, cases.ProjectMatchingRunId, cases.ProjectFundingMatchId,
               cases.FundingOpportunityId, matches.Classification, matches.CompatibilityScore,
               cases.DatasetSplit, cases.RelevanceLabel,
               projectEmbeddings.Id, opportunityEmbeddings.Id,
               normalized.CosineDistance,
               CONVERT(DECIMAL(9,8), 1 - normalized.CosineDistance),
               CONVERT(DECIMAL(5,2), (2 - normalized.CosineDistance) * 50)
        FROM dbo.FundingPlatform_SemanticEvaluationRunCases AS cases
        INNER JOIN dbo.FundingPlatform_ProjectFundingMatches AS matches
            ON matches.Id = cases.ProjectFundingMatchId
        INNER JOIN dbo.FundingPlatform_SemanticEmbeddings AS projectEmbeddings
            ON projectEmbeddings.ContentAddress = cases.ProjectContentAddress
           AND projectEmbeddings.SemanticConfigurationId = @ConfigurationId
           AND projectEmbeddings.SubjectType = 0
           AND projectEmbeddings.OrganizationId = cases.OrganizationId
           AND projectEmbeddings.ProjectId = cases.ProjectId
           AND projectEmbeddings.ProjectVersion = cases.ProjectVersion
           AND projectEmbeddings.InputContentHash = cases.ProjectInputContentHash
        INNER JOIN dbo.FundingPlatform_SemanticEmbeddings AS opportunityEmbeddings
            ON opportunityEmbeddings.ContentAddress = cases.OpportunityContentAddress
           AND opportunityEmbeddings.SemanticConfigurationId = @ConfigurationId
           AND opportunityEmbeddings.SubjectType = 1
           AND opportunityEmbeddings.FundingOpportunityId = cases.FundingOpportunityId
           AND opportunityEmbeddings.FundingContentVersion = cases.FundingContentVersion
           AND opportunityEmbeddings.InputContentHash = cases.OpportunityInputContentHash
        CROSS APPLY
           (SELECT VECTOR_DISTANCE('cosine', projectEmbeddings.Embedding,
                                            opportunityEmbeddings.Embedding) AS RawDistance) AS distance
        CROSS APPLY
           (SELECT CONVERT(DECIMAL(9,8), CASE WHEN distance.RawDistance < 0 THEN 0
                                              WHEN distance.RawDistance > 2 THEN 2
                                              ELSE distance.RawDistance END) AS CosineDistance) AS normalized
        WHERE cases.SemanticEvaluationRunId = @RunId
          AND distance.RawDistance IS NOT NULL;

        DECLARE @BaselineRanks TABLE (CaseOrdinal INT NOT NULL PRIMARY KEY, RankValue SMALLINT NOT NULL);
        ;WITH ranked AS
        (
            SELECT cases.CaseOrdinal,
                   ROW_NUMBER() OVER
                   (PARTITION BY cases.ProjectMatchingRunId
                    ORDER BY CASE matches.Classification WHEN 0 THEN 0 WHEN 2 THEN 1 ELSE 2 END,
                             CASE WHEN matches.CompatibilityScore IS NULL THEN 1 ELSE 0 END,
                             matches.CompatibilityScore DESC,
                             CASE WHEN matches.CloseDate IS NULL THEN 1 ELSE 0 END,
                             matches.CloseDate,
                             cases.FundingOpportunityId) AS RankValue
            FROM dbo.FundingPlatform_SemanticEvaluationRunCases AS cases
            INNER JOIN dbo.FundingPlatform_ProjectFundingMatches AS matches
                ON matches.Id = cases.ProjectFundingMatchId
            WHERE cases.SemanticEvaluationRunId = @RunId
              AND cases.DatasetSplit = 1 AND matches.Classification <> 1
        )
        INSERT INTO @BaselineRanks
        SELECT CaseOrdinal, CONVERT(SMALLINT, RankValue) FROM ranked;

        DECLARE @SemanticRanks TABLE (CaseOrdinal INT NOT NULL PRIMARY KEY, RankValue SMALLINT NOT NULL);
        ;WITH ranked AS
        (
            SELECT ready.CaseOrdinal,
                   ROW_NUMBER() OVER
                   (PARTITION BY ready.ProjectMatchingRunId
                    ORDER BY CASE ready.Classification WHEN 0 THEN 0 WHEN 2 THEN 1 ELSE 2 END,
                             ready.CosineDistance ASC, ready.FundingOpportunityId) AS RankValue
            FROM @Ready AS ready
            WHERE ready.DatasetSplit = 1 AND ready.Classification <> 1
        )
        INSERT INTO @SemanticRanks
        SELECT CaseOrdinal, CONVERT(SMALLINT, RankValue) FROM ranked;

        INSERT INTO dbo.FundingPlatform_SemanticEvaluationItems
            (SemanticEvaluationRunId, CaseOrdinal, ProjectFundingMatchId,
             ProjectEmbeddingId, OpportunityEmbeddingId, CosineDistance,
             CosineSimilarity, SemanticScore, SemanticRank, DeterministicRank,
             RelevanceLabel, DatasetSplit, IsPrimaryCohort, CreatedAtUtc)
        SELECT @RunId, ready.CaseOrdinal, ready.ProjectFundingMatchId,
               ready.ProjectEmbeddingId, ready.OpportunityEmbeddingId,
               ready.CosineDistance, ready.CosineSimilarity, ready.SemanticScore,
               semanticRanks.RankValue, baselineRanks.RankValue,
               ready.RelevanceLabel, ready.DatasetSplit,
               CONVERT(BIT, CASE WHEN ready.DatasetSplit = 1 AND ready.Classification <> 1
                                 THEN 1 ELSE 0 END), @CompletedAtUtc
        FROM @Ready AS ready
        LEFT JOIN @SemanticRanks AS semanticRanks ON semanticRanks.CaseOrdinal = ready.CaseOrdinal
        LEFT JOIN @BaselineRanks AS baselineRanks ON baselineRanks.CaseOrdinal = ready.CaseOrdinal;

        DECLARE @EvaluatedCount INT = (SELECT COUNT(1) FROM @Ready);
        DECLARE @Coverage DECIMAL(5,2) = CONVERT(DECIMAL(5,2),
            100.0 * @EvaluatedCount / NULLIF(@PairCount, 0));
        DECLARE @Addresses TABLE (ContentAddress BINARY(32) NOT NULL PRIMARY KEY);
        INSERT INTO @Addresses
        SELECT ProjectContentAddress FROM dbo.FundingPlatform_SemanticEvaluationRunCases
        WHERE SemanticEvaluationRunId = @RunId
        UNION
        SELECT OpportunityContentAddress FROM dbo.FundingPlatform_SemanticEvaluationRunCases
        WHERE SemanticEvaluationRunId = @RunId;
        DECLARE @Usage TABLE
        (
            UsageId BIGINT NOT NULL PRIMARY KEY, OutcomeCode NVARCHAR(32) NOT NULL,
            EstimatedCostUsd DECIMAL(19,6) NOT NULL, LatencyMilliseconds INT NOT NULL
        );
        INSERT INTO @Usage
        SELECT ledger.Id, ledger.OutcomeCode, ledger.EstimatedCostUsd, ledger.LatencyMilliseconds
        FROM dbo.FundingPlatform_SemanticUsageLedger AS ledger
        INNER JOIN dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
            ON jobs.Id = ledger.EmbeddingJobId
        INNER JOIN @Addresses AS addresses ON addresses.ContentAddress = jobs.ContentAddress
        WHERE ledger.RecordedAtUtc >= @RunCreatedAtUtc
          AND ledger.RecordedAtUtc <= @CompletedAtUtc;
        DECLARE @RequiredSubjectCount INT = (SELECT COUNT(1) FROM @Addresses);
        DECLARE @AvailableSubjectCount INT =
            (SELECT COUNT(1) FROM @Addresses AS addresses
             WHERE EXISTS
                (SELECT 1 FROM dbo.FundingPlatform_SemanticEmbeddings AS embeddings
                 WHERE embeddings.ContentAddress = addresses.ContentAddress));
        DECLARE @ProviderSuccess DECIMAL(5,2) = CONVERT(DECIMAL(5,2),
            100.0 * @AvailableSubjectCount / NULLIF(@RequiredSubjectCount, 0));
        DECLARE @TotalCost DECIMAL(19,6) = COALESCE
            ((SELECT SUM(EstimatedCostUsd) FROM @Usage), 0);
        DECLARE @P95Latency INT = 0;
        SELECT TOP (1) @P95Latency = CONVERT(INT, CEILING
            (PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY LatencyMilliseconds) OVER ()))
        FROM @Usage WHERE OutcomeCode = N'succeeded';

        DECLARE @ProjectMetrics TABLE
        (
            ProjectMatchingRunId BIGINT NOT NULL PRIMARY KEY,
            RecallAt10 FLOAT NOT NULL, SemanticNdcgAt10 FLOAT NOT NULL,
            BaselineNdcgAt10 FLOAT NOT NULL, MrrAt10 FLOAT NOT NULL,
            MeanRankDelta FLOAT NOT NULL
        );
        ;WITH cohort AS
        (
            SELECT cases.ProjectMatchingRunId, cases.CaseOrdinal,
                   cases.FundingOpportunityId, cases.RelevanceLabel,
                   baselineRanks.RankValue AS BaselineRank,
                   semanticRanks.RankValue AS SemanticRank,
                   ROW_NUMBER() OVER
                   (PARTITION BY cases.ProjectMatchingRunId
                    ORDER BY cases.RelevanceLabel DESC, cases.FundingOpportunityId) AS IdealRank
            FROM dbo.FundingPlatform_SemanticEvaluationRunCases AS cases
            INNER JOIN dbo.FundingPlatform_ProjectFundingMatches AS matches
                ON matches.Id = cases.ProjectFundingMatchId
            INNER JOIN @BaselineRanks AS baselineRanks ON baselineRanks.CaseOrdinal = cases.CaseOrdinal
            LEFT JOIN @SemanticRanks AS semanticRanks ON semanticRanks.CaseOrdinal = cases.CaseOrdinal
            WHERE cases.SemanticEvaluationRunId = @RunId
              AND cases.DatasetSplit = 1 AND matches.Classification <> 1
        ), aggregateMetrics AS
        (
            SELECT ProjectMatchingRunId,
                   CONVERT(FLOAT, SUM(CASE WHEN RelevanceLabel > 0 AND SemanticRank <= 10
                                          THEN 1 ELSE 0 END)) /
                       NULLIF(SUM(CASE WHEN RelevanceLabel > 0 THEN 1 ELSE 0 END), 0) AS RecallAt10,
                   SUM(CASE WHEN SemanticRank <= 10
                            THEN (POWER(CONVERT(FLOAT, 2), RelevanceLabel) - 1) /
                                 LOG(CONVERT(FLOAT, SemanticRank + 1), 2) ELSE 0 END) AS SemanticDcg,
                   SUM(CASE WHEN BaselineRank <= 10
                            THEN (POWER(CONVERT(FLOAT, 2), RelevanceLabel) - 1) /
                                 LOG(CONVERT(FLOAT, BaselineRank + 1), 2) ELSE 0 END) AS BaselineDcg,
                   SUM(CASE WHEN IdealRank <= 10
                            THEN (POWER(CONVERT(FLOAT, 2), RelevanceLabel) - 1) /
                                 LOG(CONVERT(FLOAT, IdealRank + 1), 2) ELSE 0 END) AS IdealDcg,
                   CASE WHEN MIN(CASE WHEN RelevanceLabel > 0 AND SemanticRank <= 10
                                      THEN SemanticRank END) IS NULL THEN 0
                        ELSE 1.0 / MIN(CASE WHEN RelevanceLabel > 0 AND SemanticRank <= 10
                                            THEN SemanticRank END) END AS MrrAt10,
                   AVG(CASE WHEN RelevanceLabel > 0
                            THEN CONVERT(FLOAT, BaselineRank - COALESCE(SemanticRank, 200)) END)
                       AS MeanRankDelta
            FROM cohort
            GROUP BY ProjectMatchingRunId
        )
        INSERT INTO @ProjectMetrics
        SELECT ProjectMatchingRunId, RecallAt10,
               CASE WHEN IdealDcg = 0 THEN 0 ELSE SemanticDcg / IdealDcg END,
               CASE WHEN IdealDcg = 0 THEN 0 ELSE BaselineDcg / IdealDcg END,
               MrrAt10, MeanRankDelta
        FROM aggregateMetrics;

        DECLARE @RecallAt10 DECIMAL(7,6), @NdcgAt10 DECIMAL(7,6);
        DECLARE @BaselineNdcgAt10 DECIMAL(7,6), @MrrAt10 DECIMAL(7,6);
        DECLARE @MeanRankDelta DECIMAL(9,4);
        SELECT @RecallAt10 = CONVERT(DECIMAL(7,6), COALESCE(AVG(RecallAt10), 0)),
               @NdcgAt10 = CONVERT(DECIMAL(7,6), COALESCE(AVG(SemanticNdcgAt10), 0)),
               @BaselineNdcgAt10 = CONVERT(DECIMAL(7,6), COALESCE(AVG(BaselineNdcgAt10), 0)),
               @MrrAt10 = CONVERT(DECIMAL(7,6), COALESCE(AVG(MrrAt10), 0)),
               @MeanRankDelta = CONVERT(DECIMAL(9,4), COALESCE(AVG(MeanRankDelta), 0))
        FROM @ProjectMetrics;
        DECLARE @NdcgDelta DECIMAL(8,6) = @NdcgAt10 - @BaselineNdcgAt10;

        DECLARE @HardFailPromotedCount INT;
        ;WITH allRanks AS
        (
            SELECT Classification,
                   ROW_NUMBER() OVER
                   (PARTITION BY ProjectMatchingRunId
                    ORDER BY CosineDistance ASC, FundingOpportunityId) AS RankValue
            FROM @Ready WHERE DatasetSplit = 1
        )
        SELECT @HardFailPromotedCount = COUNT(1)
        FROM allRanks WHERE Classification = 1 AND RankValue <= 10;
        DECLARE @PromotionEligible BIT = CONVERT(BIT, CASE
            WHEN @IsLocalFake = 0 AND @EvaluatedCount = @PairCount
             AND @Coverage >= 95 AND @ProviderSuccess >= 99
             AND @RecallAt10 >= 0.80 AND @NdcgAt10 >= 0.75 AND @NdcgDelta >= 0.05
             AND @HardFailPromotedCount = 0 THEN 1 ELSE 0 END);

        UPDATE dbo.FundingPlatform_SemanticEvaluationRuns
        SET Status = 2, EvaluatedCount = @EvaluatedCount, LabelledCount = @EvaluatedCount,
            CoveragePercentage = COALESCE(@Coverage, 0),
            SuccessPercentage = COALESCE(@ProviderSuccess, 0),
            RecallAt10 = COALESCE(@RecallAt10, 0), NdcgAt10 = COALESCE(@NdcgAt10, 0),
            BaselineNdcgAt10 = COALESCE(@BaselineNdcgAt10, 0),
            NdcgDelta = COALESCE(@NdcgDelta, 0), MrrAt10 = COALESCE(@MrrAt10, 0),
            MeanRankDelta = COALESCE(@MeanRankDelta, 0), TotalEstimatedCostUsd = @TotalCost,
            P95LatencyMilliseconds = COALESCE(@P95Latency, 0),
            HardFailPromotedCount = COALESCE(@HardFailPromotedCount, 0),
            IsPromotionEligible = @PromotionEligible,
            CompletionLeaseId = @LeaseId,
            LeaseId = NULL, LeaseOwnerHash = NULL, LeaseUntilUtc = NULL,
            ErrorCode = NULL, CompletedAtUtc = @CompletedAtUtc, UpdatedAtUtc = @CompletedAtUtc
        WHERE Id = @RunId AND Status = 1 AND LeaseId = @LeaseId
          AND LeaseUntilUtc > @CompletedAtUtc;
        IF @@ROWCOUNT <> 1
            THROW 54134, N'Semantic evaluation completion lease changed concurrently.', 1;
        IF @Started = 1 COMMIT TRANSACTION;
        SELECT CONVERT(BIT, 1) AS Succeeded, CONVERT(BIT, 0) AS WasReplay,
               N'completed' AS Code;
    END TRY
    BEGIN CATCH
        IF @Started = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_SemanticEvalComplete;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SemanticEvaluationRun_Wait
    @RunPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @ReasonCode NVARCHAR(50),
    @NextAttemptAtUtc DATETIME2(3),
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    IF @ReasonCode <> N'semantic-embeddings-pending' OR @NextAttemptAtUtc <= @NowUtc
       OR @NextAttemptAtUtc > DATEADD(HOUR, 1, @NowUtc)
        THROW 54132, N'Bounded semantic wait metadata is invalid.', 1;
    UPDATE dbo.FundingPlatform_SemanticEvaluationRuns
    SET Status = 0, LeaseId = NULL, LeaseOwnerHash = NULL, LeaseUntilUtc = NULL,
        AttemptCount = CASE WHEN AttemptCount > 0 THEN AttemptCount - 1 ELSE 0 END,
        NextAttemptAtUtc = @NextAttemptAtUtc, ErrorCode = NULL, UpdatedAtUtc = @NowUtc
    WHERE PublicId = @RunPublicId AND Status = 1 AND LeaseId = @LeaseId
      AND LeaseUntilUtc > @NowUtc;
    SELECT CONVERT(BIT, CASE WHEN @@ROWCOUNT = 1 THEN 1 ELSE 0 END) AS Succeeded;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SemanticEvaluationRun_List
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @PageNumber INT = 1,
    @PageSize INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @AdminUserPublicId IS NULL OR @PageNumber NOT BETWEEN 1 AND 10000
       OR @PageSize NOT BETWEEN 1 AND 100
        THROW 54138, N'Bounded semantic evaluation list parameters are required.', 1;
    DECLARE @ActorUserId BIGINT;
    BEGIN TRANSACTION;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId = @AdminUserPublicId, @ActorUserId = @ActorUserId OUTPUT;
        SELECT COUNT_BIG(1) AS TotalCount
        FROM dbo.FundingPlatform_SemanticEvaluationRuns;
        SELECT PublicId, Status, EvaluationSetVersion, SemanticConfigurationVersion,
               ProviderCode, ModelCode, Dimensions, PurposeCode, NormalizationVersion,
               ProjectCount, OpportunityCount, PairCount, PrimaryCohortCount,
               EvaluatedCount, LabelledCount, CoveragePercentage,
               ProviderSuccessPercentage, RecallAt10,
               NormalizedDiscountedCumulativeGainAt10,
               BaselineNormalizedDiscountedCumulativeGainAt10,
               NormalizedDiscountedCumulativeGainDelta, MeanReciprocalRankAt10,
               MeanRankDelta, TotalEstimatedCostUsd, LatencyP95Milliseconds,
               HardGatePromotionCount, MeetsPromotionGate, CreatedAtUtc,
               StartedAtUtc, CompletedAtUtc, LastErrorCode
        FROM dbo.FundingPlatform_ifn_SemanticEvaluationRunSummaries()
        ORDER BY CreatedAtUtc DESC, SemanticEvaluationRunId DESC
        OFFSET CONVERT(BIGINT, @PageNumber - 1) * @PageSize ROWS
        FETCH NEXT @PageSize ROWS ONLY;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SemanticEvaluationRun_Get
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @RunPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @AdminUserPublicId IS NULL OR @RunPublicId IS NULL
        THROW 54139, N'Semantic evaluation run identity is required.', 1;
    DECLARE @ActorUserId BIGINT, @RunId BIGINT;
    BEGIN TRANSACTION;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId = @AdminUserPublicId, @ActorUserId = @ActorUserId OUTPUT;
        SELECT @RunId = SemanticEvaluationRunId
        FROM dbo.FundingPlatform_ifn_SemanticEvaluationRunSummaries()
        WHERE PublicId = @RunPublicId;
        SELECT PublicId, Status, EvaluationSetVersion, SemanticConfigurationVersion,
               ProviderCode, ModelCode, Dimensions, PurposeCode, NormalizationVersion,
               ProjectCount, OpportunityCount, PairCount, PrimaryCohortCount,
               EvaluatedCount, LabelledCount, CoveragePercentage,
               ProviderSuccessPercentage, RecallAt10,
               NormalizedDiscountedCumulativeGainAt10,
               BaselineNormalizedDiscountedCumulativeGainAt10,
               NormalizedDiscountedCumulativeGainDelta, MeanReciprocalRankAt10,
               MeanRankDelta, TotalEstimatedCostUsd, LatencyP95Milliseconds,
               HardGatePromotionCount, MeetsPromotionGate, CreatedAtUtc,
               StartedAtUtc, CompletedAtUtc, LastErrorCode
        FROM dbo.FundingPlatform_ifn_SemanticEvaluationRunSummaries()
        WHERE SemanticEvaluationRunId = @RunId;
        ;WITH addresses AS
        (
            SELECT ProjectContentAddress AS ContentAddress
            FROM dbo.FundingPlatform_SemanticEvaluationRunCases WHERE SemanticEvaluationRunId = @RunId
            UNION
            SELECT OpportunityContentAddress
            FROM dbo.FundingPlatform_SemanticEvaluationRunCases WHERE SemanticEvaluationRunId = @RunId
        ), relevantJobs AS
        (
            SELECT jobs.Id, jobs.Status, jobs.ErrorCode
            FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
            INNER JOIN addresses ON addresses.ContentAddress = jobs.ContentAddress
        )
        SELECT COALESCE(SUM(CASE WHEN Status = 0 THEN 1 ELSE 0 END), 0)
                   AS QueuedEmbeddingJobCount,
               COALESCE(SUM(CASE WHEN Status = 1 THEN 1 ELSE 0 END), 0)
                   AS ProcessingEmbeddingJobCount,
               COALESCE(SUM(CASE WHEN Status = 2 THEN 1 ELSE 0 END), 0)
                   AS SucceededEmbeddingJobCount,
               COALESCE(SUM(CASE WHEN Status = 3 THEN 1 ELSE 0 END), 0)
                   AS RetryScheduledEmbeddingJobCount,
               COALESCE(SUM(CASE WHEN Status = 4 AND ErrorCode NOT IN
                    (N'invalid-canonical-input', N'input-too-large', N'pii-email-detected',
                     N'pii-url-detected', N'pii-rut-detected', N'input-rejected',
                     N'semantic-input-invalid', N'semantic-input-hash-mismatch',
                     N'semantic-input-privacy-rejected') THEN 1 ELSE 0 END), 0)
                   AS PermanentFailedEmbeddingJobCount,
               COALESCE(SUM(CASE WHEN Status = 5 AND ErrorCode = N'stale-subject'
                                 THEN 1 ELSE 0 END), 0) AS SkippedStaleEmbeddingJobCount,
               COALESCE(SUM(CASE WHEN Status = 4 AND ErrorCode IN
                    (N'invalid-canonical-input', N'input-too-large', N'pii-email-detected',
                     N'pii-url-detected', N'pii-rut-detected', N'input-rejected',
                     N'semantic-input-invalid', N'semantic-input-hash-mismatch',
                     N'semantic-input-privacy-rejected') THEN 1 ELSE 0 END), 0)
                   AS RejectedInputEmbeddingJobCount
        FROM relevantJobs;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SemanticEvaluationRun_Report
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @RunPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @AdminUserPublicId IS NULL OR @RunPublicId IS NULL
        THROW 54139, N'Semantic evaluation report identity is required.', 1;
    DECLARE @ActorUserId BIGINT, @RunId BIGINT;
    BEGIN TRANSACTION;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId = @AdminUserPublicId, @ActorUserId = @ActorUserId OUTPUT;
        SELECT @RunId = SemanticEvaluationRunId
        FROM dbo.FundingPlatform_ifn_SemanticEvaluationRunSummaries()
        WHERE PublicId = @RunPublicId;
        SELECT PublicId, Status, EvaluationSetVersion, SemanticConfigurationVersion,
               ProviderCode, ModelCode, Dimensions, PurposeCode, NormalizationVersion,
               ProjectCount, OpportunityCount, PairCount, PrimaryCohortCount,
               EvaluatedCount, LabelledCount, CoveragePercentage,
               ProviderSuccessPercentage, RecallAt10,
               NormalizedDiscountedCumulativeGainAt10,
               BaselineNormalizedDiscountedCumulativeGainAt10,
               NormalizedDiscountedCumulativeGainDelta, MeanReciprocalRankAt10,
               MeanRankDelta, TotalEstimatedCostUsd, LatencyP95Milliseconds,
               HardGatePromotionCount, MeetsPromotionGate, CreatedAtUtc,
               StartedAtUtc, CompletedAtUtc, LastErrorCode
        FROM dbo.FundingPlatform_ifn_SemanticEvaluationRunSummaries()
        WHERE SemanticEvaluationRunId = @RunId;
        SELECT cases.DatasetSplit,
               COUNT_BIG(1) AS PairCount,
               COUNT_BIG(items.CaseOrdinal) AS EvaluatedCount,
               COUNT_BIG(items.CaseOrdinal) AS LabelledCount,
               SUM(CASE WHEN cases.RelevanceLabel > 0 THEN CONVERT(BIGINT, 1) ELSE 0 END)
                   AS RelevantLabelCount,
               CONVERT(DECIMAL(5,2), 100.0 * COUNT_BIG(items.CaseOrdinal) /
                   NULLIF(COUNT_BIG(1), 0)) AS CoveragePercentage,
               CASE WHEN cases.DatasetSplit = 1 THEN runs.RecallAt10 END AS RecallAt10,
               CASE WHEN cases.DatasetSplit = 1 THEN runs.NdcgAt10 END
                   AS NormalizedDiscountedCumulativeGainAt10,
               CASE WHEN cases.DatasetSplit = 1 THEN runs.BaselineNdcgAt10 END
                   AS BaselineNormalizedDiscountedCumulativeGainAt10,
               CASE WHEN cases.DatasetSplit = 1 THEN runs.NdcgDelta END
                   AS NormalizedDiscountedCumulativeGainDelta,
               CASE WHEN cases.DatasetSplit = 1 THEN runs.MrrAt10 END
                   AS MeanReciprocalRankAt10,
               CASE WHEN cases.DatasetSplit = 1 THEN runs.MeanRankDelta END AS MeanRankDelta
        FROM dbo.FundingPlatform_SemanticEvaluationRunCases AS cases
        INNER JOIN dbo.FundingPlatform_SemanticEvaluationRuns AS runs
            ON runs.Id = cases.SemanticEvaluationRunId
        LEFT JOIN dbo.FundingPlatform_SemanticEvaluationItems AS items
            ON items.SemanticEvaluationRunId = cases.SemanticEvaluationRunId
           AND items.CaseOrdinal = cases.CaseOrdinal
        WHERE cases.SemanticEvaluationRunId = @RunId
        GROUP BY cases.DatasetSplit, runs.RecallAt10, runs.NdcgAt10,
                 runs.BaselineNdcgAt10, runs.NdcgDelta, runs.MrrAt10, runs.MeanRankDelta
        ORDER BY cases.DatasetSplit;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SemanticEvaluationRun_Fail
    @RunPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @ErrorCode NVARCHAR(50),
    @Retryable BIT,
    @FailedAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @ErrorCode NOT IN
       (N'semantic-configuration-invalid', N'semantic-work-invalid',
        N'semantic-embedding-permanent-failure', N'semantic-evaluation-error', N'internal-error')
        THROW 54133, N'Sanitized semantic evaluation failure code is required.', 1;
    IF @RunPublicId IS NULL OR @LeaseId IS NULL OR @Retryable IS NULL OR @FailedAtUtc IS NULL
        THROW 54133, N'Complete semantic evaluation failure metadata is required.', 1;
    DECLARE @Attempt TINYINT, @WillRetry BIT;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @Started BIT = 0;
    IF @InitialTransactionCount = 0 BEGIN BEGIN TRANSACTION; SET @Started = 1; END
    ELSE SAVE TRANSACTION FP_SemanticEvalFail;
    BEGIN TRY
        SELECT @Attempt = AttemptCount
        FROM dbo.FundingPlatform_SemanticEvaluationRuns WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @RunPublicId AND Status = 1 AND LeaseId = @LeaseId
          AND LeaseUntilUtc > @FailedAtUtc;
        IF @Attempt IS NULL THROW 54134, N'Semantic evaluation failure lease is stale.', 1;
        SET @WillRetry = CASE WHEN @Retryable = 1 AND @Attempt < 3 THEN 1 ELSE 0 END;
        UPDATE dbo.FundingPlatform_SemanticEvaluationRuns
        SET Status = CASE WHEN @WillRetry = 1 THEN 3 ELSE 4 END,
            NextAttemptAtUtc = CASE WHEN @WillRetry = 1 THEN DATEADD(MINUTE, 1, @FailedAtUtc)
                                   ELSE NextAttemptAtUtc END,
            LeaseId = NULL, LeaseOwnerHash = NULL, LeaseUntilUtc = NULL,
            ErrorCode = @ErrorCode,
            CompletedAtUtc = CASE WHEN @WillRetry = 1 THEN NULL ELSE @FailedAtUtc END,
            UpdatedAtUtc = @FailedAtUtc
        WHERE PublicId = @RunPublicId AND Status = 1 AND LeaseId = @LeaseId
          AND LeaseUntilUtc > @FailedAtUtc;
        IF @@ROWCOUNT <> 1 THROW 54134, N'Semantic evaluation failure lease changed concurrently.', 1;
        IF @Started = 1 COMMIT TRANSACTION;
        SELECT CONVERT(BIT, 1) AS Succeeded,
               CASE WHEN @WillRetry = 1 THEN N'retry-scheduled' ELSE N'permanent-failed' END AS Code;
    END TRY
    BEGIN CATCH
        IF @Started = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_SemanticEvalFail;
        THROW;
    END CATCH;
END;
GO

/* Least-privilege execution surfaces. Membership is deployment-owned; this
   migration creates no users and assigns no principal. Ownership chaining lets
   the procedures use dbo tables while both roles are denied direct semantic data. */
IF DATABASE_PRINCIPAL_ID(N'FundingPlatform_SemanticWorkerRole') IS NULL
    CREATE ROLE FundingPlatform_SemanticWorkerRole AUTHORIZATION dbo;
IF DATABASE_PRINCIPAL_ID(N'FundingPlatform_SemanticAdminRole') IS NULL
    CREATE ROLE FundingPlatform_SemanticAdminRole AUTHORIZATION dbo;
GO

GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SemanticEmbeddingJob_Claim TO FundingPlatform_SemanticWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SemanticEmbeddingJob_GetInput TO FundingPlatform_SemanticWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SemanticEmbeddingJob_RenewLease TO FundingPlatform_SemanticWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SemanticEmbeddingJob_Complete TO FundingPlatform_SemanticWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SemanticEmbeddingJob_Fail TO FundingPlatform_SemanticWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SemanticEvaluationRun_Claim TO FundingPlatform_SemanticWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SemanticEvaluationRun_RenewLease TO FundingPlatform_SemanticWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SemanticEvaluationRun_GetWork TO FundingPlatform_SemanticWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SemanticEvaluationRun_Complete TO FundingPlatform_SemanticWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SemanticEvaluationRun_Wait TO FundingPlatform_SemanticWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SemanticEvaluationRun_Fail TO FundingPlatform_SemanticWorkerRole;

GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SemanticEmbeddingJob_BackfillEnqueue TO FundingPlatform_SemanticAdminRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SemanticEvaluationRun_Create TO FundingPlatform_SemanticAdminRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SemanticEvaluationRun_List TO FundingPlatform_SemanticAdminRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SemanticEvaluationRun_Get TO FundingPlatform_SemanticAdminRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SemanticEvaluationRun_Report TO FundingPlatform_SemanticAdminRole;

DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticConfigurations TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticEvaluationSets TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticEvaluationCases TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticEmbeddingJobs TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticEmbeddings TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticBudgetReservations TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticUsageLedger TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticEvaluationRuns TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticEvaluationRunCases TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticEvaluationItems TO FundingPlatform_SemanticWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticEvaluationRunRequests TO FundingPlatform_SemanticWorkerRole;

DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticConfigurations TO FundingPlatform_SemanticAdminRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticEvaluationSets TO FundingPlatform_SemanticAdminRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticEvaluationCases TO FundingPlatform_SemanticAdminRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticEmbeddingJobs TO FundingPlatform_SemanticAdminRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticEmbeddings TO FundingPlatform_SemanticAdminRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticBudgetReservations TO FundingPlatform_SemanticAdminRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticUsageLedger TO FundingPlatform_SemanticAdminRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticEvaluationRuns TO FundingPlatform_SemanticAdminRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticEvaluationRunCases TO FundingPlatform_SemanticAdminRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticEvaluationItems TO FundingPlatform_SemanticAdminRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SemanticEvaluationRunRequests TO FundingPlatform_SemanticAdminRole;
GO
