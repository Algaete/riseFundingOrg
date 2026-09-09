using System.Security.Claims;
using FundingPlatform.Application.Collaboration;
using FundingPlatform.Core.Collaboration;
using FundingPlatform.Core.Validation;

namespace FundingPlatform.Api.Endpoints;

public static class ConsortiumEndpoints
{
    public sealed record ParticipantActionRequest(ConsortiumParticipantStatus Action);
    public static IEndpointRouteBuilder MapConsortiumEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/consortia").RequireAuthorization("full-session")
            .WithTags("Consortia").AddEndpointFilter<CollaborationExceptionFilter>();
        group.MapGet("/", ListAsync).RequireRateLimiting("organization-activity-read");
        group.MapGet("/{consortiumId:guid}", GetAsync).RequireRateLimiting("organization-activity-read");
        group.MapPost("/", CreateAsync).RequireRateLimiting("organization-write");
        group.MapPut("/{consortiumId:guid}", UpdateAsync).RequireRateLimiting("organization-write");
        group.MapPost("/{consortiumId:guid}/invitations", InviteAsync).RequireRateLimiting("network-connect-write");
        group.MapPatch("/{consortiumId:guid}/participants/{participantId:guid}", ActAsync).RequireRateLimiting("organization-write");
        return endpoints;
    }
    private static async Task<IResult> ListAsync(ClaimsPrincipal principal, ConsortiumService service, CancellationToken token, int page = 1, int pageSize = 20)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        if (!CollaborationRules.ValidPage(page, pageSize)) { var errors = new FieldValidationErrors(); CollaborationRules.Invalid(errors, "pagination"); return FieldValidationResults.BadRequest(errors); }
        return Results.Ok(await service.ListAsync(userId, page, pageSize, token));
    }
    private static async Task<IResult> GetAsync(Guid consortiumId, ClaimsPrincipal principal, HttpContext context, ConsortiumService service, CancellationToken token)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        var result = await service.GetAsync(userId, consortiumId, token);
        if (result is null) return ProjectEndpointResults.Problem(404, "Consorcio no disponible", null, "collaboration-not-found");
        context.Response.Headers.ETag = result.Consortium.ETag;
        return Results.Ok(result);
    }
    private static async Task<IResult> CreateAsync(ConsortiumCreateData request, ClaimsPrincipal principal, HttpContext context, ConsortiumService service, CancellationToken token)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        if (!CollaborationEndpointSupport.Headers(context, false, false, out var key, out _, out var error)) return error!;
        var errors = CollaborationRules.ValidateConsortium(request.Name?.Trim(), request.Summary?.Trim());
        if (request.ProjectId == Guid.Empty) CollaborationRules.Invalid(errors, "projectId");
        if (errors.Count > 0) return FieldValidationResults.BadRequest(errors);
        var result = await service.CreateAsync(userId, request, key, token);
        context.Response.Headers.ETag = result.ETag;
        return result.WasReplay ? Results.Ok(result) : Results.Created($"/api/v1/consortia/{result.EntityId:D}", result);
    }
    private static async Task<IResult> UpdateAsync(Guid consortiumId, ConsortiumUpdateData request, ClaimsPrincipal principal, HttpContext context, ConsortiumService service, CancellationToken token)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        if (consortiumId == Guid.Empty) return Results.NotFound();
        if (!CollaborationEndpointSupport.Headers(context, true, false, out var key, out var version, out var error)) return error!;
        var errors = CollaborationRules.ValidateConsortium(request.Name?.Trim(), request.Summary?.Trim());
        if (!Enum.IsDefined(request.Status)) CollaborationRules.Invalid(errors, "status");
        if (errors.Count > 0) return FieldValidationResults.BadRequest(errors);
        var result = await service.UpdateAsync(userId, consortiumId, request, version!, key, token);
        context.Response.Headers.ETag = result.ETag; return Results.Ok(result);
    }
    private static async Task<IResult> InviteAsync(Guid consortiumId, ConsortiumInvitationData request, ClaimsPrincipal principal, HttpContext context, ConsortiumService service, CancellationToken token)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        if (consortiumId == Guid.Empty) return Results.NotFound();
        if (!CollaborationEndpointSupport.Headers(context, true, false, out var key, out var version, out var error)) return error!;
        var errors = CollaborationRules.ValidateInvitation(request with { Contribution = (request.Contribution ?? "").Trim(), Message = (request.Message ?? "").Trim() });
        if (errors.Count > 0) return FieldValidationResults.BadRequest(errors);
        var result = await service.InviteAsync(userId, consortiumId, request, version!, key, token);
        context.Response.Headers.ETag = result.ETag; return Results.Ok(result);
    }
    private static async Task<IResult> ActAsync(Guid consortiumId, Guid participantId, ParticipantActionRequest request, ClaimsPrincipal principal, HttpContext context, ConsortiumService service, CancellationToken token)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        if (consortiumId == Guid.Empty || participantId == Guid.Empty) return Results.NotFound();
        if (!CollaborationEndpointSupport.Headers(context, true, false, out var key, out var version, out var error)) return error!;
        if (request.Action is < ConsortiumParticipantStatus.Accepted or > ConsortiumParticipantStatus.Removed)
        { var errors = new FieldValidationErrors(); CollaborationRules.Invalid(errors, "action"); return FieldValidationResults.BadRequest(errors); }
        var result = await service.ActAsync(userId, consortiumId, participantId, request.Action, version!, key, token);
        context.Response.Headers.ETag = result.ETag; return Results.Ok(result);
    }
}
