/* Transactional smoke for migration 037: authenticated project-asset Defender pipeline. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetDefenderReceipts', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Record', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Finalize', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetScan_WatchdogTimeout', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre037', N'P') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_EventIngressTrustPolicies', N'WorkloadKind') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_ProjectAssetScanEvents',
                 N'RevokedTrustedBlobObjectName') IS NULL
    THROW 55730, N'Project asset Defender persistence contract is missing.', 1;

IF COL_LENGTH(N'dbo.FundingPlatform_ProjectAssetDefenderReceipts', N'PayloadJson') IS NOT NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_ProjectAssetDefenderReceipts', N'MalwareName') IS NOT NULL
   OR NOT EXISTS
      (SELECT 1 FROM sys.check_constraints
       WHERE parent_object_id =
             OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetDefenderReceipts', N'U')
         AND name = N'FundingPlatform_CK_ProjectAssetDefenderReceipts_Provider')
   OR NOT EXISTS
      (SELECT 1 FROM sys.check_constraints
       WHERE parent_object_id =
             OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetScanEvents', N'U')
         AND name = N'FundingPlatform_CK_ProjectAssetScanEvents_Status'
         AND definition LIKE N'%FromStatus%=%(1)%')
    THROW 55731, N'Defender receipt minimization or scan-transition constraints drifted.', 1;

DECLARE @UpsertDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_EventIngressTrustPolicy_Upsert', N'P'));
DECLARE @SourceReceiptDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Record', N'P'));
DECLARE @ProjectReceiptDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Record', N'P'));
DECLARE @ApplyDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult', N'P'));
DECLARE @WatchdogDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetScan_WatchdogTimeout', N'P'));
DECLARE @OutboxAuditDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge', N'P'));
IF OBJECT_ID(N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre038', N'P') IS NOT NULL
BEGIN
    IF CHARINDEX(N'EXEC dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre038', @OutboxAuditDefinition) = 0
        THROW 55732, N'Current audit sink does not delegate to the asset sink.', 1;
    SET @OutboxAuditDefinition += OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre038'));
END;

IF @UpsertDefinition NOT LIKE N'%@WorkloadKind TINYINT%'
   OR @UpsertDefinition NOT LIKE N'%WorkloadKind = @WorkloadKind%'
   OR @UpsertDefinition NOT LIKE N'%identity is immutable%'
   OR @SourceReceiptDefinition NOT LIKE N'%WHERE WorkloadKind = 1 AND Provider = 1%'
   OR @ProjectReceiptDefinition NOT LIKE N'%WHERE WorkloadKind = 2 AND Provider = 1%'
   OR @ApplyDefinition NOT LIKE N'%@ReportedContentHash BINARY(32) = NULL%'
   OR @ApplyDefinition NOT LIKE N'%@StoredStorageStatus = 2%'
   OR @ApplyDefinition NOT LIKE N'%IsCover = 0%'
   OR @ApplyDefinition NOT LIKE N'%ProjectAssetScanTrustRevoked%'
   OR @ApplyDefinition NOT LIKE N'%ProjectAssetDefenderReceipts%'
   OR @ApplyDefinition NOT LIKE N'%@ScanProvider = 1 AND @TrustedBlobVersionId IS NULL%'
   OR @WatchdogDefinition NOT LIKE N'%assets.ScanProvider = 1%'
   OR @WatchdogDefinition NOT LIKE N'%assets.ScanStatus = 0%'
   OR @OutboxAuditDefinition NOT LIKE N'%FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre037%'
   OR @OutboxAuditDefinition NOT LIKE N'%ProjectAssetUploadIntentCreated%'
   OR @OutboxAuditDefinition NOT LIKE N'%ProjectAssetUploadIntentRejected%'
   OR @OutboxAuditDefinition NOT LIKE N'%ProjectAssetFinalized%'
   OR @OutboxAuditDefinition NOT LIKE N'%ProjectAssetQuarantined%'
   OR @OutboxAuditDefinition NOT LIKE N'%ProjectAssetScanCompleted%'
   OR @OutboxAuditDefinition NOT LIKE N'%ProjectAssetMetadataUpdated%'
   OR @OutboxAuditDefinition NOT LIKE N'%ProjectAssetsReordered%'
   OR @OutboxAuditDefinition NOT LIKE N'%ProjectAssetDeleted%'
   OR @OutboxAuditDefinition NOT LIKE N'%ProjectAssetScanTrustRevoked%'
   OR @OutboxAuditDefinition NOT LIKE N'%ProjectAssetScanTimedOut%'
   OR @OutboxAuditDefinition LIKE N'%JSON_VALUE(messages.PayloadJson, N''$.version'')%'
    THROW 55732, N'Defender procedure boundaries drifted.', 1;

DECLARE @ApiRoleId INT = DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole');
DECLARE @WorkerRoleId INT = DATABASE_PRINCIPAL_ID(N'FundingPlatform_GeneralWorkerRole');
DECLARE @WorkerProcedures TABLE (ObjectId INT NOT NULL PRIMARY KEY);
INSERT INTO @WorkerProcedures (ObjectId)
SELECT OBJECT_ID(required.Name, N'P')
FROM (VALUES
    (N'dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Record'),
    (N'dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Finalize'),
    (N'dbo.FundingPlatform_usp_ProjectAssetScan_WatchdogTimeout')
) AS required(Name);

IF @ApiRoleId IS NULL OR @WorkerRoleId IS NULL
   OR (SELECT COUNT_BIG(1) FROM @WorkerProcedures) <> 3
   OR EXISTS
      (SELECT 1 FROM @WorkerProcedures AS required
       WHERE NOT EXISTS
             (SELECT 1 FROM sys.database_permissions AS permissions
              WHERE permissions.grantee_principal_id = @WorkerRoleId
                AND permissions.class = 1 AND permissions.major_id = required.ObjectId
                AND permissions.permission_name = N'EXECUTE'
                AND permissions.state IN (N'G', N'W')))
   OR EXISTS
      (SELECT 1 FROM @WorkerProcedures AS forbidden
       INNER JOIN sys.database_permissions AS permissions
           ON permissions.major_id = forbidden.ObjectId
       WHERE permissions.grantee_principal_id = @ApiRoleId
         AND permissions.class = 1 AND permissions.permission_name = N'EXECUTE'
         AND permissions.state IN (N'G', N'W'))
   OR (SELECT COUNT_BIG(1) FROM sys.database_permissions
       WHERE grantee_principal_id = @ApiRoleId) <> 162
       + CASE WHEN OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMap_Search', N'P') IS NULL THEN 0 ELSE 1 END
       + CASE WHEN OBJECT_ID(N'dbo.FundingPlatform_FunderWorkspaceOwners', N'U') IS NULL THEN 0 ELSE 1 END
       + CASE WHEN OBJECT_ID(N'dbo.FundingPlatform_Consortia', N'U') IS NULL THEN 0 ELSE 9 END
       + CASE WHEN OBJECT_ID(N'dbo.FundingPlatform_usp_DiscoveryMatching_Context', N'P') IS NULL THEN 0 ELSE 1 END
       + CASE WHEN OBJECT_ID(N'dbo.FundingPlatform_FundingDiscovery', N'U') IS NULL THEN 0 ELSE 3 END
   OR (SELECT COUNT_BIG(1) FROM sys.database_permissions
       WHERE grantee_principal_id = @WorkerRoleId) <> 53 +
       CASE WHEN OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetContentRetentionTasks', N'U') IS NULL THEN 0 ELSE 3 END
    THROW 55733, N'Project asset Defender permissions exceed the worker-only allowlist.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke037;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @Suffix NVARCHAR(32) =
        REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'');
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @OneSecond DATETIME2(3) = DATEADD(SECOND, 1, @NowUtc);
    DECLARE @TwoSeconds DATETIME2(3) = DATEADD(SECOND, 2, @NowUtc);
    DECLARE @ThreeSeconds DATETIME2(3) = DATEADD(SECOND, 3, @NowUtc);
    DECLARE @FourSeconds DATETIME2(3) = DATEADD(SECOND, 4, @NowUtc);
    DECLARE @AdminPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @AdminEmail NVARCHAR(320) = N'asset-defender-' + @Suffix + N'@example.invalid';

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@AdminPublicId, @AdminEmail, UPPER(@AdminEmail),
         N'Project asset Defender smoke', N'not-a-credential', N'asset-defender-smoke',
         1, 1, 2, N'es-CL');
    DECLARE @AdminUserId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @AdminPublicId);
    DECLARE @SuperAdminRoleId SMALLINT =
        (SELECT Id FROM dbo.FundingPlatform_Roles WHERE NormalizedName = N'SUPERADMIN');
    IF @SuperAdminRoleId IS NULL
        THROW 55734, N'SuperAdmin fixture role is missing.', 1;
    INSERT INTO dbo.FundingPlatform_UserRoles (UserId, RoleId, GrantedByUserId)
    VALUES (@AdminUserId, @SuperAdminRoleId, @AdminUserId);

    DECLARE @TenantId UNIQUEIDENTIFIER = NEWID();
    DECLARE @PrincipalId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ApplicationId UNIQUEIDENTIFIER = NEWID();
    DECLARE @SubscriptionId UNIQUEIDENTIFIER = NEWID();
    DECLARE @TopicResourceId NVARCHAR(500) =
        N'/subscriptions/' + CONVERT(NVARCHAR(36), @SubscriptionId)
        + N'/resourcegroups/fp-dev/providers/microsoft.eventgrid/systemtopics/assets-smoke';
    DECLARE @StorageResourceId NVARCHAR(500) =
        N'/subscriptions/' + CONVERT(NVARCHAR(36), @SubscriptionId)
        + N'/resourcegroups/fp-dev/providers/microsoft.storage/storageaccounts/fpassetsdev';
    DECLARE @StorageHost NVARCHAR(253) = N'fpassetsdev.blob.core.windows.net';
    DECLARE @QuarantineContainer NVARCHAR(63) = N'project-quarantine';
    DECLARE @SubscriptionName NVARCHAR(100) = N'project-assets-defender';
    DECLARE @PolicyValidFromUtc DATETIME2(3) = DATEADD(MINUTE, -1, @NowUtc);
    DECLARE @SourcePolicyIdempotency BINARY(32) =
        HASHBYTES('SHA2_256', N'source-policy-' + @Suffix);
    DECLARE @SourcePolicyRequest BINARY(32) =
        HASHBYTES('SHA2_256', N'source-policy-request-' + @Suffix);
    DECLARE @AssetPolicyIdempotency BINARY(32) =
        HASHBYTES('SHA2_256', N'asset-policy-' + @Suffix);
    DECLARE @AssetPolicyRequest BINARY(32) =
        HASHBYTES('SHA2_256', N'asset-policy-request-' + @Suffix);
    DECLARE @TrustResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), PolicyPublicId UNIQUEIDENTIFIER NULL,
        IsEnabled BIT NULL, RowVersion BINARY(8) NULL, WasReplay BIT
    );

    INSERT INTO @TrustResult
    EXEC dbo.FundingPlatform_usp_EventIngressTrustPolicy_Upsert
        @SuperAdminUserPublicId = @AdminPublicId,
        @PolicyPublicId = NULL, @ExpectedRowVersion = NULL, @WorkloadKind = 1,
        @TenantId = @TenantId, @PrincipalObjectId = @PrincipalId,
        @ApplicationClientId = @ApplicationId,
        @ExpectedTopicResourceId = @TopicResourceId,
        @EventSubscriptionName = @SubscriptionName,
        @StorageAccountResourceId = @StorageResourceId,
        @StorageAccountHost = @StorageHost,
        @QuarantineBlobContainer = @QuarantineContainer,
        @IsEnabled = 1, @ValidFromUtc = @PolicyValidFromUtc,
        @ExpiresAtUtc = NULL, @Reason = N'Source-document coexistence fixture.',
        @IdempotencyKeyHash = @SourcePolicyIdempotency,
        @RequestHash = @SourcePolicyRequest,
        @CorrelationId = N'smoke037-source-policy', @NowUtc = @NowUtc;
    DECLARE @SourcePolicyPublicId UNIQUEIDENTIFIER =
        (SELECT PolicyPublicId FROM @TrustResult WHERE Succeeded = 1);

    DELETE FROM @TrustResult;
    INSERT INTO @TrustResult
    EXEC dbo.FundingPlatform_usp_EventIngressTrustPolicy_Upsert
        @SuperAdminUserPublicId = @AdminPublicId,
        @PolicyPublicId = NULL, @ExpectedRowVersion = NULL, @WorkloadKind = 2,
        @TenantId = @TenantId, @PrincipalObjectId = @PrincipalId,
        @ApplicationClientId = @ApplicationId,
        @ExpectedTopicResourceId = @TopicResourceId,
        @EventSubscriptionName = @SubscriptionName,
        @StorageAccountResourceId = @StorageResourceId,
        @StorageAccountHost = @StorageHost,
        @QuarantineBlobContainer = @QuarantineContainer,
        @IsEnabled = 1, @ValidFromUtc = @PolicyValidFromUtc,
        @ExpiresAtUtc = NULL, @Reason = N'Cross-workload replay must fail closed.',
        @IdempotencyKeyHash = @SourcePolicyIdempotency,
        @RequestHash = @SourcePolicyRequest,
        @CorrelationId = N'smoke037-cross-workload', @NowUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @TrustResult
        WHERE Succeeded = 0 AND Code = N'idempotency-conflict'
          AND PolicyPublicId IS NULL AND WasReplay = 0)
        THROW 55735, N'Cross-workload trust-policy idempotency replay was accepted.', 1;

    DELETE FROM @TrustResult;
    INSERT INTO @TrustResult
    EXEC dbo.FundingPlatform_usp_EventIngressTrustPolicy_Upsert
        @SuperAdminUserPublicId = @AdminPublicId,
        @PolicyPublicId = NULL, @ExpectedRowVersion = NULL, @WorkloadKind = 2,
        @TenantId = @TenantId, @PrincipalObjectId = @PrincipalId,
        @ApplicationClientId = @ApplicationId,
        @ExpectedTopicResourceId = @TopicResourceId,
        @EventSubscriptionName = @SubscriptionName,
        @StorageAccountResourceId = @StorageResourceId,
        @StorageAccountHost = @StorageHost,
        @QuarantineBlobContainer = @QuarantineContainer,
        @IsEnabled = 1, @ValidFromUtc = @PolicyValidFromUtc,
        @ExpiresAtUtc = NULL, @Reason = N'Project-asset Defender fixture.',
        @IdempotencyKeyHash = @AssetPolicyIdempotency,
        @RequestHash = @AssetPolicyRequest,
        @CorrelationId = N'smoke037-asset-policy', @NowUtc = @NowUtc;
    DECLARE @AssetPolicyPublicId UNIQUEIDENTIFIER =
        (SELECT PolicyPublicId FROM @TrustResult WHERE Succeeded = 1);

    IF @SourcePolicyPublicId IS NULL OR @AssetPolicyPublicId IS NULL
       OR @SourcePolicyPublicId = @AssetPolicyPublicId
       OR (SELECT COUNT_BIG(1)
           FROM dbo.FundingPlatform_EventIngressTrustPolicies
           WHERE TenantId = @TenantId AND PrincipalObjectId = @PrincipalId
             AND ApplicationClientId = @ApplicationId
             AND TopicResourceId = @TopicResourceId
             AND StorageAccountResourceId = @StorageResourceId) <> 2
        THROW 55736, N'Source and project policies cannot coexist for one Azure identity.', 1;

    DECLARE @Organization TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProfileVersion INT, RowVersion BINARY(8));
    DECLARE @OrganizationSnapshot NVARCHAR(MAX) = N'{"name":"Asset Defender smoke"}';
    DECLARE @OrganizationHash BINARY(32) = HASHBYTES('SHA2_256', @OrganizationSnapshot);
    INSERT INTO @Organization
    EXEC dbo.FundingPlatform_usp_Organization_CreateForUser
        @UserPublicId = @AdminPublicId,
        @Name = N'Asset Defender smoke', @HomeCountryId = 152,
        @OrganizationTypeId = 2, @SnapshotJson = @OrganizationSnapshot,
        @ContentHash = @OrganizationHash;
    DECLARE @OrganizationId BIGINT = (SELECT Id FROM @Organization);
    DECLARE @OrganizationPublicId UNIQUEIDENTIFIER = (SELECT PublicId FROM @Organization);
    UPDATE dbo.FundingPlatform_Organizations
    SET ProfileStatus = 2, ProfileCompleteness = 100, UpdatedAtUtc = @NowUtc
    WHERE Id = @OrganizationId;

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
        N'{"title":"Asset Defender smoke","projectStage":1,"sustainableDevelopmentGoalIds":[1]}';
    DECLARE @ProjectHash BINARY(32) = HASHBYTES('SHA2_256', @ProjectSnapshot);
    DECLARE @ProjectSlug NVARCHAR(180) = N'asset-defender-' + @Suffix;
    DECLARE @Project TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProjectVersion INT, RowVersion BINARY(8));
    INSERT INTO @Project
    EXEC dbo.FundingPlatform_usp_Project_Create
        @OrganizationPublicId = @OrganizationPublicId,
        @UserPublicId = @AdminPublicId,
        @Slug = @ProjectSlug,
        @Title = N'Asset Defender smoke',
        @Summary = N'Validación transaccional de activos protegidos.',
        @Description = N'Proyecto completo para verificar revocación del marketplace.',
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
    UPDATE dbo.FundingPlatform_Projects
    SET PublicationStatus = 2, SubmittedAtUtc = @NowUtc,
        PublishedAtUtc = @NowUtc, ReviewedAtUtc = @NowUtc,
        ReviewedByUserId = @AdminUserId, RejectionReason = NULL,
        UpdatedAtUtc = @NowUtc
    WHERE Id = @ProjectId;

    DECLARE @AssetPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @AssetHash BINARY(32) = HASHBYTES('SHA2_256', N'asset-' + @Suffix);
    DECLARE @AssetObject NVARCHAR(1024) =
        LOWER(CONVERT(NVARCHAR(36), NEWID())) + N'/' + REPLICATE(N'a', 32) + N'.png';
    DECLARE @TrustedObject NVARCHAR(1024) = @AssetObject;
    DECLARE @IncomingObject NVARCHAR(1024) = @AssetObject;
    DECLARE @AssetETag NVARCHAR(100) = N'"asset-' + LEFT(@Suffix, 12) + N'"';
    INSERT INTO dbo.FundingPlatform_ProjectAssets
        (PublicId, ProjectId, Kind, OriginalFileName, DisplayName, VerifiedMimeType,
         ContentLength, ContentHash, PixelWidth, PixelHeight,
         QuarantineBlobContainer, QuarantineBlobObjectName,
         QuarantineBlobETag, QuarantineBlobVersionId,
         StorageStatus, ScanStatus, ScanProvider, ScanResultCode,
         ScanStartedAtUtc, ScanCompletedAtUtc, AltText, Caption, SortOrder,
         IsCover, IsDeleted, UploadedByUserId, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@AssetPublicId, @ProjectId, 0, N'impacto.png', N'Impacto', N'image/png',
         1024, @AssetHash, 800, 600, @QuarantineContainer, @AssetObject,
         @AssetETag, N'quarantine-v1', 1, 0, 1, NULL,
         @NowUtc, NULL, N'Actividad comunitaria', NULL, 0,
         0, 0, @AdminUserId, @NowUtc, @NowUtc);
    DECLARE @AssetId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_ProjectAssets WHERE PublicId = @AssetPublicId);

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
         N'project-incoming', @IncomingObject,
         @QuarantineContainer, @AssetObject,
         N'project-trusted', @TrustedObject,
         HASHBYTES('SHA2_256', N'completion-' + @Suffix), 2,
         DATEADD(MINUTE, 5, @NowUtc), 1, @AssetId, @NowUtc,
         @AdminUserId, @NowUtc, @NowUtc);

    DECLARE @ReceiptResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), ReceiptPublicId UNIQUEIDENTIFIER NULL,
        ProjectAssetPublicId UNIQUEIDENTIFIER NULL, ScanProvider TINYINT NULL,
        Kind TINYINT NULL, QuarantineBlobContainer NVARCHAR(63) NULL,
        QuarantineBlobObjectName NVARCHAR(1024) NULL,
        QuarantineBlobETag NVARCHAR(100) NULL, ContentHash BINARY(32) NULL,
        ContentLength BIGINT NULL, MimeType NVARCHAR(100) NULL, WasReplay BIT
    );
    DECLARE @UnauthorizedEventId NVARCHAR(200) = N'unauthorized-' + @Suffix;
    DECLARE @UnauthorizedPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'unauthorized-' + @Suffix);
    INSERT INTO @ReceiptResult
    EXEC dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Record
        @ProviderEventId = @UnauthorizedEventId,
        @PayloadHash = @UnauthorizedPayloadHash,
        @AuthenticatedTenantId = @TenantId,
        @AuthenticatedPrincipalId = @Fixture,
        @ApplicationClientId = @ApplicationId,
        @TopicResourceId = @TopicResourceId,
        @EventSubscriptionName = @SubscriptionName,
        @StorageAccountResourceId = @StorageResourceId,
        @BlobHost = @StorageHost, @BlobContainer = @QuarantineContainer,
        @BlobObjectName = @AssetObject, @BlobETag = @AssetETag,
        @ReportedContentHash = @AssetHash, @ToStatus = 1,
        @ResultCode = N'clean', @OccurredAtUtc = @OneSecond,
        @ReceivedAtUtc = @OneSecond;
    IF NOT EXISTS (SELECT 1 FROM @ReceiptResult WHERE Succeeded = 0 AND Code = N'unauthorized')
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssetDefenderReceipts
           WHERE ProviderEventId = @UnauthorizedEventId)
        THROW 55737, N'Unauthenticated project-asset event was persisted or accepted.', 1;

    DECLARE @CleanEventId NVARCHAR(200) = N'asset-clean-' + @Suffix;
    DECLARE @CleanPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'asset-clean-payload-' + @Suffix);
    DELETE FROM @ReceiptResult;
    DECLARE @ConflictingPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'conflicting-payload-' + @Suffix);
    INSERT INTO @ReceiptResult
    EXEC dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Record
        @ProviderEventId = @CleanEventId, @PayloadHash = @CleanPayloadHash,
        @AuthenticatedTenantId = @TenantId,
        @AuthenticatedPrincipalId = @PrincipalId,
        @ApplicationClientId = @ApplicationId,
        @TopicResourceId = @TopicResourceId,
        @EventSubscriptionName = @SubscriptionName,
        @StorageAccountResourceId = @StorageResourceId,
        @BlobHost = @StorageHost, @BlobContainer = @QuarantineContainer,
        @BlobObjectName = @AssetObject, @BlobETag = @AssetETag,
        @ReportedContentHash = @AssetHash, @ToStatus = 1,
        @ResultCode = N'clean', @OccurredAtUtc = @OneSecond,
        @ReceivedAtUtc = @OneSecond;
    DECLARE @CleanReceiptPublicId UNIQUEIDENTIFIER =
        (SELECT ReceiptPublicId FROM @ReceiptResult WHERE Succeeded = 1);
    IF @CleanReceiptPublicId IS NULL
       OR NOT EXISTS
          (SELECT 1 FROM @ReceiptResult
           WHERE Code = N'accepted' AND ProjectAssetPublicId = @AssetPublicId
             AND ScanProvider = 1 AND Kind = 0 AND ContentHash = @AssetHash)
        THROW 55738, N'Exact authenticated project-asset receipt was not accepted.', 1;

    DELETE FROM @ReceiptResult;
    INSERT INTO @ReceiptResult
    EXEC dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Record
        @ProviderEventId = @CleanEventId, @PayloadHash = @CleanPayloadHash,
        @AuthenticatedTenantId = @TenantId,
        @AuthenticatedPrincipalId = @PrincipalId,
        @ApplicationClientId = @ApplicationId,
        @TopicResourceId = @TopicResourceId,
        @EventSubscriptionName = @SubscriptionName,
        @StorageAccountResourceId = @StorageResourceId,
        @BlobHost = @StorageHost, @BlobContainer = @QuarantineContainer,
        @BlobObjectName = @AssetObject, @BlobETag = @AssetETag,
        @ReportedContentHash = @AssetHash, @ToStatus = 1,
        @ResultCode = N'clean', @OccurredAtUtc = @OneSecond,
        @ReceivedAtUtc = @OneSecond;
    IF NOT EXISTS
       (SELECT 1 FROM @ReceiptResult
        WHERE Succeeded = 1 AND Code = N'replayed-accepted' AND WasReplay = 1)
        THROW 55739, N'Accepted project-asset receipt replay was not stable.', 1;

    DELETE FROM @ReceiptResult;
    INSERT INTO @ReceiptResult
    EXEC dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Record
        @ProviderEventId = @CleanEventId,
        @PayloadHash = @ConflictingPayloadHash,
        @AuthenticatedTenantId = @TenantId,
        @AuthenticatedPrincipalId = @PrincipalId,
        @ApplicationClientId = @ApplicationId,
        @TopicResourceId = @TopicResourceId,
        @EventSubscriptionName = @SubscriptionName,
        @StorageAccountResourceId = @StorageResourceId,
        @BlobHost = @StorageHost, @BlobContainer = @QuarantineContainer,
        @BlobObjectName = @AssetObject, @BlobETag = @AssetETag,
        @ReportedContentHash = @AssetHash, @ToStatus = 1,
        @ResultCode = N'clean', @OccurredAtUtc = @OneSecond,
        @ReceivedAtUtc = @OneSecond;
    IF NOT EXISTS
       (SELECT 1 FROM @ReceiptResult
        WHERE Succeeded = 0 AND Code = N'event-conflict' AND ReceiptPublicId IS NULL)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_ProjectAssetDefenderReceipts
           WHERE ProviderEventId = @CleanEventId) <> 1
        THROW 55740, N'Provider-event conflict was not contained.', 1;

    DECLARE @ApplyResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), AssetPublicId UNIQUEIDENTIFIER,
        StorageStatus TINYINT NULL, ScanStatus TINYINT NULL,
        ScanProvider TINYINT NULL, AssetRowVersion BINARY(8) NULL,
        ProjectRowVersion BINARY(8) NULL, WasReplay BIT,
        RevokedTrustedBlobContainer NVARCHAR(63) NULL,
        RevokedTrustedBlobObjectName NVARCHAR(1024) NULL,
        RevokedTrustedBlobETag NVARCHAR(100) NULL,
        RevokedTrustedBlobVersionId NVARCHAR(200) NULL,
        RevokedTrustedMimeType NVARCHAR(100) NULL,
        RevokedTrustedContentLength BIGINT NULL,
        RevokedTrustedContentHash BINARY(32) NULL,
        RevokedTrustedPixelWidth INT NULL, RevokedTrustedPixelHeight INT NULL,
        RevokedTrustedProcessingVersion NVARCHAR(100) NULL,
        RevokedTrustedCreatedAtUtc DATETIME2(3) NULL
    );
    DECLARE @TrustedETag NVARCHAR(100) = N'"trusted-' + LEFT(@Suffix, 12) + N'"';
    DECLARE @BeforeMissingVersionRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_ProjectAssets WHERE Id = @AssetId);
    INSERT INTO @ApplyResult
    EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
        @AssetPublicId = @AssetPublicId, @ScanProvider = 1,
        @ProviderEventId = @CleanEventId, @PayloadHash = @CleanPayloadHash,
        @QuarantineBlobETag = @AssetETag, @ReportedContentHash = @AssetHash,
        @ToStatus = 1, @ResultCode = N'clean', @OccurredAtUtc = @OneSecond,
        @TrustedBlobContainer = N'project-trusted',
        @TrustedBlobObjectName = @TrustedObject,
        @TrustedBlobETag = @TrustedETag,
        @TrustedBlobVersionId = NULL,
        @TrustedMimeType = N'image/png', @TrustedContentLength = 1024,
        @TrustedContentHash = @AssetHash, @TrustedPixelWidth = 800, @TrustedPixelHeight = 600,
        @TrustedProcessingVersion = N'skia-4.151.2-image-v1';
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyResult
        WHERE Succeeded = 0 AND Code = N'invalid-scan-result')
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssets
           WHERE Id = @AssetId AND StorageStatus = 1 AND ScanStatus = 0
             AND RowVersion = @BeforeMissingVersionRowVersion)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssetScanEvents
           WHERE ProjectAssetId = @AssetId AND ProviderEventId = @CleanEventId)
        THROW 55755, N'Defender Clean without an immutable trusted version mutated state.', 1;

    DELETE FROM @ApplyResult;
    DECLARE @BypassEventId NVARCHAR(200) = N'asset-bypass-' + @Suffix;
    DECLARE @BypassPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'asset-bypass-payload-' + @Suffix);
    INSERT INTO @ApplyResult
    EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
        @AssetPublicId = @AssetPublicId, @ScanProvider = 1,
        @ProviderEventId = @BypassEventId, @PayloadHash = @BypassPayloadHash,
        @QuarantineBlobETag = @AssetETag, @ReportedContentHash = @AssetHash,
        @ToStatus = 1, @ResultCode = N'clean', @OccurredAtUtc = @OneSecond,
        @TrustedBlobContainer = N'project-trusted',
        @TrustedBlobObjectName = @TrustedObject,
        @TrustedBlobETag = @TrustedETag,
        @TrustedBlobVersionId = N'trusted-bypass-v1',
        @TrustedMimeType = N'image/png', @TrustedContentLength = 1024,
        @TrustedContentHash = @AssetHash, @TrustedPixelWidth = 800, @TrustedPixelHeight = 600,
        @TrustedProcessingVersion = N'skia-4.151.2-image-v1';
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyResult
        WHERE Succeeded = 0 AND Code = N'defender-receipt-required')
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssets
           WHERE Id = @AssetId AND StorageStatus = 1 AND ScanStatus = 0
             AND RowVersion = @BeforeMissingVersionRowVersion)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssetScanEvents
           WHERE ProjectAssetId = @AssetId AND ProviderEventId = @BypassEventId)
        THROW 55756, N'Defender scan application bypassed its authenticated receipt.', 1;

    DELETE FROM @ApplyResult;
    INSERT INTO @ApplyResult
    EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
        @AssetPublicId = @AssetPublicId, @ScanProvider = 1,
        @ProviderEventId = @CleanEventId, @PayloadHash = @CleanPayloadHash,
        @QuarantineBlobETag = @AssetETag, @ReportedContentHash = @AssetHash,
        @ToStatus = 1, @ResultCode = N'clean', @OccurredAtUtc = @OneSecond,
        @TrustedBlobContainer = N'project-trusted',
        @TrustedBlobObjectName = @TrustedObject,
        @TrustedBlobETag = @TrustedETag,
        @TrustedBlobVersionId = N'trusted-v1',
        @TrustedMimeType = N'image/png', @TrustedContentLength = 1024,
        @TrustedContentHash = @AssetHash, @TrustedPixelWidth = 800, @TrustedPixelHeight = 600,
        @TrustedProcessingVersion = N'skia-4.151.2-image-v1';
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyResult
        WHERE Succeeded = 1 AND Code = N'scan-result-applied'
          AND StorageStatus = 2 AND ScanStatus = 1
          AND AssetRowVersion IS NOT NULL AND ProjectRowVersion IS NOT NULL)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssetScanEvents
           WHERE ProjectAssetId = @AssetId AND ProviderEventId = @CleanEventId
             AND FromStatus = 0 AND ToStatus = 1)
        THROW 55741, N'Pending-to-clean transition was not applied durably.', 1;

    DECLARE @FinalizeResult TABLE
        (Succeeded BIT, Code NVARCHAR(50), ReceiptStatus TINYINT NULL, WasReplay BIT);
    INSERT INTO @FinalizeResult
    EXEC dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Finalize
        @ReceiptPublicId = @CleanReceiptPublicId, @PayloadHash = @CleanPayloadHash,
        @Applied = 1, @OutcomeCode = N'scan-result-applied',
        @FinalizedAtUtc = @TwoSeconds;
    IF NOT EXISTS
       (SELECT 1 FROM @FinalizeResult WHERE Succeeded = 1 AND Code = N'applied')
        THROW 55742, N'Applied project-asset receipt did not finalize.', 1;
    DELETE FROM @FinalizeResult;
    INSERT INTO @FinalizeResult
    EXEC dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Finalize
        @ReceiptPublicId = @CleanReceiptPublicId, @PayloadHash = @CleanPayloadHash,
        @Applied = 1, @OutcomeCode = N'scan-result-applied',
        @FinalizedAtUtc = @ThreeSeconds;
    IF NOT EXISTS
       (SELECT 1 FROM @FinalizeResult
        WHERE Succeeded = 1 AND Code = N'replayed' AND WasReplay = 1)
        THROW 55743, N'Project-asset receipt finalization replay was unstable.', 1;

    UPDATE dbo.FundingPlatform_ProjectAssets
    SET IsCover = 1, UpdatedAtUtc = @TwoSeconds
    WHERE Id = @AssetId;
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ProjectAssets
        WHERE Id = @AssetId AND IsCover = 1)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMarketplaceReady()
           WHERE ProjectId = @ProjectId)
        THROW 55744, N'Trusted accessible cover did not enter the marketplace fixture.', 1;

    DECLARE @StaleEventId NVARCHAR(200) = N'asset-stale-' + @Suffix;
    DECLARE @StalePayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'asset-stale-payload-' + @Suffix);
    DELETE FROM @ReceiptResult;
    INSERT INTO @ReceiptResult
    EXEC dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Record
        @ProviderEventId = @StaleEventId, @PayloadHash = @StalePayloadHash,
        @AuthenticatedTenantId = @TenantId,
        @AuthenticatedPrincipalId = @PrincipalId,
        @ApplicationClientId = @ApplicationId,
        @TopicResourceId = @TopicResourceId,
        @EventSubscriptionName = @SubscriptionName,
        @StorageAccountResourceId = @StorageResourceId,
        @BlobHost = @StorageHost, @BlobContainer = @QuarantineContainer,
        @BlobObjectName = @AssetObject, @BlobETag = @AssetETag,
        @ReportedContentHash = @AssetHash, @ToStatus = 2,
        @ResultCode = N'malicious', @OccurredAtUtc = @OneSecond,
        @ReceivedAtUtc = @TwoSeconds;
    IF NOT EXISTS
       (SELECT 1 FROM @ReceiptResult
        WHERE Succeeded = 0 AND Code = N'stale-scan-result' AND WasReplay = 0)
        THROW 55745, N'Stale Defender result remained retryable.', 1;
    DELETE FROM @ReceiptResult;
    INSERT INTO @ReceiptResult
    EXEC dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Record
        @ProviderEventId = @StaleEventId, @PayloadHash = @StalePayloadHash,
        @AuthenticatedTenantId = @TenantId,
        @AuthenticatedPrincipalId = @PrincipalId,
        @ApplicationClientId = @ApplicationId,
        @TopicResourceId = @TopicResourceId,
        @EventSubscriptionName = @SubscriptionName,
        @StorageAccountResourceId = @StorageResourceId,
        @BlobHost = @StorageHost, @BlobContainer = @QuarantineContainer,
        @BlobObjectName = @AssetObject, @BlobETag = @AssetETag,
        @ReportedContentHash = @AssetHash, @ToStatus = 2,
        @ResultCode = N'malicious', @OccurredAtUtc = @OneSecond,
        @ReceivedAtUtc = @TwoSeconds;
    IF NOT EXISTS
       (SELECT 1 FROM @ReceiptResult
        WHERE Succeeded = 0 AND Code = N'replayed-ignored' AND WasReplay = 1)
        THROW 55746, N'Stale Defender receipt replay was not terminal.', 1;

    DECLARE @ThreatEventId NVARCHAR(200) = N'asset-threat-' + @Suffix;
    DECLARE @ThreatPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'asset-threat-payload-' + @Suffix);
    DELETE FROM @ReceiptResult;
    INSERT INTO @ReceiptResult
    EXEC dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Record
        @ProviderEventId = @ThreatEventId, @PayloadHash = @ThreatPayloadHash,
        @AuthenticatedTenantId = @TenantId,
        @AuthenticatedPrincipalId = @PrincipalId,
        @ApplicationClientId = @ApplicationId,
        @TopicResourceId = @TopicResourceId,
        @EventSubscriptionName = @SubscriptionName,
        @StorageAccountResourceId = @StorageResourceId,
        @BlobHost = @StorageHost, @BlobContainer = @QuarantineContainer,
        @BlobObjectName = @AssetObject, @BlobETag = @AssetETag,
        @ReportedContentHash = @AssetHash, @ToStatus = 2,
        @ResultCode = N'malicious', @OccurredAtUtc = @ThreeSeconds,
        @ReceivedAtUtc = @ThreeSeconds;
    DECLARE @ThreatReceiptPublicId UNIQUEIDENTIFIER =
        (SELECT ReceiptPublicId FROM @ReceiptResult WHERE Succeeded = 1);
    IF @ThreatReceiptPublicId IS NULL
        THROW 55747, N'Later authenticated threat was not accepted.', 1;

    DELETE FROM @ApplyResult;
    INSERT INTO @ApplyResult
    EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
        @AssetPublicId = @AssetPublicId, @ScanProvider = 1,
        @ProviderEventId = @ThreatEventId, @PayloadHash = @ThreatPayloadHash,
        @QuarantineBlobETag = @AssetETag, @ReportedContentHash = @AssetHash,
        @ToStatus = 2, @ResultCode = N'malicious', @OccurredAtUtc = @ThreeSeconds,
        @TrustedBlobContainer = NULL, @TrustedBlobObjectName = NULL,
        @TrustedBlobETag = NULL, @TrustedBlobVersionId = NULL;
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyResult
        WHERE Succeeded = 1 AND Code = N'scan-result-superseded'
          AND StorageStatus = 3 AND ScanStatus = 2
          AND RevokedTrustedBlobContainer = N'project-trusted'
          AND RevokedTrustedBlobObjectName = @TrustedObject
          AND RevokedTrustedBlobVersionId = N'trusted-v1')
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssets
           WHERE Id = @AssetId AND StorageStatus = 3 AND ScanStatus = 2
             AND TrustedBlobContainer IS NULL AND TrustedBlobObjectName IS NULL
             AND TrustedBlobETag IS NULL AND TrustedBlobVersionId IS NULL
             AND IsCover = 0)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMarketplaceReady()
           WHERE ProjectId = @ProjectId)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
           WHERE MessageType = N'ProjectAssetScanTrustRevoked'
             AND AggregateId = CONVERT(NVARCHAR(100), @AssetPublicId)
             AND JSON_VALUE(PayloadJson, N'$.assetPublicId') =
                 CONVERT(NVARCHAR(36), @AssetPublicId)
             AND JSON_VALUE(PayloadJson, N'$.projectId') IS NULL)
        THROW 55748, N'Late malicious result did not revoke cover and marketplace trust.', 1;

    DELETE FROM @FinalizeResult;
    INSERT INTO @FinalizeResult
    EXEC dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Finalize
        @ReceiptPublicId = @ThreatReceiptPublicId,
        @PayloadHash = @ThreatPayloadHash, @Applied = 1,
        @OutcomeCode = N'scan-result-superseded', @FinalizedAtUtc = @FourSeconds;
    IF NOT EXISTS
       (SELECT 1 FROM @FinalizeResult WHERE Succeeded = 1 AND Code = N'applied')
        THROW 55749, N'Superseding project-asset receipt did not finalize.', 1;

    DELETE FROM @ApplyResult;
    INSERT INTO @ApplyResult
    EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
        @AssetPublicId = @AssetPublicId, @ScanProvider = 1,
        @ProviderEventId = @ThreatEventId, @PayloadHash = @ThreatPayloadHash,
        @QuarantineBlobETag = @AssetETag, @ReportedContentHash = @AssetHash,
        @ToStatus = 2, @ResultCode = N'malicious', @OccurredAtUtc = @ThreeSeconds;
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyResult
        WHERE Succeeded = 1 AND Code = N'scan-result-superseded'
          AND WasReplay = 1
          AND RevokedTrustedBlobObjectName = @TrustedObject
          AND RevokedTrustedBlobVersionId = N'trusted-v1')
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_ProjectAssetScanEvents
           WHERE ProjectAssetId = @AssetId AND FromStatus = 1) <> 1
        THROW 55750, N'Late threat replay lost its conditional-delete identity.', 1;

    /* Failed and TimedOut may legitimately arrive without a provider content hash. */
    DECLARE @FailedAssetPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @FailedAssetHash BINARY(32) = HASHBYTES('SHA2_256', N'failed-' + @Suffix);
    DECLARE @FailedAssetObject NVARCHAR(1024) =
        LOWER(CONVERT(NVARCHAR(36), NEWID())) + N'/' + REPLICATE(N'd', 32) + N'.png';
    DECLARE @FailedAssetETag NVARCHAR(100) = N'"failed-' + LEFT(@Suffix, 12) + N'"';
    INSERT INTO dbo.FundingPlatform_ProjectAssets
        (PublicId, ProjectId, Kind, OriginalFileName, VerifiedMimeType,
         ContentLength, ContentHash, PixelWidth, PixelHeight,
         QuarantineBlobContainer, QuarantineBlobObjectName, QuarantineBlobETag,
         StorageStatus, ScanStatus, ScanProvider, ScanStartedAtUtc,
         AltText, SortOrder, IsCover, IsDeleted, UploadedByUserId,
         CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@FailedAssetPublicId, @ProjectId, 0, N'failed.png', N'image/png',
         512, @FailedAssetHash, 100, 100, @QuarantineContainer,
         @FailedAssetObject, @FailedAssetETag, 1, 0, 1, @NowUtc,
         N'Asset destinado a fallo', 1, 0, 0, @AdminUserId, @NowUtc, @NowUtc);
    DECLARE @FailedEventId NVARCHAR(200) = N'asset-failed-' + @Suffix;
    DECLARE @FailedPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'asset-failed-payload-' + @Suffix);
    DELETE FROM @ReceiptResult;
    INSERT INTO @ReceiptResult
    EXEC dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Record
        @ProviderEventId = @FailedEventId, @PayloadHash = @FailedPayloadHash,
        @AuthenticatedTenantId = @TenantId,
        @AuthenticatedPrincipalId = @PrincipalId,
        @ApplicationClientId = @ApplicationId,
        @TopicResourceId = @TopicResourceId,
        @EventSubscriptionName = @SubscriptionName,
        @StorageAccountResourceId = @StorageResourceId,
        @BlobHost = @StorageHost, @BlobContainer = @QuarantineContainer,
        @BlobObjectName = @FailedAssetObject, @BlobETag = @FailedAssetETag,
        @ReportedContentHash = NULL, @ToStatus = 3,
        @ResultCode = N'scan-failed', @OccurredAtUtc = @TwoSeconds,
        @ReceivedAtUtc = @TwoSeconds;
    IF NOT EXISTS (SELECT 1 FROM @ReceiptResult WHERE Succeeded = 1 AND Code = N'accepted')
        THROW 55751, N'Hashless failed receipt was rejected.', 1;
    DELETE FROM @ApplyResult;
    INSERT INTO @ApplyResult
    EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
        @AssetPublicId = @FailedAssetPublicId, @ScanProvider = 1,
        @ProviderEventId = @FailedEventId, @PayloadHash = @FailedPayloadHash,
        @QuarantineBlobETag = @FailedAssetETag, @ReportedContentHash = NULL,
        @ToStatus = 3, @ResultCode = N'scan-failed', @OccurredAtUtc = @TwoSeconds;
    IF NOT EXISTS
       (SELECT 1 FROM @ApplyResult
        WHERE Succeeded = 1 AND Code = N'scan-result-applied'
          AND StorageStatus = 3 AND ScanStatus = 3)
        THROW 55752, N'Hashless failed result did not terminalize fail closed.', 1;

    DECLARE @OldUtc DATETIME2(3) = DATEADD(HOUR, -4, @NowUtc);
    DECLARE @TimeoutAssetPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @FakeAssetPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @TimeoutAssetObject NVARCHAR(1024) =
        LOWER(CONVERT(NVARCHAR(36), NEWID())) + N'/' + REPLICATE(N'e', 32) + N'.png';
    DECLARE @FakeAssetObject NVARCHAR(1024) =
        LOWER(CONVERT(NVARCHAR(36), NEWID())) + N'/' + REPLICATE(N'f', 32) + N'.png';
    INSERT INTO dbo.FundingPlatform_ProjectAssets
        (PublicId, ProjectId, Kind, OriginalFileName, VerifiedMimeType,
         ContentLength, ContentHash, PixelWidth, PixelHeight,
         QuarantineBlobContainer, QuarantineBlobObjectName, QuarantineBlobETag,
         StorageStatus, ScanStatus, ScanProvider, ScanStartedAtUtc,
         AltText, SortOrder, IsCover, IsDeleted, UploadedByUserId,
         CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@TimeoutAssetPublicId, @ProjectId, 0, N'timeout.png', N'image/png', 512,
         HASHBYTES('SHA2_256', N'timeout-' + @Suffix), 100, 100,
         @QuarantineContainer, @TimeoutAssetObject, N'"timeout"',
         1, 0, 1, @OldUtc, N'Asset Defender pendiente', 2, 0, 0,
         @AdminUserId, @OldUtc, @OldUtc),
        (@FakeAssetPublicId, @ProjectId, 0, N'fake.png', N'image/png', 512,
         HASHBYTES('SHA2_256', N'fake-' + @Suffix), 100, 100,
         @QuarantineContainer, @FakeAssetObject, N'"fake"',
         1, 0, 0, @OldUtc, N'Asset fake pendiente', 3, 0, 0,
         @AdminUserId, @OldUtc, @OldUtc);

    DECLARE @WatchdogResult TABLE
    (
        ProjectAssetPublicId UNIQUEIDENTIFIER, StorageStatus TINYINT,
        ScanStatus TINYINT, ScanProvider TINYINT,
        AssetRowVersion BINARY(8), ProjectRowVersion BINARY(8)
    );
    INSERT INTO @WatchdogResult
    EXEC dbo.FundingPlatform_usp_ProjectAssetScan_WatchdogTimeout
        @BatchSize = 100, @TimeoutSeconds = 10800, @NowUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @WatchdogResult
        WHERE ProjectAssetPublicId = @TimeoutAssetPublicId
          AND StorageStatus = 3 AND ScanStatus = 4 AND ScanProvider = 1
          AND AssetRowVersion IS NOT NULL AND ProjectRowVersion IS NOT NULL)
       OR EXISTS
          (SELECT 1 FROM @WatchdogResult
           WHERE ProjectAssetPublicId = @FakeAssetPublicId)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssets
           WHERE PublicId = @FakeAssetPublicId
             AND StorageStatus = 1 AND ScanStatus = 0 AND ScanProvider = 0)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssetScanEvents AS events
           INNER JOIN dbo.FundingPlatform_ProjectAssets AS assets
               ON assets.Id = events.ProjectAssetId
           WHERE assets.PublicId = @TimeoutAssetPublicId
             AND events.FromStatus = 0 AND events.ToStatus = 4
             AND events.ReportedContentHash IS NULL
             AND events.ResultCode = N'defender-timeout')
        THROW 55753, N'Defender watchdog scope or audit event is invalid.', 1;

    DELETE FROM @WatchdogResult;
    DECLARE @WatchdogReplayUtc DATETIME2(3) = DATEADD(MINUTE, 1, @NowUtc);
    INSERT INTO @WatchdogResult
    EXEC dbo.FundingPlatform_usp_ProjectAssetScan_WatchdogTimeout
        @BatchSize = 100, @TimeoutSeconds = 10800,
        @NowUtc = @WatchdogReplayUtc;
    IF EXISTS
       (SELECT 1 FROM @WatchdogResult
        WHERE ProjectAssetPublicId = @TimeoutAssetPublicId)
       OR (SELECT COUNT_BIG(1)
           FROM dbo.FundingPlatform_ProjectAssetScanEvents AS events
           INNER JOIN dbo.FundingPlatform_ProjectAssets AS assets
               ON assets.Id = events.ProjectAssetId
           WHERE assets.PublicId = @TimeoutAssetPublicId
             AND events.ResultCode = N'defender-timeout') <> 1
        THROW 55754, N'Defender watchdog replay was not idempotent.', 1;

    /* The cumulative audit sink must consume only the ten exact 036/037 event
       schemas, share the caller's batch budget, and fail closed otherwise. */
    DECLARE @LedgerAckUtc DATETIME2(3) = DATEADD(MINUTE, 2, @WatchdogReplayUtc);
    UPDATE dbo.FundingPlatform_OutboxMessages
    SET AvailableAtUtc = DATEADD(DAY, 2, @LedgerAckUtc)
    WHERE DispatchedAtUtc IS NULL;

    DECLARE @LedgerIntentCreated UNIQUEIDENTIFIER = NEWID();
    DECLARE @LedgerIntentRejected UNIQUEIDENTIFIER = NEWID();
    DECLARE @LedgerFinalizedAsset UNIQUEIDENTIFIER = NEWID();
    DECLARE @LedgerQuarantinedAsset UNIQUEIDENTIFIER = NEWID();
    DECLARE @LedgerScannedAsset UNIQUEIDENTIFIER = NEWID();
    DECLARE @LedgerMetadataAsset UNIQUEIDENTIFIER = NEWID();
    DECLARE @LedgerDeletedAsset UNIQUEIDENTIFIER = NEWID();
    DECLARE @LedgerRevokedAsset UNIQUEIDENTIFIER = NEWID();
    DECLARE @LedgerTimedOutAsset UNIQUEIDENTIFIER = NEWID();
    DECLARE @LedgerScanEvent UNIQUEIDENTIFIER = NEWID();
    DECLARE @LedgerRevokeEvent UNIQUEIDENTIFIER = NEWID();
    DECLARE @LedgerTimeoutEvent UNIQUEIDENTIFIER = NEWID();
    DECLARE @LedgerAssetCount INT =
        (SELECT COUNT(1) FROM dbo.FundingPlatform_ProjectAssets
         WHERE ProjectId = @ProjectId AND IsDeleted = 0);

    DECLARE @LedgerIntentCreatedPayload NVARCHAR(MAX) =
        (SELECT @LedgerIntentCreated AS intentPublicId,
                @ProjectPublicId AS projectPublicId,
                CAST(0 AS TINYINT) AS kind, CAST(0 AS TINYINT) AS status
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @LedgerIntentRejectedPayload NVARCHAR(MAX) =
        (SELECT @LedgerIntentRejected AS intentPublicId,
                @ProjectPublicId AS projectPublicId,
                CAST(4 AS TINYINT) AS status, N'upload-rejected' AS errorCode
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @LedgerFinalizedPayload NVARCHAR(MAX) =
        (SELECT @LedgerFinalizedAsset AS assetPublicId,
                @ProjectPublicId AS projectPublicId,
                @LedgerIntentCreated AS intentPublicId,
                CAST(0 AS TINYINT) AS kind, CAST(0 AS TINYINT) AS storageStatus,
                CAST(0 AS TINYINT) AS scanStatus, CAST(1 AS TINYINT) AS scanProvider
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @LedgerQuarantinedPayload NVARCHAR(MAX) =
        (SELECT @LedgerQuarantinedAsset AS assetPublicId,
                @ProjectPublicId AS projectPublicId,
                CAST(1 AS TINYINT) AS storageStatus,
                CAST(0 AS TINYINT) AS scanStatus, CAST(1 AS TINYINT) AS scanProvider
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @LedgerScannedPayload NVARCHAR(MAX) =
        (SELECT @LedgerScanEvent AS eventId, @LedgerScannedAsset AS assetPublicId,
                CAST(1 AS TINYINT) AS scanProvider, CAST(1 AS TINYINT) AS scanStatus,
                CAST(2 AS TINYINT) AS storageStatus, N'clean' AS resultCode
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @LedgerMetadataPayload NVARCHAR(MAX) =
        (SELECT @LedgerMetadataAsset AS assetPublicId,
                @ProjectPublicId AS projectPublicId, CAST(1 AS BIT) AS isCover
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @LedgerReorderedPayload NVARCHAR(MAX) =
        (SELECT @ProjectPublicId AS projectPublicId, @LedgerAssetCount AS assetCount
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @LedgerDeletedPayload NVARCHAR(MAX) =
        (SELECT @LedgerDeletedAsset AS assetPublicId,
                @ProjectPublicId AS projectPublicId
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @LedgerRevokedPayload NVARCHAR(MAX) =
        (SELECT @LedgerRevokeEvent AS eventId, @LedgerRevokedAsset AS assetPublicId,
                CAST(2 AS TINYINT) AS scanStatus, CAST(3 AS TINYINT) AS storageStatus,
                N'malicious' AS resultCode
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @LedgerTimedOutPayload NVARCHAR(MAX) =
        (SELECT @LedgerTimeoutEvent AS eventId, @LedgerTimedOutAsset AS assetPublicId,
                CAST(1 AS TINYINT) AS scanProvider, CAST(4 AS TINYINT) AS scanStatus,
                CAST(3 AS TINYINT) AS storageStatus, N'defender-timeout' AS resultCode
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    DECLARE @ValidAuditMessages TABLE
        (Id BIGINT NOT NULL PRIMARY KEY, MessageType NVARCHAR(100) NOT NULL);
    INSERT INTO dbo.FundingPlatform_OutboxMessages
        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
         OccurredAtUtc, AvailableAtUtc)
    OUTPUT inserted.Id, inserted.MessageType
        INTO @ValidAuditMessages (Id, MessageType)
    VALUES
        (NEWID(), N'ProjectAssetUploadIntentCreated', N'ProjectAssetUploadIntent',
         CONVERT(NVARCHAR(100), @LedgerIntentCreated), @LedgerIntentCreatedPayload,
         @LedgerAckUtc, @LedgerAckUtc),
        (NEWID(), N'ProjectAssetUploadIntentRejected', N'ProjectAssetUploadIntent',
         CONVERT(NVARCHAR(100), @LedgerIntentRejected), @LedgerIntentRejectedPayload,
         @LedgerAckUtc, @LedgerAckUtc),
        (NEWID(), N'ProjectAssetFinalized', N'ProjectAsset',
         CONVERT(NVARCHAR(100), @LedgerFinalizedAsset), @LedgerFinalizedPayload,
         @LedgerAckUtc, @LedgerAckUtc),
        (NEWID(), N'ProjectAssetQuarantined', N'ProjectAsset',
         CONVERT(NVARCHAR(100), @LedgerQuarantinedAsset), @LedgerQuarantinedPayload,
         @LedgerAckUtc, @LedgerAckUtc),
        (@LedgerScanEvent, N'ProjectAssetScanCompleted', N'ProjectAsset',
         CONVERT(NVARCHAR(100), @LedgerScannedAsset), @LedgerScannedPayload,
         @LedgerAckUtc, @LedgerAckUtc),
        (NEWID(), N'ProjectAssetMetadataUpdated', N'ProjectAsset',
         CONVERT(NVARCHAR(100), @LedgerMetadataAsset), @LedgerMetadataPayload,
         @LedgerAckUtc, @LedgerAckUtc),
        (NEWID(), N'ProjectAssetsReordered', N'Project',
         CONVERT(NVARCHAR(100), @ProjectId), @LedgerReorderedPayload,
         @LedgerAckUtc, @LedgerAckUtc),
        (NEWID(), N'ProjectAssetDeleted', N'ProjectAsset',
         CONVERT(NVARCHAR(100), @LedgerDeletedAsset), @LedgerDeletedPayload,
         @LedgerAckUtc, @LedgerAckUtc),
        (@LedgerRevokeEvent, N'ProjectAssetScanTrustRevoked', N'ProjectAsset',
         CONVERT(NVARCHAR(100), @LedgerRevokedAsset), @LedgerRevokedPayload,
         @LedgerAckUtc, @LedgerAckUtc),
        (@LedgerTimeoutEvent, N'ProjectAssetScanTimedOut', N'ProjectAsset',
         CONVERT(NVARCHAR(100), @LedgerTimedOutAsset), @LedgerTimedOutPayload,
         @LedgerAckUtc, @LedgerAckUtc);

    DECLARE @MalformedAssetPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @MalformedPayload NVARCHAR(MAX) =
        (SELECT @MalformedAssetPublicId AS assetPublicId,
                @ProjectPublicId AS projectPublicId, 1 AS version
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    INSERT INTO dbo.FundingPlatform_OutboxMessages
        (MessageType, AggregateType, AggregateId, PayloadJson,
         OccurredAtUtc, AvailableAtUtc)
    VALUES
        (N'ProjectAssetDeleted', N'ProjectAsset',
         CONVERT(NVARCHAR(100), @MalformedAssetPublicId), @MalformedPayload,
         @LedgerAckUtc, @LedgerAckUtc);
    DECLARE @MalformedAuditId BIGINT = SCOPE_IDENTITY();

    DECLARE @UnknownAssetPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @UnknownPayload NVARCHAR(MAX) =
        (SELECT @UnknownAssetPublicId AS assetPublicId,
                @ProjectPublicId AS projectPublicId
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    INSERT INTO dbo.FundingPlatform_OutboxMessages
        (MessageType, AggregateType, AggregateId, PayloadJson,
         OccurredAtUtc, AvailableAtUtc)
    VALUES
        (N'ProjectAssetUnknown', N'ProjectAsset',
         CONVERT(NVARCHAR(100), @UnknownAssetPublicId), @UnknownPayload,
         @LedgerAckUtc, @LedgerAckUtc);
    DECLARE @UnknownAuditId BIGINT = SCOPE_IDENTITY();

    DECLARE @InvalidKindIntentPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InvalidKindPayload NVARCHAR(MAX) =
        (SELECT @InvalidKindIntentPublicId AS intentPublicId,
                @ProjectPublicId AS projectPublicId,
                CAST(9 AS TINYINT) AS kind, CAST(0 AS TINYINT) AS status
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    INSERT INTO dbo.FundingPlatform_OutboxMessages
        (MessageType, AggregateType, AggregateId, PayloadJson,
         OccurredAtUtc, AvailableAtUtc)
    VALUES
        (N'ProjectAssetUploadIntentCreated', N'ProjectAssetUploadIntent',
         CONVERT(NVARCHAR(100), @InvalidKindIntentPublicId), @InvalidKindPayload,
         @LedgerAckUtc, @LedgerAckUtc);
    DECLARE @InvalidKindAuditId BIGINT = SCOPE_IDENTITY();

    DECLARE @AcknowledgedCount INT = -1;
    EXEC dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge
        @BatchSize = 4, @NowUtc = @LedgerAckUtc,
        @AcknowledgedCount = @AcknowledgedCount OUTPUT;
    IF @AcknowledgedCount <> 4
       OR (SELECT COUNT_BIG(1)
           FROM dbo.FundingPlatform_OutboxMessages AS messages
           INNER JOIN @ValidAuditMessages AS valid ON valid.Id = messages.Id
           WHERE messages.DispatchedAtUtc = @LedgerAckUtc) <> 4
        THROW 55757, N'Project asset audit sink did not respect the shared batch size.', 1;

    SET @AcknowledgedCount = -1;
    EXEC dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge
        @BatchSize = 500, @NowUtc = @LedgerAckUtc,
        @AcknowledgedCount = @AcknowledgedCount OUTPUT;
    IF @AcknowledgedCount <> 6
       OR (SELECT COUNT_BIG(1)
           FROM dbo.FundingPlatform_OutboxMessages AS messages
           INNER JOIN @ValidAuditMessages AS valid ON valid.Id = messages.Id
           WHERE messages.DispatchedAtUtc = @LedgerAckUtc
             AND messages.LastError = N'event-ledger-acknowledged') <> 10
       OR (SELECT COUNT(DISTINCT MessageType) FROM @ValidAuditMessages) <> 10
        THROW 55758, N'Project asset audit sink did not recognize all ten exact schemas.', 1;

    IF EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
        WHERE Id IN (@MalformedAuditId, @UnknownAuditId, @InvalidKindAuditId)
          AND DispatchedAtUtc IS NOT NULL)
        THROW 55759, N'Project asset audit sink accepted unknown or widened payloads.', 1;

    SET @AcknowledgedCount = -1;
    DECLARE @LedgerReplayUtc DATETIME2(3) = DATEADD(SECOND, 1, @LedgerAckUtc);
    EXEC dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge
        @BatchSize = 500, @NowUtc = @LedgerReplayUtc,
        @AcknowledgedCount = @AcknowledgedCount OUTPUT;
    IF @AcknowledgedCount <> 0
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
           WHERE Id IN (@MalformedAuditId, @UnknownAuditId, @InvalidKindAuditId)
             AND DispatchedAtUtc IS NOT NULL)
        THROW 55760, N'Project asset audit acknowledgement was not idempotent or fail closed.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke037;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FP_Smoke037;
    THROW;
END CATCH;

SELECT CAST(1 AS BIT) AS Succeeded;
