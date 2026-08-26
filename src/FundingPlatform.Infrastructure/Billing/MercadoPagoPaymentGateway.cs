using System.Globalization;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using FundingPlatform.Application.Billing;
using FundingPlatform.Core.Billing;
using FundingPlatform.Infrastructure.Configuration;

namespace FundingPlatform.Infrastructure.Billing;

public sealed class MercadoPagoPaymentGateway(
    HttpClient client,
    BillingOptions options) : IPaymentGateway
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    public string ProviderCode => "mercado-pago-sandbox";

    public async Task<PaymentCheckoutResult> CreateOrRecoverCheckoutAsync(
        PaymentCheckoutRequest request, CancellationToken cancellationToken)
    {
        var recovered = await FindSubscriptionDocumentAsync(request.ExternalReference,
            cancellationToken);
        if (recovered.HasValue) return Checkout(recovered.Value);
        using var message = new HttpRequestMessage(HttpMethod.Post, "/preapproval");
        Authorize(message);
        message.Headers.TryAddWithoutValidation("X-Idempotency-Key",
            request.CheckoutPublicId.ToString("D"));
        message.Content = JsonContent.Create(new
        {
            reason = request.PlanName,
            external_reference = request.ExternalReference.ToString("D"),
            payer_email = request.PayerEmail,
            back_url = request.ReturnUri.AbsoluteUri,
            notification_url = request.NotificationUri.AbsoluteUri,
            status = "pending",
            auto_recurring = new
            {
                frequency = request.Interval == BillingInterval.Monthly ? 1 : 12,
                frequency_type = "months",
                transaction_amount = request.Amount,
                currency_id = request.Currency
            }
        }, options: JsonOptions);
        using var response = await SendAsync(message, cancellationToken);
        return Checkout(await ReadAsync(response, cancellationToken));
    }

    public async Task<PaymentProviderSubscriptionSnapshot?> GetSubscriptionAsync(
        string providerSubscriptionId, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get,
            $"/preapproval/{Uri.EscapeDataString(providerSubscriptionId)}");
        Authorize(request);
        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);
        if (response.StatusCode == System.Net.HttpStatusCode.NotFound) return null;
        EnsureSuccess(response);
        return Snapshot(await ReadAsync(response, cancellationToken));
    }

    public async Task<PaymentProviderSubscriptionSnapshot?> FindSubscriptionAsync(
        Guid externalReference, CancellationToken cancellationToken)
    {
        var document = await FindSubscriptionDocumentAsync(externalReference, cancellationToken);
        return document.HasValue ? Snapshot(document.Value) : null;
    }

    public async Task<PaymentProviderSubscriptionSnapshot?> GetWebhookSnapshotAsync(
        string eventType, string providerResourceId, CancellationToken cancellationToken)
    {
        if (eventType == "subscription_preapproval")
            return await GetSubscriptionAsync(providerResourceId, cancellationToken);
        JsonElement? invoice = eventType == "subscription_authorized_payment"
            ? await GetDocumentAsync($"/authorized_payments/{Uri.EscapeDataString(providerResourceId)}",
                cancellationToken)
            : eventType == "payment"
                ? await FindInvoiceByPaymentAsync(providerResourceId, cancellationToken)
                : null;
        if (!invoice.HasValue) return null;
        var preapprovalId = RequiredString(invoice.Value, "preapproval_id", 200);
        var subscription = await GetSubscriptionAsync(preapprovalId, cancellationToken);
        if (subscription is null) return null;
        var payment = invoice.Value.TryGetProperty("payment", out var paymentValue) &&
            paymentValue.ValueKind == JsonValueKind.Object ? paymentValue : default;
        var amountText = OptionalString(invoice.Value, "transaction_amount", 50);
        var amount = decimal.TryParse(amountText, NumberStyles.Number,
            CultureInfo.InvariantCulture, out var parsedAmount) ? parsedAmount : (decimal?)null;
        return subscription with
        {
            ProviderPaymentId = payment.ValueKind == JsonValueKind.Object
                ? OptionalString(payment, "id", 200) : null,
            ProviderInvoiceId = OptionalString(invoice.Value, "id", 200),
            PaymentStatusCode = payment.ValueKind == JsonValueKind.Object
                ? OptionalString(payment, "status", 50) : OptionalString(invoice.Value, "status", 50),
            PaymentAmount = amount,
            PaymentCurrency = OptionalString(invoice.Value, "currency_id", 3),
            PaidAtUtc = Date(invoice.Value, "debit_date"),
            FailureCode = payment.ValueKind == JsonValueKind.Object
                ? OptionalString(payment, "status_detail", 100) : null,
            ProviderUpdatedAtUtc = Date(invoice.Value, "last_modified") ??
                subscription.ProviderUpdatedAtUtc
        };
    }

    public Task<PaymentProviderSubscriptionSnapshot> CancelAsync(
        string providerSubscriptionId, CancellationToken cancellationToken) =>
        ChangeStatusAsync(providerSubscriptionId, "cancelled", cancellationToken);

    public Task<PaymentProviderSubscriptionSnapshot> ResumeAsync(
        string providerSubscriptionId, CancellationToken cancellationToken) =>
        ChangeStatusAsync(providerSubscriptionId, "authorized", cancellationToken);

    private async Task<PaymentProviderSubscriptionSnapshot> ChangeStatusAsync(string id,
        string status, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Put,
            $"/preapproval/{Uri.EscapeDataString(id)}");
        Authorize(request);
        request.Headers.TryAddWithoutValidation("X-Idempotency-Key", Guid.NewGuid().ToString("D"));
        request.Content = JsonContent.Create(new { status }, options: JsonOptions);
        using var response = await SendAsync(request, cancellationToken);
        return Snapshot(await ReadAsync(response, cancellationToken));
    }

    private async Task<JsonElement?> FindSubscriptionDocumentAsync(Guid externalReference,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get,
            $"/preapproval/search?external_reference={externalReference:D}&limit=2&offset=0");
        Authorize(request);
        using var response = await SendAsync(request, cancellationToken);
        var root = await ReadAsync(response, cancellationToken);
        if (!root.TryGetProperty("results", out var results) || results.ValueKind != JsonValueKind.Array)
            throw new PaymentGatewayException("invalid-search-response");
        JsonElement? found = null;
        foreach (var item in results.EnumerateArray())
        {
            if (!item.TryGetProperty("external_reference", out var reference) ||
                reference.GetString() != externalReference.ToString("D")) continue;
            if (found.HasValue) throw new PaymentGatewayException("ambiguous-external-reference");
            found = item.Clone();
        }
        return found;
    }

    private async Task<JsonElement?> FindInvoiceByPaymentAsync(string paymentId,
        CancellationToken cancellationToken)
    {
        var root = await GetDocumentAsync(
            $"/authorized_payments/search?payment_id={Uri.EscapeDataString(paymentId)}&limit=2&offset=0",
            cancellationToken);
        if (!root.HasValue || !root.Value.TryGetProperty("results", out var results) ||
            results.ValueKind != JsonValueKind.Array) return null;
        JsonElement? found = null;
        foreach (var item in results.EnumerateArray())
        {
            if (!item.TryGetProperty("payment", out var payment) ||
                OptionalString(payment, "id", 200) != paymentId) continue;
            if (found.HasValue) throw new PaymentGatewayException("ambiguous-payment-invoice");
            found = item.Clone();
        }
        return found;
    }

    private async Task<JsonElement?> GetDocumentAsync(string path,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, path);
        Authorize(request);
        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);
        if (response.StatusCode == System.Net.HttpStatusCode.NotFound) return null;
        EnsureSuccess(response);
        return await ReadAsync(response, cancellationToken);
    }

    private static PaymentCheckoutResult Checkout(JsonElement root)
    {
        var id = RequiredString(root, "id", 200);
        var uriText = RequiredString(root, "init_point", 2048);
        if (!Uri.TryCreate(uriText, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps ||
            !uri.Host.EndsWith("mercadopago.cl", StringComparison.OrdinalIgnoreCase) &&
            !uri.Host.EndsWith("mercadopago.com", StringComparison.OrdinalIgnoreCase))
            throw new PaymentGatewayException("invalid-checkout-uri");
        return new PaymentCheckoutResult(id, uri, UpdatedAt(root));
    }

    private static PaymentProviderSubscriptionSnapshot Snapshot(JsonElement root) => new(
        RequiredString(root, "id", 200),
        OptionalString(root, "payer_id", 200),
        RequiredString(root, "status", 50),
        Date(root, "date_created"),
        Date(root, "next_payment_date"),
        string.Equals(OptionalString(root, "status", 50), "cancelled", StringComparison.Ordinal),
        UpdatedAt(root),
        LiveMode: root.TryGetProperty("live_mode", out var live) && live.ValueKind == JsonValueKind.True);

    private async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        try
        {
            var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead,
                cancellationToken);
            EnsureSuccess(response);
            return response;
        }
        catch (PaymentGatewayException) { throw; }
        catch (Exception exception) when (exception is HttpRequestException or TaskCanceledException)
        {
            throw new PaymentGatewayException("provider-unavailable", exception);
        }
    }

    private static void EnsureSuccess(HttpResponseMessage response)
    {
        if (!response.IsSuccessStatusCode)
            throw new PaymentGatewayException($"provider-http-{(int)response.StatusCode}");
    }

    private static async Task<JsonElement> ReadAsync(HttpResponseMessage response,
        CancellationToken cancellationToken)
    {
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        try
        {
            using var document = await JsonDocument.ParseAsync(stream,
                new JsonDocumentOptions { MaxDepth = 32 }, cancellationToken);
            return document.RootElement.Clone();
        }
        catch (JsonException exception)
        {
            throw new PaymentGatewayException("invalid-provider-json", exception);
        }
    }

    private void Authorize(HttpRequestMessage request)
    {
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", options.AccessToken);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
    }

    private static string RequiredString(JsonElement root, string name, int maximum)
    {
        var value = OptionalString(root, name, maximum);
        return string.IsNullOrWhiteSpace(value)
            ? throw new PaymentGatewayException("invalid-provider-contract") : value;
    }

    private static string? OptionalString(JsonElement root, string name, int maximum)
    {
        if (!root.TryGetProperty(name, out var property) || property.ValueKind == JsonValueKind.Null)
            return null;
        var value = property.ValueKind == JsonValueKind.String ? property.GetString() : property.ToString();
        return string.IsNullOrWhiteSpace(value) || value.Length > maximum ? null : value;
    }

    private static DateTimeOffset UpdatedAt(JsonElement root) =>
        Date(root, "date_last_modified") ?? Date(root, "last_modified") ?? DateTimeOffset.UtcNow;

    private static DateTimeOffset? Date(JsonElement root, string name) =>
        root.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.String &&
        DateTimeOffset.TryParse(property.GetString(), CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal, out var result) ? result.ToUniversalTime() : null;
}

public sealed class DevelopmentPaymentGateway(TimeProvider timeProvider) : IPaymentGateway
{
    public string ProviderCode => "development-sandbox";
    public Task<PaymentCheckoutResult> CreateOrRecoverCheckoutAsync(PaymentCheckoutRequest request,
        CancellationToken cancellationToken) => Task.FromResult(new PaymentCheckoutResult(
            $"dev-{request.ExternalReference:N}",
            new Uri($"https://sandbox.example.invalid/checkout/{request.ExternalReference:D}"),
            timeProvider.GetUtcNow()));
    public Task<PaymentProviderSubscriptionSnapshot?> GetSubscriptionAsync(string id,
        CancellationToken cancellationToken) => Task.FromResult<PaymentProviderSubscriptionSnapshot?>(
            Snapshot(id));
    public Task<PaymentProviderSubscriptionSnapshot?> FindSubscriptionAsync(Guid reference,
        CancellationToken cancellationToken) => Task.FromResult<PaymentProviderSubscriptionSnapshot?>(
            Snapshot($"dev-{reference:N}"));
    public Task<PaymentProviderSubscriptionSnapshot?> GetWebhookSnapshotAsync(string eventType,
        string providerResourceId, CancellationToken cancellationToken) =>
        Task.FromResult<PaymentProviderSubscriptionSnapshot?>(Snapshot(providerResourceId));
    public Task<PaymentProviderSubscriptionSnapshot> CancelAsync(string id,
        CancellationToken cancellationToken) => Task.FromResult(Snapshot(id) with
        { StatusCode = "cancelled", CancelAtPeriodEnd = true });
    public Task<PaymentProviderSubscriptionSnapshot> ResumeAsync(string id,
        CancellationToken cancellationToken) => Task.FromResult(Snapshot(id));
    private PaymentProviderSubscriptionSnapshot Snapshot(string id) => new(id, "dev-customer",
        "authorized", timeProvider.GetUtcNow().AddDays(-1), timeProvider.GetUtcNow().AddMonths(1),
        false, timeProvider.GetUtcNow());
}
