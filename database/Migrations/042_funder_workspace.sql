/* Block 4: explicit funder ownership; existing editorial procedures remain the single
   mutation path. Default @OwnerWorkspace = 0 preserves admin/MFA behavior.
   Reviewed/public/imported records are never claimed by name, email or primary-funder link.
   Bodies below retain the latest 010 definitions, adding only scoped authorization,
   ownership assignment/filtering and owner-input guards. */
SET XACT_ABORT ON;
GO
CREATE TABLE dbo.FundingPlatform_FunderWorkspaceOwners
(
    FunderId BIGINT NOT NULL PRIMARY KEY,
    UserId BIGINT NOT NULL,
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_FunderWorkspaceOwners_Active DEFAULT (1),
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FunderWorkspaceOwners_Created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FundingPlatform_FK_FunderWorkspaceOwners_Funder FOREIGN KEY (FunderId) REFERENCES dbo.FundingPlatform_Funders(Id),
    CONSTRAINT FundingPlatform_FK_FunderWorkspaceOwners_User FOREIGN KEY (UserId) REFERENCES dbo.FundingPlatform_Users(Id)
);
CREATE INDEX FundingPlatform_IX_FunderWorkspaceOwners_User ON dbo.FundingPlatform_FunderWorkspaceOwners(UserId, IsActive);
CREATE TABLE dbo.FundingPlatform_OpportunityWorkspaceOwners
(
    FundingOpportunityId BIGINT NOT NULL PRIMARY KEY,
    FunderId BIGINT NOT NULL,
    CONSTRAINT FundingPlatform_FK_OpportunityWorkspaceOwners_Opportunity FOREIGN KEY (FundingOpportunityId) REFERENCES dbo.FundingPlatform_FundingOpportunities(Id),
    CONSTRAINT FundingPlatform_FK_OpportunityWorkspaceOwners_Funder FOREIGN KEY (FunderId) REFERENCES dbo.FundingPlatform_Funders(Id)
);
CREATE INDEX FundingPlatform_IX_OpportunityWorkspaceOwners_Funder ON dbo.FundingPlatform_OpportunityWorkspaceOwners(FunderId);
INSERT INTO dbo.FundingPlatform_FundingSources(Name, ProviderType, IsEnabled, ProviderCode)
VALUES (N'Portal de financiadores', 0, 1, N'funder-workspace');
GO
/* Locks are reacquired inside each write transaction before checking/replaying events.
   This helper grants nothing and cannot approve/review, transfer or claim an existing entity. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FunderWorkspace_Assert
    @UserPublicId UNIQUEIDENTIFIER, @EntityKind TINYINT,
    @EntityPublicId UNIQUEIDENTIFIER = NULL, @ActorUserId BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @ActorUserId = NULL;
    SELECT @ActorUserId = Id FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
    WHERE PublicId = @UserPublicId AND Status = 2 AND EmailConfirmed = 1;
    IF @ActorUserId IS NULL OR @EntityKind NOT IN (1, 2)
        THROW 51601, N'Workspace access is not available.', 1;
    IF dbo.FundingPlatform_fn_AdminAccessState(@UserPublicId) = 1
        THROW 51602, N'MFA is required for this account.', 1;
    IF @EntityPublicId IS NOT NULL AND @EntityKind = 1 AND NOT EXISTS
        (SELECT 1 FROM dbo.FundingPlatform_FunderWorkspaceOwners AS owners WITH (UPDLOCK, HOLDLOCK)
         INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = owners.FunderId
         WHERE funders.PublicId = @EntityPublicId AND owners.UserId = @ActorUserId AND owners.IsActive = 1)
        THROW 51601, N'Workspace access is not available.', 1;
    IF @EntityPublicId IS NOT NULL AND @EntityKind = 2 AND NOT EXISTS
        (SELECT 1 FROM dbo.FundingPlatform_OpportunityWorkspaceOwners AS managed WITH (UPDLOCK, HOLDLOCK)
         INNER JOIN dbo.FundingPlatform_FunderWorkspaceOwners AS owners WITH (UPDLOCK, HOLDLOCK) ON owners.FunderId = managed.FunderId
         INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities ON opportunities.Id = managed.FundingOpportunityId
         WHERE opportunities.PublicId = @EntityPublicId AND owners.UserId = @ActorUserId AND owners.IsActive = 1)
        THROW 51601, N'Workspace access is not available.', 1;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FunderWorkspace_Sources
    @UserPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ActorUserId BIGINT;
    EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @UserPublicId, 1, NULL, @ActorUserId OUTPUT;
    SELECT Id, Name, ProviderType, BaseUrl, IsEnabled
    FROM dbo.FundingPlatform_FundingSources
    WHERE ProviderCode = N'funder-workspace' AND IsEnabled = 1;
END;
GO
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_FunderWorkspace_Sources TO FundingPlatform_ApiRuntimeRole;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Funder_Admin_List
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @Query NVARCHAR(300) = NULL,
    @PublicationStatus TINYINT = NULL,
    @IncludeInactive BIT = 0,
    @PageNumber INT = 1,
    @PageSize INT = 50,
    @OwnerWorkspace BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    IF @OwnerWorkspace IS NULL THROW 51601, N'Invalid workspace scope.', 1;
    DECLARE @WorkspaceActorUserId BIGINT;
    IF @OwnerWorkspace = 1
        EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 1, NULL, @WorkspaceActorUserId OUTPUT;
    ELSE
    BEGIN
    IF dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId) = 0
        THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId) = 1
        THROW 51602, N'MFA is required for this administrative operation.', 1;
    END;
    IF @PageNumber < 1 THROW 51603, N'PageNumber must be at least 1.', 1;
    IF @PageSize < 1 OR @PageSize > 100
        THROW 51604, N'PageSize must be between 1 and 100.', 1;
    IF @PublicationStatus IS NOT NULL AND @PublicationStatus NOT BETWEEN 0 AND 4
        THROW 51605, N'PublicationStatus is invalid.', 1;

    DECLARE @QueryLike NVARCHAR(302) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Query)), N'') IS NULL THEN NULL
             ELSE N'%' + LTRIM(RTRIM(@Query)) + N'%' END;

    SELECT COUNT_BIG(1) AS TotalCount
    FROM dbo.FundingPlatform_Funders AS funders
    WHERE (@OwnerWorkspace = 0 OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_FunderWorkspaceOwners AS owners WHERE owners.FunderId = funders.Id AND owners.UserId = @WorkspaceActorUserId AND owners.IsActive = 1))
      AND (@IncludeInactive = 1 OR funders.IsActive = 1)
      AND (@PublicationStatus IS NULL OR funders.PublicationStatus = @PublicationStatus)
      AND (@QueryLike IS NULL OR funders.Name LIKE @QueryLike OR funders.Slug LIKE @QueryLike
           OR EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_FunderAliases AS aliases
               WHERE aliases.FunderId = funders.Id AND aliases.IsActive = 1
                 AND aliases.Alias LIKE @QueryLike));

    SELECT funders.PublicId AS FunderPublicId,
           funders.Slug, funders.Name, funders.Description, funders.WebsiteUrl,
           funders.CountryId, RTRIM(countries.Iso2) AS CountryCode,
           countries.Name AS CountryName, funders.ContentVersion,
           funders.PublicationStatus, funders.IsActive,
           funders.SubmittedAtUtc, funders.PublishedAtUtc, funders.ReviewedAtUtc,
           reviewers.PublicId AS ReviewedByUserPublicId, funders.RejectionReason,
           funders.CreatedAtUtc, funders.UpdatedAtUtc, funders.RowVersion
    FROM dbo.FundingPlatform_Funders AS funders
    LEFT JOIN dbo.FundingPlatform_Countries AS countries ON countries.Id = funders.CountryId
    LEFT JOIN dbo.FundingPlatform_Users AS reviewers ON reviewers.Id = funders.ReviewedByUserId
    WHERE (@OwnerWorkspace = 0 OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_FunderWorkspaceOwners AS owners WHERE owners.FunderId = funders.Id AND owners.UserId = @WorkspaceActorUserId AND owners.IsActive = 1))
      AND (@IncludeInactive = 1 OR funders.IsActive = 1)
      AND (@PublicationStatus IS NULL OR funders.PublicationStatus = @PublicationStatus)
      AND (@QueryLike IS NULL OR funders.Name LIKE @QueryLike OR funders.Slug LIKE @QueryLike
           OR EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_FunderAliases AS aliases
               WHERE aliases.FunderId = funders.Id AND aliases.IsActive = 1
                 AND aliases.Alias LIKE @QueryLike))
    ORDER BY funders.UpdatedAtUtc DESC, funders.Id DESC
    OFFSET ((@PageNumber - 1) * @PageSize) ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Funder_Admin_Get
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FunderPublicId UNIQUEIDENTIFIER,
    @OwnerWorkspace BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    IF @OwnerWorkspace IS NULL THROW 51601, N'Invalid workspace scope.', 1;
    DECLARE @WorkspaceActorUserId BIGINT;
    IF @OwnerWorkspace = 1
        EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 1, @FunderPublicId, @WorkspaceActorUserId OUTPUT;
    ELSE
    BEGIN
    IF dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId) = 0
        THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId) = 1
        THROW 51602, N'MFA is required for this administrative operation.', 1;
    END;

    DECLARE @FunderId BIGINT;
    SELECT @FunderId = Id FROM dbo.FundingPlatform_Funders WHERE PublicId = @FunderPublicId;
    IF @FunderId IS NULL THROW 51606, N'Funder was not found.', 1;

    SELECT funders.PublicId AS FunderPublicId,
           funders.Slug, funders.Name, funders.Description, funders.WebsiteUrl,
           funders.CountryId, RTRIM(countries.Iso2) AS CountryCode,
           countries.Name AS CountryName, funders.ContentVersion,
           funders.PublicationStatus, funders.IsActive,
           funders.SubmittedAtUtc, funders.PublishedAtUtc, funders.ReviewedAtUtc,
           reviewers.PublicId AS ReviewedByUserPublicId, funders.RejectionReason,
           funders.CreatedAtUtc, funders.UpdatedAtUtc, funders.RowVersion
    FROM dbo.FundingPlatform_Funders AS funders
    LEFT JOIN dbo.FundingPlatform_Countries AS countries ON countries.Id = funders.CountryId
    LEFT JOIN dbo.FundingPlatform_Users AS reviewers ON reviewers.Id = funders.ReviewedByUserId
    WHERE funders.Id = @FunderId;

    SELECT Alias, IsPrimary, IsActive
    FROM dbo.FundingPlatform_FunderAliases
    WHERE FunderId = @FunderId
    ORDER BY IsActive DESC, IsPrimary DESC, Alias, Id;

    SELECT opportunities.PublicId AS FundingOpportunityPublicId,
           opportunities.Slug, opportunities.Title, links.Role,
           opportunities.PublicationStatus, opportunities.IsActive
    FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
    INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
        ON opportunities.Id = links.FundingOpportunityId
    WHERE links.FunderId = @FunderId AND links.IsActive = 1
      AND (@OwnerWorkspace = 0 OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_OpportunityWorkspaceOwners AS managed WHERE managed.FundingOpportunityId = opportunities.Id AND managed.FunderId = @FunderId))
    ORDER BY opportunities.UpdatedAtUtc DESC, opportunities.Id DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Funder_Create
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @Slug NVARCHAR(180),
    @Name NVARCHAR(300),
    @Description NVARCHAR(2000) = NULL,
    @WebsiteUrl NVARCHAR(2048) = NULL,
    @CountryId SMALLINT = NULL,
    @AliasesJson NVARCHAR(MAX) = N'[]',
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @OwnerWorkspace BIT = 0
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @OwnerWorkspace IS NULL THROW 51601, N'Invalid workspace scope.', 1;
    DECLARE @WorkspaceActorUserId BIGINT;
    IF @OwnerWorkspace = 1
        EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 1, NULL, @WorkspaceActorUserId OUTPUT;
    ELSE
    BEGIN
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    END;

    DECLARE @ActorUserId BIGINT, @FunderId BIGINT, @FunderPublicId UNIQUEIDENTIFIER;
    DECLARE @RowVersion BINARY(8), @ExistingRequestHash BINARY(32);
    DECLARE @Code NVARCHAR(50) = N'created', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @NormalizedName NVARCHAR(300) = UPPER(LTRIM(RTRIM(@Name)));
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @RawAliasCount INT, @ValidAliasCount INT;
    DECLARE @Aliases TABLE (Alias NVARCHAR(300) NOT NULL, NormalizedAlias NVARCHAR(300) NOT NULL);

    IF NULLIF(LTRIM(RTRIM(@Slug)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(@Name)), N'') IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               CAST(NULL AS UNIQUEIDENTIFIER) AS FunderPublicId, CAST(NULL AS INT) AS ContentVersion,
               CAST(NULL AS TINYINT) AS PublicationStatus, CAST(NULL AS BINARY(8)) AS RowVersion,
               CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;
    IF ISJSON(COALESCE(@AliasesJson, N'[]')) <> 1
       OR LEFT(LTRIM(COALESCE(@AliasesJson, N'[]')), 1) <> N'['
        THROW 51607, N'AliasesJson must be a JSON array.', 1;

    SELECT @RawAliasCount = COUNT(*)
    FROM OPENJSON(COALESCE(@AliasesJson, N'[]'));
    SELECT @ValidAliasCount = COUNT(*)
    FROM OPENJSON(COALESCE(@AliasesJson, N'[]'))
    WITH (Alias NVARCHAR(4000) '$.alias') AS parsed
    WHERE NULLIF(LTRIM(RTRIM(parsed.Alias)), N'') IS NOT NULL
      AND LEN(parsed.Alias) <= 300;

    IF @RawAliasCount <> @ValidAliasCount
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               CAST(NULL AS UNIQUEIDENTIFIER) AS FunderPublicId, CAST(NULL AS INT) AS ContentVersion,
               CAST(NULL AS TINYINT) AS PublicationStatus, CAST(NULL AS BINARY(8)) AS RowVersion,
               CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    INSERT INTO @Aliases (Alias, NormalizedAlias)
    SELECT LTRIM(RTRIM(parsed.Alias)), UPPER(LTRIM(RTRIM(parsed.Alias)))
    FROM OPENJSON(COALESCE(@AliasesJson, N'[]'))
    WITH (Alias NVARCHAR(300) '$.alias') AS parsed
    WHERE NULLIF(LTRIM(RTRIM(parsed.Alias)), N'') IS NOT NULL
      AND UPPER(LTRIM(RTRIM(parsed.Alias))) <> @NormalizedName;

    IF EXISTS (SELECT NormalizedAlias FROM @Aliases GROUP BY NormalizedAlias HAVING COUNT_BIG(1) > 1)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'alias-conflict' AS Code,
               CAST(NULL AS UNIQUEIDENTIFIER) AS FunderPublicId, CAST(NULL AS INT) AS ContentVersion,
               CAST(NULL AS TINYINT) AS PublicationStatus, CAST(NULL AS BINARY(8)) AS RowVersion,
               CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_FunderCreate;
    BEGIN TRY
        IF @OwnerWorkspace = 1
            EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 1, NULL, @ActorUserId OUTPUT;
        ELSE
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @ActorUserId = Id
        FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;

        SELECT @FunderId = events.FunderId, @ExistingRequestHash = events.RequestHash,
               @RowVersion = events.ResultRowVersion
        FROM dbo.FundingPlatform_FunderEditorialEvents AS events WITH (UPDLOCK, HOLDLOCK)
        WHERE events.ActorUserId = @ActorUserId AND events.ActionCode = N'Create'
          AND events.IdempotencyKeyHash = @IdempotencyKeyHash;

        IF @FunderId IS NOT NULL
        BEGIN
            IF @OwnerWorkspace = 1 AND NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FunderWorkspaceOwners WHERE FunderId = @FunderId AND UserId = @ActorUserId AND IsActive = 1)
                THROW 51601, N'Workspace access is not available.', 1;
            SELECT @FunderPublicId = PublicId FROM dbo.FundingPlatform_Funders WHERE Id = @FunderId;
            IF @ExistingRequestHash = @RequestHash
            BEGIN
                SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'created';
            END
            ELSE SET @Code = N'idempotency-conflict';
        END
        ELSE IF @CountryId IS NOT NULL AND NOT EXISTS
                (SELECT 1 FROM dbo.FundingPlatform_Countries WHERE Id = @CountryId AND IsActive = 1)
            SET @Code = N'invalid-document';
            ELSE IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders WITH (UPDLOCK, HOLDLOCK)
                            WHERE Slug = LTRIM(RTRIM(@Slug)))
                SET @Code = N'slug-conflict';
            ELSE IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders WITH (UPDLOCK, HOLDLOCK)
                            WHERE NormalizedName = @NormalizedName)
            SET @Code = N'name-conflict';
        ELSE
        BEGIN
            DECLARE @InsertedFunder TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER, RowVersion BINARY(8));
            INSERT INTO dbo.FundingPlatform_Funders
            (
                Slug, Name, NormalizedName, Description, WebsiteUrl, CountryId,
                PublicationStatus, ContentVersion, IsActive,
                CreatedByUserId, UpdatedByUserId, CreatedAtUtc, UpdatedAtUtc
            )
            OUTPUT inserted.Id, inserted.PublicId, inserted.RowVersion
                INTO @InsertedFunder (Id, PublicId, RowVersion)
            VALUES
            (
                LTRIM(RTRIM(@Slug)), LTRIM(RTRIM(@Name)), @NormalizedName,
                NULLIF(LTRIM(RTRIM(@Description)), N''), NULLIF(LTRIM(RTRIM(@WebsiteUrl)), N''),
                @CountryId, 0, 1, 1, @ActorUserId, @ActorUserId, @NowUtc, @NowUtc
            );
            SELECT @FunderId = Id, @FunderPublicId = PublicId, @RowVersion = RowVersion
            FROM @InsertedFunder;
            IF @OwnerWorkspace = 1
            BEGIN
                IF (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_FunderWorkspaceOwners WITH (UPDLOCK, HOLDLOCK) WHERE UserId = @ActorUserId) >= 3
                    THROW 51601, N'Workspace profile limit reached.', 1;
                INSERT INTO dbo.FundingPlatform_FunderWorkspaceOwners(FunderId, UserId) VALUES (@FunderId, @ActorUserId);
            END;

            INSERT INTO dbo.FundingPlatform_FunderAliases
                (FunderId, Alias, NormalizedAlias, IsPrimary, IsActive, CreatedAtUtc)
            VALUES (@FunderId, LTRIM(RTRIM(@Name)), @NormalizedName, 1, 1, @NowUtc);
            INSERT INTO dbo.FundingPlatform_FunderAliases
                (FunderId, Alias, NormalizedAlias, IsPrimary, IsActive, CreatedAtUtc)
            SELECT @FunderId, aliases.Alias, aliases.NormalizedAlias, 0, 1, @NowUtc
            FROM @Aliases AS aliases;

            DECLARE @SnapshotJson NVARCHAR(MAX) =
            (
                SELECT LTRIM(RTRIM(@Slug)) AS slug, LTRIM(RTRIM(@Name)) AS name,
                       NULLIF(LTRIM(RTRIM(@Description)), N'') AS description,
                       NULLIF(LTRIM(RTRIM(@WebsiteUrl)), N'') AS websiteUrl,
                       @CountryId AS countryId,
                       JSON_QUERY
                       (
                           (SELECT aliases.Alias AS alias, aliases.IsPrimary AS isPrimary
                            FROM dbo.FundingPlatform_FunderAliases AS aliases
                            WHERE aliases.FunderId = @FunderId AND aliases.IsActive = 1
                            ORDER BY aliases.IsPrimary DESC, aliases.Id FOR JSON PATH)
                       ) AS aliases
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
            INSERT INTO dbo.FundingPlatform_FunderVersions
                (FunderId, ContentVersion, SnapshotJson, ContentHash, CreatedByUserId, CreatedAtUtc)
            VALUES (@FunderId, 1, @SnapshotJson,
                    HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @SnapshotJson)),
                    @ActorUserId, @NowUtc);
            INSERT INTO dbo.FundingPlatform_FunderEditorialEvents
                (EventId, FunderId, ContentVersion, FromStatus, ToStatus, ActionCode,
                 ActorUserId, Reason, IdempotencyKeyHash, RequestHash, ResultRowVersion, CreatedAtUtc)
            VALUES (@EventId, @FunderId, 1, 0, 0, N'Create', @ActorUserId, NULL,
                    @IdempotencyKeyHash, @RequestHash, @RowVersion, @NowUtc);
            INSERT INTO dbo.FundingPlatform_OutboxMessages
                (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                 OccurredAtUtc, AvailableAtUtc)
            SELECT @EventId, N'FunderDraftCreated', N'Funder', CONVERT(NVARCHAR(100), @FunderId),
                   (SELECT @EventId AS eventId, @FunderId AS funderId,
                           @FunderPublicId AS funderPublicId, 1 AS contentVersion
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
            SET @Succeeded = 1;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_FunderCreate;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, @FunderPublicId AS FunderPublicId,
           CASE WHEN @FunderId IS NULL THEN NULL ELSE 1 END AS ContentVersion,
           CASE WHEN @FunderId IS NULL THEN NULL ELSE 0 END AS PublicationStatus,
           @RowVersion AS RowVersion, @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Funder_Update
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FunderPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @Name NVARCHAR(300),
    @Description NVARCHAR(2000) = NULL,
    @WebsiteUrl NVARCHAR(2048) = NULL,
    @CountryId SMALLINT = NULL,
    @AliasesJson NVARCHAR(MAX) = N'[]',
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @OwnerWorkspace BIT = 0
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @OwnerWorkspace IS NULL THROW 51601, N'Invalid workspace scope.', 1;
    DECLARE @WorkspaceActorUserId BIGINT;
    IF @OwnerWorkspace = 1
        EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 1, @FunderPublicId, @WorkspaceActorUserId OUTPUT;
    ELSE
    BEGIN
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    END;
    IF ISJSON(COALESCE(@AliasesJson, N'[]')) <> 1
       OR LEFT(LTRIM(COALESCE(@AliasesJson, N'[]')), 1) <> N'['
        THROW 51607, N'AliasesJson must be a JSON array.', 1;

    DECLARE @ActorUserId BIGINT, @FunderId BIGINT, @CurrentStatus TINYINT, @CurrentSlug NVARCHAR(180);
    DECLARE @CurrentVersion INT, @NextVersion INT, @CurrentRowVersion BINARY(8), @RowVersion BINARY(8);
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @NormalizedName NVARCHAR(300) = UPPER(LTRIM(RTRIM(@Name)));
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @RawAliasCount INT, @ValidAliasCount INT;
    DECLARE @Aliases TABLE (Alias NVARCHAR(300) NOT NULL, NormalizedAlias NVARCHAR(300) NOT NULL);

    INSERT INTO @Aliases (Alias, NormalizedAlias)
    SELECT LTRIM(RTRIM(parsed.Alias)), UPPER(LTRIM(RTRIM(parsed.Alias)))
    FROM OPENJSON(COALESCE(@AliasesJson, N'[]'))
    WITH (Alias NVARCHAR(300) '$.alias') AS parsed
    WHERE NULLIF(LTRIM(RTRIM(parsed.Alias)), N'') IS NOT NULL
      AND UPPER(LTRIM(RTRIM(parsed.Alias))) <> @NormalizedName;

    SELECT @RawAliasCount = COUNT(*)
    FROM OPENJSON(COALESCE(@AliasesJson, N'[]'));
    SELECT @ValidAliasCount = COUNT(*)
    FROM OPENJSON(COALESCE(@AliasesJson, N'[]'))
    WITH (Alias NVARCHAR(4000) '$.alias') AS parsed
    WHERE NULLIF(LTRIM(RTRIM(parsed.Alias)), N'') IS NOT NULL
      AND LEN(parsed.Alias) <= 300;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_FunderUpdate;
    BEGIN TRY
        IF @OwnerWorkspace = 1
            EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 1, @FunderPublicId, @ActorUserId OUTPUT;
        ELSE
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @ActorUserId = Id
        FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;
        SELECT @FunderId = Id, @CurrentStatus = PublicationStatus, @CurrentSlug = Slug,
               @CurrentVersion = ContentVersion, @CurrentRowVersion = RowVersion
        FROM dbo.FundingPlatform_Funders WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @FunderPublicId;

        IF @FunderId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = ActionCode, @ExistingRequestHash = RequestHash,
                   @ExistingToStatus = ToStatus, @RowVersion = ResultRowVersion,
                   @NextVersion = ContentVersion
            FROM dbo.FundingPlatform_FunderEditorialEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE FunderId = @FunderId AND IdempotencyKeyHash = @IdempotencyKeyHash;
            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'Update' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'updated';
                    SET @CurrentStatus = @ExistingToStatus;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus NOT IN (0, 3) SET @Code = N'invalid-transition';
            ELSE IF NULLIF(LTRIM(RTRIM(@Name)), N'') IS NULL
                 OR @RawAliasCount <> @ValidAliasCount
                 OR EXISTS (SELECT NormalizedAlias FROM @Aliases GROUP BY NormalizedAlias HAVING COUNT_BIG(1) > 1)
                SET @Code = N'invalid-document';
            ELSE IF @CountryId IS NOT NULL AND NOT EXISTS
                    (SELECT 1 FROM dbo.FundingPlatform_Countries WHERE Id = @CountryId AND IsActive = 1)
                SET @Code = N'invalid-document';
            ELSE IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders WITH (UPDLOCK, HOLDLOCK)
                            WHERE NormalizedName = @NormalizedName AND Id <> @FunderId)
                SET @Code = N'name-conflict';
            ELSE
            BEGIN
                SET @NextVersion = @CurrentVersion + 1;
                DECLARE @UpdatedFunder TABLE (RowVersion BINARY(8));
                UPDATE dbo.FundingPlatform_Funders
                SET Name = LTRIM(RTRIM(@Name)),
                    NormalizedName = @NormalizedName,
                    Description = NULLIF(LTRIM(RTRIM(@Description)), N''),
                    WebsiteUrl = NULLIF(LTRIM(RTRIM(@WebsiteUrl)), N''),
                    CountryId = @CountryId, ContentVersion = @NextVersion,
                    UpdatedByUserId = @ActorUserId, UpdatedAtUtc = @NowUtc
                OUTPUT inserted.RowVersion INTO @UpdatedFunder (RowVersion)
                WHERE Id = @FunderId AND RowVersion = @ExpectedRowVersion;
                SELECT @RowVersion = RowVersion FROM @UpdatedFunder;
                IF @RowVersion IS NULL SET @Code = N'etag-conflict';
                ELSE
                BEGIN
                    UPDATE dbo.FundingPlatform_FunderAliases
                    SET IsActive = 0, IsPrimary = 0
                    WHERE FunderId = @FunderId;
                    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_FunderAliases
                               WHERE FunderId = @FunderId AND NormalizedAlias = @NormalizedName)
                        UPDATE dbo.FundingPlatform_FunderAliases
                        SET Alias = LTRIM(RTRIM(@Name)), IsPrimary = 1, IsActive = 1
                        WHERE FunderId = @FunderId AND NormalizedAlias = @NormalizedName;
                    ELSE
                        INSERT INTO dbo.FundingPlatform_FunderAliases
                            (FunderId, Alias, NormalizedAlias, IsPrimary, IsActive, CreatedAtUtc)
                        VALUES (@FunderId, LTRIM(RTRIM(@Name)), @NormalizedName, 1, 1, @NowUtc);

                    UPDATE aliases
                    SET Alias = requested.Alias, IsPrimary = 0, IsActive = 1
                    FROM dbo.FundingPlatform_FunderAliases AS aliases
                    INNER JOIN @Aliases AS requested ON requested.NormalizedAlias = aliases.NormalizedAlias
                    WHERE aliases.FunderId = @FunderId;
                    INSERT INTO dbo.FundingPlatform_FunderAliases
                        (FunderId, Alias, NormalizedAlias, IsPrimary, IsActive, CreatedAtUtc)
                    SELECT @FunderId, requested.Alias, requested.NormalizedAlias, 0, 1, @NowUtc
                    FROM @Aliases AS requested
                    WHERE NOT EXISTS
                    (
                        SELECT 1 FROM dbo.FundingPlatform_FunderAliases AS existing
                        WHERE existing.FunderId = @FunderId
                          AND existing.NormalizedAlias = requested.NormalizedAlias
                    );

                    DECLARE @SnapshotJson NVARCHAR(MAX) =
                    (
                        SELECT @CurrentSlug AS slug, LTRIM(RTRIM(@Name)) AS name,
                               NULLIF(LTRIM(RTRIM(@Description)), N'') AS description,
                               NULLIF(LTRIM(RTRIM(@WebsiteUrl)), N'') AS websiteUrl,
                               @CountryId AS countryId,
                               JSON_QUERY
                               (
                                   (SELECT aliases.Alias AS alias, aliases.IsPrimary AS isPrimary
                                    FROM dbo.FundingPlatform_FunderAliases AS aliases
                                    WHERE aliases.FunderId = @FunderId AND aliases.IsActive = 1
                                    ORDER BY aliases.IsPrimary DESC, aliases.Id FOR JSON PATH)
                               ) AS aliases
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    );
                    INSERT INTO dbo.FundingPlatform_FunderVersions
                        (FunderId, ContentVersion, SnapshotJson, ContentHash, CreatedByUserId, CreatedAtUtc)
                    VALUES (@FunderId, @NextVersion, @SnapshotJson,
                            HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @SnapshotJson)),
                            @ActorUserId, @NowUtc);
                    INSERT INTO dbo.FundingPlatform_FunderEditorialEvents
                        (EventId, FunderId, ContentVersion, FromStatus, ToStatus, ActionCode,
                         ActorUserId, Reason, IdempotencyKeyHash, RequestHash, ResultRowVersion, CreatedAtUtc)
                    VALUES (@EventId, @FunderId, @NextVersion, @CurrentStatus, @CurrentStatus,
                            N'Update', @ActorUserId, NULL, @IdempotencyKeyHash,
                            @RequestHash, @RowVersion, @NowUtc);
                    INSERT INTO dbo.FundingPlatform_OutboxMessages
                        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                         OccurredAtUtc, AvailableAtUtc)
                    SELECT @EventId, N'FunderChanged', N'Funder', CONVERT(NVARCHAR(100), @FunderId),
                           (SELECT @EventId AS eventId, @FunderId AS funderId,
                                   @FunderPublicId AS funderPublicId, @NextVersion AS contentVersion
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                    SET @Succeeded = 1; SET @Code = N'updated';
                END;
            END;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_FunderUpdate;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, @FunderPublicId AS FunderPublicId,
           COALESCE(@NextVersion, @CurrentVersion) AS ContentVersion,
           @CurrentStatus AS PublicationStatus, COALESCE(@RowVersion, @CurrentRowVersion) AS RowVersion,
           @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Funder_RequestPublication
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FunderPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @ResultCode NVARCHAR(50) = NULL OUTPUT,
    @ResultCompleteness DECIMAL(5,2) = NULL OUTPUT,
    @OwnerWorkspace BIT = 0
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @OwnerWorkspace IS NULL THROW 51601, N'Invalid workspace scope.', 1;
    DECLARE @WorkspaceActorUserId BIGINT;
    IF @OwnerWorkspace = 1
        EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 1, @FunderPublicId, @WorkspaceActorUserId OUTPUT;
    ELSE
    BEGIN
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    END;

    DECLARE @Issues TABLE
    (
        Code NVARCHAR(50) NOT NULL,
        FieldPath NVARCHAR(100) NOT NULL,
        Message NVARCHAR(300) NOT NULL
    );
    DECLARE @ActorUserId BIGINT, @FunderId BIGINT, @ContentVersion INT;
    DECLARE @CurrentStatus TINYINT, @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @SubmittedAtUtc DATETIME2(3), @PublishedAtUtc DATETIME2(3), @ReviewedAtUtc DATETIME2(3);
    DECLARE @ReviewedByUserPublicId UNIQUEIDENTIFIER, @RejectionReason NVARCHAR(1000);
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Completeness DECIMAL(5,2) = 0;
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_FunderRequest;
    BEGIN TRY
        IF @OwnerWorkspace = 1
            EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 1, @FunderPublicId, @ActorUserId OUTPUT;
        ELSE
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @ActorUserId = Id FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;
        SELECT @FunderId = funders.Id, @ContentVersion = funders.ContentVersion,
               @CurrentStatus = funders.PublicationStatus,
               @CurrentRowVersion = funders.RowVersion,
               @SubmittedAtUtc = funders.SubmittedAtUtc,
               @PublishedAtUtc = funders.PublishedAtUtc,
               @ReviewedAtUtc = funders.ReviewedAtUtc,
               @ReviewedByUserPublicId = reviewers.PublicId,
               @RejectionReason = funders.RejectionReason
        FROM dbo.FundingPlatform_Funders AS funders WITH (UPDLOCK, HOLDLOCK)
        LEFT JOIN dbo.FundingPlatform_Users AS reviewers ON reviewers.Id = funders.ReviewedByUserId
        WHERE funders.PublicId = @FunderPublicId;

        IF @FunderId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = ActionCode, @ExistingRequestHash = RequestHash,
                   @ExistingToStatus = ToStatus, @ResultRowVersion = ResultRowVersion,
                   @ContentVersion = ContentVersion, @Completeness = ResultCompleteness,
                   @SubmittedAtUtc = ResultSubmittedAtUtc,
                   @PublishedAtUtc = ResultPublishedAtUtc,
                   @ReviewedAtUtc = ResultReviewedAtUtc,
                   @ReviewedByUserPublicId = ResultReviewedByUserPublicId,
                   @RejectionReason = ResultRejectionReason
            FROM dbo.FundingPlatform_FunderEditorialEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE FunderId = @FunderId AND IdempotencyKeyHash = @IdempotencyKeyHash;
            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'RequestPublication' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'review-requested';
                    SET @CurrentStatus = @ExistingToStatus;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus NOT IN (0, 3) SET @Code = N'invalid-transition';
            ELSE
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders
                               WHERE Id = @FunderId AND NULLIF(LTRIM(RTRIM(Name)), N'') IS NOT NULL)
                    INSERT INTO @Issues VALUES (N'name', N'name', N'Name is required.');
                IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders
                               WHERE Id = @FunderId AND NULLIF(LTRIM(RTRIM(Slug)), N'') IS NOT NULL)
                    INSERT INTO @Issues VALUES (N'slug', N'slug', N'A stable public slug is required.');
                IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Funders
                               WHERE Id = @FunderId AND NULLIF(LTRIM(RTRIM(WebsiteUrl)), N'') IS NOT NULL)
                    INSERT INTO @Issues VALUES (N'websiteUrl', N'websiteUrl', N'An official website is required.');
                IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FunderAliases
                               WHERE FunderId = @FunderId AND IsPrimary = 1 AND IsActive = 1)
                    INSERT INTO @Issues VALUES (N'primaryAlias', N'aliases', N'A primary alias is required.');
                SET @Completeness = CONVERT(DECIMAL(5,2), 100 - (SELECT COUNT(1) * 25 FROM @Issues));

                IF EXISTS (SELECT 1 FROM @Issues) SET @Code = N'funder-not-ready';
                ELSE
                BEGIN
                    DECLARE @Updated TABLE (RowVersion BINARY(8));
                    UPDATE dbo.FundingPlatform_Funders
                    SET PublicationStatus = 1, SubmittedAtUtc = @NowUtc,
                        ReviewedAtUtc = NULL, ReviewedByUserId = NULL,
                        RejectionReason = NULL, UpdatedByUserId = @ActorUserId,
                        UpdatedAtUtc = @NowUtc
                    OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
                    WHERE Id = @FunderId AND RowVersion = @ExpectedRowVersion;
                    SELECT @ResultRowVersion = RowVersion FROM @Updated;
                    IF @ResultRowVersion IS NULL SET @Code = N'etag-conflict';
                    ELSE
                    BEGIN
                        INSERT INTO dbo.FundingPlatform_FunderEditorialEvents
                            (EventId, FunderId, ContentVersion, FromStatus, ToStatus, ActionCode,
                             ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                             ResultRowVersion, ResultCompleteness, ResultSubmittedAtUtc,
                             ResultPublishedAtUtc, ResultReviewedAtUtc,
                             ResultReviewedByUserPublicId, ResultRejectionReason, CreatedAtUtc)
                        VALUES (@EventId, @FunderId, @ContentVersion, @CurrentStatus, 1,
                                N'RequestPublication', @ActorUserId, NULL, @IdempotencyKeyHash,
                                @RequestHash, @ResultRowVersion, 100, @NowUtc,
                                @PublishedAtUtc, NULL, NULL, NULL, @NowUtc);
                        INSERT INTO dbo.FundingPlatform_OutboxMessages
                            (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                             OccurredAtUtc, AvailableAtUtc)
                        SELECT @EventId, N'FunderPublicationRequested', N'Funder',
                               CONVERT(NVARCHAR(100), @FunderId),
                               (SELECT @EventId AS eventId, @FunderId AS funderId,
                                       @FunderPublicId AS funderPublicId, @ContentVersion AS contentVersion,
                                       @CurrentStatus AS fromStatus, 1 AS toStatus
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                        SET @Succeeded = 1; SET @Code = N'review-requested';
                        SET @CurrentStatus = 1; SET @SubmittedAtUtc = @NowUtc;
                        SET @ReviewedAtUtc = NULL; SET @ReviewedByUserPublicId = NULL;
                        SET @RejectionReason = NULL;
                    END;
                END;
            END;
        END;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_FunderRequest;
        THROW;
    END CATCH;

    SET @ResultCode = @Code; SET @ResultCompleteness = @Completeness;
    SELECT @Succeeded AS Succeeded, @Code AS Code, @Completeness AS Completeness,
           @FunderPublicId AS FunderPublicId, @ContentVersion AS ContentVersion,
           @CurrentStatus AS PublicationStatus, @SubmittedAtUtc AS SubmittedAtUtc,
           @PublishedAtUtc AS PublishedAtUtc, @ReviewedAtUtc AS ReviewedAtUtc,
           @ReviewedByUserPublicId AS ReviewedByUserPublicId,
           @RejectionReason AS RejectionReason,
           COALESCE(@ResultRowVersion, @CurrentRowVersion) AS RowVersion, @WasReplay AS WasReplay;
    SELECT Code, FieldPath, Message FROM @Issues ORDER BY FieldPath, Code;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Funder_StartCorrection
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FunderPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @Reason NVARCHAR(1000),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @OwnerWorkspace BIT = 0
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @OwnerWorkspace IS NULL THROW 51601, N'Invalid workspace scope.', 1;
    DECLARE @WorkspaceActorUserId BIGINT;
    IF @OwnerWorkspace = 1
        EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 1, @FunderPublicId, @WorkspaceActorUserId OUTPUT;
    ELSE
    BEGIN
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    END;

    DECLARE @NormalizedReason NVARCHAR(1000) = LTRIM(RTRIM(@Reason));
    IF LEN(COALESCE(@NormalizedReason, N'')) NOT BETWEEN 3 AND 1000
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               CAST(NULL AS DECIMAL(5,2)) AS Completeness,
               @FunderPublicId AS FunderPublicId, CAST(NULL AS INT) AS ContentVersion,
               CAST(NULL AS TINYINT) AS PublicationStatus,
               CAST(NULL AS DATETIME2(3)) AS SubmittedAtUtc,
               CAST(NULL AS DATETIME2(3)) AS PublishedAtUtc,
               CAST(NULL AS DATETIME2(3)) AS ReviewedAtUtc,
               CAST(NULL AS UNIQUEIDENTIFIER) AS ReviewedByUserPublicId,
               CAST(NULL AS NVARCHAR(1000)) AS RejectionReason,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    DECLARE @ActorUserId BIGINT, @FunderId BIGINT, @ContentVersion INT;
    DECLARE @CurrentStatus TINYINT, @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @SubmittedAtUtc DATETIME2(3), @PublishedAtUtc DATETIME2(3), @ReviewedAtUtc DATETIME2(3);
    DECLARE @ReviewedByUserPublicId UNIQUEIDENTIFIER, @CurrentRejectionReason NVARCHAR(1000);
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_FunderCorrection;
    BEGIN TRY
        IF @OwnerWorkspace = 1
            EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 1, @FunderPublicId, @ActorUserId OUTPUT;
        ELSE
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @FunderId = funders.Id, @ContentVersion = funders.ContentVersion,
               @CurrentStatus = funders.PublicationStatus,
               @CurrentRowVersion = funders.RowVersion,
               @SubmittedAtUtc = funders.SubmittedAtUtc,
               @PublishedAtUtc = funders.PublishedAtUtc,
               @ReviewedAtUtc = funders.ReviewedAtUtc,
               @ReviewedByUserPublicId = reviewers.PublicId,
               @CurrentRejectionReason = funders.RejectionReason
        FROM dbo.FundingPlatform_Funders AS funders WITH (UPDLOCK, HOLDLOCK)
        LEFT JOIN dbo.FundingPlatform_Users AS reviewers ON reviewers.Id = funders.ReviewedByUserId
        WHERE funders.PublicId = @FunderPublicId;

        IF @FunderId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = ActionCode, @ExistingRequestHash = RequestHash,
                   @ExistingToStatus = ToStatus, @ResultRowVersion = ResultRowVersion,
                   @ContentVersion = ContentVersion,
                   @SubmittedAtUtc = ResultSubmittedAtUtc,
                   @PublishedAtUtc = ResultPublishedAtUtc,
                   @ReviewedAtUtc = ResultReviewedAtUtc,
                   @ReviewedByUserPublicId = ResultReviewedByUserPublicId,
                   @CurrentRejectionReason = ResultRejectionReason
            FROM dbo.FundingPlatform_FunderEditorialEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE FunderId = @FunderId AND IdempotencyKeyHash = @IdempotencyKeyHash;

            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'StartCorrection' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1;
                    SET @Code = N'correction-started'; SET @CurrentStatus = @ExistingToStatus;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus <> 2 SET @Code = N'invalid-transition';
            ELSE
            BEGIN
                DECLARE @Updated TABLE (RowVersion BINARY(8));
                UPDATE dbo.FundingPlatform_Funders
                SET PublicationStatus = 0, SubmittedAtUtc = NULL, PublishedAtUtc = NULL,
                    ReviewedAtUtc = NULL, ReviewedByUserId = NULL, RejectionReason = NULL,
                    UpdatedByUserId = @ActorUserId, UpdatedAtUtc = @NowUtc
                OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
                WHERE Id = @FunderId AND RowVersion = @ExpectedRowVersion;
                SELECT @ResultRowVersion = RowVersion FROM @Updated;
                IF @ResultRowVersion IS NULL SET @Code = N'etag-conflict';
                ELSE
                BEGIN
                    INSERT INTO dbo.FundingPlatform_FunderEditorialEvents
                        (EventId, FunderId, ContentVersion, FromStatus, ToStatus, ActionCode,
                         ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                         ResultRowVersion, ResultCompleteness, ResultSubmittedAtUtc,
                         ResultPublishedAtUtc, ResultReviewedAtUtc,
                         ResultReviewedByUserPublicId, ResultRejectionReason, CreatedAtUtc)
                    VALUES (@EventId, @FunderId, @ContentVersion, 2, 0, N'StartCorrection',
                            @ActorUserId, @NormalizedReason, @IdempotencyKeyHash, @RequestHash,
                            @ResultRowVersion, NULL, NULL, NULL, NULL, NULL, NULL, @NowUtc);
                    INSERT INTO dbo.FundingPlatform_OutboxMessages
                        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                         OccurredAtUtc, AvailableAtUtc)
                    SELECT @EventId, N'FunderCorrectionStarted', N'Funder',
                           CONVERT(NVARCHAR(100), @FunderId),
                           (SELECT @EventId AS eventId, @FunderId AS funderId,
                                   @FunderPublicId AS funderPublicId,
                                   @ContentVersion AS contentVersion, 2 AS fromStatus, 0 AS toStatus
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                    SET @Succeeded = 1; SET @Code = N'correction-started'; SET @CurrentStatus = 0;
                    SET @SubmittedAtUtc = NULL; SET @PublishedAtUtc = NULL;
                    SET @ReviewedAtUtc = NULL; SET @ReviewedByUserPublicId = NULL;
                    SET @CurrentRejectionReason = NULL;
                END;
            END;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_FunderCorrection;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           CAST(NULL AS DECIMAL(5,2)) AS Completeness,
           @FunderPublicId AS FunderPublicId, @ContentVersion AS ContentVersion,
           @CurrentStatus AS PublicationStatus, @SubmittedAtUtc AS SubmittedAtUtc,
           @PublishedAtUtc AS PublishedAtUtc, @ReviewedAtUtc AS ReviewedAtUtc,
           @ReviewedByUserPublicId AS ReviewedByUserPublicId,
           @CurrentRejectionReason AS RejectionReason,
           COALESCE(@ResultRowVersion, @CurrentRowVersion) AS RowVersion,
           @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Funder_Deactivate
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FunderPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @Reason NVARCHAR(1000) = NULL,
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @OwnerWorkspace BIT = 0
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @OwnerWorkspace IS NULL THROW 51601, N'Invalid workspace scope.', 1;
    DECLARE @WorkspaceActorUserId BIGINT;
    IF @OwnerWorkspace = 1
        EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 1, @FunderPublicId, @WorkspaceActorUserId OUTPUT;
    ELSE
    BEGIN
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    END;

    DECLARE @ActorUserId BIGINT, @FunderId BIGINT, @ContentVersion INT;
    DECLARE @CurrentStatus TINYINT, @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @SubmittedAtUtc DATETIME2(3), @PublishedAtUtc DATETIME2(3), @ReviewedAtUtc DATETIME2(3);
    DECLARE @ReviewedByUserPublicId UNIQUEIDENTIFIER, @RejectionReason NVARCHAR(1000);
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_FunderDeactivate;
    BEGIN TRY
        IF @OwnerWorkspace = 1
            EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 1, @FunderPublicId, @ActorUserId OUTPUT;
        ELSE
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @ActorUserId = Id FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;
        SELECT @FunderId = funders.Id, @ContentVersion = funders.ContentVersion,
               @CurrentStatus = funders.PublicationStatus, @CurrentRowVersion = funders.RowVersion,
               @SubmittedAtUtc = funders.SubmittedAtUtc, @PublishedAtUtc = funders.PublishedAtUtc,
               @ReviewedAtUtc = funders.ReviewedAtUtc, @ReviewedByUserPublicId = reviewers.PublicId,
               @RejectionReason = funders.RejectionReason
        FROM dbo.FundingPlatform_Funders AS funders WITH (UPDLOCK, HOLDLOCK)
        LEFT JOIN dbo.FundingPlatform_Users AS reviewers ON reviewers.Id = funders.ReviewedByUserId
        WHERE funders.PublicId = @FunderPublicId;

        IF @FunderId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = ActionCode, @ExistingRequestHash = RequestHash,
                   @ExistingToStatus = ToStatus, @ResultRowVersion = ResultRowVersion,
                   @ContentVersion = ContentVersion,
                   @SubmittedAtUtc = ResultSubmittedAtUtc,
                   @PublishedAtUtc = ResultPublishedAtUtc,
                   @ReviewedAtUtc = ResultReviewedAtUtc,
                   @ReviewedByUserPublicId = ResultReviewedByUserPublicId,
                   @RejectionReason = ResultRejectionReason
            FROM dbo.FundingPlatform_FunderEditorialEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE FunderId = @FunderId AND IdempotencyKeyHash = @IdempotencyKeyHash;
            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'Deactivate' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'deactivated';
                    SET @CurrentStatus = @ExistingToStatus;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus NOT IN (0, 1, 2, 3) SET @Code = N'invalid-transition';
            ELSE
            BEGIN
                DECLARE @Updated TABLE (RowVersion BINARY(8));
                UPDATE dbo.FundingPlatform_Funders
                SET PublicationStatus = 4, IsActive = 0,
                    UpdatedByUserId = @ActorUserId, UpdatedAtUtc = @NowUtc
                OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
                WHERE Id = @FunderId AND RowVersion = @ExpectedRowVersion;
                SELECT @ResultRowVersion = RowVersion FROM @Updated;
                IF @ResultRowVersion IS NULL SET @Code = N'etag-conflict';
                ELSE
                BEGIN
                    INSERT INTO dbo.FundingPlatform_FunderEditorialEvents
                        (EventId, FunderId, ContentVersion, FromStatus, ToStatus, ActionCode,
                         ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                         ResultRowVersion, ResultCompleteness, ResultSubmittedAtUtc,
                         ResultPublishedAtUtc, ResultReviewedAtUtc,
                         ResultReviewedByUserPublicId, ResultRejectionReason, CreatedAtUtc)
                    VALUES (@EventId, @FunderId, @ContentVersion, @CurrentStatus, 4, N'Deactivate',
                            @ActorUserId, NULLIF(LTRIM(RTRIM(@Reason)), N''),
                            @IdempotencyKeyHash, @RequestHash, @ResultRowVersion, NULL,
                            @SubmittedAtUtc, @PublishedAtUtc, @ReviewedAtUtc,
                            @ReviewedByUserPublicId, @RejectionReason, @NowUtc);
                    INSERT INTO dbo.FundingPlatform_OutboxMessages
                        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                         OccurredAtUtc, AvailableAtUtc)
                    SELECT @EventId, N'FunderDeactivated', N'Funder', CONVERT(NVARCHAR(100), @FunderId),
                           (SELECT @EventId AS eventId, @FunderId AS funderId,
                                   @FunderPublicId AS funderPublicId, @ContentVersion AS contentVersion,
                                   @CurrentStatus AS fromStatus, 4 AS toStatus
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                    SET @Succeeded = 1; SET @Code = N'deactivated'; SET @CurrentStatus = 4;
                END;
            END;
        END;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_FunderDeactivate;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, CAST(NULL AS DECIMAL(5,2)) AS Completeness,
           @FunderPublicId AS FunderPublicId, @ContentVersion AS ContentVersion,
           @CurrentStatus AS PublicationStatus, @SubmittedAtUtc AS SubmittedAtUtc,
           @PublishedAtUtc AS PublishedAtUtc, @ReviewedAtUtc AS ReviewedAtUtc,
           @ReviewedByUserPublicId AS ReviewedByUserPublicId,
           @RejectionReason AS RejectionReason,
           COALESCE(@ResultRowVersion, @CurrentRowVersion) AS RowVersion, @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Admin_List
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @Query NVARCHAR(300) = NULL,
    @PublicationStatus TINYINT = NULL,
    @IncludeInactive BIT = 0,
    @PageNumber INT = 1,
    @PageSize INT = 50,
    @OwnerWorkspace BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    IF @OwnerWorkspace IS NULL THROW 51601, N'Invalid workspace scope.', 1;
    DECLARE @WorkspaceActorUserId BIGINT;
    IF @OwnerWorkspace = 1
        EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 2, NULL, @WorkspaceActorUserId OUTPUT;
    ELSE
    BEGIN
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    END;
    IF @PageNumber < 1 THROW 51603, N'PageNumber must be at least 1.', 1;
    IF @PageSize < 1 OR @PageSize > 100
        THROW 51604, N'PageSize must be between 1 and 100.', 1;
    IF @PublicationStatus IS NOT NULL AND @PublicationStatus NOT BETWEEN 0 AND 4
        THROW 51605, N'PublicationStatus is invalid.', 1;

    DECLARE @QueryLike NVARCHAR(302) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Query)), N'') IS NULL THEN NULL
             ELSE N'%' + LTRIM(RTRIM(@Query)) + N'%' END;

    SELECT COUNT_BIG(1) AS TotalCount
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    WHERE (@OwnerWorkspace = 0 OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_OpportunityWorkspaceOwners AS managed INNER JOIN dbo.FundingPlatform_FunderWorkspaceOwners AS owners ON owners.FunderId = managed.FunderId WHERE managed.FundingOpportunityId = opportunities.Id AND owners.UserId = @WorkspaceActorUserId AND owners.IsActive = 1))
      AND (@IncludeInactive = 1 OR opportunities.IsActive = 1)
      AND (@PublicationStatus IS NULL OR opportunities.PublicationStatus = @PublicationStatus)
      AND (@QueryLike IS NULL OR opportunities.Title LIKE @QueryLike
           OR opportunities.SponsorName LIKE @QueryLike OR opportunities.Slug LIKE @QueryLike);

    SELECT opportunities.PublicId AS FundingOpportunityPublicId,
           opportunities.Slug, opportunities.Title, opportunities.Summary,
           opportunities.SponsorName, opportunities.PublicationStatus,
           opportunities.IsActive, opportunities.OpenDate, opportunities.CloseDate,
           opportunities.Currency, opportunities.MinAmount, opportunities.MaxAmount,
           opportunities.DataQualityScore, opportunities.ContentVersion,
           opportunities.SubmittedAtUtc, opportunities.PublishedAtUtc,
           opportunities.ReviewedAtUtc, reviewers.PublicId AS ReviewedByUserPublicId,
           opportunities.RejectionReason, sourceLink.SourceName, sourceLink.SourceUrl,
           opportunities.LastVerifiedAtUtc, opportunities.CreatedAtUtc,
           opportunities.UpdatedAtUtc, opportunities.RowVersion
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    LEFT JOIN dbo.FundingPlatform_Users AS reviewers ON reviewers.Id = opportunities.ReviewedByUserId
    OUTER APPLY
    (
        SELECT TOP (1) sources.Name AS SourceName, links.SourceUrl
        FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
        INNER JOIN dbo.FundingPlatform_FundingSources AS sources ON sources.Id = links.FundingSourceId
        WHERE links.FundingOpportunityId = opportunities.Id AND links.IsActive = 1
        ORDER BY links.IsPrimary DESC, links.Id
    ) AS sourceLink
    WHERE (@OwnerWorkspace = 0 OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_OpportunityWorkspaceOwners AS managed INNER JOIN dbo.FundingPlatform_FunderWorkspaceOwners AS owners ON owners.FunderId = managed.FunderId WHERE managed.FundingOpportunityId = opportunities.Id AND owners.UserId = @WorkspaceActorUserId AND owners.IsActive = 1))
      AND (@IncludeInactive = 1 OR opportunities.IsActive = 1)
      AND (@PublicationStatus IS NULL OR opportunities.PublicationStatus = @PublicationStatus)
      AND (@QueryLike IS NULL OR opportunities.Title LIKE @QueryLike
           OR opportunities.SponsorName LIKE @QueryLike OR opportunities.Slug LIKE @QueryLike)
    ORDER BY opportunities.UpdatedAtUtc DESC, opportunities.Id DESC
    OFFSET ((@PageNumber - 1) * @PageSize) ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Admin_Get
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FundingOpportunityPublicId UNIQUEIDENTIFIER,
    @OwnerWorkspace BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    IF @OwnerWorkspace IS NULL THROW 51601, N'Invalid workspace scope.', 1;
    DECLARE @WorkspaceActorUserId BIGINT;
    IF @OwnerWorkspace = 1
        EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 2, @FundingOpportunityPublicId, @WorkspaceActorUserId OUTPUT;
    ELSE
    BEGIN
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    END;

    DECLARE @OpportunityId BIGINT;
    SELECT @OpportunityId = Id FROM dbo.FundingPlatform_FundingOpportunities
    WHERE PublicId = @FundingOpportunityPublicId;
    IF @OpportunityId IS NULL THROW 51608, N'Funding opportunity was not found.', 1;

    SELECT opportunities.PublicId AS FundingOpportunityPublicId,
           opportunities.Slug, opportunities.Title, opportunities.Description,
           opportunities.Summary, opportunities.SponsorName, opportunities.SponsorUrl,
           opportunities.ApplicationUrl, opportunities.IssuerCountryId,
           opportunities.FundingTypeId, opportunities.Currency,
           opportunities.MinAmount, opportunities.MaxAmount, opportunities.AmountStatus,
           opportunities.OpenDate, opportunities.CloseDate, opportunities.CloseAtUtc,
           opportunities.DeadlineTimeZoneId, opportunities.DeadlineType,
           opportunities.DeadlinePrecision, opportunities.EligibilityDescription,
           opportunities.Requirements, opportunities.Objectives,
           opportunities.AllowedActivities, opportunities.ExcludedActivities,
           opportunities.Restrictions, opportunities.TargetOrganizationsDescription,
           opportunities.TargetPopulationsDescription, opportunities.MinimumOperatingYears,
           opportunities.RequiresLegalEntity, opportunities.RequiresPriorExperience,
           opportunities.RequiresCofunding, opportunities.CofundingPercentage,
           opportunities.GeographicScope, opportunities.RemoteApplication,
           opportunities.PublicationStatus, opportunities.SubmittedAtUtc,
           opportunities.PublishedAtUtc, opportunities.ReviewedAtUtc,
           reviewers.PublicId AS ReviewedByUserPublicId, opportunities.RejectionReason,
           opportunities.LastVerifiedAtUtc, opportunities.DataQualityScore,
           opportunities.ContentVersion, opportunities.IsActive,
           opportunities.CreatedAtUtc, opportunities.UpdatedAtUtc, opportunities.RowVersion
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    LEFT JOIN dbo.FundingPlatform_Users AS reviewers ON reviewers.Id = opportunities.ReviewedByUserId
    WHERE opportunities.Id = @OpportunityId;

    SELECT links.CountryId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityCountries AS links
    INNER JOIN dbo.FundingPlatform_Countries AS countries
        ON countries.Id = links.CountryId AND countries.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.CountryId;
    SELECT links.RegionId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityRegions AS links
    INNER JOIN dbo.FundingPlatform_Regions AS regions
        ON regions.Id = links.RegionId AND regions.IsActive = 1
    INNER JOIN dbo.FundingPlatform_Countries AS countries
        ON countries.Id = regions.CountryId AND countries.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.RegionId;
    SELECT links.FundingCategoryId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityCategories AS links
    INNER JOIN dbo.FundingPlatform_FundingCategories AS categories
        ON categories.Id = links.FundingCategoryId AND categories.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.FundingCategoryId;
    SELECT links.BeneficiaryTypeId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes AS links
    INNER JOIN dbo.FundingPlatform_BeneficiaryTypes AS beneficiaryTypes
        ON beneficiaryTypes.Id = links.BeneficiaryTypeId AND beneficiaryTypes.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.BeneficiaryTypeId;
    SELECT links.ProjectTypeId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityProjectTypes AS links
    INNER JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
        ON projectTypes.Id = links.ProjectTypeId AND projectTypes.IsActive = 1
    WHERE links.FundingOpportunityId = @OpportunityId ORDER BY links.ProjectTypeId;

    SELECT funders.PublicId AS FunderPublicId, funders.Slug, funders.Name, links.Role
    FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
    INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
    WHERE links.FundingOpportunityId = @OpportunityId AND links.IsActive = 1
    ORDER BY links.Role, funders.Name, funders.Id;

    SELECT evidence.PublicId AS EvidencePublicId, evidence.FieldPath, evidence.ValueJson,
           evidence.ExtractionMethod, evidence.EvidenceText, evidence.SourceLocator,
           evidence.Confidence, evidence.IsSelected, evidence.IsManualLock,
           creators.PublicId AS CreatedByUserPublicId, evidence.CreatedAtUtc
    FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
    LEFT JOIN dbo.FundingPlatform_Users AS creators ON creators.Id = evidence.CreatedByUserId
    WHERE evidence.FundingOpportunityId = @OpportunityId
    ORDER BY evidence.FieldPath, evidence.IsSelected DESC, evidence.CreatedAtUtc DESC, evidence.Id DESC;

    SELECT links.FundingSourceId, sources.Name AS SourceName, links.ExternalId,
           links.SourceUrl, links.FirstSeenAtUtc, links.LastSeenAtUtc,
           links.IsPrimary, links.IsActive
    FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
    INNER JOIN dbo.FundingPlatform_FundingSources AS sources ON sources.Id = links.FundingSourceId
    WHERE links.FundingOpportunityId = @OpportunityId
    ORDER BY links.IsActive DESC, links.IsPrimary DESC, links.Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Create
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @Slug NVARCHAR(320), @Title NVARCHAR(350),
    @Description NVARCHAR(MAX) = NULL, @Summary NVARCHAR(2000) = NULL,
    @SponsorName NVARCHAR(300), @SponsorUrl NVARCHAR(2048) = NULL,
    @ApplicationUrl NVARCHAR(2048) = NULL, @IssuerCountryId SMALLINT = NULL,
    @FundingTypeId SMALLINT = NULL, @Currency CHAR(3) = NULL,
    @MinAmount DECIMAL(19,4) = NULL, @MaxAmount DECIMAL(19,4) = NULL,
    @AmountStatus TINYINT, @OpenDate DATE = NULL, @CloseDate DATE = NULL,
    @CloseAtUtc DATETIME2(3) = NULL, @DeadlineTimeZoneId NVARCHAR(100) = NULL,
    @DeadlineType TINYINT, @DeadlinePrecision TINYINT,
    @EligibilityDescription NVARCHAR(MAX) = NULL, @Requirements NVARCHAR(MAX) = NULL,
    @Objectives NVARCHAR(MAX) = NULL, @AllowedActivities NVARCHAR(MAX) = NULL,
    @ExcludedActivities NVARCHAR(MAX) = NULL, @Restrictions NVARCHAR(MAX) = NULL,
    @TargetOrganizationsDescription NVARCHAR(2000) = NULL,
    @TargetPopulationsDescription NVARCHAR(2000) = NULL,
    @MinimumOperatingYears SMALLINT = NULL, @RequiresLegalEntity BIT = NULL,
    @RequiresPriorExperience BIT = NULL, @RequiresCofunding BIT = NULL,
    @CofundingPercentage DECIMAL(5,2) = NULL, @GeographicScope TINYINT,
    @RemoteApplication TINYINT, @LastVerifiedAtUtc DATETIME2(3) = NULL,
    @DataQualityScore DECIMAL(5,2),
    @FundingSourceId INT, @ExternalId NVARCHAR(250) = NULL,
    @SourceItemKeyHash BINARY(32), @SourceUrl NVARCHAR(2048),
    @CanonicalUrlHash BINARY(32) = NULL,
    @SnapshotJson NVARCHAR(MAX), @ContentHash BINARY(32),
    @CountryIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @RegionIds dbo.FundingPlatform_IntIdList READONLY,
    @CategoryIds dbo.FundingPlatform_IntIdList READONLY,
    @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @FunderLinksJson NVARCHAR(MAX), @EvidenceJson NVARCHAR(MAX) = N'[]',
    @IdempotencyKeyHash BINARY(32), @RequestHash BINARY(32),
    @OwnerWorkspace BIT = 0
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @OwnerWorkspace IS NULL THROW 51601, N'Invalid workspace scope.', 1;
    DECLARE @WorkspaceActorUserId BIGINT;
    IF @OwnerWorkspace = 1
        EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 2, NULL, @WorkspaceActorUserId OUTPUT;
    ELSE
    BEGIN
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    END;
    IF ISJSON(@SnapshotJson) <> 1 OR LEFT(LTRIM(@SnapshotJson), 1) <> N'{'
        THROW 51609, N'SnapshotJson must be a JSON object.', 1;
    IF ISJSON(COALESCE(@FunderLinksJson, N'[]')) <> 1
       OR LEFT(LTRIM(COALESCE(@FunderLinksJson, N'[]')), 1) <> N'['
        THROW 51610, N'FunderLinksJson must be a JSON array.', 1;
    IF ISJSON(COALESCE(@EvidenceJson, N'[]')) <> 1
       OR LEFT(LTRIM(COALESCE(@EvidenceJson, N'[]')), 1) <> N'['
        THROW 51611, N'EvidenceJson must be a JSON array.', 1;

    DECLARE @ActorUserId BIGINT, @OpportunityId BIGINT, @OpportunityPublicId UNIQUEIDENTIFIER;
    DECLARE @RowVersion BINARY(8), @ExistingRequestHash BINARY(32), @SourceLinkId BIGINT;
    DECLARE @Code NVARCHAR(50) = N'created', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @RawFunderCount INT =
        (SELECT COUNT(1) FROM OPENJSON(COALESCE(@FunderLinksJson, N'[]')));
    DECLARE @RawEvidenceCount INT =
        (SELECT COUNT(1) FROM OPENJSON(COALESCE(@EvidenceJson, N'[]')));
    DECLARE @RequestedFunders TABLE
    (
        FunderPublicId UNIQUEIDENTIFIER NOT NULL,
        Role TINYINT NOT NULL,
        FunderId BIGINT NULL,
        PRIMARY KEY (FunderPublicId)
    );
    DECLARE @ExtraEvidence TABLE
    (
        FieldPath NVARCHAR(200) NOT NULL PRIMARY KEY,
        ValueJson NVARCHAR(MAX) NOT NULL,
        EvidenceText NVARCHAR(2000) NULL,
        SourceLocator NVARCHAR(500) NULL,
        Confidence DECIMAL(5,2) NULL,
        IsManualLock BIT NOT NULL
    );

    INSERT INTO @RequestedFunders (FunderPublicId, Role)
    SELECT TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(items.value, '$.funderPublicId')),
           MIN(TRY_CONVERT(TINYINT, JSON_VALUE(items.value, '$.role')))
    FROM OPENJSON(COALESCE(@FunderLinksJson, N'[]')) AS items
    WHERE TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(items.value, '$.funderPublicId')) IS NOT NULL
      AND TRY_CONVERT(TINYINT, JSON_VALUE(items.value, '$.role')) BETWEEN 1 AND 3
    GROUP BY TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(items.value, '$.funderPublicId'))
    HAVING COUNT_BIG(1) = 1;

    INSERT INTO @ExtraEvidence
        (FieldPath, ValueJson, EvidenceText, SourceLocator, Confidence, IsManualLock)
    SELECT JSON_VALUE(items.value, '$.fieldPath'),
           MAX(JSON_QUERY(items.value, '$.valueJson')),
           MAX(JSON_VALUE(items.value, '$.evidenceText')),
           MAX(JSON_VALUE(items.value, '$.sourceLocator')),
           MAX(TRY_CONVERT(DECIMAL(5,2), JSON_VALUE(items.value, '$.confidence'))),
           MAX(CONVERT(TINYINT,
               COALESCE(TRY_CONVERT(BIT, JSON_VALUE(items.value, '$.isManualLock')), 1)))
    FROM OPENJSON(COALESCE(@EvidenceJson, N'[]')) AS items
    WHERE LEFT(JSON_VALUE(items.value, '$.fieldPath'), 1) = N'/'
      AND LEN(JSON_VALUE(items.value, '$.fieldPath')) BETWEEN 2 AND 200
      AND JSON_QUERY(items.value, '$.valueJson') IS NOT NULL
      AND LEFT(LTRIM(JSON_QUERY(items.value, '$.valueJson')), 1) = N'{'
      AND (JSON_VALUE(items.value, '$.evidenceText') IS NULL
           OR LEN(JSON_VALUE(items.value, '$.evidenceText')) <= 2000)
      AND (JSON_VALUE(items.value, '$.sourceLocator') IS NULL
           OR LEN(JSON_VALUE(items.value, '$.sourceLocator')) <= 500)
      AND (JSON_VALUE(items.value, '$.confidence') IS NULL
           OR TRY_CONVERT(DECIMAL(5,2), JSON_VALUE(items.value, '$.confidence')) BETWEEN 0 AND 100)
      AND (JSON_VALUE(items.value, '$.isManualLock') IS NULL
           OR TRY_CONVERT(BIT, JSON_VALUE(items.value, '$.isManualLock')) IS NOT NULL)
      AND JSON_VALUE(items.value, '$.fieldPath') NOT IN
          (N'/title', N'/description', N'/eligibilityDescription', N'/closeDate', N'/sponsorName')
    GROUP BY JSON_VALUE(items.value, '$.fieldPath')
    HAVING COUNT_BIG(1) = 1;

    IF NULLIF(LTRIM(RTRIM(@Slug)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@Title)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@SponsorName)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@SourceUrl)), N'') IS NULL
       OR @RawFunderCount <> (SELECT COUNT(1) FROM @RequestedFunders)
       OR @RawEvidenceCount <> (SELECT COUNT(1) FROM @ExtraEvidence)
       OR (SELECT COUNT(1) FROM @RequestedFunders WHERE Role = 1) <> 1
       OR @AmountStatus NOT BETWEEN 0 AND 2
       OR (@AmountStatus = 1 AND (@Currency IS NULL OR (@MinAmount IS NULL AND @MaxAmount IS NULL)))
       OR (@AmountStatus IN (0, 2) AND (@Currency IS NOT NULL OR @MinAmount IS NOT NULL OR @MaxAmount IS NOT NULL))
       OR @MinAmount < 0 OR @MaxAmount < COALESCE(@MinAmount, 0)
       OR @DeadlineType NOT BETWEEN 0 AND 2 OR @DeadlinePrecision NOT BETWEEN 0 AND 2
       OR (@DeadlineType = 0 AND (@DeadlinePrecision <> 0 OR @CloseAtUtc IS NOT NULL))
       OR (@DeadlineType = 2 AND (@DeadlinePrecision <> 0 OR @CloseDate IS NOT NULL OR @CloseAtUtc IS NOT NULL))
       OR (@DeadlineType = 1 AND @DeadlinePrecision NOT IN (1, 2))
       OR (@DeadlineType = 1 AND @DeadlinePrecision = 1 AND (@CloseDate IS NULL OR @CloseAtUtc IS NOT NULL))
       OR (@DeadlineType = 1 AND @DeadlinePrecision = 2
           AND (@CloseDate IS NULL OR @CloseAtUtc IS NULL OR @DeadlineTimeZoneId IS NULL))
       OR (@OpenDate IS NOT NULL AND @CloseDate IS NOT NULL AND @OpenDate > @CloseDate)
       OR @GeographicScope NOT BETWEEN 0 AND 2 OR @RemoteApplication NOT BETWEEN 0 AND 2
       OR (@GeographicScope = 0
           AND (EXISTS (SELECT 1 FROM @CountryIds) OR EXISTS (SELECT 1 FROM @RegionIds)))
       OR (@GeographicScope = 1 AND NOT EXISTS (SELECT 1 FROM @CountryIds))
       OR (@GeographicScope = 2
           AND (EXISTS (SELECT 1 FROM @CountryIds) OR EXISTS (SELECT 1 FROM @RegionIds)))
       OR @DataQualityScore NOT BETWEEN 0 AND 100
       OR @MinimumOperatingYears < 0
       OR @CofundingPercentage < 0 OR @CofundingPercentage > 100
       OR (@RequiresCofunding IS NULL AND @CofundingPercentage IS NOT NULL)
       OR (@RequiresCofunding = 0 AND COALESCE(@CofundingPercentage, 0) <> 0)
       OR (@RequiresCofunding = 1 AND COALESCE(@CofundingPercentage, 0) <= 0)
       OR (@LastVerifiedAtUtc IS NOT NULL
           AND @LastVerifiedAtUtc > DATEADD(MINUTE, 5, SYSUTCDATETIME()))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               CAST(NULL AS UNIQUEIDENTIFIER) AS FundingOpportunityPublicId,
               CAST(NULL AS INT) AS ContentVersion, CAST(NULL AS TINYINT) AS PublicationStatus,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_OppCreate;
    BEGIN TRY
        IF @OwnerWorkspace = 1
            EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 2, NULL, @ActorUserId OUTPUT;
        ELSE
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        IF @OwnerWorkspace = 1
        BEGIN
            /* Native submission provenance and exactly one owned primary funder.
               Existing/imported records cannot be adopted through a link or a replay. */
            IF (SELECT COUNT_BIG(1) FROM @RequestedFunders) <> 1
               OR NOT EXISTS (SELECT 1 FROM @RequestedFunders AS requested
                   INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.PublicId = requested.FunderPublicId
                   INNER JOIN dbo.FundingPlatform_FunderWorkspaceOwners AS owners WITH (UPDLOCK, HOLDLOCK) ON owners.FunderId = funders.Id
                   WHERE requested.Role = 1 AND owners.UserId = @ActorUserId AND owners.IsActive = 1)
               OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingSources WHERE Id = @FundingSourceId AND ProviderCode = N'funder-workspace' AND IsEnabled = 1)
                THROW 51601, N'Workspace funder or source is not permitted.', 1;
        END;
        SELECT @ActorUserId = Id FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;
        SELECT @OpportunityId = events.FundingOpportunityId,
               @ExistingRequestHash = events.RequestHash, @RowVersion = events.ResultRowVersion
        FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents AS events WITH (UPDLOCK, HOLDLOCK)
        WHERE events.ActorUserId = @ActorUserId AND events.ActionCode = N'Create'
          AND events.IdempotencyKeyHash = @IdempotencyKeyHash;

        IF @OpportunityId IS NOT NULL
        BEGIN
            IF @OwnerWorkspace = 1 AND NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_OpportunityWorkspaceOwners AS managed INNER JOIN dbo.FundingPlatform_FunderWorkspaceOwners AS owners ON owners.FunderId = managed.FunderId WHERE managed.FundingOpportunityId = @OpportunityId AND owners.UserId = @ActorUserId AND owners.IsActive = 1)
                THROW 51601, N'Workspace access is not available.', 1;
            SELECT @OpportunityPublicId = PublicId
            FROM dbo.FundingPlatform_FundingOpportunities WHERE Id = @OpportunityId;
            IF @ExistingRequestHash = @RequestHash
            BEGIN
                SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'created';
            END
            ELSE SET @Code = N'idempotency-conflict';
        END
        ELSE
        BEGIN
            UPDATE requested SET FunderId = funders.Id
            FROM @RequestedFunders AS requested
            INNER JOIN dbo.FundingPlatform_Funders AS funders WITH (UPDLOCK, HOLDLOCK)
                ON funders.PublicId = requested.FunderPublicId
               AND funders.IsActive = 1 AND funders.PublicationStatus <> 4;

            IF EXISTS (SELECT 1 FROM @RequestedFunders WHERE FunderId IS NULL)
                SET @Code = N'funder-not-found';
            ELSE IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingSources
                                WHERE Id = @FundingSourceId AND IsEnabled = 1)
                SET @Code = N'source-disabled';
            ELSE IF (@IssuerCountryId IS NOT NULL AND NOT EXISTS
                     (SELECT 1 FROM dbo.FundingPlatform_Countries
                      WHERE Id = @IssuerCountryId AND IsActive = 1))
                 OR (@FundingTypeId IS NOT NULL AND NOT EXISTS
                     (SELECT 1 FROM dbo.FundingPlatform_FundingTypes
                      WHERE Id = @FundingTypeId AND IsActive = 1))
                 OR (@Currency IS NOT NULL AND NOT EXISTS
                     (SELECT 1 FROM dbo.FundingPlatform_Currencies
                      WHERE Code = @Currency AND IsActive = 1))
                 OR EXISTS (SELECT 1 FROM @CountryIds AS selected
                            LEFT JOIN dbo.FundingPlatform_Countries AS catalog
                                ON catalog.Id = selected.Id AND catalog.IsActive = 1
                            WHERE catalog.Id IS NULL)
                 OR EXISTS (SELECT 1 FROM @CategoryIds AS selected
                            LEFT JOIN dbo.FundingPlatform_FundingCategories AS catalog
                                ON catalog.Id = selected.Id AND catalog.IsActive = 1
                            WHERE catalog.Id IS NULL)
                 OR EXISTS (SELECT 1 FROM @BeneficiaryTypeIds AS selected
                            LEFT JOIN dbo.FundingPlatform_BeneficiaryTypes AS catalog
                                ON catalog.Id = selected.Id AND catalog.IsActive = 1
                            WHERE catalog.Id IS NULL)
                 OR EXISTS (SELECT 1 FROM @ProjectTypeIds AS selected
                            LEFT JOIN dbo.FundingPlatform_ProjectTypes AS catalog
                                ON catalog.Id = selected.Id AND catalog.IsActive = 1
                            WHERE catalog.Id IS NULL)
                SET @Code = N'invalid-document';
            ELSE IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WITH (UPDLOCK, HOLDLOCK)
                            WHERE Slug = LTRIM(RTRIM(@Slug)))
                SET @Code = N'slug-conflict';
            ELSE IF EXISTS
            (
                SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks WITH (UPDLOCK, HOLDLOCK)
                WHERE FundingSourceId = @FundingSourceId
                  AND (SourceItemKeyHash = @SourceItemKeyHash
                       OR (@ExternalId IS NOT NULL AND ExternalId = @ExternalId))
            ) SET @Code = N'source-link-conflict';
            ELSE IF EXISTS
            (
                SELECT 1 FROM @RegionIds AS selected
                LEFT JOIN dbo.FundingPlatform_Regions AS regions
                    ON regions.Id = selected.Id AND regions.IsActive = 1
                WHERE regions.Id IS NULL
                   OR NOT EXISTS (SELECT 1 FROM @CountryIds AS countries WHERE countries.Id = regions.CountryId)
            ) SET @Code = N'invalid-document';
            ELSE
            BEGIN
                DECLARE @InsertedOpportunity TABLE
                    (Id BIGINT, PublicId UNIQUEIDENTIFIER, RowVersion BINARY(8));
                INSERT INTO dbo.FundingPlatform_FundingOpportunities
                (
                    Slug, Title, Description, Summary, SponsorName, SponsorUrl, ApplicationUrl,
                    IssuerCountryId, FundingTypeId, Currency, MinAmount, MaxAmount, AmountStatus,
                    OpenDate, CloseDate, CloseAtUtc, DeadlineTimeZoneId, DeadlineType,
                    DeadlinePrecision, EligibilityDescription, Requirements, Objectives,
                    AllowedActivities, ExcludedActivities, Restrictions,
                    TargetOrganizationsDescription, TargetPopulationsDescription,
                    MinimumOperatingYears, RequiresLegalEntity, RequiresPriorExperience,
                    RequiresCofunding, CofundingPercentage, GeographicScope, RemoteApplication,
                    PublicationStatus, PublishedAtUtc, LastVerifiedAtUtc, DataQualityScore,
                    ContentVersion, ContentFingerprint, IsActive, CreatedByUserId, UpdatedByUserId,
                    CreatedAtUtc, UpdatedAtUtc
                )
                OUTPUT inserted.Id, inserted.PublicId, inserted.RowVersion
                    INTO @InsertedOpportunity (Id, PublicId, RowVersion)
                VALUES
                (
                    LTRIM(RTRIM(@Slug)), LTRIM(RTRIM(@Title)), @Description, @Summary,
                    LTRIM(RTRIM(@SponsorName)), @SponsorUrl, @ApplicationUrl,
                    @IssuerCountryId, @FundingTypeId, @Currency, @MinAmount, @MaxAmount,
                    @AmountStatus, @OpenDate, @CloseDate, @CloseAtUtc, @DeadlineTimeZoneId,
                    @DeadlineType, @DeadlinePrecision, @EligibilityDescription, @Requirements,
                    @Objectives, @AllowedActivities, @ExcludedActivities, @Restrictions,
                    @TargetOrganizationsDescription, @TargetPopulationsDescription,
                    @MinimumOperatingYears, @RequiresLegalEntity, @RequiresPriorExperience,
                    @RequiresCofunding, @CofundingPercentage, @GeographicScope,
                    @RemoteApplication, 0, NULL, COALESCE(@LastVerifiedAtUtc, @NowUtc),
                    @DataQualityScore, 1,
                    @ContentHash, 1, @ActorUserId, @ActorUserId, @NowUtc, @NowUtc
                );
                SELECT @OpportunityId = Id, @OpportunityPublicId = PublicId, @RowVersion = RowVersion
                FROM @InsertedOpportunity;
                IF @OwnerWorkspace = 1
                    INSERT INTO dbo.FundingPlatform_OpportunityWorkspaceOwners(FundingOpportunityId, FunderId)
                    SELECT @OpportunityId, FunderId FROM @RequestedFunders WHERE Role = 1;

                DECLARE @InsertedSourceLink TABLE (Id BIGINT);
                INSERT INTO dbo.FundingPlatform_FundingOpportunitySourceLinks
                    (FundingOpportunityId, FundingSourceId, ExternalId, SourceItemKeyHash,
                     SourceUrl, CanonicalUrlHash, FirstSeenAtUtc, LastSeenAtUtc, IsPrimary, IsActive)
                OUTPUT inserted.Id INTO @InsertedSourceLink (Id)
                VALUES (@OpportunityId, @FundingSourceId, @ExternalId, @SourceItemKeyHash,
                        @SourceUrl, @CanonicalUrlHash, @NowUtc, @NowUtc, 1, 1);
                SELECT @SourceLinkId = Id FROM @InsertedSourceLink;

                INSERT INTO dbo.FundingPlatform_FundingOpportunityCountries
                    (FundingOpportunityId, CountryId)
                SELECT @OpportunityId, Id FROM @CountryIds;
                INSERT INTO dbo.FundingPlatform_FundingOpportunityRegions
                    (FundingOpportunityId, RegionId)
                SELECT @OpportunityId, Id FROM @RegionIds;
                INSERT INTO dbo.FundingPlatform_FundingOpportunityCategories
                    (FundingOpportunityId, FundingCategoryId)
                SELECT @OpportunityId, Id FROM @CategoryIds;
                INSERT INTO dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes
                    (FundingOpportunityId, BeneficiaryTypeId)
                SELECT @OpportunityId, Id FROM @BeneficiaryTypeIds;
                INSERT INTO dbo.FundingPlatform_FundingOpportunityProjectTypes
                    (FundingOpportunityId, ProjectTypeId)
                SELECT @OpportunityId, Id FROM @ProjectTypeIds;

                DECLARE @CriticalEvidence TABLE
                    (FieldPath NVARCHAR(200), ValueText NVARCHAR(MAX), StatusCode NVARCHAR(20),
                     EvidenceText NVARCHAR(2000));
                INSERT INTO @CriticalEvidence VALUES
                    (N'/title', @Title, N'known', LEFT(@Title, 2000)),
                    (N'/description', @Description,
                     CASE WHEN NULLIF(LTRIM(RTRIM(@Description)), N'') IS NULL THEN N'unknown' ELSE N'known' END,
                     LEFT(@Description, 2000)),
                    (N'/eligibilityDescription', @EligibilityDescription,
                     CASE WHEN NULLIF(LTRIM(RTRIM(@EligibilityDescription)), N'') IS NULL THEN N'unknown' ELSE N'known' END,
                     LEFT(@EligibilityDescription, 2000)),
                    (N'/closeDate', CONVERT(NVARCHAR(30), @CloseDate, 23),
                     CASE WHEN @CloseDate IS NULL THEN N'unknown' ELSE N'known' END,
                     CONVERT(NVARCHAR(30), @CloseDate, 23)),
                    (N'/sponsorName', @SponsorName, N'known', LEFT(@SponsorName, 2000));
                INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
                    (FundingOpportunityId, FieldPath, ValueJson, FundingOpportunitySourceLinkId,
                     ExtractionMethod, EvidenceText, SourceLocator, Confidence,
                     IsSelected, IsManualLock, CreatedByUserId, CreatedAtUtc)
                SELECT @OpportunityId, critical.FieldPath,
                       (SELECT critical.ValueText AS [value], critical.StatusCode AS [status]
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
                       @SourceLinkId, 1, critical.EvidenceText, LEFT(@SourceUrl, 500),
                       100, 1, 1, @ActorUserId, @NowUtc
                FROM @CriticalEvidence AS critical;
                INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
                    (FundingOpportunityId, FieldPath, ValueJson, FundingOpportunitySourceLinkId,
                     ExtractionMethod, EvidenceText, SourceLocator, Confidence,
                     IsSelected, IsManualLock, CreatedByUserId, CreatedAtUtc)
                SELECT @OpportunityId, extra.FieldPath, extra.ValueJson, @SourceLinkId, 1,
                       extra.EvidenceText, COALESCE(extra.SourceLocator, LEFT(@SourceUrl, 500)),
                       extra.Confidence, 1, extra.IsManualLock, @ActorUserId, @NowUtc
                FROM @ExtraEvidence AS extra;

                DECLARE @SponsorEvidenceId BIGINT =
                    (SELECT Id FROM dbo.FundingPlatform_FundingFieldEvidence
                     WHERE FundingOpportunityId = @OpportunityId
                       AND FieldPath = N'/sponsorName' AND IsSelected = 1);
                INSERT INTO dbo.FundingPlatform_FundingOpportunityFunders
                    (FundingOpportunityId, FunderId, Role, EvidenceId, IsActive,
                     CreatedAtUtc, UpdatedAtUtc)
                SELECT @OpportunityId, FunderId, Role,
                       CASE WHEN Role = 1 THEN @SponsorEvidenceId ELSE NULL END,
                       1, @NowUtc, @NowUtc
                FROM @RequestedFunders;

                INSERT INTO dbo.FundingPlatform_FundingOpportunityVersions
                    (FundingOpportunityId, ContentVersion, SnapshotJson, ContentHash,
                     CreatedByUserId, CreatedAtUtc)
                VALUES (@OpportunityId, 1, @SnapshotJson, @ContentHash, @ActorUserId, @NowUtc);
                INSERT INTO dbo.FundingPlatform_FundingOpportunityEditorialEvents
                    (EventId, FundingOpportunityId, ContentVersion, FromStatus, ToStatus,
                     ActionCode, ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                     ResultRowVersion, CreatedAtUtc)
                VALUES (@EventId, @OpportunityId, 1, 0, 0, N'Create', @ActorUserId, NULL,
                        @IdempotencyKeyHash, @RequestHash, @RowVersion, @NowUtc);
                INSERT INTO dbo.FundingPlatform_OutboxMessages
                    (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                     OccurredAtUtc, AvailableAtUtc)
                SELECT @EventId, N'FundingOpportunityDraftCreated', N'FundingOpportunity',
                       CONVERT(NVARCHAR(100), @OpportunityId),
                       (SELECT @EventId AS eventId, @OpportunityId AS fundingOpportunityId,
                               @OpportunityPublicId AS fundingOpportunityPublicId, 1 AS contentVersion
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                SET @Succeeded = 1; SET @Code = N'created';
            END;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_OppCreate;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @OpportunityPublicId AS FundingOpportunityPublicId,
           CASE WHEN @OpportunityId IS NULL THEN NULL ELSE 1 END AS ContentVersion,
           CASE WHEN @OpportunityId IS NULL THEN NULL ELSE 0 END AS PublicationStatus,
           @RowVersion AS RowVersion, @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Update
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FundingOpportunityPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @Title NVARCHAR(350), @Description NVARCHAR(MAX) = NULL,
    @Summary NVARCHAR(2000) = NULL, @SponsorName NVARCHAR(300),
    @SponsorUrl NVARCHAR(2048) = NULL, @ApplicationUrl NVARCHAR(2048) = NULL,
    @IssuerCountryId SMALLINT = NULL, @FundingTypeId SMALLINT = NULL,
    @Currency CHAR(3) = NULL, @MinAmount DECIMAL(19,4) = NULL,
    @MaxAmount DECIMAL(19,4) = NULL, @AmountStatus TINYINT,
    @OpenDate DATE = NULL, @CloseDate DATE = NULL, @CloseAtUtc DATETIME2(3) = NULL,
    @DeadlineTimeZoneId NVARCHAR(100) = NULL, @DeadlineType TINYINT,
    @DeadlinePrecision TINYINT, @EligibilityDescription NVARCHAR(MAX) = NULL,
    @Requirements NVARCHAR(MAX) = NULL, @Objectives NVARCHAR(MAX) = NULL,
    @AllowedActivities NVARCHAR(MAX) = NULL, @ExcludedActivities NVARCHAR(MAX) = NULL,
    @Restrictions NVARCHAR(MAX) = NULL,
    @TargetOrganizationsDescription NVARCHAR(2000) = NULL,
    @TargetPopulationsDescription NVARCHAR(2000) = NULL,
    @MinimumOperatingYears SMALLINT = NULL, @RequiresLegalEntity BIT = NULL,
    @RequiresPriorExperience BIT = NULL, @RequiresCofunding BIT = NULL,
    @CofundingPercentage DECIMAL(5,2) = NULL, @GeographicScope TINYINT,
    @RemoteApplication TINYINT, @LastVerifiedAtUtc DATETIME2(3) = NULL,
    @DataQualityScore DECIMAL(5,2),
    @FundingSourceId INT, @ExternalId NVARCHAR(250) = NULL,
    @SourceItemKeyHash BINARY(32), @SourceUrl NVARCHAR(2048),
    @CanonicalUrlHash BINARY(32) = NULL,
    @SnapshotJson NVARCHAR(MAX), @ContentHash BINARY(32),
    @CountryIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @RegionIds dbo.FundingPlatform_IntIdList READONLY,
    @CategoryIds dbo.FundingPlatform_IntIdList READONLY,
    @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @FunderLinksJson NVARCHAR(MAX), @EvidenceJson NVARCHAR(MAX) = N'[]',
    @IdempotencyKeyHash BINARY(32), @RequestHash BINARY(32),
    @OwnerWorkspace BIT = 0
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @OwnerWorkspace IS NULL THROW 51601, N'Invalid workspace scope.', 1;
    DECLARE @WorkspaceActorUserId BIGINT;
    IF @OwnerWorkspace = 1
        EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 2, @FundingOpportunityPublicId, @WorkspaceActorUserId OUTPUT;
    ELSE
    BEGIN
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    END;
    IF ISJSON(@SnapshotJson) <> 1 OR LEFT(LTRIM(@SnapshotJson), 1) <> N'{'
        THROW 51609, N'SnapshotJson must be a JSON object.', 1;
    IF ISJSON(COALESCE(@FunderLinksJson, N'[]')) <> 1
       OR LEFT(LTRIM(COALESCE(@FunderLinksJson, N'[]')), 1) <> N'['
        THROW 51610, N'FunderLinksJson must be a JSON array.', 1;
    IF ISJSON(COALESCE(@EvidenceJson, N'[]')) <> 1
       OR LEFT(LTRIM(COALESCE(@EvidenceJson, N'[]')), 1) <> N'['
        THROW 51611, N'EvidenceJson must be a JSON array.', 1;

    DECLARE @ActorUserId BIGINT, @OpportunityId BIGINT, @CurrentSlug NVARCHAR(320);
    DECLARE @CurrentStatus TINYINT, @CurrentVersion INT, @NextVersion INT;
    DECLARE @CurrentRowVersion BINARY(8), @RowVersion BINARY(8), @SourceLinkId BIGINT;
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @RawFunderCount INT =
        (SELECT COUNT(1) FROM OPENJSON(COALESCE(@FunderLinksJson, N'[]')));
    DECLARE @RawEvidenceCount INT =
        (SELECT COUNT(1) FROM OPENJSON(COALESCE(@EvidenceJson, N'[]')));
    DECLARE @RequestedFunders TABLE
    (
        FunderPublicId UNIQUEIDENTIFIER NOT NULL,
        Role TINYINT NOT NULL,
        FunderId BIGINT NULL,
        PRIMARY KEY (FunderPublicId)
    );
    DECLARE @ExtraEvidence TABLE
    (
        FieldPath NVARCHAR(200) NOT NULL PRIMARY KEY,
        ValueJson NVARCHAR(MAX) NOT NULL,
        EvidenceText NVARCHAR(2000) NULL,
        SourceLocator NVARCHAR(500) NULL,
        Confidence DECIMAL(5,2) NULL,
        IsManualLock BIT NOT NULL
    );

    INSERT INTO @RequestedFunders (FunderPublicId, Role)
    SELECT TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(items.value, '$.funderPublicId')),
           MIN(TRY_CONVERT(TINYINT, JSON_VALUE(items.value, '$.role')))
    FROM OPENJSON(COALESCE(@FunderLinksJson, N'[]')) AS items
    WHERE TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(items.value, '$.funderPublicId')) IS NOT NULL
      AND TRY_CONVERT(TINYINT, JSON_VALUE(items.value, '$.role')) BETWEEN 1 AND 3
    GROUP BY TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(items.value, '$.funderPublicId'))
    HAVING COUNT_BIG(1) = 1;

    INSERT INTO @ExtraEvidence
        (FieldPath, ValueJson, EvidenceText, SourceLocator, Confidence, IsManualLock)
    SELECT JSON_VALUE(items.value, '$.fieldPath'),
           MAX(JSON_QUERY(items.value, '$.valueJson')),
           MAX(JSON_VALUE(items.value, '$.evidenceText')),
           MAX(JSON_VALUE(items.value, '$.sourceLocator')),
           MAX(TRY_CONVERT(DECIMAL(5,2), JSON_VALUE(items.value, '$.confidence'))),
           MAX(CONVERT(TINYINT,
               COALESCE(TRY_CONVERT(BIT, JSON_VALUE(items.value, '$.isManualLock')), 1)))
    FROM OPENJSON(COALESCE(@EvidenceJson, N'[]')) AS items
    WHERE LEFT(JSON_VALUE(items.value, '$.fieldPath'), 1) = N'/'
      AND LEN(JSON_VALUE(items.value, '$.fieldPath')) BETWEEN 2 AND 200
      AND JSON_QUERY(items.value, '$.valueJson') IS NOT NULL
      AND LEFT(LTRIM(JSON_QUERY(items.value, '$.valueJson')), 1) = N'{'
      AND (JSON_VALUE(items.value, '$.evidenceText') IS NULL
           OR LEN(JSON_VALUE(items.value, '$.evidenceText')) <= 2000)
      AND (JSON_VALUE(items.value, '$.sourceLocator') IS NULL
           OR LEN(JSON_VALUE(items.value, '$.sourceLocator')) <= 500)
      AND (JSON_VALUE(items.value, '$.confidence') IS NULL
           OR TRY_CONVERT(DECIMAL(5,2), JSON_VALUE(items.value, '$.confidence')) BETWEEN 0 AND 100)
      AND (JSON_VALUE(items.value, '$.isManualLock') IS NULL
           OR TRY_CONVERT(BIT, JSON_VALUE(items.value, '$.isManualLock')) IS NOT NULL)
      AND JSON_VALUE(items.value, '$.fieldPath') NOT IN
          (N'/title', N'/description', N'/eligibilityDescription', N'/closeDate', N'/sponsorName')
    GROUP BY JSON_VALUE(items.value, '$.fieldPath')
    HAVING COUNT_BIG(1) = 1;

    IF NULLIF(LTRIM(RTRIM(@Title)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@SponsorName)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(@SourceUrl)), N'') IS NULL
       OR @RawFunderCount <> (SELECT COUNT(1) FROM @RequestedFunders)
       OR @RawEvidenceCount <> (SELECT COUNT(1) FROM @ExtraEvidence)
       OR (SELECT COUNT(1) FROM @RequestedFunders WHERE Role = 1) <> 1
       OR @AmountStatus NOT BETWEEN 0 AND 2
       OR (@AmountStatus = 1 AND (@Currency IS NULL OR (@MinAmount IS NULL AND @MaxAmount IS NULL)))
       OR (@AmountStatus IN (0, 2) AND (@Currency IS NOT NULL OR @MinAmount IS NOT NULL OR @MaxAmount IS NOT NULL))
       OR @MinAmount < 0 OR @MaxAmount < COALESCE(@MinAmount, 0)
       OR @DeadlineType NOT BETWEEN 0 AND 2 OR @DeadlinePrecision NOT BETWEEN 0 AND 2
       OR (@DeadlineType = 0 AND (@DeadlinePrecision <> 0 OR @CloseAtUtc IS NOT NULL))
       OR (@DeadlineType = 2 AND (@DeadlinePrecision <> 0 OR @CloseDate IS NOT NULL OR @CloseAtUtc IS NOT NULL))
       OR (@DeadlineType = 1 AND @DeadlinePrecision NOT IN (1, 2))
       OR (@DeadlineType = 1 AND @DeadlinePrecision = 1 AND (@CloseDate IS NULL OR @CloseAtUtc IS NOT NULL))
       OR (@DeadlineType = 1 AND @DeadlinePrecision = 2
           AND (@CloseDate IS NULL OR @CloseAtUtc IS NULL OR @DeadlineTimeZoneId IS NULL))
       OR (@OpenDate IS NOT NULL AND @CloseDate IS NOT NULL AND @OpenDate > @CloseDate)
       OR @GeographicScope NOT BETWEEN 0 AND 2 OR @RemoteApplication NOT BETWEEN 0 AND 2
       OR (@GeographicScope = 0
           AND (EXISTS (SELECT 1 FROM @CountryIds) OR EXISTS (SELECT 1 FROM @RegionIds)))
       OR (@GeographicScope = 1 AND NOT EXISTS (SELECT 1 FROM @CountryIds))
       OR (@GeographicScope = 2
           AND (EXISTS (SELECT 1 FROM @CountryIds) OR EXISTS (SELECT 1 FROM @RegionIds)))
       OR @DataQualityScore NOT BETWEEN 0 AND 100
       OR @MinimumOperatingYears < 0
       OR @CofundingPercentage < 0 OR @CofundingPercentage > 100
       OR (@RequiresCofunding IS NULL AND @CofundingPercentage IS NOT NULL)
       OR (@RequiresCofunding = 0 AND COALESCE(@CofundingPercentage, 0) <> 0)
       OR (@RequiresCofunding = 1 AND COALESCE(@CofundingPercentage, 0) <= 0)
       OR (@LastVerifiedAtUtc IS NOT NULL
           AND @LastVerifiedAtUtc > DATEADD(MINUTE, 5, SYSUTCDATETIME()))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               @FundingOpportunityPublicId AS FundingOpportunityPublicId,
               CAST(NULL AS INT) AS ContentVersion, CAST(NULL AS TINYINT) AS PublicationStatus,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_OppUpdate;
    BEGIN TRY
        IF @OwnerWorkspace = 1
            EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 2, @FundingOpportunityPublicId, @ActorUserId OUTPUT;
        ELSE
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        IF @OwnerWorkspace = 1
        BEGIN
            /* Native submission provenance and exactly one owned primary funder.
               Existing/imported records cannot be adopted through a link or a replay. */
            IF (SELECT COUNT_BIG(1) FROM @RequestedFunders) <> 1
               OR NOT EXISTS (SELECT 1 FROM @RequestedFunders AS requested
                   INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.PublicId = requested.FunderPublicId
                   INNER JOIN dbo.FundingPlatform_FunderWorkspaceOwners AS owners WITH (UPDLOCK, HOLDLOCK) ON owners.FunderId = funders.Id
                   WHERE requested.Role = 1 AND owners.UserId = @ActorUserId AND owners.IsActive = 1)
               OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingSources WHERE Id = @FundingSourceId AND ProviderCode = N'funder-workspace' AND IsEnabled = 1)
                THROW 51601, N'Workspace funder or source is not permitted.', 1;
            IF NOT EXISTS (SELECT 1 FROM @RequestedFunders AS requested
                INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.PublicId = requested.FunderPublicId
                INNER JOIN dbo.FundingPlatform_OpportunityWorkspaceOwners AS managed ON managed.FunderId = funders.Id
                INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities ON opportunities.Id = managed.FundingOpportunityId
                WHERE opportunities.PublicId = @FundingOpportunityPublicId)
                THROW 51601, N'Workspace ownership cannot be transferred.', 1;
        END;
        SELECT @ActorUserId = Id FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;
        SELECT @OpportunityId = Id, @CurrentSlug = Slug, @CurrentStatus = PublicationStatus,
               @CurrentVersion = ContentVersion, @CurrentRowVersion = RowVersion
        FROM dbo.FundingPlatform_FundingOpportunities WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @FundingOpportunityPublicId;

        IF @OpportunityId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = ActionCode, @ExistingRequestHash = RequestHash,
                   @ExistingToStatus = ToStatus, @NextVersion = ContentVersion,
                   @RowVersion = ResultRowVersion
            FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE FundingOpportunityId = @OpportunityId
              AND IdempotencyKeyHash = @IdempotencyKeyHash;
            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'Update' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'updated';
                    SET @CurrentStatus = @ExistingToStatus;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus NOT IN (0, 3) SET @Code = N'invalid-transition';
            ELSE
            BEGIN
                UPDATE requested SET FunderId = funders.Id
                FROM @RequestedFunders AS requested
                INNER JOIN dbo.FundingPlatform_Funders AS funders WITH (UPDLOCK, HOLDLOCK)
                    ON funders.PublicId = requested.FunderPublicId
                   AND funders.IsActive = 1 AND funders.PublicationStatus <> 4;

                SELECT @SourceLinkId = links.Id
                FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
                    WITH (UPDLOCK, HOLDLOCK)
                WHERE links.FundingOpportunityId = @OpportunityId
                  AND links.FundingSourceId = @FundingSourceId
                  AND links.SourceItemKeyHash = @SourceItemKeyHash;

                IF EXISTS (SELECT 1 FROM @RequestedFunders WHERE FunderId IS NULL)
                    SET @Code = N'funder-not-found';
                ELSE IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingSources
                                    WHERE Id = @FundingSourceId AND IsEnabled = 1)
                    SET @Code = N'source-disabled';
                ELSE IF (@IssuerCountryId IS NOT NULL AND NOT EXISTS
                         (SELECT 1 FROM dbo.FundingPlatform_Countries
                          WHERE Id = @IssuerCountryId AND IsActive = 1))
                     OR (@FundingTypeId IS NOT NULL AND NOT EXISTS
                         (SELECT 1 FROM dbo.FundingPlatform_FundingTypes
                          WHERE Id = @FundingTypeId AND IsActive = 1))
                     OR (@Currency IS NOT NULL AND NOT EXISTS
                         (SELECT 1 FROM dbo.FundingPlatform_Currencies
                          WHERE Code = @Currency AND IsActive = 1))
                     OR EXISTS (SELECT 1 FROM @CountryIds AS selected
                                LEFT JOIN dbo.FundingPlatform_Countries AS catalog
                                    ON catalog.Id = selected.Id AND catalog.IsActive = 1
                                WHERE catalog.Id IS NULL)
                     OR EXISTS (SELECT 1 FROM @CategoryIds AS selected
                                LEFT JOIN dbo.FundingPlatform_FundingCategories AS catalog
                                    ON catalog.Id = selected.Id AND catalog.IsActive = 1
                                WHERE catalog.Id IS NULL)
                     OR EXISTS (SELECT 1 FROM @BeneficiaryTypeIds AS selected
                                LEFT JOIN dbo.FundingPlatform_BeneficiaryTypes AS catalog
                                    ON catalog.Id = selected.Id AND catalog.IsActive = 1
                                WHERE catalog.Id IS NULL)
                     OR EXISTS (SELECT 1 FROM @ProjectTypeIds AS selected
                                LEFT JOIN dbo.FundingPlatform_ProjectTypes AS catalog
                                    ON catalog.Id = selected.Id AND catalog.IsActive = 1
                                WHERE catalog.Id IS NULL)
                    SET @Code = N'invalid-document';
                ELSE IF EXISTS
                (
                    SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks WITH (UPDLOCK, HOLDLOCK)
                    WHERE FundingSourceId = @FundingSourceId
                      AND Id <> COALESCE(@SourceLinkId, -1)
                      AND (SourceItemKeyHash = @SourceItemKeyHash
                           OR (@ExternalId IS NOT NULL AND ExternalId = @ExternalId))
                ) SET @Code = N'source-link-conflict';
                ELSE IF EXISTS
                (
                    SELECT 1 FROM @RegionIds AS selected
                    LEFT JOIN dbo.FundingPlatform_Regions AS regions
                        ON regions.Id = selected.Id AND regions.IsActive = 1
                    WHERE regions.Id IS NULL
                       OR NOT EXISTS (SELECT 1 FROM @CountryIds AS countries
                                      WHERE countries.Id = regions.CountryId)
                ) SET @Code = N'invalid-document';
                ELSE
                BEGIN
                    SET @NextVersion = @CurrentVersion + 1;
                    DECLARE @UpdatedOpportunity TABLE (RowVersion BINARY(8));
                    UPDATE dbo.FundingPlatform_FundingOpportunities
                    SET Title = LTRIM(RTRIM(@Title)), Description = @Description, Summary = @Summary,
                        SponsorName = LTRIM(RTRIM(@SponsorName)), SponsorUrl = @SponsorUrl,
                        ApplicationUrl = @ApplicationUrl, IssuerCountryId = @IssuerCountryId,
                        FundingTypeId = @FundingTypeId, Currency = @Currency,
                        MinAmount = @MinAmount, MaxAmount = @MaxAmount, AmountStatus = @AmountStatus,
                        OpenDate = @OpenDate, CloseDate = @CloseDate, CloseAtUtc = @CloseAtUtc,
                        DeadlineTimeZoneId = @DeadlineTimeZoneId, DeadlineType = @DeadlineType,
                        DeadlinePrecision = @DeadlinePrecision,
                        EligibilityDescription = @EligibilityDescription, Requirements = @Requirements,
                        Objectives = @Objectives, AllowedActivities = @AllowedActivities,
                        ExcludedActivities = @ExcludedActivities, Restrictions = @Restrictions,
                        TargetOrganizationsDescription = @TargetOrganizationsDescription,
                        TargetPopulationsDescription = @TargetPopulationsDescription,
                        MinimumOperatingYears = @MinimumOperatingYears,
                        RequiresLegalEntity = @RequiresLegalEntity,
                        RequiresPriorExperience = @RequiresPriorExperience,
                        RequiresCofunding = @RequiresCofunding,
                        CofundingPercentage = @CofundingPercentage,
                        GeographicScope = @GeographicScope, RemoteApplication = @RemoteApplication,
                        LastVerifiedAtUtc = COALESCE(@LastVerifiedAtUtc, @NowUtc),
                        DataQualityScore = @DataQualityScore,
                        ContentVersion = @NextVersion, ContentFingerprint = @ContentHash,
                        UpdatedByUserId = @ActorUserId, UpdatedAtUtc = @NowUtc
                    OUTPUT inserted.RowVersion INTO @UpdatedOpportunity (RowVersion)
                    WHERE Id = @OpportunityId AND RowVersion = @ExpectedRowVersion;
                    SELECT @RowVersion = RowVersion FROM @UpdatedOpportunity;

                    IF @RowVersion IS NULL SET @Code = N'etag-conflict';
                    ELSE
                    BEGIN
                        UPDATE dbo.FundingPlatform_FundingOpportunitySourceLinks
                        SET IsPrimary = 0
                        WHERE FundingOpportunityId = @OpportunityId AND IsPrimary = 1;
                        SELECT @SourceLinkId = Id
                        FROM dbo.FundingPlatform_FundingOpportunitySourceLinks
                        WHERE FundingOpportunityId = @OpportunityId
                          AND FundingSourceId = @FundingSourceId
                          AND SourceItemKeyHash = @SourceItemKeyHash;
                        IF @SourceLinkId IS NULL
                        BEGIN
                            DECLARE @InsertedSourceLink TABLE (Id BIGINT);
                            INSERT INTO dbo.FundingPlatform_FundingOpportunitySourceLinks
                                (FundingOpportunityId, FundingSourceId, ExternalId, SourceItemKeyHash,
                                 SourceUrl, CanonicalUrlHash, FirstSeenAtUtc, LastSeenAtUtc,
                                 IsPrimary, IsActive)
                            OUTPUT inserted.Id INTO @InsertedSourceLink (Id)
                            VALUES (@OpportunityId, @FundingSourceId, @ExternalId, @SourceItemKeyHash,
                                    @SourceUrl, @CanonicalUrlHash, @NowUtc, @NowUtc, 1, 1);
                            SELECT @SourceLinkId = Id FROM @InsertedSourceLink;
                        END
                        ELSE
                            UPDATE dbo.FundingPlatform_FundingOpportunitySourceLinks
                            SET ExternalId = @ExternalId, SourceUrl = @SourceUrl,
                                CanonicalUrlHash = @CanonicalUrlHash, LastSeenAtUtc = @NowUtc,
                                IsPrimary = 1, IsActive = 1
                            WHERE Id = @SourceLinkId;

                        DELETE FROM dbo.FundingPlatform_FundingOpportunityCountries
                        WHERE FundingOpportunityId = @OpportunityId;
                        DELETE FROM dbo.FundingPlatform_FundingOpportunityRegions
                        WHERE FundingOpportunityId = @OpportunityId;
                        DELETE FROM dbo.FundingPlatform_FundingOpportunityCategories
                        WHERE FundingOpportunityId = @OpportunityId;
                        DELETE FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes
                        WHERE FundingOpportunityId = @OpportunityId;
                        DELETE FROM dbo.FundingPlatform_FundingOpportunityProjectTypes
                        WHERE FundingOpportunityId = @OpportunityId;
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityCountries
                            (FundingOpportunityId, CountryId) SELECT @OpportunityId, Id FROM @CountryIds;
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityRegions
                            (FundingOpportunityId, RegionId) SELECT @OpportunityId, Id FROM @RegionIds;
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityCategories
                            (FundingOpportunityId, FundingCategoryId) SELECT @OpportunityId, Id FROM @CategoryIds;
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes
                            (FundingOpportunityId, BeneficiaryTypeId)
                        SELECT @OpportunityId, Id FROM @BeneficiaryTypeIds;
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityProjectTypes
                            (FundingOpportunityId, ProjectTypeId)
                        SELECT @OpportunityId, Id FROM @ProjectTypeIds;

                        UPDATE dbo.FundingPlatform_FundingOpportunityFunders
                        SET IsActive = 0, UpdatedAtUtc = @NowUtc
                        WHERE FundingOpportunityId = @OpportunityId AND IsActive = 1;
                        UPDATE links
                        SET Role = requested.Role, EvidenceId = NULL,
                            IsActive = 1, UpdatedAtUtc = @NowUtc
                        FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
                        INNER JOIN @RequestedFunders AS requested
                            ON requested.FunderId = links.FunderId
                        WHERE links.FundingOpportunityId = @OpportunityId;
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityFunders
                            (FundingOpportunityId, FunderId, Role, EvidenceId, IsActive,
                             CreatedAtUtc, UpdatedAtUtc)
                        SELECT @OpportunityId, requested.FunderId, requested.Role, NULL, 1,
                               @NowUtc, @NowUtc
                        FROM @RequestedFunders AS requested
                        WHERE NOT EXISTS
                        (
                            SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunders AS existing
                            WHERE existing.FundingOpportunityId = @OpportunityId
                              AND existing.FunderId = requested.FunderId
                        );

                        UPDATE evidence
                        SET IsSelected = 0
                        FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
                        WHERE evidence.FundingOpportunityId = @OpportunityId
                          AND evidence.IsSelected = 1
                          AND
                          (
                              evidence.FieldPath IN
                                  (N'/title', N'/description', N'/eligibilityDescription',
                                   N'/closeDate', N'/sponsorName')
                              OR EXISTS
                                 (SELECT 1 FROM @ExtraEvidence AS replacement
                                  WHERE replacement.FieldPath = evidence.FieldPath)
                          );
                        DECLARE @CriticalEvidence TABLE
                            (FieldPath NVARCHAR(200), ValueText NVARCHAR(MAX), StatusCode NVARCHAR(20),
                             EvidenceText NVARCHAR(2000));
                        INSERT INTO @CriticalEvidence VALUES
                            (N'/title', @Title, N'known', LEFT(@Title, 2000)),
                            (N'/description', @Description,
                             CASE WHEN NULLIF(LTRIM(RTRIM(@Description)), N'') IS NULL THEN N'unknown' ELSE N'known' END,
                             LEFT(@Description, 2000)),
                            (N'/eligibilityDescription', @EligibilityDescription,
                             CASE WHEN NULLIF(LTRIM(RTRIM(@EligibilityDescription)), N'') IS NULL THEN N'unknown' ELSE N'known' END,
                             LEFT(@EligibilityDescription, 2000)),
                            (N'/closeDate', CONVERT(NVARCHAR(30), @CloseDate, 23),
                             CASE WHEN @CloseDate IS NULL THEN N'unknown' ELSE N'known' END,
                             CONVERT(NVARCHAR(30), @CloseDate, 23)),
                            (N'/sponsorName', @SponsorName, N'known', LEFT(@SponsorName, 2000));
                        INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
                            (FundingOpportunityId, FieldPath, ValueJson, FundingOpportunitySourceLinkId,
                             ExtractionMethod, EvidenceText, SourceLocator, Confidence,
                             IsSelected, IsManualLock, CreatedByUserId, CreatedAtUtc)
                        SELECT @OpportunityId, critical.FieldPath,
                               (SELECT critical.ValueText AS [value], critical.StatusCode AS [status]
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
                               @SourceLinkId, 1, critical.EvidenceText, LEFT(@SourceUrl, 500),
                               100, 1, 1, @ActorUserId, @NowUtc
                        FROM @CriticalEvidence AS critical;
                        INSERT INTO dbo.FundingPlatform_FundingFieldEvidence
                            (FundingOpportunityId, FieldPath, ValueJson, FundingOpportunitySourceLinkId,
                             ExtractionMethod, EvidenceText, SourceLocator, Confidence,
                             IsSelected, IsManualLock, CreatedByUserId, CreatedAtUtc)
                        SELECT @OpportunityId, extra.FieldPath, extra.ValueJson, @SourceLinkId, 1,
                               extra.EvidenceText, COALESCE(extra.SourceLocator, LEFT(@SourceUrl, 500)),
                               extra.Confidence, 1, extra.IsManualLock, @ActorUserId, @NowUtc
                        FROM @ExtraEvidence AS extra;
                        DECLARE @SponsorEvidenceId BIGINT =
                            (SELECT Id FROM dbo.FundingPlatform_FundingFieldEvidence
                             WHERE FundingOpportunityId = @OpportunityId
                               AND FieldPath = N'/sponsorName' AND IsSelected = 1);
                        UPDATE links SET EvidenceId = @SponsorEvidenceId
                        FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
                        WHERE links.FundingOpportunityId = @OpportunityId
                          AND links.Role = 1 AND links.IsActive = 1;

                        INSERT INTO dbo.FundingPlatform_FundingOpportunityVersions
                            (FundingOpportunityId, ContentVersion, SnapshotJson, ContentHash,
                             CreatedByUserId, CreatedAtUtc)
                        VALUES (@OpportunityId, @NextVersion, @SnapshotJson, @ContentHash,
                                @ActorUserId, @NowUtc);
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityEditorialEvents
                            (EventId, FundingOpportunityId, ContentVersion, FromStatus, ToStatus,
                             ActionCode, ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                             ResultRowVersion, CreatedAtUtc)
                        VALUES (@EventId, @OpportunityId, @NextVersion, @CurrentStatus, @CurrentStatus,
                                N'Update', @ActorUserId, NULL, @IdempotencyKeyHash,
                                @RequestHash, @RowVersion, @NowUtc);
                        INSERT INTO dbo.FundingPlatform_OutboxMessages
                            (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                             OccurredAtUtc, AvailableAtUtc)
                        SELECT @EventId, N'FundingOpportunityChanged', N'FundingOpportunity',
                               CONVERT(NVARCHAR(100), @OpportunityId),
                               (SELECT @EventId AS eventId, @OpportunityId AS fundingOpportunityId,
                                       @FundingOpportunityPublicId AS fundingOpportunityPublicId,
                                       @NextVersion AS contentVersion
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                        SET @Succeeded = 1; SET @Code = N'updated';
                    END;
                END;
            END;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_OppUpdate;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           @FundingOpportunityPublicId AS FundingOpportunityPublicId,
           COALESCE(@NextVersion, @CurrentVersion) AS ContentVersion,
           @CurrentStatus AS PublicationStatus, COALESCE(@RowVersion, @CurrentRowVersion) AS RowVersion,
           @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_RequestPublication
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FundingOpportunityPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @ResultCode NVARCHAR(50) = NULL OUTPUT,
    @ResultCompleteness DECIMAL(5,2) = NULL OUTPUT,
    @OwnerWorkspace BIT = 0
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @OwnerWorkspace IS NULL THROW 51601, N'Invalid workspace scope.', 1;
    DECLARE @WorkspaceActorUserId BIGINT;
    IF @OwnerWorkspace = 1
        EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 2, @FundingOpportunityPublicId, @WorkspaceActorUserId OUTPUT;
    ELSE
    BEGIN
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    END;

    DECLARE @Issues TABLE
    (
        Code NVARCHAR(50) NOT NULL,
        FieldPath NVARCHAR(100) NOT NULL,
        Message NVARCHAR(300) NOT NULL
    );
    DECLARE @ActorUserId BIGINT, @OpportunityId BIGINT, @ContentVersion INT;
    DECLARE @GeographicScope TINYINT;
    DECLARE @CurrentStatus TINYINT, @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @SubmittedAtUtc DATETIME2(3), @PublishedAtUtc DATETIME2(3), @ReviewedAtUtc DATETIME2(3);
    DECLARE @ReviewedByUserPublicId UNIQUEIDENTIFIER, @RejectionReason NVARCHAR(1000);
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Completeness DECIMAL(5,2) = 0;
    DECLARE @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_OppRequest;
    BEGIN TRY
        IF @OwnerWorkspace = 1
            EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 2, @FundingOpportunityPublicId, @ActorUserId OUTPUT;
        ELSE
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @ActorUserId = Id FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;
        SELECT @OpportunityId = opportunities.Id, @ContentVersion = opportunities.ContentVersion,
               @GeographicScope = opportunities.GeographicScope,
               @CurrentStatus = opportunities.PublicationStatus,
               @CurrentRowVersion = opportunities.RowVersion,
               @SubmittedAtUtc = opportunities.SubmittedAtUtc,
               @PublishedAtUtc = opportunities.PublishedAtUtc,
               @ReviewedAtUtc = opportunities.ReviewedAtUtc,
               @ReviewedByUserPublicId = reviewers.PublicId,
               @RejectionReason = opportunities.RejectionReason
        FROM dbo.FundingPlatform_FundingOpportunities AS opportunities WITH (UPDLOCK, HOLDLOCK)
        LEFT JOIN dbo.FundingPlatform_Users AS reviewers
            ON reviewers.Id = opportunities.ReviewedByUserId
        WHERE opportunities.PublicId = @FundingOpportunityPublicId;

        IF @OpportunityId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = ActionCode, @ExistingRequestHash = RequestHash,
                   @ExistingToStatus = ToStatus, @ResultRowVersion = ResultRowVersion,
                   @ContentVersion = ContentVersion, @Completeness = ResultCompleteness,
                   @SubmittedAtUtc = ResultSubmittedAtUtc,
                   @PublishedAtUtc = ResultPublishedAtUtc,
                   @ReviewedAtUtc = ResultReviewedAtUtc,
                   @ReviewedByUserPublicId = ResultReviewedByUserPublicId,
                   @RejectionReason = ResultRejectionReason
            FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE FundingOpportunityId = @OpportunityId
              AND IdempotencyKeyHash = @IdempotencyKeyHash;
            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'RequestPublication' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'review-requested';
                    SET @CurrentStatus = @ExistingToStatus;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus NOT IN (0, 3) SET @Code = N'invalid-transition';
            ELSE
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities
                               WHERE Id = @OpportunityId
                                 AND NULLIF(LTRIM(RTRIM(Title)), N'') IS NOT NULL)
                    INSERT INTO @Issues VALUES (N'title', N'title', N'Title is required.');
                IF NOT EXISTS
                (
                    SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityFunders AS links
                    INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = links.FunderId
                    WHERE links.FundingOpportunityId = @OpportunityId AND links.Role = 1
                      AND links.IsActive = 1 AND funders.PublicationStatus = 2 AND funders.IsActive = 1
                ) INSERT INTO @Issues VALUES
                    (N'primaryFunder', N'funderLinks', N'A published primary funder is required.');
                IF NOT EXISTS
                (
                    SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks AS links
                    INNER JOIN dbo.FundingPlatform_FundingSources AS sources
                        ON sources.Id = links.FundingSourceId
                    WHERE links.FundingOpportunityId = @OpportunityId AND links.IsPrimary = 1
                      AND links.IsActive = 1 AND sources.IsEnabled = 1
                      AND NULLIF(LTRIM(RTRIM(links.SourceUrl)), N'') IS NOT NULL
                ) INSERT INTO @Issues VALUES
                    (N'officialSource', N'sourceUrl', N'An enabled primary source URL is required.');
                IF @GeographicScope = 0
                    INSERT INTO @Issues VALUES
                        (N'geographicScope', N'geographicScope',
                         N'Unknown geographic scope cannot be published.');
                IF @GeographicScope = 1
                   AND NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries
                                   WHERE FundingOpportunityId = @OpportunityId)
                    INSERT INTO @Issues VALUES
                        (N'countries', N'countryIds',
                         N'Explicit geographic scope requires at least one eligible country.');
                IF @GeographicScope = 2
                   AND
                   (
                       EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries
                               WHERE FundingOpportunityId = @OpportunityId)
                       OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityRegions
                                  WHERE FundingOpportunityId = @OpportunityId)
                   )
                    INSERT INTO @Issues VALUES
                        (N'globalGeography', N'countryIds',
                         N'Global geographic scope cannot contain country or region restrictions.');
                IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCategories
                               WHERE FundingOpportunityId = @OpportunityId)
                    INSERT INTO @Issues VALUES
                        (N'categories', N'categoryIds', N'At least one category is required.');
                IF NOT EXISTS
                (
                    SELECT 1
                    FROM dbo.FundingPlatform_ifn_FundingOpportunityActiveCatalogs() AS catalogs
                    WHERE catalogs.FundingOpportunityId = @OpportunityId
                )
                    INSERT INTO @Issues VALUES
                        (N'inactiveCatalogReference', N'catalogs',
                         N'Every catalog reference must be active and geography must remain consistent.');
                IF EXISTS
                (
                    SELECT required.FieldPath
                    FROM (VALUES (N'/title'), (N'/description'),
                                 (N'/eligibilityDescription'), (N'/closeDate')) AS required(FieldPath)
                    WHERE NOT EXISTS
                    (
                        SELECT 1 FROM dbo.FundingPlatform_FundingFieldEvidence AS evidence
                        WHERE evidence.FundingOpportunityId = @OpportunityId
                          AND evidence.FieldPath = required.FieldPath AND evidence.IsSelected = 1
                          AND JSON_VALUE(evidence.ValueJson, '$.status') IN (N'known', N'unknown')
                    )
                ) INSERT INTO @Issues VALUES
                    (N'criticalEvidence', N'evidence',
                     N'Every critical field requires selected evidence or an explicit unknown value.');

                DECLARE @IssueCount INT = (SELECT COUNT(1) FROM @Issues);
                SET @Completeness = CONVERT(DECIMAL(5,2),
                    CASE WHEN @IssueCount >= 5 THEN 0 ELSE 100 - (@IssueCount * 20) END);
                IF @IssueCount > 0 SET @Code = N'opportunity-not-ready';
                ELSE
                BEGIN
                    DECLARE @Updated TABLE (RowVersion BINARY(8));
                    UPDATE dbo.FundingPlatform_FundingOpportunities
                    SET PublicationStatus = 1, SubmittedAtUtc = @NowUtc,
                        ReviewedAtUtc = NULL, ReviewedByUserId = NULL,
                        RejectionReason = NULL, UpdatedByUserId = @ActorUserId,
                        UpdatedAtUtc = @NowUtc
                    OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
                    WHERE Id = @OpportunityId AND RowVersion = @ExpectedRowVersion;
                    SELECT @ResultRowVersion = RowVersion FROM @Updated;
                    IF @ResultRowVersion IS NULL SET @Code = N'etag-conflict';
                    ELSE
                    BEGIN
                        INSERT INTO dbo.FundingPlatform_FundingOpportunityEditorialEvents
                            (EventId, FundingOpportunityId, ContentVersion, FromStatus, ToStatus,
                             ActionCode, ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                             ResultRowVersion, ResultCompleteness, ResultSubmittedAtUtc,
                             ResultPublishedAtUtc, ResultReviewedAtUtc,
                             ResultReviewedByUserPublicId, ResultRejectionReason, CreatedAtUtc)
                        VALUES (@EventId, @OpportunityId, @ContentVersion, @CurrentStatus, 1,
                                N'RequestPublication', @ActorUserId, NULL, @IdempotencyKeyHash,
                                @RequestHash, @ResultRowVersion, 100, @NowUtc,
                                @PublishedAtUtc, NULL, NULL, NULL, @NowUtc);
                        INSERT INTO dbo.FundingPlatform_OutboxMessages
                            (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                             OccurredAtUtc, AvailableAtUtc)
                        SELECT @EventId, N'FundingOpportunityPublicationRequested',
                               N'FundingOpportunity', CONVERT(NVARCHAR(100), @OpportunityId),
                               (SELECT @EventId AS eventId,
                                       @OpportunityId AS fundingOpportunityId,
                                       @FundingOpportunityPublicId AS fundingOpportunityPublicId,
                                       @ContentVersion AS contentVersion,
                                       @CurrentStatus AS fromStatus, 1 AS toStatus
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                        SET @Succeeded = 1; SET @Code = N'review-requested';
                        SET @CurrentStatus = 1; SET @SubmittedAtUtc = @NowUtc;
                        SET @ReviewedAtUtc = NULL; SET @ReviewedByUserPublicId = NULL;
                        SET @RejectionReason = NULL;
                    END;
                END;
            END;
        END;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_OppRequest;
        THROW;
    END CATCH;

    SET @ResultCode = @Code; SET @ResultCompleteness = @Completeness;
    SELECT @Succeeded AS Succeeded, @Code AS Code, @Completeness AS Completeness,
           @FundingOpportunityPublicId AS FundingOpportunityPublicId,
           @ContentVersion AS ContentVersion, @CurrentStatus AS PublicationStatus,
           @SubmittedAtUtc AS SubmittedAtUtc, @PublishedAtUtc AS PublishedAtUtc,
           @ReviewedAtUtc AS ReviewedAtUtc,
           @ReviewedByUserPublicId AS ReviewedByUserPublicId,
           @RejectionReason AS RejectionReason,
           COALESCE(@ResultRowVersion, @CurrentRowVersion) AS RowVersion, @WasReplay AS WasReplay;
    SELECT Code, FieldPath, Message FROM @Issues ORDER BY FieldPath, Code;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_StartCorrection
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FundingOpportunityPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @Reason NVARCHAR(1000),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @OwnerWorkspace BIT = 0
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @OwnerWorkspace IS NULL THROW 51601, N'Invalid workspace scope.', 1;
    DECLARE @WorkspaceActorUserId BIGINT;
    IF @OwnerWorkspace = 1
        EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 2, @FundingOpportunityPublicId, @WorkspaceActorUserId OUTPUT;
    ELSE
    BEGIN
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    END;

    DECLARE @NormalizedReason NVARCHAR(1000) = LTRIM(RTRIM(@Reason));
    IF LEN(COALESCE(@NormalizedReason, N'')) NOT BETWEEN 3 AND 1000
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, N'invalid-document' AS Code,
               CAST(NULL AS DECIMAL(5,2)) AS Completeness,
               @FundingOpportunityPublicId AS FundingOpportunityPublicId,
               CAST(NULL AS INT) AS ContentVersion, CAST(NULL AS TINYINT) AS PublicationStatus,
               CAST(NULL AS DATETIME2(3)) AS SubmittedAtUtc,
               CAST(NULL AS DATETIME2(3)) AS PublishedAtUtc,
               CAST(NULL AS DATETIME2(3)) AS ReviewedAtUtc,
               CAST(NULL AS UNIQUEIDENTIFIER) AS ReviewedByUserPublicId,
               CAST(NULL AS NVARCHAR(1000)) AS RejectionReason,
               CAST(NULL AS BINARY(8)) AS RowVersion, CAST(0 AS BIT) AS WasReplay;
        RETURN;
    END;

    DECLARE @ActorUserId BIGINT, @OpportunityId BIGINT, @ContentVersion INT;
    DECLARE @CurrentStatus TINYINT, @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @SubmittedAtUtc DATETIME2(3), @PublishedAtUtc DATETIME2(3), @ReviewedAtUtc DATETIME2(3);
    DECLARE @ReviewedByUserPublicId UNIQUEIDENTIFIER, @CurrentRejectionReason NVARCHAR(1000);
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_OppCorrection;
    BEGIN TRY
        IF @OwnerWorkspace = 1
            EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 2, @FundingOpportunityPublicId, @ActorUserId OUTPUT;
        ELSE
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @OpportunityId = opportunities.Id,
               @ContentVersion = opportunities.ContentVersion,
               @CurrentStatus = opportunities.PublicationStatus,
               @CurrentRowVersion = opportunities.RowVersion,
               @SubmittedAtUtc = opportunities.SubmittedAtUtc,
               @PublishedAtUtc = opportunities.PublishedAtUtc,
               @ReviewedAtUtc = opportunities.ReviewedAtUtc,
               @ReviewedByUserPublicId = reviewers.PublicId,
               @CurrentRejectionReason = opportunities.RejectionReason
        FROM dbo.FundingPlatform_FundingOpportunities AS opportunities WITH (UPDLOCK, HOLDLOCK)
        LEFT JOIN dbo.FundingPlatform_Users AS reviewers
            ON reviewers.Id = opportunities.ReviewedByUserId
        WHERE opportunities.PublicId = @FundingOpportunityPublicId;

        IF @OpportunityId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = ActionCode, @ExistingRequestHash = RequestHash,
                   @ExistingToStatus = ToStatus, @ResultRowVersion = ResultRowVersion,
                   @ContentVersion = ContentVersion,
                   @SubmittedAtUtc = ResultSubmittedAtUtc,
                   @PublishedAtUtc = ResultPublishedAtUtc,
                   @ReviewedAtUtc = ResultReviewedAtUtc,
                   @ReviewedByUserPublicId = ResultReviewedByUserPublicId,
                   @CurrentRejectionReason = ResultRejectionReason
            FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE FundingOpportunityId = @OpportunityId
              AND IdempotencyKeyHash = @IdempotencyKeyHash;

            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'StartCorrection' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1;
                    SET @Code = N'correction-started'; SET @CurrentStatus = @ExistingToStatus;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus <> 2 SET @Code = N'invalid-transition';
            ELSE
            BEGIN
                DECLARE @Updated TABLE (RowVersion BINARY(8));
                UPDATE dbo.FundingPlatform_FundingOpportunities
                SET PublicationStatus = 0, SubmittedAtUtc = NULL, PublishedAtUtc = NULL,
                    ReviewedAtUtc = NULL, ReviewedByUserId = NULL, RejectionReason = NULL,
                    UpdatedByUserId = @ActorUserId, UpdatedAtUtc = @NowUtc
                OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
                WHERE Id = @OpportunityId AND RowVersion = @ExpectedRowVersion;
                SELECT @ResultRowVersion = RowVersion FROM @Updated;
                IF @ResultRowVersion IS NULL SET @Code = N'etag-conflict';
                ELSE
                BEGIN
                    INSERT INTO dbo.FundingPlatform_FundingOpportunityEditorialEvents
                        (EventId, FundingOpportunityId, ContentVersion, FromStatus, ToStatus,
                         ActionCode, ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                         ResultRowVersion, ResultCompleteness, ResultSubmittedAtUtc,
                         ResultPublishedAtUtc, ResultReviewedAtUtc,
                         ResultReviewedByUserPublicId, ResultRejectionReason, CreatedAtUtc)
                    VALUES (@EventId, @OpportunityId, @ContentVersion, 2, 0,
                            N'StartCorrection', @ActorUserId, @NormalizedReason,
                            @IdempotencyKeyHash, @RequestHash, @ResultRowVersion,
                            NULL, NULL, NULL, NULL, NULL, NULL, @NowUtc);
                    INSERT INTO dbo.FundingPlatform_OutboxMessages
                        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                         OccurredAtUtc, AvailableAtUtc)
                    SELECT @EventId, N'FundingOpportunityCorrectionStarted',
                           N'FundingOpportunity', CONVERT(NVARCHAR(100), @OpportunityId),
                           (SELECT @EventId AS eventId,
                                   @OpportunityId AS fundingOpportunityId,
                                   @FundingOpportunityPublicId AS fundingOpportunityPublicId,
                                   @ContentVersion AS contentVersion, 2 AS fromStatus, 0 AS toStatus
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                    SET @Succeeded = 1; SET @Code = N'correction-started'; SET @CurrentStatus = 0;
                    SET @SubmittedAtUtc = NULL; SET @PublishedAtUtc = NULL;
                    SET @ReviewedAtUtc = NULL; SET @ReviewedByUserPublicId = NULL;
                    SET @CurrentRejectionReason = NULL;
                END;
            END;
        END;

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_OppCorrection;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code,
           CAST(NULL AS DECIMAL(5,2)) AS Completeness,
           @FundingOpportunityPublicId AS FundingOpportunityPublicId,
           @ContentVersion AS ContentVersion, @CurrentStatus AS PublicationStatus,
           @SubmittedAtUtc AS SubmittedAtUtc, @PublishedAtUtc AS PublishedAtUtc,
           @ReviewedAtUtc AS ReviewedAtUtc,
           @ReviewedByUserPublicId AS ReviewedByUserPublicId,
           @CurrentRejectionReason AS RejectionReason,
           COALESCE(@ResultRowVersion, @CurrentRowVersion) AS RowVersion,
           @WasReplay AS WasReplay;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Deactivate
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @FundingOpportunityPublicId UNIQUEIDENTIFIER,
    @ExpectedRowVersion BINARY(8),
    @Reason NVARCHAR(1000) = NULL,
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @OwnerWorkspace BIT = 0
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @OwnerWorkspace IS NULL THROW 51601, N'Invalid workspace scope.', 1;
    DECLARE @WorkspaceActorUserId BIGINT;
    IF @OwnerWorkspace = 1
        EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 2, @FundingOpportunityPublicId, @WorkspaceActorUserId OUTPUT;
    ELSE
    BEGIN
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active Admin or SuperAdmin role is required.', 1;
    IF @AccessState = 1 THROW 51602, N'MFA is required for this administrative operation.', 1;
    END;

    DECLARE @ActorUserId BIGINT, @OpportunityId BIGINT, @ContentVersion INT;
    DECLARE @CurrentStatus TINYINT, @CurrentRowVersion BINARY(8), @ResultRowVersion BINARY(8);
    DECLARE @SubmittedAtUtc DATETIME2(3), @PublishedAtUtc DATETIME2(3), @ReviewedAtUtc DATETIME2(3);
    DECLARE @ReviewedByUserPublicId UNIQUEIDENTIFIER, @RejectionReason NVARCHAR(1000);
    DECLARE @ExistingAction NVARCHAR(50), @ExistingRequestHash BINARY(32), @ExistingToStatus TINYINT;
    DECLARE @Code NVARCHAR(50) = N'not-found', @Succeeded BIT = 0, @WasReplay BIT = 0;
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME(), @EventId UNIQUEIDENTIFIER = NEWID();
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_OppDeactivate;
    BEGIN TRY
        IF @OwnerWorkspace = 1
            EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert @AdminUserPublicId, 2, @FundingOpportunityPublicId, @ActorUserId OUTPUT;
        ELSE
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock
            @AdminUserPublicId, @ActorUserId OUTPUT;
        SELECT @ActorUserId = Id FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @AdminUserPublicId AND Status = 2;
        SELECT @OpportunityId = opportunities.Id, @ContentVersion = opportunities.ContentVersion,
               @CurrentStatus = opportunities.PublicationStatus,
               @CurrentRowVersion = opportunities.RowVersion,
               @SubmittedAtUtc = opportunities.SubmittedAtUtc,
               @PublishedAtUtc = opportunities.PublishedAtUtc,
               @ReviewedAtUtc = opportunities.ReviewedAtUtc,
               @ReviewedByUserPublicId = reviewers.PublicId,
               @RejectionReason = opportunities.RejectionReason
        FROM dbo.FundingPlatform_FundingOpportunities AS opportunities WITH (UPDLOCK, HOLDLOCK)
        LEFT JOIN dbo.FundingPlatform_Users AS reviewers
            ON reviewers.Id = opportunities.ReviewedByUserId
        WHERE opportunities.PublicId = @FundingOpportunityPublicId;

        IF @OpportunityId IS NOT NULL
        BEGIN
            SELECT @ExistingAction = ActionCode, @ExistingRequestHash = RequestHash,
                   @ExistingToStatus = ToStatus, @ResultRowVersion = ResultRowVersion,
                   @ContentVersion = ContentVersion,
                   @SubmittedAtUtc = ResultSubmittedAtUtc,
                   @PublishedAtUtc = ResultPublishedAtUtc,
                   @ReviewedAtUtc = ResultReviewedAtUtc,
                   @ReviewedByUserPublicId = ResultReviewedByUserPublicId,
                   @RejectionReason = ResultRejectionReason
            FROM dbo.FundingPlatform_FundingOpportunityEditorialEvents WITH (UPDLOCK, HOLDLOCK)
            WHERE FundingOpportunityId = @OpportunityId
              AND IdempotencyKeyHash = @IdempotencyKeyHash;
            IF @ExistingAction IS NOT NULL
            BEGIN
                IF @ExistingAction = N'Deactivate' AND @ExistingRequestHash = @RequestHash
                BEGIN
                    SET @Succeeded = 1; SET @WasReplay = 1; SET @Code = N'deactivated';
                    SET @CurrentStatus = @ExistingToStatus;
                END
                ELSE SET @Code = N'idempotency-conflict';
            END
            ELSE IF @CurrentRowVersion <> @ExpectedRowVersion SET @Code = N'etag-conflict';
            ELSE IF @CurrentStatus NOT IN (0, 1, 2, 3) SET @Code = N'invalid-transition';
            ELSE
            BEGIN
                DECLARE @Updated TABLE (RowVersion BINARY(8));
                UPDATE dbo.FundingPlatform_FundingOpportunities
                SET PublicationStatus = 4, IsActive = 0,
                    UpdatedByUserId = @ActorUserId, UpdatedAtUtc = @NowUtc
                OUTPUT inserted.RowVersion INTO @Updated (RowVersion)
                WHERE Id = @OpportunityId AND RowVersion = @ExpectedRowVersion;
                SELECT @ResultRowVersion = RowVersion FROM @Updated;
                IF @ResultRowVersion IS NULL SET @Code = N'etag-conflict';
                ELSE
                BEGIN
                    INSERT INTO dbo.FundingPlatform_FundingOpportunityEditorialEvents
                        (EventId, FundingOpportunityId, ContentVersion, FromStatus, ToStatus,
                         ActionCode, ActorUserId, Reason, IdempotencyKeyHash, RequestHash,
                         ResultRowVersion, ResultCompleteness, ResultSubmittedAtUtc,
                         ResultPublishedAtUtc, ResultReviewedAtUtc,
                         ResultReviewedByUserPublicId, ResultRejectionReason, CreatedAtUtc)
                    VALUES (@EventId, @OpportunityId, @ContentVersion, @CurrentStatus, 4,
                            N'Deactivate', @ActorUserId, NULLIF(LTRIM(RTRIM(@Reason)), N''),
                            @IdempotencyKeyHash, @RequestHash, @ResultRowVersion, NULL,
                            @SubmittedAtUtc, @PublishedAtUtc, @ReviewedAtUtc,
                            @ReviewedByUserPublicId, @RejectionReason, @NowUtc);
                    INSERT INTO dbo.FundingPlatform_OutboxMessages
                        (MessageId, MessageType, AggregateType, AggregateId, PayloadJson,
                         OccurredAtUtc, AvailableAtUtc)
                    SELECT @EventId, N'FundingOpportunityDeactivated', N'FundingOpportunity',
                           CONVERT(NVARCHAR(100), @OpportunityId),
                           (SELECT @EventId AS eventId, @OpportunityId AS fundingOpportunityId,
                                   @FundingOpportunityPublicId AS fundingOpportunityPublicId,
                                   @ContentVersion AS contentVersion,
                                   @CurrentStatus AS fromStatus, 4 AS toStatus
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), @NowUtc, @NowUtc;
                    SET @Succeeded = 1; SET @Code = N'deactivated'; SET @CurrentStatus = 4;
                END;
            END;
        END;
        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FP_OppDeactivate;
        THROW;
    END CATCH;

    SELECT @Succeeded AS Succeeded, @Code AS Code, CAST(NULL AS DECIMAL(5,2)) AS Completeness,
           @FundingOpportunityPublicId AS FundingOpportunityPublicId,
           @ContentVersion AS ContentVersion, @CurrentStatus AS PublicationStatus,
           @SubmittedAtUtc AS SubmittedAtUtc, @PublishedAtUtc AS PublishedAtUtc,
           @ReviewedAtUtc AS ReviewedAtUtc,
           @ReviewedByUserPublicId AS ReviewedByUserPublicId,
           @RejectionReason AS RejectionReason,
           COALESCE(@ResultRowVersion, @CurrentRowVersion) AS RowVersion, @WasReplay AS WasReplay;
END;
GO

