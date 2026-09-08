/* Transactional smoke for migration 036: governed private project assets. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_ProjectAssets', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetUploadIntents', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetScanEvents', N'U') IS NULL
   OR TYPE_ID(N'dbo.FundingPlatform_ProjectAssetOrderList') IS NULL
    THROW 55620, N'Project asset schema contract is missing.', 1;

IF NOT EXISTS
(
    SELECT 1 FROM sys.foreign_keys
    WHERE parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_ProjectAssets', N'U')
      AND name = N'FundingPlatform_FK_ProjectAssets_Projects'
      AND delete_referential_action = 1
)
   OR NOT EXISTS
   (
       SELECT 1 FROM sys.foreign_keys
       WHERE parent_object_id =
             OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetUploadIntents', N'U')
         AND name = N'FundingPlatform_FK_ProjectAssetUploadIntents_Projects'
         AND delete_referential_action = 1
   )
    THROW 55621, N'Project asset tenant cascade contract failed.', 1;

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.FundingPlatform_ProjectAssets', N'U')
      AND name = N'FundingPlatform_UQ_ProjectAssets_ActiveCover'
      AND is_unique = 1 AND has_filter = 1
)
   OR NOT EXISTS
   (
       SELECT 1 FROM sys.check_constraints
       WHERE parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_ProjectAssets', N'U')
         AND name IN (N'FundingPlatform_CK_ProjectAssets_ImageDimensions',
                      N'FundingPlatform_CK_ProjectAssets_TrustedState',
                      N'FundingPlatform_CK_ProjectAssets_Metadata')
       GROUP BY parent_object_id
       HAVING COUNT_BIG(1) = 3
   )
    THROW 55622, N'Project asset safety constraints failed.', 1;

DECLARE @CreateDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Create', N'P'));
DECLARE @CompleteDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Complete', N'P'));
DECLARE @AcquireDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(
        N'dbo.FundingPlatform_usp_ProjectAssetUploadIntent_AcquireFinalize', N'P'));
DECLARE @ListDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_List', N'P'));
DECLARE @TrustedDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_GetTrustedContent', N'P'));
DECLARE @RequestDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_Project_RequestPublication', N'P'));
DECLARE @ReviewDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_Project_AdminReview', N'P'));
DECLARE @MarketplaceDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_ifn_ProjectMarketplaceReady', N'IF'));

IF @CreateDefinition NOT LIKE N'%@ExpectedProjectRowVersion BINARY(8)%'
   OR @CreateDefinition NOT LIKE N'%pending-intent-limit%'
   OR @CreateDefinition NOT LIKE N'%@IncomingBlobContainer = @QuarantineBlobContainer%'
   OR @CreateDefinition NOT LIKE N'%@IncomingBlobContainer = @TrustedBlobContainer%'
   OR @CreateDefinition NOT LIKE N'%@QuarantineBlobContainer = @TrustedBlobContainer%'
   OR @CreateDefinition NOT LIKE N'%SUBSTRING(@IncomingBlobObjectName, 38, 32)%'
   OR @CreateDefinition NOT LIKE N'%@MaxContentLength > 10485760%'
   OR @CreateDefinition NOT LIKE N'%@MaxContentLength > 26214400%'
   OR @CompleteDefinition NOT LIKE N'%@PixelWidth INT = NULL%'
   OR @CompleteDefinition NOT LIKE N'%25000000%'
   OR @CompleteDefinition NOT LIKE N'%asset-limit%'
   OR @CompleteDefinition NOT LIKE N'%image-limit%'
   OR @CompleteDefinition NOT LIKE N'%document-limit%'
   OR @CompleteDefinition NOT LIKE
      N'%WHERE assets.Id = @AssetId%AND assets.IsDeleted = 0%'
   OR @AcquireDefinition NOT LIKE N'%@CompletionTokenHash BINARY(32)%'
   OR @AcquireDefinition NOT LIKE N'%CASE WHEN @LeaseUntilUtc > @ExpiresAtUtc%'
   OR @AcquireDefinition NOT LIKE N'%COALESCE(@AssetIsDeleted, 1) = 1%'
   OR @AcquireDefinition NOT LIKE N'%SET @Code = N''asset-deleted''%'
   OR @AcquireDefinition NOT LIKE
      N'%assets.Id = intents.CompletedProjectAssetId AND assets.IsDeleted = 0%'
   OR @AcquireDefinition NOT LIKE N'%assets.RowVersion AS AssetRowVersion%'
    THROW 55623, N'Project asset write bounds drifted.', 1;

IF @ListDefinition LIKE N'%TrustedBlobContainer%'
   OR @ListDefinition LIKE N'%QuarantineBlobContainer%'
   OR @ListDefinition LIKE N'%IncomingBlobContainer%'
   OR @ListDefinition LIKE N'%ContentHash%'
   OR @ListDefinition NOT LIKE N'%ProjectRowVersion%'
   OR @ListDefinition LIKE N'%memberships.Role = 1%'
   OR @TrustedDefinition LIKE N'%memberships.Role = 1%'
   OR @TrustedDefinition NOT LIKE N'%@StorageStatus <> 2 OR @ScanStatus <> 1%'
   OR @TrustedDefinition NOT LIKE N'%@StoredAssetPublicId IS NULL%'
   OR @TrustedDefinition NOT LIKE N'%@StoredAssetPublicId AS AssetPublicId%'
   OR @TrustedDefinition NOT LIKE N'%TrustedBlobETag%'
   OR @TrustedDefinition NOT LIKE N'%Kind%'
    THROW 55624, N'Private asset read boundary drifted.', 1;

IF @RequestDefinition NOT LIKE N'%assetsPending%'
   OR @RequestDefinition NOT LIKE N'%assetsNotTrusted%'
   OR @RequestDefinition NOT LIKE N'%coverAltText%'
   OR @ReviewDefinition NOT LIKE N'%project-assets-not-ready%'
   OR @MarketplaceDefinition NOT LIKE N'%FundingPlatform_ProjectAssets%'
   OR @MarketplaceDefinition NOT LIKE N'%assets.StorageStatus <> 2%'
   OR @MarketplaceDefinition NOT LIKE N'%assets.ScanStatus <> 1%'
    THROW 55625, N'Project publication fail-closed gates drifted.', 1;

IF DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole') IS NOT NULL
   AND
   (
       EXISTS
       (
           SELECT 1
           FROM sys.database_permissions AS permissions
           WHERE permissions.grantee_principal_id =
                 DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole')
             AND permissions.class = 1
             AND permissions.major_id IN
                 (OBJECT_ID(N'dbo.FundingPlatform_ProjectAssets', N'U'),
                  OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetUploadIntents', N'U'),
                  OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetScanEvents', N'U'))
             AND permissions.permission_name IN (N'SELECT', N'INSERT', N'UPDATE', N'DELETE')
             AND permissions.state IN (N'G', N'W')
       )
       OR NOT EXISTS
       (
           SELECT 1
           FROM sys.database_permissions AS permissions
           WHERE permissions.grantee_principal_id =
                 DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole')
             AND permissions.class = 1
             AND permissions.major_id =
                 OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_List', N'P')
             AND permissions.permission_name = N'EXECUTE'
             AND permissions.state IN (N'G', N'W')
       )
       OR
       (
           SELECT COUNT_BIG(1)
           FROM sys.database_permissions AS permissions
           WHERE permissions.grantee_principal_id =
                 DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole')
             AND permissions.class = 1
             AND permissions.major_id IN
                 (OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Create', N'P'),
                  OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Get', N'P'),
                  OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetUploadIntent_AcquireFinalize', N'P'),
                  OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetUploadIntent_ReleaseFinalize', N'P'),
                  OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetUploadIntent_RejectFinalize', N'P'),
                  OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Complete', N'P'),
                  OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_MarkQuarantined', N'P'),
                  OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_List', N'P'),
                  OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_UpdateMetadata', N'P'),
                  OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_Reorder', N'P'),
                  OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_Delete', N'P'),
                  OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_GetTrustedContent', N'P'),
                  OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult', N'P'))
             AND permissions.permission_name = N'EXECUTE'
             AND permissions.state IN (N'G', N'W')
       ) <> 13
       OR NOT EXISTS
       (
           SELECT 1
           FROM sys.database_permissions AS permissions
           WHERE permissions.grantee_principal_id =
                 DATABASE_PRINCIPAL_ID(N'FundingPlatform_GeneralWorkerRole')
             AND permissions.class = 1
             AND permissions.major_id =
                 OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult', N'P')
             AND permissions.permission_name = N'EXECUTE'
             AND permissions.state IN (N'G', N'W')
       )
       OR
       (
           SELECT COUNT_BIG(1)
           FROM sys.database_permissions AS permissions
           WHERE permissions.grantee_principal_id =
                 DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole')
             AND permissions.class = 6
             AND permissions.major_id = TYPE_ID(N'dbo.FundingPlatform_ProjectAssetOrderList')
             AND permissions.permission_name IN (N'EXECUTE', N'REFERENCES')
             AND permissions.state IN (N'G', N'W')
       ) <> 2
   )
    THROW 55626, N'Project asset runtime permissions drifted.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke036;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @UserPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @Email NVARCHAR(320) = N'project-assets-' +
        REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'') + N'@example.invalid';

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, Status, PreferredLocale)
    VALUES
        (@UserPublicId, @Email, UPPER(@Email), N'Project asset smoke',
         N'not-a-credential', N'project-assets', 1, 2, N'es-CL');

    DECLARE @Organization TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProfileVersion INT, RowVersion BINARY(8));
    DECLARE @OrganizationSnapshot NVARCHAR(MAX) = N'{"name":"Project asset smoke"}';
    DECLARE @OrganizationContentHash BINARY(32) =
        HASHBYTES('SHA2_256', @OrganizationSnapshot);
    INSERT INTO @Organization EXEC dbo.FundingPlatform_usp_Organization_CreateForUser
        @UserPublicId = @UserPublicId,
        @Name = N'Project asset smoke',
        @HomeCountryId = 152,
        @OrganizationTypeId = 2,
        @SnapshotJson = @OrganizationSnapshot,
        @ContentHash = @OrganizationContentHash;
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
        N'{"title":"Project asset smoke","projectStage":1,"sustainableDevelopmentGoalIds":[1]}';
    DECLARE @ProjectContentHash BINARY(32) = HASHBYTES('SHA2_256', @ProjectSnapshot);
    DECLARE @Project TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProjectVersion INT, RowVersion BINARY(8));
    DECLARE @Slug NVARCHAR(180) = N'project-assets-' +
        REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'');
    INSERT INTO @Project EXEC dbo.FundingPlatform_usp_Project_Create
        @OrganizationPublicId = @OrganizationPublicId,
        @UserPublicId = @UserPublicId,
        @Slug = @Slug,
        @Title = N'Project asset smoke',
        @Summary = N'Smoke de adjuntos privados.',
        @Description = N'Verifica upload durable, cuarentena y confianza.',
        @ProjectStatus = 2,
        @StartDate = '2027-01-01',
        @EndDate = '2027-12-31',
        @BudgetTotal = 100000,
        @ConfirmedFunding = 10000,
        @Currency = 'CLP',
        @SnapshotJson = @ProjectSnapshot,
        @ContentHash = @ProjectContentHash,
        @CountryIds = @CountryIds,
        @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds,
        @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds,
        @ProjectStage = 1,
        @ProjectStageIsSpecified = 1,
        @SustainableDevelopmentGoalIdsJson = N'[1]';

    DECLARE @ProjectId BIGINT = (SELECT Id FROM @Project);
    DECLARE @ProjectPublicId UNIQUEIDENTIFIER = (SELECT PublicId FROM @Project);
    DECLARE @ProjectRowVersion BINARY(8) = (SELECT RowVersion FROM @Project);
    DECLARE @TokenHash BINARY(32) = HASHBYTES('SHA2_256', CONVERT(VARBINARY(16), NEWID()));
    DECLARE @PathPrefix NVARCHAR(37) = LOWER(CONVERT(NVARCHAR(36), NEWID())) + N'/';
    DECLARE @IncomingObject NVARCHAR(1024) = @PathPrefix + REPLICATE(N'a', 32) + N'.png';
    DECLARE @QuarantineObject NVARCHAR(1024) =
        LOWER(CONVERT(NVARCHAR(36), NEWID())) + N'/' + REPLICATE(N'b', 32) + N'.png';
    DECLARE @TrustedObject NVARCHAR(1024) =
        LOWER(CONVERT(NVARCHAR(36), NEWID())) + N'/' + REPLICATE(N'c', 32) + N'.png';
    DECLARE @IntentExpiresAtUtc DATETIME2(3) = DATEADD(MINUTE, 4, SYSUTCDATETIME());

    EXEC dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Create
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @UserPublicId = @UserPublicId,
        @ExpectedProjectRowVersion = @ProjectRowVersion,
        @Kind = 0,
        @OriginalFileName = N'impacto.png',
        @DeclaredMimeType = N'image/png',
        @ExpectedContentLength = 1024,
        @MaxContentLength = 10485760,
        @IncomingBlobContainer = N'project-incoming',
        @IncomingBlobObjectName = @IncomingObject,
        @QuarantineBlobContainer = N'project-quarantine',
        @QuarantineBlobObjectName = @QuarantineObject,
        @TrustedBlobContainer = N'project-trusted',
        @TrustedBlobObjectName = @TrustedObject,
        @CompletionTokenHash = @TokenHash,
        @ExpiresAtUtc = @IntentExpiresAtUtc;

    DECLARE @IntentPublicId UNIQUEIDENTIFIER =
        (SELECT PublicId
         FROM dbo.FundingPlatform_ProjectAssetUploadIntents
         WHERE ProjectId = @ProjectId AND CompletionTokenHash = @TokenHash);
    IF @IntentPublicId IS NULL
        THROW 55627, N'Project asset upload intent creation failed.', 1;

    SET @ProjectRowVersion =
        (SELECT RowVersion FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId);
    DECLARE @LeaseId UNIQUEIDENTIFIER = NEWID();
    DECLARE @RequestedLeaseUntilUtc DATETIME2(3) = DATEADD(MINUTE, 5, SYSUTCDATETIME());
    EXEC dbo.FundingPlatform_usp_ProjectAssetUploadIntent_AcquireFinalize
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @UserPublicId = @UserPublicId,
        @IntentPublicId = @IntentPublicId,
        @CompletionTokenHash = @TokenHash,
        @LeaseId = @LeaseId,
        @LeaseUntilUtc = @RequestedLeaseUntilUtc;

    IF NOT EXISTS
    (
        SELECT 1 FROM dbo.FundingPlatform_ProjectAssetUploadIntents
        WHERE PublicId = @IntentPublicId AND Status = 1
          AND FinalizeLeaseId = @LeaseId
          AND FinalizeLeaseUntilUtc <= ExpiresAtUtc
    )
        THROW 55628, N'Project asset finalize lease acquisition failed.', 1;

    DECLARE @AssetHash BINARY(32) = HASHBYTES('SHA2_256', 0x89504E470D0A1A0A);
    EXEC dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Complete
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @UserPublicId = @UserPublicId,
        @IntentPublicId = @IntentPublicId,
        @LeaseId = @LeaseId,
        @ExpectedProjectRowVersion = @ProjectRowVersion,
        @VerifiedMimeType = N'image/png',
        @ActualContentLength = 1024,
        @ContentHash = @AssetHash,
        @ScanProvider = 0,
        @PixelWidth = 800,
        @PixelHeight = 600;

    DECLARE @AssetId BIGINT =
        (SELECT CompletedProjectAssetId
         FROM dbo.FundingPlatform_ProjectAssetUploadIntents
         WHERE PublicId = @IntentPublicId AND Status = 2);
    DECLARE @AssetPublicId UNIQUEIDENTIFIER =
        (SELECT PublicId FROM dbo.FundingPlatform_ProjectAssets WHERE Id = @AssetId);
    IF @AssetPublicId IS NULL
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssets
           WHERE Id = @AssetId AND StorageStatus = 0 AND ScanStatus = 0
             AND PixelWidth = 800 AND PixelHeight = 600)
        THROW 55629, N'Project asset completion failed closed.', 1;

    DECLARE @AssetRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_ProjectAssets WHERE Id = @AssetId);
    SET @ProjectRowVersion =
        (SELECT RowVersion FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId);
    EXEC dbo.FundingPlatform_usp_ProjectAsset_UpdateMetadata
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @UserPublicId = @UserPublicId,
        @AssetPublicId = @AssetPublicId,
        @ExpectedAssetRowVersion = @AssetRowVersion,
        @ExpectedProjectRowVersion = @ProjectRowVersion,
        @DisplayName = N'Portada todavía insegura',
        @AltText = N'Esta imagen aún no supera el análisis',
        @Caption = NULL,
        @IsCover = 1;

    IF EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ProjectAssets
        WHERE Id = @AssetId AND IsCover = 1)
        THROW 55634, N'An untrusted project image must not become the cover.', 1;

    EXEC dbo.FundingPlatform_usp_ProjectAsset_MarkQuarantined
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @UserPublicId = @UserPublicId,
        @AssetPublicId = @AssetPublicId,
        @ExpectedAssetRowVersion = @AssetRowVersion,
        @QuarantineBlobETag = N'"quarantine-etag"',
        @QuarantineBlobVersionId = N'quarantine-version';

    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ProjectAssets
        WHERE Id = @AssetId AND StorageStatus = 1 AND ScanStatus = 0
          AND QuarantineBlobETag = N'"quarantine-etag"')
        THROW 55630, N'Project asset quarantine receipt failed.', 1;

    DECLARE @ScanPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'development-fake-clean-036');
    DECLARE @ScanOccurredAtUtc DATETIME2(3) = SYSUTCDATETIME();
    EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
        @AssetPublicId = @AssetPublicId,
        @ScanProvider = 0,
        @ProviderEventId = N'development-fake-clean-036',
        @PayloadHash = @ScanPayloadHash,
        @QuarantineBlobETag = N'"quarantine-etag"',
        @ReportedContentHash = @AssetHash,
        @ToStatus = 1,
        @ResultCode = N'clean',
        @OccurredAtUtc = @ScanOccurredAtUtc,
        @TrustedBlobContainer = N'project-trusted',
        @TrustedBlobObjectName = @TrustedObject,
        @TrustedBlobETag = N'"trusted-etag"',
        @TrustedBlobVersionId = N'trusted-version';

    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ProjectAssets
        WHERE Id = @AssetId AND StorageStatus = 2 AND ScanStatus = 1
          AND TrustedBlobObjectName = @TrustedObject
          AND TrustedBlobETag = N'"trusted-etag"')
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_ProjectAssetScanEvents
           WHERE ProjectAssetId = @AssetId) <> 1
        THROW 55631, N'Project asset clean promotion failed.', 1;

    EXEC dbo.FundingPlatform_usp_ProjectAsset_List
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @UserPublicId = @UserPublicId;
    EXEC dbo.FundingPlatform_usp_ProjectAsset_GetTrustedContent
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @UserPublicId = @UserPublicId,
        @AssetPublicId = @AssetPublicId;

    SET @AssetRowVersion =
        (SELECT RowVersion FROM dbo.FundingPlatform_ProjectAssets WHERE Id = @AssetId);
    SET @ProjectRowVersion =
        (SELECT RowVersion FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId);
    EXEC dbo.FundingPlatform_usp_ProjectAsset_UpdateMetadata
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @UserPublicId = @UserPublicId,
        @AssetPublicId = @AssetPublicId,
        @ExpectedAssetRowVersion = @AssetRowVersion,
        @ExpectedProjectRowVersion = @ProjectRowVersion,
        @DisplayName = N'Imagen de impacto',
        @AltText = N'Personas participando en una actividad comunitaria',
        @Caption = N'Actividad piloto',
        @IsCover = 1;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ProjectAssets
        WHERE Id = @AssetId AND IsCover = 1
          AND AltText = N'Personas participando en una actividad comunitaria')
        THROW 55632, N'Project asset cover metadata failed.', 1;

    SET @AssetRowVersion =
        (SELECT RowVersion FROM dbo.FundingPlatform_ProjectAssets WHERE Id = @AssetId);
    SET @ProjectRowVersion =
        (SELECT RowVersion FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId);
    EXEC dbo.FundingPlatform_usp_ProjectAsset_Delete
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @UserPublicId = @UserPublicId,
        @AssetPublicId = @AssetPublicId,
        @ExpectedAssetRowVersion = @AssetRowVersion,
        @ExpectedProjectRowVersion = @ProjectRowVersion;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ProjectAssets
        WHERE Id = @AssetId AND IsDeleted = 1 AND IsCover = 0
          AND DeletedAtUtc IS NOT NULL)
        THROW 55633, N'Project asset logical delete failed.', 1;

    DECLARE @AttemptsBeforeDeletedReplay SMALLINT =
        (SELECT FinalizeAttemptCount
         FROM dbo.FundingPlatform_ProjectAssetUploadIntents
         WHERE PublicId = @IntentPublicId);
    DECLARE @DeletedReplayLeaseId UNIQUEIDENTIFIER = NEWID();
    DECLARE @DeletedReplayLeaseUntilUtc DATETIME2(3) =
        DATEADD(MINUTE, 1, SYSUTCDATETIME());
    EXEC dbo.FundingPlatform_usp_ProjectAssetUploadIntent_AcquireFinalize
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @UserPublicId = @UserPublicId,
        @IntentPublicId = @IntentPublicId,
        @CompletionTokenHash = @TokenHash,
        @LeaseId = @DeletedReplayLeaseId,
        @LeaseUntilUtc = @DeletedReplayLeaseUntilUtc;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ProjectAssetUploadIntents
        WHERE PublicId = @IntentPublicId AND Status = 2
          AND FinalizeAttemptCount = @AttemptsBeforeDeletedReplay)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectAssets
           WHERE Id = @AssetId AND IsDeleted = 1)
        THROW 55635, N'Deleted project asset replay must remain inert.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke036;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FP_Smoke036;
    THROW;
END CATCH;

SELECT CAST(1 AS BIT) AS Succeeded;
