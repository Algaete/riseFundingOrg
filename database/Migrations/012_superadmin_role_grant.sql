SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_GlobalRole_ListAdministrators
AS
BEGIN
    SET NOCOUNT ON;

    SELECT users.Email,
           roles.Name AS RoleName,
           users.Status,
           users.EmailConfirmed,
           users.TwoFactorEnabled,
           userRoles.CreatedAtUtc AS GrantedAtUtc
    FROM dbo.FundingPlatform_UserRoles AS userRoles
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = userRoles.UserId
    INNER JOIN dbo.FundingPlatform_Roles AS roles
        ON roles.Id = userRoles.RoleId
    WHERE roles.NormalizedName IN (N'ADMIN', N'SUPERADMIN')
    ORDER BY CASE roles.NormalizedName WHEN N'SUPERADMIN' THEN 0 ELSE 1 END,
             users.NormalizedEmail;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_GlobalRole_GrantSuperAdmin
    @NormalizedEmail NVARCHAR(320),
    @ReasonCode NVARCHAR(50),
    @SecurityStamp NVARCHAR(100),
    @OperationId UNIQUEIDENTIFIER,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @NormalizedEmail = UPPER(LTRIM(RTRIM(@NormalizedEmail)));

    IF @NormalizedEmail IS NULL OR LEN(@NormalizedEmail) NOT BETWEEN 3 AND 320
        THROW 52221, N'A normalized target email is required.', 1;
    IF @ReasonCode <> N'owner_authorized_local_promotion'
        THROW 52222, N'The operator grant reason is invalid.', 1;
    IF @SecurityStamp IS NULL OR LEN(@SecurityStamp) NOT BETWEEN 32 AND 100
        THROW 52223, N'A strong replacement security stamp is required.', 1;
    IF @OperationId IS NULL OR @NowUtc IS NULL
        THROW 52224, N'Operation metadata is required.', 1;

    DECLARE @StartedTransaction BIT = 0;
    DECLARE @LockResult INT;
    DECLARE @RoleId SMALLINT;
    DECLARE @UserId BIGINT;
    DECLARE @Email NVARCHAR(320);
    DECLARE @Status TINYINT;
    DECLARE @EmailConfirmed BIT;
    DECLARE @TwoFactorEnabled BIT;
    DECLARE @SecurityVersion INT;
    DECLARE @GrantedAtUtc DATETIME2(3);

    IF @@TRANCOUNT = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE
        SAVE TRANSACTION FP_GrantSuperAdmin;

    BEGIN TRY
        EXEC @LockResult = sys.sp_getapplock
            @Resource = N'FundingPlatform:GlobalRoleGrant',
            @LockMode = N'Exclusive',
            @LockOwner = N'Transaction',
            @LockTimeout = 10000;

        IF @LockResult < 0
            THROW 52225, N'The global role grant lock could not be acquired.', 1;

        SELECT @RoleId = Id
        FROM dbo.FundingPlatform_Roles WITH (UPDLOCK, HOLDLOCK)
        WHERE NormalizedName = N'SUPERADMIN';

        IF @RoleId IS NULL
        BEGIN
            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 4) AS ResultCode,
                   CONVERT(NVARCHAR(320), NULL) AS Email,
                   CONVERT(INT, NULL) AS SecurityVersion,
                   CONVERT(BIT, NULL) AS TwoFactorEnabled,
                   CONVERT(DATETIME2(3), NULL) AS GrantedAtUtc;
            RETURN;
        END;

        SELECT @UserId = Id,
               @Email = Email,
               @Status = Status,
               @EmailConfirmed = EmailConfirmed,
               @TwoFactorEnabled = TwoFactorEnabled,
               @SecurityVersion = SecurityVersion
        FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE NormalizedEmail = @NormalizedEmail;

        IF @UserId IS NULL
        BEGIN
            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 2) AS ResultCode,
                   CONVERT(NVARCHAR(320), NULL) AS Email,
                   CONVERT(INT, NULL) AS SecurityVersion,
                   CONVERT(BIT, NULL) AS TwoFactorEnabled,
                   CONVERT(DATETIME2(3), NULL) AS GrantedAtUtc;
            RETURN;
        END;

        IF @Status <> 2 OR @EmailConfirmed <> 1
        BEGIN
            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 3) AS ResultCode,
                   @Email AS Email,
                   @SecurityVersion AS SecurityVersion,
                   @TwoFactorEnabled AS TwoFactorEnabled,
                   CONVERT(DATETIME2(3), NULL) AS GrantedAtUtc;
            RETURN;
        END;

        SELECT @GrantedAtUtc = CreatedAtUtc
        FROM dbo.FundingPlatform_UserRoles WITH (UPDLOCK, HOLDLOCK)
        WHERE UserId = @UserId
          AND RoleId = @RoleId;

        IF @GrantedAtUtc IS NOT NULL
        BEGIN
            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 1) AS ResultCode,
                   @Email AS Email,
                   @SecurityVersion AS SecurityVersion,
                   @TwoFactorEnabled AS TwoFactorEnabled,
                   @GrantedAtUtc AS GrantedAtUtc;
            RETURN;
        END;

        INSERT INTO dbo.FundingPlatform_UserRoles
            (UserId, RoleId, GrantedByUserId, CreatedAtUtc)
        VALUES
            (@UserId, @RoleId, NULL, @NowUtc);

        UPDATE dbo.FundingPlatform_Users
        SET SecurityStamp = @SecurityStamp,
            SecurityVersion = SecurityVersion + 1,
            UpdatedAtUtc = @NowUtc
        WHERE Id = @UserId;

        IF @@ROWCOUNT <> 1
            THROW 52226, N'The promoted account sessions could not be invalidated.', 1;

        UPDATE dbo.FundingPlatform_RefreshTokens
        SET RevokedAtUtc = @NowUtc,
            RevocationReason = 3
        WHERE UserId = @UserId
          AND RevokedAtUtc IS NULL;

        INSERT INTO dbo.FundingPlatform_AuthenticationEvents
        (
            UserId, EventType, Outcome, ReasonCode, IpHash,
            UserAgent, CorrelationId, CreatedAtUtc
        )
        VALUES
        (
            @UserId, 9, 0, @ReasonCode, NULL,
            N'FundingPlatform.AdminCli',
            CONCAT(N'admin-cli:', CONVERT(NVARCHAR(36), @OperationId)),
            @NowUtc
        );

        SELECT @SecurityVersion = SecurityVersion
        FROM dbo.FundingPlatform_Users
        WHERE Id = @UserId;

        SET @GrantedAtUtc = @NowUtc;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
        SELECT CONVERT(TINYINT, 0) AS ResultCode,
               @Email AS Email,
               @SecurityVersion AS SecurityVersion,
               @TwoFactorEnabled AS TwoFactorEnabled,
               @GrantedAtUtc AS GrantedAtUtc;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            IF @StartedTransaction = 1 ROLLBACK TRANSACTION;
            ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_GrantSuperAdmin;
        END;
        THROW;
    END CATCH;
END;
GO
