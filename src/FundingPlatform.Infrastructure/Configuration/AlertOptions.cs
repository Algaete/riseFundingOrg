using FundingPlatform.Application.Alerts;
using FundingPlatform.Infrastructure.Identity.Configuration;

namespace FundingPlatform.Infrastructure.Configuration;

public sealed class AlertOptions
{
    public const string SectionName = "Alerts";

    public bool Enabled { get; set; }
    public int SchedulerBatchSize { get; set; } = 10;
    public int ScheduleLeaseSeconds { get; set; } = 120;
    public int DeliveryLeaseSeconds { get; set; } = 180;
    public int MaximumAttempts { get; set; } = 3;
    public int RetryBaseSeconds { get; set; } = 300;
    public string UnsubscribeTokenKey { get; set; } = string.Empty;

    public AlertProcessingPolicy ToPolicy(EmailOptions email)
    {
        byte[] key = [];
        if (!string.IsNullOrWhiteSpace(UnsubscribeTokenKey))
        {
            try { key = Convert.FromBase64String(UnsubscribeTokenKey); }
            catch (FormatException) { key = []; }
        }

        return new AlertProcessingPolicy(
            Enabled,
            SchedulerBatchSize,
            ScheduleLeaseSeconds,
            DeliveryLeaseSeconds,
            MaximumAttempts,
            RetryBaseSeconds,
            email.FrontendBaseUrl,
            key);
    }

    public static bool IsValid(AlertOptions options, EmailOptions email)
    {
        try
        {
            var policy = options.ToPolicy(email);
            policy.EnsureValid();
            return !options.Enabled || EmailOptions.IsValid(email);
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }
}
