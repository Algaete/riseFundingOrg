/* FundingPlatform - authenticated Microsoft Defender pipeline for project assets (036B).
   Requires migrations 001-036.

   WorkloadKind: 1 source documents, 2 project assets.
   ReceiptStatus: 0 accepted, 1 applied, 2 ignored, 3 rejected.

   Azure identifiers and bounded receipt metadata are audit data, not credentials.
   Raw Event Grid payloads, SAS values and malware names are deliberately excluded.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF OBJECT_ID(N'dbo.FundingPlatform_EventIngressTrustPolicies', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_SourceDocumentDefenderReceipts', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ProjectAssets', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetScanEvents', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetUploadIntents', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_OutboxMessages', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge', N'P') IS NULL
    THROW 55701, N'Project asset Defender pipeline requires migrations 001-036.', 1;

ALTER TABLE dbo.FundingPlatform_EventIngressTrustPolicies
    ADD WorkloadKind TINYINT NULL
        CONSTRAINT FundingPlatform_DF_EventIngressTrustPolicies_Workload DEFAULT (1);
GO
UPDATE dbo.FundingPlatform_EventIngressTrustPolicies SET WorkloadKind = 1;
ALTER TABLE dbo.FundingPlatform_EventIngressTrustPolicies
    ALTER COLUMN WorkloadKind TINYINT NOT NULL;
ALTER TABLE dbo.FundingPlatform_EventIngressTrustPolicies WITH CHECK
    ADD CONSTRAINT FundingPlatform_CK_EventIngressTrustPolicies_Workload
        CHECK (WorkloadKind IN (1, 2));

ALTER TABLE dbo.FundingPlatform_EventIngressTrustPolicies
    DROP CONSTRAINT FundingPlatform_UQ_EventIngressTrustPolicies_Identity;
ALTER TABLE dbo.FundingPlatform_EventIngressTrustPolicies
    ADD CONSTRAINT FundingPlatform_UQ_EventIngressTrustPolicies_Identity
        UNIQUE (WorkloadKind, Provider, TenantId, PrincipalObjectId,
                ApplicationClientId, TopicResourceId, StorageAccountResourceId);
ALTER TABLE dbo.FundingPlatform_EventIngressTrustPolicies
    ADD CONSTRAINT FundingPlatform_UQ_EventIngressTrustPolicies_IdWorkload
        UNIQUE (Id, WorkloadKind);

DROP INDEX FundingPlatform_IX_EventIngressTrustPolicies_Resolve
    ON dbo.FundingPlatform_EventIngressTrustPolicies;
CREATE INDEX FundingPlatform_IX_EventIngressTrustPolicies_Resolve
    ON dbo.FundingPlatform_EventIngressTrustPolicies
       (WorkloadKind, Provider, TenantId, PrincipalObjectId,
        IsEnabled, ValidFromUtc, ExpiresAtUtc)
    INCLUDE (ApplicationClientId, TopicResourceId, EventSubscriptionName,
             StorageAccountResourceId, StorageAccountHost,
             QuarantineBlobContainer, PublicId);
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_EventIngressTrustPolicy_AdminList
    @SuperAdminUserPublicId UNIQUEIDENTIFIER,
    @WorkloadKind TINYINT = 1
AS
BEGIN
    SET NOCOUNT ON;
    IF @WorkloadKind IS NULL OR @WorkloadKind NOT IN (1, 2)
        THROW 55702, N'WorkloadKind must be SourceDocument or ProjectAsset.', 1;

    DECLARE @ActorUserId BIGINT;
    EXEC dbo.FundingPlatform_usp_AdminActor_Lock
        @AdminUserPublicId = @SuperAdminUserPublicId,
        @ActorUserId = @ActorUserId OUTPUT;
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_UserRoles AS userRoles
        INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
        WHERE userRoles.UserId = @ActorUserId AND roles.NormalizedName = N'SUPERADMIN')
        THROW 51827, N'Active SuperAdmin role is required.', 1;

    SELECT policies.PublicId AS PolicyPublicId, policies.WorkloadKind,
           policies.Provider, policies.TenantId, policies.PrincipalObjectId,
           policies.ApplicationClientId,
           policies.TopicResourceId AS ExpectedTopicResourceId,
           policies.EventSubscriptionName, policies.StorageAccountResourceId,
           policies.StorageAccountHost, policies.QuarantineBlobContainer,
           policies.IsEnabled, policies.ValidFromUtc, policies.ExpiresAtUtc,
           policies.CreatedAtUtc, policies.UpdatedAtUtc, policies.RowVersion
    FROM dbo.FundingPlatform_EventIngressTrustPolicies AS policies
    WHERE policies.WorkloadKind = @WorkloadKind
    ORDER BY policies.IsEnabled DESC, policies.UpdatedAtUtc DESC, policies.Id DESC;
END;
GO

ALTER TABLE dbo.FundingPlatform_ProjectAssetScanEvents
    DROP CONSTRAINT FundingPlatform_CK_ProjectAssetScanEvents_Status;
ALTER TABLE dbo.FundingPlatform_ProjectAssetScanEvents
    DROP CONSTRAINT FundingPlatform_CK_ProjectAssetScanEvents_Result;
ALTER TABLE dbo.FundingPlatform_ProjectAssetScanEvents
    ALTER COLUMN ReportedContentHash BINARY(32) NULL;
ALTER TABLE dbo.FundingPlatform_ProjectAssetScanEvents ADD
    RevokedTrustedBlobContainer NVARCHAR(63) NULL,
    RevokedTrustedBlobObjectName NVARCHAR(1024) NULL,
    RevokedTrustedBlobETag NVARCHAR(100) NULL,
    RevokedTrustedBlobVersionId NVARCHAR(200) NULL;
GO

ALTER TABLE dbo.FundingPlatform_ProjectAssetScanEvents WITH CHECK
    ADD CONSTRAINT FundingPlatform_CK_ProjectAssetScanEvents_Status
        CHECK (ScanProvider BETWEEN 0 AND 1
               AND ((FromStatus = 0 AND ToStatus BETWEEN 1 AND 4)
                    OR (FromStatus = 1 AND ScanProvider = 1 AND ToStatus BETWEEN 2 AND 4)));
ALTER TABLE dbo.FundingPlatform_ProjectAssetScanEvents WITH CHECK
    ADD CONSTRAINT FundingPlatform_CK_ProjectAssetScanEvents_Result
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
               AND CHARINDEX(CHAR(13), ResultCode) = 0
               AND (ToStatus NOT IN (1, 2) OR ReportedContentHash IS NOT NULL)
               AND ((FromStatus = 0
                     AND RevokedTrustedBlobContainer IS NULL
                     AND RevokedTrustedBlobObjectName IS NULL
                     AND RevokedTrustedBlobETag IS NULL
                     AND RevokedTrustedBlobVersionId IS NULL)
                    OR (FromStatus = 1
                        AND NULLIF(LTRIM(RTRIM(RevokedTrustedBlobContainer)), N'') IS NOT NULL
                        AND NULLIF(LTRIM(RTRIM(RevokedTrustedBlobObjectName)), N'') IS NOT NULL
                        AND NULLIF(LTRIM(RTRIM(RevokedTrustedBlobETag)), N'') IS NOT NULL
                        AND NULLIF(LTRIM(RTRIM(RevokedTrustedBlobVersionId)), N'') IS NOT NULL
                        AND CHARINDEX(N'&', RevokedTrustedBlobContainer) = 0
                        AND CHARINDEX(N'#', RevokedTrustedBlobContainer) = 0
                        AND CHARINDEX(N'?', RevokedTrustedBlobContainer) = 0
                        AND CHARINDEX(N'&', RevokedTrustedBlobObjectName) = 0
                        AND CHARINDEX(N'#', RevokedTrustedBlobObjectName) = 0
                        AND CHARINDEX(N'?', RevokedTrustedBlobObjectName) = 0
                        AND CHARINDEX(N'&', RevokedTrustedBlobVersionId) = 0
                        AND CHARINDEX(N'#', RevokedTrustedBlobVersionId) = 0
                        AND CHARINDEX(N'?', RevokedTrustedBlobVersionId) = 0)));
GO

CREATE TABLE dbo.FundingPlatform_ProjectAssetDefenderReceipts
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_ProjectAssetDefenderReceipts_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    TrustPolicyId INT NOT NULL,
    WorkloadKind TINYINT NOT NULL
        CONSTRAINT FundingPlatform_DF_ProjectAssetDefenderReceipts_Workload DEFAULT (2),
    ProjectAssetId BIGINT NULL,
    Provider TINYINT NOT NULL,
    ProviderEventId NVARCHAR(200) NOT NULL,
    PayloadHash BINARY(32) NOT NULL,
    TopicResourceId NVARCHAR(500) NOT NULL,
    AuthenticatedTenantId UNIQUEIDENTIFIER NOT NULL,
    AuthenticatedPrincipalId UNIQUEIDENTIFIER NOT NULL,
    ApplicationClientId UNIQUEIDENTIFIER NOT NULL,
    EventSubscriptionName NVARCHAR(100) NOT NULL,
    StorageAccountResourceId NVARCHAR(500) NOT NULL,
    BlobHost NVARCHAR(253) NOT NULL,
    BlobContainer NVARCHAR(63) NOT NULL,
    BlobObjectName NVARCHAR(1024) NOT NULL,
    BlobETag NVARCHAR(100) NOT NULL,
    ReportedContentHash BINARY(32) NULL,
    ToStatus TINYINT NOT NULL,
    ResultCode NVARCHAR(100) NOT NULL,
    ReceiptStatus TINYINT NOT NULL,
    OutcomeCode NVARCHAR(100) NULL,
    OccurredAtUtc DATETIME2(3) NOT NULL,
    ReceivedAtUtc DATETIME2(3) NOT NULL,
    FinalizedAtUtc DATETIME2(3) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_ProjectAssetDefenderReceipts_Created
        DEFAULT (SYSUTCDATETIME()),
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_ProjectAssetDefenderReceipts PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_ProjectAssetDefenderReceipts_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_ProjectAssetDefenderReceipts_ProviderEvent
        UNIQUE (Provider, ProviderEventId),
    CONSTRAINT FundingPlatform_FK_ProjectAssetDefenderReceipts_Policy
        FOREIGN KEY (TrustPolicyId, WorkloadKind)
        REFERENCES dbo.FundingPlatform_EventIngressTrustPolicies (Id, WorkloadKind),
    CONSTRAINT FundingPlatform_FK_ProjectAssetDefenderReceipts_Asset
        FOREIGN KEY (ProjectAssetId) REFERENCES dbo.FundingPlatform_ProjectAssets (Id)
        ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_CK_ProjectAssetDefenderReceipts_Provider
        CHECK (Provider = 1 AND WorkloadKind = 2),
    CONSTRAINT FundingPlatform_CK_ProjectAssetDefenderReceipts_Blob
        CHECK (BlobHost = LOWER(LTRIM(RTRIM(BlobHost)))
               AND BlobHost LIKE N'%.blob.core.windows.net'
               AND BlobHost NOT LIKE N'%[^-a-z0-9.]%' COLLATE Latin1_General_100_BIN2
               AND LEN(BlobContainer) BETWEEN 3 AND 63
               AND BlobContainer = LOWER(BlobContainer)
               AND BlobContainer NOT LIKE N'%[^-a-z0-9]%' COLLATE Latin1_General_100_BIN2
               AND LEN(BlobObjectName) BETWEEN 1 AND 1024
               AND LEFT(BlobObjectName, 1) <> N'/'
               AND CHARINDEX(N'?', BlobObjectName) = 0
               AND CHARINDEX(N'#', BlobObjectName) = 0
               AND LEN(BlobETag) BETWEEN 3 AND 100
               AND LEFT(BlobETag, 1) = N'"' AND RIGHT(BlobETag, 1) = N'"'),
    CONSTRAINT FundingPlatform_CK_ProjectAssetDefenderReceipts_Result
        CHECK (ToStatus BETWEEN 1 AND 4
               AND (ToStatus NOT IN (1, 2) OR ReportedContentHash IS NOT NULL)
               AND NULLIF(LTRIM(RTRIM(ResultCode)), N'') IS NOT NULL
               AND CHARINDEX(CHAR(10), ResultCode) = 0
               AND CHARINDEX(CHAR(13), ResultCode) = 0),
    CONSTRAINT FundingPlatform_CK_ProjectAssetDefenderReceipts_State
        CHECK ((ReceiptStatus = 0 AND OutcomeCode IS NULL AND FinalizedAtUtc IS NULL)
               OR (ReceiptStatus BETWEEN 1 AND 3
                   AND NULLIF(LTRIM(RTRIM(OutcomeCode)), N'') IS NOT NULL
                   AND FinalizedAtUtc IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_ProjectAssetDefenderReceipts_Time
        CHECK (ReceivedAtUtc >= DATEADD(DAY, -1, CreatedAtUtc)
               AND ReceivedAtUtc <= DATEADD(MINUTE, 5, CreatedAtUtc)
               AND OccurredAtUtc >= DATEADD(DAY, -1, ReceivedAtUtc)
               AND OccurredAtUtc <= DATEADD(MINUTE, 5, ReceivedAtUtc)
               AND (FinalizedAtUtc IS NULL OR FinalizedAtUtc >= ReceivedAtUtc))
);

CREATE INDEX FundingPlatform_IX_ProjectAssetDefenderReceipts_Asset
    ON dbo.FundingPlatform_ProjectAssetDefenderReceipts
       (ProjectAssetId, ReceivedAtUtc DESC, Id DESC)
    INCLUDE (PublicId, ProviderEventId, ReceiptStatus, ToStatus, ResultCode);
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_EventIngressTrustPolicy_Upsert
    @SuperAdminUserPublicId UNIQUEIDENTIFIER,
    @PolicyPublicId UNIQUEIDENTIFIER = NULL,
    @ExpectedRowVersion BINARY(8) = NULL,
    @WorkloadKind TINYINT = 1,
    @TenantId UNIQUEIDENTIFIER,
    @PrincipalObjectId UNIQUEIDENTIFIER,
    @ApplicationClientId UNIQUEIDENTIFIER,
    @ExpectedTopicResourceId NVARCHAR(500),
    @EventSubscriptionName NVARCHAR(100),
    @StorageAccountResourceId NVARCHAR(500),
    @StorageAccountHost NVARCHAR(253),
    @QuarantineBlobContainer NVARCHAR(63),
    @IsEnabled BIT,
    @ValidFromUtc DATETIME2(3),
    @ExpiresAtUtc DATETIME2(3) = NULL,
    @Reason NVARCHAR(500),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @CorrelationId NVARCHAR(100),
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET @ExpectedTopicResourceId = LOWER(LTRIM(RTRIM(@ExpectedTopicResourceId)));
    SET @StorageAccountResourceId = LOWER(LTRIM(RTRIM(@StorageAccountResourceId)));
    SET @StorageAccountHost = LOWER(LTRIM(RTRIM(@StorageAccountHost)));
    SET @QuarantineBlobContainer = LOWER(LTRIM(RTRIM(@QuarantineBlobContainer)));
    SET @EventSubscriptionName = LTRIM(RTRIM(@EventSubscriptionName));
    SET @Reason = LTRIM(RTRIM(@Reason));
    SET @CorrelationId = LTRIM(RTRIM(@CorrelationId));

    IF @WorkloadKind IS NULL OR @WorkloadKind NOT IN (1, 2)
       OR @TenantId IS NULL OR @PrincipalObjectId IS NULL OR @ApplicationClientId IS NULL
       OR @IsEnabled IS NULL
       OR @ValidFromUtc IS NULL OR @NowUtc IS NULL
       OR @IdempotencyKeyHash IS NULL OR @RequestHash IS NULL
       OR NULLIF(@ExpectedTopicResourceId, N'') IS NULL
       OR LEN(@ExpectedTopicResourceId) > 500
       OR CHARINDEX(CHAR(10), @ExpectedTopicResourceId) > 0
       OR CHARINDEX(CHAR(13), @ExpectedTopicResourceId) > 0
       OR CHARINDEX(0x0000, CONVERT(VARBINARY(1000), @ExpectedTopicResourceId)) > 0
       OR NULLIF(@StorageAccountResourceId, N'') IS NULL
       OR LEN(@StorageAccountResourceId) > 500
       OR @StorageAccountResourceId NOT LIKE
          N'/subscriptions/%/resourcegroups/%/providers/microsoft.storage/storageaccounts/%'
       OR CHARINDEX(CHAR(10), @StorageAccountResourceId) > 0
       OR CHARINDEX(CHAR(13), @StorageAccountResourceId) > 0
       OR CHARINDEX(0x0000, CONVERT(VARBINARY(1000), @StorageAccountResourceId)) > 0
       OR NULLIF(@StorageAccountHost, N'') IS NULL
       OR @StorageAccountHost <>
          RIGHT(@StorageAccountResourceId,
                NULLIF(CHARINDEX(N'/', REVERSE(@StorageAccountResourceId)), 0) - 1)
          + N'.blob.core.windows.net'
       OR NULLIF(@QuarantineBlobContainer, N'') IS NULL
       OR NULLIF(@EventSubscriptionName, N'') IS NULL
       OR NULLIF(@Reason, N'') IS NULL OR LEN(@Reason) > 500
       OR CHARINDEX(CHAR(10), @Reason) > 0 OR CHARINDEX(CHAR(13), @Reason) > 0
       OR NULLIF(@CorrelationId, N'') IS NULL OR LEN(@CorrelationId) > 100
       OR @CorrelationId COLLATE Latin1_General_100_BIN2
          LIKE N'%[^-A-Za-z0-9:_.]%' COLLATE Latin1_General_100_BIN2
       OR (@ExpiresAtUtc IS NOT NULL AND @ExpiresAtUtc <= @ValidFromUtc)
        THROW 51828, N'Valid bounded trust-policy metadata is required.', 1;

    SET XACT_ABORT ON;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @ActorUserId BIGINT, @PolicyId INT, @StoredRequestHash BINARY(32);
    DECLARE @StoredPolicyPublicId UNIQUEIDENTIFIER, @StoredEnabled BIT;
    DECLARE @StoredWorkloadKind TINYINT;
    DECLARE @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'not-found';

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_TrustUpsert037;

    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId = @SuperAdminUserPublicId,
            @ActorUserId = @ActorUserId OUTPUT;
        IF NOT EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_UserRoles AS userRoles WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.FundingPlatform_Roles AS roles WITH (UPDLOCK, HOLDLOCK)
                ON roles.Id = userRoles.RoleId
            WHERE userRoles.UserId = @ActorUserId AND roles.NormalizedName = N'SUPERADMIN')
            THROW 51829, N'Active SuperAdmin role is required.', 1;

        SELECT @StoredRequestHash = events.RequestHash,
               @PolicyId = policies.Id, @StoredPolicyPublicId = policies.PublicId,
               @StoredEnabled = policies.IsEnabled,
               @StoredWorkloadKind = policies.WorkloadKind,
               @ResultRowVersion = policies.RowVersion
        FROM dbo.FundingPlatform_EventIngressTrustPolicyEvents AS events
             WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_EventIngressTrustPolicies AS policies WITH (HOLDLOCK)
            ON policies.Id = events.TrustPolicyId
        WHERE events.ActorUserId = @ActorUserId
          AND events.IdempotencyKeyHash = @IdempotencyKeyHash;

        IF @StoredRequestHash IS NOT NULL
        BEGIN
            IF @StoredRequestHash = @RequestHash
               AND @StoredWorkloadKind = @WorkloadKind
            BEGIN
                SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'replayed';
            END
            ELSE
            BEGIN
                SET @PolicyId = NULL; SET @StoredPolicyPublicId = NULL;
                SET @StoredEnabled = NULL; SET @ResultRowVersion = NULL;
                SET @Code = N'idempotency-conflict';
            END;
        END
        ELSE
        BEGIN
            SET @PolicyId = NULL;
            IF @PolicyPublicId IS NOT NULL
                SELECT @PolicyId = Id, @StoredPolicyPublicId = PublicId,
                       @CurrentRowVersion = RowVersion
                FROM dbo.FundingPlatform_EventIngressTrustPolicies WITH (UPDLOCK, HOLDLOCK)
                WHERE PublicId = @PolicyPublicId;
            ELSE
                SELECT @PolicyId = Id, @StoredPolicyPublicId = PublicId,
                       @CurrentRowVersion = RowVersion
                FROM dbo.FundingPlatform_EventIngressTrustPolicies WITH (UPDLOCK, HOLDLOCK)
                WHERE WorkloadKind = @WorkloadKind AND Provider = 1
                  AND TenantId = @TenantId
                  AND PrincipalObjectId = @PrincipalObjectId
                  AND ApplicationClientId = @ApplicationClientId
                  AND TopicResourceId = @ExpectedTopicResourceId
                  AND StorageAccountResourceId = @StorageAccountResourceId;

            IF @PolicyPublicId IS NOT NULL AND @PolicyId IS NULL SET @Code = N'not-found';
            ELSE IF @PolicyId IS NOT NULL AND @ExpectedRowVersion IS NULL
                SET @Code = N'precondition-required';
            ELSE IF @PolicyId IS NOT NULL AND @CurrentRowVersion <> @ExpectedRowVersion
                SET @Code = N'etag-conflict';
            ELSE
            BEGIN
                IF @PolicyId IS NULL
                BEGIN
                    DECLARE @InsertedPolicy TABLE
                        (Id INT, PublicId UNIQUEIDENTIFIER, RowVersion BINARY(8));
                    INSERT INTO dbo.FundingPlatform_EventIngressTrustPolicies
                        (WorkloadKind, Provider, TenantId, PrincipalObjectId,
                         ApplicationClientId, TopicResourceId, EventSubscriptionName,
                         StorageAccountResourceId, StorageAccountHost,
                         QuarantineBlobContainer, IsEnabled, ValidFromUtc, ExpiresAtUtc,
                         CreatedByUserId, CreatedAtUtc, UpdatedAtUtc)
                    OUTPUT inserted.Id, inserted.PublicId, inserted.RowVersion
                        INTO @InsertedPolicy (Id, PublicId, RowVersion)
                    VALUES (@WorkloadKind, 1, @TenantId, @PrincipalObjectId,
                            @ApplicationClientId, @ExpectedTopicResourceId,
                            @EventSubscriptionName, @StorageAccountResourceId,
                            @StorageAccountHost, @QuarantineBlobContainer, @IsEnabled,
                            @ValidFromUtc, @ExpiresAtUtc, @ActorUserId, @NowUtc, @NowUtc);
                    SELECT @PolicyId = Id, @StoredPolicyPublicId = PublicId,
                           @ResultRowVersion = RowVersion FROM @InsertedPolicy;
                    SET @Code = N'created';
                END
                ELSE
                BEGIN
                    IF NOT EXISTS
                       (SELECT 1 FROM dbo.FundingPlatform_EventIngressTrustPolicies
                        WHERE Id = @PolicyId AND WorkloadKind = @WorkloadKind
                          AND TenantId = @TenantId
                          AND PrincipalObjectId = @PrincipalObjectId
                          AND ApplicationClientId = @ApplicationClientId
                          AND TopicResourceId = @ExpectedTopicResourceId
                          AND StorageAccountResourceId = @StorageAccountResourceId)
                        THROW 51830, N'Trust-policy identity is immutable; create a replacement.', 1;

                    UPDATE dbo.FundingPlatform_EventIngressTrustPolicies
                    SET EventSubscriptionName = @EventSubscriptionName,
                        StorageAccountHost = @StorageAccountHost,
                        QuarantineBlobContainer = @QuarantineBlobContainer,
                        IsEnabled = @IsEnabled, ValidFromUtc = @ValidFromUtc,
                        ExpiresAtUtc = @ExpiresAtUtc, UpdatedAtUtc = @NowUtc
                    WHERE Id = @PolicyId;
                    SELECT @ResultRowVersion = RowVersion
                    FROM dbo.FundingPlatform_EventIngressTrustPolicies WHERE Id = @PolicyId;
                    SET @Code = N'updated';
                END;

                INSERT INTO dbo.FundingPlatform_EventIngressTrustPolicyEvents
                    (TrustPolicyId, ActorUserId, Action, Reason, CorrelationId,
                     IdempotencyKeyHash, RequestHash, CreatedAtUtc)
                VALUES (@PolicyId, @ActorUserId, CASE WHEN @IsEnabled = 1 THEN 1 ELSE 2 END,
                        @Reason, @CorrelationId, @IdempotencyKeyHash, @RequestHash, @NowUtc);
                SET @StoredEnabled = @IsEnabled; SET @Succeeded = 1;
            END;
        END;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_TrustUpsert037;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @StoredPolicyPublicId AS PolicyPublicId, @StoredEnabled AS IsEnabled,
           @ResultRowVersion AS RowVersion, @WasReplay AS WasReplay;
END;
GO

/* Preserve the established source-document receipt contract while preventing
   a project-asset policy with the same Azure identity from authorizing it. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SourceDocumentDefenderReceipt_Record
    @ProviderEventId NVARCHAR(200),
    @PayloadHash BINARY(32),
    @AuthenticatedTenantId UNIQUEIDENTIFIER,
    @AuthenticatedPrincipalId UNIQUEIDENTIFIER,
    @ApplicationClientId UNIQUEIDENTIFIER,
    @TopicResourceId NVARCHAR(500),
    @EventSubscriptionName NVARCHAR(100),
    @StorageAccountResourceId NVARCHAR(500),
    @BlobHost NVARCHAR(253),
    @BlobContainer NVARCHAR(63),
    @BlobObjectName NVARCHAR(1024),
    @BlobETag NVARCHAR(100),
    @ReportedContentHash BINARY(32) = NULL,
    @ToStatus TINYINT,
    @ResultCode NVARCHAR(100),
    @OccurredAtUtc DATETIME2(3),
    @ReceivedAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ProviderEventId = LTRIM(RTRIM(@ProviderEventId));
    SET @TopicResourceId = LOWER(LTRIM(RTRIM(@TopicResourceId)));
    SET @StorageAccountResourceId = LOWER(LTRIM(RTRIM(@StorageAccountResourceId)));
    SET @BlobHost = LOWER(LTRIM(RTRIM(@BlobHost)));
    SET @BlobContainer = LOWER(LTRIM(RTRIM(@BlobContainer)));
    SET @BlobObjectName = LTRIM(RTRIM(@BlobObjectName));
    SET @BlobETag = LTRIM(RTRIM(@BlobETag));
    SET @EventSubscriptionName = LTRIM(RTRIM(@EventSubscriptionName));
    SET @ResultCode = LOWER(LTRIM(RTRIM(@ResultCode)));

    IF NULLIF(@ProviderEventId, N'') IS NULL OR LEN(@ProviderEventId) > 200
       OR @PayloadHash IS NULL OR @AuthenticatedTenantId IS NULL
       OR @AuthenticatedPrincipalId IS NULL OR @ApplicationClientId IS NULL
       OR NULLIF(@TopicResourceId, N'') IS NULL OR LEN(@TopicResourceId) > 500
       OR CHARINDEX(CHAR(10), @TopicResourceId) > 0
       OR CHARINDEX(CHAR(13), @TopicResourceId) > 0
       OR CHARINDEX(0x0000, CONVERT(VARBINARY(1000), @TopicResourceId)) > 0
       OR NULLIF(@StorageAccountResourceId, N'') IS NULL
       OR LEN(@StorageAccountResourceId) > 500
       OR CHARINDEX(CHAR(10), @StorageAccountResourceId) > 0
       OR CHARINDEX(CHAR(13), @StorageAccountResourceId) > 0
       OR CHARINDEX(0x0000, CONVERT(VARBINARY(1000), @StorageAccountResourceId)) > 0
       OR NULLIF(@EventSubscriptionName, N'') IS NULL OR LEN(@EventSubscriptionName) > 100
       OR NULLIF(@BlobHost, N'') IS NULL OR LEN(@BlobHost) > 253
       OR LEN(@BlobContainer) NOT BETWEEN 3 AND 63
       OR NULLIF(@BlobObjectName, N'') IS NULL OR LEN(@BlobObjectName) > 1024
       OR LEFT(@BlobObjectName, 1) = N'/' OR CHARINDEX(N'?', @BlobObjectName) > 0
       OR CHARINDEX(N'#', @BlobObjectName) > 0
       OR LEN(@BlobETag) NOT BETWEEN 3 AND 100
       OR LEFT(@BlobETag, 1) <> N'"' OR RIGHT(@BlobETag, 1) <> N'"'
       OR @ToStatus NOT BETWEEN 1 AND 4
       OR (@ToStatus IN (1, 2) AND @ReportedContentHash IS NULL)
       OR NULLIF(@ResultCode, N'') IS NULL OR LEN(@ResultCode) > 100
       OR @ResultCode LIKE N'%[^-a-z0-9._]%' COLLATE Latin1_General_100_BIN2
       OR @OccurredAtUtc IS NULL OR @ReceivedAtUtc IS NULL
        THROW 51831, N'Authenticated bounded Defender receipt metadata is required.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @PolicyId INT, @DocumentId BIGINT, @DocumentPublicId UNIQUEIDENTIFIER;
    DECLARE @StoredETag NVARCHAR(100), @StoredHash BINARY(32), @ContentLength BIGINT;
    DECLARE @MimeType NVARCHAR(100), @StorageStatus TINYINT, @ScanStatus TINYINT;
    DECLARE @ContentRetentionStatus TINYINT, @ScanCompletedAtUtc DATETIME2(3);
    DECLARE @ReceiptId BIGINT, @ReceiptPublicId UNIQUEIDENTIFIER;
    DECLARE @ExistingPayloadHash BINARY(32), @ExistingDocumentId BIGINT;
    DECLARE @ExistingTenant UNIQUEIDENTIFIER, @ExistingPrincipal UNIQUEIDENTIFIER;
    DECLARE @ExistingApp UNIQUEIDENTIFIER, @ExistingTopic NVARCHAR(500);
    DECLARE @ExistingSubscription NVARCHAR(100);
    DECLARE @ExistingStorage NVARCHAR(500), @ExistingHost NVARCHAR(253);
    DECLARE @ExistingContainer NVARCHAR(63), @ExistingObject NVARCHAR(1024);
    DECLARE @ExistingETag NVARCHAR(100), @ExistingReportedHash BINARY(32);
    DECLARE @ExistingToStatus TINYINT, @ExistingResultCode NVARCHAR(100);
    DECLARE @ReceiptStatus TINYINT, @OutcomeCode NVARCHAR(100);
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'unauthorized';
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_SourceReceipt037;

    BEGIN TRY
        SELECT @ReceiptId = Id, @ReceiptPublicId = PublicId,
               @ExistingPayloadHash = PayloadHash, @ExistingDocumentId = SourceDocumentId,
               @ExistingTenant = AuthenticatedTenantId,
               @ExistingPrincipal = AuthenticatedPrincipalId,
               @ExistingApp = ApplicationClientId, @ExistingTopic = TopicResourceId,
               @ExistingSubscription = EventSubscriptionName,
               @ExistingStorage = StorageAccountResourceId, @ExistingHost = BlobHost,
               @ExistingContainer = BlobContainer, @ExistingObject = BlobObjectName,
               @ExistingETag = BlobETag, @ExistingReportedHash = ReportedContentHash,
               @ExistingToStatus = ToStatus, @ExistingResultCode = ResultCode,
               @ReceiptStatus = ReceiptStatus, @OutcomeCode = OutcomeCode
        FROM dbo.FundingPlatform_SourceDocumentDefenderReceipts WITH (UPDLOCK, HOLDLOCK)
        WHERE Provider = 1 AND ProviderEventId = @ProviderEventId;

        IF @ReceiptId IS NOT NULL
        BEGIN
            IF @ExistingPayloadHash = @PayloadHash
               AND @ExistingTenant = @AuthenticatedTenantId
               AND @ExistingPrincipal = @AuthenticatedPrincipalId
               AND @ExistingApp = @ApplicationClientId
               AND @ExistingTopic = @TopicResourceId
               AND @ExistingSubscription = @EventSubscriptionName
               AND @ExistingStorage = @StorageAccountResourceId
               AND @ExistingHost = @BlobHost
               AND @ExistingContainer = @BlobContainer
               AND @ExistingObject = @BlobObjectName
               AND @ExistingETag = @BlobETag
               AND ((@ExistingReportedHash IS NULL AND @ReportedContentHash IS NULL)
                    OR @ExistingReportedHash = @ReportedContentHash)
               AND @ExistingToStatus = @ToStatus AND @ExistingResultCode = @ResultCode
            BEGIN
                SET @WasReplay = 1;
                SET @Succeeded = CASE WHEN @ReceiptStatus IN (0, 1) THEN 1 ELSE 0 END;
                SET @Code = CASE @ReceiptStatus
                              WHEN 0 THEN N'replayed-accepted'
                              WHEN 1 THEN N'replayed-applied'
                              WHEN 2 THEN N'replayed-ignored'
                              ELSE N'replayed-rejected' END;
                SET @DocumentId = @ExistingDocumentId;
            END
            ELSE
            BEGIN
                SET @ReceiptPublicId = NULL; SET @DocumentId = NULL;
                SET @ReceiptStatus = NULL; SET @Code = N'event-conflict';
            END;
        END
        ELSE
        BEGIN
            SELECT @PolicyId = Id
            FROM dbo.FundingPlatform_EventIngressTrustPolicies WITH (UPDLOCK, HOLDLOCK)
            WHERE WorkloadKind = 1 AND Provider = 1
              AND TenantId = @AuthenticatedTenantId
              AND PrincipalObjectId = @AuthenticatedPrincipalId
              AND ApplicationClientId = @ApplicationClientId
              AND TopicResourceId = @TopicResourceId
              AND EventSubscriptionName = @EventSubscriptionName
              AND StorageAccountResourceId = @StorageAccountResourceId
              AND StorageAccountHost = @BlobHost
              AND QuarantineBlobContainer = @BlobContainer
              AND IsEnabled = 1 AND ValidFromUtc <= @ReceivedAtUtc
              AND (ExpiresAtUtc IS NULL OR ExpiresAtUtc > @ReceivedAtUtc);

            IF @PolicyId IS NULL SET @Code = N'unauthorized';
            ELSE
            BEGIN
                SELECT @DocumentId = Id, @DocumentPublicId = PublicId,
                       @StoredETag = BlobETag, @StoredHash = ContentHash,
                       @ContentLength = ContentLength, @MimeType = MimeType,
                       @StorageStatus = StorageStatus, @ScanStatus = ScanStatus,
                       @ContentRetentionStatus = ContentRetentionStatus,
                       @ScanCompletedAtUtc = ScanCompletedAtUtc
                FROM dbo.FundingPlatform_SourceDocuments WITH (UPDLOCK, HOLDLOCK)
                WHERE BlobContainer = @BlobContainer AND BlobObjectName = @BlobObjectName
                  AND ScanProvider = 1;

                SET @ReceiptStatus = 0; SET @OutcomeCode = NULL;
                IF @DocumentId IS NULL
                BEGIN SET @ReceiptStatus = 3; SET @OutcomeCode = N'document-not-found'; END
                ELSE IF @StoredETag <> @BlobETag
                BEGIN SET @ReceiptStatus = 3; SET @OutcomeCode = N'blob-etag-mismatch'; END
                ELSE IF @ReportedContentHash IS NOT NULL AND @StoredHash <> @ReportedContentHash
                BEGIN SET @ReceiptStatus = 3; SET @OutcomeCode = N'content-hash-mismatch'; END
                ELSE IF @ContentRetentionStatus IN (1, 2, 3)
                BEGIN SET @ReceiptStatus = 2; SET @OutcomeCode = N'content-retention-ignored'; END
                ELSE IF @OccurredAtUtc < DATEADD(DAY, -1, @ReceivedAtUtc)
                     OR @OccurredAtUtc > DATEADD(MINUTE, 5, @ReceivedAtUtc)
                BEGIN SET @ReceiptStatus = 3; SET @OutcomeCode = N'invalid-event-time'; END
                ELSE IF @StorageStatus = 1 AND @ScanStatus = 0 SET @ReceiptStatus = 0;
                ELSE IF @ScanCompletedAtUtc IS NOT NULL AND @OccurredAtUtc <= @ScanCompletedAtUtc
                BEGIN SET @ReceiptStatus = 2; SET @OutcomeCode = N'stale-scan-result'; END
                ELSE IF @ScanCompletedAtUtc IS NOT NULL AND @ToStatus = @ScanStatus
                BEGIN SET @ReceiptStatus = 2; SET @OutcomeCode = N'duplicate-scan-result'; END
                ELSE IF @StorageStatus = 2 AND @ScanStatus = 1
                     AND @ToStatus IN (2, 3, 4) AND @ReportedContentHash IS NULL
                BEGIN
                    SET @ReceiptStatus = 3;
                    SET @OutcomeCode = N'content-hash-required-for-supersede';
                END
                ELSE IF @StorageStatus = 2 AND @ScanStatus = 1
                     AND @ToStatus IN (2, 3, 4) SET @ReceiptStatus = 0;
                ELSE IF @ScanStatus IN (1, 2, 3, 4)
                BEGIN SET @ReceiptStatus = 3; SET @OutcomeCode = N'terminal-scan-result-conflict'; END
                ELSE
                BEGIN SET @ReceiptStatus = 3; SET @OutcomeCode = N'invalid-document-state'; END;

                DECLARE @InsertedReceipt TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER);
                INSERT INTO dbo.FundingPlatform_SourceDocumentDefenderReceipts
                    (TrustPolicyId, SourceDocumentId, Provider, ProviderEventId, PayloadHash,
                     TopicResourceId, AuthenticatedTenantId, AuthenticatedPrincipalId,
                     ApplicationClientId, EventSubscriptionName, StorageAccountResourceId,
                     BlobHost, BlobContainer, BlobObjectName, BlobETag, ReportedContentHash,
                     ToStatus, ResultCode, ReceiptStatus, OutcomeCode, OccurredAtUtc,
                     ReceivedAtUtc, FinalizedAtUtc, CreatedAtUtc)
                OUTPUT inserted.Id, inserted.PublicId INTO @InsertedReceipt (Id, PublicId)
                VALUES (@PolicyId, @DocumentId, 1, @ProviderEventId, @PayloadHash,
                        @TopicResourceId, @AuthenticatedTenantId, @AuthenticatedPrincipalId,
                        @ApplicationClientId, @EventSubscriptionName, @StorageAccountResourceId,
                        @BlobHost, @BlobContainer, @BlobObjectName, @BlobETag,
                        @ReportedContentHash, @ToStatus, @ResultCode, @ReceiptStatus,
                        @OutcomeCode, @OccurredAtUtc, @ReceivedAtUtc,
                        CASE WHEN @ReceiptStatus IN (2, 3) THEN @ReceivedAtUtc END, @NowUtc);
                SELECT @ReceiptId = Id, @ReceiptPublicId = PublicId FROM @InsertedReceipt;

                IF @ReceiptStatus = 0
                BEGIN SET @Succeeded = 1; SET @Code = N'accepted'; END
                ELSE SET @Code = @OutcomeCode;
            END;
        END;

        IF @DocumentId IS NOT NULL AND @DocumentPublicId IS NULL
            SELECT @DocumentPublicId = PublicId, @StoredETag = BlobETag,
                   @StoredHash = ContentHash, @ContentLength = ContentLength,
                   @MimeType = MimeType
            FROM dbo.FundingPlatform_SourceDocuments WHERE Id = @DocumentId;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_SourceReceipt037;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, @ReceiptPublicId AS ReceiptPublicId,
           CASE WHEN @Succeeded = 1 THEN @DocumentPublicId END AS SourceDocumentPublicId,
           CAST(1 AS TINYINT) AS ScanProvider,
           CASE WHEN @Succeeded = 1 THEN @BlobContainer END AS QuarantineBlobContainer,
           CASE WHEN @Succeeded = 1 THEN @BlobObjectName END AS QuarantineBlobObjectName,
           CASE WHEN @Succeeded = 1 THEN @StoredETag END AS QuarantineBlobETag,
           CASE WHEN @Succeeded = 1 THEN @StoredHash END AS ContentHash,
           CASE WHEN @Succeeded = 1 THEN @ContentLength END AS ContentLength,
           CASE WHEN @Succeeded = 1 THEN @MimeType END AS MimeType,
           @WasReplay AS WasReplay;
END;
GO

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
    ELSE SAVE TRANSACTION FP_ProjectFinalize037;

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
            IF @StoredOutcome = @OutcomeCode
               AND ((@Status = 1 AND @Applied = 1)
                    OR (@Status = 2 AND @Applied = 0))
            BEGIN SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'replayed'; END
            ELSE SET @Code = N'receipt-conflict';
        END
        ELSE IF @Status = 3 SET @Code = N'rejected';
        ELSE IF @Applied = 1 AND NOT EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_ProjectAssetScanEvents
                           WITH (UPDLOCK, HOLDLOCK)
              WHERE ProjectAssetId = @AssetId AND ScanProvider = 1
                AND ProviderEventId = @ProviderEventId AND PayloadHash = @PayloadHash
                AND QuarantineBlobETag = @StoredBlobETag
                AND ((ReportedContentHash IS NULL AND @StoredReportedHash IS NULL)
                     OR ReportedContentHash = @StoredReportedHash)
                AND ToStatus = @StoredToStatus AND ResultCode = @StoredResultCode
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
            ROLLBACK TRANSACTION FP_ProjectFinalize037;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, @Status AS ReceiptStatus,
           @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Record
    @ProviderEventId NVARCHAR(200),
    @PayloadHash BINARY(32),
    @AuthenticatedTenantId UNIQUEIDENTIFIER,
    @AuthenticatedPrincipalId UNIQUEIDENTIFIER,
    @ApplicationClientId UNIQUEIDENTIFIER,
    @TopicResourceId NVARCHAR(500),
    @EventSubscriptionName NVARCHAR(100),
    @StorageAccountResourceId NVARCHAR(500),
    @BlobHost NVARCHAR(253),
    @BlobContainer NVARCHAR(63),
    @BlobObjectName NVARCHAR(1024),
    @BlobETag NVARCHAR(100),
    @ReportedContentHash BINARY(32) = NULL,
    @ToStatus TINYINT,
    @ResultCode NVARCHAR(100),
    @OccurredAtUtc DATETIME2(3),
    @ReceivedAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @ProviderEventId = LTRIM(RTRIM(@ProviderEventId));
    SET @TopicResourceId = LOWER(LTRIM(RTRIM(@TopicResourceId)));
    SET @StorageAccountResourceId = LOWER(LTRIM(RTRIM(@StorageAccountResourceId)));
    SET @BlobHost = LOWER(LTRIM(RTRIM(@BlobHost)));
    SET @BlobContainer = LOWER(LTRIM(RTRIM(@BlobContainer)));
    SET @BlobObjectName = LTRIM(RTRIM(@BlobObjectName));
    SET @BlobETag = LTRIM(RTRIM(@BlobETag));
    SET @EventSubscriptionName = LTRIM(RTRIM(@EventSubscriptionName));
    SET @ResultCode = LOWER(LTRIM(RTRIM(@ResultCode)));

    IF NULLIF(@ProviderEventId, N'') IS NULL OR LEN(@ProviderEventId) > 200
       OR @PayloadHash IS NULL OR @AuthenticatedTenantId IS NULL
       OR @AuthenticatedPrincipalId IS NULL OR @ApplicationClientId IS NULL
       OR NULLIF(@TopicResourceId, N'') IS NULL OR LEN(@TopicResourceId) > 500
       OR CHARINDEX(CHAR(10), @TopicResourceId) > 0
       OR CHARINDEX(CHAR(13), @TopicResourceId) > 0
       OR CHARINDEX(0x0000, CONVERT(VARBINARY(1000), @TopicResourceId)) > 0
       OR NULLIF(@StorageAccountResourceId, N'') IS NULL
       OR LEN(@StorageAccountResourceId) > 500
       OR CHARINDEX(CHAR(10), @StorageAccountResourceId) > 0
       OR CHARINDEX(CHAR(13), @StorageAccountResourceId) > 0
       OR CHARINDEX(0x0000, CONVERT(VARBINARY(1000), @StorageAccountResourceId)) > 0
       OR NULLIF(@EventSubscriptionName, N'') IS NULL OR LEN(@EventSubscriptionName) > 100
       OR NULLIF(@BlobHost, N'') IS NULL OR LEN(@BlobHost) > 253
       OR LEN(@BlobContainer) NOT BETWEEN 3 AND 63
       OR NULLIF(@BlobObjectName, N'') IS NULL OR LEN(@BlobObjectName) > 1024
       OR LEFT(@BlobObjectName, 1) = N'/' OR CHARINDEX(N'?', @BlobObjectName) > 0
       OR CHARINDEX(N'#', @BlobObjectName) > 0
       OR LEN(@BlobETag) NOT BETWEEN 3 AND 100
       OR LEFT(@BlobETag, 1) <> N'"' OR RIGHT(@BlobETag, 1) <> N'"'
       OR @ToStatus IS NULL OR @ToStatus NOT BETWEEN 1 AND 4
       OR (@ToStatus IN (1, 2) AND @ReportedContentHash IS NULL)
       OR NULLIF(@ResultCode, N'') IS NULL OR LEN(@ResultCode) > 100
       OR @ResultCode LIKE N'%[^-a-z0-9._]%' COLLATE Latin1_General_100_BIN2
       OR @OccurredAtUtc IS NULL OR @ReceivedAtUtc IS NULL
        THROW 55710, N'Authenticated bounded project-asset receipt metadata is required.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;
    DECLARE @PolicyId INT, @AssetId BIGINT, @AssetPublicId UNIQUEIDENTIFIER;
    DECLARE @Kind TINYINT, @StoredETag NVARCHAR(100), @StoredHash BINARY(32);
    DECLARE @ContentLength BIGINT, @MimeType NVARCHAR(100), @IsDeleted BIT;
    DECLARE @StorageStatus TINYINT, @ScanStatus TINYINT;
    DECLARE @ScanCompletedAtUtc DATETIME2(3);
    DECLARE @ReceiptId BIGINT, @ReceiptPublicId UNIQUEIDENTIFIER;
    DECLARE @ExistingPayloadHash BINARY(32), @ExistingAssetId BIGINT;
    DECLARE @ExistingTenant UNIQUEIDENTIFIER, @ExistingPrincipal UNIQUEIDENTIFIER;
    DECLARE @ExistingApp UNIQUEIDENTIFIER, @ExistingTopic NVARCHAR(500);
    DECLARE @ExistingSubscription NVARCHAR(100);
    DECLARE @ExistingStorage NVARCHAR(500), @ExistingHost NVARCHAR(253);
    DECLARE @ExistingContainer NVARCHAR(63), @ExistingObject NVARCHAR(1024);
    DECLARE @ExistingETag NVARCHAR(100), @ExistingReportedHash BINARY(32);
    DECLARE @ExistingToStatus TINYINT, @ExistingResultCode NVARCHAR(100);
    DECLARE @ReceiptStatus TINYINT, @OutcomeCode NVARCHAR(100);
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @Code NVARCHAR(50) = N'unauthorized';
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_ProjectReceipt037;

    BEGIN TRY
        SELECT @ReceiptId = Id, @ReceiptPublicId = PublicId,
               @ExistingPayloadHash = PayloadHash, @ExistingAssetId = ProjectAssetId,
               @ExistingTenant = AuthenticatedTenantId,
               @ExistingPrincipal = AuthenticatedPrincipalId,
               @ExistingApp = ApplicationClientId, @ExistingTopic = TopicResourceId,
               @ExistingSubscription = EventSubscriptionName,
               @ExistingStorage = StorageAccountResourceId, @ExistingHost = BlobHost,
               @ExistingContainer = BlobContainer, @ExistingObject = BlobObjectName,
               @ExistingETag = BlobETag, @ExistingReportedHash = ReportedContentHash,
               @ExistingToStatus = ToStatus, @ExistingResultCode = ResultCode,
               @ReceiptStatus = ReceiptStatus, @OutcomeCode = OutcomeCode
        FROM dbo.FundingPlatform_ProjectAssetDefenderReceipts WITH (UPDLOCK, HOLDLOCK)
        WHERE Provider = 1 AND ProviderEventId = @ProviderEventId;

        IF @ReceiptId IS NOT NULL
        BEGIN
            IF @ExistingPayloadHash = @PayloadHash
               AND @ExistingTenant = @AuthenticatedTenantId
               AND @ExistingPrincipal = @AuthenticatedPrincipalId
               AND @ExistingApp = @ApplicationClientId
               AND @ExistingTopic = @TopicResourceId
               AND @ExistingSubscription = @EventSubscriptionName
               AND @ExistingStorage = @StorageAccountResourceId
               AND @ExistingHost = @BlobHost
               AND @ExistingContainer = @BlobContainer
               AND @ExistingObject = @BlobObjectName
               AND @ExistingETag = @BlobETag
               AND ((@ExistingReportedHash IS NULL AND @ReportedContentHash IS NULL)
                    OR @ExistingReportedHash = @ReportedContentHash)
               AND @ExistingToStatus = @ToStatus AND @ExistingResultCode = @ResultCode
            BEGIN
                SET @WasReplay = 1;
                SET @Succeeded = CASE WHEN @ReceiptStatus IN (0, 1) THEN 1 ELSE 0 END;
                SET @Code = CASE @ReceiptStatus
                              WHEN 0 THEN N'replayed-accepted'
                              WHEN 1 THEN N'replayed-applied'
                              WHEN 2 THEN N'replayed-ignored'
                              ELSE N'replayed-rejected' END;
                SET @AssetId = @ExistingAssetId;
            END
            ELSE
            BEGIN
                SET @ReceiptPublicId = NULL; SET @AssetId = NULL;
                SET @ReceiptStatus = NULL; SET @Code = N'event-conflict';
            END;
        END
        ELSE
        BEGIN
            SELECT @PolicyId = Id
            FROM dbo.FundingPlatform_EventIngressTrustPolicies WITH (UPDLOCK, HOLDLOCK)
            WHERE WorkloadKind = 2 AND Provider = 1
              AND TenantId = @AuthenticatedTenantId
              AND PrincipalObjectId = @AuthenticatedPrincipalId
              AND ApplicationClientId = @ApplicationClientId
              AND TopicResourceId = @TopicResourceId
              AND EventSubscriptionName = @EventSubscriptionName
              AND StorageAccountResourceId = @StorageAccountResourceId
              AND StorageAccountHost = @BlobHost
              AND QuarantineBlobContainer = @BlobContainer
              AND IsEnabled = 1 AND ValidFromUtc <= @ReceivedAtUtc
              AND (ExpiresAtUtc IS NULL OR ExpiresAtUtc > @ReceivedAtUtc);

            IF @PolicyId IS NULL SET @Code = N'unauthorized';
            ELSE
            BEGIN
                SELECT @AssetId = Id, @AssetPublicId = PublicId, @Kind = Kind,
                       @StoredETag = QuarantineBlobETag, @StoredHash = ContentHash,
                       @ContentLength = ContentLength, @MimeType = VerifiedMimeType,
                       @StorageStatus = StorageStatus, @ScanStatus = ScanStatus,
                       @ScanCompletedAtUtc = ScanCompletedAtUtc, @IsDeleted = IsDeleted
                FROM dbo.FundingPlatform_ProjectAssets WITH (UPDLOCK, HOLDLOCK)
                WHERE QuarantineBlobContainer = @BlobContainer
                  AND QuarantineBlobObjectName = @BlobObjectName
                  AND ScanProvider = 1;

                SET @ReceiptStatus = 0; SET @OutcomeCode = NULL;
                IF @AssetId IS NULL
                BEGIN SET @ReceiptStatus = 3; SET @OutcomeCode = N'asset-not-found'; END
                ELSE IF @IsDeleted = 1
                BEGIN SET @ReceiptStatus = 2; SET @OutcomeCode = N'asset-deleted'; END
                ELSE IF @StoredETag <> @BlobETag
                BEGIN SET @ReceiptStatus = 3; SET @OutcomeCode = N'blob-etag-mismatch'; END
                ELSE IF @ReportedContentHash IS NOT NULL AND @StoredHash <> @ReportedContentHash
                BEGIN SET @ReceiptStatus = 3; SET @OutcomeCode = N'content-hash-mismatch'; END
                ELSE IF @OccurredAtUtc < DATEADD(DAY, -1, @ReceivedAtUtc)
                     OR @OccurredAtUtc > DATEADD(MINUTE, 5, @ReceivedAtUtc)
                BEGIN SET @ReceiptStatus = 3; SET @OutcomeCode = N'invalid-event-time'; END
                ELSE IF @StorageStatus = 1 AND @ScanStatus = 0 SET @ReceiptStatus = 0;
                ELSE IF @ScanCompletedAtUtc IS NOT NULL AND @OccurredAtUtc <= @ScanCompletedAtUtc
                BEGIN SET @ReceiptStatus = 2; SET @OutcomeCode = N'stale-scan-result'; END
                ELSE IF @ScanCompletedAtUtc IS NOT NULL AND @ToStatus = @ScanStatus
                BEGIN SET @ReceiptStatus = 2; SET @OutcomeCode = N'duplicate-scan-result'; END
                ELSE IF @StorageStatus = 2 AND @ScanStatus = 1
                     AND @ToStatus IN (2, 3, 4) SET @ReceiptStatus = 0;
                ELSE IF @ScanStatus IN (1, 2, 3, 4)
                BEGIN
                    SET @ReceiptStatus = 3;
                    SET @OutcomeCode = N'terminal-scan-result-conflict';
                END
                ELSE
                BEGIN SET @ReceiptStatus = 3; SET @OutcomeCode = N'invalid-asset-state'; END;

                DECLARE @InsertedReceipt TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER);
                INSERT INTO dbo.FundingPlatform_ProjectAssetDefenderReceipts
                    (TrustPolicyId, WorkloadKind, ProjectAssetId, Provider,
                     ProviderEventId, PayloadHash, TopicResourceId,
                     AuthenticatedTenantId, AuthenticatedPrincipalId,
                     ApplicationClientId, EventSubscriptionName,
                     StorageAccountResourceId, BlobHost, BlobContainer,
                     BlobObjectName, BlobETag, ReportedContentHash, ToStatus,
                     ResultCode, ReceiptStatus, OutcomeCode, OccurredAtUtc,
                     ReceivedAtUtc, FinalizedAtUtc, CreatedAtUtc)
                OUTPUT inserted.Id, inserted.PublicId INTO @InsertedReceipt (Id, PublicId)
                VALUES (@PolicyId, 2, @AssetId, 1, @ProviderEventId, @PayloadHash,
                        @TopicResourceId, @AuthenticatedTenantId,
                        @AuthenticatedPrincipalId, @ApplicationClientId,
                        @EventSubscriptionName, @StorageAccountResourceId,
                        @BlobHost, @BlobContainer, @BlobObjectName, @BlobETag,
                        @ReportedContentHash, @ToStatus, @ResultCode, @ReceiptStatus,
                        @OutcomeCode, @OccurredAtUtc, @ReceivedAtUtc,
                        CASE WHEN @ReceiptStatus IN (2, 3) THEN @ReceivedAtUtc END,
                        @NowUtc);
                SELECT @ReceiptId = Id, @ReceiptPublicId = PublicId FROM @InsertedReceipt;

                IF @ReceiptStatus = 0
                BEGIN SET @Succeeded = 1; SET @Code = N'accepted'; END
                ELSE SET @Code = @OutcomeCode;
            END;
        END;

        IF @AssetId IS NOT NULL AND @AssetPublicId IS NULL
            SELECT @AssetPublicId = PublicId, @Kind = Kind,
                   @StoredETag = QuarantineBlobETag, @StoredHash = ContentHash,
                   @ContentLength = ContentLength, @MimeType = VerifiedMimeType
            FROM dbo.FundingPlatform_ProjectAssets WHERE Id = @AssetId;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @StartedTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ProjectReceipt037;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, @ReceiptPublicId AS ReceiptPublicId,
           CASE WHEN @Succeeded = 1 THEN @AssetPublicId END AS ProjectAssetPublicId,
           CAST(1 AS TINYINT) AS ScanProvider,
           CASE WHEN @Succeeded = 1 THEN @Kind END AS Kind,
           CASE WHEN @Succeeded = 1 THEN @BlobContainer END AS QuarantineBlobContainer,
           CASE WHEN @Succeeded = 1 THEN @BlobObjectName END AS QuarantineBlobObjectName,
           CASE WHEN @Succeeded = 1 THEN @StoredETag END AS QuarantineBlobETag,
           CASE WHEN @Succeeded = 1 THEN @StoredHash END AS ContentHash,
           CASE WHEN @Succeeded = 1 THEN @ContentLength END AS ContentLength,
           CASE WHEN @Succeeded = 1 THEN @MimeType END AS MimeType,
           @WasReplay AS WasReplay;
END;
GO

/* Pending results terminalize once. A later authenticated Defender terminal
   result can supersede Clean for the same immutable quarantine blob version. */
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
    @TrustedBlobContainer NVARCHAR(63) = NULL,
    @TrustedBlobObjectName NVARCHAR(1024) = NULL,
    @TrustedBlobETag NVARCHAR(100) = NULL,
    @TrustedBlobVersionId NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @AssetId BIGINT, @ProjectId BIGINT, @StoredProvider TINYINT;
    DECLARE @StoredStorageStatus TINYINT, @StoredScanStatus TINYINT;
    DECLARE @StoredQuarantineETag NVARCHAR(100), @StoredContentHash BINARY(32);
    DECLARE @StoredCreatedAtUtc DATETIME2(3), @StoredScanStartedAtUtc DATETIME2(3);
    DECLARE @StoredScanCompletedAtUtc DATETIME2(3), @IsDeleted BIT;
    DECLARE @AssetRowVersion BINARY(8), @ProjectRowVersion BINARY(8);
    DECLARE @ExpectedTrustedContainer NVARCHAR(63);
    DECLARE @ExpectedTrustedObjectName NVARCHAR(1024);
    DECLARE @AuthorizedReceiptAssetId BIGINT;
    DECLARE @ExistingAssetId BIGINT, @ExistingPayloadHash BINARY(32);
    DECLARE @ExistingFromStatus TINYINT, @ExistingToStatus TINYINT;
    DECLARE @ExistingQuarantineETag NVARCHAR(100);
    DECLARE @ExistingReportedHash BINARY(32), @ExistingResultCode NVARCHAR(100);
    DECLARE @ExistingResultRowVersion BINARY(8);
    DECLARE @RevokedContainer NVARCHAR(63), @RevokedObject NVARCHAR(1024);
    DECLARE @RevokedETag NVARCHAR(100), @RevokedVersionId NVARCHAR(200);
    DECLARE @Code NVARCHAR(50) = N'not-found';
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT, @StartedTransaction BIT = 0;

    SET @ProviderEventId = LTRIM(RTRIM(@ProviderEventId));
    SET @QuarantineBlobETag = LTRIM(RTRIM(@QuarantineBlobETag));
    SET @ResultCode = LOWER(LTRIM(RTRIM(@ResultCode)));
    SET @TrustedBlobContainer = NULLIF(LTRIM(RTRIM(@TrustedBlobContainer)), N'');
    SET @TrustedBlobObjectName = NULLIF(LTRIM(RTRIM(@TrustedBlobObjectName)), N'');
    SET @TrustedBlobETag = NULLIF(LTRIM(RTRIM(@TrustedBlobETag)), N'');
    SET @TrustedBlobVersionId = NULLIF(LTRIM(RTRIM(@TrustedBlobVersionId)), N'');

    IF @AssetPublicId IS NULL
       OR @ScanProvider IS NULL OR @ScanProvider NOT BETWEEN 0 AND 1
       OR NULLIF(@ProviderEventId, N'') IS NULL OR LEN(@ProviderEventId) > 200
       OR CHARINDEX(CHAR(10), @ProviderEventId) > 0
       OR CHARINDEX(CHAR(13), @ProviderEventId) > 0
       OR @PayloadHash IS NULL
       OR (@ToStatus IN (1, 2) AND @ReportedContentHash IS NULL)
       OR LEN(COALESCE(@QuarantineBlobETag, N'')) NOT BETWEEN 3 AND 100
       OR LEFT(@QuarantineBlobETag, 1) <> N'"'
       OR RIGHT(@QuarantineBlobETag, 1) <> N'"'
       OR CHARINDEX(CHAR(10), @QuarantineBlobETag) > 0
       OR CHARINDEX(CHAR(13), @QuarantineBlobETag) > 0
       OR @ToStatus IS NULL OR @ToStatus NOT BETWEEN 1 AND 4
       OR NULLIF(@ResultCode, N'') IS NULL OR LEN(@ResultCode) > 100
       OR @ResultCode LIKE N'%[^-a-z0-9._]%' COLLATE Latin1_General_100_BIN2
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
            OR (@ScanProvider = 1 AND @TrustedBlobVersionId IS NULL)))
       OR (@ToStatus <> 1 AND
           (@TrustedBlobContainer IS NOT NULL OR @TrustedBlobObjectName IS NOT NULL
            OR @TrustedBlobETag IS NOT NULL OR @TrustedBlobVersionId IS NOT NULL))
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
               CAST(NULL AS NVARCHAR(200)) AS RevokedTrustedBlobVersionId;
        RETURN;
    END;

    IF @InitialTransactionCount = 0
    BEGIN BEGIN TRANSACTION; SET @StartedTransaction = 1; END
    ELSE SAVE TRANSACTION FP_ApplyProjectAsset037;

    BEGIN TRY
        IF @ScanProvider = 1
            SELECT @AuthorizedReceiptAssetId = receipts.ProjectAssetId
            FROM dbo.FundingPlatform_ProjectAssetDefenderReceipts AS receipts
                 WITH (UPDLOCK, HOLDLOCK)
            WHERE receipts.Provider = 1
              AND receipts.ProviderEventId = @ProviderEventId
              AND receipts.PayloadHash = @PayloadHash
              AND receipts.BlobETag = @QuarantineBlobETag
              AND ((receipts.ReportedContentHash IS NULL AND @ReportedContentHash IS NULL)
                   OR receipts.ReportedContentHash = @ReportedContentHash)
              AND receipts.ToStatus = @ToStatus
              AND receipts.ResultCode = @ResultCode
              AND receipts.OccurredAtUtc = @OccurredAtUtc
              AND receipts.ReceiptStatus IN (0, 1);

        SELECT @AssetId = assets.Id, @ProjectId = assets.ProjectId,
               @StoredProvider = assets.ScanProvider,
               @StoredStorageStatus = assets.StorageStatus,
               @StoredScanStatus = assets.ScanStatus,
               @StoredQuarantineETag = assets.QuarantineBlobETag,
               @StoredContentHash = assets.ContentHash,
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

        /* Match the watchdog's asset -> scan-event lock order. Defender adds
           its receipt lock first, which also serializes Finalize. */
        SELECT @ExistingAssetId = events.ProjectAssetId,
               @ExistingPayloadHash = events.PayloadHash,
               @ExistingFromStatus = events.FromStatus,
               @ExistingToStatus = events.ToStatus,
               @ExistingQuarantineETag = events.QuarantineBlobETag,
               @ExistingReportedHash = events.ReportedContentHash,
               @ExistingResultCode = events.ResultCode,
               @ExistingResultRowVersion = events.ResultRowVersion,
               @RevokedContainer = events.RevokedTrustedBlobContainer,
               @RevokedObject = events.RevokedTrustedBlobObjectName,
               @RevokedETag = events.RevokedTrustedBlobETag,
               @RevokedVersionId = events.RevokedTrustedBlobVersionId
        FROM dbo.FundingPlatform_ProjectAssetScanEvents AS events WITH (UPDLOCK, HOLDLOCK)
        WHERE events.ScanProvider = @ScanProvider
          AND events.ProviderEventId = @ProviderEventId;

        IF @ScanProvider = 1
           AND (@AuthorizedReceiptAssetId IS NULL OR @AuthorizedReceiptAssetId <> @AssetId)
            SET @Code = N'defender-receipt-required';
        ELSE IF @ExistingAssetId IS NOT NULL
        BEGIN
            IF @AssetId = @ExistingAssetId
               AND @ExistingPayloadHash = @PayloadHash
               AND @ExistingToStatus = @ToStatus
               AND @ExistingQuarantineETag = @QuarantineBlobETag
               AND @ExistingResultCode = @ResultCode
               AND ((@ExistingReportedHash IS NULL AND @ReportedContentHash IS NULL)
                    OR @ExistingReportedHash = @ReportedContentHash)
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
        ELSE IF @StoredQuarantineETag <> @QuarantineBlobETag SET @Code = N'etag-mismatch';
        ELSE IF @OccurredAtUtc < @StoredCreatedAtUtc
             OR (@StoredScanStartedAtUtc IS NOT NULL
                 AND @OccurredAtUtc < @StoredScanStartedAtUtc)
            SET @Code = N'invalid-event-time';
        ELSE IF @ReportedContentHash IS NOT NULL
             AND @StoredContentHash <> @ReportedContentHash
            SET @Code = N'hash-mismatch';
        ELSE IF @StoredStorageStatus = 1 AND @StoredScanStatus = 0
        BEGIN
            IF @ToStatus = 1 AND
               (@ExpectedTrustedContainer IS NULL OR @ExpectedTrustedObjectName IS NULL
                OR @TrustedBlobContainer <> @ExpectedTrustedContainer
                OR @TrustedBlobObjectName <> @ExpectedTrustedObjectName)
                SET @Code = N'trusted-destination-mismatch';
            ELSE
            BEGIN
                DECLARE @EventId UNIQUEIDENTIFIER = NEWID();
                DECLARE @UpdatedAsset TABLE (RowVersion BINARY(8) NOT NULL);
                UPDATE dbo.FundingPlatform_ProjectAssets
                SET StorageStatus = CASE WHEN @ToStatus = 1 THEN 2 ELSE 3 END,
                    ScanStatus = @ToStatus, ScanResultCode = @ResultCode,
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
                    UpdatedAtUtc = @NowUtc
                OUTPUT inserted.RowVersion INTO @UpdatedAsset (RowVersion)
                WHERE Id = @AssetId AND StorageStatus = 1 AND ScanStatus = 0;
                SELECT @AssetRowVersion = RowVersion FROM @UpdatedAsset;
                IF @AssetRowVersion IS NULL
                    THROW 55712, N'Project asset changed during scan application.', 1;

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
                VALUES (@EventId, @AssetId, @ScanProvider, @ProviderEventId,
                        @PayloadHash, 0, @ToStatus, @QuarantineBlobETag,
                        @ReportedContentHash, @ResultCode, @AssetRowVersion,
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
        BEGIN
            IF @StoredScanCompletedAtUtc IS NULL
               OR @OccurredAtUtc <= @StoredScanCompletedAtUtc
                SET @Code = N'stale-scan-result';
            ELSE
            BEGIN
                SELECT @RevokedContainer = TrustedBlobContainer,
                       @RevokedObject = TrustedBlobObjectName,
                       @RevokedETag = TrustedBlobETag,
                       @RevokedVersionId = TrustedBlobVersionId
                FROM dbo.FundingPlatform_ProjectAssets WITH (HOLDLOCK)
                WHERE Id = @AssetId;

                IF @RevokedContainer IS NULL OR @RevokedObject IS NULL
                   OR @RevokedETag IS NULL OR @RevokedVersionId IS NULL
                    SET @Code = N'trusted-blob-identity-missing';
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
                        IsCover = 0, UpdatedAtUtc = @NowUtc
                    OUTPUT inserted.RowVersion INTO @RevokedAsset (RowVersion)
                    WHERE Id = @AssetId AND StorageStatus = 2 AND ScanStatus = 1;
                    SELECT @AssetRowVersion = RowVersion FROM @RevokedAsset;
                    IF @AssetRowVersion IS NULL
                        THROW 55713, N'Project asset changed during trust revocation.', 1;

                    DECLARE @RevokedProject TABLE (RowVersion BINARY(8) NOT NULL);
                    UPDATE dbo.FundingPlatform_Projects
                    SET UpdatedAtUtc = @NowUtc
                    OUTPUT inserted.RowVersion INTO @RevokedProject (RowVersion)
                    WHERE Id = @ProjectId;
                    SELECT @ProjectRowVersion = RowVersion FROM @RevokedProject;

                    INSERT INTO dbo.FundingPlatform_ProjectAssetScanEvents
                        (EventId, ProjectAssetId, ScanProvider, ProviderEventId,
                         PayloadHash, FromStatus, ToStatus, QuarantineBlobETag,
                         ReportedContentHash, ResultCode, ResultRowVersion,
                         OccurredAtUtc, CreatedAtUtc,
                         RevokedTrustedBlobContainer, RevokedTrustedBlobObjectName,
                         RevokedTrustedBlobETag, RevokedTrustedBlobVersionId)
                    VALUES (@RevokeEventId, @AssetId, @ScanProvider, @ProviderEventId,
                            @PayloadHash, 1, @ToStatus, @QuarantineBlobETag,
                            @ReportedContentHash, @ResultCode, @AssetRowVersion,
                            @OccurredAtUtc, @NowUtc, @RevokedContainer, @RevokedObject,
                            @RevokedETag, @RevokedVersionId);

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
            ROLLBACK TRANSACTION FP_ApplyProjectAsset037;
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
                THEN @RevokedVersionId END AS RevokedTrustedBlobVersionId;
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
    ELSE SAVE TRANSACTION FP_ProjectWatchdog037;

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
             FromStatus, ToStatus, QuarantineBlobETag, ReportedContentHash,
             ResultCode, ResultRowVersion, OccurredAtUtc, CreatedAtUtc)
        SELECT timedOut.EventId, timedOut.Id, 1, timedOut.ProviderEventId,
               HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
                   timedOut.ProviderEventId COLLATE Latin1_General_100_BIN2_UTF8))),
               0, 4, timedOut.QuarantineBlobETag, NULL,
               N'defender-timeout', timedOut.AssetRowVersion, @NowUtc, @NowUtc
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
            ROLLBACK TRANSACTION FP_ProjectWatchdog037;
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

/* The project-asset messages are audit-ledger facts, never worker commands.
   Preserve the cumulative 016/017/019 sink behind a versioned wrapper and
   consume only exact, currently unversioned 036/037 payload schemas. */
DECLARE @Pre037AuditSinkDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge', N'P'));
IF @Pre037AuditSinkDefinition NOT LIKE N'%FundingApplicationCreated%'
   OR @Pre037AuditSinkDefinition NOT LIKE N'%FundingApplicationUpdated%'
    THROW 55720, N'Project asset audit sink requires the cumulative migration 019 wrapper.', 1;

EXEC sys.sp_rename
    @objname = N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge',
    @newname = N'FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre037',
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
        THROW 55721, N'BatchSize must be between 1 and 500.', 1;
    IF @NowUtc IS NULL THROW 55722, N'NowUtc is required.', 1;

    /* Compatibility markers for downstream migration smokes: the delegated
       Pre037 sink retains FundingApplicationCreated/FundingApplicationUpdated;
       this layer validates its own schemas with OPENJSON(PayloadJson). */
    DECLARE @PreviousCount INT = 0;
    EXEC dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre037
        @BatchSize = @BatchSize, @NowUtc = @NowUtc,
        @AcknowledgedCount = @PreviousCount OUTPUT;

    DECLARE @Remaining INT = @BatchSize - @PreviousCount, @CurrentCount INT = 0;
    IF @Remaining > 0
    BEGIN
        ;WITH ProjectAssetAuditEvents AS
        (
            SELECT TOP (@Remaining) messages.*
            FROM dbo.FundingPlatform_OutboxMessages AS messages
                 WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
            WHERE messages.DispatchedAtUtc IS NULL
              AND messages.AvailableAtUtc <= @NowUtc
              AND (messages.LeaseUntilUtc IS NULL OR messages.LeaseUntilUtc <= @NowUtc)
              AND LEFT(LTRIM(messages.PayloadJson), 1) = N'{'
              AND RIGHT(RTRIM(messages.PayloadJson), 1) = N'}'
              AND
              (
                  (messages.MessageType COLLATE Latin1_General_100_BIN2 = N'ProjectAssetUploadIntentCreated'
                   AND messages.AggregateType COLLATE Latin1_General_100_BIN2 = N'ProjectAssetUploadIntent'
                   AND LEN(messages.AggregateId) = 36
                   AND TRY_CONVERT(UNIQUEIDENTIFIER, messages.AggregateId) =
                       TRY_CONVERT(UNIQUEIDENTIFIER,
                                   JSON_VALUE(messages.PayloadJson, N'$.intentPublicId'))
                   AND TRY_CONVERT(UNIQUEIDENTIFIER,
                                   JSON_VALUE(messages.PayloadJson, N'$.projectPublicId')) IS NOT NULL
                   AND TRY_CONVERT(TINYINT,
                                   JSON_VALUE(messages.PayloadJson, N'$.kind')) IN (0, 1)
                   AND TRY_CONVERT(TINYINT,
                                   JSON_VALUE(messages.PayloadJson, N'$.status')) = 0
                   AND (SELECT COUNT_BIG(1) FROM OPENJSON(PayloadJson)) = 4
                   AND NOT EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 NOT IN
                              (N'intentPublicId', N'projectPublicId', N'kind', N'status'))
                   AND EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 = N'intentPublicId'
                          AND fields.[type] = 1)
                   AND EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 = N'projectPublicId'
                          AND fields.[type] = 1)
                   AND EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 = N'kind'
                          AND fields.[type] = 2)
                   AND EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 = N'status'
                          AND fields.[type] = 2))
                  OR
                  (messages.MessageType COLLATE Latin1_General_100_BIN2 = N'ProjectAssetUploadIntentRejected'
                   AND messages.AggregateType COLLATE Latin1_General_100_BIN2 = N'ProjectAssetUploadIntent'
                   AND LEN(messages.AggregateId) = 36
                   AND TRY_CONVERT(UNIQUEIDENTIFIER, messages.AggregateId) =
                       TRY_CONVERT(UNIQUEIDENTIFIER,
                                   JSON_VALUE(messages.PayloadJson, N'$.intentPublicId'))
                   AND TRY_CONVERT(UNIQUEIDENTIFIER,
                                   JSON_VALUE(messages.PayloadJson, N'$.projectPublicId')) IS NOT NULL
                   AND TRY_CONVERT(TINYINT,
                                   JSON_VALUE(messages.PayloadJson, N'$.status')) = 4
                   AND NULLIF(LTRIM(RTRIM(
                           JSON_VALUE(messages.PayloadJson, N'$.errorCode'))), N'') IS NOT NULL
                   AND LEN(JSON_VALUE(messages.PayloadJson, N'$.errorCode')) <= 100
                   AND CHARINDEX(CHAR(10), JSON_VALUE(messages.PayloadJson, N'$.errorCode')) = 0
                   AND CHARINDEX(CHAR(13), JSON_VALUE(messages.PayloadJson, N'$.errorCode')) = 0
                   AND (SELECT COUNT_BIG(1) FROM OPENJSON(PayloadJson)) = 4
                   AND NOT EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 NOT IN
                              (N'intentPublicId', N'projectPublicId', N'status', N'errorCode'))
                   AND EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 = N'intentPublicId'
                          AND fields.[type] = 1)
                   AND EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 = N'projectPublicId'
                          AND fields.[type] = 1)
                   AND EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 = N'status'
                          AND fields.[type] = 2)
                   AND EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 = N'errorCode'
                          AND fields.[type] = 1))
                  OR
                  (messages.MessageType COLLATE Latin1_General_100_BIN2 = N'ProjectAssetFinalized'
                   AND messages.AggregateType COLLATE Latin1_General_100_BIN2 = N'ProjectAsset'
                   AND LEN(messages.AggregateId) = 36
                   AND TRY_CONVERT(UNIQUEIDENTIFIER, messages.AggregateId) =
                       TRY_CONVERT(UNIQUEIDENTIFIER,
                                   JSON_VALUE(messages.PayloadJson, N'$.assetPublicId'))
                   AND TRY_CONVERT(UNIQUEIDENTIFIER,
                                   JSON_VALUE(messages.PayloadJson, N'$.projectPublicId')) IS NOT NULL
                   AND TRY_CONVERT(UNIQUEIDENTIFIER,
                                   JSON_VALUE(messages.PayloadJson, N'$.intentPublicId')) IS NOT NULL
                   AND TRY_CONVERT(TINYINT,
                                   JSON_VALUE(messages.PayloadJson, N'$.kind')) IN (0, 1)
                   AND TRY_CONVERT(TINYINT,
                                   JSON_VALUE(messages.PayloadJson, N'$.storageStatus')) = 0
                   AND TRY_CONVERT(TINYINT,
                                   JSON_VALUE(messages.PayloadJson, N'$.scanStatus')) = 0
                   AND TRY_CONVERT(TINYINT,
                                   JSON_VALUE(messages.PayloadJson, N'$.scanProvider')) BETWEEN 0 AND 1
                   AND (SELECT COUNT_BIG(1) FROM OPENJSON(PayloadJson)) = 7
                   AND NOT EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 NOT IN
                              (N'assetPublicId', N'projectPublicId', N'intentPublicId', N'kind',
                               N'storageStatus', N'scanStatus', N'scanProvider'))
                   AND (SELECT COUNT_BIG(1) FROM OPENJSON(PayloadJson) AS fields
                        WHERE (fields.[key] COLLATE Latin1_General_100_BIN2 IN
                                   (N'assetPublicId', N'projectPublicId', N'intentPublicId')
                               AND fields.[type] = 1)
                           OR (fields.[key] COLLATE Latin1_General_100_BIN2 IN
                                   (N'kind', N'storageStatus', N'scanStatus', N'scanProvider')
                               AND fields.[type] = 2)) = 7)
                  OR
                  (messages.MessageType COLLATE Latin1_General_100_BIN2 = N'ProjectAssetQuarantined'
                   AND messages.AggregateType COLLATE Latin1_General_100_BIN2 = N'ProjectAsset'
                   AND LEN(messages.AggregateId) = 36
                   AND TRY_CONVERT(UNIQUEIDENTIFIER, messages.AggregateId) =
                       TRY_CONVERT(UNIQUEIDENTIFIER,
                                   JSON_VALUE(messages.PayloadJson, N'$.assetPublicId'))
                   AND TRY_CONVERT(UNIQUEIDENTIFIER,
                                   JSON_VALUE(messages.PayloadJson, N'$.projectPublicId')) IS NOT NULL
                   AND TRY_CONVERT(TINYINT,
                                   JSON_VALUE(messages.PayloadJson, N'$.storageStatus')) = 1
                   AND TRY_CONVERT(TINYINT,
                                   JSON_VALUE(messages.PayloadJson, N'$.scanStatus')) = 0
                   AND TRY_CONVERT(TINYINT,
                                   JSON_VALUE(messages.PayloadJson, N'$.scanProvider')) BETWEEN 0 AND 1
                   AND (SELECT COUNT_BIG(1) FROM OPENJSON(PayloadJson)) = 5
                   AND NOT EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 NOT IN
                              (N'assetPublicId', N'projectPublicId', N'storageStatus',
                               N'scanStatus', N'scanProvider'))
                   AND (SELECT COUNT_BIG(1) FROM OPENJSON(PayloadJson) AS fields
                        WHERE (fields.[key] COLLATE Latin1_General_100_BIN2 IN
                                   (N'assetPublicId', N'projectPublicId') AND fields.[type] = 1)
                           OR (fields.[key] COLLATE Latin1_General_100_BIN2 IN
                                   (N'storageStatus', N'scanStatus', N'scanProvider')
                               AND fields.[type] = 2)) = 5)
                  OR
                  (messages.MessageType COLLATE Latin1_General_100_BIN2 = N'ProjectAssetScanCompleted'
                   AND messages.AggregateType COLLATE Latin1_General_100_BIN2 = N'ProjectAsset'
                   AND LEN(messages.AggregateId) = 36
                   AND TRY_CONVERT(UNIQUEIDENTIFIER, messages.AggregateId) =
                       TRY_CONVERT(UNIQUEIDENTIFIER,
                                   JSON_VALUE(messages.PayloadJson, N'$.assetPublicId'))
                   AND messages.MessageId = TRY_CONVERT(UNIQUEIDENTIFIER,
                                   JSON_VALUE(messages.PayloadJson, N'$.eventId'))
                   AND TRY_CONVERT(TINYINT,
                                   JSON_VALUE(messages.PayloadJson, N'$.scanProvider')) BETWEEN 0 AND 1
                   AND TRY_CONVERT(TINYINT,
                                   JSON_VALUE(messages.PayloadJson, N'$.scanStatus')) BETWEEN 1 AND 4
                   AND TRY_CONVERT(TINYINT,
                                   JSON_VALUE(messages.PayloadJson, N'$.storageStatus')) =
                       CASE WHEN TRY_CONVERT(TINYINT,
                                      JSON_VALUE(messages.PayloadJson, N'$.scanStatus')) = 1
                            THEN 2 ELSE 3 END
                   AND NULLIF(LTRIM(RTRIM(
                           JSON_VALUE(messages.PayloadJson, N'$.resultCode'))), N'') IS NOT NULL
                   AND LEN(JSON_VALUE(messages.PayloadJson, N'$.resultCode')) <= 100
                   AND CHARINDEX(CHAR(10), JSON_VALUE(messages.PayloadJson, N'$.resultCode')) = 0
                   AND CHARINDEX(CHAR(13), JSON_VALUE(messages.PayloadJson, N'$.resultCode')) = 0
                   AND JSON_VALUE(messages.PayloadJson, N'$.resultCode')
                       NOT LIKE N'%[^-a-z0-9._]%' COLLATE Latin1_General_100_BIN2
                   AND (SELECT COUNT_BIG(1) FROM OPENJSON(PayloadJson)) = 6
                   AND NOT EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 NOT IN
                              (N'eventId', N'assetPublicId', N'scanProvider', N'scanStatus',
                               N'storageStatus', N'resultCode'))
                   AND (SELECT COUNT_BIG(1) FROM OPENJSON(PayloadJson) AS fields
                        WHERE (fields.[key] COLLATE Latin1_General_100_BIN2 IN
                                   (N'eventId', N'assetPublicId', N'resultCode')
                               AND fields.[type] = 1)
                           OR (fields.[key] COLLATE Latin1_General_100_BIN2 IN
                                   (N'scanProvider', N'scanStatus', N'storageStatus')
                               AND fields.[type] = 2)) = 6)
                  OR
                  (messages.MessageType COLLATE Latin1_General_100_BIN2 = N'ProjectAssetMetadataUpdated'
                   AND messages.AggregateType COLLATE Latin1_General_100_BIN2 = N'ProjectAsset'
                   AND LEN(messages.AggregateId) = 36
                   AND TRY_CONVERT(UNIQUEIDENTIFIER, messages.AggregateId) =
                       TRY_CONVERT(UNIQUEIDENTIFIER,
                                   JSON_VALUE(messages.PayloadJson, N'$.assetPublicId'))
                   AND TRY_CONVERT(UNIQUEIDENTIFIER,
                                   JSON_VALUE(messages.PayloadJson, N'$.projectPublicId')) IS NOT NULL
                   AND EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 = N'isCover'
                          AND fields.[type] = 3)
                   AND (SELECT COUNT_BIG(1) FROM OPENJSON(PayloadJson)) = 3
                   AND NOT EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 NOT IN
                              (N'assetPublicId', N'projectPublicId', N'isCover'))
                   AND (SELECT COUNT_BIG(1) FROM OPENJSON(PayloadJson) AS fields
                        WHERE (fields.[key] COLLATE Latin1_General_100_BIN2 IN
                                   (N'assetPublicId', N'projectPublicId') AND fields.[type] = 1)
                           OR (fields.[key] COLLATE Latin1_General_100_BIN2 = N'isCover'
                               AND fields.[type] = 3)) = 3)
                  OR
                  (messages.MessageType COLLATE Latin1_General_100_BIN2 = N'ProjectAssetsReordered'
                   AND messages.AggregateType COLLATE Latin1_General_100_BIN2 = N'Project'
                   AND TRY_CONVERT(BIGINT, messages.AggregateId) IS NOT NULL
                   AND CONVERT(NVARCHAR(100), TRY_CONVERT(BIGINT, messages.AggregateId)) =
                       messages.AggregateId
                   AND EXISTS
                       (SELECT 1 FROM dbo.FundingPlatform_Projects AS projects
                        WHERE projects.Id = TRY_CONVERT(BIGINT, messages.AggregateId)
                          AND projects.PublicId = TRY_CONVERT(UNIQUEIDENTIFIER,
                                  JSON_VALUE(messages.PayloadJson, N'$.projectPublicId')))
                   AND TRY_CONVERT(INT,
                           JSON_VALUE(messages.PayloadJson, N'$.assetCount')) BETWEEN 1 AND 32768
                   AND (SELECT COUNT_BIG(1) FROM OPENJSON(PayloadJson)) = 2
                   AND NOT EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 NOT IN
                              (N'projectPublicId', N'assetCount'))
                   AND (SELECT COUNT_BIG(1) FROM OPENJSON(PayloadJson) AS fields
                        WHERE (fields.[key] COLLATE Latin1_General_100_BIN2 = N'projectPublicId'
                               AND fields.[type] = 1)
                           OR (fields.[key] COLLATE Latin1_General_100_BIN2 = N'assetCount'
                               AND fields.[type] = 2)) = 2)
                  OR
                  (messages.MessageType COLLATE Latin1_General_100_BIN2 = N'ProjectAssetDeleted'
                   AND messages.AggregateType COLLATE Latin1_General_100_BIN2 = N'ProjectAsset'
                   AND LEN(messages.AggregateId) = 36
                   AND TRY_CONVERT(UNIQUEIDENTIFIER, messages.AggregateId) =
                       TRY_CONVERT(UNIQUEIDENTIFIER,
                                   JSON_VALUE(messages.PayloadJson, N'$.assetPublicId'))
                   AND TRY_CONVERT(UNIQUEIDENTIFIER,
                                   JSON_VALUE(messages.PayloadJson, N'$.projectPublicId')) IS NOT NULL
                   AND (SELECT COUNT_BIG(1) FROM OPENJSON(PayloadJson)) = 2
                   AND NOT EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 NOT IN
                              (N'assetPublicId', N'projectPublicId'))
                   AND (SELECT COUNT_BIG(1) FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 IN
                                  (N'assetPublicId', N'projectPublicId')
                          AND fields.[type] = 1) = 2)
                  OR
                  (messages.MessageType COLLATE Latin1_General_100_BIN2 = N'ProjectAssetScanTrustRevoked'
                   AND messages.AggregateType COLLATE Latin1_General_100_BIN2 = N'ProjectAsset'
                   AND LEN(messages.AggregateId) = 36
                   AND TRY_CONVERT(UNIQUEIDENTIFIER, messages.AggregateId) =
                       TRY_CONVERT(UNIQUEIDENTIFIER,
                                   JSON_VALUE(messages.PayloadJson, N'$.assetPublicId'))
                   AND messages.MessageId = TRY_CONVERT(UNIQUEIDENTIFIER,
                                   JSON_VALUE(messages.PayloadJson, N'$.eventId'))
                   AND TRY_CONVERT(TINYINT,
                                   JSON_VALUE(messages.PayloadJson, N'$.scanStatus')) BETWEEN 2 AND 4
                   AND TRY_CONVERT(TINYINT,
                                   JSON_VALUE(messages.PayloadJson, N'$.storageStatus')) = 3
                   AND NULLIF(LTRIM(RTRIM(
                           JSON_VALUE(messages.PayloadJson, N'$.resultCode'))), N'') IS NOT NULL
                   AND LEN(JSON_VALUE(messages.PayloadJson, N'$.resultCode')) <= 100
                   AND CHARINDEX(CHAR(10), JSON_VALUE(messages.PayloadJson, N'$.resultCode')) = 0
                   AND CHARINDEX(CHAR(13), JSON_VALUE(messages.PayloadJson, N'$.resultCode')) = 0
                   AND JSON_VALUE(messages.PayloadJson, N'$.resultCode')
                       NOT LIKE N'%[^-a-z0-9._]%' COLLATE Latin1_General_100_BIN2
                   AND (SELECT COUNT_BIG(1) FROM OPENJSON(PayloadJson)) = 5
                   AND NOT EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 NOT IN
                              (N'eventId', N'assetPublicId', N'scanStatus',
                               N'storageStatus', N'resultCode'))
                   AND (SELECT COUNT_BIG(1) FROM OPENJSON(PayloadJson) AS fields
                        WHERE (fields.[key] COLLATE Latin1_General_100_BIN2 IN
                                   (N'eventId', N'assetPublicId', N'resultCode')
                               AND fields.[type] = 1)
                           OR (fields.[key] COLLATE Latin1_General_100_BIN2 IN
                                   (N'scanStatus', N'storageStatus') AND fields.[type] = 2)) = 5)
                  OR
                  (messages.MessageType COLLATE Latin1_General_100_BIN2 = N'ProjectAssetScanTimedOut'
                   AND messages.AggregateType COLLATE Latin1_General_100_BIN2 = N'ProjectAsset'
                   AND LEN(messages.AggregateId) = 36
                   AND TRY_CONVERT(UNIQUEIDENTIFIER, messages.AggregateId) =
                       TRY_CONVERT(UNIQUEIDENTIFIER,
                                   JSON_VALUE(messages.PayloadJson, N'$.assetPublicId'))
                   AND messages.MessageId = TRY_CONVERT(UNIQUEIDENTIFIER,
                                   JSON_VALUE(messages.PayloadJson, N'$.eventId'))
                   AND TRY_CONVERT(TINYINT,
                                   JSON_VALUE(messages.PayloadJson, N'$.scanProvider')) = 1
                   AND TRY_CONVERT(TINYINT,
                                   JSON_VALUE(messages.PayloadJson, N'$.scanStatus')) = 4
                   AND TRY_CONVERT(TINYINT,
                                   JSON_VALUE(messages.PayloadJson, N'$.storageStatus')) = 3
                   AND JSON_VALUE(messages.PayloadJson, N'$.resultCode') = N'defender-timeout'
                   AND (SELECT COUNT_BIG(1) FROM OPENJSON(PayloadJson)) = 6
                   AND NOT EXISTS
                       (SELECT 1 FROM OPENJSON(PayloadJson) AS fields
                        WHERE fields.[key] COLLATE Latin1_General_100_BIN2 NOT IN
                              (N'eventId', N'assetPublicId', N'scanProvider', N'scanStatus',
                               N'storageStatus', N'resultCode'))
                   AND (SELECT COUNT_BIG(1) FROM OPENJSON(PayloadJson) AS fields
                        WHERE (fields.[key] COLLATE Latin1_General_100_BIN2 IN
                                   (N'eventId', N'assetPublicId', N'resultCode')
                               AND fields.[type] = 1)
                           OR (fields.[key] COLLATE Latin1_General_100_BIN2 IN
                                   (N'scanProvider', N'scanStatus', N'storageStatus')
                               AND fields.[type] = 2)) = 6)
              )
            ORDER BY messages.AvailableAtUtc, messages.Id
        )
        UPDATE ProjectAssetAuditEvents
        SET DispatchedAtUtc = @NowUtc, LeaseOwner = NULL, LeaseUntilUtc = NULL,
            LastError = N'event-ledger-acknowledged';
        SET @CurrentCount = @@ROWCOUNT;
    END;

    SET @AcknowledgedCount = @PreviousCount + @CurrentCount;
END;
GO

IF DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole') IS NULL
   OR DATABASE_PRINCIPAL_ID(N'FundingPlatform_GeneralWorkerRole') IS NULL
    THROW 55716, N'Project asset Defender pipeline requires migration 027 roles.', 1;

GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Record
    TO FundingPlatform_GeneralWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Finalize
    TO FundingPlatform_GeneralWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProjectAssetScan_WatchdogTimeout
    TO FundingPlatform_GeneralWorkerRole;

IF EXISTS
(
    SELECT 1
    FROM sys.database_permissions AS permissions
    WHERE permissions.grantee_principal_id IN
          (DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole'),
           DATABASE_PRINCIPAL_ID(N'FundingPlatform_GeneralWorkerRole'))
      AND permissions.class = 1
      AND permissions.major_id IN
          (OBJECT_ID(N'dbo.FundingPlatform_EventIngressTrustPolicies', N'U'),
           OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetDefenderReceipts', N'U'),
           OBJECT_ID(N'dbo.FundingPlatform_ProjectAssets', N'U'),
           OBJECT_ID(N'dbo.FundingPlatform_ProjectAssetScanEvents', N'U'))
      AND permissions.permission_name IN (N'SELECT', N'INSERT', N'UPDATE', N'DELETE')
      AND permissions.state IN (N'G', N'W')
)
    THROW 55717, N'Runtime roles must not have direct Defender pipeline table access.', 1;

IF EXISTS
(
    SELECT 1
    FROM sys.database_permissions AS permissions
    WHERE permissions.grantee_principal_id =
          DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole')
      AND permissions.class = 1
      AND permissions.major_id IN
          (OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Record', N'P'),
           OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetDefenderReceipt_Finalize', N'P'),
           OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetScan_WatchdogTimeout', N'P'))
      AND permissions.permission_name = N'EXECUTE'
      AND permissions.state IN (N'G', N'W')
)
    THROW 55718, N'Project asset Defender worker procedures must not be API callable.', 1;

IF (SELECT COUNT_BIG(1)
    FROM sys.database_permissions
    WHERE grantee_principal_id =
          DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole')) <> 162
   OR (SELECT COUNT_BIG(1)
       FROM sys.database_permissions
       WHERE grantee_principal_id =
             DATABASE_PRINCIPAL_ID(N'FundingPlatform_GeneralWorkerRole')) <> 53
    THROW 55719, N'Runtime role permissions do not match the Defender allowlist.', 1;
GO
