using System.Globalization;
using System.Security.Claims;
using FundingPlatform.Application.Networking;
using FundingPlatform.Contracts.Networking;
using FundingPlatform.Core.Networking;

namespace FundingPlatform.Api.Endpoints;

public static class NetworkingEndpoints
{
    public static IEndpointRouteBuilder MapNetworkingEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/organizations/{organizationId:guid}/network")
            .WithTags("Organization networking")
            .RequireAuthorization("full-session");

        group.MapGet("/settings", GetSettingsAsync)
            .RequireRateLimiting("organization-activity-read")
            .WithName("GetNetworkingSettings")
            .Produces<NetworkingPreferenceResponse>()
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status429TooManyRequests);
        group.MapPut("/settings", PutSettingsAsync)
            .RequireRateLimiting("organization-write")
            .WithName("PutNetworkingSettings")
            .Produces<NetworkingPreferenceResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);
        group.MapGet("/directory", SearchDirectoryAsync)
            .RequireRateLimiting("organization-activity-read")
            .WithName("SearchOrganizationNetworkDirectory")
            .Produces<NetworkDirectoryPageResponse>()
            .ProducesValidationProblem()
            .ProducesProblem(StatusCodes.Status404NotFound);
        group.MapGet("/connections", ListConnectionsAsync)
            .RequireRateLimiting("organization-activity-read")
            .WithName("ListOrganizationConnections")
            .Produces<OrganizationConnectionPageResponse>()
            .ProducesValidationProblem()
            .ProducesProblem(StatusCodes.Status404NotFound);
        group.MapPost("/connections", CreateConnectionAsync)
            .RequireRateLimiting("network-connect-write")
            .WithName("CreateOrganizationConnection")
            .Produces<OrganizationConnectionResponse>(StatusCodes.Status201Created)
            .Produces<OrganizationConnectionResponse>(StatusCodes.Status200OK)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired)
            .ProducesProblem(StatusCodes.Status429TooManyRequests);
        group.MapGet("/connections/{connectionId:guid}", GetConnectionAsync)
            .RequireRateLimiting("organization-activity-read")
            .WithName("GetOrganizationConnection")
            .Produces<OrganizationConnectionResponse>()
            .ProducesProblem(StatusCodes.Status404NotFound);
        group.MapPatch("/connections/{connectionId:guid}", ActionConnectionAsync)
            .RequireRateLimiting("organization-write")
            .WithName("ActionOrganizationConnection")
            .Produces<OrganizationConnectionResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);
        return endpoints;
    }

    private static async Task<IResult> GetSettingsAsync(Guid organizationId,
        ClaimsPrincipal principal, HttpContext context, NetworkingService service,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        var value = await service.GetPreferenceAsync(userId, organizationId, cancellationToken);
        if (value is null) return NotFound();
        if (value.ETag is not null) context.Response.Headers.ETag = value.ETag;
        return Results.Ok(Map(value));
    }

    private static async Task<IResult> PutSettingsAsync(Guid organizationId,
        NetworkingPreferenceWriteRequest request, ClaimsPrincipal principal,
        HttpContext context, NetworkingService service, CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        byte[]? expected = null;
        var header = context.Request.Headers.IfMatch.ToString();
        if (!string.IsNullOrWhiteSpace(header) &&
            !ProjectEndpointResults.TryParseETag(header, out expected))
            return ProjectEndpointResults.PreconditionRequired("if-match-invalid",
                "Versión inválida", "Envía el ETag fuerte vigente o quita If-Match al activar por primera vez.");
        var result = await service.PutPreferenceAsync(userId, organizationId,
            request.IsDiscoverable, request.AllowRequests, expected, cancellationToken);
        if (result.Outcome is NetworkingMutationOutcome.Created or NetworkingMutationOutcome.Updated)
        {
            context.Response.Headers.ETag = result.Preference!.ETag;
            return Results.Ok(Map(result.Preference));
        }
        return MapFailure(result.Outcome, null);
    }

    private static async Task<IResult> SearchDirectoryAsync(Guid organizationId,
        string? q, string? countryIds, string? categoryIds, string? projectTypeIds,
        ClaimsPrincipal principal, NetworkingService service, CancellationToken cancellationToken,
        int page = 1, int pageSize = 20)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        if (!TryCsv<short>(countryIds, out var countries) ||
            !TryCsv<int>(categoryIds, out var categories) ||
            !TryCsv<int>(projectTypeIds, out var projectTypes))
            return Results.ValidationProblem(new Dictionary<string, string[]>
            { ["filters"] = ["Los identificadores deben ser enteros positivos separados por comas."] });
        var result = await service.SearchDirectoryAsync(userId, organizationId,
            new NetworkDirectoryFilters(q, countries, categories, projectTypes, page, pageSize),
            cancellationToken);
        if (result.Errors is not null) return Results.ValidationProblem(result.Errors);
        return result.Page is null ? NotFound() : Results.Ok(Map(result.Page));
    }

    private static async Task<IResult> ListConnectionsAsync(Guid organizationId,
        string? direction, string? status, ClaimsPrincipal principal,
        NetworkingService service, CancellationToken cancellationToken,
        int page = 1, int pageSize = 20)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        if (!TryDirection(direction, out var parsedDirection) ||
            !TryStatus(status, out var parsedStatus) || page is < 1 or > 10_000 ||
            pageSize is < 1 or > 50)
            return Results.ValidationProblem(new Dictionary<string, string[]>
            { ["filters"] = ["Dirección o estado no permitido."] });
        var result = await service.ListConnectionsAsync(userId, organizationId,
            parsedDirection, parsedStatus, page, pageSize, cancellationToken);
        return result is null ? NotFound() : Results.Ok(Map(result));
    }

    private static async Task<IResult> GetConnectionAsync(Guid organizationId, Guid connectionId,
        ClaimsPrincipal principal, HttpContext context, NetworkingService service,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        var result = await service.GetConnectionAsync(
            userId, organizationId, connectionId, cancellationToken);
        if (result is null) return NotFound();
        context.Response.Headers.ETag = result.ETag;
        return Results.Ok(Map(result));
    }

    private static async Task<IResult> CreateConnectionAsync(Guid organizationId,
        OrganizationConnectionCreateRequest request, ClaimsPrincipal principal,
        HttpContext context, NetworkingService service, CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        var key = context.Request.Headers["Idempotency-Key"].ToString();
        if (string.IsNullOrWhiteSpace(key))
            return ProjectEndpointResults.PreconditionRequired("idempotency-key-required",
                "Idempotency-Key requerida", "Envía una clave estable para crear la solicitud de conexión.");
        if (!TryPurpose(request.Purpose, out var purpose))
            return ProjectEndpointResults.Validation(StatusCodes.Status422UnprocessableEntity,
                "Solicitud inválida", "networking-validation",
                new Dictionary<string, string[]> { ["purpose"] = ["Propósito no permitido."] });
        var result = await service.CreateConnectionAsync(new CreateConnectionCommand(
            userId, organizationId, request.RecipientOrganizationId,
            request.RequesterProjectId, purpose, request.Message, key), cancellationToken);
        if (result.Outcome is NetworkingMutationOutcome.Created or NetworkingMutationOutcome.Replay)
        {
            var response = Map(result.Connection!);
            context.Response.Headers.ETag = response.ETag;
            return result.Outcome == NetworkingMutationOutcome.Replay
                ? Results.Ok(response)
                : Results.Created($"/api/v1/organizations/{organizationId:D}/network/connections/{response.Id:D}", response);
        }
        return MapFailure(result.Outcome, result.Errors);
    }

    private static async Task<IResult> ActionConnectionAsync(Guid organizationId,
        Guid connectionId, OrganizationConnectionActionRequest request,
        ClaimsPrincipal principal, HttpContext context, NetworkingService service,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
            return ProjectEndpointResults.InvalidSession();
        if (!ProjectEndpointResults.TryParseETag(context.Request.Headers.IfMatch,
                out var expectedRowVersion))
            return ProjectEndpointResults.PreconditionRequired("if-match-required",
                "Versión requerida", "Recarga la solicitud y envía su ETag vigente.");
        if (!TryAction(request.Action, out var action))
            return ProjectEndpointResults.Validation(StatusCodes.Status422UnprocessableEntity,
                "Acción inválida", "networking-validation",
                new Dictionary<string, string[]> { ["action"] = ["Acción no permitida."] });
        var result = await service.ActionConnectionAsync(userId, organizationId,
            connectionId, action, expectedRowVersion, cancellationToken);
        if (result.Outcome == NetworkingMutationOutcome.Updated)
        {
            var response = Map(result.Connection!);
            context.Response.Headers.ETag = response.ETag;
            return Results.Ok(response);
        }
        return MapFailure(result.Outcome, result.Errors);
    }

    private static IResult MapFailure(NetworkingMutationOutcome outcome,
        IReadOnlyDictionary<string, string[]>? errors) => outcome switch
    {
        NetworkingMutationOutcome.ValidationFailed => ProjectEndpointResults.Validation(422,
            "Solicitud inválida", "networking-validation", errors),
        NetworkingMutationOutcome.NotFound => NotFound(),
        NetworkingMutationOutcome.Forbidden => ProjectEndpointResults.Problem(403,
            "Se requiere administración de la organización", null, "networking-forbidden"),
        NetworkingMutationOutcome.PreconditionRequired => ProjectEndpointResults.PreconditionRequired(
            "if-match-required", "Versión requerida", "Envía el ETag vigente."),
        NetworkingMutationOutcome.PreconditionFailed => ProjectEndpointResults.Problem(412,
            "La configuración cambió", "Recarga e intenta nuevamente.", "networking-precondition-failed"),
        NetworkingMutationOutcome.IdempotencyConflict => ProjectEndpointResults.Problem(409,
            "Conflicto de idempotencia", "La clave ya fue utilizada con otros datos.", "idempotency-conflict"),
        NetworkingMutationOutcome.AlreadyExists => ProjectEndpointResults.Problem(409,
            "Ya existe una conexión activa", null, "networking-already-exists"),
        NetworkingMutationOutcome.NetworkingDisabled => ProjectEndpointResults.Problem(422,
            "Networking desactivado", "Activa la visibilidad antes de conectar.", "networking-disabled"),
        NetworkingMutationOutcome.RateLimited => ProjectEndpointResults.Problem(429,
            "Límite de solicitudes alcanzado", "Inténtalo más tarde.", "networking-rate-limit"),
        NetworkingMutationOutcome.InvalidTransition => ProjectEndpointResults.Problem(409,
            "Acción no permitida", "El estado actual ya no admite esa acción.", "networking-invalid-transition"),
        _ => ProjectEndpointResults.Problem(500, "No fue posible completar la operación", null,
            "networking-failed")
    };

    private static NetworkingPreferenceResponse Map(NetworkingPreference value) => new(
        value.Exists, value.IsDiscoverable, value.AllowRequests, value.CreatedAtUtc,
        value.UpdatedAtUtc, value.ETag);

    private static NetworkDirectoryPageResponse Map(NetworkDirectoryPage page) => new(
        page.Items.Select(value => new NetworkDirectoryOrganizationResponse(value.PublicId,
            value.Name, value.Description, value.WebsiteUrl, Map(value.HomeCountry),
            Map(value.OrganizationType), value.VisibleProjectCount, value.AllowsRequests,
            value.ConnectionPublicId,
            DirectoryState(value.ConnectionState), value.Categories.Select(Map).ToArray(),
            value.ProjectTypes.Select(Map).ToArray())).ToArray(),
        page.TotalCount, page.PageNumber, page.PageSize);

    private static OrganizationConnectionPageResponse Map(OrganizationConnectionPage page) =>
        new(page.Items.Select(Map).ToArray(), page.TotalCount, page.PageNumber, page.PageSize);

    private static OrganizationConnectionResponse Map(OrganizationConnection value) => new(
        value.PublicId, Direction(value.Direction), Status(value.Status), Purpose(value.Purpose),
        value.Message, value.CounterpartyOrganizationPublicId, value.CounterpartyOrganizationName,
        value.CounterpartyIsPublic, value.RequesterProjectPublicId, value.RequesterProjectSlug,
        value.RequesterProjectTitle, value.CanRespond, value.CanCancel, value.CanBlock,
        value.CreatedAtUtc, value.UpdatedAtUtc, value.ActionedAtUtc, value.ETag);

    private static NetworkCatalogItemResponse<T> Map<T>(NetworkCatalogItem<T> value) =>
        new(value.Id, value.Code, value.Name);
    private static string DirectoryState(DirectoryConnectionState value) => value switch
    { DirectoryConnectionState.PendingOutgoing => "pending-outgoing", DirectoryConnectionState.PendingIncoming => "pending-incoming", DirectoryConnectionState.Connected => "connected", _ => "none" };
    private static string Direction(ConnectionDirection value) => value == ConnectionDirection.Incoming ? "incoming" : "outgoing";
    private static string Status(OrganizationConnectionStatus value) => value.ToString().ToLowerInvariant();
    private static string Purpose(ConnectionPurpose value) => value switch
    { ConnectionPurpose.GeographicReach => "geographic-reach", ConnectionPurpose.ConsortiumExploration => "consortium-exploration", _ => value.ToString().ToLowerInvariant() };

    private static bool TryPurpose(string? value, out ConnectionPurpose result) =>
        EnumTry(value, new Dictionary<string, ConnectionPurpose>(StringComparer.Ordinal)
        { ["partnership"] = ConnectionPurpose.Partnership, ["expertise"] = ConnectionPurpose.Expertise,
          ["geographic-reach"] = ConnectionPurpose.GeographicReach,
          ["consortium-exploration"] = ConnectionPurpose.ConsortiumExploration }, out result);
    private static bool TryAction(string? value, out OrganizationConnectionStatus result) =>
        EnumTry(value, new Dictionary<string, OrganizationConnectionStatus>(StringComparer.Ordinal)
        { ["accept"] = OrganizationConnectionStatus.Accepted, ["reject"] = OrganizationConnectionStatus.Rejected,
          ["cancel"] = OrganizationConnectionStatus.Cancelled, ["block"] = OrganizationConnectionStatus.Blocked }, out result);
    private static bool TryDirection(string? value, out ConnectionDirection result) =>
        EnumTry(string.IsNullOrWhiteSpace(value) ? "all" : value,
            new Dictionary<string, ConnectionDirection>(StringComparer.Ordinal)
            { ["all"] = ConnectionDirection.All, ["incoming"] = ConnectionDirection.Incoming,
              ["outgoing"] = ConnectionDirection.Outgoing }, out result);
    private static bool TryStatus(string? value, out OrganizationConnectionStatus? result)
    {
        result = null;
        if (string.IsNullOrWhiteSpace(value)) return true;
        var map = Enum.GetValues<OrganizationConnectionStatus>()
            .ToDictionary(item => item.ToString().ToLowerInvariant(), item => item, StringComparer.Ordinal);
        if (!map.TryGetValue(value, out var parsed)) return false;
        result = parsed; return true;
    }
    private static bool EnumTry<T>(string? value, IReadOnlyDictionary<string, T> values, out T result)
    {
        if (value is not null && values.TryGetValue(value, out result!)) return true;
        result = default!; return false;
    }

    private static bool TryCsv<T>(string? value, out IReadOnlyList<T> result)
        where T : struct, IParsable<T>, IComparable<T>
    {
        result = [];
        if (string.IsNullOrWhiteSpace(value)) return true;
        var parts = value.Split(',');
        if (parts.Length > NetworkingService.MaximumFilterValues) return false;
        var values = new List<T>();
        foreach (var part in parts)
        {
            if (part.Length == 0 || part != part.Trim() || !part.All(char.IsAsciiDigit) ||
                !T.TryParse(part, CultureInfo.InvariantCulture, out var parsed) ||
                parsed.CompareTo(default) <= 0) return false;
            values.Add(parsed);
        }
        result = values; return true;
    }

    private static IResult NotFound() => ProjectEndpointResults.Problem(404,
        "Espacio de networking no encontrado", null, "networking-not-found");
}
