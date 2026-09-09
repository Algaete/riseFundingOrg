using FundingPlatform.Core.Validation;
using System.Security.Claims;
using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Contracts.ProjectAssets;
using FundingPlatform.Core.ProjectAssets;

namespace FundingPlatform.Api.Endpoints;

public static class ProjectAssetEndpoints
{
    private const string ProjectETagHeader = "X-Project-If-Match";
    private const string ProjectResponseETagHeader = "X-Project-ETag";

    public static IEndpointRouteBuilder MapProjectAssetEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints
            .MapGroup("/api/v1/organizations/{organizationId:guid}/projects/{projectId:guid}")
            .WithTags("Project Assets")
            .RequireAuthorization("full-session");

        group.MapGet("/assets", ListAsync)
            .Produces<ProjectAssetCollectionResponse>()
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        group.MapPost("/asset-upload-intents", CreateUploadIntentAsync)
            .RequireRateLimiting("project-asset-create")
            .Produces<ProjectAssetUploadIntentCreatedResponse>(StatusCodes.Status201Created)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        group.MapGet("/asset-upload-intents/{intentId:guid}", GetUploadIntentAsync)
            .Produces<ProjectAssetUploadIntentResponse>()
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        group.MapPost("/asset-upload-intents/{intentId:guid}/complete", CompleteUploadIntentAsync)
            .RequireRateLimiting("project-asset-mutation")
            .Produces<ProjectAssetOperationResponse>()
            .Produces<ProjectAssetOperationResponse>(StatusCodes.Status202Accepted)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status410Gone)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);
        group.MapPatch("/assets/{assetId:guid}", UpdateMetadataAsync)
            .RequireRateLimiting("project-asset-mutation")
            .Produces<ProjectAssetOperationResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);
        group.MapPut("/assets/order", ReorderAsync)
            .RequireRateLimiting("project-asset-mutation")
            .Produces<ProjectAssetOperationResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);
        group.MapDelete("/assets/{assetId:guid}", DeleteAsync)
            .RequireRateLimiting("project-asset-mutation")
            .Produces<ProjectAssetOperationResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);
        group.MapGet("/assets/{assetId:guid}/content", GetContentAsync)
            .RequireRateLimiting("project-asset-content")
            .Produces(StatusCodes.Status200OK)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        return endpoints;
    }

    private static async Task<IResult> CreateUploadIntentAsync(
        Guid organizationId,
        Guid projectId,
        CreateProjectAssetUploadIntentRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        ProjectAssetService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        if (!ProjectEndpointResults.TryParseETag(
                context.Request.Headers.IfMatch.FirstOrDefault(), out var projectRowVersion))
            return ProjectEndpointResults.PreconditionRequired(
                "project-if-match-required",
                "Versión del proyecto requerida",
                "Envía el ETag vigente del proyecto en If-Match.");
        var result = await service.CreateUploadIntentAsync(
            userId,
            organizationId,
            projectId,
            projectRowVersion,
            (ProjectAssetKind)request.Kind,
            request.FileName,
            request.MimeType,
            request.ContentLength,
            cancellationToken);
        if (result.Outcome != ProjectAssetOutcome.Success ||
            result.IntentPublicId is null || result.Kind is null || result.Status is null ||
            result.ExpiresAtUtc is null || result.UploadUri is null ||
            result.RequiredHeaders is null || result.CompletionToken is null ||
            result.IntentRowVersion is not { Length: 8 } ||
            result.ProjectRowVersion is not { Length: 8 })
            return MapFailure(result.Outcome, result.Code, result.Errors);

        var intentETag = FormatETag(result.IntentRowVersion);
        var projectETag = SetProjectETag(context, result.ProjectRowVersion);
        context.Response.Headers.ETag = intentETag;
        var statusUrl = AssetBase(organizationId, projectId) +
            $"/asset-upload-intents/{result.IntentPublicId:D}";
        return Results.Created(
            statusUrl,
            new ProjectAssetUploadIntentCreatedResponse(
                result.IntentPublicId.Value,
                (byte)result.Kind.Value,
                (byte)result.Status.Value,
                result.ExpiresAtUtc.Value,
                result.MaxContentLength,
                "PUT",
                result.UploadUri,
                result.RequiredHeaders,
                result.CompletionToken,
                statusUrl,
                intentETag,
                projectETag,
                "La autorización sólo permite crear este archivo. El servidor verificará tamaño, tipo, contenido y análisis de seguridad antes de usarlo."));
    }

    private static async Task<IResult> CompleteUploadIntentAsync(
        Guid organizationId,
        Guid projectId,
        Guid intentId,
        CompleteProjectAssetUploadIntentRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        ProjectAssetService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        var result = await service.CompleteUploadIntentAsync(
            userId, organizationId, projectId, intentId,
            request.CompletionToken, cancellationToken);
        return MapOperation(
            result,
            context,
            AssetBase(organizationId, projectId) + $"/asset-upload-intents/{intentId:D}");
    }

    private static async Task<IResult> GetUploadIntentAsync(
        Guid organizationId,
        Guid projectId,
        Guid intentId,
        ClaimsPrincipal principal,
        HttpContext context,
        ProjectAssetService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        var result = await service.GetUploadIntentAsync(
            userId, organizationId, projectId, intentId, cancellationToken);
        if (result.Value is null) return MapFailure(result.Outcome, result.Code, null);
        var value = result.Value;
        var etag = FormatETag(value.RowVersion);
        context.Response.Headers.ETag = etag;
        return Results.Ok(new ProjectAssetUploadIntentResponse(
            value.PublicId,
            value.ProjectPublicId,
            (byte)value.Kind,
            value.OriginalFileName,
            value.DeclaredMimeType,
            value.ExpectedContentLength,
            value.MaxContentLength,
            (byte)value.Status,
            value.ExpiresAtUtc,
            value.AssetPublicId,
            value.StorageStatus.HasValue ? (byte)value.StorageStatus.Value : null,
            value.ScanStatus.HasValue ? (byte)value.ScanStatus.Value : null,
            value.ScanProvider.HasValue ? (byte)value.ScanProvider.Value : null,
            value.CreatedAtUtc,
            value.UpdatedAtUtc,
            etag));
    }

    private static async Task<IResult> ListAsync(
        Guid organizationId,
        Guid projectId,
        ClaimsPrincipal principal,
        HttpContext context,
        ProjectAssetService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        var result = await service.ListAsync(
            userId, organizationId, projectId, cancellationToken);
        if (result.Value is null) return MapFailure(result.Outcome, result.Code, null);
        var value = result.Value;
        var projectETag = SetProjectETag(context, value.ProjectRowVersion);
        context.Response.Headers.ETag = projectETag;
        return Results.Ok(new ProjectAssetCollectionResponse(
            value.ProjectPublicId,
            value.PublicationStatus,
            projectETag,
            value.Items.Select(item => MapAsset(organizationId, projectId, item)).ToArray()));
    }

    private static async Task<IResult> UpdateMetadataAsync(
        Guid organizationId,
        Guid projectId,
        Guid assetId,
        UpdateProjectAssetMetadataRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        ProjectAssetService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        if (!TryDualETag(context, out var assetRowVersion, out var projectRowVersion, out var failure))
            return failure!;
        var result = await service.UpdateMetadataAsync(
            userId,
            organizationId,
            projectId,
            assetId,
            assetRowVersion,
            projectRowVersion,
            new ProjectAssetMetadata(
                request.DisplayName ?? string.Empty,
                request.AltText,
                request.Caption,
                request.IsCover),
            cancellationToken);
        return MapOperation(result, context, AssetBase(organizationId, projectId));
    }

    private static async Task<IResult> ReorderAsync(
        Guid organizationId,
        Guid projectId,
        ReorderProjectAssetsRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        ProjectAssetService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        if (!ProjectEndpointResults.TryParseETag(
                context.Request.Headers.IfMatch.FirstOrDefault(), out var projectRowVersion))
            return ProjectEndpointResults.PreconditionRequired(
                "project-if-match-required", "Versión del proyecto requerida",
                "Envía el ETag vigente del proyecto en If-Match.");
        var items = new List<(Guid AssetPublicId, byte[] RowVersion)>();
        foreach (var item in request.Items ?? [])
        {
            if (!ProjectEndpointResults.TryParseETag(item.ETag, out var rowVersion))
                return ProjectEndpointResults.Validation(
                    422,
                    "Orden inválido",
                    "project-asset-order-invalid",
                    new FieldValidationErrors
                    {
                        { "items", "api-validation-044", "Cada adjunto necesita su ETag vigente." }
                    });
            items.Add((item.AssetId, rowVersion));
        }
        var result = await service.ReorderAsync(
            userId, organizationId, projectId,
            projectRowVersion, items, cancellationToken);
        return MapOperation(result, context, AssetBase(organizationId, projectId));
    }

    private static async Task<IResult> DeleteAsync(
        Guid organizationId,
        Guid projectId,
        Guid assetId,
        ClaimsPrincipal principal,
        HttpContext context,
        ProjectAssetService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        if (!TryDualETag(context, out var assetRowVersion, out var projectRowVersion, out var failure))
            return failure!;
        var result = await service.DeleteAsync(
            userId,
            organizationId,
            projectId,
            assetId,
            assetRowVersion,
            projectRowVersion,
            cancellationToken);
        return MapOperation(result, context, AssetBase(organizationId, projectId));
    }

    private static async Task<IResult> GetContentAsync(
        Guid organizationId,
        Guid projectId,
        Guid assetId,
        ClaimsPrincipal principal,
        HttpContext context,
        ProjectAssetService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUserId(principal, out var userId)) return ProjectEndpointResults.InvalidSession();
        var result = await service.GetTrustedContentAsync(
            userId, organizationId, projectId, assetId, cancellationToken);
        if (result.Outcome != ProjectAssetOutcome.Success ||
            result.Claim is null || result.Content is null)
            return MapFailure(result.Outcome, result.Code, null);

        context.Response.Headers.ContentSecurityPolicy = "default-src 'none'; sandbox";
        context.Response.Headers.CacheControl = "private, no-store";
        var downloadName = result.Claim.Kind != ProjectAssetKind.Image
            ? result.Claim.FileName
            : null;
        return Results.Stream(
            result.Content.Content,
            result.Claim.MimeType,
            downloadName,
            enableRangeProcessing: true);
    }

    private static ProjectAssetResponse MapAsset(
        Guid organizationId,
        Guid projectId,
        ProjectAsset value)
    {
        var eTag = FormatETag(value.RowVersion);
        return new ProjectAssetResponse(
            value.PublicId,
            (byte)value.Kind,
            value.OriginalFileName,
            value.DisplayName,
            value.MimeType,
            value.ContentLength,
            value.PixelWidth,
            value.PixelHeight,
            (byte)value.StorageStatus,
            (byte)value.ScanStatus,
            (byte)value.ScanProvider,
            value.ScanResultCode,
            value.SortOrder,
            value.IsCover,
            value.AltText,
            value.Caption,
            value.IsReady,
            value.IsReady
                ? AssetBase(organizationId, projectId) + $"/assets/{value.PublicId:D}/content"
                : null,
            value.CreatedAtUtc,
            value.UpdatedAtUtc,
            eTag);
    }

    private static IResult MapOperation(
        ProjectAssetOperationResult result,
        HttpContext context,
        string statusUrl)
    {
        if (result.Outcome is not (ProjectAssetOutcome.Success or ProjectAssetOutcome.Processing))
            return MapFailure(result.Outcome, result.Code, result.Errors);
        var intentETag = OptionalETag(result.IntentRowVersion);
        var assetETag = OptionalETag(result.AssetRowVersion);
        var projectETag = result.ProjectRowVersion is { Length: 8 }
            ? SetProjectETag(context, result.ProjectRowVersion)
            : null;
        if (assetETag is not null) context.Response.Headers.ETag = assetETag;
        else if (intentETag is not null) context.Response.Headers.ETag = intentETag;
        var response = new ProjectAssetOperationResponse(
            result.Code,
            result.IntentPublicId,
            result.IntentStatus.HasValue ? (byte)result.IntentStatus.Value : null,
            result.AssetPublicId,
            result.StorageStatus.HasValue ? (byte)result.StorageStatus.Value : null,
            result.ScanStatus.HasValue ? (byte)result.ScanStatus.Value : null,
            result.ScanProvider.HasValue ? (byte)result.ScanProvider.Value : null,
            intentETag,
            assetETag,
            projectETag,
            result.WasReplay);
        if (result.Outcome == ProjectAssetOutcome.Processing)
        {
            context.Response.Headers.Location = statusUrl;
            context.Response.Headers.RetryAfter = "2";
            return Results.Accepted(statusUrl, response);
        }
        return Results.Ok(response);
    }

    private static IResult MapFailure(
        ProjectAssetOutcome outcome,
        string code,
        IReadOnlyDictionary<string, string[]>? errors) => outcome switch
    {
        ProjectAssetOutcome.Disabled => ProjectEndpointResults.Problem(
            503, "Adjuntos temporalmente deshabilitados",
            "La carga permanecerá cerrada hasta completar el circuito de análisis de seguridad.",
            "project-assets-disabled"),
        ProjectAssetOutcome.ValidationFailed => ProjectEndpointResults.Validation(
            422, "Adjunto inválido", code, errors),
        ProjectAssetOutcome.NotFound => ProjectEndpointResults.Problem(
            404, "Adjunto no encontrado", null, code),
        ProjectAssetOutcome.Forbidden => ProjectEndpointResults.Problem(
            403, "Acceso denegado", null, code),
        ProjectAssetOutcome.Expired => ProjectEndpointResults.Problem(
            410, "La autorización de carga venció", null, code),
        ProjectAssetOutcome.InvalidState => ProjectEndpointResults.Problem(
            409, "El proyecto no admite cambios",
            "Sólo se pueden modificar adjuntos en borradores o proyectos rechazados.", code),
        ProjectAssetOutcome.Conflict when code.Contains("etag", StringComparison.Ordinal) =>
            ProjectEndpointResults.Problem(
                412, "La versión cambió", "Recarga el proyecto e intenta nuevamente.", code),
        ProjectAssetOutcome.Conflict => ProjectEndpointResults.Problem(
            409, "El adjunto cambió", "Recarga el proyecto e intenta nuevamente.", code),
        _ => ProjectEndpointResults.Problem(
            503, "No fue posible procesar el adjunto", null, code)
    };

    private static bool TryDualETag(
        HttpContext context,
        out byte[] assetRowVersion,
        out byte[] projectRowVersion,
        out IResult? failure)
    {
        assetRowVersion = [];
        projectRowVersion = [];
        failure = null;
        if (!ProjectEndpointResults.TryParseETag(
                context.Request.Headers.IfMatch.FirstOrDefault(), out assetRowVersion))
        {
            failure = ProjectEndpointResults.PreconditionRequired(
                "asset-if-match-required", "Versión del adjunto requerida",
                "Envía el ETag vigente del adjunto en If-Match.");
            return false;
        }
        if (!ProjectEndpointResults.TryParseETag(
                context.Request.Headers[ProjectETagHeader].FirstOrDefault(), out projectRowVersion))
        {
            failure = ProjectEndpointResults.PreconditionRequired(
                "project-if-match-required", "Versión del proyecto requerida",
                $"Envía el ETag vigente del proyecto en {ProjectETagHeader}.");
            return false;
        }
        return true;
    }

    private static bool TryGetUserId(ClaimsPrincipal principal, out Guid userId) =>
        Guid.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out userId);

    private static string AssetBase(Guid organizationId, Guid projectId) =>
        $"/api/v1/organizations/{organizationId:D}/projects/{projectId:D}";

    private static string FormatETag(byte[] rowVersion) =>
        ProjectEndpointResults.FormatETag(rowVersion);

    private static string? OptionalETag(byte[]? rowVersion) =>
        rowVersion is { Length: 8 } ? FormatETag(rowVersion) : null;

    private static string SetProjectETag(HttpContext context, byte[] rowVersion)
    {
        var eTag = FormatETag(rowVersion);
        context.Response.Headers[ProjectResponseETagHeader] = eTag;
        return eTag;
    }
}
