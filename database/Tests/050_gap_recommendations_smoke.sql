/* Real result assertions using synthetic tenants/funding, always rolled back.
   Candidate opt-in and block rules remain owned and exercised by 043/044. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke050;
BEGIN TRY
 DECLARE @Actor UNIQUEIDENTIFIER = NEWID(), @Stranger UNIQUEIDENTIFIER = NEWID(),
    @Project UNIQUEIDENTIFIER = NEWID(), @Opportunity UNIQUEIDENTIFIER = NEWID(), @Now DATETIME2(3) = SYSUTCDATETIME();
 DECLARE @Tag NVARCHAR(80) = N'gap-smoke-' + CONVERT(NVARCHAR(36), @Actor);
 INSERT dbo.FundingPlatform_Users(PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp, EmailConfirmed, Status, PreferredLocale)
 SELECT value, CONVERT(NVARCHAR(36), value) + N'@example.invalid', UPPER(CONVERT(NVARCHAR(36), value) + N'@example.invalid'),
    @Tag, N'not-a-credential', @Tag, 1, 2, N'es-CL' FROM (VALUES(@Actor),(@Stranger)) fixtures(value);
 DECLARE @UserId BIGINT = (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @Actor);
 INSERT dbo.FundingPlatform_Organizations(PublicId, CreatedByUserId, Name, HomeCountryId, OrganizationTypeId, ProfileStatus, ProfileCompleteness, IsActive)
 VALUES(NEWID(), @UserId, @Tag, 152, 2, 2, 100, 1);
 DECLARE @OrganizationId BIGINT = SCOPE_IDENTITY();
 INSERT dbo.FundingPlatform_OrganizationUsers(OrganizationId, UserId, Role, MembershipStatus, JoinedAtUtc)
 VALUES(@OrganizationId, @UserId, 1, 1, @Now);
 INSERT dbo.FundingPlatform_Projects(PublicId, OrganizationId, CreatedByUserId, Slug, Title, Summary, Description,
    ProjectStatus, PublicationStatus, EnrichmentJson, IsActive, CreatedAtUtc, UpdatedAtUtc)
 VALUES(@Project, @OrganizationId, @UserId, @Tag, @Tag, N'Private source', N'Rollback-only project', 0, 0,
    N'{"soughtPartners":"Municipios","soughtProfessionals":"GIS","seekingConsortium":true}', 1, @Now, @Now);
 INSERT dbo.FundingPlatform_Funders(PublicId, Slug, Name, NormalizedName, WebsiteUrl, PublicationStatus,
    PublishedAtUtc, ReviewedAtUtc, ContentVersion, IsActive, CreatedAtUtc, UpdatedAtUtc)
 VALUES(NEWID(), @Tag, @Tag, UPPER(@Tag), N'https://example.invalid/funder', 2, @Now, @Now, 1, 1, @Now, @Now);
 DECLARE @FunderId BIGINT = SCOPE_IDENTITY();
 INSERT dbo.FundingPlatform_FundingOpportunities(PublicId, Slug, Title, Description, Summary, SponsorName,
    AmountStatus, DeadlineType, DeadlinePrecision, GeographicScope, RemoteApplication,
    PublicationStatus, PublishedAtUtc, LastVerifiedAtUtc, DataQualityScore, ContentVersion, IsActive, ReviewedAtUtc)
 VALUES(@Opportunity, @Tag, @Tag, N'Description', N'Summary', @Tag, 2, 2, 0, 2, 0, 2, @Now, @Now, 100, 1, 1, @Now);
 DECLARE @OpportunityId BIGINT = SCOPE_IDENTITY();
 INSERT dbo.FundingPlatform_FundingOpportunityCategories(FundingOpportunityId, FundingCategoryId) VALUES(@OpportunityId, 1);
 INSERT dbo.FundingPlatform_FundingOpportunityFunders(FundingOpportunityId, FunderId, Role, IsActive, CreatedAtUtc, UpdatedAtUtc)
 VALUES(@OpportunityId, @FunderId, 1, 1, @Now, @Now);
 DECLARE @SourceId INT = (SELECT TOP(1) Id FROM dbo.FundingPlatform_FundingSources WHERE IsEnabled = 1 ORDER BY Id);
 DECLARE @Hash BINARY(32) = HASHBYTES('SHA2_256', @Tag);
 INSERT dbo.FundingPlatform_FundingOpportunitySourceLinks(FundingOpportunityId, FundingSourceId, SourceItemKeyHash,
    SourceUrl, CanonicalUrlHash, FirstSeenAtUtc, LastSeenAtUtc, IsPrimary, IsActive)
 VALUES(@OpportunityId, @SourceId, @Hash, N'https://example.invalid/terms', @Hash, @Now, @Now, 1, 1);
 INSERT dbo.FundingPlatform_FundingFieldEvidence(FundingOpportunityId, FieldPath, ValueJson, ExtractionMethod, IsSelected, IsManualLock, CreatedAtUtc)
 SELECT @OpportunityId, path, N'{"status":"unknown","value":null}', 1, 1, 0, @Now
 FROM (VALUES(N'/title'),(N'/description'),(N'/eligibilityDescription'),(N'/closeDate')) fields(path);
 INSERT dbo.FundingPlatform_FundingDiscovery(FundingOpportunityId, ContentVersion, DataJson, ReviewedByUserId, ReviewedAtUtc)
 VALUES(@OpportunityId, 1, N'{"requiresInternationalPartner":true,"requiresConsortium":false,"evidenceUrl":"https://example.invalid/terms"}', @UserId, @Now);
 IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() WHERE FundingOpportunityId = @OpportunityId)
    THROW 55950, N'Synthetic opportunity must be public-ready.', 1;
 DECLARE @Document TABLE(Json NVARCHAR(MAX));
 INSERT @Document EXEC dbo.FundingPlatform_usp_GapRecommendations_Context @Actor, @Project, @Opportunity;
 IF (SELECT COUNT(*) FROM @Document) <> 1 OR NOT EXISTS(SELECT 1 FROM @Document
    WHERE JSON_VALUE(Json, '$.requiresInternationalPartner') = N'true'
      AND JSON_VALUE(Json, '$.requiresConsortium') = N'false' AND JSON_VALUE(Json, '$.seekingConsortium') = N'true'
      AND JSON_VALUE(Json, '$.homeCountryId') = N'152' AND JSON_VALUE(Json, '$.soughtProfessionals') = N'GIS'
      AND JSON_VALUE(Json, '$.reviewedContentVersion') = N'1')
    THROW 55951, N'Current requirement context lost facts or nullable/boolean types.', 1;
 IF EXISTS(SELECT 1 FROM @Document WHERE Json LIKE N'%@example.invalid%' OR Json LIKE N'%PasswordHash%' OR Json LIKE N'%SecurityStamp%')
    THROW 55952, N'Context exposed account fields.', 1;
 DELETE @Document;
 INSERT @Document EXEC dbo.FundingPlatform_usp_GapRecommendations_Context @Stranger, @Project, @Opportunity;
 IF EXISTS(SELECT 1 FROM @Document) THROW 55953, N'Unrelated account read private project context.', 1;
 UPDATE dbo.FundingPlatform_OrganizationUsers SET MembershipStatus = 2 WHERE OrganizationId = @OrganizationId AND UserId = @UserId;
 INSERT @Document EXEC dbo.FundingPlatform_usp_GapRecommendations_Context @Actor, @Project, @Opportunity;
 IF EXISTS(SELECT 1 FROM @Document) THROW 55954, N'Inactive membership read context.', 1;
 UPDATE dbo.FundingPlatform_OrganizationUsers SET MembershipStatus = 1 WHERE OrganizationId = @OrganizationId AND UserId = @UserId;
 UPDATE dbo.FundingPlatform_FundingOpportunities SET ContentVersion = 2 WHERE Id = @OpportunityId;
 INSERT @Document EXEC dbo.FundingPlatform_usp_GapRecommendations_Context @Actor, @Project, @Opportunity;
 IF (SELECT COUNT(*) FROM @Document) <> 1 OR EXISTS(SELECT 1 FROM @Document
    WHERE JSON_VALUE(Json, '$.requiresInternationalPartner') IS NOT NULL OR JSON_VALUE(Json, '$.requiresConsortium') IS NOT NULL
       OR JSON_VALUE(Json, '$.evidenceUrl') IS NOT NULL OR JSON_VALUE(Json, '$.reviewedContentVersion') IS NOT NULL)
    THROW 55955, N'Stale classification or its evidence remained visible.', 1;
 DELETE @Document;
 UPDATE dbo.FundingPlatform_FundingDiscovery SET ContentVersion = 2,
    DataJson = N'{"requiresInternationalPartner":null,"requiresConsortium":null,"evidenceUrl":"https://example.invalid/terms"}' WHERE FundingOpportunityId = @OpportunityId;
 INSERT @Document EXEC dbo.FundingPlatform_usp_GapRecommendations_Context @Actor, @Project, @Opportunity;
 IF (SELECT COUNT(*) FROM @Document) <> 1 OR EXISTS(SELECT 1 FROM @Document
    WHERE JSON_VALUE(Json, '$.requiresInternationalPartner') IS NOT NULL OR JSON_VALUE(Json, '$.requiresConsortium') IS NOT NULL)
    THROW 55956, N'Unknown requirements were coerced to false.', 1;
 DELETE @Document;
 UPDATE dbo.FundingPlatform_FundingOpportunities SET PublicationStatus = 0 WHERE Id = @OpportunityId;
 INSERT @Document EXEC dbo.FundingPlatform_usp_GapRecommendations_Context @Actor, @Project, @Opportunity;
 IF EXISTS(SELECT 1 FROM @Document) THROW 55957, N'Unpublished funding leaked into recommendations.', 1;
 UPDATE dbo.FundingPlatform_FundingOpportunities SET PublicationStatus = 2 WHERE Id = @OpportunityId;
 UPDATE dbo.FundingPlatform_FundingOpportunitySourceLinks SET IsActive = 0 WHERE FundingOpportunityId = @OpportunityId;
 INSERT @Document EXEC dbo.FundingPlatform_usp_GapRecommendations_Context @Actor, @Project, @Opportunity;
 IF EXISTS(SELECT 1 FROM @Document) THROW 55958, N'Funding without public provenance remained available.', 1;
 UPDATE dbo.FundingPlatform_FundingOpportunitySourceLinks SET IsActive = 1 WHERE FundingOpportunityId = @OpportunityId;
 UPDATE dbo.FundingPlatform_Projects SET IsActive = 0 WHERE PublicId = @Project;
 INSERT @Document EXEC dbo.FundingPlatform_usp_GapRecommendations_Context @Actor, @Project, @Opportunity;
 IF EXISTS(SELECT 1 FROM @Document) THROW 55959, N'Inactive project context remained available.', 1;
 IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
 ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke050;
END TRY
BEGIN CATCH
 IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
 ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke050;
 THROW;
END CATCH;
