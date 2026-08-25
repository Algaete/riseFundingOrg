/* Transactional FASE 8B smoke: public marketplace, tenant applications and derived calendar. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_FundingApplications', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_FundingApplicationCreateRequests', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ifn_OrganizationMarketplaceReady', N'IF') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ifn_ProjectMarketplaceReady', N'IF') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMarketplace_Search', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMarketplace_GetBySlug', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_OrganizationMarketplace_Get', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_FundingApplication_List', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_FundingApplication_Get', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_FundingApplication_Create', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_FundingApplication_Update', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_OrganizationCalendar_List', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre019', N'P') IS NULL
    THROW 53901, N'FASE 8B objects are incomplete.', 1;

IF NOT EXISTS
   (SELECT 1 FROM sys.foreign_keys
    WHERE parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_FundingApplications')
      AND name = N'FundingPlatform_FK_FundingApplications_ProjectOrganization')
   OR NOT EXISTS
   (SELECT 1 FROM sys.foreign_keys
    WHERE parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_FundingApplications')
      AND name = N'FundingPlatform_FK_FundingApplications_OwnerMembership')
   OR NOT EXISTS
   (SELECT 1 FROM sys.key_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_FundingApplications')
      AND name = N'FundingPlatform_UQ_FundingApplications_OrganizationProjectOpportunity')
    THROW 53902, N'Application tenant or uniqueness constraints are missing.', 1;

DECLARE @MarketplaceDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMarketplace_Search'));
DECLARE @DetailDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMarketplace_GetBySlug'));
DECLARE @LegacyDetailDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_Project_Public_GetBySlug'));
DECLARE @CalendarDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_OrganizationCalendar_List'));
DECLARE @OutboxDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge'));
IF @MarketplaceDefinition NOT LIKE N'%funding-gap-desc%'
   OR @MarketplaceDefinition NOT LIKE N'%projects.Currency = @NormalizedCurrency%'
   OR @MarketplaceDefinition NOT LIKE N'%@NormalizedSort = N''funding-gap-desc'' AND @NormalizedCurrency IS NULL%'
   OR @DetailDefinition NOT LIKE N'%FundingPlatform_ifn_ProjectMarketplaceReady%'
   OR @LegacyDetailDefinition NOT LIKE N'%FundingPlatform_usp_ProjectMarketplace_GetBySlug%'
   OR @CalendarDefinition NOT LIKE N'%applications.Status <> 5%'
   OR @OutboxDefinition NOT LIKE N'%FundingApplicationCreated%'
   OR @OutboxDefinition NOT LIKE N'%FundingApplicationUpdated%'
    THROW 53903, N'FASE 8B guards, currency ordering, calendar or outbox contract drifted.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke019;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @Suffix NVARCHAR(32) = REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'');
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @TodayUtc DATE = CONVERT(DATE, @NowUtc);
    DECLARE @ExactCloseAtUtc DATETIME2(3) = DATEADD(DAY, 15, @NowUtc);
    DECLARE @ExactCloseDate DATE = CONVERT(DATE, @ExactCloseAtUtc);
    DECLARE @CategoryId INT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_FundingCategories WHERE IsActive = 1 ORDER BY Id);
    DECLARE @BeneficiaryTypeId INT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_BeneficiaryTypes WHERE IsActive = 1 ORDER BY Id);
    DECLARE @ProjectTypeId INT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_ProjectTypes WHERE IsActive = 1 ORDER BY Id);
    DECLARE @SourceId INT =
        (SELECT Id FROM dbo.FundingPlatform_FundingSources
         WHERE Name = N'Manual editorial' AND IsEnabled = 1);
    IF @CategoryId IS NULL OR @BeneficiaryTypeId IS NULL OR @ProjectTypeId IS NULL
       OR @SourceId IS NULL
        THROW 53904, N'Required active catalog fixtures are missing.', 1;

    DECLARE @AdminPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @MemberPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ViewerPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @OtherPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @OrgPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @OtherOrgPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @IncompleteOrgPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @AdminEmail NVARCHAR(320) = N'fase8b-admin-' + @Suffix + N'@example.invalid';
    DECLARE @MemberEmail NVARCHAR(320) = N'fase8b-member-' + @Suffix + N'@example.invalid';
    DECLARE @ViewerEmail NVARCHAR(320) = N'fase8b-viewer-' + @Suffix + N'@example.invalid';
    DECLARE @OtherEmail NVARCHAR(320) = N'fase8b-other-' + @Suffix + N'@example.invalid';

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash,
         SecurityStamp, EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@AdminPublicId, @AdminEmail, UPPER(@AdminEmail), N'FASE 8B admin',
         N'not-a-credential', N'fase8b-admin', 1, 0, 2, N'es-CL'),
        (@MemberPublicId, @MemberEmail, UPPER(@MemberEmail), N'FASE 8B member',
         N'not-a-credential', N'fase8b-member', 1, 0, 2, N'es-CL'),
        (@ViewerPublicId, @ViewerEmail, UPPER(@ViewerEmail), N'FASE 8B viewer',
         N'not-a-credential', N'fase8b-viewer', 1, 0, 2, N'es-CL'),
        (@OtherPublicId, @OtherEmail, UPPER(@OtherEmail), N'FASE 8B other',
         N'not-a-credential', N'fase8b-other', 1, 0, 2, N'es-CL');
    DECLARE @AdminId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @AdminPublicId);
    DECLARE @MemberId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @MemberPublicId);
    DECLARE @ViewerId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @ViewerPublicId);
    DECLARE @OtherId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @OtherPublicId);

    INSERT INTO dbo.FundingPlatform_Organizations
        (PublicId, CreatedByUserId, Name, HomeCountryId, OrganizationTypeId,
         WebsiteUrl, Description, EstablishedYear, ProfileStatus, ProfileCompleteness)
    VALUES
        (@OrgPublicId, @AdminId, N'FASE 8B organization ' + @Suffix, 152, 1,
         N'fase8b.example.invalid', N'Public safe description', 2020, 2, 100),
        (@OtherOrgPublicId, @OtherId, N'FASE 8B other org ' + @Suffix, 152, 1,
         NULL, N'Other tenant', 2021, 2, 100),
        (@IncompleteOrgPublicId, @OtherId, N'FASE 8B incomplete org ' + @Suffix, 152, 1,
         NULL, N'Incomplete', 2022, 1, 70);
    DECLARE @OrgId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Organizations WHERE PublicId = @OrgPublicId);
    DECLARE @OtherOrgId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Organizations WHERE PublicId = @OtherOrgPublicId);
    DECLARE @IncompleteOrgId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Organizations WHERE PublicId = @IncompleteOrgPublicId);

    INSERT INTO dbo.FundingPlatform_OrganizationUsers
        (OrganizationId, UserId, Role, MembershipStatus, JoinedAtUtc)
    VALUES
        (@OrgId, @AdminId, 1, 1, @NowUtc),
        (@OrgId, @MemberId, 2, 1, @NowUtc),
        (@OrgId, @ViewerId, 2, 1, @NowUtc),
        (@OtherOrgId, @OtherId, 1, 1, @NowUtc),
        (@IncompleteOrgId, @OtherId, 1, 1, @NowUtc);

    DECLARE @PublishedOnePublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @PublishedTwoPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @DraftPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @RejectedPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @IncompletePublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @OtherProjectPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ArchivedPublicId UNIQUEIDENTIFIER = NEWID();

    INSERT INTO dbo.FundingPlatform_Projects
        (PublicId, OrganizationId, CreatedByUserId, Slug, Title, Summary, Description,
         ProjectStatus, PublicationStatus, StartDate, EndDate, BudgetTotal,
         ConfirmedFunding, Currency, ProjectVersion, IsActive, CreatedAtUtc, UpdatedAtUtc,
         SubmittedAtUtc, PublishedAtUtc, ReviewedAtUtc, ReviewedByUserId, RejectionReason)
    VALUES
        (@PublishedOnePublicId, @OrgId, @AdminId, N'fase8b-alpha-' + @Suffix,
         N'Alpha climate ' + @Suffix, N'Alpha summary', N'Alpha description', 1, 2,
         DATEADD(DAY, 5, @TodayUtc), DATEADD(DAY, 30, @TodayUtc), 1000, 200, 'USD',
         1, 1, @NowUtc, DATEADD(MINUTE, -1, @NowUtc), DATEADD(DAY, -3, @NowUtc),
         DATEADD(DAY, -2, @NowUtc), DATEADD(DAY, -2, @NowUtc), @AdminId, NULL),
        (@PublishedTwoPublicId, @OrgId, @AdminId, N'fase8b-beta-' + @Suffix,
         N'Beta education ' + @Suffix, N'Beta summary', N'Beta description', 2, 2,
         DATEADD(DAY, 40, @TodayUtc), DATEADD(DAY, 80, @TodayUtc), 1000, 600, 'USD',
         1, 1, @NowUtc, DATEADD(MINUTE, -2, @NowUtc), DATEADD(DAY, -4, @NowUtc),
         DATEADD(DAY, -3, @NowUtc), DATEADD(DAY, -3, @NowUtc), @AdminId, NULL),
        (@DraftPublicId, @OrgId, @AdminId, N'fase8b-draft-' + @Suffix,
         N'Draft project ' + @Suffix, N'Draft summary', N'Draft description', 0, 0,
         DATEADD(DAY, 90, @TodayUtc), DATEADD(DAY, 120, @TodayUtc), 500, 0, 'USD',
         1, 1, @NowUtc, @NowUtc, NULL, NULL, NULL, NULL, NULL),
        (@RejectedPublicId, @OrgId, @AdminId, N'fase8b-rejected-' + @Suffix,
         N'Rejected project ' + @Suffix, N'Rejected summary', N'Rejected description', 0, 3,
         NULL, NULL, 500, 0, 'USD', 1, 1, @NowUtc, @NowUtc,
         DATEADD(DAY, -3, @NowUtc), NULL, DATEADD(DAY, -2, @NowUtc), @AdminId, N'Fixture rejection'),
        (@IncompletePublicId, @IncompleteOrgId, @OtherId, N'fase8b-incomplete-' + @Suffix,
         N'Incomplete organization project ' + @Suffix, N'Hidden summary', N'Hidden description',
         0, 2, NULL, NULL, 500, 0, 'USD', 1, 1, @NowUtc, @NowUtc,
         DATEADD(DAY, -3, @NowUtc), DATEADD(DAY, -2, @NowUtc),
         DATEADD(DAY, -2, @NowUtc), @OtherId, NULL),
        (@OtherProjectPublicId, @OtherOrgId, @OtherId, N'fase8b-other-' + @Suffix,
         N'Other tenant project ' + @Suffix, N'Other summary', N'Other description', 0, 0,
         NULL, NULL, 500, 0, 'USD', 1, 1, @NowUtc, @NowUtc,
         NULL, NULL, NULL, NULL, NULL),
        (@ArchivedPublicId, @OrgId, @AdminId, N'fase8b-archived-' + @Suffix,
         N'Archived project ' + @Suffix, N'Archived summary', N'Archived description', 6, 4,
         NULL, NULL, 500, 0, 'USD', 1, 1, @NowUtc, @NowUtc,
         NULL, NULL, NULL, NULL, NULL);

    DECLARE @PublicProjects TABLE (ProjectId BIGINT NOT NULL PRIMARY KEY);
    INSERT INTO @PublicProjects (ProjectId)
    SELECT Id FROM dbo.FundingPlatform_Projects
    WHERE PublicId IN (@PublishedOnePublicId, @PublishedTwoPublicId, @IncompletePublicId);
    INSERT INTO dbo.FundingPlatform_ProjectCountries (ProjectId, CountryId)
        SELECT ProjectId, 152 FROM @PublicProjects;
    INSERT INTO dbo.FundingPlatform_ProjectCategories (ProjectId, FundingCategoryId)
        SELECT ProjectId, @CategoryId FROM @PublicProjects;
    INSERT INTO dbo.FundingPlatform_ProjectBeneficiaryTypes (ProjectId, BeneficiaryTypeId)
        SELECT ProjectId, @BeneficiaryTypeId FROM @PublicProjects;
    INSERT INTO dbo.FundingPlatform_ProjectProjectTypes (ProjectId, ProjectTypeId)
        SELECT ProjectId, @ProjectTypeId FROM @PublicProjects;

    IF (SELECT COUNT_BIG(1)
        FROM dbo.FundingPlatform_ifn_ProjectMarketplaceReady() AS ready
        INNER JOIN @PublicProjects AS fixtures ON fixtures.ProjectId = ready.ProjectId) <> 2
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMarketplaceReady() AS ready
           INNER JOIN dbo.FundingPlatform_Projects AS projects ON projects.Id = ready.ProjectId
           WHERE projects.PublicId IN
                 (@DraftPublicId, @RejectedPublicId, @IncompletePublicId, @ArchivedPublicId))
        THROW 53905, N'Draft, rejected, archived or incomplete-organization project became public.', 1;

    DECLARE @FunderPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @SponsorName NVARCHAR(300) = N'FASE 8B sponsor ' + @Suffix;
    INSERT INTO dbo.FundingPlatform_Funders
        (PublicId, Slug, Name, NormalizedName, WebsiteUrl,
         PublicationStatus, SubmittedAtUtc, PublishedAtUtc, ReviewedAtUtc,
         ContentVersion, IsActive, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@FunderPublicId, N'fase8b-funder-' + @Suffix, @SponsorName, UPPER(@SponsorName),
         N'https://fase8b-funder.example.invalid', 2, DATEADD(DAY, -3, @NowUtc),
         DATEADD(DAY, -2, @NowUtc), DATEADD(DAY, -2, @NowUtc),
         1, 1, @NowUtc, @NowUtc);
    DECLARE @FunderId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Funders WHERE PublicId = @FunderPublicId);

    DECLARE @OpportunityPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @FavoriteOpportunityPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ClosedOpportunityPublicId UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.FundingPlatform_FundingOpportunities
        (PublicId, Slug, Title, Description, Summary, SponsorName,
         IssuerCountryId, FundingTypeId, Currency, MinAmount, MaxAmount, AmountStatus,
         OpenDate, CloseDate, CloseAtUtc, DeadlineTimeZoneId, DeadlineType,
         DeadlinePrecision, EligibilityDescription, Requirements, GeographicScope,
         RemoteApplication, PublicationStatus, PublishedAtUtc, LastVerifiedAtUtc,
         DataQualityScore, ContentVersion, IsActive, ReviewedAtUtc, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@OpportunityPublicId, N'fase8b-opportunity-' + @Suffix,
         N'Exact deadline ' + @Suffix, N'Description', N'Summary', @SponsorName,
         152, 1, 'USD', 100, 1000, 1, DATEADD(DAY, -1, @TodayUtc),
         @ExactCloseDate, @ExactCloseAtUtc, N'UTC', 1, 2, N'Eligible', N'Requirements',
         1, 1, 2, DATEADD(DAY, -2, @NowUtc), @NowUtc, 100, 1, 1,
         DATEADD(DAY, -2, @NowUtc), @NowUtc, @NowUtc),
        (@FavoriteOpportunityPublicId, N'fase8b-favorite-' + @Suffix,
         N'Favorite deadline ' + @Suffix, N'Description', N'Summary', @SponsorName,
         152, 1, 'USD', 100, 1000, 1, DATEADD(DAY, -1, @TodayUtc),
         DATEADD(DAY, 25, @TodayUtc), NULL, NULL, 1, 1, N'Eligible', N'Requirements',
         1, 1, 2, DATEADD(DAY, -2, @NowUtc), @NowUtc, 100, 1, 1,
         DATEADD(DAY, -2, @NowUtc), @NowUtc, @NowUtc),
        (@ClosedOpportunityPublicId, N'fase8b-closed-' + @Suffix,
         N'Closed backfill ' + @Suffix, N'Description', N'Summary', @SponsorName,
         152, 1, 'USD', 100, 1000, 1, DATEADD(DAY, -30, @TodayUtc),
         DATEADD(DAY, -1, @TodayUtc), NULL, NULL, 1, 1, N'Eligible', N'Requirements',
         1, 1, 2, DATEADD(DAY, -2, @NowUtc), @NowUtc, 100, 1, 1,
         DATEADD(DAY, -2, @NowUtc), @NowUtc, @NowUtc);

    DECLARE @Opportunities TABLE
    (
        SequenceNumber INT NOT NULL PRIMARY KEY,
        PublicId UNIQUEIDENTIFIER NOT NULL,
        OpportunityId BIGINT NOT NULL
    );
    INSERT INTO @Opportunities (SequenceNumber, PublicId, OpportunityId)
    SELECT fixture.SequenceNumber, fixture.PublicId, opportunities.Id
    FROM (VALUES
          (1, @OpportunityPublicId),
          (2, @FavoriteOpportunityPublicId),
          (3, @ClosedOpportunityPublicId)) AS fixture(SequenceNumber, PublicId)
    INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
        ON opportunities.PublicId = fixture.PublicId;

    INSERT INTO dbo.FundingPlatform_FundingOpportunityCountries
        (FundingOpportunityId, CountryId)
        SELECT OpportunityId, 152 FROM @Opportunities;
    INSERT INTO dbo.FundingPlatform_FundingOpportunityCategories
        (FundingOpportunityId, FundingCategoryId)
        SELECT OpportunityId, @CategoryId FROM @Opportunities;
    INSERT INTO dbo.FundingPlatform_FundingOpportunityFunders
        (FundingOpportunityId, FunderId, Role, IsActive, CreatedAtUtc, UpdatedAtUtc)
        SELECT OpportunityId, @FunderId, 1, 1, @NowUtc, @NowUtc FROM @Opportunities;
    INSERT INTO dbo.FundingPlatform_FundingOpportunitySourceLinks
        (FundingOpportunityId, FundingSourceId, ExternalId, SourceItemKeyHash,
         SourceUrl, CanonicalUrlHash, FirstSeenAtUtc, LastSeenAtUtc, IsPrimary, IsActive)
    SELECT OpportunityId, @SourceId,
           N'fase8b-' + CONVERT(NVARCHAR(10), SequenceNumber) + N'-' + @Suffix,
           HASHBYTES('SHA2_256', N'fase8b-key-' +
                     CONVERT(NVARCHAR(10), SequenceNumber) + @Suffix),
           N'https://fase8b-source.example.invalid/' +
              CONVERT(NVARCHAR(10), SequenceNumber) + N'/' + @Suffix,
           HASHBYTES('SHA2_256', N'fase8b-url-' +
                     CONVERT(NVARCHAR(10), SequenceNumber) + @Suffix),
           @NowUtc, @NowUtc, 1, 1
    FROM @Opportunities;
    INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
        (FundingOpportunityId, FieldPath, ValueJson, ExtractionMethod,
         IsSelected, IsManualLock, CreatedAtUtc)
    SELECT opportunities.OpportunityId, paths.FieldPath,
           N'{"status":"known","value":"phase8b"}', 1, 1, 0, @NowUtc
    FROM @Opportunities AS opportunities
    CROSS JOIN (VALUES (N'/title'), (N'/description'),
                       (N'/eligibilityDescription'), (N'/closeDate')) AS paths(FieldPath);

    IF (SELECT COUNT_BIG(1)
        FROM dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
        INNER JOIN @Opportunities AS fixtures
            ON fixtures.OpportunityId = ready.FundingOpportunityId) <> 3
        THROW 53906, N'Application opportunity fixtures are not public-ready.', 1;

    DECLARE @CountryIds dbo.FundingPlatform_SmallIntIdList;
    DECLARE @CategoryIds dbo.FundingPlatform_IntIdList;
    DECLARE @ProjectTypeIds dbo.FundingPlatform_IntIdList;
    DECLARE @Matched BIGINT;
    EXEC dbo.FundingPlatform_usp_ProjectMarketplace_Search
        @Sort = N'newest', @PageNumber = 1, @PageSize = 1,
        @CountryIds = @CountryIds, @CategoryIds = @CategoryIds,
        @ProjectTypeIds = @ProjectTypeIds, @MatchedCount = @Matched OUTPUT;
    IF @Matched <> 2 THROW 53907, N'Marketplace paging exposed non-public projects.', 1;

    EXEC dbo.FundingPlatform_usp_ProjectMarketplace_Search
        @Query = N'Alpha climate', @ProjectStatus = 1, @Currency = 'USD',
        @Sort = N'funding-gap-desc', @PageNumber = 1, @PageSize = 20,
        @CountryIds = @CountryIds, @CategoryIds = @CategoryIds,
        @ProjectTypeIds = @ProjectTypeIds, @MatchedCount = @Matched OUTPUT;
    IF @Matched <> 1 THROW 53908, N'Marketplace text/status/currency filters drifted.', 1;

    INSERT INTO @CountryIds VALUES (152);
    INSERT INTO @CategoryIds VALUES (@CategoryId), (2147483000);
    INSERT INTO @ProjectTypeIds VALUES (@ProjectTypeId);
    EXEC dbo.FundingPlatform_usp_ProjectMarketplace_Search
        @Currency = 'USD', @Sort = N'funding-gap-desc', @PageNumber = 2, @PageSize = 1,
        @CountryIds = @CountryIds, @CategoryIds = @CategoryIds,
        @ProjectTypeIds = @ProjectTypeIds, @MatchedCount = @Matched OUTPUT;
    IF @Matched <> 2
        THROW 53909, N'Marketplace taxonomy/pagination or currency-safe ordering drifted.', 1;

    DECLARE @MarketplaceError INT = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_ProjectMarketplace_Search
            @Sort = N'funding-gap-desc',
            @CountryIds = @CountryIds, @CategoryIds = @CategoryIds,
            @ProjectTypeIds = @ProjectTypeIds, @MatchedCount = @Matched OUTPUT;
    END TRY
    BEGIN CATCH SET @MarketplaceError = ERROR_NUMBER(); END CATCH;
    SET XACT_ABORT ON;
    IF @MarketplaceError <> 52102 OR XACT_STATE() <> 1
        THROW 53910, N'Cross-currency funding-gap sort was not rejected.', 1;

    SET @MarketplaceError = 0;
    DECLARE @OversizedQuery NVARCHAR(300) = REPLICATE(N'x', 201);
    SET XACT_ABORT OFF;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_ProjectMarketplace_Search
            @Query = @OversizedQuery, @Sort = N'newest',
            @CountryIds = @CountryIds, @CategoryIds = @CategoryIds,
            @ProjectTypeIds = @ProjectTypeIds, @MatchedCount = @Matched OUTPUT;
    END TRY
    BEGIN CATCH SET @MarketplaceError = ERROR_NUMBER(); END CATCH;
    SET XACT_ABORT ON;
    IF @MarketplaceError <> 52102 OR XACT_STATE() <> 1
        THROW 53911, N'Oversized marketplace query was accepted.', 1;

    DECLARE @TooManyCategoryIds dbo.FundingPlatform_IntIdList;
    INSERT INTO @TooManyCategoryIds (Id)
    SELECT TOP (51) 100000 + CONVERT(INT, ROW_NUMBER() OVER (ORDER BY object_id))
    FROM sys.all_objects;
    SET @MarketplaceError = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_ProjectMarketplace_Search
            @Sort = N'newest', @CountryIds = @CountryIds,
            @CategoryIds = @TooManyCategoryIds, @ProjectTypeIds = @ProjectTypeIds,
            @MatchedCount = @Matched OUTPUT;
    END TRY
    BEGIN CATCH SET @MarketplaceError = ERROR_NUMBER(); END CATCH;
    SET XACT_ABORT ON;
    IF @MarketplaceError <> 52102 OR XACT_STATE() <> 1
        THROW 53942, N'Marketplace accepted more than 50 values for a filter.', 1;

    /* Runtime compile all public detail/profile rowsets. Direct guard assertions
       above verify the no-row behavior for non-ready organizations/projects. */
    DECLARE @PublishedOneSlug NVARCHAR(180) = N'fase8b-alpha-' + @Suffix;
    EXEC dbo.FundingPlatform_usp_ProjectMarketplace_GetBySlug @Slug = @PublishedOneSlug;
    EXEC dbo.FundingPlatform_usp_Project_Public_GetBySlug @Slug = @PublishedOneSlug;
    EXEC dbo.FundingPlatform_usp_OrganizationMarketplace_Get
        @OrganizationPublicId = @OrgPublicId;

    DECLARE @Mutations TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), FundingApplicationPublicId UNIQUEIDENTIFIER NULL,
        Status TINYINT NULL, OwnerUserPublicId UNIQUEIDENTIFIER NULL,
        RowVersion BINARY(8) NULL, CreatedAtUtc DATETIME2(3) NULL,
        UpdatedAtUtc DATETIME2(3) NULL, WasReplay BIT
    );
    DECLARE @MainKey BINARY(32) = HASHBYTES('SHA2_256', N'fase8b-main-key-' + @Suffix);
    DECLARE @MainRequest BINARY(32) = HASHBYTES('SHA2_256', N'fase8b-main-request-' + @Suffix);
    DECLARE @MainApplicationDate DATE = DATEADD(DAY, 10, @TodayUtc);
    DECLARE @MainResultDate DATE = DATEADD(DAY, 20, @TodayUtc);
    DECLARE @ConflictingRequest BINARY(32) =
        HASHBYTES('SHA2_256', N'fase8b-conflicting-request-' + @Suffix);
    DECLARE @OtherKey BINARY(32) = HASHBYTES('SHA2_256', N'fase8b-other-key-' + @Suffix);
    INSERT INTO @Mutations
    EXEC dbo.FundingPlatform_usp_FundingApplication_Create
        @UserPublicId = @AdminPublicId, @OrganizationPublicId = @OrgPublicId,
        @ProjectPublicId = @PublishedOnePublicId,
        @FundingOpportunityPublicId = @OpportunityPublicId,
        @Notes = N'Private notes', @ApplicationDate = @MainApplicationDate,
        @RequestedAmount = 250, @Currency = 'USD',
        @ResultDate = @MainResultDate,
        @IdempotencyKeyHash = @MainKey, @RequestHash = @MainRequest;
    DECLARE @MainApplicationPublicId UNIQUEIDENTIFIER =
        (SELECT FundingApplicationPublicId FROM @Mutations WHERE Code = N'created');
    DECLARE @MainRowVersion BINARY(8) =
        (SELECT RowVersion FROM @Mutations WHERE Code = N'created');
    IF @MainApplicationPublicId IS NULL OR @MainRowVersion IS NULL
        THROW 53912, N'Funding application was not created.', 1;

    DELETE FROM @Mutations;
    DECLARE @CrossKey BINARY(32) = HASHBYTES('SHA2_256', N'fase8b-cross-key-' + @Suffix);
    DECLARE @CrossRequest BINARY(32) =
        HASHBYTES('SHA2_256', N'fase8b-cross-request-' + @Suffix);
    INSERT INTO @Mutations
    EXEC dbo.FundingPlatform_usp_FundingApplication_Create
        @UserPublicId = @AdminPublicId, @OrganizationPublicId = @OrgPublicId,
        @ProjectPublicId = @PublishedOnePublicId,
        @FundingOpportunityPublicId = @OpportunityPublicId,
        @Notes = N'Private notes', @ApplicationDate = @MainApplicationDate,
        @RequestedAmount = 250, @Currency = 'USD',
        @ResultDate = @MainResultDate,
        @IdempotencyKeyHash = @MainKey, @RequestHash = @MainRequest;
    IF NOT EXISTS
       (SELECT 1 FROM @Mutations
        WHERE Succeeded = 1 AND Code = N'replayed' AND WasReplay = 1
          AND FundingApplicationPublicId = @MainApplicationPublicId
          AND RowVersion = @MainRowVersion)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_FundingApplications
           WHERE OrganizationId = @OrgId AND ProjectId =
                 (SELECT Id FROM dbo.FundingPlatform_Projects
                  WHERE PublicId = @PublishedOnePublicId)
             AND FundingOpportunityId =
                 (SELECT OpportunityId FROM @Opportunities
                  WHERE PublicId = @OpportunityPublicId)) <> 1
        THROW 53913, N'Durable create replay duplicated or changed its response.', 1;

    DELETE FROM @Mutations;
    INSERT INTO @Mutations
    EXEC dbo.FundingPlatform_usp_FundingApplication_Create
        @UserPublicId = @AdminPublicId, @OrganizationPublicId = @OrgPublicId,
        @ProjectPublicId = @PublishedOnePublicId,
        @FundingOpportunityPublicId = @OpportunityPublicId,
        @Notes = N'Changed request', @ApplicationDate = @MainApplicationDate,
        @RequestedAmount = 250, @Currency = 'USD',
        @ResultDate = @MainResultDate,
        @IdempotencyKeyHash = @MainKey,
        @RequestHash = @ConflictingRequest;
    IF NOT EXISTS (SELECT 1 FROM @Mutations WHERE Succeeded = 0 AND Code = N'idempotency-conflict')
        THROW 53914, N'Idempotency-key payload conflict was not rejected.', 1;

    DELETE FROM @Mutations;
    INSERT INTO @Mutations
    EXEC dbo.FundingPlatform_usp_FundingApplication_Create
        @UserPublicId = @AdminPublicId, @OrganizationPublicId = @OrgPublicId,
        @ProjectPublicId = @PublishedOnePublicId,
        @FundingOpportunityPublicId = @OpportunityPublicId,
        @Notes = N'Private notes', @ApplicationDate = @MainApplicationDate,
        @RequestedAmount = 250, @Currency = 'USD',
        @ResultDate = @MainResultDate,
        @IdempotencyKeyHash = @OtherKey,
        @RequestHash = @MainRequest;
    IF NOT EXISTS (SELECT 1 FROM @Mutations WHERE Succeeded = 0 AND Code = N'already-exists')
        THROW 53915, N'Organization/project/opportunity uniqueness was not surfaced safely.', 1;

    /* A closed but still public-ready opportunity is valid for historical backfill. */
    DECLARE @ClosedKey BINARY(32) = HASHBYTES('SHA2_256', N'fase8b-closed-key-' + @Suffix);
    DECLARE @ClosedRequest BINARY(32) = HASHBYTES('SHA2_256', N'fase8b-closed-request-' + @Suffix);
    DELETE FROM @Mutations;
    INSERT INTO @Mutations
    EXEC dbo.FundingPlatform_usp_FundingApplication_Create
        @UserPublicId = @MemberPublicId, @OrganizationPublicId = @OrgPublicId,
        @ProjectPublicId = @PublishedTwoPublicId,
        @FundingOpportunityPublicId = @ClosedOpportunityPublicId,
        @Notes = N'Closed backfill', @ApplicationDate = @TodayUtc,
        @RequestedAmount = 300, @Currency = 'USD', @ResultDate = NULL,
        @IdempotencyKeyHash = @ClosedKey, @RequestHash = @ClosedRequest;
    DECLARE @ClosedApplicationPublicId UNIQUEIDENTIFIER =
        (SELECT FundingApplicationPublicId FROM @Mutations WHERE Code = N'created');
    DECLARE @ClosedRowVersion BINARY(8) =
        (SELECT RowVersion FROM @Mutations WHERE Code = N'created');
    IF @ClosedApplicationPublicId IS NULL
        THROW 53916, N'Closed public-ready opportunity could not be backfilled.', 1;

    /* A non-owner regular member sees the resource as not found. */
    DELETE FROM @Mutations;
    INSERT INTO @Mutations
    EXEC dbo.FundingPlatform_usp_FundingApplication_Update
        @UserPublicId = @ViewerPublicId, @OrganizationPublicId = @OrgPublicId,
        @FundingApplicationPublicId = @ClosedApplicationPublicId,
        @ExpectedRowVersion = @ClosedRowVersion, @Status = 1,
        @Notes = N'Unauthorized', @ApplicationDate = @TodayUtc,
        @RequestedAmount = 300, @Currency = 'USD', @ResultDate = NULL;
    IF NOT EXISTS (SELECT 1 FROM @Mutations WHERE Succeeded = 0 AND Code = N'not-found')
        THROW 53917, N'Application ownership leaked through mutation outcome.', 1;

    /* An organization administrator may mutate another member's application. */
    DELETE FROM @Mutations;
    INSERT INTO @Mutations
    EXEC dbo.FundingPlatform_usp_FundingApplication_Update
        @UserPublicId = @AdminPublicId, @OrganizationPublicId = @OrgPublicId,
        @FundingApplicationPublicId = @ClosedApplicationPublicId,
        @ExpectedRowVersion = @ClosedRowVersion, @Status = 1,
        @Notes = N'Admin update', @ApplicationDate = @TodayUtc,
        @RequestedAmount = 300, @Currency = 'USD', @ResultDate = NULL;
    DECLARE @ClosedUpdatedRowVersion BINARY(8) =
        (SELECT RowVersion FROM @Mutations WHERE Succeeded = 1 AND Code = N'updated');
    IF @ClosedUpdatedRowVersion IS NULL
        THROW 53918, N'Organization administrator could not update member application.', 1;

    DELETE FROM @Mutations;
    INSERT INTO @Mutations
    EXEC dbo.FundingPlatform_usp_FundingApplication_Update
        @UserPublicId = @MemberPublicId, @OrganizationPublicId = @OrgPublicId,
        @FundingApplicationPublicId = @ClosedApplicationPublicId,
        @ExpectedRowVersion = @ClosedRowVersion, @Status = 5,
        @Notes = N'Discarded', @ApplicationDate = @TodayUtc,
        @RequestedAmount = 300, @Currency = 'USD', @ResultDate = NULL;
    IF NOT EXISTS (SELECT 1 FROM @Mutations WHERE Succeeded = 0 AND Code = N'etag-conflict')
        THROW 53919, N'Stale application ETag was accepted.', 1;

    DELETE FROM @Mutations;
    INSERT INTO @Mutations
    EXEC dbo.FundingPlatform_usp_FundingApplication_Update
        @UserPublicId = @MemberPublicId, @OrganizationPublicId = @OrgPublicId,
        @FundingApplicationPublicId = @ClosedApplicationPublicId,
        @ExpectedRowVersion = @ClosedUpdatedRowVersion, @Status = 5,
        @Notes = N'Discarded', @ApplicationDate = @TodayUtc,
        @RequestedAmount = 300, @Currency = 'USD', @ResultDate = NULL;
    IF NOT EXISTS (SELECT 1 FROM @Mutations WHERE Succeeded = 1 AND Code = N'updated' AND Status = 5)
        THROW 53920, N'Application owner could not discard current version.', 1;

    DELETE FROM @Mutations;
    INSERT INTO @Mutations
    EXEC dbo.FundingPlatform_usp_FundingApplication_Update
        @UserPublicId = @AdminPublicId, @OrganizationPublicId = @OrgPublicId,
        @FundingApplicationPublicId = @MainApplicationPublicId,
        @ExpectedRowVersion = @MainRowVersion, @Status = 1,
        @Notes = N'Applying', @ApplicationDate = @MainApplicationDate,
        @RequestedAmount = 250, @Currency = 'USD',
        @ResultDate = @MainResultDate;
    DECLARE @MainUpdatedRowVersion BINARY(8) =
        (SELECT RowVersion FROM @Mutations WHERE Succeeded = 1 AND Code = N'updated');
    IF @MainUpdatedRowVersion IS NULL THROW 53921, N'Application owner update failed.', 1;

    DECLARE @ApplicationCount BIGINT;
    EXEC dbo.FundingPlatform_usp_FundingApplication_List
        @UserPublicId = @AdminPublicId, @OrganizationPublicId = @OrgPublicId,
        @PageNumber = 1, @PageSize = 1, @MatchedCount = @ApplicationCount OUTPUT;
    IF @ApplicationCount <> 2
        THROW 53922, N'Application list paging lost tenant history.', 1;
    EXEC dbo.FundingPlatform_usp_FundingApplication_List
        @UserPublicId = @AdminPublicId, @OrganizationPublicId = @OrgPublicId,
        @Status = 5, @PageNumber = 1, @PageSize = 20,
        @MatchedCount = @ApplicationCount OUTPUT;
    IF @ApplicationCount <> 1 THROW 53923, N'Application status filter drifted.', 1;

    DECLARE @ApplicationRows TABLE
    (
        FundingApplicationPublicId UNIQUEIDENTIFIER, Status TINYINT,
        Notes NVARCHAR(5000), ApplicationDate DATE, RequestedAmount DECIMAL(19,4),
        Currency CHAR(3), ResultDate DATE, OwnerUserPublicId UNIQUEIDENTIFIER,
        CanEdit BIT, ProjectPublicId UNIQUEIDENTIFIER, ProjectSlug NVARCHAR(180),
        ProjectTitle NVARCHAR(250), FundingOpportunityPublicId UNIQUEIDENTIFIER,
        FundingOpportunitySlug NVARCHAR(320), FundingOpportunityTitle NVARCHAR(350),
        SponsorName NVARCHAR(300), CloseDate DATE, CloseAtUtc DATETIME2(3),
        DeadlinePrecision TINYINT, CreatedAtUtc DATETIME2(3), UpdatedAtUtc DATETIME2(3),
        RowVersion BINARY(8)
    );
    INSERT INTO @ApplicationRows
    EXEC dbo.FundingPlatform_usp_FundingApplication_Get
        @UserPublicId = @ViewerPublicId, @OrganizationPublicId = @OrgPublicId,
        @FundingApplicationPublicId = @MainApplicationPublicId;
    IF NOT EXISTS (SELECT 1 FROM @ApplicationRows WHERE CanEdit = 0)
        THROW 53924, N'Application read leaked edit authority.', 1;
    DELETE FROM @ApplicationRows;
    INSERT INTO @ApplicationRows
    EXEC dbo.FundingPlatform_usp_FundingApplication_Get
        @UserPublicId = @AdminPublicId, @OrganizationPublicId = @OrgPublicId,
        @FundingApplicationPublicId = @MainApplicationPublicId;
    IF NOT EXISTS (SELECT 1 FROM @ApplicationRows WHERE CanEdit = 1)
        THROW 53925, N'Application owner lost edit authority.', 1;

    DELETE FROM @ApplicationRows;
    INSERT INTO @ApplicationRows
    EXEC dbo.FundingPlatform_usp_FundingApplication_Get
        @UserPublicId = @OtherPublicId, @OrganizationPublicId = @OtherOrgPublicId,
        @FundingApplicationPublicId = @MainApplicationPublicId;
    IF EXISTS (SELECT 1 FROM @ApplicationRows)
        THROW 53926, N'Cross-tenant application detail leaked.', 1;

    DELETE FROM @Mutations;
    INSERT INTO @Mutations
    EXEC dbo.FundingPlatform_usp_FundingApplication_Update
        @UserPublicId = @OtherPublicId, @OrganizationPublicId = @OtherOrgPublicId,
        @FundingApplicationPublicId = @MainApplicationPublicId,
        @ExpectedRowVersion = @MainUpdatedRowVersion, @Status = 2,
        @Notes = NULL, @ApplicationDate = NULL,
        @RequestedAmount = NULL, @Currency = NULL, @ResultDate = NULL;
    IF NOT EXISTS (SELECT 1 FROM @Mutations WHERE Succeeded = 0 AND Code = N'not-found')
        THROW 53927, N'Cross-tenant mutation was distinguishable from not found.', 1;

    DELETE FROM @Mutations;
    INSERT INTO @Mutations
    EXEC dbo.FundingPlatform_usp_FundingApplication_Create
        @UserPublicId = @AdminPublicId, @OrganizationPublicId = @OrgPublicId,
        @ProjectPublicId = @OtherProjectPublicId,
        @FundingOpportunityPublicId = @FavoriteOpportunityPublicId,
        @Notes = NULL, @ApplicationDate = NULL,
        @RequestedAmount = NULL, @Currency = NULL, @ResultDate = NULL,
        @IdempotencyKeyHash = @CrossKey, @RequestHash = @CrossRequest;
    IF NOT EXISTS (SELECT 1 FROM @Mutations WHERE Succeeded = 0 AND Code = N'not-found')
        THROW 53928, N'Cross-tenant project creation was not hidden.', 1;

    DELETE FROM @Mutations;
    DECLARE @ArchivedKey BINARY(32) =
        HASHBYTES('SHA2_256', N'fase8b-archived-key-' + @Suffix);
    DECLARE @ArchivedRequest BINARY(32) =
        HASHBYTES('SHA2_256', N'fase8b-archived-request-' + @Suffix);
    INSERT INTO @Mutations
    EXEC dbo.FundingPlatform_usp_FundingApplication_Create
        @UserPublicId = @AdminPublicId, @OrganizationPublicId = @OrgPublicId,
        @ProjectPublicId = @ArchivedPublicId,
        @FundingOpportunityPublicId = @FavoriteOpportunityPublicId,
        @Notes = NULL, @ApplicationDate = NULL,
        @RequestedAmount = NULL, @Currency = NULL, @ResultDate = NULL,
        @IdempotencyKeyHash = @ArchivedKey, @RequestHash = @ArchivedRequest;
    IF NOT EXISTS (SELECT 1 FROM @Mutations WHERE Succeeded = 0 AND Code = N'not-found')
        THROW 53929, N'Archived project accepted a new application.', 1;

    DECLARE @TenantError INT = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_FundingApplication_List
            @UserPublicId = @AdminPublicId, @OrganizationPublicId = @OtherOrgPublicId,
            @MatchedCount = @ApplicationCount OUTPUT;
    END TRY
    BEGIN CATCH SET @TenantError = ERROR_NUMBER(); END CATCH;
    SET XACT_ABORT ON;
    IF @TenantError <> 52101 OR XACT_STATE() <> 1
        THROW 53930, N'Cross-tenant workspace access was not caller-safe not found.', 1;

    /* Database constraints independently reject mismatched project and owner tenants. */
    DECLARE @ConstraintError INT = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        INSERT INTO dbo.FundingPlatform_FundingApplications
            (OrganizationId, ProjectId, FundingOpportunityId, OwnerUserId, Status,
             CreatedAtUtc, UpdatedAtUtc)
        VALUES
            (@OrgId,
             (SELECT Id FROM dbo.FundingPlatform_Projects WHERE PublicId = @OtherProjectPublicId),
             (SELECT OpportunityId FROM @Opportunities WHERE PublicId = @FavoriteOpportunityPublicId),
             @AdminId, 0, @NowUtc, @NowUtc);
    END TRY
    BEGIN CATCH SET @ConstraintError = ERROR_NUMBER(); END CATCH;
    SET XACT_ABORT ON;
    IF @ConstraintError <> 547 OR XACT_STATE() <> 1
        THROW 53931, N'Project/organization composite FK did not reject cross-tenant write.', 1;

    SET @ConstraintError = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        INSERT INTO dbo.FundingPlatform_FundingApplications
            (OrganizationId, ProjectId, FundingOpportunityId, OwnerUserId, Status,
             CreatedAtUtc, UpdatedAtUtc)
        VALUES
            (@OrgId,
             (SELECT Id FROM dbo.FundingPlatform_Projects WHERE PublicId = @PublishedTwoPublicId),
             (SELECT OpportunityId FROM @Opportunities WHERE PublicId = @FavoriteOpportunityPublicId),
             @OtherId, 0, @NowUtc, @NowUtc);
    END TRY
    BEGIN CATCH SET @ConstraintError = ERROR_NUMBER(); END CATCH;
    SET XACT_ABORT ON;
    IF @ConstraintError <> 547 OR XACT_STATE() <> 1
        THROW 53932, N'Owner/membership composite FK did not reject cross-tenant write.', 1;

    /* Calendar favorite deadlines deduplicate active applications and reappear
       when the only application for that opportunity is discarded. */
    INSERT INTO dbo.FundingPlatform_UserFundingFavorites
        (OrganizationId, UserId, FundingOpportunityId, CreatedAtUtc)
    SELECT @OrgId, @AdminId, OpportunityId, @NowUtc
    FROM @Opportunities
    WHERE PublicId IN
          (@OpportunityPublicId, @FavoriteOpportunityPublicId, @ClosedOpportunityPublicId);

    DECLARE @Calendar TABLE
    (
        EventKey NVARCHAR(100), EventType NVARCHAR(30), EventDate DATE,
        EventAtUtc DATETIME2(3), DatePrecision TINYINT, Title NVARCHAR(350),
        Status TINYINT NULL, FundingApplicationPublicId UNIQUEIDENTIFIER NULL,
        ProjectPublicId UNIQUEIDENTIFIER NULL,
        FundingOpportunityPublicId UNIQUEIDENTIFIER NULL
    );
    DECLARE @CalendarFrom DATE = DATEADD(DAY, -5, @TodayUtc);
    DECLARE @CalendarTo DATE = DATEADD(DAY, 300, @TodayUtc);
    DECLARE @CalendarTooFar DATE = DATEADD(DAY, 366, @TodayUtc);
    INSERT INTO @Calendar
    EXEC dbo.FundingPlatform_usp_OrganizationCalendar_List
        @UserPublicId = @AdminPublicId, @OrganizationPublicId = @OrgPublicId,
        @FromDate = @CalendarFrom, @ToDate = @CalendarTo;
    IF (SELECT COUNT_BIG(1) FROM @Calendar) <> 11
       OR (SELECT COUNT_BIG(1) FROM @Calendar
           WHERE EventType = N'application-deadline'
             AND FundingApplicationPublicId = @MainApplicationPublicId) <> 1
       OR EXISTS
          (SELECT 1 FROM @Calendar
           WHERE EventType = N'favorite-deadline'
             AND FundingOpportunityPublicId = @OpportunityPublicId)
       OR NOT EXISTS
          (SELECT 1 FROM @Calendar
           WHERE EventType = N'favorite-deadline'
             AND FundingOpportunityPublicId = @ClosedOpportunityPublicId)
       OR EXISTS
          (SELECT 1 FROM @Calendar
           WHERE FundingApplicationPublicId = @ClosedApplicationPublicId)
       OR NOT EXISTS
          (SELECT 1 FROM @Calendar
           WHERE EventType = N'application-deadline' AND DatePrecision = 2
             AND EventAtUtc = @ExactCloseAtUtc)
       OR EXISTS
          (SELECT 1 FROM @Calendar
           WHERE EventType IN (N'project-start', N'project-end', N'favorite-deadline')
             AND Status IS NOT NULL)
       OR NOT EXISTS
          (SELECT 1 FROM @Calendar
           WHERE EventType = N'project-start' AND ProjectPublicId = @DraftPublicId)
       OR EXISTS
          (SELECT 1 FROM @Calendar
           WHERE EventType IN (N'project-start', N'project-end')
             AND ProjectPublicId = @ArchivedPublicId)
        THROW 53933, N'Calendar dedupe, discarded status or deadline precision drifted.', 1;

    SET @TenantError = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_OrganizationCalendar_List
            @UserPublicId = @AdminPublicId, @OrganizationPublicId = @OrgPublicId,
            @FromDate = @TodayUtc, @ToDate = @CalendarTooFar;
    END TRY
    BEGIN CATCH SET @TenantError = ERROR_NUMBER(); END CATCH;
    SET XACT_ABORT ON;
    IF @TenantError <> 52102 OR XACT_STATE() <> 1
        THROW 53934, N'Calendar accepted a range longer than 366 inclusive days.', 1;

    /* Historical application reads and calendar events survive later archival
       of their project and funding opportunity. Public marketplace reads do not. */
    UPDATE dbo.FundingPlatform_Projects
    SET PublicationStatus = 4, IsActive = 0, UpdatedAtUtc = @NowUtc
    WHERE PublicId = @PublishedOnePublicId;
    UPDATE dbo.FundingPlatform_FundingOpportunities
    SET PublicationStatus = 4, IsActive = 0, UpdatedAtUtc = @NowUtc
    WHERE PublicId = @OpportunityPublicId;

    DELETE FROM @ApplicationRows;
    INSERT INTO @ApplicationRows
    EXEC dbo.FundingPlatform_usp_FundingApplication_Get
        @UserPublicId = @AdminPublicId, @OrganizationPublicId = @OrgPublicId,
        @FundingApplicationPublicId = @MainApplicationPublicId;
    IF (SELECT COUNT_BIG(1) FROM @ApplicationRows) <> 1
        THROW 53935, N'Archival destroyed historical application detail.', 1;
    EXEC dbo.FundingPlatform_usp_FundingApplication_List
        @UserPublicId = @AdminPublicId, @OrganizationPublicId = @OrgPublicId,
        @MatchedCount = @ApplicationCount OUTPUT;
    IF @ApplicationCount <> 2
        THROW 53936, N'Archival removed historical application list rows.', 1;
    IF EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMarketplaceReady() AS ready
        INNER JOIN dbo.FundingPlatform_Projects AS projects ON projects.Id = ready.ProjectId
        WHERE projects.PublicId = @PublishedOnePublicId)
        THROW 53937, N'Archived project remained in the public marketplace.', 1;

    DELETE FROM @Calendar;
    INSERT INTO @Calendar
    EXEC dbo.FundingPlatform_usp_OrganizationCalendar_List
        @UserPublicId = @AdminPublicId, @OrganizationPublicId = @OrgPublicId,
        @FromDate = @CalendarFrom, @ToDate = @CalendarTo;
    IF (SELECT COUNT_BIG(1) FROM @Calendar) <> 11
       OR NOT EXISTS
          (SELECT 1 FROM @Calendar
           WHERE EventType = N'application-deadline'
             AND FundingApplicationPublicId = @MainApplicationPublicId
             AND EventAtUtc = @ExactCloseAtUtc)
        THROW 53938, N'Calendar lost historical application events after archival.', 1;

    /* Isolate the fixture ledger rows inside this transaction. */
    UPDATE dbo.FundingPlatform_OutboxMessages
    SET AvailableAtUtc = DATEADD(DAY, 2, @NowUtc)
    WHERE DispatchedAtUtc IS NULL
      AND
      (
          MessageType NOT IN (N'FundingApplicationCreated', N'FundingApplicationUpdated')
          OR COALESCE(TRY_CONVERT(UNIQUEIDENTIFIER,
                 JSON_VALUE(PayloadJson, N'$.fundingApplicationPublicId')),
                 CONVERT(UNIQUEIDENTIFIER, '00000000-0000-0000-0000-000000000000'))
             NOT IN (@MainApplicationPublicId, @ClosedApplicationPublicId)
      );

    INSERT INTO dbo.FundingPlatform_OutboxMessages
        (MessageType, AggregateType, AggregateId, PayloadJson, OccurredAtUtc, AvailableAtUtc)
    VALUES
        (N'FundingApplicationCreated', N'FundingApplication', N'999019',
         (SELECT NEWID() AS fundingApplicationPublicId,
                 @PublishedOnePublicId AS projectPublicId,
                 @FavoriteOpportunityPublicId AS fundingOpportunityPublicId,
                 0 AS status, N'must-never-be-accepted' AS notes
          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc);
    DECLARE @MalformedOutboxId BIGINT = SCOPE_IDENTITY();

    IF EXISTS
       (SELECT 1
        FROM dbo.FundingPlatform_OutboxMessages AS messages
        CROSS APPLY OPENJSON(messages.PayloadJson) AS fields
        WHERE messages.MessageType IN
              (N'FundingApplicationCreated', N'FundingApplicationUpdated')
          AND TRY_CONVERT(UNIQUEIDENTIFIER,
              JSON_VALUE(messages.PayloadJson, N'$.fundingApplicationPublicId'))
              IN (@MainApplicationPublicId, @ClosedApplicationPublicId)
          AND fields.[key] IN
              (N'notes', N'requestedAmount', N'currency', N'applicationDate', N'resultDate'))
        THROW 53939, N'Application outbox payload contains private application data.', 1;

    DECLARE @AcknowledgedCount INT = 0;
    DECLARE @FirstAckAtUtc DATETIME2(3) = DATEADD(SECOND, 1, @NowUtc);
    DECLARE @SecondAckAtUtc DATETIME2(3) = DATEADD(SECOND, 2, @NowUtc);
    EXEC dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge
        @BatchSize = 500, @NowUtc = @FirstAckAtUtc,
        @AcknowledgedCount = @AcknowledgedCount OUTPUT;
    IF @AcknowledgedCount <> 5
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
           WHERE MessageType IN (N'FundingApplicationCreated', N'FundingApplicationUpdated')
             AND TRY_CONVERT(UNIQUEIDENTIFIER,
                 JSON_VALUE(PayloadJson, N'$.fundingApplicationPublicId'))
                 IN (@MainApplicationPublicId, @ClosedApplicationPublicId)
             AND DispatchedAtUtc IS NULL)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
           WHERE Id = @MalformedOutboxId AND DispatchedAtUtc IS NULL)
        THROW 53940, N'Application event-ledger acknowledgement was unsafe or incomplete.', 1;

    SET @AcknowledgedCount = -1;
    EXEC dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge
        @BatchSize = 500, @NowUtc = @SecondAckAtUtc,
        @AcknowledgedCount = @AcknowledgedCount OUTPUT;
    IF @AcknowledgedCount <> 0
        THROW 53941, N'Application event-ledger acknowledgement was not idempotent.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke019;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FP_Smoke019;
    THROW;
END CATCH;

SELECT N'FASE 8B marketplace, applications and calendar smoke passed.' AS Result;
GO
