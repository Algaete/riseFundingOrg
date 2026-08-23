using FundingPlatform.Application.Projects;
using FundingPlatform.Contracts.Projects;
using FundingPlatform.Core.Projects;

namespace FundingPlatform.Api.Endpoints;

public static class PublicProjectEndpoints
{
    public static IEndpointRouteBuilder MapPublicProjectEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/v1/projects/{slug}", GetBySlugAsync)
            .WithTags("Public Projects")
            .AllowAnonymous()
            .Produces<PublicProjectResponse>()
            .ProducesProblem(StatusCodes.Status404NotFound);
        return endpoints;
    }

    private static async Task<IResult> GetBySlugAsync(
        string slug,
        HttpContext context,
        ProjectWorkflowService service,
        CancellationToken cancellationToken)
    {
        var project = await service.GetPublishedBySlugAsync(slug, cancellationToken);
        if (project is null)
            return ProjectEndpointResults.Problem(404, "Proyecto no encontrado", null,
                "published-project-not-found");

        context.Response.Headers.CacheControl = "public,max-age=60";
        return Results.Ok(Map(project));
    }

    private static PublicProjectResponse Map(PublicProjectDetails project) => new(
        project.PublicId,
        project.Slug,
        project.Title,
        project.Summary,
        project.Description,
        (byte)project.Status,
        project.StartDate,
        project.EndDate,
        project.BudgetTotal,
        project.ConfirmedFunding,
        project.Currency,
        project.FundingGap,
        project.PublishedAtUtc,
        new PublicProjectOrganizationResponse(
            project.Organization.PublicId,
            project.Organization.Name,
            project.Organization.WebsiteUrl),
        project.Countries.Select(Map).ToArray(),
        project.Regions.Select(Map).ToArray(),
        project.Categories.Select(Map).ToArray(),
        project.BeneficiaryTypes.Select(Map).ToArray(),
        project.ProjectTypes.Select(Map).ToArray());

    private static PublicProjectTaxonomyResponse Map(PublicProjectTaxonomyItem item) =>
        new(item.Id, item.Code, item.Name);

    private static PublicProjectRegionResponse Map(PublicProjectRegion item) =>
        new(item.Id, item.CountryId, item.Code, item.Name);
}
