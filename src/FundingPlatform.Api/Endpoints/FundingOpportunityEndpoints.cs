using FundingPlatform.Core.Validation;
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
        string? locale,
        HttpContext context,
        FundingOpportunityCatalogService service,
        FundingTranslationOptions translationOptions,
        CancellationToken cancellationToken)
    {
        var requestedPageNumber = pageNumber ?? 1;
        var requestedPageSize = pageSize ?? 12;
        if (locale is not null && !FundingTranslationRules.Supports(locale)) return Results.BadRequest();

        if (requestedPageNumber < 1 || requestedPageSize is < 1 or > 50)
        {
            return FieldValidationResults.BadRequest(new FieldValidationErrors
            {
                { "pagination", "api-validation-093", "pageNumber must be at least 1 and pageSize must be between 1 and 50." }
            });
        }

        if (query?.Trim().Length > 300)
        {
            return FieldValidationResults.BadRequest(new FieldValidationErrors
            {
                { "query", "api-validation-094", "query must contain at most 300 characters." }
            });
        }

        var page = await service.SearchAsync(
            query,
            requestedPageNumber,
            requestedPageSize,
            cancellationToken,
            includeReviewedTranslations: translationOptions.Enabled);

        // Do not construct SQL translation dependencies for disabled/original reads.
        if (translationOptions.Enabled && locale is not null)
            page = await context.RequestServices.GetRequiredService<FundingTranslationService>().LocalizeAsync(page, locale, cancellationToken);
        context.Response.Headers.CacheControl = locale is null && !translationOptions.Enabled ? "public,max-age=60" : "no-store";
        return Results.Ok(new FundingOpportunityListResponse(
            page.Items.Select(MapListItem).ToArray(),
            page.TotalCount,
            page.PageNumber,
            page.PageSize));
    }

    private static async Task<IResult> GetBySlugAsync(
        string slug,
        string? locale,
        HttpContext context,
        FundingOpportunityCatalogService service,
        FundingTranslationService translations,
        CancellationToken cancellationToken)
    {
        if (locale is not null && !FundingTranslationRules.Supports(locale)) return Results.BadRequest();
        var opportunity = await service.GetBySlugAsync(slug, cancellationToken);
        if (opportunity is null)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status404NotFound,
                title: "Funding opportunity not found",
                detail: "The requested opportunity is not published or does not exist.");
        }

        opportunity = await translations.LocalizeAsync(opportunity, locale, cancellationToken);
        // A new source version or withdrawal of review must not leave an obsolete
        // translation in an HTTP cache. No translation provider runs on this read.
        context.Response.Headers.CacheControl = locale is null ? "public,max-age=60" : "no-store";
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
            opportunity.DataQualityScore, opportunity.CoverKey,
            opportunity.Localization is { } info ? new(info.RequestedLanguage, info.Status, info.Revision) : null);
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
                    (byte)funder.Role)).ToArray(),
            opportunity.ContentVersion,
            opportunity.Localization is { } info ? new FundingLocalizationResponse(info.RequestedLanguage, info.Status, info.Revision) : null,
            opportunity.OtherCategoryDescription, opportunity.CoverKey);
    }
}
