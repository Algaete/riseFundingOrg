/* Curated discovery metadata is independent of, and bound to, the editorial content version.
   Public classification never outlives a parent revision; imported drafts remain drafts. */
SET XACT_ABORT ON;
CREATE TABLE dbo.FundingPlatform_FundingDiscovery
(
    FundingOpportunityId BIGINT NOT NULL PRIMARY KEY REFERENCES dbo.FundingPlatform_FundingOpportunities(Id),
    ContentVersion INT NOT NULL CHECK(ContentVersion > 0),
    DataJson NVARCHAR(MAX) NOT NULL CHECK(ISJSON(DataJson) = 1),
    ReviewedByUserId BIGINT NOT NULL REFERENCES dbo.FundingPlatform_Users(Id),
    ReviewedAtUtc DATETIME2(3) NOT NULL,
    RowVersion ROWVERSION NOT NULL
);
CREATE TABLE dbo.FundingPlatform_FundingDiscoveryReviews
(
    Id BIGINT IDENTITY NOT NULL PRIMARY KEY,
    FundingOpportunityId BIGINT NOT NULL REFERENCES dbo.FundingPlatform_FundingOpportunities(Id),
    ActorUserId BIGINT NOT NULL REFERENCES dbo.FundingPlatform_Users(Id),
    ContentVersion INT NOT NULL,
    DataJson NVARCHAR(MAX) NOT NULL CHECK(ISJSON(DataJson) = 1),
    KeyHash BINARY(32) NOT NULL, RequestHash BINARY(32) NOT NULL, ResultVersion BINARY(8) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FundingPlatform_UQ_FundingDiscoveryReviews_Key UNIQUE(ActorUserId, KeyHash)
);
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingDiscovery_AdminGet
 @UserPublicId UNIQUEIDENTIFIER, @OpportunityPublicId UNIQUEIDENTIFIER
AS
BEGIN
 SET NOCOUNT ON;
 IF dbo.FundingPlatform_fn_AdminAccessState(@UserPublicId) <> 2 THROW 51601, N'Administrative access required.', 1;
 SELECT (SELECT p.PublicId AS opportunityId, p.Title AS title, p.ContentVersion AS contentVersion,
    metadata.ContentVersion AS reviewedContentVersion, JSON_QUERY(metadata.DataJson) AS data,
    CASE WHEN metadata.RowVersion IS NOT NULL THEN N'"' + CONVERT(NVARCHAR(16), metadata.RowVersion, 2) + N'"' END AS eTag,
    JSON_QUERY(COALESCE((SELECT N'[' + STRING_AGG(CONVERT(NVARCHAR(MAX), N'"' + STRING_ESCAPE(url, 'json') + N'"'), N',') + N']'
      FROM (SELECT links.SourceUrl AS url FROM dbo.FundingPlatform_FundingOpportunitySourceLinks links
            WHERE links.FundingOpportunityId = p.Id AND links.IsActive = 1
            UNION SELECT p.ApplicationUrl WHERE p.ApplicationUrl IS NOT NULL) urls), N'[]')) AS sourceUrls
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES) AS Json
 FROM dbo.FundingPlatform_FundingOpportunities p
 LEFT JOIN dbo.FundingPlatform_FundingDiscovery metadata ON metadata.FundingOpportunityId = p.Id
 WHERE p.PublicId = @OpportunityPublicId AND p.IsActive = 1;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingDiscovery_Review
 @UserPublicId UNIQUEIDENTIFIER, @OpportunityPublicId UNIQUEIDENTIFIER, @ContentVersion INT,
 @DataJson NVARCHAR(MAX), @ExpectedVersion BINARY(8), @KeyHash BINARY(32), @RequestHash BINARY(32)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF @ContentVersion IS NULL OR @ContentVersion < 1 OR @KeyHash IS NULL OR @RequestHash IS NULL OR ISJSON(@DataJson) <> 1
    THROW 55704, N'Invalid classification.', 1;
 DECLARE @Kind INT = TRY_CONVERT(INT, JSON_VALUE(@DataJson, '$.funderKind'));
 IF @Kind NOT BETWEEN 1 AND 6 OR JSON_VALUE(@DataJson, '$.requiresConsortium') NOT IN (N'true', N'false')
    OR JSON_VALUE(@DataJson, '$.requiresInternationalPartner') NOT IN (N'true', N'false')
    OR NULLIF(JSON_VALUE(@DataJson, '$.evidenceUrl'), N'') IS NULL
    THROW 55704, N'Invalid classification.', 1;
 DECLARE @Actor BIGINT, @Id BIGINT, @CurrentVersion INT, @PreviousVersion BINARY(8), @ResultVersion BINARY(8), @Replay BIT = 0;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.FundingPlatform_usp_AdminActor_Lock @UserPublicId, @Actor OUTPUT;
  SELECT @Id = Id, @CurrentVersion = ContentVersion FROM dbo.FundingPlatform_FundingOpportunities WITH(UPDLOCK, HOLDLOCK)
   WHERE PublicId = @OpportunityPublicId AND IsActive = 1;
  IF @Id IS NULL THROW 55701, N'Opportunity not available.', 1;
  DECLARE @PreviousHash BINARY(32), @PreviousId BIGINT;
  SELECT @PreviousHash = RequestHash, @PreviousId = FundingOpportunityId, @ResultVersion = ResultVersion
    FROM dbo.FundingPlatform_FundingDiscoveryReviews WITH(UPDLOCK, HOLDLOCK) WHERE ActorUserId = @Actor AND KeyHash = @KeyHash;
  IF @PreviousHash IS NOT NULL
  BEGIN
    IF @PreviousHash <> @RequestHash OR @PreviousId <> @Id THROW 55703, N'Command key conflict.', 1;
    SET @Replay = 1;
  END
  ELSE
  BEGIN
    IF @CurrentVersion <> @ContentVersion THROW 55702, N'Opportunity content changed.', 1;
    SELECT @PreviousVersion = RowVersion FROM dbo.FundingPlatform_FundingDiscovery WITH(UPDLOCK, HOLDLOCK) WHERE FundingOpportunityId = @Id;
    IF (@ExpectedVersion IS NULL AND @PreviousVersion IS NOT NULL) OR (@ExpectedVersion IS NOT NULL AND (@PreviousVersion IS NULL OR @PreviousVersion <> @ExpectedVersion))
       THROW 55702, N'Classification changed.', 1;
    DECLARE @Evidence NVARCHAR(2000) = JSON_VALUE(@DataJson, '$.evidenceUrl');
    IF @Evidence NOT LIKE N'https://%' OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks WHERE FundingOpportunityId = @Id AND IsActive = 1 AND SourceUrl = @Evidence
        UNION ALL SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE Id = @Id AND ApplicationUrl = @Evidence)
       THROW 55704, N'Evidence must be an existing opportunity source.', 1;
    IF @PreviousVersion IS NULL
       INSERT dbo.FundingPlatform_FundingDiscovery(FundingOpportunityId, ContentVersion, DataJson, ReviewedByUserId, ReviewedAtUtc)
       VALUES(@Id, @ContentVersion, @DataJson, @Actor, SYSUTCDATETIME());
    ELSE UPDATE dbo.FundingPlatform_FundingDiscovery SET ContentVersion = @ContentVersion, DataJson = @DataJson,
       ReviewedByUserId = @Actor, ReviewedAtUtc = SYSUTCDATETIME() WHERE FundingOpportunityId = @Id;
    SELECT @ResultVersion = RowVersion FROM dbo.FundingPlatform_FundingDiscovery WHERE FundingOpportunityId = @Id;
    INSERT dbo.FundingPlatform_FundingDiscoveryReviews(FundingOpportunityId, ActorUserId, ContentVersion, DataJson, KeyHash, RequestHash, ResultVersion)
       VALUES(@Id, @Actor, @ContentVersion, @DataJson, @KeyHash, @RequestHash, @ResultVersion);
  END;
  COMMIT TRANSACTION;
  SELECT (SELECT @OpportunityPublicId AS entityId, N'"' + CONVERT(NVARCHAR(16), @ResultVersion, 2) + N'"' AS eTag, @Replay AS wasReplay FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS Json;
 END TRY
 BEGIN CATCH
  IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
  THROW;
 END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingDiscovery_Search @FiltersJson NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON;
 IF ISJSON(@FiltersJson) <> 1 THROW 55704, N'Invalid filters.', 1;
 DECLARE @Query NVARCHAR(300), @Country SMALLINT, @Region INT, @Category INT, @FundingType SMALLINT, @OrganizationType SMALLINT, @Language SMALLINT,
   @Kind TINYINT, @Consortium BIT, @International BIT, @Minimum DECIMAL(19,4), @Maximum DECIMAL(19,4), @Currency CHAR(3),
   @ClosingFrom DATE, @ClosingTo DATE, @OnlyOpen BIT, @Page INT, @PageSize INT;
 SELECT @Query = query, @Country = countryId, @Region = regionId, @Category = categoryId, @FundingType = fundingTypeId,
   @OrganizationType = organizationTypeId, @Language = languageId, @Kind = funderKind, @Consortium = requiresConsortium,
   @International = requiresInternationalPartner, @Minimum = minimumAmount, @Maximum = maximumAmount, @Currency = currency,
   @ClosingFrom = closingFrom, @ClosingTo = closingTo, @OnlyOpen = onlyOpen, @Page = page, @PageSize = pageSize
 FROM OPENJSON(@FiltersJson) WITH(query NVARCHAR(300), countryId SMALLINT, regionId INT, categoryId INT, fundingTypeId SMALLINT,
   organizationTypeId SMALLINT, languageId SMALLINT, funderKind TINYINT, requiresConsortium BIT, requiresInternationalPartner BIT,
   minimumAmount DECIMAL(19,4), maximumAmount DECIMAL(19,4), currency CHAR(3), closingFrom DATE, closingTo DATE, onlyOpen BIT, page INT, pageSize INT);
 IF @Page IS NULL OR @Page NOT BETWEEN 1 AND 10000 OR @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 50
    OR @Minimum < 0 OR @Maximum < 0 OR @Minimum > @Maximum OR ((@Minimum IS NOT NULL OR @Maximum IS NOT NULL) AND @Currency IS NULL)
    THROW 55704, N'Invalid filters.', 1;
 DECLARE @Like NVARCHAR(610) = CASE WHEN NULLIF(LTRIM(RTRIM(@Query)), N'') IS NULL THEN NULL ELSE N'%' +
   REPLACE(REPLACE(REPLACE(REPLACE(@Query, N'~', N'~~'), N'%', N'~%'), N'_', N'~_'), N'[', N'~[') + N'%' END;
 SELECT p.Id INTO #Ids
 FROM dbo.FundingPlatform_FundingOpportunities p
 INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() ready ON ready.FundingOpportunityId = p.Id
 LEFT JOIN dbo.FundingPlatform_FundingDiscovery metadata ON metadata.FundingOpportunityId = p.Id AND metadata.ContentVersion = p.ContentVersion
 WHERE (@Like IS NULL OR p.Title LIKE @Like ESCAPE N'~' OR p.Summary LIKE @Like ESCAPE N'~' OR p.SponsorName LIKE @Like ESCAPE N'~')
   AND (@Country IS NULL OR p.GeographicScope = 2 OR EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries WHERE FundingOpportunityId = p.Id AND CountryId = @Country))
   AND (@Region IS NULL OR p.GeographicScope = 2 OR EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions WHERE FundingOpportunityId = p.Id AND RegionId = @Region))
   AND (@Category IS NULL OR EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCategories WHERE FundingOpportunityId = p.Id AND FundingCategoryId = @Category))
   AND (@FundingType IS NULL OR p.FundingTypeId = @FundingType)
   AND (@OrganizationType IS NULL OR (EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityOrganizationTypes WHERE FundingOpportunityId = p.Id AND OrganizationTypeId = @OrganizationType AND EligibilityMode = 1)
     AND NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityOrganizationTypes WHERE FundingOpportunityId = p.Id AND OrganizationTypeId = @OrganizationType AND EligibilityMode = 2)))
   AND (@Language IS NULL OR EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityLanguages WHERE FundingOpportunityId = p.Id AND LanguageId = @Language))
   AND (@Kind IS NULL OR TRY_CONVERT(TINYINT, JSON_VALUE(metadata.DataJson, '$.funderKind')) = @Kind)
   AND (@Consortium IS NULL OR JSON_VALUE(metadata.DataJson, '$.requiresConsortium') = CASE WHEN @Consortium = 1 THEN N'true' ELSE N'false' END)
   AND (@International IS NULL OR JSON_VALUE(metadata.DataJson, '$.requiresInternationalPartner') = CASE WHEN @International = 1 THEN N'true' ELSE N'false' END)
   AND (@Currency IS NULL OR p.Currency = @Currency)
   AND (@Minimum IS NULL OR (p.AmountStatus = 1 AND (p.MaxAmount >= @Minimum OR (p.MaxAmount IS NULL AND p.MinAmount IS NOT NULL))))
   AND (@Maximum IS NULL OR (p.AmountStatus = 1 AND (p.MinAmount <= @Maximum OR (p.MinAmount IS NULL AND p.MaxAmount IS NOT NULL))))
   AND (@ClosingFrom IS NULL OR p.CloseDate >= @ClosingFrom) AND (@ClosingTo IS NULL OR p.CloseDate <= @ClosingTo)
   AND (@OnlyOpen = 0 OR ((p.OpenDate IS NULL OR p.OpenDate <= CONVERT(DATE, SYSUTCDATETIME())) AND
     (p.DeadlineType = 2 OR (p.DeadlineType = 1 AND ((p.DeadlinePrecision = 2 AND p.CloseAtUtc > SYSUTCDATETIME())
       OR (p.DeadlinePrecision = 1 AND p.CloseDate >= CONVERT(DATE, SYSUTCDATETIME())))))));
 SELECT (SELECT (SELECT COUNT_BIG(1) FROM #Ids) AS totalCount, @Page AS page, @PageSize AS pageSize,
   JSON_QUERY((SELECT p.PublicId AS id, p.Slug AS slug, p.Title AS title, p.Summary AS summary,
     source.SourceName AS sourceName, source.SourceUrl AS sourceUrl, TODATETIMEOFFSET(p.LastVerifiedAtUtc, '+00:00') AS lastVerifiedAtUtc,
     p.MinAmount AS minimumAmount, p.MaxAmount AS maximumAmount, p.Currency AS currency, p.CloseDate AS closeDate,
     JSON_QUERY(metadata.DataJson) AS classification
     FROM #Ids ids INNER JOIN dbo.FundingPlatform_FundingOpportunities p ON p.Id = ids.Id
     LEFT JOIN dbo.FundingPlatform_FundingDiscovery metadata ON metadata.FundingOpportunityId = p.Id AND metadata.ContentVersion = p.ContentVersion
     CROSS APPLY(SELECT TOP(1) s.Name AS SourceName, l.SourceUrl FROM dbo.FundingPlatform_FundingOpportunitySourceLinks l
       INNER JOIN dbo.FundingPlatform_FundingSources s ON s.Id = l.FundingSourceId AND s.IsEnabled = 1
       WHERE l.FundingOpportunityId = p.Id AND l.IsActive = 1 AND l.IsPrimary = 1 ORDER BY l.FundingSourceId) source
     ORDER BY p.UpdatedAtUtc DESC, p.Id OFFSET (@Page - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY
     FOR JSON PATH, INCLUDE_NULL_VALUES)) AS items FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS Json;
END;
GO
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_FundingDiscovery_Search TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_FundingDiscovery_AdminGet TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_FundingDiscovery_Review TO FundingPlatform_ApiRuntimeRole;
