/* Disposable SQL only. Synthetic organization/story; all writes roll back. */
SET NOCOUNT ON; SET XACT_ABORT ON;
DECLARE @InitialTransactionCount INT=@@TRANCOUNT;
IF @InitialTransactionCount=0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke061;
BEGIN TRY
 DECLARE @User UNIQUEIDENTIFIER=NEWID(),@Story UNIQUEIDENTIFIER=NEWID();
 DECLARE @Tag NVARCHAR(80)=N'story-smoke-'+CONVERT(NVARCHAR(36),@User);
 INSERT dbo.FundingPlatform_Users(PublicId,Email,NormalizedEmail,DisplayName,PasswordHash,SecurityStamp,EmailConfirmed,Status,PreferredLocale)
 VALUES(@User,@Tag+N'@example.invalid',UPPER(@Tag+N'@example.invalid'),@Tag,N'not-a-credential',@Tag,1,2,N'es-CL');
 DECLARE @OrgResult TABLE(Id BIGINT,PublicId UNIQUEIDENTIFIER,ProfileVersion INT,RowVersion BINARY(8));
 DECLARE @Snapshot NVARCHAR(MAX)=N'{"name":"Story smoke"}',@Hash BINARY(32)=HASHBYTES('SHA2_256',N'story-smoke');
 INSERT @OrgResult EXEC dbo.FundingPlatform_usp_Organization_CreateForUser @User,N'Story smoke',152,2,@Snapshot,@Hash;
 DECLARE @Org UNIQUEIDENTIFIER=(SELECT PublicId FROM @OrgResult);
 DECLARE @Content NVARCHAR(MAX)=N'{"title":"Historia sintética","summary":null,"body":"Aprendizajes del trabajo en terreno con nuestra comunidad.","kind":"beneficiaries","projectId":null,"categoryIds":[1],"goalIds":[1],"countryIds":[152],"containsPersonalExperiences":true}';
 EXEC dbo.FundingPlatform_usp_Story_Save @User,@Org,@Story,0,@Content;
 DECLARE @Result TABLE(Json NVARCHAR(MAX));
 INSERT @Result EXEC dbo.FundingPlatform_usp_Story_List @OrganizationPublicId=@Org;
 IF COALESCE((SELECT JSON_VALUE(Json,'$.totalCount') FROM @Result),'')<>'0' THROW 56150,N'Draft story leaked.',1;
 DELETE @Result;
 INSERT @Result EXEC dbo.FundingPlatform_usp_Story_List @UserPublicId=@User,@OrganizationPublicId=@Org;
 IF COALESCE((SELECT JSON_VALUE(Json,'$.totalCount') FROM @Result),'')<>'1' THROW 56151,N'Owner cannot see draft.',1;
 -- Fixture readiness only, not a production publication alternative.
 UPDATE dbo.FundingPlatform_Organizations SET ProfileStatus=2,ProfileCompleteness=100 WHERE PublicId=@Org;
 EXEC dbo.FundingPlatform_usp_Story_Publish @User,@Org,@Story,1,1,1,1;
 DELETE @Result;
 INSERT @Result EXEC dbo.FundingPlatform_usp_Story_List @OrganizationPublicId=@Org;
 IF COALESCE((SELECT JSON_VALUE(Json,'$.items[0].id') FROM @Result),'')<>CONVERT(NVARCHAR(36),@Story)
   THROW 56152,N'Consented story was not published.',1;
 IF EXISTS(SELECT 1 FROM @Result WHERE Json LIKE N'%updatedByUser%' OR Json LIKE N'%personalConsentConfirmed%' OR Json LIKE N'%rightsConfirmed%')
   THROW 56153,N'Private audit metadata leaked.',1;
 UPDATE dbo.FundingPlatform_Organizations SET ProfileStatus=0 WHERE PublicId=@Org;
 IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_StoryPublicReady() WHERE PublicId=@Story) THROW 56154,N'Private organization story leaked.',1;
 UPDATE dbo.FundingPlatform_Organizations SET ProfileStatus=2 WHERE PublicId=@Org;
 EXEC dbo.FundingPlatform_usp_Story_Save @User,@Org,@Story,2,@Content;
 IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_StoryPublicReady() WHERE PublicId=@Story) THROW 56155,N'Edited story stayed public.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_Stories WHERE PublicId=@Story AND Revision=3 AND RightsConfirmed=0 AND PersonalConsentConfirmed=0)
   THROW 56156,N'Edit did not reset consent.',1;
 EXEC dbo.FundingPlatform_usp_Story_Publish @User,@Org,@Story,3,1,1,1;
 EXEC dbo.FundingPlatform_usp_Story_Publish @User,@Org,@Story,4,0,0,0;
 IF EXISTS(SELECT 1 FROM dbo.FundingPlatform_ifn_StoryPublicReady() WHERE PublicId=@Story) THROW 56157,N'Withdrawn story stayed public.',1;
 IF (SELECT COUNT(*) FROM dbo.FundingPlatform_StoryHistory WHERE StoryPublicId=@Story)<>5 THROW 56158,N'History incomplete.',1;
 IF @InitialTransactionCount=0 ROLLBACK TRANSACTION;
 ELSE ROLLBACK TRANSACTION FP_Smoke061;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0
 BEGIN
  IF @InitialTransactionCount=0 OR XACT_STATE()=-1 ROLLBACK TRANSACTION;
  ELSE ROLLBACK TRANSACTION FP_Smoke061;
 END;
 THROW;
END CATCH;
