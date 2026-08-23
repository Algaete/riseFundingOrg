/* Non-transactional, idempotent FASE 8A Full-Text provisioning.
   Run only through DatabaseMigrator --provision-full-text, which owns a
   session-scoped application lock and verifies migration 018 first. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF @@TRANCOUNT <> 0
    THROW 52050, N'Full-Text provisioning must not run inside a user transaction.', 1;
IF COALESCE(FULLTEXTSERVICEPROPERTY('IsFullTextInstalled'), 0) <> 1
    THROW 52051, N'Full-Text Search is unavailable on the target database.', 1;
IF OBJECT_ID(N'dbo.FundingPlatform_FundingOpportunities', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ifn_FundingOpportunityPublicReady', N'IF') IS NULL
   OR NOT EXISTS
      (SELECT 1 FROM dbo.FundingPlatform_SchemaVersions WHERE Version = 18)
    THROW 52052, N'Migration 018 must be applied before Full-Text provisioning.', 1;

/* Reject an incompatible pre-existing index before creating any catalog. */
DECLARE @PreflightObjectId INT =
    OBJECT_ID(N'dbo.FundingPlatform_FundingOpportunities');
IF EXISTS
   (SELECT 1 FROM sys.fulltext_catalogs
    WHERE name = N'FundingPlatform_FundingSearchCatalog'
      AND (is_accent_sensitivity_on <> 0
           OR principal_id <> DATABASE_PRINCIPAL_ID(N'dbo')))
    THROW 52055, N'The existing Full-Text catalog has incompatible ownership or accent sensitivity.', 1;
IF EXISTS
   (SELECT 1
    FROM sys.fulltext_indexes AS indexes
    INNER JOIN sys.fulltext_catalogs AS catalogs
        ON catalogs.fulltext_catalog_id = indexes.fulltext_catalog_id
    WHERE catalogs.name = N'FundingPlatform_FundingSearchCatalog'
      AND indexes.object_id <> @PreflightObjectId)
    THROW 52056, N'The dedicated Full-Text catalog is already used by another table.', 1;
IF EXISTS
   (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = @PreflightObjectId)
   AND
   (
       NOT EXISTS
       (SELECT 1
        FROM sys.fulltext_indexes AS indexes
        INNER JOIN sys.fulltext_catalogs AS catalogs
            ON catalogs.fulltext_catalog_id = indexes.fulltext_catalog_id
        INNER JOIN sys.indexes AS keys
            ON keys.object_id = indexes.object_id
           AND keys.index_id = indexes.unique_index_id
        WHERE indexes.object_id = @PreflightObjectId
          AND catalogs.name = N'FundingPlatform_FundingSearchCatalog'
          AND catalogs.is_accent_sensitivity_on = 0
          AND keys.name = N'FundingPlatform_PK_FundingOpportunities'
          AND indexes.change_tracking_state_desc = N'AUTO'
          AND indexes.stoplist_id = 0
          AND indexes.property_list_id IS NULL
          AND indexes.is_enabled = 1)
       OR (SELECT COUNT_BIG(1)
           FROM sys.fulltext_index_columns AS indexedColumns
           INNER JOIN sys.columns AS columns
               ON columns.object_id = indexedColumns.object_id
              AND columns.column_id = indexedColumns.column_id
           WHERE indexedColumns.object_id = @PreflightObjectId
             AND columns.name IN
                 (N'Title', N'Description', N'Summary', N'SponsorName',
                  N'EligibilityDescription', N'Requirements')
             AND indexedColumns.language_id = 0
             AND indexedColumns.statistical_semantics = 0) <> 6
       OR EXISTS
          (SELECT 1
           FROM sys.fulltext_index_columns AS indexedColumns
           INNER JOIN sys.columns AS columns
               ON columns.object_id = indexedColumns.object_id
              AND columns.column_id = indexedColumns.column_id
           WHERE indexedColumns.object_id = @PreflightObjectId
             AND (columns.name NOT IN
                  (N'Title', N'Description', N'Summary', N'SponsorName',
                   N'EligibilityDescription', N'Requirements')
                  OR indexedColumns.language_id <> 0
                  OR indexedColumns.statistical_semantics <> 0))
   )
    THROW 52053, N'The existing Full-Text index configuration conflicts with FASE 8A.', 1;

IF NOT EXISTS
   (SELECT 1 FROM sys.fulltext_catalogs
    WHERE name = N'FundingPlatform_FundingSearchCatalog')
    EXEC sys.sp_executesql
        N'CREATE FULLTEXT CATALOG FundingPlatform_FundingSearchCatalog
          WITH ACCENT_SENSITIVITY = OFF AUTHORIZATION dbo;';
GO

IF NOT EXISTS
   (SELECT 1 FROM sys.fulltext_indexes
    WHERE object_id = OBJECT_ID(N'dbo.FundingPlatform_FundingOpportunities'))
    EXEC sys.sp_executesql N'
        CREATE FULLTEXT INDEX ON dbo.FundingPlatform_FundingOpportunities
        (
            Title LANGUAGE 0,
            Description LANGUAGE 0,
            Summary LANGUAGE 0,
            SponsorName LANGUAGE 0,
            EligibilityDescription LANGUAGE 0,
            Requirements LANGUAGE 0
        )
        KEY INDEX FundingPlatform_PK_FundingOpportunities
        ON FundingPlatform_FundingSearchCatalog
        WITH CHANGE_TRACKING AUTO, STOPLIST = SYSTEM;';
GO

DECLARE @OpportunityObjectId INT =
    OBJECT_ID(N'dbo.FundingPlatform_FundingOpportunities');
DECLARE @ExpectedCatalogId INT =
    (SELECT fulltext_catalog_id FROM sys.fulltext_catalogs
     WHERE name = N'FundingPlatform_FundingSearchCatalog'
       AND is_accent_sensitivity_on = 0
       AND principal_id = DATABASE_PRINCIPAL_ID(N'dbo'));

IF EXISTS
   (SELECT 1 FROM sys.fulltext_indexes
    WHERE fulltext_catalog_id = @ExpectedCatalogId
      AND object_id <> @OpportunityObjectId)
    THROW 52056, N'The dedicated Full-Text catalog is already used by another table.', 1;

IF NOT EXISTS
   (SELECT 1 FROM sys.fulltext_indexes
    WHERE object_id = @OpportunityObjectId
      AND fulltext_catalog_id = @ExpectedCatalogId
      AND unique_index_id =
          (SELECT index_id FROM sys.indexes
           WHERE object_id = @OpportunityObjectId
             AND name = N'FundingPlatform_PK_FundingOpportunities')
      AND change_tracking_state_desc = N'AUTO'
      AND stoplist_id = 0
      AND property_list_id IS NULL
      AND is_enabled = 1)
    THROW 52053, N'The existing Full-Text index configuration conflicts with FASE 8A.', 1;

IF (SELECT COUNT_BIG(1)
    FROM sys.fulltext_index_columns AS indexedColumns
    INNER JOIN sys.columns AS columns
        ON columns.object_id = indexedColumns.object_id
       AND columns.column_id = indexedColumns.column_id
    WHERE indexedColumns.object_id = @OpportunityObjectId
      AND columns.name IN
          (N'Title', N'Description', N'Summary', N'SponsorName',
           N'EligibilityDescription', N'Requirements')
      AND indexedColumns.language_id = 0
      AND indexedColumns.statistical_semantics = 0) <> 6
   OR EXISTS
      (SELECT 1
       FROM sys.fulltext_index_columns AS indexedColumns
       INNER JOIN sys.columns AS columns
           ON columns.object_id = indexedColumns.object_id
          AND columns.column_id = indexedColumns.column_id
       WHERE indexedColumns.object_id = @OpportunityObjectId
         AND (columns.name NOT IN
              (N'Title', N'Description', N'Summary', N'SponsorName',
               N'EligibilityDescription', N'Requirements')
              OR indexedColumns.language_id <> 0
              OR indexedColumns.statistical_semantics <> 0))
    THROW 52054, N'The existing Full-Text indexed columns conflict with FASE 8A.', 1;

SELECT CASE
           WHEN OBJECTPROPERTYEX
                (@OpportunityObjectId, 'TableFulltextFailCount') <> 0
             OR OBJECTPROPERTYEX
                (@OpportunityObjectId, 'TableFullTextPopulateStatus') = 6
           THEN N'population-failed'
           WHEN FULLTEXTCATALOGPROPERTY
                (N'FundingPlatform_FundingSearchCatalog', 'PopulateStatus') = 0
            AND OBJECTPROPERTYEX
                (@OpportunityObjectId, 'TableFullTextPopulateStatus') = 0
            AND EXISTS
                (SELECT 1 FROM sys.fulltext_indexes
                 WHERE object_id = @OpportunityObjectId
                   AND has_crawl_completed = 1)
           THEN N'ready'
           ELSE N'populating'
       END AS FullTextState;
GO
