using System.Security.Claims;
using FundingPlatform.Api.Authorization;
using FundingPlatform.Infrastructure.Identity.Configuration;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Options;

namespace FundingPlatform.IntegrationTests;

public sealed class RecentMfaRequirementTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 8, 21, 18, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Recent_mfa_satisfies_the_requirement()
    {
        var context = CreateContext(Now.AddMinutes(-59));

        await CreateHandler().HandleAsync(context);

        Assert.True(context.HasSucceeded);
    }

    [Fact]
    public async Task Expired_or_future_mfa_is_rejected()
    {
        var expired = CreateContext(Now.AddMinutes(-61));
        var future = CreateContext(Now.AddMinutes(1));
        var handler = CreateHandler();

        await handler.HandleAsync(expired);
        await handler.HandleAsync(future);

        Assert.False(expired.HasSucceeded);
        Assert.False(future.HasSucceeded);
    }

    [Fact]
    public async Task Missing_or_invalid_authentication_time_is_rejected()
    {
        var requirement = new RecentMfaRequirement();
        var principal = new ClaimsPrincipal(new ClaimsIdentity(
            [new Claim("amr", "mfa"), new Claim("auth_time", "invalid")],
            "test"));
        var context = new AuthorizationHandlerContext([requirement], principal, null);

        await CreateHandler().HandleAsync(context);

        Assert.False(context.HasSucceeded);
    }

    private static RecentMfaHandler CreateHandler() => new(
        new FixedTimeProvider(Now),
        Options.Create(new AuthenticationOptions
        {
            Mfa = new MfaOptions { AdminSessionMinutes = 60 }
        }));

    private static AuthorizationHandlerContext CreateContext(DateTimeOffset authenticationTime)
    {
        var requirement = new RecentMfaRequirement();
        var principal = new ClaimsPrincipal(new ClaimsIdentity(
            [
                new Claim("amr", "mfa"),
                new Claim("auth_time", authenticationTime.ToUnixTimeSeconds().ToString())
            ],
            "test"));
        return new AuthorizationHandlerContext([requirement], principal, null);
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
}
