/*
    Transactional smoke test for database/Migrations/002_identity_security.sql.
    All fixture data is rolled back. Raw credentials and tokens are never used here;
    deterministic SHA-256 probe values are sufficient to validate persistence rules.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ExpectedTables TABLE (Name SYSNAME NOT NULL PRIMARY KEY);
INSERT INTO @ExpectedTables (Name)
VALUES
    (N'FundingPlatform_UserSecurityTokens'),
    (N'FundingPlatform_UserAuthenticatorKeys'),
    (N'FundingPlatform_UserRecoveryCodes'),
    (N'FundingPlatform_UserMfaChallenges'),
    (N'FundingPlatform_RefreshTokens'),
    (N'FundingPlatform_AuthenticationEvents');

IF EXISTS
(
    SELECT 1
    FROM @ExpectedTables AS Expected
    WHERE OBJECT_ID(N'dbo.' + Expected.Name, N'U') IS NULL
)
    THROW 52101, N'One or more FASE 3 identity tables are missing.', 1;

DECLARE @ExpectedProcedures TABLE (Name SYSNAME NOT NULL PRIMARY KEY);
INSERT INTO @ExpectedProcedures (Name)
VALUES
    (N'FundingPlatform_usp_User_Register'),
    (N'FundingPlatform_usp_UserSecurityToken_Issue'),
    (N'FundingPlatform_usp_User_VerifyEmail'),
    (N'FundingPlatform_usp_User_ResetPassword'),
    (N'FundingPlatform_usp_RefreshToken_Rotate'),
    (N'FundingPlatform_usp_RefreshToken_RevokeFamily'),
    (N'FundingPlatform_usp_User_InvalidateSessions');

IF EXISTS
(
    SELECT 1
    FROM @ExpectedProcedures AS Expected
    WHERE OBJECT_ID(N'dbo.' + Expected.Name, N'P') IS NULL
)
    THROW 52102, N'One or more FASE 3 identity procedures are missing.', 1;

IF EXISTS
(
    SELECT 1
    FROM sys.objects AS ObjectDefinition
    WHERE LEFT(ObjectDefinition.name COLLATE DATABASE_DEFAULT, 16)
          = N'FundingPlatform_' COLLATE DATABASE_DEFAULT
      AND ObjectDefinition.type IN (N'U', N'P')
      AND SCHEMA_NAME(ObjectDefinition.schema_id) COLLATE DATABASE_DEFAULT
          <> N'dbo' COLLATE DATABASE_DEFAULT
)
    THROW 52103, N'A FundingPlatform identity object is outside dbo.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0
    BEGIN TRANSACTION;
ELSE
    SAVE TRANSACTION FundingPlatform_Smoke002;

BEGIN TRY
    DECLARE @FixtureId UNIQUEIDENTIFIER = NEWID();
    DECLARE @FixtureText NVARCHAR(36) = CONVERT(NVARCHAR(36), @FixtureId);
    DECLARE @Email NVARCHAR(320) =
        N'identity-' + REPLACE(@FixtureText, N'-', N'') + N'@example.invalid';
    DECLARE @NormalizedEmail NVARCHAR(320) = UPPER(@Email);
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @VerificationHash BINARY(32) = HASHBYTES('SHA2_256', N'verify-' + @FixtureText);
    DECLARE @ResetHash BINARY(32) = HASHBYTES('SHA2_256', N'reset-' + @FixtureText);
    DECLARE @RefreshHash1 BINARY(32) = HASHBYTES('SHA2_256', N'refresh-1-' + @FixtureText);
    DECLARE @RefreshHash2 BINARY(32) = HASHBYTES('SHA2_256', N'refresh-2-' + @FixtureText);
    DECLARE @RefreshHash3 BINARY(32) = HASHBYTES('SHA2_256', N'refresh-3-' + @FixtureText);
    DECLARE @DuplicateHash BINARY(32) = HASHBYTES('SHA2_256', N'duplicate-' + @FixtureText);
    DECLARE @ConflictHash BINARY(32) = HASHBYTES('SHA2_256', N'conflict-' + @FixtureText);
    DECLARE @ReplayHash BINARY(32) = HASHBYTES('SHA2_256', N'replay-' + @FixtureText);
    DECLARE @OneHourFromNow DATETIME2(3) = DATEADD(HOUR, 1, @NowUtc);
    DECLARE @OneDayFromNow DATETIME2(3) = DATEADD(DAY, 1, @NowUtc);
    DECLARE @VerifyNowUtc DATETIME2(3) = DATEADD(SECOND, 1, @NowUtc);
    DECLARE @IssueNowUtc DATETIME2(3) = DATEADD(SECOND, 2, @NowUtc);
    DECLARE @ResetExpiryUtc DATETIME2(3) = DATEADD(MINUTE, 30, @NowUtc);
    DECLARE @RotateNowUtc DATETIME2(3) = DATEADD(SECOND, 3, @NowUtc);
    DECLARE @RotateGraceUtc DATETIME2(3) = DATEADD(SECOND, 13, @NowUtc);
    DECLARE @ConflictNowUtc DATETIME2(3) = DATEADD(SECOND, 5, @NowUtc);
    DECLARE @ConflictGraceUtc DATETIME2(3) = DATEADD(SECOND, 15, @NowUtc);
    DECLARE @ReplayNowUtc DATETIME2(3) = DATEADD(SECOND, 20, @NowUtc);
    DECLARE @ReplayGraceUtc DATETIME2(3) = DATEADD(SECOND, 30, @NowUtc);
    DECLARE @ThirdRefreshCreatedUtc DATETIME2(3) = DATEADD(SECOND, 21, @NowUtc);
    DECLARE @ResetNowUtc DATETIME2(3) = DATEADD(SECOND, 22, @NowUtc);
    DECLARE @ReplacementJwtId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ConflictJwtId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ReplayJwtId UNIQUEIDENTIFIER = NEWID();
    DECLARE @TransactionCountBeforeProcedure INT = @@TRANCOUNT;

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
        @DisplayName = N'Identity SQL smoke',
        @PasswordHash = N'smoke-password-hash-not-a-credential',
        @SecurityStamp = N'smoke-security-stamp',
        @PreferredLocale = N'es-CL',
        @TokenHash = @VerificationHash,
        @TokenExpiresAtUtc = @OneHourFromNow,
        @RequestedIpHash = NULL,
        @NowUtc = @NowUtc;

    IF @@TRANCOUNT <> @TransactionCountBeforeProcedure
        THROW 52104, N'User_Register changed the caller transaction ownership.', 1;

    DECLARE @UserId BIGINT = (SELECT UserId FROM @Registration WHERE ResultCode = 0);
    IF @UserId IS NULL
        THROW 52105, N'User_Register did not create the identity fixture.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_Users
        WHERE Id = @UserId AND Status = 1 AND EmailConfirmed = 0 AND SecurityVersion = 1
    )
        THROW 52106, N'The registered user has an invalid initial security state.', 1;

    DECLARE @DuplicateRegistration TABLE
    (
        ResultCode TINYINT NOT NULL,
        UserId BIGINT NULL,
        PublicId UNIQUEIDENTIFIER NULL
    );
    INSERT INTO @DuplicateRegistration (ResultCode, UserId, PublicId)
    EXEC dbo.FundingPlatform_usp_User_Register
        @Email = @Email,
        @NormalizedEmail = @NormalizedEmail,
        @DisplayName = N'Duplicate fixture',
        @PasswordHash = N'duplicate-hash',
        @SecurityStamp = N'duplicate-stamp',
        @PreferredLocale = N'es-CL',
        @TokenHash = @DuplicateHash,
        @TokenExpiresAtUtc = @OneHourFromNow,
        @RequestedIpHash = NULL,
        @NowUtc = @NowUtc;

    IF NOT EXISTS (SELECT 1 FROM @DuplicateRegistration WHERE ResultCode = 1)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_Users WHERE NormalizedEmail = @NormalizedEmail) <> 1
        THROW 52107, N'User_Register is not idempotent for duplicate normalized email.', 1;

    DECLARE @VerifyResult TABLE (ResultCode TINYINT NOT NULL);
    INSERT INTO @VerifyResult (ResultCode)
    EXEC dbo.FundingPlatform_usp_User_VerifyEmail
        @TokenHash = @VerificationHash,
        @NowUtc = @VerifyNowUtc;

    IF NOT EXISTS (SELECT 1 FROM @VerifyResult WHERE ResultCode = 0)
       OR NOT EXISTS
       (
           SELECT 1 FROM dbo.FundingPlatform_Users
           WHERE Id = @UserId AND Status = 2 AND EmailConfirmed = 1
       )
        THROW 52108, N'User_VerifyEmail did not activate the user atomically.', 1;

    DECLARE @IssueResult TABLE
    (
        ResultCode TINYINT NOT NULL,
        UserId BIGINT NULL,
        Email NVARCHAR(320) NULL,
        DisplayName NVARCHAR(150) NULL
    );
    INSERT INTO @IssueResult (ResultCode, UserId, Email, DisplayName)
    EXEC dbo.FundingPlatform_usp_UserSecurityToken_Issue
        @NormalizedEmail = @NormalizedEmail,
        @Purpose = 1,
        @TokenHash = @ResetHash,
        @ExpiresAtUtc = @ResetExpiryUtc,
        @RequestedIpHash = NULL,
        @NowUtc = @IssueNowUtc;

    IF NOT EXISTS (SELECT 1 FROM @IssueResult WHERE ResultCode = 0 AND UserId = @UserId)
        THROW 52109, N'UserSecurityToken_Issue did not issue the reset token.', 1;

    DECLARE @FamilyId UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.FundingPlatform_RefreshTokens
    (
        UserId, SecurityVersion, MfaAuthenticated, FamilyId, TokenHash, JwtId,
        ExpiresAtUtc, CreatedAtUtc, CreatedIpHash, UserAgent
    )
    VALUES
    (
        @UserId, 1, 0, @FamilyId, @RefreshHash1, NEWID(),
        DATEADD(DAY, 1, @NowUtc), @NowUtc, NULL, N'sql-smoke'
    );

    DECLARE @RotationResult TABLE
    (
        ResultCode TINYINT NOT NULL,
        UserId BIGINT NULL,
        PublicId UNIQUEIDENTIFIER NULL,
        Email NVARCHAR(320) NULL,
        DisplayName NVARCHAR(150) NULL,
        SecurityVersion INT NULL,
        TwoFactorEnabled BIT NULL,
        MfaAuthenticated BIT NULL,
        MfaAuthenticatedAtUtc DATETIME2(3) NULL,
        FamilyId UNIQUEIDENTIFIER NULL
    );
    INSERT INTO @RotationResult
    EXEC dbo.FundingPlatform_usp_RefreshToken_Rotate
        @CurrentTokenHash = @RefreshHash1,
        @ReplacementTokenHash = @RefreshHash2,
        @ReplacementJwtId = @ReplacementJwtId,
        @ReplacementExpiresAtUtc = @OneDayFromNow,
        @CreatedIpHash = NULL,
        @UserAgent = N'sql-smoke-rotated',
        @NowUtc = @RotateNowUtc,
        @GraceUntilUtc = @RotateGraceUtc;

    IF NOT EXISTS
    (
        SELECT 1 FROM @RotationResult
        WHERE ResultCode = 0 AND UserId = @UserId AND FamilyId = @FamilyId
          AND MfaAuthenticated = 0 AND MfaAuthenticatedAtUtc IS NULL
    )
        THROW 52110, N'RefreshToken_Rotate did not create a valid replacement.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_RefreshTokens AS PreviousToken
        INNER JOIN dbo.FundingPlatform_RefreshTokens AS ReplacementToken
            ON ReplacementToken.Id = PreviousToken.ReplacedByTokenId
        WHERE PreviousToken.TokenHash = @RefreshHash1
          AND PreviousToken.RevocationReason = 0
          AND ReplacementToken.TokenHash = @RefreshHash2
          AND ReplacementToken.RevokedAtUtc IS NULL
    )
        THROW 52111, N'Refresh token rotation lineage is invalid.', 1;

    DECLARE @ConflictResult TABLE (ResultCode TINYINT NOT NULL);
    INSERT INTO @ConflictResult (ResultCode)
    EXEC dbo.FundingPlatform_usp_RefreshToken_Rotate
        @CurrentTokenHash = @RefreshHash1,
        @ReplacementTokenHash = @ConflictHash,
        @ReplacementJwtId = @ConflictJwtId,
        @ReplacementExpiresAtUtc = @OneDayFromNow,
        @CreatedIpHash = NULL,
        @UserAgent = N'sql-smoke-conflict',
        @NowUtc = @ConflictNowUtc,
        @GraceUntilUtc = @ConflictGraceUtc;

    IF NOT EXISTS (SELECT 1 FROM @ConflictResult WHERE ResultCode = 5)
        THROW 52112, N'Concurrent refresh did not return the bounded grace conflict.', 1;

    DECLARE @ReplayResult TABLE (ResultCode TINYINT NOT NULL);
    INSERT INTO @ReplayResult (ResultCode)
    EXEC dbo.FundingPlatform_usp_RefreshToken_Rotate
        @CurrentTokenHash = @RefreshHash1,
        @ReplacementTokenHash = @ReplayHash,
        @ReplacementJwtId = @ReplayJwtId,
        @ReplacementExpiresAtUtc = @OneDayFromNow,
        @CreatedIpHash = NULL,
        @UserAgent = N'sql-smoke-replay',
        @NowUtc = @ReplayNowUtc,
        @GraceUntilUtc = @ReplayGraceUtc;

    IF NOT EXISTS (SELECT 1 FROM @ReplayResult WHERE ResultCode = 3)
       OR NOT EXISTS
       (
           SELECT 1 FROM dbo.FundingPlatform_RefreshTokens
           WHERE TokenHash = @RefreshHash2 AND RevocationReason = 2
       )
        THROW 52113, N'Refresh replay did not revoke the active token family.', 1;

    INSERT INTO dbo.FundingPlatform_RefreshTokens
    (
        UserId, SecurityVersion, MfaAuthenticated, FamilyId, TokenHash, JwtId,
        ExpiresAtUtc, CreatedAtUtc
    )
    VALUES
    (
        @UserId, 1, 0, NEWID(), @RefreshHash3, NEWID(),
        @OneDayFromNow, @ThirdRefreshCreatedUtc
    );

    DECLARE @ResetResult TABLE (ResultCode TINYINT NOT NULL);
    INSERT INTO @ResetResult (ResultCode)
    EXEC dbo.FundingPlatform_usp_User_ResetPassword
        @TokenHash = @ResetHash,
        @PasswordHash = N'new-smoke-password-hash',
        @SecurityStamp = N'new-smoke-security-stamp',
        @NowUtc = @ResetNowUtc;

    IF NOT EXISTS (SELECT 1 FROM @ResetResult WHERE ResultCode = 0)
       OR NOT EXISTS
       (
           SELECT 1 FROM dbo.FundingPlatform_Users
           WHERE Id = @UserId AND SecurityVersion = 2
             AND SecurityStamp = N'new-smoke-security-stamp'
       )
       OR NOT EXISTS
       (
           SELECT 1 FROM dbo.FundingPlatform_RefreshTokens
           WHERE TokenHash = @RefreshHash3 AND RevocationReason = 3
       )
        THROW 52114, N'User_ResetPassword did not invalidate active sessions.', 1;

    IF @@TRANCOUNT <> @TransactionCountBeforeProcedure
        THROW 52115, N'An identity procedure changed the caller transaction ownership.', 1;

    IF @InitialTransactionCount = 0
        ROLLBACK TRANSACTION;
    ELSE
        ROLLBACK TRANSACTION FundingPlatform_Smoke002;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FundingPlatform_Smoke002;
    THROW;
END CATCH;

SELECT
    CAST(1 AS BIT) AS Succeeded,
    (SELECT COUNT_BIG(1) FROM @ExpectedTables) AS ExpectedTableCount,
    (SELECT COUNT_BIG(1) FROM @ExpectedProcedures) AS ExpectedProcedureCount;
