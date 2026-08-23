using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml;
using System.Xml.Linq;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Infrastructure.FundingSources.Rss;

public sealed partial class OfficialRssFundingSourceProvider : IFundingSourceProvider
{
    public const string Code = "official-rss";

    private readonly HttpClient httpClient;
    private readonly OfficialRssOptions options;
    private readonly IFundingSourceAcquisitionAuthorizer acquisitionAuthorizer;
    private readonly GovernedAcquisitionRequestGate requestGate;
    private readonly TimeProvider timeProvider;
    private readonly Uri feedUri;
    private readonly IReadOnlySet<string> allowedHosts;

    public OfficialRssFundingSourceProvider(
        HttpClient httpClient,
        IOptions<OfficialRssOptions> options,
        IFundingSourceAcquisitionAuthorizer acquisitionAuthorizer,
        GovernedAcquisitionRequestGate requestGate,
        TimeProvider timeProvider)
    {
        this.options = options.Value;
        if (!OfficialRssOptions.IsValid(this.options) || !this.options.Enabled)
            throw new InvalidOperationException("The official RSS provider is not governed and enabled.");
        this.httpClient = httpClient;
        this.acquisitionAuthorizer = acquisitionAuthorizer;
        this.requestGate = requestGate;
        this.timeProvider = timeProvider;
        feedUri = new Uri(this.options.FeedUri, UriKind.Absolute);
        allowedHosts = this.options.GetAllowedHosts();
        if (httpClient.BaseAddress is null ||
            !OriginEquals(httpClient.BaseAddress, feedUri))
            throw new InvalidOperationException("The official RSS HttpClient origin is not allowlisted.");
        Source = new FundingSourceDescriptor(
            Code,
            this.options.SourceName,
            ProviderType: 2,
            feedUri.GetLeftPart(UriPartial.Authority),
            this.options.LicenseUri,
            null,
            this.options.MinimumDelaySeconds,
            this.options.UserAgent);
    }

    public FundingSourceDescriptor Source { get; }

    public async Task<IReadOnlyList<FundingSourceObservation>> FetchOpenAsync(
        string keyword,
        int maximumResults,
        GovernedAcquisitionContext governance,
        CancellationToken cancellationToken)
    {
        if (maximumResults is < 1 or > 25) throw new ArgumentOutOfRangeException(nameof(maximumResults));
        if (!options.Enabled || !options.ComplianceApproved)
            throw new FundingSourceImportException("The official RSS kill switch is active.");
        var localFingerprint = OfficialRssPolicyFingerprint.Compute(
            options, governance.AcquisitionPolicyVersion);
        if (governance.AcquisitionPolicyFingerprint is not { Length: 32 } ||
            !CryptographicOperations.FixedTimeEquals(
                localFingerprint, governance.AcquisitionPolicyFingerprint))
            throw new FundingSourceImportException(
                "The official RSS configuration does not match the durable acquisition policy.");

        if (!await IsAllowedByRobotsAsync(governance, cancellationToken))
            throw new FundingSourceImportException("The official RSS robots policy denied acquisition.");

        using var response = await SendAsync(feedUri, governance, isRobots: false, cancellationToken);
        ValidateResponse(response.Response, feedUri, isRobots: false);
        var document = await ReadDocumentAsync(
            response.Response,
            Math.Min(options.MaximumBytes, response.MaximumResponseBytes),
            cancellationToken);
        var observations = new List<FundingSourceObservation>();
        foreach (var item in EnumerateItems(document))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var title = Normalize(item.Title, 500);
            var description = Normalize(StripMarkup(item.Description), 8_000);
            if (title is null || !TryAllowedUri(item.Link, out var link)) continue;
            if (!Matches(keyword, title, description)) continue;
            var externalId = StableExternalId(item.Id, link);
            var retrievedAt = timeProvider.GetUtcNow();
            var raw = JsonSerializer.Serialize(new
            {
                schemaVersion = 1,
                providerCode = Code,
                id = externalId,
                title,
                description,
                link = link.AbsoluteUri,
                publishedAtUtc = item.PublishedAtUtc
            });
            var opportunity = new ExternalFundingOpportunity(
                Code,
                externalId,
                externalId,
                title,
                options.SponsorName,
                description,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                link.AbsoluteUri,
                link.AbsoluteUri,
                retrievedAt);
            observations.Add(new FundingSourceObservation(
                externalId,
                link.AbsoluteUri,
                raw,
                SHA256.HashData(Encoding.UTF8.GetBytes(raw)),
                retrievedAt,
                opportunity));
            if (observations.Count >= Math.Min(maximumResults, options.MaximumItems)) break;
        }
        return observations;
    }

    private async Task<bool> IsAllowedByRobotsAsync(
        GovernedAcquisitionContext governance,
        CancellationToken cancellationToken)
    {
        var robotsUri = new Uri(feedUri, "/robots.txt");
        using var response = await SendAsync(
            robotsUri, governance, isRobots: true, cancellationToken);
        if (response.Response.StatusCode is HttpStatusCode.NotFound or HttpStatusCode.Gone)
            return true;
        if (!response.Response.IsSuccessStatusCode) return false;
        ValidateResponse(response.Response, robotsUri, isRobots: true);
        var bytes = await ReadBoundedAsync(
            response.Response,
            Math.Min(524_288, response.MaximumResponseBytes),
            cancellationToken);
        var content = Encoding.UTF8.GetString(bytes);
        return RobotsPolicyEvaluator.IsAllowed(content, options.UserAgent, feedUri.PathAndQuery);
    }

    private async Task<AuthorizedResponse> SendAsync(
        Uri exactDestination,
        GovernedAcquisitionContext governance,
        bool isRobots,
        CancellationToken cancellationToken)
    {
        using var permit = await requestGate.AuthorizeAsync(
            acquisitionAuthorizer,
            governance,
            exactDestination,
            TimeSpan.FromSeconds(options.MinimumDelaySeconds),
            cancellationToken);
        using var request = new HttpRequestMessage(HttpMethod.Get, exactDestination);
        request.Headers.UserAgent.ParseAdd(options.UserAgent);
        request.Headers.Accept.ParseAdd(isRobots ? "text/plain" : "application/rss+xml");
        if (!isRobots) request.Headers.Accept.ParseAdd("application/atom+xml");
        var response = await httpClient.SendAsync(
            request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        return new AuthorizedResponse(response, permit.MaximumResponseBytes);
    }

    private async Task<XDocument> ReadDocumentAsync(
        HttpResponseMessage response,
        int maximumBytes,
        CancellationToken cancellationToken)
    {
        var bytes = await ReadBoundedAsync(response, maximumBytes, cancellationToken);
        await using var stream = new MemoryStream(bytes, writable: false);
        var settings = new XmlReaderSettings
        {
            Async = true,
            DtdProcessing = DtdProcessing.Prohibit,
            XmlResolver = null,
            MaxCharactersInDocument = options.MaximumCharacters,
            MaxCharactersFromEntities = 0,
            IgnoreComments = true,
            IgnoreProcessingInstructions = true
        };
        using var reader = XmlReader.Create(stream, settings);
        try
        {
            return await XDocument.LoadAsync(reader, LoadOptions.None, cancellationToken);
        }
        catch (XmlException exception)
        {
            throw new FundingSourceImportException(
                "The official RSS feed was not valid safe XML.", exception);
        }
    }

    private static IEnumerable<FeedItem> EnumerateItems(XDocument document)
    {
        var root = document.Root;
        if (root is null) yield break;
        var entries = root.Name.LocalName.Equals("feed", StringComparison.OrdinalIgnoreCase)
            ? root.Elements().Where(element => element.Name.LocalName == "entry")
            : root.Descendants().Where(element => element.Name.LocalName == "item");
        foreach (var entry in entries)
        {
            var title = Value(entry, "title");
            var description = Value(entry, "description") ?? Value(entry, "summary") ??
                              Value(entry, "content");
            var id = Value(entry, "guid") ?? Value(entry, "id");
            var linkElement = entry.Elements().FirstOrDefault(element => element.Name.LocalName == "link");
            var link = linkElement?.Attribute("href")?.Value ?? linkElement?.Value;
            var date = Value(entry, "pubDate") ?? Value(entry, "published") ?? Value(entry, "updated");
            DateTimeOffset? published = DateTimeOffset.TryParse(
                date, CultureInfo.InvariantCulture,
                DateTimeStyles.AllowWhiteSpaces | DateTimeStyles.AssumeUniversal,
                out var parsed) ? parsed.ToUniversalTime() : null;
            yield return new FeedItem(id, title, description, link, published);
        }
    }

    private bool TryAllowedUri(string? value, out Uri uri)
    {
        uri = null!;
        if (!Uri.TryCreate(value, UriKind.Absolute, out var parsed) ||
            parsed.Scheme != Uri.UriSchemeHttps || parsed.Port != 443 ||
            !string.IsNullOrEmpty(parsed.UserInfo) || !string.IsNullOrEmpty(parsed.Fragment) ||
            !allowedHosts.Contains(parsed.Host))
            return false;
        uri = parsed;
        return true;
    }

    private static async Task<byte[]> ReadBoundedAsync(
        HttpResponseMessage response,
        int maximumBytes,
        CancellationToken cancellationToken)
    {
        if (response.Content.Headers.ContentLength > maximumBytes)
            throw new FundingSourceImportException("The official RSS response exceeded its limit.");
        await using var input = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var output = new MemoryStream();
        var buffer = new byte[16 * 1024];
        int read;
        while ((read = await input.ReadAsync(buffer, cancellationToken)) > 0)
        {
            if (output.Length + read > maximumBytes)
                throw new FundingSourceImportException("The official RSS response exceeded its limit.");
            await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
        }
        return output.ToArray();
    }

    private static void ValidateResponse(
        HttpResponseMessage response,
        Uri expected,
        bool isRobots)
    {
        var actual = response.RequestMessage?.RequestUri;
        if (actual is null || !OriginEquals(actual, expected) ||
            !string.Equals(actual.PathAndQuery, expected.PathAndQuery, StringComparison.Ordinal) ||
            (int)response.StatusCode is >= 300 and < 400)
            throw new FundingSourceImportException("The official RSS response origin was rejected.");
        if (!response.IsSuccessStatusCode)
            throw new FundingSourceImportException(
                $"The official RSS request failed with HTTP status {(int)response.StatusCode}.");
        var mediaType = response.Content.Headers.ContentType?.MediaType;
        var valid = isRobots
            ? mediaType is null || mediaType.Equals("text/plain", StringComparison.OrdinalIgnoreCase)
            : mediaType is not null && new[]
            {
                "application/rss+xml", "application/atom+xml", "application/xml", "text/xml"
            }.Contains(mediaType, StringComparer.OrdinalIgnoreCase);
        if (!valid) throw new FundingSourceImportException("The official RSS content type was rejected.");
    }

    private static bool OriginEquals(Uri left, Uri right) =>
        left.Scheme == Uri.UriSchemeHttps && right.Scheme == Uri.UriSchemeHttps &&
        left.Port == 443 && right.Port == 443 &&
        string.Equals(left.Host, right.Host, StringComparison.OrdinalIgnoreCase);

    private static bool Matches(string keyword, string title, string? description) =>
        string.IsNullOrWhiteSpace(keyword) || keyword is "*" or "open" ||
        title.Contains(keyword, StringComparison.OrdinalIgnoreCase) ||
        description?.Contains(keyword, StringComparison.OrdinalIgnoreCase) == true;

    private static string? Value(XElement parent, string localName) =>
        parent.Elements().FirstOrDefault(element =>
            element.Name.LocalName.Equals(localName, StringComparison.OrdinalIgnoreCase))?.Value;

    private static string? Normalize(string? value, int maximumLength)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var normalized = WhitespaceRegex().Replace(
            value.Normalize(NormalizationForm.FormKC), " ").Trim();
        return normalized.Length == 0 ? null : normalized[..Math.Min(maximumLength, normalized.Length)];
    }

    private static string StableExternalId(string? suppliedId, Uri canonicalLink)
    {
        var normalized = Normalize(suppliedId, 251);
        if (normalized is { Length: <= 250 }) return normalized;
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(canonicalLink.AbsoluteUri));
        return $"url-sha256:{Convert.ToHexString(hash)}";
    }

    private static string? StripMarkup(string? value) =>
        value is null ? null : WebUtility.HtmlDecode(HtmlTagRegex().Replace(value, " "));

    [GeneratedRegex("<[^>]{0,1000}>", RegexOptions.CultureInvariant)]
    private static partial Regex HtmlTagRegex();

    [GeneratedRegex("\\s+", RegexOptions.CultureInvariant)]
    private static partial Regex WhitespaceRegex();

    private sealed record FeedItem(
        string? Id,
        string? Title,
        string? Description,
        string? Link,
        DateTimeOffset? PublishedAtUtc);

    private sealed class AuthorizedResponse(
        HttpResponseMessage response,
        int maximumResponseBytes) : IDisposable
    {
        public HttpResponseMessage Response { get; } = response;
        public int MaximumResponseBytes { get; } = maximumResponseBytes;
        public void Dispose() => Response.Dispose();
    }
}
