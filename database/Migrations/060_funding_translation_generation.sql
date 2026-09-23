/* On-demand machine proposals, NOT public translations. No worker, timer or paid defaults.
   Reservations are conservative: no refunds/retries after an uncertain provider call. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF OBJECT_ID(N'dbo.FundingPlatform_FundingTranslationGenerations',N'U') IS NULL
BEGIN
 CREATE TABLE dbo.FundingPlatform_FundingTranslationGenerations(
  GenerationId UNIQUEIDENTIFIER NOT NULL CONSTRAINT FundingPlatform_DF_TranslationGeneration_Id DEFAULT NEWID(),
  FundingOpportunityId BIGINT NOT NULL,
  Language VARCHAR(2) COLLATE Latin1_General_100_BIN2 NOT NULL,
  SourceContentVersion INT NOT NULL,
  SourceRowVersion BINARY(8) NOT NULL,
  ActorUserId BIGINT NOT NULL,
  Model VARCHAR(100) NOT NULL,
  PromptVersion VARCHAR(40) NOT NULL,
  Status VARCHAR(12) NOT NULL,
  ReservedCostUsd DECIMAL(12,6) NOT NULL,
  TextJson NVARCHAR(MAX) NULL,
  InputTokens INT NULL,
  OutputTokens INT NULL,
  CreatedAtUtc DATETIME2(7) NOT NULL,
  CompletedAtUtc DATETIME2(7) NULL,
  CONSTRAINT FundingPlatform_PK_TranslationGeneration PRIMARY KEY(GenerationId),
  CONSTRAINT FundingPlatform_UQ_TranslationGeneration UNIQUE(FundingOpportunityId,Language,SourceContentVersion),
  CONSTRAINT FundingPlatform_FK_TranslationGeneration_Opportunity FOREIGN KEY(FundingOpportunityId) REFERENCES dbo.FundingPlatform_FundingOpportunities(Id),
  CONSTRAINT FundingPlatform_FK_TranslationGeneration_Actor FOREIGN KEY(ActorUserId) REFERENCES dbo.FundingPlatform_Users(Id),
  CONSTRAINT FundingPlatform_CK_TranslationGeneration_Data CHECK(Language IN ('es','en') AND SourceContentVersion > 0
    AND ReservedCostUsd > 0 AND ReservedCostUsd <= 1 AND Status IN ('processing','completed','failed')
    AND ((Status = 'completed' AND TextJson IS NOT NULL AND ISJSON(TextJson,OBJECT) = 1
          AND InputTokens IS NOT NULL AND InputTokens > 0 AND OutputTokens IS NOT NULL AND OutputTokens > 0 AND CompletedAtUtc IS NOT NULL)
      OR (Status <> 'completed' AND TextJson IS NULL AND InputTokens IS NULL AND OutputTokens IS NULL)))
 );
 CREATE INDEX FundingPlatform_IX_TranslationGeneration_Budget
   ON dbo.FundingPlatform_FundingTranslationGenerations(CreatedAtUtc) INCLUDE(ReservedCostUsd);
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingTranslationGeneration_Reserve
 @UserPublicId UNIQUEIDENTIFIER, @OpportunityPublicId UNIQUEIDENTIFIER, @Language NVARCHAR(20),
 @SourceContentVersion INT, @SourceRowVersion BINARY(8), @Model VARCHAR(100),
 @MaximumCostUsdPerRequest DECIMAL(12,6), @MonthlyBudgetUsd DECIMAL(12,6), @MonthlyRequestLimit INT
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF @Language IS NULL OR @Language COLLATE Latin1_General_100_BIN2 NOT IN (N'es',N'en') OR DATALENGTH(@Language) <> 4
    OR @SourceContentVersion IS NULL OR @SourceContentVersion < 1 OR @SourceRowVersion IS NULL
    OR NULLIF(@Model,'') IS NULL OR @Model COLLATE Latin1_General_100_BIN2 LIKE '%[^a-zA-Z0-9_.-]%'
    OR @MaximumCostUsdPerRequest IS NULL OR @MaximumCostUsdPerRequest <= 0 OR @MaximumCostUsdPerRequest > 1
    OR @MonthlyBudgetUsd IS NULL OR @MonthlyBudgetUsd < @MaximumCostUsdPerRequest OR @MonthlyBudgetUsd > 100
    OR @MonthlyRequestLimit IS NULL OR @MonthlyRequestLimit NOT BETWEEN 1 AND 1000
    THROW 56034,N'Invalid generation configuration.',1;
 DECLARE @Actor BIGINT, @Id BIGINT, @CurrentVersion INT, @CurrentRowVersion BINARY(8), @Generation UNIQUEIDENTIFIER,
   @Acquired BIT = 0, @Status VARCHAR(12), @Text NVARCHAR(MAX), @Lock INT,
   @Now DATETIME2(7) = SYSUTCDATETIME(), @Month DATETIME2(7), @Spent DECIMAL(18,6), @Count INT;
 SET @Month = DATEFROMPARTS(YEAR(@Now),MONTH(@Now),1);
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.FundingPlatform_usp_AdminActor_Lock @UserPublicId,@Actor OUTPUT;
  SELECT @Id=Id,@CurrentVersion=ContentVersion,@CurrentRowVersion=RowVersion
    FROM dbo.FundingPlatform_FundingOpportunities WITH(UPDLOCK,HOLDLOCK) WHERE PublicId=@OpportunityPublicId AND IsActive=1;
  IF @Id IS NULL THROW 56031,N'Opportunity not available.',1;
  IF @CurrentVersion <> @SourceContentVersion OR @CurrentRowVersion <> @SourceRowVersion THROW 56032,N'Original changed.',1;
  -- Global budget lock serializes all instances, actors, opportunities and languages.
  EXEC @Lock=sys.sp_getapplock @Resource=N'FundingPlatform:TranslationGenerationBudget',
    @LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=5000;
  IF @Lock < 0 THROW 56095,N'Translation budget unavailable.',1;
  SELECT @Generation=GenerationId,@Status=Status,@Text=TextJson
    FROM dbo.FundingPlatform_FundingTranslationGenerations WITH(UPDLOCK,HOLDLOCK)
    WHERE FundingOpportunityId=@Id AND Language=@Language AND SourceContentVersion=@SourceContentVersion;
  IF @Generation IS NULL
  BEGIN
   SELECT @Spent=COALESCE(SUM(ReservedCostUsd),0),@Count=COUNT(*)
     FROM dbo.FundingPlatform_FundingTranslationGenerations
     WHERE CreatedAtUtc >= @Month AND CreatedAtUtc < DATEADD(MONTH,1,@Month);
   IF @Spent + @MaximumCostUsdPerRequest > @MonthlyBudgetUsd OR @Count >= @MonthlyRequestLimit
     THROW 56095,N'Translation monthly limit reached.',1;
   SET @Generation=NEWID(); SET @Status='processing'; SET @Acquired=1;
   INSERT dbo.FundingPlatform_FundingTranslationGenerations
     (GenerationId,FundingOpportunityId,Language,SourceContentVersion,SourceRowVersion,ActorUserId,Model,PromptVersion,Status,ReservedCostUsd,CreatedAtUtc)
     VALUES(@Generation,@Id,@Language,@SourceContentVersion,@SourceRowVersion,@Actor,@Model,'funding-translation-v1',@Status,@MaximumCostUsdPerRequest,@Now);
  END;
  COMMIT TRANSACTION;
  SELECT (SELECT @Generation AS generationId,@Acquired AS acquired,@Status AS status,JSON_QUERY(@Text) AS [text]
    FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) AS Json;
 END TRY
 BEGIN CATCH
  IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
  THROW;
 END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingTranslationGeneration_Finish
 @UserPublicId UNIQUEIDENTIFIER, @GenerationId UNIQUEIDENTIFIER,
 @TextJson NVARCHAR(MAX)=NULL, @InputTokens INT=NULL, @OutputTokens INT=NULL
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 DECLARE @Fields TABLE(Name NVARCHAR(100) COLLATE Latin1_General_100_BIN2 PRIMARY KEY, MaxLength INT NOT NULL);
 INSERT @Fields VALUES(N'title',350),(N'summary',2000),(N'description',50000),(N'eligibilityDescription',30000),
   (N'requirements',30000),(N'objectives',30000),(N'allowedActivities',30000),(N'excludedActivities',30000),
   (N'restrictions',30000),(N'targetOrganizationsDescription',2000),(N'targetPopulationsDescription',2000);
 IF @TextJson IS NOT NULL
 BEGIN
  IF ISJSON(@TextJson,OBJECT) <> 1 OR DATALENGTH(@TextJson)>3000000
    OR @InputTokens IS NULL OR @InputTokens NOT BETWEEN 1 AND 80384
    OR @OutputTokens IS NULL OR @OutputTokens NOT BETWEEN 1 AND 16384 THROW 56034,N'Invalid generation result.',1;
  IF (SELECT COUNT(*) FROM OPENJSON(@TextJson))<>11
    OR EXISTS(SELECT [key] COLLATE Latin1_General_100_BIN2 FROM OPENJSON(@TextJson) GROUP BY [key] COLLATE Latin1_General_100_BIN2 HAVING COUNT(*)>1)
    OR EXISTS(SELECT 1 FROM OPENJSON(@TextJson) j LEFT JOIN @Fields f ON f.Name=j.[key] COLLATE Latin1_General_100_BIN2
      WHERE f.Name IS NULL OR j.[type] NOT IN(0,1) OR DATALENGTH(j.[value])>f.MaxLength*2)
    THROW 56034,N'Invalid generation fields.',1;
 END;
 DECLARE @Actor BIGINT,@Id BIGINT,@Version INT,@RowVersion BINARY(8),@Original NVARCHAR(MAX),@Status VARCHAR(12);
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.FundingPlatform_usp_AdminActor_Lock @UserPublicId,@Actor OUTPUT;
  -- Same lock order as Reserve and editorial writes: actor, opportunity, generation.
  SELECT @Id=FundingOpportunityId FROM dbo.FundingPlatform_FundingTranslationGenerations
    WHERE GenerationId=@GenerationId AND ActorUserId=@Actor;
  SELECT @Original=Title FROM dbo.FundingPlatform_FundingOpportunities WITH(UPDLOCK,HOLDLOCK) WHERE Id=@Id;
  SELECT @Id=FundingOpportunityId,@Version=SourceContentVersion,@RowVersion=SourceRowVersion,@Status=Status
    FROM dbo.FundingPlatform_FundingTranslationGenerations WITH(UPDLOCK,HOLDLOCK)
    WHERE GenerationId=@GenerationId AND ActorUserId=@Actor;
  IF @Id IS NULL THROW 56031,N'Generation not available.',1;
  IF @Status='processing'
  BEGIN
   IF @TextJson IS NOT NULL
   BEGIN
    IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WITH(HOLDLOCK)
        WHERE Id=@Id AND IsActive=1 AND ContentVersion=@Version AND RowVersion=@RowVersion)
      THROW 56032,N'Original changed.',1;
    SET @Original=(SELECT Title AS title,Summary AS summary,Description AS description,
      EligibilityDescription AS eligibilityDescription,Requirements AS requirements,Objectives AS objectives,
      AllowedActivities AS allowedActivities,ExcludedActivities AS excludedActivities,Restrictions AS restrictions,
      TargetOrganizationsDescription AS targetOrganizationsDescription,TargetPopulationsDescription AS targetPopulationsDescription
      FROM dbo.FundingPlatform_FundingOpportunities WHERE Id=@Id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
    IF EXISTS(SELECT 1 FROM @Fields f
      LEFT JOIN OPENJSON(@Original) s ON s.[key] COLLATE Latin1_General_100_BIN2=f.Name
      LEFT JOIN OPENJSON(@TextJson) t ON t.[key] COLLATE Latin1_General_100_BIN2=f.Name
      WHERE (NULLIF(LTRIM(RTRIM(s.[value])),N'') IS NULL AND NULLIF(LTRIM(RTRIM(t.[value])),N'') IS NOT NULL)
         OR (NULLIF(LTRIM(RTRIM(s.[value])),N'') IS NOT NULL AND NULLIF(LTRIM(RTRIM(t.[value])),N'') IS NULL))
      THROW 56034,N'Generation coverage differs from original.',1;
   END;
   UPDATE dbo.FundingPlatform_FundingTranslationGenerations SET
     Status=CASE WHEN @TextJson IS NULL THEN 'failed' ELSE 'completed' END,TextJson=@TextJson,
     InputTokens=CASE WHEN @TextJson IS NULL THEN NULL ELSE @InputTokens END,
     OutputTokens=CASE WHEN @TextJson IS NULL THEN NULL ELSE @OutputTokens END,CompletedAtUtc=SYSUTCDATETIME()
     WHERE GenerationId=@GenerationId;
  END;
  COMMIT TRANSACTION;
 END TRY
 BEGIN CATCH
  IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
  THROW;
 END CATCH;
END;
GO
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_FundingTranslationGeneration_Reserve TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_FundingTranslationGeneration_Finish TO FundingPlatform_ApiRuntimeRole;
