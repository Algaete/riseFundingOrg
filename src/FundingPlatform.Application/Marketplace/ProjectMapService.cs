using FundingPlatform.Core.Marketplace;
using FundingPlatform.Core.Validation;

namespace FundingPlatform.Application.Marketplace;

public interface IProjectMapRepository
{
    Task<ProjectMapPage> SearchAsync(ProjectMapFilters filters, CancellationToken cancellationToken);
}

public sealed class ProjectMapService(IProjectMapRepository repository)
{
    public static FieldValidationErrors Validate(ProjectMapFilters filters)
    {
        var errors = new FieldValidationErrors();
        if (filters.Query?.Trim().Length > 200)
            errors.Set("q", "text-max-length", "Admite hasta 200 caracteres.", max: 200);
        if (filters.CountryId is <= 0 || filters.CategoryId is <= 0 || filters.OrganizationTypeId is <= 0 || filters.ProjectStage is > 5 ||
            filters.ProjectStatus is > 6 || filters.SustainableDevelopmentGoalId is < 1 or > 17 ||
            filters.Page is < 1 or > 10000 || filters.PageSize is < 1 or > 200)
            errors.Set("filters", "api-validation-131", "El valor no es válido.");
        foreach (var amount in new[] { filters.MinimumFundingGap, filters.MaximumFundingGap })
            if (amount is < 0 or > 999999999999m || amount.HasValue && decimal.Round(amount.Value, 4) != amount.Value)
                errors.Set("amount", "api-validation-131", "El valor no es válido.");
        if (filters.MinimumFundingGap > filters.MaximumFundingGap)
            errors.Set("amount", "api-validation-131", "El valor no es válido.");
        if ((filters.MinimumFundingGap.HasValue || filters.MaximumFundingGap.HasValue) && filters.Currency is null ||
            filters.Currency is { } currency && (currency.Length != 3 || currency.Any(c => c is < 'A' or > 'Z')))
            errors.Set("currency", "api-validation-131", "Selecciona una moneda para filtrar montos; no se convierten monedas.");
        if (filters.ProjectIds is { } ids && (ids.Count is < 1 or > 50 || ids.Contains(Guid.Empty) || ids.Distinct().Count() != ids.Count))
            errors.Set("projectIds", "api-validation-131", "Elige entre 1 y 50 proyectos distintos.");
        return errors;
    }

    public Task<ProjectMapPage> SearchAsync(ProjectMapFilters filters, CancellationToken cancellationToken)
    {
        if (Validate(filters).Count > 0) throw new ArgumentException("Invalid map filters.", nameof(filters));
        return repository.SearchAsync(filters with { Query = string.IsNullOrWhiteSpace(filters.Query) ? null : filters.Query.Trim() }, cancellationToken);
    }
}
