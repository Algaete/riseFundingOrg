/* Read-only regression: optional TEST fixtures must obey the global source contract. */
SET NOCOUNT ON;
IF EXISTS(
 SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks l
 JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=l.FundingOpportunityId
 WHERE o.PublicId IN ('70510000-0000-4000-8000-000000000101','70510000-0000-4000-8000-000000000102')
 AND NULLIF(LTRIM(RTRIM(l.ExternalId)),N'') IS NOT NULL
 AND l.SourceItemKeyHash<>HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),CONVERT(VARCHAR(MAX),l.ExternalId COLLATE Latin1_General_100_BIN2_UTF8)))
) THROW 56091,N'TEST source identity must use UTF-8, just like real imported identities.',1;
