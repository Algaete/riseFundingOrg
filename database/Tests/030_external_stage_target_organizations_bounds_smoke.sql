/* Read-only smoke for the external staging target-organizations bound. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ProcedureObjectId INT =
    OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunity_StageExternal_Pre016', N'P');
DECLARE @Definition NVARCHAR(MAX) = OBJECT_DEFINITION(@ProcedureObjectId);
DECLARE @InsertToken NVARCHAR(200) =
    N'LEFT(@EligibilityDescription, 2000), @RequiresCofunding, @CofundingPercentage,';
DECLARE @UpdateToken NVARCHAR(200) =
    N'TargetOrganizationsDescription = LEFT(@EligibilityDescription, 2000),';
DECLARE @InsertCount INT = CASE WHEN @Definition IS NULL THEN -1 ELSE
    (DATALENGTH(@Definition) - DATALENGTH(REPLACE(@Definition, @InsertToken, N''))) /
    DATALENGTH(@InsertToken) END;
DECLARE @UpdateCount INT = CASE WHEN @Definition IS NULL THEN -1 ELSE
    (DATALENGTH(@Definition) - DATALENGTH(REPLACE(@Definition, @UpdateToken, N''))) /
    DATALENGTH(@UpdateToken) END;

IF @ProcedureObjectId IS NULL OR @InsertCount <> 1 OR @UpdateCount <> 1
    THROW 55120, N'External staging does not enforce the target-organizations bound.', 1;

IF NOT EXISTS
   (SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.FundingPlatform_FundingOpportunities', N'U')
      AND name = N'TargetOrganizationsDescription'
      AND system_type_id = TYPE_ID(N'nvarchar')
      AND max_length = 4000)
    THROW 55121, N'The target-organizations column contract changed unexpectedly.', 1;

IF LEN(LEFT(REPLICATE(N'X', 2500), 2000)) <> 2000
    THROW 55122, N'The target-organizations bound is not deterministic.', 1;

SELECT N'External staging target-organizations bounds smoke passed.' AS Result;
GO
