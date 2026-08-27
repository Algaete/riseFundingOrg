/* FundingPlatform deployment hotfix - unambiguous SQL LIKE hyphen allowlists.
   Requires migrations 001-028. Existing migration checksums remain immutable. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF OBJECT_ID(N'dbo.FundingPlatform_SemanticConfigurations', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_SemanticEvaluationSets', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_AiProviderGovernancePolicies', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_AiExplanationConfigurations', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_SemanticEvaluationRun_Create', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_SemanticEmbeddingJob_Claim', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_SemanticEvaluationRun_Claim', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_AlertDelivery_Fail', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_OrganizationConnection_Create', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_OrganizationConnection_Action', N'P') IS NULL
    THROW 55001, N'Hyphen allowlist compatibility requires migrations 001-028.', 1;

DECLARE @ConstraintPatches TABLE
(
    TableName SYSNAME NOT NULL PRIMARY KEY,
    ConstraintName SYSNAME NOT NULL UNIQUE,
    ExpectedLowerCount INT NOT NULL,
    ExpectedUpperCount INT NOT NULL
);

INSERT INTO @ConstraintPatches
    (TableName, ConstraintName, ExpectedLowerCount, ExpectedUpperCount)
VALUES
    (N'FundingPlatform_SemanticConfigurations',
     N'FundingPlatform_CK_SemanticConfigurations_Text', 1, 7),
    (N'FundingPlatform_SemanticEvaluationSets',
     N'FundingPlatform_CK_SemanticEvaluationSets_Text', 1, 0),
    (N'FundingPlatform_AiProviderGovernancePolicies',
     N'FundingPlatform_CK_AiProviderGovernancePolicies_Text', 1, 2),
    (N'FundingPlatform_AiExplanationConfigurations',
     N'FundingPlatform_CK_AiExplanationConfigurations_Text', 1, 0);

DECLARE @LegacyLower NVARCHAR(100) = N'%[^a-z0-9._-]%';
DECLARE @SafeLower NVARCHAR(100) = N'%[^-a-z0-9._]%';
DECLARE @LegacyUpper NVARCHAR(100) = N'%[^A-Za-z0-9._-]%';
DECLARE @SafeUpper NVARCHAR(100) = N'%[^-A-Za-z0-9._]%';
DECLARE @TableName SYSNAME, @ConstraintName SYSNAME;
DECLARE @ExpectedLowerCount INT, @ExpectedUpperCount INT;
DECLARE ConstraintCursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT TableName, ConstraintName, ExpectedLowerCount, ExpectedUpperCount
    FROM @ConstraintPatches
    ORDER BY TableName;

OPEN ConstraintCursor;
FETCH NEXT FROM ConstraintCursor
    INTO @TableName, @ConstraintName, @ExpectedLowerCount, @ExpectedUpperCount;
WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @TableObjectId INT = OBJECT_ID(N'dbo.' + @TableName, N'U');
    DECLARE @ConstraintDefinition NVARCHAR(MAX), @ConstraintDisabled BIT,
            @ConstraintNotTrusted BIT;
    SELECT @ConstraintDefinition = definition,
           @ConstraintDisabled = is_disabled,
           @ConstraintNotTrusted = is_not_trusted
    FROM sys.check_constraints
    WHERE name = @ConstraintName AND parent_object_id = @TableObjectId;

    IF @ConstraintDefinition IS NULL OR @ConstraintDisabled <> 0 OR @ConstraintNotTrusted <> 0
        THROW 55002, N'An expected trusted text allowlist constraint is missing.', 1;

    DECLARE @LegacyLowerCount INT =
        (DATALENGTH(@ConstraintDefinition) -
         DATALENGTH(REPLACE(@ConstraintDefinition, @LegacyLower, N''))) /
        DATALENGTH(@LegacyLower);
    DECLARE @SafeLowerCount INT =
        (DATALENGTH(@ConstraintDefinition) -
         DATALENGTH(REPLACE(@ConstraintDefinition, @SafeLower, N''))) /
        DATALENGTH(@SafeLower);
    DECLARE @LegacyUpperCount INT =
        (DATALENGTH(@ConstraintDefinition) -
         DATALENGTH(REPLACE(@ConstraintDefinition, @LegacyUpper, N''))) /
        DATALENGTH(@LegacyUpper);
    DECLARE @SafeUpperCount INT =
        (DATALENGTH(@ConstraintDefinition) -
         DATALENGTH(REPLACE(@ConstraintDefinition, @SafeUpper, N''))) /
        DATALENGTH(@SafeUpper);

    IF NOT
       ((@LegacyLowerCount = @ExpectedLowerCount AND @SafeLowerCount = 0
         AND @LegacyUpperCount = @ExpectedUpperCount AND @SafeUpperCount = 0)
        OR
        (@LegacyLowerCount = 0 AND @SafeLowerCount = @ExpectedLowerCount
         AND @LegacyUpperCount = 0 AND @SafeUpperCount = @ExpectedUpperCount))
        THROW 55003, N'An expected constraint allowlist definition has drifted.', 1;

    SET @ConstraintDefinition = REPLACE(@ConstraintDefinition, @LegacyLower, @SafeLower);
    SET @ConstraintDefinition = REPLACE(@ConstraintDefinition, @LegacyUpper, @SafeUpper);
    DECLARE @ConstraintSql NVARCHAR(MAX) =
        N'ALTER TABLE dbo.' + QUOTENAME(@TableName) +
        N' DROP CONSTRAINT ' + QUOTENAME(@ConstraintName) + N';';
    EXEC sys.sp_executesql @ConstraintSql;
    SET @ConstraintSql =
        N'ALTER TABLE dbo.' + QUOTENAME(@TableName) +
        N' WITH CHECK ADD CONSTRAINT ' + QUOTENAME(@ConstraintName) +
        N' CHECK ' + @ConstraintDefinition + N';';
    EXEC sys.sp_executesql @ConstraintSql;
    SET @ConstraintSql =
        N'ALTER TABLE dbo.' + QUOTENAME(@TableName) +
        N' CHECK CONSTRAINT ' + QUOTENAME(@ConstraintName) + N';';
    EXEC sys.sp_executesql @ConstraintSql;

    SELECT @ConstraintDefinition = definition,
           @ConstraintDisabled = is_disabled,
           @ConstraintNotTrusted = is_not_trusted
    FROM sys.check_constraints
    WHERE name = @ConstraintName AND parent_object_id = @TableObjectId;
    SET @SafeLowerCount =
        (DATALENGTH(@ConstraintDefinition) -
         DATALENGTH(REPLACE(@ConstraintDefinition, @SafeLower, N''))) /
        DATALENGTH(@SafeLower);
    SET @SafeUpperCount =
        (DATALENGTH(@ConstraintDefinition) -
         DATALENGTH(REPLACE(@ConstraintDefinition, @SafeUpper, N''))) /
        DATALENGTH(@SafeUpper);

    IF @ConstraintDefinition IS NULL OR @ConstraintDisabled <> 0 OR @ConstraintNotTrusted <> 0
       OR CHARINDEX(@LegacyLower, @ConstraintDefinition) > 0
       OR CHARINDEX(@LegacyUpper, @ConstraintDefinition) > 0
       OR @SafeLowerCount <> @ExpectedLowerCount
       OR @SafeUpperCount <> @ExpectedUpperCount
        THROW 55004, N'A corrected text allowlist constraint is invalid or untrusted.', 1;

    FETCH NEXT FROM ConstraintCursor
        INTO @TableName, @ConstraintName, @ExpectedLowerCount, @ExpectedUpperCount;
END;
CLOSE ConstraintCursor;
DEALLOCATE ConstraintCursor;

DECLARE @ProcedurePatches TABLE
(
    ProcedureName SYSNAME NOT NULL PRIMARY KEY,
    OldToken NVARCHAR(100) NOT NULL,
    NewToken NVARCHAR(100) NOT NULL,
    ExpectedCount INT NOT NULL
);

INSERT INTO @ProcedurePatches (ProcedureName, OldToken, NewToken, ExpectedCount)
VALUES
    (N'FundingPlatform_usp_SemanticEvaluationRun_Create',
     N'%[^A-Za-z0-9._-]%', N'%[^-A-Za-z0-9._]%', 2),
    (N'FundingPlatform_usp_SemanticEmbeddingJob_Claim',
     N'%[^A-Za-z0-9._-]%', N'%[^-A-Za-z0-9._]%', 1),
    (N'FundingPlatform_usp_SemanticEvaluationRun_Claim',
     N'%[^A-Za-z0-9._-]%', N'%[^-A-Za-z0-9._]%', 1),
    (N'FundingPlatform_usp_AlertDelivery_Fail',
     N'%[^a-z0-9-]%', N'%[^-a-z0-9]%', 1),
    /* These outcomes occur before any write. COMMIT closes the transaction
       opened by the procedure without rolling back an ambient transaction and
       remains compatible with INSERT...EXEC capture on Azure SQL. */
    (N'FundingPlatform_usp_OrganizationConnection_Create',
     N'BEGIN ROLLBACK; SELECT', N'BEGIN COMMIT; SELECT', 7),
    (N'FundingPlatform_usp_OrganizationConnection_Action',
     N'BEGIN ROLLBACK; SELECT', N'BEGIN COMMIT; SELECT', 3);

DECLARE @ProcedureName SYSNAME, @OldToken NVARCHAR(100), @NewToken NVARCHAR(100),
        @ExpectedCount INT;
DECLARE ProcedureCursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT ProcedureName, OldToken, NewToken, ExpectedCount
    FROM @ProcedurePatches
    ORDER BY ProcedureName;

OPEN ProcedureCursor;
FETCH NEXT FROM ProcedureCursor
    INTO @ProcedureName, @OldToken, @NewToken, @ExpectedCount;
WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @ProcedureObjectId INT = OBJECT_ID(N'dbo.' + @ProcedureName, N'P');
    DECLARE @Definition NVARCHAR(MAX) = OBJECT_DEFINITION(@ProcedureObjectId);
    DECLARE @OldCount INT =
        (DATALENGTH(@Definition) - DATALENGTH(REPLACE(@Definition, @OldToken, N''))) /
        DATALENGTH(@OldToken);
    DECLARE @NewCount INT =
        (DATALENGTH(@Definition) - DATALENGTH(REPLACE(@Definition, @NewToken, N''))) /
        DATALENGTH(@NewToken);
    IF @Definition IS NULL
       OR NOT ((@OldCount = @ExpectedCount AND @NewCount = 0)
               OR (@OldCount = 0 AND @NewCount = @ExpectedCount))
        THROW 55005, N'An expected procedure allowlist definition has drifted.', 1;

    IF @OldCount = @ExpectedCount
    BEGIN
        SET @Definition = REPLACE(@Definition, @OldToken, @NewToken);
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
            THROW 55006, N'An expected procedure definition has an unsafe DDL header.', 1;
        SET @TrimmedDefinition = N'CREATE OR ALTER PROCEDURE' + SUBSTRING(
            @TrimmedDefinition,
            @ProcedureKeywordPosition + LEN(N'PROCEDURE'),
            2147483647);
        SET @Definition = LEFT(@Definition, @LeadingWhitespaceLength) + @TrimmedDefinition;
        EXEC sys.sp_executesql @Definition;
    END;

    SET @Definition = OBJECT_DEFINITION(@ProcedureObjectId);
    SET @OldCount =
        (DATALENGTH(@Definition) - DATALENGTH(REPLACE(@Definition, @OldToken, N''))) /
        DATALENGTH(@OldToken);
    SET @NewCount =
        (DATALENGTH(@Definition) - DATALENGTH(REPLACE(@Definition, @NewToken, N''))) /
        DATALENGTH(@NewToken);
    IF OBJECT_ID(N'dbo.' + @ProcedureName, N'P') <> @ProcedureObjectId
       OR @OldCount <> 0 OR @NewCount <> @ExpectedCount
       OR NOT EXISTS
          (SELECT 1
           FROM sys.sql_modules
           WHERE object_id = @ProcedureObjectId
             AND uses_ansi_nulls = 1
             AND uses_quoted_identifier = 1)
        THROW 55007, N'A corrected procedure did not preserve its trusted identity.', 1;

    FETCH NEXT FROM ProcedureCursor
        INTO @ProcedureName, @OldToken, @NewToken, @ExpectedCount;
END;
CLOSE ProcedureCursor;
DEALLOCATE ProcedureCursor;
GO

/* Azure SQL keeps the row produced by an AFTER trigger when its THROW is caught
   under XACT_ABORT OFF. Validate before mutation so a rejected forged semantic
   result cannot remain visible in the caller transaction. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF NOT EXISTS
   (SELECT 1
    FROM sys.triggers
    WHERE object_id = OBJECT_ID(N'dbo.FundingPlatform_tr_SemanticEvaluationItems_SubjectGuard')
      AND parent_id = OBJECT_ID(N'dbo.FundingPlatform_SemanticEvaluationItems')
      AND is_disabled = 0)
   OR OBJECT_DEFINITION(
          OBJECT_ID(N'dbo.FundingPlatform_tr_SemanticEvaluationItems_SubjectGuard'))
      NOT LIKE N'%VECTOR_DISTANCE(''cosine''%'
   OR OBJECT_DEFINITION(
          OBJECT_ID(N'dbo.FundingPlatform_tr_SemanticEvaluationItems_SubjectGuard'))
      NOT LIKE N'%inserted.SemanticScore <>%'
    THROW 55020, N'The semantic evaluation subject guard has drifted.', 1;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_SemanticEvaluationItems_SubjectGuard
ON dbo.FundingPlatform_SemanticEvaluationItems
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS
       (SELECT 1
        FROM inserted
        LEFT JOIN dbo.FundingPlatform_SemanticEvaluationRunCases AS runCases
            ON runCases.SemanticEvaluationRunId = inserted.SemanticEvaluationRunId
           AND runCases.CaseOrdinal = inserted.CaseOrdinal
           AND runCases.ProjectFundingMatchId = inserted.ProjectFundingMatchId
        LEFT JOIN dbo.FundingPlatform_SemanticEvaluationRuns AS evaluationRuns
            ON evaluationRuns.Id = runCases.SemanticEvaluationRunId
        LEFT JOIN dbo.FundingPlatform_ProjectFundingMatches AS matches
            ON matches.Id = runCases.ProjectFundingMatchId
        LEFT JOIN dbo.FundingPlatform_SemanticEmbeddings AS projectEmbeddings
            ON projectEmbeddings.Id = inserted.ProjectEmbeddingId
           AND projectEmbeddings.SemanticConfigurationId = evaluationRuns.SemanticConfigurationId
           AND projectEmbeddings.SubjectType = 0
           AND projectEmbeddings.OrganizationId = runCases.OrganizationId
           AND projectEmbeddings.ProjectId = runCases.ProjectId
           AND projectEmbeddings.ProjectVersion = runCases.ProjectVersion
           AND projectEmbeddings.SubjectContentHash = runCases.ProjectContentHash
           AND projectEmbeddings.InputContentHash = runCases.ProjectInputContentHash
           AND projectEmbeddings.ContentAddress = runCases.ProjectContentAddress
        LEFT JOIN dbo.FundingPlatform_SemanticEmbeddings AS opportunityEmbeddings
            ON opportunityEmbeddings.Id = inserted.OpportunityEmbeddingId
           AND opportunityEmbeddings.SemanticConfigurationId = evaluationRuns.SemanticConfigurationId
           AND opportunityEmbeddings.SubjectType = 1
           AND opportunityEmbeddings.OrganizationId IS NULL
           AND opportunityEmbeddings.FundingOpportunityId = runCases.FundingOpportunityId
           AND opportunityEmbeddings.FundingContentVersion = runCases.FundingContentVersion
           AND opportunityEmbeddings.SubjectContentHash = runCases.OpportunityContentHash
           AND opportunityEmbeddings.InputContentHash = runCases.OpportunityInputContentHash
           AND opportunityEmbeddings.ContentAddress = runCases.OpportunityContentAddress
        OUTER APPLY
           (SELECT VECTOR_DISTANCE('cosine', projectEmbeddings.Embedding,
                                             opportunityEmbeddings.Embedding) AS RawDistance)
             AS vectorDistance
        OUTER APPLY
           (SELECT CONVERT(DECIMAL(9,8),
               CASE WHEN vectorDistance.RawDistance < 0 THEN 0
                    WHEN vectorDistance.RawDistance > 2 THEN 2
                    ELSE vectorDistance.RawDistance END) AS ExpectedDistance)
             AS calculated
        WHERE runCases.SemanticEvaluationRunId IS NULL OR evaluationRuns.Id IS NULL
           OR projectEmbeddings.Id IS NULL OR opportunityEmbeddings.Id IS NULL
           OR calculated.ExpectedDistance IS NULL
           OR inserted.CosineDistance <> calculated.ExpectedDistance
           OR inserted.CosineSimilarity <>
              CONVERT(DECIMAL(9,8), 1 - calculated.ExpectedDistance)
           OR inserted.SemanticScore <>
              CONVERT(DECIMAL(5,2), (2 - calculated.ExpectedDistance) * 50)
           OR inserted.RelevanceLabel <> runCases.RelevanceLabel
           OR inserted.DatasetSplit <> runCases.DatasetSplit
           OR inserted.IsPrimaryCohort <>
              CASE WHEN runCases.DatasetSplit = 1 AND matches.Classification <> 1
                   THEN 1 ELSE 0 END)
        THROW 54103, N'Shadow item subjects, versions, tenant and configuration must match the frozen 9A run.', 1;

    /* A same-table write from an INSTEAD OF trigger bypasses this trigger and
       proceeds through constraints and any AFTER triggers exactly once. */
    INSERT INTO dbo.FundingPlatform_SemanticEvaluationItems
        (SemanticEvaluationRunId, CaseOrdinal, ProjectFundingMatchId,
         ProjectEmbeddingId, OpportunityEmbeddingId, CosineDistance,
         CosineSimilarity, SemanticScore, SemanticRank, DeterministicRank,
         RelevanceLabel, DatasetSplit, IsPrimaryCohort, CreatedAtUtc)
    SELECT SemanticEvaluationRunId, CaseOrdinal, ProjectFundingMatchId,
           ProjectEmbeddingId, OpportunityEmbeddingId, CosineDistance,
           CosineSimilarity, SemanticScore, SemanticRank, DeterministicRank,
           RelevanceLabel, DatasetSplit, IsPrimaryCohort, CreatedAtUtc
    FROM inserted;
END;
GO

IF NOT EXISTS
   (SELECT 1
    FROM sys.triggers
    WHERE object_id = OBJECT_ID(N'dbo.FundingPlatform_tr_SemanticEvaluationItems_SubjectGuard')
      AND parent_id = OBJECT_ID(N'dbo.FundingPlatform_SemanticEvaluationItems')
      AND is_disabled = 0
      AND is_instead_of_trigger = 1)
   OR OBJECT_DEFINITION(
          OBJECT_ID(N'dbo.FundingPlatform_tr_SemanticEvaluationItems_SubjectGuard'))
      NOT LIKE N'%INSERT INTO dbo.FundingPlatform_SemanticEvaluationItems%'
    THROW 55021, N'The pre-mutation semantic subject guard was not installed.', 1;
GO

/* Migration 023 introduced governed structured explanations but the 022 policy
   guard only considered active embedding configurations. Close that final-schema
   gap without changing either already-registered migration. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_AiProviderGovernancePolicies', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_SemanticConfigurations', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_AiExplanationConfigurations', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_tr_AiProviderGovernancePolicies_Immutable', N'TR') IS NULL
   OR OBJECT_DEFINITION(
          OBJECT_ID(N'dbo.FundingPlatform_tr_AiProviderGovernancePolicies_Immutable'))
      NOT LIKE N'%inserted.PolicyFingerprint <> state.CalculatedFingerprint%'
   OR OBJECT_DEFINITION(
          OBJECT_ID(N'dbo.FundingPlatform_tr_AiProviderGovernancePolicies_Immutable'))
      NOT LIKE N'%FundingPlatform_SemanticConfigurations%'
    THROW 55030, N'The governed-provider immutability guard has drifted.', 1;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_AiProviderGovernancePolicies_Immutable
ON dbo.FundingPlatform_AiProviderGovernancePolicies
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS
       (SELECT 1 FROM inserted
        OUTER APPLY dbo.FundingPlatform_ifn_AiProviderGovernancePolicyState(inserted.Id) AS state
        WHERE state.Id IS NULL OR inserted.PolicyFingerprint <> state.CalculatedFingerprint)
        THROW 54203, N'AI provider governance fingerprint must match all frozen fields.', 1;
    IF EXISTS (SELECT 1 FROM deleted WHERE NOT EXISTS
               (SELECT 1 FROM inserted WHERE inserted.Id = deleted.Id))
       OR EXISTS
          (SELECT 1 FROM inserted INNER JOIN deleted ON deleted.Id = inserted.Id
           WHERE inserted.PublicId <> deleted.PublicId
              OR inserted.Code COLLATE Latin1_General_100_BIN2 <>
                 deleted.Code COLLATE Latin1_General_100_BIN2
              OR inserted.Version <> deleted.Version
              OR inserted.ProviderCode COLLATE Latin1_General_100_BIN2 <>
                 deleted.ProviderCode COLLATE Latin1_General_100_BIN2
              OR inserted.ModelCode COLLATE Latin1_General_100_BIN2 <>
                 deleted.ModelCode COLLATE Latin1_General_100_BIN2
              OR inserted.Capability <> deleted.Capability
              OR inserted.EndpointOrigin COLLATE Latin1_General_100_BIN2 <>
                 deleted.EndpointOrigin COLLATE Latin1_General_100_BIN2
              OR inserted.RetentionMode <> deleted.RetentionMode
              OR inserted.MaximumProviderRetentionDays <> deleted.MaximumProviderRetentionDays
              OR inserted.DataResidencyCode COLLATE Latin1_General_100_BIN2 <>
                 deleted.DataResidencyCode COLLATE Latin1_General_100_BIN2
              OR inserted.DpaReferenceHash <> deleted.DpaReferenceHash
              OR inserted.TermsSnapshotHash <> deleted.TermsSnapshotHash
              OR inserted.InputTokenCostUsdPerMillion <> deleted.InputTokenCostUsdPerMillion
              OR inserted.OutputTokenCostUsdPerMillion <> deleted.OutputTokenCostUsdPerMillion
              OR inserted.PolicyFingerprint <> deleted.PolicyFingerprint
              OR inserted.ExternalProcessingAllowed <> deleted.ExternalProcessingAllowed
              OR inserted.ApprovedByUserId <> deleted.ApprovedByUserId
              OR inserted.ApprovedAtUtc <> deleted.ApprovedAtUtc
              OR inserted.ExpiresAtUtc <> deleted.ExpiresAtUtc
              OR inserted.CreatedAtUtc <> deleted.CreatedAtUtc
              OR (deleted.IsActive = 0 AND inserted.IsActive = 1))
        THROW 54204, N'Published AI provider governance is immutable and cannot be reactivated.', 1;
    IF EXISTS
       (SELECT 1 FROM inserted INNER JOIN deleted ON deleted.Id = inserted.Id
        WHERE deleted.IsActive = 1 AND inserted.IsActive = 0
          AND
          (EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_SemanticConfigurations AS configurations
              WHERE configurations.ProviderGovernancePolicyId = inserted.Id
                AND configurations.IsActive = 1)
           OR EXISTS
             (SELECT 1 FROM dbo.FundingPlatform_AiExplanationConfigurations AS configurations
              WHERE configurations.ProviderGovernancePolicyId = inserted.Id
                AND configurations.IsActive = 1)))
        THROW 54205, N'Governance used by an active semantic or explanation configuration cannot be disabled.', 1;
END;
GO

IF NOT EXISTS
   (SELECT 1
    FROM sys.triggers
    WHERE object_id =
          OBJECT_ID(N'dbo.FundingPlatform_tr_AiProviderGovernancePolicies_Immutable')
      AND parent_id = OBJECT_ID(N'dbo.FundingPlatform_AiProviderGovernancePolicies')
      AND is_disabled = 0
      AND is_instead_of_trigger = 0)
   OR OBJECT_DEFINITION(
          OBJECT_ID(N'dbo.FundingPlatform_tr_AiProviderGovernancePolicies_Immutable'))
      NOT LIKE N'%FundingPlatform_AiExplanationConfigurations%'
    THROW 55031, N'The governed-provider explanation dependency guard was not installed.', 1;
GO
