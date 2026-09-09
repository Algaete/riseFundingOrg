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
        if (filters.CountryId is <= 0 || filters.CategoryId is <= 0 || filters.ProjectStage is > 5 ||
            filters.ProjectStatus is > 6 || filters.SustainableDevelopmentGoalId is < 1 or > 17 ||
            filters.Page is < 1 or > 10000 || filters.PageSize is < 1 or > 200)
            errors.Set("filters", "api-validation-131", "El valor no es válido.");
        return errors;
    }

    public Task<ProjectMapPage> SearchAsync(ProjectMapFilters filters, CancellationToken cancellationToken)
    {
        if (Validate(filters).Count > 0) throw new ArgumentException("Invalid map filters.", nameof(filters));
        return repository.SearchAsync(filters with { Query = string.IsNullOrWhiteSpace(filters.Query) ? null : filters.Query.Trim() }, cancellationToken);
    }
}
