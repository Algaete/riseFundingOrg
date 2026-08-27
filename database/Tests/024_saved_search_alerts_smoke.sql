/* Transactional FASE 10A smoke: saved search, daily scheduling and email ledger. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_SavedSearches', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_AlertSubscriptions', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_NotificationLogs', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_SavedSearch_Create', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_AlertSchedule_Materialize', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_AlertDelivery_Complete', N'P') IS NULL
   OR DATABASE_PRINCIPAL_ID(N'FundingPlatform_AlertWorkerRole') IS NULL
    THROW 54550, N'FASE 10A objects are incomplete.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys
               WHERE name = N'FundingPlatform_FK_SavedSearches_Membership')
   OR NOT EXISTS (SELECT 1 FROM sys.foreign_keys
                  WHERE name = N'FundingPlatform_FK_NotificationLogs_Subscription')
   OR NOT EXISTS (SELECT 1 FROM sys.indexes
                  WHERE name = N'FundingPlatform_UQ_NotificationLogs_Idempotency'
                    AND object_id = OBJECT_ID(N'dbo.FundingPlatform_NotificationLogs'))
    THROW 54551, N'FASE 10A tenant or idempotency guards are missing.', 1;

IF NOT EXISTS
   (SELECT 1 FROM sys.database_permissions
    WHERE grantee_principal_id = DATABASE_PRINCIPAL_ID(N'FundingPlatform_AlertWorkerRole')
      AND major_id = OBJECT_ID(N'dbo.FundingPlatform_usp_AlertDelivery_Claim')
      AND permission_name = N'EXECUTE' AND state IN (N'G', N'W'))
   OR NOT EXISTS
   (SELECT 1 FROM sys.database_permissions
    WHERE grantee_principal_id = DATABASE_PRINCIPAL_ID(N'FundingPlatform_AlertWorkerRole')
      AND major_id = OBJECT_ID(N'dbo.FundingPlatform_NotificationLogs')
      AND permission_name = N'SELECT' AND state = N'D')
    THROW 54552, N'The alert worker is not constrained to stored procedures.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke024;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @Suffix NVARCHAR(32) = REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'');
    DECLARE @BaseUtc DATETIME2(3) = DATEADD(DAY, -3, SYSUTCDATETIME());
    DECLARE @PublishedUtc DATETIME2(3) = DATEADD(DAY, 1, @BaseUtc);
    DECLARE @ScheduledUtc DATETIME2(3) = DATEADD(DAY, 1, @BaseUtc);
    DECLARE @RunUtc DATETIME2(3) = DATEADD(DAY, 2, @ScheduledUtc);
    DECLARE @NextRunUtc DATETIME2(3) = DATEADD(DAY, 1, @RunUtc);
    DECLARE @UserAPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @UserBPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @OrgAPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @OrgBPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @FunderPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @OpportunityPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @UserAEmail NVARCHAR(320) = N'fase10a-a-' + @Suffix + N'@example.invalid';
    DECLARE @UserBEmail NVARCHAR(320) = N'fase10a-b-' + @Suffix + N'@example.invalid';
    DECLARE @Sponsor NVARCHAR(300) = N'FASE 10A Sponsor ' + @Suffix;

    INSERT dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash,
         SecurityStamp, EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@UserAPublicId, @UserAEmail, UPPER(@UserAEmail), N'FASE 10A A',
         N'not-a-credential', N'fase10a-a', 1, 0, 2, N'es-CL'),
        (@UserBPublicId, @UserBEmail, UPPER(@UserBEmail), N'FASE 10A B',
         N'not-a-credential', N'fase10a-b', 1, 0, 2, N'es-CL');
    DECLARE @UserAId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @UserAPublicId);
    DECLARE @UserBId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @UserBPublicId);
    INSERT dbo.FundingPlatform_Organizations
        (PublicId, CreatedByUserId, Name, HomeCountryId, OrganizationTypeId)
    VALUES
        (@OrgAPublicId, @UserAId, N'FASE 10A Org A ' + @Suffix, 152, 1),
        (@OrgBPublicId, @UserBId, N'FASE 10A Org B ' + @Suffix, 152, 2);
    DECLARE @OrgAId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Organizations WHERE PublicId = @OrgAPublicId);
    DECLARE @OrgBId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Organizations WHERE PublicId = @OrgBPublicId);
    INSERT dbo.FundingPlatform_OrganizationUsers
        (OrganizationId, UserId, Role, MembershipStatus, JoinedAtUtc)
    VALUES (@OrgAId, @UserAId, 1, 1, @BaseUtc),
           (@OrgBId, @UserBId, 1, 1, @BaseUtc);

    INSERT dbo.FundingPlatform_Funders
        (PublicId, Slug, Name, NormalizedName, WebsiteUrl, PublicationStatus,
         SubmittedAtUtc, PublishedAtUtc, ReviewedAtUtc, ContentVersion,
         IsActive, CreatedAtUtc, UpdatedAtUtc)
    VALUES (@FunderPublicId, N'fase10a-funder-' + @Suffix, @Sponsor, UPPER(@Sponsor),
            N'https://fase10a-funder.example.invalid', 2, @BaseUtc, @BaseUtc,
            @BaseUtc, 1, 1, @BaseUtc, @BaseUtc);
    DECLARE @FunderId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Funders WHERE PublicId = @FunderPublicId);
    DECLARE @SourceId INT =
        (SELECT Id FROM dbo.FundingPlatform_FundingSources
         WHERE Name = N'Manual editorial' AND IsEnabled = 1);
    IF @SourceId IS NULL THROW 54553, N'Manual source fixture is missing.', 1;

    INSERT dbo.FundingPlatform_FundingOpportunities
        (PublicId, Slug, Title, Description, Summary, SponsorName,
         IssuerCountryId, FundingTypeId, Currency, MinAmount, MaxAmount, AmountStatus,
         OpenDate, CloseDate, DeadlineType, DeadlinePrecision,
         EligibilityDescription, Requirements, GeographicScope, RemoteApplication,
         PublicationStatus, PublishedAtUtc, LastVerifiedAtUtc, DataQualityScore,
         ContentVersion, IsActive, ReviewedAtUtc, CreatedAtUtc, UpdatedAtUtc)
    VALUES (@OpportunityPublicId, N'fase10a-opportunity-' + @Suffix,
            N'Agua comunitaria ' + @Suffix, N'Descripción', N'Resumen', @Sponsor,
            152, 1, 'USD', 100, 200, 1, CONVERT(DATE, @BaseUtc),
            DATEADD(DAY, 30, CONVERT(DATE, @RunUtc)), 1, 1,
            N'Condiciones publicadas', N'Requisitos', 1, 1, 2, @PublishedUtc,
            @PublishedUtc, 95, 1, 1, @PublishedUtc, @BaseUtc, @PublishedUtc);
    DECLARE @OpportunityId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_FundingOpportunities
         WHERE PublicId = @OpportunityPublicId);
    INSERT dbo.FundingPlatform_FundingOpportunityCountries
        (FundingOpportunityId, CountryId)
    VALUES (@OpportunityId, 152);
    INSERT dbo.FundingPlatform_FundingOpportunityCategories
        (FundingOpportunityId, FundingCategoryId)
    VALUES (@OpportunityId, 1);
    INSERT dbo.FundingPlatform_FundingOpportunityFunders
        (FundingOpportunityId, FunderId, Role, IsActive, CreatedAtUtc, UpdatedAtUtc)
    VALUES (@OpportunityId, @FunderId, 1, 1, @BaseUtc, @BaseUtc);
    INSERT dbo.FundingPlatform_FundingOpportunitySourceLinks
        (FundingOpportunityId, FundingSourceId, ExternalId, SourceItemKeyHash,
         SourceUrl, CanonicalUrlHash, FirstSeenAtUtc, LastSeenAtUtc, IsPrimary, IsActive)
    VALUES (@OpportunityId, @SourceId, N'fase10a-' + @Suffix,
            HASHBYTES('SHA2_256', N'fase10a-key-' + @Suffix),
            N'https://fase10a-source.example.invalid/' + @Suffix,
            HASHBYTES('SHA2_256', N'fase10a-url-' + @Suffix),
            @BaseUtc, @PublishedUtc, 1, 1);
    INSERT dbo.FundingPlatform_FundingFieldEvidence
        (FundingOpportunityId, FieldPath, ValueJson, ExtractionMethod,
         IsSelected, IsManualLock, CreatedAtUtc)
    SELECT @OpportunityId, FieldPath, N'{"status":"known","value":"fase10a"}',
           1, 1, 0, @BaseUtc
    FROM (VALUES (N'/title'), (N'/description'),
                 (N'/eligibilityDescription'), (N'/closeDate')) AS required(FieldPath);
    IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_ifn_FundingOpportunityPublicReady()
                   WHERE FundingOpportunityId = @OpportunityId)
        THROW 54554, N'Published fixture is not PublicReady.', 1;

    DECLARE @CountryIds dbo.FundingPlatform_SmallIntIdList;
    DECLARE @RegionIds dbo.FundingPlatform_IntIdList;
    DECLARE @CategoryIds dbo.FundingPlatform_IntIdList;
    DECLARE @TagIds dbo.FundingPlatform_BigIntIdList;
    DECLARE @BeneficiaryIds dbo.FundingPlatform_IntIdList;
    DECLARE @ProjectTypeIds dbo.FundingPlatform_IntIdList;
    DECLARE @FundingTypeIds dbo.FundingPlatform_SmallIntIdList;
    DECLARE @OrganizationTypeIds dbo.FundingPlatform_SmallIntIdList;
    DECLARE @FunderIds dbo.FundingPlatform_GuidIdList;
    INSERT @CountryIds VALUES (152);
    INSERT @CategoryIds VALUES (1);
    INSERT @FundingTypeIds VALUES (1);
    INSERT @FunderIds VALUES (@FunderPublicId);
    DECLARE @IdempotencyHash BINARY(32) = HASHBYTES('SHA2_256', N'fase10a-idem-' + @Suffix);
    DECLARE @RequestHash BINARY(32) = HASHBYTES('SHA2_256', N'fase10a-request-' + @Suffix);
    DECLARE @SearchName NVARCHAR(150) = N'Agua ' + @Suffix;
    DECLARE @CreateResult TABLE (Code NVARCHAR(30), SavedSearchPublicId UNIQUEIDENTIFIER);
    INSERT @CreateResult
    EXEC dbo.FundingPlatform_usp_SavedSearch_Create
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @Name = @SearchName, @QueryText = N'Agua', @SponsorText = @Sponsor,
        @Currency = 'USD', @OnlyOpen = 1, @SortCode = 1,
        @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @TagIds = @TagIds,
        @BeneficiaryTypeIds = @BeneficiaryIds, @ProjectTypeIds = @ProjectTypeIds,
        @FundingTypeIds = @FundingTypeIds, @OrganizationTypeIds = @OrganizationTypeIds,
        @FunderPublicIds = @FunderIds, @IdempotencyKeyHash = @IdempotencyHash,
        @RequestHash = @RequestHash, @NowUtc = @BaseUtc;
    DECLARE @SavedSearchPublicId UNIQUEIDENTIFIER =
        (SELECT SavedSearchPublicId FROM @CreateResult WHERE Code = N'created');
    IF @SavedSearchPublicId IS NULL THROW 54555, N'Saved search was not created.', 1;
    DELETE FROM @CreateResult;
    INSERT @CreateResult
    EXEC dbo.FundingPlatform_usp_SavedSearch_Create
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @Name = @SearchName, @QueryText = N'Agua', @SponsorText = @Sponsor,
        @Currency = 'USD', @OnlyOpen = 1, @SortCode = 1,
        @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @TagIds = @TagIds,
        @BeneficiaryTypeIds = @BeneficiaryIds, @ProjectTypeIds = @ProjectTypeIds,
        @FundingTypeIds = @FundingTypeIds, @OrganizationTypeIds = @OrganizationTypeIds,
        @FunderPublicIds = @FunderIds, @IdempotencyKeyHash = @IdempotencyHash,
        @RequestHash = @RequestHash, @NowUtc = @BaseUtc;
    IF NOT EXISTS (SELECT 1 FROM @CreateResult WHERE Code = N'replayed'
                    AND SavedSearchPublicId = @SavedSearchPublicId)
        THROW 54556, N'Saved-search idempotent replay failed.', 1;

    EXEC dbo.FundingPlatform_usp_SavedSearch_List
        @UserAPublicId, @OrgAPublicId, 1, 20;
    EXEC dbo.FundingPlatform_usp_SavedSearch_Get
        @UserAPublicId, @OrgAPublicId, @SavedSearchPublicId;
    SET XACT_ABORT OFF;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_SavedSearch_Get
            @UserBPublicId, @OrgBPublicId, @SavedSearchPublicId;
        THROW 54557, N'Cross-tenant saved search was exposed.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> 54503 THROW;
    END CATCH;
    SET XACT_ABORT ON;

    EXEC dbo.FundingPlatform_usp_AlertSubscription_Put
        @UserPublicId = @UserAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @SavedSearchPublicId = @SavedSearchPublicId, @PreferredHourLocal = 8,
        @TimeZoneId = N'America/Santiago', @NextRunAtUtc = @ScheduledUtc,
        @NowUtc = @BaseUtc;
    DECLARE @AlertId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_AlertSubscriptions
         WHERE SavedSearchId = (SELECT Id FROM dbo.FundingPlatform_SavedSearches
                                WHERE PublicId = @SavedSearchPublicId));
    DECLARE @AlertPublicId UNIQUEIDENTIFIER =
        (SELECT PublicId FROM dbo.FundingPlatform_AlertSubscriptions WHERE Id = @AlertId);
    DECLARE @AlertNonce UNIQUEIDENTIFIER =
        (SELECT UnsubscribeNonce FROM dbo.FundingPlatform_AlertSubscriptions WHERE Id = @AlertId);
    DECLARE @WorkerId UNIQUEIDENTIFIER = NEWID();
    EXEC dbo.FundingPlatform_usp_AlertSchedule_Claim
        @LeaseOwner = @WorkerId, @BatchSize = 5, @LeaseSeconds = 120, @NowUtc = @RunUtc;
    DECLARE @ScheduleLeaseId UNIQUEIDENTIFIER =
        (SELECT LeaseId FROM dbo.FundingPlatform_AlertSubscriptions WHERE Id = @AlertId);
    IF @ScheduleLeaseId IS NULL THROW 54558, N'Due alert was not claimed.', 1;
    IF (SELECT NextRunAtUtc FROM dbo.FundingPlatform_AlertSubscriptions WHERE Id = @AlertId) <> @RunUtc
        THROW 54565, N'Stale alert schedule was not collapsed into one catch-up digest.', 1;
    SET @ScheduledUtc = @RunUtc;
    EXEC dbo.FundingPlatform_usp_AlertSchedule_Materialize
        @AlertSubscriptionPublicId = @AlertPublicId, @LeaseId = @ScheduleLeaseId,
        @ScheduledForUtc = @ScheduledUtc, @NextRunAtUtc = @NextRunUtc, @NowUtc = @RunUtc;
    DECLARE @LogId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_NotificationLogs
         WHERE AlertSubscriptionId = @AlertId AND ScheduledForUtc = @ScheduledUtc);
    DECLARE @LogPublicId UNIQUEIDENTIFIER =
        (SELECT PublicId FROM dbo.FundingPlatform_NotificationLogs WHERE Id = @LogId);
    IF @LogId IS NULL OR
       (SELECT ItemCount FROM dbo.FundingPlatform_NotificationLogs WHERE Id = @LogId) <> 1 OR
       NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_NotificationLogItems
                   WHERE NotificationLogId = @LogId AND FundingOpportunityId = @OpportunityId)
        THROW 54559, N'Alert digest was not materialized exactly once.', 1;

    EXEC dbo.FundingPlatform_usp_AlertDelivery_Claim
        @LeaseOwner = @WorkerId, @LeaseSeconds = 180, @MaximumAttempts = 3, @NowUtc = @RunUtc;
    DECLARE @DeliveryLeaseId UNIQUEIDENTIFIER =
        (SELECT LeaseId FROM dbo.FundingPlatform_NotificationLogs WHERE Id = @LogId);
    DECLARE @RenewNow DATETIME2(3) = DATEADD(SECOND, 1, @RunUtc);
    DECLARE @FailNow DATETIME2(3) = DATEADD(SECOND, 2, @RunUtc);
    DECLARE @RetryNow DATETIME2(3) = DATEADD(SECOND, 40, @RunUtc);
    DECLARE @CompleteNow DATETIME2(3) = DATEADD(SECOND, 41, @RunUtc);
    DECLARE @UnsubscribeNow DATETIME2(3) = DATEADD(MINUTE, 5, @RunUtc);
    DECLARE @ProviderMessageId NVARCHAR(200) = N'fase10a-provider-' + @Suffix;
    IF @DeliveryLeaseId IS NULL THROW 54560, N'Digest delivery was not claimed.', 1;
    EXEC dbo.FundingPlatform_usp_AlertDelivery_RenewLease
        @NotificationLogPublicId = @LogPublicId, @LeaseId = @DeliveryLeaseId,
        @LeaseSeconds = 180, @NowUtc = @RenewNow;
    EXEC dbo.FundingPlatform_usp_AlertDelivery_Fail
        @NotificationLogPublicId = @LogPublicId, @LeaseId = @DeliveryLeaseId,
        @DeliveryUnknown = 0, @ErrorCode = N'provider-rejected',
        @RetryDelaySeconds = 30, @MaximumAttempts = 3,
        @NowUtc = @FailNow;
    IF (SELECT Status FROM dbo.FundingPlatform_NotificationLogs WHERE Id = @LogId) <> 3
        THROW 54561, N'Confirmed pre-send failure was not scheduled for retry.', 1;
    EXEC dbo.FundingPlatform_usp_AlertDelivery_Claim
        @LeaseOwner = @WorkerId, @LeaseSeconds = 180, @MaximumAttempts = 3,
        @NowUtc = @RetryNow;
    SET @DeliveryLeaseId =
        (SELECT LeaseId FROM dbo.FundingPlatform_NotificationLogs WHERE Id = @LogId);
    EXEC dbo.FundingPlatform_usp_AlertDelivery_Complete
        @NotificationLogPublicId = @LogPublicId, @LeaseId = @DeliveryLeaseId,
        @ProviderMessageId = @ProviderMessageId,
        @NowUtc = @CompleteNow;
    IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_NotificationLogs
                   WHERE Id = @LogId AND Status = 2 AND AttemptCount = 2
                     AND ProviderMessageId = @ProviderMessageId)
        THROW 54562, N'Digest delivery did not complete with its provider receipt.', 1;
    EXEC dbo.FundingPlatform_usp_NotificationLog_List
        @UserAPublicId, @OrgAPublicId, 1, 20;
    EXEC dbo.FundingPlatform_usp_AlertSubscription_Unsubscribe
        @AlertSubscriptionPublicId = @AlertPublicId,
        @UnsubscribeNonce = @AlertNonce, @NowUtc = @UnsubscribeNow;
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_AlertSubscriptions
               WHERE Id = @AlertId AND IsActive = 1)
        THROW 54563, N'One-purpose unsubscribe did not disable the alert.', 1;
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_NotificationLogs
               WHERE Id = @LogId AND (TemplateCode LIKE N'%@%' OR ErrorCode LIKE N'%@%'))
        THROW 54564, N'Notification ledger contains an email address.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK;
    ELSE ROLLBACK TRANSACTION FP_Smoke024;
    PRINT N'FASE 10A saved-search alert smoke passed.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
    BEGIN
        IF @InitialTransactionCount = 0 ROLLBACK;
        ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke024;
        ELSE ROLLBACK;
    END;
    THROW;
END CATCH;
