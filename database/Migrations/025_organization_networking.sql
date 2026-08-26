/* FundingPlatform FASE 10B - opt-in organization networking and moderated Connect requests.
   Requires 019. No member PII, email, phone or private project data is exposed. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_ifn_OrganizationMarketplaceReady', N'IF') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ifn_ProjectMarketplaceReady', N'IF') IS NULL
    THROW 54601, N'FASE 10B requires migration 019.', 1;

CREATE TABLE dbo.FundingPlatform_OrganizationNetworkingPreferences
(
    OrganizationId BIGINT NOT NULL,
    IsDiscoverable BIT NOT NULL,
    AllowRequests BIT NOT NULL,
    UpdatedByUserId BIGINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_OrganizationNetworkingPreferences PRIMARY KEY (OrganizationId),
    CONSTRAINT FundingPlatform_FK_OrganizationNetworkingPreferences_Organization
        FOREIGN KEY (OrganizationId) REFERENCES dbo.FundingPlatform_Organizations (Id),
    CONSTRAINT FundingPlatform_FK_OrganizationNetworkingPreferences_UpdatedBy
        FOREIGN KEY (UpdatedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_OrganizationNetworkingPreferences_Membership
        FOREIGN KEY (OrganizationId, UpdatedByUserId)
        REFERENCES dbo.FundingPlatform_OrganizationUsers (OrganizationId, UserId),
    CONSTRAINT FundingPlatform_CK_OrganizationNetworkingPreferences_State CHECK
        (IsDiscoverable = 1 OR AllowRequests = 0),
    CONSTRAINT FundingPlatform_CK_OrganizationNetworkingPreferences_Time CHECK
        (CreatedAtUtc <= UpdatedAtUtc)
);

CREATE TABLE dbo.FundingPlatform_OrganizationConnectionRequests
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_OrganizationConnectionRequests_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    RequesterOrganizationId BIGINT NOT NULL,
    RecipientOrganizationId BIGINT NOT NULL,
    RequestedByUserId BIGINT NOT NULL,
    RequesterProjectId BIGINT NULL,
    RequesterOrganizationNameSnapshot NVARCHAR(250) NOT NULL,
    RecipientOrganizationNameSnapshot NVARCHAR(250) NOT NULL,
    RequesterProjectPublicIdSnapshot UNIQUEIDENTIFIER NULL,
    RequesterProjectSlugSnapshot NVARCHAR(180) NULL,
    RequesterProjectTitleSnapshot NVARCHAR(250) NULL,
    PurposeCode TINYINT NOT NULL,
    Message NVARCHAR(500) NOT NULL,
    Status TINYINT NOT NULL,
    ActionedByUserId BIGINT NULL,
    ActionedAtUtc DATETIME2(3) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    RowVersion ROWVERSION NOT NULL,
    PairLowOrganizationId AS
        (CASE WHEN RequesterOrganizationId < RecipientOrganizationId
              THEN RequesterOrganizationId ELSE RecipientOrganizationId END) PERSISTED,
    PairHighOrganizationId AS
        (CASE WHEN RequesterOrganizationId < RecipientOrganizationId
              THEN RecipientOrganizationId ELSE RequesterOrganizationId END) PERSISTED,
    CONSTRAINT FundingPlatform_PK_OrganizationConnectionRequests PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_OrganizationConnectionRequests_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_OrganizationConnectionRequests_IdRequester
        UNIQUE (Id, RequesterOrganizationId),
    CONSTRAINT FundingPlatform_FK_OrganizationConnectionRequests_Requester
        FOREIGN KEY (RequesterOrganizationId) REFERENCES dbo.FundingPlatform_Organizations (Id),
    CONSTRAINT FundingPlatform_FK_OrganizationConnectionRequests_Recipient
        FOREIGN KEY (RecipientOrganizationId) REFERENCES dbo.FundingPlatform_Organizations (Id),
    CONSTRAINT FundingPlatform_FK_OrganizationConnectionRequests_RequestedBy
        FOREIGN KEY (RequestedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_OrganizationConnectionRequests_RequesterMembership
        FOREIGN KEY (RequesterOrganizationId, RequestedByUserId)
        REFERENCES dbo.FundingPlatform_OrganizationUsers (OrganizationId, UserId),
    CONSTRAINT FundingPlatform_FK_OrganizationConnectionRequests_Project
        FOREIGN KEY (RequesterProjectId) REFERENCES dbo.FundingPlatform_Projects (Id),
    CONSTRAINT FundingPlatform_FK_OrganizationConnectionRequests_ProjectRequester
        FOREIGN KEY (RequesterProjectId, RequesterOrganizationId)
        REFERENCES dbo.FundingPlatform_Projects (Id, OrganizationId),
    CONSTRAINT FundingPlatform_FK_OrganizationConnectionRequests_ActionedBy
        FOREIGN KEY (ActionedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    /* 0 pending, 1 accepted, 2 rejected, 3 cancelled, 4 blocked. */
    CONSTRAINT FundingPlatform_CK_OrganizationConnectionRequests_Status CHECK (Status BETWEEN 0 AND 4),
    /* 0 partnership, 1 expertise, 2 geographic reach, 3 consortium exploration. */
    CONSTRAINT FundingPlatform_CK_OrganizationConnectionRequests_Purpose CHECK (PurposeCode BETWEEN 0 AND 3),
    CONSTRAINT FundingPlatform_CK_OrganizationConnectionRequests_DifferentOrganizations CHECK
        (RequesterOrganizationId <> RecipientOrganizationId),
    CONSTRAINT FundingPlatform_CK_OrganizationConnectionRequests_Message CHECK
        (LEN(LTRIM(RTRIM(Message))) BETWEEN 10 AND 500
         AND DATALENGTH(Message) = DATALENGTH(LTRIM(RTRIM(Message)))
         AND Message NOT LIKE N'%@%'
         AND LOWER(Message) NOT LIKE N'%http:%'
         AND LOWER(Message) NOT LIKE N'%https:%'
         AND LOWER(Message) NOT LIKE N'%www.%'
         AND Message NOT LIKE N'%[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%'),
    CONSTRAINT FundingPlatform_CK_OrganizationConnectionRequests_Snapshots CHECK
        (LEN(LTRIM(RTRIM(RequesterOrganizationNameSnapshot))) BETWEEN 1 AND 250
         AND LEN(LTRIM(RTRIM(RecipientOrganizationNameSnapshot))) BETWEEN 1 AND 250
         AND ((RequesterProjectId IS NULL AND RequesterProjectPublicIdSnapshot IS NULL
               AND RequesterProjectSlugSnapshot IS NULL AND RequesterProjectTitleSnapshot IS NULL)
              OR (RequesterProjectId IS NOT NULL AND RequesterProjectPublicIdSnapshot IS NOT NULL
                  AND LEN(RequesterProjectSlugSnapshot) BETWEEN 1 AND 180
                  AND LEN(RequesterProjectTitleSnapshot) BETWEEN 1 AND 250))),
    CONSTRAINT FundingPlatform_CK_OrganizationConnectionRequests_Action CHECK
        ((Status = 0 AND ActionedByUserId IS NULL AND ActionedAtUtc IS NULL)
         OR (Status <> 0 AND ActionedByUserId IS NOT NULL AND ActionedAtUtc IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_OrganizationConnectionRequests_Time CHECK
        (CreatedAtUtc <= UpdatedAtUtc
         AND (ActionedAtUtc IS NULL OR ActionedAtUtc BETWEEN CreatedAtUtc AND UpdatedAtUtc))
);

CREATE UNIQUE INDEX FundingPlatform_UX_OrganizationConnectionRequests_ActivePair
    ON dbo.FundingPlatform_OrganizationConnectionRequests
        (PairLowOrganizationId, PairHighOrganizationId)
    WHERE Status IN (0, 1);
CREATE INDEX FundingPlatform_IX_OrganizationConnectionRequests_RequesterStatus
    ON dbo.FundingPlatform_OrganizationConnectionRequests
        (RequesterOrganizationId, Status, UpdatedAtUtc DESC, Id DESC);
CREATE INDEX FundingPlatform_IX_OrganizationConnectionRequests_RecipientStatus
    ON dbo.FundingPlatform_OrganizationConnectionRequests
        (RecipientOrganizationId, Status, UpdatedAtUtc DESC, Id DESC);
CREATE INDEX FundingPlatform_IX_OrganizationConnectionRequests_BlockedPair
    ON dbo.FundingPlatform_OrganizationConnectionRequests
        (PairLowOrganizationId, PairHighOrganizationId, Status)
    WHERE Status = 4;

CREATE TABLE dbo.FundingPlatform_OrganizationConnectionCreateRequests
(
    RequesterOrganizationId BIGINT NOT NULL,
    RequestedByUserId BIGINT NOT NULL,
    IdempotencyKeyHash BINARY(32) NOT NULL,
    RequestHash BINARY(32) NOT NULL,
    OrganizationConnectionRequestId BIGINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_OrganizationConnectionCreateRequests
        PRIMARY KEY (RequesterOrganizationId, RequestedByUserId, IdempotencyKeyHash),
    CONSTRAINT FundingPlatform_FK_OrganizationConnectionCreateRequests_Membership
        FOREIGN KEY (RequesterOrganizationId, RequestedByUserId)
        REFERENCES dbo.FundingPlatform_OrganizationUsers (OrganizationId, UserId),
    CONSTRAINT FundingPlatform_FK_OrganizationConnectionCreateRequests_Request
        FOREIGN KEY (OrganizationConnectionRequestId, RequesterOrganizationId)
        REFERENCES dbo.FundingPlatform_OrganizationConnectionRequests (Id, RequesterOrganizationId)
);
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_OrganizationConnectionRequests_Lifecycle
ON dbo.FundingPlatform_OrganizationConnectionRequests
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted) AND NOT EXISTS (SELECT 1 FROM inserted)
        THROW 54605, N'Organization connection history is immutable.', 1;
    IF EXISTS
    (
        SELECT 1
        FROM inserted AS currentRows
        INNER JOIN deleted AS previousRows ON previousRows.Id = currentRows.Id
        WHERE currentRows.PublicId <> previousRows.PublicId
           OR currentRows.RequesterOrganizationId <> previousRows.RequesterOrganizationId
           OR currentRows.RecipientOrganizationId <> previousRows.RecipientOrganizationId
           OR currentRows.RequestedByUserId <> previousRows.RequestedByUserId
           OR ISNULL(currentRows.RequesterProjectId, -1) <> ISNULL(previousRows.RequesterProjectId, -1)
           OR currentRows.RequesterOrganizationNameSnapshot <> previousRows.RequesterOrganizationNameSnapshot
           OR currentRows.RecipientOrganizationNameSnapshot <> previousRows.RecipientOrganizationNameSnapshot
           OR ISNULL(currentRows.RequesterProjectPublicIdSnapshot, '00000000-0000-0000-0000-000000000000') <>
              ISNULL(previousRows.RequesterProjectPublicIdSnapshot, '00000000-0000-0000-0000-000000000000')
           OR ISNULL(currentRows.RequesterProjectSlugSnapshot, N'') <>
              ISNULL(previousRows.RequesterProjectSlugSnapshot, N'')
           OR ISNULL(currentRows.RequesterProjectTitleSnapshot, N'') <>
              ISNULL(previousRows.RequesterProjectTitleSnapshot, N'')
           OR currentRows.PurposeCode <> previousRows.PurposeCode
           OR currentRows.Message <> previousRows.Message
           OR currentRows.CreatedAtUtc <> previousRows.CreatedAtUtc
           OR currentRows.UpdatedAtUtc < previousRows.UpdatedAtUtc
           OR NOT ((previousRows.Status = 0 AND currentRows.Status BETWEEN 1 AND 4)
                   OR (previousRows.Status = 1 AND currentRows.Status = 4))
    )
        THROW 54605, N'Organization connection history can only advance through its moderated lifecycle.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_OrganizationConnectionCreateRequests_Immutable
ON dbo.FundingPlatform_OrganizationConnectionCreateRequests
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted)
        THROW 54605, N'Organization connection idempotency ledger is immutable.', 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_OrganizationNetworkingPreference_Get
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT;
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.PublicId = @UserPublicId AND users.Status = 2
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.UserId = users.Id
       AND memberships.MembershipStatus = 1
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1;
    IF @OrganizationId IS NULL THROW 54603, N'Networking workspace not found.', 1;

    SELECT CONVERT(BIT, CASE WHEN preferences.OrganizationId IS NULL THEN 0 ELSE 1 END) AS Exists,
           COALESCE(preferences.IsDiscoverable, CONVERT(BIT, 0)) AS IsDiscoverable,
           COALESCE(preferences.AllowRequests, CONVERT(BIT, 0)) AS AllowRequests,
           preferences.CreatedAtUtc, preferences.UpdatedAtUtc, preferences.RowVersion
    FROM (VALUES (@OrganizationId)) AS scope(OrganizationId)
    LEFT JOIN dbo.FundingPlatform_OrganizationNetworkingPreferences AS preferences
        ON preferences.OrganizationId = scope.OrganizationId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_OrganizationNetworkingPreference_Put
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @IsDiscoverable BIT,
    @AllowRequests BIT,
    @ExpectedRowVersion BINARY(8) = NULL,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @IsDiscoverable IS NULL OR @AllowRequests IS NULL OR
       (@IsDiscoverable = 0 AND @AllowRequests = 1)
        THROW 54602, N'Networking preference is invalid.', 1;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @Role TINYINT;
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id, @Role = memberships.Role
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.PublicId = @UserPublicId AND users.Status = 2
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.UserId = users.Id
       AND memberships.MembershipStatus = 1
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1;
    IF @OrganizationId IS NULL THROW 54603, N'Networking workspace not found.', 1;
    IF @Role <> 1 THROW 54604, N'Organization administrator required.', 1;

    BEGIN TRANSACTION;
    DECLARE @CurrentRowVersion BINARY(8);
    SELECT @CurrentRowVersion = RowVersion
    FROM dbo.FundingPlatform_OrganizationNetworkingPreferences WITH (UPDLOCK, HOLDLOCK)
    WHERE OrganizationId = @OrganizationId;
    IF @CurrentRowVersion IS NULL
    BEGIN
        IF @ExpectedRowVersion IS NOT NULL
        BEGIN ROLLBACK; SELECT N'etag-conflict' AS Code; RETURN; END;
        INSERT dbo.FundingPlatform_OrganizationNetworkingPreferences
            (OrganizationId, IsDiscoverable, AllowRequests, UpdatedByUserId, CreatedAtUtc, UpdatedAtUtc)
        VALUES (@OrganizationId, @IsDiscoverable, @AllowRequests, @UserId, @NowUtc, @NowUtc);
        COMMIT; SELECT N'created' AS Code; RETURN;
    END;
    IF @ExpectedRowVersion IS NULL
    BEGIN ROLLBACK; SELECT N'precondition-required' AS Code; RETURN; END;
    IF @CurrentRowVersion <> @ExpectedRowVersion
    BEGIN ROLLBACK; SELECT N'etag-conflict' AS Code; RETURN; END;
    UPDATE dbo.FundingPlatform_OrganizationNetworkingPreferences
    SET IsDiscoverable = @IsDiscoverable, AllowRequests = @AllowRequests,
        UpdatedByUserId = @UserId, UpdatedAtUtc = @NowUtc
    WHERE OrganizationId = @OrganizationId;
    COMMIT; SELECT N'updated' AS Code;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_OrganizationNetworkDirectory_Search
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @Query NVARCHAR(200) = NULL,
    @CountryIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @CategoryIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @PageNumber INT,
    @PageSize INT
AS
BEGIN
    SET NOCOUNT ON;
    IF @PageNumber < 1 OR @PageNumber > 10000 OR @PageSize < 1 OR @PageSize > 50 OR
       LEN(COALESCE(@Query, N'')) > 200 OR
       (SELECT COUNT_BIG(*) FROM @CountryIds) > 50 OR
       (SELECT COUNT_BIG(*) FROM @CategoryIds) > 50 OR
       (SELECT COUNT_BIG(*) FROM @ProjectTypeIds) > 50
        THROW 54602, N'Networking directory filters are invalid.', 1;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT;
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.PublicId = @UserPublicId AND users.Status = 2
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.UserId = users.Id
       AND memberships.MembershipStatus = 1
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1;
    IF @OrganizationId IS NULL THROW 54603, N'Networking workspace not found.', 1;

    DECLARE @Pattern NVARCHAR(410) = NULL;
    IF @Query IS NOT NULL
        SET @Pattern = N'%' + REPLACE(REPLACE(REPLACE(REPLACE(@Query, N'~', N'~~'),
            N'%', N'~%'), N'_', N'~_'), N'[', N'~[') + N'%';

    CREATE TABLE #Directory
    (
        OrganizationId BIGINT NOT NULL PRIMARY KEY,
        OrganizationPublicId UNIQUEIDENTIFIER NOT NULL,
        Name NVARCHAR(250) NOT NULL,
        Description NVARCHAR(2000) NULL,
        WebsiteUrl NVARCHAR(2048) NULL,
        HomeCountryId SMALLINT NOT NULL,
        HomeCountryCode CHAR(2) NOT NULL,
        HomeCountryName NVARCHAR(120) NOT NULL,
        OrganizationTypeId SMALLINT NOT NULL,
        OrganizationTypeCode NVARCHAR(100) NOT NULL,
        OrganizationTypeName NVARCHAR(150) NOT NULL,
        VisibleProjectCount INT NOT NULL,
        AllowsRequests BIT NOT NULL,
        ConnectionPublicId UNIQUEIDENTIFIER NULL,
        ConnectionState TINYINT NOT NULL
    );
    INSERT #Directory
    SELECT organizations.Id, organizations.PublicId, organizations.Name,
           organizations.Description, organizations.WebsiteUrl,
           countries.Id, countries.Iso2, countries.Name,
           organizationTypes.Id, organizationTypes.Code, organizationTypes.Name,
           projects.VisibleProjectCount, preferences.AllowRequests, activeConnection.PublicId,
           CONVERT(TINYINT, CASE WHEN activeConnection.Id IS NULL THEN 0
                WHEN activeConnection.Status = 1 THEN 3
                WHEN activeConnection.RequesterOrganizationId = @OrganizationId THEN 1
                ELSE 2 END)
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_ifn_OrganizationMarketplaceReady() AS ready
        ON ready.OrganizationId = organizations.Id
    INNER JOIN dbo.FundingPlatform_OrganizationNetworkingPreferences AS preferences
        ON preferences.OrganizationId = organizations.Id
       AND preferences.IsDiscoverable = 1
    INNER JOIN dbo.FundingPlatform_Countries AS countries
        ON countries.Id = organizations.HomeCountryId AND countries.IsActive = 1
    INNER JOIN dbo.FundingPlatform_OrganizationTypes AS organizationTypes
        ON organizationTypes.Id = organizations.OrganizationTypeId AND organizationTypes.IsActive = 1
    CROSS APPLY
    (
        SELECT COUNT_BIG(*) AS VisibleProjectCount
        FROM dbo.FundingPlatform_ifn_ProjectMarketplaceReady() AS readyProjects
        WHERE readyProjects.OrganizationId = organizations.Id
        HAVING COUNT_BIG(*) > 0
    ) AS projects
    OUTER APPLY
    (
        SELECT TOP (1) requests.Id, requests.PublicId, requests.Status,
               requests.RequesterOrganizationId
        FROM dbo.FundingPlatform_OrganizationConnectionRequests AS requests
        WHERE requests.Status IN (0, 1)
          AND ((requests.RequesterOrganizationId = @OrganizationId
                AND requests.RecipientOrganizationId = organizations.Id)
            OR (requests.RecipientOrganizationId = @OrganizationId
                AND requests.RequesterOrganizationId = organizations.Id))
        ORDER BY requests.Id DESC
    ) AS activeConnection
    WHERE organizations.Id <> @OrganizationId
      AND (@Query IS NULL OR organizations.Name LIKE @Pattern ESCAPE N'~'
           OR organizations.Description LIKE @Pattern ESCAPE N'~')
      AND (NOT EXISTS (SELECT 1 FROM @CountryIds) OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OrganizationCountries AS links
           INNER JOIN @CountryIds AS filters ON filters.Id = links.CountryId
           WHERE links.OrganizationId = organizations.Id))
      AND (NOT EXISTS (SELECT 1 FROM @CategoryIds) OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OrganizationCategories AS links
           INNER JOIN @CategoryIds AS filters ON filters.Id = links.FundingCategoryId
           WHERE links.OrganizationId = organizations.Id))
      AND (NOT EXISTS (SELECT 1 FROM @ProjectTypeIds) OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OrganizationProjectTypes AS links
           INNER JOIN @ProjectTypeIds AS filters ON filters.Id = links.ProjectTypeId
           WHERE links.OrganizationId = organizations.Id))
      AND NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OrganizationConnectionRequests AS blocked
           WHERE blocked.Status = 4
             AND blocked.PairLowOrganizationId = CASE WHEN @OrganizationId < organizations.Id
                 THEN @OrganizationId ELSE organizations.Id END
             AND blocked.PairHighOrganizationId = CASE WHEN @OrganizationId < organizations.Id
                 THEN organizations.Id ELSE @OrganizationId END);

    SELECT COUNT_BIG(*) AS TotalCount FROM #Directory;
    SELECT directory.OrganizationPublicId, directory.Name, directory.Description,
           directory.WebsiteUrl, directory.HomeCountryId,
           RTRIM(directory.HomeCountryCode) AS HomeCountryCode, directory.HomeCountryName,
           directory.OrganizationTypeId, directory.OrganizationTypeCode,
           directory.OrganizationTypeName, directory.VisibleProjectCount, directory.AllowsRequests,
           directory.ConnectionPublicId, directory.ConnectionState,
           (SELECT categories.Id, categories.Code, categories.Name
            FROM dbo.FundingPlatform_OrganizationCategories AS links
            INNER JOIN dbo.FundingPlatform_FundingCategories AS categories
                ON categories.Id = links.FundingCategoryId AND categories.IsActive = 1
            WHERE links.OrganizationId = directory.OrganizationId
            ORDER BY categories.Name, categories.Id FOR JSON PATH) AS CategoriesJson,
           (SELECT projectTypes.Id, projectTypes.Code, projectTypes.Name
            FROM dbo.FundingPlatform_OrganizationProjectTypes AS links
            INNER JOIN dbo.FundingPlatform_ProjectTypes AS projectTypes
                ON projectTypes.Id = links.ProjectTypeId AND projectTypes.IsActive = 1
            WHERE links.OrganizationId = directory.OrganizationId
            ORDER BY projectTypes.Name, projectTypes.Id FOR JSON PATH) AS ProjectTypesJson
    FROM #Directory AS directory
    ORDER BY directory.Name, directory.OrganizationId
    OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_OrganizationConnection_Get
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ConnectionPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @Role TINYINT;
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id, @Role = memberships.Role
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.PublicId = @UserPublicId AND users.Status = 2
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.UserId = users.Id
       AND memberships.MembershipStatus = 1
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1;
    IF @OrganizationId IS NULL THROW 54603, N'Networking workspace not found.', 1;

    SELECT requests.PublicId AS ConnectionPublicId,
           CONVERT(TINYINT, CASE WHEN requests.RequesterOrganizationId = @OrganizationId THEN 2 ELSE 1 END) AS Direction,
           requests.Status,
           requests.PurposeCode, requests.Message,
           CASE WHEN requests.RequesterOrganizationId = @OrganizationId
                THEN recipient.PublicId ELSE requester.PublicId END AS CounterpartyOrganizationPublicId,
           CASE WHEN requests.RequesterOrganizationId = @OrganizationId
                THEN requests.RecipientOrganizationNameSnapshot
                ELSE requests.RequesterOrganizationNameSnapshot END AS CounterpartyOrganizationName,
           CONVERT(BIT, CASE WHEN publicCounterparty.OrganizationId IS NULL THEN 0 ELSE 1 END) AS CounterpartyIsPublic,
           requests.RequesterProjectPublicIdSnapshot, requests.RequesterProjectSlugSnapshot,
           requests.RequesterProjectTitleSnapshot,
           CONVERT(BIT, CASE WHEN @Role = 1 AND requests.RecipientOrganizationId = @OrganizationId
                                  AND requests.Status = 0 THEN 1 ELSE 0 END) AS CanRespond,
           CONVERT(BIT, CASE WHEN @Role = 1 AND requests.RequesterOrganizationId = @OrganizationId
                                  AND requests.Status = 0 THEN 1 ELSE 0 END) AS CanCancel,
           CONVERT(BIT, CASE WHEN @Role = 1 AND
                                  ((requests.RecipientOrganizationId = @OrganizationId AND requests.Status = 0)
                                   OR requests.Status = 1) THEN 1 ELSE 0 END) AS CanBlock,
           requests.CreatedAtUtc, requests.UpdatedAtUtc, requests.ActionedAtUtc,
           requests.RowVersion
    FROM dbo.FundingPlatform_OrganizationConnectionRequests AS requests
    INNER JOIN dbo.FundingPlatform_Organizations AS requester
        ON requester.Id = requests.RequesterOrganizationId
    INNER JOIN dbo.FundingPlatform_Organizations AS recipient
        ON recipient.Id = requests.RecipientOrganizationId
    OUTER APPLY
    (
        SELECT ready.OrganizationId
        FROM dbo.FundingPlatform_ifn_OrganizationMarketplaceReady() AS ready
        WHERE ready.OrganizationId = CASE WHEN requests.RequesterOrganizationId = @OrganizationId
                                          THEN requests.RecipientOrganizationId
                                          ELSE requests.RequesterOrganizationId END
          AND EXISTS (SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMarketplaceReady() AS projects
                      WHERE projects.OrganizationId = ready.OrganizationId)
    ) AS publicCounterparty
    WHERE requests.PublicId = @ConnectionPublicId
      AND @OrganizationId IN (requests.RequesterOrganizationId, requests.RecipientOrganizationId);
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_OrganizationConnection_List
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @Direction TINYINT,
    @Status TINYINT = NULL,
    @PageNumber INT,
    @PageSize INT
AS
BEGIN
    SET NOCOUNT ON;
    IF @Direction NOT BETWEEN 0 AND 2 OR (@Status IS NOT NULL AND @Status NOT BETWEEN 0 AND 4)
       OR @PageNumber < 1 OR @PageNumber > 10000 OR @PageSize < 1 OR @PageSize > 50
        THROW 54602, N'Connection list filters are invalid.', 1;
    DECLARE @OrganizationId BIGINT, @Role TINYINT;
    SELECT @OrganizationId = organizations.Id, @Role = memberships.Role
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.PublicId = @UserPublicId AND users.Status = 2
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.UserId = users.Id
       AND memberships.MembershipStatus = 1
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1;
    IF @OrganizationId IS NULL THROW 54603, N'Networking workspace not found.', 1;

    CREATE TABLE #Ids (Id BIGINT NOT NULL PRIMARY KEY);
    INSERT #Ids
    SELECT requests.Id
    FROM dbo.FundingPlatform_OrganizationConnectionRequests AS requests
    WHERE @OrganizationId IN (requests.RequesterOrganizationId, requests.RecipientOrganizationId)
      AND (@Direction = 0 OR (@Direction = 1 AND requests.RecipientOrganizationId = @OrganizationId)
           OR (@Direction = 2 AND requests.RequesterOrganizationId = @OrganizationId))
      AND (@Status IS NULL OR requests.Status = @Status);
    SELECT COUNT_BIG(*) AS TotalCount FROM #Ids;
    SELECT requests.PublicId AS ConnectionPublicId,
           CONVERT(TINYINT, CASE WHEN requests.RequesterOrganizationId = @OrganizationId THEN 2 ELSE 1 END) AS Direction,
           requests.Status,
           requests.PurposeCode, requests.Message,
           CASE WHEN requests.RequesterOrganizationId = @OrganizationId
                THEN recipient.PublicId ELSE requester.PublicId END AS CounterpartyOrganizationPublicId,
           CASE WHEN requests.RequesterOrganizationId = @OrganizationId
                THEN requests.RecipientOrganizationNameSnapshot
                ELSE requests.RequesterOrganizationNameSnapshot END AS CounterpartyOrganizationName,
           CONVERT(BIT, CASE WHEN publicCounterparty.OrganizationId IS NULL THEN 0 ELSE 1 END) AS CounterpartyIsPublic,
           requests.RequesterProjectPublicIdSnapshot, requests.RequesterProjectSlugSnapshot,
           requests.RequesterProjectTitleSnapshot,
           CONVERT(BIT, CASE WHEN @Role = 1 AND requests.RecipientOrganizationId = @OrganizationId
                                  AND requests.Status = 0 THEN 1 ELSE 0 END) AS CanRespond,
           CONVERT(BIT, CASE WHEN @Role = 1 AND requests.RequesterOrganizationId = @OrganizationId
                                  AND requests.Status = 0 THEN 1 ELSE 0 END) AS CanCancel,
           CONVERT(BIT, CASE WHEN @Role = 1 AND
                                  ((requests.RecipientOrganizationId = @OrganizationId AND requests.Status = 0)
                                   OR requests.Status = 1) THEN 1 ELSE 0 END) AS CanBlock,
           requests.CreatedAtUtc, requests.UpdatedAtUtc, requests.ActionedAtUtc,
           requests.RowVersion
    FROM #Ids AS ids
    INNER JOIN dbo.FundingPlatform_OrganizationConnectionRequests AS requests ON requests.Id = ids.Id
    INNER JOIN dbo.FundingPlatform_Organizations AS requester
        ON requester.Id = requests.RequesterOrganizationId
    INNER JOIN dbo.FundingPlatform_Organizations AS recipient
        ON recipient.Id = requests.RecipientOrganizationId
    OUTER APPLY
    (
        SELECT ready.OrganizationId
        FROM dbo.FundingPlatform_ifn_OrganizationMarketplaceReady() AS ready
        WHERE ready.OrganizationId = CASE WHEN requests.RequesterOrganizationId = @OrganizationId
                                          THEN requests.RecipientOrganizationId
                                          ELSE requests.RequesterOrganizationId END
          AND EXISTS (SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMarketplaceReady() AS projects
                      WHERE projects.OrganizationId = ready.OrganizationId)
    ) AS publicCounterparty
    ORDER BY requests.UpdatedAtUtc DESC, requests.Id DESC
    OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_OrganizationConnection_Create
    @UserPublicId UNIQUEIDENTIFIER,
    @RequesterOrganizationPublicId UNIQUEIDENTIFIER,
    @RecipientOrganizationPublicId UNIQUEIDENTIFIER,
    @RequesterProjectPublicId UNIQUEIDENTIFIER = NULL,
    @PurposeCode TINYINT,
    @Message NVARCHAR(500),
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @PurposeCode NOT BETWEEN 0 AND 3 OR LEN(LTRIM(RTRIM(COALESCE(@Message, N'')))) NOT BETWEEN 10 AND 500
       OR DATALENGTH(@Message) <> DATALENGTH(LTRIM(RTRIM(@Message))) OR @Message LIKE N'%@%'
       OR LOWER(@Message) LIKE N'%http:%' OR LOWER(@Message) LIKE N'%https:%'
       OR LOWER(@Message) LIKE N'%www.%'
       OR @Message LIKE N'%[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%'
       OR @IdempotencyKeyHash IS NULL OR @RequestHash IS NULL
        THROW 54602, N'Connection request is invalid.', 1;
    DECLARE @RequesterId BIGINT, @RecipientId BIGINT, @UserId BIGINT, @Role TINYINT,
            @ProjectId BIGINT, @RequesterName NVARCHAR(250), @RecipientName NVARCHAR(250),
            @ProjectSlug NVARCHAR(180), @ProjectTitle NVARCHAR(250),
            @ProjectPublicId UNIQUEIDENTIFIER;
    SELECT @RequesterId = organizations.Id, @RequesterName = organizations.Name,
           @UserId = users.Id, @Role = memberships.Role
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.PublicId = @UserPublicId AND users.Status = 2
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.UserId = users.Id
       AND memberships.MembershipStatus = 1
    WHERE organizations.PublicId = @RequesterOrganizationPublicId AND organizations.IsActive = 1;
    IF @RequesterId IS NULL THROW 54603, N'Networking workspace not found.', 1;
    IF @Role <> 1 THROW 54604, N'Organization administrator required.', 1;

    BEGIN TRANSACTION;
    DECLARE @ExistingId BIGINT, @ExistingRequestHash BINARY(32), @ExistingPublicId UNIQUEIDENTIFIER;
    SELECT @ExistingId = ledger.OrganizationConnectionRequestId,
           @ExistingRequestHash = ledger.RequestHash
    FROM dbo.FundingPlatform_OrganizationConnectionCreateRequests AS ledger WITH (UPDLOCK, HOLDLOCK)
    WHERE ledger.RequesterOrganizationId = @RequesterId AND ledger.RequestedByUserId = @UserId
      AND ledger.IdempotencyKeyHash = @IdempotencyKeyHash;
    IF @ExistingId IS NOT NULL
    BEGIN
        IF @ExistingRequestHash <> @RequestHash
        BEGIN ROLLBACK; SELECT N'idempotency-conflict' AS Code,
            CAST(NULL AS UNIQUEIDENTIFIER) AS ConnectionPublicId; RETURN; END;
        SELECT @ExistingPublicId = PublicId
        FROM dbo.FundingPlatform_OrganizationConnectionRequests WHERE Id = @ExistingId;
        COMMIT; SELECT N'replayed' AS Code, @ExistingPublicId AS ConnectionPublicId; RETURN;
    END;

    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_OrganizationNetworkingPreferences WITH (UPDLOCK, HOLDLOCK)
        WHERE OrganizationId = @RequesterId AND IsDiscoverable = 1)
    BEGIN ROLLBACK; SELECT N'networking-disabled' AS Code,
        CAST(NULL AS UNIQUEIDENTIFIER) AS ConnectionPublicId; RETURN; END;
    SELECT @RecipientId = organizations.Id, @RecipientName = organizations.Name
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_ifn_OrganizationMarketplaceReady() AS ready
        ON ready.OrganizationId = organizations.Id
    INNER JOIN dbo.FundingPlatform_OrganizationNetworkingPreferences AS preferences WITH (UPDLOCK, HOLDLOCK)
        ON preferences.OrganizationId = organizations.Id
       AND preferences.IsDiscoverable = 1 AND preferences.AllowRequests = 1
    WHERE organizations.PublicId = @RecipientOrganizationPublicId
      AND EXISTS (SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMarketplaceReady() AS projects
                  WHERE projects.OrganizationId = organizations.Id);
    IF @RecipientId IS NULL OR @RecipientId = @RequesterId
    BEGIN ROLLBACK; SELECT N'not-found' AS Code,
        CAST(NULL AS UNIQUEIDENTIFIER) AS ConnectionPublicId; RETURN; END;

    IF @RequesterProjectPublicId IS NOT NULL
    BEGIN
        SELECT @ProjectId = projects.Id, @ProjectPublicId = projects.PublicId,
               @ProjectSlug = projects.Slug, @ProjectTitle = projects.Title
        FROM dbo.FundingPlatform_Projects AS projects
        INNER JOIN dbo.FundingPlatform_ifn_ProjectMarketplaceReady() AS ready
            ON ready.ProjectId = projects.Id AND ready.OrganizationId = @RequesterId
        WHERE projects.PublicId = @RequesterProjectPublicId;
        IF @ProjectId IS NULL
        BEGIN ROLLBACK; SELECT N'project-not-found' AS Code,
            CAST(NULL AS UNIQUEIDENTIFIER) AS ConnectionPublicId; RETURN; END;
    END;
    DECLARE @PairLow BIGINT = CASE WHEN @RequesterId < @RecipientId THEN @RequesterId ELSE @RecipientId END,
            @PairHigh BIGINT = CASE WHEN @RequesterId < @RecipientId THEN @RecipientId ELSE @RequesterId END;
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_OrganizationConnectionRequests WITH (UPDLOCK, HOLDLOCK)
               WHERE PairLowOrganizationId = @PairLow AND PairHighOrganizationId = @PairHigh AND Status = 4)
    BEGIN ROLLBACK; SELECT N'not-found' AS Code,
        CAST(NULL AS UNIQUEIDENTIFIER) AS ConnectionPublicId; RETURN; END;
    SELECT TOP (1) @ExistingPublicId = PublicId
    FROM dbo.FundingPlatform_OrganizationConnectionRequests WITH (UPDLOCK, HOLDLOCK)
    WHERE PairLowOrganizationId = @PairLow AND PairHighOrganizationId = @PairHigh AND Status IN (0, 1);
    IF @ExistingPublicId IS NOT NULL
    BEGIN ROLLBACK; SELECT N'already-exists' AS Code, @ExistingPublicId AS ConnectionPublicId; RETURN; END;
    IF (SELECT COUNT_BIG(*) FROM dbo.FundingPlatform_OrganizationConnectionRequests
        WHERE RequesterOrganizationId = @RequesterId AND CreatedAtUtc > DATEADD(HOUR, -24, @NowUtc)) >= 5
       OR (SELECT COUNT_BIG(*) FROM dbo.FundingPlatform_OrganizationConnectionRequests
           WHERE RequesterOrganizationId = @RequesterId AND Status = 0) >= 20
    BEGIN ROLLBACK; SELECT N'rate-limit' AS Code,
        CAST(NULL AS UNIQUEIDENTIFIER) AS ConnectionPublicId; RETURN; END;

    INSERT dbo.FundingPlatform_OrganizationConnectionRequests
        (RequesterOrganizationId, RecipientOrganizationId, RequestedByUserId,
         RequesterProjectId, RequesterOrganizationNameSnapshot, RecipientOrganizationNameSnapshot,
         RequesterProjectPublicIdSnapshot, RequesterProjectSlugSnapshot, RequesterProjectTitleSnapshot,
         PurposeCode, Message, Status, ActionedByUserId, ActionedAtUtc, CreatedAtUtc, UpdatedAtUtc)
    VALUES (@RequesterId, @RecipientId, @UserId, @ProjectId, @RequesterName, @RecipientName,
            @ProjectPublicId, @ProjectSlug, @ProjectTitle, @PurposeCode, @Message, 0,
            NULL, NULL, @NowUtc, @NowUtc);
    SET @ExistingId = SCOPE_IDENTITY();
    SELECT @ExistingPublicId = PublicId
    FROM dbo.FundingPlatform_OrganizationConnectionRequests WHERE Id = @ExistingId;
    INSERT dbo.FundingPlatform_OrganizationConnectionCreateRequests
        (RequesterOrganizationId, RequestedByUserId, IdempotencyKeyHash, RequestHash,
         OrganizationConnectionRequestId, CreatedAtUtc)
    VALUES (@RequesterId, @UserId, @IdempotencyKeyHash, @RequestHash, @ExistingId, @NowUtc);
    COMMIT; SELECT N'created' AS Code, @ExistingPublicId AS ConnectionPublicId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_OrganizationConnection_Action
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ConnectionPublicId UNIQUEIDENTIFIER,
    @ActionCode TINYINT,
    @ExpectedRowVersion BINARY(8),
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    /* 1 accept, 2 reject, 3 cancel, 4 block. */
    IF @ActionCode NOT BETWEEN 1 AND 4 OR @ExpectedRowVersion IS NULL
        THROW 54602, N'Connection action is invalid.', 1;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @Role TINYINT;
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id, @Role = memberships.Role
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.PublicId = @UserPublicId AND users.Status = 2
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.UserId = users.Id
       AND memberships.MembershipStatus = 1
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1;
    IF @OrganizationId IS NULL THROW 54603, N'Networking workspace not found.', 1;
    IF @Role <> 1 THROW 54604, N'Organization administrator required.', 1;

    BEGIN TRANSACTION;
    DECLARE @RequestId BIGINT, @RequesterId BIGINT, @RecipientId BIGINT,
            @Status TINYINT, @RowVersion BINARY(8);
    SELECT @RequestId = Id, @RequesterId = RequesterOrganizationId,
           @RecipientId = RecipientOrganizationId, @Status = Status, @RowVersion = RowVersion
    FROM dbo.FundingPlatform_OrganizationConnectionRequests WITH (UPDLOCK, HOLDLOCK)
    WHERE PublicId = @ConnectionPublicId
      AND @OrganizationId IN (RequesterOrganizationId, RecipientOrganizationId);
    IF @RequestId IS NULL
    BEGIN ROLLBACK; SELECT N'not-found' AS Code; RETURN; END;
    IF @RowVersion <> @ExpectedRowVersion
    BEGIN ROLLBACK; SELECT N'etag-conflict' AS Code; RETURN; END;
    IF NOT ((@ActionCode IN (1, 2) AND @OrganizationId = @RecipientId AND @Status = 0)
            OR (@ActionCode = 3 AND @OrganizationId = @RequesterId AND @Status = 0)
            OR (@ActionCode = 4 AND ((@OrganizationId = @RecipientId AND @Status = 0)
                                     OR @Status = 1)))
    BEGIN ROLLBACK; SELECT N'invalid-transition' AS Code; RETURN; END;
    UPDATE dbo.FundingPlatform_OrganizationConnectionRequests
    SET Status = @ActionCode, ActionedByUserId = @UserId,
        ActionedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc
    WHERE Id = @RequestId;
    COMMIT; SELECT CASE @ActionCode WHEN 1 THEN N'accepted' WHEN 2 THEN N'rejected'
        WHEN 3 THEN N'cancelled' ELSE N'blocked' END AS Code;
END;
GO
