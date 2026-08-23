/* FundingPlatform FASE 7B - governed document extraction, authenticated
   Defender receipts and human-only duplicate decisions. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

/* Compliance metadata is deliberately explicit. Unknown or rejected policy
   never authorizes a network fetch or document extraction. */
ALTER TABLE dbo.FundingPlatform_FundingSources ADD
    LicenseStatus TINYINT NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingSources_LicenseStatus DEFAULT (0),
    LicenseName NVARCHAR(200) NULL,
    LicenseUrl NVARCHAR(2048) NULL,
    LicenseUrlHash BINARY(32) NULL,
    LicenseReviewedAtUtc DATETIME2(3) NULL,
    LicenseExpiresAtUtc DATETIME2(3) NULL,
    RobotsPolicyStatus TINYINT NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingSources_RobotsPolicyStatus DEFAULT (0),
    RobotsExpiresAtUtc DATETIME2(3) NULL,
    RobotsPolicyCode NVARCHAR(20) NULL,
    RobotsPolicyVersion INT NULL,
    AcquisitionEndpointHash BINARY(32) NULL,
    AllowedHostsHash BINARY(32) NULL,
    AcquisitionPolicyFingerprint BINARY(32) NULL,
    RequestRateLimitPerMinute INT NULL,
    MaximumResponseBytes BIGINT NULL,
    ContentRetentionDays SMALLINT NULL,
    AllowedHostsRequired BIT NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingSources_AllowedHostsRequired DEFAULT (0),
    AcquisitionPolicyVersion INT NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingSources_PolicyVersion DEFAULT (1),
    NextAcquisitionAllowedAtUtc DATETIME2(3) NULL;
GO

ALTER TABLE dbo.FundingPlatform_FundingSources WITH CHECK
    ADD CONSTRAINT FundingPlatform_CK_FundingSources_LicensePolicy
        CHECK (LicenseStatus BETWEEN 0 AND 3
               AND (LicenseName IS NULL
                    OR NULLIF(LTRIM(RTRIM(LicenseName)), N'') IS NOT NULL)
               AND (LicenseUrl IS NULL
                    OR (LicenseUrl LIKE N'https://%'
                        AND CHARINDEX(CHAR(10), LicenseUrl) = 0
                        AND CHARINDEX(CHAR(13), LicenseUrl) = 0
                        AND CHARINDEX(CHAR(0), LicenseUrl) = 0))
               AND ((LicenseUrl IS NULL AND LicenseUrlHash IS NULL)
                    OR (LicenseUrl IS NOT NULL AND LicenseUrlHash IS NOT NULL))
               AND (LicenseExpiresAtUtc IS NULL
                    OR (LicenseReviewedAtUtc IS NOT NULL
                        AND LicenseExpiresAtUtc > LicenseReviewedAtUtc)));

ALTER TABLE dbo.FundingPlatform_FundingSources WITH CHECK
    ADD CONSTRAINT FundingPlatform_CK_FundingSources_RobotsPolicy
        CHECK (RobotsPolicyStatus BETWEEN 0 AND 3
               AND (RobotsPolicyCode IS NULL
                    OR RobotsPolicyCode IN (N'enforce', N'not-applicable'))
               AND (RobotsPolicyVersion IS NULL OR RobotsPolicyVersion >= 1)
               AND ((RobotsPolicyCode IS NULL AND RobotsPolicyVersion IS NULL)
                    OR (RobotsPolicyCode IS NOT NULL AND RobotsPolicyVersion IS NOT NULL))
               AND (RobotsExpiresAtUtc IS NULL
                    OR (RobotsReviewedAtUtc IS NOT NULL
                        AND RobotsExpiresAtUtc > RobotsReviewedAtUtc)));

ALTER TABLE dbo.FundingPlatform_FundingSources WITH CHECK
    ADD CONSTRAINT FundingPlatform_CK_FundingSources_AcquisitionLimits
        CHECK ((RequestRateLimitPerMinute IS NULL
                OR RequestRateLimitPerMinute BETWEEN 1 AND 600)
               AND (MaximumResponseBytes IS NULL
                    OR MaximumResponseBytes BETWEEN 1024 AND 26214400)
               AND (ContentRetentionDays IS NULL
                    OR ContentRetentionDays BETWEEN 1 AND 3650)
               AND AcquisitionPolicyVersion >= 1);

GO

CREATE TABLE dbo.FundingPlatform_FundingSourceAllowedHosts
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    FundingSourceId INT NOT NULL,
    HostName NVARCHAR(253) NOT NULL,
    Port SMALLINT NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingSourceAllowedHosts_Port DEFAULT (443),
    AllowSubdomains BIT NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingSourceAllowedHosts_Subdomains DEFAULT (0),
    IsEnabled BIT NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingSourceAllowedHosts_Enabled DEFAULT (1),
    CreatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingSourceAllowedHosts_Created DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingSourceAllowedHosts_Updated DEFAULT (SYSUTCDATETIME()),
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_FundingSourceAllowedHosts PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_FundingSourceAllowedHosts_SourceHost
        UNIQUE (FundingSourceId, HostName, Port),
    CONSTRAINT FundingPlatform_FK_FundingSourceAllowedHosts_Source
        FOREIGN KEY (FundingSourceId) REFERENCES dbo.FundingPlatform_FundingSources (Id),
    CONSTRAINT FundingPlatform_CK_FundingSourceAllowedHosts_Host
        CHECK (HostName = LOWER(LTRIM(RTRIM(HostName)))
               AND LEN(HostName) BETWEEN 1 AND 253
               AND HostName NOT LIKE N'%[^-a-z0-9.]%' COLLATE Latin1_General_100_BIN2
               AND HostName NOT LIKE N'.%'
               AND HostName NOT LIKE N'%.'
               AND HostName NOT LIKE N'%..%'
               AND Port BETWEEN 1 AND 32767),
    CONSTRAINT FundingPlatform_CK_FundingSourceAllowedHosts_Time
        CHECK (UpdatedAtUtc >= CreatedAtUtc)
);

CREATE INDEX FundingPlatform_IX_FundingSourceAllowedHosts_Resolve
    ON dbo.FundingPlatform_FundingSourceAllowedHosts (HostName, Port, IsEnabled, FundingSourceId)
    INCLUDE (AllowSubdomains);
GO

DECLARE @PolicySeedNowUtc DATETIME2(3) = SYSUTCDATETIME();

UPDATE dbo.FundingPlatform_FundingSources
SET LicenseStatus = 1,
    LicenseName = N'Official API terms',
    LicenseUrl = N'https://www.grants.gov/api/terms-conditions',
    LicenseUrlHash = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX),
        CONVERT(VARCHAR(MAX), N'https://www.grants.gov/api/terms-conditions'
            COLLATE Latin1_General_100_BIN2_UTF8))),
    LicenseReviewedAtUtc = COALESCE(LicenseReviewedAtUtc, TermsReviewedAtUtc, @PolicySeedNowUtc),
    RobotsPolicyStatus = 3,
    RobotsPolicyCode = N'not-applicable',
    RobotsPolicyVersion = 1,
    RobotsExpiresAtUtc = NULL,
    RequestRateLimitPerMinute = COALESCE(RequestRateLimitPerMinute, 60),
    MaximumResponseBytes = COALESCE(MaximumResponseBytes, 4194304),
    ContentRetentionDays = COALESCE(ContentRetentionDays, 90),
    AllowedHostsRequired = 1,
    AcquisitionEndpointHash = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX),
        CONVERT(VARCHAR(MAX), N'https://api.grants.gov/v1/api/'
            COLLATE Latin1_General_100_BIN2_UTF8))),
    AcquisitionPolicyVersion = AcquisitionPolicyVersion + 1,
    UpdatedAtUtc = @PolicySeedNowUtc
WHERE ProviderCode = N'grants-gov';

INSERT INTO dbo.FundingPlatform_FundingSourceAllowedHosts
    (FundingSourceId, HostName, Port, AllowSubdomains, IsEnabled, CreatedAtUtc, UpdatedAtUtc)
SELECT Id, N'api.grants.gov', 443, 0, 1, @PolicySeedNowUtc, @PolicySeedNowUtc
FROM dbo.FundingPlatform_FundingSources AS sources
WHERE sources.ProviderCode = N'grants-gov'
  AND NOT EXISTS
      (SELECT 1 FROM dbo.FundingPlatform_FundingSourceAllowedHosts AS hosts
       WHERE hosts.FundingSourceId = sources.Id
         AND hosts.HostName = N'api.grants.gov' AND hosts.Port = 443);

UPDATE dbo.FundingPlatform_FundingSources
SET ProviderCode = COALESCE(ProviderCode, N'manual-document'),
    ComplianceStatus = 1,
    ComplianceApprovedAtUtc = COALESCE(ComplianceApprovedAtUtc, @PolicySeedNowUtc),
    LicenseStatus = 3,
    LicenseName = NULL,
    LicenseUrl = NULL,
    LicenseUrlHash = NULL,
    LicenseReviewedAtUtc = COALESCE(LicenseReviewedAtUtc, @PolicySeedNowUtc),
    LicenseExpiresAtUtc = NULL,
    RobotsPolicyStatus = 3,
    RobotsPolicyCode = N'not-applicable',
    RobotsPolicyVersion = 1,
    RobotsReviewedAtUtc = COALESCE(RobotsReviewedAtUtc, @PolicySeedNowUtc),
    RobotsExpiresAtUtc = NULL,
    RequestRateLimitPerMinute = NULL,
    MaximumResponseBytes = COALESCE(MaximumResponseBytes, 26214400),
    ContentRetentionDays = COALESCE(ContentRetentionDays, 90),
    AllowedHostsRequired = 0,
    AcquisitionPolicyVersion = AcquisitionPolicyVersion + 1,
    UpdatedAtUtc = @PolicySeedNowUtc
WHERE Name = N'Manual document upload'
  AND (ProviderCode IS NULL OR ProviderCode = N'manual-document');

UPDATE dbo.FundingPlatform_FundingSources
SET ProviderCode = COALESCE(ProviderCode, N'manual-editorial'),
    ComplianceStatus = 1,
    ComplianceApprovedAtUtc = COALESCE(ComplianceApprovedAtUtc, @PolicySeedNowUtc),
    LicenseStatus = 3,
    LicenseUrlHash = NULL,
    LicenseReviewedAtUtc = COALESCE(LicenseReviewedAtUtc, @PolicySeedNowUtc),
    RobotsPolicyStatus = 3,
    RobotsPolicyCode = N'not-applicable',
    RobotsPolicyVersion = 1,
    RobotsReviewedAtUtc = COALESCE(RobotsReviewedAtUtc, @PolicySeedNowUtc),
    AllowedHostsRequired = 0,
    ContentRetentionDays = COALESCE(ContentRetentionDays, 90),
    AcquisitionPolicyVersion = AcquisitionPolicyVersion + 1,
    UpdatedAtUtc = @PolicySeedNowUtc
WHERE Name = N'Manual editorial';
GO

/* The optional RSS adapter exists as an inert catalog entry only. A governed,
   audited policy operation must provide its exact feed/license/robots policy
   and enable it; environment configuration alone can never activate SQL work. */
DECLARE @RssSeedNowUtc DATETIME2(3) = SYSUTCDATETIME();
INSERT INTO dbo.FundingPlatform_FundingSources
(
    Name, ProviderType, BaseUrl, IsEnabled, ScheduleCron, MinimumDelaySeconds,
    UserAgent, TermsUrl, TermsReviewedAtUtc, RobotsReviewedAtUtc,
    LastSuccessfulRunAtUtc, ConfigurationJson, SecretReference,
    ProviderCode, ScheduleIntervalSeconds, NextRunAtUtc,
    ComplianceStatus, ComplianceApprovedAtUtc, MaxRunAttempts,
    RetryBaseDelaySeconds, ConsecutiveFailureCount,
    LicenseStatus, LicenseName, LicenseUrl, LicenseUrlHash,
    LicenseReviewedAtUtc, LicenseExpiresAtUtc,
    RobotsPolicyStatus, RobotsExpiresAtUtc, RobotsPolicyCode,
    RobotsPolicyVersion, RequestRateLimitPerMinute, MaximumResponseBytes,
    ContentRetentionDays, AllowedHostsRequired, AcquisitionPolicyVersion,
    CreatedAtUtc, UpdatedAtUtc
)
SELECT N'Official RSS (disabled)', 2, NULL, 0, NULL, 2,
       N'FundingPlatform-MVP/0.1', NULL, NULL, NULL,
       NULL, N'{"providerCode":"official-rss","autoPublish":false}', NULL,
       N'official-rss', NULL, NULL,
       0, NULL, 3, 60, 0,
       0, NULL, NULL, NULL, NULL, NULL,
       0, NULL, NULL, NULL, NULL, NULL, 90, 1, 1,
       @RssSeedNowUtc, @RssSeedNowUtc
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_FundingSources
    WHERE ProviderCode = N'official-rss'
);
GO

DECLARE @FingerprintNowUtc DATETIME2(3) = SYSUTCDATETIME();
DECLARE @GrantSourceId INT =
    (SELECT Id FROM dbo.FundingPlatform_FundingSources WHERE ProviderCode = N'grants-gov');
IF @GrantSourceId IS NOT NULL
BEGIN
    DECLARE @GrantEndpointHash BINARY(32), @GrantLicenseHash BINARY(32);
    DECLARE @GrantHostsHash BINARY(32), @GrantPolicyVersion INT;
    SELECT @GrantEndpointHash = AcquisitionEndpointHash,
           @GrantLicenseHash = LicenseUrlHash,
           @GrantPolicyVersion = AcquisitionPolicyVersion
    FROM dbo.FundingPlatform_FundingSources WHERE Id = @GrantSourceId;
    SET @GrantHostsHash = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX),
        CONVERT(VARCHAR(MAX), N'api.grants.gov'
            COLLATE Latin1_General_100_BIN2_UTF8)));
    UPDATE dbo.FundingPlatform_FundingSources
    SET AllowedHostsHash = @GrantHostsHash,
        AcquisitionPolicyFingerprint = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX),
            CONVERT(VARCHAR(MAX), CONCAT
            (N'v1|grants-gov|', CONVERT(VARCHAR(64), @GrantEndpointHash, 2), N'|',
             CONVERT(VARCHAR(64), @GrantLicenseHash, 2), N'|not-applicable|1|',
             CONVERT(VARCHAR(64), @GrantHostsHash, 2), N'|',
             CONVERT(VARCHAR(20), @GrantPolicyVersion))
             COLLATE Latin1_General_100_BIN2_UTF8))),
        UpdatedAtUtc = @FingerprintNowUtc
    WHERE Id = @GrantSourceId;
END;
GO

/* Keep the editorial mutation from 010, but put a durable source-identity gate
   in front of it.  Acquisition workers must stage against the exact source id
   and provider code obtained from their leased run; source display names never
   participate in identity resolution and this wrapper never creates a source. */
EXEC sys.sp_rename
    @objname = N'dbo.FundingPlatform_usp_FundingOpportunity_StageExternal',
    @newname = N'FundingPlatform_usp_FundingOpportunity_StageExternal_Pre016',
    @objtype = N'OBJECT';
GO

CREATE PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_StageExternal
    @FundingSourceId INT,
    @ExpectedProviderCode NVARCHAR(100) = NULL,
    @ExternalId NVARCHAR(250) = NULL,
    @SourceItemKeyHash BINARY(32),
    @SourceUrl NVARCHAR(2048) = NULL,
    @CanonicalUrlHash BINARY(32) = NULL,
    @ObservedAtUtc DATETIME2(3),
    @Slug NVARCHAR(320),
    @Title NVARCHAR(350),
    @Description NVARCHAR(MAX) = NULL,
    @Summary NVARCHAR(2000) = NULL,
    @SponsorName NVARCHAR(300),
    @SponsorUrl NVARCHAR(2048) = NULL,
    @ApplicationUrl NVARCHAR(2048) = NULL,
    @FundingTypeId SMALLINT = NULL,
    @Currency CHAR(3) = NULL,
    @MinAmount DECIMAL(19,4) = NULL,
    @MaxAmount DECIMAL(19,4) = NULL,
    @AmountStatus TINYINT,
    @OpenDate DATE = NULL,
    @CloseDate DATE = NULL,
    @DeadlineType TINYINT,
    @DeadlinePrecision TINYINT,
    @EligibilityDescription NVARCHAR(MAX) = NULL,
    @Objectives NVARCHAR(MAX) = NULL,
    @RequiresCofunding BIT = NULL,
    @CofundingPercentage DECIMAL(5,2) = NULL,
    @DataQualityScore DECIMAL(5,2),
    @SnapshotJson NVARCHAR(MAX),
    @ContentHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @StoredProviderCode NVARCHAR(100), @ProviderType TINYINT;
    DECLARE @SourceReady BIT = 0;

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_StageExternalIdentity;

    BEGIN TRY
        IF @FundingSourceId > 0
           AND (@ExpectedProviderCode IS NULL
                OR (NULLIF(LTRIM(RTRIM(@ExpectedProviderCode)), N'') IS NOT NULL
                    AND LEN(@ExpectedProviderCode) <= 100
                    AND @ExpectedProviderCode = LTRIM(RTRIM(@ExpectedProviderCode))
                    AND @ExpectedProviderCode NOT LIKE N'%[^-a-z0-9._]%'
                        COLLATE Latin1_General_100_BIN2))
        BEGIN
            SELECT @StoredProviderCode = sources.ProviderCode,
                   @ProviderType = sources.ProviderType,
                   @SourceReady = CASE
                       WHEN sources.ProviderType = 0 AND sources.IsEnabled = 1 THEN 1
                       WHEN sources.ProviderType IN (1, 2, 3)
                        AND @ExpectedProviderCode IS NOT NULL
                        AND sources.IsEnabled = 1
                        AND sources.ComplianceStatus = 1
                        AND sources.ComplianceApprovedAtUtc IS NOT NULL
                        AND policies.PolicyVersion = sources.AcquisitionPolicyVersion
                        AND policies.PolicyFingerprint IS NOT NULL
                        AND policies.PolicyFingerprint = sources.AcquisitionPolicyFingerprint
                       THEN 1 ELSE 0 END
            FROM dbo.FundingPlatform_FundingSources AS sources WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions AS policies
                WITH (HOLDLOCK)
                ON policies.FundingSourceId = sources.Id
               AND policies.PolicyVersion = sources.AcquisitionPolicyVersion
            WHERE sources.Id = @FundingSourceId;
        END;

        IF @StoredProviderCode IS NULL
           OR (@ExpectedProviderCode IS NULL AND @ProviderType <> 0)
           OR (@ExpectedProviderCode IS NOT NULL
               AND @StoredProviderCode COLLATE Latin1_General_100_BIN2
                   <> @ExpectedProviderCode COLLATE Latin1_General_100_BIN2)
           OR @SourceReady = 0
        BEGIN
            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CAST(0 AS BIT) AS Succeeded,
                   CASE WHEN @StoredProviderCode IS NULL THEN N'source-not-found'
                        WHEN @ExpectedProviderCode IS NULL AND @ProviderType <> 0
                            THEN N'source-identity-required'
                        WHEN @ExpectedProviderCode IS NOT NULL
                             AND @StoredProviderCode COLLATE Latin1_General_100_BIN2
                                 <> @ExpectedProviderCode COLLATE Latin1_General_100_BIN2
                            THEN N'source-identity-mismatch'
                        ELSE N'source-policy-not-ready' END AS Code,
                   CAST(NULL AS UNIQUEIDENTIFIER) AS FundingOpportunityPublicId,
                   CAST(NULL AS INT) AS ContentVersion,
                   CAST(NULL AS TINYINT) AS PublicationStatus,
                   CAST(NULL AS BINARY(8)) AS RowVersion,
                   CAST(NULL AS UNIQUEIDENTIFIER) AS StagedRevisionPublicId;
            RETURN;
        END;

        EXEC dbo.FundingPlatform_usp_FundingOpportunity_StageExternal_Pre016
            @FundingSourceId = @FundingSourceId,
            @ExternalId = @ExternalId,
            @SourceItemKeyHash = @SourceItemKeyHash,
            @SourceUrl = @SourceUrl,
            @CanonicalUrlHash = @CanonicalUrlHash,
            @ObservedAtUtc = @ObservedAtUtc,
            @Slug = @Slug,
            @Title = @Title,
            @Description = @Description,
            @Summary = @Summary,
            @SponsorName = @SponsorName,
            @SponsorUrl = @SponsorUrl,
            @ApplicationUrl = @ApplicationUrl,
            @FundingTypeId = @FundingTypeId,
            @Currency = @Currency,
            @MinAmount = @MinAmount,
            @MaxAmount = @MaxAmount,
            @AmountStatus = @AmountStatus,
            @OpenDate = @OpenDate,
            @CloseDate = @CloseDate,
            @DeadlineType = @DeadlineType,
            @DeadlinePrecision = @DeadlinePrecision,
            @EligibilityDescription = @EligibilityDescription,
            @Objectives = @Objectives,
            @RequiresCofunding = @RequiresCofunding,
            @CofundingPercentage = @CofundingPercentage,
            @DataQualityScore = @DataQualityScore,
            @SnapshotJson = @SnapshotJson,
            @ContentHash = @ContentHash;

        /* Do not capture the legacy result set with INSERT EXEC: callers use
           INSERT EXEC themselves and SQL Server forbids nested INSERT EXEC.
           Resolve the durable identity from the exact source-link key after
           staging, then run the add-only provenance helper silently. */
        DECLARE @CoreOpportunityPublicId UNIQUEIDENTIFIER;
        SELECT @CoreOpportunityPublicId = opportunities.PublicId
        FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links WITH (HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities WITH (HOLDLOCK)
            ON opportunities.Id = links.FundingOpportunityId
        WHERE links.FundingSourceId = @FundingSourceId
          AND links.SourceItemKeyHash = @SourceItemKeyHash;

        IF @CoreOpportunityPublicId IS NOT NULL
            EXEC dbo.FundingPlatform_usp_FundingOpportunity_EnsurePrimaryFunder
                @FundingOpportunityPublicId = @CoreOpportunityPublicId;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_StageExternalIdentity;
        THROW;
    END CATCH;
END;
GO

/* StageExternal has always required sponsor provenance.  Keep the canonical
   funder relation synchronized without publishing either side or inventing a
   reviewer.  This internal helper is idempotent and caller-transaction-safe. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_EnsurePrimaryFunder
    @FundingOpportunityPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @FundingOpportunityPublicId IS NULL RETURN;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @OpportunityId BIGINT, @SponsorName NVARCHAR(300), @SponsorUrl NVARCHAR(2048);
    DECLARE @NormalizedName NVARCHAR(300), @OpportunityCreatedAtUtc DATETIME2(3);
    DECLARE @FunderId BIGINT, @EvidenceId BIGINT, @NowUtc DATETIME2(3) = SYSUTCDATETIME();

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_EnsurePrimaryFunder;
    BEGIN TRY
        SELECT @OpportunityId = Id, @SponsorName = LTRIM(RTRIM(SponsorName)),
               @SponsorUrl = SponsorUrl, @OpportunityCreatedAtUtc = CreatedAtUtc
        FROM dbo.FundingPlatform_FundingOpportunities WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @FundingOpportunityPublicId;
        SET @NormalizedName = UPPER(@SponsorName);

        IF @OpportunityId IS NOT NULL AND NULLIF(@SponsorName, N'') IS NOT NULL
           AND NOT EXISTS
               (SELECT 1
                FROM dbo.FundingPlatform_FundingOpportunityFunders WITH (UPDLOCK, HOLDLOCK)
                WHERE FundingOpportunityId = @OpportunityId
                  AND Role = 1 AND IsActive = 1)
        BEGIN
            SELECT @FunderId = Id
            FROM dbo.FundingPlatform_Funders WITH (UPDLOCK, HOLDLOCK)
            WHERE NormalizedName = @NormalizedName;

            IF @FunderId IS NULL
            BEGIN
                DECLARE @InsertedFunder TABLE (Id BIGINT PRIMARY KEY);
                INSERT INTO dbo.FundingPlatform_Funders
                    (Slug, Name, NormalizedName, WebsiteUrl, PublicationStatus,
                     ContentVersion, IsActive, CreatedAtUtc, UpdatedAtUtc)
                OUTPUT inserted.Id INTO @InsertedFunder (Id)
                VALUES
                    (N'imported-' + LOWER(CONVERT(VARCHAR(64),
                         HASHBYTES('SHA2_256', @NormalizedName), 2)),
                     @SponsorName, @NormalizedName, @SponsorUrl, 0,
                     1, 1, @OpportunityCreatedAtUtc, @NowUtc);
                SELECT @FunderId = Id FROM @InsertedFunder;
            END;

            IF NOT EXISTS
               (SELECT 1 FROM dbo.FundingPlatform_FunderAliases WITH (UPDLOCK, HOLDLOCK)
                WHERE FunderId = @FunderId AND NormalizedAlias = @NormalizedName)
                INSERT INTO dbo.FundingPlatform_FunderAliases
                    (FunderId, Alias, NormalizedAlias, IsPrimary, IsActive, CreatedAtUtc)
                VALUES (@FunderId, @SponsorName, @NormalizedName, 1, 1, @NowUtc);

            IF NOT EXISTS
               (SELECT 1 FROM dbo.FundingPlatform_FunderVersions WITH (UPDLOCK, HOLDLOCK)
                WHERE FunderId = @FunderId AND ContentVersion = 1)
            BEGIN
                DECLARE @FunderSnapshot NVARCHAR(MAX) =
                    (SELECT funders.Slug AS slug, funders.Name AS name,
                            funders.Description AS description,
                            funders.WebsiteUrl AS websiteUrl,
                            funders.CountryId AS countryId
                     FROM dbo.FundingPlatform_Funders AS funders
                     WHERE funders.Id = @FunderId
                     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
                INSERT INTO dbo.FundingPlatform_FunderVersions
                    (FunderId, ContentVersion, SnapshotJson, ContentHash,
                     CreatedByUserId, CreatedAtUtc)
                VALUES (@FunderId, 1, @FunderSnapshot,
                        HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @FunderSnapshot)),
                        NULL, @NowUtc);
            END;

            SELECT TOP (1) @EvidenceId = Id
            FROM dbo.FundingPlatform_FundingFieldEvidence WITH (UPDLOCK, HOLDLOCK)
            WHERE FundingOpportunityId = @OpportunityId
              AND FieldPath = N'/sponsorName' AND IsSelected = 1
            ORDER BY Id DESC;
            IF @EvidenceId IS NULL
            BEGIN
                DECLARE @InsertedEvidence TABLE (Id BIGINT PRIMARY KEY);
                INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
                    (FundingOpportunityId, FieldPath, ValueJson,
                     FundingOpportunitySourceLinkId, ExtractionMethod, EvidenceText,
                     SourceLocator, Confidence, IsSelected, IsManualLock,
                     CreatedByUserId, CreatedAtUtc)
                OUTPUT inserted.Id INTO @InsertedEvidence (Id)
                VALUES
                    (@OpportunityId, N'/sponsorName',
                     (SELECT @SponsorName AS [value], N'known' AS [status]
                      FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                     NULL, 2, LEFT(@SponsorName, 2000), N'canonical-row',
                     NULL, 1, 0, NULL, @NowUtc);
                SELECT @EvidenceId = Id FROM @InsertedEvidence;
            END;

            UPDATE dbo.FundingPlatform_FundingOpportunityFunders
            SET Role = 1, EvidenceId = @EvidenceId, IsActive = 1, UpdatedAtUtc = @NowUtc
            WHERE FundingOpportunityId = @OpportunityId AND FunderId = @FunderId;
            IF @@ROWCOUNT = 0
                INSERT INTO dbo.FundingPlatform_FundingOpportunityFunders
                    (FundingOpportunityId, FunderId, Role, EvidenceId,
                     IsActive, CreatedAtUtc, UpdatedAtUtc)
                VALUES (@OpportunityId, @FunderId, 1, @EvidenceId,
                        1, @NowUtc, @NowUtc);
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_EnsurePrimaryFunder;
        THROW;
    END CATCH;
END;
GO

/* Repair only the derived sponsor relation for rows produced after the FASE 6
   backfill.  No opportunity or funder is published by this maintenance pass. */
DECLARE @BackfillOpportunityPublicId UNIQUEIDENTIFIER;
DECLARE FundingPlatform_PrimaryFunderBackfill CURSOR LOCAL FAST_FORWARD FOR
    SELECT opportunities.PublicId
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    WHERE NULLIF(LTRIM(RTRIM(opportunities.SponsorName)), N'') IS NOT NULL
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
           WHERE links.FundingOpportunityId = opportunities.Id
             AND links.Role = 1 AND links.IsActive = 1);
OPEN FundingPlatform_PrimaryFunderBackfill;
FETCH NEXT FROM FundingPlatform_PrimaryFunderBackfill INTO @BackfillOpportunityPublicId;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_EnsurePrimaryFunder
        @FundingOpportunityPublicId = @BackfillOpportunityPublicId;
    FETCH NEXT FROM FundingPlatform_PrimaryFunderBackfill INTO @BackfillOpportunityPublicId;
END;
CLOSE FundingPlatform_PrimaryFunderBackfill;
DEALLOCATE FundingPlatform_PrimaryFunderBackfill;
GO

ALTER TABLE dbo.FundingPlatform_FundingSources WITH CHECK
    ADD CONSTRAINT FundingPlatform_CK_FundingSources_NetworkGovernance
        CHECK (ComplianceStatus <> 1 OR ProviderType NOT IN (1, 2, 3)
               OR (LicenseStatus = 1
                   AND NULLIF(LTRIM(RTRIM(LicenseName)), N'') IS NOT NULL
                   AND LicenseUrl LIKE N'https://%'
                   AND LicenseUrlHash IS NOT NULL
                   AND LicenseReviewedAtUtc IS NOT NULL
                   AND AcquisitionEndpointHash IS NOT NULL
                   AND AllowedHostsHash IS NOT NULL
                   AND AcquisitionPolicyFingerprint IS NOT NULL
                   AND AllowedHostsRequired = 1
                   AND RequestRateLimitPerMinute IS NOT NULL
                   AND MaximumResponseBytes IS NOT NULL
                   AND ContentRetentionDays IS NOT NULL));
GO

/* Policy versions are immutable evidence. Runtime authorization and durable
   artifacts resolve this snapshot instead of mutable catalog columns. */
CREATE TABLE dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingSourcePolicies_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    FundingSourceId INT NOT NULL,
    PolicyVersion INT NOT NULL,
    ProviderCode NVARCHAR(100) NULL,
    ProviderType TINYINT NOT NULL,
    BaseUrl NVARCHAR(2048) NULL,
    AcquisitionEndpointHash BINARY(32) NULL,
    LicenseStatus TINYINT NOT NULL,
    LicenseName NVARCHAR(200) NULL,
    LicenseUrl NVARCHAR(2048) NULL,
    LicenseUrlHash BINARY(32) NULL,
    LicenseReviewedAtUtc DATETIME2(3) NULL,
    LicenseExpiresAtUtc DATETIME2(3) NULL,
    RobotsPolicyStatus TINYINT NOT NULL,
    RobotsPolicyCode NVARCHAR(20) NULL,
    RobotsPolicyVersion INT NULL,
    RobotsReviewedAtUtc DATETIME2(3) NULL,
    RobotsExpiresAtUtc DATETIME2(3) NULL,
    AllowedHostsHash BINARY(32) NULL,
    RequestRateLimitPerMinute INT NULL,
    MaximumResponseBytes INT NULL,
    ContentRetentionDays SMALLINT NOT NULL,
    PolicyFingerprint BINARY(32) NULL,
    CreatedByUserId BIGINT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_FundingSourcePolicies PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_FundingSourcePolicies_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_FundingSourcePolicies_SourceVersion
        UNIQUE (FundingSourceId, PolicyVersion),
    CONSTRAINT FundingPlatform_UQ_FundingSourcePolicies_IdSource
        UNIQUE (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_FK_FundingSourcePolicies_Source
        FOREIGN KEY (FundingSourceId) REFERENCES dbo.FundingPlatform_FundingSources (Id),
    CONSTRAINT FundingPlatform_FK_FundingSourcePolicies_Actor
        FOREIGN KEY (CreatedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_FundingSourcePolicies_Identity
        CHECK (PolicyVersion >= 1 AND ProviderType BETWEEN 0 AND 4
               AND (ProviderCode IS NULL
                    OR (ProviderCode = LOWER(LTRIM(RTRIM(ProviderCode)))
                        AND CHARINDEX(CHAR(10), ProviderCode) = 0
                        AND CHARINDEX(CHAR(13), ProviderCode) = 0
                        AND CHARINDEX(CHAR(0), ProviderCode) = 0))),
    CONSTRAINT FundingPlatform_CK_FundingSourcePolicies_License
        CHECK (LicenseStatus BETWEEN 0 AND 3
               AND ((LicenseUrl IS NULL AND LicenseUrlHash IS NULL)
                    OR (LicenseUrl LIKE N'https://%'
                        AND LicenseUrlHash IS NOT NULL
                        AND CHARINDEX(CHAR(10), LicenseUrl) = 0
                        AND CHARINDEX(CHAR(13), LicenseUrl) = 0
                        AND CHARINDEX(CHAR(0), LicenseUrl) = 0))
               AND (LicenseExpiresAtUtc IS NULL
                    OR (LicenseReviewedAtUtc IS NOT NULL
                        AND LicenseExpiresAtUtc > LicenseReviewedAtUtc))),
    CONSTRAINT FundingPlatform_CK_FundingSourcePolicies_Robots
        CHECK (RobotsPolicyStatus BETWEEN 0 AND 3
               AND (RobotsPolicyCode IS NULL
                    OR RobotsPolicyCode IN (N'enforce', N'not-applicable'))
               AND ((RobotsPolicyCode IS NULL AND RobotsPolicyVersion IS NULL)
                    OR (RobotsPolicyCode IS NOT NULL AND RobotsPolicyVersion >= 1))
               AND (RobotsExpiresAtUtc IS NULL
                    OR (RobotsReviewedAtUtc IS NOT NULL
                        AND RobotsExpiresAtUtc > RobotsReviewedAtUtc))),
    CONSTRAINT FundingPlatform_CK_FundingSourcePolicies_Limits
        CHECK ((RequestRateLimitPerMinute IS NULL
                OR RequestRateLimitPerMinute BETWEEN 1 AND 600)
               AND (MaximumResponseBytes IS NULL
                    OR MaximumResponseBytes BETWEEN 1024 AND 26214400)
               AND ContentRetentionDays BETWEEN 1 AND 3650),
    CONSTRAINT FundingPlatform_CK_FundingSourcePolicies_NetworkReady
        CHECK (ProviderType NOT IN (1, 2, 3)
               OR PolicyFingerprint IS NULL
               OR (ProviderCode IS NOT NULL AND BaseUrl LIKE N'https://%'
                   AND AcquisitionEndpointHash IS NOT NULL
                   AND LicenseStatus = 1 AND LicenseName IS NOT NULL
                   AND LicenseUrlHash IS NOT NULL AND LicenseReviewedAtUtc IS NOT NULL
                   AND RobotsPolicyCode IS NOT NULL AND RobotsPolicyVersion IS NOT NULL
                   AND AllowedHostsHash IS NOT NULL
                   AND RequestRateLimitPerMinute IS NOT NULL
                   AND MaximumResponseBytes IS NOT NULL))
);

CREATE TABLE dbo.FundingPlatform_FundingSourceAcquisitionPolicyHosts
(
    PolicyId BIGINT NOT NULL,
    FundingSourceId INT NOT NULL,
    HostName NVARCHAR(253) NOT NULL,
    Port SMALLINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_FundingSourcePolicyHosts
        PRIMARY KEY (PolicyId, HostName, Port),
    CONSTRAINT FundingPlatform_FK_FundingSourcePolicyHosts_Policy
        FOREIGN KEY (PolicyId, FundingSourceId)
        REFERENCES dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_CK_FundingSourcePolicyHosts_Host
        CHECK (HostName = LOWER(LTRIM(RTRIM(HostName)))
               AND LEN(HostName) BETWEEN 3 AND 253
               AND HostName LIKE N'%.%'
               AND HostName LIKE N'%[a-z]%'
                    COLLATE Latin1_General_100_BIN2
               AND HostName NOT LIKE N'%[^-a-z0-9.]%'
                    COLLATE Latin1_General_100_BIN2
               AND HostName <> N'localhost' AND HostName NOT LIKE N'%.local'
               AND Port = 443)
);

/* Kind: 1 primary/base, 2 outbound API/feed, 3 robots.txt. */
CREATE TABLE dbo.FundingPlatform_FundingSourceAcquisitionPolicyEndpoints
(
    PolicyId BIGINT NOT NULL,
    FundingSourceId INT NOT NULL,
    EndpointKind TINYINT NOT NULL,
    CanonicalUri NVARCHAR(2048) NOT NULL,
    CanonicalUriHash BINARY(32) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_FundingSourcePolicyEndpoints
        PRIMARY KEY (PolicyId, EndpointKind, CanonicalUriHash),
    CONSTRAINT FundingPlatform_FK_FundingSourcePolicyEndpoints_Policy
        FOREIGN KEY (PolicyId, FundingSourceId)
        REFERENCES dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_CK_FundingSourcePolicyEndpoints_Uri
        CHECK (EndpointKind BETWEEN 1 AND 3
               AND CanonicalUri LIKE N'https://%'
               AND LEN(CanonicalUri) BETWEEN 10 AND 2048
               AND CHARINDEX(N'@', CanonicalUri) = 0
               AND CHARINDEX(N'#', CanonicalUri) = 0
               AND CHARINDEX(CHAR(10), CanonicalUri) = 0
               AND CHARINDEX(CHAR(13), CanonicalUri) = 0
               AND CHARINDEX(CHAR(0), CanonicalUri) = 0)
);

CREATE TABLE dbo.FundingPlatform_FundingSourceAcquisitionPolicyEvents
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingSourcePolicyEvents_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    FundingSourceId INT NOT NULL,
    PolicyId BIGINT NOT NULL,
    ActorUserId BIGINT NOT NULL,
    Action TINYINT NOT NULL,
    IdempotencyKeyHash BINARY(32) NOT NULL,
    RequestHash BINARY(32) NOT NULL,
    CorrelationId NVARCHAR(100) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_FundingSourcePolicyEvents PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_FundingSourcePolicyEvents_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_FundingSourcePolicyEvents_Idempotency
        UNIQUE (ActorUserId, FundingSourceId, IdempotencyKeyHash),
    CONSTRAINT FundingPlatform_FK_FundingSourcePolicyEvents_Source
        FOREIGN KEY (FundingSourceId) REFERENCES dbo.FundingPlatform_FundingSources (Id),
    CONSTRAINT FundingPlatform_FK_FundingSourcePolicyEvents_Policy
        FOREIGN KEY (PolicyId, FundingSourceId)
        REFERENCES dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_FK_FundingSourcePolicyEvents_Actor
        FOREIGN KEY (ActorUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_FundingSourcePolicyEvents_Fields
        CHECK (Action IN (1, 2)
               AND NULLIF(LTRIM(RTRIM(CorrelationId)), N'') IS NOT NULL
               AND CorrelationId COLLATE Latin1_General_100_BIN2
                   NOT LIKE N'%[^-A-Za-z0-9:_.]%' COLLATE Latin1_General_100_BIN2)
);
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_FundingSourcePolicies_Immutable
ON dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions
INSTEAD OF UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    THROW 51868, N'Acquisition policy versions are append-only.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_FundingSourcePolicyHosts_Immutable
ON dbo.FundingPlatform_FundingSourceAcquisitionPolicyHosts
INSTEAD OF UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    THROW 51868, N'Acquisition policy hosts are append-only.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_FundingSourcePolicyEndpoints_Immutable
ON dbo.FundingPlatform_FundingSourceAcquisitionPolicyEndpoints
INSTEAD OF UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    THROW 51868, N'Acquisition policy endpoints are append-only.', 1;
END;
GO

DECLARE @PolicyHistoryNowUtc DATETIME2(3) = SYSUTCDATETIME();
INSERT INTO dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions
    (FundingSourceId, PolicyVersion, ProviderCode, ProviderType, BaseUrl,
     AcquisitionEndpointHash, LicenseStatus, LicenseName, LicenseUrl,
     LicenseUrlHash, LicenseReviewedAtUtc, LicenseExpiresAtUtc,
     RobotsPolicyStatus, RobotsPolicyCode, RobotsPolicyVersion,
     RobotsReviewedAtUtc, RobotsExpiresAtUtc, AllowedHostsHash,
     RequestRateLimitPerMinute, MaximumResponseBytes, ContentRetentionDays,
     PolicyFingerprint, CreatedByUserId, CreatedAtUtc)
SELECT sources.Id, sources.AcquisitionPolicyVersion, sources.ProviderCode,
       sources.ProviderType, sources.BaseUrl, sources.AcquisitionEndpointHash,
       sources.LicenseStatus, sources.LicenseName, sources.LicenseUrl,
       sources.LicenseUrlHash, sources.LicenseReviewedAtUtc, sources.LicenseExpiresAtUtc,
       sources.RobotsPolicyStatus, sources.RobotsPolicyCode,
       sources.RobotsPolicyVersion, sources.RobotsReviewedAtUtc,
       sources.RobotsExpiresAtUtc, sources.AllowedHostsHash,
       sources.RequestRateLimitPerMinute,
       CONVERT(INT, sources.MaximumResponseBytes),
       COALESCE(sources.ContentRetentionDays, CONVERT(SMALLINT, 90)),
       sources.AcquisitionPolicyFingerprint, NULL, @PolicyHistoryNowUtc
FROM dbo.FundingPlatform_FundingSources AS sources;

INSERT INTO dbo.FundingPlatform_FundingSourceAcquisitionPolicyHosts
    (PolicyId, FundingSourceId, HostName, Port, CreatedAtUtc)
SELECT policies.Id, policies.FundingSourceId, hosts.HostName, hosts.Port,
       @PolicyHistoryNowUtc
FROM dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions AS policies
INNER JOIN dbo.FundingPlatform_FundingSources AS sources
    ON sources.Id = policies.FundingSourceId
   AND sources.AcquisitionPolicyVersion = policies.PolicyVersion
INNER JOIN dbo.FundingPlatform_FundingSourceAllowedHosts AS hosts
    ON hosts.FundingSourceId = sources.Id AND hosts.IsEnabled = 1;

INSERT INTO dbo.FundingPlatform_FundingSourceAcquisitionPolicyEndpoints
    (PolicyId, FundingSourceId, EndpointKind, CanonicalUri,
     CanonicalUriHash, CreatedAtUtc)
SELECT policies.Id, policies.FundingSourceId, 1, sources.BaseUrl,
       sources.AcquisitionEndpointHash, @PolicyHistoryNowUtc
FROM dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions AS policies
INNER JOIN dbo.FundingPlatform_FundingSources AS sources
    ON sources.Id = policies.FundingSourceId
   AND sources.AcquisitionPolicyVersion = policies.PolicyVersion
WHERE sources.BaseUrl IS NOT NULL AND sources.AcquisitionEndpointHash IS NOT NULL;

INSERT INTO dbo.FundingPlatform_FundingSourceAcquisitionPolicyEndpoints
    (PolicyId, FundingSourceId, EndpointKind, CanonicalUri,
     CanonicalUriHash, CreatedAtUtc)
SELECT policies.Id, policies.FundingSourceId, 2, endpoints.CanonicalUri,
       HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
           endpoints.CanonicalUri COLLATE Latin1_General_100_BIN2_UTF8))),
       @PolicyHistoryNowUtc
FROM dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions AS policies
INNER JOIN dbo.FundingPlatform_FundingSources AS sources
    ON sources.Id = policies.FundingSourceId
   AND sources.AcquisitionPolicyVersion = policies.PolicyVersion
CROSS APPLY
(
    VALUES (N'https://api.grants.gov/v1/api/search2'),
           (N'https://api.grants.gov/v1/api/fetchOpportunity')
) AS endpoints (CanonicalUri)
WHERE sources.ProviderCode = N'grants-gov';
GO

/* Retention is snapshotted on every durable acquisition artifact. Existing
   observations receive a conservative 90-day fallback if their legacy source
   did not yet have an explicit policy. Hashes and provenance survive redaction. */
DISABLE TRIGGER dbo.FundingPlatform_tr_RawFundingOpportunities_Immutable
    ON dbo.FundingPlatform_RawFundingOpportunities;

ALTER TABLE dbo.FundingPlatform_RawFundingOpportunities ADD
    ContentRetentionDays SMALLINT NULL,
    AcquisitionPolicyVersion INT NULL,
    RetentionUntilUtc DATETIME2(3) NULL,
    IsContentRedacted BIT NOT NULL
        CONSTRAINT FundingPlatform_DF_RawFundingOpportunities_Redacted DEFAULT (0),
    RedactedAtUtc DATETIME2(3) NULL;
GO

UPDATE raw
SET ContentRetentionDays = COALESCE(sources.ContentRetentionDays, CONVERT(SMALLINT, 90)),
    AcquisitionPolicyVersion = sources.AcquisitionPolicyVersion,
    RetentionUntilUtc = DATEADD
        (DAY, COALESCE(sources.ContentRetentionDays, CONVERT(SMALLINT, 90)), raw.CreatedAtUtc)
FROM dbo.FundingPlatform_RawFundingOpportunities AS raw
INNER JOIN dbo.FundingPlatform_FundingSources AS sources ON sources.Id = raw.FundingSourceId;

ALTER TABLE dbo.FundingPlatform_RawFundingOpportunities
    ALTER COLUMN ContentRetentionDays SMALLINT NOT NULL;
ALTER TABLE dbo.FundingPlatform_RawFundingOpportunities
    ALTER COLUMN AcquisitionPolicyVersion INT NOT NULL;
ALTER TABLE dbo.FundingPlatform_RawFundingOpportunities
    ALTER COLUMN RetentionUntilUtc DATETIME2(3) NOT NULL;

ALTER TABLE dbo.FundingPlatform_RawFundingOpportunities WITH CHECK
    ADD CONSTRAINT FundingPlatform_CK_RawFundingOpportunities_Retention
        CHECK (ContentRetentionDays BETWEEN 1 AND 3650
               AND AcquisitionPolicyVersion >= 1
               AND RetentionUntilUtc > CreatedAtUtc
               AND ((IsContentRedacted = 0 AND RedactedAtUtc IS NULL)
                    OR (IsContentRedacted = 1
                        AND RawContent = N'{"redacted":true}'
                        AND RedactedAtUtc >= RetentionUntilUtc)));

ALTER TABLE dbo.FundingPlatform_RawFundingOpportunities WITH CHECK
    ADD CONSTRAINT FundingPlatform_FK_RawFundingOpportunities_PolicyVersion
        FOREIGN KEY (FundingSourceId, AcquisitionPolicyVersion)
        REFERENCES dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions
            (FundingSourceId, PolicyVersion);

ALTER TABLE dbo.FundingPlatform_ImportRunItems ADD
    ContentRetentionDays SMALLINT NULL,
    AcquisitionPolicyVersion INT NULL,
    RetentionUntilUtc DATETIME2(3) NULL,
    IsContentRedacted BIT NOT NULL
        CONSTRAINT FundingPlatform_DF_ImportRunItems_Redacted DEFAULT (0),
    RedactedAtUtc DATETIME2(3) NULL;
GO

UPDATE items
SET ContentRetentionDays = raw.ContentRetentionDays,
    AcquisitionPolicyVersion = raw.AcquisitionPolicyVersion,
    RetentionUntilUtc = raw.RetentionUntilUtc
FROM dbo.FundingPlatform_ImportRunItems AS items
INNER JOIN dbo.FundingPlatform_RawFundingOpportunities AS raw
    ON raw.Id = items.RawFundingOpportunityId;

ALTER TABLE dbo.FundingPlatform_ImportRunItems
    ALTER COLUMN ContentRetentionDays SMALLINT NOT NULL;
ALTER TABLE dbo.FundingPlatform_ImportRunItems
    ALTER COLUMN AcquisitionPolicyVersion INT NOT NULL;
ALTER TABLE dbo.FundingPlatform_ImportRunItems
    ALTER COLUMN RetentionUntilUtc DATETIME2(3) NOT NULL;

ALTER TABLE dbo.FundingPlatform_ImportRunItems WITH CHECK
    ADD CONSTRAINT FundingPlatform_CK_ImportRunItems_Retention
        CHECK (ContentRetentionDays BETWEEN 1 AND 3650
               AND AcquisitionPolicyVersion >= 1
               AND RetentionUntilUtc > CreatedAtUtc
               AND ((IsContentRedacted = 0 AND RedactedAtUtc IS NULL)
                    OR (IsContentRedacted = 1
                        AND JSON_VALUE(NormalizedSnapshotJson, N'$.opportunity.redacted') = N'true'
                        AND RedactedAtUtc >= RetentionUntilUtc)));

ALTER TABLE dbo.FundingPlatform_ImportRunItems WITH CHECK
    ADD CONSTRAINT FundingPlatform_FK_ImportRunItems_PolicyVersion
        FOREIGN KEY (FundingSourceId, AcquisitionPolicyVersion)
        REFERENCES dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions
            (FundingSourceId, PolicyVersion);

ALTER TABLE dbo.FundingPlatform_ImportRuns ADD
    ContentRetentionDaysSnapshot SMALLINT NULL,
    AcquisitionPolicyVersionSnapshot INT NULL,
    AcquisitionPolicyFingerprintSnapshot BINARY(32) NULL;
GO

ALTER TABLE dbo.FundingPlatform_ImportRuns WITH CHECK
    ADD CONSTRAINT FundingPlatform_CK_ImportRuns_RetentionSnapshot
        CHECK ((ContentRetentionDaysSnapshot IS NULL
                AND AcquisitionPolicyVersionSnapshot IS NULL
                AND AcquisitionPolicyFingerprintSnapshot IS NULL)
               OR (ContentRetentionDaysSnapshot BETWEEN 1 AND 3650
                   AND AcquisitionPolicyVersionSnapshot >= 1
                   AND AcquisitionPolicyFingerprintSnapshot IS NOT NULL));

ALTER TABLE dbo.FundingPlatform_ImportRuns WITH CHECK
    ADD CONSTRAINT FundingPlatform_FK_ImportRuns_PolicyVersion
        FOREIGN KEY (FundingSourceId, AcquisitionPolicyVersionSnapshot)
        REFERENCES dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions
            (FundingSourceId, PolicyVersion);
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_RawFundingOpportunities_Immutable
ON dbo.FundingPlatform_RawFundingOpportunities
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM deleted WHERE NOT EXISTS
               (SELECT 1 FROM inserted WHERE inserted.Id = deleted.Id))
        THROW 51730, N'Raw funding observations cannot be deleted.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM inserted
        INNER JOIN deleted ON deleted.Id = inserted.Id
        WHERE NOT
        (
            deleted.IsContentRedacted = 0 AND inserted.IsContentRedacted = 1
            AND deleted.RedactedAtUtc IS NULL
            AND inserted.RawContent = N'{"redacted":true}'
            AND inserted.RedactedAtUtc IS NOT NULL
            AND inserted.RedactedAtUtc >= inserted.RetentionUntilUtc
            AND inserted.PublicId = deleted.PublicId
            AND inserted.FundingSourceId = deleted.FundingSourceId
            AND inserted.ExternalId = deleted.ExternalId
            AND inserted.SourceItemKeyHash = deleted.SourceItemKeyHash
            AND inserted.ContentHash = deleted.ContentHash
            AND inserted.SourceUrl = deleted.SourceUrl
            AND inserted.MimeType = deleted.MimeType
            AND inserted.RetrievedAtUtc = deleted.RetrievedAtUtc
            AND inserted.CreatedAtUtc = deleted.CreatedAtUtc
            AND inserted.ContentRetentionDays = deleted.ContentRetentionDays
            AND inserted.AcquisitionPolicyVersion = deleted.AcquisitionPolicyVersion
            AND inserted.RetentionUntilUtc = deleted.RetentionUntilUtc
        )
    )
        THROW 51730, N'Raw funding observations are immutable except for due retention redaction.', 1;
END;
GO

/* The run's first successful claim freezes the retention policy. Recording an
   observation therefore cannot silently adopt a later or weaker source policy. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_RawFundingOpportunity_Record
    @RunPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @ExternalId NVARCHAR(250),
    @SourceUrl NVARCHAR(2048),
    @RetrievedAtUtc DATETIME2(3),
    @MimeType NVARCHAR(100),
    @RawContent NVARCHAR(MAX),
    @ContentHash BINARY(32),
    @SourceItemKeyHash BINARY(32),
    @NormalizedSnapshotVersion SMALLINT,
    @NormalizedSnapshotJson NVARCHAR(MAX),
    @NormalizedSnapshotHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ExternalId = LTRIM(RTRIM(@ExternalId));
    SET @SourceUrl = LTRIM(RTRIM(@SourceUrl));
    SET @MimeType = LOWER(LTRIM(RTRIM(@MimeType)));

    IF NULLIF(@ExternalId, N'') IS NULL OR LEN(@ExternalId) > 250
        THROW 51850, N'ExternalId is required and cannot exceed 250 characters.', 1;
    IF NULLIF(@SourceUrl, N'') IS NULL OR LEN(@SourceUrl) > 2048
       OR CHARINDEX(CHAR(10), @SourceUrl) > 0 OR CHARINDEX(CHAR(13), @SourceUrl) > 0
        THROW 51851, N'SourceUrl is required, bounded and single-line.', 1;
    IF NULLIF(@MimeType, N'') IS NULL OR LEN(@MimeType) > 100
        THROW 51852, N'MimeType is required and cannot exceed 100 characters.', 1;
    IF @RawContent IS NULL OR DATALENGTH(@RawContent) NOT BETWEEN 2 AND 4194304
        THROW 51853, N'RawContent size is outside the allowed range.', 1;
    IF @MimeType = N'application/json' AND ISJSON(@RawContent) <> 1
        THROW 51854, N'RawContent must be valid JSON for application/json.', 1;
    IF @ContentHash IS NULL OR @SourceItemKeyHash IS NULL
        THROW 51855, N'Content and source-item hashes are required.', 1;
    IF HASHBYTES
       ('SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
          @RawContent COLLATE Latin1_General_100_BIN2_UTF8))) <> @ContentHash
        THROW 51856, N'Raw content hash does not match its content.', 1;
    IF @NormalizedSnapshotVersion <> 1 OR @NormalizedSnapshotJson IS NULL
       OR ISJSON(@NormalizedSnapshotJson) <> 1
       OR COALESCE(TRY_CONVERT(SMALLINT,
          JSON_VALUE(@NormalizedSnapshotJson, N'$.schemaVersion')), -1) <> 1
       OR COALESCE(LEFT(LTRIM(JSON_QUERY
          (@NormalizedSnapshotJson, N'$.opportunity')), 1), N'') <> N'{'
       OR DATALENGTH(CONVERT(VARCHAR(MAX),
          @NormalizedSnapshotJson COLLATE Latin1_General_100_BIN2_UTF8))
          NOT BETWEEN 2 AND 262144 OR @NormalizedSnapshotHash IS NULL
        THROW 51857, N'Normalized snapshot is invalid or outside the allowed range.', 1;
    IF HASHBYTES
       ('SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
          @NormalizedSnapshotJson COLLATE Latin1_General_100_BIN2_UTF8)))
       <> @NormalizedSnapshotHash
        THROW 51858, N'Normalized snapshot hash does not match its content.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @RunId BIGINT, @FundingSourceId INT, @RunStatus TINYINT;
    DECLARE @CurrentLeaseId UNIQUEIDENTIFIER, @LeaseUntilUtc DATETIME2(3);
    DECLARE @RetrievedCount INT, @MaximumResults INT;
    DECLARE @RetentionDays SMALLINT, @PolicyVersion INT;
    DECLARE @RawId BIGINT, @RawPublicId UNIQUEIDENTIFIER, @ExistingRawHash BINARY(32);
    DECLARE @ItemId BIGINT, @ItemPublicId UNIQUEIDENTIFIER, @ItemStatus TINYINT;
    DECLARE @ExistingSnapshotVersion SMALLINT, @ExistingSnapshotHash BINARY(32);
    DECLARE @WasRawReplay BIT = 0, @AlreadyCompleted BIT = 0;
    DECLARE @Succeeded BIT = 0, @Code NVARCHAR(50) = N'not-found';
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_RawRecord7B;

    BEGIN TRY
        SELECT @RunId = Id, @FundingSourceId = FundingSourceId, @RunStatus = Status,
               @CurrentLeaseId = LeaseId, @LeaseUntilUtc = LeaseUntilUtc,
               @RetrievedCount = RetrievedCount, @MaximumResults = MaximumResults,
               @RetentionDays = ContentRetentionDaysSnapshot,
               @PolicyVersion = AcquisitionPolicyVersionSnapshot
        FROM dbo.FundingPlatform_ImportRuns WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @RunPublicId;

        IF @RunId IS NULL SET @Code = N'not-found';
        ELSE IF @RunStatus <> 1 SET @Code = N'invalid-state';
        ELSE IF @CurrentLeaseId <> @LeaseId OR @LeaseUntilUtc <= @NowUtc
            SET @Code = N'stale-lease';
        ELSE IF @RetentionDays IS NULL OR @PolicyVersion IS NULL
            SET @Code = N'retention-policy-required';
        ELSE IF @RetrievedAtUtc < DATEADD(DAY, -30, @NowUtc)
             OR @RetrievedAtUtc > DATEADD(MINUTE, 5, @NowUtc)
            SET @Code = N'invalid-retrieval-time';
        ELSE
        BEGIN
            SELECT @ItemId = items.Id, @ItemPublicId = items.PublicId,
                   @ItemStatus = items.Status, @RawId = raw.Id,
                   @RawPublicId = raw.PublicId, @ExistingRawHash = raw.ContentHash,
                   @ExistingSnapshotVersion = items.NormalizedSnapshotVersion,
                   @ExistingSnapshotHash = items.NormalizedSnapshotHash
            FROM dbo.FundingPlatform_ImportRunItems AS items WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.FundingPlatform_RawFundingOpportunities AS raw WITH (HOLDLOCK)
                ON raw.Id = items.RawFundingOpportunityId
            WHERE items.ImportRunId = @RunId
              AND items.SourceItemKeyHash = @SourceItemKeyHash;

            IF @ItemId IS NOT NULL
            BEGIN
                IF @ItemStatus IN (2, 3)
                BEGIN
                    SET @Succeeded = 1; SET @Code = N'replayed';
                    SET @WasRawReplay = 1; SET @AlreadyCompleted = 1;
                END
                ELSE IF @ExistingRawHash <> @ContentHash
                     OR @ExistingSnapshotVersion <> @NormalizedSnapshotVersion
                     OR @ExistingSnapshotHash <> @NormalizedSnapshotHash
                BEGIN
                    SET @ItemPublicId = NULL; SET @RawPublicId = NULL;
                    SET @Code = N'item-conflict';
                END
                ELSE
                BEGIN
                    SET @Succeeded = 1; SET @Code = N'replayed';
                    SET @WasRawReplay = 1;
                END;
            END
            ELSE IF @RetrievedCount >= @MaximumResults
                SET @Code = N'maximum-results-reached';
            ELSE
            BEGIN
                SELECT @RawId = Id, @RawPublicId = PublicId
                FROM dbo.FundingPlatform_RawFundingOpportunities WITH (UPDLOCK, HOLDLOCK)
                WHERE FundingSourceId = @FundingSourceId
                  AND SourceItemKeyHash = @SourceItemKeyHash
                  AND ContentHash = @ContentHash;

                IF @RawId IS NULL
                BEGIN
                    DECLARE @InsertedRaw TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER);
                    INSERT INTO dbo.FundingPlatform_RawFundingOpportunities
                        (FundingSourceId, ExternalId, SourceItemKeyHash, ContentHash,
                         SourceUrl, MimeType, RawContent, RetrievedAtUtc,
                         ContentRetentionDays, AcquisitionPolicyVersion,
                         RetentionUntilUtc, CreatedAtUtc)
                    OUTPUT inserted.Id, inserted.PublicId INTO @InsertedRaw (Id, PublicId)
                    VALUES (@FundingSourceId, @ExternalId, @SourceItemKeyHash, @ContentHash,
                            @SourceUrl, @MimeType, @RawContent, @RetrievedAtUtc,
                            @RetentionDays, @PolicyVersion,
                            DATEADD(DAY, @RetentionDays, @NowUtc), @NowUtc);
                    SELECT @RawId = Id, @RawPublicId = PublicId FROM @InsertedRaw;
                END
                ELSE SET @WasRawReplay = 1;

                DECLARE @InsertedItem TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER);
                INSERT INTO dbo.FundingPlatform_ImportRunItems
                    (ImportRunId, FundingSourceId, RawFundingOpportunityId,
                     FundingOpportunityId, ExternalId, SourceItemKeyHash,
                     NormalizedSnapshotVersion, NormalizedSnapshotJson,
                     NormalizedSnapshotHash, Status, OutcomeCode,
                     ContentRetentionDays, AcquisitionPolicyVersion, RetentionUntilUtc,
                     CreatedAtUtc, CompletedAtUtc, UpdatedAtUtc)
                OUTPUT inserted.Id, inserted.PublicId INTO @InsertedItem (Id, PublicId)
                VALUES (@RunId, @FundingSourceId, @RawId, NULL, @ExternalId,
                        @SourceItemKeyHash, @NormalizedSnapshotVersion,
                        @NormalizedSnapshotJson, @NormalizedSnapshotHash,
                        1, NULL, @RetentionDays, @PolicyVersion,
                        DATEADD(DAY, @RetentionDays, @NowUtc), @NowUtc, NULL, @NowUtc);
                SELECT @ItemId = Id, @ItemPublicId = PublicId FROM @InsertedItem;

                UPDATE dbo.FundingPlatform_ImportRuns
                SET RetrievedCount = RetrievedCount + 1, UpdatedAtUtc = @NowUtc
                WHERE Id = @RunId;
                SET @Succeeded = 1; SET @Code = N'recorded';
            END;
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_RawRecord7B;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @ItemPublicId AS ItemPublicId, @RawPublicId AS RawObservationPublicId,
           @WasRawReplay AS WasRawReplay, @AlreadyCompleted AS AlreadyCompleted;
END;
GO

ENABLE TRIGGER dbo.FundingPlatform_tr_RawFundingOpportunities_Immutable
    ON dbo.FundingPlatform_RawFundingOpportunities;
GO

CREATE TABLE dbo.FundingPlatform_ContentRetentionRuns
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_ContentRetentionRuns_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    CutoffUtc DATETIME2(3) NOT NULL,
    RawRedactedCount INT NOT NULL,
    ItemRedactedCount INT NOT NULL,
    ResultRedactedCount INT NOT NULL,
    EvidenceRedactedCount INT NOT NULL,
    StartedAtUtc DATETIME2(3) NOT NULL,
    CompletedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_ContentRetentionRuns PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_ContentRetentionRuns_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_CK_ContentRetentionRuns_Counts
        CHECK (RawRedactedCount >= 0 AND ItemRedactedCount >= 0
               AND ResultRedactedCount >= 0 AND EvidenceRedactedCount >= 0),
    CONSTRAINT FundingPlatform_CK_ContentRetentionRuns_Time
        CHECK (CompletedAtUtc >= StartedAtUtc AND CutoffUtc <= CompletedAtUtc)
);
GO

/* The PDF has its own durable retention lease. Blob identity is preserved as
   provenance; the worker requests conditional deletion of every visible blob
   version. Azure soft-delete/lifecycle controls final physical reclamation. */
ALTER TABLE dbo.FundingPlatform_SourceDocuments ADD
    ContentRetentionDays SMALLINT NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocuments_RetentionDays DEFAULT (90),
    AcquisitionPolicyVersion INT NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocuments_PolicyVersion DEFAULT (1),
    RetentionUntilUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocuments_RetentionUntil
        DEFAULT (DATEADD(DAY, 90, SYSUTCDATETIME())),
    ContentRetentionStatus TINYINT NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocuments_RetentionStatus DEFAULT (0),
    ContentRetentionAttemptCount SMALLINT NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocuments_RetentionAttempts DEFAULT (0),
    ContentRetentionMaxAttempts SMALLINT NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocuments_RetentionMaxAttempts DEFAULT (5),
    ContentRetentionNextAttemptAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocuments_RetentionNext
        DEFAULT (SYSUTCDATETIME()),
    ContentRetentionLeaseId UNIQUEIDENTIFIER NULL,
    ContentRetentionLeaseUntilUtc DATETIME2(3) NULL,
    ContentRetentionLastErrorCode NVARCHAR(100) NULL,
    ContentDeletionRequestedAtUtc DATETIME2(3) NULL;
GO

UPDATE documents
SET ContentRetentionDays = policies.ContentRetentionDays,
    AcquisitionPolicyVersion = policies.PolicyVersion,
    RetentionUntilUtc = DATEADD(DAY, policies.ContentRetentionDays, documents.CreatedAtUtc),
    ContentRetentionNextAttemptAtUtc = documents.CreatedAtUtc
FROM dbo.FundingPlatform_SourceDocuments AS documents
INNER JOIN dbo.FundingPlatform_FundingSources AS sources
    ON sources.Id = documents.FundingSourceId
INNER JOIN dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions AS policies
    ON policies.FundingSourceId = sources.Id
   AND policies.PolicyVersion = sources.AcquisitionPolicyVersion;

ALTER TABLE dbo.FundingPlatform_SourceDocuments WITH CHECK
    ADD CONSTRAINT FundingPlatform_CK_SourceDocuments_ContentRetention
        CHECK (ContentRetentionDays BETWEEN 1 AND 3650
               AND AcquisitionPolicyVersion >= 1
               AND RetentionUntilUtc > CreatedAtUtc
               AND ContentRetentionStatus BETWEEN 0 AND 3
               AND ContentRetentionAttemptCount BETWEEN 0 AND ContentRetentionMaxAttempts
               AND ContentRetentionMaxAttempts BETWEEN 1 AND 10
               AND ContentRetentionNextAttemptAtUtc >= CreatedAtUtc
               AND (ContentRetentionLastErrorCode IS NULL
                    OR (NULLIF(LTRIM(RTRIM(ContentRetentionLastErrorCode)), N'') IS NOT NULL
                        AND CHARINDEX(CHAR(10), ContentRetentionLastErrorCode) = 0
                        AND CHARINDEX(CHAR(13), ContentRetentionLastErrorCode) = 0))
               AND ((ContentRetentionStatus = 0
                     AND ContentRetentionLeaseId IS NULL
                     AND ContentRetentionLeaseUntilUtc IS NULL
                     AND ContentDeletionRequestedAtUtc IS NULL)
                    OR (ContentRetentionStatus = 1
                        AND ContentRetentionLeaseId IS NOT NULL
                        AND ContentRetentionLeaseUntilUtc IS NOT NULL
                        AND ContentDeletionRequestedAtUtc IS NULL)
                    OR (ContentRetentionStatus = 2
                        AND ContentRetentionLeaseId IS NULL
                        AND ContentRetentionLeaseUntilUtc IS NULL
                        AND ContentRetentionLastErrorCode IS NULL
                        AND ContentDeletionRequestedAtUtc >= RetentionUntilUtc)
                    OR (ContentRetentionStatus = 3
                        AND ContentRetentionLeaseId IS NULL
                        AND ContentRetentionLeaseUntilUtc IS NULL
                        AND ContentRetentionLastErrorCode IS NOT NULL
                        AND ContentDeletionRequestedAtUtc IS NULL)));

ALTER TABLE dbo.FundingPlatform_SourceDocuments WITH CHECK
    ADD CONSTRAINT FundingPlatform_FK_SourceDocuments_PolicyVersion
        FOREIGN KEY (FundingSourceId, AcquisitionPolicyVersion)
        REFERENCES dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions
            (FundingSourceId, PolicyVersion);

CREATE INDEX FundingPlatform_IX_SourceDocuments_ContentRetentionClaim
    ON dbo.FundingPlatform_SourceDocuments
       (ContentRetentionStatus, ContentRetentionNextAttemptAtUtc,
        RetentionUntilUtc, Id)
    INCLUDE (PublicId, FundingSourceId, ContentRetentionAttemptCount,
             ContentRetentionMaxAttempts, ContentRetentionLeaseUntilUtc,
             BlobContainer, BlobObjectName, BlobETag,
             TrustedBlobContainer, TrustedBlobObjectName, TrustedBlobETag);
GO

/* Replace the FASE 6 completion insert so every new document snapshots the
   active immutable policy version instead of relying on a numeric default. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentUploadIntent_Complete
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @IntentPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @VerifiedMimeType NVARCHAR(100),
    @ActualContentLength BIGINT,
    @ContentHash BINARY(32),
    @ScanProvider TINYINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    SET XACT_ABORT ON;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @ActorUserId BIGINT;
    DECLARE @IntentId BIGINT, @FundingSourceId INT, @OriginalFileName NVARCHAR(260);
    DECLARE @QuarantineBlobContainer NVARCHAR(63), @QuarantineBlobObjectName NVARCHAR(1024);
    DECLARE @ExpectedContentLength BIGINT, @MaxContentLength BIGINT, @UploadedByUserId BIGINT;
    DECLARE @Status TINYINT, @StoredLeaseId UNIQUEIDENTIFIER;
    DECLARE @StoredLeaseUntilUtc DATETIME2(3), @DocumentId BIGINT;
    DECLARE @DocumentPublicId UNIQUEIDENTIFIER, @StorageStatus TINYINT, @ScanStatus TINYINT;
    DECLARE @StoredScanProvider TINYINT, @RowVersion BINARY(8);
    DECLARE @RetentionDays SMALLINT, @PolicyVersion INT, @PolicyId BIGINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;

    IF @LeaseId IS NULL OR LOWER(COALESCE(@VerifiedMimeType, N'')) <> N'application/pdf'
       OR @ActualContentLength NOT BETWEEN 1 AND 26214400
       OR @ContentHash IS NULL OR @ScanProvider NOT BETWEEN 0 AND 1
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               @IntentPublicId AS IntentPublicId,
               CAST(NULL AS UNIQUEIDENTIFIER) AS SourceDocumentPublicId,
               CAST(NULL AS TINYINT) AS StorageStatus,
               CAST(NULL AS TINYINT) AS ScanStatus,
               CAST(NULL AS TINYINT) AS ScanProvider,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_CompleteUpload7B;

    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;

        SELECT @IntentId = intents.Id, @FundingSourceId = intents.FundingSourceId,
               @OriginalFileName = intents.OriginalFileName,
               @QuarantineBlobContainer = intents.QuarantineBlobContainer,
               @QuarantineBlobObjectName = intents.QuarantineBlobObjectName,
               @ExpectedContentLength = intents.ExpectedContentLength,
               @MaxContentLength = intents.MaxContentLength,
               @UploadedByUserId = intents.UploadedByUserId,
               @Status = intents.Status, @StoredLeaseId = intents.FinalizeLeaseId,
               @StoredLeaseUntilUtc = intents.FinalizeLeaseUntilUtc,
               @DocumentId = intents.CompletedSourceDocumentId
        FROM dbo.FundingPlatform_SourceDocumentUploadIntents AS intents
             WITH (UPDLOCK, HOLDLOCK)
        WHERE intents.PublicId = @IntentPublicId;

        IF @FundingSourceId IS NOT NULL
            SELECT @RetentionDays = policies.ContentRetentionDays,
                   @PolicyVersion = policies.PolicyVersion, @PolicyId = policies.Id
            FROM dbo.FundingPlatform_FundingSources AS sources WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions AS policies
                WITH (HOLDLOCK)
                ON policies.FundingSourceId = sources.Id
               AND policies.PolicyVersion = sources.AcquisitionPolicyVersion
            WHERE sources.Id = @FundingSourceId;

        IF @IntentId IS NULL SET @Code = N'not-found';
        ELSE IF @Status = 2
        BEGIN
            SELECT @DocumentPublicId = documents.PublicId,
                   @StorageStatus = documents.StorageStatus,
                   @ScanStatus = documents.ScanStatus,
                   @StoredScanProvider = documents.ScanProvider,
                   @RowVersion = documents.RowVersion
            FROM dbo.FundingPlatform_SourceDocuments AS documents WITH (UPDLOCK, HOLDLOCK)
            WHERE documents.Id = @DocumentId
              AND documents.MimeType = N'application/pdf'
              AND documents.ContentLength = @ActualContentLength
              AND documents.ContentHash = @ContentHash
              AND documents.ScanProvider = @ScanProvider;
            IF @DocumentPublicId IS NULL SET @Code = N'completion-conflict';
            ELSE BEGIN SET @Succeeded = 1; SET @Code = N'completed'; SET @WasReplay = 1; END;
        END
        ELSE IF @Status <> 1 OR @StoredLeaseId <> @LeaseId SET @Code = N'lease-conflict';
        ELSE IF @StoredLeaseUntilUtc <= @NowUtc SET @Code = N'lease-expired';
        ELSE IF @ActualContentLength <> @ExpectedContentLength
             OR @ActualContentLength > @MaxContentLength SET @Code = N'length-mismatch';
        ELSE IF @PolicyId IS NULL OR @RetentionDays IS NULL
            SET @Code = N'retention-policy-required';
        ELSE
        BEGIN
            DECLARE @InsertedDocument TABLE
                (Id BIGINT, PublicId UNIQUEIDENTIFIER, RowVersion BINARY(8));
            INSERT INTO dbo.FundingPlatform_SourceDocuments
                (FundingSourceId, OriginalFileName, MimeType, ContentLength, ContentHash,
                 BlobContainer, BlobObjectName, StorageStatus, ScanStatus, ScanProvider,
                 ScanAttemptCount, ExtractionStatus, UploadedByUserId,
                 ContentRetentionDays, AcquisitionPolicyVersion, RetentionUntilUtc,
                 ContentRetentionStatus, ContentRetentionAttemptCount,
                 ContentRetentionMaxAttempts, ContentRetentionNextAttemptAtUtc,
                 CreatedAtUtc, UpdatedAtUtc)
            OUTPUT inserted.Id, inserted.PublicId, inserted.RowVersion
                INTO @InsertedDocument (Id, PublicId, RowVersion)
            VALUES (@FundingSourceId, @OriginalFileName, N'application/pdf',
                    @ActualContentLength, @ContentHash,
                    @QuarantineBlobContainer, @QuarantineBlobObjectName,
                    0, 0, @ScanProvider, 1, 0, @UploadedByUserId,
                    @RetentionDays, @PolicyVersion,
                    DATEADD(DAY, @RetentionDays, @NowUtc), 0, 0, 5, @NowUtc,
                    @NowUtc, @NowUtc);
            SELECT @DocumentId = Id, @DocumentPublicId = PublicId, @RowVersion = RowVersion
            FROM @InsertedDocument;
            SET @StorageStatus = 0; SET @ScanStatus = 0; SET @StoredScanProvider = @ScanProvider;

            UPDATE dbo.FundingPlatform_SourceDocumentUploadIntents
            SET Status = 2, FinalizeLeaseId = NULL, FinalizeLeaseUntilUtc = NULL,
                CompletedSourceDocumentId = @DocumentId, CompletedAtUtc = @NowUtc,
                LastErrorCode = NULL, UpdatedAtUtc = @NowUtc
            WHERE Id = @IntentId;

            INSERT INTO dbo.FundingPlatform_OutboxMessages
                (MessageType, AggregateType, AggregateId, PayloadJson,
                 OccurredAtUtc, AvailableAtUtc)
            SELECT N'SourceDocumentFinalized', N'SourceDocument',
                   CONVERT(NVARCHAR(100), @DocumentPublicId),
                   (SELECT @DocumentPublicId AS sourceDocumentPublicId,
                           @IntentPublicId AS intentPublicId,
                           @StoredScanProvider AS scanProvider,
                           @StorageStatus AS storageStatus, @ScanStatus AS scanStatus
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
            SET @Succeeded = 1; SET @Code = N'completed';
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_CompleteUpload7B;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, @IntentPublicId AS IntentPublicId,
           @DocumentPublicId AS SourceDocumentPublicId, @StorageStatus AS StorageStatus,
           @ScanStatus AS ScanStatus, @StoredScanProvider AS ScanProvider,
           @RowVersion AS RowVersion, @WasReplay AS WasReplay;
END;
GO

ALTER TABLE dbo.FundingPlatform_SourceDocuments
    DROP CONSTRAINT FundingPlatform_CK_SourceDocuments_Statuses;

ALTER TABLE dbo.FundingPlatform_SourceDocuments WITH CHECK
    ADD CONSTRAINT FundingPlatform_CK_SourceDocuments_Statuses
        CHECK (StorageStatus BETWEEN 0 AND 3
               AND ScanStatus BETWEEN 0 AND 4
               AND ScanProvider BETWEEN 0 AND 1
               AND ExtractionStatus BETWEEN 0 AND 6
               AND ScanAttemptCount BETWEEN 1 AND 100);

ALTER TABLE dbo.FundingPlatform_SourceDocumentScanEvents
    DROP CONSTRAINT FundingPlatform_CK_SourceDocumentScanEvents_Status;

ALTER TABLE dbo.FundingPlatform_SourceDocumentScanEvents WITH CHECK
    ADD CONSTRAINT FundingPlatform_CK_SourceDocumentScanEvents_Status
        CHECK (ScanProvider BETWEEN 0 AND 1
               AND ((FromStatus = 0 AND ToStatus BETWEEN 1 AND 4
                     AND ActorUserId IS NULL
                     AND IdempotencyKeyHash IS NULL AND RequestHash IS NULL)
                    OR (FromStatus = 1 AND ToStatus BETWEEN 2 AND 4
                        AND ActorUserId IS NULL
                        AND IdempotencyKeyHash IS NULL AND RequestHash IS NULL)
                    OR (FromStatus IN (3, 4) AND ToStatus = 0
                        AND ActorUserId IS NOT NULL
                        AND IdempotencyKeyHash IS NOT NULL AND RequestHash IS NOT NULL)));

ALTER TABLE dbo.FundingPlatform_SourceDocumentScanEvents ADD
    RevokedTrustedBlobContainer NVARCHAR(63) NULL,
    RevokedTrustedBlobObjectName NVARCHAR(1024) NULL,
    RevokedTrustedBlobETag NVARCHAR(100) NULL;
GO

ALTER TABLE dbo.FundingPlatform_SourceDocumentScanEvents WITH CHECK
    ADD CONSTRAINT FundingPlatform_CK_SourceDocumentScanEvents_RevokedBlob
        CHECK ((RevokedTrustedBlobContainer IS NULL
                AND RevokedTrustedBlobObjectName IS NULL
                AND RevokedTrustedBlobETag IS NULL)
               OR (FromStatus = 1 AND ToStatus BETWEEN 2 AND 4
                   AND NULLIF(LTRIM(RTRIM(RevokedTrustedBlobContainer)), N'') IS NOT NULL
                   AND NULLIF(LTRIM(RTRIM(RevokedTrustedBlobObjectName)), N'') IS NOT NULL
                   AND NULLIF(LTRIM(RTRIM(RevokedTrustedBlobETag)), N'') IS NOT NULL
                   AND CHARINDEX(N'?', RevokedTrustedBlobObjectName) = 0
                   AND CHARINDEX(N'#', RevokedTrustedBlobObjectName) = 0));
GO

/* ExtractionStatus: 0 not started, 1 queued, 2 running, 3 completed,
   4 completed with warnings, 5 failed, 6 canceled. */
CREATE TABLE dbo.FundingPlatform_SourceDocumentExtractionJobs
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocumentExtractionJobs_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    SourceDocumentId BIGINT NOT NULL,
    FundingSourceId INT NOT NULL,
    Status TINYINT NOT NULL,
    ParserCode NVARCHAR(100) NOT NULL,
    ParserVersion NVARCHAR(50) NOT NULL,
    ParserSettingsHash BINARY(32) NOT NULL,
    MaximumCharacters INT NOT NULL,
    MaximumPages INT NOT NULL,
    MaximumUtf8Bytes INT NOT NULL,
    MaximumStackDepth SMALLINT NOT NULL,
    MaximumBytes INT NOT NULL,
    ContentRetentionDays SMALLINT NOT NULL,
    AcquisitionPolicyVersion INT NOT NULL,
    RetentionUntilUtc DATETIME2(3) NOT NULL,
    ExpectedTrustedBlobETag NVARCHAR(100) NOT NULL,
    ExpectedContentHash BINARY(32) NOT NULL,
    ExpectedContentLength BIGINT NOT NULL,
    AttemptCount SMALLINT NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocumentExtractionJobs_Attempts DEFAULT (0),
    MaxAttempts SMALLINT NOT NULL,
    RetryBaseDelaySeconds INT NOT NULL,
    NextAttemptAtUtc DATETIME2(3) NOT NULL,
    LeaseId UNIQUEIDENTIFIER NULL,
    LeaseUntilUtc DATETIME2(3) NULL,
    LastErrorCode NVARCHAR(100) NULL,
    LastErrorMessage NVARCHAR(1000) NULL,
    RequestedByUserId BIGINT NOT NULL,
    IdempotencyKeyHash BINARY(32) NOT NULL,
    RequestHash BINARY(32) NOT NULL,
    CorrelationId NVARCHAR(100) NOT NULL,
    StartedAtUtc DATETIME2(3) NULL,
    CompletedAtUtc DATETIME2(3) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocumentExtractionJobs_Created DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocumentExtractionJobs_Updated DEFAULT (SYSUTCDATETIME()),
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_SourceDocumentExtractionJobs PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentExtractionJobs_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentExtractionJobs_IdSource
        UNIQUE (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentExtractionJobs_ParserPolicy
        UNIQUE (SourceDocumentId, ParserCode, ParserVersion, ParserSettingsHash),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentExtractionJobs_Idempotency
        UNIQUE (RequestedByUserId, SourceDocumentId, IdempotencyKeyHash),
    CONSTRAINT FundingPlatform_FK_SourceDocumentExtractionJobs_Document
        FOREIGN KEY (SourceDocumentId, FundingSourceId)
        REFERENCES dbo.FundingPlatform_SourceDocuments (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_FK_SourceDocumentExtractionJobs_User
        FOREIGN KEY (RequestedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_SourceDocumentExtractionJobs_Policy
        FOREIGN KEY (FundingSourceId, AcquisitionPolicyVersion)
        REFERENCES dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions
            (FundingSourceId, PolicyVersion),
    CONSTRAINT FundingPlatform_CK_SourceDocumentExtractionJobs_Status
        CHECK (Status BETWEEN 1 AND 6),
    CONSTRAINT FundingPlatform_CK_SourceDocumentExtractionJobs_Parser
        CHECK (NULLIF(LTRIM(RTRIM(ParserCode)), N'') IS NOT NULL
               AND ParserCode = LOWER(ParserCode)
               AND ParserCode NOT LIKE N'%[^-a-z0-9._]%' COLLATE Latin1_General_100_BIN2
               AND NULLIF(LTRIM(RTRIM(ParserVersion)), N'') IS NOT NULL
               AND CHARINDEX(CHAR(10), ParserVersion) = 0
               AND CHARINDEX(CHAR(13), ParserVersion) = 0
               AND MaximumCharacters BETWEEN 1 AND 500000
               AND MaximumPages BETWEEN 1 AND 250
               AND MaximumUtf8Bytes BETWEEN 1024 AND 2097152
               AND MaximumStackDepth BETWEEN 16 AND 128
               AND MaximumBytes BETWEEN 1024 AND 26214400
               AND ContentRetentionDays BETWEEN 1 AND 3650
               AND AcquisitionPolicyVersion >= 1),
    CONSTRAINT FundingPlatform_CK_SourceDocumentExtractionJobs_Attempts
        CHECK (AttemptCount BETWEEN 0 AND MaxAttempts
               AND MaxAttempts BETWEEN 1 AND 10
               AND RetryBaseDelaySeconds BETWEEN 5 AND 3600),
    CONSTRAINT FundingPlatform_CK_SourceDocumentExtractionJobs_State
        CHECK ((Status = 1 AND LeaseId IS NULL AND LeaseUntilUtc IS NULL
                AND CompletedAtUtc IS NULL)
               OR (Status = 2 AND LeaseId IS NOT NULL AND LeaseUntilUtc IS NOT NULL
                   AND StartedAtUtc IS NOT NULL AND CompletedAtUtc IS NULL)
               OR (Status BETWEEN 3 AND 6 AND LeaseId IS NULL AND LeaseUntilUtc IS NULL
                   AND CompletedAtUtc IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_SourceDocumentExtractionJobs_Error
        CHECK ((LastErrorCode IS NULL AND LastErrorMessage IS NULL)
               OR (NULLIF(LTRIM(RTRIM(LastErrorCode)), N'') IS NOT NULL
                   AND NULLIF(LTRIM(RTRIM(LastErrorMessage)), N'') IS NOT NULL
                   AND CHARINDEX(CHAR(10), LastErrorCode) = 0
                   AND CHARINDEX(CHAR(13), LastErrorCode) = 0
                   AND CHARINDEX(CHAR(10), LastErrorMessage) = 0
                   AND CHARINDEX(CHAR(13), LastErrorMessage) = 0)),
    CONSTRAINT FundingPlatform_CK_SourceDocumentExtractionJobs_Correlation
        CHECK (NULLIF(LTRIM(RTRIM(CorrelationId)), N'') IS NOT NULL
               AND CorrelationId = LTRIM(RTRIM(CorrelationId))
               AND CorrelationId COLLATE Latin1_General_100_BIN2
                   NOT LIKE N'%[^-A-Za-z0-9:_.]%' COLLATE Latin1_General_100_BIN2),
    CONSTRAINT FundingPlatform_CK_SourceDocumentExtractionJobs_Time
        CHECK (UpdatedAtUtc >= CreatedAtUtc
               AND NextAttemptAtUtc >= CreatedAtUtc
               AND (StartedAtUtc IS NULL OR StartedAtUtc >= CreatedAtUtc)
               AND (CompletedAtUtc IS NULL OR CompletedAtUtc >= CreatedAtUtc)
               AND RetentionUntilUtc > CreatedAtUtc
               AND (LeaseUntilUtc IS NULL OR LeaseUntilUtc > UpdatedAtUtc))
);

CREATE INDEX FundingPlatform_IX_SourceDocumentExtractionJobs_Claim
    ON dbo.FundingPlatform_SourceDocumentExtractionJobs
       (Status, NextAttemptAtUtc, CreatedAtUtc, Id)
    INCLUDE (PublicId, SourceDocumentId, FundingSourceId, AttemptCount, MaxAttempts, LeaseUntilUtc);

CREATE TABLE dbo.FundingPlatform_SourceDocumentExtractionResults
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocumentExtractionResults_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    ExtractionJobId BIGINT NOT NULL,
    SourceDocumentId BIGINT NOT NULL,
    FundingSourceId INT NOT NULL,
    ParserCode NVARCHAR(100) NOT NULL,
    ParserVersion NVARCHAR(50) NOT NULL,
    ParserSettingsHash BINARY(32) NOT NULL,
    MaximumCharacters INT NOT NULL,
    MaximumPages INT NOT NULL,
    MaximumUtf8Bytes INT NOT NULL,
    MaximumStackDepth SMALLINT NOT NULL,
    MaximumBytes INT NOT NULL,
    ContentRetentionDays SMALLINT NOT NULL,
    AcquisitionPolicyVersion INT NOT NULL,
    RetentionUntilUtc DATETIME2(3) NOT NULL,
    ExtractedText NVARCHAR(MAX) NOT NULL,
    ExtractedTextHash BINARY(32) NOT NULL,
    PageCount INT NOT NULL,
    CharacterCount INT NOT NULL,
    CompletedWithErrors BIT NOT NULL,
    IsContentRedacted BIT NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocumentExtractionResults_Redacted DEFAULT (0),
    RedactedAtUtc DATETIME2(3) NULL,
    IsSecurityRevoked BIT NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocumentExtractionResults_Revoked DEFAULT (0),
    SecurityRevokedAtUtc DATETIME2(3) NULL,
    SecurityRevocationCode NVARCHAR(100) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_SourceDocumentExtractionResults PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentExtractionResults_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentExtractionResults_IdSource
        UNIQUE (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentExtractionResults_Job UNIQUE (ExtractionJobId),
    CONSTRAINT FundingPlatform_FK_SourceDocumentExtractionResults_Job
        FOREIGN KEY (ExtractionJobId, FundingSourceId)
        REFERENCES dbo.FundingPlatform_SourceDocumentExtractionJobs (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_FK_SourceDocumentExtractionResults_Document
        FOREIGN KEY (SourceDocumentId, FundingSourceId)
        REFERENCES dbo.FundingPlatform_SourceDocuments (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_FK_SourceDocumentExtractionResults_Policy
        FOREIGN KEY (FundingSourceId, AcquisitionPolicyVersion)
        REFERENCES dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions
            (FundingSourceId, PolicyVersion),
    CONSTRAINT FundingPlatform_CK_SourceDocumentExtractionResults_Content
        CHECK (CharacterCount BETWEEN 0 AND MaximumCharacters
               AND CharacterCount = DATALENGTH(ExtractedText) / 2
               AND DATALENGTH(CONVERT(VARCHAR(MAX),
                   ExtractedText COLLATE Latin1_General_100_BIN2_UTF8)) <= MaximumUtf8Bytes
               AND MaximumCharacters BETWEEN 1 AND 500000
               AND MaximumUtf8Bytes BETWEEN 1024 AND 2097152
               AND MaximumStackDepth BETWEEN 16 AND 128
               AND MaximumBytes BETWEEN 1024 AND 26214400
               AND ContentRetentionDays BETWEEN 1 AND 3650
               AND AcquisitionPolicyVersion >= 1
               AND RetentionUntilUtc > CreatedAtUtc
               AND ((IsContentRedacted = 0 AND RedactedAtUtc IS NULL)
                    OR (IsContentRedacted = 1 AND ExtractedText = N''
                        AND CharacterCount = 0 AND RedactedAtUtc >= RetentionUntilUtc))
               AND ((IsSecurityRevoked = 0 AND SecurityRevokedAtUtc IS NULL
                      AND SecurityRevocationCode IS NULL)
                    OR (IsSecurityRevoked = 1 AND SecurityRevokedAtUtc IS NOT NULL
                        AND NULLIF(LTRIM(RTRIM(SecurityRevocationCode)), N'') IS NOT NULL))),
    CONSTRAINT FundingPlatform_CK_SourceDocumentExtractionResults_Pages
        CHECK (PageCount BETWEEN 0 AND MaximumPages
               AND MaximumPages BETWEEN 1 AND 250)
);

/* Evidence is written while a valid job lease is held, then attached to the
   immutable completed result. Excerpts are bounded and never treated as HTML. */
CREATE TABLE dbo.FundingPlatform_SourceDocumentExtractionEvidence
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocumentExtractionEvidence_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    ExtractionJobId BIGINT NOT NULL,
    ExtractionResultId BIGINT NULL,
    SourceDocumentId BIGINT NOT NULL,
    FundingSourceId INT NOT NULL,
    Ordinal SMALLINT NOT NULL,
    PageNumber INT NULL,
    StartOffset INT NOT NULL,
    CharacterLength INT NOT NULL,
    Excerpt NVARCHAR(2000) NOT NULL,
    EvidenceHash BINARY(32) NOT NULL,
    ContentRetentionDays SMALLINT NOT NULL,
    AcquisitionPolicyVersion INT NOT NULL,
    RetentionUntilUtc DATETIME2(3) NOT NULL,
    IsContentRedacted BIT NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocumentExtractionEvidence_Redacted DEFAULT (0),
    RedactedAtUtc DATETIME2(3) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_SourceDocumentExtractionEvidence PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentExtractionEvidence_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentExtractionEvidence_Ordinal
        UNIQUE (ExtractionJobId, Ordinal),
    CONSTRAINT FundingPlatform_FK_SourceDocumentExtractionEvidence_Job
        FOREIGN KEY (ExtractionJobId, FundingSourceId)
        REFERENCES dbo.FundingPlatform_SourceDocumentExtractionJobs (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_FK_SourceDocumentExtractionEvidence_Result
        FOREIGN KEY (ExtractionResultId, FundingSourceId)
        REFERENCES dbo.FundingPlatform_SourceDocumentExtractionResults (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_FK_SourceDocumentExtractionEvidence_Document
        FOREIGN KEY (SourceDocumentId, FundingSourceId)
        REFERENCES dbo.FundingPlatform_SourceDocuments (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_FK_SourceDocumentExtractionEvidence_Policy
        FOREIGN KEY (FundingSourceId, AcquisitionPolicyVersion)
        REFERENCES dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions
            (FundingSourceId, PolicyVersion),
    CONSTRAINT FundingPlatform_CK_SourceDocumentExtractionEvidence_Locator
        CHECK (Ordinal BETWEEN 1 AND 500
               AND (PageNumber IS NULL OR PageNumber BETWEEN 1 AND 250)
               AND StartOffset BETWEEN 0 AND 500000
               AND CharacterLength BETWEEN 1 AND 2000
               AND StartOffset + CharacterLength <= 500000
               AND DATALENGTH(Excerpt) / 2 BETWEEN 1 AND 2000
               AND ContentRetentionDays BETWEEN 1 AND 3650
               AND AcquisitionPolicyVersion >= 1
               AND RetentionUntilUtc > CreatedAtUtc
               AND ((IsContentRedacted = 0 AND RedactedAtUtc IS NULL)
                    OR (IsContentRedacted = 1 AND Excerpt = N'[redacted]'
                        AND RedactedAtUtc >= RetentionUntilUtc)))
);

CREATE INDEX FundingPlatform_IX_SourceDocumentExtractionEvidence_Result
    ON dbo.FundingPlatform_SourceDocumentExtractionEvidence
       (ExtractionResultId, Ordinal, Id)
    INCLUDE (PublicId, PageNumber, StartOffset, CharacterLength);

CREATE TABLE dbo.FundingPlatform_SourceDocumentExtractionErrors
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocumentExtractionErrors_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    ExtractionJobId BIGINT NOT NULL,
    FundingSourceId INT NOT NULL,
    Stage NVARCHAR(50) NOT NULL,
    ErrorCode NVARCHAR(100) NOT NULL,
    SanitizedMessage NVARCHAR(1000) NOT NULL,
    IsRetryable BIT NOT NULL,
    OccurredAtUtc DATETIME2(3) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_SourceDocumentExtractionErrors PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentExtractionErrors_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_FK_SourceDocumentExtractionErrors_Job
        FOREIGN KEY (ExtractionJobId, FundingSourceId)
        REFERENCES dbo.FundingPlatform_SourceDocumentExtractionJobs (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_CK_SourceDocumentExtractionErrors_Fields
        CHECK (NULLIF(LTRIM(RTRIM(Stage)), N'') IS NOT NULL
               AND NULLIF(LTRIM(RTRIM(ErrorCode)), N'') IS NOT NULL
               AND NULLIF(LTRIM(RTRIM(SanitizedMessage)), N'') IS NOT NULL
               AND CHARINDEX(CHAR(10), Stage + ErrorCode + SanitizedMessage) = 0
               AND CHARINDEX(CHAR(13), Stage + ErrorCode + SanitizedMessage) = 0),
    CONSTRAINT FundingPlatform_CK_SourceDocumentExtractionErrors_Time
        CHECK (OccurredAtUtc >= DATEADD(DAY, -30, CreatedAtUtc)
               AND OccurredAtUtc <= DATEADD(MINUTE, 5, CreatedAtUtc))
);

CREATE INDEX FundingPlatform_IX_SourceDocumentExtractionErrors_Job
    ON dbo.FundingPlatform_SourceDocumentExtractionErrors (ExtractionJobId, OccurredAtUtc, Id)
    INCLUDE (PublicId, Stage, ErrorCode, IsRetryable);
GO

/* Azure identity identifiers are not credentials. No token, signature, raw
   Event Grid payload, malware name or SAS URI is persisted. */
CREATE TABLE dbo.FundingPlatform_EventIngressTrustPolicies
(
    Id INT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_EventIngressTrustPolicies_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    Provider TINYINT NOT NULL,
    TenantId UNIQUEIDENTIFIER NOT NULL,
    PrincipalObjectId UNIQUEIDENTIFIER NOT NULL,
    ApplicationClientId UNIQUEIDENTIFIER NOT NULL,
    TopicResourceId NVARCHAR(500) NOT NULL,
    EventSubscriptionName NVARCHAR(100) NOT NULL,
    StorageAccountResourceId NVARCHAR(500) NOT NULL,
    StorageAccountHost NVARCHAR(253) NOT NULL,
    QuarantineBlobContainer NVARCHAR(63) NOT NULL,
    IsEnabled BIT NOT NULL,
    ValidFromUtc DATETIME2(3) NOT NULL,
    ExpiresAtUtc DATETIME2(3) NULL,
    CreatedByUserId BIGINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_EventIngressTrustPolicies_Created DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_EventIngressTrustPolicies_Updated DEFAULT (SYSUTCDATETIME()),
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_EventIngressTrustPolicies PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_EventIngressTrustPolicies_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_EventIngressTrustPolicies_Identity
        UNIQUE (Provider, TenantId, PrincipalObjectId, ApplicationClientId, TopicResourceId,
                StorageAccountResourceId),
    CONSTRAINT FundingPlatform_FK_EventIngressTrustPolicies_User
        FOREIGN KEY (CreatedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_EventIngressTrustPolicies_Provider
        CHECK (Provider = 1),
    CONSTRAINT FundingPlatform_CK_EventIngressTrustPolicies_Topic
        CHECK (TopicResourceId = LOWER(LTRIM(RTRIM(TopicResourceId)))
               AND LEN(TopicResourceId) BETWEEN 1 AND 500
               AND (TopicResourceId LIKE N'/subscriptions/%/resourcegroups/%/providers/microsoft.eventgrid/topics/%'
                    OR TopicResourceId LIKE N'/subscriptions/%/resourcegroups/%/providers/microsoft.eventgrid/systemtopics/%')
               AND CHARINDEX(N'?', TopicResourceId) = 0
               AND CHARINDEX(N'#', TopicResourceId) = 0
               AND CHARINDEX(CHAR(10), TopicResourceId) = 0
               AND CHARINDEX(CHAR(13), TopicResourceId) = 0
               AND CHARINDEX(0x0000, CONVERT(VARBINARY(1000), TopicResourceId)) = 0),
    CONSTRAINT FundingPlatform_CK_EventIngressTrustPolicies_Subscription
        CHECK (NULLIF(LTRIM(RTRIM(EventSubscriptionName)), N'') IS NOT NULL
               AND LEN(EventSubscriptionName) <= 100
               AND CHARINDEX(CHAR(10), EventSubscriptionName) = 0
               AND CHARINDEX(CHAR(13), EventSubscriptionName) = 0
               AND CHARINDEX(0x0000, CONVERT(VARBINARY(200), EventSubscriptionName)) = 0),
    CONSTRAINT FundingPlatform_CK_EventIngressTrustPolicies_Storage
        CHECK (StorageAccountResourceId = LOWER(LTRIM(RTRIM(StorageAccountResourceId)))
               AND LEN(StorageAccountResourceId) BETWEEN 1 AND 500
               AND StorageAccountResourceId LIKE N'/subscriptions/%/resourcegroups/%/providers/microsoft.storage/storageaccounts/%'
               AND CHARINDEX(N'?', StorageAccountResourceId) = 0
               AND CHARINDEX(N'#', StorageAccountResourceId) = 0
               AND CHARINDEX(CHAR(10), StorageAccountResourceId) = 0
               AND CHARINDEX(CHAR(13), StorageAccountResourceId) = 0
               AND CHARINDEX(0x0000, CONVERT(VARBINARY(1000), StorageAccountResourceId)) = 0
               AND StorageAccountHost = LOWER(LTRIM(RTRIM(StorageAccountHost)))
               AND LEN(StorageAccountHost) BETWEEN 1 AND 253
               AND StorageAccountHost LIKE N'%.blob.core.windows.net'
               AND StorageAccountHost NOT LIKE N'%[^-a-z0-9.]%' COLLATE Latin1_General_100_BIN2
               AND CHARINDEX(0x0000, CONVERT(VARBINARY(506), StorageAccountHost)) = 0
               AND StorageAccountHost =
                   RIGHT(StorageAccountResourceId,
                         NULLIF(CHARINDEX(N'/', REVERSE(StorageAccountResourceId)), 0) - 1)
                   + N'.blob.core.windows.net'
               AND LEN(QuarantineBlobContainer) BETWEEN 3 AND 63
               AND QuarantineBlobContainer = LOWER(QuarantineBlobContainer)
               AND QuarantineBlobContainer NOT LIKE N'%[^-a-z0-9]%' COLLATE Latin1_General_100_BIN2),
    CONSTRAINT FundingPlatform_CK_EventIngressTrustPolicies_Time
        CHECK (UpdatedAtUtc >= CreatedAtUtc
               AND ValidFromUtc >= DATEADD(DAY, -1, CreatedAtUtc)
               AND (ExpiresAtUtc IS NULL OR ExpiresAtUtc > ValidFromUtc))
);

CREATE INDEX FundingPlatform_IX_EventIngressTrustPolicies_Resolve
    ON dbo.FundingPlatform_EventIngressTrustPolicies
       (Provider, TenantId, PrincipalObjectId, IsEnabled, ValidFromUtc, ExpiresAtUtc)
    INCLUDE (ApplicationClientId, TopicResourceId, EventSubscriptionName,
             StorageAccountResourceId, StorageAccountHost, QuarantineBlobContainer, PublicId);

CREATE TABLE dbo.FundingPlatform_EventIngressTrustPolicyEvents
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_EventIngressTrustPolicyEvents_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    TrustPolicyId INT NOT NULL,
    ActorUserId BIGINT NOT NULL,
    Action TINYINT NOT NULL,
    Reason NVARCHAR(500) NOT NULL,
    CorrelationId NVARCHAR(100) NOT NULL,
    IdempotencyKeyHash BINARY(32) NOT NULL,
    RequestHash BINARY(32) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_EventIngressTrustPolicyEvents PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_EventIngressTrustPolicyEvents_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_EventIngressTrustPolicyEvents_Idempotency
        UNIQUE (ActorUserId, IdempotencyKeyHash),
    CONSTRAINT FundingPlatform_FK_EventIngressTrustPolicyEvents_Policy
        FOREIGN KEY (TrustPolicyId) REFERENCES dbo.FundingPlatform_EventIngressTrustPolicies (Id),
    CONSTRAINT FundingPlatform_FK_EventIngressTrustPolicyEvents_Actor
        FOREIGN KEY (ActorUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_EventIngressTrustPolicyEvents_Action CHECK (Action IN (1, 2)),
    CONSTRAINT FundingPlatform_CK_EventIngressTrustPolicyEvents_Reason
        CHECK (NULLIF(LTRIM(RTRIM(Reason)), N'') IS NOT NULL
               AND CHARINDEX(CHAR(10), Reason) = 0
               AND CHARINDEX(CHAR(13), Reason) = 0
               AND NULLIF(LTRIM(RTRIM(CorrelationId)), N'') IS NOT NULL
               AND CorrelationId COLLATE Latin1_General_100_BIN2
                   NOT LIKE N'%[^-A-Za-z0-9:_.]%' COLLATE Latin1_General_100_BIN2)
);

/* ReceiptStatus: 0 accepted, 1 applied, 2 ignored, 3 rejected. Only events
   which matched an enabled trust policy can enter this table. */
CREATE TABLE dbo.FundingPlatform_SourceDocumentDefenderReceipts
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocumentDefenderReceipts_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    TrustPolicyId INT NOT NULL,
    SourceDocumentId BIGINT NULL,
    Provider TINYINT NOT NULL,
    ProviderEventId NVARCHAR(200) NOT NULL,
    PayloadHash BINARY(32) NOT NULL,
    TopicResourceId NVARCHAR(500) NOT NULL,
    AuthenticatedTenantId UNIQUEIDENTIFIER NOT NULL,
    AuthenticatedPrincipalId UNIQUEIDENTIFIER NOT NULL,
    ApplicationClientId UNIQUEIDENTIFIER NOT NULL,
    EventSubscriptionName NVARCHAR(100) NOT NULL,
    StorageAccountResourceId NVARCHAR(500) NOT NULL,
    BlobHost NVARCHAR(253) NOT NULL,
    BlobContainer NVARCHAR(63) NOT NULL,
    BlobObjectName NVARCHAR(1024) NOT NULL,
    BlobETag NVARCHAR(100) NOT NULL,
    ReportedContentHash BINARY(32) NULL,
    ToStatus TINYINT NOT NULL,
    ResultCode NVARCHAR(100) NOT NULL,
    ReceiptStatus TINYINT NOT NULL,
    OutcomeCode NVARCHAR(100) NULL,
    OccurredAtUtc DATETIME2(3) NOT NULL,
    ReceivedAtUtc DATETIME2(3) NOT NULL,
    FinalizedAtUtc DATETIME2(3) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_SourceDocumentDefenderReceipts PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentDefenderReceipts_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentDefenderReceipts_ProviderEvent
        UNIQUE (Provider, ProviderEventId),
    CONSTRAINT FundingPlatform_FK_SourceDocumentDefenderReceipts_Policy
        FOREIGN KEY (TrustPolicyId) REFERENCES dbo.FundingPlatform_EventIngressTrustPolicies (Id),
    CONSTRAINT FundingPlatform_FK_SourceDocumentDefenderReceipts_Document
        FOREIGN KEY (SourceDocumentId) REFERENCES dbo.FundingPlatform_SourceDocuments (Id),
    CONSTRAINT FundingPlatform_CK_SourceDocumentDefenderReceipts_Provider
        CHECK (Provider = 1),
    CONSTRAINT FundingPlatform_CK_SourceDocumentDefenderReceipts_Blob
        CHECK (BlobHost = LOWER(LTRIM(RTRIM(BlobHost)))
               AND BlobHost LIKE N'%.blob.core.windows.net'
               AND BlobHost NOT LIKE N'%[^-a-z0-9.]%' COLLATE Latin1_General_100_BIN2
               AND LEN(BlobContainer) BETWEEN 3 AND 63
               AND LEN(BlobObjectName) BETWEEN 1 AND 1024
               AND LEFT(BlobObjectName, 1) <> N'/'
               AND CHARINDEX(N'?', BlobObjectName) = 0
               AND CHARINDEX(N'#', BlobObjectName) = 0
               AND NULLIF(LTRIM(RTRIM(BlobETag)), N'') IS NOT NULL),
    CONSTRAINT FundingPlatform_CK_SourceDocumentDefenderReceipts_Result
        CHECK (ToStatus BETWEEN 1 AND 4
               AND (ToStatus NOT IN (1, 2) OR ReportedContentHash IS NOT NULL)
               AND NULLIF(LTRIM(RTRIM(ResultCode)), N'') IS NOT NULL
               AND CHARINDEX(CHAR(10), ResultCode) = 0
               AND CHARINDEX(CHAR(13), ResultCode) = 0),
    CONSTRAINT FundingPlatform_CK_SourceDocumentDefenderReceipts_State
        CHECK ((ReceiptStatus = 0 AND OutcomeCode IS NULL AND FinalizedAtUtc IS NULL)
               OR (ReceiptStatus BETWEEN 1 AND 3
                   AND NULLIF(LTRIM(RTRIM(OutcomeCode)), N'') IS NOT NULL
                   AND FinalizedAtUtc IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_SourceDocumentDefenderReceipts_Time
        CHECK (ReceivedAtUtc >= DATEADD(DAY, -1, CreatedAtUtc)
               AND ReceivedAtUtc <= DATEADD(MINUTE, 5, CreatedAtUtc)
               AND OccurredAtUtc >= DATEADD(DAY, -1, ReceivedAtUtc)
               AND OccurredAtUtc <= DATEADD(MINUTE, 5, ReceivedAtUtc)
               AND (FinalizedAtUtc IS NULL OR FinalizedAtUtc >= ReceivedAtUtc))
);

CREATE INDEX FundingPlatform_IX_SourceDocumentDefenderReceipts_Document
    ON dbo.FundingPlatform_SourceDocumentDefenderReceipts (SourceDocumentId, ReceivedAtUtc DESC, Id DESC)
    INCLUDE (PublicId, ProviderEventId, ReceiptStatus, ToStatus, ResultCode);

CREATE UNIQUE INDEX FundingPlatform_UQ_ImportRunItems_FullIdentity
    ON dbo.FundingPlatform_ImportRunItems
       (Id, ImportRunId, FundingSourceId, RawFundingOpportunityId);

/* A completed text extraction can later support one or more concrete import
   observations. This junction is empty until all four referenced identities
   exist and never creates a synthetic ImportRun. */
CREATE TABLE dbo.FundingPlatform_SourceDocumentAcquisitionLinks
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocumentAcquisitionLinks_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    ExtractionResultId BIGINT NOT NULL,
    FundingSourceId INT NOT NULL,
    ImportRunId BIGINT NOT NULL,
    RawFundingOpportunityId BIGINT NOT NULL,
    ImportRunItemId BIGINT NOT NULL,
    IsSecurityRevoked BIT NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocumentAcquisitionLinks_Revoked DEFAULT (0),
    SecurityRevokedAtUtc DATETIME2(3) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocumentAcquisitionLinks_Created DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_SourceDocumentAcquisitionLinks PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentAcquisitionLinks_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentAcquisitionLinks_ResultItem
        UNIQUE (ExtractionResultId, ImportRunItemId),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentAcquisitionLinks_Item UNIQUE (ImportRunItemId),
    CONSTRAINT FundingPlatform_FK_SourceDocumentAcquisitionLinks_Result
        FOREIGN KEY (ExtractionResultId, FundingSourceId)
        REFERENCES dbo.FundingPlatform_SourceDocumentExtractionResults (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_FK_SourceDocumentAcquisitionLinks_Run
        FOREIGN KEY (ImportRunId, FundingSourceId)
        REFERENCES dbo.FundingPlatform_ImportRuns (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_FK_SourceDocumentAcquisitionLinks_Raw
        FOREIGN KEY (RawFundingOpportunityId, FundingSourceId)
        REFERENCES dbo.FundingPlatform_RawFundingOpportunities (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_FK_SourceDocumentAcquisitionLinks_Item
        FOREIGN KEY (ImportRunItemId, ImportRunId, FundingSourceId, RawFundingOpportunityId)
        REFERENCES dbo.FundingPlatform_ImportRunItems
                   (Id, ImportRunId, FundingSourceId, RawFundingOpportunityId),
    CONSTRAINT FundingPlatform_CK_SourceDocumentAcquisitionLinks_Revoked
        CHECK ((IsSecurityRevoked = 0 AND SecurityRevokedAtUtc IS NULL)
               OR (IsSecurityRevoked = 1 AND SecurityRevokedAtUtc IS NOT NULL))
);
GO

/* Duplicate candidates are advisory. The only mutation below records a human
   decision; it does not merge, deactivate, publish or edit an opportunity. */
CREATE TABLE dbo.FundingPlatform_FundingOpportunityDuplicateCandidates
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingOpportunityDuplicateCandidates_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    FundingSourceId INT NOT NULL,
    ImportRunId BIGINT NULL,
    ImportRunItemId BIGINT NULL,
    CandidateOpportunityId BIGINT NOT NULL,
    SuggestedCanonicalOpportunityId BIGINT NULL,
    CandidateFingerprint BINARY(32) NOT NULL,
    MatchKind TINYINT NOT NULL,
    Confidence DECIMAL(5,4) NOT NULL,
    EvidenceJson NVARCHAR(MAX) NOT NULL,
    Status TINYINT NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingOpportunityDuplicateCandidates_Status DEFAULT (0),
    CreatedAtUtc DATETIME2(3) NOT NULL,
    DecidedAtUtc DATETIME2(3) NULL,
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_FundingOpportunityDuplicateCandidates PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_FundingOpportunityDuplicateCandidates_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_FundingOpportunityDuplicateCandidates_Identity
        UNIQUE (CandidateOpportunityId, SuggestedCanonicalOpportunityId, CandidateFingerprint),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityDuplicateCandidates_Source
        FOREIGN KEY (FundingSourceId) REFERENCES dbo.FundingPlatform_FundingSources (Id),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityDuplicateCandidates_Item
        FOREIGN KEY (ImportRunItemId, ImportRunId, FundingSourceId)
        REFERENCES dbo.FundingPlatform_ImportRunItems (Id, ImportRunId, FundingSourceId),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityDuplicateCandidates_Candidate
        FOREIGN KEY (CandidateOpportunityId) REFERENCES dbo.FundingPlatform_FundingOpportunities (Id),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityDuplicateCandidates_Suggested
        FOREIGN KEY (SuggestedCanonicalOpportunityId) REFERENCES dbo.FundingPlatform_FundingOpportunities (Id),
    CONSTRAINT FundingPlatform_CK_FundingOpportunityDuplicateCandidates_Match
        CHECK (MatchKind BETWEEN 0 AND 2
               AND Confidence BETWEEN 0 AND 1
               AND ((ImportRunItemId IS NULL AND ImportRunId IS NULL)
                    OR (ImportRunItemId IS NOT NULL AND ImportRunId IS NOT NULL))
               AND (SuggestedCanonicalOpportunityId IS NULL
                    OR SuggestedCanonicalOpportunityId <> CandidateOpportunityId)),
    CONSTRAINT FundingPlatform_CK_FundingOpportunityDuplicateCandidates_Evidence
        CHECK (ISJSON(EvidenceJson) = 1
               AND DATALENGTH(CONVERT(VARCHAR(MAX),
                   EvidenceJson COLLATE Latin1_General_100_BIN2_UTF8)) BETWEEN 2 AND 65536),
    CONSTRAINT FundingPlatform_CK_FundingOpportunityDuplicateCandidates_State
        CHECK ((Status = 0 AND DecidedAtUtc IS NULL)
               OR (Status = 1 AND DecidedAtUtc IS NOT NULL))
);

CREATE INDEX FundingPlatform_IX_FundingOpportunityDuplicateCandidates_Admin
    ON dbo.FundingPlatform_FundingOpportunityDuplicateCandidates
       (Status, CreatedAtUtc DESC, Id DESC)
    INCLUDE (PublicId, CandidateOpportunityId, SuggestedCanonicalOpportunityId,
             MatchKind, Confidence, DecidedAtUtc);

CREATE TABLE dbo.FundingPlatform_FundingOpportunityDuplicateDecisions
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingOpportunityDuplicateDecisions_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    DuplicateCandidateId BIGINT NOT NULL,
    Decision TINYINT NOT NULL,
    CanonicalOpportunityId BIGINT NULL,
    ActorUserId BIGINT NOT NULL,
    Reason NVARCHAR(500) NOT NULL,
    IdempotencyKeyHash BINARY(32) NOT NULL,
    RequestHash BINARY(32) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_FundingOpportunityDuplicateDecisions PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_FundingOpportunityDuplicateDecisions_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_FundingOpportunityDuplicateDecisions_Candidate
        UNIQUE (DuplicateCandidateId),
    CONSTRAINT FundingPlatform_UQ_FundingOpportunityDuplicateDecisions_Idempotency
        UNIQUE (ActorUserId, IdempotencyKeyHash),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityDuplicateDecisions_Candidate
        FOREIGN KEY (DuplicateCandidateId)
        REFERENCES dbo.FundingPlatform_FundingOpportunityDuplicateCandidates (Id),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityDuplicateDecisions_Canonical
        FOREIGN KEY (CanonicalOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityDuplicateDecisions_Actor
        FOREIGN KEY (ActorUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_FundingOpportunityDuplicateDecisions_Decision
        CHECK ((Decision = 2 AND CanonicalOpportunityId IS NOT NULL)
               OR (Decision IN (1, 3) AND CanonicalOpportunityId IS NULL)),
    CONSTRAINT FundingPlatform_CK_FundingOpportunityDuplicateDecisions_Reason
        CHECK (NULLIF(LTRIM(RTRIM(Reason)), N'') IS NOT NULL
               AND CHARINDEX(CHAR(10), Reason) = 0
               AND CHARINDEX(CHAR(13), Reason) = 0)
);
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingSource_AcquisitionPolicy_Resolve
    @FundingSourceId INT,
    @Scheme NVARCHAR(10),
    @HostName NVARCHAR(253),
    @Port SMALLINT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET @Scheme = LOWER(LTRIM(RTRIM(@Scheme)));
    SET @HostName = LOWER(LTRIM(RTRIM(@HostName)));

    DECLARE @IsEnabled BIT, @ProviderType TINYINT, @ComplianceStatus TINYINT;
    DECLARE @LicenseStatus TINYINT, @LicenseExpiresAtUtc DATETIME2(3);
    DECLARE @RobotsStatus TINYINT, @RobotsExpiresAtUtc DATETIME2(3);
    DECLARE @AllowedHostsRequired BIT, @HostAllowed BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Allowed BIT = 0;
    DECLARE @Rate INT, @MaximumBytes BIGINT, @RetentionDays SMALLINT;

    DECLARE @PolicyId BIGINT;
    SELECT @IsEnabled = sources.IsEnabled, @ProviderType = policies.ProviderType,
           @ComplianceStatus = sources.ComplianceStatus,
           @LicenseStatus = policies.LicenseStatus,
           @LicenseExpiresAtUtc = policies.LicenseExpiresAtUtc,
           @RobotsStatus = policies.RobotsPolicyStatus,
           @RobotsExpiresAtUtc = policies.RobotsExpiresAtUtc,
           @AllowedHostsRequired = sources.AllowedHostsRequired,
           @Rate = policies.RequestRateLimitPerMinute,
           @MaximumBytes = policies.MaximumResponseBytes,
           @RetentionDays = policies.ContentRetentionDays,
           @PolicyId = policies.Id
    FROM dbo.FundingPlatform_FundingSources AS sources
    LEFT JOIN dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions AS policies
        ON policies.FundingSourceId = sources.Id
       AND policies.PolicyVersion = sources.AcquisitionPolicyVersion
    WHERE sources.Id = @FundingSourceId;

    IF @IsEnabled IS NULL SET @Code = N'not-found';
    ELSE IF @Scheme <> N'https' OR @Port NOT BETWEEN 1 AND 32767
         OR NULLIF(@HostName, N'') IS NULL
        SET @Code = N'endpoint-not-allowed';
    ELSE IF @IsEnabled <> 1 SET @Code = N'source-disabled';
    ELSE IF @ComplianceStatus <> 1 SET @Code = N'compliance-required';
    ELSE IF @PolicyId IS NULL SET @Code = N'policy-not-found';
    ELSE IF (@ProviderType IN (1, 2, 3)
             AND (@LicenseStatus <> 1 OR @LicenseExpiresAtUtc IS NOT NULL
                  AND @LicenseExpiresAtUtc <= @NowUtc))
         OR (@ProviderType IN (0, 4) AND @LicenseStatus NOT IN (1, 3))
        SET @Code = N'license-required';
    ELSE IF @ProviderType IN (2, 3)
         AND (@RobotsStatus <> 1 OR @RobotsExpiresAtUtc IS NULL
              OR @RobotsExpiresAtUtc <= @NowUtc)
        SET @Code = N'robots-policy-required';
    ELSE IF @Rate IS NULL OR @MaximumBytes IS NULL OR @RetentionDays IS NULL
        SET @Code = N'limits-required';
    ELSE
    BEGIN
        IF EXISTS
        (
            SELECT 1
            FROM dbo.FundingPlatform_FundingSourceAcquisitionPolicyHosts
            WHERE PolicyId = @PolicyId AND FundingSourceId = @FundingSourceId
              AND Port = @Port AND HostName = @HostName
        ) SET @HostAllowed = 1;

        IF @ProviderType IN (1, 2, 3)
           AND (@AllowedHostsRequired <> 1 OR @HostAllowed = 0)
            SET @Code = N'host-not-allowed';
        ELSE IF @AllowedHostsRequired = 1 AND @HostAllowed = 0
            SET @Code = N'host-not-allowed';
        ELSE
        BEGIN
            SET @Allowed = 1;
            SET @Code = N'allowed';
        END;
    END;

    SELECT @Allowed AS Allowed, @Code AS Code, @FundingSourceId AS FundingSourceId,
           CASE WHEN @Allowed = 1 THEN @Rate END AS RequestRateLimitPerMinute,
           CASE WHEN @Allowed = 1 THEN @MaximumBytes END AS MaximumResponseBytes,
           CASE WHEN @Allowed = 1 THEN @RetentionDays END AS ContentRetentionDays;
END;
GO

/* Every outbound network request reserves one globally serialized slot. The
   caller may wait until ReservedAtUtc; no URI, query string or response is
   persisted. This makes the approved rate effective across scaled workers. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingSource_AcquisitionRequest_Authorize
    @FundingSourceId INT,
    @Scheme NVARCHAR(10),
    @HostName NVARCHAR(253),
    @Port SMALLINT,
    @CanonicalDestinationHash BINARY(32),
    @AcquisitionPolicyFingerprint BINARY(32),
    @MinimumIntervalMilliseconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Scheme = LOWER(LTRIM(RTRIM(@Scheme)));
    SET @HostName = LOWER(LTRIM(RTRIM(@HostName)));

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @IsEnabled BIT, @ProviderType TINYINT, @ComplianceStatus TINYINT;
    DECLARE @LicenseStatus TINYINT, @LicenseName NVARCHAR(200), @LicenseUrl NVARCHAR(2048);
    DECLARE @LicenseReviewed DATETIME2(3), @LicenseExpires DATETIME2(3);
    DECLARE @RobotsStatus TINYINT, @RobotsExpires DATETIME2(3);
    DECLARE @HostAllowed BIT = 0, @EndpointAllowed BIT = 0, @PolicyId BIGINT;
    DECLARE @Rate INT, @MaximumBytes BIGINT, @RetentionDays SMALLINT, @PolicyVersion INT;
    DECLARE @StoredPolicyFingerprint BINARY(32);
    DECLARE @CurrentNext DATETIME2(3), @ReservedAtUtc DATETIME2(3), @NextAllowedAtUtc DATETIME2(3);
    DECLARE @IntervalMilliseconds INT, @RetryAfterMilliseconds BIGINT;
    DECLARE @Allowed BIT = 0, @Code NVARCHAR(50) = N'not-found';

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_AcquisitionAuthorize;

    BEGIN TRY
        SELECT @IsEnabled = sources.IsEnabled, @ProviderType = policies.ProviderType,
               @ComplianceStatus = sources.ComplianceStatus,
               @LicenseStatus = policies.LicenseStatus,
               @LicenseName = policies.LicenseName, @LicenseUrl = policies.LicenseUrl,
               @LicenseReviewed = policies.LicenseReviewedAtUtc,
               @LicenseExpires = policies.LicenseExpiresAtUtc,
               @RobotsStatus = policies.RobotsPolicyStatus,
               @RobotsExpires = policies.RobotsExpiresAtUtc,
               @Rate = policies.RequestRateLimitPerMinute,
               @MaximumBytes = policies.MaximumResponseBytes,
               @RetentionDays = policies.ContentRetentionDays,
               @PolicyVersion = policies.PolicyVersion,
               @StoredPolicyFingerprint = policies.PolicyFingerprint,
               @PolicyId = policies.Id,
               @CurrentNext = sources.NextAcquisitionAllowedAtUtc
        FROM dbo.FundingPlatform_FundingSources AS sources WITH (UPDLOCK, HOLDLOCK)
        LEFT JOIN dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions AS policies
            WITH (HOLDLOCK)
            ON policies.FundingSourceId = sources.Id
           AND policies.PolicyVersion = sources.AcquisitionPolicyVersion
        WHERE sources.Id = @FundingSourceId;

        IF @IsEnabled IS NULL SET @Code = N'not-found';
        ELSE IF @NowUtc IS NULL
             OR @MinimumIntervalMilliseconds NOT BETWEEN 100 AND 60000
             OR @CanonicalDestinationHash IS NULL
             OR @AcquisitionPolicyFingerprint IS NULL
             OR @Scheme <> N'https' OR @Port NOT BETWEEN 1 AND 32767
             OR NULLIF(@HostName, N'') IS NULL OR LEN(@HostName) > 253
             OR @HostName NOT LIKE N'%.%'
             OR @HostName = N'localhost'
             OR @HostName LIKE N'127.%' OR @HostName LIKE N'10.%'
             OR @HostName LIKE N'192.168.%' OR @HostName LIKE N'169.254.%'
            SET @Code = N'endpoint-not-allowed';
        ELSE IF @ProviderType NOT IN (1, 2, 3) SET @Code = N'network-provider-required';
        ELSE IF @IsEnabled <> 1 SET @Code = N'source-disabled';
        ELSE IF @ComplianceStatus <> 1 SET @Code = N'compliance-required';
        ELSE IF @PolicyId IS NULL OR @StoredPolicyFingerprint IS NULL
            SET @Code = N'policy-not-found';
        ELSE IF @StoredPolicyFingerprint <> @AcquisitionPolicyFingerprint
            SET @Code = N'policy-changed';
        ELSE IF @LicenseStatus <> 1 OR @LicenseName IS NULL OR @LicenseUrl IS NULL
             OR @LicenseReviewed IS NULL
             OR (@LicenseExpires IS NOT NULL AND @LicenseExpires <= @NowUtc)
            SET @Code = N'license-required';
        ELSE IF @ProviderType IN (2, 3)
             AND (@RobotsStatus <> 1 OR @RobotsExpires IS NULL OR @RobotsExpires <= @NowUtc)
            SET @Code = N'robots-policy-required';
        ELSE IF @Rate IS NULL OR @MaximumBytes IS NULL OR @RetentionDays IS NULL
            SET @Code = N'limits-required';
        ELSE
        BEGIN
            IF EXISTS
            (
                SELECT 1
                FROM dbo.FundingPlatform_FundingSourceAcquisitionPolicyHosts WITH (HOLDLOCK)
                WHERE PolicyId = @PolicyId AND FundingSourceId = @FundingSourceId
                  AND Port = @Port AND HostName = @HostName
            ) SET @HostAllowed = 1;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.FundingPlatform_FundingSourceAcquisitionPolicyEndpoints WITH (HOLDLOCK)
                WHERE PolicyId = @PolicyId AND FundingSourceId = @FundingSourceId
                  AND CanonicalUriHash = @CanonicalDestinationHash
            ) SET @EndpointAllowed = 1;

            IF @HostAllowed = 0 SET @Code = N'host-not-allowed';
            ELSE IF @EndpointAllowed = 0 SET @Code = N'endpoint-not-allowed';
            ELSE
            BEGIN
                SET @ReservedAtUtc = CASE WHEN @CurrentNext IS NULL OR @CurrentNext < @NowUtc
                                          THEN @NowUtc ELSE @CurrentNext END;
                SET @IntervalMilliseconds = (60000 + @Rate - 1) / @Rate;
                IF @MinimumIntervalMilliseconds > @IntervalMilliseconds
                    SET @IntervalMilliseconds = @MinimumIntervalMilliseconds;
                SET @NextAllowedAtUtc = DATEADD(MILLISECOND, @IntervalMilliseconds, @ReservedAtUtc);
                SET @RetryAfterMilliseconds = DATEDIFF_BIG(MILLISECOND, @NowUtc, @ReservedAtUtc);
                UPDATE dbo.FundingPlatform_FundingSources
                SET NextAcquisitionAllowedAtUtc = @NextAllowedAtUtc
                WHERE Id = @FundingSourceId;
                SET @Allowed = 1; SET @Code = N'reserved';
            END;
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_AcquisitionAuthorize;
        THROW;
    END CATCH;

    SELECT @Allowed AS Allowed, @Code AS Code, @FundingSourceId AS FundingSourceId,
           CASE WHEN @Allowed = 1 THEN @ReservedAtUtc END AS ReservedAtUtc,
           CASE WHEN @Allowed = 1 THEN @NextAllowedAtUtc END AS NextAllowedAtUtc,
           CASE WHEN @Allowed = 1 THEN CONVERT(INT,
                CASE WHEN @RetryAfterMilliseconds > 2147483647 THEN 2147483647
                     ELSE @RetryAfterMilliseconds END) END AS RetryAfterMilliseconds,
           CASE WHEN @Allowed = 1 THEN @Rate END AS RequestRateLimitPerMinute,
           CASE WHEN @Allowed = 1 THEN CONVERT(INT, @MaximumBytes) END AS MaximumResponseBytes,
           CASE WHEN @Allowed = 1 THEN @RetentionDays END AS ContentRetentionDays,
           CASE WHEN @Allowed = 1 THEN @PolicyVersion END AS AcquisitionPolicyVersion,
           CASE WHEN @Allowed = 1 THEN @StoredPolicyFingerprint END
               AS AcquisitionPolicyFingerprint,
           CASE WHEN @Allowed = 1 THEN @IntervalMilliseconds END
               AS AppliedIntervalMilliseconds;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingSource_AdminList
    @AdminUserPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;

    SELECT sources.Id, sources.Name, COALESCE(policies.ProviderType, sources.ProviderType)
               AS ProviderType,
           policies.BaseUrl,
           sources.IsEnabled, policies.ProviderCode,
           CASE sources.ComplianceStatus WHEN 1 THEN N'approved'
                                         WHEN 2 THEN N'rejected'
                                         ELSE N'pending' END AS ComplianceStatus,
           policies.LicenseStatus, policies.LicenseName, policies.LicenseUrl,
           policies.LicenseReviewedAtUtc, policies.LicenseExpiresAtUtc,
           policies.RobotsPolicyStatus, policies.RobotsReviewedAtUtc,
           policies.RobotsExpiresAtUtc, policies.RequestRateLimitPerMinute,
           policies.MaximumResponseBytes, policies.ContentRetentionDays,
           sources.AllowedHostsRequired, sources.AcquisitionPolicyVersion,
           CONVERT(INT, (SELECT COUNT_BIG(1)
                         FROM dbo.FundingPlatform_FundingSourceAcquisitionPolicyHosts AS hosts
                         WHERE hosts.PolicyId = policies.Id
                           AND hosts.FundingSourceId = sources.Id))
               AS EnabledAllowedHostCount,
           CAST(CASE
             WHEN sources.IsEnabled <> 1 OR sources.ComplianceStatus <> 1 THEN 0
             WHEN policies.Id IS NULL OR policies.PolicyFingerprint IS NULL THEN 0
             WHEN policies.ProviderType IN (1, 2, 3)
                  AND (policies.LicenseStatus <> 1 OR policies.LicenseName IS NULL
                       OR policies.LicenseUrl IS NULL OR policies.LicenseReviewedAtUtc IS NULL
                       OR (policies.LicenseExpiresAtUtc IS NOT NULL
                           AND policies.LicenseExpiresAtUtc <= SYSUTCDATETIME())
                       OR policies.RequestRateLimitPerMinute IS NULL
                       OR policies.MaximumResponseBytes IS NULL
                       OR policies.ContentRetentionDays IS NULL
                       OR NOT EXISTS
                          (SELECT 1
                           FROM dbo.FundingPlatform_FundingSourceAcquisitionPolicyHosts AS hosts
                           WHERE hosts.PolicyId = policies.Id
                             AND hosts.FundingSourceId = sources.Id)
                       OR NOT EXISTS
                          (SELECT 1
                           FROM dbo.FundingPlatform_FundingSourceAcquisitionPolicyEndpoints AS endpoints
                           WHERE endpoints.PolicyId = policies.Id
                             AND endpoints.FundingSourceId = sources.Id
                             AND endpoints.EndpointKind = 2)) THEN 0
             WHEN policies.ProviderType IN (2, 3)
                  AND (policies.RobotsPolicyStatus <> 1
                       OR policies.RobotsExpiresAtUtc IS NULL
                       OR policies.RobotsExpiresAtUtc <= SYSUTCDATETIME()
                       OR NOT EXISTS
                          (SELECT 1
                           FROM dbo.FundingPlatform_FundingSourceAcquisitionPolicyEndpoints AS endpoints
                           WHERE endpoints.PolicyId = policies.Id
                             AND endpoints.FundingSourceId = sources.Id
                             AND endpoints.EndpointKind = 3)) THEN 0
             WHEN policies.ProviderType IN (0, 4)
                  AND policies.LicenseStatus NOT IN (1, 3) THEN 0
             ELSE 1 END AS BIT) AS AcquisitionReady,
           policies.PolicyFingerprint AS AcquisitionPolicyFingerprint,
           sources.NextRunAtUtc, sources.LastSuccessfulRunAtUtc
    FROM dbo.FundingPlatform_FundingSources AS sources
    LEFT JOIN dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions AS policies
        ON policies.FundingSourceId = sources.Id
       AND policies.PolicyVersion = sources.AcquisitionPolicyVersion
    ORDER BY sources.Name, sources.Id;
END;
GO

/* Operator-only policy activation. Hosts/endpoints are accepted as bounded
   JSON arrays, canonicalized and snapshotted; no secret reference is returned. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingSourceAcquisitionPolicy_Upsert
    @SuperAdminUserPublicId UNIQUEIDENTIFIER,
    @ProviderCode NVARCHAR(100),
    @BaseUrl NVARCHAR(2048),
    @LicenseName NVARCHAR(200),
    @LicenseUrl NVARCHAR(2048),
    @LicenseReviewedAtUtc DATETIME2(3),
    @LicenseExpiresAtUtc DATETIME2(3) = NULL,
    @RobotsPolicyCode NVARCHAR(20),
    @RobotsPolicyVersion INT,
    @RobotsReviewedAtUtc DATETIME2(3),
    @RobotsExpiresAtUtc DATETIME2(3) = NULL,
    @AllowedHostsJson NVARCHAR(MAX),
    @AllowedEndpointsJson NVARCHAR(MAX),
    @RequestRateLimitPerMinute INT,
    @MaximumResponseBytes INT,
    @ContentRetentionDays SMALLINT,
    @ScheduleIntervalSeconds INT = NULL,
    @IsEnabled BIT,
    @ComplianceApproved BIT,
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @CorrelationId NVARCHAR(100),
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ProviderCode = LOWER(LTRIM(RTRIM(@ProviderCode)));
    SET @BaseUrl = LTRIM(RTRIM(@BaseUrl));
    SET @LicenseName = LTRIM(RTRIM(@LicenseName));
    SET @LicenseUrl = LTRIM(RTRIM(@LicenseUrl));
    SET @RobotsPolicyCode = LOWER(LTRIM(RTRIM(@RobotsPolicyCode)));
    SET @CorrelationId = LTRIM(RTRIM(@CorrelationId));

    IF @NowUtc IS NULL OR @IdempotencyKeyHash IS NULL OR @RequestHash IS NULL
       OR NULLIF(@ProviderCode, N'') IS NULL OR LEN(@ProviderCode) > 100
       OR @ProviderCode LIKE N'%[^-a-z0-9._]%' COLLATE Latin1_General_100_BIN2
       OR NULLIF(@BaseUrl, N'') IS NULL OR LEN(@BaseUrl) > 2048
       OR @BaseUrl NOT LIKE N'https://%' OR CHARINDEX(N'@', @BaseUrl) > 0
       OR CHARINDEX(N'#', @BaseUrl) > 0 OR CHARINDEX(CHAR(10), @BaseUrl) > 0
       OR CHARINDEX(CHAR(13), @BaseUrl) > 0 OR CHARINDEX(CHAR(0), @BaseUrl) > 0
       OR NULLIF(@LicenseName, N'') IS NULL OR LEN(@LicenseName) > 200
       OR NULLIF(@LicenseUrl, N'') IS NULL OR LEN(@LicenseUrl) > 2048
       OR @LicenseUrl NOT LIKE N'https://%' OR CHARINDEX(N'@', @LicenseUrl) > 0
       OR CHARINDEX(N'#', @LicenseUrl) > 0 OR CHARINDEX(CHAR(10), @LicenseUrl) > 0
       OR CHARINDEX(CHAR(13), @LicenseUrl) > 0 OR CHARINDEX(CHAR(0), @LicenseUrl) > 0
       OR @LicenseReviewedAtUtc IS NULL OR @LicenseReviewedAtUtc > @NowUtc
       OR (@LicenseExpiresAtUtc IS NOT NULL AND @LicenseExpiresAtUtc <= @NowUtc)
       OR @RobotsPolicyCode NOT IN (N'enforce', N'not-applicable')
       OR @RobotsPolicyVersion < 1 OR @RobotsReviewedAtUtc IS NULL
       OR @RobotsReviewedAtUtc > @NowUtc
       OR (@RobotsExpiresAtUtc IS NOT NULL AND @RobotsExpiresAtUtc <= @NowUtc)
       OR @RequestRateLimitPerMinute NOT BETWEEN 1 AND 600
       OR @MaximumResponseBytes NOT BETWEEN 4096 AND 26214400
       OR @ContentRetentionDays NOT BETWEEN 1 AND 3650
       OR (@ScheduleIntervalSeconds IS NOT NULL
           AND @ScheduleIntervalSeconds NOT BETWEEN 300 AND 604800)
       OR @IsEnabled IS NULL OR @ComplianceApproved IS NULL
       OR NULLIF(@CorrelationId, N'') IS NULL OR LEN(@CorrelationId) > 100
       OR @CorrelationId COLLATE Latin1_General_100_BIN2
          LIKE N'%[^-A-Za-z0-9:_.]%' COLLATE Latin1_General_100_BIN2
       OR ISJSON(@AllowedHostsJson) <> 1 OR ISJSON(@AllowedEndpointsJson) <> 1
        THROW 51872, N'Acquisition policy input is invalid or incomplete.', 1;

    DECLARE @Hosts TABLE (HostName NVARCHAR(253) PRIMARY KEY);
    INSERT INTO @Hosts (HostName)
    SELECT DISTINCT LOWER(LTRIM(RTRIM(CONVERT(NVARCHAR(253), value))))
    FROM OPENJSON(@AllowedHostsJson)
    WHERE [type] = 1;
    IF (SELECT COUNT(*) FROM @Hosts) NOT BETWEEN 1 AND 5
       OR EXISTS
          (SELECT 1 FROM @Hosts
           WHERE LEN(HostName) NOT BETWEEN 3 AND 253 OR HostName NOT LIKE N'%.%'
              OR HostName NOT LIKE N'%[a-z]%' COLLATE Latin1_General_100_BIN2
              OR HostName LIKE N'%[^-a-z0-9.]%' COLLATE Latin1_General_100_BIN2
              OR HostName = N'localhost' OR HostName LIKE N'%.local'
              OR HostName LIKE N'127.%' OR HostName LIKE N'10.%'
              OR HostName LIKE N'192.168.%' OR HostName LIKE N'169.254.%')
        THROW 51873, N'Allowed host policy is invalid.', 1;

    DECLARE @Endpoints TABLE
    (
        EndpointKind TINYINT NOT NULL,
        CanonicalUri NVARCHAR(2048) NOT NULL,
        CanonicalUriHash BINARY(32) NOT NULL,
        PRIMARY KEY (EndpointKind, CanonicalUriHash)
    );
    INSERT INTO @Endpoints (EndpointKind, CanonicalUri, CanonicalUriHash)
    SELECT parsed.EndpointKind, parsed.CanonicalUri,
           HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
               parsed.CanonicalUri COLLATE Latin1_General_100_BIN2_UTF8)))
    FROM OPENJSON(@AllowedEndpointsJson)
    WITH (EndpointKind TINYINT N'$.kind', CanonicalUri NVARCHAR(2048) N'$.uri') AS parsed
    WHERE parsed.EndpointKind BETWEEN 1 AND 3
      AND NULLIF(LTRIM(RTRIM(parsed.CanonicalUri)), N'') IS NOT NULL;
    IF (SELECT COUNT(*) FROM @Endpoints) NOT BETWEEN 2 AND 10
       OR NOT EXISTS (SELECT 1 FROM @Endpoints WHERE EndpointKind = 1
                      AND CanonicalUri = @BaseUrl)
       OR NOT EXISTS (SELECT 1 FROM @Endpoints WHERE EndpointKind = 2)
       OR EXISTS
          (SELECT 1 FROM @Endpoints
           WHERE LEN(CanonicalUri) > 2048 OR CanonicalUri NOT LIKE N'https://%'
              OR CHARINDEX(N'@', CanonicalUri) > 0 OR CHARINDEX(N'#', CanonicalUri) > 0
              OR CHARINDEX(CHAR(10), CanonicalUri) > 0
              OR CHARINDEX(CHAR(13), CanonicalUri) > 0
              OR CHARINDEX(CHAR(0), CanonicalUri) > 0
              OR NOT EXISTS
                 (SELECT 1 FROM @Hosts AS hosts
                  WHERE CanonicalUri LIKE N'https://' + hosts.HostName + N'/%'
                     OR CanonicalUri = N'https://' + hosts.HostName))
        THROW 51874, N'Allowed endpoint policy is invalid.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @ActorUserId BIGINT, @FundingSourceId INT, @ProviderType TINYINT;
    DECLARE @CurrentVersion INT, @NewVersion INT, @PolicyId BIGINT;
    DECLARE @PolicyPublicId UNIQUEIDENTIFIER, @StoredRequestHash BINARY(32);
    DECLARE @WasReplay BIT = 0, @EndpointHash BINARY(32), @LicenseHash BINARY(32);
    DECLARE @HostsCanonical NVARCHAR(2000), @HostsHash BINARY(32), @Fingerprint BINARY(32);
    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_SourcePolicyUpsert;

    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId = @SuperAdminUserPublicId,
            @ActorUserId = @ActorUserId OUTPUT;
        IF NOT EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_UserRoles AS userRoles
            INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
            WHERE userRoles.UserId = @ActorUserId AND roles.NormalizedName = N'SUPERADMIN')
            THROW 51875, N'Active SuperAdmin role is required.', 1;

        SELECT @FundingSourceId = Id, @ProviderType = ProviderType,
               @CurrentVersion = AcquisitionPolicyVersion
        FROM dbo.FundingPlatform_FundingSources WITH (UPDLOCK, HOLDLOCK)
        WHERE ProviderCode = @ProviderCode;
        IF @FundingSourceId IS NULL OR @ProviderType NOT IN (1, 2, 3)
            THROW 51876, N'Network funding source was not found.', 1;
        IF @ProviderType IN (2, 3) AND @RobotsPolicyCode = N'enforce'
           AND NOT EXISTS (SELECT 1 FROM @Endpoints WHERE EndpointKind = 3)
            THROW 51877, N'An exact robots endpoint is required.', 1;

        SELECT @PolicyId = events.PolicyId, @StoredRequestHash = events.RequestHash,
               @PolicyPublicId = policies.PublicId, @Fingerprint = policies.PolicyFingerprint,
               @NewVersion = policies.PolicyVersion
        FROM dbo.FundingPlatform_FundingSourceAcquisitionPolicyEvents AS events
             WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions AS policies
            ON policies.Id = events.PolicyId
        WHERE events.ActorUserId = @ActorUserId
          AND events.FundingSourceId = @FundingSourceId
          AND events.IdempotencyKeyHash = @IdempotencyKeyHash;
        IF @PolicyId IS NOT NULL AND @StoredRequestHash <> @RequestHash
            THROW 51878, N'Idempotency key conflicts with a prior policy request.', 1;
        IF @PolicyId IS NOT NULL SET @WasReplay = 1;
        ELSE
        BEGIN
            SET @NewVersion = @CurrentVersion + 1;
            SELECT @HostsCanonical = STRING_AGG(CONVERT(NVARCHAR(MAX), HostName), NCHAR(10))
                       WITHIN GROUP (ORDER BY HostName)
            FROM @Hosts;
            SET @EndpointHash = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX),
                CONVERT(VARCHAR(MAX), @BaseUrl COLLATE Latin1_General_100_BIN2_UTF8)));
            SET @LicenseHash = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX),
                CONVERT(VARCHAR(MAX), @LicenseUrl COLLATE Latin1_General_100_BIN2_UTF8)));
            SET @HostsHash = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX),
                CONVERT(VARCHAR(MAX), @HostsCanonical COLLATE Latin1_General_100_BIN2_UTF8)));
            SET @Fingerprint = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX),
                CONVERT(VARCHAR(MAX), CONCAT
                (N'v1|', @ProviderCode, N'|', CONVERT(VARCHAR(64), @EndpointHash, 2), N'|',
                 CONVERT(VARCHAR(64), @LicenseHash, 2), N'|', @RobotsPolicyCode, N'|',
                 CONVERT(VARCHAR(20), @RobotsPolicyVersion), N'|',
                 CONVERT(VARCHAR(64), @HostsHash, 2), N'|',
                 CONVERT(VARCHAR(20), @NewVersion))
                 COLLATE Latin1_General_100_BIN2_UTF8)));

            DECLARE @InsertedPolicy TABLE
                (Id BIGINT, PublicId UNIQUEIDENTIFIER);
            INSERT INTO dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions
                (FundingSourceId, PolicyVersion, ProviderCode, ProviderType, BaseUrl,
                 AcquisitionEndpointHash, LicenseStatus, LicenseName, LicenseUrl,
                 LicenseUrlHash, LicenseReviewedAtUtc, LicenseExpiresAtUtc,
                 RobotsPolicyStatus, RobotsPolicyCode, RobotsPolicyVersion,
                 RobotsReviewedAtUtc, RobotsExpiresAtUtc, AllowedHostsHash,
                 RequestRateLimitPerMinute, MaximumResponseBytes, ContentRetentionDays,
                 PolicyFingerprint, CreatedByUserId, CreatedAtUtc)
            OUTPUT inserted.Id, inserted.PublicId INTO @InsertedPolicy (Id, PublicId)
            VALUES (@FundingSourceId, @NewVersion, @ProviderCode, @ProviderType, @BaseUrl,
                    @EndpointHash, 1, @LicenseName, @LicenseUrl, @LicenseHash,
                    @LicenseReviewedAtUtc, @LicenseExpiresAtUtc,
                    CASE WHEN @RobotsPolicyCode = N'enforce' THEN 1 ELSE 3 END,
                    @RobotsPolicyCode, @RobotsPolicyVersion, @RobotsReviewedAtUtc,
                    @RobotsExpiresAtUtc, @HostsHash, @RequestRateLimitPerMinute,
                    @MaximumResponseBytes, @ContentRetentionDays, @Fingerprint,
                    @ActorUserId, @NowUtc);
            SELECT @PolicyId = Id, @PolicyPublicId = PublicId FROM @InsertedPolicy;

            INSERT INTO dbo.FundingPlatform_FundingSourceAcquisitionPolicyHosts
                (PolicyId, FundingSourceId, HostName, Port, CreatedAtUtc)
            SELECT @PolicyId, @FundingSourceId, HostName, 443, @NowUtc FROM @Hosts;
            INSERT INTO dbo.FundingPlatform_FundingSourceAcquisitionPolicyEndpoints
                (PolicyId, FundingSourceId, EndpointKind, CanonicalUri,
                 CanonicalUriHash, CreatedAtUtc)
            SELECT @PolicyId, @FundingSourceId, EndpointKind, CanonicalUri,
                   CanonicalUriHash, @NowUtc FROM @Endpoints;

            DELETE FROM dbo.FundingPlatform_FundingSourceAllowedHosts
            WHERE FundingSourceId = @FundingSourceId;
            INSERT INTO dbo.FundingPlatform_FundingSourceAllowedHosts
                (FundingSourceId, HostName, Port, AllowSubdomains, IsEnabled,
                 CreatedAtUtc, UpdatedAtUtc)
            SELECT @FundingSourceId, HostName, 443, 0, 1, @NowUtc, @NowUtc FROM @Hosts;

            UPDATE dbo.FundingPlatform_FundingSources
            SET BaseUrl = @BaseUrl, IsEnabled = @IsEnabled,
                ScheduleIntervalSeconds = @ScheduleIntervalSeconds,
                ScheduleCron = CASE WHEN @ScheduleIntervalSeconds IS NULL THEN NULL
                                    ELSE N'fixed:' + CONVERT(NVARCHAR(20), @ScheduleIntervalSeconds) END,
                NextRunAtUtc = CASE WHEN @IsEnabled = 1 AND @ScheduleIntervalSeconds IS NOT NULL
                                    THEN DATEADD(SECOND, @ScheduleIntervalSeconds, @NowUtc) END,
                ComplianceStatus = CASE WHEN @ComplianceApproved = 1 THEN 1 ELSE 0 END,
                ComplianceApprovedAtUtc = CASE WHEN @ComplianceApproved = 1 THEN @NowUtc END,
                LicenseStatus = 1, LicenseName = @LicenseName, LicenseUrl = @LicenseUrl,
                LicenseUrlHash = @LicenseHash, LicenseReviewedAtUtc = @LicenseReviewedAtUtc,
                LicenseExpiresAtUtc = @LicenseExpiresAtUtc,
                RobotsPolicyStatus = CASE WHEN @RobotsPolicyCode = N'enforce' THEN 1 ELSE 3 END,
                RobotsPolicyCode = @RobotsPolicyCode,
                RobotsPolicyVersion = @RobotsPolicyVersion,
                RobotsReviewedAtUtc = @RobotsReviewedAtUtc,
                RobotsExpiresAtUtc = @RobotsExpiresAtUtc,
                RequestRateLimitPerMinute = @RequestRateLimitPerMinute,
                MaximumResponseBytes = @MaximumResponseBytes,
                ContentRetentionDays = @ContentRetentionDays,
                AllowedHostsRequired = 1, AcquisitionPolicyVersion = @NewVersion,
                AcquisitionEndpointHash = @EndpointHash,
                AllowedHostsHash = @HostsHash,
                AcquisitionPolicyFingerprint = @Fingerprint,
                NextAcquisitionAllowedAtUtc = NULL, UpdatedAtUtc = @NowUtc
            WHERE Id = @FundingSourceId;

            INSERT INTO dbo.FundingPlatform_FundingSourceAcquisitionPolicyEvents
                (FundingSourceId, PolicyId, ActorUserId, Action, IdempotencyKeyHash,
                 RequestHash, CorrelationId, CreatedAtUtc)
            VALUES (@FundingSourceId, @PolicyId, @ActorUserId,
                    CASE WHEN @IsEnabled = 1 THEN 1 ELSE 2 END,
                    @IdempotencyKeyHash, @RequestHash, @CorrelationId, @NowUtc);
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_SourcePolicyUpsert;
        THROW;
    END CATCH;

    SELECT CAST(1 AS BIT) AS Succeeded,
           CASE WHEN @WasReplay = 1 THEN N'replayed' ELSE N'upserted' END AS Code,
           @FundingSourceId AS FundingSourceId, @PolicyPublicId AS PolicyPublicId,
           @NewVersion AS PolicyVersion, @Fingerprint AS AcquisitionPolicyFingerprint,
           @IsEnabled AS IsEnabled, @WasReplay AS WasReplay;
END;
GO

/* Preserve the three-result-set FASE 7A contract while making advisory
   duplicate review discoverable from each import item. No raw payload or
   evidence JSON is exposed by this operational detail query. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ImportRun_Admin_Get
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @RunPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;

    DECLARE @RunId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_ImportRuns WHERE PublicId = @RunPublicId);

    IF @RunId IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, CAST(N'not-found' AS NVARCHAR(50)) AS Code,
               CAST(NULL AS UNIQUEIDENTIFIER) AS RunPublicId,
               CAST(NULL AS INT) AS FundingSourceId,
               CAST(NULL AS NVARCHAR(150)) AS SourceName,
               CAST(NULL AS NVARCHAR(100)) AS ProviderCode,
               CAST(NULL AS TINYINT) AS TriggerType, CAST(NULL AS TINYINT) AS Status,
               CAST(NULL AS NVARCHAR(100)) AS Keyword,
               CAST(NULL AS INT) AS MaximumResults,
               CAST(NULL AS INT) AS RetrievedCount, CAST(NULL AS INT) AS CreatedCount,
               CAST(NULL AS INT) AS UpdatedCount, CAST(NULL AS INT) AS UnchangedCount,
               CAST(NULL AS INT) AS StagedForReviewCount,
               CAST(NULL AS INT) AS FailedCount,
               CAST(NULL AS SMALLINT) AS AttemptCount,
               CAST(NULL AS DATETIME2(3)) AS CreatedAtUtc,
               CAST(NULL AS DATETIME2(3)) AS StartedAtUtc,
               CAST(NULL AS DATETIME2(3)) AS CompletedAtUtc,
               CAST(NULL AS NVARCHAR(100)) AS LastErrorCode;

        SELECT CAST(NULL AS UNIQUEIDENTIFIER) AS ItemPublicId,
               CAST(NULL AS UNIQUEIDENTIFIER) AS RawObservationPublicId,
               CAST(NULL AS UNIQUEIDENTIFIER) AS OpportunityPublicId,
               CAST(NULL AS NVARCHAR(250)) AS ExternalId,
               CAST(NULL AS TINYINT) AS Status,
               CAST(NULL AS NVARCHAR(50)) AS OutcomeCode,
               CAST(NULL AS DATETIME2(3)) AS CreatedAtUtc,
               CAST(NULL AS DATETIME2(3)) AS CompletedAtUtc,
               CAST(NULL AS UNIQUEIDENTIFIER) AS DuplicateCandidatePublicId,
               CAST(NULL AS TINYINT) AS DuplicateCandidateStatus,
               CAST(NULL AS TINYINT) AS DuplicateMatchKind,
               CAST(NULL AS DECIMAL(5,4)) AS DuplicateConfidence,
               CAST(NULL AS UNIQUEIDENTIFIER) AS SuggestedCanonicalOpportunityPublicId,
               CAST(NULL AS NVARCHAR(350)) AS SuggestedCanonicalTitle,
               CAST(NULL AS UNIQUEIDENTIFIER) AS DuplicateDecisionPublicId,
               CAST(NULL AS TINYINT) AS DuplicateDecision,
               CAST(NULL AS BINARY(8)) AS DuplicateCandidateRowVersion
        WHERE 1 = 0;

        SELECT CAST(NULL AS UNIQUEIDENTIFIER) AS ErrorPublicId,
               CAST(NULL AS UNIQUEIDENTIFIER) AS ItemPublicId,
               CAST(NULL AS NVARCHAR(50)) AS Stage,
               CAST(NULL AS NVARCHAR(100)) AS ErrorCode,
               CAST(NULL AS NVARCHAR(1000)) AS SanitizedMessage,
               CAST(NULL AS BIT) AS IsRetryable,
               CAST(NULL AS DATETIME2(3)) AS OccurredAtUtc
        WHERE 1 = 0;
        RETURN;
    END;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(N'found' AS NVARCHAR(50)) AS Code,
           runs.PublicId AS RunPublicId, runs.FundingSourceId,
           sources.Name AS SourceName, sources.ProviderCode,
           runs.TriggerType, runs.Status, runs.Keyword, runs.MaximumResults,
           runs.RetrievedCount, runs.CreatedCount, runs.UpdatedCount,
           runs.UnchangedCount, runs.StagedForReviewCount, runs.FailedCount,
           runs.AttemptCount, runs.CreatedAtUtc, runs.StartedAtUtc,
           runs.CompletedAtUtc, runs.LastErrorCode
    FROM dbo.FundingPlatform_ImportRuns AS runs
    INNER JOIN dbo.FundingPlatform_FundingSources AS sources
        ON sources.Id = runs.FundingSourceId
    WHERE runs.Id = @RunId;

    SELECT items.PublicId AS ItemPublicId,
           raw.PublicId AS RawObservationPublicId,
           opportunities.PublicId AS OpportunityPublicId,
           items.ExternalId, items.Status, items.OutcomeCode,
           items.CreatedAtUtc, items.CompletedAtUtc,
           candidates.PublicId AS DuplicateCandidatePublicId,
           candidates.Status AS DuplicateCandidateStatus,
           candidates.MatchKind AS DuplicateMatchKind,
           candidates.Confidence AS DuplicateConfidence,
           suggested.PublicId AS SuggestedCanonicalOpportunityPublicId,
           suggested.Title AS SuggestedCanonicalTitle,
           decisions.PublicId AS DuplicateDecisionPublicId,
           decisions.Decision AS DuplicateDecision,
           candidates.RowVersion AS DuplicateCandidateRowVersion
    FROM dbo.FundingPlatform_ImportRunItems AS items
    INNER JOIN dbo.FundingPlatform_RawFundingOpportunities AS raw
        ON raw.Id = items.RawFundingOpportunityId
    LEFT JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
        ON opportunities.Id = items.FundingOpportunityId
    OUTER APPLY
    (
        SELECT TOP (1) duplicateCandidates.*
        FROM dbo.FundingPlatform_FundingOpportunityDuplicateCandidates AS duplicateCandidates
        WHERE duplicateCandidates.ImportRunItemId = items.Id
          AND duplicateCandidates.ImportRunId = items.ImportRunId
        ORDER BY duplicateCandidates.Id DESC
    ) AS candidates
    LEFT JOIN dbo.FundingPlatform_FundingOpportunities AS suggested
        ON suggested.Id = candidates.SuggestedCanonicalOpportunityId
    LEFT JOIN dbo.FundingPlatform_FundingOpportunityDuplicateDecisions AS decisions
        ON decisions.DuplicateCandidateId = candidates.Id
    WHERE items.ImportRunId = @RunId
    ORDER BY items.Id;

    SELECT errors.PublicId AS ErrorPublicId,
           items.PublicId AS ItemPublicId,
           errors.Stage, errors.ErrorCode,
           errors.SanitizedMessage, errors.IsRetryable, errors.OccurredAtUtc
    FROM dbo.FundingPlatform_ImportErrors AS errors
    LEFT JOIN dbo.FundingPlatform_ImportRunItems AS items
        ON items.Id = errors.ImportRunItemId
    WHERE errors.ImportRunId = @RunId
    ORDER BY errors.OccurredAtUtc, errors.Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentExtraction_AdminStart
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @SourceDocumentPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @CorrelationId NVARCHAR(100),
    @ParserCode NVARCHAR(100),
    @ParserVersion NVARCHAR(50),
    @ParserSettingsHash BINARY(32),
    @MaximumCharacters INT,
    @MaximumPages INT,
    @MaximumUtf8Bytes INT,
    @MaximumStackDepth SMALLINT,
    @MaximumBytes INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51801, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51802, N'MFA is required for this administrative operation.', 1;
    SET XACT_ABORT ON;

    SET @CorrelationId = LTRIM(RTRIM(@CorrelationId));
    SET @ParserCode = LOWER(LTRIM(RTRIM(@ParserCode)));
    SET @ParserVersion = LTRIM(RTRIM(@ParserVersion));
    DECLARE @ComputedParserSettingsHash BINARY(32) = HASHBYTES(
        'SHA2_256',
        CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
            CONCAT(@ParserCode, N'|', @ParserVersion, N'|',
                   CONVERT(VARCHAR(20), @MaximumCharacters), N'|',
                   CONVERT(VARCHAR(20), @MaximumPages), N'|',
                   CONVERT(VARCHAR(20), @MaximumUtf8Bytes), N'|',
                   CONVERT(VARCHAR(20), @MaximumStackDepth), N'|',
                   CONVERT(VARCHAR(20), @MaximumBytes))
            COLLATE Latin1_General_100_BIN2_UTF8)));
    IF @ExpectedRowVersion IS NULL OR @IdempotencyKeyHash IS NULL OR @RequestHash IS NULL
        THROW 51803, N'Row version, idempotency hash and request hash are required.', 1;
    IF @NowUtc IS NULL
        THROW 51804, N'NowUtc is required.', 1;
    IF NULLIF(@CorrelationId, N'') IS NULL OR LEN(@CorrelationId) > 100
       OR @CorrelationId COLLATE Latin1_General_100_BIN2
          LIKE N'%[^-A-Za-z0-9:_.]%' COLLATE Latin1_General_100_BIN2
        THROW 51805, N'CorrelationId has an invalid format.', 1;
    IF NULLIF(@ParserCode, N'') IS NULL OR LEN(@ParserCode) > 100
       OR @ParserCode LIKE N'%[^-a-z0-9._]%' COLLATE Latin1_General_100_BIN2
       OR NULLIF(@ParserVersion, N'') IS NULL OR LEN(@ParserVersion) > 50
       OR @ParserSettingsHash IS NULL
       OR @MaximumCharacters NOT BETWEEN 1 AND 500000
       OR @MaximumPages NOT BETWEEN 1 AND 250
       OR @MaximumUtf8Bytes NOT BETWEEN 1024 AND 2097152
       OR @MaximumStackDepth NOT BETWEEN 16 AND 128
       OR @MaximumBytes NOT BETWEEN 1024 AND 26214400
       OR @ParserSettingsHash <> @ComputedParserSettingsHash
        THROW 51808, N'Parser identity and bounded settings are required.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @ActorUserId BIGINT, @DocumentId BIGINT, @FundingSourceId INT;
    DECLARE @StorageStatus TINYINT, @ScanStatus TINYINT, @ExtractionStatus TINYINT;
    DECLARE @CurrentRowVersion BINARY(8), @TrustedETag NVARCHAR(100);
    DECLARE @ContentHash BINARY(32), @ContentLength BIGINT;
    DECLARE @IsEnabled BIT, @ProviderType TINYINT, @ComplianceStatus TINYINT, @LicenseStatus TINYINT;
    DECLARE @LicenseName NVARCHAR(200), @LicenseUrl NVARCHAR(2048);
    DECLARE @LicenseReviewedAtUtc DATETIME2(3);
    DECLARE @LicenseExpiresAtUtc DATETIME2(3), @MaxAttempts SMALLINT, @RetrySeconds INT;
    DECLARE @ContentRetentionDays SMALLINT, @AcquisitionPolicyVersion INT;
    DECLARE @DocumentRetentionUntilUtc DATETIME2(3), @DocumentRetentionStatus TINYINT;
    DECLARE @ActivePolicyId BIGINT;
    DECLARE @JobId BIGINT, @JobPublicId UNIQUEIDENTIFIER, @JobStatus TINYINT;
    DECLARE @JobAttemptCount SMALLINT;
    DECLARE @StoredIdempotencyHash BINARY(32), @StoredRequestHash BINARY(32);
    DECLARE @ActiveJobId BIGINT;
    DECLARE @ResultRowVersion BINARY(8), @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @DocumentResultRowVersion BINARY(8);
    DECLARE @Code NVARCHAR(50) = N'not-found';

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_ExtractStart;

    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId = @AdminUserPublicId,
            @ActorUserId = @ActorUserId OUTPUT;

        SELECT @DocumentId = documents.Id, @FundingSourceId = documents.FundingSourceId,
               @StorageStatus = documents.StorageStatus, @ScanStatus = documents.ScanStatus,
               @ExtractionStatus = documents.ExtractionStatus,
               @CurrentRowVersion = documents.RowVersion,
               @TrustedETag = documents.TrustedBlobETag,
               @ContentHash = documents.ContentHash,
               @ContentLength = documents.ContentLength,
               @DocumentRetentionUntilUtc = documents.RetentionUntilUtc,
               @DocumentRetentionStatus = documents.ContentRetentionStatus,
               @ContentRetentionDays = documents.ContentRetentionDays,
               @AcquisitionPolicyVersion = documents.AcquisitionPolicyVersion,
               @IsEnabled = sources.IsEnabled,
               @ProviderType = policies.ProviderType,
               @ComplianceStatus = sources.ComplianceStatus,
               @LicenseStatus = policies.LicenseStatus,
               @LicenseName = policies.LicenseName, @LicenseUrl = policies.LicenseUrl,
               @LicenseReviewedAtUtc = policies.LicenseReviewedAtUtc,
               @LicenseExpiresAtUtc = policies.LicenseExpiresAtUtc,
               @ActivePolicyId = policies.Id,
               @MaxAttempts = sources.MaxRunAttempts,
               @RetrySeconds = sources.RetryBaseDelaySeconds
        FROM dbo.FundingPlatform_SourceDocuments AS documents WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_FundingSources AS sources WITH (UPDLOCK, HOLDLOCK)
            ON sources.Id = documents.FundingSourceId
        LEFT JOIN dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions AS policies
            WITH (HOLDLOCK)
            ON policies.FundingSourceId = sources.Id
           AND policies.PolicyVersion = sources.AcquisitionPolicyVersion
        WHERE documents.PublicId = @SourceDocumentPublicId;

        IF @DocumentId IS NOT NULL
        BEGIN
            /* Resolve the actor/idempotency identity first. A replay with changed
               parser settings must be a deterministic conflict, never UQ 2601. */
            SELECT @JobId = Id, @JobPublicId = PublicId, @JobStatus = Status,
                   @StoredIdempotencyHash = IdempotencyKeyHash,
                   @StoredRequestHash = RequestHash, @ResultRowVersion = RowVersion,
                   @JobAttemptCount = AttemptCount, @MaxAttempts = MaxAttempts
            FROM dbo.FundingPlatform_SourceDocumentExtractionJobs WITH (UPDLOCK, HOLDLOCK)
            WHERE SourceDocumentId = @DocumentId AND RequestedByUserId = @ActorUserId
              AND IdempotencyKeyHash = @IdempotencyKeyHash;

            IF @JobId IS NULL
                SELECT @JobId = Id, @JobPublicId = PublicId, @JobStatus = Status,
                       @StoredIdempotencyHash = IdempotencyKeyHash,
                       @StoredRequestHash = RequestHash, @ResultRowVersion = RowVersion,
                       @JobAttemptCount = AttemptCount, @MaxAttempts = MaxAttempts
                FROM dbo.FundingPlatform_SourceDocumentExtractionJobs WITH (UPDLOCK, HOLDLOCK)
                WHERE SourceDocumentId = @DocumentId
                  AND ParserCode = @ParserCode AND ParserVersion = @ParserVersion
                  AND ParserSettingsHash = @ParserSettingsHash;

            SELECT TOP (1) @ActiveJobId = Id
            FROM dbo.FundingPlatform_SourceDocumentExtractionJobs WITH (UPDLOCK, HOLDLOCK)
            WHERE SourceDocumentId = @DocumentId AND Status IN (1, 2)
            ORDER BY Id DESC;
        END;

        IF @DocumentId IS NULL SET @Code = N'not-found';
        ELSE IF @JobId IS NOT NULL
        BEGIN
            IF @StoredIdempotencyHash = @IdempotencyKeyHash
               AND @StoredRequestHash = @RequestHash
            BEGIN
                SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'replayed';
            END
            ELSE IF @StoredIdempotencyHash = @IdempotencyKeyHash
                SET @Code = N'idempotency-conflict';
            ELSE SET @Code = N'already-started';
        END
        ELSE IF @ActiveJobId IS NOT NULL SET @Code = N'already-started';
        ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
        ELSE IF @StorageStatus <> 2 OR @ScanStatus <> 1 OR @TrustedETag IS NULL
            SET @Code = N'unsafe-document';
        ELSE IF @DocumentRetentionStatus <> 0
             OR @DocumentRetentionUntilUtc <= @NowUtc
            SET @Code = N'retention-expired';
        ELSE IF @ContentLength > @MaximumBytes SET @Code = N'document-too-large-for-extraction';
        ELSE IF @ExtractionStatus IN (1, 2) SET @Code = N'invalid-transition';
        ELSE IF @IsEnabled <> 1 SET @Code = N'source-disabled';
        ELSE IF @ComplianceStatus <> 1 SET @Code = N'compliance-required';
        ELSE IF @ActivePolicyId IS NULL SET @Code = N'policy-not-found';
        ELSE IF (@ProviderType IN (1, 2, 3)
                 AND (@LicenseStatus <> 1 OR @LicenseName IS NULL OR @LicenseUrl IS NULL
                      OR @LicenseReviewedAtUtc IS NULL
                      OR (@LicenseExpiresAtUtc IS NOT NULL
                          AND @LicenseExpiresAtUtc <= @NowUtc)))
             OR (@ProviderType IN (0, 4) AND @LicenseStatus NOT IN (1, 3))
            SET @Code = N'license-required';
        ELSE IF @ContentRetentionDays IS NULL
            SET @Code = N'retention-policy-required';
        ELSE
        BEGIN
            DECLARE @InsertedJob TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER, RowVersion BINARY(8));
            INSERT INTO dbo.FundingPlatform_SourceDocumentExtractionJobs
                (SourceDocumentId, FundingSourceId, Status, ParserCode, ParserVersion,
                 ParserSettingsHash, MaximumCharacters, MaximumPages, MaximumUtf8Bytes,
                 MaximumStackDepth, MaximumBytes, ContentRetentionDays,
                 AcquisitionPolicyVersion, RetentionUntilUtc,
                 ExpectedTrustedBlobETag, ExpectedContentHash, ExpectedContentLength,
                 AttemptCount, MaxAttempts, RetryBaseDelaySeconds, NextAttemptAtUtc,
                 RequestedByUserId, IdempotencyKeyHash, RequestHash, CorrelationId,
                 CreatedAtUtc, UpdatedAtUtc)
            OUTPUT inserted.Id, inserted.PublicId, inserted.RowVersion
                INTO @InsertedJob (Id, PublicId, RowVersion)
            VALUES (@DocumentId, @FundingSourceId, 1, @ParserCode, @ParserVersion,
                    @ParserSettingsHash, @MaximumCharacters, @MaximumPages, @MaximumUtf8Bytes,
                    @MaximumStackDepth, @MaximumBytes, @ContentRetentionDays,
                    @AcquisitionPolicyVersion, @DocumentRetentionUntilUtc,
                    @TrustedETag, @ContentHash, @ContentLength, 0,
                    @MaxAttempts, @RetrySeconds, @NowUtc, @ActorUserId,
                    @IdempotencyKeyHash, @RequestHash, @CorrelationId, @NowUtc, @NowUtc);
            SELECT @JobId = Id, @JobPublicId = PublicId, @ResultRowVersion = RowVersion
            FROM @InsertedJob;

            UPDATE dbo.FundingPlatform_SourceDocuments
            SET ExtractionStatus = 1, UpdatedAtUtc = @NowUtc
            WHERE Id = @DocumentId;
            SELECT @DocumentResultRowVersion = RowVersion
            FROM dbo.FundingPlatform_SourceDocuments WHERE Id = @DocumentId;

            DECLARE @MessageId UNIQUEIDENTIFIER = NEWID();
            INSERT INTO dbo.FundingPlatform_OutboxMessages
                (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                 OccurredAtUtc, AvailableAtUtc)
            SELECT @MessageId, N'SourceDocumentExtractionRequested',
                   N'SourceDocumentExtractionJob', CONVERT(NVARCHAR(100), @JobPublicId),
                   (SELECT @JobPublicId AS jobId, 1 AS [version]
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;

            SET @JobStatus = 1; SET @Succeeded = 1; SET @Code = N'queued';
            SET @JobAttemptCount = 0;
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ExtractStart;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           CASE WHEN @Succeeded = 1 THEN @JobPublicId END AS JobPublicId,
           CASE WHEN @DocumentId IS NULL THEN NULL ELSE @SourceDocumentPublicId END
               AS SourceDocumentPublicId,
           @JobStatus AS ExtractionStatus, @JobAttemptCount AS AttemptCount,
           @MaxAttempts AS MaxAttempts, @ResultRowVersion AS JobRowVersion,
           COALESCE(@DocumentResultRowVersion, @CurrentRowVersion) AS DocumentRowVersion,
           @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentExtraction_Claim
    @JobPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @LeaseSeconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @JobPublicId IS NULL OR @LeaseId IS NULL OR @NowUtc IS NULL
        THROW 51806, N'JobPublicId, LeaseId and NowUtc are required.', 1;
    IF @LeaseSeconds NOT BETWEEN 30 AND 3600
        THROW 51807, N'LeaseSeconds must be between 30 and 3600.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @JobId BIGINT, @DocumentId BIGINT, @DocumentPublicId UNIQUEIDENTIFIER;
    DECLARE @FundingSourceId INT, @Status TINYINT, @CurrentLease UNIQUEIDENTIFIER;
    DECLARE @CurrentLeaseUntil DATETIME2(3), @NextAttempt DATETIME2(3);
    DECLARE @AttemptCount SMALLINT, @MaxAttempts SMALLINT;
    DECLARE @ParserCode NVARCHAR(100), @ParserVersion NVARCHAR(50);
    DECLARE @ParserSettingsHash BINARY(32), @MaximumCharacters INT;
    DECLARE @MaximumPages INT, @MaximumUtf8Bytes INT;
    DECLARE @MaximumStackDepth SMALLINT;
    DECLARE @MaximumBytes INT;
    DECLARE @ContentRetentionDays SMALLINT, @AcquisitionPolicyVersion INT;
    DECLARE @RetentionUntilUtc DATETIME2(3);
    DECLARE @ExpectedETag NVARCHAR(100), @ExpectedHash BINARY(32), @ExpectedLength BIGINT;
    DECLARE @Container NVARCHAR(63), @ObjectName NVARCHAR(1024), @ETag NVARCHAR(100);
    DECLARE @ContentHash BINARY(32), @ContentLength BIGINT, @MimeType NVARCHAR(100);
    DECLARE @StorageStatus TINYINT, @ScanStatus TINYINT, @DocumentRetentionStatus TINYINT;
    DECLARE @IsEnabled BIT, @ProviderType TINYINT, @ComplianceStatus TINYINT, @LicenseStatus TINYINT;
    DECLARE @LicenseName NVARCHAR(200), @LicenseUrl NVARCHAR(2048);
    DECLARE @LicenseReviewed DATETIME2(3), @LicenseExpires DATETIME2(3), @LeaseUntil DATETIME2(3);
    DECLARE @ActivePolicyId BIGINT;
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0, @Code NVARCHAR(50) = N'not-found';

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_ExtractClaim;

    BEGIN TRY
        SELECT @JobId = jobs.Id, @DocumentId = jobs.SourceDocumentId,
               @FundingSourceId = jobs.FundingSourceId, @Status = jobs.Status,
               @CurrentLease = jobs.LeaseId, @CurrentLeaseUntil = jobs.LeaseUntilUtc,
               @NextAttempt = jobs.NextAttemptAtUtc, @AttemptCount = jobs.AttemptCount,
               @MaxAttempts = jobs.MaxAttempts, @ParserCode = jobs.ParserCode,
               @ParserVersion = jobs.ParserVersion,
               @ParserSettingsHash = jobs.ParserSettingsHash,
               @MaximumCharacters = jobs.MaximumCharacters,
               @MaximumPages = jobs.MaximumPages,
               @MaximumUtf8Bytes = jobs.MaximumUtf8Bytes,
               @MaximumStackDepth = jobs.MaximumStackDepth,
               @MaximumBytes = jobs.MaximumBytes,
               @ContentRetentionDays = jobs.ContentRetentionDays,
               @AcquisitionPolicyVersion = jobs.AcquisitionPolicyVersion,
               @RetentionUntilUtc = jobs.RetentionUntilUtc,
               @ExpectedETag = jobs.ExpectedTrustedBlobETag,
               @ExpectedHash = jobs.ExpectedContentHash,
               @ExpectedLength = jobs.ExpectedContentLength,
               @DocumentPublicId = documents.PublicId,
               @Container = documents.TrustedBlobContainer,
               @ObjectName = documents.TrustedBlobObjectName,
               @ETag = documents.TrustedBlobETag, @ContentHash = documents.ContentHash,
               @ContentLength = documents.ContentLength, @MimeType = documents.MimeType,
               @StorageStatus = documents.StorageStatus, @ScanStatus = documents.ScanStatus,
               @DocumentRetentionStatus = documents.ContentRetentionStatus,
               @IsEnabled = sources.IsEnabled, @ProviderType = policies.ProviderType,
               @ComplianceStatus = sources.ComplianceStatus,
               @LicenseStatus = policies.LicenseStatus, @LicenseName = policies.LicenseName,
               @LicenseUrl = policies.LicenseUrl,
               @LicenseReviewed = policies.LicenseReviewedAtUtc,
               @LicenseExpires = policies.LicenseExpiresAtUtc,
               @ActivePolicyId = policies.Id
        FROM dbo.FundingPlatform_SourceDocumentExtractionJobs AS jobs WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_SourceDocuments AS documents WITH (UPDLOCK, HOLDLOCK)
            ON documents.Id = jobs.SourceDocumentId
        INNER JOIN dbo.FundingPlatform_FundingSources AS sources WITH (UPDLOCK, HOLDLOCK)
            ON sources.Id = jobs.FundingSourceId
        LEFT JOIN dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions AS policies
            WITH (HOLDLOCK)
            ON policies.FundingSourceId = sources.Id
           AND policies.PolicyVersion = sources.AcquisitionPolicyVersion
        WHERE jobs.PublicId = @JobPublicId;

        IF @JobId IS NULL SET @Code = N'not-found';
        ELSE IF @Status IN (1, 2) AND @RetentionUntilUtc <= @NowUtc
        BEGIN
            UPDATE dbo.FundingPlatform_SourceDocumentExtractionJobs
            SET Status = 6, LeaseId = NULL, LeaseUntilUtc = NULL,
                LastErrorCode = N'retention-expired',
                LastErrorMessage = N'The extraction retention window expired before processing.',
                CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc
            WHERE Id = @JobId;
            UPDATE dbo.FundingPlatform_SourceDocuments
            SET ExtractionStatus = 6, UpdatedAtUtc = @NowUtc WHERE Id = @DocumentId;
            SET @Status = 6; SET @Code = N'retention-expired';
        END
        ELSE IF @Status = 2 AND @CurrentLease = @LeaseId
             AND @CurrentLeaseUntil > @NowUtc
        BEGIN
            SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'replayed';
            SET @LeaseUntil = @CurrentLeaseUntil;
        END
        ELSE IF @Status BETWEEN 3 AND 6 SET @Code = N'already-terminal';
        ELSE IF @Status = 2 AND @CurrentLeaseUntil > @NowUtc SET @Code = N'lease-active';
        ELSE IF @AttemptCount >= @MaxAttempts
        BEGIN
            UPDATE dbo.FundingPlatform_SourceDocumentExtractionJobs
            SET Status = 5, LeaseId = NULL, LeaseUntilUtc = NULL,
                LastErrorCode = N'retries-exhausted',
                LastErrorMessage = N'The extraction job exhausted its retry limit.',
                CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc
            WHERE Id = @JobId;
            UPDATE dbo.FundingPlatform_SourceDocuments
            SET ExtractionStatus = 5, UpdatedAtUtc = @NowUtc WHERE Id = @DocumentId;
            SET @Status = 5; SET @Code = N'retries-exhausted';
        END
        ELSE IF @IsEnabled <> 1 OR @ComplianceStatus <> 1 OR @ActivePolicyId IS NULL
             OR (@ProviderType IN (0, 4) AND @LicenseStatus NOT IN (1, 3))
             OR (@ProviderType IN (1, 2, 3)
                 AND (@LicenseStatus <> 1 OR @LicenseName IS NULL OR @LicenseUrl IS NULL
                      OR @LicenseReviewed IS NULL
                      OR (@LicenseExpires IS NOT NULL AND @LicenseExpires <= @NowUtc)))
        BEGIN
            UPDATE dbo.FundingPlatform_SourceDocumentExtractionJobs
            SET Status = 6, LeaseId = NULL, LeaseUntilUtc = NULL,
                LastErrorCode = N'governance-revoked',
                LastErrorMessage = N'The source is no longer authorized for extraction.',
                CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc
            WHERE Id = @JobId;
            UPDATE dbo.FundingPlatform_SourceDocuments
            SET ExtractionStatus = 6, UpdatedAtUtc = @NowUtc WHERE Id = @DocumentId;
            SET @Status = 6; SET @Code = N'governance-revoked';
        END
        ELSE IF @DocumentRetentionStatus <> 0
             OR @StorageStatus <> 2 OR @ScanStatus <> 1
             OR @ETag <> @ExpectedETag OR @ContentHash <> @ExpectedHash
             OR @ContentLength <> @ExpectedLength OR @ContentLength > @MaximumBytes
             OR @ExpectedLength > @MaximumBytes
             OR @Container IS NULL OR @ObjectName IS NULL
        BEGIN
            UPDATE dbo.FundingPlatform_SourceDocumentExtractionJobs
            SET Status = 6, LeaseId = NULL, LeaseUntilUtc = NULL,
                LastErrorCode = N'unsafe-document',
                LastErrorMessage = N'The trusted document identity no longer matches the extraction request.',
                CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc
            WHERE Id = @JobId;
            UPDATE dbo.FundingPlatform_SourceDocuments
            SET ExtractionStatus = 6, UpdatedAtUtc = @NowUtc WHERE Id = @DocumentId;
            SET @Status = 6; SET @Code = N'unsafe-document';
        END
        ELSE IF @NextAttempt > @NowUtc SET @Code = N'not-due';
        ELSE
        BEGIN
            IF @Status = 2
                INSERT INTO dbo.FundingPlatform_SourceDocumentExtractionErrors
                    (ExtractionJobId, FundingSourceId, Stage, ErrorCode, SanitizedMessage,
                     IsRetryable, OccurredAtUtc, CreatedAtUtc)
                VALUES (@JobId, @FundingSourceId, N'lease', N'lease-expired',
                        N'The previous extraction lease expired and was reclaimed.',
                        1, @NowUtc, @NowUtc);

            SET @LeaseUntil = DATEADD(SECOND, @LeaseSeconds, @NowUtc);
            UPDATE dbo.FundingPlatform_SourceDocumentExtractionJobs
            SET Status = 2, AttemptCount = AttemptCount + 1, LeaseId = @LeaseId,
                LeaseUntilUtc = @LeaseUntil, StartedAtUtc = COALESCE(StartedAtUtc, @NowUtc),
                LastErrorCode = NULL, LastErrorMessage = NULL, UpdatedAtUtc = @NowUtc
            WHERE Id = @JobId;
            UPDATE dbo.FundingPlatform_SourceDocuments
            SET ExtractionStatus = 2, UpdatedAtUtc = @NowUtc WHERE Id = @DocumentId;
            SET @AttemptCount += 1; SET @Status = 2;
            SET @Succeeded = 1; SET @Code = N'claimed';
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ExtractClaim;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           CASE WHEN @JobId IS NULL THEN NULL ELSE @JobPublicId END AS JobPublicId,
           @DocumentPublicId AS SourceDocumentPublicId, @FundingSourceId AS FundingSourceId,
           CASE WHEN @Succeeded = 1 THEN @Container END AS TrustedBlobContainer,
           CASE WHEN @Succeeded = 1 THEN @ObjectName END AS TrustedBlobObjectName,
           CASE WHEN @Succeeded = 1 THEN @ETag END AS TrustedBlobETag,
           CASE WHEN @Succeeded = 1 THEN @ContentHash END AS ContentHash,
           CASE WHEN @Succeeded = 1 THEN @ContentLength END AS ContentLength,
           CASE WHEN @Succeeded = 1 THEN @MimeType END AS MimeType,
           @ParserCode AS ParserCode, @ParserVersion AS ParserVersion,
           @ParserSettingsHash AS ParserSettingsHash,
           @MaximumCharacters AS MaximumCharacters, @MaximumPages AS MaximumPages,
           @MaximumUtf8Bytes AS MaximumUtf8Bytes,
           @MaximumStackDepth AS MaximumStackDepth,
           @MaximumBytes AS MaximumBytes,
           @ContentRetentionDays AS ContentRetentionDays,
           @AcquisitionPolicyVersion AS AcquisitionPolicyVersion,
           @RetentionUntilUtc AS RetentionUntilUtc,
           @AttemptCount AS AttemptCount, @MaxAttempts AS MaxAttempts,
           @LeaseUntil AS LeaseUntilUtc,
           @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentExtraction_RenewLease
    @JobPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @LeaseSeconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @JobPublicId IS NULL OR @LeaseId IS NULL OR @NowUtc IS NULL
        THROW 51809, N'JobPublicId, LeaseId and NowUtc are required.', 1;
    IF @LeaseSeconds NOT BETWEEN 30 AND 3600
        THROW 51810, N'LeaseSeconds must be between 30 and 3600.', 1;

    DECLARE @LeaseUntilUtc DATETIME2(3) = DATEADD(SECOND, @LeaseSeconds, @NowUtc);
    DECLARE @ActualLeaseUntilUtc DATETIME2(3), @Succeeded BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'not-found';

    UPDATE jobs WITH (UPDLOCK, ROWLOCK)
    SET LeaseUntilUtc = @LeaseUntilUtc, UpdatedAtUtc = @NowUtc
    FROM dbo.FundingPlatform_SourceDocumentExtractionJobs AS jobs
    INNER JOIN dbo.FundingPlatform_SourceDocuments AS documents
        ON documents.Id = jobs.SourceDocumentId
    WHERE jobs.PublicId = @JobPublicId AND jobs.Status = 2
      AND jobs.LeaseId = @LeaseId AND jobs.LeaseUntilUtc > @NowUtc
      AND documents.StorageStatus = 2 AND documents.ScanStatus = 1
      AND documents.ContentRetentionStatus = 0
      AND jobs.RetentionUntilUtc > @NowUtc
      AND documents.TrustedBlobETag = jobs.ExpectedTrustedBlobETag
      AND documents.ContentHash = jobs.ExpectedContentHash
      AND documents.ContentLength = jobs.ExpectedContentLength;

    IF @@ROWCOUNT = 1
    BEGIN
        SET @Succeeded = 1; SET @Code = N'renewed';
        SET @ActualLeaseUntilUtc = @LeaseUntilUtc;
    END
    ELSE
    BEGIN
        DECLARE @Status TINYINT, @CurrentLease UNIQUEIDENTIFIER;
        DECLARE @CurrentUntil DATETIME2(3), @Safe BIT;
        SELECT @Status = jobs.Status, @CurrentLease = jobs.LeaseId,
               @CurrentUntil = jobs.LeaseUntilUtc,
               @Safe = CASE WHEN documents.ContentRetentionStatus = 0
                                  AND jobs.RetentionUntilUtc > @NowUtc
                                  AND documents.StorageStatus = 2 AND documents.ScanStatus = 1
                                  AND documents.TrustedBlobETag = jobs.ExpectedTrustedBlobETag
                                  AND documents.ContentHash = jobs.ExpectedContentHash
                                  AND documents.ContentLength = jobs.ExpectedContentLength
                            THEN 1 ELSE 0 END
        FROM dbo.FundingPlatform_SourceDocumentExtractionJobs AS jobs
        INNER JOIN dbo.FundingPlatform_SourceDocuments AS documents
            ON documents.Id = jobs.SourceDocumentId
        WHERE jobs.PublicId = @JobPublicId;
        IF @Status IS NULL SET @Code = N'not-found';
        ELSE IF @Safe <> 1 SET @Code = N'unsafe-document';
        ELSE IF @Status <> 2 SET @Code = N'invalid-state';
        ELSE IF @CurrentLease <> @LeaseId OR @CurrentUntil <= @NowUtc
            SET @Code = N'stale-lease';
    END;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @ActualLeaseUntilUtc AS LeaseUntilUtc;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentExtraction_RecordEvidence
    @JobPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @Ordinal SMALLINT,
    @PageNumber INT = NULL,
    @StartOffset INT,
    @CharacterLength INT,
    @Excerpt NVARCHAR(2000),
    @EvidenceHash BINARY(32),
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @Ordinal NOT BETWEEN 1 AND 500
       OR (@PageNumber IS NOT NULL AND @PageNumber NOT BETWEEN 1 AND 250)
       OR @StartOffset NOT BETWEEN 0 AND 500000
       OR @CharacterLength NOT BETWEEN 1 AND 2000
       OR @StartOffset + @CharacterLength > 500000
       OR @Excerpt IS NULL OR DATALENGTH(@Excerpt) / 2 NOT BETWEEN 1 AND 2000
       OR @EvidenceHash IS NULL OR @NowUtc IS NULL
        THROW 51811, N'Evidence locator and bounded excerpt are required.', 1;
    IF HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
       @Excerpt COLLATE Latin1_General_100_BIN2_UTF8))) <> @EvidenceHash
        THROW 51812, N'Evidence hash does not match its excerpt.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @JobId BIGINT, @DocumentId BIGINT, @FundingSourceId INT, @Status TINYINT;
    DECLARE @CurrentLease UNIQUEIDENTIFIER, @LeaseUntil DATETIME2(3);
    DECLARE @ContentRetentionDays SMALLINT, @AcquisitionPolicyVersion INT;
    DECLARE @RetentionUntilUtc DATETIME2(3);
    DECLARE @EvidenceId BIGINT, @EvidencePublicId UNIQUEIDENTIFIER;
    DECLARE @StoredPage INT, @StoredStart INT, @StoredLength INT;
    DECLARE @StoredHash BINARY(32), @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'not-found';

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_ExtractEvidence;

    BEGIN TRY
        SELECT @JobId = Id, @DocumentId = SourceDocumentId,
               @FundingSourceId = FundingSourceId, @Status = Status,
               @CurrentLease = LeaseId, @LeaseUntil = LeaseUntilUtc,
               @ContentRetentionDays = ContentRetentionDays,
               @AcquisitionPolicyVersion = AcquisitionPolicyVersion,
               @RetentionUntilUtc = RetentionUntilUtc
        FROM dbo.FundingPlatform_SourceDocumentExtractionJobs WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @JobPublicId;

        IF @JobId IS NOT NULL
            SELECT @EvidenceId = Id, @EvidencePublicId = PublicId,
                   @StoredPage = PageNumber, @StoredStart = StartOffset,
                   @StoredLength = CharacterLength, @StoredHash = EvidenceHash
            FROM dbo.FundingPlatform_SourceDocumentExtractionEvidence WITH (UPDLOCK, HOLDLOCK)
            WHERE ExtractionJobId = @JobId AND Ordinal = @Ordinal;

        IF @JobId IS NULL SET @Code = N'not-found';
        ELSE IF @EvidenceId IS NOT NULL
        BEGIN
            IF @StoredHash = @EvidenceHash AND @StoredStart = @StartOffset
               AND @StoredLength = @CharacterLength
               AND ((@StoredPage IS NULL AND @PageNumber IS NULL) OR @StoredPage = @PageNumber)
            BEGIN SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'replayed'; END
            ELSE SET @Code = N'evidence-conflict';
        END
        ELSE IF @Status <> 2 SET @Code = N'invalid-state';
        ELSE IF @CurrentLease <> @LeaseId OR @LeaseUntil <= @NowUtc
            SET @Code = N'stale-lease';
        ELSE
        BEGIN
            DECLARE @Inserted TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER);
            INSERT INTO dbo.FundingPlatform_SourceDocumentExtractionEvidence
                (ExtractionJobId, ExtractionResultId, SourceDocumentId, FundingSourceId,
                 Ordinal, PageNumber, StartOffset, CharacterLength, Excerpt,
                 EvidenceHash, ContentRetentionDays, AcquisitionPolicyVersion,
                 RetentionUntilUtc, CreatedAtUtc)
            OUTPUT inserted.Id, inserted.PublicId INTO @Inserted (Id, PublicId)
            VALUES (@JobId, NULL, @DocumentId, @FundingSourceId, @Ordinal, @PageNumber,
                    @StartOffset, @CharacterLength, @Excerpt, @EvidenceHash,
                    @ContentRetentionDays, @AcquisitionPolicyVersion,
                    @RetentionUntilUtc, @NowUtc);
            SELECT @EvidenceId = Id, @EvidencePublicId = PublicId FROM @Inserted;
            SET @Succeeded = 1; SET @Code = N'recorded';
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ExtractEvidence;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @EvidencePublicId AS EvidencePublicId, @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentExtraction_Complete
    @JobPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @ExtractedText NVARCHAR(MAX),
    @ExtractedTextHash BINARY(32),
    @PageCount INT,
    @CharacterCount INT,
    @CompletedWithErrors BIT,
    @CompletedAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @ExtractedText IS NULL OR @ExtractedTextHash IS NULL OR @CompletedAtUtc IS NULL
        THROW 51813, N'Extraction content, hash and completion time are required.', 1;
    IF HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
       @ExtractedText COLLATE Latin1_General_100_BIN2_UTF8))) <> @ExtractedTextHash
        THROW 51814, N'Extracted text hash does not match its content.', 1;
    IF @CharacterCount <> DATALENGTH(@ExtractedText) / 2
        THROW 51815, N'CharacterCount does not match extracted text.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @JobId BIGINT, @DocumentId BIGINT, @FundingSourceId INT, @Status TINYINT;
    DECLARE @CurrentLease UNIQUEIDENTIFIER, @LeaseUntil DATETIME2(3);
    DECLARE @ParserCode NVARCHAR(100), @ParserVersion NVARCHAR(50);
    DECLARE @SettingsHash BINARY(32), @MaxChars INT, @MaxPages INT, @MaxUtf8Bytes INT;
    DECLARE @MaxStackDepth SMALLINT;
    DECLARE @MaxBytes INT;
    DECLARE @ContentRetentionDays SMALLINT, @AcquisitionPolicyVersion INT;
    DECLARE @RetentionUntilUtc DATETIME2(3);
    DECLARE @ExpectedETag NVARCHAR(100), @ExpectedHash BINARY(32), @ExpectedLength BIGINT;
    DECLARE @DocumentSafe BIT, @ResultId BIGINT, @ResultPublicId UNIQUEIDENTIFIER;
    DECLARE @StoredTextHash BINARY(32), @StoredPageCount INT, @StoredCharacterCount INT;
    DECLARE @StoredWarnings BIT, @ResultStatus TINYINT, @JobRowVersion BINARY(8);
    DECLARE @DocumentRowVersion BINARY(8), @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'not-found', @NowUtc DATETIME2(3) = SYSUTCDATETIME();

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_ExtractComplete;

    BEGIN TRY
        SELECT @JobId = jobs.Id, @DocumentId = jobs.SourceDocumentId,
               @FundingSourceId = jobs.FundingSourceId, @Status = jobs.Status,
               @CurrentLease = jobs.LeaseId, @LeaseUntil = jobs.LeaseUntilUtc,
               @ParserCode = jobs.ParserCode, @ParserVersion = jobs.ParserVersion,
               @SettingsHash = jobs.ParserSettingsHash,
               @MaxChars = jobs.MaximumCharacters, @MaxPages = jobs.MaximumPages,
               @MaxUtf8Bytes = jobs.MaximumUtf8Bytes,
               @MaxStackDepth = jobs.MaximumStackDepth,
               @MaxBytes = jobs.MaximumBytes,
               @ContentRetentionDays = jobs.ContentRetentionDays,
               @AcquisitionPolicyVersion = jobs.AcquisitionPolicyVersion,
               @RetentionUntilUtc = jobs.RetentionUntilUtc,
               @ExpectedETag = jobs.ExpectedTrustedBlobETag,
               @ExpectedHash = jobs.ExpectedContentHash,
               @ExpectedLength = jobs.ExpectedContentLength,
               @JobRowVersion = jobs.RowVersion,
               @DocumentRowVersion = documents.RowVersion,
               @DocumentSafe = CASE WHEN documents.ContentRetentionStatus = 0
                                          AND documents.StorageStatus = 2
                                          AND documents.ScanStatus = 1
                                          AND documents.TrustedBlobETag = jobs.ExpectedTrustedBlobETag
                                          AND documents.ContentHash = jobs.ExpectedContentHash
                                          AND documents.ContentLength = jobs.ExpectedContentLength
                                    THEN 1 ELSE 0 END
        FROM dbo.FundingPlatform_SourceDocumentExtractionJobs AS jobs WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_SourceDocuments AS documents WITH (UPDLOCK, HOLDLOCK)
            ON documents.Id = jobs.SourceDocumentId
        WHERE jobs.PublicId = @JobPublicId;

        IF @JobId IS NOT NULL
            SELECT @ResultId = Id, @ResultPublicId = PublicId,
                   @StoredTextHash = ExtractedTextHash, @StoredPageCount = PageCount,
                   @StoredCharacterCount = CharacterCount,
                   @StoredWarnings = CompletedWithErrors
            FROM dbo.FundingPlatform_SourceDocumentExtractionResults WITH (UPDLOCK, HOLDLOCK)
            WHERE ExtractionJobId = @JobId;

        IF @JobId IS NULL SET @Code = N'not-found';
        ELSE IF @ResultId IS NOT NULL
        BEGIN
            IF @StoredTextHash = @ExtractedTextHash AND @StoredPageCount = @PageCount
               AND @StoredCharacterCount = @CharacterCount
               AND @StoredWarnings = @CompletedWithErrors
            BEGIN
                SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'replayed';
                SET @ResultStatus = CASE WHEN @StoredWarnings = 1 THEN 4 ELSE 3 END;
            END
            ELSE SET @Code = N'result-conflict';
        END
        ELSE IF @Status <> 2 SET @Code = N'invalid-state';
        ELSE IF @CurrentLease <> @LeaseId OR @LeaseUntil <= @NowUtc
            SET @Code = N'stale-lease';
        ELSE IF @DocumentSafe <> 1 SET @Code = N'unsafe-document';
        ELSE IF @RetentionUntilUtc <= @CompletedAtUtc SET @Code = N'retention-expired';
        ELSE IF @CharacterCount NOT BETWEEN 0 AND @MaxChars
             OR @PageCount NOT BETWEEN 0 AND @MaxPages
             OR DATALENGTH(CONVERT(VARCHAR(MAX),
                 @ExtractedText COLLATE Latin1_General_100_BIN2_UTF8)) > @MaxUtf8Bytes
            SET @Code = N'extraction-limits-exceeded';
        ELSE IF EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentExtractionEvidence
              WHERE ExtractionJobId = @JobId
                AND (StartOffset + CharacterLength > @CharacterCount
                     OR (PageNumber IS NOT NULL AND PageNumber > @PageCount)))
            SET @Code = N'evidence-out-of-range';
        ELSE
        BEGIN
            SET @ResultStatus = CASE WHEN @CompletedWithErrors = 1 THEN 4 ELSE 3 END;
            DECLARE @InsertedResult TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER);
            INSERT INTO dbo.FundingPlatform_SourceDocumentExtractionResults
                (ExtractionJobId, SourceDocumentId, FundingSourceId, ParserCode, ParserVersion,
                 ParserSettingsHash, MaximumCharacters, MaximumPages, MaximumUtf8Bytes,
                 MaximumStackDepth, MaximumBytes, ContentRetentionDays,
                 AcquisitionPolicyVersion, RetentionUntilUtc,
                 ExtractedText, ExtractedTextHash, PageCount, CharacterCount,
                 CompletedWithErrors, CreatedAtUtc)
            OUTPUT inserted.Id, inserted.PublicId INTO @InsertedResult (Id, PublicId)
            VALUES (@JobId, @DocumentId, @FundingSourceId, @ParserCode, @ParserVersion,
                    @SettingsHash, @MaxChars, @MaxPages, @MaxUtf8Bytes, @MaxStackDepth,
                    @MaxBytes, @ContentRetentionDays, @AcquisitionPolicyVersion,
                    @RetentionUntilUtc, @ExtractedText,
                    @ExtractedTextHash, @PageCount, @CharacterCount,
                    @CompletedWithErrors, @CompletedAtUtc);
            SELECT @ResultId = Id, @ResultPublicId = PublicId FROM @InsertedResult;

            UPDATE dbo.FundingPlatform_SourceDocumentExtractionEvidence
            SET ExtractionResultId = @ResultId
            WHERE ExtractionJobId = @JobId AND ExtractionResultId IS NULL;

            UPDATE dbo.FundingPlatform_SourceDocumentExtractionJobs
            SET Status = @ResultStatus, LeaseId = NULL, LeaseUntilUtc = NULL,
                LastErrorCode = CASE WHEN @CompletedWithErrors = 1
                                     THEN N'extraction-warnings' ELSE NULL END,
                LastErrorMessage = CASE WHEN @CompletedWithErrors = 1
                                        THEN N'The document was extracted with bounded warnings.' ELSE NULL END,
                CompletedAtUtc = @CompletedAtUtc, UpdatedAtUtc = @NowUtc
            WHERE Id = @JobId;
            SELECT @JobRowVersion = RowVersion
            FROM dbo.FundingPlatform_SourceDocumentExtractionJobs WHERE Id = @JobId;

            UPDATE dbo.FundingPlatform_SourceDocuments
            SET ExtractionStatus = @ResultStatus, UpdatedAtUtc = @NowUtc
            WHERE Id = @DocumentId;
            SELECT @DocumentRowVersion = RowVersion
            FROM dbo.FundingPlatform_SourceDocuments WHERE Id = @DocumentId;

            SET @Succeeded = 1; SET @Code = CASE WHEN @CompletedWithErrors = 1
                                                 THEN N'completed-with-errors'
                                                 ELSE N'completed' END;
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ExtractComplete;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, @ResultPublicId AS ResultPublicId,
           @ResultStatus AS ExtractionStatus, @JobRowVersion AS JobRowVersion,
           @DocumentRowVersion AS DocumentRowVersion, @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentExtraction_Fail
    @JobPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @ErrorCode NVARCHAR(100),
    @SanitizedMessage NVARCHAR(1000),
    @IsRetryable BIT,
    @FailedAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ErrorCode = LOWER(LTRIM(RTRIM(@ErrorCode)));
    SET @SanitizedMessage = LTRIM(RTRIM(@SanitizedMessage));
    IF NULLIF(@ErrorCode, N'') IS NULL OR LEN(@ErrorCode) > 100
       OR NULLIF(@SanitizedMessage, N'') IS NULL OR LEN(@SanitizedMessage) > 1000
       OR CHARINDEX(CHAR(10), @ErrorCode + @SanitizedMessage) > 0
       OR CHARINDEX(CHAR(13), @ErrorCode + @SanitizedMessage) > 0
       OR @FailedAtUtc IS NULL
        THROW 51816, N'Bounded single-line failure context is required.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @JobId BIGINT, @DocumentId BIGINT, @FundingSourceId INT, @Status TINYINT;
    DECLARE @CurrentLease UNIQUEIDENTIFIER, @LeaseUntil DATETIME2(3);
    DECLARE @AttemptCount SMALLINT, @MaxAttempts SMALLINT, @RetrySeconds INT;
    DECLARE @StoredError NVARCHAR(100), @NextAttempt DATETIME2(3);
    DECLARE @ResultStatus TINYINT, @JobRowVersion BINARY(8), @DocumentRowVersion BINARY(8);
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0, @Code NVARCHAR(50) = N'not-found';
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_ExtractFail;

    BEGIN TRY
        SELECT @JobId = Id, @DocumentId = SourceDocumentId,
               @FundingSourceId = FundingSourceId, @Status = Status,
               @CurrentLease = LeaseId, @LeaseUntil = LeaseUntilUtc,
               @AttemptCount = AttemptCount, @MaxAttempts = MaxAttempts,
               @RetrySeconds = RetryBaseDelaySeconds, @StoredError = LastErrorCode,
               @NextAttempt = NextAttemptAtUtc, @JobRowVersion = RowVersion
        FROM dbo.FundingPlatform_SourceDocumentExtractionJobs WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @JobPublicId;

        IF @JobId IS NULL SET @Code = N'not-found';
        ELSE IF @Status = 5 AND @StoredError = @ErrorCode
        BEGIN
            SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'replayed';
            SET @ResultStatus = @Status;
        END
        ELSE IF @Status <> 2 SET @Code = N'invalid-state';
        ELSE IF @CurrentLease <> @LeaseId OR @LeaseUntil <= @NowUtc
            SET @Code = N'stale-lease';
        ELSE
        BEGIN
            INSERT INTO dbo.FundingPlatform_SourceDocumentExtractionErrors
                (ExtractionJobId, FundingSourceId, Stage, ErrorCode, SanitizedMessage,
                 IsRetryable, OccurredAtUtc, CreatedAtUtc)
            VALUES (@JobId, @FundingSourceId, N'extraction', @ErrorCode,
                    @SanitizedMessage, @IsRetryable, @FailedAtUtc, @NowUtc);

            IF @IsRetryable = 1 AND @AttemptCount < @MaxAttempts
            BEGIN
                DECLARE @DelaySeconds INT =
                    CASE WHEN @RetrySeconds
                              * CONVERT(INT, POWER(CONVERT(FLOAT, 2), @AttemptCount - 1)) > 3600
                         THEN 3600
                         ELSE @RetrySeconds
                              * CONVERT(INT, POWER(CONVERT(FLOAT, 2), @AttemptCount - 1)) END;
                SET @NextAttempt = DATEADD(SECOND, @DelaySeconds, @FailedAtUtc);
                UPDATE dbo.FundingPlatform_SourceDocumentExtractionJobs
                SET Status = 1, LeaseId = NULL, LeaseUntilUtc = NULL,
                    NextAttemptAtUtc = @NextAttempt, LastErrorCode = @ErrorCode,
                    LastErrorMessage = @SanitizedMessage, UpdatedAtUtc = @NowUtc
                WHERE Id = @JobId;
                UPDATE dbo.FundingPlatform_SourceDocuments
                SET ExtractionStatus = 1, UpdatedAtUtc = @NowUtc WHERE Id = @DocumentId;

                DECLARE @RetryMessageId UNIQUEIDENTIFIER = NEWID();
                INSERT INTO dbo.FundingPlatform_OutboxMessages
                    (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                     OccurredAtUtc, AvailableAtUtc)
                SELECT @RetryMessageId, N'SourceDocumentExtractionRequested',
                       N'SourceDocumentExtractionJob', CONVERT(NVARCHAR(100), @JobPublicId),
                       (SELECT @JobPublicId AS jobId, 1 AS [version]
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @FailedAtUtc, @NextAttempt;
                SET @ResultStatus = 1; SET @Succeeded = 1; SET @Code = N'retry-scheduled';
            END
            ELSE
            BEGIN
                UPDATE dbo.FundingPlatform_SourceDocumentExtractionJobs
                SET Status = 5, LeaseId = NULL, LeaseUntilUtc = NULL,
                    LastErrorCode = @ErrorCode, LastErrorMessage = @SanitizedMessage,
                    CompletedAtUtc = @FailedAtUtc, UpdatedAtUtc = @NowUtc
                WHERE Id = @JobId;
                UPDATE dbo.FundingPlatform_SourceDocuments
                SET ExtractionStatus = 5, UpdatedAtUtc = @NowUtc WHERE Id = @DocumentId;
                SET @ResultStatus = 5; SET @Succeeded = 1; SET @Code = N'failed';
            END;

            SELECT @JobRowVersion = RowVersion
            FROM dbo.FundingPlatform_SourceDocumentExtractionJobs WHERE Id = @JobId;
            SELECT @DocumentRowVersion = RowVersion
            FROM dbo.FundingPlatform_SourceDocuments WHERE Id = @DocumentId;
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ExtractFail;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @ResultStatus AS ExtractionStatus, @NextAttempt AS NextAttemptAtUtc,
           @JobRowVersion AS JobRowVersion, @DocumentRowVersion AS DocumentRowVersion,
           @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentExtraction_RequeueStranded
    @NowUtc DATETIME2(3),
    @BatchSize INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @NowUtc IS NULL THROW 51817, N'NowUtc is required.', 1;
    IF @BatchSize NOT BETWEEN 1 AND 100
        THROW 51818, N'BatchSize must be between 1 and 100.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @Candidates TABLE
    (
        JobId BIGINT PRIMARY KEY, JobPublicId UNIQUEIDENTIFIER,
        DocumentId BIGINT, FundingSourceId INT, Status TINYINT,
        AttemptCount SMALLINT, MaxAttempts SMALLINT, IsSafe BIT, IsGoverned BIT,
        IsRetentionValid BIT
    );
    DECLARE @Requeued TABLE
    (
        JobId BIGINT PRIMARY KEY, JobPublicId UNIQUEIDENTIFIER,
        SourceDocumentPublicId UNIQUEIDENTIFIER, FundingSourceId INT
    );

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_ExtractWatchdog;

    BEGIN TRY
        INSERT INTO @Candidates
            (JobId, JobPublicId, DocumentId, FundingSourceId, Status,
             AttemptCount, MaxAttempts, IsSafe, IsGoverned, IsRetentionValid)
        SELECT TOP (@BatchSize) jobs.Id, jobs.PublicId, jobs.SourceDocumentId,
               jobs.FundingSourceId, jobs.Status, jobs.AttemptCount, jobs.MaxAttempts,
               CASE WHEN documents.ContentRetentionStatus = 0
                          AND documents.StorageStatus = 2 AND documents.ScanStatus = 1
                          AND documents.TrustedBlobETag = jobs.ExpectedTrustedBlobETag
                          AND documents.ContentHash = jobs.ExpectedContentHash
                          AND documents.ContentLength = jobs.ExpectedContentLength
                    THEN 1 ELSE 0 END,
               CASE WHEN sources.IsEnabled = 1 AND sources.ComplianceStatus = 1
                          AND policies.Id IS NOT NULL
                          AND ((policies.ProviderType IN (0, 4)
                                AND policies.LicenseStatus IN (1, 3))
                               OR (policies.ProviderType IN (1, 2, 3)
                                   AND policies.LicenseStatus = 1
                                   AND policies.LicenseName IS NOT NULL
                                   AND policies.LicenseUrl IS NOT NULL
                                   AND policies.LicenseReviewedAtUtc IS NOT NULL
                                   AND (policies.LicenseExpiresAtUtc IS NULL
                                        OR policies.LicenseExpiresAtUtc > @NowUtc)))
                    THEN 1 ELSE 0 END
               ,CASE WHEN jobs.RetentionUntilUtc > @NowUtc THEN 1 ELSE 0 END
        FROM dbo.FundingPlatform_SourceDocumentExtractionJobs AS jobs
             WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
        INNER JOIN dbo.FundingPlatform_SourceDocuments AS documents WITH (HOLDLOCK)
            ON documents.Id = jobs.SourceDocumentId
        INNER JOIN dbo.FundingPlatform_FundingSources AS sources WITH (HOLDLOCK)
            ON sources.Id = jobs.FundingSourceId
        LEFT JOIN dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions AS policies
            WITH (HOLDLOCK)
            ON policies.FundingSourceId = sources.Id
           AND policies.PolicyVersion = sources.AcquisitionPolicyVersion
        WHERE ((jobs.Status = 1 AND jobs.NextAttemptAtUtc <= @NowUtc)
               OR (jobs.Status = 2 AND jobs.LeaseUntilUtc <= @NowUtc))
          AND NOT EXISTS
          (
              SELECT 1 FROM dbo.FundingPlatform_OutboxMessages AS outbox WITH (UPDLOCK, HOLDLOCK)
              WHERE outbox.MessageType = N'SourceDocumentExtractionRequested'
                AND outbox.AggregateType = N'SourceDocumentExtractionJob'
                AND outbox.AggregateId = CONVERT(NVARCHAR(100), jobs.PublicId)
                AND outbox.DispatchedAtUtc IS NULL
          )
          AND (jobs.Status = 2 OR COALESCE
              ((SELECT MAX(previous.DispatchedAtUtc)
                FROM dbo.FundingPlatform_OutboxMessages AS previous WITH (HOLDLOCK)
                WHERE previous.MessageType = N'SourceDocumentExtractionRequested'
                  AND previous.AggregateType = N'SourceDocumentExtractionJob'
                  AND previous.AggregateId = CONVERT(NVARCHAR(100), jobs.PublicId)),
               CONVERT(DATETIME2(3), N'1900-01-01T00:00:00'))
               <= DATEADD(MINUTE, -180, @NowUtc))
        ORDER BY CASE WHEN jobs.Status = 2 THEN jobs.LeaseUntilUtc ELSE jobs.NextAttemptAtUtc END,
                 jobs.Id;

        INSERT INTO dbo.FundingPlatform_SourceDocumentExtractionErrors
            (ExtractionJobId, FundingSourceId, Stage, ErrorCode, SanitizedMessage,
             IsRetryable, OccurredAtUtc, CreatedAtUtc)
        SELECT JobId, FundingSourceId, N'lease', N'lease-expired',
               N'The previous extraction lease expired and was requeued.', 1, @NowUtc, @NowUtc
        FROM @Candidates WHERE Status = 2 AND AttemptCount < MaxAttempts
          AND IsSafe = 1 AND IsGoverned = 1 AND IsRetentionValid = 1;

        UPDATE jobs
        SET Status = CASE WHEN candidates.IsSafe = 0 OR candidates.IsGoverned = 0
                                    OR candidates.IsRetentionValid = 0 THEN 6
                          WHEN candidates.AttemptCount >= candidates.MaxAttempts THEN 5
                          ELSE 1 END,
            LeaseId = NULL, LeaseUntilUtc = NULL,
            CompletedAtUtc = CASE WHEN candidates.IsSafe = 0 OR candidates.IsGoverned = 0
                                       OR candidates.IsRetentionValid = 0
                                       OR candidates.AttemptCount >= candidates.MaxAttempts
                                  THEN @NowUtc ELSE NULL END,
            LastErrorCode = CASE WHEN candidates.IsSafe = 0 THEN N'unsafe-document'
                                 WHEN candidates.IsGoverned = 0 THEN N'governance-revoked'
                                 WHEN candidates.IsRetentionValid = 0 THEN N'retention-expired'
                                 WHEN candidates.AttemptCount >= candidates.MaxAttempts
                                      THEN N'retries-exhausted'
                                 ELSE N'lease-expired' END,
            LastErrorMessage = CASE WHEN candidates.IsSafe = 0
                                      THEN N'The trusted document identity no longer matches.'
                                    WHEN candidates.IsGoverned = 0
                                      THEN N'The source is no longer authorized for extraction.'
                                    WHEN candidates.IsRetentionValid = 0
                                      THEN N'The extraction retention window expired.'
                                    WHEN candidates.AttemptCount >= candidates.MaxAttempts
                                      THEN N'The extraction job exhausted its retry limit.'
                                    ELSE N'The previous extraction lease expired.' END,
            UpdatedAtUtc = @NowUtc
        FROM dbo.FundingPlatform_SourceDocumentExtractionJobs AS jobs
        INNER JOIN @Candidates AS candidates ON candidates.JobId = jobs.Id;

        UPDATE documents
        SET ExtractionStatus = CASE WHEN candidates.IsSafe = 0 OR candidates.IsGoverned = 0
                                              OR candidates.IsRetentionValid = 0
                                    THEN 6
                                    WHEN candidates.AttemptCount >= candidates.MaxAttempts
                                    THEN 5 ELSE 1 END,
            UpdatedAtUtc = @NowUtc
        FROM dbo.FundingPlatform_SourceDocuments AS documents
        INNER JOIN @Candidates AS candidates ON candidates.DocumentId = documents.Id;

        INSERT INTO @Requeued (JobId, JobPublicId, SourceDocumentPublicId, FundingSourceId)
        SELECT candidates.JobId, candidates.JobPublicId, documents.PublicId,
               candidates.FundingSourceId
        FROM @Candidates AS candidates
        INNER JOIN dbo.FundingPlatform_SourceDocuments AS documents
            ON documents.Id = candidates.DocumentId
        WHERE candidates.IsSafe = 1 AND candidates.IsGoverned = 1
          AND candidates.IsRetentionValid = 1
          AND candidates.AttemptCount < candidates.MaxAttempts;

        INSERT INTO dbo.FundingPlatform_OutboxMessages
            (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
             OccurredAtUtc, AvailableAtUtc)
        SELECT NEWID(), N'SourceDocumentExtractionRequested',
               N'SourceDocumentExtractionJob', CONVERT(NVARCHAR(100), JobPublicId),
               (SELECT JobPublicId AS jobId, 1 AS [version]
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc
        FROM @Requeued;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ExtractWatchdog;
        THROW;
    END CATCH;

    SELECT JobPublicId, SourceDocumentPublicId, FundingSourceId
    FROM @Requeued ORDER BY JobId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentExtraction_AdminGet
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @SourceDocumentPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51819, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51820, N'MFA is required for this administrative operation.', 1;

    SELECT TOP (1) jobs.PublicId AS JobPublicId,
           documents.PublicId AS SourceDocumentPublicId,
           jobs.Status AS ExtractionStatus, jobs.ParserCode, jobs.ParserVersion,
           jobs.AttemptCount, jobs.MaxAttempts,
           results.PublicId AS ResultPublicId, results.PageCount, results.CharacterCount,
           results.CompletedWithErrors, results.IsContentRedacted,
           results.RedactedAtUtc, results.IsSecurityRevoked,
           CONVERT(INT, (SELECT COUNT_BIG(1)
                         FROM dbo.FundingPlatform_SourceDocumentExtractionEvidence AS evidence
                         WHERE evidence.ExtractionJobId = jobs.Id)) AS EvidenceCount,
           CONVERT(INT, (SELECT COUNT_BIG(1)
                         FROM dbo.FundingPlatform_SourceDocumentExtractionErrors AS errors
                         WHERE errors.ExtractionJobId = jobs.Id)) AS ErrorCount,
           CASE WHEN results.Id IS NULL OR results.IsContentRedacted = 1
                     OR results.IsSecurityRevoked = 1 THEN NULL
                ELSE LEFT(results.ExtractedText, 4000) END AS TextPreview,
           CASE WHEN results.IsContentRedacted = 1
                THEN N'content-retention-redacted'
                ELSE jobs.LastErrorCode END AS LastErrorCode,
           jobs.CreatedAtUtc, jobs.StartedAtUtc,
           jobs.CompletedAtUtc, jobs.UpdatedAtUtc,
           jobs.RowVersion AS JobRowVersion,
           documents.RowVersion AS DocumentRowVersion
    FROM dbo.FundingPlatform_SourceDocuments AS documents
    LEFT JOIN dbo.FundingPlatform_SourceDocumentExtractionJobs AS jobs
        ON jobs.SourceDocumentId = documents.Id
    LEFT JOIN dbo.FundingPlatform_SourceDocumentExtractionResults AS results
        ON results.ExtractionJobId = jobs.Id
    WHERE documents.PublicId = @SourceDocumentPublicId
    ORDER BY jobs.Id DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentExtractionEvidence_AdminList
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @JobPublicId UNIQUEIDENTIFIER,
    @Page INT = 1,
    @PageSize INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51821, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51822, N'MFA is required for this administrative operation.', 1;
    IF @Page < 1 OR @PageSize NOT BETWEEN 1 AND 100
        THROW 51823, N'Page and PageSize are outside the allowed range.', 1;

    DECLARE @JobId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_SourceDocumentExtractionJobs
         WHERE PublicId = @JobPublicId);
    DECLARE @TotalCount BIGINT =
        (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SourceDocumentExtractionEvidence
         WHERE ExtractionJobId = @JobId);

    SELECT evidence.PublicId AS EvidencePublicId, evidence.Ordinal,
           evidence.PageNumber, evidence.StartOffset, evidence.CharacterLength,
           CASE WHEN evidence.IsContentRedacted = 1
                     OR results.IsSecurityRevoked = 1
                     OR jobs.LastErrorCode = N'security-scan-revoked'
                THEN NULL ELSE evidence.Excerpt END AS Excerpt,
           evidence.IsContentRedacted,
           COALESCE(results.IsSecurityRevoked,
                    CASE WHEN jobs.LastErrorCode = N'security-scan-revoked'
                         THEN CONVERT(BIT, 1) ELSE CONVERT(BIT, 0) END)
               AS IsSecurityRevoked,
           evidence.CreatedAtUtc, @TotalCount AS TotalCount
    FROM dbo.FundingPlatform_SourceDocumentExtractionEvidence AS evidence
    INNER JOIN dbo.FundingPlatform_SourceDocumentExtractionJobs AS jobs
        ON jobs.Id = evidence.ExtractionJobId
    LEFT JOIN dbo.FundingPlatform_SourceDocumentExtractionResults AS results
        ON results.Id = evidence.ExtractionResultId
    WHERE evidence.ExtractionJobId = @JobId
    ORDER BY evidence.Ordinal, evidence.Id
    OFFSET (@Page - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

/* Historical outbox rows also contain event-ledger records. They are retained
   for audit but terminalized by an explicit allowlist so they never enter a
   command worker. Unknown types remain pending (fail closed). */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge
    @BatchSize INT,
    @NowUtc DATETIME2(3),
    @AcknowledgedCount INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @BatchSize NOT BETWEEN 1 AND 500
        THROW 51861, N'BatchSize must be between 1 and 500.', 1;
    IF @NowUtc IS NULL THROW 51862, N'NowUtc is required.', 1;

    ;WITH EventOnly AS
    (
        SELECT TOP (@BatchSize) *
        FROM dbo.FundingPlatform_OutboxMessages
             WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
        WHERE DispatchedAtUtc IS NULL AND AvailableAtUtc <= @NowUtc
          AND (LeaseUntilUtc IS NULL OR LeaseUntilUtc <= @NowUtc)
          AND MessageType IN
          (
              N'OrganizationCreated', N'OrganizationProfileChanged',
              N'ProjectCreated', N'ProjectChanged', N'ProjectPublicationRequested',
              N'ProjectPublished', N'ProjectRejected', N'ProjectArchived',
              N'FunderDraftCreated', N'FunderChanged', N'FunderPublicationRequested',
              N'FunderPublished', N'FunderRejected', N'FunderCorrectionStarted',
              N'FunderDeactivated',
              N'FundingOpportunityDraftCreated', N'FundingOpportunityChanged',
              N'FundingOpportunityPublicationRequested', N'FundingOpportunityPublished',
              N'FundingOpportunityRejected', N'FundingOpportunityCorrectionStarted',
              N'FundingOpportunityDeactivated', N'FundingOpportunityDraftStaged',
              N'FundingOpportunityRevisionStaged', N'FundingOpportunityDraftChanged',
              N'SourceDocumentUploadIntentCreated', N'SourceDocumentUploadIntentExpired',
              N'SourceDocumentUploadIntentRejected', N'SourceDocumentQuarantined',
              N'SourceDocumentFinalized', N'SourceDocumentScanCompleted',
              N'SourceDocumentContentDeletionRequested',
              N'SourceDocumentScanRetryRequested'
          )
        ORDER BY AvailableAtUtc, Id
    )
    UPDATE EventOnly
    SET DispatchedAtUtc = @NowUtc, LeaseOwner = NULL, LeaseUntilUtc = NULL,
        LastError = CASE WHEN MessageType = N'SourceDocumentScanRetryRequested'
                         THEN N'unsupported-command-not-delivered'
                         ELSE N'event-ledger-acknowledged' END;
    SET @AcknowledgedCount = @@ROWCOUNT;
END;
GO

/* The command dispatcher is intentionally widened only to executable request
   messages. Event-ledger rows above are never returned to parser workers. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ImportRunOutbox_Claim
    @LeaseOwner NVARCHAR(100),
    @BatchSize INT,
    @LeaseSeconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NULLIF(LTRIM(RTRIM(@LeaseOwner)), N'') IS NULL
        THROW 51824, N'LeaseOwner is required.', 1;
    IF @BatchSize NOT BETWEEN 1 AND 100
        THROW 51825, N'BatchSize must be between 1 and 100.', 1;
    IF @LeaseSeconds NOT BETWEEN 5 AND 3600
        THROW 51826, N'LeaseSeconds must be between 5 and 3600.', 1;

    DECLARE @AcknowledgedEventCount INT;
    EXEC dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge
        @BatchSize = 500, @NowUtc = @NowUtc,
        @AcknowledgedCount = @AcknowledgedEventCount OUTPUT;

    ;WITH Claimable AS
    (
        SELECT TOP (@BatchSize) *
        FROM dbo.FundingPlatform_OutboxMessages
             WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
        WHERE MessageType IN (N'ImportRunRequested', N'SourceDocumentExtractionRequested')
          AND ((MessageType = N'ImportRunRequested'
                AND AggregateType = N'ImportRun'
                AND TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(PayloadJson, N'$.runId'))
                    = TRY_CONVERT(UNIQUEIDENTIFIER, AggregateId)
                AND TRY_CONVERT(INT, JSON_VALUE(PayloadJson, N'$.version')) = 1)
               OR (MessageType = N'SourceDocumentExtractionRequested'
                   AND AggregateType = N'SourceDocumentExtractionJob'
                   AND TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(PayloadJson, N'$.jobId'))
                       = TRY_CONVERT(UNIQUEIDENTIFIER, AggregateId)
                   AND TRY_CONVERT(INT, JSON_VALUE(PayloadJson, N'$.version')) = 1))
          AND DispatchedAtUtc IS NULL AND AvailableAtUtc <= @NowUtc
          AND (LeaseUntilUtc IS NULL OR LeaseUntilUtc <= @NowUtc)
        ORDER BY AvailableAtUtc, Id
    )
    UPDATE Claimable
    SET LeaseOwner = @LeaseOwner,
        LeaseUntilUtc = DATEADD(SECOND, @LeaseSeconds, @NowUtc),
        AttemptCount = AttemptCount + 1
    OUTPUT inserted.Id, inserted.MessageId, inserted.MessageType,
           inserted.AggregateType, inserted.AggregateId, inserted.PayloadJson,
           inserted.OccurredAtUtc, inserted.AttemptCount, inserted.LeaseUntilUtc;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_EventIngressTrustPolicy_AdminList
    @SuperAdminUserPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ActorUserId BIGINT;
    EXEC dbo.FundingPlatform_usp_AdminActor_Lock
        @AdminUserPublicId = @SuperAdminUserPublicId,
        @ActorUserId = @ActorUserId OUTPUT;
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_UserRoles AS userRoles
        INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
        WHERE userRoles.UserId = @ActorUserId AND roles.NormalizedName = N'SUPERADMIN')
        THROW 51827, N'Active SuperAdmin role is required.', 1;

    SELECT policies.PublicId AS PolicyPublicId, policies.Provider,
           policies.TenantId, policies.PrincipalObjectId, policies.ApplicationClientId,
           policies.TopicResourceId AS ExpectedTopicResourceId,
           policies.EventSubscriptionName, policies.StorageAccountResourceId,
           policies.StorageAccountHost, policies.QuarantineBlobContainer,
           policies.IsEnabled, policies.ValidFromUtc, policies.ExpiresAtUtc,
           policies.CreatedAtUtc, policies.UpdatedAtUtc, policies.RowVersion
    FROM dbo.FundingPlatform_EventIngressTrustPolicies AS policies
    ORDER BY policies.IsEnabled DESC, policies.UpdatedAtUtc DESC, policies.Id DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_EventIngressTrustPolicy_Upsert
    @SuperAdminUserPublicId UNIQUEIDENTIFIER,
    @PolicyPublicId UNIQUEIDENTIFIER = NULL,
    @ExpectedRowVersion BINARY(8) = NULL,
    @TenantId UNIQUEIDENTIFIER,
    @PrincipalObjectId UNIQUEIDENTIFIER,
    @ApplicationClientId UNIQUEIDENTIFIER,
    @ExpectedTopicResourceId NVARCHAR(500),
    @EventSubscriptionName NVARCHAR(100),
    @StorageAccountResourceId NVARCHAR(500),
    @StorageAccountHost NVARCHAR(253),
    @QuarantineBlobContainer NVARCHAR(63),
    @IsEnabled BIT,
    @ValidFromUtc DATETIME2(3),
    @ExpiresAtUtc DATETIME2(3) = NULL,
    @Reason NVARCHAR(500),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @CorrelationId NVARCHAR(100),
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET @ExpectedTopicResourceId = LOWER(LTRIM(RTRIM(@ExpectedTopicResourceId)));
    SET @StorageAccountResourceId = LOWER(LTRIM(RTRIM(@StorageAccountResourceId)));
    SET @StorageAccountHost = LOWER(LTRIM(RTRIM(@StorageAccountHost)));
    SET @QuarantineBlobContainer = LOWER(LTRIM(RTRIM(@QuarantineBlobContainer)));
    SET @EventSubscriptionName = LTRIM(RTRIM(@EventSubscriptionName));
    SET @Reason = LTRIM(RTRIM(@Reason));
    SET @CorrelationId = LTRIM(RTRIM(@CorrelationId));

    IF @TenantId IS NULL OR @PrincipalObjectId IS NULL OR @ApplicationClientId IS NULL
       OR @ValidFromUtc IS NULL OR @NowUtc IS NULL
       OR @IdempotencyKeyHash IS NULL OR @RequestHash IS NULL
       OR NULLIF(@ExpectedTopicResourceId, N'') IS NULL
       OR LEN(@ExpectedTopicResourceId) > 500
       OR CHARINDEX(CHAR(10), @ExpectedTopicResourceId) > 0
       OR CHARINDEX(CHAR(13), @ExpectedTopicResourceId) > 0
       OR CHARINDEX(0x0000, CONVERT(VARBINARY(1000), @ExpectedTopicResourceId)) > 0
       OR NULLIF(@StorageAccountResourceId, N'') IS NULL
       OR LEN(@StorageAccountResourceId) > 500
       OR @StorageAccountResourceId NOT LIKE
          N'/subscriptions/%/resourcegroups/%/providers/microsoft.storage/storageaccounts/%'
       OR CHARINDEX(CHAR(10), @StorageAccountResourceId) > 0
       OR CHARINDEX(CHAR(13), @StorageAccountResourceId) > 0
       OR CHARINDEX(0x0000, CONVERT(VARBINARY(1000), @StorageAccountResourceId)) > 0
       OR NULLIF(@StorageAccountHost, N'') IS NULL
       OR @StorageAccountHost <>
          RIGHT(@StorageAccountResourceId,
                NULLIF(CHARINDEX(N'/', REVERSE(@StorageAccountResourceId)), 0) - 1)
          + N'.blob.core.windows.net'
       OR NULLIF(@QuarantineBlobContainer, N'') IS NULL
       OR NULLIF(@EventSubscriptionName, N'') IS NULL
       OR NULLIF(@Reason, N'') IS NULL OR LEN(@Reason) > 500
       OR CHARINDEX(CHAR(10), @Reason) > 0 OR CHARINDEX(CHAR(13), @Reason) > 0
       OR NULLIF(@CorrelationId, N'') IS NULL OR LEN(@CorrelationId) > 100
       OR @CorrelationId COLLATE Latin1_General_100_BIN2
          LIKE N'%[^-A-Za-z0-9:_.]%' COLLATE Latin1_General_100_BIN2
       OR (@ExpiresAtUtc IS NOT NULL AND @ExpiresAtUtc <= @ValidFromUtc)
        THROW 51828, N'Valid bounded trust-policy metadata is required.', 1;

    /* Validate before enabling XACT_ABORT so a caller-owned transaction can
       safely observe bounded-input failures without becoming uncommittable. */
    SET XACT_ABORT ON;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @ActorUserId BIGINT, @PolicyId INT, @StoredRequestHash BINARY(32);
    DECLARE @StoredPolicyPublicId UNIQUEIDENTIFIER, @StoredEnabled BIT;
    DECLARE @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0, @Code NVARCHAR(50) = N'not-found';

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_TrustUpsert;

    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId = @SuperAdminUserPublicId,
            @ActorUserId = @ActorUserId OUTPUT;
        IF NOT EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_UserRoles AS userRoles WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.FundingPlatform_Roles AS roles WITH (UPDLOCK, HOLDLOCK)
                ON roles.Id = userRoles.RoleId
            WHERE userRoles.UserId = @ActorUserId AND roles.NormalizedName = N'SUPERADMIN')
            THROW 51829, N'Active SuperAdmin role is required.', 1;

        SELECT @StoredRequestHash = events.RequestHash,
               @PolicyId = policies.Id, @StoredPolicyPublicId = policies.PublicId,
               @StoredEnabled = policies.IsEnabled, @ResultRowVersion = policies.RowVersion
        FROM dbo.FundingPlatform_EventIngressTrustPolicyEvents AS events
             WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_EventIngressTrustPolicies AS policies WITH (HOLDLOCK)
            ON policies.Id = events.TrustPolicyId
        WHERE events.ActorUserId = @ActorUserId
          AND events.IdempotencyKeyHash = @IdempotencyKeyHash;

        IF @StoredRequestHash IS NOT NULL
        BEGIN
            IF @StoredRequestHash = @RequestHash
            BEGIN
                SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'replayed';
            END
            ELSE
            BEGIN
                SET @PolicyId = NULL; SET @StoredPolicyPublicId = NULL;
                SET @StoredEnabled = NULL; SET @ResultRowVersion = NULL;
                SET @Code = N'idempotency-conflict';
            END;
        END
        ELSE
        BEGIN
            SET @PolicyId = NULL;
            IF @PolicyPublicId IS NOT NULL
                SELECT @PolicyId = Id, @StoredPolicyPublicId = PublicId,
                       @CurrentRowVersion = RowVersion
                FROM dbo.FundingPlatform_EventIngressTrustPolicies WITH (UPDLOCK, HOLDLOCK)
                WHERE PublicId = @PolicyPublicId;
            ELSE
                SELECT @PolicyId = Id, @StoredPolicyPublicId = PublicId,
                       @CurrentRowVersion = RowVersion
                FROM dbo.FundingPlatform_EventIngressTrustPolicies WITH (UPDLOCK, HOLDLOCK)
                WHERE Provider = 1 AND TenantId = @TenantId
                  AND PrincipalObjectId = @PrincipalObjectId
                  AND ApplicationClientId = @ApplicationClientId
                  AND TopicResourceId = @ExpectedTopicResourceId
                  AND StorageAccountResourceId = @StorageAccountResourceId;

            IF @PolicyPublicId IS NOT NULL AND @PolicyId IS NULL SET @Code = N'not-found';
            ELSE IF @PolicyId IS NOT NULL AND @ExpectedRowVersion IS NULL
                SET @Code = N'precondition-required';
            ELSE IF @PolicyId IS NOT NULL AND @CurrentRowVersion <> @ExpectedRowVersion
                SET @Code = N'etag-conflict';
            ELSE
            BEGIN
                IF @PolicyId IS NULL
                BEGIN
                    DECLARE @InsertedPolicy TABLE
                        (Id INT, PublicId UNIQUEIDENTIFIER, RowVersion BINARY(8));
                    INSERT INTO dbo.FundingPlatform_EventIngressTrustPolicies
                        (Provider, TenantId, PrincipalObjectId, ApplicationClientId,
                         TopicResourceId, EventSubscriptionName, StorageAccountResourceId,
                         StorageAccountHost, QuarantineBlobContainer, IsEnabled,
                         ValidFromUtc, ExpiresAtUtc, CreatedByUserId, CreatedAtUtc, UpdatedAtUtc)
                    OUTPUT inserted.Id, inserted.PublicId, inserted.RowVersion
                        INTO @InsertedPolicy (Id, PublicId, RowVersion)
                    VALUES (1, @TenantId, @PrincipalObjectId, @ApplicationClientId,
                            @ExpectedTopicResourceId, @EventSubscriptionName,
                            @StorageAccountResourceId, @StorageAccountHost,
                            @QuarantineBlobContainer, @IsEnabled, @ValidFromUtc,
                            @ExpiresAtUtc, @ActorUserId, @NowUtc, @NowUtc);
                    SELECT @PolicyId = Id, @StoredPolicyPublicId = PublicId,
                           @ResultRowVersion = RowVersion FROM @InsertedPolicy;
                    SET @Code = N'created';
                END
                ELSE
                BEGIN
                    IF NOT EXISTS
                       (SELECT 1 FROM dbo.FundingPlatform_EventIngressTrustPolicies
                        WHERE Id = @PolicyId AND TenantId = @TenantId
                          AND PrincipalObjectId = @PrincipalObjectId
                          AND ApplicationClientId = @ApplicationClientId
                          AND TopicResourceId = @ExpectedTopicResourceId
                          AND StorageAccountResourceId = @StorageAccountResourceId)
                        THROW 51830, N'Trust-policy identity is immutable; create a replacement.', 1;

                    UPDATE dbo.FundingPlatform_EventIngressTrustPolicies
                    SET EventSubscriptionName = @EventSubscriptionName,
                        StorageAccountHost = @StorageAccountHost,
                        QuarantineBlobContainer = @QuarantineBlobContainer,
                        IsEnabled = @IsEnabled, ValidFromUtc = @ValidFromUtc,
                        ExpiresAtUtc = @ExpiresAtUtc, UpdatedAtUtc = @NowUtc
                    WHERE Id = @PolicyId;
                    SELECT @ResultRowVersion = RowVersion
                    FROM dbo.FundingPlatform_EventIngressTrustPolicies WHERE Id = @PolicyId;
                    SET @Code = N'updated';
                END;

                INSERT INTO dbo.FundingPlatform_EventIngressTrustPolicyEvents
                    (TrustPolicyId, ActorUserId, Action, Reason, CorrelationId,
                     IdempotencyKeyHash, RequestHash, CreatedAtUtc)
                VALUES (@PolicyId, @ActorUserId, CASE WHEN @IsEnabled = 1 THEN 1 ELSE 2 END,
                        @Reason, @CorrelationId, @IdempotencyKeyHash, @RequestHash, @NowUtc);
                SET @StoredEnabled = @IsEnabled; SET @Succeeded = 1;
            END;
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_TrustUpsert;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @StoredPolicyPublicId AS PolicyPublicId, @StoredEnabled AS IsEnabled,
           @ResultRowVersion AS RowVersion, @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Record
    @ProviderEventId NVARCHAR(200),
    @PayloadHash BINARY(32),
    @AuthenticatedTenantId UNIQUEIDENTIFIER,
    @AuthenticatedPrincipalId UNIQUEIDENTIFIER,
    @ApplicationClientId UNIQUEIDENTIFIER,
    @TopicResourceId NVARCHAR(500),
    @EventSubscriptionName NVARCHAR(100),
    @StorageAccountResourceId NVARCHAR(500),
    @BlobHost NVARCHAR(253),
    @BlobContainer NVARCHAR(63),
    @BlobObjectName NVARCHAR(1024),
    @BlobETag NVARCHAR(100),
    @ReportedContentHash BINARY(32) = NULL,
    @ToStatus TINYINT,
    @ResultCode NVARCHAR(100),
    @OccurredAtUtc DATETIME2(3),
    @ReceivedAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ProviderEventId = LTRIM(RTRIM(@ProviderEventId));
    SET @TopicResourceId = LOWER(LTRIM(RTRIM(@TopicResourceId)));
    SET @StorageAccountResourceId = LOWER(LTRIM(RTRIM(@StorageAccountResourceId)));
    SET @BlobHost = LOWER(LTRIM(RTRIM(@BlobHost)));
    SET @BlobContainer = LOWER(LTRIM(RTRIM(@BlobContainer)));
    SET @BlobObjectName = LTRIM(RTRIM(@BlobObjectName));
    SET @BlobETag = LTRIM(RTRIM(@BlobETag));
    SET @EventSubscriptionName = LTRIM(RTRIM(@EventSubscriptionName));
    SET @ResultCode = LOWER(LTRIM(RTRIM(@ResultCode)));

    IF NULLIF(@ProviderEventId, N'') IS NULL OR LEN(@ProviderEventId) > 200
       OR @PayloadHash IS NULL OR @AuthenticatedTenantId IS NULL
       OR @AuthenticatedPrincipalId IS NULL OR @ApplicationClientId IS NULL
       OR NULLIF(@TopicResourceId, N'') IS NULL OR LEN(@TopicResourceId) > 500
       OR CHARINDEX(CHAR(10), @TopicResourceId) > 0
       OR CHARINDEX(CHAR(13), @TopicResourceId) > 0
       OR CHARINDEX(0x0000, CONVERT(VARBINARY(1000), @TopicResourceId)) > 0
       OR NULLIF(@StorageAccountResourceId, N'') IS NULL
       OR LEN(@StorageAccountResourceId) > 500
       OR CHARINDEX(CHAR(10), @StorageAccountResourceId) > 0
       OR CHARINDEX(CHAR(13), @StorageAccountResourceId) > 0
       OR CHARINDEX(0x0000, CONVERT(VARBINARY(1000), @StorageAccountResourceId)) > 0
       OR NULLIF(@EventSubscriptionName, N'') IS NULL OR LEN(@EventSubscriptionName) > 100
       OR NULLIF(@BlobHost, N'') IS NULL OR LEN(@BlobHost) > 253
       OR LEN(@BlobContainer) NOT BETWEEN 3 AND 63
       OR NULLIF(@BlobObjectName, N'') IS NULL OR LEN(@BlobObjectName) > 1024
       OR LEFT(@BlobObjectName, 1) = N'/' OR CHARINDEX(N'?', @BlobObjectName) > 0
       OR CHARINDEX(N'#', @BlobObjectName) > 0
       OR LEN(@BlobETag) NOT BETWEEN 3 AND 100
       OR LEFT(@BlobETag, 1) <> N'"' OR RIGHT(@BlobETag, 1) <> N'"'
       OR @ToStatus NOT BETWEEN 1 AND 4
       OR (@ToStatus IN (1, 2) AND @ReportedContentHash IS NULL)
       OR NULLIF(@ResultCode, N'') IS NULL OR LEN(@ResultCode) > 100
       OR @ResultCode LIKE N'%[^-a-z0-9._]%' COLLATE Latin1_General_100_BIN2
       OR @OccurredAtUtc IS NULL OR @ReceivedAtUtc IS NULL
        THROW 51831, N'Authenticated bounded Defender receipt metadata is required.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @PolicyId INT, @DocumentId BIGINT, @DocumentPublicId UNIQUEIDENTIFIER;
    DECLARE @StoredETag NVARCHAR(100), @StoredHash BINARY(32), @ContentLength BIGINT;
    DECLARE @MimeType NVARCHAR(100), @StorageStatus TINYINT, @ScanStatus TINYINT;
    DECLARE @ContentRetentionStatus TINYINT;
    DECLARE @ScanCompletedAtUtc DATETIME2(3);
    DECLARE @ReceiptId BIGINT, @ReceiptPublicId UNIQUEIDENTIFIER;
    DECLARE @ExistingPayloadHash BINARY(32), @ExistingDocumentId BIGINT;
    DECLARE @ExistingTenant UNIQUEIDENTIFIER, @ExistingPrincipal UNIQUEIDENTIFIER;
    DECLARE @ExistingApp UNIQUEIDENTIFIER, @ExistingTopic NVARCHAR(500);
    DECLARE @ExistingSubscription NVARCHAR(100);
    DECLARE @ExistingStorage NVARCHAR(500), @ExistingHost NVARCHAR(253);
    DECLARE @ExistingContainer NVARCHAR(63), @ExistingObject NVARCHAR(1024);
    DECLARE @ExistingETag NVARCHAR(100), @ExistingReportedHash BINARY(32);
    DECLARE @ExistingToStatus TINYINT, @ExistingResultCode NVARCHAR(100);
    DECLARE @ReceiptStatus TINYINT, @OutcomeCode NVARCHAR(100);
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0, @Code NVARCHAR(50) = N'unauthorized';
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_DefenderReceipt;

    BEGIN TRY
        SELECT @ReceiptId = Id, @ReceiptPublicId = PublicId,
               @ExistingPayloadHash = PayloadHash, @ExistingDocumentId = SourceDocumentId,
               @ExistingTenant = AuthenticatedTenantId,
               @ExistingPrincipal = AuthenticatedPrincipalId,
               @ExistingApp = ApplicationClientId, @ExistingTopic = TopicResourceId,
               @ExistingSubscription = EventSubscriptionName,
               @ExistingStorage = StorageAccountResourceId, @ExistingHost = BlobHost,
               @ExistingContainer = BlobContainer, @ExistingObject = BlobObjectName,
               @ExistingETag = BlobETag, @ExistingReportedHash = ReportedContentHash,
               @ExistingToStatus = ToStatus, @ExistingResultCode = ResultCode,
               @ReceiptStatus = ReceiptStatus, @OutcomeCode = OutcomeCode
        FROM dbo.FundingPlatform_SourceDocumentDefenderReceipts WITH (UPDLOCK, HOLDLOCK)
        WHERE Provider = 1 AND ProviderEventId = @ProviderEventId;

        IF @ReceiptId IS NOT NULL
        BEGIN
            IF @ExistingPayloadHash = @PayloadHash
               AND @ExistingTenant = @AuthenticatedTenantId
               AND @ExistingPrincipal = @AuthenticatedPrincipalId
               AND @ExistingApp = @ApplicationClientId
               AND @ExistingTopic = @TopicResourceId
               AND @ExistingSubscription = @EventSubscriptionName
               AND @ExistingStorage = @StorageAccountResourceId
               AND @ExistingHost = @BlobHost
               AND @ExistingContainer = @BlobContainer
               AND @ExistingObject = @BlobObjectName
               AND @ExistingETag = @BlobETag
               AND ((@ExistingReportedHash IS NULL AND @ReportedContentHash IS NULL)
                    OR @ExistingReportedHash = @ReportedContentHash)
               AND @ExistingToStatus = @ToStatus AND @ExistingResultCode = @ResultCode
            BEGIN
                SET @WasReplay = 1;
                SET @Succeeded = CASE WHEN @ReceiptStatus IN (0, 1) THEN 1 ELSE 0 END;
                SET @Code = CASE @ReceiptStatus
                              WHEN 0 THEN N'replayed-accepted'
                              WHEN 1 THEN N'replayed-applied'
                              WHEN 2 THEN N'replayed-ignored'
                              ELSE N'replayed-rejected' END;
                SET @DocumentId = @ExistingDocumentId;
            END
            ELSE
            BEGIN
                SET @ReceiptPublicId = NULL; SET @DocumentId = NULL;
                SET @ReceiptStatus = NULL; SET @Code = N'event-conflict';
            END;
        END
        ELSE
        BEGIN
            SELECT @PolicyId = Id
            FROM dbo.FundingPlatform_EventIngressTrustPolicies WITH (UPDLOCK, HOLDLOCK)
            WHERE Provider = 1 AND TenantId = @AuthenticatedTenantId
              AND PrincipalObjectId = @AuthenticatedPrincipalId
              AND ApplicationClientId = @ApplicationClientId
              AND TopicResourceId = @TopicResourceId
              AND EventSubscriptionName = @EventSubscriptionName
              AND StorageAccountResourceId = @StorageAccountResourceId
              AND StorageAccountHost = @BlobHost
              AND QuarantineBlobContainer = @BlobContainer
              AND IsEnabled = 1 AND ValidFromUtc <= @ReceivedAtUtc
              AND (ExpiresAtUtc IS NULL OR ExpiresAtUtc > @ReceivedAtUtc);

            IF @PolicyId IS NULL SET @Code = N'unauthorized';
            ELSE
            BEGIN
                SELECT @DocumentId = Id, @DocumentPublicId = PublicId,
                       @StoredETag = BlobETag, @StoredHash = ContentHash,
                       @ContentLength = ContentLength, @MimeType = MimeType,
                       @StorageStatus = StorageStatus, @ScanStatus = ScanStatus,
                       @ContentRetentionStatus = ContentRetentionStatus,
                       @ScanCompletedAtUtc = ScanCompletedAtUtc
                FROM dbo.FundingPlatform_SourceDocuments WITH (UPDLOCK, HOLDLOCK)
                WHERE BlobContainer = @BlobContainer AND BlobObjectName = @BlobObjectName
                  AND ScanProvider = 1;

                SET @ReceiptStatus = 0;
                SET @OutcomeCode = NULL;
                IF @DocumentId IS NULL
                BEGIN SET @ReceiptStatus = 3; SET @OutcomeCode = N'document-not-found'; END
                ELSE IF @StoredETag <> @BlobETag
                BEGIN SET @ReceiptStatus = 3; SET @OutcomeCode = N'blob-etag-mismatch'; END
                ELSE IF @ReportedContentHash IS NOT NULL AND @StoredHash <> @ReportedContentHash
                BEGIN SET @ReceiptStatus = 3; SET @OutcomeCode = N'content-hash-mismatch'; END
                ELSE IF @ContentRetentionStatus IN (1, 2, 3)
                BEGIN
                    SET @ReceiptStatus = 2;
                    SET @OutcomeCode = N'content-retention-ignored';
                END
                ELSE IF @OccurredAtUtc < DATEADD(DAY, -1, @ReceivedAtUtc)
                     OR @OccurredAtUtc > DATEADD(MINUTE, 5, @ReceivedAtUtc)
                BEGIN SET @ReceiptStatus = 3; SET @OutcomeCode = N'invalid-event-time'; END
                ELSE IF @StorageStatus = 1 AND @ScanStatus = 0
                BEGIN
                    /* Normal first result; ReceiptStatus remains accepted. */
                    SET @ReceiptStatus = 0;
                END
                ELSE IF @ScanCompletedAtUtc IS NOT NULL
                     AND @OccurredAtUtc <= @ScanCompletedAtUtc
                BEGIN SET @ReceiptStatus = 2; SET @OutcomeCode = N'stale-scan-result'; END
                ELSE IF @ScanCompletedAtUtc IS NOT NULL AND @ToStatus = @ScanStatus
                BEGIN SET @ReceiptStatus = 2; SET @OutcomeCode = N'duplicate-scan-result'; END
                ELSE IF @StorageStatus = 2 AND @ScanStatus = 1
                     AND @ToStatus IN (2, 3, 4)
                     AND @ReportedContentHash IS NULL
                BEGIN
                    SET @ReceiptStatus = 3;
                    SET @OutcomeCode = N'content-hash-required-for-supersede';
                END
                ELSE IF @StorageStatus = 2 AND @ScanStatus = 1
                     AND @ToStatus IN (2, 3, 4)
                BEGIN
                    /* A later authenticated threat can revoke a trusted result. */
                    SET @ReceiptStatus = 0;
                END
                ELSE IF @ScanStatus IN (1, 2, 3, 4)
                BEGIN
                    SET @ReceiptStatus = 3;
                    SET @OutcomeCode = N'terminal-scan-result-conflict';
                END
                ELSE
                BEGIN SET @ReceiptStatus = 3; SET @OutcomeCode = N'invalid-document-state'; END;

                DECLARE @InsertedReceipt TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER);
                INSERT INTO dbo.FundingPlatform_SourceDocumentDefenderReceipts
                    (TrustPolicyId, SourceDocumentId, Provider, ProviderEventId, PayloadHash,
                     TopicResourceId, AuthenticatedTenantId, AuthenticatedPrincipalId,
                     ApplicationClientId, EventSubscriptionName, StorageAccountResourceId,
                     BlobHost, BlobContainer, BlobObjectName, BlobETag, ReportedContentHash,
                     ToStatus, ResultCode, ReceiptStatus, OutcomeCode, OccurredAtUtc,
                     ReceivedAtUtc, FinalizedAtUtc, CreatedAtUtc)
                OUTPUT inserted.Id, inserted.PublicId INTO @InsertedReceipt (Id, PublicId)
                VALUES (@PolicyId, @DocumentId, 1, @ProviderEventId, @PayloadHash,
                        @TopicResourceId, @AuthenticatedTenantId, @AuthenticatedPrincipalId,
                        @ApplicationClientId, @EventSubscriptionName, @StorageAccountResourceId,
                        @BlobHost, @BlobContainer, @BlobObjectName, @BlobETag,
                        @ReportedContentHash, @ToStatus, @ResultCode, @ReceiptStatus,
                        @OutcomeCode, @OccurredAtUtc, @ReceivedAtUtc,
                        CASE WHEN @ReceiptStatus IN (2, 3)
                             THEN @ReceivedAtUtc ELSE NULL END, @NowUtc);
                SELECT @ReceiptId = Id, @ReceiptPublicId = PublicId FROM @InsertedReceipt;

                IF @ReceiptStatus = 0
                BEGIN SET @Succeeded = 1; SET @Code = N'accepted'; END
                ELSE SET @Code = @OutcomeCode;
            END;
        END;

        IF @DocumentId IS NOT NULL AND @DocumentPublicId IS NULL
            SELECT @DocumentPublicId = PublicId, @StoredETag = BlobETag,
                   @StoredHash = ContentHash, @ContentLength = ContentLength,
                   @MimeType = MimeType
            FROM dbo.FundingPlatform_SourceDocuments WHERE Id = @DocumentId;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_DefenderReceipt;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, @ReceiptPublicId AS ReceiptPublicId,
           CASE WHEN @Succeeded = 1 THEN @DocumentPublicId END AS SourceDocumentPublicId,
           CAST(1 AS TINYINT) AS ScanProvider,
           CASE WHEN @Succeeded = 1 THEN @BlobContainer END AS QuarantineBlobContainer,
           CASE WHEN @Succeeded = 1 THEN @BlobObjectName END AS QuarantineBlobObjectName,
           CASE WHEN @Succeeded = 1 THEN @StoredETag END AS QuarantineBlobETag,
           CASE WHEN @Succeeded = 1 THEN @StoredHash END AS ContentHash,
           CASE WHEN @Succeeded = 1 THEN @ContentLength END AS ContentLength,
           CASE WHEN @Succeeded = 1 THEN @MimeType END AS MimeType,
           @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Finalize
    @ReceiptPublicId UNIQUEIDENTIFIER,
    @PayloadHash BINARY(32),
    @Applied BIT,
    @OutcomeCode NVARCHAR(100),
    @FinalizedAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @OutcomeCode = LOWER(LTRIM(RTRIM(@OutcomeCode)));
    IF @ReceiptPublicId IS NULL OR @PayloadHash IS NULL OR @FinalizedAtUtc IS NULL
       OR NULLIF(@OutcomeCode, N'') IS NULL OR LEN(@OutcomeCode) > 100
       OR @OutcomeCode LIKE N'%[^-a-z0-9._]%' COLLATE Latin1_General_100_BIN2
        THROW 51832, N'Valid receipt finalization metadata is required.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @ReceiptId BIGINT, @DocumentId BIGINT, @Status TINYINT;
    DECLARE @StoredHash BINARY(32), @StoredOutcome NVARCHAR(100);
    DECLARE @ProviderEventId NVARCHAR(200), @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'not-found';

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_DefenderFinalize;

    BEGIN TRY
        SELECT @ReceiptId = Id, @DocumentId = SourceDocumentId,
               @Status = ReceiptStatus, @StoredHash = PayloadHash,
               @StoredOutcome = OutcomeCode, @ProviderEventId = ProviderEventId
        FROM dbo.FundingPlatform_SourceDocumentDefenderReceipts WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @ReceiptPublicId;

        IF @ReceiptId IS NULL SET @Code = N'not-found';
        ELSE IF @StoredHash <> @PayloadHash SET @Code = N'receipt-conflict';
        ELSE IF @Status IN (1, 2)
        BEGIN
            IF @StoredOutcome = @OutcomeCode
               AND ((@Status = 1 AND @Applied = 1) OR (@Status = 2 AND @Applied = 0))
            BEGIN SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'replayed'; END
            ELSE SET @Code = N'receipt-conflict';
        END
        ELSE IF @Status = 3 SET @Code = N'rejected';
        ELSE IF @Applied = 1 AND NOT EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentScanEvents
              WHERE SourceDocumentId = @DocumentId AND ScanProvider = 1
                AND ProviderEventId = @ProviderEventId AND PayloadHash = @PayloadHash)
            SET @Code = N'scan-result-not-applied';
        ELSE
        BEGIN
            SET @Status = CASE WHEN @Applied = 1 THEN 1 ELSE 2 END;
            UPDATE dbo.FundingPlatform_SourceDocumentDefenderReceipts
            SET ReceiptStatus = @Status, OutcomeCode = @OutcomeCode,
                FinalizedAtUtc = @FinalizedAtUtc
            WHERE Id = @ReceiptId;
            SET @Succeeded = 1;
            SET @Code = CASE WHEN @Applied = 1 THEN N'applied' ELSE N'ignored' END;
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_DefenderFinalize;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, @Status AS ReceiptStatus,
           @WasReplay AS WasReplay;
END;
GO

/* Internal watchdog for asynchronous Defender delivery. It changes only
   quarantined Microsoft Defender documents whose pending interval expired.
   A second call is a no-op, and no trusted location is ever synthesized. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentScan_WatchdogTimeout
    @BatchSize INT,
    @TimeoutSeconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @BatchSize NOT BETWEEN 1 AND 100
        THROW 51845, N'BatchSize must be between 1 and 100.', 1;
    IF @TimeoutSeconds NOT BETWEEN 60 AND 86400 OR @NowUtc IS NULL
        THROW 51846, N'A timeout between 60 seconds and one day and NowUtc are required.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @CutoffUtc DATETIME2(3) = DATEADD(SECOND, -@TimeoutSeconds, @NowUtc);
    DECLARE @TimedOut TABLE
    (
        Id BIGINT NOT NULL,
        PublicId UNIQUEIDENTIFIER NOT NULL,
        BlobETag NVARCHAR(100) NOT NULL,
        ScanAttemptCount SMALLINT NOT NULL,
        RowVersion BINARY(8) NOT NULL
    );

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_ScanWatchdog;

    BEGIN TRY
        ;WITH Due AS
        (
            SELECT TOP (@BatchSize) documents.*
            FROM dbo.FundingPlatform_SourceDocuments AS documents
                 WITH (UPDLOCK, READPAST, ROWLOCK)
            WHERE documents.ScanProvider = 1
              AND documents.StorageStatus = 1
              AND documents.ScanStatus = 0
              AND documents.ScanStartedAtUtc IS NOT NULL
              AND documents.ScanStartedAtUtc <= @CutoffUtc
            ORDER BY documents.ScanStartedAtUtc, documents.Id
        )
        UPDATE Due
        SET ScanStatus = 4,
            ScanResultCode = N'defender-timeout',
            ScanCompletedAtUtc = @NowUtc,
            TrustedBlobContainer = NULL,
            TrustedBlobObjectName = NULL,
            TrustedBlobETag = NULL,
            UpdatedAtUtc = @NowUtc
        OUTPUT inserted.Id, inserted.PublicId, inserted.BlobETag,
               inserted.ScanAttemptCount, inserted.RowVersion
        INTO @TimedOut (Id, PublicId, BlobETag, ScanAttemptCount, RowVersion);

        INSERT INTO dbo.FundingPlatform_SourceDocumentScanEvents
            (EventId, SourceDocumentId, ScanProvider, ProviderEventId, PayloadHash,
             FromStatus, ToStatus, BlobETag, ReportedContentHash, ResultCode,
             ActorUserId, IdempotencyKeyHash, RequestHash, ResultRowVersion,
             ResultScanAttemptCount, OccurredAtUtc, CreatedAtUtc)
        SELECT NEWID(), timedOut.Id, 1, identityValues.ProviderEventId,
               HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
                   identityValues.ProviderEventId COLLATE Latin1_General_100_BIN2_UTF8))),
               0, 4, timedOut.BlobETag, NULL, N'defender-timeout',
               NULL, NULL, NULL, timedOut.RowVersion, timedOut.ScanAttemptCount,
               @NowUtc, @NowUtc
        FROM @TimedOut AS timedOut
        CROSS APPLY
        (
            SELECT N'defender-timeout:' + CONVERT(NVARCHAR(36), timedOut.PublicId)
                   + N':' + CONVERT(NVARCHAR(3), timedOut.ScanAttemptCount)
                   AS ProviderEventId
        ) AS identityValues;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ScanWatchdog;
        THROW;
    END CATCH;

    SELECT PublicId AS SourceDocumentPublicId, CAST(1 AS TINYINT) AS StorageStatus,
           CAST(4 AS TINYINT) AS ScanStatus, CAST(1 AS TINYINT) AS ScanProvider,
           ScanAttemptCount, RowVersion
    FROM @TimedOut
    ORDER BY SourceDocumentPublicId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentExtraction_LinkAcquisition
    @ResultPublicId UNIQUEIDENTIFIER,
    @RunPublicId UNIQUEIDENTIFIER,
    @ItemPublicId UNIQUEIDENTIFIER,
    @RawObservationPublicId UNIQUEIDENTIFIER,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @ResultPublicId IS NULL OR @RunPublicId IS NULL OR @ItemPublicId IS NULL
       OR @RawObservationPublicId IS NULL OR @NowUtc IS NULL
        THROW 51847, N'Complete acquisition-link identity is required.', 1;
    DECLARE @ResultId BIGINT, @FundingSourceId INT, @JobStatus TINYINT;
    DECLARE @ResultRedacted BIT, @ResultSecurityRevoked BIT, @LinkSecurityRevoked BIT;
    DECLARE @RunId BIGINT, @ItemId BIGINT, @RawId BIGINT, @ItemRawId BIGINT;
    DECLARE @LinkPublicId UNIQUEIDENTIFIER, @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_LinkAcquisition;

    BEGIN TRY
        SELECT @ResultId = results.Id, @FundingSourceId = results.FundingSourceId,
               @JobStatus = jobs.Status, @ResultRedacted = results.IsContentRedacted,
               @ResultSecurityRevoked = results.IsSecurityRevoked
        FROM dbo.FundingPlatform_SourceDocumentExtractionResults AS results WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_SourceDocumentExtractionJobs AS jobs WITH (HOLDLOCK)
            ON jobs.Id = results.ExtractionJobId
        WHERE results.PublicId = @ResultPublicId;
        SELECT @RunId = Id FROM dbo.FundingPlatform_ImportRuns WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @RunPublicId AND FundingSourceId = @FundingSourceId;
        SELECT @RawId = Id FROM dbo.FundingPlatform_RawFundingOpportunities WITH (HOLDLOCK)
        WHERE PublicId = @RawObservationPublicId AND FundingSourceId = @FundingSourceId;
        SELECT @ItemId = Id, @ItemRawId = RawFundingOpportunityId
        FROM dbo.FundingPlatform_ImportRunItems WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @ItemPublicId AND ImportRunId = @RunId
          AND FundingSourceId = @FundingSourceId;

        IF @ResultId IS NULL OR @RunId IS NULL OR @RawId IS NULL OR @ItemId IS NULL
            SET @Code = N'not-found';
        ELSE IF @JobStatus NOT IN (3, 4) SET @Code = N'extraction-not-complete';
        ELSE IF @ResultSecurityRevoked = 1 SET @Code = N'extraction-security-revoked';
        ELSE IF @ResultRedacted = 1 SET @Code = N'extraction-content-redacted';
        ELSE IF @ItemRawId <> @RawId SET @Code = N'item-raw-mismatch';
        ELSE
        BEGIN
            SELECT @LinkPublicId = PublicId, @LinkSecurityRevoked = IsSecurityRevoked
            FROM dbo.FundingPlatform_SourceDocumentAcquisitionLinks WITH (UPDLOCK, HOLDLOCK)
            WHERE ImportRunItemId = @ItemId;
            IF @LinkPublicId IS NOT NULL AND @LinkSecurityRevoked = 1
                SET @Code = N'extraction-security-revoked';
            ELSE IF @LinkPublicId IS NOT NULL
            BEGIN SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'replayed'; END
            ELSE
            BEGIN
                DECLARE @Inserted TABLE (PublicId UNIQUEIDENTIFIER);
                INSERT INTO dbo.FundingPlatform_SourceDocumentAcquisitionLinks
                    (ExtractionResultId, FundingSourceId, ImportRunId,
                     RawFundingOpportunityId, ImportRunItemId, CreatedAtUtc)
                OUTPUT inserted.PublicId INTO @Inserted (PublicId)
                VALUES (@ResultId, @FundingSourceId, @RunId, @RawId, @ItemId, @NowUtc);
                SELECT @LinkPublicId = PublicId FROM @Inserted;
                SET @Succeeded = 1; SET @Code = N'linked';
            END;
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_LinkAcquisition;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @LinkPublicId AS LinkPublicId, @WasReplay AS WasReplay;
END;
GO

/* Internal deterministic evaluator. It emits no result set so it can be called
   inside the import completion transaction without changing the Dapper contract. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunityDuplicateCandidate_EvaluateItem
    @ImportRunItemId BIGINT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @RunId BIGINT, @FundingSourceId INT, @CandidateId BIGINT;
    DECLARE @CandidateFingerprint BINARY(32), @CandidateTitle NVARCHAR(350);
    DECLARE @CandidateSponsor NVARCHAR(300), @SuggestedId BIGINT, @MatchKind TINYINT;
    DECLARE @Confidence DECIMAL(5,4), @EvidenceJson NVARCHAR(MAX);

    SELECT @RunId = items.ImportRunId, @FundingSourceId = items.FundingSourceId,
           @CandidateId = items.FundingOpportunityId,
           @CandidateFingerprint = opportunities.ContentFingerprint,
           @CandidateTitle = opportunities.Title, @CandidateSponsor = opportunities.SponsorName
    FROM dbo.FundingPlatform_ImportRunItems AS items WITH (UPDLOCK, HOLDLOCK)
    INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities WITH (HOLDLOCK)
        ON opportunities.Id = items.FundingOpportunityId
    WHERE items.Id = @ImportRunItemId AND items.Status = 2;

    IF @CandidateId IS NULL RETURN;
    IF @CandidateFingerprint IS NULL
    BEGIN
        SET @CandidateFingerprint = HASHBYTES
            ('SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
             (LOWER(LTRIM(RTRIM(@CandidateTitle))) + N'|' +
              LOWER(LTRIM(RTRIM(@CandidateSponsor))))
             COLLATE Latin1_General_100_BIN2_UTF8)));
    END;

    ;WITH Alternatives AS
    (
        SELECT other.Id,
               CASE
                 WHEN candidate.ContentFingerprint IS NOT NULL
                      AND candidate.ContentFingerprint = other.ContentFingerprint THEN 0
                 WHEN EXISTS
                      (SELECT 1
                       FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS candidateLinks
                       INNER JOIN dbo.FundingPlatform_FundingOpportunitySourceLinks AS otherLinks
                         ON otherLinks.CanonicalUrlHash = candidateLinks.CanonicalUrlHash
                        AND otherLinks.CanonicalUrlHash IS NOT NULL
                       WHERE candidateLinks.FundingOpportunityId = candidate.Id
                         AND otherLinks.FundingOpportunityId = other.Id
                         AND candidateLinks.IsActive = 1 AND otherLinks.IsActive = 1) THEN 1
                 ELSE 2 END AS MatchKind,
               other.PublicationStatus, other.CreatedAtUtc
        FROM dbo.FundingPlatform_FundingOpportunities AS candidate
        INNER JOIN dbo.FundingPlatform_FundingOpportunities AS other
            ON other.Id <> candidate.Id AND other.IsActive = 1
        WHERE candidate.Id = @CandidateId
          AND ((candidate.ContentFingerprint IS NOT NULL
                AND candidate.ContentFingerprint = other.ContentFingerprint)
               OR EXISTS
                  (SELECT 1
                   FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS candidateLinks
                   INNER JOIN dbo.FundingPlatform_FundingOpportunitySourceLinks AS otherLinks
                     ON otherLinks.CanonicalUrlHash = candidateLinks.CanonicalUrlHash
                    AND otherLinks.CanonicalUrlHash IS NOT NULL
                   WHERE candidateLinks.FundingOpportunityId = candidate.Id
                     AND otherLinks.FundingOpportunityId = other.Id
                     AND candidateLinks.IsActive = 1 AND otherLinks.IsActive = 1)
               OR (LOWER(LTRIM(RTRIM(other.Title))) = LOWER(LTRIM(RTRIM(candidate.Title)))
                   AND LOWER(LTRIM(RTRIM(other.SponsorName))) =
                       LOWER(LTRIM(RTRIM(candidate.SponsorName)))))
    )
    SELECT TOP (1) @SuggestedId = Id, @MatchKind = MatchKind
    FROM Alternatives
    ORDER BY MatchKind, CASE WHEN PublicationStatus = 2 THEN 0 ELSE 1 END,
             CreatedAtUtc, Id;

    IF @SuggestedId IS NULL RETURN;
    SET @Confidence = CASE @MatchKind WHEN 0 THEN 1.0000
                                     WHEN 1 THEN 0.9900 ELSE 0.8500 END;
    SET @EvidenceJson =
        (SELECT 1 AS [version],
                CASE @MatchKind WHEN 0 THEN N'exact-content-fingerprint'
                                WHEN 1 THEN N'exact-canonical-url'
                                ELSE N'normalized-title-sponsor' END AS method
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityDuplicateCandidates
        WHERE CandidateOpportunityId = @CandidateId
          AND SuggestedCanonicalOpportunityId = @SuggestedId
          AND CandidateFingerprint = @CandidateFingerprint)
        INSERT INTO dbo.FundingPlatform_FundingOpportunityDuplicateCandidates
            (FundingSourceId, ImportRunId, ImportRunItemId, CandidateOpportunityId,
             SuggestedCanonicalOpportunityId, CandidateFingerprint, MatchKind,
             Confidence, EvidenceJson, Status, CreatedAtUtc, DecidedAtUtc)
        VALUES (@FundingSourceId, @RunId, @ImportRunItemId, @CandidateId,
                @SuggestedId, @CandidateFingerprint, @MatchKind,
                @Confidence, @EvidenceJson, 0, @NowUtc, NULL);
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunityDuplicateCandidate_AdminEvaluate
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @ImportRunItemPublicId UNIQUEIDENTIFIER,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51833, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51834, N'MFA is required for this administrative operation.', 1;
    DECLARE @ItemId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_ImportRunItems WHERE PublicId = @ImportRunItemPublicId);
    IF @ItemId IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'not-found' AS Code,
               CAST(NULL AS UNIQUEIDENTIFIER) AS CandidatePublicId;
        RETURN;
    END;
    EXEC dbo.FundingPlatform_usp_FundingOpportunityDuplicateCandidate_EvaluateItem
        @ImportRunItemId = @ItemId, @NowUtc = @NowUtc;
    SELECT CAST(CASE WHEN candidates.Id IS NULL THEN 0 ELSE 1 END AS BIT) AS Succeeded,
           CASE WHEN candidates.Id IS NULL THEN N'no-match' ELSE N'evaluated' END AS Code,
           candidates.PublicId AS CandidatePublicId
    FROM (SELECT 1 AS Anchor) AS anchor
    LEFT JOIN dbo.FundingPlatform_FundingOpportunityDuplicateCandidates AS candidates
      ON candidates.Id =
         (SELECT TOP (1) Id
          FROM dbo.FundingPlatform_FundingOpportunityDuplicateCandidates
          WHERE ImportRunItemId = @ItemId ORDER BY Id DESC);
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunityDuplicateCandidate_AdminList
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @Status TINYINT = NULL,
    @Page INT = 1,
    @PageSize INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51835, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51836, N'MFA is required for this administrative operation.', 1;
    IF (@Status IS NOT NULL AND @Status NOT IN (0, 1))
       OR @Page < 1 OR @PageSize NOT BETWEEN 1 AND 100
        THROW 51837, N'Duplicate-candidate filters are invalid.', 1;

    DECLARE @TotalCount BIGINT =
        (SELECT COUNT_BIG(1)
         FROM dbo.FundingPlatform_FundingOpportunityDuplicateCandidates
         WHERE @Status IS NULL OR Status = @Status);
    SELECT candidates.PublicId AS CandidatePublicId,
           candidate.PublicId AS CandidateOpportunityPublicId,
           candidate.Title AS CandidateTitle, candidate.SponsorName AS CandidateSponsor,
           suggested.PublicId AS SuggestedCanonicalOpportunityPublicId,
           suggested.Title AS SuggestedCanonicalTitle,
           candidates.MatchKind, candidates.Confidence, candidates.Status,
           candidates.CreatedAtUtc, candidates.DecidedAtUtc,
           candidates.RowVersion, @TotalCount AS TotalCount
    FROM dbo.FundingPlatform_FundingOpportunityDuplicateCandidates AS candidates
    INNER JOIN dbo.FundingPlatform_FundingOpportunities AS candidate
        ON candidate.Id = candidates.CandidateOpportunityId
    LEFT JOIN dbo.FundingPlatform_FundingOpportunities AS suggested
        ON suggested.Id = candidates.SuggestedCanonicalOpportunityId
    WHERE @Status IS NULL OR candidates.Status = @Status
    ORDER BY candidates.CreatedAtUtc DESC, candidates.Id DESC
    OFFSET (@Page - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunityDuplicateCandidate_AdminGet
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @CandidatePublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51838, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51839, N'MFA is required for this administrative operation.', 1;
    SELECT candidates.PublicId AS CandidatePublicId,
           candidate.PublicId AS CandidateOpportunityPublicId,
           candidate.Title AS CandidateTitle, candidate.SponsorName AS CandidateSponsor,
           candidate.PublicationStatus AS CandidatePublicationStatus,
           suggested.PublicId AS SuggestedCanonicalOpportunityPublicId,
           suggested.Title AS SuggestedCanonicalTitle,
           suggested.SponsorName AS SuggestedCanonicalSponsor,
           suggested.PublicationStatus AS SuggestedCanonicalPublicationStatus,
           candidates.MatchKind, candidates.Confidence, candidates.EvidenceJson,
           candidates.Status, candidates.CreatedAtUtc, candidates.DecidedAtUtc,
           decisions.PublicId AS DecisionPublicId, decisions.Decision,
           canonical.PublicId AS DecidedCanonicalOpportunityPublicId,
           decisions.Reason AS DecisionReason, decisions.CreatedAtUtc AS DecisionCreatedAtUtc,
           candidates.RowVersion
    FROM dbo.FundingPlatform_FundingOpportunityDuplicateCandidates AS candidates
    INNER JOIN dbo.FundingPlatform_FundingOpportunities AS candidate
        ON candidate.Id = candidates.CandidateOpportunityId
    LEFT JOIN dbo.FundingPlatform_FundingOpportunities AS suggested
        ON suggested.Id = candidates.SuggestedCanonicalOpportunityId
    LEFT JOIN dbo.FundingPlatform_FundingOpportunityDuplicateDecisions AS decisions
        ON decisions.DuplicateCandidateId = candidates.Id
    LEFT JOIN dbo.FundingPlatform_FundingOpportunities AS canonical
        ON canonical.Id = decisions.CanonicalOpportunityId
    WHERE candidates.PublicId = @CandidatePublicId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunityDuplicateCandidate_AdminDecide
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @CandidatePublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @Decision TINYINT,
    @CanonicalOpportunityPublicId UNIQUEIDENTIFIER = NULL,
    @Reason NVARCHAR(500),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @DecidedAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51842, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51843, N'MFA is required for this administrative operation.', 1;
    SET XACT_ABORT ON;
    SET @Reason = LTRIM(RTRIM(@Reason));
    IF @ExpectedRowVersion IS NULL OR @Decision NOT IN (1, 2, 3)
       OR NULLIF(@Reason, N'') IS NULL OR LEN(@Reason) > 500
       OR CHARINDEX(CHAR(10), @Reason) > 0 OR CHARINDEX(CHAR(13), @Reason) > 0
       OR @IdempotencyKeyHash IS NULL OR @RequestHash IS NULL OR @DecidedAtUtc IS NULL
       OR (@Decision = 2 AND @CanonicalOpportunityPublicId IS NULL)
       OR (@Decision IN (1, 3) AND @CanonicalOpportunityPublicId IS NOT NULL)
        THROW 51844, N'Valid duplicate decision metadata is required.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @ActorUserId BIGINT, @CandidateId BIGINT, @CandidateOpportunityId BIGINT;
    DECLARE @ResultCandidatePublicId UNIQUEIDENTIFIER;
    DECLARE @Status TINYINT, @CurrentRowVersion BINARY(8), @CanonicalId BIGINT;
    DECLARE @DecisionId BIGINT, @DecisionPublicId UNIQUEIDENTIFIER;
    DECLARE @StoredRequestHash BINARY(32), @StoredDecision TINYINT;
    DECLARE @StoredCanonicalId BIGINT, @StoredReason NVARCHAR(500);
    DECLARE @StoredDecidedAtUtc DATETIME2(3);
    DECLARE @ResultRowVersion BINARY(8), @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'not-found';

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_DuplicateDecide;

    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId = @AdminUserPublicId,
            @ActorUserId = @ActorUserId OUTPUT;

        SELECT @DecisionId = decisions.Id, @DecisionPublicId = decisions.PublicId,
               @StoredRequestHash = decisions.RequestHash,
               @StoredDecision = decisions.Decision,
               @StoredCanonicalId = decisions.CanonicalOpportunityId,
               @StoredReason = decisions.Reason,
               @StoredDecidedAtUtc = decisions.CreatedAtUtc,
               @CandidateId = candidates.Id, @CandidateOpportunityId = candidates.CandidateOpportunityId,
               @ResultCandidatePublicId = candidates.PublicId,
               @ResultRowVersion = candidates.RowVersion, @Status = candidates.Status
        FROM dbo.FundingPlatform_FundingOpportunityDuplicateDecisions AS decisions
             WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_FundingOpportunityDuplicateCandidates AS candidates WITH (HOLDLOCK)
            ON candidates.Id = decisions.DuplicateCandidateId
        WHERE decisions.ActorUserId = @ActorUserId
          AND decisions.IdempotencyKeyHash = @IdempotencyKeyHash;

        IF @DecisionId IS NOT NULL
        BEGIN
            IF @StoredRequestHash = @RequestHash
            BEGIN
                SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'replayed';
            END
            ELSE
            BEGIN
                SET @CandidateId = NULL; SET @DecisionPublicId = NULL;
                SET @ResultRowVersion = NULL; SET @Status = NULL;
                SET @Code = N'idempotency-conflict';
            END;
        END
        ELSE
        BEGIN
            SELECT @CandidateId = Id, @CandidateOpportunityId = CandidateOpportunityId,
                   @Status = Status, @CurrentRowVersion = RowVersion,
                   @ResultCandidatePublicId = PublicId
            FROM dbo.FundingPlatform_FundingOpportunityDuplicateCandidates WITH (UPDLOCK, HOLDLOCK)
            WHERE PublicId = @CandidatePublicId;

            IF @Decision = 2
                SELECT @CanonicalId = Id
                FROM dbo.FundingPlatform_FundingOpportunities WITH (UPDLOCK, HOLDLOCK)
                WHERE PublicId = @CanonicalOpportunityPublicId AND IsActive = 1;

            IF @CandidateId IS NULL SET @Code = N'not-found';
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @Status <> 0 SET @Code = N'already-decided';
            ELSE IF @Decision = 2 AND @CanonicalId IS NULL SET @Code = N'canonical-not-found';
            ELSE IF @Decision = 2 AND @CanonicalId = @CandidateOpportunityId
                SET @Code = N'invalid-canonical';
            ELSE
            BEGIN
                DECLARE @InsertedDecision TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER);
                INSERT INTO dbo.FundingPlatform_FundingOpportunityDuplicateDecisions
                    (DuplicateCandidateId, Decision, CanonicalOpportunityId, ActorUserId,
                     Reason, IdempotencyKeyHash, RequestHash, CreatedAtUtc)
                OUTPUT inserted.Id, inserted.PublicId
                    INTO @InsertedDecision (Id, PublicId)
                VALUES (@CandidateId, @Decision, @CanonicalId, @ActorUserId,
                        @Reason, @IdempotencyKeyHash, @RequestHash, @DecidedAtUtc);
                SELECT @DecisionId = Id, @DecisionPublicId = PublicId FROM @InsertedDecision;

                UPDATE dbo.FundingPlatform_FundingOpportunityDuplicateCandidates
                SET Status = 1, DecidedAtUtc = @DecidedAtUtc
                WHERE Id = @CandidateId;
                SELECT @ResultRowVersion = RowVersion
                FROM dbo.FundingPlatform_FundingOpportunityDuplicateCandidates
                WHERE Id = @CandidateId;
                SET @Status = 1; SET @Succeeded = 1; SET @Code = N'decided';
            END;
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_DuplicateDecide;
        THROW;
    END CATCH;

    DECLARE @ResultCanonicalPublicId UNIQUEIDENTIFIER =
        (SELECT PublicId FROM dbo.FundingPlatform_FundingOpportunities
         WHERE Id = COALESCE(@CanonicalId, @StoredCanonicalId));
    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @ResultCandidatePublicId AS CandidatePublicId,
           @DecisionPublicId AS DecisionPublicId, @Status AS Status,
           COALESCE(@StoredDecision, @Decision) AS Decision,
           @ResultCanonicalPublicId AS CanonicalOpportunityPublicId,
           COALESCE(@StoredDecidedAtUtc, @DecidedAtUtc) AS DecidedAtUtc,
           @ResultRowVersion AS RowVersion,
           @WasReplay AS WasReplay;
END;
GO

/* Import completion materializes advisory comparisons in the same transaction.
   The trigger is set based and has no effect on opportunity publication/content. */
CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_ImportRunItems_EvaluateDuplicates
ON dbo.FundingPlatform_ImportRunItems
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH Completed AS
    (
        SELECT inserted.Id AS ItemId, inserted.ImportRunId, inserted.FundingSourceId,
               inserted.FundingOpportunityId,
               COALESCE(candidate.ContentFingerprint,
                        HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
                          (LOWER(LTRIM(RTRIM(candidate.Title))) + N'|' +
                           LOWER(LTRIM(RTRIM(candidate.SponsorName))))
                          COLLATE Latin1_General_100_BIN2_UTF8)))) AS CandidateFingerprint
        FROM inserted
        INNER JOIN deleted ON deleted.Id = inserted.Id
        INNER JOIN dbo.FundingPlatform_FundingOpportunities AS candidate
            ON candidate.Id = inserted.FundingOpportunityId
        WHERE inserted.Status = 2 AND inserted.FundingOpportunityId IS NOT NULL
          AND (deleted.Status <> 2
               OR ISNULL(deleted.FundingOpportunityId, -1) <> inserted.FundingOpportunityId)
    )
    INSERT INTO dbo.FundingPlatform_FundingOpportunityDuplicateCandidates
        (FundingSourceId, ImportRunId, ImportRunItemId, CandidateOpportunityId,
         SuggestedCanonicalOpportunityId, CandidateFingerprint, MatchKind,
         Confidence, EvidenceJson, Status, CreatedAtUtc, DecidedAtUtc)
    SELECT completed.FundingSourceId, completed.ImportRunId, completed.ItemId,
           completed.FundingOpportunityId, alternatives.Id,
           completed.CandidateFingerprint, alternatives.MatchKind,
           CASE alternatives.MatchKind WHEN 0 THEN 1.0000
                                       WHEN 1 THEN 0.9900 ELSE 0.8500 END,
           (SELECT 1 AS [version],
                   CASE alternatives.MatchKind
                     WHEN 0 THEN N'exact-content-fingerprint'
                     WHEN 1 THEN N'exact-canonical-url'
                     ELSE N'normalized-title-sponsor' END AS method
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           0, SYSUTCDATETIME(), NULL
    FROM Completed AS completed
    CROSS APPLY
    (
        SELECT TOP (1) other.Id,
               CASE
                 WHEN candidate.ContentFingerprint IS NOT NULL
                      AND candidate.ContentFingerprint = other.ContentFingerprint THEN 0
                 WHEN EXISTS
                      (SELECT 1
                       FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS candidateLinks
                       INNER JOIN dbo.FundingPlatform_FundingOpportunitySourceLinks AS otherLinks
                         ON otherLinks.CanonicalUrlHash = candidateLinks.CanonicalUrlHash
                        AND otherLinks.CanonicalUrlHash IS NOT NULL
                       WHERE candidateLinks.FundingOpportunityId = candidate.Id
                         AND otherLinks.FundingOpportunityId = other.Id
                         AND candidateLinks.IsActive = 1 AND otherLinks.IsActive = 1) THEN 1
                 ELSE 2 END AS MatchKind
        FROM dbo.FundingPlatform_FundingOpportunities AS candidate
        INNER JOIN dbo.FundingPlatform_FundingOpportunities AS other
            ON other.Id <> candidate.Id AND other.IsActive = 1
        WHERE candidate.Id = completed.FundingOpportunityId
          AND ((candidate.ContentFingerprint IS NOT NULL
                AND candidate.ContentFingerprint = other.ContentFingerprint)
               OR EXISTS
                  (SELECT 1
                   FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS candidateLinks
                   INNER JOIN dbo.FundingPlatform_FundingOpportunitySourceLinks AS otherLinks
                     ON otherLinks.CanonicalUrlHash = candidateLinks.CanonicalUrlHash
                    AND otherLinks.CanonicalUrlHash IS NOT NULL
                   WHERE candidateLinks.FundingOpportunityId = candidate.Id
                     AND otherLinks.FundingOpportunityId = other.Id
                     AND candidateLinks.IsActive = 1 AND otherLinks.IsActive = 1)
               OR (LOWER(LTRIM(RTRIM(other.Title))) = LOWER(LTRIM(RTRIM(candidate.Title)))
                   AND LOWER(LTRIM(RTRIM(other.SponsorName))) =
                       LOWER(LTRIM(RTRIM(candidate.SponsorName)))))
        ORDER BY CASE
                   WHEN candidate.ContentFingerprint IS NOT NULL
                        AND candidate.ContentFingerprint = other.ContentFingerprint THEN 0
                   WHEN EXISTS
                        (SELECT 1
                         FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS candidateLinks
                         INNER JOIN dbo.FundingPlatform_FundingOpportunitySourceLinks AS otherLinks
                           ON otherLinks.CanonicalUrlHash = candidateLinks.CanonicalUrlHash
                          AND otherLinks.CanonicalUrlHash IS NOT NULL
                         WHERE candidateLinks.FundingOpportunityId = candidate.Id
                           AND otherLinks.FundingOpportunityId = other.Id
                           AND candidateLinks.IsActive = 1 AND otherLinks.IsActive = 1) THEN 1
                   ELSE 2 END,
                 CASE WHEN other.PublicationStatus = 2 THEN 0 ELSE 1 END,
                 other.CreatedAtUtc, other.Id
    ) AS alternatives
    WHERE NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityDuplicateCandidates AS existing
                WITH (UPDLOCK, HOLDLOCK)
           WHERE existing.CandidateOpportunityId = completed.FundingOpportunityId
             AND existing.SuggestedCanonicalOpportunityId = alternatives.Id
             AND existing.CandidateFingerprint = completed.CandidateFingerprint);
END;
GO

/* FASE 7B governance replaces the 7A scheduler predicate. Network sources
   cannot become due when license, robots, limits or allowlist have expired. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ImportRun_Scheduler_CreateDue
    @NowUtc DATETIME2(3),
    @BatchSize INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @NowUtc IS NULL THROW 51845, N'NowUtc is required.', 1;
    IF @BatchSize NOT BETWEEN 1 AND 100
        THROW 51846, N'BatchSize must be between 1 and 100.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @DueSources TABLE
    (
        FundingSourceId INT PRIMARY KEY, ProviderCode NVARCHAR(100),
        ScheduleSlotUtc DATETIME2(3), ScheduleIntervalSeconds INT,
        Keyword NVARCHAR(100), MaximumResults INT, MaxAttempts SMALLINT,
        RetryBaseDelaySeconds INT
    );
    DECLARE @CreatedRuns TABLE
        (RunId BIGINT PRIMARY KEY, RunPublicId UNIQUEIDENTIFIER, FundingSourceId INT);

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_ImportSchedule;
    BEGIN TRY
        INSERT INTO @DueSources
            (FundingSourceId, ProviderCode, ScheduleSlotUtc, ScheduleIntervalSeconds,
             Keyword, MaximumResults, MaxAttempts, RetryBaseDelaySeconds)
        SELECT TOP (@BatchSize) sources.Id, policies.ProviderCode, sources.NextRunAtUtc,
               sources.ScheduleIntervalSeconds,
               LEFT(COALESCE(NULLIF(LTRIM(RTRIM(JSON_VALUE
                    (sources.ConfigurationJson, N'$.defaultKeyword'))), N''), N'nonprofit'), 100),
               CASE WHEN TRY_CONVERT(INT, JSON_VALUE
                               (sources.ConfigurationJson, N'$.maximumResults')) BETWEEN 1 AND 25
                    THEN TRY_CONVERT(INT, JSON_VALUE
                               (sources.ConfigurationJson, N'$.maximumResults')) ELSE 25 END,
               sources.MaxRunAttempts, sources.RetryBaseDelaySeconds
        FROM dbo.FundingPlatform_FundingSources AS sources
             WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
        INNER JOIN dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions AS policies
            ON policies.FundingSourceId = sources.Id
           AND policies.PolicyVersion = sources.AcquisitionPolicyVersion
        WHERE sources.IsEnabled = 1 AND sources.ComplianceStatus = 1
          AND policies.ProviderCode IS NOT NULL
          AND policies.PolicyFingerprint IS NOT NULL
          AND sources.ScheduleIntervalSeconds IS NOT NULL
          AND sources.NextRunAtUtc <= @NowUtc
          AND ((policies.ProviderType IN (0, 4) AND policies.LicenseStatus IN (1, 3))
               OR (policies.ProviderType IN (1, 2, 3)
                   AND policies.LicenseStatus = 1
                   AND policies.LicenseName IS NOT NULL AND policies.LicenseUrl IS NOT NULL
                   AND policies.LicenseReviewedAtUtc IS NOT NULL
                   AND (policies.LicenseExpiresAtUtc IS NULL
                        OR policies.LicenseExpiresAtUtc > @NowUtc)
                   AND policies.RequestRateLimitPerMinute IS NOT NULL
                   AND policies.MaximumResponseBytes IS NOT NULL
                   AND policies.ContentRetentionDays IS NOT NULL
                   AND EXISTS
                      (SELECT 1
                       FROM dbo.FundingPlatform_FundingSourceAcquisitionPolicyHosts AS hosts
                       WHERE hosts.PolicyId = policies.Id
                         AND hosts.FundingSourceId = sources.Id)
                   AND EXISTS
                      (SELECT 1
                       FROM dbo.FundingPlatform_FundingSourceAcquisitionPolicyEndpoints AS endpoints
                       WHERE endpoints.PolicyId = policies.Id
                         AND endpoints.FundingSourceId = sources.Id
                         AND endpoints.EndpointKind = 2)))
          AND (policies.ProviderType NOT IN (2, 3)
               OR (policies.RobotsPolicyStatus = 1
                   AND policies.RobotsExpiresAtUtc > @NowUtc))
        ORDER BY sources.NextRunAtUtc, sources.Id;

        UPDATE sources
        SET NextRunAtUtc = DATEADD(SECOND, due.ScheduleIntervalSeconds, @NowUtc),
            UpdatedAtUtc = @NowUtc
        FROM dbo.FundingPlatform_FundingSources AS sources
        INNER JOIN @DueSources AS due ON due.FundingSourceId = sources.Id;

        INSERT INTO dbo.FundingPlatform_ImportRuns
            (FundingSourceId, TriggerType, Status, Keyword, MaximumResults, CorrelationId,
             RequestedByUserId, ScheduleSlotUtc, IdempotencyKeyHash, RequestHash,
             AttemptCount, MaxAttempts, RetryBaseDelaySeconds, NextAttemptAtUtc,
             CreatedAtUtc, UpdatedAtUtc)
        OUTPUT inserted.Id, inserted.PublicId, inserted.FundingSourceId
            INTO @CreatedRuns (RunId, RunPublicId, FundingSourceId)
        SELECT due.FundingSourceId, 1, 0, due.Keyword, due.MaximumResults,
               CONCAT(N'schedule:', CONVERT(NVARCHAR(12), due.FundingSourceId), N':',
                      CONVERT(NVARCHAR(33), due.ScheduleSlotUtc, 126)),
               NULL, due.ScheduleSlotUtc, NULL, NULL, 0, due.MaxAttempts,
               due.RetryBaseDelaySeconds, @NowUtc, @NowUtc, @NowUtc
        FROM @DueSources AS due
        WHERE NOT EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_ImportRuns AS existing WITH (UPDLOCK, HOLDLOCK)
              WHERE existing.FundingSourceId = due.FundingSourceId
                AND existing.ScheduleSlotUtc = due.ScheduleSlotUtc
                AND existing.TriggerType = 1);

        INSERT INTO dbo.FundingPlatform_OutboxMessages
            (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
             OccurredAtUtc, AvailableAtUtc)
        SELECT NEWID(), N'ImportRunRequested', N'ImportRun',
               CONVERT(NVARCHAR(100), RunPublicId),
               (SELECT RunPublicId AS runId, 1 AS [version]
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc
        FROM @CreatedRuns;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ImportSchedule;
        THROW;
    END CATCH;

    SELECT created.RunPublicId, created.FundingSourceId, due.ProviderCode
    FROM @CreatedRuns AS created
    INNER JOIN @DueSources AS due ON due.FundingSourceId = created.FundingSourceId
    ORDER BY created.RunId;
END;
GO

/* Keep the battle-tested 7A lease state machine and place a locked 7B policy
   gate in front of it. The rename is forward-only and performed once by 016. */
EXEC sys.sp_rename
    @objname = N'dbo.FundingPlatform_usp_ImportRun_Claim',
    @newname = N'FundingPlatform_usp_ImportRun_Claim_7A',
    @objtype = N'OBJECT';
GO

CREATE PROCEDURE dbo.FundingPlatform_usp_ImportRun_Claim
    @RunPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @LeaseSeconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @RunPublicId IS NULL OR @LeaseId IS NULL OR @NowUtc IS NULL
        THROW 51847, N'RunPublicId, LeaseId and NowUtc are required.', 1;
    IF @LeaseSeconds NOT BETWEEN 30 AND 3600
        THROW 51848, N'LeaseSeconds must be between 30 and 3600.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @RunId BIGINT, @FundingSourceId INT, @RunStatus TINYINT;
    DECLARE @ProviderCode NVARCHAR(100), @Keyword NVARCHAR(100), @MaximumResults INT;
    DECLARE @AttemptCount SMALLINT, @RetrievedCount INT;
    DECLARE @MaxAttempts SMALLINT, @CurrentLeaseId UNIQUEIDENTIFIER;
    DECLARE @CurrentLeaseUntilUtc DATETIME2(3), @NextAttemptAtUtc DATETIME2(3);
    DECLARE @LeaseUntilUtc DATETIME2(3), @ClaimSucceeded BIT = 0;
    DECLARE @ClaimCode NVARCHAR(50) = N'not-found';
    DECLARE @IsEnabled BIT, @ProviderType TINYINT, @ComplianceStatus TINYINT;
    DECLARE @LicenseStatus TINYINT, @LicenseName NVARCHAR(200), @LicenseUrl NVARCHAR(2048);
    DECLARE @LicenseReviewed DATETIME2(3), @LicenseExpires DATETIME2(3);
    DECLARE @RobotsStatus TINYINT, @RobotsExpires DATETIME2(3);
    DECLARE @Rate INT, @MaximumBytes BIGINT, @Retention SMALLINT;
    DECLARE @PolicyId BIGINT, @PolicyVersion INT, @PolicyFingerprint BINARY(32);
    DECLARE @RunPolicyVersion INT, @RunPolicyFingerprint BINARY(32);
    DECLARE @RunRetention SMALLINT;
    DECLARE @PolicyCode NVARCHAR(50), @PendingItemCount INT;

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_ImportClaim7B;

    BEGIN TRY
        SELECT @RunId = runs.Id, @FundingSourceId = runs.FundingSourceId,
               @RunStatus = runs.Status, @Keyword = runs.Keyword,
               @MaximumResults = runs.MaximumResults, @AttemptCount = runs.AttemptCount,
               @RetrievedCount = runs.RetrievedCount,
               @MaxAttempts = runs.MaxAttempts, @CurrentLeaseId = runs.LeaseId,
               @CurrentLeaseUntilUtc = runs.LeaseUntilUtc,
               @NextAttemptAtUtc = runs.NextAttemptAtUtc,
               @RunPolicyVersion = runs.AcquisitionPolicyVersionSnapshot,
               @RunPolicyFingerprint = runs.AcquisitionPolicyFingerprintSnapshot,
               @RunRetention = runs.ContentRetentionDaysSnapshot,
               @ProviderCode = policies.ProviderCode,
               @IsEnabled = sources.IsEnabled, @ProviderType = policies.ProviderType,
               @ComplianceStatus = sources.ComplianceStatus,
               @LicenseStatus = policies.LicenseStatus, @LicenseName = policies.LicenseName,
               @LicenseUrl = policies.LicenseUrl,
               @LicenseReviewed = policies.LicenseReviewedAtUtc,
               @LicenseExpires = policies.LicenseExpiresAtUtc,
               @RobotsStatus = policies.RobotsPolicyStatus,
               @RobotsExpires = policies.RobotsExpiresAtUtc,
               @Rate = policies.RequestRateLimitPerMinute,
               @MaximumBytes = policies.MaximumResponseBytes,
               @Retention = policies.ContentRetentionDays,
               @PolicyVersion = policies.PolicyVersion,
               @PolicyFingerprint = policies.PolicyFingerprint,
               @PolicyId = policies.Id
        FROM dbo.FundingPlatform_ImportRuns AS runs WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_FundingSources AS sources WITH (UPDLOCK, HOLDLOCK)
            ON sources.Id = runs.FundingSourceId
        LEFT JOIN dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions AS policies
            WITH (HOLDLOCK)
            ON policies.FundingSourceId = sources.Id
           AND policies.PolicyVersion = sources.AcquisitionPolicyVersion
        WHERE runs.PublicId = @RunPublicId;

        IF @RunId IS NOT NULL AND @RunStatus IN (0, 1)
        BEGIN
            IF @RunPolicyVersion IS NOT NULL
               AND (@RunPolicyVersion <> @PolicyVersion
                    OR @RunPolicyFingerprint IS NULL
                    OR @RunPolicyFingerprint <> @PolicyFingerprint
                    OR @RunRetention IS NULL OR @RunRetention <> @Retention)
                SET @PolicyCode = N'policy-changed';
            ELSE IF @IsEnabled <> 1 SET @PolicyCode = N'source-disabled';
            ELSE IF @PolicyId IS NULL OR @ProviderCode IS NULL
                SET @PolicyCode = N'policy-not-found';
            ELSE IF @ProviderType NOT IN (1, 2, 3)
                SET @PolicyCode = N'provider-not-supported';
            ELSE IF @PolicyFingerprint IS NULL
                SET @PolicyCode = N'policy-not-found';
            ELSE IF @ComplianceStatus <> 1 SET @PolicyCode = N'compliance-required';
            ELSE IF (@ProviderType IN (0, 4) AND @LicenseStatus NOT IN (1, 3))
                 OR (@ProviderType IN (1, 2, 3)
                     AND (@LicenseStatus <> 1 OR @LicenseName IS NULL OR @LicenseUrl IS NULL
                          OR @LicenseReviewed IS NULL
                          OR (@LicenseExpires IS NOT NULL AND @LicenseExpires <= @NowUtc)))
                SET @PolicyCode = N'license-required';
            ELSE IF @ProviderType IN (2, 3)
                 AND (@RobotsStatus <> 1 OR @RobotsExpires IS NULL
                      OR @RobotsExpires <= @NowUtc)
                SET @PolicyCode = N'robots-policy-required';
            ELSE IF @ProviderType IN (1, 2, 3)
                 AND (NOT EXISTS
                         (SELECT 1
                          FROM dbo.FundingPlatform_FundingSourceAcquisitionPolicyHosts
                          WHERE PolicyId = @PolicyId
                            AND FundingSourceId = @FundingSourceId)
                      OR NOT EXISTS
                         (SELECT 1
                          FROM dbo.FundingPlatform_FundingSourceAcquisitionPolicyEndpoints
                          WHERE PolicyId = @PolicyId
                            AND FundingSourceId = @FundingSourceId
                            AND EndpointKind = 2))
                SET @PolicyCode = N'host-not-allowed';
            ELSE IF @Retention IS NULL
                SET @PolicyCode = N'retention-policy-required';
            ELSE IF @ProviderType IN (1, 2, 3)
                 AND (@Rate IS NULL OR @MaximumBytes IS NULL)
                SET @PolicyCode = N'limits-required';
        END;

        IF @PolicyCode IS NOT NULL
        BEGIN
            UPDATE dbo.FundingPlatform_ImportRunItems
            SET Status = 3, OutcomeCode = N'failed', CompletedAtUtc = @NowUtc,
                UpdatedAtUtc = @NowUtc
            WHERE ImportRunId = @RunId AND Status IN (0, 1);
            SET @PendingItemCount = @@ROWCOUNT;

            UPDATE dbo.FundingPlatform_ImportRuns
            SET Status = 5, LeaseId = NULL, LeaseUntilUtc = NULL,
                CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc,
                FailedCount = FailedCount + @PendingItemCount,
                LastErrorCode = @PolicyCode,
                LastErrorMessage = N'The funding source is not ready under its acquisition policy.'
            WHERE Id = @RunId;

            INSERT INTO dbo.FundingPlatform_ImportErrors
                (ImportRunId, FundingSourceId, ImportRunItemId, Stage, ErrorCode,
                 SanitizedMessage, IsRetryable, OccurredAtUtc, CreatedAtUtc)
            VALUES (@RunId, @FundingSourceId, NULL, N'governance', @PolicyCode,
                    N'The funding source is not ready under its acquisition policy.',
                    0, @NowUtc, @NowUtc);

            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CAST(0 AS BIT) AS Succeeded, @PolicyCode AS Code,
                   @RunPublicId AS RunPublicId, @FundingSourceId AS FundingSourceId,
                   @ProviderCode AS ProviderCode, @Keyword AS Keyword,
                   @MaximumResults AS MaximumResults, @AttemptCount AS AttemptCount,
                   @RetrievedCount AS RetrievedCount,
                   CAST(NULL AS DATETIME2(3)) AS LeaseUntilUtc,
                   CAST(NULL AS INT) AS RequestRateLimitPerMinute,
                   CAST(NULL AS INT) AS MaximumResponseBytes,
                   CAST(NULL AS SMALLINT) AS ContentRetentionDays,
                   CAST(NULL AS INT) AS AcquisitionPolicyVersion,
                   CAST(NULL AS BINARY(32)) AS AcquisitionPolicyFingerprint;
            RETURN;
        END;

        /* Inline the 7A lease transition rather than using INSERT EXEC.  Dapper
           and the SQL smokes capture this wrapper with INSERT EXEC themselves,
           and SQL Server rejects nested captures (8164). */
        IF @RunId IS NULL
            SET @ClaimCode = N'not-found';
        ELSE IF @RunStatus = 1 AND @CurrentLeaseId = @LeaseId
                  AND @CurrentLeaseUntilUtc > @NowUtc
        BEGIN
            SET @ClaimSucceeded = 1;
            SET @ClaimCode = N'replayed';
            SET @LeaseUntilUtc = @CurrentLeaseUntilUtc;
        END
        ELSE IF @RunStatus BETWEEN 2 AND 5
            SET @ClaimCode = N'already-terminal';
        ELSE IF @RunStatus = 1 AND @CurrentLeaseUntilUtc > @NowUtc
            SET @ClaimCode = N'lease-active';
        ELSE IF @AttemptCount >= @MaxAttempts
        BEGIN
            DECLARE @ExhaustedItemCount INT;
            UPDATE dbo.FundingPlatform_ImportRunItems
            SET Status = 3, OutcomeCode = N'failed',
                CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc
            WHERE ImportRunId = @RunId AND Status IN (0, 1);
            SET @ExhaustedItemCount = @@ROWCOUNT;

            UPDATE dbo.FundingPlatform_ImportRuns
            SET Status = 4, LeaseId = NULL, LeaseUntilUtc = NULL,
                CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc,
                FailedCount = FailedCount + @ExhaustedItemCount,
                LastErrorCode = N'retries-exhausted',
                LastErrorMessage = N'The import run exhausted its retry limit.'
            WHERE Id = @RunId;
            INSERT INTO dbo.FundingPlatform_ImportErrors
                (ImportRunId, FundingSourceId, ImportRunItemId, Stage, ErrorCode,
                 SanitizedMessage, IsRetryable, OccurredAtUtc, CreatedAtUtc)
            VALUES (@RunId, @FundingSourceId, NULL, N'lease', N'retries-exhausted',
                    N'The import run exhausted its retry limit.', 0, @NowUtc, @NowUtc);
            SET @RunStatus = 4;
            SET @ClaimCode = N'retries-exhausted';
        END
        ELSE IF @NextAttemptAtUtc > @NowUtc
            SET @ClaimCode = N'not-due';
        ELSE
        BEGIN
            IF @RunStatus = 1 AND @CurrentLeaseUntilUtc <= @NowUtc
                INSERT INTO dbo.FundingPlatform_ImportErrors
                    (ImportRunId, FundingSourceId, ImportRunItemId, Stage, ErrorCode,
                     SanitizedMessage, IsRetryable, OccurredAtUtc, CreatedAtUtc)
                VALUES (@RunId, @FundingSourceId, NULL, N'lease', N'lease-expired',
                        N'The previous worker lease expired and the run was reclaimed.',
                        1, @NowUtc, @NowUtc);

            SET @LeaseUntilUtc = DATEADD(SECOND, @LeaseSeconds, @NowUtc);
            UPDATE dbo.FundingPlatform_ImportRuns
            SET Status = 1, AttemptCount = AttemptCount + 1,
                LeaseId = @LeaseId, LeaseUntilUtc = @LeaseUntilUtc,
                StartedAtUtc = COALESCE(StartedAtUtc, @NowUtc),
                UpdatedAtUtc = @NowUtc
            WHERE Id = @RunId;
            SET @AttemptCount = @AttemptCount + 1;
            SET @RunStatus = 1;
            SET @ClaimSucceeded = 1;
            SET @ClaimCode = N'claimed';
        END;

        IF @ClaimSucceeded = 1
        BEGIN
            UPDATE dbo.FundingPlatform_ImportRuns
            SET ContentRetentionDaysSnapshot =
                    COALESCE(ContentRetentionDaysSnapshot, @Retention),
                AcquisitionPolicyVersionSnapshot =
                    COALESCE(AcquisitionPolicyVersionSnapshot, @PolicyVersion),
                AcquisitionPolicyFingerprintSnapshot =
                    COALESCE(AcquisitionPolicyFingerprintSnapshot, @PolicyFingerprint)
            WHERE Id = @RunId;
            SELECT @Retention = ContentRetentionDaysSnapshot,
                   @PolicyVersion = AcquisitionPolicyVersionSnapshot,
                   @PolicyFingerprint = AcquisitionPolicyFingerprintSnapshot
            FROM dbo.FundingPlatform_ImportRuns WITH (HOLDLOCK)
            WHERE Id = @RunId;
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;

        SELECT @ClaimSucceeded AS Succeeded, @ClaimCode AS Code,
               CASE WHEN @ClaimCode = N'not-found' THEN NULL ELSE @RunPublicId END
                   AS RunPublicId,
               @FundingSourceId AS FundingSourceId, @ProviderCode AS ProviderCode,
               @Keyword AS Keyword, @MaximumResults AS MaximumResults,
               @AttemptCount AS AttemptCount, @RetrievedCount AS RetrievedCount,
               @LeaseUntilUtc AS LeaseUntilUtc,
               CASE WHEN @ClaimSucceeded = 1 THEN @Rate END
                   AS RequestRateLimitPerMinute,
               CASE WHEN @ClaimSucceeded = 1 THEN CONVERT(INT, @MaximumBytes) END
                   AS MaximumResponseBytes,
               CASE WHEN @ClaimSucceeded = 1 THEN @Retention END AS ContentRetentionDays,
               CASE WHEN @ClaimSucceeded = 1 THEN @PolicyVersion END
                   AS AcquisitionPolicyVersion,
               CASE WHEN @ClaimSucceeded = 1 THEN @PolicyFingerprint END
                   AS AcquisitionPolicyFingerprint;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ImportClaim7B;
        THROW;
    END CATCH;
END;
GO

/* Pending normalized work cannot outlive its immutable policy snapshot. The
   active run lease serializes terminalization with staging workers. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ImportRunItem_ListPending
    @RunPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @BatchSize INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @RunPublicId IS NULL OR @LeaseId IS NULL OR @NowUtc IS NULL
        THROW 51739, N'RunPublicId, LeaseId and NowUtc are required.', 1;
    IF @BatchSize NOT BETWEEN 1 AND 25
        THROW 51740, N'BatchSize must be between 1 and 25.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @RunId BIGINT, @FundingSourceId INT, @RunStatus TINYINT;
    DECLARE @CurrentLeaseId UNIQUEIDENTIFIER, @LeaseUntilUtc DATETIME2(3);
    DECLARE @Expired TABLE (ItemId BIGINT PRIMARY KEY);
    DECLARE @ExpiredCount INT = 0;
    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_ListPendingItems7B;

    BEGIN TRY
        SELECT @RunId = Id, @FundingSourceId = FundingSourceId, @RunStatus = Status,
               @CurrentLeaseId = LeaseId, @LeaseUntilUtc = LeaseUntilUtc
        FROM dbo.FundingPlatform_ImportRuns WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @RunPublicId;
        IF @RunId IS NULL THROW 51741, N'Import run was not found.', 1;
        IF @RunStatus <> 1 THROW 51742, N'Import run is not running.', 1;
        IF @CurrentLeaseId <> @LeaseId OR @LeaseUntilUtc <= @NowUtc
            THROW 51743, N'Import run lease is stale.', 1;

        UPDATE items
        SET Status = 3, OutcomeCode = N'failed', CompletedAtUtc = @NowUtc,
            NormalizedSnapshotJson =
                N'{"schemaVersion":1,"opportunity":{"redacted":true}}',
            IsContentRedacted = 1, RedactedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc
        OUTPUT inserted.Id INTO @Expired (ItemId)
        FROM dbo.FundingPlatform_ImportRunItems AS items WITH (UPDLOCK, HOLDLOCK)
        WHERE items.ImportRunId = @RunId AND items.Status IN (0, 1)
          AND items.IsContentRedacted = 0 AND items.RetentionUntilUtc <= @NowUtc;
        SET @ExpiredCount = @@ROWCOUNT;

        IF @ExpiredCount > 0
        BEGIN
            UPDATE dbo.FundingPlatform_ImportRuns
            SET FailedCount = FailedCount + @ExpiredCount, UpdatedAtUtc = @NowUtc
            WHERE Id = @RunId;
            INSERT INTO dbo.FundingPlatform_ImportErrors
                (ImportRunId, FundingSourceId, ImportRunItemId, Stage, ErrorCode,
                 SanitizedMessage, IsRetryable, OccurredAtUtc, CreatedAtUtc)
            SELECT @RunId, @FundingSourceId, expired.ItemId, N'retention',
                   N'retention-expired',
                   N'The normalized item reached its retention deadline before staging.',
                   0, @NowUtc, @NowUtc
            FROM @Expired AS expired;
        END;

        SELECT TOP (@BatchSize) items.PublicId AS ItemPublicId,
               raw.PublicId AS RawObservationPublicId, items.ExternalId,
               items.NormalizedSnapshotVersion, items.NormalizedSnapshotJson,
               items.NormalizedSnapshotHash
        FROM dbo.FundingPlatform_ImportRunItems AS items
        INNER JOIN dbo.FundingPlatform_RawFundingOpportunities AS raw
            ON raw.Id = items.RawFundingOpportunityId
           AND raw.FundingSourceId = items.FundingSourceId
        WHERE items.ImportRunId = @RunId AND items.Status IN (0, 1)
          AND items.IsContentRedacted = 0 AND items.RetentionUntilUtc > @NowUtc
        ORDER BY items.Id;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ListPendingItems7B;
        THROW;
    END CATCH;
END;
GO

/* Blob-content retention is separate from SQL redaction. A claim freezes
   the exact immutable blob identities; scan/extraction mutations reject a
   document while deletion is leased or completed. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentContentRetention_Claim
    @BatchSize INT,
    @LeaseId UNIQUEIDENTIFIER,
    @LeaseSeconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @BatchSize NOT BETWEEN 1 AND 100 OR @LeaseId IS NULL OR @NowUtc IS NULL
       OR @LeaseSeconds NOT BETWEEN 30 AND 3600
        THROW 51869, N'Retention claim parameters are invalid.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @LeaseUntilUtc DATETIME2(3) = DATEADD(SECOND, @LeaseSeconds, @NowUtc);
    DECLARE @Claimed TABLE (DocumentId BIGINT PRIMARY KEY);
    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_DocumentRetentionClaim;

    BEGIN TRY
        /* A due blob without an immutable ETag cannot be deleted conditionally. */
        ;WITH UnsafeDue AS
        (
            SELECT TOP (@BatchSize) documents.*
            FROM dbo.FundingPlatform_SourceDocuments AS documents
                 WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
            WHERE documents.ContentRetentionStatus = 0
              AND documents.RetentionUntilUtc <= @NowUtc
              AND documents.ContentRetentionNextAttemptAtUtc <= @NowUtc
              AND documents.BlobETag IS NULL
            ORDER BY documents.RetentionUntilUtc, documents.Id
        )
        UPDATE UnsafeDue
        SET ContentRetentionStatus = 3,
            ContentRetentionLastErrorCode = N'quarantine-etag-required',
            UpdatedAtUtc = CASE WHEN UpdatedAtUtc > @NowUtc THEN UpdatedAtUtc ELSE @NowUtc END;

        ;WITH Exhausted AS
        (
            SELECT TOP (@BatchSize) documents.*
            FROM dbo.FundingPlatform_SourceDocuments AS documents
                 WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
            WHERE documents.ContentRetentionStatus = 1
              AND documents.ContentRetentionLeaseUntilUtc <= @NowUtc
              AND documents.ContentRetentionAttemptCount >= documents.ContentRetentionMaxAttempts
            ORDER BY documents.ContentRetentionLeaseUntilUtc, documents.Id
        )
        UPDATE Exhausted
        SET ContentRetentionStatus = 3,
            ContentRetentionLeaseId = NULL, ContentRetentionLeaseUntilUtc = NULL,
            ContentRetentionLastErrorCode = N'retries-exhausted',
            UpdatedAtUtc = CASE WHEN UpdatedAtUtc > @NowUtc THEN UpdatedAtUtc ELSE @NowUtc END;

        ;WITH Candidates AS
        (
            SELECT TOP (@BatchSize) documents.*
            FROM dbo.FundingPlatform_SourceDocuments AS documents
                 WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
            WHERE documents.BlobETag IS NOT NULL
              AND documents.RetentionUntilUtc <= @NowUtc
              AND documents.ContentRetentionAttemptCount < documents.ContentRetentionMaxAttempts
              AND ((documents.ContentRetentionStatus = 0
                    AND documents.ContentRetentionNextAttemptAtUtc <= @NowUtc)
                   OR (documents.ContentRetentionStatus = 1
                       AND documents.ContentRetentionLeaseUntilUtc <= @NowUtc))
            ORDER BY documents.RetentionUntilUtc, documents.Id
        )
        UPDATE Candidates
        SET ContentRetentionStatus = 1,
            ContentRetentionAttemptCount = ContentRetentionAttemptCount + 1,
            ContentRetentionLeaseId = @LeaseId,
            ContentRetentionLeaseUntilUtc = @LeaseUntilUtc,
            ContentRetentionLastErrorCode = NULL,
            UpdatedAtUtc = CASE WHEN UpdatedAtUtc > @NowUtc THEN UpdatedAtUtc ELSE @NowUtc END
        OUTPUT inserted.Id INTO @Claimed (DocumentId);

        UPDATE jobs
        SET Status = 6, LeaseId = NULL, LeaseUntilUtc = NULL,
            LastErrorCode = N'content-retention-due',
            LastErrorMessage = N'The source document reached its retention deadline.',
            CompletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc
        FROM dbo.FundingPlatform_SourceDocumentExtractionJobs AS jobs
        INNER JOIN @Claimed AS claimed ON claimed.DocumentId = jobs.SourceDocumentId
        WHERE jobs.Status IN (1, 2);

        UPDATE documents
        SET ExtractionStatus = CASE WHEN ExtractionStatus IN (1, 2) THEN 6
                                    ELSE ExtractionStatus END,
            UpdatedAtUtc = CASE WHEN UpdatedAtUtc > @NowUtc THEN UpdatedAtUtc ELSE @NowUtc END
        FROM dbo.FundingPlatform_SourceDocuments AS documents
        INNER JOIN @Claimed AS claimed ON claimed.DocumentId = documents.Id;

        /* An authenticated Event Grid delivery may have been accepted immediately
           before the retention lease won the document lock.  Finalize that receipt
           as an ignored terminal outcome in the same transaction so neither an
           in-flight handler nor a replay can reopen content scheduled for deletion. */
        UPDATE receipts
        SET ReceiptStatus = 2,
            OutcomeCode = N'content-retention-ignored',
            FinalizedAtUtc = @NowUtc
        FROM dbo.FundingPlatform_SourceDocumentDefenderReceipts AS receipts
        INNER JOIN @Claimed AS claimed ON claimed.DocumentId = receipts.SourceDocumentId
        WHERE receipts.ReceiptStatus = 0;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_DocumentRetentionClaim;
        THROW;
    END CATCH;

    SELECT documents.PublicId AS SourceDocumentPublicId,
           documents.FundingSourceId, documents.ContentHash, documents.ContentLength,
           documents.BlobContainer AS QuarantineBlobContainer,
           documents.BlobObjectName AS QuarantineBlobObjectName,
           documents.BlobETag AS QuarantineBlobETag,
           documents.TrustedBlobContainer, documents.TrustedBlobObjectName,
           documents.TrustedBlobETag, documents.RetentionUntilUtc,
           documents.ContentRetentionAttemptCount AS AttemptCount,
           documents.ContentRetentionMaxAttempts AS MaxAttempts,
           documents.ContentRetentionLeaseUntilUtc AS LeaseUntilUtc,
           CAST(CASE WHEN documents.TrustedBlobContainer IS NOT NULL THEN 1 ELSE 0 END AS BIT)
               AS RequiresTrustedDelete
    FROM dbo.FundingPlatform_SourceDocuments AS documents
    WHERE documents.ContentRetentionStatus = 1
      AND documents.ContentRetentionLeaseId = @LeaseId
      AND documents.ContentRetentionLeaseUntilUtc > @NowUtc
    ORDER BY documents.RetentionUntilUtc, documents.Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentContentRetention_Complete
    @SourceDocumentPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @QuarantineDeleted BIT,
    @TrustedDeleted BIT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @SourceDocumentPublicId IS NULL OR @LeaseId IS NULL OR @NowUtc IS NULL
       OR @QuarantineDeleted IS NULL OR @TrustedDeleted IS NULL
        THROW 51870, N'Retention completion parameters are invalid.', 1;

    DECLARE @Status TINYINT, @StoredLease UNIQUEIDENTIFIER;
    DECLARE @LeaseUntil DATETIME2(3), @TrustedContainer NVARCHAR(63);
    DECLARE @DeletedAt DATETIME2(3), @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_DocumentRetentionComplete;
    BEGIN TRY
    SELECT @Status = ContentRetentionStatus, @StoredLease = ContentRetentionLeaseId,
           @LeaseUntil = ContentRetentionLeaseUntilUtc,
           @TrustedContainer = TrustedBlobContainer,
           @DeletedAt = ContentDeletionRequestedAtUtc
    FROM dbo.FundingPlatform_SourceDocuments WITH (UPDLOCK, ROWLOCK)
    WHERE PublicId = @SourceDocumentPublicId;

    IF @Status IS NULL SET @Code = N'not-found';
    ELSE IF @Status = 2
    BEGIN SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'completed'; END
    ELSE IF @Status <> 1 SET @Code = N'invalid-state';
    ELSE IF @StoredLease <> @LeaseId OR @LeaseUntil <= @NowUtc SET @Code = N'stale-lease';
    ELSE IF @QuarantineDeleted <> 1 OR (@TrustedContainer IS NOT NULL AND @TrustedDeleted <> 1)
        SET @Code = N'blob-delete-incomplete';
    ELSE
    BEGIN
        UPDATE dbo.FundingPlatform_SourceDocuments
        SET ContentRetentionStatus = 2, ContentRetentionLeaseId = NULL,
            ContentRetentionLeaseUntilUtc = NULL, ContentRetentionLastErrorCode = NULL,
            ContentDeletionRequestedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc
        WHERE PublicId = @SourceDocumentPublicId;
        INSERT INTO dbo.FundingPlatform_OutboxMessages
            (MessageType, AggregateType, AggregateId, PayloadJson,
             OccurredAtUtc, AvailableAtUtc)
        SELECT N'SourceDocumentContentDeletionRequested', N'SourceDocument',
               CONVERT(NVARCHAR(100), @SourceDocumentPublicId),
               (SELECT @SourceDocumentPublicId AS sourceDocumentId, 1 AS [version]
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
        SET @Succeeded = 1; SET @Code = N'completed'; SET @DeletedAt = @NowUtc;
    END;

    IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_DocumentRetentionComplete;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @SourceDocumentPublicId AS SourceDocumentPublicId,
           @DeletedAt AS ContentDeletionRequestedAtUtc, @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentContentRetention_Fail
    @SourceDocumentPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @ErrorCode NVARCHAR(100),
    @IsRetryable BIT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ErrorCode = LOWER(LTRIM(RTRIM(@ErrorCode)));
    IF @SourceDocumentPublicId IS NULL OR @LeaseId IS NULL OR @NowUtc IS NULL
       OR @IsRetryable IS NULL OR NULLIF(@ErrorCode, N'') IS NULL
       OR LEN(@ErrorCode) > 100
       OR @ErrorCode LIKE N'%[^-a-z0-9._]%' COLLATE Latin1_General_100_BIN2
        THROW 51871, N'Retention failure parameters are invalid.', 1;

    DECLARE @Status TINYINT, @StoredLease UNIQUEIDENTIFIER;
    DECLARE @LeaseUntil DATETIME2(3), @Attempts SMALLINT, @MaxAttempts SMALLINT;
    DECLARE @NextAttempt DATETIME2(3), @Succeeded BIT = 0, @Code NVARCHAR(50) = N'not-found';
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_DocumentRetentionFail;
    BEGIN TRY
    SELECT @Status = ContentRetentionStatus, @StoredLease = ContentRetentionLeaseId,
           @LeaseUntil = ContentRetentionLeaseUntilUtc,
           @Attempts = ContentRetentionAttemptCount,
           @MaxAttempts = ContentRetentionMaxAttempts
    FROM dbo.FundingPlatform_SourceDocuments WITH (UPDLOCK, ROWLOCK)
    WHERE PublicId = @SourceDocumentPublicId;

    IF @Status IS NULL SET @Code = N'not-found';
    ELSE IF @Status = 2 BEGIN SET @Succeeded = 1; SET @Code = N'already-completed'; END
    ELSE IF @Status <> 1 SET @Code = N'invalid-state';
    ELSE IF @StoredLease <> @LeaseId OR @LeaseUntil <= @NowUtc SET @Code = N'stale-lease';
    ELSE
    BEGIN
        IF @IsRetryable = 1 AND @Attempts < @MaxAttempts
            SET @NextAttempt = DATEADD(SECOND,
                CASE WHEN POWER(CONVERT(BIGINT, 2), @Attempts) * 30 > 3600 THEN 3600
                     ELSE CONVERT(INT, POWER(CONVERT(BIGINT, 2), @Attempts) * 30) END,
                @NowUtc);
        UPDATE dbo.FundingPlatform_SourceDocuments
        SET ContentRetentionStatus = CASE WHEN @NextAttempt IS NULL THEN 3 ELSE 0 END,
            ContentRetentionLeaseId = NULL, ContentRetentionLeaseUntilUtc = NULL,
            ContentRetentionNextAttemptAtUtc = COALESCE(@NextAttempt,
                                                       ContentRetentionNextAttemptAtUtc),
            ContentRetentionLastErrorCode = @ErrorCode, UpdatedAtUtc = @NowUtc
        WHERE PublicId = @SourceDocumentPublicId;
        SET @Succeeded = 1;
        SET @Code = CASE WHEN @NextAttempt IS NULL THEN N'failed' ELSE N'retry-scheduled' END;
    END;

    IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_DocumentRetentionFail;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @SourceDocumentPublicId AS SourceDocumentPublicId,
           @NextAttempt AS NextAttemptAtUtc, @Attempts AS AttemptCount,
           @MaxAttempts AS MaxAttempts;
END;
GO

/* Internal retention worker. It redacts only due terminal content, never
   identifiers, hashes, policy snapshots, timestamps or provenance links. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ContentRetention_Enforce
    @BatchSize INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @BatchSize NOT BETWEEN 1 AND 500
        THROW 51859, N'BatchSize must be between 1 and 500.', 1;
    IF @NowUtc IS NULL
        THROW 51860, N'NowUtc is required.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @RunPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @StartedAtUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @CompletedAtUtc DATETIME2(3);
    DECLARE @RawCount INT = 0, @ItemCount INT = 0;
    DECLARE @ResultCount INT = 0, @EvidenceCount INT = 0;

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_ContentRetention;

    BEGIN TRY
        ;WITH DueItems AS
        (
            SELECT TOP (@BatchSize) *
            FROM dbo.FundingPlatform_ImportRunItems
                 WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
            WHERE Status IN (2, 3) AND IsContentRedacted = 0
              AND RetentionUntilUtc <= @NowUtc
            ORDER BY RetentionUntilUtc, Id
        )
        UPDATE DueItems
        SET NormalizedSnapshotJson =
                N'{"schemaVersion":1,"opportunity":{"redacted":true}}',
            IsContentRedacted = 1, RedactedAtUtc = @NowUtc,
            UpdatedAtUtc = CASE WHEN UpdatedAtUtc > @NowUtc THEN UpdatedAtUtc ELSE @NowUtc END;
        SET @ItemCount = @@ROWCOUNT;

        ;WITH DueEvidence AS
        (
            SELECT TOP (@BatchSize) evidence.*
            FROM dbo.FundingPlatform_SourceDocumentExtractionEvidence AS evidence
                 WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
            INNER JOIN dbo.FundingPlatform_SourceDocumentExtractionJobs AS jobs
                ON jobs.Id = evidence.ExtractionJobId
            WHERE jobs.Status BETWEEN 3 AND 6
              AND evidence.IsContentRedacted = 0
              AND evidence.RetentionUntilUtc <= @NowUtc
            ORDER BY evidence.RetentionUntilUtc, evidence.Id
        )
        UPDATE DueEvidence
        SET Excerpt = N'[redacted]', IsContentRedacted = 1, RedactedAtUtc = @NowUtc;
        SET @EvidenceCount = @@ROWCOUNT;

        ;WITH DueResults AS
        (
            SELECT TOP (@BatchSize) results.*
            FROM dbo.FundingPlatform_SourceDocumentExtractionResults AS results
                 WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
            INNER JOIN dbo.FundingPlatform_SourceDocumentExtractionJobs AS jobs
                ON jobs.Id = results.ExtractionJobId
            WHERE jobs.Status BETWEEN 3 AND 6
              AND results.IsContentRedacted = 0
              AND results.RetentionUntilUtc <= @NowUtc
              AND NOT EXISTS
                  (SELECT 1
                   FROM dbo.FundingPlatform_SourceDocumentExtractionEvidence AS evidence
                   WHERE evidence.ExtractionResultId = results.Id
                     AND evidence.IsContentRedacted = 0)
            ORDER BY results.RetentionUntilUtc, results.Id
        )
        UPDATE DueResults
        SET ExtractedText = N'', CharacterCount = 0,
            IsContentRedacted = 1, RedactedAtUtc = @NowUtc;
        SET @ResultCount = @@ROWCOUNT;

        ;WITH DueRaw AS
        (
            SELECT TOP (@BatchSize) raw.*
            FROM dbo.FundingPlatform_RawFundingOpportunities AS raw
                 WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
            WHERE raw.IsContentRedacted = 0 AND raw.RetentionUntilUtc <= @NowUtc
            ORDER BY raw.RetentionUntilUtc, raw.Id
        )
        UPDATE DueRaw
        SET RawContent = N'{"redacted":true}',
            IsContentRedacted = 1, RedactedAtUtc = @NowUtc;
        SET @RawCount = @@ROWCOUNT;

        SET @CompletedAtUtc = SYSUTCDATETIME();
        INSERT INTO dbo.FundingPlatform_ContentRetentionRuns
            (PublicId, CutoffUtc, RawRedactedCount, ItemRedactedCount,
             ResultRedactedCount, EvidenceRedactedCount, StartedAtUtc, CompletedAtUtc)
        VALUES (@RunPublicId, @NowUtc, @RawCount, @ItemCount,
                @ResultCount, @EvidenceCount, @StartedAtUtc, @CompletedAtUtc);

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ContentRetention;
        THROW;
    END CATCH;

    SELECT @RunPublicId AS RunPublicId, @RawCount AS RawRedactedCount,
           @ItemCount AS ItemRedactedCount, @ResultCount AS ResultRedactedCount,
           @EvidenceCount AS EvidenceRedactedCount,
           @StartedAtUtc AS StartedAtUtc, @CompletedAtUtc AS CompletedAtUtc;
END;
GO

/* Defender has no generally available rescan command in this local phase.
   Keep fake-provider retry support, but never report a Microsoft Defender retry
   as queued when no consumer exists. */
EXEC sys.sp_rename
    @objname = N'dbo.FundingPlatform_usp_SourceDocument_RetryScan',
    @newname = N'FundingPlatform_usp_SourceDocument_RetryScan_7A',
    @objtype = N'OBJECT';
GO

CREATE PROCEDURE dbo.FundingPlatform_usp_SourceDocument_RetryScan
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @SourceDocumentPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT =
        dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51863, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51864, N'MFA is required for this administrative operation.', 1;

    /* Revalidate the actor under the same durable lock contract used by the
       original mutation before returning the fail-closed Defender outcome. */
    DECLARE @ActorUserId BIGINT;
    EXEC dbo.FundingPlatform_usp_AdminActor_Lock
        @AdminUserPublicId, @ActorUserId OUTPUT;

    DECLARE @StorageStatus TINYINT, @ScanStatus TINYINT, @ScanProvider TINYINT;
    DECLARE @ScanAttemptCount SMALLINT, @RowVersion BINARY(8);
    SELECT @StorageStatus = StorageStatus, @ScanStatus = ScanStatus,
           @ScanProvider = ScanProvider, @ScanAttemptCount = ScanAttemptCount,
           @RowVersion = RowVersion
    FROM dbo.FundingPlatform_SourceDocuments
    WHERE PublicId = @SourceDocumentPublicId;

    IF @ScanProvider IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'not-found' AS Code,
               @SourceDocumentPublicId AS SourceDocumentPublicId,
               CAST(NULL AS TINYINT) AS StorageStatus,
               CAST(NULL AS TINYINT) AS ScanStatus,
               CAST(NULL AS TINYINT) AS ScanProvider,
               CAST(NULL AS SMALLINT) AS ScanAttemptCount,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @ExpectedRowVersion IS NULL OR @IdempotencyKeyHash IS NULL OR @RequestHash IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               @SourceDocumentPublicId AS SourceDocumentPublicId,
               @StorageStatus AS StorageStatus, @ScanStatus AS ScanStatus,
               @ScanProvider AS ScanProvider, @ScanAttemptCount AS ScanAttemptCount,
               @RowVersion AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @ScanProvider = 1
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded,
               N'defender-rescan-not-configured' AS Code,
               @SourceDocumentPublicId AS SourceDocumentPublicId,
               @StorageStatus AS StorageStatus, @ScanStatus AS ScanStatus,
               @ScanProvider AS ScanProvider, @ScanAttemptCount AS ScanAttemptCount,
               @RowVersion AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    EXEC dbo.FundingPlatform_usp_SourceDocument_RetryScan_7A
        @AdminUserPublicId = @AdminUserPublicId,
        @SourceDocumentPublicId = @SourceDocumentPublicId,
        @ExpectedRowVersion = @ExpectedRowVersion,
        @IdempotencyKeyHash = @IdempotencyKeyHash,
        @RequestHash = @RequestHash;
END;
GO

/* A later authenticated Defender threat for the exact immutable blob version
   can revoke an earlier clean result. Trusted blob identity is returned so the
   caller can delete it conditionally; it is also persisted for replay safety. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocument_ApplyScanResult
    @SourceDocumentPublicId UNIQUEIDENTIFIER,
    @ScanProvider TINYINT,
    @ProviderEventId NVARCHAR(200),
    @PayloadHash BINARY(32),
    @BlobETag NVARCHAR(100),
    @ReportedContentHash BINARY(32) = NULL,
    @ToStatus TINYINT,
    @ResultCode NVARCHAR(100),
    @TrustedBlobContainer NVARCHAR(63) = NULL,
    @TrustedBlobObjectName NVARCHAR(1024) = NULL,
    @TrustedBlobETag NVARCHAR(100) = NULL,
    @OccurredAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ProviderEventId = LTRIM(RTRIM(@ProviderEventId));
    SET @BlobETag = LTRIM(RTRIM(@BlobETag));
    SET @ResultCode = LOWER(LTRIM(RTRIM(@ResultCode)));
    SET @TrustedBlobContainer = NULLIF(LTRIM(RTRIM(@TrustedBlobContainer)), N'');
    SET @TrustedBlobObjectName = NULLIF(LTRIM(RTRIM(@TrustedBlobObjectName)), N'');
    SET @TrustedBlobETag = NULLIF(LTRIM(RTRIM(@TrustedBlobETag)), N'');

    IF @ScanProvider NOT BETWEEN 0 AND 1
       OR NULLIF(@ProviderEventId, N'') IS NULL OR LEN(@ProviderEventId) > 200
       OR @PayloadHash IS NULL OR LEN(@BlobETag) NOT BETWEEN 3 AND 100
       OR @ToStatus NOT BETWEEN 1 AND 4
       OR NULLIF(@ResultCode, N'') IS NULL OR LEN(@ResultCode) > 100
       OR @ResultCode LIKE N'%[^-a-z0-9._]%' COLLATE Latin1_General_100_BIN2
       OR @OccurredAtUtc IS NULL
       OR (@ToStatus IN (1, 2) AND @ReportedContentHash IS NULL)
       OR (@ToStatus = 1 AND (@TrustedBlobContainer IS NULL
           OR @TrustedBlobObjectName IS NULL OR @TrustedBlobETag IS NULL))
       OR (@ToStatus <> 1 AND (@TrustedBlobContainer IS NOT NULL
           OR @TrustedBlobObjectName IS NOT NULL OR @TrustedBlobETag IS NOT NULL))
       OR (@TrustedBlobObjectName IS NOT NULL
           AND (LEFT(@TrustedBlobObjectName, 1) = N'/'
                OR CHARINDEX(N'?', @TrustedBlobObjectName) > 0
                OR CHARINDEX(N'#', @TrustedBlobObjectName) > 0))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               @SourceDocumentPublicId AS SourceDocumentPublicId,
               CAST(NULL AS TINYINT) AS StorageStatus,
               CAST(NULL AS TINYINT) AS ScanStatus,
               CAST(NULL AS TINYINT) AS ScanProvider,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay,
               CAST(NULL AS NVARCHAR(63)) AS RevokedTrustedBlobContainer,
               CAST(NULL AS NVARCHAR(1024)) AS RevokedTrustedBlobObjectName,
               CAST(NULL AS NVARCHAR(100)) AS RevokedTrustedBlobETag;
        RETURN;
    END;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @DocumentId BIGINT, @StorageStatus TINYINT, @ScanStatus TINYINT;
    DECLARE @StoredProvider TINYINT, @StoredETag NVARCHAR(100), @StoredHash BINARY(32);
    DECLARE @ScanAttemptCount SMALLINT, @DocumentCreatedAtUtc DATETIME2(3);
    DECLARE @ContentRetentionStatus TINYINT;
    DECLARE @ScanStartedAtUtc DATETIME2(3), @ScanCompletedAtUtc DATETIME2(3);
    DECLARE @RowVersion BINARY(8), @ExistingDocumentId BIGINT;
    DECLARE @ExistingPayloadHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @ExistingFromStatus TINYINT, @ExistingETag NVARCHAR(100);
    DECLARE @ExistingHash BINARY(32), @ExistingResultCode NVARCHAR(100);
    DECLARE @ExistingRowVersion BINARY(8), @ExistingAttempts SMALLINT;
    DECLARE @RevokedContainer NVARCHAR(63), @RevokedObject NVARCHAR(1024);
    DECLARE @RevokedETag NVARCHAR(100);
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'not-found';

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_ApplyScan7B;

    BEGIN TRY
        SELECT @ExistingDocumentId = SourceDocumentId,
               @ExistingPayloadHash = PayloadHash,
               @ExistingFromStatus = FromStatus, @ExistingToStatus = ToStatus,
               @ExistingETag = BlobETag, @ExistingHash = ReportedContentHash,
               @ExistingResultCode = ResultCode,
               @ExistingRowVersion = ResultRowVersion,
               @ExistingAttempts = ResultScanAttemptCount,
               @RevokedContainer = RevokedTrustedBlobContainer,
               @RevokedObject = RevokedTrustedBlobObjectName,
               @RevokedETag = RevokedTrustedBlobETag
        FROM dbo.FundingPlatform_SourceDocumentScanEvents WITH (UPDLOCK, HOLDLOCK)
        WHERE ScanProvider = @ScanProvider AND ProviderEventId = @ProviderEventId;

        SELECT @DocumentId = Id, @StorageStatus = StorageStatus,
               @ScanStatus = ScanStatus, @StoredProvider = ScanProvider,
               @StoredETag = BlobETag, @StoredHash = ContentHash,
               @ScanAttemptCount = ScanAttemptCount,
               @DocumentCreatedAtUtc = CreatedAtUtc,
               @ScanStartedAtUtc = ScanStartedAtUtc,
               @ScanCompletedAtUtc = ScanCompletedAtUtc,
               @ContentRetentionStatus = ContentRetentionStatus,
               @RowVersion = RowVersion
        FROM dbo.FundingPlatform_SourceDocuments WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @SourceDocumentPublicId;

        IF @ExistingDocumentId IS NOT NULL
        BEGIN
            IF @ExistingDocumentId = @DocumentId
               AND @ExistingPayloadHash = @PayloadHash
               AND @ExistingToStatus = @ToStatus AND @ExistingETag = @BlobETag
               AND @ExistingResultCode = @ResultCode
               AND ((@ExistingHash IS NULL AND @ReportedContentHash IS NULL)
                    OR @ExistingHash = @ReportedContentHash)
            BEGIN
                SET @Succeeded = 1; SET @WasReplay = 1;
                SET @Code = CASE WHEN @ExistingFromStatus = 1
                                 THEN N'scan-result-superseded'
                                 ELSE N'scan-result-applied' END;
                SET @RowVersion = @ExistingRowVersion;
                SET @ScanAttemptCount = @ExistingAttempts;
            END
            ELSE SET @Code = N'event-conflict';
        END
        ELSE IF @DocumentId IS NULL SET @Code = N'not-found';
        ELSE IF @ContentRetentionStatus IN (1, 2, 3)
        BEGIN
            SET @Succeeded = 1;
            SET @Code = N'content-retention-ignored';
        END
        ELSE IF @StoredProvider <> @ScanProvider SET @Code = N'provider-mismatch';
        ELSE IF @StoredETag <> @BlobETag SET @Code = N'blob-etag-mismatch';
        ELSE IF @OccurredAtUtc < @DocumentCreatedAtUtc
             OR (@ScanStartedAtUtc IS NOT NULL AND @OccurredAtUtc < @ScanStartedAtUtc)
             OR @OccurredAtUtc > DATEADD(MINUTE, 5, @NowUtc)
            SET @Code = N'invalid-event-time';
        ELSE IF @ReportedContentHash IS NOT NULL AND @ReportedContentHash <> @StoredHash
            SET @Code = N'content-hash-mismatch';
        ELSE IF @StorageStatus = 1 AND @ScanStatus = 0
        BEGIN
            IF @ToStatus = 1 AND EXISTS
               (SELECT 1 FROM dbo.FundingPlatform_SourceDocuments
                WHERE Id = @DocumentId AND BlobContainer = @TrustedBlobContainer
                  AND BlobObjectName = @TrustedBlobObjectName)
                SET @Code = N'invalid-trusted-location';
            ELSE
            BEGIN
                DECLARE @NormalEventId UNIQUEIDENTIFIER = NEWID();
                DECLARE @NormalUpdated TABLE (RowVersion BINARY(8));
                UPDATE dbo.FundingPlatform_SourceDocuments
                SET ScanStatus = @ToStatus, ScanResultCode = @ResultCode,
                    ScanCompletedAtUtc = @OccurredAtUtc,
                    StorageStatus = CASE WHEN @ToStatus = 1 THEN 2 ELSE 1 END,
                    TrustedBlobContainer = CASE WHEN @ToStatus = 1
                                                THEN @TrustedBlobContainer END,
                    TrustedBlobObjectName = CASE WHEN @ToStatus = 1
                                                 THEN @TrustedBlobObjectName END,
                    TrustedBlobETag = CASE WHEN @ToStatus = 1 THEN @TrustedBlobETag END,
                    UpdatedAtUtc = @NowUtc
                OUTPUT inserted.RowVersion INTO @NormalUpdated
                WHERE Id = @DocumentId;
                SELECT @RowVersion = RowVersion FROM @NormalUpdated;

                INSERT INTO dbo.FundingPlatform_SourceDocumentScanEvents
                    (EventId, SourceDocumentId, ScanProvider, ProviderEventId, PayloadHash,
                     FromStatus, ToStatus, BlobETag, ReportedContentHash, ResultCode,
                     ActorUserId, IdempotencyKeyHash, RequestHash, ResultRowVersion,
                     ResultScanAttemptCount, OccurredAtUtc, CreatedAtUtc)
                VALUES (@NormalEventId, @DocumentId, @ScanProvider, @ProviderEventId,
                        @PayloadHash, 0, @ToStatus, @BlobETag, @ReportedContentHash,
                        @ResultCode, NULL, NULL, NULL, @RowVersion,
                        @ScanAttemptCount, @OccurredAtUtc, @NowUtc);
                SET @StorageStatus = CASE WHEN @ToStatus = 1 THEN 2 ELSE 1 END;
                SET @ScanStatus = @ToStatus; SET @Succeeded = 1;
                SET @Code = N'scan-result-applied';
            END;
        END
        ELSE IF @ScanProvider = 1 AND @StorageStatus = 2 AND @ScanStatus = 1
             AND @ToStatus IN (2, 3, 4)
        BEGIN
            IF @ReportedContentHash IS NULL SET @Code = N'content-hash-required';
            ELSE IF @ScanCompletedAtUtc IS NULL OR @OccurredAtUtc <= @ScanCompletedAtUtc
                SET @Code = N'stale-scan-result';
            ELSE
            BEGIN
                SELECT @RevokedContainer = TrustedBlobContainer,
                       @RevokedObject = TrustedBlobObjectName,
                       @RevokedETag = TrustedBlobETag
                FROM dbo.FundingPlatform_SourceDocuments WITH (HOLDLOCK)
                WHERE Id = @DocumentId;
                IF @RevokedContainer IS NULL OR @RevokedObject IS NULL OR @RevokedETag IS NULL
                    SET @Code = N'trusted-blob-identity-missing';
                ELSE
                BEGIN
                    DECLARE @SupersedeEventId UNIQUEIDENTIFIER = NEWID();
                    DECLARE @SupersedeUpdated TABLE (RowVersion BINARY(8));
                    UPDATE dbo.FundingPlatform_SourceDocuments
                    SET StorageStatus = 1, ScanStatus = @ToStatus,
                        ScanResultCode = @ResultCode, ScanCompletedAtUtc = @OccurredAtUtc,
                        TrustedBlobContainer = NULL, TrustedBlobObjectName = NULL,
                        TrustedBlobETag = NULL, ExtractionStatus = 6,
                        UpdatedAtUtc = @NowUtc
                    OUTPUT inserted.RowVersion INTO @SupersedeUpdated
                    WHERE Id = @DocumentId;
                    SELECT @RowVersion = RowVersion FROM @SupersedeUpdated;

                    UPDATE dbo.FundingPlatform_SourceDocumentExtractionJobs
                    SET Status = 6, LeaseId = NULL, LeaseUntilUtc = NULL,
                        LastErrorCode = N'security-scan-revoked',
                        LastErrorMessage = N'A later authenticated scan revoked the trusted document.',
                        CompletedAtUtc = COALESCE(CompletedAtUtc, @NowUtc), UpdatedAtUtc = @NowUtc
                    WHERE SourceDocumentId = @DocumentId AND Status IN (1, 2, 3, 4);

                    UPDATE dbo.FundingPlatform_SourceDocumentExtractionResults
                    SET IsSecurityRevoked = 1, SecurityRevokedAtUtc = @NowUtc,
                        SecurityRevocationCode = N'security-scan-revoked'
                    WHERE SourceDocumentId = @DocumentId AND IsSecurityRevoked = 0;

                    UPDATE links
                    SET IsSecurityRevoked = 1, SecurityRevokedAtUtc = @NowUtc
                    FROM dbo.FundingPlatform_SourceDocumentAcquisitionLinks AS links
                    INNER JOIN dbo.FundingPlatform_SourceDocumentExtractionResults AS results
                        ON results.Id = links.ExtractionResultId
                    WHERE results.SourceDocumentId = @DocumentId
                      AND links.IsSecurityRevoked = 0;

                    INSERT INTO dbo.FundingPlatform_SourceDocumentScanEvents
                        (EventId, SourceDocumentId, ScanProvider, ProviderEventId, PayloadHash,
                         FromStatus, ToStatus, BlobETag, ReportedContentHash, ResultCode,
                         ActorUserId, IdempotencyKeyHash, RequestHash, ResultRowVersion,
                         ResultScanAttemptCount, OccurredAtUtc, CreatedAtUtc,
                         RevokedTrustedBlobContainer, RevokedTrustedBlobObjectName,
                         RevokedTrustedBlobETag)
                    VALUES (@SupersedeEventId, @DocumentId, @ScanProvider, @ProviderEventId,
                            @PayloadHash, 1, @ToStatus, @BlobETag, @ReportedContentHash,
                            @ResultCode, NULL, NULL, NULL, @RowVersion,
                            @ScanAttemptCount, @OccurredAtUtc, @NowUtc,
                            @RevokedContainer, @RevokedObject, @RevokedETag);
                    SET @StorageStatus = 1; SET @ScanStatus = @ToStatus;
                    SET @Succeeded = 1; SET @Code = N'scan-result-superseded';
                END;
            END;
        END
        ELSE IF @ScanStatus = @ToStatus SET @Code = N'scan-result-ignored';
        ELSE SET @Code = N'invalid-transition';

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ApplyScan7B;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @SourceDocumentPublicId AS SourceDocumentPublicId,
           @StorageStatus AS StorageStatus, @ScanStatus AS ScanStatus,
           @StoredProvider AS ScanProvider, @RowVersion AS RowVersion,
           @WasReplay AS WasReplay,
           CASE WHEN @Code = N'scan-result-superseded'
                THEN @RevokedContainer END AS RevokedTrustedBlobContainer,
           CASE WHEN @Code = N'scan-result-superseded'
                THEN @RevokedObject END AS RevokedTrustedBlobObjectName,
           CASE WHEN @Code = N'scan-result-superseded'
                THEN @RevokedETag END AS RevokedTrustedBlobETag;
END;
GO

/* Administrative document detail exposes retention state without returning
   storage locations, ETags, content hashes or any credential-bearing value. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocument_Get
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @SourceDocumentPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51701, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51702, N'MFA is required for this administrative operation.', 1;

    SELECT documents.PublicId AS SourceDocumentPublicId,
           documents.FundingSourceId, sources.Name AS FundingSourceName,
           documents.OriginalFileName, documents.MimeType, documents.ContentLength,
           documents.StorageStatus, documents.ScanStatus, documents.ScanProvider,
           CAST(CASE WHEN documents.ScanProvider = 1 THEN 1 ELSE 0 END AS BIT)
               AS IsProductionScan,
           documents.ScanAttemptCount, documents.ScanResultCode,
           documents.ScanStartedAtUtc, documents.ScanCompletedAtUtc,
           documents.ExtractionStatus,
           documents.ContentRetentionStatus,
           documents.RetentionUntilUtc,
           documents.ContentDeletionRequestedAtUtc,
           documents.ContentRetentionLastErrorCode,
           uploaders.PublicId AS UploadedByUserPublicId,
           documents.CreatedAtUtc, documents.UpdatedAtUtc, documents.RowVersion
    FROM dbo.FundingPlatform_SourceDocuments AS documents
    INNER JOIN dbo.FundingPlatform_FundingSources AS sources
        ON sources.Id = documents.FundingSourceId
    INNER JOIN dbo.FundingPlatform_Users AS uploaders
        ON uploaders.Id = documents.UploadedByUserId
    WHERE documents.PublicId = @SourceDocumentPublicId;
END;
GO

/* Deployment assigns the extraction workload managed identity to this role.
   The migration deliberately creates no Azure principal and grants no table,
   schema, import, admin, or Event Grid permissions. */
IF DATABASE_PRINCIPAL_ID(N'FundingPlatform_ExtractionWorkerRole') IS NULL
    CREATE ROLE FundingPlatform_ExtractionWorkerRole AUTHORIZATION dbo;
GO

GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SourceDocumentExtraction_Claim
    TO FundingPlatform_ExtractionWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SourceDocumentExtraction_RenewLease
    TO FundingPlatform_ExtractionWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SourceDocumentExtraction_RecordEvidence
    TO FundingPlatform_ExtractionWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SourceDocumentExtraction_Complete
    TO FundingPlatform_ExtractionWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SourceDocumentExtraction_Fail
    TO FundingPlatform_ExtractionWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_SourceDocumentExtraction_RequeueStranded
    TO FundingPlatform_ExtractionWorkerRole;
GO
