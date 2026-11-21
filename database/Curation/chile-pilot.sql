-- Executed transactionally by FundingPlatform.PilotCatalog. No schema changes.
-- New records only. Never overwrite subsequent editorial work on rerun.
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
IF ISJSON(@CatalogJson) <> 1 THROW 56900,N'Invalid curated catalog.',1;
DECLARE @Now DATETIME2(3)=SYSUTCDATETIME();
DECLARE @Reviewed DATETIME2(3)='2026-11-15T00:00:00';
DECLARE @Funds TABLE(PublicId UNIQUEIDENTIFIER,Slug NVARCHAR(180),Title NVARCHAR(350),Funder NVARCHAR(300),Url NVARCHAR(2048),ApplicationUrl NVARCHAR(2048),Summary NVARCHAR(2000),Description NVARCHAR(MAX),Eligibility NVARCHAR(MAX),Requirements NVARCHAR(MAX),Amount DECIMAL(19,4),OpenDate DATE,CloseDate DATE,CloseUtc DATETIME2(3),Zone NVARCHAR(100),GlobalScope BIT,Categories NVARCHAR(MAX));
INSERT @Funds SELECT * FROM OPENJSON(@CatalogJson,'$.funds') WITH(PublicId UNIQUEIDENTIFIER '$.id',Slug NVARCHAR(180) '$.slug',Title NVARCHAR(350) '$.title',Funder NVARCHAR(300) '$.funder',Url NVARCHAR(2048) '$.url',ApplicationUrl NVARCHAR(2048) '$.application',Summary NVARCHAR(2000) '$.summary',Description NVARCHAR(MAX) '$.description',Eligibility NVARCHAR(MAX) '$.eligibility',Requirements NVARCHAR(MAX) '$.requirements',Amount DECIMAL(19,4) '$.amount',OpenDate DATE '$.opened',CloseDate DATE '$.closed',CloseUtc DATETIME2(3) '$.closeUtc',Zone NVARCHAR(100) '$.zone',GlobalScope BIT '$.globalScope',Categories NVARCHAR(MAX) '$.categories' AS JSON);
IF (SELECT COUNT(*) FROM @Funds)<>3 THROW 56901,N'Expected three reviewed opportunities.',1;
IF EXISTS(SELECT 1 FROM @Funds f JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Slug=f.Slug WHERE o.PublicId<>f.PublicId) THROW 56902,N'Catalog slug collision.',1;
DECLARE @Inserted TABLE(Id BIGINT,PublicId UNIQUEIDENTIFIER);
DECLARE @Id UNIQUEIDENTIFIER,@Slug NVARCHAR(180),@Name NVARCHAR(300),@Url NVARCHAR(2048),@SourceId INT,@FunderId BIGINT;
DECLARE curated CURSOR LOCAL FAST_FORWARD FOR SELECT PublicId,Slug,Funder,Url FROM @Funds;
OPEN curated; FETCH NEXT FROM curated INTO @Id,@Slug,@Name,@Url;
WHILE @@FETCH_STATUS=0
BEGIN
 IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId=@Id)
 BEGIN
  SET @SourceId=NULL; SET @FunderId=NULL;
  SELECT @SourceId=Id FROM dbo.FundingPlatform_FundingSources WHERE Name=@Name AND BaseUrl=@Url AND ProviderType=0 AND ProviderCode IS NULL;
  IF @SourceId IS NULL BEGIN
   INSERT dbo.FundingPlatform_FundingSources(Name,ProviderType,BaseUrl,IsEnabled,ScheduleCron,ConfigurationJson)
   VALUES(@Name,0,@Url,1,NULL,N'{"manualOnly":true,"curation":"chile-pilot-2026-11"}');
   SET @SourceId=SCOPE_IDENTITY();
  END;
  SELECT @FunderId=Id FROM dbo.FundingPlatform_Funders WHERE Slug=@Slug+N'-financiador';
  IF @FunderId IS NULL BEGIN
   INSERT dbo.FundingPlatform_Funders(PublicId,Slug,Name,NormalizedName,WebsiteUrl,PublicationStatus,PublishedAtUtc,ReviewedAtUtc,ContentVersion,IsActive,CreatedAtUtc,UpdatedAtUtc)
   VALUES(NEWID(),@Slug+N'-financiador',@Name,UPPER(@Name),@Url,2,@Now,@Reviewed,1,1,@Now,@Now);
   SET @FunderId=SCOPE_IDENTITY();
  END;
  INSERT dbo.FundingPlatform_FundingOpportunities(PublicId,Slug,Title,Description,Summary,SponsorName,SponsorUrl,ApplicationUrl,Currency,MinAmount,MaxAmount,AmountStatus,OpenDate,CloseDate,CloseAtUtc,DeadlineTimeZoneId,DeadlineType,DeadlinePrecision,GeographicScope,RemoteApplication,EligibilityDescription,Requirements,PublicationStatus,PublishedAtUtc,ReviewedAtUtc,LastVerifiedAtUtc,DataQualityScore,ContentVersion,IsActive)
  OUTPUT inserted.Id,inserted.PublicId INTO @Inserted
  SELECT PublicId,Slug,Title,Description,Summary,Funder,Url,ApplicationUrl,CASE WHEN Amount IS NULL THEN NULL ELSE 'USD' END,NULL,Amount,CASE WHEN Amount IS NULL THEN 0 ELSE 1 END,OpenDate,CloseDate,CloseUtc,Zone,1,CASE WHEN CloseUtc IS NULL THEN 1 ELSE 2 END,CASE WHEN GlobalScope=1 THEN 2 ELSE 1 END,2,Eligibility,Requirements,2,@Now,@Reviewed,@Reviewed,
   85+CASE WHEN Amount IS NULL THEN 0 ELSE 10 END+CASE WHEN GlobalScope=1 THEN 0 ELSE 5 END,1,1
  FROM @Funds WHERE PublicId=@Id;
  DECLARE @OpportunityId BIGINT=(SELECT Id FROM @Inserted WHERE PublicId=@Id);
  INSERT dbo.FundingPlatform_FundingOpportunityCategories(FundingOpportunityId,FundingCategoryId)
  SELECT @OpportunityId,CONVERT(INT,c.value) FROM @Funds f CROSS APPLY OPENJSON(f.Categories)c WHERE f.PublicId=@Id;
  INSERT dbo.FundingPlatform_FundingOpportunityCountries(FundingOpportunityId,CountryId) SELECT @OpportunityId,152 FROM @Funds WHERE PublicId=@Id AND GlobalScope=0;
  INSERT dbo.FundingPlatform_FundingOpportunityFunders(FundingOpportunityId,FunderId,Role,IsActive,CreatedAtUtc,UpdatedAtUtc) VALUES(@OpportunityId,@FunderId,1,1,@Now,@Now);
  INSERT dbo.FundingPlatform_FundingOpportunitySourceLinks(FundingOpportunityId,FundingSourceId,ExternalId,SourceItemKeyHash,SourceUrl,CanonicalUrlHash,FirstSeenAtUtc,LastSeenAtUtc,IsPrimary,IsActive)
  VALUES(@OpportunityId,@SourceId,@Slug,HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),CONVERT(VARCHAR(MAX),@Slug COLLATE Latin1_General_100_BIN2_UTF8))),@Url,dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash(@Url),@Reviewed,@Reviewed,1,1);
  INSERT dbo.FundingPlatform_FundingFieldEvidence(FundingOpportunityId,FieldPath,ValueJson,ExtractionMethod,IsSelected,IsManualLock,CreatedAtUtc)
  SELECT @OpportunityId,v.Path,(SELECT N'known' AS status,v.Value AS value,@Url AS sourceUrl FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),1,1,1,@Reviewed
  FROM @Funds f CROSS APPLY(VALUES(N'/title',f.Title),(N'/description',f.Description),(N'/eligibilityDescription',f.Eligibility),(N'/closeDate',CONVERT(NVARCHAR(MAX),f.CloseDate,23)))v(Path,Value) WHERE f.PublicId=@Id;
  DECLARE @Snapshot NVARCHAR(MAX)=(SELECT f.*,N'chile-pilot-2026-11' AS curation FROM @Funds f WHERE f.PublicId=@Id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  INSERT dbo.FundingPlatform_FundingOpportunityVersions(FundingOpportunityId,ContentVersion,SnapshotJson,ContentHash,CreatedAtUtc) VALUES(@OpportunityId,1,@Snapshot,HASHBYTES('SHA2_256',@Snapshot),@Now);
 END;
 FETCH NEXT FROM curated INTO @Id,@Slug,@Name,@Url;
END;
CLOSE curated; DEALLOCATE curated;
-- Reversible withdrawal of the two EXACT known synthetic records; never delete.
UPDATE dbo.FundingPlatform_FundingOpportunities SET PublicationStatus=4,IsActive=0,UpdatedAtUtc=@Now
WHERE PublicId IN ('70510000-0000-4000-8000-000000000101','70510000-0000-4000-8000-000000000102')
 AND Slug IN (N'test-datos-prueba-socio-union-europea',N'test-datos-prueba-socio-europa-m49') AND Title LIKE N'TEST · DATOS DE PRUEBA · %' AND IsActive=1;
IF (SELECT COUNT(*) FROM @Funds f JOIN dbo.FundingPlatform_FundingOpportunities o ON o.PublicId=f.PublicId JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() ready ON ready.FundingOpportunityId=o.Id)<>3 THROW 56903,N'Curated opportunities failed public readiness.',1;
SELECT (SELECT COUNT(*) FROM @Inserted) AS InsertedCount,3 AS PublicReadyCount;
