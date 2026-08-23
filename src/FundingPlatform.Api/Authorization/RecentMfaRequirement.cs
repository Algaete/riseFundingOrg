using System.Globalization;
using FundingPlatform.Infrastructure.Identity.Configuration;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Api.Authorization;

public sealed class RecentMfaRequirement : IAuthorizationRequirement;

public sealed class RecentMfaHandler(
    TimeProvider timeProvider,
    IOptions<AuthenticationOptions> authenticationOptions)
    : AuthorizationHandler<RecentMfaRequirement>
{
    private static readonly TimeSpan FutureClockSkew = TimeSpan.FromSeconds(30);

    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        RecentMfaRequirement requirement)
    {
        var authenticationMethod = context.User.FindFirst("amr")?.Value;
        var authenticationTimeValue = context.User.FindFirst("auth_time")?.Value;
        if (!string.Equals(authenticationMethod, "mfa", StringComparison.Ordinal) ||
            !long.TryParse(
                authenticationTimeValue,
                NumberStyles.None,
                CultureInfo.InvariantCulture,
                out var authenticationTimeSeconds))
        {
            return Task.CompletedTask;
        }

        DateTimeOffset authenticationTime;
        try
        {
            authenticationTime = DateTimeOffset.FromUnixTimeSeconds(authenticationTimeSeconds);
        }
        catch (ArgumentOutOfRangeException)
        {
            return Task.CompletedTask;
        }

        var now = timeProvider.GetUtcNow();
        var maxAge = TimeSpan.FromMinutes(authenticationOptions.Value.Mfa.AdminSessionMinutes);
        if (authenticationTime <= now.Add(FutureClockSkew) && now - authenticationTime <= maxAge)
        {
            context.Succeed(requirement);
        }

        return Task.CompletedTask;
    }
}
