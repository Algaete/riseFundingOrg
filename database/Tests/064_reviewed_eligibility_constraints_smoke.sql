/* Real SQL acceptance: v3 limits, regional restrictions, review gaps, replay and immutable v2 history. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke064;

BEGIN TRY
    UPDATE dbo.FundingPlatform_MatchingProfiles SET IsActive=0 WHERE IsActive=1;
    UPDATE dbo.FundingPlatform_MatchingProfiles SET IsActive=1 WHERE EngineVersion=N'deterministic-sql-v2';
    DECLARE @Suffix NVARCHAR(32) =
        REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N'');
    DECLARE @RunNowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @CloseAtUtc DATETIME2(3) = DATEADD(MINUTE, 5, @RunNowUtc);
    DECLARE @OrganizationTypeId SMALLINT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_OrganizationTypes
         WHERE IsActive = 1 ORDER BY Id);
    DECLARE @SourceId INT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_FundingSources
         WHERE IsEnabled = 1 ORDER BY Id);
    DECLARE @OtherCategoryId INT =
        (SELECT Id FROM dbo.FundingPlatform_FundingCategories
         WHERE Id = 1 AND IsActive = 1);
    DECLARE @OtherBeneficiaryId INT =
        (SELECT Id FROM dbo.FundingPlatform_BeneficiaryTypes
         WHERE Id = 1 AND IsActive = 1);
    DECLARE @OtherProjectTypeId INT =
        (SELECT Id FROM dbo.FundingPlatform_ProjectTypes
         WHERE Id = 1 AND IsActive = 1);
    IF @OrganizationTypeId IS NULL OR @SourceId IS NULL
       OR @OtherCategoryId IS NULL OR @OtherBeneficiaryId IS NULL
       OR @OtherProjectTypeId IS NULL
        THROW 55223, N'Catalogs required by the OTHER neutrality fixture are unavailable.', 1;

    DECLARE @OwnerPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @OwnerEmail NVARCHAR(320) = N'smoke064-' + @Suffix + N'@example.invalid';
    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@OwnerPublicId, @OwnerEmail, UPPER(@OwnerEmail), N'Smoke 064 owner',
         N'not-a-credential', N'smoke064', 1, 0, 2, N'es-CL');
    DECLARE @OwnerId BIGINT = SCOPE_IDENTITY();

    DECLARE @OrganizationPublicId UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.FundingPlatform_Organizations
        (PublicId, CreatedByUserId, Name, HomeCountryId, OrganizationTypeId,
         PreviousFundingExperience, ProfileStatus, ProfileCompleteness,
         ProfileVersion, IsActive)
    VALUES
        (@OrganizationPublicId, @OwnerId, N'Smoke 064 organization ' + @Suffix,
         152, @OrganizationTypeId, 2, 2, 90, 1, 1);
    DECLARE @OrganizationId BIGINT = SCOPE_IDENTITY();
    INSERT INTO dbo.FundingPlatform_OrganizationUsers
        (OrganizationId, UserId, Role, MembershipStatus, JoinedAtUtc)
    VALUES (@OrganizationId, @OwnerId, 1, 1, @RunNowUtc);
    INSERT INTO dbo.FundingPlatform_OrganizationProfileVersions
        (OrganizationId, ProfileVersion, SnapshotJson, ContentHash,
         CreatedByUserId, CreatedAtUtc)
    VALUES
        (@OrganizationId, 1, N'{"schema":"smoke064-organization"}',
         HASHBYTES('SHA2_256', N'smoke064-organization-' + @Suffix),
         @OwnerId, @RunNowUtc);

    DECLARE @ProjectPublicId UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.FundingPlatform_Projects
        (PublicId, OrganizationId, CreatedByUserId, Slug, Title, Summary, Description,
         ProjectStatus, PublicationStatus, BudgetTotal, ConfirmedFunding, Currency,
         ProjectVersion, IsActive, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@ProjectPublicId, @OrganizationId, @OwnerId,
         N'smoke064-project-' + @Suffix, N'Smoke 064 project ' + @Suffix,
         N'Summary', N'Description', 2, 0, 1000, 0, 'USD', 1, 1,
         @RunNowUtc, @RunNowUtc);
    DECLARE @ProjectId BIGINT = SCOPE_IDENTITY();
    INSERT INTO dbo.FundingPlatform_ProjectVersions
        (ProjectId, ProjectVersion, SnapshotJson, ContentHash,
         CreatedByUserId, CreatedAtUtc)
    VALUES
        (@ProjectId, 1, N'{"schema":"smoke064-project"}',
         HASHBYTES('SHA2_256', N'smoke064-project-' + @Suffix),
         @OwnerId, @RunNowUtc);
    INSERT INTO dbo.FundingPlatform_ProjectCategories (ProjectId, FundingCategoryId)
        VALUES (@ProjectId, @OtherCategoryId);
    INSERT INTO dbo.FundingPlatform_ProjectBeneficiaryTypes (ProjectId, BeneficiaryTypeId)
        VALUES (@ProjectId, @OtherBeneficiaryId);
    INSERT INTO dbo.FundingPlatform_ProjectProjectTypes (ProjectId, ProjectTypeId)
        VALUES (@ProjectId, @OtherProjectTypeId);

    DECLARE @FunderPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @SponsorName NVARCHAR(300) = N'Smoke 064 funder ' + @Suffix;
    INSERT INTO dbo.FundingPlatform_Funders
        (PublicId, Slug, Name, NormalizedName, WebsiteUrl, PublicationStatus,
         PublishedAtUtc, ReviewedAtUtc, ContentVersion, IsActive,
         CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@FunderPublicId, N'smoke064-funder-' + @Suffix, @SponsorName,
         UPPER(@SponsorName), N'https://smoke064-funder.example.invalid',
         2, @RunNowUtc, @RunNowUtc, 1, 1, @RunNowUtc, @RunNowUtc);
    DECLARE @FunderId BIGINT = SCOPE_IDENTITY();

    DECLARE @OpportunityPublicId UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.FundingPlatform_FundingOpportunities
        (PublicId, Slug, Title, Description, Summary, SponsorName,
         Currency, MinAmount, MaxAmount, AmountStatus, OpenDate,
         CloseDate, CloseAtUtc, DeadlineTimeZoneId, DeadlineType, DeadlinePrecision,
         EligibilityDescription, Requirements, MinimumOperatingYears,
         RequiresLegalEntity, RequiresPriorExperience, GeographicScope,
         RemoteApplication, PublicationStatus, PublishedAtUtc, LastVerifiedAtUtc,
         DataQualityScore, ContentVersion, IsActive, ReviewedAtUtc,
         CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@OpportunityPublicId, N'smoke064-opportunity-' + @Suffix,
         N'Smoke 064 opportunity ' + @Suffix, N'Description', N'Summary', @SponsorName,
         'USD', 100, 1000, 1, NULL, CONVERT(DATE, @CloseAtUtc), @CloseAtUtc,
         N'UTC', 1, 2, N'Controlled criteria', N'Requirements', 0, 0, 0, 2,
         1, 2, @RunNowUtc, @RunNowUtc, 100, 1, 1, @RunNowUtc,
         @RunNowUtc, @RunNowUtc);
    DECLARE @OpportunityId BIGINT = SCOPE_IDENTITY();

    INSERT INTO dbo.FundingPlatform_FundingOpportunityCategories
        (FundingOpportunityId, FundingCategoryId)
        VALUES (@OpportunityId, @OtherCategoryId);
    INSERT INTO dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes
        (FundingOpportunityId, BeneficiaryTypeId)
        VALUES (@OpportunityId, @OtherBeneficiaryId);
    INSERT INTO dbo.FundingPlatform_FundingOpportunityProjectTypes
        (FundingOpportunityId, ProjectTypeId)
        VALUES (@OpportunityId, @OtherProjectTypeId);
    INSERT INTO dbo.FundingPlatform_FundingOpportunityOrganizationTypes
        (FundingOpportunityId, OrganizationTypeId, EligibilityMode)
        VALUES (@OpportunityId, @OrganizationTypeId, 1);
    INSERT INTO dbo.FundingPlatform_FundingOpportunityFunders
        (FundingOpportunityId, FunderId, Role, IsActive, CreatedAtUtc, UpdatedAtUtc)
        VALUES (@OpportunityId, @FunderId, 1, 1, @RunNowUtc, @RunNowUtc);
    INSERT INTO dbo.FundingPlatform_FundingOpportunitySourceLinks
        (FundingOpportunityId, FundingSourceId, ExternalId, SourceItemKeyHash,
         SourceUrl, CanonicalUrlHash, FirstSeenAtUtc, LastSeenAtUtc, IsPrimary, IsActive)
    VALUES
        (@OpportunityId, @SourceId, N'smoke064-' + @Suffix,
         HASHBYTES('SHA2_256', N'smoke064-source-key-' + @Suffix),
         N'https://smoke064-source.example.invalid/' + @Suffix,
         HASHBYTES('SHA2_256', N'smoke064-source-url-' + @Suffix),
         @RunNowUtc, @RunNowUtc, 1, 1);
    INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
        (FundingOpportunityId, FieldPath, ValueJson, ExtractionMethod,
         IsSelected, IsManualLock, CreatedAtUtc)
    SELECT @OpportunityId, fields.FieldPath,
           N'{"status":"known","value":"controlled"}', 1, 1, 0, @RunNowUtc
    FROM (VALUES (N'/title'), (N'/description'),
                 (N'/eligibilityDescription'), (N'/closeDate')) AS fields(FieldPath);
    INSERT INTO dbo.FundingPlatform_FundingOpportunityVersions
        (FundingOpportunityId, ContentVersion, SnapshotJson, ContentHash,
         CreatedByUserId, CreatedAtUtc)
    VALUES
        (@OpportunityId, 1, N'{"schema":"smoke064-opportunity"}',
         HASHBYTES('SHA2_256', N'smoke064-opportunity-' + @Suffix),
         @OwnerId, @RunNowUtc);

    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ifn_FundingOpportunityPublicReady()
        WHERE FundingOpportunityId = @OpportunityId)
        THROW 55224, N'The OTHER neutrality opportunity is not PublicReady.', 1;

    DECLARE @RunRows TABLE
    (
        RunPublicId UNIQUEIDENTIFIER, ProjectPublicId UNIQUEIDENTIFIER,
        ProjectSlug NVARCHAR(180), ProjectTitle NVARCHAR(250), Status TINYINT,
        MatchingProfileCode NVARCHAR(100), MatchingProfileVersion INT,
        EngineVersion NVARCHAR(50), ProjectVersion INT, OrganizationProfileVersion INT,
        CandidateSetFingerprint BINARY(32), CatalogSnapshotAtUtc DATETIME2(3),
        TotalCandidateCount INT, ProcessedCandidateCount INT, CompatibleCount INT,
        IncompatibleCount INT, InsufficientDataCount INT, IsTruncated BIT,
        IsCurrent BIT, WasReplay BIT, StartedAtUtc DATETIME2(3),
        CompletedAtUtc DATETIME2(3), CreatedAtUtc DATETIME2(3)
    );
    DECLARE @IdempotencyKeyHash BINARY(32) =
        HASHBYTES('SHA2_256', N'smoke064-idempotency-' + @Suffix);
    DECLARE @RequestHash BINARY(32) =
        HASHBYTES('SHA2_256', N'smoke064-request-' + @Suffix);
    INSERT INTO @RunRows
    EXEC dbo.FundingPlatform_usp_ProjectMatchingRun_Create
        @UserPublicId = @OwnerPublicId,
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @IdempotencyKeyHash = @IdempotencyKeyHash,
        @RequestHash = @RequestHash,
        @NowUtc = @RunNowUtc;


    DECLARE @LegacyRun UNIQUEIDENTIFIER=(SELECT RunPublicId FROM @RunRows);
    DECLARE @LegacyMatch BIGINT=(SELECT m.Id FROM dbo.FundingPlatform_ProjectFundingMatches m
      JOIN dbo.FundingPlatform_ProjectMatchingRuns r ON r.Id=m.MatchRunId
      WHERE r.PublicId=@LegacyRun AND m.FundingOpportunityId=@OpportunityId);
    IF NOT EXISTS(SELECT 1 FROM @RunRows WHERE EngineVersion=N'deterministic-sql-v2')
      THROW 57020,N'Legacy fixture must start on v2.',1;
    UPDATE dbo.FundingPlatform_MatchingProfiles SET IsActive=0 WHERE IsActive=1;
    UPDATE dbo.FundingPlatform_MatchingProfiles SET IsActive=1 WHERE EngineVersion=N'deterministic-sql-v3';

    DECLARE @Cases TABLE(Id INT IDENTITY PRIMARY KEY,Label NVARCHAR(150),Policy NVARCHAR(MAX),
      Budget DECIMAL(19,4),Currency CHAR(3),AnnualMin DECIMAL(19,4),AnnualMax DECIMAL(19,4),AnnualCurrency CHAR(3),
      CategoryId INT,BeneficiaryId INT,Restricted BIT,ProjectRegion INT,OpportunityRegion INT,
      RuleCode NVARCHAR(100),Outcome TINYINT,Classification TINYINT);
    INSERT @Cases(Label,Policy,Budget,Currency,AnnualMin,AnnualMax,AnnualCurrency,CategoryId,BeneficiaryId,
       Restricted,ProjectRegion,OpportunityRegion,RuleCode,Outcome,Classification) VALUES
     (N'Not reviewed stays unknown',NULL,10000,N'USD',NULL,NULL,NULL,1,1,0,NULL,NULL,N'project_budget_limit',3,2),
     (N'Reviewed no additional cap',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":null,"organizationAnnualBudgetLimit":null,"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',10000,N'USD',NULL,NULL,NULL,1,1,0,NULL,NULL,N'project_budget_limit',0,0),
     (N'Below project cap',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":{"amount":10000,"currency":"USD","inclusive":false},"organizationAnnualBudgetLimit":null,"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',9999,N'USD',NULL,NULL,NULL,1,1,0,NULL,NULL,N'project_budget_limit',0,0),
     (N'Exclusive project equality',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":{"amount":10000,"currency":"USD","inclusive":false},"organizationAnnualBudgetLimit":null,"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',10000,N'USD',NULL,NULL,NULL,1,1,0,NULL,NULL,N'project_budget_limit',2,1),
     (N'Inclusive project equality',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":{"amount":10000,"currency":"USD","inclusive":true},"organizationAnnualBudgetLimit":null,"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',10000,N'USD',NULL,NULL,NULL,1,1,0,NULL,NULL,N'project_budget_limit',0,0),
     (N'Above project cap',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":{"amount":10000,"currency":"USD","inclusive":false},"organizationAnnualBudgetLimit":null,"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',10001,N'USD',NULL,NULL,NULL,1,1,0,NULL,NULL,N'project_budget_limit',2,1),
     (N'Unknown exchange rate',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":{"amount":10000,"currency":"USD","inclusive":false},"organizationAnnualBudgetLimit":null,"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',10000,N'CLP',NULL,NULL,NULL,1,1,0,NULL,NULL,N'project_budget_limit',3,2),
     (N'Annual below cap',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":null,"organizationAnnualBudgetLimit":{"amount":50000,"currency":"USD","inclusive":false},"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',10000,N'USD',10000,49999,N'USD',1,1,0,NULL,NULL,N'organization_budget_limit',0,0),
     (N'Annual exclusive equality',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":null,"organizationAnnualBudgetLimit":{"amount":50000,"currency":"USD","inclusive":false},"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',10000,N'USD',50000,50000,N'USD',1,1,0,NULL,NULL,N'organization_budget_limit',2,1),
     (N'Annual inclusive equality',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":null,"organizationAnnualBudgetLimit":{"amount":50000,"currency":"USD","inclusive":true},"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',10000,N'USD',50000,50000,N'USD',1,1,0,NULL,NULL,N'organization_budget_limit',0,0),
     (N'Annual straddling interval',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":null,"organizationAnnualBudgetLimit":{"amount":50000,"currency":"USD","inclusive":false},"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',10000,N'USD',40000,60000,N'USD',1,1,0,NULL,NULL,N'organization_budget_limit',3,2),
     (N'Annual unknown lower bound',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":null,"organizationAnnualBudgetLimit":{"amount":50000,"currency":"USD","inclusive":false},"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',10000,N'USD',NULL,40000,N'USD',1,1,0,NULL,NULL,N'organization_budget_limit',0,0),
     (N'Annual unknown currency',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":null,"organizationAnnualBudgetLimit":{"amount":50000,"currency":"USD","inclusive":false},"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',10000,N'USD',1000,2000,N'CLP',1,1,0,NULL,NULL,N'organization_budget_limit',3,2),
     (N'Required category matches',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":null,"organizationAnnualBudgetLimit":null,"requiredCategoryIds":[1],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',10000,N'USD',NULL,NULL,NULL,1,1,0,NULL,NULL,N'required_categories',0,0),
     (N'Required category mismatch',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":null,"organizationAnnualBudgetLimit":null,"requiredCategoryIds":[2],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',10000,N'USD',NULL,NULL,NULL,1,1,0,NULL,NULL,N'required_categories',2,1),
     (N'Other category remains unknown',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":null,"organizationAnnualBudgetLimit":null,"requiredCategoryIds":[1],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',10000,N'USD',NULL,NULL,NULL,16,1,0,NULL,NULL,N'required_categories',3,2),
     (N'No category remains unknown',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":null,"organizationAnnualBudgetLimit":null,"requiredCategoryIds":[1],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',10000,N'USD',NULL,NULL,NULL,NULL,1,0,NULL,NULL,N'required_categories',3,2),
     (N'Required beneficiary matches',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":null,"organizationAnnualBudgetLimit":null,"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[1],"manualRequirements":[]}',10000,N'USD',NULL,NULL,NULL,1,1,0,NULL,NULL,N'required_beneficiaries',0,0),
     (N'Required beneficiary mismatch',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":null,"organizationAnnualBudgetLimit":null,"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[2],"manualRequirements":[]}',10000,N'USD',NULL,NULL,NULL,1,1,0,NULL,NULL,N'required_beneficiaries',2,1),
     (N'Other beneficiary unknown',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":null,"organizationAnnualBudgetLimit":null,"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[1],"manualRequirements":[]}',10000,N'USD',NULL,NULL,NULL,1,12,0,NULL,NULL,N'required_beneficiaries',3,2),
     (N'Manual review unresolved',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":null,"organizationAnnualBudgetLimit":null,"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":["Volunteer led"]}',10000,N'USD',NULL,NULL,NULL,1,1,0,NULL,NULL,N'manual_eligibility',3,2),
     (N'Known failure beats unresolved manual',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":{"amount":10000,"currency":"USD","inclusive":false},"organizationAnnualBudgetLimit":null,"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":["Volunteer led"]}',10000,N'USD',NULL,NULL,NULL,1,1,0,NULL,NULL,N'manual_eligibility',3,1),
     (N'Region match',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":null,"organizationAnnualBudgetLimit":null,"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',10000,N'USD',NULL,NULL,NULL,1,1,1,4,4,N'geography',0,0),
     (N'Country cannot override excluded region',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":null,"organizationAnnualBudgetLimit":null,"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',10000,N'USD',NULL,NULL,NULL,1,1,1,7,4,N'geography',2,1),
     (N'Region unknown',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":null,"organizationAnnualBudgetLimit":null,"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',10000,N'USD',NULL,NULL,NULL,1,1,1,NULL,4,N'geography',3,2),
     (N'Whole country unrestricted',N'{"sourceUrl":"https://example.invalid/criteria","projectBudgetLimit":null,"organizationAnnualBudgetLimit":null,"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}',10000,N'USD',NULL,NULL,NULL,1,1,1,7,NULL,N'geography',0,0);

    DECLARE @Case INT=1,@Total INT=(SELECT COUNT(*) FROM @Cases),@Policy NVARCHAR(MAX),@Label NVARCHAR(150),
      @ExpectedOutcome TINYINT,@ExpectedClassification TINYINT,@Rule NVARCHAR(100),@Version INT,@Snapshot NVARCHAR(MAX),
      @RunPublicId UNIQUEIDENTIFIER,@MatchId BIGINT,@Error NVARCHAR(2048),@OriginalHash BINARY(32);
    SELECT @OriginalHash=HASHBYTES('SHA2_256',CONVERT(NVARCHAR(MAX),RuleScore)) FROM dbo.FundingPlatform_ProjectFundingMatches WHERE Id=@LegacyMatch;
    WHILE @Case<=@Total
    BEGIN
      SELECT @Policy=Policy,@Label=Label,@Rule=RuleCode,@ExpectedOutcome=Outcome,@ExpectedClassification=Classification FROM @Cases WHERE Id=@Case;
      SET @Version=@Case+1;
      UPDATE p SET BudgetTotal=c.Budget,Currency=c.Currency,ProjectVersion=@Version
       FROM dbo.FundingPlatform_Projects p CROSS JOIN @Cases c WHERE p.Id=@ProjectId AND c.Id=@Case;
      UPDATE o SET AnnualBudgetMin=c.AnnualMin,AnnualBudgetMax=c.AnnualMax,AnnualBudgetCurrency=c.AnnualCurrency,ProfileVersion=@Version
       FROM dbo.FundingPlatform_Organizations o CROSS JOIN @Cases c WHERE o.Id=@OrganizationId AND c.Id=@Case;
      UPDATE o SET EligibilityPolicyJson=@Policy,ContentVersion=@Version,GeographicScope=CASE WHEN c.Restricted=1 THEN 1 ELSE 2 END
       FROM dbo.FundingPlatform_FundingOpportunities o CROSS JOIN @Cases c WHERE o.Id=@OpportunityId AND c.Id=@Case;
      DELETE dbo.FundingPlatform_ProjectCategories WHERE ProjectId=@ProjectId;
      INSERT dbo.FundingPlatform_ProjectCategories(ProjectId,FundingCategoryId) SELECT @ProjectId,CategoryId FROM @Cases WHERE Id=@Case AND CategoryId IS NOT NULL;
      DELETE dbo.FundingPlatform_ProjectBeneficiaryTypes WHERE ProjectId=@ProjectId;
      INSERT dbo.FundingPlatform_ProjectBeneficiaryTypes(ProjectId,BeneficiaryTypeId) SELECT @ProjectId,BeneficiaryId FROM @Cases WHERE Id=@Case AND BeneficiaryId IS NOT NULL;
      DELETE dbo.FundingPlatform_ProjectCountries WHERE ProjectId=@ProjectId;
      INSERT dbo.FundingPlatform_ProjectCountries(ProjectId,CountryId) VALUES(@ProjectId,152);
      DELETE dbo.FundingPlatform_ProjectRegions WHERE ProjectId=@ProjectId;
      INSERT dbo.FundingPlatform_ProjectRegions(ProjectId,RegionId) SELECT @ProjectId,ProjectRegion FROM @Cases WHERE Id=@Case AND ProjectRegion IS NOT NULL;
      DELETE dbo.FundingPlatform_FundingOpportunityCountries WHERE FundingOpportunityId=@OpportunityId;
      INSERT dbo.FundingPlatform_FundingOpportunityCountries(FundingOpportunityId,CountryId) SELECT @OpportunityId,152 FROM @Cases WHERE Id=@Case AND Restricted=1;
      DELETE dbo.FundingPlatform_FundingOpportunityRegions WHERE FundingOpportunityId=@OpportunityId;
      INSERT dbo.FundingPlatform_FundingOpportunityRegions(FundingOpportunityId,RegionId) SELECT @OpportunityId,OpportunityRegion FROM @Cases WHERE Id=@Case AND OpportunityRegion IS NOT NULL;
      SET @Snapshot=(SELECT @Case AS fixtureCase,JSON_QUERY(@Policy) AS eligibilityPolicy FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
      INSERT dbo.FundingPlatform_FundingOpportunityVersions(FundingOpportunityId,ContentVersion,SnapshotJson,ContentHash,CreatedByUserId,CreatedAtUtc)
       VALUES(@OpportunityId,@Version,@Snapshot,HASHBYTES('SHA2_256',@Snapshot),@OwnerId,@RunNowUtc);
      INSERT dbo.FundingPlatform_ProjectVersions(ProjectId,ProjectVersion,SnapshotJson,ContentHash,CreatedByUserId,CreatedAtUtc)
       VALUES(@ProjectId,@Version,@Snapshot,HASHBYTES('SHA2_256',@Snapshot),@OwnerId,@RunNowUtc);
      INSERT dbo.FundingPlatform_OrganizationProfileVersions(OrganizationId,ProfileVersion,SnapshotJson,ContentHash,CreatedByUserId,CreatedAtUtc)
       VALUES(@OrganizationId,@Version,@Snapshot,HASHBYTES('SHA2_256',@Snapshot),@OwnerId,@RunNowUtc);
      DELETE @RunRows;
      SET @IdempotencyKeyHash=HASHBYTES('SHA2_256',CONCAT(@Suffix,N'case',@Case));
      INSERT @RunRows EXEC dbo.FundingPlatform_usp_ProjectMatchingRun_Create @OwnerPublicId,@OrganizationPublicId,@ProjectPublicId,@IdempotencyKeyHash,@RequestHash,@RunNowUtc;
      SELECT @RunPublicId=RunPublicId FROM @RunRows;
      SELECT @MatchId=m.Id FROM dbo.FundingPlatform_ProjectFundingMatches m JOIN dbo.FundingPlatform_ProjectMatchingRuns r ON r.Id=m.MatchRunId
       WHERE r.PublicId=@RunPublicId AND m.FundingOpportunityId=@OpportunityId;
      IF @MatchId IS NULL OR NOT EXISTS(SELECT 1 FROM @RunRows WHERE EngineVersion=N'deterministic-sql-v3' AND MatchingProfileVersion=3 AND WasReplay=0)
       THROW 57021,N'Expected fresh v3 calculation.',1;
      IF (SELECT COUNT(*) FROM dbo.FundingPlatform_ProjectFundingMatchRuleResults WHERE MatchId=@MatchId)<>14
       THROW 57022,N'Expected fourteen complete rule results.',1;
      IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_ProjectFundingMatchRuleResults rr JOIN dbo.FundingPlatform_MatchingRules r ON r.Id=rr.MatchingRuleId
         WHERE rr.MatchId=@MatchId AND r.Code=@Rule AND rr.Outcome=@ExpectedOutcome AND r.HandlerVersion=N'v3')
      BEGIN SET @Error=N'Unexpected rule outcome: '+@Label; THROW 57023,@Error,1; END;
      IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_ProjectFundingMatches WHERE Id=@MatchId AND Classification=@ExpectedClassification
        AND (@ExpectedClassification<>1 OR CompatibilityScore IS NULL))
      BEGIN SET @Error=N'Unexpected eligibility classification: '+@Label; THROW 57024,@Error,1; END;
      -- Changing only the idempotency key still reuses the same versioned inputs.
      DELETE @RunRows;
      SET @IdempotencyKeyHash=HASHBYTES('SHA2_256',CONCAT(@Suffix,N'replay',@Case));
      INSERT @RunRows EXEC dbo.FundingPlatform_usp_ProjectMatchingRun_Create @OwnerPublicId,@OrganizationPublicId,@ProjectPublicId,@IdempotencyKeyHash,@RequestHash,@RunNowUtc;
      IF NOT EXISTS(SELECT 1 FROM @RunRows WHERE RunPublicId=@RunPublicId AND WasReplay=1)
       THROW 57025,N'Unchanged inputs did not replay the stored result.',1;
      SET @Case+=1;
    END;
    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_ProjectFundingMatches WHERE Id=@LegacyMatch
       AND HASHBYTES('SHA2_256',CONVERT(NVARCHAR(MAX),RuleScore))=@OriginalHash)
       OR (SELECT COUNT(*) FROM dbo.FundingPlatform_ProjectFundingMatchRuleResults WHERE MatchId=@LegacyMatch)<>9
       OR NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_ProjectMatchingRuns WHERE PublicId=@LegacyRun AND EngineVersionSnapshot=N'deterministic-sql-v2')
      THROW 57026,N'New eligibility rules altered immutable legacy results.',1;
    IF dbo.FundingPlatform_fn_EligibilityPolicyValid(N'{}')<>0
       OR dbo.FundingPlatform_fn_EligibilityPolicyValid(N'{"sourceUrl":"http://example.invalid","requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}')<>0
       OR dbo.FundingPlatform_fn_EligibilityPolicyValid(N'{"sourceUrl":"https://example.invalid","requiredCategoryIds":[16],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}')<>0
       OR dbo.FundingPlatform_fn_EligibilityPolicyValid(N'{"sourceUrl":"https://example.invalid","projectBudgetLimit":{"amount":-1,"currency":"USD","inclusive":false},"requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":[]}')<>0
      THROW 57027,N'Invalid editorial policy accepted.',1;
    -- Default .NET JSON escapes non-ASCII; valid long Spanish criteria must still fit.
    DECLARE @EscapedPolicy NVARCHAR(MAX)=N'{"sourceUrl":"https://example.invalid","requiredCategoryIds":[],"requiredBeneficiaryTypeIds":[],"manualRequirements":[';
    DECLARE @Item INT=0;
    WHILE @Item<12 BEGIN
      SET @EscapedPolicy+=CASE WHEN @Item>0 THEN N',' ELSE N'' END+N'"'+REPLICATE(CONVERT(NVARCHAR(MAX),N'\u00f1'),500)+N'"';
      SET @Item+=1;
    END;
    SET @EscapedPolicy+=N']}';
    IF dbo.FundingPlatform_fn_EligibilityPolicyValid(@EscapedPolicy)<>1
      THROW 57028,N'Valid escaped Unicode criteria rejected.',1;
    IF @InitialTransactionCount=0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke064;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount=0 AND XACT_STATE()<>0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount>0 AND XACT_STATE()=1 ROLLBACK TRANSACTION FP_Smoke064;
    THROW;
END CATCH;
