using System.Net.Mail;
using System.Security.Cryptography;
using System.Text.Json;
using FundingPlatform.Core.Engagement;
using FundingPlatform.Core.Validation;

namespace FundingPlatform.Application.Engagement;

public static class ProfessionalServices
{
    public static readonly string[] Codes = ["advisory", "application-support", "project-design", "getting-started", "partnerships", "translation", "proposal-review"];
    public static readonly string[] Topics = ["funding", "project", "application", "project-design", "partnerships", "service", "platform", "other"];
}
public interface IInquiryRepository
{
    Task<InquiryReceipt> CaptureAsync(InquiryInput data, byte[] hash, CancellationToken token);
    Task<InquiryPage> ListAsync(Guid actor, int page, CancellationToken token);
    Task ReviewAsync(Guid actor, Guid id, InquiryReview data, CancellationToken token);
    Task<Inquiry?> ClaimNotificationAsync(Guid id, CancellationToken token);
    Task FinishNotificationAsync(Guid id, bool accepted, CancellationToken token);
}
public interface IInquiryTeamNotifier
{
    bool Configured { get; }
    Task SendAsync(Inquiry inquiry, CancellationToken token);
}
public sealed class InquiryDataException(int number, Exception inner) : Exception("Inquiry operation failed.", inner)
{ public int Number { get; } = number; }
public sealed class InquiryNotificationException() : Exception("Inquiry notification could not be confirmed.");

public static class InquiryRules
{
    public static InquiryInput Normalize(InquiryInput d) => d with { Name = d.Name?.Trim() ?? "", Email = d.Email?.Trim().ToLowerInvariant() ?? "",
        Organization = Trim(d.Organization), ProjectReference = Trim(d.ProjectReference), FundingReference = Trim(d.FundingReference),
        Description = d.Description?.Trim() ?? "", ServiceCode = Trim(d.ServiceCode), Website = Trim(d.Website) };
    private static string? Trim(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();
    public static FieldValidationErrors Validate(InquiryInput d)
    {
        var errors = new FieldValidationErrors();
        if (d.RequestId == Guid.Empty || d.Website is not null) errors.Set("request", "inquiry-invalid", "Revisa la solicitud.");
        if (d.Name.Length is < 2 or > 150 || d.Name.Any(char.IsControl)) errors.Set("name", "inquiry-name", "Indica tu nombre (2 a 150 caracteres).");
        if (d.Email.Length > 254 || !MailAddress.TryCreate(d.Email, out var mail) || mail.Address != d.Email || d.Email.Any(char.IsControl))
            errors.Set("email", "inquiry-email", "Indica un correo válido.");
        if (d.CountryId is < 1 or > short.MaxValue) errors.Set("countryId", "inquiry-country", "Selecciona tu país.");
        if (!ProfessionalServices.Topics.Contains(d.Topic) || d.ServiceCode is not null && !ProfessionalServices.Codes.Contains(d.ServiceCode)
            || d.Topic == "service" && d.ServiceCode is null || d.Topic != "service" && d.ServiceCode is not null)
            errors.Set("topic", "inquiry-topic", "Selecciona el motivo y, si corresponde, el servicio.");
        if (d.Organization?.Length > 250 || d.ProjectReference?.Length > 1000 || d.FundingReference?.Length > 1000)
            errors.Set("references", "inquiry-references", "Revisa la longitud de las referencias.");
        if (d.Description.Length is < 20 or > 5000) errors.Set("description", "inquiry-description", "Describe tu necesidad (20 a 5.000 caracteres).");
        if (!d.ConsentToContact) errors.Set("consentToContact", "inquiry-consent", "Confirma que podemos usar estos datos para responderte.");
        if (d.Deadline?.Year is < 2000 or > 2100) errors.Set("deadline", "inquiry-deadline", "Revisa la fecha límite.");
        return errors;
    }
}
public sealed class InquiryService(IInquiryRepository repository, IInquiryTeamNotifier notifier)
{
    public async Task<InquiryReceipt> CaptureAsync(InquiryInput normalized, CancellationToken token)
    {
        var hash = SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(normalized, new JsonSerializerOptions(JsonSerializerDefaults.Web)));
        var receipt = await repository.CaptureAsync(normalized, hash, token);
        // Durable record first. No loss or duplicate capture if email is off/unavailable.
        if (notifier.Configured)
        {
            try
            {
                var pending = await repository.ClaimNotificationAsync(receipt.RequestId, token);
                if (pending is not null)
                {
                    var accepted = false;
                    using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
                    timeout.CancelAfter(TimeSpan.FromSeconds(15));
                    try { await notifier.SendAsync(pending, timeout.Token); accepted = true; }
                    catch (Exception e) when (e is InquiryNotificationException or OperationCanceledException) { }
                    using var finish = new CancellationTokenSource(TimeSpan.FromSeconds(5));
                    await repository.FinishNotificationAsync(receipt.RequestId, accepted, finish.Token);
                }
            }
            catch (Exception e) when (e is InquiryDataException or OperationCanceledException) { /* Inbox remains authoritative. */ }
        }
        return receipt;
    }
}
