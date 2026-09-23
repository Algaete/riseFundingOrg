/* Optional human stories. No subscription gate, paid provider, files or donations. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF OBJECT_ID(N'dbo.FundingPlatform_Stories',N'U') IS NULL
BEGIN
 CREATE TABLE dbo.FundingPlatform_Stories(
  PublicId UNIQUEIDENTIFIER NOT NULL CONSTRAINT FundingPlatform_PK_Stories PRIMARY KEY, OrganizationId BIGINT NOT NULL, ProjectId BIGINT NULL,
  ContentJson NVARCHAR(MAX) NOT NULL, Status TINYINT NOT NULL CONSTRAINT FundingPlatform_DF_Story_Status DEFAULT 0, Revision INT NOT NULL,
  UpdatedByUserId BIGINT NOT NULL, UpdatedAtUtc DATETIME2(7) NOT NULL,
  RightsConfirmed BIT NOT NULL CONSTRAINT FundingPlatform_DF_Story_Rights DEFAULT 0,
  PersonalConsentConfirmed BIT NOT NULL CONSTRAINT FundingPlatform_DF_Story_Consent DEFAULT 0,
  CONSTRAINT FundingPlatform_FK_Story_Organization FOREIGN KEY(OrganizationId) REFERENCES dbo.FundingPlatform_Organizations(Id),
  CONSTRAINT FundingPlatform_FK_Story_ProjectOrganization FOREIGN KEY(ProjectId,OrganizationId) REFERENCES dbo.FundingPlatform_Projects(Id,OrganizationId),
  CONSTRAINT FundingPlatform_FK_Story_User FOREIGN KEY(UpdatedByUserId) REFERENCES dbo.FundingPlatform_Users(Id),
  CONSTRAINT FundingPlatform_CK_Story_Data CHECK(ISJSON(ContentJson,OBJECT)=1 AND Revision>0 AND Status IN(0,1,2) AND (Status<>1 OR RightsConfirmed=1))
 );
 CREATE INDEX FundingPlatform_IX_Stories_Organization ON dbo.FundingPlatform_Stories(OrganizationId,UpdatedAtUtc DESC);
 CREATE INDEX FundingPlatform_IX_Stories_Public ON dbo.FundingPlatform_Stories(Status,UpdatedAtUtc DESC);
 CREATE TABLE dbo.FundingPlatform_StoryHistory(
  StoryPublicId UNIQUEIDENTIFIER NOT NULL, Revision INT NOT NULL, ActorUserId BIGINT NOT NULL,
  Status TINYINT NOT NULL, ContentJson NVARCHAR(MAX) NOT NULL, RightsConfirmed BIT NOT NULL,
  PersonalConsentConfirmed BIT NOT NULL, CreatedAtUtc DATETIME2(7) NOT NULL,
  CONSTRAINT FundingPlatform_PK_StoryHistory PRIMARY KEY(StoryPublicId,Revision),
  CONSTRAINT FundingPlatform_FK_StoryHistory_Story FOREIGN KEY(StoryPublicId) REFERENCES dbo.FundingPlatform_Stories(PublicId),
  CONSTRAINT FundingPlatform_FK_StoryHistory_User FOREIGN KEY(ActorUserId) REFERENCES dbo.FundingPlatform_Users(Id)
 );
END;
GO
CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_StoryPublicReady()
RETURNS TABLE AS RETURN(
 SELECT s.PublicId FROM dbo.FundingPlatform_Stories s
 JOIN dbo.FundingPlatform_ifn_OrganizationMarketplaceReady() o ON o.OrganizationId=s.OrganizationId
 WHERE s.Status=1 AND s.RightsConfirmed=1
   AND ((JSON_VALUE(s.ContentJson,'$.containsPersonalExperiences')='false' AND JSON_VALUE(s.ContentJson,'$.kind')<>'beneficiaries') OR s.PersonalConsentConfirmed=1)
   AND (s.ProjectId IS NULL OR EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMarketplaceReady() p WHERE p.ProjectId=s.ProjectId AND p.OrganizationId=s.OrganizationId))
   AND NOT EXISTS(SELECT 1 FROM OPENJSON(s.ContentJson,'$.categoryIds') j LEFT JOIN dbo.FundingPlatform_FundingCategories c ON c.Id=TRY_CONVERT(INT,j.value) AND c.IsActive=1 WHERE c.Id IS NULL)
   AND NOT EXISTS(SELECT 1 FROM OPENJSON(s.ContentJson,'$.goalIds') j LEFT JOIN dbo.FundingPlatform_SustainableDevelopmentGoals c ON c.Id=TRY_CONVERT(INT,j.value) AND c.IsActive=1 WHERE c.Id IS NULL)
   AND NOT EXISTS(SELECT 1 FROM OPENJSON(s.ContentJson,'$.countryIds') j LEFT JOIN dbo.FundingPlatform_Countries c ON c.Id=TRY_CONVERT(INT,j.value) AND c.IsActive=1 WHERE c.Id IS NULL)
);
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Story_List
 @UserPublicId UNIQUEIDENTIFIER=NULL,@OrganizationPublicId UNIQUEIDENTIFIER=NULL,@ProjectPublicId UNIQUEIDENTIFIER=NULL,
 @StoryPublicId UNIQUEIDENTIFIER=NULL,@Page INT=1
AS
BEGIN
 SET NOCOUNT ON;
 IF @Page IS NULL OR @Page NOT BETWEEN 1 AND 1000 THROW 56122,N'Invalid page.',1;
 IF @UserPublicId IS NOT NULL AND NOT EXISTS(
  SELECT 1 FROM dbo.FundingPlatform_Organizations o JOIN dbo.FundingPlatform_OrganizationUsers m ON m.OrganizationId=o.Id
  JOIN dbo.FundingPlatform_Users u ON u.Id=m.UserId
  WHERE o.PublicId=@OrganizationPublicId AND o.IsActive=1 AND m.MembershipStatus=1 AND u.Status=2 AND u.PublicId=@UserPublicId)
  THROW 56120,N'Organization unavailable.',1;
 DECLARE @Visible TABLE(PublicId UNIQUEIDENTIFIER PRIMARY KEY);
 INSERT @Visible SELECT s.PublicId FROM dbo.FundingPlatform_Stories s
 JOIN dbo.FundingPlatform_Organizations o ON o.Id=s.OrganizationId
 LEFT JOIN dbo.FundingPlatform_Projects p ON p.Id=s.ProjectId
 WHERE (@OrganizationPublicId IS NULL OR o.PublicId=@OrganizationPublicId)
   AND (@ProjectPublicId IS NULL OR p.PublicId=@ProjectPublicId) AND (@StoryPublicId IS NULL OR s.PublicId=@StoryPublicId)
   AND (@UserPublicId IS NOT NULL OR EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_StoryPublicReady() ready WHERE ready.PublicId=s.PublicId));
 SELECT (SELECT (SELECT COUNT(*) FROM @Visible) AS totalCount,@Page AS page,
   JSON_QUERY((SELECT s.PublicId AS id,o.PublicId AS organizationId,o.Name AS organizationName,
     p.Title AS projectTitle,p.Slug AS projectSlug,JSON_QUERY(s.ContentJson) AS content,s.Status AS status,s.Revision AS revision,
     TODATETIMEOFFSET(s.UpdatedAtUtc,'+00:00') AS updatedAtUtc
    FROM @Visible v JOIN dbo.FundingPlatform_Stories s ON s.PublicId=v.PublicId
    JOIN dbo.FundingPlatform_Organizations o ON o.Id=s.OrganizationId LEFT JOIN dbo.FundingPlatform_Projects p ON p.Id=s.ProjectId
    ORDER BY s.UpdatedAtUtc DESC,s.PublicId OFFSET (@Page-1)*20 ROWS FETCH NEXT 20 ROWS ONLY FOR JSON PATH)) AS items
   FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) AS Json;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Story_Save
 @UserPublicId UNIQUEIDENTIFIER,@OrganizationPublicId UNIQUEIDENTIFIER,@StoryPublicId UNIQUEIDENTIFIER,@ExpectedRevision INT,@ContentJson NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF @StoryPublicId IS NULL OR @ExpectedRevision IS NULL OR @ExpectedRevision<0 OR @ContentJson IS NULL
   OR ISJSON(@ContentJson,OBJECT)<>1 OR DATALENGTH(@ContentJson)>240000 THROW 56122,N'Invalid story.',1;
 -- Only the canonical public fields are stored; reject arbitrary private metadata.
 IF EXISTS(SELECT 1 FROM OPENJSON(@ContentJson) WHERE [key] COLLATE Latin1_General_100_BIN2 NOT IN
   ('title','summary','body','kind','projectId','categoryIds','goalIds','countryIds','containsPersonalExperiences'))
   OR EXISTS(SELECT 1 FROM OPENJSON(@ContentJson) GROUP BY [key] COLLATE Latin1_General_100_BIN2 HAVING COUNT(*)>1)
   OR NOT EXISTS(SELECT 1 FROM OPENJSON(@ContentJson) WHERE [key]='containsPersonalExperiences' AND type=3)
   THROW 56122,N'Invalid story schema.',1;
 DECLARE @Title NVARCHAR(MAX),@Body NVARCHAR(MAX),@Summary NVARCHAR(MAX),@Kind NVARCHAR(100),@ProjectPublicId UNIQUEIDENTIFIER;
 SELECT @Title=Title,@Body=Body,@Summary=Summary,@Kind=Kind,@ProjectPublicId=ProjectId FROM OPENJSON(@ContentJson)
 WITH(Title NVARCHAR(MAX) '$.title',Body NVARCHAR(MAX) '$.body',Summary NVARCHAR(MAX) '$.summary',Kind NVARCHAR(100) '$.kind',ProjectId UNIQUEIDENTIFIER '$.projectId');
 IF LEN(TRIM(COALESCE(@Title,N'')))<3 OR DATALENGTH(@Title)>400 OR LEN(TRIM(COALESCE(@Body,N'')))<20 OR DATALENGTH(@Body)>30000
   OR DATALENGTH(@Summary)>1200 OR @Kind IS NULL OR @Kind COLLATE Latin1_General_100_BIN2 NOT IN('organization','project','fieldwork','volunteers','team','learning','impact','news','beneficiaries')
   OR JSON_VALUE(@ContentJson,'$.containsPersonalExperiences') IS NULL
   OR JSON_VALUE(@ContentJson,'$.containsPersonalExperiences') NOT IN('true','false')
   THROW 56122,N'Invalid story content.',1;
 IF ISNULL(ISJSON(JSON_QUERY(@ContentJson,'$.categoryIds'),ARRAY),0)<>1 OR ISNULL(ISJSON(JSON_QUERY(@ContentJson,'$.goalIds'),ARRAY),0)<>1
   OR ISNULL(ISJSON(JSON_QUERY(@ContentJson,'$.countryIds'),ARRAY),0)<>1 THROW 56122,N'Invalid story selections.',1;
 IF (SELECT COUNT(*) FROM OPENJSON(@ContentJson,'$.categoryIds'))>30 OR (SELECT COUNT(*) FROM OPENJSON(@ContentJson,'$.goalIds'))>17
   OR (SELECT COUNT(*) FROM OPENJSON(@ContentJson,'$.countryIds'))>50 THROW 56122,N'Too many story selections.',1;
 IF EXISTS(SELECT 1 FROM OPENJSON(@ContentJson,'$.categoryIds') j LEFT JOIN dbo.FundingPlatform_FundingCategories c ON c.Id=TRY_CONVERT(INT,j.value) AND c.IsActive=1 WHERE c.Id IS NULL OR j.type<>2)
   OR EXISTS(SELECT 1 FROM OPENJSON(@ContentJson,'$.goalIds') j LEFT JOIN dbo.FundingPlatform_SustainableDevelopmentGoals c ON c.Id=TRY_CONVERT(INT,j.value) AND c.IsActive=1 WHERE c.Id IS NULL OR j.type<>2)
   OR EXISTS(SELECT 1 FROM OPENJSON(@ContentJson,'$.countryIds') j LEFT JOIN dbo.FundingPlatform_Countries c ON c.Id=TRY_CONVERT(INT,j.value) AND c.IsActive=1 WHERE c.Id IS NULL OR j.type<>2)
   THROW 56122,N'Inactive story selections.',1;
 DECLARE @Org BIGINT,@Actor BIGINT,@Project BIGINT,@Current INT,@StoredOrg BIGINT,@Now DATETIME2(7)=SYSUTCDATETIME();
 BEGIN TRY
  BEGIN TRANSACTION;
  SELECT @Org=o.Id,@Actor=u.Id FROM dbo.FundingPlatform_Organizations o WITH(UPDLOCK,HOLDLOCK)
  JOIN dbo.FundingPlatform_OrganizationUsers m WITH(UPDLOCK,HOLDLOCK) ON m.OrganizationId=o.Id
  JOIN dbo.FundingPlatform_Users u WITH(UPDLOCK,HOLDLOCK) ON u.Id=m.UserId
  WHERE o.PublicId=@OrganizationPublicId AND o.IsActive=1 AND m.MembershipStatus=1 AND m.Role=1 AND u.Status=2 AND u.PublicId=@UserPublicId;
  IF @Org IS NULL THROW 56120,N'Organization unavailable.',1;
  IF @ProjectPublicId IS NOT NULL
  BEGIN
   SELECT @Project=Id FROM dbo.FundingPlatform_Projects WITH(UPDLOCK,HOLDLOCK) WHERE PublicId=@ProjectPublicId AND OrganizationId=@Org;
   IF @Project IS NULL THROW 56122,N'Project unavailable.',1;
  END;
  SELECT @Current=Revision,@StoredOrg=OrganizationId FROM dbo.FundingPlatform_Stories WITH(UPDLOCK,HOLDLOCK) WHERE PublicId=@StoryPublicId;
  IF @StoredOrg IS NOT NULL AND @StoredOrg<>@Org THROW 56120,N'Story unavailable.',1;
  IF ISNULL(@Current,0)<>@ExpectedRevision THROW 56121,N'Story changed.',1;
  IF @Current IS NULL
   INSERT dbo.FundingPlatform_Stories(PublicId,OrganizationId,ProjectId,ContentJson,Status,Revision,UpdatedByUserId,UpdatedAtUtc)
    VALUES(@StoryPublicId,@Org,@Project,@ContentJson,0,1,@Actor,@Now);
  ELSE UPDATE dbo.FundingPlatform_Stories SET ProjectId=@Project,ContentJson=@ContentJson,Status=0,Revision=Revision+1,
    RightsConfirmed=0,PersonalConsentConfirmed=0,UpdatedByUserId=@Actor,UpdatedAtUtc=@Now WHERE PublicId=@StoryPublicId;
  INSERT dbo.FundingPlatform_StoryHistory SELECT PublicId,Revision,@Actor,Status,ContentJson,RightsConfirmed,PersonalConsentConfirmed,@Now
    FROM dbo.FundingPlatform_Stories WHERE PublicId=@StoryPublicId;
  COMMIT TRANSACTION;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  THROW;
 END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Story_Publish
 @UserPublicId UNIQUEIDENTIFIER,@OrganizationPublicId UNIQUEIDENTIFIER,@StoryPublicId UNIQUEIDENTIFIER,@ExpectedRevision INT,
 @Publish BIT,@RightsConfirmed BIT,@PersonalConsentConfirmed BIT
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF @ExpectedRevision IS NULL OR @ExpectedRevision<1 OR @Publish IS NULL OR @RightsConfirmed IS NULL OR @PersonalConsentConfirmed IS NULL
   THROW 56122,N'Invalid publication.',1;
 DECLARE @Org BIGINT,@Actor BIGINT,@Current INT,@Personal BIT,@Kind VARCHAR(100),@Now DATETIME2(7)=SYSUTCDATETIME();
 BEGIN TRY
  BEGIN TRANSACTION;
  SELECT @Org=o.Id,@Actor=u.Id FROM dbo.FundingPlatform_Organizations o WITH(UPDLOCK,HOLDLOCK)
  JOIN dbo.FundingPlatform_OrganizationUsers m WITH(UPDLOCK,HOLDLOCK) ON m.OrganizationId=o.Id
  JOIN dbo.FundingPlatform_Users u WITH(UPDLOCK,HOLDLOCK) ON u.Id=m.UserId
  WHERE o.PublicId=@OrganizationPublicId AND o.IsActive=1 AND m.MembershipStatus=1 AND m.Role=1 AND u.Status=2 AND u.PublicId=@UserPublicId;
  IF @Org IS NULL THROW 56120,N'Organization unavailable.',1;
  SELECT @Current=Revision,@Personal=CASE WHEN JSON_VALUE(ContentJson,'$.containsPersonalExperiences')='true' THEN 1 ELSE 0 END,@Kind=JSON_VALUE(ContentJson,'$.kind')
    FROM dbo.FundingPlatform_Stories WITH(UPDLOCK,HOLDLOCK) WHERE PublicId=@StoryPublicId AND OrganizationId=@Org;
  IF @Current IS NULL THROW 56120,N'Story unavailable.',1;
  IF @Current<>@ExpectedRevision THROW 56121,N'Story changed.',1;
  IF @Publish=1 AND (@RightsConfirmed<>1 OR ((@Personal=1 OR @Kind='beneficiaries') AND @PersonalConsentConfirmed<>1))
    THROW 56123,N'Rights and consent must be confirmed.',1;
  UPDATE dbo.FundingPlatform_Stories SET Status=CASE WHEN @Publish=1 THEN 1 ELSE 2 END,Revision=Revision+1,
    RightsConfirmed=@RightsConfirmed,PersonalConsentConfirmed=@PersonalConsentConfirmed,UpdatedByUserId=@Actor,UpdatedAtUtc=@Now WHERE PublicId=@StoryPublicId;
  IF @Publish=1 AND NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_StoryPublicReady() WHERE PublicId=@StoryPublicId)
    THROW 56123,N'Organization, project or catalogs are not public-ready.',1;
  INSERT dbo.FundingPlatform_StoryHistory SELECT PublicId,Revision,@Actor,Status,ContentJson,RightsConfirmed,PersonalConsentConfirmed,@Now
    FROM dbo.FundingPlatform_Stories WHERE PublicId=@StoryPublicId;
  COMMIT TRANSACTION;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  THROW;
 END CATCH;
END;
GO
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_Story_List TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_Story_Save TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_Story_Publish TO FundingPlatform_ApiRuntimeRole;
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
      AND (EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMarketplaceReady() AS readyProjects
           WHERE readyProjects.OrganizationId = organizations.Id)
        OR EXISTS(SELECT 1 FROM dbo.FundingPlatform_Stories s
           JOIN dbo.FundingPlatform_ifn_StoryPublicReady() readyStories ON readyStories.PublicId=s.PublicId
           WHERE s.OrganizationId=organizations.Id));

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
