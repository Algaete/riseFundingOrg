-- Preserve original grant amounts; never infer an exchange rate.
-- Additive ISO 4217 currencies, two fractional digits each.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_Currencies WHERE Code IN ('GBP','CHF') AND MinorUnits <> 2)
    THROW 57100,N'Existing GBP or CHF precision conflicts with the catalog.',1;
INSERT dbo.FundingPlatform_Currencies(Code,Name,MinorUnits)
SELECT s.Code,s.Name,2 FROM (VALUES ('GBP',N'Libra esterlina'),('CHF',N'Franco suizo')) s(Code,Name)
WHERE NOT EXISTS(SELECT 1 FROM dbo.FundingPlatform_Currencies c WHERE c.Code=s.Code);
