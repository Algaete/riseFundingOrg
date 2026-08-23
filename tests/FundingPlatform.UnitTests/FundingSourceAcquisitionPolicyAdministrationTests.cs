using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Infrastructure.FundingSources.Rss;

namespace FundingPlatform.UnitTests;

public sealed class FundingSourceAcquisitionPolicyAdministrationTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 8, 22, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task Request_hash_is_stable_after_host_and_endpoint_canonicalization()
    {
        var repository = new RecordingRepository();
        var service = new FundingSourceAcquisitionPolicyAdministrationService(
            repository, new FixedTimeProvider(Now));
        var command = ValidCommand() with
        {
            AllowedHosts = ["LICENSE.EXAMPLE.ORG", "official.example.org"],
            AllowedEndpoints =
            [
                new(FundingSourceAcquisitionEndpointKind.Robots,
                    "https://official.example.org/robots.txt"),
                new(FundingSourceAcquisitionEndpointKind.License,
                    "https://official.example.org/terms"),
                new(FundingSourceAcquisitionEndpointKind.Acquisition,
                    "https://official.example.org/feed.xml")
            ]
        };

        await service.UpsertAsync(command, CancellationToken.None);
        var firstHash = repository.RequestHash;
        await service.UpsertAsync(command with
        {
            AllowedHosts = ["official.example.org", "license.example.org"],
            AllowedEndpoints = command.AllowedEndpoints.Reverse().ToArray()
        }, CancellationToken.None);

        Assert.Equal(firstHash, repository.RequestHash);
        Assert.Equal(new[] { "license.example.org", "official.example.org" },
            repository.Command!.AllowedHosts);
        Assert.Equal(32, repository.IdempotencyKeyHash!.Length);
    }

    [Fact]
    public async Task Request_hash_changes_when_a_durable_limit_changes()
    {
        var repository = new RecordingRepository();
        var service = new FundingSourceAcquisitionPolicyAdministrationService(
            repository, new FixedTimeProvider(Now));

        await service.UpsertAsync(ValidCommand(), CancellationToken.None);
        var baseline = repository.RequestHash;
        await service.UpsertAsync(ValidCommand() with
        {
            MaximumResponseBytes = 524_288
        }, CancellationToken.None);

        Assert.NotEqual(baseline, repository.RequestHash);
    }

    [Fact]
    public async Task Endpoint_outside_the_exact_host_allowlist_is_rejected_before_SQL()
    {
        var repository = new RecordingRepository();
        var service = new FundingSourceAcquisitionPolicyAdministrationService(
            repository, new FixedTimeProvider(Now));
        var command = ValidCommand() with
        {
            AllowedEndpoints =
            [
                new(FundingSourceAcquisitionEndpointKind.Acquisition,
                    "https://official.example.org/feed.xml"),
                new(FundingSourceAcquisitionEndpointKind.License,
                    "https://different.example.org/terms"),
                new(FundingSourceAcquisitionEndpointKind.Robots,
                    "https://official.example.org/robots.txt")
            ],
            LicenseUrl = "https://different.example.org/terms"
        };

        await Assert.ThrowsAsync<ArgumentException>(() =>
            service.UpsertAsync(command, CancellationToken.None));
        Assert.Equal(0, repository.Calls);
    }

    [Fact]
    public void Official_rss_preflight_requires_the_exact_runtime_boundary()
    {
        var options = ValidOptions();
        OfficialRssPolicyPreflight.ValidateEnabledPolicy(ValidCommand(), options);

        Assert.Throws<InvalidOperationException>(() =>
            OfficialRssPolicyPreflight.ValidateEnabledPolicy(
                ValidCommand() with { MaximumResponseBytes = 524_288 }, options));
        Assert.Throws<InvalidOperationException>(() =>
            OfficialRssPolicyPreflight.ValidateEnabledPolicy(
                ValidCommand() with
                {
                    BaseUrl = "https://official.example.org/another-feed.xml"
                }, options));
    }

    private static FundingSourceAcquisitionPolicyCommand ValidCommand() => new(
        Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
        "official-rss",
        "https://official.example.org/feed.xml",
        "Official terms",
        "https://official.example.org/terms",
        Now.AddDays(-1),
        Now.AddDays(90),
        "enforce",
        1,
        Now.AddDays(-1),
        Now.AddDays(30),
        ["official.example.org"],
        [
            new(FundingSourceAcquisitionEndpointKind.Acquisition,
                "https://official.example.org/feed.xml"),
            new(FundingSourceAcquisitionEndpointKind.License,
                "https://official.example.org/terms"),
            new(FundingSourceAcquisitionEndpointKind.Robots,
                "https://official.example.org/robots.txt")
        ],
        30,
        1_048_576,
        90,
        3_600,
        true,
        true,
        "policy-request-0001",
        "policy-test-0001");

    private static OfficialRssOptions ValidOptions() => new()
    {
        Enabled = true,
        FeedUri = "https://official.example.org/feed.xml",
        AllowedHosts = "official.example.org",
        SourceName = "Official source",
        SponsorName = "Official sponsor",
        LicenseName = "Official terms",
        LicenseUri = "https://official.example.org/terms",
        ComplianceApproved = true,
        RobotsPolicy = "Enforce",
        RobotsPolicyVersion = 1,
        MinimumDelaySeconds = 2,
        TimeoutSeconds = 15,
        MaximumBytes = 1_048_576,
        MaximumCharacters = 1_000_000,
        MaximumItems = 25,
        UserAgent = "FundingPlatform-Workers/1.0"
    };

    private sealed class RecordingRepository : IFundingSourceAcquisitionPolicyRepository
    {
        public int Calls { get; private set; }
        public FundingSourceAcquisitionPolicyCommand? Command { get; private set; }
        public byte[]? IdempotencyKeyHash { get; private set; }
        public byte[]? RequestHash { get; private set; }

        public Task<FundingSourceAcquisitionPolicyMutation> UpsertAsync(
            FundingSourceAcquisitionPolicyCommand command,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
        {
            Calls++;
            Command = command;
            IdempotencyKeyHash = idempotencyKeyHash;
            RequestHash = requestHash;
            return Task.FromResult(new FundingSourceAcquisitionPolicyMutation(
                true,
                "upserted",
                1,
                Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
                2,
                new byte[32],
                command.IsEnabled,
                false));
        }
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
}
