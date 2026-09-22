/* Localized list projections. One bounded read for the already-authorized page.
   No external provider, scheduler, writes to opportunities or translated search index. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingTranslation_ReadSummaries
 @ReferencesJson NVARCHAR(MAX), @Language NVARCHAR(20)
AS
BEGIN
 SET NOCOUNT ON;
 IF @Language IS NULL OR @Language COLLATE Latin1_General_100_BIN2 NOT IN (N'es',N'en')
    OR DATALENGTH(@Language) <> 4
    OR @ReferencesJson IS NULL OR DATALENGTH(@ReferencesJson) > 40000
    OR ISJSON(@ReferencesJson, ARRAY) <> 1
    THROW 56060, N'Invalid translation page.', 1;
 IF (SELECT COUNT(*) FROM OPENJSON(@ReferencesJson)) > 100
    OR EXISTS(SELECT 1 FROM OPENJSON(@ReferencesJson) WHERE [type] <> 5)
    THROW 56060, N'Invalid translation page.', 1;
 DECLARE @References TABLE(OpportunityId UNIQUEIDENTIFIER PRIMARY KEY, SourceContentVersion INT NOT NULL);
 /* Reject duplicates, coercions, excess fields and malformed GUIDs before typed parsing. */
 IF EXISTS(SELECT 1 FROM OPENJSON(@ReferencesJson) item
    WHERE (SELECT COUNT(*) FROM OPENJSON(item.[value])) <> 2
       OR (SELECT COUNT(*) FROM OPENJSON(item.[value]) WHERE [key] COLLATE Latin1_General_100_BIN2 = N'opportunityId' AND [type] = 1) <> 1
       OR (SELECT COUNT(*) FROM OPENJSON(item.[value]) WHERE [key] COLLATE Latin1_General_100_BIN2 = N'sourceContentVersion' AND [type] = 2) <> 1
       OR DATALENGTH(JSON_VALUE(item.[value], '$.opportunityId')) <> 72
       OR TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(item.[value], '$.opportunityId')) IS NULL
       OR TRY_CONVERT(INT, JSON_VALUE(item.[value], '$.sourceContentVersion')) IS NULL
       OR TRY_CONVERT(INT, JSON_VALUE(item.[value], '$.sourceContentVersion')) < 1)
    THROW 56060, N'Invalid translation references.', 1;
 IF EXISTS(SELECT TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE([value], '$.opportunityId'))
    FROM OPENJSON(@ReferencesJson) GROUP BY TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE([value], '$.opportunityId')) HAVING COUNT(*) > 1)
    THROW 56060, N'Duplicate translation reference.', 1;
 INSERT @References SELECT TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE([value], '$.opportunityId')),
    TRY_CONVERT(INT, JSON_VALUE([value], '$.sourceContentVersion')) FROM OPENJSON(@ReferencesJson);
 SELECT o.PublicId AS OpportunityId, t.Language, t.SourceContentVersion, t.Revision, t.Reviewed,
    JSON_VALUE(t.TextJson, '$.title') AS Title, JSON_VALUE(t.TextJson, '$.summary') AS Summary
 FROM @References r
 JOIN dbo.FundingPlatform_FundingOpportunities o ON o.PublicId = r.OpportunityId AND o.ContentVersion = r.SourceContentVersion
 JOIN dbo.FundingPlatform_FundingTranslations t ON t.FundingOpportunityId = o.Id
 WHERE t.Language = @Language COLLATE Latin1_General_100_BIN2 AND t.Reviewed = 1
   AND t.SourceContentVersion = o.ContentVersion
   AND EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() p WHERE p.FundingOpportunityId = o.Id);
END;
GO
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_FundingTranslation_ReadSummaries TO FundingPlatform_ApiRuntimeRole;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Public_List
    @Query NVARCHAR(300) = NULL,
    @PageNumber INT = 1,
    @PageSize INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    IF @PageNumber < 1 THROW 51603, N'PageNumber must be at least 1.', 1;
    IF @PageSize < 1 OR @PageSize > 100
        THROW 51604, N'PageSize must be between 1 and 100.', 1;
    DECLARE @QueryLike NVARCHAR(302) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Query)), N'') IS NULL THEN NULL
             ELSE N'%' + LTRIM(RTRIM(@Query)) + N'%' END;

    SELECT COUNT_BIG(1) AS TotalCount
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    WHERE opportunities.PublicationStatus = 2 AND opportunities.IsActive = 1
      AND EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs() AS catalogs
           WHERE catalogs.FundingOpportunityId = opportunities.Id)
      AND (@QueryLike IS NULL OR opportunities.Title LIKE @QueryLike
           OR opportunities.SponsorName LIKE @QueryLike OR opportunities.Summary LIKE @QueryLike)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCategories AS categories
           WHERE categories.FundingOpportunityId = opportunities.Id)
      AND
          ((opportunities.GeographicScope = 1 AND EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS countries
               WHERE countries.FundingOpportunityId = opportunities.Id))
           OR (opportunities.GeographicScope = 2
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS countries
                    WHERE countries.FundingOpportunityId = opportunities.Id)
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions AS regions
                    WHERE regions.FundingOpportunityId = opportunities.Id)))
      AND NOT EXISTS
          (SELECT required.FieldPath
           FROM (VALUES (N'/title'), (N'/description'),
                        (N'/eligibilityDescription'), (N'/closeDate')) AS required(FieldPath)
           WHERE NOT EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
              WHERE evidence.FundingOpportunityId = opportunities.Id
                AND evidence.FieldPath = required.FieldPath AND evidence.IsSelected = 1
                AND JSON_VALUE(evidence.ValueJson, '$.status') IN (N'known', N'unknown')))
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
           INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
           WHERE links.FundingOpportunityId = opportunities.Id AND links.Role = 1
             AND links.IsActive = 1 AND funders.PublicationStatus = 2 AND funders.IsActive = 1)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
           INNER JOIN dbo.FundingPlatform_FundingSources AS sources ON sources.Id = links.FundingSourceId
           WHERE links.FundingOpportunityId = opportunities.Id AND links.IsPrimary = 1
             AND links.IsActive = 1 AND sources.IsEnabled = 1
             AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL);

    SELECT opportunities.PublicId AS FundingOpportunityPublicId, opportunities.CoverKey, opportunities.ContentVersion,
           opportunities.Slug, opportunities.Title, opportunities.Summary,
           opportunities.SponsorName, opportunities.Currency,
           opportunities.MinAmount, opportunities.MaxAmount,
           opportunities.OpenDate, opportunities.CloseDate,
           opportunities.PublishedAtUtc, opportunities.DataQualityScore,
           primaryFunder.FunderPublicId AS PrimaryFunderPublicId,
           primaryFunder.FunderName AS PrimaryFunderName,
           primarySource.SourceName, primarySource.SourceUrl
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    CROSS APPLY
    (
        SELECT funders.PublicId AS FunderPublicId, funders.Name AS FunderName
        FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
        INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
        WHERE links.FundingOpportunityId = opportunities.Id AND links.Role = 1
          AND links.IsActive = 1 AND funders.PublicationStatus = 2 AND funders.IsActive = 1
    ) AS primaryFunder
    CROSS APPLY
    (
        SELECT sources.Name AS SourceName, links.SourceUrl
        FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
        INNER JOIN dbo.FundingPlatform_FundingSources AS sources ON sources.Id = links.FundingSourceId
        WHERE links.FundingOpportunityId = opportunities.Id AND links.IsPrimary = 1
          AND links.IsActive = 1 AND sources.IsEnabled = 1
          AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL
    ) AS primarySource
    WHERE opportunities.PublicationStatus = 2 AND opportunities.IsActive = 1
      AND EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs() AS catalogs
           WHERE catalogs.FundingOpportunityId = opportunities.Id)
      AND (@QueryLike IS NULL OR opportunities.Title LIKE @QueryLike
           OR opportunities.SponsorName LIKE @QueryLike OR opportunities.Summary LIKE @QueryLike)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCategories AS categories
           WHERE categories.FundingOpportunityId = opportunities.Id)
      AND
          ((opportunities.GeographicScope = 1 AND EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS countries
               WHERE countries.FundingOpportunityId = opportunities.Id))
           OR (opportunities.GeographicScope = 2
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS countries
                    WHERE countries.FundingOpportunityId = opportunities.Id)
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions AS regions
                    WHERE regions.FundingOpportunityId = opportunities.Id)))
      AND NOT EXISTS
          (SELECT required.FieldPath
           FROM (VALUES (N'/title'), (N'/description'),
                        (N'/eligibilityDescription'), (N'/closeDate')) AS required(FieldPath)
           WHERE NOT EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
              WHERE evidence.FundingOpportunityId = opportunities.Id
                AND evidence.FieldPath = required.FieldPath AND evidence.IsSelected = 1
                AND JSON_VALUE(evidence.ValueJson, '$.status') IN (N'known', N'unknown')))
    ORDER BY CASE WHEN opportunities.CloseDate IS NULL THEN 1 ELSE 0 END,
             opportunities.CloseDate, opportunities.Id DESC
    OFFSET ((@PageNumber - 1) * @PageSize) ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @Query NVARCHAR(300) = NULL,
    @Sponsor NVARCHAR(300) = NULL,
    @Currency CHAR(3) = NULL,
    @MinAmount DECIMAL(19,4) = NULL,
    @MaxAmount DECIMAL(19,4) = NULL,
    @ClosingFrom DATE = NULL,
    @ClosingTo DATE = NULL,
    @OnlyOpen BIT = 0,
    @Sort NVARCHAR(30) = N'closing-soon',
    @PageNumber INT = 1,
    @PageSize INT = 20,
    @CountryIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @RegionIds dbo.FundingPlatform_IntIdList READONLY,
    @CategoryIds dbo.FundingPlatform_IntIdList READONLY,
    @TagIds dbo.FundingPlatform_BigIntIdList READONLY,
    @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @FundingTypeIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @FunderPublicIds dbo.FundingPlatform_GuidIdList READONLY,
    @OrganizationTypeIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @MatchedCount BIGINT = NULL OUTPUT,
    @EffectiveSearchMode NVARCHAR(20) = NULL OUTPUT
WITH EXECUTE AS OWNER
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
      AND organizations.IsActive = 1
      AND users.PublicId = @UserPublicId;

    IF @OrganizationId IS NULL OR @UserId IS NULL
        THROW 52001, N'The workspace resource was not found.', 1;

    DECLARE @NormalizedQuery NVARCHAR(300) = NULLIF(LTRIM(RTRIM(@Query)), N'');
    DECLARE @NormalizedSponsor NVARCHAR(300) = NULLIF(LTRIM(RTRIM(@Sponsor)), N'');
    DECLARE @NormalizedCurrency CHAR(3) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Currency)), '') IS NULL THEN NULL
             ELSE UPPER(LTRIM(RTRIM(@Currency))) END;
    DECLARE @NormalizedSort NVARCHAR(30) = LOWER(LTRIM(RTRIM(COALESCE(@Sort, N''))));
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @TodayUtc DATE = CONVERT(DATE, @NowUtc);
    DECLARE @Offset BIGINT;

    IF @PageNumber < 1 OR @PageNumber > 10000 OR @PageSize < 1 OR @PageSize > 50
       OR @OnlyOpen IS NULL
       OR @NormalizedSort NOT IN
          (N'relevance', N'closing-soon', N'newest', N'amount-asc', N'amount-desc')
       OR (@NormalizedSort = N'relevance' AND @NormalizedQuery IS NULL)
       OR @MinAmount < 0 OR @MaxAmount < 0
       OR (@MinAmount IS NOT NULL AND @MaxAmount IS NOT NULL AND @MinAmount > @MaxAmount)
       OR (@ClosingFrom IS NOT NULL AND @ClosingTo IS NOT NULL
           AND @ClosingFrom > @ClosingTo)
       OR ((@MinAmount IS NOT NULL OR @MaxAmount IS NOT NULL
            OR @NormalizedSort IN (N'amount-asc', N'amount-desc'))
           AND @NormalizedCurrency IS NULL)
       OR (@NormalizedCurrency IS NOT NULL AND
           (LEN(@NormalizedCurrency) <> 3 OR @NormalizedCurrency LIKE '%[^A-Z]%'))
        THROW 52002, N'The search filters are invalid.', 1;

    /* Catalog IDs can become stale between rendering and submitting a filter.
       Unknown/inactive values simply do not match; a mixed list still keeps
       its valid OR alternatives and never turns a normal race into a 500. */

    SET @Offset = (CONVERT(BIGINT, @PageNumber) - 1) * CONVERT(BIGINT, @PageSize);

    DECLARE @QueryPattern NVARCHAR(610) = NULL;
    DECLARE @SponsorPattern NVARCHAR(610) = NULL;
    IF @NormalizedQuery IS NOT NULL
        SET @QueryPattern = N'%' +
            REPLACE(REPLACE(REPLACE(REPLACE(@NormalizedQuery,
                N'~', N'~~'), N'%', N'~%'), N'_', N'~_'), N'[', N'~[') + N'%';
    IF @NormalizedSponsor IS NOT NULL
        SET @SponsorPattern = N'%' +
            REPLACE(REPLACE(REPLACE(REPLACE(@NormalizedSponsor,
                N'~', N'~~'), N'%', N'~%'), N'_', N'~_'), N'[', N'~[') + N'%';

    CREATE TABLE #TextRanks
    (
        FundingOpportunityId BIGINT NOT NULL PRIMARY KEY,
        TextRank INT NOT NULL
    );

    CREATE TABLE #LiteralRanks
    (
        FundingOpportunityId BIGINT NOT NULL PRIMARY KEY,
        TextRank INT NOT NULL
    );

    IF @NormalizedQuery IS NOT NULL
        INSERT INTO #LiteralRanks (FundingOpportunityId, TextRank)
        SELECT opportunities.Id,
               CASE
                   WHEN opportunities.Title = @NormalizedQuery THEN 1000
                   WHEN opportunities.Title LIKE @QueryPattern ESCAPE N'~' THEN 800
                   WHEN opportunities.SponsorName LIKE @QueryPattern ESCAPE N'~' THEN 600
                   WHEN opportunities.Summary LIKE @QueryPattern ESCAPE N'~' THEN 400
                   WHEN opportunities.Description LIKE @QueryPattern ESCAPE N'~' THEN 300
                   WHEN opportunities.EligibilityDescription LIKE @QueryPattern ESCAPE N'~' THEN 200
                   ELSE 100
               END
        FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
        WHERE opportunities.Title LIKE @QueryPattern ESCAPE N'~'
           OR opportunities.SponsorName LIKE @QueryPattern ESCAPE N'~'
           OR opportunities.Summary LIKE @QueryPattern ESCAPE N'~'
           OR opportunities.Description LIKE @QueryPattern ESCAPE N'~'
           OR opportunities.EligibilityDescription LIKE @QueryPattern ESCAPE N'~'
           OR opportunities.Requirements LIKE @QueryPattern ESCAPE N'~';

    DECLARE @SearchMode NVARCHAR(20) = N'filtered';
    DECLARE @FullTextReady BIT = 0;
    DECLARE @FullTextObjectId INT =
        OBJECT_ID(N'dbo.FundingPlatform_FundingOpportunities');
    DECLARE @FullTextCatalogId INT =
        (SELECT fulltext_catalog_id FROM sys.fulltext_catalogs
         WHERE name = N'FundingPlatform_FundingSearchCatalog'
           AND is_accent_sensitivity_on = 0
           AND principal_id = DATABASE_PRINCIPAL_ID(N'dbo'));
    DECLARE @FullTextKeyIndexId INT =
        (SELECT index_id FROM sys.indexes
         WHERE object_id = @FullTextObjectId
           AND name = N'FundingPlatform_PK_FundingOpportunities');
    IF @NormalizedQuery IS NOT NULL
       AND COALESCE(FULLTEXTSERVICEPROPERTY('IsFullTextInstalled'), 0) = 1
       AND EXISTS
       (
           SELECT 1
           FROM sys.fulltext_indexes AS indexes
           WHERE indexes.object_id = @FullTextObjectId
             AND indexes.fulltext_catalog_id = @FullTextCatalogId
             AND indexes.unique_index_id = @FullTextKeyIndexId
             AND indexes.is_enabled = 1
             AND indexes.change_tracking_state_desc = N'AUTO'
             AND indexes.stoplist_id = 0
             AND indexes.property_list_id IS NULL
             AND indexes.has_crawl_completed = 1
       )
       AND NOT EXISTS
           (SELECT 1 FROM sys.fulltext_indexes AS indexes
            WHERE indexes.fulltext_catalog_id = @FullTextCatalogId
              AND indexes.object_id <> @FullTextObjectId)
       AND (SELECT COUNT_BIG(1)
            FROM sys.fulltext_index_columns AS indexedColumns
            INNER JOIN sys.columns AS columns
                ON columns.object_id = indexedColumns.object_id
               AND columns.column_id = indexedColumns.column_id
            WHERE indexedColumns.object_id = @FullTextObjectId
              AND columns.name IN
                  (N'Title', N'Description', N'Summary', N'SponsorName',
                   N'EligibilityDescription', N'Requirements')
              AND indexedColumns.language_id = 0
              AND indexedColumns.statistical_semantics = 0) = 6
       AND NOT EXISTS
           (SELECT 1
            FROM sys.fulltext_index_columns AS indexedColumns
            INNER JOIN sys.columns AS columns
                ON columns.object_id = indexedColumns.object_id
               AND columns.column_id = indexedColumns.column_id
            WHERE indexedColumns.object_id = @FullTextObjectId
              AND (columns.name NOT IN
                   (N'Title', N'Description', N'Summary', N'SponsorName',
                    N'EligibilityDescription', N'Requirements')
                   OR indexedColumns.language_id <> 0
                   OR indexedColumns.statistical_semantics <> 0))
       AND FULLTEXTCATALOGPROPERTY
           (N'FundingPlatform_FundingSearchCatalog', 'PopulateStatus') = 0
       AND OBJECTPROPERTYEX(@FullTextObjectId, 'TableFullTextPopulateStatus') = 0
       AND OBJECTPROPERTYEX(@FullTextObjectId, 'TableFulltextFailCount') = 0
        SET @FullTextReady = 1;

    IF @NormalizedQuery IS NOT NULL AND @FullTextReady = 1
    BEGIN
        BEGIN TRY
            EXEC sys.sp_executesql
                N'INSERT INTO #TextRanks (FundingOpportunityId, TextRank)
                  SELECT results.[KEY], results.[RANK]
                  FROM FREETEXTTABLE
                  (
                      dbo.FundingPlatform_FundingOpportunities,
                      (Title, Description, Summary, SponsorName,
                       EligibilityDescription, Requirements),
                      @SearchQuery
                  ) AS results;',
                N'@SearchQuery NVARCHAR(300)',
                @SearchQuery = @NormalizedQuery;
            SET @SearchMode = N'full-text';

            /* AUTO change tracking is asynchronous. Preserve zero literal
               omissions and deterministic exact-match relevance for commits
               that have not reached the index yet. */
            UPDATE ranked
            SET ranked.TextRank = CASE
                                      WHEN literal.TextRank > ranked.TextRank
                                      THEN literal.TextRank
                                      ELSE ranked.TextRank
                                  END
            FROM #TextRanks AS ranked
            INNER JOIN #LiteralRanks AS literal
                ON literal.FundingOpportunityId = ranked.FundingOpportunityId;

            INSERT INTO #TextRanks (FundingOpportunityId, TextRank)
            SELECT literal.FundingOpportunityId, literal.TextRank
            FROM #LiteralRanks AS literal
            WHERE NOT EXISTS
                (SELECT 1 FROM #TextRanks AS ranked
                 WHERE ranked.FundingOpportunityId = literal.FundingOpportunityId);
        END TRY
        BEGIN CATCH
            DELETE FROM #TextRanks;
            SET @FullTextReady = 0;
        END CATCH;
    END;

    IF @NormalizedQuery IS NOT NULL AND @FullTextReady = 0
    BEGIN
        INSERT INTO #TextRanks (FundingOpportunityId, TextRank)
        SELECT FundingOpportunityId, TextRank FROM #LiteralRanks;
        SET @SearchMode = N'literal-fallback';
    END;

    CREATE TABLE #Matches
    (
        FundingOpportunityId BIGINT NOT NULL PRIMARY KEY,
        TextRank INT NOT NULL
    );

    INSERT INTO #Matches (FundingOpportunityId, TextRank)
    SELECT opportunities.Id, COALESCE(textRanks.TextRank, 0)
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
        ON ready.FundingOpportunityId = opportunities.Id
    LEFT JOIN #TextRanks AS textRanks
        ON textRanks.FundingOpportunityId = opportunities.Id
    WHERE (@NormalizedQuery IS NULL OR textRanks.FundingOpportunityId IS NOT NULL)
      AND (@NormalizedSponsor IS NULL
           OR opportunities.SponsorName LIKE @SponsorPattern ESCAPE N'~')
      AND (@NormalizedCurrency IS NULL OR opportunities.Currency = @NormalizedCurrency)
      AND (@MinAmount IS NULL OR
           (opportunities.AmountStatus = 1
            AND COALESCE(opportunities.MaxAmount, opportunities.MinAmount) >= @MinAmount))
      AND (@MaxAmount IS NULL OR
           (opportunities.AmountStatus = 1
            AND COALESCE(opportunities.MinAmount, opportunities.MaxAmount) <= @MaxAmount))
      AND (@ClosingFrom IS NULL OR opportunities.CloseDate >= @ClosingFrom)
      AND (@ClosingTo IS NULL OR opportunities.CloseDate <= @ClosingTo)
      AND (@OnlyOpen = 0 OR
           ((opportunities.OpenDate IS NULL OR opportunities.OpenDate <= @TodayUtc)
            AND (opportunities.DeadlineType = 2
                 OR (opportunities.DeadlineType = 1
                     AND ((opportunities.CloseAtUtc IS NOT NULL
                           AND opportunities.CloseAtUtc > @NowUtc)
                          OR (opportunities.CloseAtUtc IS NULL
                              AND opportunities.CloseDate >= @TodayUtc))))))
      AND (NOT EXISTS (SELECT 1 FROM @CountryIds)
           OR opportunities.GeographicScope = 2 OR EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS links
            INNER JOIN @CountryIds AS ids ON ids.Id = links.CountryId
            WHERE links.FundingOpportunityId = opportunities.Id))
      AND (NOT EXISTS (SELECT 1 FROM @RegionIds)
           OR opportunities.GeographicScope = 2 OR EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions AS links
            INNER JOIN @RegionIds AS ids ON ids.Id = links.RegionId
            WHERE links.FundingOpportunityId = opportunities.Id))
      AND (NOT EXISTS (SELECT 1 FROM @CategoryIds) OR EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCategories AS links
            INNER JOIN @CategoryIds AS ids ON ids.Id = links.FundingCategoryId
            WHERE links.FundingOpportunityId = opportunities.Id))
      AND (NOT EXISTS (SELECT 1 FROM @TagIds) OR EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityTags AS links
            INNER JOIN @TagIds AS ids ON ids.Id = links.TagId
            WHERE links.FundingOpportunityId = opportunities.Id))
      AND (NOT EXISTS (SELECT 1 FROM @BeneficiaryTypeIds) OR EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes AS links
            INNER JOIN @BeneficiaryTypeIds AS ids ON ids.Id = links.BeneficiaryTypeId
            WHERE links.FundingOpportunityId = opportunities.Id))
      AND (NOT EXISTS (SELECT 1 FROM @ProjectTypeIds) OR EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityProjectTypes AS links
            INNER JOIN @ProjectTypeIds AS ids ON ids.Id = links.ProjectTypeId
            WHERE links.FundingOpportunityId = opportunities.Id))
      AND (NOT EXISTS (SELECT 1 FROM @FundingTypeIds)
           OR opportunities.FundingTypeId IN (SELECT Id FROM @FundingTypeIds))
      AND (NOT EXISTS (SELECT 1 FROM @FunderPublicIds) OR EXISTS
           (SELECT 1
            FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
            INNER JOIN dbo.FundingPlatform_Funders AS funders
                ON funders.Id = links.FunderId
               AND funders.PublicationStatus = 2 AND funders.IsActive = 1
            INNER JOIN @FunderPublicIds AS ids ON ids.Id = funders.PublicId
            WHERE links.FundingOpportunityId = opportunities.Id
              AND links.IsActive = 1))
      AND (NOT EXISTS (SELECT 1 FROM @OrganizationTypeIds) OR EXISTS
           (SELECT 1
            FROM dbo.FundingPlatform_FundingOpportunityOrganizationTypes AS links
            INNER JOIN @OrganizationTypeIds AS ids
                ON ids.Id = links.OrganizationTypeId
            WHERE links.FundingOpportunityId = opportunities.Id
              AND links.EligibilityMode = 1));

    SELECT @MatchedCount = COUNT_BIG(1) FROM #Matches;
    SET @EffectiveSearchMode = @SearchMode;
    SELECT @MatchedCount AS TotalCount, @SearchMode AS SearchMode;

    SELECT opportunities.PublicId AS FundingOpportunityPublicId, opportunities.CoverKey, opportunities.ContentVersion,
           opportunities.Slug, opportunities.Title, opportunities.Summary,
           opportunities.SponsorName, opportunities.Currency,
           opportunities.MinAmount, opportunities.MaxAmount,
           opportunities.OpenDate, opportunities.CloseDate, opportunities.CloseAtUtc,
           opportunities.DeadlineType, opportunities.DeadlinePrecision,
           opportunities.PublishedAtUtc, opportunities.DataQualityScore,
           primaryFunder.FunderPublicId AS PrimaryFunderPublicId,
           primaryFunder.FunderName AS PrimaryFunderName,
           primarySource.SourceName, primarySource.SourceUrl,
           CONVERT(BIT, CASE WHEN favorites.FundingOpportunityId IS NULL THEN 0 ELSE 1 END)
               AS IsFavorite
    FROM #Matches AS matches
    INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
        ON opportunities.Id = matches.FundingOpportunityId
    CROSS APPLY
    (
        SELECT funders.PublicId AS FunderPublicId, funders.Name AS FunderName
        FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
        INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
        WHERE links.FundingOpportunityId = opportunities.Id
          AND links.Role = 1 AND links.IsActive = 1
          AND funders.PublicationStatus = 2 AND funders.IsActive = 1
    ) AS primaryFunder
    CROSS APPLY
    (
        SELECT sources.Name AS SourceName, links.SourceUrl
        FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
        INNER JOIN dbo.FundingPlatform_FundingSources AS sources
            ON sources.Id = links.FundingSourceId
        WHERE links.FundingOpportunityId = opportunities.Id
          AND links.IsPrimary = 1 AND links.IsActive = 1
          AND sources.IsEnabled = 1
          AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL
    ) AS primarySource
    LEFT JOIN dbo.FundingPlatform_UserFundingFavorites AS favorites
        ON favorites.OrganizationId = @OrganizationId
       AND favorites.UserId = @UserId
       AND favorites.FundingOpportunityId = opportunities.Id
    ORDER BY
        CASE WHEN @NormalizedSort = N'relevance' THEN matches.TextRank END DESC,
        CASE WHEN @NormalizedSort IN (N'relevance', N'closing-soon')
             AND opportunities.DeadlineType = 2 THEN 1
             WHEN @NormalizedSort IN (N'relevance', N'closing-soon')
             AND opportunities.CloseDate IS NULL THEN 2 ELSE 0 END,
        CASE WHEN @NormalizedSort IN (N'relevance', N'closing-soon')
             THEN COALESCE(opportunities.CloseAtUtc,
                           DATEADD(DAY, 1, CONVERT(DATETIME2(3), opportunities.CloseDate))) END,
        CASE WHEN @NormalizedSort = N'newest' THEN opportunities.PublishedAtUtc END DESC,
        CASE WHEN @NormalizedSort IN (N'amount-asc', N'amount-desc')
                  AND opportunities.MaxAmount IS NULL
             THEN 1 ELSE 0 END,
        CASE WHEN @NormalizedSort = N'amount-asc'
             THEN opportunities.MaxAmount END,
        CASE WHEN @NormalizedSort = N'amount-desc'
             THEN opportunities.MaxAmount END DESC,
        opportunities.Id DESC
    OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Favorite_List
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @PageNumber INT = 1,
    @PageSize INT = 20,
    @MatchedCount BIGINT = NULL OUTPUT
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
      AND organizations.IsActive = 1
      AND users.PublicId = @UserPublicId;

    IF @OrganizationId IS NULL OR @UserId IS NULL
        THROW 52001, N'The workspace resource was not found.', 1;
    IF @PageNumber < 1 OR @PageNumber > 10000 OR @PageSize < 1 OR @PageSize > 50
        THROW 52002, N'The favorite page is invalid.', 1;

    DECLARE @Offset BIGINT =
        (CONVERT(BIGINT, @PageNumber) - 1) * CONVERT(BIGINT, @PageSize);

    SELECT @MatchedCount = COUNT_BIG(1)
    FROM dbo.FundingPlatform_UserFundingFavorites AS favorites
    INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
        ON ready.FundingOpportunityId = favorites.FundingOpportunityId
    WHERE favorites.OrganizationId = @OrganizationId AND favorites.UserId = @UserId;
    SELECT @MatchedCount AS TotalCount;

    SELECT opportunities.PublicId AS FundingOpportunityPublicId, opportunities.CoverKey, opportunities.ContentVersion,
           opportunities.Slug, opportunities.Title, opportunities.Summary,
           opportunities.SponsorName, opportunities.Currency,
           opportunities.MinAmount, opportunities.MaxAmount,
           opportunities.OpenDate, opportunities.CloseDate, opportunities.CloseAtUtc,
           opportunities.DeadlineType, opportunities.DeadlinePrecision,
           opportunities.PublishedAtUtc, opportunities.DataQualityScore,
           primaryFunder.FunderPublicId AS PrimaryFunderPublicId,
           primaryFunder.FunderName AS PrimaryFunderName,
           primarySource.SourceName, primarySource.SourceUrl,
           CONVERT(BIT, 1) AS IsFavorite, favorites.CreatedAtUtc AS FavoriteCreatedAtUtc
    FROM dbo.FundingPlatform_UserFundingFavorites AS favorites
    INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
        ON ready.FundingOpportunityId = favorites.FundingOpportunityId
    INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
        ON opportunities.Id = favorites.FundingOpportunityId
    CROSS APPLY
    (
        SELECT funders.PublicId AS FunderPublicId, funders.Name AS FunderName
        FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
        INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
        WHERE links.FundingOpportunityId = opportunities.Id
          AND links.Role = 1 AND links.IsActive = 1
          AND funders.PublicationStatus = 2 AND funders.IsActive = 1
    ) AS primaryFunder
    CROSS APPLY
    (
        SELECT sources.Name AS SourceName, links.SourceUrl
        FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
        INNER JOIN dbo.FundingPlatform_FundingSources AS sources
            ON sources.Id = links.FundingSourceId
        WHERE links.FundingOpportunityId = opportunities.Id
          AND links.IsPrimary = 1 AND links.IsActive = 1
          AND sources.IsEnabled = 1
          AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL
    ) AS primarySource
    WHERE favorites.OrganizationId = @OrganizationId AND favorites.UserId = @UserId
    ORDER BY favorites.CreatedAtUtc DESC, favorites.FundingOpportunityId DESC
    OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
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
   JSON_QUERY((SELECT p.PublicId AS id, p.ContentVersion AS contentVersion, p.Slug AS slug, p.Title AS title, p.Summary AS summary,
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
