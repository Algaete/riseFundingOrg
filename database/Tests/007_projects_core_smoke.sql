SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @RequiredProcedures TABLE (Name SYSNAME NOT NULL PRIMARY KEY);
INSERT INTO @RequiredProcedures (Name) VALUES
    (N'FundingPlatform_usp_Project_List'),
    (N'FundingPlatform_usp_Project_Create'),
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
    THROW 52701, N'One or more FASE 5 project procedures are missing.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FundingPlatform_Smoke007;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @UserAPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @UserBPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @EmailA NVARCHAR(320) = N'project-a-' + REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'') + N'@example.invalid';
    DECLARE @EmailB NVARCHAR(320) = N'project-b-' + REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'') + N'@example.invalid';

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, Status, PreferredLocale)
    VALUES
        (@UserAPublicId, @EmailA, UPPER(@EmailA), N'Project tenant A', N'not-a-credential', N'project-a', 1, 2, N'es-CL'),
        (@UserBPublicId, @EmailB, UPPER(@EmailB), N'Project tenant B', N'not-a-credential', N'project-b', 1, 2, N'es-CL');

    DECLARE @OrganizationA TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProfileVersion INT, RowVersion BINARY(8));
    DECLARE @OrganizationB TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProfileVersion INT, RowVersion BINARY(8));
    DECLARE @OrganizationSnapshot NVARCHAR(MAX) = N'{"name":"Project smoke organization"}';
    DECLARE @OrganizationHash BINARY(32) = HASHBYTES('SHA2_256', @OrganizationSnapshot);

    INSERT INTO @OrganizationA EXEC dbo.FundingPlatform_usp_Organization_CreateForUser
        @UserPublicId = @UserAPublicId, @Name = N'Project tenant A', @HomeCountryId = 152,
        @OrganizationTypeId = 2, @SnapshotJson = @OrganizationSnapshot, @ContentHash = @OrganizationHash;
    INSERT INTO @OrganizationB EXEC dbo.FundingPlatform_usp_Organization_CreateForUser
        @UserPublicId = @UserBPublicId, @Name = N'Project tenant B', @HomeCountryId = 152,
        @OrganizationTypeId = 2, @SnapshotJson = @OrganizationSnapshot, @ContentHash = @OrganizationHash;

    DECLARE @OrganizationAPublicId UNIQUEIDENTIFIER = (SELECT PublicId FROM @OrganizationA);
    DECLARE @OrganizationBPublicId UNIQUEIDENTIFIER = (SELECT PublicId FROM @OrganizationB);
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

    DECLARE @Snapshot1 NVARCHAR(MAX) = N'{"title":"Agua rural"}';
    DECLARE @Snapshot2 NVARCHAR(MAX) = N'{"title":"Educacion digital"}';
    DECLARE @Hash1 BINARY(32) = HASHBYTES('SHA2_256', @Snapshot1);
    DECLARE @Hash2 BINARY(32) = HASHBYTES('SHA2_256', @Snapshot2);
    DECLARE @Created1 TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProjectVersion INT, RowVersion BINARY(8));
    DECLARE @Created2 TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProjectVersion INT, RowVersion BINARY(8));

    INSERT INTO @Created1 EXEC dbo.FundingPlatform_usp_Project_Create
        @OrganizationPublicId = @OrganizationAPublicId, @UserPublicId = @UserAPublicId,
        @Slug = N'agua-rural-smoke', @Title = N'Agua rural', @Summary = N'Acceso sostenible al agua',
        @Description = N'Proyecto para comunidades rurales.', @ProjectStatus = 2,
        @StartDate = '2027-01-01', @EndDate = '2027-12-31', @BudgetTotal = 100000,
        @ConfirmedFunding = 25000, @Currency = 'CLP', @SnapshotJson = @Snapshot1,
        @ContentHash = @Hash1, @CountryIds = @CountryIds,
        @RegionIds = @RegionIds, @CategoryIds = @CategoryIds,
        @BeneficiaryTypeIds = @BeneficiaryTypeIds, @ProjectTypeIds = @ProjectTypeIds;
    INSERT INTO @Created2 EXEC dbo.FundingPlatform_usp_Project_Create
        @OrganizationPublicId = @OrganizationAPublicId, @UserPublicId = @UserAPublicId,
        @Slug = N'educacion-digital-smoke', @Title = N'Educacion digital', @ProjectStatus = 1,
        @BudgetTotal = 50000, @ConfirmedFunding = NULL, @Currency = 'CLP',
        @SnapshotJson = @Snapshot2, @ContentHash = @Hash2,
        @CountryIds = @CountryIds, @RegionIds = @RegionIds, @CategoryIds = @CategoryIds,
        @BeneficiaryTypeIds = @BeneficiaryTypeIds, @ProjectTypeIds = @ProjectTypeIds;

    DECLARE @ProjectId BIGINT = (SELECT Id FROM @Created1);
    DECLARE @ProjectPublicId UNIQUEIDENTIFIER = (SELECT PublicId FROM @Created1);
    DECLARE @InitialRowVersion BINARY(8) = (SELECT RowVersion FROM @Created1);
    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_Projects WHERE OrganizationId = (SELECT Id FROM @OrganizationA)) <> 2
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId AND FundingGap = 75000)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectVersions WHERE ProjectId = @ProjectId AND ProjectVersion = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages WHERE AggregateType = N'Project' AND AggregateId = CONVERT(NVARCHAR(100), @ProjectId) AND MessageType = N'ProjectCreated')
        THROW 52702, N'Project creation, versioning, funding gap or outbox failed.', 1;

    DECLARE @ListedA TABLE
    (
        PublicId UNIQUEIDENTIFIER, Slug NVARCHAR(180), Title NVARCHAR(250), Summary NVARCHAR(1000),
        ProjectStatus TINYINT, PublicationStatus TINYINT, StartDate DATE, EndDate DATE,
        BudgetTotal DECIMAL(19,4), ConfirmedFunding DECIMAL(19,4), Currency CHAR(3),
        FundingGap DECIMAL(19,4), ProjectVersion INT, UpdatedAtUtc DATETIME2(3)
    );
    INSERT INTO @ListedA EXEC dbo.FundingPlatform_usp_Project_List
        @OrganizationPublicId = @OrganizationAPublicId, @UserPublicId = @UserAPublicId;
    IF (SELECT COUNT(*) FROM @ListedA) <> 2
        THROW 52703, N'Tenant A cannot list its two distinct projects.', 1;

    DECLARE @ListedB TABLE
    (
        PublicId UNIQUEIDENTIFIER, Slug NVARCHAR(180), Title NVARCHAR(250), Summary NVARCHAR(1000),
        ProjectStatus TINYINT, PublicationStatus TINYINT, StartDate DATE, EndDate DATE,
        BudgetTotal DECIMAL(19,4), ConfirmedFunding DECIMAL(19,4), Currency CHAR(3),
        FundingGap DECIMAL(19,4), ProjectVersion INT, UpdatedAtUtc DATETIME2(3)
    );
    INSERT INTO @ListedB EXEC dbo.FundingPlatform_usp_Project_List
        @OrganizationPublicId = @OrganizationBPublicId, @UserPublicId = @UserBPublicId;
    IF EXISTS (SELECT 1 FROM @ListedB)
        THROW 52704, N'Projects leaked into the other organization tenant.', 1;

    DECLARE @UpdatedSnapshot NVARCHAR(MAX) = N'{"title":"Agua rural ampliada"}';
    DECLARE @UpdatedHash BINARY(32) = HASHBYTES('SHA2_256', @UpdatedSnapshot);
    DECLARE @Updated TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProjectVersion INT, RowVersion BINARY(8));
    INSERT INTO @Updated EXEC dbo.FundingPlatform_usp_Project_Update
        @OrganizationPublicId = @OrganizationAPublicId, @ProjectPublicId = @ProjectPublicId,
        @UserPublicId = @UserAPublicId, @ExpectedRowVersion = @InitialRowVersion,
        @Title = N'Agua rural ampliada', @ProjectStatus = 3, @BudgetTotal = 120000,
        @ConfirmedFunding = 30000, @Currency = 'CLP', @SnapshotJson = @UpdatedSnapshot,
        @ContentHash = @UpdatedHash, @CountryIds = @CountryIds,
        @RegionIds = @RegionIds, @CategoryIds = @CategoryIds,
        @BeneficiaryTypeIds = @BeneficiaryTypeIds, @ProjectTypeIds = @ProjectTypeIds;

    IF NOT EXISTS (SELECT 1 FROM @Updated WHERE ProjectVersion = 2 AND RowVersion <> @InitialRowVersion)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectVersions WHERE ProjectId = @ProjectId AND ProjectVersion = 2)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId AND FundingGap = 90000 AND ProjectStatus = 3)
       OR NOT EXISTS (SELECT 1 FROM @Created2 WHERE ProjectVersion = 1)
        THROW 52705, N'Project update mixed versions, states or funding needs.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FundingPlatform_Smoke007;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION FundingPlatform_Smoke007;
    THROW;
END CATCH;

SELECT CAST(1 AS BIT) AS Succeeded;
