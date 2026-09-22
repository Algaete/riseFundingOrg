/* Read-only smoke. Do not require AUD to be active: an operator may disable it. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Currencies WHERE Code = 'AUD' AND MinorUnits = 2)
    THROW 56022, N'AUD catalog preparation is missing or inconsistent.', 1;

SELECT N'aud-currency-catalog-ok' AS Result;
