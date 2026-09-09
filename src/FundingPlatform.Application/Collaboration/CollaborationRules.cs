using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FundingPlatform.Core.Collaboration;
using FundingPlatform.Core.Validation;

namespace FundingPlatform.Application.Collaboration;

public static class CollaborationRules
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    public static string? Trim(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    public static byte[] Hash(object value) => SHA256.HashData(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(value, JsonOptions)));
    public static bool ValidKey(string? value) => value is { Length: >= 16 and <= 128 } && value.All(c => c is >= '!' and <= '~');
    public static bool ValidPage(int page, int size) => page is >= 1 and <= 10000 && size is >= 1 and <= 50;

    public static ProfessionalProfileData Normalize(ProfessionalProfileData value) => value with
    {
        DisplayName = (value.DisplayName ?? "").Trim(), Headline = (value.Headline ?? "").Trim(), Biography = Trim(value.Biography),
        Skills = (value.Skills ?? []).Take(21).Select(s => (s ?? "").Trim()).ToArray(),
        LanguageIds = (value.LanguageIds ?? []).Take(21).ToArray(), CategoryIds = (value.CategoryIds ?? []).Take(31).ToArray()
    };

    public static FieldValidationErrors Validate(ProfessionalProfileData value)
    {
        var errors = new FieldValidationErrors();
        Text(value.DisplayName, "displayName", 120, true, errors);
        Text(value.Headline, "headline", 160, true, errors);
        Text(value.Biography, "biography", 2000, false, errors);
        if (value.CountryId is <= 0) Invalid(errors, "countryId");
        if (value.AllowsInvitations && !value.IsDiscoverable) Invalid(errors, "allowsInvitations");
        if (value.Skills?.Count > 20 || value.Skills?.Any(s => string.IsNullOrWhiteSpace(s) || s.Length is < 2 or > 80) == true) Invalid(errors, "skills");
        if (value.LanguageIds?.Count > 20 || value.LanguageIds?.Any(id => id <= 0) == true) Invalid(errors, "languageIds");
        if (value.CategoryIds?.Count > 30 || value.CategoryIds?.Any(id => id <= 0) == true) Invalid(errors, "categoryIds");
        return errors;
    }

    public static FieldValidationErrors ValidateConsortium(string? name, string? summary)
    {
        var errors = new FieldValidationErrors();
        Text(name, "name", 160, true, errors); Text(summary, "summary", 1000, false, errors);
        return errors;
    }

    public static FieldValidationErrors ValidateInvitation(ConsortiumInvitationData value)
    {
        var errors = new FieldValidationErrors();
        if (!Enum.IsDefined(value.Kind) || value.TargetId == Guid.Empty) Invalid(errors, "targetId");
        Text(value.Contribution, "contribution", 160, true, errors);
        Text(value.Message, "message", 500, true, errors);
        if (value.Message is null || value.Message.Length < 10 || value.Message.Contains('@') ||
            value.Message.Contains("http:", StringComparison.OrdinalIgnoreCase) || value.Message.Contains("https:", StringComparison.OrdinalIgnoreCase) ||
            value.Message.Contains("www.", StringComparison.OrdinalIgnoreCase) ||
            System.Text.RegularExpressions.Regex.IsMatch(value.Message, @"\d{8}")) Invalid(errors, "message");
        return errors;
    }

    public static void Invalid(FieldValidationErrors errors, string field) => errors.Set(field, "api-validation-131", "El valor no es válido.");
    private static void Text(string? value, string field, int max, bool required, FieldValidationErrors errors)
    {
        if (required && (value?.Trim().Length ?? 0) < 2) Invalid(errors, field);
        if (value?.Length > max) errors.Set(field, "text-max-length", $"Admite hasta {max} caracteres.", max: max);
    }
}
