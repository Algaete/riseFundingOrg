/* Synthetic ownership fixtures; rollback only. Run on disposable/dev SQL after 042.
   Parser validation is not execution. Existing editorial review smoke remains 010. */
SET NOCOUNT ON;
SET XACT_ABORT OFF;
IF OBJECT_ID(N'dbo.FundingPlatform_FunderWorkspaceOwners', N'U') IS NULL
    THROW 55440, N'Funder workspace ownership is missing.', 1;
IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_Funder_AdminReview')) NOT LIKE N'%FundingPlatform_fn_AdminAccessState%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunity_AdminReview')) NOT LIKE N'%FundingPlatform_fn_AdminAccessState%'
    THROW 55441, N'Administrative review guard is missing.', 1;
DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke042;
BEGIN TRY
    DECLARE @Owner UNIQUEIDENTIFIER = NEWID(), @Stranger UNIQUEIDENTIFIER = NEWID();
    DECLARE @Slug NVARCHAR(180) = N'workspace-' + CONVERT(NVARCHAR(36), @Owner);
    DECLARE @Email NVARCHAR(320) = @Slug + N'@example.invalid';
    INSERT INTO dbo.FundingPlatform_Users(PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp, EmailConfirmed, Status, PreferredLocale)
    VALUES (@Owner, @Email, UPPER(@Email), N'Workspace owner', N'not-a-credential', N'workspace', 1, 2, N'es-CL');
    SET @Email = N'workspace-' + CONVERT(NVARCHAR(36), @Stranger) + N'@example.invalid';
    INSERT INTO dbo.FundingPlatform_Users(PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp, EmailConfirmed, Status, PreferredLocale)
    VALUES (@Stranger, @Email, UPPER(@Email), N'Unrelated user', N'not-a-credential', N'workspace-other', 1, 2, N'es-CL');
    DECLARE @OwnerId BIGINT = (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @Owner);
    DECLARE @Key BINARY(32) = HASHBYTES('SHA2_256', N'workspace-create');
    DECLARE @Hash BINARY(32) = HASHBYTES('SHA2_256', @Slug);
    DECLARE @Result TABLE(Succeeded BIT, Code NVARCHAR(50), FunderPublicId UNIQUEIDENTIFIER,
        ContentVersion INT, PublicationStatus TINYINT, RowVersion BINARY(8), WasReplay BIT);
    INSERT INTO @Result EXEC dbo.FundingPlatform_usp_Funder_Create
        @AdminUserPublicId = @Owner, @Slug = @Slug, @Name = @Slug,
        @WebsiteUrl = N'https://example.invalid/funder', @CountryId = 152,
        @IdempotencyKeyHash = @Key, @RequestHash = @Hash, @OwnerWorkspace = 1;
    DECLARE @Funder UNIQUEIDENTIFIER = (SELECT FunderPublicId FROM @Result);
    DECLARE @Version BINARY(8) = (SELECT RowVersion FROM @Result);
    IF NOT EXISTS (SELECT 1 FROM @Result WHERE Succeeded = 1 AND PublicationStatus = 0 AND ContentVersion = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_FunderWorkspaceOwners AS owners
           INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = owners.FunderId
           WHERE funders.PublicId = @Funder AND owners.UserId = @OwnerId AND owners.IsActive = 1)
        THROW 55442, N'Owner creation failed or bypassed draft review.', 1;
    DELETE FROM @Result;
    INSERT INTO @Result EXEC dbo.FundingPlatform_usp_Funder_Create
        @AdminUserPublicId = @Owner, @Slug = @Slug, @Name = @Slug,
        @WebsiteUrl = N'https://example.invalid/funder', @CountryId = 152,
        @IdempotencyKeyHash = @Key, @RequestHash = @Hash, @OwnerWorkspace = 1;
    IF NOT EXISTS (SELECT 1 FROM @Result WHERE WasReplay = 1 AND FunderPublicId = @Funder)
        THROW 55443, N'Owner creation did not replay safely.', 1;
    SET @Key = HASHBYTES('SHA2_256', N'workspace-update');
    DELETE FROM @Result;
    INSERT INTO @Result EXEC dbo.FundingPlatform_usp_Funder_Update
        @AdminUserPublicId = @Owner, @FunderPublicId = @Funder, @ExpectedRowVersion = @Version,
        @Name = @Slug, @Description = N'Updated by owner', @WebsiteUrl = N'https://example.invalid/funder',
        @CountryId = 152, @IdempotencyKeyHash = @Key, @RequestHash = @Hash, @OwnerWorkspace = 1;
    IF NOT EXISTS (SELECT 1 FROM @Result WHERE Succeeded = 1 AND ContentVersion = 2 AND PublicationStatus = 0)
        THROW 55444, N'Owner update lost versioning or published without review.', 1;

    EXEC dbo.FundingPlatform_usp_Funder_Admin_Get @AdminUserPublicId = @Owner, @FunderPublicId = @Funder, @OwnerWorkspace = 1;
    EXEC dbo.FundingPlatform_usp_FunderWorkspace_Sources @UserPublicId = @Owner;
    /* Read-only rejection checks keep the fixture transaction usable. */
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_Funder_Admin_Get @AdminUserPublicId = @Stranger, @FunderPublicId = @Funder, @OwnerWorkspace = 1;
        THROW 55445, N'Unrelated user read another funder.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> 51601 THROW;
    END CATCH;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_Funder_Admin_Get @AdminUserPublicId = @Owner, @FunderPublicId = @Funder;
        THROW 55446, N'Ownership granted global administrative access.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> 51601 THROW;
    END CATCH;

    DECLARE @Countries dbo.FundingPlatform_SmallIntIdList;
    DECLARE @Regions dbo.FundingPlatform_IntIdList;
    DECLARE @Categories dbo.FundingPlatform_IntIdList;
    DECLARE @Beneficiaries dbo.FundingPlatform_IntIdList;
    DECLARE @Types dbo.FundingPlatform_IntIdList;
    INSERT INTO @Categories VALUES(1);
    DECLARE @SourceId INT = (SELECT Id FROM dbo.FundingPlatform_FundingSources WHERE ProviderCode = N'funder-workspace');
    DECLARE @Links NVARCHAR(MAX) = N'[{"funderPublicId":"' + CONVERT(NVARCHAR(36), @Funder) + N'","role":1}]';
    DECLARE @OpportunityResult TABLE(Succeeded BIT, Code NVARCHAR(50), FundingOpportunityPublicId UNIQUEIDENTIFIER,
        ContentVersion INT, PublicationStatus TINYINT, RowVersion BINARY(8), WasReplay BIT);
    SET @Key = HASHBYTES('SHA2_256', N'workspace-opportunity');
    INSERT INTO @OpportunityResult EXEC dbo.FundingPlatform_usp_FundingOpportunity_Create
        @AdminUserPublicId = @Owner, @Slug = @Slug, @Title = N'Owner opportunity',
        @SponsorName = @Slug, @Summary = N'Synthetic draft', @Description = N'For ownership smoke only',
        @AmountStatus = 2, @DeadlineType = 2, @DeadlinePrecision = 0, @GeographicScope = 2,
        @RemoteApplication = 0, @DataQualityScore = 0, @FundingSourceId = @SourceId,
        @SourceItemKeyHash = @Hash, @SourceUrl = N'https://example.invalid/fund', @SnapshotJson = N'{}', @ContentHash = @Hash,
        @CountryIds = @Countries, @RegionIds = @Regions, @CategoryIds = @Categories,
        @BeneficiaryTypeIds = @Beneficiaries, @ProjectTypeIds = @Types, @FunderLinksJson = @Links,
        @IdempotencyKeyHash = @Key, @RequestHash = @Hash, @OwnerWorkspace = 1;
    DECLARE @Opportunity UNIQUEIDENTIFIER = (SELECT FundingOpportunityPublicId FROM @OpportunityResult);
    IF NOT EXISTS (SELECT 1 FROM @OpportunityResult WHERE Succeeded = 1 AND PublicationStatus = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_OpportunityWorkspaceOwners AS managed
           INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities ON opportunities.Id = managed.FundingOpportunityId
           INNER JOIN dbo.FundingPlatform_Funders AS funders ON funders.Id = managed.FunderId
           WHERE opportunities.PublicId = @Opportunity AND funders.PublicId = @Funder)
        THROW 55447, N'Opportunity was not atomically assigned to its owner in draft.', 1;
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_FundingOpportunity_Admin_Get @AdminUserPublicId = @Stranger, @FundingOpportunityPublicId = @Opportunity, @OwnerWorkspace = 1;
        THROW 55448, N'Unrelated user read a managed opportunity.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> 51601 THROW;
    END CATCH;
    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke042;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke042;
    THROW;
END CATCH;
