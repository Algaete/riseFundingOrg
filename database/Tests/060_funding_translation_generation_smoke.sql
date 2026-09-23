/* Synthetic proposals only; no provider calls, no published translations, rollback. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @InitialTransactionCount INT=@@TRANCOUNT;
IF @InitialTransactionCount=0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke060;
BEGIN TRY
 DECLARE @Actor UNIQUEIDENTIFIER=NEWID(),@Opportunity UNIQUEIDENTIFIER=NEWID(),@Now DATETIME2(7)=SYSUTCDATETIME();
 DECLARE @Tag NVARCHAR(80)=N'generation-smoke-'+CONVERT(NVARCHAR(36),@Actor);
 INSERT dbo.FundingPlatform_Users(PublicId,Email,NormalizedEmail,DisplayName,PasswordHash,SecurityStamp,EmailConfirmed,Status,PreferredLocale,TwoFactorEnabled)
 VALUES(@Actor,@Tag+N'@example.invalid',UPPER(@Tag+N'@example.invalid'),@Tag,N'not-a-credential',@Tag,1,2,N'es-CL',1);
 DECLARE @ActorId BIGINT=SCOPE_IDENTITY();
 INSERT dbo.FundingPlatform_UserRoles(UserId,RoleId) SELECT @ActorId,Id FROM dbo.FundingPlatform_Roles WHERE NormalizedName=N'ADMIN';
 INSERT dbo.FundingPlatform_FundingOpportunities(PublicId,Slug,Title,Description,Summary,SponsorName,
   AmountStatus,DeadlineType,DeadlinePrecision,GeographicScope,RemoteApplication,PublicationStatus,LastVerifiedAtUtc,DataQualityScore,ContentVersion,IsActive)
 VALUES(@Opportunity,@Tag,@Tag,N'Description',N'Summary',@Tag,2,2,0,2,0,0,@Now,100,1,1);
 DECLARE @Id BIGINT=SCOPE_IDENTITY(),@Version BINARY(8);
 SELECT @Version=RowVersion FROM dbo.FundingPlatform_FundingOpportunities WHERE Id=@Id;
 DECLARE @Results TABLE(Json NVARCHAR(MAX));
 INSERT @Results EXEC dbo.FundingPlatform_usp_FundingTranslationGeneration_Reserve @Actor,@Opportunity,N'es',1,@Version,'test-model-snapshot',0.000001,100,1000;
 IF COALESCE((SELECT JSON_VALUE(Json,'$.acquired') FROM @Results),'')<>'true' THROW 56100,N'Generation was not reserved.',1;
 DECLARE @Generation UNIQUEIDENTIFIER=(SELECT CONVERT(UNIQUEIDENTIFIER,JSON_VALUE(Json,'$.generationId')) FROM @Results);
 DELETE @Results;
 INSERT @Results EXEC dbo.FundingPlatform_usp_FundingTranslationGeneration_Reserve @Actor,@Opportunity,N'es',1,@Version,'test-model-snapshot',0.000001,100,1000;
 IF COALESCE((SELECT JSON_VALUE(Json,'$.acquired') FROM @Results),'')<>'false'
    OR COALESCE((SELECT JSON_VALUE(Json,'$.status') FROM @Results),'')<>'processing'
    THROW 56101,N'In-flight attempt was not reused.',1;
 DECLARE @Text NVARCHAR(MAX)=N'{"title":"Título","summary":"Resumen","description":"Descripción","eligibilityDescription":null,"requirements":null,"objectives":null,"allowedActivities":null,"excludedActivities":null,"restrictions":null,"targetOrganizationsDescription":null,"targetPopulationsDescription":null}';
 EXEC dbo.FundingPlatform_usp_FundingTranslationGeneration_Finish @Actor,@Generation,@Text,100,100;
 DELETE @Results;
 INSERT @Results EXEC dbo.FundingPlatform_usp_FundingTranslationGeneration_Reserve @Actor,@Opportunity,N'es',1,@Version,'test-model-snapshot',0.000001,100,1000;
 IF COALESCE((SELECT JSON_VALUE(Json,'$.acquired') FROM @Results),'')<>'false'
    OR COALESCE((SELECT JSON_VALUE(Json,'$.status') FROM @Results),'')<>'completed'
    OR COALESCE((SELECT JSON_VALUE(Json,'$.text.title') FROM @Results),'')<>N'Título'
    THROW 56102,N'Completed proposal was not cached.',1;
 EXEC dbo.FundingPlatform_usp_FundingTranslationGeneration_Finish @Actor,@Generation;
 IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingTranslationGenerations WHERE GenerationId=@Generation AND Status='completed')
    THROW 56103,N'Late failure overwrote completed result.',1;
 IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingTranslations WHERE FundingOpportunityId=@Id)
    OR EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingTranslationHistory WHERE FundingOpportunityId=@Id)
    THROW 56104,N'Proposal became an editorial translation without approval.',1;
 IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE Id=@Id AND (RowVersion<>@Version OR Title<>@Tag OR PublicationStatus<>0))
    THROW 56105,N'Generation mutated the original.',1;
 DELETE @Results;
 INSERT @Results EXEC dbo.FundingPlatform_usp_FundingTranslationGeneration_Reserve @Actor,@Opportunity,N'en',1,@Version,'test-model-snapshot',0.000001,100,1000;
 SET @Generation=(SELECT CONVERT(UNIQUEIDENTIFIER,JSON_VALUE(Json,'$.generationId')) FROM @Results);
 EXEC dbo.FundingPlatform_usp_FundingTranslationGeneration_Finish @Actor,@Generation;
 DELETE @Results;
 INSERT @Results EXEC dbo.FundingPlatform_usp_FundingTranslationGeneration_Reserve @Actor,@Opportunity,N'en',1,@Version,'test-model-snapshot',0.000001,100,1000;
 IF COALESCE((SELECT JSON_VALUE(Json,'$.status') FROM @Results),'')<>'failed'
    OR COALESCE((SELECT JSON_VALUE(Json,'$.acquired') FROM @Results),'')<>'false'
    THROW 56106,N'Failed attempt was retried.',1;
 IF (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingTranslationGenerations WHERE FundingOpportunityId=@Id)<>2
    OR (SELECT SUM(ReservedCostUsd) FROM dbo.FundingPlatform_FundingTranslationGenerations WHERE FundingOpportunityId=@Id)<>0.000002
    THROW 56107,N'Reservations were refunded or duplicated.',1;
 IF EXISTS(SELECT 1 FROM sys.database_permissions WHERE major_id=OBJECT_ID(N'dbo.FundingPlatform_FundingTranslationGenerations')
    AND grantee_principal_id IN(DATABASE_PRINCIPAL_ID('FundingPlatform_ApiRuntimeRole'),DATABASE_PRINCIPAL_ID('FundingPlatform_WorkerRuntimeRole'))
    AND state IN('G','W')) THROW 56108,N'Direct runtime table grant.',1;
 IF @InitialTransactionCount=0 ROLLBACK TRANSACTION;
 ELSE ROLLBACK TRANSACTION FP_Smoke060;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0
 BEGIN
  IF @InitialTransactionCount=0 OR XACT_STATE()=-1 ROLLBACK TRANSACTION;
  ELSE ROLLBACK TRANSACTION FP_Smoke060;
 END;
 THROW;
END CATCH;
