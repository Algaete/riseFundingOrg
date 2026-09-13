/* Synthetic geography review and context round trips; always rollback.
   Does not publish user records or persist country catalog edits. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke051;
BEGIN TRY
 DECLARE @Actor UNIQUEIDENTIFIER = NEWID(), @Stranger UNIQUEIDENTIFIER = NEWID(),
    @Project UNIQUEIDENTIFIER = NEWID(), @Opportunity UNIQUEIDENTIFIER = NEWID(), @Now DATETIME2(3) = SYSUTCDATETIME();
 DECLARE @Tag NVARCHAR(80) = N'geo-smoke-' + CONVERT(NVARCHAR(36), @Actor);
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

 UPDATE dbo.FundingPlatform_Users SET TwoFactorEnabled = 1 WHERE Id = @UserId;
 INSERT dbo.FundingPlatform_UserRoles(UserId, RoleId)
 SELECT @UserId, Id FROM dbo.FundingPlatform_Roles WHERE NormalizedName = N'ADMIN';
 IF (SELECT COUNT(*) FROM dbo.FundingPlatform_ifn_PartnerGeographyCountries() WHERE RegionCode = N'EU') <> 27
    OR EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_PartnerGeographyCountries() g
       WHERE NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_Countries c WHERE c.Id = g.CountryId))
    THROW 55960, N'Pinned regional catalog is inconsistent with ISO country identifiers.', 1;
 IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_PartnerGeographyCountries() WHERE RegionCode = N'EU' AND CountryId = 196)
    OR EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_PartnerGeographyCountries() WHERE RegionCode = N'EU' AND CountryId IN (826,756))
    OR EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_PartnerGeographyCountries() WHERE RegionCode = N'M49-150' AND CountryId = 196)
    THROW 55961, N'Europe and EU membership were conflated.', 1;
 DECLARE @Data NVARCHAR(MAX) = N'{"funderKind":3,"requiresConsortium":false,"requiresInternationalPartner":true,"evidenceUrl":"https://example.invalid/terms","partnerGeography":{"scope":2,"countryIds":[826],"regionCodes":["EU"],"catalogVersion":"partner-geography-2026-09-12"}}';
 DECLARE @Legacy NVARCHAR(MAX) = N'{"funderKind":3,"requiresConsortium":false,"requiresInternationalPartner":true,"evidenceUrl":"https://example.invalid/terms"}';
 DECLARE @Version BINARY(8) = (SELECT RowVersion FROM dbo.FundingPlatform_FundingDiscovery WHERE FundingOpportunityId = @OpportunityId);
 DECLARE @Key BINARY(32) = HASHBYTES('SHA2_256', @Tag + N'-review');
 SET @Hash = HASHBYTES('SHA2_256', @Data);
 DECLARE @Document TABLE(Json NVARCHAR(MAX));
 INSERT @Document EXEC dbo.FundingPlatform_usp_FundingDiscovery_Review @Actor, @Opportunity, 1, @Data, @Version, @Key, @Hash;
 IF COALESCE((SELECT JSON_VALUE(Json, '$.wasReplay') FROM @Document), N'') <> N'false'
    THROW 55962, N'Geographic review failed.', 1;
 DELETE @Document;
 INSERT @Document EXEC dbo.FundingPlatform_usp_FundingDiscovery_Review @Actor, @Opportunity, 1, @Data, @Version, @Key, @Hash;
 IF COALESCE((SELECT JSON_VALUE(Json, '$.wasReplay') FROM @Document), N'') <> N'true'
    OR (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingDiscoveryReviews WHERE FundingOpportunityId = @OpportunityId) <> 1
    THROW 55963, N'Geographic review replay was not idempotent.', 1;
 DELETE @Document;
 INSERT @Document EXEC dbo.FundingPlatform_usp_GapRecommendations_Context @Actor, @Project, @Opportunity;
 DECLARE @Context NVARCHAR(MAX) = (SELECT Json FROM @Document);
 IF JSON_VALUE(@Context, '$.partnerGeography.scope') <> N'2'
    OR JSON_VALUE(@Context, '$.partnerGeographyValid') <> N'true'
    OR (SELECT COUNT(*) FROM OPENJSON(@Context, '$.eligiblePartnerCountryIds')) <> 28
    OR NOT EXISTS(SELECT 1 FROM OPENJSON(@Context, '$.eligiblePartnerCountryIds') WHERE [value] = N'826')
    OR NOT EXISTS(SELECT 1 FROM OPENJSON(@Context, '$.eligiblePartnerCountryIds') WHERE [value] = N'196')
    OR EXISTS(SELECT 1 FROM OPENJSON(@Context, '$.eligiblePartnerCountryIds') WHERE [value] IN (N'756',N'840'))
    THROW 55964, N'Country/region union did not expand to the exact active set.', 1;
 DELETE @Document;
 UPDATE dbo.FundingPlatform_Countries SET IsActive = 0 WHERE Id = 826;
 INSERT @Document EXEC dbo.FundingPlatform_usp_GapRecommendations_Context @Actor, @Project, @Opportunity;
 SET @Context = (SELECT Json FROM @Document);
 IF JSON_VALUE(@Context, '$.partnerGeographyValid') <> N'false'
    OR EXISTS(SELECT 1 FROM OPENJSON(@Context, '$.eligiblePartnerCountryIds') WHERE [value] = N'826')
    THROW 55965, N'Inactive explicit country remained eligible.', 1;
 UPDATE dbo.FundingPlatform_Countries SET IsActive = 1 WHERE Id = 826;
 DELETE @Document;
 SET @Version = (SELECT RowVersion FROM dbo.FundingPlatform_FundingDiscovery WHERE FundingOpportunityId = @OpportunityId);
 SET @Key = HASHBYTES('SHA2_256', @Tag + N'-legacy');
 SET @Hash = HASHBYTES('SHA2_256', @Legacy);
 INSERT @Document EXEC dbo.FundingPlatform_usp_FundingDiscovery_Review @Actor, @Opportunity, 1, @Legacy, @Version, @Key, @Hash;
 IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingDiscoveryReviews WHERE FundingOpportunityId = @OpportunityId
    AND KeyHash = @Key AND JSON_VALUE(DataJson, '$.partnerGeography.regionCodes[0]') = N'EU')
    THROW 55966, N'Old client erased geographic restrictions or audit lost effective data.', 1;
 DELETE @Document;
 INSERT @Document EXEC dbo.FundingPlatform_usp_FundingDiscovery_AdminGet @Actor, @Opportunity;
 IF COALESCE((SELECT JSON_VALUE(Json, '$.data.partnerGeography.countryIds[0]') FROM @Document), N'') <> N'826'
    THROW 55967, N'Admin read lost reviewed partner geography.', 1;
 DELETE @Document;
 SET @Data = JSON_MODIFY(@Legacy, '$.partnerGeography', JSON_QUERY(N'{"scope":0,"countryIds":[],"regionCodes":[]}'));
 SET @Version = (SELECT RowVersion FROM dbo.FundingPlatform_FundingDiscovery WHERE FundingOpportunityId = @OpportunityId);
 SET @Key = HASHBYTES('SHA2_256', @Tag + N'-clear');
 SET @Hash = HASHBYTES('SHA2_256', @Data);
 INSERT @Document EXEC dbo.FundingPlatform_usp_FundingDiscovery_Review @Actor, @Opportunity, 1, @Data, @Version, @Key, @Hash;
 DELETE @Document;
 INSERT @Document EXEC dbo.FundingPlatform_usp_GapRecommendations_Context @Actor, @Project, @Opportunity;
 SET @Context = (SELECT Json FROM @Document);
 IF JSON_VALUE(@Context, '$.partnerGeography.scope') <> N'0' OR JSON_QUERY(@Context, '$.eligiblePartnerCountryIds') <> N'[]'
    THROW 55968, N'Explicit clear did not return geography to unknown.', 1;
 DELETE @Document;
 SET @Data = JSON_MODIFY(@Legacy, '$.partnerGeography', JSON_QUERY(N'{"scope":2,"countryIds":[250],"regionCodes":[]}'));
 SET @Version = (SELECT RowVersion FROM dbo.FundingPlatform_FundingDiscovery WHERE FundingOpportunityId = @OpportunityId);
 SET @Key = HASHBYTES('SHA2_256', @Tag + N'-country');
 SET @Hash = HASHBYTES('SHA2_256', @Data);
 INSERT @Document EXEC dbo.FundingPlatform_usp_FundingDiscovery_Review @Actor, @Opportunity, 1, @Data, @Version, @Key, @Hash;
 DELETE @Document;
 INSERT @Document EXEC dbo.FundingPlatform_usp_GapRecommendations_Context @Actor, @Project, @Opportunity;
 IF COALESCE((SELECT JSON_QUERY(Json, '$.eligiblePartnerCountryIds') FROM @Document), N'') <> N'[250]'
    THROW 55969, N'Explicit country was not respected.', 1;
 DELETE @Document;
 UPDATE dbo.FundingPlatform_FundingOpportunities SET ContentVersion = 2 WHERE Id = @OpportunityId;
 INSERT @Document EXEC dbo.FundingPlatform_usp_GapRecommendations_Context @Actor, @Project, @Opportunity;
 IF EXISTS(SELECT 1 FROM @Document WHERE JSON_QUERY(Json, '$.partnerGeography') IS NOT NULL OR JSON_QUERY(Json, '$.eligiblePartnerCountryIds') <> N'[]')
    THROW 55970, N'Stale reviewed geography leaked into the matching context.', 1;
 DELETE @Document;
 SET @Version = (SELECT RowVersion FROM dbo.FundingPlatform_FundingDiscovery WHERE FundingOpportunityId = @OpportunityId);
 SET @Key = HASHBYTES('SHA2_256', @Tag + N'-new-version-legacy');
 SET @Hash = HASHBYTES('SHA2_256', @Legacy);
 INSERT @Document EXEC dbo.FundingPlatform_usp_FundingDiscovery_Review @Actor, @Opportunity, 2, @Legacy, @Version, @Key, @Hash;
 IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingDiscovery WHERE FundingOpportunityId = @OpportunityId
    AND JSON_QUERY(DataJson, '$.partnerGeography') IS NOT NULL)
    THROW 55971, N'Old client resurrected geography from a previous content version.', 1;
 IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
 ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke051;
END TRY
BEGIN CATCH
 IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
 ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke051;
 THROW;
END CATCH;
