/* Transactional fixture: own organization -> opt-in professional; no production data changes. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke044;
BEGIN TRY
    DECLARE @Actor UNIQUEIDENTIFIER = NEWID(), @Professional UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.FundingPlatform_Users(PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp, EmailConfirmed, Status, PreferredLocale)
    SELECT value, CONVERT(NVARCHAR(36), value) + N'@example.invalid', UPPER(CONVERT(NVARCHAR(36), value) + N'@example.invalid'),
        N'Discovery synthetic', N'not-a-credential', N'discovery-smoke', 1, 2, N'es-CL'
    FROM (VALUES (@Actor), (@Professional)) AS fixtures(value);
    DECLARE @Organization TABLE(Id BIGINT, PublicId UNIQUEIDENTIFIER, ProfileVersion INT, RowVersion BINARY(8));
    DECLARE @Hash BINARY(32) = HASHBYTES('SHA2_256', N'discovery-smoke');
    INSERT INTO @Organization EXEC dbo.FundingPlatform_usp_Organization_CreateForUser
        @UserPublicId = @Actor, @Name = N'Discovery smoke', @HomeCountryId = 152, @OrganizationTypeId = 2,
        @SnapshotJson = N'{"name":"Discovery smoke"}', @ContentHash = @Hash;
    DECLARE @OrganizationId UNIQUEIDENTIFIER = (SELECT PublicId FROM @Organization);
    DECLARE @Write TABLE(EntityId UNIQUEIDENTIFIER, ETag NVARCHAR(18), WasReplay BIT);
    DECLARE @Profile NVARCHAR(MAX) = N'{"displayName":"Discovery professional","headline":"GIS","countryId":152,"skills":["GIS"],"languageIds":[],"categoryIds":[1],"isDiscoverable":false,"allowsInvitations":false}';
    INSERT INTO @Write EXEC dbo.FundingPlatform_usp_ProfessionalProfile_Save @Professional, @Profile, NULL, @Hash, @Hash;
    DECLARE @ProfileId UNIQUEIDENTIFIER = (SELECT EntityId FROM @Write);
    DECLARE @Expected BINARY(8) = CONVERT(BINARY(8), REPLACE((SELECT ETag FROM @Write), N'"', N''), 2);
    DECLARE @Document TABLE(Json NVARCHAR(MAX));
    INSERT INTO @Document EXEC dbo.FundingPlatform_usp_DiscoveryMatching_Context @Actor, 2, @OrganizationId, 3;
    IF EXISTS(SELECT 1 FROM @Document CROSS APPLY OPENJSON(Json, '$.candidates') WHERE JSON_VALUE(value, '$.Id') = CONVERT(NVARCHAR(36), @ProfileId))
        THROW 55650, N'Private professional leaked into matching.', 1;
    DELETE FROM @Document; DELETE FROM @Write;
    SET @Profile = JSON_MODIFY(JSON_MODIFY(@Profile, '$.isDiscoverable', CAST(1 AS BIT)), '$.allowsInvitations', CAST(1 AS BIT));
    SET @Hash = HASHBYTES('SHA2_256', N'discovery-opt-in');
    INSERT INTO @Write EXEC dbo.FundingPlatform_usp_ProfessionalProfile_Save @Professional, @Profile, @Expected, @Hash, @Hash;
    INSERT INTO @Document EXEC dbo.FundingPlatform_usp_DiscoveryMatching_Context @Actor, 2, @OrganizationId, 3;
    IF NOT EXISTS(SELECT 1 FROM @Document CROSS APPLY OPENJSON(Json, '$.candidates') WHERE JSON_VALUE(value, '$.Id') = CONVERT(NVARCHAR(36), @ProfileId))
        THROW 55651, N'Opt-in professional missing from matching.', 1;
    IF EXISTS(SELECT 1 FROM @Document WHERE Json LIKE N'%@example.invalid%' OR Json LIKE N'%PasswordHash%')
        THROW 55652, N'Matching leaked account fields.', 1;
    DELETE FROM @Document;
    DECLARE @Denied BIT = 0;
    SET XACT_ABORT OFF;
    BEGIN TRY
        INSERT INTO @Document EXEC dbo.FundingPlatform_usp_DiscoveryMatching_Context @Professional, 2, @OrganizationId, 3;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> 55601 THROW;
        SET @Denied = 1;
    END CATCH;
    IF @Denied = 0 THROW 55653, N'Unrelated user read private source.', 1;
    SET XACT_ABORT ON;
    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke044;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke044;
    THROW;
END CATCH;
