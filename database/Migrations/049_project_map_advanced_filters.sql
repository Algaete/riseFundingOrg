/* Advanced public map filters; additive procedure parameters, no account/content changes.
   Existing callers remain compatible. Requires 041. Preserves public readiness and location consent. */
SET XACT_ABORT ON;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectMap_Search
    @Query NVARCHAR(300) = NULL, @CountryId SMALLINT = NULL, @CategoryId INT = NULL,
    @ProjectStage TINYINT = NULL, @SustainableDevelopmentGoalId INT = NULL,
    @ProjectStatus TINYINT = NULL, @Page INT = 1, @PageSize INT = 100,
    @OrganizationTypeId SMALLINT = NULL, @MinimumFundingGap DECIMAL(19,4) = NULL,
    @MaximumFundingGap DECIMAL(19,4) = NULL, @Currency VARCHAR(10) = NULL,
    @SeekingFunding BIT = 0, @SeekingPartners BIT = 0, @SeekingProfessionals BIT = 0,
    @SeekingConsortium BIT = 0, @ProjectIdsJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF LEN(LTRIM(RTRIM(COALESCE(@Query, N'')))) > 200 OR @CountryId <= 0 OR @CategoryId <= 0
       OR @ProjectStage > 5 OR @ProjectStatus > 6 OR @SustainableDevelopmentGoalId NOT BETWEEN 1 AND 17
       OR @Page NOT BETWEEN 1 AND 10000 OR @PageSize NOT BETWEEN 1 AND 200
       OR @Page IS NULL OR @PageSize IS NULL
        THROW 52102, N'Invalid public map filters.', 1;
    IF @OrganizationTypeId <= 0 OR @MinimumFundingGap < 0 OR @MaximumFundingGap < 0
       OR @MinimumFundingGap > 999999999999 OR @MaximumFundingGap > 999999999999
       OR @MinimumFundingGap > @MaximumFundingGap
       OR ((@MinimumFundingGap IS NOT NULL OR @MaximumFundingGap IS NOT NULL) AND @Currency IS NULL)
       OR (@Currency IS NOT NULL AND (DATALENGTH(@Currency) <> 3 OR @Currency COLLATE Latin1_General_100_BIN2 LIKE '%[^A-Z]%'))
       OR @SeekingFunding IS NULL OR @SeekingPartners IS NULL OR @SeekingProfessionals IS NULL OR @SeekingConsortium IS NULL
        THROW 52102, N'Invalid advanced public map filters.', 1;

    DECLARE @SelectedProjects TABLE (Id UNIQUEIDENTIFIER PRIMARY KEY);
    IF @ProjectIdsJson IS NOT NULL
    BEGIN
        IF DATALENGTH(@ProjectIdsJson) > 4000 OR ISJSON(@ProjectIdsJson) <> 1 OR LEFT(LTRIM(@ProjectIdsJson), 1) <> N'['
            THROW 52102, N'Invalid public project selection.', 1;
        IF (SELECT COUNT(*) FROM OPENJSON(@ProjectIdsJson)) NOT BETWEEN 1 AND 50
           OR EXISTS (SELECT 1 FROM OPENJSON(@ProjectIdsJson) WHERE [type] <> 1 OR LEN([value]) <> 36
               OR TRY_CONVERT(UNIQUEIDENTIFIER, [value]) IS NULL
               OR TRY_CONVERT(UNIQUEIDENTIFIER, [value]) = '00000000-0000-0000-0000-000000000000')
           OR (SELECT COUNT(*) FROM OPENJSON(@ProjectIdsJson)) <>
              (SELECT COUNT(DISTINCT TRY_CONVERT(UNIQUEIDENTIFIER, [value])) FROM OPENJSON(@ProjectIdsJson))
            THROW 52102, N'Invalid public project selection.', 1;
        INSERT @SelectedProjects SELECT CONVERT(UNIQUEIDENTIFIER, [value]) FROM OPENJSON(@ProjectIdsJson);
    END;

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
      AND (@ProjectIdsJson IS NULL OR EXISTS (SELECT 1 FROM @SelectedProjects WHERE Id = projects.PublicId))
      AND (@OrganizationTypeId IS NULL OR organizations.OrganizationTypeId = @OrganizationTypeId)
      AND (@Currency IS NULL OR projects.Currency = @Currency)
      AND (@MinimumFundingGap IS NULL OR projects.FundingGap >= @MinimumFundingGap)
      AND (@MaximumFundingGap IS NULL OR projects.FundingGap <= @MaximumFundingGap)
      AND (@SeekingFunding = 0 OR projects.FundingGap > 0)
      AND (@SeekingPartners = 0 OR NULLIF(LTRIM(RTRIM(JSON_VALUE(projects.EnrichmentJson, '$.soughtPartners'))), N'') IS NOT NULL)
      AND (@SeekingProfessionals = 0 OR NULLIF(LTRIM(RTRIM(JSON_VALUE(projects.EnrichmentJson, '$.soughtProfessionals'))), N'') IS NOT NULL)
      AND (@SeekingConsortium = 0 OR JSON_VALUE(projects.EnrichmentJson, '$.seekingConsortium') = N'true')
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
