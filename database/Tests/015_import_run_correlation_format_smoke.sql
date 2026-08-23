/* Transactional regression smoke for the FASE 7A correlation-id hotfix. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ConstraintDefinition NVARCHAR(MAX) =
    (SELECT definition
     FROM sys.check_constraints
     WHERE parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_ImportRuns')
       AND name = N'FundingPlatform_CK_ImportRuns_Request');
DECLARE @CreateDefinition NVARCHAR(MAX) = OBJECT_DEFINITION
    (OBJECT_ID(N'dbo.FundingPlatform_usp_ImportRun_Admin_Create'));

IF @ConstraintDefinition IS NULL
   OR CHARINDEX(N'%[^-A-Za-z0-9:_.]%', @ConstraintDefinition) = 0
    THROW 53501, N'The import-run correlation constraint was not repaired.', 1;
IF @CreateDefinition IS NULL
   OR CHARINDEX(N'%[^-A-Za-z0-9:_.]%', @CreateDefinition) = 0
    THROW 53502, N'The manual import correlation validator was not repaired.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke015;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @Suffix NVARCHAR(32) =
        REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'');
    DECLARE @AdminPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @AdminEmail NVARCHAR(320) =
        N'import-hotfix-' + @Suffix + N'@example.invalid';
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@AdminPublicId, @AdminEmail, UPPER(@AdminEmail), N'Import hotfix smoke',
         N'not-a-credential', N'import-hotfix-smoke', 1, 1, 2, N'es-CL');

    DECLARE @AdminUserId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @AdminPublicId);
    DECLARE @AdminRoleId SMALLINT =
        (SELECT Id FROM dbo.FundingPlatform_Roles WHERE NormalizedName = N'ADMIN');
    DECLARE @FundingSourceId INT =
        (SELECT Id FROM dbo.FundingPlatform_FundingSources
         WHERE ProviderCode = N'grants-gov');

    IF @AdminRoleId IS NULL OR @FundingSourceId IS NULL
        THROW 53503, N'The correlation smoke prerequisites are missing.', 1;

    INSERT INTO dbo.FundingPlatform_UserRoles (UserId, RoleId, GrantedByUserId)
    VALUES (@AdminUserId, @AdminRoleId, @AdminUserId);

    DECLARE @CreateResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), RunPublicId UNIQUEIDENTIFIER NULL,
        FundingSourceId INT, SourceName NVARCHAR(150) NULL, Status TINYINT NULL,
        CreatedAtUtc DATETIME2(3) NULL, WasReplay BIT
    );
    DECLARE @ManualCorrelation NVARCHAR(100) =
        N'import-run-' + LEFT(@Suffix, 24);
    DECLARE @IdempotencyKeyHash BINARY(32) =
        HASHBYTES('SHA2_256', N'hotfix-idem-' + @Suffix);
    DECLARE @RequestHash BINARY(32) =
        HASHBYTES('SHA2_256', N'hotfix-request-' + @Suffix);

    INSERT INTO @CreateResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Admin_Create
        @AdminUserPublicId = @AdminPublicId,
        @FundingSourceId = @FundingSourceId,
        @Keyword = N'nonprofit',
        @MaximumResults = 1,
        @IdempotencyKeyHash = @IdempotencyKeyHash,
        @RequestHash = @RequestHash,
        @CorrelationId = @ManualCorrelation;

    IF NOT EXISTS
       (SELECT 1 FROM @CreateResult
        WHERE Succeeded = 1 AND Code = N'created' AND WasReplay = 0)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ImportRuns
           WHERE PublicId = (SELECT RunPublicId FROM @CreateResult)
             AND CorrelationId = @ManualCorrelation)
        THROW 53504, N'A valid hyphenated manual correlation was rejected.', 1;

    DECLARE @ScheduleSlotUtc DATETIME2(3) = DATEADD(MINUTE, -1, @NowUtc);
    UPDATE dbo.FundingPlatform_FundingSources
    SET IsEnabled = 1,
        ComplianceStatus = 1,
        ComplianceApprovedAtUtc = COALESCE(ComplianceApprovedAtUtc, @NowUtc),
        ScheduleIntervalSeconds = COALESCE(ScheduleIntervalSeconds, 86400),
        NextRunAtUtc = @ScheduleSlotUtc,
        ConfigurationJson =
            N'{"providerCode":"grants-gov","defaultKeyword":"nonprofit","maximumResults":1,"autoPublish":false}',
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
           WHERE PublicId = @ScheduledRunPublicId
             AND TriggerType = 1
             AND ScheduleSlotUtc = @ScheduleSlotUtc
             AND CorrelationId LIKE N'schedule:%-%')
        THROW 53505, N'A scheduled correlation with an ISO date was rejected.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke015;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
    BEGIN
        IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
        ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke015;
    END;
    THROW;
END CATCH;

SELECT N'FundingPlatform import correlation hotfix smoke passed.' AS Result;
