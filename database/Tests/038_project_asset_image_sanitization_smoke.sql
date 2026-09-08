/* Transactional smoke for migration 038: trusted manifests and image sanitization. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre038', N'P') IS NULL
   OR OBJECT_ID(
          N'dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Finalize', N'P') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_ProjectAssets', N'TrustedContentHash') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_ProjectAssets', N'TrustedProcessingVersion') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_ProjectAssetScanEvents',
                 N'ProviderObservedStatus') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_ProjectAssetScanEvents',
                 N'RevokedTrustedContentHash') IS NULL
    THROW 55830, N'Project asset sanitization persistence contract is missing.', 1;

IF NOT EXISTS
   (SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_ProjectAssets', N'U')
      AND name = N'FundingPlatform_CK_ProjectAssets_TrustedManifest'
      AND definition LIKE N'%skia-4.151.2-image-v1%'
      AND definition LIKE N'%pdf-copy-v1%')
   OR NOT EXISTS
   (SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id =
          OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetScanEvents', N'U')
      AND name = N'FundingPlatform_CK_ProjectAssetScanEvents_Result'
      AND definition LIKE N'%ProviderObservedStatus%'
      AND definition LIKE N'%image-output-too-large%')
    THROW 55831, N'Trusted-manifest or derived-result constraints drifted.', 1;

DECLARE @ApplyDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult', N'P'));
DECLARE @TrustedDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_GetTrustedContent', N'P'));
DECLARE @ListDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_List', N'P'));
DECLARE @WatchdogDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetScan_WatchdogTimeout', N'P'));
DECLARE @FinalizeDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(
        N'dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Finalize', N'P'));
DECLARE @OutboxDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge', N'P'));

IF @ApplyDefinition NOT LIKE N'%@ProviderObservedStatus TINYINT = NULL%'
   OR @ApplyDefinition NOT LIKE N'%@ProviderResultCode NVARCHAR(100) = NULL%'
   OR @ApplyDefinition NOT LIKE N'%@TrustedContentHash BINARY(32) = NULL%'
   OR @ApplyDefinition NOT LIKE N'%image-format-rejected%'
   OR @ApplyDefinition NOT LIKE N'%image-decode-rejected%'
   OR @ApplyDefinition NOT LIKE N'%image-frame-count-rejected%'
   OR @ApplyDefinition NOT LIKE N'%image-dimensions-rejected%'
   OR @ApplyDefinition NOT LIKE N'%image-output-too-large%'
   OR @ApplyDefinition NOT LIKE N'%@TrustedMimeType <> @StoredVerifiedMimeType%'
   OR @ApplyDefinition NOT LIKE N'%@TrustedContentLength <> @StoredContentLength%'
   OR @ApplyDefinition NOT LIKE N'%@TrustedContentHash <> @StoredContentHash%'
   OR @ApplyDefinition LIKE N'%@TrustedCreatedAtUtc DATETIME2(3)%'
   OR @TrustedDefinition NOT LIKE N'%TrustedContentHash AS TrustedContentHash%'
   OR @TrustedDefinition NOT LIKE N'%TrustedMimeType AS TrustedMimeType%'
   OR @TrustedDefinition NOT LIKE N'%TrustedCreatedAtUtc AS TrustedCreatedAtUtc%'
   OR @ListDefinition NOT LIKE N'%TrustedProcessingVersion%'
   OR @ListDefinition LIKE N'%TrustedBlobObjectName AS%'
   OR @WatchdogDefinition NOT LIKE N'%TrustedContentHash = NULL%'
   OR @WatchdogDefinition NOT LIKE N'%ProviderObservedStatus%'
   OR @FinalizeDefinition NOT LIKE N'%ProviderObservedStatus = @StoredToStatus%'
   OR @FinalizeDefinition NOT LIKE N'%ProviderResultCode COLLATE Latin1_General_100_BIN2%'
   OR @OutboxDefinition NOT LIKE
      N'%FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre038%'
   OR @OutboxDefinition NOT LIKE N'%ProjectAssetLegacyTrustRevoked%'
   OR @OutboxDefinition NOT LIKE N'%(SELECT COUNT_BIG(1) FROM OPENJSON(messages.PayloadJson)) = 16%'
    THROW 55832, N'Project asset sanitization procedure boundaries drifted.', 1;

IF EXISTS
   (SELECT 1 FROM dbo.FundingPlatform_ProjectAssets
    WHERE StorageStatus = 2 AND ScanStatus = 1 AND Kind = 0
      AND (TrustedProcessingVersion <> N'skia-4.151.2-image-v1'
           OR TrustedContentHash IS NULL OR TrustedMimeType IS NULL
           OR TrustedContentLength IS NULL OR TrustedPixelWidth IS NULL
           OR TrustedPixelHeight IS NULL OR TrustedCreatedAtUtc IS NULL))
   OR EXISTS
   (SELECT 1 FROM dbo.FundingPlatform_ProjectAssets
    WHERE StorageStatus = 2 AND ScanStatus = 1 AND Kind = 1
      AND (TrustedProcessingVersion <> N'pdf-copy-v1'
           OR TrustedContentHash IS NULL OR TrustedMimeType <> N'application/pdf'
           OR TrustedContentLength IS NULL OR TrustedPixelWidth IS NOT NULL
           OR TrustedPixelHeight IS NOT NULL OR TrustedCreatedAtUtc IS NULL))
   OR EXISTS
   (SELECT 1
    FROM dbo.FundingPlatform_ProjectAssetScanEvents AS scanEvents
    WHERE scanEvents.ProviderEventId LIKE N'migration-038-legacy-image:%'
      AND (scanEvents.ResultCode <> N'legacy-image-unsanitized'
           OR scanEvents.RevokedTrustedProcessingVersion <> N'legacy-unsanitized-v0'
           OR scanEvents.RevokedTrustedContentHash IS NULL
           OR NOT EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages AS messages
               WHERE messages.MessageId = scanEvents.EventId
                 AND messages.MessageType = N'ProjectAssetLegacyTrustRevoked')))
    THROW 55833, N'Legacy trusted content was not upgraded fail closed.', 1;

DECLARE @ApiRoleId INT = DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole');
DECLARE @WorkerRoleId INT = DATABASE_PRINCIPAL_ID(N'FundingPlatform_GeneralWorkerRole');
IF @ApiRoleId IS NULL OR @WorkerRoleId IS NULL
   OR EXISTS
      (SELECT 1 FROM sys.database_permissions AS permissions
       WHERE permissions.grantee_principal_id IN (@ApiRoleId, @WorkerRoleId)
         AND permissions.class = 1
         AND permissions.major_id IN
             (OBJECT_ID(N'dbo.FundingPlatform_ProjectAssets', N'U'),
              OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetScanEvents', N'U'),
              OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetDefenderReceipts', N'U'))
         AND permissions.permission_name IN (N'SELECT', N'INSERT', N'UPDATE', N'DELETE')
         AND permissions.state IN (N'G', N'W'))
   OR (SELECT COUNT_BIG(1) FROM sys.database_permissions
       WHERE grantee_principal_id = @ApiRoleId) <> 162
   OR (SELECT COUNT_BIG(1) FROM sys.database_permissions
       WHERE grantee_principal_id = @WorkerRoleId) <> 53
    THROW 55834, N'Project asset sanitization permissions exceed the runtime allowlist.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke038;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @Suffix NVARCHAR(32) =
        REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'');
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @OneSecond DATETIME2(3) = DATEADD(SECOND, 1, @NowUtc);
    DECLARE @TwoSeconds DATETIME2(3) = DATEADD(SECOND, 2, @NowUtc);
    DECLARE @ThreeSeconds DATETIME2(3) = DATEADD(SECOND, 3, @NowUtc);
    DECLARE @FourSeconds DATETIME2(3) = DATEADD(SECOND, 4, @NowUtc);
    DECLARE @UserPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @Email NVARCHAR(320) = N'asset-sanitizer-' + @Suffix + N'@example.invalid';

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@UserPublicId, @Email, UPPER(@Email), N'Asset sanitizer smoke',
         N'not-a-credential', N'asset-sanitizer-smoke', 1, 1, 2, N'es-CL');
    DECLARE @UserId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @UserPublicId);

    DECLARE @Organization TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProfileVersion INT, RowVersion BINARY(8));
    DECLARE @OrganizationSnapshot NVARCHAR(MAX) = N'{"name":"Asset sanitizer smoke"}';
    DECLARE @OrganizationHash BINARY(32) =
        HASHBYTES('SHA2_256', @OrganizationSnapshot);
    INSERT INTO @Organization
    EXEC dbo.FundingPlatform_usp_Organization_CreateForUser
        @UserPublicId = @UserPublicId,
        @Name = N'Asset sanitizer smoke', @HomeCountryId = 152,
        @OrganizationTypeId = 2, @SnapshotJson = @OrganizationSnapshot,
        @ContentHash = @OrganizationHash;
    DECLARE @OrganizationId BIGINT = (SELECT Id FROM @Organization);
    DECLARE @OrganizationPublicId UNIQUEIDENTIFIER =
        (SELECT PublicId FROM @Organization);

    DECLARE @CountryIds dbo.FundingPlatform_SmallIntIdList;
    DECLARE @RegionIds dbo.FundingPlatform_IntIdList;
    DECLARE @CategoryIds dbo.FundingPlatform_IntIdList;
    DECLARE @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList;
    DECLARE @ProjectTypeIds dbo.FundingPlatform_IntIdList;
    INSERT INTO @CountryIds VALUES (152);
    INSERT INTO @RegionIds VALUES (7);
    INSERT INTO @CategoryIds VALUES (1);
    INSERT INTO @BeneficiaryTypeIds VALUES (1);
    INSERT INTO @ProjectTypeIds VALUES (1);
    DECLARE @ProjectSnapshot NVARCHAR(MAX) =
        N'{"title":"Asset sanitizer smoke","projectStage":1,"sustainableDevelopmentGoalIds":[1]}';
    DECLARE @ProjectSlug NVARCHAR(180) = N'asset-sanitizer-' + @Suffix;
    DECLARE @ProjectHash BINARY(32) = HASHBYTES('SHA2_256', @ProjectSnapshot);
    DECLARE @Project TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProjectVersion INT, RowVersion BINARY(8));
    INSERT INTO @Project
    EXEC dbo.FundingPlatform_usp_Project_Create
        @OrganizationPublicId = @OrganizationPublicId,
        @UserPublicId = @UserPublicId,
        @Slug = @ProjectSlug,
        @Title = N'Asset sanitizer smoke',
        @Summary = N'Validación de manifiestos de contenido confiable.',
        @Description = N'Proyecto para probar sanitización y revocación exactas.',
        @ProjectStatus = 2, @StartDate = '2027-01-01', @EndDate = '2027-12-31',
        @BudgetTotal = 100000, @ConfirmedFunding = 10000, @Currency = 'CLP',
        @SnapshotJson = @ProjectSnapshot,
        @ContentHash = @ProjectHash,
        @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds,
        @ProjectStage = 1, @ProjectStageIsSpecified = 1,
        @SustainableDevelopmentGoalIdsJson = N'[1]';
    DECLARE @ProjectId BIGINT = (SELECT Id FROM @Project);
    DECLARE @ProjectPublicId UNIQUEIDENTIFIER = (SELECT PublicId FROM @Project);

    DECLARE @TenantId UNIQUEIDENTIFIER = NEWID();
    DECLARE @PrincipalId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ApplicationId UNIQUEIDENTIFIER = NEWID();
    DECLARE @SubscriptionId UNIQUEIDENTIFIER = NEWID();
    DECLARE @TopicResourceId NVARCHAR(500) =
        N'/subscriptions/' + CONVERT(NVARCHAR(36), @SubscriptionId)
        + N'/resourcegroups/fp-dev/providers/microsoft.eventgrid/systemtopics/assets-sanitize';
    DECLARE @StorageResourceId NVARCHAR(500) =
        N'/subscriptions/' + CONVERT(NVARCHAR(36), @SubscriptionId)
        + N'/resourcegroups/fp-dev/providers/microsoft.storage/storageaccounts/fpassetsdev';
    DECLARE @PolicyPublicId UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.FundingPlatform_EventIngressTrustPolicies
        (PublicId, WorkloadKind, Provider, TenantId, PrincipalObjectId,
         ApplicationClientId, TopicResourceId, EventSubscriptionName,
         StorageAccountResourceId, StorageAccountHost, QuarantineBlobContainer,
         IsEnabled, ValidFromUtc, CreatedByUserId, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@PolicyPublicId, 2, 1, @TenantId, @PrincipalId, @ApplicationId,
         @TopicResourceId, N'project-assets-sanitizer', @StorageResourceId,
         N'fpassetsdev.blob.core.windows.net', N'project-quarantine',
         1, DATEADD(MINUTE, -1, @NowUtc), @UserId, @NowUtc, @NowUtc);
    DECLARE @PolicyId INT =
        (SELECT Id FROM dbo.FundingPlatform_EventIngressTrustPolicies
         WHERE PublicId = @PolicyPublicId);

    DECLARE @ApplyResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), AssetPublicId UNIQUEIDENTIFIER,
        StorageStatus TINYINT NULL, ScanStatus TINYINT NULL, ScanProvider TINYINT NULL,
        AssetRowVersion BINARY(8) NULL, ProjectRowVersion BINARY(8) NULL,
        WasReplay BIT,
        RevokedTrustedBlobContainer NVARCHAR(63) NULL,
        RevokedTrustedBlobObjectName NVARCHAR(1024) NULL,
        RevokedTrustedBlobETag NVARCHAR(100) NULL,
        RevokedTrustedBlobVersionId NVARCHAR(200) NULL,
        RevokedTrustedMimeType NVARCHAR(100) NULL,
        RevokedTrustedContentLength BIGINT NULL,
        RevokedTrustedContentHash BINARY(32) NULL,
        RevokedTrustedPixelWidth INT NULL,
        RevokedTrustedPixelHeight INT NULL,
        RevokedTrustedProcessingVersion NVARCHAR(100) NULL,
        RevokedTrustedCreatedAtUtc DATETIME2(3) NULL
    );

    /* Asset 1: Defender Clean -> sanitized trust -> later Malicious revocation. */
    DECLARE @AssetPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @AssetId BIGINT;
    DECLARE @OriginalHash BINARY(32) = HASHBYTES('SHA2_256', N'original-' + @Suffix);
    DECLARE @TrustedHash BINARY(32) = HASHBYTES('SHA2_256', N'sanitized-' + @Suffix);
    DECLARE @ObjectName NVARCHAR(1024) =
        LOWER(CONVERT(NVARCHAR(36), NEWID())) + N'/' + REPLICATE(N'a', 32) + N'.png';
    DECLARE @QuarantineETag NVARCHAR(100) = N'"q-' + LEFT(@Suffix, 12) + N'"';
    DECLARE @TrustedETag NVARCHAR(100) = N'"t-' + LEFT(@Suffix, 12) + N'"';

    INSERT INTO dbo.FundingPlatform_ProjectAssets
        (PublicId, ProjectId, Kind, OriginalFileName, DisplayName, VerifiedMimeType,
         ContentLength, ContentHash, PixelWidth, PixelHeight,
         QuarantineBlobContainer, QuarantineBlobObjectName,
         QuarantineBlobETag, QuarantineBlobVersionId,
         StorageStatus, ScanStatus, ScanProvider, ScanStartedAtUtc,
         SortOrder, IsCover, IsDeleted, UploadedByUserId, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@AssetPublicId, @ProjectId, 0, N'impacto.png', N'Impacto', N'image/png',
         1024, @OriginalHash, 800, 600,
         N'project-quarantine', @ObjectName, @QuarantineETag, N'quarantine-v1',
         1, 0, 1, @NowUtc, 0, 0, 0, @UserId, @NowUtc, @NowUtc);
    SET @AssetId = SCOPE_IDENTITY();

    INSERT INTO dbo.FundingPlatform_ProjectAssetUploadIntents
        (ProjectId, Kind, OriginalFileName, DeclaredMimeType,
         ExpectedContentLength, MaxContentLength,
         IncomingBlobContainer, IncomingBlobObjectName,
         QuarantineBlobContainer, QuarantineBlobObjectName,
         TrustedBlobContainer, TrustedBlobObjectName,
         CompletionTokenHash, Status, ExpiresAtUtc, FinalizeAttemptCount,
         CompletedProjectAssetId, CompletedAtUtc, UploadedByUserId,
         CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@ProjectId, 0, N'impacto.png', N'image/png', 1024, 10485760,
         N'project-incoming', @ObjectName,
         N'project-quarantine', @ObjectName,
         N'project-trusted', @ObjectName,
         HASHBYTES('SHA2_256', N'completion-1-' + @Suffix), 2,
         DATEADD(MINUTE, 5, @NowUtc), 1, @AssetId, @NowUtc,
         @UserId, @NowUtc, @NowUtc);

    DECLARE @CleanEventId NVARCHAR(200) = N'sanitize-clean-' + @Suffix;
    DECLARE @CleanPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'sanitize-clean-payload-' + @Suffix);
    INSERT INTO dbo.FundingPlatform_ProjectAssetDefenderReceipts
        (TrustPolicyId, WorkloadKind, ProjectAssetId, Provider, ProviderEventId,
         PayloadHash, TopicResourceId, AuthenticatedTenantId,
         AuthenticatedPrincipalId, ApplicationClientId, EventSubscriptionName,
         StorageAccountResourceId, BlobHost, BlobContainer, BlobObjectName,
         BlobETag, ReportedContentHash, ToStatus, ResultCode, ReceiptStatus,
         OccurredAtUtc, ReceivedAtUtc, CreatedAtUtc)
    VALUES
        (@PolicyId, 2, @AssetId, 1, @CleanEventId, @CleanPayloadHash,
         @TopicResourceId, @TenantId, @PrincipalId, @ApplicationId,
         N'project-assets-sanitizer', @StorageResourceId,
         N'fpassetsdev.blob.core.windows.net', N'project-quarantine', @ObjectName,
         @QuarantineETag, @OriginalHash, 1, N'defender-clean', 0,
         @OneSecond, @OneSecond, @NowUtc);

    INSERT INTO @ApplyResult
    EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
        @AssetPublicId = @AssetPublicId, @ScanProvider = 1,
        @ProviderEventId = @CleanEventId, @PayloadHash = @CleanPayloadHash,
        @QuarantineBlobETag = @QuarantineETag,
        @ReportedContentHash = @OriginalHash,
        @ToStatus = 1, @ResultCode = N'defender-clean',
        @OccurredAtUtc = @OneSecond,
        @ProviderObservedStatus = 1, @ProviderResultCode = N'defender-clean',
        @TrustedBlobContainer = N'project-trusted',
        @TrustedBlobObjectName = @ObjectName,
        @TrustedBlobETag = @TrustedETag,
        @TrustedBlobVersionId = N'trusted-v1',
        @TrustedMimeType = N'image/png', @TrustedContentLength = 800,
        @TrustedContentHash = @TrustedHash,
        @TrustedPixelWidth = 640, @TrustedPixelHeight = 480,
        @TrustedProcessingVersion = N'skia-4.151.2-image-v1';

    IF NOT EXISTS
       (SELECT 1 FROM @ApplyResult
        WHERE Succeeded = 1 AND Code = N'scan-result-applied'
          AND StorageStatus = 2 AND ScanStatus = 1 AND WasReplay = 0)
       OR @OriginalHash = @TrustedHash
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssets
           WHERE Id = @AssetId AND ContentHash = @OriginalHash
             AND TrustedContentHash = @TrustedHash
             AND TrustedContentLength = 800
             AND TrustedPixelWidth = 640 AND TrustedPixelHeight = 480
             AND TrustedProcessingVersion = N'skia-4.151.2-image-v1'
             AND TrustedCreatedAtUtc IS NOT NULL)
        THROW 55835, N'Sanitized trusted manifest was not stored separately.', 1;

    DECLARE @TrustedResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), AssetPublicId UNIQUEIDENTIFIER,
        Kind TINYINT NULL, TrustedBlobContainer NVARCHAR(63) NULL,
        TrustedBlobObjectName NVARCHAR(1024) NULL,
        TrustedBlobETag NVARCHAR(100) NULL, TrustedBlobVersionId NVARCHAR(200) NULL,
        TrustedContentHash BINARY(32) NULL, TrustedMimeType NVARCHAR(100) NULL,
        TrustedContentLength BIGINT NULL, TrustedPixelWidth INT NULL,
        TrustedPixelHeight INT NULL, TrustedProcessingVersion NVARCHAR(100) NULL,
        TrustedCreatedAtUtc DATETIME2(3) NULL,
        OriginalFileName NVARCHAR(260) NULL, RowVersion BINARY(8) NULL
    );
    INSERT INTO @TrustedResult
    EXEC dbo.FundingPlatform_usp_ProjectAsset_GetTrustedContent
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @UserPublicId = @UserPublicId,
        @AssetPublicId = @AssetPublicId;
    IF NOT EXISTS
       (SELECT 1 FROM @TrustedResult
        WHERE Succeeded = 1 AND Code = N'trusted'
          AND TrustedContentHash = @TrustedHash
          AND TrustedMimeType = N'image/png' AND TrustedContentLength = 800
          AND TrustedPixelWidth = 640 AND TrustedPixelHeight = 480
          AND TrustedProcessingVersion = N'skia-4.151.2-image-v1'
          AND TrustedCreatedAtUtc IS NOT NULL)
        THROW 55836, N'Trusted read returned original or incomplete metadata.', 1;

    /* A later exact Defender Malicious fact revokes every trusted field and
       returns the immutable manifest needed to delete that exact blob version. */
    DECLARE @MaliciousEventId NVARCHAR(200) = N'sanitize-malicious-' + @Suffix;
    DECLARE @MaliciousPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'sanitize-malicious-payload-' + @Suffix);
    INSERT INTO dbo.FundingPlatform_ProjectAssetDefenderReceipts
        (TrustPolicyId, WorkloadKind, ProjectAssetId, Provider, ProviderEventId,
         PayloadHash, TopicResourceId, AuthenticatedTenantId,
         AuthenticatedPrincipalId, ApplicationClientId, EventSubscriptionName,
         StorageAccountResourceId, BlobHost, BlobContainer, BlobObjectName,
         BlobETag, ReportedContentHash, ToStatus, ResultCode, ReceiptStatus,
         OccurredAtUtc, ReceivedAtUtc, CreatedAtUtc)
    VALUES
        (@PolicyId, 2, @AssetId, 1, @MaliciousEventId, @MaliciousPayloadHash,
         @TopicResourceId, @TenantId, @PrincipalId, @ApplicationId,
         N'project-assets-sanitizer', @StorageResourceId,
         N'fpassetsdev.blob.core.windows.net', N'project-quarantine', @ObjectName,
         @QuarantineETag, @OriginalHash, 2, N'malicious', 0,
         @TwoSeconds, @TwoSeconds, @NowUtc);

    DECLARE @MissingManifestEventId NVARCHAR(200) =
        N'dev-clean-no-manifest-' + @Suffix;
    DELETE FROM @ApplyResult;
    INSERT INTO @ApplyResult
    EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
        @AssetPublicId = @AssetPublicId, @ScanProvider = 1,
        @ProviderEventId = @MaliciousEventId,
        @PayloadHash = @MaliciousPayloadHash,
        @QuarantineBlobETag = @QuarantineETag,
        @ReportedContentHash = @OriginalHash,
        @ToStatus = 2, @ResultCode = N'malicious',
        @OccurredAtUtc = @TwoSeconds,
        @ProviderObservedStatus = 2, @ProviderResultCode = N'malicious';

    DECLARE @RevokedCreatedAtUtc DATETIME2(3) =
        (SELECT RevokedTrustedCreatedAtUtc FROM @ApplyResult WHERE Succeeded = 1);
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyResult
        WHERE Succeeded = 1 AND Code = N'scan-result-superseded'
          AND StorageStatus = 3 AND ScanStatus = 2 AND WasReplay = 0
          AND RevokedTrustedBlobContainer = N'project-trusted'
          AND RevokedTrustedBlobObjectName = @ObjectName
          AND RevokedTrustedBlobETag = @TrustedETag
          AND RevokedTrustedBlobVersionId = N'trusted-v1'
          AND RevokedTrustedMimeType = N'image/png'
          AND RevokedTrustedContentLength = 800
          AND RevokedTrustedContentHash = @TrustedHash
          AND RevokedTrustedPixelWidth = 640
          AND RevokedTrustedPixelHeight = 480
          AND RevokedTrustedProcessingVersion = N'skia-4.151.2-image-v1'
          AND RevokedTrustedCreatedAtUtc IS NOT NULL)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssets
           WHERE Id = @AssetId
             AND (TrustedBlobContainer IS NOT NULL
                  OR TrustedBlobObjectName IS NOT NULL
                  OR TrustedBlobETag IS NOT NULL
                  OR TrustedBlobVersionId IS NOT NULL
                  OR TrustedMimeType IS NOT NULL
                  OR TrustedContentLength IS NOT NULL
                  OR TrustedContentHash IS NOT NULL
                  OR TrustedPixelWidth IS NOT NULL
                  OR TrustedPixelHeight IS NOT NULL
                  OR TrustedProcessingVersion IS NOT NULL
                  OR TrustedCreatedAtUtc IS NOT NULL
                  OR IsCover <> 0))
        THROW 55837, N'Late Defender revocation lost or retained trusted manifest data.', 1;

    DELETE FROM @ApplyResult;
    INSERT INTO @ApplyResult
    EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
        @AssetPublicId = @AssetPublicId, @ScanProvider = 1,
        @ProviderEventId = @MaliciousEventId,
        @PayloadHash = @MaliciousPayloadHash,
        @QuarantineBlobETag = @QuarantineETag,
        @ReportedContentHash = @OriginalHash,
        @ToStatus = 2, @ResultCode = N'malicious',
        @OccurredAtUtc = @TwoSeconds,
        @ProviderObservedStatus = 2, @ProviderResultCode = N'malicious';
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyResult
        WHERE Succeeded = 1 AND Code = N'scan-result-superseded'
          AND WasReplay = 1
          AND RevokedTrustedContentHash = @TrustedHash
          AND RevokedTrustedPixelWidth = 640
          AND RevokedTrustedPixelHeight = 480
          AND RevokedTrustedProcessingVersion = N'skia-4.151.2-image-v1'
          AND RevokedTrustedCreatedAtUtc = @RevokedCreatedAtUtc)
       OR (SELECT COUNT_BIG(1)
           FROM dbo.FundingPlatform_ProjectAssetScanEvents
           WHERE ScanProvider = 1 AND ProviderEventId = @MaliciousEventId) <> 1
        THROW 55838, N'Late revocation replay was not manifest-idempotent.', 1;

    DELETE FROM @ApplyResult;
    INSERT INTO @ApplyResult
    EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
        @AssetPublicId = @AssetPublicId, @ScanProvider = 1,
        @ProviderEventId = @CleanEventId, @PayloadHash = @CleanPayloadHash,
        @QuarantineBlobETag = @QuarantineETag,
        @ReportedContentHash = @OriginalHash,
        @ToStatus = 1, @ResultCode = N'defender-clean',
        @OccurredAtUtc = @OneSecond,
        @ProviderObservedStatus = 1, @ProviderResultCode = N'defender-clean',
        @TrustedBlobContainer = N'project-trusted',
        @TrustedBlobObjectName = @ObjectName,
        @TrustedBlobETag = @TrustedETag,
        @TrustedBlobVersionId = N'trusted-v1',
        @TrustedMimeType = N'image/png', @TrustedContentLength = 800,
        @TrustedContentHash = @TrustedHash,
        @TrustedPixelWidth = 640, @TrustedPixelHeight = 480,
        @TrustedProcessingVersion = N'skia-4.151.2-image-v1';
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyResult
        WHERE Succeeded = 1 AND Code = N'scan-result-applied'
          AND WasReplay = 1 AND StorageStatus = 3 AND ScanStatus = 2)
        THROW 55847, N'Exact Clean replay after revocation was not recognized.', 1;

    DECLARE @TamperedTrustedHash BINARY(32) =
        HASHBYTES('SHA2_256', N'tampered-sanitized-' + @Suffix);
    DELETE FROM @ApplyResult;
    INSERT INTO @ApplyResult
    EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
        @AssetPublicId = @AssetPublicId, @ScanProvider = 1,
        @ProviderEventId = @CleanEventId, @PayloadHash = @CleanPayloadHash,
        @QuarantineBlobETag = @QuarantineETag,
        @ReportedContentHash = @OriginalHash,
        @ToStatus = 1, @ResultCode = N'defender-clean',
        @OccurredAtUtc = @OneSecond,
        @ProviderObservedStatus = 1, @ProviderResultCode = N'defender-clean',
        @TrustedBlobContainer = N'project-trusted',
        @TrustedBlobObjectName = @ObjectName,
        @TrustedBlobETag = @TrustedETag,
        @TrustedBlobVersionId = N'trusted-v1',
        @TrustedMimeType = N'image/png', @TrustedContentLength = 800,
        @TrustedContentHash = @TamperedTrustedHash,
        @TrustedPixelWidth = 640, @TrustedPixelHeight = 480,
        @TrustedProcessingVersion = N'skia-4.151.2-image-v1';
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyResult
        WHERE Succeeded = 0 AND Code = N'provider-event-conflict'
          AND WasReplay = 0)
        THROW 55848, N'Clean replay accepted a manifest not captured at revocation.', 1;

    /* Asset 2: missing trusted data cannot turn a Clean result into trust. The
       same DevelopmentFake observation may derive only an allowlisted failure. */
    DECLARE @DerivedAssetPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @DerivedObject NVARCHAR(1024) =
        LOWER(CONVERT(NVARCHAR(36), NEWID())) + N'/' + REPLICATE(N'b', 32) + N'.png';
    DECLARE @DerivedETag NVARCHAR(100) = N'"d-' + LEFT(@Suffix, 12) + N'"';
    DECLARE @DerivedHash BINARY(32) = HASHBYTES('SHA2_256', N'derived-' + @Suffix);
    INSERT INTO dbo.FundingPlatform_ProjectAssets
        (PublicId, ProjectId, Kind, OriginalFileName, VerifiedMimeType,
         ContentLength, ContentHash, PixelWidth, PixelHeight,
         QuarantineBlobContainer, QuarantineBlobObjectName,
         QuarantineBlobETag, StorageStatus, ScanStatus, ScanProvider,
         ScanStartedAtUtc, SortOrder, IsCover, IsDeleted,
         UploadedByUserId, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@DerivedAssetPublicId, @ProjectId, 0, N'derived.png', N'image/png',
         900, @DerivedHash, 640, 480, N'project-quarantine', @DerivedObject,
         @DerivedETag, 1, 0, 0, @NowUtc, 1, 0, 0,
         @UserId, @NowUtc, @NowUtc);
    DECLARE @DerivedAssetId BIGINT = SCOPE_IDENTITY();
    INSERT INTO dbo.FundingPlatform_ProjectAssetUploadIntents
        (ProjectId, Kind, OriginalFileName, DeclaredMimeType,
         ExpectedContentLength, MaxContentLength,
         IncomingBlobContainer, IncomingBlobObjectName,
         QuarantineBlobContainer, QuarantineBlobObjectName,
         TrustedBlobContainer, TrustedBlobObjectName,
         CompletionTokenHash, Status, ExpiresAtUtc, FinalizeAttemptCount,
         CompletedProjectAssetId, CompletedAtUtc, UploadedByUserId,
         CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@ProjectId, 0, N'derived.png', N'image/png', 900, 10485760,
         N'project-incoming', @DerivedObject,
         N'project-quarantine', @DerivedObject,
         N'project-trusted', @DerivedObject,
         HASHBYTES('SHA2_256', N'completion-2-' + @Suffix), 2,
         DATEADD(MINUTE, 5, @NowUtc), 1, @DerivedAssetId, @NowUtc,
         @UserId, @NowUtc, @NowUtc);

    DELETE FROM @ApplyResult;
    INSERT INTO @ApplyResult
    EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
        @AssetPublicId = @DerivedAssetPublicId, @ScanProvider = 0,
        @ProviderEventId = @MissingManifestEventId,
        @PayloadHash = 0x0101010101010101010101010101010101010101010101010101010101010101,
        @QuarantineBlobETag = @DerivedETag,
        @ReportedContentHash = @DerivedHash,
        @ToStatus = 1, @ResultCode = N'development-clean',
        @OccurredAtUtc = @OneSecond,
        @ProviderObservedStatus = 1, @ProviderResultCode = N'development-clean';
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyResult
        WHERE Succeeded = 0 AND Code = N'invalid-scan-result' AND WasReplay = 0)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssetScanEvents
           WHERE ProjectAssetId = @DerivedAssetId)
        THROW 55839, N'Clean without a trusted manifest did not fail closed.', 1;

    DECLARE @DerivedEventId NVARCHAR(200) = N'dev-derived-' + @Suffix;
    DECLARE @DerivedPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'dev-derived-payload-' + @Suffix);
    DECLARE @NonAllowlistedEventId NVARCHAR(200) =
        N'dev-non-allowlisted-' + @Suffix;
    DELETE FROM @ApplyResult;
    INSERT INTO @ApplyResult
    EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
        @AssetPublicId = @DerivedAssetPublicId, @ScanProvider = 0,
        @ProviderEventId = @DerivedEventId, @PayloadHash = @DerivedPayloadHash,
        @QuarantineBlobETag = @DerivedETag,
        @ReportedContentHash = @DerivedHash,
        @ToStatus = 3, @ResultCode = N'image-decode-rejected',
        @OccurredAtUtc = @OneSecond,
        @ProviderObservedStatus = 1, @ProviderResultCode = N'development-clean';
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyResult
        WHERE Succeeded = 1 AND Code = N'scan-result-applied'
          AND StorageStatus = 3 AND ScanStatus = 3)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssetScanEvents
           WHERE ProjectAssetId = @DerivedAssetId
             AND ToStatus = 3 AND ResultCode = N'image-decode-rejected'
             AND ProviderObservedStatus = 1
             AND ProviderResultCode = N'development-clean')
        THROW 55840, N'Allowlisted DevelopmentFake sanitizer failure was rejected.', 1;

    /* Asset 3: Defender derivation must match the original Clean receipt exactly. */
    DECLARE @DefenderDerivedPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @DefenderDerivedObject NVARCHAR(1024) =
        LOWER(CONVERT(NVARCHAR(36), NEWID())) + N'/' + REPLICATE(N'c', 32) + N'.png';
    DECLARE @DefenderDerivedETag NVARCHAR(100) = N'"r-' + LEFT(@Suffix, 12) + N'"';
    DECLARE @DefenderDerivedHash BINARY(32) =
        HASHBYTES('SHA2_256', N'defender-derived-' + @Suffix);
    INSERT INTO dbo.FundingPlatform_ProjectAssets
        (PublicId, ProjectId, Kind, OriginalFileName, VerifiedMimeType,
         ContentLength, ContentHash, PixelWidth, PixelHeight,
         QuarantineBlobContainer, QuarantineBlobObjectName,
         QuarantineBlobETag, StorageStatus, ScanStatus, ScanProvider,
         ScanStartedAtUtc, SortOrder, IsCover, IsDeleted,
         UploadedByUserId, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@DefenderDerivedPublicId, @ProjectId, 0, N'receipt.png', N'image/png',
         700, @DefenderDerivedHash, 320, 240,
         N'project-quarantine', @DefenderDerivedObject, @DefenderDerivedETag,
         1, 0, 1, @NowUtc, 2, 0, 0, @UserId, @NowUtc, @NowUtc);
    DECLARE @DefenderDerivedId BIGINT = SCOPE_IDENTITY();
    INSERT INTO dbo.FundingPlatform_ProjectAssetUploadIntents
        (ProjectId, Kind, OriginalFileName, DeclaredMimeType,
         ExpectedContentLength, MaxContentLength,
         IncomingBlobContainer, IncomingBlobObjectName,
         QuarantineBlobContainer, QuarantineBlobObjectName,
         TrustedBlobContainer, TrustedBlobObjectName,
         CompletionTokenHash, Status, ExpiresAtUtc, FinalizeAttemptCount,
         CompletedProjectAssetId, CompletedAtUtc, UploadedByUserId,
         CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@ProjectId, 0, N'receipt.png', N'image/png', 700, 10485760,
         N'project-incoming', @DefenderDerivedObject,
         N'project-quarantine', @DefenderDerivedObject,
         N'project-trusted', @DefenderDerivedObject,
         HASHBYTES('SHA2_256', N'completion-3-' + @Suffix), 2,
         DATEADD(MINUTE, 5, @NowUtc), 1, @DefenderDerivedId, @NowUtc,
         @UserId, @NowUtc, @NowUtc);

    DECLARE @DefenderDerivedEventId NVARCHAR(200) = N'defender-derived-' + @Suffix;
    DECLARE @DefenderDerivedPayload BINARY(32) =
        HASHBYTES('SHA2_256', N'defender-derived-payload-' + @Suffix);
    INSERT INTO dbo.FundingPlatform_ProjectAssetDefenderReceipts
        (TrustPolicyId, WorkloadKind, ProjectAssetId, Provider, ProviderEventId,
         PayloadHash, TopicResourceId, AuthenticatedTenantId,
         AuthenticatedPrincipalId, ApplicationClientId, EventSubscriptionName,
         StorageAccountResourceId, BlobHost, BlobContainer, BlobObjectName,
         BlobETag, ReportedContentHash, ToStatus, ResultCode, ReceiptStatus,
         OccurredAtUtc, ReceivedAtUtc, CreatedAtUtc)
    VALUES
        (@PolicyId, 2, @DefenderDerivedId, 1, @DefenderDerivedEventId,
         @DefenderDerivedPayload, @TopicResourceId, @TenantId, @PrincipalId,
         @ApplicationId, N'project-assets-sanitizer', @StorageResourceId,
         N'fpassetsdev.blob.core.windows.net', N'project-quarantine',
         @DefenderDerivedObject, @DefenderDerivedETag, @DefenderDerivedHash,
         1, N'defender-clean', 0, @ThreeSeconds, @ThreeSeconds, @NowUtc);

    DELETE FROM @ApplyResult;
    INSERT INTO @ApplyResult
    EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
        @AssetPublicId = @DefenderDerivedPublicId, @ScanProvider = 1,
        @ProviderEventId = @DefenderDerivedEventId,
        @PayloadHash = @DefenderDerivedPayload,
        @QuarantineBlobETag = @DefenderDerivedETag,
        @ReportedContentHash = @DefenderDerivedHash,
        @ToStatus = 3, @ResultCode = N'image-format-rejected',
        @OccurredAtUtc = @ThreeSeconds,
        @ProviderObservedStatus = 1, @ProviderResultCode = N'wrong-clean-code';
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyResult
        WHERE Succeeded = 0 AND Code = N'defender-receipt-required')
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssetScanEvents
           WHERE ProjectAssetId = @DefenderDerivedId)
        THROW 55841, N'Derived Defender failure bypassed exact receipt matching.', 1;

    DELETE FROM @ApplyResult;
    INSERT INTO @ApplyResult
    EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
        @AssetPublicId = @DefenderDerivedPublicId, @ScanProvider = 1,
        @ProviderEventId = @DefenderDerivedEventId,
        @PayloadHash = @DefenderDerivedPayload,
        @QuarantineBlobETag = @DefenderDerivedETag,
        @ReportedContentHash = @DefenderDerivedHash,
        @ToStatus = 3, @ResultCode = N'image-format-rejected',
        @OccurredAtUtc = @ThreeSeconds,
        @ProviderObservedStatus = 1, @ProviderResultCode = N'defender-clean';
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyResult
        WHERE Succeeded = 1 AND Code = N'scan-result-applied'
          AND StorageStatus = 3 AND ScanStatus = 3)
        THROW 55842, N'Exact allowlisted Defender sanitizer failure was rejected.', 1;

    DECLARE @DefenderDerivedReceiptPublicId UNIQUEIDENTIFIER =
        (SELECT PublicId
         FROM dbo.FundingPlatform_ProjectAssetDefenderReceipts
         WHERE Provider = 1 AND ProviderEventId = @DefenderDerivedEventId);
    DECLARE @FinalizeResult TABLE
    (
        Succeeded BIT,
        Code NVARCHAR(50),
        ReceiptStatus TINYINT,
        WasReplay BIT
    );
    INSERT INTO @FinalizeResult
    EXEC dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Finalize
        @ReceiptPublicId = @DefenderDerivedReceiptPublicId,
        @PayloadHash = @DefenderDerivedPayload,
        @Applied = 1,
        @OutcomeCode = N'scan-result-applied',
        @FinalizedAtUtc = @FourSeconds;
    IF NOT EXISTS
       (SELECT 1 FROM @FinalizeResult
        WHERE Succeeded = 1 AND Code = N'applied'
          AND ReceiptStatus = 1 AND WasReplay = 0)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssetDefenderReceipts
           WHERE PublicId = @DefenderDerivedReceiptPublicId
             AND ReceiptStatus = 1 AND OutcomeCode = N'scan-result-applied'
             AND FinalizedAtUtc = @FourSeconds)
        THROW 55849, N'Derived Defender result did not finalize its Clean receipt.', 1;

    DELETE FROM @FinalizeResult;
    INSERT INTO @FinalizeResult
    EXEC dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Finalize
        @ReceiptPublicId = @DefenderDerivedReceiptPublicId,
        @PayloadHash = @DefenderDerivedPayload,
        @Applied = 1,
        @OutcomeCode = N'scan-result-applied',
        @FinalizedAtUtc = @FourSeconds;
    IF NOT EXISTS
       (SELECT 1 FROM @FinalizeResult
        WHERE Succeeded = 1 AND Code = N'replayed'
          AND ReceiptStatus = 1 AND WasReplay = 1)
        THROW 55850, N'Derived Defender receipt finalization was not idempotent.', 1;

    /* Only the five enumerated sanitizer failures may differ from the observed status. */
    DECLARE @RejectedPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @RejectedObject NVARCHAR(1024) =
        LOWER(CONVERT(NVARCHAR(36), NEWID())) + N'/' + REPLICATE(N'd', 32) + N'.png';
    DECLARE @RejectedETag NVARCHAR(100) = N'"x-' + LEFT(@Suffix, 12) + N'"';
    DECLARE @RejectedHash BINARY(32) = HASHBYTES('SHA2_256', N'rejected-' + @Suffix);
    INSERT INTO dbo.FundingPlatform_ProjectAssets
        (PublicId, ProjectId, Kind, OriginalFileName, VerifiedMimeType,
         ContentLength, ContentHash, PixelWidth, PixelHeight,
         QuarantineBlobContainer, QuarantineBlobObjectName, QuarantineBlobETag,
         StorageStatus, ScanStatus, ScanProvider, ScanStartedAtUtc,
         SortOrder, IsCover, IsDeleted, UploadedByUserId, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@RejectedPublicId, @ProjectId, 0, N'rejected.png', N'image/png',
         600, @RejectedHash, 320, 240, N'project-quarantine', @RejectedObject,
         @RejectedETag, 1, 0, 0, @NowUtc, 3, 0, 0, @UserId, @NowUtc, @NowUtc);
    DECLARE @RejectedId BIGINT = SCOPE_IDENTITY();
    DELETE FROM @ApplyResult;
    INSERT INTO @ApplyResult
    EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
        @AssetPublicId = @RejectedPublicId, @ScanProvider = 0,
        @ProviderEventId = @NonAllowlistedEventId,
        @PayloadHash = 0x0202020202020202020202020202020202020202020202020202020202020202,
        @QuarantineBlobETag = @RejectedETag,
        @ReportedContentHash = @RejectedHash,
        @ToStatus = 3, @ResultCode = N'image-policy-rejected',
        @OccurredAtUtc = @OneSecond,
        @ProviderObservedStatus = 1, @ProviderResultCode = N'development-clean';
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyResult
        WHERE Succeeded = 0 AND Code = N'invalid-scan-result')
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssetScanEvents
           WHERE ProjectAssetId = @RejectedId)
        THROW 55843, N'Non-allowlisted derived failure was accepted.', 1;

    /* PDF trust is an exact byte copy: unlike image re-encoding, its trusted
       hash and length may never diverge from the immutable original manifest. */
    DECLARE @PdfPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @PdfObject NVARCHAR(1024) =
        LOWER(CONVERT(NVARCHAR(36), NEWID())) + N'/' + REPLICATE(N'f', 32) + N'.pdf';
    DECLARE @PdfQuarantineETag NVARCHAR(100) = N'"pq-' + LEFT(@Suffix, 12) + N'"';
    DECLARE @PdfTrustedETag NVARCHAR(100) = N'"pt-' + LEFT(@Suffix, 12) + N'"';
    DECLARE @PdfHash BINARY(32) = HASHBYTES('SHA2_256', N'pdf-' + @Suffix);
    DECLARE @WrongPdfHash BINARY(32) = HASHBYTES('SHA2_256', N'wrong-pdf-' + @Suffix);
    INSERT INTO dbo.FundingPlatform_ProjectAssets
        (PublicId, ProjectId, Kind, OriginalFileName, VerifiedMimeType,
         ContentLength, ContentHash, PixelWidth, PixelHeight,
         QuarantineBlobContainer, QuarantineBlobObjectName, QuarantineBlobETag,
         StorageStatus, ScanStatus, ScanProvider, ScanStartedAtUtc,
         SortOrder, IsCover, IsDeleted, UploadedByUserId, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@PdfPublicId, @ProjectId, 1, N'evidencia.pdf', N'application/pdf',
         1200, @PdfHash, NULL, NULL, N'project-quarantine', @PdfObject,
         @PdfQuarantineETag, 1, 0, 0, @NowUtc, 5, 0, 0,
         @UserId, @NowUtc, @NowUtc);
    DECLARE @PdfId BIGINT = SCOPE_IDENTITY();
    INSERT INTO dbo.FundingPlatform_ProjectAssetUploadIntents
        (ProjectId, Kind, OriginalFileName, DeclaredMimeType,
         ExpectedContentLength, MaxContentLength,
         IncomingBlobContainer, IncomingBlobObjectName,
         QuarantineBlobContainer, QuarantineBlobObjectName,
         TrustedBlobContainer, TrustedBlobObjectName,
         CompletionTokenHash, Status, ExpiresAtUtc, FinalizeAttemptCount,
         CompletedProjectAssetId, CompletedAtUtc, UploadedByUserId,
         CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@ProjectId, 1, N'evidencia.pdf', N'application/pdf', 1200, 26214400,
         N'project-incoming', @PdfObject,
         N'project-quarantine', @PdfObject,
         N'project-trusted', @PdfObject,
         HASHBYTES('SHA2_256', N'completion-pdf-' + @Suffix), 2,
         DATEADD(MINUTE, 5, @NowUtc), 1, @PdfId, @NowUtc,
         @UserId, @NowUtc, @NowUtc);
    DECLARE @PdfEventId NVARCHAR(200) = N'dev-pdf-copy-' + @Suffix;
    DECLARE @PdfPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'dev-pdf-copy-payload-' + @Suffix);

    DELETE FROM @ApplyResult;
    INSERT INTO @ApplyResult
    EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
        @AssetPublicId = @PdfPublicId, @ScanProvider = 0,
        @ProviderEventId = @PdfEventId, @PayloadHash = @PdfPayloadHash,
        @QuarantineBlobETag = @PdfQuarantineETag,
        @ReportedContentHash = @PdfHash,
        @ToStatus = 1, @ResultCode = N'development-clean',
        @OccurredAtUtc = @OneSecond,
        @TrustedBlobContainer = N'project-trusted',
        @TrustedBlobObjectName = @PdfObject,
        @TrustedBlobETag = @PdfTrustedETag,
        @TrustedMimeType = N'application/pdf',
        @TrustedContentLength = 1199, @TrustedContentHash = @WrongPdfHash,
        @TrustedPixelWidth = NULL, @TrustedPixelHeight = NULL,
        @TrustedProcessingVersion = N'pdf-copy-v1';
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyResult
        WHERE Succeeded = 0 AND Code = N'invalid-trusted-manifest')
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssetScanEvents
           WHERE ProjectAssetId = @PdfId)
        THROW 55845, N'Changed PDF bytes were accepted as an exact trusted copy.', 1;

    DELETE FROM @ApplyResult;
    INSERT INTO @ApplyResult
    EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
        @AssetPublicId = @PdfPublicId, @ScanProvider = 0,
        @ProviderEventId = @PdfEventId, @PayloadHash = @PdfPayloadHash,
        @QuarantineBlobETag = @PdfQuarantineETag,
        @ReportedContentHash = @PdfHash,
        @ToStatus = 1, @ResultCode = N'development-clean',
        @OccurredAtUtc = @OneSecond,
        @TrustedBlobContainer = N'project-trusted',
        @TrustedBlobObjectName = @PdfObject,
        @TrustedBlobETag = @PdfTrustedETag,
        @TrustedMimeType = N'application/pdf',
        @TrustedContentLength = 1200, @TrustedContentHash = @PdfHash,
        @TrustedPixelWidth = NULL, @TrustedPixelHeight = NULL,
        @TrustedProcessingVersion = N'pdf-copy-v1';
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyResult
        WHERE Succeeded = 1 AND Code = N'scan-result-applied'
          AND StorageStatus = 2 AND ScanStatus = 1)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssets
           WHERE Id = @PdfId AND TrustedContentLength = ContentLength
             AND TrustedContentHash = ContentHash
             AND TrustedProcessingVersion = N'pdf-copy-v1')
        THROW 55846, N'Exact PDF copy manifest was not trusted.', 1;

    /* Synthetic historical row verifies the exact legacy audit schema that the
       data-upgrade batch emits when an old raw trusted image is invalidated. */
    DECLARE @LegacyAssetPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @LegacyObject NVARCHAR(1024) =
        LOWER(CONVERT(NVARCHAR(36), NEWID())) + N'/' + REPLICATE(N'e', 32) + N'.png';
    DECLARE @LegacyQuarantineETag NVARCHAR(100) = N'"lq-' + LEFT(@Suffix, 12) + N'"';
    DECLARE @LegacyTrustedETag NVARCHAR(100) = N'"lt-' + LEFT(@Suffix, 12) + N'"';
    DECLARE @LegacyHash BINARY(32) = HASHBYTES('SHA2_256', N'legacy-' + @Suffix);
    INSERT INTO dbo.FundingPlatform_ProjectAssets
        (PublicId, ProjectId, Kind, OriginalFileName, VerifiedMimeType,
         ContentLength, ContentHash, PixelWidth, PixelHeight,
         QuarantineBlobContainer, QuarantineBlobObjectName,
         QuarantineBlobETag, QuarantineBlobVersionId,
         StorageStatus, ScanStatus, ScanProvider, ScanResultCode,
         ScanStartedAtUtc, ScanCompletedAtUtc,
         SortOrder, IsCover, IsDeleted, UploadedByUserId, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@LegacyAssetPublicId, @ProjectId, 0, N'legacy.png', N'image/png',
         500, @LegacyHash, 100, 80, N'project-quarantine', @LegacyObject,
         @LegacyQuarantineETag, N'legacy-quarantine-v1',
         3, 3, 0, N'legacy-image-unsanitized', @NowUtc, @NowUtc,
         4, 0, 0, @UserId, @NowUtc, @NowUtc);
    DECLARE @LegacyAssetId BIGINT = SCOPE_IDENTITY();
    DECLARE @LegacyRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_ProjectAssets
         WHERE Id = @LegacyAssetId);
    DECLARE @LegacyEventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @LegacyProviderEventId NVARCHAR(200) =
        N'migration-038-legacy-image:' + CONVERT(NVARCHAR(36), @LegacyAssetPublicId);

    INSERT INTO dbo.FundingPlatform_ProjectAssetScanEvents
        (EventId, ProjectAssetId, ScanProvider, ProviderEventId,
         PayloadHash, FromStatus, ToStatus, ProviderObservedStatus,
         QuarantineBlobETag, ReportedContentHash,
         ResultCode, ProviderResultCode, ResultRowVersion,
         OccurredAtUtc, CreatedAtUtc,
         RevokedTrustedBlobContainer, RevokedTrustedBlobObjectName,
         RevokedTrustedBlobETag, RevokedTrustedBlobVersionId,
         RevokedTrustedMimeType, RevokedTrustedContentLength,
         RevokedTrustedContentHash, RevokedTrustedPixelWidth,
         RevokedTrustedPixelHeight, RevokedTrustedProcessingVersion,
         RevokedTrustedCreatedAtUtc)
    VALUES
        (@LegacyEventId, @LegacyAssetId, 0, @LegacyProviderEventId,
         HASHBYTES('SHA2_256', @LegacyProviderEventId), 1, 3, 1,
         @LegacyQuarantineETag, @LegacyHash,
         N'legacy-image-unsanitized', N'development-clean',
         @LegacyRowVersion, @NowUtc, @NowUtc,
         N'project-trusted', @LegacyObject, @LegacyTrustedETag, NULL,
         N'image/png', 500, @LegacyHash, 100, 80,
         N'legacy-unsanitized-v0', @NowUtc);

    INSERT INTO dbo.FundingPlatform_OutboxMessages
        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
         OccurredAtUtc, AvailableAtUtc)
    SELECT @LegacyEventId, N'ProjectAssetLegacyTrustRevoked', N'ProjectAsset',
           CONVERT(NVARCHAR(100), @LegacyAssetPublicId),
           (SELECT @LegacyEventId AS eventId,
                   @LegacyAssetPublicId AS assetPublicId,
                   CAST(3 AS TINYINT) AS scanStatus,
                   CAST(3 AS TINYINT) AS storageStatus,
                   N'legacy-image-unsanitized' AS resultCode,
                   N'project-trusted' AS revokedTrustedBlobContainer,
                   @LegacyObject AS revokedTrustedBlobObjectName,
                   @LegacyTrustedETag AS revokedTrustedBlobETag,
                   CAST(NULL AS NVARCHAR(200)) AS revokedTrustedBlobVersionId,
                   N'image/png' AS revokedTrustedMimeType,
                   CAST(500 AS BIGINT) AS revokedTrustedContentLength,
                   CONVERT(VARCHAR(64), @LegacyHash, 2)
                       AS revokedTrustedContentHashSha256,
                   CAST(100 AS INT) AS revokedTrustedPixelWidth,
                   CAST(80 AS INT) AS revokedTrustedPixelHeight,
                   N'legacy-unsanitized-v0' AS revokedTrustedProcessingVersion,
                   @NowUtc AS revokedTrustedCreatedAtUtc
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
           @NowUtc, @NowUtc;

    DECLARE @MalformedMessageId UNIQUEIDENTIFIER = NEWID();
    DECLARE @MalformedProviderEventId NVARCHAR(200) = @LegacyProviderEventId + N':duplicate';
    INSERT INTO dbo.FundingPlatform_ProjectAssetScanEvents
        (EventId, ProjectAssetId, ScanProvider, ProviderEventId,
         PayloadHash, FromStatus, ToStatus, ProviderObservedStatus,
         QuarantineBlobETag, ReportedContentHash,
         ResultCode, ProviderResultCode, ResultRowVersion,
         OccurredAtUtc, CreatedAtUtc,
         RevokedTrustedBlobContainer, RevokedTrustedBlobObjectName,
         RevokedTrustedBlobETag, RevokedTrustedBlobVersionId,
         RevokedTrustedMimeType, RevokedTrustedContentLength,
         RevokedTrustedContentHash, RevokedTrustedPixelWidth,
         RevokedTrustedPixelHeight, RevokedTrustedProcessingVersion,
         RevokedTrustedCreatedAtUtc)
    VALUES
        (@MalformedMessageId, @LegacyAssetId, 0, @MalformedProviderEventId,
         HASHBYTES('SHA2_256', @MalformedProviderEventId), 1, 3, 1,
         @LegacyQuarantineETag, @LegacyHash,
         N'legacy-image-unsanitized', N'development-clean',
         @LegacyRowVersion, @NowUtc, @NowUtc,
         N'project-trusted', @LegacyObject, @LegacyTrustedETag, NULL,
         N'image/png', 500, @LegacyHash, 100, 80,
         N'legacy-unsanitized-v0', @NowUtc);

    DECLARE @MalformedPayload NVARCHAR(MAX) =
        (SELECT PayloadJson FROM dbo.FundingPlatform_OutboxMessages
         WHERE MessageId = @LegacyEventId);
    SET @MalformedPayload = JSON_MODIFY
        (@MalformedPayload, N'$.eventId', CONVERT(NVARCHAR(36), @MalformedMessageId));
    /* Lax JSON_MODIFY removes the nullable key; append a duplicate allowed key
       so the object still has sixteen members and tests per-key uniqueness. */
    SET @MalformedPayload = JSON_MODIFY
        (@MalformedPayload, N'$.revokedTrustedBlobVersionId', NULL);
    SET @MalformedPayload = LEFT(@MalformedPayload, LEN(@MalformedPayload) - 1)
        + N',"resultCode":"legacy-image-unsanitized"}';
    INSERT INTO dbo.FundingPlatform_OutboxMessages
        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
         OccurredAtUtc, AvailableAtUtc)
    VALUES
        (@MalformedMessageId, N'ProjectAssetLegacyTrustRevoked', N'ProjectAsset',
         CONVERT(NVARCHAR(100), @LegacyAssetPublicId), @MalformedPayload,
         @NowUtc, @NowUtc);

    DECLARE @Acknowledged INT = 0, @Attempt INT = 0;
    WHILE @Attempt < 20
          AND NOT EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
               WHERE MessageId = @LegacyEventId AND DispatchedAtUtc IS NOT NULL)
    BEGIN
        EXEC dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge
            @BatchSize = 500, @NowUtc = @ThreeSeconds,
            @AcknowledgedCount = @Acknowledged OUTPUT;
        SET @Attempt += 1;
        IF @Acknowledged = 0 BREAK;
    END;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
        WHERE MessageId = @LegacyEventId AND DispatchedAtUtc IS NOT NULL
          AND LastError = N'event-ledger-acknowledged')
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
           WHERE MessageId = @MalformedMessageId AND DispatchedAtUtc IS NOT NULL)
        THROW 55844, N'Legacy revocation audit sink was not exact and fail closed.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke038;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FP_Smoke038;
    THROW;
END CATCH;

SELECT N'038 project asset image sanitization smoke passed.' AS Result;
