namespace FundingPlatform.Core.FundingOpportunities;

/// <summary>Editorial requirements tied to the same immutable content version as the fund.</summary>
public sealed record FundingEligibilityPolicy(
    string SourceUrl,
    FundingEligibilityBudgetLimit? ProjectBudgetLimit = null,
    FundingEligibilityBudgetLimit? OrganizationAnnualBudgetLimit = null,
    IReadOnlyList<int>? RequiredCategoryIds = null,
    IReadOnlyList<int>? RequiredBeneficiaryTypeIds = null,
    IReadOnlyList<string>? ManualRequirements = null);

/// <summary>The applicant's total budget, not the grant amount or funding gap. No implicit FX conversion.</summary>
public sealed record FundingEligibilityBudgetLimit(decimal Amount, string Currency, bool Inclusive);
