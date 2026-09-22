using FundingPlatform.Core.Validation;

namespace FundingPlatform.Application.FundingOpportunities;

/// <summary>Versioned, bundled illustrations only. Never a URL, path or uploaded file.</summary>
public static class FundingCoverRules
{
    public static bool IsSupported(string? key) => key is null or "auto" or
        "nature-v1" or "education-v1" or "community-v1" or "research-v1";

    public static void Validate(string? key, FieldValidationErrors errors)
    {
        if (!IsSupported(key))
            errors.Set("coverKey", "funding-cover-invalid", "Selecciona una portada disponible en la biblioteca.");
    }
}
