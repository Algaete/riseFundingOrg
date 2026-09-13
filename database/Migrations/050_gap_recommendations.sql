/* On-demand recommendations. No tables, timers, matching writes or automatic invitations.
   Source = active project membership; opportunity = existing public-ready projection.
   Candidate selection reuses 044's public/opt-in/block checks, never an unrestricted directory. */
SET XACT_ABORT ON;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_GapRecommendations_Context
 @UserPublicId UNIQUEIDENTIFIER, @ProjectPublicId UNIQUEIDENTIFIER, @OpportunityPublicId UNIQUEIDENTIFIER
AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @UserId BIGINT;
 EXEC dbo.FundingPlatform_usp_Collaboration_User @UserPublicId, @UserId OUTPUT;
 SELECT (SELECT project.Title AS projectTitle, opportunity.Title AS opportunityTitle,
    opportunity.ContentVersion AS contentVersion, organization.HomeCountryId AS homeCountryId,
    metadata.ContentVersion AS reviewedContentVersion,
    CASE JSON_VALUE(metadata.DataJson, '$.requiresConsortium') WHEN N'true' THEN CONVERT(BIT, 1) WHEN N'false' THEN CONVERT(BIT, 0) END AS requiresConsortium,
    CASE JSON_VALUE(metadata.DataJson, '$.requiresInternationalPartner') WHEN N'true' THEN CONVERT(BIT, 1) WHEN N'false' THEN CONVERT(BIT, 0) END AS requiresInternationalPartner,
    JSON_VALUE(metadata.DataJson, '$.evidenceUrl') AS evidenceUrl,
    JSON_VALUE(project.EnrichmentJson, '$.soughtPartners') AS soughtPartners,
    JSON_VALUE(project.EnrichmentJson, '$.soughtProfessionals') AS soughtProfessionals,
    CASE JSON_VALUE(project.EnrichmentJson, '$.seekingConsortium') WHEN N'true' THEN CONVERT(BIT, 1) WHEN N'false' THEN CONVERT(BIT, 0) END AS seekingConsortium,
    TODATETIMEOFFSET(SYSUTCDATETIME(), '+00:00') AS evaluatedAtUtc
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES) AS Json
 FROM dbo.FundingPlatform_Projects project
 INNER JOIN dbo.FundingPlatform_Organizations organization ON organization.Id = project.OrganizationId AND organization.IsActive = 1
 INNER JOIN dbo.FundingPlatform_OrganizationUsers membership ON membership.OrganizationId = organization.Id
    AND membership.UserId = @UserId AND membership.MembershipStatus = 1
 INNER JOIN dbo.FundingPlatform_FundingOpportunities opportunity ON opportunity.PublicId = @OpportunityPublicId
 INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() ready ON ready.FundingOpportunityId = opportunity.Id
 LEFT JOIN dbo.FundingPlatform_FundingDiscovery metadata ON metadata.FundingOpportunityId = opportunity.Id
    AND metadata.ContentVersion = opportunity.ContentVersion
 WHERE project.PublicId = @ProjectPublicId AND project.IsActive = 1 AND project.PublicationStatus <> 4;
END;
GO
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_GapRecommendations_Context TO FundingPlatform_ApiRuntimeRole;
