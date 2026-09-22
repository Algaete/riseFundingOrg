/* Bundled funding cover library. No uploads, URLs, runtime grants or paid services.
   Complete procedures preserve 054 editorial guards and 010/018 search contracts.
   Existing rows stay NULL; the frontend uses a stable bundled default. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF COL_LENGTH(N'dbo.FundingPlatform_FundingOpportunities', N'CoverKey') IS NULL
    ALTER TABLE dbo.FundingPlatform_FundingOpportunities ADD CoverKey NVARCHAR(40) NULL;
GO
IF NOT EXISTS(SELECT 1 FROM sys.check_constraints
              WHERE name = N'FundingPlatform_CK_Opportunities_CoverKey'
                AND parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_FundingOpportunities'))
    ALTER TABLE dbo.FundingPlatform_FundingOpportunities WITH CHECK
        ADD CONSTRAINT FundingPlatform_CK_Opportunities_CoverKey CHECK
        (CoverKey IS NULL OR (CoverKey COLLATE Latin1_General_100_BIN2 IN
          (N'auto', N'nature-v1', N'education-v1', N'community-v1', N'research-v1')
          AND DATALENGTH(CoverKey) = DATALENGTH(RTRIM(CoverKey))));
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Create
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @Slug NVARCHAR(320), @Title NVARCHAR(350),
    @Description NVARCHAR(MAX) = NULL, @Summary NVARCHAR(2000) = NULL,
    @SponsorName NVARCHAR(300), @SponsorUrl NVARCHAR(2048) = NULL,
    @ApplicationUrl NVARCHAR(2048) = NULL, @IssuerCountryId SMALLINT = NULL,
    @FundingTypeId SMALLINT = NULL, @Currency CHAR(3) = NULL,
    @MinAmount DECIMAL(19,4) = NULL, @MaxAmount DECIMAL(19,4) = NULL,
    @AmountStatus TINYINT, @OpenDate DATE = NULL, @CloseDate DATE = NULL,
    @CloseAtUtc DATETIME2(3) = NULL, @DeadlineTimeZoneId NVARCHAR(100) = NULL,
    @DeadlineType TINYINT, @DeadlinePrecision TINYINT,
    @EligibilityDescription NVARCHAR(MAX) = NULL, @Requirements NVARCHAR(MAX) = NULL,
    @Objectives NVARCHAR(MAX) = NULL, @AllowedActivities NVARCHAR(MAX) = NULL,
    @ExcludedActivities NVARCHAR(MAX) = NULL, @Restrictions NVARCHAR(MAX) = NULL,
    @TargetOrganizationsDescription NVARCHAR(2000) = NULL,
    @TargetPopulationsDescription NVARCHAR(2000) = NULL,
    @MinimumOperatingYears SMALLINT = NULL, @RequiresLegalEntity BIT = NULL,
    @RequiresPriorExperience BIT = NULL, @RequiresCofunding BIT = NULL,
    @CofundingPercentage DECIMAL(5,2) = NULL, @GeographicScope TINYINT,
    @RemoteApplication TINYINT, @LastVerifiedAtUtc DATETIME2(3) = NULL,
    @DataQualityScore DECIMAL(5,2),
    @FundingSourceId INT, @ExternalId NVARCHAR(250) = NULL,
    @SourceItemKeyHash BINARY(32), @SourceUrl NVARCHAR(2048),
    @CanonicalUrlHash BINARY(32) = NULL,
    @SnapshotJson NVARCHAR(MAX), @ContentHash BINARY(32),
    @CountryIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @RegionIds dbo.FundingPlatform_IntIdList READONLY,
    @CategoryIds dbo.FundingPlatform_IntIdList READONLY,
    @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @FunderLinksJson NVARCHAR(MAX), @EvidenceJson NVARCHAR(MAX) = N'[]',
    @IdempotencyKeyHash BINARY(32), @RequestHash BINARY(32),
    @OwnerWorkspace BIT = 0,
    @OtherCategoryDescription NVARCHAR(MAX) = NULL,
    @CoverKey NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @OwnerWorkspace IS NULL THROW 51601, N'Invalid workspace scope.', 1;
    DECLARE @WorkspaceActorUserId BIGINT;
    IF @OwnerWorkspace = 1
        EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 2, NULL, @WorkspaceActorUserId OUTPUT;
    ELSE
    BEGIN
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    END;
    IF ISJSON(@SnapshotJson) <> 1 OR LEFT(LTRIM(@SnapshotJson), 1) <> N'{'
        THROW 51609, N'SnapshotJson must be a JSON object.', 1;


    SET @CoverKey = NULLIF(LTRIM(RTRIM(@CoverKey)), N'');
    IF (@CoverKey IS NOT NULL AND (DATALENGTH(@CoverKey) > 80
        OR @CoverKey COLLATE Latin1_General_100_BIN2 NOT IN
            (N'auto', N'nature-v1', N'education-v1', N'community-v1', N'research-v1')))
       OR (SELECT COUNT(*) FROM OPENJSON(@SnapshotJson) WHERE [key] COLLATE Latin1_General_100_BIN2 = N'coverKey') > 1
       OR EXISTS(SELECT 1 FROM OPENJSON(@SnapshotJson) WHERE [key] COLLATE Latin1_General_100_BIN2 = N'coverKey'
                 AND ([type] NOT IN(0,1) OR DATALENGTH([value]) > 80))
       OR COALESCE(JSON_VALUE(@SnapshotJson, '$.coverKey'), N'') COLLATE Latin1_General_100_BIN2
          <> COALESCE(@CoverKey, N'') COLLATE Latin1_General_100_BIN2
       OR DATALENGTH(COALESCE(JSON_VALUE(@SnapshotJson, '$.coverKey'), N''))
          <> DATALENGTH(COALESCE(@CoverKey, N''))
        THROW 56090, N'Cover key must be in the bundled library and match its version snapshot.', 1;

    SET @OtherCategoryDescription = NULLIF(LTRIM(RTRIM(@OtherCategoryDescription)), N'');
    IF DATALENGTH(@OtherCategoryDescription) > 400
       OR (EXISTS(SELECT 1 FROM @CategoryIds WHERE Id = 16) AND @OtherCategoryDescription IS NULL)
       OR (NOT EXISTS(SELECT 1 FROM @CategoryIds WHERE Id = 16) AND @OtherCategoryDescription IS NOT NULL)
       OR (SELECT COUNT(*) FROM OPENJSON(@SnapshotJson) WHERE [key] COLLATE Latin1_General_100_BIN2 = N'otherCategoryDescription') > 1
       OR EXISTS(SELECT 1 FROM OPENJSON(@SnapshotJson) WHERE [key] COLLATE Latin1_General_100_BIN2 = N'otherCategoryDescription' AND ([type] NOT IN(0,1) OR DATALENGTH([value]) > 400))
       OR COALESCE(JSON_VALUE(@SnapshotJson, '$.otherCategoryDescription'), N'') COLLATE Latin1_General_100_BIN2
          <> COALESCE(@OtherCategoryDescription, N'') COLLATE Latin1_General_100_BIN2
       OR DATALENGTH(COALESCE(JSON_VALUE(@SnapshotJson, '$.otherCategoryDescription'), N''))
          <> DATALENGTH(COALESCE(@OtherCategoryDescription, N''))
        THROW 51609, N'Other category must be selected, specified and match its version snapshot.', 1;
    IF ISJSON(COALESCE(@FunderLinksJson, N'[]')) <> 1
       OR LEFT(LTRIM(COALESCE(@FunderLinksJson, N'[]')), 1) <> N'['
        THROW 51610, N'FunderLinksJson must be a JSON array.', 1;
    IF ISJSON(COALESCE(@EvidenceJson, N'[]')) <> 1
       OR LEFT(LTRIM(COALESCE(@EvidenceJson, N'[]')), 1) <> N'['
        THROW 51611, N'EvidenceJson must be a JSON array.', 1;

    DECLARE @ActorUserId BIGINT, @OpportunityId BIGINT, @OpportunityPublicId UNIQUEIDENTIFIER;
    DECLARE @RowVersion BINARY(8), @ExistingRequestHash BINARY(32), @SourceLinkId BIGINT;
    DECLARE @Code NVARCHAR(50) = N'created', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @RawFunderCount INT =
        (SELECT COUNT(1) FROM OPENJSON(COALESCE(@FunderLinksJson, N'[]')));
    DECLARE @RawEvidenceCount INT =
        (SELECT COUNT(1) FROM OPENJSON(COALESCE(@EvidenceJson, N'[]')));
    DECLARE @RequestedFunders TABLE
    (
        FunderPublicId UNIQUEIDENTIFIER NOT NULL,
        Role TINYINT NOT NULL,
        FunderId BIGINT NULL,
        PRIMARY KEY (FunderPublicId)
    );
    DECLARE @ExtraEvidence TABLE
    (
        FieldPath NVARCHAR(200) NOT NULL PRIMARY KEY,
        ValueJson NVARCHAR(MAX) NOT NULL,
        EvidenceText NVARCHAR(2000) NULL,
        SourceLocator NVARCHAR(500) NULL,
        Confidence DECIMAL(5,2) NULL,
        IsManualLock BIT NOT NULL
    );

    INSERT INTO @RequestedFunders (FunderPublicId, Role)
    SELECT TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(items.value, '$.funderPublicId')),
           MIN(TRY_CONVERT(TINYINT, JSON_VALUE(items.value, '$.role')))
    FROM OPENJSON(COALESCE(@FunderLinksJson, N'[]')) AS items
    WHERE TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(items.value, '$.funderPublicId')) IS NOT NULL
      AND TRY_CONVERT(TINYINT, JSON_VALUE(items.value, '$.role')) BETWEEN 1 AND 3
    GROUP BY TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(items.value, '$.funderPublicId'))
    HAVING COUNT_BIG(1) = 1;

    INSERT INTO @ExtraEvidence
        (FieldPath, ValueJson, EvidenceText, SourceLocator, Confidence, IsManualLock)
    SELECT JSON_VALUE(items.value, '$.fieldPath'),
           MAX(JSON_QUERY(items.value, '$.valueJson')),
           MAX(JSON_VALUE(items.value, '$.evidenceText')),
           MAX(JSON_VALUE(items.value, '$.sourceLocator')),
           MAX(TRY_CONVERT(DECIMAL(5,2), JSON_VALUE(items.value, '$.confidence'))),
           MAX(CONVERT(TINYINT,
               COALESCE(TRY_CONVERT(BIT, JSON_VALUE(items.value, '$.isManualLock')), 1)))
    FROM OPENJSON(COALESCE(@EvidenceJson, N'[]')) AS items
    WHERE LEFT(JSON_VALUE(items.value, '$.fieldPath'), 1) = N'/'
      AND LEN(JSON_VALUE(items.value, '$.fieldPath')) BETWEEN 2 AND 200
      AND JSON_QUERY(items.value, '$.valueJson') IS NOT NULL
      AND LEFT(LTRIM(JSON_QUERY(items.value, '$.valueJson')), 1) = N'{'
      AND (JSON_VALUE(items.value, '$.evidenceText') IS NULL
           OR LEN(JSON_VALUE(items.value, '$.evidenceText')) <= 2000)
      AND (JSON_VALUE(items.value, '$.sourceLocator') IS NULL
           OR LEN(JSON_VALUE(items.value, '$.sourceLocator')) <= 500)
      AND (JSON_VALUE(items.value, '$.confidence') IS NULL
           OR TRY_CONVERT(DECIMAL(5,2), JSON_VALUE(items.value, '$.confidence')) BETWEEN 0 AND 100)
      AND (JSON_VALUE(items.value, '$.isManualLock') IS NULL
           OR TRY_CONVERT(BIT, JSON_VALUE(items.value, '$.isManualLock')) IS NOT NULL)
      AND JSON_VALUE(items.value, '$.fieldPath') NOT IN
          (N'/title', N'/description', N'/eligibilityDescription', N'/closeDate', N'/sponsorName')
    GROUP BY JSON_VALUE(items.value, '$.fieldPath')
    HAVING COUNT_BIG(1) = 1;

    IF NULLIF(LTRIM(RTRIM(@Slug)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@Title)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@SponsorName)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@SourceUrl)), N'') IS NULL
       OR @RawFunderCount <> (SELECT COUNT(1) FROM @RequestedFunders)
       OR @RawEvidenceCount <> (SELECT COUNT(1) FROM @ExtraEvidence)
       OR (SELECT COUNT(1) FROM @RequestedFunders WHERE Role = 1) <> 1
       OR @AmountStatus NOT BETWEEN 0 AND 2
       OR (@AmountStatus = 1 AND (@Currency IS NULL OR (@MinAmount IS NULL AND @MaxAmount IS NULL)))
       OR (@AmountStatus IN (0, 2) AND (@Currency IS NOT NULL OR @MinAmount IS NOT NULL OR @MaxAmount IS NOT NULL))
       OR @MinAmount < 0 OR @MaxAmount < COALESCE(@MinAmount, 0)
       OR @DeadlineType NOT BETWEEN 0 AND 2 OR @DeadlinePrecision NOT BETWEEN 0 AND 2
       OR (@DeadlineType = 0 AND (@DeadlinePrecision <> 0 OR @CloseAtUtc IS NOT NULL))
       OR (@DeadlineType = 2 AND (@DeadlinePrecision <> 0 OR @CloseDate IS NOT NULL OR @CloseAtUtc IS NOT NULL))
       OR (@DeadlineType = 1 AND @DeadlinePrecision NOT IN (1, 2))
       OR (@DeadlineType = 1 AND @DeadlinePrecision = 1 AND (@CloseDate IS NULL OR @CloseAtUtc IS NOT NULL))
       OR (@DeadlineType = 1 AND @DeadlinePrecision = 2
           AND (@CloseDate IS NULL OR @CloseAtUtc IS NULL OR @DeadlineTimeZoneId IS NULL))
       OR (@OpenDate IS NOT NULL AND @CloseDate IS NOT NULL AND @OpenDate > @CloseDate)
       OR @GeographicScope NOT BETWEEN 0 AND 2 OR @RemoteApplication NOT BETWEEN 0 AND 2
       OR (@GeographicScope = 0
           AND (EXISTS (SELECT 1 FROM @CountryIds) OR EXISTS (SELECT 1 FROM @RegionIds)))
       OR (@GeographicScope = 1 AND NOT EXISTS (SELECT 1 FROM @CountryIds))
       OR (@GeographicScope = 2
           AND (EXISTS (SELECT 1 FROM @CountryIds) OR EXISTS (SELECT 1 FROM @RegionIds)))
       OR @DataQualityScore NOT BETWEEN 0 AND 100
       OR @MinimumOperatingYears < 0
       OR @CofundingPercentage < 0 OR @CofundingPercentage > 100
       OR (@RequiresCofunding IS NULL AND @CofundingPercentage IS NOT NULL)
       OR (@RequiresCofunding = 0 AND COALESCE(@CofundingPercentage, 0) <> 0)
       OR (@RequiresCofunding = 1 AND COALESCE(@CofundingPercentage, 0) <= 0)
       OR (@LastVerifiedAtUtc IS NOT NULL
           AND @LastVerifiedAtUtc > DATEADD(MINUTE, 5, SYSUTCDATETIME()))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               CAST(NULL AS UNIQUEIDENTIFIER) AS FundingOpportunityPublicId,
               CAST(NULL AS INT) AS ContentVersion, CAST(NULL AS TINYINT) AS PublicationStatus,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_OppCreate;
    BEGIN TRY
        IF @OwnerWorkspace = 1
            EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 2, NULL, @ActorUserId OUTPUT;
        ELSE
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        IF @OwnerWorkspace = 1
        BEGIN
            /* Native submission provenance and exactly one owned primary funder.
               Existing/imported records cannot be adopted through a link or a replay. */
            IF (SELECT COUNT_BIG(1) FROM @RequestedFunders) <> 1
               OR NOT EXISTS (SELECT 1 FROM @RequestedFunders AS requested
                   INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.PublicId = requested.FunderPublicId
                   INNER JOIN dbo.FundingPlatform_FunderWorkspaceOwners AS owners WITH (UPDLOCK, HOLDLOCK) ON owners.FunderId = funders.Id
                   WHERE requested.Role = 1 AND owners.UserId = @ActorUserId AND owners.IsActive = 1)
               OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingSources WHERE Id = @FundingSourceId AND ProviderCode = N'funder-workspace' AND IsEnabled = 1)
                THROW 51601, N'Workspace funder or source is not permitted.', 1;
        END;
        SELECT @ActorUserId = Id FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;
        SELECT @OpportunityId = events.FundingOpportunityId,
               @ExistingRequestHash = events.RequestHash, @RowVersion = events.ResultRowVersion
        FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents AS events WITH (UPDLOCK, HOLDLOCK)
        WHERE events.ActorUserId = @ActorUserId AND events.ActionCode = N'Create'
          AND events.IdempotencyKeyHash = @IdempotencyKeyHash;

        IF @OpportunityId IS NOT NULL
        BEGIN
            IF @OwnerWorkspace = 1 AND NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_OpportunityWorkspaceOwners AS managed INNER JOIN dbo.FundingPlatform_FunderWorkspaceOwners AS owners ON owners.FunderId = managed.FunderId WHERE managed.FundingOpportunityId = @OpportunityId AND owners.UserId = @ActorUserId AND owners.IsActive = 1)
                THROW 51601, N'Workspace access is not available.', 1;
            SELECT @OpportunityPublicId = PublicId
            FROM dbo.FundingPlatform_FundingOpportunities WHERE Id = @OpportunityId;
            IF @ExistingRequestHash = @RequestHash
            BEGIN
                SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'created';
            END
            ELSE SET @Code = N'idempotency-conflict';
        END
        ELSE
        BEGIN
            UPDATE requested SET FunderId = funders.Id
            FROM @RequestedFunders AS requested
            INNER JOIN dbo.FundingPlatform_Funders AS funders WITH (UPDLOCK, HOLDLOCK)
                ON funders.PublicId = requested.FunderPublicId
               AND funders.IsActive = 1 AND funders.PublicationStatus <> 4;

            IF EXISTS (SELECT 1 FROM @RequestedFunders WHERE FunderId IS NULL)
                SET @Code = N'funder-not-found';
            ELSE IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingSources
                                WHERE Id = @FundingSourceId AND IsEnabled = 1)
                SET @Code = N'source-disabled';
            ELSE IF (@IssuerCountryId IS NOT NULL AND NOT EXISTS
                     (SELECT 1 FROM dbo.FundingPlatform_Countries
                      WHERE Id = @IssuerCountryId AND IsActive = 1))
                 OR (@FundingTypeId IS NOT NULL AND NOT EXISTS
                     (SELECT 1 FROM dbo.FundingPlatform_FundingTypes
                      WHERE Id = @FundingTypeId AND IsActive = 1))
                 OR (@Currency IS NOT NULL AND NOT EXISTS
                     (SELECT 1 FROM dbo.FundingPlatform_Currencies
                      WHERE Code = @Currency AND IsActive = 1))
                 OR EXISTS (SELECT 1 FROM @CountryIds AS selected
                            LEFT JOIN dbo.FundingPlatform_Countries AS catalog
                                ON catalog.Id = selected.Id AND catalog.IsActive = 1
                            WHERE catalog.Id IS NULL)
                 OR EXISTS (SELECT 1 FROM @CategoryIds AS selected
                            LEFT JOIN dbo.FundingPlatform_FundingCategories AS catalog
                                ON catalog.Id = selected.Id AND catalog.IsActive = 1
                            WHERE catalog.Id IS NULL)
                 OR EXISTS (SELECT 1 FROM @BeneficiaryTypeIds AS selected
                            LEFT JOIN dbo.FundingPlatform_BeneficiaryTypes AS catalog
                                ON catalog.Id = selected.Id AND catalog.IsActive = 1
                            WHERE catalog.Id IS NULL)
                 OR EXISTS (SELECT 1 FROM @ProjectTypeIds AS selected
                            LEFT JOIN dbo.FundingPlatform_ProjectTypes AS catalog
                                ON catalog.Id = selected.Id AND catalog.IsActive = 1
                            WHERE catalog.Id IS NULL)
                SET @Code = N'invalid-document';
            ELSE IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WITH (UPDLOCK, HOLDLOCK)
                            WHERE Slug = LTRIM(RTRIM(@Slug)))
                SET @Code = N'slug-conflict';
            ELSE IF EXISTS
            (
                SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks WITH (UPDLOCK, HOLDLOCK)
                WHERE FundingSourceId = @FundingSourceId
                  AND (SourceItemKeyHash = @SourceItemKeyHash
                       OR (@ExternalId IS NOT NULL AND ExternalId = @ExternalId))
            ) SET @Code = N'source-link-conflict';
            ELSE IF EXISTS
            (
                SELECT 1 FROM @RegionIds AS selected
                LEFT JOIN dbo.FundingPlatform_Regions AS regions
                    ON regions.Id = selected.Id AND regions.IsActive = 1
                WHERE regions.Id IS NULL
                   OR NOT EXISTS (SELECT 1 FROM @CountryIds AS countries WHERE countries.Id = regions.CountryId)
            ) SET @Code = N'invalid-document';
            ELSE
            BEGIN
                DECLARE @InsertedOpportunity TABLE
                    (Id BIGINT, PublicId UNIQUEIDENTIFIER, RowVersion BINARY(8));
                INSERT INTO dbo.FundingPlatform_FundingOpportunities
                (
                    Slug, Title, Description, Summary, SponsorName, SponsorUrl, ApplicationUrl,
                    IssuerCountryId, FundingTypeId, Currency, MinAmount, MaxAmount, AmountStatus,
                    OpenDate, CloseDate, CloseAtUtc, DeadlineTimeZoneId, DeadlineType,
                    DeadlinePrecision, EligibilityDescription, Requirements, Objectives,
                    AllowedActivities, ExcludedActivities, Restrictions,
                    TargetOrganizationsDescription, TargetPopulationsDescription,
                    MinimumOperatingYears, RequiresLegalEntity, RequiresPriorExperience,
                    RequiresCofunding, CofundingPercentage, GeographicScope, RemoteApplication,
                    PublicationStatus, PublishedAtUtc, LastVerifiedAtUtc, DataQualityScore,
                    ContentVersion, ContentFingerprint, IsActive, CreatedByUserId, UpdatedByUserId,
                    CreatedAtUtc, UpdatedAtUtc, OtherCategoryDescription, CoverKey
                )
                OUTPUT inserted.Id, inserted.PublicId, inserted.RowVersion
                    INTO @InsertedOpportunity (Id, PublicId, RowVersion)
                VALUES
                (
                    LTRIM(RTRIM(@Slug)), LTRIM(RTRIM(@Title)), @Description, @Summary,
                    LTRIM(RTRIM(@SponsorName)), @SponsorUrl, @ApplicationUrl,
                    @IssuerCountryId, @FundingTypeId, @Currency, @MinAmount, @MaxAmount,
                    @AmountStatus, @OpenDate, @CloseDate, @CloseAtUtc, @DeadlineTimeZoneId,
                    @DeadlineType, @DeadlinePrecision, @EligibilityDescription, @Requirements,
                    @Objectives, @AllowedActivities, @ExcludedActivities, @Restrictions,
                    @TargetOrganizationsDescription, @TargetPopulationsDescription,
                    @MinimumOperatingYears, @RequiresLegalEntity, @RequiresPriorExperience,
                    @RequiresCofunding, @CofundingPercentage, @GeographicScope,
                    @RemoteApplication, 0, NULL, COALESCE(@LastVerifiedAtUtc, @NowUtc),
                    @DataQualityScore, 1,
                    @ContentHash, 1, @ActorUserId, @ActorUserId, @NowUtc, @NowUtc, @OtherCategoryDescription, @CoverKey
                );
                SELECT @OpportunityId = Id, @OpportunityPublicId = PublicId, @RowVersion = RowVersion
                FROM @InsertedOpportunity;
                IF @OwnerWorkspace = 1
                    INSERT INTO dbo.FundingPlatform_OpportunityWorkspaceOwners(FundingOpportunityId, FunderId)
                    SELECT @OpportunityId, FunderId FROM @RequestedFunders WHERE Role = 1;

                DECLARE @InsertedSourceLink TABLE (Id BIGINT);
                INSERT INTO dbo.FundingPlatform_FundingOpportunitySourceLinks
                    (FundingOpportunityId, FundingSourceId, ExternalId, SourceItemKeyHash,
                     SourceUrl, CanonicalUrlHash, FirstSeenAtUtc, LastSeenAtUtc, IsPrimary, IsActive)
                OUTPUT inserted.Id INTO @InsertedSourceLink (Id)
                VALUES (@OpportunityId, @FundingSourceId, @ExternalId, @SourceItemKeyHash,
                        @SourceUrl, @CanonicalUrlHash, @NowUtc, @NowUtc, 1, 1);
                SELECT @SourceLinkId = Id FROM @InsertedSourceLink;

                INSERT INTO dbo.FundingPlatform_FundingOpportunityCountries
                    (FundingOpportunityId, CountryId)
                SELECT @OpportunityId, Id FROM @CountryIds;
                INSERT INTO dbo.FundingPlatform_FundingOpportunityRegions
                    (FundingOpportunityId, RegionId)
                SELECT @OpportunityId, Id FROM @RegionIds;
                INSERT INTO dbo.FundingPlatform_FundingOpportunityCategories
                    (FundingOpportunityId, FundingCategoryId)
                SELECT @OpportunityId, Id FROM @CategoryIds;
                INSERT INTO dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes
                    (FundingOpportunityId, BeneficiaryTypeId)
                SELECT @OpportunityId, Id FROM @BeneficiaryTypeIds;
                INSERT INTO dbo.FundingPlatform_FundingOpportunityProjectTypes
                    (FundingOpportunityId, ProjectTypeId)
                SELECT @OpportunityId, Id FROM @ProjectTypeIds;

                DECLARE @CriticalEvidence TABLE
                    (FieldPath NVARCHAR(200), ValueText NVARCHAR(MAX), StatusCode NVARCHAR(20),
                     EvidenceText NVARCHAR(2000));
                INSERT INTO @CriticalEvidence VALUES
                    (N'/title', @Title, N'known', LEFT(@Title, 2000)),
                    (N'/description', @Description,
                     CASE WHEN NULLIF(LTRIM(RTRIM(@Description)), N'') IS NULL THEN N'unknown' ELSE N'known' END,
                     LEFT(@Description, 2000)),
                    (N'/eligibilityDescription', @EligibilityDescription,
                     CASE WHEN NULLIF(LTRIM(RTRIM(@EligibilityDescription)), N'') IS NULL THEN N'unknown' ELSE N'known' END,
                     LEFT(@EligibilityDescription, 2000)),
                    (N'/closeDate', CONVERT(NVARCHAR(30), @CloseDate, 23),
                     CASE WHEN @CloseDate IS NULL THEN N'unknown' ELSE N'known' END,
                     CONVERT(NVARCHAR(30), @CloseDate, 23)),
                    (N'/sponsorName', @SponsorName, N'known', LEFT(@SponsorName, 2000));
                INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
                    (FundingOpportunityId, FieldPath, ValueJson, FundingOpportunitySourceLinkId,
                     ExtractionMethod, EvidenceText, SourceLocator, Confidence,
                     IsSelected, IsManualLock, CreatedByUserId, CreatedAtUtc)
                SELECT @OpportunityId, critical.FieldPath,
                       (SELECT critical.ValueText AS [value], critical.StatusCode AS [status]
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
                       @SourceLinkId, 1, critical.EvidenceText, LEFT(@SourceUrl, 500),
                       100, 1, 1, @ActorUserId, @NowUtc
                FROM @CriticalEvidence AS critical;
                INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
                    (FundingOpportunityId, FieldPath, ValueJson, FundingOpportunitySourceLinkId,
                     ExtractionMethod, EvidenceText, SourceLocator, Confidence,
                     IsSelected, IsManualLock, CreatedByUserId, CreatedAtUtc)
                SELECT @OpportunityId, extra.FieldPath, extra.ValueJson, @SourceLinkId, 1,
                       extra.EvidenceText, COALESCE(extra.SourceLocator, LEFT(@SourceUrl, 500)),
                       extra.Confidence, 1, extra.IsManualLock, @ActorUserId, @NowUtc
                FROM @ExtraEvidence AS extra;

                DECLARE @SponsorEvidenceId BIGINT =
                    (SELECT Id FROM dbo.FundingPlatform_FundingFieldEvidence
                     WHERE FundingOpportunityId = @OpportunityId
                       AND FieldPath = N'/sponsorName' AND IsSelected = 1);
                INSERT INTO dbo.FundingPlatform_FundingOpportunityFunders
                    (FundingOpportunityId, FunderId, Role, EvidenceId, IsActive,
                     CreatedAtUtc, UpdatedAtUtc)
                SELECT @OpportunityId, FunderId, Role,
                       CASE WHEN Role = 1 THEN @SponsorEvidenceId ELSE NULL END,
                       1, @NowUtc, @NowUtc
                FROM @RequestedFunders;

                INSERT INTO dbo.FundingPlatform_FundingOpportunityVersions
                    (FundingOpportunityId, ContentVersion, SnapshotJson, ContentHash,
                     CreatedByUserId, CreatedAtUtc)
                VALUES (@OpportunityId, 1, @SnapshotJson, @ContentHash, @ActorUserId, @NowUtc);
                INSERT INTO dbo.FundingPlatform_FundingOpportunityEditorialEvents
                    (EventId, FundingOpportunityId, ContentVersion, FromStatus, ToStatus,
                     ActionCode, ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                     ResultRowVersion, CreatedAtUtc)
                VALUES (@EventId, @OpportunityId, 1, 0, 0, N'Create', @ActorUserId, NULL,
                        @IdempotencyKeyHash, @RequestHash, @RowVersion, @NowUtc);
                INSERT INTO dbo.FundingPlatform_OutboxMessages
                    (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                     OccurredAtUtc, AvailableAtUtc)
                SELECT @EventId, N'FundingOpportunityDraftCreated', N'FundingOpportunity',
                       CONVERT(NVARCHAR(100), @OpportunityId),
                       (SELECT @EventId AS eventId, @OpportunityId AS fundingOpportunityId,
                               @OpportunityPublicId AS fundingOpportunityPublicId, 1 AS contentVersion
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                SET @Succeeded = 1; SET @Code = N'created';
            END;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_OppCreate;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @OpportunityPublicId AS FundingOpportunityPublicId,
           CASE WHEN @OpportunityId IS NULL THEN NULL ELSE 1 END AS ContentVersion,
           CASE WHEN @OpportunityId IS NULL THEN NULL ELSE 0 END AS PublicationStatus,
           @RowVersion AS RowVersion, @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Update
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FundingOpportunityPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @Title NVARCHAR(350), @Description NVARCHAR(MAX) = NULL,
    @Summary NVARCHAR(2000) = NULL, @SponsorName NVARCHAR(300),
    @SponsorUrl NVARCHAR(2048) = NULL, @ApplicationUrl NVARCHAR(2048) = NULL,
    @IssuerCountryId SMALLINT = NULL, @FundingTypeId SMALLINT = NULL,
    @Currency CHAR(3) = NULL, @MinAmount DECIMAL(19,4) = NULL,
    @MaxAmount DECIMAL(19,4) = NULL, @AmountStatus TINYINT,
    @OpenDate DATE = NULL, @CloseDate DATE = NULL, @CloseAtUtc DATETIME2(3) = NULL,
    @DeadlineTimeZoneId NVARCHAR(100) = NULL, @DeadlineType TINYINT,
    @DeadlinePrecision TINYINT, @EligibilityDescription NVARCHAR(MAX) = NULL,
    @Requirements NVARCHAR(MAX) = NULL, @Objectives NVARCHAR(MAX) = NULL,
    @AllowedActivities NVARCHAR(MAX) = NULL, @ExcludedActivities NVARCHAR(MAX) = NULL,
    @Restrictions NVARCHAR(MAX) = NULL,
    @TargetOrganizationsDescription NVARCHAR(2000) = NULL,
    @TargetPopulationsDescription NVARCHAR(2000) = NULL,
    @MinimumOperatingYears SMALLINT = NULL, @RequiresLegalEntity BIT = NULL,
    @RequiresPriorExperience BIT = NULL, @RequiresCofunding BIT = NULL,
    @CofundingPercentage DECIMAL(5,2) = NULL, @GeographicScope TINYINT,
    @RemoteApplication TINYINT, @LastVerifiedAtUtc DATETIME2(3) = NULL,
    @DataQualityScore DECIMAL(5,2),
    @FundingSourceId INT, @ExternalId NVARCHAR(250) = NULL,
    @SourceItemKeyHash BINARY(32), @SourceUrl NVARCHAR(2048),
    @CanonicalUrlHash BINARY(32) = NULL,
    @SnapshotJson NVARCHAR(MAX), @ContentHash BINARY(32),
    @CountryIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @RegionIds dbo.FundingPlatform_IntIdList READONLY,
    @CategoryIds dbo.FundingPlatform_IntIdList READONLY,
    @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @FunderLinksJson NVARCHAR(MAX), @EvidenceJson NVARCHAR(MAX) = N'[]',
    @IdempotencyKeyHash BINARY(32), @RequestHash BINARY(32),
    @OwnerWorkspace BIT = 0,
    @OtherCategoryDescription NVARCHAR(MAX) = NULL,
    @CoverKey NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @OwnerWorkspace IS NULL THROW 51601, N'Invalid workspace scope.', 1;
    DECLARE @WorkspaceActorUserId BIGINT;
    IF @OwnerWorkspace = 1
        EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 2, @FundingOpportunityPublicId, @WorkspaceActorUserId OUTPUT;
    ELSE
    BEGIN
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    END;
    IF ISJSON(@SnapshotJson) <> 1 OR LEFT(LTRIM(@SnapshotJson), 1) <> N'{'
        THROW 51609, N'SnapshotJson must be a JSON object.', 1;


    SET @CoverKey = NULLIF(LTRIM(RTRIM(@CoverKey)), N'');
    IF (@CoverKey IS NOT NULL AND (DATALENGTH(@CoverKey) > 80
        OR @CoverKey COLLATE Latin1_General_100_BIN2 NOT IN
            (N'auto', N'nature-v1', N'education-v1', N'community-v1', N'research-v1')))
       OR (SELECT COUNT(*) FROM OPENJSON(@SnapshotJson) WHERE [key] COLLATE Latin1_General_100_BIN2 = N'coverKey') > 1
       OR EXISTS(SELECT 1 FROM OPENJSON(@SnapshotJson) WHERE [key] COLLATE Latin1_General_100_BIN2 = N'coverKey'
                 AND ([type] NOT IN(0,1) OR DATALENGTH([value]) > 80))
       OR COALESCE(JSON_VALUE(@SnapshotJson, '$.coverKey'), N'') COLLATE Latin1_General_100_BIN2
          <> COALESCE(@CoverKey, N'') COLLATE Latin1_General_100_BIN2
       OR DATALENGTH(COALESCE(JSON_VALUE(@SnapshotJson, '$.coverKey'), N''))
          <> DATALENGTH(COALESCE(@CoverKey, N''))
        THROW 56090, N'Cover key must be in the bundled library and match its version snapshot.', 1;

    SET @OtherCategoryDescription = NULLIF(LTRIM(RTRIM(@OtherCategoryDescription)), N'');
    IF DATALENGTH(@OtherCategoryDescription) > 400
       OR (EXISTS(SELECT 1 FROM @CategoryIds WHERE Id = 16) AND @OtherCategoryDescription IS NULL)
       OR (NOT EXISTS(SELECT 1 FROM @CategoryIds WHERE Id = 16) AND @OtherCategoryDescription IS NOT NULL)
       OR (SELECT COUNT(*) FROM OPENJSON(@SnapshotJson) WHERE [key] COLLATE Latin1_General_100_BIN2 = N'otherCategoryDescription') > 1
       OR EXISTS(SELECT 1 FROM OPENJSON(@SnapshotJson) WHERE [key] COLLATE Latin1_General_100_BIN2 = N'otherCategoryDescription' AND ([type] NOT IN(0,1) OR DATALENGTH([value]) > 400))
       OR COALESCE(JSON_VALUE(@SnapshotJson, '$.otherCategoryDescription'), N'') COLLATE Latin1_General_100_BIN2
          <> COALESCE(@OtherCategoryDescription, N'') COLLATE Latin1_General_100_BIN2
       OR DATALENGTH(COALESCE(JSON_VALUE(@SnapshotJson, '$.otherCategoryDescription'), N''))
          <> DATALENGTH(COALESCE(@OtherCategoryDescription, N''))
        THROW 51609, N'Other category must be selected, specified and match its version snapshot.', 1;
    IF ISJSON(COALESCE(@FunderLinksJson, N'[]')) <> 1
       OR LEFT(LTRIM(COALESCE(@FunderLinksJson, N'[]')), 1) <> N'['
        THROW 51610, N'FunderLinksJson must be a JSON array.', 1;
    IF ISJSON(COALESCE(@EvidenceJson, N'[]')) <> 1
       OR LEFT(LTRIM(COALESCE(@EvidenceJson, N'[]')), 1) <> N'['
        THROW 51611, N'EvidenceJson must be a JSON array.', 1;

    DECLARE @ActorUserId BIGINT, @OpportunityId BIGINT, @CurrentSlug NVARCHAR(320);
    DECLARE @CurrentStatus TINYINT, @CurrentVersion INT, @NextVersion INT;
    DECLARE @CurrentCoverKey NVARCHAR(40);
    DECLARE @CurrentRowVersion BINARY(8), @RowVersion BINARY(8), @SourceLinkId BIGINT;
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @RawFunderCount INT =
        (SELECT COUNT(1) FROM OPENJSON(COALESCE(@FunderLinksJson, N'[]')));
    DECLARE @RawEvidenceCount INT =
        (SELECT COUNT(1) FROM OPENJSON(COALESCE(@EvidenceJson, N'[]')));
    DECLARE @RequestedFunders TABLE
    (
        FunderPublicId UNIQUEIDENTIFIER NOT NULL,
        Role TINYINT NOT NULL,
        FunderId BIGINT NULL,
        PRIMARY KEY (FunderPublicId)
    );
    DECLARE @ExtraEvidence TABLE
    (
        FieldPath NVARCHAR(200) NOT NULL PRIMARY KEY,
        ValueJson NVARCHAR(MAX) NOT NULL,
        EvidenceText NVARCHAR(2000) NULL,
        SourceLocator NVARCHAR(500) NULL,
        Confidence DECIMAL(5,2) NULL,
        IsManualLock BIT NOT NULL
    );

    INSERT INTO @RequestedFunders (FunderPublicId, Role)
    SELECT TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(items.value, '$.funderPublicId')),
           MIN(TRY_CONVERT(TINYINT, JSON_VALUE(items.value, '$.role')))
    FROM OPENJSON(COALESCE(@FunderLinksJson, N'[]')) AS items
    WHERE TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(items.value, '$.funderPublicId')) IS NOT NULL
      AND TRY_CONVERT(TINYINT, JSON_VALUE(items.value, '$.role')) BETWEEN 1 AND 3
    GROUP BY TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(items.value, '$.funderPublicId'))
    HAVING COUNT_BIG(1) = 1;

    INSERT INTO @ExtraEvidence
        (FieldPath, ValueJson, EvidenceText, SourceLocator, Confidence, IsManualLock)
    SELECT JSON_VALUE(items.value, '$.fieldPath'),
           MAX(JSON_QUERY(items.value, '$.valueJson')),
           MAX(JSON_VALUE(items.value, '$.evidenceText')),
           MAX(JSON_VALUE(items.value, '$.sourceLocator')),
           MAX(TRY_CONVERT(DECIMAL(5,2), JSON_VALUE(items.value, '$.confidence'))),
           MAX(CONVERT(TINYINT,
               COALESCE(TRY_CONVERT(BIT, JSON_VALUE(items.value, '$.isManualLock')), 1)))
    FROM OPENJSON(COALESCE(@EvidenceJson, N'[]')) AS items
    WHERE LEFT(JSON_VALUE(items.value, '$.fieldPath'), 1) = N'/'
      AND LEN(JSON_VALUE(items.value, '$.fieldPath')) BETWEEN 2 AND 200
      AND JSON_QUERY(items.value, '$.valueJson') IS NOT NULL
      AND LEFT(LTRIM(JSON_QUERY(items.value, '$.valueJson')), 1) = N'{'
      AND (JSON_VALUE(items.value, '$.evidenceText') IS NULL
           OR LEN(JSON_VALUE(items.value, '$.evidenceText')) <= 2000)
      AND (JSON_VALUE(items.value, '$.sourceLocator') IS NULL
           OR LEN(JSON_VALUE(items.value, '$.sourceLocator')) <= 500)
      AND (JSON_VALUE(items.value, '$.confidence') IS NULL
           OR TRY_CONVERT(DECIMAL(5,2), JSON_VALUE(items.value, '$.confidence')) BETWEEN 0 AND 100)
      AND (JSON_VALUE(items.value, '$.isManualLock') IS NULL
           OR TRY_CONVERT(BIT, JSON_VALUE(items.value, '$.isManualLock')) IS NOT NULL)
      AND JSON_VALUE(items.value, '$.fieldPath') NOT IN
          (N'/title', N'/description', N'/eligibilityDescription', N'/closeDate', N'/sponsorName')
    GROUP BY JSON_VALUE(items.value, '$.fieldPath')
    HAVING COUNT_BIG(1) = 1;

    IF NULLIF(LTRIM(RTRIM(@Title)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@SponsorName)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@SourceUrl)), N'') IS NULL
       OR @RawFunderCount <> (SELECT COUNT(1) FROM @RequestedFunders)
       OR @RawEvidenceCount <> (SELECT COUNT(1) FROM @ExtraEvidence)
       OR (SELECT COUNT(1) FROM @RequestedFunders WHERE Role = 1) <> 1
       OR @AmountStatus NOT BETWEEN 0 AND 2
       OR (@AmountStatus = 1 AND (@Currency IS NULL OR (@MinAmount IS NULL AND @MaxAmount IS NULL)))
       OR (@AmountStatus IN (0, 2) AND (@Currency IS NOT NULL OR @MinAmount IS NOT NULL OR @MaxAmount IS NOT NULL))
       OR @MinAmount < 0 OR @MaxAmount < COALESCE(@MinAmount, 0)
       OR @DeadlineType NOT BETWEEN 0 AND 2 OR @DeadlinePrecision NOT BETWEEN 0 AND 2
       OR (@DeadlineType = 0 AND (@DeadlinePrecision <> 0 OR @CloseAtUtc IS NOT NULL))
       OR (@DeadlineType = 2 AND (@DeadlinePrecision <> 0 OR @CloseDate IS NOT NULL OR @CloseAtUtc IS NOT NULL))
       OR (@DeadlineType = 1 AND @DeadlinePrecision NOT IN (1, 2))
       OR (@DeadlineType = 1 AND @DeadlinePrecision = 1 AND (@CloseDate IS NULL OR @CloseAtUtc IS NOT NULL))
       OR (@DeadlineType = 1 AND @DeadlinePrecision = 2
           AND (@CloseDate IS NULL OR @CloseAtUtc IS NULL OR @DeadlineTimeZoneId IS NULL))
       OR (@OpenDate IS NOT NULL AND @CloseDate IS NOT NULL AND @OpenDate > @CloseDate)
       OR @GeographicScope NOT BETWEEN 0 AND 2 OR @RemoteApplication NOT BETWEEN 0 AND 2
       OR (@GeographicScope = 0
           AND (EXISTS (SELECT 1 FROM @CountryIds) OR EXISTS (SELECT 1 FROM @RegionIds)))
       OR (@GeographicScope = 1 AND NOT EXISTS (SELECT 1 FROM @CountryIds))
       OR (@GeographicScope = 2
           AND (EXISTS (SELECT 1 FROM @CountryIds) OR EXISTS (SELECT 1 FROM @RegionIds)))
       OR @DataQualityScore NOT BETWEEN 0 AND 100
       OR @MinimumOperatingYears < 0
       OR @CofundingPercentage < 0 OR @CofundingPercentage > 100
       OR (@RequiresCofunding IS NULL AND @CofundingPercentage IS NOT NULL)
       OR (@RequiresCofunding = 0 AND COALESCE(@CofundingPercentage, 0) <> 0)
       OR (@RequiresCofunding = 1 AND COALESCE(@CofundingPercentage, 0) <= 0)
       OR (@LastVerifiedAtUtc IS NOT NULL
           AND @LastVerifiedAtUtc > DATEADD(MINUTE, 5, SYSUTCDATETIME()))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               @FundingOpportunityPublicId AS FundingOpportunityPublicId,
               CAST(NULL AS INT) AS ContentVersion, CAST(NULL AS TINYINT) AS PublicationStatus,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_OppUpdate;
    BEGIN TRY
        IF @OwnerWorkspace = 1
            EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 2, @FundingOpportunityPublicId, @ActorUserId OUTPUT;
        ELSE
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        IF @OwnerWorkspace = 1
        BEGIN
            /* Native submission provenance and exactly one owned primary funder.
               Existing/imported records cannot be adopted through a link or a replay. */
            IF (SELECT COUNT_BIG(1) FROM @RequestedFunders) <> 1
               OR NOT EXISTS (SELECT 1 FROM @RequestedFunders AS requested
                   INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.PublicId = requested.FunderPublicId
                   INNER JOIN dbo.FundingPlatform_FunderWorkspaceOwners AS owners WITH (UPDLOCK, HOLDLOCK) ON owners.FunderId = funders.Id
                   WHERE requested.Role = 1 AND owners.UserId = @ActorUserId AND owners.IsActive = 1)
               OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingSources WHERE Id = @FundingSourceId AND ProviderCode = N'funder-workspace' AND IsEnabled = 1)
                THROW 51601, N'Workspace funder or source is not permitted.', 1;
            IF NOT EXISTS (SELECT 1 FROM @RequestedFunders AS requested
                INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.PublicId = requested.FunderPublicId
                INNER JOIN dbo.FundingPlatform_OpportunityWorkspaceOwners AS managed ON managed.FunderId = funders.Id
                INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities ON opportunities.Id = managed.FundingOpportunityId
                WHERE opportunities.PublicId = @FundingOpportunityPublicId)
                THROW 51601, N'Workspace ownership cannot be transferred.', 1;
        END;
        SELECT @ActorUserId = Id FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;
        SELECT @OpportunityId = Id, @CurrentSlug = Slug, @CurrentStatus = PublicationStatus,
               @CurrentVersion = ContentVersion, @CurrentRowVersion = RowVersion, @CurrentCoverKey = CoverKey
        FROM dbo.FundingPlatform_FundingOpportunities WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @FundingOpportunityPublicId;

        IF @OpportunityId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = ActionCode, @ExistingRequestHash = RequestHash,
                   @ExistingToStatus = ToStatus, @NextVersion = ContentVersion,
                   @RowVersion = ResultRowVersion
            FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE FundingOpportunityId = @OpportunityId
              AND IdempotencyKeyHash = @IdempotencyKeyHash;
            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'Update' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'updated';
                    SET @CurrentStatus = @ExistingToStatus;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus NOT IN (0, 3) SET @Code = N'invalid-transition';
            /* Old clients may not erase an editorial cover. Explicit auto resets it. */
            ELSE IF @CoverKey IS NULL AND @CurrentCoverKey IS NOT NULL SET @Code = N'cover-selection-required';
            ELSE
            BEGIN
                UPDATE requested SET FunderId = funders.Id
                FROM @RequestedFunders AS requested
                INNER JOIN dbo.FundingPlatform_Funders AS funders WITH (UPDLOCK, HOLDLOCK)
                    ON funders.PublicId = requested.FunderPublicId
                   AND funders.IsActive = 1 AND funders.PublicationStatus <> 4;

                SELECT @SourceLinkId = links.Id
                FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
                    WITH (UPDLOCK, HOLDLOCK)
                WHERE links.FundingOpportunityId = @OpportunityId
                  AND links.FundingSourceId = @FundingSourceId
                  AND links.SourceItemKeyHash = @SourceItemKeyHash;

                IF EXISTS (SELECT 1 FROM @RequestedFunders WHERE FunderId IS NULL)
                    SET @Code = N'funder-not-found';
                ELSE IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingSources
                                    WHERE Id = @FundingSourceId AND IsEnabled = 1)
                    SET @Code = N'source-disabled';
                ELSE IF (@IssuerCountryId IS NOT NULL AND NOT EXISTS
                         (SELECT 1 FROM dbo.FundingPlatform_Countries
                          WHERE Id = @IssuerCountryId AND IsActive = 1))
                     OR (@FundingTypeId IS NOT NULL AND NOT EXISTS
                         (SELECT 1 FROM dbo.FundingPlatform_FundingTypes
                          WHERE Id = @FundingTypeId AND IsActive = 1))
                     OR (@Currency IS NOT NULL AND NOT EXISTS
                         (SELECT 1 FROM dbo.FundingPlatform_Currencies
                          WHERE Code = @Currency AND IsActive = 1))
                     OR EXISTS (SELECT 1 FROM @CountryIds AS selected
                                LEFT JOIN dbo.FundingPlatform_Countries AS catalog
                                    ON catalog.Id = selected.Id AND catalog.IsActive = 1
                                WHERE catalog.Id IS NULL)
                     OR EXISTS (SELECT 1 FROM @CategoryIds AS selected
                                LEFT JOIN dbo.FundingPlatform_FundingCategories AS catalog
                                    ON catalog.Id = selected.Id AND catalog.IsActive = 1
                                WHERE catalog.Id IS NULL)
                     OR EXISTS (SELECT 1 FROM @BeneficiaryTypeIds AS selected
                                LEFT JOIN dbo.FundingPlatform_BeneficiaryTypes AS catalog
                                    ON catalog.Id = selected.Id AND catalog.IsActive = 1
                                WHERE catalog.Id IS NULL)
                     OR EXISTS (SELECT 1 FROM @ProjectTypeIds AS selected
                                LEFT JOIN dbo.FundingPlatform_ProjectTypes AS catalog
                                    ON catalog.Id = selected.Id AND catalog.IsActive = 1
                                WHERE catalog.Id IS NULL)
                    SET @Code = N'invalid-document';
                ELSE IF EXISTS
                (
                    SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks WITH (UPDLOCK, HOLDLOCK)
                    WHERE FundingSourceId = @FundingSourceId
                      AND Id <> COALESCE(@SourceLinkId, -1)
                      AND (SourceItemKeyHash = @SourceItemKeyHash
                           OR (@ExternalId IS NOT NULL AND ExternalId = @ExternalId))
                ) SET @Code = N'source-link-conflict';
                ELSE IF EXISTS
                (
                    SELECT 1 FROM @RegionIds AS selected
                    LEFT JOIN dbo.FundingPlatform_Regions AS regions
                        ON regions.Id = selected.Id AND regions.IsActive = 1
                    WHERE regions.Id IS NULL
                       OR NOT EXISTS (SELECT 1 FROM @CountryIds AS countries
                                      WHERE countries.Id = regions.CountryId)
                ) SET @Code = N'invalid-document';
                ELSE
                BEGIN
                    SET @NextVersion = @CurrentVersion + 1;
                    DECLARE @UpdatedOpportunity TABLE (RowVersion BINARY(8));
                    UPDATE dbo.FundingPlatform_FundingOpportunities
                    SET CoverKey = @CoverKey, OtherCategoryDescription = @OtherCategoryDescription,
                        Title = LTRIM(RTRIM(@Title)), Description = @Description, Summary = @Summary,
                        SponsorName = LTRIM(RTRIM(@SponsorName)), SponsorUrl = @SponsorUrl,
                        ApplicationUrl = @ApplicationUrl, IssuerCountryId = @IssuerCountryId,
                        FundingTypeId = @FundingTypeId, Currency = @Currency,
                        MinAmount = @MinAmount, MaxAmount = @MaxAmount, AmountStatus = @AmountStatus,
                        OpenDate = @OpenDate, CloseDate = @CloseDate, CloseAtUtc = @CloseAtUtc,
                        DeadlineTimeZoneId = @DeadlineTimeZoneId, DeadlineType = @DeadlineType,
                        DeadlinePrecision = @DeadlinePrecision,
                        EligibilityDescription = @EligibilityDescription, Requirements = @Requirements,
                        Objectives = @Objectives, AllowedActivities = @AllowedActivities,
                        ExcludedActivities = @ExcludedActivities, Restrictions = @Restrictions,
                        TargetOrganizationsDescription = @TargetOrganizationsDescription,
                        TargetPopulationsDescription = @TargetPopulationsDescription,
                        MinimumOperatingYears = @MinimumOperatingYears,
                        RequiresLegalEntity = @RequiresLegalEntity,
                        RequiresPriorExperience = @RequiresPriorExperience,
                        RequiresCofunding = @RequiresCofunding,
                        CofundingPercentage = @CofundingPercentage,
                        GeographicScope = @GeographicScope, RemoteApplication = @RemoteApplication,
                        LastVerifiedAtUtc = COALESCE(@LastVerifiedAtUtc, @NowUtc),
                        DataQualityScore = @DataQualityScore,
                        ContentVersion = @NextVersion, ContentFingerprint = @ContentHash,
                        UpdatedByUserId = @ActorUserId, UpdatedAtUtc = @NowUtc
                    OUTPUT inserted.RowVersion INTO @UpdatedOpportunity (RowVersion)
                    WHERE Id = @OpportunityId AND RowVersion = @ExpectedRowVersion;
                    SELECT @RowVersion = RowVersion FROM @UpdatedOpportunity;

                    IF @RowVersion IS NULL SET @Code = N'etag-conflict';
                    ELSE
                    BEGIN
                        UPDATE dbo.FundingPlatform_FundingOpportunitySourceLinks
                        SET IsPrimary = 0
                        WHERE FundingOpportunityId = @OpportunityId AND IsPrimary = 1;
                        SELECT @SourceLinkId = Id
                        FROM dbo.FundingPlatform_FundingOpportunitySourceLinks
                        WHERE FundingOpportunityId = @OpportunityId
                          AND FundingSourceId = @FundingSourceId
                          AND SourceItemKeyHash = @SourceItemKeyHash;
                        IF @SourceLinkId IS NULL
                        BEGIN
                            DECLARE @InsertedSourceLink TABLE (Id BIGINT);
                            INSERT INTO dbo.FundingPlatform_FundingOpportunitySourceLinks
                                (FundingOpportunityId, FundingSourceId, ExternalId, SourceItemKeyHash,
                                 SourceUrl, CanonicalUrlHash, FirstSeenAtUtc, LastSeenAtUtc,
                                 IsPrimary, IsActive)
                            OUTPUT inserted.Id INTO @InsertedSourceLink (Id)
                            VALUES (@OpportunityId, @FundingSourceId, @ExternalId, @SourceItemKeyHash,
                                    @SourceUrl, @CanonicalUrlHash, @NowUtc, @NowUtc, 1, 1);
                            SELECT @SourceLinkId = Id FROM @InsertedSourceLink;
                        END
                        ELSE
                            UPDATE dbo.FundingPlatform_FundingOpportunitySourceLinks
                            SET ExternalId = @ExternalId, SourceUrl = @SourceUrl,
                                CanonicalUrlHash = @CanonicalUrlHash, LastSeenAtUtc = @NowUtc,
                                IsPrimary = 1, IsActive = 1
                            WHERE Id = @SourceLinkId;

                        DELETE FROM dbo.FundingPlatform_FundingOpportunityCountries
                        WHERE FundingOpportunityId = @OpportunityId;
                        DELETE FROM dbo.FundingPlatform_FundingOpportunityRegions
                        WHERE FundingOpportunityId = @OpportunityId;
                        DELETE FROM dbo.FundingPlatform_FundingOpportunityCategories
                        WHERE FundingOpportunityId = @OpportunityId;
                        DELETE FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes
                        WHERE FundingOpportunityId = @OpportunityId;
                        DELETE FROM dbo.FundingPlatform_FundingOpportunityProjectTypes
                        WHERE FundingOpportunityId = @OpportunityId;
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityCountries
                            (FundingOpportunityId, CountryId) SELECT @OpportunityId, Id FROM @CountryIds;
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityRegions
                            (FundingOpportunityId, RegionId) SELECT @OpportunityId, Id FROM @RegionIds;
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityCategories
                            (FundingOpportunityId, FundingCategoryId) SELECT @OpportunityId, Id FROM @CategoryIds;
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes
                            (FundingOpportunityId, BeneficiaryTypeId)
                        SELECT @OpportunityId, Id FROM @BeneficiaryTypeIds;
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityProjectTypes
                            (FundingOpportunityId, ProjectTypeId)
                        SELECT @OpportunityId, Id FROM @ProjectTypeIds;

                        UPDATE dbo.FundingPlatform_FundingOpportunityFunders
                        SET IsActive = 0, UpdatedAtUtc = @NowUtc
                        WHERE FundingOpportunityId = @OpportunityId AND IsActive = 1;
                        UPDATE links
                        SET Role = requested.Role, EvidenceId = NULL,
                            IsActive = 1, UpdatedAtUtc = @NowUtc
                        FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
                        INNER JOIN @RequestedFunders AS requested
                            ON requested.FunderId = links.FunderId
                        WHERE links.FundingOpportunityId = @OpportunityId;
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityFunders
                            (FundingOpportunityId, FunderId, Role, EvidenceId, IsActive,
                             CreatedAtUtc, UpdatedAtUtc)
                        SELECT @OpportunityId, requested.FunderId, requested.Role, NULL, 1,
                               @NowUtc, @NowUtc
                        FROM @RequestedFunders AS requested
                        WHERE NOT EXISTS
                        (
                            SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunders AS existing
                            WHERE existing.FundingOpportunityId = @OpportunityId
                              AND existing.FunderId = requested.FunderId
                        );

                        UPDATE evidence
                        SET IsSelected = 0
                        FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
                        WHERE evidence.FundingOpportunityId = @OpportunityId
                          AND evidence.IsSelected = 1
                          AND
                          (
                              evidence.FieldPath IN
                                  (N'/title', N'/description', N'/eligibilityDescription',
                                   N'/closeDate', N'/sponsorName')
                              OR EXISTS
                                 (SELECT 1 FROM @ExtraEvidence AS replacement
                                  WHERE replacement.FieldPath = evidence.FieldPath)
                          );
                        DECLARE @CriticalEvidence TABLE
                            (FieldPath NVARCHAR(200), ValueText NVARCHAR(MAX), StatusCode NVARCHAR(20),
                             EvidenceText NVARCHAR(2000));
                        INSERT INTO @CriticalEvidence VALUES
                            (N'/title', @Title, N'known', LEFT(@Title, 2000)),
                            (N'/description', @Description,
                             CASE WHEN NULLIF(LTRIM(RTRIM(@Description)), N'') IS NULL THEN N'unknown' ELSE N'known' END,
                             LEFT(@Description, 2000)),
                            (N'/eligibilityDescription', @EligibilityDescription,
                             CASE WHEN NULLIF(LTRIM(RTRIM(@EligibilityDescription)), N'') IS NULL THEN N'unknown' ELSE N'known' END,
                             LEFT(@EligibilityDescription, 2000)),
                            (N'/closeDate', CONVERT(NVARCHAR(30), @CloseDate, 23),
                             CASE WHEN @CloseDate IS NULL THEN N'unknown' ELSE N'known' END,
                             CONVERT(NVARCHAR(30), @CloseDate, 23)),
                            (N'/sponsorName', @SponsorName, N'known', LEFT(@SponsorName, 2000));
                        INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
                            (FundingOpportunityId, FieldPath, ValueJson, FundingOpportunitySourceLinkId,
                             ExtractionMethod, EvidenceText, SourceLocator, Confidence,
                             IsSelected, IsManualLock, CreatedByUserId, CreatedAtUtc)
                        SELECT @OpportunityId, critical.FieldPath,
                               (SELECT critical.ValueText AS [value], critical.StatusCode AS [status]
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
                               @SourceLinkId, 1, critical.EvidenceText, LEFT(@SourceUrl, 500),
                               100, 1, 1, @ActorUserId, @NowUtc
                        FROM @CriticalEvidence AS critical;
                        INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
                            (FundingOpportunityId, FieldPath, ValueJson, FundingOpportunitySourceLinkId,
                             ExtractionMethod, EvidenceText, SourceLocator, Confidence,
                             IsSelected, IsManualLock, CreatedByUserId, CreatedAtUtc)
                        SELECT @OpportunityId, extra.FieldPath, extra.ValueJson, @SourceLinkId, 1,
                               extra.EvidenceText, COALESCE(extra.SourceLocator, LEFT(@SourceUrl, 500)),
                               extra.Confidence, 1, extra.IsManualLock, @ActorUserId, @NowUtc
                        FROM @ExtraEvidence AS extra;
                        DECLARE @SponsorEvidenceId BIGINT =
                            (SELECT Id FROM dbo.FundingPlatform_FundingFieldEvidence
                             WHERE FundingOpportunityId = @OpportunityId
                               AND FieldPath = N'/sponsorName' AND IsSelected = 1);
                        UPDATE links SET EvidenceId = @SponsorEvidenceId
                        FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
                        WHERE links.FundingOpportunityId = @OpportunityId
                          AND links.Role = 1 AND links.IsActive = 1;

                        INSERT INTO dbo.FundingPlatform_FundingOpportunityVersions
                            (FundingOpportunityId, ContentVersion, SnapshotJson, ContentHash,
                             CreatedByUserId, CreatedAtUtc)
                        VALUES (@OpportunityId, @NextVersion, @SnapshotJson, @ContentHash,
                                @ActorUserId, @NowUtc);
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityEditorialEvents
                            (EventId, FundingOpportunityId, ContentVersion, FromStatus, ToStatus,
                             ActionCode, ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                             ResultRowVersion, CreatedAtUtc)
                        VALUES (@EventId, @OpportunityId, @NextVersion, @CurrentStatus, @CurrentStatus,
                                N'Update', @ActorUserId, NULL, @IdempotencyKeyHash,
                                @RequestHash, @RowVersion, @NowUtc);
                        INSERT INTO dbo.FundingPlatform_OutboxMessages
                            (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                             OccurredAtUtc, AvailableAtUtc)
                        SELECT @EventId, N'FundingOpportunityChanged', N'FundingOpportunity',
                               CONVERT(NVARCHAR(100), @OpportunityId),
                               (SELECT @EventId AS eventId, @OpportunityId AS fundingOpportunityId,
                                       @FundingOpportunityPublicId AS fundingOpportunityPublicId,
                                       @NextVersion AS contentVersion
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                        SET @Succeeded = 1; SET @Code = N'updated';
                    END;
                END;
            END;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_OppUpdate;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @FundingOpportunityPublicId AS FundingOpportunityPublicId,
           COALESCE(@NextVersion, @CurrentVersion) AS ContentVersion,
           @CurrentStatus AS PublicationStatus, COALESCE(@RowVersion, @CurrentRowVersion) AS RowVersion,
           @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Admin_Get
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FundingOpportunityPublicId UNIQUEIDENTIFIER,
    @OwnerWorkspace BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    IF @OwnerWorkspace IS NULL THROW 51601, N'Invalid workspace scope.', 1;
    DECLARE @WorkspaceActorUserId BIGINT;
    IF @OwnerWorkspace = 1
        EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 2, @FundingOpportunityPublicId, @WorkspaceActorUserId OUTPUT;
    ELSE
    BEGIN
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    END;

    DECLARE @OpportunityId BIGINT;
    SELECT @OpportunityId = Id FROM dbo.FundingPlatform_FundingOpportunities
    WHERE PublicId = @FundingOpportunityPublicId;
    IF @OpportunityId IS NULL THROW 51608, N'Funding opportunity was not found.', 1;

    SELECT opportunities.PublicId AS FundingOpportunityPublicId, opportunities.CoverKey,
           opportunities.Slug, opportunities.Title, opportunities.Description,
           opportunities.OtherCategoryDescription,
           opportunities.Summary, opportunities.SponsorName, opportunities.SponsorUrl,
           opportunities.ApplicationUrl, opportunities.IssuerCountryId,
           opportunities.FundingTypeId, opportunities.Currency,
           opportunities.MinAmount, opportunities.MaxAmount, opportunities.AmountStatus,
           opportunities.OpenDate, opportunities.CloseDate, opportunities.CloseAtUtc,
           opportunities.DeadlineTimeZoneId, opportunities.DeadlineType,
           opportunities.DeadlinePrecision, opportunities.EligibilityDescription,
           opportunities.Requirements, opportunities.Objectives,
           opportunities.AllowedActivities, opportunities.ExcludedActivities,
           opportunities.Restrictions, opportunities.TargetOrganizationsDescription,
           opportunities.TargetPopulationsDescription, opportunities.MinimumOperatingYears,
           opportunities.RequiresLegalEntity, opportunities.RequiresPriorExperience,
           opportunities.RequiresCofunding, opportunities.CofundingPercentage,
           opportunities.GeographicScope, opportunities.RemoteApplication,
           opportunities.PublicationStatus, opportunities.SubmittedAtUtc,
           opportunities.PublishedAtUtc, opportunities.ReviewedAtUtc,
           reviewers.PublicId AS ReviewedByUserPublicId, opportunities.RejectionReason,
           opportunities.LastVerifiedAtUtc, opportunities.DataQualityScore,
           opportunities.ContentVersion, opportunities.IsActive,
           opportunities.CreatedAtUtc, opportunities.UpdatedAtUtc, opportunities.RowVersion
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    LEFT JOIN dbo.FundingPlatform_Users AS reviewers ON reviewers.Id = opportunities.ReviewedByUserId
    WHERE opportunities.Id = @OpportunityId;

    SELECT links.CountryId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityCountries AS links
    INNER JOIN dbo.FundingPlatform_Countries AS countries
        ON countries.Id = links.CountryId AND countries.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.CountryId;
    SELECT links.RegionId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityRegions AS links
    INNER JOIN dbo.FundingPlatform_Regions AS regions
        ON regions.Id = links.RegionId AND regions.IsActive = 1
    INNER JOIN dbo.FundingPlatform_Countries AS countries
        ON countries.Id = regions.CountryId AND countries.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.RegionId;
    SELECT links.FundingCategoryId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityCategories AS links
    INNER JOIN dbo.FundingPlatform_FundingCategories AS categories
        ON categories.Id = links.FundingCategoryId AND categories.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.FundingCategoryId;
    SELECT links.BeneficiaryTypeId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes AS links
    INNER JOIN dbo.FundingPlatform_BeneficiaryTypes AS beneficiaryTypes
        ON beneficiaryTypes.Id = links.BeneficiaryTypeId AND beneficiaryTypes.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.BeneficiaryTypeId;
    SELECT links.ProjectTypeId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityProjectTypes AS links
    INNER JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
        ON projectTypes.Id = links.ProjectTypeId AND projectTypes.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.ProjectTypeId;

    SELECT funders.PublicId AS FunderPublicId, funders.Slug, funders.Name, links.Role
    FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
    INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
    WHERE links.FundingOpportunityId = @OpportunityId AND links.IsActive = 1
    ORDER BY links.Role, funders.Name, funders.Id;

    SELECT evidence.PublicId AS EvidencePublicId, evidence.FieldPath, evidence.ValueJson,
           evidence.ExtractionMethod, evidence.EvidenceText, evidence.SourceLocator,
           evidence.Confidence, evidence.IsSelected, evidence.IsManualLock,
           creators.PublicId AS CreatedByUserPublicId, evidence.CreatedAtUtc
    FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
    LEFT JOIN dbo.FundingPlatform_Users AS creators ON creators.Id = evidence.CreatedByUserId
    WHERE evidence.FundingOpportunityId = @OpportunityId
    ORDER BY evidence.FieldPath, evidence.IsSelected DESC, evidence.CreatedAtUtc DESC, evidence.Id DESC;

    SELECT links.FundingSourceId, sources.Name AS SourceName, links.ExternalId,
           links.SourceUrl, links.FirstSeenAtUtc, links.LastSeenAtUtc,
           links.IsPrimary, links.IsActive
    FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
    INNER JOIN dbo.FundingPlatform_FundingSources AS sources ON sources.Id = links.FundingSourceId
    WHERE links.FundingOpportunityId = @OpportunityId
    ORDER BY links.IsActive DESC, links.IsPrimary DESC, links.Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Public_GetBySlug
    @Slug NVARCHAR(320)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @OpportunityId BIGINT;
    SELECT @OpportunityId = opportunities.Id
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    WHERE opportunities.Slug = @Slug AND opportunities.PublicationStatus = 2
      AND opportunities.IsActive = 1
      AND EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs() AS catalogs
           WHERE catalogs.FundingOpportunityId = opportunities.Id)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCategories AS categories
           WHERE categories.FundingOpportunityId = opportunities.Id)
      AND
          ((opportunities.GeographicScope = 1 AND EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS countries
               WHERE countries.FundingOpportunityId = opportunities.Id))
           OR (opportunities.GeographicScope = 2
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS countries
                    WHERE countries.FundingOpportunityId = opportunities.Id)
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions AS regions
                    WHERE regions.FundingOpportunityId = opportunities.Id)))
      AND NOT EXISTS
          (SELECT required.FieldPath
           FROM (VALUES (N'/title'), (N'/description'),
                        (N'/eligibilityDescription'), (N'/closeDate')) AS required(FieldPath)
           WHERE NOT EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
              WHERE evidence.FundingOpportunityId = opportunities.Id
                AND evidence.FieldPath = required.FieldPath AND evidence.IsSelected = 1
                AND JSON_VALUE(evidence.ValueJson, '$.status') IN (N'known', N'unknown')))
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
           INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
           WHERE links.FundingOpportunityId = opportunities.Id AND links.Role = 1
             AND links.IsActive = 1 AND funders.PublicationStatus = 2 AND funders.IsActive = 1)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
           INNER JOIN dbo.FundingPlatform_FundingSources AS sources ON sources.Id = links.FundingSourceId
           WHERE links.FundingOpportunityId = opportunities.Id AND links.IsPrimary = 1
             AND links.IsActive = 1 AND sources.IsEnabled = 1
             AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL);

    SELECT opportunities.PublicId AS FundingOpportunityPublicId, opportunities.CoverKey,
           opportunities.Slug, opportunities.Title, opportunities.Description,
           opportunities.OtherCategoryDescription,
           opportunities.Summary, opportunities.SponsorName, opportunities.SponsorUrl,
           opportunities.ApplicationUrl, opportunities.IssuerCountryId,
           opportunities.FundingTypeId, opportunities.Currency,
           opportunities.MinAmount, opportunities.MaxAmount, opportunities.AmountStatus,
           opportunities.OpenDate, opportunities.CloseDate, opportunities.CloseAtUtc,
           opportunities.DeadlineTimeZoneId, opportunities.DeadlineType,
           opportunities.DeadlinePrecision, opportunities.EligibilityDescription,
           opportunities.Requirements, opportunities.Objectives,
           opportunities.AllowedActivities, opportunities.ExcludedActivities,
           opportunities.Restrictions, opportunities.TargetOrganizationsDescription,
           opportunities.TargetPopulationsDescription, opportunities.MinimumOperatingYears,
           opportunities.RequiresLegalEntity, opportunities.RequiresPriorExperience,
           opportunities.RequiresCofunding, opportunities.CofundingPercentage,
           opportunities.GeographicScope, opportunities.RemoteApplication,
           opportunities.LastVerifiedAtUtc, opportunities.DataQualityScore,
           opportunities.ContentVersion, opportunities.PublishedAtUtc,
           primaryFunder.FunderPublicId AS PrimaryFunderPublicId,
           primaryFunder.FunderSlug AS PrimaryFunderSlug,
           primaryFunder.FunderName AS PrimaryFunderName,
           primarySource.SourceName, primarySource.SourceUrl
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    CROSS APPLY
    (
        SELECT funders.PublicId AS FunderPublicId, funders.Slug AS FunderSlug,
               funders.Name AS FunderName
        FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
        INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
        WHERE links.FundingOpportunityId = opportunities.Id AND links.Role = 1
          AND links.IsActive = 1 AND funders.PublicationStatus = 2 AND funders.IsActive = 1
    ) AS primaryFunder
    CROSS APPLY
    (
        SELECT sources.Name AS SourceName, links.SourceUrl
        FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
        INNER JOIN dbo.FundingPlatform_FundingSources AS sources ON sources.Id = links.FundingSourceId
        WHERE links.FundingOpportunityId = opportunities.Id AND links.IsPrimary = 1
          AND links.IsActive = 1 AND sources.IsEnabled = 1
          AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL
    ) AS primarySource
    WHERE opportunities.Id = @OpportunityId;

    SELECT links.CountryId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityCountries AS links
    INNER JOIN dbo.FundingPlatform_Countries AS countries
        ON countries.Id = links.CountryId AND countries.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.CountryId;
    SELECT links.RegionId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityRegions AS links
    INNER JOIN dbo.FundingPlatform_Regions AS regions
        ON regions.Id = links.RegionId AND regions.IsActive = 1
    INNER JOIN dbo.FundingPlatform_Countries AS countries
        ON countries.Id = regions.CountryId AND countries.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.RegionId;
    SELECT links.FundingCategoryId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityCategories AS links
    INNER JOIN dbo.FundingPlatform_FundingCategories AS categories
        ON categories.Id = links.FundingCategoryId AND categories.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.FundingCategoryId;
    SELECT links.BeneficiaryTypeId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes AS links
    INNER JOIN dbo.FundingPlatform_BeneficiaryTypes AS beneficiaryTypes
        ON beneficiaryTypes.Id = links.BeneficiaryTypeId AND beneficiaryTypes.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.BeneficiaryTypeId;
    SELECT links.ProjectTypeId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityProjectTypes AS links
    INNER JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
        ON projectTypes.Id = links.ProjectTypeId AND projectTypes.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.ProjectTypeId;
    SELECT funders.PublicId AS FunderPublicId, funders.Slug, funders.Name, links.Role
    FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
    INNER JOIN dbo.FundingPlatform_Funders AS funders
        ON funders.Id = links.FunderId AND funders.PublicationStatus = 2 AND funders.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId AND links.IsActive = 1
    ORDER BY links.Role, funders.Name, funders.Id;
    SELECT links.FundingSourceId, sources.Name AS SourceName, links.ExternalId,
           links.SourceUrl, links.FirstSeenAtUtc, links.LastSeenAtUtc,
           links.IsPrimary, links.IsActive
    FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
    INNER JOIN dbo.FundingPlatform_FundingSources AS sources
        ON sources.Id = links.FundingSourceId AND sources.IsEnabled = 1
    WHERE links.FundingOpportunityId = @OpportunityId AND links.IsActive = 1
    ORDER BY links.IsPrimary DESC, links.Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_OrganizationGet
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @FundingOpportunityPublicId UNIQUEIDENTIFIER = NULL,
    @Slug NVARCHAR(320) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @OpportunityId BIGINT;
    DECLARE @NormalizedSlug NVARCHAR(320) = NULLIF(LTRIM(RTRIM(@Slug)), N'');
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id
       AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId
      AND organizations.IsActive = 1
      AND users.PublicId = @UserPublicId;

    IF @OrganizationId IS NULL OR @UserId IS NULL
        THROW 52001, N'The workspace resource was not found.', 1;
    IF (@FundingOpportunityPublicId IS NULL AND @NormalizedSlug IS NULL)
       OR (@FundingOpportunityPublicId IS NOT NULL AND @NormalizedSlug IS NOT NULL)
        THROW 52002, N'Exactly one opportunity identifier is required.', 1;

    SELECT @OpportunityId = opportunities.Id
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
        ON ready.FundingOpportunityId = opportunities.Id
    WHERE (@FundingOpportunityPublicId IS NOT NULL
           AND opportunities.PublicId = @FundingOpportunityPublicId)
       OR (@NormalizedSlug IS NOT NULL AND opportunities.Slug = @NormalizedSlug);

    IF @OpportunityId IS NULL
        THROW 52001, N'The workspace resource was not found.', 1;

    SELECT opportunities.PublicId AS FundingOpportunityPublicId, opportunities.CoverKey,
           opportunities.Slug, opportunities.Title, opportunities.Description,
           opportunities.OtherCategoryDescription,
           opportunities.Summary, opportunities.SponsorName, opportunities.SponsorUrl,
           opportunities.ApplicationUrl, opportunities.IssuerCountryId,
           opportunities.FundingTypeId, opportunities.Currency,
           opportunities.MinAmount, opportunities.MaxAmount, opportunities.AmountStatus,
           opportunities.OpenDate, opportunities.CloseDate, opportunities.CloseAtUtc,
           opportunities.DeadlineTimeZoneId, opportunities.DeadlineType,
           opportunities.DeadlinePrecision, opportunities.EligibilityDescription,
           opportunities.Requirements, opportunities.Objectives,
           opportunities.AllowedActivities, opportunities.ExcludedActivities,
           opportunities.Restrictions, opportunities.TargetOrganizationsDescription,
           opportunities.TargetPopulationsDescription, opportunities.MinimumOperatingYears,
           opportunities.RequiresLegalEntity, opportunities.RequiresPriorExperience,
           opportunities.RequiresCofunding, opportunities.CofundingPercentage,
           opportunities.GeographicScope, opportunities.RemoteApplication,
           opportunities.LastVerifiedAtUtc, opportunities.DataQualityScore,
           opportunities.ContentVersion, opportunities.PublishedAtUtc,
           CONVERT(BIT, CASE WHEN favorites.FundingOpportunityId IS NULL THEN 0 ELSE 1 END)
               AS IsFavorite,
           primaryFunder.FunderPublicId AS PrimaryFunderPublicId,
           primaryFunder.FunderSlug AS PrimaryFunderSlug,
           primaryFunder.FunderName AS PrimaryFunderName, primarySource.SourceName,
           primarySource.SourceUrl, primarySource.ExternalId
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    CROSS APPLY
    (
        SELECT funders.PublicId AS FunderPublicId, funders.Slug AS FunderSlug,
               funders.Name AS FunderName
        FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
        INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
        WHERE links.FundingOpportunityId = opportunities.Id
          AND links.Role = 1 AND links.IsActive = 1
          AND funders.PublicationStatus = 2 AND funders.IsActive = 1
    ) AS primaryFunder
    CROSS APPLY
    (
        SELECT sources.Name AS SourceName, links.SourceUrl, links.ExternalId
        FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
        INNER JOIN dbo.FundingPlatform_FundingSources AS sources
            ON sources.Id = links.FundingSourceId
        WHERE links.FundingOpportunityId = opportunities.Id
          AND links.IsPrimary = 1 AND links.IsActive = 1
          AND sources.IsEnabled = 1
          AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL
    ) AS primarySource
    LEFT JOIN dbo.FundingPlatform_UserFundingFavorites AS favorites
        ON favorites.OrganizationId = @OrganizationId
       AND favorites.UserId = @UserId
       AND favorites.FundingOpportunityId = opportunities.Id
    WHERE opportunities.Id = @OpportunityId;

    SELECT links.CountryId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityCountries AS links
    INNER JOIN dbo.FundingPlatform_Countries AS catalogs
        ON catalogs.Id = links.CountryId AND catalogs.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.CountryId;

    SELECT links.RegionId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityRegions AS links
    INNER JOIN dbo.FundingPlatform_Regions AS catalogs
        ON catalogs.Id = links.RegionId AND catalogs.IsActive = 1
    INNER JOIN dbo.FundingPlatform_Countries AS countries
        ON countries.Id = catalogs.CountryId AND countries.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.RegionId;

    SELECT links.FundingCategoryId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityCategories AS links
    INNER JOIN dbo.FundingPlatform_FundingCategories AS catalogs
        ON catalogs.Id = links.FundingCategoryId AND catalogs.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.FundingCategoryId;

    SELECT links.BeneficiaryTypeId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes AS links
    INNER JOIN dbo.FundingPlatform_BeneficiaryTypes AS catalogs
        ON catalogs.Id = links.BeneficiaryTypeId AND catalogs.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.BeneficiaryTypeId;

    SELECT links.ProjectTypeId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityProjectTypes AS links
    INNER JOIN dbo.FundingPlatform_ProjectTypes AS catalogs
        ON catalogs.Id = links.ProjectTypeId AND catalogs.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.ProjectTypeId;

    SELECT links.TagId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityTags AS links
    INNER JOIN dbo.FundingPlatform_Tags AS catalogs
        ON catalogs.Id = links.TagId
       AND catalogs.IsActive = 1 AND catalogs.IsApproved = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.TagId;

    SELECT links.OrganizationTypeId AS Id, links.EligibilityMode
    FROM dbo.FundingPlatform_FundingOpportunityOrganizationTypes AS links
    INNER JOIN dbo.FundingPlatform_OrganizationTypes AS catalogs
        ON catalogs.Id = links.OrganizationTypeId AND catalogs.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId
    ORDER BY links.EligibilityMode, links.OrganizationTypeId;

    SELECT links.LegalEntityTypeId AS Id, links.EligibilityMode
    FROM dbo.FundingPlatform_FundingOpportunityLegalEntityTypes AS links
    INNER JOIN dbo.FundingPlatform_LegalEntityTypes AS catalogs
        ON catalogs.Id = links.LegalEntityTypeId AND catalogs.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId
    ORDER BY links.EligibilityMode, links.LegalEntityTypeId;

    SELECT links.LanguageId AS Id, links.LanguagePurpose
    FROM dbo.FundingPlatform_FundingOpportunityLanguages AS links
    INNER JOIN dbo.FundingPlatform_Languages AS catalogs
        ON catalogs.Id = links.LanguageId AND catalogs.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId
    ORDER BY links.LanguagePurpose, links.LanguageId;

    SELECT funders.PublicId AS FunderPublicId, funders.Slug, funders.Name, links.Role
    FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
    INNER JOIN dbo.FundingPlatform_Funders AS funders
        ON funders.Id = links.FunderId
       AND funders.PublicationStatus = 2 AND funders.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId AND links.IsActive = 1
    ORDER BY links.Role, funders.Name, funders.Id;

    SELECT links.FundingSourceId, sources.Name AS SourceName, links.ExternalId,
           links.SourceUrl, links.FirstSeenAtUtc, links.LastSeenAtUtc,
           links.IsPrimary, links.IsActive
    FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
    INNER JOIN dbo.FundingPlatform_FundingSources AS sources
        ON sources.Id = links.FundingSourceId AND sources.IsEnabled = 1
    WHERE links.FundingOpportunityId = @OpportunityId AND links.IsActive = 1
    ORDER BY links.IsPrimary DESC, links.Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Public_List
    @Query NVARCHAR(300) = NULL,
    @PageNumber INT = 1,
    @PageSize INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    IF @PageNumber < 1 THROW 51603, N'PageNumber must be at least 1.', 1;
    IF @PageSize < 1 OR @PageSize > 100
        THROW 51604, N'PageSize must be between 1 and 100.', 1;
    DECLARE @QueryLike NVARCHAR(302) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Query)), N'') IS NULL THEN NULL
             ELSE N'%' + LTRIM(RTRIM(@Query)) + N'%' END;

    SELECT COUNT_BIG(1) AS TotalCount
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    WHERE opportunities.PublicationStatus = 2 AND opportunities.IsActive = 1
      AND EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs() AS catalogs
           WHERE catalogs.FundingOpportunityId = opportunities.Id)
      AND (@QueryLike IS NULL OR opportunities.Title LIKE @QueryLike
           OR opportunities.SponsorName LIKE @QueryLike OR opportunities.Summary LIKE @QueryLike)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCategories AS categories
           WHERE categories.FundingOpportunityId = opportunities.Id)
      AND
          ((opportunities.GeographicScope = 1 AND EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS countries
               WHERE countries.FundingOpportunityId = opportunities.Id))
           OR (opportunities.GeographicScope = 2
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS countries
                    WHERE countries.FundingOpportunityId = opportunities.Id)
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions AS regions
                    WHERE regions.FundingOpportunityId = opportunities.Id)))
      AND NOT EXISTS
          (SELECT required.FieldPath
           FROM (VALUES (N'/title'), (N'/description'),
                        (N'/eligibilityDescription'), (N'/closeDate')) AS required(FieldPath)
           WHERE NOT EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
              WHERE evidence.FundingOpportunityId = opportunities.Id
                AND evidence.FieldPath = required.FieldPath AND evidence.IsSelected = 1
                AND JSON_VALUE(evidence.ValueJson, '$.status') IN (N'known', N'unknown')))
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
           INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
           WHERE links.FundingOpportunityId = opportunities.Id AND links.Role = 1
             AND links.IsActive = 1 AND funders.PublicationStatus = 2 AND funders.IsActive = 1)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
           INNER JOIN dbo.FundingPlatform_FundingSources AS sources ON sources.Id = links.FundingSourceId
           WHERE links.FundingOpportunityId = opportunities.Id AND links.IsPrimary = 1
             AND links.IsActive = 1 AND sources.IsEnabled = 1
             AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL);

    SELECT opportunities.PublicId AS FundingOpportunityPublicId, opportunities.CoverKey,
           opportunities.Slug, opportunities.Title, opportunities.Summary,
           opportunities.SponsorName, opportunities.Currency,
           opportunities.MinAmount, opportunities.MaxAmount,
           opportunities.OpenDate, opportunities.CloseDate,
           opportunities.PublishedAtUtc, opportunities.DataQualityScore,
           primaryFunder.FunderPublicId AS PrimaryFunderPublicId,
           primaryFunder.FunderName AS PrimaryFunderName,
           primarySource.SourceName, primarySource.SourceUrl
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    CROSS APPLY
    (
        SELECT funders.PublicId AS FunderPublicId, funders.Name AS FunderName
        FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
        INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
        WHERE links.FundingOpportunityId = opportunities.Id AND links.Role = 1
          AND links.IsActive = 1 AND funders.PublicationStatus = 2 AND funders.IsActive = 1
    ) AS primaryFunder
    CROSS APPLY
    (
        SELECT sources.Name AS SourceName, links.SourceUrl
        FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
        INNER JOIN dbo.FundingPlatform_FundingSources AS sources ON sources.Id = links.FundingSourceId
        WHERE links.FundingOpportunityId = opportunities.Id AND links.IsPrimary = 1
          AND links.IsActive = 1 AND sources.IsEnabled = 1
          AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL
    ) AS primarySource
    WHERE opportunities.PublicationStatus = 2 AND opportunities.IsActive = 1
      AND EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs() AS catalogs
           WHERE catalogs.FundingOpportunityId = opportunities.Id)
      AND (@QueryLike IS NULL OR opportunities.Title LIKE @QueryLike
           OR opportunities.SponsorName LIKE @QueryLike OR opportunities.Summary LIKE @QueryLike)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCategories AS categories
           WHERE categories.FundingOpportunityId = opportunities.Id)
      AND
          ((opportunities.GeographicScope = 1 AND EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS countries
               WHERE countries.FundingOpportunityId = opportunities.Id))
           OR (opportunities.GeographicScope = 2
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS countries
                    WHERE countries.FundingOpportunityId = opportunities.Id)
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions AS regions
                    WHERE regions.FundingOpportunityId = opportunities.Id)))
      AND NOT EXISTS
          (SELECT required.FieldPath
           FROM (VALUES (N'/title'), (N'/description'),
                        (N'/eligibilityDescription'), (N'/closeDate')) AS required(FieldPath)
           WHERE NOT EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
              WHERE evidence.FundingOpportunityId = opportunities.Id
                AND evidence.FieldPath = required.FieldPath AND evidence.IsSelected = 1
                AND JSON_VALUE(evidence.ValueJson, '$.status') IN (N'known', N'unknown')))
    ORDER BY CASE WHEN opportunities.CloseDate IS NULL THEN 1 ELSE 0 END,
             opportunities.CloseDate, opportunities.Id DESC
    OFFSET ((@PageNumber - 1) * @PageSize) ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @Query NVARCHAR(300) = NULL,
    @Sponsor NVARCHAR(300) = NULL,
    @Currency CHAR(3) = NULL,
    @MinAmount DECIMAL(19,4) = NULL,
    @MaxAmount DECIMAL(19,4) = NULL,
    @ClosingFrom DATE = NULL,
    @ClosingTo DATE = NULL,
    @OnlyOpen BIT = 0,
    @Sort NVARCHAR(30) = N'closing-soon',
    @PageNumber INT = 1,
    @PageSize INT = 20,
    @CountryIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @RegionIds dbo.FundingPlatform_IntIdList READONLY,
    @CategoryIds dbo.FundingPlatform_IntIdList READONLY,
    @TagIds dbo.FundingPlatform_BigIntIdList READONLY,
    @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @FundingTypeIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @FunderPublicIds dbo.FundingPlatform_GuidIdList READONLY,
    @OrganizationTypeIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @MatchedCount BIGINT = NULL OUTPUT,
    @EffectiveSearchMode NVARCHAR(20) = NULL OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OrganizationId BIGINT, @UserId BIGINT;
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id
       AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId
      AND organizations.IsActive = 1
      AND users.PublicId = @UserPublicId;

    IF @OrganizationId IS NULL OR @UserId IS NULL
        THROW 52001, N'The workspace resource was not found.', 1;

    DECLARE @NormalizedQuery NVARCHAR(300) = NULLIF(LTRIM(RTRIM(@Query)), N'');
    DECLARE @NormalizedSponsor NVARCHAR(300) = NULLIF(LTRIM(RTRIM(@Sponsor)), N'');
    DECLARE @NormalizedCurrency CHAR(3) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Currency)), '') IS NULL THEN NULL
             ELSE UPPER(LTRIM(RTRIM(@Currency))) END;
    DECLARE @NormalizedSort NVARCHAR(30) = LOWER(LTRIM(RTRIM(COALESCE(@Sort, N''))));
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @TodayUtc DATE = CONVERT(DATE, @NowUtc);
    DECLARE @Offset BIGINT;

    IF @PageNumber < 1 OR @PageNumber > 10000 OR @PageSize < 1 OR @PageSize > 50
       OR @OnlyOpen IS NULL
       OR @NormalizedSort NOT IN
          (N'relevance', N'closing-soon', N'newest', N'amount-asc', N'amount-desc')
       OR (@NormalizedSort = N'relevance' AND @NormalizedQuery IS NULL)
       OR @MinAmount < 0 OR @MaxAmount < 0
       OR (@MinAmount IS NOT NULL AND @MaxAmount IS NOT NULL AND @MinAmount > @MaxAmount)
       OR (@ClosingFrom IS NOT NULL AND @ClosingTo IS NOT NULL
           AND @ClosingFrom > @ClosingTo)
       OR ((@MinAmount IS NOT NULL OR @MaxAmount IS NOT NULL
            OR @NormalizedSort IN (N'amount-asc', N'amount-desc'))
           AND @NormalizedCurrency IS NULL)
       OR (@NormalizedCurrency IS NOT NULL AND
           (LEN(@NormalizedCurrency) <> 3 OR @NormalizedCurrency LIKE '%[^A-Z]%'))
        THROW 52002, N'The search filters are invalid.', 1;

    /* Catalog IDs can become stale between rendering and submitting a filter.
       Unknown/inactive values simply do not match; a mixed list still keeps
       its valid OR alternatives and never turns a normal race into a 500. */

    SET @Offset = (CONVERT(BIGINT, @PageNumber) - 1) * CONVERT(BIGINT, @PageSize);

    DECLARE @QueryPattern NVARCHAR(610) = NULL;
    DECLARE @SponsorPattern NVARCHAR(610) = NULL;
    IF @NormalizedQuery IS NOT NULL
        SET @QueryPattern = N'%' +
            REPLACE(REPLACE(REPLACE(REPLACE(@NormalizedQuery,
                N'~', N'~~'), N'%', N'~%'), N'_', N'~_'), N'[', N'~[') + N'%';
    IF @NormalizedSponsor IS NOT NULL
        SET @SponsorPattern = N'%' +
            REPLACE(REPLACE(REPLACE(REPLACE(@NormalizedSponsor,
                N'~', N'~~'), N'%', N'~%'), N'_', N'~_'), N'[', N'~[') + N'%';

    CREATE TABLE #TextRanks
    (
        FundingOpportunityId BIGINT NOT NULL PRIMARY KEY,
        TextRank INT NOT NULL
    );

    CREATE TABLE #LiteralRanks
    (
        FundingOpportunityId BIGINT NOT NULL PRIMARY KEY,
        TextRank INT NOT NULL
    );

    IF @NormalizedQuery IS NOT NULL
        INSERT INTO #LiteralRanks (FundingOpportunityId, TextRank)
        SELECT opportunities.Id,
               CASE
                   WHEN opportunities.Title = @NormalizedQuery THEN 1000
                   WHEN opportunities.Title LIKE @QueryPattern ESCAPE N'~' THEN 800
                   WHEN opportunities.SponsorName LIKE @QueryPattern ESCAPE N'~' THEN 600
                   WHEN opportunities.Summary LIKE @QueryPattern ESCAPE N'~' THEN 400
                   WHEN opportunities.Description LIKE @QueryPattern ESCAPE N'~' THEN 300
                   WHEN opportunities.EligibilityDescription LIKE @QueryPattern ESCAPE N'~' THEN 200
                   ELSE 100
               END
        FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
        WHERE opportunities.Title LIKE @QueryPattern ESCAPE N'~'
           OR opportunities.SponsorName LIKE @QueryPattern ESCAPE N'~'
           OR opportunities.Summary LIKE @QueryPattern ESCAPE N'~'
           OR opportunities.Description LIKE @QueryPattern ESCAPE N'~'
           OR opportunities.EligibilityDescription LIKE @QueryPattern ESCAPE N'~'
           OR opportunities.Requirements LIKE @QueryPattern ESCAPE N'~';

    DECLARE @SearchMode NVARCHAR(20) = N'filtered';
    DECLARE @FullTextReady BIT = 0;
    DECLARE @FullTextObjectId INT =
        OBJECT_ID(N'dbo.FundingPlatform_FundingOpportunities');
    DECLARE @FullTextCatalogId INT =
        (SELECT fulltext_catalog_id FROM sys.fulltext_catalogs
         WHERE name = N'FundingPlatform_FundingSearchCatalog'
           AND is_accent_sensitivity_on = 0
           AND principal_id = DATABASE_PRINCIPAL_ID(N'dbo'));
    DECLARE @FullTextKeyIndexId INT =
        (SELECT index_id FROM sys.indexes
         WHERE object_id = @FullTextObjectId
           AND name = N'FundingPlatform_PK_FundingOpportunities');
    IF @NormalizedQuery IS NOT NULL
       AND COALESCE(FULLTEXTSERVICEPROPERTY('IsFullTextInstalled'), 0) = 1
       AND EXISTS
       (
           SELECT 1
           FROM sys.fulltext_indexes AS indexes
           WHERE indexes.object_id = @FullTextObjectId
             AND indexes.fulltext_catalog_id = @FullTextCatalogId
             AND indexes.unique_index_id = @FullTextKeyIndexId
             AND indexes.is_enabled = 1
             AND indexes.change_tracking_state_desc = N'AUTO'
             AND indexes.stoplist_id = 0
             AND indexes.property_list_id IS NULL
             AND indexes.has_crawl_completed = 1
       )
       AND NOT EXISTS
           (SELECT 1 FROM sys.fulltext_indexes AS indexes
            WHERE indexes.fulltext_catalog_id = @FullTextCatalogId
              AND indexes.object_id <> @FullTextObjectId)
       AND (SELECT COUNT_BIG(1)
            FROM sys.fulltext_index_columns AS indexedColumns
            INNER JOIN sys.columns AS columns
                ON columns.object_id = indexedColumns.object_id
               AND columns.column_id = indexedColumns.column_id
            WHERE indexedColumns.object_id = @FullTextObjectId
              AND columns.name IN
                  (N'Title', N'Description', N'Summary', N'SponsorName',
                   N'EligibilityDescription', N'Requirements')
              AND indexedColumns.language_id = 0
              AND indexedColumns.statistical_semantics = 0) = 6
       AND NOT EXISTS
           (SELECT 1
            FROM sys.fulltext_index_columns AS indexedColumns
            INNER JOIN sys.columns AS columns
                ON columns.object_id = indexedColumns.object_id
               AND columns.column_id = indexedColumns.column_id
            WHERE indexedColumns.object_id = @FullTextObjectId
              AND (columns.name NOT IN
                   (N'Title', N'Description', N'Summary', N'SponsorName',
                    N'EligibilityDescription', N'Requirements')
                   OR indexedColumns.language_id <> 0
                   OR indexedColumns.statistical_semantics <> 0))
       AND FULLTEXTCATALOGPROPERTY
           (N'FundingPlatform_FundingSearchCatalog', 'PopulateStatus') = 0
       AND OBJECTPROPERTYEX(@FullTextObjectId, 'TableFullTextPopulateStatus') = 0
       AND OBJECTPROPERTYEX(@FullTextObjectId, 'TableFulltextFailCount') = 0
        SET @FullTextReady = 1;

    IF @NormalizedQuery IS NOT NULL AND @FullTextReady = 1
    BEGIN
        BEGIN TRY
            EXEC sys.sp_executesql
                N'INSERT INTO #TextRanks (FundingOpportunityId, TextRank)
                  SELECT results.[KEY], results.[RANK]
                  FROM FREETEXTTABLE
                  (
                      dbo.FundingPlatform_FundingOpportunities,
                      (Title, Description, Summary, SponsorName,
                       EligibilityDescription, Requirements),
                      @SearchQuery
                  ) AS results;',
                N'@SearchQuery NVARCHAR(300)',
                @SearchQuery = @NormalizedQuery;
            SET @SearchMode = N'full-text';

            /* AUTO change tracking is asynchronous. Preserve zero literal
               omissions and deterministic exact-match relevance for commits
               that have not reached the index yet. */
            UPDATE ranked
            SET ranked.TextRank = CASE
                                      WHEN literal.TextRank > ranked.TextRank
                                      THEN literal.TextRank
                                      ELSE ranked.TextRank
                                  END
            FROM #TextRanks AS ranked
            INNER JOIN #LiteralRanks AS literal
                ON literal.FundingOpportunityId = ranked.FundingOpportunityId;

            INSERT INTO #TextRanks (FundingOpportunityId, TextRank)
            SELECT literal.FundingOpportunityId, literal.TextRank
            FROM #LiteralRanks AS literal
            WHERE NOT EXISTS
                (SELECT 1 FROM #TextRanks AS ranked
                 WHERE ranked.FundingOpportunityId = literal.FundingOpportunityId);
        END TRY
        BEGIN CATCH
            DELETE FROM #TextRanks;
            SET @FullTextReady = 0;
        END CATCH;
    END;

    IF @NormalizedQuery IS NOT NULL AND @FullTextReady = 0
    BEGIN
        INSERT INTO #TextRanks (FundingOpportunityId, TextRank)
        SELECT FundingOpportunityId, TextRank FROM #LiteralRanks;
        SET @SearchMode = N'literal-fallback';
    END;

    CREATE TABLE #Matches
    (
        FundingOpportunityId BIGINT NOT NULL PRIMARY KEY,
        TextRank INT NOT NULL
    );

    INSERT INTO #Matches (FundingOpportunityId, TextRank)
    SELECT opportunities.Id, COALESCE(textRanks.TextRank, 0)
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
        ON ready.FundingOpportunityId = opportunities.Id
    LEFT JOIN #TextRanks AS textRanks
        ON textRanks.FundingOpportunityId = opportunities.Id
    WHERE (@NormalizedQuery IS NULL OR textRanks.FundingOpportunityId IS NOT NULL)
      AND (@NormalizedSponsor IS NULL
           OR opportunities.SponsorName LIKE @SponsorPattern ESCAPE N'~')
      AND (@NormalizedCurrency IS NULL OR opportunities.Currency = @NormalizedCurrency)
      AND (@MinAmount IS NULL OR
           (opportunities.AmountStatus = 1
            AND COALESCE(opportunities.MaxAmount, opportunities.MinAmount) >= @MinAmount))
      AND (@MaxAmount IS NULL OR
           (opportunities.AmountStatus = 1
            AND COALESCE(opportunities.MinAmount, opportunities.MaxAmount) <= @MaxAmount))
      AND (@ClosingFrom IS NULL OR opportunities.CloseDate >= @ClosingFrom)
      AND (@ClosingTo IS NULL OR opportunities.CloseDate <= @ClosingTo)
      AND (@OnlyOpen = 0 OR
           ((opportunities.OpenDate IS NULL OR opportunities.OpenDate <= @TodayUtc)
            AND (opportunities.DeadlineType = 2
                 OR (opportunities.DeadlineType = 1
                     AND ((opportunities.CloseAtUtc IS NOT NULL
                           AND opportunities.CloseAtUtc > @NowUtc)
                          OR (opportunities.CloseAtUtc IS NULL
                              AND opportunities.CloseDate >= @TodayUtc))))))
      AND (NOT EXISTS (SELECT 1 FROM @CountryIds)
           OR opportunities.GeographicScope = 2 OR EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS links
            INNER JOIN @CountryIds AS ids ON ids.Id = links.CountryId
            WHERE links.FundingOpportunityId = opportunities.Id))
      AND (NOT EXISTS (SELECT 1 FROM @RegionIds)
           OR opportunities.GeographicScope = 2 OR EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions AS links
            INNER JOIN @RegionIds AS ids ON ids.Id = links.RegionId
            WHERE links.FundingOpportunityId = opportunities.Id))
      AND (NOT EXISTS (SELECT 1 FROM @CategoryIds) OR EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCategories AS links
            INNER JOIN @CategoryIds AS ids ON ids.Id = links.FundingCategoryId
            WHERE links.FundingOpportunityId = opportunities.Id))
      AND (NOT EXISTS (SELECT 1 FROM @TagIds) OR EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityTags AS links
            INNER JOIN @TagIds AS ids ON ids.Id = links.TagId
            WHERE links.FundingOpportunityId = opportunities.Id))
      AND (NOT EXISTS (SELECT 1 FROM @BeneficiaryTypeIds) OR EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes AS links
            INNER JOIN @BeneficiaryTypeIds AS ids ON ids.Id = links.BeneficiaryTypeId
            WHERE links.FundingOpportunityId = opportunities.Id))
      AND (NOT EXISTS (SELECT 1 FROM @ProjectTypeIds) OR EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityProjectTypes AS links
            INNER JOIN @ProjectTypeIds AS ids ON ids.Id = links.ProjectTypeId
            WHERE links.FundingOpportunityId = opportunities.Id))
      AND (NOT EXISTS (SELECT 1 FROM @FundingTypeIds)
           OR opportunities.FundingTypeId IN (SELECT Id FROM @FundingTypeIds))
      AND (NOT EXISTS (SELECT 1 FROM @FunderPublicIds) OR EXISTS
           (SELECT 1
            FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
            INNER JOIN dbo.FundingPlatform_Funders AS funders
                ON funders.Id = links.FunderId
               AND funders.PublicationStatus = 2 AND funders.IsActive = 1
            INNER JOIN @FunderPublicIds AS ids ON ids.Id = funders.PublicId
            WHERE links.FundingOpportunityId = opportunities.Id
              AND links.IsActive = 1))
      AND (NOT EXISTS (SELECT 1 FROM @OrganizationTypeIds) OR EXISTS
           (SELECT 1
            FROM dbo.FundingPlatform_FundingOpportunityOrganizationTypes AS links
            INNER JOIN @OrganizationTypeIds AS ids
                ON ids.Id = links.OrganizationTypeId
            WHERE links.FundingOpportunityId = opportunities.Id
              AND links.EligibilityMode = 1));

    SELECT @MatchedCount = COUNT_BIG(1) FROM #Matches;
    SET @EffectiveSearchMode = @SearchMode;
    SELECT @MatchedCount AS TotalCount, @SearchMode AS SearchMode;

    SELECT opportunities.PublicId AS FundingOpportunityPublicId, opportunities.CoverKey,
           opportunities.Slug, opportunities.Title, opportunities.Summary,
           opportunities.SponsorName, opportunities.Currency,
           opportunities.MinAmount, opportunities.MaxAmount,
           opportunities.OpenDate, opportunities.CloseDate, opportunities.CloseAtUtc,
           opportunities.DeadlineType, opportunities.DeadlinePrecision,
           opportunities.PublishedAtUtc, opportunities.DataQualityScore,
           primaryFunder.FunderPublicId AS PrimaryFunderPublicId,
           primaryFunder.FunderName AS PrimaryFunderName,
           primarySource.SourceName, primarySource.SourceUrl,
           CONVERT(BIT, CASE WHEN favorites.FundingOpportunityId IS NULL THEN 0 ELSE 1 END)
               AS IsFavorite
    FROM #Matches AS matches
    INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
        ON opportunities.Id = matches.FundingOpportunityId
    CROSS APPLY
    (
        SELECT funders.PublicId AS FunderPublicId, funders.Name AS FunderName
        FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
        INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
        WHERE links.FundingOpportunityId = opportunities.Id
          AND links.Role = 1 AND links.IsActive = 1
          AND funders.PublicationStatus = 2 AND funders.IsActive = 1
    ) AS primaryFunder
    CROSS APPLY
    (
        SELECT sources.Name AS SourceName, links.SourceUrl
        FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
        INNER JOIN dbo.FundingPlatform_FundingSources AS sources
            ON sources.Id = links.FundingSourceId
        WHERE links.FundingOpportunityId = opportunities.Id
          AND links.IsPrimary = 1 AND links.IsActive = 1
          AND sources.IsEnabled = 1
          AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL
    ) AS primarySource
    LEFT JOIN dbo.FundingPlatform_UserFundingFavorites AS favorites
        ON favorites.OrganizationId = @OrganizationId
       AND favorites.UserId = @UserId
       AND favorites.FundingOpportunityId = opportunities.Id
    ORDER BY
        CASE WHEN @NormalizedSort = N'relevance' THEN matches.TextRank END DESC,
        CASE WHEN @NormalizedSort IN (N'relevance', N'closing-soon')
             AND opportunities.DeadlineType = 2 THEN 1
             WHEN @NormalizedSort IN (N'relevance', N'closing-soon')
             AND opportunities.CloseDate IS NULL THEN 2 ELSE 0 END,
        CASE WHEN @NormalizedSort IN (N'relevance', N'closing-soon')
             THEN COALESCE(opportunities.CloseAtUtc,
                           DATEADD(DAY, 1, CONVERT(DATETIME2(3), opportunities.CloseDate))) END,
        CASE WHEN @NormalizedSort = N'newest' THEN opportunities.PublishedAtUtc END DESC,
        CASE WHEN @NormalizedSort IN (N'amount-asc', N'amount-desc')
                  AND opportunities.MaxAmount IS NULL
             THEN 1 ELSE 0 END,
        CASE WHEN @NormalizedSort = N'amount-asc'
             THEN opportunities.MaxAmount END,
        CASE WHEN @NormalizedSort = N'amount-desc'
             THEN opportunities.MaxAmount END DESC,
        opportunities.Id DESC
    OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Favorite_List
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @PageNumber INT = 1,
    @PageSize INT = 20,
    @MatchedCount BIGINT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT;
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id
       AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId
      AND organizations.IsActive = 1
      AND users.PublicId = @UserPublicId;

    IF @OrganizationId IS NULL OR @UserId IS NULL
        THROW 52001, N'The workspace resource was not found.', 1;
    IF @PageNumber < 1 OR @PageNumber > 10000 OR @PageSize < 1 OR @PageSize > 50
        THROW 52002, N'The favorite page is invalid.', 1;

    DECLARE @Offset BIGINT =
        (CONVERT(BIGINT, @PageNumber) - 1) * CONVERT(BIGINT, @PageSize);

    SELECT @MatchedCount = COUNT_BIG(1)
    FROM dbo.FundingPlatform_UserFundingFavorites AS favorites
    INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
        ON ready.FundingOpportunityId = favorites.FundingOpportunityId
    WHERE favorites.OrganizationId = @OrganizationId AND favorites.UserId = @UserId;
    SELECT @MatchedCount AS TotalCount;

    SELECT opportunities.PublicId AS FundingOpportunityPublicId, opportunities.CoverKey,
           opportunities.Slug, opportunities.Title, opportunities.Summary,
           opportunities.SponsorName, opportunities.Currency,
           opportunities.MinAmount, opportunities.MaxAmount,
           opportunities.OpenDate, opportunities.CloseDate, opportunities.CloseAtUtc,
           opportunities.DeadlineType, opportunities.DeadlinePrecision,
           opportunities.PublishedAtUtc, opportunities.DataQualityScore,
           primaryFunder.FunderPublicId AS PrimaryFunderPublicId,
           primaryFunder.FunderName AS PrimaryFunderName,
           primarySource.SourceName, primarySource.SourceUrl,
           CONVERT(BIT, 1) AS IsFavorite, favorites.CreatedAtUtc AS FavoriteCreatedAtUtc
    FROM dbo.FundingPlatform_UserFundingFavorites AS favorites
    INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
        ON ready.FundingOpportunityId = favorites.FundingOpportunityId
    INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
        ON opportunities.Id = favorites.FundingOpportunityId
    CROSS APPLY
    (
        SELECT funders.PublicId AS FunderPublicId, funders.Name AS FunderName
        FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
        INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
        WHERE links.FundingOpportunityId = opportunities.Id
          AND links.Role = 1 AND links.IsActive = 1
          AND funders.PublicationStatus = 2 AND funders.IsActive = 1
    ) AS primaryFunder
    CROSS APPLY
    (
        SELECT sources.Name AS SourceName, links.SourceUrl
        FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
        INNER JOIN dbo.FundingPlatform_FundingSources AS sources
            ON sources.Id = links.FundingSourceId
        WHERE links.FundingOpportunityId = opportunities.Id
          AND links.IsPrimary = 1 AND links.IsActive = 1
          AND sources.IsEnabled = 1
          AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL
    ) AS primarySource
    WHERE favorites.OrganizationId = @OrganizationId AND favorites.UserId = @UserId
    ORDER BY favorites.CreatedAtUtc DESC, favorites.FundingOpportunityId DESC
    OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO
