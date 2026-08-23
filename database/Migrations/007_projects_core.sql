/* FundingPlatform FASE 5 - project aggregate, versions and tenant-safe CRUD. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

CREATE TABLE dbo.FundingPlatform_Projects
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL CONSTRAINT FundingPlatform_DF_Projects_PublicId DEFAULT (NEWSEQUENTIALID()),
    OrganizationId BIGINT NOT NULL,
    CreatedByUserId BIGINT NOT NULL,
    Slug NVARCHAR(180) NOT NULL,
    Title NVARCHAR(250) NOT NULL,
    Summary NVARCHAR(1000) NULL,
    Description NVARCHAR(MAX) NULL,
    ProjectStatus TINYINT NOT NULL CONSTRAINT FundingPlatform_DF_Projects_Status DEFAULT (0),
    PublicationStatus TINYINT NOT NULL CONSTRAINT FundingPlatform_DF_Projects_PublicationStatus DEFAULT (0),
    StartDate DATE NULL,
    EndDate DATE NULL,
    BudgetTotal DECIMAL(19,4) NULL,
    ConfirmedFunding DECIMAL(19,4) NULL,
    Currency CHAR(3) NULL,
    FundingGap AS
        (CASE WHEN BudgetTotal IS NULL THEN NULL
              WHEN ISNULL(ConfirmedFunding, (0)) >= BudgetTotal THEN CONVERT(DECIMAL(19,4), (0))
              ELSE CONVERT(DECIMAL(19,4), BudgetTotal - ISNULL(ConfirmedFunding, (0))) END) PERSISTED,
    ProjectVersion INT NOT NULL CONSTRAINT FundingPlatform_DF_Projects_Version DEFAULT (1),
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_Projects_IsActive DEFAULT (1),
    CreatedAtUtc DATETIME2(3) NOT NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_Projects PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_Projects_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_Projects_Slug UNIQUE (Slug),
    CONSTRAINT FundingPlatform_FK_Projects_Organizations FOREIGN KEY (OrganizationId)
        REFERENCES dbo.FundingPlatform_Organizations (Id),
    CONSTRAINT FundingPlatform_FK_Projects_CreatedByUser FOREIGN KEY (CreatedByUserId)
        REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_Projects_Currency FOREIGN KEY (Currency)
        REFERENCES dbo.FundingPlatform_Currencies (Code),
    CONSTRAINT FundingPlatform_CK_Projects_Status CHECK (ProjectStatus BETWEEN 0 AND 6),
    CONSTRAINT FundingPlatform_CK_Projects_PublicationStatus CHECK (PublicationStatus BETWEEN 0 AND 4),
    CONSTRAINT FundingPlatform_CK_Projects_Dates CHECK (StartDate IS NULL OR EndDate IS NULL OR EndDate >= StartDate),
    CONSTRAINT FundingPlatform_CK_Projects_Budget CHECK
        ((BudgetTotal IS NULL AND ConfirmedFunding IS NULL AND Currency IS NULL)
         OR (BudgetTotal IS NOT NULL AND BudgetTotal >= 0
             AND (ConfirmedFunding IS NULL OR ConfirmedFunding >= 0) AND Currency IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_Projects_Version CHECK (ProjectVersion >= 1)
);

CREATE INDEX FundingPlatform_IX_Projects_Organization_Active_Updated
    ON dbo.FundingPlatform_Projects (OrganizationId, IsActive, UpdatedAtUtc DESC)
    INCLUDE (PublicId, Title, ProjectStatus, PublicationStatus, ProjectVersion);

CREATE TABLE dbo.FundingPlatform_ProjectVersions
(
    ProjectId BIGINT NOT NULL,
    ProjectVersion INT NOT NULL,
    SnapshotJson NVARCHAR(MAX) NOT NULL,
    ContentHash BINARY(32) NOT NULL,
    CreatedByUserId BIGINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_ProjectVersions PRIMARY KEY (ProjectId, ProjectVersion),
    CONSTRAINT FundingPlatform_FK_ProjectVersions_Projects FOREIGN KEY (ProjectId)
        REFERENCES dbo.FundingPlatform_Projects (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_ProjectVersions_Users FOREIGN KEY (CreatedByUserId)
        REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_ProjectVersions_Json CHECK (ISJSON(SnapshotJson) = 1),
    CONSTRAINT FundingPlatform_CK_ProjectVersions_Version CHECK (ProjectVersion >= 1)
);

CREATE TABLE dbo.FundingPlatform_ProjectCountries
(
    ProjectId BIGINT NOT NULL, CountryId SMALLINT NOT NULL,
    CONSTRAINT FundingPlatform_PK_ProjectCountries PRIMARY KEY (ProjectId, CountryId),
    CONSTRAINT FundingPlatform_FK_ProjectCountries_Projects FOREIGN KEY (ProjectId) REFERENCES dbo.FundingPlatform_Projects (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_ProjectCountries_Countries FOREIGN KEY (CountryId) REFERENCES dbo.FundingPlatform_Countries (Id)
);
CREATE TABLE dbo.FundingPlatform_ProjectRegions
(
    ProjectId BIGINT NOT NULL, RegionId INT NOT NULL,
    CONSTRAINT FundingPlatform_PK_ProjectRegions PRIMARY KEY (ProjectId, RegionId),
    CONSTRAINT FundingPlatform_FK_ProjectRegions_Projects FOREIGN KEY (ProjectId) REFERENCES dbo.FundingPlatform_Projects (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_ProjectRegions_Regions FOREIGN KEY (RegionId) REFERENCES dbo.FundingPlatform_Regions (Id)
);
CREATE TABLE dbo.FundingPlatform_ProjectCategories
(
    ProjectId BIGINT NOT NULL, FundingCategoryId INT NOT NULL,
    CONSTRAINT FundingPlatform_PK_ProjectCategories PRIMARY KEY (ProjectId, FundingCategoryId),
    CONSTRAINT FundingPlatform_FK_ProjectCategories_Projects FOREIGN KEY (ProjectId) REFERENCES dbo.FundingPlatform_Projects (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_ProjectCategories_Categories FOREIGN KEY (FundingCategoryId) REFERENCES dbo.FundingPlatform_FundingCategories (Id)
);
CREATE TABLE dbo.FundingPlatform_ProjectBeneficiaryTypes
(
    ProjectId BIGINT NOT NULL, BeneficiaryTypeId INT NOT NULL,
    CONSTRAINT FundingPlatform_PK_ProjectBeneficiaryTypes PRIMARY KEY (ProjectId, BeneficiaryTypeId),
    CONSTRAINT FundingPlatform_FK_ProjectBeneficiaryTypes_Projects FOREIGN KEY (ProjectId) REFERENCES dbo.FundingPlatform_Projects (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_ProjectBeneficiaryTypes_Types FOREIGN KEY (BeneficiaryTypeId) REFERENCES dbo.FundingPlatform_BeneficiaryTypes (Id)
);
CREATE TABLE dbo.FundingPlatform_ProjectProjectTypes
(
    ProjectId BIGINT NOT NULL, ProjectTypeId INT NOT NULL,
    CONSTRAINT FundingPlatform_PK_ProjectProjectTypes PRIMARY KEY (ProjectId, ProjectTypeId),
    CONSTRAINT FundingPlatform_FK_ProjectProjectTypes_Projects FOREIGN KEY (ProjectId) REFERENCES dbo.FundingPlatform_Projects (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_ProjectProjectTypes_Types FOREIGN KEY (ProjectTypeId) REFERENCES dbo.FundingPlatform_ProjectTypes (Id)
);

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Project_List
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @OrganizationId BIGINT;
    SELECT @OrganizationId = organizations.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1
      AND users.PublicId = @UserPublicId;

    IF @OrganizationId IS NULL THROW 51401, N''Organization was not found.'', 1;

    SELECT PublicId, Slug, Title, Summary, ProjectStatus, PublicationStatus,
           StartDate, EndDate, BudgetTotal, ConfirmedFunding, Currency, FundingGap,
           ProjectVersion, UpdatedAtUtc
    FROM dbo.FundingPlatform_Projects
    WHERE OrganizationId = @OrganizationId AND IsActive = 1
    ORDER BY UpdatedAtUtc DESC, Id DESC;
END;';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Project_Create
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER,
    @Slug NVARCHAR(180), @Title NVARCHAR(250), @Summary NVARCHAR(1000) = NULL,
    @Description NVARCHAR(MAX) = NULL, @ProjectStatus TINYINT,
    @StartDate DATE = NULL, @EndDate DATE = NULL,
    @BudgetTotal DECIMAL(19,4) = NULL, @ConfirmedFunding DECIMAL(19,4) = NULL,
    @Currency CHAR(3) = NULL, @SnapshotJson NVARCHAR(MAX), @ContentHash BINARY(32),
    @CountryIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @RegionIds dbo.FundingPlatform_IntIdList READONLY,
    @CategoryIds dbo.FundingPlatform_IntIdList READONLY,
    @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @ProjectId BIGINT;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FundingPlatform_CreateProject;
    BEGIN TRY
        SELECT @OrganizationId = organizations.Id, @UserId = users.Id
        FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id AND memberships.Role = 1 AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
            ON users.Id = memberships.UserId AND users.Status = 2
        WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1
          AND users.PublicId = @UserPublicId;
        IF @OrganizationId IS NULL THROW 51402, N''Active organization administrator membership is required.'', 1;
        IF ISJSON(@SnapshotJson) <> 1 THROW 51403, N''Project snapshot must be JSON.'', 1;
        IF EXISTS (SELECT 1 FROM @RegionIds selected INNER JOIN dbo.FundingPlatform_Regions region ON region.Id = selected.Id WHERE NOT EXISTS (SELECT 1 FROM @CountryIds country WHERE country.Id = region.CountryId))
            THROW 51404, N''Every project region requires its country.'', 1;

        INSERT INTO dbo.FundingPlatform_Projects
            (OrganizationId, CreatedByUserId, Slug, Title, Summary, Description,
             ProjectStatus, PublicationStatus, StartDate, EndDate, BudgetTotal,
             ConfirmedFunding, Currency, ProjectVersion, CreatedAtUtc, UpdatedAtUtc)
        VALUES
            (@OrganizationId, @UserId, @Slug, @Title, @Summary, @Description,
             @ProjectStatus, 0, @StartDate, @EndDate, @BudgetTotal,
             @ConfirmedFunding, @Currency, 1, @NowUtc, @NowUtc);
        SET @ProjectId = CONVERT(BIGINT, SCOPE_IDENTITY());
        INSERT INTO dbo.FundingPlatform_ProjectCountries SELECT @ProjectId, Id FROM @CountryIds;
        INSERT INTO dbo.FundingPlatform_ProjectRegions SELECT @ProjectId, Id FROM @RegionIds;
        INSERT INTO dbo.FundingPlatform_ProjectCategories SELECT @ProjectId, Id FROM @CategoryIds;
        INSERT INTO dbo.FundingPlatform_ProjectBeneficiaryTypes SELECT @ProjectId, Id FROM @BeneficiaryTypeIds;
        INSERT INTO dbo.FundingPlatform_ProjectProjectTypes SELECT @ProjectId, Id FROM @ProjectTypeIds;
        INSERT INTO dbo.FundingPlatform_ProjectVersions
            (ProjectId, ProjectVersion, SnapshotJson, ContentHash, CreatedByUserId, CreatedAtUtc)
        VALUES (@ProjectId, 1, @SnapshotJson, @ContentHash, @UserId, @NowUtc);
        INSERT INTO dbo.FundingPlatform_OutboxMessages
            (MessageType, AggregateType, AggregateId, PayloadJson, OccurredAtUtc, AvailableAtUtc)
        SELECT N''ProjectCreated'', N''Project'', CONVERT(NVARCHAR(100), @ProjectId),
               (SELECT @ProjectId AS projectId, 1 AS projectVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
               @NowUtc, @NowUtc;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
        SELECT Id, PublicId, ProjectVersion, RowVersion FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION FundingPlatform_CreateProject;
        THROW;
    END CATCH;
END;';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Project_Get
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ProjectId BIGINT;
    SELECT @ProjectId = projects.Id
    FROM dbo.FundingPlatform_Projects AS projects
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations ON organizations.Id = projects.OrganizationId AND organizations.IsActive = 1
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships ON memberships.OrganizationId = organizations.Id AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId AND projects.PublicId = @ProjectPublicId
      AND projects.IsActive = 1 AND users.PublicId = @UserPublicId;
    IF @ProjectId IS NULL THROW 51405, N''Project was not found.'', 1;
    SELECT PublicId, Slug, Title, Summary, Description, ProjectStatus, PublicationStatus,
           StartDate, EndDate, BudgetTotal, ConfirmedFunding, Currency, FundingGap,
           ProjectVersion, UpdatedAtUtc, RowVersion
    FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId;
    SELECT CountryId AS Id FROM dbo.FundingPlatform_ProjectCountries WHERE ProjectId = @ProjectId ORDER BY CountryId;
    SELECT RegionId AS Id FROM dbo.FundingPlatform_ProjectRegions WHERE ProjectId = @ProjectId ORDER BY RegionId;
    SELECT FundingCategoryId AS Id FROM dbo.FundingPlatform_ProjectCategories WHERE ProjectId = @ProjectId ORDER BY FundingCategoryId;
    SELECT BeneficiaryTypeId AS Id FROM dbo.FundingPlatform_ProjectBeneficiaryTypes WHERE ProjectId = @ProjectId ORDER BY BeneficiaryTypeId;
    SELECT ProjectTypeId AS Id FROM dbo.FundingPlatform_ProjectProjectTypes WHERE ProjectId = @ProjectId ORDER BY ProjectTypeId;
END;';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Project_Update
    @OrganizationPublicId UNIQUEIDENTIFIER, @ProjectPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER, @ExpectedRowVersion BINARY(8),
    @Title NVARCHAR(250), @Summary NVARCHAR(1000) = NULL,
    @Description NVARCHAR(MAX) = NULL, @ProjectStatus TINYINT,
    @StartDate DATE = NULL, @EndDate DATE = NULL,
    @BudgetTotal DECIMAL(19,4) = NULL, @ConfirmedFunding DECIMAL(19,4) = NULL,
    @Currency CHAR(3) = NULL, @SnapshotJson NVARCHAR(MAX), @ContentHash BINARY(32),
    @CountryIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @RegionIds dbo.FundingPlatform_IntIdList READONLY,
    @CategoryIds dbo.FundingPlatform_IntIdList READONLY,
    @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @ProjectId BIGINT, @NextVersion INT;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FundingPlatform_UpdateProject;
    BEGIN TRY
        SELECT @OrganizationId = organizations.Id, @UserId = users.Id
        FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id AND memberships.Role = 1 AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
            ON users.Id = memberships.UserId AND users.Status = 2
        WHERE organizations.PublicId = @OrganizationPublicId AND users.PublicId = @UserPublicId AND organizations.IsActive = 1;
        IF @OrganizationId IS NULL THROW 51406, N''Active organization administrator membership is required.'', 1;
        SELECT @ProjectId = Id, @NextVersion = ProjectVersion + 1
        FROM dbo.FundingPlatform_Projects WITH (UPDLOCK, HOLDLOCK)
        WHERE OrganizationId = @OrganizationId AND PublicId = @ProjectPublicId AND IsActive = 1;
        IF @ProjectId IS NULL THROW 51405, N''Project was not found.'', 1;
        IF EXISTS (SELECT 1 FROM @RegionIds selected INNER JOIN dbo.FundingPlatform_Regions region ON region.Id = selected.Id WHERE NOT EXISTS (SELECT 1 FROM @CountryIds country WHERE country.Id = region.CountryId))
            THROW 51404, N''Every project region requires its country.'', 1;
        UPDATE dbo.FundingPlatform_Projects
        SET Title = @Title, Summary = @Summary, Description = @Description,
            ProjectStatus = @ProjectStatus, StartDate = @StartDate, EndDate = @EndDate,
            BudgetTotal = @BudgetTotal, ConfirmedFunding = @ConfirmedFunding,
            Currency = @Currency, ProjectVersion = @NextVersion, UpdatedAtUtc = @NowUtc
        WHERE Id = @ProjectId AND RowVersion = @ExpectedRowVersion;
        IF @@ROWCOUNT = 0 THROW 51407, N''Project has a concurrency conflict.'', 1;
        DELETE FROM dbo.FundingPlatform_ProjectCountries WHERE ProjectId = @ProjectId;
        DELETE FROM dbo.FundingPlatform_ProjectRegions WHERE ProjectId = @ProjectId;
        DELETE FROM dbo.FundingPlatform_ProjectCategories WHERE ProjectId = @ProjectId;
        DELETE FROM dbo.FundingPlatform_ProjectBeneficiaryTypes WHERE ProjectId = @ProjectId;
        DELETE FROM dbo.FundingPlatform_ProjectProjectTypes WHERE ProjectId = @ProjectId;
        INSERT INTO dbo.FundingPlatform_ProjectCountries SELECT @ProjectId, Id FROM @CountryIds;
        INSERT INTO dbo.FundingPlatform_ProjectRegions SELECT @ProjectId, Id FROM @RegionIds;
        INSERT INTO dbo.FundingPlatform_ProjectCategories SELECT @ProjectId, Id FROM @CategoryIds;
        INSERT INTO dbo.FundingPlatform_ProjectBeneficiaryTypes SELECT @ProjectId, Id FROM @BeneficiaryTypeIds;
        INSERT INTO dbo.FundingPlatform_ProjectProjectTypes SELECT @ProjectId, Id FROM @ProjectTypeIds;
        INSERT INTO dbo.FundingPlatform_ProjectVersions
            (ProjectId, ProjectVersion, SnapshotJson, ContentHash, CreatedByUserId, CreatedAtUtc)
        VALUES (@ProjectId, @NextVersion, @SnapshotJson, @ContentHash, @UserId, @NowUtc);
        INSERT INTO dbo.FundingPlatform_OutboxMessages
            (MessageType, AggregateType, AggregateId, PayloadJson, OccurredAtUtc, AvailableAtUtc)
        SELECT N''ProjectChanged'', N''Project'', CONVERT(NVARCHAR(100), @ProjectId),
               (SELECT @ProjectId AS projectId, @NextVersion AS projectVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
               @NowUtc, @NowUtc;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
        SELECT Id, PublicId, ProjectVersion, RowVersion FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION FundingPlatform_UpdateProject;
        THROW;
    END CATCH;
END;';
