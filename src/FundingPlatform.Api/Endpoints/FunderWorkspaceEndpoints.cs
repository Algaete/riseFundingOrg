using System.Security.Claims;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Contracts.FundingOpportunities;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Api.Endpoints;

/// <summary>Authenticated owner routes reuse editorial contracts; review routes are deliberately absent.</summary>
public static class FunderWorkspaceEndpoints
{
    public static IEndpointRouteBuilder MapFunderWorkspaceEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var funders = endpoints.MapGroup("/api/v1/funder-workspace/funders")
            .RequireAuthorization("full-session").WithTags("Funder workspace");
        var opportunities = endpoints.MapGroup("/api/v1/funder-workspace/funding-opportunities")
            .RequireAuthorization("full-session").WithTags("Funder workspace");
        funders.MapGet("/", ListFundersAsync).RequireRateLimiting("organization-funding-read");
        funders.MapGet("/{funderId:guid}", GetFunderAsync).RequireRateLimiting("organization-funding-read");
        funders.MapPost("/", CreateFunderAsync).RequireRateLimiting("organization-write");
        funders.MapPut("/{funderId:guid}", UpdateFunderAsync).RequireRateLimiting("organization-write");
        funders.MapPost("/{funderId:guid}/submit-review", SubmitFunderReviewAsync).RequireRateLimiting("organization-write");
        funders.MapPost("/{funderId:guid}/start-correction", StartFunderCorrectionAsync).RequireRateLimiting("organization-write");
        funders.MapPost("/{funderId:guid}/deactivate", DeactivateFunderAsync).RequireRateLimiting("organization-write");
        opportunities.MapGet("/", ListOpportunitiesAsync).RequireRateLimiting("organization-funding-read");
        opportunities.MapGet("/{opportunityId:guid}", GetOpportunityAsync).RequireRateLimiting("organization-funding-read");
        opportunities.MapPost("/", CreateOpportunityAsync).RequireRateLimiting("organization-write");
        opportunities.MapPut("/{opportunityId:guid}", UpdateOpportunityAsync).RequireRateLimiting("organization-write");
        opportunities.MapPost("/{opportunityId:guid}/submit-review", SubmitOpportunityReviewAsync).RequireRateLimiting("organization-write");
        opportunities.MapPost("/{opportunityId:guid}/start-correction", StartOpportunityCorrectionAsync).RequireRateLimiting("organization-write");
        opportunities.MapPost("/{opportunityId:guid}/deactivate", DeactivateOpportunityAsync).RequireRateLimiting("organization-write");
        endpoints.MapGet("/api/v1/funder-workspace/funding-sources", SourcesAsync)
            .RequireAuthorization("full-session").RequireRateLimiting("organization-funding-read")
            .WithTags("Funder workspace");
        return endpoints;
    }

    private static async Task<IResult> SourcesAsync(ClaimsPrincipal principal, IFunderWorkspaceSourceRepository repository, CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId)) return Results.Unauthorized();
        try { return Results.Ok(await repository.ListAsync(userId, cancellationToken)); }
        catch (SqlException exception) when (exception.Number is 51601 or 51602)
        {
            return ProjectEndpointResults.Problem(403, "Acceso no disponible", null, "funder-workspace-forbidden");
        }
    }

    private static Task<IResult> ListFundersAsync(
        ClaimsPrincipal principal,
        [FromKeyedServices("funder-workspace")] FunderEditorialService service,
        CancellationToken cancellationToken,
        string? query = null,
        byte? status = null,
        bool includeInactive = false,
        int page = 1,
        int pageSize = 50) =>
        AdminFundingEditorialEndpoints.ListFundersAsync(principal, service, cancellationToken, query, status, includeInactive, page, pageSize);

    private static Task<IResult> GetFunderAsync(
        Guid funderId,
        ClaimsPrincipal principal,
        HttpContext context,
        [FromKeyedServices("funder-workspace")] FunderEditorialService service,
        CancellationToken cancellationToken) =>
        AdminFundingEditorialEndpoints.GetFunderAsync(funderId, principal, context, service, cancellationToken);

    private static Task<IResult> CreateFunderAsync(
        FunderWriteRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        [FromKeyedServices("funder-workspace")] FunderEditorialService service,
        CancellationToken cancellationToken) =>
        AdminFundingEditorialEndpoints.CreateFunderAsync(request, principal, context, service, cancellationToken);

    private static Task<IResult> UpdateFunderAsync(
        Guid funderId,
        FunderWriteRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        [FromKeyedServices("funder-workspace")] FunderEditorialService service,
        CancellationToken cancellationToken) =>
        AdminFundingEditorialEndpoints.UpdateFunderAsync(funderId, request, principal, context, service, cancellationToken);

    private static Task<IResult> SubmitFunderReviewAsync(
        Guid funderId,
        ClaimsPrincipal principal,
        HttpContext context,
        [FromKeyedServices("funder-workspace")] FunderEditorialService service,
        CancellationToken cancellationToken) =>
        AdminFundingEditorialEndpoints.SubmitFunderReviewAsync(funderId, principal, context, service, cancellationToken);

    private static Task<IResult> StartFunderCorrectionAsync(
        Guid funderId,
        FundingEditorialStartCorrectionRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        [FromKeyedServices("funder-workspace")] FunderEditorialService service,
        CancellationToken cancellationToken) =>
        AdminFundingEditorialEndpoints.StartFunderCorrectionAsync(funderId, request, principal, context, service, cancellationToken);

    private static Task<IResult> DeactivateFunderAsync(
        Guid funderId,
        FundingEditorialDeactivateRequest? request,
        ClaimsPrincipal principal,
        HttpContext context,
        [FromKeyedServices("funder-workspace")] FunderEditorialService service,
        CancellationToken cancellationToken) =>
        AdminFundingEditorialEndpoints.DeactivateFunderAsync(funderId, request, principal, context, service, cancellationToken);

    private static Task<IResult> ListOpportunitiesAsync(
        ClaimsPrincipal principal,
        [FromKeyedServices("funder-workspace")] FundingOpportunityEditorialService service,
        CancellationToken cancellationToken,
        string? query = null,
        byte? status = null,
        bool includeInactive = false,
        int page = 1,
        int pageSize = 50) =>
        AdminFundingEditorialEndpoints.ListOpportunitiesAsync(principal, service, cancellationToken, query, status, includeInactive, page, pageSize);

    private static Task<IResult> GetOpportunityAsync(
        Guid opportunityId,
        ClaimsPrincipal principal,
        HttpContext context,
        [FromKeyedServices("funder-workspace")] FundingOpportunityEditorialService service,
        CancellationToken cancellationToken) =>
        AdminFundingEditorialEndpoints.GetOpportunityAsync(opportunityId, principal, context, service, cancellationToken);

    private static Task<IResult> CreateOpportunityAsync(
        FundingOpportunityWriteRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        [FromKeyedServices("funder-workspace")] FundingOpportunityEditorialService service,
        CancellationToken cancellationToken) =>
        AdminFundingEditorialEndpoints.CreateOpportunityAsync(request, principal, context, service, cancellationToken);

    private static Task<IResult> UpdateOpportunityAsync(
        Guid opportunityId,
        FundingOpportunityWriteRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        [FromKeyedServices("funder-workspace")] FundingOpportunityEditorialService service,
        CancellationToken cancellationToken) =>
        AdminFundingEditorialEndpoints.UpdateOpportunityAsync(opportunityId, request, principal, context, service, cancellationToken);

    private static Task<IResult> SubmitOpportunityReviewAsync(
        Guid opportunityId,
        ClaimsPrincipal principal,
        HttpContext context,
        [FromKeyedServices("funder-workspace")] FundingOpportunityEditorialService service,
        CancellationToken cancellationToken) =>
        AdminFundingEditorialEndpoints.SubmitOpportunityReviewAsync(opportunityId, principal, context, service, cancellationToken);

    private static Task<IResult> StartOpportunityCorrectionAsync(
        Guid opportunityId,
        FundingEditorialStartCorrectionRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        [FromKeyedServices("funder-workspace")] FundingOpportunityEditorialService service,
        CancellationToken cancellationToken) =>
        AdminFundingEditorialEndpoints.StartOpportunityCorrectionAsync(opportunityId, request, principal, context, service, cancellationToken);

    private static Task<IResult> DeactivateOpportunityAsync(
        Guid opportunityId,
        FundingEditorialDeactivateRequest? request,
        ClaimsPrincipal principal,
        HttpContext context,
        [FromKeyedServices("funder-workspace")] FundingOpportunityEditorialService service,
        CancellationToken cancellationToken) =>
        AdminFundingEditorialEndpoints.DeactivateOpportunityAsync(opportunityId, request, principal, context, service, cancellationToken);
}

