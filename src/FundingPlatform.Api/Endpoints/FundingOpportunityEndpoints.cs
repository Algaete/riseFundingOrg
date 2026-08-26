using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Contracts.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Api.Endpoints;

public static class FundingOpportunityEndpoints
{
    public static IEndpointRouteBuilder MapFundingOpportunityEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints
            .MapGroup("/api/v1/funding-opportunities")
            .WithTags("Funding opportunities")
            .AllowAnonymous()
            .RequireRateLimiting("marketplace-read");

        group.MapGet("/", SearchAsync)
            .WithName("SearchFundingOpportunities")
            .WithSummary("Searches active, published funding opportunities.")
            .Produces<FundingOpportunityListResponse>()
            .ProducesValidationProblem()
            .ProducesProblem(StatusCodes.Status429TooManyRequests);

        group.MapGet("/{slug}", GetBySlugAsync)
            .WithName("GetFundingOpportunityBySlug")
            .WithSummary("Gets a published funding opportunity and its source traceability.")
            .Produces<FundingOpportunityDetailResponse>()
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status429TooManyRequests);

        return endpoints;
    }

    private static async Task<IResult> SearchAsync(
        string? query,
        int? pageNumber,
        int? pageSize,
        HttpContext context,
        FundingOpportunityCatalogService service,
        CancellationToken cancellationToken)
    {
        var requestedPageNumber = pageNumber ?? 1;
        var requestedPageSize = pageSize ?? 12;

        if (requestedPageNumber < 1 || requestedPageSize is < 1 or > 50)
        {
            return Results.ValidationProblem(new Dictionary<string, string[]>
            {
                ["pagination"] = ["pageNumber must be at least 1 and pageSize must be between 1 and 50."]
            });
        }

        if (query?.Trim().Length > 300)
        {
            return Results.ValidationProblem(new Dictionary<string, string[]>
            {
                ["query"] = ["query must contain at most 300 characters."]
            });
        }

        var page = await service.SearchAsync(
            query,
            requestedPageNumber,
            requestedPageSize,
            cancellationToken);

        context.Response.Headers.CacheControl = "public,max-age=60";
        return Results.Ok(new FundingOpportunityListResponse(
            page.Items.Select(MapListItem).ToArray(),
            page.TotalCount,
            page.PageNumber,
            page.PageSize));
    }

    private static async Task<IResult> GetBySlugAsync(
        string slug,
        HttpContext context,
        FundingOpportunityCatalogService service,
        CancellationToken cancellationToken)
    {
        var opportunity = await service.GetBySlugAsync(slug, cancellationToken);
        if (opportunity is null)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status404NotFound,
                title: "Funding opportunity not found",
                detail: "The requested opportunity is not published or does not exist.");
        }

        context.Response.Headers.CacheControl = "public,max-age=60";
        return Results.Ok(MapDetails(opportunity));
    }

    private static FundingOpportunityListItemResponse MapListItem(
        FundingOpportunitySummary opportunity)
    {
        return new FundingOpportunityListItemResponse(
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
            opportunity.SourceName,
            opportunity.SourceUrl,
            opportunity.PublishedAtUtc,
            opportunity.DataQualityScore);
    }

    private static FundingOpportunityDetailResponse MapDetails(
        FundingOpportunityDetails opportunity)
    {
        return new FundingOpportunityDetailResponse(
            opportunity.PublicId,
            opportunity.Slug,
            opportunity.Title,
            opportunity.Description,
            opportunity.Summary,
            opportunity.SponsorName,
            opportunity.SponsorUrl,
            opportunity.ApplicationUrl,
            opportunity.Currency,
            opportunity.MinimumAmount,
            opportunity.MaximumAmount,
            opportunity.OpenDate,
            opportunity.CloseDate,
            opportunity.EligibilityDescription,
            opportunity.Requirements,
            opportunity.Objectives,
            opportunity.RequiresCofunding,
            opportunity.SourceName,
            opportunity.SourceUrl,
            opportunity.ExternalId,
            opportunity.LastVerifiedAtUtc,
            opportunity.DataQualityScore,
            (opportunity.Funders ?? []).Select(funder =>
                new FundingOpportunityFunderResponse(
                    funder.PublicId,
                    funder.Slug,
                    funder.Name,
                    (byte)funder.Role)).ToArray());
    }
}
