/* Transactional regression smoke for FASE 7B governed document extraction. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_SourceDocumentExtractionJobs', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_SourceDocumentExtractionResults', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_SourceDocumentExtractionEvidence', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_SourceDocumentDefenderReceipts', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_EventIngressTrustPolicies', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_FundingOpportunityDuplicateCandidates', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_SourceDocumentExtraction_AdminStart', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_SourceDocumentScan_WatchdogTimeout', N'P') IS NULL
    THROW 53601, N'FASE 7B persistence objects are incomplete.', 1;

IF COL_LENGTH(N'dbo.FundingPlatform_SourceDocumentExtractionJobs', N'MaximumBytes') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_SourceDocumentExtractionResults', N'MaximumBytes') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_SourceDocumentDefenderReceipts', N'PayloadJson') IS NOT NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_SourceDocumentDefenderReceipts', N'MalwareName') IS NOT NULL
    THROW 53602, N'Extraction policy snapshots or receipt minimization are invalid.', 1;

DECLARE @ImportDetailDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ImportRun_Admin_Get'));
DECLARE @OutboxClaimDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ImportRunOutbox_Claim'));
DECLARE @ExtractionAdminGetDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_SourceDocumentExtraction_AdminGet'));
DECLARE @ExtractionAdminStartDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_SourceDocumentExtraction_AdminStart'));
IF CHARINDEX(N'DuplicateCandidatePublicId', COALESCE(@ImportDetailDefinition, N'')) = 0
   OR CHARINDEX(N'SourceDocumentExtractionRequested', COALESCE(@OutboxClaimDefinition, N'')) = 0
   OR CHARINDEX(N'IsContentRedacted', COALESCE(@ExtractionAdminGetDefinition, N'')) = 0
   OR CHARINDEX(N'RedactedAtUtc', COALESCE(@ExtractionAdminGetDefinition, N'')) = 0
   OR CHARINDEX(N'content-retention-redacted', COALESCE(@ExtractionAdminGetDefinition, N'')) = 0
   OR CHARINDEX(N'@MaximumPages NOT BETWEEN 1 AND 250',
                COALESCE(@ExtractionAdminStartDefinition, N'')) = 0
    THROW 53603, N'Import detail discovery or extraction dispatch is not wired.', 1;

DECLARE @ExtractionWorkerRoleId INT =
    DATABASE_PRINCIPAL_ID(N'FundingPlatform_ExtractionWorkerRole');
DECLARE @ExtractionWorkerProcedures TABLE
(
    ObjectId INT NOT NULL PRIMARY KEY
);
INSERT INTO @ExtractionWorkerProcedures (ObjectId)
SELECT OBJECT_ID(required.Name, N'P')
FROM (VALUES
    (N'dbo.FundingPlatform_usp_SourceDocumentExtraction_Claim'),
    (N'dbo.FundingPlatform_usp_SourceDocumentExtraction_RenewLease'),
    (N'dbo.FundingPlatform_usp_SourceDocumentExtraction_RecordEvidence'),
    (N'dbo.FundingPlatform_usp_SourceDocumentExtraction_Complete'),
    (N'dbo.FundingPlatform_usp_SourceDocumentExtraction_Fail'),
    (N'dbo.FundingPlatform_usp_SourceDocumentExtraction_RequeueStranded')
) AS required(Name)
WHERE OBJECT_ID(required.Name, N'P') IS NOT NULL;

IF @ExtractionWorkerRoleId IS NULL
   OR (SELECT COUNT(*) FROM @ExtractionWorkerProcedures) <> 6
   OR EXISTS
      (
          SELECT 1
          FROM @ExtractionWorkerProcedures AS required
          WHERE NOT EXISTS
          (
              SELECT 1
              FROM sys.database_permissions AS permissions
              WHERE permissions.grantee_principal_id = @ExtractionWorkerRoleId
                AND permissions.class = 1
                AND permissions.major_id = required.ObjectId
                AND permissions.permission_name = N'EXECUTE'
                AND permissions.state IN (N'G', N'W')
          )
      )
    THROW 53690, N'The extraction worker role is missing a required procedure grant.', 1;

IF EXISTS
   (
       SELECT 1
       FROM sys.database_permissions AS permissions
       WHERE permissions.grantee_principal_id = @ExtractionWorkerRoleId
         AND (permissions.class <> 1
              OR permissions.permission_name <> N'EXECUTE'
              OR NOT EXISTS
                 (SELECT 1 FROM @ExtractionWorkerProcedures AS allowed
                  WHERE allowed.ObjectId = permissions.major_id))
   )
    THROW 53691, N'The extraction worker role has permissions outside its bounded contract.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke016;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @Suffix NVARCHAR(32) =
        REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'');
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @NowMinusOneMinute DATETIME2(3) = DATEADD(MINUTE, -1, @NowUtc);
    DECLARE @NowPlusOneSecond DATETIME2(3) = DATEADD(SECOND, 1, @NowUtc);
    DECLARE @NowPlusTwoSeconds DATETIME2(3) = DATEADD(SECOND, 2, @NowUtc);
    DECLARE @NowPlusThreeSeconds DATETIME2(3) = DATEADD(SECOND, 3, @NowUtc);
    DECLARE @NowPlusFourSeconds DATETIME2(3) = DATEADD(SECOND, 4, @NowUtc);
    DECLARE @NowPlusFiveSeconds DATETIME2(3) = DATEADD(SECOND, 5, @NowUtc);
    DECLARE @NowPlusSixSeconds DATETIME2(3) = DATEADD(SECOND, 6, @NowUtc);
    DECLARE @NowPlusTwoMinutes DATETIME2(3) = DATEADD(MINUTE, 2, @NowUtc);
    DECLARE @NowPlusFourMinutes DATETIME2(3) = DATEADD(MINUTE, 4, @NowUtc);
    DECLARE @NowPlusSixMinutes DATETIME2(3) = DATEADD(MINUTE, 6, @NowUtc);
    DECLARE @NowPlusSevenMinutes DATETIME2(3) = DATEADD(MINUTE, 7, @NowUtc);
    DECLARE @AdminPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @AdminEmail NVARCHAR(320) = N'phase7b-' + @Suffix + N'@example.invalid';

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@AdminPublicId, @AdminEmail, UPPER(@AdminEmail), N'Phase 7B smoke administrator',
         N'not-a-credential', N'phase7b-smoke', 1, 1, 2, N'es-CL');

    DECLARE @AdminUserId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @AdminPublicId);
    DECLARE @SuperAdminRoleId SMALLINT =
        (SELECT Id FROM dbo.FundingPlatform_Roles WHERE NormalizedName = N'SUPERADMIN');
    DECLARE @ManualSourceId INT =
        (SELECT Id FROM dbo.FundingPlatform_FundingSources
         WHERE ProviderCode = N'manual-document');
    DECLARE @ApiSourceId INT =
        (SELECT Id FROM dbo.FundingPlatform_FundingSources
         WHERE ProviderCode = N'grants-gov');
    IF @SuperAdminRoleId IS NULL OR @ManualSourceId IS NULL OR @ApiSourceId IS NULL
        THROW 53604, N'FASE 7B smoke prerequisites are missing.', 1;
    INSERT INTO dbo.FundingPlatform_UserRoles (UserId, RoleId, GrantedByUserId)
    VALUES (@AdminUserId, @SuperAdminRoleId, @AdminUserId);

    DECLARE @ApiPolicyFingerprint BINARY(32), @ApiSearchEndpointHash BINARY(32);
    DECLARE @ApiPolicyVersion INT, @ApiRetentionDays SMALLINT;
    DECLARE @ManualPolicyVersion INT, @ManualRetentionDays SMALLINT;
    SELECT @ManualPolicyVersion = policies.PolicyVersion,
           @ManualRetentionDays = policies.ContentRetentionDays
    FROM dbo.FundingPlatform_FundingSources AS sources
    INNER JOIN dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions AS policies
        ON policies.FundingSourceId = sources.Id
       AND policies.PolicyVersion = sources.AcquisitionPolicyVersion
    WHERE sources.Id = @ManualSourceId;
    SELECT @ApiPolicyFingerprint = policies.PolicyFingerprint,
           @ApiPolicyVersion = policies.PolicyVersion,
           @ApiRetentionDays = policies.ContentRetentionDays
    FROM dbo.FundingPlatform_FundingSources AS sources
    INNER JOIN dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions AS policies
        ON policies.FundingSourceId = sources.Id
       AND policies.PolicyVersion = sources.AcquisitionPolicyVersion
    WHERE sources.Id = @ApiSourceId;
    SELECT @ApiSearchEndpointHash = endpoints.CanonicalUriHash
    FROM dbo.FundingPlatform_FundingSources AS sources
    INNER JOIN dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions AS policies
        ON policies.FundingSourceId = sources.Id
       AND policies.PolicyVersion = sources.AcquisitionPolicyVersion
    INNER JOIN dbo.FundingPlatform_FundingSourceAcquisitionPolicyEndpoints AS endpoints
        ON endpoints.PolicyId = policies.Id AND endpoints.FundingSourceId = sources.Id
    WHERE sources.Id = @ApiSourceId AND endpoints.EndpointKind = 2
      AND endpoints.CanonicalUri = N'https://api.grants.gov/v1/api/search2';
    IF @ApiPolicyFingerprint IS NULL OR @ApiSearchEndpointHash IS NULL
       OR @ApiPolicyVersion IS NULL OR @ApiRetentionDays IS NULL
       OR @ManualPolicyVersion IS NULL OR @ManualRetentionDays IS NULL
        THROW 53667, N'The exact acquisition policy fixture is incomplete.', 1;

    /* Network acquisition remains exact-host and compliance fail-closed. */
    DECLARE @PolicyResolution TABLE
    (
        Allowed BIT, Code NVARCHAR(50), FundingSourceId INT,
        RequestRateLimitPerMinute INT NULL, MaximumResponseBytes BIGINT NULL,
        ContentRetentionDays SMALLINT NULL
    );
    INSERT INTO @PolicyResolution
    EXEC dbo.FundingPlatform_usp_FundingSource_AcquisitionPolicy_Resolve
        @FundingSourceId = @ApiSourceId, @Scheme = N'https',
        @HostName = N'api.grants.gov', @Port = 443, @NowUtc = @NowUtc;
    IF NOT EXISTS (SELECT 1 FROM @PolicyResolution WHERE Allowed = 1 AND Code = N'allowed')
        THROW 53605, N'The approved official API policy did not resolve.', 1;
    DELETE FROM @PolicyResolution;
    INSERT INTO @PolicyResolution
    EXEC dbo.FundingPlatform_usp_FundingSource_AcquisitionPolicy_Resolve
        @FundingSourceId = @ApiSourceId, @Scheme = N'https',
        @HostName = N'localhost', @Port = 443, @NowUtc = @NowUtc;
    IF NOT EXISTS (SELECT 1 FROM @PolicyResolution WHERE Allowed = 0 AND Code = N'host-not-allowed')
        THROW 53606, N'An unlisted acquisition host was accepted.', 1;

    DECLARE @Authorization TABLE
    (
        Allowed BIT, Code NVARCHAR(50), FundingSourceId INT,
        ReservedAtUtc DATETIME2(3) NULL, NextAllowedAtUtc DATETIME2(3) NULL,
        RetryAfterMilliseconds INT NULL, RequestRateLimitPerMinute INT NULL,
        MaximumResponseBytes INT NULL, ContentRetentionDays SMALLINT NULL,
        AcquisitionPolicyVersion INT NULL, AcquisitionPolicyFingerprint BINARY(32) NULL,
        AppliedIntervalMilliseconds INT NULL
    );
    INSERT INTO @Authorization
    EXEC dbo.FundingPlatform_usp_FundingSource_AcquisitionRequest_Authorize
        @FundingSourceId = @ApiSourceId, @Scheme = N'https',
        @HostName = N'api.grants.gov', @Port = 443,
        @CanonicalDestinationHash = @ApiSearchEndpointHash,
        @AcquisitionPolicyFingerprint = @ApiPolicyFingerprint,
        @MinimumIntervalMilliseconds = 2000, @NowUtc = @NowUtc;
    DECLARE @FirstReservation DATETIME2(3) =
        (SELECT ReservedAtUtc FROM @Authorization WHERE Allowed = 1);
    DECLARE @FirstNextAllowed DATETIME2(3) =
        (SELECT NextAllowedAtUtc FROM @Authorization WHERE Allowed = 1);
    IF @FirstReservation <> @NowUtc
       OR @FirstNextAllowed <> DATEADD(MILLISECOND, 2000, @FirstReservation)
       OR NOT EXISTS
          (SELECT 1 FROM @Authorization
           WHERE Code = N'reserved' AND RetryAfterMilliseconds = 0
             AND RequestRateLimitPerMinute BETWEEN 1 AND 600
             AND MaximumResponseBytes BETWEEN 1024 AND 26214400
             AND ContentRetentionDays BETWEEN 1 AND 3650
             AND AcquisitionPolicyVersion >= 1
             AND AcquisitionPolicyFingerprint = @ApiPolicyFingerprint
             AND AppliedIntervalMilliseconds = 2000)
        THROW 53651, N'The first global acquisition slot was not reserved with its policy.', 1;

    DELETE FROM @Authorization;
    INSERT INTO @Authorization
    EXEC dbo.FundingPlatform_usp_FundingSource_AcquisitionRequest_Authorize
        @FundingSourceId = @ApiSourceId, @Scheme = N'https',
        @HostName = N'api.grants.gov', @Port = 443,
        @CanonicalDestinationHash = @ApiSearchEndpointHash,
        @AcquisitionPolicyFingerprint = @ApiPolicyFingerprint,
        @MinimumIntervalMilliseconds = 2000, @NowUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @Authorization
        WHERE Allowed = 1 AND Code = N'reserved'
          AND ReservedAtUtc = @FirstNextAllowed AND RetryAfterMilliseconds > 0
          AND NextAllowedAtUtc = DATEADD(MILLISECOND, 2000, ReservedAtUtc)
          AND AppliedIntervalMilliseconds = 2000)
        THROW 53652, N'Global acquisition rate reservation is not serialized.', 1;

    DELETE FROM @Authorization;
    INSERT INTO @Authorization
    EXEC dbo.FundingPlatform_usp_FundingSource_AcquisitionRequest_Authorize
        @FundingSourceId = @ApiSourceId, @Scheme = N'https',
        @HostName = N'127.0.0.1', @Port = 443,
        @CanonicalDestinationHash = @ApiSearchEndpointHash,
        @AcquisitionPolicyFingerprint = @ApiPolicyFingerprint,
        @MinimumIntervalMilliseconds = 2000, @NowUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @Authorization
        WHERE Allowed = 0 AND Code = N'endpoint-not-allowed'
          AND MaximumResponseBytes IS NULL)
        THROW 53653, N'A private acquisition endpoint was authorized.', 1;

    UPDATE dbo.FundingPlatform_FundingSources SET IsEnabled = 0 WHERE Id = @ApiSourceId;
    DELETE FROM @Authorization;
    INSERT INTO @Authorization
    EXEC dbo.FundingPlatform_usp_FundingSource_AcquisitionRequest_Authorize
        @FundingSourceId = @ApiSourceId, @Scheme = N'https',
        @HostName = N'api.grants.gov', @Port = 443,
        @CanonicalDestinationHash = @ApiSearchEndpointHash,
        @AcquisitionPolicyFingerprint = @ApiPolicyFingerprint,
        @MinimumIntervalMilliseconds = 2000,
        @NowUtc = @NowPlusTwoSeconds;
    IF NOT EXISTS
       (SELECT 1 FROM @Authorization WHERE Allowed = 0 AND Code = N'source-disabled')
        THROW 53654, N'A revoked acquisition source authorized a request.', 1;
    UPDATE dbo.FundingPlatform_FundingSources SET IsEnabled = 1 WHERE Id = @ApiSourceId;

    DECLARE @GovernanceConstraintError INT;
    SET XACT_ABORT OFF;
    BEGIN TRY
        UPDATE dbo.FundingPlatform_FundingSources
        SET LicenseStatus = 3, AllowedHostsRequired = 0
        WHERE Id = @ApiSourceId;
    END TRY
    BEGIN CATCH
        SET @GovernanceConstraintError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;
    IF ISNULL(@GovernanceConstraintError, 0) <> 547
        THROW 53607, N'Approved network sources can bypass license or host governance.', 1;

    /* Durable staging binds the leased source id to its exact provider code.
       A mismatch is advisory failure only and cannot create a source or draft. */
    DECLARE @StageSourceCountBefore BIGINT =
        (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_FundingSources);
    DECLARE @StageOpportunityCountBefore BIGINT =
        (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_FundingOpportunities);
    DECLARE @StageExternalId NVARCHAR(250) = N'phase7b-stage-' + @Suffix;
    DECLARE @StageSlug NVARCHAR(320) = N'phase7b-stage-' + LOWER(@Suffix);
    DECLARE @StageSourceItemKeyHash BINARY(32) =
        HASHBYTES('SHA2_256', @StageExternalId);
    DECLARE @StageSourceUrl NVARCHAR(2048) = N'https://api.grants.gov/v1/api/search2';
    DECLARE @StageCanonicalUrlHash BINARY(32) = HASHBYTES(
        'SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
        @StageSourceUrl COLLATE Latin1_General_100_BIN2_UTF8)));
    DECLARE @StageSnapshot NVARCHAR(MAX) =
        (SELECT @StageExternalId AS externalId, N'Phase 7B governed draft' AS title
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @StageContentHash BINARY(32) = HASHBYTES(
        'SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
        @StageSnapshot COLLATE Latin1_General_100_BIN2_UTF8)));
    DECLARE @StageResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50),
        FundingOpportunityPublicId UNIQUEIDENTIFIER NULL,
        ContentVersion INT NULL, PublicationStatus TINYINT NULL,
        RowVersion BINARY(8) NULL, StagedRevisionPublicId UNIQUEIDENTIFIER NULL
    );
    INSERT INTO @StageResult
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_StageExternal
        @FundingSourceId = @ApiSourceId, @ExpectedProviderCode = N'wrong-provider',
        @ExternalId = @StageExternalId, @SourceItemKeyHash = @StageSourceItemKeyHash,
        @SourceUrl = @StageSourceUrl, @CanonicalUrlHash = @StageCanonicalUrlHash,
        @ObservedAtUtc = @NowUtc, @Slug = @StageSlug,
        @Title = N'Phase 7B governed draft', @SponsorName = N'Official smoke sponsor',
        @AmountStatus = 0, @DeadlineType = 0, @DeadlinePrecision = 0,
        @DataQualityScore = 80, @SnapshotJson = @StageSnapshot,
        @ContentHash = @StageContentHash;
    IF NOT EXISTS
       (SELECT 1 FROM @StageResult
        WHERE Succeeded = 0 AND Code = N'source-identity-mismatch'
          AND FundingOpportunityPublicId IS NULL)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_FundingSources)
          <> @StageSourceCountBefore
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_FundingOpportunities)
          <> @StageOpportunityCountBefore
        THROW 53668, N'A mismatched durable source identity mutated editorial state.', 1;

    DELETE FROM @StageResult;
    INSERT INTO @StageResult
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_StageExternal
        @FundingSourceId = @ApiSourceId, @ExpectedProviderCode = N'grants-gov',
        @ExternalId = @StageExternalId, @SourceItemKeyHash = @StageSourceItemKeyHash,
        @SourceUrl = @StageSourceUrl, @CanonicalUrlHash = @StageCanonicalUrlHash,
        @ObservedAtUtc = @NowUtc, @Slug = @StageSlug,
        @Title = N'Phase 7B governed draft', @SponsorName = N'Official smoke sponsor',
        @AmountStatus = 0, @DeadlineType = 0, @DeadlinePrecision = 0,
        @DataQualityScore = 80, @SnapshotJson = @StageSnapshot,
        @ContentHash = @StageContentHash;
    DECLARE @StagedOpportunityPublicId UNIQUEIDENTIFIER =
        (SELECT FundingOpportunityPublicId FROM @StageResult WHERE Succeeded = 1);
    IF @StagedOpportunityPublicId IS NULL
       OR NOT EXISTS
          (SELECT 1 FROM @StageResult
           WHERE Code = N'draft-created' AND PublicationStatus = 0)
       OR NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
           INNER JOIN dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
               ON links.FundingOpportunityId = opportunities.Id
           WHERE opportunities.PublicId = @StagedOpportunityPublicId
             AND opportunities.PublicationStatus = 0
             AND links.FundingSourceId = @ApiSourceId)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
           WHERE PublicId = @StagedOpportunityPublicId AND PublicationStatus = 2)
        THROW 53669, N'Exact durable source identity did not create a draft safely.', 1;

    DECLARE @StagedOpportunityId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_FundingOpportunities
         WHERE PublicId = @StagedOpportunityPublicId);
    DECLARE @CuratedPrimaryFunderId BIGINT;
    SELECT @CuratedPrimaryFunderId = links.FunderId
    FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
    WHERE links.FundingOpportunityId = @StagedOpportunityId
      AND links.Role = 1 AND links.IsActive = 1;
    DECLARE @FunderCountBeforeAddOnly BIGINT =
        (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_Funders);
    UPDATE dbo.FundingPlatform_FundingOpportunities
    SET SponsorName = N'A separately curated primary sponsor'
    WHERE Id = @StagedOpportunityId;
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_EnsurePrimaryFunder
        @FundingOpportunityPublicId = @StagedOpportunityPublicId;
    IF @CuratedPrimaryFunderId IS NULL
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunders
           WHERE FundingOpportunityId = @StagedOpportunityId
             AND FunderId = @CuratedPrimaryFunderId
             AND Role = 1 AND IsActive = 1)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_Funders)
          <> @FunderCountBeforeAddOnly
        THROW 53692, N'The add-only sponsor helper replaced a curated primary funder.', 1;
    UPDATE dbo.FundingPlatform_FundingOpportunities
    SET SponsorName = N'Official smoke sponsor'
    WHERE Id = @StagedOpportunityId;

    DECLARE @CleanDocumentPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @UnsafeDocumentPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @LargeDocumentPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @CleanHash BINARY(32) = HASHBYTES('SHA2_256', N'phase7b-clean-' + @Suffix);
    DECLARE @UnsafeHash BINARY(32) = HASHBYTES('SHA2_256', N'phase7b-unsafe-' + @Suffix);
    DECLARE @LargeHash BINARY(32) = HASHBYTES('SHA2_256', N'phase7b-large-' + @Suffix);
    DECLARE @CleanETag NVARCHAR(100) = N'"clean-' + LEFT(@Suffix, 24) + N'"';
    DECLARE @UnsafeETag NVARCHAR(100) = N'"unsafe-' + LEFT(@Suffix, 24) + N'"';
    DECLARE @LargeETag NVARCHAR(100) = N'"large-' + LEFT(@Suffix, 24) + N'"';

    INSERT INTO dbo.FundingPlatform_SourceDocuments
        (PublicId, FundingSourceId, OriginalFileName, MimeType, ContentLength, ContentHash,
         BlobContainer, BlobObjectName, BlobETag,
         TrustedBlobContainer, TrustedBlobObjectName, TrustedBlobETag,
         StorageStatus, ScanStatus, ScanProvider, ScanAttemptCount, ScanResultCode,
         ScanStartedAtUtc, ScanCompletedAtUtc, ExtractionStatus, UploadedByUserId,
         ContentRetentionDays, AcquisitionPolicyVersion, RetentionUntilUtc,
         CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@CleanDocumentPublicId, @ManualSourceId, N'clean.pdf', N'application/pdf', 1000,
         @CleanHash, N'phase7b-quarantine', N'clean/' + @Suffix + N'.pdf', @CleanETag,
         N'phase7b-trusted', N'clean/' + @Suffix + N'.pdf', @CleanETag,
         2, 1, 0, 1, N'clean', @NowUtc, @NowUtc, 0, @AdminUserId,
         @ManualRetentionDays, @ManualPolicyVersion,
         DATEADD(DAY, @ManualRetentionDays, @NowUtc), @NowUtc, @NowUtc),
        (@UnsafeDocumentPublicId, @ManualSourceId, N'unsafe.pdf', N'application/pdf', 1000,
         @UnsafeHash, N'phase7b-quarantine', N'unsafe/' + @Suffix + N'.pdf', @UnsafeETag,
         NULL, NULL, NULL, 1, 0, 1, 1, NULL, @NowUtc, NULL, 0,
         @AdminUserId, @ManualRetentionDays, @ManualPolicyVersion,
         DATEADD(DAY, @ManualRetentionDays, @NowUtc), @NowUtc, @NowUtc),
        (@LargeDocumentPublicId, @ManualSourceId, N'large.pdf', N'application/pdf', 10485761,
         @LargeHash, N'phase7b-quarantine', N'large/' + @Suffix + N'.pdf', @LargeETag,
         N'phase7b-trusted', N'large/' + @Suffix + N'.pdf', @LargeETag,
         2, 1, 0, 1, N'clean', @NowUtc, @NowUtc, 0, @AdminUserId,
         @ManualRetentionDays, @ManualPolicyVersion,
         DATEADD(DAY, @ManualRetentionDays, @NowUtc), @NowUtc, @NowUtc);

    DECLARE @ParserCode NVARCHAR(100) = N'fundingplatform-pdf-text';
    DECLARE @ParserVersion NVARCHAR(50) = N'1-pdfpig-0.1.15';
    DECLARE @MaximumCharacters INT = 500000, @MaximumPages INT = 250;
    DECLARE @MaximumUtf8Bytes INT = 2097152, @MaximumStackDepth SMALLINT = 64;
    DECLARE @MaximumBytes INT = 10485760;
    DECLARE @SettingsHash BINARY(32) = HASHBYTES(
        'SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
        CONCAT(@ParserCode, N'|', @ParserVersion, N'|',
               CONVERT(VARCHAR(20), @MaximumCharacters), N'|',
               CONVERT(VARCHAR(20), @MaximumPages), N'|',
               CONVERT(VARCHAR(20), @MaximumUtf8Bytes), N'|',
               CONVERT(VARCHAR(20), @MaximumStackDepth), N'|',
               CONVERT(VARCHAR(20), @MaximumBytes))
        COLLATE Latin1_General_100_BIN2_UTF8)));
    DECLARE @StartResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), JobPublicId UNIQUEIDENTIFIER NULL,
        SourceDocumentPublicId UNIQUEIDENTIFIER NULL, ExtractionStatus TINYINT NULL,
        AttemptCount SMALLINT NULL, MaxAttempts SMALLINT NULL,
        JobRowVersion BINARY(8) NULL, DocumentRowVersion BINARY(8) NULL, WasReplay BIT
    );

    DECLARE @LargeRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_SourceDocuments
         WHERE PublicId = @LargeDocumentPublicId);
    INSERT INTO @StartResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentExtraction_AdminStart
        @AdminUserPublicId = @AdminPublicId,
        @SourceDocumentPublicId = @LargeDocumentPublicId,
        @ExpectedRowVersion = @LargeRowVersion,
        @IdempotencyKeyHash = 0x1111111111111111111111111111111111111111111111111111111111111111,
        @RequestHash = 0x1212121212121212121212121212121212121212121212121212121212121212,
        @CorrelationId = N'phase7b-large', @ParserCode = @ParserCode,
        @ParserVersion = @ParserVersion, @ParserSettingsHash = @SettingsHash,
        @MaximumCharacters = @MaximumCharacters, @MaximumPages = @MaximumPages,
        @MaximumUtf8Bytes = @MaximumUtf8Bytes, @MaximumStackDepth = @MaximumStackDepth,
        @MaximumBytes = @MaximumBytes, @NowUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @StartResult
        WHERE Succeeded = 0 AND Code = N'document-too-large-for-extraction')
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentExtractionJobs AS jobs
           INNER JOIN dbo.FundingPlatform_SourceDocuments AS documents
               ON documents.Id = jobs.SourceDocumentId
           WHERE documents.PublicId = @LargeDocumentPublicId)
        THROW 53608, N'An oversized document entered the extraction queue.', 1;

    DELETE FROM @StartResult;
    DECLARE @UnsafeRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_SourceDocuments
         WHERE PublicId = @UnsafeDocumentPublicId);
    INSERT INTO @StartResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentExtraction_AdminStart
        @AdminUserPublicId = @AdminPublicId,
        @SourceDocumentPublicId = @UnsafeDocumentPublicId,
        @ExpectedRowVersion = @UnsafeRowVersion,
        @IdempotencyKeyHash = 0x1313131313131313131313131313131313131313131313131313131313131313,
        @RequestHash = 0x1414141414141414141414141414141414141414141414141414141414141414,
        @CorrelationId = N'phase7b-unsafe', @ParserCode = @ParserCode,
        @ParserVersion = @ParserVersion, @ParserSettingsHash = @SettingsHash,
        @MaximumCharacters = @MaximumCharacters, @MaximumPages = @MaximumPages,
        @MaximumUtf8Bytes = @MaximumUtf8Bytes, @MaximumStackDepth = @MaximumStackDepth,
        @MaximumBytes = @MaximumBytes, @NowUtc = @NowUtc;
    IF NOT EXISTS (SELECT 1 FROM @StartResult WHERE Succeeded = 0 AND Code = N'unsafe-document')
        THROW 53609, N'An untrusted document entered the extraction queue.', 1;

    DECLARE @PageLimitError INT;
    DECLARE @PageLimitRetentionUntilUtc DATETIME2(3) =
        DATEADD(DAY, @ManualRetentionDays, @NowUtc);
    SET XACT_ABORT OFF;
    BEGIN TRY
        INSERT INTO dbo.FundingPlatform_SourceDocumentExtractionJobs
            (SourceDocumentId, FundingSourceId, Status, ParserCode, ParserVersion,
             ParserSettingsHash, MaximumCharacters, MaximumPages, MaximumUtf8Bytes,
             MaximumStackDepth, MaximumBytes, ContentRetentionDays,
             AcquisitionPolicyVersion, RetentionUntilUtc, ExpectedTrustedBlobETag,
             ExpectedContentHash, ExpectedContentLength, AttemptCount, MaxAttempts,
             RetryBaseDelaySeconds, NextAttemptAtUtc, RequestedByUserId,
             IdempotencyKeyHash, RequestHash, CorrelationId, CreatedAtUtc, UpdatedAtUtc)
        VALUES
            ((SELECT Id FROM dbo.FundingPlatform_SourceDocuments
              WHERE PublicId = @CleanDocumentPublicId),
             @ManualSourceId, 1, @ParserCode, N'invalid-page-limit',
             0x1717171717171717171717171717171717171717171717171717171717171717,
             @MaximumCharacters, 251, @MaximumUtf8Bytes, @MaximumStackDepth,
             @MaximumBytes, @ManualRetentionDays, @ManualPolicyVersion,
             @PageLimitRetentionUntilUtc, @CleanETag, @CleanHash, 1000, 0, 3, 30,
             @NowUtc, @AdminUserId,
             0x1515151515151515151515151515151515151515151515151515151515151515,
             0x1616161616161616161616161616161616161616161616161616161616161616,
             N'phase7b-page-limit', @NowUtc, @NowUtc);
    END TRY
    BEGIN CATCH
        SET @PageLimitError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;
    IF ISNULL(@PageLimitError, 0) <> 547
        THROW 53610, N'The extraction page cap is not enforced.', 1;

    DELETE FROM @StartResult;
    DECLARE @CleanRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_SourceDocuments
         WHERE PublicId = @CleanDocumentPublicId);
    DECLARE @StartIdempotencyHash BINARY(32) =
        HASHBYTES('SHA2_256', N'extraction-idempotency-' + @Suffix);
    DECLARE @StartRequestHash BINARY(32) =
        HASHBYTES('SHA2_256', N'extraction-request-' + @Suffix);
    INSERT INTO @StartResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentExtraction_AdminStart
        @AdminUserPublicId = @AdminPublicId,
        @SourceDocumentPublicId = @CleanDocumentPublicId,
        @ExpectedRowVersion = @CleanRowVersion,
        @IdempotencyKeyHash = @StartIdempotencyHash,
        @RequestHash = @StartRequestHash,
        @CorrelationId = N'phase7b-extract', @ParserCode = @ParserCode,
        @ParserVersion = @ParserVersion, @ParserSettingsHash = @SettingsHash,
        @MaximumCharacters = @MaximumCharacters, @MaximumPages = @MaximumPages,
        @MaximumUtf8Bytes = @MaximumUtf8Bytes, @MaximumStackDepth = @MaximumStackDepth,
        @MaximumBytes = @MaximumBytes, @NowUtc = @NowUtc;
    DECLARE @JobPublicId UNIQUEIDENTIFIER =
        (SELECT JobPublicId FROM @StartResult WHERE Succeeded = 1);
    DECLARE @QueuedDocumentRowVersion BINARY(8) =
        (SELECT DocumentRowVersion FROM @StartResult WHERE Succeeded = 1);
    IF @JobPublicId IS NULL OR @QueuedDocumentRowVersion IS NULL
       OR NOT EXISTS
          (SELECT 1 FROM @StartResult
           WHERE Code = N'queued' AND ExtractionStatus = 1
             AND AttemptCount = 0 AND MaxAttempts BETWEEN 1 AND 10 AND WasReplay = 0)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
           WHERE MessageType = N'SourceDocumentExtractionRequested'
             AND AggregateId = CONVERT(NVARCHAR(100), @JobPublicId)
             AND JSON_VALUE(PayloadJson, N'$.jobId') = CONVERT(NVARCHAR(36), @JobPublicId)
             AND TRY_CONVERT(INT, JSON_VALUE(PayloadJson, N'$.version')) = 1
             AND PayloadJson NOT LIKE N'%container%'
             AND PayloadJson NOT LIKE N'%etag%'
             AND PayloadJson NOT LIKE N'%hash%')
        THROW 53611, N'A trusted extraction job or its identifiers-only outbox was not created.', 1;

    DELETE FROM @StartResult;
    INSERT INTO @StartResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentExtraction_AdminStart
        @AdminUserPublicId = @AdminPublicId,
        @SourceDocumentPublicId = @CleanDocumentPublicId,
        @ExpectedRowVersion = @CleanRowVersion,
        @IdempotencyKeyHash = @StartIdempotencyHash,
        @RequestHash = @StartRequestHash,
        @CorrelationId = N'phase7b-extract', @ParserCode = @ParserCode,
        @ParserVersion = @ParserVersion, @ParserSettingsHash = @SettingsHash,
        @MaximumCharacters = @MaximumCharacters, @MaximumPages = @MaximumPages,
        @MaximumUtf8Bytes = @MaximumUtf8Bytes, @MaximumStackDepth = @MaximumStackDepth,
        @MaximumBytes = @MaximumBytes, @NowUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @StartResult
        WHERE Succeeded = 1 AND Code = N'replayed' AND JobPublicId = @JobPublicId
          AND DocumentRowVersion = @QueuedDocumentRowVersion AND WasReplay = 1)
        THROW 53612, N'Extraction start replay is not stable.', 1;

    DECLARE @ChangedMaximumBytes INT = @MaximumBytes - 1;
    DECLARE @ChangedSettingsHash BINARY(32) = HASHBYTES(
        'SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
        CONCAT(@ParserCode, N'|', @ParserVersion, N'|',
               CONVERT(VARCHAR(20), @MaximumCharacters), N'|',
               CONVERT(VARCHAR(20), @MaximumPages), N'|',
               CONVERT(VARCHAR(20), @MaximumUtf8Bytes), N'|',
               CONVERT(VARCHAR(20), @MaximumStackDepth), N'|',
               CONVERT(VARCHAR(20), @ChangedMaximumBytes))
        COLLATE Latin1_General_100_BIN2_UTF8)));
    DELETE FROM @StartResult;
    INSERT INTO @StartResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentExtraction_AdminStart
        @AdminUserPublicId = @AdminPublicId,
        @SourceDocumentPublicId = @CleanDocumentPublicId,
        @ExpectedRowVersion = @QueuedDocumentRowVersion,
        @IdempotencyKeyHash = @StartIdempotencyHash,
        @RequestHash = 0x1818181818181818181818181818181818181818181818181818181818181818,
        @CorrelationId = N'phase7b-extract-changed', @ParserCode = @ParserCode,
        @ParserVersion = @ParserVersion, @ParserSettingsHash = @ChangedSettingsHash,
        @MaximumCharacters = @MaximumCharacters, @MaximumPages = @MaximumPages,
        @MaximumUtf8Bytes = @MaximumUtf8Bytes, @MaximumStackDepth = @MaximumStackDepth,
        @MaximumBytes = @ChangedMaximumBytes, @NowUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @StartResult
        WHERE Succeeded = 0 AND Code = N'idempotency-conflict' AND JobPublicId IS NULL)
        THROW 53613, N'A changed extraction policy replay was accepted.', 1;

    DECLARE @ClaimResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), JobPublicId UNIQUEIDENTIFIER NULL,
        SourceDocumentPublicId UNIQUEIDENTIFIER NULL, FundingSourceId INT NULL,
        TrustedBlobContainer NVARCHAR(63) NULL, TrustedBlobObjectName NVARCHAR(1024) NULL,
        TrustedBlobETag NVARCHAR(100) NULL, ContentHash BINARY(32) NULL,
        ContentLength BIGINT NULL, MimeType NVARCHAR(100) NULL,
        ParserCode NVARCHAR(100) NULL, ParserVersion NVARCHAR(50) NULL,
        ParserSettingsHash BINARY(32) NULL, MaximumCharacters INT NULL,
        MaximumPages INT NULL, MaximumUtf8Bytes INT NULL,
        MaximumStackDepth SMALLINT NULL, MaximumBytes INT NULL,
        ContentRetentionDays SMALLINT NULL, AcquisitionPolicyVersion INT NULL,
        RetentionUntilUtc DATETIME2(3) NULL,
        AttemptCount SMALLINT NULL, MaxAttempts SMALLINT NULL,
        LeaseUntilUtc DATETIME2(3) NULL, WasReplay BIT
    );
    DECLARE @LeaseId UNIQUEIDENTIFIER = NEWID();
    INSERT INTO @ClaimResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentExtraction_Claim
        @JobPublicId = @JobPublicId, @LeaseId = @LeaseId,
        @LeaseSeconds = 120, @NowUtc = @NowPlusOneSecond;
    IF NOT EXISTS
       (SELECT 1 FROM @ClaimResult
        WHERE Succeeded = 1 AND Code = N'claimed' AND AttemptCount = 1
          AND MaxAttempts BETWEEN 1 AND 10 AND ParserSettingsHash = @SettingsHash
          AND MaximumBytes = @MaximumBytes AND MaximumPages = 250
          AND TrustedBlobETag = @CleanETag AND ContentHash = @CleanHash)
        THROW 53614, N'A safe extraction job could not be claimed with its frozen policy.', 1;

    DECLARE @ExpiredClaimLeaseId UNIQUEIDENTIFIER = NEWID();
    DELETE FROM @ClaimResult;
    INSERT INTO @ClaimResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentExtraction_Claim
        @JobPublicId = @JobPublicId, @LeaseId = @LeaseId,
        @LeaseSeconds = 120, @NowUtc = @NowPlusTwoSeconds;
    IF NOT EXISTS (SELECT 1 FROM @ClaimResult WHERE Succeeded = 1 AND Code = N'replayed' AND WasReplay = 1)
        THROW 53615, N'Extraction claim replay failed.', 1;

    DECLARE @ConcurrentLeaseId UNIQUEIDENTIFIER = NEWID();
    DELETE FROM @ClaimResult;
    INSERT INTO @ClaimResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentExtraction_Claim
        @JobPublicId = @JobPublicId, @LeaseId = @ConcurrentLeaseId,
        @LeaseSeconds = 120, @NowUtc = @NowPlusTwoSeconds;
    IF NOT EXISTS (SELECT 1 FROM @ClaimResult WHERE Succeeded = 0 AND Code = N'lease-active')
        THROW 53616, N'A concurrent extraction lease was accepted.', 1;

    DECLARE @RenewResult TABLE
        (Succeeded BIT, Code NVARCHAR(50), LeaseUntilUtc DATETIME2(3) NULL);
    INSERT INTO @RenewResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentExtraction_RenewLease
        @JobPublicId = @JobPublicId, @LeaseId = @LeaseId,
        @LeaseSeconds = 180, @NowUtc = @NowPlusThreeSeconds;
    IF NOT EXISTS (SELECT 1 FROM @RenewResult WHERE Succeeded = 1 AND Code = N'renewed')
        THROW 53617, N'An active extraction lease could not be renewed.', 1;

    DECLARE @Excerpt NVARCHAR(2000) = N'Grant closes soon.';
    DECLARE @ExcerptHash BINARY(32) = HASHBYTES(
        'SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
        @Excerpt COLLATE Latin1_General_100_BIN2_UTF8)));
    DECLARE @EvidenceResult TABLE
        (Succeeded BIT, Code NVARCHAR(50), EvidencePublicId UNIQUEIDENTIFIER NULL, WasReplay BIT);
    INSERT INTO @EvidenceResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentExtraction_RecordEvidence
        @JobPublicId = @JobPublicId, @LeaseId = @LeaseId, @Ordinal = 1,
        @PageNumber = 1, @StartOffset = 0, @CharacterLength = 5,
        @Excerpt = @Excerpt, @EvidenceHash = @ExcerptHash,
        @NowUtc = @NowPlusFourSeconds;
    IF NOT EXISTS (SELECT 1 FROM @EvidenceResult WHERE Succeeded = 1 AND Code = N'recorded')
        THROW 53618, N'Bounded extraction evidence was not recorded.', 1;
    DELETE FROM @EvidenceResult;
    INSERT INTO @EvidenceResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentExtraction_RecordEvidence
        @JobPublicId = @JobPublicId, @LeaseId = @LeaseId, @Ordinal = 1,
        @PageNumber = 1, @StartOffset = 0, @CharacterLength = 5,
        @Excerpt = @Excerpt, @EvidenceHash = @ExcerptHash,
        @NowUtc = @NowPlusFiveSeconds;
    IF NOT EXISTS (SELECT 1 FROM @EvidenceResult WHERE Succeeded = 1 AND Code = N'replayed' AND WasReplay = 1)
        THROW 53619, N'Extraction evidence replay failed.', 1;

    DECLARE @FailResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), ExtractionStatus TINYINT NULL,
        NextAttemptAtUtc DATETIME2(3) NULL, JobRowVersion BINARY(8) NULL,
        DocumentRowVersion BINARY(8) NULL, WasReplay BIT
    );
    INSERT INTO @FailResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentExtraction_Fail
        @JobPublicId = @JobPublicId, @LeaseId = @LeaseId,
        @ErrorCode = N'parser-transient',
        @SanitizedMessage = N'Transient parser failure without document content.',
        @IsRetryable = 1, @FailedAtUtc = @NowPlusSixSeconds;
    DECLARE @NextAttemptAtUtc DATETIME2(3) =
        (SELECT NextAttemptAtUtc FROM @FailResult WHERE Succeeded = 1);
    IF @NextAttemptAtUtc IS NULL
       OR NOT EXISTS (SELECT 1 FROM @FailResult WHERE Code = N'retry-scheduled' AND ExtractionStatus = 1)
        THROW 53620, N'A retryable extraction failure was not durably scheduled.', 1;

    DECLARE @SecondLeaseId UNIQUEIDENTIFIER = NEWID();
    DECLARE @RetryClaimAtUtc DATETIME2(3) = DATEADD(SECOND, 1, @NextAttemptAtUtc);
    DECLARE @CompleteAtUtc DATETIME2(3) = DATEADD(SECOND, 2, @NextAttemptAtUtc);
    DECLARE @CompleteReplayAtUtc DATETIME2(3) = DATEADD(MINUTE, 2, @NextAttemptAtUtc);
    DELETE FROM @ClaimResult;
    INSERT INTO @ClaimResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentExtraction_Claim
        @JobPublicId = @JobPublicId, @LeaseId = @SecondLeaseId,
        @LeaseSeconds = 180, @NowUtc = @RetryClaimAtUtc;
    IF NOT EXISTS (SELECT 1 FROM @ClaimResult WHERE Succeeded = 1 AND Code = N'claimed' AND AttemptCount = 2)
        THROW 53621, N'A due extraction retry could not be reclaimed.', 1;

    DECLARE @ExtractedText NVARCHAR(MAX) = N'Grant closes soon.';
    DECLARE @ExtractedTextHash BINARY(32) = HASHBYTES(
        'SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
        @ExtractedText COLLATE Latin1_General_100_BIN2_UTF8)));
    DECLARE @CompleteResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), ResultPublicId UNIQUEIDENTIFIER NULL,
        ExtractionStatus TINYINT NULL, JobRowVersion BINARY(8) NULL,
        DocumentRowVersion BINARY(8) NULL, WasReplay BIT
    );
    INSERT INTO @CompleteResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentExtraction_Complete
        @JobPublicId = @JobPublicId, @LeaseId = @SecondLeaseId,
        @ExtractedText = @ExtractedText, @ExtractedTextHash = @ExtractedTextHash,
        @PageCount = 1, @CharacterCount = 18, @CompletedWithErrors = 0,
        @CompletedAtUtc = @CompleteAtUtc;
    DECLARE @ResultPublicId UNIQUEIDENTIFIER =
        (SELECT ResultPublicId FROM @CompleteResult WHERE Succeeded = 1);
    IF @ResultPublicId IS NULL
       OR NOT EXISTS (SELECT 1 FROM @CompleteResult WHERE Code = N'completed' AND ExtractionStatus = 3)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentExtractionResults
           WHERE PublicId = @ResultPublicId AND ParserSettingsHash = @SettingsHash
             AND MaximumBytes = @MaximumBytes AND MaximumPages = 250
             AND ExtractedTextHash = @ExtractedTextHash)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentExtractionEvidence AS evidence
           INNER JOIN dbo.FundingPlatform_SourceDocumentExtractionResults AS results
               ON results.Id = evidence.ExtractionResultId
           WHERE results.PublicId = @ResultPublicId AND evidence.Ordinal = 1)
        THROW 53622, N'Extraction completion did not preserve its result and evidence.', 1;

    DELETE FROM @CompleteResult;
    INSERT INTO @CompleteResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentExtraction_Complete
        @JobPublicId = @JobPublicId, @LeaseId = @SecondLeaseId,
        @ExtractedText = @ExtractedText, @ExtractedTextHash = @ExtractedTextHash,
        @PageCount = 1, @CharacterCount = 18, @CompletedWithErrors = 0,
        @CompletedAtUtc = @CompleteReplayAtUtc;
    IF NOT EXISTS (SELECT 1 FROM @CompleteResult WHERE Succeeded = 1 AND Code = N'replayed' AND WasReplay = 1)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
           WHERE AggregateId = CONVERT(NVARCHAR(100), @JobPublicId)
             AND MessageType = N'SourceDocumentExtractionCompleted')
        THROW 53623, N'Extraction completion replay or terminal outbox behavior is invalid.', 1;

    /* Trust policy is operable only through an audited SuperAdmin boundary. */
    DECLARE @TenantId UNIQUEIDENTIFIER = NEWID();
    DECLARE @PrincipalId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ApplicationId UNIQUEIDENTIFIER = NEWID();
    DECLARE @SubscriptionId UNIQUEIDENTIFIER = NEWID();
    DECLARE @TopicResourceId NVARCHAR(500) =
        N'/subscriptions/' + CONVERT(NVARCHAR(36), @SubscriptionId)
        + N'/resourcegroups/algat3/providers/microsoft.eventgrid/topics/phase7b-smoke';
    DECLARE @StorageResourceId NVARCHAR(500) =
        N'/subscriptions/' + CONVERT(NVARCHAR(36), @SubscriptionId)
        + N'/resourcegroups/algat3/providers/microsoft.storage/storageaccounts/fpongdev1234';
    DECLARE @StorageHost NVARCHAR(253) = N'fpongdev1234.blob.core.windows.net';
    DECLARE @DefenderContainer NVARCHAR(63) = N'phase7b-defender';
    DECLARE @TrustIdempotency BINARY(32) = HASHBYTES('SHA2_256', N'trust-idem-' + @Suffix);
    DECLARE @TrustRequest BINARY(32) = HASHBYTES('SHA2_256', N'trust-request-' + @Suffix);
    DECLARE @TrustResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), PolicyPublicId UNIQUEIDENTIFIER NULL,
        IsEnabled BIT NULL, RowVersion BINARY(8) NULL, WasReplay BIT
    );
    INSERT INTO @TrustResult
    EXEC dbo.FundingPlatform_usp_EventIngressTrustPolicy_Upsert
        @SuperAdminUserPublicId = @AdminPublicId,
        @PolicyPublicId = NULL, @ExpectedRowVersion = NULL,
        @TenantId = @TenantId, @PrincipalObjectId = @PrincipalId,
        @ApplicationClientId = @ApplicationId,
        @ExpectedTopicResourceId = @TopicResourceId,
        @EventSubscriptionName = N'phase7b-defender-subscription',
        @StorageAccountResourceId = @StorageResourceId,
        @StorageAccountHost = @StorageHost,
        @QuarantineBlobContainer = @DefenderContainer,
        @IsEnabled = 1, @ValidFromUtc = @NowMinusOneMinute,
        @ExpiresAtUtc = NULL, @Reason = N'Phase 7B transactional smoke policy.',
        @IdempotencyKeyHash = @TrustIdempotency,
        @RequestHash = @TrustRequest, @CorrelationId = N'phase7b-trust',
        @NowUtc = @NowUtc;
    DECLARE @PolicyPublicId UNIQUEIDENTIFIER =
        (SELECT PolicyPublicId FROM @TrustResult WHERE Succeeded = 1);
    IF @PolicyPublicId IS NULL
       OR NOT EXISTS (SELECT 1 FROM @TrustResult WHERE Code = N'created' AND IsEnabled = 1)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_EventIngressTrustPolicyEvents AS events
           INNER JOIN dbo.FundingPlatform_EventIngressTrustPolicies AS policies
               ON policies.Id = events.TrustPolicyId
           WHERE policies.PublicId = @PolicyPublicId AND events.ActorUserId = @AdminUserId)
        THROW 53624, N'An audited Defender trust policy was not created.', 1;

    DELETE FROM @TrustResult;
    INSERT INTO @TrustResult
    EXEC dbo.FundingPlatform_usp_EventIngressTrustPolicy_Upsert
        @SuperAdminUserPublicId = @AdminPublicId,
        @PolicyPublicId = NULL, @ExpectedRowVersion = NULL,
        @TenantId = @TenantId, @PrincipalObjectId = @PrincipalId,
        @ApplicationClientId = @ApplicationId,
        @ExpectedTopicResourceId = @TopicResourceId,
        @EventSubscriptionName = N'phase7b-defender-subscription',
        @StorageAccountResourceId = @StorageResourceId,
        @StorageAccountHost = @StorageHost,
        @QuarantineBlobContainer = @DefenderContainer,
        @IsEnabled = 1, @ValidFromUtc = @NowMinusOneMinute,
        @ExpiresAtUtc = NULL, @Reason = N'Phase 7B transactional smoke policy.',
        @IdempotencyKeyHash = @TrustIdempotency,
        @RequestHash = @TrustRequest, @CorrelationId = N'phase7b-trust',
        @NowUtc = @NowUtc;
    IF NOT EXISTS (SELECT 1 FROM @TrustResult WHERE Succeeded = 1 AND Code = N'replayed' AND WasReplay = 1)
        THROW 53625, N'Trust policy replay failed.', 1;

    DECLARE @TrustControlError INT;
    DECLARE @ControlTenantId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ControlPrincipalId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ControlApplicationId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ControlTopicResourceId NVARCHAR(500) = @TopicResourceId + CHAR(10);
    SET XACT_ABORT OFF;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_EventIngressTrustPolicy_Upsert
            @SuperAdminUserPublicId = @AdminPublicId,
            @PolicyPublicId = NULL, @ExpectedRowVersion = NULL,
            @TenantId = @ControlTenantId, @PrincipalObjectId = @ControlPrincipalId,
            @ApplicationClientId = @ControlApplicationId,
            @ExpectedTopicResourceId = @ControlTopicResourceId,
            @EventSubscriptionName = N'phase7b-control',
            @StorageAccountResourceId = @StorageResourceId,
            @StorageAccountHost = @StorageHost,
            @QuarantineBlobContainer = @DefenderContainer,
            @IsEnabled = 1, @ValidFromUtc = @NowUtc, @ExpiresAtUtc = NULL,
            @Reason = N'Control character rejection.',
            @IdempotencyKeyHash = 0x1919191919191919191919191919191919191919191919191919191919191919,
            @RequestHash = 0x2020202020202020202020202020202020202020202020202020202020202020,
            @CorrelationId = N'phase7b-control', @NowUtc = @NowUtc;
    END TRY
    BEGIN CATCH
        SET @TrustControlError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;
    IF ISNULL(@TrustControlError, 0) <> 51828
        THROW 53626, N'Trust resource identifiers accept control characters.', 1;

    DECLARE @TrustStorageMismatchError INT;
    DECLARE @MismatchTenantId UNIQUEIDENTIFIER = NEWID();
    DECLARE @MismatchPrincipalId UNIQUEIDENTIFIER = NEWID();
    DECLARE @MismatchApplicationId UNIQUEIDENTIFIER = NEWID();
    SET XACT_ABORT OFF;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_EventIngressTrustPolicy_Upsert
            @SuperAdminUserPublicId = @AdminPublicId,
            @PolicyPublicId = NULL, @ExpectedRowVersion = NULL,
            @TenantId = @MismatchTenantId, @PrincipalObjectId = @MismatchPrincipalId,
            @ApplicationClientId = @MismatchApplicationId,
            @ExpectedTopicResourceId = @TopicResourceId,
            @EventSubscriptionName = N'phase7b-storage-mismatch',
            @StorageAccountResourceId = @StorageResourceId,
            @StorageAccountHost = N'anotheraccount.blob.core.windows.net',
            @QuarantineBlobContainer = @DefenderContainer,
            @IsEnabled = 1, @ValidFromUtc = @NowUtc, @ExpiresAtUtc = NULL,
            @Reason = N'Storage identity mismatch rejection.',
            @IdempotencyKeyHash = 0x2121212121212121212121212121212121212121212121212121212121212121,
            @RequestHash = 0x2222222222222222222222222222222222222222222222222222222222222222,
            @CorrelationId = N'phase7b-storage-mismatch', @NowUtc = @NowUtc;
    END TRY
    BEGIN CATCH
        SET @TrustStorageMismatchError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;
    IF ISNULL(@TrustStorageMismatchError, 0) <> 51828
        THROW 53637, N'Mismatched storage resource and blob host were accepted.', 1;

    DECLARE @DefenderDocumentPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @TimeoutDocumentPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @DefenderHash BINARY(32) = HASHBYTES('SHA2_256', N'defender-' + @Suffix);
    DECLARE @TimeoutHash BINARY(32) = HASHBYTES('SHA2_256', N'timeout-' + @Suffix);
    DECLARE @DefenderETag NVARCHAR(100) = N'"0xABC' + LEFT(@Suffix, 12) + N'"';
    DECLARE @TimeoutETag NVARCHAR(100) = N'"0xTIME' + LEFT(@Suffix, 12) + N'"';
    DECLARE @DefenderObject NVARCHAR(1024) = N'defender/' + @Suffix + N'.pdf';
    DECLARE @TimeoutObject NVARCHAR(1024) = N'timeout/' + @Suffix + N'.pdf';
    INSERT INTO dbo.FundingPlatform_SourceDocuments
        (PublicId, FundingSourceId, OriginalFileName, MimeType, ContentLength, ContentHash,
         BlobContainer, BlobObjectName, BlobETag, StorageStatus, ScanStatus, ScanProvider,
         ScanAttemptCount, ScanResultCode, ScanStartedAtUtc, ScanCompletedAtUtc,
         ExtractionStatus, UploadedByUserId,
         ContentRetentionDays, AcquisitionPolicyVersion, RetentionUntilUtc,
         CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@DefenderDocumentPublicId, @ManualSourceId, N'defender.pdf', N'application/pdf',
         2048, @DefenderHash, @DefenderContainer, @DefenderObject, @DefenderETag,
         1, 0, 1, 1, NULL, @NowUtc, NULL, 0, @AdminUserId,
         @ManualRetentionDays, @ManualPolicyVersion,
         DATEADD(DAY, @ManualRetentionDays, @NowUtc), @NowUtc, @NowUtc),
        (@TimeoutDocumentPublicId, @ManualSourceId, N'timeout.pdf', N'application/pdf',
         2048, @TimeoutHash, @DefenderContainer, @TimeoutObject, @TimeoutETag,
         1, 0, 1, 1, NULL, DATEADD(MINUTE, -5, @NowUtc), NULL, 0,
         @AdminUserId, @ManualRetentionDays, @ManualPolicyVersion,
         DATEADD(DAY, @ManualRetentionDays, DATEADD(MINUTE, -5, @NowUtc)),
         DATEADD(MINUTE, -5, @NowUtc), DATEADD(MINUTE, -5, @NowUtc));

    DECLARE @ProviderEventId NVARCHAR(200) = N'defender-event-' + @Suffix;
    DECLARE @PayloadHash BINARY(32) = HASHBYTES('SHA2_256', N'defender-payload-' + @Suffix);
    DECLARE @ReceiptResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), ReceiptPublicId UNIQUEIDENTIFIER NULL,
        SourceDocumentPublicId UNIQUEIDENTIFIER NULL, ScanProvider TINYINT,
        QuarantineBlobContainer NVARCHAR(63) NULL,
        QuarantineBlobObjectName NVARCHAR(1024) NULL,
        QuarantineBlobETag NVARCHAR(100) NULL, ContentHash BINARY(32) NULL,
        ContentLength BIGINT NULL, MimeType NVARCHAR(100) NULL, WasReplay BIT
    );
    INSERT INTO @ReceiptResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Record
        @ProviderEventId = @ProviderEventId, @PayloadHash = @PayloadHash,
        @AuthenticatedTenantId = @TenantId, @AuthenticatedPrincipalId = @PrincipalId,
        @ApplicationClientId = @ApplicationId, @TopicResourceId = @TopicResourceId,
        @EventSubscriptionName = N'phase7b-defender-subscription',
        @StorageAccountResourceId = @StorageResourceId, @BlobHost = @StorageHost,
        @BlobContainer = @DefenderContainer, @BlobObjectName = @DefenderObject,
        @BlobETag = @DefenderETag, @ReportedContentHash = @DefenderHash,
        @ToStatus = 1, @ResultCode = N'clean',
        @OccurredAtUtc = @NowUtc, @ReceivedAtUtc = @NowUtc;
    DECLARE @ReceiptPublicId UNIQUEIDENTIFIER =
        (SELECT ReceiptPublicId FROM @ReceiptResult WHERE Succeeded = 1);
    IF @ReceiptPublicId IS NULL
       OR NOT EXISTS
          (SELECT 1 FROM @ReceiptResult
           WHERE Code = N'accepted' AND SourceDocumentPublicId = @DefenderDocumentPublicId
             AND QuarantineBlobETag = @DefenderETag AND ContentHash = @DefenderHash)
        THROW 53627, N'An authenticated exact Defender event was not accepted.', 1;

    DECLARE @ApplyScanResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), SourceDocumentPublicId UNIQUEIDENTIFIER,
        StorageStatus TINYINT NULL, ScanStatus TINYINT NULL, ScanProvider TINYINT NULL,
        RowVersion BINARY(8) NULL, WasReplay BIT,
        RevokedTrustedBlobContainer NVARCHAR(63) NULL,
        RevokedTrustedBlobObjectName NVARCHAR(1024) NULL,
        RevokedTrustedBlobETag NVARCHAR(100) NULL
    );
    INSERT INTO @ApplyScanResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_ApplyScanResult
        @SourceDocumentPublicId = @DefenderDocumentPublicId, @ScanProvider = 1,
        @ProviderEventId = @ProviderEventId, @PayloadHash = @PayloadHash,
        @BlobETag = @DefenderETag, @ReportedContentHash = @DefenderHash,
        @ToStatus = 1, @ResultCode = N'clean',
        @TrustedBlobContainer = N'phase7b-defender-trusted',
        @TrustedBlobObjectName = @DefenderObject,
        @TrustedBlobETag = @DefenderETag, @OccurredAtUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyScanResult
        WHERE Succeeded = 1 AND Code = N'scan-result-applied'
          AND StorageStatus = 2 AND ScanStatus = 1)
        THROW 53628, N'The accepted Defender result was not safely applied.', 1;

    DECLARE @FinalizeResult TABLE
        (Succeeded BIT, Code NVARCHAR(50), ReceiptStatus TINYINT NULL, WasReplay BIT);
    INSERT INTO @FinalizeResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Finalize
        @ReceiptPublicId = @ReceiptPublicId, @PayloadHash = @PayloadHash,
        @Applied = 1, @OutcomeCode = N'scan-result-applied', @FinalizedAtUtc = @NowUtc;
    IF NOT EXISTS (SELECT 1 FROM @FinalizeResult WHERE Succeeded = 1 AND Code = N'applied')
        THROW 53629, N'Defender receipt finalization failed.', 1;
    DELETE FROM @FinalizeResult;
    INSERT INTO @FinalizeResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Finalize
        @ReceiptPublicId = @ReceiptPublicId, @PayloadHash = @PayloadHash,
        @Applied = 1, @OutcomeCode = N'scan-result-applied',
        @FinalizedAtUtc = @NowPlusOneSecond;
    IF NOT EXISTS (SELECT 1 FROM @FinalizeResult WHERE Succeeded = 1 AND Code = N'replayed' AND WasReplay = 1)
        THROW 53630, N'Defender receipt finalization replay failed.', 1;
    DELETE FROM @ReceiptResult;
    INSERT INTO @ReceiptResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Record
        @ProviderEventId = @ProviderEventId, @PayloadHash = @PayloadHash,
        @AuthenticatedTenantId = @TenantId, @AuthenticatedPrincipalId = @PrincipalId,
        @ApplicationClientId = @ApplicationId, @TopicResourceId = @TopicResourceId,
        @EventSubscriptionName = N'phase7b-defender-subscription',
        @StorageAccountResourceId = @StorageResourceId, @BlobHost = @StorageHost,
        @BlobContainer = @DefenderContainer, @BlobObjectName = @DefenderObject,
        @BlobETag = @DefenderETag, @ReportedContentHash = @DefenderHash,
        @ToStatus = 1, @ResultCode = N'clean',
        @OccurredAtUtc = @NowUtc, @ReceivedAtUtc = @NowUtc;
    IF NOT EXISTS (SELECT 1 FROM @ReceiptResult WHERE Succeeded = 1 AND Code = N'replayed-applied' AND WasReplay = 1)
        THROW 53631, N'Applied Defender event replay is not terminal.', 1;

    DECLARE @UnknownEventId NVARCHAR(200) = N'defender-unknown-' + @Suffix;
    DECLARE @MissingBlobObjectName NVARCHAR(1024) = N'missing/' + @Suffix + N'.pdf';
    DECLARE @UnknownPayload BINARY(32) = HASHBYTES('SHA2_256', N'unknown-' + @Suffix);
    DELETE FROM @ReceiptResult;
    INSERT INTO @ReceiptResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Record
        @ProviderEventId = @UnknownEventId, @PayloadHash = @UnknownPayload,
        @AuthenticatedTenantId = @TenantId, @AuthenticatedPrincipalId = @PrincipalId,
        @ApplicationClientId = @ApplicationId, @TopicResourceId = @TopicResourceId,
        @EventSubscriptionName = N'phase7b-defender-subscription',
        @StorageAccountResourceId = @StorageResourceId, @BlobHost = @StorageHost,
        @BlobContainer = @DefenderContainer,
        @BlobObjectName = @MissingBlobObjectName,
        @BlobETag = N'"missing"', @ReportedContentHash = @UnknownPayload,
        @ToStatus = 1, @ResultCode = N'clean',
        @OccurredAtUtc = @NowUtc, @ReceivedAtUtc = @NowUtc;
    IF NOT EXISTS (SELECT 1 FROM @ReceiptResult WHERE Succeeded = 0 AND Code = N'document-not-found')
        THROW 53632, N'An unknown Defender blob was not rejected durably.', 1;
    DELETE FROM @ReceiptResult;
    INSERT INTO @ReceiptResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Record
        @ProviderEventId = @UnknownEventId, @PayloadHash = @UnknownPayload,
        @AuthenticatedTenantId = @TenantId, @AuthenticatedPrincipalId = @PrincipalId,
        @ApplicationClientId = @ApplicationId, @TopicResourceId = @TopicResourceId,
        @EventSubscriptionName = N'phase7b-defender-subscription',
        @StorageAccountResourceId = @StorageResourceId, @BlobHost = @StorageHost,
        @BlobContainer = @DefenderContainer,
        @BlobObjectName = @MissingBlobObjectName,
        @BlobETag = N'"missing"', @ReportedContentHash = @UnknownPayload,
        @ToStatus = 1, @ResultCode = N'clean',
        @OccurredAtUtc = @NowUtc, @ReceivedAtUtc = @NowUtc;
    IF NOT EXISTS (SELECT 1 FROM @ReceiptResult WHERE Succeeded = 0 AND Code = N'replayed-rejected' AND WasReplay = 1)
        THROW 53633, N'Rejected Defender event replay is not terminal.', 1;

    DECLARE @TimeoutResult TABLE
    (
        SourceDocumentPublicId UNIQUEIDENTIFIER, StorageStatus TINYINT,
        ScanStatus TINYINT, ScanProvider TINYINT, ScanAttemptCount SMALLINT,
        RowVersion BINARY(8)
    );
    INSERT INTO @TimeoutResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentScan_WatchdogTimeout
        @BatchSize = 100, @TimeoutSeconds = 600, @NowUtc = @NowUtc;
    IF EXISTS (SELECT 1 FROM @TimeoutResult WHERE SourceDocumentPublicId = @TimeoutDocumentPublicId)
        THROW 53634, N'Defender watchdog timed out a document before its threshold.', 1;
    DELETE FROM @TimeoutResult;
    INSERT INTO @TimeoutResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentScan_WatchdogTimeout
        @BatchSize = 100, @TimeoutSeconds = 600,
        @NowUtc = @NowPlusSixMinutes;
    DECLARE @TimeoutRowVersion BINARY(8) =
        (SELECT RowVersion FROM @TimeoutResult
         WHERE SourceDocumentPublicId = @TimeoutDocumentPublicId);
    IF @TimeoutRowVersion IS NULL
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentScanEvents AS events
           INNER JOIN dbo.FundingPlatform_SourceDocuments AS documents
               ON documents.Id = events.SourceDocumentId
           WHERE documents.PublicId = @TimeoutDocumentPublicId
             AND events.FromStatus = 0 AND events.ToStatus = 4
             AND events.ResultCode = N'defender-timeout')
        THROW 53635, N'Defender watchdog did not create an idempotent timeout audit.', 1;
    DELETE FROM @TimeoutResult;
    INSERT INTO @TimeoutResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentScan_WatchdogTimeout
        @BatchSize = 100, @TimeoutSeconds = 600,
        @NowUtc = @NowPlusSevenMinutes;
    IF EXISTS (SELECT 1 FROM @TimeoutResult WHERE SourceDocumentPublicId = @TimeoutDocumentPublicId)
        THROW 53636, N'Defender watchdog replay was not a no-op.', 1;

    /* Microsoft Defender retry is never reported as queued without a consumer. */
    DECLARE @RetryScanResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), SourceDocumentPublicId UNIQUEIDENTIFIER,
        StorageStatus TINYINT NULL, ScanStatus TINYINT NULL, ScanProvider TINYINT NULL,
        ScanAttemptCount SMALLINT NULL, RowVersion BINARY(8) NULL, WasReplay BIT
    );
    INSERT INTO @RetryScanResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_RetryScan
        @AdminUserPublicId = @AdminPublicId,
        @SourceDocumentPublicId = @TimeoutDocumentPublicId,
        @ExpectedRowVersion = @TimeoutRowVersion,
        @IdempotencyKeyHash = 0x2323232323232323232323232323232323232323232323232323232323232323,
        @RequestHash = 0x2424242424242424242424242424242424242424242424242424242424242424;
    IF NOT EXISTS
       (SELECT 1 FROM @RetryScanResult
        WHERE Succeeded = 0 AND Code = N'defender-rescan-not-configured'
          AND ScanStatus = 4 AND ScanAttemptCount = 1 AND RowVersion = @TimeoutRowVersion)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
           WHERE MessageType = N'SourceDocumentScanRetryRequested'
             AND AggregateId = CONVERT(NVARCHAR(100), @TimeoutDocumentPublicId)
             AND DispatchedAtUtc IS NULL)
        THROW 53638, N'Defender retry reported false delivery or mutated the document.', 1;

    /* Queue an extraction while the Defender document is trusted, then revoke it
       with a later authenticated malicious result for the exact immutable bytes. */
    DELETE FROM @StartResult;
    DECLARE @DefenderTrustedRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_SourceDocuments
         WHERE PublicId = @DefenderDocumentPublicId);
    DECLARE @DefenderJobIdempotency BINARY(32) =
        HASHBYTES('SHA2_256', N'defender-extraction-idem-' + @Suffix);
    DECLARE @DefenderJobRequest BINARY(32) =
        HASHBYTES('SHA2_256', N'defender-extraction-request-' + @Suffix);
    INSERT INTO @StartResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentExtraction_AdminStart
        @AdminUserPublicId = @AdminPublicId,
        @SourceDocumentPublicId = @DefenderDocumentPublicId,
        @ExpectedRowVersion = @DefenderTrustedRowVersion,
        @IdempotencyKeyHash = @DefenderJobIdempotency,
        @RequestHash = @DefenderJobRequest,
        @CorrelationId = N'phase7b-defender-extract', @ParserCode = @ParserCode,
        @ParserVersion = @ParserVersion, @ParserSettingsHash = @SettingsHash,
        @MaximumCharacters = @MaximumCharacters, @MaximumPages = @MaximumPages,
        @MaximumUtf8Bytes = @MaximumUtf8Bytes,
        @MaximumStackDepth = @MaximumStackDepth,
        @MaximumBytes = @MaximumBytes, @NowUtc = @NowUtc;
    DECLARE @DefenderJobPublicId UNIQUEIDENTIFIER =
        (SELECT JobPublicId FROM @StartResult WHERE Succeeded = 1);
    IF @DefenderJobPublicId IS NULL
        THROW 53639, N'The trusted Defender document could not enter extraction.', 1;

    DECLARE @ThreatEventId NVARCHAR(200) = N'defender-threat-' + @Suffix;
    DECLARE @ThreatPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'defender-threat-payload-' + @Suffix);
    DELETE FROM @ReceiptResult;
    INSERT INTO @ReceiptResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Record
        @ProviderEventId = @ThreatEventId, @PayloadHash = @ThreatPayloadHash,
        @AuthenticatedTenantId = @TenantId, @AuthenticatedPrincipalId = @PrincipalId,
        @ApplicationClientId = @ApplicationId, @TopicResourceId = @TopicResourceId,
        @EventSubscriptionName = N'phase7b-defender-subscription',
        @StorageAccountResourceId = @StorageResourceId, @BlobHost = @StorageHost,
        @BlobContainer = @DefenderContainer, @BlobObjectName = @DefenderObject,
        @BlobETag = @DefenderETag, @ReportedContentHash = @DefenderHash,
        @ToStatus = 2, @ResultCode = N'malicious',
        @OccurredAtUtc = @NowPlusThreeSeconds,
        @ReceivedAtUtc = @NowPlusThreeSeconds;
    DECLARE @ThreatReceiptPublicId UNIQUEIDENTIFIER =
        (SELECT ReceiptPublicId FROM @ReceiptResult WHERE Succeeded = 1);
    IF @ThreatReceiptPublicId IS NULL
        THROW 53640, N'A later exact authenticated threat was not accepted.', 1;

    DELETE FROM @ApplyScanResult;
    INSERT INTO @ApplyScanResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_ApplyScanResult
        @SourceDocumentPublicId = @DefenderDocumentPublicId, @ScanProvider = 1,
        @ProviderEventId = @ThreatEventId, @PayloadHash = @ThreatPayloadHash,
        @BlobETag = @DefenderETag, @ReportedContentHash = @DefenderHash,
        @ToStatus = 2, @ResultCode = N'malicious',
        @TrustedBlobContainer = NULL, @TrustedBlobObjectName = NULL,
        @TrustedBlobETag = NULL, @OccurredAtUtc = @NowPlusThreeSeconds;
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyScanResult
        WHERE Succeeded = 1 AND Code = N'scan-result-superseded'
          AND StorageStatus = 1 AND ScanStatus = 2
          AND RevokedTrustedBlobContainer = N'phase7b-defender-trusted'
          AND RevokedTrustedBlobObjectName = @DefenderObject
          AND RevokedTrustedBlobETag = @DefenderETag)
       OR NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_SourceDocuments AS documents
           INNER JOIN dbo.FundingPlatform_SourceDocumentExtractionJobs AS jobs
               ON jobs.SourceDocumentId = documents.Id
           WHERE documents.PublicId = @DefenderDocumentPublicId
             AND documents.TrustedBlobContainer IS NULL
             AND documents.TrustedBlobObjectName IS NULL
             AND documents.TrustedBlobETag IS NULL
             AND documents.ExtractionStatus = 6
             AND jobs.PublicId = @DefenderJobPublicId
             AND jobs.Status = 6 AND jobs.LastErrorCode = N'security-scan-revoked')
        THROW 53641, N'A later threat did not revoke trusted extraction state fail-closed.', 1;

    DELETE FROM @FinalizeResult;
    INSERT INTO @FinalizeResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Finalize
        @ReceiptPublicId = @ThreatReceiptPublicId, @PayloadHash = @ThreatPayloadHash,
        @Applied = 1, @OutcomeCode = N'scan-result-superseded',
        @FinalizedAtUtc = @NowPlusFourSeconds;
    IF NOT EXISTS (SELECT 1 FROM @FinalizeResult WHERE Succeeded = 1 AND Code = N'applied')
        THROW 53642, N'The superseding Defender receipt did not finalize.', 1;

    DELETE FROM @ApplyScanResult;
    INSERT INTO @ApplyScanResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_ApplyScanResult
        @SourceDocumentPublicId = @DefenderDocumentPublicId, @ScanProvider = 1,
        @ProviderEventId = @ThreatEventId, @PayloadHash = @ThreatPayloadHash,
        @BlobETag = @DefenderETag, @ReportedContentHash = @DefenderHash,
        @ToStatus = 2, @ResultCode = N'malicious',
        @TrustedBlobContainer = NULL, @TrustedBlobObjectName = NULL,
        @TrustedBlobETag = NULL, @OccurredAtUtc = @NowPlusThreeSeconds;
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyScanResult
        WHERE Succeeded = 1 AND Code = N'scan-result-superseded' AND WasReplay = 1
          AND RevokedTrustedBlobContainer = N'phase7b-defender-trusted'
          AND RevokedTrustedBlobObjectName = @DefenderObject
          AND RevokedTrustedBlobETag = @DefenderETag)
        THROW 53643, N'Superseding scan replay did not preserve conditional-delete identity.', 1;

    DECLARE @DuplicateThreatEventId NVARCHAR(200) = N'defender-threat-duplicate-' + @Suffix;
    DECLARE @DuplicateThreatPayload BINARY(32) =
        HASHBYTES('SHA2_256', N'defender-threat-duplicate-payload-' + @Suffix);
    DELETE FROM @ReceiptResult;
    INSERT INTO @ReceiptResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Record
        @ProviderEventId = @DuplicateThreatEventId, @PayloadHash = @DuplicateThreatPayload,
        @AuthenticatedTenantId = @TenantId, @AuthenticatedPrincipalId = @PrincipalId,
        @ApplicationClientId = @ApplicationId, @TopicResourceId = @TopicResourceId,
        @EventSubscriptionName = N'phase7b-defender-subscription',
        @StorageAccountResourceId = @StorageResourceId, @BlobHost = @StorageHost,
        @BlobContainer = @DefenderContainer, @BlobObjectName = @DefenderObject,
        @BlobETag = @DefenderETag, @ReportedContentHash = @DefenderHash,
        @ToStatus = 2, @ResultCode = N'malicious',
        @OccurredAtUtc = @NowPlusFiveSeconds,
        @ReceivedAtUtc = @NowPlusFiveSeconds;
    IF NOT EXISTS
       (SELECT 1 FROM @ReceiptResult
        WHERE Succeeded = 0 AND Code = N'duplicate-scan-result' AND WasReplay = 0)
        THROW 53644, N'A duplicate terminal scan was not ignored.', 1;
    DELETE FROM @ReceiptResult;
    INSERT INTO @ReceiptResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Record
        @ProviderEventId = @DuplicateThreatEventId, @PayloadHash = @DuplicateThreatPayload,
        @AuthenticatedTenantId = @TenantId, @AuthenticatedPrincipalId = @PrincipalId,
        @ApplicationClientId = @ApplicationId, @TopicResourceId = @TopicResourceId,
        @EventSubscriptionName = N'phase7b-defender-subscription',
        @StorageAccountResourceId = @StorageResourceId, @BlobHost = @StorageHost,
        @BlobContainer = @DefenderContainer, @BlobObjectName = @DefenderObject,
        @BlobETag = @DefenderETag, @ReportedContentHash = @DefenderHash,
        @ToStatus = 2, @ResultCode = N'malicious',
        @OccurredAtUtc = @NowPlusFiveSeconds,
        @ReceivedAtUtc = @NowPlusFiveSeconds;
    IF NOT EXISTS
       (SELECT 1 FROM @ReceiptResult
        WHERE Succeeded = 0 AND Code = N'replayed-ignored' AND WasReplay = 1)
        THROW 53645, N'Ignored scan replay was not terminal.', 1;

    DECLARE @TerminalConflictEventId NVARCHAR(200) = N'defender-conflict-' + @Suffix;
    DECLARE @TerminalConflictPayload BINARY(32) =
        HASHBYTES('SHA2_256', N'defender-conflict-payload-' + @Suffix);
    DELETE FROM @ReceiptResult;
    INSERT INTO @ReceiptResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Record
        @ProviderEventId = @TerminalConflictEventId, @PayloadHash = @TerminalConflictPayload,
        @AuthenticatedTenantId = @TenantId, @AuthenticatedPrincipalId = @PrincipalId,
        @ApplicationClientId = @ApplicationId, @TopicResourceId = @TopicResourceId,
        @EventSubscriptionName = N'phase7b-defender-subscription',
        @StorageAccountResourceId = @StorageResourceId, @BlobHost = @StorageHost,
        @BlobContainer = @DefenderContainer, @BlobObjectName = @DefenderObject,
        @BlobETag = @DefenderETag, @ReportedContentHash = @DefenderHash,
        @ToStatus = 1, @ResultCode = N'clean',
        @OccurredAtUtc = @NowPlusSixSeconds,
        @ReceivedAtUtc = @NowPlusSixSeconds;
    IF NOT EXISTS
       (SELECT 1 FROM @ReceiptResult
        WHERE Succeeded = 0 AND Code = N'terminal-scan-result-conflict')
        THROW 53646, N'A contradictory terminal Defender result was not rejected.', 1;

    /* A delivery arriving after the timeout is terminal and never retries forever. */
    DECLARE @LateTimeoutEventId NVARCHAR(200) = N'defender-late-timeout-' + @Suffix;
    DECLARE @LateTimeoutPayload BINARY(32) =
        HASHBYTES('SHA2_256', N'defender-late-timeout-payload-' + @Suffix);
    DELETE FROM @ReceiptResult;
    INSERT INTO @ReceiptResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Record
        @ProviderEventId = @LateTimeoutEventId, @PayloadHash = @LateTimeoutPayload,
        @AuthenticatedTenantId = @TenantId, @AuthenticatedPrincipalId = @PrincipalId,
        @ApplicationClientId = @ApplicationId, @TopicResourceId = @TopicResourceId,
        @EventSubscriptionName = N'phase7b-defender-subscription',
        @StorageAccountResourceId = @StorageResourceId, @BlobHost = @StorageHost,
        @BlobContainer = @DefenderContainer, @BlobObjectName = @TimeoutObject,
        @BlobETag = @TimeoutETag, @ReportedContentHash = @TimeoutHash,
        @ToStatus = 1, @ResultCode = N'clean',
        @OccurredAtUtc = @NowPlusFourMinutes,
        @ReceivedAtUtc = @NowPlusFourMinutes;
    IF NOT EXISTS
       (SELECT 1 FROM @ReceiptResult
        WHERE Succeeded = 0 AND Code = N'stale-scan-result')
        THROW 53647, N'A late timeout delivery was left retryable.', 1;

    /* Only an explicit event-ledger allowlist is terminalized. Unknown messages
       remain visible and command workers receive only executable request types. */
    DECLARE @KnownAuditMessageId UNIQUEIDENTIFIER = NEWID();
    DECLARE @HistoricalRetryMessageId UNIQUEIDENTIFIER = NEWID();
    DECLARE @UnknownOutboxMessageId UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.FundingPlatform_OutboxMessages
        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
         OccurredAtUtc, AvailableAtUtc)
    VALUES
        (@KnownAuditMessageId, N'OrganizationCreated', N'Organization', @Suffix,
         N'{"version":1}', DATEADD(DAY, -1, @NowUtc), DATEADD(DAY, -1, @NowUtc)),
        (@HistoricalRetryMessageId, N'SourceDocumentScanRetryRequested',
         N'SourceDocument', @Suffix, N'{"version":1}',
         DATEADD(DAY, -1, @NowUtc), DATEADD(DAY, -1, @NowUtc)),
        (@UnknownOutboxMessageId, N'Phase7BUnknownMessage', N'Unknown', @Suffix,
         N'{"version":1}', DATEADD(DAY, -1, @NowUtc), DATEADD(DAY, -1, @NowUtc));

    DECLARE @AcknowledgedAuditCount INT;
    EXEC dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge
        @BatchSize = 500, @NowUtc = @NowUtc,
        @AcknowledgedCount = @AcknowledgedAuditCount OUTPUT;
    IF @AcknowledgedAuditCount < 2
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
           WHERE MessageId = @KnownAuditMessageId AND DispatchedAtUtc = @NowUtc
             AND LastError = N'event-ledger-acknowledged')
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
           WHERE MessageId = @HistoricalRetryMessageId AND DispatchedAtUtc = @NowUtc
             AND LastError = N'unsupported-command-not-delivered')
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
           WHERE MessageId = @UnknownOutboxMessageId AND DispatchedAtUtc IS NULL
             AND LeaseOwner IS NULL)
        THROW 53648, N'Outbox event terminalization is not explicitly fail-closed.', 1;

    DECLARE @Dispatch TABLE
    (
        Id BIGINT, MessageId UNIQUEIDENTIFIER, MessageType NVARCHAR(100),
        AggregateType NVARCHAR(100), AggregateId NVARCHAR(100), PayloadJson NVARCHAR(MAX),
        OccurredAtUtc DATETIME2(3), AttemptCount SMALLINT, LeaseUntilUtc DATETIME2(3)
    );
    INSERT INTO @Dispatch
    EXEC dbo.FundingPlatform_usp_ImportRunOutbox_Claim
        @LeaseOwner = N'phase7b-smoke', @BatchSize = 100,
        @LeaseSeconds = 60, @NowUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @Dispatch WHERE MessageType = N'SourceDocumentExtractionRequested')
       OR EXISTS
          (SELECT 1 FROM @Dispatch
           WHERE MessageType NOT IN (N'ImportRunRequested', N'SourceDocumentExtractionRequested'))
       OR EXISTS (SELECT 1 FROM @Dispatch WHERE MessageId = @UnknownOutboxMessageId)
        THROW 53649, N'The command dispatcher leaked audit or unknown messages.', 1;

    /* Retention expiry is terminal before parsing, both on direct claim and on
       stranded-lease recovery. */
    DECLARE @RetentionCreatedAtUtc DATETIME2(3) =
        DATEADD(DAY, -CONVERT(INT, @ManualRetentionDays) - 1, @NowUtc);
    DECLARE @RetentionDueAtUtc DATETIME2(3) = DATEADD(DAY, -1, @NowUtc);
    DECLARE @ExpiredClaimDocumentPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ExpiredRequeueDocumentPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @RetentionDocumentPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ExpiredClaimHash BINARY(32) = HASHBYTES('SHA2_256', N'expired-claim-' + @Suffix);
    DECLARE @ExpiredRequeueHash BINARY(32) = HASHBYTES('SHA2_256', N'expired-requeue-' + @Suffix);
    DECLARE @RetentionDocumentHash BINARY(32) = HASHBYTES('SHA2_256', N'retention-document-' + @Suffix);
    DECLARE @ExpiredClaimETag NVARCHAR(100) = N'"expired-claim-' + LEFT(@Suffix, 16) + N'"';
    DECLARE @ExpiredRequeueETag NVARCHAR(100) = N'"expired-requeue-' + LEFT(@Suffix, 16) + N'"';
    DECLARE @RetentionDocumentETag NVARCHAR(100) = N'"retention-' + LEFT(@Suffix, 16) + N'"';

    INSERT INTO dbo.FundingPlatform_SourceDocuments
        (PublicId, FundingSourceId, OriginalFileName, MimeType, ContentLength, ContentHash,
         BlobContainer, BlobObjectName, BlobETag,
         TrustedBlobContainer, TrustedBlobObjectName, TrustedBlobETag,
         StorageStatus, ScanStatus, ScanProvider, ScanAttemptCount, ScanResultCode,
         ScanStartedAtUtc, ScanCompletedAtUtc, ExtractionStatus, UploadedByUserId,
         ContentRetentionDays, AcquisitionPolicyVersion, RetentionUntilUtc,
         ContentRetentionNextAttemptAtUtc,
         CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@ExpiredClaimDocumentPublicId, @ManualSourceId, N'expired-claim.pdf',
         N'application/pdf', 1024, @ExpiredClaimHash, N'phase7b-quarantine',
         N'expired-claim/' + @Suffix + N'.pdf', @ExpiredClaimETag,
         N'phase7b-trusted', N'expired-claim/' + @Suffix + N'.pdf', @ExpiredClaimETag,
         2, 1, 0, 1, N'clean', @RetentionCreatedAtUtc, @RetentionCreatedAtUtc,
         1, @AdminUserId, 1, @ManualPolicyVersion, @RetentionDueAtUtc,
         @RetentionCreatedAtUtc, @RetentionCreatedAtUtc, @RetentionCreatedAtUtc),
        (@ExpiredRequeueDocumentPublicId, @ManualSourceId, N'expired-requeue.pdf',
         N'application/pdf', 1024, @ExpiredRequeueHash, N'phase7b-quarantine',
         N'expired-requeue/' + @Suffix + N'.pdf', @ExpiredRequeueETag,
         N'phase7b-trusted', N'expired-requeue/' + @Suffix + N'.pdf', @ExpiredRequeueETag,
         2, 1, 0, 1, N'clean', @RetentionCreatedAtUtc, @RetentionCreatedAtUtc,
         2, @AdminUserId, 1, @ManualPolicyVersion, @RetentionDueAtUtc,
         @RetentionCreatedAtUtc, @RetentionCreatedAtUtc, DATEADD(HOUR, -2, @NowUtc)),
        (@RetentionDocumentPublicId, @ManualSourceId, N'retention-result.pdf',
         N'application/pdf', 1024, @RetentionDocumentHash, N'phase7b-quarantine',
         N'retention-result/' + @Suffix + N'.pdf', @RetentionDocumentETag,
         N'phase7b-trusted', N'retention-result/' + @Suffix + N'.pdf', @RetentionDocumentETag,
         2, 1, 0, 1, N'clean', @RetentionCreatedAtUtc, @RetentionCreatedAtUtc,
         3, @AdminUserId, 1, @ManualPolicyVersion, @RetentionDueAtUtc,
         @RetentionCreatedAtUtc, @RetentionCreatedAtUtc,
         DATEADD(HOUR, 1, @RetentionCreatedAtUtc));

    DECLARE @ExpiredClaimJobPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ExpiredRequeueJobPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @RetentionJobPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ExpiredRequeueLeaseId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ExpiredClaimSettings BINARY(32) = HASHBYTES('SHA2_256', N'expired-claim-settings-' + @Suffix);
    DECLARE @ExpiredRequeueSettings BINARY(32) = HASHBYTES('SHA2_256', N'expired-requeue-settings-' + @Suffix);
    DECLARE @RetentionSettings BINARY(32) = HASHBYTES('SHA2_256', N'retention-settings-' + @Suffix);
    INSERT INTO dbo.FundingPlatform_SourceDocumentExtractionJobs
        (PublicId, SourceDocumentId, FundingSourceId, Status,
         ParserCode, ParserVersion, ParserSettingsHash,
         MaximumCharacters, MaximumPages, MaximumUtf8Bytes, MaximumStackDepth,
         MaximumBytes, ContentRetentionDays, AcquisitionPolicyVersion, RetentionUntilUtc,
         ExpectedTrustedBlobETag, ExpectedContentHash, ExpectedContentLength,
         AttemptCount, MaxAttempts, RetryBaseDelaySeconds, NextAttemptAtUtc,
         LeaseId, LeaseUntilUtc, LastErrorCode, LastErrorMessage,
         RequestedByUserId, IdempotencyKeyHash, RequestHash, CorrelationId,
         StartedAtUtc, CompletedAtUtc, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@ExpiredClaimJobPublicId,
         (SELECT Id FROM dbo.FundingPlatform_SourceDocuments WHERE PublicId = @ExpiredClaimDocumentPublicId),
         @ManualSourceId, 1, @ParserCode, N'retention-expired-claim', @ExpiredClaimSettings,
         @MaximumCharacters, @MaximumPages, @MaximumUtf8Bytes, @MaximumStackDepth,
         @MaximumBytes, 1, @ManualPolicyVersion, @RetentionDueAtUtc,
         @ExpiredClaimETag, @ExpiredClaimHash, 1024, 0, 3, 30, @RetentionCreatedAtUtc,
         NULL, NULL, NULL, NULL, @AdminUserId,
         HASHBYTES('SHA2_256', N'expired-claim-idem-' + @Suffix),
         HASHBYTES('SHA2_256', N'expired-claim-request-' + @Suffix),
         N'phase7b-retention-claim', NULL, NULL,
         @RetentionCreatedAtUtc, @RetentionCreatedAtUtc),
        (@ExpiredRequeueJobPublicId,
         (SELECT Id FROM dbo.FundingPlatform_SourceDocuments WHERE PublicId = @ExpiredRequeueDocumentPublicId),
         @ManualSourceId, 2, @ParserCode, N'retention-expired-requeue', @ExpiredRequeueSettings,
         @MaximumCharacters, @MaximumPages, @MaximumUtf8Bytes, @MaximumStackDepth,
         @MaximumBytes, 1, @ManualPolicyVersion, @RetentionDueAtUtc,
         @ExpiredRequeueETag, @ExpiredRequeueHash, 1024, 1, 3, 30, @RetentionCreatedAtUtc,
         @ExpiredRequeueLeaseId, DATEADD(HOUR, -1, @NowUtc), NULL, NULL, @AdminUserId,
         HASHBYTES('SHA2_256', N'expired-requeue-idem-' + @Suffix),
         HASHBYTES('SHA2_256', N'expired-requeue-request-' + @Suffix),
         N'phase7b-retention-requeue', @RetentionCreatedAtUtc, NULL,
         @RetentionCreatedAtUtc, DATEADD(HOUR, -2, @NowUtc)),
        (@RetentionJobPublicId,
         (SELECT Id FROM dbo.FundingPlatform_SourceDocuments WHERE PublicId = @RetentionDocumentPublicId),
         @ManualSourceId, 3, @ParserCode, N'retention-result', @RetentionSettings,
         @MaximumCharacters, @MaximumPages, @MaximumUtf8Bytes, @MaximumStackDepth,
         @MaximumBytes, 1, @ManualPolicyVersion, @RetentionDueAtUtc,
         @RetentionDocumentETag, @RetentionDocumentHash, 1024, 1, 3, 30,
         @RetentionCreatedAtUtc, NULL, NULL, NULL, NULL, @AdminUserId,
         HASHBYTES('SHA2_256', N'retention-result-idem-' + @Suffix),
         HASHBYTES('SHA2_256', N'retention-result-request-' + @Suffix),
         N'phase7b-retention-result', @RetentionCreatedAtUtc,
         DATEADD(HOUR, 1, @RetentionCreatedAtUtc), @RetentionCreatedAtUtc,
         DATEADD(HOUR, 1, @RetentionCreatedAtUtc));

    DELETE FROM @ClaimResult;
    INSERT INTO @ClaimResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentExtraction_Claim
        @JobPublicId = @ExpiredClaimJobPublicId, @LeaseId = @ExpiredClaimLeaseId,
        @LeaseSeconds = 60, @NowUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @ClaimResult
        WHERE Succeeded = 0 AND Code = N'retention-expired'
          AND ContentRetentionDays = 1 AND AcquisitionPolicyVersion = @ManualPolicyVersion
          AND RetentionUntilUtc = @RetentionDueAtUtc AND MaxAttempts = 3)
       OR NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_SourceDocumentExtractionJobs AS jobs
           INNER JOIN dbo.FundingPlatform_SourceDocuments AS documents
               ON documents.Id = jobs.SourceDocumentId
           WHERE jobs.PublicId = @ExpiredClaimJobPublicId AND jobs.Status = 6
             AND jobs.LeaseId IS NULL AND jobs.LastErrorCode = N'retention-expired'
             AND documents.ExtractionStatus = 6)
        THROW 53650, N'Expired extraction content was not canceled before parsing.', 1;

    DECLARE @RequeueResult TABLE
        (JobPublicId UNIQUEIDENTIFIER, SourceDocumentPublicId UNIQUEIDENTIFIER, FundingSourceId INT);
    INSERT INTO @RequeueResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentExtraction_RequeueStranded
        @BatchSize = 100, @NowUtc = @NowUtc;
    IF EXISTS (SELECT 1 FROM @RequeueResult WHERE JobPublicId = @ExpiredRequeueJobPublicId)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentExtractionJobs
           WHERE PublicId = @ExpiredRequeueJobPublicId AND Status = 6
             AND LeaseId IS NULL AND LeaseUntilUtc IS NULL
             AND LastErrorCode = N'retention-expired')
        THROW 53655, N'Expired stranded extraction was requeued instead of canceled.', 1;

    /* Build due result/evidence plus a raw observation shared by a due terminal
       item and a later live item. Raw bytes expire on their own snapshot. */
    DECLARE @RetentionJobId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_SourceDocumentExtractionJobs
         WHERE PublicId = @RetentionJobPublicId);
    DECLARE @RetentionDocumentId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_SourceDocuments
         WHERE PublicId = @RetentionDocumentPublicId);
    DECLARE @RetentionResultPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @RetentionResultText NVARCHAR(MAX) = N'Retention payload';
    DECLARE @RetentionResultHash BINARY(32) = HASHBYTES(
        'SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
        @RetentionResultText COLLATE Latin1_General_100_BIN2_UTF8)));
    INSERT INTO dbo.FundingPlatform_SourceDocumentExtractionResults
        (PublicId, ExtractionJobId, SourceDocumentId, FundingSourceId,
         ParserCode, ParserVersion, ParserSettingsHash,
         MaximumCharacters, MaximumPages, MaximumUtf8Bytes, MaximumStackDepth,
         MaximumBytes, ContentRetentionDays, AcquisitionPolicyVersion, RetentionUntilUtc,
         ExtractedText, ExtractedTextHash, PageCount, CharacterCount,
         CompletedWithErrors, CreatedAtUtc)
    VALUES
        (@RetentionResultPublicId, @RetentionJobId, @RetentionDocumentId, @ManualSourceId,
         @ParserCode, N'retention-result', @RetentionSettings,
         @MaximumCharacters, @MaximumPages, @MaximumUtf8Bytes, @MaximumStackDepth,
         @MaximumBytes, 1, @ManualPolicyVersion, @RetentionDueAtUtc,
         @RetentionResultText, @RetentionResultHash, 1, DATALENGTH(@RetentionResultText) / 2,
         0, DATEADD(HOUR, 1, @RetentionCreatedAtUtc));
    DECLARE @RetentionResultId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_SourceDocumentExtractionResults
         WHERE PublicId = @RetentionResultPublicId);
    DECLARE @RetentionEvidencePublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @RetentionEvidenceHash BINARY(32) = HASHBYTES('SHA2_256', N'Retention evidence');
    INSERT INTO dbo.FundingPlatform_SourceDocumentExtractionEvidence
        (PublicId, ExtractionJobId, ExtractionResultId, SourceDocumentId, FundingSourceId,
         Ordinal, PageNumber, StartOffset, CharacterLength, Excerpt, EvidenceHash,
         ContentRetentionDays, AcquisitionPolicyVersion, RetentionUntilUtc, CreatedAtUtc)
    VALUES
        (@RetentionEvidencePublicId, @RetentionJobId, @RetentionResultId,
         @RetentionDocumentId, @ManualSourceId, 1, 1, 0, 18,
         N'Retention evidence', @RetentionEvidenceHash, 1, @ManualPolicyVersion,
         @RetentionDueAtUtc, DATEADD(HOUR, 1, @RetentionCreatedAtUtc));

    DECLARE @DueRunPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @LiveRunPublicId UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.FundingPlatform_ImportRuns
        (PublicId, FundingSourceId, TriggerType, Status, Keyword, MaximumResults,
         CorrelationId, RequestedByUserId, ScheduleSlotUtc, IdempotencyKeyHash, RequestHash,
         AttemptCount, MaxAttempts, RetryBaseDelaySeconds, NextAttemptAtUtc,
         LeaseId, LeaseUntilUtc, RetrievedCount, FailedCount,
         StartedAtUtc, CompletedAtUtc, CreatedAtUtc, UpdatedAtUtc,
         ContentRetentionDaysSnapshot, AcquisitionPolicyVersionSnapshot,
         AcquisitionPolicyFingerprintSnapshot)
    VALUES
        (@DueRunPublicId, @ApiSourceId, 0, 2, N'retention', 1,
         N'phase7b-retention-due', @AdminUserId, NULL,
         HASHBYTES('SHA2_256', N'due-run-idem-' + @Suffix),
         HASHBYTES('SHA2_256', N'due-run-request-' + @Suffix),
         1, 3, 30, @RetentionCreatedAtUtc, NULL, NULL, 1, 1,
         @RetentionCreatedAtUtc, DATEADD(HOUR, 1, @RetentionCreatedAtUtc),
         @RetentionCreatedAtUtc, DATEADD(HOUR, 1, @RetentionCreatedAtUtc),
         @ApiRetentionDays, @ApiPolicyVersion, @ApiPolicyFingerprint),
        (@LiveRunPublicId, @ApiSourceId, 0, 1, N'retention', 1,
         N'phase7b-retention-live', @AdminUserId, NULL,
         HASHBYTES('SHA2_256', N'live-run-idem-' + @Suffix),
         HASHBYTES('SHA2_256', N'live-run-request-' + @Suffix),
         1, 3, 30, @NowUtc, NEWID(), DATEADD(HOUR, 1, @NowUtc), 1, 0,
         @NowUtc, NULL, @NowUtc, @NowUtc,
         @ApiRetentionDays, @ApiPolicyVersion, @ApiPolicyFingerprint);
    DECLARE @DueRunId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_ImportRuns WHERE PublicId = @DueRunPublicId);
    DECLARE @LiveRunId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_ImportRuns WHERE PublicId = @LiveRunPublicId);

    DECLARE @RawContent NVARCHAR(MAX) = N'{"source":"retention-smoke"}';
    DECLARE @RawContentHash BINARY(32) = HASHBYTES(
        'SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
        @RawContent COLLATE Latin1_General_100_BIN2_UTF8)));
    DECLARE @RawItemKeyHash BINARY(32) = HASHBYTES('SHA2_256', N'retention-key-' + @Suffix);
    DECLARE @RawPublicId UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.FundingPlatform_RawFundingOpportunities
        (PublicId, FundingSourceId, ExternalId, SourceItemKeyHash, ContentHash,
         SourceUrl, MimeType, RawContent, RetrievedAtUtc, CreatedAtUtc,
         ContentRetentionDays, AcquisitionPolicyVersion, RetentionUntilUtc)
    VALUES
        (@RawPublicId, @ApiSourceId, N'retention-' + @Suffix,
         @RawItemKeyHash, @RawContentHash,
         N'https://example.invalid/retention/' + @Suffix, N'application/json',
         @RawContent, @RetentionCreatedAtUtc, @RetentionCreatedAtUtc,
         @ApiRetentionDays, @ApiPolicyVersion, @RetentionDueAtUtc);
    DECLARE @RawId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_RawFundingOpportunities WHERE PublicId = @RawPublicId);

    DECLARE @NotDueRawContent NVARCHAR(MAX) = N'{"source":"not-due"}';
    DECLARE @NotDueRawHash BINARY(32) = HASHBYTES(
        'SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
        @NotDueRawContent COLLATE Latin1_General_100_BIN2_UTF8)));
    DECLARE @NotDueRawPublicId UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.FundingPlatform_RawFundingOpportunities
        (PublicId, FundingSourceId, ExternalId, SourceItemKeyHash, ContentHash,
         SourceUrl, MimeType, RawContent, RetrievedAtUtc, CreatedAtUtc,
         ContentRetentionDays, AcquisitionPolicyVersion, RetentionUntilUtc)
    VALUES
        (@NotDueRawPublicId, @ApiSourceId, N'not-due-' + @Suffix,
         HASHBYTES('SHA2_256', N'not-due-key-' + @Suffix), @NotDueRawHash,
         N'https://example.invalid/not-due/' + @Suffix, N'application/json',
         @NotDueRawContent, @NowUtc, @NowUtc, @ApiRetentionDays, @ApiPolicyVersion,
         DATEADD(DAY, @ApiRetentionDays, @NowUtc));

    DECLARE @NormalizedSnapshot NVARCHAR(MAX) =
        N'{"schemaVersion":1,"opportunity":{"title":"Retention candidate"}}';
    DECLARE @NormalizedSnapshotHash BINARY(32) = HASHBYTES(
        'SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
        @NormalizedSnapshot COLLATE Latin1_General_100_BIN2_UTF8)));
    DECLARE @DueItemPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @LiveItemPublicId UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.FundingPlatform_ImportRunItems
        (PublicId, ImportRunId, FundingSourceId, RawFundingOpportunityId,
         FundingOpportunityId, ExternalId, SourceItemKeyHash,
         NormalizedSnapshotVersion, NormalizedSnapshotJson, NormalizedSnapshotHash,
         Status, OutcomeCode, CreatedAtUtc, CompletedAtUtc, UpdatedAtUtc,
         ContentRetentionDays, AcquisitionPolicyVersion, RetentionUntilUtc)
    VALUES
        (@DueItemPublicId, @DueRunId, @ApiSourceId, @RawId, NULL,
         N'retention-due-' + @Suffix, @RawItemKeyHash, 1,
         @NormalizedSnapshot, @NormalizedSnapshotHash, 3, N'failed',
         @RetentionCreatedAtUtc, DATEADD(HOUR, 1, @RetentionCreatedAtUtc),
         DATEADD(HOUR, 1, @RetentionCreatedAtUtc), @ApiRetentionDays, @ApiPolicyVersion,
         @RetentionDueAtUtc),
        (@LiveItemPublicId, @LiveRunId, @ApiSourceId, @RawId, NULL,
         N'retention-live-' + @Suffix, @RawItemKeyHash, 1,
         @NormalizedSnapshot, @NormalizedSnapshotHash, 1, NULL,
         @NowUtc, NULL, @NowUtc, @ApiRetentionDays, @ApiPolicyVersion,
         DATEADD(DAY, @ApiRetentionDays, @NowUtc));

    DECLARE @RetentionRunResult TABLE
    (
        RunPublicId UNIQUEIDENTIFIER, RawRedactedCount INT, ItemRedactedCount INT,
        ResultRedactedCount INT, EvidenceRedactedCount INT,
        StartedAtUtc DATETIME2(3), CompletedAtUtc DATETIME2(3)
    );
    INSERT INTO @RetentionRunResult
    EXEC dbo.FundingPlatform_usp_ContentRetention_Enforce
        @BatchSize = 500, @NowUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @RetentionRunResult
        WHERE RawRedactedCount >= 1 AND ItemRedactedCount >= 1
          AND ResultRedactedCount >= 1 AND EvidenceRedactedCount >= 1
          AND CompletedAtUtc >= StartedAtUtc AND @NowUtc <= CompletedAtUtc)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_RawFundingOpportunities
           WHERE PublicId = @RawPublicId AND IsContentRedacted = 1
             AND RawContent = N'{"redacted":true}' AND ContentHash = @RawContentHash
             AND SourceItemKeyHash = @RawItemKeyHash)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ImportRunItems
           WHERE PublicId = @DueItemPublicId AND IsContentRedacted = 1
             AND JSON_VALUE(NormalizedSnapshotJson, N'$.opportunity.redacted') = N'true'
             AND NormalizedSnapshotHash = @NormalizedSnapshotHash)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ImportRunItems
           WHERE PublicId = @LiveItemPublicId AND Status = 1 AND IsContentRedacted = 0
             AND NormalizedSnapshotJson = @NormalizedSnapshot)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_RawFundingOpportunities
           WHERE PublicId = @NotDueRawPublicId AND IsContentRedacted = 0
             AND RawContent = @NotDueRawContent AND ContentHash = @NotDueRawHash)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentExtractionResults
           WHERE PublicId = @RetentionResultPublicId AND IsContentRedacted = 1
             AND ExtractedText = N'' AND CharacterCount = 0
             AND ExtractedTextHash = @RetentionResultHash)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentExtractionEvidence
           WHERE PublicId = @RetentionEvidencePublicId AND IsContentRedacted = 1
             AND Excerpt = N'[redacted]' AND EvidenceHash = @RetentionEvidenceHash)
        THROW 53656, N'Due retention content was not tombstoned without losing provenance.', 1;

    DELETE FROM @RetentionRunResult;
    INSERT INTO @RetentionRunResult
    EXEC dbo.FundingPlatform_usp_ContentRetention_Enforce
        @BatchSize = 500, @NowUtc = @NowUtc;
    IF EXISTS
       (SELECT 1 FROM @RetentionRunResult
        WHERE RawRedactedCount <> 0 OR ItemRedactedCount <> 0
           OR ResultRedactedCount <> 0 OR EvidenceRedactedCount <> 0)
        THROW 53657, N'Retention enforcement was not idempotent.', 1;

    /* Blob retention uses exact immutable identities and a durable lease.  It
       also closes the Event Grid race before a worker can reopen deleted bytes. */
    DECLARE @RetentionRetryDocumentPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @RetentionRaceDocumentPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @RetentionRetryHash BINARY(32) =
        HASHBYTES('SHA2_256', N'retention-retry-' + @Suffix);
    DECLARE @RetentionRaceHash BINARY(32) =
        HASHBYTES('SHA2_256', N'retention-race-' + @Suffix);
    DECLARE @RetentionRetryETag NVARCHAR(100) =
        N'"retention-retry-' + LEFT(@Suffix, 16) + N'"';
    DECLARE @RetentionRaceETag NVARCHAR(100) =
        N'"retention-race-' + LEFT(@Suffix, 16) + N'"';
    DECLARE @RetentionRetryObject NVARCHAR(1024) =
        N'retention-retry/' + @Suffix + N'.pdf';
    DECLARE @RetentionRaceObject NVARCHAR(1024) =
        N'retention-race/' + @Suffix + N'.pdf';
    INSERT INTO dbo.FundingPlatform_SourceDocuments
        (PublicId, FundingSourceId, OriginalFileName, MimeType, ContentLength, ContentHash,
         BlobContainer, BlobObjectName, BlobETag,
         TrustedBlobContainer, TrustedBlobObjectName, TrustedBlobETag,
         StorageStatus, ScanStatus, ScanProvider, ScanAttemptCount, ScanResultCode,
         ScanStartedAtUtc, ScanCompletedAtUtc, ExtractionStatus, UploadedByUserId,
         ContentRetentionDays, AcquisitionPolicyVersion, RetentionUntilUtc,
         ContentRetentionNextAttemptAtUtc, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@RetentionRetryDocumentPublicId, @ManualSourceId, N'retention-retry.pdf',
         N'application/pdf', 1024, @RetentionRetryHash, N'phase7b-quarantine',
         @RetentionRetryObject, @RetentionRetryETag, N'phase7b-trusted',
         @RetentionRetryObject, @RetentionRetryETag, 2, 1, 0, 1, N'clean',
         @RetentionCreatedAtUtc, @RetentionCreatedAtUtc, 0, @AdminUserId,
         @ManualRetentionDays, @ManualPolicyVersion, @RetentionDueAtUtc,
         @RetentionCreatedAtUtc, @RetentionCreatedAtUtc, @RetentionCreatedAtUtc),
        (@RetentionRaceDocumentPublicId, @ManualSourceId, N'retention-race.pdf',
         N'application/pdf', 1024, @RetentionRaceHash, @DefenderContainer,
         @RetentionRaceObject, @RetentionRaceETag, NULL, NULL, NULL,
         1, 0, 1, 1, NULL, @NowUtc, NULL, 0, @AdminUserId,
         @ManualRetentionDays, @ManualPolicyVersion, @RetentionDueAtUtc,
         @RetentionCreatedAtUtc, @RetentionCreatedAtUtc, @NowUtc);

    DECLARE @RetentionRaceEventId NVARCHAR(200) = N'retention-race-' + @Suffix;
    DECLARE @RetentionRacePayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'retention-race-payload-' + @Suffix);
    DELETE FROM @ReceiptResult;
    INSERT INTO @ReceiptResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Record
        @ProviderEventId = @RetentionRaceEventId,
        @PayloadHash = @RetentionRacePayloadHash,
        @AuthenticatedTenantId = @TenantId, @AuthenticatedPrincipalId = @PrincipalId,
        @ApplicationClientId = @ApplicationId, @TopicResourceId = @TopicResourceId,
        @EventSubscriptionName = N'phase7b-defender-subscription',
        @StorageAccountResourceId = @StorageResourceId, @BlobHost = @StorageHost,
        @BlobContainer = @DefenderContainer, @BlobObjectName = @RetentionRaceObject,
        @BlobETag = @RetentionRaceETag, @ReportedContentHash = @RetentionRaceHash,
        @ToStatus = 1, @ResultCode = N'clean',
        @OccurredAtUtc = @NowUtc, @ReceivedAtUtc = @NowUtc;
    DECLARE @RetentionRaceReceiptPublicId UNIQUEIDENTIFIER =
        (SELECT ReceiptPublicId FROM @ReceiptResult
         WHERE Succeeded = 1 AND Code = N'accepted');
    IF @RetentionRaceReceiptPublicId IS NULL
        THROW 53670, N'The retention race fixture was not accepted.', 1;

    DECLARE @RetentionLease1 UNIQUEIDENTIFIER = NEWID();
    DECLARE @RetentionLease2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @RetentionClaims TABLE
    (
        SourceDocumentPublicId UNIQUEIDENTIFIER, FundingSourceId INT,
        ContentHash BINARY(32), ContentLength BIGINT,
        QuarantineBlobContainer NVARCHAR(63),
        QuarantineBlobObjectName NVARCHAR(1024), QuarantineBlobETag NVARCHAR(100),
        TrustedBlobContainer NVARCHAR(63), TrustedBlobObjectName NVARCHAR(1024),
        TrustedBlobETag NVARCHAR(100), RetentionUntilUtc DATETIME2(3),
        AttemptCount SMALLINT, MaxAttempts SMALLINT, LeaseUntilUtc DATETIME2(3),
        RequiresTrustedDelete BIT
    );
    INSERT INTO @RetentionClaims
    EXEC dbo.FundingPlatform_usp_SourceDocumentContentRetention_Claim
        @BatchSize = 100, @LeaseId = @RetentionLease1,
        @LeaseSeconds = 120, @NowUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @RetentionClaims
        WHERE SourceDocumentPublicId = @RetentionDocumentPublicId
          AND QuarantineBlobETag = @RetentionDocumentETag
          AND TrustedBlobETag = @RetentionDocumentETag
          AND RequiresTrustedDelete = 1 AND AttemptCount = 1)
       OR NOT EXISTS
          (SELECT 1 FROM @RetentionClaims
           WHERE SourceDocumentPublicId = @RetentionRetryDocumentPublicId
             AND ContentHash = @RetentionRetryHash AND RequiresTrustedDelete = 1)
       OR NOT EXISTS
          (SELECT 1 FROM @RetentionClaims
           WHERE SourceDocumentPublicId = @RetentionRaceDocumentPublicId
             AND RequiresTrustedDelete = 0)
       OR EXISTS
          (SELECT 1 FROM @RetentionClaims
           WHERE SourceDocumentPublicId = @CleanDocumentPublicId)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentDefenderReceipts
           WHERE PublicId = @RetentionRaceReceiptPublicId AND ReceiptStatus = 2
             AND OutcomeCode = N'content-retention-ignored'
             AND FinalizedAtUtc = @NowUtc)
        THROW 53671, N'Blob retention claim was not exact, due-only or race-safe.', 1;

    DELETE FROM @ApplyScanResult;
    INSERT INTO @ApplyScanResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_ApplyScanResult
        @SourceDocumentPublicId = @RetentionRaceDocumentPublicId, @ScanProvider = 1,
        @ProviderEventId = @RetentionRaceEventId, @PayloadHash = @RetentionRacePayloadHash,
        @BlobETag = @RetentionRaceETag, @ReportedContentHash = @RetentionRaceHash,
        @ToStatus = 1, @ResultCode = N'clean',
        @TrustedBlobContainer = N'phase7b-defender-trusted',
        @TrustedBlobObjectName = @RetentionRaceObject,
        @TrustedBlobETag = @RetentionRaceETag, @OccurredAtUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyScanResult
        WHERE Succeeded = 1 AND Code = N'content-retention-ignored')
        THROW 53672, N'An in-flight scan reopened a retention-leased document.', 1;

    DELETE FROM @ReceiptResult;
    INSERT INTO @ReceiptResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Record
        @ProviderEventId = @RetentionRaceEventId,
        @PayloadHash = @RetentionRacePayloadHash,
        @AuthenticatedTenantId = @TenantId, @AuthenticatedPrincipalId = @PrincipalId,
        @ApplicationClientId = @ApplicationId, @TopicResourceId = @TopicResourceId,
        @EventSubscriptionName = N'phase7b-defender-subscription',
        @StorageAccountResourceId = @StorageResourceId, @BlobHost = @StorageHost,
        @BlobContainer = @DefenderContainer, @BlobObjectName = @RetentionRaceObject,
        @BlobETag = @RetentionRaceETag, @ReportedContentHash = @RetentionRaceHash,
        @ToStatus = 1, @ResultCode = N'clean',
        @OccurredAtUtc = @NowUtc, @ReceivedAtUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @ReceiptResult
        WHERE Succeeded = 0 AND Code = N'replayed-ignored' AND WasReplay = 1)
        THROW 53673, N'Retention-ignored Defender replay was not terminal.', 1;

    DECLARE @RetentionCompletion TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), SourceDocumentPublicId UNIQUEIDENTIFIER,
        ContentDeletionRequestedAtUtc DATETIME2(3) NULL, WasReplay BIT
    );
    INSERT INTO @RetentionCompletion
    EXEC dbo.FundingPlatform_usp_SourceDocumentContentRetention_Complete
        @SourceDocumentPublicId = @RetentionDocumentPublicId,
        @LeaseId = @RetentionLease1, @QuarantineDeleted = 1, @TrustedDeleted = 1,
        @NowUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @RetentionCompletion
        WHERE Succeeded = 1 AND Code = N'completed' AND WasReplay = 0
          AND ContentDeletionRequestedAtUtc = @NowUtc)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocuments
           WHERE PublicId = @RetentionDocumentPublicId
             AND ContentRetentionStatus = 2
             AND ContentDeletionRequestedAtUtc = @NowUtc)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
           WHERE MessageType = N'SourceDocumentContentDeletionRequested'
             AND AggregateId = CONVERT(NVARCHAR(100), @RetentionDocumentPublicId)
             AND JSON_VALUE(PayloadJson, N'$.sourceDocumentId') =
                 CONVERT(NVARCHAR(36), @RetentionDocumentPublicId)
             AND JSON_VALUE(PayloadJson, N'$.version') = N'1'
             AND JSON_QUERY(PayloadJson, N'$.blob') IS NULL)
        THROW 53674, N'Blob retention completion did not create a safe tombstone.', 1;

    DECLARE @RetentionDeletionRequestedAtUtc DATETIME2(3) =
        (SELECT ContentDeletionRequestedAtUtc FROM @RetentionCompletion
         WHERE Succeeded = 1);
    DELETE FROM @RetentionCompletion;
    INSERT INTO @RetentionCompletion
    EXEC dbo.FundingPlatform_usp_SourceDocumentContentRetention_Complete
        @SourceDocumentPublicId = @RetentionDocumentPublicId,
        @LeaseId = @RetentionLease1, @QuarantineDeleted = 1, @TrustedDeleted = 1,
        @NowUtc = @NowPlusOneSecond;
    IF NOT EXISTS
       (SELECT 1 FROM @RetentionCompletion
        WHERE Succeeded = 1 AND Code = N'completed' AND WasReplay = 1
          AND ContentDeletionRequestedAtUtc = @RetentionDeletionRequestedAtUtc)
        THROW 53675, N'Blob retention completion replay changed its timestamp.', 1;

    DECLARE @RetentionFailure TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), SourceDocumentPublicId UNIQUEIDENTIFIER,
        NextAttemptAtUtc DATETIME2(3) NULL, AttemptCount SMALLINT, MaxAttempts SMALLINT
    );
    INSERT INTO @RetentionFailure
    EXEC dbo.FundingPlatform_usp_SourceDocumentContentRetention_Fail
        @SourceDocumentPublicId = @RetentionRetryDocumentPublicId,
        @LeaseId = @RetentionLease1, @ErrorCode = N'blob-delete-transient',
        @IsRetryable = 1, @NowUtc = @NowUtc;
    DECLARE @RetentionRetryAtUtc DATETIME2(3) =
        (SELECT NextAttemptAtUtc FROM @RetentionFailure
         WHERE Succeeded = 1 AND Code = N'retry-scheduled');
    IF @RetentionRetryAtUtc IS NULL
       OR NOT EXISTS
          (SELECT 1 FROM @RetentionFailure
           WHERE AttemptCount = 1 AND MaxAttempts = 5)
        THROW 53676, N'Blob retention retry was not scheduled durably.', 1;

    DECLARE @BeforeRetentionRetryAtUtc DATETIME2(3) =
        DATEADD(MILLISECOND, -1, @RetentionRetryAtUtc);
    DELETE FROM @RetentionClaims;
    INSERT INTO @RetentionClaims
    EXEC dbo.FundingPlatform_usp_SourceDocumentContentRetention_Claim
        @BatchSize = 100, @LeaseId = @RetentionLease2,
        @LeaseSeconds = 120, @NowUtc = @BeforeRetentionRetryAtUtc;
    IF EXISTS
       (SELECT 1 FROM @RetentionClaims
        WHERE SourceDocumentPublicId = @RetentionRetryDocumentPublicId)
        THROW 53677, N'Blob retention retried before its backoff elapsed.', 1;

    DELETE FROM @RetentionClaims;
    INSERT INTO @RetentionClaims
    EXEC dbo.FundingPlatform_usp_SourceDocumentContentRetention_Claim
        @BatchSize = 100, @LeaseId = @RetentionLease2,
        @LeaseSeconds = 120, @NowUtc = @RetentionRetryAtUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @RetentionClaims
        WHERE SourceDocumentPublicId = @RetentionRetryDocumentPublicId
          AND AttemptCount = 2 AND QuarantineBlobETag = @RetentionRetryETag)
        THROW 53678, N'Blob retention retry could not reclaim the exact version.', 1;

    DELETE FROM @RetentionCompletion;
    INSERT INTO @RetentionCompletion
    EXEC dbo.FundingPlatform_usp_SourceDocumentContentRetention_Complete
        @SourceDocumentPublicId = @RetentionRetryDocumentPublicId,
        @LeaseId = @RetentionLease2, @QuarantineDeleted = 1, @TrustedDeleted = 1,
        @NowUtc = @RetentionRetryAtUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @RetentionCompletion
        WHERE Succeeded = 1 AND Code = N'completed' AND WasReplay = 0)
        THROW 53679, N'Blob retention retry did not complete after backoff.', 1;

    /* A completed real import item materializes an advisory duplicate. Listing,
       comparing and deciding it never edits or publishes either opportunity. */
    DECLARE @CanonicalOpportunityPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @CandidateOpportunityPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @DuplicateFingerprint BINARY(32) =
        HASHBYTES('SHA2_256', N'duplicate-fingerprint-' + @Suffix);
    INSERT INTO dbo.FundingPlatform_FundingOpportunities
        (PublicId, Slug, Title, SponsorName, AmountStatus,
         DeadlineType, DeadlinePrecision, GeographicScope, RemoteApplication,
         PublicationStatus, ContentVersion, ContentFingerprint, IsActive,
         CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@CanonicalOpportunityPublicId, N'phase7b-canonical-' + @Suffix,
         N'Phase 7B duplicate opportunity', N'Phase 7B sponsor', 0,
         0, 0, 0, 0, 0, 1, @DuplicateFingerprint, 1,
         DATEADD(MINUTE, -1, @NowUtc), DATEADD(MINUTE, -1, @NowUtc)),
        (@CandidateOpportunityPublicId, N'phase7b-candidate-' + @Suffix,
         N'Phase 7B duplicate opportunity', N'Phase 7B sponsor', 0,
         0, 0, 0, 0, 0, 1, @DuplicateFingerprint, 1, @NowUtc, @NowUtc);
    DECLARE @CanonicalOpportunityId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_FundingOpportunities
         WHERE PublicId = @CanonicalOpportunityPublicId);
    DECLARE @CandidateOpportunityId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_FundingOpportunities
         WHERE PublicId = @CandidateOpportunityPublicId);
    DECLARE @CanonicalOpportunityRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_FundingOpportunities
         WHERE Id = @CanonicalOpportunityId);
    DECLARE @CandidateOpportunityRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_FundingOpportunities
         WHERE Id = @CandidateOpportunityId);

    UPDATE dbo.FundingPlatform_ImportRunItems
    SET FundingOpportunityId = @CandidateOpportunityId,
        Status = 2, OutcomeCode = N'created', CompletedAtUtc = @NowUtc,
        UpdatedAtUtc = @NowUtc
    WHERE PublicId = @LiveItemPublicId AND Status = 1;

    DECLARE @DuplicateCandidatePublicId UNIQUEIDENTIFIER =
        (SELECT PublicId
         FROM dbo.FundingPlatform_FundingOpportunityDuplicateCandidates
         WHERE ImportRunItemId =
               (SELECT Id FROM dbo.FundingPlatform_ImportRunItems
                WHERE PublicId = @LiveItemPublicId)
           AND CandidateOpportunityId = @CandidateOpportunityId
           AND SuggestedCanonicalOpportunityId = @CanonicalOpportunityId);
    IF @DuplicateCandidatePublicId IS NULL
        THROW 53658, N'A completed import item did not materialize a duplicate candidate.', 1;

    DECLARE @EvaluateResult TABLE
        (Succeeded BIT, Code NVARCHAR(50), CandidatePublicId UNIQUEIDENTIFIER NULL);
    INSERT INTO @EvaluateResult
    EXEC dbo.FundingPlatform_usp_FundingOpportunityDuplicateCandidate_AdminEvaluate
        @AdminUserPublicId = @AdminPublicId,
        @ImportRunItemPublicId = @LiveItemPublicId, @NowUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @EvaluateResult
        WHERE Succeeded = 1 AND Code = N'evaluated'
          AND CandidatePublicId = @DuplicateCandidatePublicId)
        THROW 53659, N'Duplicate evaluation replay did not resolve the item candidate.', 1;

    DECLARE @DuplicateList TABLE
    (
        CandidatePublicId UNIQUEIDENTIFIER,
        CandidateOpportunityPublicId UNIQUEIDENTIFIER,
        CandidateTitle NVARCHAR(350), CandidateSponsor NVARCHAR(300),
        SuggestedCanonicalOpportunityPublicId UNIQUEIDENTIFIER NULL,
        SuggestedCanonicalTitle NVARCHAR(350) NULL,
        MatchKind TINYINT, Confidence DECIMAL(5,4), Status TINYINT,
        CreatedAtUtc DATETIME2(3), DecidedAtUtc DATETIME2(3) NULL,
        RowVersion BINARY(8), TotalCount BIGINT
    );
    INSERT INTO @DuplicateList
    EXEC dbo.FundingPlatform_usp_FundingOpportunityDuplicateCandidate_AdminList
        @AdminUserPublicId = @AdminPublicId, @Status = 0, @Page = 1, @PageSize = 100;
    IF NOT EXISTS
       (SELECT 1 FROM @DuplicateList
        WHERE CandidatePublicId = @DuplicateCandidatePublicId
          AND CandidateOpportunityPublicId = @CandidateOpportunityPublicId
          AND SuggestedCanonicalOpportunityPublicId = @CanonicalOpportunityPublicId
          AND MatchKind = 0 AND Confidence = CONVERT(DECIMAL(5,4), 1))
        THROW 53660, N'The advisory duplicate was not visible in the admin list.', 1;

    DECLARE @DuplicateDetail TABLE
    (
        CandidatePublicId UNIQUEIDENTIFIER,
        CandidateOpportunityPublicId UNIQUEIDENTIFIER,
        CandidateTitle NVARCHAR(350), CandidateSponsor NVARCHAR(300),
        CandidatePublicationStatus TINYINT,
        SuggestedCanonicalOpportunityPublicId UNIQUEIDENTIFIER NULL,
        SuggestedCanonicalTitle NVARCHAR(350) NULL,
        SuggestedCanonicalSponsor NVARCHAR(300) NULL,
        SuggestedCanonicalPublicationStatus TINYINT NULL,
        MatchKind TINYINT, Confidence DECIMAL(5,4), EvidenceJson NVARCHAR(MAX),
        Status TINYINT, CreatedAtUtc DATETIME2(3), DecidedAtUtc DATETIME2(3) NULL,
        DecisionPublicId UNIQUEIDENTIFIER NULL, Decision TINYINT NULL,
        DecidedCanonicalOpportunityPublicId UNIQUEIDENTIFIER NULL,
        DecisionReason NVARCHAR(500) NULL, DecisionCreatedAtUtc DATETIME2(3) NULL,
        RowVersion BINARY(8)
    );
    INSERT INTO @DuplicateDetail
    EXEC dbo.FundingPlatform_usp_FundingOpportunityDuplicateCandidate_AdminGet
        @AdminUserPublicId = @AdminPublicId,
        @CandidatePublicId = @DuplicateCandidatePublicId;
    DECLARE @DuplicateCandidateRowVersion BINARY(8) =
        (SELECT RowVersion FROM @DuplicateDetail
         WHERE CandidatePublicId = @DuplicateCandidatePublicId);
    IF @DuplicateCandidateRowVersion IS NULL
       OR NOT EXISTS
          (SELECT 1 FROM @DuplicateDetail
           WHERE CandidatePublicId = @DuplicateCandidatePublicId
             AND ISJSON(EvidenceJson) = 1
             AND JSON_VALUE(EvidenceJson, N'$.method') = N'exact-content-fingerprint'
             AND Status = 0 AND DecisionPublicId IS NULL)
        THROW 53661, N'Duplicate comparison detail is incomplete.', 1;

    DECLARE @DecisionIdempotencyHash BINARY(32) =
        HASHBYTES('SHA2_256', N'dedupe-decision-idem-' + @Suffix);
    DECLARE @DecisionRequestHash BINARY(32) =
        HASHBYTES('SHA2_256', N'dedupe-decision-request-' + @Suffix);
    DECLARE @DecisionAtUtc DATETIME2(3) = DATEADD(SECOND, 1, @NowUtc);
    DECLARE @DecisionResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), CandidatePublicId UNIQUEIDENTIFIER NULL,
        DecisionPublicId UNIQUEIDENTIFIER NULL, Status TINYINT NULL,
        Decision TINYINT NULL, CanonicalOpportunityPublicId UNIQUEIDENTIFIER NULL,
        DecidedAtUtc DATETIME2(3) NULL, RowVersion BINARY(8) NULL, WasReplay BIT
    );
    INSERT INTO @DecisionResult
    EXEC dbo.FundingPlatform_usp_FundingOpportunityDuplicateCandidate_AdminDecide
        @AdminUserPublicId = @AdminPublicId,
        @CandidatePublicId = @DuplicateCandidatePublicId,
        @ExpectedRowVersion = @DuplicateCandidateRowVersion,
        @Decision = 2,
        @CanonicalOpportunityPublicId = @CanonicalOpportunityPublicId,
        @Reason = N'Exact fingerprint reviewed by the Phase 7B smoke.',
        @IdempotencyKeyHash = @DecisionIdempotencyHash,
        @RequestHash = @DecisionRequestHash, @DecidedAtUtc = @DecisionAtUtc;
    DECLARE @DecisionPublicId UNIQUEIDENTIFIER =
        (SELECT DecisionPublicId FROM @DecisionResult WHERE Succeeded = 1);
    IF @DecisionPublicId IS NULL
       OR NOT EXISTS
          (SELECT 1 FROM @DecisionResult
           WHERE Code = N'decided' AND Status = 1 AND Decision = 2
             AND CanonicalOpportunityPublicId = @CanonicalOpportunityPublicId
             AND DecidedAtUtc = @DecisionAtUtc AND WasReplay = 0)
        THROW 53662, N'The reviewed duplicate decision was not recorded.', 1;

    DECLARE @DecisionReplayAtUtc DATETIME2(3) = DATEADD(HOUR, 1, @DecisionAtUtc);
    DELETE FROM @DecisionResult;
    INSERT INTO @DecisionResult
    EXEC dbo.FundingPlatform_usp_FundingOpportunityDuplicateCandidate_AdminDecide
        @AdminUserPublicId = @AdminPublicId,
        @CandidatePublicId = @DuplicateCandidatePublicId,
        @ExpectedRowVersion = @DuplicateCandidateRowVersion,
        @Decision = 2,
        @CanonicalOpportunityPublicId = @CanonicalOpportunityPublicId,
        @Reason = N'Exact fingerprint reviewed by the Phase 7B smoke.',
        @IdempotencyKeyHash = @DecisionIdempotencyHash,
        @RequestHash = @DecisionRequestHash,
        @DecidedAtUtc = @DecisionReplayAtUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @DecisionResult
        WHERE Succeeded = 1 AND Code = N'replayed' AND WasReplay = 1
          AND DecisionPublicId = @DecisionPublicId AND DecidedAtUtc = @DecisionAtUtc)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
           WHERE (Id = @CanonicalOpportunityId AND
                  (RowVersion <> @CanonicalOpportunityRowVersion
                   OR Title <> N'Phase 7B duplicate opportunity'
                   OR PublicationStatus <> 0 OR ContentVersion <> 1))
              OR (Id = @CandidateOpportunityId AND
                  (RowVersion <> @CandidateOpportunityRowVersion
                   OR Title <> N'Phase 7B duplicate opportunity'
                   OR PublicationStatus <> 0 OR ContentVersion <> 1)))
        THROW 53663, N'Dedupe replay changed its timestamp or mutated opportunity content.', 1;

    DELETE FROM @DuplicateDetail;
    INSERT INTO @DuplicateDetail
    EXEC dbo.FundingPlatform_usp_FundingOpportunityDuplicateCandidate_AdminGet
        @AdminUserPublicId = @AdminPublicId,
        @CandidatePublicId = @DuplicateCandidatePublicId;
    IF NOT EXISTS
       (SELECT 1 FROM @DuplicateDetail
        WHERE CandidatePublicId = @DuplicateCandidatePublicId AND Status = 1
          AND DecisionPublicId = @DecisionPublicId AND Decision = 2
          AND DecidedCanonicalOpportunityPublicId = @CanonicalOpportunityPublicId
          AND DecisionCreatedAtUtc = @DecisionAtUtc)
        THROW 53664, N'The durable human decision was not visible in comparison detail.', 1;

    /* Manual document uploads are extraction inputs, not executable acquisition
       providers. A legacy import request is terminalized before taking a lease. */
    DECLARE @ManualRunCreate TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), RunPublicId UNIQUEIDENTIFIER NULL,
        FundingSourceId INT, SourceName NVARCHAR(150) NULL, Status TINYINT NULL,
        CreatedAtUtc DATETIME2(3) NULL, WasReplay BIT
    );
    INSERT INTO @ManualRunCreate
    EXEC dbo.FundingPlatform_usp_ImportRun_Admin_Create
        @AdminUserPublicId = @AdminPublicId, @FundingSourceId = @ManualSourceId,
        @Keyword = N'manual-document-is-not-an-import-provider', @MaximumResults = 1,
        @IdempotencyKeyHash = 0x2525252525252525252525252525252525252525252525252525252525252525,
        @RequestHash = 0x2626262626262626262626262626262626262626262626262626262626262626,
        @CorrelationId = N'phase7b-manual-import';
    DECLARE @UnsupportedManualRunPublicId UNIQUEIDENTIFIER =
        (SELECT RunPublicId FROM @ManualRunCreate WHERE Succeeded = 1);
    IF @UnsupportedManualRunPublicId IS NULL
        THROW 53665, N'The manual-provider compatibility fixture was not created.', 1;

    DECLARE @UnsupportedManualLeaseId UNIQUEIDENTIFIER = NEWID();
    DECLARE @UnsupportedManualClaimAtUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @ImportClaimResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), RunPublicId UNIQUEIDENTIFIER NULL,
        FundingSourceId INT NULL, ProviderCode NVARCHAR(100) NULL,
        Keyword NVARCHAR(100) NULL, MaximumResults INT NULL,
        AttemptCount SMALLINT NULL, RetrievedCount INT NULL,
        LeaseUntilUtc DATETIME2(3) NULL, RequestRateLimitPerMinute INT NULL,
        MaximumResponseBytes INT NULL, ContentRetentionDays SMALLINT NULL,
        AcquisitionPolicyVersion INT NULL, AcquisitionPolicyFingerprint BINARY(32) NULL
    );
    INSERT INTO @ImportClaimResult
    EXEC dbo.FundingPlatform_usp_ImportRun_Claim
        @RunPublicId = @UnsupportedManualRunPublicId, @LeaseId = @UnsupportedManualLeaseId,
        @LeaseSeconds = 60, @NowUtc = @UnsupportedManualClaimAtUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @ImportClaimResult
        WHERE Succeeded = 0 AND Code = N'provider-not-supported'
          AND ProviderCode = N'manual-document' AND LeaseUntilUtc IS NULL
          AND RequestRateLimitPerMinute IS NULL)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ImportRuns
           WHERE PublicId = @UnsupportedManualRunPublicId AND Status = 5
             AND LeaseId IS NULL AND LeaseUntilUtc IS NULL
             AND LastErrorCode = N'provider-not-supported')
        THROW 53666, N'An unsupported manual acquisition run took a worker lease.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke016;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FP_Smoke016;
    THROW;
END CATCH;

SELECT N'FASE 7B governed document extraction smoke passed.' AS Result;
GO
