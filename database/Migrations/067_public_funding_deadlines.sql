-- Expose existing reviewed deadline fields. Publication, translation and paging predicates are unchanged.
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Public_List
    @Query NVARCHAR(300) = NULL,
    @PageNumber INT = 1,
    @PageSize INT = 20,
    @IncludeReviewedTranslations BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    IF @PageNumber < 1 THROW 51603, N'PageNumber must be at least 1.', 1;
    IF @PageSize < 1 OR @PageSize > 100
        THROW 51604, N'PageSize must be between 1 and 100.', 1;
    DECLARE @NormalizedQuery NVARCHAR(300) = NULLIF(LTRIM(RTRIM(@Query)), N'');
    DECLARE @QueryLike NVARCHAR(610) = CASE WHEN @NormalizedQuery IS NULL THEN NULL ELSE N'%' +
        REPLACE(REPLACE(REPLACE(REPLACE(@NormalizedQuery, N'~', N'~~'), N'%', N'~%'), N'_', N'~_'), N'[', N'~[') + N'%' END;
    DECLARE @TranslationMatches TABLE(FundingOpportunityId BIGINT PRIMARY KEY);
    IF @IncludeReviewedTranslations = 1 AND @NormalizedQuery IS NOT NULL
        INSERT @TranslationMatches SELECT FundingOpportunityId
        FROM dbo.FundingPlatform_ifn_FundingTranslationSearch(@NormalizedQuery);

    SELECT COUNT_BIG(1) AS TotalCount
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    WHERE opportunities.PublicationStatus = 2 AND opportunities.IsActive = 1
      AND EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs() AS catalogs
           WHERE catalogs.FundingOpportunityId = opportunities.Id)
      AND (@QueryLike IS NULL OR opportunities.Title LIKE @QueryLike ESCAPE N'~'
           OR opportunities.SponsorName LIKE @QueryLike ESCAPE N'~' OR opportunities.Summary LIKE @QueryLike ESCAPE N'~'
           OR EXISTS(SELECT 1 FROM @TranslationMatches t WHERE t.FundingOpportunityId = opportunities.Id))
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
           opportunities.CloseAtUtc, opportunities.DeadlineType, opportunities.DeadlinePrecision, opportunities.DeadlineTimeZoneId,
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
      AND (@QueryLike IS NULL OR opportunities.Title LIKE @QueryLike ESCAPE N'~'
           OR opportunities.SponsorName LIKE @QueryLike ESCAPE N'~' OR opportunities.Summary LIKE @QueryLike ESCAPE N'~'
           OR EXISTS(SELECT 1 FROM @TranslationMatches t WHERE t.FundingOpportunityId = opportunities.Id))
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
