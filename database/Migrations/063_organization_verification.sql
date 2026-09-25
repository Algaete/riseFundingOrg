/* Private administrative verification, independent of profile completeness.
   No access/publication/payment policy changes. Existing organizations start pending.
   A decision covers one profile version; later edits make it effectively pending. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF OBJECT_ID(N'dbo.FundingPlatform_Organizations', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_AdminActor_Lock', N'P') IS NULL
   OR DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole') IS NULL
    THROW 56300, N'Organization verification prerequisites are missing.', 1;

IF OBJECT_ID(N'dbo.FundingPlatform_OrganizationVerifications', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FundingPlatform_OrganizationVerifications
    (
        OrganizationId BIGINT NOT NULL CONSTRAINT FundingPlatform_PK_OrganizationVerifications PRIMARY KEY,
        Status TINYINT NOT NULL,
        Revision INT NOT NULL,
        ReviewedProfileVersion INT NOT NULL,
        Reason NVARCHAR(2000) NOT NULL,
        ReviewedByUserId BIGINT NOT NULL,
        ReviewedAtUtc DATETIME2(7) NOT NULL,
        CONSTRAINT FundingPlatform_FK_OrganizationVerifications_Organization FOREIGN KEY (OrganizationId)
            REFERENCES dbo.FundingPlatform_Organizations(Id),
        CONSTRAINT FundingPlatform_FK_OrganizationVerifications_Reviewer FOREIGN KEY (ReviewedByUserId)
            REFERENCES dbo.FundingPlatform_Users(Id),
        CONSTRAINT FundingPlatform_CK_OrganizationVerifications_Values CHECK
            (Status IN (0, 1, 2) AND Revision >= 1 AND ReviewedProfileVersion >= 1
             AND LEN(TRIM(Reason)) >= 5 AND DATALENGTH(Reason) <= 4000)
    );
END;
IF OBJECT_ID(N'dbo.FundingPlatform_OrganizationVerificationHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FundingPlatform_OrganizationVerificationHistory
    (
        OrganizationId BIGINT NOT NULL,
        Revision INT NOT NULL,
        Status TINYINT NOT NULL,
        ProfileVersion INT NOT NULL,
        Reason NVARCHAR(2000) NOT NULL,
        ReviewedByUserId BIGINT NOT NULL,
        ReviewedAtUtc DATETIME2(7) NOT NULL,
        CONSTRAINT FundingPlatform_PK_OrganizationVerificationHistory PRIMARY KEY (OrganizationId, Revision),
        CONSTRAINT FundingPlatform_FK_OrganizationVerificationHistory_Organization FOREIGN KEY (OrganizationId)
            REFERENCES dbo.FundingPlatform_Organizations(Id),
        CONSTRAINT FundingPlatform_FK_OrganizationVerificationHistory_Reviewer FOREIGN KEY (ReviewedByUserId)
            REFERENCES dbo.FundingPlatform_Users(Id),
        CONSTRAINT FundingPlatform_CK_OrganizationVerificationHistory_Values CHECK
            (Status IN (0, 1, 2) AND Revision >= 1 AND ProfileVersion >= 1
             AND LEN(TRIM(Reason)) >= 5 AND DATALENGTH(Reason) <= 4000)
    );
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_OrganizationVerification_Get
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Access TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @Access = 0 THROW 51601, N'Active administrator required.', 1;
    IF @Access = 1 THROW 51602, N'Administrator MFA required.', 1;
    SELECT NULLIF((
        SELECT o.PublicId AS organizationPublicId, o.Name AS name,
            CONVERT(TINYINT, CASE WHEN v.ReviewedProfileVersion = o.ProfileVersion THEN v.Status ELSE 0 END) AS status,
            COALESCE(v.Status, CONVERT(TINYINT, 0)) AS recordedStatus,
            COALESCE(v.Revision, 0) AS revision, o.ProfileVersion AS profileVersion,
            v.ReviewedProfileVersion AS reviewedProfileVersion,
            TODATETIMEOFFSET(v.ReviewedAtUtc, '+00:00') AS reviewedAtUtc,
            reviewer.PublicId AS reviewedByUserPublicId, reviewer.DisplayName AS reviewedByName,
            v.Reason AS reason,
            CONVERT(BIT, CASE WHEN v.Status IN (1, 2) AND v.ReviewedProfileVersion <> o.ProfileVersion THEN 1 ELSE 0 END) AS needsReverification,
            JSON_QUERY(COALESCE((SELECT TOP (50) h.Revision AS revision, h.Status AS status,
                h.ProfileVersion AS profileVersion, h.Reason AS reason,
                TODATETIMEOFFSET(h.ReviewedAtUtc, '+00:00') AS reviewedAtUtc,
                actor.PublicId AS reviewedByUserPublicId, actor.DisplayName AS reviewedByName
                FROM dbo.FundingPlatform_OrganizationVerificationHistory h
                INNER JOIN dbo.FundingPlatform_Users actor ON actor.Id = h.ReviewedByUserId
                WHERE h.OrganizationId = o.Id ORDER BY h.Revision DESC
                FOR JSON PATH, INCLUDE_NULL_VALUES), N'[]')) AS history
        FROM dbo.FundingPlatform_Organizations o
        LEFT JOIN dbo.FundingPlatform_OrganizationVerifications v ON v.OrganizationId = o.Id
        LEFT JOIN dbo.FundingPlatform_Users reviewer ON reviewer.Id = v.ReviewedByUserId
        WHERE o.PublicId = @OrganizationPublicId
        FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER
    ), N'') AS Json;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_OrganizationVerification_Decide
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @Status TINYINT,
    @Reason NVARCHAR(MAX),
    @ExpectedRevision INT,
    @ExpectedProfileVersion INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Reason = TRIM(@Reason);
    IF @Status IS NULL OR @Status NOT IN (0, 1, 2)
       OR @Reason IS NULL OR LEN(@Reason) < 5 OR DATALENGTH(@Reason) > 4000
       OR @ExpectedRevision IS NULL OR @ExpectedRevision < 0 OR @ExpectedRevision = 2147483647
       OR @ExpectedProfileVersion IS NULL OR @ExpectedProfileVersion < 1
        THROW 56303, N'Invalid verification decision.', 1;
    DECLARE @Actor BIGINT, @Org BIGINT, @ProfileVersion INT, @Revision INT = 0,
        @Now DATETIME2(7) = SYSUTCDATETIME();
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC dbo.FundingPlatform_usp_AdminActor_Lock @AdminUserPublicId, @Actor OUTPUT;
        /* Lock the profile as well as the review, so edits cannot race approval. */
        SELECT @Org = Id, @ProfileVersion = ProfileVersion
        FROM dbo.FundingPlatform_Organizations WITH (UPDLOCK, HOLDLOCK)
        WHERE PublicId = @OrganizationPublicId;
        IF @Org IS NULL THROW 56301, N'Organization unavailable.', 1;
        SELECT @Revision = Revision
        FROM dbo.FundingPlatform_OrganizationVerifications WITH (UPDLOCK, HOLDLOCK)
        WHERE OrganizationId = @Org;
        IF @Revision <> @ExpectedRevision OR @ProfileVersion <> @ExpectedProfileVersion
            THROW 56302, N'The organization or its verification has changed.', 1;
        IF @Revision = 0
            INSERT dbo.FundingPlatform_OrganizationVerifications
                (OrganizationId, Status, Revision, ReviewedProfileVersion, Reason, ReviewedByUserId, ReviewedAtUtc)
            VALUES (@Org, @Status, 1, @ProfileVersion, @Reason, @Actor, @Now);
        ELSE
            UPDATE dbo.FundingPlatform_OrganizationVerifications
            SET Status = @Status, Revision = Revision + 1, ReviewedProfileVersion = @ProfileVersion,
                Reason = @Reason, ReviewedByUserId = @Actor, ReviewedAtUtc = @Now
            WHERE OrganizationId = @Org;
        /* Append only. A later rejection/reset never removes the earlier decision. */
        INSERT dbo.FundingPlatform_OrganizationVerificationHistory
            (OrganizationId, Revision, Status, ProfileVersion, Reason, ReviewedByUserId, ReviewedAtUtc)
        VALUES (@Org, @Revision + 1, @Status, @ProfileVersion, @Reason, @Actor, @Now);
        EXEC dbo.FundingPlatform_usp_OrganizationVerification_Get @AdminUserPublicId, @OrganizationPublicId;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

/* Preserve the existing read-only admin list and its grants; add an independent filter. */
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AdminOrganization_List
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @Query NVARCHAR(200) = NULL,
    @ProfileStatus TINYINT = NULL,
    @IsActive BIT = NULL,
    @PageNumber INT = 1,
    @PageSize INT = 25,
    @VerificationStatus TINYINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active administrator access is required.', 1;
    IF @AccessState = 1 THROW 51602, N'Administrator MFA setup is required.', 1;
    SET @Query = NULLIF(LTRIM(RTRIM(@Query)), N'');
    IF (@Query IS NOT NULL AND LEN(@Query) > 200)
       OR @ProfileStatus NOT BETWEEN 0 AND 2 OR @VerificationStatus NOT BETWEEN 0 AND 2
       OR @PageNumber IS NULL OR @PageNumber NOT BETWEEN 1 AND 10000
       OR @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 50
        THROW 54901, N'Invalid admin organization filters.', 1;

    /* One filtered snapshot gives a consistent count and page during concurrent reviews. */
    SELECT organizations.Id, organizations.PublicId AS OrganizationPublicId,
        organizations.Name AS OrganizationName, RTRIM(countries.Iso2) AS CountryCode,
        countries.Name AS CountryName, organizationTypes.Name AS OrganizationTypeName,
        organizations.ProfileStatus, organizations.ProfileCompleteness, organizations.IsActive,
        organizations.CreatedAtUtc, organizations.UpdatedAtUtc,
        CONVERT(TINYINT, CASE WHEN v.ReviewedProfileVersion = organizations.ProfileVersion THEN v.Status ELSE 0 END) AS VerificationStatus
    INTO #Organizations
    FROM dbo.FundingPlatform_Organizations organizations
    INNER JOIN dbo.FundingPlatform_Countries countries ON countries.Id = organizations.HomeCountryId
    INNER JOIN dbo.FundingPlatform_OrganizationTypes organizationTypes ON organizationTypes.Id = organizations.OrganizationTypeId
    LEFT JOIN dbo.FundingPlatform_OrganizationVerifications v ON v.OrganizationId = organizations.Id
    WHERE (@Query IS NULL OR organizations.Name LIKE N'%' + @Query + N'%'
        OR organizations.LegalName LIKE N'%' + @Query + N'%'
        OR CONVERT(NVARCHAR(36), organizations.PublicId) = @Query)
      AND (@ProfileStatus IS NULL OR organizations.ProfileStatus = @ProfileStatus)
      AND (@IsActive IS NULL OR organizations.IsActive = @IsActive)
      AND (@VerificationStatus IS NULL OR @VerificationStatus =
        CASE WHEN v.ReviewedProfileVersion = organizations.ProfileVersion THEN v.Status ELSE 0 END);
    SELECT COUNT_BIG(*) AS TotalCount FROM #Organizations;
    SELECT o.OrganizationPublicId, o.OrganizationName, o.CountryCode, o.CountryName,
        o.OrganizationTypeName, o.ProfileStatus, o.ProfileCompleteness, o.IsActive,
        (SELECT COUNT_BIG(*) FROM dbo.FundingPlatform_OrganizationUsers members
            WHERE members.OrganizationId = o.Id AND members.MembershipStatus = 1) AS MemberCount,
        (SELECT COUNT_BIG(*) FROM dbo.FundingPlatform_Projects projects
            WHERE projects.OrganizationId = o.Id) AS ProjectCount,
        COALESCE(subscriptionInfo.PlanCode, N'FREE') AS PlanCode,
        COALESCE(subscriptionInfo.PlanName, N'Free') AS PlanName,
        subscriptionInfo.SubscriptionStatus, o.CreatedAtUtc, o.UpdatedAtUtc, o.VerificationStatus
    FROM #Organizations o
    OUTER APPLY
    (
        SELECT TOP (1) plans.Code AS PlanCode, plans.Name AS PlanName, subscriptions.Status AS SubscriptionStatus
        FROM dbo.FundingPlatform_Subscriptions subscriptions
        INNER JOIN dbo.FundingPlatform_SubscriptionPlanPrices prices ON prices.Id = subscriptions.SubscriptionPlanPriceId
        INNER JOIN dbo.FundingPlatform_SubscriptionPlans plans ON plans.Id = prices.SubscriptionPlanId
        WHERE subscriptions.OrganizationId = o.Id
        ORDER BY CASE WHEN subscriptions.Status IN (0, 1, 2, 3) THEN 0 ELSE 1 END,
            subscriptions.UpdatedAtUtc DESC, subscriptions.Id DESC
    ) subscriptionInfo
    ORDER BY o.UpdatedAtUtc DESC, o.Id DESC
    OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_OrganizationVerification_Get TO FundingPlatform_ApiRuntimeRole;
GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_OrganizationVerification_Decide TO FundingPlatform_ApiRuntimeRole;
