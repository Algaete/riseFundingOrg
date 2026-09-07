/* FundingPlatform import hotfix - preserve full eligibility while bounding the
   editorial target-organizations projection to its NVARCHAR(2000) contract.
   Requires migrations 001-029. Existing migration checksums remain immutable. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @ProcedureObjectId INT =
    OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunity_StageExternal_Pre016', N'P');
IF @ProcedureObjectId IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunity_StageExternal', N'P') IS NULL
    THROW 55101, N'External staging bounds require migrations 001-029.', 1;

DECLARE @Definition NVARCHAR(MAX) = OBJECT_DEFINITION(@ProcedureObjectId);
DECLARE @OldInsertToken NVARCHAR(200) =
    N'@EligibilityDescription, @RequiresCofunding, @CofundingPercentage,';
DECLARE @NewInsertToken NVARCHAR(200) =
    N'LEFT(@EligibilityDescription, 2000), @RequiresCofunding, @CofundingPercentage,';
DECLARE @OldUpdateToken NVARCHAR(200) =
    N'TargetOrganizationsDescription = @EligibilityDescription,';
DECLARE @NewUpdateToken NVARCHAR(200) =
    N'TargetOrganizationsDescription = LEFT(@EligibilityDescription, 2000),';

DECLARE @OldInsertCount INT = CASE WHEN @Definition IS NULL THEN -1 ELSE
    (DATALENGTH(@Definition) - DATALENGTH(REPLACE(@Definition, @OldInsertToken, N''))) /
    DATALENGTH(@OldInsertToken) END;
DECLARE @NewInsertCount INT = CASE WHEN @Definition IS NULL THEN -1 ELSE
    (DATALENGTH(@Definition) - DATALENGTH(REPLACE(@Definition, @NewInsertToken, N''))) /
    DATALENGTH(@NewInsertToken) END;
DECLARE @OldUpdateCount INT = CASE WHEN @Definition IS NULL THEN -1 ELSE
    (DATALENGTH(@Definition) - DATALENGTH(REPLACE(@Definition, @OldUpdateToken, N''))) /
    DATALENGTH(@OldUpdateToken) END;
DECLARE @NewUpdateCount INT = CASE WHEN @Definition IS NULL THEN -1 ELSE
    (DATALENGTH(@Definition) - DATALENGTH(REPLACE(@Definition, @NewUpdateToken, N''))) /
    DATALENGTH(@NewUpdateToken) END;

IF NOT
   (((@OldInsertCount = 1 AND @NewInsertCount = 0)
      OR (@OldInsertCount = 0 AND @NewInsertCount = 1))
    AND
    ((@OldUpdateCount = 1 AND @NewUpdateCount = 0)
      OR (@OldUpdateCount = 0 AND @NewUpdateCount = 1)))
    THROW 55102, N'The internal external-staging procedure definition has drifted.', 1;

IF @OldInsertCount = 1 AND @OldUpdateCount = 1
BEGIN
    SET @Definition = REPLACE(@Definition, @OldInsertToken, @NewInsertToken);
    SET @Definition = REPLACE(@Definition, @OldUpdateToken, @NewUpdateToken);

    /* sp_rename intentionally left the original module header text behind in
       migration 016. Rebuild only that header and preserve the verified body. */
    DECLARE @FirstParameterPosition INT =
        CHARINDEX(N'@FundingSourceId', @Definition COLLATE Latin1_General_100_BIN2);
    DECLARE @Header NVARCHAR(400) = CASE
        WHEN @FirstParameterPosition > 1
        THEN LEFT(@Definition, @FirstParameterPosition - 1)
        ELSE N'' END;
    IF @FirstParameterPosition NOT BETWEEN 50 AND 300
       OR CHARINDEX(N'PROCEDURE', UPPER(@Header)) = 0
       OR CHARINDEX(N';', @Header) > 0
        THROW 55103, N'The internal external-staging procedure header is unsafe.', 1;

    SET @Definition =
        N'CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_StageExternal_Pre016' +
        NCHAR(10) + N'    ' + SUBSTRING(@Definition, @FirstParameterPosition, 2147483647);
    EXEC sys.sp_executesql @Definition;
END;

IF OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunity_StageExternal_Pre016', N'P')
       <> @ProcedureObjectId
    THROW 55104, N'The internal external-staging procedure identity changed.', 1;

SET @Definition = OBJECT_DEFINITION(@ProcedureObjectId);
SET @OldInsertCount =
    (DATALENGTH(@Definition) - DATALENGTH(REPLACE(@Definition, @OldInsertToken, N''))) /
    DATALENGTH(@OldInsertToken);
SET @NewInsertCount =
    (DATALENGTH(@Definition) - DATALENGTH(REPLACE(@Definition, @NewInsertToken, N''))) /
    DATALENGTH(@NewInsertToken);
SET @OldUpdateCount =
    (DATALENGTH(@Definition) - DATALENGTH(REPLACE(@Definition, @OldUpdateToken, N''))) /
    DATALENGTH(@OldUpdateToken);
SET @NewUpdateCount =
    (DATALENGTH(@Definition) - DATALENGTH(REPLACE(@Definition, @NewUpdateToken, N''))) /
    DATALENGTH(@NewUpdateToken);

IF @Definition IS NULL
   OR @OldInsertCount <> 0 OR @NewInsertCount <> 1
   OR @OldUpdateCount <> 0 OR @NewUpdateCount <> 1
    THROW 55105, N'The external-staging bounds patch did not persist exactly once.', 1;
GO
