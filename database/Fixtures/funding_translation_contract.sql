/* Invoked only inside the migrator's rollback transaction. @Tag is a unique parameter. */
SET NOCOUNT ON;
IF @@TRANCOUNT = 0 THROW 56092, N'Translation verification requires a transaction.', 1;
DECLARE @Now DATETIME2(7) = SYSUTCDATETIME(), @Actor UNIQUEIDENTIFIER = NEWID();
INSERT dbo.FundingPlatform_Users(PublicId,Email,NormalizedEmail,DisplayName,PasswordHash,SecurityStamp,EmailConfirmed,Status,PreferredLocale,TwoFactorEnabled)
VALUES(@Actor,@Tag + N'@example.invalid',UPPER(@Tag + N'@example.invalid'),@Tag,N'not-a-credential',@Tag,1,2,N'es-CL',1);
DECLARE @UserId BIGINT = SCOPE_IDENTITY();
INSERT dbo.FundingPlatform_Funders(PublicId,Slug,Name,NormalizedName,WebsiteUrl,PublicationStatus,PublishedAtUtc,ReviewedAtUtc,ContentVersion,IsActive,CreatedAtUtc,UpdatedAtUtc)
VALUES(NEWID(),@Tag,@Tag,UPPER(@Tag),N'https://example.invalid/funder',2,@Now,@Now,1,1,@Now,@Now);
DECLARE @FunderId BIGINT = SCOPE_IDENTITY();
DECLARE @SourceId INT = (SELECT TOP(1) Id FROM dbo.FundingPlatform_FundingSources WHERE IsEnabled = 1 ORDER BY Id);
DECLARE @Fixtures TABLE(Scenario NVARCHAR(30), Id BIGINT, PublicId UNIQUEIDENTIFIER, Title NVARCHAR(350), Summary NVARCHAR(2000));
DECLARE @Cases TABLE(Ordinal INT PRIMARY KEY, Scenario NVARCHAR(30), Reviewed BIT, SourceVersion INT, Active BIT);
INSERT @Cases VALUES(1,N'title',1,1,1),(2,N'summary',1,1,1),(3,N'draft',0,1,1),(4,N'stale',1,2,1),(5,N'inactive',1,1,0);
DECLARE @Index INT = 1;
WHILE @Index <= 5
BEGIN
 DECLARE @Scenario NVARCHAR(30), @Reviewed BIT, @ContentVersion INT, @Active BIT;
 SELECT @Scenario=Scenario,@Reviewed=Reviewed,@ContentVersion=SourceVersion,@Active=Active FROM @Cases WHERE Ordinal=@Index;
 DECLARE @PublicId UNIQUEIDENTIFIER = NEWID(), @Title NVARCHAR(350) = N'TEST original ' + @Scenario + N' ' + @Tag,
   @Summary NVARCHAR(2000) = N'TEST original summary', @Slug NVARCHAR(320) = @Tag + N'-' + @Scenario;
 INSERT dbo.FundingPlatform_FundingOpportunities(PublicId,Slug,Title,Description,Summary,SponsorName,
   Currency,MinAmount,MaxAmount,AmountStatus,DeadlineType,DeadlinePrecision,GeographicScope,RemoteApplication,
   PublicationStatus,PublishedAtUtc,LastVerifiedAtUtc,DataQualityScore,ContentVersion,IsActive,ReviewedAtUtc,CoverKey)
 VALUES(@PublicId,@Slug,@Title,N'TEST original description',@Summary,@Tag,'USD',100,1000,1,2,0,2,0,
   CASE WHEN @Active=0 THEN 4 ELSE 2 END,@Now,@Now,100,@ContentVersion,@Active,@Now,N'education-v1');
 DECLARE @Id BIGINT = SCOPE_IDENTITY();
 INSERT @Fixtures VALUES(@Scenario,@Id,@PublicId,@Title,@Summary);
 INSERT dbo.FundingPlatform_FundingOpportunityCategories(FundingOpportunityId,FundingCategoryId) VALUES(@Id,1);
 INSERT dbo.FundingPlatform_FundingOpportunityFunders(FundingOpportunityId,FunderId,Role,IsActive,CreatedAtUtc,UpdatedAtUtc) VALUES(@Id,@FunderId,1,1,@Now,@Now);
 DECLARE @Hash BINARY(32) = HASHBYTES('SHA2_256',@Slug);
 INSERT dbo.FundingPlatform_FundingOpportunitySourceLinks(FundingOpportunityId,FundingSourceId,SourceItemKeyHash,SourceUrl,CanonicalUrlHash,FirstSeenAtUtc,LastSeenAtUtc,IsPrimary,IsActive)
 VALUES(@Id,@SourceId,@Hash,N'https://example.invalid/' + @Slug,@Hash,@Now,@Now,1,1);
 INSERT dbo.FundingPlatform_FundingFieldEvidence(FundingOpportunityId,FieldPath,ValueJson,ExtractionMethod,IsSelected,IsManualLock,CreatedAtUtc)
 SELECT @Id,path,N'{"status":"unknown","value":null}',1,1,0,@Now
 FROM (VALUES(N'/title'),(N'/description'),(N'/eligibilityDescription'),(N'/closeDate')) fields(path);
 DECLARE @Spanish NVARCHAR(MAX) = (SELECT
   CASE WHEN @Scenario=N'summary' THEN N'TEST beca revisada' ELSE N'TEST educación traducida-' + @Tag END AS title,
   CASE WHEN @Scenario=N'summary' THEN N'TEST resumen traducida-' + @Tag ELSE N'TEST resumen revisado' END AS summary,
   N'TEST descripción revisada' AS description FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
 INSERT dbo.FundingPlatform_FundingTranslations(FundingOpportunityId,Language,SourceContentVersion,Revision,Reviewed,TextJson,UpdatedByUserId,UpdatedAtUtc)
 VALUES(@Id,'es',1,1,@Reviewed,@Spanish,@UserId,@Now);
 IF @Scenario=N'title'
 BEGIN
  DECLARE @English NVARCHAR(MAX) = (SELECT N'TEST education traducida-' + @Tag AS title,N'TEST reviewed summary' AS summary,N'TEST reviewed description' AS description FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
  INSERT dbo.FundingPlatform_FundingTranslations(FundingOpportunityId,Language,SourceContentVersion,Revision,Reviewed,TextJson,UpdatedByUserId,UpdatedAtUtc)
  VALUES(@Id,'en',1,1,1,@English,@UserId,@Now);
 END;
 SET @Index += 1;
END;
SELECT Scenario,Id,PublicId,Title,Summary,@FunderId AS FunderId FROM @Fixtures;
