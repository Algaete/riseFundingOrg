SET NOCOUNT ON;
IF (SELECT COUNT(*) FROM dbo.FundingPlatform_Currencies WHERE Code IN ('GBP','CHF') AND MinorUnits=2)<>2
    THROW 57101,N'GBP and CHF catalog entries are required.',1;
SELECT N'gbp-chf-currency-catalog-ok' AS Result;
