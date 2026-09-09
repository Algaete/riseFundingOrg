/* 040: Optional, atomic project enrichment. Requires 001-039.
   Deploy DB -> all API revisions -> frontend. No backfill or publication-policy changes.
   Public reads retain the current marketplace/media readiness gate from 036/038.
   Older API writers fail closed (51411) once enrichment exists. */
SET XACT_ABORT ON;
GO

IF COL_LENGTH(N'dbo.FundingPlatform_Projects', N'EnrichmentJson') IS NULL
    ALTER TABLE dbo.FundingPlatform_Projects ADD EnrichmentJson NVARCHAR(MAX) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_Projects')
                 AND name = N'FundingPlatform_CK_Projects_EnrichmentJson')
    ALTER TABLE dbo.FundingPlatform_Projects WITH CHECK ADD
        CONSTRAINT FundingPlatform_CK_Projects_EnrichmentJson CHECK
        (EnrichmentJson IS NULL OR (ISJSON(EnrichmentJson, OBJECT) = 1 AND DATALENGTH(EnrichmentJson) <= 240000));
GO

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
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectStage TINYINT = NULL,
    @ProjectStageIsSpecified BIT = 0,
    @SustainableDevelopmentGoalIdsJson NVARCHAR(1000) = NULL,
    @EnrichmentJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @ProjectId BIGINT;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @SelectedGoals TABLE (Id INT NOT NULL PRIMARY KEY);

    IF @ProjectStageIsSpecified NOT IN (0, 1)
       OR (@ProjectStageIsSpecified = 1 AND @ProjectStage IS NOT NULL
           AND @ProjectStage NOT BETWEEN 0 AND 5)
        THROW 51410, N'Project stage is invalid.', 1;
    IF @SustainableDevelopmentGoalIdsJson IS NOT NULL
       AND ISJSON(@SustainableDevelopmentGoalIdsJson) <> 1
        THROW 51410, N'Project SDG selection must be a JSON array.', 1;
    IF @SustainableDevelopmentGoalIdsJson IS NOT NULL
       AND LEFT(LTRIM(@SustainableDevelopmentGoalIdsJson), 1) <> N'['
        THROW 51410, N'Project SDG selection must be a JSON array.', 1;
    IF EXISTS
    (
        SELECT 1 FROM OPENJSON(COALESCE(@SustainableDevelopmentGoalIdsJson, N'[]'))
        WHERE [type] <> 2 OR TRY_CONVERT(INT, [value]) IS NULL
           OR CONVERT(NVARCHAR(11), TRY_CONVERT(INT, [value])) <> [value]
           OR TRY_CONVERT(INT, [value]) NOT BETWEEN 1 AND 17
    ) OR EXISTS
    (
        SELECT 1 FROM OPENJSON(COALESCE(@SustainableDevelopmentGoalIdsJson, N'[]'))
        GROUP BY TRY_CONVERT(INT, [value]) HAVING COUNT_BIG(1) > 1
    )
        THROW 51410, N'Project SDG selection contains invalid or duplicate identifiers.', 1;

    INSERT INTO @SelectedGoals (Id)
    SELECT TRY_CONVERT(INT, [value])
    FROM OPENJSON(COALESCE(@SustainableDevelopmentGoalIdsJson, N'[]'));

    IF EXISTS
    (
        SELECT 1 FROM @SelectedGoals AS selected
        LEFT JOIN dbo.FundingPlatform_SustainableDevelopmentGoals AS goals
            ON goals.Id = selected.Id AND goals.IsActive = 1
        WHERE goals.Id IS NULL
    )
        THROW 51410, N'One or more project SDGs do not exist or are inactive.', 1;

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
        IF @OrganizationId IS NULL THROW 51402, N'Active organization administrator membership is required.', 1;
        IF ISJSON(@SnapshotJson) <> 1 THROW 51403, N'Project snapshot must be JSON.', 1;

        /* The extension is part of this exact content version, never an independent write. */
        IF @EnrichmentJson IS NOT NULL AND
           (ISJSON(@EnrichmentJson, OBJECT) <> 1 OR DATALENGTH(@EnrichmentJson) > 240000)
            THROW 51410, N'Project enrichment must be a bounded JSON object.', 1;
        IF COALESCE(JSON_QUERY(@SnapshotJson, '$.enrichment'), N'null') COLLATE Latin1_General_100_BIN2
             <> COALESCE(@EnrichmentJson, N'null') COLLATE Latin1_General_100_BIN2
           OR DATALENGTH(COALESCE(JSON_QUERY(@SnapshotJson, '$.enrichment'), N'null'))
             <> DATALENGTH(COALESCE(@EnrichmentJson, N'null'))
            THROW 51410, N'Project enrichment must match its version snapshot.', 1;
        IF @EnrichmentJson IS NOT NULL
        BEGIN
            IF EXISTS (SELECT 1 FROM OPENJSON(@EnrichmentJson)
                       GROUP BY [key] COLLATE Latin1_General_100_BIN2 HAVING COUNT_BIG(1) > 1)
               OR EXISTS
               (
                   SELECT 1 FROM OPENJSON(@EnrichmentJson)
                   WHERE [key] COLLATE Latin1_General_100_BIN2 NOT IN
                     (N'problem', N'solution', N'beneficiaryCount', N'locality', N'latitude',
                      N'longitude', N'locationVisibility', N'impactIndicators', N'soughtPartners',
                      N'soughtProfessionals', N'seekingConsortium')
                      OR ([key] IN (N'problem', N'solution', N'locality', N'soughtPartners', N'soughtProfessionals')
                          AND [type] NOT IN (0, 1))
                      OR ([key] IN (N'beneficiaryCount', N'latitude', N'longitude', N'locationVisibility')
                          AND [type] NOT IN (0, 2))
                      OR ([key] = N'impactIndicators' AND [type] NOT IN (0, 4))
                      OR ([key] = N'seekingConsortium' AND [type] NOT IN (0, 3))
               )
                THROW 51410, N'Project enrichment contains invalid properties.', 1;
            DECLARE @Visibility INT = COALESCE(TRY_CONVERT(INT, JSON_VALUE(@EnrichmentJson, '$.locationVisibility')), 0);
            DECLARE @Latitude DECIMAL(38,18) = TRY_CONVERT(DECIMAL(38,18), JSON_VALUE(@EnrichmentJson, '$.latitude'));
            DECLARE @Longitude DECIMAL(38,18) = TRY_CONVERT(DECIMAL(38,18), JSON_VALUE(@EnrichmentJson, '$.longitude'));
            IF @Visibility NOT BETWEEN 0 AND 2
               OR (JSON_VALUE(@EnrichmentJson, '$.locationVisibility') IS NOT NULL AND
                   JSON_VALUE(@EnrichmentJson, '$.locationVisibility') <> CONVERT(NVARCHAR(10), @Visibility))
               OR (@Latitude IS NULL AND @Longitude IS NOT NULL)
               OR (@Latitude IS NOT NULL AND @Longitude IS NULL)
               OR (@Latitude NOT BETWEEN -90 AND 90 OR @Longitude NOT BETWEEN -180 AND 180)
               OR (JSON_VALUE(@EnrichmentJson, '$.latitude') IS NOT NULL AND @Latitude IS NULL)
               OR (JSON_VALUE(@EnrichmentJson, '$.longitude') IS NOT NULL AND @Longitude IS NULL)
               OR (@Visibility = 1 AND NULLIF(LTRIM(RTRIM(JSON_VALUE(@EnrichmentJson, '$.locality'))), N'') IS NULL)
               OR (@Visibility = 2 AND (@Latitude IS NULL OR @Longitude IS NULL))
                THROW 51410, N'Project location or public visibility is invalid.', 1;
            IF EXISTS
            (
                SELECT 1 FROM OPENJSON(@EnrichmentJson)
                WHERE ([key] IN (N'problem', N'solution') AND DATALENGTH([value]) > 6000)
                   OR ([key] = N'locality' AND DATALENGTH([value]) > 400)
                   OR ([key] IN (N'soughtPartners', N'soughtProfessionals') AND DATALENGTH([value]) > 4000)
                   OR ([key] = N'beneficiaryCount' AND [type] <> 0 AND
                       (TRY_CONVERT(INT, [value]) IS NULL OR TRY_CONVERT(INT, [value]) < 0
                        OR CONVERT(NVARCHAR(11), TRY_CONVERT(INT, [value])) <> [value]))
            )
                THROW 51410, N'Project enrichment values exceed their bounds.', 1;
            IF (SELECT COUNT_BIG(1) FROM OPENJSON(@EnrichmentJson, '$.impactIndicators')) > 20
               OR EXISTS
               (
                   SELECT 1 FROM OPENJSON(@EnrichmentJson, '$.impactIndicators')
                   WHERE [type] <> 5
               )
                THROW 51410, N'Project impact indicators must contain up to 20 objects.', 1;
            IF EXISTS
            (
                SELECT 1 FROM OPENJSON(@EnrichmentJson, '$.impactIndicators') AS indicator
                CROSS APPLY OPENJSON(indicator.[value]) AS field
                WHERE field.[key] COLLATE Latin1_General_100_BIN2 NOT IN (N'name', N'unit', N'baseline', N'target')
                   OR (field.[key] IN (N'name', N'unit') AND field.[type] <> 1)
                   OR (field.[key] = N'name' AND DATALENGTH(field.[value]) > 400)
                   OR (field.[key] = N'unit' AND DATALENGTH(field.[value]) > 160)
                   OR (field.[key] IN (N'baseline', N'target') AND field.[type] <> 0 AND
                       (field.[type] <> 2 OR TRY_CONVERT(DECIMAL(38,18), field.[value]) IS NULL
                        OR TRY_CONVERT(DECIMAL(38,18), field.[value]) NOT BETWEEN -1000000000000 AND 1000000000000))
            ) OR EXISTS
            (
                SELECT 1 FROM OPENJSON(@EnrichmentJson, '$.impactIndicators') AS indicator
                WHERE NULLIF(LTRIM(RTRIM(JSON_VALUE(indicator.[value], '$.name'))), N'') IS NULL
                   OR NULLIF(LTRIM(RTRIM(JSON_VALUE(indicator.[value], '$.unit'))), N'') IS NULL
            ) OR EXISTS
            (
                SELECT 1 FROM OPENJSON(@EnrichmentJson, '$.impactIndicators') AS indicator
                CROSS APPLY OPENJSON(indicator.[value]) AS field
                GROUP BY indicator.[key], field.[key] COLLATE Latin1_General_100_BIN2
                HAVING COUNT_BIG(1) > 1
            )
                THROW 51410, N'Project impact indicator fields are invalid.', 1;
        END;

        IF EXISTS
        (
            SELECT 1 FROM @RegionIds selected
            LEFT JOIN dbo.FundingPlatform_Regions region ON region.Id = selected.Id
            WHERE region.Id IS NULL
        ) THROW 51409, N'One or more project regions do not exist.', 1;
        IF EXISTS
        (
            SELECT 1 FROM @RegionIds selected
            INNER JOIN dbo.FundingPlatform_Regions region ON region.Id = selected.Id
            WHERE NOT EXISTS (SELECT 1 FROM @CountryIds country WHERE country.Id = region.CountryId)
        ) THROW 51404, N'Every project region requires its country.', 1;

        INSERT INTO dbo.FundingPlatform_Projects
            (OrganizationId, CreatedByUserId, Slug, Title, Summary, Description,
             ProjectStatus, ProjectStage, PublicationStatus, StartDate, EndDate, BudgetTotal,
             ConfirmedFunding, Currency, ProjectVersion, CreatedAtUtc, UpdatedAtUtc, EnrichmentJson)
        VALUES
            (@OrganizationId, @UserId, @Slug, @Title, @Summary, @Description,
             @ProjectStatus,
             CASE WHEN @ProjectStageIsSpecified = 1 THEN @ProjectStage ELSE NULL END,
             0, @StartDate, @EndDate, @BudgetTotal,
             @ConfirmedFunding, @Currency, 1, @NowUtc, @NowUtc, @EnrichmentJson);
        SET @ProjectId = CONVERT(BIGINT, SCOPE_IDENTITY());
        INSERT INTO dbo.FundingPlatform_ProjectCountries SELECT @ProjectId, Id FROM @CountryIds;
        INSERT INTO dbo.FundingPlatform_ProjectRegions SELECT @ProjectId, Id FROM @RegionIds;
        INSERT INTO dbo.FundingPlatform_ProjectCategories SELECT @ProjectId, Id FROM @CategoryIds;
        INSERT INTO dbo.FundingPlatform_ProjectBeneficiaryTypes SELECT @ProjectId, Id FROM @BeneficiaryTypeIds;
        INSERT INTO dbo.FundingPlatform_ProjectProjectTypes SELECT @ProjectId, Id FROM @ProjectTypeIds;
        INSERT INTO dbo.FundingPlatform_ProjectSustainableDevelopmentGoals
            SELECT @ProjectId, Id FROM @SelectedGoals;
        INSERT INTO dbo.FundingPlatform_ProjectVersions
            (ProjectId, ProjectVersion, SnapshotJson, ContentHash, CreatedByUserId, CreatedAtUtc)
        VALUES (@ProjectId, 1, @SnapshotJson, @ContentHash, @UserId, @NowUtc);
        INSERT INTO dbo.FundingPlatform_OutboxMessages
            (MessageType, AggregateType, AggregateId, PayloadJson, OccurredAtUtc, AvailableAtUtc)
        SELECT N'ProjectCreated', N'Project', CONVERT(NVARCHAR(100), @ProjectId),
               (SELECT @ProjectId AS projectId, 1 AS projectVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
               @NowUtc, @NowUtc;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
        SELECT Id, PublicId, ProjectVersion, RowVersion
        FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FundingPlatform_CreateProject;
        THROW;
    END CATCH;
END;
GO

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
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectStage TINYINT = NULL,
    @ProjectStageIsSpecified BIT = 0,
    @SustainableDevelopmentGoalIdsJson NVARCHAR(1000) = NULL,
    @EnrichmentJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @ProjectId BIGINT, @NextVersion INT;
    DECLARE @PublicationStatus TINYINT, @ExistingProjectStage TINYINT;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @SelectedGoals TABLE (Id INT NOT NULL PRIMARY KEY);

    IF @ProjectStageIsSpecified NOT IN (0, 1)
       OR (@ProjectStageIsSpecified = 1 AND @ProjectStage IS NOT NULL
           AND @ProjectStage NOT BETWEEN 0 AND 5)
        THROW 51410, N'Project stage is invalid.', 1;
    IF @SustainableDevelopmentGoalIdsJson IS NOT NULL
       AND (ISJSON(@SustainableDevelopmentGoalIdsJson) <> 1
            OR LEFT(LTRIM(@SustainableDevelopmentGoalIdsJson), 1) <> N'[')
        THROW 51410, N'Project SDG selection must be a JSON array.', 1;
    IF EXISTS
    (
        SELECT 1 FROM OPENJSON(COALESCE(@SustainableDevelopmentGoalIdsJson, N'[]'))
        WHERE [type] <> 2 OR TRY_CONVERT(INT, [value]) IS NULL
           OR CONVERT(NVARCHAR(11), TRY_CONVERT(INT, [value])) <> [value]
           OR TRY_CONVERT(INT, [value]) NOT BETWEEN 1 AND 17
    ) OR EXISTS
    (
        SELECT 1 FROM OPENJSON(COALESCE(@SustainableDevelopmentGoalIdsJson, N'[]'))
        GROUP BY TRY_CONVERT(INT, [value]) HAVING COUNT_BIG(1) > 1
    )
        THROW 51410, N'Project SDG selection contains invalid or duplicate identifiers.', 1;

    INSERT INTO @SelectedGoals (Id)
    SELECT TRY_CONVERT(INT, [value])
    FROM OPENJSON(COALESCE(@SustainableDevelopmentGoalIdsJson, N'[]'));

    IF EXISTS
    (
        SELECT 1 FROM @SelectedGoals AS selected
        LEFT JOIN dbo.FundingPlatform_SustainableDevelopmentGoals AS goals
            ON goals.Id = selected.Id AND goals.IsActive = 1
        WHERE goals.Id IS NULL
    )
        THROW 51410, N'One or more project SDGs do not exist or are inactive.', 1;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_UpdateProject;
    BEGIN TRY
        SELECT @OrganizationId = organizations.Id, @UserId = users.Id
        FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id AND memberships.Role = 1 AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Users AS users WITH (UPDLOCK, HOLDLOCK)
            ON users.Id = memberships.UserId AND users.Status = 2
        WHERE organizations.PublicId = @OrganizationPublicId AND users.PublicId = @UserPublicId
          AND organizations.IsActive = 1;
        IF @OrganizationId IS NULL THROW 51406, N'Active organization administrator membership is required.', 1;
        SELECT @ProjectId = Id, @NextVersion = ProjectVersion + 1,
               @PublicationStatus = PublicationStatus,
               @ExistingProjectStage = ProjectStage
        FROM dbo.FundingPlatform_Projects WITH (UPDLOCK, HOLDLOCK)
        WHERE OrganizationId = @OrganizationId AND PublicId = @ProjectPublicId AND IsActive = 1;
        IF @ProjectId IS NULL THROW 51405, N'Project was not found.', 1;
        IF @PublicationStatus NOT IN (0, 3)
            THROW 51408, N'Only draft or rejected project content can be edited.', 1;
        /* Never write an incomplete historical snapshot for a legacy caller.
           Legacy updates remain accepted while the aggregate has no new impact
           data. Once impact data exists they fail closed, preserving row, links
           and the last complete project version. */
        IF (@ProjectStageIsSpecified = 0 AND @ExistingProjectStage IS NOT NULL)
           OR (@SustainableDevelopmentGoalIdsJson IS NULL AND EXISTS
               (SELECT 1
                FROM dbo.FundingPlatform_ProjectSustainableDevelopmentGoals
                WHERE ProjectId = @ProjectId))
            THROW 51411, N'Legacy update cannot replace a project with impact data.', 1;
        IF @EnrichmentJson IS NULL AND EXISTS
            (SELECT 1 FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId AND EnrichmentJson IS NOT NULL)
            THROW 51411, N'Legacy update cannot replace a project with enrichment data.', 1;
        IF ISJSON(@SnapshotJson) <> 1 THROW 51403, N'Project snapshot must be JSON.', 1;

        /* The extension is part of this exact content version, never an independent write. */
        IF @EnrichmentJson IS NOT NULL AND
           (ISJSON(@EnrichmentJson, OBJECT) <> 1 OR DATALENGTH(@EnrichmentJson) > 240000)
            THROW 51410, N'Project enrichment must be a bounded JSON object.', 1;
        IF COALESCE(JSON_QUERY(@SnapshotJson, '$.enrichment'), N'null') COLLATE Latin1_General_100_BIN2
             <> COALESCE(@EnrichmentJson, N'null') COLLATE Latin1_General_100_BIN2
           OR DATALENGTH(COALESCE(JSON_QUERY(@SnapshotJson, '$.enrichment'), N'null'))
             <> DATALENGTH(COALESCE(@EnrichmentJson, N'null'))
            THROW 51410, N'Project enrichment must match its version snapshot.', 1;
        IF @EnrichmentJson IS NOT NULL
        BEGIN
            IF EXISTS (SELECT 1 FROM OPENJSON(@EnrichmentJson)
                       GROUP BY [key] COLLATE Latin1_General_100_BIN2 HAVING COUNT_BIG(1) > 1)
               OR EXISTS
               (
                   SELECT 1 FROM OPENJSON(@EnrichmentJson)
                   WHERE [key] COLLATE Latin1_General_100_BIN2 NOT IN
                     (N'problem', N'solution', N'beneficiaryCount', N'locality', N'latitude',
                      N'longitude', N'locationVisibility', N'impactIndicators', N'soughtPartners',
                      N'soughtProfessionals', N'seekingConsortium')
                      OR ([key] IN (N'problem', N'solution', N'locality', N'soughtPartners', N'soughtProfessionals')
                          AND [type] NOT IN (0, 1))
                      OR ([key] IN (N'beneficiaryCount', N'latitude', N'longitude', N'locationVisibility')
                          AND [type] NOT IN (0, 2))
                      OR ([key] = N'impactIndicators' AND [type] NOT IN (0, 4))
                      OR ([key] = N'seekingConsortium' AND [type] NOT IN (0, 3))
               )
                THROW 51410, N'Project enrichment contains invalid properties.', 1;
            DECLARE @Visibility INT = COALESCE(TRY_CONVERT(INT, JSON_VALUE(@EnrichmentJson, '$.locationVisibility')), 0);
            DECLARE @Latitude DECIMAL(38,18) = TRY_CONVERT(DECIMAL(38,18), JSON_VALUE(@EnrichmentJson, '$.latitude'));
            DECLARE @Longitude DECIMAL(38,18) = TRY_CONVERT(DECIMAL(38,18), JSON_VALUE(@EnrichmentJson, '$.longitude'));
            IF @Visibility NOT BETWEEN 0 AND 2
               OR (JSON_VALUE(@EnrichmentJson, '$.locationVisibility') IS NOT NULL AND
                   JSON_VALUE(@EnrichmentJson, '$.locationVisibility') <> CONVERT(NVARCHAR(10), @Visibility))
               OR (@Latitude IS NULL AND @Longitude IS NOT NULL)
               OR (@Latitude IS NOT NULL AND @Longitude IS NULL)
               OR (@Latitude NOT BETWEEN -90 AND 90 OR @Longitude NOT BETWEEN -180 AND 180)
               OR (JSON_VALUE(@EnrichmentJson, '$.latitude') IS NOT NULL AND @Latitude IS NULL)
               OR (JSON_VALUE(@EnrichmentJson, '$.longitude') IS NOT NULL AND @Longitude IS NULL)
               OR (@Visibility = 1 AND NULLIF(LTRIM(RTRIM(JSON_VALUE(@EnrichmentJson, '$.locality'))), N'') IS NULL)
               OR (@Visibility = 2 AND (@Latitude IS NULL OR @Longitude IS NULL))
                THROW 51410, N'Project location or public visibility is invalid.', 1;
            IF EXISTS
            (
                SELECT 1 FROM OPENJSON(@EnrichmentJson)
                WHERE ([key] IN (N'problem', N'solution') AND DATALENGTH([value]) > 6000)
                   OR ([key] = N'locality' AND DATALENGTH([value]) > 400)
                   OR ([key] IN (N'soughtPartners', N'soughtProfessionals') AND DATALENGTH([value]) > 4000)
                   OR ([key] = N'beneficiaryCount' AND [type] <> 0 AND
                       (TRY_CONVERT(INT, [value]) IS NULL OR TRY_CONVERT(INT, [value]) < 0
                        OR CONVERT(NVARCHAR(11), TRY_CONVERT(INT, [value])) <> [value]))
            )
                THROW 51410, N'Project enrichment values exceed their bounds.', 1;
            IF (SELECT COUNT_BIG(1) FROM OPENJSON(@EnrichmentJson, '$.impactIndicators')) > 20
               OR EXISTS
               (
                   SELECT 1 FROM OPENJSON(@EnrichmentJson, '$.impactIndicators')
                   WHERE [type] <> 5
               )
                THROW 51410, N'Project impact indicators must contain up to 20 objects.', 1;
            IF EXISTS
            (
                SELECT 1 FROM OPENJSON(@EnrichmentJson, '$.impactIndicators') AS indicator
                CROSS APPLY OPENJSON(indicator.[value]) AS field
                WHERE field.[key] COLLATE Latin1_General_100_BIN2 NOT IN (N'name', N'unit', N'baseline', N'target')
                   OR (field.[key] IN (N'name', N'unit') AND field.[type] <> 1)
                   OR (field.[key] = N'name' AND DATALENGTH(field.[value]) > 400)
                   OR (field.[key] = N'unit' AND DATALENGTH(field.[value]) > 160)
                   OR (field.[key] IN (N'baseline', N'target') AND field.[type] <> 0 AND
                       (field.[type] <> 2 OR TRY_CONVERT(DECIMAL(38,18), field.[value]) IS NULL
                        OR TRY_CONVERT(DECIMAL(38,18), field.[value]) NOT BETWEEN -1000000000000 AND 1000000000000))
            ) OR EXISTS
            (
                SELECT 1 FROM OPENJSON(@EnrichmentJson, '$.impactIndicators') AS indicator
                WHERE NULLIF(LTRIM(RTRIM(JSON_VALUE(indicator.[value], '$.name'))), N'') IS NULL
                   OR NULLIF(LTRIM(RTRIM(JSON_VALUE(indicator.[value], '$.unit'))), N'') IS NULL
            ) OR EXISTS
            (
                SELECT 1 FROM OPENJSON(@EnrichmentJson, '$.impactIndicators') AS indicator
                CROSS APPLY OPENJSON(indicator.[value]) AS field
                GROUP BY indicator.[key], field.[key] COLLATE Latin1_General_100_BIN2
                HAVING COUNT_BIG(1) > 1
            )
                THROW 51410, N'Project impact indicator fields are invalid.', 1;
        END;

        IF EXISTS
        (
            SELECT 1 FROM @RegionIds selected
            LEFT JOIN dbo.FundingPlatform_Regions region ON region.Id = selected.Id
            WHERE region.Id IS NULL
        ) THROW 51409, N'One or more project regions do not exist.', 1;
        IF EXISTS
        (
            SELECT 1 FROM @RegionIds selected
            INNER JOIN dbo.FundingPlatform_Regions region ON region.Id = selected.Id
            WHERE NOT EXISTS (SELECT 1 FROM @CountryIds country WHERE country.Id = region.CountryId)
        ) THROW 51404, N'Every project region requires its country.', 1;

        UPDATE dbo.FundingPlatform_Projects
        SET Title = @Title, Summary = @Summary, Description = @Description,
            EnrichmentJson = @EnrichmentJson,
            ProjectStatus = @ProjectStatus,
            ProjectStage = CASE WHEN @ProjectStageIsSpecified = 1
                                THEN @ProjectStage ELSE ProjectStage END,
            StartDate = @StartDate, EndDate = @EndDate,
            BudgetTotal = @BudgetTotal, ConfirmedFunding = @ConfirmedFunding,
            Currency = @Currency, ProjectVersion = @NextVersion, UpdatedAtUtc = @NowUtc
        WHERE Id = @ProjectId AND RowVersion = @ExpectedRowVersion;
        IF @@ROWCOUNT = 0 THROW 51407, N'Project has a concurrency conflict.', 1;

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

        /* NULL means an older caller omitted the new optional parameter. */
        IF @SustainableDevelopmentGoalIdsJson IS NOT NULL
        BEGIN
            DELETE FROM dbo.FundingPlatform_ProjectSustainableDevelopmentGoals
            WHERE ProjectId = @ProjectId;
            INSERT INTO dbo.FundingPlatform_ProjectSustainableDevelopmentGoals
                SELECT @ProjectId, Id FROM @SelectedGoals;
        END;

        INSERT INTO dbo.FundingPlatform_ProjectVersions
            (ProjectId, ProjectVersion, SnapshotJson, ContentHash, CreatedByUserId, CreatedAtUtc)
        VALUES (@ProjectId, @NextVersion, @SnapshotJson, @ContentHash, @UserId, @NowUtc);
        INSERT INTO dbo.FundingPlatform_OutboxMessages
            (MessageType, AggregateType, AggregateId, PayloadJson, OccurredAtUtc, AvailableAtUtc)
        SELECT N'ProjectChanged', N'Project', CONVERT(NVARCHAR(100), @ProjectId),
               (SELECT @ProjectId AS projectId, @NextVersion AS projectVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
               @NowUtc, @NowUtc;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
        SELECT Id, PublicId, ProjectVersion, RowVersion
        FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_UpdateProject;
        THROW;
    END CATCH;
END;
GO

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
    IF @ProjectId IS NULL THROW 51405, N'Project was not found.', 1;

    SELECT PublicId, Slug, Title, Summary, Description, ProjectStatus, ProjectStage,
           PublicationStatus, StartDate, EndDate, BudgetTotal, ConfirmedFunding,
           Currency, FundingGap, ProjectVersion, UpdatedAtUtc, RowVersion,
           SubmittedAtUtc, ReviewedAtUtc, RejectionReason, PublishedAtUtc, EnrichmentJson
    FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId;
    SELECT CountryId AS Id FROM dbo.FundingPlatform_ProjectCountries
        WHERE ProjectId = @ProjectId ORDER BY CountryId;
    SELECT RegionId AS Id FROM dbo.FundingPlatform_ProjectRegions
        WHERE ProjectId = @ProjectId ORDER BY RegionId;
    SELECT FundingCategoryId AS Id FROM dbo.FundingPlatform_ProjectCategories
        WHERE ProjectId = @ProjectId ORDER BY FundingCategoryId;
    SELECT BeneficiaryTypeId AS Id FROM dbo.FundingPlatform_ProjectBeneficiaryTypes
        WHERE ProjectId = @ProjectId ORDER BY BeneficiaryTypeId;
    SELECT ProjectTypeId AS Id FROM dbo.FundingPlatform_ProjectProjectTypes
        WHERE ProjectId = @ProjectId ORDER BY ProjectTypeId;
    /* Result set 6 after the aggregate row: selected ODS identifiers. */
    SELECT SustainableDevelopmentGoalId AS Id
    FROM dbo.FundingPlatform_ProjectSustainableDevelopmentGoals
    WHERE ProjectId = @ProjectId ORDER BY SustainableDevelopmentGoalId;
END;
GO

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
          AND roles.NormalizedName IN (N'ADMIN', N'SUPERADMIN')
    ) THROW 51503, N'Active Admin or SuperAdmin role is required.', 1;

    SELECT projects.PublicId AS ProjectPublicId,
           projects.Slug, projects.Title, projects.Summary, projects.Description,
           projects.EnrichmentJson,
           projects.ProjectStatus, projects.ProjectStage, projects.PublicationStatus,
           projects.StartDate, projects.EndDate, projects.BudgetTotal,
           projects.ConfirmedFunding, projects.Currency, projects.FundingGap,
           projects.ProjectVersion, projects.PublishedAtUtc, projects.UpdatedAtUtc,
           organizations.PublicId AS OrganizationPublicId,
           organizations.Name AS OrganizationName,
           organizations.WebsiteUrl AS OrganizationWebsiteUrl,
           projects.SubmittedAtUtc, projects.RejectionReason,
           CONVERT(DECIMAL(5,2), 100
               - CASE WHEN organizations.ProfileStatus = 2
                            AND organizations.ProfileCompleteness >= 80 THEN 0 ELSE 10 END
               - CASE WHEN NULLIF(LTRIM(RTRIM(projects.Title)), N'') IS NOT NULL THEN 0 ELSE 10 END
               - CASE WHEN NULLIF(LTRIM(RTRIM(projects.Summary)), N'') IS NOT NULL THEN 0 ELSE 10 END
               - CASE WHEN NULLIF(LTRIM(RTRIM(projects.Description)), N'') IS NOT NULL THEN 0 ELSE 10 END
               - CASE WHEN NULLIF(LTRIM(RTRIM(projects.Slug)), N'') IS NOT NULL THEN 0 ELSE 10 END
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
                ORDER BY countries.Name, countries.Id FOR JSON PATH), N'[]'
           )) AS CountriesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT regions.Id AS id, regions.CountryId AS countryId,
                       regions.Code AS code, regions.Name AS name
                FROM dbo.FundingPlatform_ProjectRegions AS projectRegions
                INNER JOIN dbo.FundingPlatform_Regions AS regions
                    ON regions.Id = projectRegions.RegionId AND regions.IsActive = 1
                WHERE projectRegions.ProjectId = projects.Id
                ORDER BY regions.Name, regions.Id FOR JSON PATH), N'[]'
           )) AS RegionsJson,
           JSON_QUERY(COALESCE
           (
               (SELECT categories.Id AS id, categories.Code AS code, categories.Name AS name
                FROM dbo.FundingPlatform_ProjectCategories AS projectCategories
                INNER JOIN dbo.FundingPlatform_FundingCategories AS categories
                    ON categories.Id = projectCategories.FundingCategoryId AND categories.IsActive = 1
                WHERE projectCategories.ProjectId = projects.Id
                ORDER BY categories.Name, categories.Id FOR JSON PATH), N'[]'
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
                ORDER BY beneficiaryTypes.Name, beneficiaryTypes.Id FOR JSON PATH), N'[]'
           )) AS BeneficiaryTypesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT projectTypes.Id AS id, projectTypes.Code AS code, projectTypes.Name AS name
                FROM dbo.FundingPlatform_ProjectProjectTypes AS projectProjectTypes
                INNER JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
                    ON projectTypes.Id = projectProjectTypes.ProjectTypeId AND projectTypes.IsActive = 1
                WHERE projectProjectTypes.ProjectId = projects.Id
                ORDER BY projectTypes.Name, projectTypes.Id FOR JSON PATH), N'[]'
           )) AS ProjectTypesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT goals.Id AS id, goals.Code AS code, goals.Name AS name
                FROM dbo.FundingPlatform_ProjectSustainableDevelopmentGoals AS projectGoals
                INNER JOIN dbo.FundingPlatform_SustainableDevelopmentGoals AS goals
                    ON goals.Id = projectGoals.SustainableDevelopmentGoalId AND goals.IsActive = 1
                WHERE projectGoals.ProjectId = projects.Id
                ORDER BY goals.Id FOR JSON PATH), N'[]'
           )) AS SustainableDevelopmentGoalsJson
    FROM dbo.FundingPlatform_Projects AS projects
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = projects.OrganizationId AND organizations.IsActive = 1
    WHERE projects.PublicId = @ProjectPublicId
      AND projects.PublicationStatus = 1
      AND projects.IsActive = 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectMarketplace_GetBySlug
    @Slug NVARCHAR(180)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @NormalizedSlug NVARCHAR(180) = NULLIF(LTRIM(RTRIM(@Slug)), N'');

    SELECT projects.PublicId AS ProjectPublicId, projects.Slug, projects.Title,
           projects.Summary, projects.Description, projects.ProjectStatus,
           projects.ProjectStage, projects.StartDate, projects.EndDate,
           projects.BudgetTotal, projects.ConfirmedFunding, projects.Currency,
           projects.FundingGap, projects.ProjectVersion, projects.PublishedAtUtc,
           projects.UpdatedAtUtc,
           /* Explicit allowlist: private coordinates never leave the public SQL boundary. */
           CASE WHEN projects.EnrichmentJson IS NULL THEN NULL ELSE
           (SELECT JSON_VALUE(projects.EnrichmentJson, '$.problem') AS problem,
                   JSON_VALUE(projects.EnrichmentJson, '$.solution') AS solution,
                   TRY_CONVERT(INT, JSON_VALUE(projects.EnrichmentJson, '$.beneficiaryCount')) AS beneficiaryCount,
                   CASE WHEN JSON_VALUE(projects.EnrichmentJson, '$.locationVisibility') IN (N'1', N'2')
                        THEN JSON_VALUE(projects.EnrichmentJson, '$.locality') END AS locality,
                   CASE WHEN JSON_VALUE(projects.EnrichmentJson, '$.locationVisibility') = N'2'
                        THEN ROUND(TRY_CONVERT(DECIMAL(38,18), JSON_VALUE(projects.EnrichmentJson, '$.latitude')), 2) END AS latitude,
                   CASE WHEN JSON_VALUE(projects.EnrichmentJson, '$.locationVisibility') = N'2'
                        THEN ROUND(TRY_CONVERT(DECIMAL(38,18), JSON_VALUE(projects.EnrichmentJson, '$.longitude')), 2) END AS longitude,
                   COALESCE(TRY_CONVERT(TINYINT, JSON_VALUE(projects.EnrichmentJson, '$.locationVisibility')), 0) AS locationVisibility,
                   JSON_QUERY(projects.EnrichmentJson, '$.impactIndicators') AS impactIndicators,
                   JSON_VALUE(projects.EnrichmentJson, '$.soughtPartners') AS soughtPartners,
                   JSON_VALUE(projects.EnrichmentJson, '$.soughtProfessionals') AS soughtProfessionals,
                   CASE JSON_VALUE(projects.EnrichmentJson, '$.seekingConsortium')
                        WHEN N'true' THEN CONVERT(BIT, 1) WHEN N'false' THEN CONVERT(BIT, 0) END AS seekingConsortium
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES) END AS EnrichmentJson,
           organizations.PublicId AS OrganizationPublicId,
           organizations.Name AS OrganizationName,
           organizations.WebsiteUrl AS OrganizationWebsiteUrl,
           JSON_QUERY(COALESCE
           (
               (SELECT countries.Id AS id, RTRIM(countries.Iso2) AS code,
                       countries.Name AS name
                FROM dbo.FundingPlatform_ProjectCountries AS projectCountries
                INNER JOIN dbo.FundingPlatform_Countries AS countries
                    ON countries.Id = projectCountries.CountryId AND countries.IsActive = 1
                WHERE projectCountries.ProjectId = projects.Id
                ORDER BY countries.Name, countries.Id FOR JSON PATH), N'[]'
           )) AS CountriesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT regions.Id AS id, regions.CountryId AS countryId,
                       regions.Code AS code, regions.Name AS name
                FROM dbo.FundingPlatform_ProjectRegions AS projectRegions
                INNER JOIN dbo.FundingPlatform_Regions AS regions
                    ON regions.Id = projectRegions.RegionId AND regions.IsActive = 1
                WHERE projectRegions.ProjectId = projects.Id
                ORDER BY regions.Name, regions.Id FOR JSON PATH), N'[]'
           )) AS RegionsJson,
           JSON_QUERY(COALESCE
           (
               (SELECT categories.Id AS id, categories.Code AS code, categories.Name AS name
                FROM dbo.FundingPlatform_ProjectCategories AS projectCategories
                INNER JOIN dbo.FundingPlatform_FundingCategories AS categories
                    ON categories.Id = projectCategories.FundingCategoryId
                   AND categories.IsActive = 1
                WHERE projectCategories.ProjectId = projects.Id
                ORDER BY categories.Name, categories.Id FOR JSON PATH), N'[]'
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
                ORDER BY beneficiaryTypes.Name, beneficiaryTypes.Id FOR JSON PATH), N'[]'
           )) AS BeneficiaryTypesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT projectTypes.Id AS id, projectTypes.Code AS code,
                       projectTypes.Name AS name
                FROM dbo.FundingPlatform_ProjectProjectTypes AS projectProjectTypes
                INNER JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
                    ON projectTypes.Id = projectProjectTypes.ProjectTypeId
                   AND projectTypes.IsActive = 1
                WHERE projectProjectTypes.ProjectId = projects.Id
                ORDER BY projectTypes.Name, projectTypes.Id FOR JSON PATH), N'[]'
           )) AS ProjectTypesJson,
           JSON_QUERY(COALESCE
           (
               (SELECT goals.Id AS id, goals.Code AS code, goals.Name AS name
                FROM dbo.FundingPlatform_ProjectSustainableDevelopmentGoals AS projectGoals
                INNER JOIN dbo.FundingPlatform_SustainableDevelopmentGoals AS goals
                    ON goals.Id = projectGoals.SustainableDevelopmentGoalId AND goals.IsActive = 1
                WHERE projectGoals.ProjectId = projects.Id
                ORDER BY goals.Id FOR JSON PATH), N'[]'
           )) AS SustainableDevelopmentGoalsJson
    FROM dbo.FundingPlatform_Projects AS projects
    INNER JOIN dbo.FundingPlatform_ifn_ProjectMarketplaceReady() AS ready
        ON ready.ProjectId = projects.Id
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = projects.OrganizationId
    WHERE projects.Slug = @NormalizedSlug;
END;
GO
