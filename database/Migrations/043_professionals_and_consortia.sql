/* Block 5. Opt-in professional discovery and explicitly accepted consortium membership.
   No automatic matching, account-role grants, email delivery or publication side effects. */
SET XACT_ABORT ON;
GO
CREATE TABLE dbo.FundingPlatform_ProfessionalProfiles
(
    Id BIGINT IDENTITY NOT NULL PRIMARY KEY,
    PublicId UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() UNIQUE,
    UserId BIGINT NOT NULL UNIQUE REFERENCES dbo.FundingPlatform_Users(Id),
    DataJson NVARCHAR(MAX) NOT NULL,
    CountryId SMALLINT NULL REFERENCES dbo.FundingPlatform_Countries(Id),
    IsDiscoverable BIT NOT NULL DEFAULT 0,
    AllowsInvitations BIT NOT NULL DEFAULT 0,
    CreatedAtUtc DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAtUtc DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_CK_ProfessionalProfiles_Json CHECK (ISJSON(DataJson) = 1 AND LEFT(LTRIM(DataJson), 1) = N'{'),
    CONSTRAINT FundingPlatform_CK_ProfessionalProfiles_Consent CHECK (IsDiscoverable = 1 OR AllowsInvitations = 0)
);
CREATE INDEX FundingPlatform_IX_ProfessionalProfiles_Discovery ON dbo.FundingPlatform_ProfessionalProfiles(IsDiscoverable, CountryId, UpdatedAtUtc DESC);
CREATE TABLE dbo.FundingPlatform_Consortia
(
    Id BIGINT IDENTITY NOT NULL PRIMARY KEY,
    PublicId UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() UNIQUE,
    ProjectId BIGINT NOT NULL UNIQUE,
    LeadOrganizationId BIGINT NOT NULL,
    Name NVARCHAR(160) NOT NULL,
    Summary NVARCHAR(1000) NULL,
    Status TINYINT NOT NULL DEFAULT 0,
    CreatedByUserId BIGINT NOT NULL REFERENCES dbo.FundingPlatform_Users(Id),
    CreatedAtUtc DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAtUtc DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_FK_Consortia_ProjectOrganization FOREIGN KEY (ProjectId, LeadOrganizationId) REFERENCES dbo.FundingPlatform_Projects(Id, OrganizationId),
    CONSTRAINT FundingPlatform_CK_Consortia_Name CHECK (LEN(LTRIM(RTRIM(Name))) BETWEEN 2 AND 160),
    CONSTRAINT FundingPlatform_CK_Consortia_Status CHECK (Status BETWEEN 0 AND 2)
);
CREATE TABLE dbo.FundingPlatform_ConsortiumParticipants
(
    Id BIGINT IDENTITY NOT NULL PRIMARY KEY,
    PublicId UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() UNIQUE,
    ConsortiumId BIGINT NOT NULL REFERENCES dbo.FundingPlatform_Consortia(Id),
    Kind TINYINT NOT NULL,
    OrganizationId BIGINT NULL REFERENCES dbo.FundingPlatform_Organizations(Id),
    ProfessionalProfileId BIGINT NULL REFERENCES dbo.FundingPlatform_ProfessionalProfiles(Id),
    Contribution NVARCHAR(160) NOT NULL,
    Message NVARCHAR(500) NOT NULL,
    Status TINYINT NOT NULL DEFAULT 0,
    InvitedByUserId BIGINT NOT NULL REFERENCES dbo.FundingPlatform_Users(Id),
    CreatedAtUtc DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAtUtc DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_CK_ConsortiumParticipants_Kind CHECK
        ((Kind = 1 AND OrganizationId IS NOT NULL AND ProfessionalProfileId IS NULL)
         OR (Kind = 2 AND OrganizationId IS NULL AND ProfessionalProfileId IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_ConsortiumParticipants_Status CHECK (Status BETWEEN 0 AND 5),
    CONSTRAINT FundingPlatform_CK_ConsortiumParticipants_Contribution CHECK (LEN(LTRIM(RTRIM(Contribution))) BETWEEN 2 AND 160),
    CONSTRAINT FundingPlatform_CK_ConsortiumParticipants_Message CHECK
        (LEN(LTRIM(RTRIM(Message))) BETWEEN 10 AND 500 AND Message NOT LIKE N'%@%'
         AND LOWER(Message) NOT LIKE N'%http:%' AND LOWER(Message) NOT LIKE N'%https:%'
         AND LOWER(Message) NOT LIKE N'%www.%'
         AND Message NOT LIKE N'%[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%')
);
CREATE UNIQUE INDEX FundingPlatform_UX_ConsortiumParticipants_Organization ON dbo.FundingPlatform_ConsortiumParticipants(ConsortiumId, OrganizationId) WHERE OrganizationId IS NOT NULL;
CREATE UNIQUE INDEX FundingPlatform_UX_ConsortiumParticipants_Professional ON dbo.FundingPlatform_ConsortiumParticipants(ConsortiumId, ProfessionalProfileId) WHERE ProfessionalProfileId IS NOT NULL;
CREATE INDEX FundingPlatform_IX_ConsortiumParticipants_ProfessionalInbox ON dbo.FundingPlatform_ConsortiumParticipants(ProfessionalProfileId, Status, ConsortiumId);
CREATE INDEX FundingPlatform_IX_ConsortiumParticipants_OrganizationInbox ON dbo.FundingPlatform_ConsortiumParticipants(OrganizationId, Status, ConsortiumId);
CREATE TABLE dbo.FundingPlatform_CollaborationEvents
(
    Id BIGINT IDENTITY NOT NULL PRIMARY KEY,
    ActorUserId BIGINT NOT NULL REFERENCES dbo.FundingPlatform_Users(Id),
    EntityPublicId UNIQUEIDENTIFIER NOT NULL,
    ActionCode NVARCHAR(40) NOT NULL,
    IdempotencyKeyHash BINARY(32) NOT NULL,
    RequestHash BINARY(32) NOT NULL,
    ResultRowVersion BINARY(8) NOT NULL,
    SnapshotJson NVARCHAR(MAX) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FundingPlatform_UQ_CollaborationEvents_Command UNIQUE (ActorUserId, IdempotencyKeyHash),
    CONSTRAINT FundingPlatform_CK_CollaborationEvents_Snapshot CHECK (ISJSON(SnapshotJson) = 1)
);
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Collaboration_User
    @UserPublicId UNIQUEIDENTIFIER, @UserId BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @UserId = NULL;
    SELECT @UserId = Id FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
    WHERE PublicId = @UserPublicId AND Status = 2 AND EmailConfirmed = 1;
    IF @UserId IS NULL THROW 55502, N'Collaboration access denied.', 1;
END;
GO
/* Call only after authorization inside a write transaction. No direct runtime grant. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Collaboration_Replay
    @UserId BIGINT, @KeyHash BINARY(32), @RequestHash BINARY(32),
    @EntityId UNIQUEIDENTIFIER OUTPUT, @RowVersion BINARY(8) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @KeyHash IS NULL OR @RequestHash IS NULL OR @@TRANCOUNT = 0 THROW 55505, N'Invalid command envelope.', 1;
    SET @EntityId = NULL; SET @RowVersion = NULL;
    DECLARE @PreviousHash BINARY(32);
    SELECT @EntityId = EntityPublicId, @RowVersion = ResultRowVersion, @PreviousHash = RequestHash
    FROM dbo.FundingPlatform_CollaborationEvents WITH (UPDLOCK, HOLDLOCK)
    WHERE ActorUserId = @UserId AND IdempotencyKeyHash = @KeyHash;
    IF @EntityId IS NOT NULL AND @PreviousHash <> @RequestHash THROW 55506, N'Idempotency conflict.', 1;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProfessionalProfile_GetOwn
    @UserPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UserId BIGINT;
    EXEC dbo.FundingPlatform_usp_Collaboration_User @UserPublicId, @UserId OUTPUT;
    SELECT (SELECT PublicId AS profileId, JSON_QUERY(DataJson) AS data,
        N'"' + CONVERT(NVARCHAR(16), RowVersion, 2) + N'"' AS eTag,
        TODATETIMEOFFSET(UpdatedAtUtc, '+00:00') AS updatedAtUtc
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS Json
    FROM dbo.FundingPlatform_ProfessionalProfiles WHERE UserId = @UserId;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProfessionalProfile_Search
    @UserPublicId UNIQUEIDENTIFIER, @Query NVARCHAR(300) = NULL,
    @CountryId SMALLINT = NULL, @CategoryId INT = NULL, @Page INT = 1, @PageSize INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UserId BIGINT;
    EXEC dbo.FundingPlatform_usp_Collaboration_User @UserPublicId, @UserId OUTPUT;
    IF LEN(LTRIM(RTRIM(COALESCE(@Query, N'')))) > 200 OR @CountryId <= 0 OR @CategoryId <= 0
        OR @Page IS NULL OR @Page NOT BETWEEN 1 AND 10000 OR @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 50
        THROW 55505, N'Invalid directory filters.', 1;
    DECLARE @Pattern NVARCHAR(610) = NULL;
    IF NULLIF(LTRIM(RTRIM(@Query)), N'') IS NOT NULL
        SET @Pattern = N'%' + REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Query)), N'~', N'~~'), N'%', N'~%'), N'_', N'~_'), N'[', N'~[') + N'%';
    SELECT profiles.Id, profiles.PublicId, profiles.DataJson INTO #Profiles
    FROM dbo.FundingPlatform_ProfessionalProfiles AS profiles
    INNER JOIN dbo.FundingPlatform_Users AS users ON users.Id = profiles.UserId AND users.Status = 2 AND users.EmailConfirmed = 1
    WHERE profiles.IsDiscoverable = 1
      AND (@CountryId IS NULL OR profiles.CountryId = @CountryId)
      AND (@CategoryId IS NULL OR EXISTS (SELECT 1 FROM OPENJSON(profiles.DataJson, '$.categoryIds') WHERE TRY_CONVERT(INT, value) = @CategoryId))
      AND (@Pattern IS NULL OR JSON_VALUE(profiles.DataJson, '$.displayName') LIKE @Pattern ESCAPE N'~'
           OR JSON_VALUE(profiles.DataJson, '$.headline') LIKE @Pattern ESCAPE N'~'
           OR EXISTS (SELECT 1 FROM OPENJSON(profiles.DataJson, '$.skills') WHERE value LIKE @Pattern ESCAPE N'~'));
    SELECT (SELECT (SELECT COUNT_BIG(1) FROM #Profiles) AS totalCount, @Page AS page, @PageSize AS pageSize,
        JSON_QUERY((SELECT PublicId AS profileId, JSON_QUERY(DataJson) AS data FROM #Profiles
            ORDER BY Id DESC OFFSET ((CONVERT(BIGINT, @Page) - 1) * @PageSize) ROWS FETCH NEXT @PageSize ROWS ONLY FOR JSON PATH)) AS items
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS Json;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProfessionalProfile_Save
    @UserPublicId UNIQUEIDENTIFIER, @DataJson NVARCHAR(MAX), @ExpectedRowVersion BINARY(8) = NULL,
    @KeyHash BINARY(32), @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF ISJSON(@DataJson) <> 1 OR LEFT(LTRIM(@DataJson), 1) <> N'{' THROW 55505, N'Invalid profile.', 1;
    IF COALESCE(LEN(JSON_VALUE(@DataJson, '$.displayName')), 0) NOT BETWEEN 2 AND 120
       OR COALESCE(LEN(JSON_VALUE(@DataJson, '$.headline')), 0) NOT BETWEEN 2 AND 160
       OR (SELECT MAX(LEN(value)) FROM OPENJSON(@DataJson) WHERE [key] = N'biography') > 2000
       OR COALESCE(JSON_VALUE(@DataJson, '$.isDiscoverable'), N'') NOT IN (N'true', N'false')
       OR COALESCE(JSON_VALUE(@DataJson, '$.allowsInvitations'), N'') NOT IN (N'true', N'false')
       OR LEFT(COALESCE(JSON_QUERY(@DataJson, '$.skills'), N''), 1) <> N'['
       OR LEFT(COALESCE(JSON_QUERY(@DataJson, '$.languageIds'), N''), 1) <> N'['
       OR LEFT(COALESCE(JSON_QUERY(@DataJson, '$.categoryIds'), N''), 1) <> N'['
       OR (SELECT COUNT_BIG(1) FROM OPENJSON(@DataJson, '$.skills')) > 20
       OR (SELECT COUNT_BIG(1) FROM OPENJSON(@DataJson, '$.languageIds')) > 20
       OR (SELECT COUNT_BIG(1) FROM OPENJSON(@DataJson, '$.categoryIds')) > 30
       OR EXISTS (SELECT 1 FROM OPENJSON(@DataJson, '$.skills') WHERE type <> 1 OR LEN(LTRIM(RTRIM(value))) NOT BETWEEN 2 AND 80)
        THROW 55505, N'Invalid profile fields.', 1;
    DECLARE @CountryId SMALLINT = TRY_CONVERT(SMALLINT, JSON_VALUE(@DataJson, '$.countryId'));
    DECLARE @Discoverable BIT = CASE WHEN JSON_VALUE(@DataJson, '$.isDiscoverable') = N'true' THEN 1 ELSE 0 END;
    DECLARE @Invitations BIT = CASE WHEN JSON_VALUE(@DataJson, '$.allowsInvitations') = N'true' THEN 1 ELSE 0 END;
    IF (@Discoverable = 0 AND @Invitations = 1)
       OR (JSON_VALUE(@DataJson, '$.countryId') IS NOT NULL AND @CountryId IS NULL)
       OR (@CountryId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Countries WHERE Id = @CountryId AND IsActive = 1))
       OR EXISTS (SELECT 1 FROM OPENJSON(@DataJson, '$.languageIds') AS valueset
           LEFT JOIN dbo.FundingPlatform_Languages AS catalog ON catalog.Id = TRY_CONVERT(SMALLINT, valueset.value) AND catalog.IsActive = 1
           WHERE valueset.type <> 2 OR catalog.Id IS NULL)
       OR EXISTS (SELECT 1 FROM OPENJSON(@DataJson, '$.categoryIds') AS valueset
           LEFT JOIN dbo.FundingPlatform_FundingCategories AS catalog ON catalog.Id = TRY_CONVERT(INT, valueset.value) AND catalog.IsActive = 1
           WHERE valueset.type <> 2 OR catalog.Id IS NULL)
        THROW 55505, N'Invalid profile consent or catalog.', 1;
    DECLARE @Initial INT = @@TRANCOUNT;
    IF @Initial = 0 BEGIN TRANSACTION; ELSE SAVE TRANSACTION FP_ProfileSave;
    BEGIN TRY
        DECLARE @UserId BIGINT, @EntityId UNIQUEIDENTIFIER, @Version BINARY(8), @Replay BIT = 0;
        EXEC dbo.FundingPlatform_usp_Collaboration_User @UserPublicId, @UserId OUTPUT;
        EXEC dbo.FundingPlatform_usp_Collaboration_Replay @UserId, @KeyHash, @RequestHash, @EntityId OUTPUT, @Version OUTPUT;
        IF @EntityId IS NOT NULL SET @Replay = 1;
        ELSE
        BEGIN
            DECLARE @ProfileId BIGINT, @Current BINARY(8);
            SELECT @ProfileId = Id, @Current = RowVersion FROM dbo.FundingPlatform_ProfessionalProfiles WITH (UPDLOCK, HOLDLOCK) WHERE UserId = @UserId;
            IF (@ProfileId IS NULL AND @ExpectedRowVersion IS NOT NULL)
               OR (@ProfileId IS NOT NULL AND (@ExpectedRowVersion IS NULL OR @Current <> @ExpectedRowVersion))
                THROW 55503, N'Profile version conflict.', 1;
            IF @ProfileId IS NULL
            BEGIN
                INSERT INTO dbo.FundingPlatform_ProfessionalProfiles(UserId, DataJson, CountryId, IsDiscoverable, AllowsInvitations)
                VALUES (@UserId, @DataJson, @CountryId, @Discoverable, @Invitations);
                SET @ProfileId = SCOPE_IDENTITY();
            END
            ELSE UPDATE dbo.FundingPlatform_ProfessionalProfiles SET DataJson = @DataJson, CountryId = @CountryId,
                IsDiscoverable = @Discoverable, AllowsInvitations = @Invitations, UpdatedAtUtc = SYSUTCDATETIME() WHERE Id = @ProfileId;
            SELECT @EntityId = PublicId, @Version = RowVersion FROM dbo.FundingPlatform_ProfessionalProfiles WHERE Id = @ProfileId;
            INSERT INTO dbo.FundingPlatform_CollaborationEvents(ActorUserId, EntityPublicId, ActionCode, IdempotencyKeyHash, RequestHash, ResultRowVersion, SnapshotJson)
            VALUES (@UserId, @EntityId, N'ProfileSave', @KeyHash, @RequestHash, @Version, @DataJson);
        END;
        IF @Initial = 0 COMMIT TRANSACTION;
        SELECT @EntityId AS EntityId, N'"' + CONVERT(NVARCHAR(16), @Version, 2) + N'"' AS ETag, @Replay AS WasReplay;
    END TRY
    BEGIN CATCH
        IF @Initial = 0 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_ProfileSave;
        THROW;
    END CATCH;
END;
GO
/* Only active membership, or an explicit live invitation/acceptance, grants access.
   Pending/blocked participants never receive the roster. Global Admin is not an override. */
CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_ConsortiumAccess(@UserId BIGINT)
RETURNS TABLE AS RETURN
(
    SELECT consortia.Id AS ConsortiumId,
        CONVERT(BIT, CASE WHEN lead.Role = 1 THEN 1 ELSE 0 END) AS CanManage,
        CONVERT(BIT, CASE WHEN lead.Role IS NOT NULL THEN 1 ELSE 0 END) AS IsLeadMember,
        CONVERT(BIT, CASE WHEN lead.Role IS NOT NULL OR participants.HasAccepted = 1 THEN 1 ELSE 0 END) AS CanViewRoster,
        CONVERT(BIT, COALESCE(participants.HasPending, 0)) AS HasPendingInvitation
    FROM dbo.FundingPlatform_Consortia AS consortia
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations ON organizations.Id = consortia.LeadOrganizationId AND organizations.IsActive = 1
    INNER JOIN dbo.FundingPlatform_Users AS users ON users.Id = @UserId AND users.Status = 2 AND users.EmailConfirmed = 1
    OUTER APPLY (SELECT memberships.Role FROM dbo.FundingPlatform_OrganizationUsers AS memberships
        WHERE memberships.OrganizationId = consortia.LeadOrganizationId AND memberships.UserId = @UserId AND memberships.MembershipStatus = 1) AS lead
    OUTER APPLY (SELECT MAX(CASE WHEN participant.Status = 1 AND blocked.Id IS NULL THEN 1 ELSE 0 END) AS HasAccepted,
        MAX(CASE WHEN participant.Status = 1 OR memberships.Role = 1 OR profiles.UserId = @UserId THEN 1 ELSE 0 END) AS HasAccess,
        MAX(CASE WHEN participant.Status = 0 AND (memberships.Role = 1 OR profiles.UserId = @UserId) THEN 1 ELSE 0 END) AS HasPending
        FROM dbo.FundingPlatform_ConsortiumParticipants AS participant
        LEFT JOIN dbo.FundingPlatform_ProfessionalProfiles AS profiles ON profiles.Id = participant.ProfessionalProfileId AND profiles.UserId = @UserId
        LEFT JOIN dbo.FundingPlatform_Organizations AS recipient ON recipient.Id = participant.OrganizationId AND recipient.IsActive = 1
        LEFT JOIN dbo.FundingPlatform_OrganizationUsers AS memberships ON memberships.OrganizationId = recipient.Id AND memberships.UserId = @UserId AND memberships.MembershipStatus = 1
        OUTER APPLY (SELECT TOP(1) requests.Id FROM dbo.FundingPlatform_OrganizationConnectionRequests AS requests
            WHERE requests.Status = 4 AND ((requests.RequesterOrganizationId = consortia.LeadOrganizationId AND requests.RecipientOrganizationId = participant.OrganizationId)
                OR (requests.RecipientOrganizationId = consortia.LeadOrganizationId AND requests.RequesterOrganizationId = participant.OrganizationId))) AS blocked
        WHERE participant.ConsortiumId = consortia.Id AND participant.Status IN (0, 1)
          AND (profiles.UserId = @UserId OR memberships.Role IS NOT NULL)) AS participants
    WHERE lead.Role IS NOT NULL OR participants.HasAccess = 1
);
GO
CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_ConsortiumSummaries(@UserId BIGINT)
RETURNS TABLE AS RETURN
(
    SELECT consortia.Id, consortia.PublicId AS ConsortiumId, projects.PublicId AS ProjectId,
        CASE WHEN ready.ProjectId IS NOT NULL OR access.IsLeadMember = 1 THEN projects.Title END AS ProjectTitle,
        CASE WHEN ready.ProjectId IS NOT NULL THEN projects.Slug END AS ProjectSlug,
        CONVERT(BIT, CASE WHEN ready.ProjectId IS NULL THEN 0 ELSE 1 END) AS ProjectIsPublic,
        consortia.Name, consortia.Summary, organizations.PublicId AS LeadOrganizationId, organizations.Name AS LeadOrganizationName, consortia.Status,
        access.CanManage, access.CanViewRoster, access.HasPendingInvitation,
        CASE WHEN access.CanViewRoster = 1 THEN (SELECT COUNT(1) FROM dbo.FundingPlatform_ConsortiumParticipants WHERE ConsortiumId = consortia.Id AND Status = 1) ELSE 0 END AS AcceptedCount,
        N'"' + CONVERT(NVARCHAR(16), consortia.RowVersion, 2) + N'"' AS ETag,
        TODATETIMEOFFSET(consortia.UpdatedAtUtc, '+00:00') AS UpdatedAtUtc
    FROM dbo.FundingPlatform_Consortia AS consortia
    INNER JOIN dbo.FundingPlatform_ifn_ConsortiumAccess(@UserId) AS access ON access.ConsortiumId = consortia.Id
    INNER JOIN dbo.FundingPlatform_Projects AS projects ON projects.Id = consortia.ProjectId
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations ON organizations.Id = consortia.LeadOrganizationId
    LEFT JOIN dbo.FundingPlatform_ifn_ProjectMarketplaceReady() AS ready ON ready.ProjectId = projects.Id
);
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Consortium_List
    @UserPublicId UNIQUEIDENTIFIER, @Page INT = 1, @PageSize INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UserId BIGINT;
    EXEC dbo.FundingPlatform_usp_Collaboration_User @UserPublicId, @UserId OUTPUT;
    IF @Page IS NULL OR @Page NOT BETWEEN 1 AND 10000 OR @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 50 THROW 55505, N'Invalid pagination.', 1;
    SELECT * INTO #Consortia FROM dbo.FundingPlatform_ifn_ConsortiumSummaries(@UserId);
    SELECT (SELECT (SELECT COUNT_BIG(1) FROM #Consortia) AS totalCount, @Page AS page, @PageSize AS pageSize,
        JSON_QUERY((SELECT ConsortiumId, ProjectId, ProjectTitle, ProjectSlug, ProjectIsPublic, Name, Summary,
            LeadOrganizationId, LeadOrganizationName, Status, CanManage, CanViewRoster, HasPendingInvitation, AcceptedCount, ETag, UpdatedAtUtc FROM #Consortia
            ORDER BY UpdatedAtUtc DESC, Id DESC OFFSET ((CONVERT(BIGINT, @Page) - 1) * @PageSize) ROWS FETCH NEXT @PageSize ROWS ONLY
            FOR JSON PATH, INCLUDE_NULL_VALUES)) AS items FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS Json;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Consortium_Get
    @UserPublicId UNIQUEIDENTIFIER, @ConsortiumPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UserId BIGINT, @Id BIGINT, @Manage BIT, @Roster BIT;
    EXEC dbo.FundingPlatform_usp_Collaboration_User @UserPublicId, @UserId OUTPUT;
    SELECT @Id = Id, @Manage = CanManage, @Roster = CanViewRoster FROM dbo.FundingPlatform_ifn_ConsortiumSummaries(@UserId) WHERE ConsortiumId = @ConsortiumPublicId;
    IF @Id IS NULL THROW 55501, N'Consortium not available.', 1;
    SELECT (SELECT JSON_QUERY((SELECT ConsortiumId, ProjectId, ProjectTitle, ProjectSlug, ProjectIsPublic, Name, Summary,
            LeadOrganizationId, LeadOrganizationName, Status, CanManage, CanViewRoster, HasPendingInvitation, AcceptedCount, ETag, UpdatedAtUtc
            FROM dbo.FundingPlatform_ifn_ConsortiumSummaries(@UserId) WHERE Id = @Id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES)) AS consortium,
        JSON_QUERY((SELECT participants.PublicId AS participantId, participants.Kind AS kind,
            COALESCE(organizations.PublicId, profiles.PublicId) AS targetId,
            COALESCE(organizations.Name, JSON_VALUE(profiles.DataJson, '$.displayName')) AS displayName,
            participants.Contribution AS contribution,
            CASE WHEN @Manage = 1 OR recipient.IsRecipient = 1 THEN participants.Message ELSE N'' END AS message,
            participants.Status AS status,
            CONVERT(BIT, CASE WHEN recipient.IsRecipient = 1 AND participants.Status = 0 AND consortia.Status <> 2 THEN 1 ELSE 0 END) AS canRespond,
            CONVERT(BIT, CASE WHEN recipient.IsRecipient = 1 AND participants.Status = 1 THEN 1 ELSE 0 END) AS canLeave,
            CONVERT(BIT, CASE WHEN @Manage = 1 AND participants.Status = 0 THEN 1 ELSE 0 END) AS canCancel,
            CONVERT(BIT, CASE WHEN @Manage = 1 AND participants.Status = 1 THEN 1 ELSE 0 END) AS canRemove,
            N'"' + CONVERT(NVARCHAR(16), participants.RowVersion, 2) + N'"' AS eTag,
            TODATETIMEOFFSET(participants.UpdatedAtUtc, '+00:00') AS updatedAtUtc
            FROM dbo.FundingPlatform_ConsortiumParticipants AS participants
            INNER JOIN dbo.FundingPlatform_Consortia AS consortia ON consortia.Id = participants.ConsortiumId
            LEFT JOIN dbo.FundingPlatform_Organizations AS organizations ON organizations.Id = participants.OrganizationId
            LEFT JOIN dbo.FundingPlatform_ProfessionalProfiles AS profiles ON profiles.Id = participants.ProfessionalProfileId
            OUTER APPLY (SELECT CONVERT(BIT, CASE WHEN profiles.UserId = @UserId OR EXISTS
                (SELECT 1 FROM dbo.FundingPlatform_OrganizationUsers WHERE OrganizationId = organizations.Id AND UserId = @UserId AND MembershipStatus = 1 AND Role = 1 AND organizations.IsActive = 1)
                THEN 1 ELSE 0 END) AS IsRecipient) AS recipient
            WHERE participants.ConsortiumId = @Id AND (@Manage = 1 OR (@Roster = 1 AND participants.Status = 1) OR recipient.IsRecipient = 1)
            ORDER BY participants.CreatedAtUtc, participants.Id FOR JSON PATH)) AS participants
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS Json;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Consortium_Create
    @UserPublicId UNIQUEIDENTIFIER, @ProjectPublicId UNIQUEIDENTIFIER, @Name NVARCHAR(300), @Summary NVARCHAR(MAX) = NULL,
    @KeyHash BINARY(32), @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF COALESCE(LEN(LTRIM(RTRIM(@Name))), 0) NOT BETWEEN 2 AND 160 OR LEN(@Summary) > 1000 THROW 55505, N'Invalid consortium fields.', 1;
    DECLARE @Initial INT = @@TRANCOUNT;
    IF @Initial = 0 BEGIN TRANSACTION; ELSE SAVE TRANSACTION FP_CCreate;
    BEGIN TRY
        DECLARE @UserId BIGINT, @EntityId UNIQUEIDENTIFIER, @Version BINARY(8), @Replay BIT = 0, @Snapshot NVARCHAR(MAX);
        EXEC dbo.FundingPlatform_usp_Collaboration_User @UserPublicId, @UserId OUTPUT;
        DECLARE @ProjectId BIGINT, @LeadId BIGINT;
        SELECT @ProjectId = projects.Id, @LeadId = projects.OrganizationId
        FROM dbo.FundingPlatform_Projects AS projects WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_Organizations AS organizations ON organizations.Id = projects.OrganizationId AND organizations.IsActive = 1
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id AND memberships.UserId = @UserId AND memberships.Role = 1 AND memberships.MembershipStatus = 1
        WHERE projects.PublicId = @ProjectPublicId AND projects.PublicationStatus <> 4;
        IF @ProjectId IS NULL THROW 55501, N'Project is not available for consortium management.', 1;
        EXEC dbo.FundingPlatform_usp_Collaboration_Replay @UserId, @KeyHash, @RequestHash, @EntityId OUTPUT, @Version OUTPUT;
        IF @EntityId IS NOT NULL SET @Replay = 1;
        ELSE
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_Consortia WITH (UPDLOCK, HOLDLOCK) WHERE ProjectId = @ProjectId)
                THROW 55504, N'This project already has a consortium.', 1;
            INSERT INTO dbo.FundingPlatform_Consortia(ProjectId, LeadOrganizationId, Name, Summary, CreatedByUserId)
            VALUES (@ProjectId, @LeadId, LTRIM(RTRIM(@Name)), NULLIF(LTRIM(RTRIM(@Summary)), N''), @UserId);
            DECLARE @CreatedId BIGINT = SCOPE_IDENTITY();
            SELECT @EntityId = PublicId, @Version = RowVersion FROM dbo.FundingPlatform_Consortia WHERE Id = @CreatedId;
            SET @Snapshot = (SELECT @ProjectPublicId AS projectId, @Name AS name, @Summary AS summary, 0 AS status FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO dbo.FundingPlatform_CollaborationEvents(ActorUserId, EntityPublicId, ActionCode, IdempotencyKeyHash, RequestHash, ResultRowVersion, SnapshotJson)
            VALUES (@UserId, @EntityId, N'ConsortiumCreate', @KeyHash, @RequestHash, @Version, @Snapshot);
        END;
        IF @Initial = 0 COMMIT TRANSACTION;
        SELECT @EntityId AS EntityId, N'"' + CONVERT(NVARCHAR(16), @Version, 2) + N'"' AS ETag, @Replay AS WasReplay;
    END TRY
    BEGIN CATCH
        IF @Initial = 0 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_CCreate;
        THROW;
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Consortium_Update
    @UserPublicId UNIQUEIDENTIFIER, @ConsortiumPublicId UNIQUEIDENTIFIER, @Name NVARCHAR(300), @Summary NVARCHAR(MAX) = NULL, @Status TINYINT, @ExpectedRowVersion BINARY(8),
    @KeyHash BINARY(32), @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF COALESCE(LEN(LTRIM(RTRIM(@Name))), 0) NOT BETWEEN 2 AND 160 OR LEN(@Summary) > 1000 OR @Status IS NULL OR @Status NOT BETWEEN 0 AND 2 THROW 55505, N'Invalid consortium fields.', 1;
    DECLARE @Initial INT = @@TRANCOUNT;
    IF @Initial = 0 BEGIN TRANSACTION; ELSE SAVE TRANSACTION FP_CUpdate;
    BEGIN TRY
        DECLARE @UserId BIGINT, @EntityId UNIQUEIDENTIFIER, @Version BINARY(8), @Replay BIT = 0, @Snapshot NVARCHAR(MAX);
        EXEC dbo.FundingPlatform_usp_Collaboration_User @UserPublicId, @UserId OUTPUT;
        DECLARE @ConsortiumId BIGINT, @LeadId BIGINT, @ProjectId BIGINT, @CurrentStatus TINYINT, @CurrentVersion BINARY(8);
        SELECT @ConsortiumId = consortia.Id, @LeadId = consortia.LeadOrganizationId,
            @ProjectId = consortia.ProjectId, @CurrentStatus = consortia.Status, @CurrentVersion = consortia.RowVersion
        FROM dbo.FundingPlatform_Consortia AS consortia WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_Organizations AS organizations ON organizations.Id = consortia.LeadOrganizationId AND organizations.IsActive = 1
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id AND memberships.UserId = @UserId AND memberships.MembershipStatus = 1 AND memberships.Role = 1
        WHERE consortia.PublicId = @ConsortiumPublicId;
        IF @ConsortiumId IS NULL THROW 55501, N'Consortium not available.', 1;
        EXEC dbo.FundingPlatform_usp_Collaboration_Replay @UserId, @KeyHash, @RequestHash, @EntityId OUTPUT, @Version OUTPUT;
        IF @EntityId IS NOT NULL SET @Replay = 1;
        ELSE
        BEGIN
            IF @ExpectedRowVersion IS NULL OR @CurrentVersion <> @ExpectedRowVersion THROW 55503, N'Consortium version conflict.', 1;
            IF @CurrentStatus = 2 OR (@CurrentStatus = 1 AND @Status = 0)
               OR (@CurrentStatus = 0 AND @Status = 1 AND NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_ConsortiumParticipants WITH (UPDLOCK, HOLDLOCK) WHERE ConsortiumId = @ConsortiumId AND Status = 1))
                THROW 55507, N'Consortium state transition is not permitted.', 1;
            UPDATE dbo.FundingPlatform_Consortia SET Name = LTRIM(RTRIM(@Name)), Summary = NULLIF(LTRIM(RTRIM(@Summary)), N''), Status = @Status, UpdatedAtUtc = SYSUTCDATETIME()
            WHERE Id = @ConsortiumId;
            DECLARE @Cancelled TABLE (ParticipantId UNIQUEIDENTIFIER);
            IF @Status = 2 UPDATE dbo.FundingPlatform_ConsortiumParticipants SET Status = 3, UpdatedAtUtc = SYSUTCDATETIME()
                OUTPUT inserted.PublicId INTO @Cancelled WHERE ConsortiumId = @ConsortiumId AND Status = 0;
            SELECT @EntityId = PublicId, @Version = RowVersion FROM dbo.FundingPlatform_Consortia WHERE Id = @ConsortiumId;
            SET @Snapshot = (SELECT @Name AS name, @Summary AS summary, @Status AS status,
                JSON_QUERY((SELECT ParticipantId FROM @Cancelled FOR JSON PATH)) AS cancelledInvitations FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO dbo.FundingPlatform_CollaborationEvents(ActorUserId, EntityPublicId, ActionCode, IdempotencyKeyHash, RequestHash, ResultRowVersion, SnapshotJson)
            VALUES (@UserId, @EntityId, N'ConsortiumUpdate', @KeyHash, @RequestHash, @Version, @Snapshot);
        END;
        IF @Initial = 0 COMMIT TRANSACTION;
        SELECT @EntityId AS EntityId, N'"' + CONVERT(NVARCHAR(16), @Version, 2) + N'"' AS ETag, @Replay AS WasReplay;
    END TRY
    BEGIN CATCH
        IF @Initial = 0 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_CUpdate;
        THROW;
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Consortium_Invite
    @UserPublicId UNIQUEIDENTIFIER, @ConsortiumPublicId UNIQUEIDENTIFIER, @Kind TINYINT, @TargetPublicId UNIQUEIDENTIFIER, @Contribution NVARCHAR(300), @Message NVARCHAR(1000), @ExpectedRowVersion BINARY(8),
    @KeyHash BINARY(32), @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @Kind IS NULL OR @Kind NOT IN (1, 2) OR @TargetPublicId IS NULL
       OR COALESCE(LEN(LTRIM(RTRIM(@Contribution))), 0) NOT BETWEEN 2 AND 160
       OR COALESCE(LEN(LTRIM(RTRIM(@Message))), 0) NOT BETWEEN 10 AND 500
       OR @Message LIKE N'%@%' OR LOWER(@Message) LIKE N'%http:%' OR LOWER(@Message) LIKE N'%https:%'
       OR LOWER(@Message) LIKE N'%www.%' OR @Message LIKE N'%[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%'
        THROW 55505, N'Invalid consortium invitation.', 1;
    DECLARE @Initial INT = @@TRANCOUNT;
    IF @Initial = 0 BEGIN TRANSACTION; ELSE SAVE TRANSACTION FP_CInvite;
    BEGIN TRY
        DECLARE @UserId BIGINT, @EntityId UNIQUEIDENTIFIER, @Version BINARY(8), @Replay BIT = 0, @Snapshot NVARCHAR(MAX);
        EXEC dbo.FundingPlatform_usp_Collaboration_User @UserPublicId, @UserId OUTPUT;
        DECLARE @ConsortiumId BIGINT, @LeadId BIGINT, @ProjectId BIGINT, @CurrentStatus TINYINT, @CurrentVersion BINARY(8);
        SELECT @ConsortiumId = consortia.Id, @LeadId = consortia.LeadOrganizationId,
            @ProjectId = consortia.ProjectId, @CurrentStatus = consortia.Status, @CurrentVersion = consortia.RowVersion
        FROM dbo.FundingPlatform_Consortia AS consortia WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_Organizations AS organizations ON organizations.Id = consortia.LeadOrganizationId AND organizations.IsActive = 1
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            ON memberships.OrganizationId = organizations.Id AND memberships.UserId = @UserId AND memberships.MembershipStatus = 1 AND memberships.Role = 1
        WHERE consortia.PublicId = @ConsortiumPublicId;
        IF @ConsortiumId IS NULL THROW 55501, N'Consortium not available.', 1;
        EXEC dbo.FundingPlatform_usp_Collaboration_Replay @UserId, @KeyHash, @RequestHash, @EntityId OUTPUT, @Version OUTPUT;
        IF @EntityId IS NOT NULL SET @Replay = 1;
        ELSE
        BEGIN
            IF @ExpectedRowVersion IS NULL OR @CurrentVersion <> @ExpectedRowVersion THROW 55503, N'Consortium version conflict.', 1;
            IF @CurrentStatus = 2 OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMarketplaceReady() WHERE ProjectId = @ProjectId)
                THROW 55507, N'A published project and open consortium are required to invite.', 1;
            IF (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_ConsortiumParticipants WITH (UPDLOCK, HOLDLOCK) WHERE ConsortiumId = @ConsortiumId) >= 50
               OR (SELECT COUNT_BIG(1) FROM dbo.FundingPlatform_ConsortiumParticipants WHERE InvitedByUserId = @UserId AND CreatedAtUtc >= DATEADD(DAY, -1, SYSUTCDATETIME())) >= 20
                THROW 55508, N'Consortium invitation limit reached.', 1;
            DECLARE @RecipientOrganizationId BIGINT = NULL, @ProfileId BIGINT = NULL;
            IF @Kind = 1
            BEGIN
                SELECT @RecipientOrganizationId = organizations.Id FROM dbo.FundingPlatform_Organizations AS organizations
                INNER JOIN dbo.FundingPlatform_ifn_OrganizationMarketplaceReady() AS ready ON ready.OrganizationId = organizations.Id
                INNER JOIN dbo.FundingPlatform_OrganizationNetworkingPreferences AS preferences WITH (UPDLOCK, HOLDLOCK) ON preferences.OrganizationId = organizations.Id AND preferences.IsDiscoverable = 1 AND preferences.AllowRequests = 1
                WHERE organizations.PublicId = @TargetPublicId AND organizations.Id <> @LeadId;
                IF @RecipientOrganizationId IS NULL OR NOT EXISTS
                    (SELECT 1 FROM dbo.FundingPlatform_OrganizationConnectionRequests WITH (UPDLOCK, HOLDLOCK) WHERE Status = 1
                     AND ((RequesterOrganizationId = @LeadId AND RecipientOrganizationId = @RecipientOrganizationId)
                          OR (RecipientOrganizationId = @LeadId AND RequesterOrganizationId = @RecipientOrganizationId)))
                   OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_OrganizationConnectionRequests WHERE Status = 4
                     AND ((RequesterOrganizationId = @LeadId AND RecipientOrganizationId = @RecipientOrganizationId)
                          OR (RecipientOrganizationId = @LeadId AND RequesterOrganizationId = @RecipientOrganizationId)))
                    THROW 55501, N'Organization is not available for invitations.', 1;
            END
            ELSE
            BEGIN
                SELECT @ProfileId = profiles.Id FROM dbo.FundingPlatform_ProfessionalProfiles AS profiles WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.FundingPlatform_Users AS users ON users.Id = profiles.UserId AND users.Status = 2 AND users.EmailConfirmed = 1
                WHERE profiles.PublicId = @TargetPublicId AND profiles.UserId <> @UserId
                  AND profiles.IsDiscoverable = 1 AND profiles.AllowsInvitations = 1;
                IF @ProfileId IS NULL THROW 55501, N'Professional is not available for invitations.', 1;
            END;
            IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_ConsortiumParticipants WITH (UPDLOCK, HOLDLOCK)
                WHERE ConsortiumId = @ConsortiumId AND (OrganizationId = @RecipientOrganizationId OR ProfessionalProfileId = @ProfileId))
                THROW 55504, N'This participant has already been invited.', 1;
            INSERT INTO dbo.FundingPlatform_ConsortiumParticipants(ConsortiumId, Kind, OrganizationId, ProfessionalProfileId, Contribution, Message, InvitedByUserId)
            VALUES (@ConsortiumId, @Kind, @RecipientOrganizationId, @ProfileId, LTRIM(RTRIM(@Contribution)), LTRIM(RTRIM(@Message)), @UserId);
            DECLARE @ParticipantId BIGINT = SCOPE_IDENTITY();
            SELECT @EntityId = PublicId, @Version = RowVersion FROM dbo.FundingPlatform_ConsortiumParticipants WHERE Id = @ParticipantId;
            UPDATE dbo.FundingPlatform_Consortia SET UpdatedAtUtc = SYSUTCDATETIME() WHERE Id = @ConsortiumId;
            SET @Snapshot = (SELECT @ConsortiumPublicId AS consortiumId, @Kind AS kind, @TargetPublicId AS targetId,
                @Contribution AS contribution, @Message AS message, 0 AS status FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO dbo.FundingPlatform_CollaborationEvents(ActorUserId, EntityPublicId, ActionCode, IdempotencyKeyHash, RequestHash, ResultRowVersion, SnapshotJson)
            VALUES (@UserId, @EntityId, N'ConsortiumInvite', @KeyHash, @RequestHash, @Version, @Snapshot);
        END;
        IF @Initial = 0 COMMIT TRANSACTION;
        SELECT @EntityId AS EntityId, N'"' + CONVERT(NVARCHAR(16), @Version, 2) + N'"' AS ETag, @Replay AS WasReplay;
    END TRY
    BEGIN CATCH
        IF @Initial = 0 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_CInvite;
        THROW;
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Consortium_ParticipantAction
    @UserPublicId UNIQUEIDENTIFIER, @ConsortiumPublicId UNIQUEIDENTIFIER, @ParticipantPublicId UNIQUEIDENTIFIER, @Action TINYINT, @ExpectedRowVersion BINARY(8),
    @KeyHash BINARY(32), @RequestHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @Action IS NULL OR @Action NOT BETWEEN 1 AND 5 THROW 55505, N'Invalid participant action.', 1;
    DECLARE @Initial INT = @@TRANCOUNT;
    IF @Initial = 0 BEGIN TRANSACTION; ELSE SAVE TRANSACTION FP_CParticipantAction;
    BEGIN TRY
        DECLARE @UserId BIGINT, @EntityId UNIQUEIDENTIFIER, @Version BINARY(8), @Replay BIT = 0, @Snapshot NVARCHAR(MAX);
        EXEC dbo.FundingPlatform_usp_Collaboration_User @UserPublicId, @UserId OUTPUT;
        DECLARE @ConsortiumId BIGINT, @ParticipantId BIGINT, @LeadId BIGINT, @ProjectId BIGINT,
            @ConsortiumStatus TINYINT, @ParticipantStatus TINYINT, @CurrentVersion BINARY(8),
            @OrganizationId BIGINT, @ProfileId BIGINT, @Manager BIT = 0, @Recipient BIT = 0;
        SELECT @ConsortiumId = consortia.Id, @ParticipantId = participants.Id,
            @LeadId = consortia.LeadOrganizationId, @ProjectId = consortia.ProjectId,
            @ConsortiumStatus = consortia.Status, @ParticipantStatus = participants.Status,
            @CurrentVersion = participants.RowVersion, @OrganizationId = participants.OrganizationId, @ProfileId = participants.ProfessionalProfileId
        FROM dbo.FundingPlatform_Consortia AS consortia WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_ConsortiumParticipants AS participants WITH (UPDLOCK, HOLDLOCK) ON participants.ConsortiumId = consortia.Id
        WHERE consortia.PublicId = @ConsortiumPublicId AND participants.PublicId = @ParticipantPublicId;
        IF @ParticipantId IS NULL THROW 55501, N'Participation is not available.', 1;
        IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.FundingPlatform_Organizations AS organizations ON organizations.Id = memberships.OrganizationId AND organizations.IsActive = 1
            WHERE memberships.UserId = @UserId AND memberships.OrganizationId = @LeadId AND memberships.MembershipStatus = 1 AND memberships.Role = 1) SET @Manager = 1;
        IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProfessionalProfiles WHERE Id = @ProfileId AND UserId = @UserId)
           OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_OrganizationUsers AS memberships WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.FundingPlatform_Organizations AS organizations ON organizations.Id = memberships.OrganizationId AND organizations.IsActive = 1
                WHERE memberships.OrganizationId = @OrganizationId AND memberships.UserId = @UserId AND memberships.MembershipStatus = 1 AND memberships.Role = 1) SET @Recipient = 1;
        IF @Manager = 0 AND @Recipient = 0 THROW 55501, N'Participation is not available.', 1;
        EXEC dbo.FundingPlatform_usp_Collaboration_Replay @UserId, @KeyHash, @RequestHash, @EntityId OUTPUT, @Version OUTPUT;
        IF @EntityId IS NOT NULL SET @Replay = 1;
        ELSE
        BEGIN
            IF @ExpectedRowVersion IS NULL OR @CurrentVersion <> @ExpectedRowVersion THROW 55503, N'Participation version conflict.', 1;
            IF NOT ((@Action = 1 AND @Recipient = 1 AND @ParticipantStatus = 0 AND @ConsortiumStatus <> 2)
                OR (@Action = 2 AND @Recipient = 1 AND @ParticipantStatus = 0)
                OR (@Action = 3 AND @Manager = 1 AND @ParticipantStatus = 0)
                OR (@Action = 4 AND @Recipient = 1 AND @ParticipantStatus = 1)
                OR (@Action = 5 AND @Manager = 1 AND @ParticipantStatus = 1))
                THROW 55507, N'Participation transition is not permitted.', 1;
            IF @Action = 1
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMarketplaceReady() WHERE ProjectId = @ProjectId)
                    THROW 55507, N'Project is not publicly available for acceptance.', 1;
                IF @OrganizationId IS NOT NULL AND (NOT EXISTS
                    (SELECT 1 FROM dbo.FundingPlatform_OrganizationConnectionRequests WITH (UPDLOCK, HOLDLOCK) WHERE Status = 1
                     AND ((RequesterOrganizationId = @LeadId AND RecipientOrganizationId = @OrganizationId)
                          OR (RecipientOrganizationId = @LeadId AND RequesterOrganizationId = @OrganizationId)))
                    OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_OrganizationConnectionRequests WHERE Status = 4
                     AND ((RequesterOrganizationId = @LeadId AND RecipientOrganizationId = @OrganizationId)
                          OR (RecipientOrganizationId = @LeadId AND RequesterOrganizationId = @OrganizationId))))
                    THROW 55507, N'Organization connection is no longer available.', 1;
            END;
            UPDATE dbo.FundingPlatform_ConsortiumParticipants SET Status = @Action, UpdatedAtUtc = SYSUTCDATETIME() WHERE Id = @ParticipantId;
            SELECT @EntityId = PublicId, @Version = RowVersion FROM dbo.FundingPlatform_ConsortiumParticipants WHERE Id = @ParticipantId;
            UPDATE dbo.FundingPlatform_Consortia SET UpdatedAtUtc = SYSUTCDATETIME() WHERE Id = @ConsortiumId;
            SET @Snapshot = (SELECT @ConsortiumPublicId AS consortiumId, @ParticipantPublicId AS participantId,
                @ParticipantStatus AS previousStatus, @Action AS status FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO dbo.FundingPlatform_CollaborationEvents(ActorUserId, EntityPublicId, ActionCode, IdempotencyKeyHash, RequestHash, ResultRowVersion, SnapshotJson)
            VALUES (@UserId, @EntityId, N'ConsortiumParticipantAction', @KeyHash, @RequestHash, @Version, @Snapshot);
        END;
        IF @Initial = 0 COMMIT TRANSACTION;
        SELECT @EntityId AS EntityId, N'"' + CONVERT(NVARCHAR(16), @Version, 2) + N'"' AS ETag, @Replay AS WasReplay;
    END TRY
    BEGIN CATCH
        IF @Initial = 0 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_CParticipantAction;
        THROW;
    END CATCH;
END;
GO
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProfessionalProfile_GetOwn TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProfessionalProfile_Search TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_ProfessionalProfile_Save TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_Consortium_List TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_Consortium_Get TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_Consortium_Create TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_Consortium_Update TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_Consortium_Invite TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_Consortium_ParticipantAction TO FundingPlatform_ApiRuntimeRole;
