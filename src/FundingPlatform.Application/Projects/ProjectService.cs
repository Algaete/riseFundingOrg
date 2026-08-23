using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FundingPlatform.Core.Projects;

namespace FundingPlatform.Application.Projects;

public sealed class ProjectService(IProjectRepository repository)
{
    private static readonly JsonSerializerOptions SnapshotOptions = new(JsonSerializerDefaults.Web);

    public async Task<ProjectListResult> ListAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        CancellationToken cancellationToken)
    {
        try
        {
            return new ProjectListResult(true,
                await repository.ListAsync(userPublicId, organizationPublicId, cancellationToken));
        }
        catch (ProjectDataException exception) when (exception.DatabaseErrorNumber == 51401)
        {
            return new ProjectListResult(false, []);
        }
    }

    public async Task<ProjectDetails?> GetAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        CancellationToken cancellationToken)
    {
        try
        {
            return await repository.GetAsync(
                userPublicId, organizationPublicId, projectPublicId, cancellationToken);
        }
        catch (ProjectDataException exception) when (exception.DatabaseErrorNumber == 51405)
        {
            return null;
        }
    }

    public Task<ProjectWriteResult> CreateAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        ProjectData input,
        CancellationToken cancellationToken) =>
        WriteAsync(userPublicId, organizationPublicId, null, null, input, cancellationToken);

    public Task<ProjectWriteResult> UpdateAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        byte[] expectedRowVersion,
        ProjectData input,
        CancellationToken cancellationToken) =>
        WriteAsync(userPublicId, organizationPublicId, projectPublicId, expectedRowVersion, input, cancellationToken);

    private async Task<ProjectWriteResult> WriteAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid? projectPublicId,
        byte[]? expectedRowVersion,
        ProjectData input,
        CancellationToken cancellationToken)
    {
        var project = Normalize(input);
        var errors = Validate(project);
        if (projectPublicId.HasValue && expectedRowVersion?.Length != 8)
            errors["ifMatch"] = ["If-Match no contiene una versión válida."];
        if (errors.Count > 0)
            return new ProjectWriteResult(ProjectWriteOutcome.ValidationFailed, Errors: errors);

        var snapshot = CreateSnapshot(project);
        try
        {
            var persisted = projectPublicId.HasValue
                ? await repository.UpdateAsync(
                    userPublicId, organizationPublicId, projectPublicId.Value, expectedRowVersion!, project,
                    snapshot.Json, snapshot.Hash, cancellationToken)
                : await repository.CreateAsync(
                    userPublicId, organizationPublicId, CreateSlug(project.Title), project,
                    snapshot.Json, snapshot.Hash, cancellationToken);
            return new ProjectWriteResult(ProjectWriteOutcome.Success, persisted);
        }
        catch (ProjectDataException exception) when (exception.DatabaseErrorNumber == 51407)
        {
            return new ProjectWriteResult(ProjectWriteOutcome.Conflict);
        }
        catch (ProjectDataException exception) when (exception.DatabaseErrorNumber == 51408)
        {
            return new ProjectWriteResult(ProjectWriteOutcome.InvalidState);
        }
        catch (ProjectDataException exception) when (exception.DatabaseErrorNumber is 51401 or 51402 or 51405 or 51406)
        {
            return new ProjectWriteResult(ProjectWriteOutcome.NotFound);
        }
        catch (ProjectDataException exception) when (exception.DatabaseErrorNumber is 51403 or 51404 or 51409 or 547 or 2601 or 2627)
        {
            return new ProjectWriteResult(ProjectWriteOutcome.ValidationFailed, Errors:
                new Dictionary<string, string[]> { ["project"] = ["El proyecto contiene relaciones o datos inválidos."] });
        }
    }

    private static ProjectData Normalize(ProjectData project) => project with
    {
        Title = project.Title.Trim(),
        Summary = NormalizeOptional(project.Summary),
        Description = NormalizeOptional(project.Description),
        Currency = string.IsNullOrWhiteSpace(project.Currency) ? null : project.Currency.Trim().ToUpperInvariant(),
        CountryIds = project.CountryIds.Distinct().Order().ToArray(),
        RegionIds = project.RegionIds.Distinct().Order().ToArray(),
        CategoryIds = project.CategoryIds.Distinct().Order().ToArray(),
        BeneficiaryTypeIds = project.BeneficiaryTypeIds.Distinct().Order().ToArray(),
        ProjectTypeIds = project.ProjectTypeIds.Distinct().Order().ToArray()
    };

    private static Dictionary<string, string[]> Validate(ProjectData project)
    {
        var errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        if (project.Title.Length is < 3 or > 250)
            errors["title"] = ["El título debe tener entre 3 y 250 caracteres."];
        ValidateLength(project.Summary, 1000, "summary", errors);
        ValidateLength(project.Description, 5000, "description", errors);
        if ((byte)project.Status > (byte)ProjectStatus.Completed)
            errors["status"] = ["El estado de proyecto no es válido."];
        if (project.StartDate.HasValue && project.EndDate.HasValue && project.EndDate < project.StartDate)
            errors["endDate"] = ["La fecha de término no puede ser anterior al inicio."];
        if (project.BudgetTotal is < 0 || project.ConfirmedFunding is < 0)
            errors["budgetTotal"] = ["Los montos no pueden ser negativos."];
        if (!project.BudgetTotal.HasValue && (project.ConfirmedFunding.HasValue || project.Currency is not null))
            errors["budgetTotal"] = ["Indica un presupuesto total antes de agregar moneda o financiamiento confirmado."];
        if (project.BudgetTotal.HasValue && (project.Currency?.Length != 3 ||
            !project.Currency.All(character => character is >= 'A' and <= 'Z')))
            errors["currency"] = ["Selecciona una moneda ISO de tres letras."];
        return errors;
    }

    private static void ValidateLength(
        string? value,
        int maximum,
        string key,
        IDictionary<string, string[]> errors)
    {
        if (value?.Length > maximum) errors[key] = [$"Admite hasta {maximum} caracteres."];
    }

    private static (string Json, byte[] Hash) CreateSnapshot(ProjectData project)
    {
        var json = JsonSerializer.Serialize(project, SnapshotOptions);
        return (json, SHA256.HashData(Encoding.UTF8.GetBytes(json)));
    }

    private static string CreateSlug(string title)
    {
        var decomposed = title.Normalize(NormalizationForm.FormD);
        var slug = new string(decomposed
            .Where(character => CharUnicodeInfo.GetUnicodeCategory(character) != UnicodeCategory.NonSpacingMark)
            .Select(character => char.IsLetterOrDigit(character) ? char.ToLowerInvariant(character) : '-')
            .ToArray());
        slug = string.Join('-', slug.Split('-', StringSplitOptions.RemoveEmptyEntries));
        if (slug.Length > 165) slug = slug[..165].TrimEnd('-');
        if (slug.Length == 0) slug = "proyecto";
        return $"{slug}-{Guid.NewGuid():N}"[..Math.Min(slug.Length + 9, 180)];
    }

    private static string? NormalizeOptional(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
