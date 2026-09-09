/* FundingPlatform - project impact profile (stage and the 17 UN SDGs).
   Requires migrations 001-032.

   Compatibility rules:
   - ProjectStage is independent from the historical ProjectStatus field;
   - existing projects remain valid with a NULL stage and no SDG links;
   - the v1 write procedures keep their names and original parameters;
   - optional scalar compatibility parameters are appended so an older API can
     keep writing projects without impact data during a rolling deployment;
   - an old update that omits the new fields fails closed (51411) when the
     project already has a stage or SDG links, preventing incomplete snapshots.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF OBJECT_ID(N'dbo.FundingPlatform_Projects', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ProjectVersions', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_Project_Update', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMarketplace_GetBySlug', N'P') IS NULL
    THROW 55301, N'Project impact profile requires migrations 001-032.', 1;

IF COL_LENGTH(N'dbo.FundingPlatform_Projects', N'ProjectStage') IS NULL
    ALTER TABLE dbo.FundingPlatform_Projects ADD ProjectStage TINYINT NULL;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_Projects')
      AND name = N'FundingPlatform_CK_Projects_ProjectStage'
)
    ALTER TABLE dbo.FundingPlatform_Projects WITH CHECK
        ADD CONSTRAINT FundingPlatform_CK_Projects_ProjectStage
        CHECK (ProjectStage IS NULL OR ProjectStage BETWEEN 0 AND 5);

IF OBJECT_ID(N'dbo.FundingPlatform_SustainableDevelopmentGoals', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FundingPlatform_SustainableDevelopmentGoals
    (
        Id INT NOT NULL,
        Code NVARCHAR(20) NOT NULL,
        Name NVARCHAR(180) NOT NULL,
        IsActive BIT NOT NULL
            CONSTRAINT FundingPlatform_DF_SustainableDevelopmentGoals_IsActive DEFAULT (1),
        CreatedAtUtc DATETIME2(3) NOT NULL
            CONSTRAINT FundingPlatform_DF_SustainableDevelopmentGoals_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
        UpdatedAtUtc DATETIME2(3) NOT NULL
            CONSTRAINT FundingPlatform_DF_SustainableDevelopmentGoals_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FundingPlatform_PK_SustainableDevelopmentGoals PRIMARY KEY (Id),
        CONSTRAINT FundingPlatform_UQ_SustainableDevelopmentGoals_Code UNIQUE (Code),
        CONSTRAINT FundingPlatform_CK_SustainableDevelopmentGoals_Id CHECK (Id BETWEEN 1 AND 17)
    );
END;

DECLARE @Goals TABLE
(
    Id INT NOT NULL PRIMARY KEY,
    Code NVARCHAR(20) NOT NULL UNIQUE,
    Name NVARCHAR(180) NOT NULL
);

INSERT INTO @Goals (Id, Code, Name)
VALUES
    (1, N'SDG_01', N'Fin de la pobreza'),
    (2, N'SDG_02', N'Hambre cero'),
    (3, N'SDG_03', N'Salud y bienestar'),
    (4, N'SDG_04', N'Educación de calidad'),
    (5, N'SDG_05', N'Igualdad de género'),
    (6, N'SDG_06', N'Agua limpia y saneamiento'),
    (7, N'SDG_07', N'Energía asequible y no contaminante'),
    (8, N'SDG_08', N'Trabajo decente y crecimiento económico'),
    (9, N'SDG_09', N'Industria, innovación e infraestructura'),
    (10, N'SDG_10', N'Reducción de las desigualdades'),
    (11, N'SDG_11', N'Ciudades y comunidades sostenibles'),
    (12, N'SDG_12', N'Producción y consumo responsables'),
    (13, N'SDG_13', N'Acción por el clima'),
    (14, N'SDG_14', N'Vida submarina'),
    (15, N'SDG_15', N'Vida de ecosistemas terrestres'),
    (16, N'SDG_16', N'Paz, justicia e instituciones sólidas'),
    (17, N'SDG_17', N'Alianzas para lograr los objetivos');

IF EXISTS
(
    SELECT 1
    FROM @Goals AS Seed
    INNER JOIN dbo.FundingPlatform_SustainableDevelopmentGoals AS Existing
        ON Existing.Id = Seed.Id OR Existing.Code = Seed.Code
    WHERE Existing.Id <> Seed.Id OR Existing.Code <> Seed.Code
)
    THROW 55302, N'SDG catalog identifier or code collision.', 1;

INSERT INTO dbo.FundingPlatform_SustainableDevelopmentGoals (Id, Code, Name)
SELECT Seed.Id, Seed.Code, Seed.Name
FROM @Goals AS Seed
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_SustainableDevelopmentGoals AS Existing
    WHERE Existing.Id = Seed.Id
);

IF EXISTS
(
    SELECT 1
    FROM @Goals AS Seed
    LEFT JOIN dbo.FundingPlatform_SustainableDevelopmentGoals AS Existing
        ON Existing.Id = Seed.Id
    WHERE Existing.Id IS NULL
       OR Existing.Code <> Seed.Code
       OR Existing.Name <> Seed.Name
       OR Existing.IsActive <> 1
)
    THROW 55303, N'SDG catalog is inconsistent with the official 17-goal seed.', 1;

IF OBJECT_ID(N'dbo.FundingPlatform_ProjectSustainableDevelopmentGoals', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FundingPlatform_ProjectSustainableDevelopmentGoals
    (
        ProjectId BIGINT NOT NULL,
        SustainableDevelopmentGoalId INT NOT NULL,
        CONSTRAINT FundingPlatform_PK_ProjectSustainableDevelopmentGoals
            PRIMARY KEY (ProjectId, SustainableDevelopmentGoalId),
        CONSTRAINT FundingPlatform_FK_ProjectSustainableDevelopmentGoals_Projects
            FOREIGN KEY (ProjectId) REFERENCES dbo.FundingPlatform_Projects (Id) ON DELETE CASCADE,
        CONSTRAINT FundingPlatform_FK_ProjectSustainableDevelopmentGoals_Goals
            FOREIGN KEY (SustainableDevelopmentGoalId)
            REFERENCES dbo.FundingPlatform_SustainableDevelopmentGoals (Id)
    );

    CREATE INDEX FundingPlatform_IX_ProjectSustainableDevelopmentGoals_Goal_Project
        ON dbo.FundingPlatform_ProjectSustainableDevelopmentGoals
            (SustainableDevelopmentGoalId, ProjectId);
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Project_AdminReviewQueue_List
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @PageNumber INT = 1,
    @PageSize INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    IF @PageNumber < 1 THROW 51501, N'PageNumber must be at least 1.', 1;
    IF @PageSize < 1 OR @PageSize > 100
        THROW 51502, N'PageSize must be between 1 and 100.', 1;
    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_Users AS users
        INNER JOIN dbo.FundingPlatform_UserRoles AS userRoles ON userRoles.UserId = users.Id
        INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
        WHERE users.PublicId = @AdminUserPublicId AND users.Status = 2
          AND roles.NormalizedName IN (N'ADMIN', N'SUPERADMIN')
    ) THROW 51503, N'Active Admin or SuperAdmin role is required.', 1;

    SELECT COUNT_BIG(1) AS TotalCount
    FROM dbo.FundingPlatform_Projects AS projects
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = projects.OrganizationId AND organizations.IsActive = 1
    WHERE projects.PublicationStatus = 1 AND projects.IsActive = 1;

    SELECT projects.PublicId AS ProjectPublicId, projects.Slug, projects.Title, projects.Summary,
           projects.ProjectStatus, projects.ProjectStage, projects.PublicationStatus,
           projects.SubmittedAtUtc,
           CAST(CASE WHEN organizations.ProfileStatus = 2
                           AND organizations.ProfileCompleteness >= 80
                     THEN 100.00 ELSE 90.00 END AS DECIMAL(5,2)) AS Completeness,
           projects.ProjectVersion, projects.UpdatedAtUtc, projects.RowVersion,
           organizations.PublicId AS OrganizationPublicId, organizations.Name AS OrganizationName
    FROM dbo.FundingPlatform_Projects AS projects
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = projects.OrganizationId AND organizations.IsActive = 1
    WHERE projects.PublicationStatus = 1 AND projects.IsActive = 1
    ORDER BY projects.SubmittedAtUtc, projects.Id
    OFFSET ((@PageNumber - 1) * @PageSize) ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Project_AdminReview_Get
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_Users AS users
        INNER JOIN dbo.FundingPlatform_UserRoles AS userRoles ON userRoles.UserId = users.Id
        INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
        WHERE users.PublicId = @AdminUserPublicId AND users.Status = 2
          AND roles.NormalizedName IN (N'ADMIN', N'SUPERADMIN')
    ) THROW 51503, N'Active Admin or SuperAdmin role is required.', 1;

    SELECT projects.PublicId AS ProjectPublicId,
           projects.Slug, projects.Title, projects.Summary, projects.Description,
           projects.ProjectStatus, projects.ProjectStage, projects.PublicationStatus,
           projects.StartDate, projects.EndDate, projects.BudgetTotal,
           projects.ConfirmedFunding, projects.Currency, projects.FundingGap,
           projects.ProjectVersion, projects.PublishedAtUtc, projects.UpdatedAtUtc,
           organizations.PublicId AS OrganizationPublicId,
           organizations.Name AS OrganizationName,
           organizations.WebsiteUrl AS OrganizationWebsiteUrl,
           projects.SubmittedAtUtc, projects.RejectionReason,
           CONVERT(DECIMAL(5,2), 100
               - CASE WHEN organizations.ProfileStatus = 2
                            AND organizations.ProfileCompleteness >= 80 THEN 0 ELSE 10 END
               - CASE WHEN NULLIF(LTRIM(RTRIM(projects.Title)), N'') IS NOT NULL THEN 0 ELSE 10 END
               - CASE WHEN NULLIF(LTRIM(RTRIM(projects.Summary)), N'') IS NOT NULL THEN 0 ELSE 10 END
               - CASE WHEN NULLIF(LTRIM(RTRIM(projects.Description)), N'') IS NOT NULL THEN 0 ELSE 10 END
               - CASE WHEN NULLIF(LTRIM(RTRIM(projects.Slug)), N'') IS NOT NULL THEN 0 ELSE 10 END
               - CASE WHEN projects.BudgetTotal > 0 AND projects.Currency IS NOT NULL THEN 0 ELSE 10 END
               - CASE WHEN EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectCountries x WHERE x.ProjectId = projects.Id) THEN 0 ELSE 10 END
               - CASE WHEN EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectCategories x WHERE x.ProjectId = projects.Id) THEN 0 ELSE 10 END
               - CASE WHEN EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectBeneficiaryTypes x WHERE x.ProjectId = projects.Id) THEN 0 ELSE 10 END
               - CASE WHEN EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectProjectTypes x WHERE x.ProjectId = projects.Id) THEN 0 ELSE 10 END
           ) AS Completeness,
           projects.RowVersion,
           JSON_QUERY(COALESCE
           (
               (SELECT countries.Id AS id, RTRIM(countries.Iso2) AS code, countries.Name AS name
                FROM dbo.FundingPlatform_ProjectCountries AS projectCountries
                INNER JOIN dbo.FundingPlatform_Countries AS countries
                    ON countries.Id = projectCountries.CountryId AND countries.IsActive = 1
                WHERE projectCountries.ProjectId = projects.Id
                ORDER BY countries.Name, countries.Id FOR JSON PATH), N'[]'
           )) AS CountriesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT regions.Id AS id, regions.CountryId AS countryId,
                       regions.Code AS code, regions.Name AS name
                FROM dbo.FundingPlatform_ProjectRegions AS projectRegions
                INNER JOIN dbo.FundingPlatform_Regions AS regions
                    ON regions.Id = projectRegions.RegionId AND regions.IsActive = 1
                WHERE projectRegions.ProjectId = projects.Id
                ORDER BY regions.Name, regions.Id FOR JSON PATH), N'[]'
           )) AS RegionsJson,
           JSON_QUERY(COALESCE
           (
               (SELECT categories.Id AS id, categories.Code AS code, categories.Name AS name
                FROM dbo.FundingPlatform_ProjectCategories AS projectCategories
                INNER JOIN dbo.FundingPlatform_FundingCategories AS categories
                    ON categories.Id = projectCategories.FundingCategoryId AND categories.IsActive = 1
                WHERE projectCategories.ProjectId = projects.Id
                ORDER BY categories.Name, categories.Id FOR JSON PATH), N'[]'
           )) AS CategoriesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT beneficiaryTypes.Id AS id, beneficiaryTypes.Code AS code,
                       beneficiaryTypes.Name AS name
                FROM dbo.FundingPlatform_ProjectBeneficiaryTypes AS projectBeneficiaryTypes
                INNER JOIN dbo.FundingPlatform_BeneficiaryTypes AS beneficiaryTypes
                    ON beneficiaryTypes.Id = projectBeneficiaryTypes.BeneficiaryTypeId
                   AND beneficiaryTypes.IsActive = 1
                WHERE projectBeneficiaryTypes.ProjectId = projects.Id
                ORDER BY beneficiaryTypes.Name, beneficiaryTypes.Id FOR JSON PATH), N'[]'
           )) AS BeneficiaryTypesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT projectTypes.Id AS id, projectTypes.Code AS code, projectTypes.Name AS name
                FROM dbo.FundingPlatform_ProjectProjectTypes AS projectProjectTypes
                INNER JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
                    ON projectTypes.Id = projectProjectTypes.ProjectTypeId AND projectTypes.IsActive = 1
                WHERE projectProjectTypes.ProjectId = projects.Id
                ORDER BY projectTypes.Name, projectTypes.Id FOR JSON PATH), N'[]'
           )) AS ProjectTypesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT goals.Id AS id, goals.Code AS code, goals.Name AS name
                FROM dbo.FundingPlatform_ProjectSustainableDevelopmentGoals AS projectGoals
                INNER JOIN dbo.FundingPlatform_SustainableDevelopmentGoals AS goals
                    ON goals.Id = projectGoals.SustainableDevelopmentGoalId AND goals.IsActive = 1
                WHERE projectGoals.ProjectId = projects.Id
                ORDER BY goals.Id FOR JSON PATH), N'[]'
           )) AS SustainableDevelopmentGoalsJson
    FROM dbo.FundingPlatform_Projects AS projects
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = projects.OrganizationId AND organizations.IsActive = 1
    WHERE projects.PublicId = @ProjectPublicId
      AND projects.PublicationStatus = 1
      AND projects.IsActive = 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectMarketplace_Search
    @Query NVARCHAR(300) = NULL,
    @Currency CHAR(3) = NULL,
    @ProjectStatus TINYINT = NULL,
    @Sort NVARCHAR(30) = N'newest',
    @PageNumber INT = 1,
    @PageSize INT = 20,
    @CountryIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @CategoryIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @MatchedCount BIGINT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NormalizedQuery NVARCHAR(300) = NULLIF(LTRIM(RTRIM(@Query)), N'');
    DECLARE @NormalizedCurrency CHAR(3) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Currency)), '') IS NULL THEN NULL
             ELSE UPPER(LTRIM(RTRIM(@Currency))) END;
    DECLARE @NormalizedSort NVARCHAR(30) = LOWER(LTRIM(RTRIM(COALESCE(@Sort, N''))));
    DECLARE @Offset BIGINT;
    IF @PageNumber < 1 OR @PageNumber > 10000 OR @PageSize < 1 OR @PageSize > 50
       OR LEN(COALESCE(@NormalizedQuery, N'')) > 200
       OR (SELECT COUNT_BIG(1) FROM @CountryIds) > 50
       OR (SELECT COUNT_BIG(1) FROM @CategoryIds) > 50
       OR (SELECT COUNT_BIG(1) FROM @ProjectTypeIds) > 50
       OR (@ProjectStatus IS NOT NULL AND @ProjectStatus NOT BETWEEN 0 AND 6)
       OR @NormalizedSort NOT IN (N'newest', N'title', N'funding-gap-desc')
       OR (@NormalizedCurrency IS NOT NULL AND
           (LEN(@NormalizedCurrency) <> 3 OR @NormalizedCurrency LIKE '%[^A-Z]%'))
       OR (@NormalizedSort = N'funding-gap-desc' AND @NormalizedCurrency IS NULL)
        THROW 52102, N'The marketplace filters are invalid.', 1;

    SET @Offset = (CONVERT(BIGINT, @PageNumber) - 1) * CONVERT(BIGINT, @PageSize);
    DECLARE @QueryPattern NVARCHAR(610) = NULL;
    IF @NormalizedQuery IS NOT NULL
        SET @QueryPattern = N'%' +
            REPLACE(REPLACE(REPLACE(REPLACE(@NormalizedQuery,
                N'~', N'~~'), N'%', N'~%'), N'_', N'~_'), N'[', N'~[') + N'%';

    CREATE TABLE #Matches (ProjectId BIGINT NOT NULL PRIMARY KEY);

    INSERT INTO #Matches (ProjectId)
    SELECT projects.Id
    FROM dbo.FundingPlatform_Projects AS projects
    INNER JOIN dbo.FundingPlatform_ifn_ProjectMarketplaceReady() AS ready
        ON ready.ProjectId = projects.Id
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = projects.OrganizationId
    WHERE (@NormalizedQuery IS NULL
           OR projects.Title LIKE @QueryPattern ESCAPE N'~'
           OR projects.Summary LIKE @QueryPattern ESCAPE N'~'
           OR projects.Description LIKE @QueryPattern ESCAPE N'~'
           OR organizations.Name LIKE @QueryPattern ESCAPE N'~')
      AND (@ProjectStatus IS NULL OR projects.ProjectStatus = @ProjectStatus)
      AND (@NormalizedCurrency IS NULL OR projects.Currency = @NormalizedCurrency)
      AND (NOT EXISTS (SELECT 1 FROM @CountryIds) OR EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_ProjectCountries AS links
            INNER JOIN @CountryIds AS ids ON ids.Id = links.CountryId
            WHERE links.ProjectId = projects.Id))
      AND (NOT EXISTS (SELECT 1 FROM @CategoryIds) OR EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_ProjectCategories AS links
            INNER JOIN @CategoryIds AS ids ON ids.Id = links.FundingCategoryId
            WHERE links.ProjectId = projects.Id))
      AND (NOT EXISTS (SELECT 1 FROM @ProjectTypeIds) OR EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_ProjectProjectTypes AS links
            INNER JOIN @ProjectTypeIds AS ids ON ids.Id = links.ProjectTypeId
            WHERE links.ProjectId = projects.Id));

    SELECT @MatchedCount = COUNT_BIG(1) FROM #Matches;
    SELECT @MatchedCount AS TotalCount;

    SELECT projects.PublicId AS ProjectPublicId, projects.Slug, projects.Title,
           projects.Summary, projects.ProjectStatus, projects.ProjectStage,
           projects.StartDate, projects.EndDate,
           projects.BudgetTotal, projects.ConfirmedFunding, projects.Currency,
           projects.FundingGap, projects.PublishedAtUtc, projects.UpdatedAtUtc,
           organizations.PublicId AS OrganizationPublicId,
           organizations.Name AS OrganizationName,
           organizations.WebsiteUrl AS OrganizationWebsiteUrl
    FROM #Matches AS matches
    INNER JOIN dbo.FundingPlatform_Projects AS projects ON projects.Id = matches.ProjectId
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = projects.OrganizationId
    ORDER BY
        CASE WHEN @NormalizedSort = N'newest' THEN projects.PublishedAtUtc END DESC,
        CASE WHEN @NormalizedSort = N'title' THEN projects.Title END,
        CASE WHEN @NormalizedSort = N'funding-gap-desc' AND projects.FundingGap IS NULL
             THEN 1 ELSE 0 END,
        CASE WHEN @NormalizedSort = N'funding-gap-desc' THEN projects.FundingGap END DESC,
        projects.Id DESC
    OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectMarketplace_GetBySlug
    @Slug NVARCHAR(180)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @NormalizedSlug NVARCHAR(180) = NULLIF(LTRIM(RTRIM(@Slug)), N'');

    SELECT projects.PublicId AS ProjectPublicId, projects.Slug, projects.Title,
           projects.Summary, projects.Description, projects.ProjectStatus,
           projects.ProjectStage, projects.StartDate, projects.EndDate,
           projects.BudgetTotal, projects.ConfirmedFunding, projects.Currency,
           projects.FundingGap, projects.ProjectVersion, projects.PublishedAtUtc,
           projects.UpdatedAtUtc,
           organizations.PublicId AS OrganizationPublicId,
           organizations.Name AS OrganizationName,
           organizations.WebsiteUrl AS OrganizationWebsiteUrl,
           JSON_QUERY(COALESCE
           (
               (SELECT countries.Id AS id, RTRIM(countries.Iso2) AS code,
                       countries.Name AS name
                FROM dbo.FundingPlatform_ProjectCountries AS projectCountries
                INNER JOIN dbo.FundingPlatform_Countries AS countries
                    ON countries.Id = projectCountries.CountryId AND countries.IsActive = 1
                WHERE projectCountries.ProjectId = projects.Id
                ORDER BY countries.Name, countries.Id FOR JSON PATH), N'[]'
           )) AS CountriesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT regions.Id AS id, regions.CountryId AS countryId,
                       regions.Code AS code, regions.Name AS name
                FROM dbo.FundingPlatform_ProjectRegions AS projectRegions
                INNER JOIN dbo.FundingPlatform_Regions AS regions
                    ON regions.Id = projectRegions.RegionId AND regions.IsActive = 1
                WHERE projectRegions.ProjectId = projects.Id
                ORDER BY regions.Name, regions.Id FOR JSON PATH), N'[]'
           )) AS RegionsJson,
           JSON_QUERY(COALESCE
           (
               (SELECT categories.Id AS id, categories.Code AS code, categories.Name AS name
                FROM dbo.FundingPlatform_ProjectCategories AS projectCategories
                INNER JOIN dbo.FundingPlatform_FundingCategories AS categories
                    ON categories.Id = projectCategories.FundingCategoryId
                   AND categories.IsActive = 1
                WHERE projectCategories.ProjectId = projects.Id
                ORDER BY categories.Name, categories.Id FOR JSON PATH), N'[]'
           )) AS CategoriesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT beneficiaryTypes.Id AS id, beneficiaryTypes.Code AS code,
                       beneficiaryTypes.Name AS name
                FROM dbo.FundingPlatform_ProjectBeneficiaryTypes AS projectBeneficiaryTypes
                INNER JOIN dbo.FundingPlatform_BeneficiaryTypes AS beneficiaryTypes
                    ON beneficiaryTypes.Id = projectBeneficiaryTypes.BeneficiaryTypeId
                   AND beneficiaryTypes.IsActive = 1
                WHERE projectBeneficiaryTypes.ProjectId = projects.Id
                ORDER BY beneficiaryTypes.Name, beneficiaryTypes.Id FOR JSON PATH), N'[]'
           )) AS BeneficiaryTypesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT projectTypes.Id AS id, projectTypes.Code AS code,
                       projectTypes.Name AS name
                FROM dbo.FundingPlatform_ProjectProjectTypes AS projectProjectTypes
                INNER JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
                    ON projectTypes.Id = projectProjectTypes.ProjectTypeId
                   AND projectTypes.IsActive = 1
                WHERE projectProjectTypes.ProjectId = projects.Id
                ORDER BY projectTypes.Name, projectTypes.Id FOR JSON PATH), N'[]'
           )) AS ProjectTypesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT goals.Id AS id, goals.Code AS code, goals.Name AS name
                FROM dbo.FundingPlatform_ProjectSustainableDevelopmentGoals AS projectGoals
                INNER JOIN dbo.FundingPlatform_SustainableDevelopmentGoals AS goals
                    ON goals.Id = projectGoals.SustainableDevelopmentGoalId AND goals.IsActive = 1
                WHERE projectGoals.ProjectId = projects.Id
                ORDER BY goals.Id FOR JSON PATH), N'[]'
           )) AS SustainableDevelopmentGoalsJson
    FROM dbo.FundingPlatform_Projects AS projects
    INNER JOIN dbo.FundingPlatform_ifn_ProjectMarketplaceReady() AS ready
        ON ready.ProjectId = projects.Id
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = projects.OrganizationId
    WHERE projects.Slug = @NormalizedSlug;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Project_Public_GetBySlug
    @Slug NVARCHAR(180)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.FundingPlatform_usp_ProjectMarketplace_GetBySlug @Slug = @Slug;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_OrganizationMarketplace_Get
    @OrganizationPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @OrganizationId BIGINT;
    SELECT @OrganizationId = organizations.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_ifn_OrganizationMarketplaceReady() AS ready
        ON ready.OrganizationId = organizations.Id
    WHERE organizations.PublicId = @OrganizationPublicId
      AND EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ifn_ProjectMarketplaceReady() AS readyProjects
           WHERE readyProjects.OrganizationId = organizations.Id);

    SELECT organizations.PublicId AS OrganizationPublicId,
           organizations.Name, organizations.Description, organizations.WebsiteUrl,
           organizations.EstablishedYear,
           homeCountries.Id AS HomeCountryId, RTRIM(homeCountries.Iso2) AS HomeCountryCode,
           homeCountries.Name AS HomeCountryName,
           organizationTypes.Id AS OrganizationTypeId,
           organizationTypes.Code AS OrganizationTypeCode,
           organizationTypes.Name AS OrganizationTypeName,
           organizationSizes.Id AS OrganizationSizeId,
           organizationSizes.Code AS OrganizationSizeCode,
           organizationSizes.Name AS OrganizationSizeName
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_Countries AS homeCountries
        ON homeCountries.Id = organizations.HomeCountryId AND homeCountries.IsActive = 1
    INNER JOIN dbo.FundingPlatform_OrganizationTypes AS organizationTypes
        ON organizationTypes.Id = organizations.OrganizationTypeId
       AND organizationTypes.IsActive = 1
    LEFT JOIN dbo.FundingPlatform_OrganizationSizes AS organizationSizes
        ON organizationSizes.Id = organizations.OrganizationSizeId
       AND organizationSizes.IsActive = 1
    WHERE organizations.Id = @OrganizationId;

    SELECT countries.Id, RTRIM(countries.Iso2) AS Code, countries.Name
    FROM dbo.FundingPlatform_OrganizationCountries AS links
    INNER JOIN dbo.FundingPlatform_Countries AS countries
        ON countries.Id = links.CountryId AND countries.IsActive = 1
    WHERE links.OrganizationId = @OrganizationId ORDER BY countries.Name, countries.Id;

    SELECT regions.Id, regions.CountryId, regions.Code, regions.Name
    FROM dbo.FundingPlatform_OrganizationRegions AS links
    INNER JOIN dbo.FundingPlatform_Regions AS regions
        ON regions.Id = links.RegionId AND regions.IsActive = 1
    WHERE links.OrganizationId = @OrganizationId ORDER BY regions.Name, regions.Id;

    SELECT categories.Id, categories.Code, categories.Name
    FROM dbo.FundingPlatform_OrganizationCategories AS links
    INNER JOIN dbo.FundingPlatform_FundingCategories AS categories
        ON categories.Id = links.FundingCategoryId AND categories.IsActive = 1
    WHERE links.OrganizationId = @OrganizationId ORDER BY categories.Name, categories.Id;

    SELECT beneficiaryTypes.Id, beneficiaryTypes.Code, beneficiaryTypes.Name
    FROM dbo.FundingPlatform_OrganizationBeneficiaryTypes AS links
    INNER JOIN dbo.FundingPlatform_BeneficiaryTypes AS beneficiaryTypes
        ON beneficiaryTypes.Id = links.BeneficiaryTypeId AND beneficiaryTypes.IsActive = 1
    WHERE links.OrganizationId = @OrganizationId
    ORDER BY beneficiaryTypes.Name, beneficiaryTypes.Id;

    SELECT projectTypes.Id, projectTypes.Code, projectTypes.Name
    FROM dbo.FundingPlatform_OrganizationProjectTypes AS links
    INNER JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
        ON projectTypes.Id = links.ProjectTypeId AND projectTypes.IsActive = 1
    WHERE links.OrganizationId = @OrganizationId ORDER BY projectTypes.Name, projectTypes.Id;

    SELECT TOP (50) projects.PublicId AS ProjectPublicId, projects.Slug, projects.Title,
           projects.Summary, projects.ProjectStatus, projects.ProjectStage,
           projects.StartDate, projects.EndDate,
           projects.BudgetTotal, projects.ConfirmedFunding, projects.Currency,
           projects.FundingGap, projects.PublishedAtUtc, projects.UpdatedAtUtc
    FROM dbo.FundingPlatform_Projects AS projects
    INNER JOIN dbo.FundingPlatform_ifn_ProjectMarketplaceReady() AS ready
        ON ready.ProjectId = projects.Id
    WHERE projects.OrganizationId = @OrganizationId
    ORDER BY projects.PublishedAtUtc DESC, projects.Id DESC;
END;
GO

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
    FROM dbo.FundingPlatform_FundingTypes
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

    /* Result set 13: official UN Sustainable Development Goals. */
    SELECT Id, Code, Name
    FROM dbo.FundingPlatform_SustainableDevelopmentGoals
    WHERE IsActive = 1 ORDER BY Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Project_List
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @OrganizationId BIGINT;
    SELECT @OrganizationId = organizations.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1
      AND users.PublicId = @UserPublicId;

    IF @OrganizationId IS NULL THROW 51401, N'Organization was not found.', 1;

    SELECT PublicId, Slug, Title, Summary, ProjectStatus, ProjectStage, PublicationStatus,
           StartDate, EndDate, BudgetTotal, ConfirmedFunding, Currency, FundingGap,
           ProjectVersion, UpdatedAtUtc
    FROM dbo.FundingPlatform_Projects
    WHERE OrganizationId = @OrganizationId AND IsActive = 1
    ORDER BY UpdatedAtUtc DESC, Id DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Project_Create
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER,
    @Slug NVARCHAR(180), @Title NVARCHAR(250), @Summary NVARCHAR(1000) = NULL,
    @Description NVARCHAR(MAX) = NULL, @ProjectStatus TINYINT,
    @StartDate DATE = NULL, @EndDate DATE = NULL,
    @BudgetTotal DECIMAL(19,4) = NULL, @ConfirmedFunding DECIMAL(19,4) = NULL,
    @Currency CHAR(3) = NULL, @SnapshotJson NVARCHAR(MAX), @ContentHash BINARY(32),
    @CountryIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @RegionIds dbo.FundingPlatform_IntIdList READONLY,
    @CategoryIds dbo.FundingPlatform_IntIdList READONLY,
    @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectStage TINYINT = NULL,
    @ProjectStageIsSpecified BIT = 0,
    @SustainableDevelopmentGoalIdsJson NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @ProjectId BIGINT;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @SelectedGoals TABLE (Id INT NOT NULL PRIMARY KEY);

    IF @ProjectStageIsSpecified NOT IN (0, 1)
       OR (@ProjectStageIsSpecified = 1 AND @ProjectStage IS NOT NULL
           AND @ProjectStage NOT BETWEEN 0 AND 5)
        THROW 51410, N'Project stage is invalid.', 1;
    IF @SustainableDevelopmentGoalIdsJson IS NOT NULL
       AND ISJSON(@SustainableDevelopmentGoalIdsJson) <> 1
        THROW 51410, N'Project SDG selection must be a JSON array.', 1;
    IF @SustainableDevelopmentGoalIdsJson IS NOT NULL
       AND LEFT(LTRIM(@SustainableDevelopmentGoalIdsJson), 1) <> N'['
        THROW 51410, N'Project SDG selection must be a JSON array.', 1;
    IF EXISTS
    (
        SELECT 1 FROM OPENJSON(COALESCE(@SustainableDevelopmentGoalIdsJson, N'[]'))
        WHERE [type] <> 2 OR TRY_CONVERT(INT, [value]) IS NULL
           OR CONVERT(NVARCHAR(11), TRY_CONVERT(INT, [value])) <> [value]
           OR TRY_CONVERT(INT, [value]) NOT BETWEEN 1 AND 17
    ) OR EXISTS
    (
        SELECT 1 FROM OPENJSON(COALESCE(@SustainableDevelopmentGoalIdsJson, N'[]'))
        GROUP BY TRY_CONVERT(INT, [value]) HAVING COUNT_BIG(1) > 1
    )
        THROW 51410, N'Project SDG selection contains invalid or duplicate identifiers.', 1;

    INSERT INTO @SelectedGoals (Id)
    SELECT TRY_CONVERT(INT, [value])
    FROM OPENJSON(COALESCE(@SustainableDevelopmentGoalIdsJson, N'[]'));

    IF EXISTS
    (
        SELECT 1 FROM @SelectedGoals AS selected
        LEFT JOIN dbo.FundingPlatform_SustainableDevelopmentGoals AS goals
            ON goals.Id = selected.Id AND goals.IsActive = 1
        WHERE goals.Id IS NULL
    )
        THROW 51410, N'One or more project SDGs do not exist or are inactive.', 1;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FundingPlatform_CreateProject;
    BEGIN TRY
        SELECT @OrganizationId = organizations.Id, @UserId = users.Id
        FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id AND memberships.Role = 1 AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
            ON users.Id = memberships.UserId AND users.Status = 2
        WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1
          AND users.PublicId = @UserPublicId;
        IF @OrganizationId IS NULL THROW 51402, N'Active organization administrator membership is required.', 1;
        IF ISJSON(@SnapshotJson) <> 1 THROW 51403, N'Project snapshot must be JSON.', 1;
        IF EXISTS
        (
            SELECT 1 FROM @RegionIds selected
            LEFT JOIN dbo.FundingPlatform_Regions region ON region.Id = selected.Id
            WHERE region.Id IS NULL
        ) THROW 51409, N'One or more project regions do not exist.', 1;
        IF EXISTS
        (
            SELECT 1 FROM @RegionIds selected
            INNER JOIN dbo.FundingPlatform_Regions region ON region.Id = selected.Id
            WHERE NOT EXISTS (SELECT 1 FROM @CountryIds country WHERE country.Id = region.CountryId)
        ) THROW 51404, N'Every project region requires its country.', 1;

        INSERT INTO dbo.FundingPlatform_Projects
            (OrganizationId, CreatedByUserId, Slug, Title, Summary, Description,
             ProjectStatus, ProjectStage, PublicationStatus, StartDate, EndDate, BudgetTotal,
             ConfirmedFunding, Currency, ProjectVersion, CreatedAtUtc, UpdatedAtUtc)
        VALUES
            (@OrganizationId, @UserId, @Slug, @Title, @Summary, @Description,
             @ProjectStatus,
             CASE WHEN @ProjectStageIsSpecified = 1 THEN @ProjectStage ELSE NULL END,
             0, @StartDate, @EndDate, @BudgetTotal,
             @ConfirmedFunding, @Currency, 1, @NowUtc, @NowUtc);
        SET @ProjectId = CONVERT(BIGINT, SCOPE_IDENTITY());
        INSERT INTO dbo.FundingPlatform_ProjectCountries SELECT @ProjectId, Id FROM @CountryIds;
        INSERT INTO dbo.FundingPlatform_ProjectRegions SELECT @ProjectId, Id FROM @RegionIds;
        INSERT INTO dbo.FundingPlatform_ProjectCategories SELECT @ProjectId, Id FROM @CategoryIds;
        INSERT INTO dbo.FundingPlatform_ProjectBeneficiaryTypes SELECT @ProjectId, Id FROM @BeneficiaryTypeIds;
        INSERT INTO dbo.FundingPlatform_ProjectProjectTypes SELECT @ProjectId, Id FROM @ProjectTypeIds;
        INSERT INTO dbo.FundingPlatform_ProjectSustainableDevelopmentGoals
            SELECT @ProjectId, Id FROM @SelectedGoals;
        INSERT INTO dbo.FundingPlatform_ProjectVersions
            (ProjectId, ProjectVersion, SnapshotJson, ContentHash, CreatedByUserId, CreatedAtUtc)
        VALUES (@ProjectId, 1, @SnapshotJson, @ContentHash, @UserId, @NowUtc);
        INSERT INTO dbo.FundingPlatform_OutboxMessages
            (MessageType, AggregateType, AggregateId, PayloadJson, OccurredAtUtc, AvailableAtUtc)
        SELECT N'ProjectCreated', N'Project', CONVERT(NVARCHAR(100), @ProjectId),
               (SELECT @ProjectId AS projectId, 1 AS projectVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
               @NowUtc, @NowUtc;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
        SELECT Id, PublicId, ProjectVersion, RowVersion
        FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FundingPlatform_CreateProject;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Project_Update
    @OrganizationPublicId UNIQUEIDENTIFIER, @ProjectPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER, @ExpectedRowVersion BINARY(8),
    @Title NVARCHAR(250), @Summary NVARCHAR(1000) = NULL,
    @Description NVARCHAR(MAX) = NULL, @ProjectStatus TINYINT,
    @StartDate DATE = NULL, @EndDate DATE = NULL,
    @BudgetTotal DECIMAL(19,4) = NULL, @ConfirmedFunding DECIMAL(19,4) = NULL,
    @Currency CHAR(3) = NULL, @SnapshotJson NVARCHAR(MAX), @ContentHash BINARY(32),
    @CountryIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @RegionIds dbo.FundingPlatform_IntIdList READONLY,
    @CategoryIds dbo.FundingPlatform_IntIdList READONLY,
    @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectStage TINYINT = NULL,
    @ProjectStageIsSpecified BIT = 0,
    @SustainableDevelopmentGoalIdsJson NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @ProjectId BIGINT, @NextVersion INT;
    DECLARE @PublicationStatus TINYINT, @ExistingProjectStage TINYINT;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @SelectedGoals TABLE (Id INT NOT NULL PRIMARY KEY);

    IF @ProjectStageIsSpecified NOT IN (0, 1)
       OR (@ProjectStageIsSpecified = 1 AND @ProjectStage IS NOT NULL
           AND @ProjectStage NOT BETWEEN 0 AND 5)
        THROW 51410, N'Project stage is invalid.', 1;
    IF @SustainableDevelopmentGoalIdsJson IS NOT NULL
       AND (ISJSON(@SustainableDevelopmentGoalIdsJson) <> 1
            OR LEFT(LTRIM(@SustainableDevelopmentGoalIdsJson), 1) <> N'[')
        THROW 51410, N'Project SDG selection must be a JSON array.', 1;
    IF EXISTS
    (
        SELECT 1 FROM OPENJSON(COALESCE(@SustainableDevelopmentGoalIdsJson, N'[]'))
        WHERE [type] <> 2 OR TRY_CONVERT(INT, [value]) IS NULL
           OR CONVERT(NVARCHAR(11), TRY_CONVERT(INT, [value])) <> [value]
           OR TRY_CONVERT(INT, [value]) NOT BETWEEN 1 AND 17
    ) OR EXISTS
    (
        SELECT 1 FROM OPENJSON(COALESCE(@SustainableDevelopmentGoalIdsJson, N'[]'))
        GROUP BY TRY_CONVERT(INT, [value]) HAVING COUNT_BIG(1) > 1
    )
        THROW 51410, N'Project SDG selection contains invalid or duplicate identifiers.', 1;

    INSERT INTO @SelectedGoals (Id)
    SELECT TRY_CONVERT(INT, [value])
    FROM OPENJSON(COALESCE(@SustainableDevelopmentGoalIdsJson, N'[]'));

    IF EXISTS
    (
        SELECT 1 FROM @SelectedGoals AS selected
        LEFT JOIN dbo.FundingPlatform_SustainableDevelopmentGoals AS goals
            ON goals.Id = selected.Id AND goals.IsActive = 1
        WHERE goals.Id IS NULL
    )
        THROW 51410, N'One or more project SDGs do not exist or are inactive.', 1;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_UpdateProject;
    BEGIN TRY
        SELECT @OrganizationId = organizations.Id, @UserId = users.Id
        FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id AND memberships.Role = 1 AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
            ON users.Id = memberships.UserId AND users.Status = 2
        WHERE organizations.PublicId = @OrganizationPublicId AND users.PublicId = @UserPublicId
          AND organizations.IsActive = 1;
        IF @OrganizationId IS NULL THROW 51406, N'Active organization administrator membership is required.', 1;
        SELECT @ProjectId = Id, @NextVersion = ProjectVersion + 1,
               @PublicationStatus = PublicationStatus,
               @ExistingProjectStage = ProjectStage
        FROM dbo.FundingPlatform_Projects WITH (UPDLOCK, HOLDLOCK)
        WHERE OrganizationId = @OrganizationId AND PublicId = @ProjectPublicId AND IsActive = 1;
        IF @ProjectId IS NULL THROW 51405, N'Project was not found.', 1;
        IF @PublicationStatus NOT IN (0, 3)
            THROW 51408, N'Only draft or rejected project content can be edited.', 1;
        /* Never write an incomplete historical snapshot for a legacy caller.
           Legacy updates remain accepted while the aggregate has no new impact
           data. Once impact data exists they fail closed, preserving row, links
           and the last complete project version. */
        IF (@ProjectStageIsSpecified = 0 AND @ExistingProjectStage IS NOT NULL)
           OR (@SustainableDevelopmentGoalIdsJson IS NULL AND EXISTS
               (SELECT 1
                FROM dbo.FundingPlatform_ProjectSustainableDevelopmentGoals
                WHERE ProjectId = @ProjectId))
            THROW 51411, N'Legacy update cannot replace a project with impact data.', 1;
        IF ISJSON(@SnapshotJson) <> 1 THROW 51403, N'Project snapshot must be JSON.', 1;
        IF EXISTS
        (
            SELECT 1 FROM @RegionIds selected
            LEFT JOIN dbo.FundingPlatform_Regions region ON region.Id = selected.Id
            WHERE region.Id IS NULL
        ) THROW 51409, N'One or more project regions do not exist.', 1;
        IF EXISTS
        (
            SELECT 1 FROM @RegionIds selected
            INNER JOIN dbo.FundingPlatform_Regions region ON region.Id = selected.Id
            WHERE NOT EXISTS (SELECT 1 FROM @CountryIds country WHERE country.Id = region.CountryId)
        ) THROW 51404, N'Every project region requires its country.', 1;

        UPDATE dbo.FundingPlatform_Projects
        SET Title = @Title, Summary = @Summary, Description = @Description,
            ProjectStatus = @ProjectStatus,
            ProjectStage = CASE WHEN @ProjectStageIsSpecified = 1
                                THEN @ProjectStage ELSE ProjectStage END,
            StartDate = @StartDate, EndDate = @EndDate,
            BudgetTotal = @BudgetTotal, ConfirmedFunding = @ConfirmedFunding,
            Currency = @Currency, ProjectVersion = @NextVersion, UpdatedAtUtc = @NowUtc
        WHERE Id = @ProjectId AND RowVersion = @ExpectedRowVersion;
        IF @@ROWCOUNT = 0 THROW 51407, N'Project has a concurrency conflict.', 1;

        DELETE FROM dbo.FundingPlatform_ProjectCountries WHERE ProjectId = @ProjectId;
        DELETE FROM dbo.FundingPlatform_ProjectRegions WHERE ProjectId = @ProjectId;
        DELETE FROM dbo.FundingPlatform_ProjectCategories WHERE ProjectId = @ProjectId;
        DELETE FROM dbo.FundingPlatform_ProjectBeneficiaryTypes WHERE ProjectId = @ProjectId;
        DELETE FROM dbo.FundingPlatform_ProjectProjectTypes WHERE ProjectId = @ProjectId;
        INSERT INTO dbo.FundingPlatform_ProjectCountries SELECT @ProjectId, Id FROM @CountryIds;
        INSERT INTO dbo.FundingPlatform_ProjectRegions SELECT @ProjectId, Id FROM @RegionIds;
        INSERT INTO dbo.FundingPlatform_ProjectCategories SELECT @ProjectId, Id FROM @CategoryIds;
        INSERT INTO dbo.FundingPlatform_ProjectBeneficiaryTypes SELECT @ProjectId, Id FROM @BeneficiaryTypeIds;
        INSERT INTO dbo.FundingPlatform_ProjectProjectTypes SELECT @ProjectId, Id FROM @ProjectTypeIds;

        /* NULL means an older caller omitted the new optional parameter. */
        IF @SustainableDevelopmentGoalIdsJson IS NOT NULL
        BEGIN
            DELETE FROM dbo.FundingPlatform_ProjectSustainableDevelopmentGoals
            WHERE ProjectId = @ProjectId;
            INSERT INTO dbo.FundingPlatform_ProjectSustainableDevelopmentGoals
                SELECT @ProjectId, Id FROM @SelectedGoals;
        END;

        INSERT INTO dbo.FundingPlatform_ProjectVersions
            (ProjectId, ProjectVersion, SnapshotJson, ContentHash, CreatedByUserId, CreatedAtUtc)
        VALUES (@ProjectId, @NextVersion, @SnapshotJson, @ContentHash, @UserId, @NowUtc);
        INSERT INTO dbo.FundingPlatform_OutboxMessages
            (MessageType, AggregateType, AggregateId, PayloadJson, OccurredAtUtc, AvailableAtUtc)
        SELECT N'ProjectChanged', N'Project', CONVERT(NVARCHAR(100), @ProjectId),
               (SELECT @ProjectId AS projectId, @NextVersion AS projectVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
               @NowUtc, @NowUtc;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
        SELECT Id, PublicId, ProjectVersion, RowVersion
        FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_UpdateProject;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Project_Get
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ProjectId BIGINT;
    SELECT @ProjectId = projects.Id
    FROM dbo.FundingPlatform_Projects AS projects
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = projects.OrganizationId AND organizations.IsActive = 1
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId AND projects.PublicId = @ProjectPublicId
      AND projects.IsActive = 1 AND users.PublicId = @UserPublicId;
    IF @ProjectId IS NULL THROW 51405, N'Project was not found.', 1;

    SELECT PublicId, Slug, Title, Summary, Description, ProjectStatus, ProjectStage,
           PublicationStatus, StartDate, EndDate, BudgetTotal, ConfirmedFunding,
           Currency, FundingGap, ProjectVersion, UpdatedAtUtc, RowVersion,
           SubmittedAtUtc, ReviewedAtUtc, RejectionReason, PublishedAtUtc
    FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId;
    SELECT CountryId AS Id FROM dbo.FundingPlatform_ProjectCountries
        WHERE ProjectId = @ProjectId ORDER BY CountryId;
    SELECT RegionId AS Id FROM dbo.FundingPlatform_ProjectRegions
        WHERE ProjectId = @ProjectId ORDER BY RegionId;
    SELECT FundingCategoryId AS Id FROM dbo.FundingPlatform_ProjectCategories
        WHERE ProjectId = @ProjectId ORDER BY FundingCategoryId;
    SELECT BeneficiaryTypeId AS Id FROM dbo.FundingPlatform_ProjectBeneficiaryTypes
        WHERE ProjectId = @ProjectId ORDER BY BeneficiaryTypeId;
    SELECT ProjectTypeId AS Id FROM dbo.FundingPlatform_ProjectProjectTypes
        WHERE ProjectId = @ProjectId ORDER BY ProjectTypeId;
    /* Result set 6 after the aggregate row: selected ODS identifiers. */
    SELECT SustainableDevelopmentGoalId AS Id
    FROM dbo.FundingPlatform_ProjectSustainableDevelopmentGoals
    WHERE ProjectId = @ProjectId ORDER BY SustainableDevelopmentGoalId;
END;
GO
