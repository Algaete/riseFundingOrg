/* 043 transactional collaboration smoke. Synthetic accounts and project only.
   Execute on disposable SQL before Azure dev; parsing is not SQL execution. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF OBJECT_ID(N'dbo.FundingPlatform_Consortia', N'U') IS NULL
    THROW 55550, N'Collaboration migration is missing.', 1;
DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke043;
BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID(), @UserPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @Email NVARCHAR(320) = N'collaboration-smoke-' +
        REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'') + N'@example.invalid';

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, Status, PreferredLocale)
    VALUES
        (@UserPublicId, @Email, UPPER(@Email), N'Collaboration smoke',
         N'not-a-credential', N'collaboration-smoke', 1, 2, N'es-CL');

    DECLARE @Organization TABLE
        (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProfileVersion INT, RowVersion BINARY(8));
    DECLARE @OrganizationSnapshot NVARCHAR(MAX) = N'{"name":"Collaboration smoke"}';
    DECLARE @OrganizationHash BINARY(32) =
        HASHBYTES('SHA2_256', @OrganizationSnapshot);
    INSERT INTO @Organization EXEC dbo.FundingPlatform_usp_Organization_CreateForUser
        @UserPublicId = @UserPublicId,
        @Name = N'Collaboration smoke',
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
    DECLARE @Slug NVARCHAR(180) = N'collaboration-smoke-' +
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


    /* Synthetic readiness only, never an alternative production publication path. */
    UPDATE dbo.FundingPlatform_Organizations SET ProfileStatus = 2, ProfileCompleteness = 100
    WHERE PublicId = @OrganizationPublicId;
    UPDATE dbo.FundingPlatform_Projects SET PublicationStatus = 2,
        PublishedAtUtc = SYSUTCDATETIME(), ReviewedAtUtc = SYSUTCDATETIME(),
        ReviewedByUserId = (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @UserPublicId)
    WHERE Id = @ProjectId;
    IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMarketplaceReady() WHERE ProjectId = @ProjectId)
        THROW 55551, N'Synthetic public project is not ready.', 1;

    DECLARE @ProfessionalUser UNIQUEIDENTIFIER = NEWID(), @SecondUser UNIQUEIDENTIFIER = NEWID(), @StrangerUser UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.FundingPlatform_Users(PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp, EmailConfirmed, Status, PreferredLocale)
    SELECT value, CONVERT(NVARCHAR(36), value) + N'@example.invalid', UPPER(CONVERT(NVARCHAR(36), value) + N'@example.invalid'),
        N'Collaboration synthetic', N'not-a-credential', N'collaboration-smoke', 1, 2, N'es-CL'
    FROM (VALUES (@ProfessionalUser), (@SecondUser), (@StrangerUser)) AS fixtures(value);
    DECLARE @Write TABLE(EntityId UNIQUEIDENTIFIER, ETag NVARCHAR(18), WasReplay BIT);
    DECLARE @Document TABLE(Json NVARCHAR(MAX));
    DECLARE @Key BINARY(32), @Hash BINARY(32), @Expected BINARY(8), @Json NVARCHAR(MAX);
    DECLARE @ProfileData NVARCHAR(MAX) = N'{"displayName":"Profesional de prueba","headline":"Ingeniería territorial","biography":null,"countryId":152,"skills":["GIS"],"languageIds":[],"categoryIds":[1],"isDiscoverable":false,"allowsInvitations":false}';
    SET @ProfileData = JSON_MODIFY(@ProfileData, '$.displayName', CONVERT(NVARCHAR(36), @Fixture));
    SET @Key = HASHBYTES('SHA2_256', N'profile-first'); SET @Hash = @Key;
    INSERT INTO @Write EXEC dbo.FundingPlatform_usp_ProfessionalProfile_Save @ProfessionalUser, @ProfileData, NULL, @Key, @Hash;
    DECLARE @ProfileId UNIQUEIDENTIFIER = (SELECT EntityId FROM @Write);
    SET @Expected = CONVERT(BINARY(8), REPLACE((SELECT ETag FROM @Write), N'"', N''), 2);
    DELETE FROM @Write;
    INSERT INTO @Document EXEC dbo.FundingPlatform_usp_ProfessionalProfile_Search @UserPublicId, @Query = NULL;
    IF EXISTS(SELECT 1 FROM @Document CROSS APPLY OPENJSON(Json, '$.items') WHERE JSON_VALUE(value, '$.profileId') = CONVERT(NVARCHAR(36), @ProfileId))
        THROW 55552, N'Private professional leaked into directory.', 1;
    DELETE FROM @Document;
    SET @ProfileData = JSON_MODIFY(JSON_MODIFY(@ProfileData, '$.isDiscoverable', CAST(1 AS BIT)), '$.allowsInvitations', CAST(1 AS BIT));
    SET @Key = HASHBYTES('SHA2_256', N'profile-opt-in'); SET @Hash = @Key;
    INSERT INTO @Write EXEC dbo.FundingPlatform_usp_ProfessionalProfile_Save @ProfessionalUser, @ProfileData, @Expected, @Key, @Hash;
    DELETE FROM @Write;
    INSERT INTO @Write EXEC dbo.FundingPlatform_usp_ProfessionalProfile_Save @ProfessionalUser, @ProfileData, @Expected, @Key, @Hash;
    IF NOT EXISTS(SELECT 1 FROM @Write WHERE EntityId = @ProfileId AND WasReplay = 1)
        THROW 55553, N'Profile command replay changed identity or failed.', 1;
    DELETE FROM @Write;
    DECLARE @Query NVARCHAR(200) = CONVERT(NVARCHAR(36), @Fixture);
    INSERT INTO @Document EXEC dbo.FundingPlatform_usp_ProfessionalProfile_Search @UserPublicId, @Query = @Query;
    IF (SELECT JSON_VALUE(Json, '$.totalCount') FROM @Document) <> N'1'
       OR EXISTS(SELECT 1 FROM @Document WHERE Json LIKE N'%@example.invalid%' OR Json LIKE N'%userId%')
        THROW 55554, N'Opt-in directory or private account projection failed.', 1;
    DELETE FROM @Document;
    SET @ProfileData = JSON_MODIFY(@ProfileData, '$.displayName', N'Segundo profesional privado en invitación');
    SET @Key = HASHBYTES('SHA2_256', N'profile-second'); SET @Hash = @Key;
    INSERT INTO @Write EXEC dbo.FundingPlatform_usp_ProfessionalProfile_Save @SecondUser, @ProfileData, NULL, @Key, @Hash;
    DECLARE @SecondProfileId UNIQUEIDENTIFIER = (SELECT EntityId FROM @Write);
    DELETE FROM @Write;

    SET @Key = HASHBYTES('SHA2_256', N'consortium-create'); SET @Hash = @Key;
    INSERT INTO @Write EXEC dbo.FundingPlatform_usp_Consortium_Create @UserPublicId, @ProjectPublicId, N'Consorcio sintético', NULL, @Key, @Hash;
    DECLARE @ConsortiumId UNIQUEIDENTIFIER = (SELECT EntityId FROM @Write);
    SET @Expected = CONVERT(BINARY(8), REPLACE((SELECT ETag FROM @Write), N'"', N''), 2);
    DELETE FROM @Write;
    INSERT INTO @Write EXEC dbo.FundingPlatform_usp_Consortium_Create @UserPublicId, @ProjectPublicId, N'Consorcio sintético', NULL, @Key, @Hash;
    IF NOT EXISTS(SELECT 1 FROM @Write WHERE EntityId = @ConsortiumId AND WasReplay = 1)
        THROW 55555, N'Consortium creation replay failed.', 1;
    DELETE FROM @Write;
    SET @Key = HASHBYTES('SHA2_256', N'invite-first'); SET @Hash = @Key;
    INSERT INTO @Write EXEC dbo.FundingPlatform_usp_Consortium_Invite @UserPublicId, @ConsortiumId, 2, @ProfileId,
        N'Análisis de datos', N'Queremos colaborar en el proyecto.', @Expected, @Key, @Hash;
    DECLARE @ParticipantId UNIQUEIDENTIFIER = (SELECT EntityId FROM @Write);
    DECLARE @ParticipantVersion BINARY(8) = CONVERT(BINARY(8), REPLACE((SELECT ETag FROM @Write), N'"', N''), 2);
    DELETE FROM @Write;
    SELECT @Expected = RowVersion FROM dbo.FundingPlatform_Consortia WHERE PublicId = @ConsortiumId;
    SET @Key = HASHBYTES('SHA2_256', N'invite-second'); SET @Hash = @Key;
    INSERT INTO @Write EXEC dbo.FundingPlatform_usp_Consortium_Invite @UserPublicId, @ConsortiumId, 2, @SecondProfileId,
        N'Investigación', N'Invitación privada para segundo participante.', @Expected, @Key, @Hash;
    DELETE FROM @Write;

    INSERT INTO @Document EXEC dbo.FundingPlatform_usp_Consortium_Get @ProfessionalUser, @ConsortiumId;
    SELECT @Json = Json FROM @Document;
    IF COALESCE(JSON_VALUE(@Json, '$.consortium.CanViewRoster'), N'') <> N'false'
       OR (SELECT COUNT(1) FROM OPENJSON(@Json, '$.participants')) <> 1
       OR @Json LIKE N'%Segundo profesional%' OR @Json LIKE N'%Invitación privada para segundo%'
        THROW 55556, N'Pending invitation leaked roster or another private message.', 1;
    DELETE FROM @Document;
    INSERT INTO @Document EXEC dbo.FundingPlatform_usp_Consortium_List @StrangerUser;
    IF COALESCE((SELECT JSON_VALUE(Json, '$.totalCount') FROM @Document), N'') <> N'0'
        THROW 55557, N'Unrelated user can list a private consortium.', 1;
    DELETE FROM @Document;

    SET @Key = HASHBYTES('SHA2_256', N'accept-first'); SET @Hash = @Key;
    INSERT INTO @Write EXEC dbo.FundingPlatform_usp_Consortium_ParticipantAction @ProfessionalUser, @ConsortiumId, @ParticipantId, 1, @ParticipantVersion, @Key, @Hash;
    SET @ParticipantVersion = CONVERT(BINARY(8), REPLACE((SELECT ETag FROM @Write), N'"', N''), 2);
    DELETE FROM @Write;
    INSERT INTO @Document EXEC dbo.FundingPlatform_usp_Consortium_Get @ProfessionalUser, @ConsortiumId;
    SELECT @Json = Json FROM @Document;
    IF COALESCE(JSON_VALUE(@Json, '$.consortium.CanViewRoster'), N'') <> N'true'
       OR JSON_VALUE(@Json, '$.consortium.AcceptedCount') <> N'1'
       OR @Json LIKE N'%Invitación privada para segundo%'
        THROW 55558, N'Accepted participant roster privacy failed.', 1;
    DELETE FROM @Document;
    SELECT @Expected = RowVersion FROM dbo.FundingPlatform_Consortia WHERE PublicId = @ConsortiumId;
    SET @Key = HASHBYTES('SHA2_256', N'activate'); SET @Hash = @Key;
    INSERT INTO @Write EXEC dbo.FundingPlatform_usp_Consortium_Update @UserPublicId, @ConsortiumId, N'Consorcio sintético', NULL, 1, @Expected, @Key, @Hash;
    DELETE FROM @Write;

    /* An existing accepted organization connection is a prerequisite, not consent
       to join. Both invitation and consortium acceptance remain separate commands. */
    DECLARE @RecipientOrg TABLE(Id BIGINT, PublicId UNIQUEIDENTIFIER, ProfileVersion INT, RowVersion BINARY(8));
    DECLARE @RecipientSnapshot NVARCHAR(MAX) = N'{"name":"Organización aliada sintética"}';
    DECLARE @RecipientHash BINARY(32) = HASHBYTES('SHA2_256', @RecipientSnapshot);
    INSERT INTO @RecipientOrg EXEC dbo.FundingPlatform_usp_Organization_CreateForUser
        @UserPublicId = @StrangerUser, @Name = N'Organización aliada sintética', @HomeCountryId = 152,
        @OrganizationTypeId = 2, @SnapshotJson = @RecipientSnapshot, @ContentHash = @RecipientHash;
    DECLARE @RecipientOrgId BIGINT = (SELECT Id FROM @RecipientOrg);
    DECLARE @RecipientOrgPublicId UNIQUEIDENTIFIER = (SELECT PublicId FROM @RecipientOrg);
    DECLARE @RecipientUserId BIGINT = (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @StrangerUser);
    DECLARE @OwnerUserId BIGINT = (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @UserPublicId);
    DECLARE @LeadOrgId BIGINT = (SELECT Id FROM @Organization);
    DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();
    UPDATE dbo.FundingPlatform_Organizations SET ProfileStatus = 2, ProfileCompleteness = 100 WHERE Id = @RecipientOrgId;
    INSERT INTO dbo.FundingPlatform_OrganizationNetworkingPreferences(OrganizationId, IsDiscoverable, AllowRequests, UpdatedByUserId, CreatedAtUtc, UpdatedAtUtc)
        VALUES (@RecipientOrgId, 1, 1, @RecipientUserId, @Now, @Now);
    INSERT INTO dbo.FundingPlatform_OrganizationConnectionRequests
        (RequesterOrganizationId, RecipientOrganizationId, RequestedByUserId, RequesterOrganizationNameSnapshot,
         RecipientOrganizationNameSnapshot, PurposeCode, Message, Status, ActionedByUserId, ActionedAtUtc, CreatedAtUtc, UpdatedAtUtc)
        VALUES (@LeadOrgId, @RecipientOrgId, @OwnerUserId, N'Coordinador sintético', N'Aliado sintético',
            3, N'Conexión sintética ya aceptada.', 1, @RecipientUserId, @Now, @Now, @Now);
    DECLARE @ConnectionId BIGINT = SCOPE_IDENTITY();
    SELECT @Expected = RowVersion FROM dbo.FundingPlatform_Consortia WHERE PublicId = @ConsortiumId;
    SET @Key = HASHBYTES('SHA2_256', N'invite-organization'); SET @Hash = @Key;
    INSERT INTO @Write EXEC dbo.FundingPlatform_usp_Consortium_Invite @UserPublicId, @ConsortiumId, 1,
        @RecipientOrgPublicId, N'Capacidad territorial', N'Colaboremos con capacidades territoriales.', @Expected, @Key, @Hash;
    DECLARE @OrgParticipant UNIQUEIDENTIFIER = (SELECT EntityId FROM @Write);
    DECLARE @OrgParticipantVersion BINARY(8) = CONVERT(BINARY(8), REPLACE((SELECT ETag FROM @Write), N'"', N''), 2);
    DELETE FROM @Write;
    IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_ConsortiumAccess(@RecipientUserId) WHERE CanViewRoster = 1)
        THROW 55563, N'Existing organization connection bypassed explicit consortium acceptance.', 1;
    SET @Key = HASHBYTES('SHA2_256', N'accept-organization'); SET @Hash = @Key;
    INSERT INTO @Write EXEC dbo.FundingPlatform_usp_Consortium_ParticipantAction @StrangerUser, @ConsortiumId, @OrgParticipant, 1, @OrgParticipantVersion, @Key, @Hash;
    DELETE FROM @Write;
    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_ConsortiumAccess(@RecipientUserId) WHERE CanViewRoster = 1)
        THROW 55564, N'Accepted organization cannot read shared roster.', 1;
    INSERT INTO @Document EXEC dbo.FundingPlatform_usp_Consortium_Get @StrangerUser, @ConsortiumId;
    SELECT @Json = Json FROM @Document;
    IF @Json LIKE N'%Queremos colaborar en el proyecto%' OR @Json LIKE N'%Invitación privada para segundo%'
        THROW 55565, N'Accepted organization received another participant private message.', 1;
    DELETE FROM @Document;
    UPDATE dbo.FundingPlatform_OrganizationConnectionRequests SET Status = 4 WHERE Id = @ConnectionId;
    IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_ConsortiumAccess(@RecipientUserId) WHERE CanViewRoster = 1)
        THROW 55566, N'Blocked organization connection retained shared roster access.', 1;


    SET @Key = HASHBYTES('SHA2_256', N'leave-first'); SET @Hash = @Key;
    INSERT INTO @Write EXEC dbo.FundingPlatform_usp_Consortium_ParticipantAction @ProfessionalUser, @ConsortiumId, @ParticipantId, 4, @ParticipantVersion, @Key, @Hash;
    DELETE FROM @Write;
    INSERT INTO @Write EXEC dbo.FundingPlatform_usp_Consortium_ParticipantAction @ProfessionalUser, @ConsortiumId, @ParticipantId, 4, @ParticipantVersion, @Key, @Hash;
    IF NOT EXISTS(SELECT 1 FROM @Write WHERE WasReplay = 1)
        THROW 55559, N'Own leave replay must work after live access is removed.', 1;
    DELETE FROM @Write;
    DECLARE @ProfessionalInternalId BIGINT = (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @ProfessionalUser);
    IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_ConsortiumAccess(@ProfessionalInternalId))
        THROW 55560, N'Leaving retained consortium access.', 1;
    SELECT @Expected = RowVersion FROM dbo.FundingPlatform_Consortia WHERE PublicId = @ConsortiumId;
    SET @Key = HASHBYTES('SHA2_256', N'close'); SET @Hash = @Key;
    INSERT INTO @Write EXEC dbo.FundingPlatform_usp_Consortium_Update @UserPublicId, @ConsortiumId, N'Consorcio sintético', NULL, 2, @Expected, @Key, @Hash;
    IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_ConsortiumParticipants AS participants
        INNER JOIN dbo.FundingPlatform_Consortia AS consortia ON consortia.Id = participants.ConsortiumId
        WHERE consortia.PublicId = @ConsortiumId AND participants.Status = 0)
        THROW 55561, N'Closing left pending invitations active.', 1;
    IF (SELECT COUNT(1) FROM dbo.FundingPlatform_CollaborationEvents
        WHERE ActorUserId IN (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId IN (@UserPublicId, @ProfessionalUser, @SecondUser, @StrangerUser))) <> 12
        THROW 55562, N'Audit count differs from successful unique commands.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke043;
    PRINT N'043 collaboration synthetic smoke passed; fixtures rolled back.';
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke043;
    THROW;
END CATCH;
