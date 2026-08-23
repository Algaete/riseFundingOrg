/* Transactional smoke for moderated project publication. Fixture data is rolled back. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @RequiredProcedures TABLE (Name SYSNAME NOT NULL PRIMARY KEY);
INSERT INTO @RequiredProcedures (Name) VALUES
    (N'FundingPlatform_usp_Project_RequestPublication'),
    (N'FundingPlatform_usp_Project_Archive'),
    (N'FundingPlatform_usp_Project_AdminReviewQueue_List'),
    (N'FundingPlatform_usp_Project_AdminReview_Get'),
    (N'FundingPlatform_usp_Project_AdminReview'),
    (N'FundingPlatform_usp_Project_Public_GetBySlug'),
    (N'FundingPlatform_usp_Project_Get'),
    (N'FundingPlatform_usp_Project_Update');

IF EXISTS
(
    SELECT 1
    FROM @RequiredProcedures AS required
    LEFT JOIN sys.procedures AS actual
        ON actual.name COLLATE DATABASE_DEFAULT = required.Name COLLATE DATABASE_DEFAULT
       AND actual.schema_id = SCHEMA_ID(N'dbo')
    WHERE actual.object_id IS NULL
)
    THROW 52801, N'One or more project publication procedures are missing.', 1;

IF OBJECT_ID(N'dbo.FundingPlatform_ProjectPublicationEvents', N'U') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_Projects', N'SubmittedAtUtc') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_Projects', N'PublishedAtUtc') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_Projects', N'ReviewedAtUtc') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_Projects', N'ReviewedByUserId') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_Projects', N'RejectionReason') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_ProjectPublicationEvents', N'ProjectVersion') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_ProjectPublicationEvents', N'OrganizationProfileVersion') IS NULL
    THROW 52802, N'Project publication schema is incomplete.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FundingPlatform_Smoke008;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @Suffix NVARCHAR(32) = REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'');
    DECLARE @AdminPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @UserAPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @UserBPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @AdminEmail NVARCHAR(320) = N'workflow-admin-' + @Suffix + N'@example.invalid';
    DECLARE @EmailA NVARCHAR(320) = N'workflow-a-' + @Suffix + N'@example.invalid';
    DECLARE @EmailB NVARCHAR(320) = N'workflow-b-' + @Suffix + N'@example.invalid';

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, Status, PreferredLocale)
    VALUES
        (@AdminPublicId, @AdminEmail, UPPER(@AdminEmail), N'Publication Admin',
         N'not-a-credential', N'workflow-admin', 1, 2, N'es-CL'),
        (@UserAPublicId, @EmailA, UPPER(@EmailA), N'Publication tenant A',
         N'not-a-credential', N'workflow-a', 1, 2, N'es-CL'),
        (@UserBPublicId, @EmailB, UPPER(@EmailB), N'Publication tenant B',
         N'not-a-credential', N'workflow-b', 1, 2, N'es-CL');

    DECLARE @AdminUserId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @AdminPublicId);
    DECLARE @AdminRoleId SMALLINT =
        (SELECT Id FROM dbo.FundingPlatform_Roles WHERE NormalizedName = N'ADMIN');
    INSERT INTO dbo.FundingPlatform_UserRoles (UserId, RoleId, GrantedByUserId)
    VALUES (@AdminUserId, @AdminRoleId, @AdminUserId);

    DECLARE @OrganizationA TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProfileVersion INT, RowVersion BINARY(8));
    DECLARE @OrganizationB TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProfileVersion INT, RowVersion BINARY(8));
    DECLARE @OrganizationSnapshot NVARCHAR(MAX) = N'{"name":"Publication smoke organization"}';
    DECLARE @OrganizationHash BINARY(32) = HASHBYTES('SHA2_256', @OrganizationSnapshot);

    INSERT INTO @OrganizationA EXEC dbo.FundingPlatform_usp_Organization_CreateForUser
        @UserPublicId = @UserAPublicId, @Name = N'Publication tenant A', @HomeCountryId = 152,
        @OrganizationTypeId = 2, @SnapshotJson = @OrganizationSnapshot,
        @ContentHash = @OrganizationHash;
    INSERT INTO @OrganizationB EXEC dbo.FundingPlatform_usp_Organization_CreateForUser
        @UserPublicId = @UserBPublicId, @Name = N'Publication tenant B', @HomeCountryId = 152,
        @OrganizationTypeId = 2, @SnapshotJson = @OrganizationSnapshot,
        @ContentHash = @OrganizationHash;

    DECLARE @OrganizationAId BIGINT = (SELECT Id FROM @OrganizationA);
    DECLARE @OrganizationAPublicId UNIQUEIDENTIFIER = (SELECT PublicId FROM @OrganizationA);
    DECLARE @OrganizationBPublicId UNIQUEIDENTIFIER = (SELECT PublicId FROM @OrganizationB);
    UPDATE dbo.FundingPlatform_Organizations
    SET TaxIdentifier = N'SENSITIVE-SMOKE-TAX-ID', WebsiteUrl = N'https://ong-a.example.invalid'
    WHERE Id = @OrganizationAId;

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

    DECLARE @EmptySmallIds dbo.FundingPlatform_SmallIntIdList;
    DECLARE @EmptyIntIds dbo.FundingPlatform_IntIdList;
    DECLARE @MainSlug NVARCHAR(180) = N'public-project-' + @Suffix;
    DECLARE @IncompleteSlug NVARCHAR(180) = N'incomplete-project-' + @Suffix;
    DECLARE @Snapshot1 NVARCHAR(MAX) = N'{"title":"Agua segura"}';
    DECLARE @Hash1 BINARY(32) = HASHBYTES('SHA2_256', @Snapshot1);
    DECLARE @CreatedMain TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProjectVersion INT, RowVersion BINARY(8));
    DECLARE @CreatedIncomplete TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProjectVersion INT, RowVersion BINARY(8));

    INSERT INTO @CreatedMain EXEC dbo.FundingPlatform_usp_Project_Create
        @OrganizationPublicId = @OrganizationAPublicId, @UserPublicId = @UserAPublicId,
        @Slug = @MainSlug, @Title = N'Agua segura', @Summary = N'Agua segura para comunidades rurales',
        @Description = N'Implementación de sistemas comunitarios sostenibles de agua potable.',
        @ProjectStatus = 2, @StartDate = '2027-01-01', @EndDate = '2027-12-31',
        @BudgetTotal = 100000, @ConfirmedFunding = 25000, @Currency = 'CLP',
        @SnapshotJson = @Snapshot1, @ContentHash = @Hash1, @CountryIds = @CountryIds,
        @RegionIds = @RegionIds, @CategoryIds = @CategoryIds,
        @BeneficiaryTypeIds = @BeneficiaryTypeIds, @ProjectTypeIds = @ProjectTypeIds;

    INSERT INTO @CreatedIncomplete EXEC dbo.FundingPlatform_usp_Project_Create
        @OrganizationPublicId = @OrganizationAPublicId, @UserPublicId = @UserAPublicId,
        @Slug = @IncompleteSlug, @Title = N'Proyecto incompleto', @Summary = NULL,
        @Description = NULL, @ProjectStatus = 0, @BudgetTotal = NULL,
        @ConfirmedFunding = NULL, @Currency = NULL,
        @SnapshotJson = N'{"title":"Proyecto incompleto"}',
        @ContentHash = 0x0000000000000000000000000000000000000000000000000000000000000000,
        @CountryIds = @EmptySmallIds, @RegionIds = @EmptyIntIds,
        @CategoryIds = @EmptyIntIds, @BeneficiaryTypeIds = @EmptyIntIds,
        @ProjectTypeIds = @EmptyIntIds;

    DECLARE @MainProjectId BIGINT = (SELECT Id FROM @CreatedMain);
    DECLARE @MainProjectPublicId UNIQUEIDENTIFIER = (SELECT PublicId FROM @CreatedMain);
    DECLARE @DraftRowVersion BINARY(8) = (SELECT RowVersion FROM @CreatedMain);
    DECLARE @IncompleteProjectId BIGINT = (SELECT Id FROM @CreatedIncomplete);
    DECLARE @IncompleteProjectPublicId UNIQUEIDENTIFIER = (SELECT PublicId FROM @CreatedIncomplete);
    DECLARE @IncompleteRowVersion BINARY(8) = (SELECT RowVersion FROM @CreatedIncomplete);

    DECLARE @PublicProjection TABLE
    (
        ProjectPublicId UNIQUEIDENTIFIER, Slug NVARCHAR(180), Title NVARCHAR(250),
        Summary NVARCHAR(1000), Description NVARCHAR(MAX), ProjectStatus TINYINT,
        StartDate DATE, EndDate DATE, BudgetTotal DECIMAL(19,4),
        ConfirmedFunding DECIMAL(19,4), Currency CHAR(3), FundingGap DECIMAL(19,4),
        ProjectVersion INT, PublishedAtUtc DATETIME2(3), UpdatedAtUtc DATETIME2(3),
        OrganizationPublicId UNIQUEIDENTIFIER, OrganizationName NVARCHAR(250),
        OrganizationWebsiteUrl NVARCHAR(2048), CountriesJson NVARCHAR(MAX),
        RegionsJson NVARCHAR(MAX), CategoriesJson NVARCHAR(MAX),
        BeneficiaryTypesJson NVARCHAR(MAX), ProjectTypesJson NVARCHAR(MAX)
    );
    INSERT INTO @PublicProjection EXEC dbo.FundingPlatform_usp_Project_Public_GetBySlug @Slug = @MainSlug;
    IF EXISTS (SELECT 1 FROM @PublicProjection)
        THROW 52803, N'A draft project was exposed by the public projection.', 1;

    DECLARE @Code NVARCHAR(50), @Completeness DECIMAL(5,2);
    DECLARE @ReadinessKey BINARY(32) = HASHBYTES('SHA2_256', N'org-readiness-' + @Suffix);
    DECLARE @ReadinessRequest BINARY(32) = HASHBYTES('SHA2_256', N'org-readiness-request-' + @Suffix);
    EXEC dbo.FundingPlatform_usp_Project_RequestPublication
        @OrganizationPublicId = @OrganizationAPublicId, @ProjectPublicId = @MainProjectPublicId,
        @UserPublicId = @UserAPublicId, @ExpectedRowVersion = @DraftRowVersion,
        @IdempotencyKeyHash = @ReadinessKey, @RequestHash = @ReadinessRequest,
        @ResultCode = @Code OUTPUT, @ResultCompleteness = @Completeness OUTPUT;
    IF @Code <> N'project-not-ready' OR @Completeness <> 90
       OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectPublicationEvents WHERE ProjectId = @MainProjectId)
        THROW 52804, N'Organization profile readiness did not block publication.', 1;

    UPDATE dbo.FundingPlatform_Organizations
    SET ProfileStatus = 2, ProfileCompleteness = 100
    WHERE Id = @OrganizationAId;
    DECLARE @ExpectedOrganizationProfileVersion INT =
        (SELECT ProfileVersion FROM dbo.FundingPlatform_Organizations WHERE Id = @OrganizationAId);

    SET @Code = NULL; SET @Completeness = NULL;
    EXEC dbo.FundingPlatform_usp_Project_RequestPublication
        @OrganizationPublicId = @OrganizationAPublicId, @ProjectPublicId = @IncompleteProjectPublicId,
        @UserPublicId = @UserAPublicId, @ExpectedRowVersion = @IncompleteRowVersion,
        @IdempotencyKeyHash = 0x0101010101010101010101010101010101010101010101010101010101010101,
        @RequestHash = 0x0202020202020202020202020202020202020202020202020202020202020202,
        @ResultCode = @Code OUTPUT, @ResultCompleteness = @Completeness OUTPUT;
    IF @Code <> N'project-not-ready' OR @Completeness >= 100
       OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectPublicationEvents WHERE ProjectId = @IncompleteProjectId)
        THROW 52805, N'Incomplete project content was accepted for review.', 1;

    SET @Code = NULL; SET @Completeness = NULL;
    EXEC dbo.FundingPlatform_usp_Project_RequestPublication
        @OrganizationPublicId = @OrganizationBPublicId, @ProjectPublicId = @MainProjectPublicId,
        @UserPublicId = @UserBPublicId, @ExpectedRowVersion = @DraftRowVersion,
        @IdempotencyKeyHash = 0x0303030303030303030303030303030303030303030303030303030303030303,
        @RequestHash = 0x0404040404040404040404040404040404040404040404040404040404040404,
        @ResultCode = @Code OUTPUT, @ResultCompleteness = @Completeness OUTPUT;
    IF @Code <> N'not-found'
       OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectPublicationEvents WHERE ProjectId = @MainProjectId)
        THROW 52806, N'Tenant B could observe or transition tenant A project.', 1;

    DECLARE @Request1Key BINARY(32) = HASHBYTES('SHA2_256', N'request-1-' + @Suffix);
    DECLARE @Request1Hash BINARY(32) = HASHBYTES('SHA2_256', N'request-1-body-' + @Suffix);
    SET @Code = NULL; SET @Completeness = NULL;
    EXEC dbo.FundingPlatform_usp_Project_RequestPublication
        @OrganizationPublicId = @OrganizationAPublicId, @ProjectPublicId = @MainProjectPublicId,
        @UserPublicId = @UserAPublicId, @ExpectedRowVersion = @DraftRowVersion,
        @IdempotencyKeyHash = @Request1Key, @RequestHash = @Request1Hash,
        @ResultCode = @Code OUTPUT, @ResultCompleteness = @Completeness OUTPUT;
    IF @Code <> N'publication-requested' OR @Completeness <> 100
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Projects WHERE Id = @MainProjectId AND PublicationStatus = 1 AND SubmittedAtUtc IS NOT NULL)
        THROW 52807, N'Complete project did not enter PendingReview.', 1;

    DECLARE @Pending1RowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_Projects WHERE Id = @MainProjectId);
    SET @Code = NULL;
    EXEC dbo.FundingPlatform_usp_Project_RequestPublication
        @OrganizationPublicId = @OrganizationAPublicId, @ProjectPublicId = @MainProjectPublicId,
        @UserPublicId = @UserAPublicId, @ExpectedRowVersion = @DraftRowVersion,
        @IdempotencyKeyHash = @Request1Key, @RequestHash = @Request1Hash,
        @ResultCode = @Code OUTPUT, @ResultCompleteness = @Completeness OUTPUT;
    IF @Code <> N'publication-requested'
       OR (SELECT COUNT(*) FROM dbo.FundingPlatform_ProjectPublicationEvents WHERE ProjectId = @MainProjectId) <> 1
       OR (SELECT COUNT(*)
           FROM dbo.FundingPlatform_ProjectPublicationEvents AS events
           INNER JOIN dbo.FundingPlatform_OutboxMessages AS outbox ON outbox.MessageId = events.EventId
           WHERE events.ProjectId = @MainProjectId) <> 1
        THROW 52808, N'Publication request replay was not idempotent.', 1;

    SET @Code = NULL;
    EXEC dbo.FundingPlatform_usp_Project_RequestPublication
        @OrganizationPublicId = @OrganizationAPublicId, @ProjectPublicId = @MainProjectPublicId,
        @UserPublicId = @UserAPublicId, @ExpectedRowVersion = @DraftRowVersion,
        @IdempotencyKeyHash = @Request1Key,
        @RequestHash = 0x0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D0D,
        @ResultCode = @Code OUTPUT, @ResultCompleteness = @Completeness OUTPUT;
    IF @Code <> N'idempotency-conflict'
       OR (SELECT COUNT(*) FROM dbo.FundingPlatform_ProjectPublicationEvents WHERE ProjectId = @MainProjectId) <> 1
       OR (SELECT COUNT(*)
           FROM dbo.FundingPlatform_ProjectPublicationEvents AS events
           INNER JOIN dbo.FundingPlatform_OutboxMessages AS outbox ON outbox.MessageId = events.EventId
           WHERE events.ProjectId = @MainProjectId) <> 1
        THROW 52822, N'Idempotency key reuse with a different request was accepted or duplicated side effects.', 1;

    SET @Code = NULL;
    EXEC dbo.FundingPlatform_usp_Project_RequestPublication
        @OrganizationPublicId = @OrganizationAPublicId, @ProjectPublicId = @MainProjectPublicId,
        @UserPublicId = @UserAPublicId, @ExpectedRowVersion = @Pending1RowVersion,
        @IdempotencyKeyHash = 0x0505050505050505050505050505050505050505050505050505050505050505,
        @RequestHash = 0x0606060606060606060606060606060606060606060606060606060606060606,
        @ResultCode = @Code OUTPUT, @ResultCompleteness = @Completeness OUTPUT;
    IF @Code <> N'invalid-transition'
        THROW 52809, N'PendingReview accepted an invalid second submission.', 1;

    DECLARE @UnauthorizedReviewBlocked BIT = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_Project_AdminReview_Get
            @AdminUserPublicId = @UserAPublicId, @ProjectPublicId = @MainProjectPublicId;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 51503 SET @UnauthorizedReviewBlocked = 1;
        ELSE THROW;
    END CATCH;
    SET XACT_ABORT ON;
    IF @UnauthorizedReviewBlocked = 0
        THROW 52823, N'Non-admin user accessed the publication review detail.', 1;

    DECLARE @AdminReviewDetail TABLE
    (
        ProjectPublicId UNIQUEIDENTIFIER, Slug NVARCHAR(180), Title NVARCHAR(250),
        Summary NVARCHAR(1000), Description NVARCHAR(MAX), ProjectStatus TINYINT,
        PublicationStatus TINYINT, StartDate DATE, EndDate DATE,
        BudgetTotal DECIMAL(19,4), ConfirmedFunding DECIMAL(19,4), Currency CHAR(3),
        FundingGap DECIMAL(19,4), ProjectVersion INT, PublishedAtUtc DATETIME2(3),
        UpdatedAtUtc DATETIME2(3), OrganizationPublicId UNIQUEIDENTIFIER,
        OrganizationName NVARCHAR(250), OrganizationWebsiteUrl NVARCHAR(2048),
        SubmittedAtUtc DATETIME2(3), RejectionReason NVARCHAR(1000),
        Completeness DECIMAL(5,2), RowVersion BINARY(8), CountriesJson NVARCHAR(MAX),
        RegionsJson NVARCHAR(MAX), CategoriesJson NVARCHAR(MAX),
        BeneficiaryTypesJson NVARCHAR(MAX), ProjectTypesJson NVARCHAR(MAX)
    );
    INSERT INTO @AdminReviewDetail EXEC dbo.FundingPlatform_usp_Project_AdminReview_Get
        @AdminUserPublicId = @AdminPublicId, @ProjectPublicId = @MainProjectPublicId;
    IF NOT EXISTS
       (SELECT 1 FROM @AdminReviewDetail
        WHERE ProjectPublicId = @MainProjectPublicId AND PublicationStatus = 1
          AND OrganizationPublicId = @OrganizationAPublicId AND Completeness = 100
          AND RowVersion = @Pending1RowVersion AND ISJSON(CountriesJson) = 1)
       OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_Project_AdminReview_Get'))
          LIKE N'%TaxIdentifier%'
        THROW 52824, N'Admin review detail is incomplete or exposes tenant-sensitive data.', 1;

    EXEC dbo.FundingPlatform_usp_Project_AdminReviewQueue_List
        @AdminUserPublicId = @AdminPublicId, @PageNumber = 1, @PageSize = 20;

    DECLARE @WorkflowResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), Completeness DECIMAL(5,2),
        ProjectPublicId UNIQUEIDENTIFIER, PublicationStatus TINYINT,
        SubmittedAtUtc DATETIME2(3), PublishedAtUtc DATETIME2(3), ReviewedAtUtc DATETIME2(3),
        ReviewedByUserPublicId UNIQUEIDENTIFIER, RejectionReason NVARCHAR(1000),
        RowVersion BINARY(8), WasReplay BIT
    );
    DECLARE @RejectKey BINARY(32) = HASHBYTES('SHA2_256', N'reject-' + @Suffix);
    DECLARE @RejectHash BINARY(32) = HASHBYTES('SHA2_256', N'reject-body-' + @Suffix);
    INSERT INTO @WorkflowResult EXEC dbo.FundingPlatform_usp_Project_AdminReview
        @AdminUserPublicId = @AdminPublicId, @ProjectPublicId = @MainProjectPublicId,
        @Decision = 3, @RejectionReason = N'Clarificar el impacto medible.',
        @ExpectedRowVersion = @Pending1RowVersion,
        @IdempotencyKeyHash = @RejectKey, @RequestHash = @RejectHash;
    IF NOT EXISTS (SELECT 1 FROM @WorkflowResult WHERE Succeeded = 1 AND Code = N'rejected' AND PublicationStatus = 3)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Projects WHERE Id = @MainProjectId AND RejectionReason = N'Clarificar el impacto medible.' AND ReviewedByUserId = @AdminUserId)
        THROW 52810, N'Admin rejection did not persist review metadata and reason.', 1;

    DECLARE @RejectedRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_Projects WHERE Id = @MainProjectId);
    DECLARE @RejectedReviewedAtUtc DATETIME2(3) =
        (SELECT ReviewedAtUtc FROM dbo.FundingPlatform_Projects WHERE Id = @MainProjectId);
    DECLARE @CorrectedSnapshot NVARCHAR(MAX) = N'{"title":"Agua segura","impact":"measurable"}';
    DECLARE @CorrectedHash BINARY(32) = HASHBYTES('SHA2_256', @CorrectedSnapshot);
    DECLARE @Corrected TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProjectVersion INT, RowVersion BINARY(8));
    INSERT INTO @Corrected EXEC dbo.FundingPlatform_usp_Project_Update
        @OrganizationPublicId = @OrganizationAPublicId, @ProjectPublicId = @MainProjectPublicId,
        @UserPublicId = @UserAPublicId, @ExpectedRowVersion = @RejectedRowVersion,
        @Title = N'Agua segura con impacto medible',
        @Summary = N'Agua segura para comunidades rurales',
        @Description = N'Implementación con indicadores verificables de acceso sostenible al agua.',
        @ProjectStatus = 2, @StartDate = '2027-01-01', @EndDate = '2027-12-31',
        @BudgetTotal = 100000, @ConfirmedFunding = 25000, @Currency = 'CLP',
        @SnapshotJson = @CorrectedSnapshot,
        @ContentHash = @CorrectedHash,
        @CountryIds = @CountryIds, @RegionIds = @RegionIds, @CategoryIds = @CategoryIds,
        @BeneficiaryTypeIds = @BeneficiaryTypeIds, @ProjectTypeIds = @ProjectTypeIds;
    DECLARE @CorrectedRowVersion BINARY(8) = (SELECT RowVersion FROM @Corrected);
    IF NOT EXISTS (SELECT 1 FROM @Corrected WHERE ProjectVersion = 2)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Projects WHERE Id = @MainProjectId AND Slug = @MainSlug AND PublicationStatus = 3)
        THROW 52811, N'Rejected project correction or stable slug failed.', 1;

    SET @Code = NULL;
    EXEC dbo.FundingPlatform_usp_Project_RequestPublication
        @OrganizationPublicId = @OrganizationAPublicId, @ProjectPublicId = @MainProjectPublicId,
        @UserPublicId = @UserAPublicId, @ExpectedRowVersion = @RejectedRowVersion,
        @IdempotencyKeyHash = 0x0707070707070707070707070707070707070707070707070707070707070707,
        @RequestHash = 0x0808080808080808080808080808080808080808080808080808080808080808,
        @ResultCode = @Code OUTPUT, @ResultCompleteness = @Completeness OUTPUT;
    IF @Code <> N'etag-conflict'
        THROW 52812, N'Stale ETag was accepted after project correction.', 1;

    DECLARE @Request2Key BINARY(32) = HASHBYTES('SHA2_256', N'request-2-' + @Suffix);
    DECLARE @Request2Hash BINARY(32) = HASHBYTES('SHA2_256', N'request-2-body-' + @Suffix);
    SET @Code = NULL;
    EXEC dbo.FundingPlatform_usp_Project_RequestPublication
        @OrganizationPublicId = @OrganizationAPublicId, @ProjectPublicId = @MainProjectPublicId,
        @UserPublicId = @UserAPublicId, @ExpectedRowVersion = @CorrectedRowVersion,
        @IdempotencyKeyHash = @Request2Key, @RequestHash = @Request2Hash,
        @ResultCode = @Code OUTPUT, @ResultCompleteness = @Completeness OUTPUT;
    IF @Code <> N'publication-requested'
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_Projects WHERE Id = @MainProjectId
           AND PublicationStatus = 1 AND RejectionReason IS NULL
           AND ReviewedAtUtc = @RejectedReviewedAtUtc AND ReviewedByUserId = @AdminUserId)
        THROW 52813, N'Rejected project could not be corrected and resubmitted safely.', 1;

    DECLARE @Pending2RowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_Projects WHERE Id = @MainProjectId);
    UPDATE dbo.FundingPlatform_Organizations SET ProfileCompleteness = 70 WHERE Id = @OrganizationAId;
    DELETE FROM @WorkflowResult;
    DECLARE @PublishKey BINARY(32) = HASHBYTES('SHA2_256', N'publish-' + @Suffix);
    DECLARE @PublishHash BINARY(32) = HASHBYTES('SHA2_256', N'publish-body-' + @Suffix);
    INSERT INTO @WorkflowResult EXEC dbo.FundingPlatform_usp_Project_AdminReview
        @AdminUserPublicId = @AdminPublicId, @ProjectPublicId = @MainProjectPublicId,
        @Decision = 2, @RejectionReason = NULL, @ExpectedRowVersion = @Pending2RowVersion,
        @IdempotencyKeyHash = @PublishKey, @RequestHash = @PublishHash;
    IF NOT EXISTS (SELECT 1 FROM @WorkflowResult WHERE Succeeded = 0 AND Code = N'organization-not-ready')
       OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectPublicationEvents WHERE ProjectId = @MainProjectId AND ToStatus = 2)
        THROW 52814, N'Admin approval ignored regressed organization readiness.', 1;
    DELETE FROM @PublicProjection;
    INSERT INTO @PublicProjection EXEC dbo.FundingPlatform_usp_Project_Public_GetBySlug @Slug = @MainSlug;
    IF EXISTS (SELECT 1 FROM @PublicProjection)
        THROW 52825, N'Project became public after readiness failed during approval.', 1;

    UPDATE dbo.FundingPlatform_Organizations SET ProfileCompleteness = 100 WHERE Id = @OrganizationAId;
    DELETE FROM @WorkflowResult;
    INSERT INTO @WorkflowResult EXEC dbo.FundingPlatform_usp_Project_AdminReview
        @AdminUserPublicId = @AdminPublicId, @ProjectPublicId = @MainProjectPublicId,
        @Decision = 2, @RejectionReason = NULL, @ExpectedRowVersion = @Pending2RowVersion,
        @IdempotencyKeyHash = @PublishKey, @RequestHash = @PublishHash;
    IF NOT EXISTS
       (SELECT 1 FROM @WorkflowResult WHERE Succeeded = 1 AND Code = N'published'
        AND PublicationStatus = 2 AND PublishedAtUtc IS NOT NULL AND RejectionReason IS NULL)
        THROW 52815, N'Admin approval did not publish the ready project.', 1;

    DECLARE @PublishedRowVersion BINARY(8) = (SELECT RowVersion FROM @WorkflowResult);
    DECLARE @PublishedAtUtc DATETIME2(3) = (SELECT PublishedAtUtc FROM @WorkflowResult);
    DELETE FROM @PublicProjection;
    INSERT INTO @PublicProjection EXEC dbo.FundingPlatform_usp_Project_Public_GetBySlug @Slug = @MainSlug;
    IF (SELECT COUNT(*) FROM @PublicProjection) <> 1
       OR NOT EXISTS
          (SELECT 1 FROM @PublicProjection
           WHERE OrganizationPublicId = @OrganizationAPublicId
             AND OrganizationWebsiteUrl = N'https://ong-a.example.invalid'
             AND ISJSON(CountriesJson) = 1 AND JSON_VALUE(CountriesJson, N'$[0].code') = N'CL'
             AND ISJSON(RegionsJson) = 1 AND JSON_VALUE(RegionsJson, N'$[0].countryId') = N'152'
             AND ISJSON(CategoriesJson) = 1 AND JSON_VALUE(CategoriesJson, N'$[0].code') IS NOT NULL
             AND ISJSON(BeneficiaryTypesJson) = 1 AND ISJSON(ProjectTypesJson) = 1)
        THROW 52816, N'Public projection is missing safe organization or catalog data.', 1;

    UPDATE dbo.FundingPlatform_Organizations SET ProfileCompleteness = 70 WHERE Id = @OrganizationAId;
    DELETE FROM @PublicProjection;
    INSERT INTO @PublicProjection EXEC dbo.FundingPlatform_usp_Project_Public_GetBySlug @Slug = @MainSlug;
    IF EXISTS (SELECT 1 FROM @PublicProjection)
        THROW 52826, N'Public projection did not fail closed after organization profile regression.', 1;
    UPDATE dbo.FundingPlatform_Organizations SET ProfileCompleteness = 100 WHERE Id = @OrganizationAId;

    DELETE FROM @WorkflowResult;
    INSERT INTO @WorkflowResult EXEC dbo.FundingPlatform_usp_Project_AdminReview
        @AdminUserPublicId = @AdminPublicId, @ProjectPublicId = @MainProjectPublicId,
        @Decision = 3, @RejectionReason = N'Invalid second review',
        @ExpectedRowVersion = @PublishedRowVersion,
        @IdempotencyKeyHash = 0x0909090909090909090909090909090909090909090909090909090909090909,
        @RequestHash = 0x0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A;
    IF NOT EXISTS (SELECT 1 FROM @WorkflowResult WHERE Succeeded = 0 AND Code = N'invalid-transition')
        THROW 52817, N'Published project accepted an invalid review transition.', 1;

    DECLARE @ArchiveResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), Completeness DECIMAL(5,2),
        ProjectPublicId UNIQUEIDENTIFIER, PublicationStatus TINYINT,
        SubmittedAtUtc DATETIME2(3), PublishedAtUtc DATETIME2(3), ReviewedAtUtc DATETIME2(3),
        ReviewedByUserPublicId UNIQUEIDENTIFIER, RejectionReason NVARCHAR(1000),
        RowVersion BINARY(8), WasReplay BIT
    );
    DECLARE @ArchiveKey BINARY(32) =
        0x0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B;
    INSERT INTO @ArchiveResult EXEC dbo.FundingPlatform_usp_Project_Archive
        @OrganizationPublicId = @OrganizationAPublicId, @ProjectPublicId = @MainProjectPublicId,
        @UserPublicId = @UserAPublicId, @ExpectedRowVersion = @PublishedRowVersion,
        @Reason = N'Publication retired after campaign close.',
        @IdempotencyKeyHash = @ArchiveKey,
        @RequestHash = 0x0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C;
    IF NOT EXISTS
       (SELECT 1 FROM @ArchiveResult WHERE Succeeded = 1 AND PublicationStatus = 4
        AND PublishedAtUtc = @PublishedAtUtc)
        THROW 52818, N'Published project archive failed or lost publication history.', 1;

    DELETE FROM @PublicProjection;
    INSERT INTO @PublicProjection EXEC dbo.FundingPlatform_usp_Project_Public_GetBySlug @Slug = @MainSlug;
    IF EXISTS (SELECT 1 FROM @PublicProjection)
        THROW 52819, N'Archived project remained public.', 1;

    DELETE FROM @WorkflowResult;
    INSERT INTO @WorkflowResult EXEC dbo.FundingPlatform_usp_Project_AdminReview
        @AdminUserPublicId = @AdminPublicId, @ProjectPublicId = @MainProjectPublicId,
        @Decision = 2, @RejectionReason = NULL, @ExpectedRowVersion = @PublishedRowVersion,
        @IdempotencyKeyHash = @PublishKey, @RequestHash = @PublishHash;
    IF NOT EXISTS
       (SELECT 1 FROM @WorkflowResult WHERE Succeeded = 1 AND WasReplay = 1
        AND PublicationStatus = 2 AND RowVersion = @PublishedRowVersion)
        THROW 52820, N'Idempotent replay did not return the original review result.', 1;

    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_ProjectPublicationEvents WHERE ProjectId = @MainProjectId) <> 5
       OR (SELECT COUNT(*)
           FROM dbo.FundingPlatform_ProjectPublicationEvents AS events
           INNER JOIN dbo.FundingPlatform_OutboxMessages AS outbox ON outbox.MessageId = events.EventId
           WHERE events.ProjectId = @MainProjectId) <> 5
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectPublicationEvents
           WHERE ProjectId = @MainProjectId AND FromStatus = 1 AND ToStatus = 3
             AND Reason = N'Clarificar el impacto medible.')
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectPublicationEvents
           WHERE ProjectId = @MainProjectId AND FromStatus = 2 AND ToStatus = 4)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectPublicationEvents
           WHERE ProjectId = @MainProjectId AND IdempotencyKeyHash = @Request1Key
             AND ActionCode = N'RequestPublication' AND ProjectVersion = 1)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectPublicationEvents
           WHERE ProjectId = @MainProjectId AND IdempotencyKeyHash = @RejectKey
             AND ActionCode = N'AdminReview' AND ProjectVersion = 1)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectPublicationEvents
           WHERE ProjectId = @MainProjectId AND IdempotencyKeyHash = @Request2Key
             AND ActionCode = N'RequestPublication' AND ProjectVersion = 2)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectPublicationEvents
           WHERE ProjectId = @MainProjectId AND IdempotencyKeyHash = @PublishKey
             AND ActionCode = N'AdminReview' AND ProjectVersion = 2)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectPublicationEvents
           WHERE ProjectId = @MainProjectId AND IdempotencyKeyHash = @ArchiveKey
             AND ActionCode = N'Archive' AND ProjectVersion = 2)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ProjectPublicationEvents
           WHERE ProjectId = @MainProjectId
             AND OrganizationProfileVersion <> @ExpectedOrganizationProfileVersion)
       OR EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_ProjectPublicationEvents AS events
           INNER JOIN dbo.FundingPlatform_OutboxMessages AS outbox ON outbox.MessageId = events.EventId
           WHERE events.ProjectId = @MainProjectId
             AND (ISNULL(TRY_CONVERT(INT, JSON_VALUE(outbox.PayloadJson, N'$.projectVersion')), -1)
                    <> events.ProjectVersion
                  OR ISNULL(TRY_CONVERT(INT, JSON_VALUE(outbox.PayloadJson, N'$.organizationProfileVersion')), -1)
                    <> events.OrganizationProfileVersion))
       OR EXISTS
          (SELECT events.EventId
           FROM dbo.FundingPlatform_ProjectPublicationEvents AS events
           INNER JOIN dbo.FundingPlatform_OutboxMessages AS outbox ON outbox.MessageId = events.EventId
           WHERE events.ProjectId = @MainProjectId
           GROUP BY events.EventId
           HAVING COUNT(*) <> 1)
        THROW 52821, N'Publication audit or one-to-one idempotent outbox history is incomplete.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FundingPlatform_Smoke008;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FundingPlatform_Smoke008;
    THROW;
END CATCH;

SELECT CAST(1 AS BIT) AS Succeeded;
