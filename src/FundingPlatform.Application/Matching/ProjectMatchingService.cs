using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Core.Matching;

namespace FundingPlatform.Application.Matching;

public sealed class ProjectMatchingService(IProjectMatchingRepository repository)
{
    public const int MinimumIdempotencyKeyLength = 16;
    public const int MaximumIdempotencyKeyLength = 128;
    public const int MaximumPageNumber = 10_000;
    public const int MaximumPageSize = 50;

    private const string RequestContractVersion = "project-matching-run-create-v1";

    public async Task<ProjectMatchingRunPageResult> ListRunsAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        ProjectMatchingRunListFilters filters,
        CancellationToken cancellationToken)
    {
        var errors = ValidateIdentifiers(organizationPublicId, projectPublicId);
        if (filters.PageNumber is < 1 or > MaximumPageNumber)
        {
            errors["page"] = [$"La página debe estar entre 1 y {MaximumPageNumber}."];
        }

        if (filters.PageSize is < 1 or > MaximumPageSize)
        {
            errors["pageSize"] = [$"El tamaño de página debe estar entre 1 y {MaximumPageSize}."];
        }

        if (errors.Count > 0)
        {
            return new ProjectMatchingRunPageResult(
                ProjectMatchingOutcome.ValidationFailed,
                Errors: errors);
        }

        try
        {
            var page = await repository.ListRunsAsync(
                userPublicId,
                organizationPublicId,
                projectPublicId,
                filters,
                cancellationToken);
            return new ProjectMatchingRunPageResult(ProjectMatchingOutcome.Success, page);
        }
        catch (ProjectMatchingDataException exception) when (exception.DatabaseErrorNumber == 52401)
        {
            return new ProjectMatchingRunPageResult(ProjectMatchingOutcome.NotFound);
        }
        catch (ProjectMatchingDataException exception) when (exception.DatabaseErrorNumber == 52402)
        {
            return new ProjectMatchingRunPageResult(
                ProjectMatchingOutcome.ValidationFailed,
                Errors: new Dictionary<string, string[]>
                {
                    ["filters"] = ["Los filtros de ejecuciones no son válidos."]
                });
        }
    }

    public async Task<ProjectMatchingRunDetailsResult> GetRunAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid matchingRunPublicId,
        CancellationToken cancellationToken)
    {
        if (organizationPublicId == Guid.Empty || projectPublicId == Guid.Empty ||
            matchingRunPublicId == Guid.Empty)
        {
            return new ProjectMatchingRunDetailsResult(ProjectMatchingOutcome.NotFound);
        }

        try
        {
            var details = await repository.GetRunAsync(
                userPublicId,
                organizationPublicId,
                projectPublicId,
                matchingRunPublicId,
                cancellationToken);
            return details is null
                ? new ProjectMatchingRunDetailsResult(ProjectMatchingOutcome.NotFound)
                : new ProjectMatchingRunDetailsResult(ProjectMatchingOutcome.Success, details);
        }
        catch (ProjectMatchingDataException exception) when (exception.DatabaseErrorNumber == 52401)
        {
            return new ProjectMatchingRunDetailsResult(ProjectMatchingOutcome.NotFound);
        }
    }

    public async Task<ProjectMatchingRunDetailsResult> CreateRunAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        string idempotencyKey,
        CancellationToken cancellationToken)
    {
        var errors = ValidateIdentifiers(organizationPublicId, projectPublicId);
        var normalizedKey = idempotencyKey?.Trim() ?? string.Empty;
        if (normalizedKey.Length is < MinimumIdempotencyKeyLength or > MaximumIdempotencyKeyLength)
        {
            errors["idempotencyKey"] =
                [$"Idempotency-Key debe tener entre {MinimumIdempotencyKeyLength} y {MaximumIdempotencyKeyLength} caracteres."];
        }

        if (errors.Count > 0)
        {
            return new ProjectMatchingRunDetailsResult(
                ProjectMatchingOutcome.ValidationFailed,
                Errors: errors);
        }

        var idempotencyKeyHash = SHA256.HashData(Encoding.UTF8.GetBytes(normalizedKey));
        var requestHash = SHA256.HashData(Encoding.UTF8.GetBytes(
            $"{RequestContractVersion}|{organizationPublicId:D}|{projectPublicId:D}"));

        try
        {
            var mutation = await repository.CreateRunAsync(
                userPublicId,
                organizationPublicId,
                projectPublicId,
                idempotencyKeyHash,
                requestHash,
                cancellationToken);
            if (!mutation.Succeeded)
            {
                return MapMutationFailure(mutation.Code);
            }

            var details = await repository.GetRunAsync(
                userPublicId,
                organizationPublicId,
                projectPublicId,
                mutation.MatchingRunPublicId,
                cancellationToken);
            return details is null
                ? new ProjectMatchingRunDetailsResult(ProjectMatchingOutcome.NotFound)
                : new ProjectMatchingRunDetailsResult(
                    ProjectMatchingOutcome.Success,
                    details,
                    WasReplay: mutation.WasReplay);
        }
        catch (ProjectMatchingDataException exception) when (exception.DatabaseErrorNumber == 52401)
        {
            return new ProjectMatchingRunDetailsResult(ProjectMatchingOutcome.NotFound);
        }
        catch (ProjectMatchingDataException exception) when (exception.DatabaseErrorNumber == 52402)
        {
            return new ProjectMatchingRunDetailsResult(
                ProjectMatchingOutcome.ValidationFailed,
                Errors: new Dictionary<string, string[]>
                {
                    ["project"] = ["El proyecto o su perfil institucional no están listos para calcular compatibilidad."]
                });
        }
        catch (ProjectMatchingDataException exception) when (exception.DatabaseErrorNumber == 52403)
        {
            return new ProjectMatchingRunDetailsResult(
                ProjectMatchingOutcome.IdempotencyConflict);
        }
        catch (ProjectMatchingDataException exception) when (exception.DatabaseErrorNumber == 52404)
        {
            return new ProjectMatchingRunDetailsResult(ProjectMatchingOutcome.Unavailable);
        }
    }

    private static ProjectMatchingRunDetailsResult MapMutationFailure(string code) => code switch
    {
        "not-found" => new(ProjectMatchingOutcome.NotFound),
        "idempotency-conflict" => new(ProjectMatchingOutcome.IdempotencyConflict),
        "project-not-ready" or "profile-not-ready" => new(
            ProjectMatchingOutcome.NotReady,
            Errors: new Dictionary<string, string[]>
            {
                ["project"] = ["Completa el proyecto y el perfil institucional antes de calcular compatibilidad."]
            }),
        "invalid-input" => new(
            ProjectMatchingOutcome.ValidationFailed,
            Errors: new Dictionary<string, string[]>
            {
                ["project"] = ["No fue posible validar los datos para esta ejecución."]
            }),
        _ => new(ProjectMatchingOutcome.Conflict)
    };

    private static Dictionary<string, string[]> ValidateIdentifiers(
        Guid organizationPublicId,
        Guid projectPublicId)
    {
        var errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        if (organizationPublicId == Guid.Empty)
        {
            errors["organizationId"] = ["La organización no es válida."];
        }

        if (projectPublicId == Guid.Empty)
        {
            errors["projectId"] = ["El proyecto no es válido."];
        }

        return errors;
    }
}
