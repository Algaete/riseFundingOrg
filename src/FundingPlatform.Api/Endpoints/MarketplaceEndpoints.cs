using System.Globalization;
using FundingPlatform.Application.Marketplace;
using FundingPlatform.Application.Organizations;
using FundingPlatform.Contracts.Marketplace;
using FundingPlatform.Contracts.Organizations;
using FundingPlatform.Contracts.Projects;
using FundingPlatform.Core.Marketplace;
using FundingPlatform.Core.Organizations;
using FundingPlatform.Core.Projects;
using Microsoft.Extensions.Primitives;

namespace FundingPlatform.Api.Endpoints;

public static class MarketplaceEndpoints
{
    private static readonly IReadOnlyDictionary<string, MarketplaceProjectSort> Sorts =
        new Dictionary<string, MarketplaceProjectSort>(StringComparer.OrdinalIgnoreCase)
        {
            ["newest"] = MarketplaceProjectSort.Newest,
            ["title"] = MarketplaceProjectSort.Title,
            ["funding-gap-desc"] = MarketplaceProjectSort.FundingGapDescending
        };

    public static IEndpointRouteBuilder MapMarketplaceEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        var marketplace = endpoints.MapGroup("/api/v1/marketplace")
            .WithTags("Marketplace")
            .AllowAnonymous()
            .RequireRateLimiting("marketplace-read");

        marketplace.MapGet("/catalogs", GetCatalogsAsync)
            .WithName("GetMarketplaceCatalogs")
            .WithSummary("Gets the allowlisted public catalogs used by marketplace filters.")
            .Produces<MarketplaceCatalogsResponse>()
            .ProducesProblem(StatusCodes.Status429TooManyRequests);
        marketplace.MapGet("/projects", SearchProjectsAsync)
            .WithName("SearchMarketplaceProjects")
            .WithSummary("Searches only currently published projects with server-side filters and paging.")
            .Produces<MarketplaceProjectPageResponse>()
            .ProducesValidationProblem()
            .ProducesProblem(StatusCodes.Status429TooManyRequests);
        marketplace.MapGet("/projects/{slug}", GetProjectAsync)
            .WithName("GetMarketplaceProject")
            .WithSummary("Gets a currently visible public project by slug.")
            .Produces<MarketplaceProjectDetailsResponse>()
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status429TooManyRequests);
        marketplace.MapGet("/organizations/{organizationId:guid}", GetOrganizationAsync)
            .WithName("GetMarketplaceOrganization")
            .WithSummary("Gets a safe public organization profile with its visible projects.")
            .Produces<MarketplaceOrganizationProfileResponse>()
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status429TooManyRequests);

        return endpoints;
    }

    private static async Task<IResult> GetCatalogsAsync(
        HttpContext context,
        OrganizationProfileService service,
        CancellationToken cancellationToken)
    {
        var catalogs = await service.GetCatalogsAsync(cancellationToken);
        SetPublicCache(context);
        return Results.Ok(new MarketplaceCatalogsResponse(
            catalogs.Countries.Select(Map).ToArray(),
            catalogs.Currencies.Select(item => new CurrencyOptionResponse(
                item.Code, item.Name, item.MinorUnits)).ToArray(),
            catalogs.FundingCategories.Select(Map).ToArray(),
            catalogs.ProjectTypes.Select(Map).ToArray()));
    }

    private static async Task<IResult> SearchProjectsAsync(
        HttpContext context,
        MarketplaceService service,
        CancellationToken cancellationToken)
    {
        if (!TryParseFilters(context.Request.Query, out var filters, out var errors))
        {
            return Results.ValidationProblem(errors);
        }

        var result = await service.SearchProjectsAsync(filters!, cancellationToken);
        if (result.Outcome == MarketplaceOutcome.ValidationFailed)
        {
            return Results.ValidationProblem(result.Errors!);
        }

        SetPublicCache(context);
        return Results.Ok(Map(result.Page!));
    }

    private static async Task<IResult> GetProjectAsync(
        string slug,
        HttpContext context,
        MarketplaceService service,
        CancellationToken cancellationToken)
    {
        var result = await service.GetProjectBySlugAsync(slug, cancellationToken);
        if (result.Outcome == MarketplaceOutcome.NotFound)
        {
            return NotFound("Proyecto no encontrado", "marketplace-project-not-found");
        }

        SetPublicCache(context);
        return Results.Ok(Map(result.Project!));
    }

    private static async Task<IResult> GetOrganizationAsync(
        Guid organizationId,
        HttpContext context,
        MarketplaceService service,
        CancellationToken cancellationToken)
    {
        var result = await service.GetOrganizationAsync(organizationId, cancellationToken);
        if (result.Outcome == MarketplaceOutcome.NotFound)
        {
            return NotFound("Organización no encontrada", "marketplace-organization-not-found");
        }

        SetPublicCache(context);
        return Results.Ok(Map(result.Organization!));
    }

    private static bool TryParseFilters(
        IQueryCollection query,
        out MarketplaceProjectFilters? filters,
        out Dictionary<string, string[]> errors)
    {
        filters = null;
        errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        var countries = ParseShortIds(query["countryIds"], "countryIds", errors);
        var categories = ParseIntIds(query["categoryIds"], "categoryIds", errors);
        var projectTypes = ParseIntIds(query["projectTypeIds"], "projectTypeIds", errors);
        var projectStatus = ParseByte(query["projectStatus"], "projectStatus", errors);
        var page = ParseInt(query["page"], "page", 1, errors);
        var pageSize = ParseInt(query["pageSize"], "pageSize", 20, errors);
        var sortCode = query["sort"].ToString();
        var sort = MarketplaceProjectSort.Newest;
        if (!string.IsNullOrWhiteSpace(sortCode) && !Sorts.TryGetValue(sortCode.Trim(), out sort))
        {
            errors["sort"] = ["El orden solicitado no es válido."];
        }

        if (errors.Count > 0)
        {
            return false;
        }

        filters = new MarketplaceProjectFilters(
            query["q"].ToString(),
            countries,
            categories,
            projectTypes,
            projectStatus.HasValue ? (ProjectStatus)projectStatus.Value : null,
            query["currency"].ToString(),
            sort,
            page,
            pageSize);
        return true;
    }

    private static short[] ParseShortIds(
        StringValues values,
        string key,
        IDictionary<string, string[]> errors)
    {
        var tokens = Tokens(values);
        var parsed = new List<short>(tokens.Length);
        if (tokens.Any(token => !short.TryParse(
                token, NumberStyles.None, CultureInfo.InvariantCulture, out var value) ||
                value <= 0))
        {
            errors[key] = ["Usa una lista de identificadores positivos separados por coma."];
            return [];
        }

        foreach (var token in tokens)
        {
            parsed.Add(short.Parse(token, CultureInfo.InvariantCulture));
        }

        return parsed.ToArray();
    }

    private static int[] ParseIntIds(
        StringValues values,
        string key,
        IDictionary<string, string[]> errors)
    {
        var tokens = Tokens(values);
        var parsed = new List<int>(tokens.Length);
        if (tokens.Any(token => !int.TryParse(
                token, NumberStyles.None, CultureInfo.InvariantCulture, out var value) ||
                value <= 0))
        {
            errors[key] = ["Usa una lista de identificadores positivos separados por coma."];
            return [];
        }

        foreach (var token in tokens)
        {
            parsed.Add(int.Parse(token, CultureInfo.InvariantCulture));
        }

        return parsed.ToArray();
    }

    private static string[] Tokens(StringValues values) => values
        .SelectMany(value => (value ?? string.Empty).Split(',', StringSplitOptions.TrimEntries))
        .Where(value => value.Length > 0)
        .ToArray();

    private static byte? ParseByte(
        StringValues value,
        string key,
        IDictionary<string, string[]> errors)
    {
        var raw = value.ToString();
        if (string.IsNullOrWhiteSpace(raw))
        {
            return null;
        }

        if (byte.TryParse(raw, NumberStyles.None, CultureInfo.InvariantCulture, out var parsed))
        {
            return parsed;
        }

        errors[key] = ["El valor no es válido."];
        return null;
    }

    private static int ParseInt(
        StringValues value,
        string key,
        int defaultValue,
        IDictionary<string, string[]> errors)
    {
        var raw = value.ToString();
        if (string.IsNullOrWhiteSpace(raw))
        {
            return defaultValue;
        }

        if (int.TryParse(raw, NumberStyles.None, CultureInfo.InvariantCulture, out var parsed))
        {
            return parsed;
        }

        errors[key] = ["El valor no es válido."];
        return defaultValue;
    }

    private static MarketplaceProjectPageResponse Map(MarketplaceProjectPage page) =>
        new(page.Items.Select(Map).ToArray(), page.TotalCount, page.PageNumber, page.PageSize);

    private static MarketplaceProjectSummaryResponse Map(MarketplaceProjectSummary project) =>
        new(
            project.PublicId,
            project.Slug,
            project.Title,
            project.Summary,
            (byte)project.Status,
            project.StartDate,
            project.EndDate,
            project.BudgetTotal,
            project.ConfirmedFunding,
            project.Currency,
            project.FundingGap,
            project.PublishedAtUtc,
            new MarketplaceProjectOrganizationResponse(
                project.Organization.PublicId,
                project.Organization.Name,
                project.Organization.WebsiteUrl));

    private static MarketplaceProjectDetailsResponse Map(PublicProjectDetails project) =>
        new(
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
            new MarketplaceProjectOrganizationResponse(
                project.Organization.PublicId,
                project.Organization.Name,
                project.Organization.WebsiteUrl),
            project.Countries.Select(Map).ToArray(),
            project.Regions.Select(Map).ToArray(),
            project.Categories.Select(Map).ToArray(),
            project.BeneficiaryTypes.Select(Map).ToArray(),
            project.ProjectTypes.Select(Map).ToArray());

    private static MarketplaceOrganizationProfileResponse Map(
        MarketplaceOrganizationProfile organization) =>
        new(
            organization.PublicId,
            organization.Name,
            organization.Description,
            organization.WebsiteUrl,
            organization.EstablishedYear,
            Map(organization.HomeCountry),
            Map(organization.OrganizationType),
            organization.OrganizationSize is null ? null : Map(organization.OrganizationSize),
            organization.Countries.Select(Map).ToArray(),
            organization.Regions.Select(item => new RegionOptionResponse(
                item.Id, item.CountryId, item.Code, item.Name)).ToArray(),
            organization.Categories.Select(Map).ToArray(),
            organization.BeneficiaryTypes.Select(Map).ToArray(),
            organization.ProjectTypes.Select(Map).ToArray(),
            organization.Projects.Select(Map).ToArray());

    private static CatalogOptionResponse<T> Map<T>(CatalogOption<T> item) =>
        new(item.Id, item.Code, item.Name);

    private static CatalogOptionResponse<T> Map<T>(PublicOrganizationCatalogItem<T> item) =>
        new(item.Id, item.Code, item.Name);

    private static PublicProjectTaxonomyResponse Map(PublicProjectTaxonomyItem item) =>
        new(item.Id, item.Code, item.Name);

    private static PublicProjectRegionResponse Map(PublicProjectRegion item) =>
        new(item.Id, item.CountryId, item.Code, item.Name);

    private static void SetPublicCache(HttpContext context) =>
        context.Response.Headers.CacheControl = "public,max-age=60";

    private static IResult NotFound(string title, string code) => Results.Problem(
        statusCode: StatusCodes.Status404NotFound,
        title: title,
        type: $"https://fundingplatform.local/problems/{code}");
}
