namespace FundingPlatform.Contracts.FundingOpportunities;

public sealed record FundingLocalizationResponse(string RequestedLanguage, string Status, int? Revision);
