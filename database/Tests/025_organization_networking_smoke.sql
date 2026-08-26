/* Transactional FASE 10B smoke: opt-in directory and moderated organization connections. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_OrganizationNetworkingPreferences', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_OrganizationConnectionRequests', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_OrganizationConnectionCreateRequests', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_OrganizationNetworkingPreference_Get', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_OrganizationNetworkingPreference_Put', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_OrganizationNetworkDirectory_Search', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_OrganizationConnection_Get', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_OrganizationConnection_List', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_OrganizationConnection_Create', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_OrganizationConnection_Action', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_tr_OrganizationConnectionRequests_Lifecycle', N'TR') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_tr_OrganizationConnectionCreateRequests_Immutable', N'TR') IS NULL
    THROW 54201, N'FASE 10B objects are incomplete.', 1;

DECLARE @CreateDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_OrganizationConnection_Create'));
DECLARE @DirectoryDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_OrganizationNetworkDirectory_Search'));
DECLARE @ActionDefinition NVARCHAR(MAX) =
    OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_OrganizationConnection_Action'));
IF @CreateDefinition NOT LIKE N'%@Role <> 1%'
   OR @CreateDefinition NOT LIKE N'%IdempotencyKeyHash%'
   OR @CreateDefinition NOT LIKE N'%Status = 4%'
   OR @CreateDefinition NOT LIKE N'%DATEADD(HOUR, -24, @NowUtc)%'
   OR CHARINDEX(N'[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]', @CreateDefinition) = 0
   OR @DirectoryDefinition NOT LIKE N'%FundingPlatform_ifn_OrganizationMarketplaceReady%'
   OR @DirectoryDefinition NOT LIKE N'%FundingPlatform_ifn_ProjectMarketplaceReady%'
   OR @DirectoryDefinition NOT LIKE N'%preferences.IsDiscoverable = 1%'
   OR @DirectoryDefinition LIKE N'%Email%'
   OR @ActionDefinition NOT LIKE N'%@RowVersion <> @ExpectedRowVersion%'
    THROW 54202, N'FASE 10B privacy, opt-in, quota, idempotency or ETag guards drifted.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID(N'dbo.FundingPlatform_OrganizationConnectionRequests')
                 AND name = N'FundingPlatform_UX_OrganizationConnectionRequests_ActivePair')
   OR NOT EXISTS (SELECT 1 FROM sys.foreign_keys
                  WHERE parent_object_id = OBJECT_ID(N'dbo.FundingPlatform_OrganizationConnectionCreateRequests')
                    AND name = N'FundingPlatform_FK_OrganizationConnectionCreateRequests_Request')
    THROW 54203, N'FASE 10B pair uniqueness or durable ledger integrity is missing.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke025;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @Suffix NVARCHAR(32) = REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'');
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @CategoryId INT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_FundingCategories WHERE IsActive = 1 ORDER BY Id);
    DECLARE @BeneficiaryTypeId INT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_BeneficiaryTypes WHERE IsActive = 1 ORDER BY Id);
    DECLARE @ProjectTypeId INT =
        (SELECT TOP (1) Id FROM dbo.FundingPlatform_ProjectTypes WHERE IsActive = 1 ORDER BY Id);
    IF @CategoryId IS NULL OR @BeneficiaryTypeId IS NULL OR @ProjectTypeId IS NULL
        THROW 54204, N'Required active catalogs are missing.', 1;

    DECLARE @AdminAPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @MemberAPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @AdminBPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @OrgAPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @OrgBPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @EmailA NVARCHAR(320) = N'fase10b-a-' + @Suffix + N'@example.invalid';
    DECLARE @EmailMember NVARCHAR(320) = N'fase10b-member-' + @Suffix + N'@example.invalid';
    DECLARE @EmailB NVARCHAR(320) = N'fase10b-b-' + @Suffix + N'@example.invalid';
    INSERT dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES
        (@AdminAPublicId, @EmailA, UPPER(@EmailA), N'10B admin A', N'not-a-credential',
         N'10b-a', 1, 0, 2, N'es-CL'),
        (@MemberAPublicId, @EmailMember, UPPER(@EmailMember), N'10B member A',
         N'not-a-credential', N'10b-member', 1, 0, 2, N'es-CL'),
        (@AdminBPublicId, @EmailB, UPPER(@EmailB), N'10B admin B', N'not-a-credential',
         N'10b-b', 1, 0, 2, N'es-CL');
    DECLARE @AdminAId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @AdminAPublicId);
    DECLARE @MemberAId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @MemberAPublicId);
    DECLARE @AdminBId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @AdminBPublicId);

    INSERT dbo.FundingPlatform_Organizations
        (PublicId, CreatedByUserId, Name, HomeCountryId, OrganizationTypeId,
         WebsiteUrl, Description, EstablishedYear, ProfileStatus, ProfileCompleteness)
    VALUES
        (@OrgAPublicId, @AdminAId, N'10B Bosques ' + @Suffix, 152, 1,
         N'https://bosques.example.invalid', N'Conservación ambiental segura', 2018, 2, 100),
        (@OrgBPublicId, @AdminBId, N'10B Agua ' + @Suffix, 152, 1,
         N'https://agua.example.invalid', N'Acceso comunitario al agua', 2019, 2, 100);
    DECLARE @OrgAId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Organizations WHERE PublicId = @OrgAPublicId);
    DECLARE @OrgBId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Organizations WHERE PublicId = @OrgBPublicId);
    INSERT dbo.FundingPlatform_OrganizationUsers
        (OrganizationId, UserId, Role, MembershipStatus, JoinedAtUtc)
    VALUES (@OrgAId, @AdminAId, 1, 1, @NowUtc),
           (@OrgAId, @MemberAId, 2, 1, @NowUtc),
           (@OrgBId, @AdminBId, 1, 1, @NowUtc);

    DECLARE @ProjectAPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @ProjectBPublicId UNIQUEIDENTIFIER = NEWID();
    INSERT dbo.FundingPlatform_Projects
        (PublicId, OrganizationId, CreatedByUserId, Slug, Title, Summary, Description,
         ProjectStatus, PublicationStatus, StartDate, EndDate, BudgetTotal,
         ConfirmedFunding, Currency, ProjectVersion, IsActive, CreatedAtUtc, UpdatedAtUtc,
         SubmittedAtUtc, PublishedAtUtc, ReviewedAtUtc, ReviewedByUserId, RejectionReason)
    VALUES
        (@ProjectAPublicId, @OrgAId, @AdminAId, N'10b-bosques-' + @Suffix,
         N'Restauración de bosques', N'Restauración comunitaria', N'Descripción pública',
         1, 2, CONVERT(DATE, @NowUtc), DATEADD(DAY, 90, CONVERT(DATE, @NowUtc)),
         1000, 100, 'USD', 1, 1, @NowUtc, @NowUtc, DATEADD(DAY, -2, @NowUtc),
         DATEADD(DAY, -1, @NowUtc), DATEADD(DAY, -1, @NowUtc), @AdminAId, NULL),
        (@ProjectBPublicId, @OrgBId, @AdminBId, N'10b-agua-' + @Suffix,
         N'Agua comunitaria', N'Agua segura rural', N'Descripción pública',
         1, 2, CONVERT(DATE, @NowUtc), DATEADD(DAY, 120, CONVERT(DATE, @NowUtc)),
         1500, 300, 'USD', 1, 1, @NowUtc, @NowUtc, DATEADD(DAY, -2, @NowUtc),
         DATEADD(DAY, -1, @NowUtc), DATEADD(DAY, -1, @NowUtc), @AdminBId, NULL);
    DECLARE @ProjectAId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Projects WHERE PublicId = @ProjectAPublicId);
    DECLARE @ProjectBId BIGINT =
        (SELECT Id FROM dbo.FundingPlatform_Projects WHERE PublicId = @ProjectBPublicId);
    INSERT dbo.FundingPlatform_ProjectCountries (ProjectId, CountryId)
        VALUES (@ProjectAId, 152), (@ProjectBId, 152);
    INSERT dbo.FundingPlatform_ProjectCategories (ProjectId, FundingCategoryId)
        VALUES (@ProjectAId, @CategoryId), (@ProjectBId, @CategoryId);
    INSERT dbo.FundingPlatform_ProjectBeneficiaryTypes (ProjectId, BeneficiaryTypeId)
        VALUES (@ProjectAId, @BeneficiaryTypeId), (@ProjectBId, @BeneficiaryTypeId);
    INSERT dbo.FundingPlatform_ProjectProjectTypes (ProjectId, ProjectTypeId)
        VALUES (@ProjectAId, @ProjectTypeId), (@ProjectBId, @ProjectTypeId);
    INSERT dbo.FundingPlatform_OrganizationCategories (OrganizationId, FundingCategoryId)
        VALUES (@OrgAId, @CategoryId), (@OrgBId, @CategoryId);
    INSERT dbo.FundingPlatform_OrganizationProjectTypes (OrganizationId, ProjectTypeId)
        VALUES (@OrgAId, @ProjectTypeId), (@OrgBId, @ProjectTypeId);
    IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMarketplaceReady()
                   WHERE ProjectId = @ProjectAId)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_ifn_ProjectMarketplaceReady()
                      WHERE ProjectId = @ProjectBId)
        THROW 54205, N'Public marketplace project fixtures are not ready.', 1;

    DECLARE @Codes TABLE (Code NVARCHAR(50));
    INSERT @Codes EXEC dbo.FundingPlatform_usp_OrganizationNetworkingPreference_Put
        @UserPublicId = @AdminAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @IsDiscoverable = 1, @AllowRequests = 1, @ExpectedRowVersion = NULL, @NowUtc = @NowUtc;
    INSERT @Codes EXEC dbo.FundingPlatform_usp_OrganizationNetworkingPreference_Put
        @UserPublicId = @AdminBPublicId, @OrganizationPublicId = @OrgBPublicId,
        @IsDiscoverable = 1, @AllowRequests = 1, @ExpectedRowVersion = NULL, @NowUtc = @NowUtc;
    IF (SELECT COUNT(*) FROM @Codes WHERE Code = N'created') <> 2
        THROW 54206, N'Opt-in preferences were not created.', 1;

    DECLARE @CountryIds dbo.FundingPlatform_SmallIntIdList;
    DECLARE @CategoryIds dbo.FundingPlatform_IntIdList;
    DECLARE @ProjectTypeIds dbo.FundingPlatform_IntIdList;
    EXEC dbo.FundingPlatform_usp_OrganizationNetworkDirectory_Search
        @UserPublicId = @MemberAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @Query = N'Agua', @CountryIds = @CountryIds, @CategoryIds = @CategoryIds,
        @ProjectTypeIds = @ProjectTypeIds, @PageNumber = 1, @PageSize = 20;

    DECLARE @Mutations TABLE (Code NVARCHAR(50), ConnectionPublicId UNIQUEIDENTIFIER NULL);
    DECLARE @Key BINARY(32) = HASHBYTES('SHA2_256', N'10b-key-' + @Suffix);
    DECLARE @Request BINARY(32) = HASHBYTES('SHA2_256', N'10b-request-' + @Suffix);
    DECLARE @ConflictingRequest BINARY(32) =
        HASHBYTES('SHA2_256', N'10b-conflict-' + @Suffix);
    DECLARE @AcceptedAtUtc DATETIME2(3) = DATEADD(SECOND, 1, @NowUtc);
    DECLARE @BlockedAtUtc DATETIME2(3) = DATEADD(SECOND, 2, @NowUtc);
    INSERT @Mutations EXEC dbo.FundingPlatform_usp_OrganizationConnection_Create
        @UserPublicId = @AdminAPublicId,
        @RequesterOrganizationPublicId = @OrgAPublicId,
        @RecipientOrganizationPublicId = @OrgBPublicId,
        @RequesterProjectPublicId = @ProjectAPublicId,
        @PurposeCode = 0, @Message = N'Buscamos una alianza técnica para este proyecto.',
        @IdempotencyKeyHash = @Key, @RequestHash = @Request, @NowUtc = @NowUtc;
    DECLARE @ConnectionPublicId UNIQUEIDENTIFIER =
        (SELECT ConnectionPublicId FROM @Mutations WHERE Code = N'created');
    IF @ConnectionPublicId IS NULL THROW 54207, N'Connection was not created.', 1;
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_OrganizationConnectionRequests
               WHERE PublicId = @ConnectionPublicId
                 AND (Message LIKE N'%@%' OR Message LIKE N'%http%'))
        THROW 54208, N'Connection persisted disallowed contact data.', 1;

    DELETE @Mutations;
    INSERT @Mutations EXEC dbo.FundingPlatform_usp_OrganizationConnection_Create
        @UserPublicId = @AdminAPublicId,
        @RequesterOrganizationPublicId = @OrgAPublicId,
        @RecipientOrganizationPublicId = @OrgBPublicId,
        @RequesterProjectPublicId = @ProjectAPublicId,
        @PurposeCode = 0, @Message = N'Buscamos una alianza técnica para este proyecto.',
        @IdempotencyKeyHash = @Key, @RequestHash = @Request, @NowUtc = @NowUtc;
    IF NOT EXISTS (SELECT 1 FROM @Mutations
                   WHERE Code = N'replayed' AND ConnectionPublicId = @ConnectionPublicId)
       OR (SELECT COUNT(*) FROM dbo.FundingPlatform_OrganizationConnectionRequests
           WHERE PublicId = @ConnectionPublicId) <> 1
        THROW 54209, N'Durable idempotent replay duplicated or changed the request.', 1;

    DELETE @Mutations;
    INSERT @Mutations EXEC dbo.FundingPlatform_usp_OrganizationConnection_Create
        @UserPublicId = @AdminAPublicId,
        @RequesterOrganizationPublicId = @OrgAPublicId,
        @RecipientOrganizationPublicId = @OrgBPublicId,
        @RequesterProjectPublicId = @ProjectAPublicId,
        @PurposeCode = 1, @Message = N'Mensaje distinto para conflicto durable.',
        @IdempotencyKeyHash = @Key,
        @RequestHash = @ConflictingRequest, @NowUtc = @NowUtc;
    IF NOT EXISTS (SELECT 1 FROM @Mutations WHERE Code = N'idempotency-conflict')
        THROW 54210, N'Idempotency payload conflict was accepted.', 1;

    DECLARE @RowVersion BINARY(8) =
        (SELECT RowVersion FROM dbo.FundingPlatform_OrganizationConnectionRequests
         WHERE PublicId = @ConnectionPublicId);
    DELETE @Codes;
    INSERT @Codes EXEC dbo.FundingPlatform_usp_OrganizationConnection_Action
        @UserPublicId = @AdminBPublicId, @OrganizationPublicId = @OrgBPublicId,
        @ConnectionPublicId = @ConnectionPublicId, @ActionCode = 1,
        @ExpectedRowVersion = @RowVersion, @NowUtc = @AcceptedAtUtc;
    IF NOT EXISTS (SELECT 1 FROM @Codes WHERE Code = N'accepted')
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_OrganizationConnectionRequests
                      WHERE PublicId = @ConnectionPublicId AND Status = 1)
        THROW 54211, N'Recipient could not accept the pending request.', 1;

    EXEC dbo.FundingPlatform_usp_OrganizationConnection_Get
        @UserPublicId = @MemberAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @ConnectionPublicId = @ConnectionPublicId;
    EXEC dbo.FundingPlatform_usp_OrganizationConnection_List
        @UserPublicId = @MemberAPublicId, @OrganizationPublicId = @OrgAPublicId,
        @Direction = 0, @Status = 1, @PageNumber = 1, @PageSize = 20;

    SET @RowVersion =
        (SELECT RowVersion FROM dbo.FundingPlatform_OrganizationConnectionRequests
         WHERE PublicId = @ConnectionPublicId);
    DELETE @Codes;
    INSERT @Codes EXEC dbo.FundingPlatform_usp_OrganizationConnection_Action
        @UserPublicId = @AdminBPublicId, @OrganizationPublicId = @OrgBPublicId,
        @ConnectionPublicId = @ConnectionPublicId, @ActionCode = 4,
        @ExpectedRowVersion = @RowVersion, @NowUtc = @BlockedAtUtc;
    IF NOT EXISTS (SELECT 1 FROM @Codes WHERE Code = N'blocked')
       OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_OrganizationConnectionRequests
                  WHERE PublicId = @ConnectionPublicId AND Status <> 4)
        THROW 54212, N'Block did not close the accepted relationship.', 1;
    IF EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_OrganizationNetworkingPreferences AS preferences
        WHERE preferences.OrganizationId = @OrgBId AND preferences.IsDiscoverable = 1
          AND NOT EXISTS
              (SELECT 1 FROM dbo.FundingPlatform_OrganizationConnectionRequests AS blocked
               WHERE blocked.Status = 4 AND blocked.PairLowOrganizationId =
                     CASE WHEN @OrgAId < @OrgBId THEN @OrgAId ELSE @OrgBId END
                 AND blocked.PairHighOrganizationId =
                     CASE WHEN @OrgAId < @OrgBId THEN @OrgBId ELSE @OrgAId END))
        THROW 54213, N'Blocked-pair guard was not persisted.', 1;

    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_OrganizationConnectionRequests
               WHERE PublicId = @ConnectionPublicId
                 AND (RequesterOrganizationNameSnapshot LIKE N'%@%'
                      OR RecipientOrganizationNameSnapshot LIKE N'%@%'))
        THROW 54214, N'Private member contact data leaked into connection snapshots.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke025;
    PRINT N'FASE 10B organization networking smoke passed and rolled back.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
    BEGIN
        IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
        ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke025;
        ELSE ROLLBACK TRANSACTION;
    END;
    THROW;
END CATCH;
GO
