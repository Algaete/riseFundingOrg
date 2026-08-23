/* FundingPlatform FASE 6 - secure administrative source-document upload boundary. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

CREATE TABLE dbo.FundingPlatform_SourceDocuments
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocuments_PublicId DEFAULT (NEWSEQUENTIALID()),
    FundingSourceId INT NOT NULL,
    OriginalFileName NVARCHAR(260) NOT NULL,
    MimeType NVARCHAR(100) NOT NULL,
    ContentLength BIGINT NOT NULL,
    ContentHash BINARY(32) NOT NULL,
    BlobContainer NVARCHAR(63) NOT NULL,
    BlobObjectName NVARCHAR(1024) NOT NULL,
    BlobETag NVARCHAR(100) NULL,
    BlobVersionId NVARCHAR(200) NULL,
    TrustedBlobContainer NVARCHAR(63) NULL,
    TrustedBlobObjectName NVARCHAR(1024) NULL,
    TrustedBlobETag NVARCHAR(100) NULL,
    StorageStatus TINYINT NOT NULL,
    ScanStatus TINYINT NOT NULL,
    ScanProvider TINYINT NOT NULL,
    ScanAttemptCount SMALLINT NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocuments_ScanAttempts DEFAULT (1),
    ScanResultCode NVARCHAR(100) NULL,
    ScanStartedAtUtc DATETIME2(3) NULL,
    ScanCompletedAtUtc DATETIME2(3) NULL,
    ExtractionStatus TINYINT NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocuments_ExtractionStatus DEFAULT (0),
    UploadedByUserId BIGINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocuments_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocuments_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_SourceDocuments PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SourceDocuments_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_SourceDocuments_IdSource UNIQUE (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_UQ_SourceDocuments_QuarantineBlob
        UNIQUE (BlobContainer, BlobObjectName),
    CONSTRAINT FundingPlatform_FK_SourceDocuments_FundingSource
        FOREIGN KEY (FundingSourceId) REFERENCES dbo.FundingPlatform_FundingSources (Id),
    CONSTRAINT FundingPlatform_FK_SourceDocuments_UploadedBy
        FOREIGN KEY (UploadedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_SourceDocuments_FileName
        CHECK (NULLIF(LTRIM(RTRIM(OriginalFileName)), N'') IS NOT NULL),
    CONSTRAINT FundingPlatform_CK_SourceDocuments_MimeType
        CHECK (NULLIF(LTRIM(RTRIM(MimeType)), N'') IS NOT NULL),
    CONSTRAINT FundingPlatform_CK_SourceDocuments_ContentLength
        CHECK (ContentLength BETWEEN 1 AND 26214400),
    CONSTRAINT FundingPlatform_CK_SourceDocuments_BlobNames
        CHECK (LEN(BlobContainer) BETWEEN 3 AND 63
               AND LEN(BlobObjectName) BETWEEN 1 AND 1024
               AND LEFT(BlobObjectName, 1) <> N'/'
               AND CHARINDEX(N'?', BlobObjectName) = 0
               AND CHARINDEX(N'#', BlobObjectName) = 0),
    CONSTRAINT FundingPlatform_CK_SourceDocuments_Statuses
        CHECK (StorageStatus BETWEEN 0 AND 3
               AND ScanStatus BETWEEN 0 AND 4
               AND ScanProvider BETWEEN 0 AND 1
               AND ExtractionStatus BETWEEN 0 AND 4
               AND ScanAttemptCount BETWEEN 1 AND 100),
    CONSTRAINT FundingPlatform_CK_SourceDocuments_QuarantineReceipt
        CHECK ((StorageStatus = 0 AND BlobETag IS NULL AND BlobVersionId IS NULL)
               OR StorageStatus = 3
               OR (StorageStatus IN (1, 2)
                   AND NULLIF(LTRIM(RTRIM(BlobETag)), N'') IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_SourceDocuments_TrustedState
        CHECK ((ScanStatus = 1 AND StorageStatus = 2
                AND NULLIF(LTRIM(RTRIM(TrustedBlobContainer)), N'') IS NOT NULL
                AND NULLIF(LTRIM(RTRIM(TrustedBlobObjectName)), N'') IS NOT NULL
                AND NULLIF(LTRIM(RTRIM(TrustedBlobETag)), N'') IS NOT NULL)
               OR (ScanStatus <> 1 AND StorageStatus <> 2
                   AND TrustedBlobContainer IS NULL
                   AND TrustedBlobObjectName IS NULL
                   AND TrustedBlobETag IS NULL)),
    CONSTRAINT FundingPlatform_CK_SourceDocuments_ScanTimes
        CHECK ((ScanStatus = 0 AND ScanCompletedAtUtc IS NULL)
               OR (ScanStatus BETWEEN 1 AND 4 AND ScanCompletedAtUtc IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_SourceDocuments_Timestamps
        CHECK (UpdatedAtUtc >= CreatedAtUtc
               AND (ScanStartedAtUtc IS NULL OR ScanStartedAtUtc >= CreatedAtUtc)
               AND (ScanCompletedAtUtc IS NULL OR ScanStartedAtUtc IS NULL
                    OR ScanCompletedAtUtc >= ScanStartedAtUtc)),
    CONSTRAINT FundingPlatform_CK_SourceDocuments_ResultCode
        CHECK (ScanResultCode IS NULL
               OR (NULLIF(LTRIM(RTRIM(ScanResultCode)), N'') IS NOT NULL
                   AND CHARINDEX(CHAR(10), ScanResultCode) = 0
                   AND CHARINDEX(CHAR(13), ScanResultCode) = 0))
);

CREATE UNIQUE INDEX FundingPlatform_UQ_SourceDocuments_TrustedBlob
    ON dbo.FundingPlatform_SourceDocuments (TrustedBlobContainer, TrustedBlobObjectName)
    WHERE TrustedBlobContainer IS NOT NULL AND TrustedBlobObjectName IS NOT NULL;

CREATE INDEX FundingPlatform_IX_SourceDocuments_ContentHash
    ON dbo.FundingPlatform_SourceDocuments (ContentHash, FundingSourceId, Id)
    INCLUDE (PublicId, MimeType, ContentLength, ScanStatus, StorageStatus);

CREATE INDEX FundingPlatform_IX_SourceDocuments_ScanQueue
    ON dbo.FundingPlatform_SourceDocuments (ScanStatus, StorageStatus, CreatedAtUtc, Id)
    INCLUDE (PublicId, ScanProvider, ScanAttemptCount)
    WHERE ScanStatus = 0;

CREATE TABLE dbo.FundingPlatform_SourceDocumentUploadIntents
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocumentUploadIntents_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    FundingSourceId INT NOT NULL,
    OriginalFileName NVARCHAR(260) NOT NULL,
    BlobContainer NVARCHAR(63) NOT NULL,
    BlobObjectName NVARCHAR(1024) NOT NULL,
    QuarantineBlobContainer NVARCHAR(63) NOT NULL,
    QuarantineBlobObjectName NVARCHAR(1024) NOT NULL,
    CompletionTokenHash BINARY(32) NOT NULL,
    DeclaredMimeType NVARCHAR(100) NOT NULL,
    ExpectedContentLength BIGINT NOT NULL,
    MaxContentLength BIGINT NOT NULL,
    Status TINYINT NOT NULL,
    ExpiresAtUtc DATETIME2(3) NOT NULL,
    UploadedByUserId BIGINT NOT NULL,
    FinalizeAttemptCount SMALLINT NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocumentUploadIntents_Attempts DEFAULT (0),
    FinalizeLeaseId UNIQUEIDENTIFIER NULL,
    FinalizeLeaseUntilUtc DATETIME2(3) NULL,
    CompletedSourceDocumentId BIGINT NULL,
    CompletedAtUtc DATETIME2(3) NULL,
    LastErrorCode NVARCHAR(100) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocumentUploadIntents_CreatedAtUtc
        DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_SourceDocumentUploadIntents_UpdatedAtUtc
        DEFAULT (SYSUTCDATETIME()),
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_SourceDocumentUploadIntents PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentUploadIntents_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentUploadIntents_Token
        UNIQUE (CompletionTokenHash),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentUploadIntents_IncomingBlob
        UNIQUE (BlobContainer, BlobObjectName),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentUploadIntents_QuarantineBlob
        UNIQUE (QuarantineBlobContainer, QuarantineBlobObjectName),
    CONSTRAINT FundingPlatform_FK_SourceDocumentUploadIntents_Source
        FOREIGN KEY (FundingSourceId) REFERENCES dbo.FundingPlatform_FundingSources (Id),
    CONSTRAINT FundingPlatform_FK_SourceDocumentUploadIntents_User
        FOREIGN KEY (UploadedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_SourceDocumentUploadIntents_Document
        FOREIGN KEY (CompletedSourceDocumentId, FundingSourceId)
        REFERENCES dbo.FundingPlatform_SourceDocuments (Id, FundingSourceId),
    CONSTRAINT FundingPlatform_CK_SourceDocumentUploadIntents_File
        CHECK (NULLIF(LTRIM(RTRIM(OriginalFileName)), N'') IS NOT NULL
               AND RIGHT(LOWER(OriginalFileName), 4) = N'.pdf'
               AND LOWER(DeclaredMimeType) = N'application/pdf'),
    CONSTRAINT FundingPlatform_CK_SourceDocumentUploadIntents_Length
        CHECK (ExpectedContentLength BETWEEN 1 AND MaxContentLength
               AND MaxContentLength BETWEEN 1 AND 26214400),
    CONSTRAINT FundingPlatform_CK_SourceDocumentUploadIntents_BlobNames
        CHECK (LEN(BlobContainer) BETWEEN 3 AND 63
               AND LEN(QuarantineBlobContainer) BETWEEN 3 AND 63
               AND LEN(BlobObjectName) BETWEEN 1 AND 1024
               AND LEN(QuarantineBlobObjectName) BETWEEN 1 AND 1024
               AND LEFT(BlobObjectName, 1) <> N'/'
               AND LEFT(QuarantineBlobObjectName, 1) <> N'/'
               AND CHARINDEX(N'?', BlobObjectName) = 0
               AND CHARINDEX(N'#', BlobObjectName) = 0
               AND CHARINDEX(N'?', QuarantineBlobObjectName) = 0
               AND CHARINDEX(N'#', QuarantineBlobObjectName) = 0
               AND NOT (BlobContainer = QuarantineBlobContainer
                        AND BlobObjectName = QuarantineBlobObjectName)),
    CONSTRAINT FundingPlatform_CK_SourceDocumentUploadIntents_Status
        CHECK (Status BETWEEN 0 AND 4 AND FinalizeAttemptCount BETWEEN 0 AND 100),
    CONSTRAINT FundingPlatform_CK_SourceDocumentUploadIntents_State
        CHECK ((Status = 0 AND FinalizeLeaseId IS NULL AND FinalizeLeaseUntilUtc IS NULL
                AND CompletedSourceDocumentId IS NULL AND CompletedAtUtc IS NULL)
               OR (Status = 1 AND FinalizeLeaseId IS NOT NULL AND FinalizeLeaseUntilUtc IS NOT NULL
                   AND CompletedSourceDocumentId IS NULL AND CompletedAtUtc IS NULL)
               OR (Status = 2 AND FinalizeLeaseId IS NULL AND FinalizeLeaseUntilUtc IS NULL
                   AND CompletedSourceDocumentId IS NOT NULL AND CompletedAtUtc IS NOT NULL)
               OR (Status IN (3, 4) AND FinalizeLeaseId IS NULL
                   AND FinalizeLeaseUntilUtc IS NULL
                   AND CompletedSourceDocumentId IS NULL AND CompletedAtUtc IS NULL)),
    CONSTRAINT FundingPlatform_CK_SourceDocumentUploadIntents_Timestamps
        CHECK (ExpiresAtUtc > CreatedAtUtc AND UpdatedAtUtc >= CreatedAtUtc
               AND (FinalizeLeaseUntilUtc IS NULL OR FinalizeLeaseUntilUtc > UpdatedAtUtc)
               AND (CompletedAtUtc IS NULL OR CompletedAtUtc >= CreatedAtUtc)),
    CONSTRAINT FundingPlatform_CK_SourceDocumentUploadIntents_ErrorCode
        CHECK (LastErrorCode IS NULL
               OR (NULLIF(LTRIM(RTRIM(LastErrorCode)), N'') IS NOT NULL
                   AND CHARINDEX(CHAR(10), LastErrorCode) = 0
                   AND CHARINDEX(CHAR(13), LastErrorCode) = 0))
);

CREATE UNIQUE INDEX FundingPlatform_UQ_SourceDocumentUploadIntents_CompletedDocument
    ON dbo.FundingPlatform_SourceDocumentUploadIntents (CompletedSourceDocumentId)
    WHERE CompletedSourceDocumentId IS NOT NULL;

CREATE INDEX FundingPlatform_IX_SourceDocumentUploadIntents_StatusExpiry
    ON dbo.FundingPlatform_SourceDocumentUploadIntents (Status, ExpiresAtUtc, Id)
    INCLUDE (PublicId, UploadedByUserId, FundingSourceId, FinalizeLeaseUntilUtc);

CREATE TABLE dbo.FundingPlatform_SourceDocumentScanEvents
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    EventId UNIQUEIDENTIFIER NOT NULL,
    SourceDocumentId BIGINT NOT NULL,
    ScanProvider TINYINT NOT NULL,
    ProviderEventId NVARCHAR(200) NOT NULL,
    PayloadHash BINARY(32) NOT NULL,
    FromStatus TINYINT NOT NULL,
    ToStatus TINYINT NOT NULL,
    BlobETag NVARCHAR(100) NOT NULL,
    ReportedContentHash BINARY(32) NULL,
    ResultCode NVARCHAR(100) NOT NULL,
    ActorUserId BIGINT NULL,
    IdempotencyKeyHash BINARY(32) NULL,
    RequestHash BINARY(32) NULL,
    ResultRowVersion BINARY(8) NOT NULL,
    ResultScanAttemptCount SMALLINT NOT NULL,
    OccurredAtUtc DATETIME2(3) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_SourceDocumentScanEvents PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentScanEvents_EventId UNIQUE (EventId),
    CONSTRAINT FundingPlatform_UQ_SourceDocumentScanEvents_ProviderEvent
        UNIQUE (ScanProvider, ProviderEventId),
    CONSTRAINT FundingPlatform_FK_SourceDocumentScanEvents_Document
        FOREIGN KEY (SourceDocumentId) REFERENCES dbo.FundingPlatform_SourceDocuments (Id),
    CONSTRAINT FundingPlatform_FK_SourceDocumentScanEvents_Actor
        FOREIGN KEY (ActorUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_SourceDocumentScanEvents_Status
        CHECK (ScanProvider BETWEEN 0 AND 1
               AND ((FromStatus = 0 AND ToStatus BETWEEN 1 AND 4
                     AND ActorUserId IS NULL
                     AND IdempotencyKeyHash IS NULL AND RequestHash IS NULL)
                    OR (FromStatus IN (3, 4) AND ToStatus = 0
                        AND ActorUserId IS NOT NULL
                        AND IdempotencyKeyHash IS NOT NULL AND RequestHash IS NOT NULL))),
    CONSTRAINT FundingPlatform_CK_SourceDocumentScanEvents_Result
        CHECK (NULLIF(LTRIM(RTRIM(ProviderEventId)), N'') IS NOT NULL
               AND NULLIF(LTRIM(RTRIM(BlobETag)), N'') IS NOT NULL
               AND NULLIF(LTRIM(RTRIM(ResultCode)), N'') IS NOT NULL
               AND CHARINDEX(CHAR(10), ResultCode) = 0
               AND CHARINDEX(CHAR(13), ResultCode) = 0
               AND ResultScanAttemptCount BETWEEN 1 AND 100
               AND (ToStatus IN (0, 3, 4) OR ReportedContentHash IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_SourceDocumentScanEvents_Timestamps
        CHECK (OccurredAtUtc >= DATEADD(DAY, -1, CreatedAtUtc)
               AND OccurredAtUtc <= DATEADD(MINUTE, 5, CreatedAtUtc))
);

CREATE INDEX FundingPlatform_IX_SourceDocumentScanEvents_DocumentCreated
    ON dbo.FundingPlatform_SourceDocumentScanEvents (SourceDocumentId, CreatedAtUtc DESC, Id DESC)
    INCLUDE (EventId, ScanProvider, FromStatus, ToStatus, ResultCode, OccurredAtUtc);

CREATE UNIQUE INDEX FundingPlatform_UQ_SourceDocumentScanEvents_ActorRetryKey
    ON dbo.FundingPlatform_SourceDocumentScanEvents (ActorUserId, IdempotencyKeyHash)
    WHERE ActorUserId IS NOT NULL AND IdempotencyKeyHash IS NOT NULL;

/* The file source is technical provenance, not the canonical funder. */
INSERT INTO dbo.FundingPlatform_FundingSources
    (Name, ProviderType, BaseUrl, IsEnabled, ScheduleCron, MinimumDelaySeconds,
     UserAgent, TermsUrl, TermsReviewedAtUtc, RobotsReviewedAtUtc,
     LastSuccessfulRunAtUtc, ConfigurationJson, SecretReference,
     CreatedAtUtc, UpdatedAtUtc)
SELECT N'Manual document upload', 4, NULL, 1, NULL, NULL,
       NULL, NULL, NULL, NULL, NULL,
       N'{"uploadMode":"administrative","maxBytes":26214400}', NULL,
       SYSUTCDATETIME(), SYSUTCDATETIME()
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_FundingSources
    WHERE Name = N'Manual document upload'
);
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentUploadIntent_Create
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FundingSourceId INT,
    @OriginalFileName NVARCHAR(260),
    @DeclaredMimeType NVARCHAR(100),
    @ExpectedContentLength BIGINT,
    @MaxContentLength BIGINT,
    @BlobContainer NVARCHAR(63),
    @BlobObjectName NVARCHAR(1024),
    @QuarantineBlobContainer NVARCHAR(63),
    @QuarantineBlobObjectName NVARCHAR(1024),
    @CompletionTokenHash BINARY(32),
    @ExpiresAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    SET XACT_ABORT ON;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @ActorUserId BIGINT;
    DECLARE @IntentId BIGINT;
    DECLARE @IntentPublicId UNIQUEIDENTIFIER;
    DECLARE @RowVersion BINARY(8);
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF NULLIF(LTRIM(RTRIM(@OriginalFileName)), N'') IS NULL
       OR RIGHT(LOWER(@OriginalFileName), 4) <> N'.pdf'
       OR LOWER(COALESCE(@DeclaredMimeType, N'')) <> N'application/pdf'
       OR @ExpectedContentLength < 1
       OR @ExpectedContentLength > @MaxContentLength
       OR @MaxContentLength < 1
       OR @MaxContentLength > 26214400
       OR NULLIF(LTRIM(RTRIM(@BlobContainer)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@BlobObjectName)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@QuarantineBlobContainer)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@QuarantineBlobObjectName)), N'') IS NULL
       OR LEN(@BlobContainer) NOT BETWEEN 3 AND 63
       OR LEN(@QuarantineBlobContainer) NOT BETWEEN 3 AND 63
       OR LEN(@BlobObjectName) NOT BETWEEN 1 AND 1024
       OR LEN(@QuarantineBlobObjectName) NOT BETWEEN 1 AND 1024
       OR LEFT(@BlobObjectName, 1) = N'/'
       OR LEFT(@QuarantineBlobObjectName, 1) = N'/'
       OR CHARINDEX(N'?', @BlobObjectName) > 0
       OR CHARINDEX(N'#', @BlobObjectName) > 0
       OR CHARINDEX(N'?', @QuarantineBlobObjectName) > 0
       OR CHARINDEX(N'#', @QuarantineBlobObjectName) > 0
       OR (@BlobContainer = @QuarantineBlobContainer
           AND @BlobObjectName = @QuarantineBlobObjectName)
       OR @CompletionTokenHash IS NULL
       OR @ExpiresAtUtc <= @NowUtc
       OR @ExpiresAtUtc > DATEADD(MINUTE, 15, @NowUtc)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               CAST(NULL AS UNIQUEIDENTIFIER) AS IntentPublicId,
               CAST(NULL AS TINYINT) AS Status, CAST(NULL AS DATETIME2(3)) AS ExpiresAtUtc,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_CreateUpload;

    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.FundingPlatform_FundingSources WITH (UPDLOCK, HOLDLOCK)
            WHERE Id = @FundingSourceId AND IsEnabled = 1 AND ProviderType IN (0, 4)
        )
        BEGIN
            IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
            SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-source' AS Code,
                   CAST(NULL AS UNIQUEIDENTIFIER) AS IntentPublicId,
                   CAST(NULL AS TINYINT) AS Status, CAST(NULL AS DATETIME2(3)) AS ExpiresAtUtc,
                   CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
            RETURN;
        END;

        DECLARE @Inserted TABLE
        (
            Id BIGINT NOT NULL,
            PublicId UNIQUEIDENTIFIER NOT NULL,
            RowVersion BINARY(8) NOT NULL
        );

        INSERT INTO dbo.FundingPlatform_SourceDocumentUploadIntents
            (FundingSourceId, OriginalFileName, BlobContainer, BlobObjectName,
             QuarantineBlobContainer, QuarantineBlobObjectName, CompletionTokenHash,
             DeclaredMimeType, ExpectedContentLength, MaxContentLength, Status,
             ExpiresAtUtc, UploadedByUserId, CreatedAtUtc, UpdatedAtUtc)
        OUTPUT inserted.Id, inserted.PublicId, inserted.RowVersion
            INTO @Inserted (Id, PublicId, RowVersion)
        VALUES
            (@FundingSourceId, LTRIM(RTRIM(@OriginalFileName)), @BlobContainer, @BlobObjectName,
             @QuarantineBlobContainer, @QuarantineBlobObjectName, @CompletionTokenHash,
             N'application/pdf', @ExpectedContentLength, @MaxContentLength, 0,
             @ExpiresAtUtc, @ActorUserId, @NowUtc, @NowUtc);

        SELECT @IntentId = Id, @IntentPublicId = PublicId, @RowVersion = RowVersion
        FROM @Inserted;

        INSERT INTO dbo.FundingPlatform_OutboxMessages
            (MessageType, AggregateType, AggregateId, PayloadJson,
             OccurredAtUtc, AvailableAtUtc)
        SELECT N'SourceDocumentUploadIntentCreated', N'SourceDocumentUploadIntent',
               CONVERT(NVARCHAR(100), @IntentPublicId),
               (SELECT @IntentPublicId AS intentPublicId, @FundingSourceId AS fundingSourceId,
                       CAST(0 AS TINYINT) AS status
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
               @NowUtc, @NowUtc;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        SELECT CAST(1 AS BIT) AS Succeeded, N'created' AS Code,
               @IntentPublicId AS IntentPublicId, CAST(0 AS TINYINT) AS Status,
               @ExpiresAtUtc AS ExpiresAtUtc, @RowVersion AS RowVersion,
               CAST(0 AS BIT) AS WasReplay;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_CreateUpload;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocument_MarkQuarantined
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @SourceDocumentPublicId UNIQUEIDENTIFIER,
    @BlobETag NVARCHAR(100),
    @BlobVersionId NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    SET XACT_ABORT ON;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @ActorUserId BIGINT;
    DECLARE @DocumentId BIGINT;
    DECLARE @StorageStatus TINYINT;
    DECLARE @ScanStatus TINYINT;
    DECLARE @ScanProvider TINYINT;
    DECLARE @StoredBlobETag NVARCHAR(100);
    DECLARE @StoredBlobVersionId NVARCHAR(200);
    DECLARE @RowVersion BINARY(8);
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @Succeeded BIT = 0;
    DECLARE @WasReplay BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    SET @BlobETag = LTRIM(RTRIM(@BlobETag));
    SET @BlobVersionId = NULLIF(LTRIM(RTRIM(@BlobVersionId)), N'');
    IF NULLIF(@BlobETag, N'') IS NULL OR LEN(@BlobETag) > 100
       OR LEN(COALESCE(@BlobVersionId, N'')) > 200
       OR CHARINDEX(CHAR(10), @BlobETag) > 0
       OR CHARINDEX(CHAR(13), @BlobETag) > 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               @SourceDocumentPublicId AS SourceDocumentPublicId,
               CAST(NULL AS TINYINT) AS StorageStatus,
               CAST(NULL AS TINYINT) AS ScanStatus,
               CAST(NULL AS TINYINT) AS ScanProvider,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_MarkQuarantine;

    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;

        SELECT @DocumentId = Id, @StorageStatus = StorageStatus,
               @ScanStatus = ScanStatus, @ScanProvider = ScanProvider,
               @StoredBlobETag = BlobETag, @StoredBlobVersionId = BlobVersionId,
               @RowVersion = RowVersion
        FROM dbo.FundingPlatform_SourceDocuments WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @SourceDocumentPublicId;

        IF @DocumentId IS NULL
        BEGIN
            SET @Code = N'not-found';
        END
        ELSE IF @StorageStatus = 0 AND @ScanStatus = 0
        BEGIN
            DECLARE @Updated TABLE (RowVersion BINARY(8) NOT NULL);
            UPDATE dbo.FundingPlatform_SourceDocuments
            SET BlobETag = @BlobETag,
                BlobVersionId = @BlobVersionId,
                StorageStatus = 1,
                ScanStartedAtUtc = COALESCE(ScanStartedAtUtc, @NowUtc),
                UpdatedAtUtc = @NowUtc
            OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
            WHERE Id = @DocumentId;
            SELECT @RowVersion = RowVersion FROM @Updated;
            SET @StorageStatus = 1;
            SET @Succeeded = 1;
            SET @Code = N'quarantined';

            INSERT INTO dbo.FundingPlatform_OutboxMessages
                (MessageType, AggregateType, AggregateId, PayloadJson,
                 OccurredAtUtc, AvailableAtUtc)
            SELECT N'SourceDocumentQuarantined', N'SourceDocument',
                   CONVERT(NVARCHAR(100), @SourceDocumentPublicId),
                   (SELECT @SourceDocumentPublicId AS sourceDocumentPublicId,
                           @StorageStatus AS storageStatus, @ScanStatus AS scanStatus,
                           @ScanProvider AS scanProvider
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                   @NowUtc, @NowUtc;
        END
        ELSE IF @StorageStatus IN (1, 2)
             AND @StoredBlobETag = @BlobETag
             AND ((@StoredBlobVersionId IS NULL AND @BlobVersionId IS NULL)
                  OR @StoredBlobVersionId = @BlobVersionId)
        BEGIN
            SET @Succeeded = 1;
            SET @Code = CASE WHEN @StorageStatus = 2 THEN N'trusted' ELSE N'quarantined' END;
            SET @WasReplay = 1;
        END
        ELSE
        BEGIN
            SET @Code = N'blob-receipt-conflict';
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        SELECT @Succeeded AS Succeeded, @Code AS Code,
               @SourceDocumentPublicId AS SourceDocumentPublicId,
               @StorageStatus AS StorageStatus, @ScanStatus AS ScanStatus,
               @ScanProvider AS ScanProvider, @RowVersion AS RowVersion,
               @WasReplay AS WasReplay;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_MarkQuarantine;
        THROW;
    END CATCH;
END;
GO

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

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @DocumentId BIGINT;
    DECLARE @CurrentStorageStatus TINYINT;
    DECLARE @CurrentScanStatus TINYINT;
    DECLARE @StoredScanProvider TINYINT;
    DECLARE @StoredBlobETag NVARCHAR(100);
    DECLARE @StoredContentHash BINARY(32);
    DECLARE @ScanAttemptCount SMALLINT;
    DECLARE @DocumentCreatedAtUtc DATETIME2(3);
    DECLARE @RowVersion BINARY(8);
    DECLARE @ExistingDocumentId BIGINT;
    DECLARE @ExistingPayloadHash BINARY(32);
    DECLARE @ExistingToStatus TINYINT;
    DECLARE @ExistingBlobETag NVARCHAR(100);
    DECLARE @ExistingReportedHash BINARY(32);
    DECLARE @ExistingResultCode NVARCHAR(100);
    DECLARE @ExistingResultRowVersion BINARY(8);
    DECLARE @ExistingResultScanAttemptCount SMALLINT;
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @Succeeded BIT = 0;
    DECLARE @WasReplay BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    SET @ProviderEventId = LTRIM(RTRIM(@ProviderEventId));
    SET @BlobETag = LTRIM(RTRIM(@BlobETag));
    SET @ResultCode = LTRIM(RTRIM(@ResultCode));
    SET @TrustedBlobContainer = NULLIF(LTRIM(RTRIM(@TrustedBlobContainer)), N'');
    SET @TrustedBlobObjectName = NULLIF(LTRIM(RTRIM(@TrustedBlobObjectName)), N'');
    SET @TrustedBlobETag = NULLIF(LTRIM(RTRIM(@TrustedBlobETag)), N'');

    IF @ScanProvider NOT BETWEEN 0 AND 1
       OR NULLIF(@ProviderEventId, N'') IS NULL OR LEN(@ProviderEventId) > 200
       OR @PayloadHash IS NULL
       OR NULLIF(@BlobETag, N'') IS NULL OR LEN(@BlobETag) > 100
       OR @ToStatus NOT BETWEEN 1 AND 4
       OR NULLIF(@ResultCode, N'') IS NULL OR LEN(@ResultCode) > 100
       OR CHARINDEX(CHAR(10), @ResultCode) > 0
       OR CHARINDEX(CHAR(13), @ResultCode) > 0
       OR @OccurredAtUtc IS NULL
       OR (@ToStatus IN (1, 2) AND @ReportedContentHash IS NULL)
       OR (@ToStatus = 1 AND
           (@TrustedBlobContainer IS NULL OR @TrustedBlobObjectName IS NULL
            OR @TrustedBlobETag IS NULL))
       OR (@ToStatus <> 1 AND
           (@TrustedBlobContainer IS NOT NULL OR @TrustedBlobObjectName IS NOT NULL
            OR @TrustedBlobETag IS NOT NULL))
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
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_ApplyScan;

    BEGIN TRY
        SELECT @ExistingDocumentId = SourceDocumentId,
               @ExistingPayloadHash = PayloadHash,
               @ExistingToStatus = ToStatus,
               @ExistingBlobETag = BlobETag,
               @ExistingReportedHash = ReportedContentHash,
               @ExistingResultCode = ResultCode,
               @ExistingResultRowVersion = ResultRowVersion,
               @ExistingResultScanAttemptCount = ResultScanAttemptCount
        FROM dbo.FundingPlatform_SourceDocumentScanEvents WITH (UPDLOCK, HOLDLOCK)
        WHERE ScanProvider = @ScanProvider AND ProviderEventId = @ProviderEventId;

        SELECT @DocumentId = Id,
               @CurrentStorageStatus = StorageStatus,
               @CurrentScanStatus = ScanStatus,
               @StoredScanProvider = ScanProvider,
               @StoredBlobETag = BlobETag,
               @StoredContentHash = ContentHash,
               @ScanAttemptCount = ScanAttemptCount,
               @DocumentCreatedAtUtc = CreatedAtUtc,
               @RowVersion = RowVersion
        FROM dbo.FundingPlatform_SourceDocuments WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @SourceDocumentPublicId;

        IF @ExistingDocumentId IS NOT NULL
        BEGIN
            IF @DocumentId = @ExistingDocumentId
               AND @ExistingPayloadHash = @PayloadHash
               AND @ExistingToStatus = @ToStatus
               AND @ExistingBlobETag = @BlobETag
               AND @ExistingResultCode = @ResultCode
               AND ((@ExistingReportedHash IS NULL AND @ReportedContentHash IS NULL)
                    OR @ExistingReportedHash = @ReportedContentHash)
               AND (@ToStatus <> 1
                    OR EXISTS
                       (SELECT 1 FROM dbo.FundingPlatform_SourceDocuments
                        WHERE Id = @DocumentId
                          AND TrustedBlobContainer = @TrustedBlobContainer
                          AND TrustedBlobObjectName = @TrustedBlobObjectName
                          AND TrustedBlobETag = @TrustedBlobETag))
            BEGIN
                SET @Succeeded = 1;
                SET @Code = N'scan-result-applied';
                SET @WasReplay = 1;
                SET @CurrentStorageStatus = CASE WHEN @ExistingToStatus = 1 THEN 2 ELSE 1 END;
                SET @CurrentScanStatus = @ExistingToStatus;
                SET @RowVersion = @ExistingResultRowVersion;
                SET @ScanAttemptCount = @ExistingResultScanAttemptCount;
            END
            ELSE
            BEGIN
                SET @Code = N'event-conflict';
            END;
        END
        ELSE IF @DocumentId IS NULL
        BEGIN
            SET @Code = N'not-found';
        END
        ELSE IF @StoredScanProvider <> @ScanProvider
        BEGIN
            SET @Code = N'provider-mismatch';
        END
        ELSE IF @CurrentStorageStatus <> 1 OR @CurrentScanStatus <> 0
        BEGIN
            SET @Code = N'invalid-transition';
        END
        ELSE IF @StoredBlobETag <> @BlobETag
        BEGIN
            SET @Code = N'blob-etag-mismatch';
        END
        ELSE IF @OccurredAtUtc < @DocumentCreatedAtUtc
             OR @OccurredAtUtc > DATEADD(MINUTE, 5, @NowUtc)
        BEGIN
            SET @Code = N'invalid-event-time';
        END
        ELSE IF @ReportedContentHash IS NOT NULL
             AND @ReportedContentHash <> @StoredContentHash
        BEGIN
            SET @Code = N'content-hash-mismatch';
        END
        ELSE IF @ToStatus = 1
             AND EXISTS
             (
                 SELECT 1
                 FROM dbo.FundingPlatform_SourceDocuments
                 WHERE Id = @DocumentId
                   AND BlobContainer = @TrustedBlobContainer
                   AND BlobObjectName = @TrustedBlobObjectName
             )
        BEGIN
            SET @Code = N'invalid-trusted-location';
        END
        ELSE
        BEGIN
            DECLARE @EventId UNIQUEIDENTIFIER = NEWID();
            DECLARE @UpdatedDocument TABLE (RowVersion BINARY(8) NOT NULL);
            UPDATE dbo.FundingPlatform_SourceDocuments
            SET ScanStatus = @ToStatus,
                ScanResultCode = @ResultCode,
                ScanCompletedAtUtc = @NowUtc,
                StorageStatus = CASE WHEN @ToStatus = 1 THEN 2 ELSE StorageStatus END,
                TrustedBlobContainer = CASE WHEN @ToStatus = 1
                                            THEN @TrustedBlobContainer ELSE NULL END,
                TrustedBlobObjectName = CASE WHEN @ToStatus = 1
                                             THEN @TrustedBlobObjectName ELSE NULL END,
                TrustedBlobETag = CASE WHEN @ToStatus = 1
                                       THEN @TrustedBlobETag ELSE NULL END,
                UpdatedAtUtc = @NowUtc
            OUTPUT inserted.RowVersion INTO @UpdatedDocument (RowVersion)
            WHERE Id = @DocumentId;
            SELECT @RowVersion = RowVersion FROM @UpdatedDocument;

            INSERT INTO dbo.FundingPlatform_SourceDocumentScanEvents
                (EventId, SourceDocumentId, ScanProvider, ProviderEventId, PayloadHash,
                 FromStatus, ToStatus, BlobETag, ReportedContentHash, ResultCode,
                 ActorUserId, IdempotencyKeyHash, RequestHash, ResultRowVersion,
                 ResultScanAttemptCount,
                 OccurredAtUtc, CreatedAtUtc)
            VALUES
                (@EventId, @DocumentId, @ScanProvider, @ProviderEventId, @PayloadHash,
                 0, @ToStatus, @BlobETag, @ReportedContentHash, @ResultCode,
                 NULL, NULL, NULL, @RowVersion, @ScanAttemptCount,
                 @OccurredAtUtc, @NowUtc);

            SET @CurrentScanStatus = @ToStatus;
            SET @CurrentStorageStatus = CASE WHEN @ToStatus = 1 THEN 2 ELSE 1 END;
            SET @Succeeded = 1;
            SET @Code = N'scan-result-applied';

            INSERT INTO dbo.FundingPlatform_OutboxMessages
                (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                 OccurredAtUtc, AvailableAtUtc)
            SELECT @EventId, N'SourceDocumentScanCompleted', N'SourceDocument',
                   CONVERT(NVARCHAR(100), @SourceDocumentPublicId),
                   (SELECT @EventId AS eventId,
                           @SourceDocumentPublicId AS sourceDocumentPublicId,
                           @ScanProvider AS scanProvider,
                           @CurrentStorageStatus AS storageStatus,
                           @CurrentScanStatus AS scanStatus
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                   @NowUtc, @NowUtc;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        SELECT @Succeeded AS Succeeded, @Code AS Code,
               @SourceDocumentPublicId AS SourceDocumentPublicId,
               @CurrentStorageStatus AS StorageStatus,
               @CurrentScanStatus AS ScanStatus,
               @StoredScanProvider AS ScanProvider,
               @RowVersion AS RowVersion,
               @WasReplay AS WasReplay;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ApplyScan;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocument_RetryScan
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @SourceDocumentPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    SET XACT_ABORT ON;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @ActorUserId BIGINT;
    DECLARE @DocumentId BIGINT;
    DECLARE @StorageStatus TINYINT;
    DECLARE @ScanStatus TINYINT;
    DECLARE @ScanProvider TINYINT;
    DECLARE @ScanAttemptCount SMALLINT;
    DECLARE @BlobETag NVARCHAR(100);
    DECLARE @CurrentRowVersion BINARY(8);
    DECLARE @ExistingDocumentId BIGINT;
    DECLARE @ExistingRequestHash BINARY(32);
    DECLARE @ExistingResultRowVersion BINARY(8);
    DECLARE @ExistingResultScanAttemptCount SMALLINT;
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @Succeeded BIT = 0;
    DECLARE @WasReplay BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @ExpectedRowVersion IS NULL OR @IdempotencyKeyHash IS NULL OR @RequestHash IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               @SourceDocumentPublicId AS SourceDocumentPublicId,
               CAST(NULL AS TINYINT) AS StorageStatus,
               CAST(NULL AS TINYINT) AS ScanStatus,
               CAST(NULL AS TINYINT) AS ScanProvider,
               CAST(NULL AS SMALLINT) AS ScanAttemptCount,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_RetryScan;

    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;

        SELECT @DocumentId = Id, @StorageStatus = StorageStatus,
               @ScanStatus = ScanStatus, @ScanProvider = ScanProvider,
               @ScanAttemptCount = ScanAttemptCount, @BlobETag = BlobETag,
               @CurrentRowVersion = RowVersion
        FROM dbo.FundingPlatform_SourceDocuments WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @SourceDocumentPublicId;

        SELECT @ExistingDocumentId = SourceDocumentId,
               @ExistingRequestHash = RequestHash,
               @ExistingResultRowVersion = ResultRowVersion,
               @ExistingResultScanAttemptCount = ResultScanAttemptCount
        FROM dbo.FundingPlatform_SourceDocumentScanEvents WITH (UPDLOCK, HOLDLOCK)
        WHERE ActorUserId = @ActorUserId
          AND IdempotencyKeyHash = @IdempotencyKeyHash;

        IF @ExistingDocumentId IS NOT NULL
        BEGIN
            IF @ExistingDocumentId = @DocumentId AND @ExistingRequestHash = @RequestHash
            BEGIN
                SET @Succeeded = 1;
                SET @Code = N'scan-retry-requested';
                SET @WasReplay = 1;
                SET @StorageStatus = 1;
                SET @ScanStatus = 0;
                SET @ScanAttemptCount = @ExistingResultScanAttemptCount;
                SET @CurrentRowVersion = @ExistingResultRowVersion;
            END
            ELSE
            BEGIN
                SET @Code = N'idempotency-conflict';
            END;
        END
        ELSE IF @DocumentId IS NULL
        BEGIN
            SET @Code = N'not-found';
        END
        ELSE IF @CurrentRowVersion <> @ExpectedRowVersion
        BEGIN
            SET @Code = N'etag-conflict';
        END
        ELSE IF @StorageStatus <> 1 OR @ScanStatus NOT IN (3, 4)
        BEGIN
            SET @Code = N'invalid-transition';
        END
        ELSE IF @ScanAttemptCount >= 100
        BEGIN
            SET @Code = N'retry-limit-reached';
        END
        ELSE
        BEGIN
            DECLARE @FromStatus TINYINT = @ScanStatus;
            DECLARE @EventId UNIQUEIDENTIFIER = NEWID();
            DECLARE @UpdatedDocument TABLE (RowVersion BINARY(8) NOT NULL);

            UPDATE dbo.FundingPlatform_SourceDocuments
            SET ScanStatus = 0,
                ScanAttemptCount = ScanAttemptCount + 1,
                ScanResultCode = NULL,
                ScanStartedAtUtc = @NowUtc,
                ScanCompletedAtUtc = NULL,
                UpdatedAtUtc = @NowUtc
            OUTPUT inserted.RowVersion INTO @UpdatedDocument (RowVersion)
            WHERE Id = @DocumentId AND RowVersion = @ExpectedRowVersion;

            SELECT @CurrentRowVersion = RowVersion FROM @UpdatedDocument;
            IF @CurrentRowVersion IS NULL
            BEGIN
                SET @Code = N'etag-conflict';
            END
            ELSE
            BEGIN
                SET @ScanStatus = 0;
                SET @ScanAttemptCount = @ScanAttemptCount + 1;

                INSERT INTO dbo.FundingPlatform_SourceDocumentScanEvents
                    (EventId, SourceDocumentId, ScanProvider, ProviderEventId, PayloadHash,
                     FromStatus, ToStatus, BlobETag, ReportedContentHash, ResultCode,
                     ActorUserId, IdempotencyKeyHash, RequestHash, ResultRowVersion,
                     ResultScanAttemptCount,
                     OccurredAtUtc, CreatedAtUtc)
                VALUES
                    (@EventId, @DocumentId, @ScanProvider,
                     N'admin-retry:' + CONVERT(NVARCHAR(36), @EventId), @RequestHash,
                     @FromStatus, 0, @BlobETag, NULL, N'retry-requested',
                     @ActorUserId, @IdempotencyKeyHash, @RequestHash, @CurrentRowVersion,
                     @ScanAttemptCount,
                     @NowUtc, @NowUtc);

                INSERT INTO dbo.FundingPlatform_OutboxMessages
                    (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                     OccurredAtUtc, AvailableAtUtc)
                SELECT @EventId, N'SourceDocumentScanRetryRequested', N'SourceDocument',
                       CONVERT(NVARCHAR(100), @SourceDocumentPublicId),
                       (SELECT @EventId AS eventId,
                               @SourceDocumentPublicId AS sourceDocumentPublicId,
                               @ScanProvider AS scanProvider,
                               @ScanStatus AS scanStatus,
                               @ScanAttemptCount AS scanAttemptCount
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                       @NowUtc, @NowUtc;

                SET @Succeeded = 1;
                SET @Code = N'scan-retry-requested';
            END;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        SELECT @Succeeded AS Succeeded, @Code AS Code,
               @SourceDocumentPublicId AS SourceDocumentPublicId,
               @StorageStatus AS StorageStatus, @ScanStatus AS ScanStatus,
               @ScanProvider AS ScanProvider, @ScanAttemptCount AS ScanAttemptCount,
               @CurrentRowVersion AS RowVersion, @WasReplay AS WasReplay;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_RetryScan;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocument_AcquireScanWork
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @SourceDocumentPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    SET XACT_ABORT ON;

    DECLARE @ActorUserId BIGINT;
    DECLARE @DocumentId BIGINT;
    DECLARE @StorageStatus TINYINT;
    DECLARE @ScanStatus TINYINT;
    DECLARE @CurrentRowVersion BINARY(8);
    DECLARE @QuarantineBlobContainer NVARCHAR(63);
    DECLARE @QuarantineBlobObjectName NVARCHAR(1024);
    DECLARE @ContentLength BIGINT;
    DECLARE @ContentHash BINARY(32);
    DECLARE @BlobETag NVARCHAR(100);
    DECLARE @BlobVersionId NVARCHAR(200);
    DECLARE @ScanProvider TINYINT;
    DECLARE @ScanAttemptCount SMALLINT;
    DECLARE @ScanStartedAtUtc DATETIME2(3);
    DECLARE @CreatedAtUtc DATETIME2(3);
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @Succeeded BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @ExpectedRowVersion IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               @SourceDocumentPublicId AS SourceDocumentPublicId,
               CAST(NULL AS NVARCHAR(63)) AS QuarantineBlobContainer,
               CAST(NULL AS NVARCHAR(1024)) AS QuarantineBlobObjectName,
               CAST(NULL AS BIGINT) AS ContentLength,
               CAST(NULL AS BINARY(32)) AS ContentHash,
               CAST(NULL AS NVARCHAR(100)) AS BlobETag,
               CAST(NULL AS NVARCHAR(200)) AS BlobVersionId,
               CAST(NULL AS TINYINT) AS ScanProvider,
               CAST(NULL AS SMALLINT) AS ScanAttemptCount,
               CAST(NULL AS DATETIME2(3)) AS ScanStartedAtUtc,
               CAST(NULL AS DATETIME2(3)) AS CreatedAtUtc,
               CAST(NULL AS BINARY(8)) AS RowVersion;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_AcquireScanWork;

    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;

        SELECT @DocumentId = Id,
               @StorageStatus = StorageStatus,
               @ScanStatus = ScanStatus,
               @CurrentRowVersion = RowVersion,
               @QuarantineBlobContainer = BlobContainer,
               @QuarantineBlobObjectName = BlobObjectName,
               @ContentLength = ContentLength,
               @ContentHash = ContentHash,
               @BlobETag = BlobETag,
               @BlobVersionId = BlobVersionId,
               @ScanProvider = ScanProvider,
               @ScanAttemptCount = ScanAttemptCount,
               @ScanStartedAtUtc = ScanStartedAtUtc,
               @CreatedAtUtc = CreatedAtUtc
        FROM dbo.FundingPlatform_SourceDocuments WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @SourceDocumentPublicId;

        IF @DocumentId IS NULL
            SET @Code = N'not-found';
        ELSE IF @CurrentRowVersion <> @ExpectedRowVersion
            SET @Code = N'etag-conflict';
        ELSE IF @StorageStatus <> 1 OR @ScanStatus <> 0
            SET @Code = N'invalid-transition';
        ELSE
        BEGIN
            SET @Succeeded = 1;
            SET @Code = N'acquired';
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        SELECT @Succeeded AS Succeeded,
               @Code AS Code,
               @SourceDocumentPublicId AS SourceDocumentPublicId,
               CASE WHEN @Succeeded = 1 THEN @QuarantineBlobContainer END
                   AS QuarantineBlobContainer,
               CASE WHEN @Succeeded = 1 THEN @QuarantineBlobObjectName END
                   AS QuarantineBlobObjectName,
               CASE WHEN @Succeeded = 1 THEN @ContentLength END AS ContentLength,
               CASE WHEN @Succeeded = 1 THEN @ContentHash END AS ContentHash,
               CASE WHEN @Succeeded = 1 THEN @BlobETag END AS BlobETag,
               CASE WHEN @Succeeded = 1 THEN @BlobVersionId END AS BlobVersionId,
               CASE WHEN @Succeeded = 1 THEN @ScanProvider END AS ScanProvider,
               CASE WHEN @Succeeded = 1 THEN @ScanAttemptCount END AS ScanAttemptCount,
               CASE WHEN @Succeeded = 1 THEN @ScanStartedAtUtc END AS ScanStartedAtUtc,
               CASE WHEN @Succeeded = 1 THEN @CreatedAtUtc END AS CreatedAtUtc,
               @CurrentRowVersion AS RowVersion;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_AcquireScanWork;
        THROW;
    END CATCH;
END;
GO

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
           documents.FundingSourceId,
           sources.Name AS FundingSourceName,
           documents.OriginalFileName,
           documents.MimeType,
           documents.ContentLength,
           documents.StorageStatus,
           documents.ScanStatus,
           documents.ScanProvider,
           CAST(CASE WHEN documents.ScanProvider = 1 THEN 1 ELSE 0 END AS BIT)
               AS IsProductionScan,
           documents.ScanAttemptCount,
           documents.ScanResultCode,
           documents.ScanStartedAtUtc,
           documents.ScanCompletedAtUtc,
           documents.ExtractionStatus,
           uploaders.PublicId AS UploadedByUserPublicId,
           documents.CreatedAtUtc,
           documents.UpdatedAtUtc,
           documents.RowVersion
    FROM dbo.FundingPlatform_SourceDocuments AS documents
    INNER JOIN dbo.FundingPlatform_FundingSources AS sources
        ON sources.Id = documents.FundingSourceId
    INNER JOIN dbo.FundingPlatform_Users AS uploaders
        ON uploaders.Id = documents.UploadedByUserId
    WHERE documents.PublicId = @SourceDocumentPublicId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentUploadIntent_ReleaseFinalize
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @IntentPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @ErrorCode NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    SET XACT_ABORT ON;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @ActorUserId BIGINT;
    DECLARE @IntentId BIGINT;
    DECLARE @Status TINYINT;
    DECLARE @ExpiresAtUtc DATETIME2(3);
    DECLARE @StoredLeaseId UNIQUEIDENTIFIER;
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @Succeeded BIT = 0;
    DECLARE @WasReplay BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @LeaseId IS NULL OR NULLIF(LTRIM(RTRIM(@ErrorCode)), N'') IS NULL
       OR LEN(@ErrorCode) > 100
       OR CHARINDEX(CHAR(10), @ErrorCode) > 0
       OR CHARINDEX(CHAR(13), @ErrorCode) > 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               @IntentPublicId AS IntentPublicId, CAST(NULL AS TINYINT) AS Status,
               CAST(NULL AS UNIQUEIDENTIFIER) AS SourceDocumentPublicId,
               CAST(NULL AS TINYINT) AS StorageStatus,
               CAST(NULL AS TINYINT) AS ScanStatus,
               CAST(NULL AS TINYINT) AS ScanProvider,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_ReleaseUpload;

    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;

        SELECT @IntentId = Id, @Status = Status, @ExpiresAtUtc = ExpiresAtUtc,
               @StoredLeaseId = FinalizeLeaseId
        FROM dbo.FundingPlatform_SourceDocumentUploadIntents WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @IntentPublicId;

        IF @IntentId IS NULL
        BEGIN
            SET @Code = N'not-found';
        END
        ELSE IF @Status = 2
        BEGIN
            SET @Succeeded = 1;
            SET @Code = N'completed';
            SET @WasReplay = 1;
        END
        ELSE IF @Status = 1 AND @StoredLeaseId = @LeaseId
        BEGIN
            SET @Status = CASE WHEN @ExpiresAtUtc <= @NowUtc THEN 3 ELSE 0 END;
            UPDATE dbo.FundingPlatform_SourceDocumentUploadIntents
            SET Status = @Status,
                FinalizeLeaseId = NULL,
                FinalizeLeaseUntilUtc = NULL,
                LastErrorCode = LEFT(LTRIM(RTRIM(@ErrorCode)), 100),
                UpdatedAtUtc = @NowUtc
            WHERE Id = @IntentId;
            SET @Succeeded = 1;
            SET @Code = CASE WHEN @Status = 3 THEN N'expired' ELSE N'released' END;

            IF @Status = 3
            BEGIN
                INSERT INTO dbo.FundingPlatform_OutboxMessages
                    (MessageType, AggregateType, AggregateId, PayloadJson,
                     OccurredAtUtc, AvailableAtUtc)
                SELECT N'SourceDocumentUploadIntentExpired', N'SourceDocumentUploadIntent',
                       CONVERT(NVARCHAR(100), @IntentPublicId),
                       (SELECT @IntentPublicId AS intentPublicId, @Status AS status
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                       @NowUtc, @NowUtc;
            END;
        END
        ELSE
        BEGIN
            SET @Code = N'lease-conflict';
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        SELECT @Succeeded AS Succeeded, @Code AS Code,
               intents.PublicId AS IntentPublicId, intents.Status,
               documents.PublicId AS SourceDocumentPublicId,
               documents.StorageStatus, documents.ScanStatus, documents.ScanProvider,
               intents.RowVersion, @WasReplay AS WasReplay
        FROM dbo.FundingPlatform_SourceDocumentUploadIntents AS intents
        LEFT JOIN dbo.FundingPlatform_SourceDocuments AS documents
            ON documents.Id = intents.CompletedSourceDocumentId
        WHERE intents.Id = @IntentId
        UNION ALL
        SELECT @Succeeded, @Code, @IntentPublicId, NULL, NULL, NULL, NULL, NULL, NULL,
               @WasReplay
        WHERE @IntentId IS NULL;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ReleaseUpload;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentUploadIntent_RejectFinalize
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @IntentPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @ErrorCode NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    SET XACT_ABORT ON;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @ActorUserId BIGINT;
    DECLARE @IntentId BIGINT;
    DECLARE @Status TINYINT;
    DECLARE @StoredLeaseId UNIQUEIDENTIFIER;
    DECLARE @StoredErrorCode NVARCHAR(100);
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @Succeeded BIT = 0;
    DECLARE @WasReplay BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    SET @ErrorCode = LEFT(LTRIM(RTRIM(@ErrorCode)), 100);
    IF @LeaseId IS NULL OR NULLIF(@ErrorCode, N'') IS NULL
       OR CHARINDEX(CHAR(10), @ErrorCode) > 0
       OR CHARINDEX(CHAR(13), @ErrorCode) > 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               @IntentPublicId AS IntentPublicId, CAST(NULL AS TINYINT) AS Status,
               CAST(NULL AS UNIQUEIDENTIFIER) AS SourceDocumentPublicId,
               CAST(NULL AS TINYINT) AS StorageStatus,
               CAST(NULL AS TINYINT) AS ScanStatus,
               CAST(NULL AS TINYINT) AS ScanProvider,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_RejectUpload;

    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;

        SELECT @IntentId = Id, @Status = Status, @StoredLeaseId = FinalizeLeaseId,
               @StoredErrorCode = LastErrorCode
        FROM dbo.FundingPlatform_SourceDocumentUploadIntents WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @IntentPublicId;

        IF @IntentId IS NULL
        BEGIN
            SET @Code = N'not-found';
        END
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
            UPDATE dbo.FundingPlatform_SourceDocumentUploadIntents
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
            SELECT N'SourceDocumentUploadIntentRejected', N'SourceDocumentUploadIntent',
                   CONVERT(NVARCHAR(100), @IntentPublicId),
                   (SELECT @IntentPublicId AS intentPublicId, CAST(4 AS TINYINT) AS status
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                   @NowUtc, @NowUtc;
        END
        ELSE
        BEGIN
            SET @Code = N'lease-conflict';
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        SELECT @Succeeded AS Succeeded, @Code AS Code,
               intents.PublicId AS IntentPublicId, intents.Status,
               documents.PublicId AS SourceDocumentPublicId,
               documents.StorageStatus, documents.ScanStatus, documents.ScanProvider,
               intents.RowVersion, @WasReplay AS WasReplay
        FROM dbo.FundingPlatform_SourceDocumentUploadIntents AS intents
        LEFT JOIN dbo.FundingPlatform_SourceDocuments AS documents
            ON documents.Id = intents.CompletedSourceDocumentId
        WHERE intents.Id = @IntentId
        UNION ALL
        SELECT @Succeeded, @Code, @IntentPublicId, NULL, NULL, NULL, NULL, NULL, NULL,
               @WasReplay
        WHERE @IntentId IS NULL;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_RejectUpload;
        THROW;
    END CATCH;
END;
GO

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

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @ActorUserId BIGINT;
    DECLARE @IntentId BIGINT;
    DECLARE @FundingSourceId INT;
    DECLARE @OriginalFileName NVARCHAR(260);
    DECLARE @QuarantineBlobContainer NVARCHAR(63);
    DECLARE @QuarantineBlobObjectName NVARCHAR(1024);
    DECLARE @ExpectedContentLength BIGINT;
    DECLARE @MaxContentLength BIGINT;
    DECLARE @UploadedByUserId BIGINT;
    DECLARE @Status TINYINT;
    DECLARE @StoredLeaseId UNIQUEIDENTIFIER;
    DECLARE @StoredLeaseUntilUtc DATETIME2(3);
    DECLARE @DocumentId BIGINT;
    DECLARE @DocumentPublicId UNIQUEIDENTIFIER;
    DECLARE @StorageStatus TINYINT;
    DECLARE @ScanStatus TINYINT;
    DECLARE @StoredScanProvider TINYINT;
    DECLARE @RowVersion BINARY(8);
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @Succeeded BIT = 0;
    DECLARE @WasReplay BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @LeaseId IS NULL
       OR LOWER(COALESCE(@VerifiedMimeType, N'')) <> N'application/pdf'
       OR @ActualContentLength < 1 OR @ActualContentLength > 26214400
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

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_CompleteUpload;

    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;

        SELECT @IntentId = Id,
               @FundingSourceId = FundingSourceId,
               @OriginalFileName = OriginalFileName,
               @QuarantineBlobContainer = QuarantineBlobContainer,
               @QuarantineBlobObjectName = QuarantineBlobObjectName,
               @ExpectedContentLength = ExpectedContentLength,
               @MaxContentLength = MaxContentLength,
               @UploadedByUserId = UploadedByUserId,
               @Status = Status,
               @StoredLeaseId = FinalizeLeaseId,
               @StoredLeaseUntilUtc = FinalizeLeaseUntilUtc,
               @DocumentId = CompletedSourceDocumentId
        FROM dbo.FundingPlatform_SourceDocumentUploadIntents WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @IntentPublicId;

        IF @IntentId IS NULL
        BEGIN
            SET @Code = N'not-found';
        END
        ELSE IF @Status = 2
        BEGIN
            SELECT @DocumentPublicId = PublicId, @StorageStatus = StorageStatus,
                   @ScanStatus = ScanStatus, @StoredScanProvider = ScanProvider,
                   @RowVersion = RowVersion
            FROM dbo.FundingPlatform_SourceDocuments WITH (UPDLOCK, HOLDLOCK)
            WHERE Id = @DocumentId
              AND MimeType = N'application/pdf'
              AND ContentLength = @ActualContentLength
              AND ContentHash = @ContentHash
              AND ScanProvider = @ScanProvider;

            IF @DocumentPublicId IS NULL
                SET @Code = N'completion-conflict';
            ELSE
            BEGIN
                SET @Succeeded = 1;
                SET @Code = N'completed';
                SET @WasReplay = 1;
            END;
        END
        ELSE IF @Status <> 1 OR @StoredLeaseId <> @LeaseId
        BEGIN
            SET @Code = N'lease-conflict';
        END
        ELSE IF @StoredLeaseUntilUtc <= @NowUtc
        BEGIN
            SET @Code = N'lease-expired';
        END
        ELSE IF @ActualContentLength <> @ExpectedContentLength
             OR @ActualContentLength > @MaxContentLength
        BEGIN
            SET @Code = N'length-mismatch';
        END
        ELSE
        BEGIN
            DECLARE @InsertedDocument TABLE
            (
                Id BIGINT NOT NULL,
                PublicId UNIQUEIDENTIFIER NOT NULL,
                RowVersion BINARY(8) NOT NULL
            );

            INSERT INTO dbo.FundingPlatform_SourceDocuments
                (FundingSourceId, OriginalFileName, MimeType, ContentLength, ContentHash,
                 BlobContainer, BlobObjectName, StorageStatus, ScanStatus, ScanProvider,
                 ScanAttemptCount, ExtractionStatus, UploadedByUserId,
                 CreatedAtUtc, UpdatedAtUtc)
            OUTPUT inserted.Id, inserted.PublicId, inserted.RowVersion
                INTO @InsertedDocument (Id, PublicId, RowVersion)
            VALUES
                (@FundingSourceId, @OriginalFileName, N'application/pdf',
                 @ActualContentLength, @ContentHash,
                 @QuarantineBlobContainer, @QuarantineBlobObjectName,
                 0, 0, @ScanProvider, 1, 0, @UploadedByUserId,
                 @NowUtc, @NowUtc);

            SELECT @DocumentId = Id, @DocumentPublicId = PublicId, @RowVersion = RowVersion
            FROM @InsertedDocument;
            SET @StorageStatus = 0;
            SET @ScanStatus = 0;
            SET @StoredScanProvider = @ScanProvider;

            UPDATE dbo.FundingPlatform_SourceDocumentUploadIntents
            SET Status = 2,
                FinalizeLeaseId = NULL,
                FinalizeLeaseUntilUtc = NULL,
                CompletedSourceDocumentId = @DocumentId,
                CompletedAtUtc = @NowUtc,
                LastErrorCode = NULL,
                UpdatedAtUtc = @NowUtc
            WHERE Id = @IntentId;

            INSERT INTO dbo.FundingPlatform_OutboxMessages
                (MessageType, AggregateType, AggregateId, PayloadJson,
                 OccurredAtUtc, AvailableAtUtc)
            SELECT N'SourceDocumentFinalized', N'SourceDocument',
                   CONVERT(NVARCHAR(100), @DocumentPublicId),
                   (SELECT @DocumentPublicId AS sourceDocumentPublicId,
                           @IntentPublicId AS intentPublicId,
                           @StoredScanProvider AS scanProvider,
                           @StorageStatus AS storageStatus,
                           @ScanStatus AS scanStatus
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                   @NowUtc, @NowUtc;

            SET @Succeeded = 1;
            SET @Code = N'completed';
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        SELECT @Succeeded AS Succeeded, @Code AS Code,
               @IntentPublicId AS IntentPublicId,
               @DocumentPublicId AS SourceDocumentPublicId,
               @StorageStatus AS StorageStatus,
               @ScanStatus AS ScanStatus,
               @StoredScanProvider AS ScanProvider,
               @RowVersion AS RowVersion,
               @WasReplay AS WasReplay;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_CompleteUpload;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentUploadIntent_Get
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @IntentPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51701, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51702, N'MFA is required for this administrative operation.', 1;

    SELECT intents.PublicId AS IntentPublicId,
           intents.FundingSourceId,
           sources.Name AS FundingSourceName,
           intents.OriginalFileName,
           intents.DeclaredMimeType,
           intents.ExpectedContentLength,
           intents.MaxContentLength,
           intents.Status,
           intents.ExpiresAtUtc,
           documents.PublicId AS SourceDocumentPublicId,
           documents.StorageStatus,
           documents.ScanStatus,
           documents.ScanProvider,
           documents.ScanResultCode,
           intents.CreatedAtUtc,
           intents.CompletedAtUtc,
           intents.UpdatedAtUtc,
           intents.RowVersion
    FROM dbo.FundingPlatform_SourceDocumentUploadIntents AS intents
    INNER JOIN dbo.FundingPlatform_FundingSources AS sources
        ON sources.Id = intents.FundingSourceId
    LEFT JOIN dbo.FundingPlatform_SourceDocuments AS documents
        ON documents.Id = intents.CompletedSourceDocumentId
    WHERE intents.PublicId = @IntentPublicId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentUploadIntent_AcquireFinalize
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @IntentPublicId UNIQUEIDENTIFIER,
    @CompletionTokenHash BINARY(32),
    @LeaseId UNIQUEIDENTIFIER,
    @LeaseUntilUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    SET XACT_ABORT ON;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @ActorUserId BIGINT;
    DECLARE @IntentId BIGINT;
    DECLARE @Status TINYINT;
    DECLARE @StoredTokenHash BINARY(32);
    DECLARE @ExpiresAtUtc DATETIME2(3);
    DECLARE @StoredLeaseId UNIQUEIDENTIFIER;
    DECLARE @StoredLeaseUntilUtc DATETIME2(3);
    DECLARE @FinalizeAttemptCount SMALLINT;
    DECLARE @Code NVARCHAR(50) = N'invalid-token';
    DECLARE @Succeeded BIT = 0;
    DECLARE @WasReplay BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @CompletionTokenHash IS NULL OR @LeaseId IS NULL
       OR @LeaseUntilUtc <= @NowUtc OR @LeaseUntilUtc > DATEADD(MINUTE, 5, @NowUtc)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               CAST(NULL AS UNIQUEIDENTIFIER) AS IntentPublicId,
               CAST(NULL AS INT) AS FundingSourceId,
               CAST(NULL AS NVARCHAR(260)) AS OriginalFileName,
               CAST(NULL AS NVARCHAR(63)) AS IncomingBlobContainer,
               CAST(NULL AS NVARCHAR(1024)) AS IncomingBlobObjectName,
               CAST(NULL AS NVARCHAR(63)) AS QuarantineBlobContainer,
               CAST(NULL AS NVARCHAR(1024)) AS QuarantineBlobObjectName,
               CAST(NULL AS NVARCHAR(100)) AS DeclaredMimeType,
               CAST(NULL AS NVARCHAR(100)) AS VerifiedMimeType,
               CAST(NULL AS BIGINT) AS ExpectedContentLength,
               CAST(NULL AS BIGINT) AS MaxContentLength,
               CAST(NULL AS BIGINT) AS ActualContentLength,
               CAST(NULL AS BINARY(32)) AS ContentHash,
               CAST(NULL AS NVARCHAR(100)) AS BlobETag,
               CAST(NULL AS NVARCHAR(200)) AS BlobVersionId,
               CAST(NULL AS TINYINT) AS Status,
               CAST(NULL AS DATETIME2(3)) AS ExpiresAtUtc,
               CAST(NULL AS UNIQUEIDENTIFIER) AS SourceDocumentPublicId,
               CAST(NULL AS TINYINT) AS StorageStatus,
               CAST(NULL AS TINYINT) AS ScanStatus,
               CAST(NULL AS TINYINT) AS ScanProvider,
               CAST(NULL AS UNIQUEIDENTIFIER) AS FinalizeLeaseId,
               CAST(NULL AS BINARY(8)) AS RowVersion,
               CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_AcquireUpload;

    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;

        SELECT @IntentId = Id,
               @Status = Status,
               @StoredTokenHash = CompletionTokenHash,
               @ExpiresAtUtc = ExpiresAtUtc,
               @StoredLeaseId = FinalizeLeaseId,
               @StoredLeaseUntilUtc = FinalizeLeaseUntilUtc,
               @FinalizeAttemptCount = FinalizeAttemptCount
        FROM dbo.FundingPlatform_SourceDocumentUploadIntents WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @IntentPublicId;

        IF @IntentId IS NULL OR @StoredTokenHash <> @CompletionTokenHash
        BEGIN
            SET @Code = N'invalid-token';
        END
        ELSE IF @Status = 2
        BEGIN
            SET @Succeeded = 1;
            SET @Code = N'completed';
            SET @WasReplay = 1;
        END
        ELSE IF @Status = 4
        BEGIN
            SET @Code = N'rejected';
        END
        ELSE IF @Status = 3 OR @ExpiresAtUtc <= @NowUtc
        BEGIN
            IF @Status IN (0, 1)
            BEGIN
                UPDATE dbo.FundingPlatform_SourceDocumentUploadIntents
                SET Status = 3,
                    FinalizeLeaseId = NULL,
                    FinalizeLeaseUntilUtc = NULL,
                    LastErrorCode = N'expired',
                    UpdatedAtUtc = @NowUtc
                WHERE Id = @IntentId;
                SET @Status = 3;

                INSERT INTO dbo.FundingPlatform_OutboxMessages
                    (MessageType, AggregateType, AggregateId, PayloadJson,
                     OccurredAtUtc, AvailableAtUtc)
                SELECT N'SourceDocumentUploadIntentExpired',
                       N'SourceDocumentUploadIntent',
                       CONVERT(NVARCHAR(100), @IntentPublicId),
                       (SELECT @IntentPublicId AS intentPublicId,
                               CAST(3 AS TINYINT) AS status
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                       @NowUtc, @NowUtc;
            END;
            SET @Code = N'expired';
        END
        ELSE IF @Status = 1 AND @StoredLeaseUntilUtc > @NowUtc
        BEGIN
            SET @Succeeded = 1;
            SET @Code = N'finalizing';
            SET @WasReplay = 1;
        END
        ELSE IF @Status IN (0, 1) AND @FinalizeAttemptCount >= 100
        BEGIN
            SET @Code = N'finalize-limit-reached';
        END
        ELSE IF @Status IN (0, 1)
        BEGIN
            UPDATE dbo.FundingPlatform_SourceDocumentUploadIntents
            SET Status = 1,
                FinalizeAttemptCount = FinalizeAttemptCount + 1,
                FinalizeLeaseId = @LeaseId,
                FinalizeLeaseUntilUtc = @LeaseUntilUtc,
                LastErrorCode = NULL,
                UpdatedAtUtc = @NowUtc
            WHERE Id = @IntentId;
            SET @Status = 1;
            SET @StoredLeaseId = @LeaseId;
            SET @Succeeded = 1;
            SET @Code = N'acquired';
        END
        ELSE
        BEGIN
            SET @Code = N'invalid-state';
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        IF @IntentId IS NULL OR @StoredTokenHash <> @CompletionTokenHash
        BEGIN
            SELECT @Succeeded AS Succeeded, @Code AS Code,
                   CAST(NULL AS UNIQUEIDENTIFIER) AS IntentPublicId,
                   CAST(NULL AS INT) AS FundingSourceId,
                   CAST(NULL AS NVARCHAR(260)) AS OriginalFileName,
                   CAST(NULL AS NVARCHAR(63)) AS IncomingBlobContainer,
                   CAST(NULL AS NVARCHAR(1024)) AS IncomingBlobObjectName,
                   CAST(NULL AS NVARCHAR(63)) AS QuarantineBlobContainer,
                   CAST(NULL AS NVARCHAR(1024)) AS QuarantineBlobObjectName,
                   CAST(NULL AS NVARCHAR(100)) AS DeclaredMimeType,
                   CAST(NULL AS NVARCHAR(100)) AS VerifiedMimeType,
                   CAST(NULL AS BIGINT) AS ExpectedContentLength,
                   CAST(NULL AS BIGINT) AS MaxContentLength,
                   CAST(NULL AS BIGINT) AS ActualContentLength,
                   CAST(NULL AS BINARY(32)) AS ContentHash,
                   CAST(NULL AS NVARCHAR(100)) AS BlobETag,
                   CAST(NULL AS NVARCHAR(200)) AS BlobVersionId,
                   CAST(NULL AS TINYINT) AS Status,
                   CAST(NULL AS DATETIME2(3)) AS ExpiresAtUtc,
                   CAST(NULL AS UNIQUEIDENTIFIER) AS SourceDocumentPublicId,
                   CAST(NULL AS TINYINT) AS StorageStatus,
                   CAST(NULL AS TINYINT) AS ScanStatus,
                   CAST(NULL AS TINYINT) AS ScanProvider,
                   CAST(NULL AS UNIQUEIDENTIFIER) AS FinalizeLeaseId,
                   CAST(NULL AS BINARY(8)) AS RowVersion,
                   @WasReplay AS WasReplay;
            RETURN;
        END;

        SELECT @Succeeded AS Succeeded,
               @Code AS Code,
               intents.PublicId AS IntentPublicId,
               intents.FundingSourceId,
               intents.OriginalFileName,
               CASE WHEN @Code = N'acquired'
                          OR (@Code = N'completed' AND documents.StorageStatus = 0)
                    THEN intents.BlobContainer END
                   AS IncomingBlobContainer,
               CASE WHEN @Code = N'acquired'
                          OR (@Code = N'completed' AND documents.StorageStatus = 0)
                    THEN intents.BlobObjectName END
                   AS IncomingBlobObjectName,
               CASE WHEN @Code = N'acquired'
                          OR (@Code = N'completed' AND documents.ScanStatus = 0)
                    THEN intents.QuarantineBlobContainer END
                   AS QuarantineBlobContainer,
               CASE WHEN @Code = N'acquired'
                          OR (@Code = N'completed' AND documents.ScanStatus = 0)
                    THEN intents.QuarantineBlobObjectName END
                   AS QuarantineBlobObjectName,
               intents.DeclaredMimeType,
               CASE WHEN @Code = N'completed' AND documents.ScanStatus = 0
                    THEN documents.MimeType END AS VerifiedMimeType,
               intents.ExpectedContentLength,
               intents.MaxContentLength,
               CASE WHEN @Code = N'completed' AND documents.ScanStatus = 0
                    THEN documents.ContentLength END AS ActualContentLength,
               CASE WHEN @Code = N'completed' AND documents.ScanStatus = 0
                    THEN documents.ContentHash END AS ContentHash,
               CASE WHEN @Code = N'completed' AND documents.ScanStatus = 0
                    THEN documents.BlobETag END AS BlobETag,
               CASE WHEN @Code = N'completed' AND documents.ScanStatus = 0
                    THEN documents.BlobVersionId END AS BlobVersionId,
               intents.Status,
               intents.ExpiresAtUtc,
               documents.PublicId AS SourceDocumentPublicId,
               documents.StorageStatus,
               documents.ScanStatus,
               documents.ScanProvider,
               CASE WHEN @Code = N'acquired' THEN intents.FinalizeLeaseId END
                   AS FinalizeLeaseId,
               intents.RowVersion,
               @WasReplay AS WasReplay
        FROM dbo.FundingPlatform_SourceDocumentUploadIntents AS intents
        LEFT JOIN dbo.FundingPlatform_SourceDocuments AS documents
            ON documents.Id = intents.CompletedSourceDocumentId
        WHERE intents.Id = @IntentId;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_AcquireUpload;
        THROW;
    END CATCH;
END;
GO
