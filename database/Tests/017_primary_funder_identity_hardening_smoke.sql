/* Transactional regression smoke for forward-only primary-funder identity hardening. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_FundingOpportunityFunderIdentityConflicts', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash', N'FN') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunity_EnsurePrimaryFunder', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunity_EnsurePrimaryFunder_Pre017', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunityFunderIdentityConflict_Record', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunityFunderIdentityConflict_AuditLegacy', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunityFunderIdentityConflict_AdminList', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge_Pre017', N'P') IS NULL
    THROW 53701, N'Primary-funder identity hardening objects are incomplete.', 1;

DECLARE @HelperDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunity_EnsurePrimaryFunder'));
DECLARE @LedgerDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunityFunderIdentityConflict_Record'));
DECLARE @AuditSinkDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge'));
IF CHARINDEX(N'FundingPlatform_fn_StrongHttpsIdentityUrlHash', COALESCE(@HelperDefinition, N'')) = 0
   OR CHARINDEX(N'Latin1_General_100_BIN2', COALESCE(@HelperDefinition, N'')) = 0
   OR CHARINDEX(N'FundingPlatform_usp_FundingOpportunityFunderIdentityConflict_Record',
                COALESCE(@HelperDefinition, N'')) = 0
   OR CHARINDEX(N'FundingOpportunityFunderIdentityConflictDetected',
                COALESCE(@LedgerDefinition, N'')) = 0
   OR CHARINDEX(N'OPENJSON(PayloadJson)', COALESCE(@AuditSinkDefinition, N'')) = 0
    THROW 53702, N'Strong identity, durable conflict audit, or safe event sink is not wired.', 1;

IF EXISTS
(
    SELECT 1
    FROM (VALUES
        (N'FundingPlatform_usp_FundingOpportunity_Public_List'),
        (N'FundingPlatform_usp_FundingOpportunity_Public_GetBySlug'),
        (N'FundingPlatform_usp_FundingOpportunity_RequestPublication'),
        (N'FundingPlatform_usp_FundingOpportunity_AdminReview')
    ) AS required(ProcedureName)
    LEFT JOIN sys.procedures AS procedures
        ON procedures.schema_id = SCHEMA_ID(N'dbo')
       AND procedures.name = required.ProcedureName
    WHERE procedures.object_id IS NULL
       OR CHARINDEX(N'FundingPlatform_ifn_FundingOpportunityActiveCatalogs',
                    COALESCE(OBJECT_DEFINITION(procedures.object_id), N'')) = 0
)
    THROW 53722, N'A public or publication-readiness path bypasses the fail-closed catalog guard.', 1;

IF EXISTS
(
    SELECT 1
    FROM sys.dm_exec_describe_first_result_set_for_object
         (OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunityFunderIdentityConflict_AdminList'), 0)
    WHERE LOWER(name) LIKE N'%url%'
       OR LOWER(name) LIKE N'%hash%'
       OR LOWER(name) LIKE N'%raw%'
       OR LOWER(name) LIKE N'%email%'
       OR LOWER(name) LIKE N'%blob%'
       OR LOWER(name) LIKE N'%token%'
       OR LOWER(name) LIKE N'%path%'
)
    THROW 53703, N'The administrative conflict queue exposes private identity material.', 1;

DECLARE @ValidIdentityHash BINARY(32) =
    dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash(N'https://identity.example.org/official');
IF @ValidIdentityHash IS NULL
   OR @ValidIdentityHash <>
      dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash(N'https://identity.example.org/official')
   OR @ValidIdentityHash =
      dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash(N'https://identity.example.org/Official')
   OR dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash(N'https://identity.example.org') IS NULL
   OR dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash(N'https://identity.example.org/') IS NULL
   OR dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash(N'https://identity.example.org') =
      dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash(N'https://identity.example.org/')
   OR dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash(N'HTTPS://identity.example.org/official') IS NOT NULL
   OR dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash(N'https://Identity.example.org/official') IS NOT NULL
   OR dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash(N'https://identity.example.org:443/official') IS NOT NULL
   OR dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash(N'https://identity.example.org/official?x=1') IS NOT NULL
   OR dbo.FundingPlatform_fn_StrongHttpsIdentityUrlHash
      (N'https://identity.example.org/' + NCHAR(0) + N'unsafe') IS NOT NULL
    THROW 53704, N'Strong HTTPS identity canonicalization is not exact and fail-closed.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke017;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @Suffix NVARCHAR(32) =
        REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'');
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @AdminPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @NoMfaPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @AdminEmail NVARCHAR(320) = N'phase7b-017-admin-' + @Suffix + N'@example.invalid';
    DECLARE @NoMfaEmail NVARCHAR(320) = N'phase7b-017-nomfa-' + @Suffix + N'@example.invalid';

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@AdminPublicId, @AdminEmail, UPPER(@AdminEmail), N'Phase 7B 017 administrator',
         N'not-a-credential', N'phase7b-017-admin', 1, 1, 2, N'es-CL'),
        (@NoMfaPublicId, @NoMfaEmail, UPPER(@NoMfaEmail), N'Phase 7B 017 no MFA',
         N'not-a-credential', N'phase7b-017-nomfa', 1, 0, 2, N'es-CL');

    DECLARE @AdminUserId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @AdminPublicId);
    DECLARE @NoMfaUserId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @NoMfaPublicId);
    DECLARE @AdminRoleId SMALLINT =
        (SELECT Id FROM dbo.FundingPlatform_Roles WHERE NormalizedName = N'ADMIN');
    DECLARE @ApiSourceId INT =
        (SELECT Id FROM dbo.FundingPlatform_FundingSources
         WHERE ProviderCode = N'grants-gov');
    DECLARE @CategoryId INT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_FundingCategories
         WHERE IsActive = 1 ORDER BY Id);
    IF @AdminRoleId IS NULL OR @ApiSourceId IS NULL OR @CategoryId IS NULL
        THROW 53705, N'Admin role, category, or governed source fixture is missing.', 1;
    INSERT INTO dbo.FundingPlatform_UserRoles (UserId, RoleId, GrantedByUserId)
    VALUES (@AdminUserId, @AdminRoleId, @AdminUserId),
           (@NoMfaUserId, @AdminRoleId, @AdminUserId);

    DECLARE @CollisionName NVARCHAR(300) = N'Identity collision ' + @Suffix;
    DECLARE @CollisionNormalizedName NVARCHAR(300) = UPPER(@CollisionName);
    DECLARE @CollisionUrl NVARCHAR(2048) =
        N'https://identity-' + LOWER(LEFT(@Suffix, 20)) + N'.example.org/official';
    DECLARE @MismatchUrl NVARCHAR(2048) =
        N'https://different-' + LOWER(LEFT(@Suffix, 20)) + N'.example.org/official';
    DECLARE @CuratedName NVARCHAR(300) = N'Curated primary ' + @Suffix;
    DECLARE @CuratedNormalizedName NVARCHAR(300) = UPPER(@CuratedName);
    DECLARE @InactiveName NVARCHAR(300) = N'Inactive legacy primary ' + @Suffix;
    DECLARE @InactiveNormalizedName NVARCHAR(300) = UPPER(@InactiveName);
    DECLARE @InactiveUrl NVARCHAR(2048) =
        N'https://inactive-' + LOWER(LEFT(@Suffix, 20)) + N'.example.org/official';
    DECLARE @CollisionFunderPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @CuratedFunderPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InactiveFunderPublicId UNIQUEIDENTIFIER = NEWID();

    INSERT INTO dbo.FundingPlatform_Funders
        (PublicId, Slug, Name, NormalizedName, WebsiteUrl, PublicationStatus,
         ContentVersion, IsActive, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@CollisionFunderPublicId, N'phase7b-017-collision-' + @Suffix,
         @CollisionName, @CollisionNormalizedName, @CollisionUrl,
         0, 1, 1, @NowUtc, @NowUtc),
        (@CuratedFunderPublicId, N'phase7b-017-curated-' + @Suffix,
         @CuratedName, @CuratedNormalizedName,
         N'https://curated-' + LOWER(LEFT(@Suffix, 20)) + N'.example.org/official',
         0, 1, 1, @NowUtc, @NowUtc),
        (@InactiveFunderPublicId, N'phase7b-017-inactive-' + @Suffix,
         @InactiveName, @InactiveNormalizedName, @InactiveUrl,
         4, 1, 0, @NowUtc, @NowUtc);
    DECLARE @CollisionFunderId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Funders WHERE PublicId = @CollisionFunderPublicId);
    DECLARE @CuratedFunderId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Funders WHERE PublicId = @CuratedFunderPublicId);
    DECLARE @InactiveFunderId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Funders WHERE PublicId = @InactiveFunderPublicId);

    DECLARE @MismatchOpportunityPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ExactOpportunityPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @CuratedOpportunityPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @NewOpportunityPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InactiveOpportunityPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @NewSponsorName NVARCHAR(300) = N'Isolated new sponsor ' + @Suffix;
    INSERT INTO dbo.FundingPlatform_FundingOpportunities
        (PublicId, Slug, Title, SponsorName, SponsorUrl, AmountStatus,
         DeadlineType, DeadlinePrecision, GeographicScope, RemoteApplication,
         PublicationStatus, ContentVersion, IsActive, CreatedAtUtc, UpdatedAtUtc)
    VALUES
        (@MismatchOpportunityPublicId, N'phase7b-017-mismatch-' + @Suffix,
         N'Identity mismatch must remain a draft', @CollisionName, @MismatchUrl,
         0, 0, 0, 0, 0, 0, 1, 1, @NowUtc, @NowUtc),
        (@ExactOpportunityPublicId, N'phase7b-017-exact-' + @Suffix,
         N'Exact identity can reuse the canonical funder', @CollisionName, @CollisionUrl,
         0, 0, 0, 0, 0, 0, 1, 1, @NowUtc, @NowUtc),
        (@CuratedOpportunityPublicId, N'phase7b-017-curated-' + @Suffix,
         N'Curated primary must never be overwritten', @CollisionName, @MismatchUrl,
         0, 0, 0, 0, 0, 0, 1, 1, @NowUtc, @NowUtc),
        (@NewOpportunityPublicId, N'phase7b-017-new-' + @Suffix,
         N'New sponsor remains isolated and draft', @NewSponsorName, NULL,
         0, 0, 0, 0, 0, 0, 1, 1, @NowUtc, @NowUtc),
        (@InactiveOpportunityPublicId, N'phase7b-017-inactive-' + @Suffix,
         N'Inactive legacy primary is audited without mutation', @InactiveName, @InactiveUrl,
         0, 0, 0, 2, 0, 0, 1, 1, @NowUtc, @NowUtc);

    DECLARE @MismatchOpportunityId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_FundingOpportunities
         WHERE PublicId = @MismatchOpportunityPublicId);
    DECLARE @ExactOpportunityId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_FundingOpportunities
         WHERE PublicId = @ExactOpportunityPublicId);
    DECLARE @CuratedOpportunityId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_FundingOpportunities
         WHERE PublicId = @CuratedOpportunityPublicId);
    DECLARE @NewOpportunityId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_FundingOpportunities
         WHERE PublicId = @NewOpportunityPublicId);
    DECLARE @InactiveOpportunityId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_FundingOpportunities
         WHERE PublicId = @InactiveOpportunityPublicId);

    INSERT INTO dbo.FundingPlatform_FundingOpportunityFunders
        (FundingOpportunityId, FunderId, Role, EvidenceId,
         IsActive, CreatedAtUtc, UpdatedAtUtc)
    VALUES (@CuratedOpportunityId, @CuratedFunderId, 1, NULL, 1, @NowUtc, @NowUtc),
           (@InactiveOpportunityId, @InactiveFunderId, 1, NULL, 1, @NowUtc, @NowUtc);
    INSERT INTO dbo.FundingPlatform_FundingOpportunityCategories
        (FundingOpportunityId, FundingCategoryId)
    VALUES (@InactiveOpportunityId, @CategoryId);
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs()
        WHERE FundingOpportunityId = @InactiveOpportunityId)
        THROW 53723, N'The legacy conflict fixture was not catalog-ready before auditing.', 1;

    DECLARE @FunderCountBeforeMismatch BIGINT =
        (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_Funders);
    IF XACT_STATE() <> 1
        THROW 53721, N'The smoke transaction was not committable before identity resolution.', 1;
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_EnsurePrimaryFunder
        @FundingOpportunityPublicId = @MismatchOpportunityPublicId;

    DECLARE @ConflictPublicId UNIQUEIDENTIFIER, @ConflictReasonCode NVARCHAR(50);
    SELECT @ConflictPublicId = PublicId, @ConflictReasonCode = ReasonCode
    FROM dbo.FundingPlatform_FundingOpportunityFunderIdentityConflicts
    WHERE FundingOpportunityId = @MismatchOpportunityId
      AND CandidateFunderId = @CollisionFunderId
      AND IsExistingLink = 0 AND DetectedBy = 1;
    IF @ConflictPublicId IS NULL
        THROW 53706, N'A same-name URL conflict was linked, published, or not audited.', 1;
    IF @ConflictReasonCode <> N'name-collision-url-mismatch'
        THROW 53719, N'Two valid but distinct canonical URLs did not yield a mismatch conflict.', 1;
    IF EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunders
        WHERE FundingOpportunityId = @MismatchOpportunityId
          AND Role = 1 AND IsActive = 1)
        THROW 53716, N'A same-name URL conflict was linked to a primary funder.', 1;
    IF (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_Funders) <> @FunderCountBeforeMismatch
        THROW 53717, N'A same-name URL conflict created a new funder.', 1;
    IF EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
        WHERE Id = @MismatchOpportunityId AND PublicationStatus <> 0)
        THROW 53718, N'A same-name URL conflict changed editorial publication state.', 1;

    DECLARE @ConflictMessageId UNIQUEIDENTIFIER, @ConflictPayload NVARCHAR(MAX);
    SELECT @ConflictMessageId = MessageId, @ConflictPayload = PayloadJson
    FROM dbo.FundingPlatform_OutboxMessages
    WHERE MessageType = N'FundingOpportunityFunderIdentityConflictDetected'
      AND AggregateType = N'FundingOpportunityFunderIdentityConflict'
      AND AggregateId = CONVERT(NVARCHAR(100), @ConflictPublicId);
    IF @ConflictMessageId IS NULL OR ISJSON(@ConflictPayload) <> 1
       OR TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(@ConflictPayload, N'$.conflictId'))
          <> @ConflictPublicId
       OR TRY_CONVERT(UNIQUEIDENTIFIER,
            JSON_VALUE(@ConflictPayload, N'$.fundingOpportunityId'))
          <> @MismatchOpportunityPublicId
       OR TRY_CONVERT(UNIQUEIDENTIFIER,
            JSON_VALUE(@ConflictPayload, N'$.candidateFunderId'))
          <> @CollisionFunderPublicId
       OR JSON_VALUE(@ConflictPayload, N'$.reasonCode') <> N'name-collision-url-mismatch'
       OR TRY_CONVERT(INT, JSON_VALUE(@ConflictPayload, N'$.version')) <> 1
       OR (SELECT COUNT(*) FROM OPENJSON(@ConflictPayload)) <> 5
       OR EXISTS
          (SELECT 1 FROM OPENJSON(@ConflictPayload)
           WHERE [key] NOT IN
             (N'conflictId', N'fundingOpportunityId', N'candidateFunderId',
              N'reasonCode', N'version'))
       OR LOWER(@ConflictPayload) LIKE N'%https%'
       OR LOWER(@ConflictPayload) LIKE N'%email%'
       OR LOWER(@ConflictPayload) LIKE N'%hash%'
        THROW 53707, N'The conflict event is not the exact IDs-only contract.', 1;

    EXEC dbo.FundingPlatform_usp_FundingOpportunity_EnsurePrimaryFunder
        @FundingOpportunityPublicId = @MismatchOpportunityPublicId;
    IF (SELECT COUNT(*)
        FROM dbo.FundingPlatform_FundingOpportunityFunderIdentityConflicts
        WHERE FundingOpportunityId = @MismatchOpportunityId
          AND CandidateFunderId = @CollisionFunderId) <> 1
       OR NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityFunderIdentityConflicts
           WHERE PublicId = @ConflictPublicId AND OccurrenceCount = 2)
       OR (SELECT COUNT(*) FROM dbo.FundingPlatform_OutboxMessages
           WHERE MessageType = N'FundingOpportunityFunderIdentityConflictDetected'
             AND AggregateId = CONVERT(NVARCHAR(100), @ConflictPublicId)) <> 1
        THROW 53708, N'Conflict replay was not durable and idempotent.', 1;

    EXEC dbo.FundingPlatform_usp_FundingOpportunityFunderIdentityConflict_AuditLegacy
        @NowUtc = @NowUtc;
    IF NOT EXISTS
       (SELECT 1
        FROM dbo.FundingPlatform_FundingOpportunityFunderIdentityConflicts
        WHERE FundingOpportunityId = @InactiveOpportunityId
          AND CandidateFunderId = @InactiveFunderId
          AND ReasonCode = N'existing-primary-funder-inactive'
          AND IsExistingLink = 1 AND DetectedBy = 2)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunders
           WHERE FundingOpportunityId = @InactiveOpportunityId
             AND FunderId = @InactiveFunderId AND Role = 1 AND IsActive = 1)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_Funders
           WHERE Id = @InactiveFunderId AND PublicationStatus = 4 AND IsActive = 0)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
           WHERE Id = @InactiveOpportunityId AND PublicationStatus <> 0)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs()
           WHERE FundingOpportunityId = @InactiveOpportunityId)
        THROW 53720, N'An inactive legacy primary was not audited non-destructively.', 1;

    /* This is the original runtime path: the governed StageExternal wrapper
       receives no SponsorUrl from the parser while an unrelated homonym exists.
       Staging may create the opportunity draft, but it must not merge a funder. */
    DECLARE @NullStageExternalId NVARCHAR(250) = N'phase7b-017-null-' + @Suffix;
    DECLARE @NullStageSourceKeyHash BINARY(32) =
        HASHBYTES('SHA2_256', @NullStageExternalId);
    DECLARE @NullStageSourceUrl NVARCHAR(2048) =
        N'https://api.grants.gov/v1/api/search2';
    DECLARE @NullStageSlug NVARCHAR(320) =
        N'phase7b-017-null-' + LOWER(@Suffix);
    DECLARE @NullStageCanonicalUrlHash BINARY(32) = HASHBYTES
    (
        'SHA2_256',
        CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
            @NullStageSourceUrl COLLATE Latin1_General_100_BIN2_UTF8))
    );
    DECLARE @NullStageSnapshot NVARCHAR(MAX) =
        (SELECT @NullStageExternalId AS externalId,
                N'Null sponsor identity must not merge' AS title
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @NullStageContentHash BINARY(32) = HASHBYTES
    (
        'SHA2_256',
        CONVERT(VARBINARY(MAX), CONVERT(VARCHAR(MAX),
            @NullStageSnapshot COLLATE Latin1_General_100_BIN2_UTF8))
    );
    DECLARE @NullStageResult TABLE
    (
        Succeeded BIT, Code NVARCHAR(50),
        FundingOpportunityPublicId UNIQUEIDENTIFIER NULL,
        ContentVersion INT NULL, PublicationStatus TINYINT NULL,
        RowVersion BINARY(8) NULL, StagedRevisionPublicId UNIQUEIDENTIFIER NULL
    );
    DECLARE @FunderCountBeforeNullStage BIGINT =
        (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_Funders);
    INSERT INTO @NullStageResult
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_StageExternal
        @FundingSourceId = @ApiSourceId, @ExpectedProviderCode = N'grants-gov',
        @ExternalId = @NullStageExternalId,
        @SourceItemKeyHash = @NullStageSourceKeyHash,
        @SourceUrl = @NullStageSourceUrl,
        @CanonicalUrlHash = @NullStageCanonicalUrlHash,
        @ObservedAtUtc = @NowUtc,
        @Slug = @NullStageSlug,
        @Title = N'Null sponsor identity must not merge',
        @SponsorName = @CollisionName, @SponsorUrl = NULL,
        @AmountStatus = 0, @DeadlineType = 0, @DeadlinePrecision = 0,
        @DataQualityScore = 80, @SnapshotJson = @NullStageSnapshot,
        @ContentHash = @NullStageContentHash;
    DECLARE @NullStageOpportunityPublicId UNIQUEIDENTIFIER =
        (SELECT FundingOpportunityPublicId FROM @NullStageResult WHERE Succeeded = 1);
    DECLARE @NullStageOpportunityId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_FundingOpportunities
         WHERE PublicId = @NullStageOpportunityPublicId);
    IF @NullStageOpportunityId IS NULL
       OR NOT EXISTS
          (SELECT 1 FROM @NullStageResult
           WHERE Code = N'draft-created' AND PublicationStatus = 0)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunders
           WHERE FundingOpportunityId = @NullStageOpportunityId
             AND Role = 1 AND IsActive = 1)
       OR NOT EXISTS
          (SELECT 1
           FROM dbo.FundingPlatform_FundingOpportunityFunderIdentityConflicts
           WHERE FundingOpportunityId = @NullStageOpportunityId
             AND CandidateFunderId = @CollisionFunderId
             AND ReasonCode = N'name-collision-url-invalid'
             AND IsExistingLink = 0 AND DetectedBy = 1)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_Funders)
          <> @FunderCountBeforeNullStage
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
           WHERE Id = @NullStageOpportunityId AND PublicationStatus <> 0)
        THROW 53715, N'StageExternal merged a same-name funder without a strong URL identity.', 1;

    DECLARE @AdminConflicts TABLE
    (
        ConflictPublicId UNIQUEIDENTIFIER,
        FundingOpportunityPublicId UNIQUEIDENTIFIER,
        FundingOpportunityTitle NVARCHAR(350),
        CandidateFunderPublicId UNIQUEIDENTIFIER,
        CandidateFunderName NVARCHAR(300),
        ReasonCode NVARCHAR(50), IsExistingLink BIT, DetectedBy TINYINT,
        Status TINYINT, OccurrenceCount INT,
        FirstDetectedAtUtc DATETIME2(3), LastDetectedAtUtc DATETIME2(3),
        RowVersion BINARY(8), TotalCount BIGINT
    );
    INSERT INTO @AdminConflicts
    EXEC dbo.FundingPlatform_usp_FundingOpportunityFunderIdentityConflict_AdminList
        @AdminUserPublicId = @AdminPublicId, @Status = 0,
        @PageNumber = 1, @PageSize = 100;
    IF NOT EXISTS
       (SELECT 1 FROM @AdminConflicts
        WHERE ConflictPublicId = @ConflictPublicId
          AND FundingOpportunityPublicId = @MismatchOpportunityPublicId
          AND CandidateFunderPublicId = @CollisionFunderPublicId
          AND ReasonCode = N'name-collision-url-mismatch'
          AND OccurrenceCount = 2)
        THROW 53709, N'The MFA-protected conflict queue did not return the safe record.', 1;

    DECLARE @NoMfaRejected BIT = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        DELETE FROM @AdminConflicts;
        INSERT INTO @AdminConflicts
        EXEC dbo.FundingPlatform_usp_FundingOpportunityFunderIdentityConflict_AdminList
            @AdminUserPublicId = @NoMfaPublicId, @Status = 0,
            @PageNumber = 1, @PageSize = 10;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 51905 SET @NoMfaRejected = 1;
        ELSE THROW;
    END CATCH;
    SET XACT_ABORT ON;
    IF @NoMfaRejected <> 1
        THROW 53710, N'The administrative conflict queue did not require MFA.', 1;

    EXEC dbo.FundingPlatform_usp_FundingOpportunity_EnsurePrimaryFunder
        @FundingOpportunityPublicId = @ExactOpportunityPublicId;
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_EnsurePrimaryFunder
        @FundingOpportunityPublicId = @ExactOpportunityPublicId;
    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunityFunders
        WHERE FundingOpportunityId = @ExactOpportunityId
          AND FunderId = @CollisionFunderId AND Role = 1 AND IsActive = 1) <> 1
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunderIdentityConflicts
           WHERE FundingOpportunityId = @ExactOpportunityId)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_Funders
           WHERE Id = @CollisionFunderId AND PublicationStatus <> 0)
        THROW 53711, N'An exact strong identity was not linked idempotently as a draft.', 1;

    DECLARE @FunderCountBeforeCurated BIGINT =
        (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_Funders);
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_EnsurePrimaryFunder
        @FundingOpportunityPublicId = @CuratedOpportunityPublicId;
    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingOpportunityFunders
        WHERE FundingOpportunityId = @CuratedOpportunityId
          AND FunderId = @CuratedFunderId AND Role = 1 AND IsActive = 1) <> 1
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunders
           WHERE FundingOpportunityId = @CuratedOpportunityId
             AND FunderId = @CollisionFunderId AND IsActive = 1)
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_Funders) <> @FunderCountBeforeCurated
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunderIdentityConflicts
           WHERE FundingOpportunityId = @CuratedOpportunityId)
        THROW 53712, N'The helper replaced or reinterpreted a curated primary funder.', 1;

    DECLARE @FunderCountBeforeNew BIGINT =
        (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_Funders);
    EXEC dbo.FundingPlatform_usp_FundingOpportunity_EnsurePrimaryFunder
        @FundingOpportunityPublicId = @NewOpportunityPublicId;
    DECLARE @NewFunderId BIGINT;
    SELECT @NewFunderId = links.FunderId
    FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
    WHERE links.FundingOpportunityId = @NewOpportunityId
      AND links.Role = 1 AND links.IsActive = 1;
    IF @NewFunderId IS NULL
       OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_Funders) <> @FunderCountBeforeNew + 1
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_Funders
           WHERE Id = @NewFunderId AND NormalizedName = UPPER(@NewSponsorName)
             AND WebsiteUrl IS NULL AND PublicationStatus = 0 AND IsActive = 1)
       OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
           WHERE Id IN (@MismatchOpportunityId, @ExactOpportunityId,
                        @CuratedOpportunityId, @NewOpportunityId)
             AND PublicationStatus <> 0)
        THROW 53713, N'A genuinely new sponsor was not isolated as an unpublished draft.', 1;

    UPDATE dbo.FundingPlatform_OutboxMessages
    SET AvailableAtUtc = CONVERT(DATETIME2(3), '2000-01-01T00:00:00.000')
    WHERE MessageId = @ConflictMessageId;
    DECLARE @AcknowledgedCount INT, @AcknowledgeAttempt INT = 0;
    WHILE @AcknowledgeAttempt < 20
          AND EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
               WHERE MessageId = @ConflictMessageId AND DispatchedAtUtc IS NULL)
    BEGIN
        SET @AcknowledgedCount = 0;
        EXEC dbo.FundingPlatform_usp_OutboxAuditEvents_Acknowledge
            @BatchSize = 500, @NowUtc = @NowUtc,
            @AcknowledgedCount = @AcknowledgedCount OUTPUT;
        SET @AcknowledgeAttempt += 1;
    END;
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
        WHERE MessageId = @ConflictMessageId AND DispatchedAtUtc = @NowUtc
          AND LastError = N'event-ledger-acknowledged')
        THROW 53714, N'The explicit audit sink did not terminalize the safe conflict event.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke017;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FP_Smoke017;
    THROW;
END CATCH;

SELECT N'Primary-funder identity hardening smoke passed.' AS Result;
GO
