using System.Security.Claims;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Contracts.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Api.Endpoints;

public static class AdminFundingEditorialEndpoints
{
    public static IEndpointRouteBuilder MapAdminFundingEditorialEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        var funders = endpoints.MapGroup("/api/v1/admin/funders")
            .WithTags("Admin Funders")
            .RequireAuthorization("admin-mfa");

        funders.MapGet("/", ListFundersAsync)
            .Produces<FunderListResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden);
        funders.MapPost("/", CreateFunderAsync)
            .RequireRateLimiting("organization-write")
            .Produces<FundingEditorialMutationResponse>(StatusCodes.Status201Created)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);
        funders.MapGet("/{funderId:guid}", GetFunderAsync)
            .Produces<FunderAdminDetailResponse>()
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound);
        funders.MapPut("/{funderId:guid}", UpdateFunderAsync)
            .RequireRateLimiting("organization-write")
            .Produces<FundingEditorialMutationResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);
        funders.MapPost("/{funderId:guid}/submit-review", SubmitFunderReviewAsync)
            .RequireRateLimiting("organization-write")
            .Produces<FundingEditorialMutationResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);
        funders.MapPost("/{funderId:guid}/reviews", ReviewFunderAsync)
            .RequireRateLimiting("organization-write")
            .Produces<FundingEditorialMutationResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);
        funders.MapPost("/{funderId:guid}/start-correction", StartFunderCorrectionAsync)
            .RequireRateLimiting("organization-write")
            .Produces<FundingEditorialMutationResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);
        funders.MapPost("/{funderId:guid}/deactivate", DeactivateFunderAsync)
            .RequireRateLimiting("organization-write")
            .Produces<FundingEditorialMutationResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);

        var opportunities = endpoints.MapGroup("/api/v1/admin/funding-opportunities")
            .WithTags("Admin Funding Opportunities")
            .RequireAuthorization("admin-mfa");

        opportunities.MapGet("/", ListOpportunitiesAsync)
            .Produces<FundingOpportunityAdminListResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden);
        opportunities.MapPost("/", CreateOpportunityAsync)
            .RequireRateLimiting("organization-write")
            .Produces<FundingEditorialMutationResponse>(StatusCodes.Status201Created)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);
        opportunities.MapGet("/{opportunityId:guid}", GetOpportunityAsync)
            .Produces<FundingOpportunityAdminDetailResponse>()
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .ProducesProblem(StatusCodes.Status404NotFound);
        opportunities.MapPut("/{opportunityId:guid}", UpdateOpportunityAsync)
            .RequireRateLimiting("organization-write")
            .Produces<FundingEditorialMutationResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);
        opportunities.MapPost("/{opportunityId:guid}/submit-review", SubmitOpportunityReviewAsync)
            .RequireRateLimiting("organization-write")
            .Produces<FundingEditorialMutationResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);
        opportunities.MapPost("/{opportunityId:guid}/reviews", ReviewOpportunityAsync)
            .RequireRateLimiting("organization-write")
            .Produces<FundingEditorialMutationResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);
        opportunities.MapPost("/{opportunityId:guid}/start-correction", StartOpportunityCorrectionAsync)
            .RequireRateLimiting("organization-write")
            .Produces<FundingEditorialMutationResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);
        opportunities.MapPost("/{opportunityId:guid}/deactivate", DeactivateOpportunityAsync)
            .RequireRateLimiting("organization-write")
            .Produces<FundingEditorialMutationResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status412PreconditionFailed)
            .ProducesProblem(StatusCodes.Status409Conflict)
            .ProducesProblem(StatusCodes.Status428PreconditionRequired);

        endpoints.MapGet("/api/v1/admin/funding-sources", ListFundingSourcesAsync)
            .WithTags("Admin Funding Sources")
            .RequireAuthorization("admin-mfa")
            .Produces<IReadOnlyList<FundingSourceAdminResponse>>()
            .ProducesProblem(StatusCodes.Status403Forbidden);

        return endpoints;
    }

    private static async Task<IResult> ListFundersAsync(
        ClaimsPrincipal principal,
        FunderEditorialService service,
        CancellationToken cancellationToken,
        string? query = null,
        byte? status = null,
        bool includeInactive = false,
        int page = 1,
        int pageSize = 50)
    {
        if (!TryGetUser(principal, out var userId, out var sessionError)) return sessionError!;
        if (!TryValidateList(query, status, page, pageSize, out var publicationStatus, out var validationError))
            return validationError!;

        var result = await service.ListAdminAsync(
            userId, query, publicationStatus, includeInactive, page, pageSize, cancellationToken);
        if (result.Outcome == FundingEditorialOutcome.Forbidden)
            return Forbidden();
        if (result.Value is null)
            return ProjectEndpointResults.Problem(500, "No fue posible listar funders", null,
                "funder-list-failed");
        return Results.Ok(new FunderListResponse(
            result.Value.Items.Select(Map).ToArray(),
            result.Value.TotalCount,
            result.Value.PageNumber,
            result.Value.PageSize));
    }

    private static async Task<IResult> GetFunderAsync(
        Guid funderId,
        ClaimsPrincipal principal,
        HttpContext context,
        FunderEditorialService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUser(principal, out var userId, out var sessionError)) return sessionError!;
        var result = await service.GetAdminAsync(userId, funderId, cancellationToken);
        if (result.Outcome == FundingEditorialOutcome.Forbidden) return Forbidden();
        if (result.Value is null)
            return ProjectEndpointResults.Problem(404, "Funder no encontrado", null, "funder-not-found");
        context.Response.Headers.ETag = ProjectEndpointResults.FormatETag(result.Value.RowVersion);
        return Results.Ok(Map(result.Value));
    }

    private static async Task<IResult> CreateFunderAsync(
        FunderWriteRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        FunderEditorialService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUser(principal, out var userId, out var sessionError)) return sessionError!;
        if (!FundingEditorialEndpointResults.TryGetMutationHeaders(
                context, false, out _, out var idempotencyKey, out var headerError))
            return headerError!;
        var result = await service.CreateAsync(
            userId, Map(request), idempotencyKey, cancellationToken);
        return FundingEditorialEndpointResults.MapCreated(
            result, context, "Funder", "funder-not-found",
            $"/api/v1/admin/funders/{result.EntityPublicId:D}");
    }

    private static async Task<IResult> UpdateFunderAsync(
        Guid funderId,
        FunderWriteRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        FunderEditorialService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUser(principal, out var userId, out var sessionError)) return sessionError!;
        if (!FundingEditorialEndpointResults.TryGetMutationHeaders(
                context, true, out var rowVersion, out var idempotencyKey, out var headerError))
            return headerError!;
        var result = await service.UpdateAsync(
            userId, funderId, rowVersion, Map(request), idempotencyKey, cancellationToken);
        return FundingEditorialEndpointResults.MapCommand(
            result, context, "Funder", "funder-not-found");
    }

    private static Task<IResult> SubmitFunderReviewAsync(
        Guid funderId,
        ClaimsPrincipal principal,
        HttpContext context,
        FunderEditorialService service,
        CancellationToken cancellationToken) => ExecuteFunderWorkflowAsync(
        funderId, principal, context, service,
        static (targetService, userId, entityId, rowVersion, key, token) =>
            targetService.RequestPublicationAsync(userId, entityId, rowVersion, key, token),
        cancellationToken);

    private static async Task<IResult> ReviewFunderAsync(
        Guid funderId,
        FundingEditorialReviewRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        FunderEditorialService service,
        CancellationToken cancellationToken)
    {
        if (!TryParseDecision(request.Decision, out var decision, out var decisionError))
            return decisionError!;
        return await ExecuteFunderWorkflowAsync(
            funderId, principal, context, service,
            (targetService, userId, entityId, rowVersion, key, token) =>
                targetService.ReviewAsync(
                    userId, entityId, decision, request.Reason, rowVersion, key, token),
            cancellationToken);
    }

    private static async Task<IResult> DeactivateFunderAsync(
        Guid funderId,
        FundingEditorialDeactivateRequest? request,
        ClaimsPrincipal principal,
        HttpContext context,
        FunderEditorialService service,
        CancellationToken cancellationToken) => await ExecuteFunderWorkflowAsync(
        funderId, principal, context, service,
        (targetService, userId, entityId, rowVersion, key, token) =>
            targetService.DeactivateAsync(
                userId, entityId, request?.Reason, rowVersion, key, token),
        cancellationToken);

    private static async Task<IResult> StartFunderCorrectionAsync(
        Guid funderId,
        FundingEditorialStartCorrectionRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        FunderEditorialService service,
        CancellationToken cancellationToken) => await ExecuteFunderWorkflowAsync(
        funderId, principal, context, service,
        (targetService, userId, entityId, rowVersion, key, token) =>
            targetService.StartCorrectionAsync(
                userId, entityId, request.Reason, rowVersion, key, token),
        cancellationToken);

    private static async Task<IResult> ExecuteFunderWorkflowAsync(
        Guid funderId,
        ClaimsPrincipal principal,
        HttpContext context,
        FunderEditorialService service,
        Func<FunderEditorialService, Guid, Guid, byte[], string, CancellationToken,
            Task<FundingEditorialCommandResult>> execute,
        CancellationToken cancellationToken)
    {
        if (!TryGetUser(principal, out var userId, out var sessionError)) return sessionError!;
        if (!FundingEditorialEndpointResults.TryGetMutationHeaders(
                context, true, out var rowVersion, out var idempotencyKey, out var headerError))
            return headerError!;
        var result = await execute(
            service, userId, funderId, rowVersion, idempotencyKey, cancellationToken);
        return FundingEditorialEndpointResults.MapCommand(
            result, context, "Funder", "funder-not-found");
    }

    private static async Task<IResult> ListOpportunitiesAsync(
        ClaimsPrincipal principal,
        FundingOpportunityEditorialService service,
        CancellationToken cancellationToken,
        string? query = null,
        byte? status = null,
        bool includeInactive = false,
        int page = 1,
        int pageSize = 50)
    {
        if (!TryGetUser(principal, out var userId, out var sessionError)) return sessionError!;
        if (!TryValidateList(query, status, page, pageSize, out var publicationStatus, out var validationError))
            return validationError!;
        var result = await service.ListAdminAsync(
            userId, query, publicationStatus, includeInactive, page, pageSize, cancellationToken);
        if (result.Outcome == FundingEditorialOutcome.Forbidden) return Forbidden();
        if (result.Value is null)
            return ProjectEndpointResults.Problem(500, "No fue posible listar oportunidades", null,
                "funding-opportunity-list-failed");
        return Results.Ok(new FundingOpportunityAdminListResponse(
            result.Value.Items.Select(Map).ToArray(),
            result.Value.TotalCount,
            result.Value.PageNumber,
            result.Value.PageSize));
    }

    private static async Task<IResult> GetOpportunityAsync(
        Guid opportunityId,
        ClaimsPrincipal principal,
        HttpContext context,
        FundingOpportunityEditorialService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUser(principal, out var userId, out var sessionError)) return sessionError!;
        var result = await service.GetAdminAsync(userId, opportunityId, cancellationToken);
        if (result.Outcome == FundingEditorialOutcome.Forbidden) return Forbidden();
        if (result.Value is null)
            return ProjectEndpointResults.Problem(
                404, "Oportunidad no encontrada", null, "funding-opportunity-not-found");
        context.Response.Headers.ETag = ProjectEndpointResults.FormatETag(result.Value.RowVersion);
        return Results.Ok(Map(result.Value));
    }

    private static async Task<IResult> CreateOpportunityAsync(
        FundingOpportunityWriteRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        FundingOpportunityEditorialService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUser(principal, out var userId, out var sessionError)) return sessionError!;
        if (!FundingEditorialEndpointResults.TryGetMutationHeaders(
                context, false, out _, out var idempotencyKey, out var headerError))
            return headerError!;
        var result = await service.CreateAsync(
            userId, Map(request), idempotencyKey, cancellationToken);
        return FundingEditorialEndpointResults.MapCreated(
            result, context, "Oportunidad", "funding-opportunity-not-found",
            $"/api/v1/admin/funding-opportunities/{result.EntityPublicId:D}");
    }

    private static async Task<IResult> UpdateOpportunityAsync(
        Guid opportunityId,
        FundingOpportunityWriteRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        FundingOpportunityEditorialService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUser(principal, out var userId, out var sessionError)) return sessionError!;
        if (!FundingEditorialEndpointResults.TryGetMutationHeaders(
                context, true, out var rowVersion, out var idempotencyKey, out var headerError))
            return headerError!;
        var result = await service.UpdateAsync(
            userId, opportunityId, rowVersion, Map(request), idempotencyKey, cancellationToken);
        return FundingEditorialEndpointResults.MapCommand(
            result, context, "Oportunidad", "funding-opportunity-not-found");
    }

    private static Task<IResult> SubmitOpportunityReviewAsync(
        Guid opportunityId,
        ClaimsPrincipal principal,
        HttpContext context,
        FundingOpportunityEditorialService service,
        CancellationToken cancellationToken) => ExecuteOpportunityWorkflowAsync(
        opportunityId, principal, context, service,
        static (targetService, userId, entityId, rowVersion, key, token) =>
            targetService.RequestPublicationAsync(userId, entityId, rowVersion, key, token),
        cancellationToken);

    private static async Task<IResult> ReviewOpportunityAsync(
        Guid opportunityId,
        FundingEditorialReviewRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        FundingOpportunityEditorialService service,
        CancellationToken cancellationToken)
    {
        if (!TryParseDecision(request.Decision, out var decision, out var decisionError))
            return decisionError!;
        return await ExecuteOpportunityWorkflowAsync(
            opportunityId, principal, context, service,
            (targetService, userId, entityId, rowVersion, key, token) =>
                targetService.ReviewAsync(
                    userId, entityId, decision, request.Reason, rowVersion, key, token),
            cancellationToken);
    }

    private static async Task<IResult> DeactivateOpportunityAsync(
        Guid opportunityId,
        FundingEditorialDeactivateRequest? request,
        ClaimsPrincipal principal,
        HttpContext context,
        FundingOpportunityEditorialService service,
        CancellationToken cancellationToken) => await ExecuteOpportunityWorkflowAsync(
        opportunityId, principal, context, service,
        (targetService, userId, entityId, rowVersion, key, token) =>
            targetService.DeactivateAsync(
                userId, entityId, request?.Reason, rowVersion, key, token),
        cancellationToken);

    private static async Task<IResult> StartOpportunityCorrectionAsync(
        Guid opportunityId,
        FundingEditorialStartCorrectionRequest request,
        ClaimsPrincipal principal,
        HttpContext context,
        FundingOpportunityEditorialService service,
        CancellationToken cancellationToken) => await ExecuteOpportunityWorkflowAsync(
        opportunityId, principal, context, service,
        (targetService, userId, entityId, rowVersion, key, token) =>
            targetService.StartCorrectionAsync(
                userId, entityId, request.Reason, rowVersion, key, token),
        cancellationToken);

    private static async Task<IResult> ExecuteOpportunityWorkflowAsync(
        Guid opportunityId,
        ClaimsPrincipal principal,
        HttpContext context,
        FundingOpportunityEditorialService service,
        Func<FundingOpportunityEditorialService, Guid, Guid, byte[], string, CancellationToken,
            Task<FundingEditorialCommandResult>> execute,
        CancellationToken cancellationToken)
    {
        if (!TryGetUser(principal, out var userId, out var sessionError)) return sessionError!;
        if (!FundingEditorialEndpointResults.TryGetMutationHeaders(
                context, true, out var rowVersion, out var idempotencyKey, out var headerError))
            return headerError!;
        var result = await execute(
            service, userId, opportunityId, rowVersion, idempotencyKey, cancellationToken);
        return FundingEditorialEndpointResults.MapCommand(
            result, context, "Oportunidad", "funding-opportunity-not-found");
    }

    private static async Task<IResult> ListFundingSourcesAsync(
        ClaimsPrincipal principal,
        FundingSourceAdminService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetUser(principal, out var userId, out var sessionError)) return sessionError!;
        var result = await service.ListAsync(userId, cancellationToken);
        if (result.Outcome == FundingEditorialOutcome.Forbidden) return Forbidden();
        return Results.Ok((result.Value ?? []).Select(source => new FundingSourceAdminResponse(
            source.Id,
            source.Name,
            source.ProviderType,
            source.BaseUrl,
            source.IsEnabled,
            source.ProviderCode,
            source.ComplianceStatus,
            source.NextRunAtUtc,
            source.LastSuccessfulRunAtUtc,
            source.LicenseStatus,
            source.LicenseName,
            source.LicenseUrl,
            source.LicenseReviewedAtUtc,
            source.LicenseExpiresAtUtc,
            source.RobotsPolicyStatus,
            source.RobotsReviewedAtUtc,
            source.RobotsExpiresAtUtc,
            source.RequestRateLimitPerMinute,
            source.MaximumResponseBytes,
            source.ContentRetentionDays,
            source.AllowedHostsRequired,
            source.AcquisitionPolicyVersion,
            source.EnabledAllowedHostCount,
            source.AcquisitionReady)).ToArray());
    }

    private static FunderData Map(FunderWriteRequest request) => new(
        request.Name,
        request.Description,
        request.WebsiteUrl,
        request.CountryId,
        request.Aliases ?? []);

    private static FundingOpportunityEditorialData Map(FundingOpportunityWriteRequest request)
    {
        var amountStatus = request.AmountStatus.HasValue
            ? (FundingAmountStatus)request.AmountStatus.Value
            : request.MinimumAmount.HasValue || request.MaximumAmount.HasValue
                ? FundingAmountStatus.Specified
                : FundingAmountStatus.Unknown;
        var deadlineType = request.DeadlineType.HasValue
            ? (FundingDeadlineType)request.DeadlineType.Value
            : request.CloseDate.HasValue || request.CloseAtUtc.HasValue
                ? FundingDeadlineType.Fixed
                : FundingDeadlineType.Unknown;
        var deadlinePrecision = request.DeadlinePrecision.HasValue
            ? (FundingDeadlinePrecision)request.DeadlinePrecision.Value
            : request.CloseAtUtc.HasValue
                ? FundingDeadlinePrecision.DateTime
                : request.CloseDate.HasValue
                    ? FundingDeadlinePrecision.Date
                    : FundingDeadlinePrecision.Unknown;
        var geographicScope = request.GeographicScope.HasValue
            ? (FundingGeographicScope)request.GeographicScope.Value
            : request.CountryIds?.Count > 0
                ? FundingGeographicScope.Specified
                : FundingGeographicScope.Unknown;

        return new FundingOpportunityEditorialData(
            request.Title,
            request.Summary,
            request.Description,
            request.SponsorName,
            request.SponsorUrl,
            request.ApplicationUrl,
            (request.Funders ?? []).Select(link => new FundingOpportunityFunderLink(
                link.FunderId, (FunderOpportunityRole)link.Role)).ToArray(),
            request.FundingSourceId,
            request.ExternalId,
            request.SourceUrl,
            request.IssuerCountryId,
            request.FundingTypeId,
            request.Currency,
            request.MinimumAmount,
            request.MaximumAmount,
            amountStatus,
            request.OpenDate,
            request.CloseDate,
            request.CloseAtUtc,
            request.DeadlineTimeZoneId,
            deadlineType,
            deadlinePrecision,
            request.EligibilityDescription,
            request.Requirements,
            request.Objectives,
            request.AllowedActivities,
            request.ExcludedActivities,
            request.Restrictions,
            request.TargetOrganizationsDescription,
            request.TargetPopulationsDescription,
            request.MinimumOperatingYears,
            request.RequiresLegalEntity,
            request.RequiresPriorExperience,
            request.RequiresCofunding,
            request.CofundingPercentage,
            geographicScope,
            request.RemoteApplication.HasValue
                ? (FundingRemoteApplication)request.RemoteApplication.Value
                : FundingRemoteApplication.Unknown,
            request.LastVerifiedAtUtc,
            request.CountryIds ?? [],
            request.RegionIds ?? [],
            request.CategoryIds ?? [],
            request.BeneficiaryTypeIds ?? [],
            request.ProjectTypeIds ?? []);
    }

    private static FunderAdminSummaryResponse Map(FunderSummary funder) => new(
        funder.PublicId, funder.Slug, funder.Name, funder.Description, funder.WebsiteUrl,
        funder.CountryId, funder.CountryCode, funder.CountryName,
        (byte)funder.PublicationStatus, funder.IsActive, funder.ContentVersion,
        funder.UpdatedAtUtc, ProjectEndpointResults.FormatETag(funder.RowVersion));

    private static FunderAdminDetailResponse Map(FunderDetails funder) => new(
        funder.PublicId, funder.Slug, funder.Name, funder.Description, funder.WebsiteUrl,
        funder.CountryId, funder.CountryCode, funder.CountryName,
        (byte)funder.PublicationStatus, funder.IsActive, funder.ContentVersion,
        funder.CreatedAtUtc, funder.UpdatedAtUtc,
        ProjectEndpointResults.FormatETag(funder.RowVersion), funder.Aliases,
        funder.SubmittedAtUtc, funder.ReviewedAtUtc, funder.ReviewedByUserPublicId,
        funder.PublishedAtUtc, funder.RejectionReason,
        funder.Opportunities.Select(item => new FunderOpportunitySummaryResponse(
            item.PublicId, item.Slug, item.Title, (byte)item.Role,
            (byte)item.PublicationStatus, item.IsActive)).ToArray());

    private static FundingOpportunityAdminSummaryResponse Map(
        FundingOpportunityAdminSummary opportunity) => new(
        opportunity.PublicId, opportunity.Slug, opportunity.Title, opportunity.Summary,
        opportunity.SponsorName, (byte)opportunity.PublicationStatus, opportunity.IsActive,
        opportunity.OpenDate, opportunity.CloseDate, opportunity.Currency,
        opportunity.MinimumAmount, opportunity.MaximumAmount, opportunity.DataQualityScore,
        opportunity.SourceName, opportunity.SourceUrl, opportunity.PublishedAtUtc,
        opportunity.LastVerifiedAtUtc,
        opportunity.ContentVersion, opportunity.UpdatedAtUtc,
        ProjectEndpointResults.FormatETag(opportunity.RowVersion));

    private static FundingOpportunityAdminDetailResponse Map(
        FundingOpportunityAdminDetails opportunity) => new(
        opportunity.PublicId,
        opportunity.Slug,
        opportunity.Data.Title,
        opportunity.Data.Summary,
        opportunity.Data.Description,
        opportunity.Data.SponsorName,
        opportunity.Data.SponsorUrl,
        opportunity.Data.ApplicationUrl,
        opportunity.Data.FundingSourceId,
        opportunity.Data.ExternalId,
        opportunity.Data.SourceUrl,
        opportunity.Data.IssuerCountryId,
        opportunity.Data.FundingTypeId,
        opportunity.Data.Currency,
        opportunity.Data.MinimumAmount,
        opportunity.Data.MaximumAmount,
        (byte)opportunity.Data.AmountStatus,
        opportunity.Data.OpenDate,
        opportunity.Data.CloseDate,
        opportunity.Data.CloseAtUtc,
        opportunity.Data.DeadlineTimeZoneId,
        (byte)opportunity.Data.DeadlineType,
        (byte)opportunity.Data.DeadlinePrecision,
        opportunity.Data.EligibilityDescription,
        opportunity.Data.Requirements,
        opportunity.Data.Objectives,
        opportunity.Data.AllowedActivities,
        opportunity.Data.ExcludedActivities,
        opportunity.Data.Restrictions,
        opportunity.Data.TargetOrganizationsDescription,
        opportunity.Data.TargetPopulationsDescription,
        opportunity.Data.MinimumOperatingYears,
        opportunity.Data.RequiresLegalEntity,
        opportunity.Data.RequiresPriorExperience,
        opportunity.Data.RequiresCofunding,
        opportunity.Data.CofundingPercentage,
        (byte)opportunity.Data.GeographicScope,
        (byte)opportunity.Data.RemoteApplication,
        opportunity.Data.LastVerifiedAtUtc,
        opportunity.Data.CountryIds,
        opportunity.Data.RegionIds,
        opportunity.Data.CategoryIds,
        opportunity.Data.BeneficiaryTypeIds,
        opportunity.Data.ProjectTypeIds,
        opportunity.Funders.Select(item => new FundingOpportunityFunderResponse(
            item.PublicId, item.Slug, item.Name, (byte)item.Role)).ToArray(),
        opportunity.Evidence.Select(item => new FundingFieldEvidenceResponse(
            item.PublicId, item.FieldPath, item.ValueJson, item.ExtractionMethod,
            item.EvidenceText, item.SourceLocator, item.Confidence, item.IsSelected,
            item.IsManualLock, item.CreatedByUserPublicId, item.CreatedAtUtc)).ToArray(),
        opportunity.SourceLinks.Select(item => new FundingOpportunitySourceResponse(
            item.FundingSourceId, item.SourceName, item.ExternalId, item.SourceUrl,
            item.FirstSeenAtUtc, item.LastSeenAtUtc, item.IsPrimary, item.IsActive)).ToArray(),
        (byte)opportunity.PublicationStatus,
        opportunity.IsActive,
        opportunity.ContentVersion,
        opportunity.DataQualityScore,
        opportunity.CreatedAtUtc,
        opportunity.UpdatedAtUtc,
        ProjectEndpointResults.FormatETag(opportunity.RowVersion),
        opportunity.SubmittedAtUtc,
        opportunity.ReviewedAtUtc,
        opportunity.ReviewedByUserPublicId,
        opportunity.PublishedAtUtc,
        opportunity.RejectionReason);

    private static bool TryGetUser(
        ClaimsPrincipal principal,
        out Guid userId,
        out IResult? error)
    {
        if (ProjectEndpointResults.TryGetUserId(principal, out userId))
        {
            error = null;
            return true;
        }

        error = ProjectEndpointResults.InvalidSession();
        return false;
    }

    private static bool TryValidateList(
        string? query,
        byte? status,
        int page,
        int pageSize,
        out FundingPublicationStatus? publicationStatus,
        out IResult? error)
    {
        publicationStatus = status.HasValue ? (FundingPublicationStatus)status.Value : null;
        if (query?.Trim().Length > 300 ||
            status > (byte)FundingPublicationStatus.Archived ||
            page < 1 || pageSize is < 1 or > 100)
        {
            error = ProjectEndpointResults.Validation(
                422, "Filtros inválidos", "invalid-funding-editorial-filter",
                new Dictionary<string, string[]>
                {
                    [query?.Trim().Length > 300
                        ? "query"
                        : status > (byte)FundingPublicationStatus.Archived
                            ? "status"
                            : "pagination"] =
                        [query?.Trim().Length > 300
                            ? "query admite hasta 300 caracteres."
                            : status > (byte)FundingPublicationStatus.Archived
                            ? "status debe estar entre 0 y 4."
                            : "page debe ser al menos 1 y pageSize debe estar entre 1 y 100."]
                });
            return false;
        }

        error = null;
        return true;
    }

    private static bool TryParseDecision(
        string? value,
        out FundingReviewDecision decision,
        out IResult? error)
    {
        if (string.Equals(value?.Trim(), "approve", StringComparison.OrdinalIgnoreCase))
        {
            decision = FundingReviewDecision.Approve;
            error = null;
            return true;
        }

        if (string.Equals(value?.Trim(), "reject", StringComparison.OrdinalIgnoreCase))
        {
            decision = FundingReviewDecision.Reject;
            error = null;
            return true;
        }

        decision = default;
        error = ProjectEndpointResults.Validation(
            422, "Decisión inválida", "invalid-review-decision",
            new Dictionary<string, string[]>
            {
                ["decision"] = ["decision debe ser approve o reject."]
            });
        return false;
    }

    private static IResult Forbidden() => ProjectEndpointResults.Problem(
        403, "Acceso denegado", null, "admin-role-required");
}
