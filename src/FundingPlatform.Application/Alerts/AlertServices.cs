using System.Security.Cryptography;
using System.Text;
using System.Globalization;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.Alerts;
using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Application.Alerts;

public interface ISavedSearchAlertRepository
{
    Task<SavedSearchPage?> ListSavedSearchesAsync(
        Guid userPublicId, Guid organizationPublicId, int pageNumber, int pageSize,
        CancellationToken cancellationToken);

    Task<SavedSearchDetails?> GetSavedSearchAsync(
        Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
        CancellationToken cancellationToken);

    Task<SavedSearchMutation> CreateSavedSearchAsync(
        Guid userPublicId, Guid organizationPublicId, string name,
        FundingOpportunitySearchFilters filters, byte[] idempotencyKeyHash,
        byte[] requestHash, DateTimeOffset nowUtc, CancellationToken cancellationToken);

    Task<SavedSearchMutation> UpdateSavedSearchAsync(
        Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
        string name, FundingOpportunitySearchFilters filters, byte[] expectedRowVersion,
        DateTimeOffset nowUtc, CancellationToken cancellationToken);

    Task<SavedSearchMutation> DeleteSavedSearchAsync(
        Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
        byte[] expectedRowVersion, DateTimeOffset nowUtc, CancellationToken cancellationToken);

    Task<AlertSubscriptionMutation> PutAlertAsync(
        Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
        byte preferredHourLocal, string timeZoneId, DateTimeOffset nextRunAtUtc,
        DateTimeOffset nowUtc, CancellationToken cancellationToken);

    Task<AlertSubscriptionMutation> DeleteAlertAsync(
        Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
        DateTimeOffset nowUtc, CancellationToken cancellationToken);

    Task<AlertSubscriptionMutation> UnsubscribeAsync(
        Guid alertSubscriptionPublicId, Guid unsubscribeNonce,
        DateTimeOffset nowUtc, CancellationToken cancellationToken);

    Task<NotificationLogPage?> ListNotificationLogsAsync(
        Guid userPublicId, Guid organizationPublicId, int pageNumber, int pageSize,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<AlertScheduleLease>> ClaimSchedulesAsync(
        Guid leaseOwner, int batchSize, int leaseSeconds, DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<AlertScheduleMaterialization> MaterializeScheduleAsync(
        Guid alertSubscriptionPublicId, Guid leaseId, DateTimeOffset scheduledForUtc,
        DateTimeOffset nextRunAtUtc, DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<AlertDeliveryLease?> ClaimDeliveryAsync(
        Guid leaseOwner, int leaseSeconds, int maximumAttempts, DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<bool> RenewDeliveryLeaseAsync(
        Guid notificationLogPublicId, Guid leaseId, int leaseSeconds,
        DateTimeOffset nowUtc, CancellationToken cancellationToken);

    Task<bool> CompleteDeliveryAsync(
        Guid notificationLogPublicId, Guid leaseId, string providerMessageId,
        DateTimeOffset nowUtc, CancellationToken cancellationToken);

    Task<bool> FailDeliveryAsync(
        Guid notificationLogPublicId, Guid leaseId, bool deliveryUnknown,
        string errorCode, int retryDelaySeconds, int maximumAttempts, DateTimeOffset nowUtc,
        CancellationToken cancellationToken);
}

public interface IAlertEmailSender
{
    Task<AlertEmailDeliveryResult> SendAsync(
        AlertEmailMessage message, CancellationToken cancellationToken);
}

public sealed class AlertEmailDeliveryException(
    string errorCode,
    bool deliveryUnknown,
    Exception? innerException = null) : Exception(
        "Alert email delivery failed.", innerException)
{
    public string ErrorCode { get; } = errorCode;
    public bool DeliveryUnknown { get; } = deliveryUnknown;
}

public sealed record AlertProcessingPolicy(
    bool Enabled,
    int SchedulerBatchSize,
    int ScheduleLeaseSeconds,
    int DeliveryLeaseSeconds,
    int MaximumAttempts,
    int RetryBaseSeconds,
    string FrontendBaseUrl,
    byte[] UnsubscribeTokenKey)
{
    public void EnsureValid()
    {
        if (SchedulerBatchSize is < 1 or > 25 ||
            ScheduleLeaseSeconds is < 30 or > 900 ||
            DeliveryLeaseSeconds is < 60 or > 900 ||
            MaximumAttempts is < 1 or > 5 || RetryBaseSeconds is < 30 or > 3600 ||
            (Enabled && (!Uri.TryCreate(FrontendBaseUrl, UriKind.Absolute, out var frontend) ||
                         (frontend.Scheme != Uri.UriSchemeHttps &&
                          !(frontend.Scheme == Uri.UriSchemeHttp && frontend.IsLoopback)) ||
                         UnsubscribeTokenKey.Length != 32)))
            throw new InvalidOperationException("The alert processing policy is invalid.");
    }
}

public sealed record SavedSearchWriteCommand(
    Guid UserPublicId,
    Guid OrganizationPublicId,
    Guid? SavedSearchPublicId,
    string Name,
    FundingOpportunitySearchFilters Filters,
    string? IdempotencyKey,
    byte[]? ExpectedRowVersion);

public enum SavedSearchServiceOutcome
{
    Success,
    Created,
    Deleted,
    Replay,
    ValidationFailed,
    NotFound,
    PreconditionFailed,
    IdempotencyConflict,
    AlertsDisabled
}

public sealed record SavedSearchServiceResult(
    SavedSearchServiceOutcome Outcome,
    SavedSearchDetails? SavedSearch = null,
    AlertSubscriptionDetails? Alert = null,
    IReadOnlyDictionary<string, string[]>? Errors = null);

public sealed class SavedSearchAlertService(
    ISavedSearchAlertRepository repository,
    AlertProcessingPolicy policy,
    TimeProvider timeProvider)
{
    public async Task<SavedSearchPage?> ListAsync(
        Guid userPublicId, Guid organizationPublicId, int page, int pageSize,
        CancellationToken cancellationToken)
    {
        if (!ValidIdentity(userPublicId, organizationPublicId) ||
            page is < 1 or > 10_000 || pageSize is < 1 or > 50)
            return null;
        return await repository.ListSavedSearchesAsync(
            userPublicId, organizationPublicId, page, pageSize, cancellationToken);
    }

    public Task<SavedSearchDetails?> GetAsync(
        Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
        CancellationToken cancellationToken) =>
        !ValidIdentity(userPublicId, organizationPublicId) || savedSearchPublicId == Guid.Empty
            ? Task.FromResult<SavedSearchDetails?>(null)
            : repository.GetSavedSearchAsync(
                userPublicId, organizationPublicId, savedSearchPublicId, cancellationToken);

    public async Task<SavedSearchServiceResult> CreateAsync(
        SavedSearchWriteCommand command, CancellationToken cancellationToken)
    {
        var normalized = Normalize(command);
        var errors = Validate(normalized, requireIdempotencyKey: true, requireRowVersion: false);
        if (errors.Count > 0)
            return Invalid(errors);
        var idempotencyKeyHash = Hash(normalized.IdempotencyKey!);
        var mutation = await repository.CreateSavedSearchAsync(
            normalized.UserPublicId, normalized.OrganizationPublicId, normalized.Name,
            normalized.Filters, idempotencyKeyHash, Hash(RequestMaterial(normalized)),
            timeProvider.GetUtcNow(), cancellationToken);
        return Map(mutation);
    }

    public async Task<SavedSearchServiceResult> UpdateAsync(
        SavedSearchWriteCommand command, CancellationToken cancellationToken)
    {
        var normalized = Normalize(command);
        var errors = Validate(normalized, requireIdempotencyKey: false, requireRowVersion: true);
        if (errors.Count > 0)
            return Invalid(errors);
        var mutation = await repository.UpdateSavedSearchAsync(
            normalized.UserPublicId, normalized.OrganizationPublicId,
            normalized.SavedSearchPublicId!.Value, normalized.Name, normalized.Filters,
            normalized.ExpectedRowVersion!, timeProvider.GetUtcNow(), cancellationToken);
        return Map(mutation);
    }

    public async Task<SavedSearchServiceResult> DeleteAsync(
        Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
        byte[]? expectedRowVersion, CancellationToken cancellationToken)
    {
        if (!ValidIdentity(userPublicId, organizationPublicId) ||
            savedSearchPublicId == Guid.Empty || expectedRowVersion?.Length != 8)
            return Invalid(new Dictionary<string, string[]>
            {
                ["ifMatch"] = ["Envía el ETag fuerte vigente."]
            });
        return Map(await repository.DeleteSavedSearchAsync(
            userPublicId, organizationPublicId, savedSearchPublicId, expectedRowVersion,
            timeProvider.GetUtcNow(), cancellationToken));
    }

    public async Task<SavedSearchServiceResult> PutAlertAsync(
        Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
        byte preferredHourLocal, string? timeZoneId, CancellationToken cancellationToken)
    {
        if (!policy.Enabled)
            return new SavedSearchServiceResult(SavedSearchServiceOutcome.AlertsDisabled);
        var normalizedZone = (timeZoneId ?? string.Empty).Trim();
        if (!ValidIdentity(userPublicId, organizationPublicId) ||
            savedSearchPublicId == Guid.Empty || preferredHourLocal > 23 ||
            !AlertScheduleCalculator.TryFindTimeZone(normalizedZone, out _))
            return Invalid(new Dictionary<string, string[]>
            {
                ["alert"] = ["La hora o zona IANA de la alerta no es válida."]
            });
        var nowUtc = timeProvider.GetUtcNow();
        var nextRun = AlertScheduleCalculator.NextDailyRun(
            nowUtc, preferredHourLocal, normalizedZone);
        var mutation = await repository.PutAlertAsync(
            userPublicId, organizationPublicId, savedSearchPublicId,
            preferredHourLocal, normalizedZone, nextRun, nowUtc, cancellationToken);
        return Map(mutation);
    }

    public async Task<SavedSearchServiceResult> DeleteAlertAsync(
        Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
        CancellationToken cancellationToken)
    {
        if (!ValidIdentity(userPublicId, organizationPublicId) ||
            savedSearchPublicId == Guid.Empty)
            return new SavedSearchServiceResult(SavedSearchServiceOutcome.NotFound);
        return Map(await repository.DeleteAlertAsync(
            userPublicId, organizationPublicId, savedSearchPublicId,
            timeProvider.GetUtcNow(), cancellationToken));
    }

    public Task<NotificationLogPage?> ListNotificationsAsync(
        Guid userPublicId, Guid organizationPublicId, int page, int pageSize,
        CancellationToken cancellationToken) =>
        !ValidIdentity(userPublicId, organizationPublicId) ||
        page is < 1 or > 10_000 || pageSize is < 1 or > 50
            ? Task.FromResult<NotificationLogPage?>(null)
            : repository.ListNotificationLogsAsync(
                userPublicId, organizationPublicId, page, pageSize, cancellationToken);

    public async Task<bool> UnsubscribeAsync(
        string? token, AlertUnsubscribeTokenService tokenService,
        CancellationToken cancellationToken)
    {
        if (!tokenService.TryValidate(token, out var subscriptionId, out var nonce))
            return false;
        var result = await repository.UnsubscribeAsync(
            subscriptionId, nonce, timeProvider.GetUtcNow(), cancellationToken);
        return result.Outcome is AlertSubscriptionMutationOutcome.Deleted or
            AlertSubscriptionMutationOutcome.Unchanged;
    }

    private static SavedSearchWriteCommand Normalize(SavedSearchWriteCommand value) => value with
    {
        Name = (value.Name ?? string.Empty).Trim(),
        IdempotencyKey = value.IdempotencyKey?.Trim(),
        Filters = FundingOpportunityWorkspaceService.Normalize(value.Filters with
        {
            PageNumber = 1,
            PageSize = 20
        })
    };

    private static Dictionary<string, string[]> Validate(
        SavedSearchWriteCommand value, bool requireIdempotencyKey, bool requireRowVersion)
    {
        var errors = FundingOpportunityWorkspaceService.Validate(value.Filters);
        errors.Remove("page");
        errors.Remove("pageSize");
        if (!ValidIdentity(value.UserPublicId, value.OrganizationPublicId) ||
            (value.SavedSearchPublicId.HasValue && value.SavedSearchPublicId == Guid.Empty))
            errors["resource"] = ["El recurso no existe."];
        if (value.Name.Length is < 1 or > 150)
            errors["name"] = ["El nombre debe tener entre 1 y 150 caracteres."];
        if (requireIdempotencyKey && !ValidIdempotencyKey(value.IdempotencyKey))
            errors["idempotencyKey"] = ["Idempotency-Key debe tener entre 16 y 128 caracteres ASCII."];
        if (requireRowVersion && value.ExpectedRowVersion?.Length != 8)
            errors["ifMatch"] = ["Envía el ETag fuerte vigente."];
        return errors;
    }

    private static bool ValidIdempotencyKey(string? value) =>
        value is { Length: >= 16 and <= 128 } && value.All(character => character is >= '!' and <= '~');

    private static bool ValidIdentity(Guid userPublicId, Guid organizationPublicId) =>
        userPublicId != Guid.Empty && organizationPublicId != Guid.Empty;

    private static SavedSearchServiceResult Invalid(IReadOnlyDictionary<string, string[]> errors) =>
        new(SavedSearchServiceOutcome.ValidationFailed, Errors: errors);

    private static SavedSearchServiceResult Map(SavedSearchMutation mutation) =>
        new(mutation.Outcome switch
        {
            SavedSearchMutationOutcome.Created => SavedSearchServiceOutcome.Created,
            SavedSearchMutationOutcome.Replay => SavedSearchServiceOutcome.Replay,
            SavedSearchMutationOutcome.Deleted => SavedSearchServiceOutcome.Deleted,
            SavedSearchMutationOutcome.NotFound => SavedSearchServiceOutcome.NotFound,
            SavedSearchMutationOutcome.PreconditionFailed => SavedSearchServiceOutcome.PreconditionFailed,
            SavedSearchMutationOutcome.IdempotencyConflict => SavedSearchServiceOutcome.IdempotencyConflict,
            SavedSearchMutationOutcome.Invalid => SavedSearchServiceOutcome.ValidationFailed,
            _ => SavedSearchServiceOutcome.Success
        }, mutation.SavedSearch);

    private static SavedSearchServiceResult Map(AlertSubscriptionMutation mutation) =>
        new(mutation.Outcome switch
        {
            AlertSubscriptionMutationOutcome.Created => SavedSearchServiceOutcome.Created,
            AlertSubscriptionMutationOutcome.Deleted => SavedSearchServiceOutcome.Deleted,
            AlertSubscriptionMutationOutcome.NotFound => SavedSearchServiceOutcome.NotFound,
            AlertSubscriptionMutationOutcome.PreconditionFailed => SavedSearchServiceOutcome.PreconditionFailed,
            AlertSubscriptionMutationOutcome.Disabled => SavedSearchServiceOutcome.AlertsDisabled,
            _ => SavedSearchServiceOutcome.Success
        }, Alert: mutation.Alert);

    private static byte[] Hash(string value) => SHA256.HashData(Encoding.UTF8.GetBytes(value));

    private static string RequestMaterial(SavedSearchWriteCommand value)
    {
        var filters = value.Filters;
        static string Join<T>(IEnumerable<T> values) => string.Join(',', values);
        return string.Join('\n',
            "saved-search-v1", value.OrganizationPublicId.ToString("D"), value.Name,
            filters.Query ?? "", filters.Sponsor ?? "",
            filters.MinimumAmount?.ToString(CultureInfo.InvariantCulture) ?? "",
            filters.MaximumAmount?.ToString(CultureInfo.InvariantCulture) ?? "", filters.Currency ?? "",
            filters.ClosingFrom?.ToString("yyyy-MM-dd") ?? "",
            filters.ClosingTo?.ToString("yyyy-MM-dd") ?? "", filters.OnlyOpen ? "1" : "0",
            ((byte)filters.Sort).ToString(), Join(filters.CountryIds), Join(filters.RegionIds),
            Join(filters.CategoryIds), Join(filters.TagIds), Join(filters.BeneficiaryTypeIds),
            Join(filters.ProjectTypeIds), Join(filters.FundingTypeIds),
            Join(filters.OrganizationTypeIds), Join(filters.FunderPublicIds));
    }
}

public static class AlertScheduleCalculator
{
    public static DateTimeOffset NextDailyRun(
        DateTimeOffset nowUtc, byte preferredHourLocal, string timeZoneId)
    {
        if (!TryFindTimeZone(timeZoneId, out var zone) || preferredHourLocal > 23)
            throw new ArgumentException("The alert schedule is invalid.");
        var localNow = TimeZoneInfo.ConvertTime(nowUtc, zone);
        var date = DateOnly.FromDateTime(localNow.DateTime);
        var local = date.ToDateTime(new TimeOnly(preferredHourLocal, 0), DateTimeKind.Unspecified);
        if (local <= localNow.DateTime)
            local = date.AddDays(1).ToDateTime(
                new TimeOnly(preferredHourLocal, 0), DateTimeKind.Unspecified);
        while (zone.IsInvalidTime(local))
            local = local.AddMinutes(1);
        var offset = zone.IsAmbiguousTime(local)
            ? zone.GetAmbiguousTimeOffsets(local).Min()
            : zone.GetUtcOffset(local);
        return new DateTimeOffset(local, offset).ToUniversalTime();
    }

    public static bool TryFindTimeZone(string? id, out TimeZoneInfo zone)
    {
        zone = null!;
        if (string.IsNullOrWhiteSpace(id) || id.Length > 100 || id.Any(char.IsControl))
            return false;
        try
        {
            zone = TimeZoneInfo.FindSystemTimeZoneById(id);
            return true;
        }
        catch (TimeZoneNotFoundException) { return false; }
        catch (InvalidTimeZoneException) { return false; }
    }
}

public sealed class AlertUnsubscribeTokenService(AlertProcessingPolicy policy)
{
    private const byte Version = 1;

    public string Create(Guid subscriptionPublicId, Guid nonce)
    {
        policy.EnsureValid();
        Span<byte> payload = stackalloc byte[33];
        payload[0] = Version;
        subscriptionPublicId.TryWriteBytes(payload[1..17]);
        nonce.TryWriteBytes(payload[17..33]);
        var signature = HMACSHA256.HashData(policy.UnsubscribeTokenKey, payload);
        var token = new byte[payload.Length + signature.Length];
        payload.CopyTo(token);
        signature.CopyTo(token.AsSpan(payload.Length));
        return Convert.ToBase64String(token).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }

    public bool TryValidate(string? token, out Guid subscriptionPublicId, out Guid nonce)
    {
        subscriptionPublicId = Guid.Empty;
        nonce = Guid.Empty;
        if (!policy.Enabled || string.IsNullOrWhiteSpace(token) || token.Length > 128)
            return false;
        try
        {
            var normalized = token.Replace('-', '+').Replace('_', '/');
            normalized = normalized.PadRight((normalized.Length + 3) / 4 * 4, '=');
            var bytes = Convert.FromBase64String(normalized);
            if (bytes.Length != 65 || bytes[0] != Version)
                return false;
            var canonical = Convert.ToBase64String(bytes)
                .TrimEnd('=').Replace('+', '-').Replace('/', '_');
            if (!string.Equals(token, canonical, StringComparison.Ordinal))
                return false;
            var expected = HMACSHA256.HashData(policy.UnsubscribeTokenKey, bytes.AsSpan(0, 33));
            if (!CryptographicOperations.FixedTimeEquals(expected, bytes.AsSpan(33, 32)))
                return false;
            subscriptionPublicId = new Guid(bytes.AsSpan(1, 16));
            nonce = new Guid(bytes.AsSpan(17, 16));
            return subscriptionPublicId != Guid.Empty && nonce != Guid.Empty;
        }
        catch (FormatException) { return false; }
    }
}

public sealed class AlertProcessingService(
    ISavedSearchAlertRepository repository,
    IAlertEmailSender emailSender,
    AlertUnsubscribeTokenService tokenService,
    AlertProcessingPolicy policy,
    TimeProvider timeProvider,
    Guid workerId)
{
    public async Task ProcessSchedulesAsync(CancellationToken cancellationToken)
    {
        if (!policy.Enabled) return;
        var nowUtc = timeProvider.GetUtcNow();
        var leases = await repository.ClaimSchedulesAsync(
            workerId, policy.SchedulerBatchSize, policy.ScheduleLeaseSeconds,
            nowUtc, cancellationToken);
        foreach (var lease in leases)
        {
            var next = AlertScheduleCalculator.NextDailyRun(
                lease.ScheduledForUtc.AddSeconds(1), lease.PreferredHourLocal, lease.TimeZoneId);
            _ = await repository.MaterializeScheduleAsync(
                lease.AlertSubscriptionPublicId, lease.LeaseId,
                lease.ScheduledForUtc, next, timeProvider.GetUtcNow(), cancellationToken);
        }
    }

    public async Task ProcessDeliveriesAsync(CancellationToken cancellationToken)
    {
        if (!policy.Enabled) return;
        for (var index = 0; index < policy.SchedulerBatchSize; index++)
        {
            var lease = await repository.ClaimDeliveryAsync(
                workerId, policy.DeliveryLeaseSeconds, policy.MaximumAttempts,
                timeProvider.GetUtcNow(), cancellationToken);
            if (lease is null) return;
            try
            {
                if (!await repository.RenewDeliveryLeaseAsync(
                        lease.NotificationLogPublicId, lease.LeaseId,
                        policy.DeliveryLeaseSeconds, timeProvider.GetUtcNow(), cancellationToken))
                    continue;
                var message = new AlertEmailMessage(
                    lease.NotificationLogPublicId, lease.RecipientEmail,
                    lease.RecipientDisplayName, lease.Locale, lease.SavedSearchName,
                    tokenService.Create(lease.AlertSubscriptionPublicId, lease.UnsubscribeNonce),
                    lease.Items);
                var result = await emailSender.SendAsync(message, cancellationToken);
                _ = await repository.CompleteDeliveryAsync(
                    lease.NotificationLogPublicId, lease.LeaseId,
                    result.ProviderMessageId, timeProvider.GetUtcNow(), cancellationToken);
            }
            catch (AlertEmailDeliveryException exception)
            {
                var retryExponent = Math.Clamp(lease.AttemptCount - 1, 0, 4);
                var delay = Math.Min(
                    86_400,
                    checked(policy.RetryBaseSeconds * (1 << retryExponent)));
                _ = await repository.FailDeliveryAsync(
                    lease.NotificationLogPublicId, lease.LeaseId,
                    exception.DeliveryUnknown, SafeCode(exception.ErrorCode), delay,
                    policy.MaximumAttempts, timeProvider.GetUtcNow(), CancellationToken.None);
            }
        }
    }

    private static string SafeCode(string? value)
    {
        var normalized = (value ?? "delivery-error").Trim().ToLowerInvariant();
        return normalized.Length is >= 1 and <= 100 &&
               normalized.All(character => character is >= 'a' and <= 'z' or >= '0' and <= '9' or '-')
            ? normalized
            : "delivery-error";
    }
}
