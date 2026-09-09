/* 040 transactional enrichment smoke. Synthetic fixtures are rolled back.
   Execute against disposable SQL first; parsing this script is not execution. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF COL_LENGTH(N'dbo.FundingPlatform_Projects', N'EnrichmentJson') IS NULL
    THROW 55400, N'Project enrichment column is missing.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_Projects')
      AND name = N'FundingPlatform_CK_Projects_EnrichmentJson'
      AND is_disabled = 0 AND is_not_trusted = 0)
    THROW 55401, N'Project enrichment constraint is missing or untrusted.', 1;
DECLARE @UpdateDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_Project_Update'));
DECLARE @PublicDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMarketplace_GetBySlug'));
IF @UpdateDefinition IS NULL OR @UpdateDefinition NOT LIKE N'%THROW 51411%'
   OR @UpdateDefinition NOT LIKE N'%Project enrichment must match its version snapshot%'
   OR @UpdateDefinition NOT LIKE N'%AND RowVersion = @ExpectedRowVersion%'
   OR @PublicDefinition IS NULL OR @PublicDefinition NOT LIKE N'%ROUND(TRY_CONVERT%'
   OR @PublicDefinition NOT LIKE N'%FundingPlatform_ifn_ProjectMarketplaceReady()%'
    THROW 55402, N'Enrichment versioning or public projection guard is missing.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke040;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @UserPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @Email NVARCHAR(320) = N'project-enrichment-' +
        REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'') + N'@example.invalid';

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, Status, PreferredLocale)
    VALUES
        (@UserPublicId, @Email, UPPER(@Email), N'Project enrichment smoke',
         N'not-a-credential', N'project-enrichment', 1, 2, N'es-CL');

    DECLARE @Organization TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProfileVersion INT, RowVersion BINARY(8));
    DECLARE @OrganizationSnapshot NVARCHAR(MAX) = N'{"name":"Project enrichment smoke"}';
    DECLARE @OrganizationHash BINARY(32) =
        HASHBYTES('SHA2_256', @OrganizationSnapshot);
    INSERT INTO @Organization EXEC dbo.FundingPlatform_usp_Organization_CreateForUser
        @UserPublicId = @UserPublicId,
        @Name = N'Project enrichment smoke',
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
        N'{"title":"Impacto ODS","status":2,"projectStage":1,"sustainableDevelopmentGoalIds":[1,13],"enrichment":{"problem":"Problema inicial","solution":"Solución propuesta","beneficiaryCount":120,"locality":"Localidad privada","latitude":-33.456789,"longitude":-70.654321,"locationVisibility":0,"impactIndicators":[{"name":"Hogares","unit":"hogares","baseline":0,"target":120}],"soughtPartners":"Municipios","soughtProfessionals":"Ingenieros","seekingConsortium":true}}';
    DECLARE @Enrichment1 NVARCHAR(MAX) = N'{"problem":"Problema inicial","solution":"Solución propuesta","beneficiaryCount":120,"locality":"Localidad privada","latitude":-33.456789,"longitude":-70.654321,"locationVisibility":0,"impactIndicators":[{"name":"Hogares","unit":"hogares","baseline":0,"target":120}],"soughtPartners":"Municipios","soughtProfessionals":"Ingenieros","seekingConsortium":true}';
    DECLARE @Hash1 BINARY(32) = HASHBYTES('SHA2_256', @Snapshot1);
    DECLARE @Created TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProjectVersion INT, RowVersion BINARY(8));
    DECLARE @Slug NVARCHAR(180) = N'project-enrichment-' +
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
        @SustainableDevelopmentGoalIdsJson = N'[1,13]', @EnrichmentJson = @Enrichment1;

    DECLARE @ProjectId BIGINT = (SELECT Id FROM @Created);
    DECLARE @ProjectPublicId UNIQUEIDENTIFIER = (SELECT PublicId FROM @Created);
    DECLARE @RowVersion1 BINARY(8) = (SELECT RowVersion FROM @Created);

    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_Projects
        WHERE Id = @ProjectId AND ProjectStatus = 2 AND ProjectStage = 1 AND EnrichmentJson = @Enrichment1)
       OR (SELECT COUNT_BIG(1)
           FROM dbo.FundingPlatform_ProjectSustainableDevelopmentGoals
           WHERE ProjectId = @ProjectId) <> 2
       OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ProjectVersions
        WHERE ProjectId = @ProjectId AND ProjectVersion = 1
          AND SnapshotJson = @Snapshot1 AND ContentHash = @Hash1)
        THROW 55326, N'Project enrichment create or initial snapshot failed.', 1;

    DELETE FROM @Created;
    DECLARE @Snapshot2 NVARCHAR(MAX) =
        N'{"title":"Impacto ODS actualizado","status":3,"projectStage":4,"sustainableDevelopmentGoalIds":[4,17],"enrichment":{"problem":"Problema actualizado","solution":"Solución propuesta","beneficiaryCount":240,"locality":"Localidad pública","latitude":-33.456789,"longitude":-70.654321,"locationVisibility":2,"impactIndicators":[{"name":"Hogares","unit":"hogares","baseline":120,"target":240}],"soughtPartners":null,"soughtProfessionals":null,"seekingConsortium":false}}';
    DECLARE @Enrichment2 NVARCHAR(MAX) = N'{"problem":"Problema actualizado","solution":"Solución propuesta","beneficiaryCount":240,"locality":"Localidad pública","latitude":-33.456789,"longitude":-70.654321,"locationVisibility":2,"impactIndicators":[{"name":"Hogares","unit":"hogares","baseline":120,"target":240}],"soughtPartners":null,"soughtProfessionals":null,"seekingConsortium":false}';
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
        @SustainableDevelopmentGoalIdsJson = N'[4,17]', @EnrichmentJson = @Enrichment2;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_Projects
        WHERE Id = @ProjectId AND ProjectVersion = 2 AND ProjectStage = 4 AND EnrichmentJson = @Enrichment2)
       OR (SELECT COUNT_BIG(1)
           FROM dbo.FundingPlatform_ProjectSustainableDevelopmentGoals
           WHERE ProjectId = @ProjectId AND SustainableDevelopmentGoalId IN (4, 17)) <> 2
       OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ProjectVersions
        WHERE ProjectId = @ProjectId AND ProjectVersion = 2
          AND SnapshotJson = @Snapshot2 AND ContentHash = @Hash2)
        THROW 55327, N'Project enrichment update or complete snapshot failed.', 1;


    /* Synthetic readiness fixtures only: application publication still requires review. */
    DECLARE @PublicRows TABLE
    (
        ProjectPublicId UNIQUEIDENTIFIER, Slug NVARCHAR(180), Title NVARCHAR(250),
        Summary NVARCHAR(1000), Description NVARCHAR(MAX), ProjectStatus TINYINT,
        ProjectStage TINYINT, StartDate DATE, EndDate DATE, BudgetTotal DECIMAL(19,4),
        ConfirmedFunding DECIMAL(19,4), Currency CHAR(3), FundingGap DECIMAL(19,4),
        ProjectVersion INT, PublishedAtUtc DATETIME2(3), UpdatedAtUtc DATETIME2(3),
        EnrichmentJson NVARCHAR(MAX), OrganizationPublicId UNIQUEIDENTIFIER,
        OrganizationName NVARCHAR(250), OrganizationWebsiteUrl NVARCHAR(2048),
        CountriesJson NVARCHAR(MAX), RegionsJson NVARCHAR(MAX), CategoriesJson NVARCHAR(MAX),
        BeneficiaryTypesJson NVARCHAR(MAX), ProjectTypesJson NVARCHAR(MAX),
        SustainableDevelopmentGoalsJson NVARCHAR(MAX)
    );
    INSERT INTO @PublicRows EXEC dbo.FundingPlatform_usp_ProjectMarketplace_GetBySlug @Slug = @Slug;
    IF EXISTS (SELECT 1 FROM @PublicRows)
        THROW 55404, N'Draft enrichment must not be publicly readable.', 1;
    UPDATE dbo.FundingPlatform_Organizations SET ProfileStatus = 2, ProfileCompleteness = 100
    WHERE PublicId = @OrganizationPublicId;
    UPDATE dbo.FundingPlatform_Projects SET PublicationStatus = 2,
        PublishedAtUtc = SYSUTCDATETIME(), ReviewedAtUtc = SYSUTCDATETIME(),
        ReviewedByUserId = (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @UserPublicId),
        EnrichmentJson = @Enrichment1
    WHERE Id = @ProjectId;
    INSERT INTO @PublicRows EXEC dbo.FundingPlatform_usp_Project_Public_GetBySlug @Slug = @Slug;
    IF (SELECT COUNT_BIG(1) FROM @PublicRows) <> 1 OR EXISTS
        (SELECT 1 FROM @PublicRows WHERE JSON_VALUE(EnrichmentJson, '$.latitude') IS NOT NULL
            OR JSON_VALUE(EnrichmentJson, '$.longitude') IS NOT NULL
            OR JSON_VALUE(EnrichmentJson, '$.locality') IS NOT NULL
            OR JSON_VALUE(EnrichmentJson, '$.problem') <> N'Problema inicial')
        THROW 55405, N'Public default visibility exposed private location or lost content.', 1;
    DELETE FROM @PublicRows;
    UPDATE dbo.FundingPlatform_Projects
        SET EnrichmentJson = JSON_MODIFY(@Enrichment1, '$.locationVisibility', 1) WHERE Id = @ProjectId;
    INSERT INTO @PublicRows EXEC dbo.FundingPlatform_usp_ProjectMarketplace_GetBySlug @Slug = @Slug;
    IF (SELECT COUNT_BIG(1) FROM @PublicRows) <> 1 OR EXISTS
        (SELECT 1 FROM @PublicRows WHERE JSON_VALUE(EnrichmentJson, '$.latitude') IS NOT NULL
            OR JSON_VALUE(EnrichmentJson, '$.longitude') IS NOT NULL
            OR COALESCE(JSON_VALUE(EnrichmentJson, '$.locality'), N'') <> N'Localidad privada')
        THROW 55406, N'Locality-only projection must exclude coordinates.', 1;
    DELETE FROM @PublicRows;
    UPDATE dbo.FundingPlatform_Projects SET EnrichmentJson = @Enrichment2 WHERE Id = @ProjectId;
    INSERT INTO @PublicRows EXEC dbo.FundingPlatform_usp_ProjectMarketplace_GetBySlug @Slug = @Slug;
    IF (SELECT COUNT_BIG(1) FROM @PublicRows) <> 1 OR EXISTS
        (SELECT 1 FROM @PublicRows
         WHERE COALESCE(TRY_CONVERT(DECIMAL(10,2), JSON_VALUE(EnrichmentJson, '$.latitude')), 999) <> -33.46
            OR COALESCE(TRY_CONVERT(DECIMAL(10,2), JSON_VALUE(EnrichmentJson, '$.longitude')), 999) <> -70.65
            OR CHARINDEX(N'33.456789', EnrichmentJson) > 0
            OR CHARINDEX(N'70.654321', EnrichmentJson) > 0
            OR JSON_VALUE(EnrichmentJson, '$.seekingConsortium') <> N'false')
        THROW 55407, N'Public point must be rounded and preserve explicit false.', 1;
    DELETE FROM @PublicRows;
    UPDATE dbo.FundingPlatform_Organizations SET IsActive = 0 WHERE PublicId = @OrganizationPublicId;
    INSERT INTO @PublicRows EXEC dbo.FundingPlatform_usp_Project_Public_GetBySlug @Slug = @Slug;
    IF EXISTS (SELECT 1 FROM @PublicRows)
        THROW 55408, N'Inactive organization enrichment became publicly readable.', 1;
    UPDATE dbo.FundingPlatform_Organizations SET IsActive = 1 WHERE PublicId = @OrganizationPublicId;
    UPDATE dbo.FundingPlatform_Projects SET PublicationStatus = 4 WHERE Id = @ProjectId;
    INSERT INTO @PublicRows EXEC dbo.FundingPlatform_usp_ProjectMarketplace_GetBySlug @Slug = @Slug;
    IF EXISTS (SELECT 1 FROM @PublicRows)
        THROW 55409, N'Archived enrichment became publicly readable.', 1;
    UPDATE dbo.FundingPlatform_Projects SET PublicationStatus = 0, PublishedAtUtc = NULL,
        ReviewedAtUtc = NULL, ReviewedByUserId = NULL WHERE Id = @ProjectId;

    /* {} is an explicit clear, not an omitted legacy aggregate. */
    DECLARE @RowVersion2 BINARY(8) = (SELECT RowVersion FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId);
    DECLARE @ClearSnapshot NVARCHAR(MAX) = N'{"title":"Enrichment cleared","projectStage":null,"sustainableDevelopmentGoalIds":[],"enrichment":{}}';
    DECLARE @ClearHash BINARY(32) = HASHBYTES('SHA2_256', @ClearSnapshot);
    DELETE FROM @Created;
    INSERT INTO @Created EXEC dbo.FundingPlatform_usp_Project_Update
        @OrganizationPublicId = @OrganizationPublicId, @ProjectPublicId = @ProjectPublicId,
        @UserPublicId = @UserPublicId, @ExpectedRowVersion = @RowVersion2,
        @Title = N'Enrichment cleared', @ProjectStatus = 2,
        @SnapshotJson = @ClearSnapshot, @ContentHash = @ClearHash,
        @CountryIds = @CountryIds, @RegionIds = @RegionIds, @CategoryIds = @CategoryIds,
        @BeneficiaryTypeIds = @BeneficiaryTypeIds, @ProjectTypeIds = @ProjectTypeIds,
        @ProjectStageIsSpecified = 1, @ProjectStage = NULL,
        @SustainableDevelopmentGoalIdsJson = N'[]', @EnrichmentJson = N'{}';
    IF NOT EXISTS
        (SELECT 1 FROM dbo.FundingPlatform_Projects
         WHERE Id = @ProjectId AND ProjectVersion = 3 AND EnrichmentJson = N'{}')
       OR NOT EXISTS
        (SELECT 1 FROM dbo.FundingPlatform_ProjectVersions
         WHERE ProjectId = @ProjectId AND ProjectVersion = 3
           AND SnapshotJson = @ClearSnapshot AND ContentHash = @ClearHash)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_ProjectVersions WHERE ProjectId = @ProjectId) <> 3
        THROW 55403, N'Explicit enrichment clearing must create a complete new version.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke040;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FP_Smoke040;
    THROW;
END CATCH;

SELECT CAST(1 AS BIT) AS Succeeded;
