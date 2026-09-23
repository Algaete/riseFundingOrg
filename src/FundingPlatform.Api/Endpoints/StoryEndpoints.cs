using System.Security.Claims;
using FundingPlatform.Application.Stories;
using FundingPlatform.Core.Stories;

namespace FundingPlatform.Api.Endpoints;

public static class StoryEndpoints
{
    public static IEndpointRouteBuilder MapStoryEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var publicRoutes = endpoints.MapGroup("/api/v1/stories").AllowAnonymous().RequireRateLimiting("marketplace-read");
        publicRoutes.MapGet("/", async (Guid? organizationId, Guid? projectId, int? page, IStoryRepository repo, HttpContext context, CancellationToken token) =>
        {
            context.Response.Headers.CacheControl = "no-store";
            if (page is < 1 or > 1000) return Results.BadRequest();
            return Results.Ok(await repo.ListAsync(null, organizationId, projectId, null, page ?? 1, token));
        });
        publicRoutes.MapGet("/{id:guid}", async (Guid id, IStoryRepository repo, HttpContext context, CancellationToken token) =>
        {
            context.Response.Headers.CacheControl = "no-store";
            var result = await repo.ListAsync(null, null, null, id, 1, token);
            return result.Items.FirstOrDefault() is { } story ? Results.Ok(story) : Results.NotFound();
        });
        var own = endpoints.MapGroup("/api/v1/organizations/{organizationId:guid}/stories")
            .RequireAuthorization("full-session").RequireRateLimiting("organization-write");
        own.MapGet("/", async (Guid organizationId, int? page, ClaimsPrincipal principal, IStoryRepository repo, CancellationToken token) =>
        {
            if (!ProjectEndpointResults.TryGetUserId(principal, out var actor)) return Results.Unauthorized();
            if (page is < 1 or > 1000) return Results.BadRequest();
            try { return Results.Ok(await repo.ListAsync(actor, organizationId, null, null, page ?? 1, token)); }
            catch (StoryDataException error) when (Known(error)) { return Failure(error); }
        });
        own.MapPut("/{id:guid}", async (Guid organizationId, Guid id, StoryWrite data, ClaimsPrincipal principal, IStoryRepository repo, CancellationToken token) =>
        {
            if (!ProjectEndpointResults.TryGetUserId(principal, out var actor)) return Results.Unauthorized();
            var normalized = StoryRules.Normalize(data);
            var errors = StoryRules.Validate(normalized);
            if (errors.Count > 0) return FieldValidationResults.BadRequest(errors);
            try { await repo.SaveAsync(actor, organizationId, id, normalized, token); return Results.NoContent(); }
            catch (StoryDataException error) when (Known(error)) { return Failure(error); }
        });
        own.MapPost("/{id:guid}/publication", async (Guid organizationId, Guid id, StoryPublication data, ClaimsPrincipal principal, IStoryRepository repo, CancellationToken token) =>
        {
            if (!ProjectEndpointResults.TryGetUserId(principal, out var actor)) return Results.Unauthorized();
            if (data.ExpectedRevision < 1 || data.Publish && !data.RightsConfirmed) return Results.BadRequest();
            try { await repo.PublishAsync(actor, organizationId, id, data, token); return Results.NoContent(); }
            catch (StoryDataException error) when (Known(error)) { return Failure(error); }
        });
        return endpoints;
    }
    private static bool Known(StoryDataException e) => e.Number is >= 56120 and <= 56123;
    private static IResult Failure(StoryDataException e) => ProjectEndpointResults.Problem(
        e.Number == 56120 ? 404 : e.Number == 56121 ? 409 : 422, "No fue posible completar la operación de historias",
        null, e.Number == 56121 ? "story-version-conflict" : "story-not-ready");
}
