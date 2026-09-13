/* Explicit, opt-in dev sample. NOT a migration. Executed in the CLI's transaction.
   Stable IDs, exact owner checks, no account creation/auth changes, no notifications.
   @Mode: preview/apply/verify/disable. @OwnerEmail is provided at runtime, never committed. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() <> N'risefunding-dev' OR @@TRANCOUNT = 0
    THROW 55980, N'Dev sample requires the exact dev database and an outer transaction.', 1;
IF @Mode NOT IN (N'preview', N'apply', N'verify', N'disable')
    THROW 55980, N'Invalid dev sample operation.', 1;
IF OBJECT_ID(N'dbo.FundingPlatform_ifn_PartnerGeographyCountries', N'IF') IS NULL
    THROW 55980, N'Apply migration 051 before preparing this sample.', 1;
DECLARE @UserId BIGINT, @Actor UNIQUEIDENTIFIER, @Now DATETIME2(3) = SYSUTCDATETIME();
SELECT @UserId = Id, @Actor = PublicId FROM dbo.FundingPlatform_Users
WHERE NormalizedEmail = UPPER(LTRIM(RTRIM(@OwnerEmail))) AND Status = 2 AND EmailConfirmed = 1;
IF @UserId IS NULL THROW 55980, N'The requested confirmed active owner does not exist; no account is created.', 1;
DECLARE @LockedActor BIGINT;
EXEC dbo.FundingPlatform_usp_AdminActor_Lock @Actor, @LockedActor OUTPUT;

DECLARE @Prefix NVARCHAR(50) = N'TEST · DATOS DE PRUEBA · ',
    @Notice NVARCHAR(1000) = N'DATOS DE PRUEBA / TEST. Registro ficticio para revisar matching geográfico en desarrollo. No representa una organización real, no ofrece financiamiento y no admite postulaciones ni contactos.',
    @Url NVARCHAR(2048) = N'https://salmon-glacier-0721afc0f.7.azurestaticapps.net/test-data/matching-geografico.html',
    @SourceName NVARCHAR(150) = N'TEST · DATOS DE PRUEBA · Fuente manual geográfica',
    @Project UNIQUEIDENTIFIER = '70510000-0000-4000-8000-000000000002',
    @Funder UNIQUEIDENTIFIER = '70510000-0000-4000-8000-000000000003';
DECLARE @Orgs TABLE(PublicId UNIQUEIDENTIFIER PRIMARY KEY, CountryId SMALLINT, Label NVARCHAR(100), IsPartner BIT, ExtraCategory BIT);
INSERT @Orgs VALUES
 ('70510000-0000-4000-8000-000000000001',152,N'Organización Chile',0,1),
 ('70510000-0000-4000-8000-000000000011',250,N'Aliado Francia',1,0),
 ('70510000-0000-4000-8000-000000000012',724,N'Aliado España',1,0),
 ('70510000-0000-4000-8000-000000000013',276,N'Aliado Alemania',1,0),
 ('70510000-0000-4000-8000-000000000014',826,N'Aliado Reino Unido (solo Europa)',1,1),
 ('70510000-0000-4000-8000-000000000015',840,N'Aliado Estados Unidos (control excluido)',1,1);
DECLARE @Funds TABLE(PublicId UNIQUEIDENTIFIER PRIMARY KEY, Slug NVARCHAR(180), Label NVARCHAR(100), RegionCode NVARCHAR(20));
INSERT @Funds VALUES
 ('70510000-0000-4000-8000-000000000101',N'test-datos-prueba-socio-union-europea',N'Socio Unión Europea',N'EU'),
 ('70510000-0000-4000-8000-000000000102',N'test-datos-prueba-socio-europa-m49',N'Socio Europa (ONU M49)',N'M49-150');

IF EXISTS(SELECT 1 FROM @Orgs f JOIN dbo.FundingPlatform_Organizations o ON o.PublicId=f.PublicId)
 OR EXISTS(SELECT 1 FROM @Funds f JOIN dbo.FundingPlatform_FundingOpportunities o ON o.PublicId=f.PublicId)
 OR EXISTS(SELECT 1 FROM dbo.FundingPlatform_Projects WHERE PublicId=@Project OR Slug=N'test-datos-prueba-educacion-clima-chile')
 OR EXISTS(SELECT 1 FROM dbo.FundingPlatform_Funders WHERE PublicId=@Funder OR Slug=N'test-datos-prueba-financiador-geografico')
 OR EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingSources WHERE Name=@SourceName)
BEGIN
    /* Refuse partial/colliding/renamed datasets. Never reset a user's edits on rerun. */
    IF (SELECT COUNT(*) FROM @Orgs f JOIN dbo.FundingPlatform_Organizations o ON o.PublicId=f.PublicId
        JOIN dbo.FundingPlatform_OrganizationUsers m ON m.OrganizationId=o.Id AND m.UserId=@UserId AND m.MembershipStatus=1
        WHERE o.CreatedByUserId=@UserId AND o.Name=@Prefix+f.Label) <> 6
      OR (SELECT COUNT(*) FROM @Funds f JOIN dbo.FundingPlatform_FundingOpportunities o ON o.PublicId=f.PublicId
          WHERE o.Title=@Prefix+f.Label AND o.Slug=f.Slug) <> 2
      OR NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_Projects p JOIN dbo.FundingPlatform_Organizations o ON o.Id=p.OrganizationId
          WHERE p.PublicId=@Project AND p.CreatedByUserId=@UserId AND o.PublicId='70510000-0000-4000-8000-000000000001'
            AND p.Title=@Prefix+N'Educación y clima en Chile' AND p.Slug=N'test-datos-prueba-educacion-clima-chile')
      OR NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_Funders WHERE PublicId=@Funder
          AND Name=@Prefix+N'Financiador ficticio' AND Slug=N'test-datos-prueba-financiador-geografico')
      OR NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingSources WHERE Name=@SourceName AND BaseUrl=@Url AND ProviderCode IS NULL)
        THROW 55981, N'Partial, renamed or foreign sample detected. No records have been overwritten.', 1;
    IF @Mode = N'disable'
    BEGIN
        UPDATE p SET IsDiscoverable=0, AllowRequests=0, UpdatedAtUtc=@Now
        FROM dbo.FundingPlatform_OrganizationNetworkingPreferences p
        JOIN dbo.FundingPlatform_Organizations o ON o.Id=p.OrganizationId JOIN @Orgs f ON f.PublicId=o.PublicId;
        UPDATE o SET IsActive=0, UpdatedAtUtc=@Now FROM dbo.FundingPlatform_Organizations o JOIN @Orgs f ON f.PublicId=o.PublicId;
        UPDATE dbo.FundingPlatform_Projects SET IsActive=0, UpdatedAtUtc=@Now WHERE PublicId=@Project;
        UPDATE o SET IsActive=0, UpdatedAtUtc=@Now FROM dbo.FundingPlatform_FundingOpportunities o JOIN @Funds f ON f.PublicId=o.PublicId;
        UPDATE dbo.FundingPlatform_Funders SET IsActive=0, UpdatedAtUtc=@Now WHERE PublicId=@Funder;
        UPDATE dbo.FundingPlatform_FundingSources SET IsEnabled=0, UpdatedAtUtc=@Now WHERE Name=@SourceName AND BaseUrl=@Url;
    END;
    RETURN;
END;
IF @Mode IN (N'verify',N'disable') THROW 55981, N'No complete dev sample exists.', 1;
IF (SELECT COUNT(*) FROM dbo.FundingPlatform_Countries c JOIN @Orgs f ON f.CountryId=c.Id WHERE c.IsActive=1) <> 6
 OR (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingCategories WHERE Id IN (1,6) AND IsActive=1) <> 2
    THROW 55980, N'Required active catalogs are missing.', 1;

/* Synthetic profile dates sort behind existing memberships, preserving the user's
   usual default organization. Version and membership audit times remain the real @Now.
   The private Chile fixture sorts first only if the owner has no existing organizations. */
DECLARE @SampleProfileAt DATETIME2(3)=(SELECT DATEADD(SECOND,-2,COALESCE(MIN(o.UpdatedAtUtc),@Now))
 FROM dbo.FundingPlatform_Organizations o JOIN dbo.FundingPlatform_OrganizationUsers m ON m.OrganizationId=o.Id
 WHERE m.UserId=@UserId AND m.MembershipStatus=1 AND o.IsActive=1);
INSERT dbo.FundingPlatform_Organizations(PublicId,CreatedByUserId,Name,Description,HomeCountryId,OrganizationTypeId,ProfileStatus,ProfileCompleteness,IsActive,CreatedAtUtc,UpdatedAtUtc)
SELECT PublicId,@UserId,@Prefix+Label,@Notice,CountryId,2,2,100,1,
 DATEADD(MILLISECOND,CASE WHEN IsPartner=0 THEN 1 ELSE 0 END,@SampleProfileAt),
 DATEADD(MILLISECOND,CASE WHEN IsPartner=0 THEN 1 ELSE 0 END,@SampleProfileAt) FROM @Orgs;
INSERT dbo.FundingPlatform_OrganizationUsers(OrganizationId,UserId,Role,MembershipStatus,JoinedAtUtc)
SELECT o.Id,@UserId,1,1,@Now FROM dbo.FundingPlatform_Organizations o JOIN @Orgs f ON f.PublicId=o.PublicId;
INSERT dbo.FundingPlatform_OrganizationNetworkingPreferences(OrganizationId,IsDiscoverable,AllowRequests,UpdatedByUserId,CreatedAtUtc,UpdatedAtUtc)
SELECT o.Id,f.IsPartner,0,@UserId,@Now,@Now FROM dbo.FundingPlatform_Organizations o JOIN @Orgs f ON f.PublicId=o.PublicId;
INSERT dbo.FundingPlatform_OrganizationCountries(OrganizationId,CountryId)
SELECT o.Id,f.CountryId FROM dbo.FundingPlatform_Organizations o JOIN @Orgs f ON f.PublicId=o.PublicId;
INSERT dbo.FundingPlatform_OrganizationCategories(OrganizationId,FundingCategoryId)
SELECT o.Id,c.Id FROM dbo.FundingPlatform_Organizations o JOIN @Orgs f ON f.PublicId=o.PublicId
CROSS JOIN (VALUES(1),(6)) c(Id) WHERE c.Id=1 OR f.ExtraCategory=1;
INSERT dbo.FundingPlatform_OrganizationProfileVersions(OrganizationId,ProfileVersion,SnapshotJson,ContentHash,CreatedByUserId,CreatedAtUtc)
SELECT o.Id,1,j.Json,HASHBYTES('SHA2_256',j.Json),@UserId,@Now FROM dbo.FundingPlatform_Organizations o JOIN @Orgs f ON f.PublicId=o.PublicId
CROSS APPLY(SELECT o.PublicId AS publicId,o.Name AS name,o.Description AS description,o.HomeCountryId AS homeCountryId,
 o.OrganizationTypeId AS organizationTypeId,JSON_QUERY(CASE WHEN f.ExtraCategory=1 THEN N'[1,6]' ELSE N'[1]' END) AS fundingCategoryIds,
 N'dev-geographic-sample-v1' AS sample FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) j(Json);

DECLARE @OrganizationId BIGINT=(SELECT Id FROM dbo.FundingPlatform_Organizations WHERE PublicId='70510000-0000-4000-8000-000000000001');
INSERT dbo.FundingPlatform_Projects(PublicId,OrganizationId,CreatedByUserId,Slug,Title,Summary,Description,ProjectStatus,PublicationStatus,
 BudgetTotal,ConfirmedFunding,Currency,ProjectStage,IsActive,CreatedAtUtc,UpdatedAtUtc)
VALUES(@Project,@OrganizationId,@UserId,N'test-datos-prueba-educacion-clima-chile',@Prefix+N'Educación y clima en Chile',@Notice,@Notice,
 0,0,100000,20000,'USD',0,1,@Now,@Now);
DECLARE @ProjectId BIGINT=SCOPE_IDENTITY();
INSERT dbo.FundingPlatform_ProjectCountries(ProjectId,CountryId) VALUES(@ProjectId,152);
INSERT dbo.FundingPlatform_ProjectCategories(ProjectId,FundingCategoryId) VALUES(@ProjectId,1),(@ProjectId,6);
INSERT dbo.FundingPlatform_ProjectBeneficiaryTypes(ProjectId,BeneficiaryTypeId) VALUES(@ProjectId,1);
INSERT dbo.FundingPlatform_ProjectProjectTypes(ProjectId,ProjectTypeId) VALUES(@ProjectId,1);
INSERT dbo.FundingPlatform_ProjectSustainableDevelopmentGoals(ProjectId,SustainableDevelopmentGoalId) VALUES(@ProjectId,4),(@ProjectId,13);
DECLARE @ProjectJson NVARCHAR(MAX)=(SELECT @Project AS publicId,@Prefix+N'Educación y clima en Chile' AS title,@Notice AS summary,
 @Notice AS description,0 AS status,0 AS projectStage,100000 AS budgetTotal,20000 AS confirmedFunding,'USD' AS currency,
 JSON_QUERY(N'[152]') AS countryIds,JSON_QUERY(N'[1,6]') AS fundingCategoryIds,JSON_QUERY(N'[1]') AS beneficiaryTypeIds,
 JSON_QUERY(N'[1]') AS projectTypeIds,JSON_QUERY(N'[4,13]') AS sustainableDevelopmentGoalIds,N'dev-geographic-sample-v1' AS sample
 FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
INSERT dbo.FundingPlatform_ProjectVersions(ProjectId,ProjectVersion,SnapshotJson,ContentHash,CreatedByUserId,CreatedAtUtc)
VALUES(@ProjectId,1,@ProjectJson,HASHBYTES('SHA2_256',@ProjectJson),@UserId,@Now);

INSERT dbo.FundingPlatform_FundingSources(Name,ProviderType,BaseUrl,IsEnabled,ScheduleCron,ConfigurationJson)
VALUES(@SourceName,0,@Url,1,NULL,N'{"sample":"dev-geographic-sample-v1","manualOnly":true}');
DECLARE @SourceId INT=SCOPE_IDENTITY();
INSERT dbo.FundingPlatform_Funders(PublicId,Slug,Name,NormalizedName,Description,WebsiteUrl,PublicationStatus,PublishedAtUtc,ReviewedAtUtc,ContentVersion,IsActive,CreatedAtUtc,UpdatedAtUtc)
VALUES(@Funder,N'test-datos-prueba-financiador-geografico',@Prefix+N'Financiador ficticio',UPPER(@Prefix+N'Financiador ficticio'),@Notice,@Url,2,@Now,@Now,1,1,@Now,@Now);
DECLARE @FunderId BIGINT=SCOPE_IDENTITY();
INSERT dbo.FundingPlatform_FundingOpportunities(PublicId,Slug,Title,Description,Summary,SponsorName,SponsorUrl,ApplicationUrl,IssuerCountryId,
 Currency,MinAmount,MaxAmount,AmountStatus,DeadlineType,DeadlinePrecision,GeographicScope,RemoteApplication,
 MinimumOperatingYears,RequiresLegalEntity,RequiresPriorExperience,EligibilityDescription,
 PublicationStatus,PublishedAtUtc,ReviewedAtUtc,LastVerifiedAtUtc,DataQualityScore,ContentVersion,IsActive)
SELECT PublicId,Slug,@Prefix+Label,@Notice,@Notice,@Prefix+N'Financiador ficticio',@Url,@Url,152,
 'USD',50000,100000,1,2,0,2,1,0,0,0,@Notice,2,@Now,@Now,@Now,100,1,1 FROM @Funds;
INSERT dbo.FundingPlatform_FundingOpportunityCategories(FundingOpportunityId,FundingCategoryId)
SELECT o.Id,c.Id FROM dbo.FundingPlatform_FundingOpportunities o JOIN @Funds f ON f.PublicId=o.PublicId CROSS JOIN (VALUES(1),(6)) c(Id);
INSERT dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes(FundingOpportunityId,BeneficiaryTypeId)
SELECT o.Id,1 FROM dbo.FundingPlatform_FundingOpportunities o JOIN @Funds f ON f.PublicId=o.PublicId;
INSERT dbo.FundingPlatform_FundingOpportunityProjectTypes(FundingOpportunityId,ProjectTypeId)
SELECT o.Id,1 FROM dbo.FundingPlatform_FundingOpportunities o JOIN @Funds f ON f.PublicId=o.PublicId;
INSERT dbo.FundingPlatform_FundingOpportunityOrganizationTypes(FundingOpportunityId,OrganizationTypeId,EligibilityMode)
SELECT o.Id,2,1 FROM dbo.FundingPlatform_FundingOpportunities o JOIN @Funds f ON f.PublicId=o.PublicId;
INSERT dbo.FundingPlatform_FundingOpportunityFunders(FundingOpportunityId,FunderId,Role,IsActive,CreatedAtUtc,UpdatedAtUtc)
SELECT o.Id,@FunderId,1,1,@Now,@Now FROM dbo.FundingPlatform_FundingOpportunities o JOIN @Funds f ON f.PublicId=o.PublicId;
INSERT dbo.FundingPlatform_FundingOpportunitySourceLinks(FundingOpportunityId,FundingSourceId,ExternalId,SourceItemKeyHash,SourceUrl,CanonicalUrlHash,FirstSeenAtUtc,LastSeenAtUtc,IsPrimary,IsActive)
SELECT o.Id,@SourceId,f.Slug,HASHBYTES('SHA2_256',f.Slug),@Url,HASHBYTES('SHA2_256',@Url),@Now,@Now,1,1
FROM dbo.FundingPlatform_FundingOpportunities o JOIN @Funds f ON f.PublicId=o.PublicId;
INSERT dbo.FundingPlatform_FundingFieldEvidence(FundingOpportunityId,FieldPath,ValueJson,ExtractionMethod,IsSelected,IsManualLock,CreatedAtUtc)
SELECT o.Id,p.Path,CASE WHEN p.Path=N'/closeDate' THEN N'{"status":"unknown","value":null}'
 ELSE N'{"status":"known","value":"DATOS DE PRUEBA / TEST; sin validez real"}' END,1,1,0,@Now
FROM dbo.FundingPlatform_FundingOpportunities o JOIN @Funds f ON f.PublicId=o.PublicId
CROSS JOIN (VALUES(N'/title'),(N'/description'),(N'/eligibilityDescription'),(N'/closeDate')) p(Path);
INSERT dbo.FundingPlatform_FundingOpportunityVersions(FundingOpportunityId,ContentVersion,SnapshotJson,ContentHash,CreatedByUserId,CreatedAtUtc)
SELECT o.Id,1,j.Json,HASHBYTES('SHA2_256',j.Json),@UserId,@Now
FROM dbo.FundingPlatform_FundingOpportunities o JOIN @Funds f ON f.PublicId=o.PublicId
CROSS APPLY(SELECT o.PublicId AS publicId,o.Title AS title,o.Summary AS summary,o.Description AS description,o.Currency AS currency,
 o.MinAmount AS minAmount,o.MaxAmount AS maxAmount,o.DeadlineType AS deadlineType,o.GeographicScope AS geographicScope,
 JSON_QUERY(N'[1,6]') AS categoryIds,N'dev-geographic-sample-v1' AS sample FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) j(Json);

DECLARE @Opportunity UNIQUEIDENTIFIER,@Region NVARCHAR(20),@Data NVARCHAR(MAX),@Key BINARY(32),@Hash BINARY(32);
DECLARE sample_funds CURSOR LOCAL FAST_FORWARD FOR SELECT PublicId,RegionCode FROM @Funds;
OPEN sample_funds;
FETCH NEXT FROM sample_funds INTO @Opportunity,@Region;
WHILE @@FETCH_STATUS=0
BEGIN
 SET @Data=(SELECT 2 AS funderKind,CONVERT(BIT,0) AS requiresConsortium,CONVERT(BIT,1) AS requiresInternationalPartner,@Url AS evidenceUrl,
 JSON_QUERY(N'{"scope":2,"countryIds":[],"regionCodes":["'+@Region+N'"],"catalogVersion":"partner-geography-2026-09-12"}') AS partnerGeography
 FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 SET @Key=HASHBYTES('SHA2_256',N'dev-geographic-sample-v1-'+@Region);
 SET @Hash=HASHBYTES('SHA2_256',@Data);
 EXEC dbo.FundingPlatform_usp_FundingDiscovery_Review @Actor,@Opportunity,1,@Data,NULL,@Key,@Hash;
 FETCH NEXT FROM sample_funds INTO @Opportunity,@Region;
END;
CLOSE sample_funds;
DEALLOCATE sample_funds;
