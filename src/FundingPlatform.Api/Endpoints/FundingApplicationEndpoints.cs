using System.Security.Claims;
using FundingPlatform.Application.Applications;
using FundingPlatform.Contracts.Applications;
using FundingPlatform.Core.Applications;

namespace FundingPlatform.Api.Endpoints;

public static class FundingApplicationEndpoints
{
    public static IEndpointRouteBuilder MapFundingApplicationEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        var organizations = endpoints
            .MapGroup("/api/v1/organizations/{organizationId:guid}")
            .WithTags("Organization applications and calendar")
            .RequireAuthorization("full-session");

        organizations.MapGet("/applications", ListAsync)
            .RequireRateLimiting("organization-activity-read")
            .WithName("ListFundingApplications")
            .WithSummary("Lists the authorized organization's applications with server-side paging.")
            .Produces<FundingApplicationPageResponse>()
            .ProducesValidationProblem()
            .ProducesProblem(StatusCodes.Status401Unauthorized)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status429TooManyRequests);
        organizations.MapPost("/applications", CreateAsync)
            .RequireRateLimiting("organization-write")
            .WithName("CreateFundingApplication")
            .WithSummary("Creates an Interested application with durable idempotency.")
            .Produces<FundingApplicationResponse>(StatusCodes.Status201Created)
            .Produces<FundingApplicationResponse>(StatusCodes.Status200OK)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired)
            .ProducesProblem(StatusCodes.Status429TooManyRequests);
        organizations.MapGet("/applications/{applicationId:guid}", GetAsync)
            .RequireRateLimiting("organization-activity-read")
            .WithName("GetFundingApplication")
            .WithSummary("Gets an application in an authorized organization context.")
            .Produces<FundingApplicationResponse>()
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status429TooManyRequests);
        organizations.MapPatch("/applications/{applicationId:guid}", UpdateAsync)
            .RequireRateLimiting("organization-write")
            .WithName("UpdateFundingApplication")
            .WithSummary("Updates the complete mutable application snapshot with optimistic concurrency.")
            .Produces<FundingApplicationResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired)
            .ProducesProblem(StatusCodes.Status429TooManyRequests);
        organizations.MapGet("/calendar", GetCalendarAsync)
            .RequireRateLimiting("organization-activity-read")
            .WithName("GetOrganizationFundingCalendar")
            .WithSummary("Gets a basic calendar derived from applications, projects and favorites.")
            .Produces<FundingCalendarResponse>()
            .ProducesValidationProblem()
            .ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status429TooManyRequests);

        return endpoints;
    }

    private static async Task<IResult> ListAsync(
        Guid organizationId,
        byte? status,
        Guid? projectId,
        Guid? fundingOpportunityId,
        ClaimsPrincipal principal,
        FundingApplicationService service,
        CancellationToken cancellationToken,
        int page = 1,
        int pageSize = 20)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
        {
            return ProjectEndpointResults.InvalidSession();
        }

        var result = await service.ListAsync(
            userId,
            organizationId,
            new FundingApplicationListFilters(
                status.HasValue ? (FundingApplicationStatus)status.Value : null,
                projectId,
                fundingOpportunityId,
                page,
                pageSize),
            cancellationToken);
        return result.Outcome switch
        {
            FundingApplicationOutcome.Success => Results.Ok(Map(result.Page!)),
            FundingApplicationOutcome.ValidationFailed => Results.ValidationProblem(result.Errors!),
            _ => NotFound()
        };
    }

    private static async Task<IResult> GetAsync(
        Guid organizationId,
        Guid applicationId,
        ClaimsPrincipal principal,
        HttpContext context,
        FundingApplicationService service,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
        {
            return ProjectEndpointResults.InvalidSession();
        }

        var result = await service.GetAsync(
            userId,
            organizationId,
            applicationId,
            cancellationToken);
        if (result.Outcome != FundingApplicationOutcome.Success)
        {
            return NotFound();
        }

        var response = Map(result.Application!);
        context.Response.Headers.ETag = response.ETag;
        return Results.Ok(response);
    }

    private static async Task<IResult> CreateAsync(
        Guid organizationId,
        CreateFundingApplicationRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        FundingApplicationService service,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
        {
            return ProjectEndpointResults.InvalidSession();
        }

        var idempotencyKey = context.Request.Headers["Idempotency-Key"].ToString();
        if (string.IsNullOrWhiteSpace(idempotencyKey))
        {
            return ProjectEndpointResults.PreconditionRequired(
                "idempotency-key-required",
                "Idempotency-Key requerida",
                "Envía una clave única para crear la postulación de forma segura.");
        }

        var result = await service.CreateAsync(
            userId,
            organizationId,
            request.ProjectId,
            request.FundingOpportunityId,
            idempotencyKey,
            new FundingApplicationData(
                FundingApplicationStatus.Interested,
                request.Notes,
                request.ApplicationDate,
                request.RequestedAmount,
                request.Currency,
                request.ResultDate),
            cancellationToken);
        if (result.Outcome != FundingApplicationOutcome.Success)
        {
            return MapFailure(result, isUpdate: false);
        }

        var response = Map(result.Application!);
        context.Response.Headers.ETag = response.ETag;
        if (result.WasReplay)
        {
            return Results.Ok(response);
        }

        return Results.Created(
            $"/api/v1/organizations/{organizationId:D}/applications/{response.PublicId:D}",
            response);
    }

    private static async Task<IResult> UpdateAsync(
        Guid organizationId,
        Guid applicationId,
        UpdateFundingApplicationRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        FundingApplicationService service,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
        {
            return ProjectEndpointResults.InvalidSession();
        }

        if (!ProjectEndpointResults.TryParseETag(
                context.Request.Headers.IfMatch,
                out var expectedRowVersion))
        {
            return ProjectEndpointResults.PreconditionRequired(
                "if-match-required",
                "Versión requerida",
                "Recarga la postulación y envía su ETag actual en If-Match.");
        }

        var result = await service.UpdateAsync(
            userId,
            organizationId,
            applicationId,
            expectedRowVersion,
            new FundingApplicationData(
                (FundingApplicationStatus)request.Status,
                request.Notes,
                request.ApplicationDate,
                request.RequestedAmount,
                request.Currency,
                request.ResultDate),
            cancellationToken);
        if (result.Outcome != FundingApplicationOutcome.Success)
        {
            return MapFailure(result, isUpdate: true);
        }

        var response = Map(result.Application!);
        context.Response.Headers.ETag = response.ETag;
        return Results.Ok(response);
    }

    private static async Task<IResult> GetCalendarAsync(
        Guid organizationId,
        DateOnly? from,
        DateOnly? to,
        ClaimsPrincipal principal,
        FundingApplicationService service,
        CancellationToken cancellationToken)
    {
        if (!ProjectEndpointResults.TryGetUserId(principal, out var userId))
        {
            return ProjectEndpointResults.InvalidSession();
        }

        if (!from.HasValue || !to.HasValue)
        {
            return Results.ValidationProblem(new Dictionary<string, string[]>
            {
                [!from.HasValue ? "from" : "to"] = ["Indica ambas fechas en formato YYYY-MM-DD."]
            });
        }

        var result = await service.ListCalendarAsync(
            userId,
            organizationId,
            from.Value,
            to.Value,
            cancellationToken);
        return result.Outcome switch
        {
            FundingApplicationOutcome.Success => Results.Ok(new FundingCalendarResponse(
                result.From,
                result.To,
                result.Items.Select(Map).ToArray())),
            FundingApplicationOutcome.ValidationFailed => Results.ValidationProblem(result.Errors!),
            _ => NotFound()
        };
    }

    private static IResult MapFailure(
        FundingApplicationDetailsResult result,
        bool isUpdate) => result.Outcome switch
    {
        FundingApplicationOutcome.ValidationFailed => ProjectEndpointResults.Validation(
            StatusCodes.Status422UnprocessableEntity,
            "Solicitud inválida",
            "funding-application-validation",
            result.Errors),
        FundingApplicationOutcome.NotFound => NotFound(),
        FundingApplicationOutcome.IdempotencyConflict => ProjectEndpointResults.Problem(
            StatusCodes.Status409Conflict,
            "Conflicto de idempotencia",
            "La misma Idempotency-Key ya se utilizó con otros datos.",
            "idempotency-conflict"),
        FundingApplicationOutcome.PreconditionFailed => ProjectEndpointResults.Problem(
            StatusCodes.Status412PreconditionFailed,
            "La postulación cambió",
            "Recarga la postulación e intenta nuevamente.",
            "funding-application-precondition-failed"),
        FundingApplicationOutcome.Conflict when isUpdate => ProjectEndpointResults.Problem(
            StatusCodes.Status409Conflict,
            "La postulación cambió",
            "Recarga la postulación e intenta nuevamente.",
            "funding-application-concurrency-conflict"),
        _ => ProjectEndpointResults.Problem(
            StatusCodes.Status409Conflict,
            "La postulación ya existe",
            "Ya existe una postulación para este proyecto y fondo.",
            "funding-application-conflict")
    };

    private static FundingApplicationPageResponse Map(FundingApplicationPage page) =>
        new(page.Items.Select(Map).ToArray(), page.TotalCount, page.PageNumber, page.PageSize);

    private static FundingApplicationResponse Map(FundingApplicationDetails application) =>
        new(
            application.PublicId,
            new FundingApplicationProjectResponse(
                application.Project.PublicId,
                application.Project.Slug,
                application.Project.Title),
            new FundingApplicationOpportunityResponse(
                application.FundingOpportunity.PublicId,
                application.FundingOpportunity.Slug,
                application.FundingOpportunity.Title,
                application.FundingOpportunity.SponsorName,
                application.FundingOpportunity.CloseDate,
                application.FundingOpportunity.CloseAtUtc,
                application.FundingOpportunity.DeadlinePrecision),
            (byte)application.Status,
            application.Notes,
            application.ApplicationDate,
            application.RequestedAmount,
            application.Currency,
            application.ResultDate,
            application.OwnerUserPublicId,
            application.CanEdit,
            application.CreatedAtUtc,
            application.UpdatedAtUtc,
            ProjectEndpointResults.FormatETag(application.RowVersion));

    private static FundingCalendarItemResponse Map(FundingCalendarItem item) =>
        new(
            item.EventKey,
            item.EventType,
            item.EventDate,
            item.EventAtUtc,
            item.DatePrecision,
            item.Title,
            item.Status.HasValue ? (byte)item.Status.Value : null,
            item.FundingApplicationPublicId,
            item.ProjectPublicId,
            item.FundingOpportunityPublicId);

    private static IResult NotFound() => ProjectEndpointResults.Problem(
        StatusCodes.Status404NotFound,
        "Postulación no encontrada",
        null,
        "funding-application-not-found");
}
