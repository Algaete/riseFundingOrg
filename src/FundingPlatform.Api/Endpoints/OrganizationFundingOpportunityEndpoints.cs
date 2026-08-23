using System.Globalization;
using System.Security.Claims;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Contracts.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using Microsoft.Extensions.Primitives;

namespace FundingPlatform.Api.Endpoints;

public static class OrganizationFundingOpportunityEndpoints
{
    private static readonly IReadOnlyDictionary<string, FundingOpportunitySearchSort> Sorts =
        new Dictionary<string, FundingOpportunitySearchSort>(StringComparer.OrdinalIgnoreCase)
        {
            ["relevance"] = FundingOpportunitySearchSort.Relevance,
            ["closing-soon"] = FundingOpportunitySearchSort.ClosingSoon,
            ["newest"] = FundingOpportunitySearchSort.Newest,
            ["amount-asc"] = FundingOpportunitySearchSort.AmountAscending,
            ["amount-desc"] = FundingOpportunitySearchSort.AmountDescending
        };

    public static IEndpointRouteBuilder MapOrganizationFundingOpportunityEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        var organization = endpoints
            .MapGroup("/api/v1/organizations/{organizationId:guid}")
            .WithTags("Organization funding opportunities")
            .RequireAuthorization("full-session");

        organization.MapGet("/funding-opportunities", SearchAsync)
            .RequireRateLimiting("organization-funding-read")
            .WithName("SearchOrganizationFundingOpportunities")
            .WithSummary("Searches published opportunities in an authorized organization context.")
            .Produces<WorkspaceFundingOpportunityListResponse>()
            .ProducesValidationProblem()
            .Produces(StatusCodes.Status429TooManyRequests)
            .ProducesProblem(StatusCodes.Status404NotFound);

        organization.MapGet("/funding-opportunities/{idOrSlug}", GetAsync)
            .RequireRateLimiting("organization-funding-read")
            .WithName("GetOrganizationFundingOpportunity")
            .WithSummary("Gets the complete published opportunity in an authorized organization context.")
            .Produces<WorkspaceFundingOpportunityDetailResponse>()
            .Produces(StatusCodes.Status429TooManyRequests)
            .ProducesProblem(StatusCodes.Status404NotFound);

        organization.MapGet("/favorites", ListFavoritesAsync)
            .RequireRateLimiting("organization-funding-read")
            .WithName("ListOrganizationFundingFavorites")
            .Produces<WorkspaceFundingOpportunityListResponse>()
            .ProducesValidationProblem()
            .Produces(StatusCodes.Status429TooManyRequests)
            .ProducesProblem(StatusCodes.Status404NotFound);

        organization.MapPut("/favorites/{fundingOpportunityId:guid}", PutFavoriteAsync)
            .RequireRateLimiting("organization-write")
            .WithName("PutOrganizationFundingFavorite")
            .WithSummary("Idempotently saves a published opportunity for the current user.")
            .Produces(StatusCodes.Status204NoContent)
            .Produces(StatusCodes.Status429TooManyRequests)
            .ProducesProblem(StatusCodes.Status404NotFound);

        organization.MapDelete("/favorites/{fundingOpportunityId:guid}", DeleteFavoriteAsync)
            .RequireRateLimiting("organization-write")
            .WithName("DeleteOrganizationFundingFavorite")
            .WithSummary("Idempotently removes a saved opportunity for the current user.")
            .Produces(StatusCodes.Status204NoContent)
            .Produces(StatusCodes.Status429TooManyRequests)
            .ProducesProblem(StatusCodes.Status404NotFound);

        return endpoints;
    }

    private static async Task<IResult> SearchAsync(
        Guid organizationId,
        ClaimsPrincipal principal,
        HttpRequest request,
        FundingOpportunityWorkspaceService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId))
        {
            return InvalidSession();
        }

        if (!TryParseFilters(request.Query, out var filters, out var parseErrors))
        {
            return Results.ValidationProblem(parseErrors);
        }

        var result = await service.SearchAsync(
            userId,
            organizationId,
            filters!,
            cancellationToken);
        return result.Outcome switch
        {
            FundingOpportunityWorkspaceSearchOutcome.Success => Results.Ok(MapPage(result.Page!)),
            FundingOpportunityWorkspaceSearchOutcome.ValidationFailed =>
                Results.ValidationProblem(result.Errors!),
            _ => NotFound()
        };
    }

    private static async Task<IResult> GetAsync(
        Guid organizationId,
        string idOrSlug,
        ClaimsPrincipal principal,
        FundingOpportunityWorkspaceService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId))
        {
            return InvalidSession();
        }

        var opportunity = await service.GetAsync(
            userId,
            organizationId,
            idOrSlug,
            cancellationToken);
        return opportunity is null ? NotFound() : Results.Ok(MapDetails(opportunity));
    }

    private static async Task<IResult> ListFavoritesAsync(
        Guid organizationId,
        ClaimsPrincipal principal,
        HttpRequest request,
        FundingOpportunityWorkspaceService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId))
        {
            return InvalidSession();
        }

        var errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        var pageNumber = ParseInt(request.Query, "page", 1, errors);
        var pageSize = ParseInt(request.Query, "pageSize", 20, errors);
        if (errors.Count > 0)
        {
            return Results.ValidationProblem(errors);
        }

        var result = await service.ListFavoritesAsync(
            userId,
            organizationId,
            pageNumber,
            pageSize,
            cancellationToken);
        return result.Outcome switch
        {
            FundingOpportunityWorkspaceSearchOutcome.Success => Results.Ok(MapPage(result.Page!)),
            FundingOpportunityWorkspaceSearchOutcome.ValidationFailed =>
                Results.ValidationProblem(result.Errors!),
            _ => NotFound()
        };
    }

    private static Task<IResult> PutFavoriteAsync(
        Guid organizationId,
        Guid fundingOpportunityId,
        ClaimsPrincipal principal,
        FundingOpportunityWorkspaceService service,
        CancellationToken cancellationToken) =>
        MutateFavoriteAsync(
            organizationId,
            fundingOpportunityId,
            principal,
            service,
            static (favoriteService, userId, tenantId, opportunityId, token) =>
                favoriteService.PutFavoriteAsync(
                    userId, tenantId, opportunityId, token),
            cancellationToken);

    private static Task<IResult> DeleteFavoriteAsync(
        Guid organizationId,
        Guid fundingOpportunityId,
        ClaimsPrincipal principal,
        FundingOpportunityWorkspaceService service,
        CancellationToken cancellationToken) =>
        MutateFavoriteAsync(
            organizationId,
            fundingOpportunityId,
            principal,
            service,
            static (favoriteService, userId, tenantId, opportunityId, token) =>
                favoriteService.DeleteFavoriteAsync(
                    userId, tenantId, opportunityId, token),
            cancellationToken);

    private static async Task<IResult> MutateFavoriteAsync(
        Guid organizationId,
        Guid fundingOpportunityId,
        ClaimsPrincipal principal,
        FundingOpportunityWorkspaceService service,
        Func<FundingOpportunityWorkspaceService, Guid, Guid, Guid, CancellationToken,
            Task<FundingFavoriteMutation>> mutation,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId))
        {
            return InvalidSession();
        }

        var result = await mutation(
            service,
            userId,
            organizationId,
            fundingOpportunityId,
            cancellationToken);
        return result.Outcome == FundingFavoriteMutationOutcome.NotFound
            ? NotFound()
            : Results.NoContent();
    }

    private static bool TryParseFilters(
        IQueryCollection query,
        out FundingOpportunitySearchFilters? filters,
        out Dictionary<string, string[]> errors)
    {
        errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        var searchText = Single(query, "q", errors);
        var sponsor = Single(query, "sponsor", errors);
        var currency = Single(query, "currency", errors);
        var sortText = Single(query, "sort", errors);
        var minimumAmount = ParseDecimal(query, "minAmount", errors);
        var maximumAmount = ParseDecimal(query, "maxAmount", errors);
        var closingFrom = ParseDate(query, "closingFrom", errors);
        var closingTo = ParseDate(query, "closingTo", errors);
        var onlyOpen = ParseBool(query, "onlyOpen", false, errors);
        var pageNumber = ParseInt(query, "page", 1, errors);
        var pageSize = ParseInt(query, "pageSize", 20, errors);

        FundingOpportunitySearchSort sort;
        if (string.IsNullOrWhiteSpace(sortText))
        {
            sort = string.IsNullOrWhiteSpace(searchText)
                ? FundingOpportunitySearchSort.ClosingSoon
                : FundingOpportunitySearchSort.Relevance;
        }
        else if (!Sorts.TryGetValue(sortText.Trim(), out sort))
        {
            errors["sort"] =
                ["Usa relevance, closing-soon, newest, amount-asc o amount-desc."];
        }

        var countryIds = ParseIds<short>(query, "countryIds", short.TryParse, errors);
        var regionIds = ParseIds<int>(query, "regionIds", int.TryParse, errors);
        var categoryIds = ParseIds<int>(query, "categoryIds", int.TryParse, errors);
        var tagIds = ParseIds<long>(query, "tagIds", long.TryParse, errors);
        var beneficiaryIds = ParseIds<int>(
            query, "beneficiaryTypeIds", int.TryParse, errors);
        var projectTypeIds = ParseIds<int>(
            query, "projectTypeIds", int.TryParse, errors);
        var fundingTypeIds = ParseIds<short>(
            query, "fundingTypeIds", short.TryParse, errors);
        var organizationTypeIds = ParseIds<short>(
            query, "organizationTypeIds", short.TryParse, errors);
        var funderIds = ParseIds<Guid>(query, "funderIds", Guid.TryParse, errors);

        if (errors.Count > 0)
        {
            filters = null;
            return false;
        }

        filters = new FundingOpportunitySearchFilters(
            searchText,
            sponsor,
            minimumAmount,
            maximumAmount,
            currency,
            closingFrom,
            closingTo,
            onlyOpen,
            sort,
            pageNumber,
            pageSize,
            countryIds,
            regionIds,
            categoryIds,
            tagIds,
            beneficiaryIds,
            projectTypeIds,
            fundingTypeIds,
            organizationTypeIds,
            funderIds);
        return true;
    }

    private static string? Single(
        IQueryCollection query,
        string key,
        IDictionary<string, string[]> errors)
    {
        if (!query.TryGetValue(key, out var values) || values.Count == 0)
        {
            return null;
        }

        if (values.Count != 1)
        {
            errors[key] = ["Envía este parámetro una sola vez."];
            return null;
        }

        return values[0];
    }

    private static int ParseInt(
        IQueryCollection query,
        string key,
        int defaultValue,
        IDictionary<string, string[]> errors)
    {
        var raw = Single(query, key, errors);
        if (raw is null)
        {
            return defaultValue;
        }

        if (int.TryParse(raw, NumberStyles.None, CultureInfo.InvariantCulture, out var parsed))
        {
            return parsed;
        }

        errors[key] = ["Debe ser un número entero válido."];
        return defaultValue;
    }

    private static decimal? ParseDecimal(
        IQueryCollection query,
        string key,
        IDictionary<string, string[]> errors)
    {
        var raw = Single(query, key, errors);
        if (raw is null)
        {
            return null;
        }

        if (decimal.TryParse(
                raw,
                NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint,
                CultureInfo.InvariantCulture,
                out var parsed))
        {
            return parsed;
        }

        errors[key] = ["Debe ser un monto válido usando punto decimal."];
        return null;
    }

    private static DateOnly? ParseDate(
        IQueryCollection query,
        string key,
        IDictionary<string, string[]> errors)
    {
        var raw = Single(query, key, errors);
        if (raw is null)
        {
            return null;
        }

        if (DateOnly.TryParseExact(raw, "yyyy-MM-dd", CultureInfo.InvariantCulture,
                DateTimeStyles.None, out var parsed))
        {
            return parsed;
        }

        errors[key] = ["Usa el formato de fecha AAAA-MM-DD."];
        return null;
    }

    private static bool ParseBool(
        IQueryCollection query,
        string key,
        bool defaultValue,
        IDictionary<string, string[]> errors)
    {
        var raw = Single(query, key, errors);
        if (raw is null)
        {
            return defaultValue;
        }

        if (bool.TryParse(raw, out var parsed))
        {
            return parsed;
        }

        errors[key] = ["Debe ser true o false."];
        return defaultValue;
    }

    private delegate bool TryParseValue<T>(string value, out T result);

    private static IReadOnlyList<T> ParseIds<T>(
        IQueryCollection query,
        string key,
        TryParseValue<T> parser,
        IDictionary<string, string[]> errors)
    {
        if (!query.TryGetValue(key, out StringValues values) || values.Count == 0)
        {
            return [];
        }

        var rawValues = values.SelectMany(value =>
            (value ?? string.Empty).Split(',', StringSplitOptions.TrimEntries));
        var parsed = new List<T>();
        foreach (var raw in rawValues)
        {
            if (raw.Length == 0 || !parser(raw, out var value))
            {
                errors[key] = ["Contiene uno o más identificadores inválidos."];
                return [];
            }

            parsed.Add(value);
            if (parsed.Count > 50)
            {
                errors[key] = ["Admite hasta 50 identificadores."];
                return [];
            }
        }

        return parsed;
    }

    private static WorkspaceFundingOpportunityListResponse MapPage(
        WorkspaceFundingOpportunityPage page) => new(
        page.Items.Select(MapListItem).ToArray(),
        page.TotalCount,
        page.PageNumber,
        page.PageSize,
        page.SearchMode);

    private static WorkspaceFundingOpportunityListItemResponse MapListItem(
        WorkspaceFundingOpportunitySummary item) => new(
        item.PublicId,
        item.Slug,
        item.Title,
        item.Summary,
        item.SponsorName,
        item.Currency,
        item.MinimumAmount,
        item.MaximumAmount,
        item.OpenDate,
        item.CloseDate,
        item.CloseAtUtc,
        (byte)item.DeadlineType,
        (byte)item.DeadlinePrecision,
        item.PublishedAtUtc,
        item.DataQualityScore,
        item.PrimaryFunderPublicId,
        item.PrimaryFunderName,
        item.SourceName,
        item.SourceUrl,
        item.IsFavorite);

    private static WorkspaceFundingOpportunityDetailResponse MapDetails(
        WorkspaceFundingOpportunityDetails item) => new(
        item.PublicId,
        item.Slug,
        item.Title,
        item.Description,
        item.Summary,
        item.SponsorName,
        item.SponsorUrl,
        item.ApplicationUrl,
        item.IssuerCountryId,
        item.FundingTypeId,
        item.Currency,
        item.MinimumAmount,
        item.MaximumAmount,
        (byte)item.AmountStatus,
        item.OpenDate,
        item.CloseDate,
        item.CloseAtUtc,
        item.DeadlineTimeZoneId,
        (byte)item.DeadlineType,
        (byte)item.DeadlinePrecision,
        item.EligibilityDescription,
        item.Requirements,
        item.Objectives,
        item.AllowedActivities,
        item.ExcludedActivities,
        item.Restrictions,
        item.TargetOrganizationsDescription,
        item.TargetPopulationsDescription,
        item.MinimumOperatingYears,
        item.RequiresLegalEntity,
        item.RequiresPriorExperience,
        item.RequiresCofunding,
        item.CofundingPercentage,
        (byte)item.GeographicScope,
        (byte)item.RemoteApplication,
        item.LastVerifiedAtUtc,
        item.DataQualityScore,
        item.ContentVersion,
        item.PublishedAtUtc,
        item.PrimaryFunderPublicId,
        item.PrimaryFunderSlug,
        item.PrimaryFunderName,
        item.SourceName,
        item.SourceUrl,
        item.ExternalId,
        item.IsFavorite,
        item.CountryIds,
        item.RegionIds,
        item.CategoryIds,
        item.BeneficiaryTypeIds,
        item.ProjectTypeIds,
        item.TagIds,
        item.OrganizationTypes.Select(value =>
            new FundingOpportunityEligibilityTypeResponse(
                value.Id, value.EligibilityMode)).ToArray(),
        item.LegalEntityTypes.Select(value =>
            new FundingOpportunityEligibilityTypeResponse(
                value.Id, value.EligibilityMode)).ToArray(),
        item.Languages.Select(value => new FundingOpportunityLanguageResponse(
            value.Id, value.LanguagePurpose)).ToArray(),
        item.Funders.Select(value => new FundingOpportunityFunderResponse(
            value.PublicId, value.Slug, value.Name, (byte)value.Role)).ToArray(),
        item.Sources.Select(value => new WorkspaceFundingOpportunitySourceResponse(
            value.FundingSourceId,
            value.SourceName,
            value.ExternalId,
            value.SourceUrl,
            value.FirstSeenAtUtc,
            value.LastSeenAtUtc,
            value.IsPrimary,
            value.IsActive)).ToArray());

    private static bool TryGetUserId(ClaimsPrincipal principal, out Guid id) =>
        Guid.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out id);

    private static IResult NotFound() => Problem(
        StatusCodes.Status404NotFound,
        "Contenido no encontrado",
        "No existe, no está publicado o no tienes acceso a esta organización.",
        "organization-funding-not-found");

    private static IResult InvalidSession() => Problem(
        StatusCodes.Status401Unauthorized,
        "Sesión inválida",
        "Inicia sesión nuevamente.",
        "invalid-session");

    private static IResult Problem(int status, string title, string detail, string code) =>
        Results.Problem(
            statusCode: status,
            title: title,
            detail: detail,
            type: $"https://fundingplatform.local/problems/{code}");
}
