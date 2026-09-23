/* Private, quote-only inquiries. No price, subscription entitlement, payment or AI call. */
SET NOCOUNT ON; SET XACT_ABORT ON;
IF OBJECT_ID(N'dbo.FundingPlatform_Inquiries',N'U') IS NULL
BEGIN
 CREATE TABLE dbo.FundingPlatform_Inquiries(
  RequestId UNIQUEIDENTIFIER NOT NULL CONSTRAINT FundingPlatform_PK_Inquiries PRIMARY KEY, RequestHash BINARY(32) NOT NULL, EmailHash BINARY(32) NOT NULL,
  CountryId SMALLINT NOT NULL, DataJson NVARCHAR(MAX) NOT NULL, Status TINYINT NOT NULL CONSTRAINT FundingPlatform_DF_Inquiry_Status DEFAULT 0,
  NotificationStatus TINYINT NOT NULL CONSTRAINT FundingPlatform_DF_Inquiry_Notification DEFAULT 0,
  Revision INT NOT NULL CONSTRAINT FundingPlatform_DF_Inquiry_Revision DEFAULT 1,
  CreatedAtUtc DATETIME2(7) NOT NULL, UpdatedAtUtc DATETIME2(7) NOT NULL, ReviewedByUserId BIGINT NULL,
  CONSTRAINT FundingPlatform_FK_Inquiry_Country FOREIGN KEY(CountryId) REFERENCES dbo.FundingPlatform_Countries(Id),
  CONSTRAINT FundingPlatform_FK_Inquiry_Reviewer FOREIGN KEY(ReviewedByUserId) REFERENCES dbo.FundingPlatform_Users(Id),
  CONSTRAINT FundingPlatform_CK_Inquiry_Data CHECK(ISJSON(DataJson,OBJECT)=1 AND Status IN(0,1,2) AND NotificationStatus IN(0,1,2,3) AND Revision>0)
 );
 CREATE INDEX FundingPlatform_IX_Inquiry_Email ON dbo.FundingPlatform_Inquiries(EmailHash,CreatedAtUtc);
 CREATE INDEX FundingPlatform_IX_Inquiry_Created ON dbo.FundingPlatform_Inquiries(CreatedAtUtc DESC);
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Inquiry_Capture
 @RequestId UNIQUEIDENTIFIER,@DataJson NVARCHAR(MAX),@RequestHash BINARY(32)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF @RequestId IS NULL OR @RequestHash IS NULL OR @DataJson IS NULL OR ISJSON(@DataJson,OBJECT)<>1 OR DATALENGTH(@DataJson)>100000
   THROW 56132,N'Invalid inquiry.',1;
 DECLARE @Name NVARCHAR(MAX),@Email NVARCHAR(MAX),@Description NVARCHAR(MAX),@Country SMALLINT,
   @Topic NVARCHAR(100),@Service NVARCHAR(100),@Org NVARCHAR(MAX),@Project NVARCHAR(MAX),@Funding NVARCHAR(MAX);
 SELECT @Name=Name,@Email=Email,@Description=Description,@Country=CountryId,@Topic=Topic,@Service=ServiceCode,
   @Org=Organization,@Project=ProjectReference,@Funding=FundingReference FROM OPENJSON(@DataJson)
 WITH(Name NVARCHAR(MAX) '$.name',Email NVARCHAR(MAX) '$.email',Description NVARCHAR(MAX) '$.description',
   CountryId SMALLINT '$.countryId',Topic NVARCHAR(100) '$.topic',ServiceCode NVARCHAR(100) '$.serviceCode',
   Organization NVARCHAR(MAX) '$.organization',ProjectReference NVARCHAR(MAX) '$.projectReference',FundingReference NVARCHAR(MAX) '$.fundingReference');
 IF LEN(TRIM(COALESCE(@Name,N'')))<2 OR DATALENGTH(@Name)>300 OR @Email IS NULL OR @Email NOT LIKE N'%_@_%._%' OR DATALENGTH(@Email)>508
   OR LEN(TRIM(COALESCE(@Description,N'')))<20 OR DATALENGTH(@Description)>10000
   OR DATALENGTH(@Org)>500 OR DATALENGTH(@Project)>2000 OR DATALENGTH(@Funding)>2000
   OR COALESCE(JSON_VALUE(@DataJson,'$.consentToContact'),'false')<>'true' OR NULLIF(JSON_VALUE(@DataJson,'$.website'),N'') IS NOT NULL
   OR @Topic IS NULL OR @Topic COLLATE Latin1_General_100_BIN2 NOT IN('funding','project','application','project-design','partnerships','service','platform','other')
   OR (@Topic='service' AND @Service IS NULL) OR (@Topic<>'service' AND @Service IS NOT NULL)
   OR (@Service IS NOT NULL AND @Service COLLATE Latin1_General_100_BIN2 NOT IN('advisory','application-support','project-design','getting-started','partnerships','translation','proposal-review'))
   OR NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_Countries WHERE Id=@Country AND IsActive=1)
   THROW 56132,N'Invalid inquiry fields.',1;
 DECLARE @Hash BINARY(32),@Replay BIT=0,@Lock INT,@Now DATETIME2(7)=SYSUTCDATETIME(),@EmailHash BINARY(32)=HASHBYTES('SHA2_256',LOWER(TRIM(@Email)));
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC @Lock=sys.sp_getapplock @Resource=N'FundingPlatform:InquiryCapture',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=5000;
  IF @Lock<0 THROW 56131,N'Inquiry service busy.',1;
  SELECT @Hash=RequestHash FROM dbo.FundingPlatform_Inquiries WITH(UPDLOCK,HOLDLOCK) WHERE RequestId=@RequestId;
  IF @Hash IS NOT NULL
  BEGIN
   IF @Hash<>@RequestHash THROW 56130,N'Idempotency conflict.',1;
   SET @Replay=1;
  END
  ELSE
  BEGIN
   IF (SELECT COUNT(*) FROM dbo.FundingPlatform_Inquiries WHERE EmailHash=@EmailHash AND CreatedAtUtc>=DATEADD(HOUR,-1,@Now))>=3
     OR (SELECT COUNT(*) FROM dbo.FundingPlatform_Inquiries WHERE CreatedAtUtc>=DATEADD(DAY,-1,@Now))>=500
     THROW 56131,N'Inquiry submission limit reached.',1;
   INSERT dbo.FundingPlatform_Inquiries(RequestId,RequestHash,EmailHash,CountryId,DataJson,CreatedAtUtc,UpdatedAtUtc)
     VALUES(@RequestId,@RequestHash,@EmailHash,@Country,@DataJson,@Now,@Now);
  END;
  COMMIT TRANSACTION;
  SELECT (SELECT @RequestId AS requestId,@Replay AS wasReplay FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) AS Json;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  THROW;
 END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Inquiry_List @UserPublicId UNIQUEIDENTIFIER,@Page INT=1
AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @Access TINYINT=dbo.FundingPlatform_fn_AdminAccessState(@UserPublicId);
 IF @Access=0 THROW 51601,N'Active administrator required.',1;
 IF @Access=1 THROW 51602,N'MFA required.',1;
 IF @Page IS NULL OR @Page NOT BETWEEN 1 AND 1000 THROW 56132,N'Invalid page.',1;
 SELECT (SELECT (SELECT COUNT(*) FROM dbo.FundingPlatform_Inquiries) AS totalCount,@Page AS page,
   JSON_QUERY((SELECT i.RequestId AS requestId,JSON_QUERY(i.DataJson) AS data,c.Name AS countryName,i.Status AS status,
     i.NotificationStatus AS notificationStatus,i.Revision AS revision,TODATETIMEOFFSET(i.CreatedAtUtc,'+00:00') AS createdAtUtc
     FROM dbo.FundingPlatform_Inquiries i JOIN dbo.FundingPlatform_Countries c ON c.Id=i.CountryId
     ORDER BY i.CreatedAtUtc DESC,i.RequestId OFFSET (@Page-1)*20 ROWS FETCH NEXT 20 ROWS ONLY FOR JSON PATH)) AS items
   FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) AS Json;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Inquiry_Review
 @UserPublicId UNIQUEIDENTIFIER,@RequestId UNIQUEIDENTIFIER,@ExpectedRevision INT,@Status TINYINT
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF @Status IS NULL OR @Status NOT IN(0,1,2) OR @ExpectedRevision IS NULL OR @ExpectedRevision<1 THROW 56132,N'Invalid review.',1;
 DECLARE @Actor BIGINT,@Revision INT;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.FundingPlatform_usp_AdminActor_Lock @UserPublicId,@Actor OUTPUT;
  SELECT @Revision=Revision FROM dbo.FundingPlatform_Inquiries WITH(UPDLOCK,HOLDLOCK) WHERE RequestId=@RequestId;
  IF @Revision IS NULL THROW 56133,N'Inquiry unavailable.',1;
  IF @Revision<>@ExpectedRevision THROW 56130,N'Inquiry changed.',1;
  UPDATE dbo.FundingPlatform_Inquiries SET Status=@Status,Revision=Revision+1,ReviewedByUserId=@Actor,UpdatedAtUtc=SYSUTCDATETIME() WHERE RequestId=@RequestId;
  COMMIT TRANSACTION;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  THROW;
 END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Inquiry_ClaimNotification @RequestId UNIQUEIDENTIFIER
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 DECLARE @Claimed TABLE(RequestId UNIQUEIDENTIFIER);
 UPDATE dbo.FundingPlatform_Inquiries SET NotificationStatus=1
   OUTPUT inserted.RequestId INTO @Claimed WHERE RequestId=@RequestId AND NotificationStatus=0;
 SELECT NULLIF((SELECT i.RequestId AS requestId,JSON_QUERY(i.DataJson) AS data,c.Name AS countryName,i.Status AS status,
   i.NotificationStatus AS notificationStatus,i.Revision AS revision,TODATETIMEOFFSET(i.CreatedAtUtc,'+00:00') AS createdAtUtc
   FROM dbo.FundingPlatform_Inquiries i JOIN @Claimed claimed ON claimed.RequestId=i.RequestId
   JOIN dbo.FundingPlatform_Countries c ON c.Id=i.CountryId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),N'') AS Json;
END;
GO
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Inquiry_FinishNotification @RequestId UNIQUEIDENTIFIER,@Accepted BIT
AS
BEGIN
 SET NOCOUNT ON;
 IF @Accepted IS NULL THROW 56132,N'Invalid notification state.',1;
 UPDATE dbo.FundingPlatform_Inquiries SET NotificationStatus=CASE WHEN @Accepted=1 THEN 2 ELSE 3 END
   WHERE RequestId=@RequestId AND NotificationStatus=1;
END;
GO
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_Inquiry_Capture TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_Inquiry_List TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_Inquiry_Review TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_Inquiry_ClaimNotification TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_Inquiry_FinishNotification TO FundingPlatform_ApiRuntimeRole;
