/* FundingPlatform FASE 7A - durable, governed acquisition for approved official APIs. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

/* Existing sources remain valid. Only sources with an approved compliance state,
   a provider code and a fixed interval participate in automated acquisition. */
ALTER TABLE dbo.FundingPlatform_FundingSources ADD
    ProviderCode NVARCHAR(100) NULL,
    ScheduleIntervalSeconds INT NULL,
    NextRunAtUtc DATETIME2(3) NULL,
    ComplianceStatus TINYINT NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingSources_ComplianceStatus DEFAULT (0),
    ComplianceApprovedAtUtc DATETIME2(3) NULL,
    MaxRunAttempts SMALLINT NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingSources_MaxRunAttempts DEFAULT (3),
    RetryBaseDelaySeconds INT NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingSources_RetryBaseDelay DEFAULT (60),
    ConsecutiveFailureCount INT NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingSources_ConsecutiveFailures DEFAULT (0);
GO

ALTER TABLE dbo.FundingPlatform_FundingSources
    ADD CONSTRAINT FundingPlatform_CK_FundingSources_ProviderCode
        CHECK (ProviderCode IS NULL
               OR (NULLIF(LTRIM(RTRIM(ProviderCode)), N'') IS NOT NULL
                   AND ProviderCode = LOWER(ProviderCode)
                   AND CHARINDEX(N' ', ProviderCode) = 0
                   AND CHARINDEX(CHAR(10), ProviderCode) = 0
                   AND CHARINDEX(CHAR(13), ProviderCode) = 0));
ALTER TABLE dbo.FundingPlatform_FundingSources
    ADD CONSTRAINT FundingPlatform_CK_FundingSources_FixedSchedule
        CHECK (ScheduleIntervalSeconds IS NULL
               OR ScheduleIntervalSeconds BETWEEN 300 AND 604800);
ALTER TABLE dbo.FundingPlatform_FundingSources
    ADD CONSTRAINT FundingPlatform_CK_FundingSources_Compliance
        CHECK (ComplianceStatus BETWEEN 0 AND 2
               AND ((ComplianceStatus = 1 AND ComplianceApprovedAtUtc IS NOT NULL)
                    OR (ComplianceStatus <> 1 AND ComplianceApprovedAtUtc IS NULL)));
ALTER TABLE dbo.FundingPlatform_FundingSources
    ADD CONSTRAINT FundingPlatform_CK_FundingSources_AcquisitionRetry
        CHECK (MaxRunAttempts BETWEEN 1 AND 10
               AND RetryBaseDelaySeconds BETWEEN 5 AND 3600
               AND ConsecutiveFailureCount >= 0);
ALTER TABLE dbo.FundingPlatform_FundingSources
    ADD CONSTRAINT FundingPlatform_CK_FundingSources_NextRun
        CHECK (NextRunAtUtc IS NULL
               OR (ProviderCode IS NOT NULL AND ScheduleIntervalSeconds IS NOT NULL));

CREATE UNIQUE INDEX FundingPlatform_UQ_FundingSources_ProviderCode
    ON dbo.FundingPlatform_FundingSources (ProviderCode)
    WHERE ProviderCode IS NOT NULL;

CREATE INDEX FundingPlatform_IX_FundingSources_Due
    ON dbo.FundingPlatform_FundingSources
       (NextRunAtUtc, Id)
    INCLUDE (ProviderCode, ScheduleIntervalSeconds, MaxRunAttempts,
             RetryBaseDelaySeconds)
    WHERE IsEnabled = 1 AND ComplianceStatus = 1
      AND ProviderCode IS NOT NULL AND ScheduleIntervalSeconds IS NOT NULL;

/* Trigger: 0 manual, 1 scheduled, 2 retry.
   Status: 0 queued, 1 running, 2 completed, 3 partial, 4 failed, 5 canceled. */
CREATE TABLE dbo.FundingPlatform_ImportRuns
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_ImportRuns_PublicId DEFAULT (NEWSEQUENTIALID()),
    FundingSourceId INT NOT NULL,
    TriggerType TINYINT NOT NULL,
    Status TINYINT NOT NULL
        CONSTRAINT FundingPlatform_DF_ImportRuns_Status DEFAULT (0),
    Keyword NVARCHAR(100) NOT NULL,
    MaximumResults INT NOT NULL,
    CorrelationId NVARCHAR(100) NOT NULL,
    RequestedByUserId BIGINT NULL,
    ScheduleSlotUtc DATETIME2(3) NULL,
    IdempotencyKeyHash BINARY(32) NULL,
    RequestHash BINARY(32) NULL,
    AttemptCount SMALLINT NOT NULL
        CONSTRAINT FundingPlatform_DF_ImportRuns_AttemptCount DEFAULT (0),
    MaxAttempts SMALLINT NOT NULL,
    RetryBaseDelaySeconds INT NOT NULL,
    NextAttemptAtUtc DATETIME2(3) NOT NULL,
    LeaseId UNIQUEIDENTIFIER NULL,
    LeaseUntilUtc DATETIME2(3) NULL,
    RetrievedCount INT NOT NULL
        CONSTRAINT FundingPlatform_DF_ImportRuns_RetrievedCount DEFAULT (0),
    CreatedCount INT NOT NULL
        CONSTRAINT FundingPlatform_DF_ImportRuns_CreatedCount DEFAULT (0),
    UpdatedCount INT NOT NULL
        CONSTRAINT FundingPlatform_DF_ImportRuns_UpdatedCount DEFAULT (0),
    UnchangedCount INT NOT NULL
        CONSTRAINT FundingPlatform_DF_ImportRuns_UnchangedCount DEFAULT (0),
    StagedForReviewCount INT NOT NULL
        CONSTRAINT FundingPlatform_DF_ImportRuns_StagedCount DEFAULT (0),
    FailedCount INT NOT NULL
        CONSTRAINT FundingPlatform_DF_ImportRuns_FailedCount DEFAULT (0),
    LastErrorCode NVARCHAR(100) NULL,
    LastErrorMessage NVARCHAR(1000) NULL,
    StartedAtUtc DATETIME2(3) NULL,
    CompletedAtUtc DATETIME2(3) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_ImportRuns_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_ImportRuns_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_ImportRuns PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_ImportRuns_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_ImportRuns_IdSource UNIQUE (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_FK_ImportRuns_Source FOREIGN KEY (FundingSourceId)
        REFERENCES dbo.FundingPlatform_FundingSources (Id),
    CONSTRAINT FundingPlatform_FK_ImportRuns_Requester FOREIGN KEY (RequestedByUserId)
        REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_ImportRuns_Enums
        CHECK (TriggerType BETWEEN 0 AND 2 AND Status BETWEEN 0 AND 5),
    CONSTRAINT FundingPlatform_CK_ImportRuns_Request
        CHECK (NULLIF(LTRIM(RTRIM(Keyword)), N'') IS NOT NULL
               AND LEN(Keyword) <= 100
               AND MaximumResults BETWEEN 1 AND 25
               AND NULLIF(LTRIM(RTRIM(CorrelationId)), N'') IS NOT NULL
               AND CorrelationId = LTRIM(RTRIM(CorrelationId))
               AND CorrelationId COLLATE Latin1_General_100_BIN2
                   NOT LIKE N'%[^A-Za-z0-9:_.-]%' COLLATE Latin1_General_100_BIN2
               AND CHARINDEX(CHAR(10), CorrelationId) = 0
               AND CHARINDEX(CHAR(13), CorrelationId) = 0),
    CONSTRAINT FundingPlatform_CK_ImportRuns_Trigger
        CHECK ((TriggerType = 0 AND RequestedByUserId IS NOT NULL
                AND ScheduleSlotUtc IS NULL
                AND IdempotencyKeyHash IS NOT NULL AND RequestHash IS NOT NULL)
               OR (TriggerType = 1 AND RequestedByUserId IS NULL
                   AND ScheduleSlotUtc IS NOT NULL
                   AND IdempotencyKeyHash IS NULL AND RequestHash IS NULL)
               OR TriggerType = 2),
    CONSTRAINT FundingPlatform_CK_ImportRuns_Attempts
        CHECK (AttemptCount BETWEEN 0 AND MaxAttempts
               AND MaxAttempts BETWEEN 1 AND 10
               AND RetryBaseDelaySeconds BETWEEN 5 AND 3600),
    CONSTRAINT FundingPlatform_CK_ImportRuns_Counters
        CHECK (RetrievedCount >= 0 AND CreatedCount >= 0 AND UpdatedCount >= 0
               AND UnchangedCount >= 0 AND StagedForReviewCount >= 0
               AND FailedCount >= 0
               AND CreatedCount + UpdatedCount + UnchangedCount
                   + StagedForReviewCount + FailedCount <= RetrievedCount),
    CONSTRAINT FundingPlatform_CK_ImportRuns_LeaseState
        CHECK ((Status = 0 AND LeaseId IS NULL AND LeaseUntilUtc IS NULL
                AND CompletedAtUtc IS NULL)
               OR (Status = 1 AND LeaseId IS NOT NULL AND LeaseUntilUtc IS NOT NULL
                   AND StartedAtUtc IS NOT NULL AND CompletedAtUtc IS NULL)
               OR (Status BETWEEN 2 AND 5 AND LeaseId IS NULL AND LeaseUntilUtc IS NULL
                   AND CompletedAtUtc IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_ImportRuns_Timestamps
        CHECK (UpdatedAtUtc >= CreatedAtUtc
               AND NextAttemptAtUtc >= CreatedAtUtc
               AND (StartedAtUtc IS NULL OR StartedAtUtc >= CreatedAtUtc)
               AND (CompletedAtUtc IS NULL OR CompletedAtUtc >= CreatedAtUtc)
               AND (LeaseUntilUtc IS NULL OR LeaseUntilUtc > UpdatedAtUtc)),
    CONSTRAINT FundingPlatform_CK_ImportRuns_Error
        CHECK ((LastErrorCode IS NULL AND LastErrorMessage IS NULL)
               OR (NULLIF(LTRIM(RTRIM(LastErrorCode)), N'') IS NOT NULL
                   AND NULLIF(LTRIM(RTRIM(LastErrorMessage)), N'') IS NOT NULL
                   AND CHARINDEX(CHAR(10), LastErrorCode) = 0
                   AND CHARINDEX(CHAR(13), LastErrorCode) = 0
                   AND CHARINDEX(CHAR(10), LastErrorMessage) = 0
                   AND CHARINDEX(CHAR(13), LastErrorMessage) = 0))
);

CREATE UNIQUE INDEX FundingPlatform_UQ_ImportRuns_ManualIdempotency
    ON dbo.FundingPlatform_ImportRuns
       (RequestedByUserId, FundingSourceId, IdempotencyKeyHash)
    WHERE TriggerType = 0 AND RequestedByUserId IS NOT NULL
      AND IdempotencyKeyHash IS NOT NULL;

CREATE UNIQUE INDEX FundingPlatform_UQ_ImportRuns_ScheduleSlot
    ON dbo.FundingPlatform_ImportRuns (FundingSourceId, ScheduleSlotUtc)
    WHERE TriggerType = 1 AND ScheduleSlotUtc IS NOT NULL;

CREATE INDEX FundingPlatform_IX_ImportRuns_Claim
    ON dbo.FundingPlatform_ImportRuns (Status, NextAttemptAtUtc, CreatedAtUtc, Id)
    INCLUDE (PublicId, FundingSourceId, AttemptCount, MaxAttempts, LeaseUntilUtc);

CREATE INDEX FundingPlatform_IX_ImportRuns_AdminList
    ON dbo.FundingPlatform_ImportRuns (CreatedAtUtc DESC, Id DESC)
    INCLUDE (PublicId, FundingSourceId, TriggerType, Status, CompletedAtUtc,
             RetrievedCount, CreatedCount, UpdatedCount, UnchangedCount,
             StagedForReviewCount, FailedCount);

/* Source-faithful payloads are globally deduplicated per source and immutable.
   The first run does not own the raw row; any later run may reference it. */
CREATE TABLE dbo.FundingPlatform_RawFundingOpportunities
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_RawFundingOpportunities_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    FundingSourceId INT NOT NULL,
    ExternalId NVARCHAR(250) NOT NULL,
    SourceItemKeyHash BINARY(32) NOT NULL,
    ContentHash BINARY(32) NOT NULL,
    SourceUrl NVARCHAR(2048) NOT NULL,
    MimeType NVARCHAR(100) NOT NULL,
    RawContent NVARCHAR(MAX) NOT NULL,
    RetrievedAtUtc DATETIME2(3) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_RawFundingOpportunities_CreatedAtUtc
        DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_RawFundingOpportunities PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_RawFundingOpportunities_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_RawFundingOpportunities_IdSource
        UNIQUE (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_UQ_RawFundingOpportunities_SourceContent
        UNIQUE (FundingSourceId, SourceItemKeyHash, ContentHash),
    CONSTRAINT FundingPlatform_FK_RawFundingOpportunities_Source
        FOREIGN KEY (FundingSourceId) REFERENCES dbo.FundingPlatform_FundingSources (Id),
    CONSTRAINT FundingPlatform_CK_RawFundingOpportunities_Identity
        CHECK (NULLIF(LTRIM(RTRIM(ExternalId)), N'') IS NOT NULL
               AND NULLIF(LTRIM(RTRIM(SourceUrl)), N'') IS NOT NULL
               AND CHARINDEX(CHAR(10), ExternalId) = 0
               AND CHARINDEX(CHAR(13), ExternalId) = 0),
    CONSTRAINT FundingPlatform_CK_RawFundingOpportunities_Content
        CHECK (NULLIF(LTRIM(RTRIM(MimeType)), N'') IS NOT NULL
               AND DATALENGTH(RawContent) BETWEEN 2 AND 4194304
               AND (LOWER(MimeType) <> N'application/json' OR ISJSON(RawContent) = 1)),
    CONSTRAINT FundingPlatform_CK_RawFundingOpportunities_Time
        CHECK (RetrievedAtUtc >= DATEADD(DAY, -30, CreatedAtUtc)
               AND RetrievedAtUtc <= DATEADD(MINUTE, 5, CreatedAtUtc))
);

CREATE INDEX FundingPlatform_IX_RawFundingOpportunities_SourceExternal
    ON dbo.FundingPlatform_RawFundingOpportunities
       (FundingSourceId, ExternalId, RetrievedAtUtc DESC, Id DESC)
    INCLUDE (PublicId, SourceItemKeyHash, ContentHash);

/* Status: 0 pending, 1 processing, 2 completed, 3 failed. */
CREATE TABLE dbo.FundingPlatform_ImportRunItems
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_ImportRunItems_PublicId DEFAULT (NEWSEQUENTIALID()),
    ImportRunId BIGINT NOT NULL,
    FundingSourceId INT NOT NULL,
    RawFundingOpportunityId BIGINT NOT NULL,
    FundingOpportunityId BIGINT NULL,
    ExternalId NVARCHAR(250) NOT NULL,
    SourceItemKeyHash BINARY(32) NOT NULL,
    NormalizedSnapshotVersion SMALLINT NOT NULL,
    NormalizedSnapshotJson NVARCHAR(MAX) NOT NULL,
    NormalizedSnapshotHash BINARY(32) NOT NULL,
    Status TINYINT NOT NULL,
    OutcomeCode NVARCHAR(50) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_ImportRunItems_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CompletedAtUtc DATETIME2(3) NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_ImportRunItems_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_ImportRunItems PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_ImportRunItems_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_ImportRunItems_IdRunSource
        UNIQUE (Id, ImportRunId, FundingSourceId),
    CONSTRAINT FundingPlatform_UQ_ImportRunItems_RunItem
        UNIQUE (ImportRunId, SourceItemKeyHash),
    CONSTRAINT FundingPlatform_FK_ImportRunItems_Run
        FOREIGN KEY (ImportRunId, FundingSourceId)
        REFERENCES dbo.FundingPlatform_ImportRuns (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_FK_ImportRunItems_Raw
        FOREIGN KEY (RawFundingOpportunityId, FundingSourceId)
        REFERENCES dbo.FundingPlatform_RawFundingOpportunities (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_FK_ImportRunItems_Opportunity
        FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id),
    CONSTRAINT FundingPlatform_CK_ImportRunItems_Status CHECK (Status BETWEEN 0 AND 3),
    CONSTRAINT FundingPlatform_CK_ImportRunItems_Identity
        CHECK (NULLIF(LTRIM(RTRIM(ExternalId)), N'') IS NOT NULL
               AND CHARINDEX(CHAR(10), ExternalId) = 0
               AND CHARINDEX(CHAR(13), ExternalId) = 0),
    CONSTRAINT FundingPlatform_CK_ImportRunItems_NormalizedSnapshot
        CHECK (NormalizedSnapshotVersion = 1
               AND ISJSON(NormalizedSnapshotJson) = 1
               AND COALESCE(TRY_CONVERT
                   (SMALLINT, JSON_VALUE(NormalizedSnapshotJson, N'$.schemaVersion')), -1)
                   = NormalizedSnapshotVersion
               AND COALESCE(LEFT(LTRIM(JSON_QUERY
                   (NormalizedSnapshotJson, N'$.opportunity')), 1), N'') = N'{'
               AND DATALENGTH
                   (CONVERT(VARCHAR(MAX),
                            NormalizedSnapshotJson COLLATE Latin1_General_100_BIN2_UTF8))
                   BETWEEN 2 AND 262144),
    CONSTRAINT FundingPlatform_CK_ImportRunItems_State
        CHECK ((Status IN (0, 1) AND OutcomeCode IS NULL AND CompletedAtUtc IS NULL)
               OR (Status = 2 AND NULLIF(LTRIM(RTRIM(OutcomeCode)), N'') IS NOT NULL
                   AND CompletedAtUtc IS NOT NULL)
               OR (Status = 3 AND OutcomeCode = N'failed' AND CompletedAtUtc IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_ImportRunItems_Timestamps
        CHECK (UpdatedAtUtc >= CreatedAtUtc
               AND (CompletedAtUtc IS NULL OR CompletedAtUtc >= CreatedAtUtc))
);

CREATE INDEX FundingPlatform_IX_ImportRunItems_Run
    ON dbo.FundingPlatform_ImportRunItems (ImportRunId, Id)
    INCLUDE (PublicId, RawFundingOpportunityId, FundingOpportunityId,
             ExternalId, Status, OutcomeCode, CreatedAtUtc, CompletedAtUtc,
             NormalizedSnapshotVersion);

CREATE TABLE dbo.FundingPlatform_ImportErrors
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_ImportErrors_PublicId DEFAULT (NEWSEQUENTIALID()),
    ImportRunId BIGINT NOT NULL,
    FundingSourceId INT NOT NULL,
    ImportRunItemId BIGINT NULL,
    Stage NVARCHAR(50) NOT NULL,
    ErrorCode NVARCHAR(100) NOT NULL,
    SanitizedMessage NVARCHAR(1000) NOT NULL,
    IsRetryable BIT NOT NULL,
    OccurredAtUtc DATETIME2(3) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_ImportErrors_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_ImportErrors PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_ImportErrors_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_FK_ImportErrors_Run
        FOREIGN KEY (ImportRunId, FundingSourceId)
        REFERENCES dbo.FundingPlatform_ImportRuns (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_FK_ImportErrors_Item
        FOREIGN KEY (ImportRunItemId, ImportRunId, FundingSourceId)
        REFERENCES dbo.FundingPlatform_ImportRunItems (Id, ImportRunId, FundingSourceId),
    CONSTRAINT FundingPlatform_CK_ImportErrors_Fields
        CHECK (NULLIF(LTRIM(RTRIM(Stage)), N'') IS NOT NULL
               AND NULLIF(LTRIM(RTRIM(ErrorCode)), N'') IS NOT NULL
               AND NULLIF(LTRIM(RTRIM(SanitizedMessage)), N'') IS NOT NULL
               AND CHARINDEX(CHAR(10), Stage) = 0
               AND CHARINDEX(CHAR(13), Stage) = 0
               AND CHARINDEX(CHAR(10), ErrorCode) = 0
               AND CHARINDEX(CHAR(13), ErrorCode) = 0
               AND CHARINDEX(CHAR(10), SanitizedMessage) = 0
               AND CHARINDEX(CHAR(13), SanitizedMessage) = 0),
    CONSTRAINT FundingPlatform_CK_ImportErrors_Time
        CHECK (OccurredAtUtc >= DATEADD(DAY, -30, CreatedAtUtc)
               AND OccurredAtUtc <= DATEADD(MINUTE, 5, CreatedAtUtc))
);

CREATE INDEX FundingPlatform_IX_ImportErrors_Run
    ON dbo.FundingPlatform_ImportErrors (ImportRunId, OccurredAtUtc, Id)
    INCLUDE (PublicId, ImportRunItemId, Stage, ErrorCode, IsRetryable);

GO
CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_RawFundingOpportunities_Immutable
ON dbo.FundingPlatform_RawFundingOpportunities
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    THROW 51730, N'Raw funding observations are immutable.', 1;
END;
GO

/* Official Grants.gov API seed. Configuration contains no secret and explicitly
   disables automatic publication; all normalized opportunities enter editorial draft. */
DECLARE @SeedNowUtc DATETIME2(3) = SYSUTCDATETIME();

INSERT INTO dbo.FundingPlatform_FundingSources
(
    Name, ProviderType, BaseUrl, IsEnabled, ScheduleCron, MinimumDelaySeconds,
    UserAgent, TermsUrl, TermsReviewedAtUtc, RobotsReviewedAtUtc,
    LastSuccessfulRunAtUtc, ConfigurationJson, SecretReference,
    ProviderCode, ScheduleIntervalSeconds, NextRunAtUtc,
    ComplianceStatus, ComplianceApprovedAtUtc, MaxRunAttempts,
    RetryBaseDelaySeconds, ConsecutiveFailureCount, CreatedAtUtc, UpdatedAtUtc
)
SELECT N'Grants.gov', 1, N'https://api.grants.gov/v1/api/', 1,
       N'fixed:86400', 1, N'FundingPlatform-MVP/0.1',
       N'https://www.grants.gov/api/terms-conditions', @SeedNowUtc, NULL,
       NULL,
       N'{"providerCode":"grants-gov","defaultKeyword":"nonprofit","maximumResults":25,"apiVersion":"v1","autoPublish":false}',
       NULL, N'grants-gov', 86400, DATEADD(DAY, 1, @SeedNowUtc),
       1, @SeedNowUtc, 3, 60, 0, @SeedNowUtc, @SeedNowUtc
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_FundingSources
    WHERE ProviderCode = N'grants-gov' OR Name = N'Grants.gov'
);

UPDATE dbo.FundingPlatform_FundingSources
SET ProviderCode = N'grants-gov',
    ProviderType = 1,
    BaseUrl = N'https://api.grants.gov/v1/api/',
    IsEnabled = 1,
    ScheduleCron = N'fixed:86400',
    ScheduleIntervalSeconds = 86400,
    NextRunAtUtc = COALESCE(NextRunAtUtc, DATEADD(DAY, 1, @SeedNowUtc)),
    MinimumDelaySeconds = 1,
    UserAgent = N'FundingPlatform-MVP/0.1',
    TermsUrl = N'https://www.grants.gov/api/terms-conditions',
    TermsReviewedAtUtc = COALESCE(TermsReviewedAtUtc, @SeedNowUtc),
    ComplianceStatus = 1,
    ComplianceApprovedAtUtc = COALESCE(ComplianceApprovedAtUtc, @SeedNowUtc),
    MaxRunAttempts = 3,
    RetryBaseDelaySeconds = 60,
    ConfigurationJson = N'{"providerCode":"grants-gov","defaultKeyword":"nonprofit","maximumResults":25,"apiVersion":"v1","autoPublish":false}',
    SecretReference = NULL,
    UpdatedAtUtc = @SeedNowUtc
WHERE Name = N'Grants.gov'
  AND (ProviderCode IS NULL OR ProviderCode = N'grants-gov');
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingSource_AdminList
    @AdminUserPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;

    SELECT Id, Name, ProviderType, BaseUrl, IsEnabled, ProviderCode,
           CASE ComplianceStatus WHEN 1 THEN N'approved'
                                 WHEN 2 THEN N'rejected'
                                 ELSE N'pending' END AS ComplianceStatus,
           NextRunAtUtc, LastSuccessfulRunAtUtc
    FROM dbo.FundingPlatform_FundingSources
    ORDER BY Name, Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ImportRun_Admin_Create
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FundingSourceId INT,
    @Keyword NVARCHAR(100),
    @MaximumResults INT,
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @CorrelationId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Keyword = LTRIM(RTRIM(@Keyword));
    IF NULLIF(@Keyword, N'') IS NULL OR LEN(@Keyword) > 100
        THROW 51701, N'Keyword is required and cannot exceed 100 characters.', 1;
    IF @MaximumResults < 1 OR @MaximumResults > 25
        THROW 51702, N'MaximumResults must be between 1 and 25.', 1;
    IF @IdempotencyKeyHash IS NULL OR @RequestHash IS NULL
        THROW 51703, N'Idempotency and request hashes are required.', 1;
    SET @CorrelationId = LTRIM(RTRIM(@CorrelationId));
    IF NULLIF(@CorrelationId, N'') IS NULL OR LEN(@CorrelationId) > 100
       OR @CorrelationId COLLATE Latin1_General_100_BIN2
          LIKE N'%[^A-Za-z0-9:_.-]%' COLLATE Latin1_General_100_BIN2
        THROW 51731, N'CorrelationId has an invalid format.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @StartedTransaction BIT = 0;
    DECLARE @ActorUserId BIGINT;
    DECLARE @RunId BIGINT, @RunPublicId UNIQUEIDENTIFIER;
    DECLARE @Status TINYINT, @CreatedAtUtc DATETIME2(3);
    DECLARE @SourceName NVARCHAR(150), @ProviderCode NVARCHAR(100);
    DECLARE @ExistingRequestHash BINARY(32), @WasReplay BIT = 0;
    DECLARE @Succeeded BIT = 0, @Code NVARCHAR(50) = N'not-found';
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();

    IF @InitialTransactionCount = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE SAVE TRANSACTION FP_ImportAdminCreate;

    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId = @AdminUserPublicId,
            @ActorUserId = @ActorUserId OUTPUT;

        SELECT @RunId = runs.Id, @RunPublicId = runs.PublicId,
               @Status = runs.Status, @CreatedAtUtc = runs.CreatedAtUtc,
               @ExistingRequestHash = runs.RequestHash,
               @SourceName = sources.Name, @ProviderCode = sources.ProviderCode
        FROM dbo.FundingPlatform_ImportRuns AS runs WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_FundingSources AS sources WITH (HOLDLOCK)
            ON sources.Id = runs.FundingSourceId
        WHERE runs.RequestedByUserId = @ActorUserId
          AND runs.FundingSourceId = @FundingSourceId
          AND runs.IdempotencyKeyHash = @IdempotencyKeyHash
          AND runs.TriggerType = 0;

        IF @RunId IS NOT NULL
        BEGIN
            IF @ExistingRequestHash = @RequestHash
            BEGIN
                SET @Succeeded = 1;
                SET @Code = N'replayed';
                SET @WasReplay = 1;
            END
            ELSE
            BEGIN
                SET @RunId = NULL;
                SET @RunPublicId = NULL;
                SET @Status = NULL;
                SET @CreatedAtUtc = NULL;
                SET @Code = N'idempotency-conflict';
            END;
        END
        ELSE
        BEGIN
            DECLARE @IsEnabled BIT, @ComplianceStatus TINYINT;
            DECLARE @MaxAttempts SMALLINT, @RetryBaseDelaySeconds INT;

            SELECT @SourceName = Name, @ProviderCode = ProviderCode,
                   @IsEnabled = IsEnabled, @ComplianceStatus = ComplianceStatus,
                   @MaxAttempts = MaxRunAttempts,
                   @RetryBaseDelaySeconds = RetryBaseDelaySeconds
            FROM dbo.FundingPlatform_FundingSources WITH (UPDLOCK, HOLDLOCK)
            WHERE Id = @FundingSourceId;

            IF @SourceName IS NULL
                SET @Code = N'not-found';
            ELSE IF @IsEnabled <> 1 OR @ProviderCode IS NULL
                SET @Code = N'source-disabled';
            ELSE IF @ComplianceStatus <> 1
                SET @Code = N'compliance-required';
            ELSE
            BEGIN
                DECLARE @InsertedRun TABLE
                    (Id BIGINT, PublicId UNIQUEIDENTIFIER, Status TINYINT,
                     CreatedAtUtc DATETIME2(3));

                INSERT INTO dbo.FundingPlatform_ImportRuns
                (
                    FundingSourceId, TriggerType, Status, Keyword, MaximumResults, CorrelationId,
                    RequestedByUserId, ScheduleSlotUtc, IdempotencyKeyHash, RequestHash,
                    AttemptCount, MaxAttempts, RetryBaseDelaySeconds, NextAttemptAtUtc,
                    CreatedAtUtc, UpdatedAtUtc
                )
                OUTPUT inserted.Id, inserted.PublicId, inserted.Status, inserted.CreatedAtUtc
                    INTO @InsertedRun (Id, PublicId, Status, CreatedAtUtc)
                VALUES
                (
                    @FundingSourceId, 0, 0, @Keyword, @MaximumResults, @CorrelationId,
                    @ActorUserId, NULL, @IdempotencyKeyHash, @RequestHash,
                    0, @MaxAttempts, @RetryBaseDelaySeconds, @NowUtc,
                    @NowUtc, @NowUtc
                );

                SELECT @RunId = Id, @RunPublicId = PublicId,
                       @Status = Status, @CreatedAtUtc = CreatedAtUtc
                FROM @InsertedRun;

                DECLARE @EventId UNIQUEIDENTIFIER = NEWID();
                INSERT INTO dbo.FundingPlatform_OutboxMessages
                    (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                     OccurredAtUtc, AvailableAtUtc)
                SELECT @EventId, N'ImportRunRequested', N'ImportRun',
                       CONVERT(NVARCHAR(100), @RunPublicId),
                       (SELECT @RunPublicId AS runId, 1 AS [version]
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                       @NowUtc, @NowUtc;

                SET @Succeeded = 1;
                SET @Code = N'created';
            END;
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ImportAdminCreate;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @RunPublicId AS RunPublicId, @FundingSourceId AS FundingSourceId,
           @SourceName AS SourceName, @Status AS Status,
           @CreatedAtUtc AS CreatedAtUtc, @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ImportRun_Admin_List
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FundingSourceId INT = NULL,
    @Status TINYINT = NULL,
    @PageNumber INT = 1,
    @PageSize INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    IF @Status IS NOT NULL AND @Status NOT BETWEEN 0 AND 5
        THROW 51704, N'Status is invalid.', 1;
    IF @PageNumber < 1 THROW 51705, N'PageNumber must be at least 1.', 1;
    IF @PageSize < 1 OR @PageSize > 100
        THROW 51706, N'PageSize must be between 1 and 100.', 1;

    SELECT COUNT_BIG(1) AS TotalCount
    FROM dbo.FundingPlatform_ImportRuns AS runs
    WHERE (@FundingSourceId IS NULL OR runs.FundingSourceId = @FundingSourceId)
      AND (@Status IS NULL OR runs.Status = @Status);

    SELECT runs.PublicId AS RunPublicId, runs.FundingSourceId,
           sources.Name AS SourceName, sources.ProviderCode,
           runs.TriggerType, runs.Status, runs.Keyword, runs.MaximumResults,
           runs.RetrievedCount, runs.CreatedCount, runs.UpdatedCount,
           runs.UnchangedCount, runs.StagedForReviewCount, runs.FailedCount,
           runs.CreatedAtUtc, runs.StartedAtUtc, runs.CompletedAtUtc,
           runs.LastErrorCode
    FROM dbo.FundingPlatform_ImportRuns AS runs
    INNER JOIN dbo.FundingPlatform_FundingSources AS sources
        ON sources.Id = runs.FundingSourceId
    WHERE (@FundingSourceId IS NULL OR runs.FundingSourceId = @FundingSourceId)
      AND (@Status IS NULL OR runs.Status = @Status)
    ORDER BY runs.CreatedAtUtc DESC, runs.Id DESC
    OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ImportRun_Admin_Get
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @RunPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;

    DECLARE @RunId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_ImportRuns WHERE PublicId = @RunPublicId);

    IF @RunId IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, CAST(N'not-found' AS NVARCHAR(50)) AS Code,
               CAST(NULL AS UNIQUEIDENTIFIER) AS RunPublicId,
               CAST(NULL AS INT) AS FundingSourceId,
               CAST(NULL AS NVARCHAR(150)) AS SourceName,
               CAST(NULL AS NVARCHAR(100)) AS ProviderCode,
               CAST(NULL AS TINYINT) AS TriggerType, CAST(NULL AS TINYINT) AS Status,
               CAST(NULL AS NVARCHAR(100)) AS Keyword,
               CAST(NULL AS INT) AS MaximumResults,
               CAST(NULL AS INT) AS RetrievedCount, CAST(NULL AS INT) AS CreatedCount,
               CAST(NULL AS INT) AS UpdatedCount, CAST(NULL AS INT) AS UnchangedCount,
               CAST(NULL AS INT) AS StagedForReviewCount,
               CAST(NULL AS INT) AS FailedCount,
               CAST(NULL AS SMALLINT) AS AttemptCount,
               CAST(NULL AS DATETIME2(3)) AS CreatedAtUtc,
               CAST(NULL AS DATETIME2(3)) AS StartedAtUtc,
               CAST(NULL AS DATETIME2(3)) AS CompletedAtUtc,
               CAST(NULL AS NVARCHAR(100)) AS LastErrorCode;

        SELECT CAST(NULL AS UNIQUEIDENTIFIER) AS ItemPublicId,
               CAST(NULL AS UNIQUEIDENTIFIER) AS RawObservationPublicId,
               CAST(NULL AS UNIQUEIDENTIFIER) AS OpportunityPublicId,
               CAST(NULL AS NVARCHAR(250)) AS ExternalId,
               CAST(NULL AS TINYINT) AS Status,
               CAST(NULL AS NVARCHAR(50)) AS OutcomeCode,
               CAST(NULL AS DATETIME2(3)) AS CreatedAtUtc,
               CAST(NULL AS DATETIME2(3)) AS CompletedAtUtc
        WHERE 1 = 0;

        SELECT CAST(NULL AS UNIQUEIDENTIFIER) AS ErrorPublicId,
               CAST(NULL AS UNIQUEIDENTIFIER) AS ItemPublicId,
               CAST(NULL AS NVARCHAR(50)) AS Stage,
               CAST(NULL AS NVARCHAR(100)) AS ErrorCode,
               CAST(NULL AS NVARCHAR(1000)) AS SanitizedMessage,
               CAST(NULL AS BIT) AS IsRetryable,
               CAST(NULL AS DATETIME2(3)) AS OccurredAtUtc
        WHERE 1 = 0;
        RETURN;
    END;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(N'found' AS NVARCHAR(50)) AS Code,
           runs.PublicId AS RunPublicId, runs.FundingSourceId,
           sources.Name AS SourceName, sources.ProviderCode,
           runs.TriggerType, runs.Status, runs.Keyword, runs.MaximumResults,
           runs.RetrievedCount, runs.CreatedCount, runs.UpdatedCount,
           runs.UnchangedCount, runs.StagedForReviewCount, runs.FailedCount,
           runs.AttemptCount, runs.CreatedAtUtc, runs.StartedAtUtc,
           runs.CompletedAtUtc, runs.LastErrorCode
    FROM dbo.FundingPlatform_ImportRuns AS runs
    INNER JOIN dbo.FundingPlatform_FundingSources AS sources
        ON sources.Id = runs.FundingSourceId
    WHERE runs.Id = @RunId;

    SELECT items.PublicId AS ItemPublicId,
           raw.PublicId AS RawObservationPublicId,
           opportunities.PublicId AS OpportunityPublicId,
           items.ExternalId, items.Status, items.OutcomeCode,
           items.CreatedAtUtc, items.CompletedAtUtc
    FROM dbo.FundingPlatform_ImportRunItems AS items
    INNER JOIN dbo.FundingPlatform_RawFundingOpportunities AS raw
        ON raw.Id = items.RawFundingOpportunityId
    LEFT JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
        ON opportunities.Id = items.FundingOpportunityId
    WHERE items.ImportRunId = @RunId
    ORDER BY items.Id;

    SELECT errors.PublicId AS ErrorPublicId,
           items.PublicId AS ItemPublicId,
           errors.Stage, errors.ErrorCode,
           errors.SanitizedMessage, errors.IsRetryable, errors.OccurredAtUtc
    FROM dbo.FundingPlatform_ImportErrors AS errors
    LEFT JOIN dbo.FundingPlatform_ImportRunItems AS items
        ON items.Id = errors.ImportRunItemId
    WHERE errors.ImportRunId = @RunId
    ORDER BY errors.OccurredAtUtc, errors.Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ImportRun_Scheduler_CreateDue
    @NowUtc DATETIME2(3),
    @BatchSize INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @NowUtc IS NULL THROW 51707, N'NowUtc is required.', 1;
    IF @BatchSize < 1 OR @BatchSize > 100
        THROW 51708, N'BatchSize must be between 1 and 100.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @StartedTransaction BIT = 0;
    DECLARE @DueSources TABLE
    (
        FundingSourceId INT NOT NULL PRIMARY KEY,
        ProviderCode NVARCHAR(100) NOT NULL,
        ScheduleSlotUtc DATETIME2(3) NOT NULL,
        ScheduleIntervalSeconds INT NOT NULL,
        Keyword NVARCHAR(100) NOT NULL,
        MaximumResults INT NOT NULL,
        MaxAttempts SMALLINT NOT NULL,
        RetryBaseDelaySeconds INT NOT NULL
    );
    DECLARE @CreatedRuns TABLE
    (
        RunId BIGINT NOT NULL PRIMARY KEY,
        RunPublicId UNIQUEIDENTIFIER NOT NULL,
        FundingSourceId INT NOT NULL
    );

    IF @InitialTransactionCount = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE SAVE TRANSACTION FP_ImportSchedule;

    BEGIN TRY
        INSERT INTO @DueSources
            (FundingSourceId, ProviderCode, ScheduleSlotUtc,
             ScheduleIntervalSeconds, Keyword, MaximumResults,
             MaxAttempts, RetryBaseDelaySeconds)
        SELECT TOP (@BatchSize) sources.Id, sources.ProviderCode, sources.NextRunAtUtc,
               sources.ScheduleIntervalSeconds,
               LEFT(COALESCE(NULLIF(LTRIM(RTRIM(JSON_VALUE
                    (sources.ConfigurationJson, N'$.defaultKeyword'))), N''), N'nonprofit'), 100),
               CASE WHEN TRY_CONVERT(INT, JSON_VALUE
                               (sources.ConfigurationJson, N'$.maximumResults')) BETWEEN 1 AND 25
                    THEN TRY_CONVERT(INT, JSON_VALUE
                               (sources.ConfigurationJson, N'$.maximumResults'))
                    ELSE 25 END,
               sources.MaxRunAttempts, sources.RetryBaseDelaySeconds
        FROM dbo.FundingPlatform_FundingSources AS sources
             WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
        WHERE sources.IsEnabled = 1
          AND sources.ComplianceStatus = 1
          AND sources.ProviderCode IS NOT NULL
          AND sources.ScheduleIntervalSeconds IS NOT NULL
          AND sources.NextRunAtUtc <= @NowUtc
        ORDER BY sources.NextRunAtUtc, sources.Id;

        UPDATE sources
        SET NextRunAtUtc = DATEADD(SECOND, due.ScheduleIntervalSeconds, @NowUtc),
            UpdatedAtUtc = @NowUtc
        FROM dbo.FundingPlatform_FundingSources AS sources
        INNER JOIN @DueSources AS due ON due.FundingSourceId = sources.Id;

        INSERT INTO dbo.FundingPlatform_ImportRuns
        (
            FundingSourceId, TriggerType, Status, Keyword, MaximumResults, CorrelationId,
            RequestedByUserId, ScheduleSlotUtc, IdempotencyKeyHash, RequestHash,
            AttemptCount, MaxAttempts, RetryBaseDelaySeconds, NextAttemptAtUtc,
            CreatedAtUtc, UpdatedAtUtc
        )
        OUTPUT inserted.Id, inserted.PublicId, inserted.FundingSourceId
            INTO @CreatedRuns (RunId, RunPublicId, FundingSourceId)
        SELECT due.FundingSourceId, 1, 0, due.Keyword, due.MaximumResults,
               CONCAT(N'schedule:', CONVERT(NVARCHAR(12), due.FundingSourceId), N':',
                      CONVERT(NVARCHAR(33), due.ScheduleSlotUtc, 126)),
               NULL, due.ScheduleSlotUtc, NULL, NULL, 0,
               due.MaxAttempts, due.RetryBaseDelaySeconds, @NowUtc, @NowUtc, @NowUtc
        FROM @DueSources AS due
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.FundingPlatform_ImportRuns AS existing WITH (UPDLOCK, HOLDLOCK)
            WHERE existing.FundingSourceId = due.FundingSourceId
              AND existing.ScheduleSlotUtc = due.ScheduleSlotUtc
              AND existing.TriggerType = 1
        );

        INSERT INTO dbo.FundingPlatform_OutboxMessages
            (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
             OccurredAtUtc, AvailableAtUtc)
        SELECT NEWID(), N'ImportRunRequested', N'ImportRun',
               CONVERT(NVARCHAR(100), created.RunPublicId),
               (SELECT created.RunPublicId AS runId, 1 AS [version]
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
               @NowUtc, @NowUtc
        FROM @CreatedRuns AS created;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ImportSchedule;
        THROW;
    END CATCH;

    SELECT created.RunPublicId, created.FundingSourceId, due.ProviderCode
    FROM @CreatedRuns AS created
    INNER JOIN @DueSources AS due ON due.FundingSourceId = created.FundingSourceId
    ORDER BY created.RunId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ImportRun_Claim
    @RunPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @LeaseSeconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @RunPublicId IS NULL OR @LeaseId IS NULL OR @NowUtc IS NULL
        THROW 51709, N'RunPublicId, LeaseId and NowUtc are required.', 1;
    IF @LeaseSeconds < 30 OR @LeaseSeconds > 3600
        THROW 51710, N'LeaseSeconds must be between 30 and 3600.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @StartedTransaction BIT = 0;
    DECLARE @RunId BIGINT, @FundingSourceId INT, @ProviderCode NVARCHAR(100);
    DECLARE @Keyword NVARCHAR(100), @MaximumResults INT, @AttemptCount SMALLINT;
    DECLARE @RetrievedCount INT;
    DECLARE @MaxAttempts SMALLINT, @Status TINYINT, @CurrentLeaseId UNIQUEIDENTIFIER;
    DECLARE @CurrentLeaseUntilUtc DATETIME2(3), @NextAttemptAtUtc DATETIME2(3);
    DECLARE @IsEnabled BIT, @ComplianceStatus TINYINT;
    DECLARE @LeaseUntilUtc DATETIME2(3), @Succeeded BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'not-found';

    IF @InitialTransactionCount = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE SAVE TRANSACTION FP_ImportClaim;

    BEGIN TRY
        SELECT @RunId = runs.Id, @FundingSourceId = runs.FundingSourceId,
               @Keyword = runs.Keyword, @MaximumResults = runs.MaximumResults,
               @AttemptCount = runs.AttemptCount, @MaxAttempts = runs.MaxAttempts,
               @RetrievedCount = runs.RetrievedCount,
               @Status = runs.Status, @CurrentLeaseId = runs.LeaseId,
               @CurrentLeaseUntilUtc = runs.LeaseUntilUtc,
               @NextAttemptAtUtc = runs.NextAttemptAtUtc,
               @ProviderCode = sources.ProviderCode, @IsEnabled = sources.IsEnabled,
               @ComplianceStatus = sources.ComplianceStatus
        FROM dbo.FundingPlatform_ImportRuns AS runs WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_FundingSources AS sources WITH (UPDLOCK, HOLDLOCK)
            ON sources.Id = runs.FundingSourceId
        WHERE runs.PublicId = @RunPublicId;

        IF @RunId IS NULL
            SET @Code = N'not-found';
        ELSE IF @Status = 1 AND @CurrentLeaseId = @LeaseId
                     AND @CurrentLeaseUntilUtc > @NowUtc
        BEGIN
            SET @Succeeded = 1;
            SET @Code = N'replayed';
            SET @LeaseUntilUtc = @CurrentLeaseUntilUtc;
        END
        ELSE IF @Status BETWEEN 2 AND 5
            SET @Code = N'already-terminal';
        ELSE IF @Status = 1 AND @CurrentLeaseUntilUtc > @NowUtc
            SET @Code = N'lease-active';
        ELSE IF @AttemptCount >= @MaxAttempts
        BEGIN
            DECLARE @ExhaustedItemCount INT;
            UPDATE dbo.FundingPlatform_ImportRunItems
            SET Status = 3, OutcomeCode = N'failed',
                CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc
            WHERE ImportRunId = @RunId AND Status IN (0, 1);
            SET @ExhaustedItemCount = @@ROWCOUNT;

            UPDATE dbo.FundingPlatform_ImportRuns
            SET Status = 4, LeaseId = NULL, LeaseUntilUtc = NULL,
                CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc,
                FailedCount = FailedCount + @ExhaustedItemCount,
                LastErrorCode = N'retries-exhausted',
                LastErrorMessage = N'The import run exhausted its retry limit.'
            WHERE Id = @RunId;

            INSERT INTO dbo.FundingPlatform_ImportErrors
                (ImportRunId, FundingSourceId, ImportRunItemId, Stage, ErrorCode,
                 SanitizedMessage, IsRetryable, OccurredAtUtc, CreatedAtUtc)
            VALUES (@RunId, @FundingSourceId, NULL, N'lease', N'retries-exhausted',
                    N'The import run exhausted its retry limit.', 0, @NowUtc, @NowUtc);

            SET @Status = 4;
            SET @Code = N'retries-exhausted';
        END
        ELSE IF @IsEnabled <> 1 OR @ProviderCode IS NULL
        BEGIN
            DECLARE @DisabledItemCount INT;
            UPDATE dbo.FundingPlatform_ImportRunItems
            SET Status = 3, OutcomeCode = N'failed',
                CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc
            WHERE ImportRunId = @RunId AND Status IN (0, 1);
            SET @DisabledItemCount = @@ROWCOUNT;
            UPDATE dbo.FundingPlatform_ImportRuns
            SET Status = 5, LeaseId = NULL, LeaseUntilUtc = NULL,
                CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc,
                FailedCount = FailedCount + @DisabledItemCount,
                LastErrorCode = N'source-disabled',
                LastErrorMessage = N'The funding source is no longer enabled.'
            WHERE Id = @RunId;
            INSERT INTO dbo.FundingPlatform_ImportErrors
                (ImportRunId, FundingSourceId, ImportRunItemId, Stage, ErrorCode,
                 SanitizedMessage, IsRetryable, OccurredAtUtc, CreatedAtUtc)
            VALUES (@RunId, @FundingSourceId, NULL, N'governance', N'source-disabled',
                    N'The funding source is no longer enabled.', 0, @NowUtc, @NowUtc);
            SET @Status = 5;
            SET @Code = N'source-disabled';
        END
        ELSE IF @ComplianceStatus <> 1
        BEGIN
            DECLARE @ComplianceItemCount INT;
            UPDATE dbo.FundingPlatform_ImportRunItems
            SET Status = 3, OutcomeCode = N'failed',
                CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc
            WHERE ImportRunId = @RunId AND Status IN (0, 1);
            SET @ComplianceItemCount = @@ROWCOUNT;
            UPDATE dbo.FundingPlatform_ImportRuns
            SET Status = 5, LeaseId = NULL, LeaseUntilUtc = NULL,
                CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc,
                FailedCount = FailedCount + @ComplianceItemCount,
                LastErrorCode = N'compliance-required',
                LastErrorMessage = N'The funding source is not approved for acquisition.'
            WHERE Id = @RunId;
            INSERT INTO dbo.FundingPlatform_ImportErrors
                (ImportRunId, FundingSourceId, ImportRunItemId, Stage, ErrorCode,
                 SanitizedMessage, IsRetryable, OccurredAtUtc, CreatedAtUtc)
            VALUES (@RunId, @FundingSourceId, NULL, N'governance', N'compliance-required',
                    N'The funding source is not approved for acquisition.', 0, @NowUtc, @NowUtc);
            SET @Status = 5;
            SET @Code = N'compliance-required';
        END
        ELSE IF @NextAttemptAtUtc > @NowUtc
            SET @Code = N'not-due';
        ELSE
        BEGIN
            IF @Status = 1 AND @CurrentLeaseUntilUtc <= @NowUtc
            BEGIN
                INSERT INTO dbo.FundingPlatform_ImportErrors
                    (ImportRunId, FundingSourceId, ImportRunItemId, Stage, ErrorCode,
                     SanitizedMessage, IsRetryable, OccurredAtUtc, CreatedAtUtc)
                VALUES (@RunId, @FundingSourceId, NULL, N'lease', N'lease-expired',
                        N'The previous worker lease expired and the run was reclaimed.',
                        1, @NowUtc, @NowUtc);
            END;

            SET @LeaseUntilUtc = DATEADD(SECOND, @LeaseSeconds, @NowUtc);
            UPDATE dbo.FundingPlatform_ImportRuns
            SET Status = 1, AttemptCount = AttemptCount + 1,
                LeaseId = @LeaseId, LeaseUntilUtc = @LeaseUntilUtc,
                StartedAtUtc = COALESCE(StartedAtUtc, @NowUtc),
                UpdatedAtUtc = @NowUtc
            WHERE Id = @RunId;
            SET @AttemptCount = @AttemptCount + 1;
            SET @Status = 1;
            SET @Succeeded = 1;
            SET @Code = N'claimed';
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ImportClaim;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           CASE WHEN @Code = N'not-found' THEN NULL ELSE @RunPublicId END AS RunPublicId,
           @FundingSourceId AS FundingSourceId, @ProviderCode AS ProviderCode,
           @Keyword AS Keyword, @MaximumResults AS MaximumResults,
           @AttemptCount AS AttemptCount, @RetrievedCount AS RetrievedCount,
           @LeaseUntilUtc AS LeaseUntilUtc;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ImportRun_RenewLease
    @RunPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @LeaseSeconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @RunPublicId IS NULL OR @LeaseId IS NULL OR @NowUtc IS NULL
        THROW 51735, N'RunPublicId, LeaseId and NowUtc are required.', 1;
    IF @LeaseSeconds < 30 OR @LeaseSeconds > 3600
        THROW 51736, N'LeaseSeconds must be between 30 and 3600.', 1;

    DECLARE @NewLeaseUntilUtc DATETIME2(3) = DATEADD(SECOND, @LeaseSeconds, @NowUtc);
    DECLARE @ActualLeaseUntilUtc DATETIME2(3), @Succeeded BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'not-found';

    UPDATE dbo.FundingPlatform_ImportRuns WITH (UPDLOCK)
    SET LeaseUntilUtc = CASE WHEN LeaseUntilUtc > @NewLeaseUntilUtc
                             THEN LeaseUntilUtc ELSE @NewLeaseUntilUtc END,
        UpdatedAtUtc = @NowUtc
    WHERE PublicId = @RunPublicId
      AND Status = 1
      AND LeaseId = @LeaseId
      AND LeaseUntilUtc > @NowUtc;

    IF @@ROWCOUNT = 1
    BEGIN
        SELECT @ActualLeaseUntilUtc = LeaseUntilUtc
        FROM dbo.FundingPlatform_ImportRuns
        WHERE PublicId = @RunPublicId;
        SET @Succeeded = 1;
        SET @Code = N'renewed';
    END
    ELSE
    BEGIN
        DECLARE @Status TINYINT, @CurrentLeaseId UNIQUEIDENTIFIER;
        DECLARE @CurrentLeaseUntilUtc DATETIME2(3);
        SELECT @Status = Status, @CurrentLeaseId = LeaseId,
               @CurrentLeaseUntilUtc = LeaseUntilUtc
        FROM dbo.FundingPlatform_ImportRuns
        WHERE PublicId = @RunPublicId;
        IF @Status IS NULL SET @Code = N'not-found';
        ELSE IF @Status <> 1 SET @Code = N'invalid-state';
        ELSE IF @CurrentLeaseId <> @LeaseId OR @CurrentLeaseUntilUtc <= @NowUtc
            SET @Code = N'stale-lease';
    END;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @ActualLeaseUntilUtc AS LeaseUntilUtc;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ImportRunOutbox_Claim
    @LeaseOwner NVARCHAR(100),
    @BatchSize INT,
    @LeaseSeconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NULLIF(LTRIM(RTRIM(@LeaseOwner)), N'') IS NULL
        THROW 51711, N'LeaseOwner is required.', 1;
    IF @BatchSize < 1 OR @BatchSize > 100
        THROW 51712, N'BatchSize must be between 1 and 100.', 1;
    IF @LeaseSeconds < 5 OR @LeaseSeconds > 3600
        THROW 51713, N'LeaseSeconds must be between 5 and 3600.', 1;

    ;WITH Claimable AS
    (
        SELECT TOP (@BatchSize) *
        FROM dbo.FundingPlatform_OutboxMessages
             WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
        WHERE MessageType = N'ImportRunRequested'
          AND DispatchedAtUtc IS NULL
          AND AvailableAtUtc <= @NowUtc
          AND (LeaseUntilUtc IS NULL OR LeaseUntilUtc <= @NowUtc)
        ORDER BY AvailableAtUtc, Id
    )
    UPDATE Claimable
    SET LeaseOwner = @LeaseOwner,
        LeaseUntilUtc = DATEADD(SECOND, @LeaseSeconds, @NowUtc),
        AttemptCount = AttemptCount + 1
    OUTPUT inserted.Id, inserted.MessageId, inserted.MessageType,
           inserted.AggregateType, inserted.AggregateId, inserted.PayloadJson,
           inserted.OccurredAtUtc, inserted.AttemptCount, inserted.LeaseUntilUtc;
END;
GO

/* Repairs the dispatch gap after a queue delivery was abandoned or poisoned.
   Five 31-minute visibility windows plus margin produce a conservative
   180-minute redispatch delay. A still-pending request is never duplicated. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ImportRun_RequeueStranded
    @NowUtc DATETIME2(3),
    @BatchSize INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @NowUtc IS NULL THROW 51732, N'NowUtc is required.', 1;
    IF @BatchSize < 1 OR @BatchSize > 100
        THROW 51733, N'BatchSize must be between 1 and 100.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @StartedTransaction BIT = 0;
    DECLARE @Candidates TABLE
    (
        RunId BIGINT NOT NULL PRIMARY KEY,
        RunPublicId UNIQUEIDENTIFIER NOT NULL,
        FundingSourceId INT NOT NULL,
        ProviderCode NVARCHAR(100) NULL,
        IsEnabled BIT NOT NULL,
        ComplianceStatus TINYINT NOT NULL
    );
    DECLARE @Requeued TABLE
    (
        RunId BIGINT NOT NULL PRIMARY KEY,
        RunPublicId UNIQUEIDENTIFIER NOT NULL,
        FundingSourceId INT NOT NULL,
        ProviderCode NVARCHAR(100) NOT NULL
    );

    IF @InitialTransactionCount = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE SAVE TRANSACTION FP_ImportWatchdog;

    BEGIN TRY
        INSERT INTO @Candidates
            (RunId, RunPublicId, FundingSourceId, ProviderCode,
             IsEnabled, ComplianceStatus)
        SELECT TOP (@BatchSize) runs.Id, runs.PublicId,
               runs.FundingSourceId, sources.ProviderCode,
               sources.IsEnabled, sources.ComplianceStatus
        FROM dbo.FundingPlatform_ImportRuns AS runs
             WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
        INNER JOIN dbo.FundingPlatform_FundingSources AS sources WITH (HOLDLOCK)
            ON sources.Id = runs.FundingSourceId
        WHERE ((runs.Status = 0 AND runs.NextAttemptAtUtc <= @NowUtc)
               OR (runs.Status = 1 AND runs.LeaseUntilUtc <= @NowUtc))
          AND NOT EXISTS
          (
              SELECT 1
              FROM dbo.FundingPlatform_OutboxMessages AS outbox WITH (UPDLOCK, HOLDLOCK)
              WHERE outbox.MessageType = N'ImportRunRequested'
                AND outbox.AggregateType = N'ImportRun'
                AND outbox.AggregateId = CONVERT(NVARCHAR(100), runs.PublicId)
                AND outbox.DispatchedAtUtc IS NULL
          )
          AND COALESCE
              (
                  (SELECT MAX(previous.DispatchedAtUtc)
                   FROM dbo.FundingPlatform_OutboxMessages AS previous WITH (HOLDLOCK)
                   WHERE previous.MessageType = N'ImportRunRequested'
                     AND previous.AggregateType = N'ImportRun'
                     AND previous.AggregateId = CONVERT(NVARCHAR(100), runs.PublicId)),
                  CONVERT(DATETIME2(3), N'1900-01-01T00:00:00')
              ) <= DATEADD(MINUTE, -180, @NowUtc)
        ORDER BY CASE WHEN runs.Status = 1 THEN runs.LeaseUntilUtc
                      ELSE runs.NextAttemptAtUtc END,
                 runs.Id;

        DECLARE @CanceledItems TABLE (RunId BIGINT NOT NULL);
        UPDATE items
        SET Status = 3, OutcomeCode = N'failed',
            CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc
        OUTPUT inserted.ImportRunId INTO @CanceledItems (RunId)
        FROM dbo.FundingPlatform_ImportRunItems AS items
        INNER JOIN @Candidates AS candidates
            ON candidates.RunId = items.ImportRunId
        WHERE (candidates.IsEnabled <> 1
               OR candidates.ComplianceStatus <> 1
               OR candidates.ProviderCode IS NULL)
          AND items.Status IN (0, 1);

        UPDATE runs
        SET Status = 5, LeaseId = NULL, LeaseUntilUtc = NULL,
            CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc,
            FailedCount = FailedCount
                + CONVERT(INT,
                    (SELECT COUNT_BIG(1) FROM @CanceledItems AS canceledItems
                     WHERE canceledItems.RunId = runs.Id)),
            LastErrorCode = CASE WHEN candidates.IsEnabled <> 1
                                      OR candidates.ProviderCode IS NULL
                                 THEN N'source-disabled'
                                 ELSE N'compliance-required' END,
            LastErrorMessage = CASE WHEN candidates.IsEnabled <> 1
                                         OR candidates.ProviderCode IS NULL
                                    THEN N'The funding source is no longer enabled.'
                                    ELSE N'The funding source is not approved for acquisition.' END
        FROM dbo.FundingPlatform_ImportRuns AS runs
        INNER JOIN @Candidates AS candidates ON candidates.RunId = runs.Id
        WHERE candidates.IsEnabled <> 1
           OR candidates.ComplianceStatus <> 1
           OR candidates.ProviderCode IS NULL;

        INSERT INTO dbo.FundingPlatform_ImportErrors
            (ImportRunId, FundingSourceId, ImportRunItemId, Stage, ErrorCode,
             SanitizedMessage, IsRetryable, OccurredAtUtc, CreatedAtUtc)
        SELECT candidates.RunId, candidates.FundingSourceId, NULL, N'governance',
               CASE WHEN candidates.IsEnabled <> 1 OR candidates.ProviderCode IS NULL
                    THEN N'source-disabled' ELSE N'compliance-required' END,
               CASE WHEN candidates.IsEnabled <> 1 OR candidates.ProviderCode IS NULL
                    THEN N'The funding source is no longer enabled.'
                    ELSE N'The funding source is not approved for acquisition.' END,
               0, @NowUtc, @NowUtc
        FROM @Candidates AS candidates
        WHERE candidates.IsEnabled <> 1
           OR candidates.ComplianceStatus <> 1
           OR candidates.ProviderCode IS NULL;

        INSERT INTO @Requeued (RunId, RunPublicId, FundingSourceId, ProviderCode)
        SELECT RunId, RunPublicId, FundingSourceId, ProviderCode
        FROM @Candidates
        WHERE IsEnabled = 1 AND ComplianceStatus = 1 AND ProviderCode IS NOT NULL;

        INSERT INTO dbo.FundingPlatform_OutboxMessages
            (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
             OccurredAtUtc, AvailableAtUtc)
        SELECT NEWID(), N'ImportRunRequested', N'ImportRun',
               CONVERT(NVARCHAR(100), requeued.RunPublicId),
               (SELECT requeued.RunPublicId AS runId, 1 AS [version]
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
               @NowUtc, @NowUtc
        FROM @Requeued AS requeued;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ImportWatchdog;
        THROW;
    END CATCH;

    SELECT RunPublicId, FundingSourceId, ProviderCode
    FROM @Requeued
    ORDER BY RunId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_RawFundingOpportunity_Record
    @RunPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @ExternalId NVARCHAR(250),
    @SourceUrl NVARCHAR(2048),
    @RetrievedAtUtc DATETIME2(3),
    @MimeType NVARCHAR(100),
    @RawContent NVARCHAR(MAX),
    @ContentHash BINARY(32),
    @SourceItemKeyHash BINARY(32),
    @NormalizedSnapshotVersion SMALLINT,
    @NormalizedSnapshotJson NVARCHAR(MAX),
    @NormalizedSnapshotHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ExternalId = LTRIM(RTRIM(@ExternalId));
    SET @SourceUrl = LTRIM(RTRIM(@SourceUrl));
    SET @MimeType = LOWER(LTRIM(RTRIM(@MimeType)));
    IF NULLIF(@ExternalId, N'') IS NULL OR LEN(@ExternalId) > 250
        THROW 51714, N'ExternalId is required and cannot exceed 250 characters.', 1;
    IF NULLIF(@SourceUrl, N'') IS NULL OR LEN(@SourceUrl) > 2048
        THROW 51715, N'SourceUrl is required and cannot exceed 2048 characters.', 1;
    IF NULLIF(@MimeType, N'') IS NULL OR LEN(@MimeType) > 100
        THROW 51716, N'MimeType is required and cannot exceed 100 characters.', 1;
    IF @RawContent IS NULL OR DATALENGTH(@RawContent) NOT BETWEEN 2 AND 4194304
        THROW 51717, N'RawContent size is outside the allowed range.', 1;
    IF @MimeType = N'application/json' AND ISJSON(@RawContent) <> 1
        THROW 51718, N'RawContent must be valid JSON for application/json.', 1;
    IF @ContentHash IS NULL OR @SourceItemKeyHash IS NULL
        THROW 51719, N'Content and source-item hashes are required.', 1;
    IF HASHBYTES
       ('SHA2_256',
        CONVERT(VARBINARY(MAX),
                CONVERT(VARCHAR(MAX),
                        @RawContent COLLATE Latin1_General_100_BIN2_UTF8)))
       <> @ContentHash
        THROW 51744, N'Raw content hash does not match its content.', 1;
    IF @NormalizedSnapshotVersion <> 1
       OR @NormalizedSnapshotJson IS NULL
       OR ISJSON(@NormalizedSnapshotJson) <> 1
       OR COALESCE(TRY_CONVERT
          (SMALLINT, JSON_VALUE(@NormalizedSnapshotJson, N'$.schemaVersion')), -1)
          <> @NormalizedSnapshotVersion
       OR COALESCE(LEFT(LTRIM(JSON_QUERY
          (@NormalizedSnapshotJson, N'$.opportunity')), 1), N'') <> N'{'
       OR DATALENGTH
          (CONVERT(VARCHAR(MAX),
                   @NormalizedSnapshotJson COLLATE Latin1_General_100_BIN2_UTF8))
          NOT BETWEEN 2 AND 262144
       OR @NormalizedSnapshotHash IS NULL
        THROW 51737, N'Normalized snapshot is invalid or outside the allowed range.', 1;
    IF HASHBYTES
       ('SHA2_256',
        CONVERT(VARBINARY(MAX),
                CONVERT(VARCHAR(MAX),
                        @NormalizedSnapshotJson COLLATE Latin1_General_100_BIN2_UTF8)))
       <> @NormalizedSnapshotHash
        THROW 51738, N'Normalized snapshot hash does not match its content.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @StartedTransaction BIT = 0;
    DECLARE @RunId BIGINT, @FundingSourceId INT, @RunStatus TINYINT;
    DECLARE @RetrievedCount INT, @MaximumResults INT;
    DECLARE @CurrentLeaseId UNIQUEIDENTIFIER, @LeaseUntilUtc DATETIME2(3);
    DECLARE @RawId BIGINT, @RawPublicId UNIQUEIDENTIFIER;
    DECLARE @ExistingRawHash BINARY(32), @ItemId BIGINT;
    DECLARE @ItemPublicId UNIQUEIDENTIFIER, @ItemStatus TINYINT;
    DECLARE @ExistingSnapshotVersion SMALLINT, @ExistingSnapshotHash BINARY(32);
    DECLARE @WasRawReplay BIT = 0, @AlreadyCompleted BIT = 0;
    DECLARE @Succeeded BIT = 0, @Code NVARCHAR(50) = N'not-found';
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();

    IF @InitialTransactionCount = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE SAVE TRANSACTION FP_RawRecord;

    BEGIN TRY
        SELECT @RunId = Id, @FundingSourceId = FundingSourceId, @RunStatus = Status,
               @CurrentLeaseId = LeaseId, @LeaseUntilUtc = LeaseUntilUtc,
               @RetrievedCount = RetrievedCount, @MaximumResults = MaximumResults
        FROM dbo.FundingPlatform_ImportRuns WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @RunPublicId;

        IF @RunId IS NULL
            SET @Code = N'not-found';
        ELSE IF @RunStatus <> 1
            SET @Code = N'invalid-state';
        ELSE IF @CurrentLeaseId <> @LeaseId OR @LeaseUntilUtc <= @NowUtc
            SET @Code = N'stale-lease';
        ELSE
        BEGIN
            SELECT @ItemId = items.Id, @ItemPublicId = items.PublicId,
                   @ItemStatus = items.Status, @RawId = raw.Id,
                   @RawPublicId = raw.PublicId, @ExistingRawHash = raw.ContentHash,
                   @ExistingSnapshotVersion = items.NormalizedSnapshotVersion,
                   @ExistingSnapshotHash = items.NormalizedSnapshotHash
            FROM dbo.FundingPlatform_ImportRunItems AS items WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.FundingPlatform_RawFundingOpportunities AS raw WITH (HOLDLOCK)
                ON raw.Id = items.RawFundingOpportunityId
            WHERE items.ImportRunId = @RunId
              AND items.SourceItemKeyHash = @SourceItemKeyHash;

            IF @ItemId IS NOT NULL
            BEGIN
                /* First observation wins. Once terminal, a late provider change
                   must not turn an already applied item into a conflict. */
                IF @ItemStatus IN (2, 3)
                BEGIN
                    SET @Succeeded = 1;
                    SET @Code = N'replayed';
                    SET @WasRawReplay = 1;
                    SET @AlreadyCompleted = 1;
                END
                ELSE IF @ExistingRawHash <> @ContentHash
                   OR @ExistingSnapshotVersion <> @NormalizedSnapshotVersion
                   OR @ExistingSnapshotHash <> @NormalizedSnapshotHash
                BEGIN
                    SET @ItemPublicId = NULL;
                    SET @RawPublicId = NULL;
                    SET @Code = N'item-conflict';
                END
                ELSE
                BEGIN
                    SET @Succeeded = 1;
                    SET @Code = N'replayed';
                    SET @WasRawReplay = 1;
                    SET @AlreadyCompleted = 0;
                END;
            END
            ELSE IF @RetrievedCount >= @MaximumResults
                SET @Code = N'maximum-results-reached';
            ELSE
            BEGIN
                SELECT @RawId = Id, @RawPublicId = PublicId
                FROM dbo.FundingPlatform_RawFundingOpportunities WITH (UPDLOCK, HOLDLOCK)
                WHERE FundingSourceId = @FundingSourceId
                  AND SourceItemKeyHash = @SourceItemKeyHash
                  AND ContentHash = @ContentHash;

                IF @RawId IS NULL
                BEGIN
                    DECLARE @InsertedRaw TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER);
                    INSERT INTO dbo.FundingPlatform_RawFundingOpportunities
                        (FundingSourceId, ExternalId, SourceItemKeyHash, ContentHash,
                         SourceUrl, MimeType, RawContent, RetrievedAtUtc, CreatedAtUtc)
                    OUTPUT inserted.Id, inserted.PublicId
                        INTO @InsertedRaw (Id, PublicId)
                    VALUES (@FundingSourceId, @ExternalId, @SourceItemKeyHash, @ContentHash,
                            @SourceUrl, @MimeType, @RawContent, @RetrievedAtUtc, @NowUtc);
                    SELECT @RawId = Id, @RawPublicId = PublicId FROM @InsertedRaw;
                END
                ELSE SET @WasRawReplay = 1;

                DECLARE @InsertedItem TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER);
                INSERT INTO dbo.FundingPlatform_ImportRunItems
                    (ImportRunId, FundingSourceId, RawFundingOpportunityId,
                     FundingOpportunityId, ExternalId, SourceItemKeyHash,
                     NormalizedSnapshotVersion, NormalizedSnapshotJson,
                     NormalizedSnapshotHash, Status, OutcomeCode,
                     CreatedAtUtc, CompletedAtUtc, UpdatedAtUtc)
                OUTPUT inserted.Id, inserted.PublicId INTO @InsertedItem (Id, PublicId)
                VALUES (@RunId, @FundingSourceId, @RawId, NULL, @ExternalId,
                        @SourceItemKeyHash, @NormalizedSnapshotVersion,
                        @NormalizedSnapshotJson, @NormalizedSnapshotHash,
                        1, NULL, @NowUtc, NULL, @NowUtc);
                SELECT @ItemId = Id, @ItemPublicId = PublicId FROM @InsertedItem;

                UPDATE dbo.FundingPlatform_ImportRuns
                SET RetrievedCount = RetrievedCount + 1, UpdatedAtUtc = @NowUtc
                WHERE Id = @RunId;

                SET @Succeeded = 1;
                SET @Code = N'recorded';
            END;
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_RawRecord;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @ItemPublicId AS ItemPublicId,
           @RawPublicId AS RawObservationPublicId,
           @WasRawReplay AS WasRawReplay,
           @AlreadyCompleted AS AlreadyCompleted;
END;
GO

/* Rehydrates normalized work after a worker/provider crash without exposing the
   immutable raw payload. The active lease is the authorization boundary. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ImportRunItem_ListPending
    @RunPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @BatchSize INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @RunPublicId IS NULL OR @LeaseId IS NULL OR @NowUtc IS NULL
        THROW 51739, N'RunPublicId, LeaseId and NowUtc are required.', 1;
    IF @BatchSize NOT BETWEEN 1 AND 25
        THROW 51740, N'BatchSize must be between 1 and 25.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @StartedTransaction BIT = 0;
    DECLARE @RunId BIGINT, @RunStatus TINYINT;
    DECLARE @CurrentLeaseId UNIQUEIDENTIFIER, @LeaseUntilUtc DATETIME2(3);

    IF @InitialTransactionCount = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE SAVE TRANSACTION FP_ListPendingItems;

    BEGIN TRY
        SELECT @RunId = Id, @RunStatus = Status,
               @CurrentLeaseId = LeaseId, @LeaseUntilUtc = LeaseUntilUtc
        FROM dbo.FundingPlatform_ImportRuns WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @RunPublicId;

        IF @RunId IS NULL
            THROW 51741, N'Import run was not found.', 1;
        IF @RunStatus <> 1
            THROW 51742, N'Import run is not running.', 1;
        IF @CurrentLeaseId <> @LeaseId OR @LeaseUntilUtc <= @NowUtc
            THROW 51743, N'Import run lease is stale.', 1;

        SELECT TOP (@BatchSize)
               items.PublicId AS ItemPublicId,
               raw.PublicId AS RawObservationPublicId,
               items.ExternalId,
               items.NormalizedSnapshotVersion,
               items.NormalizedSnapshotJson,
               items.NormalizedSnapshotHash
        FROM dbo.FundingPlatform_ImportRunItems AS items
        INNER JOIN dbo.FundingPlatform_RawFundingOpportunities AS raw
            ON raw.Id = items.RawFundingOpportunityId
           AND raw.FundingSourceId = items.FundingSourceId
        WHERE items.ImportRunId = @RunId
          AND items.Status IN (0, 1)
        ORDER BY items.Id;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ListPendingItems;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ImportRunItem_Complete
    @RunPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @ItemPublicId UNIQUEIDENTIFIER,
    @OutcomeCode NVARCHAR(50),
    @OpportunityPublicId UNIQUEIDENTIFIER = NULL,
    @CompletedAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @OutcomeCode = LOWER(LTRIM(RTRIM(@OutcomeCode)));
    IF @OutcomeCode NOT IN (N'created', N'updated', N'unchanged', N'staged-for-review')
        THROW 51720, N'OutcomeCode is invalid.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @StartedTransaction BIT = 0;
    DECLARE @RunId BIGINT, @FundingSourceId INT, @RunStatus TINYINT;
    DECLARE @CurrentLeaseId UNIQUEIDENTIFIER, @LeaseUntilUtc DATETIME2(3);
    DECLARE @ItemId BIGINT, @ItemRunId BIGINT, @ItemStatus TINYINT;
    DECLARE @ItemSourceUrl NVARCHAR(2048);
    DECLARE @ItemCanonicalUrlHash BINARY(32);
    DECLARE @CurrentOutcomeCode NVARCHAR(50), @CurrentOpportunityId BIGINT;
    DECLARE @OpportunityId BIGINT, @OpportunityMatchCount BIGINT;
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();

    IF @InitialTransactionCount = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE SAVE TRANSACTION FP_ItemComplete;

    BEGIN TRY
        SELECT @RunId = Id, @FundingSourceId = FundingSourceId, @RunStatus = Status,
               @CurrentLeaseId = LeaseId, @LeaseUntilUtc = LeaseUntilUtc
        FROM dbo.FundingPlatform_ImportRuns WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @RunPublicId;

        IF @RunId IS NULL
            SET @Code = N'not-found';
        ELSE IF @RunStatus <> 1
            SET @Code = N'invalid-state';
        ELSE IF @CurrentLeaseId <> @LeaseId OR @LeaseUntilUtc <= @NowUtc
            SET @Code = N'stale-lease';
        ELSE
        BEGIN
            SELECT @ItemId = items.Id, @ItemRunId = items.ImportRunId,
                   @ItemStatus = items.Status,
                   @ItemSourceUrl = raw.SourceUrl,
                   @ItemCanonicalUrlHash = HASHBYTES
                       ('SHA2_256',
                        CONVERT(VARBINARY(MAX),
                                CONVERT(VARCHAR(MAX),
                                        raw.SourceUrl COLLATE Latin1_General_100_BIN2_UTF8))),
                   @CurrentOutcomeCode = items.OutcomeCode,
                   @CurrentOpportunityId = items.FundingOpportunityId
            FROM dbo.FundingPlatform_ImportRunItems AS items WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.FundingPlatform_RawFundingOpportunities AS raw WITH (HOLDLOCK)
                ON raw.Id = items.RawFundingOpportunityId
            WHERE items.PublicId = @ItemPublicId;

            IF @ItemId IS NULL OR @ItemRunId <> @RunId
                SET @Code = N'item-not-found';
            ELSE
            BEGIN
                SELECT @OpportunityId = MIN(links.FundingOpportunityId),
                       @OpportunityMatchCount = COUNT_BIG(DISTINCT links.FundingOpportunityId)
                FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links WITH (HOLDLOCK)
                INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities WITH (HOLDLOCK)
                    ON opportunities.Id = links.FundingOpportunityId
                WHERE links.FundingSourceId = @FundingSourceId
                  /* Raw ExternalId is the Grants.gov internal hit id while the
                     source link ExternalId is its public reference number. */
                  AND links.SourceUrl = @ItemSourceUrl
                  AND links.CanonicalUrlHash = @ItemCanonicalUrlHash
                  AND (@OpportunityPublicId IS NULL
                       OR opportunities.PublicId = @OpportunityPublicId);

                IF ISNULL(@OpportunityMatchCount, 0) = 0
                    SET @Code = N'opportunity-not-found';
                ELSE IF @OpportunityMatchCount > 1
                    SET @Code = N'source-link-conflict';
                ELSE IF @ItemStatus = 2
                BEGIN
                    IF @CurrentOutcomeCode = @OutcomeCode
                       AND ISNULL(@CurrentOpportunityId, -1) = ISNULL(@OpportunityId, -1)
                    BEGIN
                        SET @Succeeded = 1;
                        SET @WasReplay = 1;
                        SET @Code = N'replayed';
                    END
                    ELSE SET @Code = N'item-conflict';
                END
                ELSE IF @ItemStatus = 3
                    SET @Code = N'already-terminal';
                ELSE
                BEGIN
                    UPDATE dbo.FundingPlatform_ImportRunItems
                    SET FundingOpportunityId = @OpportunityId, Status = 2,
                        OutcomeCode = @OutcomeCode, CompletedAtUtc = @CompletedAtUtc,
                        UpdatedAtUtc = @NowUtc
                    WHERE Id = @ItemId;

                    UPDATE dbo.FundingPlatform_ImportRuns
                    SET CreatedCount = CreatedCount
                            + CASE WHEN @OutcomeCode = N'created' THEN 1 ELSE 0 END,
                        UpdatedCount = UpdatedCount
                            + CASE WHEN @OutcomeCode = N'updated' THEN 1 ELSE 0 END,
                        UnchangedCount = UnchangedCount
                            + CASE WHEN @OutcomeCode = N'unchanged' THEN 1 ELSE 0 END,
                        StagedForReviewCount = StagedForReviewCount
                            + CASE WHEN @OutcomeCode = N'staged-for-review' THEN 1 ELSE 0 END,
                        UpdatedAtUtc = @NowUtc
                    WHERE Id = @RunId;

                    SET @Succeeded = 1;
                    SET @Code = N'completed';
                END;
            END;
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ItemComplete;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ImportRunItem_Fail
    @RunPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @ItemPublicId UNIQUEIDENTIFIER,
    @Stage NVARCHAR(50),
    @ErrorCode NVARCHAR(100),
    @SanitizedMessage NVARCHAR(1000),
    @IsRetryable BIT,
    @OccurredAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Stage = LOWER(LTRIM(RTRIM(@Stage)));
    SET @ErrorCode = LOWER(LTRIM(RTRIM(@ErrorCode)));
    SET @SanitizedMessage = LTRIM(RTRIM(@SanitizedMessage));
    IF NULLIF(@Stage, N'') IS NULL OR LEN(@Stage) > 50
       OR NULLIF(@ErrorCode, N'') IS NULL OR LEN(@ErrorCode) > 100
       OR NULLIF(@SanitizedMessage, N'') IS NULL OR LEN(@SanitizedMessage) > 1000
       OR CHARINDEX(CHAR(10), @Stage + @ErrorCode + @SanitizedMessage) > 0
       OR CHARINDEX(CHAR(13), @Stage + @ErrorCode + @SanitizedMessage) > 0
        THROW 51721, N'Error context must be present, bounded and single-line.', 1;
    IF @IsRetryable = 1
        THROW 51734, N'Retryable item failures must be retried at run scope.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @StartedTransaction BIT = 0;
    DECLARE @RunId BIGINT, @FundingSourceId INT, @RunStatus TINYINT;
    DECLARE @CurrentLeaseId UNIQUEIDENTIFIER, @LeaseUntilUtc DATETIME2(3);
    DECLARE @ItemId BIGINT, @ItemRunId BIGINT, @ItemStatus TINYINT;
    DECLARE @ErrorPublicId UNIQUEIDENTIFIER, @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();

    IF @InitialTransactionCount = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE SAVE TRANSACTION FP_ItemFail;

    BEGIN TRY
        SELECT @RunId = Id, @FundingSourceId = FundingSourceId, @RunStatus = Status,
               @CurrentLeaseId = LeaseId, @LeaseUntilUtc = LeaseUntilUtc
        FROM dbo.FundingPlatform_ImportRuns WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @RunPublicId;

        IF @RunId IS NULL
            SET @Code = N'not-found';
        ELSE IF @RunStatus <> 1
            SET @Code = N'invalid-state';
        ELSE IF @CurrentLeaseId <> @LeaseId OR @LeaseUntilUtc <= @NowUtc
            SET @Code = N'stale-lease';
        ELSE
        BEGIN
            SELECT @ItemId = Id, @ItemRunId = ImportRunId, @ItemStatus = Status
            FROM dbo.FundingPlatform_ImportRunItems WITH (UPDLOCK, HOLDLOCK)
            WHERE PublicId = @ItemPublicId;

            IF @ItemId IS NULL OR @ItemRunId <> @RunId
                SET @Code = N'item-not-found';
            ELSE IF @ItemStatus = 2
                SET @Code = N'already-terminal';
            ELSE IF @ItemStatus = 3
            BEGIN
                SELECT TOP (1) @ErrorPublicId = PublicId
                FROM dbo.FundingPlatform_ImportErrors
                WHERE ImportRunItemId = @ItemId
                  AND Stage = @Stage AND ErrorCode = @ErrorCode
                ORDER BY Id DESC;
                IF @ErrorPublicId IS NOT NULL
                BEGIN
                    SET @Succeeded = 1;
                    SET @WasReplay = 1;
                    SET @Code = N'replayed';
                END
                ELSE SET @Code = N'item-conflict';
            END
            ELSE
            BEGIN
                DECLARE @InsertedError TABLE (PublicId UNIQUEIDENTIFIER);
                INSERT INTO dbo.FundingPlatform_ImportErrors
                    (ImportRunId, FundingSourceId, ImportRunItemId, Stage, ErrorCode,
                     SanitizedMessage, IsRetryable, OccurredAtUtc, CreatedAtUtc)
                OUTPUT inserted.PublicId INTO @InsertedError (PublicId)
                VALUES (@RunId, @FundingSourceId, @ItemId, @Stage, @ErrorCode,
                        @SanitizedMessage, @IsRetryable, @OccurredAtUtc, @NowUtc);
                SELECT @ErrorPublicId = PublicId FROM @InsertedError;

                UPDATE dbo.FundingPlatform_ImportRunItems
                SET Status = 3, OutcomeCode = N'failed',
                    CompletedAtUtc = @OccurredAtUtc, UpdatedAtUtc = @NowUtc
                WHERE Id = @ItemId;
                UPDATE dbo.FundingPlatform_ImportRuns
                SET FailedCount = FailedCount + 1, UpdatedAtUtc = @NowUtc
                WHERE Id = @RunId;

                SET @Succeeded = 1;
                SET @Code = N'failed';
            END;
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ItemFail;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @ErrorPublicId AS ErrorPublicId, @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ImportRun_Complete
    @RunPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @CompletedAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @StartedTransaction BIT = 0;
    DECLARE @RunId BIGINT, @FundingSourceId INT, @Status TINYINT;
    DECLARE @CurrentLeaseId UNIQUEIDENTIFIER, @LeaseUntilUtc DATETIME2(3);
    DECLARE @RetrievedCount INT, @FailedCount INT, @SuccessfulCount INT;
    DECLARE @CurrentLastErrorCode NVARCHAR(100);
    DECLARE @Succeeded BIT = 0, @Code NVARCHAR(50) = N'not-found';
    DECLARE @WasReplay BIT = 0, @NowUtc DATETIME2(3) = SYSUTCDATETIME();

    IF @InitialTransactionCount = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE SAVE TRANSACTION FP_RunComplete;

    BEGIN TRY
        SELECT @RunId = Id, @FundingSourceId = FundingSourceId, @Status = Status,
               @CurrentLeaseId = LeaseId, @LeaseUntilUtc = LeaseUntilUtc,
               @RetrievedCount = RetrievedCount, @FailedCount = FailedCount,
               @SuccessfulCount = CreatedCount + UpdatedCount + UnchangedCount
                                  + StagedForReviewCount,
               @CurrentLastErrorCode = LastErrorCode
        FROM dbo.FundingPlatform_ImportRuns WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @RunPublicId;

        IF @RunId IS NULL
            SET @Code = N'not-found';
        ELSE IF @Status IN (2, 3)
                OR (@Status = 4 AND @CurrentLastErrorCode = N'all-items-failed')
        BEGIN
            SET @Succeeded = 1;
            SET @WasReplay = 1;
            SET @Code = N'replayed';
        END
        ELSE IF @Status <> 1
            SET @Code = N'invalid-state';
        ELSE IF @CurrentLeaseId <> @LeaseId OR @LeaseUntilUtc <= @NowUtc
            SET @Code = N'stale-lease';
        ELSE IF EXISTS
                (SELECT 1 FROM dbo.FundingPlatform_ImportRunItems WITH (UPDLOCK, HOLDLOCK)
                 WHERE ImportRunId = @RunId AND Status IN (0, 1))
            SET @Code = N'items-pending';
        ELSE IF @RetrievedCount <>
                (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_ImportRunItems
                 WHERE ImportRunId = @RunId)
            SET @Code = N'counter-conflict';
        ELSE
        BEGIN
            SET @Status = CASE WHEN @RetrievedCount > 0 AND @SuccessfulCount = 0
                                    AND @FailedCount = @RetrievedCount THEN 4
                               WHEN @FailedCount > 0 THEN 3 ELSE 2 END;
            UPDATE dbo.FundingPlatform_ImportRuns
            SET Status = @Status, LeaseId = NULL, LeaseUntilUtc = NULL,
                CompletedAtUtc = @CompletedAtUtc, UpdatedAtUtc = @NowUtc,
                LastErrorCode = CASE WHEN @Status = 4 THEN N'all-items-failed'
                                     WHEN @Status = 3 THEN N'item-errors'
                                     ELSE NULL END,
                LastErrorMessage = CASE
                    WHEN @Status = 4 THEN N'All retrieved items failed processing.'
                    WHEN @Status = 3 THEN N'One or more retrieved items failed processing.'
                    ELSE NULL END
            WHERE Id = @RunId;

            IF @SuccessfulCount > 0 OR @RetrievedCount = 0
                UPDATE dbo.FundingPlatform_FundingSources
                SET LastSuccessfulRunAtUtc = @CompletedAtUtc,
                    ConsecutiveFailureCount = 0, UpdatedAtUtc = @NowUtc
                WHERE Id = @FundingSourceId;
            ELSE
                UPDATE dbo.FundingPlatform_FundingSources
                SET ConsecutiveFailureCount = ConsecutiveFailureCount + 1,
                    UpdatedAtUtc = @NowUtc
                WHERE Id = @FundingSourceId;

            SET @Succeeded = 1;
            SET @Code = CASE WHEN @Status = 4 THEN N'failed'
                             WHEN @Status = 3 THEN N'partial' ELSE N'completed' END;
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_RunComplete;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, @Status AS Status,
           @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ImportRun_Fail
    @RunPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @Stage NVARCHAR(50),
    @ErrorCode NVARCHAR(100),
    @SanitizedMessage NVARCHAR(1000),
    @IsRetryable BIT,
    @FailedAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Stage = LOWER(LTRIM(RTRIM(@Stage)));
    SET @ErrorCode = LOWER(LTRIM(RTRIM(@ErrorCode)));
    SET @SanitizedMessage = LTRIM(RTRIM(@SanitizedMessage));
    IF NULLIF(@Stage, N'') IS NULL OR LEN(@Stage) > 50
       OR NULLIF(@ErrorCode, N'') IS NULL OR LEN(@ErrorCode) > 100
       OR NULLIF(@SanitizedMessage, N'') IS NULL OR LEN(@SanitizedMessage) > 1000
       OR CHARINDEX(CHAR(10), @Stage + @ErrorCode + @SanitizedMessage) > 0
       OR CHARINDEX(CHAR(13), @Stage + @ErrorCode + @SanitizedMessage) > 0
        THROW 51722, N'Error context must be present, bounded and single-line.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @StartedTransaction BIT = 0;
    DECLARE @RunId BIGINT, @FundingSourceId INT, @Status TINYINT;
    DECLARE @CurrentLeaseId UNIQUEIDENTIFIER, @LeaseUntilUtc DATETIME2(3);
    DECLARE @AttemptCount SMALLINT, @MaxAttempts SMALLINT, @RetryBaseDelaySeconds INT;
    DECLARE @CurrentLastErrorCode NVARCHAR(100);
    DECLARE @NextAttemptAtUtc DATETIME2(3), @Succeeded BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'not-found', @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();

    IF @InitialTransactionCount = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE SAVE TRANSACTION FP_RunFail;

    BEGIN TRY
        SELECT @RunId = Id, @FundingSourceId = FundingSourceId, @Status = Status,
               @CurrentLeaseId = LeaseId, @LeaseUntilUtc = LeaseUntilUtc,
               @AttemptCount = AttemptCount, @MaxAttempts = MaxAttempts,
               @RetryBaseDelaySeconds = RetryBaseDelaySeconds,
               @NextAttemptAtUtc = NextAttemptAtUtc,
               @CurrentLastErrorCode = LastErrorCode
        FROM dbo.FundingPlatform_ImportRuns WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @RunPublicId;

        IF @RunId IS NULL
            SET @Code = N'not-found';
        ELSE IF @Status = 4 AND @CurrentLastErrorCode = @ErrorCode
        BEGIN
            SET @Succeeded = 1;
            SET @WasReplay = 1;
            SET @Code = N'replayed';
        END
        ELSE IF @Status <> 1
            SET @Code = N'invalid-state';
        ELSE IF @CurrentLeaseId <> @LeaseId OR @LeaseUntilUtc <= @NowUtc
            SET @Code = N'stale-lease';
        ELSE
        BEGIN
            INSERT INTO dbo.FundingPlatform_ImportErrors
                (ImportRunId, FundingSourceId, ImportRunItemId, Stage, ErrorCode,
                 SanitizedMessage, IsRetryable, OccurredAtUtc, CreatedAtUtc)
            VALUES (@RunId, @FundingSourceId, NULL, @Stage, @ErrorCode,
                    @SanitizedMessage, @IsRetryable, @FailedAtUtc, @NowUtc);

            UPDATE dbo.FundingPlatform_FundingSources
            SET ConsecutiveFailureCount = ConsecutiveFailureCount + 1,
                UpdatedAtUtc = @NowUtc
            WHERE Id = @FundingSourceId;

            IF @IsRetryable = 1 AND @AttemptCount < @MaxAttempts
            BEGIN
                DECLARE @DelaySeconds INT =
                    CASE WHEN @RetryBaseDelaySeconds
                              * CONVERT(INT, POWER(CONVERT(FLOAT, 2), @AttemptCount - 1)) > 3600
                         THEN 3600
                         ELSE @RetryBaseDelaySeconds
                              * CONVERT(INT, POWER(CONVERT(FLOAT, 2), @AttemptCount - 1)) END;
                SET @NextAttemptAtUtc = DATEADD(SECOND, @DelaySeconds, @FailedAtUtc);

                UPDATE dbo.FundingPlatform_ImportRuns
                SET Status = 0, LeaseId = NULL, LeaseUntilUtc = NULL,
                    NextAttemptAtUtc = @NextAttemptAtUtc,
                    LastErrorCode = @ErrorCode,
                    LastErrorMessage = @SanitizedMessage,
                    UpdatedAtUtc = @NowUtc
                WHERE Id = @RunId;

                DECLARE @RetryEventId UNIQUEIDENTIFIER = NEWID();
                INSERT INTO dbo.FundingPlatform_OutboxMessages
                    (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                     OccurredAtUtc, AvailableAtUtc)
                SELECT @RetryEventId, N'ImportRunRequested', N'ImportRun',
                       CONVERT(NVARCHAR(100), @RunPublicId),
                       (SELECT @RunPublicId AS runId, 1 AS [version]
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                       @FailedAtUtc, @NextAttemptAtUtc;

                SET @Status = 0;
                SET @Succeeded = 1;
                SET @Code = N'retry-scheduled';
            END
            ELSE
            BEGIN
                DECLARE @TerminalItemCount INT;
                UPDATE dbo.FundingPlatform_ImportRunItems
                SET Status = 3, OutcomeCode = N'failed',
                    CompletedAtUtc = @FailedAtUtc, UpdatedAtUtc = @NowUtc
                WHERE ImportRunId = @RunId AND Status IN (0, 1);
                SET @TerminalItemCount = @@ROWCOUNT;

                UPDATE dbo.FundingPlatform_ImportRuns
                SET Status = 4, LeaseId = NULL, LeaseUntilUtc = NULL,
                    CompletedAtUtc = @FailedAtUtc,
                    FailedCount = FailedCount + @TerminalItemCount,
                    LastErrorCode = @ErrorCode,
                    LastErrorMessage = @SanitizedMessage,
                    UpdatedAtUtc = @NowUtc
                WHERE Id = @RunId;

                SET @Status = 4;
                SET @NextAttemptAtUtc = NULL;
                SET @Succeeded = 1;
                SET @Code = N'failed';
            END;
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_RunFail;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, @Status AS Status,
           @NextAttemptAtUtc AS NextAttemptAtUtc, @WasReplay AS WasReplay;
END;
GO
