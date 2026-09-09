/* Project-asset exact-manifest retention. Requires migrations 001-038.
   BlobKind: 0 quarantine, 1 trusted. SourceKind: 0 asset quarantine,
   1 deleted asset trusted, 2 revoked scan-event trusted.
   Status: 0 pending, 1 leased, 2 logically unavailable, 3 failed.
   Incoming uploads and orphan promotions WITHOUT a persisted receipt are excluded.
   Azure soft delete/lifecycle determines when unavailable bytes are physically purged. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF COL_LENGTH(N'dbo.FundingPlatform_ProjectAssets', N'TrustedContentHash') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_ProjectAssetScanEvents', N'RevokedTrustedContentHash') IS NULL
   OR DATABASE_PRINCIPAL_ID(N'FundingPlatform_GeneralWorkerRole') IS NULL
    THROW 55901, N'Project asset retention requires migrations 001-038.', 1;

CREATE TABLE dbo.FundingPlatform_ProjectAssetContentRetentionTasks
(
    Id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT FundingPlatform_PK_ProjectAssetRetention PRIMARY KEY,
    PublicId UNIQUEIDENTIFIER NOT NULL CONSTRAINT FundingPlatform_DF_ProjectAssetRetention_PublicId DEFAULT (NEWSEQUENTIALID()) CONSTRAINT FundingPlatform_UQ_ProjectAssetRetention_PublicId UNIQUE,
    SourceKind TINYINT NOT NULL,
    SourceId BIGINT NOT NULL,
    ProjectAssetPublicId UNIQUEIDENTIFIER NOT NULL,
    BlobKind TINYINT NOT NULL,
    BlobContainer NVARCHAR(63) COLLATE Latin1_General_100_BIN2 NOT NULL,
    BlobObjectName NVARCHAR(1024) COLLATE Latin1_General_100_BIN2 NOT NULL,
    BlobETag NVARCHAR(100) COLLATE Latin1_General_100_BIN2 NOT NULL,
    BlobVersionId NVARCHAR(200) COLLATE Latin1_General_100_BIN2 NULL,
    MimeType NVARCHAR(100) NOT NULL,
    ContentLength BIGINT NOT NULL,
    ContentHash BINARY(32) NOT NULL,
    SourceContentHash BINARY(32) NULL,
    ManifestProcessingVersion NVARCHAR(100) NULL,
    IdentityHash BINARY(32) NOT NULL,
    RetentionUntilUtc DATETIME2(3) NOT NULL,
    Status TINYINT NOT NULL CONSTRAINT FundingPlatform_DF_ProjectAssetRetention_Status DEFAULT (0),
    AttemptCount SMALLINT NOT NULL CONSTRAINT FundingPlatform_DF_ProjectAssetRetention_AttemptCount DEFAULT (0),
    MaxAttempts SMALLINT NOT NULL CONSTRAINT FundingPlatform_DF_ProjectAssetRetention_MaxAttempts DEFAULT (8),
    LeaseId UNIQUEIDENTIFIER NULL,
    LeaseUntilUtc DATETIME2(3) NULL,
    NextAttemptAtUtc DATETIME2(3) NULL,
    ContentDeletedAtUtc DATETIME2(3) NULL,
    LastErrorCode NVARCHAR(100) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_UQ_ProjectAssetRetention_Source UNIQUE (SourceKind, SourceId),
    CONSTRAINT FundingPlatform_CK_ProjectAssetRetention_Kind CHECK
        ((SourceKind = 0 AND BlobKind = 0) OR (SourceKind IN (1, 2) AND BlobKind = 1)),
    CONSTRAINT FundingPlatform_CK_ProjectAssetRetention_Manifest CHECK
        (SourceId > 0 AND LEN(BlobContainer) BETWEEN 3 AND 63
         AND LEN(BlobObjectName) BETWEEN 73 AND 74
         AND LEFT(BlobETag, 1) = N'"' AND RIGHT(BlobETag, 1) = N'"'
         AND LEN(BlobETag) BETWEEN 3 AND 100
         AND CHARINDEX(CHAR(10), BlobETag) = 0 AND CHARINDEX(CHAR(13), BlobETag) = 0
         AND ((MimeType IN (N'image/jpeg', N'image/png', N'image/webp')
               AND ContentLength BETWEEN 1 AND 10485760)
              OR (MimeType = N'application/pdf' AND ContentLength BETWEEN 1 AND 26214400))
         AND ((BlobKind = 0 AND SourceContentHash IS NULL AND ManifestProcessingVersion IS NULL)
              OR (BlobKind = 1 AND SourceContentHash IS NOT NULL
                  AND ManifestProcessingVersion IS NOT NULL
                  AND ManifestProcessingVersion IN
                      (N'pdf-copy-v1', N'legacy-unsanitized-v0', N'skia-4.151.2-image-v1')))),
    CONSTRAINT FundingPlatform_CK_ProjectAssetRetention_State CHECK
        (Status BETWEEN 0 AND 3 AND MaxAttempts = 8
         AND AttemptCount BETWEEN 0 AND MaxAttempts
         AND ((Status = 1 AND LeaseId IS NOT NULL AND LeaseUntilUtc IS NOT NULL)
              OR (Status <> 1 AND LeaseUntilUtc IS NULL))
         AND ((Status = 0 AND NextAttemptAtUtc IS NOT NULL) OR
              (Status <> 0 AND NextAttemptAtUtc IS NULL))
         AND ((Status = 2 AND ContentDeletedAtUtc IS NOT NULL) OR
              (Status <> 2 AND ContentDeletedAtUtc IS NULL))
         AND (Status <> 3 OR LastErrorCode IS NOT NULL)
         AND UpdatedAtUtc >= CreatedAtUtc)
);
CREATE INDEX FundingPlatform_IX_ProjectAssetRetention_Queue
    ON dbo.FundingPlatform_ProjectAssetContentRetentionTasks
       (Status, NextAttemptAtUtc, LeaseUntilUtc, Id);
CREATE TABLE dbo.FundingPlatform_ProjectAssetContentRetentionAttempts
(
    TaskId BIGINT NOT NULL,
    AttemptCount SMALLINT NOT NULL,
    LeaseId UNIQUEIDENTIFIER NOT NULL,
    ClaimedAtUtc DATETIME2(3) NOT NULL,
    FinishedAtUtc DATETIME2(3) NULL,
    OutcomeCode NVARCHAR(100) NULL,
    CONSTRAINT FundingPlatform_PK_ProjectAssetRetentionAttempts PRIMARY KEY (TaskId, AttemptCount),
    CONSTRAINT FundingPlatform_FK_ProjectAssetRetentionAttempts_Task FOREIGN KEY (TaskId) REFERENCES dbo.FundingPlatform_ProjectAssetContentRetentionTasks (Id)
);
GO

CREATE OR ALTER VIEW dbo.FundingPlatform_vw_ProjectAssetRetentionCandidates
AS
WITH Manifests AS
(
    SELECT CAST(0 AS TINYINT) AS SourceKind, assets.Id AS SourceId,
           assets.PublicId AS ProjectAssetPublicId, CAST(0 AS TINYINT) AS BlobKind,
           assets.QuarantineBlobContainer AS BlobContainer,
           assets.QuarantineBlobObjectName AS BlobObjectName,
           assets.QuarantineBlobETag AS BlobETag,
           assets.QuarantineBlobVersionId AS BlobVersionId,
           LOWER(assets.VerifiedMimeType) AS MimeType, assets.ContentLength, assets.ContentHash,
           CAST(NULL AS BINARY(32)) AS SourceContentHash,
           CAST(NULL AS NVARCHAR(100)) AS ManifestProcessingVersion,
           DATEADD(HOUR, 24, CASE WHEN assets.IsDeleted = 1 THEN assets.DeletedAtUtc
                                 ELSE assets.ScanCompletedAtUtc END) AS RetentionUntilUtc
    FROM dbo.FundingPlatform_ProjectAssets AS assets
    WHERE assets.QuarantineBlobETag IS NOT NULL
      AND (assets.IsDeleted = 1 OR (assets.StorageStatus = 3 AND assets.ScanStatus IN (2, 3, 4)))
    UNION ALL
    SELECT 1, assets.Id, assets.PublicId, 1,
           assets.TrustedBlobContainer, assets.TrustedBlobObjectName,
           assets.TrustedBlobETag, assets.TrustedBlobVersionId,
           assets.TrustedMimeType, assets.TrustedContentLength, assets.TrustedContentHash,
           assets.ContentHash, assets.TrustedProcessingVersion,
           DATEADD(HOUR, 24, assets.DeletedAtUtc)
    FROM dbo.FundingPlatform_ProjectAssets AS assets
    WHERE assets.IsDeleted = 1 AND assets.StorageStatus = 2 AND assets.ScanStatus = 1
    UNION ALL
    SELECT 2, events.Id, assets.PublicId, 1,
           events.RevokedTrustedBlobContainer, events.RevokedTrustedBlobObjectName,
           events.RevokedTrustedBlobETag, events.RevokedTrustedBlobVersionId,
           events.RevokedTrustedMimeType, events.RevokedTrustedContentLength,
           events.RevokedTrustedContentHash, assets.ContentHash,
           events.RevokedTrustedProcessingVersion, events.CreatedAtUtc
    FROM dbo.FundingPlatform_ProjectAssetScanEvents AS events
    INNER JOIN dbo.FundingPlatform_ProjectAssets AS assets ON assets.Id = events.ProjectAssetId
    WHERE events.FromStatus = 1 AND events.ToStatus IN (2, 3, 4)
)
SELECT manifests.*,
       CONVERT(BINARY(32), HASHBYTES('SHA2_256', CONVERT(NVARCHAR(MAX),
           (SELECT manifests.BlobKind AS kind, manifests.BlobContainer AS container,
                   manifests.BlobObjectName AS objectName, manifests.BlobETag AS etag,
                   manifests.BlobVersionId AS versionId, manifests.MimeType AS mime,
                   manifests.ContentLength AS length, manifests.ContentHash AS hash,
                   manifests.SourceContentHash AS sourceHash,
                   manifests.ManifestProcessingVersion AS processingVersion
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES)))) AS IdentityHash
FROM Manifests AS manifests
WHERE manifests.BlobETag IS NOT NULL AND manifests.ContentHash IS NOT NULL
  AND manifests.MimeType IS NOT NULL AND manifests.ContentLength IS NOT NULL
  AND manifests.RetentionUntilUtc IS NOT NULL
  /* Keep both current trust and its quarantine evidence available for late Defender results. */
  AND NOT EXISTS
      (SELECT 1 FROM dbo.FundingPlatform_ProjectAssets AS active
       WHERE active.IsDeleted = 0
         AND ((active.TrustedBlobContainer COLLATE Latin1_General_100_BIN2 = manifests.BlobContainer
               AND active.TrustedBlobObjectName COLLATE Latin1_General_100_BIN2 = manifests.BlobObjectName)
              OR (active.StorageStatus IN (0, 1, 2)
                  AND active.QuarantineBlobContainer COLLATE Latin1_General_100_BIN2 = manifests.BlobContainer
                  AND active.QuarantineBlobObjectName COLLATE Latin1_General_100_BIN2 = manifests.BlobObjectName)));
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_ProjectAssetRetention_Immutable
ON dbo.FundingPlatform_ProjectAssetContentRetentionTasks
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS
       (SELECT Id, PublicId, SourceKind, SourceId, ProjectAssetPublicId, BlobKind,
               BlobContainer, BlobObjectName, BlobETag, BlobVersionId,
               MimeType, ContentLength, ContentHash, SourceContentHash,
               ManifestProcessingVersion, IdentityHash, RetentionUntilUtc, MaxAttempts, CreatedAtUtc
        FROM deleted
        EXCEPT
        SELECT Id, PublicId, SourceKind, SourceId, ProjectAssetPublicId, BlobKind,
               BlobContainer, BlobObjectName, BlobETag, BlobVersionId,
               MimeType, ContentLength, ContentHash, SourceContentHash,
               ManifestProcessingVersion, IdentityHash, RetentionUntilUtc, MaxAttempts, CreatedAtUtc
        FROM inserted)
       OR EXISTS (SELECT 1 FROM deleted AS d JOIN inserted AS i ON i.Id = d.Id
                  WHERE d.Status IN (2, 3) AND i.Status <> d.Status)
        THROW 55902, N'Retention identity and terminal states are immutable.', 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAssetContentRetention_Claim
    @BatchSize INT,
    @LeaseId UNIQUEIDENTIFIER,
    @LeaseSeconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @BatchSize IS NULL OR @BatchSize NOT BETWEEN 1 AND 100
       OR @LeaseId IS NULL OR @LeaseId = '00000000-0000-0000-0000-000000000000'
       OR @LeaseSeconds IS NULL OR @LeaseSeconds NOT BETWEEN 30 AND 3600
       OR @NowUtc IS NULL OR ABS(DATEDIFF_BIG(SECOND, @NowUtc, SYSUTCDATETIME())) > 300
        THROW 55903, N'Invalid retention batch, lease or clock.', 1;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @Claimed TABLE (Id BIGINT PRIMARY KEY);
    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_RetentionClaim039;
    BEGIN TRY
        DECLARE @LockResult INT;
        EXEC @LockResult = sys.sp_getapplock
            @Resource = N'FundingPlatform:ProjectAssetRetention', @LockMode = N'Exclusive',
            @LockOwner = N'Transaction', @LockTimeout = 10000;
        IF @LockResult < 0 THROW 55904, N'Retention claim lock unavailable.', 1;

        INSERT INTO dbo.FundingPlatform_ProjectAssetContentRetentionTasks
            (SourceKind, SourceId, ProjectAssetPublicId, BlobKind, BlobContainer, BlobObjectName,
             BlobETag, BlobVersionId, MimeType, ContentLength, ContentHash, SourceContentHash,
             ManifestProcessingVersion, IdentityHash, RetentionUntilUtc, NextAttemptAtUtc,
             CreatedAtUtc, UpdatedAtUtc)
        SELECT TOP (@BatchSize) candidates.SourceKind, candidates.SourceId,
               candidates.ProjectAssetPublicId, candidates.BlobKind, candidates.BlobContainer,
               candidates.BlobObjectName, candidates.BlobETag, candidates.BlobVersionId,
               candidates.MimeType, candidates.ContentLength, candidates.ContentHash,
               candidates.SourceContentHash, candidates.ManifestProcessingVersion,
               candidates.IdentityHash, candidates.RetentionUntilUtc, @NowUtc, @NowUtc, @NowUtc
        FROM dbo.FundingPlatform_vw_ProjectAssetRetentionCandidates AS candidates
        WHERE candidates.RetentionUntilUtc <= @NowUtc
          AND NOT EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_ProjectAssetContentRetentionTasks AS tasks
               WHERE tasks.SourceKind = candidates.SourceKind AND tasks.SourceId = candidates.SourceId)
        ORDER BY candidates.RetentionUntilUtc, candidates.SourceKind, candidates.SourceId;

        UPDATE attempts SET FinishedAtUtc = @NowUtc, OutcomeCode = N'lease-expired'
        FROM dbo.FundingPlatform_ProjectAssetContentRetentionAttempts AS attempts
        INNER JOIN dbo.FundingPlatform_ProjectAssetContentRetentionTasks AS tasks
            ON tasks.Id = attempts.TaskId AND tasks.AttemptCount = attempts.AttemptCount
        WHERE tasks.Status = 1 AND tasks.LeaseUntilUtc <= @NowUtc
          AND attempts.FinishedAtUtc IS NULL;

        UPDATE dbo.FundingPlatform_ProjectAssetContentRetentionTasks
        SET Status = 3, LeaseUntilUtc = NULL, NextAttemptAtUtc = NULL,
            LastErrorCode = N'retries-exhausted', UpdatedAtUtc = @NowUtc
        WHERE ((Status = 1 AND LeaseUntilUtc <= @NowUtc) OR
               (Status = 0 AND NextAttemptAtUtc <= @NowUtc)) AND AttemptCount >= MaxAttempts;

        ;WITH Due AS
        (
            SELECT TOP (@BatchSize) tasks.*
            FROM dbo.FundingPlatform_ProjectAssetContentRetentionTasks AS tasks WITH (UPDLOCK, HOLDLOCK)
            WHERE ((tasks.Status = 0 AND tasks.NextAttemptAtUtc <= @NowUtc)
                    OR (tasks.Status = 1 AND tasks.LeaseUntilUtc <= @NowUtc))
              AND tasks.AttemptCount < tasks.MaxAttempts
              /* Revalidate source eligibility AND the exact persisted manifest on every lease. */
              AND EXISTS
                  (SELECT 1 FROM dbo.FundingPlatform_vw_ProjectAssetRetentionCandidates AS candidates
                   WHERE candidates.SourceKind = tasks.SourceKind AND candidates.SourceId = tasks.SourceId
                     AND candidates.IdentityHash = tasks.IdentityHash
                     AND candidates.RetentionUntilUtc <= @NowUtc)
            ORDER BY tasks.RetentionUntilUtc, tasks.Id
        )
        UPDATE Due SET Status = 1, AttemptCount = AttemptCount + 1,
            LeaseId = @LeaseId, LeaseUntilUtc = DATEADD(SECOND, @LeaseSeconds, @NowUtc),
            NextAttemptAtUtc = NULL, LastErrorCode = NULL, UpdatedAtUtc = @NowUtc
        OUTPUT inserted.Id INTO @Claimed;

        INSERT INTO dbo.FundingPlatform_ProjectAssetContentRetentionAttempts
            (TaskId, AttemptCount, LeaseId, ClaimedAtUtc)
        SELECT tasks.Id, tasks.AttemptCount, @LeaseId, @NowUtc
        FROM dbo.FundingPlatform_ProjectAssetContentRetentionTasks AS tasks
        INNER JOIN @Claimed AS claimed ON claimed.Id = tasks.Id;

        /* Terminal assets cannot regain trust. Close accepted receipts before evidence deletion
           so their deliveries do not endlessly retry a blob intentionally made unavailable. */
        UPDATE receipts SET ReceiptStatus = 2, OutcomeCode = N'asset-retention-ignored',
            FinalizedAtUtc = CASE WHEN ReceivedAtUtc > @NowUtc THEN ReceivedAtUtc ELSE @NowUtc END
        FROM dbo.FundingPlatform_ProjectAssetDefenderReceipts AS receipts
        INNER JOIN dbo.FundingPlatform_ProjectAssets AS assets ON assets.Id = receipts.ProjectAssetId
        INNER JOIN dbo.FundingPlatform_ProjectAssetContentRetentionTasks AS tasks
            ON tasks.ProjectAssetPublicId = assets.PublicId AND tasks.BlobKind = 0
        INNER JOIN @Claimed AS claimed ON claimed.Id = tasks.Id
        WHERE receipts.ReceiptStatus = 0;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION FP_RetentionClaim039;
        THROW;
    END CATCH;
    SELECT tasks.PublicId AS TaskPublicId, tasks.ProjectAssetPublicId, tasks.BlobKind,
           tasks.BlobContainer, tasks.BlobObjectName, tasks.BlobETag, tasks.BlobVersionId,
           tasks.MimeType, tasks.ContentLength, tasks.ContentHash,
           CASE WHEN tasks.ManifestProcessingVersion = N'skia-4.151.2-image-v1'
                THEN tasks.SourceContentHash END AS SourceContentHash,
           CASE WHEN tasks.ManifestProcessingVersion = N'skia-4.151.2-image-v1'
                THEN tasks.ManifestProcessingVersion END AS ProcessingVersion,
           tasks.RetentionUntilUtc, tasks.AttemptCount, tasks.MaxAttempts,
           tasks.LeaseUntilUtc, tasks.IdentityHash
    FROM dbo.FundingPlatform_ProjectAssetContentRetentionTasks AS tasks
    INNER JOIN @Claimed AS claimed ON claimed.Id = tasks.Id
    ORDER BY tasks.RetentionUntilUtc, tasks.Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAssetContentRetention_Complete
    @TaskPublicId UNIQUEIDENTIFIER, @LeaseId UNIQUEIDENTIFIER,
    @IdentityHash BINARY(32), @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @TaskPublicId IS NULL OR @LeaseId IS NULL OR @IdentityHash IS NULL
       OR @NowUtc IS NULL OR ABS(DATEDIFF_BIG(SECOND, @NowUtc, SYSUTCDATETIME())) > 300
        THROW 55903, N'Invalid retention completion identity or clock.', 1;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @Succeeded BIT = 0, @Replay BIT = 0, @Code NVARCHAR(50) = N'lease-conflict';
    DECLARE @Id BIGINT, @Status TINYINT, @Attempt SMALLINT, @Max SMALLINT, @Deleted DATETIME2(3);
    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_RetentionComplete039;
    BEGIN TRY
        SELECT @Id = Id, @Status = Status, @Attempt = AttemptCount, @Max = MaxAttempts,
               @Deleted = ContentDeletedAtUtc
        FROM dbo.FundingPlatform_ProjectAssetContentRetentionTasks WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @TaskPublicId AND LeaseId = @LeaseId AND IdentityHash = @IdentityHash
          AND (Status = 2 OR (Status = 1 AND LeaseUntilUtc > @NowUtc AND UpdatedAtUtc <= @NowUtc));
        IF @Status = 2
            SELECT @Succeeded = 1, @Replay = 1, @Code = N'completed';
        ELSE IF @Status = 1
        BEGIN
            UPDATE dbo.FundingPlatform_ProjectAssetContentRetentionTasks
            SET Status = 2, LeaseUntilUtc = NULL, ContentDeletedAtUtc = @NowUtc,
                LastErrorCode = NULL, UpdatedAtUtc = @NowUtc WHERE Id = @Id;
            UPDATE dbo.FundingPlatform_ProjectAssetContentRetentionAttempts
            SET FinishedAtUtc = @NowUtc, OutcomeCode = N'completed'
            WHERE TaskId = @Id AND AttemptCount = @Attempt;
            SELECT @Succeeded = 1, @Code = N'completed', @Deleted = @NowUtc;
        END;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION FP_RetentionComplete039;
        THROW;
    END CATCH;
    SELECT @Succeeded AS Succeeded, @Code AS Code, @Deleted AS ContentDeletedAtUtc,
           CAST(NULL AS DATETIME2(3)) AS NextAttemptAtUtc, @Attempt AS AttemptCount,
           @Max AS MaxAttempts, @Replay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAssetContentRetention_Fail
    @TaskPublicId UNIQUEIDENTIFIER, @LeaseId UNIQUEIDENTIFIER,
    @IdentityHash BINARY(32), @ErrorCode NVARCHAR(100), @IsRetryable BIT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @TaskPublicId IS NULL OR @LeaseId IS NULL OR @IdentityHash IS NULL OR @IsRetryable IS NULL
       OR @NowUtc IS NULL OR ABS(DATEDIFF_BIG(SECOND, @NowUtc, SYSUTCDATETIME())) > 300
       OR @ErrorCode IS NULL OR @ErrorCode COLLATE Latin1_General_100_BIN2 NOT IN
           (N'retention-task-invalid', N'blob-deletion-materialization-invalid',
            N'blob-identity-conflict', N'active-blob-version-remains', N'blob-deletion-unavailable')
       OR (@IsRetryable = 1 AND @ErrorCode NOT IN
           (N'active-blob-version-remains', N'blob-deletion-unavailable'))
        THROW 55903, N'Invalid retention failure identity, error or clock.', 1;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @Succeeded BIT = 0, @Code NVARCHAR(50) = N'lease-conflict';
    DECLARE @Id BIGINT, @Attempt SMALLINT, @Max SMALLINT, @Next DATETIME2(3);
    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_RetentionFail039;
    BEGIN TRY
        SELECT @Id = Id, @Attempt = AttemptCount, @Max = MaxAttempts
        FROM dbo.FundingPlatform_ProjectAssetContentRetentionTasks WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @TaskPublicId AND LeaseId = @LeaseId AND IdentityHash = @IdentityHash
          AND Status = 1 AND LeaseUntilUtc > @NowUtc AND UpdatedAtUtc <= @NowUtc;
        IF @Id IS NOT NULL
        BEGIN
            IF @IsRetryable = 1 AND @Attempt < @Max
            BEGIN
                SET @Next = DATEADD(SECOND, CASE WHEN @Attempt >= 7 THEN 3600
                    ELSE CONVERT(INT, POWER(2, @Attempt)) * 30 END, @NowUtc);
                SET @Code = N'retry-scheduled';
            END
            ELSE SET @Code = CASE WHEN @IsRetryable = 1 THEN N'retries-exhausted' ELSE N'failed' END;
            UPDATE dbo.FundingPlatform_ProjectAssetContentRetentionTasks
            SET Status = CASE WHEN @Next IS NULL THEN 3 ELSE 0 END,
                LeaseUntilUtc = NULL, NextAttemptAtUtc = @Next,
                LastErrorCode = CASE WHEN @Code = N'retries-exhausted' THEN @Code ELSE @ErrorCode END,
                UpdatedAtUtc = @NowUtc WHERE Id = @Id;
            UPDATE dbo.FundingPlatform_ProjectAssetContentRetentionAttempts
            SET FinishedAtUtc = @NowUtc, OutcomeCode = @ErrorCode
            WHERE TaskId = @Id AND AttemptCount = @Attempt;
            SET @Succeeded = 1;
        END;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION FP_RetentionFail039;
        THROW;
    END CATCH;
    SELECT @Succeeded AS Succeeded, @Code AS Code,
           CAST(NULL AS DATETIME2(3)) AS ContentDeletedAtUtc, @Next AS NextAttemptAtUtc,
           @Attempt AS AttemptCount, @Max AS MaxAttempts, CAST(0 AS BIT) AS WasReplay;
END;
GO

GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAssetContentRetention_Claim
    TO FundingPlatform_GeneralWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAssetContentRetention_Complete
    TO FundingPlatform_GeneralWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAssetContentRetention_Fail
    TO FundingPlatform_GeneralWorkerRole;

IF EXISTS (SELECT 1 FROM sys.database_permissions
           WHERE grantee_principal_id IN
                 (DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole'),
                  DATABASE_PRINCIPAL_ID(N'FundingPlatform_GeneralWorkerRole'))
             AND major_id IN
                 (OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetContentRetentionTasks'),
                  OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetContentRetentionAttempts'),
                  OBJECT_ID(N'dbo.FundingPlatform_vw_ProjectAssetRetentionCandidates')))
    THROW 55905, N'Retention tables and candidate view must not be runtime accessible.', 1;
GO
