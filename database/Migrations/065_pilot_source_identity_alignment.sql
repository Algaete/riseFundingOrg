/* Forward repair of the three exact November pilot source references.
   The original one-off publisher used UTF-16 rather than the UTF-8 source contract.
   Preserve editorial content, versions, publication status, evidence and history.
   Absent/corrected rows are no-ops; unexpected identities and collisions fail closed. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @Targets TABLE(PublicId UNIQUEIDENTIFIER,Slug NVARCHAR(180),SourceName NVARCHAR(300),SourceUrl NVARCHAR(2048));
INSERT @Targets VALUES
 ('c1112026-0000-4000-8000-000000000001',N'japon-apc-chile-2027',N'Embajada del Japón en Chile',N'https://www.cl.emb-japan.go.jp/itpr_es/cooperacion.html'),
 ('c1112026-0000-4000-8000-000000000002',N'pollination-project-daily-grants-2026',N'The Pollination Project',N'https://thepollinationproject.org/apply/'),
 ('c1112026-0000-4000-8000-000000000003',N'awesome-disability-diciembre-2026',N'Awesome Foundation — Disability',N'https://www.awesomefoundation.org/en/chapters/disability');
DECLARE @Candidates TABLE(LinkId BIGINT PRIMARY KEY,FundingSourceId INT,ExpectedHash BINARY(32),ExpectedUrlHash BINARY(32),LegacyHash BINARY(32),LegacyUrlHash BINARY(32));
INSERT @Candidates
SELECT l.Id,l.FundingSourceId,
 HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),CONVERT(VARCHAR(MAX),l.ExternalId COLLATE Latin1_General_100_BIN2_UTF8))),
 dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash(l.SourceUrl),HASHBYTES('SHA2_256',l.ExternalId),HASHBYTES('SHA2_256',l.SourceUrl)
FROM @Targets t
JOIN dbo.FundingPlatform_FundingOpportunities o ON o.PublicId=t.PublicId AND o.Slug=t.Slug
JOIN dbo.FundingPlatform_FundingOpportunitySourceLinks l ON l.FundingOpportunityId=o.Id AND l.ExternalId=t.Slug AND l.SourceUrl=t.SourceUrl
JOIN dbo.FundingPlatform_FundingSources s ON s.Id=l.FundingSourceId AND s.Name=t.SourceName AND s.BaseUrl=t.SourceUrl
WHERE s.ProviderType=0 AND s.ProviderCode IS NULL
 AND JSON_VALUE(s.ConfigurationJson,'$.manualOnly')=N'true'
 AND JSON_VALUE(s.ConfigurationJson,'$.curation')=N'chile-pilot-2026-11';
IF EXISTS(SELECT 1 FROM @Candidates c JOIN dbo.FundingPlatform_FundingOpportunitySourceLinks l ON l.Id=c.LinkId
 WHERE l.SourceItemKeyHash NOT IN(c.ExpectedHash,c.LegacyHash))
 THROW 57050,N'Pilot source identity differs from the known legacy hash; review before repair.',1;
IF EXISTS(SELECT 1 FROM @Candidates c JOIN dbo.FundingPlatform_FundingOpportunitySourceLinks l
 ON l.FundingSourceId=c.FundingSourceId AND l.SourceItemKeyHash=c.ExpectedHash AND l.Id<>c.LinkId)
 THROW 57051,N'Pilot source identity conflicts with another source reference.',1;
UPDATE l SET SourceItemKeyHash=c.ExpectedHash,
 CanonicalUrlHash=CASE WHEN l.CanonicalUrlHash=c.LegacyUrlHash THEN c.ExpectedUrlHash ELSE l.CanonicalUrlHash END
FROM dbo.FundingPlatform_FundingOpportunitySourceLinks l JOIN @Candidates c ON c.LinkId=l.Id
WHERE l.SourceItemKeyHash=c.LegacyHash OR l.CanonicalUrlHash=c.LegacyUrlHash;
