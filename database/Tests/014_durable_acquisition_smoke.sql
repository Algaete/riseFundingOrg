/* Transactional smoke for FASE 7A durable acquisition. Always rolls back fixtures. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @RequiredTables TABLE (Name SYSNAME NOT NULL PRIMARY KEY);
INSERT INTO @RequiredTables (Name) VALUES
    (N'FundingPlatform_ImportRuns'),
    (N'FundingPlatform_RawFundingOpportunities'),
    (N'FundingPlatform_ImportRunItems'),
    (N'FundingPlatform_ImportErrors');

IF EXISTS
(
    SELECT 1
    FROM @RequiredTables AS required
    LEFT JOIN sys.tables AS actual
        ON actual.name COLLATE DATABASE_DEFAULT = required.Name COLLATE DATABASE_DEFAULT
       AND actual.schema_id = SCHEMA_ID(N'dbo')
    WHERE actual.object_id IS NULL
)
    THROW 53401, N'One or more durable-acquisition tables are missing.', 1;

DECLARE @RequiredProcedures TABLE (Name SYSNAME NOT NULL PRIMARY KEY);
INSERT INTO @RequiredProcedures (Name) VALUES
    (N'FundingPlatform_usp_ImportRun_Admin_Create'),
    (N'FundingPlatform_usp_ImportRun_Admin_List'),
    (N'FundingPlatform_usp_ImportRun_Admin_Get'),
    (N'FundingPlatform_usp_ImportRun_Scheduler_CreateDue'),
    (N'FundingPlatform_usp_ImportRun_Claim'),
    (N'FundingPlatform_usp_ImportRun_RenewLease'),
    (N'FundingPlatform_usp_ImportRunOutbox_Claim'),
    (N'FundingPlatform_usp_ImportRun_RequeueStranded'),
    (N'FundingPlatform_usp_RawFundingOpportunity_Record'),
    (N'FundingPlatform_usp_ImportRunItem_ListPending'),
    (N'FundingPlatform_usp_ImportRunItem_Complete'),
    (N'FundingPlatform_usp_ImportRunItem_Fail'),
    (N'FundingPlatform_usp_ImportRun_Complete'),
    (N'FundingPlatform_usp_ImportRun_Fail');

IF EXISTS
(
    SELECT 1
    FROM @RequiredProcedures AS required
    LEFT JOIN sys.procedures AS actual
        ON actual.name COLLATE DATABASE_DEFAULT = required.Name COLLATE DATABASE_DEFAULT
       AND actual.schema_id = SCHEMA_ID(N'dbo')
    WHERE actual.object_id IS NULL
)
    THROW 53402, N'One or more durable-acquisition procedures are missing.', 1;

IF COL_LENGTH(N'dbo.FundingPlatform_FundingSources', N'ProviderCode') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_FundingSources', N'NextRunAtUtc') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_FundingSources', N'ScheduleIntervalSeconds') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_FundingSources', N'ComplianceStatus') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_ImportRuns', N'CorrelationId') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_ImportRuns', N'LeaseId') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_RawFundingOpportunities', N'ContentHash') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_ImportRunItems', N'RawFundingOpportunityId') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_ImportRunItems', N'NormalizedSnapshotVersion') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_ImportRunItems', N'NormalizedSnapshotJson') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_ImportRunItems', N'NormalizedSnapshotHash') IS NULL
    THROW 53403, N'Durable-acquisition schema is incomplete.', 1;

IF EXISTS
(
    SELECT 1
    FROM sys.columns
    WHERE object_id IN
          (OBJECT_ID(N'dbo.FundingPlatform_ImportRuns'),
           OBJECT_ID(N'dbo.FundingPlatform_RawFundingOpportunities'),
           OBJECT_ID(N'dbo.FundingPlatform_ImportRunItems'))
      AND name IN (N'ContentHash', N'SourceItemKeyHash',
                   N'IdempotencyKeyHash', N'RequestHash',
                   N'NormalizedSnapshotHash')
      AND (system_type_id <> TYPE_ID(N'binary') OR max_length <> 32)
)
    THROW 53404, N'A durable-acquisition hash is not BINARY(32).', 1;

IF OBJECT_ID(N'dbo.FundingPlatform_tr_RawFundingOpportunities_Immutable', N'TR') IS NULL
   OR CHARINDEX(N'AFTER UPDATE, DELETE', UPPER(COALESCE(OBJECT_DEFINITION
      (OBJECT_ID(N'dbo.FundingPlatform_tr_RawFundingOpportunities_Immutable')), N''))) = 0
    THROW 53405, N'Raw observations are not protected as immutable.', 1;

DECLARE @AdminProcedures TABLE (Name SYSNAME NOT NULL PRIMARY KEY);
INSERT INTO @AdminProcedures (Name) VALUES
    (N'FundingPlatform_usp_ImportRun_Admin_Create'),
    (N'FundingPlatform_usp_ImportRun_Admin_List'),
    (N'FundingPlatform_usp_ImportRun_Admin_Get');

IF EXISTS
(
    SELECT 1
    FROM @AdminProcedures AS required
    INNER JOIN sys.procedures AS procedures
        ON procedures.name COLLATE DATABASE_DEFAULT = required.Name COLLATE DATABASE_DEFAULT
       AND procedures.schema_id = SCHEMA_ID(N'dbo')
    WHERE CHARINDEX(N'FundingPlatform_fn_AdminAccessState',
                    COALESCE(OBJECT_DEFINITION(procedures.object_id), N'')) = 0
      AND CHARINDEX(N'FundingPlatform_usp_AdminActor_Lock',
                    COALESCE(OBJECT_DEFINITION(procedures.object_id), N'')) = 0
)
    THROW 53406, N'An import administration procedure does not enforce Admin MFA.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_FundingSources
    WHERE ProviderCode = N'grants-gov' AND Name = N'Grants.gov'
      AND ProviderType = 1 AND IsEnabled = 1 AND ComplianceStatus = 1
      AND ComplianceApprovedAtUtc IS NOT NULL
      AND ScheduleIntervalSeconds = 86400
      AND JSON_VALUE(ConfigurationJson, N'$.autoPublish') = N'false'
      AND SecretReference IS NULL
)
    THROW 53407, N'The conservative approved Grants.gov source seed is missing.', 1;

IF CHARINDEX(N'RawContent', COALESCE(OBJECT_DEFINITION
       (OBJECT_ID(N'dbo.FundingPlatform_usp_ImportRunOutbox_Claim')), N'')) > 0
   OR EXISTS
      (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
       WHERE MessageType LIKE N'ImportRun%'
         AND (PayloadJson LIKE N'%rawContent%'
              OR PayloadJson LIKE N'%keyword%'
              OR PayloadJson LIKE N'%sourceUrl%'))
    THROW 53408, N'An import outbox contract exposes raw or request content.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke014;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @Suffix NVARCHAR(32) = REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'');
    DECLARE @AdminPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @NoMfaPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @AdminEmail NVARCHAR(320) = N'import-admin-' + @Suffix + N'@example.invalid';
    DECLARE @NoMfaEmail NVARCHAR(320) = N'import-no-mfa-' + @Suffix + N'@example.invalid';
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@AdminPublicId, @AdminEmail, UPPER(@AdminEmail), N'Import smoke admin',
         N'not-a-credential', N'import-smoke-admin', 1, 1, 2, N'es-CL'),
        (@NoMfaPublicId, @NoMfaEmail, UPPER(@NoMfaEmail), N'Import smoke no MFA',
         N'not-a-credential', N'import-smoke-no-mfa', 1, 0, 2, N'es-CL');

    DECLARE @AdminUserId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @AdminPublicId);
    DECLARE @NoMfaUserId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @NoMfaPublicId);
    DECLARE @AdminRoleId SMALLINT =
        (SELECT Id FROM dbo.FundingPlatform_Roles WHERE NormalizedName = N'ADMIN');
    DECLARE @FundingSourceId INT =
        (SELECT Id FROM dbo.FundingPlatform_FundingSources
         WHERE ProviderCode = N'grants-gov');

    INSERT INTO dbo.FundingPlatform_UserRoles (UserId, RoleId, GrantedByUserId)
    VALUES (@AdminUserId, @AdminRoleId, @AdminUserId),
           (@NoMfaUserId, @AdminRoleId, @AdminUserId);

    DECLARE @CreateResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), RunPublicId UNIQUEIDENTIFIER NULL,
        FundingSourceId INT, SourceName NVARCHAR(150) NULL, Status TINYINT NULL,
        CreatedAtUtc DATETIME2(3) NULL, WasReplay BIT
    );
    DECLARE @NoMfaError INT;
    DECLARE @DeniedActorUserId BIGINT;

    SET XACT_ABORT OFF;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId = @NoMfaPublicId,
            @ActorUserId = @DeniedActorUserId OUTPUT;
    END TRY
    BEGIN CATCH
        SET @NoMfaError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;

    IF ISNULL(@NoMfaError, 0) <> 51602
       OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_ImportRuns
                  WHERE RequestedByUserId = @NoMfaUserId)
        THROW 53409, N'An administrator without MFA created an import run.', 1;

    DECLARE @IdempotencyHash BINARY(32) = HASHBYTES('SHA2_256', N'idem-' + @Suffix);
    DECLARE @RequestHash BINARY(32) = HASHBYTES('SHA2_256', N'request-' + @Suffix);
    DELETE FROM @CreateResult;
    DECLARE @GovernanceIdempotencyHash BINARY(32) =
        HASHBYTES('SHA2_256', N'idem-governance-' + @Suffix);
    DECLARE @GovernanceRequestHash BINARY(32) =
        HASHBYTES('SHA2_256', N'request-governance-' + @Suffix);
    INSERT INTO @CreateResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Admin_Create
        @AdminUserPublicId = @AdminPublicId,
        @FundingSourceId = @FundingSourceId,
        @Keyword = N'community foundations',
        @MaximumResults = 5,
        @IdempotencyKeyHash = @IdempotencyHash,
        @RequestHash = @RequestHash,
        @CorrelationId = N'smokecreatemain';

    DECLARE @RunPublicId UNIQUEIDENTIFIER = (SELECT RunPublicId FROM @CreateResult);
    DECLARE @RunId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_ImportRuns WHERE PublicId = @RunPublicId);
    IF @RunPublicId IS NULL
       OR NOT EXISTS (SELECT 1 FROM @CreateResult
                      WHERE Succeeded = 1 AND Code = N'created'
                        AND Status = 0 AND WasReplay = 0)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ImportRuns
           WHERE Id = @RunId AND TriggerType = 0 AND CorrelationId = N'smokecreatemain')
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_OutboxMessages
           WHERE MessageType = N'ImportRunRequested'
             AND AggregateId = CONVERT(NVARCHAR(100), @RunPublicId)) <> 1
        THROW 53410, N'A manual import run was not durably created.', 1;

    DELETE FROM @CreateResult;
    INSERT INTO @CreateResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Admin_Create
        @AdminUserPublicId = @AdminPublicId,
        @FundingSourceId = @FundingSourceId,
        @Keyword = N'community foundations',
        @MaximumResults = 5,
        @IdempotencyKeyHash = @IdempotencyHash,
        @RequestHash = @RequestHash,
        @CorrelationId = N'smokereplayignored';

    IF NOT EXISTS (SELECT 1 FROM @CreateResult
                   WHERE Succeeded = 1 AND Code = N'replayed'
                     AND RunPublicId = @RunPublicId AND WasReplay = 1)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_ImportRuns
           WHERE RequestedByUserId = @AdminUserId
             AND FundingSourceId = @FundingSourceId
             AND IdempotencyKeyHash = @IdempotencyHash) <> 1
        THROW 53411, N'Manual import idempotency replay failed.', 1;

    DELETE FROM @CreateResult;
    INSERT INTO @CreateResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Admin_Create
        @AdminUserPublicId = @AdminPublicId,
        @FundingSourceId = @FundingSourceId,
        @Keyword = N'different request',
        @MaximumResults = 3,
        @IdempotencyKeyHash = @IdempotencyHash,
        @RequestHash = 0x0303030303030303030303030303030303030303030303030303030303030303,
        @CorrelationId = N'smokeconflict';

    IF NOT EXISTS (SELECT 1 FROM @CreateResult
                   WHERE Succeeded = 0 AND Code = N'idempotency-conflict'
                     AND RunPublicId IS NULL)
        THROW 53412, N'A conflicting idempotency replay was accepted.', 1;

    DECLARE @ClaimResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), RunPublicId UNIQUEIDENTIFIER NULL,
        FundingSourceId INT NULL, ProviderCode NVARCHAR(100) NULL,
        Keyword NVARCHAR(200) NULL, MaximumResults INT NULL,
        AttemptCount SMALLINT NULL, RetrievedCount INT NULL,
        LeaseUntilUtc DATETIME2(3) NULL,
        RequestRateLimitPerMinute INT NULL,
        MaximumResponseBytes INT NULL,
        ContentRetentionDays SMALLINT NULL,
        AcquisitionPolicyVersion INT NULL,
        AcquisitionPolicyFingerprint BINARY(32) NULL
    );

    DELETE FROM @CreateResult;
    INSERT INTO @CreateResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Admin_Create
        @AdminUserPublicId = @AdminPublicId, @FundingSourceId = @FundingSourceId,
        @Keyword = N'governance fixture', @MaximumResults = 1,
        @IdempotencyKeyHash = @GovernanceIdempotencyHash,
        @RequestHash = @GovernanceRequestHash,
        @CorrelationId = N'smokegovernance';
    DECLARE @GovernanceRunPublicId UNIQUEIDENTIFIER =
        (SELECT RunPublicId FROM @CreateResult);
    DECLARE @GovernanceNowUtc DATETIME2(3) = SYSUTCDATETIME();
    UPDATE dbo.FundingPlatform_FundingSources
    SET IsEnabled = 0, UpdatedAtUtc = @GovernanceNowUtc
    WHERE Id = @FundingSourceId;
    DECLARE @GovernanceLease UNIQUEIDENTIFIER = NEWID();
    INSERT INTO @ClaimResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Claim
        @RunPublicId = @GovernanceRunPublicId, @LeaseId = @GovernanceLease,
        @LeaseSeconds = 120, @NowUtc = @GovernanceNowUtc;
    IF NOT EXISTS (SELECT 1 FROM @ClaimResult
                   WHERE Succeeded = 0 AND Code = N'source-disabled')
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ImportRuns
           WHERE PublicId = @GovernanceRunPublicId AND Status = 5
             AND CompletedAtUtc IS NOT NULL)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ImportErrors AS errors
           INNER JOIN dbo.FundingPlatform_ImportRuns AS runs
               ON runs.Id = errors.ImportRunId
           WHERE runs.PublicId = @GovernanceRunPublicId
             AND errors.ErrorCode = N'source-disabled')
        THROW 53432, N'A revoked source left its queued run non-terminal.', 1;
    UPDATE dbo.FundingPlatform_FundingSources
    SET IsEnabled = 1, UpdatedAtUtc = @GovernanceNowUtc
    WHERE Id = @FundingSourceId;
    DELETE FROM @ClaimResult;

    DECLARE @Lease1 UNIQUEIDENTIFIER = NEWID();
    DECLARE @MainClaimAtUtc DATETIME2(3) = SYSUTCDATETIME();
    INSERT INTO @ClaimResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Claim
        @RunPublicId = @RunPublicId, @LeaseId = @Lease1,
        @LeaseSeconds = 120, @NowUtc = @MainClaimAtUtc;

    IF NOT EXISTS (SELECT 1 FROM @ClaimResult
                   WHERE Succeeded = 1 AND Code = N'claimed'
                     AND AttemptCount = 1 AND RetrievedCount = 0
                     AND ProviderCode = N'grants-gov')
        THROW 53413, N'A queued import run was not claimed.', 1;

    DELETE FROM @ClaimResult;
    DECLARE @MainReplayAtUtc DATETIME2(3) = DATEADD(SECOND, 1, @MainClaimAtUtc);
    INSERT INTO @ClaimResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Claim
        @RunPublicId = @RunPublicId, @LeaseId = @Lease1,
        @LeaseSeconds = 120, @NowUtc = @MainReplayAtUtc;
    IF NOT EXISTS (SELECT 1 FROM @ClaimResult
                   WHERE Succeeded = 1 AND Code = N'replayed' AND AttemptCount = 1)
        THROW 53414, N'A lease replay incremented the attempt count.', 1;

    DECLARE @RenewResult TABLE
        (Succeeded BIT, Code NVARCHAR(50), LeaseUntilUtc DATETIME2(3) NULL);
    INSERT INTO @RenewResult
    EXEC dbo.FundingPlatform_usp_ImportRun_RenewLease
        @RunPublicId = @RunPublicId, @LeaseId = @Lease1,
        @LeaseSeconds = 180, @NowUtc = @MainReplayAtUtc;
    IF NOT EXISTS (SELECT 1 FROM @RenewResult
                   WHERE Succeeded = 1 AND Code = N'renewed'
                     AND LeaseUntilUtc > DATEADD(MINUTE, 2, @MainClaimAtUtc))
        THROW 53436, N'An active worker could not renew its run lease.', 1;

    DECLARE @Lease2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @MainReclaimAtUtc DATETIME2(3) = DATEADD(MINUTE, 4, @MainClaimAtUtc);
    DELETE FROM @ClaimResult;
    INSERT INTO @ClaimResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Claim
        @RunPublicId = @RunPublicId, @LeaseId = @Lease2,
        @LeaseSeconds = 300, @NowUtc = @MainReclaimAtUtc;
    IF NOT EXISTS (SELECT 1 FROM @ClaimResult
                   WHERE Succeeded = 1 AND Code = N'claimed' AND AttemptCount = 2)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ImportErrors
           WHERE ImportRunId = @RunId AND ErrorCode = N'lease-expired')
        THROW 53415, N'An expired run lease was not safely reclaimed.', 1;

    DECLARE @RawRetrievedAtUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @RawContent NVARCHAR(MAX) =
        (SELECT N'HIT-' + @Suffix AS id, N'Smoke funding opportunity' AS title
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @RawContentHash BINARY(32) =
        HASHBYTES
        ('SHA2_256',
         CONVERT(VARBINARY(MAX),
                 CONVERT(VARCHAR(MAX),
                         @RawContent COLLATE Latin1_General_100_BIN2_UTF8)));
    DECLARE @RawSourceKeyHash BINARY(32) =
        HASHBYTES('SHA2_256', N'HIT-' + @Suffix);
    DECLARE @RawExternalId NVARCHAR(250) = N'HIT-' + @Suffix;
    DECLARE @SourceUrl NVARCHAR(2048) =
        N'https://www.grants.gov/search-results-detail/' + @Suffix;
    DECLARE @ReferenceNumber NVARCHAR(250) = N'REF-' + @Suffix;
    DECLARE @NormalizedSnapshotVersion SMALLINT = 1;
    DECLARE @NormalizedOpportunityBody NVARCHAR(MAX) =
        (SELECT N'grants-gov' AS providerCode,
                @RawExternalId AS externalId,
                @ReferenceNumber AS referenceNumber,
                N'Smoke funding opportunity' AS title,
                N'Smoke official sponsor' AS sponsorName,
                N'Public official fixture for durable acquisition.' AS description,
                N'Eligible nonprofit organizations.' AS eligibilityDescription,
                CAST(NULL AS NVARCHAR(100)) AS fundingInstrument,
                CAST(NULL AS NVARCHAR(1000)) AS fundingCategoriesDescription,
                CAST(NULL AS NVARCHAR(10)) AS openDate,
                CAST(NULL AS NVARCHAR(10)) AS closeDate,
                CAST(NULL AS DECIMAL(19,4)) AS minimumAmount,
                CAST(NULL AS DECIMAL(19,4)) AS maximumAmount,
                CAST(NULL AS BIT) AS requiresCofunding,
                @SourceUrl AS sourceUrl,
                @SourceUrl AS applicationUrl,
                CONVERT(NVARCHAR(40),
                        TODATETIMEOFFSET(@RawRetrievedAtUtc, N'+00:00'), 127)
                    AS retrievedAtUtc
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);
    DECLARE @NormalizedSnapshotJson NVARCHAR(MAX) =
        (SELECT @NormalizedSnapshotVersion AS schemaVersion,
                JSON_QUERY(@NormalizedOpportunityBody) AS opportunity
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @NormalizedSnapshotHash BINARY(32) =
        HASHBYTES
        ('SHA2_256',
         CONVERT(VARBINARY(MAX),
                 CONVERT(VARCHAR(MAX),
                         @NormalizedSnapshotJson COLLATE Latin1_General_100_BIN2_UTF8)));
    DECLARE @RawResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), ItemPublicId UNIQUEIDENTIFIER NULL,
        RawObservationPublicId UNIQUEIDENTIFIER NULL,
        WasRawReplay BIT, AlreadyCompleted BIT
    );

    INSERT INTO @RawResult
    EXEC dbo.FundingPlatform_usp_RawFundingOpportunity_Record
        @RunPublicId = @RunPublicId, @LeaseId = @Lease2,
        @ExternalId = @RawExternalId, @SourceUrl = @SourceUrl,
        @RetrievedAtUtc = @RawRetrievedAtUtc, @MimeType = N'application/json',
        @RawContent = @RawContent, @ContentHash = @RawContentHash,
        @SourceItemKeyHash = @RawSourceKeyHash,
        @NormalizedSnapshotVersion = @NormalizedSnapshotVersion,
        @NormalizedSnapshotJson = @NormalizedSnapshotJson,
        @NormalizedSnapshotHash = @NormalizedSnapshotHash;

    DECLARE @ItemPublicId UNIQUEIDENTIFIER = (SELECT ItemPublicId FROM @RawResult);
    DECLARE @RawPublicId UNIQUEIDENTIFIER = (SELECT RawObservationPublicId FROM @RawResult);
    IF @ItemPublicId IS NULL OR @RawPublicId IS NULL
       OR NOT EXISTS (SELECT 1 FROM @RawResult
                      WHERE Succeeded = 1 AND Code = N'recorded'
                        AND WasRawReplay = 0 AND AlreadyCompleted = 0)
        THROW 53416, N'A raw observation was not durably recorded.', 1;

    DELETE FROM @RawResult;
    INSERT INTO @RawResult
    EXEC dbo.FundingPlatform_usp_RawFundingOpportunity_Record
        @RunPublicId = @RunPublicId, @LeaseId = @Lease2,
        @ExternalId = @RawExternalId, @SourceUrl = @SourceUrl,
        @RetrievedAtUtc = @RawRetrievedAtUtc, @MimeType = N'application/json',
        @RawContent = @RawContent, @ContentHash = @RawContentHash,
        @SourceItemKeyHash = @RawSourceKeyHash,
        @NormalizedSnapshotVersion = @NormalizedSnapshotVersion,
        @NormalizedSnapshotJson = @NormalizedSnapshotJson,
        @NormalizedSnapshotHash = @NormalizedSnapshotHash;
    IF NOT EXISTS (SELECT 1 FROM @RawResult
                   WHERE Succeeded = 1 AND Code = N'replayed'
                     AND ItemPublicId = @ItemPublicId
                     AND RawObservationPublicId = @RawPublicId
                     AND WasRawReplay = 1)
       OR (SELECT RetrievedCount FROM dbo.FundingPlatform_ImportRuns
           WHERE Id = @RunId) <> 1
        THROW 53417, N'Raw/item idempotency replay failed.', 1;

    DECLARE @ConflictingSnapshotJson NVARCHAR(MAX) =
        JSON_MODIFY(@NormalizedSnapshotJson, N'$.opportunity.title', N'Changed title');
    DECLARE @ConflictingSnapshotHash BINARY(32) =
        HASHBYTES
        ('SHA2_256',
         CONVERT(VARBINARY(MAX),
                 CONVERT(VARCHAR(MAX),
                         @ConflictingSnapshotJson COLLATE Latin1_General_100_BIN2_UTF8)));
    DELETE FROM @RawResult;
    INSERT INTO @RawResult
    EXEC dbo.FundingPlatform_usp_RawFundingOpportunity_Record
        @RunPublicId = @RunPublicId, @LeaseId = @Lease2,
        @ExternalId = @RawExternalId, @SourceUrl = @SourceUrl,
        @RetrievedAtUtc = @RawRetrievedAtUtc, @MimeType = N'application/json',
        @RawContent = @RawContent, @ContentHash = @RawContentHash,
        @SourceItemKeyHash = @RawSourceKeyHash,
        @NormalizedSnapshotVersion = @NormalizedSnapshotVersion,
        @NormalizedSnapshotJson = @ConflictingSnapshotJson,
        @NormalizedSnapshotHash = @ConflictingSnapshotHash;
    IF NOT EXISTS (SELECT 1 FROM @RawResult
                   WHERE Succeeded = 0 AND Code = N'item-conflict'
                     AND ItemPublicId IS NULL AND RawObservationPublicId IS NULL)
        THROW 53443, N'A conflicting pending snapshot was accepted.', 1;

    /* StageExternal remains the single normalization/editorial boundary. The
       raw hit id intentionally differs from the source-link reference number. */
    DECLARE @StageSourceKeyHash BINARY(32) =
        HASHBYTES('SHA2_256', @ReferenceNumber);
    DECLARE @StageSnapshot NVARCHAR(MAX) =
        (SELECT @ReferenceNumber AS referenceNumber,
                N'Smoke funding opportunity' AS title
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @StageContentHash BINARY(32) =
        HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @StageSnapshot));
    DECLARE @StageCanonicalUrlHash BINARY(32) =
        HASHBYTES
        ('SHA2_256',
         CONVERT(VARBINARY(MAX),
                 CONVERT(VARCHAR(MAX),
                         @SourceUrl COLLATE Latin1_General_100_BIN2_UTF8)));
    DECLARE @StageSlug NVARCHAR(320) = N'smoke-f7a-' + LOWER(@Suffix);
    DECLARE @StageResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50),
        FundingOpportunityPublicId UNIQUEIDENTIFIER NULL,
        ContentVersion INT NULL, PublicationStatus TINYINT NULL,
        RowVersion BINARY(8) NULL, StagedRevisionPublicId UNIQUEIDENTIFIER NULL
    );

    INSERT INTO @StageResult
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_StageExternal
        @FundingSourceId = @FundingSourceId,
        @ExpectedProviderCode = N'grants-gov',
        @ExternalId = @ReferenceNumber,
        @SourceItemKeyHash = @StageSourceKeyHash,
        @SourceUrl = @SourceUrl,
        @CanonicalUrlHash = @StageCanonicalUrlHash,
        @ObservedAtUtc = @RawRetrievedAtUtc,
        @Slug = @StageSlug,
        @Title = N'Smoke funding opportunity',
        @Description = N'Public official fixture for durable acquisition.',
        @Summary = N'Durable acquisition smoke fixture.',
        @SponsorName = N'Smoke official sponsor',
        @SponsorUrl = N'https://www.grants.gov/',
        @ApplicationUrl = @SourceUrl,
        @FundingTypeId = NULL,
        @Currency = NULL,
        @MinAmount = NULL,
        @MaxAmount = NULL,
        @AmountStatus = 0,
        @OpenDate = NULL,
        @CloseDate = NULL,
        @DeadlineType = 0,
        @DeadlinePrecision = 0,
        @EligibilityDescription = N'Eligible nonprofit organizations.',
        @Objectives = N'Community impact.',
        @RequiresCofunding = NULL,
        @CofundingPercentage = NULL,
        @DataQualityScore = 85,
        @SnapshotJson = @StageSnapshot,
        @ContentHash = @StageContentHash;

    DECLARE @OpportunityPublicId UNIQUEIDENTIFIER =
        (SELECT FundingOpportunityPublicId FROM @StageResult);
    IF @OpportunityPublicId IS NULL
       OR NOT EXISTS (SELECT 1 FROM @StageResult
                      WHERE Succeeded = 1 AND Code = N'draft-created'
                        AND PublicationStatus = 0)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
           WHERE PublicId = @OpportunityPublicId AND PublicationStatus = 0
             AND PublishedAtUtc IS NULL)
        THROW 53418, N'External staging bypassed or failed the draft-only boundary.', 1;

    DECLARE @ItemCompleteResult TABLE
        (Succeeded BIT, Code NVARCHAR(50), WasReplay BIT);
    DECLARE @ItemCompletedAtUtc DATETIME2(3) = SYSUTCDATETIME();
    INSERT INTO @ItemCompleteResult
    EXEC dbo.FundingPlatform_usp_ImportRunItem_Complete
        @RunPublicId = @RunPublicId, @LeaseId = @Lease2,
        @ItemPublicId = @ItemPublicId, @OutcomeCode = N'created',
        @OpportunityPublicId = NULL, @CompletedAtUtc = @ItemCompletedAtUtc;

    IF NOT EXISTS (SELECT 1 FROM @ItemCompleteResult
                   WHERE Succeeded = 1 AND Code = N'completed' AND WasReplay = 0)
       OR NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ImportRunItems AS items
           INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
               ON opportunities.Id = items.FundingOpportunityId
           WHERE items.PublicId = @ItemPublicId
             AND opportunities.PublicId = @OpportunityPublicId)
        THROW 53419, N'Item completion did not resolve the staged draft by source URL.', 1;

    DELETE FROM @ItemCompleteResult;
    INSERT INTO @ItemCompleteResult
    EXEC dbo.FundingPlatform_usp_ImportRunItem_Complete
        @RunPublicId = @RunPublicId, @LeaseId = @Lease2,
        @ItemPublicId = @ItemPublicId, @OutcomeCode = N'created',
        @OpportunityPublicId = NULL, @CompletedAtUtc = @ItemCompletedAtUtc;
    IF NOT EXISTS (SELECT 1 FROM @ItemCompleteResult
                   WHERE Succeeded = 1 AND Code = N'replayed' AND WasReplay = 1)
       OR (SELECT CreatedCount FROM dbo.FundingPlatform_ImportRuns
           WHERE Id = @RunId) <> 1
        THROW 53420, N'Item outcome idempotency failed.', 1;

    DECLARE @ChangedRawContent NVARCHAR(MAX) =
        JSON_MODIFY(@RawContent, N'$.title', N'Late provider change');
    DECLARE @ChangedRawContentHash BINARY(32) =
        HASHBYTES
        ('SHA2_256',
         CONVERT(VARBINARY(MAX),
                 CONVERT(VARCHAR(MAX),
                         @ChangedRawContent COLLATE Latin1_General_100_BIN2_UTF8)));
    DELETE FROM @RawResult;
    INSERT INTO @RawResult
    EXEC dbo.FundingPlatform_usp_RawFundingOpportunity_Record
        @RunPublicId = @RunPublicId, @LeaseId = @Lease2,
        @ExternalId = @RawExternalId, @SourceUrl = @SourceUrl,
        @RetrievedAtUtc = @ItemCompletedAtUtc, @MimeType = N'application/json',
        @RawContent = @ChangedRawContent, @ContentHash = @ChangedRawContentHash,
        @SourceItemKeyHash = @RawSourceKeyHash,
        @NormalizedSnapshotVersion = @NormalizedSnapshotVersion,
        @NormalizedSnapshotJson = @ConflictingSnapshotJson,
        @NormalizedSnapshotHash = @ConflictingSnapshotHash;
    IF NOT EXISTS (SELECT 1 FROM @RawResult
                   WHERE Succeeded = 1 AND Code = N'replayed'
                     AND ItemPublicId = @ItemPublicId
                     AND RawObservationPublicId = @RawPublicId
                     AND AlreadyCompleted = 1)
       OR (SELECT RetrievedCount FROM dbo.FundingPlatform_ImportRuns
           WHERE Id = @RunId) <> 1
        THROW 53444, N'A completed first observation did not replay idempotently.', 1;

    DECLARE @RunCompleteResult TABLE
        (Succeeded BIT, Code NVARCHAR(50), Status TINYINT, WasReplay BIT);
    DECLARE @MainRunCompletedAtUtc DATETIME2(3) = SYSUTCDATETIME();
    INSERT INTO @RunCompleteResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Complete
        @RunPublicId = @RunPublicId, @LeaseId = @Lease2,
        @CompletedAtUtc = @MainRunCompletedAtUtc;
    IF NOT EXISTS (SELECT 1 FROM @RunCompleteResult
                   WHERE Succeeded = 1 AND Code = N'completed' AND Status = 2)
        THROW 53421, N'A successful import run did not complete.', 1;
    DECLARE @LastSuccessBeforeFailedItems DATETIME2(3) =
        (SELECT LastSuccessfulRunAtUtc
         FROM dbo.FundingPlatform_FundingSources WHERE Id = @FundingSourceId);

    /* A second run reuses the immutable raw row but owns an independent item. */
    DECLARE @SecondIdempotencyHash BINARY(32) = HASHBYTES('SHA2_256', N'idem-2-' + @Suffix);
    DECLARE @SecondRequestHash BINARY(32) = HASHBYTES('SHA2_256', N'request-2-' + @Suffix);
    DELETE FROM @CreateResult;
    INSERT INTO @CreateResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Admin_Create
        @AdminUserPublicId = @AdminPublicId, @FundingSourceId = @FundingSourceId,
        @Keyword = N'community foundations', @MaximumResults = 5,
        @IdempotencyKeyHash = @SecondIdempotencyHash,
        @RequestHash = @SecondRequestHash,
        @CorrelationId = N'smokesecondrun';
    DECLARE @SecondRunPublicId UNIQUEIDENTIFIER = (SELECT RunPublicId FROM @CreateResult);
    DECLARE @SecondRunId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_ImportRuns WHERE PublicId = @SecondRunPublicId);
    DECLARE @SecondLease UNIQUEIDENTIFIER = NEWID();
    DECLARE @SecondClaimAtUtc DATETIME2(3) = SYSUTCDATETIME();
    DELETE FROM @ClaimResult;
    INSERT INTO @ClaimResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Claim
        @RunPublicId = @SecondRunPublicId, @LeaseId = @SecondLease,
        @LeaseSeconds = 300, @NowUtc = @SecondClaimAtUtc;
    DECLARE @SecondRawRetrievedAtUtc DATETIME2(3) = SYSUTCDATETIME();
    DELETE FROM @RawResult;
    INSERT INTO @RawResult
    EXEC dbo.FundingPlatform_usp_RawFundingOpportunity_Record
        @RunPublicId = @SecondRunPublicId, @LeaseId = @SecondLease,
        @ExternalId = @RawExternalId, @SourceUrl = @SourceUrl,
        @RetrievedAtUtc = @SecondRawRetrievedAtUtc, @MimeType = N'application/json',
        @RawContent = @RawContent, @ContentHash = @RawContentHash,
        @SourceItemKeyHash = @RawSourceKeyHash,
        @NormalizedSnapshotVersion = @NormalizedSnapshotVersion,
        @NormalizedSnapshotJson = @NormalizedSnapshotJson,
        @NormalizedSnapshotHash = @NormalizedSnapshotHash;
    DECLARE @SecondItemPublicId UNIQUEIDENTIFIER = (SELECT ItemPublicId FROM @RawResult);
    IF @SecondItemPublicId = @ItemPublicId
       OR NOT EXISTS (SELECT 1 FROM @RawResult
                      WHERE RawObservationPublicId = @RawPublicId AND WasRawReplay = 1)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_RawFundingOpportunities
           WHERE FundingSourceId = @FundingSourceId
             AND SourceItemKeyHash = @RawSourceKeyHash
             AND ContentHash = @RawContentHash) <> 1
        THROW 53422, N'Raw observations were not deduplicated across runs.', 1;

    DECLARE @ItemFailResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50),
        ErrorPublicId UNIQUEIDENTIFIER NULL, WasReplay BIT
    );
    DECLARE @SecondItemFailedAtUtc DATETIME2(3) = SYSUTCDATETIME();
    INSERT INTO @ItemFailResult
    EXEC dbo.FundingPlatform_usp_ImportRunItem_Fail
        @RunPublicId = @SecondRunPublicId, @LeaseId = @SecondLease,
        @ItemPublicId = @SecondItemPublicId, @Stage = N'normalize',
        @ErrorCode = N'invalid-fixture',
        @SanitizedMessage = N'The fixture could not be normalized.',
        @IsRetryable = 0, @OccurredAtUtc = @SecondItemFailedAtUtc;
    IF NOT EXISTS (SELECT 1 FROM @ItemFailResult
                   WHERE Succeeded = 1 AND Code = N'failed'
                     AND ErrorPublicId IS NOT NULL)
        THROW 53423, N'An item error was not durably recorded.', 1;

    DELETE FROM @RunCompleteResult;
    DECLARE @SecondRunCompletedAtUtc DATETIME2(3) =
        DATEADD(SECOND, 1, @SecondItemFailedAtUtc);
    INSERT INTO @RunCompleteResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Complete
        @RunPublicId = @SecondRunPublicId, @LeaseId = @SecondLease,
        @CompletedAtUtc = @SecondRunCompletedAtUtc;
    IF NOT EXISTS (SELECT 1 FROM @RunCompleteResult
                   WHERE Succeeded = 1 AND Code = N'failed' AND Status = 4)
       OR (SELECT LastSuccessfulRunAtUtc
           FROM dbo.FundingPlatform_FundingSources WHERE Id = @FundingSourceId)
          <> @LastSuccessBeforeFailedItems
        THROW 53424, N'A 100-percent item failure was recorded as source success.', 1;

    /* Run-level retry uses a fresh outbox message and a new lease. */
    DELETE FROM @CreateResult;
    DECLARE @RetryIdempotencyHash BINARY(32) =
        HASHBYTES('SHA2_256', N'idem-3-' + @Suffix);
    DECLARE @RetryRequestHash BINARY(32) =
        HASHBYTES('SHA2_256', N'request-3-' + @Suffix);
    INSERT INTO @CreateResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Admin_Create
        @AdminUserPublicId = @AdminPublicId, @FundingSourceId = @FundingSourceId,
        @Keyword = N'retry fixture', @MaximumResults = 1,
        @IdempotencyKeyHash = @RetryIdempotencyHash,
        @RequestHash = @RetryRequestHash,
        @CorrelationId = N'smokeretryrun';
    DECLARE @RetryRunPublicId UNIQUEIDENTIFIER = (SELECT RunPublicId FROM @CreateResult);
    DECLARE @RetryRunId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_ImportRuns WHERE PublicId = @RetryRunPublicId);
    DECLARE @RetryLease1 UNIQUEIDENTIFIER = NEWID();
    DECLARE @RetryClaimAtUtc DATETIME2(3) = SYSUTCDATETIME();
    DELETE FROM @ClaimResult;
    INSERT INTO @ClaimResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Claim
        @RunPublicId = @RetryRunPublicId, @LeaseId = @RetryLease1,
        @LeaseSeconds = 300, @NowUtc = @RetryClaimAtUtc;

    DELETE FROM @RawResult;
    INSERT INTO @RawResult
    EXEC dbo.FundingPlatform_usp_RawFundingOpportunity_Record
        @RunPublicId = @RetryRunPublicId, @LeaseId = @RetryLease1,
        @ExternalId = @RawExternalId, @SourceUrl = @SourceUrl,
        @RetrievedAtUtc = @RetryClaimAtUtc, @MimeType = N'application/json',
        @RawContent = @RawContent, @ContentHash = @RawContentHash,
        @SourceItemKeyHash = @RawSourceKeyHash,
        @NormalizedSnapshotVersion = @NormalizedSnapshotVersion,
        @NormalizedSnapshotJson = @NormalizedSnapshotJson,
        @NormalizedSnapshotHash = @NormalizedSnapshotHash;
    DECLARE @RetryItemPublicId UNIQUEIDENTIFIER = (SELECT ItemPublicId FROM @RawResult);

    DECLARE @OverflowSourceKeyHash BINARY(32) =
        HASHBYTES('SHA2_256', N'overflow-' + @Suffix);
    DECLARE @OverflowExternalId NVARCHAR(250) = N'OVERFLOW-' + @Suffix;
    DELETE FROM @RawResult;
    INSERT INTO @RawResult
    EXEC dbo.FundingPlatform_usp_RawFundingOpportunity_Record
        @RunPublicId = @RetryRunPublicId, @LeaseId = @RetryLease1,
        @ExternalId = @OverflowExternalId, @SourceUrl = @SourceUrl,
        @RetrievedAtUtc = @RetryClaimAtUtc, @MimeType = N'application/json',
        @RawContent = @RawContent, @ContentHash = @RawContentHash,
        @SourceItemKeyHash = @OverflowSourceKeyHash,
        @NormalizedSnapshotVersion = @NormalizedSnapshotVersion,
        @NormalizedSnapshotJson = @NormalizedSnapshotJson,
        @NormalizedSnapshotHash = @NormalizedSnapshotHash;
    IF NOT EXISTS (SELECT 1 FROM @RawResult
                   WHERE Succeeded = 0 AND Code = N'maximum-results-reached'
                     AND ItemPublicId IS NULL AND RawObservationPublicId IS NULL)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ImportRunItems
           WHERE ImportRunId = @RetryRunId
             AND SourceItemKeyHash = @OverflowSourceKeyHash)
        THROW 53445, N'Run maximum-results cap was not enforced atomically.', 1;

    DECLARE @RunFailResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), Status TINYINT,
        NextAttemptAtUtc DATETIME2(3) NULL, WasReplay BIT
    );
    INSERT INTO @RunFailResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Fail
        @RunPublicId = @RetryRunPublicId, @LeaseId = @RetryLease1,
        @Stage = N'provider', @ErrorCode = N'temporary-provider-error',
        @SanitizedMessage = N'The provider request failed temporarily.',
        @IsRetryable = 1, @FailedAtUtc = @RetryClaimAtUtc;
    DECLARE @RetryAtUtc DATETIME2(3) = (SELECT NextAttemptAtUtc FROM @RunFailResult);
    IF @RetryAtUtc IS NULL
       OR NOT EXISTS (SELECT 1 FROM @RunFailResult
                      WHERE Succeeded = 1 AND Code = N'retry-scheduled' AND Status = 0)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_OutboxMessages
           WHERE MessageType = N'ImportRunRequested'
             AND AggregateId = CONVERT(NVARCHAR(100), @RetryRunPublicId)) <> 2
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ImportRunItems
           WHERE PublicId = @RetryItemPublicId AND Status = 1
             AND CompletedAtUtc IS NULL)
        THROW 53425, N'A retryable run failure was not durably rescheduled.', 1;

    DECLARE @RetryLease2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @RetrySecondAttemptAtUtc DATETIME2(3) = DATEADD(SECOND, 1, @RetryAtUtc);
    DELETE FROM @ClaimResult;
    INSERT INTO @ClaimResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Claim
        @RunPublicId = @RetryRunPublicId, @LeaseId = @RetryLease2,
        @LeaseSeconds = 300, @NowUtc = @RetrySecondAttemptAtUtc;
    IF NOT EXISTS (SELECT 1 FROM @ClaimResult
                   WHERE Succeeded = 1 AND Code = N'claimed' AND AttemptCount = 2
                     AND RetrievedCount = 1)
        THROW 53426, N'A scheduled retry could not acquire a fresh lease.', 1;

    /* Simulate an empty provider replay after a crash: the normalized item must
       be recoverable without fetching or exposing its immutable raw payload. */
    DECLARE @PendingItems TABLE
    (
        ItemPublicId UNIQUEIDENTIFIER,
        RawObservationPublicId UNIQUEIDENTIFIER,
        ExternalId NVARCHAR(250),
        NormalizedSnapshotVersion SMALLINT,
        NormalizedSnapshotJson NVARCHAR(MAX),
        NormalizedSnapshotHash BINARY(32)
    );
    INSERT INTO @PendingItems
    EXEC dbo.FundingPlatform_usp_ImportRunItem_ListPending
        @RunPublicId = @RetryRunPublicId,
        @LeaseId = @RetryLease2,
        @BatchSize = 25,
        @NowUtc = @RetrySecondAttemptAtUtc;
    IF (SELECT COUNT_BIG(1) FROM @PendingItems) <> 1
       OR NOT EXISTS
          (SELECT 1 FROM @PendingItems
           WHERE ItemPublicId = @RetryItemPublicId
             AND RawObservationPublicId = @RawPublicId
             AND ExternalId = @RawExternalId
             AND NormalizedSnapshotVersion = @NormalizedSnapshotVersion
             AND NormalizedSnapshotJson = @NormalizedSnapshotJson
             AND NormalizedSnapshotHash = @NormalizedSnapshotHash)
        THROW 53439, N'A pending normalized item could not be durably rehydrated.', 1;

    DELETE FROM @StageResult;
    INSERT INTO @StageResult
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_StageExternal
        @FundingSourceId = @FundingSourceId,
        @ExpectedProviderCode = N'grants-gov',
        @ExternalId = @ReferenceNumber,
        @SourceItemKeyHash = @StageSourceKeyHash,
        @SourceUrl = @SourceUrl,
        @CanonicalUrlHash = @StageCanonicalUrlHash,
        @ObservedAtUtc = @RawRetrievedAtUtc,
        @Slug = @StageSlug,
        @Title = N'Smoke funding opportunity',
        @Description = N'Public official fixture for durable acquisition.',
        @Summary = N'Durable acquisition smoke fixture.',
        @SponsorName = N'Smoke official sponsor',
        @SponsorUrl = N'https://www.grants.gov/',
        @ApplicationUrl = @SourceUrl,
        @FundingTypeId = NULL,
        @Currency = NULL,
        @MinAmount = NULL,
        @MaxAmount = NULL,
        @AmountStatus = 0,
        @OpenDate = NULL,
        @CloseDate = NULL,
        @DeadlineType = 0,
        @DeadlinePrecision = 0,
        @EligibilityDescription = N'Eligible nonprofit organizations.',
        @Objectives = N'Community impact.',
        @RequiresCofunding = NULL,
        @CofundingPercentage = NULL,
        @DataQualityScore = 85,
        @SnapshotJson = @StageSnapshot,
        @ContentHash = @StageContentHash;
    IF NOT EXISTS (SELECT 1 FROM @StageResult
                   WHERE Succeeded = 1 AND Code = N'unchanged')
        THROW 53440, N'A rehydrated item did not safely replay editorial staging.', 1;

    DELETE FROM @ItemCompleteResult;
    INSERT INTO @ItemCompleteResult
    EXEC dbo.FundingPlatform_usp_ImportRunItem_Complete
        @RunPublicId = @RetryRunPublicId, @LeaseId = @RetryLease2,
        @ItemPublicId = @RetryItemPublicId, @OutcomeCode = N'unchanged',
        @OpportunityPublicId = NULL,
        @CompletedAtUtc = @RetrySecondAttemptAtUtc;
    IF NOT EXISTS (SELECT 1 FROM @ItemCompleteResult
                   WHERE Succeeded = 1 AND Code = N'completed' AND WasReplay = 0)
        THROW 53441, N'A rehydrated item did not complete.', 1;

    DELETE FROM @RunCompleteResult;
    INSERT INTO @RunCompleteResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Complete
        @RunPublicId = @RetryRunPublicId, @LeaseId = @RetryLease2,
        @CompletedAtUtc = @RetrySecondAttemptAtUtc;
    IF NOT EXISTS (SELECT 1 FROM @RunCompleteResult
                   WHERE Succeeded = 1 AND Code = N'completed' AND Status = 2)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ImportRuns
           WHERE Id = @RetryRunId AND Status = 2 AND UnchangedCount = 1)
        THROW 53442, N'The rehydrated retry run did not complete.', 1;

    /* A separate terminal failure closes work still marked processing. */
    DELETE FROM @CreateResult;
    DECLARE @TerminalIdempotencyHash BINARY(32) =
        HASHBYTES('SHA2_256', N'idem-terminal-' + @Suffix);
    DECLARE @TerminalRequestHash BINARY(32) =
        HASHBYTES('SHA2_256', N'request-terminal-' + @Suffix);
    INSERT INTO @CreateResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Admin_Create
        @AdminUserPublicId = @AdminPublicId, @FundingSourceId = @FundingSourceId,
        @Keyword = N'terminal fixture', @MaximumResults = 1,
        @IdempotencyKeyHash = @TerminalIdempotencyHash,
        @RequestHash = @TerminalRequestHash,
        @CorrelationId = N'smoketerminalrun';
    DECLARE @TerminalRunPublicId UNIQUEIDENTIFIER = (SELECT RunPublicId FROM @CreateResult);
    DECLARE @TerminalRunId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_ImportRuns WHERE PublicId = @TerminalRunPublicId);
    DECLARE @TerminalLease UNIQUEIDENTIFIER = NEWID();
    DECLARE @TerminalClaimAtUtc DATETIME2(3) = DATEADD(SECOND, 1, SYSUTCDATETIME());
    DELETE FROM @ClaimResult;
    INSERT INTO @ClaimResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Claim
        @RunPublicId = @TerminalRunPublicId, @LeaseId = @TerminalLease,
        @LeaseSeconds = 300, @NowUtc = @TerminalClaimAtUtc;

    DELETE FROM @RawResult;
    INSERT INTO @RawResult
    EXEC dbo.FundingPlatform_usp_RawFundingOpportunity_Record
        @RunPublicId = @TerminalRunPublicId, @LeaseId = @TerminalLease,
        @ExternalId = @RawExternalId, @SourceUrl = @SourceUrl,
        @RetrievedAtUtc = @TerminalClaimAtUtc, @MimeType = N'application/json',
        @RawContent = @RawContent, @ContentHash = @RawContentHash,
        @SourceItemKeyHash = @RawSourceKeyHash,
        @NormalizedSnapshotVersion = @NormalizedSnapshotVersion,
        @NormalizedSnapshotJson = @NormalizedSnapshotJson,
        @NormalizedSnapshotHash = @NormalizedSnapshotHash;
    DECLARE @TerminalItemPublicId UNIQUEIDENTIFIER = (SELECT ItemPublicId FROM @RawResult);

    DELETE FROM @RunFailResult;
    DECLARE @TerminalFailedAtUtc DATETIME2(3) = DATEADD(SECOND, 2, @TerminalClaimAtUtc);
    INSERT INTO @RunFailResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Fail
        @RunPublicId = @TerminalRunPublicId, @LeaseId = @TerminalLease,
        @Stage = N'provider', @ErrorCode = N'permanent-provider-error',
        @SanitizedMessage = N'The provider request failed permanently.',
        @IsRetryable = 0, @FailedAtUtc = @TerminalFailedAtUtc;
    IF NOT EXISTS (SELECT 1 FROM @RunFailResult
                   WHERE Succeeded = 1 AND Code = N'failed' AND Status = 4)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_ImportRuns
                      WHERE Id = @TerminalRunId AND Status = 4
                        AND LeaseId IS NULL AND CompletedAtUtc IS NOT NULL
                        AND FailedCount = 1)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ImportRunItems
           WHERE PublicId = @TerminalItemPublicId AND Status = 3
             AND OutcomeCode = N'failed' AND CompletedAtUtc IS NOT NULL)
        THROW 53427, N'A terminal run failure was not recorded.', 1;

    /* A poisoned delivery must still terminalize if governance is revoked
       before the watchdog sweep; it must never restart acquisition. */
    DELETE FROM @CreateResult;
    DECLARE @RevokedIdempotencyHash BINARY(32) =
        HASHBYTES('SHA2_256', N'idem-revoked-watchdog-' + @Suffix);
    DECLARE @RevokedRequestHash BINARY(32) =
        HASHBYTES('SHA2_256', N'request-revoked-watchdog-' + @Suffix);
    INSERT INTO @CreateResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Admin_Create
        @AdminUserPublicId = @AdminPublicId, @FundingSourceId = @FundingSourceId,
        @Keyword = N'revoked watchdog fixture', @MaximumResults = 1,
        @IdempotencyKeyHash = @RevokedIdempotencyHash,
        @RequestHash = @RevokedRequestHash,
        @CorrelationId = N'smokerevokedwatchdog';
    DECLARE @RevokedRunPublicId UNIQUEIDENTIFIER = (SELECT RunPublicId FROM @CreateResult);
    DECLARE @RevokedWatchdogAtUtc DATETIME2(3) =
        DATEADD(MINUTE, 181, SYSUTCDATETIME());
    UPDATE dbo.FundingPlatform_OutboxMessages
    SET DispatchedAtUtc = DATEADD(MINUTE, -181, @RevokedWatchdogAtUtc),
        AttemptCount = 5, LeaseOwner = NULL, LeaseUntilUtc = NULL
    WHERE MessageType = N'ImportRunRequested'
      AND AggregateId = CONVERT(NVARCHAR(100), @RevokedRunPublicId)
      AND DispatchedAtUtc IS NULL;
    UPDATE dbo.FundingPlatform_FundingSources
    SET IsEnabled = 0, UpdatedAtUtc = SYSUTCDATETIME()
    WHERE Id = @FundingSourceId;

    DECLARE @RevokedWatchdogResult TABLE
        (RunPublicId UNIQUEIDENTIFIER, FundingSourceId INT, ProviderCode NVARCHAR(100));
    INSERT INTO @RevokedWatchdogResult
    EXEC dbo.FundingPlatform_usp_ImportRun_RequeueStranded
        @NowUtc = @RevokedWatchdogAtUtc, @BatchSize = 25;
    IF EXISTS (SELECT 1 FROM @RevokedWatchdogResult
               WHERE RunPublicId = @RevokedRunPublicId)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ImportRuns
           WHERE PublicId = @RevokedRunPublicId AND Status = 5
             AND LastErrorCode = N'source-disabled'
             AND CompletedAtUtc = @RevokedWatchdogAtUtc)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ImportErrors AS errors
           INNER JOIN dbo.FundingPlatform_ImportRuns AS runs
               ON runs.Id = errors.ImportRunId
           WHERE runs.PublicId = @RevokedRunPublicId
             AND errors.ErrorCode = N'source-disabled')
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
           WHERE MessageType = N'ImportRunRequested'
             AND AggregateId = CONVERT(NVARCHAR(100), @RevokedRunPublicId)
             AND DispatchedAtUtc IS NULL)
        THROW 53446, N'Watchdog did not terminalize a poisoned revoked run.', 1;
    UPDATE dbo.FundingPlatform_FundingSources
    SET IsEnabled = 1, UpdatedAtUtc = SYSUTCDATETIME()
    WHERE Id = @FundingSourceId;

    /* Resetting a source to the same schedule slot must not duplicate the run. */
    DECLARE @ScheduleSlotUtc DATETIME2(3) = DATEADD(MINUTE, -1, @NowUtc);
    UPDATE dbo.FundingPlatform_FundingSources
    SET NextRunAtUtc = @ScheduleSlotUtc,
        ConfigurationJson = N'{"providerCode":"grants-gov","defaultKeyword":"nonprofit","maximumResults":100,"autoPublish":false}',
        UpdatedAtUtc = @NowUtc
    WHERE Id = @FundingSourceId;

    DECLARE @ScheduledRuns TABLE
        (RunPublicId UNIQUEIDENTIFIER, FundingSourceId INT, ProviderCode NVARCHAR(100));
    INSERT INTO @ScheduledRuns
    EXEC dbo.FundingPlatform_usp_ImportRun_Scheduler_CreateDue
        @NowUtc = @NowUtc, @BatchSize = 10;
    DECLARE @ScheduledRunPublicId UNIQUEIDENTIFIER =
        (SELECT RunPublicId FROM @ScheduledRuns WHERE FundingSourceId = @FundingSourceId);
    IF @ScheduledRunPublicId IS NULL
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ImportRuns
           WHERE PublicId = @ScheduledRunPublicId AND TriggerType = 1
             AND ScheduleSlotUtc = @ScheduleSlotUtc AND MaximumResults = 25
             AND CorrelationId LIKE N'schedule:%')
        THROW 53428, N'The due scheduler did not create a capped scheduled run.', 1;

    UPDATE dbo.FundingPlatform_FundingSources
    SET NextRunAtUtc = @ScheduleSlotUtc, UpdatedAtUtc = @NowUtc
    WHERE Id = @FundingSourceId;
    DELETE FROM @ScheduledRuns;
    INSERT INTO @ScheduledRuns
    EXEC dbo.FundingPlatform_usp_ImportRun_Scheduler_CreateDue
        @NowUtc = @NowUtc, @BatchSize = 10;
    IF EXISTS (SELECT 1 FROM @ScheduledRuns WHERE FundingSourceId = @FundingSourceId)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_ImportRuns
           WHERE FundingSourceId = @FundingSourceId
             AND TriggerType = 1 AND ScheduleSlotUtc = @ScheduleSlotUtc) <> 1
        THROW 53429, N'Scheduler replay created a duplicate schedule slot.', 1;

    DECLARE @WatchdogResult TABLE
        (RunPublicId UNIQUEIDENTIFIER, FundingSourceId INT, ProviderCode NVARCHAR(100));
    INSERT INTO @WatchdogResult
    EXEC dbo.FundingPlatform_usp_ImportRun_RequeueStranded
        @NowUtc = @NowUtc, @BatchSize = 25;
    IF EXISTS (SELECT 1 FROM @WatchdogResult
               WHERE RunPublicId = @ScheduledRunPublicId)
        THROW 53433, N'Watchdog duplicated a pending request message.', 1;

    UPDATE dbo.FundingPlatform_OutboxMessages
    SET DispatchedAtUtc = DATEADD(MINUTE, -181, @NowUtc), AttemptCount = 5,
        LeaseOwner = NULL, LeaseUntilUtc = NULL
    WHERE MessageType = N'ImportRunRequested'
      AND AggregateId = CONVERT(NVARCHAR(100), @ScheduledRunPublicId)
      AND DispatchedAtUtc IS NULL;
    DELETE FROM @WatchdogResult;
    INSERT INTO @WatchdogResult
    EXEC dbo.FundingPlatform_usp_ImportRun_RequeueStranded
        @NowUtc = @NowUtc, @BatchSize = 25;
    IF NOT EXISTS (SELECT 1 FROM @WatchdogResult
                   WHERE RunPublicId = @ScheduledRunPublicId)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_OutboxMessages
           WHERE MessageType = N'ImportRunRequested'
             AND AggregateId = CONVERT(NVARCHAR(100), @ScheduledRunPublicId)
             AND DispatchedAtUtc IS NULL) <> 1
        THROW 53434, N'Watchdog did not repair a stranded poison delivery.', 1;

    DELETE FROM @WatchdogResult;
    DECLARE @WatchdogReplayAtUtc DATETIME2(3) = DATEADD(MINUTE, 1, @NowUtc);
    INSERT INTO @WatchdogResult
    EXEC dbo.FundingPlatform_usp_ImportRun_RequeueStranded
        @NowUtc = @WatchdogReplayAtUtc, @BatchSize = 25;
    IF EXISTS (SELECT 1 FROM @WatchdogResult
               WHERE RunPublicId = @ScheduledRunPublicId)
        THROW 53435, N'Watchdog duplicated its own pending repair message.', 1;

    UPDATE dbo.FundingPlatform_OutboxMessages
    SET DispatchedAtUtc = DATEADD(MINUTE, -181, @NowUtc),
        LeaseOwner = NULL, LeaseUntilUtc = NULL
    WHERE MessageType = N'ImportRunRequested'
      AND AggregateId = CONVERT(NVARCHAR(100), @ScheduledRunPublicId)
      AND DispatchedAtUtc IS NULL;
    DECLARE @ExhaustedLease UNIQUEIDENTIFIER = NEWID();
    UPDATE dbo.FundingPlatform_ImportRuns
    SET Status = 1, AttemptCount = MaxAttempts,
        LeaseId = @ExhaustedLease,
        LeaseUntilUtc = DATEADD(SECOND, 1, @NowUtc),
        StartedAtUtc = COALESCE(StartedAtUtc, @NowUtc),
        UpdatedAtUtc = @NowUtc
    WHERE PublicId = @ScheduledRunPublicId;

    DELETE FROM @WatchdogResult;
    DECLARE @ExhaustedReclaimAtUtc DATETIME2(3) = DATEADD(SECOND, 2, @NowUtc);
    INSERT INTO @WatchdogResult
    EXEC dbo.FundingPlatform_usp_ImportRun_RequeueStranded
        @NowUtc = @ExhaustedReclaimAtUtc, @BatchSize = 25;
    IF NOT EXISTS (SELECT 1 FROM @WatchdogResult
                   WHERE RunPublicId = @ScheduledRunPublicId)
        THROW 53437, N'Watchdog stranded a max-attempt expired running lease.', 1;

    DELETE FROM @ClaimResult;
    DECLARE @ExhaustedReclaimLease UNIQUEIDENTIFIER = NEWID();
    INSERT INTO @ClaimResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Claim
        @RunPublicId = @ScheduledRunPublicId, @LeaseId = @ExhaustedReclaimLease,
        @LeaseSeconds = 120, @NowUtc = @ExhaustedReclaimAtUtc;
    IF NOT EXISTS (SELECT 1 FROM @ClaimResult
                   WHERE Succeeded = 0 AND Code = N'retries-exhausted')
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ImportRuns
           WHERE PublicId = @ScheduledRunPublicId AND Status = 4
             AND CompletedAtUtc IS NOT NULL)
        THROW 53438, N'An exhausted reclaimed run was not terminalized.', 1;

    IF EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
        WHERE MessageType LIKE N'ImportRun%'
          AND (PayloadJson LIKE N'%HIT-%'
               OR PayloadJson LIKE N'%community%'
               OR PayloadJson LIKE N'%grants.gov%'))
        THROW 53430, N'Import outbox payloads contain source or request content.', 1;

    IF EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
        WHERE MessageType IN (N'ImportRunCompleted', N'ImportRunFailed', N'ImportRunCanceled'))
        THROW 53431, N'Unconsumed terminal events contaminated the shared outbox.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke014;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
    BEGIN
        IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
        ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke014;
    END;
    THROW;
END CATCH;

SELECT N'FundingPlatform durable acquisition smoke passed.' AS Result;
