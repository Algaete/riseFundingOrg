/* Synthetic data only; all fixture and translation changes are rolled back. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke058;
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
 DECLARE @Keyword NVARCHAR(80) = N'prueba' + REPLACE(CONVERT(NVARCHAR(36), NEWID()),N'-',N'');
 DECLARE @SummaryKeyword NVARCHAR(100) = @Keyword + N'resumen';
 DECLARE @Title NVARCHAR(150) = @Keyword + N' Educación';
 DECLARE @AccentQuery NVARCHAR(150) = @Keyword + N' educacion';
 DECLARE @Text NVARCHAR(MAX) = (SELECT @Title AS title, @SummaryKeyword AS summary, N'Descripción' AS description FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
 DECLARE @Result TABLE(Json NVARCHAR(MAX));
 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingTranslation_Save @Actor,@Opportunity,N'es',1,0,0,@Text,@Version;
 IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_FundingTranslationSearch(@Keyword))
    THROW 56070,N'Draft must not match translated search.',1;
 DELETE @Result;
 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingTranslation_Save @Actor,@Opportunity,N'es',1,1,1,@Text,@Version;
 IF (SELECT COUNT(*) FROM dbo.FundingPlatform_ifn_FundingTranslationSearch(@Keyword) WHERE FundingOpportunityId = @Id AND TextRank = 800) <> 1
    THROW 56071,N'Reviewed title must match with literal rank.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_FundingTranslationSearch(@AccentQuery) WHERE FundingOpportunityId = @Id AND TextRank = 1000)
    THROW 56072,N'Translated matching must ignore accents and letter case.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_FundingTranslationSearch(@SummaryKeyword) WHERE FundingOpportunityId = @Id AND TextRank = 400)
    THROW 56073,N'Reviewed summary must be searchable.',1;
 IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_FundingTranslationSearch(NULL))
    OR EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_FundingTranslationSearch(N'   '))
    THROW 56074,N'Empty query must not scan translations into results.',1;
 DECLARE @LiteralQuery NVARCHAR(120) = @Keyword + N'%[_]~';
 IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_FundingTranslationSearch(@LiteralQuery))
    THROW 56075,N'Query wildcards must be treated literally.',1;
 UPDATE dbo.FundingPlatform_FundingTranslations SET TextJson = JSON_MODIFY(TextJson,'$.summary',@LiteralQuery)
 WHERE FundingOpportunityId = @Id AND Language = 'es';
 IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_FundingTranslationSearch(@LiteralQuery) WHERE FundingOpportunityId = @Id AND TextRank = 400)
    THROW 56089,N'Literal punctuation must still find an exact substring.',1;
 UPDATE dbo.FundingPlatform_FundingTranslations SET TextJson = @Text WHERE FundingOpportunityId = @Id AND Language = 'es';

 /* Both language rows match the same opportunity; counts must stay at one. */
 DELETE @Result;
 DECLARE @English NVARCHAR(MAX) = (SELECT @Keyword + N' Education' AS title, @SummaryKeyword AS summary, N'Description' AS description FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingTranslation_Save @Actor,@Opportunity,N'en',1,0,1,@English,@Version;
 DECLARE @EnglishQuery NVARCHAR(150) = @Keyword + N' Education';
 IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_FundingTranslationSearch(@EnglishQuery) WHERE FundingOpportunityId = @Id AND TextRank = 1000)
    THROW 56090,N'English reviewed title must match independently of Spanish.',1;
 IF (SELECT COUNT(*) FROM dbo.FundingPlatform_ifn_FundingTranslationSearch(@Keyword) WHERE FundingOpportunityId = @Id) <> 1
    THROW 56076,N'Two language matches duplicated an opportunity.',1;
 UPDATE dbo.FundingPlatform_FundingTranslations SET Reviewed = 0 WHERE FundingOpportunityId = @Id AND Language = 'es';
 IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_FundingTranslationSearch(@AccentQuery) WHERE FundingOpportunityId = @Id)
    THROW 56091,N'Withdrawal of review must remove translated search match.',1;
 UPDATE dbo.FundingPlatform_FundingTranslations SET Reviewed = 1 WHERE FundingOpportunityId = @Id AND Language = 'es';
 DECLARE @Filters NVARCHAR(MAX) = (SELECT @Keyword AS query, 1 AS page, 1 AS pageSize, CAST(0 AS BIT) AS onlyOpen FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
 DELETE @Result;
 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingDiscovery_Search @Filters;
 IF COALESCE((SELECT JSON_VALUE(Json,'$.totalCount') FROM @Result),N'') <> N'0'
    THROW 56077,N'Existing callers must retain original-only search by default.',1;
 DELETE @Result;
 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingDiscovery_Search @Filters,1;
 IF COALESCE((SELECT JSON_VALUE(Json,'$.totalCount') FROM @Result),N'') <> N'1'
    OR COALESCE((SELECT JSON_VALUE(Json,'$.items[0].id') FROM @Result),N'') <> CONVERT(NVARCHAR(36),@Opportunity)
    THROW 56078,N'Translated discovery search must match before counting and paging.',1;
 DELETE @Result;
 SET @Filters = JSON_MODIFY(@Filters,'$.page',2);
 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingDiscovery_Search @Filters,1;
 IF COALESCE((SELECT JSON_VALUE(Json,'$.totalCount') FROM @Result),N'') <> N'1'
    OR EXISTS(SELECT 1 FROM @Result CROSS APPLY OPENJSON(Json,'$.items'))
    THROW 56079,N'Translated page beyond the result must retain count and return no items.',1;
 DELETE @Result;
 SET @Filters = JSON_MODIFY(@Filters,'$.page',1);
 SET @Filters = JSON_MODIFY(@Filters,'$.categoryId',2);
 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingDiscovery_Search @Filters,1;
 IF COALESCE((SELECT JSON_VALUE(Json,'$.totalCount') FROM @Result),N'') <> N'0'
    THROW 56080,N'Translated matching must not bypass category filters.',1;
 DELETE @Result;
 SET @Filters = JSON_MODIFY(@Filters,'$.categoryId',NULL);
 SET @Filters = JSON_MODIFY(@Filters,'$.languageId',1);
 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingDiscovery_Search @Filters,1;
 IF COALESCE((SELECT JSON_VALUE(Json,'$.totalCount') FROM @Result),N'') <> N'0'
    THROW 56081,N'Translation language must not become eligibility language.',1;
 SET @Filters = JSON_MODIFY(@Filters,'$.languageId',NULL);

 /* Real organization procedure: shared matching, count and unchanged membership gate. */
 DECLARE @OrgPublicId UNIQUEIDENTIFIER = NEWID();
 INSERT dbo.FundingPlatform_Organizations(PublicId,CreatedByUserId,Name,HomeCountryId,OrganizationTypeId)
 VALUES(@OrgPublicId,@UserId,@Tag,152,1);
 DECLARE @OrgId BIGINT = SCOPE_IDENTITY();
 INSERT dbo.FundingPlatform_OrganizationUsers(OrganizationId,UserId,Role,MembershipStatus,JoinedAtUtc)
 VALUES(@OrgId,@UserId,1,1,@Now);
 DECLARE @Countries dbo.FundingPlatform_SmallIntIdList, @Regions dbo.FundingPlatform_IntIdList,
   @Categories dbo.FundingPlatform_IntIdList, @Tags dbo.FundingPlatform_BigIntIdList,
   @Beneficiaries dbo.FundingPlatform_IntIdList, @Projects dbo.FundingPlatform_IntIdList,
   @FundingTypes dbo.FundingPlatform_SmallIntIdList, @OrganizationTypes dbo.FundingPlatform_SmallIntIdList,
   @Funders dbo.FundingPlatform_GuidIdList, @Count BIGINT, @Mode NVARCHAR(20);
 DECLARE @Enabled BIT = 0;
 WHILE 1 = 1
 BEGIN
  EXEC dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch
   @UserPublicId=@Actor,@OrganizationPublicId=@OrgPublicId,@Query=@Keyword,@Sort=N'relevance',@PageNumber=2,@PageSize=1,
   @CountryIds=@Countries,@RegionIds=@Regions,@CategoryIds=@Categories,@TagIds=@Tags,
   @BeneficiaryTypeIds=@Beneficiaries,@ProjectTypeIds=@Projects,@FundingTypeIds=@FundingTypes,
   @OrganizationTypeIds=@OrganizationTypes,@FunderPublicIds=@Funders,
   @MatchedCount=@Count OUTPUT,@EffectiveSearchMode=@Mode OUTPUT,@IncludeReviewedTranslations=@Enabled;
  IF (@Enabled = 0 AND @Count <> 0) OR (@Enabled = 1 AND @Count <> 1)
    THROW 56082,N'Organization search flag/count mismatch.',1;
  IF @Mode NOT IN (N'full-text',N'literal-fallback') THROW 56083,N'Canonical search mode lost.',1;
  IF @Enabled = 1 BREAK;
  SET @Enabled = 1;
 END;
 /* Public procedure emits both result sets; static tests also require the same
    translation predicate in its count and page queries. */
 EXEC dbo.FundingPlatform_usp_FundingOpportunity_Public_List @Keyword,1,1,1;
 EXEC dbo.FundingPlatform_usp_FundingOpportunity_Public_List @Keyword,2,1,1;

 /* Match in original + both translations still yields one item. */
 UPDATE dbo.FundingPlatform_FundingOpportunities SET Title = @Title WHERE Id = @Id;
 DELETE @Result;
 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingDiscovery_Search @Filters,1;
 IF COALESCE((SELECT JSON_VALUE(Json,'$.totalCount') FROM @Result),N'') <> N'1'
    THROW 56084,N'Original plus translations duplicated discovery result.',1;
 UPDATE dbo.FundingPlatform_FundingOpportunities SET Title = @Tag, ContentVersion = 2 WHERE Id = @Id;
 IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_FundingTranslationSearch(@Keyword))
    THROW 56085,N'Stale translations must never match.',1;
 DELETE @Result;
 INSERT @Result EXEC dbo.FundingPlatform_usp_FundingDiscovery_Search @Filters,1;
 IF COALESCE((SELECT JSON_VALUE(Json,'$.totalCount') FROM @Result),N'') <> N'0'
    THROW 56086,N'Stale translation leaked through discovery.',1;

 /* Restore only our fixture version, then test publication removal. All rolled back. */
 UPDATE dbo.FundingPlatform_FundingOpportunities SET ContentVersion = 1 WHERE Id = @Id;
 UPDATE dbo.FundingPlatform_Funders SET PublicationStatus = 0 WHERE Id = @FunderId;
 IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_FundingTranslationSearch(@Keyword))
    THROW 56087,N'Unpublished funder must remove translated match.',1;
 UPDATE dbo.FundingPlatform_Funders SET PublicationStatus = 2 WHERE Id = @FunderId;
 UPDATE dbo.FundingPlatform_FundingOpportunities SET IsActive = 0, PublicationStatus = 4 WHERE Id = @Id;
 IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_FundingTranslationSearch(@Keyword))
    THROW 56088,N'Inactive opportunity must remove translated match.',1;
 IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
 ELSE ROLLBACK TRANSACTION FP_Smoke058;
END TRY
BEGIN CATCH
 IF XACT_STATE() <> 0
 BEGIN
  IF @InitialTransactionCount = 0 OR XACT_STATE() = -1 ROLLBACK TRANSACTION;
  ELSE ROLLBACK TRANSACTION FP_Smoke058;
 END;
 THROW;
END CATCH;
