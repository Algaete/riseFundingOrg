SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_usp_GlobalRole_ListAdministrators', N'P') IS NULL
    THROW 52231, N'The global administrator listing procedure is missing.', 1;
IF OBJECT_ID(N'dbo.FundingPlatform_usp_GlobalRole_GrantSuperAdmin', N'P') IS NULL
    THROW 52232, N'The SuperAdmin grant procedure is missing.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0
    BEGIN TRANSACTION;
ELSE
    SAVE TRANSACTION FP_Smoke012;

BEGIN TRY
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @Suffix NVARCHAR(32) = REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N'');
    DECLARE @Email NVARCHAR(320) = N'grant-' + @Suffix + N'@example.invalid';
    DECLARE @NormalizedEmail NVARCHAR(320) = UPPER(@Email);
    DECLARE @IneligibleEmail NVARCHAR(320) = N'pending-' + @Suffix + N'@example.invalid';
    DECLARE @OperationId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ReplayOperationId UNIQUEIDENTIFIER = NEWID();
    DECLARE @MissingOperationId UNIQUEIDENTIFIER = NEWID();
    DECLARE @IneligibleOperationId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ReplayNowUtc DATETIME2(3) = DATEADD(SECOND, 1, @NowUtc);
    DECLARE @MissingNormalizedEmail NVARCHAR(320) = N'MISSING-' + @NormalizedEmail;
    DECLARE @IneligibleNormalizedEmail NVARCHAR(320) = UPPER(@IneligibleEmail);
    DECLARE @OriginalSecurityVersion INT = 7;
    DECLARE @TransactionCountBeforeProcedure INT;

    INSERT INTO dbo.FundingPlatform_Users
    (
        Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
        SecurityVersion, EmailConfirmed, TwoFactorEnabled, Status,
        AccessFailedCount, PreferredLocale, CreatedAtUtc, UpdatedAtUtc
    )
    VALUES
    (
        @Email, @NormalizedEmail, N'Role grant smoke user', N'smoke-hash-not-a-secret',
        N'original-smoke-security-stamp', @OriginalSecurityVersion, 1, 1, 2,
        0, N'es-CL', @NowUtc, @NowUtc
    );

    DECLARE @UserId BIGINT = CONVERT(BIGINT, SCOPE_IDENTITY());
    DECLARE @LiveTokenHash BINARY(32) = HASHBYTES(
        N'SHA2_256', CONVERT(VARBINARY(100), CONCAT(N'live-', @Suffix)));
    DECLARE @RevokedTokenHash BINARY(32) = HASHBYTES(
        N'SHA2_256', CONVERT(VARBINARY(100), CONCAT(N'revoked-', @Suffix)));

    INSERT INTO dbo.FundingPlatform_RefreshTokens
    (
        UserId, SecurityVersion, MfaAuthenticated, MfaAuthenticatedAtUtc,
        FamilyId, TokenHash, JwtId, ExpiresAtUtc, CreatedAtUtc,
        RevokedAtUtc, ReplacedByTokenId, RotationGraceUntilUtc, RevocationReason,
        CreatedIpHash, UserAgent
    )
    VALUES
    (
        @UserId, @OriginalSecurityVersion, 1, DATEADD(MINUTE, -1, @NowUtc),
        NEWID(), @LiveTokenHash, NEWID(), DATEADD(DAY, 1, @NowUtc), @NowUtc,
        NULL, NULL, NULL, NULL, NULL, N'FundingPlatform smoke'
    ),
    (
        @UserId, @OriginalSecurityVersion, 0, NULL,
        NEWID(), @RevokedTokenHash, NEWID(), DATEADD(DAY, 1, @NowUtc), @NowUtc,
        @NowUtc, NULL, NULL, 4, NULL, N'FundingPlatform smoke'
    );

    DECLARE @Result TABLE
    (
        ResultCode TINYINT NOT NULL,
        Email NVARCHAR(320) NULL,
        SecurityVersion INT NULL,
        TwoFactorEnabled BIT NULL,
        GrantedAtUtc DATETIME2(3) NULL
    );

    SET @TransactionCountBeforeProcedure = @@TRANCOUNT;
    INSERT INTO @Result
        (ResultCode, Email, SecurityVersion, TwoFactorEnabled, GrantedAtUtc)
    EXEC dbo.FundingPlatform_usp_GlobalRole_GrantSuperAdmin
        @NormalizedEmail = @NormalizedEmail,
        @ReasonCode = N'owner_authorized_local_promotion',
        @SecurityStamp = N'replacement-smoke-security-stamp-012',
        @OperationId = @OperationId,
        @NowUtc = @NowUtc;

    IF @@TRANCOUNT <> @TransactionCountBeforeProcedure
        THROW 52233, N'The role grant changed caller transaction ownership.', 1;
    IF NOT EXISTS
    (
        SELECT 1 FROM @Result
        WHERE ResultCode = 0
          AND Email = @Email
          AND SecurityVersion = @OriginalSecurityVersion + 1
          AND TwoFactorEnabled = 1
          AND GrantedAtUtc = @NowUtc
    )
        THROW 52234, N'The role grant returned an invalid success result.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_UserRoles AS userRoles
        INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
        WHERE userRoles.UserId = @UserId
          AND roles.NormalizedName = N'SUPERADMIN'
          AND userRoles.GrantedByUserId IS NULL
    )
        THROW 52235, N'The SuperAdmin role was not granted as an operator action.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_Users
        WHERE Id = @UserId
          AND SecurityVersion = @OriginalSecurityVersion + 1
          AND SecurityStamp = N'replacement-smoke-security-stamp-012'
          AND TwoFactorEnabled = 1
    )
        THROW 52236, N'The account security state was not rotated correctly.', 1;

    IF NOT EXISTS
    (
        SELECT 1 FROM dbo.FundingPlatform_RefreshTokens
        WHERE UserId = @UserId
          AND TokenHash = @LiveTokenHash
          AND RevokedAtUtc = @NowUtc
          AND RevocationReason = 3
    )
        THROW 52237, N'The live refresh session was not revoked.', 1;
    IF NOT EXISTS
    (
        SELECT 1 FROM dbo.FundingPlatform_RefreshTokens
        WHERE UserId = @UserId
          AND TokenHash = @RevokedTokenHash
          AND RevokedAtUtc = @NowUtc
          AND RevocationReason = 4
    )
        THROW 52238, N'An already revoked session was overwritten.', 1;

    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_AuthenticationEvents
        WHERE UserId = @UserId AND EventType = 9) <> 1
        THROW 52239, N'The role grant audit event is missing or duplicated.', 1;
    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_AuthenticationEvents
        WHERE UserId = @UserId
          AND EventType = 9
          AND Outcome = 0
          AND ReasonCode = N'owner_authorized_local_promotion'
          AND UserAgent = N'FundingPlatform.AdminCli'
          AND CorrelationId = CONCAT(N'admin-cli:', CONVERT(NVARCHAR(36), @OperationId))
          AND ReasonCode NOT LIKE N'%@%'
          AND UserAgent NOT LIKE N'%@%'
          AND CorrelationId NOT LIKE N'%@%'
    )
        THROW 52240, N'The role grant audit event is invalid or contains identity data.', 1;

    DECLARE @Administrators TABLE
    (
        Email NVARCHAR(320) NOT NULL,
        RoleName NVARCHAR(100) NOT NULL,
        Status TINYINT NOT NULL,
        EmailConfirmed BIT NOT NULL,
        TwoFactorEnabled BIT NOT NULL,
        GrantedAtUtc DATETIME2(3) NOT NULL
    );
    INSERT INTO @Administrators
        (Email, RoleName, Status, EmailConfirmed, TwoFactorEnabled, GrantedAtUtc)
    EXEC dbo.FundingPlatform_usp_GlobalRole_ListAdministrators;

    IF NOT EXISTS
    (
        SELECT 1 FROM @Administrators
        WHERE Email = @Email
          AND RoleName = N'SuperAdmin'
          AND Status = 2
          AND EmailConfirmed = 1
          AND TwoFactorEnabled = 1
    )
        THROW 52241, N'The administrator listing omitted the granted role.', 1;

    DELETE FROM @Result;
    INSERT INTO @Result
        (ResultCode, Email, SecurityVersion, TwoFactorEnabled, GrantedAtUtc)
    EXEC dbo.FundingPlatform_usp_GlobalRole_GrantSuperAdmin
        @NormalizedEmail = @NormalizedEmail,
        @ReasonCode = N'owner_authorized_local_promotion',
        @SecurityStamp = N'another-valid-smoke-security-stamp-012',
        @OperationId = @ReplayOperationId,
        @NowUtc = @ReplayNowUtc;

    IF NOT EXISTS (SELECT 1 FROM @Result WHERE ResultCode = 1)
        THROW 52242, N'The role grant replay was not idempotent.', 1;
    IF (SELECT SecurityVersion FROM dbo.FundingPlatform_Users WHERE Id = @UserId)
        <> @OriginalSecurityVersion + 1
        THROW 52243, N'The replay invalidated sessions again.', 1;
    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_AuthenticationEvents
        WHERE UserId = @UserId AND EventType = 9) <> 1
        THROW 52244, N'The replay duplicated the audit event.', 1;

    DELETE FROM @Result;
    INSERT INTO @Result
        (ResultCode, Email, SecurityVersion, TwoFactorEnabled, GrantedAtUtc)
    EXEC dbo.FundingPlatform_usp_GlobalRole_GrantSuperAdmin
        @NormalizedEmail = @MissingNormalizedEmail,
        @ReasonCode = N'owner_authorized_local_promotion',
        @SecurityStamp = N'missing-user-smoke-security-stamp-012',
        @OperationId = @MissingOperationId,
        @NowUtc = @NowUtc;
    IF NOT EXISTS (SELECT 1 FROM @Result WHERE ResultCode = 2)
        THROW 52245, N'A missing user did not return the expected outcome.', 1;

    INSERT INTO dbo.FundingPlatform_Users
    (
        Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
        SecurityVersion, EmailConfirmed, TwoFactorEnabled, Status,
        AccessFailedCount, PreferredLocale, CreatedAtUtc, UpdatedAtUtc
    )
    VALUES
    (
        @IneligibleEmail, UPPER(@IneligibleEmail), N'Ineligible role grant smoke user',
        N'smoke-hash-not-a-secret', N'ineligible-smoke-security-stamp', 1,
        0, 0, 1, 0, N'es-CL', @NowUtc, @NowUtc
    );

    DECLARE @IneligibleUserId BIGINT = CONVERT(BIGINT, SCOPE_IDENTITY());
    DELETE FROM @Result;
    INSERT INTO @Result
        (ResultCode, Email, SecurityVersion, TwoFactorEnabled, GrantedAtUtc)
    EXEC dbo.FundingPlatform_usp_GlobalRole_GrantSuperAdmin
        @NormalizedEmail = @IneligibleNormalizedEmail,
        @ReasonCode = N'owner_authorized_local_promotion',
        @SecurityStamp = N'ineligible-user-new-security-stamp-012',
        @OperationId = @IneligibleOperationId,
        @NowUtc = @NowUtc;
    IF NOT EXISTS (SELECT 1 FROM @Result WHERE ResultCode = 3)
        THROW 52246, N'An ineligible user did not return the expected outcome.', 1;
    IF EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_UserRoles AS userRoles
        INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
        WHERE userRoles.UserId = @IneligibleUserId
          AND roles.NormalizedName = N'SUPERADMIN'
    )
        THROW 52247, N'An ineligible user received the SuperAdmin role.', 1;

    IF @InitialTransactionCount = 0
        ROLLBACK TRANSACTION;
    ELSE
        ROLLBACK TRANSACTION FP_Smoke012;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FP_Smoke012;
    THROW;
END CATCH;

SELECT CAST(1 AS BIT) AS Succeeded;
