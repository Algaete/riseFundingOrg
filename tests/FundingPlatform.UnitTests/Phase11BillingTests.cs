using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Application.Billing;
using FundingPlatform.Infrastructure.Billing;
using FundingPlatform.Infrastructure.Configuration;
using FundingPlatform.Infrastructure.Persistence.Migrations;

namespace FundingPlatform.UnitTests;

public sealed class Phase11BillingTests
{
    [Fact]
    public void Webhook_signature_is_verified_and_live_events_are_rejected()
    {
        const string secret = "sandbox-secret-long-enough";
        const string requestId = "request-1";
        const string dataId = "456";
        var now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);
        var manifest = $"id:{dataId};request-id:{requestId};ts:{now.ToUnixTimeSeconds()};";
        var signature = $"ts={now.ToUnixTimeSeconds()},v1={Convert.ToHexString(HMACSHA256.HashData(Encoding.UTF8.GetBytes(secret), Encoding.UTF8.GetBytes(manifest))).ToLowerInvariant()}";
        var verifier = new MercadoPagoWebhookVerifier(new BillingOptions
        {
            Enabled = true, GatewayMode = "MercadoPagoSandbox", WebhookSecret = secret
        });
        var payload = Encoding.UTF8.GetBytes("{\"id\":\"event-123\",\"live_mode\":false,\"type\":\"subscription_preapproval\",\"action\":\"updated\",\"data\":{\"id\":\"456\"}}");

        var verified = verifier.Verify(signature, requestId, dataId, payload, now);
        Assert.Equal("event-123", verified.ProviderEventId);
        Assert.Equal(dataId, verified.ProviderResourceId);

        var live = Encoding.UTF8.GetBytes("{\"id\":\"event-124\",\"live_mode\":true,\"type\":\"subscription_preapproval\",\"data\":{\"id\":\"456\"}}");
        var exception = Assert.Throws<PaymentWebhookVerificationException>(() =>
            verifier.Verify(signature, requestId, dataId, live, now));
        Assert.Equal("live-or-mismatched-webhook", exception.Code);
    }

    [Fact]
    public void Migration_ships_paid_plans_disabled_and_never_persists_payment_secrets()
    {
        var migration = Read("database", "Migrations", "026_subscription_billing_sandbox.sql");
        Assert.Contains("IsPurchasable, SortOrder", migration, StringComparison.Ordinal);
        Assert.Contains("N'PROFESSIONAL'", migration, StringComparison.Ordinal);
        Assert.Contains("N'ORGANIZATION'", migration, StringComparison.Ordinal);
        Assert.Contains("ifn_OrganizationEntitlements", migration, StringComparison.Ordinal);
        Assert.Contains("PaymentWebhookEvents_ImmutableEnvelope", migration, StringComparison.Ordinal);
        Assert.DoesNotContain("CardNumber", migration, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("AccessToken NVARCHAR", migration, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("WebhookSecret NVARCHAR", migration, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("PayloadJson", migration, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Smoke_is_transactional_and_checks_free_replay_and_no_raw_payload()
    {
        var smoke = Read("database", "Tests", "026_subscription_billing_sandbox_smoke.sql");
        Assert.Contains("BEGIN TRY", smoke, StringComparison.Ordinal);
        Assert.Contains("ROLLBACK", smoke, StringComparison.Ordinal);
        Assert.Contains("Free fallback entitlement", smoke, StringComparison.Ordinal);
        Assert.Contains("Code=N'replayed'", smoke, StringComparison.Ordinal);
        Assert.Contains("PayloadJson", smoke, StringComparison.Ordinal);
    }

    private static string Read(params string[] parts)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        return File.ReadAllText(Path.Combine([root, .. parts]));
    }
}
