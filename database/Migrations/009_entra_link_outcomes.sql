/* FundingPlatform - distinguish a newly linked Entra identity from an idempotent retry. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ExternalIdentity_Link
    @UserPublicId UNIQUEIDENTIFIER,
    @Provider NVARCHAR(32),
    @Issuer NVARCHAR(300),
    @ProviderSubject NVARCHAR(255),
    @Email NVARCHAR(320) = NULL,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @UserId BIGINT;
    DECLARE @ExistingUserId BIGINT;
    DECLARE @ResultCode TINYINT;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_ExternalLink;
    BEGIN TRY
        SELECT @UserId = Id
        FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @UserPublicId AND Status = 2;

        IF @UserId IS NULL
            SET @ResultCode = 3;
        ELSE
        BEGIN
            SELECT @ExistingUserId = UserId
            FROM dbo.FundingPlatform_UserExternalLogins WITH (UPDLOCK, HOLDLOCK)
            WHERE Provider = @Provider AND Issuer = @Issuer AND ProviderSubject = @ProviderSubject;

            IF @ExistingUserId IS NOT NULL AND @ExistingUserId <> @UserId
                SET @ResultCode = 1;
            ELSE IF @ExistingUserId = @UserId
                SET @ResultCode = 4;
            ELSE IF EXISTS
            (
                SELECT 1 FROM dbo.FundingPlatform_UserExternalLogins
                WHERE UserId = @UserId AND Provider = @Provider AND Issuer = @Issuer
            )
                SET @ResultCode = 2;
            ELSE
            BEGIN
                INSERT INTO dbo.FundingPlatform_UserExternalLogins
                    (UserId, Provider, Issuer, ProviderSubject, EmailAtLink, CreatedAtUtc, LastLoginAtUtc)
                VALUES
                    (@UserId, @Provider, @Issuer, @ProviderSubject, @Email, @NowUtc, @NowUtc);
                SET @ResultCode = 0;
            END;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
        SELECT @ResultCode AS ResultCode, @UserId AS UserId, @UserPublicId AS PublicId;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION FP_ExternalLink;
        THROW;
    END CATCH;
END;';
