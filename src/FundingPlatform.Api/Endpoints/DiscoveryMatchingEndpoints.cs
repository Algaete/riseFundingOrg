using System.Security.Claims;
using FundingPlatform.Application.Matching;
using FundingPlatform.Core.Matching;

namespace FundingPlatform.Api.Endpoints;
public static class DiscoveryMatchingEndpoints
{
    public static IEndpointRouteBuilder MapDiscoveryMatchingEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/api/v1/matching/discovery", SearchAsync).RequireAuthorization("full-session")
            .RequireRateLimiting("organization-activity-read").WithTags("Discovery matching");
        return endpoints;
    }
    private static async Task<IResult> SearchAsync(DiscoveryMatchingRequest request, ClaimsPrincipal principal,
        DiscoveryMatchingService service, CancellationToken token)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        var errors = DiscoveryMatchingService.Validate(request);
        if (errors.Count > 0) return FieldValidationResults.BadRequest(errors);
        try
        {
            var result = await service.SearchAsync(userId, request, token);
            return result is null ? ProjectEndpointResults.Problem(404, "Origen no disponible", null, "discovery-not-found") : Results.Ok(result);
        }
        catch (DiscoveryMatchingDataException error) when (error.Number is 55501 or 55502 or 55601)
        { return ProjectEndpointResults.Problem(404, "Origen no disponible", null, "discovery-not-found"); }
    }
}
