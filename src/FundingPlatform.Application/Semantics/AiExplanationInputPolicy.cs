using System.Text.Json;

namespace FundingPlatform.Application.Semantics;

public static class AiExplanationInputPolicy
{
    private static readonly string[] RootPropertyNames =
    [
        "schemaVersion", "semanticScore", "cosineSimilarity", "semanticRank",
        "deterministicRank", "classification", "hardGateStatus",
        "compatibilityScore", "ruleScore", "evidenceCoverage", "rules"
    ];

    private static readonly string[] RulePropertyNames =
        ["ruleCode", "outcome", "dataState", "reasonCode", "warning"];

    private static readonly string[] RuleCodes =
    [
        "amount", "beneficiaries", "categories", "geography", "legal_entity",
        "operating_years", "organization_type", "prior_experience", "project_type"
    ];

    private static readonly IReadOnlySet<string> ReasonCodes = new HashSet<string>(
        [
            "geography.global",
            "geography.country_match",
            "geography.region_match",
            "geography.explicit_no_match",
            "geography.missing_project",
            "geography.missing_opportunity",
            "organization_type.allowed",
            "organization_type.excluded",
            "organization_type.not_allowed",
            "organization_type.not_restricted",
            "organization_type.missing_opportunity",
            "legal_entity.not_required",
            "legal_entity.allowed",
            "legal_entity.excluded",
            "legal_entity.not_allowed",
            "legal_entity.present",
            "legal_entity.missing_organization",
            "legal_entity.missing_opportunity",
            "operating_years.meets",
            "operating_years.not_required",
            "operating_years.minimum_not_met",
            "operating_years.boundary_unknown",
            "operating_years.missing_organization",
            "operating_years.missing_opportunity",
            "prior_experience.not_required",
            "prior_experience.has_experience",
            "prior_experience.no_experience",
            "prior_experience.missing_organization",
            "prior_experience.missing_opportunity",
            "categories.match",
            "categories.no_match",
            "categories.missing_project",
            "categories.missing_opportunity",
            "beneficiaries.match",
            "beneficiaries.no_match",
            "beneficiaries.missing_project",
            "beneficiaries.missing_opportunity",
            "project_type.match",
            "project_type.no_match",
            "project_type.missing_project",
            "project_type.missing_opportunity",
            "amount.within_range",
            "amount.above_max_partial",
            "amount.below_min",
            "amount.currency_mismatch",
            "amount.missing_project",
            "amount.missing_opportunity"
        ],
        StringComparer.Ordinal);

    public static bool IsCanonicalAndSafe(string? canonicalInputJson)
    {
        if (string.IsNullOrEmpty(canonicalInputJson)) return false;
        try
        {
            using var document = JsonDocument.Parse(canonicalInputJson, new JsonDocumentOptions
            {
                AllowTrailingCommas = false,
                CommentHandling = JsonCommentHandling.Disallow,
                MaxDepth = 5
            });
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                !HasExactOrderedProperties(root, RootPropertyNames) ||
                !IsExactString(root, "schemaVersion", "explanation-input-v1") ||
                !IsDecimal(root, "semanticScore", 0m, 100m) ||
                !IsDecimal(root, "cosineSimilarity", -1m, 1m) ||
                !IsInteger(root, "semanticRank", 1, 200) ||
                !IsInteger(root, "deterministicRank", 1, 200) ||
                !IsInteger(root, "classification", 0, 2) ||
                !IsInteger(root, "hardGateStatus", 0, 2) ||
                !IsNullableDecimal(root, "compatibilityScore", 0m, 100m) ||
                !IsDecimal(root, "ruleScore", 0m, 100m) ||
                !IsDecimal(root, "evidenceCoverage", 0m, 100m) ||
                !root.TryGetProperty("rules", out var rules) ||
                rules.ValueKind != JsonValueKind.Array ||
                rules.GetArrayLength() != RuleCodes.Length)
                return false;

            var classification = root.GetProperty("classification").GetInt32();
            var hardGateStatus = root.GetProperty("hardGateStatus").GetInt32();
            var compatibilityScore = root.GetProperty("compatibilityScore");
            if ((classification == 1) != (hardGateStatus == 1) ||
                classification == 0 && hardGateStatus != 0 ||
                classification == 2 && hardGateStatus != 2 ||
                classification == 1 && compatibilityScore.ValueKind != JsonValueKind.Null ||
                classification != 1 && compatibilityScore.ValueKind == JsonValueKind.Null)
                return false;

            var ordinal = 0;
            foreach (var rule in rules.EnumerateArray())
            {
                if (rule.ValueKind != JsonValueKind.Object ||
                    !HasExactOrderedProperties(rule, RulePropertyNames) ||
                    !IsExactString(rule, "ruleCode", RuleCodes[ordinal]) ||
                    !IsInteger(rule, "outcome", 0, 3) ||
                    !IsInteger(rule, "dataState", 0, 2) ||
                    !rule.TryGetProperty("reasonCode", out var reason) ||
                    reason.ValueKind != JsonValueKind.String ||
                    reason.GetString() is not { } reasonCode ||
                    !ReasonCodes.Contains(reasonCode) ||
                    !reasonCode.StartsWith(RuleCodes[ordinal] + ".", StringComparison.Ordinal) ||
                    !rule.TryGetProperty("warning", out var warning) ||
                    warning.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                    return false;
                ordinal++;
            }
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static bool HasExactOrderedProperties(JsonElement element, string[] expected) =>
        element.EnumerateObject().Select(property => property.Name)
            .SequenceEqual(expected, StringComparer.Ordinal);

    private static bool IsExactString(JsonElement element, string name, string expected) =>
        element.TryGetProperty(name, out var value) &&
        value.ValueKind == JsonValueKind.String &&
        string.Equals(value.GetString(), expected, StringComparison.Ordinal);

    private static bool IsInteger(JsonElement element, string name, int minimum, int maximum) =>
        element.TryGetProperty(name, out var value) &&
        value.ValueKind == JsonValueKind.Number &&
        value.TryGetInt32(out var parsed) && parsed >= minimum && parsed <= maximum;

    private static bool IsDecimal(
        JsonElement element,
        string name,
        decimal minimum,
        decimal maximum) =>
        element.TryGetProperty(name, out var value) &&
        value.ValueKind == JsonValueKind.Number &&
        value.TryGetDecimal(out var parsed) && parsed >= minimum && parsed <= maximum;

    private static bool IsNullableDecimal(
        JsonElement element,
        string name,
        decimal minimum,
        decimal maximum) =>
        element.TryGetProperty(name, out var value) &&
        (value.ValueKind == JsonValueKind.Null ||
         value.ValueKind == JsonValueKind.Number && value.TryGetDecimal(out var parsed) &&
         parsed >= minimum && parsed <= maximum);
}
