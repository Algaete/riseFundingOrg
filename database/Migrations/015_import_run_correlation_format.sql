/* FundingPlatform FASE 7A hotfix - unambiguous correlation-id character class. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

ALTER TABLE dbo.FundingPlatform_ImportRuns
    DROP CONSTRAINT FundingPlatform_CK_ImportRuns_Request;

ALTER TABLE dbo.FundingPlatform_ImportRuns WITH CHECK
    ADD CONSTRAINT FundingPlatform_CK_ImportRuns_Request
        CHECK (NULLIF(LTRIM(RTRIM(Keyword)), N'') IS NOT NULL
               AND LEN(Keyword) <= 100
               AND MaximumResults BETWEEN 1 AND 25
               AND NULLIF(LTRIM(RTRIM(CorrelationId)), N'') IS NOT NULL
               AND CorrelationId = LTRIM(RTRIM(CorrelationId))
               AND CorrelationId COLLATE Latin1_General_100_BIN2
                   NOT LIKE N'%[^-A-Za-z0-9:_.]%' COLLATE Latin1_General_100_BIN2
               AND CHARINDEX(CHAR(10), CorrelationId) = 0
               AND CHARINDEX(CHAR(13), CorrelationId) = 0);

ALTER TABLE dbo.FundingPlatform_ImportRuns
    CHECK CONSTRAINT FundingPlatform_CK_ImportRuns_Request;
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
          LIKE N'%[^-A-Za-z0-9:_.]%' COLLATE Latin1_General_100_BIN2
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
