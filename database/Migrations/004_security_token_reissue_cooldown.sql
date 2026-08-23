CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_UserSecurityToken_Issue
    @NormalizedEmail NVARCHAR(320),
    @Purpose TINYINT,
    @TokenHash BINARY(32),
    @ExpiresAtUtc DATETIME2(3),
    @RequestedIpHash BINARY(32) = NULL,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartedTransaction BIT = 0;
    DECLARE @UserId BIGINT;
    DECLARE @SecurityVersion INT;
    DECLARE @Email NVARCHAR(320);
    DECLARE @DisplayName NVARCHAR(150);

    IF @@TRANCOUNT = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE
        SAVE TRANSACTION FundingPlatform_TokenIssue;

    BEGIN TRY
        SELECT
            @UserId = Id,
            @SecurityVersion = SecurityVersion,
            @Email = Email,
            @DisplayName = DisplayName
        FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE NormalizedEmail = @NormalizedEmail
          AND ((@Purpose = 0 AND Status = 1 AND EmailConfirmed = 0)
               OR (@Purpose = 1 AND Status = 2 AND EmailConfirmed = 1));

        IF @UserId IS NULL
        BEGIN
            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 1) AS ResultCode,
                   CONVERT(BIGINT, NULL) AS UserId,
                   CONVERT(NVARCHAR(320), NULL) AS Email,
                   CONVERT(NVARCHAR(150), NULL) AS DisplayName;
            RETURN;
        END;

        /*
            Keep the current link valid when a form is submitted repeatedly. The
            endpoint still returns its enumeration-safe accepted response, but it
            neither invalidates the token nor sends another message for five minutes.
        */
        IF EXISTS
        (
            SELECT 1
            FROM dbo.FundingPlatform_UserSecurityTokens
            WHERE UserId = @UserId
              AND Purpose = @Purpose
              AND SecurityVersion = @SecurityVersion
              AND ConsumedAtUtc IS NULL
              AND ExpiresAtUtc > @NowUtc
              AND CreatedAtUtc > DATEADD(MINUTE, -5, @NowUtc)
        )
        BEGIN
            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 2) AS ResultCode,
                   @UserId AS UserId,
                   CONVERT(NVARCHAR(320), NULL) AS Email,
                   CONVERT(NVARCHAR(150), NULL) AS DisplayName;
            RETURN;
        END;

        UPDATE dbo.FundingPlatform_UserSecurityTokens
        SET ConsumedAtUtc = @NowUtc
        WHERE UserId = @UserId
          AND Purpose = @Purpose
          AND ConsumedAtUtc IS NULL;

        INSERT INTO dbo.FundingPlatform_UserSecurityTokens
        (
            UserId, SecurityVersion, Purpose, TokenHash, ExpiresAtUtc,
            RequestedIpHash, CreatedAtUtc
        )
        VALUES
        (
            @UserId, @SecurityVersion, @Purpose, @TokenHash, @ExpiresAtUtc,
            @RequestedIpHash, @NowUtc
        );

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
        SELECT CONVERT(TINYINT, 0) AS ResultCode, @UserId AS UserId,
               @Email AS Email, @DisplayName AS DisplayName;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            IF @StartedTransaction = 1 ROLLBACK TRANSACTION;
            ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FundingPlatform_TokenIssue;
        END;
        THROW;
    END CATCH;
END;
GO
