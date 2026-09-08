/* FundingPlatform - organization funding-experience types.
   Requires migrations 001-033.

   Compatibility rules:
   - existing financing ranges, summary, languages and tri-state experience stay unchanged;
   - the optional JSON parameter is appended to the existing write procedures;
   - NULL is a legacy call and may update only aggregates without experience-type links;
   - [] explicitly clears links; old clients can never erase or snapshot incomplete links.

   Rollout order: database, then 100% of API traffic, then the frontend selector.
   Once links exist, an old API instance intentionally receives error 51011 instead
   of writing a profile snapshot that omits the new relation.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF OBJECT_ID(N'dbo.FundingPlatform_Organizations', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_OrganizationProfileVersions', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_Catalogs_GetForOrganizationProfile', N'P') IS NULL
    THROW 55401, N'Organization funding experience types require migrations 001-033.', 1;

IF OBJECT_ID(N'dbo.FundingPlatform_FundingExperienceTypes', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FundingPlatform_FundingExperienceTypes
    (
        Id SMALLINT NOT NULL,
        Code NVARCHAR(60) NOT NULL,
        Name NVARCHAR(160) NOT NULL,
        SortOrder TINYINT NOT NULL,
        IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_FundingExperienceTypes_IsActive DEFAULT (1),
        CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FundingExperienceTypes_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FundingExperienceTypes_UpdatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FundingPlatform_PK_FundingExperienceTypes PRIMARY KEY (Id),
        CONSTRAINT FundingPlatform_UQ_FundingExperienceTypes_Code UNIQUE (Code),
        CONSTRAINT FundingPlatform_UQ_FundingExperienceTypes_SortOrder UNIQUE (SortOrder),
        CONSTRAINT FundingPlatform_CK_FundingExperienceTypes_Code CHECK
            (Code = UPPER(Code) AND Code NOT LIKE N'%[^A-Z0-9_]%' AND LEN(Code) BETWEEN 1 AND 60),
        CONSTRAINT FundingPlatform_CK_FundingExperienceTypes_SortOrder CHECK (SortOrder BETWEEN 1 AND 6)
    );
END;

DECLARE @ExpectedTypes TABLE
(
    Id SMALLINT NOT NULL PRIMARY KEY,
    Code NVARCHAR(60) NOT NULL UNIQUE,
    Name NVARCHAR(160) NOT NULL,
    SortOrder TINYINT NOT NULL UNIQUE
);
INSERT INTO @ExpectedTypes (Id, Code, Name, SortOrder)
VALUES
    (1, N'GOVERNMENTS_PUBLIC_FUNDS', N'Gobiernos / fondos públicos', 1),
    (2, N'FOUNDATIONS_GRANTMAKERS', N'Fundaciones / grantmakers', 2),
    (3, N'MULTILATERAL_ORGANIZATIONS', N'Organismos multilaterales', 3),
    (4, N'INTERNATIONAL_COOPERATION', N'Cooperación internacional', 4),
    (5, N'COMPANIES', N'Empresas', 5),
    (6, N'PHILANTHROPISTS', N'Filántropos', 6);

IF EXISTS
(
    SELECT 1
    FROM @ExpectedTypes AS seed
    INNER JOIN dbo.FundingPlatform_FundingExperienceTypes AS existing
        ON existing.Id = seed.Id OR existing.Code = seed.Code OR existing.SortOrder = seed.SortOrder
    WHERE existing.Id <> seed.Id OR existing.Code <> seed.Code
       OR existing.SortOrder <> seed.SortOrder
)
    THROW 55402, N'Funding experience type identifier, code or order collision.', 1;

INSERT INTO dbo.FundingPlatform_FundingExperienceTypes (Id, Code, Name, SortOrder)
SELECT seed.Id, seed.Code, seed.Name, seed.SortOrder
FROM @ExpectedTypes AS seed
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_FundingExperienceTypes AS existing
    WHERE existing.Id = seed.Id
);

IF EXISTS
(
    SELECT 1
    FROM @ExpectedTypes AS expected
    LEFT JOIN dbo.FundingPlatform_FundingExperienceTypes AS actual ON actual.Id = expected.Id
    WHERE actual.Id IS NULL OR actual.Code <> expected.Code OR actual.Name <> expected.Name
       OR actual.SortOrder <> expected.SortOrder OR actual.IsActive <> 1
)
    THROW 55403, N'Funding experience type catalog is inconsistent.', 1;

IF OBJECT_ID(N'dbo.FundingPlatform_OrganizationFundingExperienceTypes', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FundingPlatform_OrganizationFundingExperienceTypes
    (
        OrganizationId BIGINT NOT NULL,
        FundingExperienceTypeId SMALLINT NOT NULL,
        CreatedAtUtc DATETIME2(3) NOT NULL
            CONSTRAINT FundingPlatform_DF_OrganizationFundingExperienceTypes_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FundingPlatform_PK_OrganizationFundingExperienceTypes
            PRIMARY KEY (OrganizationId, FundingExperienceTypeId),
        CONSTRAINT FundingPlatform_FK_OrganizationFundingExperienceTypes_Organizations
            FOREIGN KEY (OrganizationId) REFERENCES dbo.FundingPlatform_Organizations (Id) ON DELETE CASCADE,
        CONSTRAINT FundingPlatform_FK_OrganizationFundingExperienceTypes_Types
            FOREIGN KEY (FundingExperienceTypeId)
            REFERENCES dbo.FundingPlatform_FundingExperienceTypes (Id)
    );
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Catalogs_GetForOrganizationProfile
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Iso2 AS Code, Name FROM dbo.FundingPlatform_Countries
    WHERE IsActive = 1 ORDER BY Name, Id;
    SELECT Id, CountryId, Code, Name FROM dbo.FundingPlatform_Regions
    WHERE IsActive = 1 ORDER BY CountryId, Name, Id;
    SELECT Code, Name, MinorUnits FROM dbo.FundingPlatform_Currencies
    WHERE IsActive = 1 ORDER BY Code;
    SELECT Id, Code, Name FROM dbo.FundingPlatform_FundingCategories
    WHERE IsActive = 1 ORDER BY Name, Id;
    SELECT Id, Code, Name FROM dbo.FundingPlatform_FundingTypes
    WHERE IsActive = 1 ORDER BY Name, Id;
    SELECT Id, Code, Name FROM dbo.FundingPlatform_OrganizationTypes
    WHERE IsActive = 1 ORDER BY Name, Id;
    SELECT Id, CountryId, Code, Name FROM dbo.FundingPlatform_LegalEntityTypes
    WHERE IsActive = 1 ORDER BY CountryId, Name, Id;
    SELECT Id, Code, Name FROM dbo.FundingPlatform_OrganizationSizes
    WHERE IsActive = 1 ORDER BY Id;
    SELECT Id, Code, Name FROM dbo.FundingPlatform_BeneficiaryTypes
    WHERE IsActive = 1 ORDER BY Name, Id;
    SELECT Id, Code, Name FROM dbo.FundingPlatform_ProjectTypes
    WHERE IsActive = 1 ORDER BY Name, Id;
    SELECT Id, NormalizedName AS Code, Name FROM dbo.FundingPlatform_Tags
    WHERE IsActive = 1 AND IsApproved = 1 ORDER BY Name, Id;
    SELECT Id, IsoCode AS Code, Name FROM dbo.FundingPlatform_Languages
    WHERE IsActive = 1 ORDER BY Name, Id;
    SELECT Id, Code, Name FROM dbo.FundingPlatform_SustainableDevelopmentGoals
    WHERE IsActive = 1 ORDER BY Id;

    /* Result set 14: optional prior-funder categories. */
    SELECT Id, Code, Name FROM dbo.FundingPlatform_FundingExperienceTypes
    WHERE IsActive = 1 ORDER BY SortOrder, Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Organization_GetProfile
    @OrganizationId BIGINT,
    @UserId BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FundingPlatform_GetProfile;

    BEGIN TRY
        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.FundingPlatform_OrganizationUsers WITH (UPDLOCK, HOLDLOCK)
            WHERE OrganizationId = @OrganizationId AND UserId = @UserId
              AND MembershipStatus = 1
        )
            THROW 51003, N'Active organization membership is required.', 1;

        SELECT o.Id, o.PublicId, o.CreatedByUserId, o.Name, o.LegalName, o.TaxIdentifier,
               o.HomeCountryId, o.OrganizationTypeId, o.LegalEntityTypeId, o.OrganizationSizeId,
               o.EstablishedYear, o.WebsiteUrl, o.Description, o.PreviousFundingExperience,
               o.ExperienceSummary, o.AnnualBudgetMin, o.AnnualBudgetMax, o.AnnualBudgetCurrency,
               o.DesiredFundingMin, o.DesiredFundingMax, o.DesiredFundingCurrency,
               o.ProfileStatus, o.ProfileCompleteness, o.ProfileVersion, o.IsActive,
               o.CreatedAtUtc, o.UpdatedAtUtc, o.RowVersion
        FROM dbo.FundingPlatform_Organizations AS o WHERE o.Id = @OrganizationId;

        SELECT CountryId AS Id FROM dbo.FundingPlatform_OrganizationCountries
        WHERE OrganizationId = @OrganizationId ORDER BY CountryId;
        SELECT RegionId AS Id FROM dbo.FundingPlatform_OrganizationRegions
        WHERE OrganizationId = @OrganizationId ORDER BY RegionId;
        SELECT FundingCategoryId AS Id FROM dbo.FundingPlatform_OrganizationCategories
        WHERE OrganizationId = @OrganizationId ORDER BY FundingCategoryId;
        SELECT BeneficiaryTypeId AS Id FROM dbo.FundingPlatform_OrganizationBeneficiaryTypes
        WHERE OrganizationId = @OrganizationId ORDER BY BeneficiaryTypeId;
        SELECT ProjectTypeId AS Id FROM dbo.FundingPlatform_OrganizationProjectTypes
        WHERE OrganizationId = @OrganizationId ORDER BY ProjectTypeId;
        SELECT TagId AS Id FROM dbo.FundingPlatform_OrganizationTags
        WHERE OrganizationId = @OrganizationId ORDER BY TagId;
        SELECT LanguageId, Proficiency FROM dbo.FundingPlatform_OrganizationLanguages
        WHERE OrganizationId = @OrganizationId ORDER BY LanguageId;
        SELECT FundingExperienceTypeId AS Id
        FROM dbo.FundingPlatform_OrganizationFundingExperienceTypes
        WHERE OrganizationId = @OrganizationId ORDER BY FundingExperienceTypeId;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FundingPlatform_GetProfile;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Organization_UpdateProfile
    @OrganizationId BIGINT,
    @ActorUserId BIGINT,
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
    @Languages dbo.FundingPlatform_OrganizationLanguageList READONLY,
    @PreviousFunderTypeIdsJson NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NULLIF(LTRIM(RTRIM(@Name)), N'') IS NULL
        THROW 51004, N'Organization name is required.', 1;
    IF ISJSON(@SnapshotJson) <> 1
        THROW 51005, N'Profile snapshot must be valid JSON.', 1;

    DECLARE @RequestedFunderTypes TABLE (Id SMALLINT NOT NULL PRIMARY KEY);
    IF @PreviousFunderTypeIdsJson IS NOT NULL
    BEGIN
        IF ISJSON(@PreviousFunderTypeIdsJson) <> 1
           OR LEFT(LTRIM(@PreviousFunderTypeIdsJson), 1) <> N'['
            THROW 51012, N'Previous funder type identifiers must be a JSON array.', 1;
        IF EXISTS
        (
            SELECT 1 FROM OPENJSON(@PreviousFunderTypeIdsJson)
            WHERE [type] <> 2 OR TRY_CONVERT(SMALLINT, [value]) IS NULL
               OR CONVERT(NVARCHAR(6), TRY_CONVERT(SMALLINT, [value]))
                    COLLATE Latin1_General_100_BIN2_UTF8
                  <> [value] COLLATE Latin1_General_100_BIN2_UTF8
        )
            THROW 51012, N'Previous funder type identifiers must be canonical integers.', 1;
        IF (SELECT COUNT_BIG(1) FROM OPENJSON(@PreviousFunderTypeIdsJson)) > 6
           OR EXISTS
           (
               SELECT TRY_CONVERT(SMALLINT, [value])
               FROM OPENJSON(@PreviousFunderTypeIdsJson)
               GROUP BY TRY_CONVERT(SMALLINT, [value]) HAVING COUNT_BIG(1) > 1
           )
            THROW 51012, N'Previous funder type identifiers must be unique and bounded.', 1;

        INSERT INTO @RequestedFunderTypes (Id)
        SELECT TRY_CONVERT(SMALLINT, [value]) FROM OPENJSON(@PreviousFunderTypeIdsJson);

        IF EXISTS
        (
            SELECT 1 FROM @RequestedFunderTypes AS requested
            LEFT JOIN dbo.FundingPlatform_FundingExperienceTypes AS types WITH (HOLDLOCK)
                ON types.Id = requested.Id AND types.IsActive = 1
            WHERE types.Id IS NULL
        )
            THROW 51012, N'One or more previous funder types are invalid.', 1;
        IF @PreviousFundingExperience <> 2 AND EXISTS (SELECT 1 FROM @RequestedFunderTypes)
            THROW 51012, N'Previous funder types require prior funding experience.', 1;

        IF JSON_QUERY(@SnapshotJson, N'$.fundingExperienceTypeIds') IS NULL
           OR EXISTS
           (
               SELECT 1 FROM OPENJSON(@SnapshotJson, N'$.fundingExperienceTypeIds')
               WHERE [type] <> 2 OR TRY_CONVERT(SMALLINT, [value]) IS NULL
                  OR CONVERT(NVARCHAR(6), TRY_CONVERT(SMALLINT, [value]))
                       COLLATE Latin1_General_100_BIN2_UTF8
                     <> [value] COLLATE Latin1_General_100_BIN2_UTF8
           )
           OR EXISTS
           (
               SELECT Id FROM @RequestedFunderTypes
               EXCEPT
               SELECT TRY_CONVERT(SMALLINT, [value])
               FROM OPENJSON(@SnapshotJson, N'$.fundingExperienceTypeIds')
           )
           OR EXISTS
           (
               SELECT TRY_CONVERT(SMALLINT, [value])
               FROM OPENJSON(@SnapshotJson, N'$.fundingExperienceTypeIds')
               EXCEPT
               SELECT Id FROM @RequestedFunderTypes
           )
           OR (SELECT COUNT_BIG(1) FROM OPENJSON(@SnapshotJson, N'$.fundingExperienceTypeIds'))
                <> (SELECT COUNT_BIG(1) FROM @RequestedFunderTypes)
            THROW 51012, N'Profile snapshot must contain the complete funding experience selection.', 1;
    END;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @NextProfileVersion INT;
    DECLARE @PayloadJson NVARCHAR(MAX);
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FundingPlatform_UpdateProfile;

    BEGIN TRY
        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.FundingPlatform_OrganizationUsers WITH (UPDLOCK, HOLDLOCK)
            WHERE OrganizationId = @OrganizationId AND UserId = @ActorUserId
              AND Role = 1 AND MembershipStatus = 1
        )
            THROW 51006, N'Active organization administrator membership is required.', 1;

        IF @PreviousFunderTypeIdsJson IS NULL AND EXISTS
        (
            SELECT 1 FROM dbo.FundingPlatform_OrganizationFundingExperienceTypes WITH (HOLDLOCK)
            WHERE OrganizationId = @OrganizationId
        )
            THROW 51011, N'Legacy profile update cannot snapshot funding experience links.', 1;

        IF EXISTS
        (
            SELECT 1 FROM @RegionIds AS selected
            LEFT JOIN dbo.FundingPlatform_Regions AS region WITH (HOLDLOCK)
                ON region.Id = selected.Id WHERE region.Id IS NULL
        )
            THROW 51007, N'One or more selected regions do not exist.', 1;
        IF EXISTS
        (
            SELECT 1 FROM @RegionIds AS selected
            INNER JOIN dbo.FundingPlatform_Regions AS region WITH (HOLDLOCK)
                ON region.Id = selected.Id
            WHERE NOT EXISTS
                (SELECT 1 FROM @CountryIds AS country WHERE country.Id = region.CountryId)
        )
            THROW 51010, N'Every selected region must belong to a selected operating country.', 1;

        SELECT @NextProfileVersion = ProfileVersion + 1
        FROM dbo.FundingPlatform_Organizations WITH (UPDLOCK, HOLDLOCK)
        WHERE Id = @OrganizationId;
        IF @NextProfileVersion IS NULL THROW 51008, N'Organization was not found.', 1;

        UPDATE dbo.FundingPlatform_Organizations
        SET Name = LTRIM(RTRIM(@Name)), LegalName = @LegalName,
            TaxIdentifier = @TaxIdentifier, HomeCountryId = @HomeCountryId,
            OrganizationTypeId = @OrganizationTypeId, LegalEntityTypeId = @LegalEntityTypeId,
            OrganizationSizeId = @OrganizationSizeId, EstablishedYear = @EstablishedYear,
            WebsiteUrl = @WebsiteUrl, Description = @Description,
            PreviousFundingExperience = @PreviousFundingExperience,
            ExperienceSummary = @ExperienceSummary, AnnualBudgetMin = @AnnualBudgetMin,
            AnnualBudgetMax = @AnnualBudgetMax, AnnualBudgetCurrency = @AnnualBudgetCurrency,
            DesiredFundingMin = @DesiredFundingMin, DesiredFundingMax = @DesiredFundingMax,
            DesiredFundingCurrency = @DesiredFundingCurrency, ProfileStatus = @ProfileStatus,
            ProfileCompleteness = @ProfileCompleteness, ProfileVersion = @NextProfileVersion,
            UpdatedAtUtc = @NowUtc
        WHERE Id = @OrganizationId AND RowVersion = @ExpectedRowVersion;
        IF @@ROWCOUNT = 0 THROW 51009, N'Organization profile has a concurrency conflict.', 1;

        DELETE FROM dbo.FundingPlatform_OrganizationCountries WHERE OrganizationId = @OrganizationId;
        DELETE FROM dbo.FundingPlatform_OrganizationRegions WHERE OrganizationId = @OrganizationId;
        DELETE FROM dbo.FundingPlatform_OrganizationCategories WHERE OrganizationId = @OrganizationId;
        DELETE FROM dbo.FundingPlatform_OrganizationBeneficiaryTypes WHERE OrganizationId = @OrganizationId;
        DELETE FROM dbo.FundingPlatform_OrganizationProjectTypes WHERE OrganizationId = @OrganizationId;
        DELETE FROM dbo.FundingPlatform_OrganizationTags WHERE OrganizationId = @OrganizationId;
        DELETE FROM dbo.FundingPlatform_OrganizationLanguages WHERE OrganizationId = @OrganizationId;
        IF @PreviousFunderTypeIdsJson IS NOT NULL
            DELETE FROM dbo.FundingPlatform_OrganizationFundingExperienceTypes
            WHERE OrganizationId = @OrganizationId;

        INSERT INTO dbo.FundingPlatform_OrganizationCountries (OrganizationId, CountryId)
            SELECT @OrganizationId, Id FROM @CountryIds;
        INSERT INTO dbo.FundingPlatform_OrganizationRegions (OrganizationId, RegionId)
            SELECT @OrganizationId, Id FROM @RegionIds;
        INSERT INTO dbo.FundingPlatform_OrganizationCategories (OrganizationId, FundingCategoryId)
            SELECT @OrganizationId, Id FROM @CategoryIds;
        INSERT INTO dbo.FundingPlatform_OrganizationBeneficiaryTypes (OrganizationId, BeneficiaryTypeId)
            SELECT @OrganizationId, Id FROM @BeneficiaryTypeIds;
        INSERT INTO dbo.FundingPlatform_OrganizationProjectTypes (OrganizationId, ProjectTypeId)
            SELECT @OrganizationId, Id FROM @ProjectTypeIds;
        INSERT INTO dbo.FundingPlatform_OrganizationTags (OrganizationId, TagId)
            SELECT @OrganizationId, Id FROM @TagIds;
        INSERT INTO dbo.FundingPlatform_OrganizationLanguages (OrganizationId, LanguageId, Proficiency)
            SELECT @OrganizationId, LanguageId, Proficiency FROM @Languages;
        IF @PreviousFunderTypeIdsJson IS NOT NULL
            INSERT INTO dbo.FundingPlatform_OrganizationFundingExperienceTypes
                (OrganizationId, FundingExperienceTypeId)
            SELECT @OrganizationId, Id FROM @RequestedFunderTypes;

        INSERT INTO dbo.FundingPlatform_OrganizationProfileVersions
            (OrganizationId, ProfileVersion, SnapshotJson, ContentHash, CreatedByUserId, CreatedAtUtc)
        VALUES (@OrganizationId, @NextProfileVersion, @SnapshotJson, @ContentHash,
                @ActorUserId, @NowUtc);
        SELECT @PayloadJson =
        (
            SELECT @OrganizationId AS organizationId, @NextProfileVersion AS profileVersion
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );
        INSERT INTO dbo.FundingPlatform_OutboxMessages
            (MessageType, AggregateType, AggregateId, PayloadJson, OccurredAtUtc, AvailableAtUtc)
        VALUES (N'OrganizationProfileChanged', N'Organization',
                CONVERT(NVARCHAR(100), @OrganizationId), @PayloadJson, @NowUtc, @NowUtc);

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FundingPlatform_UpdateProfile;
        THROW;
    END CATCH;

    SELECT Id, PublicId, ProfileVersion, RowVersion
    FROM dbo.FundingPlatform_Organizations WHERE Id = @OrganizationId;
END;
GO

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
    @Languages dbo.FundingPlatform_OrganizationLanguageList READONLY,
    @PreviousFunderTypeIdsJson NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @OrganizationId BIGINT;
    DECLARE @UserId BIGINT;
    SELECT @OrganizationId = Id FROM dbo.FundingPlatform_Organizations
    WHERE PublicId = @OrganizationPublicId AND IsActive = 1;
    SELECT @UserId = Id FROM dbo.FundingPlatform_Users
    WHERE PublicId = @UserPublicId AND Status = 2;
    IF @OrganizationId IS NULL OR @UserId IS NULL
        THROW 51204, N'The organization profile was not found.', 1;

    EXEC dbo.FundingPlatform_usp_Organization_UpdateProfile
        @OrganizationId = @OrganizationId, @ActorUserId = @UserId,
        @ExpectedRowVersion = @ExpectedRowVersion, @Name = @Name,
        @LegalName = @LegalName, @TaxIdentifier = @TaxIdentifier,
        @HomeCountryId = @HomeCountryId, @OrganizationTypeId = @OrganizationTypeId,
        @LegalEntityTypeId = @LegalEntityTypeId, @OrganizationSizeId = @OrganizationSizeId,
        @EstablishedYear = @EstablishedYear, @WebsiteUrl = @WebsiteUrl,
        @Description = @Description, @PreviousFundingExperience = @PreviousFundingExperience,
        @ExperienceSummary = @ExperienceSummary, @AnnualBudgetMin = @AnnualBudgetMin,
        @AnnualBudgetMax = @AnnualBudgetMax, @AnnualBudgetCurrency = @AnnualBudgetCurrency,
        @DesiredFundingMin = @DesiredFundingMin, @DesiredFundingMax = @DesiredFundingMax,
        @DesiredFundingCurrency = @DesiredFundingCurrency, @ProfileStatus = @ProfileStatus,
        @ProfileCompleteness = @ProfileCompleteness, @SnapshotJson = @SnapshotJson,
        @ContentHash = @ContentHash, @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds, @TagIds = @TagIds, @Languages = @Languages,
        @PreviousFunderTypeIdsJson = @PreviousFunderTypeIdsJson;
END;
GO
