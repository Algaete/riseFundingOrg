using System.Security.Claims;
using FundingPlatform.Api.Configuration;
using FundingPlatform.Application.Authentication;
using FundingPlatform.Contracts.Authentication;
using FundingPlatform.Infrastructure.Identity.Configuration;
using FundingPlatform.Infrastructure.Identity.Persistence;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Api.Endpoints;

public static class AuthenticationEndpoints
{
    public const string RefreshCookieName = "__Secure-fp_refresh";

    public static IEndpointRouteBuilder MapAuthenticationEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        var auth = endpoints.MapGroup("/api/v1/auth").WithTags("Authentication");

        auth.MapPost("/register", RegisterAsync)
            .AllowAnonymous()
            .RequireRateLimiting("auth-registration");
        auth.MapPost("/verify-email", VerifyEmailAsync)
            .AllowAnonymous()
            .RequireRateLimiting("auth-token");
        auth.MapPost("/resend-verification", ResendVerificationAsync)
            .AllowAnonymous()
            .RequireRateLimiting("auth-registration");
        auth.MapPost("/login", LoginAsync)
            .AllowAnonymous()
            .RequireRateLimiting("auth-login");
        auth.MapPost("/mfa/challenge", CompleteMfaChallengeAsync)
            .AllowAnonymous()
            .RequireRateLimiting("auth-login");
        auth.MapPost("/refresh", RefreshAsync)
            .AllowAnonymous()
            .RequireRateLimiting("auth-refresh");
        auth.MapPost("/logout", LogoutAsync)
            .AllowAnonymous()
            .RequireRateLimiting("auth-refresh");
        auth.MapPost("/logout-all", LogoutAllAsync)
            .RequireAuthorization("full-session")
            .RequireRateLimiting("auth-refresh");
        auth.MapPost("/forgot-password", ForgotPasswordAsync)
            .AllowAnonymous()
            .RequireRateLimiting("auth-registration");
        auth.MapPost("/reset-password", ResetPasswordAsync)
            .AllowAnonymous()
            .RequireRateLimiting("auth-token");

        endpoints.MapGet("/api/v1/me", GetCurrentUserAsync)
            .WithTags("Account")
            .RequireAuthorization("full-session");
        endpoints.MapPost("/api/v1/me/mfa/setup", BeginMfaSetupAsync)
            .WithTags("Account")
            .RequireAuthorization("authenticated-session")
            .RequireRateLimiting("auth-token");
        endpoints.MapPost("/api/v1/me/mfa/confirm", ConfirmMfaSetupAsync)
            .WithTags("Account")
            .RequireAuthorization("authenticated-session")
            .RequireRateLimiting("auth-token");

        return endpoints;
    }

    private static async Task<IResult> RegisterAsync(
        RegisterRequest request,
        HttpContext httpContext,
        IAuthenticationService service,
        CancellationToken cancellationToken)
    {
        var result = await service.RegisterAsync(
            new RegistrationInput(
                request.Email,
                request.DisplayName,
                request.Password,
                request.PreferredLocale),
            CreateClientContext(httpContext),
            cancellationToken);

        if (!result.Accepted)
        {
            return Results.ValidationProblem(ToValidationDictionary(result.ValidationFailures));
        }

        return Results.Accepted(value: new AcceptedResponse(
            "Si la solicitud es válida, recibirás instrucciones por correo."));
    }

    private static async Task<IResult> VerifyEmailAsync(
        VerifyEmailRequest request,
        HttpContext httpContext,
        IAuthenticationService service,
        CancellationToken cancellationToken)
    {
        var succeeded = await service.VerifyEmailAsync(
            request.Token,
            CreateClientContext(httpContext),
            cancellationToken);
        return succeeded
            ? Results.Ok(new AcceptedResponse("Tu correo fue confirmado."))
            : Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Enlace inválido o vencido",
                detail: "Solicita un nuevo correo de verificación.",
                type: "https://fundingplatform.local/problems/invalid-security-token");
    }

    private static async Task<IResult> ResendVerificationAsync(
        EmailRequest request,
        HttpContext httpContext,
        IAuthenticationService service,
        CancellationToken cancellationToken)
    {
        await service.ResendVerificationAsync(
            request.Email,
            CreateClientContext(httpContext),
            cancellationToken);
        return Results.Accepted(value: new AcceptedResponse(
            "Si la cuenta puede verificarse, recibirás un nuevo correo."));
    }

    private static async Task<IResult> LoginAsync(
        LoginRequest request,
        HttpContext httpContext,
        IAuthenticationService service,
        IOptions<AuthenticationOptions> options,
        CancellationToken cancellationToken)
    {
        var result = await service.LoginAsync(
            new LoginInput(request.Email, request.Password),
            CreateClientContext(httpContext),
            cancellationToken);

        if (result.Outcome == LoginOutcome.Success &&
            result.Session is not null &&
            result.RefreshToken is not null)
        {
            SetRefreshCookie(httpContext.Response, result.RefreshToken, options.Value);
            return Results.Ok(MapAuthenticationResponse(result));
        }

        return result.Outcome switch
        {
            LoginOutcome.MfaRequired or LoginOutcome.MfaSetupRequired =>
                Results.Json(MapAuthenticationResponse(result), statusCode: StatusCodes.Status202Accepted),
            LoginOutcome.EmailVerificationRequired => Results.Problem(
                statusCode: StatusCodes.Status403Forbidden,
                title: "Verificación requerida",
                detail: "Debes confirmar tu correo antes de iniciar sesión.",
                type: "https://fundingplatform.local/problems/email-verification-required"),
            _ => InvalidCredentials()
        };
    }

    private static async Task<IResult> CompleteMfaChallengeAsync(
        MfaChallengeRequest request,
        HttpContext httpContext,
        IAuthenticationService service,
        IOptions<AuthenticationOptions> options,
        CancellationToken cancellationToken)
    {
        var result = await service.CompleteMfaChallengeAsync(
            new MfaChallengeInput(request.ChallengeToken, request.Code),
            CreateClientContext(httpContext),
            cancellationToken);
        if (result.Outcome != LoginOutcome.Success ||
            result.Session is null ||
            result.RefreshToken is null)
        {
            return InvalidCredentials();
        }

        SetRefreshCookie(httpContext.Response, result.RefreshToken, options.Value);
        return Results.Ok(MapAuthenticationResponse(result));
    }

    private static async Task<IResult> RefreshAsync(
        HttpContext httpContext,
        IAuthenticationService service,
        IOptions<WebOptions> webOptions,
        IOptions<AuthenticationOptions> authOptions,
        CancellationToken cancellationToken)
    {
        if (!HasAllowedOrigin(httpContext.Request, webOptions.Value))
        {
            return InvalidOrigin();
        }

        if (!httpContext.Request.Cookies.TryGetValue(RefreshCookieName, out var refreshToken))
        {
            return InvalidSession();
        }

        var result = await service.RefreshAsync(
            refreshToken,
            CreateClientContext(httpContext),
            cancellationToken);
        if (result.Outcome == RefreshOutcome.Success &&
            result.Session is not null &&
            result.RefreshToken is not null)
        {
            SetRefreshCookie(httpContext.Response, result.RefreshToken, authOptions.Value);
            return Results.Ok(new AuthenticationResponse(
                "authenticated",
                result.Session.AccessToken,
                result.Session.ExpiresAtUtc,
                MapUser(result.Session.User)));
        }

        if (result.Outcome == RefreshOutcome.Conflict)
        {
            return Results.Problem(
                statusCode: StatusCodes.Status409Conflict,
                title: "Actualización de sesión en curso",
                detail: "Otra pestaña ya actualizó la sesión. Reintenta una vez.",
                type: "https://fundingplatform.local/problems/refresh-conflict");
        }

        DeleteRefreshCookie(httpContext.Response);
        return InvalidSession(result.Outcome == RefreshOutcome.ReplayDetected
            ? "La sesión fue revocada por reutilización de credenciales."
            : null);
    }

    private static async Task<IResult> LogoutAsync(
        HttpContext httpContext,
        IAuthenticationService service,
        IOptions<WebOptions> webOptions,
        ILoggerFactory loggerFactory,
        CancellationToken cancellationToken)
    {
        if (!HasAllowedOrigin(httpContext.Request, webOptions.Value))
        {
            return InvalidOrigin();
        }

        try
        {
            if (httpContext.Request.Cookies.TryGetValue(RefreshCookieName, out var refreshToken))
            {
                await service.LogoutAsync(
                    refreshToken,
                    CreateClientContext(httpContext),
                    cancellationToken);
            }
        }
        catch (AuthenticationDataException exception)
        {
            loggerFactory.CreateLogger("FundingPlatform.Authentication").LogWarning(
                "Server-side logout revocation failed. Operation={Operation} SqlError={SqlError}",
                exception.Operation,
                exception.SqlErrorNumber);
            return Results.Problem(
                statusCode: StatusCodes.Status503ServiceUnavailable,
                title: "Cierre de sesión incompleto",
                detail: "La sesión local se eliminó, pero no fue posible confirmar la revocación en el servidor.",
                type: "https://fundingplatform.local/problems/logout-incomplete");
        }
        finally
        {
            DeleteRefreshCookie(httpContext.Response);
        }

        return Results.NoContent();
    }

    private static async Task<IResult> LogoutAllAsync(
        HttpContext httpContext,
        IAuthenticationService service,
        IOptions<WebOptions> webOptions,
        CancellationToken cancellationToken)
    {
        if (!HasAllowedOrigin(httpContext.Request, webOptions.Value))
        {
            return InvalidOrigin();
        }

        if (!TryGetPublicUserId(httpContext.User, out var publicUserId))
        {
            return InvalidSession();
        }

        await service.LogoutAllAsync(
            publicUserId,
            CreateClientContext(httpContext),
            cancellationToken);
        DeleteRefreshCookie(httpContext.Response);
        return Results.NoContent();
    }

    private static async Task<IResult> ForgotPasswordAsync(
        EmailRequest request,
        HttpContext httpContext,
        IAuthenticationService service,
        CancellationToken cancellationToken)
    {
        await service.ForgotPasswordAsync(
            request.Email,
            CreateClientContext(httpContext),
            cancellationToken);
        return Results.Accepted(value: new AcceptedResponse(
            "Si la cuenta existe, recibirás instrucciones para restablecerla."));
    }

    private static async Task<IResult> ResetPasswordAsync(
        ResetPasswordRequest request,
        HttpContext httpContext,
        IAuthenticationService service,
        CancellationToken cancellationToken)
    {
        var result = await service.ResetPasswordAsync(
            new ResetPasswordInput(request.Token, request.NewPassword),
            CreateClientContext(httpContext),
            cancellationToken);
        if (result.ValidationFailures.Count > 0)
        {
            return Results.ValidationProblem(ToValidationDictionary(result.ValidationFailures));
        }

        return result.Succeeded
            ? Results.Ok(new AcceptedResponse("La contraseña fue actualizada."))
            : Results.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                title: "Enlace inválido o vencido",
                detail: "Solicita un nuevo enlace para restablecer tu contraseña.",
                type: "https://fundingplatform.local/problems/invalid-security-token");
    }

    private static async Task<IResult> GetCurrentUserAsync(
        ClaimsPrincipal principal,
        IAuthenticationService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetPublicUserId(principal, out var publicUserId))
        {
            return InvalidSession();
        }

        var user = await service.GetCurrentUserAsync(publicUserId, cancellationToken);
        return user is null ? InvalidSession() : Results.Ok(MapUser(user));
    }

    private static async Task<IResult> BeginMfaSetupAsync(
        ClaimsPrincipal principal,
        IAuthenticationService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetPublicUserId(principal, out var publicUserId))
        {
            return InvalidSession();
        }

        var setup = await service.BeginMfaSetupAsync(publicUserId, cancellationToken);
        return Results.Ok(new MfaSetupResponse(setup.SharedKey, setup.AuthenticatorUri));
    }

    private static async Task<IResult> ConfirmMfaSetupAsync(
        MfaCodeRequest request,
        ClaimsPrincipal principal,
        IAuthenticationService service,
        CancellationToken cancellationToken)
    {
        if (!TryGetPublicUserId(principal, out var publicUserId))
        {
            return InvalidSession();
        }

        var result = await service.ConfirmMfaSetupAsync(
            publicUserId,
            request.Code,
            cancellationToken);
        return result is null
            ? Results.ValidationProblem(new Dictionary<string, string[]>
            {
                ["code"] = ["El código de autenticación no es válido."]
            })
            : Results.Ok(new MfaConfirmationResponse(result.RecoveryCodes));
    }

    private static AuthenticationResponse MapAuthenticationResponse(LoginResult result)
    {
        return new AuthenticationResponse(
            result.Outcome switch
            {
                LoginOutcome.Success => "authenticated",
                LoginOutcome.MfaRequired => "mfa_required",
                LoginOutcome.MfaSetupRequired => "mfa_setup_required",
                _ => "authentication_failed"
            },
            result.Session?.AccessToken,
            result.Session?.ExpiresAtUtc,
            result.Session is null ? null : MapUser(result.Session.User),
            result.MfaChallengeToken,
            result.MfaChallengeExpiresAtUtc,
            result.MfaSetupToken);
    }

    private static AuthenticatedUserResponse MapUser(AuthenticatedUser user)
    {
        return new AuthenticatedUserResponse(
            user.PublicId,
            user.Email,
            user.DisplayName,
            user.PreferredLocale,
            user.Roles,
            user.MfaEnabled);
    }

    private static Dictionary<string, string[]> ToValidationDictionary(
        IReadOnlyCollection<PasswordValidationFailure> failures)
    {
        return failures
            .GroupBy(failure => failure.Code, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(
                group => group.Key,
                group => group.Select(failure => failure.Description).Distinct().ToArray(),
                StringComparer.OrdinalIgnoreCase);
    }

    private static ClientRequestContext CreateClientContext(HttpContext context)
    {
        return new ClientRequestContext(
            context.Connection.RemoteIpAddress?.ToString(),
            context.Request.Headers.UserAgent.ToString(),
            context.TraceIdentifier);
    }

    private static bool TryGetPublicUserId(ClaimsPrincipal principal, out Guid publicUserId)
    {
        return Guid.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out publicUserId);
    }

    private static bool HasAllowedOrigin(HttpRequest request, WebOptions options)
    {
        if (!request.Headers.TryGetValue("Origin", out var values) || values.Count != 1)
        {
            return false;
        }

        return options.AllowedCorsOrigins.Contains(values[0]!, StringComparer.OrdinalIgnoreCase);
    }

    private static void SetRefreshCookie(
        HttpResponse response,
        string refreshToken,
        AuthenticationOptions options)
    {
        response.Cookies.Append(
            RefreshCookieName,
            refreshToken,
            new CookieOptions
            {
                HttpOnly = true,
                Secure = true,
                SameSite = SameSiteMode.Lax,
                Path = "/api/v1/auth",
                IsEssential = true,
                MaxAge = TimeSpan.FromDays(options.RefreshToken.LifetimeDays)
            });
    }

    private static void DeleteRefreshCookie(HttpResponse response)
    {
        response.Cookies.Delete(
            RefreshCookieName,
            new CookieOptions
            {
                HttpOnly = true,
                Secure = true,
                SameSite = SameSiteMode.Lax,
                Path = "/api/v1/auth",
                IsEssential = true
            });
    }

    private static IResult InvalidCredentials()
    {
        return Results.Problem(
            statusCode: StatusCodes.Status401Unauthorized,
            title: "No fue posible iniciar sesión",
            detail: "El correo o la contraseña no son válidos.",
            type: "https://fundingplatform.local/problems/invalid-credentials");
    }

    private static IResult InvalidSession(string? detail = null)
    {
        return Results.Problem(
            statusCode: StatusCodes.Status401Unauthorized,
            title: "Sesión inválida",
            detail: detail ?? "Inicia sesión nuevamente.",
            type: "https://fundingplatform.local/problems/invalid-session");
    }

    private static IResult InvalidOrigin()
    {
        return Results.Problem(
            statusCode: StatusCodes.Status403Forbidden,
            title: "Origen no permitido",
            detail: "La operación fue rechazada por la política de seguridad del navegador.",
            type: "https://fundingplatform.local/problems/invalid-origin");
    }
}
