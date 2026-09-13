using System.Security.Claims;
using FundingPlatform.Application.Matching;
using FundingPlatform.Core.Matching;

namespace FundingPlatform.Api.Endpoints;

public static class GapRecommendationEndpoints
{
    public static IEndpointRouteBuilder MapGapRecommendationEndpoints(this IEndpointRouteBuilder endpoints)
    {
        // POST carries the private project context in the body. This operation has no side effects.
        endpoints.MapPost("/api/v1/matching/gap-recommendations", ReadAsync)
            .RequireAuthorization("full-session").RequireRateLimiting("organization-activity-read")
            .WithTags("Matching recommendations");
        return endpoints;
    }

    private static async Task<IResult> ReadAsync(GapRecommendationRequest request, ClaimsPrincipal principal,
        GapRecommendationService service, CancellationToken token)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var actor)) return ProjectEndpointResults.InvalidSession();
        var errors = GapRecommendationService.Validate(request);
        if (errors.Count > 0) return FieldValidationResults.BadRequest(errors);
        try
        {
            var result = await service.ReadAsync(actor, request, token);
            return result is null ? NotFound() : Results.Ok(result);
        }
        catch (DiscoveryMatchingDataException error) when (error.Number is 55501 or 55502 or 55601 or 55901)
        { return NotFound(); }
    }

    private static IResult NotFound() => ProjectEndpointResults.Problem(404, "Contexto no disponible", null, "gap-context-not-found");
}
