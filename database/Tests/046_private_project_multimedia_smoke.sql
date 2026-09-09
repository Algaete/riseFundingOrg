/* 046: transactional private MP4/TXT trust, receipt, access and identity smoke.
   Synthetic Defender receipts below are SQL fixtures only, never Azure activation evidence. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke046;

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

    DECLARE @Iteration INT = 0;
    WHILE @Iteration < 2
    BEGIN
        DECLARE @Kind TINYINT = CASE WHEN @Iteration = 0 THEN 2 ELSE 1 END;
        DECLARE @Mime NVARCHAR(100) = CASE WHEN @Kind = 2 THEN N'video/mp4' ELSE N'text/plain' END;
        DECLARE @File NVARCHAR(260) = CASE WHEN @Kind = 2 THEN N'evidence.mp4' ELSE N'evidence.txt' END;
        DECLARE @Processing NVARCHAR(100) = CASE WHEN @Kind = 2 THEN N'mp4-copy-v1' ELSE N'utf8-copy-v1' END;
        DECLARE @Maximum BIGINT = CASE WHEN @Kind = 2 THEN 26214400 ELSE 1048576 END;
        DECLARE @AssetPublicId UNIQUEIDENTIFIER = NEWID();
        DECLARE @ObjectName NVARCHAR(1024) = LOWER(CONVERT(NVARCHAR(36), NEWID())) + N'/' + REPLICATE(N'a', 32) + RIGHT(@File, 4);
        DECLARE @Hash BINARY(32) = HASHBYTES('SHA2_256', @ObjectName);
        DECLARE @Event NVARCHAR(200) = N'media-clean-' + CONVERT(NVARCHAR(36), @AssetPublicId);
        INSERT dbo.FundingPlatform_ProjectAssets
            (PublicId, ProjectId, Kind, OriginalFileName, DisplayName, VerifiedMimeType,
             ContentLength, ContentHash, QuarantineBlobContainer, QuarantineBlobObjectName,
             QuarantineBlobETag, QuarantineBlobVersionId,
             StorageStatus, ScanStatus, ScanProvider, ScanStartedAtUtc,
             SortOrder, IsCover, IsDeleted, UploadedByUserId, CreatedAtUtc, UpdatedAtUtc)
        VALUES (@AssetPublicId, @ProjectId, @Kind, @File, N'Private original', @Mime,
             1024, @Hash, N'project-quarantine', @ObjectName, N'"quarantine"', N'qv1',
             1, 0, 1, @NowUtc, @Iteration, 0, 0, @UserId, @NowUtc, @NowUtc);
        DECLARE @AssetId BIGINT = SCOPE_IDENTITY();
        INSERT dbo.FundingPlatform_ProjectAssetUploadIntents
            (ProjectId, Kind, OriginalFileName, DeclaredMimeType, ExpectedContentLength, MaxContentLength,
             IncomingBlobContainer, IncomingBlobObjectName, QuarantineBlobContainer, QuarantineBlobObjectName,
             TrustedBlobContainer, TrustedBlobObjectName, CompletionTokenHash, Status, ExpiresAtUtc,
             FinalizeAttemptCount, CompletedProjectAssetId, CompletedAtUtc, UploadedByUserId, CreatedAtUtc, UpdatedAtUtc)
        VALUES (@ProjectId, @Kind, @File, @Mime, 1024, @Maximum,
             N'project-incoming', @ObjectName, N'project-quarantine', @ObjectName, N'project-trusted', @ObjectName,
             @Hash, 2, DATEADD(MINUTE, 5, @NowUtc), 1, @AssetId, @NowUtc, @UserId, @NowUtc, @NowUtc);

        DELETE @TrustedResult;
        INSERT @TrustedResult EXEC dbo.FundingPlatform_usp_ProjectAsset_GetTrustedContent
            @OrganizationPublicId, @ProjectPublicId, @UserPublicId, @AssetPublicId;
        IF EXISTS (SELECT 1 FROM @TrustedResult WHERE Succeeded = 1 OR TrustedBlobObjectName IS NOT NULL)
            THROW 55960, N'Pending private original was exposed.', 1;

        INSERT dbo.FundingPlatform_ProjectAssetDefenderReceipts
            (TrustPolicyId, WorkloadKind, ProjectAssetId, Provider, ProviderEventId, PayloadHash,
             TopicResourceId, AuthenticatedTenantId, AuthenticatedPrincipalId, ApplicationClientId,
             EventSubscriptionName, StorageAccountResourceId, BlobHost, BlobContainer, BlobObjectName,
             BlobETag, ReportedContentHash, ToStatus, ResultCode, ReceiptStatus, OccurredAtUtc, ReceivedAtUtc, CreatedAtUtc)
        VALUES (@PolicyId, 2, @AssetId, 1, @Event, @Hash, @TopicResourceId, @TenantId, @PrincipalId, @ApplicationId,
             N'project-assets-sanitizer', @StorageResourceId, N'fpassetsdev.blob.core.windows.net',
             N'project-quarantine', @ObjectName, N'"quarantine"', @Hash, 1, N'defender-clean', 0, @OneSecond, @OneSecond, @NowUtc);

        /* Wrong copy version cannot make a video/text trusted. */
        DELETE @ApplyResult;
        INSERT @ApplyResult EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
            @AssetPublicId = @AssetPublicId, @ScanProvider = 1, @ProviderEventId = @Event,
            @PayloadHash = @Hash, @QuarantineBlobETag = N'"quarantine"', @ReportedContentHash = @Hash,
            @ToStatus = 1, @ResultCode = N'defender-clean', @OccurredAtUtc = @OneSecond,
            @ProviderObservedStatus = 1, @ProviderResultCode = N'defender-clean',
            @TrustedBlobContainer = N'project-trusted', @TrustedBlobObjectName = @ObjectName,
            @TrustedBlobETag = N'"trusted"', @TrustedBlobVersionId = N'tv1',
            @TrustedMimeType = @Mime, @TrustedContentLength = 1024, @TrustedContentHash = @Hash,
            @TrustedProcessingVersion = N'pdf-copy-v1';
        IF EXISTS (SELECT 1 FROM @ApplyResult WHERE Succeeded = 1)
            THROW 55961, N'Mismatched private-original processing identity accepted.', 1;

        DELETE @ApplyResult;
        INSERT @ApplyResult EXEC dbo.FundingPlatform_usp_ProjectAsset_ApplyScanResult
            @AssetPublicId = @AssetPublicId, @ScanProvider = 1, @ProviderEventId = @Event,
            @PayloadHash = @Hash, @QuarantineBlobETag = N'"quarantine"', @ReportedContentHash = @Hash,
            @ToStatus = 1, @ResultCode = N'defender-clean', @OccurredAtUtc = @OneSecond,
            @ProviderObservedStatus = 1, @ProviderResultCode = N'defender-clean',
            @TrustedBlobContainer = N'project-trusted', @TrustedBlobObjectName = @ObjectName,
            @TrustedBlobETag = N'"trusted"', @TrustedBlobVersionId = N'tv1',
            @TrustedMimeType = @Mime, @TrustedContentLength = 1024, @TrustedContentHash = @Hash,
            @TrustedProcessingVersion = @Processing;
        IF NOT EXISTS (SELECT 1 FROM @ApplyResult WHERE Succeeded = 1 AND StorageStatus = 2 AND ScanStatus = 1)
            THROW 55962, N'Authenticated exact private copy was not trusted.', 1;
        DELETE @TrustedResult;
        INSERT @TrustedResult EXEC dbo.FundingPlatform_usp_ProjectAsset_GetTrustedContent
            @OrganizationPublicId, @ProjectPublicId, @UserPublicId, @AssetPublicId;
        IF NOT EXISTS (SELECT 1 FROM @TrustedResult WHERE Succeeded = 1 AND Kind = @Kind
            AND TrustedContentHash = @Hash AND TrustedContentLength = 1024
            AND TrustedProcessingVersion = @Processing AND TrustedMimeType = @Mime
            AND TrustedPixelWidth IS NULL AND TrustedPixelHeight IS NULL)
            THROW 55963, N'Private original trusted download contract drifted.', 1;
        DECLARE @Stranger UNIQUEIDENTIFIER = NEWID();
        DELETE @TrustedResult;
        /* Membership denial intentionally throws the same not-found as an absent project.
           Keep the enclosing rollback fixture usable after this expected read failure. */
        SET XACT_ABORT OFF;
        BEGIN TRY
            INSERT @TrustedResult EXEC dbo.FundingPlatform_usp_ProjectAsset_GetTrustedContent
                @OrganizationPublicId, @ProjectPublicId, @Stranger, @AssetPublicId;
            THROW 55964, N'Private original leaked outside membership.', 1;
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER() <> 55604 THROW;
        END CATCH;
        SET XACT_ABORT ON;
        IF XACT_STATE() <> 1 OR EXISTS (SELECT 1 FROM @TrustedResult)
            THROW 55964, N'Membership denial changed the fixture or exposed a result.', 1;
        SET @Iteration += 1;
    END;
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId AND PublicationStatus <> 0)
        THROW 55965, N'Multimedia implicitly published a draft.', 1;
    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke046;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke046;
    THROW;
END CATCH;
