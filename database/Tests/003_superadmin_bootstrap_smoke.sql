SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_usp_SuperAdmin_Bootstrap', N'P') IS NULL
    THROW 52211, N'The SuperAdmin bootstrap procedure is missing.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0
    BEGIN TRANSACTION;
ELSE
    SAVE TRANSACTION FundingPlatform_Smoke003;

BEGIN TRY
    DECLARE @FixtureId UNIQUEIDENTIFIER = NEWID();
    DECLARE @Email NVARCHAR(320) =
        N'admin-' + REPLACE(CONVERT(NVARCHAR(36), @FixtureId), N'-', N'') + N'@example.invalid';
    DECLARE @NormalizedEmail NVARCHAR(320) = UPPER(@Email);
    DECLARE @SecondEmail NVARCHAR(320) = N'another-' + @Email;
    DECLARE @SecondNormalizedEmail NVARCHAR(320) = N'ANOTHER-' + @NormalizedEmail;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @TransactionCountBeforeProcedure INT = @@TRANCOUNT;
    DECLARE @ExistingSuperAdminUserId BIGINT;

    SELECT TOP (1) @ExistingSuperAdminUserId = userRoles.UserId
    FROM dbo.FundingPlatform_UserRoles AS userRoles
    INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
    WHERE roles.NormalizedName = N'SUPERADMIN';

    IF @ExistingSuperAdminUserId IS NOT NULL
        DELETE FROM dbo.FundingPlatform_UserRoles
        WHERE UserId = @ExistingSuperAdminUserId
          AND RoleId = (SELECT Id FROM dbo.FundingPlatform_Roles WHERE NormalizedName = N'SUPERADMIN');

    DECLARE @Result TABLE
    (
        ResultCode TINYINT NOT NULL,
        UserId BIGINT NULL,
        PublicId UNIQUEIDENTIFIER NULL
    );
    INSERT INTO @Result (ResultCode, UserId, PublicId)
    EXEC dbo.FundingPlatform_usp_SuperAdmin_Bootstrap
        @Email = @Email,
        @NormalizedEmail = @NormalizedEmail,
        @DisplayName = N'SQL smoke administrator',
        @PasswordHash = N'smoke-password-hash-not-a-credential',
        @SecurityStamp = N'smoke-security-stamp',
        @PreferredLocale = N'es-CL',
        @NowUtc = @NowUtc;

    DECLARE @UserId BIGINT = (SELECT UserId FROM @Result WHERE ResultCode = 0);
    IF @UserId IS NULL
        THROW 52212, N'The first SuperAdmin was not bootstrapped.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_Users AS users
        INNER JOIN dbo.FundingPlatform_UserRoles AS userRoles ON userRoles.UserId = users.Id
        INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
        WHERE users.Id = @UserId
          AND users.Status = 2
          AND users.EmailConfirmed = 1
          AND users.TwoFactorEnabled = 0
          AND roles.NormalizedName = N'SUPERADMIN'
    )
        THROW 52213, N'The SuperAdmin security state is invalid.', 1;

    DECLARE @SecondResult TABLE
    (
        ResultCode TINYINT NOT NULL,
        UserId BIGINT NULL,
        PublicId UNIQUEIDENTIFIER NULL
    );
    INSERT INTO @SecondResult (ResultCode, UserId, PublicId)
    EXEC dbo.FundingPlatform_usp_SuperAdmin_Bootstrap
        @Email = @SecondEmail,
        @NormalizedEmail = @SecondNormalizedEmail,
        @DisplayName = N'Second SQL smoke administrator',
        @PasswordHash = N'smoke-password-hash-not-a-credential',
        @SecurityStamp = N'smoke-security-stamp-2',
        @PreferredLocale = N'es-CL',
        @NowUtc = @NowUtc;

    IF NOT EXISTS (SELECT 1 FROM @SecondResult WHERE ResultCode = 1)
        THROW 52214, N'The bootstrap allowed a second SuperAdmin.', 1;

    IF @@TRANCOUNT <> @TransactionCountBeforeProcedure
        THROW 52215, N'The bootstrap changed caller transaction ownership.', 1;

    IF @InitialTransactionCount = 0
        ROLLBACK TRANSACTION;
    ELSE
        ROLLBACK TRANSACTION FundingPlatform_Smoke003;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FundingPlatform_Smoke003;
    THROW;
END CATCH;

SELECT CAST(1 AS BIT) AS Succeeded;
