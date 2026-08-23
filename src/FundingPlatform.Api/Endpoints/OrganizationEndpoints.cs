using System.Security.Claims;
using FundingPlatform.Application.Organizations;
using FundingPlatform.Contracts.Organizations;
using FundingPlatform.Core.Organizations;

namespace FundingPlatform.Api.Endpoints;

public static class OrganizationEndpoints
{
    public static IEndpointRouteBuilder MapOrganizationEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/v1/catalogs", GetCatalogsAsync)
            .WithTags("Catalogs")
            .RequireAuthorization("full-session")
            .Produces<OrganizationCatalogsResponse>();

        var group = endpoints.MapGroup("/api/v1/organizations")
            .WithTags("Organizations")
            .RequireAuthorization("full-session");

        group.MapGet("/", ListAsync).Produces<IReadOnlyList<OrganizationSummaryResponse>>();
        group.MapPost("/", CreateAsync)
            .RequireRateLimiting("organization-write")
            .Produces<OrganizationCreatedResponse>(StatusCodes.Status201Created)
            .ProducesValidationProblem()
            .ProducesProblem(StatusCodes.Status409Conflict);
        group.MapGet("/{organizationId:guid}/profile", GetProfileAsync)
            .Produces<OrganizationProfileResponse>()
            .ProducesProblem(StatusCodes.Status404NotFound);
        group.MapGet("/{organizationId:guid}/profile-completeness", GetCompletenessAsync)
            .Produces<ProfileCompletenessResponse>()
            .ProducesProblem(StatusCodes.Status404NotFound);
        group.MapPut("/{organizationId:guid}/profile", UpdateProfileAsync)
            .RequireRateLimiting("organization-write")
            .Produces<OrganizationProfileResponse>()
            .ProducesValidationProblem()
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);

        return endpoints;
    }

    private static async Task<IResult> GetCatalogsAsync(
        OrganizationProfileService service,
        CancellationToken cancellationToken)
    {
        var catalogs = await service.GetCatalogsAsync(cancellationToken);
        return Results.Ok(MapCatalogs(catalogs));
    }

    private static async Task<IResult> ListAsync(
        ClaimsPrincipal principal,
        OrganizationProfileService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetPublicUserId(principal, out var userId)) return InvalidSession();
        var organizations = await service.ListAsync(userId, cancellationToken);
        return Results.Ok(organizations.Select(item => new OrganizationSummaryResponse(
            item.PublicId, item.Name, RoleName(item.MembershipRole), item.ProfileStatus,
            item.ProfileCompleteness, item.ProfileVersion, item.UpdatedAtUtc)).ToArray());
    }

    private static async Task<IResult> CreateAsync(
        CreateOrganizationRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        OrganizationProfileService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetPublicUserId(principal, out var userId)) return InvalidSession();
        var result = await service.CreateAsync(
            userId, request.Name, request.HomeCountryId, request.OrganizationTypeId, cancellationToken);
        if (result.Outcome == OrganizationWriteOutcome.ValidationFailed)
            return Results.ValidationProblem(result.Errors!);
        if (result.Outcome == OrganizationWriteOutcome.OwnedLimitReached)
            return Problem(StatusCodes.Status409Conflict, "Límite alcanzado",
                "El MVP permite una organización propia por usuario.", "organization-owned-limit");
        if (result.Organization is null) return Problem(500, "No fue posible crear la organización", null, "organization-create-failed");

        var response = MapCreated(result.Organization);
        context.Response.Headers.ETag = response.ETag;
        return Results.Created($"/api/v1/organizations/{response.PublicId:D}/profile", response);
    }

    private static async Task<IResult> GetProfileAsync(
        Guid organizationId,
        ClaimsPrincipal principal,
        HttpContext context,
        OrganizationProfileService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetPublicUserId(principal, out var userId)) return InvalidSession();
        var profile = await service.GetAsync(userId, organizationId, cancellationToken);
        if (profile is null) return NotFound();
        var response = MapProfile(profile);
        context.Response.Headers.ETag = response.ETag;
        return Results.Ok(response);
    }

    private static async Task<IResult> GetCompletenessAsync(
        Guid organizationId,
        ClaimsPrincipal principal,
        OrganizationProfileService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetPublicUserId(principal, out var userId)) return InvalidSession();
        var profile = await service.GetAsync(userId, organizationId, cancellationToken);
        return profile is null
            ? NotFound()
            : Results.Ok(new ProfileCompletenessResponse(
                profile.ProfileCompleteness, profile.ProfileStatus, profile.ProfileVersion));
    }

    private static async Task<IResult> UpdateProfileAsync(
        Guid organizationId,
        UpdateOrganizationProfileRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        OrganizationProfileService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetPublicUserId(principal, out var userId)) return InvalidSession();
        if (!TryParseETag(context.Request.Headers.IfMatch, out var rowVersion))
            return Problem(StatusCodes.Status428PreconditionRequired, "Versión requerida",
                "Vuelve a cargar el perfil e intenta nuevamente.", "if-match-required");
        if (request.CountryIds is null || request.RegionIds is null || request.CategoryIds is null ||
            request.BeneficiaryTypeIds is null || request.ProjectTypeIds is null ||
            request.TagIds is null || request.Languages is null)
            return Results.ValidationProblem(new Dictionary<string, string[]>
            {
                ["collections"] = ["Todas las colecciones del perfil deben enviarse."]
            });

        var profile = new OrganizationProfileData(
            request.Name, request.LegalName, request.TaxIdentifier, request.HomeCountryId,
            request.OrganizationTypeId, request.LegalEntityTypeId, request.OrganizationSizeId,
            request.EstablishedYear, request.WebsiteUrl, request.Description,
            request.PreviousFundingExperience, request.ExperienceSummary,
            request.AnnualBudgetMin, request.AnnualBudgetMax, request.AnnualBudgetCurrency,
            request.DesiredFundingMin, request.DesiredFundingMax, request.DesiredFundingCurrency,
            request.CountryIds, request.RegionIds, request.CategoryIds,
            request.BeneficiaryTypeIds, request.ProjectTypeIds, request.TagIds,
            request.Languages.Select(language =>
                new OrganizationLanguage(language.LanguageId, language.Proficiency)).ToArray());
        var result = await service.UpdateAsync(
            userId, organizationId, rowVersion, profile, cancellationToken);

        if (result.Outcome == OrganizationWriteOutcome.ValidationFailed)
            return Results.ValidationProblem(result.Errors!);
        if (result.Outcome == OrganizationWriteOutcome.Conflict)
            return Problem(StatusCodes.Status409Conflict, "El perfil cambió",
                "Otra sesión guardó una versión más reciente. Recarga antes de continuar.", "organization-concurrency-conflict");
        if (result.Outcome is OrganizationWriteOutcome.NotFound or OrganizationWriteOutcome.Forbidden)
            return NotFound();

        var updated = await service.GetAsync(userId, organizationId, cancellationToken);
        if (updated is null) return NotFound();
        var response = MapProfile(updated);
        context.Response.Headers.ETag = response.ETag;
        return Results.Ok(response);
    }

    private static OrganizationCatalogsResponse MapCatalogs(OrganizationCatalogs catalogs) => new(
        catalogs.Countries.Select(Map).ToArray(),
        catalogs.Regions.Select(item => new RegionOptionResponse(item.Id, item.CountryId, item.Code, item.Name)).ToArray(),
        catalogs.Currencies.Select(item => new CurrencyOptionResponse(item.Code, item.Name, item.MinorUnits)).ToArray(),
        catalogs.FundingCategories.Select(Map).ToArray(),
        catalogs.FundingTypes.Select(Map).ToArray(),
        catalogs.OrganizationTypes.Select(Map).ToArray(),
        catalogs.LegalEntityTypes.Select(item => new LegalEntityTypeOptionResponse(item.Id, item.CountryId, item.Code, item.Name)).ToArray(),
        catalogs.OrganizationSizes.Select(Map).ToArray(),
        catalogs.BeneficiaryTypes.Select(Map).ToArray(),
        catalogs.ProjectTypes.Select(Map).ToArray(),
        catalogs.Tags.Select(Map).ToArray(),
        catalogs.Languages.Select(Map).ToArray());

    private static CatalogOptionResponse<T> Map<T>(CatalogOption<T> item) => new(item.Id, item.Code, item.Name);

    private static OrganizationCreatedResponse MapCreated(PersistedOrganization organization) =>
        new(organization.PublicId, organization.ProfileVersion, FormatETag(organization.RowVersion));

    private static OrganizationProfileResponse MapProfile(OrganizationProfile profile) => new(
        profile.PublicId, profile.Name, profile.LegalName, profile.TaxIdentifier,
        profile.HomeCountryId, profile.OrganizationTypeId, profile.LegalEntityTypeId,
        profile.OrganizationSizeId, profile.EstablishedYear, profile.WebsiteUrl,
        profile.Description, profile.PreviousFundingExperience, profile.ExperienceSummary,
        profile.AnnualBudgetMin, profile.AnnualBudgetMax, profile.AnnualBudgetCurrency,
        profile.DesiredFundingMin, profile.DesiredFundingMax, profile.DesiredFundingCurrency,
        profile.ProfileStatus, profile.ProfileCompleteness, profile.ProfileVersion,
        RoleName(profile.MembershipRole), profile.MembershipRole == 1,
        FormatETag(profile.RowVersion), profile.CountryIds, profile.RegionIds,
        profile.CategoryIds, profile.BeneficiaryTypeIds, profile.ProjectTypeIds,
        profile.TagIds, profile.Languages.Select(language =>
            new OrganizationLanguageResponse(language.LanguageId, language.Proficiency)).ToArray());

    private static string FormatETag(byte[] rowVersion) => $"\"{Convert.ToHexString(rowVersion)}\"";

    private static bool TryParseETag(string? value, out byte[] rowVersion)
    {
        rowVersion = [];
        if (string.IsNullOrWhiteSpace(value)) return false;
        var normalized = value.Trim().Trim('"');
        if (normalized.Length != 16) return false;
        try { rowVersion = Convert.FromHexString(normalized); return rowVersion.Length == 8; }
        catch (FormatException) { return false; }
    }

    private static bool TryGetPublicUserId(ClaimsPrincipal principal, out Guid id) =>
        Guid.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out id);

    private static string RoleName(byte role) => role == 1 ? "admin" : "member";
    private static IResult NotFound() => Problem(404, "Organización no encontrada",
        "No existe o no tienes una membresía activa.", "organization-not-found");
    private static IResult InvalidSession() => Problem(401, "Sesión inválida", "Inicia sesión nuevamente.", "invalid-session");
    private static IResult Problem(int status, string title, string? detail, string code) => Results.Problem(
        statusCode: status, title: title, detail: detail,
        type: $"https://fundingplatform.local/problems/{code}");
}
