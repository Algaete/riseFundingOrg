/* Read-only map deployment check. Privacy fixtures are also covered by smoke 040.
   This checks deployed guards and executes both result sets; it does not write fixtures. */
SET NOCOUNT ON;
DECLARE @Definition NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMap_Search'));
IF @Definition IS NULL
   OR @Definition NOT LIKE N'%INNER JOIN dbo.FundingPlatform_ifn_ProjectMarketplaceReady()%'
   OR CHARINDEX(N'''$.locationVisibility'') = N''2''', @Definition) = 0
   OR @Definition NOT LIKE N'%ROUND(coordinates.Latitude, 2)%'
   OR @Definition NOT LIKE N'%ROUND(coordinates.Longitude, 2)%'
   OR @Definition NOT LIKE N'%WHERE Latitude IS NOT NULL AND Longitude IS NOT NULL%'
    THROW 55420, N'Public map publication or location privacy guards are missing.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.database_permissions
    WHERE grantee_principal_id = DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole')
      AND class = 1 AND major_id = OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMap_Search')
      AND permission_name = N'EXECUTE' AND state = 'G')
    THROW 55421, N'Public map runtime permission is missing.', 1;
SET XACT_ABORT OFF;
BEGIN TRY
    EXEC dbo.FundingPlatform_usp_ProjectMap_Search @PageSize = 201;
    THROW 55422, N'Unbounded map page was accepted.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 52102 THROW;
END CATCH;
SET XACT_ABORT ON;
IF XACT_STATE() = -1 THROW 55423, N'Map validation damaged the caller transaction.', 1;
EXEC dbo.FundingPlatform_usp_ProjectMap_Search @PageSize = 1;
EXEC dbo.FundingPlatform_usp_ProjectMap_Search @CountryId = 152, @ProjectStage = 0, @PageSize = 1;
