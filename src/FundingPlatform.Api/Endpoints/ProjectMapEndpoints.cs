using FundingPlatform.Application.Marketplace;
using FundingPlatform.Core.Marketplace;
using Microsoft.AspNetCore.Mvc;

namespace FundingPlatform.Api.Endpoints;

public static class ProjectMapEndpoints
{
    public static IEndpointRouteBuilder MapProjectMapEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/v1/marketplace/project-map", SearchAsync)
            .AllowAnonymous().RequireRateLimiting("marketplace-read").WithTags("Project Map")
            .Produces<ProjectMapPage>().ProducesValidationProblem();
        return endpoints;
    }

    private static async Task<IResult> SearchAsync(HttpContext context, ProjectMapService service,
        CancellationToken cancellationToken, string? q = null, short? countryId = null,
        int? categoryId = null, byte? projectStage = null, int? sustainableDevelopmentGoalId = null,
        byte? projectStatus = null, int page = 1, int pageSize = 100,
        short? organizationTypeId = null, decimal? minimumFundingGap = null,
        decimal? maximumFundingGap = null, string? currency = null,
        bool seekingFunding = false, bool seekingPartners = false,
        bool seekingProfessionals = false, bool seekingConsortium = false,
        [FromQuery] Guid[]? projectIds = null)
    {
        var filters = new ProjectMapFilters(q, countryId, categoryId, projectStage,
            sustainableDevelopmentGoalId, projectStatus, page, pageSize,
            organizationTypeId, minimumFundingGap, maximumFundingGap, currency,
            seekingFunding, seekingPartners, seekingProfessionals, seekingConsortium,
            projectIds is { Length: > 0 } ? projectIds : null);
        var errors = ProjectMapService.Validate(filters);
        if (errors.Count > 0) return FieldValidationResults.BadRequest(errors);
        var result = await service.SearchAsync(filters, cancellationToken);
        context.Response.Headers.CacheControl = "public,max-age=60";
        return Results.Ok(result with { Items = result.Items.Select(point => point with
        {
            Latitude = decimal.Round(point.Latitude, 2, MidpointRounding.AwayFromZero),
            Longitude = decimal.Round(point.Longitude, 2, MidpointRounding.AwayFromZero)
        }).ToArray() });
    }
}
