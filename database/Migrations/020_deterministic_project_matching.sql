/* FundingPlatform FASE 9A - bounded, versioned and explainable deterministic matching. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

CREATE TABLE dbo.FundingPlatform_MatchingProfiles
(
    Id INT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_MatchingProfiles_PublicId DEFAULT (NEWSEQUENTIALID()),
    Code NVARCHAR(100) NOT NULL,
    Version INT NOT NULL,
    EngineVersion NVARCHAR(50) NOT NULL,
    UnknownPolicy TINYINT NOT NULL,
    Status TINYINT NOT NULL,
    IsActive BIT NOT NULL,
    PublishedAtUtc DATETIME2(3) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_MatchingProfiles PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_MatchingProfiles_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_MatchingProfiles_CodeVersion UNIQUE (Code, Version),
    CONSTRAINT FundingPlatform_CK_MatchingProfiles_Version CHECK (Version >= 1),
    /* 1 = unknown scores zero, reduces coverage and is never renormalized. */
    CONSTRAINT FundingPlatform_CK_MatchingProfiles_UnknownPolicy CHECK (UnknownPolicy = 1),
    /* FASE 9A stores only published immutable configuration. */
    CONSTRAINT FundingPlatform_CK_MatchingProfiles_Status CHECK (Status = 2),
    CONSTRAINT FundingPlatform_CK_MatchingProfiles_Code CHECK
        (LEN(LTRIM(RTRIM(Code))) BETWEEN 1 AND 100),
    CONSTRAINT FundingPlatform_CK_MatchingProfiles_Engine CHECK
        (LEN(LTRIM(RTRIM(EngineVersion))) BETWEEN 1 AND 50)
);

CREATE UNIQUE INDEX FundingPlatform_UQ_MatchingProfiles_Active
    ON dbo.FundingPlatform_MatchingProfiles (IsActive)
    WHERE IsActive = 1;

CREATE TABLE dbo.FundingPlatform_MatchingRules
(
    Id INT IDENTITY(1,1) NOT NULL,
    Code NVARCHAR(100) NOT NULL,
    Name NVARCHAR(150) NOT NULL,
    HandlerVersion NVARCHAR(50) NOT NULL,
    IsHardGate BIT NOT NULL,
    IsActive BIT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_MatchingRules PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_MatchingRules_CodeHandler UNIQUE (Code, HandlerVersion),
    CONSTRAINT FundingPlatform_CK_MatchingRules_Code CHECK
        (LEN(LTRIM(RTRIM(Code))) BETWEEN 1 AND 100),
    CONSTRAINT FundingPlatform_CK_MatchingRules_Name CHECK
        (LEN(LTRIM(RTRIM(Name))) BETWEEN 1 AND 150),
    CONSTRAINT FundingPlatform_CK_MatchingRules_Handler CHECK
        (LEN(LTRIM(RTRIM(HandlerVersion))) BETWEEN 1 AND 50)
);

CREATE TABLE dbo.FundingPlatform_MatchingRuleWeights
(
    MatchingProfileId INT NOT NULL,
    MatchingRuleId INT NOT NULL,
    Weight DECIMAL(5,2) NOT NULL,
    ParametersJson NVARCHAR(MAX) NULL,
    CONSTRAINT FundingPlatform_PK_MatchingRuleWeights
        PRIMARY KEY (MatchingProfileId, MatchingRuleId),
    CONSTRAINT FundingPlatform_FK_MatchingRuleWeights_Profile
        FOREIGN KEY (MatchingProfileId) REFERENCES dbo.FundingPlatform_MatchingProfiles (Id),
    CONSTRAINT FundingPlatform_FK_MatchingRuleWeights_Rule
        FOREIGN KEY (MatchingRuleId) REFERENCES dbo.FundingPlatform_MatchingRules (Id),
    CONSTRAINT FundingPlatform_CK_MatchingRuleWeights_Weight CHECK (Weight BETWEEN 0 AND 100),
    CONSTRAINT FundingPlatform_CK_MatchingRuleWeights_Parameters CHECK
        (ParametersJson IS NULL OR
         (ISJSON(ParametersJson) = 1 AND LEFT(LTRIM(ParametersJson), 1) = N'{'))
);

CREATE TABLE dbo.FundingPlatform_ProjectMatchingRuns
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_ProjectMatchingRuns_PublicId DEFAULT (NEWSEQUENTIALID()),
    OrganizationId BIGINT NOT NULL,
    ProjectId BIGINT NOT NULL,
    ProjectSlugSnapshot NVARCHAR(180) NOT NULL,
    ProjectTitleSnapshot NVARCHAR(250) NOT NULL,
    MatchingProfileId INT NOT NULL,
    MatchingProfileCodeSnapshot NVARCHAR(100) NOT NULL,
    MatchingProfileVersionSnapshot INT NOT NULL,
    EngineVersionSnapshot NVARCHAR(50) NOT NULL,
    RuleSetFingerprint BINARY(32) NOT NULL,
    ProjectVersion INT NOT NULL,
    OrganizationProfileVersion INT NOT NULL,
    InputFingerprint BINARY(32) NOT NULL,
    CandidateSetFingerprint BINARY(32) NOT NULL,
    CatalogSnapshotAtUtc DATETIME2(3) NOT NULL,
    CalculationCalendarYear SMALLINT NOT NULL,
    TotalCandidateCount INT NOT NULL,
    ProcessedCandidateCount INT NOT NULL,
    CompatibleCount INT NOT NULL,
    IncompatibleCount INT NOT NULL,
    InsufficientDataCount INT NOT NULL,
    IsTruncated BIT NOT NULL,
    Status TINYINT NOT NULL,
    StartedAtUtc DATETIME2(3) NOT NULL,
    CompletedAtUtc DATETIME2(3) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_ProjectMatchingRuns PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_ProjectMatchingRuns_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_ProjectMatchingRuns_IdTenantProject
        UNIQUE (Id, OrganizationId, ProjectId),
    CONSTRAINT FundingPlatform_UQ_ProjectMatchingRuns_Reproducible
        UNIQUE (Id, OrganizationId, ProjectId, MatchingProfileId,
                ProjectVersion, OrganizationProfileVersion),
    CONSTRAINT FundingPlatform_FK_ProjectMatchingRuns_Organization
        FOREIGN KEY (OrganizationId) REFERENCES dbo.FundingPlatform_Organizations (Id),
    CONSTRAINT FundingPlatform_FK_ProjectMatchingRuns_ProjectOrganization
        FOREIGN KEY (ProjectId, OrganizationId)
        REFERENCES dbo.FundingPlatform_Projects (Id, OrganizationId),
    CONSTRAINT FundingPlatform_FK_ProjectMatchingRuns_Profile
        FOREIGN KEY (MatchingProfileId) REFERENCES dbo.FundingPlatform_MatchingProfiles (Id),
    CONSTRAINT FundingPlatform_FK_ProjectMatchingRuns_ProjectVersion
        FOREIGN KEY (ProjectId, ProjectVersion)
        REFERENCES dbo.FundingPlatform_ProjectVersions (ProjectId, ProjectVersion),
    CONSTRAINT FundingPlatform_FK_ProjectMatchingRuns_OrganizationVersion
        FOREIGN KEY (OrganizationId, OrganizationProfileVersion)
        REFERENCES dbo.FundingPlatform_OrganizationProfileVersions (OrganizationId, ProfileVersion),
    CONSTRAINT FundingPlatform_CK_ProjectMatchingRuns_Versions CHECK
        (MatchingProfileVersionSnapshot >= 1
         AND ProjectVersion >= 1 AND OrganizationProfileVersion >= 1),
    CONSTRAINT FundingPlatform_CK_ProjectMatchingRuns_ProfileSnapshot CHECK
        (LEN(LTRIM(RTRIM(MatchingProfileCodeSnapshot))) BETWEEN 1 AND 100
         AND LEN(LTRIM(RTRIM(EngineVersionSnapshot))) BETWEEN 1 AND 50),
    CONSTRAINT FundingPlatform_CK_ProjectMatchingRuns_ProjectSnapshot CHECK
        (LEN(LTRIM(RTRIM(ProjectSlugSnapshot))) BETWEEN 1 AND 180
         AND LEN(LTRIM(RTRIM(ProjectTitleSnapshot))) BETWEEN 1 AND 250),
    CONSTRAINT FundingPlatform_CK_ProjectMatchingRuns_CalendarYear CHECK
        (CalculationCalendarYear BETWEEN 2000 AND 2200),
    CONSTRAINT FundingPlatform_CK_ProjectMatchingRuns_Counts CHECK
        (TotalCandidateCount >= 0
         AND ProcessedCandidateCount BETWEEN 0 AND 200
         AND ProcessedCandidateCount <= TotalCandidateCount
         AND CompatibleCount >= 0 AND IncompatibleCount >= 0
         AND InsufficientDataCount >= 0
         AND CompatibleCount + IncompatibleCount + InsufficientDataCount = ProcessedCandidateCount),
    CONSTRAINT FundingPlatform_CK_ProjectMatchingRuns_Truncation CHECK
        ((IsTruncated = 0 AND ProcessedCandidateCount = TotalCandidateCount)
         OR (IsTruncated = 1 AND TotalCandidateCount > ProcessedCandidateCount)),
    /* Synchronous 9A runs have one terminal state: 2 = Completed. */
    CONSTRAINT FundingPlatform_CK_ProjectMatchingRuns_Status CHECK (Status = 2),
    CONSTRAINT FundingPlatform_CK_ProjectMatchingRuns_Times CHECK
        (StartedAtUtc <= CompletedAtUtc AND CreatedAtUtc <= CompletedAtUtc)
);

CREATE INDEX FundingPlatform_IX_ProjectMatchingRuns_ProjectCreated
    ON dbo.FundingPlatform_ProjectMatchingRuns (OrganizationId, ProjectId, CreatedAtUtc DESC, Id DESC)
    INCLUDE (PublicId, MatchingProfileId, ProjectVersion, OrganizationProfileVersion,
             Status, ProcessedCandidateCount, CompletedAtUtc);

CREATE INDEX FundingPlatform_IX_ProjectMatchingRuns_ProjectInput
    ON dbo.FundingPlatform_ProjectMatchingRuns (ProjectId, InputFingerprint, Id DESC)
    INCLUDE (PublicId, Status, CompletedAtUtc);

CREATE TABLE dbo.FundingPlatform_ProjectFundingMatches
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT FundingPlatform_DF_ProjectFundingMatches_PublicId DEFAULT (NEWSEQUENTIALID()),
    OrganizationId BIGINT NOT NULL,
    ProjectId BIGINT NOT NULL,
    FundingOpportunityId BIGINT NOT NULL,
    MatchRunId BIGINT NOT NULL,
    MatchingProfileId INT NOT NULL,
    ProjectVersion INT NOT NULL,
    OrganizationProfileVersion INT NOT NULL,
    FundingContentVersion INT NOT NULL,
    OpportunitySlug NVARCHAR(320) NOT NULL,
    OpportunityTitle NVARCHAR(350) NOT NULL,
    SponsorName NVARCHAR(300) NOT NULL,
    Currency CHAR(3) NULL,
    MinAmount DECIMAL(19,4) NULL,
    MaxAmount DECIMAL(19,4) NULL,
    CloseDate DATE NULL,
    CloseAtUtc DATETIME2(3) NULL,
    DeadlinePrecision TINYINT NOT NULL,
    Classification TINYINT NOT NULL,
    HardGateStatus TINYINT NOT NULL,
    CompatibilityScore DECIMAL(5,2) NULL,
    RuleScore DECIMAL(5,2) NOT NULL,
    EvidenceCoverage DECIMAL(5,2) NOT NULL,
    InputFingerprint BINARY(32) NOT NULL,
    IsCurrent BIT NOT NULL,
    CalculatedAtUtc DATETIME2(3) NOT NULL,
    SupersededAtUtc DATETIME2(3) NULL,
    CONSTRAINT FundingPlatform_PK_ProjectFundingMatches PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_ProjectFundingMatches_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_ProjectFundingMatches_RunOpportunity
        UNIQUE (MatchRunId, FundingOpportunityId),
    CONSTRAINT FundingPlatform_FK_ProjectFundingMatches_Run
        FOREIGN KEY (MatchRunId, OrganizationId, ProjectId, MatchingProfileId,
                     ProjectVersion, OrganizationProfileVersion)
        REFERENCES dbo.FundingPlatform_ProjectMatchingRuns
            (Id, OrganizationId, ProjectId, MatchingProfileId,
             ProjectVersion, OrganizationProfileVersion),
    CONSTRAINT FundingPlatform_FK_ProjectFundingMatches_OpportunityVersion
        FOREIGN KEY (FundingOpportunityId, FundingContentVersion)
        REFERENCES dbo.FundingPlatform_FundingOpportunityVersions
            (FundingOpportunityId, ContentVersion),
    CONSTRAINT FundingPlatform_FK_ProjectFundingMatches_Currency
        FOREIGN KEY (Currency) REFERENCES dbo.FundingPlatform_Currencies (Code),
    /* 0 Compatible, 1 Incompatible, 2 InsufficientData. */
    CONSTRAINT FundingPlatform_CK_ProjectFundingMatches_Classification CHECK
        (Classification BETWEEN 0 AND 2),
    /* 0 Pass, 1 Fail, 2 Unknown. */
    CONSTRAINT FundingPlatform_CK_ProjectFundingMatches_HardGateStatus CHECK
        ((Classification = 0 AND HardGateStatus = 0)
         OR (Classification = 1 AND HardGateStatus = 1)
         OR (Classification = 2 AND HardGateStatus = 2)),
    CONSTRAINT FundingPlatform_CK_ProjectFundingMatches_Scores CHECK
        (RuleScore BETWEEN 0 AND 100 AND EvidenceCoverage BETWEEN 0 AND 100
         AND ((Classification = 1 AND CompatibilityScore IS NULL)
              OR (Classification IN (0, 2) AND CompatibilityScore BETWEEN 0 AND 100))),
    CONSTRAINT FundingPlatform_CK_ProjectFundingMatches_Current CHECK
        ((IsCurrent = 1 AND SupersededAtUtc IS NULL)
         OR (IsCurrent = 0 AND SupersededAtUtc IS NOT NULL))
);

CREATE UNIQUE INDEX FundingPlatform_UQ_ProjectFundingMatches_Current
    ON dbo.FundingPlatform_ProjectFundingMatches (ProjectId, FundingOpportunityId)
    WHERE IsCurrent = 1;

CREATE INDEX FundingPlatform_IX_ProjectFundingMatches_RunScore
    ON dbo.FundingPlatform_ProjectFundingMatches
       (MatchRunId, Classification, CompatibilityScore DESC, FundingOpportunityId)
    INCLUDE (PublicId, EvidenceCoverage, HardGateStatus);

CREATE TABLE dbo.FundingPlatform_ProjectFundingMatchRuleResults
(
    MatchId BIGINT NOT NULL,
    MatchingRuleId INT NOT NULL,
    Outcome TINYINT NOT NULL,
    RawScore DECIMAL(5,2) NULL,
    DataState TINYINT NOT NULL,
    EffectiveScore DECIMAL(5,2) NOT NULL,
    AppliedWeight DECIMAL(5,2) NOT NULL,
    WeightedPoints DECIMAL(7,4) NOT NULL,
    ReasonCode NVARCHAR(100) NOT NULL,
    ReasonParametersJson NVARCHAR(MAX) NULL,
    EvidenceJson NVARCHAR(MAX) NULL,
    IsWarning BIT NOT NULL,
    CONSTRAINT FundingPlatform_PK_ProjectFundingMatchRuleResults
        PRIMARY KEY (MatchId, MatchingRuleId),
    CONSTRAINT FundingPlatform_FK_ProjectFundingMatchRuleResults_Match
        FOREIGN KEY (MatchId) REFERENCES dbo.FundingPlatform_ProjectFundingMatches (Id),
    CONSTRAINT FundingPlatform_FK_ProjectFundingMatchRuleResults_Rule
        FOREIGN KEY (MatchingRuleId) REFERENCES dbo.FundingPlatform_MatchingRules (Id),
    /* 0 Match/Pass, 1 Partial, 2 NoMatch/Fail, 3 Unknown. */
    CONSTRAINT FundingPlatform_CK_ProjectFundingMatchRuleResults_Outcome CHECK
        (Outcome BETWEEN 0 AND 3),
    /* 0 Known, 1 Unknown, 2 NotApplicable. */
    CONSTRAINT FundingPlatform_CK_ProjectFundingMatchRuleResults_DataState CHECK
        ((Outcome = 3 AND DataState = 1 AND RawScore IS NULL AND EffectiveScore = 0)
         OR (Outcome <> 3 AND DataState IN (0, 2)
             AND RawScore BETWEEN 0 AND 100 AND EffectiveScore = RawScore)),
    CONSTRAINT FundingPlatform_CK_ProjectFundingMatchRuleResults_Scores CHECK
        (AppliedWeight BETWEEN 0 AND 100 AND WeightedPoints BETWEEN 0 AND 100
         AND WeightedPoints = CONVERT(DECIMAL(7,4), AppliedWeight * EffectiveScore / 100.0)),
    CONSTRAINT FundingPlatform_CK_ProjectFundingMatchRuleResults_Reason CHECK
        (LEN(LTRIM(RTRIM(ReasonCode))) BETWEEN 1 AND 100),
    CONSTRAINT FundingPlatform_CK_ProjectFundingMatchRuleResults_Json CHECK
        ((ReasonParametersJson IS NULL OR
          (ISJSON(ReasonParametersJson) = 1 AND LEFT(LTRIM(ReasonParametersJson), 1) = N'{'))
         AND (EvidenceJson IS NULL OR
          (ISJSON(EvidenceJson) = 1 AND LEFT(LTRIM(EvidenceJson), 1) = N'{')))
);

CREATE TABLE dbo.FundingPlatform_ProjectMatchingRunRequests
(
    UserId BIGINT NOT NULL,
    OrganizationId BIGINT NOT NULL,
    ProjectId BIGINT NOT NULL,
    IdempotencyKeyHash BINARY(32) NOT NULL,
    RequestHash BINARY(32) NOT NULL,
    MatchRunId BIGINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_ProjectMatchingRunRequests
        PRIMARY KEY (UserId, OrganizationId, ProjectId, IdempotencyKeyHash),
    CONSTRAINT FundingPlatform_FK_ProjectMatchingRunRequests_Membership
        FOREIGN KEY (OrganizationId, UserId)
        REFERENCES dbo.FundingPlatform_OrganizationUsers (OrganizationId, UserId),
    CONSTRAINT FundingPlatform_FK_ProjectMatchingRunRequests_ProjectOrganization
        FOREIGN KEY (ProjectId, OrganizationId)
        REFERENCES dbo.FundingPlatform_Projects (Id, OrganizationId),
    CONSTRAINT FundingPlatform_FK_ProjectMatchingRunRequests_RunTenantProject
        FOREIGN KEY (MatchRunId, OrganizationId, ProjectId)
        REFERENCES dbo.FundingPlatform_ProjectMatchingRuns (Id, OrganizationId, ProjectId)
);

DECLARE @SeededAtUtc DATETIME2(3) = SYSUTCDATETIME();
INSERT INTO dbo.FundingPlatform_MatchingProfiles
    (Code, Version, EngineVersion, UnknownPolicy, Status, IsActive, PublishedAtUtc, CreatedAtUtc)
VALUES
    (N'deterministic-project-v1', 1, N'deterministic-sql-v1', 1, 2, 1,
     @SeededAtUtc, @SeededAtUtc);

INSERT INTO dbo.FundingPlatform_MatchingRules
    (Code, Name, HandlerVersion, IsHardGate, IsActive, CreatedAtUtc)
VALUES
    (N'geography', N'Geography', N'v1', 1, 1, @SeededAtUtc),
    (N'organization_type', N'Organization type', N'v1', 1, 1, @SeededAtUtc),
    (N'legal_entity', N'Legal entity', N'v1', 1, 1, @SeededAtUtc),
    (N'operating_years', N'Operating years', N'v1', 1, 1, @SeededAtUtc),
    (N'prior_experience', N'Prior funding experience', N'v1', 1, 1, @SeededAtUtc),
    (N'categories', N'Funding categories', N'v1', 0, 1, @SeededAtUtc),
    (N'beneficiaries', N'Beneficiary types', N'v1', 0, 1, @SeededAtUtc),
    (N'project_type', N'Project type', N'v1', 0, 1, @SeededAtUtc),
    (N'amount', N'Funding amount', N'v1', 0, 1, @SeededAtUtc);

DECLARE @ProfileId INT =
    (SELECT Id FROM dbo.FundingPlatform_MatchingProfiles
     WHERE Code = N'deterministic-project-v1' AND Version = 1);
INSERT INTO dbo.FundingPlatform_MatchingRuleWeights
    (MatchingProfileId, MatchingRuleId, Weight, ParametersJson)
SELECT @ProfileId, rules.Id, weights.Weight,
       N'{"unknownPolicy":"zero-no-renormalization"}'
FROM (VALUES
        (N'geography', CONVERT(DECIMAL(5,2), 20)),
        (N'organization_type', CONVERT(DECIMAL(5,2), 15)),
        (N'legal_entity', CONVERT(DECIMAL(5,2), 15)),
        (N'operating_years', CONVERT(DECIMAL(5,2), 10)),
        (N'prior_experience', CONVERT(DECIMAL(5,2), 10)),
        (N'categories', CONVERT(DECIMAL(5,2), 10)),
        (N'beneficiaries', CONVERT(DECIMAL(5,2), 5)),
        (N'project_type', CONVERT(DECIMAL(5,2), 5)),
        (N'amount', CONVERT(DECIMAL(5,2), 10))
     ) AS weights(Code, Weight)
INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
    ON rules.Code = weights.Code AND rules.HandlerVersion = N'v1';
GO

/* Published deterministic configuration is immutable except for toggling the
   profile active flag; new rule/profile versions use new rows. */
CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_MatchingProfiles_Immutable
ON dbo.FundingPlatform_MatchingProfiles
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted WHERE NOT EXISTS
               (SELECT 1 FROM inserted WHERE inserted.Id = deleted.Id))
       OR EXISTS
          (SELECT 1
           FROM inserted
           INNER JOIN deleted ON deleted.Id = inserted.Id
           WHERE inserted.PublicId <> deleted.PublicId
              OR inserted.Code <> deleted.Code
              OR inserted.Version <> deleted.Version
              OR inserted.EngineVersion <> deleted.EngineVersion
              OR inserted.UnknownPolicy <> deleted.UnknownPolicy
              OR inserted.Status <> deleted.Status
              OR inserted.PublishedAtUtc <> deleted.PublishedAtUtc
              OR inserted.CreatedAtUtc <> deleted.CreatedAtUtc)
        THROW 52406, N'Published matching profiles are immutable.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_MatchingRules_Immutable
ON dbo.FundingPlatform_MatchingRules
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted)
        THROW 52406, N'Published matching rules are immutable.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_MatchingRuleWeights_Immutable
ON dbo.FundingPlatform_MatchingRuleWeights
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted)
       OR EXISTS
          (SELECT 1 FROM inserted
           INNER JOIN dbo.FundingPlatform_MatchingProfiles AS profiles
               ON profiles.Id = inserted.MatchingProfileId
           WHERE profiles.IsActive = 1
              OR EXISTS
                 (SELECT 1
                  FROM dbo.FundingPlatform_ProjectMatchingRuns AS runs
                  WHERE runs.MatchingProfileId = inserted.MatchingProfileId))
        THROW 52406, N'Published matching rule weights are immutable.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_ProjectMatchingRuns_Immutable
ON dbo.FundingPlatform_ProjectMatchingRuns
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted)
        THROW 52406, N'Completed matching runs are immutable.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_ProjectFundingMatchRuleResults_Immutable
ON dbo.FundingPlatform_ProjectFundingMatchRuleResults
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted)
        THROW 52406, N'Deterministic matching rule results are immutable.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_ProjectMatchingRunRequests_Immutable
ON dbo.FundingPlatform_ProjectMatchingRunRequests
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted)
        THROW 52406, N'Matching idempotency requests are immutable.', 1;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_ProjectFundingMatches_SupersessionOnly
ON dbo.FundingPlatform_ProjectFundingMatches
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    IF EXISTS (SELECT 1 FROM deleted WHERE NOT EXISTS
               (SELECT 1 FROM inserted WHERE inserted.Id = deleted.Id))
       OR EXISTS
          (SELECT 1
           FROM inserted
           INNER JOIN deleted ON deleted.Id = inserted.Id
           WHERE deleted.IsCurrent <> 1 OR deleted.SupersededAtUtc IS NOT NULL
              OR inserted.IsCurrent <> 0 OR inserted.SupersededAtUtc IS NULL
              OR inserted.SupersededAtUtc < deleted.CalculatedAtUtc)
       OR EXISTS
          (SELECT Id, PublicId, OrganizationId, ProjectId, FundingOpportunityId,
                  MatchRunId, MatchingProfileId, ProjectVersion,
                  OrganizationProfileVersion, FundingContentVersion,
                  OpportunitySlug, OpportunityTitle, SponsorName, Currency,
                  MinAmount, MaxAmount, CloseDate, CloseAtUtc, DeadlinePrecision,
                  Classification, HardGateStatus, CompatibilityScore, RuleScore,
                  EvidenceCoverage, InputFingerprint, CalculatedAtUtc
           FROM inserted
           EXCEPT
           SELECT Id, PublicId, OrganizationId, ProjectId, FundingOpportunityId,
                  MatchRunId, MatchingProfileId, ProjectVersion,
                  OrganizationProfileVersion, FundingContentVersion,
                  OpportunitySlug, OpportunityTitle, SponsorName, Currency,
                  MinAmount, MaxAmount, CloseDate, CloseAtUtc, DeadlinePrecision,
                  Classification, HardGateStatus, CompatibilityScore, RuleScore,
                  EvidenceCoverage, InputFingerprint, CalculatedAtUtc
           FROM deleted)
       OR EXISTS
          (SELECT Id, PublicId, OrganizationId, ProjectId, FundingOpportunityId,
                  MatchRunId, MatchingProfileId, ProjectVersion,
                  OrganizationProfileVersion, FundingContentVersion,
                  OpportunitySlug, OpportunityTitle, SponsorName, Currency,
                  MinAmount, MaxAmount, CloseDate, CloseAtUtc, DeadlinePrecision,
                  Classification, HardGateStatus, CompatibilityScore, RuleScore,
                  EvidenceCoverage, InputFingerprint, CalculatedAtUtc
           FROM deleted
           EXCEPT
           SELECT Id, PublicId, OrganizationId, ProjectId, FundingOpportunityId,
                  MatchRunId, MatchingProfileId, ProjectVersion,
                  OrganizationProfileVersion, FundingContentVersion,
                  OpportunitySlug, OpportunityTitle, SponsorName, Currency,
                  MinAmount, MaxAmount, CloseDate, CloseAtUtc, DeadlinePrecision,
                  Classification, HardGateStatus, CompatibilityScore, RuleScore,
                  EvidenceCoverage, InputFingerprint, CalculatedAtUtc
           FROM inserted)
        THROW 52406, N'Project matches are immutable except for exact supersession.', 1;
END;
GO

/* One shared fail-closed definition of PublicReady + currently open. Unknown
   deadlines are deliberately excluded from recommendations. */
CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_ProjectMatchingOpenCandidates
(
    @NowUtc DATETIME2(3)
)
RETURNS TABLE
AS
RETURN
(
    SELECT opportunities.Id AS FundingOpportunityId,
           opportunities.PublicId AS FundingOpportunityPublicId,
           opportunities.ContentVersion,
           versions.ContentHash,
           opportunities.UpdatedAtUtc,
           opportunities.CloseDate,
           opportunities.CloseAtUtc,
           opportunities.DeadlinePrecision
    FROM dbo.FundingPlatform_FundingOpportunities AS opportunities
    INNER JOIN dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() AS ready
        ON ready.FundingOpportunityId = opportunities.Id
    INNER JOIN dbo.FundingPlatform_FundingOpportunityVersions AS versions
        ON versions.FundingOpportunityId = opportunities.Id
       AND versions.ContentVersion = opportunities.ContentVersion
    WHERE (opportunities.OpenDate IS NULL
           OR opportunities.OpenDate <= CONVERT(DATE, @NowUtc))
      AND
      (
          opportunities.DeadlineType = 2
          OR
          (opportunities.DeadlineType = 1 AND
           ((opportunities.DeadlinePrecision = 2
             AND opportunities.CloseAtUtc IS NOT NULL
             AND opportunities.CloseAtUtc > @NowUtc)
            OR
            (opportunities.DeadlinePrecision = 1
             AND opportunities.CloseDate IS NOT NULL
             AND opportunities.CloseDate >= CONVERT(DATE, @NowUtc))))
      )
);
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_ProjectMatchingCatalogState
(
    @NowUtc DATETIME2(3)
)
RETURNS TABLE
AS
RETURN
(
    SELECT CONVERT(INT, COUNT_BIG(1)) AS TotalCandidateCount,
           CONVERT(BINARY(32), HASHBYTES
           (
               'SHA2_256',
               CONVERT(VARBINARY(MAX), COALESCE
               (
                   STRING_AGG
                   (
                       CONVERT(NVARCHAR(MAX), CONCAT
                       (
                           candidates.FundingOpportunityId, N':',
                           candidates.ContentVersion, N':',
                           CONVERT(VARCHAR(64), candidates.ContentHash, 2), N':',
                           CONVERT(NVARCHAR(33), candidates.UpdatedAtUtc, 126)
                       )),
                       N'|'
                   ) WITHIN GROUP (ORDER BY candidates.FundingOpportunityId),
                   N'empty-public-open-catalog'
               ))
           )) AS CandidateSetFingerprint
    FROM dbo.FundingPlatform_ifn_ProjectMatchingOpenCandidates(@NowUtc) AS candidates
);
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_MatchingProfileRuleSetFingerprint
(
    @MatchingProfileId INT
)
RETURNS TABLE
AS
RETURN
(
    SELECT CONVERT(BINARY(32), HASHBYTES
    (
        'SHA2_256', CONVERT(VARBINARY(MAX), COALESCE
        (
            STRING_AGG(CONVERT(NVARCHAR(MAX), CONCAT
            (
                rules.Code, N':', rules.HandlerVersion, N':', rules.IsHardGate, N':',
                weights.Weight, N':', COALESCE(weights.ParametersJson, N'null')
            )), N'|') WITHIN GROUP (ORDER BY rules.Code, rules.HandlerVersion),
            N'empty-rule-set'
        ))
    )) AS RuleSetFingerprint
    FROM dbo.FundingPlatform_MatchingRuleWeights AS weights
    INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
        ON rules.Id = weights.MatchingRuleId
    WHERE weights.MatchingProfileId = @MatchingProfileId
);
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_ProjectMatchingRunSummaries
(
    @NowUtc DATETIME2(3)
)
RETURNS TABLE
AS
RETURN
(
    SELECT runs.Id AS MatchRunId,
           runs.OrganizationId,
           runs.ProjectId,
           runs.PublicId AS RunPublicId,
           projects.PublicId AS ProjectPublicId,
           runs.ProjectSlugSnapshot AS ProjectSlug,
           runs.ProjectTitleSnapshot AS ProjectTitle,
           runs.Status,
           runs.MatchingProfileCodeSnapshot AS MatchingProfileCode,
           runs.MatchingProfileVersionSnapshot AS MatchingProfileVersion,
           runs.EngineVersionSnapshot AS EngineVersion,
           runs.ProjectVersion,
           runs.OrganizationProfileVersion,
           runs.CandidateSetFingerprint,
           runs.CatalogSnapshotAtUtc,
           runs.TotalCandidateCount,
           runs.ProcessedCandidateCount,
           runs.CompatibleCount,
           runs.IncompatibleCount,
           runs.InsufficientDataCount,
           runs.IsTruncated,
           CONVERT(BIT, CASE
               WHEN projects.IsActive = 1 AND projects.PublicationStatus <> 4
                AND organizations.IsActive = 1
                AND projects.ProjectVersion = runs.ProjectVersion
                AND organizations.ProfileVersion = runs.OrganizationProfileVersion
                AND profiles.IsActive = 1 AND profiles.Status = 2
                AND currentRuleSet.RuleSetFingerprint = runs.RuleSetFingerprint
                AND runs.CalculationCalendarYear = DATEPART(YEAR, @NowUtc)
                AND catalog.CandidateSetFingerprint = runs.CandidateSetFingerprint
                AND NOT EXISTS
                    (SELECT 1
                     FROM dbo.FundingPlatform_ProjectMatchingRuns AS newerRuns
                     WHERE newerRuns.ProjectId = runs.ProjectId
                       AND newerRuns.Id > runs.Id)
               THEN 1 ELSE 0 END) AS IsCurrent,
           runs.StartedAtUtc,
           runs.CompletedAtUtc,
           runs.CreatedAtUtc
    FROM dbo.FundingPlatform_ProjectMatchingRuns AS runs
    INNER JOIN dbo.FundingPlatform_Projects AS projects ON projects.Id = runs.ProjectId
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = runs.OrganizationId
    INNER JOIN dbo.FundingPlatform_MatchingProfiles AS profiles
        ON profiles.Id = runs.MatchingProfileId
    CROSS APPLY dbo.FundingPlatform_ifn_MatchingProfileRuleSetFingerprint
        (runs.MatchingProfileId) AS currentRuleSet
    CROSS JOIN dbo.FundingPlatform_ifn_ProjectMatchingCatalogState(@NowUtc) AS catalog
);
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectMatchingRun_List
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @PageNumber INT = 1,
    @PageSize INT = 20,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;

    IF @PageNumber NOT BETWEEN 1 AND 10000
       OR @PageSize NOT BETWEEN 1 AND 50 OR @NowUtc IS NULL
        THROW 52402, N'The matching run page is invalid.', 1;

    DECLARE @OrganizationId BIGINT, @ProjectId BIGINT;
    SELECT @OrganizationId = organizations.Id, @ProjectId = projects.Id
    FROM dbo.FundingPlatform_Users AS users
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.UserId = users.Id AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = memberships.OrganizationId AND organizations.IsActive = 1
    INNER JOIN dbo.FundingPlatform_Projects AS projects
        ON projects.OrganizationId = organizations.Id
    WHERE users.PublicId = @UserPublicId AND users.Status = 2
      AND organizations.PublicId = @OrganizationPublicId
      AND projects.PublicId = @ProjectPublicId;

    IF @OrganizationId IS NULL OR @ProjectId IS NULL
        THROW 52401, N'The workspace resource was not found.', 1;

    SELECT COUNT_BIG(1) AS TotalCount
    FROM dbo.FundingPlatform_ProjectMatchingRuns
    WHERE OrganizationId = @OrganizationId AND ProjectId = @ProjectId;

    SELECT RunPublicId, ProjectPublicId, ProjectSlug, ProjectTitle, Status,
           MatchingProfileCode, MatchingProfileVersion, EngineVersion,
           ProjectVersion, OrganizationProfileVersion, CandidateSetFingerprint,
           CatalogSnapshotAtUtc, TotalCandidateCount, ProcessedCandidateCount,
           CompatibleCount, IncompatibleCount, InsufficientDataCount,
           IsTruncated, IsCurrent, CONVERT(BIT, 0) AS WasReplay,
           StartedAtUtc, CompletedAtUtc, CreatedAtUtc
    FROM dbo.FundingPlatform_ifn_ProjectMatchingRunSummaries(@NowUtc)
    WHERE OrganizationId = @OrganizationId AND ProjectId = @ProjectId
    ORDER BY CreatedAtUtc DESC, MatchRunId DESC
    OFFSET CONVERT(BIGINT, @PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectMatchingRun_Get
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @RunPublicId UNIQUEIDENTIFIER,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;

    IF @RunPublicId IS NULL OR @NowUtc IS NULL
        THROW 52402, N'The matching run identifier is invalid.', 1;

    DECLARE @OrganizationId BIGINT, @ProjectId BIGINT, @MatchRunId BIGINT;
    DECLARE @RunIsCurrent BIT;
    SELECT @OrganizationId = organizations.Id, @ProjectId = projects.Id
    FROM dbo.FundingPlatform_Users AS users
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.UserId = users.Id AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = memberships.OrganizationId AND organizations.IsActive = 1
    INNER JOIN dbo.FundingPlatform_Projects AS projects
        ON projects.OrganizationId = organizations.Id
    WHERE users.PublicId = @UserPublicId AND users.Status = 2
      AND organizations.PublicId = @OrganizationPublicId
      AND projects.PublicId = @ProjectPublicId;

    IF @OrganizationId IS NULL OR @ProjectId IS NULL
        THROW 52401, N'The workspace resource was not found.', 1;

    SELECT * INTO #RequestedRunSummary
    FROM dbo.FundingPlatform_ifn_ProjectMatchingRunSummaries(@NowUtc) AS summaries
    WHERE summaries.OrganizationId = @OrganizationId
      AND summaries.ProjectId = @ProjectId
      AND summaries.RunPublicId = @RunPublicId;

    SELECT @MatchRunId = summaries.MatchRunId,
           @RunIsCurrent = summaries.IsCurrent
    FROM #RequestedRunSummary AS summaries;

    IF @MatchRunId IS NULL
        THROW 52401, N'The workspace resource was not found.', 1;

    SELECT RunPublicId, ProjectPublicId, ProjectSlug, ProjectTitle, Status,
           MatchingProfileCode, MatchingProfileVersion, EngineVersion,
           ProjectVersion, OrganizationProfileVersion, CandidateSetFingerprint,
           CatalogSnapshotAtUtc, TotalCandidateCount, ProcessedCandidateCount,
           CompatibleCount, IncompatibleCount, InsufficientDataCount,
           IsTruncated, IsCurrent, CONVERT(BIT, 0) AS WasReplay,
           StartedAtUtc, CompletedAtUtc, CreatedAtUtc
    FROM #RequestedRunSummary;

    SELECT matches.PublicId AS MatchPublicId,
           opportunities.PublicId AS FundingOpportunityPublicId,
           matches.OpportunitySlug AS Slug,
           matches.OpportunityTitle AS Title,
           matches.SponsorName,
           matches.Currency,
           matches.MinAmount,
           matches.MaxAmount,
           matches.CloseDate,
           matches.CloseAtUtc,
           matches.DeadlinePrecision,
           matches.FundingContentVersion,
           matches.Classification,
           matches.HardGateStatus,
           matches.CompatibilityScore,
           matches.RuleScore,
           matches.EvidenceCoverage,
           CONVERT(BIT, @RunIsCurrent) AS IsCurrent,
           matches.CalculatedAtUtc
    FROM dbo.FundingPlatform_ProjectFundingMatches AS matches
    INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
        ON opportunities.Id = matches.FundingOpportunityId
    WHERE matches.MatchRunId = @MatchRunId
    ORDER BY CASE matches.Classification WHEN 0 THEN 0 WHEN 2 THEN 1 ELSE 2 END,
             CASE WHEN matches.CompatibilityScore IS NULL THEN 1 ELSE 0 END,
             matches.CompatibilityScore DESC,
             CASE WHEN matches.CloseDate IS NULL THEN 1 ELSE 0 END,
             matches.CloseDate,
             matches.FundingOpportunityId;

    SELECT matches.PublicId AS MatchPublicId,
           rules.Code AS RuleCode,
           rules.Name AS RuleName,
           rules.IsHardGate,
           results.Outcome,
           results.RawScore,
           results.DataState,
           results.AppliedWeight,
           results.WeightedPoints,
           results.ReasonCode,
           results.ReasonParametersJson,
           results.EvidenceJson,
           results.IsWarning
    FROM dbo.FundingPlatform_ProjectFundingMatches AS matches
    INNER JOIN dbo.FundingPlatform_ProjectFundingMatchRuleResults AS results
        ON results.MatchId = matches.Id
    INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
        ON rules.Id = results.MatchingRuleId
    WHERE matches.MatchRunId = @MatchRunId
    ORDER BY matches.Id, rules.IsHardGate DESC, rules.Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectMatchingRun_Create
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @ProjectPublicId UNIQUEIDENTIFIER,
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserPublicId IS NULL OR @OrganizationPublicId IS NULL OR @ProjectPublicId IS NULL
       OR @IdempotencyKeyHash IS NULL OR DATALENGTH(@IdempotencyKeyHash) <> 32
       OR @RequestHash IS NULL OR DATALENGTH(@RequestHash) <> 32
       OR @NowUtc IS NULL
        THROW 52402, N'The matching run request is invalid.', 1;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
    DECLARE @UserId BIGINT, @OrganizationId BIGINT, @ProjectId BIGINT;
    DECLARE @ProjectSlug NVARCHAR(180), @ProjectTitle NVARCHAR(250);
    DECLARE @ProjectIsActive BIT, @ProjectPublicationStatus TINYINT;
    DECLARE @ProjectVersion INT, @OrganizationProfileVersion INT;
    DECLARE @ProjectContentHash BINARY(32), @OrganizationContentHash BINARY(32);
    DECLARE @MatchingProfileId INT, @MatchingProfileCode NVARCHAR(100);
    DECLARE @MatchingProfileVersion INT, @EngineVersion NVARCHAR(50);
    DECLARE @RuleSetFingerprint BINARY(32);
    DECLARE @ExistingRequestHash BINARY(32), @MatchRunId BIGINT;
    DECLARE @WasReplay BIT = 0;

    IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
    ELSE SAVE TRANSACTION FP_ProjectMatchCreate;

    BEGIN TRY
        /* The project lock serializes two recalculations for the same tenant
           aggregate; callers never choose versions or opportunity IDs. */
        SELECT @UserId = users.Id,
               @OrganizationId = organizations.Id,
               @ProjectId = projects.Id,
               @ProjectSlug = projects.Slug,
               @ProjectTitle = projects.Title,
               @ProjectIsActive = projects.IsActive,
               @ProjectPublicationStatus = projects.PublicationStatus,
               @ProjectVersion = projects.ProjectVersion,
               @OrganizationProfileVersion = organizations.ProfileVersion
        FROM dbo.FundingPlatform_Users AS users
        INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
            ON memberships.UserId = users.Id AND memberships.MembershipStatus = 1
        INNER JOIN dbo.FundingPlatform_Organizations AS organizations WITH (HOLDLOCK)
            ON organizations.Id = memberships.OrganizationId AND organizations.IsActive = 1
        INNER JOIN dbo.FundingPlatform_Projects AS projects WITH (UPDLOCK, HOLDLOCK)
            ON projects.OrganizationId = organizations.Id
        WHERE users.PublicId = @UserPublicId AND users.Status = 2
          AND organizations.PublicId = @OrganizationPublicId
          AND projects.PublicId = @ProjectPublicId;

        IF @UserId IS NULL OR @OrganizationId IS NULL OR @ProjectId IS NULL
            THROW 52401, N'The workspace resource was not found.', 1;

        /* Durable replay is resolved before mutable project/profile/catalog
           readiness. Current membership and tenant identity are still required. */
        SELECT @ExistingRequestHash = requests.RequestHash,
               @MatchRunId = requests.MatchRunId
        FROM dbo.FundingPlatform_ProjectMatchingRunRequests AS requests WITH (UPDLOCK, HOLDLOCK)
        WHERE requests.UserId = @UserId
          AND requests.OrganizationId = @OrganizationId
          AND requests.ProjectId = @ProjectId
          AND requests.IdempotencyKeyHash = @IdempotencyKeyHash;

        IF @MatchRunId IS NOT NULL AND @ExistingRequestHash <> @RequestHash
            THROW 52403, N'The idempotency key was used with a different request.', 1;

        IF @MatchRunId IS NOT NULL
        BEGIN
            SET @WasReplay = 1;
            IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

            SELECT RunPublicId, ProjectPublicId, ProjectSlug, ProjectTitle, Status,
                   MatchingProfileCode, MatchingProfileVersion, EngineVersion,
                   ProjectVersion, OrganizationProfileVersion, CandidateSetFingerprint,
                   CatalogSnapshotAtUtc, TotalCandidateCount, ProcessedCandidateCount,
                   CompatibleCount, IncompatibleCount, InsufficientDataCount,
                   IsTruncated, IsCurrent, @WasReplay AS WasReplay,
                   StartedAtUtc, CompletedAtUtc, CreatedAtUtc
            FROM dbo.FundingPlatform_ifn_ProjectMatchingRunSummaries(@NowUtc)
            WHERE MatchRunId = @MatchRunId;
            RETURN;
        END;

        IF @ProjectIsActive <> 1 OR @ProjectPublicationStatus = 4
            THROW 52401, N'The workspace resource was not found.', 1;

        /* Expected identity/idempotency errors above preserve the caller's
           transaction mode. New calculations use atomic XACT_ABORT semantics. */
        SET XACT_ABORT ON;

        SELECT @ProjectContentHash = versions.ContentHash
        FROM dbo.FundingPlatform_ProjectVersions AS versions
        WHERE versions.ProjectId = @ProjectId
          AND versions.ProjectVersion = @ProjectVersion;
        SELECT @OrganizationContentHash = versions.ContentHash
        FROM dbo.FundingPlatform_OrganizationProfileVersions AS versions
        WHERE versions.OrganizationId = @OrganizationId
          AND versions.ProfileVersion = @OrganizationProfileVersion;

        IF @ProjectContentHash IS NULL OR @OrganizationContentHash IS NULL
            THROW 52404, N'The current version snapshots are unavailable.', 1;

        SELECT @MatchingProfileId = profiles.Id,
               @MatchingProfileCode = profiles.Code,
               @MatchingProfileVersion = profiles.Version,
               @EngineVersion = profiles.EngineVersion
        FROM dbo.FundingPlatform_MatchingProfiles AS profiles WITH (HOLDLOCK)
        WHERE profiles.IsActive = 1 AND profiles.Status = 2;

        IF @MatchingProfileId IS NULL
            THROW 52404, N'An active deterministic matching profile is unavailable.', 1;

        IF (SELECT COUNT_BIG(1)
            FROM dbo.FundingPlatform_MatchingRuleWeights AS weights
            WHERE weights.MatchingProfileId = @MatchingProfileId) <> 9
           OR (SELECT COUNT_BIG(1)
            FROM dbo.FundingPlatform_MatchingRuleWeights AS weights
            INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
                ON rules.Id = weights.MatchingRuleId AND rules.IsActive = 1
            WHERE weights.MatchingProfileId = @MatchingProfileId) <> 9
           OR (SELECT SUM(weights.Weight)
               FROM dbo.FundingPlatform_MatchingRuleWeights AS weights
               WHERE weights.MatchingProfileId = @MatchingProfileId) <> 100
           OR EXISTS
              (SELECT required.Code
               FROM (VALUES
                     (N'geography', CONVERT(DECIMAL(5,2), 20), CONVERT(BIT, 1)),
                     (N'organization_type', CONVERT(DECIMAL(5,2), 15), CONVERT(BIT, 1)),
                     (N'legal_entity', CONVERT(DECIMAL(5,2), 15), CONVERT(BIT, 1)),
                     (N'operating_years', CONVERT(DECIMAL(5,2), 10), CONVERT(BIT, 1)),
                     (N'prior_experience', CONVERT(DECIMAL(5,2), 10), CONVERT(BIT, 1)),
                     (N'categories', CONVERT(DECIMAL(5,2), 10), CONVERT(BIT, 0)),
                     (N'beneficiaries', CONVERT(DECIMAL(5,2), 5), CONVERT(BIT, 0)),
                     (N'project_type', CONVERT(DECIMAL(5,2), 5), CONVERT(BIT, 0)),
                     (N'amount', CONVERT(DECIMAL(5,2), 10), CONVERT(BIT, 0)))
                    AS required(Code, Weight, IsHardGate)
               WHERE NOT EXISTS
                    (SELECT 1
                     FROM dbo.FundingPlatform_MatchingRuleWeights AS weights
                     INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
                         ON rules.Id = weights.MatchingRuleId
                     WHERE weights.MatchingProfileId = @MatchingProfileId
                       AND rules.Code = required.Code
                       AND rules.HandlerVersion = N'v1'
                       AND rules.IsActive = 1
                       AND rules.IsHardGate = required.IsHardGate
                       AND weights.Weight = required.Weight))
            THROW 52404, N'The active deterministic matching profile is incomplete.', 1;

        SELECT @RuleSetFingerprint = state.RuleSetFingerprint
        FROM dbo.FundingPlatform_ifn_MatchingProfileRuleSetFingerprint
            (@MatchingProfileId) AS state;
        IF @RuleSetFingerprint IS NULL
            THROW 52404, N'The active deterministic matching profile is incomplete.', 1;

        /* Capture the whole eligible/open catalog once. The fingerprint covers
           all candidates, even those beyond the synchronous TOP (200). */
        SELECT candidates.FundingOpportunityId,
               candidates.FundingOpportunityPublicId,
               candidates.ContentVersion,
               candidates.ContentHash,
               candidates.UpdatedAtUtc,
               opportunities.Slug,
               opportunities.Title,
               opportunities.SponsorName,
               opportunities.Currency,
               opportunities.MinAmount,
               opportunities.MaxAmount,
               opportunities.AmountStatus,
               opportunities.CloseDate,
               opportunities.CloseAtUtc,
               opportunities.DeadlinePrecision,
               opportunities.GeographicScope,
               opportunities.MinimumOperatingYears,
               opportunities.RequiresLegalEntity,
               opportunities.RequiresPriorExperience,
               ROW_NUMBER() OVER
               (
                   ORDER BY CASE WHEN opportunities.CloseDate IS NULL THEN 1 ELSE 0 END,
                            opportunities.CloseDate,
                            CASE WHEN opportunities.CloseAtUtc IS NULL THEN 1 ELSE 0 END,
                            opportunities.CloseAtUtc,
                            opportunities.Id
               ) AS CandidateOrdinal
        INTO #AllCandidates
        FROM dbo.FundingPlatform_ifn_ProjectMatchingOpenCandidates(@NowUtc) AS candidates
        INNER JOIN dbo.FundingPlatform_FundingOpportunities AS opportunities
            ON opportunities.Id = candidates.FundingOpportunityId;

        DECLARE @TotalCandidateCount INT = (SELECT COUNT(1) FROM #AllCandidates);
        DECLARE @CandidateSetFingerprint BINARY(32) = CONVERT(BINARY(32), HASHBYTES
        (
            'SHA2_256',
            CONVERT(VARBINARY(MAX), COALESCE
            (
                (SELECT STRING_AGG
                    (CONVERT(NVARCHAR(MAX), CONCAT
                     (FundingOpportunityId, N':', ContentVersion, N':',
                      CONVERT(VARCHAR(64), ContentHash, 2), N':',
                      CONVERT(NVARCHAR(33), UpdatedAtUtc, 126))), N'|')
                 WITHIN GROUP (ORDER BY FundingOpportunityId)
                 FROM #AllCandidates),
                N'empty-public-open-catalog'
            ))
        ));
        DECLARE @CalculationCalendarYear SMALLINT = DATEPART(YEAR, @NowUtc);
        DECLARE @InputFingerprint BINARY(32) = CONVERT(BINARY(32), HASHBYTES
        (
            'SHA2_256', CONVERT(VARBINARY(MAX), CONCAT
            (
                N'project:', @ProjectId, N':', @ProjectVersion, N':',
                CONVERT(VARCHAR(64), @ProjectContentHash, 2),
                N'|organization:', @OrganizationId, N':', @OrganizationProfileVersion, N':',
                CONVERT(VARCHAR(64), @OrganizationContentHash, 2),
                N'|profile:', @MatchingProfileId, N':', @MatchingProfileCode, N':',
                @MatchingProfileVersion, N':', @EngineVersion, N':',
                CONVERT(VARCHAR(64), @RuleSetFingerprint, 2),
                N'|calendar-year:', @CalculationCalendarYear,
                N'|catalog:', CONVERT(VARCHAR(64), @CandidateSetFingerprint, 2)
            ))
        ));

        SELECT @MatchRunId = runs.Id
        FROM dbo.FundingPlatform_ProjectMatchingRuns AS runs WITH (UPDLOCK, HOLDLOCK)
        WHERE runs.ProjectId = @ProjectId
          AND runs.InputFingerprint = @InputFingerprint
          AND NOT EXISTS
              (SELECT 1
               FROM dbo.FundingPlatform_ProjectMatchingRuns AS newerRuns
               WHERE newerRuns.ProjectId = runs.ProjectId
                 AND newerRuns.Id > runs.Id);

        IF @MatchRunId IS NOT NULL
        BEGIN
            INSERT INTO dbo.FundingPlatform_ProjectMatchingRunRequests
                (UserId, OrganizationId, ProjectId, IdempotencyKeyHash,
                 RequestHash, MatchRunId, CreatedAtUtc)
            VALUES
                (@UserId, @OrganizationId, @ProjectId, @IdempotencyKeyHash,
                 @RequestHash, @MatchRunId, SYSUTCDATETIME());
            SET @WasReplay = 1;
            IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

            SELECT RunPublicId, ProjectPublicId, ProjectSlug, ProjectTitle, Status,
                   MatchingProfileCode, MatchingProfileVersion, EngineVersion,
                   ProjectVersion, OrganizationProfileVersion, CandidateSetFingerprint,
                   CatalogSnapshotAtUtc, TotalCandidateCount, ProcessedCandidateCount,
                   CompatibleCount, IncompatibleCount, InsufficientDataCount,
                   IsTruncated, IsCurrent, @WasReplay AS WasReplay,
                   StartedAtUtc, CompletedAtUtc, CreatedAtUtc
            FROM dbo.FundingPlatform_ifn_ProjectMatchingRunSummaries(@NowUtc)
            WHERE MatchRunId = @MatchRunId;
            RETURN;
        END;

        SELECT TOP (200) * INTO #Candidates
        FROM #AllCandidates
        ORDER BY CandidateOrdinal;
        CREATE UNIQUE CLUSTERED INDEX IX_Candidates_Opportunity
            ON #Candidates (FundingOpportunityId);
        DECLARE @ProcessedCandidateCount INT = (SELECT COUNT(1) FROM #Candidates);

        /* Hold the selected canonical rows until commit. Editorial writers and
           FK-backed relationship changes cannot interleave a new fact set with
           the version/hash captured above. */
        DECLARE @LockedCandidateCount INT;
        SELECT @LockedCandidateCount = COUNT(1)
        FROM dbo.FundingPlatform_FundingOpportunities AS opportunities WITH (HOLDLOCK)
        INNER JOIN #Candidates AS candidates
            ON candidates.FundingOpportunityId = opportunities.Id
           AND candidates.ContentVersion = opportunities.ContentVersion
           AND candidates.UpdatedAtUtc = opportunities.UpdatedAtUtc
        INNER JOIN dbo.FundingPlatform_FundingOpportunityVersions AS versions WITH (HOLDLOCK)
            ON versions.FundingOpportunityId = opportunities.Id
           AND versions.ContentVersion = opportunities.ContentVersion
           AND versions.ContentHash = candidates.ContentHash;

        IF @LockedCandidateCount <> @ProcessedCandidateCount
            THROW 52404, N'The candidate catalog changed while matching; retry the request.', 1;

        /* Materialize every N:N fact under serializable key-range locks. Rule
           statements below consume only these snapshots, never mutable child
           tables, so a run cannot mix two content versions. */
        SELECT links.FundingOpportunityId, links.CountryId
        INTO #CandidateCountries
        FROM dbo.FundingPlatform_FundingOpportunityCountries AS links WITH (HOLDLOCK)
        INNER JOIN #Candidates AS candidates
            ON candidates.FundingOpportunityId = links.FundingOpportunityId;
        SELECT links.FundingOpportunityId, links.RegionId
        INTO #CandidateRegions
        FROM dbo.FundingPlatform_FundingOpportunityRegions AS links WITH (HOLDLOCK)
        INNER JOIN #Candidates AS candidates
            ON candidates.FundingOpportunityId = links.FundingOpportunityId;
        SELECT links.FundingOpportunityId, links.OrganizationTypeId, links.EligibilityMode
        INTO #CandidateOrganizationTypes
        FROM dbo.FundingPlatform_FundingOpportunityOrganizationTypes AS links WITH (HOLDLOCK)
        INNER JOIN #Candidates AS candidates
            ON candidates.FundingOpportunityId = links.FundingOpportunityId;
        SELECT links.FundingOpportunityId, links.LegalEntityTypeId, links.EligibilityMode
        INTO #CandidateLegalEntityTypes
        FROM dbo.FundingPlatform_FundingOpportunityLegalEntityTypes AS links WITH (HOLDLOCK)
        INNER JOIN #Candidates AS candidates
            ON candidates.FundingOpportunityId = links.FundingOpportunityId;
        SELECT links.FundingOpportunityId, links.FundingCategoryId
        INTO #CandidateCategories
        FROM dbo.FundingPlatform_FundingOpportunityCategories AS links WITH (HOLDLOCK)
        INNER JOIN #Candidates AS candidates
            ON candidates.FundingOpportunityId = links.FundingOpportunityId;
        SELECT links.FundingOpportunityId, links.BeneficiaryTypeId
        INTO #CandidateBeneficiaryTypes
        FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes AS links WITH (HOLDLOCK)
        INNER JOIN #Candidates AS candidates
            ON candidates.FundingOpportunityId = links.FundingOpportunityId;
        SELECT links.FundingOpportunityId, links.ProjectTypeId
        INTO #CandidateProjectTypes
        FROM dbo.FundingPlatform_FundingOpportunityProjectTypes AS links WITH (HOLDLOCK)
        INNER JOIN #Candidates AS candidates
            ON candidates.FundingOpportunityId = links.FundingOpportunityId;

        SELECT links.CountryId INTO #MatchingProjectCountries
        FROM dbo.FundingPlatform_ProjectCountries AS links WITH (HOLDLOCK)
        WHERE links.ProjectId = @ProjectId;
        SELECT links.RegionId INTO #MatchingProjectRegions
        FROM dbo.FundingPlatform_ProjectRegions AS links WITH (HOLDLOCK)
        WHERE links.ProjectId = @ProjectId;
        SELECT links.FundingCategoryId INTO #MatchingProjectCategories
        FROM dbo.FundingPlatform_ProjectCategories AS links WITH (HOLDLOCK)
        WHERE links.ProjectId = @ProjectId;
        SELECT links.BeneficiaryTypeId INTO #MatchingProjectBeneficiaryTypes
        FROM dbo.FundingPlatform_ProjectBeneficiaryTypes AS links WITH (HOLDLOCK)
        WHERE links.ProjectId = @ProjectId;
        SELECT links.ProjectTypeId INTO #MatchingProjectTypes
        FROM dbo.FundingPlatform_ProjectProjectTypes AS links WITH (HOLDLOCK)
        WHERE links.ProjectId = @ProjectId;

        DECLARE @OrganizationTypeId SMALLINT, @LegalEntityTypeId SMALLINT;
        DECLARE @EstablishedYear SMALLINT, @PreviousFundingExperience TINYINT;
        SELECT @OrganizationTypeId = OrganizationTypeId,
               @LegalEntityTypeId = LegalEntityTypeId,
               @EstablishedYear = EstablishedYear,
               @PreviousFundingExperience = PreviousFundingExperience
        FROM dbo.FundingPlatform_Organizations
        WHERE Id = @OrganizationId;

        DECLARE @ProjectCurrency CHAR(3), @ProjectFundingGap DECIMAL(19,4);
        SELECT @ProjectCurrency = Currency, @ProjectFundingGap = FundingGap
        FROM dbo.FundingPlatform_Projects WHERE Id = @ProjectId;

        DECLARE @ProjectGeographyCount INT =
            (SELECT COUNT(1) FROM #MatchingProjectCountries)
            + (SELECT COUNT(1) FROM #MatchingProjectRegions);
        DECLARE @ProjectRegionCount INT =
            (SELECT COUNT(1) FROM #MatchingProjectRegions);
        DECLARE @ProjectCategoryCount INT =
            (SELECT COUNT(1) FROM #MatchingProjectCategories);
        DECLARE @ProjectBeneficiaryCount INT =
            (SELECT COUNT(1) FROM #MatchingProjectBeneficiaryTypes);
        DECLARE @ProjectTypeCount INT =
            (SELECT COUNT(1) FROM #MatchingProjectTypes);

        CREATE TABLE #RuleEvaluations
        (
            FundingOpportunityId BIGINT NOT NULL,
            RuleCode NVARCHAR(100) NOT NULL,
            Outcome TINYINT NOT NULL,
            RawScore DECIMAL(5,2) NULL,
            DataState TINYINT NOT NULL,
            ReasonCode NVARCHAR(100) NOT NULL,
            ReasonParametersJson NVARCHAR(MAX) NULL,
            EvidenceJson NVARCHAR(MAX) NULL,
            IsWarning BIT NOT NULL,
            PRIMARY KEY (FundingOpportunityId, RuleCode)
        );

        /* Geography hard gate: global, exact country/region overlap, explicit
           disjoint failure, or conservative unknown when granularity is absent. */
        INSERT INTO #RuleEvaluations
            (FundingOpportunityId, RuleCode, Outcome, RawScore, DataState,
             ReasonCode, ReasonParametersJson, EvidenceJson, IsWarning)
        SELECT candidates.FundingOpportunityId, N'geography', result.Outcome,
               CASE result.Outcome WHEN 0 THEN 100 WHEN 2 THEN 0 ELSE NULL END,
               CASE WHEN result.Outcome = 3 THEN 1 ELSE 0 END,
               result.ReasonCode,
               CASE WHEN result.MatchCount > 0
                    THEN CONCAT(N'{"matchCount":"', result.MatchCount, N'"}') END,
               CASE WHEN result.Outcome = 3 THEN NULL ELSE
                    N'{"source":"versioned-snapshots","fieldCode":"geography","valueCodes":["project-geography","opportunity-geography"]}' END,
               CONVERT(BIT, CASE WHEN result.Outcome IN (2, 3) THEN 1 ELSE 0 END)
        FROM #Candidates AS candidates
        OUTER APPLY
        (
            SELECT (SELECT COUNT(1)
                    FROM #CandidateCountries
                    WHERE FundingOpportunityId = candidates.FundingOpportunityId)
                 + (SELECT COUNT(1)
                    FROM #CandidateRegions
                    WHERE FundingOpportunityId = candidates.FundingOpportunityId) AS OpportunityGeoCount,
                   (SELECT COUNT(1)
                    FROM #CandidateCountries AS opportunityCountries
                    INNER JOIN #MatchingProjectCountries AS projectCountries
                        ON projectCountries.CountryId = opportunityCountries.CountryId
                    WHERE opportunityCountries.FundingOpportunityId = candidates.FundingOpportunityId) AS CountryMatches,
                   (SELECT COUNT(1)
                    FROM #CandidateRegions AS opportunityRegions
                    INNER JOIN #MatchingProjectRegions AS projectRegions
                        ON projectRegions.RegionId = opportunityRegions.RegionId
                    WHERE opportunityRegions.FundingOpportunityId = candidates.FundingOpportunityId) AS RegionMatches,
                   (SELECT COUNT(1)
                    FROM #CandidateRegions AS opportunityRegions
                    INNER JOIN dbo.FundingPlatform_Regions AS regions
                        ON regions.Id = opportunityRegions.RegionId
                    INNER JOIN #MatchingProjectCountries AS projectCountries
                        ON projectCountries.CountryId = regions.CountryId
                    WHERE opportunityRegions.FundingOpportunityId = candidates.FundingOpportunityId) AS CountryNeedsRegionDetail
        ) AS facts
        OUTER APPLY
        (
            SELECT CONVERT(TINYINT, CASE
                     WHEN candidates.GeographicScope = 2 THEN 0
                     WHEN candidates.GeographicScope <> 1 THEN 3
                     WHEN facts.OpportunityGeoCount = 0 THEN 3
                     WHEN @ProjectGeographyCount = 0 THEN 3
                     WHEN facts.RegionMatches + facts.CountryMatches > 0 THEN 0
                     WHEN facts.CountryNeedsRegionDetail > 0 AND @ProjectRegionCount = 0 THEN 3
                     ELSE 2 END) AS Outcome,
                   CASE
                     WHEN candidates.GeographicScope = 2 THEN N'geography.global'
                     WHEN candidates.GeographicScope <> 1 OR facts.OpportunityGeoCount = 0
                         THEN N'geography.missing_opportunity'
                     WHEN @ProjectGeographyCount = 0 THEN N'geography.missing_project'
                     WHEN facts.RegionMatches > 0 THEN N'geography.region_match'
                     WHEN facts.CountryMatches > 0 THEN N'geography.country_match'
                     WHEN facts.CountryNeedsRegionDetail > 0 AND @ProjectRegionCount = 0
                         THEN N'geography.missing_project'
                     ELSE N'geography.explicit_no_match' END AS ReasonCode,
                   facts.RegionMatches + facts.CountryMatches AS MatchCount
        ) AS result;

        /* Organization type hard gate. EligibilityMode 1 is allowed, 2 excluded. */
        INSERT INTO #RuleEvaluations
            (FundingOpportunityId, RuleCode, Outcome, RawScore, DataState,
             ReasonCode, ReasonParametersJson, EvidenceJson, IsWarning)
        SELECT candidates.FundingOpportunityId, N'organization_type', result.Outcome,
               CASE result.Outcome WHEN 0 THEN 100 WHEN 2 THEN 0 ELSE NULL END,
               CASE WHEN result.Outcome = 3 THEN 1 ELSE 0 END,
               result.ReasonCode, NULL,
               CASE WHEN result.Outcome = 3 THEN NULL ELSE
                    N'{"source":"versioned-snapshots","fieldCode":"organization_type","valueCodes":["organization-type","opportunity-organization-types"]}' END,
               CONVERT(BIT, CASE WHEN result.Outcome IN (2, 3) THEN 1 ELSE 0 END)
        FROM #Candidates AS candidates
        OUTER APPLY
        (
            SELECT COUNT(1) AS RuleCount,
                   COALESCE(SUM(CASE WHEN EligibilityMode = 1 THEN 1 ELSE 0 END), 0) AS AllowedCount,
                   COALESCE(SUM(CASE WHEN EligibilityMode = 1 AND OrganizationTypeId = @OrganizationTypeId THEN 1 ELSE 0 END), 0) AS AllowedMatch,
                   COALESCE(SUM(CASE WHEN EligibilityMode = 2 AND OrganizationTypeId = @OrganizationTypeId THEN 1 ELSE 0 END), 0) AS ExcludedMatch
            FROM #CandidateOrganizationTypes
            WHERE FundingOpportunityId = candidates.FundingOpportunityId
        ) AS facts
        OUTER APPLY
        (
            SELECT CONVERT(TINYINT, CASE
                       WHEN facts.RuleCount = 0 THEN 3
                       WHEN facts.ExcludedMatch > 0 THEN 2
                       WHEN facts.AllowedCount > 0 AND facts.AllowedMatch = 0 THEN 2
                       ELSE 0 END) AS Outcome,
                   CASE
                       WHEN facts.RuleCount = 0 THEN N'organization_type.missing_opportunity'
                       WHEN facts.ExcludedMatch > 0 THEN N'organization_type.excluded'
                       WHEN facts.AllowedCount > 0 AND facts.AllowedMatch = 0
                           THEN N'organization_type.not_allowed'
                       WHEN facts.AllowedMatch > 0 THEN N'organization_type.allowed'
                       ELSE N'organization_type.not_restricted' END AS ReasonCode
        ) AS result;

        /* Legal entity hard gate keeps requirement and explicit allow/exclude
           lists separate. An absent requirement is not guessed. */
        INSERT INTO #RuleEvaluations
            (FundingOpportunityId, RuleCode, Outcome, RawScore, DataState,
             ReasonCode, ReasonParametersJson, EvidenceJson, IsWarning)
        SELECT candidates.FundingOpportunityId, N'legal_entity', result.Outcome,
               CASE result.Outcome WHEN 0 THEN 100 WHEN 2 THEN 0 ELSE NULL END,
               CASE WHEN result.Outcome = 3 THEN 1
                    WHEN result.ReasonCode = N'legal_entity.not_required' THEN 2 ELSE 0 END,
               result.ReasonCode, NULL,
               CASE WHEN result.Outcome = 3 THEN NULL ELSE
                    N'{"source":"versioned-snapshots","fieldCode":"legal_entity","valueCodes":["organization-legal-entity","opportunity-legal-entity-requirement"]}' END,
               CONVERT(BIT, CASE WHEN result.Outcome IN (2, 3) THEN 1 ELSE 0 END)
        FROM #Candidates AS candidates
        OUTER APPLY
        (
            SELECT COUNT(1) AS RuleCount,
                   COALESCE(SUM(CASE WHEN EligibilityMode = 1 THEN 1 ELSE 0 END), 0) AS AllowedCount,
                   COALESCE(SUM(CASE WHEN EligibilityMode = 1 AND LegalEntityTypeId = @LegalEntityTypeId THEN 1 ELSE 0 END), 0) AS AllowedMatch,
                   COALESCE(SUM(CASE WHEN EligibilityMode = 2 AND LegalEntityTypeId = @LegalEntityTypeId THEN 1 ELSE 0 END), 0) AS ExcludedMatch
            FROM #CandidateLegalEntityTypes
            WHERE FundingOpportunityId = candidates.FundingOpportunityId
        ) AS facts
        OUTER APPLY
        (
            SELECT CONVERT(TINYINT, CASE
                       WHEN facts.RuleCount > 0 AND @LegalEntityTypeId IS NULL THEN 3
                       WHEN facts.ExcludedMatch > 0 THEN 2
                       WHEN facts.AllowedCount > 0 AND facts.AllowedMatch = 0 THEN 2
                       WHEN facts.RuleCount > 0 THEN 0
                       WHEN candidates.RequiresLegalEntity = 0 THEN 0
                       WHEN candidates.RequiresLegalEntity IS NULL THEN 3
                       WHEN @LegalEntityTypeId IS NULL THEN 3
                       ELSE 0 END) AS Outcome,
                   CASE
                       WHEN facts.RuleCount > 0 AND @LegalEntityTypeId IS NULL
                           THEN N'legal_entity.missing_organization'
                       WHEN facts.ExcludedMatch > 0 THEN N'legal_entity.excluded'
                       WHEN facts.AllowedCount > 0 AND facts.AllowedMatch = 0
                           THEN N'legal_entity.not_allowed'
                       WHEN facts.AllowedMatch > 0 THEN N'legal_entity.allowed'
                       WHEN facts.RuleCount > 0 THEN N'legal_entity.present'
                       WHEN candidates.RequiresLegalEntity = 0 THEN N'legal_entity.not_required'
                       WHEN candidates.RequiresLegalEntity IS NULL
                           THEN N'legal_entity.missing_opportunity'
                       WHEN @LegalEntityTypeId IS NULL THEN N'legal_entity.missing_organization'
                       ELSE N'legal_entity.present' END AS ReasonCode
        ) AS result;

        /* EstablishedYear is not an anniversary date. A pass/fail is emitted
           only outside the one-year uncertainty boundary. */
        INSERT INTO #RuleEvaluations
            (FundingOpportunityId, RuleCode, Outcome, RawScore, DataState,
             ReasonCode, ReasonParametersJson, EvidenceJson, IsWarning)
        SELECT candidates.FundingOpportunityId, N'operating_years', result.Outcome,
               CASE result.Outcome WHEN 0 THEN 100 WHEN 2 THEN 0 ELSE NULL END,
               CASE WHEN result.Outcome = 3 THEN 1
                    WHEN result.ReasonCode = N'operating_years.not_required' THEN 2 ELSE 0 END,
               result.ReasonCode,
               CASE WHEN candidates.MinimumOperatingYears > 0 AND @EstablishedYear IS NOT NULL
                    THEN CONCAT(N'{"minimumGuaranteedYears":"', ages.MinimumGuaranteedYears,
                                N'","maximumPossibleYears":"', ages.MaximumPossibleYears,
                                N'","requiredYears":"', candidates.MinimumOperatingYears, N'"}') END,
               CASE WHEN result.Outcome = 3 THEN NULL ELSE
                    N'{"source":"versioned-snapshots","fieldCode":"operating_years","valueCodes":["organization-established-year","opportunity-minimum-years"]}' END,
               CONVERT(BIT, CASE WHEN result.Outcome IN (2, 3) THEN 1 ELSE 0 END)
        FROM #Candidates AS candidates
        OUTER APPLY
        (
            SELECT CASE WHEN @EstablishedYear IS NULL OR @EstablishedYear > @CalculationCalendarYear
                        THEN NULL
                        WHEN @CalculationCalendarYear - @EstablishedYear - 1 < 0 THEN 0
                        ELSE @CalculationCalendarYear - @EstablishedYear - 1 END AS MinimumGuaranteedYears,
                   CASE WHEN @EstablishedYear IS NULL OR @EstablishedYear > @CalculationCalendarYear
                        THEN NULL
                        ELSE @CalculationCalendarYear - @EstablishedYear END AS MaximumPossibleYears
        ) AS ages
        OUTER APPLY
        (
            SELECT CONVERT(TINYINT, CASE
                       WHEN candidates.MinimumOperatingYears = 0 THEN 0
                       WHEN candidates.MinimumOperatingYears IS NULL THEN 3
                       WHEN ages.MinimumGuaranteedYears IS NULL THEN 3
                       WHEN ages.MinimumGuaranteedYears >= candidates.MinimumOperatingYears THEN 0
                       WHEN ages.MaximumPossibleYears < candidates.MinimumOperatingYears THEN 2
                       ELSE 3 END) AS Outcome,
                   CASE
                       WHEN candidates.MinimumOperatingYears = 0
                           THEN N'operating_years.not_required'
                       WHEN candidates.MinimumOperatingYears IS NULL
                           THEN N'operating_years.missing_opportunity'
                       WHEN ages.MinimumGuaranteedYears IS NULL
                           THEN N'operating_years.missing_organization'
                       WHEN ages.MinimumGuaranteedYears >= candidates.MinimumOperatingYears
                           THEN N'operating_years.meets'
                       WHEN ages.MaximumPossibleYears < candidates.MinimumOperatingYears
                           THEN N'operating_years.minimum_not_met'
                       ELSE N'operating_years.boundary_unknown' END AS ReasonCode
        ) AS result;

        /* PreviousFundingExperience: 0 Unknown, 1 None, 2 HasExperience. */
        INSERT INTO #RuleEvaluations
            (FundingOpportunityId, RuleCode, Outcome, RawScore, DataState,
             ReasonCode, ReasonParametersJson, EvidenceJson, IsWarning)
        SELECT candidates.FundingOpportunityId, N'prior_experience', result.Outcome,
               CASE result.Outcome WHEN 0 THEN 100 WHEN 2 THEN 0 ELSE NULL END,
               CASE WHEN result.Outcome = 3 THEN 1
                    WHEN result.ReasonCode = N'prior_experience.not_required' THEN 2 ELSE 0 END,
               result.ReasonCode, NULL,
               CASE WHEN result.Outcome = 3 THEN NULL ELSE
                    N'{"source":"versioned-snapshots","fieldCode":"prior_experience","valueCodes":["organization-funding-experience","opportunity-prior-experience-requirement"]}' END,
               CONVERT(BIT, CASE WHEN result.Outcome IN (2, 3) THEN 1 ELSE 0 END)
        FROM #Candidates AS candidates
        OUTER APPLY
        (
            SELECT CONVERT(TINYINT, CASE
                       WHEN candidates.RequiresPriorExperience = 0 THEN 0
                       WHEN candidates.RequiresPriorExperience IS NULL THEN 3
                       WHEN @PreviousFundingExperience = 0 THEN 3
                       WHEN @PreviousFundingExperience = 1 THEN 2
                       ELSE 0 END) AS Outcome,
                   CASE
                       WHEN candidates.RequiresPriorExperience = 0
                           THEN N'prior_experience.not_required'
                       WHEN candidates.RequiresPriorExperience IS NULL
                           THEN N'prior_experience.missing_opportunity'
                       WHEN @PreviousFundingExperience = 0
                           THEN N'prior_experience.missing_organization'
                       WHEN @PreviousFundingExperience = 1
                           THEN N'prior_experience.no_experience'
                       ELSE N'prior_experience.has_experience' END AS ReasonCode
        ) AS result;

        /* Three project-first taxonomy overlaps. Missing data is Unknown, not
           a fabricated negative or a renormalized score. */
        INSERT INTO #RuleEvaluations
            (FundingOpportunityId, RuleCode, Outcome, RawScore, DataState,
             ReasonCode, ReasonParametersJson, EvidenceJson, IsWarning)
        SELECT candidates.FundingOpportunityId, N'categories', result.Outcome,
               CASE result.Outcome WHEN 0 THEN 100 WHEN 2 THEN 0 ELSE NULL END,
               CASE WHEN result.Outcome = 3 THEN 1 ELSE 0 END,
               result.ReasonCode,
               CASE WHEN facts.MatchCount > 0
                    THEN CONCAT(N'{"matchCount":"', facts.MatchCount, N'"}') END,
               CASE WHEN result.Outcome = 3 THEN NULL ELSE
                    N'{"source":"versioned-snapshots","fieldCode":"categories","valueCodes":["project-categories","opportunity-categories"]}' END,
               CONVERT(BIT, CASE WHEN result.Outcome IN (2, 3) THEN 1 ELSE 0 END)
        FROM #Candidates AS candidates
        OUTER APPLY
        (
            SELECT (SELECT COUNT(1)
                    FROM #CandidateCategories
                    WHERE FundingOpportunityId = candidates.FundingOpportunityId) AS OpportunityCount,
                   (SELECT COUNT(1)
                    FROM #CandidateCategories AS opportunityLinks
                    INNER JOIN #MatchingProjectCategories AS projectLinks
                        ON projectLinks.FundingCategoryId = opportunityLinks.FundingCategoryId
                    WHERE opportunityLinks.FundingOpportunityId = candidates.FundingOpportunityId) AS MatchCount
        ) AS facts
        OUTER APPLY
        (
            SELECT CONVERT(TINYINT, CASE WHEN @ProjectCategoryCount = 0 THEN 3
                       WHEN facts.OpportunityCount = 0 THEN 3
                       WHEN facts.MatchCount > 0 THEN 0 ELSE 2 END) AS Outcome,
                   CASE WHEN @ProjectCategoryCount = 0 THEN N'categories.missing_project'
                       WHEN facts.OpportunityCount = 0 THEN N'categories.missing_opportunity'
                       WHEN facts.MatchCount > 0 THEN N'categories.match'
                       ELSE N'categories.no_match' END AS ReasonCode
        ) AS result;

        INSERT INTO #RuleEvaluations
            (FundingOpportunityId, RuleCode, Outcome, RawScore, DataState,
             ReasonCode, ReasonParametersJson, EvidenceJson, IsWarning)
        SELECT candidates.FundingOpportunityId, N'beneficiaries', result.Outcome,
               CASE result.Outcome WHEN 0 THEN 100 WHEN 2 THEN 0 ELSE NULL END,
               CASE WHEN result.Outcome = 3 THEN 1 ELSE 0 END,
               result.ReasonCode,
               CASE WHEN facts.MatchCount > 0
                    THEN CONCAT(N'{"matchCount":"', facts.MatchCount, N'"}') END,
               CASE WHEN result.Outcome = 3 THEN NULL ELSE
                    N'{"source":"versioned-snapshots","fieldCode":"beneficiaries","valueCodes":["project-beneficiaries","opportunity-beneficiaries"]}' END,
               CONVERT(BIT, CASE WHEN result.Outcome IN (2, 3) THEN 1 ELSE 0 END)
        FROM #Candidates AS candidates
        OUTER APPLY
        (
            SELECT (SELECT COUNT(1)
                    FROM #CandidateBeneficiaryTypes
                    WHERE FundingOpportunityId = candidates.FundingOpportunityId) AS OpportunityCount,
                   (SELECT COUNT(1)
                    FROM #CandidateBeneficiaryTypes AS opportunityLinks
                    INNER JOIN #MatchingProjectBeneficiaryTypes AS projectLinks
                        ON projectLinks.BeneficiaryTypeId = opportunityLinks.BeneficiaryTypeId
                    WHERE opportunityLinks.FundingOpportunityId = candidates.FundingOpportunityId) AS MatchCount
        ) AS facts
        OUTER APPLY
        (
            SELECT CONVERT(TINYINT, CASE WHEN @ProjectBeneficiaryCount = 0 THEN 3
                       WHEN facts.OpportunityCount = 0 THEN 3
                       WHEN facts.MatchCount > 0 THEN 0 ELSE 2 END) AS Outcome,
                   CASE WHEN @ProjectBeneficiaryCount = 0 THEN N'beneficiaries.missing_project'
                       WHEN facts.OpportunityCount = 0 THEN N'beneficiaries.missing_opportunity'
                       WHEN facts.MatchCount > 0 THEN N'beneficiaries.match'
                       ELSE N'beneficiaries.no_match' END AS ReasonCode
        ) AS result;

        INSERT INTO #RuleEvaluations
            (FundingOpportunityId, RuleCode, Outcome, RawScore, DataState,
             ReasonCode, ReasonParametersJson, EvidenceJson, IsWarning)
        SELECT candidates.FundingOpportunityId, N'project_type', result.Outcome,
               CASE result.Outcome WHEN 0 THEN 100 WHEN 2 THEN 0 ELSE NULL END,
               CASE WHEN result.Outcome = 3 THEN 1 ELSE 0 END,
               result.ReasonCode,
               CASE WHEN facts.MatchCount > 0
                    THEN CONCAT(N'{"matchCount":"', facts.MatchCount, N'"}') END,
               CASE WHEN result.Outcome = 3 THEN NULL ELSE
                    N'{"source":"versioned-snapshots","fieldCode":"project_type","valueCodes":["project-types","opportunity-project-types"]}' END,
               CONVERT(BIT, CASE WHEN result.Outcome IN (2, 3) THEN 1 ELSE 0 END)
        FROM #Candidates AS candidates
        OUTER APPLY
        (
            SELECT (SELECT COUNT(1)
                    FROM #CandidateProjectTypes
                    WHERE FundingOpportunityId = candidates.FundingOpportunityId) AS OpportunityCount,
                   (SELECT COUNT(1)
                    FROM #CandidateProjectTypes AS opportunityLinks
                    INNER JOIN #MatchingProjectTypes AS projectLinks
                        ON projectLinks.ProjectTypeId = opportunityLinks.ProjectTypeId
                    WHERE opportunityLinks.FundingOpportunityId = candidates.FundingOpportunityId) AS MatchCount
        ) AS facts
        OUTER APPLY
        (
            SELECT CONVERT(TINYINT, CASE WHEN @ProjectTypeCount = 0 THEN 3
                       WHEN facts.OpportunityCount = 0 THEN 3
                       WHEN facts.MatchCount > 0 THEN 0 ELSE 2 END) AS Outcome,
                   CASE WHEN @ProjectTypeCount = 0 THEN N'project_type.missing_project'
                       WHEN facts.OpportunityCount = 0 THEN N'project_type.missing_opportunity'
                       WHEN facts.MatchCount > 0 THEN N'project_type.match'
                       ELSE N'project_type.no_match' END AS ReasonCode
        ) AS result;

        /* Amount never invents an exchange rate. Above-max is partial because
           the opportunity can fund part of a positive gap; below-min is known no-match. */
        INSERT INTO #RuleEvaluations
            (FundingOpportunityId, RuleCode, Outcome, RawScore, DataState,
             ReasonCode, ReasonParametersJson, EvidenceJson, IsWarning)
        SELECT candidates.FundingOpportunityId, N'amount', result.Outcome,
               CASE result.Outcome WHEN 0 THEN 100 WHEN 1 THEN 50
                    WHEN 2 THEN 0 ELSE NULL END,
               CASE WHEN result.Outcome = 3 THEN 1 ELSE 0 END,
               result.ReasonCode,
               CASE WHEN result.ReasonCode = N'amount.currency_mismatch'
                    THEN CONCAT(N'{"projectCurrency":"', RTRIM(@ProjectCurrency),
                                N'","opportunityCurrency":"', RTRIM(candidates.Currency), N'"}') END,
               CASE WHEN result.Outcome = 3 THEN NULL ELSE
                    N'{"source":"versioned-snapshots","fieldCode":"amount","valueCodes":["project-funding-gap","opportunity-amount-range"]}' END,
               CONVERT(BIT, CASE WHEN result.Outcome <> 0 THEN 1 ELSE 0 END)
        FROM #Candidates AS candidates
        OUTER APPLY
        (
            SELECT CONVERT(TINYINT, CASE
                       WHEN @ProjectFundingGap IS NULL OR @ProjectCurrency IS NULL THEN 3
                       WHEN candidates.AmountStatus <> 1 OR candidates.Currency IS NULL
                            OR (candidates.MinAmount IS NULL AND candidates.MaxAmount IS NULL) THEN 3
                       WHEN candidates.Currency <> @ProjectCurrency THEN 3
                       WHEN candidates.MinAmount IS NOT NULL
                            AND @ProjectFundingGap < candidates.MinAmount THEN 2
                       WHEN candidates.MaxAmount IS NOT NULL
                            AND @ProjectFundingGap > candidates.MaxAmount THEN 1
                       ELSE 0 END) AS Outcome,
                   CASE
                       WHEN @ProjectFundingGap IS NULL OR @ProjectCurrency IS NULL
                           THEN N'amount.missing_project'
                       WHEN candidates.AmountStatus <> 1 OR candidates.Currency IS NULL
                            OR (candidates.MinAmount IS NULL AND candidates.MaxAmount IS NULL)
                           THEN N'amount.missing_opportunity'
                       WHEN candidates.Currency <> @ProjectCurrency
                           THEN N'amount.currency_mismatch'
                       WHEN candidates.MinAmount IS NOT NULL
                            AND @ProjectFundingGap < candidates.MinAmount
                           THEN N'amount.below_min'
                       WHEN candidates.MaxAmount IS NOT NULL
                            AND @ProjectFundingGap > candidates.MaxAmount
                           THEN N'amount.above_max_partial'
                       ELSE N'amount.within_range' END AS ReasonCode
        ) AS result;

        IF (SELECT COUNT_BIG(1) FROM #RuleEvaluations)
           <> CONVERT(BIGINT, @ProcessedCandidateCount) * 9
            THROW 52404, N'The deterministic rule evaluation was incomplete.', 1;

        SELECT evaluations.FundingOpportunityId,
               CONVERT(TINYINT, CASE
                   WHEN SUM(CASE WHEN rules.IsHardGate = 1 AND evaluations.Outcome = 2 THEN 1 ELSE 0 END) > 0 THEN 1
                   WHEN SUM(CASE WHEN rules.IsHardGate = 1 AND evaluations.Outcome = 3 THEN 1 ELSE 0 END) > 0 THEN 2
                   ELSE 0 END) AS Classification,
               CONVERT(TINYINT, CASE
                   WHEN SUM(CASE WHEN rules.IsHardGate = 1 AND evaluations.Outcome = 2 THEN 1 ELSE 0 END) > 0 THEN 1
                   WHEN SUM(CASE WHEN rules.IsHardGate = 1 AND evaluations.Outcome = 3 THEN 1 ELSE 0 END) > 0 THEN 2
                   ELSE 0 END) AS HardGateStatus,
               CONVERT(DECIMAL(5,2), SUM
               (
                   CONVERT(DECIMAL(7,4), weights.Weight
                       * CASE WHEN evaluations.Outcome = 3 THEN 0 ELSE evaluations.RawScore END / 100.0)
               )) AS RuleScore,
               CONVERT(DECIMAL(5,2), SUM
               (
                   CASE WHEN evaluations.DataState = 1 THEN 0 ELSE weights.Weight END
               )) AS EvidenceCoverage
        INTO #MatchScores
        FROM #RuleEvaluations AS evaluations
        INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
            ON rules.Code = evaluations.RuleCode AND rules.HandlerVersion = N'v1'
        INNER JOIN dbo.FundingPlatform_MatchingRuleWeights AS weights
            ON weights.MatchingProfileId = @MatchingProfileId
           AND weights.MatchingRuleId = rules.Id
        GROUP BY evaluations.FundingOpportunityId;

        DECLARE @CompatibleCount INT =
            (SELECT COUNT(1) FROM #MatchScores WHERE Classification = 0);
        DECLARE @IncompatibleCount INT =
            (SELECT COUNT(1) FROM #MatchScores WHERE Classification = 1);
        DECLARE @InsufficientDataCount INT =
            (SELECT COUNT(1) FROM #MatchScores WHERE Classification = 2);
        DECLARE @StartedAtUtc DATETIME2(3) = SYSUTCDATETIME();
        DECLARE @CompletedAtUtc DATETIME2(3) = SYSUTCDATETIME();

        /* The full catalog, including rows beyond TOP (200), must still be the
           set used by the input fingerprint immediately before persistence. */
        DECLARE @CurrentCandidateCount INT, @CurrentCandidateSetFingerprint BINARY(32);
        SELECT @CurrentCandidateCount = state.TotalCandidateCount,
               @CurrentCandidateSetFingerprint = state.CandidateSetFingerprint
        FROM dbo.FundingPlatform_ifn_ProjectMatchingCatalogState(@NowUtc) AS state;
        IF @CurrentCandidateCount <> @TotalCandidateCount
           OR @CurrentCandidateSetFingerprint <> @CandidateSetFingerprint
            THROW 52404, N'The candidate catalog changed while matching; retry the request.', 1;

        INSERT INTO dbo.FundingPlatform_ProjectMatchingRuns
            (OrganizationId, ProjectId, ProjectSlugSnapshot, ProjectTitleSnapshot,
             MatchingProfileId,
             MatchingProfileCodeSnapshot, MatchingProfileVersionSnapshot,
             EngineVersionSnapshot, RuleSetFingerprint, ProjectVersion,
             OrganizationProfileVersion, InputFingerprint, CandidateSetFingerprint,
             CatalogSnapshotAtUtc, CalculationCalendarYear, TotalCandidateCount,
             ProcessedCandidateCount, CompatibleCount, IncompatibleCount,
             InsufficientDataCount, IsTruncated, Status, StartedAtUtc,
             CompletedAtUtc, CreatedAtUtc)
        VALUES
            (@OrganizationId, @ProjectId, @ProjectSlug, @ProjectTitle,
             @MatchingProfileId,
             @MatchingProfileCode, @MatchingProfileVersion,
             @EngineVersion, @RuleSetFingerprint, @ProjectVersion,
             @OrganizationProfileVersion, @InputFingerprint, @CandidateSetFingerprint,
             @NowUtc, @CalculationCalendarYear, @TotalCandidateCount,
             @ProcessedCandidateCount, @CompatibleCount, @IncompatibleCount,
             @InsufficientDataCount,
             CONVERT(BIT, CASE WHEN @TotalCandidateCount > @ProcessedCandidateCount THEN 1 ELSE 0 END),
             2, @StartedAtUtc, @CompletedAtUtc, @StartedAtUtc);
        SET @MatchRunId = SCOPE_IDENTITY();

        UPDATE dbo.FundingPlatform_ProjectFundingMatches
        SET IsCurrent = 0, SupersededAtUtc = @CompletedAtUtc
        WHERE ProjectId = @ProjectId AND IsCurrent = 1;

        INSERT INTO dbo.FundingPlatform_ProjectFundingMatches
            (OrganizationId, ProjectId, FundingOpportunityId, MatchRunId,
             MatchingProfileId, ProjectVersion, OrganizationProfileVersion,
             FundingContentVersion, OpportunitySlug, OpportunityTitle, SponsorName,
             Currency, MinAmount, MaxAmount, CloseDate, CloseAtUtc, DeadlinePrecision,
             Classification, HardGateStatus, CompatibilityScore, RuleScore,
             EvidenceCoverage, InputFingerprint, IsCurrent, CalculatedAtUtc, SupersededAtUtc)
        SELECT @OrganizationId, @ProjectId, candidates.FundingOpportunityId, @MatchRunId,
               @MatchingProfileId, @ProjectVersion, @OrganizationProfileVersion,
               candidates.ContentVersion, candidates.Slug, candidates.Title,
               candidates.SponsorName, candidates.Currency, candidates.MinAmount,
               candidates.MaxAmount, candidates.CloseDate, candidates.CloseAtUtc,
               candidates.DeadlinePrecision, scores.Classification, scores.HardGateStatus,
               CASE WHEN scores.Classification = 1 THEN NULL ELSE scores.RuleScore END,
               scores.RuleScore, scores.EvidenceCoverage, @InputFingerprint, 1,
               @CompletedAtUtc, NULL
        FROM #Candidates AS candidates
        INNER JOIN #MatchScores AS scores
            ON scores.FundingOpportunityId = candidates.FundingOpportunityId;

        INSERT INTO dbo.FundingPlatform_ProjectFundingMatchRuleResults
            (MatchId, MatchingRuleId, Outcome, RawScore, DataState, EffectiveScore,
             AppliedWeight, WeightedPoints, ReasonCode, ReasonParametersJson,
             EvidenceJson, IsWarning)
        SELECT matches.Id, rules.Id, evaluations.Outcome, evaluations.RawScore,
               evaluations.DataState,
               CONVERT(DECIMAL(5,2), CASE WHEN evaluations.Outcome = 3
                                          THEN 0 ELSE evaluations.RawScore END),
               weights.Weight,
               CONVERT(DECIMAL(7,4), weights.Weight
                   * CASE WHEN evaluations.Outcome = 3 THEN 0 ELSE evaluations.RawScore END / 100.0),
               evaluations.ReasonCode, evaluations.ReasonParametersJson,
               evaluations.EvidenceJson, evaluations.IsWarning
        FROM #RuleEvaluations AS evaluations
        INNER JOIN dbo.FundingPlatform_MatchingRules AS rules
            ON rules.Code = evaluations.RuleCode AND rules.HandlerVersion = N'v1'
        INNER JOIN dbo.FundingPlatform_MatchingRuleWeights AS weights
            ON weights.MatchingProfileId = @MatchingProfileId
           AND weights.MatchingRuleId = rules.Id
        INNER JOIN dbo.FundingPlatform_ProjectFundingMatches AS matches
            ON matches.MatchRunId = @MatchRunId
           AND matches.FundingOpportunityId = evaluations.FundingOpportunityId;

        INSERT INTO dbo.FundingPlatform_ProjectMatchingRunRequests
            (UserId, OrganizationId, ProjectId, IdempotencyKeyHash,
             RequestHash, MatchRunId, CreatedAtUtc)
        VALUES
            (@UserId, @OrganizationId, @ProjectId, @IdempotencyKeyHash,
             @RequestHash, @MatchRunId, @CompletedAtUtc);

        IF @InitialTransactionCount = 0 COMMIT TRANSACTION;

        SELECT RunPublicId, ProjectPublicId, ProjectSlug, ProjectTitle, Status,
               MatchingProfileCode, MatchingProfileVersion, EngineVersion,
               ProjectVersion, OrganizationProfileVersion, CandidateSetFingerprint,
               CatalogSnapshotAtUtc, TotalCandidateCount, ProcessedCandidateCount,
               CompatibleCount, IncompatibleCount, InsufficientDataCount,
               IsTruncated, IsCurrent, @WasReplay AS WasReplay,
               StartedAtUtc, CompletedAtUtc, CreatedAtUtc
        FROM dbo.FundingPlatform_ifn_ProjectMatchingRunSummaries(@NowUtc)
        WHERE MatchRunId = @MatchRunId;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
            ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_ProjectMatchCreate;
        END;
        THROW;
    END CATCH;
END;
GO
