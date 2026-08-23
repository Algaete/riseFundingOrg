/* FASE 6 transactional smoke. All fixture data is rolled back. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @RequiredTables TABLE (Name SYSNAME NOT NULL PRIMARY KEY);
INSERT INTO @RequiredTables (Name) VALUES
    (N'FundingPlatform_Funders'),
    (N'FundingPlatform_FunderAliases'),
    (N'FundingPlatform_FunderVersions'),
    (N'FundingPlatform_FunderEditorialEvents'),
    (N'FundingPlatform_FundingOpportunityFunders'),
    (N'FundingPlatform_FundingOpportunityVersions'),
    (N'FundingPlatform_FundingOpportunityEditorialEvents'),
    (N'FundingPlatform_FundingFieldEvidence'),
    (N'FundingPlatform_FundingOpportunityStagedRevisions');

IF EXISTS
(
    SELECT 1
    FROM @RequiredTables AS required
    LEFT JOIN sys.tables AS actual
        ON actual.name COLLATE DATABASE_DEFAULT = required.Name COLLATE DATABASE_DEFAULT
       AND actual.schema_id = SCHEMA_ID(N'dbo')
    WHERE actual.object_id IS NULL
)
    THROW 53001, N'One or more FASE 6 tables are missing.', 1;

DECLARE @RequiredProcedures TABLE (Name SYSNAME NOT NULL PRIMARY KEY);
INSERT INTO @RequiredProcedures (Name) VALUES
    (N'FundingPlatform_usp_FundingSource_AdminList'),
    (N'FundingPlatform_usp_Funder_Admin_List'),
    (N'FundingPlatform_usp_Funder_Admin_Get'),
    (N'FundingPlatform_usp_Funder_Public_List'),
    (N'FundingPlatform_usp_Funder_Public_GetBySlug'),
    (N'FundingPlatform_usp_Funder_Create'),
    (N'FundingPlatform_usp_Funder_Update'),
    (N'FundingPlatform_usp_Funder_RequestPublication'),
    (N'FundingPlatform_usp_Funder_AdminReview'),
    (N'FundingPlatform_usp_Funder_StartCorrection'),
    (N'FundingPlatform_usp_Funder_Deactivate'),
    (N'FundingPlatform_usp_FundingOpportunity_Admin_List'),
    (N'FundingPlatform_usp_FundingOpportunity_Admin_Get'),
    (N'FundingPlatform_usp_FundingOpportunity_Public_List'),
    (N'FundingPlatform_usp_FundingOpportunity_Public_GetBySlug'),
    (N'FundingPlatform_usp_FundingOpportunity_Create'),
    (N'FundingPlatform_usp_FundingOpportunity_Update'),
    (N'FundingPlatform_usp_FundingOpportunity_RequestPublication'),
    (N'FundingPlatform_usp_FundingOpportunity_AdminReview'),
    (N'FundingPlatform_usp_FundingOpportunity_StartCorrection'),
    (N'FundingPlatform_usp_FundingOpportunity_Deactivate'),
    (N'FundingPlatform_usp_FundingOpportunity_StageExternal'),
    (N'FundingPlatform_usp_RefreshToken_Create'),
    (N'FundingPlatform_usp_RefreshToken_Rotate');

IF EXISTS
(
    SELECT 1
    FROM @RequiredProcedures AS required
    LEFT JOIN sys.procedures AS actual
        ON actual.name COLLATE DATABASE_DEFAULT = required.Name COLLATE DATABASE_DEFAULT
       AND actual.schema_id = SCHEMA_ID(N'dbo')
    WHERE actual.object_id IS NULL
)
    THROW 53002, N'One or more FASE 6 procedures are missing.', 1;

IF OBJECT_ID(N'dbo.FundingPlatform_fn_AdminAccessState', N'FN') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs', N'IF') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_RefreshTokens', N'MfaAuthenticatedAtUtc') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_FundingOpportunities', N'SubmittedAtUtc') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_FundingOpportunities', N'ReviewedAtUtc') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_FunderEditorialEvents', N'ResultRowVersion') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_FunderEditorialEvents', N'ResultSubmittedAtUtc') IS NULL
   OR COL_LENGTH(N'dbo.FundingPlatform_FundingOpportunityEditorialEvents', N'ResultSubmittedAtUtc') IS NULL
    THROW 53003, N'FASE 6 editorial schema is incomplete.', 1;

IF NOT EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_FundingSources
    WHERE Name = N'Manual editorial' AND ProviderType = 0 AND IsEnabled = 1
)
    THROW 53004, N'The Manual editorial source was not seeded.', 1;

IF EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
    WHERE (PublicationStatus = 2 AND (PublishedAtUtc IS NULL OR ReviewedAtUtc IS NULL))
       OR (PublicationStatus = 4 AND IsActive <> 0)
       OR (PublicationStatus <> 4 AND IsActive <> 1)
)
    THROW 53041, N'Legacy opportunity editorial timestamps or archive state were not normalized.', 1;

/* Every legacy sponsor and opportunity must have a canonical snapshot and primary funder. */
IF EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    WHERE NULLIF(LTRIM(RTRIM(opportunities.SponsorName)), N'') IS NOT NULL
      AND
      (
          NOT EXISTS
          (
              SELECT 1
              FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
              WHERE links.FundingOpportunityId = opportunities.Id
                AND links.Role = 1 AND links.IsActive = 1
          )
          OR NOT EXISTS
          (
              SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityVersions AS versions
              WHERE versions.FundingOpportunityId = opportunities.Id
                AND versions.ContentVersion = opportunities.ContentVersion
          )
          OR EXISTS
          (
              SELECT required.FieldPath
              FROM (VALUES (N'/title'), (N'/description'),
                           (N'/eligibilityDescription'), (N'/closeDate')) AS required(FieldPath)
              WHERE NOT EXISTS
              (
                  SELECT 1 FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
                  WHERE evidence.FundingOpportunityId = opportunities.Id
                    AND evidence.FieldPath = required.FieldPath
                    AND evidence.IsSelected = 1
                    AND JSON_VALUE(evidence.ValueJson, '$.status') IN (N'known', N'unknown')
              )
          )
      )
)
    THROW 53005, N'Legacy sponsor or opportunity backfill is incomplete.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FundingPlatform_Smoke010;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @Suffix NVARCHAR(32) = REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'');
    DECLARE @AdminPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @SuperAdminPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @NoMfaPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @NoRolePublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @AdminEmail NVARCHAR(320) = N'fase6-admin-' + @Suffix + N'@example.invalid';
    DECLARE @SuperAdminEmail NVARCHAR(320) = N'fase6-super-' + @Suffix + N'@example.invalid';
    DECLARE @NoMfaEmail NVARCHAR(320) = N'fase6-nomfa-' + @Suffix + N'@example.invalid';
    DECLARE @NoRoleEmail NVARCHAR(320) = N'fase6-norole-' + @Suffix + N'@example.invalid';

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@AdminPublicId, @AdminEmail, UPPER(@AdminEmail), N'FASE 6 Admin',
         N'not-a-credential', N'fase6-admin', 1, 1, 2, N'es-CL'),
        (@SuperAdminPublicId, @SuperAdminEmail, UPPER(@SuperAdminEmail), N'FASE 6 SuperAdmin',
         N'not-a-credential', N'fase6-super', 1, 1, 2, N'es-CL'),
        (@NoMfaPublicId, @NoMfaEmail, UPPER(@NoMfaEmail), N'FASE 6 no MFA',
         N'not-a-credential', N'fase6-nomfa', 1, 0, 2, N'es-CL'),
        (@NoRolePublicId, @NoRoleEmail, UPPER(@NoRoleEmail), N'FASE 6 no role',
         N'not-a-credential', N'fase6-norole', 1, 1, 2, N'es-CL');

    DECLARE @AdminUserId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @AdminPublicId);
    DECLARE @SuperAdminUserId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @SuperAdminPublicId);
    DECLARE @NoMfaUserId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @NoMfaPublicId);
    DECLARE @AdminRoleId SMALLINT =
        (SELECT Id FROM dbo.FundingPlatform_Roles WHERE NormalizedName = N'ADMIN');
    DECLARE @SuperAdminRoleId SMALLINT =
        (SELECT Id FROM dbo.FundingPlatform_Roles WHERE NormalizedName = N'SUPERADMIN');

    INSERT INTO dbo.FundingPlatform_UserRoles (UserId, RoleId, GrantedByUserId)
    VALUES (@AdminUserId, @AdminRoleId, @AdminUserId),
           (@SuperAdminUserId, @SuperAdminRoleId, @SuperAdminUserId),
           (@NoMfaUserId, @AdminRoleId, @AdminUserId);

    /* MFA authentication time is carried unchanged across refresh rotation. */
    DECLARE @RefreshNowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @MfaAuthenticatedAtUtc DATETIME2(3) = DATEADD(MINUTE, -1, @RefreshNowUtc);
    DECLARE @RefreshSecurityVersion INT =
        (SELECT SecurityVersion FROM dbo.FundingPlatform_Users WHERE Id = @AdminUserId);
    DECLARE @RefreshFamilyId UNIQUEIDENTIFIER = NEWID();
    DECLARE @RefreshExpiresAtUtc DATETIME2(3) = DATEADD(DAY, 1, @RefreshNowUtc);
    DECLARE @RefreshGraceUntilUtc DATETIME2(3) = DATEADD(SECOND, 5, @RefreshNowUtc);
    DECLARE @CurrentRefreshHash BINARY(32) =
        HASHBYTES('SHA2_256', N'fase6-refresh-current-' + @Suffix);
    DECLARE @ReplacementRefreshHash BINARY(32) =
        HASHBYTES('SHA2_256', N'fase6-refresh-replacement-' + @Suffix);
    EXEC dbo.FundingPlatform_usp_RefreshToken_Create
        @UserId = @AdminUserId, @SecurityVersion = @RefreshSecurityVersion,
        @MfaAuthenticated = 1, @MfaAuthenticatedAtUtc = @MfaAuthenticatedAtUtc,
        @FamilyId = @RefreshFamilyId, @TokenHash = @CurrentRefreshHash,
        @JwtId = @Fixture, @ExpiresAtUtc = @RefreshExpiresAtUtc,
        @CreatedAtUtc = @RefreshNowUtc;
    DECLARE @RefreshRotation TABLE
    (
        ResultCode TINYINT, UserId BIGINT, PublicId UNIQUEIDENTIFIER,
        Email NVARCHAR(320), DisplayName NVARCHAR(150), SecurityVersion INT,
        TwoFactorEnabled BIT, MfaAuthenticated BIT,
        MfaAuthenticatedAtUtc DATETIME2(3), FamilyId UNIQUEIDENTIFIER
    );
    INSERT INTO @RefreshRotation
    EXEC dbo.FundingPlatform_usp_RefreshToken_Rotate
        @CurrentTokenHash = @CurrentRefreshHash,
        @ReplacementTokenHash = @ReplacementRefreshHash,
        @ReplacementJwtId = @NoRolePublicId,
        @ReplacementExpiresAtUtc = @RefreshExpiresAtUtc,
        @NowUtc = @RefreshNowUtc,
        @GraceUntilUtc = @RefreshGraceUntilUtc;
    IF NOT EXISTS
       (SELECT 1 FROM @RefreshRotation
        WHERE ResultCode = 0 AND MfaAuthenticated = 1
          AND MfaAuthenticatedAtUtc = @MfaAuthenticatedAtUtc
          AND FamilyId = @RefreshFamilyId)
       OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_RefreshTokens
        WHERE TokenHash = @ReplacementRefreshHash
          AND MfaAuthenticatedAtUtc = @MfaAuthenticatedAtUtc)
        THROW 53051, N'Refresh rotation did not preserve the original MFA instant.', 1;

    /* Read authorization: both privileged roles pass; role and MFA failures are distinct. */
    EXEC dbo.FundingPlatform_usp_FundingSource_AdminList @AdminUserPublicId = @AdminPublicId;
    EXEC dbo.FundingPlatform_usp_FundingSource_AdminList @AdminUserPublicId = @SuperAdminPublicId;

    DECLARE @NoRoleBlocked BIT = 0, @NoMfaBlocked BIT = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_FundingSource_AdminList @AdminUserPublicId = @NoRolePublicId;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 51601 SET @NoRoleBlocked = 1;
        ELSE THROW;
    END CATCH;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_FundingSource_AdminList @AdminUserPublicId = @NoMfaPublicId;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 51602 SET @NoMfaBlocked = 1;
        ELSE THROW;
    END CATCH;
    SET XACT_ABORT ON;
    IF @NoRoleBlocked = 0 OR @NoMfaBlocked = 0
        THROW 53006, N'Administrative role/MFA authorization was not enforced.', 1;

    DECLARE @CountryId SMALLINT, @RegionId INT, @CategoryId INT;
    DECLARE @BeneficiaryTypeId INT, @ProjectTypeId INT, @FundingTypeId SMALLINT;
    SELECT TOP (1) @RegionId = regions.Id, @CountryId = regions.CountryId
    FROM dbo.FundingPlatform_Regions AS regions
    INNER JOIN dbo.FundingPlatform_Countries AS countries ON countries.Id = regions.CountryId
    WHERE regions.IsActive = 1 AND countries.IsActive = 1
    ORDER BY regions.Id;
    SELECT TOP (1) @CategoryId = Id FROM dbo.FundingPlatform_FundingCategories
    WHERE IsActive = 1 ORDER BY Id;
    SELECT TOP (1) @BeneficiaryTypeId = Id FROM dbo.FundingPlatform_BeneficiaryTypes
    WHERE IsActive = 1 ORDER BY Id;
    SELECT TOP (1) @ProjectTypeId = Id FROM dbo.FundingPlatform_ProjectTypes
    WHERE IsActive = 1 ORDER BY Id;
    SELECT TOP (1) @FundingTypeId = Id FROM dbo.FundingPlatform_FundingTypes
    WHERE IsActive = 1 ORDER BY Id;
    IF @CountryId IS NULL OR @RegionId IS NULL OR @CategoryId IS NULL
       OR @BeneficiaryTypeId IS NULL OR @ProjectTypeId IS NULL OR @FundingTypeId IS NULL
        THROW 53007, N'Required active catalog fixtures are unavailable.', 1;

    DECLARE @ManualSourceId INT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_FundingSources
         WHERE Name = N'Manual editorial' AND IsEnabled = 1 ORDER BY Id);

    /* Canonical funder CRUD, ETag, versioning and idempotent historical replay. */
    DECLARE @FunderSlug NVARCHAR(180) = N'fase6-funder-' + @Suffix;
    DECLARE @FunderName NVARCHAR(300) = N'Fundación FASE 6 ' + @Suffix;
    DECLARE @UpdatedFunderName NVARCHAR(300) = N'Fundación FASE 6 actualizada ' + @Suffix;
    DECLARE @FunderCreateKey BINARY(32) = HASHBYTES('SHA2_256', N'funder-create-' + @Suffix);
    DECLARE @FunderCreateHash BINARY(32) = HASHBYTES('SHA2_256', N'funder-create-body-' + @Suffix);
    DECLARE @FunderStaleKey BINARY(32) = HASHBYTES('SHA2_256', N'funder-stale-' + @Suffix);
    DECLARE @FunderStaleHash BINARY(32) = HASHBYTES('SHA2_256', N'funder-stale-body-' + @Suffix);
    DECLARE @FunderWrite TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), FunderPublicId UNIQUEIDENTIFIER,
        ContentVersion INT, PublicationStatus TINYINT, RowVersion BINARY(8), WasReplay BIT
    );
    DECLARE @InvalidAliasSlug NVARCHAR(180) = N'fase6-invalid-alias-' + @Suffix;
    INSERT INTO @FunderWrite
    EXEC dbo.FundingPlatform_usp_Funder_Create
        @AdminUserPublicId = @AdminPublicId, @Slug = @InvalidAliasSlug,
        @Name = N'Invalid alias fixture', @AliasesJson = N'[{"notAlias":"missing"}]',
        @IdempotencyKeyHash = 0x0101010101010101010101010101010101010101010101010101010101010101,
        @RequestHash = 0x0202020202020202020202020202020202020202020202020202020202020202;
    IF NOT EXISTS (SELECT 1 FROM @FunderWrite
                   WHERE Succeeded = 0 AND Code = N'invalid-document')
       OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders WHERE Slug = @InvalidAliasSlug)
        THROW 53048, N'Invalid alias elements were silently accepted.', 1;
    DELETE FROM @FunderWrite;
    INSERT INTO @FunderWrite
    EXEC dbo.FundingPlatform_usp_Funder_Create
        @AdminUserPublicId = @AdminPublicId, @Slug = @FunderSlug,
        @Name = @FunderName,
        @Description = N'Funder canónico para smoke editorial.',
        @WebsiteUrl = N'https://funder.example.invalid', @CountryId = @CountryId,
        @AliasesJson = N'[{"alias":"Funder smoke alias"}]',
        @IdempotencyKeyHash = @FunderCreateKey, @RequestHash = @FunderCreateHash;
    IF NOT EXISTS
       (SELECT 1 FROM @FunderWrite WHERE Succeeded = 1 AND Code = N'created'
                                      AND ContentVersion = 1 AND PublicationStatus = 0)
        THROW 53008, N'Funder creation failed.', 1;

    DECLARE @FunderPublicId UNIQUEIDENTIFIER = (SELECT TOP (1) FunderPublicId FROM @FunderWrite);
    DECLARE @FunderCreateRowVersion BINARY(8) = (SELECT TOP (1) RowVersion FROM @FunderWrite);
    DECLARE @FunderId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Funders WHERE PublicId = @FunderPublicId);
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders
               WHERE Id = @FunderId AND (PublicationStatus <> 0 OR IsActive <> 1))
       OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders
                  WHERE Id = @FunderId AND Slug <> @FunderSlug)
       OR (SELECT COUNT(*) FROM dbo.FundingPlatform_FunderVersions WHERE FunderId = @FunderId) <> 1
       OR (SELECT COUNT(*) FROM dbo.FundingPlatform_FunderAliases
           WHERE FunderId = @FunderId AND IsPrimary = 1 AND IsActive = 1) <> 1
        THROW 53009, N'Funder aggregate invariants failed after create.', 1;
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders
               WHERE Id = @FunderId AND PublicationStatus = 2 AND IsActive = 1)
        THROW 53010, N'A draft funder was exposed by the public predicate.', 1;
    EXEC dbo.FundingPlatform_usp_Funder_Public_GetBySlug @Slug = @FunderSlug;

    DELETE FROM @FunderWrite;
    INSERT INTO @FunderWrite
    EXEC dbo.FundingPlatform_usp_Funder_Update
        @AdminUserPublicId = @AdminPublicId, @FunderPublicId = @FunderPublicId,
        @ExpectedRowVersion = 0x0000000000000000,
        @Name = @UpdatedFunderName,
        @Description = N'Update con ETag inválido.',
        @WebsiteUrl = N'https://funder.example.invalid', @CountryId = @CountryId,
        @AliasesJson = N'[]',
        @IdempotencyKeyHash = @FunderStaleKey,
        @RequestHash = @FunderStaleHash;
    IF NOT EXISTS (SELECT 1 FROM @FunderWrite WHERE Succeeded = 0 AND Code = N'etag-conflict')
        THROW 53011, N'Funder stale ETag was accepted.', 1;

    DECLARE @FunderUpdateKey BINARY(32) = HASHBYTES('SHA2_256', N'funder-update-' + @Suffix);
    DECLARE @FunderUpdateHash BINARY(32) = HASHBYTES('SHA2_256', N'funder-update-body-' + @Suffix);
    DELETE FROM @FunderWrite;
    INSERT INTO @FunderWrite
    EXEC dbo.FundingPlatform_usp_Funder_Update
        @AdminUserPublicId = @AdminPublicId, @FunderPublicId = @FunderPublicId,
        @ExpectedRowVersion = @FunderCreateRowVersion,
        @Name = @UpdatedFunderName,
        @Description = N'Funder actualizado y versionado.',
        @WebsiteUrl = N'https://funder.example.invalid', @CountryId = @CountryId,
        @AliasesJson = N'[{"alias":"Alias editorial"}]',
        @IdempotencyKeyHash = @FunderUpdateKey, @RequestHash = @FunderUpdateHash;
    IF NOT EXISTS
       (SELECT 1 FROM @FunderWrite WHERE Succeeded = 1 AND Code = N'updated'
                                      AND ContentVersion = 2 AND PublicationStatus = 0)
        THROW 53012, N'Funder update/versioning failed.', 1;
    DECLARE @FunderUpdateRowVersion BINARY(8) = (SELECT TOP (1) RowVersion FROM @FunderWrite);

    DECLARE @FunderResultCode NVARCHAR(50), @FunderCompleteness DECIMAL(5,2);
    DECLARE @FunderRequestKey BINARY(32) = HASHBYTES('SHA2_256', N'funder-request-' + @Suffix);
    DECLARE @FunderRequestHash BINARY(32) = HASHBYTES('SHA2_256', N'funder-request-body-' + @Suffix);
    EXEC dbo.FundingPlatform_usp_Funder_RequestPublication
        @AdminUserPublicId = @AdminPublicId, @FunderPublicId = @FunderPublicId,
        @ExpectedRowVersion = @FunderUpdateRowVersion,
        @IdempotencyKeyHash = @FunderRequestKey, @RequestHash = @FunderRequestHash,
        @ResultCode = @FunderResultCode OUTPUT, @ResultCompleteness = @FunderCompleteness OUTPUT;
    IF @FunderResultCode <> N'review-requested' OR @FunderCompleteness <> 100
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders
                      WHERE Id = @FunderId AND PublicationStatus = 1 AND SubmittedAtUtc IS NOT NULL)
        THROW 53013, N'Funder did not enter PendingReview.', 1;

    DECLARE @FunderPendingRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_Funders WHERE Id = @FunderId);
    DECLARE @FunderReviewKey BINARY(32) = HASHBYTES('SHA2_256', N'funder-review-' + @Suffix);
    DECLARE @FunderReviewHash BINARY(32) = HASHBYTES('SHA2_256', N'funder-review-body-' + @Suffix);
    DECLARE @FunderReview TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), Completeness DECIMAL(5,2),
        FunderPublicId UNIQUEIDENTIFIER, ContentVersion INT, PublicationStatus TINYINT,
        SubmittedAtUtc DATETIME2(3), PublishedAtUtc DATETIME2(3), ReviewedAtUtc DATETIME2(3),
        ReviewedByUserPublicId UNIQUEIDENTIFIER, RejectionReason NVARCHAR(1000),
        RowVersion BINARY(8), WasReplay BIT
    );
    INSERT INTO @FunderReview
    EXEC dbo.FundingPlatform_usp_Funder_AdminReview
        @AdminUserPublicId = @SuperAdminPublicId, @FunderPublicId = @FunderPublicId,
        @ExpectedRowVersion = @FunderPendingRowVersion, @Decision = 2,
        @IdempotencyKeyHash = @FunderReviewKey, @RequestHash = @FunderReviewHash;
    IF NOT EXISTS
       (SELECT 1 FROM @FunderReview WHERE Succeeded = 1 AND Code = N'published'
                                       AND PublicationStatus = 2 AND ReviewedByUserPublicId = @SuperAdminPublicId)
        THROW 53014, N'Funder approval failed.', 1;
    DECLARE @FunderPublishedRowVersion BINARY(8) = (SELECT TOP (1) RowVersion FROM @FunderReview);
    DECLARE @FunderPublishedAt DATETIME2(3) = (SELECT TOP (1) PublishedAtUtc FROM @FunderReview);
    DECLARE @FunderReviewedAt DATETIME2(3) = (SELECT TOP (1) ReviewedAtUtc FROM @FunderReview);
    IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders
                   WHERE Id = @FunderId AND PublicationStatus = 2 AND IsActive = 1)
        THROW 53015, N'Published funder is not visible through fail-closed predicate.', 1;
    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_FunderAliases
        WHERE FunderId = @FunderId AND IsActive = 1) < 2
        THROW 53046, N'Published funder aliases are missing from the public aggregate.', 1;
    EXEC dbo.FundingPlatform_usp_Funder_Public_GetBySlug @Slug = @FunderSlug;

    /* Replay an old Update after later transitions: response must remain generation 2/Draft. */
    DELETE FROM @FunderWrite;
    INSERT INTO @FunderWrite
    EXEC dbo.FundingPlatform_usp_Funder_Update
        @AdminUserPublicId = @AdminPublicId, @FunderPublicId = @FunderPublicId,
        @ExpectedRowVersion = @FunderCreateRowVersion,
        @Name = @UpdatedFunderName,
        @Description = N'Funder actualizado y versionado.',
        @WebsiteUrl = N'https://funder.example.invalid', @CountryId = @CountryId,
        @AliasesJson = N'[{"alias":"Alias editorial"}]',
        @IdempotencyKeyHash = @FunderUpdateKey, @RequestHash = @FunderUpdateHash;
    IF NOT EXISTS
       (SELECT 1 FROM @FunderWrite WHERE Succeeded = 1 AND WasReplay = 1
                                      AND ContentVersion = 2 AND PublicationStatus = 0
                                      AND RowVersion = @FunderUpdateRowVersion)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders
                      WHERE Id = @FunderId AND PublicationStatus = 2)
        THROW 53016, N'Historical Funder Update replay mixed aggregate generations.', 1;
    DELETE FROM @FunderWrite;
    INSERT INTO @FunderWrite
    EXEC dbo.FundingPlatform_usp_Funder_Update
        @AdminUserPublicId = @AdminPublicId, @FunderPublicId = @FunderPublicId,
        @ExpectedRowVersion = @FunderCreateRowVersion, @Name = @UpdatedFunderName,
        @Description = N'Different request body.',
        @WebsiteUrl = N'https://funder.example.invalid', @CountryId = @CountryId,
        @AliasesJson = N'[]', @IdempotencyKeyHash = @FunderUpdateKey,
        @RequestHash = @FunderStaleHash;
    IF NOT EXISTS (SELECT 1 FROM @FunderWrite
                   WHERE Succeeded = 0 AND Code = N'idempotency-conflict')
        THROW 53045, N'Funder idempotency key reuse with a different request was accepted.', 1;

    DECLARE @CountryIds dbo.FundingPlatform_SmallIntIdList;
    DECLARE @RegionIds dbo.FundingPlatform_IntIdList;
    DECLARE @CategoryIds dbo.FundingPlatform_IntIdList;
    DECLARE @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList;
    DECLARE @ProjectTypeIds dbo.FundingPlatform_IntIdList;
    INSERT INTO @CountryIds VALUES (@CountryId);
    INSERT INTO @RegionIds VALUES (@RegionId);
    INSERT INTO @CategoryIds VALUES (@CategoryId);
    INSERT INTO @BeneficiaryTypeIds VALUES (@BeneficiaryTypeId);
    INSERT INTO @ProjectTypeIds VALUES (@ProjectTypeId);

    DECLARE @OpportunitySlug NVARCHAR(320) = N'fase6-opportunity-' + @Suffix;
    DECLARE @SourceItemKeyHash BINARY(32) = HASHBYTES('SHA2_256', N'manual-source-' + @Suffix);
    DECLARE @SourceUrl NVARCHAR(2048) = N'https://source.example.invalid/fase6/' + @Suffix;
    DECLARE @SourceUrlHash BINARY(32) = HASHBYTES('SHA2_256', @SourceUrl);
    DECLARE @ManualExternalId NVARCHAR(250) = N'manual-' + @Suffix;
    DECLARE @OpportunitySnapshot1 NVARCHAR(MAX) =
        N'{"title":"Fondo FASE 6","contentVersion":1}';
    DECLARE @OpportunityHash1 BINARY(32) =
        HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @OpportunitySnapshot1));
    DECLARE @FunderLinksJson NVARCHAR(MAX) =
        N'[{"funderPublicId":"' + CONVERT(NVARCHAR(36), @FunderPublicId) + N'","role":1}]';
    DECLARE @OpportunityCreateKey BINARY(32) = HASHBYTES('SHA2_256', N'opp-create-' + @Suffix);
    DECLARE @OpportunityCreateHash BINARY(32) = HASHBYTES('SHA2_256', N'opp-create-body-' + @Suffix);
    DECLARE @OpportunityWrite TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), FundingOpportunityPublicId UNIQUEIDENTIFIER,
        ContentVersion INT, PublicationStatus TINYINT, RowVersion BINARY(8), WasReplay BIT
    );
    INSERT INTO @OpportunityWrite
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Create
        @AdminUserPublicId = @AdminPublicId, @Slug = @OpportunitySlug,
        @Title = N'Fondo FASE 6', @Description = N'Fondo con evidencia editorial.',
        @Summary = N'Resumen público', @SponsorName = @UpdatedFunderName,
        @ApplicationUrl = N'https://apply.example.invalid', @IssuerCountryId = @CountryId,
        @FundingTypeId = @FundingTypeId, @Currency = 'USD', @MinAmount = 1000,
        @MaxAmount = 5000, @AmountStatus = 1, @OpenDate = '2027-01-01',
        @CloseDate = '2027-12-31', @DeadlineType = 1, @DeadlinePrecision = 1,
        @EligibilityDescription = N'ONG activas.', @Requirements = N'Formulario oficial.',
        @Objectives = N'Financiar impacto social.', @GeographicScope = 1,
        @RemoteApplication = 1, @LastVerifiedAtUtc = NULL, @DataQualityScore = 90,
        @FundingSourceId = @ManualSourceId, @ExternalId = @ManualExternalId,
        @SourceItemKeyHash = @SourceItemKeyHash, @SourceUrl = @SourceUrl,
        @CanonicalUrlHash = @SourceUrlHash,
        @SnapshotJson = @OpportunitySnapshot1, @ContentHash = @OpportunityHash1,
        @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds, @FunderLinksJson = @FunderLinksJson,
        @EvidenceJson = N'[{"fieldPath":"/editorialNote","valueJson":{"value":"retain","status":"known"},"evidenceText":"Manual provenance","isManualLock":true}]',
        @IdempotencyKeyHash = @OpportunityCreateKey,
        @RequestHash = @OpportunityCreateHash;
    IF NOT EXISTS
       (SELECT 1 FROM @OpportunityWrite WHERE Succeeded = 1 AND Code = N'created'
                                           AND ContentVersion = 1 AND PublicationStatus = 0)
        THROW 53017, N'Funding opportunity creation failed.', 1;

    DECLARE @OpportunityPublicId UNIQUEIDENTIFIER =
        (SELECT TOP (1) FundingOpportunityPublicId FROM @OpportunityWrite);
    DECLARE @OpportunityId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId = @OpportunityPublicId);
    DECLARE @OpportunityCreateRowVersion BINARY(8) =
        (SELECT TOP (1) RowVersion FROM @OpportunityWrite);
    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunityVersions
        WHERE FundingOpportunityId = @OpportunityId) <> 1
       OR (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingFieldEvidence
           WHERE FundingOpportunityId = @OpportunityId AND IsSelected = 1 AND IsManualLock = 1
             AND FieldPath IN (N'/title', N'/description', N'/eligibilityDescription',
                               N'/closeDate', N'/sponsorName')) <> 5
       OR (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunityFunders
           WHERE FundingOpportunityId = @OpportunityId AND IsActive = 1 AND Role = 1) <> 1
        THROW 53018, N'Opportunity versions, evidence or canonical funder relation are incomplete.', 1;
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
               WHERE Id = @OpportunityId AND PublicationStatus = 2 AND IsActive = 1)
        THROW 53019, N'A draft opportunity was exposed by the public predicate.', 1;
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Public_GetBySlug @Slug = @OpportunitySlug;
    EXEC dbo.FundingPlatform_usp_Funder_Public_GetBySlug @Slug = @FunderSlug;

    /* Duplicate funder entries must produce a stable business outcome, not an FK/PK exception. */
    DECLARE @DuplicateFunderLinks NVARCHAR(MAX) =
        N'[{"funderPublicId":"' + CONVERT(NVARCHAR(36), @FunderPublicId) +
        N'","role":1},{"funderPublicId":"' + CONVERT(NVARCHAR(36), @FunderPublicId) +
        N'","role":2}]';
    DECLARE @DuplicateSlug NVARCHAR(320) = N'duplicate-funder-' + @Suffix;
    DECLARE @DuplicateSourceKey BINARY(32) = HASHBYTES('SHA2_256', N'duplicate-funder-' + @Suffix);
    DECLARE @DuplicateContentHash BINARY(32) = HASHBYTES('SHA2_256', N'invalid-duplicate');
    DECLARE @DuplicateKey BINARY(32) = HASHBYTES('SHA2_256', N'duplicate-key-' + @Suffix);
    DECLARE @DuplicateHash BINARY(32) = HASHBYTES('SHA2_256', N'duplicate-body-' + @Suffix);
    DELETE FROM @OpportunityWrite;
    INSERT INTO @OpportunityWrite
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Create
        @AdminUserPublicId = @AdminPublicId, @Slug = @DuplicateSlug,
        @Title = N'Invalid duplicate funder', @SponsorName = N'Invalid sponsor',
        @AmountStatus = 0, @CloseDate = '2027-12-31', @DeadlineType = 1,
        @DeadlinePrecision = 1, @GeographicScope = 1, @RemoteApplication = 1,
        @DataQualityScore = 10, @FundingSourceId = @ManualSourceId,
        @SourceItemKeyHash = @DuplicateSourceKey,
        @SourceUrl = N'https://source.example.invalid/invalid',
        @SnapshotJson = N'{"invalid":true}',
        @ContentHash = @DuplicateContentHash,
        @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds, @FunderLinksJson = @DuplicateFunderLinks,
        @IdempotencyKeyHash = @DuplicateKey,
        @RequestHash = @DuplicateHash;
    IF NOT EXISTS (SELECT 1 FROM @OpportunityWrite
                   WHERE Succeeded = 0 AND Code = N'invalid-document')
        THROW 53020, N'Duplicate opportunity funder roles were not rejected safely.', 1;

    /* A manual lock stages external changes durably and preserves canonical/source values. */
    DECLARE @StageResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), FundingOpportunityPublicId UNIQUEIDENTIFIER,
        ContentVersion INT, PublicationStatus TINYINT, RowVersion BINARY(8),
        StagedRevisionPublicId UNIQUEIDENTIFIER
    );
    DECLARE @LockedCandidateJson NVARCHAR(MAX) = N'{"title":"Parser candidate under lock"}';
    DECLARE @LockedCandidateHash BINARY(32) =
        HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @LockedCandidateJson));
    DECLARE @ExternalChangeId NVARCHAR(250) = N'external-change-' + @Suffix;
    DECLARE @ParserCanonicalHash BINARY(32) = HASHBYTES('SHA2_256', N'parser-change');
    INSERT INTO @StageResult
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_StageExternal
        @FundingSourceId = @ManualSourceId, @ExternalId = @ExternalChangeId,
        @SourceItemKeyHash = @SourceItemKeyHash,
        @SourceUrl = N'https://source.example.invalid/parser-change',
        @CanonicalUrlHash = @ParserCanonicalHash,
        @ObservedAtUtc = NULL, @Slug = @OpportunitySlug,
        @Title = N'Parser candidate under lock', @Description = N'External change',
        @SponsorName = N'External sponsor', @AmountStatus = 0,
        @CloseDate = '2028-01-31', @DeadlineType = 1, @DeadlinePrecision = 1,
        @DataQualityScore = 80, @SnapshotJson = @LockedCandidateJson,
        @ContentHash = @LockedCandidateHash;
    IF NOT EXISTS
       (SELECT 1 FROM @StageResult WHERE Succeeded = 1 AND Code = N'manual-lock-protected'
                                       AND StagedRevisionPublicId IS NOT NULL)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
                      WHERE Id = @OpportunityId AND Title = N'Fondo FASE 6'
                        AND ContentVersion = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks
                      WHERE FundingOpportunityId = @OpportunityId AND IsPrimary = 1
                        AND SourceUrl = @SourceUrl)
        THROW 53021, N'Manual evidence lock did not protect the canonical opportunity.', 1;

    /* Update ETag then successful replacement of dimensions and selected evidence. */
    DECLARE @OpportunitySnapshot2 NVARCHAR(MAX) =
        N'{"title":"Fondo FASE 6 actualizado","contentVersion":2}';
    DECLARE @OpportunityHash2 BINARY(32) =
        HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @OpportunitySnapshot2));
    DECLARE @OpportunityStaleKey BINARY(32) = HASHBYTES('SHA2_256', N'opp-stale-' + @Suffix);
    DECLARE @OpportunityStaleHash BINARY(32) = HASHBYTES('SHA2_256', N'opp-stale-body-' + @Suffix);
    DECLARE @CollisionExternalId NVARCHAR(250) = N'collision-' + @Suffix;
    DECLARE @CollisionSourceKey BINARY(32) = HASHBYTES('SHA2_256', N'collision-source-' + @Suffix);
    INSERT INTO dbo.FundingPlatform_FundingOpportunitySourceLinks
        (FundingOpportunityId, FundingSourceId, ExternalId, SourceItemKeyHash,
         SourceUrl, CanonicalUrlHash, FirstSeenAtUtc, LastSeenAtUtc, IsPrimary, IsActive)
    VALUES (@OpportunityId, @ManualSourceId, @CollisionExternalId, @CollisionSourceKey,
            N'https://source.example.invalid/collision',
            HASHBYTES('SHA2_256', N'collision-url'), SYSUTCDATETIME(), SYSUTCDATETIME(), 0, 1);
    DELETE FROM @OpportunityWrite;
    INSERT INTO @OpportunityWrite
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Update
        @AdminUserPublicId = @AdminPublicId,
        @FundingOpportunityPublicId = @OpportunityPublicId,
        @ExpectedRowVersion = @OpportunityCreateRowVersion,
        @Title = N'Fondo FASE 6 actualizado', @Description = N'Descripción actualizada.',
        @Summary = N'Resumen actualizado', @SponsorName = @UpdatedFunderName,
        @ApplicationUrl = N'https://apply.example.invalid', @IssuerCountryId = @CountryId,
        @FundingTypeId = @FundingTypeId, @Currency = 'USD', @MinAmount = 1000,
        @MaxAmount = 7000, @AmountStatus = 1, @OpenDate = '2027-01-01',
        @CloseDate = '2027-12-31', @DeadlineType = 1, @DeadlinePrecision = 1,
        @EligibilityDescription = N'ONG activas.', @Requirements = N'Formulario oficial.',
        @Objectives = N'Impacto actualizado.', @GeographicScope = 1,
        @RemoteApplication = 1, @DataQualityScore = 95,
        @FundingSourceId = @ManualSourceId, @ExternalId = @CollisionExternalId,
        @SourceItemKeyHash = @SourceItemKeyHash, @SourceUrl = @SourceUrl,
        @CanonicalUrlHash = @SourceUrlHash,
        @SnapshotJson = @OpportunitySnapshot2, @ContentHash = @OpportunityHash2,
        @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds, @FunderLinksJson = @FunderLinksJson,
        @EvidenceJson = N'[]',
        @IdempotencyKeyHash = @OpportunityStaleKey, @RequestHash = @OpportunityStaleHash;
    IF NOT EXISTS (SELECT 1 FROM @OpportunityWrite
                   WHERE Succeeded = 0 AND Code = N'source-link-conflict')
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
                      WHERE Id = @OpportunityId AND ContentVersion = 1
                        AND RowVersion = @OpportunityCreateRowVersion)
        THROW 53047, N'Same-opportunity ExternalId collision was not a stable business outcome.', 1;

    SET @OpportunityStaleKey = HASHBYTES('SHA2_256', N'opp-etag-stale-' + @Suffix);
    SET @OpportunityStaleHash = HASHBYTES('SHA2_256', N'opp-etag-stale-body-' + @Suffix);
    DELETE FROM @OpportunityWrite;
    INSERT INTO @OpportunityWrite
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Update
        @AdminUserPublicId = @AdminPublicId,
        @FundingOpportunityPublicId = @OpportunityPublicId,
        @ExpectedRowVersion = 0x0000000000000000,
        @Title = N'Fondo FASE 6 actualizado', @Description = N'Descripción actualizada.',
        @Summary = N'Resumen actualizado', @SponsorName = @UpdatedFunderName,
        @ApplicationUrl = N'https://apply.example.invalid', @IssuerCountryId = @CountryId,
        @FundingTypeId = @FundingTypeId, @Currency = 'USD', @MinAmount = 1000,
        @MaxAmount = 7000, @AmountStatus = 1, @OpenDate = '2027-01-01',
        @CloseDate = '2027-12-31', @DeadlineType = 1, @DeadlinePrecision = 1,
        @EligibilityDescription = N'ONG activas.', @Requirements = N'Formulario oficial.',
        @Objectives = N'Impacto actualizado.', @GeographicScope = 1,
        @RemoteApplication = 1, @DataQualityScore = 95,
        @FundingSourceId = @ManualSourceId, @ExternalId = @ManualExternalId,
        @SourceItemKeyHash = @SourceItemKeyHash, @SourceUrl = @SourceUrl,
        @CanonicalUrlHash = @SourceUrlHash,
        @SnapshotJson = @OpportunitySnapshot2, @ContentHash = @OpportunityHash2,
        @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds, @FunderLinksJson = @FunderLinksJson,
        @EvidenceJson = N'[]',
        @IdempotencyKeyHash = @OpportunityStaleKey,
        @RequestHash = @OpportunityStaleHash;
    IF NOT EXISTS (SELECT 1 FROM @OpportunityWrite WHERE Succeeded = 0 AND Code = N'etag-conflict')
        THROW 53022, N'Opportunity stale ETag was accepted.', 1;

    DECLARE @OpportunityUpdateKey BINARY(32) = HASHBYTES('SHA2_256', N'opp-update-' + @Suffix);
    DECLARE @OpportunityUpdateHash BINARY(32) = HASHBYTES('SHA2_256', N'opp-update-body-' + @Suffix);
    DELETE FROM @OpportunityWrite;
    INSERT INTO @OpportunityWrite
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Update
        @AdminUserPublicId = @AdminPublicId,
        @FundingOpportunityPublicId = @OpportunityPublicId,
        @ExpectedRowVersion = @OpportunityCreateRowVersion,
        @Title = N'Fondo FASE 6 actualizado', @Description = N'Descripción actualizada.',
        @Summary = N'Resumen actualizado', @SponsorName = @UpdatedFunderName,
        @ApplicationUrl = N'https://apply.example.invalid', @IssuerCountryId = @CountryId,
        @FundingTypeId = @FundingTypeId, @Currency = 'USD', @MinAmount = 1000,
        @MaxAmount = 7000, @AmountStatus = 1, @OpenDate = '2027-01-01',
        @CloseDate = '2027-12-31', @DeadlineType = 1, @DeadlinePrecision = 1,
        @EligibilityDescription = N'ONG activas.', @Requirements = N'Formulario oficial.',
        @Objectives = N'Impacto actualizado.', @GeographicScope = 1,
        @RemoteApplication = 1, @DataQualityScore = 95,
        @FundingSourceId = @ManualSourceId, @ExternalId = @ManualExternalId,
        @SourceItemKeyHash = @SourceItemKeyHash, @SourceUrl = @SourceUrl,
        @CanonicalUrlHash = @SourceUrlHash,
        @SnapshotJson = @OpportunitySnapshot2, @ContentHash = @OpportunityHash2,
        @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds, @FunderLinksJson = @FunderLinksJson,
        @EvidenceJson = N'[]', @IdempotencyKeyHash = @OpportunityUpdateKey,
        @RequestHash = @OpportunityUpdateHash;
    IF NOT EXISTS
       (SELECT 1 FROM @OpportunityWrite WHERE Succeeded = 1 AND Code = N'updated'
                                           AND ContentVersion = 2 AND PublicationStatus = 0)
        THROW 53023, N'Opportunity update/versioning failed.', 1;
    DECLARE @OpportunityUpdateRowVersion BINARY(8) =
        (SELECT TOP (1) RowVersion FROM @OpportunityWrite);
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_FundingFieldEvidence
        WHERE FundingOpportunityId = @OpportunityId AND FieldPath = N'/editorialNote'
          AND IsSelected = 1 AND IsManualLock = 1
          AND JSON_VALUE(ValueJson, '$.value') = N'retain')
        THROW 53049, N'An unaddressed evidence path was lost during scalar update.', 1;

    DECLARE @OpportunityResultCode NVARCHAR(50), @OpportunityCompleteness DECIMAL(5,2);
    DECLARE @OpportunityRequestKey BINARY(32) = HASHBYTES('SHA2_256', N'opp-request-' + @Suffix);
    DECLARE @OpportunityRequestHash BINARY(32) = HASHBYTES('SHA2_256', N'opp-request-body-' + @Suffix);
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_RequestPublication
        @AdminUserPublicId = @AdminPublicId,
        @FundingOpportunityPublicId = @OpportunityPublicId,
        @ExpectedRowVersion = @OpportunityUpdateRowVersion,
        @IdempotencyKeyHash = @OpportunityRequestKey, @RequestHash = @OpportunityRequestHash,
        @ResultCode = @OpportunityResultCode OUTPUT,
        @ResultCompleteness = @OpportunityCompleteness OUTPUT;
    IF @OpportunityResultCode <> N'review-requested' OR @OpportunityCompleteness <> 100
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
                      WHERE Id = @OpportunityId AND PublicationStatus = 1 AND SubmittedAtUtc IS NOT NULL)
        THROW 53024, N'Opportunity did not enter PendingReview.', 1;

    DECLARE @OpportunityPendingRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_FundingOpportunities WHERE Id = @OpportunityId);
    DECLARE @OpportunityReviewKey BINARY(32) = HASHBYTES('SHA2_256', N'opp-review-' + @Suffix);
    DECLARE @OpportunityReviewHash BINARY(32) = HASHBYTES('SHA2_256', N'opp-review-body-' + @Suffix);
    DECLARE @OpportunityReview TABLE
    (
        Succeeded BIT, Code NVARCHAR(50), Completeness DECIMAL(5,2),
        FundingOpportunityPublicId UNIQUEIDENTIFIER, ContentVersion INT,
        PublicationStatus TINYINT, SubmittedAtUtc DATETIME2(3), PublishedAtUtc DATETIME2(3),
        ReviewedAtUtc DATETIME2(3), ReviewedByUserPublicId UNIQUEIDENTIFIER,
        RejectionReason NVARCHAR(1000), RowVersion BINARY(8), WasReplay BIT
    );
    INSERT INTO @OpportunityReview
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_AdminReview
        @AdminUserPublicId = @SuperAdminPublicId,
        @FundingOpportunityPublicId = @OpportunityPublicId,
        @ExpectedRowVersion = @OpportunityPendingRowVersion, @Decision = 2,
        @IdempotencyKeyHash = @OpportunityReviewKey, @RequestHash = @OpportunityReviewHash;
    IF NOT EXISTS
       (SELECT 1 FROM @OpportunityReview WHERE Succeeded = 1 AND Code = N'published'
                                            AND PublicationStatus = 2
                                            AND ReviewedByUserPublicId = @SuperAdminPublicId)
        THROW 53025, N'Opportunity approval failed.', 1;
    DECLARE @OpportunityPublishedRowVersion BINARY(8) =
        (SELECT TOP (1) RowVersion FROM @OpportunityReview);
    DECLARE @OpportunityPublishedAt DATETIME2(3) =
        (SELECT TOP (1) PublishedAtUtc FROM @OpportunityReview);
    DECLARE @OpportunityReviewedAt DATETIME2(3) =
        (SELECT TOP (1) ReviewedAtUtc FROM @OpportunityReview);
    IF NOT EXISTS
       (
           SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
           WHERE opportunities.Id = @OpportunityId
             AND opportunities.PublicationStatus = 2 AND opportunities.IsActive = 1
             AND EXISTS
                 (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
                  INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
                  WHERE links.FundingOpportunityId = opportunities.Id AND links.Role = 1
                    AND links.IsActive = 1 AND funders.PublicationStatus = 2 AND funders.IsActive = 1)
             AND EXISTS
                 (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
                  INNER JOIN dbo.FundingPlatform_FundingSources AS sources
                      ON sources.Id = links.FundingSourceId
                  WHERE links.FundingOpportunityId = opportunities.Id AND links.IsPrimary = 1
                    AND links.IsActive = 1 AND sources.IsEnabled = 1
                    AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL)
       )
        THROW 53026, N'Published opportunity is not visible through the public fail-closed predicate.', 1;
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Public_GetBySlug @Slug = @OpportunitySlug;
    EXEC dbo.FundingPlatform_usp_Funder_Public_GetBySlug @Slug = @FunderSlug;

    /* Published content and official source metadata remain immutable under external ingestion. */
    DECLARE @PublishedCandidateJson NVARCHAR(MAX) = N'{"title":"Unreviewed parser replacement"}';
    DECLARE @PublishedCandidateHash BINARY(32) =
        HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @PublishedCandidateJson));
    DECLARE @UnreviewedExternalId NVARCHAR(250) = N'unreviewed-' + @Suffix;
    DECLARE @UnreviewedCanonicalHash BINARY(32) = HASHBYTES('SHA2_256', N'malicious-change');
    DELETE FROM @StageResult;
    INSERT INTO @StageResult
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_StageExternal
        @FundingSourceId = @ManualSourceId, @ExternalId = @UnreviewedExternalId,
        @SourceItemKeyHash = @SourceItemKeyHash,
        @SourceUrl = N'https://malicious-change.example.invalid',
        @CanonicalUrlHash = @UnreviewedCanonicalHash,
        @ObservedAtUtc = NULL, @Slug = @OpportunitySlug,
        @Title = N'Unreviewed parser replacement', @Description = N'Unreviewed',
        @SponsorName = N'Unreviewed sponsor', @AmountStatus = 0,
        @CloseDate = '2029-01-31', @DeadlineType = 1, @DeadlinePrecision = 1,
        @DataQualityScore = 99, @SnapshotJson = @PublishedCandidateJson,
        @ContentHash = @PublishedCandidateHash;
    IF NOT EXISTS
       (SELECT 1 FROM @StageResult WHERE Succeeded = 1 AND Code = N'published-protected'
                                       AND StagedRevisionPublicId IS NOT NULL)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
                      WHERE Id = @OpportunityId AND Title = N'Fondo FASE 6 actualizado'
                        AND ContentVersion = 2 AND RowVersion = @OpportunityPublishedRowVersion)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks
                      WHERE FundingOpportunityId = @OpportunityId AND IsPrimary = 1
                        AND SourceUrl = @SourceUrl AND ExternalId = @ManualExternalId)
        THROW 53027, N'External ingestion overwrote a published canonical record or source link.', 1;
    DECLARE @PublishedCandidatePublicId UNIQUEIDENTIFIER =
        (SELECT TOP (1) StagedRevisionPublicId FROM @StageResult);
    DELETE FROM @StageResult;
    INSERT INTO @StageResult
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_StageExternal
        @FundingSourceId = @ManualSourceId, @ExternalId = @UnreviewedExternalId,
        @SourceItemKeyHash = @SourceItemKeyHash,
        @SourceUrl = N'https://malicious-change.example.invalid',
        @CanonicalUrlHash = @UnreviewedCanonicalHash,
        @ObservedAtUtc = NULL, @Slug = @OpportunitySlug,
        @Title = N'Unreviewed parser replacement', @Description = N'Unreviewed',
        @SponsorName = N'Unreviewed sponsor', @AmountStatus = 0,
        @CloseDate = '2029-01-31', @DeadlineType = 1, @DeadlinePrecision = 1,
        @DataQualityScore = 99, @SnapshotJson = @PublishedCandidateJson,
        @ContentHash = @PublishedCandidateHash;
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityStagedRevisions
        WHERE PublicId = @PublishedCandidatePublicId AND SeenCount = 2)
       OR (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunityStagedRevisions
           WHERE FundingOpportunityId = @OpportunityId AND ContentHash = @PublishedCandidateHash) <> 1
        THROW 53028, N'Candidate retry was not idempotent.', 1;

    DECLARE @SourceLastSeenBefore DATETIME2(3) =
        (SELECT LastSeenAtUtc FROM dbo.FundingPlatform_FundingOpportunitySourceLinks
         WHERE FundingOpportunityId = @OpportunityId AND FundingSourceId = @ManualSourceId
           AND SourceItemKeyHash = @SourceItemKeyHash);
    DECLARE @CandidateLastObservedBefore DATETIME2(3) =
        (SELECT LastObservedAtUtc
         FROM dbo.FundingPlatform_FundingOpportunityStagedRevisions
         WHERE PublicId = @PublishedCandidatePublicId);
    DECLARE @StaleObservedAtUtc DATETIME2(3) = DATEADD(DAY, -30, SYSUTCDATETIME());
    DELETE FROM @StageResult;
    INSERT INTO @StageResult
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_StageExternal
        @FundingSourceId = @ManualSourceId, @ExternalId = @UnreviewedExternalId,
        @SourceItemKeyHash = @SourceItemKeyHash,
        @SourceUrl = N'https://malicious-change.example.invalid',
        @CanonicalUrlHash = @UnreviewedCanonicalHash,
        @ObservedAtUtc = @StaleObservedAtUtc, @Slug = @OpportunitySlug,
        @Title = N'Unreviewed parser replacement', @Description = N'Unreviewed',
        @SponsorName = N'Unreviewed sponsor', @AmountStatus = 0,
        @CloseDate = '2029-01-31', @DeadlineType = 1, @DeadlinePrecision = 1,
        @DataQualityScore = 99, @SnapshotJson = @PublishedCandidateJson,
        @ContentHash = @PublishedCandidateHash;
    IF EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks
        WHERE FundingOpportunityId = @OpportunityId AND FundingSourceId = @ManualSourceId
          AND SourceItemKeyHash = @SourceItemKeyHash AND LastSeenAtUtc < @SourceLastSeenBefore)
       OR EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityStagedRevisions
        WHERE PublicId = @PublishedCandidatePublicId
          AND (LastObservedAtUtc < @CandidateLastObservedBefore OR SeenCount <> 3))
        THROW 53050, N'Out-of-order observations regressed ingestion timestamps.', 1;

    /* Replaying Update after publish returns its original Draft/version/RV without changing live state. */
    DELETE FROM @OpportunityWrite;
    INSERT INTO @OpportunityWrite
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Update
        @AdminUserPublicId = @AdminPublicId,
        @FundingOpportunityPublicId = @OpportunityPublicId,
        @ExpectedRowVersion = @OpportunityCreateRowVersion,
        @Title = N'Fondo FASE 6 actualizado', @Description = N'Descripción actualizada.',
        @Summary = N'Resumen actualizado', @SponsorName = @UpdatedFunderName,
        @ApplicationUrl = N'https://apply.example.invalid', @IssuerCountryId = @CountryId,
        @FundingTypeId = @FundingTypeId, @Currency = 'USD', @MinAmount = 1000,
        @MaxAmount = 7000, @AmountStatus = 1, @OpenDate = '2027-01-01',
        @CloseDate = '2027-12-31', @DeadlineType = 1, @DeadlinePrecision = 1,
        @EligibilityDescription = N'ONG activas.', @Requirements = N'Formulario oficial.',
        @Objectives = N'Impacto actualizado.', @GeographicScope = 1,
        @RemoteApplication = 1, @DataQualityScore = 95,
        @FundingSourceId = @ManualSourceId, @ExternalId = @ManualExternalId,
        @SourceItemKeyHash = @SourceItemKeyHash, @SourceUrl = @SourceUrl,
        @CanonicalUrlHash = @SourceUrlHash,
        @SnapshotJson = @OpportunitySnapshot2, @ContentHash = @OpportunityHash2,
        @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds, @FunderLinksJson = @FunderLinksJson,
        @EvidenceJson = N'[]', @IdempotencyKeyHash = @OpportunityUpdateKey,
        @RequestHash = @OpportunityUpdateHash;
    IF NOT EXISTS
       (SELECT 1 FROM @OpportunityWrite WHERE Succeeded = 1 AND WasReplay = 1
                                           AND ContentVersion = 2 AND PublicationStatus = 0
                                           AND RowVersion = @OpportunityUpdateRowVersion)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
                      WHERE Id = @OpportunityId AND PublicationStatus = 2)
        THROW 53029, N'Historical Opportunity Update replay mixed aggregate generations.', 1;

    /* Published correction withdraws public content, then follows the full review cycle again. */
    DECLARE @OpportunityCorrectionKey BINARY(32) =
        HASHBYTES('SHA2_256', N'opp-correction-' + @Suffix);
    DECLARE @OpportunityCorrectionHash BINARY(32) =
        HASHBYTES('SHA2_256', N'opp-correction-body-' + @Suffix);
    DELETE FROM @OpportunityReview;
    INSERT INTO @OpportunityReview
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_StartCorrection
        @AdminUserPublicId = @AdminPublicId,
        @FundingOpportunityPublicId = @OpportunityPublicId,
        @ExpectedRowVersion = @OpportunityPublishedRowVersion,
        @Reason = N'Correct editorial content',
        @IdempotencyKeyHash = @OpportunityCorrectionKey,
        @RequestHash = @OpportunityCorrectionHash;
    IF NOT EXISTS
       (SELECT 1 FROM @OpportunityReview
        WHERE Succeeded = 1 AND Code = N'correction-started'
          AND ContentVersion = 2 AND PublicationStatus = 0
          AND SubmittedAtUtc IS NULL AND PublishedAtUtc IS NULL
          AND ReviewedAtUtc IS NULL AND ReviewedByUserPublicId IS NULL)
       OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
        WHERE Id = @OpportunityId AND PublicationStatus = 0 AND IsActive = 1
          AND ContentVersion = 2 AND PublishedAtUtc IS NULL)
        THROW 53052, N'Published opportunity correction did not create a clean Draft.', 1;
    DECLARE @OpportunityCorrectionRowVersion BINARY(8) =
        (SELECT TOP (1) RowVersion FROM @OpportunityReview);
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Public_GetBySlug @Slug = @OpportunitySlug;

    DELETE FROM @OpportunityReview;
    INSERT INTO @OpportunityReview
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_StartCorrection
        @AdminUserPublicId = @AdminPublicId,
        @FundingOpportunityPublicId = @OpportunityPublicId,
        @ExpectedRowVersion = @OpportunityPublishedRowVersion,
        @Reason = N'Correct editorial content',
        @IdempotencyKeyHash = @OpportunityCorrectionKey,
        @RequestHash = @OpportunityCorrectionHash;
    IF NOT EXISTS
       (SELECT 1 FROM @OpportunityReview
        WHERE Succeeded = 1 AND WasReplay = 1 AND PublicationStatus = 0
          AND ContentVersion = 2 AND RowVersion = @OpportunityCorrectionRowVersion)
        THROW 53053, N'Opportunity correction retry was not idempotent.', 1;

    DECLARE @OpportunityCorrectionSnapshot NVARCHAR(MAX) =
        N'{"title":"Fondo FASE 6 corregido","contentVersion":3}';
    DECLARE @OpportunityCorrectionContentHash BINARY(32) =
        HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @OpportunityCorrectionSnapshot));
    DECLARE @OpportunityCorrectionUpdateKey BINARY(32) =
        HASHBYTES('SHA2_256', N'opp-correction-update-' + @Suffix);
    DECLARE @OpportunityCorrectionUpdateHash BINARY(32) =
        HASHBYTES('SHA2_256', N'opp-correction-update-body-' + @Suffix);
    DELETE FROM @OpportunityWrite;
    INSERT INTO @OpportunityWrite
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Update
        @AdminUserPublicId = @AdminPublicId,
        @FundingOpportunityPublicId = @OpportunityPublicId,
        @ExpectedRowVersion = @OpportunityCorrectionRowVersion,
        @Title = N'Fondo FASE 6 corregido', @Description = N'Descripción corregida.',
        @Summary = N'Resumen corregido', @SponsorName = @UpdatedFunderName,
        @ApplicationUrl = N'https://apply.example.invalid', @IssuerCountryId = @CountryId,
        @FundingTypeId = @FundingTypeId, @Currency = 'USD', @MinAmount = 1000,
        @MaxAmount = 7000, @AmountStatus = 1, @OpenDate = '2027-01-01',
        @CloseDate = '2027-12-31', @DeadlineType = 1, @DeadlinePrecision = 1,
        @EligibilityDescription = N'ONG activas.', @Requirements = N'Formulario oficial.',
        @Objectives = N'Impacto corregido.', @GeographicScope = 1,
        @RemoteApplication = 1, @DataQualityScore = 96,
        @FundingSourceId = @ManualSourceId, @ExternalId = @ManualExternalId,
        @SourceItemKeyHash = @SourceItemKeyHash, @SourceUrl = @SourceUrl,
        @CanonicalUrlHash = @SourceUrlHash,
        @SnapshotJson = @OpportunityCorrectionSnapshot,
        @ContentHash = @OpportunityCorrectionContentHash,
        @CountryIds = @CountryIds, @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds, @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds, @FunderLinksJson = @FunderLinksJson,
        @EvidenceJson = N'[]', @IdempotencyKeyHash = @OpportunityCorrectionUpdateKey,
        @RequestHash = @OpportunityCorrectionUpdateHash;
    IF NOT EXISTS
       (SELECT 1 FROM @OpportunityWrite
        WHERE Succeeded = 1 AND Code = N'updated'
          AND ContentVersion = 3 AND PublicationStatus = 0)
        THROW 53054, N'Opportunity correction could not be edited/versioned.', 1;
    DECLARE @OpportunityCorrectionUpdateRowVersion BINARY(8) =
        (SELECT TOP (1) RowVersion FROM @OpportunityWrite);

    /* A catalog deactivated after editing fails closed before review. */
    DECLARE @InactiveCatalogRequestKey BINARY(32) =
        HASHBYTES('SHA2_256', N'opp-inactive-catalog-request-' + @Suffix);
    DECLARE @InactiveCatalogRequestHash BINARY(32) =
        HASHBYTES('SHA2_256', N'opp-inactive-catalog-request-body-' + @Suffix);
    UPDATE dbo.FundingPlatform_FundingCategories SET IsActive = 0 WHERE Id = @CategoryId;
    SET @OpportunityResultCode = NULL; SET @OpportunityCompleteness = NULL;
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_RequestPublication
        @AdminUserPublicId = @AdminPublicId,
        @FundingOpportunityPublicId = @OpportunityPublicId,
        @ExpectedRowVersion = @OpportunityCorrectionUpdateRowVersion,
        @IdempotencyKeyHash = @InactiveCatalogRequestKey,
        @RequestHash = @InactiveCatalogRequestHash,
        @ResultCode = @OpportunityResultCode OUTPUT,
        @ResultCompleteness = @OpportunityCompleteness OUTPUT;
    IF @OpportunityResultCode <> N'opportunity-not-ready'
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
           WHERE Id = @OpportunityId AND PublicationStatus = 0
             AND RowVersion = @OpportunityCorrectionUpdateRowVersion)
        THROW 53062, N'RequestPublication accepted an inactive catalog relation.', 1;
    UPDATE dbo.FundingPlatform_FundingCategories SET IsActive = 1 WHERE Id = @CategoryId;

    DECLARE @OpportunityCorrectionRequestKey BINARY(32) =
        HASHBYTES('SHA2_256', N'opp-correction-request-' + @Suffix);
    DECLARE @OpportunityCorrectionRequestHash BINARY(32) =
        HASHBYTES('SHA2_256', N'opp-correction-request-body-' + @Suffix);
    SET @OpportunityResultCode = NULL; SET @OpportunityCompleteness = NULL;
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_RequestPublication
        @AdminUserPublicId = @AdminPublicId,
        @FundingOpportunityPublicId = @OpportunityPublicId,
        @ExpectedRowVersion = @OpportunityCorrectionUpdateRowVersion,
        @IdempotencyKeyHash = @OpportunityCorrectionRequestKey,
        @RequestHash = @OpportunityCorrectionRequestHash,
        @ResultCode = @OpportunityResultCode OUTPUT,
        @ResultCompleteness = @OpportunityCompleteness OUTPUT;
    IF @OpportunityResultCode <> N'review-requested' OR @OpportunityCompleteness <> 100
        THROW 53055, N'Corrected opportunity could not re-enter review.', 1;

    DECLARE @OpportunityCorrectionPendingRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_FundingOpportunities WHERE Id = @OpportunityId);
    DECLARE @OpportunityCorrectionReviewKey BINARY(32) =
        HASHBYTES('SHA2_256', N'opp-correction-review-' + @Suffix);
    DECLARE @OpportunityCorrectionReviewHash BINARY(32) =
        HASHBYTES('SHA2_256', N'opp-correction-review-body-' + @Suffix);
    DECLARE @InactiveCatalogReviewKey BINARY(32) =
        HASHBYTES('SHA2_256', N'opp-inactive-catalog-review-' + @Suffix);
    DECLARE @InactiveCatalogReviewHash BINARY(32) =
        HASHBYTES('SHA2_256', N'opp-inactive-catalog-review-body-' + @Suffix);
    UPDATE dbo.FundingPlatform_FundingTypes SET IsActive = 0 WHERE Id = @FundingTypeId;
    DELETE FROM @OpportunityReview;
    INSERT INTO @OpportunityReview
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_AdminReview
        @AdminUserPublicId = @SuperAdminPublicId,
        @FundingOpportunityPublicId = @OpportunityPublicId,
        @ExpectedRowVersion = @OpportunityCorrectionPendingRowVersion, @Decision = 2,
        @IdempotencyKeyHash = @InactiveCatalogReviewKey,
        @RequestHash = @InactiveCatalogReviewHash;
    IF NOT EXISTS
       (SELECT 1 FROM @OpportunityReview
        WHERE Succeeded = 0 AND Code = N'opportunity-not-ready'
          AND PublicationStatus = 1)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
           WHERE Id = @OpportunityId AND PublicationStatus = 1
             AND RowVersion = @OpportunityCorrectionPendingRowVersion)
        THROW 53063, N'AdminReview accepted an inactive catalog reference.', 1;
    UPDATE dbo.FundingPlatform_FundingTypes SET IsActive = 1 WHERE Id = @FundingTypeId;
    DELETE FROM @OpportunityReview;
    INSERT INTO @OpportunityReview
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_AdminReview
        @AdminUserPublicId = @SuperAdminPublicId,
        @FundingOpportunityPublicId = @OpportunityPublicId,
        @ExpectedRowVersion = @OpportunityCorrectionPendingRowVersion, @Decision = 2,
        @IdempotencyKeyHash = @OpportunityCorrectionReviewKey,
        @RequestHash = @OpportunityCorrectionReviewHash;
    IF NOT EXISTS
       (SELECT 1 FROM @OpportunityReview
        WHERE Succeeded = 1 AND Code = N'published'
          AND ContentVersion = 3 AND PublicationStatus = 2)
        THROW 53056, N'Corrected opportunity could not be republished.', 1;
    DECLARE @OpportunityCurrentPublishedRowVersion BINARY(8) =
        (SELECT TOP (1) RowVersion FROM @OpportunityReview);
    IF NOT EXISTS
       (SELECT 1
        FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs()
        WHERE FundingOpportunityId = @OpportunityId)
        THROW 53064, N'Active catalog references were rejected from public visibility.', 1;

    /* Every catalog dependency independently withdraws the published aggregate. */
    UPDATE dbo.FundingPlatform_Currencies SET IsActive = 0 WHERE Code = 'USD';
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs()
               WHERE FundingOpportunityId = @OpportunityId)
        THROW 53065, N'Inactive currency remained publicly eligible.', 1;
    UPDATE dbo.FundingPlatform_Currencies SET IsActive = 1 WHERE Code = 'USD';

    UPDATE dbo.FundingPlatform_FundingTypes SET IsActive = 0 WHERE Id = @FundingTypeId;
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs()
               WHERE FundingOpportunityId = @OpportunityId)
        THROW 53066, N'Inactive funding type remained publicly eligible.', 1;
    UPDATE dbo.FundingPlatform_FundingTypes SET IsActive = 1 WHERE Id = @FundingTypeId;

    UPDATE dbo.FundingPlatform_Countries SET IsActive = 0 WHERE Id = @CountryId;
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs()
               WHERE FundingOpportunityId = @OpportunityId)
        THROW 53067, N'Inactive issuer or eligible country remained publicly eligible.', 1;
    UPDATE dbo.FundingPlatform_Countries SET IsActive = 1 WHERE Id = @CountryId;

    UPDATE dbo.FundingPlatform_Regions SET IsActive = 0 WHERE Id = @RegionId;
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs()
               WHERE FundingOpportunityId = @OpportunityId)
        THROW 53068, N'Inactive region remained publicly eligible.', 1;
    UPDATE dbo.FundingPlatform_Regions SET IsActive = 1 WHERE Id = @RegionId;

    UPDATE dbo.FundingPlatform_FundingCategories SET IsActive = 0 WHERE Id = @CategoryId;
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs()
               WHERE FundingOpportunityId = @OpportunityId)
        THROW 53069, N'Inactive category remained publicly eligible.', 1;
    UPDATE dbo.FundingPlatform_FundingCategories SET IsActive = 1 WHERE Id = @CategoryId;

    UPDATE dbo.FundingPlatform_BeneficiaryTypes SET IsActive = 0 WHERE Id = @BeneficiaryTypeId;
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs()
               WHERE FundingOpportunityId = @OpportunityId)
        THROW 53070, N'Inactive beneficiary type remained publicly eligible.', 1;
    UPDATE dbo.FundingPlatform_BeneficiaryTypes SET IsActive = 1 WHERE Id = @BeneficiaryTypeId;

    UPDATE dbo.FundingPlatform_ProjectTypes SET IsActive = 0 WHERE Id = @ProjectTypeId;
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs()
               WHERE FundingOpportunityId = @OpportunityId)
        THROW 53071, N'Inactive project type remained publicly eligible.', 1;
    UPDATE dbo.FundingPlatform_ProjectTypes SET IsActive = 1 WHERE Id = @ProjectTypeId;

    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Public_GetBySlug @Slug = @OpportunitySlug;

    /* Deactivate, then replay the first approval and verify its original outcome exactly. */
    DECLARE @OpportunityDeactivateKey BINARY(32) = HASHBYTES('SHA2_256', N'opp-deactivate-' + @Suffix);
    DECLARE @OpportunityDeactivateHash BINARY(32) = HASHBYTES('SHA2_256', N'opp-deactivate-body-' + @Suffix);
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Deactivate
        @AdminUserPublicId = @AdminPublicId,
        @FundingOpportunityPublicId = @OpportunityPublicId,
        @ExpectedRowVersion = @OpportunityCurrentPublishedRowVersion,
        @Reason = N'Archive smoke', @IdempotencyKeyHash = @OpportunityDeactivateKey,
        @RequestHash = @OpportunityDeactivateHash;
    IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
                   WHERE Id = @OpportunityId AND PublicationStatus = 4 AND IsActive = 0)
        THROW 53030, N'Opportunity deactivate invariant failed.', 1;

    DELETE FROM @OpportunityReview;
    INSERT INTO @OpportunityReview
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_AdminReview
        @AdminUserPublicId = @SuperAdminPublicId,
        @FundingOpportunityPublicId = @OpportunityPublicId,
        @ExpectedRowVersion = @OpportunityPendingRowVersion, @Decision = 2,
        @IdempotencyKeyHash = @OpportunityReviewKey, @RequestHash = @OpportunityReviewHash;
    IF NOT EXISTS
       (SELECT 1 FROM @OpportunityReview WHERE Succeeded = 1 AND WasReplay = 1
                                            AND PublicationStatus = 2 AND ContentVersion = 2
                                            AND RowVersion = @OpportunityPublishedRowVersion
                                            AND PublishedAtUtc = @OpportunityPublishedAt
                                            AND ReviewedAtUtc = @OpportunityReviewedAt
                                            AND ReviewedByUserPublicId = @SuperAdminPublicId)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
                      WHERE Id = @OpportunityId AND PublicationStatus = 4 AND IsActive = 0)
        THROW 53031, N'Historical Opportunity approval replay mixed aggregate generations.', 1;

    /* Geography invariant: Explicit published above; Global is publishable without dimensions. */
    DECLARE @EmptyCountryIds dbo.FundingPlatform_SmallIntIdList;
    DECLARE @EmptyRegionIds dbo.FundingPlatform_IntIdList;
    DECLARE @GlobalSlug NVARCHAR(320) = N'global-opportunity-' + @Suffix;
    DECLARE @GlobalExternalId NVARCHAR(250) = N'global-' + @Suffix;
    DECLARE @GlobalSourceKey BINARY(32) = HASHBYTES('SHA2_256', N'global-source-' + @Suffix);
    DECLARE @GlobalSourceUrl NVARCHAR(2048) = N'https://source.example.invalid/global/' + @Suffix;
    DECLARE @GlobalSourceUrlHash BINARY(32) = HASHBYTES('SHA2_256', @GlobalSourceUrl);
    DECLARE @GlobalSnapshot1 NVARCHAR(MAX) = N'{"title":"Global FASE 6","version":1}';
    DECLARE @GlobalHash1 BINARY(32) =
        HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @GlobalSnapshot1));
    DECLARE @GlobalCreateKey BINARY(32) = HASHBYTES('SHA2_256', N'global-create-' + @Suffix);
    DECLARE @GlobalCreateHash BINARY(32) = HASHBYTES('SHA2_256', N'global-create-body-' + @Suffix);
    DELETE FROM @OpportunityWrite;
    INSERT INTO @OpportunityWrite
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Create
        @AdminUserPublicId = @AdminPublicId, @Slug = @GlobalSlug,
        @Title = N'Global FASE 6', @Description = N'Global description',
        @SponsorName = @UpdatedFunderName, @AmountStatus = 0,
        @CloseDate = '2028-12-31', @DeadlineType = 1, @DeadlinePrecision = 1,
        @EligibilityDescription = N'ONG globales.', @GeographicScope = 2,
        @RemoteApplication = 1, @DataQualityScore = 85,
        @FundingSourceId = @ManualSourceId, @ExternalId = @GlobalExternalId,
        @SourceItemKeyHash = @GlobalSourceKey, @SourceUrl = @GlobalSourceUrl,
        @CanonicalUrlHash = @GlobalSourceUrlHash,
        @SnapshotJson = @GlobalSnapshot1, @ContentHash = @GlobalHash1,
        @CountryIds = @EmptyCountryIds, @RegionIds = @EmptyRegionIds,
        @CategoryIds = @CategoryIds, @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds, @FunderLinksJson = @FunderLinksJson,
        @IdempotencyKeyHash = @GlobalCreateKey, @RequestHash = @GlobalCreateHash;
    IF NOT EXISTS (SELECT 1 FROM @OpportunityWrite
                   WHERE Succeeded = 1 AND Code = N'created' AND PublicationStatus = 0)
        THROW 53036, N'Global opportunity without country restrictions was rejected.', 1;
    DECLARE @GlobalPublicId UNIQUEIDENTIFIER =
        (SELECT TOP (1) FundingOpportunityPublicId FROM @OpportunityWrite);
    DECLARE @GlobalOpportunityId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId = @GlobalPublicId);
    DECLARE @GlobalCreateRowVersion BINARY(8) = (SELECT TOP (1) RowVersion FROM @OpportunityWrite);

    /* The same Update idempotency key is scoped per aggregate; it must not raise SQL 2601. */
    DECLARE @GlobalSnapshot2 NVARCHAR(MAX) = N'{"title":"Global FASE 6 updated","version":2}';
    DECLARE @GlobalHash2 BINARY(32) =
        HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @GlobalSnapshot2));
    DECLARE @GlobalUpdateHash BINARY(32) = HASHBYTES('SHA2_256', N'global-update-body-' + @Suffix);
    DELETE FROM @OpportunityWrite;
    INSERT INTO @OpportunityWrite
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Update
        @AdminUserPublicId = @AdminPublicId, @FundingOpportunityPublicId = @GlobalPublicId,
        @ExpectedRowVersion = @GlobalCreateRowVersion,
        @Title = N'Global FASE 6 updated', @Description = N'Global description updated',
        @SponsorName = @UpdatedFunderName, @AmountStatus = 0,
        @CloseDate = '2028-12-31', @DeadlineType = 1, @DeadlinePrecision = 1,
        @EligibilityDescription = N'ONG globales.', @GeographicScope = 2,
        @RemoteApplication = 1, @DataQualityScore = 86,
        @FundingSourceId = @ManualSourceId, @ExternalId = @GlobalExternalId,
        @SourceItemKeyHash = @GlobalSourceKey, @SourceUrl = @GlobalSourceUrl,
        @CanonicalUrlHash = @GlobalSourceUrlHash,
        @SnapshotJson = @GlobalSnapshot2, @ContentHash = @GlobalHash2,
        @CountryIds = @EmptyCountryIds, @RegionIds = @EmptyRegionIds,
        @CategoryIds = @CategoryIds, @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds, @FunderLinksJson = @FunderLinksJson,
        @IdempotencyKeyHash = @OpportunityUpdateKey, @RequestHash = @GlobalUpdateHash;
    IF NOT EXISTS (SELECT 1 FROM @OpportunityWrite
                   WHERE Succeeded = 1 AND Code = N'updated' AND ContentVersion = 2)
        THROW 53037, N'Aggregate-scoped idempotency or Global update failed.', 1;
    DECLARE @GlobalUpdateRowVersion BINARY(8) = (SELECT TOP (1) RowVersion FROM @OpportunityWrite);
    DECLARE @GlobalRequestKey BINARY(32) = HASHBYTES('SHA2_256', N'global-request-' + @Suffix);
    DECLARE @GlobalRequestHash BINARY(32) = HASHBYTES('SHA2_256', N'global-request-body-' + @Suffix);
    SET @OpportunityResultCode = NULL; SET @OpportunityCompleteness = NULL;
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_RequestPublication
        @AdminUserPublicId = @AdminPublicId,
        @FundingOpportunityPublicId = @GlobalPublicId,
        @ExpectedRowVersion = @GlobalUpdateRowVersion,
        @IdempotencyKeyHash = @GlobalRequestKey, @RequestHash = @GlobalRequestHash,
        @ResultCode = @OpportunityResultCode OUTPUT,
        @ResultCompleteness = @OpportunityCompleteness OUTPUT;
    IF @OpportunityResultCode <> N'review-requested' OR @OpportunityCompleteness <> 100
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
                      WHERE Id = @GlobalOpportunityId AND GeographicScope = 2
                        AND PublicationStatus = 1)
        THROW 53038, N'Global geography was not accepted for review.', 1;

    DECLARE @GlobalPendingRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_FundingOpportunities WHERE Id = @GlobalOpportunityId);
    DECLARE @GlobalRejectKey BINARY(32) = HASHBYTES('SHA2_256', N'global-reject-' + @Suffix);
    DECLARE @GlobalRejectHash BINARY(32) = HASHBYTES('SHA2_256', N'global-reject-body-' + @Suffix);
    DELETE FROM @OpportunityReview;
    INSERT INTO @OpportunityReview
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_AdminReview
        @AdminUserPublicId = @SuperAdminPublicId,
        @FundingOpportunityPublicId = @GlobalPublicId,
        @ExpectedRowVersion = @GlobalPendingRowVersion, @Decision = 3,
        @RejectionReason = N'Rejected by smoke review',
        @IdempotencyKeyHash = @GlobalRejectKey, @RequestHash = @GlobalRejectHash;
    IF NOT EXISTS (SELECT 1 FROM @OpportunityReview
                   WHERE Succeeded = 1 AND Code = N'rejected' AND PublicationStatus = 3
                     AND RejectionReason = N'Rejected by smoke review')
       OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
                  WHERE Id = @GlobalOpportunityId AND PublicationStatus = 2 AND IsActive = 1)
        THROW 53044, N'Rejected opportunity transition or fail-closed visibility failed.', 1;
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Public_GetBySlug @Slug = @GlobalSlug;

    /* Unknown has no dimensions by invariant, but remains fail-closed and cannot be published. */
    DECLARE @UnknownSlug NVARCHAR(320) = N'unknown-opportunity-' + @Suffix;
    DECLARE @UnknownExternalId NVARCHAR(250) = N'unknown-' + @Suffix;
    DECLARE @UnknownSourceKey BINARY(32) = HASHBYTES('SHA2_256', N'unknown-source-' + @Suffix);
    DECLARE @UnknownSourceUrl NVARCHAR(2048) = N'https://source.example.invalid/unknown/' + @Suffix;
    DECLARE @UnknownSourceUrlHash BINARY(32) = HASHBYTES('SHA2_256', @UnknownSourceUrl);
    DECLARE @UnknownSnapshot NVARCHAR(MAX) = N'{"title":"Unknown geography"}';
    DECLARE @UnknownContentHash BINARY(32) =
        HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @UnknownSnapshot));
    DECLARE @UnknownCreateKey BINARY(32) = HASHBYTES('SHA2_256', N'unknown-create-' + @Suffix);
    DECLARE @UnknownCreateHash BINARY(32) = HASHBYTES('SHA2_256', N'unknown-create-body-' + @Suffix);
    DELETE FROM @OpportunityWrite;
    INSERT INTO @OpportunityWrite
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_Create
        @AdminUserPublicId = @AdminPublicId, @Slug = @UnknownSlug,
        @Title = N'Unknown geography', @Description = N'Unknown description',
        @SponsorName = @UpdatedFunderName, @AmountStatus = 0,
        @CloseDate = '2028-12-31', @DeadlineType = 1, @DeadlinePrecision = 1,
        @EligibilityDescription = N'ONG por determinar.', @GeographicScope = 0,
        @RemoteApplication = 1, @DataQualityScore = 60,
        @FundingSourceId = @ManualSourceId, @ExternalId = @UnknownExternalId,
        @SourceItemKeyHash = @UnknownSourceKey, @SourceUrl = @UnknownSourceUrl,
        @CanonicalUrlHash = @UnknownSourceUrlHash,
        @SnapshotJson = @UnknownSnapshot, @ContentHash = @UnknownContentHash,
        @CountryIds = @EmptyCountryIds, @RegionIds = @EmptyRegionIds,
        @CategoryIds = @CategoryIds, @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds, @FunderLinksJson = @FunderLinksJson,
        @IdempotencyKeyHash = @UnknownCreateKey, @RequestHash = @UnknownCreateHash;
    IF NOT EXISTS (SELECT 1 FROM @OpportunityWrite WHERE Succeeded = 1 AND Code = N'created')
        THROW 53039, N'Unknown geography draft invariant failed.', 1;
    DECLARE @UnknownPublicId UNIQUEIDENTIFIER =
        (SELECT TOP (1) FundingOpportunityPublicId FROM @OpportunityWrite);
    DECLARE @UnknownOpportunityId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_FundingOpportunities WHERE PublicId = @UnknownPublicId);
    DECLARE @UnknownRowVersion BINARY(8) = (SELECT TOP (1) RowVersion FROM @OpportunityWrite);
    DECLARE @UnknownRequestKey BINARY(32) = HASHBYTES('SHA2_256', N'unknown-request-' + @Suffix);
    DECLARE @UnknownRequestHash BINARY(32) = HASHBYTES('SHA2_256', N'unknown-request-body-' + @Suffix);
    SET @OpportunityResultCode = NULL; SET @OpportunityCompleteness = NULL;
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_RequestPublication
        @AdminUserPublicId = @AdminPublicId,
        @FundingOpportunityPublicId = @UnknownPublicId,
        @ExpectedRowVersion = @UnknownRowVersion,
        @IdempotencyKeyHash = @UnknownRequestKey, @RequestHash = @UnknownRequestHash,
        @ResultCode = @OpportunityResultCode OUTPUT,
        @ResultCompleteness = @OpportunityCompleteness OUTPUT;
    IF @OpportunityResultCode <> N'opportunity-not-ready'
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
                      WHERE Id = @UnknownOpportunityId AND GeographicScope = 0
                        AND PublicationStatus = 0 AND IsActive = 1)
       OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents
                  WHERE FundingOpportunityId = @UnknownOpportunityId
                    AND ActionCode = N'RequestPublication')
        THROW 53040, N'Unknown geography was allowed into review/publication.', 1;

    /* External Draft A -> B -> A must create three auditable versions without key collision. */
    DECLARE @CycleSourceKey BINARY(32) = HASHBYTES('SHA2_256', N'cycle-source-' + @Suffix);
    DECLARE @CycleSlug NVARCHAR(320) = N'external-cycle-' + @Suffix;
    DECLARE @CycleA NVARCHAR(MAX) = N'{"title":"Cycle A"}';
    DECLARE @CycleB NVARCHAR(MAX) = N'{"title":"Cycle B"}';
    DECLARE @CycleAHash BINARY(32) = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @CycleA));
    DECLARE @CycleBHash BINARY(32) = HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @CycleB));
    DECLARE @CycleExternalId NVARCHAR(250) = N'cycle-' + @Suffix;
    DECLARE @CycleCanonicalA BINARY(32) = HASHBYTES('SHA2_256', N'cycle');
    DECLARE @CycleCanonicalB BINARY(32) = HASHBYTES('SHA2_256', N'cycle-b');
    DECLARE @CycleCanonicalAAgain BINARY(32) = HASHBYTES('SHA2_256', N'cycle-a-again');
    DELETE FROM @StageResult;
    INSERT INTO @StageResult
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_StageExternal
        @FundingSourceId = @ManualSourceId, @ExternalId = @CycleExternalId,
        @SourceItemKeyHash = @CycleSourceKey,
        @SourceUrl = N'https://source.example.invalid/cycle',
        @CanonicalUrlHash = @CycleCanonicalA, @ObservedAtUtc = NULL,
        @Slug = @CycleSlug, @Title = N'Cycle A', @Description = N'A',
        @SponsorName = N'Cycle sponsor', @AmountStatus = 0,
        @CloseDate = '2028-01-01', @DeadlineType = 1, @DeadlinePrecision = 1,
        @DataQualityScore = 50, @SnapshotJson = @CycleA, @ContentHash = @CycleAHash;
    DECLARE @CycleOpportunityPublicId UNIQUEIDENTIFIER =
        (SELECT TOP (1) FundingOpportunityPublicId FROM @StageResult);
    DECLARE @CycleOpportunityId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_FundingOpportunities
         WHERE PublicId = @CycleOpportunityPublicId);
    IF NOT EXISTS (SELECT 1 FROM @StageResult WHERE Code = N'draft-created')
        THROW 53032, N'External Draft A was not created.', 1;

    DELETE FROM @StageResult;
    INSERT INTO @StageResult
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_StageExternal
        @FundingSourceId = @ManualSourceId, @ExternalId = @CycleExternalId,
        @SourceItemKeyHash = @CycleSourceKey,
        @SourceUrl = N'https://source.example.invalid/cycle-b',
        @CanonicalUrlHash = @CycleCanonicalB, @ObservedAtUtc = NULL,
        @Slug = @CycleSlug, @Title = N'Cycle B', @Description = N'B',
        @SponsorName = N'Cycle sponsor', @AmountStatus = 0,
        @CloseDate = '2028-01-02', @DeadlineType = 1, @DeadlinePrecision = 1,
        @DataQualityScore = 51, @SnapshotJson = @CycleB, @ContentHash = @CycleBHash;
    IF NOT EXISTS (SELECT 1 FROM @StageResult WHERE Code = N'draft-updated' AND ContentVersion = 2)
        THROW 53033, N'External Draft B was not versioned.', 1;

    DELETE FROM @StageResult;
    INSERT INTO @StageResult
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_StageExternal
        @FundingSourceId = @ManualSourceId, @ExternalId = @CycleExternalId,
        @SourceItemKeyHash = @CycleSourceKey,
        @SourceUrl = N'https://source.example.invalid/cycle-a-again',
        @CanonicalUrlHash = @CycleCanonicalAAgain, @ObservedAtUtc = NULL,
        @Slug = @CycleSlug, @Title = N'Cycle A', @Description = N'A',
        @SponsorName = N'Cycle sponsor', @AmountStatus = 0,
        @CloseDate = '2028-01-01', @DeadlineType = 1, @DeadlinePrecision = 1,
        @DataQualityScore = 50, @SnapshotJson = @CycleA, @ContentHash = @CycleAHash;
    IF NOT EXISTS (SELECT 1 FROM @StageResult WHERE Code = N'draft-updated' AND ContentVersion = 3)
       OR (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunityVersions
           WHERE FundingOpportunityId = @CycleOpportunityId) <> 3
       OR (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents
           WHERE FundingOpportunityId = @CycleOpportunityId AND ActionCode = N'ExternalStage') <> 3
        THROW 53034, N'External A-B-A reversion was not independently versioned/audited.', 1;

    /* Canonical funder correction follows Published -> Draft -> edit -> review -> Published. */
    DECLARE @FunderCorrectionKey BINARY(32) =
        HASHBYTES('SHA2_256', N'funder-correction-' + @Suffix);
    DECLARE @FunderCorrectionHash BINARY(32) =
        HASHBYTES('SHA2_256', N'funder-correction-body-' + @Suffix);
    DELETE FROM @FunderReview;
    INSERT INTO @FunderReview
    EXEC dbo.FundingPlatform_usp_Funder_StartCorrection
        @AdminUserPublicId = @AdminPublicId, @FunderPublicId = @FunderPublicId,
        @ExpectedRowVersion = @FunderPublishedRowVersion,
        @Reason = N'Correct canonical funder',
        @IdempotencyKeyHash = @FunderCorrectionKey,
        @RequestHash = @FunderCorrectionHash;
    IF NOT EXISTS
       (SELECT 1 FROM @FunderReview
        WHERE Succeeded = 1 AND Code = N'correction-started'
          AND ContentVersion = 2 AND PublicationStatus = 0
          AND SubmittedAtUtc IS NULL AND PublishedAtUtc IS NULL
          AND ReviewedAtUtc IS NULL AND ReviewedByUserPublicId IS NULL)
       OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_Funders
        WHERE Id = @FunderId AND PublicationStatus = 0 AND IsActive = 1
          AND ContentVersion = 2 AND PublishedAtUtc IS NULL)
        THROW 53057, N'Published funder correction did not create a clean Draft.', 1;
    DECLARE @FunderCorrectionRowVersion BINARY(8) =
        (SELECT TOP (1) RowVersion FROM @FunderReview);
    EXEC dbo.FundingPlatform_usp_Funder_Public_GetBySlug @Slug = @FunderSlug;

    DELETE FROM @FunderReview;
    INSERT INTO @FunderReview
    EXEC dbo.FundingPlatform_usp_Funder_StartCorrection
        @AdminUserPublicId = @AdminPublicId, @FunderPublicId = @FunderPublicId,
        @ExpectedRowVersion = @FunderPublishedRowVersion,
        @Reason = N'Correct canonical funder',
        @IdempotencyKeyHash = @FunderCorrectionKey,
        @RequestHash = @FunderCorrectionHash;
    IF NOT EXISTS
       (SELECT 1 FROM @FunderReview
        WHERE Succeeded = 1 AND WasReplay = 1 AND PublicationStatus = 0
          AND ContentVersion = 2 AND RowVersion = @FunderCorrectionRowVersion)
        THROW 53058, N'Funder correction retry was not idempotent.', 1;

    DECLARE @FunderCorrectionUpdateKey BINARY(32) =
        HASHBYTES('SHA2_256', N'funder-correction-update-' + @Suffix);
    DECLARE @FunderCorrectionUpdateHash BINARY(32) =
        HASHBYTES('SHA2_256', N'funder-correction-update-body-' + @Suffix);
    DELETE FROM @FunderWrite;
    INSERT INTO @FunderWrite
    EXEC dbo.FundingPlatform_usp_Funder_Update
        @AdminUserPublicId = @AdminPublicId, @FunderPublicId = @FunderPublicId,
        @ExpectedRowVersion = @FunderCorrectionRowVersion,
        @Name = @UpdatedFunderName,
        @Description = N'Funder corregido y versionado.',
        @WebsiteUrl = N'https://funder.example.invalid', @CountryId = @CountryId,
        @AliasesJson = N'[{"alias":"Alias editorial corregido"}]',
        @IdempotencyKeyHash = @FunderCorrectionUpdateKey,
        @RequestHash = @FunderCorrectionUpdateHash;
    IF NOT EXISTS
       (SELECT 1 FROM @FunderWrite
        WHERE Succeeded = 1 AND Code = N'updated'
          AND ContentVersion = 3 AND PublicationStatus = 0)
        THROW 53059, N'Funder correction could not be edited/versioned.', 1;
    DECLARE @FunderCorrectionUpdateRowVersion BINARY(8) =
        (SELECT TOP (1) RowVersion FROM @FunderWrite);

    DECLARE @FunderCorrectionRequestKey BINARY(32) =
        HASHBYTES('SHA2_256', N'funder-correction-request-' + @Suffix);
    DECLARE @FunderCorrectionRequestHash BINARY(32) =
        HASHBYTES('SHA2_256', N'funder-correction-request-body-' + @Suffix);
    SET @FunderResultCode = NULL; SET @FunderCompleteness = NULL;
    EXEC dbo.FundingPlatform_usp_Funder_RequestPublication
        @AdminUserPublicId = @AdminPublicId, @FunderPublicId = @FunderPublicId,
        @ExpectedRowVersion = @FunderCorrectionUpdateRowVersion,
        @IdempotencyKeyHash = @FunderCorrectionRequestKey,
        @RequestHash = @FunderCorrectionRequestHash,
        @ResultCode = @FunderResultCode OUTPUT,
        @ResultCompleteness = @FunderCompleteness OUTPUT;
    IF @FunderResultCode <> N'review-requested' OR @FunderCompleteness <> 100
        THROW 53060, N'Corrected funder could not re-enter review.', 1;
    DECLARE @FunderCorrectionPendingRowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_Funders WHERE Id = @FunderId);
    DECLARE @FunderCorrectionReviewKey BINARY(32) =
        HASHBYTES('SHA2_256', N'funder-correction-review-' + @Suffix);
    DECLARE @FunderCorrectionReviewHash BINARY(32) =
        HASHBYTES('SHA2_256', N'funder-correction-review-body-' + @Suffix);
    DELETE FROM @FunderReview;
    INSERT INTO @FunderReview
    EXEC dbo.FundingPlatform_usp_Funder_AdminReview
        @AdminUserPublicId = @SuperAdminPublicId, @FunderPublicId = @FunderPublicId,
        @ExpectedRowVersion = @FunderCorrectionPendingRowVersion, @Decision = 2,
        @IdempotencyKeyHash = @FunderCorrectionReviewKey,
        @RequestHash = @FunderCorrectionReviewHash;
    IF NOT EXISTS
       (SELECT 1 FROM @FunderReview
        WHERE Succeeded = 1 AND Code = N'published'
          AND ContentVersion = 3 AND PublicationStatus = 2)
        THROW 53061, N'Corrected funder could not be republished.', 1;
    DECLARE @FunderCurrentPublishedRowVersion BINARY(8) =
        (SELECT TOP (1) RowVersion FROM @FunderReview);
    EXEC dbo.FundingPlatform_usp_Funder_Public_GetBySlug @Slug = @FunderSlug;

    DECLARE @FunderDeactivateKey BINARY(32) = HASHBYTES('SHA2_256', N'funder-deactivate-' + @Suffix);
    DECLARE @FunderDeactivateHash BINARY(32) = HASHBYTES('SHA2_256', N'funder-deactivate-body-' + @Suffix);
    EXEC dbo.FundingPlatform_usp_Funder_Deactivate
        @AdminUserPublicId = @AdminPublicId, @FunderPublicId = @FunderPublicId,
        @ExpectedRowVersion = @FunderCurrentPublishedRowVersion,
        @Reason = N'Archive smoke', @IdempotencyKeyHash = @FunderDeactivateKey,
        @RequestHash = @FunderDeactivateHash;
    IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders
                   WHERE Id = @FunderId AND PublicationStatus = 4 AND IsActive = 0)
       OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders
                  WHERE Id = @FunderId AND PublicationStatus = 2 AND IsActive = 1)
        THROW 53042, N'Funder deactivate/public fail-closed invariant failed.', 1;

    DELETE FROM @FunderReview;
    INSERT INTO @FunderReview
    EXEC dbo.FundingPlatform_usp_Funder_AdminReview
        @AdminUserPublicId = @SuperAdminPublicId, @FunderPublicId = @FunderPublicId,
        @ExpectedRowVersion = @FunderPendingRowVersion, @Decision = 2,
        @IdempotencyKeyHash = @FunderReviewKey, @RequestHash = @FunderReviewHash;
    IF NOT EXISTS
       (SELECT 1 FROM @FunderReview WHERE Succeeded = 1 AND WasReplay = 1
                                       AND PublicationStatus = 2 AND ContentVersion = 2
                                       AND RowVersion = @FunderPublishedRowVersion
                                       AND PublishedAtUtc = @FunderPublishedAt
                                       AND ReviewedAtUtc = @FunderReviewedAt
                                       AND ReviewedByUserPublicId = @SuperAdminPublicId)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders
                      WHERE Id = @FunderId AND PublicationStatus = 4 AND IsActive = 0)
        THROW 53043, N'Historical Funder approval replay mixed aggregate generations.', 1;

    /* Every business mutation event written by this fixture has an atomic outbox peer. */
    IF EXISTS
       (
           SELECT 1
           FROM dbo.FundingPlatform_FunderEditorialEvents AS events
           WHERE events.FunderId = @FunderId
             AND NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages AS outbox
                             WHERE outbox.MessageId = events.EventId)
       )
       OR EXISTS
       (
           SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents AS events
           WHERE events.FundingOpportunityId IN (@OpportunityId, @CycleOpportunityId)
             AND NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages AS outbox
                             WHERE outbox.MessageId = events.EventId)
       )
        THROW 53035, N'Editorial audit and outbox were not written atomically.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FundingPlatform_Smoke010;
    PRINT N'FASE 6 funder/editorial workflow smoke passed; fixture rolled back.';
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FundingPlatform_Smoke010;
    THROW;
END CATCH;
