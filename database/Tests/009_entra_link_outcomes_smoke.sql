/* Transactional smoke for new and idempotent Entra identity link outcomes. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FundingPlatform_Smoke009;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @Suffix NVARCHAR(32) = REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'');
    DECLARE @UserPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @Email NVARCHAR(320) = N'link-outcome-' + @Suffix + N'@example.invalid';
    DECLARE @Issuer NVARCHAR(300) = N'https://login.microsoftonline.com/smoke-link-outcome/v2.0';
    DECLARE @Subject NVARCHAR(255) = CONVERT(NVARCHAR(36), NEWID());
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, Status, PreferredLocale)
    VALUES
        (@UserPublicId, @Email, UPPER(@Email), N'Entra link outcome smoke',
         N'unreachable-smoke-password-hash', N'entra-link-outcome-smoke', 1, 2, N'es-CL');

    DECLARE @UserId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @UserPublicId);
    DECLARE @FirstResult TABLE
        (ResultCode TINYINT, UserId BIGINT NULL, PublicId UNIQUEIDENTIFIER NULL);

    INSERT INTO @FirstResult
    EXEC dbo.FundingPlatform_usp_ExternalIdentity_Link
        @UserPublicId = @UserPublicId,
        @Provider = N'entra',
        @Issuer = @Issuer,
        @ProviderSubject = @Subject,
        @Email = @Email,
        @NowUtc = @NowUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @FirstResult WHERE ResultCode = 0 AND UserId = @UserId AND PublicId = @UserPublicId)
       OR (SELECT COUNT_BIG(*) FROM dbo.FundingPlatform_UserExternalLogins
           WHERE UserId = @UserId AND Provider = N'entra'
             AND Issuer = @Issuer AND ProviderSubject = @Subject) <> 1
        THROW 52901, N'A newly linked Entra identity did not return ResultCode 0.', 1;

    DECLARE @ExternalLoginId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_UserExternalLogins
         WHERE UserId = @UserId AND Provider = N'entra'
           AND Issuer = @Issuer AND ProviderSubject = @Subject);
    DECLARE @SecondAttemptUtc DATETIME2(3) = DATEADD(SECOND, 1, @NowUtc);
    DECLARE @SecondResult TABLE
        (ResultCode TINYINT, UserId BIGINT NULL, PublicId UNIQUEIDENTIFIER NULL);

    INSERT INTO @SecondResult
    EXEC dbo.FundingPlatform_usp_ExternalIdentity_Link
        @UserPublicId = @UserPublicId,
        @Provider = N'entra',
        @Issuer = @Issuer,
        @ProviderSubject = @Subject,
        @Email = @Email,
        @NowUtc = @SecondAttemptUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @SecondResult WHERE ResultCode = 4 AND UserId = @UserId AND PublicId = @UserPublicId)
       OR (SELECT COUNT_BIG(*) FROM dbo.FundingPlatform_UserExternalLogins
           WHERE UserId = @UserId AND Provider = N'entra'
             AND Issuer = @Issuer AND ProviderSubject = @Subject) <> 1
       OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_UserExternalLogins WHERE Id = @ExternalLoginId)
        THROW 52902, N'An idempotent Entra link retry did not return ResultCode 4.', 1;

    DECLARE @ThirdAttemptUtc DATETIME2(3) = DATEADD(SECOND, 2, @NowUtc);
    DECLARE @ThirdResult TABLE
        (ResultCode TINYINT, UserId BIGINT NULL, PublicId UNIQUEIDENTIFIER NULL);

    INSERT INTO @ThirdResult
    EXEC dbo.FundingPlatform_usp_ExternalIdentity_Link
        @UserPublicId = @UserPublicId,
        @Provider = N'entra',
        @Issuer = @Issuer,
        @ProviderSubject = @Subject,
        @Email = @Email,
        @NowUtc = @ThirdAttemptUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @ThirdResult WHERE ResultCode = 4 AND UserId = @UserId AND PublicId = @UserPublicId)
       OR (SELECT COUNT_BIG(*) FROM dbo.FundingPlatform_UserExternalLogins
           WHERE UserId = @UserId AND Provider = N'entra'
             AND Issuer = @Issuer AND ProviderSubject = @Subject) <> 1
        THROW 52903, N'Repeated Entra link retries are not idempotent.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FundingPlatform_Smoke009;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FundingPlatform_Smoke009;
    THROW;
END CATCH;

SELECT CAST(1 AS BIT) AS Succeeded;
