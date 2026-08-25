using FundingPlatform.Core.Marketplace;
using FundingPlatform.Core.Projects;

namespace FundingPlatform.Application.Marketplace;

public sealed class MarketplaceService(IMarketplaceRepository repository)
{
    public const int MaximumQueryLength = 200;
    public const int MaximumFilterValues = 50;
    public const int MaximumPageNumber = 10_000;
    public const int MaximumPageSize = 50;

    public async Task<MarketplaceProjectPageResult> SearchProjectsAsync(
        MarketplaceProjectFilters filters,
        CancellationToken cancellationToken)
    {
        var normalized = filters with
        {
            Query = NormalizeOptional(filters.Query),
            Currency = NormalizeOptional(filters.Currency)?.ToUpperInvariant(),
            CountryIds = filters.CountryIds.Distinct().Order().ToArray(),
            CategoryIds = filters.CategoryIds.Distinct().Order().ToArray(),
            ProjectTypeIds = filters.ProjectTypeIds.Distinct().Order().ToArray()
        };
        var errors = Validate(normalized);
        if (errors.Count > 0)
        {
            return new MarketplaceProjectPageResult(
                MarketplaceOutcome.ValidationFailed,
                Errors: errors);
        }

        try
        {
            return new MarketplaceProjectPageResult(
                MarketplaceOutcome.Success,
                await repository.SearchProjectsAsync(normalized, cancellationToken));
        }
        catch (MarketplaceDataException exception) when (exception.DatabaseErrorNumber == 52102)
        {
            return new MarketplaceProjectPageResult(
                MarketplaceOutcome.ValidationFailed,
                Errors: new Dictionary<string, string[]>
                {
                    ["filters"] = ["Los filtros del marketplace no son válidos."]
                });
        }
    }

    public async Task<MarketplaceProjectDetailsResult> GetProjectBySlugAsync(
        string slug,
        CancellationToken cancellationToken)
    {
        var normalized = NormalizeOptional(slug);
        if (normalized is null || normalized.Length > 180)
        {
            return new MarketplaceProjectDetailsResult(MarketplaceOutcome.NotFound);
        }

        var project = await repository.GetProjectBySlugAsync(normalized, cancellationToken);
        return project is null
            ? new MarketplaceProjectDetailsResult(MarketplaceOutcome.NotFound)
            : new MarketplaceProjectDetailsResult(MarketplaceOutcome.Success, project);
    }

    public async Task<MarketplaceOrganizationResult> GetOrganizationAsync(
        Guid organizationPublicId,
        CancellationToken cancellationToken)
    {
        if (organizationPublicId == Guid.Empty)
        {
            return new MarketplaceOrganizationResult(MarketplaceOutcome.NotFound);
        }

        var organization = await repository.GetOrganizationAsync(
            organizationPublicId,
            cancellationToken);
        return organization is null
            ? new MarketplaceOrganizationResult(MarketplaceOutcome.NotFound)
            : new MarketplaceOrganizationResult(MarketplaceOutcome.Success, organization);
    }

    private static Dictionary<string, string[]> Validate(MarketplaceProjectFilters filters)
    {
        var errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        if (filters.Query?.Length > MaximumQueryLength)
        {
            errors["q"] = [$"La búsqueda admite hasta {MaximumQueryLength} caracteres."];
        }

        ValidateIdentifiers(filters.CountryIds, "countryIds", errors);
        ValidateIdentifiers(filters.CategoryIds, "categoryIds", errors);
        ValidateIdentifiers(filters.ProjectTypeIds, "projectTypeIds", errors);
        if (filters.ProjectStatus.HasValue &&
            (byte)filters.ProjectStatus.Value > (byte)ProjectStatus.Completed)
        {
            errors["projectStatus"] = ["El estado de proyecto no es válido."];
        }

        if (filters.Currency is not null &&
            (filters.Currency.Length != 3 ||
             !filters.Currency.All(character => character is >= 'A' and <= 'Z')))
        {
            errors["currency"] = ["Selecciona una moneda ISO de tres letras."];
        }

        if (filters.Sort == MarketplaceProjectSort.FundingGapDescending &&
            filters.Currency is null)
        {
            errors["currency"] =
                ["Selecciona una moneda para ordenar por brecha de financiamiento."];
        }

        if (!Enum.IsDefined(filters.Sort))
        {
            errors["sort"] = ["El orden solicitado no es válido."];
        }

        if (filters.PageNumber is < 1 or > MaximumPageNumber)
        {
            errors["page"] = [$"La página debe estar entre 1 y {MaximumPageNumber}."];
        }

        if (filters.PageSize is < 1 or > MaximumPageSize)
        {
            errors["pageSize"] = [$"El tamaño de página debe estar entre 1 y {MaximumPageSize}."];
        }

        return errors;
    }

    private static void ValidateIdentifiers<T>(
        IReadOnlyCollection<T> identifiers,
        string key,
        IDictionary<string, string[]> errors) where T : struct, IComparable<T>
    {
        if (identifiers.Count > MaximumFilterValues ||
            identifiers.Any(identifier => identifier.CompareTo(default) <= 0))
        {
            errors[key] =
                [$"Admite hasta {MaximumFilterValues} identificadores positivos."];
        }
    }

    private static string? NormalizeOptional(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
