SET NOCOUNT ON;
SET XACT_ABORT ON;

IF EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
    CROSS APPLY
    (
        SELECT HASHBYTES(
            'SHA2_256',
            CONVERT(
                VARBINARY(MAX),
                CONVERT(
                    VARCHAR(MAX),
                    links.ExternalId COLLATE Latin1_General_100_BIN2_UTF8)))
            AS ExpectedSourceItemKeyHash
    ) AS expected
    WHERE NULLIF(LTRIM(RTRIM(links.ExternalId)), N'') IS NOT NULL
      AND links.SourceItemKeyHash <> expected.ExpectedSourceItemKeyHash
)
    THROW 52311, N'An editable external source reference has a mismatched source identity.', 1;

IF EXISTS
(
    SELECT links.FundingSourceId, links.SourceItemKeyHash
    FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
    GROUP BY links.FundingSourceId, links.SourceItemKeyHash
    HAVING COUNT_BIG(*) > 1
)
    THROW 52312, N'Duplicate source identities remain after alignment.', 1;
