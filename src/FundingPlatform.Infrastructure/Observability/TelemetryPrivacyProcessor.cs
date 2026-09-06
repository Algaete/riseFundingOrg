using System.Diagnostics;
using OpenTelemetry;

namespace FundingPlatform.Infrastructure.Observability;

/// <summary>
/// Removes request-instance data from completed spans before any exporter sees it.
/// The processor is intentionally stateless so the same instance can be shared by
/// the API and isolated Functions workers.
/// </summary>
public sealed class TelemetryPrivacyProcessor : BaseProcessor<Activity>
{
    private const string DatabaseStatementTag = "db.statement";
    private const string DatabaseQueryTextTag = "db.query.text";
    private const string HttpTargetTag = "http.target";
    private const string HttpUrlTag = "http.url";
    private const string UrlFullTag = "url.full";
    private const string UrlPathTag = "url.path";
    private const string UrlQueryTag = "url.query";
    private const string UrlFragmentTag = "url.fragment";

    public override void OnEnd(Activity activity)
    {
        var isInboundHttp = IsInboundHttp(activity);
        var isOutboundHttp = IsOutboundHttp(activity);
        var containedDatabaseText =
            activity.GetTagItem(DatabaseStatementTag) is not null ||
            activity.GetTagItem(DatabaseQueryTextTag) is not null;

        RemoveTag(activity, HttpTargetTag);
        RemoveTag(activity, DatabaseStatementTag);
        RemoveTag(activity, DatabaseQueryTextTag);

        if (isInboundHttp)
        {
            SanitizeInboundHttp(activity);
        }
        else if (isOutboundHttp)
        {
            SanitizeOutboundHttp(activity);
        }
        else if (containedDatabaseText)
        {
            activity.DisplayName = ReadSafeToken(activity, "db.operation.name") ?? "database";
        }

        if (isInboundHttp || isOutboundHttp || containedDatabaseText)
        {
            activity.SetStatus(activity.Status);
        }
    }

    private static void SanitizeInboundHttp(Activity activity)
    {
        var route = ReadRouteTemplate(activity);
        if (route is null)
        {
            RemoveTag(activity, "http.route");
            route = "/";
        }

        activity.SetTag(UrlPathTag, route);
        RemoveTag(activity, UrlQueryTag);
        RemoveTag(activity, UrlFragmentTag);
        _ = SanitizeUrlToOrigin(activity, UrlFullTag);
        _ = SanitizeUrlToOrigin(activity, HttpUrlTag);
        activity.DisplayName = $"{ReadHttpMethod(activity)} {route}";
    }

    private static void SanitizeOutboundHttp(Activity activity)
    {
        var fullUrlOrigin = SanitizeUrlToOrigin(activity, UrlFullTag);
        var legacyUrlOrigin = SanitizeUrlToOrigin(activity, HttpUrlTag);
        var origin = fullUrlOrigin ?? legacyUrlOrigin;

        // Client instrumentation normally emits url.full rather than these
        // server attributes. Remove them if another instrumentation library adds
        // them so the origin-only boundary cannot be bypassed.
        RemoveTag(activity, UrlPathTag);
        RemoveTag(activity, UrlQueryTag);
        RemoveTag(activity, UrlFragmentTag);
        RemoveTag(activity, "http.route");

        activity.DisplayName = origin is null
            ? $"{ReadHttpMethod(activity)} remote"
            : $"{ReadHttpMethod(activity)} {origin}";
    }

    private static bool IsInboundHttp(Activity activity) =>
        activity.Kind == ActivityKind.Server && HasHttpTag(activity);

    private static bool IsOutboundHttp(Activity activity) =>
        activity.Kind == ActivityKind.Client && HasHttpTag(activity);

    private static bool HasHttpTag(Activity activity) =>
        activity.GetTagItem("http.request.method") is not null ||
        activity.GetTagItem("http.method") is not null ||
        activity.GetTagItem("http.route") is not null ||
        activity.GetTagItem(HttpTargetTag) is not null ||
        activity.GetTagItem(UrlFullTag) is not null ||
        activity.GetTagItem(HttpUrlTag) is not null ||
        activity.GetTagItem(UrlPathTag) is not null;

    private static string? ReadRouteTemplate(Activity activity)
    {
        if (activity.GetTagItem("http.route") is not string route ||
            string.IsNullOrWhiteSpace(route) ||
            route.Length > 1_024 ||
            route[0] != '/' ||
            route.Any(char.IsControl))
        {
            return null;
        }

        return route;
    }

    private static string ReadHttpMethod(Activity activity) =>
        ReadSafeToken(activity, "http.request.method") ??
        ReadSafeToken(activity, "http.method") ??
        "HTTP";

    private static string? ReadSafeToken(Activity activity, string tagName)
    {
        if (activity.GetTagItem(tagName) is not string value ||
            value.Length is < 1 or > 32 ||
            !value.All(IsTokenCharacter))
        {
            return null;
        }

        return value;
    }

    private static bool IsTokenCharacter(char value) =>
        char.IsAsciiLetterOrDigit(value) ||
        value is '!' or '#' or '$' or '%' or '&' or '\'' or '*' or '+' or '-' or '.' or
            '^' or '_' or '`' or '|' or '~';

    private static string? SanitizeUrlToOrigin(Activity activity, string tagName)
    {
        if (activity.GetTagItem(tagName) is not string rawUrl ||
            !TryGetHttpOrigin(rawUrl, out var origin))
        {
            RemoveTag(activity, tagName);
            return null;
        }

        activity.SetTag(tagName, origin);
        return origin;
    }

    private static bool TryGetHttpOrigin(string rawUrl, out string origin)
    {
        origin = string.Empty;
        if (!Uri.TryCreate(rawUrl, UriKind.Absolute, out var uri) ||
            (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp) ||
            string.IsNullOrWhiteSpace(uri.IdnHost))
        {
            return false;
        }

        try
        {
            var builder = new UriBuilder(uri.Scheme, uri.IdnHost)
            {
                Port = uri.IsDefaultPort ? -1 : uri.Port,
                Fragment = string.Empty,
                Password = string.Empty,
                Path = string.Empty,
                Query = string.Empty,
                UserName = string.Empty
            };
            origin = builder.Uri.GetLeftPart(UriPartial.Authority);
            return true;
        }
        catch (UriFormatException)
        {
            return false;
        }
    }

    private static void RemoveTag(Activity activity, string tagName) =>
        activity.SetTag(tagName, null);
}
