using System.Diagnostics;
using FundingPlatform.Infrastructure.Observability;

namespace FundingPlatform.UnitTests;

public sealed class TelemetryPrivacyProcessorTests
{
    private readonly TelemetryPrivacyProcessor processor = new();

    [Fact]
    public void Inbound_http_span_uses_route_template_and_preserves_identity_and_status()
    {
        using var activity = CreateCompletedActivity(ActivityKind.Server, item =>
        {
            item.DisplayName =
                "GET /api/v1/organizations/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/private-ngo";
            item.SetTag("http.request.method", "GET");
            item.SetTag("http.route", "/api/v1/organizations/{organizationId:guid}/{slug}");
            item.SetTag("url.path",
                "/api/v1/organizations/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/private-ngo");
            item.SetTag("url.query", "?code=oauth-code-secret");
            item.SetTag("url.full",
                "https://api.example.org/api/v1/oauth/complete?code=oauth-code-secret");
            item.SetTag("http.target",
                "/api/v1/oauth/complete?code=oauth-code-secret");
            item.SetTag("http.response.status_code", 200);
            item.SetStatus(ActivityStatusCode.Ok);
            item.AddEvent(new ActivityEvent(
                "synthetic-checkpoint",
                tags: new ActivityTagsCollection { { "event.kind", "test" } }));
        });
        var traceId = activity.TraceId;
        var spanId = activity.SpanId;
        var status = activity.Status;

        processor.OnEnd(activity);

        Assert.Equal(traceId, activity.TraceId);
        Assert.Equal(spanId, activity.SpanId);
        Assert.Equal(status, activity.Status);
        Assert.Equal(200, activity.GetTagItem("http.response.status_code"));
        Assert.Equal(
            "/api/v1/organizations/{organizationId:guid}/{slug}",
            activity.GetTagItem("url.path"));
        Assert.Equal("https://api.example.org", activity.GetTagItem("url.full"));
        Assert.Null(activity.GetTagItem("url.query"));
        Assert.Null(activity.GetTagItem("http.target"));
        Assert.Equal(
            "GET /api/v1/organizations/{organizationId:guid}/{slug}",
            activity.DisplayName);
        var activityEvent = Assert.Single(activity.Events);
        Assert.Equal("synthetic-checkpoint", activityEvent.Name);
        Assert.Equal("test", activityEvent.Tags.Single().Value);
    }

    [Fact]
    public void Inbound_http_span_without_route_never_keeps_the_raw_path_in_display_name()
    {
        const string rawPath =
            "/api/v1/projects/private-ngo-slug/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
        using var activity = CreateCompletedActivity(ActivityKind.Server, item =>
        {
            item.DisplayName = $"POST {rawPath}";
            item.SetTag("http.request.method", "POST");
            item.SetTag("url.path", rawPath);
            item.SetTag("url.query", "?sig=synthetic-sas-secret");
        });

        processor.OnEnd(activity);

        Assert.Equal("/", activity.GetTagItem("url.path"));
        Assert.Null(activity.GetTagItem("url.query"));
        Assert.Equal("POST /", activity.DisplayName);
        Assert.DoesNotContain("private-ngo", activity.DisplayName, StringComparison.Ordinal);
        Assert.DoesNotContain("aaaaaaaa", activity.DisplayName, StringComparison.Ordinal);
    }

    [Fact]
    public void Outbound_http_span_keeps_only_origins_and_removes_alternate_path_tags()
    {
        using var activity = CreateCompletedActivity(ActivityKind.Client, item =>
        {
            item.DisplayName =
                "POST https://user:password@storage.example.org:8443/private/file.pdf?sig=secret";
            item.SetTag("http.request.method", "POST");
            item.SetTag("url.full",
                "https://user:password@storage.example.org:8443/private/file.pdf?sv=1&sig=synthetic-sas#fragment");
            item.SetTag("http.url",
                "https://user:password@identity.example.org/oauth/token?code=oauth-secret#fragment");
            item.SetTag("http.target", "/private/file.pdf?sig=synthetic-sas");
            item.SetTag("url.path", "/private/file.pdf");
            item.SetTag("url.query", "?sig=synthetic-sas");
            item.SetTag("server.address", "storage.example.org");
            item.SetTag("http.response.status_code", 202);
            item.SetStatus(ActivityStatusCode.Error,
                "https://storage.example.org/private/file.pdf?sig=synthetic-sas");
        });
        var traceId = activity.TraceId;
        var spanId = activity.SpanId;

        processor.OnEnd(activity);

        Assert.Equal(traceId, activity.TraceId);
        Assert.Equal(spanId, activity.SpanId);
        Assert.Equal(ActivityStatusCode.Error, activity.Status);
        Assert.Null(activity.StatusDescription);
        Assert.Equal(202, activity.GetTagItem("http.response.status_code"));
        Assert.Equal("storage.example.org", activity.GetTagItem("server.address"));
        Assert.Equal(
            "https://storage.example.org:8443",
            activity.GetTagItem("url.full"));
        Assert.Equal("https://identity.example.org", activity.GetTagItem("http.url"));
        Assert.Null(activity.GetTagItem("http.target"));
        Assert.Null(activity.GetTagItem("url.path"));
        Assert.Null(activity.GetTagItem("url.query"));
        Assert.Equal("POST https://storage.example.org:8443", activity.DisplayName);
        Assert.DoesNotContain("password", activity.DisplayName, StringComparison.Ordinal);
        Assert.DoesNotContain("synthetic-sas", activity.DisplayName, StringComparison.Ordinal);
    }

    [Fact]
    public void Invalid_outbound_urls_are_removed_instead_of_exported()
    {
        using var activity = CreateCompletedActivity(ActivityKind.Client, item =>
        {
            item.DisplayName = "GET not-an-absolute-url/private";
            item.SetTag("http.request.method", "GET");
            item.SetTag("url.full", "not-an-absolute-url/private?sig=secret");
            item.SetTag("http.url", "file:///private/oauth-code-secret");
        });

        processor.OnEnd(activity);

        Assert.Null(activity.GetTagItem("url.full"));
        Assert.Null(activity.GetTagItem("http.url"));
        Assert.Equal("GET remote", activity.DisplayName);
    }

    [Fact]
    public void Database_text_is_removed_without_changing_status_or_operational_tags()
    {
        using var activity = CreateCompletedActivity(ActivityKind.Client, item =>
        {
            item.DisplayName = "SELECT * FROM Users WHERE Email = 'person@example.org'";
            item.SetTag("db.system.name", "mssql");
            item.SetTag("db.operation.name", "SELECT");
            item.SetTag("db.statement",
                "SELECT * FROM Users WHERE Email = 'person@example.org'");
            item.SetTag("db.query.text",
                "SELECT * FROM Projects WHERE Slug = 'private-ngo-slug'");
            item.SetStatus(ActivityStatusCode.Error, "synthetic database failure");
        });
        var traceId = activity.TraceId;
        var spanId = activity.SpanId;

        processor.OnEnd(activity);

        Assert.Null(activity.GetTagItem("db.statement"));
        Assert.Null(activity.GetTagItem("db.query.text"));
        Assert.Equal("mssql", activity.GetTagItem("db.system.name"));
        Assert.Equal("SELECT", activity.GetTagItem("db.operation.name"));
        Assert.Equal("SELECT", activity.DisplayName);
        Assert.Equal(ActivityStatusCode.Error, activity.Status);
        Assert.Null(activity.StatusDescription);
        Assert.Equal(traceId, activity.TraceId);
        Assert.Equal(spanId, activity.SpanId);
    }

    private static Activity CreateCompletedActivity(
        ActivityKind kind,
        Action<Activity> configure)
    {
        var sourceName = $"FundingPlatform.UnitTests.Telemetry.{Guid.NewGuid():N}";
        using var listener = new ActivityListener
        {
            ShouldListenTo = source => source.Name == sourceName,
            Sample = static (ref ActivityCreationOptions<ActivityContext> _) =>
                ActivitySamplingResult.AllDataAndRecorded,
            SampleUsingParentId = static (ref ActivityCreationOptions<string> _) =>
                ActivitySamplingResult.AllDataAndRecorded
        };
        ActivitySource.AddActivityListener(listener);

        using var source = new ActivitySource(sourceName);
        var activity = source.StartActivity("synthetic raw display name", kind) ??
            throw new InvalidOperationException("The synthetic activity was not created.");
        configure(activity);
        activity.Stop();
        return activity;
    }
}
