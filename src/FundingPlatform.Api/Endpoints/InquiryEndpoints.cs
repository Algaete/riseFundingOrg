using System.Security.Claims;
using FundingPlatform.Application.Engagement;
using FundingPlatform.Core.Engagement;

namespace FundingPlatform.Api.Endpoints;

public static class InquiryEndpoints
{
    public static IEndpointRouteBuilder MapInquiryEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/v1/services", () => Results.Ok(ProfessionalServices.Codes)).AllowAnonymous().RequireRateLimiting("marketplace-read");
        endpoints.MapPost("/api/v1/inquiries", async (InquiryInput data, InquiryService service, HttpContext context, CancellationToken token) =>
        {
            context.Response.Headers.CacheControl = "no-store";
            var normalized = InquiryRules.Normalize(data);
            var errors = InquiryRules.Validate(normalized);
            if (errors.Count > 0) return FieldValidationResults.BadRequest(errors);
            try { return Results.Ok(await service.CaptureAsync(normalized, token)); }
            catch (InquiryDataException e) when (Known(e)) { return Failure(e); }
        }).AllowAnonymous().RequireRateLimiting("contact-write");
        var admin = endpoints.MapGroup("/api/v1/admin/inquiries").RequireAuthorization("admin-mfa").RequireRateLimiting("organization-write");
        admin.MapGet("/", async (int? page, ClaimsPrincipal principal, IInquiryRepository repo, CancellationToken token) =>
        {
            if (!ProjectEndpointResults.TryGetUserId(principal, out var actor)) return Results.Unauthorized();
            if (page is < 1 or > 1000) return Results.BadRequest();
            try { return Results.Ok(await repo.ListAsync(actor, page ?? 1, token)); }
            catch (InquiryDataException e) when (Known(e)) { return Failure(e); }
        });
        admin.MapPut("/{id:guid}", async (Guid id, InquiryReview data, ClaimsPrincipal principal, IInquiryRepository repo, CancellationToken token) =>
        {
            if (!ProjectEndpointResults.TryGetUserId(principal, out var actor)) return Results.Unauthorized();
            if (data.ExpectedRevision < 1 || data.Status > 2) return Results.BadRequest();
            try { await repo.ReviewAsync(actor, id, data, token); return Results.NoContent(); }
            catch (InquiryDataException e) when (Known(e)) { return Failure(e); }
        });
        return endpoints;
    }
    private static bool Known(InquiryDataException e) => e.Number is 51601 or 51602 or >= 56130 and <= 56133;
    private static IResult Failure(InquiryDataException e) => ProjectEndpointResults.Problem(e.Number switch
        { 51601 or 51602 => 403, 56130 => 409, 56131 => 429, 56133 => 404, _ => 422 },
        "No fue posible procesar la solicitud", null, "inquiry-request-failed");
}
