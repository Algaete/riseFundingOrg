/* FundingPlatform - governed project assets foundation (036A).
   Requires migrations 001-035.

   Enum contract:
   - Kind: 0 Image, 1 Document, 2 Video (reserved; rejected by 036A writes).
   - Upload intent: 0 Pending, 1 Finalizing, 2 Completed, 3 Expired, 4 Rejected.
   - Storage: 0 AwaitingQuarantine, 1 Quarantined, 2 Trusted, 3 Failed.
   - Scan: 0 Pending, 1 Clean, 2 Malicious, 3 Failed, 4 TimedOut.
   - Provider: 0 DevelopmentFake, 1 MicrosoftDefender.

   Blob names use the opaque `<random-guid>/<32-lower-hex>.<ext>` format. They
   deliberately contain no organization, project, user or original-file-name data. No procedure in this
   migration exposes an incoming or quarantine path except the token-protected
   finalize lease. Trusted content has its own authenticated, fail-closed read.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF OBJECT_ID(N'dbo.FundingPlatform_Projects', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_Organizations', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_OrganizationUsers', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_Users', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_OutboxMessages', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ProjectPublicationEvents', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_Project_RequestPublication', N'P') IS NULL
    THROW 55601, N'Project assets require migrations 001-035.', 1;

CREATE TABLE dbo.FundingPlatform_ProjectAssets
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_ProjectAssets_PublicId DEFAULT (NEWSEQUENTIALID()),
    ProjectId BIGINT NOT NULL,
    Kind TINYINT NOT NULL,
    OriginalFileName NVARCHAR(260) NOT NULL,
    DisplayName NVARCHAR(200) NULL,
    VerifiedMimeType NVARCHAR(100) NOT NULL,
    ContentLength BIGINT NOT NULL,
    ContentHash BINARY(32) NOT NULL,
    PixelWidth INT NULL,
    PixelHeight INT NULL,
    QuarantineBlobContainer NVARCHAR(63) NOT NULL,
    QuarantineBlobObjectName NVARCHAR(1024) NOT NULL,
    QuarantineBlobETag NVARCHAR(100) NULL,
    QuarantineBlobVersionId NVARCHAR(200) NULL,
    TrustedBlobContainer NVARCHAR(63) NULL,
    TrustedBlobObjectName NVARCHAR(1024) NULL,
    TrustedBlobETag NVARCHAR(100) NULL,
    TrustedBlobVersionId NVARCHAR(200) NULL,
    StorageStatus TINYINT NOT NULL,
    ScanStatus TINYINT NOT NULL,
    ScanProvider TINYINT NOT NULL,
    ScanResultCode NVARCHAR(100) NULL,
    ScanStartedAtUtc DATETIME2(3) NULL,
    ScanCompletedAtUtc DATETIME2(3) NULL,
    AltText NVARCHAR(300) NULL,
    Caption NVARCHAR(1000) NULL,
    SortOrder SMALLINT NOT NULL,
    IsCover BIT NOT NULL
        CONSTRAINT FundingPlatform_DF_ProjectAssets_IsCover DEFAULT (0),
    IsDeleted BIT NOT NULL
        CONSTRAINT FundingPlatform_DF_ProjectAssets_IsDeleted DEFAULT (0),
    UploadedByUserId BIGINT NOT NULL,
    DeletedByUserId BIGINT NULL,
    DeletedAtUtc DATETIME2(3) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_ProjectAssets_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_ProjectAssets_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_ProjectAssets PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_ProjectAssets_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_ProjectAssets_IdProject UNIQUE (Id, ProjectId),
    CONSTRAINT FundingPlatform_UQ_ProjectAssets_QuarantineBlob
        UNIQUE (QuarantineBlobContainer, QuarantineBlobObjectName),
    CONSTRAINT FundingPlatform_FK_ProjectAssets_Projects
        FOREIGN KEY (ProjectId) REFERENCES dbo.FundingPlatform_Projects (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_ProjectAssets_UploadedBy
        FOREIGN KEY (UploadedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_ProjectAssets_DeletedBy
        FOREIGN KEY (DeletedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_ProjectAssets_Kind
        CHECK (Kind BETWEEN 0 AND 2),
    CONSTRAINT FundingPlatform_CK_ProjectAssets_File
        CHECK
        (
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
                OR (Kind = 1 AND LOWER(VerifiedMimeType) = N'application/pdf'
                    AND RIGHT(LOWER(OriginalFileName), 4) = N'.pdf')
            )
        ),
    CONSTRAINT FundingPlatform_CK_ProjectAssets_ContentLength
        CHECK ((Kind = 0 AND ContentLength BETWEEN 1 AND 10485760)
               OR (Kind = 1 AND ContentLength BETWEEN 1 AND 26214400)),
    CONSTRAINT FundingPlatform_CK_ProjectAssets_ImageDimensions
        CHECK ((Kind = 0 AND PixelWidth IS NOT NULL AND PixelHeight IS NOT NULL
                AND PixelWidth BETWEEN 1 AND 32768
                AND PixelHeight BETWEEN 1 AND 32768
                AND CONVERT(BIGINT, PixelWidth) * CONVERT(BIGINT, PixelHeight) <= 25000000)
               OR (Kind = 1 AND PixelWidth IS NULL AND PixelHeight IS NULL)),
    CONSTRAINT FundingPlatform_CK_ProjectAssets_QuarantineContainer
        CHECK
        (
            LEN(QuarantineBlobContainer) BETWEEN 3 AND 63
            AND QuarantineBlobContainer = LOWER(QuarantineBlobContainer)
            AND QuarantineBlobContainer COLLATE Latin1_General_100_BIN2
                NOT LIKE N'%[^a-z0-9-]%'
            AND LEFT(QuarantineBlobContainer, 1) <> N'-'
            AND RIGHT(QuarantineBlobContainer, 1) <> N'-'
            AND QuarantineBlobContainer NOT LIKE N'%--%'
        ),
    CONSTRAINT FundingPlatform_CK_ProjectAssets_QuarantineObject
        CHECK
        (
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
                OR (LOWER(VerifiedMimeType) = N'application/pdf'
                    AND RIGHT(LOWER(QuarantineBlobObjectName), 4) = N'.pdf'
                    AND LEN(QuarantineBlobObjectName) = 73)
            )
        ),
    CONSTRAINT FundingPlatform_CK_ProjectAssets_Statuses
        CHECK (StorageStatus BETWEEN 0 AND 3
               AND ScanStatus BETWEEN 0 AND 4
               AND ScanProvider BETWEEN 0 AND 1),
    CONSTRAINT FundingPlatform_CK_ProjectAssets_QuarantineReceipt
        CHECK ((StorageStatus = 0 AND QuarantineBlobETag IS NULL
                AND QuarantineBlobVersionId IS NULL AND ScanStatus = 0)
               OR (StorageStatus IN (1, 2, 3)
                   AND NULLIF(LTRIM(RTRIM(QuarantineBlobETag)), N'') IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_ProjectAssets_ReceiptValues
        CHECK ((QuarantineBlobETag IS NULL
                OR (LEN(QuarantineBlobETag) BETWEEN 3 AND 100
                    AND LEFT(QuarantineBlobETag, 1) = N'"'
                    AND RIGHT(QuarantineBlobETag, 1) = N'"'
                    AND CHARINDEX(CHAR(10), QuarantineBlobETag) = 0
                    AND CHARINDEX(CHAR(13), QuarantineBlobETag) = 0))
               AND (TrustedBlobETag IS NULL
                    OR (LEN(TrustedBlobETag) BETWEEN 3 AND 100
                        AND LEFT(TrustedBlobETag, 1) = N'"'
                        AND RIGHT(TrustedBlobETag, 1) = N'"'
                        AND CHARINDEX(CHAR(10), TrustedBlobETag) = 0
                        AND CHARINDEX(CHAR(13), TrustedBlobETag) = 0))
               AND (QuarantineBlobVersionId IS NULL
                    OR (CHARINDEX(CHAR(10), QuarantineBlobVersionId) = 0
                        AND CHARINDEX(CHAR(13), QuarantineBlobVersionId) = 0))
               AND (TrustedBlobVersionId IS NULL
                    OR (CHARINDEX(CHAR(10), TrustedBlobVersionId) = 0
                        AND CHARINDEX(CHAR(13), TrustedBlobVersionId) = 0))),
    CONSTRAINT FundingPlatform_CK_ProjectAssets_TrustedState
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
        ),
    CONSTRAINT FundingPlatform_CK_ProjectAssets_ScanState
        CHECK ((ScanStatus = 0 AND StorageStatus IN (0, 1) AND ScanCompletedAtUtc IS NULL)
               OR (ScanStatus = 1 AND StorageStatus = 2 AND ScanCompletedAtUtc IS NOT NULL)
               OR (ScanStatus BETWEEN 2 AND 4 AND StorageStatus = 3
                   AND ScanCompletedAtUtc IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_ProjectAssets_TrustedContainer
        CHECK
        (
            TrustedBlobContainer IS NULL
            OR
            (LEN(TrustedBlobContainer) BETWEEN 3 AND 63
             AND TrustedBlobContainer = LOWER(TrustedBlobContainer)
             AND TrustedBlobContainer COLLATE Latin1_General_100_BIN2
                 NOT LIKE N'%[^a-z0-9-]%'
             AND LEFT(TrustedBlobContainer, 1) <> N'-'
             AND RIGHT(TrustedBlobContainer, 1) <> N'-'
             AND TrustedBlobContainer NOT LIKE N'%--%')
        ),
    CONSTRAINT FundingPlatform_CK_ProjectAssets_TrustedObject
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
                 (LOWER(VerifiedMimeType) = N'image/jpeg'
                  AND (RIGHT(LOWER(TrustedBlobObjectName), 4) = N'.jpg'
                       OR RIGHT(LOWER(TrustedBlobObjectName), 5) = N'.jpeg')
                  AND LEN(TrustedBlobObjectName) IN (73, 74))
                 OR (LOWER(VerifiedMimeType) = N'image/png'
                     AND RIGHT(LOWER(TrustedBlobObjectName), 4) = N'.png'
                     AND LEN(TrustedBlobObjectName) = 73)
                 OR (LOWER(VerifiedMimeType) = N'image/webp'
                     AND RIGHT(LOWER(TrustedBlobObjectName), 5) = N'.webp'
                     AND LEN(TrustedBlobObjectName) = 74)
                 OR (LOWER(VerifiedMimeType) = N'application/pdf'
                     AND RIGHT(LOWER(TrustedBlobObjectName), 4) = N'.pdf'
                     AND LEN(TrustedBlobObjectName) = 73)
             ))
        ),
    CONSTRAINT FundingPlatform_CK_ProjectAssets_Metadata
        CHECK ((DisplayName IS NULL OR NULLIF(LTRIM(RTRIM(DisplayName)), N'') IS NOT NULL)
               AND (AltText IS NULL OR NULLIF(LTRIM(RTRIM(AltText)), N'') IS NOT NULL)
               AND (IsCover = 0 OR
                    (Kind = 0 AND StorageStatus = 2 AND ScanStatus = 1
                     AND NULLIF(LTRIM(RTRIM(AltText)), N'') IS NOT NULL))
               AND SortOrder BETWEEN 0 AND 32767),
    CONSTRAINT FundingPlatform_CK_ProjectAssets_Deletion
        CHECK ((IsDeleted = 0 AND DeletedByUserId IS NULL AND DeletedAtUtc IS NULL)
               OR (IsDeleted = 1 AND IsCover = 0
                   AND DeletedByUserId IS NOT NULL AND DeletedAtUtc IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_ProjectAssets_Timestamps
        CHECK (UpdatedAtUtc >= CreatedAtUtc
               AND (ScanStartedAtUtc IS NULL OR ScanStartedAtUtc >= CreatedAtUtc)
               AND (ScanCompletedAtUtc IS NULL OR ScanStartedAtUtc IS NULL
                    OR ScanCompletedAtUtc >= ScanStartedAtUtc)
               AND (DeletedAtUtc IS NULL OR DeletedAtUtc >= CreatedAtUtc)),
    CONSTRAINT FundingPlatform_CK_ProjectAssets_ResultCode
        CHECK (ScanResultCode IS NULL
               OR (NULLIF(LTRIM(RTRIM(ScanResultCode)), N'') IS NOT NULL
                   AND CHARINDEX(CHAR(10), ScanResultCode) = 0
                   AND CHARINDEX(CHAR(13), ScanResultCode) = 0))
);

CREATE UNIQUE INDEX FundingPlatform_UQ_ProjectAssets_TrustedBlob
    ON dbo.FundingPlatform_ProjectAssets (TrustedBlobContainer, TrustedBlobObjectName)
    WHERE TrustedBlobContainer IS NOT NULL AND TrustedBlobObjectName IS NOT NULL;

CREATE UNIQUE INDEX FundingPlatform_UQ_ProjectAssets_ActiveCover
    ON dbo.FundingPlatform_ProjectAssets (ProjectId)
    WHERE IsCover = 1 AND IsDeleted = 0;

CREATE INDEX FundingPlatform_IX_ProjectAssets_ProjectOrder
    ON dbo.FundingPlatform_ProjectAssets (ProjectId, IsDeleted, SortOrder, Id)
    INCLUDE (PublicId, Kind, DisplayName, VerifiedMimeType, ContentLength,
             StorageStatus, ScanStatus, IsCover, UpdatedAtUtc);

CREATE INDEX FundingPlatform_IX_ProjectAssets_ScanQueue
    ON dbo.FundingPlatform_ProjectAssets (ScanStatus, StorageStatus, CreatedAtUtc, Id)
    INCLUDE (PublicId, ProjectId, ScanProvider, QuarantineBlobETag)
    WHERE IsDeleted = 0 AND ScanStatus = 0;

CREATE TABLE dbo.FundingPlatform_ProjectAssetUploadIntents
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_ProjectAssetUploadIntents_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    ProjectId BIGINT NOT NULL,
    Kind TINYINT NOT NULL,
    OriginalFileName NVARCHAR(260) NOT NULL,
    DeclaredMimeType NVARCHAR(100) NOT NULL,
    ExpectedContentLength BIGINT NOT NULL,
    MaxContentLength BIGINT NOT NULL,
    IncomingBlobContainer NVARCHAR(63) NOT NULL,
    IncomingBlobObjectName NVARCHAR(1024) NOT NULL,
    QuarantineBlobContainer NVARCHAR(63) NOT NULL,
    QuarantineBlobObjectName NVARCHAR(1024) NOT NULL,
    TrustedBlobContainer NVARCHAR(63) NOT NULL,
    TrustedBlobObjectName NVARCHAR(1024) NOT NULL,
    CompletionTokenHash BINARY(32) NOT NULL,
    Status TINYINT NOT NULL,
    ExpiresAtUtc DATETIME2(3) NOT NULL,
    FinalizeAttemptCount SMALLINT NOT NULL
        CONSTRAINT FundingPlatform_DF_ProjectAssetUploadIntents_Attempts DEFAULT (0),
    FinalizeLeaseId UNIQUEIDENTIFIER NULL,
    FinalizeLeaseUntilUtc DATETIME2(3) NULL,
    CompletedProjectAssetId BIGINT NULL,
    CompletedAtUtc DATETIME2(3) NULL,
    LastErrorCode NVARCHAR(100) NULL,
    UploadedByUserId BIGINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_ProjectAssetUploadIntents_CreatedAtUtc
        DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_ProjectAssetUploadIntents_UpdatedAtUtc
        DEFAULT (SYSUTCDATETIME()),
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_ProjectAssetUploadIntents PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_ProjectAssetUploadIntents_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_ProjectAssetUploadIntents_Token UNIQUE (CompletionTokenHash),
    CONSTRAINT FundingPlatform_UQ_ProjectAssetUploadIntents_IncomingBlob
        UNIQUE (IncomingBlobContainer, IncomingBlobObjectName),
    CONSTRAINT FundingPlatform_UQ_ProjectAssetUploadIntents_QuarantineBlob
        UNIQUE (QuarantineBlobContainer, QuarantineBlobObjectName),
    CONSTRAINT FundingPlatform_UQ_ProjectAssetUploadIntents_TrustedBlob
        UNIQUE (TrustedBlobContainer, TrustedBlobObjectName),
    CONSTRAINT FundingPlatform_FK_ProjectAssetUploadIntents_Projects
        FOREIGN KEY (ProjectId) REFERENCES dbo.FundingPlatform_Projects (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_ProjectAssetUploadIntents_User
        FOREIGN KEY (UploadedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_ProjectAssetUploadIntents_Asset
        FOREIGN KEY (CompletedProjectAssetId, ProjectId)
        REFERENCES dbo.FundingPlatform_ProjectAssets (Id, ProjectId),
    CONSTRAINT FundingPlatform_CK_ProjectAssetUploadIntents_Kind
        CHECK (Kind BETWEEN 0 AND 2),
    CONSTRAINT FundingPlatform_CK_ProjectAssetUploadIntents_File
        CHECK
        (
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
                OR (Kind = 1 AND LOWER(DeclaredMimeType) = N'application/pdf'
                    AND RIGHT(LOWER(OriginalFileName), 4) = N'.pdf')
            )
        ),
    CONSTRAINT FundingPlatform_CK_ProjectAssetUploadIntents_Length
        CHECK (ExpectedContentLength BETWEEN 1 AND MaxContentLength
               AND ((Kind = 0 AND MaxContentLength BETWEEN 1 AND 10485760)
                    OR (Kind = 1 AND MaxContentLength BETWEEN 1 AND 26214400))),
    CONSTRAINT FundingPlatform_CK_ProjectAssetUploadIntents_Containers
        CHECK
        (
            LEN(IncomingBlobContainer) BETWEEN 3 AND 63
            AND LEN(QuarantineBlobContainer) BETWEEN 3 AND 63
            AND LEN(TrustedBlobContainer) BETWEEN 3 AND 63
            AND IncomingBlobContainer = LOWER(IncomingBlobContainer)
            AND QuarantineBlobContainer = LOWER(QuarantineBlobContainer)
            AND TrustedBlobContainer = LOWER(TrustedBlobContainer)
            AND IncomingBlobContainer COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[^a-z0-9-]%'
            AND QuarantineBlobContainer COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[^a-z0-9-]%'
            AND TrustedBlobContainer COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[^a-z0-9-]%'
            AND LEFT(IncomingBlobContainer, 1) <> N'-'
            AND LEFT(QuarantineBlobContainer, 1) <> N'-'
            AND LEFT(TrustedBlobContainer, 1) <> N'-'
            AND RIGHT(IncomingBlobContainer, 1) <> N'-'
            AND RIGHT(QuarantineBlobContainer, 1) <> N'-'
            AND RIGHT(TrustedBlobContainer, 1) <> N'-'
            AND IncomingBlobContainer NOT LIKE N'%--%'
            AND QuarantineBlobContainer NOT LIKE N'%--%'
            AND TrustedBlobContainer NOT LIKE N'%--%'
            AND IncomingBlobContainer <> QuarantineBlobContainer
            AND IncomingBlobContainer <> TrustedBlobContainer
            AND QuarantineBlobContainer <> TrustedBlobContainer
            AND NOT (IncomingBlobContainer = QuarantineBlobContainer
                     AND IncomingBlobObjectName = QuarantineBlobObjectName)
            AND NOT (IncomingBlobContainer = TrustedBlobContainer
                     AND IncomingBlobObjectName = TrustedBlobObjectName)
            AND NOT (QuarantineBlobContainer = TrustedBlobContainer
                     AND QuarantineBlobObjectName = TrustedBlobObjectName)
        ),
    CONSTRAINT FundingPlatform_CK_ProjectAssetUploadIntents_OpaqueObjects
        CHECK
        (
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
                OR (LOWER(DeclaredMimeType) = N'application/pdf'
                    AND RIGHT(LOWER(IncomingBlobObjectName), 4) = N'.pdf'
                    AND RIGHT(LOWER(QuarantineBlobObjectName), 4) = N'.pdf'
                    AND RIGHT(LOWER(TrustedBlobObjectName), 4) = N'.pdf'
                    AND LEN(IncomingBlobObjectName) = 73
                    AND LEN(QuarantineBlobObjectName) = 73
                    AND LEN(TrustedBlobObjectName) = 73)
            )
        ),
    CONSTRAINT FundingPlatform_CK_ProjectAssetUploadIntents_Status
        CHECK (Status BETWEEN 0 AND 4 AND FinalizeAttemptCount BETWEEN 0 AND 100),
    CONSTRAINT FundingPlatform_CK_ProjectAssetUploadIntents_State
        CHECK ((Status = 0 AND FinalizeLeaseId IS NULL AND FinalizeLeaseUntilUtc IS NULL
                AND CompletedProjectAssetId IS NULL AND CompletedAtUtc IS NULL)
               OR (Status = 1 AND FinalizeLeaseId IS NOT NULL AND FinalizeLeaseUntilUtc IS NOT NULL
                   AND CompletedProjectAssetId IS NULL AND CompletedAtUtc IS NULL)
               OR (Status = 2 AND FinalizeLeaseId IS NULL AND FinalizeLeaseUntilUtc IS NULL
                   AND CompletedProjectAssetId IS NOT NULL AND CompletedAtUtc IS NOT NULL)
               OR (Status IN (3, 4) AND FinalizeLeaseId IS NULL
                   AND FinalizeLeaseUntilUtc IS NULL
                   AND CompletedProjectAssetId IS NULL AND CompletedAtUtc IS NULL)),
    CONSTRAINT FundingPlatform_CK_ProjectAssetUploadIntents_Timestamps
        CHECK (ExpiresAtUtc > CreatedAtUtc AND UpdatedAtUtc >= CreatedAtUtc
               AND (FinalizeLeaseUntilUtc IS NULL OR FinalizeLeaseUntilUtc > UpdatedAtUtc)
               AND (CompletedAtUtc IS NULL OR CompletedAtUtc >= CreatedAtUtc)),
    CONSTRAINT FundingPlatform_CK_ProjectAssetUploadIntents_Error
        CHECK (LastErrorCode IS NULL
               OR (NULLIF(LTRIM(RTRIM(LastErrorCode)), N'') IS NOT NULL
                   AND CHARINDEX(CHAR(10), LastErrorCode) = 0
                   AND CHARINDEX(CHAR(13), LastErrorCode) = 0))
);

CREATE UNIQUE INDEX FundingPlatform_UQ_ProjectAssetUploadIntents_CompletedAsset
    ON dbo.FundingPlatform_ProjectAssetUploadIntents (CompletedProjectAssetId)
    WHERE CompletedProjectAssetId IS NOT NULL;

CREATE INDEX FundingPlatform_IX_ProjectAssetUploadIntents_ProjectPending
    ON dbo.FundingPlatform_ProjectAssetUploadIntents (ProjectId, Status, ExpiresAtUtc, Id)
    INCLUDE (PublicId, UploadedByUserId, FinalizeLeaseUntilUtc)
    WHERE Status IN (0, 1);

CREATE TABLE dbo.FundingPlatform_ProjectAssetScanEvents
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    EventId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_ProjectAssetScanEvents_EventId DEFAULT (NEWSEQUENTIALID()),
    ProjectAssetId BIGINT NOT NULL,
    ScanProvider TINYINT NOT NULL,
    ProviderEventId NVARCHAR(200) NOT NULL,
    PayloadHash BINARY(32) NOT NULL,
    FromStatus TINYINT NOT NULL,
    ToStatus TINYINT NOT NULL,
    QuarantineBlobETag NVARCHAR(100) NOT NULL,
    ReportedContentHash BINARY(32) NOT NULL,
    ResultCode NVARCHAR(100) NOT NULL,
    ResultRowVersion BINARY(8) NOT NULL,
    OccurredAtUtc DATETIME2(3) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_ProjectAssetScanEvents_CreatedAtUtc
        DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_ProjectAssetScanEvents PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_ProjectAssetScanEvents_EventId UNIQUE (EventId),
    CONSTRAINT FundingPlatform_UQ_ProjectAssetScanEvents_ProviderEvent
        UNIQUE (ScanProvider, ProviderEventId),
    CONSTRAINT FundingPlatform_FK_ProjectAssetScanEvents_Asset
        FOREIGN KEY (ProjectAssetId) REFERENCES dbo.FundingPlatform_ProjectAssets (Id)
        ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_CK_ProjectAssetScanEvents_Status
        CHECK (ScanProvider BETWEEN 0 AND 1 AND FromStatus = 0 AND ToStatus BETWEEN 1 AND 4),
    CONSTRAINT FundingPlatform_CK_ProjectAssetScanEvents_Result
        CHECK (NULLIF(LTRIM(RTRIM(ProviderEventId)), N'') IS NOT NULL
               AND NULLIF(LTRIM(RTRIM(QuarantineBlobETag)), N'') IS NOT NULL
               AND NULLIF(LTRIM(RTRIM(ResultCode)), N'') IS NOT NULL
               AND CHARINDEX(CHAR(10), ProviderEventId) = 0
               AND CHARINDEX(CHAR(13), ProviderEventId) = 0
               AND LEFT(QuarantineBlobETag, 1) = N'"'
               AND RIGHT(QuarantineBlobETag, 1) = N'"'
               AND CHARINDEX(CHAR(10), QuarantineBlobETag) = 0
               AND CHARINDEX(CHAR(13), QuarantineBlobETag) = 0
               AND CHARINDEX(CHAR(10), ResultCode) = 0
               AND CHARINDEX(CHAR(13), ResultCode) = 0),
    CONSTRAINT FundingPlatform_CK_ProjectAssetScanEvents_Time
        CHECK (OccurredAtUtc >= DATEADD(DAY, -1, CreatedAtUtc)
               AND OccurredAtUtc <= DATEADD(MINUTE, 5, CreatedAtUtc))
);

CREATE INDEX FundingPlatform_IX_ProjectAssetScanEvents_AssetCreated
    ON dbo.FundingPlatform_ProjectAssetScanEvents (ProjectAssetId, CreatedAtUtc DESC, Id DESC)
    INCLUDE (EventId, ScanProvider, FromStatus, ToStatus, ResultCode, OccurredAtUtc);
GO

IF TYPE_ID(N'dbo.FundingPlatform_ProjectAssetOrderList') IS NULL
    EXEC sys.sp_executesql N'
        CREATE TYPE dbo.FundingPlatform_ProjectAssetOrderList AS TABLE
        (
            AssetPublicId UNIQUEIDENTIFIER NOT NULL,
            ExpectedRowVersion BINARY(8) NOT NULL,
            SortOrder SMALLINT NOT NULL,
            PRIMARY KEY (AssetPublicId),
            UNIQUE (SortOrder),
            CHECK (SortOrder BETWEEN 0 AND 32767)
        );';
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_ProjectMarketplaceReady()
RETURNS TABLE
AS
RETURN
(
    SELECT projects.Id AS ProjectId, projects.OrganizationId
    FROM dbo.FundingPlatform_Projects AS projects
    INNER JOIN dbo.FundingPlatform_ifn_OrganizationMarketplaceReady() AS readyOrganizations
        ON readyOrganizations.OrganizationId = projects.OrganizationId
    LEFT JOIN dbo.FundingPlatform_Currencies AS currencies
        ON currencies.Code = projects.Currency AND currencies.IsActive = 1
    WHERE projects.IsActive = 1
      AND projects.PublicationStatus = 2
      AND NULLIF(LTRIM(RTRIM(projects.Slug)), N'') IS NOT NULL
      AND NULLIF(LTRIM(RTRIM(projects.Title)), N'') IS NOT NULL
      AND NULLIF(LTRIM(RTRIM(projects.Summary)), N'') IS NOT NULL
      AND NULLIF(LTRIM(RTRIM(projects.Description)), N'') IS NOT NULL
      AND projects.BudgetTotal > 0
      AND currencies.Code IS NOT NULL
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectCountries
           WHERE ProjectId = projects.Id)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectCategories
           WHERE ProjectId = projects.Id)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectBeneficiaryTypes
           WHERE ProjectId = projects.Id)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectProjectTypes
           WHERE ProjectId = projects.Id)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ProjectCountries AS links
           LEFT JOIN dbo.FundingPlatform_Countries AS countries
               ON countries.Id = links.CountryId AND countries.IsActive = 1
           WHERE links.ProjectId = projects.Id AND countries.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ProjectRegions AS links
           LEFT JOIN dbo.FundingPlatform_Regions AS regions
               ON regions.Id = links.RegionId AND regions.IsActive = 1
           LEFT JOIN dbo.FundingPlatform_Countries AS countries
               ON countries.Id = regions.CountryId AND countries.IsActive = 1
           WHERE links.ProjectId = projects.Id
             AND (regions.Id IS NULL OR countries.Id IS NULL
                  OR NOT EXISTS
                     (SELECT 1
                      FROM dbo.FundingPlatform_ProjectCountries AS projectCountries
                      WHERE projectCountries.ProjectId = projects.Id
                        AND projectCountries.CountryId = regions.CountryId)))
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ProjectCategories AS links
           LEFT JOIN dbo.FundingPlatform_FundingCategories AS categories
               ON categories.Id = links.FundingCategoryId AND categories.IsActive = 1
           WHERE links.ProjectId = projects.Id AND categories.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ProjectBeneficiaryTypes AS links
           LEFT JOIN dbo.FundingPlatform_BeneficiaryTypes AS beneficiaryTypes
               ON beneficiaryTypes.Id = links.BeneficiaryTypeId
              AND beneficiaryTypes.IsActive = 1
           WHERE links.ProjectId = projects.Id AND beneficiaryTypes.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ProjectProjectTypes AS links
           LEFT JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
               ON projectTypes.Id = links.ProjectTypeId AND projectTypes.IsActive = 1
           WHERE links.ProjectId = projects.Id AND projectTypes.Id IS NULL)
      /* Assets are optional, but any active asset must remain safe. This also
         revokes late marketplace visibility if trust is ever lost. */
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ProjectAssets AS assets
           WHERE assets.ProjectId = projects.Id AND assets.IsDeleted = 0
             AND (assets.StorageStatus <> 2 OR assets.ScanStatus <> 1))
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ProjectAssets AS assets
           WHERE assets.ProjectId = projects.Id AND assets.IsDeleted = 0
             AND assets.IsCover = 1
             AND NULLIF(LTRIM(RTRIM(assets.AltText)), N'') IS NULL)
);
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Create
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER,
    @ExpectedProjectRowVersion BINARY(8),
    @Kind TINYINT,
    @OriginalFileName NVARCHAR(260),
    @DeclaredMimeType NVARCHAR(100),
    @ExpectedContentLength BIGINT,
    @MaxContentLength BIGINT,
    @IncomingBlobContainer NVARCHAR(63),
    @IncomingBlobObjectName NVARCHAR(1024),
    @QuarantineBlobContainer NVARCHAR(63),
    @QuarantineBlobObjectName NVARCHAR(1024),
    @TrustedBlobContainer NVARCHAR(63),
    @TrustedBlobObjectName NVARCHAR(1024),
    @CompletionTokenHash BINARY(32),
    @ExpiresAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @ProjectId BIGINT;
    DECLARE @ActorUserId BIGINT;
    DECLARE @PublicationStatus TINYINT;
    DECLARE @IntentId BIGINT;
    DECLARE @IntentPublicId UNIQUEIDENTIFIER;
    DECLARE @IntentRowVersion BINARY(8);
    DECLARE @CurrentProjectRowVersion BINARY(8);
    DECLARE @ResultProjectRowVersion BINARY(8);
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    SET @OriginalFileName = LTRIM(RTRIM(@OriginalFileName));
    SET @DeclaredMimeType = LOWER(LTRIM(RTRIM(@DeclaredMimeType)));
    SET @IncomingBlobContainer = LTRIM(RTRIM(@IncomingBlobContainer));
    SET @IncomingBlobObjectName = LTRIM(RTRIM(@IncomingBlobObjectName));
    SET @QuarantineBlobContainer = LTRIM(RTRIM(@QuarantineBlobContainer));
    SET @QuarantineBlobObjectName = LTRIM(RTRIM(@QuarantineBlobObjectName));
    SET @TrustedBlobContainer = LTRIM(RTRIM(@TrustedBlobContainer));
    SET @TrustedBlobObjectName = LTRIM(RTRIM(@TrustedBlobObjectName));

    IF @Kind IS NULL OR @Kind NOT IN (0, 1)
       OR NULLIF(@OriginalFileName, N'') IS NULL
       OR CHARINDEX(N'/', @OriginalFileName) > 0
       OR CHARINDEX(N'\', @OriginalFileName) > 0
       OR CHARINDEX(CHAR(10), @OriginalFileName) > 0
       OR CHARINDEX(CHAR(13), @OriginalFileName) > 0
       OR NOT
          (
              (@Kind = 0 AND
               ((@DeclaredMimeType = N'image/jpeg'
                 AND (RIGHT(LOWER(@OriginalFileName), 4) = N'.jpg'
                      OR RIGHT(LOWER(@OriginalFileName), 5) = N'.jpeg'))
                OR (@DeclaredMimeType = N'image/png'
                    AND RIGHT(LOWER(@OriginalFileName), 4) = N'.png')
                OR (@DeclaredMimeType = N'image/webp'
                    AND RIGHT(LOWER(@OriginalFileName), 5) = N'.webp')))
              OR (@Kind = 1 AND @DeclaredMimeType = N'application/pdf'
                  AND RIGHT(LOWER(@OriginalFileName), 4) = N'.pdf')
          )
       OR @ExpectedContentLength IS NULL OR @MaxContentLength IS NULL
       OR @ExpectedContentLength < 1
       OR @ExpectedContentLength > @MaxContentLength
       OR (@Kind = 0 AND (@MaxContentLength < 1 OR @MaxContentLength > 10485760))
       OR (@Kind = 1 AND (@MaxContentLength < 1 OR @MaxContentLength > 26214400))
       OR @CompletionTokenHash IS NULL
       OR @ExpectedProjectRowVersion IS NULL
       OR @ExpiresAtUtc IS NULL
       OR @ExpiresAtUtc <= @NowUtc
       OR @ExpiresAtUtc > DATEADD(MINUTE, 5, @NowUtc)
       OR NULLIF(@IncomingBlobContainer, N'') IS NULL
       OR NULLIF(@QuarantineBlobContainer, N'') IS NULL
       OR NULLIF(@TrustedBlobContainer, N'') IS NULL
       OR LEN(@IncomingBlobContainer) NOT BETWEEN 3 AND 63
       OR LEN(@QuarantineBlobContainer) NOT BETWEEN 3 AND 63
       OR LEN(@TrustedBlobContainer) NOT BETWEEN 3 AND 63
       OR @IncomingBlobContainer <> LOWER(@IncomingBlobContainer)
       OR @QuarantineBlobContainer <> LOWER(@QuarantineBlobContainer)
       OR @TrustedBlobContainer <> LOWER(@TrustedBlobContainer)
       OR @IncomingBlobContainer COLLATE Latin1_General_100_BIN2 LIKE N'%[^a-z0-9-]%'
       OR @QuarantineBlobContainer COLLATE Latin1_General_100_BIN2 LIKE N'%[^a-z0-9-]%'
       OR @TrustedBlobContainer COLLATE Latin1_General_100_BIN2 LIKE N'%[^a-z0-9-]%'
       OR LEFT(@IncomingBlobContainer, 1) = N'-'
       OR LEFT(@QuarantineBlobContainer, 1) = N'-'
       OR LEFT(@TrustedBlobContainer, 1) = N'-'
       OR RIGHT(@IncomingBlobContainer, 1) = N'-'
       OR RIGHT(@QuarantineBlobContainer, 1) = N'-'
       OR RIGHT(@TrustedBlobContainer, 1) = N'-'
       OR @IncomingBlobContainer LIKE N'%--%'
       OR @QuarantineBlobContainer LIKE N'%--%'
       OR @TrustedBlobContainer LIKE N'%--%'
       OR @IncomingBlobContainer = @QuarantineBlobContainer
       OR @IncomingBlobContainer = @TrustedBlobContainer
       OR @QuarantineBlobContainer = @TrustedBlobContainer
       OR (@IncomingBlobContainer = @QuarantineBlobContainer
           AND @IncomingBlobObjectName = @QuarantineBlobObjectName)
       OR (@IncomingBlobContainer = @TrustedBlobContainer
           AND @IncomingBlobObjectName = @TrustedBlobObjectName)
       OR (@QuarantineBlobContainer = @TrustedBlobContainer
           AND @QuarantineBlobObjectName = @TrustedBlobObjectName)
       OR TRY_CONVERT(UNIQUEIDENTIFIER, LEFT(@IncomingBlobObjectName, 36)) IS NULL
       OR TRY_CONVERT(UNIQUEIDENTIFIER, LEFT(@QuarantineBlobObjectName, 36)) IS NULL
       OR TRY_CONVERT(UNIQUEIDENTIFIER, LEFT(@TrustedBlobObjectName, 36)) IS NULL
       OR SUBSTRING(@IncomingBlobObjectName, 37, 1) <> N'/'
       OR SUBSTRING(@QuarantineBlobObjectName, 37, 1) <> N'/'
       OR SUBSTRING(@TrustedBlobObjectName, 37, 1) <> N'/'
       OR SUBSTRING(@IncomingBlobObjectName, 38, 32) <>
          LOWER(SUBSTRING(@IncomingBlobObjectName, 38, 32))
       OR SUBSTRING(@QuarantineBlobObjectName, 38, 32) <>
          LOWER(SUBSTRING(@QuarantineBlobObjectName, 38, 32))
       OR SUBSTRING(@TrustedBlobObjectName, 38, 32) <>
          LOWER(SUBSTRING(@TrustedBlobObjectName, 38, 32))
       OR SUBSTRING(@IncomingBlobObjectName, 38, 32)
          COLLATE Latin1_General_100_BIN2 LIKE N'%[^0-9a-f]%'
       OR SUBSTRING(@QuarantineBlobObjectName, 38, 32)
          COLLATE Latin1_General_100_BIN2 LIKE N'%[^0-9a-f]%'
       OR SUBSTRING(@TrustedBlobObjectName, 38, 32)
          COLLATE Latin1_General_100_BIN2 LIKE N'%[^0-9a-f]%'
       OR SUBSTRING(@IncomingBlobObjectName, 70, 1) <> N'.'
       OR SUBSTRING(@QuarantineBlobObjectName, 70, 1) <> N'.'
       OR SUBSTRING(@TrustedBlobObjectName, 70, 1) <> N'.'
       OR CHARINDEX(N'/', @IncomingBlobObjectName, 38) > 0
       OR CHARINDEX(N'/', @QuarantineBlobObjectName, 38) > 0
       OR CHARINDEX(N'/', @TrustedBlobObjectName, 38) > 0
       OR NOT
          (
              (@DeclaredMimeType = N'image/jpeg'
               AND ((RIGHT(LOWER(@IncomingBlobObjectName), 4) = N'.jpg'
                     AND RIGHT(LOWER(@QuarantineBlobObjectName), 4) = N'.jpg'
                     AND RIGHT(LOWER(@TrustedBlobObjectName), 4) = N'.jpg'
                     AND LEN(@IncomingBlobObjectName) = 73
                     AND LEN(@QuarantineBlobObjectName) = 73
                     AND LEN(@TrustedBlobObjectName) = 73)
                    OR (RIGHT(LOWER(@IncomingBlobObjectName), 5) = N'.jpeg'
                        AND RIGHT(LOWER(@QuarantineBlobObjectName), 5) = N'.jpeg'
                        AND RIGHT(LOWER(@TrustedBlobObjectName), 5) = N'.jpeg'
                        AND LEN(@IncomingBlobObjectName) = 74
                        AND LEN(@QuarantineBlobObjectName) = 74
                        AND LEN(@TrustedBlobObjectName) = 74)))
              OR (@DeclaredMimeType IN (N'image/png', N'application/pdf')
                  AND RIGHT(LOWER(@IncomingBlobObjectName), 4) =
                      CASE WHEN @DeclaredMimeType = N'image/png' THEN N'.png' ELSE N'.pdf' END
                  AND RIGHT(LOWER(@QuarantineBlobObjectName), 4) =
                      RIGHT(LOWER(@IncomingBlobObjectName), 4)
                  AND RIGHT(LOWER(@TrustedBlobObjectName), 4) =
                      RIGHT(LOWER(@IncomingBlobObjectName), 4)
                  AND LEN(@IncomingBlobObjectName) = 73
                  AND LEN(@QuarantineBlobObjectName) = 73
                  AND LEN(@TrustedBlobObjectName) = 73)
              OR (@DeclaredMimeType = N'image/webp'
                  AND RIGHT(LOWER(@IncomingBlobObjectName), 5) = N'.webp'
                  AND RIGHT(LOWER(@QuarantineBlobObjectName), 5) = N'.webp'
                  AND RIGHT(LOWER(@TrustedBlobObjectName), 5) = N'.webp'
                  AND LEN(@IncomingBlobObjectName) = 74
                  AND LEN(@QuarantineBlobObjectName) = 74
                  AND LEN(@TrustedBlobObjectName) = 74)
          )
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-asset' AS Code,
               CAST(NULL AS UNIQUEIDENTIFIER) AS IntentPublicId,
               CAST(NULL AS TINYINT) AS Status,
               CAST(NULL AS DATETIME2(3)) AS ExpiresAtUtc,
               CAST(NULL AS BINARY(8)) AS RowVersion,
               CAST(NULL AS BINARY(8)) AS ProjectRowVersion,
               CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_CreateProjectAssetIntent;

    BEGIN TRY
        SELECT @ProjectId = projects.Id,
               @ActorUserId = users.Id,
               @PublicationStatus = projects.PublicationStatus,
               @CurrentProjectRowVersion = projects.RowVersion
        FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id
           AND memberships.Role = 1 AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
            ON users.Id = memberships.UserId AND users.Status = 2
        INNER JOIN dbo.FundingPlatform_Projects AS projects WITH (UPDLOCK, HOLDLOCK)
            ON projects.OrganizationId = organizations.Id AND projects.IsActive = 1
        WHERE organizations.PublicId = @OrganizationPublicId
          AND organizations.IsActive = 1
          AND users.PublicId = @UserPublicId
          AND projects.PublicId = @ProjectPublicId;

        IF @ProjectId IS NULL
            THROW 55602, N'Active organization administrator membership is required.', 1;

        IF @PublicationStatus NOT IN (0, 3)
        BEGIN
            IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
            SELECT CAST(0 AS BIT) AS Succeeded, N'project-not-editable' AS Code,
                   CAST(NULL AS UNIQUEIDENTIFIER) AS IntentPublicId,
                   CAST(NULL AS TINYINT) AS Status,
                   CAST(NULL AS DATETIME2(3)) AS ExpiresAtUtc,
                   CAST(NULL AS BINARY(8)) AS RowVersion,
                   @CurrentProjectRowVersion AS ProjectRowVersion,
                   CAST(0 AS BIT) AS WasReplay;
            RETURN;
        END;

        IF @CurrentProjectRowVersion <> @ExpectedProjectRowVersion
        BEGIN
            IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
            SELECT CAST(0 AS BIT) AS Succeeded, N'project-etag-conflict' AS Code,
                   CAST(NULL AS UNIQUEIDENTIFIER) AS IntentPublicId,
                   CAST(NULL AS TINYINT) AS Status,
                   CAST(NULL AS DATETIME2(3)) AS ExpiresAtUtc,
                   CAST(NULL AS BINARY(8)) AS RowVersion,
                   @CurrentProjectRowVersion AS ProjectRowVersion,
                   CAST(0 AS BIT) AS WasReplay;
            RETURN;
        END;

        UPDATE dbo.FundingPlatform_ProjectAssetUploadIntents
        SET Status = 3,
            FinalizeLeaseId = NULL,
            FinalizeLeaseUntilUtc = NULL,
            LastErrorCode = N'expired',
            UpdatedAtUtc = @NowUtc
        WHERE ProjectId = @ProjectId
          AND Status IN (0, 1)
          AND ExpiresAtUtc <= @NowUtc;

        IF (SELECT COUNT_BIG(1)
            FROM dbo.FundingPlatform_ProjectAssetUploadIntents WITH (UPDLOCK, HOLDLOCK)
            WHERE ProjectId = @ProjectId AND Status IN (0, 1)) >= 5
        BEGIN
            IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
            SELECT CAST(0 AS BIT) AS Succeeded, N'pending-intent-limit' AS Code,
                   CAST(NULL AS UNIQUEIDENTIFIER) AS IntentPublicId,
                   CAST(NULL AS TINYINT) AS Status,
                   CAST(NULL AS DATETIME2(3)) AS ExpiresAtUtc,
                   CAST(NULL AS BINARY(8)) AS RowVersion,
                   @CurrentProjectRowVersion AS ProjectRowVersion,
                   CAST(0 AS BIT) AS WasReplay;
            RETURN;
        END;

        DECLARE @UpdatedProject TABLE (RowVersion BINARY(8) NOT NULL);
        UPDATE dbo.FundingPlatform_Projects
        SET UpdatedAtUtc = @NowUtc
        OUTPUT inserted.RowVersion INTO @UpdatedProject (RowVersion)
        WHERE Id = @ProjectId AND RowVersion = @ExpectedProjectRowVersion;
        SELECT @ResultProjectRowVersion = RowVersion FROM @UpdatedProject;

        IF @ResultProjectRowVersion IS NULL
        BEGIN
            IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
            SELECT CAST(0 AS BIT) AS Succeeded, N'project-etag-conflict' AS Code,
                   CAST(NULL AS UNIQUEIDENTIFIER) AS IntentPublicId,
                   CAST(NULL AS TINYINT) AS Status,
                   CAST(NULL AS DATETIME2(3)) AS ExpiresAtUtc,
                   CAST(NULL AS BINARY(8)) AS RowVersion,
                   @CurrentProjectRowVersion AS ProjectRowVersion,
                   CAST(0 AS BIT) AS WasReplay;
            RETURN;
        END;

        DECLARE @InsertedIntent TABLE
        (
            Id BIGINT NOT NULL,
            PublicId UNIQUEIDENTIFIER NOT NULL,
            RowVersion BINARY(8) NOT NULL
        );

        INSERT INTO dbo.FundingPlatform_ProjectAssetUploadIntents
            (ProjectId, Kind, OriginalFileName, DeclaredMimeType,
             ExpectedContentLength, MaxContentLength,
             IncomingBlobContainer, IncomingBlobObjectName,
             QuarantineBlobContainer, QuarantineBlobObjectName,
             TrustedBlobContainer, TrustedBlobObjectName,
             CompletionTokenHash, Status, ExpiresAtUtc, UploadedByUserId,
             CreatedAtUtc, UpdatedAtUtc)
        OUTPUT inserted.Id, inserted.PublicId, inserted.RowVersion
            INTO @InsertedIntent (Id, PublicId, RowVersion)
        VALUES
            (@ProjectId, @Kind, @OriginalFileName, @DeclaredMimeType,
             @ExpectedContentLength, @MaxContentLength,
             @IncomingBlobContainer, @IncomingBlobObjectName,
             @QuarantineBlobContainer, @QuarantineBlobObjectName,
             @TrustedBlobContainer, @TrustedBlobObjectName,
             @CompletionTokenHash, 0, @ExpiresAtUtc, @ActorUserId,
             @NowUtc, @NowUtc);

        SELECT @IntentId = Id, @IntentPublicId = PublicId,
               @IntentRowVersion = RowVersion
        FROM @InsertedIntent;

        INSERT INTO dbo.FundingPlatform_OutboxMessages
            (MessageType, AggregateType, AggregateId, PayloadJson,
             OccurredAtUtc, AvailableAtUtc)
        SELECT N'ProjectAssetUploadIntentCreated', N'ProjectAssetUploadIntent',
               CONVERT(NVARCHAR(100), @IntentPublicId),
               (SELECT @IntentPublicId AS intentPublicId,
                       @ProjectPublicId AS projectPublicId,
                       @Kind AS kind, CAST(0 AS TINYINT) AS status
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
               @NowUtc, @NowUtc;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        SELECT CAST(1 AS BIT) AS Succeeded, N'created' AS Code,
               @IntentPublicId AS IntentPublicId, CAST(0 AS TINYINT) AS Status,
               @ExpiresAtUtc AS ExpiresAtUtc, @IntentRowVersion AS RowVersion,
               @ResultProjectRowVersion AS ProjectRowVersion,
               CAST(0 AS BIT) AS WasReplay;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_CreateProjectAssetIntent;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Project_RequestPublication
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @ResultCode NVARCHAR(50) = NULL OUTPUT,
    @ResultCompleteness DECIMAL(5,2) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Issues TABLE
    (
        Code NVARCHAR(50) NOT NULL,
        FieldPath NVARCHAR(100) NOT NULL,
        Message NVARCHAR(300) NOT NULL
    );
    DECLARE @ProjectId BIGINT, @OrganizationId BIGINT, @ActorUserId BIGINT;
    DECLARE @OrganizationIsActive BIT;
    DECLARE @OrganizationProfileStatus TINYINT, @OrganizationCompleteness DECIMAL(5,2);
    DECLARE @CurrentStatus TINYINT, @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @SubmittedAtUtc DATETIME2(3), @PublishedAtUtc DATETIME2(3), @ReviewedAtUtc DATETIME2(3);
    DECLARE @ReviewedByUserPublicId UNIQUEIDENTIFIER, @RejectionReason NVARCHAR(1000);
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32);
    DECLARE @ExistingToStatus TINYINT, @ExistingResultRowVersion BINARY(8);
    DECLARE @ProjectVersion INT, @OrganizationProfileVersion INT;
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Completeness DECIMAL(5,2) = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_RequestPublication;

    BEGIN TRY
        SELECT @ProjectId = projects.Id,
               @OrganizationId = organizations.Id,
               @ActorUserId = users.Id,
               @OrganizationIsActive = organizations.IsActive,
               @OrganizationProfileStatus = organizations.ProfileStatus,
               @OrganizationCompleteness = organizations.ProfileCompleteness,
               @CurrentStatus = projects.PublicationStatus,
               @CurrentRowVersion = projects.RowVersion,
               @SubmittedAtUtc = projects.SubmittedAtUtc,
               @PublishedAtUtc = projects.PublishedAtUtc,
               @ReviewedAtUtc = projects.ReviewedAtUtc,
               @ReviewedByUserPublicId = reviewer.PublicId,
               @RejectionReason = projects.RejectionReason,
               @ProjectVersion = projects.ProjectVersion,
               @OrganizationProfileVersion = organizations.ProfileVersion
        FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id
           AND memberships.Role = 1 AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
            ON users.Id = memberships.UserId AND users.Status = 2
        INNER JOIN dbo.FundingPlatform_Projects AS projects WITH (UPDLOCK, HOLDLOCK)
            ON projects.OrganizationId = organizations.Id AND projects.IsActive = 1
        LEFT JOIN dbo.FundingPlatform_Users AS reviewer
            ON reviewer.Id = projects.ReviewedByUserId
        WHERE organizations.PublicId = @OrganizationPublicId
          AND users.PublicId = @UserPublicId
          AND projects.PublicId = @ProjectPublicId;

        IF @ProjectId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = events.ActionCode,
                   @ExistingRequestHash = events.RequestHash,
                   @ExistingToStatus = events.ToStatus,
                   @ExistingResultRowVersion = events.ResultRowVersion
            FROM dbo.FundingPlatform_ProjectPublicationEvents AS events WITH (UPDLOCK, HOLDLOCK)
            WHERE events.ProjectId = @ProjectId
              AND events.IdempotencyKeyHash = @IdempotencyKeyHash;

            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'RequestPublication' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1;
                    SET @WasReplay = 1;
                    SET @Code = N'publication-requested';
                    SET @Completeness = 100;
                    SET @CurrentStatus = @ExistingToStatus;
                    SET @ResultRowVersion = @ExistingResultRowVersion;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion
                SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus NOT IN (0, 3)
                SET @Code = N'invalid-transition';
            ELSE
            BEGIN
                IF @OrganizationIsActive <> 1
                   OR @OrganizationProfileStatus <> 2
                   OR @OrganizationCompleteness < 80
                    INSERT INTO @Issues VALUES
                        (N'organizationProfile', N'organizationProfile',
                         N'The organization profile must be complete and at least 80 percent.');
                IF NOT EXISTS
                (
                    SELECT 1 FROM dbo.FundingPlatform_Projects
                    WHERE Id = @ProjectId AND NULLIF(LTRIM(RTRIM(Title)), N'') IS NOT NULL
                ) INSERT INTO @Issues VALUES (N'title', N'title', N'Title is required.');
                IF NOT EXISTS
                (
                    SELECT 1 FROM dbo.FundingPlatform_Projects
                    WHERE Id = @ProjectId AND NULLIF(LTRIM(RTRIM(Summary)), N'') IS NOT NULL
                ) INSERT INTO @Issues VALUES (N'summary', N'summary', N'Summary is required.');
                IF NOT EXISTS
                (
                    SELECT 1 FROM dbo.FundingPlatform_Projects
                    WHERE Id = @ProjectId AND NULLIF(LTRIM(RTRIM(Description)), N'') IS NOT NULL
                ) INSERT INTO @Issues VALUES (N'description', N'description', N'Description is required.');
                IF NOT EXISTS
                (
                    SELECT 1 FROM dbo.FundingPlatform_Projects
                    WHERE Id = @ProjectId AND NULLIF(LTRIM(RTRIM(Slug)), N'') IS NOT NULL
                ) INSERT INTO @Issues VALUES (N'slug', N'slug', N'A public slug is required.');
                IF NOT EXISTS
                (
                    SELECT 1 FROM dbo.FundingPlatform_Projects
                    WHERE Id = @ProjectId AND BudgetTotal > 0 AND Currency IS NOT NULL
                ) INSERT INTO @Issues VALUES
                    (N'budget', N'budgetTotal', N'A positive budget and currency are required.');
                IF NOT EXISTS
                    (SELECT 1 FROM dbo.FundingPlatform_ProjectCountries WHERE ProjectId = @ProjectId)
                    INSERT INTO @Issues VALUES
                        (N'countries', N'countryIds', N'At least one country is required.');
                IF NOT EXISTS
                    (SELECT 1 FROM dbo.FundingPlatform_ProjectCategories WHERE ProjectId = @ProjectId)
                    INSERT INTO @Issues VALUES
                        (N'categories', N'categoryIds', N'At least one category is required.');
                IF NOT EXISTS
                    (SELECT 1 FROM dbo.FundingPlatform_ProjectBeneficiaryTypes WHERE ProjectId = @ProjectId)
                    INSERT INTO @Issues VALUES
                        (N'beneficiaries', N'beneficiaryTypeIds',
                         N'At least one beneficiary type is required.');
                IF NOT EXISTS
                    (SELECT 1 FROM dbo.FundingPlatform_ProjectProjectTypes WHERE ProjectId = @ProjectId)
                    INSERT INTO @Issues VALUES
                        (N'projectTypes', N'projectTypeIds', N'At least one project type is required.');

                IF EXISTS
                (
                    SELECT 1
                    FROM dbo.FundingPlatform_ProjectAssetUploadIntents AS intents
                        WITH (UPDLOCK, HOLDLOCK)
                    WHERE intents.ProjectId = @ProjectId
                      AND intents.Status IN (0, 1)
                      AND intents.ExpiresAtUtc > @NowUtc
                )
                    INSERT INTO @Issues VALUES
                        (N'assetsPending', N'assets',
                         N'All active project asset uploads must finish before review.');

                IF EXISTS
                (
                    SELECT 1
                    FROM dbo.FundingPlatform_ProjectAssets AS assets WITH (UPDLOCK, HOLDLOCK)
                    WHERE assets.ProjectId = @ProjectId AND assets.IsDeleted = 0
                      AND (assets.StorageStatus <> 2 OR assets.ScanStatus <> 1)
                )
                    INSERT INTO @Issues VALUES
                        (N'assetsNotTrusted', N'assets',
                         N'All active project assets must be clean and trusted before review.');

                IF EXISTS
                (
                    SELECT 1
                    FROM dbo.FundingPlatform_ProjectAssets AS assets WITH (UPDLOCK, HOLDLOCK)
                    WHERE assets.ProjectId = @ProjectId AND assets.IsDeleted = 0
                      AND assets.IsCover = 1
                      AND NULLIF(LTRIM(RTRIM(assets.AltText)), N'') IS NULL
                )
                    INSERT INTO @Issues VALUES
                        (N'coverAltText', N'assets.cover.altText',
                         N'Cover image alternative text is required.');

                DECLARE @IssueCount INT = (SELECT COUNT(1) FROM @Issues);
                SET @Completeness = CONVERT(DECIMAL(5,2),
                    CASE WHEN @IssueCount >= 10 THEN 0 ELSE 100 - (@IssueCount * 10) END);

                IF EXISTS (SELECT 1 FROM @Issues)
                    SET @Code = N'project-not-ready';
                ELSE
                BEGIN
                    DECLARE @Updated TABLE (RowVersion BINARY(8) NOT NULL);
                    UPDATE dbo.FundingPlatform_Projects
                    SET PublicationStatus = 1,
                        SubmittedAtUtc = @NowUtc,
                        RejectionReason = NULL,
                        UpdatedAtUtc = @NowUtc
                    OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
                    WHERE Id = @ProjectId AND RowVersion = @ExpectedRowVersion;

                    SELECT @ResultRowVersion = RowVersion FROM @Updated;
                    IF @ResultRowVersion IS NULL
                        SET @Code = N'etag-conflict';
                    ELSE
                    BEGIN
                        INSERT INTO dbo.FundingPlatform_ProjectPublicationEvents
                            (EventId, ProjectId, ProjectVersion, OrganizationProfileVersion,
                             FromStatus, ToStatus, ActionCode, ActorUserId, Reason,
                             IdempotencyKeyHash, RequestHash, ResultRowVersion, CreatedAtUtc)
                        VALUES
                            (@EventId, @ProjectId, @ProjectVersion, @OrganizationProfileVersion,
                             @CurrentStatus, 1, N'RequestPublication', @ActorUserId,
                             NULL, @IdempotencyKeyHash, @RequestHash, @ResultRowVersion, @NowUtc);

                        INSERT INTO dbo.FundingPlatform_OutboxMessages
                            (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                             OccurredAtUtc, AvailableAtUtc)
                        SELECT @EventId, N'ProjectPublicationRequested', N'Project',
                               CONVERT(NVARCHAR(100), @ProjectId),
                               (SELECT @EventId AS eventId, @ProjectId AS projectId,
                                       @ProjectPublicId AS projectPublicId,
                                       @CurrentStatus AS fromStatus, 1 AS toStatus,
                                       @ProjectVersion AS projectVersion,
                                       @OrganizationProfileVersion AS organizationProfileVersion
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                               @NowUtc, @NowUtc;

                        SET @Succeeded = 1;
                        SET @Code = N'publication-requested';
                        SET @CurrentStatus = 1;
                        SET @SubmittedAtUtc = @NowUtc;
                        SET @RejectionReason = NULL;
                    END;
                END;
            END;
        END;

        IF @ResultRowVersion IS NULL SET @ResultRowVersion = @CurrentRowVersion;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_RequestPublication;
        THROW;
    END CATCH;

    SET @ResultCode = @Code;
    SET @ResultCompleteness = @Completeness;
    SELECT @Succeeded AS Succeeded, @Code AS Code, @Completeness AS Completeness,
           @ProjectPublicId AS ProjectPublicId, @CurrentStatus AS PublicationStatus,
           @SubmittedAtUtc AS SubmittedAtUtc, @PublishedAtUtc AS PublishedAtUtc,
           @ReviewedAtUtc AS ReviewedAtUtc,
           @ReviewedByUserPublicId AS ReviewedByUserPublicId,
           @RejectionReason AS RejectionReason, @ResultRowVersion AS RowVersion,
           @WasReplay AS WasReplay;
    SELECT Code, FieldPath, Message FROM @Issues ORDER BY FieldPath, Code;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Project_AdminReview
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @Decision TINYINT,
    @RejectionReason NVARCHAR(1000) = NULL,
    @ExpectedRowVersion BINARY(8),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ProjectId BIGINT, @AdminUserId BIGINT, @CurrentStatus TINYINT;
    DECLARE @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @SubmittedAtUtc DATETIME2(3), @PublishedAtUtc DATETIME2(3), @ReviewedAtUtc DATETIME2(3);
    DECLARE @ReviewedByUserPublicId UNIQUEIDENTIFIER, @CurrentRejectionReason NVARCHAR(1000);
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32);
    DECLARE @ExistingToStatus TINYINT, @ExistingResultRowVersion BINARY(8);
    DECLARE @ProjectVersion INT, @OrganizationProfileVersion INT;
    DECLARE @OrganizationIsActive BIT, @OrganizationProfileStatus TINYINT;
    DECLARE @OrganizationCompleteness DECIMAL(5,2);
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'forbidden';
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_AdminReviewProject;

    BEGIN TRY
        SELECT @AdminUserId = users.Id
        FROM dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
        WHERE users.PublicId = @AdminUserPublicId AND users.Status = 2
          AND EXISTS
          (
              SELECT 1
              FROM dbo.FundingPlatform_UserRoles AS userRoles WITH (UPDLOCK, HOLDLOCK)
              INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
              WHERE userRoles.UserId = users.Id
                AND roles.NormalizedName IN (N'ADMIN', N'SUPERADMIN')
          );

        IF @AdminUserId IS NOT NULL
        BEGIN
            SELECT @ProjectId = projects.Id,
                   @CurrentStatus = projects.PublicationStatus,
                   @CurrentRowVersion = projects.RowVersion,
                   @SubmittedAtUtc = projects.SubmittedAtUtc,
                   @PublishedAtUtc = projects.PublishedAtUtc,
                   @ReviewedAtUtc = projects.ReviewedAtUtc,
                   @ReviewedByUserPublicId = reviewer.PublicId,
                   @CurrentRejectionReason = projects.RejectionReason,
                   @ProjectVersion = projects.ProjectVersion,
                   @OrganizationIsActive = organizations.IsActive,
                   @OrganizationProfileStatus = organizations.ProfileStatus,
                   @OrganizationCompleteness = organizations.ProfileCompleteness,
                   @OrganizationProfileVersion = organizations.ProfileVersion
            FROM dbo.FundingPlatform_Projects AS projects WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
                ON organizations.Id = projects.OrganizationId
            LEFT JOIN dbo.FundingPlatform_Users AS reviewer
                ON reviewer.Id = projects.ReviewedByUserId
            WHERE projects.PublicId = @ProjectPublicId AND projects.IsActive = 1;

            IF @ProjectId IS NULL SET @Code = N'not-found';
            ELSE
            BEGIN
                SELECT @ExistingAction = events.ActionCode,
                       @ExistingRequestHash = events.RequestHash,
                       @ExistingToStatus = events.ToStatus,
                       @ExistingResultRowVersion = events.ResultRowVersion
                FROM dbo.FundingPlatform_ProjectPublicationEvents AS events WITH (UPDLOCK, HOLDLOCK)
                WHERE events.ProjectId = @ProjectId
                  AND events.IdempotencyKeyHash = @IdempotencyKeyHash;

                IF @ExistingAction IS NOT NULL
                BEGIN
                    IF @ExistingAction = N'AdminReview' AND @ExistingRequestHash = @RequestHash
                    BEGIN
                        SET @Succeeded = 1;
                        SET @WasReplay = 1;
                        SET @Code = CASE WHEN @Decision = 2 THEN N'published' ELSE N'rejected' END;
                        SET @CurrentStatus = @ExistingToStatus;
                        SET @ResultRowVersion = @ExistingResultRowVersion;
                    END
                    ELSE SET @Code = N'idempotency-conflict';
                END
                ELSE IF @Decision IS NULL OR @Decision NOT IN (2, 3)
                    SET @Code = N'invalid-decision';
                ELSE IF @Decision = 3 AND NULLIF(LTRIM(RTRIM(@RejectionReason)), N'') IS NULL
                    SET @Code = N'rejection-reason-required';
                ELSE IF @Decision = 2 AND NULLIF(LTRIM(RTRIM(@RejectionReason)), N'') IS NOT NULL
                    SET @Code = N'rejection-reason-not-allowed';
                ELSE IF @Decision = 2 AND
                        (@OrganizationIsActive <> 1 OR @OrganizationProfileStatus <> 2
                         OR @OrganizationCompleteness < 80)
                    SET @Code = N'organization-not-ready';
                ELSE IF @Decision = 2 AND
                        (
                            EXISTS
                            (
                                SELECT 1
                                FROM dbo.FundingPlatform_ProjectAssetUploadIntents AS intents
                                    WITH (UPDLOCK, HOLDLOCK)
                                WHERE intents.ProjectId = @ProjectId
                                  AND intents.Status IN (0, 1)
                                  AND intents.ExpiresAtUtc > @NowUtc
                            )
                            OR EXISTS
                            (
                                SELECT 1
                                FROM dbo.FundingPlatform_ProjectAssets AS assets
                                    WITH (UPDLOCK, HOLDLOCK)
                                WHERE assets.ProjectId = @ProjectId AND assets.IsDeleted = 0
                                  AND (assets.StorageStatus <> 2 OR assets.ScanStatus <> 1)
                            )
                            OR EXISTS
                            (
                                SELECT 1
                                FROM dbo.FundingPlatform_ProjectAssets AS assets
                                    WITH (UPDLOCK, HOLDLOCK)
                                WHERE assets.ProjectId = @ProjectId AND assets.IsDeleted = 0
                                  AND assets.IsCover = 1
                                  AND NULLIF(LTRIM(RTRIM(assets.AltText)), N'') IS NULL
                            )
                        )
                    SET @Code = N'project-assets-not-ready';
                ELSE IF @CurrentRowVersion <> @ExpectedRowVersion
                    SET @Code = N'etag-conflict';
                ELSE IF @CurrentStatus <> 1
                    SET @Code = N'invalid-transition';
                ELSE
                BEGIN
                    DECLARE @Updated TABLE (RowVersion BINARY(8) NOT NULL);
                    UPDATE dbo.FundingPlatform_Projects
                    SET PublicationStatus = @Decision,
                        PublishedAtUtc = CASE WHEN @Decision = 2 THEN @NowUtc ELSE PublishedAtUtc END,
                        ReviewedAtUtc = @NowUtc,
                        ReviewedByUserId = @AdminUserId,
                        RejectionReason = CASE WHEN @Decision = 3
                                               THEN LTRIM(RTRIM(@RejectionReason)) ELSE NULL END,
                        UpdatedAtUtc = @NowUtc
                    OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
                    WHERE Id = @ProjectId AND RowVersion = @ExpectedRowVersion;
                    SELECT @ResultRowVersion = RowVersion FROM @Updated;

                    IF @ResultRowVersion IS NULL SET @Code = N'etag-conflict';
                    ELSE
                    BEGIN
                        INSERT INTO dbo.FundingPlatform_ProjectPublicationEvents
                            (EventId, ProjectId, ProjectVersion, OrganizationProfileVersion,
                             FromStatus, ToStatus, ActionCode, ActorUserId, Reason,
                             IdempotencyKeyHash, RequestHash, ResultRowVersion, CreatedAtUtc)
                        VALUES
                            (@EventId, @ProjectId, @ProjectVersion, @OrganizationProfileVersion,
                             @CurrentStatus, @Decision, N'AdminReview', @AdminUserId,
                             CASE WHEN @Decision = 3 THEN LTRIM(RTRIM(@RejectionReason)) ELSE NULL END,
                             @IdempotencyKeyHash, @RequestHash, @ResultRowVersion, @NowUtc);

                        INSERT INTO dbo.FundingPlatform_OutboxMessages
                            (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                             OccurredAtUtc, AvailableAtUtc)
                        SELECT @EventId,
                               CASE WHEN @Decision = 2
                                    THEN N'ProjectPublished' ELSE N'ProjectRejected' END,
                               N'Project', CONVERT(NVARCHAR(100), @ProjectId),
                               (SELECT @EventId AS eventId, @ProjectId AS projectId,
                                       @ProjectPublicId AS projectPublicId,
                                       @CurrentStatus AS fromStatus, @Decision AS toStatus,
                                       @ProjectVersion AS projectVersion,
                                       @OrganizationProfileVersion AS organizationProfileVersion
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                               @NowUtc, @NowUtc;

                        SET @Succeeded = 1;
                        SET @Code = CASE WHEN @Decision = 2
                                         THEN N'published' ELSE N'rejected' END;
                        SET @CurrentStatus = @Decision;
                        SET @ReviewedAtUtc = @NowUtc;
                        SET @ReviewedByUserPublicId = @AdminUserPublicId;
                        SET @CurrentRejectionReason = CASE WHEN @Decision = 3
                            THEN LTRIM(RTRIM(@RejectionReason)) ELSE NULL END;
                        IF @Decision = 2 SET @PublishedAtUtc = @NowUtc;
                    END;
                END;
            END;
        END;

        IF @ResultRowVersion IS NULL SET @ResultRowVersion = @CurrentRowVersion;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_AdminReviewProject;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           CAST(NULL AS DECIMAL(5,2)) AS Completeness,
           @ProjectPublicId AS ProjectPublicId, @CurrentStatus AS PublicationStatus,
           @SubmittedAtUtc AS SubmittedAtUtc, @PublishedAtUtc AS PublishedAtUtc,
           @ReviewedAtUtc AS ReviewedAtUtc,
           @ReviewedByUserPublicId AS ReviewedByUserPublicId,
           @CurrentRejectionReason AS RejectionReason,
           @ResultRowVersion AS RowVersion, @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
    @AssetPublicId UNIQUEIDENTIFIER,
    @ScanProvider TINYINT,
    @ProviderEventId NVARCHAR(200),
    @PayloadHash BINARY(32),
    @QuarantineBlobETag NVARCHAR(100),
    @ReportedContentHash BINARY(32),
    @ToStatus TINYINT,
    @ResultCode NVARCHAR(100),
    @OccurredAtUtc DATETIME2(3),
    @TrustedBlobContainer NVARCHAR(63) = NULL,
    @TrustedBlobObjectName NVARCHAR(1024) = NULL,
    @TrustedBlobETag NVARCHAR(100) = NULL,
    @TrustedBlobVersionId NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @AssetId BIGINT;
    DECLARE @ProjectId BIGINT;
    DECLARE @StoredProvider TINYINT;
    DECLARE @StoredStorageStatus TINYINT;
    DECLARE @StoredScanStatus TINYINT;
    DECLARE @StoredQuarantineETag NVARCHAR(100);
    DECLARE @StoredContentHash BINARY(32);
    DECLARE @IsDeleted BIT;
    DECLARE @AssetRowVersion BINARY(8);
    DECLARE @ProjectRowVersion BINARY(8);
    DECLARE @ExpectedTrustedContainer NVARCHAR(63);
    DECLARE @ExpectedTrustedObjectName NVARCHAR(1024);
    DECLARE @ExistingAssetId BIGINT;
    DECLARE @ExistingPayloadHash BINARY(32);
    DECLARE @ExistingToStatus TINYINT;
    DECLARE @ExistingQuarantineETag NVARCHAR(100);
    DECLARE @ExistingReportedHash BINARY(32);
    DECLARE @ExistingResultCode NVARCHAR(100);
    DECLARE @ExistingResultRowVersion BINARY(8);
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @Succeeded BIT = 0;
    DECLARE @WasReplay BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    SET @ProviderEventId = LTRIM(RTRIM(@ProviderEventId));
    SET @QuarantineBlobETag = LTRIM(RTRIM(@QuarantineBlobETag));
    SET @ResultCode = LTRIM(RTRIM(@ResultCode));
    SET @TrustedBlobContainer = NULLIF(LTRIM(RTRIM(@TrustedBlobContainer)), N'');
    SET @TrustedBlobObjectName = NULLIF(LTRIM(RTRIM(@TrustedBlobObjectName)), N'');
    SET @TrustedBlobETag = NULLIF(LTRIM(RTRIM(@TrustedBlobETag)), N'');
    SET @TrustedBlobVersionId = NULLIF(LTRIM(RTRIM(@TrustedBlobVersionId)), N'');

    IF @ScanProvider IS NULL OR @ScanProvider NOT BETWEEN 0 AND 1
       OR NULLIF(@ProviderEventId, N'') IS NULL OR LEN(@ProviderEventId) > 200
       OR CHARINDEX(CHAR(10), @ProviderEventId) > 0
       OR CHARINDEX(CHAR(13), @ProviderEventId) > 0
       OR @PayloadHash IS NULL OR @ReportedContentHash IS NULL
       OR LEN(COALESCE(@QuarantineBlobETag, N'')) NOT BETWEEN 3 AND 100
       OR LEFT(@QuarantineBlobETag, 1) <> N'"'
       OR RIGHT(@QuarantineBlobETag, 1) <> N'"'
       OR CHARINDEX(CHAR(10), @QuarantineBlobETag) > 0
       OR CHARINDEX(CHAR(13), @QuarantineBlobETag) > 0
       OR @ToStatus IS NULL OR @ToStatus NOT BETWEEN 1 AND 4
       OR NULLIF(@ResultCode, N'') IS NULL OR LEN(@ResultCode) > 100
       OR CHARINDEX(CHAR(10), @ResultCode) > 0
       OR CHARINDEX(CHAR(13), @ResultCode) > 0
       OR @OccurredAtUtc IS NULL
       OR @OccurredAtUtc < DATEADD(DAY, -1, @NowUtc)
       OR @OccurredAtUtc > DATEADD(MINUTE, 5, @NowUtc)
       OR (@ToStatus = 1 AND
           (@TrustedBlobContainer IS NULL OR @TrustedBlobObjectName IS NULL
            OR LEN(COALESCE(@TrustedBlobETag, N'')) NOT BETWEEN 3 AND 100
            OR LEFT(@TrustedBlobETag, 1) <> N'"'
            OR RIGHT(@TrustedBlobETag, 1) <> N'"'
            OR CHARINDEX(CHAR(10), @TrustedBlobETag) > 0
            OR CHARINDEX(CHAR(13), @TrustedBlobETag) > 0))
       OR (@ToStatus <> 1 AND
           (@TrustedBlobContainer IS NOT NULL OR @TrustedBlobObjectName IS NOT NULL
            OR @TrustedBlobETag IS NOT NULL OR @TrustedBlobVersionId IS NOT NULL))
       OR LEN(COALESCE(@TrustedBlobVersionId, N'')) > 200
       OR CHARINDEX(CHAR(10), COALESCE(@TrustedBlobVersionId, N'')) > 0
       OR CHARINDEX(CHAR(13), COALESCE(@TrustedBlobVersionId, N'')) > 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-scan-result' AS Code,
               @AssetPublicId AS AssetPublicId,
               CAST(NULL AS TINYINT) AS StorageStatus,
               CAST(NULL AS TINYINT) AS ScanStatus,
               CAST(NULL AS TINYINT) AS ScanProvider,
               CAST(NULL AS BINARY(8)) AS AssetRowVersion,
               CAST(NULL AS BINARY(8)) AS ProjectRowVersion,
               CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_ApplyProjectAssetScan;

    BEGIN TRY
        SELECT @ExistingAssetId = events.ProjectAssetId,
               @ExistingPayloadHash = events.PayloadHash,
               @ExistingToStatus = events.ToStatus,
               @ExistingQuarantineETag = events.QuarantineBlobETag,
               @ExistingReportedHash = events.ReportedContentHash,
               @ExistingResultCode = events.ResultCode,
               @ExistingResultRowVersion = events.ResultRowVersion
        FROM dbo.FundingPlatform_ProjectAssetScanEvents AS events WITH (UPDLOCK, HOLDLOCK)
        WHERE events.ScanProvider = @ScanProvider
          AND events.ProviderEventId = @ProviderEventId;

        IF @ExistingAssetId IS NOT NULL
        BEGIN
            SELECT @AssetId = assets.Id,
                   @ProjectId = assets.ProjectId,
                   @StoredProvider = assets.ScanProvider,
                   @StoredStorageStatus = assets.StorageStatus,
                   @StoredScanStatus = assets.ScanStatus,
                   @StoredQuarantineETag = assets.QuarantineBlobETag,
                   @StoredContentHash = assets.ContentHash,
                   @IsDeleted = assets.IsDeleted,
                   @AssetRowVersion = assets.RowVersion
            FROM dbo.FundingPlatform_ProjectAssets AS assets WITH (UPDLOCK, HOLDLOCK)
            WHERE assets.Id = @ExistingAssetId AND assets.PublicId = @AssetPublicId;

            IF @AssetId IS NOT NULL
               AND @ExistingPayloadHash = @PayloadHash
               AND @ExistingToStatus = @ToStatus
               AND @ExistingQuarantineETag = @QuarantineBlobETag
               AND @ExistingReportedHash = @ReportedContentHash
               AND @ExistingResultCode = @ResultCode
               AND @StoredScanStatus = @ToStatus
               AND ((@ToStatus = 1
                     AND @StoredStorageStatus = 2
                     AND EXISTS
                         (SELECT 1 FROM dbo.FundingPlatform_ProjectAssets
                          WHERE Id = @AssetId
                            AND TrustedBlobContainer = @TrustedBlobContainer
                            AND TrustedBlobObjectName = @TrustedBlobObjectName
                            AND TrustedBlobETag = @TrustedBlobETag
                            AND ((TrustedBlobVersionId IS NULL AND @TrustedBlobVersionId IS NULL)
                                 OR TrustedBlobVersionId = @TrustedBlobVersionId)))
                    OR (@ToStatus <> 1 AND @StoredStorageStatus = 3))
            BEGIN
                SET @Succeeded = 1;
                SET @Code = N'applied';
                SET @WasReplay = 1;
                SET @AssetRowVersion = @ExistingResultRowVersion;
                SELECT @ProjectRowVersion = RowVersion
                FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId;
            END
            ELSE SET @Code = N'provider-event-conflict';
        END
        ELSE
        BEGIN
            SELECT @AssetId = assets.Id,
                   @ProjectId = assets.ProjectId,
                   @StoredProvider = assets.ScanProvider,
                   @StoredStorageStatus = assets.StorageStatus,
                   @StoredScanStatus = assets.ScanStatus,
                   @StoredQuarantineETag = assets.QuarantineBlobETag,
                   @StoredContentHash = assets.ContentHash,
                   @IsDeleted = assets.IsDeleted,
                   @AssetRowVersion = assets.RowVersion,
                   @ExpectedTrustedContainer = intents.TrustedBlobContainer,
                   @ExpectedTrustedObjectName = intents.TrustedBlobObjectName
            FROM dbo.FundingPlatform_ProjectAssets AS assets WITH (UPDLOCK, HOLDLOCK)
            LEFT JOIN dbo.FundingPlatform_ProjectAssetUploadIntents AS intents WITH (HOLDLOCK)
                ON intents.CompletedProjectAssetId = assets.Id AND intents.Status = 2
            WHERE assets.PublicId = @AssetPublicId;

            IF @AssetId IS NULL
                SET @Code = N'not-found';
            ELSE IF @IsDeleted = 1
                SET @Code = N'asset-deleted';
            ELSE IF @StoredProvider <> @ScanProvider
                SET @Code = N'provider-mismatch';
            ELSE IF @StoredStorageStatus <> 1 OR @StoredScanStatus <> 0
                SET @Code = N'invalid-state';
            ELSE IF @StoredQuarantineETag <> @QuarantineBlobETag
                SET @Code = N'etag-mismatch';
            ELSE IF @StoredContentHash <> @ReportedContentHash
                SET @Code = N'hash-mismatch';
            ELSE IF @ToStatus = 1 AND
                    (@TrustedBlobContainer <> @ExpectedTrustedContainer
                     OR @TrustedBlobObjectName <> @ExpectedTrustedObjectName)
                SET @Code = N'trusted-destination-mismatch';
            ELSE
            BEGIN
                DECLARE @UpdatedAsset TABLE (RowVersion BINARY(8) NOT NULL);
                UPDATE dbo.FundingPlatform_ProjectAssets
                SET StorageStatus = CASE WHEN @ToStatus = 1 THEN 2 ELSE 3 END,
                    ScanStatus = @ToStatus,
                    ScanResultCode = @ResultCode,
                    ScanStartedAtUtc = COALESCE(ScanStartedAtUtc, @NowUtc),
                    ScanCompletedAtUtc = @NowUtc,
                    TrustedBlobContainer = CASE WHEN @ToStatus = 1
                                                THEN @TrustedBlobContainer END,
                    TrustedBlobObjectName = CASE WHEN @ToStatus = 1
                                                 THEN @TrustedBlobObjectName END,
                    TrustedBlobETag = CASE WHEN @ToStatus = 1
                                           THEN @TrustedBlobETag END,
                    TrustedBlobVersionId = CASE WHEN @ToStatus = 1
                                                THEN @TrustedBlobVersionId END,
                    UpdatedAtUtc = @NowUtc
                OUTPUT inserted.RowVersion INTO @UpdatedAsset (RowVersion)
                WHERE Id = @AssetId AND StorageStatus = 1 AND ScanStatus = 0;
                SELECT @AssetRowVersion = RowVersion FROM @UpdatedAsset;

                IF @AssetRowVersion IS NULL
                    THROW 55605, N'Project asset changed during scan result application.', 1;

                DECLARE @UpdatedProject TABLE (RowVersion BINARY(8) NOT NULL);
                UPDATE dbo.FundingPlatform_Projects
                SET UpdatedAtUtc = @NowUtc
                OUTPUT inserted.RowVersion INTO @UpdatedProject (RowVersion)
                WHERE Id = @ProjectId;
                SELECT @ProjectRowVersion = RowVersion FROM @UpdatedProject;

                INSERT INTO dbo.FundingPlatform_ProjectAssetScanEvents
                    (EventId, ProjectAssetId, ScanProvider, ProviderEventId,
                     PayloadHash, FromStatus, ToStatus, QuarantineBlobETag,
                     ReportedContentHash, ResultCode, ResultRowVersion,
                     OccurredAtUtc, CreatedAtUtc)
                VALUES
                    (@EventId, @AssetId, @ScanProvider, @ProviderEventId,
                     @PayloadHash, 0, @ToStatus, @QuarantineBlobETag,
                     @ReportedContentHash, @ResultCode, @AssetRowVersion,
                     @OccurredAtUtc, @NowUtc);

                INSERT INTO dbo.FundingPlatform_OutboxMessages
                    (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                     OccurredAtUtc, AvailableAtUtc)
                SELECT @EventId, N'ProjectAssetScanCompleted', N'ProjectAsset',
                       CONVERT(NVARCHAR(100), @AssetPublicId),
                       (SELECT @EventId AS eventId,
                               @AssetPublicId AS assetPublicId,
                               @ScanProvider AS scanProvider,
                               @ToStatus AS scanStatus,
                               CASE WHEN @ToStatus = 1 THEN 2 ELSE 3 END AS storageStatus,
                               @ResultCode AS resultCode
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                       @NowUtc, @NowUtc;

                SET @StoredStorageStatus = CASE WHEN @ToStatus = 1 THEN 2 ELSE 3 END;
                SET @StoredScanStatus = @ToStatus;
                SET @Succeeded = 1;
                SET @Code = N'applied';
            END;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        SELECT @Succeeded AS Succeeded, @Code AS Code,
               @AssetPublicId AS AssetPublicId,
               @StoredStorageStatus AS StorageStatus,
               @StoredScanStatus AS ScanStatus,
               @StoredProvider AS ScanProvider,
               @AssetRowVersion AS AssetRowVersion,
               @ProjectRowVersion AS ProjectRowVersion,
               @WasReplay AS WasReplay;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ApplyProjectAssetScan;
        THROW;
    END CATCH;
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
    DECLARE @ContentHash BINARY(32);
    DECLARE @VerifiedMimeType NVARCHAR(100);
    DECLARE @ContentLength BIGINT;
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
           @ContentHash = ContentHash,
           @VerifiedMimeType = VerifiedMimeType,
           @ContentLength = ContentLength,
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
               CAST(NULL AS BINARY(32)) AS ContentHash,
               CAST(NULL AS NVARCHAR(100)) AS VerifiedMimeType,
               CAST(NULL AS BIGINT) AS ContentLength,
               CAST(NULL AS NVARCHAR(260)) AS OriginalFileName,
               CAST(NULL AS BINARY(8)) AS RowVersion;
        RETURN;
    END;

    IF @StorageStatus <> 2 OR @ScanStatus <> 1
       OR @TrustedBlobContainer IS NULL OR @TrustedBlobObjectName IS NULL
       OR @TrustedBlobETag IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'content-unavailable' AS Code,
               @AssetPublicId AS AssetPublicId,
               CAST(NULL AS TINYINT) AS Kind,
               CAST(NULL AS NVARCHAR(63)) AS TrustedBlobContainer,
               CAST(NULL AS NVARCHAR(1024)) AS TrustedBlobObjectName,
               CAST(NULL AS NVARCHAR(100)) AS TrustedBlobETag,
               CAST(NULL AS NVARCHAR(200)) AS TrustedBlobVersionId,
               CAST(NULL AS BINARY(32)) AS ContentHash,
               CAST(NULL AS NVARCHAR(100)) AS VerifiedMimeType,
               CAST(NULL AS BIGINT) AS ContentLength,
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
           @ContentHash AS ContentHash,
           @VerifiedMimeType AS VerifiedMimeType,
           @ContentLength AS ContentLength,
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

    /* Result set 1: collection envelope, including an ETag even when empty. */
    SELECT PublicId AS ProjectPublicId, PublicationStatus,
           RowVersion AS ProjectRowVersion
    FROM dbo.FundingPlatform_Projects
    WHERE Id = @ProjectId;

    /* Result set 2: safe metadata only. Blob locations are intentionally absent. */
    SELECT PublicId AS AssetPublicId,
           Kind,
           OriginalFileName,
           DisplayName,
           VerifiedMimeType,
           ContentLength,
           PixelWidth,
           PixelHeight,
           StorageStatus,
           ScanStatus,
           ScanProvider,
           ScanResultCode,
           AltText,
           Caption,
           SortOrder,
           IsCover,
           CAST(CASE WHEN StorageStatus = 2 AND ScanStatus = 1
                     THEN 1 ELSE 0 END AS BIT) AS ContentAvailable,
           CreatedAtUtc,
           UpdatedAtUtc,
           RowVersion
    FROM dbo.FundingPlatform_ProjectAssets
    WHERE ProjectId = @ProjectId AND IsDeleted = 0
    ORDER BY SortOrder, Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAsset_UpdateMetadata
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER,
    @AssetPublicId UNIQUEIDENTIFIER,
    @ExpectedAssetRowVersion BINARY(8),
    @ExpectedProjectRowVersion BINARY(8),
    @DisplayName NVARCHAR(200) = NULL,
    @AltText NVARCHAR(300) = NULL,
    @Caption NVARCHAR(1000) = NULL,
    @IsCover BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @ProjectId BIGINT;
    DECLARE @ActorUserId BIGINT;
    DECLARE @PublicationStatus TINYINT;
    DECLARE @CurrentProjectRowVersion BINARY(8);
    DECLARE @AssetId BIGINT;
    DECLARE @Kind TINYINT;
    DECLARE @StorageStatus TINYINT;
    DECLARE @ScanStatus TINYINT;
    DECLARE @CurrentAssetRowVersion BINARY(8);
    DECLARE @ResultAssetRowVersion BINARY(8);
    DECLARE @ResultProjectRowVersion BINARY(8);
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @Succeeded BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    SET @DisplayName = NULLIF(LTRIM(RTRIM(@DisplayName)), N'');
    SET @AltText = NULLIF(LTRIM(RTRIM(@AltText)), N'');
    SET @Caption = NULLIF(LTRIM(RTRIM(@Caption)), N'');

    IF @ExpectedAssetRowVersion IS NULL OR @ExpectedProjectRowVersion IS NULL
       OR @IsCover IS NULL
       OR (@IsCover = 1 AND @AltText IS NULL)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-metadata' AS Code,
               @AssetPublicId AS AssetPublicId,
               CAST(NULL AS BINARY(8)) AS AssetRowVersion,
               CAST(NULL AS BINARY(8)) AS ProjectRowVersion;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_UpdateProjectAsset;

    BEGIN TRY
        SELECT @ProjectId = projects.Id,
               @ActorUserId = users.Id,
               @PublicationStatus = projects.PublicationStatus,
               @CurrentProjectRowVersion = projects.RowVersion
        FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id
           AND memberships.Role = 1 AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
            ON users.Id = memberships.UserId AND users.Status = 2
        INNER JOIN dbo.FundingPlatform_Projects AS projects WITH (UPDLOCK, HOLDLOCK)
            ON projects.OrganizationId = organizations.Id AND projects.IsActive = 1
        WHERE organizations.PublicId = @OrganizationPublicId
          AND organizations.IsActive = 1
          AND projects.PublicId = @ProjectPublicId
          AND users.PublicId = @UserPublicId;

        IF @ProjectId IS NULL
            THROW 55602, N'Active organization administrator membership is required.', 1;

        SELECT @AssetId = Id,
               @Kind = Kind,
               @StorageStatus = StorageStatus,
               @ScanStatus = ScanStatus,
               @CurrentAssetRowVersion = RowVersion
        FROM dbo.FundingPlatform_ProjectAssets WITH (UPDLOCK, HOLDLOCK)
        WHERE ProjectId = @ProjectId AND PublicId = @AssetPublicId AND IsDeleted = 0;

        IF @AssetId IS NULL
            SET @Code = N'not-found';
        ELSE IF @PublicationStatus NOT IN (0, 3)
            SET @Code = N'project-not-editable';
        ELSE IF @CurrentProjectRowVersion <> @ExpectedProjectRowVersion
            SET @Code = N'project-etag-conflict';
        ELSE IF @CurrentAssetRowVersion <> @ExpectedAssetRowVersion
            SET @Code = N'asset-etag-conflict';
        ELSE IF @IsCover = 1 AND @Kind <> 0
            SET @Code = N'cover-requires-image';
        ELSE IF @IsCover = 1 AND (@StorageStatus <> 2 OR @ScanStatus <> 1)
            SET @Code = N'cover-image-not-ready';
        ELSE
        BEGIN
            IF @IsCover = 1
                UPDATE dbo.FundingPlatform_ProjectAssets
                SET IsCover = 0, UpdatedAtUtc = @NowUtc
                WHERE ProjectId = @ProjectId AND IsDeleted = 0
                  AND IsCover = 1 AND Id <> @AssetId;

            DECLARE @UpdatedAsset TABLE (RowVersion BINARY(8) NOT NULL);
            UPDATE dbo.FundingPlatform_ProjectAssets
            SET DisplayName = @DisplayName,
                AltText = @AltText,
                Caption = @Caption,
                IsCover = @IsCover,
                UpdatedAtUtc = @NowUtc
            OUTPUT inserted.RowVersion INTO @UpdatedAsset (RowVersion)
            WHERE Id = @AssetId AND RowVersion = @ExpectedAssetRowVersion;
            SELECT @ResultAssetRowVersion = RowVersion FROM @UpdatedAsset;

            DECLARE @UpdatedProject TABLE (RowVersion BINARY(8) NOT NULL);
            UPDATE dbo.FundingPlatform_Projects
            SET UpdatedAtUtc = @NowUtc
            OUTPUT inserted.RowVersion INTO @UpdatedProject (RowVersion)
            WHERE Id = @ProjectId AND RowVersion = @ExpectedProjectRowVersion;
            SELECT @ResultProjectRowVersion = RowVersion FROM @UpdatedProject;

            IF @ResultAssetRowVersion IS NULL OR @ResultProjectRowVersion IS NULL
                THROW 55605, N'Project asset changed during metadata update.', 1;

            SET @Succeeded = 1;
            SET @Code = N'updated';

            INSERT INTO dbo.FundingPlatform_OutboxMessages
                (MessageType, AggregateType, AggregateId, PayloadJson,
                 OccurredAtUtc, AvailableAtUtc)
            SELECT N'ProjectAssetMetadataUpdated', N'ProjectAsset',
                   CONVERT(NVARCHAR(100), @AssetPublicId),
                   (SELECT @AssetPublicId AS assetPublicId,
                           @ProjectPublicId AS projectPublicId,
                           @IsCover AS isCover
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                   @NowUtc, @NowUtc;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        SELECT @Succeeded AS Succeeded, @Code AS Code,
               @AssetPublicId AS AssetPublicId,
               COALESCE(@ResultAssetRowVersion, @CurrentAssetRowVersion) AS AssetRowVersion,
               COALESCE(@ResultProjectRowVersion, @CurrentProjectRowVersion) AS ProjectRowVersion;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_UpdateProjectAsset;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAsset_Reorder
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER,
    @ExpectedProjectRowVersion BINARY(8),
    @Items dbo.FundingPlatform_ProjectAssetOrderList READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @ProjectId BIGINT;
    DECLARE @PublicationStatus TINYINT;
    DECLARE @CurrentProjectRowVersion BINARY(8);
    DECLARE @ResultProjectRowVersion BINARY(8);
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @Succeeded BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @ExpectedProjectRowVersion IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-order' AS Code,
               CAST(NULL AS BINARY(8)) AS ProjectRowVersion;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_ReorderProjectAssets;

    BEGIN TRY
        SELECT @ProjectId = projects.Id,
               @PublicationStatus = projects.PublicationStatus,
               @CurrentProjectRowVersion = projects.RowVersion
        FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id
           AND memberships.Role = 1 AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
            ON users.Id = memberships.UserId AND users.Status = 2
        INNER JOIN dbo.FundingPlatform_Projects AS projects WITH (UPDLOCK, HOLDLOCK)
            ON projects.OrganizationId = organizations.Id AND projects.IsActive = 1
        WHERE organizations.PublicId = @OrganizationPublicId
          AND organizations.IsActive = 1
          AND projects.PublicId = @ProjectPublicId
          AND users.PublicId = @UserPublicId;

        IF @ProjectId IS NULL
            THROW 55602, N'Active organization administrator membership is required.', 1;

        DECLARE @ActiveCount INT =
            (SELECT COUNT(1) FROM dbo.FundingPlatform_ProjectAssets WITH (UPDLOCK, HOLDLOCK)
             WHERE ProjectId = @ProjectId AND IsDeleted = 0);

        IF @PublicationStatus NOT IN (0, 3)
            SET @Code = N'project-not-editable';
        ELSE IF @CurrentProjectRowVersion <> @ExpectedProjectRowVersion
            SET @Code = N'project-etag-conflict';
        ELSE IF @ActiveCount <> (SELECT COUNT(1) FROM @Items)
             OR EXISTS
                (
                    SELECT 1
                    FROM @Items AS requested
                    LEFT JOIN dbo.FundingPlatform_ProjectAssets AS assets
                        ON assets.ProjectId = @ProjectId
                       AND assets.PublicId = requested.AssetPublicId
                       AND assets.IsDeleted = 0
                    WHERE assets.Id IS NULL OR assets.RowVersion <> requested.ExpectedRowVersion
                )
             OR EXISTS
                (
                    SELECT 1
                    FROM dbo.FundingPlatform_ProjectAssets AS assets
                    LEFT JOIN @Items AS requested ON requested.AssetPublicId = assets.PublicId
                    WHERE assets.ProjectId = @ProjectId AND assets.IsDeleted = 0
                      AND requested.AssetPublicId IS NULL
                )
            SET @Code = N'asset-order-conflict';
        ELSE IF @ActiveCount = 0
        BEGIN
            SET @Succeeded = 1;
            SET @Code = N'ordered';
            SET @ResultProjectRowVersion = @CurrentProjectRowVersion;
        END
        ELSE
        BEGIN
            UPDATE assets
            SET SortOrder = requested.SortOrder,
                UpdatedAtUtc = @NowUtc
            FROM dbo.FundingPlatform_ProjectAssets AS assets
            INNER JOIN @Items AS requested ON requested.AssetPublicId = assets.PublicId
            WHERE assets.ProjectId = @ProjectId AND assets.IsDeleted = 0
              AND assets.RowVersion = requested.ExpectedRowVersion;

            IF @@ROWCOUNT <> @ActiveCount
                THROW 55605, N'Project assets changed during reorder.', 1;

            DECLARE @UpdatedProject TABLE (RowVersion BINARY(8) NOT NULL);
            UPDATE dbo.FundingPlatform_Projects
            SET UpdatedAtUtc = @NowUtc
            OUTPUT inserted.RowVersion INTO @UpdatedProject (RowVersion)
            WHERE Id = @ProjectId AND RowVersion = @ExpectedProjectRowVersion;
            SELECT @ResultProjectRowVersion = RowVersion FROM @UpdatedProject;
            IF @ResultProjectRowVersion IS NULL
                THROW 55605, N'Project changed during asset reorder.', 1;

            SET @Succeeded = 1;
            SET @Code = N'ordered';

            INSERT INTO dbo.FundingPlatform_OutboxMessages
                (MessageType, AggregateType, AggregateId, PayloadJson,
                 OccurredAtUtc, AvailableAtUtc)
            SELECT N'ProjectAssetsReordered', N'Project',
                   CONVERT(NVARCHAR(100), @ProjectId),
                   (SELECT @ProjectPublicId AS projectPublicId,
                           @ActiveCount AS assetCount
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                   @NowUtc, @NowUtc;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        SELECT @Succeeded AS Succeeded, @Code AS Code,
               COALESCE(@ResultProjectRowVersion, @CurrentProjectRowVersion) AS ProjectRowVersion;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ReorderProjectAssets;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAsset_Delete
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER,
    @AssetPublicId UNIQUEIDENTIFIER,
    @ExpectedAssetRowVersion BINARY(8),
    @ExpectedProjectRowVersion BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @ProjectId BIGINT;
    DECLARE @ActorUserId BIGINT;
    DECLARE @PublicationStatus TINYINT;
    DECLARE @CurrentProjectRowVersion BINARY(8);
    DECLARE @AssetId BIGINT;
    DECLARE @IsDeleted BIT;
    DECLARE @CurrentAssetRowVersion BINARY(8);
    DECLARE @ResultAssetRowVersion BINARY(8);
    DECLARE @ResultProjectRowVersion BINARY(8);
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @Succeeded BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @ExpectedAssetRowVersion IS NULL OR @ExpectedProjectRowVersion IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-asset' AS Code,
               @AssetPublicId AS AssetPublicId,
               CAST(NULL AS BINARY(8)) AS AssetRowVersion,
               CAST(NULL AS BINARY(8)) AS ProjectRowVersion;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_DeleteProjectAsset;

    BEGIN TRY
        SELECT @ProjectId = projects.Id,
               @ActorUserId = users.Id,
               @PublicationStatus = projects.PublicationStatus,
               @CurrentProjectRowVersion = projects.RowVersion
        FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id
           AND memberships.Role = 1 AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
            ON users.Id = memberships.UserId AND users.Status = 2
        INNER JOIN dbo.FundingPlatform_Projects AS projects WITH (UPDLOCK, HOLDLOCK)
            ON projects.OrganizationId = organizations.Id AND projects.IsActive = 1
        WHERE organizations.PublicId = @OrganizationPublicId
          AND organizations.IsActive = 1
          AND projects.PublicId = @ProjectPublicId
          AND users.PublicId = @UserPublicId;

        IF @ProjectId IS NULL
            THROW 55602, N'Active organization administrator membership is required.', 1;

        SELECT @AssetId = Id, @IsDeleted = IsDeleted,
               @CurrentAssetRowVersion = RowVersion
        FROM dbo.FundingPlatform_ProjectAssets WITH (UPDLOCK, HOLDLOCK)
        WHERE ProjectId = @ProjectId AND PublicId = @AssetPublicId;

        IF @AssetId IS NULL
            SET @Code = N'not-found';
        ELSE IF @IsDeleted = 1
        BEGIN
            SET @Succeeded = 1;
            SET @Code = N'deleted';
            SET @ResultAssetRowVersion = @CurrentAssetRowVersion;
            SET @ResultProjectRowVersion = @CurrentProjectRowVersion;
        END
        ELSE IF @PublicationStatus NOT IN (0, 3)
            SET @Code = N'project-not-editable';
        ELSE IF @CurrentProjectRowVersion <> @ExpectedProjectRowVersion
            SET @Code = N'project-etag-conflict';
        ELSE IF @CurrentAssetRowVersion <> @ExpectedAssetRowVersion
            SET @Code = N'asset-etag-conflict';
        ELSE
        BEGIN
            DECLARE @UpdatedAsset TABLE (RowVersion BINARY(8) NOT NULL);
            UPDATE dbo.FundingPlatform_ProjectAssets
            SET IsDeleted = 1,
                IsCover = 0,
                DeletedByUserId = @ActorUserId,
                DeletedAtUtc = @NowUtc,
                UpdatedAtUtc = @NowUtc
            OUTPUT inserted.RowVersion INTO @UpdatedAsset (RowVersion)
            WHERE Id = @AssetId AND RowVersion = @ExpectedAssetRowVersion;
            SELECT @ResultAssetRowVersion = RowVersion FROM @UpdatedAsset;

            DECLARE @UpdatedProject TABLE (RowVersion BINARY(8) NOT NULL);
            UPDATE dbo.FundingPlatform_Projects
            SET UpdatedAtUtc = @NowUtc
            OUTPUT inserted.RowVersion INTO @UpdatedProject (RowVersion)
            WHERE Id = @ProjectId AND RowVersion = @ExpectedProjectRowVersion;
            SELECT @ResultProjectRowVersion = RowVersion FROM @UpdatedProject;

            IF @ResultAssetRowVersion IS NULL OR @ResultProjectRowVersion IS NULL
                THROW 55605, N'Project asset changed during delete.', 1;

            SET @Succeeded = 1;
            SET @Code = N'deleted';

            INSERT INTO dbo.FundingPlatform_OutboxMessages
                (MessageType, AggregateType, AggregateId, PayloadJson,
                 OccurredAtUtc, AvailableAtUtc)
            SELECT N'ProjectAssetDeleted', N'ProjectAsset',
                   CONVERT(NVARCHAR(100), @AssetPublicId),
                   (SELECT @AssetPublicId AS assetPublicId,
                           @ProjectPublicId AS projectPublicId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                   @NowUtc, @NowUtc;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        SELECT @Succeeded AS Succeeded, @Code AS Code,
               @AssetPublicId AS AssetPublicId,
               COALESCE(@ResultAssetRowVersion, @CurrentAssetRowVersion) AS AssetRowVersion,
               COALESCE(@ResultProjectRowVersion, @CurrentProjectRowVersion) AS ProjectRowVersion;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_DeleteProjectAsset;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Complete
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER,
    @IntentPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @ExpectedProjectRowVersion BINARY(8),
    @VerifiedMimeType NVARCHAR(100),
    @ActualContentLength BIGINT,
    @ContentHash BINARY(32),
    @ScanProvider TINYINT,
    @PixelWidth INT = NULL,
    @PixelHeight INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @ProjectId BIGINT;
    DECLARE @ActorUserId BIGINT;
    DECLARE @PublicationStatus TINYINT;
    DECLARE @CurrentProjectRowVersion BINARY(8);
    DECLARE @ResultProjectRowVersion BINARY(8);
    DECLARE @IntentId BIGINT;
    DECLARE @Kind TINYINT;
    DECLARE @OriginalFileName NVARCHAR(260);
    DECLARE @DeclaredMimeType NVARCHAR(100);
    DECLARE @ExpectedContentLength BIGINT;
    DECLARE @MaxContentLength BIGINT;
    DECLARE @QuarantineBlobContainer NVARCHAR(63);
    DECLARE @QuarantineBlobObjectName NVARCHAR(1024);
    DECLARE @UploadedByUserId BIGINT;
    DECLARE @Status TINYINT;
    DECLARE @StoredLeaseId UNIQUEIDENTIFIER;
    DECLARE @StoredLeaseUntilUtc DATETIME2(3);
    DECLARE @AssetId BIGINT;
    DECLARE @AssetPublicId UNIQUEIDENTIFIER;
    DECLARE @StorageStatus TINYINT;
    DECLARE @ScanStatus TINYINT;
    DECLARE @StoredScanProvider TINYINT;
    DECLARE @AssetRowVersion BINARY(8);
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @Succeeded BIT = 0;
    DECLARE @WasReplay BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    SET @VerifiedMimeType = LOWER(LTRIM(RTRIM(@VerifiedMimeType)));
    IF @LeaseId IS NULL OR @ExpectedProjectRowVersion IS NULL
       OR NULLIF(@VerifiedMimeType, N'') IS NULL
       OR @ContentHash IS NULL OR @ScanProvider IS NULL
       OR @ScanProvider NOT BETWEEN 0 AND 1
       OR @ActualContentLength IS NULL
       OR @ActualContentLength < 1 OR @ActualContentLength > 26214400
       OR @VerifiedMimeType NOT IN
          (N'image/jpeg', N'image/png', N'image/webp', N'application/pdf')
       OR (@VerifiedMimeType IN (N'image/jpeg', N'image/png', N'image/webp')
           AND (@PixelWidth IS NULL OR @PixelHeight IS NULL
                OR @PixelWidth NOT BETWEEN 1 AND 32768
                OR @PixelHeight NOT BETWEEN 1 AND 32768
                OR CONVERT(BIGINT, @PixelWidth) * CONVERT(BIGINT, @PixelHeight) > 25000000))
       OR (@VerifiedMimeType = N'application/pdf'
           AND (@PixelWidth IS NOT NULL OR @PixelHeight IS NOT NULL))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-asset' AS Code,
               @IntentPublicId AS IntentPublicId,
               CAST(NULL AS UNIQUEIDENTIFIER) AS AssetPublicId,
               CAST(NULL AS TINYINT) AS StorageStatus,
               CAST(NULL AS TINYINT) AS ScanStatus,
               CAST(NULL AS TINYINT) AS ScanProvider,
               CAST(NULL AS BINARY(8)) AS AssetRowVersion,
               CAST(NULL AS BINARY(8)) AS ProjectRowVersion,
               CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_CompleteProjectAsset;

    BEGIN TRY
        SELECT @ProjectId = projects.Id,
               @ActorUserId = users.Id,
               @PublicationStatus = projects.PublicationStatus,
               @CurrentProjectRowVersion = projects.RowVersion,
               @IntentId = intents.Id,
               @Kind = intents.Kind,
               @OriginalFileName = intents.OriginalFileName,
               @DeclaredMimeType = intents.DeclaredMimeType,
               @ExpectedContentLength = intents.ExpectedContentLength,
               @MaxContentLength = intents.MaxContentLength,
               @QuarantineBlobContainer = intents.QuarantineBlobContainer,
               @QuarantineBlobObjectName = intents.QuarantineBlobObjectName,
               @UploadedByUserId = intents.UploadedByUserId,
               @Status = intents.Status,
               @StoredLeaseId = intents.FinalizeLeaseId,
               @StoredLeaseUntilUtc = intents.FinalizeLeaseUntilUtc,
               @AssetId = intents.CompletedProjectAssetId
        FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id
           AND memberships.Role = 1 AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
            ON users.Id = memberships.UserId AND users.Status = 2
        INNER JOIN dbo.FundingPlatform_Projects AS projects WITH (UPDLOCK, HOLDLOCK)
            ON projects.OrganizationId = organizations.Id AND projects.IsActive = 1
        INNER JOIN dbo.FundingPlatform_ProjectAssetUploadIntents AS intents
            WITH (UPDLOCK, HOLDLOCK) ON intents.ProjectId = projects.Id
        WHERE organizations.PublicId = @OrganizationPublicId
          AND organizations.IsActive = 1
          AND projects.PublicId = @ProjectPublicId
          AND users.PublicId = @UserPublicId
          AND intents.PublicId = @IntentPublicId;

        IF @IntentId IS NULL
            SET @Code = N'not-found';
        ELSE IF @Status = 2
        BEGIN
            SELECT @AssetPublicId = assets.PublicId,
                   @StorageStatus = assets.StorageStatus,
                   @ScanStatus = assets.ScanStatus,
                   @StoredScanProvider = assets.ScanProvider,
                   @AssetRowVersion = assets.RowVersion
            FROM dbo.FundingPlatform_ProjectAssets AS assets WITH (UPDLOCK, HOLDLOCK)
            WHERE assets.Id = @AssetId
              AND assets.IsDeleted = 0
              AND assets.VerifiedMimeType = @VerifiedMimeType
              AND assets.ContentLength = @ActualContentLength
              AND assets.ContentHash = @ContentHash
              AND ((assets.PixelWidth IS NULL AND @PixelWidth IS NULL)
                   OR assets.PixelWidth = @PixelWidth)
              AND ((assets.PixelHeight IS NULL AND @PixelHeight IS NULL)
                   OR assets.PixelHeight = @PixelHeight)
              AND assets.ScanProvider = @ScanProvider;

            IF @AssetPublicId IS NULL
                SET @Code = N'completion-conflict';
            ELSE
            BEGIN
                SET @Succeeded = 1;
                SET @Code = N'completed';
                SET @WasReplay = 1;
                SET @ResultProjectRowVersion = @CurrentProjectRowVersion;
            END;
        END
        ELSE IF @PublicationStatus NOT IN (0, 3)
            SET @Code = N'project-not-editable';
        ELSE IF @Status <> 1 OR @StoredLeaseId <> @LeaseId
            SET @Code = N'lease-conflict';
        ELSE IF @StoredLeaseUntilUtc <= @NowUtc
            SET @Code = N'lease-expired';
        ELSE IF @CurrentProjectRowVersion <> @ExpectedProjectRowVersion
            SET @Code = N'project-etag-conflict';
        ELSE IF @VerifiedMimeType <> @DeclaredMimeType
             OR @ActualContentLength <> @ExpectedContentLength
             OR @ActualContentLength > @MaxContentLength
             OR (@Kind = 0 AND
                 (@VerifiedMimeType NOT IN (N'image/jpeg', N'image/png', N'image/webp')
                  OR @ActualContentLength > 10485760
                  OR @PixelWidth IS NULL OR @PixelHeight IS NULL))
             OR (@Kind = 1 AND
                 (@VerifiedMimeType <> N'application/pdf'
                  OR @ActualContentLength > 26214400
                  OR @PixelWidth IS NOT NULL OR @PixelHeight IS NOT NULL))
            SET @Code = N'verification-mismatch';
        ELSE IF (SELECT COUNT_BIG(1)
                 FROM dbo.FundingPlatform_ProjectAssets WITH (UPDLOCK, HOLDLOCK)
                 WHERE ProjectId = @ProjectId AND IsDeleted = 0) >= 12
            SET @Code = N'asset-limit';
        ELSE IF @Kind = 0 AND
                (SELECT COUNT_BIG(1)
                 FROM dbo.FundingPlatform_ProjectAssets WITH (UPDLOCK, HOLDLOCK)
                 WHERE ProjectId = @ProjectId AND Kind = 0 AND IsDeleted = 0) >= 8
            SET @Code = N'image-limit';
        ELSE IF @Kind = 1 AND
                (SELECT COUNT_BIG(1)
                 FROM dbo.FundingPlatform_ProjectAssets WITH (UPDLOCK, HOLDLOCK)
                 WHERE ProjectId = @ProjectId AND Kind = 1 AND IsDeleted = 0) >= 4
            SET @Code = N'document-limit';
        ELSE IF COALESCE
                ((SELECT SUM(ContentLength)
                  FROM dbo.FundingPlatform_ProjectAssets WITH (UPDLOCK, HOLDLOCK)
                  WHERE ProjectId = @ProjectId AND IsDeleted = 0), 0)
                + @ActualContentLength > 262144000
            SET @Code = N'project-byte-limit';
        ELSE
        BEGIN
            DECLARE @NextSortOrder SMALLINT = CONVERT(SMALLINT, COALESCE
                ((SELECT MAX(SortOrder)
                  FROM dbo.FundingPlatform_ProjectAssets WITH (UPDLOCK, HOLDLOCK)
                  WHERE ProjectId = @ProjectId AND IsDeleted = 0), -1) + 1);
            DECLARE @InsertedAsset TABLE
                (Id BIGINT NOT NULL, PublicId UNIQUEIDENTIFIER NOT NULL,
                 RowVersion BINARY(8) NOT NULL);

            INSERT INTO dbo.FundingPlatform_ProjectAssets
                (ProjectId, Kind, OriginalFileName, DisplayName,
                 VerifiedMimeType, ContentLength, ContentHash, PixelWidth, PixelHeight,
                 QuarantineBlobContainer, QuarantineBlobObjectName,
                 StorageStatus, ScanStatus, ScanProvider,
                 SortOrder, IsCover, IsDeleted, UploadedByUserId,
                 CreatedAtUtc, UpdatedAtUtc)
            OUTPUT inserted.Id, inserted.PublicId, inserted.RowVersion
                INTO @InsertedAsset (Id, PublicId, RowVersion)
            VALUES
                (@ProjectId, @Kind, @OriginalFileName, NULL,
                 @VerifiedMimeType, @ActualContentLength, @ContentHash,
                 @PixelWidth, @PixelHeight,
                 @QuarantineBlobContainer, @QuarantineBlobObjectName,
                 0, 0, @ScanProvider,
                 @NextSortOrder, 0, 0, @UploadedByUserId,
                 @NowUtc, @NowUtc);

            SELECT @AssetId = Id, @AssetPublicId = PublicId,
                   @AssetRowVersion = RowVersion
            FROM @InsertedAsset;

            UPDATE dbo.FundingPlatform_ProjectAssetUploadIntents
            SET Status = 2,
                FinalizeLeaseId = NULL,
                FinalizeLeaseUntilUtc = NULL,
                CompletedProjectAssetId = @AssetId,
                CompletedAtUtc = @NowUtc,
                LastErrorCode = NULL,
                UpdatedAtUtc = @NowUtc
            WHERE Id = @IntentId;

            DECLARE @UpdatedProject TABLE (RowVersion BINARY(8) NOT NULL);
            UPDATE dbo.FundingPlatform_Projects
            SET UpdatedAtUtc = @NowUtc
            OUTPUT inserted.RowVersion INTO @UpdatedProject (RowVersion)
            WHERE Id = @ProjectId AND RowVersion = @ExpectedProjectRowVersion;
            SELECT @ResultProjectRowVersion = RowVersion FROM @UpdatedProject;
            IF @ResultProjectRowVersion IS NULL
                THROW 55605, N'Project changed while completing its asset.', 1;

            SET @StorageStatus = 0;
            SET @ScanStatus = 0;
            SET @StoredScanProvider = @ScanProvider;
            SET @Succeeded = 1;
            SET @Code = N'completed';

            INSERT INTO dbo.FundingPlatform_OutboxMessages
                (MessageType, AggregateType, AggregateId, PayloadJson,
                 OccurredAtUtc, AvailableAtUtc)
            SELECT N'ProjectAssetFinalized', N'ProjectAsset',
                   CONVERT(NVARCHAR(100), @AssetPublicId),
                   (SELECT @AssetPublicId AS assetPublicId,
                           @ProjectPublicId AS projectPublicId,
                           @IntentPublicId AS intentPublicId,
                           @Kind AS kind, CAST(0 AS TINYINT) AS storageStatus,
                           CAST(0 AS TINYINT) AS scanStatus, @ScanProvider AS scanProvider
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                   @NowUtc, @NowUtc;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        SELECT @Succeeded AS Succeeded, @Code AS Code,
               @IntentPublicId AS IntentPublicId,
               @AssetPublicId AS AssetPublicId,
               @StorageStatus AS StorageStatus,
               @ScanStatus AS ScanStatus,
               @StoredScanProvider AS ScanProvider,
               @AssetRowVersion AS AssetRowVersion,
               COALESCE(@ResultProjectRowVersion, @CurrentProjectRowVersion) AS ProjectRowVersion,
               @WasReplay AS WasReplay;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_CompleteProjectAsset;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAsset_MarkQuarantined
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER,
    @AssetPublicId UNIQUEIDENTIFIER,
    @ExpectedAssetRowVersion BINARY(8),
    @QuarantineBlobETag NVARCHAR(100),
    @QuarantineBlobVersionId NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @ProjectId BIGINT;
    DECLARE @AssetId BIGINT;
    DECLARE @PublicationStatus TINYINT;
    DECLARE @StorageStatus TINYINT;
    DECLARE @ScanStatus TINYINT;
    DECLARE @ScanProvider TINYINT;
    DECLARE @StoredETag NVARCHAR(100);
    DECLARE @StoredVersionId NVARCHAR(200);
    DECLARE @AssetRowVersion BINARY(8);
    DECLARE @ProjectRowVersion BINARY(8);
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @Succeeded BIT = 0;
    DECLARE @WasReplay BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    SET @QuarantineBlobETag = LTRIM(RTRIM(@QuarantineBlobETag));
    SET @QuarantineBlobVersionId = NULLIF(LTRIM(RTRIM(@QuarantineBlobVersionId)), N'');
    IF @ExpectedAssetRowVersion IS NULL
       OR LEN(COALESCE(@QuarantineBlobETag, N'')) NOT BETWEEN 3 AND 100
       OR LEFT(@QuarantineBlobETag, 1) <> N'"'
       OR RIGHT(@QuarantineBlobETag, 1) <> N'"'
       OR LEN(COALESCE(@QuarantineBlobVersionId, N'')) > 200
       OR CHARINDEX(CHAR(10), @QuarantineBlobETag) > 0
       OR CHARINDEX(CHAR(13), @QuarantineBlobETag) > 0
       OR CHARINDEX(CHAR(10), COALESCE(@QuarantineBlobVersionId, N'')) > 0
       OR CHARINDEX(CHAR(13), COALESCE(@QuarantineBlobVersionId, N'')) > 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-receipt' AS Code,
               @AssetPublicId AS AssetPublicId,
               CAST(NULL AS TINYINT) AS StorageStatus,
               CAST(NULL AS TINYINT) AS ScanStatus,
               CAST(NULL AS TINYINT) AS ScanProvider,
               CAST(NULL AS BINARY(8)) AS AssetRowVersion,
               CAST(NULL AS BINARY(8)) AS ProjectRowVersion,
               CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_MarkProjectAssetQuarantine;

    BEGIN TRY
        SELECT @ProjectId = projects.Id,
               @PublicationStatus = projects.PublicationStatus,
               @ProjectRowVersion = projects.RowVersion,
               @AssetId = assets.Id,
               @StorageStatus = assets.StorageStatus,
               @ScanStatus = assets.ScanStatus,
               @ScanProvider = assets.ScanProvider,
               @StoredETag = assets.QuarantineBlobETag,
               @StoredVersionId = assets.QuarantineBlobVersionId,
               @AssetRowVersion = assets.RowVersion
        FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id
           AND memberships.Role = 1 AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
            ON users.Id = memberships.UserId AND users.Status = 2
        INNER JOIN dbo.FundingPlatform_Projects AS projects WITH (UPDLOCK, HOLDLOCK)
            ON projects.OrganizationId = organizations.Id AND projects.IsActive = 1
        INNER JOIN dbo.FundingPlatform_ProjectAssets AS assets WITH (UPDLOCK, HOLDLOCK)
            ON assets.ProjectId = projects.Id AND assets.IsDeleted = 0
        WHERE organizations.PublicId = @OrganizationPublicId
          AND organizations.IsActive = 1
          AND projects.PublicId = @ProjectPublicId
          AND users.PublicId = @UserPublicId
          AND assets.PublicId = @AssetPublicId;

        IF @AssetId IS NULL
            SET @Code = N'not-found';
        ELSE IF @StorageStatus IN (1, 2)
             AND @StoredETag = @QuarantineBlobETag
             AND ((@StoredVersionId IS NULL AND @QuarantineBlobVersionId IS NULL)
                  OR @StoredVersionId = @QuarantineBlobVersionId)
        BEGIN
            SET @Succeeded = 1;
            SET @Code = CASE WHEN @StorageStatus = 2 THEN N'trusted' ELSE N'quarantined' END;
            SET @WasReplay = 1;
        END
        ELSE IF @PublicationStatus NOT IN (0, 3)
            SET @Code = N'project-not-editable';
        ELSE IF @AssetRowVersion <> @ExpectedAssetRowVersion
            SET @Code = N'asset-etag-conflict';
        ELSE IF @StorageStatus = 0 AND @ScanStatus = 0
        BEGIN
            DECLARE @UpdatedAsset TABLE (RowVersion BINARY(8) NOT NULL);
            UPDATE dbo.FundingPlatform_ProjectAssets
            SET QuarantineBlobETag = @QuarantineBlobETag,
                QuarantineBlobVersionId = @QuarantineBlobVersionId,
                StorageStatus = 1,
                ScanStartedAtUtc = COALESCE(ScanStartedAtUtc, @NowUtc),
                UpdatedAtUtc = @NowUtc
            OUTPUT inserted.RowVersion INTO @UpdatedAsset (RowVersion)
            WHERE Id = @AssetId AND RowVersion = @ExpectedAssetRowVersion;
            SELECT @AssetRowVersion = RowVersion FROM @UpdatedAsset;

            DECLARE @UpdatedProject TABLE (RowVersion BINARY(8) NOT NULL);
            UPDATE dbo.FundingPlatform_Projects
            SET UpdatedAtUtc = @NowUtc
            OUTPUT inserted.RowVersion INTO @UpdatedProject (RowVersion)
            WHERE Id = @ProjectId;
            SELECT @ProjectRowVersion = RowVersion FROM @UpdatedProject;

            SET @StorageStatus = 1;
            SET @Succeeded = 1;
            SET @Code = N'quarantined';

            INSERT INTO dbo.FundingPlatform_OutboxMessages
                (MessageType, AggregateType, AggregateId, PayloadJson,
                 OccurredAtUtc, AvailableAtUtc)
            SELECT N'ProjectAssetQuarantined', N'ProjectAsset',
                   CONVERT(NVARCHAR(100), @AssetPublicId),
                   (SELECT @AssetPublicId AS assetPublicId,
                           @ProjectPublicId AS projectPublicId,
                           CAST(1 AS TINYINT) AS storageStatus,
                           CAST(0 AS TINYINT) AS scanStatus,
                           @ScanProvider AS scanProvider
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                   @NowUtc, @NowUtc;
        END
        ELSE SET @Code = N'invalid-state';

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        SELECT @Succeeded AS Succeeded, @Code AS Code,
               @AssetPublicId AS AssetPublicId,
               @StorageStatus AS StorageStatus,
               @ScanStatus AS ScanStatus,
               @ScanProvider AS ScanProvider,
               @AssetRowVersion AS AssetRowVersion,
               @ProjectRowVersion AS ProjectRowVersion,
               @WasReplay AS WasReplay;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_MarkProjectAssetQuarantine;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAssetUploadIntent_ReleaseFinalize
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER,
    @IntentPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @ErrorCode NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @IntentId BIGINT;
    DECLARE @Status TINYINT;
    DECLARE @ExpiresAtUtc DATETIME2(3);
    DECLARE @StoredLeaseId UNIQUEIDENTIFIER;
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @Succeeded BIT = 0;
    DECLARE @WasReplay BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    SET @ErrorCode = LTRIM(RTRIM(@ErrorCode));
    IF @LeaseId IS NULL OR NULLIF(@ErrorCode, N'') IS NULL
       OR LEN(@ErrorCode) > 100
       OR CHARINDEX(CHAR(10), @ErrorCode) > 0
       OR CHARINDEX(CHAR(13), @ErrorCode) > 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-asset' AS Code,
               @IntentPublicId AS IntentPublicId, CAST(NULL AS TINYINT) AS Status,
               CAST(NULL AS UNIQUEIDENTIFIER) AS AssetPublicId,
               CAST(NULL AS TINYINT) AS StorageStatus,
               CAST(NULL AS TINYINT) AS ScanStatus,
               CAST(NULL AS TINYINT) AS ScanProvider,
               CAST(NULL AS BINARY(8)) AS RowVersion,
               CAST(NULL AS BINARY(8)) AS ProjectRowVersion,
               CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_ReleaseProjectAsset;

    BEGIN TRY
        SELECT @IntentId = intents.Id,
               @Status = intents.Status,
               @ExpiresAtUtc = intents.ExpiresAtUtc,
               @StoredLeaseId = intents.FinalizeLeaseId
        FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id
           AND memberships.Role = 1 AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
            ON users.Id = memberships.UserId AND users.Status = 2
        INNER JOIN dbo.FundingPlatform_Projects AS projects WITH (UPDLOCK, HOLDLOCK)
            ON projects.OrganizationId = organizations.Id AND projects.IsActive = 1
        INNER JOIN dbo.FundingPlatform_ProjectAssetUploadIntents AS intents
            WITH (UPDLOCK, HOLDLOCK) ON intents.ProjectId = projects.Id
        WHERE organizations.PublicId = @OrganizationPublicId
          AND organizations.IsActive = 1
          AND projects.PublicId = @ProjectPublicId
          AND users.PublicId = @UserPublicId
          AND intents.PublicId = @IntentPublicId;

        IF @IntentId IS NULL
            SET @Code = N'not-found';
        ELSE IF @Status = 2
        BEGIN
            SET @Succeeded = 1;
            SET @Code = N'completed';
            SET @WasReplay = 1;
        END
        ELSE IF @Status = 1 AND @StoredLeaseId = @LeaseId
        BEGIN
            SET @Status = CASE WHEN @ExpiresAtUtc <= @NowUtc THEN 3 ELSE 0 END;
            UPDATE dbo.FundingPlatform_ProjectAssetUploadIntents
            SET Status = @Status,
                FinalizeLeaseId = NULL,
                FinalizeLeaseUntilUtc = NULL,
                LastErrorCode = @ErrorCode,
                UpdatedAtUtc = @NowUtc
            WHERE Id = @IntentId;
            SET @Succeeded = 1;
            SET @Code = CASE WHEN @Status = 3 THEN N'expired' ELSE N'released' END;
        END
        ELSE SET @Code = N'lease-conflict';

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        SELECT @Succeeded AS Succeeded, @Code AS Code,
               intents.PublicId AS IntentPublicId, intents.Status,
               assets.PublicId AS AssetPublicId,
               assets.StorageStatus, assets.ScanStatus, assets.ScanProvider,
               intents.RowVersion, projects.RowVersion AS ProjectRowVersion,
               @WasReplay AS WasReplay
        FROM dbo.FundingPlatform_ProjectAssetUploadIntents AS intents
        INNER JOIN dbo.FundingPlatform_Projects AS projects ON projects.Id = intents.ProjectId
        LEFT JOIN dbo.FundingPlatform_ProjectAssets AS assets
            ON assets.Id = intents.CompletedProjectAssetId
        WHERE intents.Id = @IntentId
        UNION ALL
        SELECT @Succeeded, @Code, @IntentPublicId, NULL, NULL, NULL, NULL, NULL,
               NULL, NULL, @WasReplay
        WHERE @IntentId IS NULL;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ReleaseProjectAsset;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAssetUploadIntent_RejectFinalize
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER,
    @IntentPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @ErrorCode NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @IntentId BIGINT;
    DECLARE @Status TINYINT;
    DECLARE @StoredLeaseId UNIQUEIDENTIFIER;
    DECLARE @StoredErrorCode NVARCHAR(100);
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @Succeeded BIT = 0;
    DECLARE @WasReplay BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    SET @ErrorCode = LTRIM(RTRIM(@ErrorCode));
    IF @LeaseId IS NULL OR NULLIF(@ErrorCode, N'') IS NULL
       OR LEN(@ErrorCode) > 100
       OR CHARINDEX(CHAR(10), @ErrorCode) > 0
       OR CHARINDEX(CHAR(13), @ErrorCode) > 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-asset' AS Code,
               @IntentPublicId AS IntentPublicId, CAST(NULL AS TINYINT) AS Status,
               CAST(NULL AS UNIQUEIDENTIFIER) AS AssetPublicId,
               CAST(NULL AS TINYINT) AS StorageStatus,
               CAST(NULL AS TINYINT) AS ScanStatus,
               CAST(NULL AS TINYINT) AS ScanProvider,
               CAST(NULL AS BINARY(8)) AS RowVersion,
               CAST(NULL AS BINARY(8)) AS ProjectRowVersion,
               CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_RejectProjectAsset;

    BEGIN TRY
        SELECT @IntentId = intents.Id,
               @Status = intents.Status,
               @StoredLeaseId = intents.FinalizeLeaseId,
               @StoredErrorCode = intents.LastErrorCode
        FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id
           AND memberships.Role = 1 AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
            ON users.Id = memberships.UserId AND users.Status = 2
        INNER JOIN dbo.FundingPlatform_Projects AS projects WITH (UPDLOCK, HOLDLOCK)
            ON projects.OrganizationId = organizations.Id AND projects.IsActive = 1
        INNER JOIN dbo.FundingPlatform_ProjectAssetUploadIntents AS intents
            WITH (UPDLOCK, HOLDLOCK) ON intents.ProjectId = projects.Id
        WHERE organizations.PublicId = @OrganizationPublicId
          AND organizations.IsActive = 1
          AND projects.PublicId = @ProjectPublicId
          AND users.PublicId = @UserPublicId
          AND intents.PublicId = @IntentPublicId;

        IF @IntentId IS NULL
            SET @Code = N'not-found';
        ELSE IF @Status = 2
        BEGIN
            SET @Succeeded = 1;
            SET @Code = N'completed';
            SET @WasReplay = 1;
        END
        ELSE IF @Status = 4 AND @StoredErrorCode = @ErrorCode
        BEGIN
            SET @Succeeded = 1;
            SET @Code = N'rejected';
            SET @WasReplay = 1;
        END
        ELSE IF @Status = 1 AND @StoredLeaseId = @LeaseId
        BEGIN
            UPDATE dbo.FundingPlatform_ProjectAssetUploadIntents
            SET Status = 4,
                FinalizeLeaseId = NULL,
                FinalizeLeaseUntilUtc = NULL,
                LastErrorCode = @ErrorCode,
                UpdatedAtUtc = @NowUtc
            WHERE Id = @IntentId;
            SET @Status = 4;
            SET @Succeeded = 1;
            SET @Code = N'rejected';

            INSERT INTO dbo.FundingPlatform_OutboxMessages
                (MessageType, AggregateType, AggregateId, PayloadJson,
                 OccurredAtUtc, AvailableAtUtc)
            SELECT N'ProjectAssetUploadIntentRejected', N'ProjectAssetUploadIntent',
                   CONVERT(NVARCHAR(100), @IntentPublicId),
                   (SELECT @IntentPublicId AS intentPublicId,
                           @ProjectPublicId AS projectPublicId,
                           CAST(4 AS TINYINT) AS status, @ErrorCode AS errorCode
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                   @NowUtc, @NowUtc;
        END
        ELSE SET @Code = N'lease-conflict';

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        SELECT @Succeeded AS Succeeded, @Code AS Code,
               intents.PublicId AS IntentPublicId, intents.Status,
               assets.PublicId AS AssetPublicId,
               assets.StorageStatus, assets.ScanStatus, assets.ScanProvider,
               intents.RowVersion, projects.RowVersion AS ProjectRowVersion,
               @WasReplay AS WasReplay
        FROM dbo.FundingPlatform_ProjectAssetUploadIntents AS intents
        INNER JOIN dbo.FundingPlatform_Projects AS projects ON projects.Id = intents.ProjectId
        LEFT JOIN dbo.FundingPlatform_ProjectAssets AS assets
            ON assets.Id = intents.CompletedProjectAssetId
        WHERE intents.Id = @IntentId
        UNION ALL
        SELECT @Succeeded, @Code, @IntentPublicId, NULL, NULL, NULL, NULL, NULL,
               NULL, NULL, @WasReplay
        WHERE @IntentId IS NULL;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_RejectProjectAsset;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Get
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER,
    @IntentPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_Organizations AS organizations
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
            ON memberships.OrganizationId = organizations.Id
           AND memberships.Role = 1 AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users
            ON users.Id = memberships.UserId AND users.Status = 2
        INNER JOIN dbo.FundingPlatform_Projects AS projects
            ON projects.OrganizationId = organizations.Id AND projects.IsActive = 1
        INNER JOIN dbo.FundingPlatform_ProjectAssetUploadIntents AS intents
            ON intents.ProjectId = projects.Id
        WHERE organizations.PublicId = @OrganizationPublicId
          AND organizations.IsActive = 1
          AND projects.PublicId = @ProjectPublicId
          AND users.PublicId = @UserPublicId
          AND intents.PublicId = @IntentPublicId
    )
        THROW 55603, N'Project asset upload intent was not found.', 1;

    SELECT intents.PublicId AS IntentPublicId,
           projects.PublicId AS ProjectPublicId,
           intents.Kind,
           intents.OriginalFileName,
           intents.DeclaredMimeType,
           intents.ExpectedContentLength,
           intents.MaxContentLength,
           CASE WHEN intents.Status IN (0, 1) AND intents.ExpiresAtUtc <= SYSUTCDATETIME()
                THEN CAST(3 AS TINYINT) ELSE intents.Status END AS Status,
           intents.ExpiresAtUtc,
           assets.PublicId AS AssetPublicId,
           assets.StorageStatus,
           assets.ScanStatus,
           assets.ScanProvider,
           assets.ScanResultCode,
           intents.FinalizeAttemptCount,
           intents.CreatedAtUtc,
           intents.CompletedAtUtc,
           intents.UpdatedAtUtc,
           intents.RowVersion
    FROM dbo.FundingPlatform_ProjectAssetUploadIntents AS intents
    INNER JOIN dbo.FundingPlatform_Projects AS projects ON projects.Id = intents.ProjectId
    LEFT JOIN dbo.FundingPlatform_ProjectAssets AS assets
        ON assets.Id = intents.CompletedProjectAssetId
    WHERE intents.PublicId = @IntentPublicId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAssetUploadIntent_AcquireFinalize
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER,
    @IntentPublicId UNIQUEIDENTIFIER,
    @CompletionTokenHash BINARY(32),
    @LeaseId UNIQUEIDENTIFIER,
    @LeaseUntilUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @ProjectId BIGINT;
    DECLARE @IntentId BIGINT;
    DECLARE @Status TINYINT;
    DECLARE @StoredTokenHash BINARY(32);
    DECLARE @ExpiresAtUtc DATETIME2(3);
    DECLARE @StoredLeaseId UNIQUEIDENTIFIER;
    DECLARE @StoredLeaseUntilUtc DATETIME2(3);
    DECLARE @EffectiveLeaseUntilUtc DATETIME2(3);
    DECLARE @FinalizeAttemptCount SMALLINT;
    DECLARE @AssetId BIGINT;
    DECLARE @AssetIsDeleted BIT;
    DECLARE @Code NVARCHAR(50) = N'invalid-token';
    DECLARE @Succeeded BIT = 0;
    DECLARE @WasReplay BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @CompletionTokenHash IS NULL OR @LeaseId IS NULL
       OR @LeaseUntilUtc <= @NowUtc
       OR @LeaseUntilUtc > DATEADD(MINUTE, 5, @NowUtc)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-asset' AS Code,
               CAST(NULL AS UNIQUEIDENTIFIER) AS IntentPublicId,
               CAST(NULL AS UNIQUEIDENTIFIER) AS ProjectPublicId,
               CAST(NULL AS TINYINT) AS Kind,
               CAST(NULL AS NVARCHAR(260)) AS OriginalFileName,
               CAST(NULL AS NVARCHAR(100)) AS DeclaredMimeType,
               CAST(NULL AS NVARCHAR(100)) AS VerifiedMimeType,
               CAST(NULL AS BIGINT) AS ExpectedContentLength,
               CAST(NULL AS BIGINT) AS MaxContentLength,
               CAST(NULL AS BIGINT) AS ActualContentLength,
               CAST(NULL AS BINARY(32)) AS ContentHash,
               CAST(NULL AS INT) AS PixelWidth,
               CAST(NULL AS INT) AS PixelHeight,
               CAST(NULL AS NVARCHAR(63)) AS IncomingBlobContainer,
               CAST(NULL AS NVARCHAR(1024)) AS IncomingBlobObjectName,
               CAST(NULL AS NVARCHAR(63)) AS QuarantineBlobContainer,
               CAST(NULL AS NVARCHAR(1024)) AS QuarantineBlobObjectName,
               CAST(NULL AS NVARCHAR(63)) AS TrustedBlobContainer,
               CAST(NULL AS NVARCHAR(1024)) AS TrustedBlobObjectName,
               CAST(NULL AS NVARCHAR(100)) AS QuarantineBlobETag,
               CAST(NULL AS NVARCHAR(200)) AS QuarantineBlobVersionId,
               CAST(NULL AS TINYINT) AS Status,
               CAST(NULL AS DATETIME2(3)) AS ExpiresAtUtc,
               CAST(NULL AS UNIQUEIDENTIFIER) AS AssetPublicId,
               CAST(NULL AS TINYINT) AS StorageStatus,
               CAST(NULL AS TINYINT) AS ScanStatus,
               CAST(NULL AS TINYINT) AS ScanProvider,
               CAST(NULL AS UNIQUEIDENTIFIER) AS FinalizeLeaseId,
               CAST(NULL AS DATETIME2(3)) AS FinalizeLeaseUntilUtc,
               CAST(NULL AS BINARY(8)) AS AssetRowVersion,
               CAST(NULL AS BINARY(8)) AS RowVersion,
               CAST(NULL AS BINARY(8)) AS ProjectRowVersion,
               CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_AcquireProjectAsset;

    BEGIN TRY
        SELECT @ProjectId = projects.Id,
               @IntentId = intents.Id,
               @Status = intents.Status,
               @StoredTokenHash = intents.CompletionTokenHash,
               @ExpiresAtUtc = intents.ExpiresAtUtc,
               @StoredLeaseId = intents.FinalizeLeaseId,
               @StoredLeaseUntilUtc = intents.FinalizeLeaseUntilUtc,
               @FinalizeAttemptCount = intents.FinalizeAttemptCount,
               @AssetId = intents.CompletedProjectAssetId,
               @AssetIsDeleted = assets.IsDeleted
        FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id
           AND memberships.Role = 1 AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
            ON users.Id = memberships.UserId AND users.Status = 2
        INNER JOIN dbo.FundingPlatform_Projects AS projects WITH (UPDLOCK, HOLDLOCK)
            ON projects.OrganizationId = organizations.Id AND projects.IsActive = 1
        INNER JOIN dbo.FundingPlatform_ProjectAssetUploadIntents AS intents
            WITH (UPDLOCK, HOLDLOCK) ON intents.ProjectId = projects.Id
        LEFT JOIN dbo.FundingPlatform_ProjectAssets AS assets WITH (UPDLOCK, HOLDLOCK)
            ON assets.Id = intents.CompletedProjectAssetId
           AND assets.ProjectId = intents.ProjectId
        WHERE organizations.PublicId = @OrganizationPublicId
          AND organizations.IsActive = 1
          AND projects.PublicId = @ProjectPublicId
          AND users.PublicId = @UserPublicId
          AND intents.PublicId = @IntentPublicId;

        IF @IntentId IS NULL OR @StoredTokenHash <> @CompletionTokenHash
            SET @Code = N'invalid-token';
        ELSE IF @Status = 2 AND COALESCE(@AssetIsDeleted, 1) = 1
            SET @Code = N'asset-deleted';
        ELSE IF @Status = 2
        BEGIN
            SET @Succeeded = 1;
            SET @Code = N'completed';
            SET @WasReplay = 1;
        END
        ELSE IF @Status = 4
            SET @Code = N'rejected';
        ELSE IF @Status = 3 OR @ExpiresAtUtc <= @NowUtc
        BEGIN
            IF @Status IN (0, 1)
            BEGIN
                UPDATE dbo.FundingPlatform_ProjectAssetUploadIntents
                SET Status = 3,
                    FinalizeLeaseId = NULL,
                    FinalizeLeaseUntilUtc = NULL,
                    LastErrorCode = N'expired',
                    UpdatedAtUtc = @NowUtc
                WHERE Id = @IntentId;
                SET @Status = 3;
            END;
            SET @Code = N'expired';
        END
        ELSE IF @Status = 1 AND @StoredLeaseUntilUtc > @NowUtc
        BEGIN
            IF @StoredLeaseId = @LeaseId
            BEGIN
                SET @Succeeded = 1;
                SET @Code = N'finalizing';
                SET @WasReplay = 1;
            END
            ELSE SET @Code = N'finalize-busy';
        END
        ELSE IF @Status IN (0, 1) AND @FinalizeAttemptCount >= 100
            SET @Code = N'finalize-limit-reached';
        ELSE IF @Status IN (0, 1)
        BEGIN
            SET @EffectiveLeaseUntilUtc =
                CASE WHEN @LeaseUntilUtc > @ExpiresAtUtc
                     THEN @ExpiresAtUtc ELSE @LeaseUntilUtc END;
            UPDATE dbo.FundingPlatform_ProjectAssetUploadIntents
            SET Status = 1,
                FinalizeAttemptCount = FinalizeAttemptCount + 1,
                FinalizeLeaseId = @LeaseId,
                FinalizeLeaseUntilUtc = @EffectiveLeaseUntilUtc,
                LastErrorCode = NULL,
                UpdatedAtUtc = @NowUtc
            WHERE Id = @IntentId;
            SET @Status = 1;
            SET @StoredLeaseId = @LeaseId;
            SET @Succeeded = 1;
            SET @Code = N'acquired';
        END
        ELSE SET @Code = N'invalid-state';

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        IF @IntentId IS NULL OR @StoredTokenHash <> @CompletionTokenHash
        BEGIN
            SELECT @Succeeded AS Succeeded, @Code AS Code,
                   CAST(NULL AS UNIQUEIDENTIFIER) AS IntentPublicId,
                   CAST(NULL AS UNIQUEIDENTIFIER) AS ProjectPublicId,
                   CAST(NULL AS TINYINT) AS Kind,
                   CAST(NULL AS NVARCHAR(260)) AS OriginalFileName,
                   CAST(NULL AS NVARCHAR(100)) AS DeclaredMimeType,
                   CAST(NULL AS NVARCHAR(100)) AS VerifiedMimeType,
                   CAST(NULL AS BIGINT) AS ExpectedContentLength,
                   CAST(NULL AS BIGINT) AS MaxContentLength,
                   CAST(NULL AS BIGINT) AS ActualContentLength,
                   CAST(NULL AS BINARY(32)) AS ContentHash,
                   CAST(NULL AS INT) AS PixelWidth,
                   CAST(NULL AS INT) AS PixelHeight,
                   CAST(NULL AS NVARCHAR(63)) AS IncomingBlobContainer,
                   CAST(NULL AS NVARCHAR(1024)) AS IncomingBlobObjectName,
                   CAST(NULL AS NVARCHAR(63)) AS QuarantineBlobContainer,
                   CAST(NULL AS NVARCHAR(1024)) AS QuarantineBlobObjectName,
                   CAST(NULL AS NVARCHAR(63)) AS TrustedBlobContainer,
                   CAST(NULL AS NVARCHAR(1024)) AS TrustedBlobObjectName,
                   CAST(NULL AS NVARCHAR(100)) AS QuarantineBlobETag,
                   CAST(NULL AS NVARCHAR(200)) AS QuarantineBlobVersionId,
                   CAST(NULL AS TINYINT) AS Status,
                   CAST(NULL AS DATETIME2(3)) AS ExpiresAtUtc,
                   CAST(NULL AS UNIQUEIDENTIFIER) AS AssetPublicId,
                   CAST(NULL AS TINYINT) AS StorageStatus,
                   CAST(NULL AS TINYINT) AS ScanStatus,
                   CAST(NULL AS TINYINT) AS ScanProvider,
                   CAST(NULL AS UNIQUEIDENTIFIER) AS FinalizeLeaseId,
                   CAST(NULL AS DATETIME2(3)) AS FinalizeLeaseUntilUtc,
                   CAST(NULL AS BINARY(8)) AS AssetRowVersion,
                   CAST(NULL AS BINARY(8)) AS RowVersion,
                   CAST(NULL AS BINARY(8)) AS ProjectRowVersion,
                   @WasReplay AS WasReplay;
            RETURN;
        END;

        SELECT @Succeeded AS Succeeded,
               @Code AS Code,
               intents.PublicId AS IntentPublicId,
               projects.PublicId AS ProjectPublicId,
               intents.Kind,
               intents.OriginalFileName,
               intents.DeclaredMimeType,
               assets.VerifiedMimeType,
               intents.ExpectedContentLength,
               intents.MaxContentLength,
               assets.ContentLength AS ActualContentLength,
               assets.ContentHash,
               assets.PixelWidth,
               assets.PixelHeight,
               CASE WHEN @Succeeded = 1 AND @Code IN (N'acquired', N'finalizing', N'completed')
                    THEN intents.IncomingBlobContainer END AS IncomingBlobContainer,
               CASE WHEN @Succeeded = 1 AND @Code IN (N'acquired', N'finalizing', N'completed')
                    THEN intents.IncomingBlobObjectName END AS IncomingBlobObjectName,
               CASE WHEN @Succeeded = 1 AND @Code IN (N'acquired', N'finalizing', N'completed')
                    THEN intents.QuarantineBlobContainer END AS QuarantineBlobContainer,
               CASE WHEN @Succeeded = 1 AND @Code IN (N'acquired', N'finalizing', N'completed')
                    THEN intents.QuarantineBlobObjectName END AS QuarantineBlobObjectName,
               CASE WHEN @Succeeded = 1 AND @Code IN (N'acquired', N'finalizing', N'completed')
                    THEN intents.TrustedBlobContainer END AS TrustedBlobContainer,
               CASE WHEN @Succeeded = 1 AND @Code IN (N'acquired', N'finalizing', N'completed')
                    THEN intents.TrustedBlobObjectName END AS TrustedBlobObjectName,
               assets.QuarantineBlobETag,
               assets.QuarantineBlobVersionId,
               intents.Status,
               intents.ExpiresAtUtc,
               assets.PublicId AS AssetPublicId,
               assets.StorageStatus,
               assets.ScanStatus,
               assets.ScanProvider,
               CASE WHEN @Succeeded = 1 AND @Code IN (N'acquired', N'finalizing')
                    THEN intents.FinalizeLeaseId END AS FinalizeLeaseId,
               CASE WHEN @Succeeded = 1 AND @Code IN (N'acquired', N'finalizing')
                    THEN intents.FinalizeLeaseUntilUtc END AS FinalizeLeaseUntilUtc,
               assets.RowVersion AS AssetRowVersion,
               intents.RowVersion,
               projects.RowVersion AS ProjectRowVersion,
               @WasReplay AS WasReplay
        FROM dbo.FundingPlatform_ProjectAssetUploadIntents AS intents
        INNER JOIN dbo.FundingPlatform_Projects AS projects ON projects.Id = intents.ProjectId
        LEFT JOIN dbo.FundingPlatform_ProjectAssets AS assets
            ON assets.Id = intents.CompletedProjectAssetId AND assets.IsDeleted = 0
        WHERE intents.Id = @IntentId;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_AcquireProjectAsset;
        THROW;
    END CATCH;
END;
GO

IF DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole') IS NULL
   OR DATABASE_PRINCIPAL_ID(N'FundingPlatform_GeneralWorkerRole') IS NULL
    THROW 55606, N'Project assets require the runtime roles from migration 027.', 1;

GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Create
    TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Get
    TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAssetUploadIntent_AcquireFinalize
    TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAssetUploadIntent_ReleaseFinalize
    TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAssetUploadIntent_RejectFinalize
    TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAssetUploadIntent_Complete
    TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAsset_MarkQuarantined
    TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAsset_List
    TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAsset_UpdateMetadata
    TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAsset_Reorder
    TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAsset_Delete
    TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAsset_GetTrustedContent
    TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
    TO FundingPlatform_ApiRuntimeRole;

GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
    TO FundingPlatform_GeneralWorkerRole;

GRANT EXECUTE, REFERENCES ON TYPE::dbo.FundingPlatform_ProjectAssetOrderList
    TO FundingPlatform_ApiRuntimeRole;

IF EXISTS
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
    THROW 55607, N'API runtime role must not have direct project asset table access.', 1;

IF (SELECT COUNT_BIG(1)
    FROM sys.database_permissions
    WHERE grantee_principal_id =
          DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole')) <> 162
   OR (SELECT COUNT_BIG(1)
       FROM sys.database_permissions
       WHERE grantee_principal_id =
             DATABASE_PRINCIPAL_ID(N'FundingPlatform_GeneralWorkerRole')) <> 50
    THROW 55608, N'Runtime role permissions do not match the project asset allowlist.', 1;
GO
