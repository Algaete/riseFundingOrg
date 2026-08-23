SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FundingPlatform_Smoke006;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @Subject NVARCHAR(255) = CONVERT(NVARCHAR(36), NEWID());
    DECLARE @Email NVARCHAR(320) = N'sso-' + REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'') + N'@example.invalid';
    DECLARE @NormalizedEmail NVARCHAR(320) = UPPER(@Email);
    DECLARE @TokenHash BINARY(32) = HASHBYTES('SHA2_256', CONVERT(NVARCHAR(36), NEWID()));
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @ExpiresAtUtc DATETIME2(3) = DATEADD(MINUTE, 3, @NowUtc);
    DECLARE @Result TABLE (ResultCode TINYINT, UserId BIGINT NULL, PublicId UNIQUEIDENTIFIER NULL);

    INSERT INTO @Result
    EXEC dbo.FundingPlatform_usp_ExternalIdentity_Complete
        @Provider = N'entra', @Issuer = N'https://login.microsoftonline.com/test/v2.0',
        @ProviderSubject = @Subject, @Email = @Email, @NormalizedEmail = @NormalizedEmail,
        @DisplayName = N'Entra SQL smoke', @PasswordHash = N'unreachable-smoke-password-hash',
        @SecurityStamp = N'smoke-security-stamp', @HandoffTokenHash = @TokenHash,
        @HandoffExpiresAtUtc = @ExpiresAtUtc, @NowUtc = @NowUtc;

    DECLARE @UserId BIGINT = (SELECT UserId FROM @Result WHERE ResultCode = 1);
    IF @UserId IS NULL
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_UserExternalLogins WHERE UserId = @UserId)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_ExternalAuthHandoffs WHERE UserId = @UserId AND ConsumedAtUtc IS NULL)
        THROW 52601, N'External identity creation or handoff persistence failed.', 1;

    DECLARE @Consumed TABLE (ResultCode TINYINT, UserId BIGINT NULL);
    INSERT INTO @Consumed EXEC dbo.FundingPlatform_usp_ExternalAuthHandoff_Consume
        @TokenHash = @TokenHash, @NowUtc = @NowUtc;
    IF NOT EXISTS (SELECT 1 FROM @Consumed WHERE ResultCode = 0 AND UserId = @UserId)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_ExternalAuthHandoffs WHERE TokenHash = @TokenHash AND ConsumedAtUtc IS NOT NULL)
        THROW 52602, N'External handoff was not consumed atomically.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FundingPlatform_Smoke006;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION FundingPlatform_Smoke006;
    THROW;
END CATCH;

SELECT CAST(1 AS BIT) AS Succeeded;
