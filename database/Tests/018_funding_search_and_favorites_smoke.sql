/* Transactional FASE 8A smoke: published search/detail and private favorites. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF TYPE_ID(N'dbo.FundingPlatform_GuidIdList') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_UserFundingFavorites', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ifn_FundingOpportunityPublicReady', N'IF') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunity_OrganizationGet', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunity_Favorite_List', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunity_Favorite_Put', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunity_Favorite_Delete', N'P') IS NULL
    THROW 53801, N'FASE 8A search or favorite objects are incomplete.', 1;

IF NOT EXISTS
   (SELECT 1 FROM sys.foreign_keys
    WHERE parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_UserFundingFavorites')
      AND name = N'FundingPlatform_FK_UserFundingFavorites_Membership')
   OR NOT EXISTS
   (SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.FundingPlatform_UserFundingFavorites')
      AND name = N'FundingPlatform_IX_UserFundingFavorites_UserCreated')
    THROW 53802, N'Favorite tenancy or paging constraints are missing.', 1;

/* Module text and exact FTS configuration are asserted by the static migration
   tests. OBJECT_DEFINITION/result-set DMVs are intentionally avoided here:
   search uses #temp plus dynamic FTS, which metadata discovery cannot describe
   reliably. Runtime calls below verify that all rowsets compile. */

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke018;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @Suffix NVARCHAR(32) =
        REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'');
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @TodayUtc DATE = CONVERT(DATE, @NowUtc);
    DECLARE @UserAPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @UserBPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @OrgAPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @OrgBPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @FunderPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @SponsorName NVARCHAR(300) = N'FASE 8A sponsor ' + @Suffix;
    DECLARE @UserAEmail NVARCHAR(320) = N'fase8a-a-' + @Suffix + N'@example.invalid';
    DECLARE @UserBEmail NVARCHAR(320) = N'fase8a-b-' + @Suffix + N'@example.invalid';

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash,
         SecurityStamp, EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@UserAPublicId, @UserAEmail, UPPER(@UserAEmail), N'FASE 8A user A',
         N'not-a-credential', N'fase8a-a', 1, 0, 2, N'es-CL'),
        (@UserBPublicId, @UserBEmail, UPPER(@UserBEmail), N'FASE 8A user B',
         N'not-a-credential', N'fase8a-b', 1, 0, 2, N'es-CL');
    DECLARE @UserAId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @UserAPublicId);
    DECLARE @UserBId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @UserBPublicId);

    INSERT INTO dbo.FundingPlatform_Organizations
        (PublicId, CreatedByUserId, Name, HomeCountryId, OrganizationTypeId)
    VALUES
        (@OrgAPublicId, @UserAId, N'FASE 8A org A ' + @Suffix, 152, 1),
        (@OrgBPublicId, @UserBId, N'FASE 8A org B ' + @Suffix, 152, 2);
    DECLARE @OrgAId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Organizations WHERE PublicId = @OrgAPublicId);
    DECLARE @OrgBId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Organizations WHERE PublicId = @OrgBPublicId);
    INSERT INTO dbo.FundingPlatform_OrganizationUsers
        (OrganizationId, UserId, Role, MembershipStatus, JoinedAtUtc)
    VALUES
        (@OrgAId, @UserAId, 1, 1, @NowUtc),
        (@OrgAId, @UserBId, 2, 1, @NowUtc),
        (@OrgBId, @UserBId, 1, 1, @NowUtc);

    INSERT INTO dbo.FundingPlatform_Funders
        (PublicId, Slug, Name, NormalizedName, WebsiteUrl,
         PublicationStatus, SubmittedAtUtc, PublishedAtUtc, ReviewedAtUtc,
         ContentVersion, IsActive, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@FunderPublicId, N'fase8a-funder-' + @Suffix,
         @SponsorName, UPPER(@SponsorName),
         N'https://fase8a-funder.example.invalid', 2,
         DATEADD(DAY, -3, @NowUtc), DATEADD(DAY, -2, @NowUtc),
         DATEADD(DAY, -2, @NowUtc), 1, 1, @NowUtc, @NowUtc);
    DECLARE @FunderId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Funders WHERE PublicId = @FunderPublicId);
    DECLARE @SourceId INT =
        (SELECT Id FROM dbo.FundingPlatform_FundingSources
         WHERE Name = N'Manual editorial' AND IsEnabled = 1);
    IF @SourceId IS NULL THROW 53806, N'Manual governed source fixture is missing.', 1;

    INSERT INTO dbo.FundingPlatform_Tags
        (Name, NormalizedName, IsApproved, IsActive)
    VALUES (N'FASE 8A tag ' + @Suffix, N'FASE8A-' + UPPER(@Suffix), 1, 1);
    DECLARE @TagId BIGINT = SCOPE_IDENTITY();

    DECLARE @OpenPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @FuturePublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ClosedPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ExpiredAtPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @MinOnlyPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @GlobalPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @DraftPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @MissingEvidencePublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ConflictPublicId UNIQUEIDENTIFIER = NEWID();

    INSERT INTO dbo.FundingPlatform_FundingOpportunities
        (PublicId, Slug, Title, Description, Summary, SponsorName,
         IssuerCountryId, FundingTypeId, Currency, MinAmount, MaxAmount, AmountStatus,
         OpenDate, CloseDate, CloseAtUtc, DeadlineTimeZoneId,
         DeadlineType, DeadlinePrecision, EligibilityDescription, Requirements,
         GeographicScope, RemoteApplication, PublicationStatus,
         PublishedAtUtc, LastVerifiedAtUtc, DataQualityScore, ContentVersion,
         IsActive, ReviewedAtUtc, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@OpenPublicId, N'fase8a-open-' + @Suffix,
         N'Resiliencia abierta ' + @Suffix, N'Descripción', N'Resumen abierto', @SponsorName,
         152, 1, 'USD', 100, 200, 1, DATEADD(DAY, -10, @TodayUtc),
         DATEADD(DAY, 30, @TodayUtc), NULL, NULL, 1, 1, N'Elegible', N'Requisitos',
         1, 1, 2, DATEADD(DAY, -2, @NowUtc), @NowUtc, 95, 1, 1,
         DATEADD(DAY, -2, @NowUtc), @NowUtc, @NowUtc),
        (@FuturePublicId, N'fase8a-future-' + @Suffix,
         N'Resiliencia futura ' + @Suffix, N'Descripción', N'Resumen futuro', @SponsorName,
         152, 1, 'USD', 300, 400, 1, DATEADD(DAY, 10, @TodayUtc),
         DATEADD(DAY, 40, @TodayUtc), NULL, NULL, 1, 1, N'Elegible', N'Requisitos',
         1, 1, 2, DATEADD(DAY, -3, @NowUtc), @NowUtc, 90, 1, 1,
         DATEADD(DAY, -3, @NowUtc), @NowUtc, @NowUtc),
        (@ClosedPublicId, N'fase8a-closed-' + @Suffix,
         N'Resiliencia cerrada ' + @Suffix, N'Descripción', N'Resumen cerrado', @SponsorName,
         152, 1, 'USD', 500, 600, 1, DATEADD(DAY, -60, @TodayUtc),
         DATEADD(DAY, -1, @TodayUtc), NULL, NULL, 1, 1, N'Elegible', N'Requisitos',
         1, 1, 2, DATEADD(DAY, -4, @NowUtc), @NowUtc, 85, 1, 1,
         DATEADD(DAY, -4, @NowUtc), @NowUtc, @NowUtc),
        (@ExpiredAtPublicId, N'fase8a-expired-at-' + @Suffix,
         N'Resiliencia hora vencida ' + @Suffix, N'Descripción', N'Resumen exacto', @SponsorName,
         152, 1, 'USD', 900, 1000, 1, DATEADD(DAY, -10, @TodayUtc),
         DATEADD(DAY, 20, @TodayUtc), DATEADD(HOUR, -1, @NowUtc), N'UTC',
         1, 2, N'Elegible', N'Requisitos', 1, 1, 2,
         DATEADD(DAY, -5, @NowUtc), @NowUtc, 80, 1, 1,
         DATEADD(DAY, -5, @NowUtc), @NowUtc, @NowUtc),
        (@MinOnlyPublicId, N'fase8a-min-only-' + @Suffix,
         N'Resiliencia desde monto ' + @Suffix, N'Descripción', N'Sin máximo conocido', @SponsorName,
         152, 1, 'USD', 700, NULL, 1, DATEADD(DAY, -5, @TodayUtc),
         DATEADD(DAY, 25, @TodayUtc), NULL, NULL, 1, 1, N'Elegible', N'Requisitos',
         1, 1, 2, DATEADD(DAY, -6, @NowUtc), @NowUtc, 75, 1, 1,
         DATEADD(DAY, -6, @NowUtc), @NowUtc, @NowUtc),
        (@GlobalPublicId, N'fase8a-global-' + @Suffix,
         N'Resiliencia global ' + @Suffix, N'Descripción', N'Alcance global', @SponsorName,
         152, 1, 'USD', 1100, 1200, 1, DATEADD(DAY, 10, @TodayUtc),
         DATEADD(DAY, 50, @TodayUtc), NULL, NULL, 1, 1, N'Elegible', N'Requisitos',
         2, 1, 2, DATEADD(DAY, -7, @NowUtc), @NowUtc, 72, 1, 1,
         DATEADD(DAY, -7, @NowUtc), @NowUtc, @NowUtc),
        (@DraftPublicId, N'fase8a-draft-' + @Suffix,
         N'Resiliencia borrador ' + @Suffix, N'Descripción', N'Borrador', @SponsorName,
         152, 1, 'USD', 100, 200, 1, @TodayUtc, DATEADD(DAY, 30, @TodayUtc),
         NULL, NULL, 1, 1, N'Elegible', N'Requisitos', 1, 1, 0,
         NULL, @NowUtc, 70, 1, 1, NULL, @NowUtc, @NowUtc),
        (@MissingEvidencePublicId, N'fase8a-no-evidence-' + @Suffix,
         N'Resiliencia sin evidencia ' + @Suffix, N'Descripción', N'Incompleto', @SponsorName,
         152, 1, 'USD', 100, 200, 1, @TodayUtc, DATEADD(DAY, 30, @TodayUtc),
         NULL, NULL, 1, 1, N'Elegible', N'Requisitos', 1, 1, 2,
         DATEADD(DAY, -2, @NowUtc), @NowUtc, 70, 1, 1,
         DATEADD(DAY, -2, @NowUtc), @NowUtc, @NowUtc),
        (@ConflictPublicId, N'fase8a-conflict-' + @Suffix,
         N'Resiliencia conflicto ' + @Suffix, N'Descripción', N'Conflicto', @SponsorName,
         152, 1, 'USD', 100, 200, 1, @TodayUtc, DATEADD(DAY, 30, @TodayUtc),
         NULL, NULL, 1, 1, N'Elegible', N'Requisitos', 1, 1, 2,
         DATEADD(DAY, -2, @NowUtc), @NowUtc, 70, 1, 1,
         DATEADD(DAY, -2, @NowUtc), @NowUtc, @NowUtc);

    DECLARE @Fixtures TABLE
    (
        SequenceNumber INT NOT NULL PRIMARY KEY,
        PublicId UNIQUEIDENTIFIER NOT NULL,
        OpportunityId BIGINT NOT NULL,
        MissingCloseEvidence BIT NOT NULL
    );
    INSERT INTO @Fixtures (SequenceNumber, PublicId, OpportunityId, MissingCloseEvidence)
    SELECT fixture.SequenceNumber, fixture.PublicId, opportunities.Id,
           fixture.MissingCloseEvidence
    FROM (VALUES
        (1, @OpenPublicId, CONVERT(BIT, 0)),
        (2, @FuturePublicId, CONVERT(BIT, 0)),
        (3, @ClosedPublicId, CONVERT(BIT, 0)),
        (4, @ExpiredAtPublicId, CONVERT(BIT, 0)),
        (5, @MinOnlyPublicId, CONVERT(BIT, 0)),
        (6, @DraftPublicId, CONVERT(BIT, 0)),
        (7, @MissingEvidencePublicId, CONVERT(BIT, 1)),
        (8, @ConflictPublicId, CONVERT(BIT, 0)),
        (9, @GlobalPublicId, CONVERT(BIT, 0))
    ) AS fixture(SequenceNumber, PublicId, MissingCloseEvidence)
    INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
        ON opportunities.PublicId = fixture.PublicId;

    INSERT INTO dbo.FundingPlatform_FundingOpportunityCountries
        (FundingOpportunityId, CountryId)
    SELECT OpportunityId, 152 FROM @Fixtures WHERE PublicId <> @GlobalPublicId;
    INSERT INTO dbo.FundingPlatform_FundingOpportunityRegions
        (FundingOpportunityId, RegionId)
    SELECT OpportunityId, 7 FROM @Fixtures WHERE PublicId <> @GlobalPublicId;
    INSERT INTO dbo.FundingPlatform_FundingOpportunityCategories
        (FundingOpportunityId, FundingCategoryId)
    SELECT OpportunityId, 1 FROM @Fixtures;
    INSERT INTO dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes
        (FundingOpportunityId, BeneficiaryTypeId)
    SELECT OpportunityId, 2 FROM @Fixtures;
    INSERT INTO dbo.FundingPlatform_FundingOpportunityProjectTypes
        (FundingOpportunityId, ProjectTypeId)
    SELECT OpportunityId, 4 FROM @Fixtures;
    INSERT INTO dbo.FundingPlatform_FundingOpportunityTags
        (FundingOpportunityId, TagId)
    SELECT OpportunityId, @TagId FROM @Fixtures;
    INSERT INTO dbo.FundingPlatform_FundingOpportunityOrganizationTypes
        (FundingOpportunityId, OrganizationTypeId, EligibilityMode)
    SELECT OpportunityId, 1, 1 FROM @Fixtures
    UNION ALL SELECT OpportunityId, 2, 2 FROM @Fixtures;
    INSERT INTO dbo.FundingPlatform_FundingOpportunityLegalEntityTypes
        (FundingOpportunityId, LegalEntityTypeId, EligibilityMode)
    SELECT OpportunityId, 1, 1 FROM @Fixtures;
    INSERT INTO dbo.FundingPlatform_FundingOpportunityLanguages
        (FundingOpportunityId, LanguageId, LanguagePurpose)
    SELECT OpportunityId, 1, 1 FROM @Fixtures;
    INSERT INTO dbo.FundingPlatform_FundingOpportunityFunders
        (FundingOpportunityId, FunderId, Role, IsActive, CreatedAtUtc, UpdatedAtUtc)
    SELECT OpportunityId, @FunderId, 1, 1, @NowUtc, @NowUtc FROM @Fixtures;

    INSERT INTO dbo.FundingPlatform_FundingOpportunitySourceLinks
        (FundingOpportunityId, FundingSourceId, ExternalId, SourceItemKeyHash,
         SourceUrl, CanonicalUrlHash, FirstSeenAtUtc, LastSeenAtUtc, IsPrimary, IsActive)
    SELECT OpportunityId, @SourceId,
           N'fase8a-' + CONVERT(NVARCHAR(10), SequenceNumber) + N'-' + @Suffix,
           HASHBYTES('SHA2_256', N'fase8a-key-' + CONVERT(NVARCHAR(10), SequenceNumber) + @Suffix),
           N'https://fase8a-source.example.invalid/' +
              CONVERT(NVARCHAR(10), SequenceNumber) + N'/' + @Suffix,
           HASHBYTES('SHA2_256', N'fase8a-url-' + CONVERT(NVARCHAR(10), SequenceNumber) + @Suffix),
           @NowUtc, @NowUtc, 1, 1
    FROM @Fixtures;

    INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
        (FundingOpportunityId, FieldPath, ValueJson, ExtractionMethod,
         IsSelected, IsManualLock, CreatedAtUtc)
    SELECT fixtures.OpportunityId, paths.FieldPath,
           N'{"status":"known","value":"phase8a"}', 1, 1, 0, @NowUtc
    FROM @Fixtures AS fixtures
    CROSS JOIN (VALUES (N'/title'), (N'/description'),
                       (N'/eligibilityDescription'), (N'/closeDate')) AS paths(FieldPath)
    WHERE fixtures.MissingCloseEvidence = 0 OR paths.FieldPath <> N'/closeDate';

    DECLARE @ConflictOpportunityId BIGINT =
        (SELECT OpportunityId FROM @Fixtures WHERE PublicId = @ConflictPublicId);
    INSERT INTO dbo.FundingPlatform_FundingOpportunityFunderIdentityConflicts
        (FundingOpportunityId, CandidateFunderId, ReasonCode, IdentityFingerprint,
         SponsorUrlHash, FunderWebsiteUrlHash, IsExistingLink, DetectedBy, Status,
         OccurrenceCount, FirstDetectedAtUtc, LastDetectedAtUtc)
    VALUES
        (@ConflictOpportunityId, @FunderId, N'existing-primary-url-mismatch',
         HASHBYTES('SHA2_256', N'fase8a-conflict-' + @Suffix),
         HASHBYTES('SHA2_256', N'fase8a-sponsor-' + @Suffix),
         HASHBYTES('SHA2_256', N'fase8a-funder-' + @Suffix),
         1, 2, 0, 1, @NowUtc, @NowUtc);

    IF (SELECT COUNT_BIG(1)
        FROM dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
        INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
            ON opportunities.Id = ready.FundingOpportunityId
        WHERE opportunities.SponsorName = @SponsorName) <> 6
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
           INNER JOIN @Fixtures AS fixtures ON fixtures.OpportunityId = ready.FundingOpportunityId
           WHERE fixtures.PublicId IN (@DraftPublicId, @MissingEvidencePublicId, @ConflictPublicId))
        THROW 53807, N'PublicReady did not fail closed for draft, evidence or identity conflict.', 1;

    DECLARE @CountryIds dbo.FundingPlatform_SmallIntIdList;
    DECLARE @RegionIds dbo.FundingPlatform_IntIdList;
    DECLARE @CategoryIds dbo.FundingPlatform_IntIdList;
    DECLARE @TagIds dbo.FundingPlatform_BigIntIdList;
    DECLARE @BeneficiaryIds dbo.FundingPlatform_IntIdList;
    DECLARE @ProjectTypeIds dbo.FundingPlatform_IntIdList;
    DECLARE @FundingTypeIds dbo.FundingPlatform_SmallIntIdList;
    DECLARE @FunderIds dbo.FundingPlatform_GuidIdList;
    DECLARE @OrganizationTypeIds dbo.FundingPlatform_SmallIntIdList;
    DECLARE @Matched BIGINT, @Mode NVARCHAR(20);

    EXEC dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @Sponsor = @SponsorName, @OnlyOpen = 0, @Sort = N'closing-soon',
        @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @TagIds = @TagIds,
        @BeneficiaryTypeIds = @BeneficiaryIds, @ProjectTypeIds = @ProjectTypeIds,
        @FundingTypeIds = @FundingTypeIds, @FunderPublicIds = @FunderIds,
        @OrganizationTypeIds = @OrganizationTypeIds,
        @MatchedCount = @Matched OUTPUT, @EffectiveSearchMode = @Mode OUTPUT;
    IF @Matched <> 6 OR @Mode <> N'filtered'
        THROW 53808, N'Unfiltered tenant search did not return only ready fixtures.', 1;

    EXEC dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @Sponsor = @SponsorName, @OnlyOpen = 1, @Sort = N'closing-soon',
        @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @TagIds = @TagIds,
        @BeneficiaryTypeIds = @BeneficiaryIds, @ProjectTypeIds = @ProjectTypeIds,
        @FundingTypeIds = @FundingTypeIds, @FunderPublicIds = @FunderIds,
        @OrganizationTypeIds = @OrganizationTypeIds,
        @MatchedCount = @Matched OUTPUT, @EffectiveSearchMode = @Mode OUTPUT;
    IF @Matched <> 2
        THROW 53809, N'OnlyOpen ignored OpenDate or CloseAtUtc precedence.', 1;

    EXEC dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @Query = N'Resiliencia', @Sponsor = @SponsorName,
        @OnlyOpen = 0, @Sort = N'relevance',
        @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @TagIds = @TagIds,
        @BeneficiaryTypeIds = @BeneficiaryIds, @ProjectTypeIds = @ProjectTypeIds,
        @FundingTypeIds = @FundingTypeIds, @FunderPublicIds = @FunderIds,
        @OrganizationTypeIds = @OrganizationTypeIds,
        @MatchedCount = @Matched OUTPUT, @EffectiveSearchMode = @Mode OUTPUT;
    IF @Matched <> 6 OR @Mode NOT IN (N'full-text', N'literal-fallback')
        THROW 53810, N'Text search omitted fresh rows or exposed non-ready rows.', 1;

    EXEC dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @Query = N'%', @Sponsor = @SponsorName,
        @OnlyOpen = 0, @Sort = N'relevance',
        @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @TagIds = @TagIds,
        @BeneficiaryTypeIds = @BeneficiaryIds, @ProjectTypeIds = @ProjectTypeIds,
        @FundingTypeIds = @FundingTypeIds, @FunderPublicIds = @FunderIds,
        @OrganizationTypeIds = @OrganizationTypeIds,
        @MatchedCount = @Matched OUTPUT, @EffectiveSearchMode = @Mode OUTPUT;
    IF @Matched <> 0
        THROW 53811, N'LIKE metacharacters were not escaped as literals.', 1;

    INSERT INTO @CountryIds VALUES (152);
    INSERT INTO @RegionIds VALUES (7);
    INSERT INTO @CategoryIds VALUES (1), (2147483000);
    INSERT INTO @TagIds VALUES (@TagId);
    INSERT INTO @BeneficiaryIds VALUES (2);
    INSERT INTO @ProjectTypeIds VALUES (4);
    INSERT INTO @FundingTypeIds VALUES (1);
    INSERT INTO @FunderIds VALUES (@FunderPublicId);
    INSERT INTO @OrganizationTypeIds VALUES (1), (2);
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @Sponsor = @SponsorName, @Currency = 'USD', @OnlyOpen = 0,
        @Sort = N'amount-desc', @PageNumber = 2, @PageSize = 2,
        @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @TagIds = @TagIds,
        @BeneficiaryTypeIds = @BeneficiaryIds, @ProjectTypeIds = @ProjectTypeIds,
        @FundingTypeIds = @FundingTypeIds, @FunderPublicIds = @FunderIds,
        @OrganizationTypeIds = @OrganizationTypeIds,
        @MatchedCount = @Matched OUTPUT, @EffectiveSearchMode = @Mode OUTPUT;
    IF @Matched <> 6
        THROW 53812, N'Combined filters or global geography semantics are incorrect.', 1;

    DELETE FROM @OrganizationTypeIds;
    INSERT INTO @OrganizationTypeIds VALUES (2);
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @Sponsor = @SponsorName, @OnlyOpen = 0, @Sort = N'newest',
        @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @TagIds = @TagIds,
        @BeneficiaryTypeIds = @BeneficiaryIds, @ProjectTypeIds = @ProjectTypeIds,
        @FundingTypeIds = @FundingTypeIds, @FunderPublicIds = @FunderIds,
        @OrganizationTypeIds = @OrganizationTypeIds,
        @MatchedCount = @Matched OUTPUT, @EffectiveSearchMode = @Mode OUTPUT;
    IF @Matched <> 0
        THROW 53813, N'EligibilityMode=2 incorrectly passed the organization-type filter.', 1;

    INSERT INTO @OrganizationTypeIds VALUES (1);
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @Sponsor = @SponsorName, @OnlyOpen = 0, @Sort = N'newest',
        @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @TagIds = @TagIds,
        @BeneficiaryTypeIds = @BeneficiaryIds, @ProjectTypeIds = @ProjectTypeIds,
        @FundingTypeIds = @FundingTypeIds, @FunderPublicIds = @FunderIds,
        @OrganizationTypeIds = @OrganizationTypeIds,
        @MatchedCount = @Matched OUTPUT, @EffectiveSearchMode = @Mode OUTPUT;
    IF @Matched <> 6
        THROW 53814, N'Organization-type OR semantics hid an explicitly eligible type.', 1;

    DELETE FROM @CountryIds; DELETE FROM @RegionIds; DELETE FROM @CategoryIds;
    DELETE FROM @TagIds; DELETE FROM @BeneficiaryIds; DELETE FROM @ProjectTypeIds;
    DELETE FROM @FundingTypeIds; DELETE FROM @FunderIds; DELETE FROM @OrganizationTypeIds;
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @Sponsor = @SponsorName, @Currency = 'USD',
        @MinAmount = 250, @MaxAmount = 450,
        @OnlyOpen = 0, @Sort = N'amount-asc',
        @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @TagIds = @TagIds,
        @BeneficiaryTypeIds = @BeneficiaryIds, @ProjectTypeIds = @ProjectTypeIds,
        @FundingTypeIds = @FundingTypeIds, @FunderPublicIds = @FunderIds,
        @OrganizationTypeIds = @OrganizationTypeIds,
        @MatchedCount = @Matched OUTPUT, @EffectiveSearchMode = @Mode OUTPUT;
    IF @Matched <> 1
        THROW 53815, N'Currency-exact amount range overlap is incorrect.', 1;

    EXEC dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @Sponsor = @SponsorName, @Currency = 'ZZZ',
        @OnlyOpen = 0, @Sort = N'closing-soon',
        @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @TagIds = @TagIds,
        @BeneficiaryTypeIds = @BeneficiaryIds, @ProjectTypeIds = @ProjectTypeIds,
        @FundingTypeIds = @FundingTypeIds, @FunderPublicIds = @FunderIds,
        @OrganizationTypeIds = @OrganizationTypeIds,
        @MatchedCount = @Matched OUTPUT, @EffectiveSearchMode = @Mode OUTPUT;
    IF @Matched <> 0
        THROW 53816, N'A stale currency filter should return no matches.', 1;

    EXEC dbo.FundingPlatform_usp_FundingOpportunity_OrganizationGet
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @FundingOpportunityPublicId = @OpenPublicId;
    DECLARE @OpenSlug NVARCHAR(320) = N'fase8a-open-' + @Suffix;
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_OrganizationGet
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @Slug = @OpenSlug;

    DECLARE @Mutations TABLE
        (Code NVARCHAR(20), FundingOpportunityPublicId UNIQUEIDENTIFIER,
         CreatedAtUtc DATETIME2(3) NULL);
    INSERT INTO @Mutations
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Favorite_Put
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @FundingOpportunityPublicId = @OpenPublicId;
    DECLARE @FavoriteCreatedAt DATETIME2(3) =
        (SELECT CreatedAtUtc FROM @Mutations WHERE Code = N'created');
    IF @FavoriteCreatedAt IS NULL
        THROW 53817, N'Favorite PUT did not create a private favorite.', 1;

    DELETE FROM @Mutations;
    INSERT INTO @Mutations
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Favorite_Put
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @FundingOpportunityPublicId = @OpenPublicId;
    IF NOT EXISTS
       (SELECT 1 FROM @Mutations
        WHERE Code = N'unchanged' AND CreatedAtUtc = @FavoriteCreatedAt)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_UserFundingFavorites
           WHERE OrganizationId = @OrgAId AND UserId = @UserAId) <> 1
        THROW 53818, N'Favorite PUT replay was not idempotent.', 1;

    DECLARE @FavoriteCount BIGINT;
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Favorite_List
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @MatchedCount = @FavoriteCount OUTPUT;
    IF @FavoriteCount <> 1 THROW 53819, N'Favorite owner list is incorrect.', 1;
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Favorite_List
        @UserPublicId = @UserBPublicId, @OrganizationPublicId = @OrgAPublicId,
        @MatchedCount = @FavoriteCount OUTPUT;
    IF @FavoriteCount <> 0 THROW 53820, N'Favorites leaked to another tenant member.', 1;

    DECLARE @CrossTenantError INT = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_FundingOpportunity_Favorite_List
            @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgBPublicId,
            @MatchedCount = @FavoriteCount OUTPUT;
    END TRY
    BEGIN CATCH
        SET @CrossTenantError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;
    IF @CrossTenantError <> 52001 OR XACT_STATE() <> 1
        THROW 53821, N'Inactive/cross-tenant membership was not hidden as not found.', 1;

    SET @CrossTenantError = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch
            @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgBPublicId,
            @OnlyOpen = 0, @Sort = N'closing-soon',
            @CountryIds = @CountryIds, @RegionIds = @RegionIds,
            @CategoryIds = @CategoryIds, @TagIds = @TagIds,
            @BeneficiaryTypeIds = @BeneficiaryIds, @ProjectTypeIds = @ProjectTypeIds,
            @FundingTypeIds = @FundingTypeIds, @FunderPublicIds = @FunderIds,
            @OrganizationTypeIds = @OrganizationTypeIds,
            @MatchedCount = @Matched OUTPUT, @EffectiveSearchMode = @Mode OUTPUT;
    END TRY
    BEGIN CATCH
        SET @CrossTenantError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;
    IF @CrossTenantError <> 52001 OR XACT_STATE() <> 1
        THROW 53827, N'Cross-tenant search was not hidden as not found.', 1;

    SET @CrossTenantError = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_FundingOpportunity_OrganizationGet
            @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgBPublicId,
            @FundingOpportunityPublicId = @OpenPublicId;
    END TRY
    BEGIN CATCH
        SET @CrossTenantError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;
    IF @CrossTenantError <> 52001 OR XACT_STATE() <> 1
        THROW 53828, N'Cross-tenant detail was not hidden as not found.', 1;

    /* A favorite remains private data but disappears immediately when the fund
       is no longer public-ready; DELETE still works and remains idempotent. */
    UPDATE dbo.FundingPlatform_FundingOpportunities
    SET PublicationStatus = 0, UpdatedAtUtc = @NowUtc
    WHERE PublicId = @OpenPublicId;
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Favorite_List
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @MatchedCount = @FavoriteCount OUTPUT;
    IF @FavoriteCount <> 0
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_UserFundingFavorites
           WHERE OrganizationId = @OrgAId AND UserId = @UserAId)
        THROW 53822, N'A stale favorite was exposed or destructively removed.', 1;

    DELETE FROM @Mutations;
    INSERT INTO @Mutations
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Favorite_Delete
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @FundingOpportunityPublicId = @OpenPublicId;
    IF NOT EXISTS (SELECT 1 FROM @Mutations WHERE Code = N'deleted')
        THROW 53823, N'A stale favorite could not be deleted.', 1;
    DELETE FROM @Mutations;
    INSERT INTO @Mutations
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Favorite_Delete
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @FundingOpportunityPublicId = @OpenPublicId;
    IF NOT EXISTS (SELECT 1 FROM @Mutations WHERE Code = N'unchanged')
        THROW 53824, N'Favorite DELETE replay was not idempotent.', 1;

    UPDATE dbo.FundingPlatform_Tags SET IsActive = 0 WHERE Id = @TagId;
    IF EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
        INNER JOIN @Fixtures AS fixtures ON fixtures.OpportunityId = ready.FundingOpportunityId)
       OR EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs() AS activeCatalogs
           INNER JOIN @Fixtures AS fixtures
               ON fixtures.OpportunityId = activeCatalogs.FundingOpportunityId)
        THROW 53825, N'An inactive linked catalog did not fail closed.', 1;
    UPDATE dbo.FundingPlatform_Tags SET IsActive = 1 WHERE Id = @TagId;

    UPDATE dbo.FundingPlatform_OrganizationUsers
    SET MembershipStatus = 2, UpdatedAtUtc = @NowUtc
    WHERE OrganizationId = @OrgAId AND UserId = @UserAId;
    DECLARE @InactiveMembershipError INT = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_FundingOpportunity_Favorite_List
            @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
            @MatchedCount = @FavoriteCount OUTPUT;
    END TRY
    BEGIN CATCH
        SET @InactiveMembershipError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;
    IF @InactiveMembershipError <> 52001 OR XACT_STATE() <> 1
        THROW 53826, N'Inactive membership retained favorite access.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke018;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FP_Smoke018;
    THROW;
END CATCH;

SELECT N'FASE 8A search and favorites smoke passed.' AS Result;
GO
