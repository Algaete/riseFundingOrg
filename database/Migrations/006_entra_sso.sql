/* FundingPlatform - Microsoft Entra SSO identities and one-time handoff grants. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

CREATE TABLE dbo.FundingPlatform_UserExternalLogins
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    UserId BIGINT NOT NULL,
    Provider NVARCHAR(32) NOT NULL,
    Issuer NVARCHAR(300) NOT NULL,
    ProviderSubject NVARCHAR(255) NOT NULL,
    EmailAtLink NVARCHAR(320) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    LastLoginAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_UserExternalLogins PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_FK_UserExternalLogins_Users FOREIGN KEY (UserId)
        REFERENCES dbo.FundingPlatform_Users (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_UQ_UserExternalLogins_Identity
        UNIQUE (Provider, Issuer, ProviderSubject),
    CONSTRAINT FundingPlatform_UQ_UserExternalLogins_UserProvider
        UNIQUE (UserId, Provider, Issuer),
    CONSTRAINT FundingPlatform_CK_UserExternalLogins_Provider
        CHECK (Provider IN (N'entra'))
);

CREATE INDEX FundingPlatform_IX_UserExternalLogins_User
    ON dbo.FundingPlatform_UserExternalLogins (UserId, LastLoginAtUtc DESC);

CREATE TABLE dbo.FundingPlatform_ExternalAuthHandoffs
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    UserId BIGINT NOT NULL,
    TokenHash BINARY(32) NOT NULL,
    SecurityVersion INT NOT NULL,
    ExpiresAtUtc DATETIME2(3) NOT NULL,
    ConsumedAtUtc DATETIME2(3) NULL,
    CreatedIpHash BINARY(32) NULL,
    UserAgent NVARCHAR(300) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_ExternalAuthHandoffs PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_FK_ExternalAuthHandoffs_Users FOREIGN KEY (UserId)
        REFERENCES dbo.FundingPlatform_Users (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_UQ_ExternalAuthHandoffs_TokenHash UNIQUE (TokenHash),
    CONSTRAINT FundingPlatform_CK_ExternalAuthHandoffs_SecurityVersion CHECK (SecurityVersion >= 1),
    CONSTRAINT FundingPlatform_CK_ExternalAuthHandoffs_Timestamps CHECK
        (ExpiresAtUtc > CreatedAtUtc AND (ConsumedAtUtc IS NULL OR ConsumedAtUtc >= CreatedAtUtc))
);

CREATE INDEX FundingPlatform_IX_ExternalAuthHandoffs_UserLive
    ON dbo.FundingPlatform_ExternalAuthHandoffs (UserId, ExpiresAtUtc)
    WHERE ConsumedAtUtc IS NULL;

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ExternalIdentity_Complete
    @Provider NVARCHAR(32),
    @Issuer NVARCHAR(300),
    @ProviderSubject NVARCHAR(255),
    @Email NVARCHAR(320),
    @NormalizedEmail NVARCHAR(320),
    @DisplayName NVARCHAR(150),
    @PasswordHash NVARCHAR(1000),
    @SecurityStamp NVARCHAR(100),
    @HandoffTokenHash BINARY(32),
    @HandoffExpiresAtUtc DATETIME2(3),
    @CreatedIpHash BINARY(32) = NULL,
    @UserAgent NVARCHAR(300) = NULL,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Provider <> N''entra'' OR NULLIF(@Issuer, N'''') IS NULL
       OR NULLIF(@ProviderSubject, N'''') IS NULL
       OR NULLIF(@NormalizedEmail, N'''') IS NULL
       OR @HandoffExpiresAtUtc <= @NowUtc
        THROW 51301, N''External identity input is invalid.'', 1;

    DECLARE @UserId BIGINT;
    DECLARE @PublicId UNIQUEIDENTIFIER;
    DECLARE @ResultCode TINYINT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_ExternalComplete;
    BEGIN TRY
        SELECT @UserId = externalLogin.UserId
        FROM dbo.FundingPlatform_UserExternalLogins AS externalLogin WITH (UPDLOCK, HOLDLOCK)
        WHERE externalLogin.Provider = @Provider
          AND externalLogin.Issuer = @Issuer
          AND externalLogin.ProviderSubject = @ProviderSubject;

        IF @UserId IS NULL
        BEGIN
            IF EXISTS
            (
                SELECT 1 FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
                WHERE NormalizedEmail = @NormalizedEmail
            )
            BEGIN
                SET @ResultCode = 2;
            END
            ELSE
            BEGIN
                INSERT INTO dbo.FundingPlatform_Users
                (
                    Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
                    SecurityVersion, EmailConfirmed, TwoFactorEnabled, Status,
                    PreferredLocale, CreatedAtUtc, UpdatedAtUtc
                )
                VALUES
                (
                    @Email, @NormalizedEmail, @DisplayName, @PasswordHash, @SecurityStamp,
                    1, 1, 0, 2, N''es-CL'', @NowUtc, @NowUtc
                );
                SET @UserId = CONVERT(BIGINT, SCOPE_IDENTITY());

                INSERT INTO dbo.FundingPlatform_UserExternalLogins
                    (UserId, Provider, Issuer, ProviderSubject, EmailAtLink, CreatedAtUtc, LastLoginAtUtc)
                VALUES
                    (@UserId, @Provider, @Issuer, @ProviderSubject, @Email, @NowUtc, @NowUtc);
                SET @ResultCode = 1;
            END;
        END
        ELSE
        BEGIN
            UPDATE dbo.FundingPlatform_UserExternalLogins
            SET EmailAtLink = @Email,
                LastLoginAtUtc = @NowUtc
            WHERE Provider = @Provider
              AND Issuer = @Issuer
              AND ProviderSubject = @ProviderSubject;
        END;

        IF @ResultCode IN (0, 1)
        BEGIN
            IF NOT EXISTS
            (
                SELECT 1 FROM dbo.FundingPlatform_Users
                WHERE Id = @UserId AND Status = 2
            )
            BEGIN
                SET @ResultCode = 3;
            END
            ELSE
            BEGIN
                UPDATE dbo.FundingPlatform_ExternalAuthHandoffs
                SET ConsumedAtUtc = @NowUtc
                WHERE UserId = @UserId AND ConsumedAtUtc IS NULL;

                INSERT INTO dbo.FundingPlatform_ExternalAuthHandoffs
                    (UserId, TokenHash, SecurityVersion, ExpiresAtUtc,
                     CreatedIpHash, UserAgent, CreatedAtUtc)
                SELECT Id, @HandoffTokenHash, SecurityVersion, @HandoffExpiresAtUtc,
                       @CreatedIpHash, @UserAgent, @NowUtc
                FROM dbo.FundingPlatform_Users
                WHERE Id = @UserId;
            END;
        END;

        SELECT @PublicId = PublicId FROM dbo.FundingPlatform_Users WHERE Id = @UserId;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
        SELECT @ResultCode AS ResultCode, @UserId AS UserId, @PublicId AS PublicId;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION FP_ExternalComplete;
        THROW;
    END CATCH;
END;';

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
                SET @ResultCode = 0;
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

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ExternalAuthHandoff_Consume
    @TokenHash BINARY(32),
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @UserId BIGINT;
    DECLARE @SecurityVersion INT;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_ExternalConsume;
    BEGIN TRY
        SELECT @UserId = handoff.UserId, @SecurityVersion = handoff.SecurityVersion
        FROM dbo.FundingPlatform_ExternalAuthHandoffs AS handoff WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_Users AS users WITH (HOLDLOCK)
            ON users.Id = handoff.UserId
           AND users.Status = 2
           AND users.SecurityVersion = handoff.SecurityVersion
        WHERE handoff.TokenHash = @TokenHash
          AND handoff.ConsumedAtUtc IS NULL
          AND handoff.ExpiresAtUtc > @NowUtc;

        IF @UserId IS NOT NULL
            UPDATE dbo.FundingPlatform_ExternalAuthHandoffs
            SET ConsumedAtUtc = @NowUtc
            WHERE TokenHash = @TokenHash AND ConsumedAtUtc IS NULL;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
        SELECT CONVERT(TINYINT, CASE WHEN @UserId IS NULL THEN 1 ELSE 0 END) AS ResultCode,
               @UserId AS UserId;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION FP_ExternalConsume;
        THROW;
    END CATCH;
END;';
