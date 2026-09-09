using FundingPlatform.Core.Validation;
using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Application.FundingOpportunities;

public sealed class FundingOpportunityWorkspaceService(
    IFundingOpportunityWorkspaceRepository repository)
{
    private const int MaximumFilterValues = 50;
    private const decimal MaximumSqlAmount = 999_999_999_999_999.9999m;

    public async Task<FundingOpportunityWorkspaceSearchResult> SearchAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        FundingOpportunitySearchFilters input,
        CancellationToken cancellationToken)
    {
        if (userPublicId == Guid.Empty || organizationPublicId == Guid.Empty)
        {
            return new FundingOpportunityWorkspaceSearchResult(
                FundingOpportunityWorkspaceSearchOutcome.NotFound);
        }

        var normalized = Normalize(input);
        var errors = Validate(normalized);
        if (errors.Count > 0)
        {
            return new FundingOpportunityWorkspaceSearchResult(
                FundingOpportunityWorkspaceSearchOutcome.ValidationFailed,
                Errors: errors);
        }

        WorkspaceFundingOpportunityPage? page;
        try
        {
            page = await repository.SearchAsync(
                userPublicId,
                organizationPublicId,
                normalized,
                cancellationToken);
        }
        catch (FundingOpportunityWorkspaceDataException exception)
            when (exception.DatabaseErrorNumber == 52002)
        {
            return new FundingOpportunityWorkspaceSearchResult(
                FundingOpportunityWorkspaceSearchOutcome.ValidationFailed,
                Errors: new FieldValidationErrors
                {
                    { "filters", "api-validation-031", "Uno o más filtros no son válidos." }
                });
        }
        return page is null
            ? new FundingOpportunityWorkspaceSearchResult(
                FundingOpportunityWorkspaceSearchOutcome.NotFound)
            : new FundingOpportunityWorkspaceSearchResult(
                FundingOpportunityWorkspaceSearchOutcome.Success,
                page);
    }

    public Task<WorkspaceFundingOpportunityDetails?> GetAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        string idOrSlug,
        CancellationToken cancellationToken)
    {
        var normalized = idOrSlug?.Trim();
        if (userPublicId == Guid.Empty || organizationPublicId == Guid.Empty ||
            string.IsNullOrWhiteSpace(normalized) || normalized.Length > 320)
        {
            return Task.FromResult<WorkspaceFundingOpportunityDetails?>(null);
        }

        var publicId = Guid.TryParse(normalized, out var parsed) ? parsed : (Guid?)null;
        return repository.GetPublishedAsync(
            userPublicId,
            organizationPublicId,
            publicId,
            publicId.HasValue ? null : normalized,
            cancellationToken);
    }

    public async Task<FundingOpportunityWorkspaceSearchResult> ListFavoritesAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        int pageNumber,
        int pageSize,
        CancellationToken cancellationToken)
    {
        if (userPublicId == Guid.Empty || organizationPublicId == Guid.Empty)
        {
            return new FundingOpportunityWorkspaceSearchResult(
                FundingOpportunityWorkspaceSearchOutcome.NotFound);
        }

        var errors = ValidatePagination(pageNumber, pageSize);
        if (errors.Count > 0)
        {
            return new FundingOpportunityWorkspaceSearchResult(
                FundingOpportunityWorkspaceSearchOutcome.ValidationFailed,
                Errors: errors);
        }

        var page = await repository.ListFavoritesAsync(
            userPublicId,
            organizationPublicId,
            pageNumber,
            pageSize,
            cancellationToken);
        return page is null
            ? new FundingOpportunityWorkspaceSearchResult(
                FundingOpportunityWorkspaceSearchOutcome.NotFound)
            : new FundingOpportunityWorkspaceSearchResult(
                FundingOpportunityWorkspaceSearchOutcome.Success,
                page);
    }

    public Task<FundingFavoriteMutation> PutFavoriteAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid fundingOpportunityPublicId,
        CancellationToken cancellationToken) =>
        userPublicId == Guid.Empty || organizationPublicId == Guid.Empty ||
        fundingOpportunityPublicId == Guid.Empty
            ? Task.FromResult(new FundingFavoriteMutation(
                FundingFavoriteMutationOutcome.NotFound,
                fundingOpportunityPublicId,
                null))
            : repository.PutFavoriteAsync(
                userPublicId,
                organizationPublicId,
                fundingOpportunityPublicId,
                cancellationToken);

    public Task<FundingFavoriteMutation> DeleteFavoriteAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid fundingOpportunityPublicId,
        CancellationToken cancellationToken) =>
        userPublicId == Guid.Empty || organizationPublicId == Guid.Empty ||
        fundingOpportunityPublicId == Guid.Empty
            ? Task.FromResult(new FundingFavoriteMutation(
                FundingFavoriteMutationOutcome.NotFound,
                fundingOpportunityPublicId,
                null))
            : repository.DeleteFavoriteAsync(
                userPublicId,
                organizationPublicId,
                fundingOpportunityPublicId,
                cancellationToken);

    public static FundingOpportunitySearchFilters Normalize(
        FundingOpportunitySearchFilters input) => input with
    {
        Query = NormalizeOptional(input.Query),
        Sponsor = NormalizeOptional(input.Sponsor),
        Currency = NormalizeOptional(input.Currency)?.ToUpperInvariant(),
        CountryIds = NormalizeIds(input.CountryIds ?? []),
        RegionIds = NormalizeIds(input.RegionIds ?? []),
        CategoryIds = NormalizeIds(input.CategoryIds ?? []),
        TagIds = NormalizeIds(input.TagIds ?? []),
        BeneficiaryTypeIds = NormalizeIds(input.BeneficiaryTypeIds ?? []),
        ProjectTypeIds = NormalizeIds(input.ProjectTypeIds ?? []),
        FundingTypeIds = NormalizeIds(input.FundingTypeIds ?? []),
        OrganizationTypeIds = NormalizeIds(input.OrganizationTypeIds ?? []),
        FunderPublicIds = (input.FunderPublicIds ?? []).Distinct().Order().ToArray()
    };

    public static FieldValidationErrors Validate(
        FundingOpportunitySearchFilters filters)
    {
        var errors = ValidatePagination(filters.PageNumber, filters.PageSize);
        ValidateLength(filters.Query, 300, "q", errors);
        ValidateLength(filters.Sponsor, 300, "sponsor", errors);

        if (!Enum.IsDefined(filters.Sort))
        {
            errors.Set("sort", "api-validation-032", "El orden solicitado no está permitido.");
        }

        if (IsInvalidAmount(filters.MinimumAmount) || IsInvalidAmount(filters.MaximumAmount) ||
            (filters.MinimumAmount.HasValue && filters.MaximumAmount.HasValue &&
             filters.MaximumAmount < filters.MinimumAmount))
        {
            errors.Set("amount", "api-validation-033", "El rango de montos no es válido.");
        }

        if ((filters.MinimumAmount.HasValue || filters.MaximumAmount.HasValue) &&
            filters.Currency is null)
        {
            errors.Set("currency", "api-validation-034", "Selecciona una moneda para filtrar por monto.");
        }

        if (filters.Currency is not null &&
            (filters.Currency.Length != 3 || filters.Currency.Any(character =>
                character is < 'A' or > 'Z')))
        {
            errors.Set("currency", "api-validation-035", "La moneda debe ser un código ISO de tres letras.");
        }

        if (filters.ClosingFrom.HasValue && filters.ClosingTo.HasValue &&
            filters.ClosingTo < filters.ClosingFrom)
        {
            errors.Set("closingTo", "api-validation-036", "La fecha final no puede ser anterior a la fecha inicial.");
        }

        if (filters.Sort == FundingOpportunitySearchSort.Relevance && filters.Query is null)
        {
            errors.Set("sort", "api-validation-037", "El orden por relevancia requiere un texto de búsqueda.");
        }

        if (filters.Sort is FundingOpportunitySearchSort.AmountAscending or
            FundingOpportunitySearchSort.AmountDescending && filters.Currency is null)
        {
            errors.Set("sort", "api-validation-038", "Para ordenar por monto debes seleccionar una moneda.");
        }

        ValidateIds(filters.CountryIds, "countryIds", errors);
        ValidateIds(filters.RegionIds, "regionIds", errors);
        ValidateIds(filters.CategoryIds, "categoryIds", errors);
        ValidateIds(filters.TagIds, "tagIds", errors);
        ValidateIds(filters.BeneficiaryTypeIds, "beneficiaryTypeIds", errors);
        ValidateIds(filters.ProjectTypeIds, "projectTypeIds", errors);
        ValidateIds(filters.FundingTypeIds, "fundingTypeIds", errors);
        ValidateIds(filters.OrganizationTypeIds, "organizationTypeIds", errors);
        if (filters.FunderPublicIds.Count > MaximumFilterValues ||
            filters.FunderPublicIds.Any(id => id == Guid.Empty))
        {
            errors.Set("funderIds", "api-validation-039", $"Admite hasta {MaximumFilterValues} identificadores válidos.", max: MaximumFilterValues);
        }

        return errors;
    }

    private static FieldValidationErrors ValidatePagination(int pageNumber, int pageSize)
    {
        var errors = new FieldValidationErrors();
        if (pageNumber is < 1 or > 10_000)
        {
            errors.Set("page", "api-validation-040", "La página debe estar entre 1 y 10000.");
        }

        if (pageSize is < 1 or > 50)
        {
            errors.Set("pageSize", "api-validation-041", "El tamaño de página debe estar entre 1 y 50.");
        }

        return errors;
    }

    private static void ValidateLength(
        string? value,
        int maximum,
        string key,
        FieldValidationErrors errors)
    {
        if (value?.Length > maximum)
        {
            errors.Set(key, "text-max-length", $"Admite hasta {maximum} caracteres.", max: maximum);
        }
    }

    private static bool IsInvalidAmount(decimal? value)
    {
        if (!value.HasValue)
        {
            return false;
        }

        var scale = (decimal.GetBits(value.Value)[3] >> 16) & 0x7F;
        return value < 0 || value > MaximumSqlAmount || scale > 4;
    }

    private static void ValidateIds<T>(
        IReadOnlyCollection<T> ids,
        string key,
        FieldValidationErrors errors) where T : struct, IComparable<T>
    {
        if (ids.Count > MaximumFilterValues || ids.Any(id => id.CompareTo(default) <= 0))
        {
            errors.Set(key, "api-validation-043", $"Admite hasta {MaximumFilterValues} identificadores positivos.", max: MaximumFilterValues);
        }
    }

    private static T[] NormalizeIds<T>(IEnumerable<T> values) where T : IComparable<T> =>
        values.Distinct().Order().ToArray();

    private static string? NormalizeOptional(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}

public enum FundingOpportunityWorkspaceSearchOutcome
{
    Success,
    ValidationFailed,
    NotFound
}

public sealed record FundingOpportunityWorkspaceSearchResult(
    FundingOpportunityWorkspaceSearchOutcome Outcome,
    WorkspaceFundingOpportunityPage? Page = null,
    IReadOnlyDictionary<string, string[]>? Errors = null);
