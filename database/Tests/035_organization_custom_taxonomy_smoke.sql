/* Transactional smoke for migration 035: private organization custom taxonomy. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_OrganizationCustomTaxonomyValues', N'U') IS NULL
   OR NOT EXISTS
   (
       SELECT 1 FROM sys.foreign_keys
       WHERE parent_object_id =
             OBJECT_ID(N'dbo.FundingPlatform_OrganizationCustomTaxonomyValues', N'U')
         AND name = N'FundingPlatform_FK_OrganizationCustomTaxonomyValues_Organizations'
         AND delete_referential_action = 1
   )
   OR NOT EXISTS
   (
       SELECT 1 FROM sys.check_constraints
       WHERE parent_object_id =
             OBJECT_ID(N'dbo.FundingPlatform_OrganizationCustomTaxonomyValues', N'U')
         AND name = N'FundingPlatform_CK_OrganizationCustomTaxonomyValues_Kind'
   )
    THROW 55520, N'Organization custom taxonomy table contract failed.', 1;

DECLARE @CoreUpdateDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_Organization_UpdateProfile', N'P'));
DECLARE @PublicUpdateDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_Organization_UpdateProfileByPublicId', N'P'));
DECLARE @GetDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_Organization_GetProfile', N'P'));

IF @CoreUpdateDefinition NOT LIKE N'%@CustomTaxonomyValuesJson NVARCHAR(MAX) = NULL%'
   OR @PublicUpdateDefinition NOT LIKE N'%@CustomTaxonomyValuesJson NVARCHAR(MAX) = NULL%'
   OR @CoreUpdateDefinition NOT LIKE N'%DATALENGTH(@CustomTaxonomyValuesJson) > 65536%'
   OR @CoreUpdateDefinition NOT LIKE N'%THROW 51013%'
   OR @CoreUpdateDefinition NOT LIKE N'%THROW 51014%'
   OR @CoreUpdateDefinition NOT LIKE N'%$.customTaxonomyValues%'
   OR @CoreUpdateDefinition NOT LIKE N'%Latin1_General_100_CI_AI_SC%'
   OR @GetDefinition NOT LIKE N'%OrganizationCustomTaxonomyValues%'
    THROW 55521, N'Backward-compatible custom taxonomy procedure contract failed.', 1;

IF DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole') IS NOT NULL
   AND EXISTS
   (
       SELECT 1
       FROM sys.database_permissions AS permission
       WHERE permission.grantee_principal_id =
             DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole')
         AND permission.class = 1
         AND permission.major_id =
             OBJECT_ID(N'dbo.FundingPlatform_OrganizationCustomTaxonomyValues', N'U')
         AND permission.permission_name IN (N'SELECT', N'INSERT', N'UPDATE', N'DELETE')
         AND permission.state IN (N'G', N'W')
   )
    THROW 55522, N'API runtime role must not receive direct custom taxonomy table access.', 1;

IF DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.database_permissions AS permission
       WHERE permission.grantee_principal_id =
             DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole')
         AND permission.class = 1
         AND permission.major_id =
             OBJECT_ID(N'dbo.FundingPlatform_usp_Organization_UpdateProfileByPublicId', N'P')
         AND permission.permission_name = N'EXECUTE'
         AND permission.state IN (N'G', N'W')
   )
    THROW 55523, N'CREATE OR ALTER did not preserve API runtime EXECUTE permission.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke035;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @UserPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @Email NVARCHAR(320) = N'custom-taxonomy-' +
        REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'') + N'@example.invalid';

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, Status, PreferredLocale)
    VALUES
        (@UserPublicId, @Email, UPPER(@Email), N'Custom taxonomy smoke',
         N'not-a-credential', N'custom-taxonomy', 1, 2, N'es-CL');

    DECLARE @Created TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProfileVersion INT, RowVersion BINARY(8));
    DECLARE @InitialSnapshot NVARCHAR(MAX) =
        N'{"name":"Custom taxonomy smoke","fundingExperienceTypeIds":[],"customTaxonomyValues":[]}';
    DECLARE @InitialHash BINARY(32) = HASHBYTES('SHA2_256', @InitialSnapshot);
    INSERT INTO @Created EXEC dbo.FundingPlatform_usp_Organization_CreateForUser
        @UserPublicId = @UserPublicId,
        @Name = N'Custom taxonomy smoke',
        @HomeCountryId = 152,
        @OrganizationTypeId = 2,
        @SnapshotJson = @InitialSnapshot,
        @ContentHash = @InitialHash;

    DECLARE @OrganizationId BIGINT = (SELECT Id FROM @Created);
    DECLARE @OrganizationPublicId UNIQUEIDENTIFIER = (SELECT PublicId FROM @Created);
    DECLARE @ExpectedRowVersion BINARY(8) = (SELECT RowVersion FROM @Created);
    DECLARE @CountryIds dbo.FundingPlatform_SmallIntIdList;
    DECLARE @RegionIds dbo.FundingPlatform_IntIdList;
    DECLARE @CategoryIds dbo.FundingPlatform_IntIdList;
    DECLARE @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList;
    DECLARE @ProjectTypeIds dbo.FundingPlatform_IntIdList;
    DECLARE @TagIds dbo.FundingPlatform_BigIntIdList;
    DECLARE @Languages dbo.FundingPlatform_OrganizationLanguageList;
    INSERT INTO @CountryIds VALUES (152);

    DECLARE @Snapshot1 NVARCHAR(MAX) =
        N'{"name":"Custom taxonomy smoke","fundingExperienceTypeIds":[],"customTaxonomyValues":[{"kind":1,"name":"Economía circular"},{"kind":4,"name":"Mapudungun"}]}';
    DECLARE @Hash1 BINARY(32) = HASHBYTES('SHA2_256', @Snapshot1);
    DECLARE @Updated1 TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProfileVersion INT, RowVersion BINARY(8));
    INSERT INTO @Updated1 EXEC dbo.FundingPlatform_usp_Organization_UpdateProfileByPublicId
        @OrganizationPublicId = @OrganizationPublicId,
        @UserPublicId = @UserPublicId,
        @ExpectedRowVersion = @ExpectedRowVersion,
        @Name = N'Custom taxonomy smoke',
        @HomeCountryId = 152,
        @OrganizationTypeId = 2,
        @PreviousFundingExperience = 0,
        @ProfileStatus = 1,
        @ProfileCompleteness = 30,
        @SnapshotJson = @Snapshot1,
        @ContentHash = @Hash1,
        @CountryIds = @CountryIds,
        @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds,
        @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds,
        @TagIds = @TagIds,
        @Languages = @Languages,
        @PreviousFunderTypeIdsJson = N'[]',
        @CustomTaxonomyValuesJson =
            N'[{"kind":1,"name":"Economía circular","normalizedName":"ECONOMIA CIRCULAR"},{"kind":4,"name":"Mapudungun","normalizedName":"MAPUDUNGUN"}]';

    IF (SELECT COUNT_BIG(1)
        FROM dbo.FundingPlatform_OrganizationCustomTaxonomyValues
        WHERE OrganizationId = @OrganizationId) <> 2
       OR NOT EXISTS
       (
           SELECT 1 FROM dbo.FundingPlatform_OrganizationCustomTaxonomyValues
           WHERE OrganizationId = @OrganizationId AND Kind = 1
             AND Name = N'Economía circular' AND NormalizedName = N'ECONOMIA CIRCULAR'
       )
       OR NOT EXISTS
       (
           SELECT 1 FROM dbo.FundingPlatform_OrganizationProfileVersions
           WHERE OrganizationId = @OrganizationId AND ProfileVersion = 2
             AND JSON_QUERY(SnapshotJson, N'$.customTaxonomyValues') =
                 N'[{"kind":1,"name":"Economía circular"},{"kind":4,"name":"Mapudungun"}]'
       )
        THROW 55524, N'Custom taxonomy write or complete snapshot failed.', 1;

    DECLARE @UserId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @UserPublicId);
    EXEC dbo.FundingPlatform_usp_Organization_GetProfile
        @OrganizationId = @OrganizationId,
        @UserId = @UserId;

    SET @ExpectedRowVersion = (SELECT RowVersion FROM @Updated1);
    DECLARE @Snapshot2 NVARCHAR(MAX) =
        N'{"name":"Custom taxonomy smoke","fundingExperienceTypeIds":[],"customTaxonomyValues":[]}';
    DECLARE @Hash2 BINARY(32) = HASHBYTES('SHA2_256', @Snapshot2);
    DECLARE @Updated2 TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProfileVersion INT, RowVersion BINARY(8));
    INSERT INTO @Updated2 EXEC dbo.FundingPlatform_usp_Organization_UpdateProfileByPublicId
        @OrganizationPublicId = @OrganizationPublicId,
        @UserPublicId = @UserPublicId,
        @ExpectedRowVersion = @ExpectedRowVersion,
        @Name = N'Custom taxonomy smoke',
        @HomeCountryId = 152,
        @OrganizationTypeId = 2,
        @PreviousFundingExperience = 0,
        @ProfileStatus = 1,
        @ProfileCompleteness = 20,
        @SnapshotJson = @Snapshot2,
        @ContentHash = @Hash2,
        @CountryIds = @CountryIds,
        @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds,
        @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds,
        @TagIds = @TagIds,
        @Languages = @Languages,
        @PreviousFunderTypeIdsJson = N'[]',
        @CustomTaxonomyValuesJson = N'[]';

    IF EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_OrganizationCustomTaxonomyValues
        WHERE OrganizationId = @OrganizationId)
        THROW 55525, N'Explicit custom taxonomy clear failed.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke035;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FP_Smoke035;
    THROW;
END CATCH;

SELECT CAST(1 AS BIT) AS Succeeded;
