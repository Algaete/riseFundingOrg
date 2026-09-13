using FundingPlatform.Core.Matching;
using FundingPlatform.Core.Validation;
using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Application.Matching;

public interface IGapRecommendationRepository
{
    Task<GapRecommendationContext?> ReadAsync(Guid userId, GapRecommendationRequest request, CancellationToken token);
}

/// <summary>Read-only, evidence-bound suggestions; never changes a match or a relationship.</summary>
public sealed class GapRecommendationService(IGapRecommendationRepository repository, IDiscoveryMatchingRepository discovery)
{
    public const string EngineVersion = "gap-actions-v2";
    public const int CandidateLimit = 200;
    public const int SuggestionsPerNeed = 3;

    public static FieldValidationErrors Validate(GapRecommendationRequest request)
    {
        var errors = new FieldValidationErrors();
        if (request.ProjectId == Guid.Empty) errors.Set("projectId", "api-validation-131", "El valor no es válido.");
        if (request.OpportunityId == Guid.Empty) errors.Set("opportunityId", "api-validation-131", "El valor no es válido.");
        return errors;
    }

    public async Task<GapRecommendationResult?> ReadAsync(Guid actor, GapRecommendationRequest request, CancellationToken token)
    {
        if (actor == Guid.Empty || Validate(request).Count > 0) throw new ArgumentException("Invalid recommendation request.");
        var context = await repository.ReadAsync(actor, request, token);
        if (context is null) return null;
        // Defense in depth: obsolete editorial flags and their evidence must never drive recommendations.
        var current = context.ReviewedContentVersion == context.ContentVersion;
        var international = current && context.RequiresInternationalPartner == true;
        var consortium = current && context.RequiresConsortium == true;
        var geographyState = GeographyState(context);
        var geographicPartners = current && context.PartnerGeography is { Scope: PartnerGeographyScope.Specific };
        var partners = !string.IsNullOrWhiteSpace(context.SoughtPartners);
        var professionals = !string.IsNullOrWhiteSpace(context.SoughtProfessionals);
        DiscoveryMatchingContext? organizations = null, people = null;
        if (international || consortium || partners || context.SeekingConsortium == true || geographicPartners)
        {
            organizations = await discovery.ReadAsync(actor, new(DiscoverySubjectKind.Project, request.ProjectId, DiscoveryTargetKind.Organizations), token);
            if (organizations is null) return null; // Recheck access; do not turn revoked access into an empty directory.
        }
        if (professionals)
        {
            people = await discovery.ReadAsync(actor, new(DiscoverySubjectKind.Project, request.ProjectId, DiscoveryTargetKind.Professionals), token);
            if (people is null) return null;
        }
        var items = new List<GapRecommendation>();
        if (international) items.Add(Recommend("international-partner", ["funding"], null, organizations!, context, true));
        if (consortium || context.SeekingConsortium == true)
            items.Add(Recommend("consortium", new[] { consortium ? "funding" : null, context.SeekingConsortium == true ? "project" : null }
                .OfType<string>().ToArray(), null, organizations!, context));
        if (partners) items.Add(Recommend("partners", ["project"], context.SoughtPartners, organizations!, context));
        if (geographicPartners && !international && !consortium && !partners && context.SeekingConsortium != true)
            items.Add(Recommend("partner-geography", ["funding"], null, organizations!, context));
        if (professionals) items.Add(Recommend("professionals", ["project"], context.SoughtProfessionals, people!, context));
        return new(EngineVersion, context.ProjectTitle, context.OpportunityTitle, context.ContentVersion,
            current, current ? context.EvidenceUrl : null, context.EvaluatedAtUtc, items,
            current ? context.PartnerGeography : null, geographyState);
    }

    private static string GeographyState(GapRecommendationContext context)
    {
        if (context.ReviewedContentVersion != context.ContentVersion || context.PartnerGeography is null) return "unverified";
        var geography = context.PartnerGeography;
        if (!context.PartnerGeographyValid || !PartnerGeographyCatalog.Valid(geography) ||
            geography.Scope == PartnerGeographyScope.Specific && context.EligiblePartnerCountryIds is null) return "needs-review";
        return geography.Scope switch { PartnerGeographyScope.Specific => "specific", PartnerGeographyScope.Any => "any", _ => "unverified" };
    }

    private static GapRecommendation Recommend(string code, string[] origins, string? need,
        DiscoveryMatchingContext directory, GapRecommendationContext context, bool international = false)
    {
        var isProfessional = code == "professionals";
        var corpus = directory.Candidates.Take(CandidateLimit).ToArray();
        var truncated = directory.TotalCandidateCount > corpus.Length;
        var geographyState = GeographyState(context);
        if (!isProfessional && geographyState == "needs-review")
            return new(code, origins, need, "geography-needs-review", [], corpus.Length, directory.TotalCandidateCount, truncated);
        var eligible = context.EligiblePartnerCountryIds?.ToHashSet();
        if (international && context.HomeCountryId is not > 0)
            return new(code, origins, need, "missing-home-country", [], corpus.Length, directory.TotalCandidateCount, truncated);
        var candidates = corpus.Select(candidate =>
        {
            var shared = directory.Source.Categories.Intersect(candidate.Features.Categories)
                .Where(id => id > 0 && id != 16).Order().ToArray(); // OTHER is not a shared impact area.
            var skills = isProfessional ? DiscoveryMatchingService.Evaluate(directory.Source with { Needs = need }, candidate,
                DiscoveryTargetKind.Professionals).Reasons.Single(rule => rule.Code == "skills").Evidence : [];
            // Organization candidates expose headquarters, not a project's operational geography.
            var country = candidate.Features.Countries is [var home] && home > 0 ? (int?)home : null;
            return new GapCandidate(candidate.Id, candidate.Name, candidate.Summary, candidate.Href, shared, skills, country);
        })
        .Where(candidate => isProfessional ? candidate.SharedSkills.Count > 0 : candidate.SharedCategoryIds.Count > 0)
        .Where(candidate => !international || candidate.HomeCountryId.HasValue && candidate.HomeCountryId != context.HomeCountryId)
        .Where(candidate => isProfessional || geographyState != "specific" ||
            candidate.HomeCountryId is { } country && eligible!.Contains(country))
        .OrderByDescending(candidate => candidate.SharedSkills.Count).ThenByDescending(candidate => candidate.SharedCategoryIds.Count)
        .ThenBy(candidate => candidate.Id).Take(SuggestionsPerNeed).ToArray();
        return new(code, origins, need, candidates.Length == 0 ? "no-evidence" : "suggestions",
            candidates, corpus.Length, directory.TotalCandidateCount, truncated);
    }
}
