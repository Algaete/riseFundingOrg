using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Infrastructure.FundingSources.GrantsGov;

public sealed partial class GrantsGovFundingSourceProvider(
    HttpClient httpClient,
    IFundingSourceAcquisitionAuthorizer acquisitionAuthorizer,
    GovernedAcquisitionRequestGate requestGate,
    TimeProvider timeProvider) : IFundingSourceProvider
{
    public const string Code = "grants-gov";
    public const string ApiBaseUrl = "https://api.grants.gov/v1/api/";

    private static readonly JsonSerializerOptions SerializerOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true
    };

    private static readonly Uri AllowedApiBaseUri = new(ApiBaseUrl, UriKind.Absolute);

    private readonly HttpClient httpClient = ValidateClient(httpClient);

    public FundingSourceDescriptor Source { get; } = new(
        Code,
        "Grants.gov",
        ProviderType: 1,
        ApiBaseUrl,
        "https://www.grants.gov/api/terms-conditions",
        "0 0 11 * * *",
        MinimumDelaySeconds: 1,
        "FundingPlatform-MVP/0.1");

    public async Task<IReadOnlyList<FundingSourceObservation>> FetchOpenAsync(
        string keyword,
        int maximumResults,
        GovernedAcquisitionContext governance,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(keyword);

        if (maximumResults is < 1 or > 25)
        {
            throw new ArgumentOutOfRangeException(
                nameof(maximumResults), maximumResults,
                "Maximum results must be between 1 and 25.");
        }

        using var searchResponse = await PostJsonWithRetryAsync(
            "search2",
            new
            {
                rows = maximumResults,
                keyword,
                oppStatuses = "posted",
                sortBy = "openDate|desc"
            },
            governance,
            cancellationToken);

        await EnsureSuccessAsync(searchResponse.Response, "search", cancellationToken);
        var searchJson = await ReadBoundedJsonAsync(
            searchResponse.Response, searchResponse.MaximumResponseBytes, cancellationToken);
        var searchPayload = JsonSerializer.Deserialize<GrantsGovSearchResponse>(
            searchJson, SerializerOptions);

        if (searchPayload is null || searchPayload.ErrorCode != 0 || searchPayload.Data is null)
        {
            throw new FundingSourceImportException("Grants.gov returned an invalid search result.");
        }

        if (searchPayload.Data.OpportunityHits is null)
        {
            throw new FundingSourceImportException("Grants.gov returned an invalid search result.");
        }

        var observations = new List<FundingSourceObservation>(
            Math.Min(maximumResults, searchPayload.Data.OpportunityHits.Count));
        var selectedHits = searchPayload.Data.OpportunityHits.Take(maximumResults).ToArray();
        for (var index = 0; index < selectedHits.Length; index++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var hit = selectedHits[index];
            var detail = await FetchDetailAsync(hit.Id, governance, cancellationToken);
            var retrievedAtUtc = timeProvider.GetUtcNow();
            var opportunity = Map(hit, detail.Data, retrievedAtUtc);
            var rawEnvelope = CreateRawEnvelope(hit, detail.CanonicalRawJson);
            observations.Add(new FundingSourceObservation(
                hit.Id,
                opportunity.SourceUrl,
                rawEnvelope,
                SHA256.HashData(Encoding.UTF8.GetBytes(rawEnvelope)),
                retrievedAtUtc,
                opportunity));
        }

        return observations;
    }

    private async Task<FetchedDetail> FetchDetailAsync(
        string opportunityId,
        GovernedAcquisitionContext governance,
        CancellationToken cancellationToken)
    {
        using var detailResponse = await PostJsonWithRetryAsync(
            "fetchOpportunity",
            new { opportunityId },
            governance,
            cancellationToken);

        await EnsureSuccessAsync(detailResponse.Response, "detail", cancellationToken);
        var rawJson = await ReadBoundedJsonAsync(
            detailResponse.Response, detailResponse.MaximumResponseBytes, cancellationToken);
        var payload = JsonSerializer.Deserialize<GrantsGovDetailResponse>(rawJson, SerializerOptions);

        if (payload is null || payload.ErrorCode != 0 || payload.Data is null)
        {
            throw new FundingSourceImportException(
                $"Grants.gov returned an invalid detail for opportunity '{opportunityId}'.");
        }

        return new FetchedDetail(payload.Data, CanonicalizeJson(rawJson));
    }

    private async Task<AuthorizedResponse> PostJsonWithRetryAsync(
        string relativePath,
        object body,
        GovernedAcquisitionContext governance,
        CancellationToken cancellationToken)
    {
        var json = JsonSerializer.Serialize(body, SerializerOptions);
        var destination = new Uri(AllowedApiBaseUri, relativePath);
        for (var attempt = 1; ; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                using var permit = await requestGate.AuthorizeAsync(
                    acquisitionAuthorizer,
                    governance,
                    destination,
                    TimeSpan.FromSeconds(Source.MinimumDelaySeconds),
                    cancellationToken);
                using var request = new HttpRequestMessage(HttpMethod.Post, relativePath)
                {
                    Content = new StringContent(json, Encoding.UTF8, "application/json")
                };
                var response = await httpClient.SendAsync(
                    request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
                ValidateResponseOrigin(response, destination);
                if (!IsTransient(response.StatusCode) || attempt >= 3)
                {
                    return new AuthorizedResponse(response, permit.MaximumResponseBytes);
                }

                response.Dispose();
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception) when (
                attempt < 3 && exception is HttpRequestException or TaskCanceledException)
            {
                // A bounded retry is safe because these provider operations are read-only.
            }

            await Task.Delay(TimeSpan.FromMilliseconds(200 * attempt), timeProvider, cancellationToken);
        }
    }

    private static Task EnsureSuccessAsync(
        HttpResponseMessage response,
        string operation,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (response.IsSuccessStatusCode)
        {
            return Task.CompletedTask;
        }

        return Task.FromException(new FundingSourceImportException(
            $"Grants.gov {operation} failed with HTTP status {(int)response.StatusCode}."));
    }

    private static async Task<string> ReadBoundedJsonAsync(
        HttpResponseMessage response,
        int governedMaximumBytes,
        CancellationToken cancellationToken)
    {
        var maximumBytes = Math.Min(1_048_576, governedMaximumBytes);
        var mediaType = response.Content.Headers.ContentType?.MediaType;
        if (!string.Equals(mediaType, "application/json", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(mediaType, "application/problem+json", StringComparison.OrdinalIgnoreCase))
        {
            throw new FundingSourceImportException("Grants.gov returned an unsupported content type.");
        }

        if (response.Content.Headers.ContentLength is long contentLength &&
            contentLength > maximumBytes)
        {
            throw new FundingSourceImportException("Grants.gov returned an oversized response.");
        }

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var buffer = new MemoryStream();
        var chunk = new byte[16 * 1024];
        while (true)
        {
            var read = await stream.ReadAsync(chunk, cancellationToken);
            if (read == 0)
            {
                break;
            }

            if (buffer.Length + read > maximumBytes)
            {
                throw new FundingSourceImportException("Grants.gov returned an oversized response.");
            }

            await buffer.WriteAsync(chunk.AsMemory(0, read), cancellationToken);
        }

        return Encoding.UTF8.GetString(buffer.ToArray());
    }

    private static string CanonicalizeJson(string json)
    {
        using var document = JsonDocument.Parse(json, new JsonDocumentOptions
        {
            AllowTrailingCommas = false,
            CommentHandling = JsonCommentHandling.Disallow,
            MaxDepth = 64
        });
        using var buffer = new MemoryStream();
        using (var writer = new Utf8JsonWriter(buffer, new JsonWriterOptions { Indented = false }))
        {
            WriteCanonical(document.RootElement, writer);
        }

        return Encoding.UTF8.GetString(buffer.ToArray());
    }

    private static string CreateRawEnvelope(
        GrantsGovSearchHit searchHit,
        string canonicalDetailJson)
    {
        using var detail = JsonDocument.Parse(canonicalDetailJson, new JsonDocumentOptions
        {
            AllowTrailingCommas = false,
            CommentHandling = JsonCommentHandling.Disallow,
            MaxDepth = 64
        });
        var envelope = JsonSerializer.Serialize(new
        {
            schemaVersion = 1,
            providerCode = Code,
            searchHit = new
            {
                searchHit.Id,
                searchHit.Number,
                searchHit.Title,
                searchHit.Agency,
                searchHit.OpenDate,
                searchHit.CloseDate
            },
            detail = detail.RootElement
        }, SerializerOptions);
        return CanonicalizeJson(envelope);
    }

    private static void WriteCanonical(JsonElement element, Utf8JsonWriter writer)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.Object:
                writer.WriteStartObject();
                foreach (var property in element.EnumerateObject()
                             .OrderBy(property => property.Name, StringComparer.Ordinal))
                {
                    writer.WritePropertyName(property.Name);
                    WriteCanonical(property.Value, writer);
                }

                writer.WriteEndObject();
                break;
            case JsonValueKind.Array:
                writer.WriteStartArray();
                foreach (var item in element.EnumerateArray())
                {
                    WriteCanonical(item, writer);
                }

                writer.WriteEndArray();
                break;
            default:
                element.WriteTo(writer);
                break;
        }
    }

    private static HttpClient ValidateClient(HttpClient client)
    {
        ArgumentNullException.ThrowIfNull(client);
        if (client.BaseAddress is null ||
            !string.Equals(client.BaseAddress.Scheme, Uri.UriSchemeHttps, StringComparison.Ordinal) ||
            !string.Equals(client.BaseAddress.Host, AllowedApiBaseUri.Host, StringComparison.OrdinalIgnoreCase) ||
            client.BaseAddress.Port != AllowedApiBaseUri.Port ||
            !string.Equals(
                client.BaseAddress.AbsolutePath.TrimEnd('/'),
                AllowedApiBaseUri.AbsolutePath.TrimEnd('/'),
                StringComparison.Ordinal))
        {
            throw new InvalidOperationException("Grants.gov HttpClient base address is not allowlisted.");
        }

        return client;
    }

    private static void ValidateResponseOrigin(HttpResponseMessage response, Uri expected)
    {
        var uri = response.RequestMessage?.RequestUri;
        if (uri is null ||
            uri.Scheme != Uri.UriSchemeHttps ||
            !string.Equals(uri.Host, AllowedApiBaseUri.Host, StringComparison.OrdinalIgnoreCase) ||
            uri.Port != AllowedApiBaseUri.Port ||
            !string.Equals(uri.PathAndQuery, expected.PathAndQuery, StringComparison.Ordinal))
        {
            response.Dispose();
            throw new FundingSourceImportException("Grants.gov response origin was rejected.");
        }
    }

    private static bool IsTransient(HttpStatusCode statusCode) => statusCode is
        HttpStatusCode.RequestTimeout or
        HttpStatusCode.TooManyRequests or
        HttpStatusCode.InternalServerError or
        HttpStatusCode.BadGateway or
        HttpStatusCode.ServiceUnavailable or
        HttpStatusCode.GatewayTimeout;

    private static ExternalFundingOpportunity Map(
        GrantsGovSearchHit hit,
        GrantsGovOpportunityData detail,
        DateTimeOffset retrievedAtUtc)
    {
        var synopsis = detail.Synopsis;
        var description = NormalizeText(synopsis?.Description);
        var eligibilityParts = new List<string>();

        if (!string.IsNullOrWhiteSpace(synopsis?.ApplicantEligibilityDescription))
        {
            eligibilityParts.Add(NormalizeText(synopsis.ApplicantEligibilityDescription)!);
        }

        if (synopsis?.ApplicantTypes is { Count: > 0 })
        {
            eligibilityParts.Add(string.Join(
                "; ",
                synopsis.ApplicantTypes
                    .Select(item => NormalizeText(item.Description))
                    .Where(item => !string.IsNullOrWhiteSpace(item))));
        }

        var categories = synopsis?.FundingActivityCategories?
            .Select(item => NormalizeText(item.Description))
            .Where(item => !string.IsNullOrWhiteSpace(item))
            .ToArray() ?? [];

        var instruments = synopsis?.FundingInstruments?
            .Select(item => NormalizeText(item.Description))
            .Where(item => !string.IsNullOrWhiteSpace(item))
            .ToArray() ?? [];

        var minimumAmount = ParsePositiveDecimal(synopsis?.AwardFloor);
        var maximumAmount = ParsePositiveDecimal(synopsis?.AwardCeiling);
        var sourceUrl = $"https://www.grants.gov/search-results-detail/{hit.Id}";

        return new ExternalFundingOpportunity(
            Code,
            hit.Id,
            detail.OpportunityNumber ?? hit.Number,
            NormalizeText(detail.OpportunityTitle) ?? NormalizeText(hit.Title) ?? hit.Id,
            NormalizeText(hit.Agency)
                ?? NormalizeText(synopsis?.AgencyName)
                ?? detail.OwningAgencyCode
                ?? "Grants.gov",
            description,
            eligibilityParts.Count == 0 ? null : string.Join("\n\n", eligibilityParts),
            instruments.Length == 0 ? null : string.Join(", ", instruments),
            categories.Length == 0 ? null : string.Join(", ", categories),
            ParseDate(hit.OpenDate) ?? ParseApiDate(synopsis?.PostingDateString),
            ParseDate(hit.CloseDate) ?? ParseApiDate(synopsis?.ResponseDateString),
            minimumAmount,
            maximumAmount,
            synopsis?.CostSharing,
            sourceUrl,
            NormalizeAbsoluteUrl(synopsis?.FundingDescriptionLinkUrl) ?? sourceUrl,
            retrievedAtUtc);
    }

    private static DateOnly? ParseDate(string? value)
    {
        if (DateOnly.TryParseExact(
                value,
                "MM/dd/yyyy",
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out var date))
        {
            return date;
        }

        return null;
    }

    private static DateOnly? ParseApiDate(string? value)
    {
        if (DateOnly.TryParseExact(
                value,
                "yyyy-MM-dd-HH-mm-ss",
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out var date))
        {
            return date;
        }

        return null;
    }

    private static decimal? ParsePositiveDecimal(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var normalized = value.Replace(",", string.Empty, StringComparison.Ordinal);
        return decimal.TryParse(
                   normalized,
                   NumberStyles.Number,
                   CultureInfo.InvariantCulture,
                   out var amount) && amount > 0
            ? amount
            : null;
    }

    private static string? NormalizeAbsoluteUrl(string? value)
    {
        return Uri.TryCreate(value, UriKind.Absolute, out var uri) &&
               (uri.Scheme == Uri.UriSchemeHttps || uri.Scheme == Uri.UriSchemeHttp)
            ? uri.ToString()
            : null;
    }

    private static string? NormalizeText(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var decoded = WebUtility.HtmlDecode(value);
        var withoutMarkup = HtmlElementRegex().Replace(decoded, " ");
        return WhitespaceRegex().Replace(withoutMarkup, " ").Trim();
    }

    [GeneratedRegex("<[^>]+>", RegexOptions.CultureInvariant)]
    private static partial Regex HtmlElementRegex();

    [GeneratedRegex("\\s+", RegexOptions.CultureInvariant)]
    private static partial Regex WhitespaceRegex();

    private sealed record GrantsGovSearchResponse(
        [property: System.Text.Json.Serialization.JsonPropertyName("errorcode")] int ErrorCode,
        [property: System.Text.Json.Serialization.JsonPropertyName("data")] GrantsGovSearchData? Data);

    private sealed record GrantsGovSearchData(
        [property: System.Text.Json.Serialization.JsonPropertyName("oppHits")]
        IReadOnlyList<GrantsGovSearchHit> OpportunityHits);

    private sealed record GrantsGovSearchHit(
        string Id,
        string Number,
        string Title,
        string? Agency,
        string? OpenDate,
        string? CloseDate);

    private sealed record GrantsGovDetailResponse(
        [property: System.Text.Json.Serialization.JsonPropertyName("errorcode")] int ErrorCode,
        [property: System.Text.Json.Serialization.JsonPropertyName("data")] GrantsGovOpportunityData? Data);

    private sealed record GrantsGovOpportunityData(
        string? OpportunityNumber,
        string? OpportunityTitle,
        string? OwningAgencyCode,
        GrantsGovSynopsis? Synopsis);

    private sealed record GrantsGovSynopsis(
        [property: System.Text.Json.Serialization.JsonPropertyName("synopsisDesc")] string? Description,
        [property: System.Text.Json.Serialization.JsonPropertyName("applicantEligibilityDesc")]
        string? ApplicantEligibilityDescription,
        string? AgencyName,
        string? AwardFloor,
        string? AwardCeiling,
        bool? CostSharing,
        [property: System.Text.Json.Serialization.JsonPropertyName("fundingDescLinkUrl")]
        string? FundingDescriptionLinkUrl,
        [property: System.Text.Json.Serialization.JsonPropertyName("postingDateStr")]
        string? PostingDateString,
        [property: System.Text.Json.Serialization.JsonPropertyName("responseDateStr")]
        string? ResponseDateString,
        IReadOnlyList<GrantsGovDescription>? ApplicantTypes,
        IReadOnlyList<GrantsGovDescription>? FundingInstruments,
        IReadOnlyList<GrantsGovDescription>? FundingActivityCategories);

    private sealed record GrantsGovDescription(string? Description);

    private sealed record FetchedDetail(
        GrantsGovOpportunityData Data,
        string CanonicalRawJson);

    private sealed class AuthorizedResponse(
        HttpResponseMessage response,
        int maximumResponseBytes) : IDisposable
    {
        public HttpResponseMessage Response { get; } = response;
        public int MaximumResponseBytes { get; } = maximumResponseBytes;
        public void Dispose() => Response.Dispose();
    }
}
