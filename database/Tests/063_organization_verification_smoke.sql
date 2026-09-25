/* Synthetic private decisions only; no real accounts, messages or external services.
   Rollback on success or failure. Never changes access/publication permissions. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke063;
BEGIN TRY
    DECLARE @Actor UNIQUEIDENTIFIER = NEWID(), @OrgPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @Tag NVARCHAR(80) = N'verification-smoke-' + CONVERT(NVARCHAR(36), @Actor);
    INSERT dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, Status, PreferredLocale, TwoFactorEnabled)
    VALUES (@Actor, @Tag + N'@example.invalid', UPPER(@Tag + N'@example.invalid'), @Tag,
        N'not-a-credential', @Tag, 1, 2, N'es-CL', 1);
    DECLARE @ActorId BIGINT = SCOPE_IDENTITY();
    INSERT dbo.FundingPlatform_UserRoles(UserId, RoleId)
        SELECT @ActorId, Id FROM dbo.FundingPlatform_Roles WHERE NormalizedName = N'ADMIN';
    DECLARE @OrgType SMALLINT = (SELECT TOP (1) Id FROM dbo.FundingPlatform_OrganizationTypes WHERE IsActive = 1 ORDER BY Id);
    INSERT dbo.FundingPlatform_Organizations
        (PublicId, CreatedByUserId, Name, HomeCountryId, OrganizationTypeId, ProfileStatus, ProfileCompleteness)
    VALUES (@OrgPublicId, @ActorId, @Tag, 152, @OrgType, 2, 100);
    DECLARE @OrgId BIGINT = SCOPE_IDENTITY();
    DECLARE @OriginalRowVersion BINARY(8) = (SELECT RowVersion FROM dbo.FundingPlatform_Organizations WHERE Id = @OrgId);
    DECLARE @Result TABLE(Json NVARCHAR(MAX));

    INSERT @Result EXEC dbo.FundingPlatform_usp_OrganizationVerification_Get @Actor, @OrgPublicId;
    IF COALESCE((SELECT JSON_VALUE(Json, '$.status') FROM @Result), '') <> '0'
       OR COALESCE((SELECT JSON_VALUE(Json, '$.revision') FROM @Result), '') <> '0'
       OR COALESCE((SELECT JSON_QUERY(Json, '$.history') FROM @Result), '') <> '[]'
        THROW 56360, N'Complete profiles must start unverified with empty history.', 1;
    IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_OrganizationVerifications WHERE OrganizationId = @OrgId)
        THROW 56361, N'Reading created a verification decision.', 1;

    DELETE @Result;
    INSERT @Result EXEC dbo.FundingPlatform_usp_OrganizationVerification_Decide
        @Actor, @OrgPublicId, 1, N'Synthetic identity checked by the reviewer.', 0, 1;
    IF NOT EXISTS(SELECT 1 FROM @Result WHERE JSON_VALUE(Json, '$.status') = '1'
        AND JSON_VALUE(Json, '$.revision') = '1' AND JSON_VALUE(Json, '$.reviewedProfileVersion') = '1'
        AND JSON_VALUE(Json, '$.reviewedByUserPublicId') = CONVERT(NVARCHAR(36), @Actor))
        THROW 56362, N'Verification attribution or version missing.', 1;
    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_Organizations WHERE Id = @OrgId
        AND RowVersion = @OriginalRowVersion AND IsActive = 1 AND ProfileStatus = 2 AND ProfileVersion = 1)
        THROW 56363, N'Verification changed the profile or access.', 1;

    /* A new profile version invalidates the effective decision, but not its history. */
    UPDATE dbo.FundingPlatform_Organizations SET ProfileVersion = ProfileVersion + 1 WHERE Id = @OrgId;
    DELETE @Result;
    INSERT @Result EXEC dbo.FundingPlatform_usp_OrganizationVerification_Get @Actor, @OrgPublicId;
    IF NOT EXISTS(SELECT 1 FROM @Result WHERE JSON_VALUE(Json, '$.status') = '0'
        AND JSON_VALUE(Json, '$.recordedStatus') = '1' AND JSON_VALUE(Json, '$.needsReverification') = 'true'
        AND JSON_VALUE(Json, '$.revision') = '1' AND JSON_VALUE(Json, '$.profileVersion') = '2')
        THROW 56364, N'Stale verification was retained after a profile edit.', 1;

    DELETE @Result;
    INSERT @Result EXEC dbo.FundingPlatform_usp_OrganizationVerification_Decide
        @Actor, @OrgPublicId, 2, N'Synthetic rejection; evidence does not match.', 1, 2;
    IF NOT EXISTS(SELECT 1 FROM @Result WHERE JSON_VALUE(Json, '$.status') = '2'
        AND JSON_VALUE(Json, '$.revision') = '2' AND JSON_VALUE(Json, '$.needsReverification') = 'false')
        THROW 56365, N'Rejection did not record the current profile version.', 1;
    UPDATE dbo.FundingPlatform_Organizations SET ProfileVersion = ProfileVersion + 1 WHERE Id = @OrgId;
    DELETE @Result;
    INSERT @Result EXEC dbo.FundingPlatform_usp_OrganizationVerification_Get @Actor, @OrgPublicId;
    IF NOT EXISTS(SELECT 1 FROM @Result WHERE JSON_VALUE(Json, '$.status') = '0'
        AND JSON_VALUE(Json, '$.recordedStatus') = '2' AND JSON_VALUE(Json, '$.needsReverification') = 'true')
        THROW 56366, N'Edited rejected profile did not become pending.', 1;

    DELETE @Result;
    INSERT @Result EXEC dbo.FundingPlatform_usp_OrganizationVerification_Decide
        @Actor, @OrgPublicId, 0, N'Synthetic reopening for further review.', 2, 3;
    IF NOT EXISTS(SELECT 1 FROM @Result WHERE JSON_VALUE(Json, '$.status') = '0'
        AND JSON_VALUE(Json, '$.revision') = '3' AND JSON_VALUE(Json, '$.needsReverification') = 'false')
        THROW 56367, N'Explicit reopening failed.', 1;
    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_OrganizationVerificationHistory WHERE OrganizationId = @OrgId) <> 3
        THROW 56368, N'History was lost or duplicated.', 1;
    IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_OrganizationVerificationHistory WHERE OrganizationId = @OrgId
        AND (ReviewedByUserId <> @ActorId OR LEN(Reason) < 5))
        THROW 56369, N'Decision audit is incomplete.', 1;

    DELETE @Result;
    DECLARE @Missing UNIQUEIDENTIFIER = NEWID();
    INSERT @Result EXEC dbo.FundingPlatform_usp_OrganizationVerification_Get @Actor, @Missing;
    IF EXISTS(SELECT 1 FROM @Result WHERE Json IS NOT NULL)
        THROW 56370, N'Missing organization should return null, not an empty JSON object.', 1;

    IF EXISTS(SELECT 1 FROM sys.database_permissions WHERE class = 1
        AND major_id IN (OBJECT_ID(N'dbo.FundingPlatform_OrganizationVerifications'),
            OBJECT_ID(N'dbo.FundingPlatform_OrganizationVerificationHistory'))
        AND grantee_principal_id IN (DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole'),
            DATABASE_PRINCIPAL_ID(N'FundingPlatform_GeneralWorkerRole'))
        AND state IN (N'G', N'W'))
        THROW 56371, N'Private verification tables have direct runtime grants.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke063;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
    BEGIN
        IF @InitialTransactionCount = 0 OR XACT_STATE() = -1 ROLLBACK TRANSACTION;
        ELSE ROLLBACK TRANSACTION FP_Smoke063;
    END;
    THROW;
END CATCH;
