namespace FundingPlatform.Api.Middleware;

public sealed class SecurityHeadersMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context)
    {
        context.Response.OnStarting(() =>
        {
            var headers = context.Response.Headers;
            headers.XContentTypeOptions = "nosniff";
            headers.XFrameOptions = "DENY";
            headers.Append("Referrer-Policy", "no-referrer");
            headers.Append("Permissions-Policy", "camera=(), microphone=(), geolocation=()");

            if (context.Request.Path.StartsWithSegments("/api/v1/auth") ||
                context.Request.Path.StartsWithSegments("/api/v1/me") ||
                context.Request.Path.StartsWithSegments("/api/v1/organizations") ||
                context.Request.Path.StartsWithSegments("/api/v1/admin") ||
                context.Request.Path.StartsWithSegments("/api/v1/alerts"))
            {
                headers.CacheControl = "no-store";
                headers.Pragma = "no-cache";
            }

            return Task.CompletedTask;
        });

        await next(context);
    }
}
