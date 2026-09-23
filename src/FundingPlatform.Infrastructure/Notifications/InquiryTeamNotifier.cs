using Azure;
using Azure.Communication.Email;
using FundingPlatform.Application.Engagement;
using FundingPlatform.Core.Engagement;
using FundingPlatform.Infrastructure.Identity.Configuration;
using Microsoft.Extensions.Options;
using System.Net.Mail;

namespace FundingPlatform.Infrastructure.Notifications;

public sealed class InquiryNotificationOptions
{
    public bool Enabled { get; init; }
    public string TeamEmail { get; init; } = "";
}
public sealed class DisabledInquiryTeamNotifier : IInquiryTeamNotifier
{
    public bool Configured => false;
    public Task SendAsync(Inquiry inquiry, CancellationToken token) => throw new InquiryNotificationException();
}
public sealed class AzureInquiryTeamNotifier(EmailClient client, IOptions<EmailOptions> email, InquiryNotificationOptions options) : IInquiryTeamNotifier
{
    public bool Configured => options.Enabled && email.Value.Enabled && MailAddress.TryCreate(options.TeamEmail, out var address)
        && address.Address == options.TeamEmail && !options.TeamEmail.Any(char.IsControl);
    public async Task SendAsync(Inquiry inquiry, CancellationToken token)
    {
        if (!Configured) throw new InquiryNotificationException();
        var d = inquiry.Data;
        var body = $"Solicitud: {inquiry.RequestId}\nNombre: {d.Name}\nCorreo: {d.Email}\nOrganización declarada: {d.Organization}\nPaís: {inquiry.CountryName}\nMotivo: {d.Topic}\nServicio: {d.ServiceCode}\nProyecto: {d.ProjectReference}\nConvocatoria: {d.FundingReference}\nFecha límite: {d.Deadline:yyyy-MM-dd}\n\n{d.Description}\n\nSolicitud de orientación/cotización. No constituye contratación, precio ni promesa de elegibilidad.";
        try
        {
            _ = await client.SendAsync(WaitUntil.Started, new EmailMessage(email.Value.FromAddress, options.TeamEmail,
                new EmailContent($"FundingPlatform — Solicitud {inquiry.RequestId}") { PlainText = body }), token);
        }
        catch (Exception e) when (e is RequestFailedException or HttpRequestException) { throw new InquiryNotificationException(); }
    }
}
