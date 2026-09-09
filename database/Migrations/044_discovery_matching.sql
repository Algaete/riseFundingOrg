/* 044: read-only cross-entity matching. No role grants, contacts or automatic acceptance.
   Public targets only; bounded latest-200 candidate corpus, explicitly reported as truncated. */
SET XACT_ABORT ON;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_DiscoveryMatching_Context
 @UserPublicId UNIQUEIDENTIFIER, @SourceKind TINYINT, @SourcePublicId UNIQUEIDENTIFIER, @TargetKind TINYINT
AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @UserId BIGINT, @OrganizationId BIGINT, @SourceName NVARCHAR(350), @Source NVARCHAR(MAX);
 EXEC dbo.FundingPlatform_usp_Collaboration_User @UserPublicId, @UserId OUTPUT;
 IF @SourceKind IS NULL OR @SourceKind NOT BETWEEN 1 AND 4 OR @TargetKind IS NULL OR @TargetKind NOT BETWEEN 1 AND 3
    OR (@SourceKind IN (3,4) AND @TargetKind <> 1) OR (@SourceKind IN (1,2) AND @TargetKind = 1)
     THROW 55601, N'Invalid discovery scope.', 1;
 IF @SourceKind = 1
   SELECT @SourceName = p.Title, @OrganizationId = o.Id, @Source = (SELECT JSON_QUERY(COALESCE((SELECT N'[' + STRING_AGG(CONVERT(NVARCHAR(MAX), CountryId), N',') + N']' FROM dbo.FundingPlatform_ProjectCountries WHERE ProjectId = p.Id), N'[]')) AS countries,
 JSON_QUERY(COALESCE((SELECT N'[' + STRING_AGG(CONVERT(NVARCHAR(MAX), FundingCategoryId), N',') + N']' FROM dbo.FundingPlatform_ProjectCategories WHERE ProjectId = p.Id), N'[]')) AS categories,
 JSON_QUERY(N'[' + CONVERT(NVARCHAR(6), o.OrganizationTypeId) + N']') AS organizationTypes,
 CASE WHEN p.ConfirmedFunding IS NOT NULL THEN p.FundingGap END AS minimumAmount,
 CASE WHEN p.ConfirmedFunding IS NOT NULL THEN p.FundingGap END AS maximumAmount, p.Currency AS currency,
 p.ProjectStage AS projectStage, JSON_VALUE(p.EnrichmentJson, '$.soughtProfessionals') AS needs FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES)
   FROM dbo.FundingPlatform_Projects p
   INNER JOIN dbo.FundingPlatform_Organizations o ON o.Id = p.OrganizationId AND o.IsActive = 1
   INNER JOIN dbo.FundingPlatform_OrganizationUsers m ON m.OrganizationId = o.Id AND m.UserId = @UserId AND m.MembershipStatus = 1
   WHERE p.PublicId = @SourcePublicId AND p.IsActive = 1 AND p.PublicationStatus <> 4;
 IF @SourceKind = 2
   SELECT @SourceName = o.Name, @OrganizationId = o.Id, @Source = (SELECT JSON_QUERY(N'[' + CONVERT(NVARCHAR(6), o.HomeCountryId) + N']') AS countries,
 JSON_QUERY(COALESCE((SELECT N'[' + STRING_AGG(CONVERT(NVARCHAR(MAX), FundingCategoryId), N',') + N']' FROM dbo.FundingPlatform_OrganizationCategories WHERE OrganizationId = o.Id), N'[]')) AS categories,
 JSON_QUERY(N'[' + CONVERT(NVARCHAR(6), o.OrganizationTypeId) + N']') AS organizationTypes
 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
   FROM dbo.FundingPlatform_Organizations o
   INNER JOIN dbo.FundingPlatform_OrganizationUsers m ON m.OrganizationId = o.Id AND m.UserId = @UserId AND m.MembershipStatus = 1
   WHERE o.PublicId = @SourcePublicId AND o.IsActive = 1;
 IF @SourceKind = 3
   SELECT @SourceName = f.Name, @Source = N'{"countries":[],"categories":[],"organizationTypes":[]}'
   FROM dbo.FundingPlatform_Funders f
   INNER JOIN dbo.FundingPlatform_FunderWorkspaceOwners owners ON owners.FunderId = f.Id AND owners.UserId = @UserId AND owners.IsActive = 1
   WHERE f.PublicId = @SourcePublicId AND f.IsActive = 1;
 IF @SourceKind = 4
   SELECT @SourceName = f.Title, @Source = (SELECT JSON_QUERY(COALESCE((SELECT N'[' + STRING_AGG(CONVERT(NVARCHAR(MAX), CountryId), N',') + N']' FROM dbo.FundingPlatform_FundingOpportunityCountries WHERE FundingOpportunityId = f.Id), N'[]')) AS countries,
 JSON_QUERY(COALESCE((SELECT N'[' + STRING_AGG(CONVERT(NVARCHAR(MAX), FundingCategoryId), N',') + N']' FROM dbo.FundingPlatform_FundingOpportunityCategories WHERE FundingOpportunityId = f.Id), N'[]')) AS categories,
 JSON_QUERY(COALESCE((SELECT N'[' + STRING_AGG(CONVERT(NVARCHAR(MAX), OrganizationTypeId), N',') + N']' FROM dbo.FundingPlatform_FundingOpportunityOrganizationTypes WHERE FundingOpportunityId = f.Id AND EligibilityMode = 1), N'[]')) AS organizationTypes,
 JSON_QUERY(COALESCE((SELECT N'[' + STRING_AGG(CONVERT(NVARCHAR(MAX), OrganizationTypeId), N',') + N']' FROM dbo.FundingPlatform_FundingOpportunityOrganizationTypes WHERE FundingOpportunityId = f.Id AND EligibilityMode = 2), N'[]')) AS excludedOrganizationTypes,
 CASE WHEN f.AmountStatus = 1 THEN f.MinAmount END AS minimumAmount,
 CASE WHEN f.AmountStatus = 1 THEN f.MaxAmount END AS maximumAmount, f.Currency AS currency,
 CONVERT(BIT, CASE WHEN f.GeographicScope = 2 THEN 1 ELSE 0 END) AS global
 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES)
   FROM dbo.FundingPlatform_FundingOpportunities f
   WHERE f.PublicId = @SourcePublicId AND f.IsActive = 1 AND
    (EXISTS (SELECT 1 FROM dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() ready WHERE ready.FundingOpportunityId = f.Id)
     OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_OpportunityWorkspaceOwners managed
        INNER JOIN dbo.FundingPlatform_FunderWorkspaceOwners owners ON owners.FunderId = managed.FunderId AND owners.UserId = @UserId AND owners.IsActive = 1
        WHERE managed.FundingOpportunityId = f.Id));
 IF @SourceName IS NULL THROW 55601, N'Discovery source not available.', 1;
 CREATE TABLE #Candidates(Id UNIQUEIDENTIFIER NOT NULL, Name NVARCHAR(350) NOT NULL, Summary NVARCHAR(2000) NULL,
   Href NVARCHAR(500) NOT NULL, Features NVARCHAR(MAX) NOT NULL, UpdatedAtUtc DATETIME2(3) NOT NULL);
 IF @TargetKind = 1
   INSERT #Candidates
   SELECT p.PublicId, p.Title, p.Summary, N'/marketplace/projects/' + p.Slug, (SELECT JSON_QUERY(COALESCE((SELECT N'[' + STRING_AGG(CONVERT(NVARCHAR(MAX), CountryId), N',') + N']' FROM dbo.FundingPlatform_ProjectCountries WHERE ProjectId = p.Id), N'[]')) AS countries,
 JSON_QUERY(COALESCE((SELECT N'[' + STRING_AGG(CONVERT(NVARCHAR(MAX), FundingCategoryId), N',') + N']' FROM dbo.FundingPlatform_ProjectCategories WHERE ProjectId = p.Id), N'[]')) AS categories,
 JSON_QUERY(N'[' + CONVERT(NVARCHAR(6), o.OrganizationTypeId) + N']') AS organizationTypes,
 CASE WHEN p.ConfirmedFunding IS NOT NULL THEN p.FundingGap END AS minimumAmount,
 CASE WHEN p.ConfirmedFunding IS NOT NULL THEN p.FundingGap END AS maximumAmount, p.Currency AS currency,
 p.ProjectStage AS projectStage, JSON_VALUE(p.EnrichmentJson, '$.soughtProfessionals') AS needs FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES), p.UpdatedAtUtc
   FROM dbo.FundingPlatform_Projects p
   INNER JOIN dbo.FundingPlatform_ifn_ProjectMarketplaceReady() ready ON ready.ProjectId = p.Id
   INNER JOIN dbo.FundingPlatform_Organizations o ON o.Id = p.OrganizationId
   WHERE p.ProjectStatus NOT IN (4,6) AND (p.FundingGap IS NULL OR p.FundingGap > 0);
 IF @TargetKind = 2
   INSERT #Candidates
   SELECT o.PublicId, o.Name, LEFT(o.Description, 2000), N'/marketplace/organizations/' + CONVERT(NVARCHAR(36), o.PublicId), (SELECT JSON_QUERY(N'[' + CONVERT(NVARCHAR(6), o.HomeCountryId) + N']') AS countries,
 JSON_QUERY(COALESCE((SELECT N'[' + STRING_AGG(CONVERT(NVARCHAR(MAX), FundingCategoryId), N',') + N']' FROM dbo.FundingPlatform_OrganizationCategories WHERE OrganizationId = o.Id), N'[]')) AS categories,
 JSON_QUERY(N'[' + CONVERT(NVARCHAR(6), o.OrganizationTypeId) + N']') AS organizationTypes
 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), o.UpdatedAtUtc
   FROM dbo.FundingPlatform_Organizations o
   INNER JOIN dbo.FundingPlatform_ifn_OrganizationMarketplaceReady() ready ON ready.OrganizationId = o.Id
   INNER JOIN dbo.FundingPlatform_OrganizationNetworkingPreferences preferences ON preferences.OrganizationId = o.Id AND preferences.IsDiscoverable = 1
   WHERE o.Id <> @OrganizationId AND NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_OrganizationConnectionRequests blocked
     WHERE blocked.Status = 4 AND ((blocked.RequesterOrganizationId = @OrganizationId AND blocked.RecipientOrganizationId = o.Id)
       OR (blocked.RecipientOrganizationId = @OrganizationId AND blocked.RequesterOrganizationId = o.Id)));
 IF @TargetKind = 3
   INSERT #Candidates
   SELECT profiles.PublicId, JSON_VALUE(profiles.DataJson, '$.displayName'), JSON_VALUE(profiles.DataJson, '$.headline'),
     N'/collaboration/consortia?professionalId=' + CONVERT(NVARCHAR(36), profiles.PublicId),
     (SELECT JSON_QUERY(CASE WHEN profiles.CountryId IS NULL THEN N'[]' ELSE N'[' + CONVERT(NVARCHAR(6), profiles.CountryId) + N']' END) AS countries,
       JSON_QUERY(profiles.DataJson, '$.categoryIds') AS categories, JSON_QUERY(N'[]') AS organizationTypes,
       JSON_QUERY(profiles.DataJson, '$.skills') AS skills FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), profiles.UpdatedAtUtc
   FROM dbo.FundingPlatform_ProfessionalProfiles profiles
   INNER JOIN dbo.FundingPlatform_Users users ON users.Id = profiles.UserId AND users.Status = 2 AND users.EmailConfirmed = 1
   WHERE profiles.IsDiscoverable = 1 AND profiles.AllowsInvitations = 1 AND profiles.UserId <> @UserId;
 SELECT (SELECT @SourceName AS sourceName, JSON_QUERY(@Source) AS source,
   (SELECT COUNT_BIG(1) FROM #Candidates) AS totalCandidateCount,
   TODATETIMEOFFSET(SYSUTCDATETIME(), '+00:00') AS evaluatedAtUtc,
   JSON_QUERY((SELECT TOP(200) Id, Name, Summary, Href, JSON_QUERY(Features) AS features
      FROM #Candidates ORDER BY UpdatedAtUtc DESC, Id FOR JSON PATH, INCLUDE_NULL_VALUES)) AS candidates
   FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS Json;
END;
GO
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_DiscoveryMatching_Context TO FundingPlatform_ApiRuntimeRole;
