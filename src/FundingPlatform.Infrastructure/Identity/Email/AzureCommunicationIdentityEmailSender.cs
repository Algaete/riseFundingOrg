using System.Net;
using Azure;
using Azure.Communication.Email;
using FundingPlatform.Application.Authentication;
using FundingPlatform.Infrastructure.Identity.Configuration;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Infrastructure.Identity.Email;

public sealed class AzureCommunicationIdentityEmailSender : IIdentityEmailSender
{
    private readonly EmailClient _emailClient;
    private readonly EmailOptions _options;

    public AzureCommunicationIdentityEmailSender(
        EmailClient emailClient,
        IOptions<EmailOptions> options)
    {
        _emailClient = emailClient;
        _options = options.Value;
    }

    public Task SendVerificationAsync(
        string email,
        string displayName,
        string rawToken,
        CancellationToken cancellationToken)
    {
        var actionUrl = BuildActionUrl("verify-email", rawToken);
        return SendAsync(
            email,
            "Confirma tu cuenta de FundingPlatform",
            $"Hola {displayName}, confirma tu cuenta visitando: {actionUrl}",
            BuildHtml(
                displayName,
                "Confirma tu cuenta",
                "Confirma tu correo para comenzar a encontrar fondos compatibles con tu organización.",
                "Confirmar cuenta",
                actionUrl),
            cancellationToken);
    }

    public Task SendPasswordResetAsync(
        string email,
        string displayName,
        string rawToken,
        CancellationToken cancellationToken)
    {
        var actionUrl = BuildActionUrl("reset-password", rawToken);
        return SendAsync(
            email,
            "Restablece tu contraseña de FundingPlatform",
            $"Hola {displayName}, restablece tu contraseña visitando: {actionUrl}",
            BuildHtml(
                displayName,
                "Restablece tu contraseña",
                "Recibimos una solicitud para cambiar tu contraseña. Si no fuiste tú, ignora este mensaje.",
                "Crear nueva contraseña",
                actionUrl),
            cancellationToken);
    }

    private async Task SendAsync(
        string recipient,
        string subject,
        string plainText,
        string html,
        CancellationToken cancellationToken)
    {
        var content = new EmailContent(subject)
        {
            PlainText = plainText,
            Html = html
        };
        var message = new EmailMessage(_options.FromAddress, recipient, content);
        _ = await _emailClient.SendAsync(WaitUntil.Started, message, cancellationToken);
    }

    private string BuildActionUrl(string route, string rawToken)
    {
        var baseUrl = _options.FrontendBaseUrl.TrimEnd('/');
        return $"{baseUrl}/{route}?token={Uri.EscapeDataString(rawToken)}";
    }

    private static string BuildHtml(
        string displayName,
        string heading,
        string description,
        string actionLabel,
        string actionUrl)
    {
        var safeDisplayName = WebUtility.HtmlEncode(displayName);
        var safeHeading = WebUtility.HtmlEncode(heading);
        var safeDescription = WebUtility.HtmlEncode(description);
        var safeActionLabel = WebUtility.HtmlEncode(actionLabel);
        var safeActionUrl = WebUtility.HtmlEncode(actionUrl);

        return $$"""
            <!doctype html>
            <html lang="es">
              <body style="margin:0;background:#f5f7f6;font-family:Arial,sans-serif;color:#17352b">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                  <tr>
                    <td align="center" style="padding:32px 16px">
                      <table role="presentation" width="100%" style="max-width:560px;background:#ffffff;border-radius:16px;padding:32px">
                        <tr><td><strong style="font-size:18px">FundingPlatform</strong></td></tr>
                        <tr><td style="padding-top:28px"><h1 style="font-size:26px;margin:0">{{safeHeading}}</h1></td></tr>
                        <tr><td style="padding-top:16px">Hola {{safeDisplayName}},</td></tr>
                        <tr><td style="padding-top:12px;line-height:1.6">{{safeDescription}}</td></tr>
                        <tr>
                          <td style="padding-top:28px">
                            <a href="{{safeActionUrl}}" style="display:inline-block;background:#147d64;color:#fff;text-decoration:none;padding:13px 20px;border-radius:10px;font-weight:700">{{safeActionLabel}}</a>
                          </td>
                        </tr>
                        <tr><td style="padding-top:28px;font-size:12px;color:#60756d">Este enlace es personal, expira pronto y solo puede utilizarse una vez.</td></tr>
                      </table>
                    </td>
                  </tr>
                </table>
              </body>
            </html>
            """;
    }
}
