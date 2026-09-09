/* Public map: explicit location consent, rounded coordinates, bounded pages. Requires 040. */
SET XACT_ABORT ON;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectMap_Search
    @Query NVARCHAR(300) = NULL, @CountryId SMALLINT = NULL, @CategoryId INT = NULL,
    @ProjectStage TINYINT = NULL, @SustainableDevelopmentGoalId INT = NULL,
    @ProjectStatus TINYINT = NULL, @Page INT = 1, @PageSize INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    IF LEN(LTRIM(RTRIM(COALESCE(@Query, N'')))) > 200 OR @CountryId <= 0 OR @CategoryId <= 0
       OR @ProjectStage > 5 OR @ProjectStatus > 6 OR @SustainableDevelopmentGoalId NOT BETWEEN 1 AND 17
       OR @Page NOT BETWEEN 1 AND 10000 OR @PageSize NOT BETWEEN 1 AND 200
       OR @Page IS NULL OR @PageSize IS NULL
        THROW 52102, N'Invalid public map filters.', 1;
    DECLARE @Pattern NVARCHAR(610) = NULL;
    IF NULLIF(LTRIM(RTRIM(@Query)), N'') IS NOT NULL
        SET @Pattern = N'%' + REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Query)),
            N'~', N'~~'), N'%', N'~%'), N'_', N'~_'), N'[', N'~[') + N'%';

    SELECT projects.Id, projects.PublicId, projects.Slug, projects.Title, projects.Summary,
        organizations.Name AS OrganizationName, projects.ProjectStatus, projects.ProjectStage,
        projects.FundingGap, projects.Currency,
        CASE WHEN JSON_VALUE(projects.EnrichmentJson, '$.locationVisibility') = N'2'
                  AND coordinates.Latitude BETWEEN -90 AND 90 AND coordinates.Longitude BETWEEN -180 AND 180
             THEN ROUND(coordinates.Latitude, 2) END AS Latitude,
        CASE WHEN JSON_VALUE(projects.EnrichmentJson, '$.locationVisibility') = N'2'
                  AND coordinates.Latitude BETWEEN -90 AND 90 AND coordinates.Longitude BETWEEN -180 AND 180
             THEN ROUND(coordinates.Longitude, 2) END AS Longitude
    INTO #Visible
    FROM dbo.FundingPlatform_Projects AS projects
    INNER JOIN dbo.FundingPlatform_ifn_ProjectMarketplaceReady() AS ready ON ready.ProjectId = projects.Id
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations ON organizations.Id = projects.OrganizationId
    CROSS APPLY (SELECT TRY_CONVERT(DECIMAL(31,28), JSON_VALUE(projects.EnrichmentJson, '$.latitude')) AS Latitude,
        TRY_CONVERT(DECIMAL(31,28), JSON_VALUE(projects.EnrichmentJson, '$.longitude')) AS Longitude) AS coordinates
    WHERE (@Pattern IS NULL OR projects.Title LIKE @Pattern ESCAPE N'~'
        OR projects.Summary LIKE @Pattern ESCAPE N'~' OR organizations.Name LIKE @Pattern ESCAPE N'~')
      AND (@ProjectStage IS NULL OR projects.ProjectStage = @ProjectStage)
      AND (@ProjectStatus IS NULL OR projects.ProjectStatus = @ProjectStatus)
      AND (@CountryId IS NULL OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectCountries
          WHERE ProjectId = projects.Id AND CountryId = @CountryId))
      AND (@CategoryId IS NULL OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectCategories
          WHERE ProjectId = projects.Id AND FundingCategoryId = @CategoryId))
      AND (@SustainableDevelopmentGoalId IS NULL OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectSustainableDevelopmentGoals
          WHERE ProjectId = projects.Id AND SustainableDevelopmentGoalId = @SustainableDevelopmentGoalId));

    SELECT COUNT_BIG(CASE WHEN Latitude IS NOT NULL AND Longitude IS NOT NULL THEN 1 END) AS TotalCount,
        COUNT_BIG(CASE WHEN Latitude IS NULL OR Longitude IS NULL THEN 1 END) AS WithoutPublicLocationCount FROM #Visible;
    SELECT PublicId, Slug, Title, Summary, OrganizationName, Latitude, Longitude,
        ProjectStatus, ProjectStage, FundingGap, Currency FROM #Visible
    WHERE Latitude IS NOT NULL AND Longitude IS NOT NULL
    ORDER BY Id DESC OFFSET ((CONVERT(BIGINT, @Page) - 1) * @PageSize) ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectMap_Search TO FundingPlatform_ApiRuntimeRole;
GO
