-- Append-only editorial correction: explicit nationwide coverage for two reviewed records.
-- No source, funder, profile, application content or prior version is changed.
SET NOCOUNT ON;
IF @@TRANCOUNT=0 THROW 57410,N'Regional review requires a transaction.',1;
IF ISJSON(@CatalogJson)<>1 OR JSON_VALUE(@CatalogJson,'$.batchId')<>N'chile-catalog-regions-2026-11-23'
 THROW 57411,N'Unexpected regional batch.',1;
DECLARE @Now DATETIME2(3)=SYSUTCDATETIME(),@Batch NVARCHAR(100)=N'chile-catalog-regions-2026-11-23';
DECLARE @Key BINARY(32)=HASHBYTES('SHA2_256',@Batch),@Hash BINARY(32)=HASHBYTES('SHA2_256',@CatalogJson);
DECLARE @Expected TABLE(PublicId UNIQUEIDENTIFIER PRIMARY KEY,Slug NVARCHAR(180),SourceUrl NVARCHAR(2048));
INSERT @Expected VALUES
 ('c6662026-0000-4000-8000-000000000001',N'fae-establecimientos-rbd-2027',N'https://www.fondosdecultura.cl/fondos/fondart-nacional/ventanilla-abierta/fae-2027-establecimientos-educacionales-rbd/'),
 ('c6662026-0000-4000-8000-000000000003',N'mapfre-innovacion-social-decima-edicion',N'https://www.fundacionmapfre.org/premios-ayudas/premios/premios-fundacion-mapfre-innovacion-social/');
DECLARE @Input TABLE(PublicId UNIQUEIDENTIFIER PRIMARY KEY,Slug NVARCHAR(180),ExpectedVersion INT,SourceUrl NVARCHAR(2048),Data NVARCHAR(MAX));
INSERT @Input SELECT CONVERT(UNIQUEIDENTIFIER,JSON_VALUE(value,'$.id')),JSON_VALUE(value,'$.slug'),
 CONVERT(INT,JSON_VALUE(value,'$.expectedVersion')),JSON_VALUE(value,'$.sourceUrl'),value FROM OPENJSON(@CatalogJson,'$.funds');
IF (SELECT COUNT(*) FROM @Input)<>2 OR EXISTS(SELECT PublicId,Slug,SourceUrl FROM @Input EXCEPT SELECT * FROM @Expected)
 OR EXISTS(SELECT 1 FROM @Input WHERE ExpectedVersion<>1 OR ExpectedVersion IS NULL)
 THROW 57412,N'Regional batch differs from reviewed targets.',1;
DECLARE @Applied INT=(SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents ev WITH(UPDLOCK,HOLDLOCK)
 JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=ev.FundingOpportunityId JOIN @Expected e ON e.PublicId=o.PublicId
 WHERE ev.IdempotencyKeyHash=@Key);
IF @Applied>0
BEGIN
 IF @Applied<>2 OR EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents ev
  JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=ev.FundingOpportunityId JOIN @Expected e ON e.PublicId=o.PublicId
  WHERE ev.IdempotencyKeyHash=@Key AND ev.RequestHash<>@Hash)
  THROW 57413,N'Partial or changed regional review detected.',1;
 SELECT 0 AS InsertedCount,0 AS UpdatedCount,2 AS AlreadyAppliedCount;
 RETURN;
END;
IF (SELECT COUNT(*) FROM dbo.FundingPlatform_Regions WHERE CountryId=152 AND IsActive=1 AND Id BETWEEN 1 AND 16)<>16
 THROW 57414,N'Expected active Chile region catalog is missing.',1;
IF EXISTS(SELECT 1 FROM @Input i WHERE (SELECT COUNT(*) FROM OPENJSON(i.Data,'$.regionIds'))<>16
 OR EXISTS(SELECT CONVERT(INT,value) FROM OPENJSON(i.Data,'$.regionIds') EXCEPT SELECT Id FROM dbo.FundingPlatform_Regions WHERE CountryId=152 AND Id BETWEEN 1 AND 16)
 OR (SELECT COUNT(DISTINCT CONVERT(INT,value)) FROM OPENJSON(i.Data,'$.regionIds'))<>16)
 THROW 57415,N'Coverage must contain the sixteen exact Chile regions.',1;
IF EXISTS(SELECT 1 FROM @Input i LEFT JOIN dbo.FundingPlatform_FundingOpportunities o WITH(UPDLOCK,HOLDLOCK) ON o.PublicId=i.PublicId
 WHERE o.Id IS NULL OR o.Slug<>i.Slug OR o.ContentVersion<>1 OR o.PublicationStatus<>2 OR o.IsActive<>1 OR o.GeographicScope<>1
 OR NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries c WHERE c.FundingOpportunityId=o.Id AND c.CountryId=152)
 OR EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries c WHERE c.FundingOpportunityId=o.Id AND c.CountryId<>152)
 OR EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions r WHERE r.FundingOpportunityId=o.Id)
 OR NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityVersions v WHERE v.FundingOpportunityId=o.Id AND v.ContentVersion=1))
 THROW 57416,N'Catalog version or previous geographic coverage changed.',1;
INSERT dbo.FundingPlatform_FundingOpportunityRegions(FundingOpportunityId,RegionId)
 SELECT o.Id,CONVERT(INT,r.value) FROM @Input i JOIN dbo.FundingPlatform_FundingOpportunities o ON o.PublicId=i.PublicId CROSS APPLY OPENJSON(i.Data,'$.regionIds') r;
UPDATE o SET ContentVersion=2,ReviewedAtUtc=@Now,LastVerifiedAtUtc=@Now,UpdatedAtUtc=@Now
 FROM dbo.FundingPlatform_FundingOpportunities o JOIN @Input i ON i.PublicId=o.PublicId;
UPDATE e SET IsSelected=0 FROM dbo.FundingPlatform_FundingFieldEvidence e
 JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=e.FundingOpportunityId JOIN @Input i ON i.PublicId=o.PublicId WHERE e.FieldPath=N'/regionIds';
INSERT dbo.FundingPlatform_FundingFieldEvidence(FundingOpportunityId,FieldPath,ValueJson,ExtractionMethod,IsSelected,IsManualLock,CreatedAtUtc)
 SELECT o.Id,N'/regionIds',(SELECT N'known' AS status,JSON_QUERY(i.Data,'$.regionIds') AS value,i.SourceUrl AS sourceUrl,
  JSON_VALUE(i.Data,'$.reason') AS reviewNote,@Batch AS curation FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),1,1,1,@Now
 FROM @Input i JOIN dbo.FundingPlatform_FundingOpportunities o ON o.PublicId=i.PublicId;
INSERT dbo.FundingPlatform_FundingOpportunityVersions(FundingOpportunityId,ContentVersion,SnapshotJson,ContentHash,CreatedAtUtc)
 SELECT o.Id,2,s.SnapshotJson,HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),CONVERT(VARCHAR(MAX),s.SnapshotJson COLLATE Latin1_General_100_BIN2_UTF8))),@Now
 FROM @Input i JOIN dbo.FundingPlatform_FundingOpportunities o ON o.PublicId=i.PublicId
 JOIN dbo.FundingPlatform_FundingOpportunityVersions v ON v.FundingOpportunityId=o.Id AND v.ContentVersion=1
 CROSS APPLY(SELECT JSON_MODIFY(JSON_MODIFY(JSON_MODIFY(JSON_MODIFY(JSON_MODIFY(v.SnapshotJson,'$.curation',@Batch),
  '$.opportunity',JSON_QUERY((SELECT o.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER))),
  '$.regionIds',JSON_QUERY((SELECT RegionId FROM dbo.FundingPlatform_FundingOpportunityRegions WHERE FundingOpportunityId=o.Id ORDER BY RegionId FOR JSON PATH))),
  '$.editorialReview.regionIds',JSON_QUERY(i.Data,'$.regionIds')),'$.regionalReview',JSON_QUERY(i.Data)) AS SnapshotJson) s;
INSERT dbo.FundingPlatform_FundingOpportunityEditorialEvents(EventId,FundingOpportunityId,ContentVersion,FromStatus,ToStatus,ActionCode,ActorUserId,Reason,IdempotencyKeyHash,RequestHash,ResultRowVersion,ResultPublishedAtUtc,ResultReviewedAtUtc,CreatedAtUtc)
 SELECT NEWID(),o.Id,2,2,2,N'CuratedBatch',NULL,@Batch,@Key,@Hash,o.RowVersion,o.PublishedAtUtc,o.ReviewedAtUtc,@Now
 FROM @Input i JOIN dbo.FundingPlatform_FundingOpportunities o ON o.PublicId=i.PublicId;
IF (SELECT COUNT(*) FROM @Input i JOIN dbo.FundingPlatform_FundingOpportunities o ON o.PublicId=i.PublicId
 JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() p ON p.FundingOpportunityId=o.Id)<>2
 THROW 57417,N'Regional correction failed publication readiness.',1;
SELECT 0 AS InsertedCount,2 AS UpdatedCount,0 AS AlreadyAppliedCount;
