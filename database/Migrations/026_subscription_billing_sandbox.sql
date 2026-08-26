/* FundingPlatform FASE 11 - organization subscriptions, entitlements and sandbox billing.
   Requires 024. Billing remains disabled until prices and Mercado Pago sandbox credentials are
   explicitly configured. No card data, webhook body, access token or secret is persisted. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_AlertSubscriptions', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_OrganizationUsers', N'U') IS NULL
    THROW 54701, N'FASE 11 requires migration 024.', 1;

CREATE TABLE dbo.FundingPlatform_SubscriptionPlanPrices
(
    Id INT IDENTITY(1,1) NOT NULL,
    SubscriptionPlanId SMALLINT NOT NULL,
    BillingInterval TINYINT NOT NULL,
    Currency CHAR(3) NOT NULL,
    Amount DECIMAL(19,4) NOT NULL,
    CountryId SMALLINT NULL,
    Provider NVARCHAR(50) NULL,
    ProviderPriceId NVARCHAR(200) NULL,
    IsActive BIT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_SubscriptionPlanPrices PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SubscriptionPlanPrices_IdPlan UNIQUE (Id, SubscriptionPlanId),
    CONSTRAINT FundingPlatform_FK_SubscriptionPlanPrices_Plan FOREIGN KEY (SubscriptionPlanId)
        REFERENCES dbo.FundingPlatform_SubscriptionPlans (Id),
    CONSTRAINT FundingPlatform_FK_SubscriptionPlanPrices_Currency FOREIGN KEY (Currency)
        REFERENCES dbo.FundingPlatform_Currencies (Code),
    CONSTRAINT FundingPlatform_FK_SubscriptionPlanPrices_Country FOREIGN KEY (CountryId)
        REFERENCES dbo.FundingPlatform_Countries (Id),
    CONSTRAINT FundingPlatform_CK_SubscriptionPlanPrices_Interval CHECK (BillingInterval IN (1, 2)),
    CONSTRAINT FundingPlatform_CK_SubscriptionPlanPrices_Amount CHECK (Amount >= 0),
    CONSTRAINT FundingPlatform_CK_SubscriptionPlanPrices_Provider CHECK
        ((Amount = 0 AND Provider IS NULL AND ProviderPriceId IS NULL)
         OR (Amount > 0 AND Provider = N'mercado-pago-sandbox'
             AND LEN(LTRIM(RTRIM(ProviderPriceId))) BETWEEN 1 AND 200
             AND DATALENGTH(ProviderPriceId) = DATALENGTH(LTRIM(RTRIM(ProviderPriceId))))),
    CONSTRAINT FundingPlatform_CK_SubscriptionPlanPrices_Time CHECK (CreatedAtUtc <= UpdatedAtUtc)
);
CREATE UNIQUE INDEX FundingPlatform_UX_SubscriptionPlanPrices_ActiveCatalog
    ON dbo.FundingPlatform_SubscriptionPlanPrices
        (SubscriptionPlanId, BillingInterval, Currency, CountryId)
    WHERE IsActive = 1;
CREATE UNIQUE INDEX FundingPlatform_UX_SubscriptionPlanPrices_ProviderPrice
    ON dbo.FundingPlatform_SubscriptionPlanPrices (Provider, ProviderPriceId)
    WHERE ProviderPriceId IS NOT NULL;

CREATE TABLE dbo.FundingPlatform_Subscriptions
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL CONSTRAINT FundingPlatform_DF_Subscriptions_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    OrganizationId BIGINT NOT NULL,
    SubscriptionPlanPriceId INT NOT NULL,
    Provider NVARCHAR(50) NOT NULL,
    ProviderCustomerId NVARCHAR(200) NULL,
    ProviderSubscriptionId NVARCHAR(200) NULL,
    ProviderUpdatedAtUtc DATETIME2(3) NULL,
    Status TINYINT NOT NULL,
    CurrentPeriodStartUtc DATETIME2(3) NULL,
    CurrentPeriodEndUtc DATETIME2(3) NULL,
    CancelAtPeriodEnd BIT NOT NULL,
    CanceledAtUtc DATETIME2(3) NULL,
    GraceUntilUtc DATETIME2(3) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_Subscriptions PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_Subscriptions_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_Subscriptions_IdOrganization UNIQUE (Id, OrganizationId),
    CONSTRAINT FundingPlatform_FK_Subscriptions_Organization FOREIGN KEY (OrganizationId)
        REFERENCES dbo.FundingPlatform_Organizations (Id),
    CONSTRAINT FundingPlatform_FK_Subscriptions_Price FOREIGN KEY (SubscriptionPlanPriceId)
        REFERENCES dbo.FundingPlatform_SubscriptionPlanPrices (Id),
    CONSTRAINT FundingPlatform_CK_Subscriptions_Provider CHECK
        (Provider = N'mercado-pago-sandbox'),
    CONSTRAINT FundingPlatform_CK_Subscriptions_Status CHECK (Status BETWEEN 0 AND 5),
    CONSTRAINT FundingPlatform_CK_Subscriptions_Period CHECK
        (CurrentPeriodStartUtc IS NULL OR CurrentPeriodEndUtc IS NULL
         OR CurrentPeriodStartUtc <= CurrentPeriodEndUtc),
    CONSTRAINT FundingPlatform_CK_Subscriptions_Time CHECK
        (CreatedAtUtc <= UpdatedAtUtc
         AND (CanceledAtUtc IS NULL OR CanceledAtUtc >= CreatedAtUtc)
         AND (GraceUntilUtc IS NULL OR GraceUntilUtc >= CreatedAtUtc))
);
CREATE UNIQUE INDEX FundingPlatform_UX_Subscriptions_ProviderSubscription
    ON dbo.FundingPlatform_Subscriptions (Provider, ProviderSubscriptionId)
    WHERE ProviderSubscriptionId IS NOT NULL;
CREATE UNIQUE INDEX FundingPlatform_UX_Subscriptions_EffectiveOrganization
    ON dbo.FundingPlatform_Subscriptions (OrganizationId)
    WHERE Status IN (0, 1, 2, 3);
CREATE INDEX FundingPlatform_IX_Subscriptions_StatusPeriod
    ON dbo.FundingPlatform_Subscriptions (Status, CurrentPeriodEndUtc, Id)
    INCLUDE (OrganizationId, SubscriptionPlanPriceId, ProviderSubscriptionId);

CREATE TABLE dbo.FundingPlatform_SubscriptionCheckoutSessions
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL CONSTRAINT FundingPlatform_DF_SubscriptionCheckoutSessions_PublicId
        DEFAULT (NEWSEQUENTIALID()),
    OrganizationId BIGINT NOT NULL,
    SubscriptionPlanPriceId INT NOT NULL,
    RequestedByUserId BIGINT NOT NULL,
    IdempotencyKeyHash BINARY(32) NOT NULL,
    RequestHash BINARY(32) NOT NULL,
    Provider NVARCHAR(50) NOT NULL,
    ExternalReference UNIQUEIDENTIFIER NOT NULL,
    ProviderCheckoutId NVARCHAR(200) NULL,
    CheckoutUrl NVARCHAR(2048) NULL,
    Status TINYINT NOT NULL,
    ExpiresAtUtc DATETIME2(3) NOT NULL,
    ClosedAtUtc DATETIME2(3) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_SubscriptionCheckoutSessions PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SubscriptionCheckoutSessions_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_SubscriptionCheckoutSessions_OrganizationKey
        UNIQUE (OrganizationId, IdempotencyKeyHash),
    CONSTRAINT FundingPlatform_UQ_SubscriptionCheckoutSessions_ProviderReference
        UNIQUE (Provider, ExternalReference),
    CONSTRAINT FundingPlatform_FK_SubscriptionCheckoutSessions_Organization
        FOREIGN KEY (OrganizationId) REFERENCES dbo.FundingPlatform_Organizations (Id),
    CONSTRAINT FundingPlatform_FK_SubscriptionCheckoutSessions_Price
        FOREIGN KEY (SubscriptionPlanPriceId) REFERENCES dbo.FundingPlatform_SubscriptionPlanPrices (Id),
    CONSTRAINT FundingPlatform_FK_SubscriptionCheckoutSessions_User
        FOREIGN KEY (RequestedByUserId) REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_SubscriptionCheckoutSessions_Membership
        FOREIGN KEY (OrganizationId, RequestedByUserId)
        REFERENCES dbo.FundingPlatform_OrganizationUsers (OrganizationId, UserId),
    CONSTRAINT FundingPlatform_CK_SubscriptionCheckoutSessions_Provider CHECK
        (Provider = N'mercado-pago-sandbox'),
    CONSTRAINT FundingPlatform_CK_SubscriptionCheckoutSessions_Status CHECK (Status BETWEEN 0 AND 4),
    CONSTRAINT FundingPlatform_CK_SubscriptionCheckoutSessions_State CHECK
        ((Status IN (0, 1) AND ClosedAtUtc IS NULL)
         OR (Status IN (2, 3, 4) AND ClosedAtUtc IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_SubscriptionCheckoutSessions_ProviderState CHECK
        ((Status = 0 AND ProviderCheckoutId IS NULL AND CheckoutUrl IS NULL)
         OR (Status <> 0 AND ProviderCheckoutId IS NOT NULL AND CheckoutUrl IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_SubscriptionCheckoutSessions_Time CHECK
        (CreatedAtUtc <= UpdatedAtUtc AND CreatedAtUtc < ExpiresAtUtc
         AND (ClosedAtUtc IS NULL OR ClosedAtUtc BETWEEN CreatedAtUtc AND UpdatedAtUtc))
);
CREATE UNIQUE INDEX FundingPlatform_UX_SubscriptionCheckoutSessions_OpenOrganization
    ON dbo.FundingPlatform_SubscriptionCheckoutSessions (OrganizationId)
    WHERE ClosedAtUtc IS NULL;
CREATE UNIQUE INDEX FundingPlatform_UX_SubscriptionCheckoutSessions_ProviderCheckout
    ON dbo.FundingPlatform_SubscriptionCheckoutSessions (Provider, ProviderCheckoutId)
    WHERE ProviderCheckoutId IS NOT NULL;
CREATE INDEX FundingPlatform_IX_SubscriptionCheckoutSessions_Reconcile
    ON dbo.FundingPlatform_SubscriptionCheckoutSessions (Status, UpdatedAtUtc, Id)
    WHERE Status IN (0, 1);

CREATE TABLE dbo.FundingPlatform_SubscriptionPayments
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    SubscriptionId BIGINT NOT NULL,
    Provider NVARCHAR(50) NOT NULL,
    ProviderPaymentId NVARCHAR(200) NOT NULL,
    ProviderInvoiceId NVARCHAR(200) NULL,
    Status TINYINT NOT NULL,
    Amount DECIMAL(19,4) NOT NULL,
    Currency CHAR(3) NOT NULL,
    PaidAtUtc DATETIME2(3) NULL,
    FailureCode NVARCHAR(100) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_SubscriptionPayments PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_FK_SubscriptionPayments_Subscription FOREIGN KEY (SubscriptionId)
        REFERENCES dbo.FundingPlatform_Subscriptions (Id),
    CONSTRAINT FundingPlatform_FK_SubscriptionPayments_Currency FOREIGN KEY (Currency)
        REFERENCES dbo.FundingPlatform_Currencies (Code),
    CONSTRAINT FundingPlatform_UQ_SubscriptionPayments_ProviderPayment
        UNIQUE (Provider, ProviderPaymentId),
    CONSTRAINT FundingPlatform_CK_SubscriptionPayments_Status CHECK (Status BETWEEN 0 AND 4),
    CONSTRAINT FundingPlatform_CK_SubscriptionPayments_Amount CHECK (Amount >= 0),
    CONSTRAINT FundingPlatform_CK_SubscriptionPayments_Time CHECK (CreatedAtUtc <= UpdatedAtUtc)
);

CREATE TABLE dbo.FundingPlatform_PaymentWebhookEvents
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    Provider NVARCHAR(50) NOT NULL,
    ProviderEventId NVARCHAR(200) NOT NULL,
    ProviderRequestId NVARCHAR(200) NULL,
    EventType NVARCHAR(150) NOT NULL,
    ResourceType NVARCHAR(100) NULL,
    ProviderResourceId NVARCHAR(200) NOT NULL,
    ProviderAction NVARCHAR(100) NULL,
    ProviderOccurredAtUtc DATETIME2(3) NULL,
    PayloadHash BINARY(32) NOT NULL,
    ReceivedAtUtc DATETIME2(3) NOT NULL,
    ProcessedAtUtc DATETIME2(3) NULL,
    Status TINYINT NOT NULL,
    AttemptCount SMALLINT NOT NULL,
    LeaseId UNIQUEIDENTIFIER NULL,
    LeaseUntilUtc DATETIME2(3) NULL,
    LastErrorCode NVARCHAR(100) NULL,
    CONSTRAINT FundingPlatform_PK_PaymentWebhookEvents PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_PaymentWebhookEvents_ProviderEvent
        UNIQUE (Provider, ProviderEventId),
    CONSTRAINT FundingPlatform_CK_PaymentWebhookEvents_Provider CHECK
        (Provider = N'mercado-pago-sandbox'),
    CONSTRAINT FundingPlatform_CK_PaymentWebhookEvents_Status CHECK (Status BETWEEN 0 AND 3),
    CONSTRAINT FundingPlatform_CK_PaymentWebhookEvents_Attempts CHECK (AttemptCount BETWEEN 0 AND 5),
    CONSTRAINT FundingPlatform_CK_PaymentWebhookEvents_Lease CHECK
        ((LeaseId IS NULL AND LeaseUntilUtc IS NULL)
         OR (LeaseId IS NOT NULL AND LeaseUntilUtc IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_PaymentWebhookEvents_Error CHECK
        ((Status IN (0, 1, 2) AND LastErrorCode IS NULL)
         OR (Status = 3 AND LastErrorCode IS NOT NULL))
);
CREATE INDEX FundingPlatform_IX_PaymentWebhookEvents_Pending
    ON dbo.FundingPlatform_PaymentWebhookEvents (Status, ReceivedAtUtc, Id)
    WHERE ProcessedAtUtc IS NULL;

CREATE TABLE dbo.FundingPlatform_SubscriptionUsageCounters
(
    OrganizationId BIGINT NOT NULL,
    FeatureCode NVARCHAR(100) NOT NULL,
    PeriodStartUtc DATETIME2(3) NOT NULL,
    PeriodEndUtc DATETIME2(3) NOT NULL,
    UsageValue DECIMAL(19,4) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL,
    UpdatedAtUtc DATETIME2(3) NOT NULL,
    CONSTRAINT FundingPlatform_PK_SubscriptionUsageCounters
        PRIMARY KEY (OrganizationId, FeatureCode, PeriodStartUtc),
    CONSTRAINT FundingPlatform_FK_SubscriptionUsageCounters_Organization
        FOREIGN KEY (OrganizationId) REFERENCES dbo.FundingPlatform_Organizations (Id),
    CONSTRAINT FundingPlatform_FK_SubscriptionUsageCounters_Feature
        FOREIGN KEY (FeatureCode) REFERENCES dbo.FundingPlatform_Features (Code),
    CONSTRAINT FundingPlatform_CK_SubscriptionUsageCounters_Value CHECK (UsageValue >= 0),
    CONSTRAINT FundingPlatform_CK_SubscriptionUsageCounters_Period CHECK
        (PeriodStartUtc < PeriodEndUtc AND CreatedAtUtc <= UpdatedAtUtc)
);
GO

/* Professional is visible but deliberately non-purchasable until business prices and sandbox
   provider IDs are configured. Organization remains a sales-led, non-purchasable tier. */
IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_SubscriptionPlans WHERE Id = 2)
    INSERT dbo.FundingPlatform_SubscriptionPlans
        (Id, Code, Name, Description, IsActive, IsPublic, IsPurchasable, SortOrder)
    VALUES (2, N'PROFESSIONAL', N'Professional',
        N'Automatización y límites ampliados. Precio sandbox pendiente de aprobación.', 1, 1, 0, 20);
IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_SubscriptionPlans WHERE Id = 3)
    INSERT dbo.FundingPlatform_SubscriptionPlans
        (Id, Code, Name, Description, IsActive, IsPublic, IsPurchasable, SortOrder)
    VALUES (3, N'ORGANIZATION', N'Organization',
        N'Plan cotizado para equipos; contactar ventas.', 1, 1, 0, 30);

INSERT dbo.FundingPlatform_SubscriptionPlanFeatures
    (SubscriptionPlanId, FeatureCode, IsEnabled, LimitValue, Unit)
SELECT plans.Id, features.FeatureCode, features.IsEnabled, features.LimitValue, features.Unit
FROM (VALUES
    (N'funding.visible_limit', 1, CAST(500 AS DECIMAL(19,4)), N'items'),
    (N'search.advanced', 1, CAST(NULL AS DECIMAL(19,4)), CAST(NULL AS NVARCHAR(30))),
    (N'recommendations.enabled', 1, NULL, NULL),
    (N'alerts.max', 1, 20, N'items'),
    (N'ai.explanations_monthly', 0, 0, N'items/month'),
    (N'applications.enabled', 1, NULL, NULL),
    (N'calendar.enabled', 1, NULL, NULL),
    (N'organization.members_max', 1, 10, N'items'),
    (N'organizations.max_owned', 1, 3, N'items'),
    (N'export.enabled', 1, NULL, NULL)
) AS features (FeatureCode, IsEnabled, LimitValue, Unit)
CROSS JOIN (SELECT Id FROM dbo.FundingPlatform_SubscriptionPlans WHERE Id IN (2, 3)) AS plans
WHERE NOT EXISTS
  (SELECT 1 FROM dbo.FundingPlatform_SubscriptionPlanFeatures AS existing
   WHERE existing.SubscriptionPlanId = plans.Id AND existing.FeatureCode = features.FeatureCode);

IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_SubscriptionPlanPrices
               WHERE SubscriptionPlanId = 1 AND BillingInterval = 1 AND Currency = 'CLP')
    INSERT dbo.FundingPlatform_SubscriptionPlanPrices
        (SubscriptionPlanId, BillingInterval, Currency, Amount, CountryId,
         Provider, ProviderPriceId, IsActive, CreatedAtUtc, UpdatedAtUtc)
    VALUES (1, 1, 'CLP', 0, 152, NULL, NULL, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_OrganizationEntitlements
(
    @OrganizationId BIGINT,
    @NowUtc DATETIME2(3)
)
RETURNS TABLE
AS RETURN
(
    WITH effectivePlan AS
    (
        SELECT TOP (1) prices.SubscriptionPlanId
        FROM dbo.FundingPlatform_Subscriptions AS subscriptions
        INNER JOIN dbo.FundingPlatform_SubscriptionPlanPrices AS prices
            ON prices.Id = subscriptions.SubscriptionPlanPriceId
        WHERE subscriptions.OrganizationId = @OrganizationId
          AND (subscriptions.Status IN (1, 2)
               OR (subscriptions.Status = 3 AND subscriptions.GraceUntilUtc >= @NowUtc))
          AND (subscriptions.CurrentPeriodEndUtc IS NULL
               OR subscriptions.CurrentPeriodEndUtc >= @NowUtc)
        ORDER BY subscriptions.UpdatedAtUtc DESC, subscriptions.Id DESC
    ), selectedPlan AS
    (
        SELECT COALESCE((SELECT SubscriptionPlanId FROM effectivePlan), CAST(1 AS SMALLINT)) AS Id
    )
    SELECT features.FeatureCode, definitions.Name, features.IsEnabled,
           features.LimitValue, features.Unit
    FROM selectedPlan
    INNER JOIN dbo.FundingPlatform_SubscriptionPlanFeatures AS features
        ON features.SubscriptionPlanId = selectedPlan.Id
    INNER JOIN dbo.FundingPlatform_Features AS definitions ON definitions.Code = features.FeatureCode
);
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_AlertSubscriptions_EntitlementLimit
ON dbo.FundingPlatform_AlertSubscriptions
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    IF EXISTS
    (
        SELECT 1
        FROM (SELECT DISTINCT OrganizationId FROM inserted WHERE IsActive = 1) AS changed
        CROSS APPLY dbo.FundingPlatform_ifn_OrganizationEntitlements(
            changed.OrganizationId, SYSUTCDATETIME()) AS entitlement
        WHERE entitlement.FeatureCode = N'alerts.max'
          AND (entitlement.IsEnabled = 0 OR entitlement.LimitValue IS NULL
               OR (SELECT COUNT_BIG(*) FROM dbo.FundingPlatform_AlertSubscriptions AS activeAlerts
                   WHERE activeAlerts.OrganizationId = changed.OrganizationId
                     AND activeAlerts.IsActive = 1) > entitlement.LimitValue)
    )
        THROW 54707, N'Active alert subscription exceeds the organization entitlement.', 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SubscriptionPlan_List
AS
BEGIN
    SET NOCOUNT ON;
    SELECT plans.Id, plans.Code, plans.Name, plans.Description,
           CONVERT(BIT, CASE WHEN plans.IsPurchasable = 1 AND EXISTS
               (SELECT 1 FROM dbo.FundingPlatform_SubscriptionPlanPrices AS prices
                WHERE prices.SubscriptionPlanId = plans.Id AND prices.IsActive = 1
                  AND prices.Amount > 0 AND prices.Provider = N'mercado-pago-sandbox')
               THEN 1 ELSE 0 END) AS IsPurchasable
    FROM dbo.FundingPlatform_SubscriptionPlans AS plans
    WHERE plans.IsActive = 1 AND plans.IsPublic = 1
    ORDER BY plans.SortOrder, plans.Id;

    SELECT prices.SubscriptionPlanId, prices.Id, prices.BillingInterval,
           prices.Currency, prices.Amount,
           CONVERT(BIT, CASE WHEN prices.IsActive = 1 AND prices.Amount > 0
                                  AND plans.IsPurchasable = 1 THEN 1 ELSE 0 END) AS IsPurchasable,
           prices.Provider
    FROM dbo.FundingPlatform_SubscriptionPlanPrices AS prices
    INNER JOIN dbo.FundingPlatform_SubscriptionPlans AS plans
        ON plans.Id = prices.SubscriptionPlanId
    WHERE prices.IsActive = 1 AND plans.IsActive = 1 AND plans.IsPublic = 1
    ORDER BY prices.SubscriptionPlanId, prices.BillingInterval, prices.Currency;

    SELECT features.SubscriptionPlanId, features.FeatureCode, definitions.Name,
           features.IsEnabled, features.LimitValue, features.Unit
    FROM dbo.FundingPlatform_SubscriptionPlanFeatures AS features
    INNER JOIN dbo.FundingPlatform_SubscriptionPlans AS plans
        ON plans.Id = features.SubscriptionPlanId AND plans.IsActive = 1 AND plans.IsPublic = 1
    INNER JOIN dbo.FundingPlatform_Features AS definitions ON definitions.Code = features.FeatureCode
    ORDER BY features.SubscriptionPlanId, features.FeatureCode;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Subscription_GetCurrent
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @OrganizationId BIGINT;
    SELECT @OrganizationId = organizations.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1
      AND users.PublicId = @UserPublicId;
    IF @OrganizationId IS NULL THROW 54703, N'Subscription workspace not found.', 1;

    DECLARE @SubscriptionId BIGINT, @PlanId SMALLINT = 1;
    SELECT TOP (1) @SubscriptionId = subscriptions.Id, @PlanId = prices.SubscriptionPlanId
    FROM dbo.FundingPlatform_Subscriptions AS subscriptions
    INNER JOIN dbo.FundingPlatform_SubscriptionPlanPrices AS prices
        ON prices.Id = subscriptions.SubscriptionPlanPriceId
    WHERE subscriptions.OrganizationId = @OrganizationId
      AND (subscriptions.Status IN (1, 2)
           OR (subscriptions.Status = 3 AND subscriptions.GraceUntilUtc >= @NowUtc))
      AND (subscriptions.CurrentPeriodEndUtc IS NULL OR subscriptions.CurrentPeriodEndUtc >= @NowUtc)
    ORDER BY subscriptions.UpdatedAtUtc DESC, subscriptions.Id DESC;

    SELECT organizations.PublicId AS OrganizationPublicId, plans.Code AS PlanCode,
           plans.Name AS PlanName, subscriptions.Status,
           prices.BillingInterval, prices.Currency, prices.Amount,
           subscriptions.CurrentPeriodStartUtc, subscriptions.CurrentPeriodEndUtc,
           COALESCE(subscriptions.CancelAtPeriodEnd, 0) AS CancelAtPeriodEnd,
           subscriptions.GraceUntilUtc,
           CONVERT(BIT, CASE WHEN @SubscriptionId IS NULL THEN 1 ELSE 0 END) AS IsFreeFallback,
           subscriptions.RowVersion
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_SubscriptionPlans AS plans ON plans.Id = @PlanId
    LEFT JOIN dbo.FundingPlatform_Subscriptions AS subscriptions ON subscriptions.Id = @SubscriptionId
    LEFT JOIN dbo.FundingPlatform_SubscriptionPlanPrices AS prices
        ON prices.Id = subscriptions.SubscriptionPlanPriceId
    WHERE organizations.Id = @OrganizationId;

    SELECT entitlements.FeatureCode, entitlements.Name, entitlements.IsEnabled,
           entitlements.LimitValue, entitlements.Unit, COALESCE(usage.UsageValue, 0) AS UsageValue
    FROM dbo.FundingPlatform_ifn_OrganizationEntitlements(@OrganizationId, @NowUtc) AS entitlements
    OUTER APPLY
    (
        SELECT SUM(counters.UsageValue) AS UsageValue
        FROM dbo.FundingPlatform_SubscriptionUsageCounters AS counters
        WHERE counters.OrganizationId = @OrganizationId
          AND counters.FeatureCode = entitlements.FeatureCode
          AND @NowUtc >= counters.PeriodStartUtc AND @NowUtc < counters.PeriodEndUtc
    ) AS usage
    ORDER BY entitlements.FeatureCode;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SubscriptionUsage_List
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @OrganizationId BIGINT;
    SELECT @OrganizationId = organizations.Id
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1
      AND users.PublicId = @UserPublicId;
    IF @OrganizationId IS NULL THROW 54703, N'Subscription workspace not found.', 1;
    DECLARE @PeriodStart DATETIME2(3) = DATETIMEFROMPARTS(YEAR(@NowUtc), MONTH(@NowUtc), 1, 0, 0, 0, 0),
            @PeriodEnd DATETIME2(3) = DATEADD(MONTH, 1,
                DATETIMEFROMPARTS(YEAR(@NowUtc), MONTH(@NowUtc), 1, 0, 0, 0, 0));
    SELECT entitlements.FeatureCode, entitlements.Name AS FeatureName,
           entitlements.IsEnabled, entitlements.LimitValue,
           COALESCE(counters.UsageValue, 0) AS UsageValue, entitlements.Unit,
           @PeriodStart AS PeriodStartUtc, @PeriodEnd AS PeriodEndUtc
    FROM dbo.FundingPlatform_ifn_OrganizationEntitlements(@OrganizationId, @NowUtc) AS entitlements
    LEFT JOIN dbo.FundingPlatform_SubscriptionUsageCounters AS counters
        ON counters.OrganizationId = @OrganizationId
       AND counters.FeatureCode = entitlements.FeatureCode
       AND counters.PeriodStartUtc = @PeriodStart
    ORDER BY entitlements.FeatureCode;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SubscriptionCheckout_Begin
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @PlanPriceId INT,
    @IdempotencyKeyHash BINARY(32),
    @RequestHash BINARY(32),
    @NowUtc DATETIME2(3),
    @ExpiresAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @PlanPriceId <= 0 OR @IdempotencyKeyHash IS NULL OR @RequestHash IS NULL
       OR @ExpiresAtUtc <= @NowUtc OR @ExpiresAtUtc > DATEADD(HOUR, 1, @NowUtc)
        THROW 54702, N'Checkout request is invalid.', 1;
    BEGIN TRANSACTION;
    DECLARE @OrganizationId BIGINT, @UserId BIGINT, @Role TINYINT, @Email NVARCHAR(320);
    SELECT @OrganizationId = organizations.Id, @UserId = users.Id,
           @Role = memberships.Role, @Email = users.Email
    FROM dbo.FundingPlatform_Organizations AS organizations WITH (UPDLOCK, HOLDLOCK)
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.PublicId = @UserPublicId AND users.Status = 2
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.UserId = users.Id
       AND memberships.MembershipStatus = 1
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1;
    IF @OrganizationId IS NULL BEGIN ROLLBACK; THROW 54703, N'Subscription workspace not found.', 1; END;
    IF @Role <> 1 BEGIN ROLLBACK; THROW 54704, N'Organization administrator required.', 1; END;

    DECLARE @ExistingId BIGINT, @ExistingHash BINARY(32), @ExistingStatus TINYINT;
    SELECT @ExistingId = Id, @ExistingHash = RequestHash, @ExistingStatus = Status
    FROM dbo.FundingPlatform_SubscriptionCheckoutSessions WITH (UPDLOCK, HOLDLOCK)
    WHERE OrganizationId = @OrganizationId AND IdempotencyKeyHash = @IdempotencyKeyHash;
    IF @ExistingId IS NOT NULL
    BEGIN
        IF @ExistingHash <> @RequestHash
        BEGIN ROLLBACK; SELECT N'idempotency-conflict' AS Code, CAST(NULL AS UNIQUEIDENTIFIER) AS CheckoutPublicId,
            CAST(NULL AS NVARCHAR(320)) AS PayerEmail, CAST(NULL AS NVARCHAR(200)) AS ProviderPriceId; RETURN; END;
        DECLARE @ReplayPublicId UNIQUEIDENTIFIER =
            (SELECT PublicId FROM dbo.FundingPlatform_SubscriptionCheckoutSessions WHERE Id = @ExistingId);
        COMMIT; SELECT N'replayed' AS Code, @ReplayPublicId AS CheckoutPublicId,
            CAST(NULL AS NVARCHAR(320)) AS PayerEmail, CAST(NULL AS NVARCHAR(200)) AS ProviderPriceId; RETURN;
    END;

    UPDATE dbo.FundingPlatform_SubscriptionCheckoutSessions
    SET Status = 4, ClosedAtUtc = @NowUtc, UpdatedAtUtc = @NowUtc,
        ProviderCheckoutId = COALESCE(ProviderCheckoutId, N'expired-' + CONVERT(NVARCHAR(36), PublicId)),
        CheckoutUrl = COALESCE(CheckoutUrl, N'https://sandbox.example.invalid/expired')
    WHERE OrganizationId = @OrganizationId AND ClosedAtUtc IS NULL AND ExpiresAtUtc <= @NowUtc;
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_SubscriptionCheckoutSessions WITH (UPDLOCK, HOLDLOCK)
               WHERE OrganizationId = @OrganizationId AND ClosedAtUtc IS NULL)
    BEGIN ROLLBACK; SELECT N'checkout-already-open' AS Code, CAST(NULL AS UNIQUEIDENTIFIER) AS CheckoutPublicId,
        CAST(NULL AS NVARCHAR(320)) AS PayerEmail, CAST(NULL AS NVARCHAR(200)) AS ProviderPriceId; RETURN; END;
    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_Subscriptions WITH (UPDLOCK, HOLDLOCK)
               WHERE OrganizationId = @OrganizationId AND Status IN (0, 1, 2, 3))
    BEGIN ROLLBACK; SELECT N'invalid-transition' AS Code, CAST(NULL AS UNIQUEIDENTIFIER) AS CheckoutPublicId,
        CAST(NULL AS NVARCHAR(320)) AS PayerEmail, CAST(NULL AS NVARCHAR(200)) AS ProviderPriceId; RETURN; END;

    DECLARE @Provider NVARCHAR(50), @ProviderPriceId NVARCHAR(200), @PlanName NVARCHAR(120);
    SELECT @Provider = prices.Provider, @ProviderPriceId = prices.ProviderPriceId,
           @PlanName = plans.Name
    FROM dbo.FundingPlatform_SubscriptionPlanPrices AS prices WITH (UPDLOCK, HOLDLOCK)
    INNER JOIN dbo.FundingPlatform_SubscriptionPlans AS plans
        ON plans.Id = prices.SubscriptionPlanId
    WHERE prices.Id = @PlanPriceId AND prices.IsActive = 1 AND prices.Amount > 0
      AND prices.Provider = N'mercado-pago-sandbox'
      AND plans.IsActive = 1 AND plans.IsPurchasable = 1;
    IF @Provider IS NULL
    BEGIN ROLLBACK; SELECT N'not-found' AS Code, CAST(NULL AS UNIQUEIDENTIFIER) AS CheckoutPublicId,
        CAST(NULL AS NVARCHAR(320)) AS PayerEmail, CAST(NULL AS NVARCHAR(200)) AS ProviderPriceId; RETURN; END;

    DECLARE @CheckoutPublicId UNIQUEIDENTIFIER = NEWID(), @ExternalReference UNIQUEIDENTIFIER = NEWID();
    INSERT dbo.FundingPlatform_SubscriptionCheckoutSessions
        (PublicId, OrganizationId, SubscriptionPlanPriceId, RequestedByUserId,
         IdempotencyKeyHash, RequestHash, Provider, ExternalReference, ProviderCheckoutId,
         CheckoutUrl, Status, ExpiresAtUtc, ClosedAtUtc, CreatedAtUtc, UpdatedAtUtc)
    VALUES (@CheckoutPublicId, @OrganizationId, @PlanPriceId, @UserId,
            @IdempotencyKeyHash, @RequestHash, @Provider, @ExternalReference, NULL,
            NULL, 0, @ExpiresAtUtc, NULL, @NowUtc, @NowUtc);
    COMMIT;
    SELECT N'created' AS Code, @CheckoutPublicId AS CheckoutPublicId,
           @Email AS PayerEmail, @ProviderPriceId AS ProviderPriceId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SubscriptionCheckout_Get
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @CheckoutPublicId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SELECT checkout.PublicId, organizations.PublicId AS OrganizationPublicId,
           checkout.SubscriptionPlanPriceId AS PlanPriceId, plans.Name AS PlanName,
           prices.BillingInterval, prices.Currency, prices.Amount, checkout.Status,
           checkout.Provider, checkout.ExternalReference, checkout.CheckoutUrl,
           checkout.ExpiresAtUtc, checkout.CreatedAtUtc, checkout.UpdatedAtUtc
    FROM dbo.FundingPlatform_SubscriptionCheckoutSessions AS checkout
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = checkout.OrganizationId AND organizations.IsActive = 1
    INNER JOIN dbo.FundingPlatform_SubscriptionPlanPrices AS prices
        ON prices.Id = checkout.SubscriptionPlanPriceId
    INNER JOIN dbo.FundingPlatform_SubscriptionPlans AS plans
        ON plans.Id = prices.SubscriptionPlanId
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Users AS users
        ON users.Id = memberships.UserId AND users.Status = 2
    WHERE users.PublicId = @UserPublicId AND organizations.PublicId = @OrganizationPublicId
      AND checkout.PublicId = @CheckoutPublicId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_SubscriptionCheckout_RecordProvider
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @CheckoutPublicId UNIQUEIDENTIFIER,
    @ProviderCheckoutId NVARCHAR(200),
    @CheckoutUrl NVARCHAR(2048),
    @ProviderUpdatedAtUtc DATETIME2(3),
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF LEN(LTRIM(RTRIM(@ProviderCheckoutId))) NOT BETWEEN 1 AND 200
       OR @CheckoutUrl NOT LIKE N'https://%' OR LEN(@CheckoutUrl) > 2048
        THROW 54702, N'Provider checkout result is invalid.', 1;
    BEGIN TRANSACTION;
    DECLARE @CheckoutId BIGINT, @OrganizationId BIGINT, @PriceId INT, @Role TINYINT,
            @Status TINYINT, @StoredProviderId NVARCHAR(200);
    SELECT @CheckoutId = checkout.Id, @OrganizationId = organizations.Id,
           @PriceId = checkout.SubscriptionPlanPriceId, @Status = checkout.Status,
           @StoredProviderId = checkout.ProviderCheckoutId, @Role = memberships.Role
    FROM dbo.FundingPlatform_SubscriptionCheckoutSessions AS checkout WITH (UPDLOCK, HOLDLOCK)
    INNER JOIN dbo.FundingPlatform_Organizations AS organizations
        ON organizations.Id = checkout.OrganizationId AND organizations.PublicId = @OrganizationPublicId
    INNER JOIN dbo.FundingPlatform_Users AS users ON users.PublicId = @UserPublicId AND users.Status = 2
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.UserId = users.Id
       AND memberships.MembershipStatus = 1
    WHERE checkout.PublicId = @CheckoutPublicId;
    IF @CheckoutId IS NULL BEGIN ROLLBACK; SELECT N'not-found' AS Code; RETURN; END;
    IF @Role <> 1 BEGIN ROLLBACK; SELECT N'forbidden' AS Code; RETURN; END;
    IF @Status = 1 AND @StoredProviderId = @ProviderCheckoutId
    BEGIN COMMIT; SELECT N'replayed' AS Code; RETURN; END;
    IF @Status <> 0 BEGIN ROLLBACK; SELECT N'invalid-transition' AS Code; RETURN; END;
    UPDATE dbo.FundingPlatform_SubscriptionCheckoutSessions
    SET ProviderCheckoutId = @ProviderCheckoutId, CheckoutUrl = @CheckoutUrl,
        Status = 1, UpdatedAtUtc = @NowUtc WHERE Id = @CheckoutId;
    INSERT dbo.FundingPlatform_Subscriptions
        (OrganizationId, SubscriptionPlanPriceId, Provider, ProviderCustomerId,
         ProviderSubscriptionId, ProviderUpdatedAtUtc, Status, CurrentPeriodStartUtc,
         CurrentPeriodEndUtc, CancelAtPeriodEnd, CanceledAtUtc, GraceUntilUtc,
         CreatedAtUtc, UpdatedAtUtc)
    VALUES (@OrganizationId, @PriceId, N'mercado-pago-sandbox', NULL,
            @ProviderCheckoutId, @ProviderUpdatedAtUtc, 0, NULL, NULL, 0, NULL, NULL,
            @NowUtc, @NowUtc);
    COMMIT; SELECT N'updated' AS Code;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Subscription_LifecycleBegin
    @UserPublicId UNIQUEIDENTIFIER,
    @OrganizationPublicId UNIQUEIDENTIFIER,
    @Resume BIT,
    @ExpectedRowVersion BINARY(8),
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @SubscriptionId BIGINT, @ProviderSubscriptionId NVARCHAR(200),
            @Status TINYINT, @CancelAtPeriodEnd BIT, @CurrentRowVersion BINARY(8), @Role TINYINT;
    SELECT TOP (1) @SubscriptionId = subscriptions.Id,
           @ProviderSubscriptionId = subscriptions.ProviderSubscriptionId,
           @Status = subscriptions.Status, @CancelAtPeriodEnd = subscriptions.CancelAtPeriodEnd,
           @CurrentRowVersion = subscriptions.RowVersion, @Role = memberships.Role
    FROM dbo.FundingPlatform_Organizations AS organizations
    INNER JOIN dbo.FundingPlatform_Users AS users ON users.PublicId = @UserPublicId AND users.Status = 2
    INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
        ON memberships.OrganizationId = organizations.Id AND memberships.UserId = users.Id
       AND memberships.MembershipStatus = 1
    INNER JOIN dbo.FundingPlatform_Subscriptions AS subscriptions WITH (UPDLOCK, HOLDLOCK)
        ON subscriptions.OrganizationId = organizations.Id
    WHERE organizations.PublicId = @OrganizationPublicId AND organizations.IsActive = 1
    ORDER BY subscriptions.UpdatedAtUtc DESC, subscriptions.Id DESC;
    IF @SubscriptionId IS NULL SELECT N'not-found' AS Code, CAST(NULL AS NVARCHAR(200)) AS ProviderSubscriptionId;
    ELSE IF @Role <> 1 SELECT N'forbidden' AS Code, CAST(NULL AS NVARCHAR(200)) AS ProviderSubscriptionId;
    ELSE IF @ExpectedRowVersion IS NULL OR @ExpectedRowVersion <> @CurrentRowVersion
        SELECT N'etag-conflict' AS Code, CAST(NULL AS NVARCHAR(200)) AS ProviderSubscriptionId;
    ELSE IF (@Resume = 0 AND (@Status NOT IN (1, 2, 3) OR @CancelAtPeriodEnd = 1))
         OR (@Resume = 1 AND (@Status NOT IN (1, 2, 3) OR @CancelAtPeriodEnd = 0))
        SELECT N'invalid-transition' AS Code, CAST(NULL AS NVARCHAR(200)) AS ProviderSubscriptionId;
    ELSE SELECT N'accepted' AS Code, @ProviderSubscriptionId AS ProviderSubscriptionId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Subscription_ApplyProviderSnapshot
    @UserPublicId UNIQUEIDENTIFIER = NULL,
    @OrganizationPublicId UNIQUEIDENTIFIER = NULL,
    @ProviderSubscriptionId NVARCHAR(200),
    @ProviderCustomerId NVARCHAR(200) = NULL,
    @StatusCode NVARCHAR(50),
    @CurrentPeriodStartUtc DATETIME2(3) = NULL,
    @CurrentPeriodEndUtc DATETIME2(3) = NULL,
    @CancelAtPeriodEnd BIT,
    @ProviderUpdatedAtUtc DATETIME2(3),
    @ProviderPaymentId NVARCHAR(200) = NULL,
    @ProviderInvoiceId NVARCHAR(200) = NULL,
    @PaymentStatusCode NVARCHAR(50) = NULL,
    @PaymentAmount DECIMAL(19,4) = NULL,
    @PaymentCurrency CHAR(3) = NULL,
    @PaidAtUtc DATETIME2(3) = NULL,
    @FailureCode NVARCHAR(100) = NULL,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @MappedStatus TINYINT = CASE @StatusCode COLLATE Latin1_General_100_BIN2
        WHEN N'pending' THEN 0 WHEN N'authorized' THEN 2 WHEN N'active' THEN 2
        WHEN N'paused' THEN 3 WHEN N'past_due' THEN 3
        WHEN N'cancelled' THEN 4 WHEN N'canceled' THEN 4 ELSE 5 END;
    BEGIN TRANSACTION;
    DECLARE @SubscriptionId BIGINT, @OrganizationId BIGINT, @StoredUpdated DATETIME2(3),
            @CheckoutId BIGINT;
    SELECT @SubscriptionId = subscriptions.Id, @OrganizationId = subscriptions.OrganizationId,
           @StoredUpdated = subscriptions.ProviderUpdatedAtUtc
    FROM dbo.FundingPlatform_Subscriptions AS subscriptions WITH (UPDLOCK, HOLDLOCK)
    WHERE subscriptions.Provider = N'mercado-pago-sandbox'
      AND subscriptions.ProviderSubscriptionId = @ProviderSubscriptionId;
    IF @SubscriptionId IS NULL BEGIN ROLLBACK; SELECT N'not-found' AS Code; RETURN; END;
    IF @UserPublicId IS NOT NULL OR @OrganizationPublicId IS NOT NULL
    BEGIN
        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.FundingPlatform_Organizations AS organizations
            INNER JOIN dbo.FundingPlatform_Users AS users ON users.PublicId = @UserPublicId AND users.Status = 2
            INNER JOIN dbo.FundingPlatform_OrganizationUsers AS memberships
                ON memberships.OrganizationId = organizations.Id AND memberships.UserId = users.Id
               AND memberships.MembershipStatus = 1 AND memberships.Role = 1
            WHERE organizations.Id = @OrganizationId AND organizations.PublicId = @OrganizationPublicId
        )
        BEGIN ROLLBACK; SELECT N'forbidden' AS Code; RETURN; END;
    END;
    IF @StoredUpdated IS NOT NULL AND @ProviderUpdatedAtUtc < @StoredUpdated
    BEGIN COMMIT; SELECT N'replayed' AS Code; RETURN; END;
    UPDATE dbo.FundingPlatform_Subscriptions
    SET ProviderCustomerId = COALESCE(@ProviderCustomerId, ProviderCustomerId),
        ProviderUpdatedAtUtc = @ProviderUpdatedAtUtc, Status = @MappedStatus,
        CurrentPeriodStartUtc = COALESCE(@CurrentPeriodStartUtc, CurrentPeriodStartUtc),
        CurrentPeriodEndUtc = COALESCE(@CurrentPeriodEndUtc, CurrentPeriodEndUtc),
        CancelAtPeriodEnd = @CancelAtPeriodEnd,
        CanceledAtUtc = CASE WHEN @MappedStatus = 4 THEN COALESCE(CanceledAtUtc, @NowUtc) ELSE NULL END,
        GraceUntilUtc = CASE WHEN @MappedStatus = 3
                             THEN COALESCE(@CurrentPeriodEndUtc, DATEADD(DAY, 3, @NowUtc)) ELSE NULL END,
        UpdatedAtUtc = @NowUtc
    WHERE Id = @SubscriptionId;
    SELECT @CheckoutId = Id FROM dbo.FundingPlatform_SubscriptionCheckoutSessions WITH (UPDLOCK, HOLDLOCK)
    WHERE Provider = N'mercado-pago-sandbox' AND ProviderCheckoutId = @ProviderSubscriptionId;
    IF @CheckoutId IS NOT NULL AND @MappedStatus IN (1, 2, 4, 5)
        UPDATE dbo.FundingPlatform_SubscriptionCheckoutSessions
        SET Status = CASE WHEN @MappedStatus IN (1, 2) THEN 2 ELSE 3 END,
            ClosedAtUtc = COALESCE(ClosedAtUtc, @NowUtc), UpdatedAtUtc = @NowUtc
        WHERE Id = @CheckoutId AND Status IN (0, 1);
    IF @ProviderPaymentId IS NOT NULL AND @PaymentAmount IS NOT NULL
       AND @PaymentCurrency IS NOT NULL AND @PaymentStatusCode IS NOT NULL
    BEGIN
        DECLARE @PaymentStatus TINYINT = CASE @PaymentStatusCode COLLATE Latin1_General_100_BIN2
            WHEN N'pending' THEN 0 WHEN N'approved' THEN 1 WHEN N'rejected' THEN 2
            WHEN N'refunded' THEN 3 ELSE 4 END;
        MERGE dbo.FundingPlatform_SubscriptionPayments AS target
        USING (SELECT @ProviderPaymentId AS ProviderPaymentId) AS source
        ON target.Provider = N'mercado-pago-sandbox'
           AND target.ProviderPaymentId = source.ProviderPaymentId
        WHEN MATCHED AND target.UpdatedAtUtc <= @ProviderUpdatedAtUtc THEN
            UPDATE SET Status = @PaymentStatus, ProviderInvoiceId = @ProviderInvoiceId,
                       Amount = @PaymentAmount, Currency = @PaymentCurrency,
                       PaidAtUtc = @PaidAtUtc, FailureCode = @FailureCode,
                       UpdatedAtUtc = @NowUtc
        WHEN NOT MATCHED THEN INSERT
            (SubscriptionId, Provider, ProviderPaymentId, ProviderInvoiceId, Status,
             Amount, Currency, PaidAtUtc, FailureCode, CreatedAtUtc, UpdatedAtUtc)
            VALUES (@SubscriptionId, N'mercado-pago-sandbox', @ProviderPaymentId,
                    @ProviderInvoiceId, @PaymentStatus, @PaymentAmount, @PaymentCurrency,
                    @PaidAtUtc, @FailureCode, @NowUtc, @NowUtc);
    END;
    COMMIT; SELECT N'updated' AS Code;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_PaymentWebhookEvent_Receive
    @ProviderEventId NVARCHAR(200),
    @ProviderRequestId NVARCHAR(200),
    @EventType NVARCHAR(150),
    @ResourceType NVARCHAR(100) = NULL,
    @ProviderResourceId NVARCHAR(200),
    @ProviderAction NVARCHAR(100) = NULL,
    @ProviderOccurredAtUtc DATETIME2(3) = NULL,
    @PayloadHash BINARY(32),
    @ReceivedAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF LEN(LTRIM(RTRIM(@ProviderEventId))) NOT BETWEEN 1 AND 200
       OR LEN(LTRIM(RTRIM(@ProviderResourceId))) NOT BETWEEN 1 AND 200
       OR @PayloadHash IS NULL
        THROW 54702, N'Webhook event is invalid.', 1;
    BEGIN TRANSACTION;
    DECLARE @StoredHash BINARY(32);
    SELECT @StoredHash = PayloadHash FROM dbo.FundingPlatform_PaymentWebhookEvents WITH (UPDLOCK, HOLDLOCK)
    WHERE Provider = N'mercado-pago-sandbox' AND ProviderEventId = @ProviderEventId;
    IF @StoredHash IS NOT NULL
    BEGIN
        IF @StoredHash <> @PayloadHash BEGIN ROLLBACK; THROW 54706, N'Webhook replay payload changed.', 1; END;
        COMMIT; SELECT CAST(0 AS BIT) AS Created; RETURN;
    END;
    INSERT dbo.FundingPlatform_PaymentWebhookEvents
        (Provider, ProviderEventId, ProviderRequestId, EventType, ResourceType,
         ProviderResourceId, ProviderAction, ProviderOccurredAtUtc, PayloadHash,
         ReceivedAtUtc, ProcessedAtUtc, Status, AttemptCount, LeaseId, LeaseUntilUtc, LastErrorCode)
    VALUES (N'mercado-pago-sandbox', @ProviderEventId, @ProviderRequestId, @EventType,
            @ResourceType, @ProviderResourceId, @ProviderAction, @ProviderOccurredAtUtc,
            @PayloadHash, @ReceivedAtUtc, NULL, 0, 0, NULL, NULL, NULL);
    COMMIT; SELECT CAST(1 AS BIT) AS Created;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_PaymentWebhookEvent_Claim
    @BatchSize INT,
    @LeaseSeconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @BatchSize NOT BETWEEN 1 AND 25 OR @LeaseSeconds NOT BETWEEN 30 AND 300
        THROW 54702, N'Webhook claim bounds are invalid.', 1;
    DECLARE @Claimed TABLE (Id BIGINT PRIMARY KEY, LeaseId UNIQUEIDENTIFIER);
    BEGIN TRANSACTION;
    UPDATE dbo.FundingPlatform_PaymentWebhookEvents
    SET Status = 0, LeaseId = NULL, LeaseUntilUtc = NULL
    WHERE Status = 1 AND LeaseUntilUtc < @NowUtc AND AttemptCount < 5;
    UPDATE events SET Status = 3, ProcessedAtUtc = @NowUtc, LeaseId = NULL,
        LeaseUntilUtc = NULL, LastErrorCode = N'maximum-attempts'
    FROM dbo.FundingPlatform_PaymentWebhookEvents AS events
    WHERE events.Status IN (0, 1) AND events.AttemptCount >= 5 AND events.ProcessedAtUtc IS NULL;
    ;WITH candidates AS
    (
        SELECT TOP (@BatchSize) Id
        FROM dbo.FundingPlatform_PaymentWebhookEvents WITH (UPDLOCK, READPAST, ROWLOCK)
        WHERE Status = 0 AND ProcessedAtUtc IS NULL
        ORDER BY ReceivedAtUtc, Id
    )
    UPDATE events SET Status = 1, AttemptCount = AttemptCount + 1,
        LeaseId = NEWID(), LeaseUntilUtc = DATEADD(SECOND, @LeaseSeconds, @NowUtc)
    OUTPUT inserted.Id, inserted.LeaseId INTO @Claimed
    FROM dbo.FundingPlatform_PaymentWebhookEvents AS events
    INNER JOIN candidates ON candidates.Id = events.Id;
    COMMIT;
    SELECT events.Id, events.ProviderEventId, events.EventType,
           events.ProviderResourceId, events.LeaseId, events.LeaseUntilUtc
    FROM dbo.FundingPlatform_PaymentWebhookEvents AS events
    INNER JOIN @Claimed AS claimed ON claimed.Id = events.Id AND claimed.LeaseId = events.LeaseId
    ORDER BY events.Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_PaymentWebhookEvent_Complete
    @Id BIGINT,
    @LeaseId UNIQUEIDENTIFIER,
    @Succeeded BIT,
    @Retryable BIT,
    @ErrorCode NVARCHAR(100) = NULL,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.FundingPlatform_PaymentWebhookEvents
    SET Status = CASE WHEN @Succeeded = 1 THEN 2
                      WHEN @Retryable = 1 AND AttemptCount < 5 THEN 0 ELSE 3 END,
        ProcessedAtUtc = CASE WHEN @Succeeded = 1 OR @Retryable = 0 OR AttemptCount >= 5
                              THEN @NowUtc ELSE NULL END,
        LeaseId = NULL, LeaseUntilUtc = NULL,
        LastErrorCode = CASE WHEN @Succeeded = 1 OR (@Retryable = 1 AND AttemptCount < 5)
                             THEN NULL ELSE @ErrorCode END
    WHERE Id = @Id AND Status = 1 AND LeaseId = @LeaseId AND LeaseUntilUtc >= @NowUtc;
    SELECT CONVERT(BIT, CASE WHEN @@ROWCOUNT = 1 THEN 1 ELSE 0 END) AS Updated;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Subscription_ReconciliationList
    @BatchSize INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    IF @BatchSize NOT BETWEEN 1 AND 50
        THROW 54702, N'Reconciliation batch size is invalid.', 1;
    SELECT TOP (@BatchSize) subscriptions.ProviderSubscriptionId
    FROM dbo.FundingPlatform_Subscriptions AS subscriptions
    WHERE subscriptions.Provider = N'mercado-pago-sandbox'
      AND subscriptions.ProviderSubscriptionId IS NOT NULL
      AND (subscriptions.Status IN (0, 3)
           OR (subscriptions.Status IN (1, 2)
               AND subscriptions.UpdatedAtUtc <= DATEADD(DAY, -1, @NowUtc)))
    ORDER BY CASE subscriptions.Status WHEN 0 THEN 0 WHEN 3 THEN 1 ELSE 2 END,
             subscriptions.UpdatedAtUtc, subscriptions.Id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AdminSubscription_List
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @Query NVARCHAR(200) = NULL,
    @Status TINYINT = NULL,
    @PageNumber INT,
    @PageSize INT
AS
BEGIN
    SET NOCOUNT ON;
    IF @PageNumber NOT BETWEEN 1 AND 10000 OR @PageSize NOT BETWEEN 1 AND 50
       OR (@Status IS NOT NULL AND @Status NOT BETWEEN 0 AND 5)
        THROW 54702, N'Admin subscription filters are invalid.', 1;
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_Users AS users
        INNER JOIN dbo.FundingPlatform_UserRoles AS userRoles ON userRoles.UserId = users.Id
        WHERE users.PublicId = @AdminUserPublicId AND users.Status = 2 AND userRoles.RoleId IN (1, 2))
        THROW 54705, N'Platform administrator required.', 1;
    DECLARE @Offset INT = (@PageNumber - 1) * @PageSize;
    ;WITH rows AS
    (
        SELECT organizations.Id, organizations.PublicId AS OrganizationPublicId,
               organizations.Name AS OrganizationName,
               COALESCE(plans.Code, N'FREE') AS PlanCode,
               COALESCE(plans.Name, N'Free') AS PlanName,
               subscriptions.Status, subscriptions.CurrentPeriodEndUtc,
               COALESCE(subscriptions.CancelAtPeriodEnd, 0) AS CancelAtPeriodEnd,
               subscriptions.Provider, subscriptions.ProviderSubscriptionId,
               COALESCE(subscriptions.UpdatedAtUtc, organizations.UpdatedAtUtc) AS UpdatedAtUtc
        FROM dbo.FundingPlatform_Organizations AS organizations
        LEFT JOIN dbo.FundingPlatform_Subscriptions AS subscriptions
            ON subscriptions.Id = (SELECT TOP (1) candidate.Id
                FROM dbo.FundingPlatform_Subscriptions AS candidate
                WHERE candidate.OrganizationId = organizations.Id
                ORDER BY candidate.UpdatedAtUtc DESC, candidate.Id DESC)
        LEFT JOIN dbo.FundingPlatform_SubscriptionPlanPrices AS prices
            ON prices.Id = subscriptions.SubscriptionPlanPriceId
        LEFT JOIN dbo.FundingPlatform_SubscriptionPlans AS plans
            ON plans.Id = prices.SubscriptionPlanId
        WHERE (@Query IS NULL OR organizations.Name LIKE N'%' + @Query + N'%')
          AND (@Status IS NULL OR subscriptions.Status = @Status)
    )
    SELECT COUNT_BIG(*) AS TotalCount FROM rows;
    ;WITH rows AS
    (
        SELECT organizations.Id, organizations.PublicId AS OrganizationPublicId,
               organizations.Name AS OrganizationName,
               COALESCE(plans.Code, N'FREE') AS PlanCode,
               COALESCE(plans.Name, N'Free') AS PlanName,
               subscriptions.Status, subscriptions.CurrentPeriodEndUtc,
               COALESCE(subscriptions.CancelAtPeriodEnd, 0) AS CancelAtPeriodEnd,
               subscriptions.Provider, subscriptions.ProviderSubscriptionId,
               COALESCE(subscriptions.UpdatedAtUtc, organizations.UpdatedAtUtc) AS UpdatedAtUtc
        FROM dbo.FundingPlatform_Organizations AS organizations
        LEFT JOIN dbo.FundingPlatform_Subscriptions AS subscriptions
            ON subscriptions.Id = (SELECT TOP (1) candidate.Id
                FROM dbo.FundingPlatform_Subscriptions AS candidate
                WHERE candidate.OrganizationId = organizations.Id
                ORDER BY candidate.UpdatedAtUtc DESC, candidate.Id DESC)
        LEFT JOIN dbo.FundingPlatform_SubscriptionPlanPrices AS prices
            ON prices.Id = subscriptions.SubscriptionPlanPriceId
        LEFT JOIN dbo.FundingPlatform_SubscriptionPlans AS plans
            ON plans.Id = prices.SubscriptionPlanId
        WHERE (@Query IS NULL OR organizations.Name LIKE N'%' + @Query + N'%')
          AND (@Status IS NULL OR subscriptions.Status = @Status)
    )
    SELECT OrganizationPublicId, OrganizationName, PlanCode, PlanName, Status,
           CurrentPeriodEndUtc, CancelAtPeriodEnd, Provider,
           ProviderSubscriptionId, UpdatedAtUtc
    FROM rows ORDER BY UpdatedAtUtc DESC, Id DESC OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_AdminBillingDashboard_Get
    @AdminUserPublicId UNIQUEIDENTIFIER,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_Users AS users
        INNER JOIN dbo.FundingPlatform_UserRoles AS userRoles ON userRoles.UserId = users.Id
        WHERE users.PublicId = @AdminUserPublicId AND users.Status = 2 AND userRoles.RoleId IN (1, 2))
        THROW 54705, N'Platform administrator required.', 1;
    SELECT (SELECT COUNT_BIG(*) FROM dbo.FundingPlatform_Organizations WHERE IsActive = 1) AS ActiveOrganizations,
           (SELECT COUNT_BIG(*) FROM dbo.FundingPlatform_Subscriptions WHERE Status IN (1, 2)) AS ActivePaidSubscriptions,
           (SELECT COUNT_BIG(*) FROM dbo.FundingPlatform_Subscriptions WHERE Status = 3) AS PastDueSubscriptions,
           (SELECT COUNT_BIG(*) FROM dbo.FundingPlatform_SubscriptionCheckoutSessions WHERE Status IN (0, 1)) AS PendingCheckouts,
           (SELECT COUNT_BIG(*) FROM dbo.FundingPlatform_PaymentWebhookEvents WHERE Status = 3) AS FailedWebhookEvents,
           COALESCE((SELECT SUM(CASE prices.BillingInterval WHEN 1 THEN prices.Amount ELSE prices.Amount / 12 END)
                     FROM dbo.FundingPlatform_Subscriptions AS subscriptions
                     INNER JOIN dbo.FundingPlatform_SubscriptionPlanPrices AS prices
                         ON prices.Id = subscriptions.SubscriptionPlanPriceId
                     WHERE subscriptions.Status IN (1, 2) AND prices.Currency = 'CLP'), 0) AS MonthlyRecurringRevenueClp,
           @NowUtc AS GeneratedAtUtc;
END;
GO

CREATE OR ALTER TRIGGER dbo.FundingPlatform_tr_PaymentWebhookEvents_ImmutableEnvelope
ON dbo.FundingPlatform_PaymentWebhookEvents
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT OFF;
    IF EXISTS (SELECT 1 FROM deleted) AND NOT EXISTS (SELECT 1 FROM inserted)
        THROW 54708, N'Payment webhook history is immutable.', 1;
    IF EXISTS
       (SELECT 1 FROM inserted AS currentRows INNER JOIN deleted AS previousRows ON previousRows.Id = currentRows.Id
        WHERE currentRows.Provider <> previousRows.Provider
           OR currentRows.ProviderEventId <> previousRows.ProviderEventId
           OR ISNULL(currentRows.ProviderRequestId, N'') <> ISNULL(previousRows.ProviderRequestId, N'')
           OR currentRows.EventType <> previousRows.EventType
           OR ISNULL(currentRows.ResourceType, N'') <> ISNULL(previousRows.ResourceType, N'')
           OR currentRows.ProviderResourceId <> previousRows.ProviderResourceId
           OR ISNULL(currentRows.ProviderAction, N'') <> ISNULL(previousRows.ProviderAction, N'')
           OR ISNULL(currentRows.ProviderOccurredAtUtc, '19000101') <> ISNULL(previousRows.ProviderOccurredAtUtc, '19000101')
           OR currentRows.PayloadHash <> previousRows.PayloadHash
           OR currentRows.ReceivedAtUtc <> previousRows.ReceivedAtUtc)
        THROW 54708, N'Payment webhook envelope is immutable.', 1;
END;
GO
