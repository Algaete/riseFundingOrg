/*
FundingPlatform - align imported source identity with the editable external reference.

The Grants.gov adapter historically stored ExternalId=ReferenceNumber while hashing a
different provider identifier into SourceItemKeyHash. The editorial update hashes the
external reference, so the same row could be mistaken for a duplicate. Future imports
use ReferenceNumber for both values; this forward-only repair aligns existing rows.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Candidates TABLE
(
    LinkId BIGINT NOT NULL PRIMARY KEY,
    FundingSourceId INT NOT NULL,
    ExpectedSourceItemKeyHash BINARY(32) NOT NULL
);

INSERT INTO @Candidates (LinkId, FundingSourceId, ExpectedSourceItemKeyHash)
SELECT links.Id,
       links.FundingSourceId,
       HASHBYTES(
           'SHA2_256',
           CONVERT(
               VARBINARY(MAX),
               CONVERT(
                   VARCHAR(MAX),
                   links.ExternalId COLLATE Latin1_General_100_BIN2_UTF8)))
FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
WHERE NULLIF(LTRIM(RTRIM(links.ExternalId)), N'') IS NOT NULL;

IF EXISTS
(
    SELECT 1
    FROM @Candidates AS candidates
    INNER JOIN dbo.FundingPlatform_FundingOpportunitySourceLinks AS otherLinks
        ON otherLinks.FundingSourceId = candidates.FundingSourceId
       AND otherLinks.SourceItemKeyHash = candidates.ExpectedSourceItemKeyHash
       AND otherLinks.Id <> candidates.LinkId
)
    THROW 52301, N'Cannot align source identities because a real source-key conflict exists.', 1;

UPDATE links
SET SourceItemKeyHash = candidates.ExpectedSourceItemKeyHash
FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
INNER JOIN @Candidates AS candidates ON candidates.LinkId = links.Id
WHERE links.SourceItemKeyHash <> candidates.ExpectedSourceItemKeyHash;
