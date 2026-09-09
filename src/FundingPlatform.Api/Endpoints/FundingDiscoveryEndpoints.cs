using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Api.Endpoints;
public static class FundingDiscoveryEndpoints
{
    public static IEndpointRouteBuilder MapFundingDiscoveryEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/v1/funding-discovery", SearchAsync).AllowAnonymous().RequireRateLimiting("marketplace-read");
        endpoints.MapGet("/api/v1/funding-discovery/catalogs", async (FundingPlatform.Application.Organizations.OrganizationProfileService service, HttpContext context, CancellationToken token) =>
        {
            var catalogs = await service.GetCatalogsAsync(token);
            context.Response.Headers.CacheControl = "public,max-age=300";
            return Results.Ok(new { catalogs.Countries, catalogs.Regions, catalogs.Currencies, catalogs.FundingCategories,
                catalogs.FundingTypes, catalogs.OrganizationTypes, catalogs.Languages });
        }).AllowAnonymous().RequireRateLimiting("marketplace-read");
        var admin = endpoints.MapGroup("/api/v1/admin/funding-discovery").RequireAuthorization("admin-mfa").RequireRateLimiting("organization-write");
        admin.MapGet("/{id:guid}", GetAsync);
        admin.MapPut("/{id:guid}", ReviewAsync);
        return endpoints;
    }
    private static async Task<IResult> SearchAsync([AsParameters] FundingDiscoveryFilters filters, HttpContext context, IFundingDiscoveryRepository repository, CancellationToken token)
    {
        var errors = FundingDiscoveryRules.Validate(filters);
        if (errors.Count > 0) return FieldValidationResults.BadRequest(errors);
        try { var result = await repository.SearchAsync(filters with { Query = filters.Query?.Trim() }, token); context.Response.Headers.CacheControl = "public,max-age=60"; return Results.Ok(result); }
        catch (FundingDiscoveryDataException error) when (error.Number == 55704) { return Failure(error); }
    }
    private static async Task<IResult> GetAsync(Guid id, ClaimsPrincipal principal, HttpContext context, IFundingDiscoveryRepository repository, CancellationToken token)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var actor)) return Results.Unauthorized();
        try { var result = await repository.GetAsync(actor, id, token); if (result?.ETag is { } tag) context.Response.Headers.ETag = tag; return result is null ? Results.NotFound() : Results.Ok(result); }
        catch (FundingDiscoveryDataException error) when (error.Number is 51601 or 51602 or 55701) { return Failure(error); }
    }
    private static async Task<IResult> ReviewAsync(Guid id, FundingDiscoveryReview data, ClaimsPrincipal principal, HttpContext context, IFundingDiscoveryRepository repository, CancellationToken token)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var actor)) return Results.Unauthorized();
        if (!CollaborationEndpointSupport.Headers(context, true, true, out var key, out var version, out var headerError)) return headerError!;
        var errors = FundingDiscoveryRules.Validate(data);
        if (errors.Count > 0) return FieldValidationResults.BadRequest(errors);
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new { id, data, version })));
        try
        {
            var result = await repository.ReviewAsync(actor, id, data, version, SHA256.HashData(Encoding.UTF8.GetBytes(key)), hash, token);
            context.Response.Headers.ETag = result.ETag; return Results.Ok(result);
        }
        catch (FundingDiscoveryDataException error) when (error.Number is 51601 or 51602 or >= 55701 and <= 55705) { return Failure(error); }
    }
    private static IResult Failure(FundingDiscoveryDataException error) => ProjectEndpointResults.Problem(error.Number switch
        { 51601 or 51602 => 403, 55701 => 404, 55702 => 412, 55703 => 409, _ => 422 }, "Operación no disponible", null,
        error.Number == 55702 ? "discovery-version-conflict" : "discovery-classification-error");
}
