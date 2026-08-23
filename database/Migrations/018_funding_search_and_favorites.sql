/* FASE 8A: organization-scoped search, complete published detail and private
   per-user favorites. Full-Text provisioning is intentionally separate because
   Full-Text index creation cannot run inside the migrator transaction. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

CREATE TYPE dbo.FundingPlatform_GuidIdList AS TABLE
(
    Id UNIQUEIDENTIFIER NOT NULL,
    PRIMARY KEY (Id)
);
GO

CREATE TABLE dbo.FundingPlatform_UserFundingFavorites
(
    OrganizationId BIGINT NOT NULL,
    UserId BIGINT NOT NULL,
    FundingOpportunityId BIGINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_UserFundingFavorites_CreatedAtUtc
        DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_UserFundingFavorites
        PRIMARY KEY (OrganizationId, UserId, FundingOpportunityId),
    CONSTRAINT FundingPlatform_FK_UserFundingFavorites_Membership
        FOREIGN KEY (OrganizationId, UserId)
        REFERENCES dbo.FundingPlatform_OrganizationUsers (OrganizationId, UserId),
    CONSTRAINT FundingPlatform_FK_UserFundingFavorites_Opportunity
        FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id)
);

CREATE INDEX FundingPlatform_IX_UserFundingFavorites_UserCreated
    ON dbo.FundingPlatform_UserFundingFavorites
       (OrganizationId, UserId, CreatedAtUtc DESC, FundingOpportunityId DESC);

/* Supports currency/range/deadline filters without copying searchable text. */
CREATE INDEX FundingPlatform_IX_FundingOpportunities_PublicFilter
    ON dbo.FundingPlatform_FundingOpportunities
       (Currency, FundingTypeId, CloseDate, Id)
    INCLUDE (PublicId, Slug, Title, SponsorName, MinAmount, MaxAmount,
             OpenDate, CloseAtUtc, PublishedAtUtc, DataQualityScore)
    WHERE PublicationStatus = 2 AND IsActive = 1;
GO

/* Keep the public catalog and the authenticated workspace on the same
   fail-closed catalog guard. Optional relation catalogs added after the
   original guard must also remain active (and approved for tags). */
CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs()
RETURNS TABLE
AS
RETURN
(
    SELECT opportunities.Id AS FundingOpportunityId
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    WHERE (opportunities.Currency IS NULL OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_Currencies AS currencies
           WHERE currencies.Code = opportunities.Currency AND currencies.IsActive = 1))
      AND (opportunities.FundingTypeId IS NULL OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingTypes AS fundingTypes
           WHERE fundingTypes.Id = opportunities.FundingTypeId AND fundingTypes.IsActive = 1))
      AND (opportunities.IssuerCountryId IS NULL OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_Countries AS issuerCountries
           WHERE issuerCountries.Id = opportunities.IssuerCountryId
             AND issuerCountries.IsActive = 1))
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityCountries AS links
           LEFT JOIN dbo.FundingPlatform_Countries AS countries
               ON countries.Id = links.CountryId AND countries.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id AND countries.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityRegions AS links
           LEFT JOIN dbo.FundingPlatform_Regions AS regions
               ON regions.Id = links.RegionId AND regions.IsActive = 1
           LEFT JOIN dbo.FundingPlatform_Countries AS countries
               ON countries.Id = regions.CountryId AND countries.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id
             AND (regions.Id IS NULL OR countries.Id IS NULL))
      AND EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityCategories AS links
           INNER JOIN dbo.FundingPlatform_FundingCategories AS categories
               ON categories.Id = links.FundingCategoryId AND categories.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityCategories AS links
           LEFT JOIN dbo.FundingPlatform_FundingCategories AS categories
               ON categories.Id = links.FundingCategoryId AND categories.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id AND categories.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes AS links
           LEFT JOIN dbo.FundingPlatform_BeneficiaryTypes AS beneficiaryTypes
               ON beneficiaryTypes.Id = links.BeneficiaryTypeId AND beneficiaryTypes.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id AND beneficiaryTypes.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityProjectTypes AS links
           LEFT JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
               ON projectTypes.Id = links.ProjectTypeId AND projectTypes.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id AND projectTypes.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityTags AS links
           LEFT JOIN dbo.FundingPlatform_Tags AS tags
               ON tags.Id = links.TagId
              AND tags.IsActive = 1 AND tags.IsApproved = 1
           WHERE links.FundingOpportunityId = opportunities.Id AND tags.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityOrganizationTypes AS links
           LEFT JOIN dbo.FundingPlatform_OrganizationTypes AS organizationTypes
               ON organizationTypes.Id = links.OrganizationTypeId
              AND organizationTypes.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id
             AND organizationTypes.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityLegalEntityTypes AS links
           LEFT JOIN dbo.FundingPlatform_LegalEntityTypes AS legalEntityTypes
               ON legalEntityTypes.Id = links.LegalEntityTypeId
              AND legalEntityTypes.IsActive = 1
           LEFT JOIN dbo.FundingPlatform_Countries AS legalCountries
               ON legalCountries.Id = legalEntityTypes.CountryId
              AND legalCountries.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id
             AND (legalEntityTypes.Id IS NULL
                  OR (legalEntityTypes.CountryId IS NOT NULL AND legalCountries.Id IS NULL)))
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityLanguages AS links
           LEFT JOIN dbo.FundingPlatform_Languages AS languages
               ON languages.Id = links.LanguageId AND languages.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id
             AND languages.Id IS NULL)
      AND
          ((opportunities.GeographicScope = 1 AND EXISTS
              (SELECT 1
               FROM dbo.FundingPlatform_FundingOpportunityCountries AS links
               INNER JOIN dbo.FundingPlatform_Countries AS countries
                   ON countries.Id = links.CountryId AND countries.IsActive = 1
               WHERE links.FundingOpportunityId = opportunities.Id))
           OR (opportunities.GeographicScope = 2
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS links
                    WHERE links.FundingOpportunityId = opportunities.Id)
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions AS links
                    WHERE links.FundingOpportunityId = opportunities.Id)))
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityFunderIdentityConflicts AS conflicts
           INNER JOIN dbo.FundingPlatform_FundingOpportunityFunders AS primaryLinks
               ON primaryLinks.FundingOpportunityId = conflicts.FundingOpportunityId
              AND primaryLinks.FunderId = conflicts.CandidateFunderId
              AND primaryLinks.Role = 1 AND primaryLinks.IsActive = 1
           WHERE conflicts.FundingOpportunityId = opportunities.Id
             AND conflicts.IsExistingLink = 1 AND conflicts.Status = 0)
);
GO

/* Non-materialized shared publication guard. It returns only the internal key;
   no private/source payload is duplicated and there is no state to refresh. */
CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_FundingOpportunityPublicReady()
RETURNS TABLE
AS
RETURN
(
    SELECT opportunities.Id AS FundingOpportunityId
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs() AS catalogs
        ON catalogs.FundingOpportunityId = opportunities.Id
    WHERE opportunities.PublicationStatus = 2
      AND opportunities.IsActive = 1
      AND NOT EXISTS
          (SELECT required.FieldPath
           FROM (VALUES (N'/title'), (N'/description'),
                        (N'/eligibilityDescription'), (N'/closeDate')) AS required(FieldPath)
           WHERE NOT EXISTS
             (SELECT 1
              FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
              WHERE evidence.FundingOpportunityId = opportunities.Id
                AND evidence.FieldPath = required.FieldPath
                AND evidence.IsSelected = 1
                AND JSON_VALUE(evidence.ValueJson, '$.status') IN (N'known', N'unknown')))
      AND EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
           INNER JOIN dbo.FundingPlatform_Funders AS funders
               ON funders.Id = links.FunderId
              AND funders.PublicationStatus = 2
              AND funders.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id
             AND links.Role = 1 AND links.IsActive = 1)
      AND EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
           INNER JOIN dbo.FundingPlatform_FundingSources AS sources
               ON sources.Id = links.FundingSourceId AND sources.IsEnabled = 1
           WHERE links.FundingOpportunityId = opportunities.Id
             AND links.IsPrimary = 1 AND links.IsActive = 1
             AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL)
);
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

    SELECT opportunities.PublicId AS FundingOpportunityPublicId,
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

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_OrganizationGet
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @FundingOpportunityPublicId UNIQUEIDENTIFIER = NULL,
    @Slug NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @OpportunityId BIGINT;
    DECLARE @NormalizedSlug NVARCHAR(320) = NULLIF(LTRIM(RTRIM(@Slug)), N'');
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
    IF (@FundingOpportunityPublicId IS NULL AND @NormalizedSlug IS NULL)
       OR (@FundingOpportunityPublicId IS NOT NULL AND @NormalizedSlug IS NOT NULL)
        THROW 52002, N'Exactly one opportunity identifier is required.', 1;

    SELECT @OpportunityId = opportunities.Id
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
        ON ready.FundingOpportunityId = opportunities.Id
    WHERE (@FundingOpportunityPublicId IS NOT NULL
           AND opportunities.PublicId = @FundingOpportunityPublicId)
       OR (@NormalizedSlug IS NOT NULL AND opportunities.Slug = @NormalizedSlug);

    IF @OpportunityId IS NULL
        THROW 52001, N'The workspace resource was not found.', 1;

    SELECT opportunities.PublicId AS FundingOpportunityPublicId,
           opportunities.Slug, opportunities.Title, opportunities.Description,
           opportunities.Summary, opportunities.SponsorName, opportunities.SponsorUrl,
           opportunities.ApplicationUrl, opportunities.IssuerCountryId,
           opportunities.FundingTypeId, opportunities.Currency,
           opportunities.MinAmount, opportunities.MaxAmount, opportunities.AmountStatus,
           opportunities.OpenDate, opportunities.CloseDate, opportunities.CloseAtUtc,
           opportunities.DeadlineTimeZoneId, opportunities.DeadlineType,
           opportunities.DeadlinePrecision, opportunities.EligibilityDescription,
           opportunities.Requirements, opportunities.Objectives,
           opportunities.AllowedActivities, opportunities.ExcludedActivities,
           opportunities.Restrictions, opportunities.TargetOrganizationsDescription,
           opportunities.TargetPopulationsDescription, opportunities.MinimumOperatingYears,
           opportunities.RequiresLegalEntity, opportunities.RequiresPriorExperience,
           opportunities.RequiresCofunding, opportunities.CofundingPercentage,
           opportunities.GeographicScope, opportunities.RemoteApplication,
           opportunities.LastVerifiedAtUtc, opportunities.DataQualityScore,
           opportunities.ContentVersion, opportunities.PublishedAtUtc,
           CONVERT(BIT, CASE WHEN favorites.FundingOpportunityId IS NULL THEN 0 ELSE 1 END)
               AS IsFavorite,
           primaryFunder.FunderPublicId AS PrimaryFunderPublicId,
           primaryFunder.FunderSlug AS PrimaryFunderSlug,
           primaryFunder.FunderName AS PrimaryFunderName, primarySource.SourceName,
           primarySource.SourceUrl, primarySource.ExternalId
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    CROSS APPLY
    (
        SELECT funders.PublicId AS FunderPublicId, funders.Slug AS FunderSlug,
               funders.Name AS FunderName
        FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
        INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
        WHERE links.FundingOpportunityId = opportunities.Id
          AND links.Role = 1 AND links.IsActive = 1
          AND funders.PublicationStatus = 2 AND funders.IsActive = 1
    ) AS primaryFunder
    CROSS APPLY
    (
        SELECT sources.Name AS SourceName, links.SourceUrl, links.ExternalId
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
    WHERE opportunities.Id = @OpportunityId;

    SELECT links.CountryId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityCountries AS links
    INNER JOIN dbo.FundingPlatform_Countries AS catalogs
        ON catalogs.Id = links.CountryId AND catalogs.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.CountryId;

    SELECT links.RegionId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityRegions AS links
    INNER JOIN dbo.FundingPlatform_Regions AS catalogs
        ON catalogs.Id = links.RegionId AND catalogs.IsActive = 1
    INNER JOIN dbo.FundingPlatform_Countries AS countries
        ON countries.Id = catalogs.CountryId AND countries.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.RegionId;

    SELECT links.FundingCategoryId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityCategories AS links
    INNER JOIN dbo.FundingPlatform_FundingCategories AS catalogs
        ON catalogs.Id = links.FundingCategoryId AND catalogs.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.FundingCategoryId;

    SELECT links.BeneficiaryTypeId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes AS links
    INNER JOIN dbo.FundingPlatform_BeneficiaryTypes AS catalogs
        ON catalogs.Id = links.BeneficiaryTypeId AND catalogs.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.BeneficiaryTypeId;

    SELECT links.ProjectTypeId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityProjectTypes AS links
    INNER JOIN dbo.FundingPlatform_ProjectTypes AS catalogs
        ON catalogs.Id = links.ProjectTypeId AND catalogs.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.ProjectTypeId;

    SELECT links.TagId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityTags AS links
    INNER JOIN dbo.FundingPlatform_Tags AS catalogs
        ON catalogs.Id = links.TagId
       AND catalogs.IsActive = 1 AND catalogs.IsApproved = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.TagId;

    SELECT links.OrganizationTypeId AS Id, links.EligibilityMode
    FROM dbo.FundingPlatform_FundingOpportunityOrganizationTypes AS links
    INNER JOIN dbo.FundingPlatform_OrganizationTypes AS catalogs
        ON catalogs.Id = links.OrganizationTypeId AND catalogs.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId
    ORDER BY links.EligibilityMode, links.OrganizationTypeId;

    SELECT links.LegalEntityTypeId AS Id, links.EligibilityMode
    FROM dbo.FundingPlatform_FundingOpportunityLegalEntityTypes AS links
    INNER JOIN dbo.FundingPlatform_LegalEntityTypes AS catalogs
        ON catalogs.Id = links.LegalEntityTypeId AND catalogs.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId
    ORDER BY links.EligibilityMode, links.LegalEntityTypeId;

    SELECT links.LanguageId AS Id, links.LanguagePurpose
    FROM dbo.FundingPlatform_FundingOpportunityLanguages AS links
    INNER JOIN dbo.FundingPlatform_Languages AS catalogs
        ON catalogs.Id = links.LanguageId AND catalogs.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId
    ORDER BY links.LanguagePurpose, links.LanguageId;

    SELECT funders.PublicId AS FunderPublicId, funders.Slug, funders.Name, links.Role
    FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
    INNER JOIN dbo.FundingPlatform_Funders AS funders
        ON funders.Id = links.FunderId
       AND funders.PublicationStatus = 2 AND funders.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId AND links.IsActive = 1
    ORDER BY links.Role, funders.Name, funders.Id;

    SELECT links.FundingSourceId, sources.Name AS SourceName, links.ExternalId,
           links.SourceUrl, links.FirstSeenAtUtc, links.LastSeenAtUtc,
           links.IsPrimary, links.IsActive
    FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
    INNER JOIN dbo.FundingPlatform_FundingSources AS sources
        ON sources.Id = links.FundingSourceId AND sources.IsEnabled = 1
    WHERE links.FundingOpportunityId = @OpportunityId AND links.IsActive = 1
    ORDER BY links.IsPrimary DESC, links.Id;
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

    SELECT opportunities.PublicId AS FundingOpportunityPublicId,
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

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Favorite_Put
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @FundingOpportunityPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_FavoritePut;

    BEGIN TRY
        DECLARE @OrganizationId BIGINT, @UserId BIGINT, @OpportunityId BIGINT;
        DECLARE @CreatedAtUtc DATETIME2(3), @Code NVARCHAR(20) = N'unchanged';
        SELECT @OrganizationId = organizations.Id, @UserId = users.Id
        FROM dbo.FundingPlatform_Organizations AS organizations
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id
           AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users
            ON users.Id = memberships.UserId AND users.Status = 2
        WHERE organizations.PublicId = @OrganizationPublicId
          AND organizations.IsActive = 1
          AND users.PublicId = @UserPublicId;

        IF @OrganizationId IS NULL OR @UserId IS NULL
            THROW 52001, N'The workspace resource was not found.', 1;

        SELECT @OpportunityId = opportunities.Id
        FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
        INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
            ON ready.FundingOpportunityId = opportunities.Id
        WHERE opportunities.PublicId = @FundingOpportunityPublicId;
        IF @OpportunityId IS NULL
            THROW 52001, N'The workspace resource was not found.', 1;

        SELECT @CreatedAtUtc = CreatedAtUtc
        FROM dbo.FundingPlatform_UserFundingFavorites WITH (UPDLOCK, HOLDLOCK)
        WHERE OrganizationId = @OrganizationId AND UserId = @UserId
          AND FundingOpportunityId = @OpportunityId;

        IF @CreatedAtUtc IS NULL
        BEGIN
            SET @CreatedAtUtc = SYSUTCDATETIME();
            INSERT INTO dbo.FundingPlatform_UserFundingFavorites
                (OrganizationId, UserId, FundingOpportunityId, CreatedAtUtc)
            VALUES (@OrganizationId, @UserId, @OpportunityId, @CreatedAtUtc);
            SET @Code = N'created';
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
        SELECT @Code AS Code, @FundingOpportunityPublicId AS FundingOpportunityPublicId,
               @CreatedAtUtc AS CreatedAtUtc;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_FavoritePut;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Favorite_Delete
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @FundingOpportunityPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_FavoriteDelete;

    BEGIN TRY
        DECLARE @OrganizationId BIGINT, @UserId BIGINT, @OpportunityId BIGINT;
        DECLARE @DeletedAt TABLE (CreatedAtUtc DATETIME2(3) NOT NULL);
        SELECT @OrganizationId = organizations.Id, @UserId = users.Id
        FROM dbo.FundingPlatform_Organizations AS organizations
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id
           AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users
            ON users.Id = memberships.UserId AND users.Status = 2
        WHERE organizations.PublicId = @OrganizationPublicId
          AND organizations.IsActive = 1
          AND users.PublicId = @UserPublicId;

        IF @OrganizationId IS NULL OR @UserId IS NULL
            THROW 52001, N'The workspace resource was not found.', 1;

        SELECT @OpportunityId = Id
        FROM dbo.FundingPlatform_FundingOpportunities
        WHERE PublicId = @FundingOpportunityPublicId;

        IF @OpportunityId IS NOT NULL
            DELETE FROM dbo.FundingPlatform_UserFundingFavorites
            OUTPUT deleted.CreatedAtUtc INTO @DeletedAt (CreatedAtUtc)
            WHERE OrganizationId = @OrganizationId AND UserId = @UserId
              AND FundingOpportunityId = @OpportunityId;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
        SELECT CASE WHEN EXISTS (SELECT 1 FROM @DeletedAt)
                    THEN N'deleted' ELSE N'unchanged' END AS Code,
               @FundingOpportunityPublicId AS FundingOpportunityPublicId,
               (SELECT TOP (1) CreatedAtUtc FROM @DeletedAt) AS CreatedAtUtc;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_FavoriteDelete;
        THROW;
    END CATCH;
END;
GO
