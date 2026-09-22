using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Core.Validation;

namespace FundingPlatform.Application.FundingOpportunities;

public sealed class FundingTranslationOptions { public bool Enabled { get; init; } }

public interface IFundingTranslationRepository
{
    Task<FundingTranslation?> GetAdminAsync(Guid actor, Guid id, string language, CancellationToken token);
    Task<FundingTranslation?> GetPublishedAsync(Guid id, string language, int sourceContentVersion, CancellationToken token);
    Task<IReadOnlyList<FundingSummaryTranslation>> GetPublishedSummariesAsync(
        IReadOnlyList<FundingTranslationReference> references, string language, CancellationToken token);
    Task<FundingTranslation> SaveAsync(Guid actor, Guid id, string language, FundingTranslationWrite data,
        byte[] sourceRowVersion, CancellationToken token);
}

public sealed class FundingTranslationDataException(int number, Exception inner)
    : Exception("Funding translation operation failed.", inner)
{ public int Number { get; } = number; }

public static class FundingTranslationRules
{
    public static bool Supports(string? language) => language is "es" or "en";
    public static FundingTranslationText From(FundingOpportunityEditorialData item) => new(
        item.Title, item.Summary, item.Description, item.EligibilityDescription, item.Requirements,
        item.Objectives, item.AllowedActivities, item.ExcludedActivities, item.Restrictions,
        item.TargetOrganizationsDescription, item.TargetPopulationsDescription);

    public static FundingTranslationText Normalize(FundingTranslationText item) => new(
        Trim(item.Title), Trim(item.Summary), Trim(item.Description), Trim(item.EligibilityDescription),
        Trim(item.Requirements), Trim(item.Objectives), Trim(item.AllowedActivities), Trim(item.ExcludedActivities),
        Trim(item.Restrictions), Trim(item.TargetOrganizationsDescription), Trim(item.TargetPopulationsDescription));
    private static string? Trim(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    public static FieldValidationErrors Validate(FundingTranslationWrite data, FundingTranslationText original)
    {
        var errors = new FieldValidationErrors();
        if (data.SourceContentVersion < 1 || data.ExpectedRevision < 0)
            errors.Set("version", "api-validation-131", "La versión no es válida.");
        if (data.Text is null)
        {
            errors.Set("text", "api-validation-131", "Falta el contenido de la traducción.");
            return errors;
        }
        var fields = Fields(data.Text).Zip(Fields(original));
        foreach (var (translated, source) in fields)
        {
            if (translated.Value?.Length > translated.Max)
                errors.Set($"text.{translated.Key}", "text-max-length", $"Admite hasta {translated.Max} caracteres.", max: translated.Max);
            // Reviewed versions are complete, never a silent mixture of languages;
            // do not add conditions where the source has no content.
            if (data.Reviewed && string.IsNullOrWhiteSpace(source.Value) != string.IsNullOrWhiteSpace(translated.Value))
                errors.Set($"text.{translated.Key}", "api-validation-131", "Traduce cada campo del original sin añadir contenido a campos vacíos.");
        }
        return errors;
    }

    public static IEnumerable<(string Key, string? Value, int Max)> Fields(FundingTranslationText text)
    {
        yield return ("title", text.Title, 350);
        yield return ("summary", text.Summary, 2000);
        yield return ("description", text.Description, 50000);
        yield return ("eligibilityDescription", text.EligibilityDescription, 30000);
        yield return ("requirements", text.Requirements, 30000);
        yield return ("objectives", text.Objectives, 30000);
        yield return ("allowedActivities", text.AllowedActivities, 30000);
        yield return ("excludedActivities", text.ExcludedActivities, 30000);
        yield return ("restrictions", text.Restrictions, 30000);
        yield return ("targetOrganizationsDescription", text.TargetOrganizationsDescription, 2000);
        yield return ("targetPopulationsDescription", text.TargetPopulationsDescription, 2000);
    }
}

public sealed class FundingTranslationService(IFundingTranslationRepository repository, FundingTranslationOptions options)
{
    public bool Enabled => options.Enabled;

    public async Task<FundingOpportunityPage> LocalizeAsync(FundingOpportunityPage page, string? language, CancellationToken token) =>
        page with { Items = await LocalizeItems(page.Items, language, x => new(x.PublicId, x.ContentVersion),
            x => x.Summary, (x, text, info) => x with { Title = text?.Title ?? x.Title,
                Summary = text is null ? x.Summary : text.Summary, Localization = info }, token) };

    public async Task<WorkspaceFundingOpportunityPage> LocalizeAsync(WorkspaceFundingOpportunityPage page, string? language, CancellationToken token) =>
        page with { Items = await LocalizeItems(page.Items, language, x => new(x.PublicId, x.ContentVersion),
            x => x.Summary, (x, text, info) => x with { Title = text?.Title ?? x.Title,
                Summary = text is null ? x.Summary : text.Summary, Localization = info }, token) };

    public async Task<FundingDiscoveryPage> LocalizeAsync(FundingDiscoveryPage page, string? language, CancellationToken token) =>
        page with { Items = await LocalizeItems(page.Items, language, x => new(x.Id, x.ContentVersion),
            x => x.Summary, (x, text, info) => x with { Title = text?.Title ?? x.Title,
                Summary = text is null ? x.Summary : text.Summary, Localization = info }, token) };

    private async Task<IReadOnlyList<T>> LocalizeItems<T>(IReadOnlyList<T> items, string? language,
        Func<T, FundingTranslationReference> reference, Func<T, string?> summary,
        Func<T, FundingSummaryTranslation?, FundingTranslationLocalization, T> apply, CancellationToken token)
    {
        if (!options.Enabled || language is null) return items;
        if (!FundingTranslationRules.Supports(language)) throw new ArgumentException("Unsupported language.", nameof(language));
        // One bounded SQL read per page, not one per card. IDs originate only from
        // the already-authorized, filtered page; SQL rechecks publication/version.
        if (items.Count > 100) throw new ArgumentOutOfRangeException(nameof(items));
        var references = items.Select(reference).Where(x => x.SourceContentVersion > 0).Distinct().ToArray();
        var values = references.Length == 0 ? [] : await repository.GetPublishedSummariesAsync(references, language, token);
        var allowed = references.ToHashSet();
        var translations = values.Where(x => x.Reviewed && x.Revision > 0 && x.Language == language
                && allowed.Contains(new(x.OpportunityId, x.SourceContentVersion))
                && !string.IsNullOrWhiteSpace(x.Title) && x.Title.Length <= 350 && x.Summary?.Length is not > 2000)
            .GroupBy(x => new FundingTranslationReference(x.OpportunityId, x.SourceContentVersion))
            .Where(group => group.Count() == 1).ToDictionary(group => group.Key, group => group.Single());
        return items.Select(item =>
        {
            translations.TryGetValue(reference(item), out var text);
            // Never silently mix a translated title with an original summary.
            if (text is not null && string.IsNullOrWhiteSpace(summary(item)) != string.IsNullOrWhiteSpace(text.Summary)) text = null;
            return apply(item, text, new(language, text is null ? "original" : "translated", text?.Revision));
        }).ToArray();
    }

    private async Task<FundingTranslation?> Read(Guid id, string language, int version, CancellationToken token)
    {
        if (!options.Enabled || !FundingTranslationRules.Supports(language) || version < 1) return null;
        var value = await repository.GetPublishedAsync(id, language, version, token);
        return value is { Reviewed: true } && value.Language == language && value.SourceContentVersion == version ? value : null;
    }

    public async Task<FundingOpportunityDetails> LocalizeAsync(FundingOpportunityDetails item, string? language, CancellationToken token)
    {
        if (!options.Enabled || language is null) return item;
        var translation = await Read(item.PublicId, language, item.ContentVersion, token);
        var info = new FundingTranslationLocalization(language, translation is null ? "original" : "translated", translation?.Revision);
        if (translation is null) return item with { Localization = info };
        var text = translation.Text;
        return item with { Title = text.Title!, Summary = text.Summary, Description = text.Description,
            EligibilityDescription = text.EligibilityDescription, Requirements = text.Requirements,
            Objectives = text.Objectives, Localization = info };
    }

    public async Task<WorkspaceFundingOpportunityDetails> LocalizeAsync(WorkspaceFundingOpportunityDetails item, string? language, CancellationToken token)
    {
        if (!options.Enabled || language is null) return item;
        var translation = await Read(item.PublicId, language, item.ContentVersion, token);
        var info = new FundingTranslationLocalization(language, translation is null ? "original" : "translated", translation?.Revision);
        if (translation is null) return item with { Localization = info };
        var text = translation.Text;
        return item with { Title = text.Title!, Summary = text.Summary, Description = text.Description,
            EligibilityDescription = text.EligibilityDescription, Requirements = text.Requirements,
            Objectives = text.Objectives, AllowedActivities = text.AllowedActivities,
            ExcludedActivities = text.ExcludedActivities, Restrictions = text.Restrictions,
            TargetOrganizationsDescription = text.TargetOrganizationsDescription,
            TargetPopulationsDescription = text.TargetPopulationsDescription, Localization = info };
    }
}
