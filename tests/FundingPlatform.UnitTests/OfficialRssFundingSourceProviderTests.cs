using System.Net;
using System.Net.Http.Headers;
using System.Text;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Infrastructure.FundingSources;
using FundingPlatform.Infrastructure.FundingSources.Rss;
using Microsoft.Extensions.Options;

namespace FundingPlatform.UnitTests;

public sealed class OfficialRssFundingSourceProviderTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 8, 22, 18, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Xxe_feed_is_rejected_without_resolving_entities()
    {
        const string xml = "<!DOCTYPE rss [<!ENTITY xxe SYSTEM 'file:///etc/passwd'>]>" +
                           "<rss><channel><item><title>&xxe;</title>" +
                           "<link>https://official.example.org/fund/1</link></item></channel></rss>";
        var provider = CreateProvider(_ => Xml(xml));

        await Assert.ThrowsAsync<FundingSourceImportException>(() =>
            provider.FetchOpenAsync("*", 10, Governance(), CancellationToken.None));
    }

    [Fact]
    public async Task Response_larger_than_durable_cap_is_rejected()
    {
        var provider = CreateProvider(_ => Xml(new string('x', 5_000)));

        await Assert.ThrowsAsync<FundingSourceImportException>(() =>
            provider.FetchOpenAsync("*", 10, Governance(maximumBytes: 4_096),
                CancellationToken.None));
    }

    [Theory]
    [InlineData(HttpStatusCode.Redirect, "https://official.example.org/feed.xml")]
    [InlineData(HttpStatusCode.OK, "https://other.example.org/feed.xml")]
    public async Task Redirect_or_off_origin_response_is_rejected(
        HttpStatusCode status,
        string responseUri)
    {
        var provider = CreateProvider(_ =>
        {
            var response = Xml("<rss><channel /></rss>", status);
            response.RequestMessage = new HttpRequestMessage(HttpMethod.Get, responseUri);
            return response;
        });

        await Assert.ThrowsAsync<FundingSourceImportException>(() =>
            provider.FetchOpenAsync("*", 10, Governance(), CancellationToken.None));
    }

    [Theory]
    [InlineData(HttpStatusCode.Unauthorized)]
    [InlineData(HttpStatusCode.Forbidden)]
    [InlineData(HttpStatusCode.TooManyRequests)]
    public async Task Protected_or_rate_limited_robots_is_fail_closed(HttpStatusCode status)
    {
        var options = WithRobots(ValidOptions(), "Enforce");
        var provider = CreateProvider(_ => new HttpResponseMessage(status)
        {
            Content = new StringContent(string.Empty, Encoding.UTF8, "text/plain")
        }, options, passRobotsToResponder: true);

        await Assert.ThrowsAsync<FundingSourceImportException>(() =>
            provider.FetchOpenAsync(
                "*", 10, Governance(options: options), CancellationToken.None));
    }

    [Fact]
    public async Task Feed_timestamp_is_not_inferred_as_open_date_and_long_url_gets_bounded_id()
    {
        var longLink = "https://official.example.org/fund/" + new string('a', 300);
        var xml = $"<rss><channel><item><title>Community fund</title>" +
                  $"<link>{longLink}</link><pubDate>Fri, 21 Aug 2026 12:00:00 GMT</pubDate>" +
                  "</item></channel></rss>";
        var provider = CreateProvider(_ => Xml(xml));

        var result = await provider.FetchOpenAsync(
            "*", 10, Governance(), CancellationToken.None);

        var observation = Assert.Single(result);
        Assert.StartsWith("url-sha256:", observation.ExternalId, StringComparison.Ordinal);
        Assert.True(observation.ExternalId.Length <= 250);
        Assert.Null(observation.Opportunity.OpenDate);
        Assert.Contains("publishedAtUtc", observation.RawJson, StringComparison.Ordinal);
        Assert.Equal(longLink, observation.SourceUrl);
    }

    [Fact]
    public async Task Local_feed_or_license_drift_is_rejected_before_any_network_request()
    {
        var calls = 0;
        var changed = ValidOptions();
        changed.LicenseUri = "https://official.example.org/changed-terms";
        var provider = CreateProvider(_ =>
        {
            calls++;
            return Xml("<rss><channel /></rss>");
        }, changed);

        await Assert.ThrowsAsync<FundingSourceImportException>(() =>
            provider.FetchOpenAsync("*", 10, Governance(), CancellationToken.None));

        Assert.Equal(0, calls);
    }

    [Fact]
    public void Official_rss_rejects_a_not_applicable_robots_policy()
    {
        var options = ValidOptions();
        options.RobotsPolicy = "NotApplicable";

        Assert.False(OfficialRssOptions.IsValid(options));
    }

    private static OfficialRssFundingSourceProvider CreateProvider(
        Func<HttpRequestMessage, HttpResponseMessage> responder,
        OfficialRssOptions? options = null,
        bool passRobotsToResponder = false)
    {
        var client = new HttpClient(new StubHandler(request =>
            !passRobotsToResponder && request.RequestUri?.AbsolutePath == "/robots.txt"
                ? Text("User-agent: *\nAllow: /")
                : responder(request)))
        {
            BaseAddress = new Uri("https://official.example.org")
        };
        return new OfficialRssFundingSourceProvider(
            client,
            Options.Create(options ?? ValidOptions()),
            new AllowingAuthorizer(),
            new GovernedAcquisitionRequestGate(new FixedTimeProvider(Now)),
            new FixedTimeProvider(Now));
    }

    private static OfficialRssOptions ValidOptions() => new()
    {
        Enabled = true,
        FeedUri = "https://official.example.org/feed.xml",
        AllowedHosts = "official.example.org",
        SourceName = "Official foundation feed",
        SponsorName = "Official Foundation",
        LicenseName = "Official terms",
        LicenseUri = "https://official.example.org/terms",
        ComplianceApproved = true,
        RobotsPolicy = "Enforce",
        MinimumDelaySeconds = 1,
        TimeoutSeconds = 10,
        MaximumBytes = 8_192,
        MaximumCharacters = 20_000,
        MaximumItems = 25,
        UserAgent = "FundingPlatform/1.0"
    };

    private static OfficialRssOptions WithRobots(
        OfficialRssOptions options,
        string value)
    {
        options.RobotsPolicy = value;
        return options;
    }

    private static GovernedAcquisitionContext Governance(
        int maximumBytes = 8_192,
        OfficialRssOptions? options = null) =>
        new(7, 600, maximumBytes, 30, 1,
            OfficialRssPolicyFingerprint.Compute(options ?? ValidOptions(), 1));

    private static HttpResponseMessage Xml(
        string content,
        HttpStatusCode status = HttpStatusCode.OK)
    {
        var response = new HttpResponseMessage(status)
        {
            Content = new StringContent(content, Encoding.UTF8)
        };
        response.Content.Headers.ContentType = new MediaTypeHeaderValue("application/rss+xml")
        {
            CharSet = "utf-8"
        };
        return response;
    }

    private static HttpResponseMessage Text(string content) => new()
    {
        Content = new StringContent(content, Encoding.UTF8, "text/plain")
    };

    private sealed class StubHandler(
        Func<HttpRequestMessage, HttpResponseMessage> responder) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var response = responder(request);
            response.RequestMessage ??= request;
            return Task.FromResult(response);
        }
    }

    private sealed class AllowingAuthorizer : IFundingSourceAcquisitionAuthorizer
    {
        public Task<FundingSourceAcquisitionAuthorization> AuthorizeAsync(
            int fundingSourceId,
            Uri exactDestination,
            byte[] canonicalDestinationHash,
            byte[] acquisitionPolicyFingerprint,
            int minimumIntervalMilliseconds,
            DateTimeOffset nowUtc,
            CancellationToken cancellationToken) => Task.FromResult(new
                FundingSourceAcquisitionAuthorization(
                    true,
                    "reserved",
                    nowUtc,
                    nowUtc.AddMilliseconds(minimumIntervalMilliseconds),
                    0,
                    600,
                    8_192,
                    30,
                    1,
                    acquisitionPolicyFingerprint));
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
}
