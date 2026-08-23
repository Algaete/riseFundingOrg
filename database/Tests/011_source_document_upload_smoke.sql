/* Transactional smoke for secure source-document upload and fail-closed scan states. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @RequiredProcedures TABLE (Name SYSNAME NOT NULL PRIMARY KEY);
INSERT INTO @RequiredProcedures (Name) VALUES
    (N'FundingPlatform_usp_SourceDocumentUploadIntent_Create'),
    (N'FundingPlatform_usp_SourceDocumentUploadIntent_Get'),
    (N'FundingPlatform_usp_SourceDocumentUploadIntent_AcquireFinalize'),
    (N'FundingPlatform_usp_SourceDocumentUploadIntent_ReleaseFinalize'),
    (N'FundingPlatform_usp_SourceDocumentUploadIntent_RejectFinalize'),
    (N'FundingPlatform_usp_SourceDocumentUploadIntent_Complete'),
    (N'FundingPlatform_usp_SourceDocument_MarkQuarantined'),
    (N'FundingPlatform_usp_SourceDocument_ApplyScanResult'),
    (N'FundingPlatform_usp_SourceDocument_RetryScan'),
    (N'FundingPlatform_usp_SourceDocument_AcquireScanWork'),
    (N'FundingPlatform_usp_SourceDocument_Get');

IF EXISTS
(
    SELECT 1
    FROM @RequiredProcedures AS required
    LEFT JOIN sys.procedures AS actual
        ON actual.name COLLATE DATABASE_DEFAULT = required.Name COLLATE DATABASE_DEFAULT
       AND actual.schema_id = SCHEMA_ID(N'dbo')
    WHERE actual.object_id IS NULL
)
    THROW 53101, N'One or more source-document procedures are missing.', 1;

DECLARE @AdminMutations TABLE (Name SYSNAME NOT NULL PRIMARY KEY);
INSERT INTO @AdminMutations (Name) VALUES
    (N'FundingPlatform_usp_SourceDocumentUploadIntent_Create'),
    (N'FundingPlatform_usp_SourceDocumentUploadIntent_AcquireFinalize'),
    (N'FundingPlatform_usp_SourceDocumentUploadIntent_ReleaseFinalize'),
    (N'FundingPlatform_usp_SourceDocumentUploadIntent_RejectFinalize'),
    (N'FundingPlatform_usp_SourceDocumentUploadIntent_Complete'),
    (N'FundingPlatform_usp_SourceDocument_MarkQuarantined'),
    (N'FundingPlatform_usp_SourceDocument_RetryScan'),
    (N'FundingPlatform_usp_SourceDocument_AcquireScanWork');

IF EXISTS
(
    SELECT 1
    FROM @AdminMutations AS required
    INNER JOIN sys.procedures AS procedures
        ON procedures.name COLLATE DATABASE_DEFAULT = required.Name COLLATE DATABASE_DEFAULT
       AND procedures.schema_id = SCHEMA_ID(N'dbo')
    WHERE CHARINDEX
          (N'FundingPlatform_usp_AdminActor_Lock',
           COALESCE(OBJECT_DEFINITION(procedures.object_id), N'')) = 0
)
    THROW 53142, N'An administrative mutation does not revalidate and lock its actor.', 1;

IF OBJECT_ID(N'dbo.FundingPlatform_SourceDocuments', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_SourceDocumentUploadIntents', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_SourceDocumentScanEvents', N'U') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_SourceDocuments', N'TrustedBlobObjectName') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_SourceDocuments', N'RowVersion') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_SourceDocumentUploadIntents', N'FinalizeLeaseId') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_SourceDocumentScanEvents', N'PayloadHash') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_SourceDocumentScanEvents', N'IdempotencyKeyHash') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_SourceDocumentScanEvents', N'RequestHash') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_SourceDocumentScanEvents', N'ResultRowVersion') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_SourceDocumentScanEvents', N'ResultScanAttemptCount') IS NULL
    THROW 53102, N'Source-document schema is incomplete.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_FundingSources
    WHERE Name = N'Manual document upload' AND ProviderType = 4 AND IsEnabled = 1
)
    THROW 53103, N'The administrative file source is missing or disabled.', 1;

IF EXISTS
(
    SELECT 1
    FROM sys.dm_exec_describe_first_result_set_for_object
         (OBJECT_ID(N'dbo.FundingPlatform_usp_SourceDocumentUploadIntent_Get'), 0)
    WHERE LOWER(name) LIKE N'%blob%'
       OR LOWER(name) LIKE N'%token%'
       OR LOWER(name) LIKE N'%hash%'
       OR LOWER(name) LIKE N'%path%'
)
OR EXISTS
(
    SELECT 1
    FROM sys.dm_exec_describe_first_result_set_for_object
         (OBJECT_ID(N'dbo.FundingPlatform_usp_SourceDocument_Get'), 0)
    WHERE LOWER(name) LIKE N'%blob%'
       OR LOWER(name) LIKE N'%token%'
       OR LOWER(name) LIKE N'%hash%'
       OR LOWER(name) LIKE N'%path%'
)
    THROW 53104, N'An administrative GET exposes internal blob, token, hash, or path data.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke011;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @Suffix NVARCHAR(32) = REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'');
    DECLARE @AdminPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @NoMfaAdminPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @AdminEmail NVARCHAR(320) = N'upload-admin-' + @Suffix + N'@example.invalid';
    DECLARE @NoMfaEmail NVARCHAR(320) = N'upload-no-mfa-' + @Suffix + N'@example.invalid';
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@AdminPublicId, @AdminEmail, UPPER(@AdminEmail), N'Upload smoke admin',
         N'not-a-credential', N'upload-smoke-admin', 1, 1, 2, N'es-CL'),
        (@NoMfaAdminPublicId, @NoMfaEmail, UPPER(@NoMfaEmail), N'Upload smoke no MFA',
         N'not-a-credential', N'upload-smoke-no-mfa', 1, 0, 2, N'es-CL');

    DECLARE @AdminUserId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @AdminPublicId);
    DECLARE @NoMfaAdminUserId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @NoMfaAdminPublicId);
    DECLARE @AdminRoleId SMALLINT =
        (SELECT Id FROM dbo.FundingPlatform_Roles WHERE NormalizedName = N'ADMIN');
    DECLARE @FundingSourceId INT =
        (SELECT Id FROM dbo.FundingPlatform_FundingSources
         WHERE Name = N'Manual document upload');
    DECLARE @FundingSourcePolicyVersion INT, @FundingSourceRetentionDays SMALLINT;
    SELECT @FundingSourcePolicyVersion = policies.PolicyVersion,
           @FundingSourceRetentionDays = policies.ContentRetentionDays
    FROM dbo.FundingPlatform_FundingSources AS sources
    INNER JOIN dbo.FundingPlatform_FundingSourceAcquisitionPolicyVersions AS policies
        ON policies.FundingSourceId = sources.Id
       AND policies.PolicyVersion = sources.AcquisitionPolicyVersion
    WHERE sources.Id = @FundingSourceId;
    IF @FundingSourcePolicyVersion IS NULL OR @FundingSourceRetentionDays IS NULL
        THROW 53143, N'The manual document retention policy is missing.', 1;
    DECLARE @LeaseUntilUtc DATETIME2(3) = DATEADD(MINUTE, 4, SYSUTCDATETIME());

    INSERT INTO dbo.FundingPlatform_UserRoles (UserId, RoleId, GrantedByUserId)
    VALUES (@AdminUserId, @AdminRoleId, @AdminUserId),
           (@NoMfaAdminUserId, @AdminRoleId, @AdminUserId);

    DECLARE @CreateResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), IntentPublicId UNIQUEIDENTIFIER NULL,
        Status TINYINT NULL, ExpiresAtUtc DATETIME2(3) NULL,
        RowVersion BINARY(8) NULL, WasReplay BIT
    );
    DECLARE @NoMfaError INT;
    DECLARE @NoMfaObject NVARCHAR(1024) = N'smoke/' + @Suffix + N'/no-mfa.pdf';
    DECLARE @NoMfaTokenHash BINARY(32) = HASHBYTES('SHA2_256', N'no-mfa-' + @Suffix);
    DECLARE @NoMfaExpiresAtUtc DATETIME2(3) = DATEADD(MINUTE, 5, SYSUTCDATETIME());

    SET XACT_ABORT OFF;
    BEGIN TRY
        INSERT INTO @CreateResult
        EXEC dbo.FundingPlatform_usp_SourceDocumentUploadIntent_Create
            @AdminUserPublicId = @NoMfaAdminPublicId,
            @FundingSourceId = @FundingSourceId,
            @OriginalFileName = N'no-mfa.pdf',
            @DeclaredMimeType = N'application/pdf',
            @ExpectedContentLength = 1024,
            @MaxContentLength = 26214400,
            @BlobContainer = N'fp-source-incoming',
            @BlobObjectName = @NoMfaObject,
            @QuarantineBlobContainer = N'fp-source-quarantine',
            @QuarantineBlobObjectName = @NoMfaObject,
            @CompletionTokenHash = @NoMfaTokenHash,
            @ExpiresAtUtc = @NoMfaExpiresAtUtc;
    END TRY
    BEGIN CATCH
        SET @NoMfaError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;

    IF @NoMfaError <> 51602
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentUploadIntents
           WHERE UploadedByUserId = @NoMfaAdminUserId)
        THROW 53105, N'An admin without MFA created an upload intent.', 1;

    DELETE FROM @CreateResult;
    DECLARE @TokenHash BINARY(32) = HASHBYTES('SHA2_256', N'main-token-' + @Suffix);
    DECLARE @ContentHash BINARY(32) = HASHBYTES('SHA2_256', N'main-content-' + @Suffix);
    DECLARE @IncomingObject NVARCHAR(1024) = N'smoke/' + @Suffix + N'/main.pdf';
    DECLARE @QuarantineObject NVARCHAR(1024) = N'smoke/' + @Suffix + N'/main.pdf';
    DECLARE @MainOriginalFileName NVARCHAR(260) = N'smoke-main-' + @Suffix + N'.pdf';
    DECLARE @MainExpiresAtUtc DATETIME2(3) = DATEADD(MINUTE, 5, SYSUTCDATETIME());

    INSERT INTO @CreateResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentUploadIntent_Create
        @AdminUserPublicId = @AdminPublicId,
        @FundingSourceId = @FundingSourceId,
        @OriginalFileName = @MainOriginalFileName,
        @DeclaredMimeType = N'application/pdf',
        @ExpectedContentLength = 1024,
        @MaxContentLength = 26214400,
        @BlobContainer = N'fp-source-incoming',
        @BlobObjectName = @IncomingObject,
        @QuarantineBlobContainer = N'fp-source-quarantine',
        @QuarantineBlobObjectName = @QuarantineObject,
        @CompletionTokenHash = @TokenHash,
        @ExpiresAtUtc = @MainExpiresAtUtc;

    DECLARE @IntentPublicId UNIQUEIDENTIFIER = (SELECT IntentPublicId FROM @CreateResult);
    IF NOT EXISTS
       (SELECT 1 FROM @CreateResult
        WHERE Succeeded = 1 AND Code = N'created' AND Status = 0 AND WasReplay = 0)
       OR @IntentPublicId IS NULL
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SourceDocumentUploadIntents
           WHERE PublicId = @IntentPublicId) <> 1
        THROW 53106, N'A valid upload intent was not created exactly once.', 1;

    DECLARE @AcquireResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), IntentPublicId UNIQUEIDENTIFIER NULL,
        FundingSourceId INT NULL, OriginalFileName NVARCHAR(260) NULL,
        IncomingBlobContainer NVARCHAR(63) NULL, IncomingBlobObjectName NVARCHAR(1024) NULL,
        QuarantineBlobContainer NVARCHAR(63) NULL,
        QuarantineBlobObjectName NVARCHAR(1024) NULL,
        DeclaredMimeType NVARCHAR(100) NULL, VerifiedMimeType NVARCHAR(100) NULL,
        ExpectedContentLength BIGINT NULL, MaxContentLength BIGINT NULL,
        ActualContentLength BIGINT NULL, ContentHash BINARY(32) NULL,
        BlobETag NVARCHAR(100) NULL, BlobVersionId NVARCHAR(200) NULL,
        Status TINYINT NULL, ExpiresAtUtc DATETIME2(3) NULL,
        SourceDocumentPublicId UNIQUEIDENTIFIER NULL,
        StorageStatus TINYINT NULL, ScanStatus TINYINT NULL, ScanProvider TINYINT NULL,
        FinalizeLeaseId UNIQUEIDENTIFIER NULL, RowVersion BINARY(8) NULL, WasReplay BIT
    );
    DECLARE @WrongTokenHash BINARY(32) =
        HASHBYTES('SHA2_256', N'wrong-token-' + @Suffix);
    DECLARE @WrongTokenLeaseId UNIQUEIDENTIFIER = NEWID();

    INSERT INTO @AcquireResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentUploadIntent_AcquireFinalize
        @AdminUserPublicId = @AdminPublicId,
        @IntentPublicId = @IntentPublicId,
        @CompletionTokenHash = @WrongTokenHash,
        @LeaseId = @WrongTokenLeaseId,
        @LeaseUntilUtc = @LeaseUntilUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @AcquireResult
        WHERE Succeeded = 0 AND Code = N'invalid-token' AND IntentPublicId IS NULL)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentUploadIntents
           WHERE PublicId = @IntentPublicId AND Status = 0)
        THROW 53107, N'An invalid completion token changed or disclosed an intent.', 1;

    DELETE FROM @AcquireResult;
    DECLARE @Lease1 UNIQUEIDENTIFIER = NEWID();
    DECLARE @Lease2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO @AcquireResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentUploadIntent_AcquireFinalize
        @AdminUserPublicId = @AdminPublicId,
        @IntentPublicId = @IntentPublicId,
        @CompletionTokenHash = @TokenHash,
        @LeaseId = @Lease1,
        @LeaseUntilUtc = @LeaseUntilUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @AcquireResult
        WHERE Succeeded = 1 AND Code = N'acquired' AND Status = 1
          AND IncomingBlobObjectName = @IncomingObject
          AND QuarantineBlobObjectName = @QuarantineObject
          AND FinalizeLeaseId = @Lease1 AND WasReplay = 0)
        THROW 53108, N'A valid finalization lease was not acquired.', 1;

    DELETE FROM @AcquireResult;
    INSERT INTO @AcquireResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentUploadIntent_AcquireFinalize
        @AdminUserPublicId = @AdminPublicId,
        @IntentPublicId = @IntentPublicId,
        @CompletionTokenHash = @TokenHash,
        @LeaseId = @Lease2,
        @LeaseUntilUtc = @LeaseUntilUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @AcquireResult
        WHERE Succeeded = 1 AND Code = N'finalizing' AND WasReplay = 1
          AND IncomingBlobObjectName IS NULL AND QuarantineBlobObjectName IS NULL)
        THROW 53109, N'A concurrent finalizer obtained protected work data.', 1;

    DECLARE @IntentMutationResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), IntentPublicId UNIQUEIDENTIFIER NULL,
        Status TINYINT NULL, SourceDocumentPublicId UNIQUEIDENTIFIER NULL,
        StorageStatus TINYINT NULL, ScanStatus TINYINT NULL, ScanProvider TINYINT NULL,
        RowVersion BINARY(8) NULL, WasReplay BIT
    );
    INSERT INTO @IntentMutationResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentUploadIntent_ReleaseFinalize
        @AdminUserPublicId = @AdminPublicId,
        @IntentPublicId = @IntentPublicId,
        @LeaseId = @Lease1,
        @ErrorCode = N'blob-timeout';

    IF NOT EXISTS
       (SELECT 1 FROM @IntentMutationResult
        WHERE Succeeded = 1 AND Code = N'released' AND Status = 0)
        THROW 53110, N'A transient finalization failure was not made retryable.', 1;

    DELETE FROM @AcquireResult;
    INSERT INTO @AcquireResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentUploadIntent_AcquireFinalize
        @AdminUserPublicId = @AdminPublicId,
        @IntentPublicId = @IntentPublicId,
        @CompletionTokenHash = @TokenHash,
        @LeaseId = @Lease2,
        @LeaseUntilUtc = @LeaseUntilUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @AcquireResult WHERE Succeeded = 1 AND Code = N'acquired')
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentUploadIntents
           WHERE PublicId = @IntentPublicId AND FinalizeAttemptCount = 2)
        THROW 53111, N'A released finalization could not be retried idempotently.', 1;

    /* Authorization is revalidated in the mutation transaction after external work. */
    DELETE FROM dbo.FundingPlatform_UserRoles
    WHERE UserId = @AdminUserId AND RoleId = @AdminRoleId;

    DECLARE @CompleteResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), IntentPublicId UNIQUEIDENTIFIER NULL,
        SourceDocumentPublicId UNIQUEIDENTIFIER NULL,
        StorageStatus TINYINT NULL, ScanStatus TINYINT NULL, ScanProvider TINYINT NULL,
        RowVersion BINARY(8) NULL, WasReplay BIT
    );
    DECLARE @RevokedError INT;
    SET XACT_ABORT OFF;
    BEGIN TRY
        INSERT INTO @CompleteResult
        EXEC dbo.FundingPlatform_usp_SourceDocumentUploadIntent_Complete
            @AdminUserPublicId = @AdminPublicId,
            @IntentPublicId = @IntentPublicId,
            @LeaseId = @Lease2,
            @VerifiedMimeType = N'application/pdf',
            @ActualContentLength = 1024,
            @ContentHash = @ContentHash,
            @ScanProvider = 0;
    END TRY
    BEGIN CATCH
        SET @RevokedError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;

    IF @RevokedError <> 51601
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentUploadIntents
           WHERE PublicId = @IntentPublicId AND CompletedSourceDocumentId IS NOT NULL)
        THROW 53112, N'Revoked admin authorization was not revalidated at completion.', 1;

    INSERT INTO dbo.FundingPlatform_UserRoles (UserId, RoleId, GrantedByUserId)
    VALUES (@AdminUserId, @AdminRoleId, @AdminUserId);

    DELETE FROM @CompleteResult;
    INSERT INTO @CompleteResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentUploadIntent_Complete
        @AdminUserPublicId = @AdminPublicId,
        @IntentPublicId = @IntentPublicId,
        @LeaseId = @Lease2,
        @VerifiedMimeType = N'application/pdf',
        @ActualContentLength = 1024,
        @ContentHash = @ContentHash,
        @ScanProvider = 0;

    DECLARE @SourceDocumentPublicId UNIQUEIDENTIFIER =
        (SELECT SourceDocumentPublicId FROM @CompleteResult);
    DECLARE @SourceDocumentId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_SourceDocuments
         WHERE PublicId = @SourceDocumentPublicId);

    IF NOT EXISTS
       (SELECT 1 FROM @CompleteResult
        WHERE Succeeded = 1 AND Code = N'completed' AND StorageStatus = 0
          AND ScanStatus = 0 AND ScanProvider = 0 AND WasReplay = 0)
       OR @SourceDocumentPublicId IS NULL
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SourceDocuments
           WHERE Id = @SourceDocumentId) <> 1
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocuments
           WHERE Id = @SourceDocumentId
             AND ContentRetentionDays = @FundingSourceRetentionDays
             AND AcquisitionPolicyVersion = @FundingSourcePolicyVersion
             AND RetentionUntilUtc =
                 DATEADD(DAY, @FundingSourceRetentionDays, CreatedAtUtc))
        THROW 53113, N'A verified upload did not create one pending source document.', 1;

    DELETE FROM @CompleteResult;
    INSERT INTO @CompleteResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentUploadIntent_Complete
        @AdminUserPublicId = @AdminPublicId,
        @IntentPublicId = @IntentPublicId,
        @LeaseId = @Lease2,
        @VerifiedMimeType = N'application/pdf',
        @ActualContentLength = 1024,
        @ContentHash = @ContentHash,
        @ScanProvider = 0;

    IF NOT EXISTS
       (SELECT 1 FROM @CompleteResult
        WHERE Succeeded = 1 AND Code = N'completed'
          AND SourceDocumentPublicId = @SourceDocumentPublicId AND WasReplay = 1)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SourceDocuments
           WHERE Id = @SourceDocumentId) <> 1
        THROW 53114, N'Completion replay duplicated or changed the source document.', 1;

    /* Simulate a crash after SQL completion and before the server-side quarantine copy. */
    DECLARE @CrashAfterCompleteLeaseId UNIQUEIDENTIFIER = NEWID();
    DELETE FROM @AcquireResult;
    INSERT INTO @AcquireResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentUploadIntent_AcquireFinalize
        @AdminUserPublicId = @AdminPublicId,
        @IntentPublicId = @IntentPublicId,
        @CompletionTokenHash = @TokenHash,
        @LeaseId = @CrashAfterCompleteLeaseId,
        @LeaseUntilUtc = @LeaseUntilUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @AcquireResult
        WHERE Succeeded = 1 AND Code = N'completed' AND WasReplay = 1
          AND SourceDocumentPublicId = @SourceDocumentPublicId
          AND StorageStatus = 0 AND ScanStatus = 0
          AND IncomingBlobObjectName = @IncomingObject
          AND QuarantineBlobObjectName = @QuarantineObject
          AND VerifiedMimeType = N'application/pdf'
          AND ActualContentLength = 1024 AND ContentHash = @ContentHash)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SourceDocuments
           WHERE Id = @SourceDocumentId) <> 1
        THROW 53115, N'Crash recovery lacks protected work data or duplicated the document.', 1;

    DECLARE @DocumentMutationResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), SourceDocumentPublicId UNIQUEIDENTIFIER NULL,
        StorageStatus TINYINT NULL, ScanStatus TINYINT NULL, ScanProvider TINYINT NULL,
        RowVersion BINARY(8) NULL, WasReplay BIT
    );
    DECLARE @MainBlobETag NVARCHAR(100) = N'"etag-main"';
    DECLARE @MainBlobVersionId NVARCHAR(200) = N'version-main';
    INSERT INTO @DocumentMutationResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_MarkQuarantined
        @AdminUserPublicId = @AdminPublicId,
        @SourceDocumentPublicId = @SourceDocumentPublicId,
        @BlobETag = @MainBlobETag,
        @BlobVersionId = @MainBlobVersionId;

    IF NOT EXISTS
       (SELECT 1 FROM @DocumentMutationResult
        WHERE Succeeded = 1 AND Code = N'quarantined'
          AND StorageStatus = 1 AND ScanStatus = 0 AND WasReplay = 0)
        THROW 53116, N'The verified document was not moved into quarantine state.', 1;

    /* Simulate a crash after quarantine and before the scanner result. */
    DECLARE @CrashAfterQuarantineLeaseId UNIQUEIDENTIFIER = NEWID();
    DELETE FROM @AcquireResult;
    INSERT INTO @AcquireResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentUploadIntent_AcquireFinalize
        @AdminUserPublicId = @AdminPublicId,
        @IntentPublicId = @IntentPublicId,
        @CompletionTokenHash = @TokenHash,
        @LeaseId = @CrashAfterQuarantineLeaseId,
        @LeaseUntilUtc = @LeaseUntilUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @AcquireResult
        WHERE Succeeded = 1 AND Code = N'completed' AND WasReplay = 1
          AND IncomingBlobObjectName IS NULL
          AND QuarantineBlobObjectName = @QuarantineObject
          AND ContentHash = @ContentHash AND BlobETag = @MainBlobETag
          AND BlobVersionId = @MainBlobVersionId
          AND StorageStatus = 1 AND ScanStatus = 0 AND ScanProvider = 0)
        THROW 53117, N'Pending scan recovery lacks the verified quarantine receipt.', 1;

    DECLARE @ScanResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), SourceDocumentPublicId UNIQUEIDENTIFIER NULL,
        StorageStatus TINYINT NULL, ScanStatus TINYINT NULL, ScanProvider TINYINT NULL,
        RowVersion BINARY(8) NULL, WasReplay BIT,
        RevokedTrustedBlobContainer NVARCHAR(63) NULL,
        RevokedTrustedBlobObjectName NVARCHAR(1024) NULL,
        RevokedTrustedBlobETag NVARCHAR(100) NULL
    );
    DECLARE @CleanEventId NVARCHAR(200) = N'dev-clean-' + @Suffix;
    DECLARE @CleanPayloadHash BINARY(32) = HASHBYTES('SHA2_256', N'clean-event-' + @Suffix);
    DECLARE @WrongETagEventId NVARCHAR(200) = N'wrong-etag-' + @Suffix;
    DECLARE @WrongETagPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'wrong-etag-event-' + @Suffix);
    DECLARE @WrongHashEventId NVARCHAR(200) = N'wrong-hash-' + @Suffix;
    DECLARE @WrongHashPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'wrong-hash-event-' + @Suffix);
    DECLARE @ConflictingPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'conflicting-event-' + @Suffix);
    DECLARE @ScanOccurredAtUtc DATETIME2(3) = SYSUTCDATETIME();

    INSERT INTO @ScanResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_ApplyScanResult
        @SourceDocumentPublicId = @SourceDocumentPublicId,
        @ScanProvider = 0,
        @ProviderEventId = @WrongETagEventId,
        @PayloadHash = @WrongETagPayloadHash,
        @BlobETag = N'"wrong-etag"',
        @ReportedContentHash = @ContentHash,
        @ToStatus = 1,
        @ResultCode = N'no-threats-found',
        @TrustedBlobContainer = N'fp-source-trusted',
        @TrustedBlobObjectName = @QuarantineObject,
        @TrustedBlobETag = N'"trusted-etag"',
        @OccurredAtUtc = @ScanOccurredAtUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @ScanResult WHERE Succeeded = 0 AND Code = N'blob-etag-mismatch')
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentScanEvents
           WHERE SourceDocumentId = @SourceDocumentId)
        THROW 53118, N'A scan result with a stale blob ETag changed state.', 1;

    DELETE FROM @ScanResult;
    SET @ScanOccurredAtUtc = SYSUTCDATETIME();
    INSERT INTO @ScanResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_ApplyScanResult
        @SourceDocumentPublicId = @SourceDocumentPublicId,
        @ScanProvider = 0,
        @ProviderEventId = @WrongHashEventId,
        @PayloadHash = @WrongHashPayloadHash,
        @BlobETag = @MainBlobETag,
        @ReportedContentHash = 0x0101010101010101010101010101010101010101010101010101010101010101,
        @ToStatus = 1,
        @ResultCode = N'no-threats-found',
        @TrustedBlobContainer = N'fp-source-trusted',
        @TrustedBlobObjectName = @QuarantineObject,
        @TrustedBlobETag = N'"trusted-etag"',
        @OccurredAtUtc = @ScanOccurredAtUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @ScanResult WHERE Succeeded = 0 AND Code = N'content-hash-mismatch')
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentScanEvents
           WHERE SourceDocumentId = @SourceDocumentId)
        THROW 53119, N'A scan result with a wrong content hash changed state.', 1;

    DELETE FROM @ScanResult;
    SET @ScanOccurredAtUtc = SYSUTCDATETIME();
    INSERT INTO @ScanResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_ApplyScanResult
        @SourceDocumentPublicId = @SourceDocumentPublicId,
        @ScanProvider = 0,
        @ProviderEventId = @CleanEventId,
        @PayloadHash = @CleanPayloadHash,
        @BlobETag = @MainBlobETag,
        @ReportedContentHash = @ContentHash,
        @ToStatus = 1,
        @ResultCode = N'no-threats-found',
        @TrustedBlobContainer = N'fp-source-trusted',
        @TrustedBlobObjectName = @QuarantineObject,
        @TrustedBlobETag = N'"trusted-etag"',
        @OccurredAtUtc = @ScanOccurredAtUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @ScanResult
        WHERE Succeeded = 1 AND Code = N'scan-result-applied'
          AND StorageStatus = 2 AND ScanStatus = 1 AND ScanProvider = 0
          AND WasReplay = 0)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocuments
           WHERE Id = @SourceDocumentId AND StorageStatus = 2 AND ScanStatus = 1
             AND TrustedBlobContainer = N'fp-source-trusted'
             AND TrustedBlobObjectName = @QuarantineObject
             AND ScanCompletedAtUtc IS NOT NULL)
        THROW 53120, N'A clean result did not promote exactly the verified document.', 1;

    DELETE FROM @ScanResult;
    SET @ScanOccurredAtUtc = SYSUTCDATETIME();
    INSERT INTO @ScanResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_ApplyScanResult
        @SourceDocumentPublicId = @SourceDocumentPublicId,
        @ScanProvider = 0,
        @ProviderEventId = @CleanEventId,
        @PayloadHash = @CleanPayloadHash,
        @BlobETag = @MainBlobETag,
        @ReportedContentHash = @ContentHash,
        @ToStatus = 1,
        @ResultCode = N'no-threats-found',
        @TrustedBlobContainer = N'fp-source-trusted',
        @TrustedBlobObjectName = @QuarantineObject,
        @TrustedBlobETag = N'"trusted-etag"',
        @OccurredAtUtc = @ScanOccurredAtUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @ScanResult
        WHERE Succeeded = 1 AND Code = N'scan-result-applied' AND WasReplay = 1)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SourceDocumentScanEvents
           WHERE SourceDocumentId = @SourceDocumentId) <> 1
        THROW 53121, N'A duplicate scan delivery was not idempotent.', 1;

    DELETE FROM @ScanResult;
    SET @ScanOccurredAtUtc = SYSUTCDATETIME();
    INSERT INTO @ScanResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_ApplyScanResult
        @SourceDocumentPublicId = @SourceDocumentPublicId,
        @ScanProvider = 0,
        @ProviderEventId = @CleanEventId,
        @PayloadHash = @ConflictingPayloadHash,
        @BlobETag = @MainBlobETag,
        @ReportedContentHash = @ContentHash,
        @ToStatus = 1,
        @ResultCode = N'no-threats-found',
        @TrustedBlobContainer = N'fp-source-trusted',
        @TrustedBlobObjectName = @QuarantineObject,
        @TrustedBlobETag = N'"trusted-etag"',
        @OccurredAtUtc = @ScanOccurredAtUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @ScanResult WHERE Succeeded = 0 AND Code = N'event-conflict')
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SourceDocumentScanEvents
           WHERE SourceDocumentId = @SourceDocumentId) <> 1
        THROW 53122, N'A conflicting provider event changed a terminal scan.', 1;

    DECLARE @RetryResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), SourceDocumentPublicId UNIQUEIDENTIFIER NULL,
        StorageStatus TINYINT NULL, ScanStatus TINYINT NULL, ScanProvider TINYINT NULL,
        ScanAttemptCount SMALLINT NULL, RowVersion BINARY(8) NULL, WasReplay BIT
    );
    DECLARE @ScanWorkResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), SourceDocumentPublicId UNIQUEIDENTIFIER NULL,
        QuarantineBlobContainer NVARCHAR(63) NULL,
        QuarantineBlobObjectName NVARCHAR(1024) NULL,
        ContentLength BIGINT NULL, ContentHash BINARY(32) NULL,
        BlobETag NVARCHAR(100) NULL, BlobVersionId NVARCHAR(200) NULL,
        ScanProvider TINYINT NULL, ScanAttemptCount SMALLINT NULL,
        ScanStartedAtUtc DATETIME2(3) NULL, CreatedAtUtc DATETIME2(3) NULL,
        RowVersion BINARY(8) NULL
    );
    DECLARE @MainCleanRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_SourceDocuments
         WHERE Id = @SourceDocumentId);
    DECLARE @MainCleanRetryKey BINARY(32) =
        HASHBYTES('SHA2_256', N'retry-clean-' + @Suffix);
    DECLARE @MainCleanRetryRequest BINARY(32) =
        HASHBYTES('SHA2_256', N'retry-clean-request-' + @Suffix);

    INSERT INTO @RetryResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_RetryScan
        @AdminUserPublicId = @AdminPublicId,
        @SourceDocumentPublicId = @SourceDocumentPublicId,
        @ExpectedRowVersion = @MainCleanRowVersion,
        @IdempotencyKeyHash = @MainCleanRetryKey,
        @RequestHash = @MainCleanRetryRequest;

    IF NOT EXISTS
       (SELECT 1 FROM @RetryResult
        WHERE Succeeded = 0 AND Code = N'invalid-transition' AND ScanStatus = 1)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentScanEvents
           WHERE SourceDocumentId = @SourceDocumentId AND ToStatus = 0)
        THROW 53123, N'A clean document was incorrectly made retryable.', 1;

    /* Independent quarantined fixtures exercise every terminal scanner outcome. */
    DECLARE @MaliciousPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @FailedPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @TimedOutPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @RetryLimitPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @MaliciousHash BINARY(32) = HASHBYTES('SHA2_256', N'malicious-content-' + @Suffix);
    DECLARE @FailedHash BINARY(32) = HASHBYTES('SHA2_256', N'failed-content-' + @Suffix);
    DECLARE @TimedOutHash BINARY(32) = HASHBYTES('SHA2_256', N'timeout-content-' + @Suffix);
    DECLARE @RetryLimitHash BINARY(32) = HASHBYTES('SHA2_256', N'limit-content-' + @Suffix);
    DECLARE @MaliciousObject NVARCHAR(1024) = N'smoke/' + @Suffix + N'/malicious.pdf';
    DECLARE @FailedObject NVARCHAR(1024) = N'smoke/' + @Suffix + N'/failed.pdf';
    DECLARE @TimedOutObject NVARCHAR(1024) = N'smoke/' + @Suffix + N'/timeout.pdf';
    DECLARE @RetryLimitObject NVARCHAR(1024) = N'smoke/' + @Suffix + N'/limit.pdf';
    DECLARE @MaliciousETag NVARCHAR(100) = N'"etag-malicious"';
    DECLARE @FailedETag NVARCHAR(100) = N'"etag-failed"';
    DECLARE @TimedOutETag NVARCHAR(100) = N'"etag-timeout"';
    DECLARE @RetryLimitETag NVARCHAR(100) = N'"etag-limit"';
    DECLARE @FixtureCreatedAtUtc DATETIME2(3) = DATEADD(MINUTE, -1, SYSUTCDATETIME());
    DECLARE @FutureEventId NVARCHAR(200) = N'future-event-' + @Suffix;
    DECLARE @FutureEventPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'future-event-payload-' + @Suffix);
    DECLARE @FutureOccurredAtUtc DATETIME2(3) = DATEADD(MINUTE, 1, SYSUTCDATETIME());
    DECLARE @MaliciousEventId NVARCHAR(200) = N'dev-malicious-' + @Suffix;
    DECLARE @MaliciousEventPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'malicious-event-' + @Suffix);
    DECLARE @OldEventId NVARCHAR(200) = N'old-event-' + @Suffix;
    DECLARE @OldEventPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'old-event-payload-' + @Suffix);
    DECLARE @OldOccurredAtUtc DATETIME2(3) = DATEADD(MINUTE, -1, @FixtureCreatedAtUtc);
    DECLARE @MaliciousRetryKey BINARY(32) =
        HASHBYTES('SHA2_256', N'retry-malicious-' + @Suffix);
    DECLARE @MaliciousRetryRequest BINARY(32) =
        HASHBYTES('SHA2_256', N'retry-malicious-request-' + @Suffix);
    DECLARE @FailedEventId NVARCHAR(200) = N'dev-failed-' + @Suffix;
    DECLARE @FailedEventPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'failed-event-' + @Suffix);
    DECLARE @FailedCleanEventId NVARCHAR(200) = N'dev-failed-clean-' + @Suffix;
    DECLARE @FailedCleanPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'failed-clean-event-' + @Suffix);
    DECLARE @TimedOutCleanEventId NVARCHAR(200) = N'dev-timeout-clean-' + @Suffix;
    DECLARE @TimedOutCleanPayloadHash BINARY(32) =
        HASHBYTES('SHA2_256', N'timeout-clean-event-' + @Suffix);
    DECLARE @TimedOutRetryKey BINARY(32) =
        HASHBYTES('SHA2_256', N'retry-timeout-' + @Suffix);
    DECLARE @TimedOutRetryRequest BINARY(32) =
        HASHBYTES('SHA2_256', N'retry-timeout-request-' + @Suffix);

    INSERT INTO dbo.FundingPlatform_SourceDocuments
        (PublicId, FundingSourceId, OriginalFileName, MimeType, ContentLength, ContentHash,
         BlobContainer, BlobObjectName, BlobETag, BlobVersionId,
         StorageStatus, ScanStatus, ScanProvider, ScanAttemptCount, ScanStartedAtUtc,
         ExtractionStatus, UploadedByUserId, ContentRetentionDays,
         AcquisitionPolicyVersion, RetentionUntilUtc, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@MaliciousPublicId, @FundingSourceId, N'malicious.pdf', N'application/pdf',
         2048, @MaliciousHash, N'fp-source-quarantine', @MaliciousObject,
         @MaliciousETag, N'version-malicious', 1, 0, 0, 1, @FixtureCreatedAtUtc,
         0, @AdminUserId, @FundingSourceRetentionDays, @FundingSourcePolicyVersion,
         DATEADD(DAY, @FundingSourceRetentionDays, @FixtureCreatedAtUtc),
         @FixtureCreatedAtUtc, @FixtureCreatedAtUtc),
        (@FailedPublicId, @FundingSourceId, N'failed.pdf', N'application/pdf',
         3072, @FailedHash, N'fp-source-quarantine', @FailedObject,
         @FailedETag, N'version-failed', 1, 0, 0, 1, @FixtureCreatedAtUtc,
         0, @AdminUserId, @FundingSourceRetentionDays, @FundingSourcePolicyVersion,
         DATEADD(DAY, @FundingSourceRetentionDays, @FixtureCreatedAtUtc),
         @FixtureCreatedAtUtc, @FixtureCreatedAtUtc),
        (@TimedOutPublicId, @FundingSourceId, N'timeout.pdf', N'application/pdf',
         4096, @TimedOutHash, N'fp-source-quarantine', @TimedOutObject,
         @TimedOutETag, N'version-timeout', 1, 0, 0, 1, @FixtureCreatedAtUtc,
         0, @AdminUserId, @FundingSourceRetentionDays, @FundingSourcePolicyVersion,
         DATEADD(DAY, @FundingSourceRetentionDays, @FixtureCreatedAtUtc),
         @FixtureCreatedAtUtc, @FixtureCreatedAtUtc),
        (@RetryLimitPublicId, @FundingSourceId, N'limit.pdf', N'application/pdf',
         5120, @RetryLimitHash, N'fp-source-quarantine', @RetryLimitObject,
         @RetryLimitETag, N'version-limit', 1, 0, 0, 1, @FixtureCreatedAtUtc,
         0, @AdminUserId, @FundingSourceRetentionDays, @FundingSourcePolicyVersion,
         DATEADD(DAY, @FundingSourceRetentionDays, @FixtureCreatedAtUtc),
         @FixtureCreatedAtUtc, @FixtureCreatedAtUtc);

    DECLARE @MaliciousId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_SourceDocuments WHERE PublicId = @MaliciousPublicId);
    DECLARE @FailedId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_SourceDocuments WHERE PublicId = @FailedPublicId);
    DECLARE @TimedOutId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_SourceDocuments WHERE PublicId = @TimedOutPublicId);
    DECLARE @RetryLimitId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_SourceDocuments WHERE PublicId = @RetryLimitPublicId);

    UPDATE dbo.FundingPlatform_SourceDocuments
    SET ScanStatus = 3,
        ScanAttemptCount = 100,
        ScanResultCode = N'Scanner unavailable',
        ScanCompletedAtUtc = SYSUTCDATETIME(),
        UpdatedAtUtc = SYSUTCDATETIME()
    WHERE Id = @RetryLimitId;

    DELETE FROM @ScanResult;
    INSERT INTO @ScanResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_ApplyScanResult
        @SourceDocumentPublicId = @MaliciousPublicId,
        @ScanProvider = 0,
        @ProviderEventId = @OldEventId,
        @PayloadHash = @OldEventPayloadHash,
        @BlobETag = @MaliciousETag,
        @ReportedContentHash = @MaliciousHash,
        @ToStatus = 2,
        @ResultCode = N'malware-detected',
        @TrustedBlobContainer = NULL,
        @TrustedBlobObjectName = NULL,
        @TrustedBlobETag = NULL,
        @OccurredAtUtc = @OldOccurredAtUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @ScanResult
        WHERE Succeeded = 0 AND Code = N'invalid-event-time' AND ScanStatus = 0)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentScanEvents
           WHERE SourceDocumentId = @MaliciousId)
        THROW 53141, N'A scanner event predating its document changed state.', 1;

    /* A future provider timestamp has a stable outcome and never falls through to CK 547. */
    DELETE FROM @ScanResult;
    INSERT INTO @ScanResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_ApplyScanResult
        @SourceDocumentPublicId = @TimedOutPublicId,
        @ScanProvider = 0,
        @ProviderEventId = @FutureEventId,
        @PayloadHash = @FutureEventPayloadHash,
        @BlobETag = @TimedOutETag,
        @ReportedContentHash = NULL,
        @ToStatus = 4,
        @ResultCode = N'scanner-timed-out',
        @TrustedBlobContainer = NULL,
        @TrustedBlobObjectName = NULL,
        @TrustedBlobETag = NULL,
        @OccurredAtUtc = @FutureOccurredAtUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @ScanResult
        WHERE Succeeded = 1 AND Code = N'scan-result-applied'
          AND StorageStatus = 1 AND ScanStatus = 4 AND WasReplay = 0)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SourceDocumentScanEvents
           WHERE SourceDocumentId = @TimedOutId) <> 1
        THROW 53124, N'A future scanner event did not return the defined safe outcome.', 1;

    DELETE FROM @ScanResult;
    SET @ScanOccurredAtUtc = SYSUTCDATETIME();
    INSERT INTO @ScanResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_ApplyScanResult
        @SourceDocumentPublicId = @MaliciousPublicId,
        @ScanProvider = 0,
        @ProviderEventId = @MaliciousEventId,
        @PayloadHash = @MaliciousEventPayloadHash,
        @BlobETag = @MaliciousETag,
        @ReportedContentHash = @MaliciousHash,
        @ToStatus = 2,
        @ResultCode = N'malware-detected',
        @TrustedBlobContainer = NULL,
        @TrustedBlobObjectName = NULL,
        @TrustedBlobETag = NULL,
        @OccurredAtUtc = @ScanOccurredAtUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @ScanResult
        WHERE Succeeded = 1 AND Code = N'scan-result-applied'
          AND StorageStatus = 1 AND ScanStatus = 2 AND WasReplay = 0)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocuments
           WHERE Id = @MaliciousId AND StorageStatus = 1 AND ScanStatus = 2
             AND TrustedBlobContainer IS NULL AND TrustedBlobObjectName IS NULL
             AND TrustedBlobETag IS NULL)
        THROW 53125, N'A malicious result was not kept quarantined and untrusted.', 1;

    DECLARE @MaliciousRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_SourceDocuments WHERE Id = @MaliciousId);
    DELETE FROM @RetryResult;
    INSERT INTO @RetryResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_RetryScan
        @AdminUserPublicId = @AdminPublicId,
        @SourceDocumentPublicId = @MaliciousPublicId,
        @ExpectedRowVersion = @MaliciousRowVersion,
        @IdempotencyKeyHash = @MaliciousRetryKey,
        @RequestHash = @MaliciousRetryRequest;

    IF NOT EXISTS
       (SELECT 1 FROM @RetryResult
        WHERE Succeeded = 0 AND Code = N'invalid-transition' AND ScanStatus = 2)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentScanEvents
           WHERE SourceDocumentId = @MaliciousId AND ToStatus = 0)
        THROW 53126, N'A malicious document was incorrectly made retryable.', 1;

    DECLARE @RetryLimitRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_SourceDocuments WHERE Id = @RetryLimitId);
    DECLARE @RetryLimitKey BINARY(32) =
        HASHBYTES('SHA2_256', N'retry-limit-' + @Suffix);
    DECLARE @RetryLimitRequest BINARY(32) =
        HASHBYTES('SHA2_256', N'retry-limit-request-' + @Suffix);
    DELETE FROM @RetryResult;
    INSERT INTO @RetryResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_RetryScan
        @AdminUserPublicId = @AdminPublicId,
        @SourceDocumentPublicId = @RetryLimitPublicId,
        @ExpectedRowVersion = @RetryLimitRowVersion,
        @IdempotencyKeyHash = @RetryLimitKey,
        @RequestHash = @RetryLimitRequest;

    IF NOT EXISTS
       (SELECT 1 FROM @RetryResult
        WHERE Succeeded = 0 AND Code = N'retry-limit-reached'
          AND StorageStatus = 1 AND ScanStatus = 3 AND ScanAttemptCount = 100)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentScanEvents
           WHERE SourceDocumentId = @RetryLimitId AND ToStatus = 0)
        THROW 53137, N'The scanner retry cap did not fail closed.', 1;

    DELETE FROM @ScanResult;
    SET @ScanOccurredAtUtc = SYSUTCDATETIME();
    INSERT INTO @ScanResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_ApplyScanResult
        @SourceDocumentPublicId = @FailedPublicId,
        @ScanProvider = 0,
        @ProviderEventId = @FailedEventId,
        @PayloadHash = @FailedEventPayloadHash,
        @BlobETag = @FailedETag,
        @ReportedContentHash = NULL,
        @ToStatus = 3,
        @ResultCode = N'scanner-unavailable',
        @TrustedBlobContainer = NULL,
        @TrustedBlobObjectName = NULL,
        @TrustedBlobETag = NULL,
        @OccurredAtUtc = @ScanOccurredAtUtc;

    DECLARE @FailedRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_SourceDocuments WHERE Id = @FailedId);
    IF NOT EXISTS
       (SELECT 1 FROM @ScanResult
        WHERE Succeeded = 1 AND StorageStatus = 1 AND ScanStatus = 3)
       OR @FailedRowVersion IS NULL
        THROW 53127, N'A scanner failure was not persisted as retryable state.', 1;

    DECLARE @FailedRetryKey BINARY(32) =
        HASHBYTES('SHA2_256', N'retry-failed-' + @Suffix);
    DECLARE @FailedRetryRequest BINARY(32) =
        HASHBYTES('SHA2_256', N'retry-failed-request-' + @Suffix);
    DECLARE @StaleRowVersion BINARY(8) = 0x0000000000000000;
    DELETE FROM @RetryResult;
    INSERT INTO @RetryResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_RetryScan
        @AdminUserPublicId = @AdminPublicId,
        @SourceDocumentPublicId = @FailedPublicId,
        @ExpectedRowVersion = @StaleRowVersion,
        @IdempotencyKeyHash = @FailedRetryKey,
        @RequestHash = @FailedRetryRequest;

    IF NOT EXISTS
       (SELECT 1 FROM @RetryResult WHERE Succeeded = 0 AND Code = N'etag-conflict')
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentScanEvents
           WHERE SourceDocumentId = @FailedId AND ToStatus = 0)
        THROW 53128, N'A stale retry ETag changed failed scan state.', 1;

    DELETE FROM @RetryResult;
    INSERT INTO @RetryResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_RetryScan
        @AdminUserPublicId = @AdminPublicId,
        @SourceDocumentPublicId = @FailedPublicId,
        @ExpectedRowVersion = @FailedRowVersion,
        @IdempotencyKeyHash = @FailedRetryKey,
        @RequestHash = @FailedRetryRequest;

    DECLARE @FailedRetryRowVersion BINARY(8) = (SELECT RowVersion FROM @RetryResult);
    IF NOT EXISTS
       (SELECT 1 FROM @RetryResult
        WHERE Succeeded = 1 AND Code = N'scan-retry-requested'
          AND StorageStatus = 1 AND ScanStatus = 0 AND ScanAttemptCount = 2
          AND WasReplay = 0)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocuments
           WHERE Id = @FailedId AND StorageStatus = 1 AND ScanStatus = 0
             AND ScanAttemptCount = 2 AND ScanResultCode IS NULL
             AND ScanCompletedAtUtc IS NULL AND RowVersion = @FailedRetryRowVersion)
        THROW 53129, N'A failed scan was not reset safely for retry.', 1;

    /* Scan work is internal, MFA-gated, revocation-safe, and ETag-bound. */
    INSERT INTO @ScanWorkResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_AcquireScanWork
        @AdminUserPublicId = @AdminPublicId,
        @SourceDocumentPublicId = @FailedPublicId,
        @ExpectedRowVersion = @FailedRowVersion;

    IF NOT EXISTS
       (SELECT 1 FROM @ScanWorkResult
        WHERE Succeeded = 0 AND Code = N'etag-conflict'
          AND QuarantineBlobObjectName IS NULL AND ContentHash IS NULL
          AND BlobETag IS NULL)
        THROW 53143, N'Stale scan work disclosed protected storage data.', 1;

    DELETE FROM @ScanWorkResult;
    DECLARE @NoMfaScanWorkError INT;
    SET XACT_ABORT OFF;
    BEGIN TRY
        INSERT INTO @ScanWorkResult
        EXEC dbo.FundingPlatform_usp_SourceDocument_AcquireScanWork
            @AdminUserPublicId = @NoMfaAdminPublicId,
            @SourceDocumentPublicId = @FailedPublicId,
            @ExpectedRowVersion = @FailedRetryRowVersion;
    END TRY
    BEGIN CATCH
        SET @NoMfaScanWorkError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;
    IF @NoMfaScanWorkError <> 51602
        THROW 53144, N'An admin without MFA acquired protected scan work.', 1;

    DELETE FROM dbo.FundingPlatform_UserRoles
    WHERE UserId = @AdminUserId AND RoleId = @AdminRoleId;
    DELETE FROM @ScanWorkResult;
    DECLARE @RevokedScanWorkError INT;
    SET XACT_ABORT OFF;
    BEGIN TRY
        INSERT INTO @ScanWorkResult
        EXEC dbo.FundingPlatform_usp_SourceDocument_AcquireScanWork
            @AdminUserPublicId = @AdminPublicId,
            @SourceDocumentPublicId = @FailedPublicId,
            @ExpectedRowVersion = @FailedRetryRowVersion;
    END TRY
    BEGIN CATCH
        SET @RevokedScanWorkError = ERROR_NUMBER();
    END CATCH;
    SET XACT_ABORT ON;
    IF @RevokedScanWorkError <> 51601
        THROW 53145, N'A revoked admin acquired protected scan work.', 1;
    INSERT INTO dbo.FundingPlatform_UserRoles (UserId, RoleId, GrantedByUserId)
    VALUES (@AdminUserId, @AdminRoleId, @AdminUserId);

    DELETE FROM @ScanWorkResult;
    INSERT INTO @ScanWorkResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_AcquireScanWork
        @AdminUserPublicId = @AdminPublicId,
        @SourceDocumentPublicId = @FailedPublicId,
        @ExpectedRowVersion = @FailedRetryRowVersion;

    IF NOT EXISTS
       (SELECT 1 FROM @ScanWorkResult
        WHERE Succeeded = 1 AND Code = N'acquired'
          AND QuarantineBlobContainer = N'fp-source-quarantine'
          AND QuarantineBlobObjectName = @FailedObject
          AND ContentLength = 3072 AND ContentHash = @FailedHash
          AND BlobETag = @FailedETag AND ScanProvider = 0
          AND ScanAttemptCount = 2 AND RowVersion = @FailedRetryRowVersion)
        THROW 53146, N'Authorized retry did not acquire complete internal scan work.', 1;

    DELETE FROM @RetryResult;
    INSERT INTO @RetryResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_RetryScan
        @AdminUserPublicId = @AdminPublicId,
        @SourceDocumentPublicId = @FailedPublicId,
        @ExpectedRowVersion = @FailedRowVersion,
        @IdempotencyKeyHash = @FailedRetryKey,
        @RequestHash = @FailedRetryRequest;

    IF NOT EXISTS
       (SELECT 1 FROM @RetryResult
        WHERE Succeeded = 1 AND Code = N'scan-retry-requested'
          AND ScanStatus = 0 AND ScanAttemptCount = 2 AND WasReplay = 1)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SourceDocumentScanEvents
           WHERE SourceDocumentId = @FailedId AND ToStatus = 0) <> 1
        THROW 53130, N'A retry replay duplicated the retry command.', 1;

    DELETE FROM @ScanResult;
    SET @ScanOccurredAtUtc = SYSUTCDATETIME();
    INSERT INTO @ScanResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_ApplyScanResult
        @SourceDocumentPublicId = @FailedPublicId,
        @ScanProvider = 0,
        @ProviderEventId = @FailedCleanEventId,
        @PayloadHash = @FailedCleanPayloadHash,
        @BlobETag = @FailedETag,
        @ReportedContentHash = @FailedHash,
        @ToStatus = 1,
        @ResultCode = N'no-threats-found-after-retry',
        @TrustedBlobContainer = N'fp-source-trusted',
        @TrustedBlobObjectName = @FailedObject,
        @TrustedBlobETag = N'"trusted-failed-etag"',
        @OccurredAtUtc = @ScanOccurredAtUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @ScanResult
        WHERE Succeeded = 1 AND StorageStatus = 2 AND ScanStatus = 1)
        THROW 53131, N'A failed scan could not become clean after an authorized retry.', 1;

    /* A late idempotent replay returns the original retry outcome, not current clean state. */
    DELETE FROM @RetryResult;
    INSERT INTO @RetryResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_RetryScan
        @AdminUserPublicId = @AdminPublicId,
        @SourceDocumentPublicId = @FailedPublicId,
        @ExpectedRowVersion = @FailedRowVersion,
        @IdempotencyKeyHash = @FailedRetryKey,
        @RequestHash = @FailedRetryRequest;

    IF NOT EXISTS
       (SELECT 1 FROM @RetryResult
        WHERE Succeeded = 1 AND Code = N'scan-retry-requested'
          AND StorageStatus = 1 AND ScanStatus = 0 AND ScanAttemptCount = 2
          AND RowVersion = @FailedRetryRowVersion AND WasReplay = 1)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocuments
           WHERE Id = @FailedId AND StorageStatus = 2 AND ScanStatus = 1)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SourceDocumentScanEvents
           WHERE SourceDocumentId = @FailedId AND ToStatus = 0) <> 1
        THROW 53138, N'A late retry replay did not preserve its historical outcome.', 1;

    DECLARE @TimedOutRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_SourceDocuments WHERE Id = @TimedOutId);
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_SourceDocuments
        WHERE Id = @TimedOutId AND StorageStatus = 1 AND ScanStatus = 4)
       OR @TimedOutRowVersion IS NULL
        THROW 53132, N'A scanner timeout was not persisted as retryable state.', 1;

    DELETE FROM @RetryResult;
    INSERT INTO @RetryResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_RetryScan
        @AdminUserPublicId = @AdminPublicId,
        @SourceDocumentPublicId = @TimedOutPublicId,
        @ExpectedRowVersion = @TimedOutRowVersion,
        @IdempotencyKeyHash = @TimedOutRetryKey,
        @RequestHash = @TimedOutRetryRequest;

    IF NOT EXISTS
       (SELECT 1 FROM @RetryResult
        WHERE Succeeded = 1 AND Code = N'scan-retry-requested'
          AND StorageStatus = 1 AND ScanStatus = 0 AND ScanAttemptCount = 2)
        THROW 53133, N'A timed-out scan was not reset safely for retry.', 1;

    DELETE FROM @ScanResult;
    SET @ScanOccurredAtUtc = SYSUTCDATETIME();
    INSERT INTO @ScanResult
    EXEC dbo.FundingPlatform_usp_SourceDocument_ApplyScanResult
        @SourceDocumentPublicId = @TimedOutPublicId,
        @ScanProvider = 0,
        @ProviderEventId = @TimedOutCleanEventId,
        @PayloadHash = @TimedOutCleanPayloadHash,
        @BlobETag = @TimedOutETag,
        @ReportedContentHash = @TimedOutHash,
        @ToStatus = 1,
        @ResultCode = N'no-threats-found-after-timeout-retry',
        @TrustedBlobContainer = N'fp-source-trusted',
        @TrustedBlobObjectName = @TimedOutObject,
        @TrustedBlobETag = N'"trusted-timeout-etag"',
        @OccurredAtUtc = @ScanOccurredAtUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @ScanResult
        WHERE Succeeded = 1 AND StorageStatus = 2 AND ScanStatus = 1)
        THROW 53134, N'A timed-out scan could not become clean after retry.', 1;

    /* A bounded finalization counter must produce a caller-safe outcome, never CK 547. */
    DECLARE @FinalizeLimitIntentPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @FinalizeLimitTokenHash BINARY(32) =
        HASHBYTES('SHA2_256', N'finalize-limit-token-' + @Suffix);
    DECLARE @FinalizeLimitIncomingObject NVARCHAR(1024) =
        N'smoke/' + @Suffix + N'/finalize-limit.pdf';
    DECLARE @FinalizeLimitQuarantineObject NVARCHAR(1024) =
        N'smoke/' + @Suffix + N'/finalize-limit-quarantine.pdf';
    DECLARE @FinalizeLimitExpiresAtUtc DATETIME2(3) =
        DATEADD(MINUTE, 4, SYSUTCDATETIME());
    DECLARE @FinalizeLimitLeaseId UNIQUEIDENTIFIER = NEWID();
    DECLARE @FinalizeLimitLeaseUntilUtc DATETIME2(3) =
        DATEADD(MINUTE, 2, SYSUTCDATETIME());

    INSERT INTO dbo.FundingPlatform_SourceDocumentUploadIntents
        (PublicId, FundingSourceId, OriginalFileName, BlobContainer, BlobObjectName,
         QuarantineBlobContainer, QuarantineBlobObjectName, CompletionTokenHash,
         DeclaredMimeType, ExpectedContentLength, MaxContentLength, Status,
         FinalizeAttemptCount, ExpiresAtUtc, UploadedByUserId)
    VALUES
        (@FinalizeLimitIntentPublicId, @FundingSourceId, N'finalize-limit.pdf',
         N'fp-source-incoming', @FinalizeLimitIncomingObject,
         N'fp-source-quarantine', @FinalizeLimitQuarantineObject,
         @FinalizeLimitTokenHash, N'application/pdf', 1024, 26214400, 0,
         100, @FinalizeLimitExpiresAtUtc, @AdminUserId);

    DELETE FROM @AcquireResult;
    INSERT INTO @AcquireResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentUploadIntent_AcquireFinalize
        @AdminUserPublicId = @AdminPublicId,
        @IntentPublicId = @FinalizeLimitIntentPublicId,
        @CompletionTokenHash = @FinalizeLimitTokenHash,
        @LeaseId = @FinalizeLimitLeaseId,
        @LeaseUntilUtc = @FinalizeLimitLeaseUntilUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @AcquireResult
        WHERE Succeeded = 0 AND Code = N'finalize-limit-reached' AND Status = 0
          AND IncomingBlobObjectName IS NULL AND QuarantineBlobObjectName IS NULL)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_SourceDocumentUploadIntents
           WHERE PublicId = @FinalizeLimitIntentPublicId
             AND Status = 0 AND FinalizeAttemptCount = 100
             AND FinalizeLeaseId IS NULL AND FinalizeLeaseUntilUtc IS NULL)
        THROW 53141, N'The finalization attempt limit was not caller-safe.', 1;

    /* Expiry is an observable transition and is emitted once on repeated acquisition. */
    DECLARE @ExpiredIntentPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ExpiredTokenHash BINARY(32) =
        HASHBYTES('SHA2_256', N'expired-token-' + @Suffix);
    DECLARE @ExpiredObject NVARCHAR(1024) = N'smoke/' + @Suffix + N'/expired.pdf';
    DECLARE @ExpiredQuarantineObject NVARCHAR(1024) =
        N'smoke/' + @Suffix + N'/expired-quarantine.pdf';
    DECLARE @ExpiredCreatedAtUtc DATETIME2(3) = DATEADD(MINUTE, -5, SYSUTCDATETIME());
    DECLARE @ExpiredAtUtc DATETIME2(3) = DATEADD(MINUTE, -4, SYSUTCDATETIME());
    DECLARE @ExpiredLeaseId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ExpiredReplayLeaseId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ExpiredLeaseUntilUtc DATETIME2(3) = DATEADD(MINUTE, 4, SYSUTCDATETIME());

    INSERT INTO dbo.FundingPlatform_SourceDocumentUploadIntents
        (PublicId, FundingSourceId, OriginalFileName, BlobContainer, BlobObjectName,
         QuarantineBlobContainer, QuarantineBlobObjectName, CompletionTokenHash,
         DeclaredMimeType, ExpectedContentLength, MaxContentLength, Status,
         ExpiresAtUtc, UploadedByUserId, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@ExpiredIntentPublicId, @FundingSourceId, N'expired.pdf',
         N'fp-source-incoming', @ExpiredObject,
         N'fp-source-quarantine', @ExpiredQuarantineObject, @ExpiredTokenHash,
         N'application/pdf', 1024, 26214400, 0,
         @ExpiredAtUtc, @AdminUserId, @ExpiredCreatedAtUtc, @ExpiredCreatedAtUtc);

    DELETE FROM @AcquireResult;
    INSERT INTO @AcquireResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentUploadIntent_AcquireFinalize
        @AdminUserPublicId = @AdminPublicId,
        @IntentPublicId = @ExpiredIntentPublicId,
        @CompletionTokenHash = @ExpiredTokenHash,
        @LeaseId = @ExpiredLeaseId,
        @LeaseUntilUtc = @ExpiredLeaseUntilUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @AcquireResult
        WHERE Succeeded = 0 AND Code = N'expired' AND Status = 3
          AND IncomingBlobObjectName IS NULL AND QuarantineBlobObjectName IS NULL)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_OutboxMessages
           WHERE MessageType = N'SourceDocumentUploadIntentExpired'
             AND AggregateId = CONVERT(NVARCHAR(100), @ExpiredIntentPublicId)) <> 1
        THROW 53139, N'Intent expiry was not persisted and emitted exactly once.', 1;

    DELETE FROM @AcquireResult;
    INSERT INTO @AcquireResult
    EXEC dbo.FundingPlatform_usp_SourceDocumentUploadIntent_AcquireFinalize
        @AdminUserPublicId = @AdminPublicId,
        @IntentPublicId = @ExpiredIntentPublicId,
        @CompletionTokenHash = @ExpiredTokenHash,
        @LeaseId = @ExpiredReplayLeaseId,
        @LeaseUntilUtc = @ExpiredLeaseUntilUtc;

    IF NOT EXISTS
       (SELECT 1 FROM @AcquireResult
        WHERE Succeeded = 0 AND Code = N'expired' AND Status = 3)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_OutboxMessages
           WHERE MessageType = N'SourceDocumentUploadIntentExpired'
             AND AggregateId = CONVERT(NVARCHAR(100), @ExpiredIntentPublicId)) <> 1
        THROW 53140, N'Intent expiry replay duplicated its integration event.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_SourceDocuments
        WHERE Id IN (@SourceDocumentId, @MaliciousId, @FailedId, @TimedOutId, @RetryLimitId)
          AND ((ScanStatus = 1 AND
                (StorageStatus <> 2 OR TrustedBlobContainer IS NULL
                 OR TrustedBlobObjectName IS NULL OR TrustedBlobETag IS NULL))
               OR (ScanStatus <> 1 AND
                   (StorageStatus = 2 OR TrustedBlobContainer IS NOT NULL
                    OR TrustedBlobObjectName IS NOT NULL OR TrustedBlobETag IS NOT NULL)))
    )
        THROW 53135, N'Trusted storage state is inconsistent with the clean verdict.', 1;

    /* Public integration events are deliberately metadata-only. */
    IF EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_OutboxMessages
        WHERE AggregateId IN
              (CONVERT(NVARCHAR(100), @IntentPublicId),
               CONVERT(NVARCHAR(100), @ExpiredIntentPublicId),
               CONVERT(NVARCHAR(100), @SourceDocumentPublicId),
               CONVERT(NVARCHAR(100), @MaliciousPublicId),
               CONVERT(NVARCHAR(100), @FailedPublicId),
               CONVERT(NVARCHAR(100), @TimedOutPublicId),
               CONVERT(NVARCHAR(100), @RetryLimitPublicId))
          AND (ISJSON(COALESCE(PayloadJson, N'')) <> 1
               OR LOWER(PayloadJson) LIKE N'%filename%'
               OR LOWER(PayloadJson) LIKE N'%blob%'
               OR LOWER(PayloadJson) LIKE N'%container%'
               OR LOWER(PayloadJson) LIKE N'%objectname%'
               OR LOWER(PayloadJson) LIKE N'%path%'
               OR LOWER(PayloadJson) LIKE N'%token%'
               OR LOWER(PayloadJson) LIKE N'%hash%'
               OR LOWER(PayloadJson) LIKE N'%etag%'
               OR PayloadJson LIKE N'%' + @Suffix + N'%')
    )
        THROW 53136, N'An outbox payload contains protected upload or scanner data.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke011;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FP_Smoke011;
    THROW;
END CATCH;

SELECT CAST(1 AS BIT) AS Succeeded,
       N'FASE 6 source-document upload smoke passed.' AS Message;
