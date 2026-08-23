/* FundingPlatform FASE 5 closure - moderated project publication workflow. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

ALTER TABLE dbo.FundingPlatform_Projects ADD
    SubmittedAtUtc DATETIME2(3) NULL,
    PublishedAtUtc DATETIME2(3) NULL,
    ReviewedAtUtc DATETIME2(3) NULL,
    ReviewedByUserId BIGINT NULL,
    RejectionReason NVARCHAR(1000) NULL;
GO

ALTER TABLE dbo.FundingPlatform_Projects
    ADD CONSTRAINT FundingPlatform_FK_Projects_ReviewedByUser
        FOREIGN KEY (ReviewedByUserId) REFERENCES dbo.FundingPlatform_Users (Id);

ALTER TABLE dbo.FundingPlatform_Projects
    ADD CONSTRAINT FundingPlatform_CK_Projects_PendingSubmitted
        CHECK (PublicationStatus <> 1 OR SubmittedAtUtc IS NOT NULL);

ALTER TABLE dbo.FundingPlatform_Projects
    ADD CONSTRAINT FundingPlatform_CK_Projects_PublishedReview
        CHECK (PublicationStatus <> 2 OR
               (PublishedAtUtc IS NOT NULL AND ReviewedAtUtc IS NOT NULL
                AND ReviewedByUserId IS NOT NULL AND RejectionReason IS NULL));

ALTER TABLE dbo.FundingPlatform_Projects
    ADD CONSTRAINT FundingPlatform_CK_Projects_RejectedReview
        CHECK (PublicationStatus <> 3 OR
               (ReviewedAtUtc IS NOT NULL AND ReviewedByUserId IS NOT NULL
                AND NULLIF(LTRIM(RTRIM(RejectionReason)), N'') IS NOT NULL));

CREATE INDEX FundingPlatform_IX_Projects_PublicationReviewQueue
    ON dbo.FundingPlatform_Projects (PublicationStatus, SubmittedAtUtc, Id)
    INCLUDE (PublicId, OrganizationId, Slug, Title, Summary, ProjectVersion, UpdatedAtUtc)
    WHERE PublicationStatus = 1 AND IsActive = 1;

CREATE TABLE dbo.FundingPlatform_ProjectPublicationEvents
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    EventId UNIQUEIDENTIFIER NOT NULL,
    ProjectId BIGINT NOT NULL,
    ProjectVersion INT NOT NULL,
    OrganizationProfileVersion INT NOT NULL,
    FromStatus TINYINT NOT NULL,
    ToStatus TINYINT NOT NULL,
    ActionCode NVARCHAR(50) NOT NULL,
    ActorUserId BIGINT NOT NULL,
    Reason NVARCHAR(1000) NULL,
    IdempotencyKeyHash BINARY(32) NOT NULL,
    RequestHash BINARY(32) NOT NULL,
    ResultRowVersion BINARY(8) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_ProjectPublicationEvents PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_ProjectPublicationEvents_EventId UNIQUE (EventId),
    CONSTRAINT FundingPlatform_UQ_ProjectPublicationEvents_ProjectKey
        UNIQUE (ProjectId, IdempotencyKeyHash),
    CONSTRAINT FundingPlatform_FK_ProjectPublicationEvents_Project
        FOREIGN KEY (ProjectId) REFERENCES dbo.FundingPlatform_Projects (Id),
    CONSTRAINT FundingPlatform_FK_ProjectPublicationEvents_Actor
        FOREIGN KEY (ActorUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_ProjectPublicationEvents_Statuses
        CHECK (FromStatus BETWEEN 0 AND 4 AND ToStatus BETWEEN 0 AND 4
               AND FromStatus <> ToStatus),
    CONSTRAINT FundingPlatform_CK_ProjectPublicationEvents_Transitions
        CHECK ((FromStatus IN (0, 3) AND ToStatus IN (1, 4))
               OR (FromStatus = 1 AND ToStatus IN (2, 3, 4))
               OR (FromStatus = 2 AND ToStatus = 4)),
    CONSTRAINT FundingPlatform_CK_ProjectPublicationEvents_Versions
        CHECK (ProjectVersion >= 1 AND OrganizationProfileVersion >= 1)
);

CREATE INDEX FundingPlatform_IX_ProjectPublicationEvents_ProjectCreated
    ON dbo.FundingPlatform_ProjectPublicationEvents (ProjectId, CreatedAtUtc DESC, Id DESC)
    INCLUDE (EventId, ProjectVersion, OrganizationProfileVersion,
             FromStatus, ToStatus, ActionCode, ActorUserId);

/* Existing CRUD remains source-compatible, but public/pending/archived content is immutable. */
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
    DECLARE @PublicationStatus TINYINT;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_UpdateProject;
    BEGIN TRY
        SELECT @OrganizationId = organizations.Id, @UserId = users.Id
        FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id AND memberships.Role = 1 AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
            ON users.Id = memberships.UserId AND users.Status = 2
        WHERE organizations.PublicId = @OrganizationPublicId AND users.PublicId = @UserPublicId AND organizations.IsActive = 1;
        IF @OrganizationId IS NULL THROW 51406, N''Active organization administrator membership is required.'', 1;
        SELECT @ProjectId = Id, @NextVersion = ProjectVersion + 1, @PublicationStatus = PublicationStatus
        FROM dbo.FundingPlatform_Projects WITH (UPDLOCK, HOLDLOCK)
        WHERE OrganizationId = @OrganizationId AND PublicId = @ProjectPublicId AND IsActive = 1;
        IF @ProjectId IS NULL THROW 51405, N''Project was not found.'', 1;
        IF @PublicationStatus NOT IN (0, 3)
            THROW 51408, N''Only draft or rejected project content can be edited.'', 1;
        IF ISJSON(@SnapshotJson) <> 1 THROW 51403, N''Project snapshot must be JSON.'', 1;
        IF EXISTS
        (
            SELECT 1 FROM @RegionIds selected
            LEFT JOIN dbo.FundingPlatform_Regions region ON region.Id = selected.Id
            WHERE region.Id IS NULL
        ) THROW 51409, N''One or more project regions do not exist.'', 1;
        IF EXISTS
        (
            SELECT 1 FROM @RegionIds selected
            INNER JOIN dbo.FundingPlatform_Regions region ON region.Id = selected.Id
            WHERE NOT EXISTS (SELECT 1 FROM @CountryIds country WHERE country.Id = region.CountryId)
        ) THROW 51404, N''Every project region requires its country.'', 1;
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
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION FP_UpdateProject;
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
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = projects.OrganizationId AND organizations.IsActive = 1
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId AND projects.PublicId = @ProjectPublicId
      AND projects.IsActive = 1 AND users.PublicId = @UserPublicId;
    IF @ProjectId IS NULL THROW 51405, N''Project was not found.'', 1;
    SELECT PublicId, Slug, Title, Summary, Description, ProjectStatus, PublicationStatus,
           StartDate, EndDate, BudgetTotal, ConfirmedFunding, Currency, FundingGap,
           ProjectVersion, UpdatedAtUtc, RowVersion, SubmittedAtUtc, ReviewedAtUtc,
           RejectionReason, PublishedAtUtc
    FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId;
    SELECT CountryId AS Id FROM dbo.FundingPlatform_ProjectCountries WHERE ProjectId = @ProjectId ORDER BY CountryId;
    SELECT RegionId AS Id FROM dbo.FundingPlatform_ProjectRegions WHERE ProjectId = @ProjectId ORDER BY RegionId;
    SELECT FundingCategoryId AS Id FROM dbo.FundingPlatform_ProjectCategories WHERE ProjectId = @ProjectId ORDER BY FundingCategoryId;
    SELECT BeneficiaryTypeId AS Id FROM dbo.FundingPlatform_ProjectBeneficiaryTypes WHERE ProjectId = @ProjectId ORDER BY BeneficiaryTypeId;
    SELECT ProjectTypeId AS Id FROM dbo.FundingPlatform_ProjectProjectTypes WHERE ProjectId = @ProjectId ORDER BY ProjectTypeId;
END;';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Project_Public_GetBySlug
    @Slug NVARCHAR(180)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT projects.PublicId AS ProjectPublicId,
           projects.Slug,
           projects.Title,
           projects.Summary,
           projects.Description,
           projects.ProjectStatus,
           projects.StartDate,
           projects.EndDate,
           projects.BudgetTotal,
           projects.ConfirmedFunding,
           projects.Currency,
           projects.FundingGap,
           projects.ProjectVersion,
           projects.PublishedAtUtc,
           projects.UpdatedAtUtc,
           organizations.PublicId AS OrganizationPublicId,
           organizations.Name AS OrganizationName,
           organizations.WebsiteUrl AS OrganizationWebsiteUrl,
           JSON_QUERY(COALESCE
           (
               (SELECT countries.Id AS id, RTRIM(countries.Iso2) AS code, countries.Name AS name
                FROM dbo.FundingPlatform_ProjectCountries AS projectCountries
                INNER JOIN dbo.FundingPlatform_Countries AS countries
                    ON countries.Id = projectCountries.CountryId AND countries.IsActive = 1
                WHERE projectCountries.ProjectId = projects.Id
                ORDER BY countries.Name, countries.Id
                FOR JSON PATH), N''[]''
           )) AS CountriesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT regions.Id AS id, regions.CountryId AS countryId,
                       regions.Code AS code, regions.Name AS name
                FROM dbo.FundingPlatform_ProjectRegions AS projectRegions
                INNER JOIN dbo.FundingPlatform_Regions AS regions
                    ON regions.Id = projectRegions.RegionId AND regions.IsActive = 1
                WHERE projectRegions.ProjectId = projects.Id
                ORDER BY regions.Name, regions.Id
                FOR JSON PATH), N''[]''
           )) AS RegionsJson,
           JSON_QUERY(COALESCE
           (
               (SELECT categories.Id AS id, categories.Code AS code, categories.Name AS name
                FROM dbo.FundingPlatform_ProjectCategories AS projectCategories
                INNER JOIN dbo.FundingPlatform_FundingCategories AS categories
                    ON categories.Id = projectCategories.FundingCategoryId AND categories.IsActive = 1
                WHERE projectCategories.ProjectId = projects.Id
                ORDER BY categories.Name, categories.Id
                FOR JSON PATH), N''[]''
           )) AS CategoriesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT beneficiaryTypes.Id AS id, beneficiaryTypes.Code AS code,
                       beneficiaryTypes.Name AS name
                FROM dbo.FundingPlatform_ProjectBeneficiaryTypes AS projectBeneficiaryTypes
                INNER JOIN dbo.FundingPlatform_BeneficiaryTypes AS beneficiaryTypes
                    ON beneficiaryTypes.Id = projectBeneficiaryTypes.BeneficiaryTypeId
                   AND beneficiaryTypes.IsActive = 1
                WHERE projectBeneficiaryTypes.ProjectId = projects.Id
                ORDER BY beneficiaryTypes.Name, beneficiaryTypes.Id
                FOR JSON PATH), N''[]''
           )) AS BeneficiaryTypesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT projectTypes.Id AS id, projectTypes.Code AS code, projectTypes.Name AS name
                FROM dbo.FundingPlatform_ProjectProjectTypes AS projectProjectTypes
                INNER JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
                    ON projectTypes.Id = projectProjectTypes.ProjectTypeId AND projectTypes.IsActive = 1
                WHERE projectProjectTypes.ProjectId = projects.Id
                ORDER BY projectTypes.Name, projectTypes.Id
                FOR JSON PATH), N''[]''
           )) AS ProjectTypesJson
    FROM dbo.FundingPlatform_Projects AS projects
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = projects.OrganizationId AND organizations.IsActive = 1
    WHERE projects.Slug = @Slug
      AND projects.PublicationStatus = 2
      AND projects.IsActive = 1
      AND organizations.ProfileStatus = 2
      AND organizations.ProfileCompleteness >= 80;
END;';


EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Project_AdminReviewQueue_List
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @PageNumber INT = 1,
    @PageSize INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    IF @PageNumber < 1 THROW 51501, N''PageNumber must be at least 1.'', 1;
    IF @PageSize < 1 OR @PageSize > 100 THROW 51502, N''PageSize must be between 1 and 100.'', 1;
    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_Users AS users
        INNER JOIN dbo.FundingPlatform_UserRoles AS userRoles ON userRoles.UserId = users.Id
        INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
        WHERE users.PublicId = @AdminUserPublicId AND users.Status = 2
          AND roles.NormalizedName IN (N''ADMIN'', N''SUPERADMIN'')
    ) THROW 51503, N''Active Admin or SuperAdmin role is required.'', 1;

    SELECT COUNT_BIG(1) AS TotalCount
    FROM dbo.FundingPlatform_Projects AS projects
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = projects.OrganizationId AND organizations.IsActive = 1
    WHERE projects.PublicationStatus = 1 AND projects.IsActive = 1;

    SELECT projects.PublicId AS ProjectPublicId, projects.Slug, projects.Title, projects.Summary,
           projects.ProjectStatus, projects.PublicationStatus, projects.SubmittedAtUtc,
           CAST(CASE WHEN organizations.ProfileStatus = 2
                           AND organizations.ProfileCompleteness >= 80
                     THEN 100.00 ELSE 90.00 END AS DECIMAL(5,2)) AS Completeness,
           projects.ProjectVersion, projects.UpdatedAtUtc, projects.RowVersion,
           organizations.PublicId AS OrganizationPublicId, organizations.Name AS OrganizationName
    FROM dbo.FundingPlatform_Projects AS projects
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = projects.OrganizationId AND organizations.IsActive = 1
    WHERE projects.PublicationStatus = 1 AND projects.IsActive = 1
    ORDER BY projects.SubmittedAtUtc, projects.Id
    OFFSET ((@PageNumber - 1) * @PageSize) ROWS FETCH NEXT @PageSize ROWS ONLY;
END;';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Project_AdminReview_Get
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_Users AS users
        INNER JOIN dbo.FundingPlatform_UserRoles AS userRoles ON userRoles.UserId = users.Id
        INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
        WHERE users.PublicId = @AdminUserPublicId AND users.Status = 2
          AND roles.NormalizedName IN (N''ADMIN'', N''SUPERADMIN'')
    ) THROW 51503, N''Active Admin or SuperAdmin role is required.'', 1;

    SELECT projects.PublicId AS ProjectPublicId,
           projects.Slug,
           projects.Title,
           projects.Summary,
           projects.Description,
           projects.ProjectStatus,
           projects.PublicationStatus,
           projects.StartDate,
           projects.EndDate,
           projects.BudgetTotal,
           projects.ConfirmedFunding,
           projects.Currency,
           projects.FundingGap,
           projects.ProjectVersion,
           projects.PublishedAtUtc,
           projects.UpdatedAtUtc,
           organizations.PublicId AS OrganizationPublicId,
           organizations.Name AS OrganizationName,
           organizations.WebsiteUrl AS OrganizationWebsiteUrl,
           projects.SubmittedAtUtc,
           projects.RejectionReason,
           CONVERT(DECIMAL(5,2), 100
               - CASE WHEN organizations.ProfileStatus = 2
                            AND organizations.ProfileCompleteness >= 80 THEN 0 ELSE 10 END
               - CASE WHEN NULLIF(LTRIM(RTRIM(projects.Title)), N'''') IS NOT NULL THEN 0 ELSE 10 END
               - CASE WHEN NULLIF(LTRIM(RTRIM(projects.Summary)), N'''') IS NOT NULL THEN 0 ELSE 10 END
               - CASE WHEN NULLIF(LTRIM(RTRIM(projects.Description)), N'''') IS NOT NULL THEN 0 ELSE 10 END
               - CASE WHEN NULLIF(LTRIM(RTRIM(projects.Slug)), N'''') IS NOT NULL THEN 0 ELSE 10 END
               - CASE WHEN projects.BudgetTotal > 0 AND projects.Currency IS NOT NULL THEN 0 ELSE 10 END
               - CASE WHEN EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectCountries x WHERE x.ProjectId = projects.Id) THEN 0 ELSE 10 END
               - CASE WHEN EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectCategories x WHERE x.ProjectId = projects.Id) THEN 0 ELSE 10 END
               - CASE WHEN EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectBeneficiaryTypes x WHERE x.ProjectId = projects.Id) THEN 0 ELSE 10 END
               - CASE WHEN EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectProjectTypes x WHERE x.ProjectId = projects.Id) THEN 0 ELSE 10 END
           ) AS Completeness,
           projects.RowVersion,
           JSON_QUERY(COALESCE
           (
               (SELECT countries.Id AS id, RTRIM(countries.Iso2) AS code, countries.Name AS name
                FROM dbo.FundingPlatform_ProjectCountries AS projectCountries
                INNER JOIN dbo.FundingPlatform_Countries AS countries
                    ON countries.Id = projectCountries.CountryId AND countries.IsActive = 1
                WHERE projectCountries.ProjectId = projects.Id
                ORDER BY countries.Name, countries.Id FOR JSON PATH), N''[]''
           )) AS CountriesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT regions.Id AS id, regions.CountryId AS countryId,
                       regions.Code AS code, regions.Name AS name
                FROM dbo.FundingPlatform_ProjectRegions AS projectRegions
                INNER JOIN dbo.FundingPlatform_Regions AS regions
                    ON regions.Id = projectRegions.RegionId AND regions.IsActive = 1
                WHERE projectRegions.ProjectId = projects.Id
                ORDER BY regions.Name, regions.Id FOR JSON PATH), N''[]''
           )) AS RegionsJson,
           JSON_QUERY(COALESCE
           (
               (SELECT categories.Id AS id, categories.Code AS code, categories.Name AS name
                FROM dbo.FundingPlatform_ProjectCategories AS projectCategories
                INNER JOIN dbo.FundingPlatform_FundingCategories AS categories
                    ON categories.Id = projectCategories.FundingCategoryId AND categories.IsActive = 1
                WHERE projectCategories.ProjectId = projects.Id
                ORDER BY categories.Name, categories.Id FOR JSON PATH), N''[]''
           )) AS CategoriesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT beneficiaryTypes.Id AS id, beneficiaryTypes.Code AS code,
                       beneficiaryTypes.Name AS name
                FROM dbo.FundingPlatform_ProjectBeneficiaryTypes AS projectBeneficiaryTypes
                INNER JOIN dbo.FundingPlatform_BeneficiaryTypes AS beneficiaryTypes
                    ON beneficiaryTypes.Id = projectBeneficiaryTypes.BeneficiaryTypeId
                   AND beneficiaryTypes.IsActive = 1
                WHERE projectBeneficiaryTypes.ProjectId = projects.Id
                ORDER BY beneficiaryTypes.Name, beneficiaryTypes.Id FOR JSON PATH), N''[]''
           )) AS BeneficiaryTypesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT projectTypes.Id AS id, projectTypes.Code AS code, projectTypes.Name AS name
                FROM dbo.FundingPlatform_ProjectProjectTypes AS projectProjectTypes
                INNER JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
                    ON projectTypes.Id = projectProjectTypes.ProjectTypeId AND projectTypes.IsActive = 1
                WHERE projectProjectTypes.ProjectId = projects.Id
                ORDER BY projectTypes.Name, projectTypes.Id FOR JSON PATH), N''[]''
           )) AS ProjectTypesJson
    FROM dbo.FundingPlatform_Projects AS projects
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = projects.OrganizationId AND organizations.IsActive = 1
    WHERE projects.PublicId = @ProjectPublicId
      AND projects.PublicationStatus = 1
      AND projects.IsActive = 1;
END;';

EXEC sys.sp_executesql N'
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
    SET NOCOUNT ON; SET XACT_ABORT ON;
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
    DECLARE @Code NVARCHAR(50) = N''forbidden'';
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
              SELECT 1 FROM dbo.FundingPlatform_UserRoles AS userRoles WITH (UPDLOCK, HOLDLOCK)
              INNER JOIN dbo.FundingPlatform_Roles AS roles ON roles.Id = userRoles.RoleId
              WHERE userRoles.UserId = users.Id
                AND roles.NormalizedName IN (N''ADMIN'', N''SUPERADMIN'')
          );

        IF @AdminUserId IS NOT NULL
        BEGIN
            SELECT @ProjectId = projects.Id, @CurrentStatus = projects.PublicationStatus,
                   @CurrentRowVersion = projects.RowVersion, @SubmittedAtUtc = projects.SubmittedAtUtc,
                   @PublishedAtUtc = projects.PublishedAtUtc, @ReviewedAtUtc = projects.ReviewedAtUtc,
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
            LEFT JOIN dbo.FundingPlatform_Users AS reviewer ON reviewer.Id = projects.ReviewedByUserId
            WHERE projects.PublicId = @ProjectPublicId AND projects.IsActive = 1;

            IF @ProjectId IS NULL SET @Code = N''not-found'';
            ELSE
            BEGIN
                SELECT @ExistingAction = events.ActionCode,
                       @ExistingRequestHash = events.RequestHash,
                       @ExistingToStatus = events.ToStatus,
                       @ExistingResultRowVersion = events.ResultRowVersion
                FROM dbo.FundingPlatform_ProjectPublicationEvents AS events WITH (UPDLOCK, HOLDLOCK)
                WHERE events.ProjectId = @ProjectId AND events.IdempotencyKeyHash = @IdempotencyKeyHash;

                IF @ExistingAction IS NOT NULL
                BEGIN
                    IF @ExistingAction = N''AdminReview'' AND @ExistingRequestHash = @RequestHash
                    BEGIN
                        SET @Succeeded = 1; SET @WasReplay = 1;
                        SET @Code = CASE WHEN @Decision = 2 THEN N''published'' ELSE N''rejected'' END;
                        SET @CurrentStatus = @ExistingToStatus;
                        SET @ResultRowVersion = @ExistingResultRowVersion;
                    END
                    ELSE SET @Code = N''idempotency-conflict'';
                END
                ELSE IF @Decision IS NULL OR @Decision NOT IN (2, 3) SET @Code = N''invalid-decision'';
                ELSE IF @Decision = 3 AND NULLIF(LTRIM(RTRIM(@RejectionReason)), N'''') IS NULL
                    SET @Code = N''rejection-reason-required'';
                ELSE IF @Decision = 2 AND NULLIF(LTRIM(RTRIM(@RejectionReason)), N'''') IS NOT NULL
                    SET @Code = N''rejection-reason-not-allowed'';
                ELSE IF @Decision = 2 AND
                        (@OrganizationIsActive <> 1 OR @OrganizationProfileStatus <> 2
                         OR @OrganizationCompleteness < 80)
                    SET @Code = N''organization-not-ready'';
                ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N''etag-conflict'';
                ELSE IF @CurrentStatus <> 1 SET @Code = N''invalid-transition'';
                ELSE
                BEGIN
                    DECLARE @Updated TABLE (RowVersion BINARY(8) NOT NULL);
                    UPDATE dbo.FundingPlatform_Projects
                    SET PublicationStatus = @Decision,
                        PublishedAtUtc = CASE WHEN @Decision = 2 THEN @NowUtc ELSE PublishedAtUtc END,
                        ReviewedAtUtc = @NowUtc,
                        ReviewedByUserId = @AdminUserId,
                        RejectionReason = CASE WHEN @Decision = 3 THEN LTRIM(RTRIM(@RejectionReason)) ELSE NULL END,
                        UpdatedAtUtc = @NowUtc
                    OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
                    WHERE Id = @ProjectId AND RowVersion = @ExpectedRowVersion;
                    SELECT @ResultRowVersion = RowVersion FROM @Updated;
                    IF @ResultRowVersion IS NULL SET @Code = N''etag-conflict'';
                    ELSE
                    BEGIN
                        INSERT INTO dbo.FundingPlatform_ProjectPublicationEvents
                            (EventId, ProjectId, ProjectVersion, OrganizationProfileVersion,
                             FromStatus, ToStatus, ActionCode, ActorUserId, Reason,
                             IdempotencyKeyHash, RequestHash, ResultRowVersion, CreatedAtUtc)
                        VALUES
                            (@EventId, @ProjectId, @ProjectVersion, @OrganizationProfileVersion,
                             @CurrentStatus, @Decision, N''AdminReview'', @AdminUserId,
                             CASE WHEN @Decision = 3 THEN LTRIM(RTRIM(@RejectionReason)) ELSE NULL END,
                             @IdempotencyKeyHash, @RequestHash, @ResultRowVersion, @NowUtc);
                        INSERT INTO dbo.FundingPlatform_OutboxMessages
                            (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                             OccurredAtUtc, AvailableAtUtc)
                        SELECT @EventId,
                               CASE WHEN @Decision = 2 THEN N''ProjectPublished'' ELSE N''ProjectRejected'' END,
                               N''Project'', CONVERT(NVARCHAR(100), @ProjectId),
                               (SELECT @EventId AS eventId, @ProjectId AS projectId,
                                       @ProjectPublicId AS projectPublicId, @CurrentStatus AS fromStatus,
                                       @Decision AS toStatus, @ProjectVersion AS projectVersion,
                                       @OrganizationProfileVersion AS organizationProfileVersion
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                               @NowUtc, @NowUtc;
                        SET @Succeeded = 1;
                        SET @Code = CASE WHEN @Decision = 2 THEN N''published'' ELSE N''rejected'' END;
                        SET @CurrentStatus = @Decision;
                        SET @ReviewedAtUtc = @NowUtc;
                        SET @ReviewedByUserPublicId = @AdminUserPublicId;
                        SET @CurrentRejectionReason = CASE WHEN @Decision = 3 THEN LTRIM(RTRIM(@RejectionReason)) ELSE NULL END;
                        IF @Decision = 2 SET @PublishedAtUtc = @NowUtc;
                    END
                END
            END
        END
        IF @ResultRowVersion IS NULL SET @ResultRowVersion = @CurrentRowVersion;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_AdminReviewProject;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, CAST(NULL AS DECIMAL(5,2)) AS Completeness,
           @ProjectPublicId AS ProjectPublicId, @CurrentStatus AS PublicationStatus,
           @SubmittedAtUtc AS SubmittedAtUtc, @PublishedAtUtc AS PublishedAtUtc,
           @ReviewedAtUtc AS ReviewedAtUtc, @ReviewedByUserPublicId AS ReviewedByUserPublicId,
           @CurrentRejectionReason AS RejectionReason, @ResultRowVersion AS RowVersion,
           @WasReplay AS WasReplay;
END;';


EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Project_Archive
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @UserPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @Reason NVARCHAR(1000) = NULL,
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @ProjectId BIGINT, @ActorUserId BIGINT, @CurrentStatus TINYINT;
    DECLARE @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @SubmittedAtUtc DATETIME2(3), @PublishedAtUtc DATETIME2(3), @ReviewedAtUtc DATETIME2(3);
    DECLARE @ReviewedByUserPublicId UNIQUEIDENTIFIER, @RejectionReason NVARCHAR(1000);
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32);
    DECLARE @ExistingToStatus TINYINT, @ExistingResultRowVersion BINARY(8);
    DECLARE @ProjectVersion INT, @OrganizationProfileVersion INT;
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @Code NVARCHAR(50) = N''not-found'';
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_ArchiveProject;
    BEGIN TRY
        SELECT @ProjectId = projects.Id, @ActorUserId = users.Id,
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
        LEFT JOIN dbo.FundingPlatform_Users AS reviewer ON reviewer.Id = projects.ReviewedByUserId
        WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1
          AND users.PublicId = @UserPublicId AND projects.PublicId = @ProjectPublicId;

        IF @ProjectId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = events.ActionCode,
                   @ExistingRequestHash = events.RequestHash,
                   @ExistingToStatus = events.ToStatus,
                   @ExistingResultRowVersion = events.ResultRowVersion
            FROM dbo.FundingPlatform_ProjectPublicationEvents AS events WITH (UPDLOCK, HOLDLOCK)
            WHERE events.ProjectId = @ProjectId AND events.IdempotencyKeyHash = @IdempotencyKeyHash;

            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N''Archive'' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N''archived'';
                    SET @CurrentStatus = @ExistingToStatus;
                    SET @ResultRowVersion = @ExistingResultRowVersion;
                END
                ELSE SET @Code = N''idempotency-conflict'';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N''etag-conflict'';
            ELSE IF @CurrentStatus NOT IN (0, 1, 2, 3) SET @Code = N''invalid-transition'';
            ELSE
            BEGIN
                DECLARE @Updated TABLE (RowVersion BINARY(8) NOT NULL);
                UPDATE dbo.FundingPlatform_Projects
                SET PublicationStatus = 4, UpdatedAtUtc = @NowUtc
                OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
                WHERE Id = @ProjectId AND RowVersion = @ExpectedRowVersion;
                SELECT @ResultRowVersion = RowVersion FROM @Updated;
                IF @ResultRowVersion IS NULL SET @Code = N''etag-conflict'';
                ELSE
                BEGIN
                    INSERT INTO dbo.FundingPlatform_ProjectPublicationEvents
                        (EventId, ProjectId, ProjectVersion, OrganizationProfileVersion,
                         FromStatus, ToStatus, ActionCode, ActorUserId, Reason,
                         IdempotencyKeyHash, RequestHash, ResultRowVersion, CreatedAtUtc)
                    VALUES
                        (@EventId, @ProjectId, @ProjectVersion, @OrganizationProfileVersion,
                         @CurrentStatus, 4, N''Archive'', @ActorUserId,
                         NULLIF(LTRIM(RTRIM(@Reason)), N''''), @IdempotencyKeyHash,
                         @RequestHash, @ResultRowVersion, @NowUtc);
                    INSERT INTO dbo.FundingPlatform_OutboxMessages
                        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                         OccurredAtUtc, AvailableAtUtc)
                    SELECT @EventId, N''ProjectArchived'', N''Project'', CONVERT(NVARCHAR(100), @ProjectId),
                           (SELECT @EventId AS eventId, @ProjectId AS projectId,
                                   @ProjectPublicId AS projectPublicId, @CurrentStatus AS fromStatus,
                                   4 AS toStatus, @ProjectVersion AS projectVersion,
                                   @OrganizationProfileVersion AS organizationProfileVersion
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                           @NowUtc, @NowUtc;
                    SET @Succeeded = 1; SET @Code = N''archived''; SET @CurrentStatus = 4;
                END
            END
        END
        IF @ResultRowVersion IS NULL SET @ResultRowVersion = @CurrentRowVersion;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_ArchiveProject;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, CAST(NULL AS DECIMAL(5,2)) AS Completeness,
           @ProjectPublicId AS ProjectPublicId, @CurrentStatus AS PublicationStatus,
           @SubmittedAtUtc AS SubmittedAtUtc, @PublishedAtUtc AS PublishedAtUtc,
           @ReviewedAtUtc AS ReviewedAtUtc, @ReviewedByUserPublicId AS ReviewedByUserPublicId,
           @RejectionReason AS RejectionReason, @ResultRowVersion AS RowVersion,
           @WasReplay AS WasReplay;
END;';


EXEC sys.sp_executesql N'
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
    SET NOCOUNT ON; SET XACT_ABORT ON;

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
    DECLARE @Code NVARCHAR(50) = N''not-found'', @Completeness DECIMAL(5,2) = 0;
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
                IF @ExistingAction = N''RequestPublication'' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1;
                    SET @WasReplay = 1;
                    SET @Code = N''publication-requested'';
                    SET @Completeness = 100;
                    SET @CurrentStatus = @ExistingToStatus;
                    SET @ResultRowVersion = @ExistingResultRowVersion;
                END
                ELSE SET @Code = N''idempotency-conflict'';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion
                SET @Code = N''etag-conflict'';
            ELSE IF @CurrentStatus NOT IN (0, 3)
                SET @Code = N''invalid-transition'';
            ELSE
            BEGIN
                IF @OrganizationIsActive <> 1 OR @OrganizationProfileStatus <> 2 OR @OrganizationCompleteness < 80
                    INSERT INTO @Issues VALUES
                        (N''organizationProfile'', N''organizationProfile'', N''The organization profile must be complete and at least 80 percent.'');
                IF NOT EXISTS
                (
                    SELECT 1 FROM dbo.FundingPlatform_Projects
                    WHERE Id = @ProjectId AND NULLIF(LTRIM(RTRIM(Title)), N'''') IS NOT NULL
                ) INSERT INTO @Issues VALUES (N''title'', N''title'', N''Title is required.'');
                IF NOT EXISTS
                (
                    SELECT 1 FROM dbo.FundingPlatform_Projects
                    WHERE Id = @ProjectId AND NULLIF(LTRIM(RTRIM(Summary)), N'''') IS NOT NULL
                ) INSERT INTO @Issues VALUES (N''summary'', N''summary'', N''Summary is required.'');
                IF NOT EXISTS
                (
                    SELECT 1 FROM dbo.FundingPlatform_Projects
                    WHERE Id = @ProjectId AND NULLIF(LTRIM(RTRIM(Description)), N'''') IS NOT NULL
                ) INSERT INTO @Issues VALUES (N''description'', N''description'', N''Description is required.'');
                IF NOT EXISTS
                (
                    SELECT 1 FROM dbo.FundingPlatform_Projects
                    WHERE Id = @ProjectId AND NULLIF(LTRIM(RTRIM(Slug)), N'''') IS NOT NULL
                ) INSERT INTO @Issues VALUES (N''slug'', N''slug'', N''A public slug is required.'');
                IF NOT EXISTS
                (
                    SELECT 1 FROM dbo.FundingPlatform_Projects
                    WHERE Id = @ProjectId AND BudgetTotal > 0 AND Currency IS NOT NULL
                ) INSERT INTO @Issues VALUES (N''budget'', N''budgetTotal'', N''A positive budget and currency are required.'');
                IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectCountries WHERE ProjectId = @ProjectId)
                    INSERT INTO @Issues VALUES (N''countries'', N''countryIds'', N''At least one country is required.'');
                IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectCategories WHERE ProjectId = @ProjectId)
                    INSERT INTO @Issues VALUES (N''categories'', N''categoryIds'', N''At least one category is required.'');
                IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectBeneficiaryTypes WHERE ProjectId = @ProjectId)
                    INSERT INTO @Issues VALUES (N''beneficiaries'', N''beneficiaryTypeIds'', N''At least one beneficiary type is required.'');
                IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectProjectTypes WHERE ProjectId = @ProjectId)
                    INSERT INTO @Issues VALUES (N''projectTypes'', N''projectTypeIds'', N''At least one project type is required.'');

                SET @Completeness = CONVERT(DECIMAL(5,2), 100 - ((SELECT COUNT(1) FROM @Issues) * 10));

                IF EXISTS (SELECT 1 FROM @Issues)
                    SET @Code = N''project-not-ready'';
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
                        SET @Code = N''etag-conflict'';
                    ELSE
                    BEGIN
                        INSERT INTO dbo.FundingPlatform_ProjectPublicationEvents
                            (EventId, ProjectId, ProjectVersion, OrganizationProfileVersion,
                             FromStatus, ToStatus, ActionCode, ActorUserId, Reason,
                             IdempotencyKeyHash, RequestHash, ResultRowVersion, CreatedAtUtc)
                        VALUES
                            (@EventId, @ProjectId, @ProjectVersion, @OrganizationProfileVersion,
                             @CurrentStatus, 1, N''RequestPublication'', @ActorUserId,
                             NULL, @IdempotencyKeyHash, @RequestHash, @ResultRowVersion, @NowUtc);

                        INSERT INTO dbo.FundingPlatform_OutboxMessages
                            (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                             OccurredAtUtc, AvailableAtUtc)
                        SELECT @EventId, N''ProjectPublicationRequested'', N''Project'',
                               CONVERT(NVARCHAR(100), @ProjectId),
                               (SELECT @EventId AS eventId, @ProjectId AS projectId,
                                       @ProjectPublicId AS projectPublicId, @CurrentStatus AS fromStatus,
                                       1 AS toStatus, @ProjectVersion AS projectVersion,
                                       @OrganizationProfileVersion AS organizationProfileVersion
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                               @NowUtc, @NowUtc;
                        SET @Succeeded = 1;
                        SET @Code = N''publication-requested'';
                        SET @CurrentStatus = 1;
                        SET @SubmittedAtUtc = @NowUtc;
                        SET @RejectionReason = NULL;
                    END
                END
            END
        END

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
           @ReviewedAtUtc AS ReviewedAtUtc, @ReviewedByUserPublicId AS ReviewedByUserPublicId,
           @RejectionReason AS RejectionReason, @ResultRowVersion AS RowVersion,
           @WasReplay AS WasReplay;
    SELECT Code, FieldPath, Message FROM @Issues ORDER BY FieldPath, Code;
END;';
