/* Receipt isolation and runtime permissions. All synthetic rows/users roll back. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @Impersonated BIT = 0;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke047;
BEGIN TRY
    DECLARE @Run UNIQUEIDENTIFIER = NEWID(), @Other UNIQUEIDENTIFIER = NEWID();
    DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @Source INT = (SELECT TOP (1) Id FROM dbo.FundingPlatform_FundingSources ORDER BY Id);
    IF @Source IS NULL THROW 55470, N'A seeded source is required.', 1;
    INSERT dbo.FundingPlatform_ImportRuns
        (PublicId, FundingSourceId, TriggerType, Status, Keyword, MaximumResults, CorrelationId,
         AttemptCount, MaxAttempts, RetryBaseDelaySeconds, NextAttemptAtUtc, CreatedAtUtc, UpdatedAtUtc)
    SELECT value, @Source, 2, 0, N'on-demand-smoke', 1, N'smoke047', 2, 3, 5, @Now, @Now, @Now
    FROM (VALUES (@Run), (@Other)) AS runs(value);

    DECLARE @Due UNIQUEIDENTIFIER = NEWID(), @Future UNIQUEIDENTIFIER = NEWID(),
        @OtherEvent UNIQUEIDENTIFIER = NEWID(), @Document UNIQUEIDENTIFIER = NEWID(),
        @Leased UNIQUEIDENTIFIER = NEWID();
    INSERT dbo.FundingPlatform_OutboxMessages
        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson, OccurredAtUtc, AvailableAtUtc)
    SELECT eventId, messageType, N'ImportRun', CONVERT(NVARCHAR(100), runId), N'{}', @Now, available
    FROM (VALUES
        (@Due, N'ImportRunRequested', @Run, @Now),
        (@Future, N'ImportRunRequested', @Run, DATEADD(HOUR, 1, @Now)),
        (@OtherEvent, N'ImportRunRequested', @Other, @Now),
        (@Document, N'SourceDocumentExtractionRequested', @Run, @Now),
        (@Leased, N'ImportRunRequested', @Run, @Now)
    ) AS events(eventId, messageType, runId, available);
    UPDATE dbo.FundingPlatform_OutboxMessages
    SET LeaseOwner = N'existing-dispatcher', LeaseUntilUtc = DATEADD(MINUTE, 10, @Now)
    WHERE MessageId = @Leased;

    DECLARE @Delivery TABLE(Status TINYINT, NextAttemptAtUtc DATETIME2(3), LeaseUntilUtc DATETIME2(3));
    INSERT @Delivery EXEC dbo.FundingPlatform_usp_ImportRun_QueueDelivery @Run, 0;
    IF NOT EXISTS (SELECT 1 FROM @Delivery WHERE Status = 0 AND NextAttemptAtUtc = @Now)
        THROW 55471, N'Retry state was not preserved.', 1;
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages WHERE MessageId = @Due AND DispatchedAtUtc IS NOT NULL)
        THROW 55472, N'A state read acknowledged a delivery.', 1;

    CREATE USER FundingPlatform_Smoke047Worker WITHOUT LOGIN;
    ALTER ROLE FundingPlatform_GeneralWorkerRole ADD MEMBER FundingPlatform_Smoke047Worker;
    CREATE USER FundingPlatform_Smoke047Api WITHOUT LOGIN;
    ALTER ROLE FundingPlatform_ApiRuntimeRole ADD MEMBER FundingPlatform_Smoke047Api;
    EXECUTE AS USER = N'FundingPlatform_Smoke047Api';
    SET @Impersonated = 1;
    IF COALESCE(HAS_PERMS_BY_NAME(N'dbo.FundingPlatform_usp_ImportRun_QueueDelivery', N'OBJECT', N'EXECUTE'), 0) <> 0
        THROW 55473, N'API acquired a worker-only permission.', 1;
    REVERT; SET @Impersonated = 0;
    EXECUTE AS USER = N'FundingPlatform_Smoke047Worker';
    SET @Impersonated = 1;
    DELETE @Delivery;
    INSERT @Delivery EXEC dbo.FundingPlatform_usp_ImportRun_QueueDelivery @Run, 1;
    REVERT; SET @Impersonated = 0;

    IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages WHERE MessageId = @Due AND DispatchedAtUtc IS NOT NULL)
        THROW 55474, N'Durable receipt was not acknowledged.', 1;
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
               WHERE MessageId IN (@Future, @OtherEvent, @Document, @Leased) AND DispatchedAtUtc IS NOT NULL)
        THROW 55475, N'Receipt crossed its run, type, time or lease boundary.', 1;
    DELETE @Delivery;
    INSERT @Delivery EXEC dbo.FundingPlatform_usp_ImportRun_QueueDelivery @Run, 1;
    IF (SELECT AttemptCount FROM dbo.FundingPlatform_ImportRuns WHERE PublicId = @Run) <> 2
        THROW 55476, N'Receipt replay reset or incremented attempts.', 1;
    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_ImportRuns WHERE PublicId IN (@Run, @Other)) <> 2
        THROW 55477, N'Receipt created or removed runs.', 1;
    DECLARE @Missing UNIQUEIDENTIFIER = NEWID();
    DELETE @Delivery;
    INSERT @Delivery EXEC dbo.FundingPlatform_usp_ImportRun_QueueDelivery @Missing, 1;
    IF EXISTS(SELECT 1 FROM @Delivery) THROW 55478, N'Unknown run returned delivery state.', 1;
    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke047;
END TRY
BEGIN CATCH
    IF @Impersonated = 1 REVERT;
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke047;
    THROW;
END CATCH;
