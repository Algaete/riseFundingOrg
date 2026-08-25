/* Transactional FASE 9A smoke: deterministic project-first matching only. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_MatchingProfiles', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_MatchingRules', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_MatchingRuleWeights', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ProjectMatchingRuns', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ProjectFundingMatches', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ProjectFundingMatchRuleResults', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ProjectMatchingRunRequests', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ifn_ProjectMatchingOpenCandidates', N'IF') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ifn_ProjectMatchingCatalogState', N'IF') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ifn_MatchingProfileRuleSetFingerprint', N'IF') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ifn_ProjectMatchingRunSummaries', N'IF') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMatchingRun_Create', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMatchingRun_List', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMatchingRun_Get', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_tr_MatchingProfiles_Immutable', N'TR') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_tr_MatchingRules_Immutable', N'TR') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_tr_MatchingRuleWeights_Immutable', N'TR') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_tr_ProjectMatchingRuns_Immutable', N'TR') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_tr_ProjectFundingMatchRuleResults_Immutable', N'TR') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_tr_ProjectMatchingRunRequests_Immutable', N'TR') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_tr_ProjectFundingMatches_SupersessionOnly', N'TR') IS NULL
    THROW 54001, N'FASE 9A objects are incomplete.', 1;

IF EXISTS
   (SELECT 1
    FROM (VALUES
          (N'dbo.FundingPlatform_tr_MatchingProfiles_Immutable'),
          (N'dbo.FundingPlatform_tr_MatchingRules_Immutable'),
          (N'dbo.FundingPlatform_tr_MatchingRuleWeights_Immutable'),
          (N'dbo.FundingPlatform_tr_ProjectMatchingRuns_Immutable'),
          (N'dbo.FundingPlatform_tr_ProjectFundingMatchRuleResults_Immutable'),
          (N'dbo.FundingPlatform_tr_ProjectMatchingRunRequests_Immutable'),
          (N'dbo.FundingPlatform_tr_ProjectFundingMatches_SupersessionOnly'))
         AS requiredTrigger(Name)
    WHERE COALESCE(OBJECT_DEFINITION(OBJECT_ID(requiredTrigger.Name)), N'')
          NOT LIKE N'%SET XACT_ABORT OFF%')
    THROW 54033, N'An immutability trigger can doom the caller transaction.', 1;

DECLARE @CreateDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMatchingRun_Create'));
DECLARE @SummaryDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_ifn_ProjectMatchingRunSummaries'));
DECLARE @OpenDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_ifn_ProjectMatchingOpenCandidates'));
IF @CreateDefinition NOT LIKE N'%SELECT TOP (200) * INTO #Candidates%'
   OR @CreateDefinition NOT LIKE N'%WITH (HOLDLOCK)%'
   OR @CreateDefinition NOT LIKE N'%#CandidateCountries%'
   OR @CreateDefinition NOT LIKE N'%#CandidateOrganizationTypes%'
   OR @CreateDefinition NOT LIKE N'%#CandidateLegalEntityTypes%'
   OR @CreateDefinition NOT LIKE N'%#CandidateCategories%'
   OR @CreateDefinition NOT LIKE N'%#CandidateBeneficiaryTypes%'
   OR @CreateDefinition NOT LIKE N'%#CandidateProjectTypes%'
   OR @CreateDefinition NOT LIKE N'%@CurrentCandidateSetFingerprint%'
   OR @CreateDefinition NOT LIKE N'%CASE WHEN result.Outcome = 3 THEN NULL ELSE%'
   OR @CreateDefinition LIKE N'%OpenAI%'
   OR @CreateDefinition LIKE N'%Embedding%'
   OR @SummaryDefinition NOT LIKE N'%CalculationCalendarYear = DATEPART(YEAR, @NowUtc)%'
   OR @SummaryDefinition NOT LIKE N'%currentRuleSet.RuleSetFingerprint = runs.RuleSetFingerprint%'
   OR @SummaryDefinition NOT LIKE N'%newerRuns.Id > runs.Id%'
   OR @CreateDefinition NOT LIKE N'%newerRuns.Id > runs.Id%'
   OR @OpenDefinition NOT LIKE N'%opportunities.DeadlineType = 2%'
   OR @OpenDefinition NOT LIKE N'%opportunities.DeadlinePrecision = 2%'
   OR @OpenDefinition NOT LIKE N'%opportunities.CloseAtUtc > @NowUtc%'
   OR @OpenDefinition NOT LIKE N'%opportunities.DeadlinePrecision = 1%'
   OR @OpenDefinition NOT LIKE N'%opportunities.CloseDate >= CONVERT(DATE, @NowUtc)%'
    THROW 54002, N'Matching bounds, locks, freshness, evidence-null or deadline guards drifted.', 1;

IF NOT EXISTS
   (SELECT 1 FROM sys.foreign_keys
    WHERE parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_ProjectMatchingRunRequests')
      AND name = N'FundingPlatform_FK_ProjectMatchingRunRequests_RunTenantProject')
   OR EXISTS
   (SELECT 1 FROM sys.foreign_keys
    WHERE parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_ProjectMatchingRunRequests')
      AND name = N'FundingPlatform_FK_ProjectMatchingRunRequests_Run')
   OR NOT EXISTS
   (SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_ProjectFundingMatches')
      AND name = N'FundingPlatform_CK_ProjectFundingMatches_Scores')
   OR NOT EXISTS
   (SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.FundingPlatform_ProjectMatchingRuns')
      AND name = N'FundingPlatform_IX_ProjectMatchingRuns_ProjectInput'
      AND is_unique = 0)
    THROW 54003, N'Matching tenant or nullable incompatible-score constraints are missing.', 1;

DECLARE @ProfileId INT =
    (SELECT Id FROM dbo.FundingPlatform_MatchingProfiles
     WHERE Code = N'deterministic-project-v1' AND Version = 1
       AND EngineVersion = N'deterministic-sql-v1'
       AND UnknownPolicy = 1 AND Status = 2 AND IsActive = 1);
IF @ProfileId IS NULL
   OR (SELECT COUNT_BIG(1)
       FROM dbo.FundingPlatform_MatchingRuleWeights AS weights
       INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
           ON rules.Id = weights.MatchingRuleId
       WHERE weights.MatchingProfileId = @ProfileId) <> 9
   OR (SELECT SUM(Weight) FROM dbo.FundingPlatform_MatchingRuleWeights
       WHERE MatchingProfileId = @ProfileId) <> 100
   OR (SELECT SUM(weights.Weight)
       FROM dbo.FundingPlatform_MatchingRuleWeights AS weights
       INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
           ON rules.Id = weights.MatchingRuleId AND rules.IsHardGate = 1
       WHERE weights.MatchingProfileId = @ProfileId) <> 70
    THROW 54004, N'The seeded deterministic profile is not the frozen 9-rule/100-point profile.', 1;

IF EXISTS
   (SELECT required.Code
    FROM (VALUES
          (N'geography', CONVERT(DECIMAL(5,2), 20), CONVERT(BIT, 1)),
          (N'organization_type', CONVERT(DECIMAL(5,2), 15), CONVERT(BIT, 1)),
          (N'legal_entity', CONVERT(DECIMAL(5,2), 15), CONVERT(BIT, 1)),
          (N'operating_years', CONVERT(DECIMAL(5,2), 10), CONVERT(BIT, 1)),
          (N'prior_experience', CONVERT(DECIMAL(5,2), 10), CONVERT(BIT, 1)),
          (N'categories', CONVERT(DECIMAL(5,2), 10), CONVERT(BIT, 0)),
          (N'beneficiaries', CONVERT(DECIMAL(5,2), 5), CONVERT(BIT, 0)),
          (N'project_type', CONVERT(DECIMAL(5,2), 5), CONVERT(BIT, 0)),
          (N'amount', CONVERT(DECIMAL(5,2), 10), CONVERT(BIT, 0)))
         AS required(Code, Weight, IsHardGate)
    WHERE NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_MatchingRuleWeights AS weights
           INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
               ON rules.Id = weights.MatchingRuleId
           WHERE weights.MatchingProfileId = @ProfileId
             AND rules.Code = required.Code
             AND rules.IsHardGate = required.IsHardGate
             AND weights.Weight = required.Weight))
    THROW 54005, N'The deterministic rule catalog or weights drifted.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke020;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @Suffix NVARCHAR(32) = REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'');
    DECLARE @RunNowUtc DATETIME2(3) = DATETIME2FROMPARTS
        (DATEPART(YEAR, SYSUTCDATETIME()), 12, 31, 12, 0, 0, 0, 3);
    DECLARE @RunDate DATE = CONVERT(DATE, @RunNowUtc);
    DECLARE @NextYearUtc DATETIME2(3) = DATEADD(DAY, 1, @RunNowUtc);
    DECLARE @CategoryId INT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_FundingCategories
         WHERE IsActive = 1 ORDER BY Id);
    DECLARE @BeneficiaryTypeId INT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_BeneficiaryTypes
         WHERE IsActive = 1 ORDER BY Id);
    DECLARE @ProjectTypeId INT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_ProjectTypes
         WHERE IsActive = 1 ORDER BY Id);
    DECLARE @OrganizationTypeId SMALLINT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_OrganizationTypes
         WHERE IsActive = 1 ORDER BY Id);
    DECLARE @LegalEntityTypeId SMALLINT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_LegalEntityTypes
         WHERE IsActive = 1 AND (CountryId IS NULL OR CountryId = 152) ORDER BY Id);
    DECLARE @SourceId INT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_FundingSources
         WHERE IsEnabled = 1 ORDER BY Id);
    IF @CategoryId IS NULL OR @BeneficiaryTypeId IS NULL OR @ProjectTypeId IS NULL
       OR @OrganizationTypeId IS NULL OR @LegalEntityTypeId IS NULL OR @SourceId IS NULL
        THROW 54006, N'Required active catalogs are unavailable.', 1;

    DECLARE @OwnerPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @OtherPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @OwnerEmail NVARCHAR(320) = N'fase9a-owner-' + @Suffix + N'@example.invalid';
    DECLARE @OtherEmail NVARCHAR(320) = N'fase9a-other-' + @Suffix + N'@example.invalid';
    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@OwnerPublicId, @OwnerEmail, UPPER(@OwnerEmail), N'FASE 9A owner',
         N'not-a-credential', N'fase9a-owner', 1, 0, 2, N'es-CL'),
        (@OtherPublicId, @OtherEmail, UPPER(@OtherEmail), N'FASE 9A other',
         N'not-a-credential', N'fase9a-other', 1, 0, 2, N'es-CL');
    DECLARE @OwnerId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @OwnerPublicId);
    DECLARE @OtherId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @OtherPublicId);

    DECLARE @OrganizationPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @OtherOrganizationPublicId UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.FundingPlatform_Organizations
        (PublicId, CreatedByUserId, Name, HomeCountryId, OrganizationTypeId,
         LegalEntityTypeId, EstablishedYear, PreviousFundingExperience,
         ProfileStatus, ProfileCompleteness, ProfileVersion, IsActive)
    VALUES
        (@OrganizationPublicId, @OwnerId, N'FASE 9A organization ' + @Suffix,
         152, @OrganizationTypeId, @LegalEntityTypeId, NULL, 2, 2, 90, 1, 1),
        (@OtherOrganizationPublicId, @OtherId, N'FASE 9A other ' + @Suffix,
         152, @OrganizationTypeId, @LegalEntityTypeId, 2020, 2, 2, 90, 1, 1);
    DECLARE @OrganizationId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Organizations WHERE PublicId = @OrganizationPublicId);
    DECLARE @OtherOrganizationId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Organizations WHERE PublicId = @OtherOrganizationPublicId);
    INSERT INTO dbo.FundingPlatform_OrganizationUsers
        (OrganizationId, UserId, Role, MembershipStatus, JoinedAtUtc)
    VALUES
        (@OrganizationId, @OwnerId, 1, 1, @RunNowUtc),
        (@OtherOrganizationId, @OtherId, 1, 1, @RunNowUtc);
    INSERT INTO dbo.FundingPlatform_OrganizationProfileVersions
        (OrganizationId, ProfileVersion, SnapshotJson, ContentHash, CreatedByUserId, CreatedAtUtc)
    VALUES
        (@OrganizationId, 1, N'{"schema":"fase9a-org"}',
         HASHBYTES('SHA2_256', N'fase9a-org-' + @Suffix), @OwnerId, @RunNowUtc),
        (@OtherOrganizationId, 1, N'{"schema":"fase9a-other-org"}',
         HASHBYTES('SHA2_256', N'fase9a-other-org-' + @Suffix), @OtherId, @RunNowUtc);

    DECLARE @ProjectPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @OtherProjectPublicId UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.FundingPlatform_Projects
        (PublicId, OrganizationId, CreatedByUserId, Slug, Title, Summary, Description,
         ProjectStatus, PublicationStatus, BudgetTotal, ConfirmedFunding, Currency,
         ProjectVersion, IsActive, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@ProjectPublicId, @OrganizationId, @OwnerId, N'fase9a-project-' + @Suffix,
         N'FASE 9A project ' + @Suffix, N'Summary', N'Description',
         2, 0, 1000, 200, 'USD', 1, 1, @RunNowUtc, @RunNowUtc),
        (@OtherProjectPublicId, @OtherOrganizationId, @OtherId,
         N'fase9a-other-project-' + @Suffix, N'FASE 9A other project ' + @Suffix,
         N'Summary', N'Description', 2, 0, 1000, 0, 'USD', 1, 1,
         @RunNowUtc, @RunNowUtc);
    DECLARE @ProjectId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Projects WHERE PublicId = @ProjectPublicId);
    DECLARE @OtherProjectId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Projects WHERE PublicId = @OtherProjectPublicId);
    INSERT INTO dbo.FundingPlatform_ProjectVersions
        (ProjectId, ProjectVersion, SnapshotJson, ContentHash, CreatedByUserId, CreatedAtUtc)
    VALUES
        (@ProjectId, 1, N'{"schema":"fase9a-project"}',
         HASHBYTES('SHA2_256', N'fase9a-project-' + @Suffix), @OwnerId, @RunNowUtc),
        (@OtherProjectId, 1, N'{"schema":"fase9a-other-project"}',
         HASHBYTES('SHA2_256', N'fase9a-other-project-' + @Suffix), @OtherId, @RunNowUtc);
    INSERT INTO dbo.FundingPlatform_ProjectCountries (ProjectId, CountryId)
        VALUES (@ProjectId, 152);
    INSERT INTO dbo.FundingPlatform_ProjectCategories (ProjectId, FundingCategoryId)
        VALUES (@ProjectId, @CategoryId);
    INSERT INTO dbo.FundingPlatform_ProjectBeneficiaryTypes (ProjectId, BeneficiaryTypeId)
        VALUES (@ProjectId, @BeneficiaryTypeId);
    INSERT INTO dbo.FundingPlatform_ProjectProjectTypes (ProjectId, ProjectTypeId)
        VALUES (@ProjectId, @ProjectTypeId);

    DECLARE @FunderPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @SponsorName NVARCHAR(300) = N'FASE 9A sponsor ' + @Suffix;
    INSERT INTO dbo.FundingPlatform_Funders
        (PublicId, Slug, Name, NormalizedName, WebsiteUrl, PublicationStatus,
         PublishedAtUtc, ReviewedAtUtc, ContentVersion, IsActive, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@FunderPublicId, N'fase9a-funder-' + @Suffix, @SponsorName, UPPER(@SponsorName),
         N'https://fase9a-funder.example.invalid', 2, DATEADD(DAY, -2, @RunNowUtc),
         DATEADD(DAY, -2, @RunNowUtc), 1, 1, @RunNowUtc, @RunNowUtc);
    DECLARE @FunderId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Funders WHERE PublicId = @FunderPublicId);

    DECLARE @CompatiblePublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @IncompatiblePublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InsufficientPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @DateBoundaryPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ExactClosedPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @UnknownDeadlinePublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @DraftPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @RollingPublicId UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.FundingPlatform_FundingOpportunities
        (PublicId, Slug, Title, Description, Summary, SponsorName,
         Currency, MinAmount, MaxAmount, AmountStatus, OpenDate,
         CloseDate, CloseAtUtc, DeadlineTimeZoneId, DeadlineType, DeadlinePrecision,
         EligibilityDescription, Requirements, MinimumOperatingYears,
         RequiresLegalEntity, RequiresPriorExperience, GeographicScope,
         RemoteApplication, PublicationStatus, PublishedAtUtc, LastVerifiedAtUtc,
         DataQualityScore, ContentVersion, IsActive, ReviewedAtUtc, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@CompatiblePublicId, N'fase9a-compatible-' + @Suffix,
         N'Compatible fixture ' + @Suffix, N'Description', N'Summary', @SponsorName,
         'USD', 100, 1000, 1, NULL, @RunDate,
         DATEADD(MILLISECOND, 1, @RunNowUtc), N'UTC', 1, 2,
         N'Controlled criteria', N'Requirements', 0, 1, 1, 2, 1, 2,
         DATEADD(DAY, -2, @RunNowUtc), @RunNowUtc, 100, 1, 1,
         DATEADD(DAY, -2, @RunNowUtc), @RunNowUtc, DATEADD(MILLISECOND, 1, @RunNowUtc)),
        (@IncompatiblePublicId, N'fase9a-incompatible-' + @Suffix,
         N'Incompatible fixture ' + @Suffix, N'Description', N'Summary', @SponsorName,
         'USD', 100, 1000, 1, NULL, @RunDate,
         DATEADD(MILLISECOND, 2, @RunNowUtc), N'UTC', 1, 2,
         N'Controlled criteria', N'Requirements', 0, 0, 0, 2, 1, 2,
         DATEADD(DAY, -2, @RunNowUtc), @RunNowUtc, 100, 1, 1,
         DATEADD(DAY, -2, @RunNowUtc), @RunNowUtc, DATEADD(MILLISECOND, 2, @RunNowUtc)),
        (@InsufficientPublicId, N'fase9a-insufficient-' + @Suffix,
         N'Insufficient fixture ' + @Suffix, N'Description', N'Summary', @SponsorName,
         'USD', 100, 1000, 1, NULL, @RunDate,
         DATEADD(MILLISECOND, 3, @RunNowUtc), N'UTC', 1, 2,
         N'Controlled criteria', N'Requirements', 0, 0, 0, 2, 1, 2,
         DATEADD(DAY, -2, @RunNowUtc), @RunNowUtc, 100, 1, 1,
         DATEADD(DAY, -2, @RunNowUtc), @RunNowUtc, DATEADD(MILLISECOND, 3, @RunNowUtc)),
        (@DateBoundaryPublicId, N'fase9a-date-boundary-' + @Suffix,
         N'Date boundary fixture ' + @Suffix, N'Description', N'Summary', @SponsorName,
         'USD', 100, 1000, 1, NULL, @RunDate, NULL, NULL, 1, 1,
         N'Controlled criteria', N'Requirements', 0, 0, 0, 2, 1, 2,
         DATEADD(DAY, -2, @RunNowUtc), @RunNowUtc, 100, 1, 1,
         DATEADD(DAY, -2, @RunNowUtc), @RunNowUtc, DATEADD(MILLISECOND, 4, @RunNowUtc)),
        (@ExactClosedPublicId, N'fase9a-exact-closed-' + @Suffix,
         N'Exact closed fixture ' + @Suffix, N'Description', N'Summary', @SponsorName,
         'USD', 100, 1000, 1, NULL, @RunDate, @RunNowUtc, N'UTC', 1, 2,
         N'Controlled criteria', N'Requirements', 0, 0, 0, 2, 1, 2,
         DATEADD(DAY, -2, @RunNowUtc), @RunNowUtc, 100, 1, 1,
         DATEADD(DAY, -2, @RunNowUtc), @RunNowUtc, DATEADD(MILLISECOND, 5, @RunNowUtc)),
        (@UnknownDeadlinePublicId, N'fase9a-unknown-deadline-' + @Suffix,
         N'Unknown deadline fixture ' + @Suffix, N'Description', N'Summary', @SponsorName,
         'USD', 100, 1000, 1, NULL, NULL, NULL, NULL, 0, 0,
         N'Controlled criteria', N'Requirements', 0, 0, 0, 2, 1, 2,
         DATEADD(DAY, -2, @RunNowUtc), @RunNowUtc, 100, 1, 1,
         DATEADD(DAY, -2, @RunNowUtc), @RunNowUtc, DATEADD(MILLISECOND, 6, @RunNowUtc)),
        (@DraftPublicId, N'fase9a-draft-' + @Suffix,
         N'Draft fixture ' + @Suffix, N'Description', N'Summary', @SponsorName,
         'USD', 100, 1000, 1, NULL, NULL, NULL, NULL, 2, 0,
         N'Controlled criteria', N'Requirements', 0, 0, 0, 2, 1, 0,
         NULL, @RunNowUtc, 100, 1, 1, NULL, @RunNowUtc,
         DATEADD(MILLISECOND, 7, @RunNowUtc)),
        (@RollingPublicId, N'fase9a-rolling-' + @Suffix,
         N'Rolling fixture ' + @Suffix, N'Description', N'Summary', @SponsorName,
         'USD', 100, 1000, 1, NULL, NULL, NULL, NULL, 2, 0,
         N'Controlled criteria', N'Requirements', 0, 0, 0, 2, 1, 2,
         DATEADD(DAY, -2, @RunNowUtc), @RunNowUtc, 100, 1, 1,
         DATEADD(DAY, -2, @RunNowUtc), @RunNowUtc, DATEADD(MILLISECOND, 8, @RunNowUtc));

    DECLARE @Opportunities TABLE
    (
        SequenceNumber INT NOT NULL PRIMARY KEY,
        PublicId UNIQUEIDENTIFIER NOT NULL,
        OpportunityId BIGINT NOT NULL
    );
    INSERT INTO @Opportunities (SequenceNumber, PublicId, OpportunityId)
    SELECT fixtures.SequenceNumber, fixtures.PublicId, opportunities.Id
    FROM (VALUES
          (1, @CompatiblePublicId), (2, @IncompatiblePublicId),
          (3, @InsufficientPublicId), (4, @DateBoundaryPublicId),
          (5, @ExactClosedPublicId), (6, @UnknownDeadlinePublicId),
          (7, @DraftPublicId), (8, @RollingPublicId)) AS fixtures(SequenceNumber, PublicId)
    INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
        ON opportunities.PublicId = fixtures.PublicId;

    INSERT INTO dbo.FundingPlatform_FundingOpportunityCategories
        (FundingOpportunityId, FundingCategoryId)
        SELECT OpportunityId, @CategoryId FROM @Opportunities;
    INSERT INTO dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes
        (FundingOpportunityId, BeneficiaryTypeId)
        SELECT OpportunityId, @BeneficiaryTypeId FROM @Opportunities;
    INSERT INTO dbo.FundingPlatform_FundingOpportunityProjectTypes
        (FundingOpportunityId, ProjectTypeId)
        SELECT OpportunityId, @ProjectTypeId FROM @Opportunities;

    DECLARE @CompatibleId BIGINT =
        (SELECT OpportunityId FROM @Opportunities WHERE PublicId = @CompatiblePublicId);
    DECLARE @IncompatibleId BIGINT =
        (SELECT OpportunityId FROM @Opportunities WHERE PublicId = @IncompatiblePublicId);
    DECLARE @InsufficientId BIGINT =
        (SELECT OpportunityId FROM @Opportunities WHERE PublicId = @InsufficientPublicId);
    INSERT INTO dbo.FundingPlatform_FundingOpportunityOrganizationTypes
        (FundingOpportunityId, OrganizationTypeId, EligibilityMode)
    VALUES
        (@CompatibleId, @OrganizationTypeId, 1),
        (@IncompatibleId, @OrganizationTypeId, 1);
    INSERT INTO dbo.FundingPlatform_FundingOpportunityLegalEntityTypes
        (FundingOpportunityId, LegalEntityTypeId, EligibilityMode)
    VALUES
        (@CompatibleId, @LegalEntityTypeId, 1),
        /* Explicit exclusion must win even though RequiresLegalEntity = false. */
        (@IncompatibleId, @LegalEntityTypeId, 2);

    INSERT INTO dbo.FundingPlatform_FundingOpportunityFunders
        (FundingOpportunityId, FunderId, Role, IsActive, CreatedAtUtc, UpdatedAtUtc)
        SELECT OpportunityId, @FunderId, 1, 1, @RunNowUtc, @RunNowUtc FROM @Opportunities;
    INSERT INTO dbo.FundingPlatform_FundingOpportunitySourceLinks
        (FundingOpportunityId, FundingSourceId, ExternalId, SourceItemKeyHash,
         SourceUrl, CanonicalUrlHash, FirstSeenAtUtc, LastSeenAtUtc, IsPrimary, IsActive)
    SELECT OpportunityId, @SourceId,
           N'fase9a-' + CONVERT(NVARCHAR(10), SequenceNumber) + N'-' + @Suffix,
           HASHBYTES('SHA2_256', N'fase9a-source-key-' +
                     CONVERT(NVARCHAR(10), SequenceNumber) + @Suffix),
           N'https://fase9a-source.example.invalid/' +
              CONVERT(NVARCHAR(10), SequenceNumber) + N'/' + @Suffix,
           HASHBYTES('SHA2_256', N'fase9a-source-url-' +
                     CONVERT(NVARCHAR(10), SequenceNumber) + @Suffix),
           @RunNowUtc, @RunNowUtc, 1, 1
    FROM @Opportunities;
    INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
        (FundingOpportunityId, FieldPath, ValueJson, ExtractionMethod,
         IsSelected, IsManualLock, CreatedAtUtc)
    SELECT opportunities.OpportunityId, paths.FieldPath,
           CASE WHEN paths.FieldPath = N'/closeDate'
                THEN N'{"status":"unknown","value":null}'
                ELSE N'{"status":"known","value":"controlled"}' END,
           1, 1, 0, @RunNowUtc
    FROM @Opportunities AS opportunities
    CROSS JOIN (VALUES (N'/title'), (N'/description'),
                       (N'/eligibilityDescription'), (N'/closeDate')) AS paths(FieldPath);
    INSERT INTO dbo.FundingPlatform_FundingOpportunityVersions
        (FundingOpportunityId, ContentVersion, SnapshotJson, ContentHash,
         CreatedByUserId, CreatedAtUtc)
    SELECT OpportunityId, 1,
           CONCAT(N'{"schema":"fase9a-opportunity-', SequenceNumber, N'"}'),
           HASHBYTES('SHA2_256', N'fase9a-opportunity-' +
                     CONVERT(NVARCHAR(10), SequenceNumber) + @Suffix),
           @OwnerId, @RunNowUtc
    FROM @Opportunities;

    IF (SELECT COUNT_BIG(1)
        FROM dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
        INNER JOIN @Opportunities AS fixtures
            ON fixtures.OpportunityId = ready.FundingOpportunityId) <> 7
        THROW 54007, N'Published fixture opportunities are not PublicReady or draft leaked.', 1;

    DECLARE @DateBoundaryId BIGINT =
        (SELECT OpportunityId FROM @Opportunities WHERE PublicId = @DateBoundaryPublicId);
    DECLARE @ExactClosedId BIGINT =
        (SELECT OpportunityId FROM @Opportunities WHERE PublicId = @ExactClosedPublicId);
    DECLARE @UnknownDeadlineId BIGINT =
        (SELECT OpportunityId FROM @Opportunities WHERE PublicId = @UnknownDeadlinePublicId);
    DECLARE @RollingId BIGINT =
        (SELECT OpportunityId FROM @Opportunities WHERE PublicId = @RollingPublicId);
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMatchingOpenCandidates(@RunNowUtc)
        WHERE FundingOpportunityId = @DateBoundaryId)
       OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMatchingOpenCandidates(@RunNowUtc)
        WHERE FundingOpportunityId = @RollingId)
       OR EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMatchingOpenCandidates(@RunNowUtc)
        WHERE FundingOpportunityId IN (@ExactClosedId, @UnknownDeadlineId))
        THROW 54008, N'Date-only/exact-time/unknown deadline boundary handling drifted.', 1;

    /* Boundary-only fixtures are not part of scoring. The three scored fixtures
       have the earliest exact future instants, so ambient catalog size cannot
       push them beyond the bounded TOP (200). */
    UPDATE dbo.FundingPlatform_FundingOpportunities
    SET PublicationStatus = 4, IsActive = 0, UpdatedAtUtc = DATEADD(SECOND, 1, @RunNowUtc)
    WHERE Id IN (@DateBoundaryId, @RollingId);

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
    DECLARE @IdempotencyKey BINARY(32) =
        HASHBYTES('SHA2_256', N'fase9a-idempotency-' + @Suffix);
    DECLARE @RequestHash BINARY(32) =
        HASHBYTES('SHA2_256', N'fase9a-request-' + @Suffix);
    INSERT INTO @RunRows
    EXEC dbo.FundingPlatform_usp_ProjectMatchingRun_Create
        @UserPublicId = @OwnerPublicId,
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @IdempotencyKeyHash = @IdempotencyKey,
        @RequestHash = @RequestHash,
        @NowUtc = @RunNowUtc;
    DECLARE @RunPublicId UNIQUEIDENTIFIER = (SELECT RunPublicId FROM @RunRows);
    DECLARE @RunId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_ProjectMatchingRuns WHERE PublicId = @RunPublicId);
    IF @RunId IS NULL OR NOT EXISTS
       (SELECT 1 FROM @RunRows WHERE WasReplay = 0 AND Status = 2 AND IsCurrent = 1
                                 AND ProcessedCandidateCount >= 3)
        THROW 54009, N'The deterministic matching run was not created current and completed.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ProjectFundingMatches
        WHERE MatchRunId = @RunId AND FundingOpportunityId = @CompatibleId
          AND Classification = 0 AND HardGateStatus = 0
          AND CompatibilityScore BETWEEN 0 AND 100)
       OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ProjectFundingMatches
        WHERE MatchRunId = @RunId AND FundingOpportunityId = @IncompatibleId
          AND Classification = 1 AND HardGateStatus = 1
          AND CompatibilityScore IS NULL)
       OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ProjectFundingMatches
        WHERE MatchRunId = @RunId AND FundingOpportunityId = @InsufficientId
          AND Classification = 2 AND HardGateStatus = 2
          AND CompatibilityScore = 85 AND RuleScore = 85 AND EvidenceCoverage = 85)
        THROW 54010, N'Compatible/Incompatible/InsufficientData classification drifted.', 1;

    DECLARE @CompatibleMatchId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_ProjectFundingMatches
         WHERE MatchRunId = @RunId AND FundingOpportunityId = @CompatibleId);
    DECLARE @IncompatibleMatchId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_ProjectFundingMatches
         WHERE MatchRunId = @RunId AND FundingOpportunityId = @IncompatibleId);
    DECLARE @InsufficientMatchId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_ProjectFundingMatches
         WHERE MatchRunId = @RunId AND FundingOpportunityId = @InsufficientId);
    IF NOT EXISTS
       (SELECT 1
        FROM dbo.FundingPlatform_ProjectFundingMatchRuleResults AS results
        INNER JOIN dbo.FundingPlatform_MatchingRules AS rules ON rules.Id = results.MatchingRuleId
        WHERE results.MatchId = @CompatibleMatchId AND rules.Code = N'operating_years'
          AND results.Outcome = 0 AND results.DataState = 2 AND results.RawScore = 100
          AND results.ReasonCode = N'operating_years.not_required')
       OR NOT EXISTS
       (SELECT 1
        FROM dbo.FundingPlatform_ProjectFundingMatchRuleResults AS results
        INNER JOIN dbo.FundingPlatform_MatchingRules AS rules ON rules.Id = results.MatchingRuleId
        WHERE results.MatchId = @IncompatibleMatchId AND rules.Code = N'legal_entity'
          AND results.Outcome = 2 AND results.ReasonCode = N'legal_entity.excluded')
       OR NOT EXISTS
       (SELECT 1
        FROM dbo.FundingPlatform_ProjectFundingMatchRuleResults AS results
        INNER JOIN dbo.FundingPlatform_MatchingRules AS rules ON rules.Id = results.MatchingRuleId
        WHERE results.MatchId = @InsufficientMatchId AND rules.Code = N'organization_type'
          AND results.Outcome = 3 AND results.DataState = 1
          AND results.RawScore IS NULL AND results.EvidenceJson IS NULL)
        THROW 54011, N'Legal precedence, zero-year N/A or unknown evidence-null drifted.', 1;

    IF EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ProjectFundingMatchRuleResults AS results
        INNER JOIN dbo.FundingPlatform_ProjectFundingMatches AS matches ON matches.Id = results.MatchId
        WHERE matches.MatchRunId = @RunId
          AND (results.WeightedPoints < 0 OR results.WeightedPoints > results.AppliedWeight))
       OR EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ProjectFundingMatches
        WHERE MatchRunId = @RunId
          AND (RuleScore < 0 OR RuleScore > 100
               OR EvidenceCoverage < 0 OR EvidenceCoverage > 100))
        THROW 54012, N'Rule points or conservative coverage escaped their bounds.', 1;

    DELETE FROM @RunRows;
    INSERT INTO @RunRows
    EXEC dbo.FundingPlatform_usp_ProjectMatchingRun_Create
        @UserPublicId = @OwnerPublicId,
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @IdempotencyKeyHash = @IdempotencyKey,
        @RequestHash = @RequestHash,
        @NowUtc = @RunNowUtc;
    IF NOT EXISTS (SELECT 1 FROM @RunRows WHERE RunPublicId = @RunPublicId AND WasReplay = 1)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_ProjectMatchingRuns
           WHERE ProjectId = @ProjectId) <> 1
        THROW 54013, N'The same idempotency key did not replay the durable run.', 1;

    DECLARE @SecondKey BINARY(32) =
        HASHBYTES('SHA2_256', N'fase9a-second-idempotency-' + @Suffix);
    DELETE FROM @RunRows;
    INSERT INTO @RunRows
    EXEC dbo.FundingPlatform_usp_ProjectMatchingRun_Create
        @UserPublicId = @OwnerPublicId,
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @IdempotencyKeyHash = @SecondKey,
        @RequestHash = @RequestHash,
        @NowUtc = @RunNowUtc;
    IF NOT EXISTS (SELECT 1 FROM @RunRows WHERE RunPublicId = @RunPublicId AND WasReplay = 1)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_ProjectMatchingRunRequests
           WHERE MatchRunId = @RunId) <> 2
        THROW 54014, N'An unchanged input fingerprint duplicated its run.', 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMatchingRunSummaries(@RunNowUtc)
        WHERE MatchRunId = @RunId AND IsCurrent = 1)
       OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMatchingRunSummaries(@NextYearUtc)
        WHERE MatchRunId = @RunId AND IsCurrent = 0)
        THROW 54015, N'Calendar-year freshness did not fail closed.', 1;

    /* Versioned organization/catalog changes stale the old run. The new
       operating-years fixture sits exactly on the one-year uncertainty edge. */
    INSERT INTO dbo.FundingPlatform_OrganizationProfileVersions
        (OrganizationId, ProfileVersion, SnapshotJson, ContentHash, CreatedByUserId, CreatedAtUtc)
    VALUES
        (@OrganizationId, 2, N'{"schema":"fase9a-org-v2"}',
         HASHBYTES('SHA2_256', N'fase9a-org-v2-' + @Suffix), @OwnerId, @RunNowUtc);
    UPDATE dbo.FundingPlatform_Organizations
    SET EstablishedYear = DATEPART(YEAR, @RunNowUtc) - 2,
        ProfileVersion = 2,
        UpdatedAtUtc = DATEADD(SECOND, 4, UpdatedAtUtc)
    WHERE Id = @OrganizationId;
    INSERT INTO dbo.FundingPlatform_FundingOpportunityVersions
        (FundingOpportunityId, ContentVersion, SnapshotJson, ContentHash,
         CreatedByUserId, CreatedAtUtc)
    VALUES
        (@InsufficientId, 2, N'{"schema":"fase9a-boundary-v2"}',
         HASHBYTES('SHA2_256', N'fase9a-boundary-v2-' + @Suffix), @OwnerId, @RunNowUtc);
    UPDATE dbo.FundingPlatform_FundingOpportunities
    SET MinimumOperatingYears = 2, ContentVersion = 2,
        UpdatedAtUtc = DATEADD(SECOND, 5, UpdatedAtUtc)
    WHERE Id = @InsufficientId;
    UPDATE dbo.FundingPlatform_FundingOpportunities
    SET UpdatedAtUtc = DATEADD(SECOND, 5, UpdatedAtUtc)
    WHERE Id = @CompatibleId;
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMatchingRunSummaries(@RunNowUtc)
        WHERE MatchRunId = @RunId AND IsCurrent = 0)
        THROW 54016, N'Catalog drift did not mark the run stale.', 1;

    /* Exact-key replay remains durable after project readiness is disabled. */
    UPDATE dbo.FundingPlatform_Projects
    SET PublicationStatus = 4, IsActive = 0
    WHERE Id = @ProjectId;
    DELETE FROM @RunRows;
    INSERT INTO @RunRows
    EXEC dbo.FundingPlatform_usp_ProjectMatchingRun_Create
        @UserPublicId = @OwnerPublicId,
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @IdempotencyKeyHash = @IdempotencyKey,
        @RequestHash = @RequestHash,
        @NowUtc = @RunNowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @RunRows
        WHERE RunPublicId = @RunPublicId AND WasReplay = 1 AND IsCurrent = 0)
        THROW 54025, N'Stale historical input did not replay before mutable readiness checks.', 1;
    UPDATE dbo.FundingPlatform_Projects
    SET PublicationStatus = 0, IsActive = 1
    WHERE Id = @ProjectId;

    DECLARE @ThirdKey BINARY(32) =
        HASHBYTES('SHA2_256', N'fase9a-third-idempotency-' + @Suffix);
    DELETE FROM @RunRows;
    INSERT INTO @RunRows
    EXEC dbo.FundingPlatform_usp_ProjectMatchingRun_Create
        @UserPublicId = @OwnerPublicId,
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @IdempotencyKeyHash = @ThirdKey,
        @RequestHash = @RequestHash,
        @NowUtc = @RunNowUtc;
    DECLARE @SecondRunPublicId UNIQUEIDENTIFIER = (SELECT RunPublicId FROM @RunRows);
    DECLARE @SecondRunId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_ProjectMatchingRuns
         WHERE PublicId = @SecondRunPublicId);
    IF @SecondRunId IS NULL OR @SecondRunId = @RunId
       OR NOT EXISTS (SELECT 1 FROM @RunRows WHERE WasReplay = 0 AND IsCurrent = 1)
       OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectFundingMatches
                  WHERE MatchRunId = @RunId AND IsCurrent = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectFundingMatches
                      WHERE MatchRunId = @SecondRunId AND IsCurrent = 1)
        THROW 54019, N'A changed fingerprint did not create and supersede exactly one run.', 1;

    IF NOT EXISTS
       (SELECT 1
        FROM dbo.FundingPlatform_ProjectFundingMatches AS matches
        INNER JOIN dbo.FundingPlatform_ProjectFundingMatchRuleResults AS results
            ON results.MatchId = matches.Id
        INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
            ON rules.Id = results.MatchingRuleId
        WHERE matches.MatchRunId = @SecondRunId
          AND matches.FundingOpportunityId = @InsufficientId
          AND rules.Code = N'operating_years'
          AND results.Outcome = 3 AND results.DataState = 1
          AND results.ReasonCode = N'operating_years.boundary_unknown'
          AND results.EvidenceJson IS NULL)
        THROW 54026, N'EstablishedYear boundary was asserted as an exact pass/fail.', 1;

    /* Physical FK proof: a request row cannot point at a run from another
       organization/project even if all scalar IDs are individually valid. */
    DECLARE @TenantFkError INT = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        INSERT INTO dbo.FundingPlatform_ProjectMatchingRunRequests
            (UserId, OrganizationId, ProjectId, IdempotencyKeyHash,
             RequestHash, MatchRunId, CreatedAtUtc)
        VALUES
            (@OtherId, @OtherOrganizationId, @OtherProjectId,
             HASHBYTES('SHA2_256', N'fase9a-cross-key-' + @Suffix),
             HASHBYTES('SHA2_256', N'fase9a-cross-request-' + @Suffix),
             @RunId, @RunNowUtc);
    END TRY
    BEGIN CATCH
        SET @TenantFkError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;
    IF @TenantFkError <> 547 OR XACT_STATE() <> 1
        THROW 54017, N'Cross-tenant run request was not rejected by a composite FK.', 1;

    /* Published config cannot be relabelled after historical runs pin it. */
    DECLARE @ImmutableError INT = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        UPDATE dbo.FundingPlatform_MatchingProfiles
        SET EngineVersion = N'forbidden-drift'
        WHERE Id = @ProfileId;
    END TRY
    BEGIN CATCH
        SET @ImmutableError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;
    IF @ImmutableError <> 52406 OR XACT_STATE() <> 1
        THROW 54018, N'Published matching configuration was mutable.', 1;

    /* Deactivation cannot reopen a ruleset already pinned by history. Only an
       inactive, never-used profile may still be bootstrapped before activation. */
    UPDATE dbo.FundingPlatform_MatchingProfiles SET IsActive = 0 WHERE Id = @ProfileId;
    INSERT INTO dbo.FundingPlatform_MatchingRules
        (Code, Name, HandlerVersion, IsHardGate, IsActive, CreatedAtUtc)
    VALUES
        (N'smoke_config_' + @Suffix, N'Forbidden historical extension',
         N'v1', 0, 1, @RunNowUtc);
    DECLARE @ExtraRuleId INT = CONVERT(INT, SCOPE_IDENTITY());
    SET @ImmutableError = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        INSERT INTO dbo.FundingPlatform_MatchingRuleWeights
            (MatchingProfileId, MatchingRuleId, Weight, ParametersJson)
        VALUES
            (@ProfileId, @ExtraRuleId, 0,
             N'{"unknownPolicy":"zero-no-renormalization"}');
    END TRY
    BEGIN CATCH
        SET @ImmutableError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;
    IF @ImmutableError <> 52406 OR XACT_STATE() <> 1
        THROW 54032, N'An inactive historical matching profile accepted new rule weights.', 1;
    UPDATE dbo.FundingPlatform_MatchingProfiles SET IsActive = 1 WHERE Id = @ProfileId;

    DECLARE @HistoryMutationError INT = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        UPDATE dbo.FundingPlatform_ProjectMatchingRuns
        SET CatalogSnapshotAtUtc = DATEADD(MILLISECOND, 1, CatalogSnapshotAtUtc)
        WHERE Id = @SecondRunId;
    END TRY
    BEGIN CATCH
        SET @HistoryMutationError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;
    IF @HistoryMutationError <> 52406 OR XACT_STATE() <> 1
        THROW 54020, N'Completed matching run history was mutable.', 1;

    SET @HistoryMutationError = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        UPDATE dbo.FundingPlatform_ProjectFundingMatches
        SET CompatibilityScore = CASE WHEN CompatibilityScore = 100 THEN 99 ELSE 100 END
        WHERE MatchRunId = @SecondRunId AND FundingOpportunityId = @CompatibleId;
    END TRY
    BEGIN CATCH
        SET @HistoryMutationError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;
    IF @HistoryMutationError <> 52406 OR XACT_STATE() <> 1
        THROW 54021, N'Persisted match score/snapshot history was mutable.', 1;

    DECLARE @SecondCompatibleMatchId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_ProjectFundingMatches
         WHERE MatchRunId = @SecondRunId AND FundingOpportunityId = @CompatibleId);
    SET @HistoryMutationError = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        UPDATE dbo.FundingPlatform_ProjectFundingMatchRuleResults
        SET ReasonCode = N'forbidden.reason'
        WHERE MatchId = @SecondCompatibleMatchId;
    END TRY
    BEGIN CATCH
        SET @HistoryMutationError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;
    IF @HistoryMutationError <> 52406 OR XACT_STATE() <> 1
        THROW 54022, N'Persisted rule-result history was mutable.', 1;

    SET @HistoryMutationError = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        UPDATE dbo.FundingPlatform_ProjectMatchingRunRequests
        SET RequestHash = HASHBYTES('SHA2_256', N'forbidden-request-drift')
        WHERE MatchRunId = @SecondRunId;
    END TRY
    BEGIN CATCH
        SET @HistoryMutationError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;
    IF @HistoryMutationError <> 52406 OR XACT_STATE() <> 1
        THROW 54023, N'Idempotency request ledger was mutable.', 1;

    SET @HistoryMutationError = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        DELETE FROM dbo.FundingPlatform_ProjectFundingMatchRuleResults
        WHERE MatchId = @SecondCompatibleMatchId;
    END TRY
    BEGIN CATCH
        SET @HistoryMutationError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;
    IF @HistoryMutationError <> 52406 OR XACT_STATE() <> 1
        THROW 54024, N'Deterministic rule-result history could be deleted.', 1;

    /* A coherent project rename/version/archive must stale, never relabel, the
       historical run; exact-key replay still returns its frozen project names. */
    DECLARE @OriginalProjectSlug NVARCHAR(180) =
        (SELECT Slug FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId);
    DECLARE @OriginalProjectTitle NVARCHAR(250) =
        (SELECT Title FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId);
    INSERT INTO dbo.FundingPlatform_ProjectVersions
        (ProjectId, ProjectVersion, SnapshotJson, ContentHash, CreatedByUserId, CreatedAtUtc)
    VALUES
        (@ProjectId, 2, N'{"schema":"fase9a-project-v2"}',
         HASHBYTES('SHA2_256', N'fase9a-project-v2-' + @Suffix), @OwnerId, @RunNowUtc);
    UPDATE dbo.FundingPlatform_Projects
    SET Slug = N'fase9a-renamed-' + @Suffix,
        Title = N'Forbidden live relabel ' + @Suffix,
        ProjectVersion = 2, PublicationStatus = 4, IsActive = 0,
        UpdatedAtUtc = DATEADD(SECOND, 10, UpdatedAtUtc)
    WHERE Id = @ProjectId;

    DELETE FROM @RunRows;
    INSERT INTO @RunRows
    EXEC dbo.FundingPlatform_usp_ProjectMatchingRun_Create
        @UserPublicId = @OwnerPublicId,
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @IdempotencyKeyHash = @IdempotencyKey,
        @RequestHash = @RequestHash,
        @NowUtc = @RunNowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @RunRows
        WHERE RunPublicId = @RunPublicId AND WasReplay = 1 AND IsCurrent = 0
          AND ProjectSlug = @OriginalProjectSlug
          AND ProjectTitle = @OriginalProjectTitle)
        THROW 54027, N'Live project rename/archive relabelled or blocked historical replay.', 1;

    DECLARE @BeforeConflictRunCount BIGINT =
        (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_ProjectMatchingRuns
         WHERE ProjectId = @ProjectId);
    DECLARE @BeforeConflictRequestCount BIGINT =
        (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_ProjectMatchingRunRequests
         WHERE ProjectId = @ProjectId);
    DECLARE @IdempotencyConflictError INT = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_ProjectMatchingRun_Create
            @UserPublicId = @OwnerPublicId,
            @OrganizationPublicId = @OrganizationPublicId,
            @ProjectPublicId = @ProjectPublicId,
            @IdempotencyKeyHash = @IdempotencyKey,
            @RequestHash = 0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA,
            @NowUtc = @RunNowUtc;
    END TRY
    BEGIN CATCH
        SET @IdempotencyConflictError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;
    IF @IdempotencyConflictError <> 52403 OR XACT_STATE() <> 1
       OR @BeforeConflictRunCount <>
          (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_ProjectMatchingRuns
           WHERE ProjectId = @ProjectId)
       OR @BeforeConflictRequestCount <>
          (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_ProjectMatchingRunRequests
           WHERE ProjectId = @ProjectId)
        THROW 54028, N'Idempotency-key hash conflict was not durable and side-effect free.', 1;

    DECLARE @TenantAccessError INT = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_ProjectMatchingRun_List
            @UserPublicId = @OtherPublicId,
            @OrganizationPublicId = @OrganizationPublicId,
            @ProjectPublicId = @ProjectPublicId,
            @PageNumber = 1, @PageSize = 20, @NowUtc = @RunNowUtc;
    END TRY
    BEGIN CATCH SET @TenantAccessError = ERROR_NUMBER(); END CATCH;
    IF @TenantAccessError <> 52401 OR XACT_STATE() <> 1
        THROW 54029, N'Foreign tenant listed matching history.', 1;

    SET @TenantAccessError = 0;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_ProjectMatchingRun_Get
            @UserPublicId = @OtherPublicId,
            @OrganizationPublicId = @OrganizationPublicId,
            @ProjectPublicId = @ProjectPublicId,
            @RunPublicId = @RunPublicId,
            @NowUtc = @RunNowUtc;
    END TRY
    BEGIN CATCH SET @TenantAccessError = ERROR_NUMBER(); END CATCH;
    IF @TenantAccessError <> 52401 OR XACT_STATE() <> 1
        THROW 54030, N'Foreign tenant read matching detail.', 1;

    SET @TenantAccessError = 0;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_ProjectMatchingRun_Create
            @UserPublicId = @OtherPublicId,
            @OrganizationPublicId = @OrganizationPublicId,
            @ProjectPublicId = @ProjectPublicId,
            @IdempotencyKeyHash = 0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB,
            @RequestHash = @RequestHash,
            @NowUtc = @RunNowUtc;
    END TRY
    BEGIN CATCH SET @TenantAccessError = ERROR_NUMBER(); END CATCH;
    SET XACT_ABORT ON;
    IF @TenantAccessError <> 52401 OR XACT_STATE() <> 1
        THROW 54031, N'Foreign tenant created a matching run.', 1;

    /* Compile all three wire procedures with their final rowset shapes. */
    EXEC dbo.FundingPlatform_usp_ProjectMatchingRun_List
        @UserPublicId = @OwnerPublicId,
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @PageNumber = 1, @PageSize = 20, @NowUtc = @RunNowUtc;
    EXEC dbo.FundingPlatform_usp_ProjectMatchingRun_Get
        @UserPublicId = @OwnerPublicId,
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @RunPublicId = @RunPublicId,
        @NowUtc = @RunNowUtc;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke020;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
    BEGIN
        IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
        ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke020;
    END;
    THROW;
END CATCH;

PRINT N'FASE 9A deterministic project matching smoke passed.';
