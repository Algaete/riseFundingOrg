using System.Security.Claims;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Api.Endpoints;

public static class FundingTranslationEndpoints
{
    public static IEndpointRouteBuilder MapFundingTranslationEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/admin/funding-opportunities/{id:guid}/translations")
            .WithTags("Funding translations").RequireAuthorization("admin-mfa").RequireRateLimiting("organization-write");
        group.MapGet("/{language}", GetAsync);
        group.MapPut("/{language}", SaveAsync);
        return endpoints;
    }
    private static async Task<IResult> GetAsync(Guid id, string language, ClaimsPrincipal principal,
        FundingTranslationService translations, IFundingTranslationRepository repository,
        FundingOpportunityEditorialService editorial, CancellationToken token)
    {
        if (!translations.Enabled) return Disabled();
        if (!FundingTranslationRules.Supports(language)) return Results.BadRequest();
        if (!ProjectEndpointResults.TryGetUserId(principal, out var actor)) return Results.Unauthorized();
        var original = await editorial.GetAdminAsync(actor, id, token);
        if (original.Outcome == FundingEditorialOutcome.Forbidden) return Results.Forbid();
        if (original.Value is null) return Results.NotFound();
        try { return Results.Ok(new { Translation = await repository.GetAdminAsync(actor, id, language, token) }); }
        catch (FundingTranslationDataException error) when (Known(error)) { return Failure(error); }
    }
    private static async Task<IResult> SaveAsync(Guid id, string language, FundingTranslationWrite data,
        ClaimsPrincipal principal, HttpContext context, FundingTranslationService translations,
        IFundingTranslationRepository repository, FundingOpportunityEditorialService editorial, CancellationToken token)
    {
        if (!translations.Enabled) return Disabled();
        if (!FundingTranslationRules.Supports(language)) return Results.BadRequest();
        if (!ProjectEndpointResults.TryGetUserId(principal, out var actor)) return Results.Unauthorized();
        if (!ProjectEndpointResults.TryParseETag(context.Request.Headers.IfMatch.ToString(), out var version))
            return ProjectEndpointResults.Problem(428, "Recarga la oportunidad antes de traducirla", null, "translation-source-version-required");
        var original = await editorial.GetAdminAsync(actor, id, token);
        if (original.Outcome == FundingEditorialOutcome.Forbidden) return Results.Forbid();
        if (original.Value is not { } item) return Results.NotFound();
        if (data.SourceContentVersion != item.ContentVersion || !version.SequenceEqual(item.RowVersion))
            return ProjectEndpointResults.Problem(412, "La oportunidad cambió", null, "translation-version-conflict");
        var normalized = data with { Text = data.Text is null ? null : FundingTranslationRules.Normalize(data.Text) };
        var errors = FundingTranslationRules.Validate(normalized, FundingTranslationRules.From(item.Data));
        if (errors.Count > 0) return FieldValidationResults.BadRequest(errors);
        try { return Results.Ok(await repository.SaveAsync(actor, id, language, normalized, version, token)); }
        catch (FundingTranslationDataException error) when (Known(error)) { return Failure(error); }
    }
    private static bool Known(FundingTranslationDataException error) => error.Number is 51601 or 51602 or >= 56031 and <= 56034;
    private static IResult Failure(FundingTranslationDataException error) => ProjectEndpointResults.Problem(
        error.Number switch { 51601 or 51602 => 403, 56031 => 404, 56032 => 412, _ => 422 },
        "No fue posible guardar o consultar la traducción", null, error.Number == 56032 ? "translation-version-conflict" : "translation-invalid");
    private static IResult Disabled() => ProjectEndpointResults.Problem(503, "Traducciones aún no habilitadas", null, "translations-disabled");
}
