namespace FundingPlatform.Contracts.FundingOpportunities;

public sealed record FundingEligibilityPolicyDto(
    string SourceUrl,
    FundingEligibilityBudgetLimitDto? ProjectBudgetLimit = null,
    FundingEligibilityBudgetLimitDto? OrganizationAnnualBudgetLimit = null,
    IReadOnlyList<int>? RequiredCategoryIds = null,
    IReadOnlyList<int>? RequiredBeneficiaryTypeIds = null,
    IReadOnlyList<string>? ManualRequirements = null);

public sealed record FundingEligibilityBudgetLimitDto(decimal Amount, string Currency, bool Inclusive);
