using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using FundingPlatform.Core.Matching;
using FundingPlatform.Core.Validation;

namespace FundingPlatform.Application.Matching;

public interface IDiscoveryMatchingRepository
{
    Task<DiscoveryMatchingContext?> ReadAsync(Guid userId, DiscoveryMatchingRequest request, CancellationToken token);
}
public sealed class DiscoveryMatchingDataException(int number, Exception inner) : Exception("Discovery matching data error.", inner)
{
    public int Number { get; } = number;
}
public sealed class DiscoveryMatchingService(IDiscoveryMatchingRepository repository)
{
    public const string EngineVersion = "ecosystem-rules-v1";
    public static FieldValidationErrors Validate(DiscoveryMatchingRequest request)
    {
        var errors = new FieldValidationErrors();
        void Invalid(string field) => errors.Set(field, "api-validation-131", "El valor no es válido.");
        if (request.SourceId == Guid.Empty || !Enum.IsDefined(request.SourceKind) || !Enum.IsDefined(request.TargetKind)) Invalid("source");
        if ((request.SourceKind is DiscoverySubjectKind.Funder or DiscoverySubjectKind.Opportunity) != (request.TargetKind == DiscoveryTargetKind.Projects)) Invalid("targetKind");
        if (request.Page is < 1 or > 10000 || request.PageSize is < 1 or > 50) Invalid("pagination");
        if (request.Criteria is { } criteria)
        {
            if (criteria.CountryId is <= 0 || criteria.CategoryId is <= 0 || criteria.ProjectStage > 5) Invalid("criteria");
            if (criteria.MinimumAmount is < 0 or > 999999999999m || criteria.MaximumAmount is < 0 or > 999999999999m ||
                criteria.MaximumAmount < criteria.MinimumAmount) Invalid("amount");
            if ((criteria.MinimumAmount.HasValue || criteria.MaximumAmount.HasValue) &&
                (criteria.Currency is null || !Regex.IsMatch(criteria.Currency, "^[A-Z]{3}$"))) Invalid("currency");
            if (request.SourceKind != DiscoverySubjectKind.Funder && criteria != new DiscoveryCriteria()) Invalid("criteria");
        }
        return errors;
    }
    public async Task<DiscoveryMatchingPage?> SearchAsync(Guid userId, DiscoveryMatchingRequest request, CancellationToken token)
    {
        if (Validate(request).Count > 0) throw new ArgumentException("Invalid discovery request.");
        var context = await repository.ReadAsync(userId, request, token);
        if (context is null) return null;
        var source = context.Source;
        if (request.SourceKind == DiscoverySubjectKind.Funder)
        {
            var criteria = request.Criteria ?? new();
            // A funder's home country is not its eligibility footprint. Only explicit search criteria apply.
            source = new(criteria.CountryId is { } country ? [country] : [], criteria.CategoryId is { } category ? [category] : [], [],
                criteria.MinimumAmount, criteria.MaximumAmount, criteria.Currency, ProjectStage: criteria.ProjectStage);
        }
        var matches = context.Candidates.Select(candidate => Evaluate(source, candidate, request.TargetKind))
            .OrderByDescending(match => match.Score ?? -1).ThenByDescending(match => match.EvidenceCoverage)
            .ThenBy(match => match.Id).ToArray();
        return new(context.SourceName, EngineVersion, context.EvaluatedAtUtc,
            matches.Skip((request.Page - 1) * request.PageSize).Take(request.PageSize).ToArray(), matches.LongLength,
            context.TotalCandidateCount, context.TotalCandidateCount > context.Candidates.Count, request.Page, request.PageSize);
    }
    public static DiscoveryMatch Evaluate(DiscoveryFeatures source, DiscoveryCandidate candidate, DiscoveryTargetKind target)
    {
        var data = candidate.Features;
        var rules = new List<DiscoveryRule>
        {
            SetRule("geography", 30, source.Countries, data.Countries, source.Global),
            // Migration 031 reserves 16 for OTHER; free text is not shared taxonomy evidence.
            SetRule("sector", 30, source.Categories.Where(id => id != 16).ToArray(), data.Categories.Where(id => id != 16).ToArray())
        };
        if (target == DiscoveryTargetKind.Projects)
        {
            rules.Add((source.ExcludedOrganizationTypes ?? []).Intersect(data.OrganizationTypes).Any()
                ? new("organization-type", "gap", 15, [])
                : SetRule("organization-type", 15, source.OrganizationTypes, data.OrganizationTypes));
            var amount = "unknown";
            if (source.Currency is not null && data.Currency is not null)
            {
                if (!string.Equals(source.Currency, data.Currency, StringComparison.OrdinalIgnoreCase)) amount = "currency-mismatch";
                else if ((source.MinimumAmount.HasValue || source.MaximumAmount.HasValue) && data.MinimumAmount.HasValue && data.MaximumAmount.HasValue)
                    amount = (source.MaximumAmount is null || data.MinimumAmount <= source.MaximumAmount) &&
                        (source.MinimumAmount is null || data.MaximumAmount >= source.MinimumAmount) ? "match" : "gap";
            }
            rules.Add(new("amount", amount, 20, amount is "match" or "gap"
                ? [source.Currency!, data.MinimumAmount!.Value.ToString(CultureInfo.InvariantCulture), data.MaximumAmount!.Value.ToString(CultureInfo.InvariantCulture)] : []));
            rules.Add(new("stage", source.ProjectStage is null || data.ProjectStage is null ? "unknown" :
                source.ProjectStage == data.ProjectStage ? "match" : "gap", 5, []));
            rules.Add(new("official-eligibility", "verify", 0, []));
        }
        else if (target == DiscoveryTargetKind.Professionals)
        {
            var needs = Tokens(source.Needs);
            var skills = (data.Skills ?? []).SelectMany(Tokens).ToHashSet(StringComparer.Ordinal);
            var overlap = needs.Intersect(skills).Order().ToArray();
            rules.Add(new("skills", needs.Count == 0 || skills.Count == 0 ? "unknown" : overlap.Length > 0 ? "match" : "gap", 40, overlap));
            rules.Add(new("availability", "verify", 0, []));
        }
        else rules.Add(new("partnership-consent", "verify", 0, []));
        var totalWeight = rules.Sum(rule => rule.Weight);
        var knownWeight = rules.Where(rule => rule.Outcome is "match" or "gap").Sum(rule => rule.Weight);
        var points = rules.Where(rule => rule.Outcome == "match").Sum(rule => rule.Weight);
        // Score is evidence-supported points, not probability or an eligibility decision.
        decimal? score = knownWeight == 0 ? null : decimal.Round(100m * points / totalWeight, 1);
        var coverage = decimal.Round(100m * knownWeight / totalWeight, 1);
        return new(candidate.Id, candidate.Name, candidate.Summary, candidate.Href, score, coverage,
            knownWeight == 0 ? "insufficient-data" : rules.Any(rule => rule.Outcome == "gap") ? "gaps" : coverage < 100 ? "partial-evidence" : "aligned", rules);
    }
    private static DiscoveryRule SetRule(string code, int weight, int[] expected, int[] actual, bool global = false)
    {
        var overlap = expected.Intersect(actual).Order().Select(id => id.ToString(CultureInfo.InvariantCulture)).ToArray();
        return new(code, global ? "match" : expected.Length == 0 || actual.Length == 0 ? "unknown" : overlap.Length > 0 ? "match" : "gap",
            weight, overlap);
    }
    private static HashSet<string> Tokens(string? value) => Regex.Matches(new string((value ?? "").Normalize(NormalizationForm.FormD)
            .Where(character => CharUnicodeInfo.GetUnicodeCategory(character) != UnicodeCategory.NonSpacingMark).ToArray()).ToLowerInvariant(), @"[\p{L}\p{N}]+")
        .Select(match => match.Value).Where(word => word.Length >= 3 && word is not ("para" or "con" or "los" or "las" or "and" or "the"))
        .Take(100).ToHashSet(StringComparer.Ordinal);
}
