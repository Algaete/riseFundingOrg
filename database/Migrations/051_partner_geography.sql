/* Reviewed partner headquarters geography. Additive to 045/050; no new runtime grants,
   timers, subscriptions or automatic editorial changes. Catalog is a pinned snapshot:
   UN M49 https://unstats.un.org/unsd/methodology/m49/overview/
   EU https://european-union.europa.eu/principles-countries-history/eu-countries_en
   Generated from Core/FundingOpportunities/partner-regions.json; parity tested. */
SET XACT_ABORT ON;
GO
CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_PartnerGeographyCountries()
RETURNS TABLE
AS RETURN
(
 SELECT regions.Code COLLATE Latin1_General_100_BIN2 AS RegionCode, CONVERT(INT, countries.[value]) AS CountryId
 FROM OPENJSON(N'[{"code":"M49-002","countryIds":[12,24,72,86,108,120,132,140,148,174,175,178,180,204,226,231,232,260,262,266,270,288,324,384,404,426,430,434,450,454,466,478,480,504,508,516,562,566,624,638,646,654,678,686,690,694,706,710,716,728,729,732,748,768,788,800,818,834,854,894]},{"code":"M49-019","countryIds":[28,32,44,52,60,68,74,76,84,92,124,136,152,170,188,192,212,214,218,222,238,239,254,304,308,312,320,328,332,340,388,474,484,500,531,533,534,535,558,591,600,604,630,652,659,660,662,663,666,670,740,780,796,840,850,858,862]},{"code":"M49-142","countryIds":[4,31,48,50,51,64,96,104,116,144,156,196,268,275,344,356,360,364,368,376,392,398,400,408,410,414,417,418,422,446,458,462,496,512,524,586,608,626,634,682,702,704,760,762,764,784,792,795,860,887]},{"code":"M49-150","countryIds":[8,20,40,56,70,100,112,191,203,208,233,234,246,248,250,276,292,300,336,348,352,372,380,428,438,440,442,470,492,498,499,528,578,616,620,642,643,674,688,703,705,724,744,752,756,804,807,826,831,832,833]},{"code":"M49-009","countryIds":[16,36,90,162,166,184,242,258,296,316,334,520,540,548,554,570,574,580,581,583,584,585,598,612,772,776,798,876,882]},{"code":"M49-419","countryIds":[28,32,44,52,68,74,76,84,92,136,152,170,188,192,212,214,218,222,238,239,254,308,312,320,328,332,340,388,474,484,500,531,533,534,535,558,591,600,604,630,652,659,660,662,663,670,740,780,796,850,858,862]},{"code":"EU","countryIds":[40,56,100,191,196,203,208,233,246,250,276,300,348,372,380,428,440,442,470,528,616,620,642,703,705,724,752]}]')
 WITH(Code NVARCHAR(20) '$.code', CountryIds NVARCHAR(MAX) '$.countryIds' AS JSON) regions
 CROSS APPLY OPENJSON(regions.CountryIds) countries
);
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingDiscovery_Review
 @UserPublicId UNIQUEIDENTIFIER, @OpportunityPublicId UNIQUEIDENTIFIER, @ContentVersion INT,
 @DataJson NVARCHAR(MAX), @ExpectedVersion BINARY(8), @KeyHash BINARY(32), @RequestHash BINARY(32)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF @ContentVersion IS NULL OR @ContentVersion < 1 OR @KeyHash IS NULL OR @RequestHash IS NULL OR ISJSON(@DataJson) <> 1
    THROW 55704, N'Invalid classification.', 1;
 DECLARE @Kind INT = TRY_CONVERT(INT, JSON_VALUE(@DataJson, '$.funderKind'));
 IF @Kind NOT BETWEEN 1 AND 6 OR JSON_VALUE(@DataJson, '$.requiresConsortium') NOT IN (N'true', N'false')
    OR JSON_VALUE(@DataJson, '$.requiresInternationalPartner') NOT IN (N'true', N'false')
    OR NULLIF(JSON_VALUE(@DataJson, '$.evidenceUrl'), N'') IS NULL
    THROW 55704, N'Invalid classification.', 1;

 -- Null/absent means an older client: preserve same-version geography under the metadata lock.
 -- An explicit scope 0 with empty arrays is the only way to clear a reviewed restriction.
 DECLARE @Geo NVARCHAR(MAX) = JSON_QUERY(@DataJson, '$.partnerGeography');
 IF EXISTS(SELECT 1 FROM OPENJSON(@DataJson) WHERE [key] = N'partnerGeography' AND [type] NOT IN (0,5))
    OR (SELECT COUNT(*) FROM OPENJSON(@DataJson) WHERE [key] = N'partnerGeography') > 1
    THROW 55704, N'Invalid partner geography.', 1;
 IF @Geo IS NOT NULL
 BEGIN
    IF (SELECT COUNT(*) FROM OPENJSON(@Geo) WHERE [key] = N'scope' AND [type] = 2 AND [value] IN (N'0',N'1',N'2')) <> 1
       OR (SELECT COUNT(*) FROM OPENJSON(@Geo) WHERE [key] = N'countryIds' AND [type] = 4) <> 1
       OR (SELECT COUNT(*) FROM OPENJSON(@Geo) WHERE [key] = N'regionCodes' AND [type] = 4) <> 1
       OR EXISTS(SELECT [key] FROM OPENJSON(@Geo) GROUP BY [key] HAVING COUNT(*) > 1)
       THROW 55704, N'Invalid partner geography shape.', 1;
    DECLARE @Scope INT = CONVERT(INT, JSON_VALUE(@Geo, '$.scope'));
    DECLARE @CountryCount INT = (SELECT COUNT(*) FROM OPENJSON(@Geo, '$.countryIds')),
            @RegionCount INT = (SELECT COUNT(*) FROM OPENJSON(@Geo, '$.regionCodes'));
    IF @CountryCount > 249 OR @RegionCount > 7 OR (@Scope = 2 AND @CountryCount + @RegionCount = 0)
       OR (@Scope <> 2 AND @CountryCount + @RegionCount <> 0)
       OR EXISTS(SELECT 1 FROM OPENJSON(@Geo, '$.countryIds') j
          WHERE j.[type] <> 2 OR NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_Countries c
             WHERE c.Id = TRY_CONVERT(INT, j.[value]) AND c.IsActive = 1
               AND j.[value] = CONVERT(NVARCHAR(10), c.Id)))
       OR EXISTS(SELECT [value] FROM OPENJSON(@Geo, '$.countryIds') GROUP BY [value] HAVING COUNT(*) > 1)
       OR EXISTS(SELECT 1 FROM OPENJSON(@Geo, '$.regionCodes') j
          WHERE j.[type] <> 1 OR NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_PartnerGeographyCountries() g
             WHERE g.RegionCode = j.[value] COLLATE Latin1_General_100_BIN2))
       OR EXISTS(SELECT [value] FROM OPENJSON(@Geo, '$.regionCodes') GROUP BY [value] HAVING COUNT(*) > 1)
       OR (@RegionCount > 0 AND ISNULL(JSON_VALUE(@Geo, '$.catalogVersion'), N'') COLLATE Latin1_General_100_BIN2 <> N'partner-geography-2026-09-12')
       THROW 55704, N'Invalid or obsolete partner geography.', 1;
    SET @Geo = JSON_MODIFY(@Geo, '$.catalogVersion', N'partner-geography-2026-09-12');
    SET @DataJson = JSON_MODIFY(@DataJson, '$.partnerGeography', JSON_QUERY(@Geo));
 END;
 DECLARE @Actor BIGINT, @Id BIGINT, @CurrentVersion INT, @PreviousVersion BINARY(8), @ResultVersion BINARY(8), @Replay BIT = 0;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.FundingPlatform_usp_AdminActor_Lock @UserPublicId, @Actor OUTPUT;
  SELECT @Id = Id, @CurrentVersion = ContentVersion FROM dbo.FundingPlatform_FundingOpportunities WITH(UPDLOCK, HOLDLOCK)
   WHERE PublicId = @OpportunityPublicId AND IsActive = 1;
  IF @Id IS NULL THROW 55701, N'Opportunity not available.', 1;
  DECLARE @PreviousHash BINARY(32), @PreviousId BIGINT;
  SELECT @PreviousHash = RequestHash, @PreviousId = FundingOpportunityId, @ResultVersion = ResultVersion
    FROM dbo.FundingPlatform_FundingDiscoveryReviews WITH(UPDLOCK, HOLDLOCK) WHERE ActorUserId = @Actor AND KeyHash = @KeyHash;
  IF @PreviousHash IS NOT NULL
  BEGIN
    IF @PreviousHash <> @RequestHash OR @PreviousId <> @Id THROW 55703, N'Command key conflict.', 1;
    SET @Replay = 1;
  END
  ELSE
  BEGIN
    IF @CurrentVersion <> @ContentVersion THROW 55702, N'Opportunity content changed.', 1;
    SELECT @PreviousVersion = RowVersion FROM dbo.FundingPlatform_FundingDiscovery WITH(UPDLOCK, HOLDLOCK) WHERE FundingOpportunityId = @Id;
    IF (@ExpectedVersion IS NULL AND @PreviousVersion IS NOT NULL) OR (@ExpectedVersion IS NOT NULL AND (@PreviousVersion IS NULL OR @PreviousVersion <> @ExpectedVersion))
       THROW 55702, N'Classification changed.', 1;
    DECLARE @Evidence NVARCHAR(2000) = JSON_VALUE(@DataJson, '$.evidenceUrl');
    IF @Evidence NOT LIKE N'https://%' OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunitySourceLinks WHERE FundingOpportunityId = @Id AND IsActive = 1 AND SourceUrl = @Evidence
        UNION ALL SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE Id = @Id AND ApplicationUrl = @Evidence)
       THROW 55704, N'Evidence must be an existing opportunity source.', 1;
    IF @Geo IS NULL
    BEGIN
       DECLARE @PreviousGeo NVARCHAR(MAX);
       SELECT @PreviousGeo = JSON_QUERY(DataJson, '$.partnerGeography')
       FROM dbo.FundingPlatform_FundingDiscovery WHERE FundingOpportunityId = @Id AND ContentVersion = @ContentVersion;
       SET @DataJson = JSON_MODIFY(@DataJson, '$.partnerGeography', JSON_QUERY(@PreviousGeo));
    END;
    IF @PreviousVersion IS NULL
       INSERT dbo.FundingPlatform_FundingDiscovery(FundingOpportunityId, ContentVersion, DataJson, ReviewedByUserId, ReviewedAtUtc)
       VALUES(@Id, @ContentVersion, @DataJson, @Actor, SYSUTCDATETIME());
    ELSE UPDATE dbo.FundingPlatform_FundingDiscovery SET ContentVersion = @ContentVersion, DataJson = @DataJson,
       ReviewedByUserId = @Actor, ReviewedAtUtc = SYSUTCDATETIME() WHERE FundingOpportunityId = @Id;
    SELECT @ResultVersion = RowVersion FROM dbo.FundingPlatform_FundingDiscovery WHERE FundingOpportunityId = @Id;
    INSERT dbo.FundingPlatform_FundingDiscoveryReviews(FundingOpportunityId, ActorUserId, ContentVersion, DataJson, KeyHash, RequestHash, ResultVersion)
       VALUES(@Id, @Actor, @ContentVersion, @DataJson, @KeyHash, @RequestHash, @ResultVersion);
  END;
  COMMIT TRANSACTION;
  SELECT (SELECT @OpportunityPublicId AS entityId, N'"' + CONVERT(NVARCHAR(16), @ResultVersion, 2) + N'"' AS eTag, @Replay AS wasReplay FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS Json;
 END TRY
 BEGIN CATCH
  IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
  THROW;
 END CATCH;
END;
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
    JSON_QUERY(metadata.DataJson, '$.partnerGeography') AS partnerGeography,
    CONVERT(BIT, CASE WHEN EXISTS(
       SELECT 1 FROM OPENJSON(metadata.DataJson, '$.partnerGeography.countryIds') j
       WHERE NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_Countries c WHERE c.Id = TRY_CONVERT(INT, j.[value]) AND c.IsActive = 1)
    ) THEN 0 ELSE 1 END) AS partnerGeographyValid,
    JSON_QUERY(COALESCE((SELECT N'[' + STRING_AGG(CONVERT(NVARCHAR(MAX), c.Id), N',') + N']'
       FROM dbo.FundingPlatform_Countries c
       WHERE c.IsActive = 1 AND (
          EXISTS(SELECT 1 FROM OPENJSON(metadata.DataJson, '$.partnerGeography.countryIds') j WHERE TRY_CONVERT(INT, j.[value]) = c.Id)
          OR EXISTS(SELECT 1 FROM OPENJSON(metadata.DataJson, '$.partnerGeography.regionCodes') j
             INNER JOIN dbo.FundingPlatform_ifn_PartnerGeographyCountries() g
                ON g.RegionCode = j.[value] COLLATE Latin1_General_100_BIN2 WHERE g.CountryId = c.Id)
       )), N'[]')) AS eligiblePartnerCountryIds,
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
