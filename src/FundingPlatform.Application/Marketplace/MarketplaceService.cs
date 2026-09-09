using FundingPlatform.Core.Validation;
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
                Errors: new FieldValidationErrors
                {
                    { "filters", "api-validation-097", "Los filtros del marketplace no son válidos." }
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

    private static FieldValidationErrors Validate(MarketplaceProjectFilters filters)
    {
        var errors = new FieldValidationErrors();
        if (filters.Query?.Length > MaximumQueryLength)
        {
            errors.Set("q", "api-validation-098", $"La búsqueda admite hasta {MaximumQueryLength} caracteres.", max: MaximumQueryLength);
        }

        ValidateIdentifiers(filters.CountryIds, "countryIds", errors);
        ValidateIdentifiers(filters.CategoryIds, "categoryIds", errors);
        ValidateIdentifiers(filters.ProjectTypeIds, "projectTypeIds", errors);
        if (filters.ProjectStatus.HasValue &&
            (byte)filters.ProjectStatus.Value > (byte)ProjectStatus.Completed)
        {
            errors.Set("projectStatus", "project-status-invalid", "El estado de proyecto no es válido.");
        }

        if (filters.Currency is not null &&
            (filters.Currency.Length != 3 ||
             !filters.Currency.All(character => character is >= 'A' and <= 'Z')))
        {
            errors.Set("currency", "currency-invalid", "Selecciona una moneda ISO de tres letras.");
        }

        if (filters.Sort == MarketplaceProjectSort.FundingGapDescending &&
            filters.Currency is null)
        {
            errors.Set("currency", "api-validation-100", "Selecciona una moneda para ordenar por brecha de financiamiento.");
        }

        if (!Enum.IsDefined(filters.Sort))
        {
            errors.Set("sort", "api-validation-101", "El orden solicitado no es válido.");
        }

        if (filters.PageNumber is < 1 or > MaximumPageNumber)
        {
            errors.Set("page", "api-validation-013", $"La página debe estar entre 1 y {MaximumPageNumber}.", max: MaximumPageNumber);
        }

        if (filters.PageSize is < 1 or > MaximumPageSize)
        {
            errors.Set("pageSize", "api-validation-014", $"El tamaño de página debe estar entre 1 y {MaximumPageSize}.", max: MaximumPageSize);
        }

        return errors;
    }

    private static void ValidateIdentifiers<T>(
        IReadOnlyCollection<T> identifiers,
        string key,
        FieldValidationErrors errors) where T : struct, IComparable<T>
    {
        if (identifiers.Count > MaximumFilterValues ||
            identifiers.Any(identifier => identifier.CompareTo(default) <= 0))
        {
            errors.Set(key, "api-validation-043", $"Admite hasta {MaximumFilterValues} identificadores positivos.", max: MaximumFilterValues);
        }
    }

    private static string? NormalizeOptional(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
