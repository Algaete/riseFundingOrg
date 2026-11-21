/* Versioned editorial eligibility. The v3 profile is staged inactive; the reviewed
   catalog publisher activates it only after API/frontend and SQL acceptance pass.
   Historical v1/v2 runs and procedures retain their recorded semantics. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
IF COL_LENGTH(N'dbo.FundingPlatform_FundingOpportunities',N'EligibilityPolicyJson') IS NULL
 ALTER TABLE dbo.FundingPlatform_FundingOpportunities ADD EligibilityPolicyJson NVARCHAR(MAX) NULL;
GO
CREATE OR ALTER FUNCTION dbo.FundingPlatform_fn_EligibilityPolicyValid(@Json NVARCHAR(MAX))
RETURNS BIT
AS
BEGIN
 IF @Json IS NULL RETURN 1;
 IF ISJSON(@Json)<>1 OR LEFT(LTRIM(@Json),1)<>N'{' OR DATALENGTH(@Json)>120000 RETURN 0;
 IF EXISTS(SELECT 1 FROM OPENJSON(@Json) GROUP BY [key] COLLATE Latin1_General_100_BIN2 HAVING COUNT(*)>1) RETURN 0;
 IF EXISTS(SELECT 1 FROM OPENJSON(@Json) WHERE [key] COLLATE Latin1_General_100_BIN2 NOT IN
  (N'sourceUrl',N'projectBudgetLimit',N'organizationAnnualBudgetLimit',N'requiredCategoryIds',N'requiredBeneficiaryTypeIds',N'manualRequirements')) RETURN 0;
 IF NOT EXISTS(SELECT 1 FROM OPENJSON(@Json) WHERE [key] COLLATE Latin1_General_100_BIN2=N'sourceUrl'
  AND [type]=1 AND [value] LIKE N'https://%._%' AND LEN([value]) BETWEEN 10 AND 2048) RETURN 0;
 IF EXISTS(SELECT 1 FROM OPENJSON(@Json) WHERE [key] IN(N'projectBudgetLimit',N'organizationAnnualBudgetLimit') AND [type] NOT IN(0,5)) RETURN 0;
 DECLARE @Limits TABLE(Data NVARCHAR(MAX));
 INSERT @Limits SELECT [value] FROM OPENJSON(@Json) WHERE [key] IN(N'projectBudgetLimit',N'organizationAnnualBudgetLimit') AND [type]=5;
 IF EXISTS(SELECT 1 FROM @Limits l WHERE (SELECT COUNT(*) FROM OPENJSON(l.Data))<>3
  OR (SELECT COUNT(DISTINCT [key] COLLATE Latin1_General_100_BIN2) FROM OPENJSON(l.Data))<>3
  OR NOT EXISTS(SELECT 1 FROM OPENJSON(l.Data) WHERE [key] COLLATE Latin1_General_100_BIN2=N'amount' AND [type]=2
    AND TRY_CONVERT(DECIMAL(19,4),[value])>0 AND TRY_CONVERT(DECIMAL(28,8),[value])=TRY_CONVERT(DECIMAL(19,4),[value]))
  OR NOT EXISTS(SELECT 1 FROM OPENJSON(l.Data) WHERE [key] COLLATE Latin1_General_100_BIN2=N'currency' AND [type]=1
    AND DATALENGTH([value])=6 AND [value] COLLATE Latin1_General_100_BIN2 NOT LIKE N'%[^A-Z]%')
  OR NOT EXISTS(SELECT 1 FROM OPENJSON(l.Data) WHERE [key] COLLATE Latin1_General_100_BIN2=N'inclusive' AND [type]=3)) RETURN 0;
 IF (SELECT COUNT(*) FROM OPENJSON(@Json) WHERE [key] COLLATE Latin1_General_100_BIN2 IN
  (N'requiredCategoryIds',N'requiredBeneficiaryTypeIds',N'manualRequirements') AND [type]=4)<>3 RETURN 0;
 IF (SELECT COUNT(*) FROM OPENJSON(@Json,'$.requiredCategoryIds'))>15 OR
  (SELECT COUNT(*) FROM OPENJSON(@Json,'$.requiredBeneficiaryTypeIds'))>11 OR
  (SELECT COUNT(*) FROM OPENJSON(@Json,'$.manualRequirements'))>12 RETURN 0;
 IF EXISTS(SELECT 1 FROM OPENJSON(@Json,'$.requiredCategoryIds') x WHERE x.[type]<>2 OR
  NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingCategories c WHERE c.Id=TRY_CONVERT(INT,x.[value]) AND c.Code<>N'OTHER' AND c.IsActive=1)
  OR TRY_CONVERT(DECIMAL(28,8),x.[value])<>TRY_CONVERT(INT,x.[value])) RETURN 0;
 IF EXISTS(SELECT 1 FROM OPENJSON(@Json,'$.requiredBeneficiaryTypeIds') x WHERE x.[type]<>2 OR
  NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_BeneficiaryTypes c WHERE c.Id=TRY_CONVERT(INT,x.[value]) AND c.Code<>N'OTHER' AND c.IsActive=1)
  OR TRY_CONVERT(DECIMAL(28,8),x.[value])<>TRY_CONVERT(INT,x.[value])) RETURN 0;
 IF EXISTS(SELECT 1 FROM OPENJSON(@Json,'$.manualRequirements') WHERE [type]<>1 OR LEN(LTRIM(RTRIM([value])))=0 OR DATALENGTH([value])>1000) RETURN 0;
 RETURN 1;
END;
GO
IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE name=N'FundingPlatform_CK_Opportunities_EligibilityPolicy')
 ALTER TABLE dbo.FundingPlatform_FundingOpportunities WITH CHECK ADD CONSTRAINT FundingPlatform_CK_Opportunities_EligibilityPolicy
 CHECK(dbo.FundingPlatform_fn_EligibilityPolicyValid(EligibilityPolicyJson)=1);
GO
DECLARE @Definition NVARCHAR(MAX)=OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunity_Create',N'P'));
IF @Definition IS NULL THROW 57002,N'Eligibility prerequisite is missing.',1;
IF (DATALENGTH(@Definition)-DATALENGTH(REPLACE(@Definition,N'@CoverKey NVARCHAR(MAX) = NULL',N'')))/DATALENGTH(N'@CoverKey NVARCHAR(MAX) = NULL')<>1
 THROW 57003,N'Eligibility prerequisite definition drifted.',1;
SET @Definition=REPLACE(@Definition,N'@CoverKey NVARCHAR(MAX) = NULL',N'@CoverKey NVARCHAR(MAX) = NULL,
    @EligibilityPolicyJson NVARCHAR(MAX) = NULL');
IF (DATALENGTH(@Definition)-DATALENGTH(REPLACE(@Definition,N'    SET @CoverKey = NULLIF',N'')))/DATALENGTH(N'    SET @CoverKey = NULLIF')<>1
 THROW 57003,N'Eligibility prerequisite definition drifted.',1;
SET @Definition=REPLACE(@Definition,N'    SET @CoverKey = NULLIF',N'
    IF dbo.FundingPlatform_fn_EligibilityPolicyValid(@EligibilityPolicyJson)<>1
       OR (SELECT COUNT(*) FROM OPENJSON(@SnapshotJson) WHERE [key] COLLATE Latin1_General_100_BIN2=N''eligibilityPolicy'')>1
       OR EXISTS(SELECT 1 FROM OPENJSON(@SnapshotJson) WHERE [key] COLLATE Latin1_General_100_BIN2=N''eligibilityPolicy'' AND [type] NOT IN(0,5))
       OR COALESCE(JSON_QUERY(@SnapshotJson,''$.eligibilityPolicy''),N'''') COLLATE Latin1_General_100_BIN2 <> COALESCE(@EligibilityPolicyJson,N'''') COLLATE Latin1_General_100_BIN2
       OR DATALENGTH(COALESCE(JSON_QUERY(@SnapshotJson,''$.eligibilityPolicy''),N''''))<>DATALENGTH(COALESCE(@EligibilityPolicyJson,N''''))
        THROW 57001,N''Eligibility policy must be valid and match its immutable content snapshot.'',1;

    SET @CoverKey = NULLIF');
IF (DATALENGTH(@Definition)-DATALENGTH(REPLACE(@Definition,N'CreatedAtUtc, UpdatedAtUtc, OtherCategoryDescription, CoverKey',N'')))/DATALENGTH(N'CreatedAtUtc, UpdatedAtUtc, OtherCategoryDescription, CoverKey')<>1
 THROW 57003,N'Eligibility prerequisite definition drifted.',1;
SET @Definition=REPLACE(@Definition,N'CreatedAtUtc, UpdatedAtUtc, OtherCategoryDescription, CoverKey',N'CreatedAtUtc, UpdatedAtUtc, OtherCategoryDescription, CoverKey, EligibilityPolicyJson');
IF (DATALENGTH(@Definition)-DATALENGTH(REPLACE(@Definition,N'@NowUtc, @NowUtc, @OtherCategoryDescription, @CoverKey',N'')))/DATALENGTH(N'@NowUtc, @NowUtc, @OtherCategoryDescription, @CoverKey')<>1
 THROW 57003,N'Eligibility prerequisite definition drifted.',1;
SET @Definition=REPLACE(@Definition,N'@NowUtc, @NowUtc, @OtherCategoryDescription, @CoverKey',N'@NowUtc, @NowUtc, @OtherCategoryDescription, @CoverKey, @EligibilityPolicyJson');
SET @Definition=N'CREATE OR ALTER '+SUBSTRING(@Definition,CHARINDEX(N'PROCEDURE',UPPER(@Definition)),2147483647);
EXEC sys.sp_executesql @Definition;
GO
DECLARE @Definition NVARCHAR(MAX)=OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunity_Update',N'P'));
IF @Definition IS NULL THROW 57002,N'Eligibility prerequisite is missing.',1;
IF (DATALENGTH(@Definition)-DATALENGTH(REPLACE(@Definition,N'@CoverKey NVARCHAR(MAX) = NULL',N'')))/DATALENGTH(N'@CoverKey NVARCHAR(MAX) = NULL')<>1
 THROW 57003,N'Eligibility prerequisite definition drifted.',1;
SET @Definition=REPLACE(@Definition,N'@CoverKey NVARCHAR(MAX) = NULL',N'@CoverKey NVARCHAR(MAX) = NULL,
    @EligibilityPolicyJson NVARCHAR(MAX) = NULL');
IF (DATALENGTH(@Definition)-DATALENGTH(REPLACE(@Definition,N'    SET @CoverKey = NULLIF',N'')))/DATALENGTH(N'    SET @CoverKey = NULLIF')<>1
 THROW 57003,N'Eligibility prerequisite definition drifted.',1;
SET @Definition=REPLACE(@Definition,N'    SET @CoverKey = NULLIF',N'
    IF dbo.FundingPlatform_fn_EligibilityPolicyValid(@EligibilityPolicyJson)<>1
       OR (SELECT COUNT(*) FROM OPENJSON(@SnapshotJson) WHERE [key] COLLATE Latin1_General_100_BIN2=N''eligibilityPolicy'')>1
       OR EXISTS(SELECT 1 FROM OPENJSON(@SnapshotJson) WHERE [key] COLLATE Latin1_General_100_BIN2=N''eligibilityPolicy'' AND [type] NOT IN(0,5))
       OR COALESCE(JSON_QUERY(@SnapshotJson,''$.eligibilityPolicy''),N'''') COLLATE Latin1_General_100_BIN2 <> COALESCE(@EligibilityPolicyJson,N'''') COLLATE Latin1_General_100_BIN2
       OR DATALENGTH(COALESCE(JSON_QUERY(@SnapshotJson,''$.eligibilityPolicy''),N''''))<>DATALENGTH(COALESCE(@EligibilityPolicyJson,N''''))
        THROW 57001,N''Eligibility policy must be valid and match its immutable content snapshot.'',1;

    SET @CoverKey = NULLIF');
IF (DATALENGTH(@Definition)-DATALENGTH(REPLACE(@Definition,N'SET CoverKey = @CoverKey, OtherCategoryDescription = @OtherCategoryDescription,',N'')))/DATALENGTH(N'SET CoverKey = @CoverKey, OtherCategoryDescription = @OtherCategoryDescription,')<>1
 THROW 57003,N'Eligibility prerequisite definition drifted.',1;
SET @Definition=REPLACE(@Definition,N'SET CoverKey = @CoverKey, OtherCategoryDescription = @OtherCategoryDescription,',N'SET EligibilityPolicyJson = @EligibilityPolicyJson, CoverKey = @CoverKey, OtherCategoryDescription = @OtherCategoryDescription,');
SET @Definition=N'CREATE OR ALTER '+SUBSTRING(@Definition,CHARINDEX(N'PROCEDURE',UPPER(@Definition)),2147483647);
EXEC sys.sp_executesql @Definition;
GO
DECLARE @Definition NVARCHAR(MAX)=OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunity_Admin_Get',N'P'));
IF @Definition IS NULL THROW 57002,N'Eligibility prerequisite is missing.',1;
IF (DATALENGTH(@Definition)-DATALENGTH(REPLACE(@Definition,N'opportunities.PublicId AS FundingOpportunityPublicId, opportunities.CoverKey,',N'')))/DATALENGTH(N'opportunities.PublicId AS FundingOpportunityPublicId, opportunities.CoverKey,')<>1
 THROW 57003,N'Eligibility prerequisite definition drifted.',1;
SET @Definition=REPLACE(@Definition,N'opportunities.PublicId AS FundingOpportunityPublicId, opportunities.CoverKey,',N'opportunities.PublicId AS FundingOpportunityPublicId, opportunities.CoverKey, opportunities.EligibilityPolicyJson,');
SET @Definition=N'CREATE OR ALTER '+SUBSTRING(@Definition,CHARINDEX(N'PROCEDURE',UPPER(@Definition)),2147483647);
EXEC sys.sp_executesql @Definition;
GO

DECLARE @OldProfile INT=(SELECT Id FROM dbo.FundingPlatform_MatchingProfiles WHERE Code=N'deterministic-project-v1' AND Version=2 AND EngineVersion=N'deterministic-sql-v2');
IF @OldProfile IS NULL THROW 57004,N'Versioned deterministic v2 prerequisite is missing.',1;
IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_MatchingProfiles WHERE Code=N'deterministic-project-v1' AND Version=3)
 THROW 57005,N'Eligibility profile already exists outside migration history.',1;
DECLARE @NewRules TABLE(Code NVARCHAR(100),Name NVARCHAR(150),IsHardGate BIT,Weight DECIMAL(5,2));
INSERT @NewRules SELECT r.Code,r.Name,r.IsHardGate,w.Weight FROM dbo.FundingPlatform_MatchingRules r
 JOIN dbo.FundingPlatform_MatchingRuleWeights w ON w.MatchingRuleId=r.Id WHERE w.MatchingProfileId=@OldProfile;
IF (SELECT COUNT(*) FROM @NewRules)<>9 THROW 57006,N'Deterministic v2 rule set drifted.',1;
INSERT @NewRules VALUES
 (N'project_budget_limit',N'Project total budget limit',1,0),
 (N'organization_budget_limit',N'Organization annual budget limit',1,0),
 (N'required_categories',N'Required project categories',1,0),
 (N'required_beneficiaries',N'Required project beneficiaries',1,0),
 (N'manual_eligibility',N'Additional eligibility review',1,0);
DECLARE @Now DATETIME2(3)=SYSUTCDATETIME();
INSERT dbo.FundingPlatform_MatchingRules(Code,Name,HandlerVersion,IsHardGate,IsActive,CreatedAtUtc)
 SELECT Code,Name,N'v3',IsHardGate,1,@Now FROM @NewRules;
INSERT dbo.FundingPlatform_MatchingProfiles(Code,Version,EngineVersion,UnknownPolicy,Status,IsActive,PublishedAtUtc,CreatedAtUtc)
 VALUES(N'deterministic-project-v1',3,N'deterministic-sql-v3',1,2,0,@Now,@Now);
DECLARE @NewProfile INT=SCOPE_IDENTITY();
INSERT dbo.FundingPlatform_MatchingRuleWeights(MatchingProfileId,MatchingRuleId,Weight,ParametersJson)
 SELECT @NewProfile,r.Id,n.Weight,N'{"unknownPolicy":"zero-no-renormalization","otherPolicy":"neutral-excluded","eligibilityPolicy":"explicit-constraints-v1"}'
 FROM @NewRules n JOIN dbo.FundingPlatform_MatchingRules r ON r.Code=n.Code AND r.HandlerVersion=N'v3';
GO
DECLARE @Definition NVARCHAR(MAX)=OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMatchingRun_Create',N'P'));
IF @Definition IS NULL THROW 57002,N'Eligibility prerequisite is missing.',1;
IF (DATALENGTH(@Definition)-DATALENGTH(REPLACE(@Definition,N'dbo.FundingPlatform_usp_ProjectMatchingRun_Create',N'')))/DATALENGTH(N'dbo.FundingPlatform_usp_ProjectMatchingRun_Create')<>1
 THROW 57003,N'Eligibility prerequisite definition drifted.',1;
SET @Definition=REPLACE(@Definition,N'dbo.FundingPlatform_usp_ProjectMatchingRun_Create',N'dbo.FundingPlatform_usp_ProjectMatchingRun_CreateV3');
IF (DATALENGTH(@Definition)-DATALENGTH(REPLACE(@Definition,N'rules.HandlerVersion = N''v2''',N'')))/DATALENGTH(N'rules.HandlerVersion = N''v2''')<>3
 THROW 57003,N'Eligibility prerequisite definition drifted.',1;
SET @Definition=REPLACE(@Definition,N'rules.HandlerVersion = N''v2''',N'rules.HandlerVersion = N''v3''');
IF (DATALENGTH(@Definition)-DATALENGTH(REPLACE(@Definition,N'@MatchingProfileId) <> 9',N'')))/DATALENGTH(N'@MatchingProfileId) <> 9')<>2
 THROW 57003,N'Eligibility prerequisite definition drifted.',1;
SET @Definition=REPLACE(@Definition,N'@MatchingProfileId) <> 9',N'@MatchingProfileId) <> 14');
IF (DATALENGTH(@Definition)-DATALENGTH(REPLACE(@Definition,N'@ProcessedCandidateCount) * 9',N'')))/DATALENGTH(N'@ProcessedCandidateCount) * 9')<>1
 THROW 57003,N'Eligibility prerequisite definition drifted.',1;
SET @Definition=REPLACE(@Definition,N'@ProcessedCandidateCount) * 9',N'@ProcessedCandidateCount) * 14');
IF (DATALENGTH(@Definition)-DATALENGTH(REPLACE(@Definition,N'(N''amount'', CONVERT(DECIMAL(5,2), 10), CONVERT(BIT, 0)))',N'')))/DATALENGTH(N'(N''amount'', CONVERT(DECIMAL(5,2), 10), CONVERT(BIT, 0)))')<>1
 THROW 57003,N'Eligibility prerequisite definition drifted.',1;
SET @Definition=REPLACE(@Definition,N'(N''amount'', CONVERT(DECIMAL(5,2), 10), CONVERT(BIT, 0)))',N'(N''amount'', CONVERT(DECIMAL(5,2), 10), CONVERT(BIT, 0)),
                     (N''project_budget_limit'', CONVERT(DECIMAL(5,2), 0), CONVERT(BIT, 1)),
                     (N''organization_budget_limit'', CONVERT(DECIMAL(5,2), 0), CONVERT(BIT, 1)),
                     (N''required_categories'', CONVERT(DECIMAL(5,2), 0), CONVERT(BIT, 1)),
                     (N''required_beneficiaries'', CONVERT(DECIMAL(5,2), 0), CONVERT(BIT, 1)),
                     (N''manual_eligibility'', CONVERT(DECIMAL(5,2), 0), CONVERT(BIT, 1)))');
IF (DATALENGTH(@Definition)-DATALENGTH(REPLACE(@Definition,N'opportunities.RequiresPriorExperience,',N'')))/DATALENGTH(N'opportunities.RequiresPriorExperience,')<>1
 THROW 57003,N'Eligibility prerequisite definition drifted.',1;
SET @Definition=REPLACE(@Definition,N'opportunities.RequiresPriorExperience,',N'opportunities.RequiresPriorExperience,
               opportunities.EligibilityPolicyJson,');
IF (DATALENGTH(@Definition)-DATALENGTH(REPLACE(@Definition,N'        IF (SELECT COUNT_BIG(1) FROM #RuleEvaluations)',N'')))/DATALENGTH(N'        IF (SELECT COUNT_BIG(1) FROM #RuleEvaluations)')<>1
 THROW 57003,N'Eligibility prerequisite definition drifted.',1;
SET @Definition=REPLACE(@Definition,N'        IF (SELECT COUNT_BIG(1) FROM #RuleEvaluations)',N'
        /* Total budgets are independent from the requested grant/funding gap.
           Unknown currencies and intervals spanning the cap remain unknown. */
        DECLARE @ProjectTotal DECIMAL(19,4),@AnnualMin DECIMAL(19,4),@AnnualMax DECIMAL(19,4),@AnnualCurrency CHAR(3);
        SELECT @ProjectTotal=BudgetTotal FROM dbo.FundingPlatform_Projects WHERE Id=@ProjectId;
        SELECT @AnnualMin=AnnualBudgetMin,@AnnualMax=AnnualBudgetMax,@AnnualCurrency=AnnualBudgetCurrency
        FROM dbo.FundingPlatform_Organizations WHERE Id=@OrganizationId;

        INSERT #RuleEvaluations(FundingOpportunityId,RuleCode,Outcome,RawScore,DataState,ReasonCode,ReasonParametersJson,EvidenceJson,IsWarning)
        SELECT c.FundingOpportunityId,f.RuleCode,r.Outcome,CASE r.Outcome WHEN 0 THEN 100 WHEN 2 THEN 0 END,
          CASE WHEN r.Outcome=3 THEN 1 WHEN f.LimitAmount IS NULL THEN 2 ELSE 0 END,
          CASE WHEN c.EligibilityPolicyJson IS NULL THEN N''eligibility.not_reviewed''
            WHEN f.LimitAmount IS NULL THEN N''budget_limit.not_required''
            WHEN f.Currency IS NULL OR f.Currency<>f.LimitCurrency THEN N''budget_limit.currency_unknown''
            WHEN r.Outcome=0 THEN N''budget_limit.meets''
            WHEN r.Outcome=2 THEN N''budget_limit.exceeded'' ELSE N''budget_limit.unknown'' END,
          (SELECT f.LimitAmount AS budgetLimit,f.LimitCurrency AS opportunityCurrency,f.Currency AS projectCurrency,
             CASE WHEN f.Inclusive=1 THEN N''inclusive'' ELSE N''exclusive'' END AS boundary FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
          CASE WHEN r.Outcome<>3 THEN N''{"source":"versioned-snapshots","fieldCode":"eligibility_policy","valueCodes":["applicant-total-budget","opportunity-eligibility-policy"]}'' END,
          CASE WHEN r.Outcome IN(2,3) THEN 1 ELSE 0 END
        FROM #Candidates c
        CROSS APPLY(VALUES
         (N''project_budget_limit'',@ProjectTotal,@ProjectTotal,@ProjectCurrency,
          TRY_CONVERT(DECIMAL(19,4),JSON_VALUE(c.EligibilityPolicyJson,''$.projectBudgetLimit.amount'')),
          JSON_VALUE(c.EligibilityPolicyJson,''$.projectBudgetLimit.currency''),
          CASE JSON_VALUE(c.EligibilityPolicyJson,''$.projectBudgetLimit.inclusive'') WHEN N''true'' THEN 1 ELSE 0 END),
         (N''organization_budget_limit'',@AnnualMin,@AnnualMax,@AnnualCurrency,
          TRY_CONVERT(DECIMAL(19,4),JSON_VALUE(c.EligibilityPolicyJson,''$.organizationAnnualBudgetLimit.amount'')),
          JSON_VALUE(c.EligibilityPolicyJson,''$.organizationAnnualBudgetLimit.currency''),
          CASE JSON_VALUE(c.EligibilityPolicyJson,''$.organizationAnnualBudgetLimit.inclusive'') WHEN N''true'' THEN 1 ELSE 0 END)
        ) f(RuleCode,LowerBudget,UpperBudget,Currency,LimitAmount,LimitCurrency,Inclusive)
        CROSS APPLY(SELECT CONVERT(TINYINT,CASE
          WHEN c.EligibilityPolicyJson IS NULL THEN 3
          WHEN f.LimitAmount IS NULL THEN 0
          WHEN f.Currency IS NULL OR f.Currency<>f.LimitCurrency THEN 3
          WHEN f.LowerBudget>f.LimitAmount OR (f.LowerBudget=f.LimitAmount AND f.Inclusive=0) THEN 2
          WHEN f.UpperBudget<f.LimitAmount OR (f.UpperBudget=f.LimitAmount AND f.Inclusive=1) THEN 0
          ELSE 3 END) AS Outcome) r;

        INSERT #RuleEvaluations(FundingOpportunityId,RuleCode,Outcome,RawScore,DataState,ReasonCode,ReasonParametersJson,EvidenceJson,IsWarning)
        SELECT c.FundingOpportunityId,f.RuleCode,r.Outcome,CASE r.Outcome WHEN 0 THEN 100 WHEN 2 THEN 0 END,
          CASE WHEN r.Outcome=3 THEN 1 WHEN f.RequiredCount=0 THEN 2 ELSE 0 END,
          CASE WHEN c.EligibilityPolicyJson IS NULL THEN N''eligibility.not_reviewed''
            WHEN f.RequiredCount=0 THEN N''required_scope.not_required''
            WHEN f.ProjectCount=0 THEN N''required_scope.unknown''
            WHEN f.MatchCount>0 THEN N''required_scope.meets'' ELSE N''required_scope.no_match'' END,
          (SELECT f.MatchCount AS matchCount FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
          CASE WHEN r.Outcome<>3 THEN N''{"source":"versioned-snapshots","fieldCode":"eligibility_policy","valueCodes":["project-categories","project-beneficiaries","opportunity-eligibility-policy"]}'' END,
          CASE WHEN r.Outcome IN(2,3) THEN 1 ELSE 0 END
        FROM #Candidates c
        CROSS APPLY(VALUES
          (N''required_categories'',@ProjectCategoryCount,
           (SELECT COUNT(*) FROM OPENJSON(c.EligibilityPolicyJson,''$.requiredCategoryIds'')),
           (SELECT COUNT(*) FROM OPENJSON(c.EligibilityPolicyJson,''$.requiredCategoryIds'') j JOIN #MatchingProjectCategories p ON p.FundingCategoryId=TRY_CONVERT(INT,j.[value]))),
          (N''required_beneficiaries'',@ProjectBeneficiaryCount,
           (SELECT COUNT(*) FROM OPENJSON(c.EligibilityPolicyJson,''$.requiredBeneficiaryTypeIds'')),
           (SELECT COUNT(*) FROM OPENJSON(c.EligibilityPolicyJson,''$.requiredBeneficiaryTypeIds'') j JOIN #MatchingProjectBeneficiaryTypes p ON p.BeneficiaryTypeId=TRY_CONVERT(INT,j.[value])))
        ) f(RuleCode,ProjectCount,RequiredCount,MatchCount)
        CROSS APPLY(SELECT CONVERT(TINYINT,CASE WHEN c.EligibilityPolicyJson IS NULL THEN 3
          WHEN f.RequiredCount=0 THEN 0 WHEN f.ProjectCount=0 THEN 3 WHEN f.MatchCount>0 THEN 0 ELSE 2 END) AS Outcome) r;

        INSERT #RuleEvaluations(FundingOpportunityId,RuleCode,Outcome,RawScore,DataState,ReasonCode,ReasonParametersJson,EvidenceJson,IsWarning)
        SELECT c.FundingOpportunityId,N''manual_eligibility'',CASE WHEN c.EligibilityPolicyJson IS NULL OR m.ManualCount>0 THEN 3 ELSE 0 END,
          CASE WHEN c.EligibilityPolicyJson IS NOT NULL AND m.ManualCount=0 THEN 100 END,
          CASE WHEN c.EligibilityPolicyJson IS NULL OR m.ManualCount>0 THEN 1 ELSE 2 END,
          CASE WHEN c.EligibilityPolicyJson IS NULL THEN N''eligibility.not_reviewed'' WHEN m.ManualCount>0 THEN N''eligibility.manual_review'' ELSE N''eligibility.no_additional_requirements'' END,
          (SELECT m.ManualCount AS manualCount FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),NULL,
          CASE WHEN c.EligibilityPolicyJson IS NULL OR m.ManualCount>0 THEN 1 ELSE 0 END
        FROM #Candidates c CROSS APPLY(SELECT COUNT(*) AS ManualCount FROM OPENJSON(c.EligibilityPolicyJson,''$.manualRequirements'')) m;

        IF (SELECT COUNT_BIG(1) FROM #RuleEvaluations)');
IF (DATALENGTH(@Definition)-DATALENGTH(REPLACE(@Definition,N'WHERE opportunityCountries.FundingOpportunityId = candidates.FundingOpportunityId) AS CountryMatches,',N'')))/DATALENGTH(N'WHERE opportunityCountries.FundingOpportunityId = candidates.FundingOpportunityId) AS CountryMatches,')<>1
 THROW 57003,N'Eligibility prerequisite definition drifted.',1;
SET @Definition=REPLACE(@Definition,N'WHERE opportunityCountries.FundingOpportunityId = candidates.FundingOpportunityId) AS CountryMatches,',N'WHERE opportunityCountries.FundingOpportunityId = candidates.FundingOpportunityId
                      AND NOT EXISTS(SELECT 1 FROM #CandidateRegions cr
                        JOIN dbo.FundingPlatform_Regions gr ON gr.Id=cr.RegionId
                        WHERE cr.FundingOpportunityId=candidates.FundingOpportunityId
                          AND gr.CountryId=opportunityCountries.CountryId)) AS CountryMatches,
                   (SELECT COUNT(*) FROM #MatchingProjectRegions pr
                    JOIN dbo.FundingPlatform_Regions gr ON gr.Id=pr.RegionId
                    WHERE EXISTS(SELECT 1 FROM #CandidateRegions cr
                      JOIN dbo.FundingPlatform_Regions r ON r.Id=cr.RegionId
                      WHERE cr.FundingOpportunityId=candidates.FundingOpportunityId
                        AND r.CountryId=gr.CountryId)) AS RestrictedKnownRegions,');
IF (DATALENGTH(@Definition)-DATALENGTH(REPLACE(@Definition,N'facts.CountryNeedsRegionDetail > 0 AND @ProjectRegionCount = 0',N'')))/DATALENGTH(N'facts.CountryNeedsRegionDetail > 0 AND @ProjectRegionCount = 0')<>2
 THROW 57003,N'Eligibility prerequisite definition drifted.',1;
SET @Definition=REPLACE(@Definition,N'facts.CountryNeedsRegionDetail > 0 AND @ProjectRegionCount = 0',N'facts.CountryNeedsRegionDetail > 0 AND facts.RestrictedKnownRegions = 0');
SET @Definition=N'CREATE OR ALTER '+SUBSTRING(@Definition,CHARINDEX(N'PROCEDURE',UPPER(@Definition)),2147483647);
EXEC sys.sp_executesql @Definition;
GO
DECLARE @Definition NVARCHAR(MAX)=OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectMatchingRun_Create',N'P'));
IF @Definition IS NULL THROW 57002,N'Eligibility prerequisite is missing.',1;
IF (DATALENGTH(@Definition)-DATALENGTH(REPLACE(@Definition,N'    SET NOCOUNT ON;',N'')))/DATALENGTH(N'    SET NOCOUNT ON;')<>1
 THROW 57003,N'Eligibility prerequisite definition drifted.',1;
SET @Definition=REPLACE(@Definition,N'    SET NOCOUNT ON;',N'    SET NOCOUNT ON;

    /* v3 is activated with the reviewed catalog, independently of this migration. */
    IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_MatchingProfiles WHERE IsActive=1 AND EngineVersion=N''deterministic-sql-v3'')
    BEGIN
        EXEC dbo.FundingPlatform_usp_ProjectMatchingRun_CreateV3 @UserPublicId,@OrganizationPublicId,@ProjectPublicId,@IdempotencyKeyHash,@RequestHash,@NowUtc;
        RETURN;
    END;
');
SET @Definition=N'CREATE OR ALTER '+SUBSTRING(@Definition,CHARINDEX(N'PROCEDURE',UPPER(@Definition)),2147483647);
EXEC sys.sp_executesql @Definition;
GO
