SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_usp_UserSecurityToken_Issue', N'P') IS NULL
    THROW 52301, N'The security token issue procedure is missing.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0
    BEGIN TRANSACTION;
ELSE
    SAVE TRANSACTION FundingPlatform_Smoke004;

BEGIN TRY
    DECLARE @FixtureId UNIQUEIDENTIFIER = NEWID();
    DECLARE @FixtureText NVARCHAR(36) = CONVERT(NVARCHAR(36), @FixtureId);
    DECLARE @Email NVARCHAR(320) =
        N'cooldown-' + REPLACE(@FixtureText, N'-', N'') + N'@example.invalid';
    DECLARE @NormalizedEmail NVARCHAR(320) = UPPER(@Email);
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @InitialHash BINARY(32) = HASHBYTES('SHA2_256', N'initial-' + @FixtureText);
    DECLARE @BlockedHash BINARY(32) = HASHBYTES('SHA2_256', N'blocked-' + @FixtureText);
    DECLARE @ReplacementHash BINARY(32) = HASHBYTES('SHA2_256', N'replacement-' + @FixtureText);
    DECLARE @InitialExpiryUtc DATETIME2(3) = DATEADD(HOUR, 1, @NowUtc);
    DECLARE @BlockedNowUtc DATETIME2(3) = DATEADD(MINUTE, 1, @NowUtc);
    DECLARE @ReplacementNowUtc DATETIME2(3) = DATEADD(MINUTE, 6, @NowUtc);
    DECLARE @Registration TABLE
    (
        ResultCode TINYINT NOT NULL,
        UserId BIGINT NULL,
        PublicId UNIQUEIDENTIFIER NULL
    );

    INSERT INTO @Registration (ResultCode, UserId, PublicId)
    EXEC dbo.FundingPlatform_usp_User_Register
        @Email = @Email,
        @NormalizedEmail = @NormalizedEmail,
        @DisplayName = N'Cooldown SQL smoke',
        @PasswordHash = N'smoke-password-hash-not-a-credential',
        @SecurityStamp = N'smoke-security-stamp',
        @PreferredLocale = N'es-CL',
        @TokenHash = @InitialHash,
        @TokenExpiresAtUtc = @InitialExpiryUtc,
        @RequestedIpHash = NULL,
        @NowUtc = @NowUtc;

    DECLARE @UserId BIGINT = (SELECT UserId FROM @Registration WHERE ResultCode = 0);
    IF @UserId IS NULL
        THROW 52302, N'The cooldown fixture could not be registered.', 1;

    DECLARE @BlockedResult TABLE
    (
        ResultCode TINYINT NOT NULL,
        UserId BIGINT NULL,
        Email NVARCHAR(320) NULL,
        DisplayName NVARCHAR(150) NULL
    );
    INSERT INTO @BlockedResult (ResultCode, UserId, Email, DisplayName)
    EXEC dbo.FundingPlatform_usp_UserSecurityToken_Issue
        @NormalizedEmail = @NormalizedEmail,
        @Purpose = 0,
        @TokenHash = @BlockedHash,
        @ExpiresAtUtc = @InitialExpiryUtc,
        @RequestedIpHash = NULL,
        @NowUtc = @BlockedNowUtc;

    IF NOT EXISTS (SELECT 1 FROM @BlockedResult WHERE ResultCode = 2 AND UserId = @UserId)
       OR EXISTS
       (
           SELECT 1 FROM dbo.FundingPlatform_UserSecurityTokens
           WHERE TokenHash = @BlockedHash
       )
       OR NOT EXISTS
       (
           SELECT 1 FROM dbo.FundingPlatform_UserSecurityTokens
           WHERE TokenHash = @InitialHash AND ConsumedAtUtc IS NULL
       )
        THROW 52303, N'A repeated request replaced the current token during cooldown.', 1;

    DECLARE @ReplacementResult TABLE
    (
        ResultCode TINYINT NOT NULL,
        UserId BIGINT NULL,
        Email NVARCHAR(320) NULL,
        DisplayName NVARCHAR(150) NULL
    );
    INSERT INTO @ReplacementResult (ResultCode, UserId, Email, DisplayName)
    EXEC dbo.FundingPlatform_usp_UserSecurityToken_Issue
        @NormalizedEmail = @NormalizedEmail,
        @Purpose = 0,
        @TokenHash = @ReplacementHash,
        @ExpiresAtUtc = @InitialExpiryUtc,
        @RequestedIpHash = NULL,
        @NowUtc = @ReplacementNowUtc;

    IF NOT EXISTS (SELECT 1 FROM @ReplacementResult WHERE ResultCode = 0 AND UserId = @UserId)
       OR NOT EXISTS
       (
           SELECT 1 FROM dbo.FundingPlatform_UserSecurityTokens
           WHERE TokenHash = @InitialHash AND ConsumedAtUtc IS NOT NULL
       )
       OR NOT EXISTS
       (
           SELECT 1 FROM dbo.FundingPlatform_UserSecurityTokens
           WHERE TokenHash = @ReplacementHash AND ConsumedAtUtc IS NULL
       )
        THROW 52304, N'A token was not replaced after the cooldown elapsed.', 1;

    IF @InitialTransactionCount = 0
        ROLLBACK TRANSACTION;
    ELSE
        ROLLBACK TRANSACTION FundingPlatform_Smoke004;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FundingPlatform_Smoke004;
    THROW;
END CATCH;

SELECT CAST(1 AS BIT) AS Succeeded;
