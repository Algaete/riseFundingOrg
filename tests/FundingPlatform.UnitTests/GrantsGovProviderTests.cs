using System.Diagnostics;
using System.Text.Json;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Infrastructure.FundingSources;
using FundingPlatform.Infrastructure.FundingSources.GrantsGov;

namespace FundingPlatform.UnitTests;

public sealed class GrantsGovProviderTests
{
    [Fact]
    public async Task Provider_canonicalizes_raw_json_to_a_deterministic_hash()
    {
        var first = CreateProvider(
            SearchJson("1"),
            """{"errorcode":0,"data":{"opportunityNumber":"REF-1","opportunityTitle":"Title","owningAgencyCode":"AG","synopsis":{"synopsisDesc":"Description"}}}""");
        var second = CreateProvider(
            SearchJson("1"),
            """{"data":{"synopsis":{"synopsisDesc":"Description"},"owningAgencyCode":"AG","opportunityTitle":"Title","opportunityNumber":"REF-1"},"errorcode":0}""");

        var firstObservation = Assert.Single(await first.FetchOpenAsync(
            "nonprofit", 1, Governance(), CancellationToken.None));
        var secondObservation = Assert.Single(await second.FetchOpenAsync(
            "nonprofit", 1, Governance(), CancellationToken.None));

        Assert.Equal(firstObservation.RawJson, secondObservation.RawJson);
        Assert.Equal(firstObservation.ContentHash, secondObservation.ContentHash);
        Assert.Equal("1", firstObservation.ExternalId);
        using var raw = JsonDocument.Parse(firstObservation.RawJson);
        Assert.Equal(1, raw.RootElement.GetProperty("schemaVersion").GetInt32());
        Assert.Equal(
            "grants-gov",
            raw.RootElement.GetProperty("providerCode").GetString());
        Assert.Equal(
            "Title 1",
            raw.RootElement.GetProperty("searchHit").GetProperty("title").GetString());
        Assert.Equal(
            "REF-1",
            raw.RootElement.GetProperty("detail").GetProperty("data")
                .GetProperty("opportunityNumber").GetString());
    }

    [Fact]
    public async Task Provider_honors_minimum_delay_between_detail_requests()
    {
        var provider = CreateProvider(
            SearchJson("1", "2"),
            DetailJson("1"),
            DetailJson("2"));
        var stopwatch = Stopwatch.StartNew();

        var observations = await provider.FetchOpenAsync(
            "nonprofit", 2, Governance(), CancellationToken.None);

        stopwatch.Stop();
        Assert.Equal(2, observations.Count);
        Assert.True(
            stopwatch.Elapsed >= TimeSpan.FromMilliseconds(900),
            $"Expected a source delay; elapsed={stopwatch.Elapsed}.");
    }

    [Fact]
    public void Provider_rejects_non_allowlisted_base_address()
    {
        using var client = new HttpClient(new SequenceHandler(SearchJson("1")))
        {
            BaseAddress = new Uri("https://example.invalid/v1/api/")
        };

        Assert.Throws<InvalidOperationException>(() =>
            new GrantsGovFundingSourceProvider(
                client, new AllowingAuthorizer(),
                new GovernedAcquisitionRequestGate(TimeProvider.System),
                TimeProvider.System));
    }

    private static GrantsGovFundingSourceProvider CreateProvider(params string[] responses)
    {
        var client = new HttpClient(new SequenceHandler(responses))
        {
            BaseAddress = new Uri(GrantsGovFundingSourceProvider.ApiBaseUrl),
            Timeout = TimeSpan.FromSeconds(5)
        };
        return new GrantsGovFundingSourceProvider(
            client, new AllowingAuthorizer(),
            new GovernedAcquisitionRequestGate(TimeProvider.System),
            TimeProvider.System);
    }

    private static GovernedAcquisitionContext Governance() =>
        new(1, 60, 1_048_576, 30, 1, new byte[32]);

    private static string SearchJson(params string[] ids)
    {
        return System.Text.Json.JsonSerializer.Serialize(new
        {
            errorcode = 0,
            data = new
            {
                oppHits = ids.Select(id => new
                {
                    id,
                    number = $"REF-{id}",
                    title = $"Title {id}",
                    agency = "Agency",
                    openDate = "08/22/2026",
                    closeDate = "09/22/2026"
                })
            }
        });
    }

    private static string DetailJson(string id) => System.Text.Json.JsonSerializer.Serialize(new
    {
        errorcode = 0,
        data = new
        {
            opportunityNumber = $"REF-{id}",
            opportunityTitle = $"Title {id}",
            owningAgencyCode = "AG",
            synopsis = new { synopsisDesc = "Description" }
        }
    });

    private sealed class SequenceHandler(params string[] responses) : HttpMessageHandler
    {
        private int index;

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            if (index >= responses.Length)
            {
                throw new InvalidOperationException("No fake response remains.");
            }

            return Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.OK)
            {
                RequestMessage = request,
                Content = new StringContent(
                    responses[index++],
                    System.Text.Encoding.UTF8,
                    "application/json")
            });
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
            CancellationToken cancellationToken) => Task.FromResult(
                new FundingSourceAcquisitionAuthorization(
                    true, "reserved", nowUtc, nowUtc.AddMilliseconds(minimumIntervalMilliseconds),
                    0, 60, 1_048_576, 30, 1, acquisitionPolicyFingerprint));
    }
}
