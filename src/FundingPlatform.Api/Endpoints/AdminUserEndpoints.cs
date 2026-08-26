using FundingPlatform.Application.Authentication;
using FundingPlatform.Contracts.Authentication;
using FundingPlatform.Core.Identity;

namespace FundingPlatform.Api.Endpoints;

public static class AdminUserEndpoints
{
    public static IEndpointRouteBuilder MapAdminUserEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/v1/admin/users", ListAsync)
            .WithTags("Admin Users")
            .RequireAuthorization("admin-mfa")
            .RequireRateLimiting("organization-activity-read")
            .Produces<AdminUserPageResponse>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status403Forbidden);
        return endpoints;
    }

    private static async Task<IResult> ListAsync(
        AdminUserDirectoryService service,
        CancellationToken cancellationToken,
        string? q = null,
        int? status = null,
        string? role = null,
        int page = 1,
        int pageSize = 25)
    {
        var errors = Validate(q, status, role, page, pageSize);
        if (errors.Count > 0)
        {
            return Results.ValidationProblem(
                errors,
                statusCode: StatusCodes.Status422UnprocessableEntity,
                title: "Filtros de usuarios inválidos");
        }

        var parsedStatus = status is null ? null : (UserStatus?)status.Value;
        var result = await service.ListAsync(
            new AdminUserDirectoryQuery(q, parsedStatus, role, page, pageSize),
            cancellationToken);
        return Results.Ok(new AdminUserPageResponse(
            result.Items.Select(Map).ToArray(),
            result.TotalCount,
            result.Page,
            result.PageSize));
    }

    private static Dictionary<string, string[]> Validate(
        string? query,
        int? status,
        string? role,
        int page,
        int pageSize)
    {
        var errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        if (query?.Trim().Length > 200)
            errors["q"] = ["q no puede superar 200 caracteres."];
        if (status is not null &&
            (status.Value is < byte.MinValue or > byte.MaxValue ||
             !Enum.IsDefined(typeof(UserStatus), (byte)status.Value)))
            errors["status"] = ["status no es válido."];
        if (role?.Trim().Length > 100)
            errors["role"] = ["role no puede superar 100 caracteres."];
        if (page is < 1 or > 10000)
            errors["page"] = ["page debe estar entre 1 y 10000."];
        if (pageSize is < 1 or > 100)
            errors["pageSize"] = ["pageSize debe estar entre 1 y 100."];
        return errors;
    }

    private static AdminUserSummaryResponse Map(AdminUserDirectoryItem value) => new(
        value.PublicId,
        value.Email,
        value.DisplayName,
        value.PreferredLocale,
        value.Status.ToString(),
        value.EmailConfirmed,
        value.TwoFactorEnabled,
        value.LastLoginAtUtc,
        value.CreatedAtUtc,
        value.Roles);
}
