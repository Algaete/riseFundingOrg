/* Transactional FASE 11 smoke: entitlements, sandbox checkout and webhook inbox. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_Subscriptions', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_SubscriptionCheckoutSessions', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_PaymentWebhookEvents', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ifn_OrganizationEntitlements', N'IF') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_SubscriptionCheckout_Begin', N'P') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_usp_PaymentWebhookEvent_Claim', N'P') IS NULL
    THROW 54750, N'FASE 11 objects are incomplete.', 1;

IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_SubscriptionPlanPrices
           WHERE Amount > 0 AND IsActive = 1)
   OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_SubscriptionPlans
             WHERE Code IN (N'PROFESSIONAL', N'ORGANIZATION') AND IsPurchasable = 1)
    THROW 54751, N'Paid billing must ship non-purchasable.', 1;
IF OBJECT_DEFINITION(OBJECT_ID(N'dbo.FundingPlatform_usp_PaymentWebhookEvent_Receive'))
       LIKE N'%PayloadJson%'
    THROW 54752, N'Raw provider payload must not be persisted.', 1;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke026;
BEGIN TRY
    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @Suffix NVARCHAR(32) = REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N'');
    DECLARE @UserPublicId UNIQUEIDENTIFIER = NEWID(), @OrganizationPublicId UNIQUEIDENTIFIER = NEWID();
    DECLARE @Email NVARCHAR(320) = N'fase11-' + @Suffix + N'@example.invalid';
    INSERT dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES (@UserPublicId, @Email, UPPER(@Email), N'FASE 11', N'not-a-credential',
            N'fase11', 1, 0, 2, N'es-CL');
    DECLARE @UserId BIGINT = (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId=@UserPublicId);
    INSERT dbo.FundingPlatform_Organizations
        (PublicId, CreatedByUserId, Name, HomeCountryId, OrganizationTypeId)
    VALUES (@OrganizationPublicId, @UserId, N'FASE 11 ' + @Suffix, 152, 1);
    DECLARE @OrganizationId BIGINT = (SELECT Id FROM dbo.FundingPlatform_Organizations WHERE PublicId=@OrganizationPublicId);
    INSERT dbo.FundingPlatform_OrganizationUsers
        (OrganizationId, UserId, Role, MembershipStatus, JoinedAtUtc)
    VALUES (@OrganizationId, @UserId, 1, 1, @NowUtc);

    IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_ifn_OrganizationEntitlements(@OrganizationId,@NowUtc)
                   WHERE FeatureCode=N'alerts.max' AND IsEnabled=1 AND LimitValue=3)
        THROW 54753, N'Free fallback entitlement is incorrect.', 1;

    UPDATE dbo.FundingPlatform_SubscriptionPlans SET IsPurchasable=1 WHERE Code=N'PROFESSIONAL';
    DECLARE @ProfessionalPlanId SMALLINT=(SELECT Id FROM dbo.FundingPlatform_SubscriptionPlans WHERE Code=N'PROFESSIONAL');
    INSERT dbo.FundingPlatform_SubscriptionPlanPrices
        (SubscriptionPlanId,BillingInterval,Currency,Amount,CountryId,Provider,ProviderPriceId,IsActive,CreatedAtUtc,UpdatedAtUtc)
    VALUES (@ProfessionalPlanId,1,'CLP',1000,152,N'mercado-pago-sandbox',N'fase11-' + @Suffix,1,@NowUtc,@NowUtc);
    DECLARE @PriceId INT=SCOPE_IDENTITY();
    DECLARE @Checkout TABLE(Code NVARCHAR(40),CheckoutPublicId UNIQUEIDENTIFIER,PayerEmail NVARCHAR(320),ProviderPriceId NVARCHAR(200));
    INSERT @Checkout EXEC dbo.FundingPlatform_usp_SubscriptionCheckout_Begin
        @UserPublicId,@OrganizationPublicId,@PriceId,
        HASHBYTES('SHA2_256',N'idem-' + @Suffix),HASHBYTES('SHA2_256',N'request-' + @Suffix),
        @NowUtc,DATEADD(MINUTE,15,@NowUtc);
    DECLARE @CheckoutPublicId UNIQUEIDENTIFIER=(SELECT CheckoutPublicId FROM @Checkout WHERE Code=N'created');
    IF @CheckoutPublicId IS NULL THROW 54754, N'Sandbox checkout was not created.', 1;
    DELETE @Checkout;
    INSERT @Checkout EXEC dbo.FundingPlatform_usp_SubscriptionCheckout_Begin
        @UserPublicId,@OrganizationPublicId,@PriceId,
        HASHBYTES('SHA2_256',N'idem-' + @Suffix),HASHBYTES('SHA2_256',N'request-' + @Suffix),
        @NowUtc,DATEADD(MINUTE,15,@NowUtc);
    IF NOT EXISTS(SELECT 1 FROM @Checkout WHERE Code=N'replayed')
        THROW 54755, N'Checkout replay failed.', 1;

    DECLARE @Received TABLE(Inserted BIT);
    INSERT @Received EXEC dbo.FundingPlatform_usp_PaymentWebhookEvent_Receive
        N'event-' + @Suffix,N'request-' + @Suffix,N'subscription_preapproval',N'preapproval',
        N'resource-' + @Suffix,N'updated',@NowUtc,HASHBYTES('SHA2_256',N'payload'),@NowUtc;
    IF NOT EXISTS(SELECT 1 FROM @Received WHERE Inserted=1)
        THROW 54756, N'Webhook was not durably received.', 1;
    DELETE @Received;
    INSERT @Received EXEC dbo.FundingPlatform_usp_PaymentWebhookEvent_Receive
        N'event-' + @Suffix,N'request-' + @Suffix,N'subscription_preapproval',N'preapproval',
        N'resource-' + @Suffix,N'updated',@NowUtc,HASHBYTES('SHA2_256',N'payload'),@NowUtc;
    IF NOT EXISTS(SELECT 1 FROM @Received WHERE Inserted=0)
        THROW 54757, N'Webhook replay is not idempotent.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke026;
    PRINT N'FASE 11 subscription billing sandbox smoke passed.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
    BEGIN
        IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
        ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke026;
        ELSE ROLLBACK TRANSACTION;
    END;
    THROW;
END CATCH;
