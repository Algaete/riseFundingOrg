/* Import queue receipts and retry state, scoped to one already-persisted run.
   No scheduler, new runs, deleted events, attempt resets or broad runtime grants. */
SET XACT_ABORT ON;
GO
CREATE INDEX FundingPlatform_IX_OutboxMessages_ImportDelivery
    ON dbo.FundingPlatform_OutboxMessages
        (MessageType, AggregateType, AggregateId, AvailableAtUtc)
    WHERE DispatchedAtUtc IS NULL;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ImportRun_QueueDelivery
    @RunPublicId UNIQUEIDENTIFIER,
    @ConfirmReceipt BIT = 0
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @RunPublicId IS NULL OR @RunPublicId = '00000000-0000-0000-0000-000000000000'
       OR @ConfirmReceipt IS NULL
        THROW 52470, N'A valid run and receipt flag are required.', 1;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    IF @ConfirmReceipt = 1
    BEGIN
        /* Receipt proves the durable queue owns this delivery. Future retries are
           not acknowledged early. Native queue redelivery survives worker crashes. */
        UPDATE dbo.FundingPlatform_OutboxMessages
        SET DispatchedAtUtc = @NowUtc, LeaseOwner = NULL, LeaseUntilUtc = NULL,
            LastError = NULL
        WHERE MessageType = N'ImportRunRequested' AND AggregateType = N'ImportRun'
          AND AggregateId = CONVERT(NVARCHAR(100), @RunPublicId)
          AND AvailableAtUtc <= @NowUtc AND DispatchedAtUtc IS NULL
          AND (LeaseUntilUtc IS NULL OR LeaseUntilUtc <= @NowUtc)
          AND EXISTS (SELECT 1 FROM dbo.FundingPlatform_ImportRuns WHERE PublicId = @RunPublicId);
    END;

    SELECT Status, NextAttemptAtUtc, LeaseUntilUtc
    FROM dbo.FundingPlatform_ImportRuns
    WHERE PublicId = @RunPublicId;
END;
GO
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ImportRun_QueueDelivery
    TO FundingPlatform_GeneralWorkerRole;
GO
