SET NOCOUNT ON;
SET XACT_ABORT ON;

CREATE TABLE dbo.FundingPlatform_UserSecurityTokens
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    UserId BIGINT NOT NULL,
    SecurityVersion INT NOT NULL,
    Purpose TINYINT NOT NULL,
    TokenHash BINARY(32) NOT NULL,
    ExpiresAtUtc DATETIME2(3) NOT NULL,
    ConsumedAtUtc DATETIME2(3) NULL,
    RequestedIpHash BINARY(32) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_UserSecurityTokens PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_UserSecurityTokens_TokenHash UNIQUE (TokenHash),
    CONSTRAINT FundingPlatform_FK_UserSecurityTokens_Users FOREIGN KEY (UserId)
        REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_UserSecurityTokens_Purpose CHECK (Purpose BETWEEN 0 AND 3),
    CONSTRAINT FundingPlatform_CK_UserSecurityTokens_SecurityVersion CHECK (SecurityVersion >= 1),
    CONSTRAINT FundingPlatform_CK_UserSecurityTokens_Timestamps CHECK
        (ExpiresAtUtc > CreatedAtUtc AND (ConsumedAtUtc IS NULL OR ConsumedAtUtc >= CreatedAtUtc))
);

CREATE INDEX FundingPlatform_IX_UserSecurityTokens_User_Purpose_Expiry
    ON dbo.FundingPlatform_UserSecurityTokens (UserId, Purpose, ExpiresAtUtc DESC)
    INCLUDE (ConsumedAtUtc, SecurityVersion);

CREATE TABLE dbo.FundingPlatform_UserAuthenticatorKeys
(
    UserId BIGINT NOT NULL,
    EncryptedKey VARBINARY(1000) NOT NULL,
    ConfirmedAtUtc DATETIME2(3) NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_UserAuthenticatorKeys PRIMARY KEY (UserId),
    CONSTRAINT FundingPlatform_FK_UserAuthenticatorKeys_Users FOREIGN KEY (UserId)
        REFERENCES dbo.FundingPlatform_Users (Id)
);

CREATE TABLE dbo.FundingPlatform_UserRecoveryCodes
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    UserId BIGINT NOT NULL,
    CodeHash BINARY(32) NOT NULL,
    HashKeyVersion NVARCHAR(50) NOT NULL,
    ConsumedAtUtc DATETIME2(3) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_UserRecoveryCodes PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_UserRecoveryCodes_KeyVersion_CodeHash
        UNIQUE (HashKeyVersion, CodeHash),
    CONSTRAINT FundingPlatform_FK_UserRecoveryCodes_Users FOREIGN KEY (UserId)
        REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_UserRecoveryCodes_Timestamps CHECK
        (ConsumedAtUtc IS NULL OR ConsumedAtUtc >= CreatedAtUtc)
);

CREATE INDEX FundingPlatform_IX_UserRecoveryCodes_User_Active
    ON dbo.FundingPlatform_UserRecoveryCodes (UserId, CreatedAtUtc DESC)
    INCLUDE (HashKeyVersion, CodeHash)
    WHERE ConsumedAtUtc IS NULL;

CREATE TABLE dbo.FundingPlatform_UserMfaChallenges
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    UserId BIGINT NOT NULL,
    SecurityVersion INT NOT NULL,
    Purpose TINYINT NOT NULL,
    TokenHash BINARY(32) NOT NULL,
    ExpiresAtUtc DATETIME2(3) NOT NULL,
    AttemptCount SMALLINT NOT NULL CONSTRAINT FundingPlatform_DF_UserMfaChallenges_AttemptCount DEFAULT (0),
    MaxAttempts SMALLINT NOT NULL,
    ConsumedAtUtc DATETIME2(3) NULL,
    CreatedIpHash BINARY(32) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_UserMfaChallenges PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_UserMfaChallenges_TokenHash UNIQUE (TokenHash),
    CONSTRAINT FundingPlatform_FK_UserMfaChallenges_Users FOREIGN KEY (UserId)
        REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_UserMfaChallenges_Purpose CHECK (Purpose BETWEEN 0 AND 1),
    CONSTRAINT FundingPlatform_CK_UserMfaChallenges_Attempts CHECK
        (AttemptCount >= 0 AND MaxAttempts BETWEEN 1 AND 20 AND AttemptCount <= MaxAttempts),
    CONSTRAINT FundingPlatform_CK_UserMfaChallenges_Timestamps CHECK
        (ExpiresAtUtc > CreatedAtUtc AND (ConsumedAtUtc IS NULL OR ConsumedAtUtc >= CreatedAtUtc))
);

CREATE INDEX FundingPlatform_IX_UserMfaChallenges_User_Expiry
    ON dbo.FundingPlatform_UserMfaChallenges (UserId, ExpiresAtUtc DESC)
    INCLUDE (Purpose, AttemptCount, MaxAttempts, ConsumedAtUtc, SecurityVersion);

CREATE TABLE dbo.FundingPlatform_RefreshTokens
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    UserId BIGINT NOT NULL,
    SecurityVersion INT NOT NULL,
    MfaAuthenticated BIT NOT NULL CONSTRAINT FundingPlatform_DF_RefreshTokens_MfaAuthenticated DEFAULT (0),
    FamilyId UNIQUEIDENTIFIER NOT NULL,
    TokenHash BINARY(32) NOT NULL,
    JwtId UNIQUEIDENTIFIER NOT NULL,
    ExpiresAtUtc DATETIME2(3) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    RevokedAtUtc DATETIME2(3) NULL,
    ReplacedByTokenId BIGINT NULL,
    RotationGraceUntilUtc DATETIME2(3) NULL,
    RevocationReason TINYINT NULL,
    CreatedIpHash BINARY(32) NULL,
    UserAgent NVARCHAR(300) NULL,
    CONSTRAINT FundingPlatform_PK_RefreshTokens PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_RefreshTokens_TokenHash UNIQUE (TokenHash),
    CONSTRAINT FundingPlatform_UQ_RefreshTokens_JwtId UNIQUE (JwtId),
    CONSTRAINT FundingPlatform_FK_RefreshTokens_Users FOREIGN KEY (UserId)
        REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_RefreshTokens_ReplacedBy FOREIGN KEY (ReplacedByTokenId)
        REFERENCES dbo.FundingPlatform_RefreshTokens (Id),
    CONSTRAINT FundingPlatform_CK_RefreshTokens_SecurityVersion CHECK (SecurityVersion >= 1),
    CONSTRAINT FundingPlatform_CK_RefreshTokens_Reason CHECK
        (RevocationReason IS NULL OR RevocationReason BETWEEN 0 AND 5),
    CONSTRAINT FundingPlatform_CK_RefreshTokens_Timestamps CHECK
        (ExpiresAtUtc > CreatedAtUtc
         AND (RevokedAtUtc IS NULL OR RevokedAtUtc >= CreatedAtUtc)
         AND (RotationGraceUntilUtc IS NULL OR RotationGraceUntilUtc >= RevokedAtUtc)),
    CONSTRAINT FundingPlatform_CK_RefreshTokens_State CHECK
        ((RevokedAtUtc IS NULL
          AND ReplacedByTokenId IS NULL
          AND RotationGraceUntilUtc IS NULL
          AND RevocationReason IS NULL)
         OR
         (RevokedAtUtc IS NOT NULL
          AND RevocationReason IS NOT NULL
          AND ((RevocationReason = 0
                AND ReplacedByTokenId IS NOT NULL
                AND RotationGraceUntilUtc IS NOT NULL)
               OR
               (RevocationReason <> 0
                AND ReplacedByTokenId IS NULL
                AND RotationGraceUntilUtc IS NULL))))
);

CREATE INDEX FundingPlatform_IX_RefreshTokens_User_Family
    ON dbo.FundingPlatform_RefreshTokens (UserId, FamilyId, CreatedAtUtc DESC);

CREATE INDEX FundingPlatform_IX_RefreshTokens_User_Live
    ON dbo.FundingPlatform_RefreshTokens (UserId, ExpiresAtUtc DESC)
    INCLUDE (FamilyId, SecurityVersion)
    WHERE RevokedAtUtc IS NULL;

CREATE TABLE dbo.FundingPlatform_AuthenticationEvents
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    UserId BIGINT NULL,
    EventType TINYINT NOT NULL,
    Outcome TINYINT NOT NULL,
    ReasonCode NVARCHAR(50) NULL,
    IpHash BINARY(32) NULL,
    UserAgent NVARCHAR(300) NULL,
    CorrelationId NVARCHAR(100) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_AuthenticationEvents PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_FK_AuthenticationEvents_Users FOREIGN KEY (UserId)
        REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_AuthenticationEvents_EventType CHECK (EventType BETWEEN 0 AND 15),
    CONSTRAINT FundingPlatform_CK_AuthenticationEvents_Outcome CHECK (Outcome BETWEEN 0 AND 2)
);

CREATE INDEX FundingPlatform_IX_AuthenticationEvents_User_Created
    ON dbo.FundingPlatform_AuthenticationEvents (UserId, CreatedAtUtc DESC)
    INCLUDE (EventType, Outcome, ReasonCode);

CREATE INDEX FundingPlatform_IX_AuthenticationEvents_Created
    ON dbo.FundingPlatform_AuthenticationEvents (CreatedAtUtc DESC)
    INCLUDE (EventType, Outcome, ReasonCode);
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_User_Register
    @Email NVARCHAR(320),
    @NormalizedEmail NVARCHAR(320),
    @DisplayName NVARCHAR(150),
    @PasswordHash NVARCHAR(1000),
    @SecurityStamp NVARCHAR(100),
    @PreferredLocale NVARCHAR(10),
    @TokenHash BINARY(32),
    @TokenExpiresAtUtc DATETIME2(3),
    @RequestedIpHash BINARY(32) = NULL,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartedTransaction BIT = 0;
    DECLARE @UserId BIGINT;
    DECLARE @PublicId UNIQUEIDENTIFIER;

    IF @@TRANCOUNT = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE
        SAVE TRANSACTION FundingPlatform_UserRegister;

    BEGIN TRY
        SELECT @UserId = Id
        FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE NormalizedEmail = @NormalizedEmail;

        IF @UserId IS NOT NULL
        BEGIN
            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 1) AS ResultCode, CONVERT(BIGINT, NULL) AS UserId,
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
            1, 0, 0, 1, 0, @PreferredLocale, @NowUtc, @NowUtc
        );

        SET @UserId = CONVERT(BIGINT, SCOPE_IDENTITY());
        SELECT @PublicId = PublicId
        FROM dbo.FundingPlatform_Users
        WHERE Id = @UserId;

        INSERT INTO dbo.FundingPlatform_UserSecurityTokens
        (
            UserId, SecurityVersion, Purpose, TokenHash, ExpiresAtUtc,
            RequestedIpHash, CreatedAtUtc
        )
        VALUES
        (
            @UserId, 1, 0, @TokenHash, @TokenExpiresAtUtc,
            @RequestedIpHash, @NowUtc
        );

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
        SELECT CONVERT(TINYINT, 0) AS ResultCode, @UserId AS UserId, @PublicId AS PublicId;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            IF @StartedTransaction = 1 ROLLBACK TRANSACTION;
            ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FundingPlatform_UserRegister;
        END;
        THROW;
    END CATCH;
END;
GO

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

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_User_VerifyEmail
    @TokenHash BINARY(32),
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartedTransaction BIT = 0;
    DECLARE @TokenId BIGINT;
    DECLARE @UserId BIGINT;
    DECLARE @SecurityVersion INT;

    IF @@TRANCOUNT = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE
        SAVE TRANSACTION FundingPlatform_VerifyEmail;

    BEGIN TRY
        SELECT
            @TokenId = token.Id,
            @UserId = token.UserId,
            @SecurityVersion = token.SecurityVersion
        FROM dbo.FundingPlatform_UserSecurityTokens AS token WITH (UPDLOCK, HOLDLOCK)
        WHERE token.TokenHash = @TokenHash
          AND token.Purpose = 0
          AND token.ConsumedAtUtc IS NULL
          AND token.ExpiresAtUtc > @NowUtc;

        IF @TokenId IS NULL OR NOT EXISTS
        (
            SELECT 1
            FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
            WHERE Id = @UserId
              AND SecurityVersion = @SecurityVersion
              AND Status = 1
              AND EmailConfirmed = 0
        )
        BEGIN
            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 1) AS ResultCode;
            RETURN;
        END;

        UPDATE dbo.FundingPlatform_UserSecurityTokens
        SET ConsumedAtUtc = @NowUtc
        WHERE Id = @TokenId;

        UPDATE dbo.FundingPlatform_Users
        SET EmailConfirmed = 1,
            Status = 2,
            UpdatedAtUtc = @NowUtc
        WHERE Id = @UserId;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
        SELECT CONVERT(TINYINT, 0) AS ResultCode;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            IF @StartedTransaction = 1 ROLLBACK TRANSACTION;
            ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FundingPlatform_VerifyEmail;
        END;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_User_ResetPassword
    @TokenHash BINARY(32),
    @PasswordHash NVARCHAR(1000),
    @SecurityStamp NVARCHAR(100),
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartedTransaction BIT = 0;
    DECLARE @TokenId BIGINT;
    DECLARE @UserId BIGINT;
    DECLARE @SecurityVersion INT;

    IF @@TRANCOUNT = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE
        SAVE TRANSACTION FundingPlatform_ResetPassword;

    BEGIN TRY
        SELECT
            @TokenId = token.Id,
            @UserId = token.UserId,
            @SecurityVersion = token.SecurityVersion
        FROM dbo.FundingPlatform_UserSecurityTokens AS token WITH (UPDLOCK, HOLDLOCK)
        WHERE token.TokenHash = @TokenHash
          AND token.Purpose = 1
          AND token.ConsumedAtUtc IS NULL
          AND token.ExpiresAtUtc > @NowUtc;

        IF @TokenId IS NULL OR NOT EXISTS
        (
            SELECT 1
            FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
            WHERE Id = @UserId
              AND SecurityVersion = @SecurityVersion
              AND Status = 2
              AND EmailConfirmed = 1
        )
        BEGIN
            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 1) AS ResultCode;
            RETURN;
        END;

        UPDATE dbo.FundingPlatform_UserSecurityTokens
        SET ConsumedAtUtc = @NowUtc
        WHERE Id = @TokenId;

        UPDATE dbo.FundingPlatform_Users
        SET PasswordHash = @PasswordHash,
            SecurityStamp = @SecurityStamp,
            SecurityVersion = SecurityVersion + 1,
            AccessFailedCount = 0,
            LockoutEndUtc = NULL,
            UpdatedAtUtc = @NowUtc
        WHERE Id = @UserId;

        UPDATE dbo.FundingPlatform_RefreshTokens
        SET RevokedAtUtc = @NowUtc,
            RevocationReason = 3
        WHERE UserId = @UserId
          AND RevokedAtUtc IS NULL;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
        SELECT CONVERT(TINYINT, 0) AS ResultCode;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            IF @StartedTransaction = 1 ROLLBACK TRANSACTION;
            ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FundingPlatform_ResetPassword;
        END;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_RefreshToken_Rotate
    @CurrentTokenHash BINARY(32),
    @ReplacementTokenHash BINARY(32),
    @ReplacementJwtId UNIQUEIDENTIFIER,
    @ReplacementExpiresAtUtc DATETIME2(3),
    @CreatedIpHash BINARY(32) = NULL,
    @UserAgent NVARCHAR(300) = NULL,
    @NowUtc DATETIME2(3),
    @GraceUntilUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartedTransaction BIT = 0;
    DECLARE @TokenId BIGINT;
    DECLARE @UserId BIGINT;
    DECLARE @SecurityVersion INT;
    DECLARE @FamilyId UNIQUEIDENTIFIER;
    DECLARE @StoredMfaAuthenticated BIT;
    DECLARE @ExpiresAtUtc DATETIME2(3);
    DECLARE @RevokedAtUtc DATETIME2(3);
    DECLARE @ReplacedByTokenId BIGINT;
    DECLARE @RotationGraceUntilUtc DATETIME2(3);
    DECLARE @RevocationReason TINYINT;
    DECLARE @ReplacementTokenId BIGINT;

    IF @@TRANCOUNT = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE
        SAVE TRANSACTION FundingPlatform_RotateRefresh;

    BEGIN TRY
        SELECT
            @TokenId = Id,
            @UserId = UserId,
            @SecurityVersion = SecurityVersion,
            @StoredMfaAuthenticated = MfaAuthenticated,
            @FamilyId = FamilyId,
            @ExpiresAtUtc = ExpiresAtUtc,
            @RevokedAtUtc = RevokedAtUtc,
            @ReplacedByTokenId = ReplacedByTokenId,
            @RotationGraceUntilUtc = RotationGraceUntilUtc,
            @RevocationReason = RevocationReason
        FROM dbo.FundingPlatform_RefreshTokens WITH (UPDLOCK, HOLDLOCK)
        WHERE TokenHash = @CurrentTokenHash;

        IF @TokenId IS NULL
        BEGIN
            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 1) AS ResultCode;
            RETURN;
        END;

        IF @RevokedAtUtc IS NOT NULL
        BEGIN
            IF @RevocationReason = 0
               AND @ReplacedByTokenId IS NOT NULL
               AND @RotationGraceUntilUtc >= @NowUtc
            BEGIN
                IF @StartedTransaction = 1 COMMIT TRANSACTION;
                SELECT CONVERT(TINYINT, 5) AS ResultCode;
                RETURN;
            END;

            UPDATE dbo.FundingPlatform_RefreshTokens
            SET RevokedAtUtc = COALESCE(RevokedAtUtc, @NowUtc),
                RevocationReason = CASE WHEN RevokedAtUtc IS NULL THEN 2 ELSE RevocationReason END
            WHERE UserId = @UserId
              AND FamilyId = @FamilyId
              AND RevokedAtUtc IS NULL;

            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 3) AS ResultCode;
            RETURN;
        END;

        IF @ExpiresAtUtc <= @NowUtc
        BEGIN
            UPDATE dbo.FundingPlatform_RefreshTokens
            SET RevokedAtUtc = @NowUtc,
                RevocationReason = 5
            WHERE Id = @TokenId;

            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 2) AS ResultCode;
            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
            WHERE Id = @UserId
              AND SecurityVersion = @SecurityVersion
              AND Status = 2
              AND EmailConfirmed = 1
        )
        BEGIN
            UPDATE dbo.FundingPlatform_RefreshTokens
            SET RevokedAtUtc = @NowUtc,
                RevocationReason = 3
            WHERE UserId = @UserId
              AND FamilyId = @FamilyId
              AND RevokedAtUtc IS NULL;

            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 4) AS ResultCode;
            RETURN;
        END;

        INSERT INTO dbo.FundingPlatform_RefreshTokens
        (
            UserId, SecurityVersion, MfaAuthenticated, FamilyId, TokenHash, JwtId,
            ExpiresAtUtc, CreatedAtUtc, CreatedIpHash, UserAgent
        )
        VALUES
        (
            @UserId, @SecurityVersion, @StoredMfaAuthenticated, @FamilyId, @ReplacementTokenHash, @ReplacementJwtId,
            @ReplacementExpiresAtUtc, @NowUtc, @CreatedIpHash, @UserAgent
        );

        SET @ReplacementTokenId = CONVERT(BIGINT, SCOPE_IDENTITY());

        UPDATE dbo.FundingPlatform_RefreshTokens
        SET RevokedAtUtc = @NowUtc,
            ReplacedByTokenId = @ReplacementTokenId,
            RotationGraceUntilUtc = @GraceUntilUtc,
            RevocationReason = 0
        WHERE Id = @TokenId;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;

        SELECT
            CONVERT(TINYINT, 0) AS ResultCode,
            users.Id AS UserId,
            users.PublicId,
            users.Email,
            users.DisplayName,
            users.SecurityVersion,
            users.TwoFactorEnabled,
            @StoredMfaAuthenticated AS MfaAuthenticated,
            @FamilyId AS FamilyId
        FROM dbo.FundingPlatform_Users AS users
        WHERE users.Id = @UserId;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            IF @StartedTransaction = 1 ROLLBACK TRANSACTION;
            ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FundingPlatform_RotateRefresh;
        END;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_RefreshToken_RevokeFamily
    @TokenHash BINARY(32),
    @Reason TINYINT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartedTransaction BIT = 0;
    DECLARE @UserId BIGINT;
    DECLARE @FamilyId UNIQUEIDENTIFIER;

    IF @@TRANCOUNT = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE
        SAVE TRANSACTION FundingPlatform_RevokeRefresh;

    BEGIN TRY
        SELECT @UserId = UserId, @FamilyId = FamilyId
        FROM dbo.FundingPlatform_RefreshTokens WITH (UPDLOCK, HOLDLOCK)
        WHERE TokenHash = @TokenHash;

        IF @UserId IS NOT NULL
        BEGIN
            UPDATE dbo.FundingPlatform_RefreshTokens
            SET RevokedAtUtc = @NowUtc,
                RevocationReason = @Reason
            WHERE UserId = @UserId
              AND FamilyId = @FamilyId
              AND RevokedAtUtc IS NULL;
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
        SELECT CONVERT(TINYINT, CASE WHEN @UserId IS NULL THEN 1 ELSE 0 END) AS ResultCode;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            IF @StartedTransaction = 1 ROLLBACK TRANSACTION;
            ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FundingPlatform_RevokeRefresh;
        END;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_User_InvalidateSessions
    @UserId BIGINT,
    @SecurityStamp NVARCHAR(100),
    @Reason TINYINT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartedTransaction BIT = 0;

    IF @@TRANCOUNT = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE
        SAVE TRANSACTION FundingPlatform_Invalidate;

    BEGIN TRY
        UPDATE dbo.FundingPlatform_Users WITH (UPDLOCK)
        SET SecurityStamp = @SecurityStamp,
            SecurityVersion = SecurityVersion + 1,
            UpdatedAtUtc = @NowUtc
        WHERE Id = @UserId;

        IF @@ROWCOUNT = 0
        BEGIN
            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 1) AS ResultCode;
            RETURN;
        END;

        UPDATE dbo.FundingPlatform_RefreshTokens
        SET RevokedAtUtc = @NowUtc,
            RevocationReason = @Reason
        WHERE UserId = @UserId
          AND RevokedAtUtc IS NULL;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
        SELECT CONVERT(TINYINT, 0) AS ResultCode;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            IF @StartedTransaction = 1 ROLLBACK TRANSACTION;
            ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FundingPlatform_Invalidate;
        END;
        THROW;
    END CATCH;
END;
GO
