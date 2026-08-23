/* FundingPlatform FASE 4 - tenant-safe organization onboarding API. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Catalogs_GetForOrganizationProfile
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Iso2 AS Code, Name
    FROM dbo.FundingPlatform_Countries
    WHERE IsActive = 1 ORDER BY Name, Id;

    SELECT Id, CountryId, Code, Name
    FROM dbo.FundingPlatform_Regions
    WHERE IsActive = 1 ORDER BY CountryId, Name, Id;

    SELECT Code, Name, MinorUnits
    FROM dbo.FundingPlatform_Currencies
    WHERE IsActive = 1 ORDER BY Code;

    SELECT Id, Code, Name
    FROM dbo.FundingPlatform_FundingCategories
    WHERE IsActive = 1 ORDER BY Name, Id;

    SELECT Id, Code, Name
    FROM dbo.FundingPlatform_OrganizationTypes
    WHERE IsActive = 1 ORDER BY Name, Id;

    SELECT Id, CountryId, Code, Name
    FROM dbo.FundingPlatform_LegalEntityTypes
    WHERE IsActive = 1 ORDER BY CountryId, Name, Id;

    SELECT Id, Code, Name
    FROM dbo.FundingPlatform_OrganizationSizes
    WHERE IsActive = 1 ORDER BY Id;

    SELECT Id, Code, Name
    FROM dbo.FundingPlatform_BeneficiaryTypes
    WHERE IsActive = 1 ORDER BY Name, Id;

    SELECT Id, Code, Name
    FROM dbo.FundingPlatform_ProjectTypes
    WHERE IsActive = 1 ORDER BY Name, Id;

    SELECT Id, NormalizedName AS Code, Name
    FROM dbo.FundingPlatform_Tags
    WHERE IsActive = 1 AND IsApproved = 1 ORDER BY Name, Id;

    SELECT Id, IsoCode AS Code, Name
    FROM dbo.FundingPlatform_Languages
    WHERE IsActive = 1 ORDER BY Name, Id;
END;';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Organization_ListForUser
    @UserPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        o.PublicId,
        o.Name,
        ou.Role AS MembershipRole,
        o.ProfileStatus,
        o.ProfileCompleteness,
        o.ProfileVersion,
        o.UpdatedAtUtc
    FROM dbo.FundingPlatform_Users AS u
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS ou
        ON ou.UserId = u.Id AND ou.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Organizations AS o
        ON o.Id = ou.OrganizationId AND o.IsActive = 1
    WHERE u.PublicId = @UserPublicId AND u.Status = 2
    ORDER BY o.UpdatedAtUtc DESC, o.Id DESC;
END;';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Organization_CreateForUser
    @UserPublicId UNIQUEIDENTIFIER,
    @Name NVARCHAR(250),
    @HomeCountryId SMALLINT,
    @OrganizationTypeId SMALLINT,
    @SnapshotJson NVARCHAR(MAX),
    @ContentHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @UserId BIGINT;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0
        BEGIN TRANSACTION;
    ELSE
        SAVE TRANSACTION FundingPlatform_CreateOrgPublic;

    BEGIN TRY
        SELECT @UserId = Id
        FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @UserPublicId AND Status = 2;

        IF @UserId IS NULL
            THROW 51201, N''An active user is required.'', 1;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.FundingPlatform_Organizations WITH (UPDLOCK, HOLDLOCK)
            WHERE CreatedByUserId = @UserId AND IsActive = 1
        )
            THROW 51202, N''The MVP permits one owned organization per user.'', 1;

        EXEC dbo.FundingPlatform_usp_Organization_Create
            @CreatedByUserId = @UserId,
            @Name = @Name,
            @HomeCountryId = @HomeCountryId,
            @OrganizationTypeId = @OrganizationTypeId,
            @SnapshotJson = @SnapshotJson,
            @ContentHash = @ContentHash;

        IF @InitialTransactionCount = 0
            COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FundingPlatform_CreateOrgPublic;
        THROW;
    END CATCH;
END;';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Organization_GetProfileByPublicId
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OrganizationId BIGINT;
    DECLARE @UserId BIGINT;
    DECLARE @MembershipRole TINYINT;

    SELECT @OrganizationId = Id
    FROM dbo.FundingPlatform_Organizations
    WHERE PublicId = @OrganizationPublicId AND IsActive = 1;

    SELECT @UserId = Id
    FROM dbo.FundingPlatform_Users
    WHERE PublicId = @UserPublicId AND Status = 2;

    IF @OrganizationId IS NULL OR @UserId IS NULL
        THROW 51203, N''The organization profile was not found.'', 1;

    SELECT @MembershipRole = Role
    FROM dbo.FundingPlatform_OrganizationUsers
    WHERE OrganizationId = @OrganizationId
      AND UserId = @UserId
      AND MembershipStatus = 1;

    IF @MembershipRole IS NULL
        THROW 51203, N''The organization profile was not found.'', 1;

    SELECT @MembershipRole;

    EXEC dbo.FundingPlatform_usp_Organization_GetProfile
        @OrganizationId = @OrganizationId,
        @UserId = @UserId;
END;';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Organization_UpdateProfileByPublicId
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @Name NVARCHAR(250),
    @LegalName NVARCHAR(300) = NULL,
    @TaxIdentifier NVARCHAR(50) = NULL,
    @HomeCountryId SMALLINT,
    @OrganizationTypeId SMALLINT,
    @LegalEntityTypeId SMALLINT = NULL,
    @OrganizationSizeId SMALLINT = NULL,
    @EstablishedYear SMALLINT = NULL,
    @WebsiteUrl NVARCHAR(2048) = NULL,
    @Description NVARCHAR(2000) = NULL,
    @PreviousFundingExperience TINYINT = 0,
    @ExperienceSummary NVARCHAR(2000) = NULL,
    @AnnualBudgetMin DECIMAL(19,4) = NULL,
    @AnnualBudgetMax DECIMAL(19,4) = NULL,
    @AnnualBudgetCurrency CHAR(3) = NULL,
    @DesiredFundingMin DECIMAL(19,4) = NULL,
    @DesiredFundingMax DECIMAL(19,4) = NULL,
    @DesiredFundingCurrency CHAR(3) = NULL,
    @ProfileStatus TINYINT,
    @ProfileCompleteness DECIMAL(5,2),
    @SnapshotJson NVARCHAR(MAX),
    @ContentHash BINARY(32),
    @CountryIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @RegionIds dbo.FundingPlatform_IntIdList READONLY,
    @CategoryIds dbo.FundingPlatform_IntIdList READONLY,
    @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @TagIds dbo.FundingPlatform_BigIntIdList READONLY,
    @Languages dbo.FundingPlatform_OrganizationLanguageList READONLY
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OrganizationId BIGINT;
    DECLARE @UserId BIGINT;

    SELECT @OrganizationId = Id
    FROM dbo.FundingPlatform_Organizations
    WHERE PublicId = @OrganizationPublicId AND IsActive = 1;

    SELECT @UserId = Id
    FROM dbo.FundingPlatform_Users
    WHERE PublicId = @UserPublicId AND Status = 2;

    IF @OrganizationId IS NULL OR @UserId IS NULL
        THROW 51204, N''The organization profile was not found.'', 1;

    EXEC dbo.FundingPlatform_usp_Organization_UpdateProfile
        @OrganizationId = @OrganizationId,
        @ActorUserId = @UserId,
        @ExpectedRowVersion = @ExpectedRowVersion,
        @Name = @Name,
        @LegalName = @LegalName,
        @TaxIdentifier = @TaxIdentifier,
        @HomeCountryId = @HomeCountryId,
        @OrganizationTypeId = @OrganizationTypeId,
        @LegalEntityTypeId = @LegalEntityTypeId,
        @OrganizationSizeId = @OrganizationSizeId,
        @EstablishedYear = @EstablishedYear,
        @WebsiteUrl = @WebsiteUrl,
        @Description = @Description,
        @PreviousFundingExperience = @PreviousFundingExperience,
        @ExperienceSummary = @ExperienceSummary,
        @AnnualBudgetMin = @AnnualBudgetMin,
        @AnnualBudgetMax = @AnnualBudgetMax,
        @AnnualBudgetCurrency = @AnnualBudgetCurrency,
        @DesiredFundingMin = @DesiredFundingMin,
        @DesiredFundingMax = @DesiredFundingMax,
        @DesiredFundingCurrency = @DesiredFundingCurrency,
        @ProfileStatus = @ProfileStatus,
        @ProfileCompleteness = @ProfileCompleteness,
        @SnapshotJson = @SnapshotJson,
        @ContentHash = @ContentHash,
        @CountryIds = @CountryIds,
        @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds,
        @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds,
        @TagIds = @TagIds,
        @Languages = @Languages;
END;';
