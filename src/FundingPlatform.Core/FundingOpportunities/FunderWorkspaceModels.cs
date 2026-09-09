namespace FundingPlatform.Core.FundingOpportunities;

public sealed record WorkspaceFundingSource(int Id, string Name, byte ProviderType, string? BaseUrl, bool IsEnabled);
