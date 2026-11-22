-- Validate the real two-result public SQL contract, including exact/rolling deadline fields.
-- Read-only; the synthetic query avoids exposing actual catalog rows in migration output.
SET NOCOUNT ON;
EXEC dbo.FundingPlatform_usp_FundingOpportunity_Public_List
    @Query=N'__public_deadline_contract_no_fixture_20261122__', @PageSize=1
WITH RESULT SETS
(
    (TotalCount BIGINT),
    (FundingOpportunityPublicId UNIQUEIDENTIFIER, CoverKey NVARCHAR(MAX), ContentVersion INT,
     Slug NVARCHAR(MAX), Title NVARCHAR(MAX), Summary NVARCHAR(MAX), SponsorName NVARCHAR(MAX), Currency CHAR(3),
     MinAmount DECIMAL(19,4), MaxAmount DECIMAL(19,4), OpenDate DATE, CloseDate DATE,
     CloseAtUtc DATETIME2(3), DeadlineType TINYINT, DeadlinePrecision TINYINT, DeadlineTimeZoneId NVARCHAR(100),
     PublishedAtUtc DATETIME2(3), DataQualityScore DECIMAL(5,2),
     PrimaryFunderPublicId UNIQUEIDENTIFIER, PrimaryFunderName NVARCHAR(MAX), SourceName NVARCHAR(MAX), SourceUrl NVARCHAR(MAX))
);
