/* FundingPlatform FASE 10A - tenant-private saved searches and idempotent daily alerts.
   Requires 018. Delivery payload is materialized server-side; no email body or unsubscribe
   bearer token is persisted. The alert worker receives current recipient data only via SP. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_ifn_FundingOpportunityPublicReady', N'IF') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch', N'P') IS NULL
    THROW 54501, N'FASE 10A requires migration 018.', 1;

CREATE TABLE dbo.FundingPlatform_SavedSearches
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_SavedSearches_PublicId DEFAULT (NEWSEQUENTIALID()),
    OrganizationId BIGINT NOT NULL,
    UserId BIGINT NOT NULL,
    Name NVARCHAR(150) NOT NULL,
    QueryText NVARCHAR(300) NULL,
    SponsorText NVARCHAR(300) NULL,
    MinAmount DECIMAL(19,4) NULL,
    MaxAmount DECIMAL(19,4) NULL,
    Currency CHAR(3) NULL,
    ClosingFrom DATE NULL,
    ClosingTo DATE NULL,
    OnlyOpen BIT NOT NULL,
    SortCode TINYINT NOT NULL,
    DeletedAtUtc DATETIME2(3) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_SavedSearches PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SavedSearches_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_SavedSearches_IdTenantUser
        UNIQUE (Id, OrganizationId, UserId),
    CONSTRAINT FundingPlatform_UQ_SavedSearches_PublicTenantUser
        UNIQUE (PublicId, OrganizationId, UserId),
    CONSTRAINT FundingPlatform_FK_SavedSearches_Membership
        FOREIGN KEY (OrganizationId, UserId)
        REFERENCES dbo.FundingPlatform_OrganizationUsers (OrganizationId, UserId),
    CONSTRAINT FundingPlatform_FK_SavedSearches_Currency FOREIGN KEY (Currency)
        REFERENCES dbo.FundingPlatform_Currencies (Code),
    CONSTRAINT FundingPlatform_CK_SavedSearches_Name CHECK
        (LEN(LTRIM(RTRIM(Name))) BETWEEN 1 AND 150
         AND DATALENGTH(Name) = DATALENGTH(LTRIM(RTRIM(Name)))),
    CONSTRAINT FundingPlatform_CK_SavedSearches_Query CHECK
        ((QueryText IS NULL OR
          (LEN(LTRIM(RTRIM(QueryText))) BETWEEN 1 AND 300
           AND DATALENGTH(QueryText) = DATALENGTH(LTRIM(RTRIM(QueryText)))))
         AND (SponsorText IS NULL OR
          (LEN(LTRIM(RTRIM(SponsorText))) BETWEEN 1 AND 300
           AND DATALENGTH(SponsorText) = DATALENGTH(LTRIM(RTRIM(SponsorText)))))),
    CONSTRAINT FundingPlatform_CK_SavedSearches_Amounts CHECK
        ((MinAmount IS NULL OR MinAmount >= 0)
         AND (MaxAmount IS NULL OR MaxAmount >= 0)
         AND (MinAmount IS NULL OR MaxAmount IS NULL OR MinAmount <= MaxAmount)
         AND ((MinAmount IS NULL AND MaxAmount IS NULL) OR Currency IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_SavedSearches_Dates CHECK
        (ClosingFrom IS NULL OR ClosingTo IS NULL OR ClosingFrom <= ClosingTo),
    CONSTRAINT FundingPlatform_CK_SavedSearches_Sort CHECK
        (SortCode BETWEEN 1 AND 5 AND (SortCode <> 1 OR QueryText IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_SavedSearches_Timestamps CHECK
        (CreatedAtUtc <= UpdatedAtUtc AND
         (DeletedAtUtc IS NULL OR DeletedAtUtc >= CreatedAtUtc))
);

CREATE INDEX FundingPlatform_IX_SavedSearches_UserActiveUpdated
    ON dbo.FundingPlatform_SavedSearches
        (OrganizationId, UserId, UpdatedAtUtc DESC, Id DESC)
    INCLUDE (PublicId, Name, QueryText, OnlyOpen, SortCode, CreatedAtUtc)
    WHERE DeletedAtUtc IS NULL;

CREATE TABLE dbo.FundingPlatform_SavedSearchCreateRequests
(
    OrganizationId BIGINT NOT NULL,
    UserId BIGINT NOT NULL,
    IdempotencyKeyHash BINARY(32) NOT NULL,
    RequestHash BINARY(32) NOT NULL,
    SavedSearchId BIGINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_SavedSearchCreateRequests
        PRIMARY KEY (OrganizationId, UserId, IdempotencyKeyHash),
    CONSTRAINT FundingPlatform_FK_SavedSearchCreateRequests_Search
        FOREIGN KEY (SavedSearchId, OrganizationId, UserId)
        REFERENCES dbo.FundingPlatform_SavedSearches (Id, OrganizationId, UserId)
);

CREATE TABLE dbo.FundingPlatform_SavedSearchCountries
(
    SavedSearchId BIGINT NOT NULL,
    CountryId SMALLINT NOT NULL,
    CONSTRAINT FundingPlatform_PK_SavedSearchCountries PRIMARY KEY (SavedSearchId, CountryId),
    CONSTRAINT FundingPlatform_FK_SavedSearchCountries_Search FOREIGN KEY (SavedSearchId)
        REFERENCES dbo.FundingPlatform_SavedSearches (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_SavedSearchCountries_Country FOREIGN KEY (CountryId)
        REFERENCES dbo.FundingPlatform_Countries (Id)
);
CREATE TABLE dbo.FundingPlatform_SavedSearchRegions
(
    SavedSearchId BIGINT NOT NULL,
    RegionId INT NOT NULL,
    CONSTRAINT FundingPlatform_PK_SavedSearchRegions PRIMARY KEY (SavedSearchId, RegionId),
    CONSTRAINT FundingPlatform_FK_SavedSearchRegions_Search FOREIGN KEY (SavedSearchId)
        REFERENCES dbo.FundingPlatform_SavedSearches (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_SavedSearchRegions_Region FOREIGN KEY (RegionId)
        REFERENCES dbo.FundingPlatform_Regions (Id)
);
CREATE TABLE dbo.FundingPlatform_SavedSearchCategories
(
    SavedSearchId BIGINT NOT NULL,
    FundingCategoryId INT NOT NULL,
    CONSTRAINT FundingPlatform_PK_SavedSearchCategories
        PRIMARY KEY (SavedSearchId, FundingCategoryId),
    CONSTRAINT FundingPlatform_FK_SavedSearchCategories_Search FOREIGN KEY (SavedSearchId)
        REFERENCES dbo.FundingPlatform_SavedSearches (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_SavedSearchCategories_Category FOREIGN KEY (FundingCategoryId)
        REFERENCES dbo.FundingPlatform_FundingCategories (Id)
);
CREATE TABLE dbo.FundingPlatform_SavedSearchTags
(
    SavedSearchId BIGINT NOT NULL,
    TagId BIGINT NOT NULL,
    CONSTRAINT FundingPlatform_PK_SavedSearchTags PRIMARY KEY (SavedSearchId, TagId),
    CONSTRAINT FundingPlatform_FK_SavedSearchTags_Search FOREIGN KEY (SavedSearchId)
        REFERENCES dbo.FundingPlatform_SavedSearches (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_SavedSearchTags_Tag FOREIGN KEY (TagId)
        REFERENCES dbo.FundingPlatform_Tags (Id)
);
CREATE TABLE dbo.FundingPlatform_SavedSearchBeneficiaryTypes
(
    SavedSearchId BIGINT NOT NULL,
    BeneficiaryTypeId INT NOT NULL,
    CONSTRAINT FundingPlatform_PK_SavedSearchBeneficiaryTypes
        PRIMARY KEY (SavedSearchId, BeneficiaryTypeId),
    CONSTRAINT FundingPlatform_FK_SavedSearchBeneficiaryTypes_Search FOREIGN KEY (SavedSearchId)
        REFERENCES dbo.FundingPlatform_SavedSearches (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_SavedSearchBeneficiaryTypes_Type FOREIGN KEY (BeneficiaryTypeId)
        REFERENCES dbo.FundingPlatform_BeneficiaryTypes (Id)
);
CREATE TABLE dbo.FundingPlatform_SavedSearchProjectTypes
(
    SavedSearchId BIGINT NOT NULL,
    ProjectTypeId INT NOT NULL,
    CONSTRAINT FundingPlatform_PK_SavedSearchProjectTypes
        PRIMARY KEY (SavedSearchId, ProjectTypeId),
    CONSTRAINT FundingPlatform_FK_SavedSearchProjectTypes_Search FOREIGN KEY (SavedSearchId)
        REFERENCES dbo.FundingPlatform_SavedSearches (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_SavedSearchProjectTypes_Type FOREIGN KEY (ProjectTypeId)
        REFERENCES dbo.FundingPlatform_ProjectTypes (Id)
);
CREATE TABLE dbo.FundingPlatform_SavedSearchFundingTypes
(
    SavedSearchId BIGINT NOT NULL,
    FundingTypeId SMALLINT NOT NULL,
    CONSTRAINT FundingPlatform_PK_SavedSearchFundingTypes
        PRIMARY KEY (SavedSearchId, FundingTypeId),
    CONSTRAINT FundingPlatform_FK_SavedSearchFundingTypes_Search FOREIGN KEY (SavedSearchId)
        REFERENCES dbo.FundingPlatform_SavedSearches (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_SavedSearchFundingTypes_Type FOREIGN KEY (FundingTypeId)
        REFERENCES dbo.FundingPlatform_FundingTypes (Id)
);
CREATE TABLE dbo.FundingPlatform_SavedSearchOrganizationTypes
(
    SavedSearchId BIGINT NOT NULL,
    OrganizationTypeId SMALLINT NOT NULL,
    CONSTRAINT FundingPlatform_PK_SavedSearchOrganizationTypes
        PRIMARY KEY (SavedSearchId, OrganizationTypeId),
    CONSTRAINT FundingPlatform_FK_SavedSearchOrganizationTypes_Search FOREIGN KEY (SavedSearchId)
        REFERENCES dbo.FundingPlatform_SavedSearches (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_SavedSearchOrganizationTypes_Type FOREIGN KEY (OrganizationTypeId)
        REFERENCES dbo.FundingPlatform_OrganizationTypes (Id)
);
CREATE TABLE dbo.FundingPlatform_SavedSearchFunders
(
    SavedSearchId BIGINT NOT NULL,
    FunderId BIGINT NOT NULL,
    CONSTRAINT FundingPlatform_PK_SavedSearchFunders PRIMARY KEY (SavedSearchId, FunderId),
    CONSTRAINT FundingPlatform_FK_SavedSearchFunders_Search FOREIGN KEY (SavedSearchId)
        REFERENCES dbo.FundingPlatform_SavedSearches (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_SavedSearchFunders_Funder FOREIGN KEY (FunderId)
        REFERENCES dbo.FundingPlatform_Funders (Id)
);

CREATE TABLE dbo.FundingPlatform_AlertSubscriptions
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_AlertSubscriptions_PublicId DEFAULT (NEWSEQUENTIALID()),
    SavedSearchId BIGINT NOT NULL,
    OrganizationId BIGINT NOT NULL,
    UserId BIGINT NOT NULL,
    Channel TINYINT NOT NULL,
    Frequency TINYINT NOT NULL,
    PreferredHourLocal TINYINT NOT NULL,
    TimeZoneId NVARCHAR(100) NOT NULL,
    NextRunAtUtc DATETIME2(3) NOT NULL,
    LastRunAtUtc DATETIME2(3) NULL,
    IsActive BIT NOT NULL,
    DisabledReasonCode NVARCHAR(100) NULL,
    DisabledAtUtc DATETIME2(3) NULL,
    UnsubscribeNonce UNIQUEIDENTIFIER NOT NULL,
    LeaseOwner UNIQUEIDENTIFIER NULL,
    LeaseId UNIQUEIDENTIFIER NULL,
    LeaseUntilUtc DATETIME2(3) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_AlertSubscriptions PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_AlertSubscriptions_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_AlertSubscriptions_SearchChannel UNIQUE (SavedSearchId, Channel),
    CONSTRAINT FundingPlatform_UQ_AlertSubscriptions_IdTenantUser
        UNIQUE (Id, OrganizationId, UserId),
    CONSTRAINT FundingPlatform_FK_AlertSubscriptions_Search
        FOREIGN KEY (SavedSearchId, OrganizationId, UserId)
        REFERENCES dbo.FundingPlatform_SavedSearches (Id, OrganizationId, UserId),
    CONSTRAINT FundingPlatform_CK_AlertSubscriptions_Contract CHECK
        (Channel = 0 AND Frequency = 0 AND PreferredHourLocal BETWEEN 0 AND 23
         AND LEN(LTRIM(RTRIM(TimeZoneId))) BETWEEN 1 AND 100
         AND DATALENGTH(TimeZoneId) = DATALENGTH(LTRIM(RTRIM(TimeZoneId)))
         AND CreatedAtUtc <= UpdatedAtUtc
         AND (LastRunAtUtc IS NULL OR LastRunAtUtc >= CreatedAtUtc)),
    CONSTRAINT FundingPlatform_CK_AlertSubscriptions_State CHECK
        ((IsActive = 1 AND DisabledReasonCode IS NULL AND DisabledAtUtc IS NULL)
         OR (IsActive = 0 AND DisabledReasonCode IS NOT NULL AND DisabledAtUtc IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_AlertSubscriptions_Lease CHECK
        ((LeaseOwner IS NULL AND LeaseId IS NULL AND LeaseUntilUtc IS NULL)
         OR (LeaseOwner IS NOT NULL AND LeaseId IS NOT NULL AND LeaseUntilUtc IS NOT NULL))
);

CREATE INDEX FundingPlatform_IX_AlertSubscriptions_Due
    ON dbo.FundingPlatform_AlertSubscriptions (NextRunAtUtc, Id)
    INCLUDE (PublicId, PreferredHourLocal, TimeZoneId)
    WHERE IsActive = 1;

CREATE TABLE dbo.FundingPlatform_NotificationLogs
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_NotificationLogs_PublicId DEFAULT (NEWSEQUENTIALID()),
    AlertSubscriptionId BIGINT NOT NULL,
    OrganizationId BIGINT NOT NULL,
    UserId BIGINT NOT NULL,
    ScheduledForUtc DATETIME2(3) NOT NULL,
    Channel TINYINT NOT NULL,
    TemplateCode NVARCHAR(100) NOT NULL,
    Locale NVARCHAR(10) NOT NULL,
    IdempotencyKey BINARY(32) NOT NULL,
    Status TINYINT NOT NULL,
    AttemptCount SMALLINT NOT NULL,
    AvailableAtUtc DATETIME2(3) NOT NULL,
    LeaseOwner UNIQUEIDENTIFIER NULL,
    LeaseId UNIQUEIDENTIFIER NULL,
    LeaseUntilUtc DATETIME2(3) NULL,
    ProviderMessageId NVARCHAR(200) NULL,
    SentAtUtc DATETIME2(3) NULL,
    ErrorCode NVARCHAR(100) NULL,
    ItemCount SMALLINT NOT NULL,
    WasTruncated BIT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_NotificationLogs PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_NotificationLogs_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_NotificationLogs_Idempotency UNIQUE (IdempotencyKey),
    CONSTRAINT FundingPlatform_UQ_NotificationLogs_SubscriptionSchedule
        UNIQUE (AlertSubscriptionId, ScheduledForUtc),
    CONSTRAINT FundingPlatform_UQ_NotificationLogs_IdTenantUser
        UNIQUE (Id, OrganizationId, UserId),
    CONSTRAINT FundingPlatform_FK_NotificationLogs_Subscription
        FOREIGN KEY (AlertSubscriptionId, OrganizationId, UserId)
        REFERENCES dbo.FundingPlatform_AlertSubscriptions (Id, OrganizationId, UserId),
    CONSTRAINT FundingPlatform_CK_NotificationLogs_Contract CHECK
        (Channel = 0 AND TemplateCode = N'daily-funding-digest-v1'
         AND LEN(Locale) BETWEEN 2 AND 10 AND Status BETWEEN 0 AND 6
         AND AttemptCount BETWEEN 0 AND 5 AND ItemCount BETWEEN 0 AND 50
         AND CreatedAtUtc <= UpdatedAtUtc),
    CONSTRAINT FundingPlatform_CK_NotificationLogs_Lease CHECK
        ((Status = 1 AND LeaseOwner IS NOT NULL AND LeaseId IS NOT NULL AND LeaseUntilUtc IS NOT NULL)
         OR (Status <> 1 AND LeaseOwner IS NULL AND LeaseId IS NULL AND LeaseUntilUtc IS NULL)),
    CONSTRAINT FundingPlatform_CK_NotificationLogs_Sent CHECK
        ((Status = 2 AND ProviderMessageId IS NOT NULL AND SentAtUtc IS NOT NULL AND ErrorCode IS NULL)
         OR (Status <> 2 AND SentAtUtc IS NULL))
);

CREATE INDEX FundingPlatform_IX_NotificationLogs_Delivery
    ON dbo.FundingPlatform_NotificationLogs (Status, AvailableAtUtc, Id)
    INCLUDE (PublicId, AttemptCount);
CREATE INDEX FundingPlatform_IX_NotificationLogs_UserCreated
    ON dbo.FundingPlatform_NotificationLogs (OrganizationId, UserId, CreatedAtUtc DESC, Id DESC)
    INCLUDE (PublicId, AlertSubscriptionId, Status, ItemCount, WasTruncated,
             ScheduledForUtc, SentAtUtc, ErrorCode);

CREATE TABLE dbo.FundingPlatform_NotificationLogItems
(
    NotificationLogId BIGINT NOT NULL,
    FundingOpportunityId BIGINT NOT NULL,
    PublishedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_NotificationLogItems
        PRIMARY KEY (NotificationLogId, FundingOpportunityId),
    CONSTRAINT FundingPlatform_FK_NotificationLogItems_Log FOREIGN KEY (NotificationLogId)
        REFERENCES dbo.FundingPlatform_NotificationLogs (Id),
    CONSTRAINT FundingPlatform_FK_NotificationLogItems_Opportunity FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id)
);
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SavedSearch_ReplaceFilters
    @SavedSearchId BIGINT,
    @CountryIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @RegionIds dbo.FundingPlatform_IntIdList READONLY,
    @CategoryIds dbo.FundingPlatform_IntIdList READONLY,
    @TagIds dbo.FundingPlatform_BigIntIdList READONLY,
    @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @FundingTypeIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @OrganizationTypeIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @FunderPublicIds dbo.FundingPlatform_GuidIdList READONLY
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    IF @SavedSearchId IS NULL OR
       (SELECT COUNT_BIG(*) FROM @CountryIds) > 50 OR
       (SELECT COUNT_BIG(*) FROM @RegionIds) > 50 OR
       (SELECT COUNT_BIG(*) FROM @CategoryIds) > 50 OR
       (SELECT COUNT_BIG(*) FROM @TagIds) > 50 OR
       (SELECT COUNT_BIG(*) FROM @BeneficiaryTypeIds) > 50 OR
       (SELECT COUNT_BIG(*) FROM @ProjectTypeIds) > 50 OR
       (SELECT COUNT_BIG(*) FROM @FundingTypeIds) > 50 OR
       (SELECT COUNT_BIG(*) FROM @OrganizationTypeIds) > 50 OR
       (SELECT COUNT_BIG(*) FROM @FunderPublicIds) > 50
        THROW 54502, N'Saved-search filters are invalid.', 1;

    DELETE FROM dbo.FundingPlatform_SavedSearchCountries WHERE SavedSearchId = @SavedSearchId;
    DELETE FROM dbo.FundingPlatform_SavedSearchRegions WHERE SavedSearchId = @SavedSearchId;
    DELETE FROM dbo.FundingPlatform_SavedSearchCategories WHERE SavedSearchId = @SavedSearchId;
    DELETE FROM dbo.FundingPlatform_SavedSearchTags WHERE SavedSearchId = @SavedSearchId;
    DELETE FROM dbo.FundingPlatform_SavedSearchBeneficiaryTypes WHERE SavedSearchId = @SavedSearchId;
    DELETE FROM dbo.FundingPlatform_SavedSearchProjectTypes WHERE SavedSearchId = @SavedSearchId;
    DELETE FROM dbo.FundingPlatform_SavedSearchFundingTypes WHERE SavedSearchId = @SavedSearchId;
    DELETE FROM dbo.FundingPlatform_SavedSearchOrganizationTypes WHERE SavedSearchId = @SavedSearchId;
    DELETE FROM dbo.FundingPlatform_SavedSearchFunders WHERE SavedSearchId = @SavedSearchId;

    INSERT dbo.FundingPlatform_SavedSearchCountries SELECT @SavedSearchId, Id FROM @CountryIds;
    INSERT dbo.FundingPlatform_SavedSearchRegions SELECT @SavedSearchId, Id FROM @RegionIds;
    INSERT dbo.FundingPlatform_SavedSearchCategories SELECT @SavedSearchId, Id FROM @CategoryIds;
    INSERT dbo.FundingPlatform_SavedSearchTags SELECT @SavedSearchId, Id FROM @TagIds;
    INSERT dbo.FundingPlatform_SavedSearchBeneficiaryTypes SELECT @SavedSearchId, Id FROM @BeneficiaryTypeIds;
    INSERT dbo.FundingPlatform_SavedSearchProjectTypes SELECT @SavedSearchId, Id FROM @ProjectTypeIds;
    INSERT dbo.FundingPlatform_SavedSearchFundingTypes SELECT @SavedSearchId, Id FROM @FundingTypeIds;
    INSERT dbo.FundingPlatform_SavedSearchOrganizationTypes SELECT @SavedSearchId, Id FROM @OrganizationTypeIds;
    INSERT dbo.FundingPlatform_SavedSearchFunders (SavedSearchId, FunderId)
    SELECT @SavedSearchId, funders.Id
    FROM @FunderPublicIds AS requested
    INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.PublicId = requested.Id;
    IF @@ROWCOUNT <> (SELECT COUNT(*) FROM @FunderPublicIds)
        THROW 54502, N'Saved-search funder filters are invalid.', 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AlertSchedule_Claim
    @LeaseOwner UNIQUEIDENTIFIER,
    @BatchSize INT,
    @LeaseSeconds INT,
    @NowUtc DATETIME2(3)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @LeaseOwner IS NULL OR @BatchSize < 1 OR @BatchSize > 25 OR
       @LeaseSeconds < 30 OR @LeaseSeconds > 900
        THROW 54504, N'Alert schedule claim parameters are invalid.', 1;
    BEGIN TRANSACTION;

    UPDATE alerts
    SET IsActive = 0,
        DisabledReasonCode = CASE WHEN searches.DeletedAtUtc IS NOT NULL THEN N'saved-search-deleted'
                                  WHEN organizations.IsActive = 0 THEN N'organization-inactive'
                                  WHEN users.Status <> 2 THEN N'user-inactive'
                                  ELSE N'membership-inactive' END,
        DisabledAtUtc = @NowUtc, LeaseOwner = NULL, LeaseId = NULL, LeaseUntilUtc = NULL,
        UpdatedAtUtc = @NowUtc
    FROM dbo.FundingPlatform_AlertSubscriptions AS alerts
    INNER JOIN dbo.FundingPlatform_SavedSearches AS searches ON searches.Id = alerts.SavedSearchId
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = alerts.OrganizationId
    INNER JOIN dbo.FundingPlatform_Users AS users ON users.Id = alerts.UserId
    LEFT JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = alerts.OrganizationId
       AND memberships.UserId = alerts.UserId AND memberships.MembershipStatus = 1
    WHERE alerts.IsActive = 1 AND
          (searches.DeletedAtUtc IS NOT NULL OR organizations.IsActive = 0 OR
           users.Status <> 2 OR memberships.UserId IS NULL);

    UPDATE dbo.FundingPlatform_AlertSubscriptions
    SET LeaseOwner = NULL, LeaseId = NULL, LeaseUntilUtc = NULL, UpdatedAtUtc = @NowUtc
    WHERE IsActive = 1 AND LeaseUntilUtc <= @NowUtc;

    /* Collapse an extended outage into one catch-up digest. Advancing the due cursor
       to now preserves the full LastRunAtUtc..Now publication window without creating
       one email for every missed day or leaving a permanently poisoned old schedule. */
    UPDATE dbo.FundingPlatform_AlertSubscriptions
    SET NextRunAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc
    WHERE IsActive = 1 AND LeaseId IS NULL
      AND NextRunAtUtc < DATEADD(HOUR, -24, @NowUtc);

    DECLARE @Claimed TABLE
    (
        PublicId UNIQUEIDENTIFIER NOT NULL,
        LeaseId UNIQUEIDENTIFIER NOT NULL,
        LeaseUntilUtc DATETIME2(3) NOT NULL,
        ScheduledForUtc DATETIME2(3) NOT NULL,
        PreferredHourLocal TINYINT NOT NULL,
        TimeZoneId NVARCHAR(100) NOT NULL
    );
    ;WITH due AS
    (
        SELECT TOP (@BatchSize) Id
        FROM dbo.FundingPlatform_AlertSubscriptions WITH (UPDLOCK, READPAST, ROWLOCK)
        WHERE IsActive = 1 AND NextRunAtUtc <= @NowUtc AND LeaseId IS NULL
        ORDER BY NextRunAtUtc, Id
    )
    UPDATE alerts
    SET LeaseOwner = @LeaseOwner, LeaseId = NEWID(),
        LeaseUntilUtc = DATEADD(SECOND, @LeaseSeconds, @NowUtc), UpdatedAtUtc = @NowUtc
    OUTPUT inserted.PublicId, inserted.LeaseId, inserted.LeaseUntilUtc,
           inserted.NextRunAtUtc, inserted.PreferredHourLocal, inserted.TimeZoneId
    INTO @Claimed
    FROM dbo.FundingPlatform_AlertSubscriptions AS alerts
    INNER JOIN due ON due.Id = alerts.Id;
    COMMIT;
    SELECT PublicId AS AlertSubscriptionPublicId, LeaseId, LeaseUntilUtc,
           ScheduledForUtc, PreferredHourLocal, TimeZoneId
    FROM @Claimed ORDER BY ScheduledForUtc, AlertSubscriptionPublicId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AlertSchedule_Materialize
    @AlertSubscriptionPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @ScheduledForUtc DATETIME2(3),
    @NextRunAtUtc DATETIME2(3),
    @NowUtc DATETIME2(3)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @AlertId BIGINT, @SavedSearchId BIGINT, @OrganizationId BIGINT,
            @UserId BIGINT, @LastRunAtUtc DATETIME2(3), @AlertCreatedAtUtc DATETIME2(3),
            @Query NVARCHAR(300), @Sponsor NVARCHAR(300), @MinAmount DECIMAL(19,4),
            @MaxAmount DECIMAL(19,4), @Currency CHAR(3), @ClosingFrom DATE,
            @ClosingTo DATE, @OnlyOpen BIT, @Locale NVARCHAR(10),
            @NotificationLogId BIGINT, @NotificationPublicId UNIQUEIDENTIFIER,
            @ExistingStatus TINYINT;
    IF @NextRunAtUtc <= @ScheduledForUtc OR @NowUtc < @ScheduledForUtc OR
       @NowUtc > DATEADD(HOUR, 24, @ScheduledForUtc)
        THROW 54504, N'Alert materialization timestamps are invalid.', 1;
    BEGIN TRANSACTION;
    SELECT @AlertId = alerts.Id, @SavedSearchId = alerts.SavedSearchId,
           @OrganizationId = alerts.OrganizationId, @UserId = alerts.UserId,
           @LastRunAtUtc = alerts.LastRunAtUtc, @AlertCreatedAtUtc = alerts.CreatedAtUtc,
           @Query = searches.QueryText, @Sponsor = searches.SponsorText,
           @MinAmount = searches.MinAmount, @MaxAmount = searches.MaxAmount,
           @Currency = searches.Currency, @ClosingFrom = searches.ClosingFrom,
           @ClosingTo = searches.ClosingTo, @OnlyOpen = searches.OnlyOpen,
           @Locale = users.PreferredLocale
    FROM dbo.FundingPlatform_AlertSubscriptions AS alerts WITH (UPDLOCK, HOLDLOCK)
    INNER JOIN dbo.FundingPlatform_SavedSearches AS searches
        ON searches.Id = alerts.SavedSearchId AND searches.DeletedAtUtc IS NULL
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = alerts.OrganizationId AND organizations.IsActive = 1
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = alerts.OrganizationId
       AND memberships.UserId = alerts.UserId AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = alerts.UserId AND users.Status = 2
    WHERE alerts.PublicId = @AlertSubscriptionPublicId AND alerts.IsActive = 1
      AND alerts.LeaseId = @LeaseId AND alerts.LeaseUntilUtc > @NowUtc
      AND alerts.NextRunAtUtc = @ScheduledForUtc;
    IF @AlertId IS NULL
    BEGIN ROLLBACK; SELECT CONVERT(BIT, 0) AS Succeeded, N'lease-lost' AS Code,
        CAST(NULL AS UNIQUEIDENTIFIER) AS NotificationLogPublicId, 0 AS ItemCount,
        CONVERT(BIT, 0) AS WasTruncated; RETURN; END;

    SELECT @NotificationLogId = Id, @NotificationPublicId = PublicId,
           @ExistingStatus = Status
    FROM dbo.FundingPlatform_NotificationLogs WITH (UPDLOCK, HOLDLOCK)
    WHERE AlertSubscriptionId = @AlertId AND ScheduledForUtc = @ScheduledForUtc;
    IF @NotificationLogId IS NOT NULL
    BEGIN
        UPDATE dbo.FundingPlatform_AlertSubscriptions
        SET LastRunAtUtc = @ScheduledForUtc, NextRunAtUtc = @NextRunAtUtc,
            LeaseOwner = NULL, LeaseId = NULL, LeaseUntilUtc = NULL, UpdatedAtUtc = @NowUtc
        WHERE Id = @AlertId;
        COMMIT;
        SELECT CONVERT(BIT, 1) AS Succeeded, N'replayed' AS Code,
               @NotificationPublicId AS NotificationLogPublicId,
               (SELECT ItemCount FROM dbo.FundingPlatform_NotificationLogs
                WHERE Id = @NotificationLogId) AS ItemCount,
               (SELECT WasTruncated FROM dbo.FundingPlatform_NotificationLogs
                WHERE Id = @NotificationLogId) AS WasTruncated;
        RETURN;
    END;

    DECLARE @QueryPattern NVARCHAR(610) = NULL, @SponsorPattern NVARCHAR(610) = NULL;
    IF @Query IS NOT NULL SET @QueryPattern = N'%' +
        REPLACE(REPLACE(REPLACE(REPLACE(@Query, N'~', N'~~'), N'%', N'~%'), N'_', N'~_'), N'[', N'~[') + N'%';
    IF @Sponsor IS NOT NULL SET @SponsorPattern = N'%' +
        REPLACE(REPLACE(REPLACE(REPLACE(@Sponsor, N'~', N'~~'), N'%', N'~%'), N'_', N'~_'), N'[', N'~[') + N'%';
    DECLARE @TodayUtc DATE = CONVERT(DATE, @ScheduledForUtc);
    CREATE TABLE #AlertMatches
    (
        FundingOpportunityId BIGINT NOT NULL PRIMARY KEY,
        PublishedAtUtc DATETIME2(3) NOT NULL
    );
    INSERT #AlertMatches (FundingOpportunityId, PublishedAtUtc)
    SELECT TOP (51) opportunities.Id, opportunities.PublishedAtUtc
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
        ON ready.FundingOpportunityId = opportunities.Id
    WHERE opportunities.PublishedAtUtc > COALESCE(@LastRunAtUtc, @AlertCreatedAtUtc)
      AND opportunities.PublishedAtUtc <= @ScheduledForUtc
      AND (@Query IS NULL OR opportunities.Title LIKE @QueryPattern ESCAPE N'~'
           OR opportunities.SponsorName LIKE @QueryPattern ESCAPE N'~'
           OR opportunities.Summary LIKE @QueryPattern ESCAPE N'~'
           OR opportunities.Description LIKE @QueryPattern ESCAPE N'~'
           OR opportunities.EligibilityDescription LIKE @QueryPattern ESCAPE N'~'
           OR opportunities.Requirements LIKE @QueryPattern ESCAPE N'~')
      AND (@Sponsor IS NULL OR opportunities.SponsorName LIKE @SponsorPattern ESCAPE N'~')
      AND (@Currency IS NULL OR opportunities.Currency = @Currency)
      AND (@MinAmount IS NULL OR (opportunities.AmountStatus = 1 AND
           COALESCE(opportunities.MaxAmount, opportunities.MinAmount) >= @MinAmount))
      AND (@MaxAmount IS NULL OR (opportunities.AmountStatus = 1 AND
           COALESCE(opportunities.MinAmount, opportunities.MaxAmount) <= @MaxAmount))
      AND (@ClosingFrom IS NULL OR opportunities.CloseDate >= @ClosingFrom)
      AND (@ClosingTo IS NULL OR opportunities.CloseDate <= @ClosingTo)
      AND (@OnlyOpen = 0 OR
           ((opportunities.OpenDate IS NULL OR opportunities.OpenDate <= @TodayUtc)
            AND (opportunities.DeadlineType = 2 OR
                 (opportunities.DeadlineType = 1 AND
                  ((opportunities.CloseAtUtc IS NOT NULL AND opportunities.CloseAtUtc > @ScheduledForUtc)
                   OR (opportunities.CloseAtUtc IS NULL AND opportunities.CloseDate >= @TodayUtc))))))
      AND (NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_SavedSearchCountries WHERE SavedSearchId = @SavedSearchId)
           OR opportunities.GeographicScope = 2 OR EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS links
            INNER JOIN dbo.FundingPlatform_SavedSearchCountries AS filters
                ON filters.CountryId = links.CountryId AND filters.SavedSearchId = @SavedSearchId
            WHERE links.FundingOpportunityId = opportunities.Id))
      AND (NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_SavedSearchRegions WHERE SavedSearchId = @SavedSearchId)
           OR opportunities.GeographicScope = 2 OR EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions AS links
            INNER JOIN dbo.FundingPlatform_SavedSearchRegions AS filters
                ON filters.RegionId = links.RegionId AND filters.SavedSearchId = @SavedSearchId
            WHERE links.FundingOpportunityId = opportunities.Id))
      AND (NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_SavedSearchCategories WHERE SavedSearchId = @SavedSearchId)
           OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCategories AS links
            INNER JOIN dbo.FundingPlatform_SavedSearchCategories AS filters
                ON filters.FundingCategoryId = links.FundingCategoryId AND filters.SavedSearchId = @SavedSearchId
            WHERE links.FundingOpportunityId = opportunities.Id))
      AND (NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_SavedSearchTags WHERE SavedSearchId = @SavedSearchId)
           OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityTags AS links
            INNER JOIN dbo.FundingPlatform_SavedSearchTags AS filters
                ON filters.TagId = links.TagId AND filters.SavedSearchId = @SavedSearchId
            WHERE links.FundingOpportunityId = opportunities.Id))
      AND (NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_SavedSearchBeneficiaryTypes WHERE SavedSearchId = @SavedSearchId)
           OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes AS links
            INNER JOIN dbo.FundingPlatform_SavedSearchBeneficiaryTypes AS filters
                ON filters.BeneficiaryTypeId = links.BeneficiaryTypeId AND filters.SavedSearchId = @SavedSearchId
            WHERE links.FundingOpportunityId = opportunities.Id))
      AND (NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_SavedSearchProjectTypes WHERE SavedSearchId = @SavedSearchId)
           OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityProjectTypes AS links
            INNER JOIN dbo.FundingPlatform_SavedSearchProjectTypes AS filters
                ON filters.ProjectTypeId = links.ProjectTypeId AND filters.SavedSearchId = @SavedSearchId
            WHERE links.FundingOpportunityId = opportunities.Id))
      AND (NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_SavedSearchFundingTypes WHERE SavedSearchId = @SavedSearchId)
           OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_SavedSearchFundingTypes AS filters
            WHERE filters.SavedSearchId = @SavedSearchId AND filters.FundingTypeId = opportunities.FundingTypeId))
      AND (NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_SavedSearchOrganizationTypes WHERE SavedSearchId = @SavedSearchId)
           OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityOrganizationTypes AS links
            INNER JOIN dbo.FundingPlatform_SavedSearchOrganizationTypes AS filters
                ON filters.OrganizationTypeId = links.OrganizationTypeId AND filters.SavedSearchId = @SavedSearchId
            WHERE links.FundingOpportunityId = opportunities.Id AND links.EligibilityMode = 1))
      AND (NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_SavedSearchFunders WHERE SavedSearchId = @SavedSearchId)
           OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
            INNER JOIN dbo.FundingPlatform_SavedSearchFunders AS filters
                ON filters.FunderId = links.FunderId AND filters.SavedSearchId = @SavedSearchId
            INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
            WHERE links.FundingOpportunityId = opportunities.Id AND links.IsActive = 1
              AND funders.PublicationStatus = 2 AND funders.IsActive = 1))
    ORDER BY opportunities.PublishedAtUtc DESC, opportunities.Id DESC;

    DECLARE @MatchCount INT = (SELECT COUNT(*) FROM #AlertMatches),
            @ItemCount SMALLINT, @WasTruncated BIT;
    SET @ItemCount = CONVERT(SMALLINT, CASE WHEN @MatchCount > 50 THEN 50 ELSE @MatchCount END);
    SET @WasTruncated = CONVERT(BIT, CASE WHEN @MatchCount > 50 THEN 1 ELSE 0 END);
    INSERT dbo.FundingPlatform_NotificationLogs
        (AlertSubscriptionId, OrganizationId, UserId, ScheduledForUtc, Channel,
         TemplateCode, Locale, IdempotencyKey, Status, AttemptCount, AvailableAtUtc,
         LeaseOwner, LeaseId, LeaseUntilUtc, ProviderMessageId, SentAtUtc, ErrorCode,
         ItemCount, WasTruncated, CreatedAtUtc, UpdatedAtUtc)
    VALUES (@AlertId, @OrganizationId, @UserId, @ScheduledForUtc, 0,
            N'daily-funding-digest-v1', @Locale,
            HASHBYTES('SHA2_256', CONCAT(N'alert-v1|', @AlertSubscriptionPublicId,
                                        N'|', CONVERT(NVARCHAR(33), @ScheduledForUtc, 126))),
            CASE WHEN @ItemCount = 0 THEN 6 ELSE 0 END, 0, @NowUtc,
            NULL, NULL, NULL, NULL, NULL,
            CASE WHEN @ItemCount = 0 THEN N'no-new-opportunities' ELSE NULL END,
            @ItemCount, @WasTruncated, @NowUtc, @NowUtc);
    SET @NotificationLogId = SCOPE_IDENTITY();
    INSERT dbo.FundingPlatform_NotificationLogItems
        (NotificationLogId, FundingOpportunityId, PublishedAtUtc)
    SELECT TOP (50) @NotificationLogId, FundingOpportunityId, PublishedAtUtc
    FROM #AlertMatches ORDER BY PublishedAtUtc DESC, FundingOpportunityId DESC;
    SELECT @NotificationPublicId = PublicId FROM dbo.FundingPlatform_NotificationLogs
        WHERE Id = @NotificationLogId;
    UPDATE dbo.FundingPlatform_AlertSubscriptions
    SET LastRunAtUtc = @ScheduledForUtc, NextRunAtUtc = @NextRunAtUtc,
        LeaseOwner = NULL, LeaseId = NULL, LeaseUntilUtc = NULL, UpdatedAtUtc = @NowUtc
    WHERE Id = @AlertId;
    COMMIT;
    SELECT CONVERT(BIT, 1) AS Succeeded, N'created' AS Code,
           @NotificationPublicId AS NotificationLogPublicId,
           @ItemCount AS ItemCount, @WasTruncated AS WasTruncated;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AlertSubscription_Put
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @SavedSearchPublicId UNIQUEIDENTIFIER,
    @PreferredHourLocal TINYINT,
    @TimeZoneId NVARCHAR(100),
    @NextRunAtUtc DATETIME2(3),
    @NowUtc DATETIME2(3)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @SavedSearchId BIGINT,
            @AlertId BIGINT, @Code NVARCHAR(30);
    BEGIN TRANSACTION;
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1
      AND users.PublicId = @UserPublicId;
    SELECT @SavedSearchId = Id FROM dbo.FundingPlatform_SavedSearches WITH (UPDLOCK, HOLDLOCK)
    WHERE PublicId = @SavedSearchPublicId AND OrganizationId = @OrganizationId
      AND UserId = @UserId AND DeletedAtUtc IS NULL;
    IF @SavedSearchId IS NULL OR @PreferredHourLocal > 23 OR
       LEN(LTRIM(RTRIM(COALESCE(@TimeZoneId, N'')))) NOT BETWEEN 1 AND 100 OR
       @NextRunAtUtc <= @NowUtc
    BEGIN ROLLBACK; SELECT N'not-found' AS Code; RETURN; END;

    SELECT @AlertId = Id FROM dbo.FundingPlatform_AlertSubscriptions WITH (UPDLOCK, HOLDLOCK)
    WHERE SavedSearchId = @SavedSearchId AND Channel = 0;
    IF @AlertId IS NULL
    BEGIN
        INSERT dbo.FundingPlatform_AlertSubscriptions
            (SavedSearchId, OrganizationId, UserId, Channel, Frequency,
             PreferredHourLocal, TimeZoneId, NextRunAtUtc, LastRunAtUtc,
             IsActive, DisabledReasonCode, DisabledAtUtc, UnsubscribeNonce,
             LeaseOwner, LeaseId, LeaseUntilUtc, CreatedAtUtc, UpdatedAtUtc)
        VALUES (@SavedSearchId, @OrganizationId, @UserId, 0, 0,
                @PreferredHourLocal, @TimeZoneId, @NextRunAtUtc, NULL,
                1, NULL, NULL, NEWID(), NULL, NULL, NULL, @NowUtc, @NowUtc);
        SET @AlertId = SCOPE_IDENTITY(); SET @Code = N'created';
    END
    ELSE
    BEGIN
        UPDATE dbo.FundingPlatform_AlertSubscriptions
        SET PreferredHourLocal = @PreferredHourLocal, TimeZoneId = @TimeZoneId,
            NextRunAtUtc = @NextRunAtUtc, IsActive = 1,
            DisabledReasonCode = NULL, DisabledAtUtc = NULL,
            UnsubscribeNonce = CASE WHEN IsActive = 0 THEN NEWID() ELSE UnsubscribeNonce END,
            LeaseOwner = NULL, LeaseId = NULL, LeaseUntilUtc = NULL, UpdatedAtUtc = @NowUtc
        WHERE Id = @AlertId;
        SET @Code = N'updated';
    END;
    COMMIT;
    SELECT @Code AS Code, PublicId AS AlertSubscriptionPublicId,
           PreferredHourLocal, TimeZoneId, NextRunAtUtc, LastRunAtUtc,
           IsActive, DisabledReasonCode, CreatedAtUtc, UpdatedAtUtc, RowVersion
    FROM dbo.FundingPlatform_AlertSubscriptions WHERE Id = @AlertId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AlertSubscription_Delete
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @SavedSearchPublicId UNIQUEIDENTIFIER,
    @NowUtc DATETIME2(3)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @AlertId BIGINT;
    BEGIN TRANSACTION;
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1
      AND users.PublicId = @UserPublicId;
    SELECT @AlertId = alerts.Id
    FROM dbo.FundingPlatform_AlertSubscriptions AS alerts WITH (UPDLOCK, HOLDLOCK)
    INNER JOIN dbo.FundingPlatform_SavedSearches AS searches ON searches.Id = alerts.SavedSearchId
    WHERE searches.PublicId = @SavedSearchPublicId AND alerts.OrganizationId = @OrganizationId
      AND alerts.UserId = @UserId AND searches.DeletedAtUtc IS NULL AND alerts.Channel = 0;
    IF @AlertId IS NULL
    BEGIN ROLLBACK; SELECT N'not-found' AS Code; RETURN; END;
    UPDATE dbo.FundingPlatform_AlertSubscriptions
    SET IsActive = 0,
        DisabledReasonCode = CASE WHEN IsActive = 1 THEN N'unsubscribe-user' ELSE DisabledReasonCode END,
        DisabledAtUtc = CASE WHEN IsActive = 1 THEN @NowUtc ELSE DisabledAtUtc END,
        LeaseOwner = NULL, LeaseId = NULL, LeaseUntilUtc = NULL, UpdatedAtUtc = @NowUtc
    WHERE Id = @AlertId;
    COMMIT;
    SELECT N'deleted' AS Code, PublicId AS AlertSubscriptionPublicId,
           PreferredHourLocal, TimeZoneId, NextRunAtUtc, LastRunAtUtc,
           IsActive, DisabledReasonCode, CreatedAtUtc, UpdatedAtUtc, RowVersion
    FROM dbo.FundingPlatform_AlertSubscriptions WHERE Id = @AlertId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AlertSubscription_Unsubscribe
    @AlertSubscriptionPublicId UNIQUEIDENTIFIER,
    @UnsubscribeNonce UNIQUEIDENTIFIER,
    @NowUtc DATETIME2(3)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @AlertId BIGINT;
    BEGIN TRANSACTION;
    SELECT @AlertId = Id FROM dbo.FundingPlatform_AlertSubscriptions WITH (UPDLOCK, HOLDLOCK)
    WHERE PublicId = @AlertSubscriptionPublicId AND UnsubscribeNonce = @UnsubscribeNonce;
    IF @AlertId IS NULL
    BEGIN ROLLBACK; SELECT N'not-found' AS Code; RETURN; END;
    UPDATE dbo.FundingPlatform_AlertSubscriptions
    SET IsActive = 0,
        DisabledReasonCode = CASE WHEN IsActive = 1 THEN N'unsubscribe-link' ELSE DisabledReasonCode END,
        DisabledAtUtc = CASE WHEN IsActive = 1 THEN @NowUtc ELSE DisabledAtUtc END,
        LeaseOwner = NULL, LeaseId = NULL, LeaseUntilUtc = NULL, UpdatedAtUtc = @NowUtc
    WHERE Id = @AlertId;
    COMMIT;
    SELECT N'deleted' AS Code;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_NotificationLog_List
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @PageNumber INT = 1,
    @PageSize INT = 20
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT;
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1
      AND users.PublicId = @UserPublicId;
    IF @OrganizationId IS NULL OR @UserId IS NULL
        THROW 54503, N'The notification workspace was not found.', 1;
    IF @PageNumber < 1 OR @PageNumber > 10000 OR @PageSize < 1 OR @PageSize > 50
        THROW 54502, N'Notification pagination is invalid.', 1;
    SELECT COUNT_BIG(*) AS TotalCount FROM dbo.FundingPlatform_NotificationLogs
    WHERE OrganizationId = @OrganizationId AND UserId = @UserId;
    SELECT logs.PublicId AS NotificationLogPublicId,
           alerts.PublicId AS AlertSubscriptionPublicId,
           searches.PublicId AS SavedSearchPublicId, searches.Name AS SavedSearchName,
           logs.Status, logs.ItemCount, logs.WasTruncated, logs.ScheduledForUtc,
           logs.SentAtUtc, logs.ErrorCode, logs.CreatedAtUtc
    FROM dbo.FundingPlatform_NotificationLogs AS logs
    INNER JOIN dbo.FundingPlatform_AlertSubscriptions AS alerts
        ON alerts.Id = logs.AlertSubscriptionId
    INNER JOIN dbo.FundingPlatform_SavedSearches AS searches
        ON searches.Id = alerts.SavedSearchId
    WHERE logs.OrganizationId = @OrganizationId AND logs.UserId = @UserId
    ORDER BY logs.CreatedAtUtc DESC, logs.Id DESC
    OFFSET (CONVERT(BIGINT, @PageNumber) - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SavedSearch_List
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @PageNumber INT = 1,
    @PageSize INT = 20
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT;
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1
      AND users.PublicId = @UserPublicId;
    IF @OrganizationId IS NULL OR @UserId IS NULL
        THROW 54503, N'The saved-search workspace was not found.', 1;
    IF @PageNumber < 1 OR @PageNumber > 10000 OR @PageSize < 1 OR @PageSize > 50
        THROW 54502, N'Saved-search pagination is invalid.', 1;

    SELECT COUNT_BIG(*) AS TotalCount
    FROM dbo.FundingPlatform_SavedSearches
    WHERE OrganizationId = @OrganizationId AND UserId = @UserId AND DeletedAtUtc IS NULL;

    SELECT searches.PublicId AS SavedSearchPublicId, searches.Name, searches.QueryText,
           searches.OnlyOpen, searches.SortCode,
           CONVERT(BIT, CASE WHEN alerts.Id IS NULL THEN 0 ELSE 1 END) AS HasActiveAlert,
           searches.CreatedAtUtc, searches.UpdatedAtUtc, searches.RowVersion
    FROM dbo.FundingPlatform_SavedSearches AS searches
    LEFT JOIN dbo.FundingPlatform_AlertSubscriptions AS alerts
        ON alerts.SavedSearchId = searches.Id AND alerts.Channel = 0 AND alerts.IsActive = 1
    WHERE searches.OrganizationId = @OrganizationId AND searches.UserId = @UserId
      AND searches.DeletedAtUtc IS NULL
    ORDER BY searches.UpdatedAtUtc DESC, searches.Id DESC
    OFFSET (CONVERT(BIGINT, @PageNumber) - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SavedSearch_Get
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @SavedSearchPublicId UNIQUEIDENTIFIER
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @SavedSearchId BIGINT;
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1
      AND users.PublicId = @UserPublicId;
    IF @OrganizationId IS NULL OR @UserId IS NULL
        THROW 54503, N'The saved-search workspace was not found.', 1;
    SELECT @SavedSearchId = Id FROM dbo.FundingPlatform_SavedSearches
    WHERE PublicId = @SavedSearchPublicId AND OrganizationId = @OrganizationId
      AND UserId = @UserId AND DeletedAtUtc IS NULL;
    IF @SavedSearchId IS NULL
        THROW 54503, N'The saved search was not found.', 1;

    SELECT searches.PublicId AS SavedSearchPublicId, searches.Name, searches.QueryText,
           searches.SponsorText, searches.MinAmount, searches.MaxAmount, searches.Currency,
           searches.ClosingFrom, searches.ClosingTo, searches.OnlyOpen, searches.SortCode,
           searches.CreatedAtUtc, searches.UpdatedAtUtc, searches.RowVersion,
           alerts.PublicId AS AlertSubscriptionPublicId, alerts.PreferredHourLocal,
           alerts.TimeZoneId, alerts.NextRunAtUtc, alerts.LastRunAtUtc, alerts.IsActive,
           alerts.DisabledReasonCode, alerts.CreatedAtUtc AS AlertCreatedAtUtc,
           alerts.UpdatedAtUtc AS AlertUpdatedAtUtc, alerts.RowVersion AS AlertRowVersion
    FROM dbo.FundingPlatform_SavedSearches AS searches
    LEFT JOIN dbo.FundingPlatform_AlertSubscriptions AS alerts
        ON alerts.SavedSearchId = searches.Id AND alerts.Channel = 0
    WHERE searches.Id = @SavedSearchId;
    SELECT CountryId AS Id FROM dbo.FundingPlatform_SavedSearchCountries
        WHERE SavedSearchId = @SavedSearchId ORDER BY CountryId;
    SELECT RegionId AS Id FROM dbo.FundingPlatform_SavedSearchRegions
        WHERE SavedSearchId = @SavedSearchId ORDER BY RegionId;
    SELECT FundingCategoryId AS Id FROM dbo.FundingPlatform_SavedSearchCategories
        WHERE SavedSearchId = @SavedSearchId ORDER BY FundingCategoryId;
    SELECT TagId AS Id FROM dbo.FundingPlatform_SavedSearchTags
        WHERE SavedSearchId = @SavedSearchId ORDER BY TagId;
    SELECT BeneficiaryTypeId AS Id FROM dbo.FundingPlatform_SavedSearchBeneficiaryTypes
        WHERE SavedSearchId = @SavedSearchId ORDER BY BeneficiaryTypeId;
    SELECT ProjectTypeId AS Id FROM dbo.FundingPlatform_SavedSearchProjectTypes
        WHERE SavedSearchId = @SavedSearchId ORDER BY ProjectTypeId;
    SELECT FundingTypeId AS Id FROM dbo.FundingPlatform_SavedSearchFundingTypes
        WHERE SavedSearchId = @SavedSearchId ORDER BY FundingTypeId;
    SELECT OrganizationTypeId AS Id FROM dbo.FundingPlatform_SavedSearchOrganizationTypes
        WHERE SavedSearchId = @SavedSearchId ORDER BY OrganizationTypeId;
    SELECT funders.PublicId AS Id
    FROM dbo.FundingPlatform_SavedSearchFunders AS links
    INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
    WHERE links.SavedSearchId = @SavedSearchId ORDER BY funders.PublicId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SavedSearch_Create
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @Name NVARCHAR(150),
    @QueryText NVARCHAR(300) = NULL,
    @SponsorText NVARCHAR(300) = NULL,
    @MinAmount DECIMAL(19,4) = NULL,
    @MaxAmount DECIMAL(19,4) = NULL,
    @Currency CHAR(3) = NULL,
    @ClosingFrom DATE = NULL,
    @ClosingTo DATE = NULL,
    @OnlyOpen BIT,
    @SortCode TINYINT,
    @CountryIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @RegionIds dbo.FundingPlatform_IntIdList READONLY,
    @CategoryIds dbo.FundingPlatform_IntIdList READONLY,
    @TagIds dbo.FundingPlatform_BigIntIdList READONLY,
    @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @FundingTypeIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @OrganizationTypeIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @FunderPublicIds dbo.FundingPlatform_GuidIdList READONLY,
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @NowUtc DATETIME2(3)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @SavedSearchId BIGINT,
            @ExistingRequestHash BINARY(32), @SavedSearchPublicId UNIQUEIDENTIFIER;
    BEGIN TRANSACTION;
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id
    FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
        ON memberships.OrganizationId = organizations.Id AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1
      AND users.PublicId = @UserPublicId;
    IF @OrganizationId IS NULL OR @UserId IS NULL
    BEGIN ROLLBACK; SELECT N'not-found' AS Code, CAST(NULL AS UNIQUEIDENTIFIER) AS SavedSearchPublicId; RETURN; END;

    SELECT @ExistingRequestHash = RequestHash, @SavedSearchId = SavedSearchId
    FROM dbo.FundingPlatform_SavedSearchCreateRequests WITH (UPDLOCK, HOLDLOCK)
    WHERE OrganizationId = @OrganizationId AND UserId = @UserId
      AND IdempotencyKeyHash = @IdempotencyKeyHash;
    IF @SavedSearchId IS NOT NULL
    BEGIN
        SELECT @SavedSearchPublicId = PublicId FROM dbo.FundingPlatform_SavedSearches
            WHERE Id = @SavedSearchId;
        COMMIT;
        SELECT CASE WHEN @ExistingRequestHash = @RequestHash THEN N'replayed'
                    ELSE N'idempotency-conflict' END AS Code,
               @SavedSearchPublicId AS SavedSearchPublicId;
        RETURN;
    END;

    INSERT dbo.FundingPlatform_SavedSearches
        (OrganizationId, UserId, Name, QueryText, SponsorText, MinAmount, MaxAmount,
         Currency, ClosingFrom, ClosingTo, OnlyOpen, SortCode, DeletedAtUtc,
         CreatedAtUtc, UpdatedAtUtc)
    VALUES (@OrganizationId, @UserId, @Name, @QueryText, @SponsorText, @MinAmount,
            @MaxAmount, @Currency, @ClosingFrom, @ClosingTo, @OnlyOpen, @SortCode,
            NULL, @NowUtc, @NowUtc);
    SET @SavedSearchId = SCOPE_IDENTITY();
    EXEC dbo.FundingPlatform_usp_SavedSearch_ReplaceFilters
        @SavedSearchId, @CountryIds, @RegionIds, @CategoryIds, @TagIds,
        @BeneficiaryTypeIds, @ProjectTypeIds, @FundingTypeIds,
        @OrganizationTypeIds, @FunderPublicIds;
    INSERT dbo.FundingPlatform_SavedSearchCreateRequests
        (OrganizationId, UserId, IdempotencyKeyHash, RequestHash, SavedSearchId, CreatedAtUtc)
    VALUES (@OrganizationId, @UserId, @IdempotencyKeyHash, @RequestHash,
            @SavedSearchId, @NowUtc);
    SELECT @SavedSearchPublicId = PublicId FROM dbo.FundingPlatform_SavedSearches
        WHERE Id = @SavedSearchId;
    COMMIT;
    SELECT N'created' AS Code, @SavedSearchPublicId AS SavedSearchPublicId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SavedSearch_Update
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @SavedSearchPublicId UNIQUEIDENTIFIER,
    @Name NVARCHAR(150),
    @QueryText NVARCHAR(300) = NULL,
    @SponsorText NVARCHAR(300) = NULL,
    @MinAmount DECIMAL(19,4) = NULL,
    @MaxAmount DECIMAL(19,4) = NULL,
    @Currency CHAR(3) = NULL,
    @ClosingFrom DATE = NULL,
    @ClosingTo DATE = NULL,
    @OnlyOpen BIT,
    @SortCode TINYINT,
    @CountryIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @RegionIds dbo.FundingPlatform_IntIdList READONLY,
    @CategoryIds dbo.FundingPlatform_IntIdList READONLY,
    @TagIds dbo.FundingPlatform_BigIntIdList READONLY,
    @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @FundingTypeIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @OrganizationTypeIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @FunderPublicIds dbo.FundingPlatform_GuidIdList READONLY,
    @ExpectedRowVersion BINARY(8),
    @NowUtc DATETIME2(3)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @SavedSearchId BIGINT;
    BEGIN TRANSACTION;
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1
      AND users.PublicId = @UserPublicId;
    SELECT @SavedSearchId = Id FROM dbo.FundingPlatform_SavedSearches WITH (UPDLOCK, HOLDLOCK)
    WHERE PublicId = @SavedSearchPublicId AND OrganizationId = @OrganizationId
      AND UserId = @UserId AND DeletedAtUtc IS NULL;
    IF @SavedSearchId IS NULL
    BEGIN ROLLBACK; SELECT N'not-found' AS Code, @SavedSearchPublicId AS SavedSearchPublicId; RETURN; END;
    UPDATE dbo.FundingPlatform_SavedSearches
    SET Name = @Name, QueryText = @QueryText, SponsorText = @SponsorText,
        MinAmount = @MinAmount, MaxAmount = @MaxAmount, Currency = @Currency,
        ClosingFrom = @ClosingFrom, ClosingTo = @ClosingTo, OnlyOpen = @OnlyOpen,
        SortCode = @SortCode, UpdatedAtUtc = @NowUtc
    WHERE Id = @SavedSearchId AND RowVersion = @ExpectedRowVersion;
    IF @@ROWCOUNT = 0
    BEGIN ROLLBACK; SELECT N'etag-conflict' AS Code, @SavedSearchPublicId AS SavedSearchPublicId; RETURN; END;
    EXEC dbo.FundingPlatform_usp_SavedSearch_ReplaceFilters
        @SavedSearchId, @CountryIds, @RegionIds, @CategoryIds, @TagIds,
        @BeneficiaryTypeIds, @ProjectTypeIds, @FundingTypeIds,
        @OrganizationTypeIds, @FunderPublicIds;
    COMMIT;
    SELECT N'updated' AS Code, @SavedSearchPublicId AS SavedSearchPublicId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SavedSearch_Delete
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @SavedSearchPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @NowUtc DATETIME2(3)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @SavedSearchId BIGINT;
    BEGIN TRANSACTION;
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1
      AND users.PublicId = @UserPublicId;
    SELECT @SavedSearchId = Id FROM dbo.FundingPlatform_SavedSearches WITH (UPDLOCK, HOLDLOCK)
    WHERE PublicId = @SavedSearchPublicId AND OrganizationId = @OrganizationId
      AND UserId = @UserId AND DeletedAtUtc IS NULL;
    IF @SavedSearchId IS NULL
    BEGIN ROLLBACK; SELECT N'not-found' AS Code, @SavedSearchPublicId AS SavedSearchPublicId; RETURN; END;
    UPDATE dbo.FundingPlatform_SavedSearches
    SET DeletedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc
    WHERE Id = @SavedSearchId AND RowVersion = @ExpectedRowVersion;
    IF @@ROWCOUNT = 0
    BEGIN ROLLBACK; SELECT N'etag-conflict' AS Code, @SavedSearchPublicId AS SavedSearchPublicId; RETURN; END;
    UPDATE dbo.FundingPlatform_AlertSubscriptions
    SET IsActive = 0, DisabledReasonCode = N'saved-search-deleted', DisabledAtUtc = @NowUtc,
        LeaseOwner = NULL, LeaseId = NULL, LeaseUntilUtc = NULL, UpdatedAtUtc = @NowUtc
    WHERE SavedSearchId = @SavedSearchId AND IsActive = 1;
    COMMIT;
    SELECT N'deleted' AS Code, @SavedSearchPublicId AS SavedSearchPublicId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AlertDelivery_Claim
    @LeaseOwner UNIQUEIDENTIFIER,
    @LeaseSeconds INT,
    @MaximumAttempts INT,
    @NowUtc DATETIME2(3)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @LeaseOwner IS NULL OR @LeaseSeconds < 60 OR @LeaseSeconds > 900 OR
       @MaximumAttempts < 1 OR @MaximumAttempts > 5
        THROW 54504, N'Alert delivery claim parameters are invalid.', 1;
    DECLARE @NotificationLogId BIGINT;
    BEGIN TRANSACTION;

    UPDATE dbo.FundingPlatform_NotificationLogs
    SET Status = 4, ErrorCode = N'delivery-lease-expired',
        LeaseOwner = NULL, LeaseId = NULL, LeaseUntilUtc = NULL, UpdatedAtUtc = @NowUtc
    WHERE Status = 1 AND LeaseUntilUtc <= @NowUtc;

    UPDATE logs
    SET Status = 6, ErrorCode = N'recipient-no-longer-active', UpdatedAtUtc = @NowUtc
    FROM dbo.FundingPlatform_NotificationLogs AS logs
    INNER JOIN dbo.FundingPlatform_AlertSubscriptions AS alerts
        ON alerts.Id = logs.AlertSubscriptionId
    INNER JOIN dbo.FundingPlatform_SavedSearches AS searches ON searches.Id = alerts.SavedSearchId
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = logs.OrganizationId
    INNER JOIN dbo.FundingPlatform_Users AS users ON users.Id = logs.UserId
    LEFT JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = logs.OrganizationId
       AND memberships.UserId = logs.UserId AND memberships.MembershipStatus = 1
    WHERE logs.Status IN (0, 3) AND
         (alerts.IsActive = 0 OR searches.DeletedAtUtc IS NOT NULL OR
          organizations.IsActive = 0 OR users.Status <> 2 OR memberships.UserId IS NULL);

    UPDATE logs
    SET Status = 6, ErrorCode = N'opportunities-no-longer-available', UpdatedAtUtc = @NowUtc
    FROM dbo.FundingPlatform_NotificationLogs AS logs
    WHERE logs.Status IN (0, 3) AND NOT EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_NotificationLogItems AS items
        INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
            ON ready.FundingOpportunityId = items.FundingOpportunityId
        WHERE items.NotificationLogId = logs.Id
    );

    DECLARE @Claimed TABLE (Id BIGINT NOT NULL PRIMARY KEY);
    ;WITH candidate AS
    (
        SELECT TOP (1) Id
        FROM dbo.FundingPlatform_NotificationLogs WITH (UPDLOCK, READPAST, ROWLOCK)
        WHERE Status IN (0, 3) AND AvailableAtUtc <= @NowUtc
          AND AttemptCount < @MaximumAttempts
        ORDER BY AvailableAtUtc, Id
    )
    UPDATE logs
    SET Status = 1, AttemptCount = AttemptCount + 1, LeaseOwner = @LeaseOwner,
        LeaseId = NEWID(), LeaseUntilUtc = DATEADD(SECOND, @LeaseSeconds, @NowUtc),
        ErrorCode = NULL, UpdatedAtUtc = @NowUtc
    OUTPUT inserted.Id INTO @Claimed (Id)
    FROM dbo.FundingPlatform_NotificationLogs AS logs
    INNER JOIN candidate ON candidate.Id = logs.Id;
    SELECT @NotificationLogId = Id FROM @Claimed;
    COMMIT;

    SELECT logs.PublicId AS NotificationLogPublicId,
           alerts.PublicId AS AlertSubscriptionPublicId, logs.LeaseId, logs.LeaseUntilUtc,
           users.Email AS RecipientEmail, users.DisplayName AS RecipientDisplayName,
           logs.Locale, alerts.UnsubscribeNonce, searches.Name AS SavedSearchName,
           logs.ScheduledForUtc, logs.AttemptCount
    FROM dbo.FundingPlatform_NotificationLogs AS logs
    INNER JOIN dbo.FundingPlatform_AlertSubscriptions AS alerts
        ON alerts.Id = logs.AlertSubscriptionId
    INNER JOIN dbo.FundingPlatform_SavedSearches AS searches ON searches.Id = alerts.SavedSearchId
    INNER JOIN dbo.FundingPlatform_Users AS users ON users.Id = logs.UserId
    WHERE logs.Id = @NotificationLogId;
    SELECT opportunities.PublicId AS FundingOpportunityPublicId,
           opportunities.Slug, opportunities.Title, opportunities.SponsorName,
           opportunities.CloseDate, opportunities.CloseAtUtc,
           opportunities.DeadlineType, opportunities.DeadlinePrecision
    FROM dbo.FundingPlatform_NotificationLogItems AS items
    INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
        ON ready.FundingOpportunityId = items.FundingOpportunityId
    INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
        ON opportunities.Id = items.FundingOpportunityId
    WHERE items.NotificationLogId = @NotificationLogId
    ORDER BY items.PublishedAtUtc DESC, items.FundingOpportunityId DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AlertDelivery_RenewLease
    @NotificationLogPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @LeaseSeconds INT,
    @NowUtc DATETIME2(3)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    IF @LeaseSeconds < 60 OR @LeaseSeconds > 900
        THROW 54504, N'Alert delivery renewal is invalid.', 1;
    UPDATE dbo.FundingPlatform_NotificationLogs
    SET LeaseUntilUtc = DATEADD(SECOND, @LeaseSeconds, @NowUtc), UpdatedAtUtc = @NowUtc
    WHERE PublicId = @NotificationLogPublicId AND Status = 1 AND LeaseId = @LeaseId
      AND LeaseUntilUtc > @NowUtc;
    SELECT CONVERT(BIT, CASE WHEN @@ROWCOUNT = 1 THEN 1 ELSE 0 END) AS Succeeded;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AlertDelivery_Complete
    @NotificationLogPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @ProviderMessageId NVARCHAR(200),
    @NowUtc DATETIME2(3)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF LEN(LTRIM(RTRIM(COALESCE(@ProviderMessageId, N'')))) NOT BETWEEN 1 AND 200
        THROW 54504, N'Alert provider receipt is invalid.', 1;
    UPDATE dbo.FundingPlatform_NotificationLogs
    SET Status = 2, ProviderMessageId = @ProviderMessageId, SentAtUtc = @NowUtc,
        ErrorCode = NULL, LeaseOwner = NULL, LeaseId = NULL, LeaseUntilUtc = NULL,
        UpdatedAtUtc = @NowUtc
    WHERE PublicId = @NotificationLogPublicId AND Status = 1 AND LeaseId = @LeaseId
      AND LeaseUntilUtc > @NowUtc;
    SELECT CONVERT(BIT, CASE WHEN @@ROWCOUNT = 1 THEN 1 ELSE 0 END) AS Succeeded;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AlertDelivery_Fail
    @NotificationLogPublicId UNIQUEIDENTIFIER,
    @LeaseId UNIQUEIDENTIFIER,
    @DeliveryUnknown BIT,
    @ErrorCode NVARCHAR(100),
    @RetryDelaySeconds INT,
    @MaximumAttempts INT,
    @NowUtc DATETIME2(3)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @DeliveryUnknown IS NULL OR @RetryDelaySeconds < 30 OR @RetryDelaySeconds > 86400 OR
       @MaximumAttempts < 1 OR @MaximumAttempts > 5 OR
       LEN(LTRIM(RTRIM(COALESCE(@ErrorCode, N'')))) NOT BETWEEN 1 AND 100 OR
       @ErrorCode LIKE N'%[^a-z0-9-]%' COLLATE Latin1_General_100_BIN2
        THROW 54504, N'Alert delivery failure is invalid.', 1;
    UPDATE dbo.FundingPlatform_NotificationLogs
    SET Status = CASE WHEN @DeliveryUnknown = 1 THEN 4
                      WHEN AttemptCount >= @MaximumAttempts THEN 5 ELSE 3 END,
        AvailableAtUtc = CASE WHEN @DeliveryUnknown = 0 AND AttemptCount < @MaximumAttempts
                              THEN DATEADD(SECOND, @RetryDelaySeconds, @NowUtc)
                              ELSE AvailableAtUtc END,
        ErrorCode = @ErrorCode, LeaseOwner = NULL, LeaseId = NULL, LeaseUntilUtc = NULL,
        UpdatedAtUtc = @NowUtc
    WHERE PublicId = @NotificationLogPublicId AND Status = 1 AND LeaseId = @LeaseId
      AND LeaseUntilUtc > @NowUtc;
    SELECT CONVERT(BIT, CASE WHEN @@ROWCOUNT = 1 THEN 1 ELSE 0 END) AS Succeeded;
END;
GO

IF DATABASE_PRINCIPAL_ID(N'FundingPlatform_AlertWorkerRole') IS NULL
    CREATE ROLE FundingPlatform_AlertWorkerRole AUTHORIZATION dbo;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_AlertSchedule_Claim
    TO FundingPlatform_AlertWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_AlertSchedule_Materialize
    TO FundingPlatform_AlertWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_AlertDelivery_Claim
    TO FundingPlatform_AlertWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_AlertDelivery_RenewLease
    TO FundingPlatform_AlertWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_AlertDelivery_Complete
    TO FundingPlatform_AlertWorkerRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_AlertDelivery_Fail
    TO FundingPlatform_AlertWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_SavedSearches
    TO FundingPlatform_AlertWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_AlertSubscriptions
    TO FundingPlatform_AlertWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_NotificationLogs
    TO FundingPlatform_AlertWorkerRole;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.FundingPlatform_NotificationLogItems
    TO FundingPlatform_AlertWorkerRole;
GO
