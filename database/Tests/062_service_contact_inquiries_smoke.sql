/* Disposable SQL only. Synthetic requests; no real mail; rollback. */
SET NOCOUNT ON; SET XACT_ABORT ON;
DECLARE @InitialTransactionCount INT=@@TRANCOUNT;
IF @InitialTransactionCount=0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke062;
BEGIN TRY
 DECLARE @Id UNIQUEIDENTIFIER=NEWID(),@Actor UNIQUEIDENTIFIER=NEWID();
 DECLARE @Tag NVARCHAR(80)=N'inquiry-smoke-'+CONVERT(NVARCHAR(36),@Actor);
 INSERT dbo.FundingPlatform_Users(PublicId,Email,NormalizedEmail,DisplayName,PasswordHash,SecurityStamp,EmailConfirmed,Status,PreferredLocale,TwoFactorEnabled)
 VALUES(@Actor,@Tag+N'@example.invalid',UPPER(@Tag+N'@example.invalid'),@Tag,N'not-a-credential',@Tag,1,2,N'es-CL',1);
 DECLARE @ActorId BIGINT=SCOPE_IDENTITY();
 INSERT dbo.FundingPlatform_UserRoles(UserId,RoleId) SELECT @ActorId,Id FROM dbo.FundingPlatform_Roles WHERE NormalizedName=N'ADMIN';
 DECLARE @Data NVARCHAR(MAX)=N'{"name":"Synthetic inquiry","email":"test@example.invalid","organization":null,"countryId":152,"topic":"service","serviceCode":"translation","projectReference":null,"fundingReference":null,"deadline":null,"description":"Please help review a synthetic project document.","consentToContact":true,"website":null}';
 SET @Data=JSON_MODIFY(JSON_MODIFY(@Data,'$.email',@Tag+N'@example.invalid'),'$.requestId',CONVERT(NVARCHAR(36),@Id));
 DECLARE @Hash BINARY(32)=HASHBYTES('SHA2_256',@Data);
 DECLARE @Result TABLE(Json NVARCHAR(MAX));
 INSERT @Result EXEC dbo.FundingPlatform_usp_Inquiry_Capture @Id,@Data,@Hash;
 IF COALESCE((SELECT JSON_VALUE(Json,'$.wasReplay') FROM @Result),'')<>'false' THROW 56160,N'Capture failed.',1;
 IF EXISTS(SELECT 1 FROM @Result WHERE Json LIKE N'%email%' OR Json LIKE N'%description%') THROW 56161,N'Receipt leaked private data.',1;
 DELETE @Result;
 INSERT @Result EXEC dbo.FundingPlatform_usp_Inquiry_Capture @Id,@Data,@Hash;
 IF COALESCE((SELECT JSON_VALUE(Json,'$.wasReplay') FROM @Result),'')<>'true' THROW 56162,N'Replay duplicated capture.',1;
 IF (SELECT COUNT(*) FROM dbo.FundingPlatform_Inquiries WHERE RequestId=@Id)<>1 THROW 56163,N'Duplicate inquiry.',1;
 DELETE @Result;
 INSERT @Result EXEC dbo.FundingPlatform_usp_Inquiry_ClaimNotification @Id;
 IF COALESCE((SELECT JSON_VALUE(Json,'$.requestId') FROM @Result),'')<>CONVERT(NVARCHAR(36),@Id) THROW 56164,N'Notification not claimed.',1;
 DELETE @Result;
 INSERT @Result EXEC dbo.FundingPlatform_usp_Inquiry_ClaimNotification @Id;
 IF EXISTS(SELECT 1 FROM @Result WHERE Json IS NOT NULL) THROW 56165,N'Notification claimed twice.',1;
 EXEC dbo.FundingPlatform_usp_Inquiry_FinishNotification @Id,0;
 IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_Inquiries WHERE RequestId=@Id AND NotificationStatus=3) THROW 56166,N'Failed notice lost request.',1;
 EXEC dbo.FundingPlatform_usp_Inquiry_Review @Actor,@Id,1,1;
 IF NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_Inquiries WHERE RequestId=@Id AND Status=1 AND Revision=2 AND ReviewedByUserId=@ActorId)
   THROW 56167,N'Admin review did not persist.',1;
 IF @InitialTransactionCount=0 ROLLBACK TRANSACTION;
 ELSE ROLLBACK TRANSACTION FP_Smoke062;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0
 BEGIN
  IF @InitialTransactionCount=0 OR XACT_STATE()=-1 ROLLBACK TRANSACTION;
  ELSE ROLLBACK TRANSACTION FP_Smoke062;
 END;
 THROW;
END CATCH;
