using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FundingPlatform.Application.Billing;
using FundingPlatform.Infrastructure.Configuration;

namespace FundingPlatform.Infrastructure.Billing;

public sealed class MercadoPagoWebhookVerifier(BillingOptions options) : IPaymentWebhookVerifier
{
    public VerifiedPaymentWebhook Verify(string signature, string requestId, string dataId,
        ReadOnlySpan<byte> payload, DateTimeOffset nowUtc)
    {
        if (!options.Enabled || string.IsNullOrWhiteSpace(options.WebhookSecret) ||
            payload.Length is 0 || payload.Length > options.MaximumWebhookBytes ||
            !SafeToken(requestId, 200) || !SafeToken(dataId, 200))
            throw new PaymentWebhookVerificationException("invalid-webhook-envelope");
        var values = ParseSignature(signature);
        if (!values.TryGetValue("ts", out var timestampText) ||
            !values.TryGetValue("v1", out var expectedHex) || expectedHex.Length != 64 ||
            !long.TryParse(timestampText, NumberStyles.None, CultureInfo.InvariantCulture,
                out var rawTimestamp))
            throw new PaymentWebhookVerificationException("invalid-webhook-signature");
        var seconds = rawTimestamp > 10_000_000_000 ? rawTimestamp / 1000 : rawTimestamp;
        DateTimeOffset signedAt;
        try { signedAt = DateTimeOffset.FromUnixTimeSeconds(seconds); }
        catch (ArgumentOutOfRangeException) { throw new PaymentWebhookVerificationException("invalid-webhook-timestamp"); }
        if (Math.Abs((nowUtc - signedAt).TotalSeconds) > options.WebhookToleranceSeconds)
            throw new PaymentWebhookVerificationException("stale-webhook");
        var canonicalId = dataId.All(char.IsLetterOrDigit) ? dataId.ToLowerInvariant() : dataId;
        var manifest = $"id:{canonicalId};request-id:{requestId};ts:{timestampText};";
        var actual = HMACSHA256.HashData(Encoding.UTF8.GetBytes(options.WebhookSecret),
            Encoding.UTF8.GetBytes(manifest));
        byte[] expected;
        try { expected = Convert.FromHexString(expectedHex); }
        catch (FormatException) { throw new PaymentWebhookVerificationException("invalid-webhook-signature"); }
        if (expected.Length != 32 || !CryptographicOperations.FixedTimeEquals(actual, expected))
            throw new PaymentWebhookVerificationException("invalid-webhook-signature");

        try
        {
            using var document = JsonDocument.Parse(payload.ToArray(),
                new JsonDocumentOptions { MaxDepth = 16 });
            var root = document.RootElement;
            var bodyDataId = root.GetProperty("data").GetProperty("id").ToString();
            var liveMode = root.TryGetProperty("live_mode", out var live) && live.GetBoolean();
            if (!string.Equals(bodyDataId, dataId, StringComparison.Ordinal) || liveMode)
                throw new PaymentWebhookVerificationException("live-or-mismatched-webhook");
            var type = Required(root, "type", 100);
            if (type is not ("payment" or "subscription_authorized_payment" or
                "subscription_preapproval"))
                throw new PaymentWebhookVerificationException("unsupported-webhook-type");
            var action = Optional(root, "action", 100);
            var eventId = Required(root, "id", 200);
            var occurred = DateTimeOffset.TryParse(Optional(root, "date_created", 100),
                CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var parsed)
                ? parsed.ToUniversalTime() : (DateTimeOffset?)null;
            return new VerifiedPaymentWebhook(eventId, requestId, type, type,
                dataId, action, occurred, SHA256.HashData(payload), false);
        }
        catch (PaymentWebhookVerificationException) { throw; }
        catch (Exception exception) when (exception is JsonException or InvalidOperationException or KeyNotFoundException)
        {
            throw new PaymentWebhookVerificationException("invalid-webhook-payload");
        }
    }

    private static Dictionary<string, string> ParseSignature(string value)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var part in (value ?? string.Empty).Split(',', StringSplitOptions.RemoveEmptyEntries))
        {
            var separator = part.IndexOf('=');
            if (separator <= 0 || separator == part.Length - 1) continue;
            result.TryAdd(part[..separator].Trim(), part[(separator + 1)..].Trim());
        }
        return result;
    }
    private static bool SafeToken(string value, int maximum) => !string.IsNullOrWhiteSpace(value) &&
        value.Length <= maximum && value.All(character => character is >= '!' and <= '~');
    private static string Required(JsonElement root, string name, int maximum) =>
        Optional(root, name, maximum) ?? throw new PaymentWebhookVerificationException("invalid-webhook-payload");
    private static string? Optional(JsonElement root, string name, int maximum)
    {
        if (!root.TryGetProperty(name, out var property) || property.ValueKind == JsonValueKind.Null)
            return null;
        var value = property.GetString();
        return string.IsNullOrWhiteSpace(value) || value.Length > maximum ? null : value;
    }
}
