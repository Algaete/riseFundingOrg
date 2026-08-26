using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Contracts.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Api.Endpoints;

public static class FunderEndpoints
{
    public static IEndpointRouteBuilder MapFunderEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/funders")
            .WithTags("Funders")
            .AllowAnonymous()
            .RequireRateLimiting("marketplace-read");

        group.MapGet("/", ListAsync)
            .Produces<PublicFunderListResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status429TooManyRequests);
        group.MapGet("/{slug}", GetBySlugAsync)
            .Produces<PublicFunderDetailResponse>()
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status429TooManyRequests);
        return endpoints;
    }

    private static async Task<IResult> ListAsync(
        HttpContext context,
        FunderEditorialService service,
        CancellationToken cancellationToken,
        string? query = null,
        int page = 1,
        int pageSize = 12)
    {
        if (page < 1 || pageSize is < 1 or > 50)
        {
            return ProjectEndpointResults.Validation(
                422, "Paginación inválida", "invalid-pagination",
                new Dictionary<string, string[]>
                {
                    [page < 1 ? "page" : "pageSize"] =
                        [page < 1
                            ? "page debe ser al menos 1."
                            : "pageSize debe estar entre 1 y 50."]
                });
        }

        if (query?.Trim().Length > 300)
        {
            return ProjectEndpointResults.Validation(
                422, "Búsqueda inválida", "invalid-query",
                new Dictionary<string, string[]>
                {
                    ["query"] = ["query admite hasta 300 caracteres."]
                });
        }

        var result = await service.ListPublishedAsync(query, page, pageSize, cancellationToken);
        context.Response.Headers.CacheControl = "public,max-age=60";
        return Results.Ok(new PublicFunderListResponse(
            result.Items.Select(Map).ToArray(),
            result.TotalCount,
            result.PageNumber,
            result.PageSize));
    }

    private static async Task<IResult> GetBySlugAsync(
        string slug,
        HttpContext context,
        FunderEditorialService service,
        CancellationToken cancellationToken)
    {
        var result = await service.GetPublishedBySlugAsync(slug, cancellationToken);
        if (result is null)
        {
            return ProjectEndpointResults.Problem(
                404, "Funder no encontrado",
                "El funder no está publicado o no existe.", "funder-not-found");
        }

        context.Response.Headers.CacheControl = "public,max-age=60";
        return Results.Ok(Map(result));
    }

    private static PublicFunderSummaryResponse Map(PublicFunderSummary funder) => new(
        funder.PublicId,
        funder.Slug,
        funder.Name,
        funder.Description,
        funder.WebsiteUrl,
        funder.CountryCode,
        funder.CountryName);

    private static PublicFunderDetailResponse Map(PublicFunderDetails funder) => new(
        funder.PublicId,
        funder.Slug,
        funder.Name,
        funder.Description,
        funder.WebsiteUrl,
        funder.CountryCode,
        funder.CountryName,
        funder.Aliases,
        funder.PublishedAtUtc,
        funder.Opportunities.Select(opportunity => new PublicFunderOpportunityResponse(
            opportunity.PublicId,
            opportunity.Slug,
            opportunity.Title,
            opportunity.Summary,
            opportunity.SponsorName,
            opportunity.Currency,
            opportunity.MinimumAmount,
            opportunity.MaximumAmount,
            opportunity.OpenDate,
            opportunity.CloseDate,
            opportunity.PublishedAtUtc)).ToArray());
}
