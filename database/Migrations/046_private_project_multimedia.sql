/* 046: private MP4 and UTF-8 attachments. No public playback, no scan bypass.
   Originals are copied exactly; the bounded probe is not video sanitization.
   Existing constraints are extended, not disabled; all tenant/ETag/retention guards remain. */
SET XACT_ABORT ON;
GO
ALTER TABLE dbo.FundingPlatform_ProjectAssets DROP CONSTRAINT FundingPlatform_CK_ProjectAssets_File;
ALTER TABLE dbo.FundingPlatform_ProjectAssets WITH CHECK ADD CONSTRAINT FundingPlatform_CK_ProjectAssets_File
CHECK (
            NULLIF(LTRIM(RTRIM(OriginalFileName)), N'') IS NOT NULL
            AND LEN(OriginalFileName) <= 260
            AND CHARINDEX(N'/', OriginalFileName) = 0
            AND CHARINDEX(N'\', OriginalFileName) = 0
            AND CHARINDEX(CHAR(10), OriginalFileName) = 0
            AND CHARINDEX(CHAR(13), OriginalFileName) = 0
            AND
            (
                (Kind = 0 AND
                 (
                     (LOWER(VerifiedMimeType) = N'image/jpeg'
                      AND (RIGHT(LOWER(OriginalFileName), 4) = N'.jpg'
                           OR RIGHT(LOWER(OriginalFileName), 5) = N'.jpeg'))
                     OR (LOWER(VerifiedMimeType) = N'image/png'
                         AND RIGHT(LOWER(OriginalFileName), 4) = N'.png')
                     OR (LOWER(VerifiedMimeType) = N'image/webp'
                         AND RIGHT(LOWER(OriginalFileName), 5) = N'.webp')
                 ))
                OR ((Kind = 1 AND LOWER(VerifiedMimeType) = N'application/pdf'
                    AND RIGHT(LOWER(OriginalFileName), 4) = N'.pdf') OR (Kind = 1 AND LOWER(VerifiedMimeType) = N'text/plain'
                    AND RIGHT(LOWER(OriginalFileName), 4) = N'.txt' AND ContentLength <= 1048576) OR (Kind = 2 AND LOWER(VerifiedMimeType) = N'video/mp4'
                    AND RIGHT(LOWER(OriginalFileName), 4) = N'.mp4'))
            )
        );
GO
ALTER TABLE dbo.FundingPlatform_ProjectAssets DROP CONSTRAINT FundingPlatform_CK_ProjectAssets_ContentLength;
ALTER TABLE dbo.FundingPlatform_ProjectAssets WITH CHECK ADD CONSTRAINT FundingPlatform_CK_ProjectAssets_ContentLength
CHECK ((Kind = 0 AND ContentLength BETWEEN 1 AND 10485760)
               OR (Kind IN (1, 2) AND ContentLength BETWEEN 1 AND 26214400));
GO
ALTER TABLE dbo.FundingPlatform_ProjectAssets DROP CONSTRAINT FundingPlatform_CK_ProjectAssets_ImageDimensions;
ALTER TABLE dbo.FundingPlatform_ProjectAssets WITH CHECK ADD CONSTRAINT FundingPlatform_CK_ProjectAssets_ImageDimensions
CHECK ((Kind = 0 AND PixelWidth IS NOT NULL AND PixelHeight IS NOT NULL
                AND PixelWidth BETWEEN 1 AND 32768
                AND PixelHeight BETWEEN 1 AND 32768
                AND CONVERT(BIGINT, PixelWidth) * CONVERT(BIGINT, PixelHeight) <= 25000000)
               OR (Kind IN (1, 2) AND PixelWidth IS NULL AND PixelHeight IS NULL));
GO
ALTER TABLE dbo.FundingPlatform_ProjectAssets DROP CONSTRAINT FundingPlatform_CK_ProjectAssets_QuarantineObject;
ALTER TABLE dbo.FundingPlatform_ProjectAssets WITH CHECK ADD CONSTRAINT FundingPlatform_CK_ProjectAssets_QuarantineObject
CHECK (
            TRY_CONVERT(UNIQUEIDENTIFIER, LEFT(QuarantineBlobObjectName, 36)) IS NOT NULL
            AND SUBSTRING(QuarantineBlobObjectName, 37, 1) = N'/'
            AND SUBSTRING(QuarantineBlobObjectName, 38, 32) =
                LOWER(SUBSTRING(QuarantineBlobObjectName, 38, 32))
            AND SUBSTRING(QuarantineBlobObjectName, 38, 32)
                COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[^0-9a-f]%'
            AND SUBSTRING(QuarantineBlobObjectName, 70, 1) = N'.'
            AND CHARINDEX(N'/', QuarantineBlobObjectName, 38) = 0
            AND CHARINDEX(N'\', QuarantineBlobObjectName) = 0
            AND CHARINDEX(N'?', QuarantineBlobObjectName) = 0
            AND CHARINDEX(N'#', QuarantineBlobObjectName) = 0
            AND
            (
                (LOWER(VerifiedMimeType) = N'image/jpeg'
                 AND (RIGHT(LOWER(QuarantineBlobObjectName), 4) = N'.jpg'
                      OR RIGHT(LOWER(QuarantineBlobObjectName), 5) = N'.jpeg')
                 AND LEN(QuarantineBlobObjectName) IN (73, 74))
                OR (LOWER(VerifiedMimeType) = N'image/png'
                    AND RIGHT(LOWER(QuarantineBlobObjectName), 4) = N'.png'
                    AND LEN(QuarantineBlobObjectName) = 73)
                OR (LOWER(VerifiedMimeType) = N'image/webp'
                    AND RIGHT(LOWER(QuarantineBlobObjectName), 5) = N'.webp'
                    AND LEN(QuarantineBlobObjectName) = 74)
                OR ((LOWER(VerifiedMimeType) = N'application/pdf'
                    AND RIGHT(LOWER(QuarantineBlobObjectName), 4) = N'.pdf'
                    AND LEN(QuarantineBlobObjectName) = 73) OR (LOWER(VerifiedMimeType) = N'text/plain'
                    AND RIGHT(LOWER(QuarantineBlobObjectName), 4) = N'.txt'
                    AND LEN(QuarantineBlobObjectName) = 73) OR (LOWER(VerifiedMimeType) = N'video/mp4'
                    AND RIGHT(LOWER(QuarantineBlobObjectName), 4) = N'.mp4'
                    AND LEN(QuarantineBlobObjectName) = 73))
            )
        );
GO
ALTER TABLE dbo.FundingPlatform_ProjectAssetUploadIntents DROP CONSTRAINT FundingPlatform_CK_ProjectAssetUploadIntents_File;
ALTER TABLE dbo.FundingPlatform_ProjectAssetUploadIntents WITH CHECK ADD CONSTRAINT FundingPlatform_CK_ProjectAssetUploadIntents_File
CHECK (
            NULLIF(LTRIM(RTRIM(OriginalFileName)), N'') IS NOT NULL
            AND CHARINDEX(N'/', OriginalFileName) = 0
            AND CHARINDEX(N'\', OriginalFileName) = 0
            AND CHARINDEX(CHAR(10), OriginalFileName) = 0
            AND CHARINDEX(CHAR(13), OriginalFileName) = 0
            AND
            (
                (Kind = 0 AND
                 (
                     (LOWER(DeclaredMimeType) = N'image/jpeg'
                      AND (RIGHT(LOWER(OriginalFileName), 4) = N'.jpg'
                           OR RIGHT(LOWER(OriginalFileName), 5) = N'.jpeg'))
                     OR (LOWER(DeclaredMimeType) = N'image/png'
                         AND RIGHT(LOWER(OriginalFileName), 4) = N'.png')
                     OR (LOWER(DeclaredMimeType) = N'image/webp'
                         AND RIGHT(LOWER(OriginalFileName), 5) = N'.webp')
                 ))
                OR ((Kind = 1 AND LOWER(DeclaredMimeType) = N'application/pdf'
                    AND RIGHT(LOWER(OriginalFileName), 4) = N'.pdf') OR (Kind = 1 AND LOWER(DeclaredMimeType) = N'text/plain'
                    AND RIGHT(LOWER(OriginalFileName), 4) = N'.txt' AND ExpectedContentLength <= 1048576 AND MaxContentLength <= 1048576) OR (Kind = 2 AND LOWER(DeclaredMimeType) = N'video/mp4'
                    AND RIGHT(LOWER(OriginalFileName), 4) = N'.mp4'))
            )
        );
GO
ALTER TABLE dbo.FundingPlatform_ProjectAssetUploadIntents DROP CONSTRAINT FundingPlatform_CK_ProjectAssetUploadIntents_Length;
ALTER TABLE dbo.FundingPlatform_ProjectAssetUploadIntents WITH CHECK ADD CONSTRAINT FundingPlatform_CK_ProjectAssetUploadIntents_Length
CHECK (ExpectedContentLength BETWEEN 1 AND MaxContentLength
               AND ((Kind = 0 AND MaxContentLength BETWEEN 1 AND 10485760)
                    OR (Kind IN (1, 2) AND MaxContentLength BETWEEN 1 AND 26214400)));
GO
ALTER TABLE dbo.FundingPlatform_ProjectAssetUploadIntents DROP CONSTRAINT FundingPlatform_CK_ProjectAssetUploadIntents_OpaqueObjects;
ALTER TABLE dbo.FundingPlatform_ProjectAssetUploadIntents WITH CHECK ADD CONSTRAINT FundingPlatform_CK_ProjectAssetUploadIntents_OpaqueObjects
CHECK (
            TRY_CONVERT(UNIQUEIDENTIFIER, LEFT(IncomingBlobObjectName, 36)) IS NOT NULL
            AND TRY_CONVERT(UNIQUEIDENTIFIER, LEFT(QuarantineBlobObjectName, 36)) IS NOT NULL
            AND TRY_CONVERT(UNIQUEIDENTIFIER, LEFT(TrustedBlobObjectName, 36)) IS NOT NULL
            AND SUBSTRING(IncomingBlobObjectName, 37, 1) = N'/'
            AND SUBSTRING(QuarantineBlobObjectName, 37, 1) = N'/'
            AND SUBSTRING(TrustedBlobObjectName, 37, 1) = N'/'
            AND SUBSTRING(IncomingBlobObjectName, 38, 32) =
                LOWER(SUBSTRING(IncomingBlobObjectName, 38, 32))
            AND SUBSTRING(QuarantineBlobObjectName, 38, 32) =
                LOWER(SUBSTRING(QuarantineBlobObjectName, 38, 32))
            AND SUBSTRING(TrustedBlobObjectName, 38, 32) =
                LOWER(SUBSTRING(TrustedBlobObjectName, 38, 32))
            AND SUBSTRING(IncomingBlobObjectName, 38, 32)
                COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[^0-9a-f]%'
            AND SUBSTRING(QuarantineBlobObjectName, 38, 32)
                COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[^0-9a-f]%'
            AND SUBSTRING(TrustedBlobObjectName, 38, 32)
                COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[^0-9a-f]%'
            AND SUBSTRING(IncomingBlobObjectName, 70, 1) = N'.'
            AND SUBSTRING(QuarantineBlobObjectName, 70, 1) = N'.'
            AND SUBSTRING(TrustedBlobObjectName, 70, 1) = N'.'
            AND CHARINDEX(N'/', IncomingBlobObjectName, 38) = 0
            AND CHARINDEX(N'/', QuarantineBlobObjectName, 38) = 0
            AND CHARINDEX(N'/', TrustedBlobObjectName, 38) = 0
            AND CHARINDEX(N'\', IncomingBlobObjectName) = 0
            AND CHARINDEX(N'\', QuarantineBlobObjectName) = 0
            AND CHARINDEX(N'\', TrustedBlobObjectName) = 0
            AND CHARINDEX(N'?', IncomingBlobObjectName) = 0
            AND CHARINDEX(N'?', QuarantineBlobObjectName) = 0
            AND CHARINDEX(N'?', TrustedBlobObjectName) = 0
            AND CHARINDEX(N'#', IncomingBlobObjectName) = 0
            AND CHARINDEX(N'#', QuarantineBlobObjectName) = 0
            AND CHARINDEX(N'#', TrustedBlobObjectName) = 0
            AND
            (
                (LOWER(DeclaredMimeType) = N'image/jpeg'
                 AND (RIGHT(LOWER(IncomingBlobObjectName), 4) = N'.jpg'
                      OR RIGHT(LOWER(IncomingBlobObjectName), 5) = N'.jpeg')
                 AND ((RIGHT(LOWER(IncomingBlobObjectName), 4) = N'.jpg'
                       AND RIGHT(LOWER(QuarantineBlobObjectName), 4) = N'.jpg'
                       AND RIGHT(LOWER(TrustedBlobObjectName), 4) = N'.jpg')
                      OR (RIGHT(LOWER(IncomingBlobObjectName), 5) = N'.jpeg'
                          AND RIGHT(LOWER(QuarantineBlobObjectName), 5) = N'.jpeg'
                          AND RIGHT(LOWER(TrustedBlobObjectName), 5) = N'.jpeg'))
                 AND LEN(IncomingBlobObjectName) IN (73, 74)
                 AND LEN(QuarantineBlobObjectName) = LEN(IncomingBlobObjectName)
                 AND LEN(TrustedBlobObjectName) = LEN(IncomingBlobObjectName))
                OR (LOWER(DeclaredMimeType) = N'image/png'
                    AND RIGHT(LOWER(IncomingBlobObjectName), 4) = N'.png'
                    AND RIGHT(LOWER(QuarantineBlobObjectName), 4) = N'.png'
                    AND RIGHT(LOWER(TrustedBlobObjectName), 4) = N'.png'
                    AND LEN(IncomingBlobObjectName) = 73
                    AND LEN(QuarantineBlobObjectName) = 73
                    AND LEN(TrustedBlobObjectName) = 73)
                OR (LOWER(DeclaredMimeType) = N'image/webp'
                    AND RIGHT(LOWER(IncomingBlobObjectName), 5) = N'.webp'
                    AND RIGHT(LOWER(QuarantineBlobObjectName), 5) = N'.webp'
                    AND RIGHT(LOWER(TrustedBlobObjectName), 5) = N'.webp'
                    AND LEN(IncomingBlobObjectName) = 74
                    AND LEN(QuarantineBlobObjectName) = 74
                    AND LEN(TrustedBlobObjectName) = 74)
                OR ((LOWER(DeclaredMimeType) = N'application/pdf'
                    AND RIGHT(LOWER(IncomingBlobObjectName), 4) = N'.pdf'
                    AND RIGHT(LOWER(QuarantineBlobObjectName), 4) = N'.pdf'
                    AND RIGHT(LOWER(TrustedBlobObjectName), 4) = N'.pdf'
                    AND LEN(IncomingBlobObjectName) = 73
                    AND LEN(QuarantineBlobObjectName) = 73
                    AND LEN(TrustedBlobObjectName) = 73) OR (LOWER(DeclaredMimeType) = N'text/plain'
                    AND RIGHT(LOWER(IncomingBlobObjectName), 4) = N'.txt'
                    AND RIGHT(LOWER(QuarantineBlobObjectName), 4) = N'.txt'
                    AND RIGHT(LOWER(TrustedBlobObjectName), 4) = N'.txt'
                    AND LEN(IncomingBlobObjectName) = 73
                    AND LEN(QuarantineBlobObjectName) = 73
                    AND LEN(TrustedBlobObjectName) = 73) OR (LOWER(DeclaredMimeType) = N'video/mp4'
                    AND RIGHT(LOWER(IncomingBlobObjectName), 4) = N'.mp4'
                    AND RIGHT(LOWER(QuarantineBlobObjectName), 4) = N'.mp4'
                    AND RIGHT(LOWER(TrustedBlobObjectName), 4) = N'.mp4'
                    AND LEN(IncomingBlobObjectName) = 73
                    AND LEN(QuarantineBlobObjectName) = 73
                    AND LEN(TrustedBlobObjectName) = 73))
            )
        );
GO
ALTER TABLE dbo.FundingPlatform_ProjectAssets DROP CONSTRAINT FundingPlatform_CK_ProjectAssets_TrustedObject;
ALTER TABLE dbo.FundingPlatform_ProjectAssets WITH CHECK ADD CONSTRAINT FundingPlatform_CK_ProjectAssets_TrustedObject
CHECK (
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
                 OR ((LOWER(TrustedMimeType) = N'application/pdf'
                     AND RIGHT(LOWER(TrustedBlobObjectName), 4) = N'.pdf'
                     AND LEN(TrustedBlobObjectName) = 73) OR (LOWER(TrustedMimeType) = N'text/plain'
                     AND RIGHT(LOWER(TrustedBlobObjectName), 4) = N'.txt'
                     AND LEN(TrustedBlobObjectName) = 73) OR (LOWER(TrustedMimeType) = N'video/mp4'
                     AND RIGHT(LOWER(TrustedBlobObjectName), 4) = N'.mp4'
                     AND LEN(TrustedBlobObjectName) = 73))
             ))
        );
GO
ALTER TABLE dbo.FundingPlatform_ProjectAssets DROP CONSTRAINT FundingPlatform_CK_ProjectAssets_TrustedManifest;
ALTER TABLE dbo.FundingPlatform_ProjectAssets WITH CHECK ADD CONSTRAINT FundingPlatform_CK_ProjectAssets_TrustedManifest
CHECK (
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
                 ((Kind = 1
                  AND TrustedMimeType = N'application/pdf'
                  AND TrustedMimeType COLLATE Latin1_General_100_BIN2 =
                      LOWER(VerifiedMimeType) COLLATE Latin1_General_100_BIN2
                  AND TrustedContentLength BETWEEN 1 AND 26214400
                  AND TrustedContentLength = ContentLength
                  AND TrustedContentHash = ContentHash
                  AND TrustedPixelWidth IS NULL
                  AND TrustedPixelHeight IS NULL
                  AND TrustedProcessingVersion = N'pdf-copy-v1') OR (Kind = 1
                  AND TrustedMimeType = N'text/plain'
                  AND TrustedMimeType COLLATE Latin1_General_100_BIN2 =
                      LOWER(VerifiedMimeType) COLLATE Latin1_General_100_BIN2
                  AND TrustedContentLength BETWEEN 1 AND 1048576
                  AND TrustedContentLength = ContentLength
                  AND TrustedContentHash = ContentHash
                  AND TrustedPixelWidth IS NULL
                  AND TrustedPixelHeight IS NULL
                  AND TrustedProcessingVersion = N'utf8-copy-v1') OR (Kind = 2
                  AND TrustedMimeType = N'video/mp4'
                  AND TrustedMimeType COLLATE Latin1_General_100_BIN2 =
                      LOWER(VerifiedMimeType) COLLATE Latin1_General_100_BIN2
                  AND TrustedContentLength BETWEEN 1 AND 26214400
                  AND TrustedContentLength = ContentLength
                  AND TrustedContentHash = ContentHash
                  AND TrustedPixelWidth IS NULL
                  AND TrustedPixelHeight IS NULL
                  AND TrustedProcessingVersion = N'mp4-copy-v1'))
             ))
        );
GO
ALTER TABLE dbo.FundingPlatform_ProjectAssetScanEvents DROP CONSTRAINT FundingPlatform_CK_ProjectAssetScanEvents_Result;
ALTER TABLE dbo.FundingPlatform_ProjectAssetScanEvents WITH CHECK ADD CONSTRAINT FundingPlatform_CK_ProjectAssetScanEvents_Result
CHECK (
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
                     ((RevokedTrustedMimeType = N'application/pdf'
                      AND RevokedTrustedContentLength BETWEEN 1 AND 26214400
                      AND RevokedTrustedPixelWidth IS NULL
                      AND RevokedTrustedPixelHeight IS NULL
                      AND RevokedTrustedProcessingVersion = N'pdf-copy-v1') OR (RevokedTrustedMimeType = N'text/plain'
                      AND RevokedTrustedContentLength BETWEEN 1 AND 1048576
                      AND RevokedTrustedPixelWidth IS NULL
                      AND RevokedTrustedPixelHeight IS NULL
                      AND RevokedTrustedProcessingVersion = N'utf8-copy-v1') OR (RevokedTrustedMimeType = N'video/mp4'
                      AND RevokedTrustedContentLength BETWEEN 1 AND 26214400
                      AND RevokedTrustedPixelWidth IS NULL
                      AND RevokedTrustedPixelHeight IS NULL
                      AND RevokedTrustedProcessingVersion = N'mp4-copy-v1'))
                 ))
            )
        );
GO
ALTER TABLE dbo.FundingPlatform_ProjectAssetContentRetentionTasks DROP CONSTRAINT FundingPlatform_CK_ProjectAssetRetention_Manifest;
ALTER TABLE dbo.FundingPlatform_ProjectAssetContentRetentionTasks WITH CHECK ADD CONSTRAINT FundingPlatform_CK_ProjectAssetRetention_Manifest
CHECK (SourceId > 0 AND LEN(BlobContainer) BETWEEN 3 AND 63
         AND LEN(BlobObjectName) BETWEEN 73 AND 74
         AND LEFT(BlobETag, 1) = N'"' AND RIGHT(BlobETag, 1) = N'"'
         AND LEN(BlobETag) BETWEEN 3 AND 100
         AND CHARINDEX(CHAR(10), BlobETag) = 0 AND CHARINDEX(CHAR(13), BlobETag) = 0
         AND ((MimeType IN (N'image/jpeg', N'image/png', N'image/webp')
               AND ContentLength BETWEEN 1 AND 10485760)
              OR ((MimeType = N'application/pdf' AND ContentLength BETWEEN 1 AND 26214400) OR (MimeType = N'text/plain' AND ContentLength BETWEEN 1 AND 1048576) OR (MimeType = N'video/mp4' AND ContentLength BETWEEN 1 AND 26214400)))
         AND ((BlobKind = 0 AND SourceContentHash IS NULL AND ManifestProcessingVersion IS NULL)
              OR (BlobKind = 1 AND SourceContentHash IS NOT NULL
                  AND ManifestProcessingVersion IS NOT NULL
                  AND ManifestProcessingVersion IN
                      (N'pdf-copy-v1', N'utf8-copy-v1', N'mp4-copy-v1', N'legacy-unsanitized-v0', N'skia-4.151.2-image-v1'))));
GO
DECLARE @Definition NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Create', N'P'));
IF @Definition IS NULL THROW 55950, N'Project media migration prerequisite is missing.', 1;
IF CHARINDEX(N'@Kind NOT IN (0, 1)', @Definition) = 0 THROW 55951, N'Project media migration anchor changed.', 1;
SET @Definition = REPLACE(@Definition, N'@Kind NOT IN (0, 1)', N'@Kind NOT IN (0, 1, 2)');
IF CHARINDEX(N'(@Kind = 1 AND @DeclaredMimeType = N''application/pdf''
                  AND RIGHT(LOWER(@OriginalFileName), 4) = N''.pdf'')', @Definition) = 0 THROW 55951, N'Project media migration anchor changed.', 1;
SET @Definition = REPLACE(@Definition, N'(@Kind = 1 AND @DeclaredMimeType = N''application/pdf''
                  AND RIGHT(LOWER(@OriginalFileName), 4) = N''.pdf'')', N'((@Kind = 1 AND @DeclaredMimeType = N''application/pdf'' AND RIGHT(LOWER(@OriginalFileName), 4) = N''.pdf'')
 OR (@Kind = 1 AND @DeclaredMimeType = N''text/plain'' AND RIGHT(LOWER(@OriginalFileName), 4) = N''.txt'' AND @MaxContentLength <= 1048576)
 OR (@Kind = 2 AND @DeclaredMimeType = N''video/mp4'' AND RIGHT(LOWER(@OriginalFileName), 4) = N''.mp4''))');
IF CHARINDEX(N'(@Kind = 1 AND (@MaxContentLength', @Definition) = 0 THROW 55951, N'Project media migration anchor changed.', 1;
SET @Definition = REPLACE(@Definition, N'(@Kind = 1 AND (@MaxContentLength', N'(@Kind IN (1, 2) AND (@MaxContentLength');
IF CHARINDEX(N'@DeclaredMimeType IN (N''image/png'', N''application/pdf'')', @Definition) = 0 THROW 55951, N'Project media migration anchor changed.', 1;
SET @Definition = REPLACE(@Definition, N'@DeclaredMimeType IN (N''image/png'', N''application/pdf'')', N'@DeclaredMimeType IN (N''image/png'', N''application/pdf'', N''text/plain'', N''video/mp4'')');
IF CHARINDEX(N'CASE WHEN @DeclaredMimeType = N''image/png'' THEN N''.png'' ELSE N''.pdf'' END', @Definition) = 0 THROW 55951, N'Project media migration anchor changed.', 1;
SET @Definition = REPLACE(@Definition, N'CASE WHEN @DeclaredMimeType = N''image/png'' THEN N''.png'' ELSE N''.pdf'' END', N'CASE @DeclaredMimeType WHEN N''image/png'' THEN N''.png'' WHEN N''text/plain'' THEN N''.txt'' WHEN N''video/mp4'' THEN N''.mp4'' ELSE N''.pdf'' END');
/* Azure may persist CREATE OR ALTER as CREATE with padding; rebuild the known header. */
DECLARE @HeaderEnd INT = CHARINDEX(N'dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Create', @Definition, CHARINDEX(N'PROCEDURE', @Definition));
IF @HeaderEnd = 0 THROW 55951, N'Project media procedure header changed.', 1;
SET @Definition = N'ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Create' + SUBSTRING(@Definition, @HeaderEnd + LEN(N'dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Create'), LEN(@Definition));
EXEC sys.sp_executesql @Definition;
GO
DECLARE @Definition NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Complete', N'P'));
IF @Definition IS NULL THROW 55950, N'Project media migration prerequisite is missing.', 1;
IF CHARINDEX(N'(@Kind = 1 AND
                 (@VerifiedMimeType <> N''application/pdf''
                  OR @ActualContentLength > 26214400
                  OR @PixelWidth IS NOT NULL OR @PixelHeight IS NOT NULL))', @Definition) = 0 THROW 55951, N'Project media migration anchor changed.', 1;
SET @Definition = REPLACE(@Definition, N'(@Kind = 1 AND
                 (@VerifiedMimeType <> N''application/pdf''
                  OR @ActualContentLength > 26214400
                  OR @PixelWidth IS NOT NULL OR @PixelHeight IS NOT NULL))', N'(@Kind IN (1, 2) AND
 ((@Kind = 1 AND @VerifiedMimeType NOT IN (N''application/pdf'', N''text/plain'')) OR (@Kind = 2 AND @VerifiedMimeType <> N''video/mp4'')
 OR (@VerifiedMimeType = N''text/plain'' AND @ActualContentLength > 1048576)
 OR @ActualContentLength > 26214400 OR @PixelWidth IS NOT NULL OR @PixelHeight IS NOT NULL))');
IF CHARINDEX(N'ELSE IF @Kind = 1 AND', @Definition) = 0 THROW 55951, N'Project media migration anchor changed.', 1;
SET @Definition = REPLACE(@Definition, N'ELSE IF @Kind = 1 AND', N'ELSE IF @Kind IN (1, 2) AND');
IF CHARINDEX(N'AND Kind = 1 AND IsDeleted = 0', @Definition) = 0 THROW 55951, N'Project media migration anchor changed.', 1;
SET @Definition = REPLACE(@Definition, N'AND Kind = 1 AND IsDeleted = 0', N'AND Kind IN (1, 2) AND IsDeleted = 0');
/* Azure may persist CREATE OR ALTER as CREATE with padding; rebuild the known header. */
DECLARE @HeaderEnd INT = CHARINDEX(N'dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Complete', @Definition, CHARINDEX(N'PROCEDURE', @Definition));
IF @HeaderEnd = 0 THROW 55951, N'Project media procedure header changed.', 1;
SET @Definition = N'ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Complete' + SUBSTRING(@Definition, @HeaderEnd + LEN(N'dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Complete'), LEN(@Definition));
EXEC sys.sp_executesql @Definition;
GO
DECLARE @Definition NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult', N'P'));
IF @Definition IS NULL THROW 55950, N'Project media migration prerequisite is missing.', 1;
IF CHARINDEX(N'(@StoredKind = 1
                    AND (@StoredVerifiedMimeType <> N''application/pdf''', @Definition) = 0 THROW 55951, N'Project media migration anchor changed.', 1;
SET @Definition = REPLACE(@Definition, N'(@StoredKind = 1
                    AND (@StoredVerifiedMimeType <> N''application/pdf''', N'(@StoredKind IN (1, 2)
 AND ((@StoredKind = 1 AND @StoredVerifiedMimeType NOT IN (N''application/pdf'', N''text/plain''))
 OR (@StoredKind = 2 AND @StoredVerifiedMimeType <> N''video/mp4'')
 OR (@StoredVerifiedMimeType = N''text/plain'' AND @TrustedContentLength > 1048576)');
IF CHARINDEX(N'@TrustedProcessingVersion <> N''pdf-copy-v1''', @Definition) = 0 THROW 55951, N'Project media migration anchor changed.', 1;
SET @Definition = REPLACE(@Definition, N'@TrustedProcessingVersion <> N''pdf-copy-v1''', N'@TrustedProcessingVersion <> CASE @StoredVerifiedMimeType WHEN N''application/pdf'' THEN N''pdf-copy-v1'' WHEN N''text/plain'' THEN N''utf8-copy-v1'' WHEN N''video/mp4'' THEN N''mp4-copy-v1'' ELSE N''unsupported'' END');
IF CHARINDEX(N'@StoredKind NOT IN (0, 1)', @Definition) = 0 THROW 55951, N'Project media migration anchor changed.', 1;
SET @Definition = REPLACE(@Definition, N'@StoredKind NOT IN (0, 1)', N'@StoredKind NOT IN (0, 1, 2)');
/* Azure may persist CREATE OR ALTER as CREATE with padding; rebuild the known header. */
DECLARE @HeaderEnd INT = CHARINDEX(N'dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult', @Definition, CHARINDEX(N'PROCEDURE', @Definition));
IF @HeaderEnd = 0 THROW 55951, N'Project media procedure header changed.', 1;
SET @Definition = N'ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult' + SUBSTRING(@Definition, @HeaderEnd + LEN(N'dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult'), LEN(@Definition));
EXEC sys.sp_executesql @Definition;
GO
DECLARE @Definition NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAsset_GetTrustedContent', N'P'));
IF @Definition IS NULL THROW 55950, N'Project media migration prerequisite is missing.', 1;
IF CHARINDEX(N'OR (@Kind = 1', @Definition) = 0 THROW 55951, N'Project media migration anchor changed.', 1;
SET @Definition = REPLACE(@Definition, N'OR (@Kind = 1', N'OR (@Kind IN (1, 2)');
IF CHARINDEX(N'@TrustedProcessingVersion <> N''pdf-copy-v1''', @Definition) = 0 THROW 55951, N'Project media migration anchor changed.', 1;
SET @Definition = REPLACE(@Definition, N'@TrustedProcessingVersion <> N''pdf-copy-v1''', N'@TrustedProcessingVersion <> CASE WHEN @Kind = 1 AND @TrustedMimeType = N''application/pdf'' THEN N''pdf-copy-v1'' WHEN @Kind = 1 AND @TrustedMimeType = N''text/plain'' THEN N''utf8-copy-v1'' WHEN @Kind = 2 AND @TrustedMimeType = N''video/mp4'' THEN N''mp4-copy-v1'' ELSE N''unsupported'' END');
/* Azure may persist CREATE OR ALTER as CREATE with padding; rebuild the known header. */
DECLARE @HeaderEnd INT = CHARINDEX(N'dbo.FundingPlatform_usp_ProjectAsset_GetTrustedContent', @Definition, CHARINDEX(N'PROCEDURE', @Definition));
IF @HeaderEnd = 0 THROW 55951, N'Project media procedure header changed.', 1;
SET @Definition = N'ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAsset_GetTrustedContent' + SUBSTRING(@Definition, @HeaderEnd + LEN(N'dbo.FundingPlatform_usp_ProjectAsset_GetTrustedContent'), LEN(@Definition));
EXEC sys.sp_executesql @Definition;
GO
DECLARE @Definition NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre038', N'P'));
IF @Definition IS NULL THROW 55950, N'Project media migration prerequisite is missing.', 1;
IF CHARINDEX(N'JSON_VALUE(messages.PayloadJson, N''$.kind'')) IN (0, 1)', @Definition) = 0 THROW 55951, N'Project media migration anchor changed.', 1;
SET @Definition = REPLACE(@Definition, N'JSON_VALUE(messages.PayloadJson, N''$.kind'')) IN (0, 1)', N'JSON_VALUE(messages.PayloadJson, N''$.kind'')) IN (0, 1, 2)');
/* Azure may persist CREATE OR ALTER as CREATE with padding; rebuild the known header. */
DECLARE @HeaderEnd INT = CHARINDEX(N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge', @Definition, CHARINDEX(N'PROCEDURE', @Definition));
IF @HeaderEnd = 0 THROW 55951, N'Project media procedure header changed.', 1;
SET @Definition = N'ALTER PROCEDURE dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre038' + SUBSTRING(@Definition, @HeaderEnd + LEN(N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge'), LEN(@Definition));
EXEC sys.sp_executesql @Definition;
GO
