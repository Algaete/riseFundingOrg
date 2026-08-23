/*
    Transactional smoke test for database/Migrations/001_initial_schema.sql.
    Execute after the migration in the target database. Fixture data is always
    rolled back, including when the runner already owns an outer transaction.
    Any failure uses THROW.
*/

SET NOCOUNT ON;

DECLARE @ExpectedTables TABLE (Name SYSNAME NOT NULL);

INSERT INTO @ExpectedTables (Name)
VALUES
    (N'FundingPlatform_Countries'),
    (N'FundingPlatform_Currencies'),
    (N'FundingPlatform_Regions'),
    (N'FundingPlatform_FundingCategories'),
    (N'FundingPlatform_OrganizationTypes'),
    (N'FundingPlatform_LegalEntityTypes'),
    (N'FundingPlatform_OrganizationSizes'),
    (N'FundingPlatform_BeneficiaryTypes'),
    (N'FundingPlatform_FundingTypes'),
    (N'FundingPlatform_ProjectTypes'),
    (N'FundingPlatform_Tags'),
    (N'FundingPlatform_Languages'),
    (N'FundingPlatform_SubscriptionPlans'),
    (N'FundingPlatform_Features'),
    (N'FundingPlatform_SubscriptionPlanFeatures'),
    (N'FundingPlatform_Users'),
    (N'FundingPlatform_Roles'),
    (N'FundingPlatform_UserRoles'),
    (N'FundingPlatform_Organizations'),
    (N'FundingPlatform_OrganizationUsers'),
    (N'FundingPlatform_OrganizationCountries'),
    (N'FundingPlatform_OrganizationRegions'),
    (N'FundingPlatform_OrganizationCategories'),
    (N'FundingPlatform_OrganizationBeneficiaryTypes'),
    (N'FundingPlatform_OrganizationProjectTypes'),
    (N'FundingPlatform_OrganizationTags'),
    (N'FundingPlatform_OrganizationLanguages'),
    (N'FundingPlatform_OrganizationProfileVersions'),
    (N'FundingPlatform_FundingSources'),
    (N'FundingPlatform_FundingOpportunities'),
    (N'FundingPlatform_FundingOpportunityCategories'),
    (N'FundingPlatform_FundingOpportunityCountries'),
    (N'FundingPlatform_FundingOpportunityRegions'),
    (N'FundingPlatform_FundingOpportunityOrganizationTypes'),
    (N'FundingPlatform_FundingOpportunityLegalEntityTypes'),
    (N'FundingPlatform_FundingOpportunityBeneficiaryTypes'),
    (N'FundingPlatform_FundingOpportunityProjectTypes'),
    (N'FundingPlatform_FundingOpportunityTags'),
    (N'FundingPlatform_FundingOpportunityLanguages'),
    (N'FundingPlatform_FundingOpportunitySourceLinks'),
    (N'FundingPlatform_OutboxMessages');

DECLARE @MissingTables NVARCHAR(2048);

SELECT @MissingTables = STRING_AGG(Expected.Name, N', ')
FROM @ExpectedTables AS Expected
WHERE OBJECT_ID(N'dbo.' + Expected.Name, N'U') IS NULL;

IF @MissingTables IS NOT NULL
BEGIN
    DECLARE @MissingTablesMessage NVARCHAR(2048) = N'Missing FundingPlatform tables: ' + @MissingTables;
    THROW 52001, @MissingTablesMessage, 1;
END;

DECLARE @ExpectedTypes TABLE (Name SYSNAME NOT NULL);

INSERT INTO @ExpectedTypes (Name)
VALUES
    (N'FundingPlatform_SmallIntIdList'),
    (N'FundingPlatform_IntIdList'),
    (N'FundingPlatform_BigIntIdList'),
    (N'FundingPlatform_OrganizationLanguageList');

IF EXISTS
(
    SELECT 1
    FROM @ExpectedTypes AS Expected
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM sys.table_types AS TypeDefinition
        INNER JOIN sys.schemas AS SchemaDefinition ON SchemaDefinition.schema_id = TypeDefinition.schema_id
        WHERE SchemaDefinition.name COLLATE DATABASE_DEFAULT = N'dbo' COLLATE DATABASE_DEFAULT
          AND TypeDefinition.name COLLATE DATABASE_DEFAULT = Expected.Name COLLATE DATABASE_DEFAULT
    )
)
    THROW 52002, N'One or more FundingPlatform table types are missing.', 1;

DECLARE @ExpectedProcedures TABLE (Name SYSNAME NOT NULL);

INSERT INTO @ExpectedProcedures (Name)
VALUES
    (N'FundingPlatform_usp_Organization_Create'),
    (N'FundingPlatform_usp_Organization_GetProfile'),
    (N'FundingPlatform_usp_Organization_UpdateProfile'),
    (N'FundingPlatform_usp_FundingOpportunity_GetById'),
    (N'FundingPlatform_usp_FundingOpportunity_Search'),
    (N'FundingPlatform_usp_Outbox_Claim'),
    (N'FundingPlatform_usp_Outbox_Complete'),
    (N'FundingPlatform_usp_Outbox_Release');

IF EXISTS
(
    SELECT 1
    FROM @ExpectedProcedures AS Expected
    WHERE OBJECT_ID(N'dbo.' + Expected.Name, N'P') IS NULL
)
    THROW 52003, N'One or more FundingPlatform stored procedures are missing.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_Countries
    WHERE Id = 152 AND Iso2 = 'CL' AND Iso3 = 'CHL' AND Name = N'Chile' AND IsActive = 1
)
    THROW 52004, N'The deterministic Chile country seed is missing.', 1;

IF
(
    SELECT COUNT_BIG(1)
    FROM dbo.FundingPlatform_Regions
    WHERE CountryId = 152 AND Code IN
        (N'CL-AP', N'CL-TA', N'CL-AN', N'CL-AT', N'CL-CO', N'CL-VS', N'CL-RM', N'CL-LI',
         N'CL-ML', N'CL-NB', N'CL-BI', N'CL-AR', N'CL-LR', N'CL-LL', N'CL-AI', N'CL-MA')
) <> 16
    THROW 52005, N'The 16-region Chile seed is incomplete.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_Currencies
    WHERE Code = 'CLP' AND MinorUnits = 0 AND IsActive = 1
)
    THROW 52006, N'The CLP currency seed is missing.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_SubscriptionPlans
    WHERE Id = 1 AND Code = N'FREE' AND IsActive = 1 AND IsPurchasable = 0
)
    THROW 52007, N'The Free plan seed is missing or invalid.', 1;

IF
(
    SELECT COUNT_BIG(1)
    FROM dbo.FundingPlatform_SubscriptionPlanFeatures
    WHERE SubscriptionPlanId = 1
) <> 10
    THROW 52008, N'The Free plan must contain its 10 baseline feature entitlements.', 1;

IF NOT EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_Roles WHERE NormalizedName = N'SUPERADMIN'
)
OR NOT EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_Roles WHERE NormalizedName = N'ADMIN'
)
    THROW 52009, N'The global role seed is incomplete.', 1;

/* All persisted objects associated with this product must be visibly namespaced. */
IF EXISTS
(
    SELECT 1
    FROM sys.objects AS ObjectDefinition
    INNER JOIN sys.schemas AS SchemaDefinition ON SchemaDefinition.schema_id = ObjectDefinition.schema_id
    WHERE SchemaDefinition.name COLLATE DATABASE_DEFAULT = N'dbo' COLLATE DATABASE_DEFAULT
      AND
      (
          ObjectDefinition.name COLLATE DATABASE_DEFAULT LIKE N'%FundingPlatform[_]%' COLLATE DATABASE_DEFAULT
          OR OBJECT_DEFINITION(ObjectDefinition.object_id) COLLATE DATABASE_DEFAULT
             LIKE N'%FundingPlatform[_]%' COLLATE DATABASE_DEFAULT
      )
      AND LEFT(ObjectDefinition.name COLLATE DATABASE_DEFAULT, 16)
          <> N'FundingPlatform_' COLLATE DATABASE_DEFAULT
)
    THROW 52010, N'A FundingPlatform-owned object does not use the FundingPlatform_ prefix.', 1;

IF EXISTS
(
    SELECT 1
    FROM sys.objects AS ConstraintDefinition
    INNER JOIN sys.tables AS ParentTable ON ParentTable.object_id = ConstraintDefinition.parent_object_id
    WHERE LEFT(ParentTable.name COLLATE DATABASE_DEFAULT, 16)
          = N'FundingPlatform_' COLLATE DATABASE_DEFAULT
      AND ConstraintDefinition.type IN (N'C', N'D', N'F', N'PK', N'UQ')
      AND LEFT(ConstraintDefinition.name COLLATE DATABASE_DEFAULT, 16)
          <> N'FundingPlatform_' COLLATE DATABASE_DEFAULT
)
    THROW 52011, N'A FundingPlatform constraint does not use the FundingPlatform_ prefix.', 1;

IF EXISTS
(
    SELECT 1
    FROM sys.indexes AS IndexDefinition
    INNER JOIN sys.tables AS ParentTable ON ParentTable.object_id = IndexDefinition.object_id
    WHERE LEFT(ParentTable.name COLLATE DATABASE_DEFAULT, 16)
          = N'FundingPlatform_' COLLATE DATABASE_DEFAULT
      AND IndexDefinition.index_id > 0
      AND IndexDefinition.name IS NOT NULL
      AND LEFT(IndexDefinition.name COLLATE DATABASE_DEFAULT, 16)
          <> N'FundingPlatform_' COLLATE DATABASE_DEFAULT
)
    THROW 52012, N'A FundingPlatform index does not use the FundingPlatform_ prefix.', 1;

/* Exercise aggregate and outbox procedures with fixtures that never persist. */
DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

IF @InitialTransactionCount = 0
    BEGIN TRANSACTION;
ELSE
    SAVE TRANSACTION FundingPlatform_Smoke001;

BEGIN TRY
    DECLARE @FixtureToken UNIQUEIDENTIFIER = NEWID();
    DECLARE @FixtureEmail NVARCHAR(320) =
        N'smoke-' + REPLACE(CONVERT(NVARCHAR(36), @FixtureToken), N'-', N'') + N'@example.invalid';
    DECLARE @FixtureUserId BIGINT;

    INSERT INTO dbo.FundingPlatform_Users
        (Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp, Status)
    VALUES
        (@FixtureEmail, UPPER(@FixtureEmail), N'SQL smoke fixture',
         N'not-a-real-password-hash-smoke-only', CONVERT(NVARCHAR(100), NEWID()), 2);

    SET @FixtureUserId = CONVERT(BIGINT, SCOPE_IDENTITY());

    DECLARE @InitialSnapshotJson NVARCHAR(MAX) =
        N'{"name":"SQL smoke organization","countryIds":[152]}';
    DECLARE @InitialContentHash BINARY(32) = HASHBYTES('SHA2_256', @InitialSnapshotJson);
    DECLARE @CreatedOrganization TABLE
    (
        Id BIGINT NOT NULL,
        PublicId UNIQUEIDENTIFIER NOT NULL,
        ProfileVersion INT NOT NULL,
        RowVersion BINARY(8) NOT NULL
    );

    INSERT INTO @CreatedOrganization (Id, PublicId, ProfileVersion, RowVersion)
    EXEC dbo.FundingPlatform_usp_Organization_Create
        @CreatedByUserId = @FixtureUserId,
        @Name = N'SQL smoke organization',
        @HomeCountryId = 152,
        @OrganizationTypeId = 1,
        @SnapshotJson = @InitialSnapshotJson,
        @ContentHash = @InitialContentHash;

    DECLARE @FixtureOrganizationId BIGINT = (SELECT Id FROM @CreatedOrganization);
    DECLARE @CreatedRowVersion BINARY(8) = (SELECT RowVersion FROM @CreatedOrganization);

    IF @FixtureOrganizationId IS NULL
        THROW 52013, N'Organization_Create did not return the created organization.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_OrganizationUsers
        WHERE OrganizationId = @FixtureOrganizationId
          AND UserId = @FixtureUserId
          AND Role = 1
          AND MembershipStatus = 1
    )
        THROW 52014, N'Organization_Create did not create the active administrator membership.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_OrganizationProfileVersions
        WHERE OrganizationId = @FixtureOrganizationId
          AND ProfileVersion = 1
          AND ContentHash = @InitialContentHash
    )
        THROW 52015, N'Organization_Create did not persist profile version 1.', 1;

    DECLARE @CountryIds dbo.FundingPlatform_SmallIntIdList;
    DECLARE @RegionIds dbo.FundingPlatform_IntIdList;
    DECLARE @CategoryIds dbo.FundingPlatform_IntIdList;
    DECLARE @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList;
    DECLARE @ProjectTypeIds dbo.FundingPlatform_IntIdList;
    DECLARE @TagIds dbo.FundingPlatform_BigIntIdList;
    DECLARE @Languages dbo.FundingPlatform_OrganizationLanguageList;

    INSERT INTO @CountryIds (Id) VALUES (152);
    INSERT INTO @RegionIds (Id) VALUES (7);
    INSERT INTO @CategoryIds (Id) VALUES (1);
    INSERT INTO @BeneficiaryTypeIds (Id) VALUES (1);
    INSERT INTO @ProjectTypeIds (Id) VALUES (1);
    INSERT INTO @Languages (LanguageId, Proficiency) VALUES (1, 5);

    DECLARE @UpdatedSnapshotJson NVARCHAR(MAX) =
        N'{"name":"SQL smoke organization updated","countryIds":[152],"regionIds":[7]}';
    DECLARE @UpdatedContentHash BINARY(32) = HASHBYTES('SHA2_256', @UpdatedSnapshotJson);
    DECLARE @UpdatedOrganization TABLE
    (
        Id BIGINT NOT NULL,
        PublicId UNIQUEIDENTIFIER NOT NULL,
        ProfileVersion INT NOT NULL,
        RowVersion BINARY(8) NOT NULL
    );

    INSERT INTO @UpdatedOrganization (Id, PublicId, ProfileVersion, RowVersion)
    EXEC dbo.FundingPlatform_usp_Organization_UpdateProfile
        @OrganizationId = @FixtureOrganizationId,
        @ActorUserId = @FixtureUserId,
        @ExpectedRowVersion = @CreatedRowVersion,
        @Name = N'SQL smoke organization updated',
        @HomeCountryId = 152,
        @OrganizationTypeId = 1,
        @ProfileStatus = 1,
        @ProfileCompleteness = 75.00,
        @SnapshotJson = @UpdatedSnapshotJson,
        @ContentHash = @UpdatedContentHash,
        @CountryIds = @CountryIds,
        @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds,
        @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds,
        @TagIds = @TagIds,
        @Languages = @Languages;

    IF NOT EXISTS
    (
        SELECT 1
        FROM @UpdatedOrganization
        WHERE Id = @FixtureOrganizationId
          AND ProfileVersion = 2
          AND RowVersion <> @CreatedRowVersion
    )
        THROW 52016, N'Organization_UpdateProfile did not advance version and rowversion.', 1;

    IF
    (
        SELECT COUNT_BIG(1)
        FROM dbo.FundingPlatform_OrganizationProfileVersions
        WHERE OrganizationId = @FixtureOrganizationId
    ) <> 2
        THROW 52017, N'Organization profile version history is incomplete.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_OrganizationRegions
        WHERE OrganizationId = @FixtureOrganizationId AND RegionId = 7
    )
    OR NOT EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_OrganizationLanguages
        WHERE OrganizationId = @FixtureOrganizationId AND LanguageId = 1 AND Proficiency = 5
    )
        THROW 52018, N'Organization_UpdateProfile did not replace profile relations.', 1;

    IF
    (
        SELECT COUNT_BIG(1)
        FROM dbo.FundingPlatform_OutboxMessages
        WHERE AggregateType = N'Organization'
          AND AggregateId = CONVERT(NVARCHAR(100), @FixtureOrganizationId)
          AND MessageType IN (N'OrganizationCreated', N'OrganizationProfileChanged')
    ) <> 2
        THROW 52019, N'Organization procedures did not write both transactional outbox events.', 1;

    DECLARE @ProbeMessageId UNIQUEIDENTIFIER = NEWID();
    DECLARE @LeaseOwner NVARCHAR(100) = N'sql-smoke-' + CONVERT(NVARCHAR(36), NEWID());
    DECLARE @ProbeNowUtc DATETIME2(3) = SYSUTCDATETIME();

    INSERT INTO dbo.FundingPlatform_OutboxMessages
        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
         OccurredAtUtc, AvailableAtUtc)
    VALUES
        (@ProbeMessageId, N'SmokeProbe', N'SmokeFixture', CONVERT(NVARCHAR(100), @FixtureToken), N'{}',
         @ProbeNowUtc, CONVERT(DATETIME2(3), '0001-01-01T00:00:00.000'));

    DECLARE @ClaimedMessages TABLE
    (
        Id BIGINT NOT NULL,
        MessageId UNIQUEIDENTIFIER NOT NULL,
        MessageType NVARCHAR(100) NOT NULL,
        AggregateType NVARCHAR(100) NOT NULL,
        AggregateId NVARCHAR(100) NOT NULL,
        PayloadJson NVARCHAR(MAX) NOT NULL,
        OccurredAtUtc DATETIME2(3) NOT NULL,
        AttemptCount SMALLINT NOT NULL,
        LeaseUntilUtc DATETIME2(3) NOT NULL
    );

    INSERT INTO @ClaimedMessages
        (Id, MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
         OccurredAtUtc, AttemptCount, LeaseUntilUtc)
    EXEC dbo.FundingPlatform_usp_Outbox_Claim
        @LeaseOwner = @LeaseOwner,
        @BatchSize = 1,
        @LeaseSeconds = 30,
        @NowUtc = @ProbeNowUtc;

    IF NOT EXISTS
    (
        SELECT 1
        FROM @ClaimedMessages
        WHERE MessageId = @ProbeMessageId AND AttemptCount = 1
    )
        THROW 52020, N'Outbox_Claim did not lease the smoke message.', 1;

    EXEC dbo.FundingPlatform_usp_Outbox_Complete
        @MessageId = @ProbeMessageId,
        @LeaseOwner = @LeaseOwner,
        @DispatchedAtUtc = @ProbeNowUtc;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_OutboxMessages
        WHERE MessageId = @ProbeMessageId
          AND DispatchedAtUtc = @ProbeNowUtc
          AND LeaseOwner IS NULL
          AND LeaseUntilUtc IS NULL
    )
        THROW 52021, N'Outbox_Complete did not finish the leased smoke message.', 1;

    IF @InitialTransactionCount = 0
        ROLLBACK TRANSACTION;
    ELSE
        ROLLBACK TRANSACTION FundingPlatform_Smoke001;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FundingPlatform_Smoke001;
    THROW;
END CATCH;

SELECT
    CAST(1 AS BIT) AS Succeeded,
    (SELECT COUNT_BIG(1) FROM @ExpectedTables) AS ExpectedTableCount,
    (SELECT COUNT_BIG(1) FROM @ExpectedTypes) AS ExpectedTypeCount,
    (SELECT COUNT_BIG(1) FROM @ExpectedProcedures) AS ExpectedProcedureCount;
