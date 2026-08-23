SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SuperAdmin_Bootstrap
    @Email NVARCHAR(320),
    @NormalizedEmail NVARCHAR(320),
    @DisplayName NVARCHAR(150),
    @PasswordHash NVARCHAR(1000),
    @SecurityStamp NVARCHAR(100),
    @PreferredLocale NVARCHAR(10),
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartedTransaction BIT = 0;
    DECLARE @LockResult INT;
    DECLARE @RoleId SMALLINT;
    DECLARE @UserId BIGINT;
    DECLARE @PublicId UNIQUEIDENTIFIER;

    IF @@TRANCOUNT = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE
        SAVE TRANSACTION FundingPlatform_BootstrapAdmin;

    BEGIN TRY
        EXEC @LockResult = sys.sp_getapplock
            @Resource = N'FundingPlatform:SuperAdminBootstrap',
            @LockMode = N'Exclusive',
            @LockOwner = N'Transaction',
            @LockTimeout = 10000;

        IF @LockResult < 0
            THROW 52201, N'The SuperAdmin bootstrap lock could not be acquired.', 1;

        SELECT @RoleId = Id
        FROM dbo.FundingPlatform_Roles WITH (UPDLOCK, HOLDLOCK)
        WHERE NormalizedName = N'SUPERADMIN';

        IF @RoleId IS NULL
        BEGIN
            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 3) AS ResultCode,
                   CONVERT(BIGINT, NULL) AS UserId,
                   CONVERT(UNIQUEIDENTIFIER, NULL) AS PublicId;
            RETURN;
        END;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.FundingPlatform_UserRoles AS userRoles WITH (UPDLOCK, HOLDLOCK)
            WHERE userRoles.RoleId = @RoleId
        )
        BEGIN
            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 1) AS ResultCode,
                   CONVERT(BIGINT, NULL) AS UserId,
                   CONVERT(UNIQUEIDENTIFIER, NULL) AS PublicId;
            RETURN;
        END;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
            WHERE NormalizedEmail = @NormalizedEmail
        )
        BEGIN
            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 2) AS ResultCode,
                   CONVERT(BIGINT, NULL) AS UserId,
                   CONVERT(UNIQUEIDENTIFIER, NULL) AS PublicId;
            RETURN;
        END;

        INSERT INTO dbo.FundingPlatform_Users
        (
            Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
            SecurityVersion, EmailConfirmed, TwoFactorEnabled, Status,
            AccessFailedCount, PreferredLocale, CreatedAtUtc, UpdatedAtUtc
        )
        VALUES
        (
            @Email, @NormalizedEmail, @DisplayName, @PasswordHash, @SecurityStamp,
            1, 1, 0, 2, 0, @PreferredLocale, @NowUtc, @NowUtc
        );

        SET @UserId = CONVERT(BIGINT, SCOPE_IDENTITY());
        SELECT @PublicId = PublicId
        FROM dbo.FundingPlatform_Users
        WHERE Id = @UserId;

        INSERT INTO dbo.FundingPlatform_UserRoles
            (UserId, RoleId, GrantedByUserId, CreatedAtUtc)
        VALUES
            (@UserId, @RoleId, @UserId, @NowUtc);

        INSERT INTO dbo.FundingPlatform_AuthenticationEvents
            (UserId, EventType, Outcome, ReasonCode, CreatedAtUtc)
        VALUES
            (@UserId, 8, 0, N'superadmin_bootstrap', @NowUtc);

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
        SELECT CONVERT(TINYINT, 0) AS ResultCode, @UserId AS UserId, @PublicId AS PublicId;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            IF @StartedTransaction = 1 ROLLBACK TRANSACTION;
            ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FundingPlatform_BootstrapAdmin;
        END;
        THROW;
    END CATCH;
END;
GO
