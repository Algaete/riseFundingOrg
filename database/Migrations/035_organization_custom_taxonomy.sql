/* FundingPlatform - private organization custom taxonomy values.
   Requires migrations 001-034.

   Four organization-private dimensions are supported: impact area, beneficiary type,
   project type and language. They are deliberately excluded from public catalogs,
   tags, search, matching and networking.

   Compatibility rules:
   - the optional JSON parameter is appended to both existing profile write procedures;
   - NULL is a legacy call and may update only organizations without custom values;
   - [] explicitly clears all custom values;
   - deploy database, then route 100% of API traffic to the new build, then deploy UI.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF OBJECT_ID(N'dbo.FundingPlatform_Organizations', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_Users', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_OrganizationFundingExperienceTypes', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_Organization_GetProfile', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_Organization_UpdateProfile', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_Organization_UpdateProfileByPublicId', N'P') IS NULL
    THROW 55501, N'Organization custom taxonomy requires migrations 001-034.', 1;

IF OBJECT_ID(N'dbo.FundingPlatform_OrganizationCustomTaxonomyValues', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FundingPlatform_OrganizationCustomTaxonomyValues
    (
        Id BIGINT IDENTITY(1,1) NOT NULL,
        OrganizationId BIGINT NOT NULL,
        Kind TINYINT NOT NULL,
        Name NVARCHAR(100) COLLATE Latin1_General_100_CI_AI_SC NOT NULL,
        NormalizedName NVARCHAR(100) COLLATE Latin1_General_100_CI_AI_SC NOT NULL,
        CreatedByUserId BIGINT NOT NULL,
        CreatedAtUtc DATETIME2(3) NOT NULL
            CONSTRAINT FundingPlatform_DF_OrganizationCustomTaxonomyValues_CreatedAt
            DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FundingPlatform_PK_OrganizationCustomTaxonomyValues PRIMARY KEY (Id),
        CONSTRAINT FundingPlatform_UQ_OrganizationCustomTaxonomyValues
            UNIQUE (OrganizationId, Kind, NormalizedName),
        CONSTRAINT FundingPlatform_UQ_OrganizationCustomTaxonomyValues_Name
            UNIQUE (OrganizationId, Kind, Name),
        CONSTRAINT FundingPlatform_FK_OrganizationCustomTaxonomyValues_Organizations
            FOREIGN KEY (OrganizationId) REFERENCES dbo.FundingPlatform_Organizations (Id)
            ON DELETE CASCADE,
        CONSTRAINT FundingPlatform_FK_OrganizationCustomTaxonomyValues_CreatedBy
            FOREIGN KEY (CreatedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
        CONSTRAINT FundingPlatform_CK_OrganizationCustomTaxonomyValues_Kind
            CHECK (Kind BETWEEN 1 AND 4),
        CONSTRAINT FundingPlatform_CK_OrganizationCustomTaxonomyValues_Name
            CHECK (LEN(Name) BETWEEN 2 AND 100
                   AND DATALENGTH(Name) = DATALENGTH(LTRIM(RTRIM(Name)))
                   AND Name NOT LIKE N'%  %' AND CHARINDEX(NCHAR(9), Name) = 0
                   AND CHARINDEX(NCHAR(10), Name) = 0 AND CHARINDEX(NCHAR(13), Name) = 0),
        CONSTRAINT FundingPlatform_CK_OrganizationCustomTaxonomyValues_NormalizedName
            CHECK (LEN(NormalizedName) BETWEEN 2 AND 100
                   AND NormalizedName COLLATE Latin1_General_100_BIN2 =
                       UPPER(NormalizedName) COLLATE Latin1_General_100_BIN2
                   AND DATALENGTH(NormalizedName) =
                       DATALENGTH(LTRIM(RTRIM(NormalizedName)))
                   AND NormalizedName COLLATE Latin1_General_100_CI_AI_SC =
                       Name COLLATE Latin1_General_100_CI_AI_SC
                   AND NormalizedName NOT LIKE N'%  %'
                   AND CHARINDEX(NCHAR(9), NormalizedName) = 0
                   AND CHARINDEX(NCHAR(10), NormalizedName) = 0
                   AND CHARINDEX(NCHAR(13), NormalizedName) = 0)
    );
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
        SELECT Kind, Name, NormalizedName
        FROM dbo.FundingPlatform_OrganizationCustomTaxonomyValues
        WHERE OrganizationId = @OrganizationId
        ORDER BY Kind, NormalizedName COLLATE Latin1_General_100_BIN2, Id;

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
    @PreviousFunderTypeIdsJson NVARCHAR(1000) = NULL,
    @CustomTaxonomyValuesJson NVARCHAR(MAX) = NULL
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

    DECLARE @RequestedCustomTaxonomy TABLE
    (
        Kind TINYINT NOT NULL,
        Name NVARCHAR(100) NOT NULL,
        NormalizedName NVARCHAR(100) COLLATE Latin1_General_100_CI_AI_SC NOT NULL,
        PRIMARY KEY (Kind, NormalizedName)
    );
    IF @CustomTaxonomyValuesJson IS NOT NULL
    BEGIN
        /* 32 Ki UTF-16 characters cover the worst-case escaped representation of
           20 display/normalized names while bounding parser memory and CPU. */
        IF DATALENGTH(@CustomTaxonomyValuesJson) > 65536
            THROW 51014, N'Custom taxonomy JSON exceeds the bounded payload size.', 1;
        IF ISJSON(@CustomTaxonomyValuesJson) <> 1
           OR LEFT(LTRIM(@CustomTaxonomyValuesJson), 1) <> N'['
            THROW 51014, N'Custom taxonomy values must be a JSON array.', 1;
        IF (SELECT COUNT_BIG(1) FROM OPENJSON(@CustomTaxonomyValuesJson)) > 20
           OR EXISTS (SELECT 1 FROM OPENJSON(@CustomTaxonomyValuesJson) WHERE [type] <> 5)
            THROW 51014, N'Custom taxonomy values must be an array of at most 20 objects.', 1;
        IF EXISTS
        (
            SELECT 1
            FROM OPENJSON(@CustomTaxonomyValuesJson) AS item
            WHERE (SELECT COUNT_BIG(1) FROM OPENJSON(item.[value])) <> 3
               OR NOT EXISTS (SELECT 1 FROM OPENJSON(item.[value]) WHERE [key] COLLATE Latin1_General_100_BIN2 = N'kind' AND [type] = 2)
               OR NOT EXISTS (SELECT 1 FROM OPENJSON(item.[value]) WHERE [key] COLLATE Latin1_General_100_BIN2 = N'name' AND [type] = 1)
               OR NOT EXISTS (SELECT 1 FROM OPENJSON(item.[value]) WHERE [key] COLLATE Latin1_General_100_BIN2 = N'normalizedName' AND [type] = 1)
               OR JSON_VALUE(item.[value], N'$.kind') IS NULL
               OR JSON_VALUE(item.[value], N'$.name') IS NULL
               OR JSON_VALUE(item.[value], N'$.normalizedName') IS NULL
               OR TRY_CONVERT(TINYINT, JSON_VALUE(item.[value], N'$.kind')) IS NULL
               OR TRY_CONVERT(TINYINT, JSON_VALUE(item.[value], N'$.kind')) NOT BETWEEN 1 AND 4
               OR CONVERT(NVARCHAR(3), TRY_CONVERT(TINYINT, JSON_VALUE(item.[value], N'$.kind')))
                    COLLATE Latin1_General_100_BIN2
                  <> JSON_VALUE(item.[value], N'$.kind') COLLATE Latin1_General_100_BIN2
               OR LEN(JSON_VALUE(item.[value], N'$.name')) NOT BETWEEN 2 AND 100
               OR DATALENGTH(JSON_VALUE(item.[value], N'$.name')) <>
                  DATALENGTH(LTRIM(RTRIM(JSON_VALUE(item.[value], N'$.name'))))
               OR JSON_VALUE(item.[value], N'$.name') LIKE N'%  %'
               OR CHARINDEX(NCHAR(9), JSON_VALUE(item.[value], N'$.name')) > 0
               OR CHARINDEX(NCHAR(10), JSON_VALUE(item.[value], N'$.name')) > 0
               OR CHARINDEX(NCHAR(13), JSON_VALUE(item.[value], N'$.name')) > 0
               OR LEN(JSON_VALUE(item.[value], N'$.normalizedName')) NOT BETWEEN 2 AND 100
               OR JSON_VALUE(item.[value], N'$.normalizedName') COLLATE Latin1_General_100_BIN2 <>
                  UPPER(JSON_VALUE(item.[value], N'$.normalizedName')) COLLATE Latin1_General_100_BIN2
               OR DATALENGTH(JSON_VALUE(item.[value], N'$.normalizedName')) <>
                  DATALENGTH(LTRIM(RTRIM(JSON_VALUE(item.[value], N'$.normalizedName'))))
               OR JSON_VALUE(item.[value], N'$.normalizedName') COLLATE Latin1_General_100_CI_AI_SC <>
                  JSON_VALUE(item.[value], N'$.name') COLLATE Latin1_General_100_CI_AI_SC
               OR JSON_VALUE(item.[value], N'$.normalizedName') LIKE N'%  %'
               OR CHARINDEX(NCHAR(9), JSON_VALUE(item.[value], N'$.normalizedName')) > 0
               OR CHARINDEX(NCHAR(10), JSON_VALUE(item.[value], N'$.normalizedName')) > 0
               OR CHARINDEX(NCHAR(13), JSON_VALUE(item.[value], N'$.normalizedName')) > 0
        )
            THROW 51014, N'Each custom taxonomy value must contain a canonical kind, name and normalizedName.', 1;
        IF EXISTS
        (
            SELECT TRY_CONVERT(TINYINT, JSON_VALUE([value], N'$.kind')),
                   JSON_VALUE([value], N'$.normalizedName') COLLATE Latin1_General_100_CI_AI_SC
            FROM OPENJSON(@CustomTaxonomyValuesJson)
            GROUP BY TRY_CONVERT(TINYINT, JSON_VALUE([value], N'$.kind')),
                     JSON_VALUE([value], N'$.normalizedName') COLLATE Latin1_General_100_CI_AI_SC
            HAVING COUNT_BIG(1) > 1
        )
            THROW 51014, N'Custom taxonomy values must be unique per dimension.', 1;
        IF EXISTS
        (
            SELECT TRY_CONVERT(TINYINT, JSON_VALUE([value], N'$.kind')),
                   JSON_VALUE([value], N'$.name') COLLATE Latin1_General_100_CI_AI_SC
            FROM OPENJSON(@CustomTaxonomyValuesJson)
            GROUP BY TRY_CONVERT(TINYINT, JSON_VALUE([value], N'$.kind')),
                     JSON_VALUE([value], N'$.name') COLLATE Latin1_General_100_CI_AI_SC
            HAVING COUNT_BIG(1) > 1
        )
            THROW 51014, N'Custom taxonomy display names must be unique per dimension.', 1;
        IF EXISTS
        (
            SELECT TRY_CONVERT(TINYINT, JSON_VALUE([value], N'$.kind'))
            FROM OPENJSON(@CustomTaxonomyValuesJson)
            GROUP BY TRY_CONVERT(TINYINT, JSON_VALUE([value], N'$.kind'))
            HAVING COUNT_BIG(1) > 5
        )
            THROW 51014, N'Custom taxonomy values are limited to five per dimension.', 1;

        INSERT INTO @RequestedCustomTaxonomy (Kind, Name, NormalizedName)
        SELECT TRY_CONVERT(TINYINT, JSON_VALUE([value], N'$.kind')),
               JSON_VALUE([value], N'$.name'),
               JSON_VALUE([value], N'$.normalizedName')
        FROM OPENJSON(@CustomTaxonomyValuesJson);

        IF JSON_QUERY(@SnapshotJson, N'$.customTaxonomyValues') IS NULL
           OR LEFT(LTRIM(JSON_QUERY(@SnapshotJson, N'$.customTaxonomyValues')), 1) <> N'['
           OR EXISTS
           (
               SELECT 1
               FROM OPENJSON(@SnapshotJson, N'$.customTaxonomyValues') AS item
               WHERE item.[type] <> 5
                  OR (SELECT COUNT_BIG(1) FROM OPENJSON(item.[value])) <> 2
                  OR NOT EXISTS (SELECT 1 FROM OPENJSON(item.[value]) WHERE [key] COLLATE Latin1_General_100_BIN2 = N'kind' AND [type] = 2)
                  OR NOT EXISTS (SELECT 1 FROM OPENJSON(item.[value]) WHERE [key] COLLATE Latin1_General_100_BIN2 = N'name' AND [type] = 1)
                  OR JSON_VALUE(item.[value], N'$.kind') IS NULL
                  OR JSON_VALUE(item.[value], N'$.name') IS NULL
                  OR TRY_CONVERT(TINYINT, JSON_VALUE(item.[value], N'$.kind')) IS NULL
                  OR TRY_CONVERT(TINYINT, JSON_VALUE(item.[value], N'$.kind')) NOT BETWEEN 1 AND 4
                  OR CONVERT(NVARCHAR(3), TRY_CONVERT(TINYINT, JSON_VALUE(item.[value], N'$.kind')))
                       COLLATE Latin1_General_100_BIN2 <>
                     JSON_VALUE(item.[value], N'$.kind') COLLATE Latin1_General_100_BIN2
           )
           OR EXISTS
           (
               SELECT Kind, Name COLLATE Latin1_General_100_BIN2 FROM @RequestedCustomTaxonomy
               EXCEPT
               SELECT TRY_CONVERT(TINYINT, JSON_VALUE([value], N'$.kind')),
                      JSON_VALUE([value], N'$.name') COLLATE Latin1_General_100_BIN2
               FROM OPENJSON(@SnapshotJson, N'$.customTaxonomyValues')
           )
           OR EXISTS
           (
               SELECT TRY_CONVERT(TINYINT, JSON_VALUE([value], N'$.kind')),
                      JSON_VALUE([value], N'$.name') COLLATE Latin1_General_100_BIN2
               FROM OPENJSON(@SnapshotJson, N'$.customTaxonomyValues')
               EXCEPT
               SELECT Kind, Name COLLATE Latin1_General_100_BIN2 FROM @RequestedCustomTaxonomy
           )
           OR (SELECT COUNT_BIG(1) FROM OPENJSON(@SnapshotJson, N'$.customTaxonomyValues'))
                <> (SELECT COUNT_BIG(1) FROM @RequestedCustomTaxonomy)
            THROW 51014, N'Profile snapshot must contain the complete custom taxonomy selection.', 1;
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
        IF @CustomTaxonomyValuesJson IS NULL AND EXISTS
        (
            SELECT 1 FROM dbo.FundingPlatform_OrganizationCustomTaxonomyValues WITH (HOLDLOCK)
            WHERE OrganizationId = @OrganizationId
        )
            THROW 51013, N'Legacy profile update cannot snapshot custom taxonomy values.', 1;

        IF @CustomTaxonomyValuesJson IS NOT NULL AND EXISTS
        (
            SELECT 1
            FROM @RequestedCustomTaxonomy AS custom
            WHERE (custom.Kind = 1 AND EXISTS
                  (SELECT 1 FROM dbo.FundingPlatform_FundingCategories AS catalog WITH (HOLDLOCK)
                   WHERE catalog.IsActive = 1
                     AND catalog.Name COLLATE Latin1_General_100_CI_AI_SC =
                         custom.Name COLLATE Latin1_General_100_CI_AI_SC))
               OR (custom.Kind = 2 AND EXISTS
                  (SELECT 1 FROM dbo.FundingPlatform_BeneficiaryTypes AS catalog WITH (HOLDLOCK)
                   WHERE catalog.IsActive = 1
                     AND catalog.Name COLLATE Latin1_General_100_CI_AI_SC =
                         custom.Name COLLATE Latin1_General_100_CI_AI_SC))
               OR (custom.Kind = 3 AND EXISTS
                  (SELECT 1 FROM dbo.FundingPlatform_ProjectTypes AS catalog WITH (HOLDLOCK)
                   WHERE catalog.IsActive = 1
                     AND catalog.Name COLLATE Latin1_General_100_CI_AI_SC =
                         custom.Name COLLATE Latin1_General_100_CI_AI_SC))
               OR (custom.Kind = 4 AND EXISTS
                  (SELECT 1 FROM dbo.FundingPlatform_Languages AS catalog WITH (HOLDLOCK)
                   WHERE catalog.IsActive = 1
                     AND catalog.Name COLLATE Latin1_General_100_CI_AI_SC =
                         custom.Name COLLATE Latin1_General_100_CI_AI_SC))
        )
            THROW 51014, N'Custom taxonomy value duplicates an official catalog option.', 1;

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
        IF @CustomTaxonomyValuesJson IS NOT NULL
            DELETE FROM dbo.FundingPlatform_OrganizationCustomTaxonomyValues
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
        IF @CustomTaxonomyValuesJson IS NOT NULL
            INSERT INTO dbo.FundingPlatform_OrganizationCustomTaxonomyValues
                (OrganizationId, Kind, Name, NormalizedName, CreatedByUserId)
            SELECT @OrganizationId, Kind, Name, NormalizedName, @ActorUserId
            FROM @RequestedCustomTaxonomy;

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
    @PreviousFunderTypeIdsJson NVARCHAR(1000) = NULL,
    @CustomTaxonomyValuesJson NVARCHAR(MAX) = NULL
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
        @PreviousFunderTypeIdsJson = @PreviousFunderTypeIdsJson,
        @CustomTaxonomyValuesJson = @CustomTaxonomyValuesJson;
END;
GO
