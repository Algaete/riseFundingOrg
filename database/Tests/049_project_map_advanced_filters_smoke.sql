/* Read-only deployment smoke. Inspects predicates and exercises the procedure's two result sets.
   Does not claim fixture/result correctness: acceptance additionally requires comparing known
   public/private project fixtures through the API after deployment (see PROJECT-MAP.md). */
SET NOCOUNT ON;
DECLARE @Definition NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMap_Search'));
IF @Definition IS NULL
   OR CHARINDEX(N'INNER JOIN dbo.FundingPlatform_ifn_ProjectMarketplaceReady()', @Definition) = 0
   OR CHARINDEX(N'''$.locationVisibility'') = N''2''', @Definition) = 0
   OR CHARINDEX(N'ROUND(coordinates.Latitude, 2)', @Definition) = 0
   OR CHARINDEX(N'ROUND(coordinates.Longitude, 2)', @Definition) = 0
   OR CHARINDEX(N'projects.FundingGap >= @MinimumFundingGap', @Definition) = 0
   OR CHARINDEX(N'projects.FundingGap <= @MaximumFundingGap', @Definition) = 0
   OR CHARINDEX(N'projects.Currency = @Currency', @Definition) = 0
   OR CHARINDEX(N'organizations.OrganizationTypeId = @OrganizationTypeId', @Definition) = 0
   OR CHARINDEX(N'@SelectedProjects WHERE Id = projects.PublicId', @Definition) = 0
   OR CHARINDEX(N'@SeekingFunding = 0 OR projects.FundingGap > 0', @Definition) = 0
   OR CHARINDEX(N'''$.soughtPartners''', @Definition) = 0
   OR CHARINDEX(N'''$.soughtProfessionals''', @Definition) = 0
   OR CHARINDEX(N'''$.seekingConsortium'') = N''true''', @Definition) = 0
   OR CHARINDEX(N'WithoutPublicLocationCount FROM #Visible', @Definition) = 0
    THROW 55890, N'Advanced map predicates or privacy guards are missing.', 1;

DECLARE @Cases TABLE (Id INT IDENTITY PRIMARY KEY, SqlText NVARCHAR(MAX));
INSERT @Cases (SqlText) VALUES
 (N'@OrganizationTypeId = 0'), (N'@MinimumFundingGap = 0'),
 (N'@MinimumFundingGap = -1, @Currency = ''USD'''),
 (N'@MaximumFundingGap = 1000000000000, @Currency = ''USD'''),
 (N'@MinimumFundingGap = 2, @MaximumFundingGap = 1, @Currency = ''USD'''),
 (N'@Currency = ''usd'''), (N'@Currency = ''USD '''), (N'@Currency = ''US1'''),
 (N'@SeekingPartners = NULL'), (N'@ProjectIdsJson = N''[]'''),
 (N'@ProjectIdsJson = N''{}'''), (N'@ProjectIdsJson = N''[null]'''),
 (N'@ProjectIdsJson = N''["invalid"]'''),
 (N'@ProjectIdsJson = N''["00000000-0000-0000-0000-000000000000"]'''),
 (N'@ProjectIdsJson = N''["11111111-1111-1111-1111-111111111111","11111111-1111-1111-1111-111111111111"]''');
DECLARE @Case INT = 1, @Command NVARCHAR(MAX);
SET XACT_ABORT OFF;
WHILE @Case <= (SELECT COUNT(*) FROM @Cases)
BEGIN
    SELECT @Command = N'EXEC dbo.FundingPlatform_usp_ProjectMap_Search ' + SqlText FROM @Cases WHERE Id = @Case;
    BEGIN TRY
        EXEC sys.sp_executesql @Command;
        THROW 55891, N'Invalid advanced map filters were accepted.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> 52102 THROW;
    END CATCH;
    SET @Case += 1;
END;
SET XACT_ABORT ON;
IF XACT_STATE() = -1 THROW 55892, N'Map validation damaged the caller transaction.', 1;

-- Legacy callers, zero bounds, combined predicates, selected IDs and paging must still execute.
EXEC dbo.FundingPlatform_usp_ProjectMap_Search @PageSize = 1;
EXEC dbo.FundingPlatform_usp_ProjectMap_Search @MinimumFundingGap = 0, @MaximumFundingGap = 0, @Currency = 'USD', @PageSize = 1;
EXEC dbo.FundingPlatform_usp_ProjectMap_Search @OrganizationTypeId = 2, @Currency = 'USD',
    @MinimumFundingGap = 0, @MaximumFundingGap = 50000, @SeekingFunding = 1,
    @SeekingPartners = 1, @SeekingProfessionals = 1, @SeekingConsortium = 1, @PageSize = 1;
DECLARE @Ids NVARCHAR(MAX) = N'["' + CONVERT(NVARCHAR(36), NEWID()) + N'"]';
EXEC dbo.FundingPlatform_usp_ProjectMap_Search @ProjectIdsJson = @Ids, @Page = 2, @PageSize = 1;
