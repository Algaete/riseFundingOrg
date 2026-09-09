/* Transactional smoke for migration 033: project stage and official UN SDGs. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF NOT EXISTS
(
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.FundingPlatform_Projects', N'U')
      AND name = N'ProjectStage' AND system_type_id = TYPE_ID(N'tinyint')
      AND is_nullable = 1
)
    THROW 55320, N'Nullable ProjectStage column is missing or has drifted.', 1;

IF NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_Projects', N'U')
      AND name = N'FundingPlatform_CK_Projects_ProjectStage'
      AND is_disabled = 0 AND is_not_trusted = 0
)
    THROW 55321, N'ProjectStage check constraint is missing or untrusted.', 1;

DECLARE @ExpectedGoals TABLE
(
    Id INT NOT NULL PRIMARY KEY,
    Code NVARCHAR(20) NOT NULL,
    Name NVARCHAR(180) NOT NULL
);
INSERT INTO @ExpectedGoals (Id, Code, Name)
VALUES
    (1, N'SDG_01', N'Fin de la pobreza'),
    (2, N'SDG_02', N'Hambre cero'),
    (3, N'SDG_03', N'Salud y bienestar'),
    (4, N'SDG_04', N'Educación de calidad'),
    (5, N'SDG_05', N'Igualdad de género'),
    (6, N'SDG_06', N'Agua limpia y saneamiento'),
    (7, N'SDG_07', N'Energía asequible y no contaminante'),
    (8, N'SDG_08', N'Trabajo decente y crecimiento económico'),
    (9, N'SDG_09', N'Industria, innovación e infraestructura'),
    (10, N'SDG_10', N'Reducción de las desigualdades'),
    (11, N'SDG_11', N'Ciudades y comunidades sostenibles'),
    (12, N'SDG_12', N'Producción y consumo responsables'),
    (13, N'SDG_13', N'Acción por el clima'),
    (14, N'SDG_14', N'Vida submarina'),
    (15, N'SDG_15', N'Vida de ecosistemas terrestres'),
    (16, N'SDG_16', N'Paz, justicia e instituciones sólidas'),
    (17, N'SDG_17', N'Alianzas para lograr los objetivos');

IF (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_SustainableDevelopmentGoals) <> 17
   OR EXISTS
   (
       SELECT 1
       FROM @ExpectedGoals AS Expected
       LEFT JOIN dbo.FundingPlatform_SustainableDevelopmentGoals AS Actual
           ON Actual.Id = Expected.Id
       WHERE Actual.Id IS NULL OR Actual.Code <> Expected.Code
          OR Actual.Name <> Expected.Name OR Actual.IsActive <> 1
   )
    THROW 55322, N'Official 17-goal catalog failed.', 1;

IF OBJECT_ID(N'dbo.FundingPlatform_ProjectSustainableDevelopmentGoals', N'U') IS NULL
   OR NOT EXISTS
   (
       SELECT 1 FROM sys.foreign_keys
       WHERE parent_object_id =
             OBJECT_ID(N'dbo.FundingPlatform_ProjectSustainableDevelopmentGoals', N'U')
         AND name = N'FundingPlatform_FK_ProjectSustainableDevelopmentGoals_Projects'
         AND delete_referential_action = 1
   )
    THROW 55323, N'Project SDG association contract failed.', 1;

DECLARE @CreateDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_Project_Create', N'P'));
DECLARE @UpdateDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_Project_Update', N'P'));
DECLARE @GetDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_Project_Get', N'P'));
DECLARE @CatalogDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_Catalogs_GetForOrganizationProfile', N'P'));

IF @CreateDefinition NOT LIKE N'%@ProjectStage TINYINT = NULL%'
   OR @CreateDefinition NOT LIKE N'%@ProjectStageIsSpecified BIT = 0%'
   OR @CreateDefinition NOT LIKE N'%@SustainableDevelopmentGoalIdsJson NVARCHAR(1000) = NULL%'
   OR @UpdateDefinition NOT LIKE N'%@ProjectStage TINYINT = NULL%'
   OR @UpdateDefinition NOT LIKE N'%@ProjectStageIsSpecified BIT = 0%'
   OR @UpdateDefinition NOT LIKE N'%@SustainableDevelopmentGoalIdsJson NVARCHAR(1000) = NULL%'
   OR @UpdateDefinition NOT LIKE N'%THROW 51411%'
   OR CHARINDEX(N'CONVERT(NVARCHAR(11), TRY_CONVERT(INT, [value])) <> [value]', @CreateDefinition) = 0
   OR CHARINDEX(N'CONVERT(NVARCHAR(11), TRY_CONVERT(INT, [value])) <> [value]', @UpdateDefinition) = 0
   OR @UpdateDefinition NOT LIKE N'%ELSE ProjectStage END%'
   OR @UpdateDefinition NOT LIKE N'%IF @SustainableDevelopmentGoalIdsJson IS NOT NULL%'
    THROW 55324, N'Backward-compatible project write contract failed.', 1;

IF @GetDefinition NOT LIKE N'%SustainableDevelopmentGoalId AS Id%'
   OR @CatalogDefinition NOT LIKE N'%FundingPlatform_SustainableDevelopmentGoals%'
    THROW 55325, N'Project or catalog read contract failed.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke033;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @UserPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @Email NVARCHAR(320) = N'project-impact-' +
        REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'') + N'@example.invalid';

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, Status, PreferredLocale)
    VALUES
        (@UserPublicId, @Email, UPPER(@Email), N'Project impact smoke',
         N'not-a-credential', N'project-impact', 1, 2, N'es-CL');

    DECLARE @Organization TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProfileVersion INT, RowVersion BINARY(8));
    DECLARE @OrganizationSnapshot NVARCHAR(MAX) = N'{"name":"Project impact smoke"}';
    DECLARE @OrganizationHash BINARY(32) =
        HASHBYTES('SHA2_256', @OrganizationSnapshot);
    INSERT INTO @Organization EXEC dbo.FundingPlatform_usp_Organization_CreateForUser
        @UserPublicId = @UserPublicId,
        @Name = N'Project impact smoke',
        @HomeCountryId = 152,
        @OrganizationTypeId = 2,
        @SnapshotJson = @OrganizationSnapshot,
        @ContentHash = @OrganizationHash;
    DECLARE @OrganizationPublicId UNIQUEIDENTIFIER = (SELECT PublicId FROM @Organization);

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

    DECLARE @Snapshot1 NVARCHAR(MAX) =
        N'{"title":"Impacto ODS","status":2,"projectStage":1,"sustainableDevelopmentGoalIds":[1,13]}';
    DECLARE @Hash1 BINARY(32) = HASHBYTES('SHA2_256', @Snapshot1);
    DECLARE @Created TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProjectVersion INT, RowVersion BINARY(8));
    DECLARE @Slug NVARCHAR(180) = N'project-impact-' +
        REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'');

    INSERT INTO @Created EXEC dbo.FundingPlatform_usp_Project_Create
        @OrganizationPublicId = @OrganizationPublicId,
        @UserPublicId = @UserPublicId,
        @Slug = @Slug,
        @Title = N'Impacto ODS',
        @Summary = N'Proyecto con etapa y dos objetivos de desarrollo sostenible.',
        @Description = N'Contrato transaccional de proyecto.',
        @ProjectStatus = 2,
        @StartDate = '2027-01-01',
        @EndDate = '2027-12-31',
        @BudgetTotal = 100000,
        @ConfirmedFunding = 25000,
        @Currency = 'CLP',
        @SnapshotJson = @Snapshot1,
        @ContentHash = @Hash1,
        @CountryIds = @CountryIds,
        @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds,
        @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds,
        @ProjectStage = 1,
        @ProjectStageIsSpecified = 1,
        @SustainableDevelopmentGoalIdsJson = N'[1,13]';

    DECLARE @ProjectId BIGINT = (SELECT Id FROM @Created);
    DECLARE @ProjectPublicId UNIQUEIDENTIFIER = (SELECT PublicId FROM @Created);
    DECLARE @RowVersion1 BINARY(8) = (SELECT RowVersion FROM @Created);

    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_Projects
        WHERE Id = @ProjectId AND ProjectStatus = 2 AND ProjectStage = 1)
       OR (SELECT COUNT_BIG(1)
           FROM dbo.FundingPlatform_ProjectSustainableDevelopmentGoals
           WHERE ProjectId = @ProjectId) <> 2
       OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ProjectVersions
        WHERE ProjectId = @ProjectId AND ProjectVersion = 1
          AND SnapshotJson = @Snapshot1 AND ContentHash = @Hash1)
        THROW 55326, N'Project impact create or initial snapshot failed.', 1;

    DELETE FROM @Created;
    DECLARE @Snapshot2 NVARCHAR(MAX) =
        N'{"title":"Impacto ODS actualizado","status":3,"projectStage":4,"sustainableDevelopmentGoalIds":[4,17]}';
    DECLARE @Hash2 BINARY(32) = HASHBYTES('SHA2_256', @Snapshot2);
    INSERT INTO @Created EXEC dbo.FundingPlatform_usp_Project_Update
        @OrganizationPublicId = @OrganizationPublicId,
        @ProjectPublicId = @ProjectPublicId,
        @UserPublicId = @UserPublicId,
        @ExpectedRowVersion = @RowVersion1,
        @Title = N'Impacto ODS actualizado',
        @Summary = N'Proyecto actualizado.',
        @Description = N'Contrato transaccional actualizado.',
        @ProjectStatus = 3,
        @StartDate = '2027-01-01',
        @EndDate = '2027-12-31',
        @BudgetTotal = 100000,
        @ConfirmedFunding = 50000,
        @Currency = 'CLP',
        @SnapshotJson = @Snapshot2,
        @ContentHash = @Hash2,
        @CountryIds = @CountryIds,
        @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds,
        @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds,
        @ProjectStage = 4,
        @ProjectStageIsSpecified = 1,
        @SustainableDevelopmentGoalIdsJson = N'[4,17]';

    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_Projects
        WHERE Id = @ProjectId AND ProjectVersion = 2 AND ProjectStage = 4)
       OR (SELECT COUNT_BIG(1)
           FROM dbo.FundingPlatform_ProjectSustainableDevelopmentGoals
           WHERE ProjectId = @ProjectId AND SustainableDevelopmentGoalId IN (4, 17)) <> 2
       OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ProjectVersions
        WHERE ProjectId = @ProjectId AND ProjectVersion = 2
          AND SnapshotJson = @Snapshot2 AND ContentHash = @Hash2)
        THROW 55327, N'Project impact update or complete snapshot failed.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke033;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FP_Smoke033;
    THROW;
END CATCH;

SELECT CAST(1 AS BIT) AS Succeeded;
