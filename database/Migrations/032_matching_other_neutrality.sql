/* FundingPlatform - OTHER taxonomy choices are neutral in deterministic matching.
   Requires migrations 001-031. Existing runs, matches and rule results remain
   immutable and auditable under deterministic-sql-v1. New calculations use a
   separately versioned profile, engine and rule handlers.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF OBJECT_ID(N'dbo.FundingPlatform_MatchingProfiles', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_MatchingRules', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_MatchingRuleWeights', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ProjectMatchingRuns', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMatchingRun_Create', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_tr_MatchingProfiles_Immutable', N'TR') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_tr_MatchingRules_Immutable', N'TR') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_tr_MatchingRuleWeights_Immutable', N'TR') IS NULL
    THROW 55201, N'Matching OTHER neutrality requires migrations 001-031.', 1;

IF NOT EXISTS
   (SELECT 1 FROM dbo.FundingPlatform_FundingCategories
    WHERE Id = 16 AND Code = N'OTHER' AND IsActive = 1)
   OR NOT EXISTS
   (SELECT 1 FROM dbo.FundingPlatform_BeneficiaryTypes
    WHERE Id = 12 AND Code = N'OTHER' AND IsActive = 1)
   OR NOT EXISTS
   (SELECT 1 FROM dbo.FundingPlatform_ProjectTypes
    WHERE Id = 13 AND Code = N'OTHER' AND IsActive = 1)
    THROW 55202, N'Migration 031 OTHER catalog identities are unavailable.', 1;

DECLARE @RuleDefinitions TABLE
(
    Code NVARCHAR(100) NOT NULL PRIMARY KEY,
    Name NVARCHAR(150) NOT NULL,
    IsHardGate BIT NOT NULL,
    Weight DECIMAL(5,2) NOT NULL
);

INSERT INTO @RuleDefinitions (Code, Name, IsHardGate, Weight)
VALUES
    (N'geography', N'Geography', 1, CONVERT(DECIMAL(5,2), 20)),
    (N'organization_type', N'Organization type', 1, CONVERT(DECIMAL(5,2), 15)),
    (N'legal_entity', N'Legal entity', 1, CONVERT(DECIMAL(5,2), 15)),
    (N'operating_years', N'Operating years', 1, CONVERT(DECIMAL(5,2), 10)),
    (N'prior_experience', N'Prior funding experience', 1, CONVERT(DECIMAL(5,2), 10)),
    (N'categories', N'Funding categories', 0, CONVERT(DECIMAL(5,2), 10)),
    (N'beneficiaries', N'Beneficiary types', 0, CONVERT(DECIMAL(5,2), 5)),
    (N'project_type', N'Project type', 0, CONVERT(DECIMAL(5,2), 5)),
    (N'amount', N'Funding amount', 0, CONVERT(DECIMAL(5,2), 10));

DECLARE @LegacyProfileId INT =
    (SELECT Id
     FROM dbo.FundingPlatform_MatchingProfiles
     WHERE Code = N'deterministic-project-v1' AND Version = 1
       AND EngineVersion = N'deterministic-sql-v1'
       AND UnknownPolicy = 1 AND Status = 2);

IF @LegacyProfileId IS NULL
   OR (SELECT COUNT_BIG(1)
       FROM dbo.FundingPlatform_MatchingRuleWeights AS weights
       INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
           ON rules.Id = weights.MatchingRuleId
       INNER JOIN @RuleDefinitions AS expected
           ON expected.Code = rules.Code
          AND expected.Name = rules.Name
          AND expected.IsHardGate = rules.IsHardGate
          AND expected.Weight = weights.Weight
       WHERE weights.MatchingProfileId = @LegacyProfileId
         AND rules.HandlerVersion = N'v1'
         AND rules.IsActive = 1) <> 9
   OR (SELECT COUNT_BIG(1)
       FROM dbo.FundingPlatform_MatchingRuleWeights
       WHERE MatchingProfileId = @LegacyProfileId) <> 9
   OR (SELECT SUM(Weight)
       FROM dbo.FundingPlatform_MatchingRuleWeights
       WHERE MatchingProfileId = @LegacyProfileId) <> 100
    THROW 55203, N'The immutable deterministic v1 profile has drifted.', 1;

/* A handler version identifies the executable rule semantics in historical
   results. Version all nine handlers together so a v2 result never points at a
   v1 handler after the calculation procedure changes. */
IF EXISTS
(
    SELECT 1
    FROM @RuleDefinitions AS expected
    INNER JOIN dbo.FundingPlatform_MatchingRules AS existing
        ON existing.Code = expected.Code AND existing.HandlerVersion = N'v2'
    WHERE existing.Name <> expected.Name
       OR existing.IsHardGate <> expected.IsHardGate
       OR existing.IsActive <> 1
)
    THROW 55204, N'A deterministic v2 matching rule has drifted.', 1;

DECLARE @PublishedAtUtc DATETIME2(3) = SYSUTCDATETIME();
INSERT INTO dbo.FundingPlatform_MatchingRules
    (Code, Name, HandlerVersion, IsHardGate, IsActive, CreatedAtUtc)
SELECT expected.Code, expected.Name, N'v2', expected.IsHardGate, 1, @PublishedAtUtc
FROM @RuleDefinitions AS expected
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_MatchingRules AS existing
    WHERE existing.Code = expected.Code AND existing.HandlerVersion = N'v2'
);

IF (SELECT COUNT_BIG(1)
    FROM dbo.FundingPlatform_MatchingRules AS rules
    INNER JOIN @RuleDefinitions AS expected
        ON expected.Code = rules.Code
       AND expected.Name = rules.Name
       AND expected.IsHardGate = rules.IsHardGate
    WHERE rules.HandlerVersion = N'v2' AND rules.IsActive = 1) <> 9
    THROW 55205, N'The deterministic v2 matching rule set is incomplete.', 1;

DECLARE @NewProfileId INT =
    (SELECT Id
     FROM dbo.FundingPlatform_MatchingProfiles
     WHERE Code = N'deterministic-project-v1' AND Version = 2);

IF @NewProfileId IS NOT NULL
   AND NOT EXISTS
       (SELECT 1
        FROM dbo.FundingPlatform_MatchingProfiles
        WHERE Id = @NewProfileId
          AND EngineVersion = N'deterministic-sql-v2'
          AND UnknownPolicy = 1 AND Status = 2)
    THROW 55206, N'The deterministic v2 matching profile has drifted.', 1;

IF @NewProfileId IS NULL
BEGIN
    INSERT INTO dbo.FundingPlatform_MatchingProfiles
        (Code, Version, EngineVersion, UnknownPolicy, Status, IsActive,
         PublishedAtUtc, CreatedAtUtc)
    VALUES
        (N'deterministic-project-v1', 2, N'deterministic-sql-v2', 1, 2, 0,
         @PublishedAtUtc, @PublishedAtUtc);
    SET @NewProfileId = SCOPE_IDENTITY();
END;

DECLARE @ExistingWeightCount INT =
    (SELECT COUNT(1)
     FROM dbo.FundingPlatform_MatchingRuleWeights
     WHERE MatchingProfileId = @NewProfileId);
IF @ExistingWeightCount NOT IN (0, 9)
    THROW 55207, N'The deterministic v2 matching profile has partial weights.', 1;

IF @ExistingWeightCount = 0
BEGIN
    IF EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_MatchingProfiles
        WHERE Id = @NewProfileId AND IsActive = 1)
       OR EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ProjectMatchingRuns
        WHERE MatchingProfileId = @NewProfileId)
        THROW 55208, N'Weights cannot be attached to an active or used v2 profile.', 1;

    INSERT INTO dbo.FundingPlatform_MatchingRuleWeights
        (MatchingProfileId, MatchingRuleId, Weight, ParametersJson)
    SELECT @NewProfileId, rules.Id, expected.Weight,
           N'{"unknownPolicy":"zero-no-renormalization","otherPolicy":"neutral-excluded"}'
    FROM @RuleDefinitions AS expected
    INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
        ON rules.Code = expected.Code AND rules.HandlerVersion = N'v2';
END;

IF (SELECT COUNT_BIG(1)
    FROM dbo.FundingPlatform_MatchingRuleWeights AS weights
    INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
        ON rules.Id = weights.MatchingRuleId
    INNER JOIN @RuleDefinitions AS expected
        ON expected.Code = rules.Code
       AND expected.Name = rules.Name
       AND expected.IsHardGate = rules.IsHardGate
       AND expected.Weight = weights.Weight
    WHERE weights.MatchingProfileId = @NewProfileId
      AND rules.HandlerVersion = N'v2'
      AND rules.IsActive = 1
      AND weights.ParametersJson =
          N'{"unknownPolicy":"zero-no-renormalization","otherPolicy":"neutral-excluded"}') <> 9
   OR (SELECT COUNT_BIG(1)
       FROM dbo.FundingPlatform_MatchingRuleWeights
       WHERE MatchingProfileId = @NewProfileId) <> 9
   OR (SELECT SUM(Weight)
       FROM dbo.FundingPlatform_MatchingRuleWeights
       WHERE MatchingProfileId = @NewProfileId) <> 100
    THROW 55209, N'The deterministic v2 matching profile is incomplete.', 1;

DECLARE @ActiveProfileId INT =
    (SELECT Id FROM dbo.FundingPlatform_MatchingProfiles WHERE IsActive = 1);
IF @ActiveProfileId IS NULL OR @ActiveProfileId NOT IN (@LegacyProfileId, @NewProfileId)
    THROW 55210, N'An unexpected deterministic matching profile is active.', 1;

/* Patch only the recognized v1 definition or an already-correct v2 definition.
   Filtering while materializing both project and opportunity snapshots makes
   OTHER absent from every taxonomy count and every intersection downstream. */
DECLARE @ProcedureObjectId INT =
    OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMatchingRun_Create', N'P');
DECLARE @Definition NVARCHAR(MAX) = OBJECT_DEFINITION(@ProcedureObjectId);
IF @Definition IS NULL
    THROW 55211, N'The deterministic matching procedure definition is unavailable.', 1;

DECLARE @ProcedurePatches TABLE
(
    PatchOrder TINYINT NOT NULL PRIMARY KEY,
    OldToken NVARCHAR(MAX) NOT NULL,
    NewToken NVARCHAR(MAX) NOT NULL,
    ExpectedCount INT NOT NULL
);

INSERT INTO @ProcedurePatches (PatchOrder, OldToken, NewToken, ExpectedCount)
VALUES
    (1,
     N'rules.HandlerVersion = N''v1''',
     N'rules.HandlerVersion = N''v2''',
     3),
    (2,
     N'FROM dbo.FundingPlatform_FundingOpportunityCategories AS links WITH (HOLDLOCK)
        INNER JOIN #Candidates AS candidates',
     N'FROM dbo.FundingPlatform_FundingOpportunityCategories AS links WITH (HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_FundingCategories AS categoryCatalog
            ON categoryCatalog.Id = links.FundingCategoryId
           AND categoryCatalog.Code <> N''OTHER''
        INNER JOIN #Candidates AS candidates',
     1),
    (3,
     N'FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes AS links WITH (HOLDLOCK)
        INNER JOIN #Candidates AS candidates',
     N'FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes AS links WITH (HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_BeneficiaryTypes AS beneficiaryCatalog
            ON beneficiaryCatalog.Id = links.BeneficiaryTypeId
           AND beneficiaryCatalog.Code <> N''OTHER''
        INNER JOIN #Candidates AS candidates',
     1),
    (4,
     N'FROM dbo.FundingPlatform_FundingOpportunityProjectTypes AS links WITH (HOLDLOCK)
        INNER JOIN #Candidates AS candidates',
     N'FROM dbo.FundingPlatform_FundingOpportunityProjectTypes AS links WITH (HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_ProjectTypes AS projectTypeCatalog
            ON projectTypeCatalog.Id = links.ProjectTypeId
           AND projectTypeCatalog.Code <> N''OTHER''
        INNER JOIN #Candidates AS candidates',
     1),
    (5,
     N'FROM dbo.FundingPlatform_ProjectCategories AS links WITH (HOLDLOCK)
        WHERE links.ProjectId = @ProjectId;',
     N'FROM dbo.FundingPlatform_ProjectCategories AS links WITH (HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_FundingCategories AS categoryCatalog
            ON categoryCatalog.Id = links.FundingCategoryId
           AND categoryCatalog.Code <> N''OTHER''
        WHERE links.ProjectId = @ProjectId;',
     1),
    (6,
     N'FROM dbo.FundingPlatform_ProjectBeneficiaryTypes AS links WITH (HOLDLOCK)
        WHERE links.ProjectId = @ProjectId;',
     N'FROM dbo.FundingPlatform_ProjectBeneficiaryTypes AS links WITH (HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_BeneficiaryTypes AS beneficiaryCatalog
            ON beneficiaryCatalog.Id = links.BeneficiaryTypeId
           AND beneficiaryCatalog.Code <> N''OTHER''
        WHERE links.ProjectId = @ProjectId;',
     1),
    (7,
     N'FROM dbo.FundingPlatform_ProjectProjectTypes AS links WITH (HOLDLOCK)
        WHERE links.ProjectId = @ProjectId;',
     N'FROM dbo.FundingPlatform_ProjectProjectTypes AS links WITH (HOLDLOCK)
        INNER JOIN dbo.FundingPlatform_ProjectTypes AS projectTypeCatalog
            ON projectTypeCatalog.Id = links.ProjectTypeId
           AND projectTypeCatalog.Code <> N''OTHER''
        WHERE links.ProjectId = @ProjectId;',
     1);

DECLARE @OldToken NVARCHAR(MAX), @NewToken NVARCHAR(MAX), @ExpectedCount INT;
DECLARE @OldCount INT, @NewCount INT, @DefinitionChanged BIT = 0;
DECLARE PatchCursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT OldToken, NewToken, ExpectedCount
    FROM @ProcedurePatches
    ORDER BY PatchOrder;

OPEN PatchCursor;
FETCH NEXT FROM PatchCursor INTO @OldToken, @NewToken, @ExpectedCount;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @OldCount =
        (DATALENGTH(@Definition) - DATALENGTH(REPLACE(@Definition, @OldToken, N''))) /
        DATALENGTH(@OldToken);
    SET @NewCount =
        (DATALENGTH(@Definition) - DATALENGTH(REPLACE(@Definition, @NewToken, N''))) /
        DATALENGTH(@NewToken);

    IF NOT ((@OldCount = @ExpectedCount AND @NewCount = 0)
            OR (@OldCount = 0 AND @NewCount = @ExpectedCount))
        THROW 55212, N'The deterministic matching procedure definition has drifted.', 1;

    IF @OldCount = @ExpectedCount
    BEGIN
        SET @Definition = REPLACE(@Definition, @OldToken, @NewToken);
        SET @DefinitionChanged = 1;
    END;

    FETCH NEXT FROM PatchCursor INTO @OldToken, @NewToken, @ExpectedCount;
END;
CLOSE PatchCursor;
DEALLOCATE PatchCursor;

IF @DefinitionChanged = 1
BEGIN
    DECLARE @LeadingWhitespaceLength INT = 0;
    WHILE UNICODE(SUBSTRING(@Definition, @LeadingWhitespaceLength + 1, 1))
          IN (9, 10, 13, 32)
        SET @LeadingWhitespaceLength += 1;
    DECLARE @TrimmedDefinition NVARCHAR(MAX) =
        SUBSTRING(@Definition, @LeadingWhitespaceLength + 1, 2147483647);
    DECLARE @ProcedureKeywordPosition INT =
        CHARINDEX(N'PROCEDURE', UPPER(@TrimmedDefinition));
    DECLARE @DdlPrefixRaw NVARCHAR(100) = CASE
        WHEN @ProcedureKeywordPosition BETWEEN 2 AND 40
            THEN RTRIM(LEFT(@TrimmedDefinition, @ProcedureKeywordPosition - 1))
        ELSE N''
    END;
    DECLARE @DdlPrefix NVARCHAR(100) = UPPER(REPLACE(REPLACE(REPLACE(REPLACE(
        @DdlPrefixRaw,
        N' ', N''), NCHAR(9), N''), NCHAR(10), N''), NCHAR(13), N''));
    IF @ProcedureKeywordPosition NOT BETWEEN 2 AND 40
       OR @DdlPrefix NOT IN (N'CREATE', N'CREATEORALTER', N'ALTER')
        THROW 55213, N'The deterministic matching procedure has an unsafe DDL header.', 1;

    SET @TrimmedDefinition = N'CREATE OR ALTER PROCEDURE' + SUBSTRING(
        @TrimmedDefinition,
        @ProcedureKeywordPosition + LEN(N'PROCEDURE'),
        2147483647);
    SET @Definition = LEFT(@Definition, @LeadingWhitespaceLength) + @TrimmedDefinition;
    EXEC sys.sp_executesql @Definition;
END;

SET @Definition = OBJECT_DEFINITION(@ProcedureObjectId);
IF @Definition IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMatchingRun_Create', N'P')
      <> @ProcedureObjectId
   OR NOT EXISTS
      (SELECT 1
       FROM sys.sql_modules
       WHERE object_id = @ProcedureObjectId
         AND uses_ansi_nulls = 1
         AND uses_quoted_identifier = 1)
    THROW 55214, N'The deterministic matching procedure did not preserve its identity.', 1;

DECLARE VerificationCursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT OldToken, NewToken, ExpectedCount
    FROM @ProcedurePatches
    ORDER BY PatchOrder;

OPEN VerificationCursor;
FETCH NEXT FROM VerificationCursor INTO @OldToken, @NewToken, @ExpectedCount;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @OldCount =
        (DATALENGTH(@Definition) - DATALENGTH(REPLACE(@Definition, @OldToken, N''))) /
        DATALENGTH(@OldToken);
    SET @NewCount =
        (DATALENGTH(@Definition) - DATALENGTH(REPLACE(@Definition, @NewToken, N''))) /
        DATALENGTH(@NewToken);
    IF @OldCount <> 0 OR @NewCount <> @ExpectedCount
        THROW 55215, N'The deterministic matching v2 procedure patch is incomplete.', 1;

    FETCH NEXT FROM VerificationCursor INTO @OldToken, @NewToken, @ExpectedCount;
END;
CLOSE VerificationCursor;
DEALLOCATE VerificationCursor;

/* Switching the active profile invalidates v1 run summaries through the
   existing IsCurrent calculation. Stored v1 runs/results are never rewritten. */
UPDATE dbo.FundingPlatform_MatchingProfiles
SET IsActive = 0
WHERE Id = @LegacyProfileId AND IsActive = 1;

UPDATE dbo.FundingPlatform_MatchingProfiles
SET IsActive = 1
WHERE Id = @NewProfileId AND IsActive = 0;

IF (SELECT COUNT_BIG(1)
    FROM dbo.FundingPlatform_MatchingProfiles
    WHERE IsActive = 1 AND Id = @NewProfileId
      AND Version = 2 AND EngineVersion = N'deterministic-sql-v2') <> 1
   OR EXISTS
      (SELECT 1
       FROM dbo.FundingPlatform_MatchingProfiles
       WHERE IsActive = 1 AND Id <> @NewProfileId)
    THROW 55216, N'The deterministic v2 matching profile was not activated exclusively.', 1;
