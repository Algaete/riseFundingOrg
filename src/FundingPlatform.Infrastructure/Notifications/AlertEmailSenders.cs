using System.Net;
using Azure;
using Azure.Communication.Email;
using FundingPlatform.Application.Alerts;
using FundingPlatform.Core.Alerts;
using FundingPlatform.Infrastructure.Identity.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Infrastructure.Notifications;

public sealed class AzureCommunicationAlertEmailSender(
    EmailClient client,
    IOptions<EmailOptions> options) : IAlertEmailSender
{
    private readonly EmailOptions _options = options.Value;

    public async Task<AlertEmailDeliveryResult> SendAsync(
        AlertEmailMessage message, CancellationToken cancellationToken)
    {
        var actionBase = _options.FrontendBaseUrl.TrimEnd('/');
        var unsubscribeUrl = $"{actionBase}/alerts/unsubscribe#token=" +
            Uri.EscapeDataString(message.UnsubscribeToken);
        var fundingUrl = $"{actionBase}/opportunities";
        var subject = $"Nuevos fondos en {SafeSubject(message.SavedSearchName)}";
        var content = new EmailContent(subject)
        {
            PlainText = BuildPlainText(message, fundingUrl, unsubscribeUrl),
            Html = BuildHtml(message, fundingUrl, unsubscribeUrl)
        };
        try
        {
            var operation = await client.SendAsync(
                WaitUntil.Started,
                new EmailMessage(_options.FromAddress, message.RecipientEmail, content),
                cancellationToken);
            if (string.IsNullOrWhiteSpace(operation.Id) || operation.Id.Length > 200)
                throw new AlertEmailDeliveryException("provider-id-invalid", true);
            return new AlertEmailDeliveryResult(operation.Id);
        }
        catch (AlertEmailDeliveryException) { throw; }
        catch (RequestFailedException exception)
        {
            var unknown = exception.Status is 0 or 408 || exception.Status >= 500;
            throw new AlertEmailDeliveryException(
                unknown ? "provider-response-uncertain" : "provider-rejected",
                unknown,
                exception);
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            throw new AlertEmailDeliveryException("provider-timeout", true, exception);
        }
        catch (HttpRequestException exception)
        {
            throw new AlertEmailDeliveryException("provider-network-uncertain", true, exception);
        }
    }

    private static string BuildPlainText(
        AlertEmailMessage message, string fundingUrl, string unsubscribeUrl)
    {
        var lines = new List<string>
        {
            $"Hola {message.RecipientDisplayName},",
            $"Encontramos {message.Items.Count} fondos nuevos para tu búsqueda {message.SavedSearchName}."
        };
        lines.AddRange(message.Items.Select(item =>
            $"- {item.Title} — {item.SponsorName}"));
        lines.Add($"Revisar fondos: {fundingUrl}");
        lines.Add($"Desactivar esta alerta: {unsubscribeUrl}");
        return string.Join(Environment.NewLine, lines);
    }

    private static string BuildHtml(
        AlertEmailMessage message, string fundingUrl, string unsubscribeUrl)
    {
        var items = string.Concat(message.Items.Select(item =>
            $"<li style=\"margin:0 0 12px\"><strong>{WebUtility.HtmlEncode(item.Title)}</strong>" +
            $"<br><span>{WebUtility.HtmlEncode(item.SponsorName)}</span></li>"));
        return $$"""
            <!doctype html>
            <html lang="es"><body style="font-family:Arial,sans-serif;color:#17352b">
              <main style="max-width:620px;margin:auto;padding:28px">
                <h1 style="font-size:24px">Nuevos fondos para tu organización</h1>
                <p>Hola {{WebUtility.HtmlEncode(message.RecipientDisplayName)}}, encontramos
                {{message.Items.Count}} novedades para
                <strong>{{WebUtility.HtmlEncode(message.SavedSearchName)}}</strong>.</p>
                <ul>{{items}}</ul>
                <p><a href="{{WebUtility.HtmlEncode(fundingUrl)}}">Revisar oportunidades</a></p>
                <p style="font-size:12px;color:#60756d"><a href="{{WebUtility.HtmlEncode(unsubscribeUrl)}}">Desactivar esta alerta</a></p>
              </main>
            </body></html>
            """;
    }

    private static string SafeSubject(string value)
    {
        var sanitized = new string(value.Where(character => !char.IsControl(character)).ToArray());
        return sanitized.Length <= 100 ? sanitized : sanitized[..100];
    }
}

public sealed class DevelopmentAlertEmailSender(
    ILogger<DevelopmentAlertEmailSender> logger) : IAlertEmailSender
{
    public Task<AlertEmailDeliveryResult> SendAsync(
        AlertEmailMessage message, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        logger.LogInformation(
            "Development alert email accepted. Notification={NotificationId} Items={ItemCount}",
            message.NotificationLogPublicId,
            message.Items.Count);
        return Task.FromResult(new AlertEmailDeliveryResult(
            $"development-{message.NotificationLogPublicId:N}"));
    }
}
