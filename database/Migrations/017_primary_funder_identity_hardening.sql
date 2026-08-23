/* FASE 7B post-deployment hardening: primary-funder identity must never be
   inferred from a normalized display name alone. This migration is forward-only. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* A strong reusable identity is deliberately narrower than a general URL.
   It accepts only an already-canonical HTTPS URL with a lowercase DNS authority,
   no credentials/default port/query/fragment/control characters, and hashes the
   exact UTF-8 bytes. Paths remain binary/case-sensitive; no fuzzy normalization
   can silently merge two legal entities. */
CREATE OR ALTER FUNCTION dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash
(
    @Url NVARCHAR(2048)
)
RETURNS BINARY(32)
AS
BEGIN
    DECLARE @CanonicalUrl NVARCHAR(2048) = NULLIF(LTRIM(RTRIM(@Url)), N'');
    IF @CanonicalUrl IS NULL
       OR LEFT(@CanonicalUrl, 8) COLLATE Latin1_General_100_BIN2
          <> N'https://' COLLATE Latin1_General_100_BIN2
       OR CHARINDEX(N'?', @CanonicalUrl) > 0
       OR CHARINDEX(N'#', @CanonicalUrl) > 0
       OR CHARINDEX(N'@', @CanonicalUrl) > 0
       OR CHARINDEX(N'\', @CanonicalUrl) > 0
       OR CHARINDEX(N' ', @CanonicalUrl) > 0
        RETURN NULL;

    /* CHARINDEX cannot search for 0x0000 under Windows collations. Inspect each
       UTF-16 code unit instead, which also rejects the complete C0 control set. */
    DECLARE @CodeUnitPosition INT = 1;
    WHILE @CodeUnitPosition <= DATALENGTH(@CanonicalUrl) / 2
    BEGIN
        DECLARE @CodeUnit INT = UNICODE(SUBSTRING(@CanonicalUrl, @CodeUnitPosition, 1));
        IF @CodeUnit < 32 OR @CodeUnit = 127 RETURN NULL;
        SET @CodeUnitPosition += 1;
    END;

    DECLARE @AuthorityAndPath NVARCHAR(2040) = SUBSTRING(@CanonicalUrl, 9, 2040);
    DECLARE @PathStart INT = CHARINDEX(N'/', @AuthorityAndPath);
    DECLARE @Authority NVARCHAR(253) =
        CASE WHEN @PathStart = 0 THEN @AuthorityAndPath
             ELSE LEFT(@AuthorityAndPath, @PathStart - 1) END;

    IF NULLIF(@Authority, N'') IS NULL OR LEN(@Authority) > 253
       OR CHARINDEX(N'.', @Authority) = 0 OR CHARINDEX(N':', @Authority) > 0
       OR LEFT(@Authority, 1) IN (N'.', N'-')
       OR RIGHT(@Authority, 1) IN (N'.', N'-')
       OR CHARINDEX(N'..', @Authority) > 0
       OR CHARINDEX(N'.-', @Authority) > 0
       OR CHARINDEX(N'-.', @Authority) > 0
       OR @Authority COLLATE Latin1_General_100_BIN2
          <> LOWER(@Authority) COLLATE Latin1_General_100_BIN2
        RETURN NULL;

    DECLARE @AuthorityPosition INT = 1, @AuthorityHasLetter BIT = 0;
    WHILE @AuthorityPosition <= DATALENGTH(@Authority) / 2
    BEGIN
        DECLARE @AuthorityCodeUnit INT =
            UNICODE(SUBSTRING(@Authority, @AuthorityPosition, 1));
        IF @AuthorityCodeUnit BETWEEN 97 AND 122 SET @AuthorityHasLetter = 1;
        ELSE IF @AuthorityCodeUnit NOT BETWEEN 48 AND 57
                AND @AuthorityCodeUnit NOT IN (45, 46)
            RETURN NULL;
        SET @AuthorityPosition += 1;
    END;
    IF @AuthorityHasLetter = 0 RETURN NULL;

    RETURN HASHBYTES
    (
        'SHA2_256',
        CONVERT(VARBINARY(MAX),
            CONVERT(VARCHAR(MAX),
                @CanonicalUrl COLLATE Latin1_General_100_BIN2_UTF8))
    );
END;
GO

CREATE TABLE dbo.FundingPlatform_FundingOpportunityFunderIdentityConflicts
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_FunderIdentityConflicts_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    FundingOpportunityId BIGINT NOT NULL,
    CandidateFunderId BIGINT NOT NULL,
    ReasonCode NVARCHAR(50) NOT NULL,
    IdentityFingerprint BINARY(32) NOT NULL,
    SponsorUrlHash BINARY(32) NULL,
    FunderWebsiteUrlHash BINARY(32) NULL,
    IsExistingLink BIT NOT NULL,
    DetectedBy TINYINT NOT NULL,
    Status TINYINT NOT NULL
        CONSTRAINT FundingPlatform_DF_FunderIdentityConflicts_Status DEFAULT (0),
    OccurrenceCount INT NOT NULL
        CONSTRAINT FundingPlatform_DF_FunderIdentityConflicts_Occurrences DEFAULT (1),
    FirstDetectedAtUtc DATETIME2(3) NOT NULL,
    LastDetectedAtUtc DATETIME2(3) NOT NULL,
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_FunderIdentityConflicts PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_FunderIdentityConflicts_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_FunderIdentityConflicts_Identity
        UNIQUE (FundingOpportunityId, CandidateFunderId, IdentityFingerprint),
    CONSTRAINT FundingPlatform_FK_FunderIdentityConflicts_Opportunity
        FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id),
    CONSTRAINT FundingPlatform_FK_FunderIdentityConflicts_Funder
        FOREIGN KEY (CandidateFunderId) REFERENCES dbo.FundingPlatform_Funders (Id),
    CONSTRAINT FundingPlatform_CK_FunderIdentityConflicts_Reason
        CHECK (ReasonCode IN
        (
            N'name-collision-url-invalid', N'name-collision-url-mismatch',
            N'name-collision-funder-inactive',
            N'existing-primary-url-invalid', N'existing-primary-url-mismatch',
            N'existing-primary-funder-inactive'
        )),
    CONSTRAINT FundingPlatform_CK_FunderIdentityConflicts_DetectedBy
        CHECK (DetectedBy IN (1, 2)),
    CONSTRAINT FundingPlatform_CK_FunderIdentityConflicts_Status
        CHECK (Status BETWEEN 0 AND 2),
    CONSTRAINT FundingPlatform_CK_FunderIdentityConflicts_Occurrences
        CHECK (OccurrenceCount >= 1),
    CONSTRAINT FundingPlatform_CK_FunderIdentityConflicts_Times
        CHECK (LastDetectedAtUtc >= FirstDetectedAtUtc)
);
GO

CREATE INDEX FundingPlatform_IX_FunderIdentityConflicts_AdminQueue
    ON dbo.FundingPlatform_FundingOpportunityFunderIdentityConflicts
       (Status, LastDetectedAtUtc DESC, Id DESC)
    INCLUDE (PublicId, FundingOpportunityId, CandidateFunderId, ReasonCode,
             IsExistingLink, DetectedBy, OccurrenceCount, FirstDetectedAtUtc);
GO

/* Every existing public/readiness path already consumes this catalog guard.
   Extending it makes an unresolved legacy identity conflict fail closed for
   public list/get and publication request/review, without deleting a link. */
CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs()
RETURNS TABLE
AS
RETURN
(
    SELECT opportunities.Id AS FundingOpportunityId
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    WHERE (opportunities.Currency IS NULL OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_Currencies AS currencies
           WHERE currencies.Code = opportunities.Currency AND currencies.IsActive = 1))
      AND (opportunities.FundingTypeId IS NULL OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingTypes AS fundingTypes
           WHERE fundingTypes.Id = opportunities.FundingTypeId AND fundingTypes.IsActive = 1))
      AND (opportunities.IssuerCountryId IS NULL OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_Countries AS issuerCountries
           WHERE issuerCountries.Id = opportunities.IssuerCountryId
             AND issuerCountries.IsActive = 1))
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityCountries AS links
           LEFT JOIN dbo.FundingPlatform_Countries AS countries
               ON countries.Id = links.CountryId AND countries.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id AND countries.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityRegions AS links
           LEFT JOIN dbo.FundingPlatform_Regions AS regions
               ON regions.Id = links.RegionId AND regions.IsActive = 1
           LEFT JOIN dbo.FundingPlatform_Countries AS countries
               ON countries.Id = regions.CountryId AND countries.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id
             AND (regions.Id IS NULL OR countries.Id IS NULL))
      AND EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityCategories AS links
           INNER JOIN dbo.FundingPlatform_FundingCategories AS categories
               ON categories.Id = links.FundingCategoryId AND categories.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityCategories AS links
           LEFT JOIN dbo.FundingPlatform_FundingCategories AS categories
               ON categories.Id = links.FundingCategoryId AND categories.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id AND categories.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes AS links
           LEFT JOIN dbo.FundingPlatform_BeneficiaryTypes AS beneficiaryTypes
               ON beneficiaryTypes.Id = links.BeneficiaryTypeId AND beneficiaryTypes.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id AND beneficiaryTypes.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityProjectTypes AS links
           LEFT JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
               ON projectTypes.Id = links.ProjectTypeId AND projectTypes.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id AND projectTypes.Id IS NULL)
      AND
          ((opportunities.GeographicScope = 1 AND EXISTS
              (SELECT 1
               FROM dbo.FundingPlatform_FundingOpportunityCountries AS links
               INNER JOIN dbo.FundingPlatform_Countries AS countries
                   ON countries.Id = links.CountryId AND countries.IsActive = 1
               WHERE links.FundingOpportunityId = opportunities.Id))
           OR (opportunities.GeographicScope = 2
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS links
                    WHERE links.FundingOpportunityId = opportunities.Id)
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions AS links
                    WHERE links.FundingOpportunityId = opportunities.Id)))
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityFunderIdentityConflicts AS conflicts
           INNER JOIN dbo.FundingPlatform_FundingOpportunityFunders AS primaryLinks
               ON primaryLinks.FundingOpportunityId = conflicts.FundingOpportunityId
              AND primaryLinks.FunderId = conflicts.CandidateFunderId
              AND primaryLinks.Role = 1 AND primaryLinks.IsActive = 1
           WHERE conflicts.FundingOpportunityId = opportunities.Id
             AND conflicts.IsExistingLink = 1 AND conflicts.Status = 0)
);
GO

/* Internal, caller-transaction-safe conflict ledger. It emits no result set and
   writes a single IDs-only audit event when a distinct conflict first appears. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunityFunderIdentityConflict_Record
    @FundingOpportunityId BIGINT,
    @CandidateFunderId BIGINT,
    @ReasonCode NVARCHAR(50),
    @SponsorUrlHash BINARY(32) = NULL,
    @FunderWebsiteUrlHash BINARY(32) = NULL,
    @IsExistingLink BIT,
    @DetectedBy TINYINT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @FundingOpportunityId IS NULL OR @CandidateFunderId IS NULL OR @NowUtc IS NULL
       OR @IsExistingLink IS NULL OR @DetectedBy NOT IN (1, 2)
       OR NULLIF(LTRIM(RTRIM(@ReasonCode)), N'') IS NULL
       OR @ReasonCode NOT IN
          (N'name-collision-url-invalid', N'name-collision-url-mismatch',
           N'name-collision-funder-inactive',
           N'existing-primary-url-invalid', N'existing-primary-url-mismatch',
           N'existing-primary-funder-inactive')
        THROW 51901, N'Funder identity conflict metadata is invalid.', 1;

    DECLARE @IdentityFingerprint BINARY(32) = HASHBYTES
    (
        'SHA2_256',
        CONVERT(BINARY(8), @FundingOpportunityId)
        + CONVERT(BINARY(8), @CandidateFunderId)
        + CONVERT(VARBINARY(100), @ReasonCode)
        + COALESCE(@SponsorUrlHash,
            0x0000000000000000000000000000000000000000000000000000000000000000)
        + COALESCE(@FunderWebsiteUrlHash,
            0x0000000000000000000000000000000000000000000000000000000000000000)
    );
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @ConflictId BIGINT, @ConflictPublicId UNIQUEIDENTIFIER;
    DECLARE @Inserted BIT = 0;

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_FunderIdentityConflict;

    BEGIN TRY
        SELECT @ConflictId = Id, @ConflictPublicId = PublicId
        FROM dbo.FundingPlatform_FundingOpportunityFunderIdentityConflicts
             WITH (UPDLOCK, HOLDLOCK)
        WHERE FundingOpportunityId = @FundingOpportunityId
          AND CandidateFunderId = @CandidateFunderId
          AND IdentityFingerprint = @IdentityFingerprint;

        IF @ConflictId IS NULL
        BEGIN
            DECLARE @CreatedConflict TABLE
                (Id BIGINT NOT NULL, PublicId UNIQUEIDENTIFIER NOT NULL);
            INSERT INTO dbo.FundingPlatform_FundingOpportunityFunderIdentityConflicts
                (FundingOpportunityId, CandidateFunderId, ReasonCode,
                 IdentityFingerprint, SponsorUrlHash, FunderWebsiteUrlHash,
                 IsExistingLink, DetectedBy, Status, OccurrenceCount,
                 FirstDetectedAtUtc, LastDetectedAtUtc)
            OUTPUT inserted.Id, inserted.PublicId
                INTO @CreatedConflict (Id, PublicId)
            VALUES
                (@FundingOpportunityId, @CandidateFunderId, @ReasonCode,
                 @IdentityFingerprint, @SponsorUrlHash, @FunderWebsiteUrlHash,
                 @IsExistingLink, @DetectedBy, 0, 1, @NowUtc, @NowUtc);
            SELECT @ConflictId = Id, @ConflictPublicId = PublicId
            FROM @CreatedConflict;
            SET @Inserted = 1;
        END
        ELSE
            UPDATE dbo.FundingPlatform_FundingOpportunityFunderIdentityConflicts
            SET OccurrenceCount = CASE WHEN OccurrenceCount = 2147483647
                                       THEN OccurrenceCount ELSE OccurrenceCount + 1 END,
                LastDetectedAtUtc = CASE WHEN LastDetectedAtUtc > @NowUtc
                                         THEN LastDetectedAtUtc ELSE @NowUtc END
            WHERE Id = @ConflictId;

        IF @Inserted = 1
        BEGIN
            DECLARE @OpportunityPublicId UNIQUEIDENTIFIER, @FunderPublicId UNIQUEIDENTIFIER;
            SELECT @OpportunityPublicId = PublicId
            FROM dbo.FundingPlatform_FundingOpportunities WITH (HOLDLOCK)
            WHERE Id = @FundingOpportunityId;
            SELECT @FunderPublicId = PublicId
            FROM dbo.FundingPlatform_Funders WITH (HOLDLOCK)
            WHERE Id = @CandidateFunderId;

            INSERT INTO dbo.FundingPlatform_OutboxMessages
                (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                 OccurredAtUtc, AvailableAtUtc)
            VALUES
                (NEWID(), N'FundingOpportunityFunderIdentityConflictDetected',
                 N'FundingOpportunityFunderIdentityConflict',
                 CONVERT(NVARCHAR(100), @ConflictPublicId),
                 (SELECT @ConflictPublicId AS conflictId,
                         @OpportunityPublicId AS fundingOpportunityId,
                         @FunderPublicId AS candidateFunderId,
                         @ReasonCode AS reasonCode, 1 AS [version]
                  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                 @NowUtc, @NowUtc);
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_FunderIdentityConflict;
        THROW;
    END CATCH;
END;
GO

/* Keep the 016 implementation available as a creation/linking primitive. The
   public helper below serializes identity resolution before it may be invoked. */
EXEC sys.sp_rename
    @objname = N'dbo.FundingPlatform_usp_FundingOpportunity_EnsurePrimaryFunder',
    @newname = N'FundingPlatform_usp_FundingOpportunity_EnsurePrimaryFunder_Pre017',
    @objtype = N'OBJECT';
GO

CREATE PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_EnsurePrimaryFunder
    @FundingOpportunityPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @FundingOpportunityPublicId IS NULL RETURN;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @OpportunityId BIGINT, @SponsorName NVARCHAR(300), @SponsorUrl NVARCHAR(2048);
    DECLARE @NormalizedName NVARCHAR(300), @CandidateFunderId BIGINT;
    DECLARE @CandidateWebsiteUrl NVARCHAR(2048), @CandidateIsActive BIT;
    DECLARE @SponsorUrlHash BINARY(32), @CandidateUrlHash BINARY(32);
    DECLARE @ReasonCode NVARCHAR(50), @NowUtc DATETIME2(3) = SYSUTCDATETIME();

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_EnsurePrimaryFunder17;

    BEGIN TRY
        SELECT @OpportunityId = Id,
               @SponsorName = NULLIF(LTRIM(RTRIM(SponsorName)), N''),
               @SponsorUrl = NULLIF(LTRIM(RTRIM(SponsorUrl)), N'')
        FROM dbo.FundingPlatform_FundingOpportunities WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @FundingOpportunityPublicId;
        SET @NormalizedName = UPPER(@SponsorName);

        IF @OpportunityId IS NOT NULL AND @SponsorName IS NOT NULL
           AND NOT EXISTS
               (SELECT 1
                FROM dbo.FundingPlatform_FundingOpportunityFunders WITH (UPDLOCK, HOLDLOCK)
                WHERE FundingOpportunityId = @OpportunityId
                  AND Role = 1 AND IsActive = 1)
        BEGIN
            SELECT @CandidateFunderId = Id,
                   @CandidateWebsiteUrl = NULLIF(LTRIM(RTRIM(WebsiteUrl)), N''),
                   @CandidateIsActive = IsActive
            FROM dbo.FundingPlatform_Funders WITH (UPDLOCK, HOLDLOCK)
            WHERE NormalizedName = @NormalizedName;

            IF @CandidateFunderId IS NOT NULL
            BEGIN
                SET @SponsorUrlHash =
                    dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash(@SponsorUrl);
                SET @CandidateUrlHash =
                    dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash(@CandidateWebsiteUrl);
                SET @ReasonCode =
                    CASE
                      WHEN @CandidateIsActive <> 1 THEN N'name-collision-funder-inactive'
                      WHEN @SponsorUrlHash IS NULL OR @CandidateUrlHash IS NULL
                          THEN N'name-collision-url-invalid'
                      WHEN @SponsorUrlHash <> @CandidateUrlHash
                           OR @SponsorUrl COLLATE Latin1_General_100_BIN2
                              <> @CandidateWebsiteUrl COLLATE Latin1_General_100_BIN2
                          THEN N'name-collision-url-mismatch'
                      ELSE NULL
                    END;

                IF @ReasonCode IS NOT NULL
                    EXEC dbo.FundingPlatform_usp_FundingOpportunityFunderIdentityConflict_Record
                        @FundingOpportunityId = @OpportunityId,
                        @CandidateFunderId = @CandidateFunderId,
                        @ReasonCode = @ReasonCode,
                        @SponsorUrlHash = @SponsorUrlHash,
                        @FunderWebsiteUrlHash = @CandidateUrlHash,
                        @IsExistingLink = 0, @DetectedBy = 1, @NowUtc = @NowUtc;
            END;

            IF @CandidateFunderId IS NULL OR @ReasonCode IS NULL
                EXEC dbo.FundingPlatform_usp_FundingOpportunity_EnsurePrimaryFunder_Pre017
                    @FundingOpportunityPublicId = @FundingOpportunityPublicId;
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_EnsurePrimaryFunder17;
        THROW;
    END CATCH;
END;
GO

/* Do not remove any link created before 017: actorless backfills and later human
   curation cannot be distinguished with certainty. This internal, no-rowset
   audit is rerunnable and records unsafe active-primary links without mutating
   opportunities, funders, or links. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunityFunderIdentityConflict_AuditLegacy
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @NowUtc IS NULL THROW 51907, N'NowUtc is required.', 1;

    DECLARE @LegacyOpportunityId BIGINT, @LegacyFunderId BIGINT;
    DECLARE @LegacyReasonCode NVARCHAR(50), @LegacySponsorUrlHash BINARY(32);
    DECLARE @LegacyFunderUrlHash BINARY(32);
    DECLARE FundingPlatform_FunderIdentityAudit CURSOR LOCAL FAST_FORWARD FOR
        SELECT opportunities.Id, funders.Id,
               CASE WHEN funders.IsActive <> 1
                    THEN N'existing-primary-funder-inactive'
                    WHEN urlHashes.SponsorUrlHash IS NULL
                         OR urlHashes.FunderWebsiteUrlHash IS NULL
                    THEN N'existing-primary-url-invalid'
                    ELSE N'existing-primary-url-mismatch' END,
               urlHashes.SponsorUrlHash, urlHashes.FunderWebsiteUrlHash
        FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
        INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
            ON opportunities.Id = links.FundingOpportunityId
        INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
        CROSS APPLY
        (
            SELECT dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash(opportunities.SponsorUrl),
                   dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash(funders.WebsiteUrl)
        ) AS urlHashes(SponsorUrlHash, FunderWebsiteUrlHash)
        WHERE links.Role = 1 AND links.IsActive = 1
          AND funders.NormalizedName = UPPER(LTRIM(RTRIM(opportunities.SponsorName)))
          AND (funders.IsActive <> 1
               OR urlHashes.SponsorUrlHash IS NULL
               OR urlHashes.FunderWebsiteUrlHash IS NULL
               OR urlHashes.SponsorUrlHash <> urlHashes.FunderWebsiteUrlHash
               OR LTRIM(RTRIM(opportunities.SponsorUrl)) COLLATE Latin1_General_100_BIN2
                  <> LTRIM(RTRIM(funders.WebsiteUrl)) COLLATE Latin1_General_100_BIN2);
    OPEN FundingPlatform_FunderIdentityAudit;
    FETCH NEXT FROM FundingPlatform_FunderIdentityAudit
        INTO @LegacyOpportunityId, @LegacyFunderId, @LegacyReasonCode,
             @LegacySponsorUrlHash, @LegacyFunderUrlHash;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC dbo.FundingPlatform_usp_FundingOpportunityFunderIdentityConflict_Record
            @FundingOpportunityId = @LegacyOpportunityId,
            @CandidateFunderId = @LegacyFunderId,
            @ReasonCode = @LegacyReasonCode,
            @SponsorUrlHash = @LegacySponsorUrlHash,
            @FunderWebsiteUrlHash = @LegacyFunderUrlHash,
            @IsExistingLink = 1, @DetectedBy = 2, @NowUtc = @NowUtc;
        FETCH NEXT FROM FundingPlatform_FunderIdentityAudit
            INTO @LegacyOpportunityId, @LegacyFunderId, @LegacyReasonCode,
                 @LegacySponsorUrlHash, @LegacyFunderUrlHash;
    END;
    CLOSE FundingPlatform_FunderIdentityAudit;
    DEALLOCATE FundingPlatform_FunderIdentityAudit;
END;
GO

DECLARE @LegacyIdentityAuditAtUtc DATETIME2(3) = SYSUTCDATETIME();
EXEC dbo.FundingPlatform_usp_FundingOpportunityFunderIdentityConflict_AuditLegacy
    @NowUtc = @LegacyIdentityAuditAtUtc;
GO

/* Extend the event-ledger sink without turning this event into worker work. */
EXEC sys.sp_rename
    @objname = N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge',
    @newname = N'FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre017',
    @objtype = N'OBJECT';
GO

CREATE PROCEDURE dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge
    @BatchSize INT,
    @NowUtc DATETIME2(3),
    @AcknowledgedCount INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @BatchSize NOT BETWEEN 1 AND 500
        THROW 51902, N'BatchSize must be between 1 and 500.', 1;
    IF @NowUtc IS NULL THROW 51903, N'NowUtc is required.', 1;

    DECLARE @PreviousCount INT = 0;
    EXEC dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre017
        @BatchSize = @BatchSize, @NowUtc = @NowUtc,
        @AcknowledgedCount = @PreviousCount OUTPUT;

    DECLARE @Remaining INT = @BatchSize - @PreviousCount, @CurrentCount INT = 0;
    IF @Remaining > 0
    BEGIN
        ;WITH ConflictEvents AS
        (
            SELECT TOP (@Remaining) *
            FROM dbo.FundingPlatform_OutboxMessages
                 WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
            WHERE MessageType = N'FundingOpportunityFunderIdentityConflictDetected'
              AND AggregateType = N'FundingOpportunityFunderIdentityConflict'
              AND TRY_CONVERT(UNIQUEIDENTIFIER, AggregateId) =
                  TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(PayloadJson, N'$.conflictId'))
              AND TRY_CONVERT(INT, JSON_VALUE(PayloadJson, N'$.version')) = 1
              AND JSON_VALUE(PayloadJson, N'$.reasonCode') IN
                  (N'name-collision-url-invalid', N'name-collision-url-mismatch',
                   N'name-collision-funder-inactive',
                   N'existing-primary-url-invalid', N'existing-primary-url-mismatch',
                   N'existing-primary-funder-inactive')
              AND TRY_CONVERT(UNIQUEIDENTIFIER,
                    JSON_VALUE(PayloadJson, N'$.fundingOpportunityId')) IS NOT NULL
              AND TRY_CONVERT(UNIQUEIDENTIFIER,
                    JSON_VALUE(PayloadJson, N'$.candidateFunderId')) IS NOT NULL
              AND NOT EXISTS
                  (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                   WHERE fields.[key] NOT IN
                       (N'conflictId', N'fundingOpportunityId',
                        N'candidateFunderId', N'reasonCode', N'version'))
              AND DispatchedAtUtc IS NULL AND AvailableAtUtc <= @NowUtc
              AND (LeaseUntilUtc IS NULL OR LeaseUntilUtc <= @NowUtc)
            ORDER BY AvailableAtUtc, Id
        )
        UPDATE ConflictEvents
        SET DispatchedAtUtc = @NowUtc, LeaseOwner = NULL, LeaseUntilUtc = NULL,
            LastError = N'event-ledger-acknowledged';
        SET @CurrentCount = @@ROWCOUNT;
    END;
    SET @AcknowledgedCount = @PreviousCount + @CurrentCount;
END;
GO

/* Operational review surface: MFA-protected and intentionally excludes URLs,
   hashes, raw payloads, e-mail addresses, and storage identities. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunityFunderIdentityConflict_AdminList
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @Status TINYINT = NULL,
    @PageNumber INT = 1,
    @PageSize INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51904, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51905, N'MFA is required for this administrative operation.', 1;
    IF (@Status IS NOT NULL AND @Status NOT BETWEEN 0 AND 2)
       OR @PageNumber < 1 OR @PageSize NOT BETWEEN 1 AND 100
        THROW 51906, N'Identity-conflict filters are invalid.', 1;

    DECLARE @TotalCount BIGINT =
        (SELECT COUNT_BIG(1)
         FROM dbo.FundingPlatform_FundingOpportunityFunderIdentityConflicts
         WHERE @Status IS NULL OR Status = @Status);

    SELECT conflicts.PublicId AS ConflictPublicId,
           opportunities.PublicId AS FundingOpportunityPublicId,
           opportunities.Title AS FundingOpportunityTitle,
           funders.PublicId AS CandidateFunderPublicId,
           funders.Name AS CandidateFunderName,
           conflicts.ReasonCode, conflicts.IsExistingLink, conflicts.DetectedBy,
           conflicts.Status, conflicts.OccurrenceCount,
           conflicts.FirstDetectedAtUtc, conflicts.LastDetectedAtUtc,
           conflicts.RowVersion, @TotalCount AS TotalCount
    FROM dbo.FundingPlatform_FundingOpportunityFunderIdentityConflicts AS conflicts
    INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
        ON opportunities.Id = conflicts.FundingOpportunityId
    INNER JOIN dbo.FundingPlatform_Funders AS funders
        ON funders.Id = conflicts.CandidateFunderId
    WHERE @Status IS NULL OR conflicts.Status = @Status
    ORDER BY conflicts.LastDetectedAtUtc DESC, conflicts.Id DESC
    OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO
