using FundingPlatform.Application.Billing;

namespace FundingPlatform.Infrastructure.Configuration;

public sealed class BillingOptions
{
    public const string SectionName = "Billing";
    public bool Enabled { get; set; }
    public bool SandboxOnly { get; set; } = true;
    public string GatewayMode { get; set; } = "Disabled";
    public string ApiBaseUri { get; set; } = "https://api.mercadopago.com";
    public string AccessToken { get; set; } = string.Empty;
    public string WebhookSecret { get; set; } = string.Empty;
    public string FrontendBaseUrl { get; set; } = "http://localhost:5173";
    public string WebhookUrl { get; set; } = "http://localhost:5070/api/v1/webhooks/payments/mercado-pago";
    public int CheckoutExpiryMinutes { get; set; } = 30;
    public int WebhookToleranceSeconds { get; set; } = 300;
    public int MaximumWebhookBytes { get; set; } = 65_536;
    public int TimeoutSeconds { get; set; } = 20;
    public int WebhookBatchSize { get; set; } = 10;
    public int WebhookLeaseSeconds { get; set; } = 120;
    public int ReconciliationBatchSize { get; set; } = 25;

    public static bool IsValid(BillingOptions options, string environmentName)
    {
        if (!options.SandboxOnly || options.CheckoutExpiryMinutes is < 5 or > 60 ||
            options.WebhookToleranceSeconds is < 60 or > 900 ||
            options.MaximumWebhookBytes is < 1024 or > 262_144 ||
            options.TimeoutSeconds is < 5 or > 60 ||
            options.WebhookBatchSize is < 1 or > 25 ||
            options.WebhookLeaseSeconds is < 30 or > 300 ||
            options.ReconciliationBatchSize is < 1 or > 50 ||
            !Uri.TryCreate(options.ApiBaseUri, UriKind.Absolute, out var api) ||
            api != new Uri("https://api.mercadopago.com") ||
            !SafeUri(options.FrontendBaseUrl) || !SafeUri(options.WebhookUrl))
            return false;
        if (!options.Enabled) return options.GatewayMode is "Disabled" or "DevelopmentFake" or "MercadoPagoSandbox";
        if (options.GatewayMode == "DevelopmentFake")
            return environmentName is "Development" or "Testing";
        return options.GatewayMode == "MercadoPagoSandbox" &&
               options.AccessToken.Length is >= 20 and <= 512 &&
               options.WebhookSecret.Length is >= 16 and <= 512;
    }

    public BillingPolicy ToPolicy() => new(Enabled, SandboxOnly, CheckoutExpiryMinutes,
        new Uri(FrontendBaseUrl), new Uri(WebhookUrl));

    private static bool SafeUri(string value) =>
        Uri.TryCreate(value, UriKind.Absolute, out var uri) &&
        (uri.Scheme == Uri.UriSchemeHttps || (uri.Scheme == Uri.UriSchemeHttp && uri.IsLoopback));
}
