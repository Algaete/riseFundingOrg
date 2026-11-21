using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Core.Validation;

namespace FundingPlatform.Application.FundingOpportunities;

public static class FundingEligibilityPolicyRules
{
    public static FundingEligibilityPolicy? Normalize(FundingEligibilityPolicy? policy) => policy is null ? null : policy with
    {
        SourceUrl = policy.SourceUrl?.Trim() ?? "",
        ProjectBudgetLimit = NormalizeLimit(policy.ProjectBudgetLimit),
        OrganizationAnnualBudgetLimit = NormalizeLimit(policy.OrganizationAnnualBudgetLimit),
        RequiredCategoryIds = (policy.RequiredCategoryIds ?? []).Distinct().Order().ToArray(),
        RequiredBeneficiaryTypeIds = (policy.RequiredBeneficiaryTypeIds ?? []).Distinct().Order().ToArray(),
        ManualRequirements = (policy.ManualRequirements ?? []).Select(value => value?.Trim() ?? "").Distinct().ToArray()
    };

    private static FundingEligibilityBudgetLimit? NormalizeLimit(FundingEligibilityBudgetLimit? limit) =>
        limit is null ? null : limit with { Currency = limit.Currency?.Trim().ToUpperInvariant() ?? "" };

    public static void Validate(FundingEligibilityPolicy? policy, FieldValidationErrors errors)
    {
        if (policy is null) return;
        if (!Uri.TryCreate(policy.SourceUrl, UriKind.Absolute, out var source) ||
            source.Scheme != Uri.UriSchemeHttps || source.UserInfo.Length != 0 ||
            policy.SourceUrl.Length > 2048)
            errors.Set("eligibilityPolicy.sourceUrl", "funding-eligibility-source-invalid", "Indica un enlace HTTPS a las bases revisadas.");
        ValidateLimit(policy.ProjectBudgetLimit, "projectBudgetLimit", errors);
        ValidateLimit(policy.OrganizationAnnualBudgetLimit, "organizationAnnualBudgetLimit", errors);
        if (policy.RequiredCategoryIds is { Count: > 15 } ||
            policy.RequiredCategoryIds?.Any(id => id is <= 0 or > 15) == true)
            errors.Set("eligibilityPolicy.requiredCategoryIds", "funding-eligibility-categories-invalid", "Selecciona áreas específicas; «Otro» no confirma un requisito obligatorio.");
        if (policy.RequiredBeneficiaryTypeIds is { Count: > 11 } ||
            policy.RequiredBeneficiaryTypeIds?.Any(id => id is <= 0 or > 11) == true)
            errors.Set("eligibilityPolicy.requiredBeneficiaryTypeIds", "funding-eligibility-beneficiaries-invalid", "Selecciona beneficiarios específicos; «Otro» no confirma un requisito obligatorio.");
        if (policy.ManualRequirements is { Count: > 12 } ||
            policy.ManualRequirements?.Any(value => string.IsNullOrWhiteSpace(value) || value.Length > 500) == true)
            errors.Set("eligibilityPolicy.manualRequirements", "funding-eligibility-manual-invalid", "Admite hasta 12 requisitos pendientes de revisión, de 1 a 500 caracteres cada uno.");
    }

    private static void ValidateLimit(FundingEligibilityBudgetLimit? limit, string field, FieldValidationErrors errors)
    {
        if (limit is null) return;
        if (limit.Amount <= 0 || limit.Amount >= 1_000_000_000_000_000m || decimal.Round(limit.Amount, 4) != limit.Amount ||
            limit.Currency is null || limit.Currency.Length != 3 || limit.Currency.Any(c => c is < 'A' or > 'Z'))
            errors.Set($"eligibilityPolicy.{field}", "funding-eligibility-budget-invalid", "El límite requiere un monto positivo con hasta cuatro decimales y una moneda ISO de tres letras.");
    }
}
