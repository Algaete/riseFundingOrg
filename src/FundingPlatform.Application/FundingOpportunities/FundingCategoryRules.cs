using FundingPlatform.Core.Validation;

namespace FundingPlatform.Application.FundingOpportunities;

public static class FundingCategoryRules
{
    // Stable catalog identity established in migration 031, not a user-created category.
    public const int OtherCategoryId = 16;
    public const int MaximumDescriptionLength = 200;

    public static void Validate(IReadOnlyList<int> categories, string? description, FieldValidationErrors errors)
    {
        if (categories.Contains(OtherCategoryId) && string.IsNullOrWhiteSpace(description))
            errors.Set("otherCategoryDescription", "funding-other-category-required", "Especifica la categoría al seleccionar Otros.");
        if (!categories.Contains(OtherCategoryId) && !string.IsNullOrWhiteSpace(description))
            errors.Set("otherCategoryDescription", "funding-other-category-unselected", "Selecciona Otros para especificar una categoría.");
        FundingEditorialServiceSupport.ValidateLength(description, MaximumDescriptionLength, "otherCategoryDescription", errors);
    }
}
