using System.Security.Claims;
using FundingPlatform.Application.Collaboration;
using FundingPlatform.Core.Collaboration;
using FundingPlatform.Core.Validation;

namespace FundingPlatform.Api.Endpoints;

public static class ProfessionalProfileEndpoints
{
    public static IEndpointRouteBuilder MapProfessionalProfileEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var own = endpoints.MapGroup("/api/v1/me/professional-profile").RequireAuthorization("full-session")
            .WithTags("Professional profiles").AddEndpointFilter<CollaborationExceptionFilter>();
        own.MapGet("/", GetOwnAsync).RequireRateLimiting("organization-activity-read");
        own.MapPut("/", SaveAsync).RequireRateLimiting("organization-write");
        endpoints.MapGet("/api/v1/professionals", SearchAsync).RequireAuthorization("full-session")
            .RequireRateLimiting("organization-activity-read").WithTags("Professional profiles").AddEndpointFilter<CollaborationExceptionFilter>();
        return endpoints;
    }
    private static async Task<IResult> GetOwnAsync(ClaimsPrincipal principal, HttpContext context, ProfessionalProfileService service, CancellationToken token)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        var profile = await service.GetOwnAsync(userId, token);
        if (profile is not null) context.Response.Headers.ETag = profile.ETag;
        // A null object result writes an empty body in ASP.NET. Send explicit JSON
        // null so first-time clients can distinguish an absent profile from failure.
        return profile is null ? Results.Content("null", "application/json", statusCode: 200) : Results.Json(profile);
    }
    private static async Task<IResult> SaveAsync(ProfessionalProfileData request, ClaimsPrincipal principal, HttpContext context, ProfessionalProfileService service, CancellationToken token)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        if (!CollaborationEndpointSupport.Headers(context, true, true, out var key, out var version, out var error)) return error!;
        var data = CollaborationRules.Normalize(request);
        var errors = CollaborationRules.Validate(data);
        if (errors.Count > 0) return FieldValidationResults.BadRequest(errors);
        var result = await service.SaveAsync(userId, data, version, key, token);
        context.Response.Headers.ETag = result.ETag;
        return Results.Ok(result);
    }
    private static async Task<IResult> SearchAsync(ClaimsPrincipal principal, ProfessionalProfileService service, CancellationToken token,
        string? q = null, short? countryId = null, int? categoryId = null, int page = 1, int pageSize = 20)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        var errors = new FieldValidationErrors();
        if (!CollaborationRules.ValidPage(page, pageSize) || q?.Trim().Length > 200 || countryId is <= 0 || categoryId is <= 0) CollaborationRules.Invalid(errors, "filters");
        if (errors.Count > 0) return FieldValidationResults.BadRequest(errors);
        return Results.Ok(await service.SearchAsync(userId, new(q, countryId, categoryId, page, pageSize), token));
    }
}
