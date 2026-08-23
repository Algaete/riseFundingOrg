/* FundingPlatform FASE 6 - canonical funders and governed opportunity editorial workflow. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

ALTER TABLE dbo.FundingPlatform_RefreshTokens ADD
    MfaAuthenticatedAtUtc DATETIME2(3) NULL;
GO

ALTER TABLE dbo.FundingPlatform_RefreshTokens
    ADD CONSTRAINT FundingPlatform_CK_RefreshTokens_MfaAuthenticatedAt
        CHECK (MfaAuthenticatedAtUtc IS NULL
               OR (MfaAuthenticated = 1 AND MfaAuthenticatedAtUtc <= CreatedAtUtc));

ALTER TABLE dbo.FundingPlatform_FundingOpportunities ADD
    SubmittedAtUtc DATETIME2(3) NULL,
    ReviewedAtUtc DATETIME2(3) NULL,
    ReviewedByUserId BIGINT NULL,
    RejectionReason NVARCHAR(1000) NULL,
    CreatedByUserId BIGINT NULL,
    UpdatedByUserId BIGINT NULL;
GO


UPDATE dbo.FundingPlatform_FundingOpportunities
SET SubmittedAtUtc = CASE WHEN PublicationStatus = 1
                          THEN COALESCE(UpdatedAtUtc, CreatedAtUtc) ELSE NULL END,
    PublishedAtUtc = CASE WHEN PublicationStatus = 2
                          THEN COALESCE(PublishedAtUtc, UpdatedAtUtc, CreatedAtUtc)
                          ELSE PublishedAtUtc END,
    ReviewedAtUtc = CASE WHEN PublicationStatus IN (2, 3)
                         THEN COALESCE(PublishedAtUtc, UpdatedAtUtc, CreatedAtUtc) ELSE NULL END,
    RejectionReason = CASE WHEN PublicationStatus = 3
                           THEN N'Legacy rejection recorded before editorial auditing.' ELSE NULL END;

UPDATE dbo.FundingPlatform_FundingOpportunities
SET PublicationStatus = 4,
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE IsActive = 0 AND PublicationStatus <> 4;

UPDATE dbo.FundingPlatform_FundingOpportunities
SET IsActive = 0,
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE PublicationStatus = 4 AND IsActive <> 0;

ALTER TABLE dbo.FundingPlatform_FundingOpportunities
    ADD CONSTRAINT FundingPlatform_FK_FundingOpportunities_ReviewedBy
        FOREIGN KEY (ReviewedByUserId) REFERENCES dbo.FundingPlatform_Users (Id);
ALTER TABLE dbo.FundingPlatform_FundingOpportunities
    ADD CONSTRAINT FundingPlatform_FK_FundingOpportunities_CreatedBy
        FOREIGN KEY (CreatedByUserId) REFERENCES dbo.FundingPlatform_Users (Id);
ALTER TABLE dbo.FundingPlatform_FundingOpportunities
    ADD CONSTRAINT FundingPlatform_FK_FundingOpportunities_UpdatedBy
        FOREIGN KEY (UpdatedByUserId) REFERENCES dbo.FundingPlatform_Users (Id);
ALTER TABLE dbo.FundingPlatform_FundingOpportunities
    ADD CONSTRAINT FundingPlatform_CK_FundingOpportunities_PendingSubmitted
        CHECK (PublicationStatus <> 1 OR SubmittedAtUtc IS NOT NULL);
ALTER TABLE dbo.FundingPlatform_FundingOpportunities
    ADD CONSTRAINT FundingPlatform_CK_FundingOpportunities_PublishedReview
        CHECK (PublicationStatus <> 2 OR
               (PublishedAtUtc IS NOT NULL AND ReviewedAtUtc IS NOT NULL
                AND RejectionReason IS NULL));
ALTER TABLE dbo.FundingPlatform_FundingOpportunities
    ADD CONSTRAINT FundingPlatform_CK_FundingOpportunities_RejectedReview
        CHECK (PublicationStatus <> 3 OR
               (ReviewedAtUtc IS NOT NULL
                AND NULLIF(LTRIM(RTRIM(RejectionReason)), N'') IS NOT NULL));
ALTER TABLE dbo.FundingPlatform_FundingOpportunities
    ADD CONSTRAINT FundingPlatform_CK_FundingOpportunities_ArchiveActive
        CHECK ((PublicationStatus = 4 AND IsActive = 0)
               OR (PublicationStatus <> 4 AND IsActive = 1));

CREATE INDEX FundingPlatform_IX_FundingOpportunities_ReviewQueue
    ON dbo.FundingPlatform_FundingOpportunities (PublicationStatus, SubmittedAtUtc, Id)
    INCLUDE (PublicId, Slug, Title, SponsorName, ContentVersion, UpdatedAtUtc)
    WHERE PublicationStatus = 1 AND IsActive = 1;

ALTER TABLE dbo.FundingPlatform_FundingOpportunitySourceLinks
    ADD CONSTRAINT FundingPlatform_UQ_FundingOpportunitySourceLinks_IdOpportunity
        UNIQUE (Id, FundingOpportunityId);

CREATE TABLE dbo.FundingPlatform_Funders
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_Funders_PublicId DEFAULT (NEWSEQUENTIALID()),
    Slug NVARCHAR(180) NOT NULL,
    Name NVARCHAR(300) NOT NULL,
    NormalizedName NVARCHAR(300) NOT NULL,
    Description NVARCHAR(2000) NULL,
    WebsiteUrl NVARCHAR(2048) NULL,
    CountryId SMALLINT NULL,
    PublicationStatus TINYINT NOT NULL
        CONSTRAINT FundingPlatform_DF_Funders_PublicationStatus DEFAULT (0),
    SubmittedAtUtc DATETIME2(3) NULL,
    PublishedAtUtc DATETIME2(3) NULL,
    ReviewedAtUtc DATETIME2(3) NULL,
    ReviewedByUserId BIGINT NULL,
    RejectionReason NVARCHAR(1000) NULL,
    ContentVersion INT NOT NULL CONSTRAINT FundingPlatform_DF_Funders_ContentVersion DEFAULT (1),
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_Funders_IsActive DEFAULT (1),
    CreatedByUserId BIGINT NULL,
    UpdatedByUserId BIGINT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_Funders_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_Funders_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_Funders PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_Funders_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_Funders_Slug UNIQUE (Slug),
    CONSTRAINT FundingPlatform_UQ_Funders_NormalizedName UNIQUE (NormalizedName),
    CONSTRAINT FundingPlatform_FK_Funders_Country FOREIGN KEY (CountryId)
        REFERENCES dbo.FundingPlatform_Countries (Id),
    CONSTRAINT FundingPlatform_FK_Funders_ReviewedBy FOREIGN KEY (ReviewedByUserId)
        REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_Funders_CreatedBy FOREIGN KEY (CreatedByUserId)
        REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_Funders_UpdatedBy FOREIGN KEY (UpdatedByUserId)
        REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_Funders_Status CHECK (PublicationStatus BETWEEN 0 AND 4),
    CONSTRAINT FundingPlatform_CK_Funders_Version CHECK (ContentVersion >= 1),
    CONSTRAINT FundingPlatform_CK_Funders_ArchiveActive
        CHECK ((PublicationStatus = 4 AND IsActive = 0)
               OR (PublicationStatus <> 4 AND IsActive = 1)),
    CONSTRAINT FundingPlatform_CK_Funders_PendingSubmitted
        CHECK (PublicationStatus <> 1 OR SubmittedAtUtc IS NOT NULL),
    CONSTRAINT FundingPlatform_CK_Funders_PublishedReview
        CHECK (PublicationStatus <> 2 OR
               (PublishedAtUtc IS NOT NULL AND ReviewedAtUtc IS NOT NULL
                AND RejectionReason IS NULL)),
    CONSTRAINT FundingPlatform_CK_Funders_RejectedReview
        CHECK (PublicationStatus <> 3 OR
               (ReviewedAtUtc IS NOT NULL
                AND NULLIF(LTRIM(RTRIM(RejectionReason)), N'') IS NOT NULL))
);

CREATE INDEX FundingPlatform_IX_Funders_Public
    ON dbo.FundingPlatform_Funders (PublicationStatus, IsActive, Name, Id)
    INCLUDE (PublicId, Slug, WebsiteUrl, CountryId, PublishedAtUtc)
    WHERE PublicationStatus = 2 AND IsActive = 1;

CREATE INDEX FundingPlatform_IX_Funders_ReviewQueue
    ON dbo.FundingPlatform_Funders (PublicationStatus, SubmittedAtUtc, Id)
    INCLUDE (PublicId, Slug, Name, ContentVersion, UpdatedAtUtc)
    WHERE PublicationStatus = 1 AND IsActive = 1;

CREATE TABLE dbo.FundingPlatform_FunderAliases
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    FunderId BIGINT NOT NULL,
    Alias NVARCHAR(300) NOT NULL,
    NormalizedAlias NVARCHAR(300) NOT NULL,
    IsPrimary BIT NOT NULL CONSTRAINT FundingPlatform_DF_FunderAliases_IsPrimary DEFAULT (0),
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_FunderAliases_IsActive DEFAULT (1),
    CreatedAtUtc DATETIME2(3) NOT NULL
        CONSTRAINT FundingPlatform_DF_FunderAliases_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_FunderAliases PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_FunderAliases_FunderAlias UNIQUE (FunderId, NormalizedAlias),
    CONSTRAINT FundingPlatform_FK_FunderAliases_Funder FOREIGN KEY (FunderId)
        REFERENCES dbo.FundingPlatform_Funders (Id) ON DELETE CASCADE
);

CREATE INDEX FundingPlatform_IX_FunderAliases_Normalized
    ON dbo.FundingPlatform_FunderAliases (NormalizedAlias, IsActive, FunderId);

CREATE UNIQUE INDEX FundingPlatform_UQ_FunderAliases_Primary
    ON dbo.FundingPlatform_FunderAliases (FunderId)
    WHERE IsPrimary = 1 AND IsActive = 1;

CREATE TABLE dbo.FundingPlatform_FunderVersions
(
    FunderId BIGINT NOT NULL,
    ContentVersion INT NOT NULL,
    SnapshotJson NVARCHAR(MAX) NOT NULL,
    ContentHash BINARY(32) NOT NULL,
    CreatedByUserId BIGINT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_FunderVersions PRIMARY KEY (FunderId, ContentVersion),
    CONSTRAINT FundingPlatform_FK_FunderVersions_Funder FOREIGN KEY (FunderId)
        REFERENCES dbo.FundingPlatform_Funders (Id),
    CONSTRAINT FundingPlatform_FK_FunderVersions_User FOREIGN KEY (CreatedByUserId)
        REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_FunderVersions_Version CHECK (ContentVersion >= 1),
    CONSTRAINT FundingPlatform_CK_FunderVersions_Json
        CHECK (ISJSON(SnapshotJson) = 1 AND LEFT(LTRIM(SnapshotJson), 1) = N'{')
);

CREATE TABLE dbo.FundingPlatform_FunderEditorialEvents
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    EventId UNIQUEIDENTIFIER NOT NULL,
    FunderId BIGINT NOT NULL,
    ContentVersion INT NOT NULL,
    FromStatus TINYINT NOT NULL,
    ToStatus TINYINT NOT NULL,
    ActionCode NVARCHAR(50) NOT NULL,
    ActorUserId BIGINT NOT NULL,
    Reason NVARCHAR(1000) NULL,
    IdempotencyKeyHash BINARY(32) NOT NULL,
    RequestHash BINARY(32) NOT NULL,
    ResultRowVersion BINARY(8) NOT NULL,
    ResultCompleteness DECIMAL(5,2) NULL,
    ResultSubmittedAtUtc DATETIME2(3) NULL,
    ResultPublishedAtUtc DATETIME2(3) NULL,
    ResultReviewedAtUtc DATETIME2(3) NULL,
    ResultReviewedByUserPublicId UNIQUEIDENTIFIER NULL,
    ResultRejectionReason NVARCHAR(1000) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_FunderEditorialEvents PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_FunderEditorialEvents_EventId UNIQUE (EventId),
    CONSTRAINT FundingPlatform_UQ_FunderEditorialEvents_FunderKey
        UNIQUE (FunderId, IdempotencyKeyHash),
    CONSTRAINT FundingPlatform_FK_FunderEditorialEvents_Funder
        FOREIGN KEY (FunderId) REFERENCES dbo.FundingPlatform_Funders (Id),
    CONSTRAINT FundingPlatform_FK_FunderEditorialEvents_Actor
        FOREIGN KEY (ActorUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_FunderEditorialEvents_Status
        CHECK (FromStatus BETWEEN 0 AND 4 AND ToStatus BETWEEN 0 AND 4),
    CONSTRAINT FundingPlatform_CK_FunderEditorialEvents_Version CHECK (ContentVersion >= 1)
    ,CONSTRAINT FundingPlatform_CK_FunderEditorialEvents_Completeness
        CHECK (ResultCompleteness IS NULL OR ResultCompleteness BETWEEN 0 AND 100)
);

CREATE INDEX FundingPlatform_IX_FunderEditorialEvents_FunderCreated
    ON dbo.FundingPlatform_FunderEditorialEvents (FunderId, CreatedAtUtc DESC, Id DESC)
    INCLUDE (EventId, ActionCode, FromStatus, ToStatus, ActorUserId, ContentVersion);

CREATE UNIQUE INDEX FundingPlatform_UQ_FunderEditorialEvents_ActorActionKey
    ON dbo.FundingPlatform_FunderEditorialEvents
       (ActorUserId, IdempotencyKeyHash)
    WHERE ActionCode = N'Create';

CREATE TABLE dbo.FundingPlatform_FundingOpportunityVersions
(
    FundingOpportunityId BIGINT NOT NULL,
    ContentVersion INT NOT NULL,
    SnapshotJson NVARCHAR(MAX) NOT NULL,
    ContentHash BINARY(32) NOT NULL,
    CreatedByUserId BIGINT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_FundingOpportunityVersions
        PRIMARY KEY (FundingOpportunityId, ContentVersion),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityVersions_Opportunity
        FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityVersions_User
        FOREIGN KEY (CreatedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_FundingOpportunityVersions_Version CHECK (ContentVersion >= 1),
    CONSTRAINT FundingPlatform_CK_FundingOpportunityVersions_Json
        CHECK (ISJSON(SnapshotJson) = 1 AND LEFT(LTRIM(SnapshotJson), 1) = N'{')
);

CREATE TABLE dbo.FundingPlatform_FundingFieldEvidence
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingFieldEvidence_PublicId DEFAULT (NEWSEQUENTIALID()),
    FundingOpportunityId BIGINT NOT NULL,
    FieldPath NVARCHAR(200) NOT NULL,
    ValueJson NVARCHAR(MAX) NOT NULL,
    FundingOpportunitySourceLinkId BIGINT NULL,
    ExtractionMethod TINYINT NOT NULL,
    EvidenceText NVARCHAR(2000) NULL,
    SourceLocator NVARCHAR(500) NULL,
    Confidence DECIMAL(5,2) NULL,
    IsSelected BIT NOT NULL CONSTRAINT FundingPlatform_DF_FundingFieldEvidence_Selected DEFAULT (1),
    IsManualLock BIT NOT NULL CONSTRAINT FundingPlatform_DF_FundingFieldEvidence_ManualLock DEFAULT (0),
    CreatedByUserId BIGINT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_FundingFieldEvidence PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_FundingFieldEvidence_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_FundingFieldEvidence_OpportunityId UNIQUE (FundingOpportunityId, Id),
    CONSTRAINT FundingPlatform_FK_FundingFieldEvidence_Opportunity
        FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id),
    CONSTRAINT FundingPlatform_FK_FundingFieldEvidence_SourceLink
        FOREIGN KEY (FundingOpportunitySourceLinkId, FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunitySourceLinks (Id, FundingOpportunityId),
    CONSTRAINT FundingPlatform_FK_FundingFieldEvidence_User
        FOREIGN KEY (CreatedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_FundingFieldEvidence_Path
        CHECK (LEFT(FieldPath, 1) = N'/' AND LEN(FieldPath) >= 2),
    CONSTRAINT FundingPlatform_CK_FundingFieldEvidence_ValueJson
        CHECK (ISJSON(ValueJson) = 1 AND LEFT(LTRIM(ValueJson), 1) = N'{'),
    CONSTRAINT FundingPlatform_CK_FundingFieldEvidence_Method CHECK (ExtractionMethod BETWEEN 1 AND 4),
    CONSTRAINT FundingPlatform_CK_FundingFieldEvidence_Confidence
        CHECK (Confidence IS NULL OR Confidence BETWEEN 0 AND 100)
);

CREATE UNIQUE INDEX FundingPlatform_UQ_FundingFieldEvidence_Selected
    ON dbo.FundingPlatform_FundingFieldEvidence (FundingOpportunityId, FieldPath)
    WHERE IsSelected = 1;

CREATE INDEX FundingPlatform_IX_FundingFieldEvidence_SourceLink
    ON dbo.FundingPlatform_FundingFieldEvidence (FundingOpportunitySourceLinkId, FundingOpportunityId)
    WHERE FundingOpportunitySourceLinkId IS NOT NULL;

CREATE TABLE dbo.FundingPlatform_FundingOpportunityFunders
(
    FundingOpportunityId BIGINT NOT NULL,
    FunderId BIGINT NOT NULL,
    Role TINYINT NOT NULL,
    EvidenceId BIGINT NULL,
    IsActive BIT NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingOpportunityFunders_IsActive DEFAULT (1),
    CreatedAtUtc DATETIME2(3) NOT NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_FundingOpportunityFunders
        PRIMARY KEY (FundingOpportunityId, FunderId),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityFunders_Opportunity
        FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityFunders_Funder
        FOREIGN KEY (FunderId) REFERENCES dbo.FundingPlatform_Funders (Id),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityFunders_Evidence
        FOREIGN KEY (FundingOpportunityId, EvidenceId)
        REFERENCES dbo.FundingPlatform_FundingFieldEvidence (FundingOpportunityId, Id),
    CONSTRAINT FundingPlatform_CK_FundingOpportunityFunders_Role CHECK (Role BETWEEN 1 AND 3)
);

CREATE UNIQUE INDEX FundingPlatform_UQ_FundingOpportunityFunders_Primary
    ON dbo.FundingPlatform_FundingOpportunityFunders (FundingOpportunityId)
    WHERE Role = 1 AND IsActive = 1;

CREATE INDEX FundingPlatform_IX_FundingOpportunityFunders_Funder
    ON dbo.FundingPlatform_FundingOpportunityFunders
       (FunderId, IsActive, Role, FundingOpportunityId);

CREATE TABLE dbo.FundingPlatform_FundingOpportunityEditorialEvents
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    EventId UNIQUEIDENTIFIER NOT NULL,
    FundingOpportunityId BIGINT NOT NULL,
    ContentVersion INT NOT NULL,
    FromStatus TINYINT NOT NULL,
    ToStatus TINYINT NOT NULL,
    ActionCode NVARCHAR(50) NOT NULL,
    ActorUserId BIGINT NULL,
    Reason NVARCHAR(1000) NULL,
    IdempotencyKeyHash BINARY(32) NOT NULL,
    RequestHash BINARY(32) NOT NULL,
    ResultRowVersion BINARY(8) NOT NULL,
    ResultCompleteness DECIMAL(5,2) NULL,
    ResultSubmittedAtUtc DATETIME2(3) NULL,
    ResultPublishedAtUtc DATETIME2(3) NULL,
    ResultReviewedAtUtc DATETIME2(3) NULL,
    ResultReviewedByUserPublicId UNIQUEIDENTIFIER NULL,
    ResultRejectionReason NVARCHAR(1000) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_FundingOpportunityEditorialEvents PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_FundingOpportunityEditorialEvents_EventId UNIQUE (EventId),
    CONSTRAINT FundingPlatform_UQ_FundingOpportunityEditorialEvents_OpportunityKey
        UNIQUE (FundingOpportunityId, IdempotencyKeyHash),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityEditorialEvents_Opportunity
        FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityEditorialEvents_Actor
        FOREIGN KEY (ActorUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_FundingOpportunityEditorialEvents_Status
        CHECK (FromStatus BETWEEN 0 AND 4 AND ToStatus BETWEEN 0 AND 4),
    CONSTRAINT FundingPlatform_CK_FundingOpportunityEditorialEvents_Version
        CHECK (ContentVersion >= 1)
    ,CONSTRAINT FundingPlatform_CK_FundingOpportunityEditorialEvents_Completeness
        CHECK (ResultCompleteness IS NULL OR ResultCompleteness BETWEEN 0 AND 100)
);

CREATE INDEX FundingPlatform_IX_FundingOpportunityEditorialEvents_Created
    ON dbo.FundingPlatform_FundingOpportunityEditorialEvents
       (FundingOpportunityId, CreatedAtUtc DESC, Id DESC)
    INCLUDE (EventId, ActionCode, FromStatus, ToStatus, ActorUserId, ContentVersion);

CREATE UNIQUE INDEX FundingPlatform_UQ_FundingOpportunityEditorialEvents_ActorActionKey
    ON dbo.FundingPlatform_FundingOpportunityEditorialEvents
       (ActorUserId, IdempotencyKeyHash)
    WHERE ActionCode = N'Create' AND ActorUserId IS NOT NULL;

CREATE TABLE dbo.FundingPlatform_FundingOpportunityStagedRevisions
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingOpportunityStagedRevisions_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    FundingSourceId INT NOT NULL,
    FundingOpportunityId BIGINT NOT NULL,
    ExternalId NVARCHAR(250) NULL,
    SourceItemKeyHash BINARY(32) NOT NULL,
    SourceUrl NVARCHAR(2048) NULL,
    CanonicalUrlHash BINARY(32) NULL,
    SnapshotJson NVARCHAR(MAX) NOT NULL,
    ContentHash BINARY(32) NOT NULL,
    CandidateStatus TINYINT NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingOpportunityStagedRevisions_Status DEFAULT (0),
    FirstObservedAtUtc DATETIME2(3) NOT NULL,
    LastObservedAtUtc DATETIME2(3) NOT NULL,
    SeenCount INT NOT NULL
        CONSTRAINT FundingPlatform_DF_FundingOpportunityStagedRevisions_SeenCount DEFAULT (1),
    ReviewedByUserId BIGINT NULL,
    ReviewedAtUtc DATETIME2(3) NULL,
    ReviewReason NVARCHAR(1000) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_FundingOpportunityStagedRevisions PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_FundingOpportunityStagedRevisions_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityStagedRevisions_Source
        FOREIGN KEY (FundingSourceId) REFERENCES dbo.FundingPlatform_FundingSources (Id),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityStagedRevisions_Opportunity
        FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityStagedRevisions_Reviewer
        FOREIGN KEY (ReviewedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_FundingOpportunityStagedRevisions_Json
        CHECK (ISJSON(SnapshotJson) = 1 AND LEFT(LTRIM(SnapshotJson), 1) = N'{'),
    CONSTRAINT FundingPlatform_CK_FundingOpportunityStagedRevisions_Status
        CHECK (CandidateStatus BETWEEN 0 AND 3),
    CONSTRAINT FundingPlatform_CK_FundingOpportunityStagedRevisions_SeenCount
        CHECK (SeenCount >= 1),
    CONSTRAINT FundingPlatform_CK_FundingOpportunityStagedRevisions_Dates
        CHECK (FirstObservedAtUtc <= LastObservedAtUtc)
);

CREATE INDEX FundingPlatform_IX_FundingOpportunityStagedRevisions_Review
    ON dbo.FundingPlatform_FundingOpportunityStagedRevisions
       (CandidateStatus, LastObservedAtUtc, Id)
    INCLUDE (PublicId, FundingSourceId, FundingOpportunityId, ExternalId, SeenCount);

CREATE UNIQUE INDEX FundingPlatform_UQ_FundingOpportunityStagedRevisions_PendingSourceHash
    ON dbo.FundingPlatform_FundingOpportunityStagedRevisions
       (FundingSourceId, SourceItemKeyHash, ContentHash)
    WHERE CandidateStatus = 0;

GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_fn_AdminAccessState
(
    @UserPublicId UNIQUEIDENTIFIER
)
RETURNS TINYINT
AS
BEGIN
    DECLARE @State TINYINT = 0;

    SELECT @State = CASE WHEN users.TwoFactorEnabled = 1 THEN 2 ELSE 1 END
    FROM dbo.FundingPlatform_Users AS users
    WHERE users.PublicId = @UserPublicId
      AND users.Status = 2
      AND EXISTS
      (
          SELECT 1
          FROM dbo.FundingPlatform_UserRoles AS userRoles
          INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
          WHERE userRoles.UserId = users.Id
            AND roles.NormalizedName IN (N'ADMIN', N'SUPERADMIN')
      );

    RETURN @State;
END;
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs()
RETURNS TABLE
AS
RETURN
(
    SELECT opportunities.Id AS FundingOpportunityId
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    WHERE (opportunities.Currency IS NULL OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_Currencies AS currencies
           WHERE currencies.Code = opportunities.Currency AND currencies.IsActive = 1))
      AND (opportunities.FundingTypeId IS NULL OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingTypes AS fundingTypes
           WHERE fundingTypes.Id = opportunities.FundingTypeId AND fundingTypes.IsActive = 1))
      AND (opportunities.IssuerCountryId IS NULL OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_Countries AS issuerCountries
           WHERE issuerCountries.Id = opportunities.IssuerCountryId
             AND issuerCountries.IsActive = 1))
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityCountries AS links
           LEFT JOIN dbo.FundingPlatform_Countries AS countries
               ON countries.Id = links.CountryId AND countries.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id AND countries.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityRegions AS links
           LEFT JOIN dbo.FundingPlatform_Regions AS regions
               ON regions.Id = links.RegionId AND regions.IsActive = 1
           LEFT JOIN dbo.FundingPlatform_Countries AS countries
               ON countries.Id = regions.CountryId AND countries.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id
             AND (regions.Id IS NULL OR countries.Id IS NULL))
      AND EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityCategories AS links
           INNER JOIN dbo.FundingPlatform_FundingCategories AS categories
               ON categories.Id = links.FundingCategoryId AND categories.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityCategories AS links
           LEFT JOIN dbo.FundingPlatform_FundingCategories AS categories
               ON categories.Id = links.FundingCategoryId AND categories.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id AND categories.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes AS links
           LEFT JOIN dbo.FundingPlatform_BeneficiaryTypes AS beneficiaryTypes
               ON beneficiaryTypes.Id = links.BeneficiaryTypeId AND beneficiaryTypes.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id AND beneficiaryTypes.Id IS NULL)
      AND NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityProjectTypes AS links
           LEFT JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
               ON projectTypes.Id = links.ProjectTypeId AND projectTypes.IsActive = 1
           WHERE links.FundingOpportunityId = opportunities.Id AND projectTypes.Id IS NULL)
      AND
          ((opportunities.GeographicScope = 1 AND EXISTS
              (SELECT 1
               FROM dbo.FundingPlatform_FundingOpportunityCountries AS links
               INNER JOIN dbo.FundingPlatform_Countries AS countries
                   ON countries.Id = links.CountryId AND countries.IsActive = 1
               WHERE links.FundingOpportunityId = opportunities.Id))
           OR (opportunities.GeographicScope = 2
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS links
                    WHERE links.FundingOpportunityId = opportunities.Id)
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions AS links
                    WHERE links.FundingOpportunityId = opportunities.Id)))
);
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Catalogs_GetForOrganizationProfile
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Iso2 AS Code, Name
    FROM dbo.FundingPlatform_Countries
    WHERE IsActive = 1 ORDER BY Name, Id;

    SELECT Id, CountryId, Code, Name
    FROM dbo.FundingPlatform_Regions
    WHERE IsActive = 1 ORDER BY CountryId, Name, Id;

    SELECT Code, Name, MinorUnits
    FROM dbo.FundingPlatform_Currencies
    WHERE IsActive = 1 ORDER BY Code;

    SELECT Id, Code, Name
    FROM dbo.FundingPlatform_FundingCategories
    WHERE IsActive = 1 ORDER BY Name, Id;

    SELECT Id, Code, Name
    FROM dbo.FundingPlatform_FundingTypes
    WHERE IsActive = 1 ORDER BY Name, Id;

    SELECT Id, Code, Name
    FROM dbo.FundingPlatform_OrganizationTypes
    WHERE IsActive = 1 ORDER BY Name, Id;

    SELECT Id, CountryId, Code, Name
    FROM dbo.FundingPlatform_LegalEntityTypes
    WHERE IsActive = 1 ORDER BY CountryId, Name, Id;

    SELECT Id, Code, Name
    FROM dbo.FundingPlatform_OrganizationSizes
    WHERE IsActive = 1 ORDER BY Id;

    SELECT Id, Code, Name
    FROM dbo.FundingPlatform_BeneficiaryTypes
    WHERE IsActive = 1 ORDER BY Name, Id;

    SELECT Id, Code, Name
    FROM dbo.FundingPlatform_ProjectTypes
    WHERE IsActive = 1 ORDER BY Name, Id;

    SELECT Id, NormalizedName AS Code, Name
    FROM dbo.FundingPlatform_Tags
    WHERE IsActive = 1 AND IsApproved = 1 ORDER BY Name, Id;

    SELECT Id, IsoCode AS Code, Name
    FROM dbo.FundingPlatform_Languages
    WHERE IsActive = 1 ORDER BY Name, Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_RefreshToken_Create
    @UserId BIGINT,
    @SecurityVersion INT,
    @MfaAuthenticated BIT,
    @MfaAuthenticatedAtUtc DATETIME2(3) = NULL,
    @FamilyId UNIQUEIDENTIFIER,
    @TokenHash BINARY(32),
    @JwtId UNIQUEIDENTIFIER,
    @ExpiresAtUtc DATETIME2(3),
    @CreatedAtUtc DATETIME2(3),
    @CreatedIpHash BINARY(32) = NULL,
    @UserAgent NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @UserId IS NULL OR @SecurityVersion IS NULL OR @SecurityVersion < 1
       OR @MfaAuthenticated IS NULL OR @CreatedAtUtc IS NULL OR @ExpiresAtUtc IS NULL
       OR @FamilyId IS NULL
       OR @TokenHash IS NULL OR @JwtId IS NULL
       OR @ExpiresAtUtc <= @CreatedAtUtc
       OR (@MfaAuthenticated = 0 AND @MfaAuthenticatedAtUtc IS NOT NULL)
       OR (@MfaAuthenticated = 1 AND
           (@MfaAuthenticatedAtUtc IS NULL OR @MfaAuthenticatedAtUtc > @CreatedAtUtc))
        THROW 51612, N'Refresh-token session metadata is invalid.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_RefreshCreate;

    BEGIN TRY
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
            WHERE Id = @UserId AND SecurityVersion = @SecurityVersion
              AND Status = 2 AND EmailConfirmed = 1
        )
            THROW 51613, N'User security state does not allow a refresh session.', 1;

        INSERT INTO dbo.FundingPlatform_RefreshTokens
        (
            UserId, SecurityVersion, MfaAuthenticated, MfaAuthenticatedAtUtc,
            FamilyId, TokenHash, JwtId, ExpiresAtUtc, CreatedAtUtc,
            CreatedIpHash, UserAgent
        )
        VALUES
        (
            @UserId, @SecurityVersion, @MfaAuthenticated, @MfaAuthenticatedAtUtc,
            @FamilyId, @TokenHash, @JwtId, @ExpiresAtUtc, @CreatedAtUtc,
            @CreatedIpHash, @UserAgent
        );

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_RefreshCreate;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_RefreshToken_Rotate
    @CurrentTokenHash BINARY(32),
    @ReplacementTokenHash BINARY(32),
    @ReplacementJwtId UNIQUEIDENTIFIER,
    @ReplacementExpiresAtUtc DATETIME2(3),
    @CreatedIpHash BINARY(32) = NULL,
    @UserAgent NVARCHAR(300) = NULL,
    @NowUtc DATETIME2(3),
    @GraceUntilUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartedTransaction BIT = 0;
    DECLARE @TokenId BIGINT;
    DECLARE @UserId BIGINT;
    DECLARE @SecurityVersion INT;
    DECLARE @FamilyId UNIQUEIDENTIFIER;
    DECLARE @StoredMfaAuthenticated BIT;
    DECLARE @StoredMfaAuthenticatedAtUtc DATETIME2(3);
    DECLARE @ExpiresAtUtc DATETIME2(3);
    DECLARE @RevokedAtUtc DATETIME2(3);
    DECLARE @ReplacedByTokenId BIGINT;
    DECLARE @RotationGraceUntilUtc DATETIME2(3);
    DECLARE @RevocationReason TINYINT;
    DECLARE @ReplacementTokenId BIGINT;

    IF @@TRANCOUNT = 0
    BEGIN
        BEGIN TRANSACTION;
        SET @StartedTransaction = 1;
    END
    ELSE
        SAVE TRANSACTION FundingPlatform_RotateRefresh;

    BEGIN TRY
        SELECT
            @TokenId = Id,
            @UserId = UserId,
            @SecurityVersion = SecurityVersion,
            @StoredMfaAuthenticated = MfaAuthenticated,
            @StoredMfaAuthenticatedAtUtc = MfaAuthenticatedAtUtc,
            @FamilyId = FamilyId,
            @ExpiresAtUtc = ExpiresAtUtc,
            @RevokedAtUtc = RevokedAtUtc,
            @ReplacedByTokenId = ReplacedByTokenId,
            @RotationGraceUntilUtc = RotationGraceUntilUtc,
            @RevocationReason = RevocationReason
        FROM dbo.FundingPlatform_RefreshTokens WITH (UPDLOCK, HOLDLOCK)
        WHERE TokenHash = @CurrentTokenHash;

        IF @TokenId IS NULL
        BEGIN
            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 1) AS ResultCode;
            RETURN;
        END;

        IF @RevokedAtUtc IS NOT NULL
        BEGIN
            IF @RevocationReason = 0
               AND @ReplacedByTokenId IS NOT NULL
               AND @RotationGraceUntilUtc >= @NowUtc
            BEGIN
                IF @StartedTransaction = 1 COMMIT TRANSACTION;
                SELECT CONVERT(TINYINT, 5) AS ResultCode;
                RETURN;
            END;

            UPDATE dbo.FundingPlatform_RefreshTokens
            SET RevokedAtUtc = COALESCE(RevokedAtUtc, @NowUtc),
                RevocationReason = CASE WHEN RevokedAtUtc IS NULL THEN 2 ELSE RevocationReason END
            WHERE UserId = @UserId
              AND FamilyId = @FamilyId
              AND RevokedAtUtc IS NULL;

            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 3) AS ResultCode;
            RETURN;
        END;

        IF @ExpiresAtUtc <= @NowUtc
        BEGIN
            UPDATE dbo.FundingPlatform_RefreshTokens
            SET RevokedAtUtc = @NowUtc,
                RevocationReason = 5
            WHERE Id = @TokenId;

            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 2) AS ResultCode;
            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
            WHERE Id = @UserId
              AND SecurityVersion = @SecurityVersion
              AND Status = 2
              AND EmailConfirmed = 1
        )
        BEGIN
            UPDATE dbo.FundingPlatform_RefreshTokens
            SET RevokedAtUtc = @NowUtc,
                RevocationReason = 3
            WHERE UserId = @UserId
              AND FamilyId = @FamilyId
              AND RevokedAtUtc IS NULL;

            IF @StartedTransaction = 1 COMMIT TRANSACTION;
            SELECT CONVERT(TINYINT, 4) AS ResultCode;
            RETURN;
        END;

        INSERT INTO dbo.FundingPlatform_RefreshTokens
        (
            UserId, SecurityVersion, MfaAuthenticated, MfaAuthenticatedAtUtc,
            FamilyId, TokenHash, JwtId, ExpiresAtUtc, CreatedAtUtc,
            CreatedIpHash, UserAgent
        )
        VALUES
        (
            @UserId, @SecurityVersion, @StoredMfaAuthenticated, @StoredMfaAuthenticatedAtUtc,
            @FamilyId, @ReplacementTokenHash, @ReplacementJwtId,
            @ReplacementExpiresAtUtc, @NowUtc, @CreatedIpHash, @UserAgent
        );

        SET @ReplacementTokenId = CONVERT(BIGINT, SCOPE_IDENTITY());

        UPDATE dbo.FundingPlatform_RefreshTokens
        SET RevokedAtUtc = @NowUtc,
            ReplacedByTokenId = @ReplacementTokenId,
            RotationGraceUntilUtc = @GraceUntilUtc,
            RevocationReason = 0
        WHERE Id = @TokenId;

        IF @StartedTransaction = 1 COMMIT TRANSACTION;

        SELECT
            CONVERT(TINYINT, 0) AS ResultCode,
            users.Id AS UserId,
            users.PublicId,
            users.Email,
            users.DisplayName,
            users.SecurityVersion,
            users.TwoFactorEnabled,
            @StoredMfaAuthenticated AS MfaAuthenticated,
            @StoredMfaAuthenticatedAtUtc AS MfaAuthenticatedAtUtc,
            @FamilyId AS FamilyId
        FROM dbo.FundingPlatform_Users AS users
        WHERE users.Id = @UserId;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            IF @StartedTransaction = 1 ROLLBACK TRANSACTION;
            ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FundingPlatform_RotateRefresh;
        END;
        THROW;
    END CATCH;
END;
GO

INSERT INTO dbo.FundingPlatform_FundingSources
(
    Name, ProviderType, BaseUrl, IsEnabled, ScheduleCron, MinimumDelaySeconds,
    UserAgent, TermsUrl, TermsReviewedAtUtc, RobotsReviewedAtUtc,
    LastSuccessfulRunAtUtc, ConfigurationJson, SecretReference,
    CreatedAtUtc, UpdatedAtUtc
)
SELECT N'Manual editorial', 0, NULL, 1, NULL, NULL,
       NULL, NULL, NULL, NULL, NULL,
       N'{"providerCode":"manual-editorial","mode":"admin"}', NULL,
       SYSUTCDATETIME(), SYSUTCDATETIME()
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_FundingSources
    WHERE Name = N'Manual editorial'
);

UPDATE dbo.FundingPlatform_FundingSources
SET ProviderType = 0,
    BaseUrl = NULL,
    IsEnabled = 1,
    ScheduleCron = NULL,
    MinimumDelaySeconds = NULL,
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE Name = N'Manual editorial'
  AND (ProviderType <> 0 OR BaseUrl IS NOT NULL OR IsEnabled <> 1
       OR ScheduleCron IS NOT NULL OR MinimumDelaySeconds IS NOT NULL);

/* Preserve the legacy public catalog without inventing a human reviewer. */
;WITH Sponsors AS
(
    SELECT UPPER(LTRIM(RTRIM(opportunities.SponsorName))) AS NormalizedName,
           MIN(LTRIM(RTRIM(opportunities.SponsorName))) AS Name,
           MIN(opportunities.SponsorUrl) AS WebsiteUrl,
           MAX(CASE WHEN opportunities.PublicationStatus = 2 AND opportunities.IsActive = 1
                    THEN 1 ELSE 0 END) AS HasPublishedOpportunity,
           MIN(COALESCE(opportunities.PublishedAtUtc,
                        opportunities.UpdatedAtUtc,
                        opportunities.CreatedAtUtc)) AS FirstKnownAtUtc
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    WHERE NULLIF(LTRIM(RTRIM(opportunities.SponsorName)), N'') IS NOT NULL
    GROUP BY UPPER(LTRIM(RTRIM(opportunities.SponsorName)))
)
INSERT INTO dbo.FundingPlatform_Funders
(
    Slug, Name, NormalizedName, WebsiteUrl, PublicationStatus,
    PublishedAtUtc, ReviewedAtUtc, ContentVersion, IsActive, CreatedAtUtc, UpdatedAtUtc
)
SELECT N'legacy-' + LOWER(CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', sponsors.NormalizedName), 2)),
       sponsors.Name,
       sponsors.NormalizedName,
       sponsors.WebsiteUrl,
       CASE WHEN sponsors.HasPublishedOpportunity = 1 THEN 2 ELSE 0 END,
       CASE WHEN sponsors.HasPublishedOpportunity = 1 THEN sponsors.FirstKnownAtUtc ELSE NULL END,
       CASE WHEN sponsors.HasPublishedOpportunity = 1 THEN sponsors.FirstKnownAtUtc ELSE NULL END,
       1,
       1,
       sponsors.FirstKnownAtUtc,
       sponsors.FirstKnownAtUtc
FROM Sponsors AS sponsors
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_Funders AS existing
    WHERE existing.NormalizedName = sponsors.NormalizedName
);

INSERT INTO dbo.FundingPlatform_FunderAliases
    (FunderId, Alias, NormalizedAlias, IsPrimary, IsActive, CreatedAtUtc)
SELECT funders.Id, funders.Name, funders.NormalizedName, 1, 1, funders.CreatedAtUtc
FROM dbo.FundingPlatform_Funders AS funders
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_FunderAliases AS aliases
    WHERE aliases.FunderId = funders.Id AND aliases.NormalizedAlias = funders.NormalizedName
);

INSERT INTO dbo.FundingPlatform_FunderVersions
    (FunderId, ContentVersion, SnapshotJson, ContentHash, CreatedByUserId, CreatedAtUtc)
SELECT funders.Id,
       funders.ContentVersion,
       snapshots.SnapshotJson,
       HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), snapshots.SnapshotJson)),
       NULL,
       funders.CreatedAtUtc
FROM dbo.FundingPlatform_Funders AS funders
CROSS APPLY
(
    SELECT
    (
        SELECT funders.Slug AS slug,
               funders.Name AS name,
               funders.Description AS description,
               funders.WebsiteUrl AS websiteUrl,
               funders.CountryId AS countryId,
               JSON_QUERY(COALESCE
               (
                   (SELECT aliases.Alias AS alias, aliases.IsPrimary AS isPrimary
                    FROM dbo.FundingPlatform_FunderAliases AS aliases
                    WHERE aliases.FunderId = funders.Id AND aliases.IsActive = 1
                    ORDER BY aliases.IsPrimary DESC, aliases.Id
                    FOR JSON PATH), N'[]'
               )) AS aliases
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    ) AS SnapshotJson
) AS snapshots
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_FunderVersions AS versions
    WHERE versions.FunderId = funders.Id AND versions.ContentVersion = funders.ContentVersion
);

INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
(
    FundingOpportunityId, FieldPath, ValueJson, FundingOpportunitySourceLinkId,
    ExtractionMethod, EvidenceText, SourceLocator, Confidence,
    IsSelected, IsManualLock, CreatedByUserId, CreatedAtUtc
)
SELECT opportunities.Id,
       N'/sponsorName',
       (SELECT opportunities.SponsorName AS [value], N'known' AS [status]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
       sourceLinks.Id,
       2,
       LEFT(opportunities.SponsorName, 2000),
       CASE WHEN sourceLinks.Id IS NULL THEN N'legacy-canonical-row' ELSE N'source-link' END,
       NULL,
       1,
       0,
       NULL,
       opportunities.CreatedAtUtc
FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
OUTER APPLY
(
    SELECT TOP (1) links.Id
    FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
    WHERE links.FundingOpportunityId = opportunities.Id AND links.IsActive = 1
    ORDER BY links.IsPrimary DESC, links.Id
) AS sourceLinks
WHERE NULLIF(LTRIM(RTRIM(opportunities.SponsorName)), N'') IS NOT NULL
  AND NOT EXISTS
  (
      SELECT 1
      FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
      WHERE evidence.FundingOpportunityId = opportunities.Id
        AND evidence.FieldPath = N'/sponsorName'
        AND evidence.IsSelected = 1
  );

INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
(
    FundingOpportunityId, FieldPath, ValueJson, FundingOpportunitySourceLinkId,
    ExtractionMethod, EvidenceText, SourceLocator, Confidence,
    IsSelected, IsManualLock, CreatedByUserId, CreatedAtUtc
)
SELECT opportunities.Id,
       critical.FieldPath,
       (SELECT critical.ValueText AS [value], critical.StatusCode AS [status]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
       sourceLinks.Id,
       2,
       LEFT(critical.ValueText, 2000),
       CASE WHEN sourceLinks.Id IS NULL THEN N'legacy-canonical-row' ELSE N'source-link' END,
       NULL,
       1,
       0,
       NULL,
       opportunities.CreatedAtUtc
FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
OUTER APPLY
(
    SELECT TOP (1) links.Id
    FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
    WHERE links.FundingOpportunityId = opportunities.Id AND links.IsActive = 1
    ORDER BY links.IsPrimary DESC, links.Id
) AS sourceLinks
CROSS APPLY
(
    VALUES
        (N'/title', CONVERT(NVARCHAR(MAX), opportunities.Title), N'known'),
        (N'/description', opportunities.Description,
         CASE WHEN NULLIF(LTRIM(RTRIM(opportunities.Description)), N'') IS NULL
              THEN N'unknown' ELSE N'known' END),
        (N'/eligibilityDescription', opportunities.EligibilityDescription,
         CASE WHEN NULLIF(LTRIM(RTRIM(opportunities.EligibilityDescription)), N'') IS NULL
              THEN N'unknown' ELSE N'known' END),
        (N'/closeDate', CONVERT(NVARCHAR(MAX), CONVERT(NVARCHAR(30), opportunities.CloseDate, 23)),
         CASE WHEN opportunities.CloseDate IS NULL THEN N'unknown' ELSE N'known' END)
) AS critical(FieldPath, ValueText, StatusCode)
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
    WHERE evidence.FundingOpportunityId = opportunities.Id
      AND evidence.FieldPath = critical.FieldPath
      AND evidence.IsSelected = 1
);

INSERT INTO dbo.FundingPlatform_FundingOpportunityFunders
    (FundingOpportunityId, FunderId, Role, EvidenceId, IsActive, CreatedAtUtc, UpdatedAtUtc)
SELECT opportunities.Id,
       funders.Id,
       1,
       evidence.Id,
       1,
       opportunities.CreatedAtUtc,
       opportunities.UpdatedAtUtc
FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
INNER JOIN dbo.FundingPlatform_Funders AS funders
    ON funders.NormalizedName = UPPER(LTRIM(RTRIM(opportunities.SponsorName)))
LEFT JOIN dbo.FundingPlatform_FundingFieldEvidence AS evidence
    ON evidence.FundingOpportunityId = opportunities.Id
   AND evidence.FieldPath = N'/sponsorName'
   AND evidence.IsSelected = 1
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
    WHERE links.FundingOpportunityId = opportunities.Id
      AND links.Role = 1 AND links.IsActive = 1
);

INSERT INTO dbo.FundingPlatform_FundingOpportunityVersions
    (FundingOpportunityId, ContentVersion, SnapshotJson, ContentHash, CreatedByUserId, CreatedAtUtc)
SELECT opportunities.Id,
       opportunities.ContentVersion,
       snapshots.SnapshotJson,
       HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), snapshots.SnapshotJson)),
       opportunities.CreatedByUserId,
       opportunities.CreatedAtUtc
FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
CROSS APPLY
(
    SELECT
    (
        SELECT opportunities.Slug AS slug,
               opportunities.Title AS title,
               opportunities.Description AS description,
               opportunities.Summary AS summary,
               opportunities.SponsorName AS sponsorName,
               opportunities.SponsorUrl AS sponsorUrl,
               opportunities.ApplicationUrl AS applicationUrl,
               opportunities.IssuerCountryId AS issuerCountryId,
               opportunities.FundingTypeId AS fundingTypeId,
               opportunities.Currency AS currency,
               opportunities.MinAmount AS minAmount,
               opportunities.MaxAmount AS maxAmount,
               opportunities.AmountStatus AS amountStatus,
               opportunities.OpenDate AS openDate,
               opportunities.CloseDate AS closeDate,
               opportunities.CloseAtUtc AS closeAtUtc,
               opportunities.DeadlineTimeZoneId AS deadlineTimeZoneId,
               opportunities.DeadlineType AS deadlineType,
               opportunities.DeadlinePrecision AS deadlinePrecision,
               opportunities.EligibilityDescription AS eligibilityDescription,
               opportunities.Requirements AS requirements,
               opportunities.Objectives AS objectives,
               opportunities.AllowedActivities AS allowedActivities,
               opportunities.ExcludedActivities AS excludedActivities,
               opportunities.Restrictions AS restrictions,
               opportunities.TargetOrganizationsDescription AS targetOrganizationsDescription,
               opportunities.TargetPopulationsDescription AS targetPopulationsDescription,
               opportunities.MinimumOperatingYears AS minimumOperatingYears,
               opportunities.RequiresLegalEntity AS requiresLegalEntity,
               opportunities.RequiresPriorExperience AS requiresPriorExperience,
               opportunities.RequiresCofunding AS requiresCofunding,
               opportunities.CofundingPercentage AS cofundingPercentage,
               opportunities.GeographicScope AS geographicScope,
               opportunities.RemoteApplication AS remoteApplication,
               opportunities.DataQualityScore AS dataQualityScore,
               JSON_QUERY(COALESCE
               (
                   (SELECT countries.CountryId AS id
                    FROM dbo.FundingPlatform_FundingOpportunityCountries AS countries
                    WHERE countries.FundingOpportunityId = opportunities.Id
                    ORDER BY countries.CountryId FOR JSON PATH), N'[]'
               )) AS countryIds,
               JSON_QUERY(COALESCE
               (
                   (SELECT regions.RegionId AS id
                    FROM dbo.FundingPlatform_FundingOpportunityRegions AS regions
                    WHERE regions.FundingOpportunityId = opportunities.Id
                    ORDER BY regions.RegionId FOR JSON PATH), N'[]'
               )) AS regionIds,
               JSON_QUERY(COALESCE
               (
                   (SELECT categories.FundingCategoryId AS id
                    FROM dbo.FundingPlatform_FundingOpportunityCategories AS categories
                    WHERE categories.FundingOpportunityId = opportunities.Id
                    ORDER BY categories.FundingCategoryId FOR JSON PATH), N'[]'
               )) AS categoryIds,
               JSON_QUERY(COALESCE
               (
                   (SELECT beneficiaries.BeneficiaryTypeId AS id
                    FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes AS beneficiaries
                    WHERE beneficiaries.FundingOpportunityId = opportunities.Id
                    ORDER BY beneficiaries.BeneficiaryTypeId FOR JSON PATH), N'[]'
               )) AS beneficiaryTypeIds,
               JSON_QUERY(COALESCE
               (
                   (SELECT projectTypes.ProjectTypeId AS id
                    FROM dbo.FundingPlatform_FundingOpportunityProjectTypes AS projectTypes
                    WHERE projectTypes.FundingOpportunityId = opportunities.Id
                    ORDER BY projectTypes.ProjectTypeId FOR JSON PATH), N'[]'
               )) AS projectTypeIds,
               JSON_QUERY(COALESCE
               (
                   (SELECT funders.PublicId AS funderPublicId, links.Role AS role
                    FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
                    INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
                    WHERE links.FundingOpportunityId = opportunities.Id AND links.IsActive = 1
                    ORDER BY links.Role, funders.Id FOR JSON PATH), N'[]'
               )) AS funders
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    ) AS SnapshotJson
) AS snapshots
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_FundingOpportunityVersions AS versions
    WHERE versions.FundingOpportunityId = opportunities.Id
      AND versions.ContentVersion = opportunities.ContentVersion
);

GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AdminActor_Lock
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @ActorUserId BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @MfaEnabled BIT;
    SET @ActorUserId = NULL;

    SELECT @ActorUserId = users.Id, @MfaEnabled = users.TwoFactorEnabled
    FROM dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
    WHERE users.PublicId = @AdminUserPublicId AND users.Status = 2
      AND EXISTS
      (
          SELECT 1
          FROM dbo.FundingPlatform_UserRoles AS userRoles WITH (UPDLOCK, HOLDLOCK)
          INNER JOIN dbo.FundingPlatform_Roles AS roles WITH (UPDLOCK, HOLDLOCK)
              ON roles.Id = userRoles.RoleId
          WHERE userRoles.UserId = users.Id
            AND roles.NormalizedName IN (N'ADMIN', N'SUPERADMIN')
      );

    IF @ActorUserId IS NULL
        THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @MfaEnabled <> 1
        THROW 51602, N'MFA is required for this administrative operation.', 1;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingSource_AdminList
    @AdminUserPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;

    SELECT Id, Name, ProviderType, BaseUrl, IsEnabled
    FROM dbo.FundingPlatform_FundingSources
    ORDER BY Name, Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Funder_Admin_List
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @Query NVARCHAR(300) = NULL,
    @PublicationStatus TINYINT = NULL,
    @IncludeInactive BIT = 0,
    @PageNumber INT = 1,
    @PageSize INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    IF dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId) = 0
        THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId) = 1
        THROW 51602, N'MFA is required for this administrative operation.', 1;
    IF @PageNumber < 1 THROW 51603, N'PageNumber must be at least 1.', 1;
    IF @PageSize < 1 OR @PageSize > 100
        THROW 51604, N'PageSize must be between 1 and 100.', 1;
    IF @PublicationStatus IS NOT NULL AND @PublicationStatus NOT BETWEEN 0 AND 4
        THROW 51605, N'PublicationStatus is invalid.', 1;

    DECLARE @QueryLike NVARCHAR(302) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Query)), N'') IS NULL THEN NULL
             ELSE N'%' + LTRIM(RTRIM(@Query)) + N'%' END;

    SELECT COUNT_BIG(1) AS TotalCount
    FROM dbo.FundingPlatform_Funders AS funders
    WHERE (@IncludeInactive = 1 OR funders.IsActive = 1)
      AND (@PublicationStatus IS NULL OR funders.PublicationStatus = @PublicationStatus)
      AND (@QueryLike IS NULL OR funders.Name LIKE @QueryLike OR funders.Slug LIKE @QueryLike
           OR EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_FunderAliases AS aliases
               WHERE aliases.FunderId = funders.Id AND aliases.IsActive = 1
                 AND aliases.Alias LIKE @QueryLike));

    SELECT funders.PublicId AS FunderPublicId,
           funders.Slug, funders.Name, funders.Description, funders.WebsiteUrl,
           funders.CountryId, RTRIM(countries.Iso2) AS CountryCode,
           countries.Name AS CountryName, funders.ContentVersion,
           funders.PublicationStatus, funders.IsActive,
           funders.SubmittedAtUtc, funders.PublishedAtUtc, funders.ReviewedAtUtc,
           reviewers.PublicId AS ReviewedByUserPublicId, funders.RejectionReason,
           funders.CreatedAtUtc, funders.UpdatedAtUtc, funders.RowVersion
    FROM dbo.FundingPlatform_Funders AS funders
    LEFT JOIN dbo.FundingPlatform_Countries AS countries ON countries.Id = funders.CountryId
    LEFT JOIN dbo.FundingPlatform_Users AS reviewers ON reviewers.Id = funders.ReviewedByUserId
    WHERE (@IncludeInactive = 1 OR funders.IsActive = 1)
      AND (@PublicationStatus IS NULL OR funders.PublicationStatus = @PublicationStatus)
      AND (@QueryLike IS NULL OR funders.Name LIKE @QueryLike OR funders.Slug LIKE @QueryLike
           OR EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_FunderAliases AS aliases
               WHERE aliases.FunderId = funders.Id AND aliases.IsActive = 1
                 AND aliases.Alias LIKE @QueryLike))
    ORDER BY funders.UpdatedAtUtc DESC, funders.Id DESC
    OFFSET ((@PageNumber - 1) * @PageSize) ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Funder_Admin_Get
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FunderPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    IF dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId) = 0
        THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId) = 1
        THROW 51602, N'MFA is required for this administrative operation.', 1;

    DECLARE @FunderId BIGINT;
    SELECT @FunderId = Id FROM dbo.FundingPlatform_Funders WHERE PublicId = @FunderPublicId;
    IF @FunderId IS NULL THROW 51606, N'Funder was not found.', 1;

    SELECT funders.PublicId AS FunderPublicId,
           funders.Slug, funders.Name, funders.Description, funders.WebsiteUrl,
           funders.CountryId, RTRIM(countries.Iso2) AS CountryCode,
           countries.Name AS CountryName, funders.ContentVersion,
           funders.PublicationStatus, funders.IsActive,
           funders.SubmittedAtUtc, funders.PublishedAtUtc, funders.ReviewedAtUtc,
           reviewers.PublicId AS ReviewedByUserPublicId, funders.RejectionReason,
           funders.CreatedAtUtc, funders.UpdatedAtUtc, funders.RowVersion
    FROM dbo.FundingPlatform_Funders AS funders
    LEFT JOIN dbo.FundingPlatform_Countries AS countries ON countries.Id = funders.CountryId
    LEFT JOIN dbo.FundingPlatform_Users AS reviewers ON reviewers.Id = funders.ReviewedByUserId
    WHERE funders.Id = @FunderId;

    SELECT Alias, IsPrimary, IsActive
    FROM dbo.FundingPlatform_FunderAliases
    WHERE FunderId = @FunderId
    ORDER BY IsActive DESC, IsPrimary DESC, Alias, Id;

    SELECT opportunities.PublicId AS FundingOpportunityPublicId,
           opportunities.Slug, opportunities.Title, links.Role,
           opportunities.PublicationStatus, opportunities.IsActive
    FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
    INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
        ON opportunities.Id = links.FundingOpportunityId
    WHERE links.FunderId = @FunderId AND links.IsActive = 1
    ORDER BY opportunities.UpdatedAtUtc DESC, opportunities.Id DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Funder_Public_List
    @Query NVARCHAR(300) = NULL,
    @PageNumber INT = 1,
    @PageSize INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    IF @PageNumber < 1 THROW 51603, N'PageNumber must be at least 1.', 1;
    IF @PageSize < 1 OR @PageSize > 100
        THROW 51604, N'PageSize must be between 1 and 100.', 1;
    DECLARE @QueryLike NVARCHAR(302) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Query)), N'') IS NULL THEN NULL
             ELSE N'%' + LTRIM(RTRIM(@Query)) + N'%' END;

    SELECT COUNT_BIG(1) AS TotalCount
    FROM dbo.FundingPlatform_Funders AS funders
    WHERE funders.PublicationStatus = 2 AND funders.IsActive = 1
      AND (@QueryLike IS NULL OR funders.Name LIKE @QueryLike OR funders.Slug LIKE @QueryLike
           OR EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_FunderAliases AS aliases
               WHERE aliases.FunderId = funders.Id AND aliases.IsActive = 1
                 AND aliases.Alias LIKE @QueryLike));

    SELECT funders.PublicId AS FunderPublicId, funders.Slug, funders.Name,
           funders.Description, funders.WebsiteUrl, funders.CountryId,
           RTRIM(countries.Iso2) AS CountryCode, countries.Name AS CountryName,
           funders.PublishedAtUtc, funders.UpdatedAtUtc
    FROM dbo.FundingPlatform_Funders AS funders
    LEFT JOIN dbo.FundingPlatform_Countries AS countries
        ON countries.Id = funders.CountryId AND countries.IsActive = 1
    WHERE funders.PublicationStatus = 2 AND funders.IsActive = 1
      AND (@QueryLike IS NULL OR funders.Name LIKE @QueryLike OR funders.Slug LIKE @QueryLike
           OR EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_FunderAliases AS aliases
               WHERE aliases.FunderId = funders.Id AND aliases.IsActive = 1
                 AND aliases.Alias LIKE @QueryLike))
    ORDER BY funders.Name, funders.Id
    OFFSET ((@PageNumber - 1) * @PageSize) ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Funder_Public_GetBySlug
    @Slug NVARCHAR(180)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @FunderId BIGINT;
    SELECT @FunderId = Id
    FROM dbo.FundingPlatform_Funders
    WHERE Slug = @Slug AND PublicationStatus = 2 AND IsActive = 1;

    SELECT funders.PublicId AS FunderPublicId, funders.Slug, funders.Name,
           funders.Description, funders.WebsiteUrl, funders.CountryId,
           RTRIM(countries.Iso2) AS CountryCode, countries.Name AS CountryName,
           funders.ContentVersion, funders.PublishedAtUtc, funders.UpdatedAtUtc
    FROM dbo.FundingPlatform_Funders AS funders
    LEFT JOIN dbo.FundingPlatform_Countries AS countries
        ON countries.Id = funders.CountryId AND countries.IsActive = 1
    WHERE funders.Id = @FunderId;

    SELECT aliases.Alias, aliases.IsPrimary
    FROM dbo.FundingPlatform_FunderAliases AS aliases
    WHERE aliases.FunderId = @FunderId AND aliases.IsActive = 1
    ORDER BY aliases.IsPrimary DESC, aliases.Alias, aliases.Id;

    SELECT opportunities.PublicId AS FundingOpportunityPublicId,
           opportunities.Slug, opportunities.Title, opportunities.Summary,
           opportunities.SponsorName, opportunities.Currency,
           opportunities.MinAmount, opportunities.MaxAmount,
           opportunities.OpenDate, opportunities.CloseDate,
           opportunities.PublishedAtUtc
    FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
    INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
        ON opportunities.Id = links.FundingOpportunityId
       AND opportunities.PublicationStatus = 2 AND opportunities.IsActive = 1
    WHERE links.FunderId = @FunderId AND links.IsActive = 1
      AND EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs() AS catalogs
           WHERE catalogs.FundingOpportunityId = opportunities.Id)
      AND EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityFunders AS primaryLinks
           INNER JOIN dbo.FundingPlatform_Funders AS primaryFunders
               ON primaryFunders.Id = primaryLinks.FunderId
           WHERE primaryLinks.FundingOpportunityId = opportunities.Id
             AND primaryLinks.Role = 1 AND primaryLinks.IsActive = 1
             AND primaryFunders.PublicationStatus = 2 AND primaryFunders.IsActive = 1)
      AND EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS sourceLinks
           INNER JOIN dbo.FundingPlatform_FundingSources AS sources
               ON sources.Id = sourceLinks.FundingSourceId
           WHERE sourceLinks.FundingOpportunityId = opportunities.Id
             AND sourceLinks.IsPrimary = 1 AND sourceLinks.IsActive = 1
             AND sources.IsEnabled = 1
             AND NULLIF(LTRIM(RTRIM(sourceLinks.SourceUrl)), N'') IS NOT NULL)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCategories AS categories
           WHERE categories.FundingOpportunityId = opportunities.Id)
      AND
          ((opportunities.GeographicScope = 1 AND EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS countries
               WHERE countries.FundingOpportunityId = opportunities.Id))
           OR (opportunities.GeographicScope = 2
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS countries
                    WHERE countries.FundingOpportunityId = opportunities.Id)
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions AS regions
                    WHERE regions.FundingOpportunityId = opportunities.Id)))
      AND NOT EXISTS
          (SELECT required.FieldPath
           FROM (VALUES (N'/title'), (N'/description'),
                        (N'/eligibilityDescription'), (N'/closeDate')) AS required(FieldPath)
           WHERE NOT EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
              WHERE evidence.FundingOpportunityId = opportunities.Id
                AND evidence.FieldPath = required.FieldPath AND evidence.IsSelected = 1
                AND JSON_VALUE(evidence.ValueJson, '$.status') IN (N'known', N'unknown')))
    ORDER BY CASE WHEN opportunities.CloseDate IS NULL THEN 1 ELSE 0 END,
             opportunities.CloseDate, opportunities.Id DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Funder_Create
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @Slug NVARCHAR(180),
    @Name NVARCHAR(300),
    @Description NVARCHAR(2000) = NULL,
    @WebsiteUrl NVARCHAR(2048) = NULL,
    @CountryId SMALLINT = NULL,
    @AliasesJson NVARCHAR(MAX) = N'[]',
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;

    DECLARE @ActorUserId BIGINT, @FunderId BIGINT, @FunderPublicId UNIQUEIDENTIFIER;
    DECLARE @RowVersion BINARY(8), @ExistingRequestHash BINARY(32);
    DECLARE @Code NVARCHAR(50) = N'created', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @NormalizedName NVARCHAR(300) = UPPER(LTRIM(RTRIM(@Name)));
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @RawAliasCount INT, @ValidAliasCount INT;
    DECLARE @Aliases TABLE (Alias NVARCHAR(300) NOT NULL, NormalizedAlias NVARCHAR(300) NOT NULL);

    IF NULLIF(LTRIM(RTRIM(@Slug)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(@Name)), N'') IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               CAST(NULL AS UNIQUEIDENTIFIER) AS FunderPublicId, CAST(NULL AS INT) AS ContentVersion,
               CAST(NULL AS TINYINT) AS PublicationStatus, CAST(NULL AS BINARY(8)) AS RowVersion,
               CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;
    IF ISJSON(COALESCE(@AliasesJson, N'[]')) <> 1
       OR LEFT(LTRIM(COALESCE(@AliasesJson, N'[]')), 1) <> N'['
        THROW 51607, N'AliasesJson must be a JSON array.', 1;

    SELECT @RawAliasCount = COUNT(*)
    FROM OPENJSON(COALESCE(@AliasesJson, N'[]'));
    SELECT @ValidAliasCount = COUNT(*)
    FROM OPENJSON(COALESCE(@AliasesJson, N'[]'))
    WITH (Alias NVARCHAR(4000) '$.alias') AS parsed
    WHERE NULLIF(LTRIM(RTRIM(parsed.Alias)), N'') IS NOT NULL
      AND LEN(parsed.Alias) <= 300;

    IF @RawAliasCount <> @ValidAliasCount
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               CAST(NULL AS UNIQUEIDENTIFIER) AS FunderPublicId, CAST(NULL AS INT) AS ContentVersion,
               CAST(NULL AS TINYINT) AS PublicationStatus, CAST(NULL AS BINARY(8)) AS RowVersion,
               CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    INSERT INTO @Aliases (Alias, NormalizedAlias)
    SELECT LTRIM(RTRIM(parsed.Alias)), UPPER(LTRIM(RTRIM(parsed.Alias)))
    FROM OPENJSON(COALESCE(@AliasesJson, N'[]'))
    WITH (Alias NVARCHAR(300) '$.alias') AS parsed
    WHERE NULLIF(LTRIM(RTRIM(parsed.Alias)), N'') IS NOT NULL
      AND UPPER(LTRIM(RTRIM(parsed.Alias))) <> @NormalizedName;

    IF EXISTS (SELECT NormalizedAlias FROM @Aliases GROUP BY NormalizedAlias HAVING COUNT_BIG(1) > 1)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'alias-conflict' AS Code,
               CAST(NULL AS UNIQUEIDENTIFIER) AS FunderPublicId, CAST(NULL AS INT) AS ContentVersion,
               CAST(NULL AS TINYINT) AS PublicationStatus, CAST(NULL AS BINARY(8)) AS RowVersion,
               CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_FunderCreate;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @ActorUserId = Id
        FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;

        SELECT @FunderId = events.FunderId, @ExistingRequestHash = events.RequestHash,
               @RowVersion = events.ResultRowVersion
        FROM dbo.FundingPlatform_FunderEditorialEvents AS events WITH (UPDLOCK, HOLDLOCK)
        WHERE events.ActorUserId = @ActorUserId AND events.ActionCode = N'Create'
          AND events.IdempotencyKeyHash = @IdempotencyKeyHash;

        IF @FunderId IS NOT NULL
        BEGIN
            SELECT @FunderPublicId = PublicId FROM dbo.FundingPlatform_Funders WHERE Id = @FunderId;
            IF @ExistingRequestHash = @RequestHash
            BEGIN
                SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'created';
            END
            ELSE SET @Code = N'idempotency-conflict';
        END
        ELSE IF @CountryId IS NOT NULL AND NOT EXISTS
                (SELECT 1 FROM dbo.FundingPlatform_Countries WHERE Id = @CountryId AND IsActive = 1)
            SET @Code = N'invalid-document';
            ELSE IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders WITH (UPDLOCK, HOLDLOCK)
                            WHERE Slug = LTRIM(RTRIM(@Slug)))
                SET @Code = N'slug-conflict';
            ELSE IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders WITH (UPDLOCK, HOLDLOCK)
                            WHERE NormalizedName = @NormalizedName)
            SET @Code = N'name-conflict';
        ELSE
        BEGIN
            DECLARE @InsertedFunder TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER, RowVersion BINARY(8));
            INSERT INTO dbo.FundingPlatform_Funders
            (
                Slug, Name, NormalizedName, Description, WebsiteUrl, CountryId,
                PublicationStatus, ContentVersion, IsActive,
                CreatedByUserId, UpdatedByUserId, CreatedAtUtc, UpdatedAtUtc
            )
            OUTPUT inserted.Id, inserted.PublicId, inserted.RowVersion
                INTO @InsertedFunder (Id, PublicId, RowVersion)
            VALUES
            (
                LTRIM(RTRIM(@Slug)), LTRIM(RTRIM(@Name)), @NormalizedName,
                NULLIF(LTRIM(RTRIM(@Description)), N''), NULLIF(LTRIM(RTRIM(@WebsiteUrl)), N''),
                @CountryId, 0, 1, 1, @ActorUserId, @ActorUserId, @NowUtc, @NowUtc
            );
            SELECT @FunderId = Id, @FunderPublicId = PublicId, @RowVersion = RowVersion
            FROM @InsertedFunder;

            INSERT INTO dbo.FundingPlatform_FunderAliases
                (FunderId, Alias, NormalizedAlias, IsPrimary, IsActive, CreatedAtUtc)
            VALUES (@FunderId, LTRIM(RTRIM(@Name)), @NormalizedName, 1, 1, @NowUtc);
            INSERT INTO dbo.FundingPlatform_FunderAliases
                (FunderId, Alias, NormalizedAlias, IsPrimary, IsActive, CreatedAtUtc)
            SELECT @FunderId, aliases.Alias, aliases.NormalizedAlias, 0, 1, @NowUtc
            FROM @Aliases AS aliases;

            DECLARE @SnapshotJson NVARCHAR(MAX) =
            (
                SELECT LTRIM(RTRIM(@Slug)) AS slug, LTRIM(RTRIM(@Name)) AS name,
                       NULLIF(LTRIM(RTRIM(@Description)), N'') AS description,
                       NULLIF(LTRIM(RTRIM(@WebsiteUrl)), N'') AS websiteUrl,
                       @CountryId AS countryId,
                       JSON_QUERY
                       (
                           (SELECT aliases.Alias AS alias, aliases.IsPrimary AS isPrimary
                            FROM dbo.FundingPlatform_FunderAliases AS aliases
                            WHERE aliases.FunderId = @FunderId AND aliases.IsActive = 1
                            ORDER BY aliases.IsPrimary DESC, aliases.Id FOR JSON PATH)
                       ) AS aliases
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
            INSERT INTO dbo.FundingPlatform_FunderVersions
                (FunderId, ContentVersion, SnapshotJson, ContentHash, CreatedByUserId, CreatedAtUtc)
            VALUES (@FunderId, 1, @SnapshotJson,
                    HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @SnapshotJson)),
                    @ActorUserId, @NowUtc);
            INSERT INTO dbo.FundingPlatform_FunderEditorialEvents
                (EventId, FunderId, ContentVersion, FromStatus, ToStatus, ActionCode,
                 ActorUserId, Reason, IdempotencyKeyHash, RequestHash, ResultRowVersion, CreatedAtUtc)
            VALUES (@EventId, @FunderId, 1, 0, 0, N'Create', @ActorUserId, NULL,
                    @IdempotencyKeyHash, @RequestHash, @RowVersion, @NowUtc);
            INSERT INTO dbo.FundingPlatform_OutboxMessages
                (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                 OccurredAtUtc, AvailableAtUtc)
            SELECT @EventId, N'FunderDraftCreated', N'Funder', CONVERT(NVARCHAR(100), @FunderId),
                   (SELECT @EventId AS eventId, @FunderId AS funderId,
                           @FunderPublicId AS funderPublicId, 1 AS contentVersion
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
            SET @Succeeded = 1;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_FunderCreate;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, @FunderPublicId AS FunderPublicId,
           CASE WHEN @FunderId IS NULL THEN NULL ELSE 1 END AS ContentVersion,
           CASE WHEN @FunderId IS NULL THEN NULL ELSE 0 END AS PublicationStatus,
           @RowVersion AS RowVersion, @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Funder_Update
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FunderPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @Name NVARCHAR(300),
    @Description NVARCHAR(2000) = NULL,
    @WebsiteUrl NVARCHAR(2048) = NULL,
    @CountryId SMALLINT = NULL,
    @AliasesJson NVARCHAR(MAX) = N'[]',
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    IF ISJSON(COALESCE(@AliasesJson, N'[]')) <> 1
       OR LEFT(LTRIM(COALESCE(@AliasesJson, N'[]')), 1) <> N'['
        THROW 51607, N'AliasesJson must be a JSON array.', 1;

    DECLARE @ActorUserId BIGINT, @FunderId BIGINT, @CurrentStatus TINYINT, @CurrentSlug NVARCHAR(180);
    DECLARE @CurrentVersion INT, @NextVersion INT, @CurrentRowVersion BINARY(8), @RowVersion BINARY(8);
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @NormalizedName NVARCHAR(300) = UPPER(LTRIM(RTRIM(@Name)));
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @RawAliasCount INT, @ValidAliasCount INT;
    DECLARE @Aliases TABLE (Alias NVARCHAR(300) NOT NULL, NormalizedAlias NVARCHAR(300) NOT NULL);

    INSERT INTO @Aliases (Alias, NormalizedAlias)
    SELECT LTRIM(RTRIM(parsed.Alias)), UPPER(LTRIM(RTRIM(parsed.Alias)))
    FROM OPENJSON(COALESCE(@AliasesJson, N'[]'))
    WITH (Alias NVARCHAR(300) '$.alias') AS parsed
    WHERE NULLIF(LTRIM(RTRIM(parsed.Alias)), N'') IS NOT NULL
      AND UPPER(LTRIM(RTRIM(parsed.Alias))) <> @NormalizedName;

    SELECT @RawAliasCount = COUNT(*)
    FROM OPENJSON(COALESCE(@AliasesJson, N'[]'));
    SELECT @ValidAliasCount = COUNT(*)
    FROM OPENJSON(COALESCE(@AliasesJson, N'[]'))
    WITH (Alias NVARCHAR(4000) '$.alias') AS parsed
    WHERE NULLIF(LTRIM(RTRIM(parsed.Alias)), N'') IS NOT NULL
      AND LEN(parsed.Alias) <= 300;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_FunderUpdate;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @ActorUserId = Id
        FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;
        SELECT @FunderId = Id, @CurrentStatus = PublicationStatus, @CurrentSlug = Slug,
               @CurrentVersion = ContentVersion, @CurrentRowVersion = RowVersion
        FROM dbo.FundingPlatform_Funders WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @FunderPublicId;

        IF @FunderId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = ActionCode, @ExistingRequestHash = RequestHash,
                   @ExistingToStatus = ToStatus, @RowVersion = ResultRowVersion,
                   @NextVersion = ContentVersion
            FROM dbo.FundingPlatform_FunderEditorialEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE FunderId = @FunderId AND IdempotencyKeyHash = @IdempotencyKeyHash;
            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'Update' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'updated';
                    SET @CurrentStatus = @ExistingToStatus;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus NOT IN (0, 3) SET @Code = N'invalid-transition';
            ELSE IF NULLIF(LTRIM(RTRIM(@Name)), N'') IS NULL
                 OR @RawAliasCount <> @ValidAliasCount
                 OR EXISTS (SELECT NormalizedAlias FROM @Aliases GROUP BY NormalizedAlias HAVING COUNT_BIG(1) > 1)
                SET @Code = N'invalid-document';
            ELSE IF @CountryId IS NOT NULL AND NOT EXISTS
                    (SELECT 1 FROM dbo.FundingPlatform_Countries WHERE Id = @CountryId AND IsActive = 1)
                SET @Code = N'invalid-document';
            ELSE IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders WITH (UPDLOCK, HOLDLOCK)
                            WHERE NormalizedName = @NormalizedName AND Id <> @FunderId)
                SET @Code = N'name-conflict';
            ELSE
            BEGIN
                SET @NextVersion = @CurrentVersion + 1;
                DECLARE @UpdatedFunder TABLE (RowVersion BINARY(8));
                UPDATE dbo.FundingPlatform_Funders
                SET Name = LTRIM(RTRIM(@Name)),
                    NormalizedName = @NormalizedName,
                    Description = NULLIF(LTRIM(RTRIM(@Description)), N''),
                    WebsiteUrl = NULLIF(LTRIM(RTRIM(@WebsiteUrl)), N''),
                    CountryId = @CountryId, ContentVersion = @NextVersion,
                    UpdatedByUserId = @ActorUserId, UpdatedAtUtc = @NowUtc
                OUTPUT inserted.RowVersion INTO @UpdatedFunder (RowVersion)
                WHERE Id = @FunderId AND RowVersion = @ExpectedRowVersion;
                SELECT @RowVersion = RowVersion FROM @UpdatedFunder;
                IF @RowVersion IS NULL SET @Code = N'etag-conflict';
                ELSE
                BEGIN
                    UPDATE dbo.FundingPlatform_FunderAliases
                    SET IsActive = 0, IsPrimary = 0
                    WHERE FunderId = @FunderId;
                    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_FunderAliases
                               WHERE FunderId = @FunderId AND NormalizedAlias = @NormalizedName)
                        UPDATE dbo.FundingPlatform_FunderAliases
                        SET Alias = LTRIM(RTRIM(@Name)), IsPrimary = 1, IsActive = 1
                        WHERE FunderId = @FunderId AND NormalizedAlias = @NormalizedName;
                    ELSE
                        INSERT INTO dbo.FundingPlatform_FunderAliases
                            (FunderId, Alias, NormalizedAlias, IsPrimary, IsActive, CreatedAtUtc)
                        VALUES (@FunderId, LTRIM(RTRIM(@Name)), @NormalizedName, 1, 1, @NowUtc);

                    UPDATE aliases
                    SET Alias = requested.Alias, IsPrimary = 0, IsActive = 1
                    FROM dbo.FundingPlatform_FunderAliases AS aliases
                    INNER JOIN @Aliases AS requested ON requested.NormalizedAlias = aliases.NormalizedAlias
                    WHERE aliases.FunderId = @FunderId;
                    INSERT INTO dbo.FundingPlatform_FunderAliases
                        (FunderId, Alias, NormalizedAlias, IsPrimary, IsActive, CreatedAtUtc)
                    SELECT @FunderId, requested.Alias, requested.NormalizedAlias, 0, 1, @NowUtc
                    FROM @Aliases AS requested
                    WHERE NOT EXISTS
                    (
                        SELECT 1 FROM dbo.FundingPlatform_FunderAliases AS existing
                        WHERE existing.FunderId = @FunderId
                          AND existing.NormalizedAlias = requested.NormalizedAlias
                    );

                    DECLARE @SnapshotJson NVARCHAR(MAX) =
                    (
                        SELECT @CurrentSlug AS slug, LTRIM(RTRIM(@Name)) AS name,
                               NULLIF(LTRIM(RTRIM(@Description)), N'') AS description,
                               NULLIF(LTRIM(RTRIM(@WebsiteUrl)), N'') AS websiteUrl,
                               @CountryId AS countryId,
                               JSON_QUERY
                               (
                                   (SELECT aliases.Alias AS alias, aliases.IsPrimary AS isPrimary
                                    FROM dbo.FundingPlatform_FunderAliases AS aliases
                                    WHERE aliases.FunderId = @FunderId AND aliases.IsActive = 1
                                    ORDER BY aliases.IsPrimary DESC, aliases.Id FOR JSON PATH)
                               ) AS aliases
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    );
                    INSERT INTO dbo.FundingPlatform_FunderVersions
                        (FunderId, ContentVersion, SnapshotJson, ContentHash, CreatedByUserId, CreatedAtUtc)
                    VALUES (@FunderId, @NextVersion, @SnapshotJson,
                            HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @SnapshotJson)),
                            @ActorUserId, @NowUtc);
                    INSERT INTO dbo.FundingPlatform_FunderEditorialEvents
                        (EventId, FunderId, ContentVersion, FromStatus, ToStatus, ActionCode,
                         ActorUserId, Reason, IdempotencyKeyHash, RequestHash, ResultRowVersion, CreatedAtUtc)
                    VALUES (@EventId, @FunderId, @NextVersion, @CurrentStatus, @CurrentStatus,
                            N'Update', @ActorUserId, NULL, @IdempotencyKeyHash,
                            @RequestHash, @RowVersion, @NowUtc);
                    INSERT INTO dbo.FundingPlatform_OutboxMessages
                        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                         OccurredAtUtc, AvailableAtUtc)
                    SELECT @EventId, N'FunderChanged', N'Funder', CONVERT(NVARCHAR(100), @FunderId),
                           (SELECT @EventId AS eventId, @FunderId AS funderId,
                                   @FunderPublicId AS funderPublicId, @NextVersion AS contentVersion
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                    SET @Succeeded = 1; SET @Code = N'updated';
                END;
            END;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_FunderUpdate;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, @FunderPublicId AS FunderPublicId,
           COALESCE(@NextVersion, @CurrentVersion) AS ContentVersion,
           @CurrentStatus AS PublicationStatus, COALESCE(@RowVersion, @CurrentRowVersion) AS RowVersion,
           @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Funder_RequestPublication
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FunderPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @ResultCode NVARCHAR(50) = NULL OUTPUT,
    @ResultCompleteness DECIMAL(5,2) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;

    DECLARE @Issues TABLE
    (
        Code NVARCHAR(50) NOT NULL,
        FieldPath NVARCHAR(100) NOT NULL,
        Message NVARCHAR(300) NOT NULL
    );
    DECLARE @ActorUserId BIGINT, @FunderId BIGINT, @ContentVersion INT;
    DECLARE @CurrentStatus TINYINT, @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @SubmittedAtUtc DATETIME2(3), @PublishedAtUtc DATETIME2(3), @ReviewedAtUtc DATETIME2(3);
    DECLARE @ReviewedByUserPublicId UNIQUEIDENTIFIER, @RejectionReason NVARCHAR(1000);
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Completeness DECIMAL(5,2) = 0;
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_FunderRequest;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @ActorUserId = Id FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;
        SELECT @FunderId = funders.Id, @ContentVersion = funders.ContentVersion,
               @CurrentStatus = funders.PublicationStatus,
               @CurrentRowVersion = funders.RowVersion,
               @SubmittedAtUtc = funders.SubmittedAtUtc,
               @PublishedAtUtc = funders.PublishedAtUtc,
               @ReviewedAtUtc = funders.ReviewedAtUtc,
               @ReviewedByUserPublicId = reviewers.PublicId,
               @RejectionReason = funders.RejectionReason
        FROM dbo.FundingPlatform_Funders AS funders WITH (UPDLOCK, HOLDLOCK)
        LEFT JOIN dbo.FundingPlatform_Users AS reviewers ON reviewers.Id = funders.ReviewedByUserId
        WHERE funders.PublicId = @FunderPublicId;

        IF @FunderId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = ActionCode, @ExistingRequestHash = RequestHash,
                   @ExistingToStatus = ToStatus, @ResultRowVersion = ResultRowVersion,
                   @ContentVersion = ContentVersion, @Completeness = ResultCompleteness,
                   @SubmittedAtUtc = ResultSubmittedAtUtc,
                   @PublishedAtUtc = ResultPublishedAtUtc,
                   @ReviewedAtUtc = ResultReviewedAtUtc,
                   @ReviewedByUserPublicId = ResultReviewedByUserPublicId,
                   @RejectionReason = ResultRejectionReason
            FROM dbo.FundingPlatform_FunderEditorialEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE FunderId = @FunderId AND IdempotencyKeyHash = @IdempotencyKeyHash;
            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'RequestPublication' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'review-requested';
                    SET @CurrentStatus = @ExistingToStatus;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus NOT IN (0, 3) SET @Code = N'invalid-transition';
            ELSE
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders
                               WHERE Id = @FunderId AND NULLIF(LTRIM(RTRIM(Name)), N'') IS NOT NULL)
                    INSERT INTO @Issues VALUES (N'name', N'name', N'Name is required.');
                IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders
                               WHERE Id = @FunderId AND NULLIF(LTRIM(RTRIM(Slug)), N'') IS NOT NULL)
                    INSERT INTO @Issues VALUES (N'slug', N'slug', N'A stable public slug is required.');
                IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders
                               WHERE Id = @FunderId AND NULLIF(LTRIM(RTRIM(WebsiteUrl)), N'') IS NOT NULL)
                    INSERT INTO @Issues VALUES (N'websiteUrl', N'websiteUrl', N'An official website is required.');
                IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FunderAliases
                               WHERE FunderId = @FunderId AND IsPrimary = 1 AND IsActive = 1)
                    INSERT INTO @Issues VALUES (N'primaryAlias', N'aliases', N'A primary alias is required.');
                SET @Completeness = CONVERT(DECIMAL(5,2), 100 - (SELECT COUNT(1) * 25 FROM @Issues));

                IF EXISTS (SELECT 1 FROM @Issues) SET @Code = N'funder-not-ready';
                ELSE
                BEGIN
                    DECLARE @Updated TABLE (RowVersion BINARY(8));
                    UPDATE dbo.FundingPlatform_Funders
                    SET PublicationStatus = 1, SubmittedAtUtc = @NowUtc,
                        ReviewedAtUtc = NULL, ReviewedByUserId = NULL,
                        RejectionReason = NULL, UpdatedByUserId = @ActorUserId,
                        UpdatedAtUtc = @NowUtc
                    OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
                    WHERE Id = @FunderId AND RowVersion = @ExpectedRowVersion;
                    SELECT @ResultRowVersion = RowVersion FROM @Updated;
                    IF @ResultRowVersion IS NULL SET @Code = N'etag-conflict';
                    ELSE
                    BEGIN
                        INSERT INTO dbo.FundingPlatform_FunderEditorialEvents
                            (EventId, FunderId, ContentVersion, FromStatus, ToStatus, ActionCode,
                             ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                             ResultRowVersion, ResultCompleteness, ResultSubmittedAtUtc,
                             ResultPublishedAtUtc, ResultReviewedAtUtc,
                             ResultReviewedByUserPublicId, ResultRejectionReason, CreatedAtUtc)
                        VALUES (@EventId, @FunderId, @ContentVersion, @CurrentStatus, 1,
                                N'RequestPublication', @ActorUserId, NULL, @IdempotencyKeyHash,
                                @RequestHash, @ResultRowVersion, 100, @NowUtc,
                                @PublishedAtUtc, NULL, NULL, NULL, @NowUtc);
                        INSERT INTO dbo.FundingPlatform_OutboxMessages
                            (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                             OccurredAtUtc, AvailableAtUtc)
                        SELECT @EventId, N'FunderPublicationRequested', N'Funder',
                               CONVERT(NVARCHAR(100), @FunderId),
                               (SELECT @EventId AS eventId, @FunderId AS funderId,
                                       @FunderPublicId AS funderPublicId, @ContentVersion AS contentVersion,
                                       @CurrentStatus AS fromStatus, 1 AS toStatus
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                        SET @Succeeded = 1; SET @Code = N'review-requested';
                        SET @CurrentStatus = 1; SET @SubmittedAtUtc = @NowUtc;
                        SET @ReviewedAtUtc = NULL; SET @ReviewedByUserPublicId = NULL;
                        SET @RejectionReason = NULL;
                    END;
                END;
            END;
        END;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_FunderRequest;
        THROW;
    END CATCH;

    SET @ResultCode = @Code; SET @ResultCompleteness = @Completeness;
    SELECT @Succeeded AS Succeeded, @Code AS Code, @Completeness AS Completeness,
           @FunderPublicId AS FunderPublicId, @ContentVersion AS ContentVersion,
           @CurrentStatus AS PublicationStatus, @SubmittedAtUtc AS SubmittedAtUtc,
           @PublishedAtUtc AS PublishedAtUtc, @ReviewedAtUtc AS ReviewedAtUtc,
           @ReviewedByUserPublicId AS ReviewedByUserPublicId,
           @RejectionReason AS RejectionReason,
           COALESCE(@ResultRowVersion, @CurrentRowVersion) AS RowVersion, @WasReplay AS WasReplay;
    SELECT Code, FieldPath, Message FROM @Issues ORDER BY FieldPath, Code;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Funder_AdminReview
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FunderPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @Decision TINYINT,
    @RejectionReason NVARCHAR(1000) = NULL,
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;

    DECLARE @ActorUserId BIGINT, @FunderId BIGINT, @ContentVersion INT;
    DECLARE @CurrentStatus TINYINT, @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @SubmittedAtUtc DATETIME2(3), @PublishedAtUtc DATETIME2(3), @ReviewedAtUtc DATETIME2(3);
    DECLARE @ReviewedByUserPublicId UNIQUEIDENTIFIER, @CurrentRejectionReason NVARCHAR(1000);
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @Completeness DECIMAL(5,2) = NULL;

    IF @Decision NOT IN (2, 3)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-decision' AS Code, @Completeness AS Completeness,
               @FunderPublicId AS FunderPublicId, CAST(NULL AS INT) AS ContentVersion,
               CAST(NULL AS TINYINT) AS PublicationStatus, CAST(NULL AS DATETIME2(3)) AS SubmittedAtUtc,
               CAST(NULL AS DATETIME2(3)) AS PublishedAtUtc, CAST(NULL AS DATETIME2(3)) AS ReviewedAtUtc,
               CAST(NULL AS UNIQUEIDENTIFIER) AS ReviewedByUserPublicId,
               CAST(NULL AS NVARCHAR(1000)) AS RejectionReason,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_FunderReview;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @ActorUserId = Id FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;
        SELECT @FunderId = funders.Id, @ContentVersion = funders.ContentVersion,
               @CurrentStatus = funders.PublicationStatus,
               @CurrentRowVersion = funders.RowVersion,
               @SubmittedAtUtc = funders.SubmittedAtUtc,
               @PublishedAtUtc = funders.PublishedAtUtc,
               @ReviewedAtUtc = funders.ReviewedAtUtc,
               @ReviewedByUserPublicId = reviewers.PublicId,
               @CurrentRejectionReason = funders.RejectionReason
        FROM dbo.FundingPlatform_Funders AS funders WITH (UPDLOCK, HOLDLOCK)
        LEFT JOIN dbo.FundingPlatform_Users AS reviewers ON reviewers.Id = funders.ReviewedByUserId
        WHERE funders.PublicId = @FunderPublicId;

        IF @FunderId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = ActionCode, @ExistingRequestHash = RequestHash,
                   @ExistingToStatus = ToStatus, @ResultRowVersion = ResultRowVersion,
                   @ContentVersion = ContentVersion, @Completeness = ResultCompleteness,
                   @SubmittedAtUtc = ResultSubmittedAtUtc,
                   @PublishedAtUtc = ResultPublishedAtUtc,
                   @ReviewedAtUtc = ResultReviewedAtUtc,
                   @ReviewedByUserPublicId = ResultReviewedByUserPublicId,
                   @CurrentRejectionReason = ResultRejectionReason
            FROM dbo.FundingPlatform_FunderEditorialEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE FunderId = @FunderId AND IdempotencyKeyHash = @IdempotencyKeyHash;
            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'AdminReview' AND @ExistingRequestHash = @RequestHash
                   AND @ExistingToStatus = @Decision
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1;
                    SET @Code = CASE WHEN @Decision = 2 THEN N'published' ELSE N'rejected' END;
                    SET @CurrentStatus = @ExistingToStatus;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus <> 1 SET @Code = N'invalid-transition';
            ELSE IF @Decision = 3 AND NULLIF(LTRIM(RTRIM(@RejectionReason)), N'') IS NULL
                SET @Code = N'rejection-reason-required';
            ELSE IF @Decision = 2 AND
                    (NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders
                                 WHERE Id = @FunderId AND NULLIF(LTRIM(RTRIM(Name)), N'') IS NOT NULL
                                   AND NULLIF(LTRIM(RTRIM(Slug)), N'') IS NOT NULL
                                   AND NULLIF(LTRIM(RTRIM(WebsiteUrl)), N'') IS NOT NULL)
                     OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FunderAliases
                                    WHERE FunderId = @FunderId AND IsPrimary = 1 AND IsActive = 1))
                SET @Code = N'funder-not-ready';
            ELSE
            BEGIN
                DECLARE @Updated TABLE (RowVersion BINARY(8));
                UPDATE dbo.FundingPlatform_Funders
                SET PublicationStatus = @Decision,
                    PublishedAtUtc = CASE WHEN @Decision = 2 THEN COALESCE(PublishedAtUtc, @NowUtc)
                                          ELSE PublishedAtUtc END,
                    ReviewedAtUtc = @NowUtc, ReviewedByUserId = @ActorUserId,
                    RejectionReason = CASE WHEN @Decision = 3 THEN LTRIM(RTRIM(@RejectionReason)) ELSE NULL END,
                    UpdatedByUserId = @ActorUserId, UpdatedAtUtc = @NowUtc
                OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
                WHERE Id = @FunderId AND RowVersion = @ExpectedRowVersion;
                SELECT @ResultRowVersion = RowVersion FROM @Updated;
                IF @ResultRowVersion IS NULL SET @Code = N'etag-conflict';
                ELSE
                BEGIN
                    INSERT INTO dbo.FundingPlatform_FunderEditorialEvents
                        (EventId, FunderId, ContentVersion, FromStatus, ToStatus, ActionCode,
                         ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                         ResultRowVersion, ResultCompleteness, ResultSubmittedAtUtc,
                         ResultPublishedAtUtc, ResultReviewedAtUtc,
                         ResultReviewedByUserPublicId, ResultRejectionReason, CreatedAtUtc)
                    VALUES (@EventId, @FunderId, @ContentVersion, @CurrentStatus, @Decision,
                            N'AdminReview', @ActorUserId,
                            CASE WHEN @Decision = 3 THEN LTRIM(RTRIM(@RejectionReason)) ELSE NULL END,
                            @IdempotencyKeyHash, @RequestHash, @ResultRowVersion, NULL,
                            @SubmittedAtUtc,
                            CASE WHEN @Decision = 2 THEN COALESCE(@PublishedAtUtc, @NowUtc)
                                 ELSE @PublishedAtUtc END,
                            @NowUtc, @AdminUserPublicId,
                            CASE WHEN @Decision = 3 THEN LTRIM(RTRIM(@RejectionReason)) ELSE NULL END,
                            @NowUtc);
                    INSERT INTO dbo.FundingPlatform_OutboxMessages
                        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                         OccurredAtUtc, AvailableAtUtc)
                    SELECT @EventId,
                           CASE WHEN @Decision = 2 THEN N'FunderPublished' ELSE N'FunderRejected' END,
                           N'Funder', CONVERT(NVARCHAR(100), @FunderId),
                           (SELECT @EventId AS eventId, @FunderId AS funderId,
                                   @FunderPublicId AS funderPublicId, @ContentVersion AS contentVersion,
                                   @CurrentStatus AS fromStatus, @Decision AS toStatus
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                    SET @Succeeded = 1;
                    SET @Code = CASE WHEN @Decision = 2 THEN N'published' ELSE N'rejected' END;
                    SET @CurrentStatus = @Decision; SET @ReviewedAtUtc = @NowUtc;
                    SET @ReviewedByUserPublicId = @AdminUserPublicId;
                    SET @CurrentRejectionReason = CASE WHEN @Decision = 3
                                                      THEN LTRIM(RTRIM(@RejectionReason)) ELSE NULL END;
                    IF @Decision = 2 SET @PublishedAtUtc = COALESCE(@PublishedAtUtc, @NowUtc);
                END;
            END;
        END;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_FunderReview;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, @Completeness AS Completeness,
           @FunderPublicId AS FunderPublicId, @ContentVersion AS ContentVersion,
           @CurrentStatus AS PublicationStatus, @SubmittedAtUtc AS SubmittedAtUtc,
           @PublishedAtUtc AS PublishedAtUtc, @ReviewedAtUtc AS ReviewedAtUtc,
           @ReviewedByUserPublicId AS ReviewedByUserPublicId,
           @CurrentRejectionReason AS RejectionReason,
           COALESCE(@ResultRowVersion, @CurrentRowVersion) AS RowVersion, @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Funder_StartCorrection
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FunderPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @Reason NVARCHAR(1000),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;

    DECLARE @NormalizedReason NVARCHAR(1000) = LTRIM(RTRIM(@Reason));
    IF LEN(COALESCE(@NormalizedReason, N'')) NOT BETWEEN 3 AND 1000
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               CAST(NULL AS DECIMAL(5,2)) AS Completeness,
               @FunderPublicId AS FunderPublicId, CAST(NULL AS INT) AS ContentVersion,
               CAST(NULL AS TINYINT) AS PublicationStatus,
               CAST(NULL AS DATETIME2(3)) AS SubmittedAtUtc,
               CAST(NULL AS DATETIME2(3)) AS PublishedAtUtc,
               CAST(NULL AS DATETIME2(3)) AS ReviewedAtUtc,
               CAST(NULL AS UNIQUEIDENTIFIER) AS ReviewedByUserPublicId,
               CAST(NULL AS NVARCHAR(1000)) AS RejectionReason,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    DECLARE @ActorUserId BIGINT, @FunderId BIGINT, @ContentVersion INT;
    DECLARE @CurrentStatus TINYINT, @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @SubmittedAtUtc DATETIME2(3), @PublishedAtUtc DATETIME2(3), @ReviewedAtUtc DATETIME2(3);
    DECLARE @ReviewedByUserPublicId UNIQUEIDENTIFIER, @CurrentRejectionReason NVARCHAR(1000);
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_FunderCorrection;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @FunderId = funders.Id, @ContentVersion = funders.ContentVersion,
               @CurrentStatus = funders.PublicationStatus,
               @CurrentRowVersion = funders.RowVersion,
               @SubmittedAtUtc = funders.SubmittedAtUtc,
               @PublishedAtUtc = funders.PublishedAtUtc,
               @ReviewedAtUtc = funders.ReviewedAtUtc,
               @ReviewedByUserPublicId = reviewers.PublicId,
               @CurrentRejectionReason = funders.RejectionReason
        FROM dbo.FundingPlatform_Funders AS funders WITH (UPDLOCK, HOLDLOCK)
        LEFT JOIN dbo.FundingPlatform_Users AS reviewers ON reviewers.Id = funders.ReviewedByUserId
        WHERE funders.PublicId = @FunderPublicId;

        IF @FunderId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = ActionCode, @ExistingRequestHash = RequestHash,
                   @ExistingToStatus = ToStatus, @ResultRowVersion = ResultRowVersion,
                   @ContentVersion = ContentVersion,
                   @SubmittedAtUtc = ResultSubmittedAtUtc,
                   @PublishedAtUtc = ResultPublishedAtUtc,
                   @ReviewedAtUtc = ResultReviewedAtUtc,
                   @ReviewedByUserPublicId = ResultReviewedByUserPublicId,
                   @CurrentRejectionReason = ResultRejectionReason
            FROM dbo.FundingPlatform_FunderEditorialEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE FunderId = @FunderId AND IdempotencyKeyHash = @IdempotencyKeyHash;

            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'StartCorrection' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1;
                    SET @Code = N'correction-started'; SET @CurrentStatus = @ExistingToStatus;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus <> 2 SET @Code = N'invalid-transition';
            ELSE
            BEGIN
                DECLARE @Updated TABLE (RowVersion BINARY(8));
                UPDATE dbo.FundingPlatform_Funders
                SET PublicationStatus = 0, SubmittedAtUtc = NULL, PublishedAtUtc = NULL,
                    ReviewedAtUtc = NULL, ReviewedByUserId = NULL, RejectionReason = NULL,
                    UpdatedByUserId = @ActorUserId, UpdatedAtUtc = @NowUtc
                OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
                WHERE Id = @FunderId AND RowVersion = @ExpectedRowVersion;
                SELECT @ResultRowVersion = RowVersion FROM @Updated;
                IF @ResultRowVersion IS NULL SET @Code = N'etag-conflict';
                ELSE
                BEGIN
                    INSERT INTO dbo.FundingPlatform_FunderEditorialEvents
                        (EventId, FunderId, ContentVersion, FromStatus, ToStatus, ActionCode,
                         ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                         ResultRowVersion, ResultCompleteness, ResultSubmittedAtUtc,
                         ResultPublishedAtUtc, ResultReviewedAtUtc,
                         ResultReviewedByUserPublicId, ResultRejectionReason, CreatedAtUtc)
                    VALUES (@EventId, @FunderId, @ContentVersion, 2, 0, N'StartCorrection',
                            @ActorUserId, @NormalizedReason, @IdempotencyKeyHash, @RequestHash,
                            @ResultRowVersion, NULL, NULL, NULL, NULL, NULL, NULL, @NowUtc);
                    INSERT INTO dbo.FundingPlatform_OutboxMessages
                        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                         OccurredAtUtc, AvailableAtUtc)
                    SELECT @EventId, N'FunderCorrectionStarted', N'Funder',
                           CONVERT(NVARCHAR(100), @FunderId),
                           (SELECT @EventId AS eventId, @FunderId AS funderId,
                                   @FunderPublicId AS funderPublicId,
                                   @ContentVersion AS contentVersion, 2 AS fromStatus, 0 AS toStatus
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                    SET @Succeeded = 1; SET @Code = N'correction-started'; SET @CurrentStatus = 0;
                    SET @SubmittedAtUtc = NULL; SET @PublishedAtUtc = NULL;
                    SET @ReviewedAtUtc = NULL; SET @ReviewedByUserPublicId = NULL;
                    SET @CurrentRejectionReason = NULL;
                END;
            END;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_FunderCorrection;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           CAST(NULL AS DECIMAL(5,2)) AS Completeness,
           @FunderPublicId AS FunderPublicId, @ContentVersion AS ContentVersion,
           @CurrentStatus AS PublicationStatus, @SubmittedAtUtc AS SubmittedAtUtc,
           @PublishedAtUtc AS PublishedAtUtc, @ReviewedAtUtc AS ReviewedAtUtc,
           @ReviewedByUserPublicId AS ReviewedByUserPublicId,
           @CurrentRejectionReason AS RejectionReason,
           COALESCE(@ResultRowVersion, @CurrentRowVersion) AS RowVersion,
           @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Funder_Deactivate
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FunderPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @Reason NVARCHAR(1000) = NULL,
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;

    DECLARE @ActorUserId BIGINT, @FunderId BIGINT, @ContentVersion INT;
    DECLARE @CurrentStatus TINYINT, @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @SubmittedAtUtc DATETIME2(3), @PublishedAtUtc DATETIME2(3), @ReviewedAtUtc DATETIME2(3);
    DECLARE @ReviewedByUserPublicId UNIQUEIDENTIFIER, @RejectionReason NVARCHAR(1000);
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_FunderDeactivate;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @ActorUserId = Id FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;
        SELECT @FunderId = funders.Id, @ContentVersion = funders.ContentVersion,
               @CurrentStatus = funders.PublicationStatus, @CurrentRowVersion = funders.RowVersion,
               @SubmittedAtUtc = funders.SubmittedAtUtc, @PublishedAtUtc = funders.PublishedAtUtc,
               @ReviewedAtUtc = funders.ReviewedAtUtc, @ReviewedByUserPublicId = reviewers.PublicId,
               @RejectionReason = funders.RejectionReason
        FROM dbo.FundingPlatform_Funders AS funders WITH (UPDLOCK, HOLDLOCK)
        LEFT JOIN dbo.FundingPlatform_Users AS reviewers ON reviewers.Id = funders.ReviewedByUserId
        WHERE funders.PublicId = @FunderPublicId;

        IF @FunderId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = ActionCode, @ExistingRequestHash = RequestHash,
                   @ExistingToStatus = ToStatus, @ResultRowVersion = ResultRowVersion,
                   @ContentVersion = ContentVersion,
                   @SubmittedAtUtc = ResultSubmittedAtUtc,
                   @PublishedAtUtc = ResultPublishedAtUtc,
                   @ReviewedAtUtc = ResultReviewedAtUtc,
                   @ReviewedByUserPublicId = ResultReviewedByUserPublicId,
                   @RejectionReason = ResultRejectionReason
            FROM dbo.FundingPlatform_FunderEditorialEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE FunderId = @FunderId AND IdempotencyKeyHash = @IdempotencyKeyHash;
            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'Deactivate' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'deactivated';
                    SET @CurrentStatus = @ExistingToStatus;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus NOT IN (0, 1, 2, 3) SET @Code = N'invalid-transition';
            ELSE
            BEGIN
                DECLARE @Updated TABLE (RowVersion BINARY(8));
                UPDATE dbo.FundingPlatform_Funders
                SET PublicationStatus = 4, IsActive = 0,
                    UpdatedByUserId = @ActorUserId, UpdatedAtUtc = @NowUtc
                OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
                WHERE Id = @FunderId AND RowVersion = @ExpectedRowVersion;
                SELECT @ResultRowVersion = RowVersion FROM @Updated;
                IF @ResultRowVersion IS NULL SET @Code = N'etag-conflict';
                ELSE
                BEGIN
                    INSERT INTO dbo.FundingPlatform_FunderEditorialEvents
                        (EventId, FunderId, ContentVersion, FromStatus, ToStatus, ActionCode,
                         ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                         ResultRowVersion, ResultCompleteness, ResultSubmittedAtUtc,
                         ResultPublishedAtUtc, ResultReviewedAtUtc,
                         ResultReviewedByUserPublicId, ResultRejectionReason, CreatedAtUtc)
                    VALUES (@EventId, @FunderId, @ContentVersion, @CurrentStatus, 4, N'Deactivate',
                            @ActorUserId, NULLIF(LTRIM(RTRIM(@Reason)), N''),
                            @IdempotencyKeyHash, @RequestHash, @ResultRowVersion, NULL,
                            @SubmittedAtUtc, @PublishedAtUtc, @ReviewedAtUtc,
                            @ReviewedByUserPublicId, @RejectionReason, @NowUtc);
                    INSERT INTO dbo.FundingPlatform_OutboxMessages
                        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                         OccurredAtUtc, AvailableAtUtc)
                    SELECT @EventId, N'FunderDeactivated', N'Funder', CONVERT(NVARCHAR(100), @FunderId),
                           (SELECT @EventId AS eventId, @FunderId AS funderId,
                                   @FunderPublicId AS funderPublicId, @ContentVersion AS contentVersion,
                                   @CurrentStatus AS fromStatus, 4 AS toStatus
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                    SET @Succeeded = 1; SET @Code = N'deactivated'; SET @CurrentStatus = 4;
                END;
            END;
        END;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_FunderDeactivate;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, CAST(NULL AS DECIMAL(5,2)) AS Completeness,
           @FunderPublicId AS FunderPublicId, @ContentVersion AS ContentVersion,
           @CurrentStatus AS PublicationStatus, @SubmittedAtUtc AS SubmittedAtUtc,
           @PublishedAtUtc AS PublishedAtUtc, @ReviewedAtUtc AS ReviewedAtUtc,
           @ReviewedByUserPublicId AS ReviewedByUserPublicId,
           @RejectionReason AS RejectionReason,
           COALESCE(@ResultRowVersion, @CurrentRowVersion) AS RowVersion, @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Admin_List
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @Query NVARCHAR(300) = NULL,
    @PublicationStatus TINYINT = NULL,
    @IncludeInactive BIT = 0,
    @PageNumber INT = 1,
    @PageSize INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    IF @PageNumber < 1 THROW 51603, N'PageNumber must be at least 1.', 1;
    IF @PageSize < 1 OR @PageSize > 100
        THROW 51604, N'PageSize must be between 1 and 100.', 1;
    IF @PublicationStatus IS NOT NULL AND @PublicationStatus NOT BETWEEN 0 AND 4
        THROW 51605, N'PublicationStatus is invalid.', 1;

    DECLARE @QueryLike NVARCHAR(302) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Query)), N'') IS NULL THEN NULL
             ELSE N'%' + LTRIM(RTRIM(@Query)) + N'%' END;

    SELECT COUNT_BIG(1) AS TotalCount
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    WHERE (@IncludeInactive = 1 OR opportunities.IsActive = 1)
      AND (@PublicationStatus IS NULL OR opportunities.PublicationStatus = @PublicationStatus)
      AND (@QueryLike IS NULL OR opportunities.Title LIKE @QueryLike
           OR opportunities.SponsorName LIKE @QueryLike OR opportunities.Slug LIKE @QueryLike);

    SELECT opportunities.PublicId AS FundingOpportunityPublicId,
           opportunities.Slug, opportunities.Title, opportunities.Summary,
           opportunities.SponsorName, opportunities.PublicationStatus,
           opportunities.IsActive, opportunities.OpenDate, opportunities.CloseDate,
           opportunities.Currency, opportunities.MinAmount, opportunities.MaxAmount,
           opportunities.DataQualityScore, opportunities.ContentVersion,
           opportunities.SubmittedAtUtc, opportunities.PublishedAtUtc,
           opportunities.ReviewedAtUtc, reviewers.PublicId AS ReviewedByUserPublicId,
           opportunities.RejectionReason, sourceLink.SourceName, sourceLink.SourceUrl,
           opportunities.LastVerifiedAtUtc, opportunities.CreatedAtUtc,
           opportunities.UpdatedAtUtc, opportunities.RowVersion
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    LEFT JOIN dbo.FundingPlatform_Users AS reviewers ON reviewers.Id = opportunities.ReviewedByUserId
    OUTER APPLY
    (
        SELECT TOP (1) sources.Name AS SourceName, links.SourceUrl
        FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
        INNER JOIN dbo.FundingPlatform_FundingSources AS sources ON sources.Id = links.FundingSourceId
        WHERE links.FundingOpportunityId = opportunities.Id AND links.IsActive = 1
        ORDER BY links.IsPrimary DESC, links.Id
    ) AS sourceLink
    WHERE (@IncludeInactive = 1 OR opportunities.IsActive = 1)
      AND (@PublicationStatus IS NULL OR opportunities.PublicationStatus = @PublicationStatus)
      AND (@QueryLike IS NULL OR opportunities.Title LIKE @QueryLike
           OR opportunities.SponsorName LIKE @QueryLike OR opportunities.Slug LIKE @QueryLike)
    ORDER BY opportunities.UpdatedAtUtc DESC, opportunities.Id DESC
    OFFSET ((@PageNumber - 1) * @PageSize) ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Admin_Get
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FundingOpportunityPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;

    DECLARE @OpportunityId BIGINT;
    SELECT @OpportunityId = Id FROM dbo.FundingPlatform_FundingOpportunities
    WHERE PublicId = @FundingOpportunityPublicId;
    IF @OpportunityId IS NULL THROW 51608, N'Funding opportunity was not found.', 1;

    SELECT opportunities.PublicId AS FundingOpportunityPublicId,
           opportunities.Slug, opportunities.Title, opportunities.Description,
           opportunities.Summary, opportunities.SponsorName, opportunities.SponsorUrl,
           opportunities.ApplicationUrl, opportunities.IssuerCountryId,
           opportunities.FundingTypeId, opportunities.Currency,
           opportunities.MinAmount, opportunities.MaxAmount, opportunities.AmountStatus,
           opportunities.OpenDate, opportunities.CloseDate, opportunities.CloseAtUtc,
           opportunities.DeadlineTimeZoneId, opportunities.DeadlineType,
           opportunities.DeadlinePrecision, opportunities.EligibilityDescription,
           opportunities.Requirements, opportunities.Objectives,
           opportunities.AllowedActivities, opportunities.ExcludedActivities,
           opportunities.Restrictions, opportunities.TargetOrganizationsDescription,
           opportunities.TargetPopulationsDescription, opportunities.MinimumOperatingYears,
           opportunities.RequiresLegalEntity, opportunities.RequiresPriorExperience,
           opportunities.RequiresCofunding, opportunities.CofundingPercentage,
           opportunities.GeographicScope, opportunities.RemoteApplication,
           opportunities.PublicationStatus, opportunities.SubmittedAtUtc,
           opportunities.PublishedAtUtc, opportunities.ReviewedAtUtc,
           reviewers.PublicId AS ReviewedByUserPublicId, opportunities.RejectionReason,
           opportunities.LastVerifiedAtUtc, opportunities.DataQualityScore,
           opportunities.ContentVersion, opportunities.IsActive,
           opportunities.CreatedAtUtc, opportunities.UpdatedAtUtc, opportunities.RowVersion
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    LEFT JOIN dbo.FundingPlatform_Users AS reviewers ON reviewers.Id = opportunities.ReviewedByUserId
    WHERE opportunities.Id = @OpportunityId;

    SELECT links.CountryId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityCountries AS links
    INNER JOIN dbo.FundingPlatform_Countries AS countries
        ON countries.Id = links.CountryId AND countries.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.CountryId;
    SELECT links.RegionId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityRegions AS links
    INNER JOIN dbo.FundingPlatform_Regions AS regions
        ON regions.Id = links.RegionId AND regions.IsActive = 1
    INNER JOIN dbo.FundingPlatform_Countries AS countries
        ON countries.Id = regions.CountryId AND countries.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.RegionId;
    SELECT links.FundingCategoryId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityCategories AS links
    INNER JOIN dbo.FundingPlatform_FundingCategories AS categories
        ON categories.Id = links.FundingCategoryId AND categories.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.FundingCategoryId;
    SELECT links.BeneficiaryTypeId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes AS links
    INNER JOIN dbo.FundingPlatform_BeneficiaryTypes AS beneficiaryTypes
        ON beneficiaryTypes.Id = links.BeneficiaryTypeId AND beneficiaryTypes.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.BeneficiaryTypeId;
    SELECT links.ProjectTypeId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityProjectTypes AS links
    INNER JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
        ON projectTypes.Id = links.ProjectTypeId AND projectTypes.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.ProjectTypeId;

    SELECT funders.PublicId AS FunderPublicId, funders.Slug, funders.Name, links.Role
    FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
    INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
    WHERE links.FundingOpportunityId = @OpportunityId AND links.IsActive = 1
    ORDER BY links.Role, funders.Name, funders.Id;

    SELECT evidence.PublicId AS EvidencePublicId, evidence.FieldPath, evidence.ValueJson,
           evidence.ExtractionMethod, evidence.EvidenceText, evidence.SourceLocator,
           evidence.Confidence, evidence.IsSelected, evidence.IsManualLock,
           creators.PublicId AS CreatedByUserPublicId, evidence.CreatedAtUtc
    FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
    LEFT JOIN dbo.FundingPlatform_Users AS creators ON creators.Id = evidence.CreatedByUserId
    WHERE evidence.FundingOpportunityId = @OpportunityId
    ORDER BY evidence.FieldPath, evidence.IsSelected DESC, evidence.CreatedAtUtc DESC, evidence.Id DESC;

    SELECT links.FundingSourceId, sources.Name AS SourceName, links.ExternalId,
           links.SourceUrl, links.FirstSeenAtUtc, links.LastSeenAtUtc,
           links.IsPrimary, links.IsActive
    FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
    INNER JOIN dbo.FundingPlatform_FundingSources AS sources ON sources.Id = links.FundingSourceId
    WHERE links.FundingOpportunityId = @OpportunityId
    ORDER BY links.IsActive DESC, links.IsPrimary DESC, links.Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Public_List
    @Query NVARCHAR(300) = NULL,
    @PageNumber INT = 1,
    @PageSize INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    IF @PageNumber < 1 THROW 51603, N'PageNumber must be at least 1.', 1;
    IF @PageSize < 1 OR @PageSize > 100
        THROW 51604, N'PageSize must be between 1 and 100.', 1;
    DECLARE @QueryLike NVARCHAR(302) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Query)), N'') IS NULL THEN NULL
             ELSE N'%' + LTRIM(RTRIM(@Query)) + N'%' END;

    SELECT COUNT_BIG(1) AS TotalCount
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    WHERE opportunities.PublicationStatus = 2 AND opportunities.IsActive = 1
      AND EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs() AS catalogs
           WHERE catalogs.FundingOpportunityId = opportunities.Id)
      AND (@QueryLike IS NULL OR opportunities.Title LIKE @QueryLike
           OR opportunities.SponsorName LIKE @QueryLike OR opportunities.Summary LIKE @QueryLike)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCategories AS categories
           WHERE categories.FundingOpportunityId = opportunities.Id)
      AND
          ((opportunities.GeographicScope = 1 AND EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS countries
               WHERE countries.FundingOpportunityId = opportunities.Id))
           OR (opportunities.GeographicScope = 2
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS countries
                    WHERE countries.FundingOpportunityId = opportunities.Id)
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions AS regions
                    WHERE regions.FundingOpportunityId = opportunities.Id)))
      AND NOT EXISTS
          (SELECT required.FieldPath
           FROM (VALUES (N'/title'), (N'/description'),
                        (N'/eligibilityDescription'), (N'/closeDate')) AS required(FieldPath)
           WHERE NOT EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
              WHERE evidence.FundingOpportunityId = opportunities.Id
                AND evidence.FieldPath = required.FieldPath AND evidence.IsSelected = 1
                AND JSON_VALUE(evidence.ValueJson, '$.status') IN (N'known', N'unknown')))
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
           INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
           WHERE links.FundingOpportunityId = opportunities.Id AND links.Role = 1
             AND links.IsActive = 1 AND funders.PublicationStatus = 2 AND funders.IsActive = 1)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
           INNER JOIN dbo.FundingPlatform_FundingSources AS sources ON sources.Id = links.FundingSourceId
           WHERE links.FundingOpportunityId = opportunities.Id AND links.IsPrimary = 1
             AND links.IsActive = 1 AND sources.IsEnabled = 1
             AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL);

    SELECT opportunities.PublicId AS FundingOpportunityPublicId,
           opportunities.Slug, opportunities.Title, opportunities.Summary,
           opportunities.SponsorName, opportunities.Currency,
           opportunities.MinAmount, opportunities.MaxAmount,
           opportunities.OpenDate, opportunities.CloseDate,
           opportunities.PublishedAtUtc, opportunities.DataQualityScore,
           primaryFunder.FunderPublicId AS PrimaryFunderPublicId,
           primaryFunder.FunderName AS PrimaryFunderName,
           primarySource.SourceName, primarySource.SourceUrl
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    CROSS APPLY
    (
        SELECT funders.PublicId AS FunderPublicId, funders.Name AS FunderName
        FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
        INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
        WHERE links.FundingOpportunityId = opportunities.Id AND links.Role = 1
          AND links.IsActive = 1 AND funders.PublicationStatus = 2 AND funders.IsActive = 1
    ) AS primaryFunder
    CROSS APPLY
    (
        SELECT sources.Name AS SourceName, links.SourceUrl
        FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
        INNER JOIN dbo.FundingPlatform_FundingSources AS sources ON sources.Id = links.FundingSourceId
        WHERE links.FundingOpportunityId = opportunities.Id AND links.IsPrimary = 1
          AND links.IsActive = 1 AND sources.IsEnabled = 1
          AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL
    ) AS primarySource
    WHERE opportunities.PublicationStatus = 2 AND opportunities.IsActive = 1
      AND EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs() AS catalogs
           WHERE catalogs.FundingOpportunityId = opportunities.Id)
      AND (@QueryLike IS NULL OR opportunities.Title LIKE @QueryLike
           OR opportunities.SponsorName LIKE @QueryLike OR opportunities.Summary LIKE @QueryLike)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCategories AS categories
           WHERE categories.FundingOpportunityId = opportunities.Id)
      AND
          ((opportunities.GeographicScope = 1 AND EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS countries
               WHERE countries.FundingOpportunityId = opportunities.Id))
           OR (opportunities.GeographicScope = 2
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS countries
                    WHERE countries.FundingOpportunityId = opportunities.Id)
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions AS regions
                    WHERE regions.FundingOpportunityId = opportunities.Id)))
      AND NOT EXISTS
          (SELECT required.FieldPath
           FROM (VALUES (N'/title'), (N'/description'),
                        (N'/eligibilityDescription'), (N'/closeDate')) AS required(FieldPath)
           WHERE NOT EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
              WHERE evidence.FundingOpportunityId = opportunities.Id
                AND evidence.FieldPath = required.FieldPath AND evidence.IsSelected = 1
                AND JSON_VALUE(evidence.ValueJson, '$.status') IN (N'known', N'unknown')))
    ORDER BY CASE WHEN opportunities.CloseDate IS NULL THEN 1 ELSE 0 END,
             opportunities.CloseDate, opportunities.Id DESC
    OFFSET ((@PageNumber - 1) * @PageSize) ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Public_GetBySlug
    @Slug NVARCHAR(320)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @OpportunityId BIGINT;
    SELECT @OpportunityId = opportunities.Id
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    WHERE opportunities.Slug = @Slug AND opportunities.PublicationStatus = 2
      AND opportunities.IsActive = 1
      AND EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs() AS catalogs
           WHERE catalogs.FundingOpportunityId = opportunities.Id)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCategories AS categories
           WHERE categories.FundingOpportunityId = opportunities.Id)
      AND
          ((opportunities.GeographicScope = 1 AND EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS countries
               WHERE countries.FundingOpportunityId = opportunities.Id))
           OR (opportunities.GeographicScope = 2
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS countries
                    WHERE countries.FundingOpportunityId = opportunities.Id)
               AND NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions AS regions
                    WHERE regions.FundingOpportunityId = opportunities.Id)))
      AND NOT EXISTS
          (SELECT required.FieldPath
           FROM (VALUES (N'/title'), (N'/description'),
                        (N'/eligibilityDescription'), (N'/closeDate')) AS required(FieldPath)
           WHERE NOT EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
              WHERE evidence.FundingOpportunityId = opportunities.Id
                AND evidence.FieldPath = required.FieldPath AND evidence.IsSelected = 1
                AND JSON_VALUE(evidence.ValueJson, '$.status') IN (N'known', N'unknown')))
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
           INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
           WHERE links.FundingOpportunityId = opportunities.Id AND links.Role = 1
             AND links.IsActive = 1 AND funders.PublicationStatus = 2 AND funders.IsActive = 1)
      AND EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
           INNER JOIN dbo.FundingPlatform_FundingSources AS sources ON sources.Id = links.FundingSourceId
           WHERE links.FundingOpportunityId = opportunities.Id AND links.IsPrimary = 1
             AND links.IsActive = 1 AND sources.IsEnabled = 1
             AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL);

    SELECT opportunities.PublicId AS FundingOpportunityPublicId,
           opportunities.Slug, opportunities.Title, opportunities.Description,
           opportunities.Summary, opportunities.SponsorName, opportunities.SponsorUrl,
           opportunities.ApplicationUrl, opportunities.IssuerCountryId,
           opportunities.FundingTypeId, opportunities.Currency,
           opportunities.MinAmount, opportunities.MaxAmount, opportunities.AmountStatus,
           opportunities.OpenDate, opportunities.CloseDate, opportunities.CloseAtUtc,
           opportunities.DeadlineTimeZoneId, opportunities.DeadlineType,
           opportunities.DeadlinePrecision, opportunities.EligibilityDescription,
           opportunities.Requirements, opportunities.Objectives,
           opportunities.AllowedActivities, opportunities.ExcludedActivities,
           opportunities.Restrictions, opportunities.TargetOrganizationsDescription,
           opportunities.TargetPopulationsDescription, opportunities.MinimumOperatingYears,
           opportunities.RequiresLegalEntity, opportunities.RequiresPriorExperience,
           opportunities.RequiresCofunding, opportunities.CofundingPercentage,
           opportunities.GeographicScope, opportunities.RemoteApplication,
           opportunities.LastVerifiedAtUtc, opportunities.DataQualityScore,
           opportunities.ContentVersion, opportunities.PublishedAtUtc,
           primaryFunder.FunderPublicId AS PrimaryFunderPublicId,
           primaryFunder.FunderSlug AS PrimaryFunderSlug,
           primaryFunder.FunderName AS PrimaryFunderName,
           primarySource.SourceName, primarySource.SourceUrl
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    CROSS APPLY
    (
        SELECT funders.PublicId AS FunderPublicId, funders.Slug AS FunderSlug,
               funders.Name AS FunderName
        FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
        INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
        WHERE links.FundingOpportunityId = opportunities.Id AND links.Role = 1
          AND links.IsActive = 1 AND funders.PublicationStatus = 2 AND funders.IsActive = 1
    ) AS primaryFunder
    CROSS APPLY
    (
        SELECT sources.Name AS SourceName, links.SourceUrl
        FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
        INNER JOIN dbo.FundingPlatform_FundingSources AS sources ON sources.Id = links.FundingSourceId
        WHERE links.FundingOpportunityId = opportunities.Id AND links.IsPrimary = 1
          AND links.IsActive = 1 AND sources.IsEnabled = 1
          AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL
    ) AS primarySource
    WHERE opportunities.Id = @OpportunityId;

    SELECT links.CountryId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityCountries AS links
    INNER JOIN dbo.FundingPlatform_Countries AS countries
        ON countries.Id = links.CountryId AND countries.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.CountryId;
    SELECT links.RegionId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityRegions AS links
    INNER JOIN dbo.FundingPlatform_Regions AS regions
        ON regions.Id = links.RegionId AND regions.IsActive = 1
    INNER JOIN dbo.FundingPlatform_Countries AS countries
        ON countries.Id = regions.CountryId AND countries.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.RegionId;
    SELECT links.FundingCategoryId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityCategories AS links
    INNER JOIN dbo.FundingPlatform_FundingCategories AS categories
        ON categories.Id = links.FundingCategoryId AND categories.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.FundingCategoryId;
    SELECT links.BeneficiaryTypeId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes AS links
    INNER JOIN dbo.FundingPlatform_BeneficiaryTypes AS beneficiaryTypes
        ON beneficiaryTypes.Id = links.BeneficiaryTypeId AND beneficiaryTypes.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.BeneficiaryTypeId;
    SELECT links.ProjectTypeId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityProjectTypes AS links
    INNER JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
        ON projectTypes.Id = links.ProjectTypeId AND projectTypes.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.ProjectTypeId;
    SELECT funders.PublicId AS FunderPublicId, funders.Slug, funders.Name, links.Role
    FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
    INNER JOIN dbo.FundingPlatform_Funders AS funders
        ON funders.Id = links.FunderId AND funders.PublicationStatus = 2 AND funders.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId AND links.IsActive = 1
    ORDER BY links.Role, funders.Name, funders.Id;
    SELECT links.FundingSourceId, sources.Name AS SourceName, links.ExternalId,
           links.SourceUrl, links.FirstSeenAtUtc, links.LastSeenAtUtc,
           links.IsPrimary, links.IsActive
    FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
    INNER JOIN dbo.FundingPlatform_FundingSources AS sources
        ON sources.Id = links.FundingSourceId AND sources.IsEnabled = 1
    WHERE links.FundingOpportunityId = @OpportunityId AND links.IsActive = 1
    ORDER BY links.IsPrimary DESC, links.Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Create
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @Slug NVARCHAR(320), @Title NVARCHAR(350),
    @Description NVARCHAR(MAX) = NULL, @Summary NVARCHAR(2000) = NULL,
    @SponsorName NVARCHAR(300), @SponsorUrl NVARCHAR(2048) = NULL,
    @ApplicationUrl NVARCHAR(2048) = NULL, @IssuerCountryId SMALLINT = NULL,
    @FundingTypeId SMALLINT = NULL, @Currency CHAR(3) = NULL,
    @MinAmount DECIMAL(19,4) = NULL, @MaxAmount DECIMAL(19,4) = NULL,
    @AmountStatus TINYINT, @OpenDate DATE = NULL, @CloseDate DATE = NULL,
    @CloseAtUtc DATETIME2(3) = NULL, @DeadlineTimeZoneId NVARCHAR(100) = NULL,
    @DeadlineType TINYINT, @DeadlinePrecision TINYINT,
    @EligibilityDescription NVARCHAR(MAX) = NULL, @Requirements NVARCHAR(MAX) = NULL,
    @Objectives NVARCHAR(MAX) = NULL, @AllowedActivities NVARCHAR(MAX) = NULL,
    @ExcludedActivities NVARCHAR(MAX) = NULL, @Restrictions NVARCHAR(MAX) = NULL,
    @TargetOrganizationsDescription NVARCHAR(2000) = NULL,
    @TargetPopulationsDescription NVARCHAR(2000) = NULL,
    @MinimumOperatingYears SMALLINT = NULL, @RequiresLegalEntity BIT = NULL,
    @RequiresPriorExperience BIT = NULL, @RequiresCofunding BIT = NULL,
    @CofundingPercentage DECIMAL(5,2) = NULL, @GeographicScope TINYINT,
    @RemoteApplication TINYINT, @LastVerifiedAtUtc DATETIME2(3) = NULL,
    @DataQualityScore DECIMAL(5,2),
    @FundingSourceId INT, @ExternalId NVARCHAR(250) = NULL,
    @SourceItemKeyHash BINARY(32), @SourceUrl NVARCHAR(2048),
    @CanonicalUrlHash BINARY(32) = NULL,
    @SnapshotJson NVARCHAR(MAX), @ContentHash BINARY(32),
    @CountryIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @RegionIds dbo.FundingPlatform_IntIdList READONLY,
    @CategoryIds dbo.FundingPlatform_IntIdList READONLY,
    @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @FunderLinksJson NVARCHAR(MAX), @EvidenceJson NVARCHAR(MAX) = N'[]',
    @IdempotencyKeyHash BINARY(32), @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    IF ISJSON(@SnapshotJson) <> 1 OR LEFT(LTRIM(@SnapshotJson), 1) <> N'{'
        THROW 51609, N'SnapshotJson must be a JSON object.', 1;
    IF ISJSON(COALESCE(@FunderLinksJson, N'[]')) <> 1
       OR LEFT(LTRIM(COALESCE(@FunderLinksJson, N'[]')), 1) <> N'['
        THROW 51610, N'FunderLinksJson must be a JSON array.', 1;
    IF ISJSON(COALESCE(@EvidenceJson, N'[]')) <> 1
       OR LEFT(LTRIM(COALESCE(@EvidenceJson, N'[]')), 1) <> N'['
        THROW 51611, N'EvidenceJson must be a JSON array.', 1;

    DECLARE @ActorUserId BIGINT, @OpportunityId BIGINT, @OpportunityPublicId UNIQUEIDENTIFIER;
    DECLARE @RowVersion BINARY(8), @ExistingRequestHash BINARY(32), @SourceLinkId BIGINT;
    DECLARE @Code NVARCHAR(50) = N'created', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @RawFunderCount INT =
        (SELECT COUNT(1) FROM OPENJSON(COALESCE(@FunderLinksJson, N'[]')));
    DECLARE @RawEvidenceCount INT =
        (SELECT COUNT(1) FROM OPENJSON(COALESCE(@EvidenceJson, N'[]')));
    DECLARE @RequestedFunders TABLE
    (
        FunderPublicId UNIQUEIDENTIFIER NOT NULL,
        Role TINYINT NOT NULL,
        FunderId BIGINT NULL,
        PRIMARY KEY (FunderPublicId)
    );
    DECLARE @ExtraEvidence TABLE
    (
        FieldPath NVARCHAR(200) NOT NULL PRIMARY KEY,
        ValueJson NVARCHAR(MAX) NOT NULL,
        EvidenceText NVARCHAR(2000) NULL,
        SourceLocator NVARCHAR(500) NULL,
        Confidence DECIMAL(5,2) NULL,
        IsManualLock BIT NOT NULL
    );

    INSERT INTO @RequestedFunders (FunderPublicId, Role)
    SELECT TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(items.value, '$.funderPublicId')),
           MIN(TRY_CONVERT(TINYINT, JSON_VALUE(items.value, '$.role')))
    FROM OPENJSON(COALESCE(@FunderLinksJson, N'[]')) AS items
    WHERE TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(items.value, '$.funderPublicId')) IS NOT NULL
      AND TRY_CONVERT(TINYINT, JSON_VALUE(items.value, '$.role')) BETWEEN 1 AND 3
    GROUP BY TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(items.value, '$.funderPublicId'))
    HAVING COUNT_BIG(1) = 1;

    INSERT INTO @ExtraEvidence
        (FieldPath, ValueJson, EvidenceText, SourceLocator, Confidence, IsManualLock)
    SELECT JSON_VALUE(items.value, '$.fieldPath'),
           MAX(JSON_QUERY(items.value, '$.valueJson')),
           MAX(JSON_VALUE(items.value, '$.evidenceText')),
           MAX(JSON_VALUE(items.value, '$.sourceLocator')),
           MAX(TRY_CONVERT(DECIMAL(5,2), JSON_VALUE(items.value, '$.confidence'))),
           MAX(CONVERT(TINYINT,
               COALESCE(TRY_CONVERT(BIT, JSON_VALUE(items.value, '$.isManualLock')), 1)))
    FROM OPENJSON(COALESCE(@EvidenceJson, N'[]')) AS items
    WHERE LEFT(JSON_VALUE(items.value, '$.fieldPath'), 1) = N'/'
      AND LEN(JSON_VALUE(items.value, '$.fieldPath')) BETWEEN 2 AND 200
      AND JSON_QUERY(items.value, '$.valueJson') IS NOT NULL
      AND LEFT(LTRIM(JSON_QUERY(items.value, '$.valueJson')), 1) = N'{'
      AND (JSON_VALUE(items.value, '$.evidenceText') IS NULL
           OR LEN(JSON_VALUE(items.value, '$.evidenceText')) <= 2000)
      AND (JSON_VALUE(items.value, '$.sourceLocator') IS NULL
           OR LEN(JSON_VALUE(items.value, '$.sourceLocator')) <= 500)
      AND (JSON_VALUE(items.value, '$.confidence') IS NULL
           OR TRY_CONVERT(DECIMAL(5,2), JSON_VALUE(items.value, '$.confidence')) BETWEEN 0 AND 100)
      AND (JSON_VALUE(items.value, '$.isManualLock') IS NULL
           OR TRY_CONVERT(BIT, JSON_VALUE(items.value, '$.isManualLock')) IS NOT NULL)
      AND JSON_VALUE(items.value, '$.fieldPath') NOT IN
          (N'/title', N'/description', N'/eligibilityDescription', N'/closeDate', N'/sponsorName')
    GROUP BY JSON_VALUE(items.value, '$.fieldPath')
    HAVING COUNT_BIG(1) = 1;

    IF NULLIF(LTRIM(RTRIM(@Slug)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@Title)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@SponsorName)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@SourceUrl)), N'') IS NULL
       OR @RawFunderCount <> (SELECT COUNT(1) FROM @RequestedFunders)
       OR @RawEvidenceCount <> (SELECT COUNT(1) FROM @ExtraEvidence)
       OR (SELECT COUNT(1) FROM @RequestedFunders WHERE Role = 1) <> 1
       OR @AmountStatus NOT BETWEEN 0 AND 2
       OR (@AmountStatus = 1 AND (@Currency IS NULL OR (@MinAmount IS NULL AND @MaxAmount IS NULL)))
       OR (@AmountStatus IN (0, 2) AND (@Currency IS NOT NULL OR @MinAmount IS NOT NULL OR @MaxAmount IS NOT NULL))
       OR @MinAmount < 0 OR @MaxAmount < COALESCE(@MinAmount, 0)
       OR @DeadlineType NOT BETWEEN 0 AND 2 OR @DeadlinePrecision NOT BETWEEN 0 AND 2
       OR (@DeadlineType = 0 AND (@DeadlinePrecision <> 0 OR @CloseAtUtc IS NOT NULL))
       OR (@DeadlineType = 2 AND (@DeadlinePrecision <> 0 OR @CloseDate IS NOT NULL OR @CloseAtUtc IS NOT NULL))
       OR (@DeadlineType = 1 AND @DeadlinePrecision NOT IN (1, 2))
       OR (@DeadlineType = 1 AND @DeadlinePrecision = 1 AND (@CloseDate IS NULL OR @CloseAtUtc IS NOT NULL))
       OR (@DeadlineType = 1 AND @DeadlinePrecision = 2
           AND (@CloseDate IS NULL OR @CloseAtUtc IS NULL OR @DeadlineTimeZoneId IS NULL))
       OR (@OpenDate IS NOT NULL AND @CloseDate IS NOT NULL AND @OpenDate > @CloseDate)
       OR @GeographicScope NOT BETWEEN 0 AND 2 OR @RemoteApplication NOT BETWEEN 0 AND 2
       OR (@GeographicScope = 0
           AND (EXISTS (SELECT 1 FROM @CountryIds) OR EXISTS (SELECT 1 FROM @RegionIds)))
       OR (@GeographicScope = 1 AND NOT EXISTS (SELECT 1 FROM @CountryIds))
       OR (@GeographicScope = 2
           AND (EXISTS (SELECT 1 FROM @CountryIds) OR EXISTS (SELECT 1 FROM @RegionIds)))
       OR @DataQualityScore NOT BETWEEN 0 AND 100
       OR @MinimumOperatingYears < 0
       OR @CofundingPercentage < 0 OR @CofundingPercentage > 100
       OR (@RequiresCofunding IS NULL AND @CofundingPercentage IS NOT NULL)
       OR (@RequiresCofunding = 0 AND COALESCE(@CofundingPercentage, 0) <> 0)
       OR (@RequiresCofunding = 1 AND COALESCE(@CofundingPercentage, 0) <= 0)
       OR (@LastVerifiedAtUtc IS NOT NULL
           AND @LastVerifiedAtUtc > DATEADD(MINUTE, 5, SYSUTCDATETIME()))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               CAST(NULL AS UNIQUEIDENTIFIER) AS FundingOpportunityPublicId,
               CAST(NULL AS INT) AS ContentVersion, CAST(NULL AS TINYINT) AS PublicationStatus,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_OppCreate;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @ActorUserId = Id FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;
        SELECT @OpportunityId = events.FundingOpportunityId,
               @ExistingRequestHash = events.RequestHash, @RowVersion = events.ResultRowVersion
        FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents AS events WITH (UPDLOCK, HOLDLOCK)
        WHERE events.ActorUserId = @ActorUserId AND events.ActionCode = N'Create'
          AND events.IdempotencyKeyHash = @IdempotencyKeyHash;

        IF @OpportunityId IS NOT NULL
        BEGIN
            SELECT @OpportunityPublicId = PublicId
            FROM dbo.FundingPlatform_FundingOpportunities WHERE Id = @OpportunityId;
            IF @ExistingRequestHash = @RequestHash
            BEGIN
                SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'created';
            END
            ELSE SET @Code = N'idempotency-conflict';
        END
        ELSE
        BEGIN
            UPDATE requested SET FunderId = funders.Id
            FROM @RequestedFunders AS requested
            INNER JOIN dbo.FundingPlatform_Funders AS funders WITH (UPDLOCK, HOLDLOCK)
                ON funders.PublicId = requested.FunderPublicId
               AND funders.IsActive = 1 AND funders.PublicationStatus <> 4;

            IF EXISTS (SELECT 1 FROM @RequestedFunders WHERE FunderId IS NULL)
                SET @Code = N'funder-not-found';
            ELSE IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingSources
                                WHERE Id = @FundingSourceId AND IsEnabled = 1)
                SET @Code = N'source-disabled';
            ELSE IF (@IssuerCountryId IS NOT NULL AND NOT EXISTS
                     (SELECT 1 FROM dbo.FundingPlatform_Countries
                      WHERE Id = @IssuerCountryId AND IsActive = 1))
                 OR (@FundingTypeId IS NOT NULL AND NOT EXISTS
                     (SELECT 1 FROM dbo.FundingPlatform_FundingTypes
                      WHERE Id = @FundingTypeId AND IsActive = 1))
                 OR (@Currency IS NOT NULL AND NOT EXISTS
                     (SELECT 1 FROM dbo.FundingPlatform_Currencies
                      WHERE Code = @Currency AND IsActive = 1))
                 OR EXISTS (SELECT 1 FROM @CountryIds AS selected
                            LEFT JOIN dbo.FundingPlatform_Countries AS catalog
                                ON catalog.Id = selected.Id AND catalog.IsActive = 1
                            WHERE catalog.Id IS NULL)
                 OR EXISTS (SELECT 1 FROM @CategoryIds AS selected
                            LEFT JOIN dbo.FundingPlatform_FundingCategories AS catalog
                                ON catalog.Id = selected.Id AND catalog.IsActive = 1
                            WHERE catalog.Id IS NULL)
                 OR EXISTS (SELECT 1 FROM @BeneficiaryTypeIds AS selected
                            LEFT JOIN dbo.FundingPlatform_BeneficiaryTypes AS catalog
                                ON catalog.Id = selected.Id AND catalog.IsActive = 1
                            WHERE catalog.Id IS NULL)
                 OR EXISTS (SELECT 1 FROM @ProjectTypeIds AS selected
                            LEFT JOIN dbo.FundingPlatform_ProjectTypes AS catalog
                                ON catalog.Id = selected.Id AND catalog.IsActive = 1
                            WHERE catalog.Id IS NULL)
                SET @Code = N'invalid-document';
            ELSE IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WITH (UPDLOCK, HOLDLOCK)
                            WHERE Slug = LTRIM(RTRIM(@Slug)))
                SET @Code = N'slug-conflict';
            ELSE IF EXISTS
            (
                SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks WITH (UPDLOCK, HOLDLOCK)
                WHERE FundingSourceId = @FundingSourceId
                  AND (SourceItemKeyHash = @SourceItemKeyHash
                       OR (@ExternalId IS NOT NULL AND ExternalId = @ExternalId))
            ) SET @Code = N'source-link-conflict';
            ELSE IF EXISTS
            (
                SELECT 1 FROM @RegionIds AS selected
                LEFT JOIN dbo.FundingPlatform_Regions AS regions
                    ON regions.Id = selected.Id AND regions.IsActive = 1
                WHERE regions.Id IS NULL
                   OR NOT EXISTS (SELECT 1 FROM @CountryIds AS countries WHERE countries.Id = regions.CountryId)
            ) SET @Code = N'invalid-document';
            ELSE
            BEGIN
                DECLARE @InsertedOpportunity TABLE
                    (Id BIGINT, PublicId UNIQUEIDENTIFIER, RowVersion BINARY(8));
                INSERT INTO dbo.FundingPlatform_FundingOpportunities
                (
                    Slug, Title, Description, Summary, SponsorName, SponsorUrl, ApplicationUrl,
                    IssuerCountryId, FundingTypeId, Currency, MinAmount, MaxAmount, AmountStatus,
                    OpenDate, CloseDate, CloseAtUtc, DeadlineTimeZoneId, DeadlineType,
                    DeadlinePrecision, EligibilityDescription, Requirements, Objectives,
                    AllowedActivities, ExcludedActivities, Restrictions,
                    TargetOrganizationsDescription, TargetPopulationsDescription,
                    MinimumOperatingYears, RequiresLegalEntity, RequiresPriorExperience,
                    RequiresCofunding, CofundingPercentage, GeographicScope, RemoteApplication,
                    PublicationStatus, PublishedAtUtc, LastVerifiedAtUtc, DataQualityScore,
                    ContentVersion, ContentFingerprint, IsActive, CreatedByUserId, UpdatedByUserId,
                    CreatedAtUtc, UpdatedAtUtc
                )
                OUTPUT inserted.Id, inserted.PublicId, inserted.RowVersion
                    INTO @InsertedOpportunity (Id, PublicId, RowVersion)
                VALUES
                (
                    LTRIM(RTRIM(@Slug)), LTRIM(RTRIM(@Title)), @Description, @Summary,
                    LTRIM(RTRIM(@SponsorName)), @SponsorUrl, @ApplicationUrl,
                    @IssuerCountryId, @FundingTypeId, @Currency, @MinAmount, @MaxAmount,
                    @AmountStatus, @OpenDate, @CloseDate, @CloseAtUtc, @DeadlineTimeZoneId,
                    @DeadlineType, @DeadlinePrecision, @EligibilityDescription, @Requirements,
                    @Objectives, @AllowedActivities, @ExcludedActivities, @Restrictions,
                    @TargetOrganizationsDescription, @TargetPopulationsDescription,
                    @MinimumOperatingYears, @RequiresLegalEntity, @RequiresPriorExperience,
                    @RequiresCofunding, @CofundingPercentage, @GeographicScope,
                    @RemoteApplication, 0, NULL, COALESCE(@LastVerifiedAtUtc, @NowUtc),
                    @DataQualityScore, 1,
                    @ContentHash, 1, @ActorUserId, @ActorUserId, @NowUtc, @NowUtc
                );
                SELECT @OpportunityId = Id, @OpportunityPublicId = PublicId, @RowVersion = RowVersion
                FROM @InsertedOpportunity;

                DECLARE @InsertedSourceLink TABLE (Id BIGINT);
                INSERT INTO dbo.FundingPlatform_FundingOpportunitySourceLinks
                    (FundingOpportunityId, FundingSourceId, ExternalId, SourceItemKeyHash,
                     SourceUrl, CanonicalUrlHash, FirstSeenAtUtc, LastSeenAtUtc, IsPrimary, IsActive)
                OUTPUT inserted.Id INTO @InsertedSourceLink (Id)
                VALUES (@OpportunityId, @FundingSourceId, @ExternalId, @SourceItemKeyHash,
                        @SourceUrl, @CanonicalUrlHash, @NowUtc, @NowUtc, 1, 1);
                SELECT @SourceLinkId = Id FROM @InsertedSourceLink;

                INSERT INTO dbo.FundingPlatform_FundingOpportunityCountries
                    (FundingOpportunityId, CountryId)
                SELECT @OpportunityId, Id FROM @CountryIds;
                INSERT INTO dbo.FundingPlatform_FundingOpportunityRegions
                    (FundingOpportunityId, RegionId)
                SELECT @OpportunityId, Id FROM @RegionIds;
                INSERT INTO dbo.FundingPlatform_FundingOpportunityCategories
                    (FundingOpportunityId, FundingCategoryId)
                SELECT @OpportunityId, Id FROM @CategoryIds;
                INSERT INTO dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes
                    (FundingOpportunityId, BeneficiaryTypeId)
                SELECT @OpportunityId, Id FROM @BeneficiaryTypeIds;
                INSERT INTO dbo.FundingPlatform_FundingOpportunityProjectTypes
                    (FundingOpportunityId, ProjectTypeId)
                SELECT @OpportunityId, Id FROM @ProjectTypeIds;

                DECLARE @CriticalEvidence TABLE
                    (FieldPath NVARCHAR(200), ValueText NVARCHAR(MAX), StatusCode NVARCHAR(20),
                     EvidenceText NVARCHAR(2000));
                INSERT INTO @CriticalEvidence VALUES
                    (N'/title', @Title, N'known', LEFT(@Title, 2000)),
                    (N'/description', @Description,
                     CASE WHEN NULLIF(LTRIM(RTRIM(@Description)), N'') IS NULL THEN N'unknown' ELSE N'known' END,
                     LEFT(@Description, 2000)),
                    (N'/eligibilityDescription', @EligibilityDescription,
                     CASE WHEN NULLIF(LTRIM(RTRIM(@EligibilityDescription)), N'') IS NULL THEN N'unknown' ELSE N'known' END,
                     LEFT(@EligibilityDescription, 2000)),
                    (N'/closeDate', CONVERT(NVARCHAR(30), @CloseDate, 23),
                     CASE WHEN @CloseDate IS NULL THEN N'unknown' ELSE N'known' END,
                     CONVERT(NVARCHAR(30), @CloseDate, 23)),
                    (N'/sponsorName', @SponsorName, N'known', LEFT(@SponsorName, 2000));
                INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
                    (FundingOpportunityId, FieldPath, ValueJson, FundingOpportunitySourceLinkId,
                     ExtractionMethod, EvidenceText, SourceLocator, Confidence,
                     IsSelected, IsManualLock, CreatedByUserId, CreatedAtUtc)
                SELECT @OpportunityId, critical.FieldPath,
                       (SELECT critical.ValueText AS [value], critical.StatusCode AS [status]
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
                       @SourceLinkId, 1, critical.EvidenceText, LEFT(@SourceUrl, 500),
                       100, 1, 1, @ActorUserId, @NowUtc
                FROM @CriticalEvidence AS critical;
                INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
                    (FundingOpportunityId, FieldPath, ValueJson, FundingOpportunitySourceLinkId,
                     ExtractionMethod, EvidenceText, SourceLocator, Confidence,
                     IsSelected, IsManualLock, CreatedByUserId, CreatedAtUtc)
                SELECT @OpportunityId, extra.FieldPath, extra.ValueJson, @SourceLinkId, 1,
                       extra.EvidenceText, COALESCE(extra.SourceLocator, LEFT(@SourceUrl, 500)),
                       extra.Confidence, 1, extra.IsManualLock, @ActorUserId, @NowUtc
                FROM @ExtraEvidence AS extra;

                DECLARE @SponsorEvidenceId BIGINT =
                    (SELECT Id FROM dbo.FundingPlatform_FundingFieldEvidence
                     WHERE FundingOpportunityId = @OpportunityId
                       AND FieldPath = N'/sponsorName' AND IsSelected = 1);
                INSERT INTO dbo.FundingPlatform_FundingOpportunityFunders
                    (FundingOpportunityId, FunderId, Role, EvidenceId, IsActive,
                     CreatedAtUtc, UpdatedAtUtc)
                SELECT @OpportunityId, FunderId, Role,
                       CASE WHEN Role = 1 THEN @SponsorEvidenceId ELSE NULL END,
                       1, @NowUtc, @NowUtc
                FROM @RequestedFunders;

                INSERT INTO dbo.FundingPlatform_FundingOpportunityVersions
                    (FundingOpportunityId, ContentVersion, SnapshotJson, ContentHash,
                     CreatedByUserId, CreatedAtUtc)
                VALUES (@OpportunityId, 1, @SnapshotJson, @ContentHash, @ActorUserId, @NowUtc);
                INSERT INTO dbo.FundingPlatform_FundingOpportunityEditorialEvents
                    (EventId, FundingOpportunityId, ContentVersion, FromStatus, ToStatus,
                     ActionCode, ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                     ResultRowVersion, CreatedAtUtc)
                VALUES (@EventId, @OpportunityId, 1, 0, 0, N'Create', @ActorUserId, NULL,
                        @IdempotencyKeyHash, @RequestHash, @RowVersion, @NowUtc);
                INSERT INTO dbo.FundingPlatform_OutboxMessages
                    (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                     OccurredAtUtc, AvailableAtUtc)
                SELECT @EventId, N'FundingOpportunityDraftCreated', N'FundingOpportunity',
                       CONVERT(NVARCHAR(100), @OpportunityId),
                       (SELECT @EventId AS eventId, @OpportunityId AS fundingOpportunityId,
                               @OpportunityPublicId AS fundingOpportunityPublicId, 1 AS contentVersion
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                SET @Succeeded = 1; SET @Code = N'created';
            END;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_OppCreate;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @OpportunityPublicId AS FundingOpportunityPublicId,
           CASE WHEN @OpportunityId IS NULL THEN NULL ELSE 1 END AS ContentVersion,
           CASE WHEN @OpportunityId IS NULL THEN NULL ELSE 0 END AS PublicationStatus,
           @RowVersion AS RowVersion, @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Update
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FundingOpportunityPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @Title NVARCHAR(350), @Description NVARCHAR(MAX) = NULL,
    @Summary NVARCHAR(2000) = NULL, @SponsorName NVARCHAR(300),
    @SponsorUrl NVARCHAR(2048) = NULL, @ApplicationUrl NVARCHAR(2048) = NULL,
    @IssuerCountryId SMALLINT = NULL, @FundingTypeId SMALLINT = NULL,
    @Currency CHAR(3) = NULL, @MinAmount DECIMAL(19,4) = NULL,
    @MaxAmount DECIMAL(19,4) = NULL, @AmountStatus TINYINT,
    @OpenDate DATE = NULL, @CloseDate DATE = NULL, @CloseAtUtc DATETIME2(3) = NULL,
    @DeadlineTimeZoneId NVARCHAR(100) = NULL, @DeadlineType TINYINT,
    @DeadlinePrecision TINYINT, @EligibilityDescription NVARCHAR(MAX) = NULL,
    @Requirements NVARCHAR(MAX) = NULL, @Objectives NVARCHAR(MAX) = NULL,
    @AllowedActivities NVARCHAR(MAX) = NULL, @ExcludedActivities NVARCHAR(MAX) = NULL,
    @Restrictions NVARCHAR(MAX) = NULL,
    @TargetOrganizationsDescription NVARCHAR(2000) = NULL,
    @TargetPopulationsDescription NVARCHAR(2000) = NULL,
    @MinimumOperatingYears SMALLINT = NULL, @RequiresLegalEntity BIT = NULL,
    @RequiresPriorExperience BIT = NULL, @RequiresCofunding BIT = NULL,
    @CofundingPercentage DECIMAL(5,2) = NULL, @GeographicScope TINYINT,
    @RemoteApplication TINYINT, @LastVerifiedAtUtc DATETIME2(3) = NULL,
    @DataQualityScore DECIMAL(5,2),
    @FundingSourceId INT, @ExternalId NVARCHAR(250) = NULL,
    @SourceItemKeyHash BINARY(32), @SourceUrl NVARCHAR(2048),
    @CanonicalUrlHash BINARY(32) = NULL,
    @SnapshotJson NVARCHAR(MAX), @ContentHash BINARY(32),
    @CountryIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @RegionIds dbo.FundingPlatform_IntIdList READONLY,
    @CategoryIds dbo.FundingPlatform_IntIdList READONLY,
    @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @FunderLinksJson NVARCHAR(MAX), @EvidenceJson NVARCHAR(MAX) = N'[]',
    @IdempotencyKeyHash BINARY(32), @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    IF ISJSON(@SnapshotJson) <> 1 OR LEFT(LTRIM(@SnapshotJson), 1) <> N'{'
        THROW 51609, N'SnapshotJson must be a JSON object.', 1;
    IF ISJSON(COALESCE(@FunderLinksJson, N'[]')) <> 1
       OR LEFT(LTRIM(COALESCE(@FunderLinksJson, N'[]')), 1) <> N'['
        THROW 51610, N'FunderLinksJson must be a JSON array.', 1;
    IF ISJSON(COALESCE(@EvidenceJson, N'[]')) <> 1
       OR LEFT(LTRIM(COALESCE(@EvidenceJson, N'[]')), 1) <> N'['
        THROW 51611, N'EvidenceJson must be a JSON array.', 1;

    DECLARE @ActorUserId BIGINT, @OpportunityId BIGINT, @CurrentSlug NVARCHAR(320);
    DECLARE @CurrentStatus TINYINT, @CurrentVersion INT, @NextVersion INT;
    DECLARE @CurrentRowVersion BINARY(8), @RowVersion BINARY(8), @SourceLinkId BIGINT;
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @RawFunderCount INT =
        (SELECT COUNT(1) FROM OPENJSON(COALESCE(@FunderLinksJson, N'[]')));
    DECLARE @RawEvidenceCount INT =
        (SELECT COUNT(1) FROM OPENJSON(COALESCE(@EvidenceJson, N'[]')));
    DECLARE @RequestedFunders TABLE
    (
        FunderPublicId UNIQUEIDENTIFIER NOT NULL,
        Role TINYINT NOT NULL,
        FunderId BIGINT NULL,
        PRIMARY KEY (FunderPublicId)
    );
    DECLARE @ExtraEvidence TABLE
    (
        FieldPath NVARCHAR(200) NOT NULL PRIMARY KEY,
        ValueJson NVARCHAR(MAX) NOT NULL,
        EvidenceText NVARCHAR(2000) NULL,
        SourceLocator NVARCHAR(500) NULL,
        Confidence DECIMAL(5,2) NULL,
        IsManualLock BIT NOT NULL
    );

    INSERT INTO @RequestedFunders (FunderPublicId, Role)
    SELECT TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(items.value, '$.funderPublicId')),
           MIN(TRY_CONVERT(TINYINT, JSON_VALUE(items.value, '$.role')))
    FROM OPENJSON(COALESCE(@FunderLinksJson, N'[]')) AS items
    WHERE TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(items.value, '$.funderPublicId')) IS NOT NULL
      AND TRY_CONVERT(TINYINT, JSON_VALUE(items.value, '$.role')) BETWEEN 1 AND 3
    GROUP BY TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(items.value, '$.funderPublicId'))
    HAVING COUNT_BIG(1) = 1;

    INSERT INTO @ExtraEvidence
        (FieldPath, ValueJson, EvidenceText, SourceLocator, Confidence, IsManualLock)
    SELECT JSON_VALUE(items.value, '$.fieldPath'),
           MAX(JSON_QUERY(items.value, '$.valueJson')),
           MAX(JSON_VALUE(items.value, '$.evidenceText')),
           MAX(JSON_VALUE(items.value, '$.sourceLocator')),
           MAX(TRY_CONVERT(DECIMAL(5,2), JSON_VALUE(items.value, '$.confidence'))),
           MAX(CONVERT(TINYINT,
               COALESCE(TRY_CONVERT(BIT, JSON_VALUE(items.value, '$.isManualLock')), 1)))
    FROM OPENJSON(COALESCE(@EvidenceJson, N'[]')) AS items
    WHERE LEFT(JSON_VALUE(items.value, '$.fieldPath'), 1) = N'/'
      AND LEN(JSON_VALUE(items.value, '$.fieldPath')) BETWEEN 2 AND 200
      AND JSON_QUERY(items.value, '$.valueJson') IS NOT NULL
      AND LEFT(LTRIM(JSON_QUERY(items.value, '$.valueJson')), 1) = N'{'
      AND (JSON_VALUE(items.value, '$.evidenceText') IS NULL
           OR LEN(JSON_VALUE(items.value, '$.evidenceText')) <= 2000)
      AND (JSON_VALUE(items.value, '$.sourceLocator') IS NULL
           OR LEN(JSON_VALUE(items.value, '$.sourceLocator')) <= 500)
      AND (JSON_VALUE(items.value, '$.confidence') IS NULL
           OR TRY_CONVERT(DECIMAL(5,2), JSON_VALUE(items.value, '$.confidence')) BETWEEN 0 AND 100)
      AND (JSON_VALUE(items.value, '$.isManualLock') IS NULL
           OR TRY_CONVERT(BIT, JSON_VALUE(items.value, '$.isManualLock')) IS NOT NULL)
      AND JSON_VALUE(items.value, '$.fieldPath') NOT IN
          (N'/title', N'/description', N'/eligibilityDescription', N'/closeDate', N'/sponsorName')
    GROUP BY JSON_VALUE(items.value, '$.fieldPath')
    HAVING COUNT_BIG(1) = 1;

    IF NULLIF(LTRIM(RTRIM(@Title)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@SponsorName)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@SourceUrl)), N'') IS NULL
       OR @RawFunderCount <> (SELECT COUNT(1) FROM @RequestedFunders)
       OR @RawEvidenceCount <> (SELECT COUNT(1) FROM @ExtraEvidence)
       OR (SELECT COUNT(1) FROM @RequestedFunders WHERE Role = 1) <> 1
       OR @AmountStatus NOT BETWEEN 0 AND 2
       OR (@AmountStatus = 1 AND (@Currency IS NULL OR (@MinAmount IS NULL AND @MaxAmount IS NULL)))
       OR (@AmountStatus IN (0, 2) AND (@Currency IS NOT NULL OR @MinAmount IS NOT NULL OR @MaxAmount IS NOT NULL))
       OR @MinAmount < 0 OR @MaxAmount < COALESCE(@MinAmount, 0)
       OR @DeadlineType NOT BETWEEN 0 AND 2 OR @DeadlinePrecision NOT BETWEEN 0 AND 2
       OR (@DeadlineType = 0 AND (@DeadlinePrecision <> 0 OR @CloseAtUtc IS NOT NULL))
       OR (@DeadlineType = 2 AND (@DeadlinePrecision <> 0 OR @CloseDate IS NOT NULL OR @CloseAtUtc IS NOT NULL))
       OR (@DeadlineType = 1 AND @DeadlinePrecision NOT IN (1, 2))
       OR (@DeadlineType = 1 AND @DeadlinePrecision = 1 AND (@CloseDate IS NULL OR @CloseAtUtc IS NOT NULL))
       OR (@DeadlineType = 1 AND @DeadlinePrecision = 2
           AND (@CloseDate IS NULL OR @CloseAtUtc IS NULL OR @DeadlineTimeZoneId IS NULL))
       OR (@OpenDate IS NOT NULL AND @CloseDate IS NOT NULL AND @OpenDate > @CloseDate)
       OR @GeographicScope NOT BETWEEN 0 AND 2 OR @RemoteApplication NOT BETWEEN 0 AND 2
       OR (@GeographicScope = 0
           AND (EXISTS (SELECT 1 FROM @CountryIds) OR EXISTS (SELECT 1 FROM @RegionIds)))
       OR (@GeographicScope = 1 AND NOT EXISTS (SELECT 1 FROM @CountryIds))
       OR (@GeographicScope = 2
           AND (EXISTS (SELECT 1 FROM @CountryIds) OR EXISTS (SELECT 1 FROM @RegionIds)))
       OR @DataQualityScore NOT BETWEEN 0 AND 100
       OR @MinimumOperatingYears < 0
       OR @CofundingPercentage < 0 OR @CofundingPercentage > 100
       OR (@RequiresCofunding IS NULL AND @CofundingPercentage IS NOT NULL)
       OR (@RequiresCofunding = 0 AND COALESCE(@CofundingPercentage, 0) <> 0)
       OR (@RequiresCofunding = 1 AND COALESCE(@CofundingPercentage, 0) <= 0)
       OR (@LastVerifiedAtUtc IS NOT NULL
           AND @LastVerifiedAtUtc > DATEADD(MINUTE, 5, SYSUTCDATETIME()))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               @FundingOpportunityPublicId AS FundingOpportunityPublicId,
               CAST(NULL AS INT) AS ContentVersion, CAST(NULL AS TINYINT) AS PublicationStatus,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_OppUpdate;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @ActorUserId = Id FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;
        SELECT @OpportunityId = Id, @CurrentSlug = Slug, @CurrentStatus = PublicationStatus,
               @CurrentVersion = ContentVersion, @CurrentRowVersion = RowVersion
        FROM dbo.FundingPlatform_FundingOpportunities WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @FundingOpportunityPublicId;

        IF @OpportunityId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = ActionCode, @ExistingRequestHash = RequestHash,
                   @ExistingToStatus = ToStatus, @NextVersion = ContentVersion,
                   @RowVersion = ResultRowVersion
            FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE FundingOpportunityId = @OpportunityId
              AND IdempotencyKeyHash = @IdempotencyKeyHash;
            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'Update' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'updated';
                    SET @CurrentStatus = @ExistingToStatus;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus NOT IN (0, 3) SET @Code = N'invalid-transition';
            ELSE
            BEGIN
                UPDATE requested SET FunderId = funders.Id
                FROM @RequestedFunders AS requested
                INNER JOIN dbo.FundingPlatform_Funders AS funders WITH (UPDLOCK, HOLDLOCK)
                    ON funders.PublicId = requested.FunderPublicId
                   AND funders.IsActive = 1 AND funders.PublicationStatus <> 4;

                SELECT @SourceLinkId = links.Id
                FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
                    WITH (UPDLOCK, HOLDLOCK)
                WHERE links.FundingOpportunityId = @OpportunityId
                  AND links.FundingSourceId = @FundingSourceId
                  AND links.SourceItemKeyHash = @SourceItemKeyHash;

                IF EXISTS (SELECT 1 FROM @RequestedFunders WHERE FunderId IS NULL)
                    SET @Code = N'funder-not-found';
                ELSE IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingSources
                                    WHERE Id = @FundingSourceId AND IsEnabled = 1)
                    SET @Code = N'source-disabled';
                ELSE IF (@IssuerCountryId IS NOT NULL AND NOT EXISTS
                         (SELECT 1 FROM dbo.FundingPlatform_Countries
                          WHERE Id = @IssuerCountryId AND IsActive = 1))
                     OR (@FundingTypeId IS NOT NULL AND NOT EXISTS
                         (SELECT 1 FROM dbo.FundingPlatform_FundingTypes
                          WHERE Id = @FundingTypeId AND IsActive = 1))
                     OR (@Currency IS NOT NULL AND NOT EXISTS
                         (SELECT 1 FROM dbo.FundingPlatform_Currencies
                          WHERE Code = @Currency AND IsActive = 1))
                     OR EXISTS (SELECT 1 FROM @CountryIds AS selected
                                LEFT JOIN dbo.FundingPlatform_Countries AS catalog
                                    ON catalog.Id = selected.Id AND catalog.IsActive = 1
                                WHERE catalog.Id IS NULL)
                     OR EXISTS (SELECT 1 FROM @CategoryIds AS selected
                                LEFT JOIN dbo.FundingPlatform_FundingCategories AS catalog
                                    ON catalog.Id = selected.Id AND catalog.IsActive = 1
                                WHERE catalog.Id IS NULL)
                     OR EXISTS (SELECT 1 FROM @BeneficiaryTypeIds AS selected
                                LEFT JOIN dbo.FundingPlatform_BeneficiaryTypes AS catalog
                                    ON catalog.Id = selected.Id AND catalog.IsActive = 1
                                WHERE catalog.Id IS NULL)
                     OR EXISTS (SELECT 1 FROM @ProjectTypeIds AS selected
                                LEFT JOIN dbo.FundingPlatform_ProjectTypes AS catalog
                                    ON catalog.Id = selected.Id AND catalog.IsActive = 1
                                WHERE catalog.Id IS NULL)
                    SET @Code = N'invalid-document';
                ELSE IF EXISTS
                (
                    SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks WITH (UPDLOCK, HOLDLOCK)
                    WHERE FundingSourceId = @FundingSourceId
                      AND Id <> COALESCE(@SourceLinkId, -1)
                      AND (SourceItemKeyHash = @SourceItemKeyHash
                           OR (@ExternalId IS NOT NULL AND ExternalId = @ExternalId))
                ) SET @Code = N'source-link-conflict';
                ELSE IF EXISTS
                (
                    SELECT 1 FROM @RegionIds AS selected
                    LEFT JOIN dbo.FundingPlatform_Regions AS regions
                        ON regions.Id = selected.Id AND regions.IsActive = 1
                    WHERE regions.Id IS NULL
                       OR NOT EXISTS (SELECT 1 FROM @CountryIds AS countries
                                      WHERE countries.Id = regions.CountryId)
                ) SET @Code = N'invalid-document';
                ELSE
                BEGIN
                    SET @NextVersion = @CurrentVersion + 1;
                    DECLARE @UpdatedOpportunity TABLE (RowVersion BINARY(8));
                    UPDATE dbo.FundingPlatform_FundingOpportunities
                    SET Title = LTRIM(RTRIM(@Title)), Description = @Description, Summary = @Summary,
                        SponsorName = LTRIM(RTRIM(@SponsorName)), SponsorUrl = @SponsorUrl,
                        ApplicationUrl = @ApplicationUrl, IssuerCountryId = @IssuerCountryId,
                        FundingTypeId = @FundingTypeId, Currency = @Currency,
                        MinAmount = @MinAmount, MaxAmount = @MaxAmount, AmountStatus = @AmountStatus,
                        OpenDate = @OpenDate, CloseDate = @CloseDate, CloseAtUtc = @CloseAtUtc,
                        DeadlineTimeZoneId = @DeadlineTimeZoneId, DeadlineType = @DeadlineType,
                        DeadlinePrecision = @DeadlinePrecision,
                        EligibilityDescription = @EligibilityDescription, Requirements = @Requirements,
                        Objectives = @Objectives, AllowedActivities = @AllowedActivities,
                        ExcludedActivities = @ExcludedActivities, Restrictions = @Restrictions,
                        TargetOrganizationsDescription = @TargetOrganizationsDescription,
                        TargetPopulationsDescription = @TargetPopulationsDescription,
                        MinimumOperatingYears = @MinimumOperatingYears,
                        RequiresLegalEntity = @RequiresLegalEntity,
                        RequiresPriorExperience = @RequiresPriorExperience,
                        RequiresCofunding = @RequiresCofunding,
                        CofundingPercentage = @CofundingPercentage,
                        GeographicScope = @GeographicScope, RemoteApplication = @RemoteApplication,
                        LastVerifiedAtUtc = COALESCE(@LastVerifiedAtUtc, @NowUtc),
                        DataQualityScore = @DataQualityScore,
                        ContentVersion = @NextVersion, ContentFingerprint = @ContentHash,
                        UpdatedByUserId = @ActorUserId, UpdatedAtUtc = @NowUtc
                    OUTPUT inserted.RowVersion INTO @UpdatedOpportunity (RowVersion)
                    WHERE Id = @OpportunityId AND RowVersion = @ExpectedRowVersion;
                    SELECT @RowVersion = RowVersion FROM @UpdatedOpportunity;

                    IF @RowVersion IS NULL SET @Code = N'etag-conflict';
                    ELSE
                    BEGIN
                        UPDATE dbo.FundingPlatform_FundingOpportunitySourceLinks
                        SET IsPrimary = 0
                        WHERE FundingOpportunityId = @OpportunityId AND IsPrimary = 1;
                        SELECT @SourceLinkId = Id
                        FROM dbo.FundingPlatform_FundingOpportunitySourceLinks
                        WHERE FundingOpportunityId = @OpportunityId
                          AND FundingSourceId = @FundingSourceId
                          AND SourceItemKeyHash = @SourceItemKeyHash;
                        IF @SourceLinkId IS NULL
                        BEGIN
                            DECLARE @InsertedSourceLink TABLE (Id BIGINT);
                            INSERT INTO dbo.FundingPlatform_FundingOpportunitySourceLinks
                                (FundingOpportunityId, FundingSourceId, ExternalId, SourceItemKeyHash,
                                 SourceUrl, CanonicalUrlHash, FirstSeenAtUtc, LastSeenAtUtc,
                                 IsPrimary, IsActive)
                            OUTPUT inserted.Id INTO @InsertedSourceLink (Id)
                            VALUES (@OpportunityId, @FundingSourceId, @ExternalId, @SourceItemKeyHash,
                                    @SourceUrl, @CanonicalUrlHash, @NowUtc, @NowUtc, 1, 1);
                            SELECT @SourceLinkId = Id FROM @InsertedSourceLink;
                        END
                        ELSE
                            UPDATE dbo.FundingPlatform_FundingOpportunitySourceLinks
                            SET ExternalId = @ExternalId, SourceUrl = @SourceUrl,
                                CanonicalUrlHash = @CanonicalUrlHash, LastSeenAtUtc = @NowUtc,
                                IsPrimary = 1, IsActive = 1
                            WHERE Id = @SourceLinkId;

                        DELETE FROM dbo.FundingPlatform_FundingOpportunityCountries
                        WHERE FundingOpportunityId = @OpportunityId;
                        DELETE FROM dbo.FundingPlatform_FundingOpportunityRegions
                        WHERE FundingOpportunityId = @OpportunityId;
                        DELETE FROM dbo.FundingPlatform_FundingOpportunityCategories
                        WHERE FundingOpportunityId = @OpportunityId;
                        DELETE FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes
                        WHERE FundingOpportunityId = @OpportunityId;
                        DELETE FROM dbo.FundingPlatform_FundingOpportunityProjectTypes
                        WHERE FundingOpportunityId = @OpportunityId;
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityCountries
                            (FundingOpportunityId, CountryId) SELECT @OpportunityId, Id FROM @CountryIds;
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityRegions
                            (FundingOpportunityId, RegionId) SELECT @OpportunityId, Id FROM @RegionIds;
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityCategories
                            (FundingOpportunityId, FundingCategoryId) SELECT @OpportunityId, Id FROM @CategoryIds;
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes
                            (FundingOpportunityId, BeneficiaryTypeId)
                        SELECT @OpportunityId, Id FROM @BeneficiaryTypeIds;
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityProjectTypes
                            (FundingOpportunityId, ProjectTypeId)
                        SELECT @OpportunityId, Id FROM @ProjectTypeIds;

                        UPDATE dbo.FundingPlatform_FundingOpportunityFunders
                        SET IsActive = 0, UpdatedAtUtc = @NowUtc
                        WHERE FundingOpportunityId = @OpportunityId AND IsActive = 1;
                        UPDATE links
                        SET Role = requested.Role, EvidenceId = NULL,
                            IsActive = 1, UpdatedAtUtc = @NowUtc
                        FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
                        INNER JOIN @RequestedFunders AS requested
                            ON requested.FunderId = links.FunderId
                        WHERE links.FundingOpportunityId = @OpportunityId;
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityFunders
                            (FundingOpportunityId, FunderId, Role, EvidenceId, IsActive,
                             CreatedAtUtc, UpdatedAtUtc)
                        SELECT @OpportunityId, requested.FunderId, requested.Role, NULL, 1,
                               @NowUtc, @NowUtc
                        FROM @RequestedFunders AS requested
                        WHERE NOT EXISTS
                        (
                            SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunders AS existing
                            WHERE existing.FundingOpportunityId = @OpportunityId
                              AND existing.FunderId = requested.FunderId
                        );

                        UPDATE evidence
                        SET IsSelected = 0
                        FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
                        WHERE evidence.FundingOpportunityId = @OpportunityId
                          AND evidence.IsSelected = 1
                          AND
                          (
                              evidence.FieldPath IN
                                  (N'/title', N'/description', N'/eligibilityDescription',
                                   N'/closeDate', N'/sponsorName')
                              OR EXISTS
                                 (SELECT 1 FROM @ExtraEvidence AS replacement
                                  WHERE replacement.FieldPath = evidence.FieldPath)
                          );
                        DECLARE @CriticalEvidence TABLE
                            (FieldPath NVARCHAR(200), ValueText NVARCHAR(MAX), StatusCode NVARCHAR(20),
                             EvidenceText NVARCHAR(2000));
                        INSERT INTO @CriticalEvidence VALUES
                            (N'/title', @Title, N'known', LEFT(@Title, 2000)),
                            (N'/description', @Description,
                             CASE WHEN NULLIF(LTRIM(RTRIM(@Description)), N'') IS NULL THEN N'unknown' ELSE N'known' END,
                             LEFT(@Description, 2000)),
                            (N'/eligibilityDescription', @EligibilityDescription,
                             CASE WHEN NULLIF(LTRIM(RTRIM(@EligibilityDescription)), N'') IS NULL THEN N'unknown' ELSE N'known' END,
                             LEFT(@EligibilityDescription, 2000)),
                            (N'/closeDate', CONVERT(NVARCHAR(30), @CloseDate, 23),
                             CASE WHEN @CloseDate IS NULL THEN N'unknown' ELSE N'known' END,
                             CONVERT(NVARCHAR(30), @CloseDate, 23)),
                            (N'/sponsorName', @SponsorName, N'known', LEFT(@SponsorName, 2000));
                        INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
                            (FundingOpportunityId, FieldPath, ValueJson, FundingOpportunitySourceLinkId,
                             ExtractionMethod, EvidenceText, SourceLocator, Confidence,
                             IsSelected, IsManualLock, CreatedByUserId, CreatedAtUtc)
                        SELECT @OpportunityId, critical.FieldPath,
                               (SELECT critical.ValueText AS [value], critical.StatusCode AS [status]
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
                               @SourceLinkId, 1, critical.EvidenceText, LEFT(@SourceUrl, 500),
                               100, 1, 1, @ActorUserId, @NowUtc
                        FROM @CriticalEvidence AS critical;
                        INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
                            (FundingOpportunityId, FieldPath, ValueJson, FundingOpportunitySourceLinkId,
                             ExtractionMethod, EvidenceText, SourceLocator, Confidence,
                             IsSelected, IsManualLock, CreatedByUserId, CreatedAtUtc)
                        SELECT @OpportunityId, extra.FieldPath, extra.ValueJson, @SourceLinkId, 1,
                               extra.EvidenceText, COALESCE(extra.SourceLocator, LEFT(@SourceUrl, 500)),
                               extra.Confidence, 1, extra.IsManualLock, @ActorUserId, @NowUtc
                        FROM @ExtraEvidence AS extra;
                        DECLARE @SponsorEvidenceId BIGINT =
                            (SELECT Id FROM dbo.FundingPlatform_FundingFieldEvidence
                             WHERE FundingOpportunityId = @OpportunityId
                               AND FieldPath = N'/sponsorName' AND IsSelected = 1);
                        UPDATE links SET EvidenceId = @SponsorEvidenceId
                        FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
                        WHERE links.FundingOpportunityId = @OpportunityId
                          AND links.Role = 1 AND links.IsActive = 1;

                        INSERT INTO dbo.FundingPlatform_FundingOpportunityVersions
                            (FundingOpportunityId, ContentVersion, SnapshotJson, ContentHash,
                             CreatedByUserId, CreatedAtUtc)
                        VALUES (@OpportunityId, @NextVersion, @SnapshotJson, @ContentHash,
                                @ActorUserId, @NowUtc);
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityEditorialEvents
                            (EventId, FundingOpportunityId, ContentVersion, FromStatus, ToStatus,
                             ActionCode, ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                             ResultRowVersion, CreatedAtUtc)
                        VALUES (@EventId, @OpportunityId, @NextVersion, @CurrentStatus, @CurrentStatus,
                                N'Update', @ActorUserId, NULL, @IdempotencyKeyHash,
                                @RequestHash, @RowVersion, @NowUtc);
                        INSERT INTO dbo.FundingPlatform_OutboxMessages
                            (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                             OccurredAtUtc, AvailableAtUtc)
                        SELECT @EventId, N'FundingOpportunityChanged', N'FundingOpportunity',
                               CONVERT(NVARCHAR(100), @OpportunityId),
                               (SELECT @EventId AS eventId, @OpportunityId AS fundingOpportunityId,
                                       @FundingOpportunityPublicId AS fundingOpportunityPublicId,
                                       @NextVersion AS contentVersion
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                        SET @Succeeded = 1; SET @Code = N'updated';
                    END;
                END;
            END;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_OppUpdate;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @FundingOpportunityPublicId AS FundingOpportunityPublicId,
           COALESCE(@NextVersion, @CurrentVersion) AS ContentVersion,
           @CurrentStatus AS PublicationStatus, COALESCE(@RowVersion, @CurrentRowVersion) AS RowVersion,
           @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_RequestPublication
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FundingOpportunityPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @ResultCode NVARCHAR(50) = NULL OUTPUT,
    @ResultCompleteness DECIMAL(5,2) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;

    DECLARE @Issues TABLE
    (
        Code NVARCHAR(50) NOT NULL,
        FieldPath NVARCHAR(100) NOT NULL,
        Message NVARCHAR(300) NOT NULL
    );
    DECLARE @ActorUserId BIGINT, @OpportunityId BIGINT, @ContentVersion INT;
    DECLARE @GeographicScope TINYINT;
    DECLARE @CurrentStatus TINYINT, @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @SubmittedAtUtc DATETIME2(3), @PublishedAtUtc DATETIME2(3), @ReviewedAtUtc DATETIME2(3);
    DECLARE @ReviewedByUserPublicId UNIQUEIDENTIFIER, @RejectionReason NVARCHAR(1000);
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Completeness DECIMAL(5,2) = 0;
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_OppRequest;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @ActorUserId = Id FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;
        SELECT @OpportunityId = opportunities.Id, @ContentVersion = opportunities.ContentVersion,
               @GeographicScope = opportunities.GeographicScope,
               @CurrentStatus = opportunities.PublicationStatus,
               @CurrentRowVersion = opportunities.RowVersion,
               @SubmittedAtUtc = opportunities.SubmittedAtUtc,
               @PublishedAtUtc = opportunities.PublishedAtUtc,
               @ReviewedAtUtc = opportunities.ReviewedAtUtc,
               @ReviewedByUserPublicId = reviewers.PublicId,
               @RejectionReason = opportunities.RejectionReason
        FROM dbo.FundingPlatform_FundingOpportunities AS opportunities WITH (UPDLOCK, HOLDLOCK)
        LEFT JOIN dbo.FundingPlatform_Users AS reviewers
            ON reviewers.Id = opportunities.ReviewedByUserId
        WHERE opportunities.PublicId = @FundingOpportunityPublicId;

        IF @OpportunityId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = ActionCode, @ExistingRequestHash = RequestHash,
                   @ExistingToStatus = ToStatus, @ResultRowVersion = ResultRowVersion,
                   @ContentVersion = ContentVersion, @Completeness = ResultCompleteness,
                   @SubmittedAtUtc = ResultSubmittedAtUtc,
                   @PublishedAtUtc = ResultPublishedAtUtc,
                   @ReviewedAtUtc = ResultReviewedAtUtc,
                   @ReviewedByUserPublicId = ResultReviewedByUserPublicId,
                   @RejectionReason = ResultRejectionReason
            FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE FundingOpportunityId = @OpportunityId
              AND IdempotencyKeyHash = @IdempotencyKeyHash;
            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'RequestPublication' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'review-requested';
                    SET @CurrentStatus = @ExistingToStatus;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus NOT IN (0, 3) SET @Code = N'invalid-transition';
            ELSE
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
                               WHERE Id = @OpportunityId
                                 AND NULLIF(LTRIM(RTRIM(Title)), N'') IS NOT NULL)
                    INSERT INTO @Issues VALUES (N'title', N'title', N'Title is required.');
                IF NOT EXISTS
                (
                    SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
                    INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
                    WHERE links.FundingOpportunityId = @OpportunityId AND links.Role = 1
                      AND links.IsActive = 1 AND funders.PublicationStatus = 2 AND funders.IsActive = 1
                ) INSERT INTO @Issues VALUES
                    (N'primaryFunder', N'funderLinks', N'A published primary funder is required.');
                IF NOT EXISTS
                (
                    SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
                    INNER JOIN dbo.FundingPlatform_FundingSources AS sources
                        ON sources.Id = links.FundingSourceId
                    WHERE links.FundingOpportunityId = @OpportunityId AND links.IsPrimary = 1
                      AND links.IsActive = 1 AND sources.IsEnabled = 1
                      AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL
                ) INSERT INTO @Issues VALUES
                    (N'officialSource', N'sourceUrl', N'An enabled primary source URL is required.');
                IF @GeographicScope = 0
                    INSERT INTO @Issues VALUES
                        (N'geographicScope', N'geographicScope',
                         N'Unknown geographic scope cannot be published.');
                IF @GeographicScope = 1
                   AND NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries
                                   WHERE FundingOpportunityId = @OpportunityId)
                    INSERT INTO @Issues VALUES
                        (N'countries', N'countryIds',
                         N'Explicit geographic scope requires at least one eligible country.');
                IF @GeographicScope = 2
                   AND
                   (
                       EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries
                               WHERE FundingOpportunityId = @OpportunityId)
                       OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions
                                  WHERE FundingOpportunityId = @OpportunityId)
                   )
                    INSERT INTO @Issues VALUES
                        (N'globalGeography', N'countryIds',
                         N'Global geographic scope cannot contain country or region restrictions.');
                IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCategories
                               WHERE FundingOpportunityId = @OpportunityId)
                    INSERT INTO @Issues VALUES
                        (N'categories', N'categoryIds', N'At least one category is required.');
                IF NOT EXISTS
                (
                    SELECT 1
                    FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs() AS catalogs
                    WHERE catalogs.FundingOpportunityId = @OpportunityId
                )
                    INSERT INTO @Issues VALUES
                        (N'inactiveCatalogReference', N'catalogs',
                         N'Every catalog reference must be active and geography must remain consistent.');
                IF EXISTS
                (
                    SELECT required.FieldPath
                    FROM (VALUES (N'/title'), (N'/description'),
                                 (N'/eligibilityDescription'), (N'/closeDate')) AS required(FieldPath)
                    WHERE NOT EXISTS
                    (
                        SELECT 1 FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
                        WHERE evidence.FundingOpportunityId = @OpportunityId
                          AND evidence.FieldPath = required.FieldPath AND evidence.IsSelected = 1
                          AND JSON_VALUE(evidence.ValueJson, '$.status') IN (N'known', N'unknown')
                    )
                ) INSERT INTO @Issues VALUES
                    (N'criticalEvidence', N'evidence',
                     N'Every critical field requires selected evidence or an explicit unknown value.');

                DECLARE @IssueCount INT = (SELECT COUNT(1) FROM @Issues);
                SET @Completeness = CONVERT(DECIMAL(5,2),
                    CASE WHEN @IssueCount >= 5 THEN 0 ELSE 100 - (@IssueCount * 20) END);
                IF @IssueCount > 0 SET @Code = N'opportunity-not-ready';
                ELSE
                BEGIN
                    DECLARE @Updated TABLE (RowVersion BINARY(8));
                    UPDATE dbo.FundingPlatform_FundingOpportunities
                    SET PublicationStatus = 1, SubmittedAtUtc = @NowUtc,
                        ReviewedAtUtc = NULL, ReviewedByUserId = NULL,
                        RejectionReason = NULL, UpdatedByUserId = @ActorUserId,
                        UpdatedAtUtc = @NowUtc
                    OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
                    WHERE Id = @OpportunityId AND RowVersion = @ExpectedRowVersion;
                    SELECT @ResultRowVersion = RowVersion FROM @Updated;
                    IF @ResultRowVersion IS NULL SET @Code = N'etag-conflict';
                    ELSE
                    BEGIN
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityEditorialEvents
                            (EventId, FundingOpportunityId, ContentVersion, FromStatus, ToStatus,
                             ActionCode, ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                             ResultRowVersion, ResultCompleteness, ResultSubmittedAtUtc,
                             ResultPublishedAtUtc, ResultReviewedAtUtc,
                             ResultReviewedByUserPublicId, ResultRejectionReason, CreatedAtUtc)
                        VALUES (@EventId, @OpportunityId, @ContentVersion, @CurrentStatus, 1,
                                N'RequestPublication', @ActorUserId, NULL, @IdempotencyKeyHash,
                                @RequestHash, @ResultRowVersion, 100, @NowUtc,
                                @PublishedAtUtc, NULL, NULL, NULL, @NowUtc);
                        INSERT INTO dbo.FundingPlatform_OutboxMessages
                            (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                             OccurredAtUtc, AvailableAtUtc)
                        SELECT @EventId, N'FundingOpportunityPublicationRequested',
                               N'FundingOpportunity', CONVERT(NVARCHAR(100), @OpportunityId),
                               (SELECT @EventId AS eventId,
                                       @OpportunityId AS fundingOpportunityId,
                                       @FundingOpportunityPublicId AS fundingOpportunityPublicId,
                                       @ContentVersion AS contentVersion,
                                       @CurrentStatus AS fromStatus, 1 AS toStatus
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                        SET @Succeeded = 1; SET @Code = N'review-requested';
                        SET @CurrentStatus = 1; SET @SubmittedAtUtc = @NowUtc;
                        SET @ReviewedAtUtc = NULL; SET @ReviewedByUserPublicId = NULL;
                        SET @RejectionReason = NULL;
                    END;
                END;
            END;
        END;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_OppRequest;
        THROW;
    END CATCH;

    SET @ResultCode = @Code; SET @ResultCompleteness = @Completeness;
    SELECT @Succeeded AS Succeeded, @Code AS Code, @Completeness AS Completeness,
           @FundingOpportunityPublicId AS FundingOpportunityPublicId,
           @ContentVersion AS ContentVersion, @CurrentStatus AS PublicationStatus,
           @SubmittedAtUtc AS SubmittedAtUtc, @PublishedAtUtc AS PublishedAtUtc,
           @ReviewedAtUtc AS ReviewedAtUtc,
           @ReviewedByUserPublicId AS ReviewedByUserPublicId,
           @RejectionReason AS RejectionReason,
           COALESCE(@ResultRowVersion, @CurrentRowVersion) AS RowVersion, @WasReplay AS WasReplay;
    SELECT Code, FieldPath, Message FROM @Issues ORDER BY FieldPath, Code;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_AdminReview
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FundingOpportunityPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @Decision TINYINT,
    @RejectionReason NVARCHAR(1000) = NULL,
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;

    DECLARE @ActorUserId BIGINT, @OpportunityId BIGINT, @ContentVersion INT;
    DECLARE @GeographicScope TINYINT;
    DECLARE @CurrentStatus TINYINT, @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @SubmittedAtUtc DATETIME2(3), @PublishedAtUtc DATETIME2(3), @ReviewedAtUtc DATETIME2(3);
    DECLARE @ReviewedByUserPublicId UNIQUEIDENTIFIER, @CurrentRejectionReason NVARCHAR(1000);
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @Decision NOT IN (2, 3)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-decision' AS Code,
               CAST(NULL AS DECIMAL(5,2)) AS Completeness,
               @FundingOpportunityPublicId AS FundingOpportunityPublicId,
               CAST(NULL AS INT) AS ContentVersion, CAST(NULL AS TINYINT) AS PublicationStatus,
               CAST(NULL AS DATETIME2(3)) AS SubmittedAtUtc,
               CAST(NULL AS DATETIME2(3)) AS PublishedAtUtc,
               CAST(NULL AS DATETIME2(3)) AS ReviewedAtUtc,
               CAST(NULL AS UNIQUEIDENTIFIER) AS ReviewedByUserPublicId,
               CAST(NULL AS NVARCHAR(1000)) AS RejectionReason,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_OppReview;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @ActorUserId = Id FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;
        SELECT @OpportunityId = opportunities.Id, @ContentVersion = opportunities.ContentVersion,
               @GeographicScope = opportunities.GeographicScope,
               @CurrentStatus = opportunities.PublicationStatus,
               @CurrentRowVersion = opportunities.RowVersion,
               @SubmittedAtUtc = opportunities.SubmittedAtUtc,
               @PublishedAtUtc = opportunities.PublishedAtUtc,
               @ReviewedAtUtc = opportunities.ReviewedAtUtc,
               @ReviewedByUserPublicId = reviewers.PublicId,
               @CurrentRejectionReason = opportunities.RejectionReason
        FROM dbo.FundingPlatform_FundingOpportunities AS opportunities WITH (UPDLOCK, HOLDLOCK)
        LEFT JOIN dbo.FundingPlatform_Users AS reviewers
            ON reviewers.Id = opportunities.ReviewedByUserId
        WHERE opportunities.PublicId = @FundingOpportunityPublicId;

        IF @OpportunityId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = ActionCode, @ExistingRequestHash = RequestHash,
                   @ExistingToStatus = ToStatus, @ResultRowVersion = ResultRowVersion,
                   @ContentVersion = ContentVersion,
                   @SubmittedAtUtc = ResultSubmittedAtUtc,
                   @PublishedAtUtc = ResultPublishedAtUtc,
                   @ReviewedAtUtc = ResultReviewedAtUtc,
                   @ReviewedByUserPublicId = ResultReviewedByUserPublicId,
                   @CurrentRejectionReason = ResultRejectionReason
            FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE FundingOpportunityId = @OpportunityId
              AND IdempotencyKeyHash = @IdempotencyKeyHash;
            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'AdminReview' AND @ExistingRequestHash = @RequestHash
                   AND @ExistingToStatus = @Decision
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1;
                    SET @Code = CASE WHEN @Decision = 2 THEN N'published' ELSE N'rejected' END;
                    SET @CurrentStatus = @ExistingToStatus;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus <> 1 SET @Code = N'invalid-transition';
            ELSE IF @Decision = 3 AND NULLIF(LTRIM(RTRIM(@RejectionReason)), N'') IS NULL
                SET @Code = N'rejection-reason-required';
            ELSE IF @Decision = 2 AND
            (
                NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
                            WHERE Id = @OpportunityId
                              AND NULLIF(LTRIM(RTRIM(Title)), N'') IS NOT NULL)
                OR NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
                    INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
                    WHERE links.FundingOpportunityId = @OpportunityId AND links.Role = 1
                      AND links.IsActive = 1 AND funders.PublicationStatus = 2 AND funders.IsActive = 1)
                OR NOT EXISTS
                   (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
                    INNER JOIN dbo.FundingPlatform_FundingSources AS sources
                        ON sources.Id = links.FundingSourceId
                    WHERE links.FundingOpportunityId = @OpportunityId AND links.IsPrimary = 1
                      AND links.IsActive = 1 AND sources.IsEnabled = 1
                      AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL)
                OR @GeographicScope = 0
                OR (@GeographicScope = 1
                    AND NOT EXISTS
                        (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries
                         WHERE FundingOpportunityId = @OpportunityId))
                OR (@GeographicScope = 2
                    AND
                    (EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries
                             WHERE FundingOpportunityId = @OpportunityId)
                     OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions
                                WHERE FundingOpportunityId = @OpportunityId)))
                OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCategories
                               WHERE FundingOpportunityId = @OpportunityId)
                OR NOT EXISTS
                   (SELECT 1
                    FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs() AS catalogs
                    WHERE catalogs.FundingOpportunityId = @OpportunityId)
                OR EXISTS
                   (SELECT required.FieldPath
                    FROM (VALUES (N'/title'), (N'/description'),
                                 (N'/eligibilityDescription'), (N'/closeDate')) AS required(FieldPath)
                    WHERE NOT EXISTS
                    (
                        SELECT 1 FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
                        WHERE evidence.FundingOpportunityId = @OpportunityId
                          AND evidence.FieldPath = required.FieldPath AND evidence.IsSelected = 1
                          AND JSON_VALUE(evidence.ValueJson, '$.status') IN (N'known', N'unknown')
                    ))
            ) SET @Code = N'opportunity-not-ready';
            ELSE
            BEGIN
                DECLARE @Updated TABLE (RowVersion BINARY(8));
                UPDATE dbo.FundingPlatform_FundingOpportunities
                SET PublicationStatus = @Decision,
                    PublishedAtUtc = CASE WHEN @Decision = 2 THEN COALESCE(PublishedAtUtc, @NowUtc)
                                          ELSE PublishedAtUtc END,
                    ReviewedAtUtc = @NowUtc, ReviewedByUserId = @ActorUserId,
                    RejectionReason = CASE WHEN @Decision = 3
                                           THEN LTRIM(RTRIM(@RejectionReason)) ELSE NULL END,
                    UpdatedByUserId = @ActorUserId, UpdatedAtUtc = @NowUtc
                OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
                WHERE Id = @OpportunityId AND RowVersion = @ExpectedRowVersion;
                SELECT @ResultRowVersion = RowVersion FROM @Updated;
                IF @ResultRowVersion IS NULL SET @Code = N'etag-conflict';
                ELSE
                BEGIN
                    INSERT INTO dbo.FundingPlatform_FundingOpportunityEditorialEvents
                        (EventId, FundingOpportunityId, ContentVersion, FromStatus, ToStatus,
                         ActionCode, ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                         ResultRowVersion, ResultCompleteness, ResultSubmittedAtUtc,
                         ResultPublishedAtUtc, ResultReviewedAtUtc,
                         ResultReviewedByUserPublicId, ResultRejectionReason, CreatedAtUtc)
                    VALUES (@EventId, @OpportunityId, @ContentVersion, @CurrentStatus, @Decision,
                            N'AdminReview', @ActorUserId,
                            CASE WHEN @Decision = 3 THEN LTRIM(RTRIM(@RejectionReason)) ELSE NULL END,
                            @IdempotencyKeyHash, @RequestHash, @ResultRowVersion, NULL,
                            @SubmittedAtUtc,
                            CASE WHEN @Decision = 2 THEN COALESCE(@PublishedAtUtc, @NowUtc)
                                 ELSE @PublishedAtUtc END,
                            @NowUtc, @AdminUserPublicId,
                            CASE WHEN @Decision = 3 THEN LTRIM(RTRIM(@RejectionReason)) ELSE NULL END,
                            @NowUtc);
                    INSERT INTO dbo.FundingPlatform_OutboxMessages
                        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                         OccurredAtUtc, AvailableAtUtc)
                    SELECT @EventId,
                           CASE WHEN @Decision = 2 THEN N'FundingOpportunityPublished'
                                ELSE N'FundingOpportunityRejected' END,
                           N'FundingOpportunity', CONVERT(NVARCHAR(100), @OpportunityId),
                           (SELECT @EventId AS eventId, @OpportunityId AS fundingOpportunityId,
                                   @FundingOpportunityPublicId AS fundingOpportunityPublicId,
                                   @ContentVersion AS contentVersion,
                                   @CurrentStatus AS fromStatus, @Decision AS toStatus
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                    SET @Succeeded = 1;
                    SET @Code = CASE WHEN @Decision = 2 THEN N'published' ELSE N'rejected' END;
                    SET @CurrentStatus = @Decision; SET @ReviewedAtUtc = @NowUtc;
                    SET @ReviewedByUserPublicId = @AdminUserPublicId;
                    SET @CurrentRejectionReason = CASE WHEN @Decision = 3
                                                      THEN LTRIM(RTRIM(@RejectionReason)) ELSE NULL END;
                    IF @Decision = 2 SET @PublishedAtUtc = COALESCE(@PublishedAtUtc, @NowUtc);
                END;
            END;
        END;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_OppReview;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, CAST(NULL AS DECIMAL(5,2)) AS Completeness,
           @FundingOpportunityPublicId AS FundingOpportunityPublicId,
           @ContentVersion AS ContentVersion, @CurrentStatus AS PublicationStatus,
           @SubmittedAtUtc AS SubmittedAtUtc, @PublishedAtUtc AS PublishedAtUtc,
           @ReviewedAtUtc AS ReviewedAtUtc,
           @ReviewedByUserPublicId AS ReviewedByUserPublicId,
           @CurrentRejectionReason AS RejectionReason,
           COALESCE(@ResultRowVersion, @CurrentRowVersion) AS RowVersion, @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_StartCorrection
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FundingOpportunityPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @Reason NVARCHAR(1000),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;

    DECLARE @NormalizedReason NVARCHAR(1000) = LTRIM(RTRIM(@Reason));
    IF LEN(COALESCE(@NormalizedReason, N'')) NOT BETWEEN 3 AND 1000
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               CAST(NULL AS DECIMAL(5,2)) AS Completeness,
               @FundingOpportunityPublicId AS FundingOpportunityPublicId,
               CAST(NULL AS INT) AS ContentVersion, CAST(NULL AS TINYINT) AS PublicationStatus,
               CAST(NULL AS DATETIME2(3)) AS SubmittedAtUtc,
               CAST(NULL AS DATETIME2(3)) AS PublishedAtUtc,
               CAST(NULL AS DATETIME2(3)) AS ReviewedAtUtc,
               CAST(NULL AS UNIQUEIDENTIFIER) AS ReviewedByUserPublicId,
               CAST(NULL AS NVARCHAR(1000)) AS RejectionReason,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    DECLARE @ActorUserId BIGINT, @OpportunityId BIGINT, @ContentVersion INT;
    DECLARE @CurrentStatus TINYINT, @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @SubmittedAtUtc DATETIME2(3), @PublishedAtUtc DATETIME2(3), @ReviewedAtUtc DATETIME2(3);
    DECLARE @ReviewedByUserPublicId UNIQUEIDENTIFIER, @CurrentRejectionReason NVARCHAR(1000);
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_OppCorrection;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @OpportunityId = opportunities.Id,
               @ContentVersion = opportunities.ContentVersion,
               @CurrentStatus = opportunities.PublicationStatus,
               @CurrentRowVersion = opportunities.RowVersion,
               @SubmittedAtUtc = opportunities.SubmittedAtUtc,
               @PublishedAtUtc = opportunities.PublishedAtUtc,
               @ReviewedAtUtc = opportunities.ReviewedAtUtc,
               @ReviewedByUserPublicId = reviewers.PublicId,
               @CurrentRejectionReason = opportunities.RejectionReason
        FROM dbo.FundingPlatform_FundingOpportunities AS opportunities WITH (UPDLOCK, HOLDLOCK)
        LEFT JOIN dbo.FundingPlatform_Users AS reviewers
            ON reviewers.Id = opportunities.ReviewedByUserId
        WHERE opportunities.PublicId = @FundingOpportunityPublicId;

        IF @OpportunityId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = ActionCode, @ExistingRequestHash = RequestHash,
                   @ExistingToStatus = ToStatus, @ResultRowVersion = ResultRowVersion,
                   @ContentVersion = ContentVersion,
                   @SubmittedAtUtc = ResultSubmittedAtUtc,
                   @PublishedAtUtc = ResultPublishedAtUtc,
                   @ReviewedAtUtc = ResultReviewedAtUtc,
                   @ReviewedByUserPublicId = ResultReviewedByUserPublicId,
                   @CurrentRejectionReason = ResultRejectionReason
            FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE FundingOpportunityId = @OpportunityId
              AND IdempotencyKeyHash = @IdempotencyKeyHash;

            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'StartCorrection' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1;
                    SET @Code = N'correction-started'; SET @CurrentStatus = @ExistingToStatus;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus <> 2 SET @Code = N'invalid-transition';
            ELSE
            BEGIN
                DECLARE @Updated TABLE (RowVersion BINARY(8));
                UPDATE dbo.FundingPlatform_FundingOpportunities
                SET PublicationStatus = 0, SubmittedAtUtc = NULL, PublishedAtUtc = NULL,
                    ReviewedAtUtc = NULL, ReviewedByUserId = NULL, RejectionReason = NULL,
                    UpdatedByUserId = @ActorUserId, UpdatedAtUtc = @NowUtc
                OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
                WHERE Id = @OpportunityId AND RowVersion = @ExpectedRowVersion;
                SELECT @ResultRowVersion = RowVersion FROM @Updated;
                IF @ResultRowVersion IS NULL SET @Code = N'etag-conflict';
                ELSE
                BEGIN
                    INSERT INTO dbo.FundingPlatform_FundingOpportunityEditorialEvents
                        (EventId, FundingOpportunityId, ContentVersion, FromStatus, ToStatus,
                         ActionCode, ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                         ResultRowVersion, ResultCompleteness, ResultSubmittedAtUtc,
                         ResultPublishedAtUtc, ResultReviewedAtUtc,
                         ResultReviewedByUserPublicId, ResultRejectionReason, CreatedAtUtc)
                    VALUES (@EventId, @OpportunityId, @ContentVersion, 2, 0,
                            N'StartCorrection', @ActorUserId, @NormalizedReason,
                            @IdempotencyKeyHash, @RequestHash, @ResultRowVersion,
                            NULL, NULL, NULL, NULL, NULL, NULL, @NowUtc);
                    INSERT INTO dbo.FundingPlatform_OutboxMessages
                        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                         OccurredAtUtc, AvailableAtUtc)
                    SELECT @EventId, N'FundingOpportunityCorrectionStarted',
                           N'FundingOpportunity', CONVERT(NVARCHAR(100), @OpportunityId),
                           (SELECT @EventId AS eventId,
                                   @OpportunityId AS fundingOpportunityId,
                                   @FundingOpportunityPublicId AS fundingOpportunityPublicId,
                                   @ContentVersion AS contentVersion, 2 AS fromStatus, 0 AS toStatus
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                    SET @Succeeded = 1; SET @Code = N'correction-started'; SET @CurrentStatus = 0;
                    SET @SubmittedAtUtc = NULL; SET @PublishedAtUtc = NULL;
                    SET @ReviewedAtUtc = NULL; SET @ReviewedByUserPublicId = NULL;
                    SET @CurrentRejectionReason = NULL;
                END;
            END;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_OppCorrection;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           CAST(NULL AS DECIMAL(5,2)) AS Completeness,
           @FundingOpportunityPublicId AS FundingOpportunityPublicId,
           @ContentVersion AS ContentVersion, @CurrentStatus AS PublicationStatus,
           @SubmittedAtUtc AS SubmittedAtUtc, @PublishedAtUtc AS PublishedAtUtc,
           @ReviewedAtUtc AS ReviewedAtUtc,
           @ReviewedByUserPublicId AS ReviewedByUserPublicId,
           @CurrentRejectionReason AS RejectionReason,
           COALESCE(@ResultRowVersion, @CurrentRowVersion) AS RowVersion,
           @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Deactivate
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FundingOpportunityPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @Reason NVARCHAR(1000) = NULL,
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;

    DECLARE @ActorUserId BIGINT, @OpportunityId BIGINT, @ContentVersion INT;
    DECLARE @CurrentStatus TINYINT, @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @SubmittedAtUtc DATETIME2(3), @PublishedAtUtc DATETIME2(3), @ReviewedAtUtc DATETIME2(3);
    DECLARE @ReviewedByUserPublicId UNIQUEIDENTIFIER, @RejectionReason NVARCHAR(1000);
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_OppDeactivate;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @ActorUserId = Id FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;
        SELECT @OpportunityId = opportunities.Id, @ContentVersion = opportunities.ContentVersion,
               @CurrentStatus = opportunities.PublicationStatus,
               @CurrentRowVersion = opportunities.RowVersion,
               @SubmittedAtUtc = opportunities.SubmittedAtUtc,
               @PublishedAtUtc = opportunities.PublishedAtUtc,
               @ReviewedAtUtc = opportunities.ReviewedAtUtc,
               @ReviewedByUserPublicId = reviewers.PublicId,
               @RejectionReason = opportunities.RejectionReason
        FROM dbo.FundingPlatform_FundingOpportunities AS opportunities WITH (UPDLOCK, HOLDLOCK)
        LEFT JOIN dbo.FundingPlatform_Users AS reviewers
            ON reviewers.Id = opportunities.ReviewedByUserId
        WHERE opportunities.PublicId = @FundingOpportunityPublicId;

        IF @OpportunityId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = ActionCode, @ExistingRequestHash = RequestHash,
                   @ExistingToStatus = ToStatus, @ResultRowVersion = ResultRowVersion,
                   @ContentVersion = ContentVersion,
                   @SubmittedAtUtc = ResultSubmittedAtUtc,
                   @PublishedAtUtc = ResultPublishedAtUtc,
                   @ReviewedAtUtc = ResultReviewedAtUtc,
                   @ReviewedByUserPublicId = ResultReviewedByUserPublicId,
                   @RejectionReason = ResultRejectionReason
            FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE FundingOpportunityId = @OpportunityId
              AND IdempotencyKeyHash = @IdempotencyKeyHash;
            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'Deactivate' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'deactivated';
                    SET @CurrentStatus = @ExistingToStatus;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus NOT IN (0, 1, 2, 3) SET @Code = N'invalid-transition';
            ELSE
            BEGIN
                DECLARE @Updated TABLE (RowVersion BINARY(8));
                UPDATE dbo.FundingPlatform_FundingOpportunities
                SET PublicationStatus = 4, IsActive = 0,
                    UpdatedByUserId = @ActorUserId, UpdatedAtUtc = @NowUtc
                OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
                WHERE Id = @OpportunityId AND RowVersion = @ExpectedRowVersion;
                SELECT @ResultRowVersion = RowVersion FROM @Updated;
                IF @ResultRowVersion IS NULL SET @Code = N'etag-conflict';
                ELSE
                BEGIN
                    INSERT INTO dbo.FundingPlatform_FundingOpportunityEditorialEvents
                        (EventId, FundingOpportunityId, ContentVersion, FromStatus, ToStatus,
                         ActionCode, ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                         ResultRowVersion, ResultCompleteness, ResultSubmittedAtUtc,
                         ResultPublishedAtUtc, ResultReviewedAtUtc,
                         ResultReviewedByUserPublicId, ResultRejectionReason, CreatedAtUtc)
                    VALUES (@EventId, @OpportunityId, @ContentVersion, @CurrentStatus, 4,
                            N'Deactivate', @ActorUserId, NULLIF(LTRIM(RTRIM(@Reason)), N''),
                            @IdempotencyKeyHash, @RequestHash, @ResultRowVersion, NULL,
                            @SubmittedAtUtc, @PublishedAtUtc, @ReviewedAtUtc,
                            @ReviewedByUserPublicId, @RejectionReason, @NowUtc);
                    INSERT INTO dbo.FundingPlatform_OutboxMessages
                        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                         OccurredAtUtc, AvailableAtUtc)
                    SELECT @EventId, N'FundingOpportunityDeactivated', N'FundingOpportunity',
                           CONVERT(NVARCHAR(100), @OpportunityId),
                           (SELECT @EventId AS eventId, @OpportunityId AS fundingOpportunityId,
                                   @FundingOpportunityPublicId AS fundingOpportunityPublicId,
                                   @ContentVersion AS contentVersion,
                                   @CurrentStatus AS fromStatus, 4 AS toStatus
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                    SET @Succeeded = 1; SET @Code = N'deactivated'; SET @CurrentStatus = 4;
                END;
            END;
        END;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_OppDeactivate;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, CAST(NULL AS DECIMAL(5,2)) AS Completeness,
           @FundingOpportunityPublicId AS FundingOpportunityPublicId,
           @ContentVersion AS ContentVersion, @CurrentStatus AS PublicationStatus,
           @SubmittedAtUtc AS SubmittedAtUtc, @PublishedAtUtc AS PublishedAtUtc,
           @ReviewedAtUtc AS ReviewedAtUtc,
           @ReviewedByUserPublicId AS ReviewedByUserPublicId,
           @RejectionReason AS RejectionReason,
           COALESCE(@ResultRowVersion, @CurrentRowVersion) AS RowVersion, @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_StageExternal
    @FundingSourceId INT,
    @ExternalId NVARCHAR(250) = NULL,
    @SourceItemKeyHash BINARY(32),
    @SourceUrl NVARCHAR(2048) = NULL,
    @CanonicalUrlHash BINARY(32) = NULL,
    @ObservedAtUtc DATETIME2(3),
    @Slug NVARCHAR(320),
    @Title NVARCHAR(350),
    @Description NVARCHAR(MAX) = NULL,
    @Summary NVARCHAR(2000) = NULL,
    @SponsorName NVARCHAR(300),
    @SponsorUrl NVARCHAR(2048) = NULL,
    @ApplicationUrl NVARCHAR(2048) = NULL,
    @FundingTypeId SMALLINT = NULL,
    @Currency CHAR(3) = NULL,
    @MinAmount DECIMAL(19,4) = NULL,
    @MaxAmount DECIMAL(19,4) = NULL,
    @AmountStatus TINYINT,
    @OpenDate DATE = NULL,
    @CloseDate DATE = NULL,
    @DeadlineType TINYINT,
    @DeadlinePrecision TINYINT,
    @EligibilityDescription NVARCHAR(MAX) = NULL,
    @Objectives NVARCHAR(MAX) = NULL,
    @RequiresCofunding BIT = NULL,
    @CofundingPercentage DECIMAL(5,2) = NULL,
    @DataQualityScore DECIMAL(5,2),
    @SnapshotJson NVARCHAR(MAX),
    @ContentHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF ISJSON(@SnapshotJson) <> 1 OR LEFT(LTRIM(@SnapshotJson), 1) <> N'{'
        THROW 51609, N'SnapshotJson must be a JSON object.', 1;

    DECLARE @OpportunityId BIGINT, @OpportunityPublicId UNIQUEIDENTIFIER;
    DECLARE @SourceLinkId BIGINT, @CurrentStatus TINYINT, @CurrentVersion INT, @NextVersion INT;
    DECLARE @CurrentFingerprint BINARY(32), @RowVersion BINARY(8);
    DECLARE @CurrentExternalId NVARCHAR(250), @CurrentSourceUrl NVARCHAR(2048);
    DECLARE @CurrentCanonicalUrlHash BINARY(32), @MetadataChanged BIT = 0;
    DECLARE @HasManualLocks BIT = 0;
    DECLARE @StagedRevisionPublicId UNIQUEIDENTIFIER;
    DECLARE @Code NVARCHAR(50) = N'source-disabled', @Succeeded BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @EffectiveObservedAtUtc DATETIME2(3) = COALESCE(@ObservedAtUtc, SYSUTCDATETIME());
    DECLARE @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @EventKeyHash BINARY(32);
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF NULLIF(LTRIM(RTRIM(@Slug)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@Title)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@SponsorName)), N'') IS NULL
       OR @SourceItemKeyHash IS NULL OR @ContentHash IS NULL
       OR @EffectiveObservedAtUtc > DATEADD(MINUTE, 5, @NowUtc)
       OR @AmountStatus NOT BETWEEN 0 AND 2
       OR (@AmountStatus = 1 AND (@Currency IS NULL OR (@MinAmount IS NULL AND @MaxAmount IS NULL)))
       OR (@AmountStatus IN (0, 2)
           AND (@Currency IS NOT NULL OR @MinAmount IS NOT NULL OR @MaxAmount IS NOT NULL))
       OR @MinAmount < 0 OR @MaxAmount < COALESCE(@MinAmount, 0)
       OR @DeadlineType NOT BETWEEN 0 AND 2 OR @DeadlinePrecision NOT BETWEEN 0 AND 2
       OR (@DeadlineType = 0 AND @DeadlinePrecision <> 0)
       OR (@DeadlineType = 2 AND (@DeadlinePrecision <> 0 OR @CloseDate IS NOT NULL))
       OR (@DeadlineType = 1 AND @DeadlinePrecision <> 1)
       OR (@DeadlineType = 1 AND @CloseDate IS NULL)
       OR (@OpenDate IS NOT NULL AND @CloseDate IS NOT NULL AND @OpenDate > @CloseDate)
       OR @DataQualityScore NOT BETWEEN 0 AND 100
       OR @CofundingPercentage < 0 OR @CofundingPercentage > 100
       OR (@RequiresCofunding IS NULL AND @CofundingPercentage IS NOT NULL)
       OR (@RequiresCofunding = 0 AND COALESCE(@CofundingPercentage, 0) <> 0)
       OR (@RequiresCofunding = 1 AND COALESCE(@CofundingPercentage, 0) <= 0)
       OR (@FundingTypeId IS NOT NULL AND NOT EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_FundingTypes
            WHERE Id = @FundingTypeId AND IsActive = 1))
       OR (@Currency IS NOT NULL AND NOT EXISTS
           (SELECT 1 FROM dbo.FundingPlatform_Currencies
            WHERE Code = @Currency AND IsActive = 1))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               CAST(NULL AS UNIQUEIDENTIFIER) AS FundingOpportunityPublicId,
               CAST(NULL AS INT) AS ContentVersion, CAST(NULL AS TINYINT) AS PublicationStatus,
               CAST(NULL AS BINARY(8)) AS RowVersion,
               CAST(NULL AS UNIQUEIDENTIFIER) AS StagedRevisionPublicId;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_StageExternal;
    BEGIN TRY
        IF EXISTS
        (
            SELECT 1 FROM dbo.FundingPlatform_FundingSources WITH (UPDLOCK, HOLDLOCK)
            WHERE Id = @FundingSourceId AND IsEnabled = 1
        )
        BEGIN
            SELECT @SourceLinkId = links.Id, @OpportunityId = opportunities.Id,
                   @OpportunityPublicId = opportunities.PublicId,
                   @CurrentStatus = opportunities.PublicationStatus,
                   @CurrentVersion = opportunities.ContentVersion,
                   @CurrentFingerprint = opportunities.ContentFingerprint,
                   @RowVersion = opportunities.RowVersion,
                   @CurrentExternalId = links.ExternalId,
                   @CurrentSourceUrl = links.SourceUrl,
                   @CurrentCanonicalUrlHash = links.CanonicalUrlHash
            FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities WITH (UPDLOCK, HOLDLOCK)
                ON opportunities.Id = links.FundingOpportunityId
            WHERE links.FundingSourceId = @FundingSourceId
              AND links.SourceItemKeyHash = @SourceItemKeyHash;

            IF @OpportunityId IS NOT NULL
               AND EXISTS
               (
                   SELECT 1
                   FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence WITH (UPDLOCK, HOLDLOCK)
                   WHERE evidence.FundingOpportunityId = @OpportunityId
                     AND evidence.IsSelected = 1
                     AND evidence.IsManualLock = 1
               )
                SET @HasManualLocks = 1;

            IF @OpportunityId IS NULL
            BEGIN
                IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
                           WHERE Slug = LTRIM(RTRIM(@Slug)))
                    SET @Code = N'slug-conflict';
                ELSE IF @ExternalId IS NOT NULL AND EXISTS
                        (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks
                         WHERE FundingSourceId = @FundingSourceId AND ExternalId = @ExternalId)
                    SET @Code = N'source-link-conflict';
                ELSE
                BEGIN
                    DECLARE @InsertedOpportunity TABLE
                        (Id BIGINT, PublicId UNIQUEIDENTIFIER, RowVersion BINARY(8));
                    INSERT INTO dbo.FundingPlatform_FundingOpportunities
                    (
                        Slug, Title, Description, Summary, SponsorName, SponsorUrl,
                        ApplicationUrl, FundingTypeId, Currency, MinAmount, MaxAmount,
                        AmountStatus, OpenDate, CloseDate, DeadlineType, DeadlinePrecision,
                        EligibilityDescription, Requirements, Objectives,
                        TargetOrganizationsDescription, RequiresCofunding, CofundingPercentage,
                        GeographicScope, RemoteApplication, PublicationStatus,
                        PublishedAtUtc, LastVerifiedAtUtc, DataQualityScore,
                        ContentVersion, ContentFingerprint, IsActive, CreatedAtUtc, UpdatedAtUtc
                    )
                    OUTPUT inserted.Id, inserted.PublicId, inserted.RowVersion
                        INTO @InsertedOpportunity (Id, PublicId, RowVersion)
                    VALUES
                    (
                        LTRIM(RTRIM(@Slug)), LTRIM(RTRIM(@Title)), @Description, @Summary,
                        LTRIM(RTRIM(@SponsorName)), @SponsorUrl, @ApplicationUrl,
                        @FundingTypeId, @Currency, @MinAmount, @MaxAmount, @AmountStatus,
                        @OpenDate, @CloseDate, @DeadlineType, @DeadlinePrecision,
                        @EligibilityDescription, @EligibilityDescription, @Objectives,
                        @EligibilityDescription, @RequiresCofunding, @CofundingPercentage,
                        0, 1, 0, NULL, @EffectiveObservedAtUtc, @DataQualityScore,
                        1, @ContentHash, 1, @NowUtc, @NowUtc
                    );
                    SELECT @OpportunityId = Id, @OpportunityPublicId = PublicId, @RowVersion = RowVersion
                    FROM @InsertedOpportunity;
                    SET @CurrentStatus = 0; SET @CurrentVersion = 1;
                    SET @EventKeyHash = HASHBYTES
                        ('SHA2_256', CONVERT(VARBINARY(MAX), @SourceItemKeyHash)
                         + CONVERT(VARBINARY(MAX), @ContentHash) + CONVERT(VARBINARY(4), 0));

                    DECLARE @InsertedSourceLink TABLE (Id BIGINT);
                    INSERT INTO dbo.FundingPlatform_FundingOpportunitySourceLinks
                        (FundingOpportunityId, FundingSourceId, ExternalId, SourceItemKeyHash,
                         SourceUrl, CanonicalUrlHash, FirstSeenAtUtc, LastSeenAtUtc,
                         IsPrimary, IsActive)
                    OUTPUT inserted.Id INTO @InsertedSourceLink (Id)
                    VALUES (@OpportunityId, @FundingSourceId, @ExternalId, @SourceItemKeyHash,
                            @SourceUrl, @CanonicalUrlHash,
                            @EffectiveObservedAtUtc, @EffectiveObservedAtUtc, 1, 1);
                    SELECT @SourceLinkId = Id FROM @InsertedSourceLink;

                    DECLARE @CriticalEvidence TABLE
                        (FieldPath NVARCHAR(200), ValueText NVARCHAR(MAX), StatusCode NVARCHAR(20),
                         EvidenceText NVARCHAR(2000));
                    INSERT INTO @CriticalEvidence VALUES
                        (N'/title', @Title, N'known', LEFT(@Title, 2000)),
                        (N'/description', @Description,
                         CASE WHEN NULLIF(LTRIM(RTRIM(@Description)), N'') IS NULL THEN N'unknown' ELSE N'known' END,
                         LEFT(@Description, 2000)),
                        (N'/eligibilityDescription', @EligibilityDescription,
                         CASE WHEN NULLIF(LTRIM(RTRIM(@EligibilityDescription)), N'') IS NULL THEN N'unknown' ELSE N'known' END,
                         LEFT(@EligibilityDescription, 2000)),
                        (N'/closeDate', CONVERT(NVARCHAR(30), @CloseDate, 23),
                         CASE WHEN @CloseDate IS NULL THEN N'unknown' ELSE N'known' END,
                         CONVERT(NVARCHAR(30), @CloseDate, 23)),
                        (N'/sponsorName', @SponsorName, N'known', LEFT(@SponsorName, 2000));
                    INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
                        (FundingOpportunityId, FieldPath, ValueJson,
                         FundingOpportunitySourceLinkId, ExtractionMethod, EvidenceText,
                         SourceLocator, Confidence, IsSelected, IsManualLock,
                         CreatedByUserId, CreatedAtUtc)
                    SELECT @OpportunityId, critical.FieldPath,
                           (SELECT critical.ValueText AS [value], critical.StatusCode AS [status]
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
                           @SourceLinkId, 2, critical.EvidenceText, LEFT(@SourceUrl, 500),
                           NULL, 1, 0, NULL, @NowUtc
                    FROM @CriticalEvidence AS critical;
                    INSERT INTO dbo.FundingPlatform_FundingOpportunityVersions
                        (FundingOpportunityId, ContentVersion, SnapshotJson, ContentHash,
                         CreatedByUserId, CreatedAtUtc)
                    VALUES (@OpportunityId, 1, @SnapshotJson, @ContentHash, NULL, @NowUtc);
                    INSERT INTO dbo.FundingPlatform_FundingOpportunityEditorialEvents
                        (EventId, FundingOpportunityId, ContentVersion, FromStatus, ToStatus,
                         ActionCode, ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                         ResultRowVersion, CreatedAtUtc)
                    VALUES (@EventId, @OpportunityId, 1, 0, 0, N'ExternalStage', NULL, NULL,
                            @EventKeyHash, @ContentHash, @RowVersion, @NowUtc);
                    INSERT INTO dbo.FundingPlatform_OutboxMessages
                        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                         OccurredAtUtc, AvailableAtUtc)
                    SELECT @EventId, N'FundingOpportunityDraftStaged', N'FundingOpportunity',
                           CONVERT(NVARCHAR(100), @OpportunityId),
                           (SELECT @EventId AS eventId, @OpportunityId AS fundingOpportunityId,
                                   @OpportunityPublicId AS fundingOpportunityPublicId,
                                   @FundingSourceId AS fundingSourceId, 1 AS contentVersion
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                    SET @Succeeded = 1; SET @Code = N'draft-created';
                END;
            END
            ELSE
            BEGIN
                UPDATE dbo.FundingPlatform_FundingOpportunitySourceLinks
                SET LastSeenAtUtc = CASE WHEN LastSeenAtUtc < @EffectiveObservedAtUtc
                                         THEN @EffectiveObservedAtUtc ELSE LastSeenAtUtc END
                WHERE Id = @SourceLinkId;

                SET @MetadataChanged = CASE
                    WHEN ISNULL(@CurrentExternalId, N'') <> ISNULL(@ExternalId, N'')
                      OR ISNULL(@CurrentSourceUrl, N'') <> ISNULL(@SourceUrl, N'')
                      OR ISNULL(@CurrentCanonicalUrlHash, 0x) <> ISNULL(@CanonicalUrlHash, 0x)
                    THEN 1 ELSE 0 END;

                IF @CurrentFingerprint = @ContentHash
                   AND NOT (@CurrentStatus IN (1, 2, 4) AND @MetadataChanged = 1)
                BEGIN
                    IF @CurrentStatus IN (0, 3)
                        UPDATE dbo.FundingPlatform_FundingOpportunitySourceLinks
                        SET ExternalId = @ExternalId, SourceUrl = @SourceUrl,
                            CanonicalUrlHash = @CanonicalUrlHash, IsActive = 1
                        WHERE Id = @SourceLinkId;
                    SET @Succeeded = 1; SET @Code = N'unchanged';
                END
                ELSE IF @CurrentStatus IN (0, 3) AND @HasManualLocks = 0
                BEGIN
                    UPDATE dbo.FundingPlatform_FundingOpportunitySourceLinks
                    SET ExternalId = @ExternalId, SourceUrl = @SourceUrl,
                        CanonicalUrlHash = @CanonicalUrlHash, IsActive = 1
                    WHERE Id = @SourceLinkId;
                    SET @NextVersion = @CurrentVersion + 1;
                    SET @EventKeyHash = HASHBYTES
                        ('SHA2_256', CONVERT(VARBINARY(MAX), @SourceItemKeyHash)
                         + CONVERT(VARBINARY(MAX), @ContentHash)
                         + CONVERT(VARBINARY(4), @CurrentVersion));
                    DECLARE @UpdatedOpportunity TABLE (RowVersion BINARY(8));
                    UPDATE dbo.FundingPlatform_FundingOpportunities
                    SET Title = LTRIM(RTRIM(@Title)), Description = @Description,
                        Summary = @Summary, SponsorName = LTRIM(RTRIM(@SponsorName)),
                        SponsorUrl = @SponsorUrl, ApplicationUrl = @ApplicationUrl,
                        FundingTypeId = @FundingTypeId, Currency = @Currency,
                        MinAmount = @MinAmount, MaxAmount = @MaxAmount,
                        AmountStatus = @AmountStatus, OpenDate = @OpenDate, CloseDate = @CloseDate,
                        DeadlineType = @DeadlineType, DeadlinePrecision = @DeadlinePrecision,
                        EligibilityDescription = @EligibilityDescription,
                        Requirements = @EligibilityDescription, Objectives = @Objectives,
                        TargetOrganizationsDescription = @EligibilityDescription,
                        RequiresCofunding = @RequiresCofunding,
                        CofundingPercentage = @CofundingPercentage,
                        PublicationStatus = 0, SubmittedAtUtc = NULL,
                        ReviewedAtUtc = NULL, ReviewedByUserId = NULL, RejectionReason = NULL,
                        LastVerifiedAtUtc = CASE
                            WHEN LastVerifiedAtUtc IS NULL
                              OR LastVerifiedAtUtc < @EffectiveObservedAtUtc
                            THEN @EffectiveObservedAtUtc ELSE LastVerifiedAtUtc END,
                        DataQualityScore = @DataQualityScore,
                        ContentVersion = @NextVersion, ContentFingerprint = @ContentHash,
                        IsActive = 1, UpdatedAtUtc = @NowUtc
                    OUTPUT inserted.RowVersion INTO @UpdatedOpportunity (RowVersion)
                    WHERE Id = @OpportunityId;
                    SELECT @RowVersion = RowVersion FROM @UpdatedOpportunity;

                    UPDATE dbo.FundingPlatform_FundingFieldEvidence
                    SET IsSelected = 0
                    WHERE FundingOpportunityId = @OpportunityId
                      AND FieldPath IN
                          (N'/title', N'/description', N'/eligibilityDescription',
                           N'/closeDate', N'/sponsorName')
                      AND IsSelected = 1 AND IsManualLock = 0;
                    DECLARE @ParserEvidence TABLE
                        (FieldPath NVARCHAR(200), ValueText NVARCHAR(MAX), StatusCode NVARCHAR(20),
                         EvidenceText NVARCHAR(2000));
                    INSERT INTO @ParserEvidence VALUES
                        (N'/title', @Title, N'known', LEFT(@Title, 2000)),
                        (N'/description', @Description,
                         CASE WHEN NULLIF(LTRIM(RTRIM(@Description)), N'') IS NULL THEN N'unknown' ELSE N'known' END,
                         LEFT(@Description, 2000)),
                        (N'/eligibilityDescription', @EligibilityDescription,
                         CASE WHEN NULLIF(LTRIM(RTRIM(@EligibilityDescription)), N'') IS NULL THEN N'unknown' ELSE N'known' END,
                         LEFT(@EligibilityDescription, 2000)),
                        (N'/closeDate', CONVERT(NVARCHAR(30), @CloseDate, 23),
                         CASE WHEN @CloseDate IS NULL THEN N'unknown' ELSE N'known' END,
                         CONVERT(NVARCHAR(30), @CloseDate, 23)),
                        (N'/sponsorName', @SponsorName, N'known', LEFT(@SponsorName, 2000));
                    INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
                        (FundingOpportunityId, FieldPath, ValueJson,
                         FundingOpportunitySourceLinkId, ExtractionMethod, EvidenceText,
                         SourceLocator, Confidence, IsSelected, IsManualLock,
                         CreatedByUserId, CreatedAtUtc)
                    SELECT @OpportunityId, parser.FieldPath,
                           (SELECT parser.ValueText AS [value], parser.StatusCode AS [status]
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
                           @SourceLinkId, 2, parser.EvidenceText, LEFT(@SourceUrl, 500),
                           NULL, 1, 0, NULL, @NowUtc
                    FROM @ParserEvidence AS parser
                    WHERE NOT EXISTS
                    (
                        SELECT 1 FROM dbo.FundingPlatform_FundingFieldEvidence AS locked
                        WHERE locked.FundingOpportunityId = @OpportunityId
                          AND locked.FieldPath = parser.FieldPath
                          AND locked.IsSelected = 1 AND locked.IsManualLock = 1
                    );
                    INSERT INTO dbo.FundingPlatform_FundingOpportunityVersions
                        (FundingOpportunityId, ContentVersion, SnapshotJson, ContentHash,
                         CreatedByUserId, CreatedAtUtc)
                    VALUES (@OpportunityId, @NextVersion, @SnapshotJson, @ContentHash, NULL, @NowUtc);
                    INSERT INTO dbo.FundingPlatform_FundingOpportunityEditorialEvents
                        (EventId, FundingOpportunityId, ContentVersion, FromStatus, ToStatus,
                         ActionCode, ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                         ResultRowVersion, CreatedAtUtc)
                    VALUES (@EventId, @OpportunityId, @NextVersion, @CurrentStatus, 0,
                            N'ExternalStage', NULL, NULL, @EventKeyHash, @ContentHash,
                            @RowVersion, @NowUtc);
                    INSERT INTO dbo.FundingPlatform_OutboxMessages
                        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                         OccurredAtUtc, AvailableAtUtc)
                    SELECT @EventId, N'FundingOpportunityDraftChanged', N'FundingOpportunity',
                           CONVERT(NVARCHAR(100), @OpportunityId),
                           (SELECT @EventId AS eventId, @OpportunityId AS fundingOpportunityId,
                                   @OpportunityPublicId AS fundingOpportunityPublicId,
                                   @FundingSourceId AS fundingSourceId,
                                   @NextVersion AS contentVersion
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                    SET @CurrentVersion = @NextVersion; SET @CurrentStatus = 0;
                    SET @Succeeded = 1; SET @Code = N'draft-updated';
                END
                ELSE
                BEGIN
                    DECLARE @ExistingCandidateId BIGINT;
                    SELECT @ExistingCandidateId = Id,
                           @StagedRevisionPublicId = PublicId
                    FROM dbo.FundingPlatform_FundingOpportunityStagedRevisions WITH (UPDLOCK, HOLDLOCK)
                    WHERE FundingSourceId = @FundingSourceId
                      AND SourceItemKeyHash = @SourceItemKeyHash AND ContentHash = @ContentHash
                      AND CandidateStatus = 0;
                    IF @ExistingCandidateId IS NULL
                    BEGIN
                        DECLARE @InsertedCandidate TABLE (PublicId UNIQUEIDENTIFIER);
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityStagedRevisions
                            (FundingSourceId, FundingOpportunityId, ExternalId,
                             SourceItemKeyHash, SourceUrl, CanonicalUrlHash, SnapshotJson,
                             ContentHash, CandidateStatus, FirstObservedAtUtc, LastObservedAtUtc,
                             SeenCount, CreatedAtUtc, UpdatedAtUtc)
                        OUTPUT inserted.PublicId INTO @InsertedCandidate (PublicId)
                        VALUES (@FundingSourceId, @OpportunityId, @ExternalId,
                                @SourceItemKeyHash, @SourceUrl, @CanonicalUrlHash, @SnapshotJson,
                                @ContentHash, 0, @EffectiveObservedAtUtc,
                                @EffectiveObservedAtUtc, 1, @NowUtc, @NowUtc);
                        SELECT @StagedRevisionPublicId = PublicId FROM @InsertedCandidate;
                        DECLARE @CandidateEventId UNIQUEIDENTIFIER = NEWID();
                        INSERT INTO dbo.FundingPlatform_OutboxMessages
                            (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                             OccurredAtUtc, AvailableAtUtc)
                        SELECT @CandidateEventId, N'FundingOpportunityRevisionStaged',
                               N'FundingOpportunity', CONVERT(NVARCHAR(100), @OpportunityId),
                               (SELECT @CandidateEventId AS eventId,
                                       @OpportunityId AS fundingOpportunityId,
                                       @OpportunityPublicId AS fundingOpportunityPublicId,
                                       @StagedRevisionPublicId AS stagedRevisionPublicId,
                                       @FundingSourceId AS fundingSourceId,
                                       @CurrentVersion AS currentContentVersion
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                    END
                    ELSE
                        UPDATE dbo.FundingPlatform_FundingOpportunityStagedRevisions
                        SET LastObservedAtUtc = CASE
                                WHEN LastObservedAtUtc < @EffectiveObservedAtUtc
                                THEN @EffectiveObservedAtUtc ELSE LastObservedAtUtc END,
                            SeenCount = SeenCount + 1,
                            UpdatedAtUtc = @NowUtc
                        WHERE Id = @ExistingCandidateId;

                    SET @Succeeded = 1;
                    SET @Code = CASE @CurrentStatus
                                    WHEN 0 THEN N'manual-lock-protected'
                                    WHEN 1 THEN N'pending-review-protected'
                                    WHEN 2 THEN N'published-protected'
                                    WHEN 3 THEN N'manual-lock-protected'
                                    ELSE N'archived-protected' END;
                END;
            END;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_StageExternal;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @OpportunityPublicId AS FundingOpportunityPublicId,
           @CurrentVersion AS ContentVersion, @CurrentStatus AS PublicationStatus,
           @RowVersion AS RowVersion, @StagedRevisionPublicId AS StagedRevisionPublicId;
END;
GO
