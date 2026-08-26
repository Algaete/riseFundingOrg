/* Transactional smoke for migration 028. The outer migrator owns the connection. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'dbo.FundingPlatform_usp_AdminOrganization_List', N'P') IS NULL
       OR OBJECT_ID(N'dbo.FundingPlatform_usp_AdminOrganization_Get', N'P') IS NULL
       OR OBJECT_ID(N'dbo.FundingPlatform_usp_AdminOperationalError_List', N'P') IS NULL
        THROW 54920, N'Admin operation procedures are missing.', 1;

    IF HAS_PERMS_BY_NAME(N'dbo.FundingPlatform_usp_AdminOrganization_List', N'OBJECT', N'EXECUTE') <> 1
       OR HAS_PERMS_BY_NAME(N'dbo.FundingPlatform_usp_AdminOrganization_Get', N'OBJECT', N'EXECUTE') <> 1
       OR HAS_PERMS_BY_NAME(N'dbo.FundingPlatform_usp_AdminOperationalError_List', N'OBJECT', N'EXECUTE') <> 1
        THROW 54921, N'Migration principal cannot execute admin operation procedures.', 1;

    IF (
        SELECT COUNT_BIG(*)
        FROM sys.database_permissions AS permissions
        INNER JOIN sys.database_principals AS principals
            ON principals.principal_id = permissions.grantee_principal_id
        WHERE principals.name = N'FundingPlatform_ApiRuntimeRole'
          AND permissions.permission_name = N'EXECUTE'
          AND permissions.state IN (N'G', N'W')
          AND permissions.major_id IN
          (
              OBJECT_ID(N'dbo.FundingPlatform_usp_AdminOrganization_List'),
              OBJECT_ID(N'dbo.FundingPlatform_usp_AdminOrganization_Get'),
              OBJECT_ID(N'dbo.FundingPlatform_usp_AdminOperationalError_List')
          )
    ) <> 3
        THROW 54922, N'ApiRuntime role grants are missing.', 1;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @AdminPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @OrganizationPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @Suffix NVARCHAR(32) = REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N'');
    DECLARE @Email NVARCHAR(320) = N'fase28-' + @Suffix + N'@example.test';

    INSERT dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@AdminPublicId, @Email, UPPER(@Email), N'FASE 28 Admin', N'not-a-credential',
         N'fase28', 1, 1, 2, N'es-CL');

    DECLARE @AdminUserId BIGINT = SCOPE_IDENTITY();
    DECLARE @AdminRoleId SMALLINT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_Roles
         WHERE NormalizedName IN (N'SUPERADMIN', N'ADMIN')
         ORDER BY CASE WHEN NormalizedName = N'SUPERADMIN' THEN 0 ELSE 1 END);
    IF @AdminRoleId IS NULL THROW 54923, N'Admin role seed is missing.', 1;

    INSERT dbo.FundingPlatform_UserRoles (UserId, RoleId, GrantedByUserId)
    VALUES (@AdminUserId, @AdminRoleId, @AdminUserId);

    DECLARE @CountryId SMALLINT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_Countries WHERE IsActive = 1 ORDER BY Id);
    DECLARE @OrganizationTypeId SMALLINT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_OrganizationTypes WHERE IsActive = 1 ORDER BY Id);
    IF @CountryId IS NULL OR @OrganizationTypeId IS NULL
        THROW 54924, N'Organization catalog seed is missing.', 1;

    INSERT dbo.FundingPlatform_Organizations
        (PublicId, CreatedByUserId, Name, HomeCountryId, OrganizationTypeId,
         ProfileStatus, ProfileCompleteness, IsActive, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@OrganizationPublicId, @AdminUserId, N'FASE 28 ' + @Suffix,
         @CountryId, @OrganizationTypeId, 1, 75, 1, @NowUtc, @NowUtc);

    DECLARE @OrganizationId BIGINT = SCOPE_IDENTITY();
    INSERT dbo.FundingPlatform_OrganizationUsers
        (OrganizationId, UserId, Role, MembershipStatus, JoinedAtUtc, CreatedAtUtc, UpdatedAtUtc)
    VALUES (@OrganizationId, @AdminUserId, 1, 1, @NowUtc, @NowUtc, @NowUtc);

    EXEC dbo.FundingPlatform_usp_AdminOrganization_List
        @AdminUserPublicId = @AdminPublicId,
        @Query = @Suffix,
        @ProfileStatus = 1,
        @IsActive = 1,
        @PageNumber = 1,
        @PageSize = 25;

    EXEC dbo.FundingPlatform_usp_AdminOrganization_Get
        @AdminUserPublicId = @AdminPublicId,
        @OrganizationPublicId = @OrganizationPublicId;

    EXEC dbo.FundingPlatform_usp_AdminOperationalError_List
        @AdminUserPublicId = @AdminPublicId,
        @Category = N'import',
        @Retryable = NULL,
        @PageNumber = 1,
        @PageSize = 25;

    DECLARE @ErrorDefinition NVARCHAR(MAX) =
        OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_AdminOperationalError_List'));
    IF @ErrorDefinition IS NULL
       OR CHARINDEX(N'PayloadHash', @ErrorDefinition) > 0
       OR CHARINDEX(N'ProviderRequestId', @ErrorDefinition) > 0
       OR CHARINDEX(N'LastErrorMessage AS SanitizedMessage', @ErrorDefinition) > 0
        THROW 54925, N'Operational error output exposes a forbidden raw field.', 1;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
