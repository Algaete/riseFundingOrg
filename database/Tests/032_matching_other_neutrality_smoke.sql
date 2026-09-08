/* Transactional smoke for migration 032. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMatchingRun_Create', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_MatchingProfiles', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_MatchingRules', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_MatchingRuleWeights', N'U') IS NULL
    THROW 55220, N'Matching OTHER neutrality objects are unavailable.', 1;

DECLARE @LegacyProfileId INT =
    (SELECT Id FROM dbo.FundingPlatform_MatchingProfiles
     WHERE Code = N'deterministic-project-v1' AND Version = 1
       AND EngineVersion = N'deterministic-sql-v1' AND IsActive = 0);
DECLARE @ProfileId INT =
    (SELECT Id FROM dbo.FundingPlatform_MatchingProfiles
     WHERE Code = N'deterministic-project-v1' AND Version = 2
       AND EngineVersion = N'deterministic-sql-v2'
       AND UnknownPolicy = 1 AND Status = 2 AND IsActive = 1);
IF @LegacyProfileId IS NULL OR @ProfileId IS NULL
   OR (SELECT COUNT_BIG(1)
       FROM dbo.FundingPlatform_MatchingRuleWeights AS weights
       INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
           ON rules.Id = weights.MatchingRuleId
       WHERE weights.MatchingProfileId = @LegacyProfileId
         AND rules.HandlerVersion = N'v1'
         AND weights.ParametersJson =
             N'{"unknownPolicy":"zero-no-renormalization"}') <> 9
   OR (SELECT SUM(Weight)
       FROM dbo.FundingPlatform_MatchingRuleWeights
       WHERE MatchingProfileId = @LegacyProfileId) <> 100
   OR (SELECT COUNT_BIG(1)
       FROM dbo.FundingPlatform_MatchingRuleWeights AS weights
       INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
           ON rules.Id = weights.MatchingRuleId
       WHERE weights.MatchingProfileId = @ProfileId
         AND rules.HandlerVersion = N'v2'
         AND weights.ParametersJson =
             N'{"unknownPolicy":"zero-no-renormalization","otherPolicy":"neutral-excluded"}') <> 9
   OR EXISTS
      (SELECT 1
       FROM dbo.FundingPlatform_ProjectMatchingRuns AS runs
       WHERE runs.MatchingProfileId = @LegacyProfileId
         AND (runs.MatchingProfileCodeSnapshot <> N'deterministic-project-v1'
              OR runs.MatchingProfileVersionSnapshot <> 1
              OR runs.EngineVersionSnapshot <> N'deterministic-sql-v1'))
   OR EXISTS
      (SELECT 1
       FROM dbo.FundingPlatform_ProjectMatchingRuns AS runs
       INNER JOIN dbo.FundingPlatform_ProjectFundingMatches AS matches
           ON matches.MatchRunId = runs.Id
       INNER JOIN dbo.FundingPlatform_ProjectFundingMatchRuleResults AS results
           ON results.MatchId = matches.Id
       INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
           ON rules.Id = results.MatchingRuleId
       WHERE runs.MatchingProfileId = @LegacyProfileId
         AND rules.HandlerVersion <> N'v1')
    THROW 55221, N'Versioned deterministic matching profiles are inconsistent.', 1;

DECLARE @CreateDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMatchingRun_Create'));
DECLARE @LegacyHandlerToken NVARCHAR(100) = N'rules.HandlerVersion = N''v1''';
DECLARE @CurrentHandlerToken NVARCHAR(100) = N'rules.HandlerVersion = N''v2''';
DECLARE @NeutralToken NVARCHAR(100) = N'Code <> N''OTHER''';
DECLARE @LegacyHandlerCount INT =
    (DATALENGTH(@CreateDefinition) -
     DATALENGTH(REPLACE(@CreateDefinition, @LegacyHandlerToken, N''))) /
    DATALENGTH(@LegacyHandlerToken);
DECLARE @CurrentHandlerCount INT =
    (DATALENGTH(@CreateDefinition) -
     DATALENGTH(REPLACE(@CreateDefinition, @CurrentHandlerToken, N''))) /
    DATALENGTH(@CurrentHandlerToken);
DECLARE @NeutralCount INT =
    (DATALENGTH(@CreateDefinition) -
     DATALENGTH(REPLACE(@CreateDefinition, @NeutralToken, N''))) /
    DATALENGTH(@NeutralToken);
IF @CreateDefinition IS NULL
   OR @LegacyHandlerCount <> 0 OR @CurrentHandlerCount <> 3 OR @NeutralCount <> 6
   OR @CreateDefinition NOT LIKE N'%FundingOpportunityCategories AS links%FundingCategories AS categoryCatalog%'
   OR @CreateDefinition NOT LIKE N'%FundingOpportunityBeneficiaryTypes AS links%BeneficiaryTypes AS beneficiaryCatalog%'
   OR @CreateDefinition NOT LIKE N'%FundingOpportunityProjectTypes AS links%ProjectTypes AS projectTypeCatalog%'
   OR @CreateDefinition NOT LIKE N'%ProjectCategories AS links%FundingCategories AS categoryCatalog%'
   OR @CreateDefinition NOT LIKE N'%ProjectBeneficiaryTypes AS links%BeneficiaryTypes AS beneficiaryCatalog%'
   OR @CreateDefinition NOT LIKE N'%ProjectProjectTypes AS links%ProjectTypes AS projectTypeCatalog%'
    THROW 55222, N'The deterministic v2 procedure does not filter every OTHER snapshot.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke032;

BEGIN TRY
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
         WHERE Code = N'OTHER' AND IsActive = 1);
    DECLARE @OtherBeneficiaryId INT =
        (SELECT Id FROM dbo.FundingPlatform_BeneficiaryTypes
         WHERE Code = N'OTHER' AND IsActive = 1);
    DECLARE @OtherProjectTypeId INT =
        (SELECT Id FROM dbo.FundingPlatform_ProjectTypes
         WHERE Code = N'OTHER' AND IsActive = 1);
    IF @OrganizationTypeId IS NULL OR @SourceId IS NULL
       OR @OtherCategoryId IS NULL OR @OtherBeneficiaryId IS NULL
       OR @OtherProjectTypeId IS NULL
        THROW 55223, N'Catalogs required by the OTHER neutrality fixture are unavailable.', 1;

    DECLARE @OwnerPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @OwnerEmail NVARCHAR(320) = N'smoke032-' + @Suffix + N'@example.invalid';
    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@OwnerPublicId, @OwnerEmail, UPPER(@OwnerEmail), N'Smoke 032 owner',
         N'not-a-credential', N'smoke032', 1, 0, 2, N'es-CL');
    DECLARE @OwnerId BIGINT = SCOPE_IDENTITY();

    DECLARE @OrganizationPublicId UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.FundingPlatform_Organizations
        (PublicId, CreatedByUserId, Name, HomeCountryId, OrganizationTypeId,
         PreviousFundingExperience, ProfileStatus, ProfileCompleteness,
         ProfileVersion, IsActive)
    VALUES
        (@OrganizationPublicId, @OwnerId, N'Smoke 032 organization ' + @Suffix,
         152, @OrganizationTypeId, 2, 2, 90, 1, 1);
    DECLARE @OrganizationId BIGINT = SCOPE_IDENTITY();
    INSERT INTO dbo.FundingPlatform_OrganizationUsers
        (OrganizationId, UserId, Role, MembershipStatus, JoinedAtUtc)
    VALUES (@OrganizationId, @OwnerId, 1, 1, @RunNowUtc);
    INSERT INTO dbo.FundingPlatform_OrganizationProfileVersions
        (OrganizationId, ProfileVersion, SnapshotJson, ContentHash,
         CreatedByUserId, CreatedAtUtc)
    VALUES
        (@OrganizationId, 1, N'{"schema":"smoke032-organization"}',
         HASHBYTES('SHA2_256', N'smoke032-organization-' + @Suffix),
         @OwnerId, @RunNowUtc);

    DECLARE @ProjectPublicId UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.FundingPlatform_Projects
        (PublicId, OrganizationId, CreatedByUserId, Slug, Title, Summary, Description,
         ProjectStatus, PublicationStatus, BudgetTotal, ConfirmedFunding, Currency,
         ProjectVersion, IsActive, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@ProjectPublicId, @OrganizationId, @OwnerId,
         N'smoke032-project-' + @Suffix, N'Smoke 032 project ' + @Suffix,
         N'Summary', N'Description', 2, 0, 1000, 0, 'USD', 1, 1,
         @RunNowUtc, @RunNowUtc);
    DECLARE @ProjectId BIGINT = SCOPE_IDENTITY();
    INSERT INTO dbo.FundingPlatform_ProjectVersions
        (ProjectId, ProjectVersion, SnapshotJson, ContentHash,
         CreatedByUserId, CreatedAtUtc)
    VALUES
        (@ProjectId, 1, N'{"schema":"smoke032-project"}',
         HASHBYTES('SHA2_256', N'smoke032-project-' + @Suffix),
         @OwnerId, @RunNowUtc);
    INSERT INTO dbo.FundingPlatform_ProjectCategories (ProjectId, FundingCategoryId)
        VALUES (@ProjectId, @OtherCategoryId);
    INSERT INTO dbo.FundingPlatform_ProjectBeneficiaryTypes (ProjectId, BeneficiaryTypeId)
        VALUES (@ProjectId, @OtherBeneficiaryId);
    INSERT INTO dbo.FundingPlatform_ProjectProjectTypes (ProjectId, ProjectTypeId)
        VALUES (@ProjectId, @OtherProjectTypeId);

    DECLARE @FunderPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @SponsorName NVARCHAR(300) = N'Smoke 032 funder ' + @Suffix;
    INSERT INTO dbo.FundingPlatform_Funders
        (PublicId, Slug, Name, NormalizedName, WebsiteUrl, PublicationStatus,
         PublishedAtUtc, ReviewedAtUtc, ContentVersion, IsActive,
         CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@FunderPublicId, N'smoke032-funder-' + @Suffix, @SponsorName,
         UPPER(@SponsorName), N'https://smoke032-funder.example.invalid',
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
        (@OpportunityPublicId, N'smoke032-opportunity-' + @Suffix,
         N'Smoke 032 opportunity ' + @Suffix, N'Description', N'Summary', @SponsorName,
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
        (@OpportunityId, @SourceId, N'smoke032-' + @Suffix,
         HASHBYTES('SHA2_256', N'smoke032-source-key-' + @Suffix),
         N'https://smoke032-source.example.invalid/' + @Suffix,
         HASHBYTES('SHA2_256', N'smoke032-source-url-' + @Suffix),
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
        (@OpportunityId, 1, N'{"schema":"smoke032-opportunity"}',
         HASHBYTES('SHA2_256', N'smoke032-opportunity-' + @Suffix),
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
        HASHBYTES('SHA2_256', N'smoke032-idempotency-' + @Suffix);
    DECLARE @RequestHash BINARY(32) =
        HASHBYTES('SHA2_256', N'smoke032-request-' + @Suffix);
    INSERT INTO @RunRows
    EXEC dbo.FundingPlatform_usp_ProjectMatchingRun_Create
        @UserPublicId = @OwnerPublicId,
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @IdempotencyKeyHash = @IdempotencyKeyHash,
        @RequestHash = @RequestHash,
        @NowUtc = @RunNowUtc;

    DECLARE @RunPublicId UNIQUEIDENTIFIER = (SELECT RunPublicId FROM @RunRows);
    DECLARE @RunId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_ProjectMatchingRuns
         WHERE PublicId = @RunPublicId);
    DECLARE @MatchId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_ProjectFundingMatches
         WHERE MatchRunId = @RunId AND FundingOpportunityId = @OpportunityId);
    IF @RunId IS NULL OR @MatchId IS NULL
       OR NOT EXISTS
          (SELECT 1 FROM @RunRows
           WHERE MatchingProfileVersion = 2
             AND EngineVersion = N'deterministic-sql-v2'
             AND WasReplay = 0 AND Status = 2)
        THROW 55225, N'The OTHER neutrality run did not use deterministic v2.', 1;

    IF (SELECT COUNT_BIG(1)
        FROM dbo.FundingPlatform_ProjectFundingMatchRuleResults AS results
        INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
            ON rules.Id = results.MatchingRuleId
        WHERE results.MatchId = @MatchId
          AND rules.HandlerVersion = N'v2'
          AND rules.Code IN (N'categories', N'beneficiaries', N'project_type')
          AND results.Outcome = 3
          AND results.DataState = 1
          AND results.RawScore IS NULL
          AND results.EffectiveScore = 0
          AND results.WeightedPoints = 0
          AND results.EvidenceJson IS NULL
          AND results.ReasonCode IN
              (N'categories.missing_project', N'beneficiaries.missing_project',
               N'project_type.missing_project')) <> 3
       OR EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ProjectFundingMatchRuleResults AS results
           INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
               ON rules.Id = results.MatchingRuleId
           WHERE results.MatchId = @MatchId
             AND rules.Code IN (N'categories', N'beneficiaries', N'project_type')
             AND results.ReasonCode IN
                 (N'categories.match', N'beneficiaries.match', N'project_type.match'))
        THROW 55226, N'An OTHER value contributed to a deterministic match.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ProjectFundingMatches
        WHERE Id = @MatchId AND Classification = 0 AND HardGateStatus = 0
          AND CompatibilityScore = 80 AND RuleScore = 80 AND EvidenceCoverage = 80)
        THROW 55227, N'Neutral OTHER rules changed the expected score or coverage.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke032;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FP_Smoke032;
    THROW;
END CATCH;
