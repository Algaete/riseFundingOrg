/* Transactional smoke for migration 034: organization funding-experience types. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ExpectedTypes TABLE
(
    Id SMALLINT NOT NULL PRIMARY KEY,
    Code NVARCHAR(60) NOT NULL,
    Name NVARCHAR(160) NOT NULL,
    SortOrder TINYINT NOT NULL
);
INSERT INTO @ExpectedTypes (Id, Code, Name, SortOrder)
VALUES
    (1, N'GOVERNMENTS_PUBLIC_FUNDS', N'Gobiernos / fondos públicos', 1),
    (2, N'FOUNDATIONS_GRANTMAKERS', N'Fundaciones / grantmakers', 2),
    (3, N'MULTILATERAL_ORGANIZATIONS', N'Organismos multilaterales', 3),
    (4, N'INTERNATIONAL_COOPERATION', N'Cooperación internacional', 4),
    (5, N'COMPANIES', N'Empresas', 5),
    (6, N'PHILANTHROPISTS', N'Filántropos', 6);

IF (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_FundingExperienceTypes) <> 6
   OR EXISTS
   (
       SELECT 1 FROM @ExpectedTypes AS expected
       LEFT JOIN dbo.FundingPlatform_FundingExperienceTypes AS actual ON actual.Id = expected.Id
       WHERE actual.Id IS NULL OR actual.Code <> expected.Code OR actual.Name <> expected.Name
          OR actual.SortOrder <> expected.SortOrder OR actual.IsActive <> 1
   )
    THROW 55420, N'Funding experience type catalog failed.', 1;

IF OBJECT_ID(N'dbo.FundingPlatform_OrganizationFundingExperienceTypes', N'U') IS NULL
   OR NOT EXISTS
   (
       SELECT 1 FROM sys.foreign_keys
       WHERE parent_object_id =
             OBJECT_ID(N'dbo.FundingPlatform_OrganizationFundingExperienceTypes', N'U')
         AND name = N'FundingPlatform_FK_OrganizationFundingExperienceTypes_Organizations'
         AND delete_referential_action = 1
   )
    THROW 55421, N'Organization funding experience association contract failed.', 1;

DECLARE @CoreUpdateDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_Organization_UpdateProfile', N'P'));
DECLARE @PublicUpdateDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_Organization_UpdateProfileByPublicId', N'P'));
DECLARE @GetDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_Organization_GetProfile', N'P'));
DECLARE @CatalogDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_Catalogs_GetForOrganizationProfile', N'P'));

IF @CoreUpdateDefinition NOT LIKE N'%@PreviousFunderTypeIdsJson NVARCHAR(1000) = NULL%'
   OR @PublicUpdateDefinition NOT LIKE N'%@PreviousFunderTypeIdsJson NVARCHAR(1000) = NULL%'
   OR @CoreUpdateDefinition NOT LIKE N'%THROW 51011%'
   OR @CoreUpdateDefinition NOT LIKE N'%CONVERT(NVARCHAR(6), TRY_CONVERT(SMALLINT, [value]))%'
   OR @CoreUpdateDefinition NOT LIKE N'%$.fundingExperienceTypeIds%'
   OR @GetDefinition NOT LIKE N'%FundingExperienceTypeId AS Id%'
   OR @CatalogDefinition NOT LIKE N'%Result set 14:%'
    THROW 55422, N'Backward-compatible funding experience procedure contract failed.', 1;

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
    THROW 55424, N'CREATE OR ALTER did not preserve API runtime EXECUTE permission.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke034;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @UserPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @Email NVARCHAR(320) = N'funding-experience-' +
        REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'') + N'@example.invalid';

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, Status, PreferredLocale)
    VALUES
        (@UserPublicId, @Email, UPPER(@Email), N'Funding experience smoke',
         N'not-a-credential', N'funding-experience', 1, 2, N'es-CL');

    DECLARE @Created TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProfileVersion INT, RowVersion BINARY(8));
    DECLARE @InitialSnapshot NVARCHAR(MAX) =
        N'{"name":"Funding experience smoke","fundingExperienceTypeIds":[]}';
    DECLARE @InitialHash BINARY(32) = HASHBYTES('SHA2_256', @InitialSnapshot);
    INSERT INTO @Created EXEC dbo.FundingPlatform_usp_Organization_CreateForUser
        @UserPublicId = @UserPublicId,
        @Name = N'Funding experience smoke',
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
        N'{"name":"Funding experience smoke","previousFundingExperience":2,"fundingExperienceTypeIds":[1,4]}';
    DECLARE @Hash1 BINARY(32) = HASHBYTES('SHA2_256', @Snapshot1);
    DECLARE @Updated1 TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProfileVersion INT, RowVersion BINARY(8));
    INSERT INTO @Updated1 EXEC dbo.FundingPlatform_usp_Organization_UpdateProfileByPublicId
        @OrganizationPublicId = @OrganizationPublicId,
        @UserPublicId = @UserPublicId,
        @ExpectedRowVersion = @ExpectedRowVersion,
        @Name = N'Funding experience smoke',
        @HomeCountryId = 152,
        @OrganizationTypeId = 2,
        @PreviousFundingExperience = 2,
        @ProfileStatus = 1,
        @ProfileCompleteness = 20,
        @SnapshotJson = @Snapshot1,
        @ContentHash = @Hash1,
        @CountryIds = @CountryIds,
        @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds,
        @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds,
        @TagIds = @TagIds,
        @Languages = @Languages,
        @PreviousFunderTypeIdsJson = N'[1,4]';

    IF (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_OrganizationFundingExperienceTypes
        WHERE OrganizationId = @OrganizationId) <> 2
       OR NOT EXISTS
       (
           SELECT 1 FROM dbo.FundingPlatform_OrganizationProfileVersions
           WHERE OrganizationId = @OrganizationId AND ProfileVersion = 2
             AND JSON_QUERY(SnapshotJson, N'$.fundingExperienceTypeIds') = N'[1,4]'
       )
        THROW 55425, N'Funding experience write or complete snapshot failed.', 1;

    SET @ExpectedRowVersion = (SELECT RowVersion FROM @Updated1);
    DECLARE @Snapshot2 NVARCHAR(MAX) =
        N'{"name":"Funding experience smoke","previousFundingExperience":1,"fundingExperienceTypeIds":[]}';
    DECLARE @Hash2 BINARY(32) = HASHBYTES('SHA2_256', @Snapshot2);
    DECLARE @Updated2 TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProfileVersion INT, RowVersion BINARY(8));
    INSERT INTO @Updated2 EXEC dbo.FundingPlatform_usp_Organization_UpdateProfileByPublicId
        @OrganizationPublicId = @OrganizationPublicId,
        @UserPublicId = @UserPublicId,
        @ExpectedRowVersion = @ExpectedRowVersion,
        @Name = N'Funding experience smoke',
        @HomeCountryId = 152,
        @OrganizationTypeId = 2,
        @PreviousFundingExperience = 1,
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
        @PreviousFunderTypeIdsJson = N'[]';

    IF EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_OrganizationFundingExperienceTypes
        WHERE OrganizationId = @OrganizationId)
        THROW 55426, N'Explicit funding experience clear failed.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke034;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FP_Smoke034;
    THROW;
END CATCH;

SELECT CAST(1 AS BIT) AS Succeeded;
