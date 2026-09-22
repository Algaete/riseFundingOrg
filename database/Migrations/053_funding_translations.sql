/* Reviewed, version-bound presentation text. No external provider or scheduler.
   Activation requires FundingTranslations:Enabled after this migration. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF OBJECT_ID(N'dbo.FundingPlatform_FundingTranslations', N'U') IS NULL
BEGIN
 CREATE TABLE dbo.FundingPlatform_FundingTranslations(
  FundingOpportunityId BIGINT NOT NULL,
  Language VARCHAR(2) COLLATE Latin1_General_100_BIN2 NOT NULL,
  SourceContentVersion INT NOT NULL,
  Revision INT NOT NULL,
  Reviewed BIT NOT NULL,
  TextJson NVARCHAR(MAX) NOT NULL,
  UpdatedByUserId BIGINT NOT NULL,
  UpdatedAtUtc DATETIME2(7) NOT NULL,
  CONSTRAINT FundingPlatform_PK_FundingTranslations PRIMARY KEY(FundingOpportunityId, Language),
  CONSTRAINT FundingPlatform_FK_Translation_Opportunity FOREIGN KEY(FundingOpportunityId) REFERENCES dbo.FundingPlatform_FundingOpportunities(Id),
  CONSTRAINT FundingPlatform_FK_Translation_Actor FOREIGN KEY(UpdatedByUserId) REFERENCES dbo.FundingPlatform_Users(Id),
  CONSTRAINT FundingPlatform_CK_Translation_Data CHECK(Language IN ('es','en') AND SourceContentVersion > 0 AND Revision > 0 AND ISJSON(TextJson, OBJECT) = 1)
 );
END;
IF OBJECT_ID(N'dbo.FundingPlatform_FundingTranslationHistory', N'U') IS NULL
BEGIN
 CREATE TABLE dbo.FundingPlatform_FundingTranslationHistory(
  FundingOpportunityId BIGINT NOT NULL,
  Language VARCHAR(2) COLLATE Latin1_General_100_BIN2 NOT NULL,
  Revision INT NOT NULL,
  SourceContentVersion INT NOT NULL,
  Reviewed BIT NOT NULL,
  TextJson NVARCHAR(MAX) NOT NULL,
  ActorUserId BIGINT NOT NULL,
  CreatedAtUtc DATETIME2(7) NOT NULL,
  CONSTRAINT FundingPlatform_PK_TranslationHistory PRIMARY KEY(FundingOpportunityId, Language, Revision),
  CONSTRAINT FundingPlatform_FK_TranslationHistory_Opportunity FOREIGN KEY(FundingOpportunityId) REFERENCES dbo.FundingPlatform_FundingOpportunities(Id),
  CONSTRAINT FundingPlatform_FK_TranslationHistory_Actor FOREIGN KEY(ActorUserId) REFERENCES dbo.FundingPlatform_Users(Id),
  CONSTRAINT FundingPlatform_CK_TranslationHistory_Data CHECK(Language IN ('es','en') AND Revision > 0 AND SourceContentVersion > 0 AND ISJSON(TextJson, OBJECT) = 1)
 );
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingTranslation_AdminGet
 @UserPublicId UNIQUEIDENTIFIER, @OpportunityPublicId UNIQUEIDENTIFIER, @Language NVARCHAR(20)
AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @Access TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@UserPublicId);
 IF @Access = 0 THROW 51601, N'Active administrator required.', 1;
 IF @Access = 1 THROW 51602, N'MFA required.', 1;
 SELECT NULLIF((SELECT t.Language AS language, t.SourceContentVersion AS sourceContentVersion,
    t.Revision AS revision, t.Reviewed AS reviewed, JSON_QUERY(t.TextJson) AS [text],
    TODATETIMEOFFSET(t.UpdatedAtUtc, '+00:00') AS updatedAtUtc
  FROM dbo.FundingPlatform_FundingTranslations t
  JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id = t.FundingOpportunityId
  WHERE o.PublicId = @OpportunityPublicId AND t.Language = @Language COLLATE Latin1_General_100_BIN2
  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), N'') AS Json;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingTranslation_Read
 @OpportunityPublicId UNIQUEIDENTIFIER, @Language NVARCHAR(20), @SourceContentVersion INT
AS
BEGIN
 SET NOCOUNT ON;
 SELECT NULLIF((SELECT t.Language AS language, t.SourceContentVersion AS sourceContentVersion,
    t.Revision AS revision, t.Reviewed AS reviewed, JSON_QUERY(t.TextJson) AS [text],
    TODATETIMEOFFSET(t.UpdatedAtUtc, '+00:00') AS updatedAtUtc
  FROM dbo.FundingPlatform_FundingTranslations t
  JOIN dbo.FundingPlatform_FundingOpportunities o ON o.Id = t.FundingOpportunityId
  WHERE o.PublicId = @OpportunityPublicId AND t.Language = @Language COLLATE Latin1_General_100_BIN2
    AND t.Reviewed = 1 AND t.SourceContentVersion = @SourceContentVersion
    AND t.SourceContentVersion = o.ContentVersion
    AND EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() p WHERE p.FundingOpportunityId = o.Id)
  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), N'') AS Json;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingTranslation_Save
 @UserPublicId UNIQUEIDENTIFIER, @OpportunityPublicId UNIQUEIDENTIFIER, @Language NVARCHAR(20),
 @SourceContentVersion INT, @ExpectedRevision INT, @Reviewed BIT, @TextJson NVARCHAR(MAX), @SourceRowVersion BINARY(8)
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF @Language IS NULL OR @Language COLLATE Latin1_General_100_BIN2 NOT IN (N'es',N'en')
    OR DATALENGTH(@Language) <> 4 OR @SourceContentVersion IS NULL OR @SourceContentVersion < 1
    OR @ExpectedRevision IS NULL OR @ExpectedRevision < 0 OR @Reviewed IS NULL OR @SourceRowVersion IS NULL
    -- Allow JSON Unicode escaping within the per-field limits (at most 236350 characters).
    OR @TextJson IS NULL OR ISJSON(@TextJson, OBJECT) <> 1 OR DATALENGTH(@TextJson) > 3000000
    THROW 56034, N'Invalid translation.', 1;
 DECLARE @Fields TABLE(Name NVARCHAR(100) COLLATE Latin1_General_100_BIN2 PRIMARY KEY, MaxLength INT NOT NULL);
 INSERT @Fields VALUES(N'title',350),(N'summary',2000),(N'description',50000),
   (N'eligibilityDescription',30000),(N'requirements',30000),(N'objectives',30000),
   (N'allowedActivities',30000),(N'excludedActivities',30000),(N'restrictions',30000),
   (N'targetOrganizationsDescription',2000),(N'targetPopulationsDescription',2000);
 IF EXISTS(SELECT [key] FROM OPENJSON(@TextJson) GROUP BY [key] HAVING COUNT(*) > 1)
    OR EXISTS(SELECT 1 FROM OPENJSON(@TextJson) j LEFT JOIN @Fields f ON f.Name = j.[key] COLLATE Latin1_General_100_BIN2
       WHERE f.Name IS NULL OR j.[type] NOT IN (0,1) OR DATALENGTH(j.[value]) > f.MaxLength * 2)
    THROW 56034, N'Invalid translation fields.', 1;
 DECLARE @Actor BIGINT, @Id BIGINT, @CurrentContentVersion INT, @CurrentRowVersion BINARY(8),
    @Revision INT, @Original NVARCHAR(MAX), @Now DATETIME2(7) = SYSUTCDATETIME(), @Result NVARCHAR(MAX);
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.FundingPlatform_usp_AdminActor_Lock @UserPublicId, @Actor OUTPUT;
  SELECT @Id = Id, @CurrentContentVersion = ContentVersion, @CurrentRowVersion = RowVersion
    FROM dbo.FundingPlatform_FundingOpportunities WITH(UPDLOCK,HOLDLOCK)
    WHERE PublicId = @OpportunityPublicId AND IsActive = 1;
  IF @Id IS NULL THROW 56031, N'Opportunity not available.', 1;
  IF @CurrentContentVersion <> @SourceContentVersion OR @CurrentRowVersion <> @SourceRowVersion
    THROW 56032, N'Original content changed.', 1;
  SELECT @Revision = Revision FROM dbo.FundingPlatform_FundingTranslations WITH(UPDLOCK,HOLDLOCK)
    WHERE FundingOpportunityId = @Id AND Language = @Language;
  IF ISNULL(@Revision, 0) <> @ExpectedRevision THROW 56032, N'Translation changed.', 1;
  SET @Original = (SELECT Title AS title, Summary AS summary, Description AS description,
    EligibilityDescription AS eligibilityDescription, Requirements AS requirements, Objectives AS objectives,
    AllowedActivities AS allowedActivities, ExcludedActivities AS excludedActivities, Restrictions AS restrictions,
    TargetOrganizationsDescription AS targetOrganizationsDescription, TargetPopulationsDescription AS targetPopulationsDescription
    FROM dbo.FundingPlatform_FundingOpportunities WHERE Id = @Id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
  IF @Reviewed = 1 AND EXISTS(SELECT 1 FROM @Fields f
    -- OPENJSON keys use a binary collation independent of the database default.
    LEFT JOIN OPENJSON(@Original) s ON s.[key] COLLATE Latin1_General_100_BIN2 = f.Name
    LEFT JOIN OPENJSON(@TextJson) t ON t.[key] COLLATE Latin1_General_100_BIN2 = f.Name
    WHERE (NULLIF(LTRIM(RTRIM(s.[value])),N'') IS NOT NULL AND NULLIF(LTRIM(RTRIM(t.[value])),N'') IS NULL)
       OR (NULLIF(LTRIM(RTRIM(s.[value])),N'') IS NULL AND NULLIF(LTRIM(RTRIM(t.[value])),N'') IS NOT NULL))
    THROW 56034, N'Reviewed translation must match the original field coverage.', 1;
  SET @Revision = ISNULL(@Revision,0) + 1;
  UPDATE dbo.FundingPlatform_FundingTranslations SET SourceContentVersion = @SourceContentVersion,
    Revision = @Revision, Reviewed = @Reviewed, TextJson = @TextJson, UpdatedByUserId = @Actor, UpdatedAtUtc = @Now
    WHERE FundingOpportunityId = @Id AND Language = @Language;
  IF @@ROWCOUNT = 0 INSERT dbo.FundingPlatform_FundingTranslations
    (FundingOpportunityId,Language,SourceContentVersion,Revision,Reviewed,TextJson,UpdatedByUserId,UpdatedAtUtc)
    VALUES(@Id,@Language,@SourceContentVersion,@Revision,@Reviewed,@TextJson,@Actor,@Now);
  INSERT dbo.FundingPlatform_FundingTranslationHistory
    (FundingOpportunityId,Language,Revision,SourceContentVersion,Reviewed,TextJson,ActorUserId,CreatedAtUtc)
    VALUES(@Id,@Language,@Revision,@SourceContentVersion,@Reviewed,@TextJson,@Actor,@Now);
  SET @Result = (SELECT @Language AS language, @SourceContentVersion AS sourceContentVersion,
    @Revision AS revision, @Reviewed AS reviewed, JSON_QUERY(@TextJson) AS [text],
    TODATETIMEOFFSET(@Now,'+00:00') AS updatedAtUtc FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
  COMMIT TRANSACTION;
  SELECT @Result AS Json;
 END TRY
 BEGIN CATCH
  IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
  THROW;
 END CATCH;
END;
GO
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_FundingTranslation_AdminGet TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_FundingTranslation_Read TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_FundingTranslation_Save TO FundingPlatform_ApiRuntimeRole;
