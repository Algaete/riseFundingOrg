using FundingPlatform.Infrastructure.Identity.Configuration;

namespace FundingPlatform.Api.Configuration;

internal static class RefreshSessionCookie
{
    internal const string SameSiteName = "__Secure-fp_refresh";
    internal const string PartitionedName = "__Secure-fp_refresh_partitioned";

    internal static string Name(AuthenticationOptions options) =>
        options.RefreshToken.UsePartitionedCookie ? PartitionedName : SameSiteName;

    internal static CookieOptions CreateOptions(AuthenticationOptions options, bool persistent = true)
    {
        var cookie = new CookieOptions
        {
            HttpOnly = true,
            Secure = true,
            SameSite = options.RefreshToken.UsePartitionedCookie ? SameSiteMode.None : SameSiteMode.Lax,
            Path = "/api/v1/auth",
            IsEssential = true,
            MaxAge = persistent ? TimeSpan.FromDays(options.RefreshToken.LifetimeDays) : null
        };
        // CHIPS binds the cookie to the top-level site. It is never a plain SameSite=None cookie.
        if (options.RefreshToken.UsePartitionedCookie) cookie.Extensions.Add("Partitioned");
        return cookie;
    }

    internal static void Append(HttpResponse response, string token, AuthenticationOptions options) =>
        response.Cookies.Append(Name(options), token, CreateOptions(options));

    internal static void Delete(HttpResponse response, AuthenticationOptions options) =>
        response.Cookies.Delete(Name(options), CreateOptions(options, persistent: false));
}
