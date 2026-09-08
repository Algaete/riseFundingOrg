/* FundingPlatform - project-asset trusted-content manifests and image sanitization (038).
   Requires migrations 001-037.

   Original/quarantine metadata remains immutable evidence. Trusted metadata describes
   the bytes that may be served after PDF copying or bounded image decode/re-encoding.
   A provider Clean observation may be converted to a local Failed result only for
   the exact image-sanitizer rejection codes enumerated below. Defender facts must
   still match their authenticated receipt exactly.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF OBJECT_ID(N'dbo.FundingPlatform_ProjectAssets', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetScanEvents', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetDefenderReceipts', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetUploadIntents', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_OutboxMessages', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_GetTrustedContent', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_List', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetScan_WatchdogTimeout', N'P') IS NULL
   OR OBJECT_ID(
          N'dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Finalize', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge', N'P') IS NULL
    THROW 55801, N'Project asset image sanitization requires migrations 001-037.', 1;

IF COL_LENGTH(N'dbo.FundingPlatform_ProjectAssets', N'TrustedContentHash') IS NOT NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_ProjectAssetScanEvents',
                 N'RevokedTrustedContentHash') IS NOT NULL
    THROW 55802, N'Project asset image sanitization migration was already applied or is partial.', 1;

DECLARE @MigrationUtc DATETIME2(3) = SYSUTCDATETIME();
DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_ProjectSanitization038;

BEGIN TRY
    ALTER TABLE dbo.FundingPlatform_ProjectAssets
        DROP CONSTRAINT FundingPlatform_CK_ProjectAssets_TrustedState;
    ALTER TABLE dbo.FundingPlatform_ProjectAssets
        DROP CONSTRAINT FundingPlatform_CK_ProjectAssets_TrustedObject;
    ALTER TABLE dbo.FundingPlatform_ProjectAssetScanEvents
        DROP CONSTRAINT FundingPlatform_CK_ProjectAssetScanEvents_Status;
    ALTER TABLE dbo.FundingPlatform_ProjectAssetScanEvents
        DROP CONSTRAINT FundingPlatform_CK_ProjectAssetScanEvents_Result;

    ALTER TABLE dbo.FundingPlatform_ProjectAssets ADD
        TrustedMimeType NVARCHAR(100) NULL,
        TrustedContentLength BIGINT NULL,
        TrustedContentHash BINARY(32) NULL,
        TrustedPixelWidth INT NULL,
        TrustedPixelHeight INT NULL,
        TrustedProcessingVersion NVARCHAR(100) NULL,
        TrustedCreatedAtUtc DATETIME2(3) NULL;

    ALTER TABLE dbo.FundingPlatform_ProjectAssetScanEvents ADD
        ProviderObservedStatus TINYINT NULL,
        ProviderResultCode NVARCHAR(100) NULL,
        RevokedTrustedMimeType NVARCHAR(100) NULL,
        RevokedTrustedContentLength BIGINT NULL,
        RevokedTrustedContentHash BINARY(32) NULL,
        RevokedTrustedPixelWidth INT NULL,
        RevokedTrustedPixelHeight INT NULL,
        RevokedTrustedProcessingVersion NVARCHAR(100) NULL,
        RevokedTrustedCreatedAtUtc DATETIME2(3) NULL;

    /* Historical scan events had one status/result domain. Preserve it exactly. */
    UPDATE dbo.FundingPlatform_ProjectAssetScanEvents
    SET ProviderObservedStatus = ToStatus,
        ProviderResultCode = ResultCode;

    /* 037 copied trusted bytes without transforming them. Preserve the complete
       revoked snapshot while explicitly distinguishing old images from sanitized ones. */
    UPDATE scanEvents
    SET RevokedTrustedMimeType = LOWER(assets.VerifiedMimeType),
        RevokedTrustedContentLength = assets.ContentLength,
        RevokedTrustedContentHash = assets.ContentHash,
        RevokedTrustedPixelWidth = assets.PixelWidth,
        RevokedTrustedPixelHeight = assets.PixelHeight,
        RevokedTrustedProcessingVersion =
            CASE WHEN assets.Kind = 1 THEN N'pdf-copy-v1'
                 ELSE N'legacy-unsanitized-v0' END,
        RevokedTrustedCreatedAtUtc = COALESCE
        (
            (SELECT MAX(cleanEvents.OccurredAtUtc)
             FROM dbo.FundingPlatform_ProjectAssetScanEvents AS cleanEvents
             WHERE cleanEvents.ProjectAssetId = scanEvents.ProjectAssetId
               AND cleanEvents.FromStatus = 0 AND cleanEvents.ToStatus = 1
               AND cleanEvents.OccurredAtUtc <= scanEvents.OccurredAtUtc),
            assets.CreatedAtUtc
        )
    FROM dbo.FundingPlatform_ProjectAssetScanEvents AS scanEvents
    INNER JOIN dbo.FundingPlatform_ProjectAssets AS assets
        ON assets.Id = scanEvents.ProjectAssetId
    WHERE scanEvents.FromStatus = 1;

    /* A PDF copy retains its byte manifest. Existing trusted PDFs are therefore
       safe to upgrade without pretending that an image sanitizer processed them. */
    UPDATE dbo.FundingPlatform_ProjectAssets
    SET TrustedMimeType = LOWER(VerifiedMimeType),
        TrustedContentLength = ContentLength,
        TrustedContentHash = ContentHash,
        TrustedPixelWidth = NULL,
        TrustedPixelHeight = NULL,
        TrustedProcessingVersion = N'pdf-copy-v1',
        TrustedCreatedAtUtc = COALESCE(ScanCompletedAtUtc, CreatedAtUtc)
    WHERE StorageStatus = 2 AND ScanStatus = 1 AND Kind = 1;

    DECLARE @LegacyImages TABLE
    (
        ProjectAssetId BIGINT NOT NULL PRIMARY KEY,
        ProjectId BIGINT NOT NULL,
        AssetPublicId UNIQUEIDENTIFIER NOT NULL,
        ScanProvider TINYINT NOT NULL,
        QuarantineBlobETag NVARCHAR(100) NOT NULL,
        ContentHash BINARY(32) NOT NULL,
        OriginalScanResultCode NVARCHAR(100) NULL,
        RevokedTrustedBlobContainer NVARCHAR(63) NOT NULL,
        RevokedTrustedBlobObjectName NVARCHAR(1024) NOT NULL,
        RevokedTrustedBlobETag NVARCHAR(100) NOT NULL,
        RevokedTrustedBlobVersionId NVARCHAR(200) NULL,
        RevokedTrustedMimeType NVARCHAR(100) NOT NULL,
        RevokedTrustedContentLength BIGINT NOT NULL,
        RevokedTrustedContentHash BINARY(32) NOT NULL,
        RevokedTrustedPixelWidth INT NOT NULL,
        RevokedTrustedPixelHeight INT NOT NULL,
        RevokedTrustedCreatedAtUtc DATETIME2(3) NOT NULL,
        ResultRowVersion BINARY(8) NOT NULL,
        EventId UNIQUEIDENTIFIER NULL,
        ProviderEventId NVARCHAR(200) NULL,
        ProviderResultCode NVARCHAR(100) NULL
    );

    /* Images trusted before 038 were raw copies. Revoke them fail closed and
       retain their opaque blob identity plus legacy manifest for physical cleanup. */
    UPDATE assets
    SET StorageStatus = 3,
        ScanStatus = 3,
        ScanResultCode = N'legacy-image-unsanitized',
        ScanCompletedAtUtc = @MigrationUtc,
        TrustedBlobContainer = NULL,
        TrustedBlobObjectName = NULL,
        TrustedBlobETag = NULL,
        TrustedBlobVersionId = NULL,
        TrustedMimeType = NULL,
        TrustedContentLength = NULL,
        TrustedContentHash = NULL,
        TrustedPixelWidth = NULL,
        TrustedPixelHeight = NULL,
        TrustedProcessingVersion = NULL,
        TrustedCreatedAtUtc = NULL,
        IsCover = 0,
        UpdatedAtUtc = @MigrationUtc
    OUTPUT deleted.Id, deleted.ProjectId, deleted.PublicId,
           deleted.ScanProvider, deleted.QuarantineBlobETag, deleted.ContentHash,
           deleted.ScanResultCode,
           deleted.TrustedBlobContainer, deleted.TrustedBlobObjectName,
           deleted.TrustedBlobETag, deleted.TrustedBlobVersionId,
           LOWER(deleted.VerifiedMimeType), deleted.ContentLength, deleted.ContentHash,
           deleted.PixelWidth, deleted.PixelHeight,
           COALESCE(deleted.ScanCompletedAtUtc, deleted.CreatedAtUtc),
           inserted.RowVersion
    INTO @LegacyImages
        (ProjectAssetId, ProjectId, AssetPublicId, ScanProvider,
         QuarantineBlobETag, ContentHash, OriginalScanResultCode,
         RevokedTrustedBlobContainer, RevokedTrustedBlobObjectName,
         RevokedTrustedBlobETag, RevokedTrustedBlobVersionId,
         RevokedTrustedMimeType, RevokedTrustedContentLength,
         RevokedTrustedContentHash, RevokedTrustedPixelWidth,
         RevokedTrustedPixelHeight, RevokedTrustedCreatedAtUtc,
         ResultRowVersion)
    FROM dbo.FundingPlatform_ProjectAssets AS assets
    WHERE assets.StorageStatus = 2 AND assets.ScanStatus = 1 AND assets.Kind = 0;

    UPDATE legacy
    SET EventId = NEWID(),
        ProviderEventId = N'migration-038-legacy-image:'
                          + CONVERT(NVARCHAR(36), legacy.AssetPublicId),
        ProviderResultCode = COALESCE
        (
            (SELECT TOP (1) cleanEvents.ProviderResultCode
             FROM dbo.FundingPlatform_ProjectAssetScanEvents AS cleanEvents
             WHERE cleanEvents.ProjectAssetId = legacy.ProjectAssetId
               AND cleanEvents.FromStatus = 0 AND cleanEvents.ToStatus = 1
             ORDER BY cleanEvents.OccurredAtUtc DESC, cleanEvents.Id DESC),
            legacy.OriginalScanResultCode,
            N'clean'
        )
    FROM @LegacyImages AS legacy;

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
    SELECT legacy.EventId, legacy.ProjectAssetId, legacy.ScanProvider,
           legacy.ProviderEventId,
           HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
               legacy.ProviderEventId COLLATE Latin1_General_100_BIN2_UTF8))),
           1, 3, 1, legacy.QuarantineBlobETag, legacy.ContentHash,
           N'legacy-image-unsanitized', legacy.ProviderResultCode,
           legacy.ResultRowVersion, @MigrationUtc, @MigrationUtc,
           legacy.RevokedTrustedBlobContainer,
           legacy.RevokedTrustedBlobObjectName,
           legacy.RevokedTrustedBlobETag,
           legacy.RevokedTrustedBlobVersionId,
           legacy.RevokedTrustedMimeType,
           legacy.RevokedTrustedContentLength,
           legacy.RevokedTrustedContentHash,
           legacy.RevokedTrustedPixelWidth,
           legacy.RevokedTrustedPixelHeight,
           N'legacy-unsanitized-v0',
           legacy.RevokedTrustedCreatedAtUtc
    FROM @LegacyImages AS legacy;

    INSERT INTO dbo.FundingPlatform_OutboxMessages
        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
         OccurredAtUtc, AvailableAtUtc)
    SELECT legacy.EventId, N'ProjectAssetLegacyTrustRevoked', N'ProjectAsset',
           CONVERT(NVARCHAR(100), legacy.AssetPublicId),
           (SELECT legacy.EventId AS eventId,
                   legacy.AssetPublicId AS assetPublicId,
                   CAST(3 AS TINYINT) AS scanStatus,
                   CAST(3 AS TINYINT) AS storageStatus,
                   N'legacy-image-unsanitized' AS resultCode,
                   legacy.RevokedTrustedBlobContainer AS revokedTrustedBlobContainer,
                   legacy.RevokedTrustedBlobObjectName AS revokedTrustedBlobObjectName,
                   legacy.RevokedTrustedBlobETag AS revokedTrustedBlobETag,
                   legacy.RevokedTrustedBlobVersionId AS revokedTrustedBlobVersionId,
                   legacy.RevokedTrustedMimeType AS revokedTrustedMimeType,
                   legacy.RevokedTrustedContentLength AS revokedTrustedContentLength,
                   CONVERT(VARCHAR(64), legacy.RevokedTrustedContentHash, 2)
                       AS revokedTrustedContentHashSha256,
                   legacy.RevokedTrustedPixelWidth AS revokedTrustedPixelWidth,
                   legacy.RevokedTrustedPixelHeight AS revokedTrustedPixelHeight,
                   N'legacy-unsanitized-v0' AS revokedTrustedProcessingVersion,
                   legacy.RevokedTrustedCreatedAtUtc AS revokedTrustedCreatedAtUtc
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
           @MigrationUtc, @MigrationUtc
    FROM @LegacyImages AS legacy;

    UPDATE projects
    SET UpdatedAtUtc = @MigrationUtc
    FROM dbo.FundingPlatform_Projects AS projects
    WHERE EXISTS (SELECT 1 FROM @LegacyImages AS legacy
                  WHERE legacy.ProjectId = projects.Id);

    ALTER TABLE dbo.FundingPlatform_ProjectAssetScanEvents
        ALTER COLUMN ProviderObservedStatus TINYINT NOT NULL;
    ALTER TABLE dbo.FundingPlatform_ProjectAssetScanEvents
        ALTER COLUMN ProviderResultCode NVARCHAR(100) NOT NULL;

    ALTER TABLE dbo.FundingPlatform_ProjectAssets WITH CHECK
        ADD CONSTRAINT FundingPlatform_CK_ProjectAssets_TrustedState
        CHECK
        (
            (StorageStatus = 2 AND ScanStatus = 1
             AND NULLIF(LTRIM(RTRIM(TrustedBlobContainer)), N'') IS NOT NULL
             AND NULLIF(LTRIM(RTRIM(TrustedBlobObjectName)), N'') IS NOT NULL
             AND NULLIF(LTRIM(RTRIM(TrustedBlobETag)), N'') IS NOT NULL
             AND NOT (TrustedBlobContainer = QuarantineBlobContainer
                      AND TrustedBlobObjectName = QuarantineBlobObjectName))
            OR
            (StorageStatus <> 2 AND ScanStatus <> 1
             AND TrustedBlobContainer IS NULL AND TrustedBlobObjectName IS NULL
             AND TrustedBlobETag IS NULL AND TrustedBlobVersionId IS NULL)
        );

    ALTER TABLE dbo.FundingPlatform_ProjectAssets WITH CHECK
        ADD CONSTRAINT FundingPlatform_CK_ProjectAssets_TrustedObject
        CHECK
        (
            TrustedBlobObjectName IS NULL
            OR
            (TRY_CONVERT(UNIQUEIDENTIFIER, LEFT(TrustedBlobObjectName, 36)) IS NOT NULL
             AND SUBSTRING(TrustedBlobObjectName, 37, 1) = N'/'
             AND SUBSTRING(TrustedBlobObjectName, 38, 32) =
                 LOWER(SUBSTRING(TrustedBlobObjectName, 38, 32))
             AND SUBSTRING(TrustedBlobObjectName, 38, 32)
                 COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[^0-9a-f]%'
             AND SUBSTRING(TrustedBlobObjectName, 70, 1) = N'.'
             AND CHARINDEX(N'/', TrustedBlobObjectName, 38) = 0
             AND CHARINDEX(N'\', TrustedBlobObjectName) = 0
             AND CHARINDEX(N'?', TrustedBlobObjectName) = 0
             AND CHARINDEX(N'#', TrustedBlobObjectName) = 0
             AND
             (
                 (LOWER(TrustedMimeType) = N'image/jpeg'
                  AND (RIGHT(LOWER(TrustedBlobObjectName), 4) = N'.jpg'
                       OR RIGHT(LOWER(TrustedBlobObjectName), 5) = N'.jpeg')
                  AND LEN(TrustedBlobObjectName) IN (73, 74))
                 OR (LOWER(TrustedMimeType) = N'image/png'
                     AND RIGHT(LOWER(TrustedBlobObjectName), 4) = N'.png'
                     AND LEN(TrustedBlobObjectName) = 73)
                 OR (LOWER(TrustedMimeType) = N'image/webp'
                     AND RIGHT(LOWER(TrustedBlobObjectName), 5) = N'.webp'
                     AND LEN(TrustedBlobObjectName) = 74)
                 OR (LOWER(TrustedMimeType) = N'application/pdf'
                     AND RIGHT(LOWER(TrustedBlobObjectName), 4) = N'.pdf'
                     AND LEN(TrustedBlobObjectName) = 73)
             ))
        );

    ALTER TABLE dbo.FundingPlatform_ProjectAssets WITH CHECK
        ADD CONSTRAINT FundingPlatform_CK_ProjectAssets_TrustedManifest
        CHECK
        (
            (StorageStatus <> 2
             AND TrustedMimeType IS NULL
             AND TrustedContentLength IS NULL
             AND TrustedContentHash IS NULL
             AND TrustedPixelWidth IS NULL
             AND TrustedPixelHeight IS NULL
             AND TrustedProcessingVersion IS NULL
             AND TrustedCreatedAtUtc IS NULL)
            OR
            (StorageStatus = 2
             AND TrustedMimeType IS NOT NULL
             AND TrustedMimeType COLLATE Latin1_General_100_BIN2 =
                 LOWER(TrustedMimeType) COLLATE Latin1_General_100_BIN2
             AND TrustedContentLength IS NOT NULL
             AND TrustedContentHash IS NOT NULL
             AND TrustedProcessingVersion IS NOT NULL
             AND TrustedCreatedAtUtc IS NOT NULL
             AND TrustedCreatedAtUtc >= CreatedAtUtc
             AND
             (
                 (Kind = 0
                  AND TrustedMimeType IN (N'image/jpeg', N'image/png', N'image/webp')
                  AND TrustedMimeType COLLATE Latin1_General_100_BIN2 =
                      LOWER(VerifiedMimeType) COLLATE Latin1_General_100_BIN2
                  AND TrustedContentLength BETWEEN 1 AND 10485760
                  AND TrustedPixelWidth IS NOT NULL
                  AND TrustedPixelHeight IS NOT NULL
                  AND TrustedPixelWidth BETWEEN 1 AND 32768
                  AND TrustedPixelHeight BETWEEN 1 AND 32768
                  AND CONVERT(BIGINT, TrustedPixelWidth)
                      * CONVERT(BIGINT, TrustedPixelHeight) <= 25000000
                  AND TrustedProcessingVersion = N'skia-4.151.2-image-v1')
                 OR
                 (Kind = 1
                  AND TrustedMimeType = N'application/pdf'
                  AND TrustedMimeType COLLATE Latin1_General_100_BIN2 =
                      LOWER(VerifiedMimeType) COLLATE Latin1_General_100_BIN2
                  AND TrustedContentLength BETWEEN 1 AND 26214400
                  AND TrustedContentLength = ContentLength
                  AND TrustedContentHash = ContentHash
                  AND TrustedPixelWidth IS NULL
                  AND TrustedPixelHeight IS NULL
                  AND TrustedProcessingVersion = N'pdf-copy-v1')
             ))
        );

    ALTER TABLE dbo.FundingPlatform_ProjectAssetScanEvents WITH CHECK
        ADD CONSTRAINT FundingPlatform_CK_ProjectAssetScanEvents_Status
        CHECK
        (
            ScanProvider BETWEEN 0 AND 1
            AND
            (
                (FromStatus = 0 AND ToStatus BETWEEN 1 AND 4)
                OR
                (FromStatus = 1
                 AND ((ScanProvider = 1 AND ToStatus BETWEEN 2 AND 4)
                      OR (ToStatus = 3
                          AND ResultCode COLLATE Latin1_General_100_BIN2 =
                              N'legacy-image-unsanitized')))
            )
        );

    ALTER TABLE dbo.FundingPlatform_ProjectAssetScanEvents WITH CHECK
        ADD CONSTRAINT FundingPlatform_CK_ProjectAssetScanEvents_Result
        CHECK
        (
            NULLIF(LTRIM(RTRIM(ProviderEventId)), N'') IS NOT NULL
            AND NULLIF(LTRIM(RTRIM(QuarantineBlobETag)), N'') IS NOT NULL
            AND NULLIF(LTRIM(RTRIM(ResultCode)), N'') IS NOT NULL
            AND NULLIF(LTRIM(RTRIM(ProviderResultCode)), N'') IS NOT NULL
            AND CHARINDEX(CHAR(10), ProviderEventId) = 0
            AND CHARINDEX(CHAR(13), ProviderEventId) = 0
            AND LEFT(QuarantineBlobETag, 1) = N'"'
            AND RIGHT(QuarantineBlobETag, 1) = N'"'
            AND CHARINDEX(CHAR(10), QuarantineBlobETag) = 0
            AND CHARINDEX(CHAR(13), QuarantineBlobETag) = 0
            AND CHARINDEX(CHAR(10), ResultCode) = 0
            AND CHARINDEX(CHAR(13), ResultCode) = 0
            AND CHARINDEX(CHAR(10), ProviderResultCode) = 0
            AND CHARINDEX(CHAR(13), ProviderResultCode) = 0
            AND ProviderObservedStatus BETWEEN 1 AND 4
            AND (ProviderObservedStatus NOT IN (1, 2) OR ReportedContentHash IS NOT NULL)
            AND
            (
                (ProviderObservedStatus = ToStatus
                 AND ProviderResultCode COLLATE Latin1_General_100_BIN2 =
                     ResultCode COLLATE Latin1_General_100_BIN2)
                OR
                (ScanProvider BETWEEN 0 AND 1 AND FromStatus = 0
                 AND ProviderObservedStatus = 1 AND ToStatus = 3
                 AND ResultCode COLLATE Latin1_General_100_BIN2 IN
                     (N'image-format-rejected', N'image-decode-rejected',
                      N'image-frame-count-rejected', N'image-dimensions-rejected',
                      N'image-output-too-large'))
                OR
                (FromStatus = 1 AND ProviderObservedStatus = 1 AND ToStatus = 3
                 AND ResultCode COLLATE Latin1_General_100_BIN2 =
                     N'legacy-image-unsanitized')
            )
            AND
            (
                (FromStatus = 0
                 AND RevokedTrustedBlobContainer IS NULL
                 AND RevokedTrustedBlobObjectName IS NULL
                 AND RevokedTrustedBlobETag IS NULL
                 AND RevokedTrustedBlobVersionId IS NULL
                 AND RevokedTrustedMimeType IS NULL
                 AND RevokedTrustedContentLength IS NULL
                 AND RevokedTrustedContentHash IS NULL
                 AND RevokedTrustedPixelWidth IS NULL
                 AND RevokedTrustedPixelHeight IS NULL
                 AND RevokedTrustedProcessingVersion IS NULL
                 AND RevokedTrustedCreatedAtUtc IS NULL)
                OR
                (FromStatus = 1
                 AND NULLIF(LTRIM(RTRIM(RevokedTrustedBlobContainer)), N'') IS NOT NULL
                 AND NULLIF(LTRIM(RTRIM(RevokedTrustedBlobObjectName)), N'') IS NOT NULL
                 AND NULLIF(LTRIM(RTRIM(RevokedTrustedBlobETag)), N'') IS NOT NULL
                 AND RevokedTrustedMimeType IS NOT NULL
                 AND RevokedTrustedContentLength IS NOT NULL
                 AND RevokedTrustedContentHash IS NOT NULL
                 AND RevokedTrustedProcessingVersion IS NOT NULL
                 AND RevokedTrustedCreatedAtUtc IS NOT NULL
                 AND CHARINDEX(N'&', RevokedTrustedBlobContainer) = 0
                 AND CHARINDEX(N'#', RevokedTrustedBlobContainer) = 0
                 AND CHARINDEX(N'?', RevokedTrustedBlobContainer) = 0
                 AND CHARINDEX(N'&', RevokedTrustedBlobObjectName) = 0
                 AND CHARINDEX(N'#', RevokedTrustedBlobObjectName) = 0
                 AND CHARINDEX(N'?', RevokedTrustedBlobObjectName) = 0
                 AND
                 (
                     (ResultCode COLLATE Latin1_General_100_BIN2 =
                          N'legacy-image-unsanitized'
                      AND CHARINDEX(CHAR(10),
                          COALESCE(RevokedTrustedBlobVersionId, N'')) = 0
                      AND CHARINDEX(CHAR(13),
                          COALESCE(RevokedTrustedBlobVersionId, N'')) = 0)
                     OR
                     (ResultCode COLLATE Latin1_General_100_BIN2 <>
                          N'legacy-image-unsanitized'
                      AND NULLIF(LTRIM(RTRIM(RevokedTrustedBlobVersionId)), N'')
                          IS NOT NULL
                      AND CHARINDEX(N'&', RevokedTrustedBlobVersionId) = 0
                      AND CHARINDEX(N'#', RevokedTrustedBlobVersionId) = 0
                      AND CHARINDEX(N'?', RevokedTrustedBlobVersionId) = 0)
                 )
                 AND
                 (
                     (RevokedTrustedMimeType IN
                          (N'image/jpeg', N'image/png', N'image/webp')
                      AND RevokedTrustedContentLength BETWEEN 1 AND 10485760
                      AND RevokedTrustedPixelWidth IS NOT NULL
                      AND RevokedTrustedPixelHeight IS NOT NULL
                      AND RevokedTrustedPixelWidth BETWEEN 1 AND 32768
                      AND RevokedTrustedPixelHeight BETWEEN 1 AND 32768
                      AND CONVERT(BIGINT, RevokedTrustedPixelWidth)
                          * CONVERT(BIGINT, RevokedTrustedPixelHeight) <= 25000000
                      AND RevokedTrustedProcessingVersion IN
                          (N'skia-4.151.2-image-v1', N'legacy-unsanitized-v0'))
                     OR
                     (RevokedTrustedMimeType = N'application/pdf'
                      AND RevokedTrustedContentLength BETWEEN 1 AND 26214400
                      AND RevokedTrustedPixelWidth IS NULL
                      AND RevokedTrustedPixelHeight IS NULL
                      AND RevokedTrustedProcessingVersion = N'pdf-copy-v1')
                 ))
            )
        );

    IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FP_ProjectSanitization038;
    THROW;
END CATCH;

IF DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole') IS NULL
   OR DATABASE_PRINCIPAL_ID(N'FundingPlatform_GeneralWorkerRole') IS NULL
    THROW 55808, N'Project asset image sanitization requires migration 027 roles.', 1;

IF EXISTS
(
    SELECT 1
    FROM sys.database_permissions AS permissions
    WHERE permissions.grantee_principal_id IN
          (DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole'),
           DATABASE_PRINCIPAL_ID(N'FundingPlatform_GeneralWorkerRole'))
      AND permissions.class = 1
      AND permissions.major_id IN
          (OBJECT_ID(N'dbo.FundingPlatform_ProjectAssets', N'U'),
           OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetScanEvents', N'U'),
           OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetDefenderReceipts', N'U'))
      AND permissions.permission_name IN (N'SELECT', N'INSERT', N'UPDATE', N'DELETE')
      AND permissions.state IN (N'G', N'W')
)
    THROW 55809, N'Runtime roles must not have direct sanitization table access.', 1;

IF (SELECT COUNT_BIG(1)
    FROM sys.database_permissions
    WHERE grantee_principal_id =
          DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole')) <> 162
   OR (SELECT COUNT_BIG(1)
       FROM sys.database_permissions
       WHERE grantee_principal_id =
             DATABASE_PRINCIPAL_ID(N'FundingPlatform_GeneralWorkerRole')) <> 53
    THROW 55810, N'Runtime role permissions do not match the sanitization allowlist.', 1;
GO

/* ProviderObserved* preserves the provider fact. ToStatus/ResultCode is the
   effective application result. They differ only for a bounded sanitizer rejection;
   Defender additionally requires an exact authenticated Clean receipt. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
    @AssetPublicId UNIQUEIDENTIFIER,
    @ScanProvider TINYINT,
    @ProviderEventId NVARCHAR(200),
    @PayloadHash BINARY(32),
    @QuarantineBlobETag NVARCHAR(100),
    @ReportedContentHash BINARY(32) = NULL,
    @ToStatus TINYINT,
    @ResultCode NVARCHAR(100),
    @OccurredAtUtc DATETIME2(3),
    @ProviderObservedStatus TINYINT = NULL,
    @ProviderResultCode NVARCHAR(100) = NULL,
    @TrustedBlobContainer NVARCHAR(63) = NULL,
    @TrustedBlobObjectName NVARCHAR(1024) = NULL,
    @TrustedBlobETag NVARCHAR(100) = NULL,
    @TrustedBlobVersionId NVARCHAR(200) = NULL,
    @TrustedMimeType NVARCHAR(100) = NULL,
    @TrustedContentLength BIGINT = NULL,
    @TrustedContentHash BINARY(32) = NULL,
    @TrustedPixelWidth INT = NULL,
    @TrustedPixelHeight INT = NULL,
    @TrustedProcessingVersion NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @AssetId BIGINT, @ProjectId BIGINT, @StoredProvider TINYINT;
    DECLARE @StoredKind TINYINT, @StoredStorageStatus TINYINT;
    DECLARE @StoredScanStatus TINYINT;
    DECLARE @StoredQuarantineETag NVARCHAR(100), @StoredContentHash BINARY(32);
    DECLARE @StoredContentLength BIGINT, @StoredVerifiedMimeType NVARCHAR(100);
    DECLARE @StoredCreatedAtUtc DATETIME2(3), @StoredScanStartedAtUtc DATETIME2(3);
    DECLARE @StoredScanCompletedAtUtc DATETIME2(3), @IsDeleted BIT;
    DECLARE @AssetRowVersion BINARY(8), @ProjectRowVersion BINARY(8);
    DECLARE @ExpectedTrustedContainer NVARCHAR(63);
    DECLARE @ExpectedTrustedObjectName NVARCHAR(1024);
    DECLARE @AuthorizedReceiptAssetId BIGINT;
    DECLARE @ExistingAssetId BIGINT, @ExistingPayloadHash BINARY(32);
    DECLARE @ExistingFromStatus TINYINT, @ExistingToStatus TINYINT;
    DECLARE @ExistingProviderObservedStatus TINYINT;
    DECLARE @ExistingQuarantineETag NVARCHAR(100);
    DECLARE @ExistingReportedHash BINARY(32), @ExistingResultCode NVARCHAR(100);
    DECLARE @ExistingProviderResultCode NVARCHAR(100);
    DECLARE @ExistingResultRowVersion BINARY(8);
    DECLARE @RevokedContainer NVARCHAR(63), @RevokedObject NVARCHAR(1024);
    DECLARE @RevokedETag NVARCHAR(100), @RevokedVersionId NVARCHAR(200);
    DECLARE @RevokedMimeType NVARCHAR(100), @RevokedContentLength BIGINT;
    DECLARE @RevokedContentHash BINARY(32), @RevokedPixelWidth INT;
    DECLARE @RevokedPixelHeight INT, @RevokedProcessingVersion NVARCHAR(100);
    DECLARE @RevokedCreatedAtUtc DATETIME2(3);
    DECLARE @IsDerivedSanitizerFailure BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;

    SET @ProviderEventId = LTRIM(RTRIM(@ProviderEventId));
    SET @QuarantineBlobETag = LTRIM(RTRIM(@QuarantineBlobETag));
    SET @ResultCode = LOWER(LTRIM(RTRIM(@ResultCode)));
    SET @ProviderObservedStatus = COALESCE(@ProviderObservedStatus, @ToStatus);
    SET @ProviderResultCode = LOWER(LTRIM(RTRIM(
        COALESCE(@ProviderResultCode, @ResultCode))));
    SET @TrustedBlobContainer = NULLIF(LOWER(LTRIM(RTRIM(@TrustedBlobContainer))), N'');
    SET @TrustedBlobObjectName = NULLIF(LTRIM(RTRIM(@TrustedBlobObjectName)), N'');
    SET @TrustedBlobETag = NULLIF(LTRIM(RTRIM(@TrustedBlobETag)), N'');
    SET @TrustedBlobVersionId = NULLIF(LTRIM(RTRIM(@TrustedBlobVersionId)), N'');
    SET @TrustedMimeType = NULLIF(LOWER(LTRIM(RTRIM(@TrustedMimeType))), N'');
    SET @TrustedProcessingVersion =
        NULLIF(LOWER(LTRIM(RTRIM(@TrustedProcessingVersion))), N'');

    IF @ScanProvider BETWEEN 0 AND 1
       AND @ProviderObservedStatus = 1 AND @ToStatus = 3
       AND @ResultCode COLLATE Latin1_General_100_BIN2 IN
           (N'image-format-rejected', N'image-decode-rejected',
            N'image-frame-count-rejected', N'image-dimensions-rejected',
            N'image-output-too-large')
        SET @IsDerivedSanitizerFailure = 1;

    IF @AssetPublicId IS NULL
       OR @ScanProvider IS NULL OR @ScanProvider NOT BETWEEN 0 AND 1
       OR NULLIF(@ProviderEventId, N'') IS NULL OR LEN(@ProviderEventId) > 200
       OR CHARINDEX(CHAR(10), @ProviderEventId) > 0
       OR CHARINDEX(CHAR(13), @ProviderEventId) > 0
       OR @PayloadHash IS NULL
       OR @ProviderObservedStatus IS NULL
       OR @ProviderObservedStatus NOT BETWEEN 1 AND 4
       OR (@ProviderObservedStatus IN (1, 2) AND @ReportedContentHash IS NULL)
       OR LEN(COALESCE(@QuarantineBlobETag, N'')) NOT BETWEEN 3 AND 100
       OR LEFT(@QuarantineBlobETag, 1) <> N'"'
       OR RIGHT(@QuarantineBlobETag, 1) <> N'"'
       OR CHARINDEX(CHAR(10), @QuarantineBlobETag) > 0
       OR CHARINDEX(CHAR(13), @QuarantineBlobETag) > 0
       OR @ToStatus IS NULL OR @ToStatus NOT BETWEEN 1 AND 4
       OR NULLIF(@ResultCode, N'') IS NULL OR LEN(@ResultCode) > 100
       OR @ResultCode LIKE N'%[^-a-z0-9._]%' COLLATE Latin1_General_100_BIN2
       OR NULLIF(@ProviderResultCode, N'') IS NULL OR LEN(@ProviderResultCode) > 100
       OR @ProviderResultCode LIKE N'%[^-a-z0-9._]%' COLLATE Latin1_General_100_BIN2
       OR NOT ((@ProviderObservedStatus = @ToStatus
                AND @ProviderResultCode COLLATE Latin1_General_100_BIN2 =
                    @ResultCode COLLATE Latin1_General_100_BIN2)
               OR @IsDerivedSanitizerFailure = 1)
       OR @OccurredAtUtc IS NULL
       OR @OccurredAtUtc < DATEADD(DAY, -1, @NowUtc)
       OR @OccurredAtUtc > DATEADD(MINUTE, 5, @NowUtc)
       OR (@ToStatus = 1 AND
           (@TrustedBlobContainer IS NULL OR @TrustedBlobObjectName IS NULL
            OR LEN(COALESCE(@TrustedBlobETag, N'')) NOT BETWEEN 3 AND 100
            OR LEFT(@TrustedBlobETag, 1) <> N'"'
            OR RIGHT(@TrustedBlobETag, 1) <> N'"'
            OR CHARINDEX(CHAR(10), @TrustedBlobETag) > 0
            OR CHARINDEX(CHAR(13), @TrustedBlobETag) > 0
            OR CHARINDEX(N'&', @TrustedBlobContainer) > 0
            OR CHARINDEX(N'#', @TrustedBlobContainer) > 0
            OR CHARINDEX(N'?', @TrustedBlobContainer) > 0
            OR CHARINDEX(N'&', @TrustedBlobObjectName) > 0
            OR CHARINDEX(N'#', @TrustedBlobObjectName) > 0
            OR CHARINDEX(N'?', @TrustedBlobObjectName) > 0
            OR (@ScanProvider = 1 AND @TrustedBlobVersionId IS NULL)
            OR @TrustedMimeType IS NULL
            OR @TrustedContentLength IS NULL OR @TrustedContentLength < 1
            OR @TrustedContentHash IS NULL
            OR @TrustedProcessingVersion IS NULL))
       OR (@ToStatus <> 1 AND
           (@TrustedBlobContainer IS NOT NULL OR @TrustedBlobObjectName IS NOT NULL
            OR @TrustedBlobETag IS NOT NULL OR @TrustedBlobVersionId IS NOT NULL
            OR @TrustedMimeType IS NOT NULL OR @TrustedContentLength IS NOT NULL
            OR @TrustedContentHash IS NOT NULL OR @TrustedPixelWidth IS NOT NULL
            OR @TrustedPixelHeight IS NOT NULL
            OR @TrustedProcessingVersion IS NOT NULL))
       OR LEN(COALESCE(@TrustedBlobVersionId, N'')) > 200
       OR CHARINDEX(CHAR(10), COALESCE(@TrustedBlobVersionId, N'')) > 0
       OR CHARINDEX(CHAR(13), COALESCE(@TrustedBlobVersionId, N'')) > 0
       OR CHARINDEX(N'&', COALESCE(@TrustedBlobVersionId, N'')) > 0
       OR CHARINDEX(N'#', COALESCE(@TrustedBlobVersionId, N'')) > 0
       OR CHARINDEX(N'?', COALESCE(@TrustedBlobVersionId, N'')) > 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-scan-result' AS Code,
               @AssetPublicId AS AssetPublicId,
               CAST(NULL AS TINYINT) AS StorageStatus,
               CAST(NULL AS TINYINT) AS ScanStatus,
               CAST(NULL AS TINYINT) AS ScanProvider,
               CAST(NULL AS BINARY(8)) AS AssetRowVersion,
               CAST(NULL AS BINARY(8)) AS ProjectRowVersion,
               CAST(0 AS BIT) AS WasReplay,
               CAST(NULL AS NVARCHAR(63)) AS RevokedTrustedBlobContainer,
               CAST(NULL AS NVARCHAR(1024)) AS RevokedTrustedBlobObjectName,
               CAST(NULL AS NVARCHAR(100)) AS RevokedTrustedBlobETag,
               CAST(NULL AS NVARCHAR(200)) AS RevokedTrustedBlobVersionId,
               CAST(NULL AS NVARCHAR(100)) AS RevokedTrustedMimeType,
               CAST(NULL AS BIGINT) AS RevokedTrustedContentLength,
               CAST(NULL AS BINARY(32)) AS RevokedTrustedContentHash,
               CAST(NULL AS INT) AS RevokedTrustedPixelWidth,
               CAST(NULL AS INT) AS RevokedTrustedPixelHeight,
               CAST(NULL AS NVARCHAR(100)) AS RevokedTrustedProcessingVersion,
               CAST(NULL AS DATETIME2(3)) AS RevokedTrustedCreatedAtUtc;
        RETURN;
    END;

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_ApplyProjectAsset038;

    BEGIN TRY
        IF @ScanProvider = 1
            SELECT @AuthorizedReceiptAssetId = receipts.ProjectAssetId
            FROM dbo.FundingPlatform_ProjectAssetDefenderReceipts AS receipts
                 WITH (UPDLOCK, HOLDLOCK)
            WHERE receipts.Provider = 1
              AND receipts.ProviderEventId COLLATE Latin1_General_100_BIN2 =
                  @ProviderEventId COLLATE Latin1_General_100_BIN2
              AND receipts.PayloadHash = @PayloadHash
              AND receipts.BlobETag COLLATE Latin1_General_100_BIN2 =
                  @QuarantineBlobETag COLLATE Latin1_General_100_BIN2
              AND ((receipts.ReportedContentHash IS NULL AND @ReportedContentHash IS NULL)
                   OR receipts.ReportedContentHash = @ReportedContentHash)
              AND receipts.ToStatus = @ProviderObservedStatus
              AND receipts.ResultCode = @ProviderResultCode
                  COLLATE Latin1_General_100_BIN2
              AND receipts.OccurredAtUtc = @OccurredAtUtc
              AND receipts.ReceiptStatus IN (0, 1);

        SELECT @AssetId = assets.Id, @ProjectId = assets.ProjectId,
               @StoredProvider = assets.ScanProvider, @StoredKind = assets.Kind,
               @StoredStorageStatus = assets.StorageStatus,
               @StoredScanStatus = assets.ScanStatus,
               @StoredQuarantineETag = assets.QuarantineBlobETag,
               @StoredContentHash = assets.ContentHash,
               @StoredContentLength = assets.ContentLength,
               @StoredVerifiedMimeType = LOWER(assets.VerifiedMimeType),
               @StoredCreatedAtUtc = assets.CreatedAtUtc,
               @StoredScanStartedAtUtc = assets.ScanStartedAtUtc,
               @StoredScanCompletedAtUtc = assets.ScanCompletedAtUtc,
               @IsDeleted = assets.IsDeleted, @AssetRowVersion = assets.RowVersion,
               @ExpectedTrustedContainer = intents.TrustedBlobContainer,
               @ExpectedTrustedObjectName = intents.TrustedBlobObjectName
        FROM dbo.FundingPlatform_ProjectAssets AS assets WITH (UPDLOCK, HOLDLOCK)
        LEFT JOIN dbo.FundingPlatform_ProjectAssetUploadIntents AS intents WITH (HOLDLOCK)
            ON intents.CompletedProjectAssetId = assets.Id AND intents.Status = 2
        WHERE assets.PublicId = @AssetPublicId;

        SELECT @ExistingAssetId = events.ProjectAssetId,
               @ExistingPayloadHash = events.PayloadHash,
               @ExistingFromStatus = events.FromStatus,
               @ExistingToStatus = events.ToStatus,
               @ExistingProviderObservedStatus = events.ProviderObservedStatus,
               @ExistingQuarantineETag = events.QuarantineBlobETag,
               @ExistingReportedHash = events.ReportedContentHash,
               @ExistingResultCode = events.ResultCode,
               @ExistingProviderResultCode = events.ProviderResultCode,
               @ExistingResultRowVersion = events.ResultRowVersion,
               @RevokedContainer = events.RevokedTrustedBlobContainer,
               @RevokedObject = events.RevokedTrustedBlobObjectName,
               @RevokedETag = events.RevokedTrustedBlobETag,
               @RevokedVersionId = events.RevokedTrustedBlobVersionId,
               @RevokedMimeType = events.RevokedTrustedMimeType,
               @RevokedContentLength = events.RevokedTrustedContentLength,
               @RevokedContentHash = events.RevokedTrustedContentHash,
               @RevokedPixelWidth = events.RevokedTrustedPixelWidth,
               @RevokedPixelHeight = events.RevokedTrustedPixelHeight,
               @RevokedProcessingVersion = events.RevokedTrustedProcessingVersion,
               @RevokedCreatedAtUtc = events.RevokedTrustedCreatedAtUtc
        FROM dbo.FundingPlatform_ProjectAssetScanEvents AS events WITH (UPDLOCK, HOLDLOCK)
        WHERE events.ScanProvider = @ScanProvider
          AND events.ProviderEventId COLLATE Latin1_General_100_BIN2 =
              @ProviderEventId COLLATE Latin1_General_100_BIN2;

        IF @ScanProvider = 1
           AND (@AuthorizedReceiptAssetId IS NULL OR @AuthorizedReceiptAssetId <> @AssetId)
            SET @Code = N'defender-receipt-required';
        ELSE IF @ExistingAssetId IS NOT NULL
        BEGIN
            IF @AssetId = @ExistingAssetId
               AND @ExistingPayloadHash = @PayloadHash
               AND @ExistingToStatus = @ToStatus
               AND @ExistingProviderObservedStatus = @ProviderObservedStatus
               AND @ExistingQuarantineETag COLLATE Latin1_General_100_BIN2 =
                   @QuarantineBlobETag COLLATE Latin1_General_100_BIN2
               AND @ExistingResultCode COLLATE Latin1_General_100_BIN2 =
                   @ResultCode COLLATE Latin1_General_100_BIN2
               AND @ExistingProviderResultCode COLLATE Latin1_General_100_BIN2 =
                   @ProviderResultCode COLLATE Latin1_General_100_BIN2
               AND ((@ExistingReportedHash IS NULL AND @ReportedContentHash IS NULL)
                    OR @ExistingReportedHash = @ReportedContentHash)
               AND
               (
                   @ExistingToStatus <> 1
                   OR
                   (@StoredScanStatus = 1 AND EXISTS
                      (SELECT 1
                       FROM dbo.FundingPlatform_ProjectAssets AS trustedAssets
                       WHERE trustedAssets.Id = @AssetId
                         AND trustedAssets.TrustedBlobContainer
                             COLLATE Latin1_General_100_BIN2 =
                             @TrustedBlobContainer COLLATE Latin1_General_100_BIN2
                         AND trustedAssets.TrustedBlobObjectName
                             COLLATE Latin1_General_100_BIN2 =
                             @TrustedBlobObjectName COLLATE Latin1_General_100_BIN2
                         AND trustedAssets.TrustedBlobETag
                             COLLATE Latin1_General_100_BIN2 =
                             @TrustedBlobETag COLLATE Latin1_General_100_BIN2
                         AND ((trustedAssets.TrustedBlobVersionId IS NULL
                               AND @TrustedBlobVersionId IS NULL)
                              OR trustedAssets.TrustedBlobVersionId
                                 COLLATE Latin1_General_100_BIN2 =
                                 @TrustedBlobVersionId COLLATE Latin1_General_100_BIN2)
                         AND trustedAssets.TrustedMimeType
                             COLLATE Latin1_General_100_BIN2 =
                             @TrustedMimeType COLLATE Latin1_General_100_BIN2
                         AND trustedAssets.TrustedContentLength = @TrustedContentLength
                         AND trustedAssets.TrustedContentHash = @TrustedContentHash
                         AND ((trustedAssets.TrustedPixelWidth IS NULL
                               AND @TrustedPixelWidth IS NULL)
                              OR trustedAssets.TrustedPixelWidth = @TrustedPixelWidth)
                         AND ((trustedAssets.TrustedPixelHeight IS NULL
                               AND @TrustedPixelHeight IS NULL)
                              OR trustedAssets.TrustedPixelHeight = @TrustedPixelHeight)
                         AND trustedAssets.TrustedProcessingVersion
                             COLLATE Latin1_General_100_BIN2 =
                             @TrustedProcessingVersion COLLATE Latin1_General_100_BIN2))
                   OR
                   (@StoredScanStatus <> 1 AND EXISTS
                      (SELECT 1
                       FROM dbo.FundingPlatform_ProjectAssetScanEvents AS superseding
                       WHERE superseding.ProjectAssetId = @AssetId
                         AND superseding.FromStatus = 1
                         AND superseding.RevokedTrustedBlobContainer
                             COLLATE Latin1_General_100_BIN2 =
                             @TrustedBlobContainer COLLATE Latin1_General_100_BIN2
                         AND superseding.RevokedTrustedBlobObjectName
                             COLLATE Latin1_General_100_BIN2 =
                             @TrustedBlobObjectName COLLATE Latin1_General_100_BIN2
                         AND superseding.RevokedTrustedBlobETag
                             COLLATE Latin1_General_100_BIN2 =
                             @TrustedBlobETag COLLATE Latin1_General_100_BIN2
                         AND ((superseding.RevokedTrustedBlobVersionId IS NULL
                               AND @TrustedBlobVersionId IS NULL)
                              OR superseding.RevokedTrustedBlobVersionId
                                 COLLATE Latin1_General_100_BIN2 =
                                 @TrustedBlobVersionId COLLATE Latin1_General_100_BIN2)
                         AND superseding.RevokedTrustedMimeType
                             COLLATE Latin1_General_100_BIN2 =
                             @TrustedMimeType COLLATE Latin1_General_100_BIN2
                         AND superseding.RevokedTrustedContentLength =
                             @TrustedContentLength
                         AND superseding.RevokedTrustedContentHash =
                             @TrustedContentHash
                         AND ((superseding.RevokedTrustedPixelWidth IS NULL
                               AND @TrustedPixelWidth IS NULL)
                              OR superseding.RevokedTrustedPixelWidth =
                                 @TrustedPixelWidth)
                         AND ((superseding.RevokedTrustedPixelHeight IS NULL
                               AND @TrustedPixelHeight IS NULL)
                              OR superseding.RevokedTrustedPixelHeight =
                                 @TrustedPixelHeight)
                         AND superseding.RevokedTrustedProcessingVersion
                             COLLATE Latin1_General_100_BIN2 =
                             @TrustedProcessingVersion COLLATE Latin1_General_100_BIN2
                         AND superseding.RevokedTrustedCreatedAtUtc IS NOT NULL))
               )
            BEGIN
                SET @Succeeded = 1; SET @WasReplay = 1;
                SET @Code = CASE WHEN @ExistingFromStatus = 1
                                 THEN N'scan-result-superseded'
                                 ELSE N'scan-result-applied' END;
                SET @AssetRowVersion = @ExistingResultRowVersion;
                SELECT @ProjectRowVersion = RowVersion
                FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId;
            END
            ELSE SET @Code = N'provider-event-conflict';
        END
        ELSE IF @AssetId IS NULL SET @Code = N'not-found';
        ELSE IF @IsDeleted = 1 SET @Code = N'asset-deleted';
        ELSE IF @StoredProvider <> @ScanProvider SET @Code = N'provider-mismatch';
        ELSE IF @StoredQuarantineETag COLLATE Latin1_General_100_BIN2 <>
                @QuarantineBlobETag COLLATE Latin1_General_100_BIN2
            SET @Code = N'etag-mismatch';
        ELSE IF @OccurredAtUtc < @StoredCreatedAtUtc
             OR (@StoredScanStartedAtUtc IS NOT NULL
                 AND @OccurredAtUtc < @StoredScanStartedAtUtc)
            SET @Code = N'invalid-event-time';
        ELSE IF @ReportedContentHash IS NOT NULL
             AND @StoredContentHash <> @ReportedContentHash
            SET @Code = N'hash-mismatch';
        ELSE IF @IsDerivedSanitizerFailure = 1 AND @StoredKind <> 0
            SET @Code = N'invalid-derived-scan-result';
        ELSE IF @StoredStorageStatus = 1 AND @StoredScanStatus = 0
        BEGIN
            IF @ToStatus = 1
               AND (@ExpectedTrustedContainer IS NULL
                    OR @ExpectedTrustedObjectName IS NULL
                    OR @TrustedBlobContainer COLLATE Latin1_General_100_BIN2 <>
                       @ExpectedTrustedContainer COLLATE Latin1_General_100_BIN2
                    OR @TrustedBlobObjectName COLLATE Latin1_General_100_BIN2 <>
                       @ExpectedTrustedObjectName COLLATE Latin1_General_100_BIN2)
                SET @Code = N'trusted-destination-mismatch';
            ELSE IF @ToStatus = 1
               AND
               (
                   (@StoredKind = 0
                    AND (@TrustedMimeType <> @StoredVerifiedMimeType
                         OR @TrustedMimeType NOT IN
                            (N'image/jpeg', N'image/png', N'image/webp')
                         OR @TrustedContentLength NOT BETWEEN 1 AND 10485760
                         OR @TrustedPixelWidth IS NULL OR @TrustedPixelHeight IS NULL
                         OR @TrustedPixelWidth NOT BETWEEN 1 AND 32768
                         OR @TrustedPixelHeight NOT BETWEEN 1 AND 32768
                         OR CONVERT(BIGINT, @TrustedPixelWidth)
                            * CONVERT(BIGINT, @TrustedPixelHeight) > 25000000
                         OR @TrustedProcessingVersion <> N'skia-4.151.2-image-v1'))
                   OR
                   (@StoredKind = 1
                    AND (@StoredVerifiedMimeType <> N'application/pdf'
                         OR @TrustedMimeType <> @StoredVerifiedMimeType
                         OR @TrustedContentLength NOT BETWEEN 1 AND 26214400
                         OR @TrustedContentLength <> @StoredContentLength
                         OR @TrustedContentHash <> @StoredContentHash
                         OR @TrustedPixelWidth IS NOT NULL
                         OR @TrustedPixelHeight IS NOT NULL
                         OR @TrustedProcessingVersion <> N'pdf-copy-v1'))
                   OR @StoredKind NOT IN (0, 1)
               )
                SET @Code = N'invalid-trusted-manifest';
            ELSE
            BEGIN
                DECLARE @EventId UNIQUEIDENTIFIER = NEWID();
                DECLARE @UpdatedAsset TABLE (RowVersion BINARY(8) NOT NULL);
                UPDATE dbo.FundingPlatform_ProjectAssets
                SET StorageStatus = CASE WHEN @ToStatus = 1 THEN 2 ELSE 3 END,
                    ScanStatus = @ToStatus,
                    ScanResultCode = @ResultCode,
                    ScanStartedAtUtc = COALESCE(ScanStartedAtUtc, @OccurredAtUtc),
                    ScanCompletedAtUtc = @OccurredAtUtc,
                    TrustedBlobContainer = CASE WHEN @ToStatus = 1
                                                THEN @TrustedBlobContainer END,
                    TrustedBlobObjectName = CASE WHEN @ToStatus = 1
                                                 THEN @TrustedBlobObjectName END,
                    TrustedBlobETag = CASE WHEN @ToStatus = 1
                                           THEN @TrustedBlobETag END,
                    TrustedBlobVersionId = CASE WHEN @ToStatus = 1
                                                THEN @TrustedBlobVersionId END,
                    TrustedMimeType = CASE WHEN @ToStatus = 1
                                           THEN @TrustedMimeType END,
                    TrustedContentLength = CASE WHEN @ToStatus = 1
                                                THEN @TrustedContentLength END,
                    TrustedContentHash = CASE WHEN @ToStatus = 1
                                              THEN @TrustedContentHash END,
                    TrustedPixelWidth = CASE WHEN @ToStatus = 1
                                             THEN @TrustedPixelWidth END,
                    TrustedPixelHeight = CASE WHEN @ToStatus = 1
                                              THEN @TrustedPixelHeight END,
                    TrustedProcessingVersion = CASE WHEN @ToStatus = 1
                                                     THEN @TrustedProcessingVersion END,
                    TrustedCreatedAtUtc = CASE WHEN @ToStatus = 1
                                               THEN @NowUtc END,
                    UpdatedAtUtc = @NowUtc
                OUTPUT inserted.RowVersion INTO @UpdatedAsset (RowVersion)
                WHERE Id = @AssetId AND StorageStatus = 1 AND ScanStatus = 0;
                SELECT @AssetRowVersion = RowVersion FROM @UpdatedAsset;
                IF @AssetRowVersion IS NULL
                    THROW 55803, N'Project asset changed during scan application.', 1;

                DECLARE @UpdatedProject TABLE (RowVersion BINARY(8) NOT NULL);
                UPDATE dbo.FundingPlatform_Projects
                SET UpdatedAtUtc = @NowUtc
                OUTPUT inserted.RowVersion INTO @UpdatedProject (RowVersion)
                WHERE Id = @ProjectId;
                SELECT @ProjectRowVersion = RowVersion FROM @UpdatedProject;

                INSERT INTO dbo.FundingPlatform_ProjectAssetScanEvents
                    (EventId, ProjectAssetId, ScanProvider, ProviderEventId,
                     PayloadHash, FromStatus, ToStatus, ProviderObservedStatus,
                     QuarantineBlobETag, ReportedContentHash,
                     ResultCode, ProviderResultCode, ResultRowVersion,
                     OccurredAtUtc, CreatedAtUtc)
                VALUES (@EventId, @AssetId, @ScanProvider, @ProviderEventId,
                        @PayloadHash, 0, @ToStatus, @ProviderObservedStatus,
                        @QuarantineBlobETag, @ReportedContentHash,
                        @ResultCode, @ProviderResultCode, @AssetRowVersion,
                        @OccurredAtUtc, @NowUtc);

                INSERT INTO dbo.FundingPlatform_OutboxMessages
                    (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                     OccurredAtUtc, AvailableAtUtc)
                SELECT @EventId, N'ProjectAssetScanCompleted', N'ProjectAsset',
                       CONVERT(NVARCHAR(100), @AssetPublicId),
                       (SELECT @EventId AS eventId, @AssetPublicId AS assetPublicId,
                               @ScanProvider AS scanProvider, @ToStatus AS scanStatus,
                               CASE WHEN @ToStatus = 1 THEN 2 ELSE 3 END AS storageStatus,
                               @ResultCode AS resultCode
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                       @NowUtc, @NowUtc;

                SET @StoredStorageStatus = CASE WHEN @ToStatus = 1 THEN 2 ELSE 3 END;
                SET @StoredScanStatus = @ToStatus;
                SET @Succeeded = 1; SET @Code = N'scan-result-applied';
            END;
        END
        ELSE IF @ScanProvider = 1 AND @StoredStorageStatus = 2
             AND @StoredScanStatus = 1 AND @ToStatus IN (2, 3, 4)
             AND @ProviderObservedStatus = @ToStatus
             AND @ProviderResultCode COLLATE Latin1_General_100_BIN2 =
                 @ResultCode COLLATE Latin1_General_100_BIN2
        BEGIN
            IF @StoredScanCompletedAtUtc IS NULL
               OR @OccurredAtUtc <= @StoredScanCompletedAtUtc
                SET @Code = N'stale-scan-result';
            ELSE
            BEGIN
                SELECT @RevokedContainer = TrustedBlobContainer,
                       @RevokedObject = TrustedBlobObjectName,
                       @RevokedETag = TrustedBlobETag,
                       @RevokedVersionId = TrustedBlobVersionId,
                       @RevokedMimeType = TrustedMimeType,
                       @RevokedContentLength = TrustedContentLength,
                       @RevokedContentHash = TrustedContentHash,
                       @RevokedPixelWidth = TrustedPixelWidth,
                       @RevokedPixelHeight = TrustedPixelHeight,
                       @RevokedProcessingVersion = TrustedProcessingVersion,
                       @RevokedCreatedAtUtc = TrustedCreatedAtUtc
                FROM dbo.FundingPlatform_ProjectAssets WITH (HOLDLOCK)
                WHERE Id = @AssetId;

                IF @RevokedContainer IS NULL OR @RevokedObject IS NULL
                   OR @RevokedETag IS NULL OR @RevokedVersionId IS NULL
                   OR @RevokedMimeType IS NULL OR @RevokedContentLength IS NULL
                   OR @RevokedContentHash IS NULL OR @RevokedProcessingVersion IS NULL
                   OR @RevokedCreatedAtUtc IS NULL
                    SET @Code = N'trusted-manifest-missing';
                ELSE
                BEGIN
                    DECLARE @RevokeEventId UNIQUEIDENTIFIER = NEWID();
                    DECLARE @RevokedAsset TABLE (RowVersion BINARY(8) NOT NULL);
                    UPDATE dbo.FundingPlatform_ProjectAssets
                    SET StorageStatus = 3, ScanStatus = @ToStatus,
                        ScanResultCode = @ResultCode,
                        ScanCompletedAtUtc = @OccurredAtUtc,
                        TrustedBlobContainer = NULL, TrustedBlobObjectName = NULL,
                        TrustedBlobETag = NULL, TrustedBlobVersionId = NULL,
                        TrustedMimeType = NULL, TrustedContentLength = NULL,
                        TrustedContentHash = NULL, TrustedPixelWidth = NULL,
                        TrustedPixelHeight = NULL, TrustedProcessingVersion = NULL,
                        TrustedCreatedAtUtc = NULL,
                        IsCover = 0, UpdatedAtUtc = @NowUtc
                    OUTPUT inserted.RowVersion INTO @RevokedAsset (RowVersion)
                    WHERE Id = @AssetId AND StorageStatus = 2 AND ScanStatus = 1;
                    SELECT @AssetRowVersion = RowVersion FROM @RevokedAsset;
                    IF @AssetRowVersion IS NULL
                        THROW 55804, N'Project asset changed during trust revocation.', 1;

                    DECLARE @RevokedProject TABLE (RowVersion BINARY(8) NOT NULL);
                    UPDATE dbo.FundingPlatform_Projects
                    SET UpdatedAtUtc = @NowUtc
                    OUTPUT inserted.RowVersion INTO @RevokedProject (RowVersion)
                    WHERE Id = @ProjectId;
                    SELECT @ProjectRowVersion = RowVersion FROM @RevokedProject;

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
                    VALUES (@RevokeEventId, @AssetId, @ScanProvider, @ProviderEventId,
                            @PayloadHash, 1, @ToStatus, @ProviderObservedStatus,
                            @QuarantineBlobETag, @ReportedContentHash,
                            @ResultCode, @ProviderResultCode, @AssetRowVersion,
                            @OccurredAtUtc, @NowUtc,
                            @RevokedContainer, @RevokedObject,
                            @RevokedETag, @RevokedVersionId,
                            @RevokedMimeType, @RevokedContentLength,
                            @RevokedContentHash, @RevokedPixelWidth,
                            @RevokedPixelHeight, @RevokedProcessingVersion,
                            @RevokedCreatedAtUtc);

                    INSERT INTO dbo.FundingPlatform_OutboxMessages
                        (MessageId, MessageType, AggregateType, AggregateId,
                         PayloadJson, OccurredAtUtc, AvailableAtUtc)
                    SELECT @RevokeEventId, N'ProjectAssetScanTrustRevoked',
                           N'ProjectAsset', CONVERT(NVARCHAR(100), @AssetPublicId),
                           (SELECT @RevokeEventId AS eventId,
                                   @AssetPublicId AS assetPublicId,
                                   @ToStatus AS scanStatus,
                                   CAST(3 AS TINYINT) AS storageStatus,
                                   @ResultCode AS resultCode
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                           @NowUtc, @NowUtc;

                    SET @StoredStorageStatus = 3; SET @StoredScanStatus = @ToStatus;
                    SET @Succeeded = 1; SET @Code = N'scan-result-superseded';
                END;
            END;
        END
        ELSE IF @StoredScanStatus = @ToStatus SET @Code = N'scan-result-ignored';
        ELSE SET @Code = N'invalid-transition';

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ApplyProjectAsset038;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @AssetPublicId AS AssetPublicId,
           @StoredStorageStatus AS StorageStatus,
           @StoredScanStatus AS ScanStatus, @StoredProvider AS ScanProvider,
           @AssetRowVersion AS AssetRowVersion,
           @ProjectRowVersion AS ProjectRowVersion, @WasReplay AS WasReplay,
           CASE WHEN @Code = N'scan-result-superseded'
                THEN @RevokedContainer END AS RevokedTrustedBlobContainer,
           CASE WHEN @Code = N'scan-result-superseded'
                THEN @RevokedObject END AS RevokedTrustedBlobObjectName,
           CASE WHEN @Code = N'scan-result-superseded'
                THEN @RevokedETag END AS RevokedTrustedBlobETag,
           CASE WHEN @Code = N'scan-result-superseded'
                THEN @RevokedVersionId END AS RevokedTrustedBlobVersionId,
           CASE WHEN @Code = N'scan-result-superseded'
                THEN @RevokedMimeType END AS RevokedTrustedMimeType,
           CASE WHEN @Code = N'scan-result-superseded'
                THEN @RevokedContentLength END AS RevokedTrustedContentLength,
           CASE WHEN @Code = N'scan-result-superseded'
                THEN @RevokedContentHash END AS RevokedTrustedContentHash,
           CASE WHEN @Code = N'scan-result-superseded'
                THEN @RevokedPixelWidth END AS RevokedTrustedPixelWidth,
           CASE WHEN @Code = N'scan-result-superseded'
                THEN @RevokedPixelHeight END AS RevokedTrustedPixelHeight,
           CASE WHEN @Code = N'scan-result-superseded'
                THEN @RevokedProcessingVersion END AS RevokedTrustedProcessingVersion,
           CASE WHEN @Code = N'scan-result-superseded'
                THEN @RevokedCreatedAtUtc END AS RevokedTrustedCreatedAtUtc;
END;
GO

/* Preserve the cumulative audit sink and add one exact schema for the one-time
   fail-closed revocation facts emitted while upgrading legacy trusted images. */
DECLARE @Pre038AuditSinkDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge', N'P'));
IF @Pre038AuditSinkDefinition NOT LIKE N'%FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre037%'
   OR @Pre038AuditSinkDefinition NOT LIKE N'%ProjectAssetScanTrustRevoked%'
    THROW 55805, N'Image sanitization audit sink requires the cumulative migration 037 wrapper.', 1;

EXEC sys.sp_rename
    @objname = N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge',
    @newname = N'FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre038',
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
    IF @BatchSize IS NULL OR @BatchSize NOT BETWEEN 1 AND 500
        THROW 55806, N'BatchSize must be between 1 and 500.', 1;
    IF @NowUtc IS NULL THROW 55807, N'NowUtc is required.', 1;

    DECLARE @PreviousCount INT = 0;
    EXEC dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre038
        @BatchSize = @BatchSize, @NowUtc = @NowUtc,
        @AcknowledgedCount = @PreviousCount OUTPUT;

    DECLARE @Remaining INT = @BatchSize - @PreviousCount, @CurrentCount INT = 0;
    IF @Remaining > 0
    BEGIN
        ;WITH LegacyImageRevocations AS
        (
            SELECT TOP (@Remaining) messages.*
            FROM dbo.FundingPlatform_OutboxMessages AS messages
                 WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
            WHERE messages.DispatchedAtUtc IS NULL
              AND messages.AvailableAtUtc <= @NowUtc
              AND (messages.LeaseUntilUtc IS NULL OR messages.LeaseUntilUtc <= @NowUtc)
              AND messages.MessageType COLLATE Latin1_General_100_BIN2 =
                  N'ProjectAssetLegacyTrustRevoked'
              AND messages.AggregateType COLLATE Latin1_General_100_BIN2 = N'ProjectAsset'
              AND LEN(messages.AggregateId) = 36
              AND LEFT(LTRIM(messages.PayloadJson), 1) = N'{'
              AND RIGHT(RTRIM(messages.PayloadJson), 1) = N'}'
              AND TRY_CONVERT(UNIQUEIDENTIFIER, messages.AggregateId) =
                  TRY_CONVERT(UNIQUEIDENTIFIER,
                              JSON_VALUE(messages.PayloadJson, N'$.assetPublicId'))
              AND messages.MessageId = TRY_CONVERT(UNIQUEIDENTIFIER,
                              JSON_VALUE(messages.PayloadJson, N'$.eventId'))
              AND TRY_CONVERT(TINYINT,
                              JSON_VALUE(messages.PayloadJson, N'$.scanStatus')) = 3
              AND TRY_CONVERT(TINYINT,
                              JSON_VALUE(messages.PayloadJson, N'$.storageStatus')) = 3
              AND JSON_VALUE(messages.PayloadJson, N'$.resultCode') =
                  N'legacy-image-unsanitized'
              AND NULLIF(JSON_VALUE(messages.PayloadJson,
                                    N'$.revokedTrustedBlobContainer'), N'') IS NOT NULL
              AND LEN(JSON_VALUE(messages.PayloadJson,
                                 N'$.revokedTrustedBlobContainer')) BETWEEN 3 AND 63
              AND NULLIF(JSON_VALUE(messages.PayloadJson,
                                    N'$.revokedTrustedBlobObjectName'), N'') IS NOT NULL
              AND LEN(JSON_VALUE(messages.PayloadJson,
                                 N'$.revokedTrustedBlobObjectName')) BETWEEN 1 AND 1024
              AND LEN(JSON_VALUE(messages.PayloadJson,
                                 N'$.revokedTrustedBlobETag')) BETWEEN 3 AND 100
              AND LEFT(JSON_VALUE(messages.PayloadJson,
                                  N'$.revokedTrustedBlobETag'), 1) = N'"'
              AND RIGHT(JSON_VALUE(messages.PayloadJson,
                                   N'$.revokedTrustedBlobETag'), 1) = N'"'
              AND
                  (JSON_VALUE(messages.PayloadJson,
                              N'$.revokedTrustedBlobVersionId') IS NULL
                   OR (LEN(JSON_VALUE(messages.PayloadJson,
                                      N'$.revokedTrustedBlobVersionId')) BETWEEN 1 AND 200
                       AND CHARINDEX(CHAR(10), JSON_VALUE(messages.PayloadJson,
                                      N'$.revokedTrustedBlobVersionId')) = 0
                       AND CHARINDEX(CHAR(13), JSON_VALUE(messages.PayloadJson,
                                      N'$.revokedTrustedBlobVersionId')) = 0))
              AND JSON_VALUE(messages.PayloadJson, N'$.revokedTrustedMimeType')
                  IN (N'image/jpeg', N'image/png', N'image/webp')
              AND TRY_CONVERT(BIGINT, JSON_VALUE(messages.PayloadJson,
                                 N'$.revokedTrustedContentLength')) BETWEEN 1 AND 10485760
              AND LEN(JSON_VALUE(messages.PayloadJson,
                                 N'$.revokedTrustedContentHashSha256')) = 64
              AND JSON_VALUE(messages.PayloadJson,
                             N'$.revokedTrustedContentHashSha256')
                  NOT LIKE N'%[^0-9A-F]%' COLLATE Latin1_General_100_BIN2
              AND TRY_CONVERT(INT, JSON_VALUE(messages.PayloadJson,
                              N'$.revokedTrustedPixelWidth')) BETWEEN 1 AND 32768
              AND TRY_CONVERT(INT, JSON_VALUE(messages.PayloadJson,
                              N'$.revokedTrustedPixelHeight')) BETWEEN 1 AND 32768
              AND TRY_CONVERT(BIGINT, JSON_VALUE(messages.PayloadJson,
                              N'$.revokedTrustedPixelWidth'))
                  * TRY_CONVERT(BIGINT, JSON_VALUE(messages.PayloadJson,
                              N'$.revokedTrustedPixelHeight')) <= 25000000
              AND JSON_VALUE(messages.PayloadJson,
                             N'$.revokedTrustedProcessingVersion') =
                  N'legacy-unsanitized-v0'
              AND TRY_CONVERT(DATETIME2(3), JSON_VALUE(messages.PayloadJson,
                              N'$.revokedTrustedCreatedAtUtc')) IS NOT NULL
              AND EXISTS
                  (SELECT 1
                   FROM dbo.FundingPlatform_ProjectAssetScanEvents AS scanEvents
                   INNER JOIN dbo.FundingPlatform_ProjectAssets AS assets
                       ON assets.Id = scanEvents.ProjectAssetId
                   WHERE scanEvents.EventId = messages.MessageId
                     AND assets.PublicId = TRY_CONVERT(UNIQUEIDENTIFIER,
                         JSON_VALUE(messages.PayloadJson, N'$.assetPublicId'))
                     AND scanEvents.FromStatus = 1
                     AND scanEvents.ToStatus = 3
                     AND scanEvents.ResultCode = N'legacy-image-unsanitized'
                     AND scanEvents.RevokedTrustedBlobContainer =
                         JSON_VALUE(messages.PayloadJson,
                                    N'$.revokedTrustedBlobContainer')
                     AND scanEvents.RevokedTrustedBlobObjectName =
                         JSON_VALUE(messages.PayloadJson,
                                    N'$.revokedTrustedBlobObjectName')
                     AND scanEvents.RevokedTrustedBlobETag =
                         JSON_VALUE(messages.PayloadJson,
                                    N'$.revokedTrustedBlobETag')
                     AND ((scanEvents.RevokedTrustedBlobVersionId IS NULL
                           AND JSON_VALUE(messages.PayloadJson,
                                          N'$.revokedTrustedBlobVersionId') IS NULL)
                          OR scanEvents.RevokedTrustedBlobVersionId =
                             JSON_VALUE(messages.PayloadJson,
                                        N'$.revokedTrustedBlobVersionId'))
                     AND scanEvents.RevokedTrustedMimeType =
                         JSON_VALUE(messages.PayloadJson,
                                    N'$.revokedTrustedMimeType')
                     AND scanEvents.RevokedTrustedContentLength =
                         TRY_CONVERT(BIGINT, JSON_VALUE(messages.PayloadJson,
                                     N'$.revokedTrustedContentLength'))
                     AND CONVERT(VARCHAR(64),
                                 scanEvents.RevokedTrustedContentHash, 2) =
                         JSON_VALUE(messages.PayloadJson,
                                    N'$.revokedTrustedContentHashSha256')
                     AND scanEvents.RevokedTrustedPixelWidth =
                         TRY_CONVERT(INT, JSON_VALUE(messages.PayloadJson,
                                     N'$.revokedTrustedPixelWidth'))
                     AND scanEvents.RevokedTrustedPixelHeight =
                         TRY_CONVERT(INT, JSON_VALUE(messages.PayloadJson,
                                     N'$.revokedTrustedPixelHeight'))
                     AND scanEvents.RevokedTrustedProcessingVersion =
                         N'legacy-unsanitized-v0'
                     AND scanEvents.RevokedTrustedCreatedAtUtc =
                         TRY_CONVERT(DATETIME2(3), JSON_VALUE(messages.PayloadJson,
                                     N'$.revokedTrustedCreatedAtUtc')))
              AND (SELECT COUNT_BIG(1) FROM OPENJSON(messages.PayloadJson)) = 16
              AND NOT EXISTS
                  (SELECT 1
                   FROM OPENJSON(messages.PayloadJson) AS fields
                   GROUP BY fields.[key] COLLATE Latin1_General_100_BIN2
                   HAVING COUNT_BIG(1) <> 1)
              AND NOT EXISTS
                  (SELECT 1 FROM OPENJSON(messages.PayloadJson) AS fields
                   WHERE fields.[key] COLLATE Latin1_General_100_BIN2 NOT IN
                         (N'eventId', N'assetPublicId', N'scanStatus', N'storageStatus',
                          N'resultCode', N'revokedTrustedBlobContainer',
                          N'revokedTrustedBlobObjectName', N'revokedTrustedBlobETag',
                          N'revokedTrustedBlobVersionId', N'revokedTrustedMimeType',
                          N'revokedTrustedContentLength',
                          N'revokedTrustedContentHashSha256',
                          N'revokedTrustedPixelWidth', N'revokedTrustedPixelHeight',
                          N'revokedTrustedProcessingVersion',
                          N'revokedTrustedCreatedAtUtc'))
              AND (SELECT COUNT_BIG(1)
                   FROM OPENJSON(messages.PayloadJson) AS fields
                   WHERE (fields.[key] COLLATE Latin1_General_100_BIN2 IN
                              (N'eventId', N'assetPublicId', N'resultCode',
                               N'revokedTrustedBlobContainer',
                               N'revokedTrustedBlobObjectName',
                               N'revokedTrustedBlobETag', N'revokedTrustedMimeType',
                               N'revokedTrustedContentHashSha256',
                               N'revokedTrustedProcessingVersion',
                               N'revokedTrustedCreatedAtUtc')
                          AND fields.[type] = 1)
                      OR (fields.[key] COLLATE Latin1_General_100_BIN2 IN
                              (N'scanStatus', N'storageStatus',
                               N'revokedTrustedContentLength',
                               N'revokedTrustedPixelWidth',
                               N'revokedTrustedPixelHeight')
                          AND fields.[type] = 2)
                      OR (fields.[key] COLLATE Latin1_General_100_BIN2 =
                              N'revokedTrustedBlobVersionId'
                          AND fields.[type] IN (0, 1))) = 16
            ORDER BY messages.AvailableAtUtc, messages.Id
        )
        UPDATE LegacyImageRevocations
        SET DispatchedAtUtc = @NowUtc, LeaseOwner = NULL, LeaseUntilUtc = NULL,
            LastError = N'event-ledger-acknowledged';
        SET @CurrentCount = @@ROWCOUNT;
    END;

    SET @AcknowledgedCount = @PreviousCount + @CurrentCount;
END;
GO

/* Finalization authenticates the provider observation, not the effective local
   sanitizer result. This preserves the receipt lifecycle when Clean becomes one
   of the five bounded image failures. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Finalize
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
    IF @ReceiptPublicId IS NULL OR @PayloadHash IS NULL OR @Applied IS NULL
       OR @FinalizedAtUtc IS NULL
       OR NULLIF(@OutcomeCode, N'') IS NULL OR LEN(@OutcomeCode) > 100
       OR @OutcomeCode LIKE N'%[^-a-z0-9._]%' COLLATE Latin1_General_100_BIN2
        THROW 55711, N'Valid project-asset receipt finalization metadata is required.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @ReceiptId BIGINT, @AssetId BIGINT, @Status TINYINT;
    DECLARE @StoredHash BINARY(32), @StoredOutcome NVARCHAR(100);
    DECLARE @ProviderEventId NVARCHAR(200), @StoredBlobETag NVARCHAR(100);
    DECLARE @StoredReportedHash BINARY(32), @StoredToStatus TINYINT;
    DECLARE @StoredResultCode NVARCHAR(100), @StoredOccurredAtUtc DATETIME2(3);
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'not-found';

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_ProjectFinalize038;

    BEGIN TRY
        SELECT @ReceiptId = Id, @AssetId = ProjectAssetId,
               @Status = ReceiptStatus, @StoredHash = PayloadHash,
               @StoredOutcome = OutcomeCode, @ProviderEventId = ProviderEventId,
               @StoredBlobETag = BlobETag, @StoredReportedHash = ReportedContentHash,
               @StoredToStatus = ToStatus, @StoredResultCode = ResultCode,
               @StoredOccurredAtUtc = OccurredAtUtc
        FROM dbo.FundingPlatform_ProjectAssetDefenderReceipts WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @ReceiptPublicId;

        IF @ReceiptId IS NULL SET @Code = N'not-found';
        ELSE IF @StoredHash <> @PayloadHash SET @Code = N'receipt-conflict';
        ELSE IF @Status IN (1, 2)
        BEGIN
            IF @StoredOutcome COLLATE Latin1_General_100_BIN2 =
                   @OutcomeCode COLLATE Latin1_General_100_BIN2
               AND ((@Status = 1 AND @Applied = 1)
                    OR (@Status = 2 AND @Applied = 0))
            BEGIN SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'replayed'; END
            ELSE SET @Code = N'receipt-conflict';
        END
        ELSE IF @Status = 3 SET @Code = N'rejected';
        ELSE IF @Applied = 1 AND NOT EXISTS
             (SELECT 1
              FROM dbo.FundingPlatform_ProjectAssetScanEvents WITH (UPDLOCK, HOLDLOCK)
              WHERE ProjectAssetId = @AssetId AND ScanProvider = 1
                AND ProviderEventId COLLATE Latin1_General_100_BIN2 =
                    @ProviderEventId COLLATE Latin1_General_100_BIN2
                AND PayloadHash = @PayloadHash
                AND QuarantineBlobETag COLLATE Latin1_General_100_BIN2 =
                    @StoredBlobETag COLLATE Latin1_General_100_BIN2
                AND ((ReportedContentHash IS NULL AND @StoredReportedHash IS NULL)
                     OR ReportedContentHash = @StoredReportedHash)
                AND ProviderObservedStatus = @StoredToStatus
                AND ProviderResultCode COLLATE Latin1_General_100_BIN2 =
                    @StoredResultCode COLLATE Latin1_General_100_BIN2
                AND OccurredAtUtc = @StoredOccurredAtUtc)
            SET @Code = N'scan-result-not-applied';
        ELSE
        BEGIN
            SET @Status = CASE WHEN @Applied = 1 THEN 1 ELSE 2 END;
            UPDATE dbo.FundingPlatform_ProjectAssetDefenderReceipts
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
            ROLLBACK TRANSACTION FP_ProjectFinalize038;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, @Status AS ReceiptStatus,
           @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAsset_GetTrustedContent
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER,
    @AssetPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ProjectId BIGINT;
    DECLARE @StoredAssetPublicId UNIQUEIDENTIFIER;
    DECLARE @Kind TINYINT;
    DECLARE @StorageStatus TINYINT;
    DECLARE @ScanStatus TINYINT;
    DECLARE @TrustedBlobContainer NVARCHAR(63);
    DECLARE @TrustedBlobObjectName NVARCHAR(1024);
    DECLARE @TrustedBlobETag NVARCHAR(100);
    DECLARE @TrustedBlobVersionId NVARCHAR(200);
    DECLARE @TrustedContentHash BINARY(32);
    DECLARE @TrustedMimeType NVARCHAR(100);
    DECLARE @TrustedContentLength BIGINT;
    DECLARE @TrustedPixelWidth INT;
    DECLARE @TrustedPixelHeight INT;
    DECLARE @TrustedProcessingVersion NVARCHAR(100);
    DECLARE @TrustedCreatedAtUtc DATETIME2(3);
    DECLARE @OriginalFileName NVARCHAR(260);
    DECLARE @AssetRowVersion BINARY(8);

    SELECT @ProjectId = projects.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id
       AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    INNER JOIN dbo.FundingPlatform_Projects AS projects
        ON projects.OrganizationId = organizations.Id AND projects.IsActive = 1
    WHERE organizations.PublicId = @OrganizationPublicId
      AND organizations.IsActive = 1
      AND projects.PublicId = @ProjectPublicId
      AND users.PublicId = @UserPublicId;

    IF @ProjectId IS NULL
        THROW 55604, N'Project was not found.', 1;

    SELECT @StoredAssetPublicId = PublicId,
           @Kind = Kind,
           @StorageStatus = StorageStatus,
           @ScanStatus = ScanStatus,
           @TrustedBlobContainer = TrustedBlobContainer,
           @TrustedBlobObjectName = TrustedBlobObjectName,
           @TrustedBlobETag = TrustedBlobETag,
           @TrustedBlobVersionId = TrustedBlobVersionId,
           @TrustedContentHash = TrustedContentHash,
           @TrustedMimeType = TrustedMimeType,
           @TrustedContentLength = TrustedContentLength,
           @TrustedPixelWidth = TrustedPixelWidth,
           @TrustedPixelHeight = TrustedPixelHeight,
           @TrustedProcessingVersion = TrustedProcessingVersion,
           @TrustedCreatedAtUtc = TrustedCreatedAtUtc,
           @OriginalFileName = OriginalFileName,
           @AssetRowVersion = RowVersion
    FROM dbo.FundingPlatform_ProjectAssets
    WHERE ProjectId = @ProjectId AND PublicId = @AssetPublicId AND IsDeleted = 0;

    IF @StoredAssetPublicId IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'not-found' AS Code,
               @AssetPublicId AS AssetPublicId,
               CAST(NULL AS TINYINT) AS Kind,
               CAST(NULL AS NVARCHAR(63)) AS TrustedBlobContainer,
               CAST(NULL AS NVARCHAR(1024)) AS TrustedBlobObjectName,
               CAST(NULL AS NVARCHAR(100)) AS TrustedBlobETag,
               CAST(NULL AS NVARCHAR(200)) AS TrustedBlobVersionId,
               CAST(NULL AS BINARY(32)) AS TrustedContentHash,
               CAST(NULL AS NVARCHAR(100)) AS TrustedMimeType,
               CAST(NULL AS BIGINT) AS TrustedContentLength,
               CAST(NULL AS INT) AS TrustedPixelWidth,
               CAST(NULL AS INT) AS TrustedPixelHeight,
               CAST(NULL AS NVARCHAR(100)) AS TrustedProcessingVersion,
               CAST(NULL AS DATETIME2(3)) AS TrustedCreatedAtUtc,
               CAST(NULL AS NVARCHAR(260)) AS OriginalFileName,
               CAST(NULL AS BINARY(8)) AS RowVersion;
        RETURN;
    END;

    IF @StorageStatus <> 2 OR @ScanStatus <> 1
       OR @TrustedBlobContainer IS NULL OR @TrustedBlobObjectName IS NULL
       OR @TrustedBlobETag IS NULL OR @TrustedContentHash IS NULL
       OR @TrustedMimeType IS NULL OR @TrustedContentLength IS NULL
       OR @TrustedProcessingVersion IS NULL OR @TrustedCreatedAtUtc IS NULL
       OR (@Kind = 0
           AND (@TrustedPixelWidth IS NULL OR @TrustedPixelHeight IS NULL
                OR @TrustedProcessingVersion <> N'skia-4.151.2-image-v1'))
       OR (@Kind = 1
           AND (@TrustedPixelWidth IS NOT NULL OR @TrustedPixelHeight IS NOT NULL
                OR @TrustedProcessingVersion <> N'pdf-copy-v1'))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'content-unavailable' AS Code,
               @AssetPublicId AS AssetPublicId,
               CAST(NULL AS TINYINT) AS Kind,
               CAST(NULL AS NVARCHAR(63)) AS TrustedBlobContainer,
               CAST(NULL AS NVARCHAR(1024)) AS TrustedBlobObjectName,
               CAST(NULL AS NVARCHAR(100)) AS TrustedBlobETag,
               CAST(NULL AS NVARCHAR(200)) AS TrustedBlobVersionId,
               CAST(NULL AS BINARY(32)) AS TrustedContentHash,
               CAST(NULL AS NVARCHAR(100)) AS TrustedMimeType,
               CAST(NULL AS BIGINT) AS TrustedContentLength,
               CAST(NULL AS INT) AS TrustedPixelWidth,
               CAST(NULL AS INT) AS TrustedPixelHeight,
               CAST(NULL AS NVARCHAR(100)) AS TrustedProcessingVersion,
               CAST(NULL AS DATETIME2(3)) AS TrustedCreatedAtUtc,
               CAST(NULL AS NVARCHAR(260)) AS OriginalFileName,
               CAST(NULL AS BINARY(8)) AS RowVersion;
        RETURN;
    END;

    SELECT CAST(1 AS BIT) AS Succeeded, N'trusted' AS Code,
           @StoredAssetPublicId AS AssetPublicId,
           @Kind AS Kind,
           @TrustedBlobContainer AS TrustedBlobContainer,
           @TrustedBlobObjectName AS TrustedBlobObjectName,
           @TrustedBlobETag AS TrustedBlobETag,
           @TrustedBlobVersionId AS TrustedBlobVersionId,
           @TrustedContentHash AS TrustedContentHash,
           @TrustedMimeType AS TrustedMimeType,
           @TrustedContentLength AS TrustedContentLength,
           @TrustedPixelWidth AS TrustedPixelWidth,
           @TrustedPixelHeight AS TrustedPixelHeight,
           @TrustedProcessingVersion AS TrustedProcessingVersion,
           @TrustedCreatedAtUtc AS TrustedCreatedAtUtc,
           @OriginalFileName AS OriginalFileName,
           @AssetRowVersion AS RowVersion;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAsset_List
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ProjectId BIGINT;
    SELECT @ProjectId = projects.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id
       AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    INNER JOIN dbo.FundingPlatform_Projects AS projects
        ON projects.OrganizationId = organizations.Id AND projects.IsActive = 1
    WHERE organizations.PublicId = @OrganizationPublicId
      AND organizations.IsActive = 1
      AND projects.PublicId = @ProjectPublicId
      AND users.PublicId = @UserPublicId;

    IF @ProjectId IS NULL
        THROW 55604, N'Project was not found.', 1;

    SELECT PublicId AS ProjectPublicId, PublicationStatus,
           RowVersion AS ProjectRowVersion
    FROM dbo.FundingPlatform_Projects
    WHERE Id = @ProjectId;

    /* Blob locations and content hashes remain absent from collection metadata. */
    SELECT PublicId AS AssetPublicId,
           Kind,
           OriginalFileName,
           DisplayName,
           VerifiedMimeType,
           ContentLength,
           PixelWidth,
           PixelHeight,
           TrustedMimeType,
           TrustedContentLength,
           TrustedPixelWidth,
           TrustedPixelHeight,
           TrustedProcessingVersion,
           TrustedCreatedAtUtc,
           StorageStatus,
           ScanStatus,
           ScanProvider,
           ScanResultCode,
           AltText,
           Caption,
           SortOrder,
           IsCover,
           CAST(CASE WHEN StorageStatus = 2 AND ScanStatus = 1
                          AND TrustedContentHash IS NOT NULL
                          AND TrustedMimeType IS NOT NULL
                          AND TrustedContentLength IS NOT NULL
                          AND TrustedProcessingVersion IS NOT NULL
                          AND TrustedCreatedAtUtc IS NOT NULL
                     THEN 1 ELSE 0 END AS BIT) AS ContentAvailable,
           CreatedAtUtc,
           UpdatedAtUtc,
           RowVersion
    FROM dbo.FundingPlatform_ProjectAssets
    WHERE ProjectId = @ProjectId AND IsDeleted = 0
    ORDER BY SortOrder, Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAssetScan_WatchdogTimeout
    @BatchSize INT,
    @TimeoutSeconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @BatchSize IS NULL OR @BatchSize NOT BETWEEN 1 AND 100
        THROW 55714, N'BatchSize must be between 1 and 100.', 1;
    IF @TimeoutSeconds IS NULL OR @TimeoutSeconds NOT BETWEEN 60 AND 86400
       OR @NowUtc IS NULL
        THROW 55715, N'A timeout between 60 seconds and one day and NowUtc are required.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @CutoffUtc DATETIME2(3) = DATEADD(SECOND, -@TimeoutSeconds, @NowUtc);
    DECLARE @TimedOut TABLE
    (
        Id BIGINT NOT NULL PRIMARY KEY,
        ProjectId BIGINT NOT NULL,
        PublicId UNIQUEIDENTIFIER NOT NULL,
        QuarantineBlobETag NVARCHAR(100) NOT NULL,
        AssetRowVersion BINARY(8) NOT NULL,
        EventId UNIQUEIDENTIFIER NULL,
        ProviderEventId NVARCHAR(200) NULL
    );
    DECLARE @UpdatedProjects TABLE
    (
        ProjectId BIGINT NOT NULL PRIMARY KEY,
        ProjectRowVersion BINARY(8) NOT NULL
    );

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_ProjectWatchdog038;

    BEGIN TRY
        ;WITH Due AS
        (
            SELECT TOP (@BatchSize) assets.*
            FROM dbo.FundingPlatform_ProjectAssets AS assets
                 WITH (UPDLOCK, READPAST, ROWLOCK)
            WHERE assets.IsDeleted = 0
              AND assets.ScanProvider = 1
              AND assets.StorageStatus = 1 AND assets.ScanStatus = 0
              AND assets.ScanStartedAtUtc IS NOT NULL
              AND assets.ScanStartedAtUtc <= @CutoffUtc
            ORDER BY assets.ScanStartedAtUtc, assets.Id
        )
        UPDATE Due
        SET StorageStatus = 3, ScanStatus = 4,
            ScanResultCode = N'defender-timeout',
            ScanCompletedAtUtc = @NowUtc,
            TrustedBlobContainer = NULL, TrustedBlobObjectName = NULL,
            TrustedBlobETag = NULL, TrustedBlobVersionId = NULL,
            TrustedMimeType = NULL, TrustedContentLength = NULL,
            TrustedContentHash = NULL, TrustedPixelWidth = NULL,
            TrustedPixelHeight = NULL, TrustedProcessingVersion = NULL,
            TrustedCreatedAtUtc = NULL,
            IsCover = 0, UpdatedAtUtc = @NowUtc
        OUTPUT inserted.Id, inserted.ProjectId, inserted.PublicId,
               inserted.QuarantineBlobETag, inserted.RowVersion
        INTO @TimedOut
            (Id, ProjectId, PublicId, QuarantineBlobETag, AssetRowVersion);

        UPDATE @TimedOut
        SET EventId = NEWID(),
            ProviderEventId = N'defender-timeout:' + CONVERT(NVARCHAR(36), PublicId);

        INSERT INTO dbo.FundingPlatform_ProjectAssetScanEvents
            (EventId, ProjectAssetId, ScanProvider, ProviderEventId, PayloadHash,
             FromStatus, ToStatus, ProviderObservedStatus,
             QuarantineBlobETag, ReportedContentHash,
             ResultCode, ProviderResultCode, ResultRowVersion,
             OccurredAtUtc, CreatedAtUtc)
        SELECT timedOut.EventId, timedOut.Id, 1, timedOut.ProviderEventId,
               HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
                   timedOut.ProviderEventId COLLATE Latin1_General_100_BIN2_UTF8))),
               0, 4, 4, timedOut.QuarantineBlobETag, NULL,
               N'defender-timeout', N'defender-timeout',
               timedOut.AssetRowVersion, @NowUtc, @NowUtc
        FROM @TimedOut AS timedOut;

        UPDATE projects
        SET UpdatedAtUtc = @NowUtc
        OUTPUT inserted.Id, inserted.RowVersion
            INTO @UpdatedProjects (ProjectId, ProjectRowVersion)
        FROM dbo.FundingPlatform_Projects AS projects
        WHERE EXISTS (SELECT 1 FROM @TimedOut AS timedOut
                      WHERE timedOut.ProjectId = projects.Id);

        INSERT INTO dbo.FundingPlatform_OutboxMessages
            (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
             OccurredAtUtc, AvailableAtUtc)
        SELECT timedOut.EventId, N'ProjectAssetScanTimedOut', N'ProjectAsset',
               CONVERT(NVARCHAR(100), timedOut.PublicId),
               (SELECT timedOut.EventId AS eventId,
                       timedOut.PublicId AS assetPublicId,
                       CAST(1 AS TINYINT) AS scanProvider,
                       CAST(4 AS TINYINT) AS scanStatus,
                       CAST(3 AS TINYINT) AS storageStatus,
                       N'defender-timeout' AS resultCode
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
               @NowUtc, @NowUtc
        FROM @TimedOut AS timedOut;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ProjectWatchdog038;
        THROW;
    END CATCH;

    SELECT timedOut.PublicId AS ProjectAssetPublicId,
           CAST(3 AS TINYINT) AS StorageStatus,
           CAST(4 AS TINYINT) AS ScanStatus,
           CAST(1 AS TINYINT) AS ScanProvider,
           timedOut.AssetRowVersion,
           updatedProjects.ProjectRowVersion
    FROM @TimedOut AS timedOut
    INNER JOIN @UpdatedProjects AS updatedProjects
        ON updatedProjects.ProjectId = timedOut.ProjectId
    ORDER BY timedOut.PublicId;
END;
GO
