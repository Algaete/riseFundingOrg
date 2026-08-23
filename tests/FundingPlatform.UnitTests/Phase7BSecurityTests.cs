using System.Net;
using System.Security.Claims;
using System.Security.Cryptography;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Application.Imports;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Infrastructure.FundingSources;
using FundingPlatform.Infrastructure.FundingSources.Rss;
using FundingPlatform.Workers.Configuration;
using FundingPlatform.Workers.Security;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.UnitTests;

public sealed class Phase7BSecurityTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.UtcNow;

    [Theory]
    [InlineData("0x8DDEADBEEF", "\"0x8DDEADBEEF\"")]
    [InlineData("\"0x8DDEADBEEF\"", "\"0x8DDEADBEEF\"")]
    [InlineData("W/\"0x8DDEADBEEF\"", "\"0x8DDEADBEEF\"")]
    public void Blob_etags_have_one_canonical_quoted_form(string input, string expected)
    {
        Assert.True(BlobETagNormalizer.TryNormalize(input, out var normalized));
        Assert.Equal(expected, normalized);
    }

    [Theory]
    [InlineData("")]
    [InlineData("\"unterminated")]
    [InlineData("a,b")]
    [InlineData("a\\b")]
    [InlineData("a\nb")]
    public void Blob_etags_reject_ambiguous_or_control_values(string input) =>
        Assert.False(BlobETagNormalizer.TryNormalize(input, out _));

    [Fact]
    public void Parser_settings_hash_covers_stack_depth_and_source_byte_limit()
    {
        var baseline = SourceDocumentExtractionSettings.ComputeHash(
            "fundingplatform-pdf-text", "1-pdfpig-0.1.15",
            500_000, 250, 2_097_152, 64, 10_485_760);
        var stackChanged = SourceDocumentExtractionSettings.ComputeHash(
            "fundingplatform-pdf-text", "1-pdfpig-0.1.15",
            500_000, 250, 2_097_152, 65, 10_485_760);
        var bytesChanged = SourceDocumentExtractionSettings.ComputeHash(
            "fundingplatform-pdf-text", "1-pdfpig-0.1.15",
            500_000, 250, 2_097_152, 64, 10_485_761);

        Assert.NotEqual(baseline, stackChanged);
        Assert.NotEqual(baseline, bytesChanged);
    }

    [Theory]
    [InlineData("100.64.0.1")]
    [InlineData("192.0.2.1")]
    [InlineData("198.18.0.1")]
    [InlineData("198.51.100.1")]
    [InlineData("203.0.113.1")]
    [InlineData("2001:db8::1")]
    [InlineData("::ffff:192.168.1.1")]
    public void Rss_network_gate_blocks_reserved_and_documentation_ranges(string address) =>
        Assert.False(PublicNetworkSocketsHttpHandler.IsPublic(IPAddress.Parse(address)));

    [Theory]
    [InlineData("User-agent: *\nDisallow: /private/*\nAllow: /private/public$", "/private/a", false)]
    [InlineData("User-agent: *\nDisallow: /private/*\nAllow: /private/public$", "/private/public", true)]
    [InlineData("User-agent: *\nDisallow: /feed?draft=*", "/feed?draft=1", false)]
    public void Robots_evaluator_applies_wildcards_end_anchor_and_query(
        string robots,
        string pathAndQuery,
        bool expected) => Assert.Equal(
            expected,
            RobotsPolicyEvaluator.IsAllowed(robots, "FundingPlatform/1.0", pathAndQuery));

    [Fact]
    public async Task Governed_gate_uses_durable_authorization_and_lower_database_cap()
    {
        var clock = new FixedTimeProvider(Now);
        var authorizer = new RecordingAuthorizer(Now, maximumBytes: 4_096, policyVersion: 7);
        var gate = new GovernedAcquisitionRequestGate(clock);

        using var permit = await gate.AuthorizeAsync(
            authorizer,
            new GovernedAcquisitionContext(9, 600, 8_192, 90, 7, new byte[32]),
            new Uri("https://official.example.org/feed.xml"),
            TimeSpan.Zero,
            CancellationToken.None);

        Assert.Equal(4_096, permit.MaximumResponseBytes);
        Assert.Equal(100, authorizer.MinimumIntervalMilliseconds);
        Assert.Equal("official.example.org", authorizer.Destination!.Host);
    }

    [Fact]
    public async Task Governed_gate_fails_closed_when_policy_changes_after_claim()
    {
        var gate = new GovernedAcquisitionRequestGate(new FixedTimeProvider(Now));
        var authorizer = new RecordingAuthorizer(Now, 4_096, policyVersion: 8);

        await Assert.ThrowsAsync<FundingSourceImportException>(() => gate.AuthorizeAsync(
            authorizer,
            new GovernedAcquisitionContext(9, 60, 8_192, 90, 7, new byte[32]),
            new Uri("https://official.example.org/feed.xml"),
            TimeSpan.Zero,
            CancellationToken.None));
    }

    [Fact]
    public async Task Governed_gate_fails_closed_when_authorizer_returns_another_fingerprint()
    {
        var gate = new GovernedAcquisitionRequestGate(new FixedTimeProvider(Now));
        var authorizer = new RecordingAuthorizer(
            Now, 4_096, policyVersion: 7, corruptFingerprint: true);

        await Assert.ThrowsAsync<FundingSourceImportException>(() => gate.AuthorizeAsync(
            authorizer,
            new GovernedAcquisitionContext(9, 60, 8_192, 90, 7, new byte[32]),
            new Uri("https://official.example.org/feed.xml"),
            TimeSpan.Zero,
            CancellationToken.None));
    }

    [Fact]
    public async Task Governed_gate_reserves_globally_only_after_entering_local_gate()
    {
        var clock = new FixedTimeProvider(Now);
        var authorizer = new RecordingAuthorizer(Now, 4_096, policyVersion: 7);
        var gate = new GovernedAcquisitionRequestGate(clock);
        var context = new GovernedAcquisitionContext(9, 600, 8_192, 90, 7, new byte[32]);
        var destination = new Uri("https://official.example.org/feed.xml");

        using var first = await gate.AuthorizeAsync(
            authorizer, context, destination, TimeSpan.Zero, CancellationToken.None);
        var secondTask = gate.AuthorizeAsync(
            authorizer, context, destination, TimeSpan.Zero, CancellationToken.None);

        await Task.Delay(50);
        Assert.Equal(1, authorizer.CallCount);
        Assert.False(secondTask.IsCompleted);

        first.Dispose();
        using var second = await secondTask.WaitAsync(TimeSpan.FromSeconds(2));
        Assert.Equal(2, authorizer.CallCount);
    }

    [Fact]
    public async Task Event_grid_metadata_failure_is_retryable_not_invalid_authentication()
    {
        var validator = new EntraEventGridBearerTokenValidator(
            Options.Create(DefenderOptions()),
            new FakeMetadata(new HttpRequestException("metadata unavailable")),
            new JsonWebTokenHandler());

        var result = await validator.ValidateAsync(
            "Bearer " + new string('a', 120), CancellationToken.None);

        Assert.Equal(EventGridTokenValidationOutcome.Unavailable, result.Outcome);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Event_grid_accepts_exact_tenant_v1_and_v2_issuers(bool versionTwo)
    {
        using var rsa = RSA.Create(2_048);
        var key = new RsaSecurityKey(rsa) { KeyId = "phase7b-test-key" };
        var configuration = new OpenIdConnectConfiguration();
        configuration.SigningKeys.Add(key);
        var options = DefenderOptions();
        var issuer = versionTwo
            ? $"https://login.microsoftonline.com/{options.TenantId}/v2.0"
            : $"https://sts.windows.net/{options.TenantId}/";
        var token = new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
        {
            Issuer = issuer,
            Audience = options.Audience,
            Subject = new ClaimsIdentity(
            [
                new Claim("tid", options.TenantId),
                new Claim(versionTwo ? "azp" : "appid", options.AllowedCallerApplicationId),
                new Claim("oid", options.AllowedCallerObjectId)
            ]),
            NotBefore = Now.AddMinutes(-1).UtcDateTime,
            Expires = Now.AddMinutes(5).UtcDateTime,
            SigningCredentials = new SigningCredentials(key, SecurityAlgorithms.RsaSha256)
        });
        var validator = new EntraEventGridBearerTokenValidator(
            Options.Create(options), new FakeMetadata(configuration), new JsonWebTokenHandler());

        var result = await validator.ValidateAsync($"Bearer {token}", CancellationToken.None);

        Assert.Equal(EventGridTokenValidationOutcome.Valid, result.Outcome);
        Assert.NotNull(result.Caller);
    }

    [Theory]
    [InlineData("tenant")]
    [InlineData("audience")]
    [InlineData("principal")]
    [InlineData("application")]
    public async Task Event_grid_rejects_tokens_outside_the_exact_trust_boundary(string mismatch)
    {
        using var rsa = RSA.Create(2_048);
        var key = new RsaSecurityKey(rsa) { KeyId = "phase7b-invalid-key" };
        var configuration = new OpenIdConnectConfiguration();
        configuration.SigningKeys.Add(key);
        var options = DefenderOptions();
        var tenant = mismatch == "tenant"
            ? "99999999-9999-9999-9999-999999999999"
            : options.TenantId;
        var audience = mismatch == "audience"
            ? "api://99999999-9999-9999-9999-999999999999"
            : options.Audience;
        var principal = mismatch == "principal"
            ? "99999999-9999-9999-9999-999999999999"
            : options.AllowedCallerObjectId;
        var application = mismatch == "application"
            ? "99999999-9999-9999-9999-999999999999"
            : options.AllowedCallerApplicationId;
        var token = new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
        {
            Issuer = $"https://login.microsoftonline.com/{tenant}/v2.0",
            Audience = audience,
            Subject = new ClaimsIdentity(
            [
                new Claim("tid", tenant),
                new Claim("azp", application),
                new Claim("oid", principal)
            ]),
            NotBefore = Now.AddMinutes(-1).UtcDateTime,
            Expires = Now.AddMinutes(5).UtcDateTime,
            SigningCredentials = new SigningCredentials(key, SecurityAlgorithms.RsaSha256)
        });
        var validator = new EntraEventGridBearerTokenValidator(
            Options.Create(options), new FakeMetadata(configuration), new JsonWebTokenHandler());

        var result = await validator.ValidateAsync($"Bearer {token}", CancellationToken.None);

        Assert.Equal(EventGridTokenValidationOutcome.Invalid, result.Outcome);
        Assert.Null(result.Caller);
    }

    [Fact]
    public void Defender_config_binds_event_storage_to_the_blob_account()
    {
        var options = DefenderOptions();
        Assert.True(DefenderEventGridOptions.IsValid(
            options, "Production", "https://fpongdev1234.blob.core.windows.net"));
        Assert.False(DefenderEventGridOptions.IsValid(
            options, "Production", "https://different.blob.core.windows.net"));
    }

    [Fact]
    public async Task Retention_service_uses_bounded_batch_and_utc_clock()
    {
        var repository = new RecordingRetentionRepository();
        var service = new ContentRetentionService(repository, new FixedTimeProvider(Now));

        await service.EnforceAsync(100, CancellationToken.None);

        Assert.Equal(100, repository.BatchSize);
        Assert.Equal(Now, repository.NowUtc);
        await Assert.ThrowsAsync<ArgumentOutOfRangeException>(() =>
            service.EnforceAsync(501, CancellationToken.None));
    }

    private static DefenderEventGridOptions DefenderOptions() => new()
    {
        Enabled = true,
        TenantId = "11111111-1111-1111-1111-111111111111",
        Audience = "api://22222222-2222-2222-2222-222222222222",
        AllowedCallerApplicationId = "33333333-3333-3333-3333-333333333333",
        AllowedCallerObjectId = "44444444-4444-4444-4444-444444444444",
        ExpectedTopicResourceId = "/subscriptions/55555555-5555-5555-5555-555555555555/resourceGroups/rg/providers/Microsoft.EventGrid/systemtopics/defender",
        ExpectedSubscriptionName = "defender-malware-results",
        StorageAccountResourceId = "/subscriptions/55555555-5555-5555-5555-555555555555/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/fpongdev1234",
        PendingScanTimeoutMinutes = 240,
        WatchdogBatchSize = 25
    };

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private sealed class RecordingAuthorizer(
        DateTimeOffset reservedAt,
        int maximumBytes,
        int policyVersion,
        bool corruptFingerprint = false) : IFundingSourceAcquisitionAuthorizer
    {
        public Uri? Destination { get; private set; }
        public int MinimumIntervalMilliseconds { get; private set; }
        public int CallCount { get; private set; }

        public Task<FundingSourceAcquisitionAuthorization> AuthorizeAsync(
            int fundingSourceId,
            Uri exactDestination,
            byte[] canonicalDestinationHash,
            byte[] acquisitionPolicyFingerprint,
            int minimumIntervalMilliseconds,
            DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
        {
            CallCount++;
            Destination = exactDestination;
            MinimumIntervalMilliseconds = minimumIntervalMilliseconds;
            return Task.FromResult(new FundingSourceAcquisitionAuthorization(
                true, "reserved", reservedAt, reservedAt.AddMilliseconds(minimumIntervalMilliseconds),
                0, 600, maximumBytes, 30, policyVersion,
                corruptFingerprint ? Enumerable.Repeat((byte)1, 32).ToArray()
                                   : acquisitionPolicyFingerprint));
        }
    }

    private sealed class FakeMetadata : IConfigurationManager<OpenIdConnectConfiguration>
    {
        private readonly OpenIdConnectConfiguration? configuration;
        private readonly Exception? exception;

        public FakeMetadata(OpenIdConnectConfiguration configuration) =>
            this.configuration = configuration;

        public FakeMetadata(Exception exception) => this.exception = exception;

        public Task<OpenIdConnectConfiguration> GetConfigurationAsync(
            CancellationToken cancel)
        {
            if (exception is not null)
                return Task.FromException<OpenIdConnectConfiguration>(exception);
            return Task.FromResult(configuration!);
        }

        public void RequestRefresh()
        {
        }
    }

    private sealed class RecordingRetentionRepository : IContentRetentionRepository
    {
        public int BatchSize { get; private set; }
        public DateTimeOffset NowUtc { get; private set; }

        public Task<ContentRetentionEnforcementResult> EnforceAsync(
            int batchSize,
            DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
        {
            BatchSize = batchSize;
            NowUtc = nowUtc;
            return Task.FromResult(new ContentRetentionEnforcementResult(0, 0, 0, 0, 0));
        }
    }
}
