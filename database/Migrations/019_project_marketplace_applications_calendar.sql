/* FundingPlatform FASE 8B - public project marketplace, private applications and derived calendar. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

/* Composite candidate keys let SQL Server enforce tenant alignment even for
   writes that do not pass through the stored procedures. */
CREATE UNIQUE INDEX FundingPlatform_UX_Projects_IdOrganization
    ON dbo.FundingPlatform_Projects (Id, OrganizationId);

CREATE TABLE dbo.FundingPlatform_FundingApplications
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingApplications_PublicId DEFAULT (NEWSEQUENTIALID()),
    OrganizationId BIGINT NOT NULL,
    ProjectId BIGINT NOT NULL,
    FundingOpportunityId BIGINT NOT NULL,
    OwnerUserId BIGINT NOT NULL,
    Status TINYINT NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingApplications_Status DEFAULT (0),
    Notes NVARCHAR(5000) NULL,
    ApplicationDate DATE NULL,
    RequestedAmount DECIMAL(19,4) NULL,
    Currency CHAR(3) NULL,
    ResultDate DATE NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_FundingApplications PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_FundingApplications_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_FundingApplications_IdOrganization
        UNIQUE (Id, OrganizationId),
    CONSTRAINT FundingPlatform_UQ_FundingApplications_OrganizationProjectOpportunity
        UNIQUE (OrganizationId, ProjectId, FundingOpportunityId),
    CONSTRAINT FundingPlatform_FK_FundingApplications_Organization
        FOREIGN KEY (OrganizationId) REFERENCES dbo.FundingPlatform_Organizations (Id),
    CONSTRAINT FundingPlatform_FK_FundingApplications_Project
        FOREIGN KEY (ProjectId) REFERENCES dbo.FundingPlatform_Projects (Id),
    CONSTRAINT FundingPlatform_FK_FundingApplications_ProjectOrganization
        FOREIGN KEY (ProjectId, OrganizationId)
        REFERENCES dbo.FundingPlatform_Projects (Id, OrganizationId),
    CONSTRAINT FundingPlatform_FK_FundingApplications_FundingOpportunity
        FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id),
    CONSTRAINT FundingPlatform_FK_FundingApplications_OwnerUser
        FOREIGN KEY (OwnerUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_FundingApplications_OwnerMembership
        FOREIGN KEY (OrganizationId, OwnerUserId)
        REFERENCES dbo.FundingPlatform_OrganizationUsers (OrganizationId, UserId),
    CONSTRAINT FundingPlatform_FK_FundingApplications_Currency
        FOREIGN KEY (Currency) REFERENCES dbo.FundingPlatform_Currencies (Code),
    /* 0 Interested, 1 Applying, 2 Submitted, 3 Won, 4 Rejected, 5 Discarded. */
    CONSTRAINT FundingPlatform_CK_FundingApplications_Status CHECK (Status BETWEEN 0 AND 5),
    CONSTRAINT FundingPlatform_CK_FundingApplications_RequestedAmount CHECK
        ((RequestedAmount IS NULL AND Currency IS NULL)
         OR (RequestedAmount IS NOT NULL AND RequestedAmount > 0 AND Currency IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_FundingApplications_Dates CHECK
        (ApplicationDate IS NULL OR ResultDate IS NULL OR ResultDate >= ApplicationDate)
);

CREATE INDEX FundingPlatform_IX_FundingApplications_OrganizationUpdated
    ON dbo.FundingPlatform_FundingApplications
       (OrganizationId, UpdatedAtUtc DESC, Id DESC)
    INCLUDE (PublicId, ProjectId, FundingOpportunityId, OwnerUserId, Status,
             ApplicationDate, ResultDate, RequestedAmount, Currency);

CREATE INDEX FundingPlatform_IX_FundingApplications_OrganizationStatusUpdated
    ON dbo.FundingPlatform_FundingApplications
       (OrganizationId, Status, UpdatedAtUtc DESC, Id DESC)
    INCLUDE (PublicId, ProjectId, FundingOpportunityId, OwnerUserId,
             ApplicationDate, ResultDate);

CREATE TABLE dbo.FundingPlatform_FundingApplicationCreateRequests
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    OrganizationId BIGINT NOT NULL,
    OwnerUserId BIGINT NOT NULL,
    FundingApplicationId BIGINT NOT NULL,
    IdempotencyKeyHash BINARY(32) NOT NULL,
    RequestHash BINARY(32) NOT NULL,
    ResultRowVersion BINARY(8) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_FundingApplicationCreateRequests PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_FundingApplicationCreateRequests_OwnerKey
        UNIQUE (OrganizationId, OwnerUserId, IdempotencyKeyHash),
    CONSTRAINT FundingPlatform_FK_FundingApplicationCreateRequests_Organization
        FOREIGN KEY (OrganizationId) REFERENCES dbo.FundingPlatform_Organizations (Id),
    CONSTRAINT FundingPlatform_FK_FundingApplicationCreateRequests_OwnerUser
        FOREIGN KEY (OwnerUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_FundingApplicationCreateRequests_OwnerMembership
        FOREIGN KEY (OrganizationId, OwnerUserId)
        REFERENCES dbo.FundingPlatform_OrganizationUsers (OrganizationId, UserId),
    CONSTRAINT FundingPlatform_FK_FundingApplicationCreateRequests_Application
        FOREIGN KEY (FundingApplicationId)
        REFERENCES dbo.FundingPlatform_FundingApplications (Id),
    CONSTRAINT FundingPlatform_FK_FundingApplicationCreateRequests_ApplicationOrganization
        FOREIGN KEY (FundingApplicationId, OrganizationId)
        REFERENCES dbo.FundingPlatform_FundingApplications (Id, OrganizationId)
);

/* The public feed has an explicit filtered access path. Publication remains
   non-materialized and is re-evaluated through the guards below on every read. */
CREATE INDEX FundingPlatform_IX_Projects_PublicMarketplace
    ON dbo.FundingPlatform_Projects (PublishedAtUtc DESC, Id DESC)
    INCLUDE (PublicId, OrganizationId, Slug, Title, Summary, ProjectStatus,
             StartDate, EndDate, BudgetTotal, ConfirmedFunding, Currency, UpdatedAtUtc)
    WHERE PublicationStatus = 2 AND IsActive = 1;
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_OrganizationMarketplaceReady()
RETURNS TABLE
AS
RETURN
(
    SELECT organizations.Id AS OrganizationId
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_Countries AS homeCountries
        ON homeCountries.Id = organizations.HomeCountryId AND homeCountries.IsActive = 1
    INNER JOIN dbo.FundingPlatform_OrganizationTypes AS organizationTypes
        ON organizationTypes.Id = organizations.OrganizationTypeId
       AND organizationTypes.IsActive = 1
    LEFT JOIN dbo.FundingPlatform_OrganizationSizes AS organizationSizes
        ON organizationSizes.Id = organizations.OrganizationSizeId
       AND organizationSizes.IsActive = 1
    WHERE organizations.IsActive = 1
      AND organizations.ProfileStatus = 2
      AND organizations.ProfileCompleteness >= 80
      AND (organizations.OrganizationSizeId IS NULL OR organizationSizes.Id IS NOT NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_OrganizationCountries AS links
           LEFT JOIN dbo.FundingPlatform_Countries AS countries
               ON countries.Id = links.CountryId AND countries.IsActive = 1
           WHERE links.OrganizationId = organizations.Id AND countries.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_OrganizationRegions AS links
           LEFT JOIN dbo.FundingPlatform_Regions AS regions
               ON regions.Id = links.RegionId AND regions.IsActive = 1
           LEFT JOIN dbo.FundingPlatform_Countries AS countries
               ON countries.Id = regions.CountryId AND countries.IsActive = 1
           WHERE links.OrganizationId = organizations.Id
             AND (regions.Id IS NULL OR countries.Id IS NULL))
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_OrganizationCategories AS links
           LEFT JOIN dbo.FundingPlatform_FundingCategories AS categories
               ON categories.Id = links.FundingCategoryId AND categories.IsActive = 1
           WHERE links.OrganizationId = organizations.Id AND categories.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_OrganizationBeneficiaryTypes AS links
           LEFT JOIN dbo.FundingPlatform_BeneficiaryTypes AS beneficiaryTypes
               ON beneficiaryTypes.Id = links.BeneficiaryTypeId
              AND beneficiaryTypes.IsActive = 1
           WHERE links.OrganizationId = organizations.Id AND beneficiaryTypes.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_OrganizationProjectTypes AS links
           LEFT JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
               ON projectTypes.Id = links.ProjectTypeId AND projectTypes.IsActive = 1
           WHERE links.OrganizationId = organizations.Id AND projectTypes.Id IS NULL)
);
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_ProjectMarketplaceReady()
RETURNS TABLE
AS
RETURN
(
    SELECT projects.Id AS ProjectId, projects.OrganizationId
    FROM dbo.FundingPlatform_Projects AS projects
    INNER JOIN dbo.FundingPlatform_ifn_OrganizationMarketplaceReady() AS readyOrganizations
        ON readyOrganizations.OrganizationId = projects.OrganizationId
    LEFT JOIN dbo.FundingPlatform_Currencies AS currencies
        ON currencies.Code = projects.Currency AND currencies.IsActive = 1
    WHERE projects.IsActive = 1
      AND projects.PublicationStatus = 2
      AND NULLIF(LTRIM(RTRIM(projects.Slug)), N'') IS NOT NULL
      AND NULLIF(LTRIM(RTRIM(projects.Title)), N'') IS NOT NULL
      AND NULLIF(LTRIM(RTRIM(projects.Summary)), N'') IS NOT NULL
      AND NULLIF(LTRIM(RTRIM(projects.Description)), N'') IS NOT NULL
      AND projects.BudgetTotal > 0
      AND currencies.Code IS NOT NULL
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectCountries
           WHERE ProjectId = projects.Id)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectCategories
           WHERE ProjectId = projects.Id)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectBeneficiaryTypes
           WHERE ProjectId = projects.Id)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectProjectTypes
           WHERE ProjectId = projects.Id)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ProjectCountries AS links
           LEFT JOIN dbo.FundingPlatform_Countries AS countries
               ON countries.Id = links.CountryId AND countries.IsActive = 1
           WHERE links.ProjectId = projects.Id AND countries.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ProjectRegions AS links
           LEFT JOIN dbo.FundingPlatform_Regions AS regions
               ON regions.Id = links.RegionId AND regions.IsActive = 1
           LEFT JOIN dbo.FundingPlatform_Countries AS countries
               ON countries.Id = regions.CountryId AND countries.IsActive = 1
           WHERE links.ProjectId = projects.Id
             AND (regions.Id IS NULL OR countries.Id IS NULL
                  OR NOT EXISTS
                     (SELECT 1 FROM dbo.FundingPlatform_ProjectCountries AS projectCountries
                      WHERE projectCountries.ProjectId = projects.Id
                        AND projectCountries.CountryId = regions.CountryId)))
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ProjectCategories AS links
           LEFT JOIN dbo.FundingPlatform_FundingCategories AS categories
               ON categories.Id = links.FundingCategoryId AND categories.IsActive = 1
           WHERE links.ProjectId = projects.Id AND categories.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ProjectBeneficiaryTypes AS links
           LEFT JOIN dbo.FundingPlatform_BeneficiaryTypes AS beneficiaryTypes
               ON beneficiaryTypes.Id = links.BeneficiaryTypeId
              AND beneficiaryTypes.IsActive = 1
           WHERE links.ProjectId = projects.Id AND beneficiaryTypes.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ProjectProjectTypes AS links
           LEFT JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
               ON projectTypes.Id = links.ProjectTypeId AND projectTypes.IsActive = 1
           WHERE links.ProjectId = projects.Id AND projectTypes.Id IS NULL)
);
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

    CREATE TABLE #Matches
    (
        ProjectId BIGINT NOT NULL PRIMARY KEY
    );

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
           projects.Summary, projects.ProjectStatus, projects.StartDate, projects.EndDate,
           projects.BudgetTotal, projects.ConfirmedFunding, projects.Currency,
           projects.FundingGap, projects.PublishedAtUtc, projects.UpdatedAtUtc,
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
               (SELECT projectTypes.Id AS id, projectTypes.Code AS code, projectTypes.Name AS name
                FROM dbo.FundingPlatform_ProjectProjectTypes AS projectProjectTypes
                INNER JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
                    ON projectTypes.Id = projectProjectTypes.ProjectTypeId
                   AND projectTypes.IsActive = 1
                WHERE projectProjectTypes.ProjectId = projects.Id
                ORDER BY projectTypes.Name, projectTypes.Id FOR JSON PATH), N'[]'
           )) AS ProjectTypesJson
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

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingApplication_List
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @Status TINYINT = NULL,
    @ProjectPublicId UNIQUEIDENTIFIER = NULL,
    @FundingOpportunityPublicId UNIQUEIDENTIFIER = NULL,
    @PageNumber INT = 1,
    @PageSize INT = 20,
    @MatchedCount BIGINT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @MembershipRole TINYINT;
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id,
           @MembershipRole = memberships.Role
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id
       AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId
      AND organizations.IsActive = 1 AND users.PublicId = @UserPublicId;

    IF @OrganizationId IS NULL OR @UserId IS NULL
        THROW 52101, N'The workspace resource was not found.', 1;
    IF (@Status IS NOT NULL AND @Status NOT BETWEEN 0 AND 5)
       OR @PageNumber < 1 OR @PageNumber > 10000 OR @PageSize < 1 OR @PageSize > 50
        THROW 52102, N'The application filters are invalid.', 1;

    DECLARE @Offset BIGINT =
        (CONVERT(BIGINT, @PageNumber) - 1) * CONVERT(BIGINT, @PageSize);
    CREATE TABLE #Matches (FundingApplicationId BIGINT NOT NULL PRIMARY KEY);
    INSERT INTO #Matches (FundingApplicationId)
    SELECT applications.Id
    FROM dbo.FundingPlatform_FundingApplications AS applications
    INNER JOIN dbo.FundingPlatform_Projects AS projects ON projects.Id = applications.ProjectId
    INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
        ON opportunities.Id = applications.FundingOpportunityId
    WHERE applications.OrganizationId = @OrganizationId
      AND (@Status IS NULL OR applications.Status = @Status)
      AND (@ProjectPublicId IS NULL OR projects.PublicId = @ProjectPublicId)
      AND (@FundingOpportunityPublicId IS NULL
           OR opportunities.PublicId = @FundingOpportunityPublicId);

    SELECT @MatchedCount = COUNT_BIG(1) FROM #Matches;
    SELECT @MatchedCount AS TotalCount;

    SELECT applications.PublicId AS FundingApplicationPublicId,
           applications.Status, applications.Notes, applications.ApplicationDate,
           applications.RequestedAmount, applications.Currency, applications.ResultDate,
           owners.PublicId AS OwnerUserPublicId,
           CONVERT(BIT, CASE WHEN applications.OwnerUserId = @UserId OR @MembershipRole = 1
                             THEN 1 ELSE 0 END) AS CanEdit,
           projects.PublicId AS ProjectPublicId, projects.Slug AS ProjectSlug,
           projects.Title AS ProjectTitle,
           opportunities.PublicId AS FundingOpportunityPublicId,
           opportunities.Slug AS FundingOpportunitySlug,
           opportunities.Title AS FundingOpportunityTitle,
           opportunities.SponsorName, opportunities.CloseDate, opportunities.CloseAtUtc,
           opportunities.DeadlinePrecision,
           applications.CreatedAtUtc, applications.UpdatedAtUtc, applications.RowVersion
    FROM #Matches AS matches
    INNER JOIN dbo.FundingPlatform_FundingApplications AS applications
        ON applications.Id = matches.FundingApplicationId
    INNER JOIN dbo.FundingPlatform_Users AS owners ON owners.Id = applications.OwnerUserId
    INNER JOIN dbo.FundingPlatform_Projects AS projects ON projects.Id = applications.ProjectId
    INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
        ON opportunities.Id = applications.FundingOpportunityId
    ORDER BY applications.UpdatedAtUtc DESC, applications.Id DESC
    OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingApplication_Get
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @FundingApplicationPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @MembershipRole TINYINT;
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id,
           @MembershipRole = memberships.Role
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id
       AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId
      AND organizations.IsActive = 1 AND users.PublicId = @UserPublicId;

    IF @OrganizationId IS NULL OR @UserId IS NULL
        THROW 52101, N'The workspace resource was not found.', 1;

    SELECT applications.PublicId AS FundingApplicationPublicId,
           applications.Status, applications.Notes, applications.ApplicationDate,
           applications.RequestedAmount, applications.Currency, applications.ResultDate,
           owners.PublicId AS OwnerUserPublicId,
           CONVERT(BIT, CASE WHEN applications.OwnerUserId = @UserId OR @MembershipRole = 1
                             THEN 1 ELSE 0 END) AS CanEdit,
           projects.PublicId AS ProjectPublicId, projects.Slug AS ProjectSlug,
           projects.Title AS ProjectTitle,
           opportunities.PublicId AS FundingOpportunityPublicId,
           opportunities.Slug AS FundingOpportunitySlug,
           opportunities.Title AS FundingOpportunityTitle,
           opportunities.SponsorName, opportunities.CloseDate, opportunities.CloseAtUtc,
           opportunities.DeadlinePrecision,
           applications.CreatedAtUtc, applications.UpdatedAtUtc, applications.RowVersion
    FROM dbo.FundingPlatform_FundingApplications AS applications
    INNER JOIN dbo.FundingPlatform_Users AS owners ON owners.Id = applications.OwnerUserId
    INNER JOIN dbo.FundingPlatform_Projects AS projects ON projects.Id = applications.ProjectId
    INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
        ON opportunities.Id = applications.FundingOpportunityId
    WHERE applications.OrganizationId = @OrganizationId
      AND applications.PublicId = @FundingApplicationPublicId;
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
           projects.StartDate, projects.EndDate, projects.BudgetTotal,
           projects.ConfirmedFunding, projects.Currency, projects.FundingGap,
           projects.ProjectVersion, projects.PublishedAtUtc, projects.UpdatedAtUtc,
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
           )) AS ProjectTypesJson
    FROM dbo.FundingPlatform_Projects AS projects
    INNER JOIN dbo.FundingPlatform_ifn_ProjectMarketplaceReady() AS ready
        ON ready.ProjectId = projects.Id
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = projects.OrganizationId
    WHERE projects.Slug = @NormalizedSlug;
END;
GO

/* Keep the FASE 5 public route source-compatible while closing the old inline
   guard gap. Both detail entry points now execute the exact same predicate. */
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

    /* Result set 1: explicitly allowlisted public fields; no legal name,
       tax identifier, users, membership, budgets or other private profile data. */
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

    /* Result sets 2-6: safe active catalog facets. */
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

    /* Result set 7: this organization can expose only projects admitted by the
       same shared guard as marketplace search and detail. */
    SELECT TOP (50) projects.PublicId AS ProjectPublicId, projects.Slug, projects.Title,
           projects.Summary, projects.ProjectStatus, projects.StartDate, projects.EndDate,
           projects.BudgetTotal, projects.ConfirmedFunding, projects.Currency,
           projects.FundingGap, projects.PublishedAtUtc, projects.UpdatedAtUtc
    FROM dbo.FundingPlatform_Projects AS projects
    INNER JOIN dbo.FundingPlatform_ifn_ProjectMarketplaceReady() AS ready
        ON ready.ProjectId = projects.Id
    WHERE projects.OrganizationId = @OrganizationId
    ORDER BY projects.PublishedAtUtc DESC, projects.Id DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingApplication_Create
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @FundingOpportunityPublicId UNIQUEIDENTIFIER,
    @Notes NVARCHAR(5000) = NULL,
    @ApplicationDate DATE = NULL,
    @RequestedAmount DECIMAL(19,4) = NULL,
    @Currency CHAR(3) = NULL,
    @ResultDate DATE = NULL,
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @ProjectId BIGINT;
    DECLARE @OpportunityId BIGINT, @ApplicationId BIGINT;
    DECLARE @ApplicationPublicId UNIQUEIDENTIFIER, @OwnerUserPublicId UNIQUEIDENTIFIER;
    DECLARE @ResultRowVersion BINARY(8), @StoredRequestHash BINARY(32);
    DECLARE @CreatedAtUtc DATETIME2(3), @UpdatedAtUtc DATETIME2(3);
    DECLARE @NormalizedNotes NVARCHAR(5000) = NULLIF(LTRIM(RTRIM(@Notes)), N'');
    DECLARE @NormalizedCurrency CHAR(3) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Currency)), '') IS NULL THEN NULL
             ELSE UPPER(LTRIM(RTRIM(@Currency))) END;
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Status TINYINT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_CreateFundingApplication;

    BEGIN TRY
        SELECT @OrganizationId = organizations.Id, @UserId = users.Id,
               @OwnerUserPublicId = users.PublicId
        FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id
           AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
            ON users.Id = memberships.UserId AND users.Status = 2
        WHERE organizations.PublicId = @OrganizationPublicId
          AND organizations.IsActive = 1 AND users.PublicId = @UserPublicId;

        IF @OrganizationId IS NULL OR @UserId IS NULL
            THROW 52101, N'The workspace resource was not found.', 1;

        IF @IdempotencyKeyHash IS NULL OR @RequestHash IS NULL
            SET @Code = N'invalid-input';
        ELSE
        BEGIN
            SELECT @ApplicationId = requests.FundingApplicationId,
                   @StoredRequestHash = requests.RequestHash,
                   @ResultRowVersion = requests.ResultRowVersion,
                   @CreatedAtUtc = requests.CreatedAtUtc
            FROM dbo.FundingPlatform_FundingApplicationCreateRequests AS requests
                WITH (UPDLOCK, HOLDLOCK)
            WHERE requests.OrganizationId = @OrganizationId
              AND requests.OwnerUserId = @UserId
              AND requests.IdempotencyKeyHash = @IdempotencyKeyHash;

            IF @ApplicationId IS NOT NULL
            BEGIN
                IF @StoredRequestHash = @RequestHash
                BEGIN
                    SELECT @ApplicationPublicId = applications.PublicId,
                           @Status = applications.Status,
                           @UpdatedAtUtc = applications.UpdatedAtUtc
                    FROM dbo.FundingPlatform_FundingApplications AS applications
                    WHERE applications.Id = @ApplicationId
                      AND applications.OrganizationId = @OrganizationId;
                    SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'replayed';
                END
                ELSE
                BEGIN
                    SET @ApplicationId = NULL;
                    SET @Code = N'idempotency-conflict';
                END
            END
            ELSE IF (@NormalizedCurrency IS NOT NULL AND
                     (LEN(@NormalizedCurrency) <> 3
                      OR @NormalizedCurrency LIKE '%[^A-Z]%'))
                 OR (@RequestedAmount IS NULL AND @NormalizedCurrency IS NOT NULL)
                 OR (@RequestedAmount IS NOT NULL AND
                     (@RequestedAmount <= 0 OR @NormalizedCurrency IS NULL))
                 OR (@ApplicationDate IS NOT NULL AND @ResultDate IS NOT NULL
                     AND @ResultDate < @ApplicationDate)
                 OR (@NormalizedCurrency IS NOT NULL AND NOT EXISTS
                     (SELECT 1 FROM dbo.FundingPlatform_Currencies
                      WHERE Code = @NormalizedCurrency AND IsActive = 1))
                SET @Code = N'invalid-input';
            ELSE
            BEGIN
                SELECT @ProjectId = projects.Id
                FROM dbo.FundingPlatform_Projects AS projects WITH (UPDLOCK, HOLDLOCK)
                WHERE projects.PublicId = @ProjectPublicId
                  AND projects.OrganizationId = @OrganizationId
                  AND projects.IsActive = 1 AND projects.PublicationStatus <> 4;

                SELECT @OpportunityId = opportunities.Id
                FROM dbo.FundingPlatform_FundingOpportunities AS opportunities WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
                    ON ready.FundingOpportunityId = opportunities.Id
                WHERE opportunities.PublicId = @FundingOpportunityPublicId;

                IF @ProjectId IS NOT NULL AND @OpportunityId IS NOT NULL
                BEGIN
                    SELECT @ApplicationId = applications.Id,
                           @ApplicationPublicId = applications.PublicId,
                           @Status = applications.Status,
                           @ResultRowVersion = applications.RowVersion,
                           @CreatedAtUtc = applications.CreatedAtUtc,
                           @UpdatedAtUtc = applications.UpdatedAtUtc
                    FROM dbo.FundingPlatform_FundingApplications AS applications
                        WITH (UPDLOCK, HOLDLOCK)
                    WHERE applications.OrganizationId = @OrganizationId
                      AND applications.ProjectId = @ProjectId
                      AND applications.FundingOpportunityId = @OpportunityId;

                    IF @ApplicationId IS NOT NULL
                        SET @Code = N'already-exists';
                    ELSE
                    BEGIN
                        DECLARE @Created TABLE
                        (
                            Id BIGINT NOT NULL, PublicId UNIQUEIDENTIFIER NOT NULL,
                            RowVersion BINARY(8) NOT NULL
                        );
                        INSERT INTO dbo.FundingPlatform_FundingApplications
                            (OrganizationId, ProjectId, FundingOpportunityId, OwnerUserId,
                             Status, Notes, ApplicationDate, RequestedAmount, Currency,
                             ResultDate, CreatedAtUtc, UpdatedAtUtc)
                        OUTPUT inserted.Id, inserted.PublicId, inserted.RowVersion
                            INTO @Created (Id, PublicId, RowVersion)
                        VALUES
                            (@OrganizationId, @ProjectId, @OpportunityId, @UserId, 0,
                             @NormalizedNotes, @ApplicationDate, @RequestedAmount,
                             @NormalizedCurrency, @ResultDate, @NowUtc, @NowUtc);
                        SELECT @ApplicationId = Id, @ApplicationPublicId = PublicId,
                               @ResultRowVersion = RowVersion FROM @Created;
                        SET @CreatedAtUtc = @NowUtc; SET @UpdatedAtUtc = @NowUtc;

                        INSERT INTO dbo.FundingPlatform_FundingApplicationCreateRequests
                            (OrganizationId, OwnerUserId, FundingApplicationId,
                             IdempotencyKeyHash, RequestHash, ResultRowVersion, CreatedAtUtc)
                        VALUES
                            (@OrganizationId, @UserId, @ApplicationId,
                             @IdempotencyKeyHash, @RequestHash, @ResultRowVersion, @NowUtc);

                        INSERT INTO dbo.FundingPlatform_OutboxMessages
                            (MessageType, AggregateType, AggregateId, PayloadJson,
                             OccurredAtUtc, AvailableAtUtc)
                        SELECT N'FundingApplicationCreated', N'FundingApplication',
                               CONVERT(NVARCHAR(100), @ApplicationId),
                               (SELECT @ApplicationPublicId AS fundingApplicationPublicId,
                                       @ProjectPublicId AS projectPublicId,
                                       @FundingOpportunityPublicId AS fundingOpportunityPublicId,
                                       0 AS status FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                               @NowUtc, @NowUtc;
                        SET @Succeeded = 1; SET @Code = N'created';
                    END
                END
            END
        END

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_CreateFundingApplication;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @ApplicationPublicId AS FundingApplicationPublicId, @Status AS Status,
           @OwnerUserPublicId AS OwnerUserPublicId, @ResultRowVersion AS RowVersion,
           @CreatedAtUtc AS CreatedAtUtc, @UpdatedAtUtc AS UpdatedAtUtc,
           @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingApplication_Update
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @FundingApplicationPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @Status TINYINT,
    @Notes NVARCHAR(5000) = NULL,
    @ApplicationDate DATE = NULL,
    @RequestedAmount DECIMAL(19,4) = NULL,
    @Currency CHAR(3) = NULL,
    @ResultDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @MembershipRole TINYINT;
    DECLARE @ApplicationId BIGINT, @OwnerUserId BIGINT;
    DECLARE @OwnerUserPublicId UNIQUEIDENTIFIER, @CurrentStatus TINYINT;
    DECLARE @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @CreatedAtUtc DATETIME2(3), @UpdatedAtUtc DATETIME2(3);
    DECLARE @NormalizedNotes NVARCHAR(5000) = NULLIF(LTRIM(RTRIM(@Notes)), N'');
    DECLARE @NormalizedCurrency CHAR(3) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Currency)), '') IS NULL THEN NULL
             ELSE UPPER(LTRIM(RTRIM(@Currency))) END;
    DECLARE @Succeeded BIT = 0, @Code NVARCHAR(50) = N'not-found';
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_UpdateFundingApplication;

    BEGIN TRY
        SELECT @OrganizationId = organizations.Id, @UserId = users.Id,
               @MembershipRole = memberships.Role
        FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id
           AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
            ON users.Id = memberships.UserId AND users.Status = 2
        WHERE organizations.PublicId = @OrganizationPublicId
          AND organizations.IsActive = 1 AND users.PublicId = @UserPublicId;

        IF @OrganizationId IS NULL OR @UserId IS NULL
            THROW 52101, N'The workspace resource was not found.', 1;

        SELECT @ApplicationId = applications.Id,
               @OwnerUserId = applications.OwnerUserId,
               @OwnerUserPublicId = owners.PublicId,
               @CurrentStatus = applications.Status,
               @CurrentRowVersion = applications.RowVersion,
               @CreatedAtUtc = applications.CreatedAtUtc,
               @UpdatedAtUtc = applications.UpdatedAtUtc
        FROM dbo.FundingPlatform_FundingApplications AS applications WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_Users AS owners ON owners.Id = applications.OwnerUserId
        WHERE applications.OrganizationId = @OrganizationId
          AND applications.PublicId = @FundingApplicationPublicId;

        IF @ApplicationId IS NULL OR (@OwnerUserId <> @UserId AND @MembershipRole <> 1)
            SET @Code = N'not-found';
        ELSE IF @ExpectedRowVersion IS NULL OR @Status IS NULL OR @Status NOT BETWEEN 0 AND 5
             OR (@NormalizedCurrency IS NOT NULL AND
                 (LEN(@NormalizedCurrency) <> 3 OR @NormalizedCurrency LIKE '%[^A-Z]%'))
             OR (@RequestedAmount IS NULL AND @NormalizedCurrency IS NOT NULL)
             OR (@RequestedAmount IS NOT NULL AND
                 (@RequestedAmount <= 0 OR @NormalizedCurrency IS NULL))
             OR (@ApplicationDate IS NOT NULL AND @ResultDate IS NOT NULL
                 AND @ResultDate < @ApplicationDate)
             OR (@NormalizedCurrency IS NOT NULL AND NOT EXISTS
                 (SELECT 1 FROM dbo.FundingPlatform_Currencies
                  WHERE Code = @NormalizedCurrency AND IsActive = 1))
            SET @Code = N'invalid-input';
        ELSE IF @CurrentRowVersion <> @ExpectedRowVersion
            SET @Code = N'etag-conflict';
        ELSE
        BEGIN
            DECLARE @Updated TABLE (RowVersion BINARY(8) NOT NULL);
            UPDATE dbo.FundingPlatform_FundingApplications
            SET Status = @Status, Notes = @NormalizedNotes,
                ApplicationDate = @ApplicationDate, RequestedAmount = @RequestedAmount,
                Currency = @NormalizedCurrency, ResultDate = @ResultDate,
                UpdatedAtUtc = @NowUtc
            OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
            WHERE Id = @ApplicationId AND OrganizationId = @OrganizationId
              AND RowVersion = @ExpectedRowVersion;
            SELECT @ResultRowVersion = RowVersion FROM @Updated;
            IF @ResultRowVersion IS NULL SET @Code = N'etag-conflict';
            ELSE
            BEGIN
                INSERT INTO dbo.FundingPlatform_OutboxMessages
                    (MessageType, AggregateType, AggregateId, PayloadJson,
                     OccurredAtUtc, AvailableAtUtc)
                SELECT N'FundingApplicationUpdated', N'FundingApplication',
                       CONVERT(NVARCHAR(100), @ApplicationId),
                       (SELECT @FundingApplicationPublicId AS fundingApplicationPublicId,
                               @CurrentStatus AS fromStatus, @Status AS toStatus
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                       @NowUtc, @NowUtc;
                SET @Succeeded = 1; SET @Code = N'updated';
                SET @CurrentStatus = @Status; SET @UpdatedAtUtc = @NowUtc;
            END
        END

        IF @ResultRowVersion IS NULL SET @ResultRowVersion = @CurrentRowVersion;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_UpdateFundingApplication;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           CASE WHEN @ApplicationId IS NULL THEN NULL ELSE @FundingApplicationPublicId END
               AS FundingApplicationPublicId,
           @CurrentStatus AS Status, @OwnerUserPublicId AS OwnerUserPublicId,
           @ResultRowVersion AS RowVersion, @CreatedAtUtc AS CreatedAtUtc,
           @UpdatedAtUtc AS UpdatedAtUtc, CONVERT(BIT, 0) AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_OrganizationCalendar_List
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @FromDate DATE,
    @ToDate DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT;
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id
       AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId
      AND organizations.IsActive = 1 AND users.PublicId = @UserPublicId;

    IF @OrganizationId IS NULL OR @UserId IS NULL
        THROW 52101, N'The workspace resource was not found.', 1;
    IF @FromDate IS NULL OR @ToDate IS NULL OR @FromDate > @ToDate
       OR DATEDIFF(DAY, @FromDate, @ToDate) > 365
        THROW 52102, N'The calendar range is invalid.', 1;

    ;WITH ApplicationBase AS
    (
        SELECT applications.Id AS FundingApplicationId,
               applications.PublicId AS FundingApplicationPublicId,
               applications.Status, applications.ApplicationDate,
               applications.ResultDate, projects.Id AS ProjectId,
               projects.PublicId AS ProjectPublicId, projects.Title AS ProjectTitle,
               opportunities.Id AS FundingOpportunityId,
               opportunities.PublicId AS FundingOpportunityPublicId,
               opportunities.Title AS FundingOpportunityTitle,
               opportunities.CloseDate, opportunities.CloseAtUtc,
               opportunities.DeadlineType, opportunities.DeadlinePrecision
        FROM dbo.FundingPlatform_FundingApplications AS applications
        INNER JOIN dbo.FundingPlatform_Projects AS projects
            ON projects.Id = applications.ProjectId
        INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
            ON opportunities.Id = applications.FundingOpportunityId
        WHERE applications.OrganizationId = @OrganizationId
          AND applications.Status <> 5
    ),
    CalendarProjects AS
    (
        SELECT projects.Id AS ProjectId
        FROM dbo.FundingPlatform_Projects AS projects
        WHERE projects.OrganizationId = @OrganizationId
          AND projects.IsActive = 1 AND projects.PublicationStatus <> 4
        UNION
        SELECT ProjectId FROM ApplicationBase
    ),
    CalendarEvents AS
    (
        SELECT CONVERT(NVARCHAR(100), N'application-deadline:' +
                   CONVERT(NVARCHAR(36), applications.FundingApplicationPublicId)) AS EventKey,
               CONVERT(NVARCHAR(30), N'application-deadline') AS EventType,
               applications.CloseDate AS EventDate,
               applications.CloseAtUtc AS EventAtUtc,
               applications.DeadlinePrecision AS DatePrecision,
               applications.FundingOpportunityTitle AS Title,
               applications.Status,
               applications.FundingApplicationPublicId,
               applications.ProjectPublicId,
               applications.FundingOpportunityPublicId
        FROM ApplicationBase AS applications
        WHERE applications.DeadlineType = 1 AND applications.CloseDate IS NOT NULL

        UNION ALL

        SELECT CONVERT(NVARCHAR(100), N'planned-submission:' +
                   CONVERT(NVARCHAR(36), applications.FundingApplicationPublicId)),
               CONVERT(NVARCHAR(30), N'planned-submission'),
               applications.ApplicationDate, CAST(NULL AS DATETIME2(3)),
               CONVERT(TINYINT, 1), applications.FundingOpportunityTitle,
               applications.Status, applications.FundingApplicationPublicId,
               applications.ProjectPublicId, applications.FundingOpportunityPublicId
        FROM ApplicationBase AS applications
        WHERE applications.ApplicationDate IS NOT NULL

        UNION ALL

        SELECT CONVERT(NVARCHAR(100), N'application-result:' +
                   CONVERT(NVARCHAR(36), applications.FundingApplicationPublicId)),
               CONVERT(NVARCHAR(30), N'application-result'),
               applications.ResultDate, CAST(NULL AS DATETIME2(3)),
               CONVERT(TINYINT, 1), applications.FundingOpportunityTitle,
               applications.Status, applications.FundingApplicationPublicId,
               applications.ProjectPublicId, applications.FundingOpportunityPublicId
        FROM ApplicationBase AS applications
        WHERE applications.ResultDate IS NOT NULL

        UNION ALL

        SELECT CONVERT(NVARCHAR(100), N'project-start:' +
                   CONVERT(NVARCHAR(36), projects.PublicId)),
               CONVERT(NVARCHAR(30), N'project-start'), projects.StartDate,
               CAST(NULL AS DATETIME2(3)), CONVERT(TINYINT, 1), projects.Title,
               CAST(NULL AS TINYINT), CAST(NULL AS UNIQUEIDENTIFIER), projects.PublicId,
               CAST(NULL AS UNIQUEIDENTIFIER)
        FROM CalendarProjects AS linked
        INNER JOIN dbo.FundingPlatform_Projects AS projects ON projects.Id = linked.ProjectId
        WHERE projects.StartDate IS NOT NULL

        UNION ALL

        SELECT CONVERT(NVARCHAR(100), N'project-end:' +
                   CONVERT(NVARCHAR(36), projects.PublicId)),
               CONVERT(NVARCHAR(30), N'project-end'), projects.EndDate,
               CAST(NULL AS DATETIME2(3)), CONVERT(TINYINT, 1), projects.Title,
               CAST(NULL AS TINYINT), CAST(NULL AS UNIQUEIDENTIFIER), projects.PublicId,
               CAST(NULL AS UNIQUEIDENTIFIER)
        FROM CalendarProjects AS linked
        INNER JOIN dbo.FundingPlatform_Projects AS projects ON projects.Id = linked.ProjectId
        WHERE projects.EndDate IS NOT NULL

        UNION ALL

        SELECT CONVERT(NVARCHAR(100), N'favorite-deadline:' +
                   CONVERT(NVARCHAR(36), opportunities.PublicId)),
               CONVERT(NVARCHAR(30), N'favorite-deadline'), opportunities.CloseDate,
               opportunities.CloseAtUtc, opportunities.DeadlinePrecision,
               opportunities.Title, CAST(NULL AS TINYINT),
               CAST(NULL AS UNIQUEIDENTIFIER), CAST(NULL AS UNIQUEIDENTIFIER),
               opportunities.PublicId
        FROM dbo.FundingPlatform_UserFundingFavorites AS favorites
        INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
            ON ready.FundingOpportunityId = favorites.FundingOpportunityId
        INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
            ON opportunities.Id = favorites.FundingOpportunityId
        WHERE favorites.OrganizationId = @OrganizationId
          AND favorites.UserId = @UserId
          AND opportunities.DeadlineType = 1 AND opportunities.CloseDate IS NOT NULL
          AND NOT EXISTS
              (SELECT 1
               FROM dbo.FundingPlatform_FundingApplications AS applications
               WHERE applications.OrganizationId = @OrganizationId
                 AND applications.FundingOpportunityId = opportunities.Id
                 AND applications.Status <> 5)
    )
    SELECT EventKey, EventType, EventDate, EventAtUtc, DatePrecision, Title, Status,
           FundingApplicationPublicId, ProjectPublicId, FundingOpportunityPublicId
    FROM CalendarEvents
    WHERE EventDate BETWEEN @FromDate AND @ToDate
    ORDER BY EventDate, EventAtUtc, EventType, EventKey;
END;
GO

/* FundingApplication outbox rows are event-ledger records, not commands. Extend
   the closed audit allowlist without widening any worker claim procedure. */
EXEC sys.sp_rename
    @objname = N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge',
    @newname = N'FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre019',
    @objtype = N'OBJECT';
GO

CREATE PROCEDURE dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge
    @BatchSize INT,
    @NowUtc DATETIME2(3),
    @AcknowledgedCount INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @BatchSize NOT BETWEEN 1 AND 500
        THROW 52103, N'BatchSize must be between 1 and 500.', 1;
    IF @NowUtc IS NULL THROW 52104, N'NowUtc is required.', 1;

    DECLARE @PreviousCount INT = 0;
    EXEC dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre019
        @BatchSize = @BatchSize, @NowUtc = @NowUtc,
        @AcknowledgedCount = @PreviousCount OUTPUT;

    DECLARE @Remaining INT = @BatchSize - @PreviousCount, @CurrentCount INT = 0;
    IF @Remaining > 0
    BEGIN
        ;WITH FundingApplicationEvents AS
        (
            SELECT TOP (@Remaining) *
            FROM dbo.FundingPlatform_OutboxMessages
                 WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
            WHERE MessageType IN (N'FundingApplicationCreated', N'FundingApplicationUpdated')
              AND AggregateType = N'FundingApplication'
              AND TRY_CONVERT(BIGINT, AggregateId) IS NOT NULL
              AND TRY_CONVERT(UNIQUEIDENTIFIER,
                    JSON_VALUE(PayloadJson, N'$.fundingApplicationPublicId')) IS NOT NULL
              AND
              (
                  (MessageType = N'FundingApplicationCreated'
                   AND TRY_CONVERT(UNIQUEIDENTIFIER,
                         JSON_VALUE(PayloadJson, N'$.projectPublicId')) IS NOT NULL
                   AND TRY_CONVERT(UNIQUEIDENTIFIER,
                         JSON_VALUE(PayloadJson, N'$.fundingOpportunityPublicId')) IS NOT NULL
                   AND TRY_CONVERT(TINYINT, JSON_VALUE(PayloadJson, N'$.status')) = 0
                   AND NOT EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] NOT IN
                            (N'fundingApplicationPublicId', N'projectPublicId',
                             N'fundingOpportunityPublicId', N'status')))
                  OR
                  (MessageType = N'FundingApplicationUpdated'
                   AND TRY_CONVERT(TINYINT,
                         JSON_VALUE(PayloadJson, N'$.fromStatus')) BETWEEN 0 AND 5
                   AND TRY_CONVERT(TINYINT,
                         JSON_VALUE(PayloadJson, N'$.toStatus')) BETWEEN 0 AND 5
                   AND NOT EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] NOT IN
                            (N'fundingApplicationPublicId', N'fromStatus', N'toStatus')))
              )
              AND DispatchedAtUtc IS NULL AND AvailableAtUtc <= @NowUtc
              AND (LeaseUntilUtc IS NULL OR LeaseUntilUtc <= @NowUtc)
            ORDER BY AvailableAtUtc, Id
        )
        UPDATE FundingApplicationEvents
        SET DispatchedAtUtc = @NowUtc, LeaseOwner = NULL, LeaseUntilUtc = NULL,
            LastError = N'event-ledger-acknowledged';
        SET @CurrentCount = @@ROWCOUNT;
    END;
    SET @AcknowledgedCount = @PreviousCount + @CurrentCount;
END;
GO
