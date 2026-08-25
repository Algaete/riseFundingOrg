using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using FundingPlatform.Core.Semantics;

namespace FundingPlatform.Application.Semantics;

public static partial class SemanticInputPolicy
{
    private static readonly HashSet<string> ProjectProperties =
    [
        "schemaVersion", "normalizationVersion", "summary", "description",
        "projectStatus", "startDate", "endDate", "budgetTotal", "confirmedFunding",
        "currency", "countryIds", "regionIds", "categoryIds", "beneficiaryTypeIds",
        "projectTypeIds"
    ];

    private static readonly HashSet<string> OpportunityProperties =
    [
        "schemaVersion", "normalizationVersion", "title", "description", "summary",
        "sponsorName", "currency", "minAmount", "maxAmount", "eligibilityDescription",
        "requirements", "objectives", "allowedActivities", "excludedActivities",
        "restrictions", "targetOrganizationsDescription", "targetPopulationsDescription",
        "minimumOperatingYears", "requiresLegalEntity", "requiresPriorExperience",
        "requiresCofunding", "cofundingPercentage", "geographicScope", "countryIds",
        "regionIds", "categoryIds", "beneficiaryTypeIds", "projectTypeIds"
    ];

    private static readonly string[] TaxonomyProperties =
    [
        "countryIds", "regionIds", "categoryIds", "beneficiaryTypeIds",
        "projectTypeIds"
    ];

    public static bool TryValidate(
        SemanticEmbeddingInput input,
        SemanticEmbeddingJobLease lease,
        SemanticProcessingPolicy policy,
        out string safeCode)
    {
        safeCode = "semantic-input-invalid";
        if (input.JobPublicId != lease.JobPublicId || input.LeaseId != lease.LeaseId ||
            input.SubjectType != lease.SubjectType || input.SubjectPublicId != lease.SubjectPublicId ||
            input.SubjectVersion != lease.SubjectVersion ||
            !string.Equals(input.PurposeCode, lease.PurposeCode, StringComparison.Ordinal) ||
            !string.Equals(input.PurposeCode, policy.PurposeCode, StringComparison.Ordinal) ||
            string.IsNullOrEmpty(input.CanonicalText) ||
            input.InputContentHash is not { Length: 32 } ||
            lease.InputContentHash is not { Length: 32 } ||
            !CryptographicOperations.FixedTimeEquals(
                input.InputContentHash, lease.InputContentHash))
        {
            return false;
        }

        var utf8 = Encoding.UTF8.GetBytes(input.CanonicalText);
        if (utf8.Length is < 2 || utf8.Length > policy.MaximumInputUtf8Bytes ||
            !CryptographicOperations.FixedTimeEquals(
                SHA256.HashData(utf8), input.InputContentHash))
        {
            safeCode = "semantic-input-hash-mismatch";
            return false;
        }

        try
        {
            using var document = JsonDocument.Parse(utf8, new JsonDocumentOptions
            {
                AllowTrailingCommas = false,
                CommentHandling = JsonCommentHandling.Disallow,
                MaxDepth = 8
            });
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                return false;
            }

            var allowed = input.SubjectType == SemanticSubjectType.Project
                ? ProjectProperties
                : OpportunityProperties;
            var properties = document.RootElement.EnumerateObject().ToArray();
            if (properties.Length != allowed.Count ||
                properties.Select(property => property.Name)
                    .Distinct(StringComparer.Ordinal).Count() != allowed.Count ||
                properties.Any(property => !allowed.Contains(property.Name)) ||
                !document.RootElement.TryGetProperty("normalizationVersion", out var normalization) ||
                normalization.ValueKind != JsonValueKind.String ||
                normalization.GetString() != policy.NormalizationVersion ||
                !document.RootElement.TryGetProperty("schemaVersion", out var schema) ||
                schema.ValueKind != JsonValueKind.String ||
                schema.GetString() != "semantic-input-v1" ||
                TaxonomyProperties.Any(name =>
                    !document.RootElement.TryGetProperty(name, out var taxonomy) ||
                    !IsCanonicalTaxonomyArray(taxonomy)))
            {
                return false;
            }

            foreach (var value in EnumerateStrings(document.RootElement))
            {
                if (value.Any(character => char.IsControl(character) &&
                        character is not '\r' and not '\n' and not '\t') ||
                    EmailPattern().IsMatch(value) || RutPattern().IsMatch(value) ||
                    value.Contains("https://", StringComparison.OrdinalIgnoreCase) ||
                    value.Contains("http://", StringComparison.OrdinalIgnoreCase) ||
                    value.Contains("www.", StringComparison.OrdinalIgnoreCase))
                {
                    safeCode = "semantic-input-privacy-rejected";
                    return false;
                }
            }

            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static bool IsCanonicalTaxonomyArray(JsonElement element)
    {
        if (element.ValueKind != JsonValueKind.Array) return false;

        long previous = 0;
        foreach (var item in element.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.Number ||
                !item.TryGetInt64(out var current) || current <= previous)
            {
                return false;
            }

            previous = current;
        }

        return true;
    }

    private static IEnumerable<string> EnumerateStrings(JsonElement element)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.String:
                yield return element.GetString() ?? string.Empty;
                break;
            case JsonValueKind.Object:
                foreach (var property in element.EnumerateObject())
                foreach (var value in EnumerateStrings(property.Value))
                    yield return value;
                break;
            case JsonValueKind.Array:
                foreach (var item in element.EnumerateArray())
                foreach (var value in EnumerateStrings(item))
                    yield return value;
                break;
        }
    }

    [GeneratedRegex(@"(?<![\p{L}\p{N}._%+-])[\p{L}\p{N}._%+-]+@[\p{L}\p{N}.-]+\.[\p{L}]{2,}(?![\p{L}\p{N}.-])", RegexOptions.CultureInvariant)]
    private static partial Regex EmailPattern();

    [GeneratedRegex(@"(?<!\d)\d{1,2}(?:\.?\d{3}){2}-[\dkK](?![\p{L}\p{N}])", RegexOptions.CultureInvariant)]
    private static partial Regex RutPattern();
}
