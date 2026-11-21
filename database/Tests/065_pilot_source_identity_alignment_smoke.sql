/* Read-only regression for the exact pilot identities; fixtures are optional. */
SET NOCOUNT ON;
IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks l
 JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=l.FundingOpportunityId
 WHERE o.PublicId IN('c1112026-0000-4000-8000-000000000001','c1112026-0000-4000-8000-000000000002','c1112026-0000-4000-8000-000000000003')
 AND NULLIF(LTRIM(RTRIM(l.ExternalId)),N'') IS NOT NULL
 AND l.SourceItemKeyHash<>HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),CONVERT(VARCHAR(MAX),l.ExternalId COLLATE Latin1_General_100_BIN2_UTF8))))
 THROW 57052,N'Pilot source references do not satisfy the UTF-8 identity contract.',1;
