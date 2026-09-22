/* Category OTHER remains catalog ID 16. Free text belongs to the opportunity,
   participates in its existing versioned editorial write, and creates no taxonomy rows.
   Derived from the latest definitions in 042, 010 and 018, preserving their authorization. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingCategories WHERE Id = 16 AND Code = N'OTHER')
    THROW 56060, N'Expected stable OTHER category from migration 031.', 1;
IF COL_LENGTH(N'dbo.FundingPlatform_FundingOpportunities', N'OtherCategoryDescription') IS NULL
    ALTER TABLE dbo.FundingPlatform_FundingOpportunities ADD OtherCategoryDescription NVARCHAR(200) NULL;
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
    @OtherCategoryDescription NVARCHAR(MAX) = NULL
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
                    CreatedAtUtc, UpdatedAtUtc, OtherCategoryDescription
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
                    @ContentHash, 1, @ActorUserId, @ActorUserId, @NowUtc, @NowUtc, @OtherCategoryDescription
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
    @OtherCategoryDescription NVARCHAR(MAX) = NULL
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
               @CurrentVersion = ContentVersion, @CurrentRowVersion = RowVersion
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
                    SET OtherCategoryDescription = @OtherCategoryDescription,
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

    SELECT opportunities.PublicId AS FundingOpportunityPublicId,
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

    SELECT opportunities.PublicId AS FundingOpportunityPublicId,
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

    SELECT opportunities.PublicId AS FundingOpportunityPublicId,
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
