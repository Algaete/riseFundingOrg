/* FundingPlatform - additive AUD catalog preparation, not a source activation.
   ISO 4217 reference: SIX List One, published 2026-01-01, checked 2026-09-14.
   https://www.six-group.com/dam/download/financial-information/data-center/iso-currrency/lists/list-one.xml
   Preserve existing labels, activity decisions and timestamps. No FX conversion.
   The migrator owns the transaction. See docs/FUNDSFORNGOS-INTEGRATION-PREP.md.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'dbo.FundingPlatform_Currencies', N'U') IS NULL
    THROW 56020, N'AUD catalog preparation requires migration 001.', 1;

IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_Currencies WHERE Code = 'AUD' AND MinorUnits <> 2)
    THROW 56021, N'Existing AUD minor units conflict with the reference catalog.', 1;

INSERT INTO dbo.FundingPlatform_Currencies (Code, Name, MinorUnits)
SELECT 'AUD', N'Dólar australiano', 2
WHERE NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_Currencies WHERE Code = 'AUD');
