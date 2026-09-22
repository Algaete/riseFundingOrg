/* Synthetic data only; all fixture and translation changes are rolled back. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke057;
BEGIN TRY
 DECLARE @Actor UNIQUEIDENTIFIER = NEWID(), @Opportunity UNIQUEIDENTIFIER = NEWID(), @Now DATETIME2(7) = SYSUTCDATETIME();
 DECLARE @Tag NVARCHAR(80) = N'translation-smoke-' + CONVERT(NVARCHAR(36), @Actor);
 INSERT dbo.FundingPlatform_Users(PublicId,Email,NormalizedEmail,DisplayName,PasswordHash,SecurityStamp,EmailConfirmed,Status,PreferredLocale,TwoFactorEnabled)
 VALUES(@Actor,@Tag + N'@example.invalid',UPPER(@Tag + N'@example.invalid'),@Tag,N'not-a-credential',@Tag,1,2,N'es-CL',1);
 DECLARE @UserId BIGINT = SCOPE_IDENTITY();
 INSERT dbo.FundingPlatform_UserRoles(UserId,RoleId) SELECT @UserId,Id FROM dbo.FundingPlatform_Roles WHERE NormalizedName = N'ADMIN';
 INSERT dbo.FundingPlatform_Funders(PublicId,Slug,Name,NormalizedName,WebsiteUrl,PublicationStatus,PublishedAtUtc,ReviewedAtUtc,ContentVersion,IsActive,CreatedAtUtc,UpdatedAtUtc)
 VALUES(NEWID(),@Tag,@Tag,UPPER(@Tag),N'https://example.invalid/funder',2,@Now,@Now,1,1,@Now,@Now);
 DECLARE @FunderId BIGINT = SCOPE_IDENTITY();
 INSERT dbo.FundingPlatform_FundingOpportunities(PublicId,Slug,Title,Description,Summary,SponsorName,
    AmountStatus,DeadlineType,DeadlinePrecision,GeographicScope,RemoteApplication,PublicationStatus,PublishedAtUtc,LastVerifiedAtUtc,DataQualityScore,ContentVersion,IsActive,ReviewedAtUtc)
 VALUES(@Opportunity,@Tag,@Tag,N'Description',N'Summary',@Tag,2,2,0,2,0,2,@Now,@Now,100,1,1,@Now);
 DECLARE @Id BIGINT = SCOPE_IDENTITY();
 INSERT dbo.FundingPlatform_FundingOpportunityCategories(FundingOpportunityId,FundingCategoryId) VALUES(@Id,1);
 INSERT dbo.FundingPlatform_FundingOpportunityFunders(FundingOpportunityId,FunderId,Role,IsActive,CreatedAtUtc,UpdatedAtUtc) VALUES(@Id,@FunderId,1,1,@Now,@Now);
 DECLARE @SourceId INT = (SELECT TOP(1) Id FROM dbo.FundingPlatform_FundingSources WHERE IsEnabled = 1 ORDER BY Id);
 DECLARE @Hash BINARY(32) = HASHBYTES('SHA2_256',@Tag);
 INSERT dbo.FundingPlatform_FundingOpportunitySourceLinks(FundingOpportunityId,FundingSourceId,SourceItemKeyHash,SourceUrl,CanonicalUrlHash,FirstSeenAtUtc,LastSeenAtUtc,IsPrimary,IsActive)
 VALUES(@Id,@SourceId,@Hash,N'https://example.invalid/terms',@Hash,@Now,@Now,1,1);
 INSERT dbo.FundingPlatform_FundingFieldEvidence(FundingOpportunityId,FieldPath,ValueJson,ExtractionMethod,IsSelected,IsManualLock,CreatedAtUtc)
 SELECT @Id,path,N'{"status":"unknown","value":null}',1,1,0,@Now
 FROM (VALUES(N'/title'),(N'/description'),(N'/eligibilityDescription'),(N'/closeDate')) fields(path);
 IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_FundingOpportunityPublicReady() WHERE FundingOpportunityId = @Id)
    THROW 56040,N'Synthetic opportunity must be public-ready.',1;
 DECLARE @Version BINARY(8) = (SELECT RowVersion FROM dbo.FundingPlatform_FundingOpportunities WHERE Id = @Id);
 DECLARE @Text NVARCHAR(MAX) = N'{"title":"Traducido","summary":"Resumen","description":"Descripción"}';
 DECLARE @Result TABLE(Json NVARCHAR(MAX));
 DECLARE @Refs NVARCHAR(MAX) = N'[{"opportunityId":"' + CONVERT(NVARCHAR(36), @Opportunity) + N'","sourceContentVersion":1}]';
 DECLARE @Summaries TABLE(OpportunityId UNIQUEIDENTIFIER, Language VARCHAR(2), SourceContentVersion INT,
    Revision INT, Reviewed BIT, Title NVARCHAR(350), Summary NVARCHAR(2000));

 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingTranslation_Save @Actor,@Opportunity,N'es',1,0,0,@Text,@Version;
 IF COALESCE((SELECT JSON_VALUE(Json,'$.revision') FROM @Result),N'') <> N'1' THROW 56041,N'Draft not saved.',1;
 DELETE @Result;
 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingTranslation_Read @Opportunity,N'es',1;
 IF EXISTS(SELECT 1 FROM @Result WHERE Json IS NOT NULL) THROW 56042,N'Draft exposed.',1;

 INSERT @Summaries EXEC dbo.FundingPlatform_usp_FundingTranslation_ReadSummaries @Refs,N'es';
 IF EXISTS(SELECT 1 FROM @Summaries) THROW 56061,N'Draft list translation exposed.',1;
 DELETE @Result;
 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingTranslation_Save @Actor,@Opportunity,N'es',1,1,1,@Text,@Version;
 DELETE @Result;
 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingTranslation_Read @Opportunity,N'es',1;
 IF COALESCE((SELECT JSON_VALUE(Json,'$.text.title') FROM @Result),N'') <> N'Traducido' THROW 56043,N'Reviewed translation missing.',1;

 INSERT @Summaries EXEC dbo.FundingPlatform_usp_FundingTranslation_ReadSummaries @Refs,N'es';
 IF (SELECT COUNT(*) FROM @Summaries) <> 1 OR NOT EXISTS(SELECT 1 FROM @Summaries
    WHERE OpportunityId = @Opportunity AND Title = N'Traducido' AND Summary = N'Resumen' AND Revision = 2)
    THROW 56062,N'Reviewed list translation missing.',1;
 DELETE @Summaries;
 INSERT @Summaries EXEC dbo.FundingPlatform_usp_FundingTranslation_ReadSummaries @Refs,N'en';
 IF EXISTS(SELECT 1 FROM @Summaries) THROW 56063,N'Wrong language in list.',1;
 INSERT @Summaries EXEC dbo.FundingPlatform_usp_FundingTranslation_ReadSummaries N'[]',N'es';
 IF EXISTS(SELECT 1 FROM @Summaries) THROW 56064,N'Empty list requested unrelated translations.',1;
 IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_FundingOpportunities WHERE Id = @Id AND (RowVersion <> @Version OR Title <> @Tag))
    THROW 56044,N'Original was mutated.',1;
 DELETE @Result;
 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingTranslation_Read @Opportunity,N'en',1;
 IF EXISTS(SELECT 1 FROM @Result WHERE Json IS NOT NULL) THROW 56045,N'Wrong language exposed.',1;
 UPDATE dbo.FundingPlatform_FundingOpportunities SET ContentVersion = 2 WHERE Id = @Id;

 INSERT @Summaries EXEC dbo.FundingPlatform_usp_FundingTranslation_ReadSummaries @Refs,N'es';
 IF EXISTS(SELECT 1 FROM @Summaries) THROW 56065,N'List used stale source snapshot.',1;
 DELETE @Result;
 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingTranslation_Read @Opportunity,N'es',1;
 IF EXISTS(SELECT 1 FROM @Result WHERE Json IS NOT NULL) THROW 56046,N'Stale translation exposed to old source snapshot.',1;
 DELETE @Result;
 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingTranslation_Read @Opportunity,N'es',2;
 IF EXISTS(SELECT 1 FROM @Result WHERE Json IS NOT NULL) THROW 56047,N'Stale translation exposed to current source snapshot.',1;
 DELETE @Result;
 SET @Version = (SELECT RowVersion FROM dbo.FundingPlatform_FundingOpportunities WHERE Id = @Id);
 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingTranslation_Save @Actor,@Opportunity,N'es',2,2,1,@Text,@Version;
 UPDATE dbo.FundingPlatform_Funders SET PublicationStatus = 0 WHERE Id = @FunderId;

 SET @Refs = REPLACE(@Refs, N'"sourceContentVersion":1', N'"sourceContentVersion":2');
 INSERT @Summaries EXEC dbo.FundingPlatform_usp_FundingTranslation_ReadSummaries @Refs,N'es';
 IF EXISTS(SELECT 1 FROM @Summaries) THROW 56066,N'List bypassed public readiness.',1;
 DELETE @Result;
 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingTranslation_Read @Opportunity,N'es',2;
 IF EXISTS(SELECT 1 FROM @Result WHERE Json IS NOT NULL) THROW 56048,N'Translation bypassed public readiness.',1;
 DELETE @Result;
 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingTranslation_AdminGet @Actor,@Opportunity,N'es';
 IF COALESCE((SELECT JSON_VALUE(Json,'$.revision') FROM @Result),N'') <> N'3' THROW 56049,N'Admin read missing revision.',1;
 IF (SELECT COUNT(*) FROM dbo.FundingPlatform_FundingTranslationHistory WHERE FundingOpportunityId = @Id) <> 3
    THROW 56050,N'Immutable revision history missing.',1;
 IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
 ELSE ROLLBACK TRANSACTION FP_Smoke057;
END TRY
BEGIN CATCH
 IF XACT_STATE() <> 0
 BEGIN
  IF @InitialTransactionCount = 0 OR XACT_STATE() = -1 ROLLBACK TRANSACTION;
  ELSE ROLLBACK TRANSACTION FP_Smoke057;
 END;
 THROW;
END CATCH;
