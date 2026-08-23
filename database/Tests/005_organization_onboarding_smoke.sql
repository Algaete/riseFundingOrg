SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @RequiredProcedures TABLE (Name SYSNAME NOT NULL PRIMARY KEY);
INSERT INTO @RequiredProcedures (Name) VALUES
    (N'FundingPlatform_usp_Catalogs_GetForOrganizationProfile'),
    (N'FundingPlatform_usp_Organization_ListForUser'),
    (N'FundingPlatform_usp_Organization_CreateForUser'),
    (N'FundingPlatform_usp_Organization_GetProfileByPublicId'),
    (N'FundingPlatform_usp_Organization_UpdateProfileByPublicId');

IF EXISTS
(
    SELECT 1
    FROM @RequiredProcedures AS required
    LEFT JOIN sys.procedures AS actual
        ON actual.name COLLATE DATABASE_DEFAULT = required.Name COLLATE DATABASE_DEFAULT
       AND actual.schema_id = SCHEMA_ID(N'dbo')
    WHERE actual.object_id IS NULL
)
    THROW 52501, N'One or more FASE 4 procedures are missing.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0
    BEGIN TRANSACTION;
ELSE
    SAVE TRANSACTION FundingPlatform_Smoke005;

BEGIN TRY
    DECLARE @Fixture UNIQUEIDENTIFIER = NEWID();
    DECLARE @PublicUserId UNIQUEIDENTIFIER = NEWID();
    DECLARE @Email NVARCHAR(320) = N'org-' + REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'') + N'@example.invalid';
    DECLARE @Snapshot NVARCHAR(MAX) = N'{"name":"Organization SQL smoke"}';
    DECLARE @Hash BINARY(32) = HASHBYTES('SHA2_256', @Snapshot);

    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, Status, PreferredLocale)
    VALUES
        (@PublicUserId, @Email, UPPER(@Email), N'Organization SQL smoke',
         N'smoke-password-hash-not-a-credential', N'smoke-security-stamp', 1, 2, N'es-CL');

    DECLARE @Created TABLE
    (
        Id BIGINT NOT NULL,
        PublicId UNIQUEIDENTIFIER NOT NULL,
        ProfileVersion INT NOT NULL,
        RowVersion BINARY(8) NOT NULL
    );
    INSERT INTO @Created (Id, PublicId, ProfileVersion, RowVersion)
    EXEC dbo.FundingPlatform_usp_Organization_CreateForUser
        @UserPublicId = @PublicUserId,
        @Name = N'Organization SQL smoke',
        @HomeCountryId = 152,
        @OrganizationTypeId = 2,
        @SnapshotJson = @Snapshot,
        @ContentHash = @Hash;

    DECLARE @OrganizationId BIGINT = (SELECT Id FROM @Created);
    DECLARE @OrganizationPublicId UNIQUEIDENTIFIER = (SELECT PublicId FROM @Created);
    DECLARE @InitialRowVersion BINARY(8) = (SELECT RowVersion FROM @Created);

    IF @OrganizationId IS NULL
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OrganizationUsers
           WHERE OrganizationId = @OrganizationId AND Role = 1 AND MembershipStatus = 1)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OrganizationProfileVersions
           WHERE OrganizationId = @OrganizationId AND ProfileVersion = 1 AND ContentHash = @Hash)
       OR NOT EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_OutboxMessages
           WHERE AggregateType = N'Organization'
             AND AggregateId = CONVERT(NVARCHAR(100), @OrganizationId)
             AND MessageType = N'OrganizationCreated')
        THROW 52502, N'Organization creation did not persist the aggregate atomically.', 1;

    DECLARE @Listed TABLE
    (
        PublicId UNIQUEIDENTIFIER NOT NULL,
        Name NVARCHAR(250) NOT NULL,
        MembershipRole TINYINT NOT NULL,
        ProfileStatus TINYINT NOT NULL,
        ProfileCompleteness DECIMAL(5,2) NOT NULL,
        ProfileVersion INT NOT NULL,
        UpdatedAtUtc DATETIME2(3) NOT NULL
    );
    INSERT INTO @Listed
    EXEC dbo.FundingPlatform_usp_Organization_ListForUser @UserPublicId = @PublicUserId;

    IF NOT EXISTS
       (SELECT 1 FROM @Listed WHERE PublicId = @OrganizationPublicId AND MembershipRole = 1 AND ProfileVersion = 1)
        THROW 52503, N'The owner cannot list the newly created organization.', 1;

    DECLARE @OtherPublicUserId UNIQUEIDENTIFIER = NEWID();
    DECLARE @OtherEmail NVARCHAR(320) = N'org-b-' + REPLACE(CONVERT(NVARCHAR(36), @Fixture), N'-', N'') + N'@example.invalid';
    INSERT INTO dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, Status, PreferredLocale)
    VALUES
        (@OtherPublicUserId, @OtherEmail, UPPER(@OtherEmail), N'Other tenant SQL smoke',
         N'smoke-password-hash-not-a-credential', N'smoke-security-stamp-b', 1, 2, N'es-CL');

    DELETE FROM @Listed;
    INSERT INTO @Listed
    EXEC dbo.FundingPlatform_usp_Organization_ListForUser @UserPublicId = @OtherPublicUserId;
    IF EXISTS (SELECT 1 FROM @Listed)
        THROW 52505, N'An organization leaked into another active user tenant list.', 1;

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

    DECLARE @UpdatedSnapshot NVARCHAR(MAX) = N'{"name":"Organization SQL smoke updated"}';
    DECLARE @UpdatedHash BINARY(32) = HASHBYTES('SHA2_256', @UpdatedSnapshot);
    DECLARE @Updated TABLE
    (
        Id BIGINT NOT NULL,
        PublicId UNIQUEIDENTIFIER NOT NULL,
        ProfileVersion INT NOT NULL,
        RowVersion BINARY(8) NOT NULL
    );
    INSERT INTO @Updated (Id, PublicId, ProfileVersion, RowVersion)
    EXEC dbo.FundingPlatform_usp_Organization_UpdateProfileByPublicId
        @OrganizationPublicId = @OrganizationPublicId,
        @UserPublicId = @PublicUserId,
        @ExpectedRowVersion = @InitialRowVersion,
        @Name = N'Organization SQL smoke updated',
        @HomeCountryId = 152,
        @OrganizationTypeId = 2,
        @ProfileStatus = 2,
        @ProfileCompleteness = 100,
        @SnapshotJson = @UpdatedSnapshot,
        @ContentHash = @UpdatedHash,
        @CountryIds = @CountryIds,
        @RegionIds = @RegionIds,
        @CategoryIds = @CategoryIds,
        @BeneficiaryTypeIds = @BeneficiaryTypeIds,
        @ProjectTypeIds = @ProjectTypeIds,
        @TagIds = @TagIds,
        @Languages = @Languages;

    IF NOT EXISTS
       (SELECT 1 FROM @Updated WHERE PublicId = @OrganizationPublicId
        AND ProfileVersion = 2 AND RowVersion <> @InitialRowVersion)
       OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_OrganizationRegions
        WHERE OrganizationId = @OrganizationId AND RegionId = 7)
       OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_OrganizationProfileVersions
        WHERE OrganizationId = @OrganizationId AND ProfileVersion = 2 AND ContentHash = @UpdatedHash)
        THROW 52504, N'Organization profile replacement or versioning failed.', 1;

    IF @InitialTransactionCount = 0
        ROLLBACK TRANSACTION;
    ELSE
        ROLLBACK TRANSACTION FundingPlatform_Smoke005;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FundingPlatform_Smoke005;
    THROW;
END CATCH;

SELECT CAST(1 AS BIT) AS Succeeded;
