-- Fourteen new reviewed opportunities. Existing catalog, profiles and history remain unchanged.
-- Does not read user profiles or enable automatic harvesting.
-- Must run in one caller-owned transaction. Exact IDs and versions fail closed.
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
IF @@TRANCOUNT=0 THROW 56910,N'Catalog requires a transaction.',1;
IF ISJSON(@CatalogJson)<>1 OR JSON_VALUE(@CatalogJson,'$.batchId')<>N'chile-catalog-scale-2026-11-22'
 THROW 56911,N'Unexpected catalog batch.',1;
DECLARE @Now DATETIME2(3)=SYSUTCDATETIME(),@Batch NVARCHAR(100)=N'chile-catalog-scale-2026-11-22';
DECLARE @Key BINARY(32)=HASHBYTES('SHA2_256',@Batch),@Hash BINARY(32)=HASHBYTES('SHA2_256',@CatalogJson);
DECLARE @Expected TABLE(PublicId UNIQUEIDENTIFIER PRIMARY KEY,Slug NVARCHAR(180),ExpectedVersion INT,IsCorrection BIT);
INSERT @Expected VALUES
 ('c5552026-0000-4000-8000-000000000001',N'gef-comunidades-chile-2026',0,0),
 ('c5552026-0000-4000-8000-000000000002',N'gilead-salud-latinoamerica',0,0),
 ('c5552026-0000-4000-8000-000000000003',N'cisco-global-impact-consulta-inicial',0,0),
 ('c5552026-0000-4000-8000-000000000004',N'itf-seed-2027',0,0),
 ('c5552026-0000-4000-8000-000000000005',N'sophie-danforth-conservacion-2027',0,0),
 ('c5552026-0000-4000-8000-000000000006',N'aliph-patrimonio-emergencia',0,0),
 ('c5552026-0000-4000-8000-000000000007',N'pulitzer-reportajes-globales',0,0),
 ('c5552026-0000-4000-8000-000000000008',N'nbc-conservacion-aves-neotropicales',0,0),
 ('c5552026-0000-4000-8000-000000000009',N'wikimedia-rapid-fund-2027',0,0),
 ('c5552026-0000-4000-8000-000000000010',N'ea-funds-bienestar-animal',0,0),
 ('c5552026-0000-4000-8000-000000000011',N'ea-funds-infraestructura-comunidad',0,0),
 ('c5552026-0000-4000-8000-000000000012',N'oak-special-interest-consulta',0,0),
 ('c5552026-0000-4000-8000-000000000013',N'reporters-respond-emergencia',0,0),
 ('c5552026-0000-4000-8000-000000000014',N'pfizer-investigacion-atm-avi-2026',0,0);
DECLARE @Input TABLE(PublicId UNIQUEIDENTIFIER PRIMARY KEY,Slug NVARCHAR(180),ExpectedVersion INT,Data NVARCHAR(MAX),IsCorrection BIT);
INSERT @Input
 SELECT CONVERT(UNIQUEIDENTIFIER,JSON_VALUE(value,'$.id')),JSON_VALUE(value,'$.slug'),CONVERT(INT,JSON_VALUE(value,'$.expectedVersion')),value,0 FROM OPENJSON(@CatalogJson,'$.funds');
IF (SELECT COUNT(*) FROM @Input)<>14 OR EXISTS(SELECT * FROM (SELECT PublicId,Slug,ExpectedVersion,IsCorrection FROM @Input EXCEPT SELECT * FROM @Expected) bad)
 THROW 56912,N'Catalog differs from exact reviewed targets.',1;
DECLARE @Applied INT=(SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents ev WITH(UPDLOCK,HOLDLOCK)
 JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=ev.FundingOpportunityId JOIN @Expected e ON e.PublicId=o.PublicId
 WHERE ev.IdempotencyKeyHash=@Key);
IF @Applied>0
BEGIN
 IF @Applied<>14 OR EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents ev JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=ev.FundingOpportunityId JOIN @Expected e ON e.PublicId=o.PublicId WHERE ev.IdempotencyKeyHash=@Key AND ev.RequestHash<>@Hash)
  THROW 56913,N'Partial or changed catalog batch detected.',1;
 SELECT 0 AS InsertedCount,0 AS UpdatedCount,14 AS AlreadyAppliedCount;
 RETURN;
END;
IF EXISTS(SELECT 1 FROM @Expected e LEFT JOIN dbo.FundingPlatform_FundingOpportunities o WITH(UPDLOCK,HOLDLOCK) ON o.PublicId=e.PublicId
 WHERE (e.ExpectedVersion=0 AND o.Id IS NOT NULL) OR (e.ExpectedVersion>0 AND (o.Id IS NULL OR o.ContentVersion<>e.ExpectedVersion OR o.Slug<>e.Slug OR o.PublicationStatus<>2 OR o.IsActive<>1)))
 THROW 56914,N'Editorial version changed or prerequisite missing; no overwrite allowed.',1;
IF EXISTS(SELECT 1 FROM @Expected e JOIN dbo.FundingPlatform_FundingOpportunities o WITH(UPDLOCK,HOLDLOCK) ON o.Slug=e.Slug WHERE o.PublicId<>e.PublicId)
 THROW 56915,N'Slug collision.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_MatchingProfiles WHERE Version=3 AND EngineVersion=N'deterministic-sql-v3' AND Status=2 AND IsActive=1)
 THROW 57030,N'Eligibility schema must be released before catalog activation.',1;
IF EXISTS(SELECT 1 FROM @Input WHERE JSON_QUERY(Data,'$.eligibilityPolicy') IS NULL OR dbo.FundingPlatform_fn_EligibilityPolicyValid(JSON_QUERY(Data,'$.eligibilityPolicy'))<>1)
 THROW 57031,N'Every reviewed target needs a valid eligibility policy.',1;

DECLARE @PublicId UNIQUEIDENTIFIER,@Slug NVARCHAR(180),@Version INT,@Data NVARCHAR(MAX),@Correction BIT;
DECLARE @Id BIGINT,@SourceId INT,@FunderId BIGINT,@Name NVARCHAR(300),@Url NVARCHAR(2048),@FunderUrl NVARCHAR(2048),@FunderSlug NVARCHAR(180),@Snapshot NVARCHAR(MAX),@SourceName NVARCHAR(200);
DECLARE @Changed TABLE(Id BIGINT PRIMARY KEY,WasNew BIT,PublicId UNIQUEIDENTIFIER,Data NVARCHAR(MAX));
DECLARE batch CURSOR LOCAL FAST_FORWARD FOR SELECT PublicId,Slug,ExpectedVersion,Data,IsCorrection FROM @Input ORDER BY PublicId;
OPEN batch; FETCH NEXT FROM batch INTO @PublicId,@Slug,@Version,@Data,@Correction;
WHILE @@FETCH_STATUS=0
BEGIN
 SET @Id=NULL;SET @SourceId=NULL;SET @FunderId=NULL;
 SET @Name=JSON_VALUE(@Data,'$.funder');
 SET @Url=JSON_VALUE(@Data,'$.url');
 SET @FunderUrl=COALESCE(JSON_VALUE(@Data,'$.funderUrl'),@Url);
 SET @FunderSlug=@Slug+N'-financiador';
 SET @SourceName=JSON_VALUE(@Data,'$.title');
 SELECT @Id=Id FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId=@PublicId;
 IF @Version=0
 BEGIN
  IF (SELECT COUNT(*) FROM dbo.FundingPlatform_Funders WHERE Name=@Name AND WebsiteUrl=@FunderUrl AND PublicationStatus=2 AND IsActive=1)>1
   THROW 56917,N'Ambiguous existing funder identity.',1;
  SELECT @FunderId=Id FROM dbo.FundingPlatform_Funders WHERE Name=@Name AND WebsiteUrl=@FunderUrl AND PublicationStatus=2 AND IsActive=1;
  -- Reuse the existing reviewed MMA funder by its exact prior opportunity.
  IF @PublicId='c5552026-0000-4000-8000-000000000001'
  BEGIN
   IF (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunityFunders l
    JOIN dbo.FundingPlatform_Funders f ON f.Id=l.FunderId
    JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=l.FundingOpportunityId
    WHERE o.PublicId='c2222026-0000-4000-8000-000000000002' AND l.IsActive=1 AND l.Role=1
      AND f.Name=N'Ministerio del Medio Ambiente' AND f.IsActive=1 AND f.PublicationStatus=2)<>1
    THROW 57110,N'Expected reviewed MMA funder is missing or ambiguous.',1;
   SELECT @FunderId=l.FunderId FROM dbo.FundingPlatform_FundingOpportunityFunders l
    JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=l.FundingOpportunityId
    WHERE o.PublicId='c2222026-0000-4000-8000-000000000002' AND l.IsActive=1 AND l.Role=1;
  END;
  IF @FunderId IS NULL
  BEGIN
  IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_Funders WHERE Slug=@FunderSlug)
   THROW 56917,N'New funder slug already exists; review identity before retrying.',1;
  INSERT dbo.FundingPlatform_Funders(PublicId,Slug,Name,NormalizedName,WebsiteUrl,PublicationStatus,PublishedAtUtc,ReviewedAtUtc,ContentVersion,IsActive,CreatedAtUtc,UpdatedAtUtc)
  VALUES(NEWID(),@FunderSlug,@Name,UPPER(@Name),@FunderUrl,2,@Now,@Now,1,1,@Now,@Now);
  SET @FunderId=SCOPE_IDENTITY();
  SET @Snapshot=(SELECT @Name AS name,@FunderUrl AS websiteUrl,@Batch AS curation FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  INSERT dbo.FundingPlatform_FunderVersions(FunderId,ContentVersion,SnapshotJson,ContentHash,CreatedAtUtc)
  VALUES(@FunderId,1,@Snapshot,HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),CONVERT(VARCHAR(MAX),@Snapshot COLLATE Latin1_General_100_BIN2_UTF8))),@Now);
  END;
 END;
 IF @Version=0
 BEGIN
  IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingSources WHERE Name=@SourceName)
   THROW 56918,N'Source name already exists; review source identity before retrying.',1;
  INSERT dbo.FundingPlatform_FundingSources(Name,ProviderType,BaseUrl,IsEnabled,ScheduleCron,ConfigurationJson)
  VALUES(@SourceName,0,@Url,1,NULL,N'{"manualOnly":true,"curation":"chile-catalog-scale-2026-11-22"}');
  SET @SourceId=SCOPE_IDENTITY();
  INSERT dbo.FundingPlatform_FundingOpportunities(PublicId,Slug,Title,SponsorName,PublicationStatus,PublishedAtUtc,ReviewedAtUtc,ContentVersion,IsActive)
  VALUES(@PublicId,@Slug,JSON_VALUE(@Data,'$.title'),@Name,2,@Now,@Now,1,1);
  SET @Id=SCOPE_IDENTITY();
  INSERT dbo.FundingPlatform_FundingOpportunityFunders(FundingOpportunityId,FunderId,Role,IsActive,CreatedAtUtc,UpdatedAtUtc)
  VALUES(@Id,@FunderId,1,1,@Now,@Now);
  INSERT dbo.FundingPlatform_FundingOpportunitySourceLinks(FundingOpportunityId,FundingSourceId,ExternalId,SourceItemKeyHash,SourceUrl,CanonicalUrlHash,FirstSeenAtUtc,LastSeenAtUtc,IsPrimary,IsActive)
  VALUES(@Id,@SourceId,@Slug,HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),CONVERT(VARCHAR(MAX),@Slug COLLATE Latin1_General_100_BIN2_UTF8))),@Url,dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash(@Url),@Now,@Now,1,1);
 END;
 BEGIN
  UPDATE o SET
   Title=f.Title,Summary=f.Summary,Description=f.Description,EligibilityDescription=f.Eligibility,Requirements=f.Requirements,
   Restrictions=f.Restrictions,SponsorName=@Name,SponsorUrl=@Url,ApplicationUrl=f.ApplicationUrl,FundingTypeId=CONVERT(SMALLINT,JSON_VALUE(@Data,'$.fundingTypeId')),
   EligibilityPolicyJson=JSON_QUERY(@Data,'$.eligibilityPolicy'),
   Currency=f.Currency,MinAmount=f.MinAmount,MaxAmount=f.MaxAmount,AmountStatus=f.AmountStatus,
   OpenDate=f.OpenDate,CloseDate=f.CloseDate,CloseAtUtc=f.CloseUtc,DeadlineTimeZoneId=f.Zone,DeadlineType=f.DeadlineType,DeadlinePrecision=f.DeadlinePrecision,
   GeographicScope=CASE WHEN f.GlobalScope=1 THEN 2 ELSE 1 END,RemoteApplication=2,
   MinimumOperatingYears=f.MinimumOperatingYears,RequiresLegalEntity=f.RequiresLegalEntity,RequiresPriorExperience=f.RequiresPriorExperience,RequiresCofunding=f.RequiresCofunding,
   ContentVersion=CASE WHEN @Version=0 THEN 1 ELSE @Version+1 END,ReviewedAtUtc=@Now,LastVerifiedAtUtc=CASE WHEN @Version=0 OR JSON_VALUE(@Data,'$.sourceVerifiedDate')=N'2026-11-22' THEN @Now ELSE LastVerifiedAtUtc END,UpdatedAtUtc=@Now,
   DataQualityScore=85+CASE WHEN f.AmountStatus=1 THEN 10 ELSE 0 END+CASE WHEN f.GlobalScope=0 THEN 5 ELSE 0 END
  FROM dbo.FundingPlatform_FundingOpportunities o CROSS APPLY OPENJSON(@Data) WITH(
   Title NVARCHAR(350) '$.title',Summary NVARCHAR(2000) '$.summary',Description NVARCHAR(MAX) '$.description',Eligibility NVARCHAR(MAX) '$.eligibility',Requirements NVARCHAR(MAX) '$.requirements',Restrictions NVARCHAR(MAX) '$.restrictions',ApplicationUrl NVARCHAR(2048) '$.application',
   Currency CHAR(3) '$.currency',MinAmount DECIMAL(19,4) '$.minAmount',MaxAmount DECIMAL(19,4) '$.maxAmount',AmountStatus TINYINT '$.amountStatus',
   OpenDate DATE '$.opened',CloseDate DATE '$.closed',CloseUtc DATETIME2(3) '$.closeUtc',Zone NVARCHAR(100) '$.zone',DeadlineType TINYINT '$.deadlineType',DeadlinePrecision TINYINT '$.deadlinePrecision',GlobalScope BIT '$.globalScope',
   MinimumOperatingYears SMALLINT '$.minimumOperatingYears',RequiresLegalEntity BIT '$.requiresLegalEntity',RequiresPriorExperience BIT '$.requiresPriorExperience',RequiresCofunding BIT '$.requiresCofunding') f WHERE o.Id=@Id;
  DELETE FROM dbo.FundingPlatform_FundingOpportunityCountries WHERE FundingOpportunityId=@Id;
  INSERT dbo.FundingPlatform_FundingOpportunityCountries(FundingOpportunityId,CountryId) SELECT @Id,CONVERT(INT,value) FROM OPENJSON(@Data,'$.countryIds');
  DELETE FROM dbo.FundingPlatform_FundingOpportunityRegions WHERE FundingOpportunityId=@Id;
  INSERT dbo.FundingPlatform_FundingOpportunityRegions(FundingOpportunityId,RegionId) SELECT @Id,CONVERT(INT,value) FROM OPENJSON(@Data,'$.regionIds');
  DELETE FROM dbo.FundingPlatform_FundingOpportunityCategories WHERE FundingOpportunityId=@Id;
  INSERT dbo.FundingPlatform_FundingOpportunityCategories(FundingOpportunityId,FundingCategoryId) SELECT @Id,CONVERT(INT,value) FROM OPENJSON(@Data,'$.categories');
  DELETE FROM dbo.FundingPlatform_FundingOpportunityOrganizationTypes WHERE FundingOpportunityId=@Id;
  INSERT dbo.FundingPlatform_FundingOpportunityOrganizationTypes(FundingOpportunityId,OrganizationTypeId,EligibilityMode) SELECT @Id,CONVERT(INT,value),1 FROM OPENJSON(@Data,'$.organizationTypes');
  DELETE FROM dbo.FundingPlatform_FundingOpportunityLegalEntityTypes WHERE FundingOpportunityId=@Id;
  INSERT dbo.FundingPlatform_FundingOpportunityLegalEntityTypes(FundingOpportunityId,LegalEntityTypeId,EligibilityMode) SELECT @Id,CONVERT(INT,value),1 FROM OPENJSON(@Data,'$.legalEntityTypes');
  DELETE FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes WHERE FundingOpportunityId=@Id;
  INSERT dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes(FundingOpportunityId,BeneficiaryTypeId) SELECT @Id,CONVERT(INT,value) FROM OPENJSON(@Data,'$.beneficiaries');
  DELETE FROM dbo.FundingPlatform_FundingOpportunityProjectTypes WHERE FundingOpportunityId=@Id;
  INSERT dbo.FundingPlatform_FundingOpportunityProjectTypes(FundingOpportunityId,ProjectTypeId) SELECT @Id,CONVERT(INT,value) FROM OPENJSON(@Data,'$.projectTypes');
  DELETE FROM dbo.FundingPlatform_FundingOpportunityLanguages WHERE FundingOpportunityId=@Id;
  INSERT dbo.FundingPlatform_FundingOpportunityLanguages(FundingOpportunityId,LanguageId,LanguagePurpose) SELECT @Id,CONVERT(SMALLINT,value),2 FROM OPENJSON(@Data,'$.languages');
  -- Preserve earlier evidence; supersede selected values only for fields reviewed here.
  UPDATE dbo.FundingPlatform_FundingFieldEvidence SET IsSelected=0 WHERE FundingOpportunityId=@Id AND FieldPath IN(N'/title',N'/description',N'/eligibilityDescription',N'/closeDate',N'/requiresLegalEntity',N'/minimumOperatingYears',N'/requiresPriorExperience',N'/restrictions');
  INSERT dbo.FundingPlatform_FundingFieldEvidence(FundingOpportunityId,FieldPath,ValueJson,ExtractionMethod,IsSelected,IsManualLock,CreatedAtUtc)
  SELECT @Id,v.Path,(SELECT CASE WHEN v.Value IS NULL THEN N'unknown' ELSE N'known' END AS status,v.Value AS value,@Url AS sourceUrl,JSON_QUERY(@Data,'$.evidence') AS reviewNotes,@Batch AS curation FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),1,1,1,@Now
  FROM dbo.FundingPlatform_FundingOpportunities o CROSS APPLY(VALUES
   (N'/title',CONVERT(NVARCHAR(MAX),o.Title)),(N'/description',o.Description),(N'/eligibilityDescription',o.EligibilityDescription),(N'/closeDate',CONVERT(NVARCHAR(MAX),o.CloseDate,23)),
   (N'/requiresLegalEntity',CONVERT(NVARCHAR(MAX),o.RequiresLegalEntity)),(N'/minimumOperatingYears',CONVERT(NVARCHAR(MAX),o.MinimumOperatingYears)),(N'/requiresPriorExperience',CONVERT(NVARCHAR(MAX),o.RequiresPriorExperience)),(N'/restrictions',o.Restrictions))v(Path,Value) WHERE o.Id=@Id;
 END;
 -- An additional append-only review record includes every source and unresolved field.
 INSERT dbo.FundingPlatform_FundingFieldEvidence(FundingOpportunityId,FieldPath,ValueJson,ExtractionMethod,IsSelected,IsManualLock,CreatedAtUtc)
 VALUES(@Id,N'/curation/chile-2026-11-22',(SELECT N'known' AS status,JSON_QUERY(@Data) AS value,@Batch AS curation FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),1,1,1,@Now);
 INSERT @Changed VALUES(@Id,CASE WHEN @Version=0 THEN 1 ELSE 0 END,@PublicId,@Data);
 FETCH NEXT FROM batch INTO @PublicId,@Slug,@Version,@Data,@Correction;
END;
CLOSE batch; DEALLOCATE batch;

-- Snapshot the actual resulting row and all matching inputs, including the reviewed eligibility policy.
INSERT dbo.FundingPlatform_FundingOpportunityVersions(FundingOpportunityId,ContentVersion,SnapshotJson,ContentHash,CreatedAtUtc)
SELECT o.Id,o.ContentVersion,s.SnapshotJson,HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),CONVERT(VARCHAR(MAX),s.SnapshotJson COLLATE Latin1_General_100_BIN2_UTF8))),@Now
FROM @Changed c JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=c.Id
CROSS APPLY(SELECT (SELECT @Batch AS curation,JSON_QUERY(o.EligibilityPolicyJson) AS eligibilityPolicy,JSON_QUERY((SELECT o.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)) AS opportunity,
 JSON_QUERY((SELECT CountryId FROM dbo.FundingPlatform_FundingOpportunityCountries WHERE FundingOpportunityId=o.Id ORDER BY CountryId FOR JSON PATH)) AS countryIds,
 JSON_QUERY((SELECT RegionId FROM dbo.FundingPlatform_FundingOpportunityRegions WHERE FundingOpportunityId=o.Id ORDER BY RegionId FOR JSON PATH)) AS regionIds,
 JSON_QUERY((SELECT FundingCategoryId FROM dbo.FundingPlatform_FundingOpportunityCategories WHERE FundingOpportunityId=o.Id ORDER BY FundingCategoryId FOR JSON PATH)) AS categories,
 JSON_QUERY((SELECT OrganizationTypeId,EligibilityMode FROM dbo.FundingPlatform_FundingOpportunityOrganizationTypes WHERE FundingOpportunityId=o.Id ORDER BY OrganizationTypeId FOR JSON PATH)) AS organizationTypes,
 JSON_QUERY((SELECT LegalEntityTypeId,EligibilityMode FROM dbo.FundingPlatform_FundingOpportunityLegalEntityTypes WHERE FundingOpportunityId=o.Id ORDER BY LegalEntityTypeId FOR JSON PATH)) AS legalEntityTypes,
 JSON_QUERY((SELECT BeneficiaryTypeId FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes WHERE FundingOpportunityId=o.Id ORDER BY BeneficiaryTypeId FOR JSON PATH)) AS beneficiaries,
 JSON_QUERY((SELECT ProjectTypeId FROM dbo.FundingPlatform_FundingOpportunityProjectTypes WHERE FundingOpportunityId=o.Id ORDER BY ProjectTypeId FOR JSON PATH)) AS projectTypes,
 JSON_QUERY((SELECT f.PublicId,l.Role FROM dbo.FundingPlatform_FundingOpportunityFunders l JOIN dbo.FundingPlatform_Funders f ON f.Id=l.FunderId WHERE l.FundingOpportunityId=o.Id AND l.IsActive=1 ORDER BY l.Role,f.PublicId FOR JSON PATH)) AS funders,
 JSON_QUERY(c.Data) AS editorialReview FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) AS SnapshotJson) s;
INSERT dbo.FundingPlatform_FundingOpportunityEditorialEvents(EventId,FundingOpportunityId,ContentVersion,FromStatus,ToStatus,ActionCode,ActorUserId,Reason,IdempotencyKeyHash,RequestHash,ResultRowVersion,ResultPublishedAtUtc,ResultReviewedAtUtc,CreatedAtUtc)
SELECT NEWID(),o.Id,o.ContentVersion,CASE WHEN c.WasNew=1 THEN 0 ELSE 2 END,o.PublicationStatus,N'CuratedBatch',NULL,@Batch,@Key,@Hash,o.RowVersion,o.PublishedAtUtc,o.ReviewedAtUtc,@Now FROM @Changed c JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id=c.Id;
IF (SELECT COUNT(*) FROM @Changed c JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() p ON p.FundingOpportunityId=c.Id)<>14
 THROW 56919,N'Edited opportunities failed publication readiness; roll back.',1;
SELECT SUM(CONVERT(INT,WasNew)) AS InsertedCount,SUM(CASE WHEN WasNew=0 THEN 1 ELSE 0 END) AS UpdatedCount,0 AS AlreadyAppliedCount FROM @Changed;
