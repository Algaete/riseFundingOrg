/* Forward repair for the two opt-in geographic TEST fixtures only.
   The original fixture hashed NVARCHAR (UTF-16); source identity requires UTF-8.
   Never rewrite real opportunities, unknown hashes, content, publication or history.
   Absent fixtures are a no-op; already corrected fixtures are a no-op. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Candidates TABLE(LinkId BIGINT PRIMARY KEY, FundingSourceId INT NOT NULL, ExpectedHash BINARY(32) NOT NULL);
INSERT @Candidates(LinkId,FundingSourceId,ExpectedHash)
SELECT l.Id,l.FundingSourceId,
 HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),CONVERT(VARCHAR(MAX),l.ExternalId COLLATE Latin1_General_100_BIN2_UTF8)))
FROM dbo.FundingPlatform_FundingOpportunitySourceLinks l
JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=l.FundingOpportunityId
JOIN dbo.FundingPlatform_FundingSources s ON s.Id=l.FundingSourceId
JOIN (VALUES
 (CONVERT(UNIQUEIDENTIFIER,'70510000-0000-4000-8000-000000000101'),N'test-datos-prueba-socio-union-europea',N'TEST · DATOS DE PRUEBA · Socio Unión Europea'),
 (CONVERT(UNIQUEIDENTIFIER,'70510000-0000-4000-8000-000000000102'),N'test-datos-prueba-socio-europa-m49',N'TEST · DATOS DE PRUEBA · Socio Europa (ONU M49)')
) f(PublicId,Slug,Title) ON o.PublicId=f.PublicId AND o.Slug=f.Slug AND o.Title=f.Title
WHERE l.ExternalId=f.Slug
 AND s.Name=N'TEST · DATOS DE PRUEBA · Fuente manual geográfica'
 AND s.BaseUrl=N'https://salmon-glacier-0721afc0f.7.azurestaticapps.net/test-data/matching-geografico.html'
 AND s.ProviderType=0 AND s.ProviderCode IS NULL
 AND JSON_VALUE(s.ConfigurationJson,'$.sample')=N'dev-geographic-sample-v1'
 AND JSON_VALUE(s.ConfigurationJson,'$.manualOnly')=N'true'
 AND l.SourceUrl=s.BaseUrl
 AND l.SourceItemKeyHash=HASHBYTES('SHA2_256',l.ExternalId);

IF EXISTS(SELECT 1 FROM @Candidates c
 JOIN dbo.FundingPlatform_FundingOpportunitySourceLinks otherLink
 ON otherLink.FundingSourceId=c.FundingSourceId AND otherLink.SourceItemKeyHash=c.ExpectedHash AND otherLink.Id<>c.LinkId)
 THROW 56090,N'TEST source identity conflicts with an existing source key; no repair applied.',1;

UPDATE l SET SourceItemKeyHash=c.ExpectedHash
FROM dbo.FundingPlatform_FundingOpportunitySourceLinks l JOIN @Candidates c ON c.LinkId=l.Id;
