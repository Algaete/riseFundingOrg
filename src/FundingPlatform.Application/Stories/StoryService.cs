using FundingPlatform.Core.Stories;
using FundingPlatform.Core.Validation;

namespace FundingPlatform.Application.Stories;

public interface IStoryRepository
{
    Task<StoryPage> ListAsync(Guid? actor, Guid? organization, Guid? project, Guid? story, int page, CancellationToken token);
    Task SaveAsync(Guid actor, Guid organization, Guid story, StoryWrite data, CancellationToken token);
    Task PublishAsync(Guid actor, Guid organization, Guid story, StoryPublication data, CancellationToken token);
}
public sealed class StoryDataException(int number, Exception inner) : Exception("Story operation failed.", inner)
{ public int Number { get; } = number; }

public static class StoryRules
{
    public static readonly string[] Kinds = ["organization", "project", "fieldwork", "volunteers", "team", "learning", "impact", "news", "beneficiaries"];
    public static StoryWrite Normalize(StoryWrite value) => value with { Content = value.Content is not { } c ? null : c with
    {
        Title = c.Title?.Trim() ?? "", Body = c.Body?.Trim() ?? "", Summary = string.IsNullOrWhiteSpace(c.Summary) ? null : c.Summary.Trim(),
        CategoryIds = c.CategoryIds?.Distinct().Order().ToArray() ?? [], GoalIds = c.GoalIds?.Distinct().Order().ToArray() ?? [],
        CountryIds = c.CountryIds?.Distinct().Order().ToArray() ?? []
    } };
    public static FieldValidationErrors Validate(StoryWrite value)
    {
        var errors = new FieldValidationErrors();
        if (value.ExpectedRevision < 0 || value.Content is null)
            errors.Set("story", "story-invalid", "Falta el contenido o la versión de la historia.");
        if (value.Content is not { } c) return errors;
        if (c.Title.Length is < 3 or > 200) errors.Set("title", "story-title", "El título debe tener entre 3 y 200 caracteres.");
        if (c.Body.Length is < 20 or > 15000) errors.Set("body", "story-body", "La historia debe tener entre 20 y 15.000 caracteres.");
        if (c.Summary?.Length > 600) errors.Set("summary", "text-max-length", "El resumen admite 600 caracteres.", max: 600);
        if (!Kinds.Contains(c.Kind)) errors.Set("kind", "story-kind", "Selecciona un tipo de historia válido.");
        if (c.ProjectId == Guid.Empty) errors.Set("projectId", "story-project", "Selecciona un proyecto válido.");
        Check(c.CategoryIds, 30, int.MaxValue, "categoryIds", errors);
        Check(c.GoalIds, 17, 17, "goalIds", errors);
        Check(c.CountryIds, 50, short.MaxValue, "countryIds", errors);
        return errors;
    }
    private static void Check(IReadOnlyList<int>? values, int count, int max, string key, FieldValidationErrors errors)
    {
        if (values is null || values.Count > count || values.Any(x => x < 1 || x > max))
            errors.Set(key, "story-catalog", "Revisa las selecciones de la historia.");
    }
}
