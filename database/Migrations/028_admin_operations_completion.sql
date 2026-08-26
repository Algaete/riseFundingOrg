/* FundingPlatform - administrative organizations and sanitized operational errors.
   Read-only administration surface. Requires migrations 001-027. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_fn_AdminAccessState', N'FN') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_Subscriptions', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_AiExplanationJobs', N'U') IS NULL
   OR DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole') IS NULL
    THROW 54900, N'Admin operations require migrations 001-027.', 1;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AdminOrganization_List
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @Query NVARCHAR(200) = NULL,
    @ProfileStatus TINYINT = NULL,
    @IsActive BIT = NULL,
    @PageNumber INT = 1,
    @PageSize INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active administrator access is required.', 1;
    IF @AccessState = 1 THROW 51602, N'Administrator MFA setup is required.', 1;

    SET @Query = NULLIF(LTRIM(RTRIM(@Query)), N'');
    IF (@Query IS NOT NULL AND LEN(@Query) > 200)
       OR @ProfileStatus NOT BETWEEN 0 AND 2
       OR @PageNumber NOT BETWEEN 1 AND 10000
       OR @PageSize NOT BETWEEN 1 AND 50
        THROW 54901, N'Invalid admin organization filters.', 1;

    SELECT COUNT_BIG(*) AS TotalCount
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_Countries AS countries
        ON countries.Id = organizations.HomeCountryId
    INNER JOIN dbo.FundingPlatform_OrganizationTypes AS organizationTypes
        ON organizationTypes.Id = organizations.OrganizationTypeId
    WHERE (@Query IS NULL
           OR organizations.Name LIKE N'%' + @Query + N'%'
           OR organizations.LegalName LIKE N'%' + @Query + N'%'
           OR CONVERT(NVARCHAR(36), organizations.PublicId) = @Query)
      AND (@ProfileStatus IS NULL OR organizations.ProfileStatus = @ProfileStatus)
      AND (@IsActive IS NULL OR organizations.IsActive = @IsActive);

    SELECT organizations.PublicId AS OrganizationPublicId,
           organizations.Name AS OrganizationName,
           RTRIM(countries.Iso2) AS CountryCode,
           countries.Name AS CountryName,
           organizationTypes.Name AS OrganizationTypeName,
           organizations.ProfileStatus,
           organizations.ProfileCompleteness,
           organizations.IsActive,
           CONVERT(BIGINT, (SELECT COUNT_BIG(*)
              FROM dbo.FundingPlatform_OrganizationUsers AS members
              WHERE members.OrganizationId = organizations.Id
                AND members.MembershipStatus = 1)) AS MemberCount,
           CONVERT(BIGINT, (SELECT COUNT_BIG(*)
              FROM dbo.FundingPlatform_Projects AS projects
              WHERE projects.OrganizationId = organizations.Id)) AS ProjectCount,
           COALESCE(subscriptionInfo.PlanCode, N'FREE') AS PlanCode,
           COALESCE(subscriptionInfo.PlanName, N'Free') AS PlanName,
           subscriptionInfo.SubscriptionStatus,
           organizations.CreatedAtUtc,
           organizations.UpdatedAtUtc
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_Countries AS countries
        ON countries.Id = organizations.HomeCountryId
    INNER JOIN dbo.FundingPlatform_OrganizationTypes AS organizationTypes
        ON organizationTypes.Id = organizations.OrganizationTypeId
    OUTER APPLY
    (
        SELECT TOP (1) plans.Code AS PlanCode, plans.Name AS PlanName,
               subscriptions.Status AS SubscriptionStatus
        FROM dbo.FundingPlatform_Subscriptions AS subscriptions
        INNER JOIN dbo.FundingPlatform_SubscriptionPlanPrices AS prices
            ON prices.Id = subscriptions.SubscriptionPlanPriceId
        INNER JOIN dbo.FundingPlatform_SubscriptionPlans AS plans
            ON plans.Id = prices.SubscriptionPlanId
        WHERE subscriptions.OrganizationId = organizations.Id
        ORDER BY CASE WHEN subscriptions.Status IN (0, 1, 2, 3) THEN 0 ELSE 1 END,
                 subscriptions.UpdatedAtUtc DESC, subscriptions.Id DESC
    ) AS subscriptionInfo
    WHERE (@Query IS NULL
           OR organizations.Name LIKE N'%' + @Query + N'%'
           OR organizations.LegalName LIKE N'%' + @Query + N'%'
           OR CONVERT(NVARCHAR(36), organizations.PublicId) = @Query)
      AND (@ProfileStatus IS NULL OR organizations.ProfileStatus = @ProfileStatus)
      AND (@IsActive IS NULL OR organizations.IsActive = @IsActive)
    ORDER BY organizations.UpdatedAtUtc DESC, organizations.Id DESC
    OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AdminOrganization_Get
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active administrator access is required.', 1;
    IF @AccessState = 1 THROW 51602, N'Administrator MFA setup is required.', 1;
    IF @OrganizationPublicId IS NULL
        THROW 54902, N'Invalid organization identifier.', 1;

    SELECT organizations.PublicId AS OrganizationPublicId,
           organizations.Name AS OrganizationName,
           organizations.LegalName,
           RTRIM(countries.Iso2) AS CountryCode,
           countries.Name AS CountryName,
           organizationTypes.Name AS OrganizationTypeName,
           legalEntityTypes.Name AS LegalEntityTypeName,
           organizationSizes.Name AS OrganizationSizeName,
           CONVERT(INT, organizations.EstablishedYear) AS EstablishedYear,
           organizations.WebsiteUrl,
           organizations.Description,
           organizations.ProfileStatus,
           organizations.ProfileCompleteness,
           organizations.ProfileVersion,
           organizations.IsActive,
           CONVERT(BIGINT, (SELECT COUNT_BIG(*)
              FROM dbo.FundingPlatform_OrganizationUsers AS members
              WHERE members.OrganizationId = organizations.Id
                AND members.MembershipStatus = 1)) AS MemberCount,
           CONVERT(BIGINT, (SELECT COUNT_BIG(*)
              FROM dbo.FundingPlatform_OrganizationUsers AS members
              WHERE members.OrganizationId = organizations.Id
                AND members.MembershipStatus = 1 AND members.Role = 1)) AS AdminMemberCount,
           CONVERT(BIGINT, (SELECT COUNT_BIG(*)
              FROM dbo.FundingPlatform_Projects AS projects
              WHERE projects.OrganizationId = organizations.Id)) AS ProjectCount,
           CONVERT(BIGINT, (SELECT COUNT_BIG(*)
              FROM dbo.FundingPlatform_Projects AS projects
              WHERE projects.OrganizationId = organizations.Id
                AND projects.PublicationStatus = 2)) AS PublishedProjectCount,
           COALESCE(subscriptionInfo.PlanCode, N'FREE') AS PlanCode,
           COALESCE(subscriptionInfo.PlanName, N'Free') AS PlanName,
           subscriptionInfo.SubscriptionStatus,
           subscriptionInfo.CurrentPeriodEndUtc,
           organizations.CreatedAtUtc,
           organizations.UpdatedAtUtc
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_Countries AS countries
        ON countries.Id = organizations.HomeCountryId
    INNER JOIN dbo.FundingPlatform_OrganizationTypes AS organizationTypes
        ON organizationTypes.Id = organizations.OrganizationTypeId
    LEFT JOIN dbo.FundingPlatform_LegalEntityTypes AS legalEntityTypes
        ON legalEntityTypes.Id = organizations.LegalEntityTypeId
    LEFT JOIN dbo.FundingPlatform_OrganizationSizes AS organizationSizes
        ON organizationSizes.Id = organizations.OrganizationSizeId
    OUTER APPLY
    (
        SELECT TOP (1) plans.Code AS PlanCode, plans.Name AS PlanName,
               subscriptions.Status AS SubscriptionStatus,
               subscriptions.CurrentPeriodEndUtc
        FROM dbo.FundingPlatform_Subscriptions AS subscriptions
        INNER JOIN dbo.FundingPlatform_SubscriptionPlanPrices AS prices
            ON prices.Id = subscriptions.SubscriptionPlanPriceId
        INNER JOIN dbo.FundingPlatform_SubscriptionPlans AS plans
            ON plans.Id = prices.SubscriptionPlanId
        WHERE subscriptions.OrganizationId = organizations.Id
        ORDER BY CASE WHEN subscriptions.Status IN (0, 1, 2, 3) THEN 0 ELSE 1 END,
                 subscriptions.UpdatedAtUtc DESC, subscriptions.Id DESC
    ) AS subscriptionInfo
    WHERE organizations.PublicId = @OrganizationPublicId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AdminOperationalError_List
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @Query NVARCHAR(200) = NULL,
    @Category NVARCHAR(20) = NULL,
    @Retryable BIT = NULL,
    @PageNumber INT = 1,
    @PageSize INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @AccessState TINYINT = dbo.FundingPlatform_fn_AdminAccessState(@AdminUserPublicId);
    IF @AccessState = 0 THROW 51601, N'Active administrator access is required.', 1;
    IF @AccessState = 1 THROW 51602, N'Administrator MFA setup is required.', 1;

    SET @Query = NULLIF(LTRIM(RTRIM(@Query)), N'');
    SET @Category = LOWER(NULLIF(LTRIM(RTRIM(@Category)), N''));
    IF (@Query IS NOT NULL AND LEN(@Query) > 200)
       OR (@Category IS NOT NULL AND @Category NOT IN
           (N'import', N'extraction', N'semantic', N'explanation', N'payment'))
       OR @PageNumber NOT BETWEEN 1 AND 10000
       OR @PageSize NOT BETWEEN 1 AND 50
        THROW 54903, N'Invalid operational error filters.', 1;

    CREATE TABLE #Events
    (
        EventId NVARCHAR(100) NOT NULL,
        Category NVARCHAR(20) NOT NULL,
        Severity TINYINT NOT NULL,
        ErrorCode NVARCHAR(100) NOT NULL,
        SanitizedMessage NVARCHAR(1000) NOT NULL,
        IsRetryable BIT NOT NULL,
        OccurredAtUtc DATETIME2(3) NOT NULL,
        RelatedResourcePublicId UNIQUEIDENTIFIER NULL,
        SourceName NVARCHAR(250) NULL
    );

    INSERT #Events
        (EventId, Category, Severity, ErrorCode, SanitizedMessage, IsRetryable,
         OccurredAtUtc, RelatedResourcePublicId, SourceName)
    SELECT N'import:' + CONVERT(NVARCHAR(36), errors.PublicId), N'import',
           CONVERT(TINYINT, CASE WHEN errors.IsRetryable = 1 THEN 1 ELSE 2 END),
           errors.ErrorCode, errors.SanitizedMessage, errors.IsRetryable,
           errors.OccurredAtUtc, runs.PublicId, sources.Name
    FROM dbo.FundingPlatform_ImportErrors AS errors
    INNER JOIN dbo.FundingPlatform_ImportRuns AS runs ON runs.Id = errors.ImportRunId
    INNER JOIN dbo.FundingPlatform_FundingSources AS sources ON sources.Id = errors.FundingSourceId;

    INSERT #Events
        (EventId, Category, Severity, ErrorCode, SanitizedMessage, IsRetryable,
         OccurredAtUtc, RelatedResourcePublicId, SourceName)
    SELECT N'extraction:' + CONVERT(NVARCHAR(36), jobs.PublicId), N'extraction',
           CONVERT(TINYINT, CASE WHEN jobs.Status = 4 THEN 1 ELSE 2 END),
           COALESCE(jobs.LastErrorCode, N'extraction-completed-with-warnings'),
           CASE WHEN jobs.Status = 4 THEN N'La extracción terminó con advertencias.'
                ELSE N'La extracción no pudo completarse.' END,
           CONVERT(BIT, CASE WHEN jobs.Status = 5 AND jobs.AttemptCount < jobs.MaxAttempts THEN 1 ELSE 0 END),
           jobs.UpdatedAtUtc, documents.PublicId, sources.Name
    FROM dbo.FundingPlatform_SourceDocumentExtractionJobs AS jobs
    INNER JOIN dbo.FundingPlatform_SourceDocuments AS documents ON documents.Id = jobs.SourceDocumentId
    INNER JOIN dbo.FundingPlatform_FundingSources AS sources ON sources.Id = jobs.FundingSourceId
    WHERE jobs.Status IN (4, 5);

    INSERT #Events
        (EventId, Category, Severity, ErrorCode, SanitizedMessage, IsRetryable,
         OccurredAtUtc, RelatedResourcePublicId, SourceName)
    SELECT N'semantic-embedding:' + CONVERT(NVARCHAR(36), jobs.PublicId), N'semantic',
           CONVERT(TINYINT, CASE WHEN jobs.Status = 3 THEN 1 ELSE 2 END),
           jobs.ErrorCode,
           CASE WHEN jobs.Status = 3 THEN N'La generación semántica se reintentará.'
                ELSE N'La generación semántica terminó con un fallo permanente.' END,
           CONVERT(BIT, CASE WHEN jobs.Status = 3 THEN 1 ELSE 0 END),
           jobs.UpdatedAtUtc, jobs.PublicId, N'Motor semántico'
    FROM dbo.FundingPlatform_SemanticEmbeddingJobs AS jobs
    WHERE jobs.Status IN (3, 4) AND jobs.ErrorCode IS NOT NULL;

    INSERT #Events
        (EventId, Category, Severity, ErrorCode, SanitizedMessage, IsRetryable,
         OccurredAtUtc, RelatedResourcePublicId, SourceName)
    SELECT N'semantic-evaluation:' + CONVERT(NVARCHAR(36), runs.PublicId), N'semantic',
           CONVERT(TINYINT, CASE WHEN runs.Status = 3 THEN 1 ELSE 2 END),
           runs.ErrorCode,
           CASE WHEN runs.Status = 3 THEN N'La evaluación semántica se reintentará.'
                ELSE N'La evaluación semántica terminó con un fallo permanente.' END,
           CONVERT(BIT, CASE WHEN runs.Status = 3 THEN 1 ELSE 0 END),
           runs.UpdatedAtUtc, runs.PublicId, N'Evaluación semántica'
    FROM dbo.FundingPlatform_SemanticEvaluationRuns AS runs
    WHERE runs.Status IN (3, 4) AND runs.ErrorCode IS NOT NULL;

    INSERT #Events
        (EventId, Category, Severity, ErrorCode, SanitizedMessage, IsRetryable,
         OccurredAtUtc, RelatedResourcePublicId, SourceName)
    SELECT N'explanation:' + CONVERT(NVARCHAR(36), jobs.PublicId), N'explanation',
           CONVERT(TINYINT, CASE WHEN jobs.Status = 3 THEN 1 ELSE 2 END),
           jobs.ErrorCode,
           CASE WHEN jobs.Status = 3 THEN N'La explicación asistida se reintentará.'
                ELSE N'La explicación asistida terminó con un fallo permanente.' END,
           CONVERT(BIT, CASE WHEN jobs.Status = 3 THEN 1 ELSE 0 END),
           jobs.UpdatedAtUtc, jobs.PublicId, N'Explicaciones asistidas'
    FROM dbo.FundingPlatform_AiExplanationJobs AS jobs
    WHERE jobs.Status IN (3, 4) AND jobs.ErrorCode IS NOT NULL;

    INSERT #Events
        (EventId, Category, Severity, ErrorCode, SanitizedMessage, IsRetryable,
         OccurredAtUtc, RelatedResourcePublicId, SourceName)
    SELECT N'payment:' + CONVERT(NVARCHAR(64),
               HASHBYTES('SHA2_256', CONCAT(events.Provider, N':', events.ProviderEventId)), 2),
           N'payment', 2, events.LastErrorCode,
           N'El webhook de pago no pudo procesarse.', 0,
           COALESCE(events.ProcessedAtUtc, events.ReceivedAtUtc), NULL, events.Provider
    FROM dbo.FundingPlatform_PaymentWebhookEvents AS events
    WHERE events.Status = 3 AND events.LastErrorCode IS NOT NULL;

    SELECT COUNT_BIG(*) AS TotalCount
    FROM #Events AS events
    WHERE (@Category IS NULL OR events.Category = @Category)
      AND (@Retryable IS NULL OR events.IsRetryable = @Retryable)
      AND (@Query IS NULL OR events.ErrorCode LIKE N'%' + @Query + N'%'
           OR events.SanitizedMessage LIKE N'%' + @Query + N'%'
           OR events.SourceName LIKE N'%' + @Query + N'%');

    SELECT events.EventId, events.Category, events.Severity, events.ErrorCode,
           events.SanitizedMessage, events.IsRetryable, events.OccurredAtUtc,
           events.RelatedResourcePublicId, events.SourceName
    FROM #Events AS events
    WHERE (@Category IS NULL OR events.Category = @Category)
      AND (@Retryable IS NULL OR events.IsRetryable = @Retryable)
      AND (@Query IS NULL OR events.ErrorCode LIKE N'%' + @Query + N'%'
           OR events.SanitizedMessage LIKE N'%' + @Query + N'%'
           OR events.SourceName LIKE N'%' + @Query + N'%')
    ORDER BY events.OccurredAtUtc DESC, events.EventId DESC
    OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

DECLARE @AdminRuntimeProcedures TABLE
(
    RoleName SYSNAME NOT NULL,
    SchemaName SYSNAME NOT NULL,
    ProcedureName SYSNAME NOT NULL,
    PRIMARY KEY (RoleName, SchemaName, ProcedureName)
);
INSERT @AdminRuntimeProcedures (RoleName, SchemaName, ProcedureName)
VALUES
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_AdminOperationalError_List'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_AdminOrganization_Get'),
    (N'FundingPlatform_ApiRuntimeRole', N'dbo', N'FundingPlatform_usp_AdminOrganization_List');

IF EXISTS
(
    SELECT 1
    FROM @AdminRuntimeProcedures AS required
    WHERE OBJECT_ID(QUOTENAME(required.SchemaName) + N'.' +
                    QUOTENAME(required.ProcedureName), N'P') IS NULL
)
    THROW 54904, N'An admin runtime procedure is missing.', 1;

DECLARE @GrantSql NVARCHAR(MAX) =
(
    SELECT STRING_AGG(CONVERT(NVARCHAR(MAX),
        N'GRANT EXECUTE ON OBJECT::' + QUOTENAME(required.SchemaName) + N'.' +
        QUOTENAME(required.ProcedureName) + N' TO ' + QUOTENAME(required.RoleName) + N';'),
        NCHAR(10))
    FROM @AdminRuntimeProcedures AS required
);
EXEC sys.sp_executesql @GrantSql;

IF (SELECT COUNT_BIG(*) FROM sys.database_permissions
    WHERE grantee_principal_id = DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole')) <> 147
    THROW 54905, N'API runtime permissions no longer match the bounded contract.', 1;
GO
