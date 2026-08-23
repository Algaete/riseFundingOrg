using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace FundingPlatform.Application.SourceDocuments;

public sealed record EventIngressTrustPolicyCommand(
    Guid SuperAdminUserId,
    Guid? PolicyId,
    byte[]? ExpectedRowVersion,
    Guid TenantId,
    Guid PrincipalObjectId,
    Guid ApplicationClientId,
    string TopicResourceId,
    string EventSubscriptionName,
    string StorageAccountResourceId,
    string StorageAccountHost,
    string QuarantineContainer,
    bool IsEnabled,
    DateTimeOffset ValidFromUtc,
    DateTimeOffset? ExpiresAtUtc,
    string Reason,
    string IdempotencyKey,
    string CorrelationId);

public sealed record EventIngressTrustPolicyMutation(
    bool Succeeded,
    string Code,
    Guid? PolicyId,
    bool? IsEnabled,
    byte[]? RowVersion,
    bool WasReplay);

public interface IEventIngressTrustPolicyRepository
{
    Task<EventIngressTrustPolicyMutation> UpsertAsync(
        EventIngressTrustPolicyCommand command,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);
}

public sealed class EventIngressTrustPolicyAdministrationService(
    IEventIngressTrustPolicyRepository repository,
    TimeProvider timeProvider)
{
    public async Task<EventIngressTrustPolicyMutation> UpsertAsync(
        EventIngressTrustPolicyCommand command,
        CancellationToken cancellationToken)
    {
        var normalized = Normalize(command);
        Validate(normalized);
        var keyHash = SHA256.HashData(Encoding.UTF8.GetBytes(normalized.IdempotencyKey));
        var requestHash = SHA256.HashData(Encoding.UTF8.GetBytes(string.Join('\n',
            "EventIngressTrustPolicy/v1",
            normalized.PolicyId?.ToString("D") ?? string.Empty,
            normalized.ExpectedRowVersion is null
                ? string.Empty : Convert.ToHexString(normalized.ExpectedRowVersion),
            normalized.TenantId.ToString("D"),
            normalized.PrincipalObjectId.ToString("D"),
            normalized.ApplicationClientId.ToString("D"),
            normalized.TopicResourceId,
            normalized.EventSubscriptionName,
            normalized.StorageAccountResourceId,
            normalized.StorageAccountHost,
            normalized.QuarantineContainer,
            normalized.IsEnabled ? "1" : "0",
            normalized.ValidFromUtc.UtcDateTime.ToString("O"),
            normalized.ExpiresAtUtc?.UtcDateTime.ToString("O") ?? string.Empty,
            normalized.Reason)));
        return await repository.UpsertAsync(
            normalized, keyHash, requestHash, timeProvider.GetUtcNow(), cancellationToken);
    }

    private static EventIngressTrustPolicyCommand Normalize(
        EventIngressTrustPolicyCommand value) => value with
    {
        TopicResourceId = value.TopicResourceId.Trim().ToLowerInvariant(),
        EventSubscriptionName = value.EventSubscriptionName.Trim(),
        StorageAccountResourceId = value.StorageAccountResourceId.Trim().ToLowerInvariant(),
        StorageAccountHost = value.StorageAccountHost.Trim().ToLowerInvariant(),
        QuarantineContainer = value.QuarantineContainer.Trim().ToLowerInvariant(),
        Reason = value.Reason.Trim(),
        IdempotencyKey = value.IdempotencyKey.Trim(),
        CorrelationId = value.CorrelationId.Trim()
    };

    private static void Validate(EventIngressTrustPolicyCommand value)
    {
        var topicPattern =
            "^/subscriptions/[0-9a-f-]{36}/resourcegroups/[^/?#]+/providers/microsoft\\.eventgrid/(?:topics|systemtopics)/[^/?#]+$";
        var storagePattern =
            "^/subscriptions/[0-9a-f-]{36}/resourcegroups/[^/?#]+/providers/microsoft\\.storage/storageaccounts/[a-z0-9]{3,24}$";
        if (value.SuperAdminUserId == Guid.Empty || value.TenantId == Guid.Empty ||
            value.PrincipalObjectId == Guid.Empty || value.ApplicationClientId == Guid.Empty ||
            (value.PolicyId.HasValue != (value.ExpectedRowVersion is { Length: 8 })) ||
            !Regex.IsMatch(value.TopicResourceId, topicPattern, RegexOptions.CultureInvariant) ||
            !Regex.IsMatch(value.StorageAccountResourceId, storagePattern, RegexOptions.CultureInvariant) ||
            value.TopicResourceId.Any(char.IsControl) ||
            value.StorageAccountResourceId.Any(char.IsControl) ||
            value.EventSubscriptionName.Length is < 1 or > 100 ||
            value.EventSubscriptionName.Any(character => char.IsControl(character) || character == '/') ||
            !Regex.IsMatch(value.StorageAccountHost,
                "^[a-z0-9]{3,24}\\.blob\\.core\\.windows\\.net$", RegexOptions.CultureInvariant) ||
            !StorageAccountMatchesHost(
                value.StorageAccountResourceId, value.StorageAccountHost) ||
            !Regex.IsMatch(value.QuarantineContainer,
                "^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])$", RegexOptions.CultureInvariant) ||
            value.QuarantineContainer.Contains("--", StringComparison.Ordinal) ||
            value.Reason.Length is < 3 or > 500 || value.Reason.Any(char.IsControl) ||
            value.IdempotencyKey.Length is < 8 or > 128 || value.IdempotencyKey.Any(char.IsControl) ||
            value.CorrelationId.Length is < 1 or > 100 || value.CorrelationId.Any(char.IsControl) ||
            value.ValidFromUtc.Offset != TimeSpan.Zero ||
            value.ExpiresAtUtc.HasValue && value.ExpiresAtUtc.Value.Offset != TimeSpan.Zero ||
            value.ExpiresAtUtc.HasValue && value.ExpiresAtUtc.Value <= value.ValidFromUtc)
            throw new ArgumentException("The Defender Event Grid trust policy is invalid or incomplete.");
    }

    private static bool StorageAccountMatchesHost(string resourceId, string host)
    {
        const string segment = "/storageaccounts/";
        var index = resourceId.LastIndexOf(segment, StringComparison.Ordinal);
        if (index < 0) return false;
        var account = resourceId[(index + segment.Length)..];
        var separator = host.IndexOf('.', StringComparison.Ordinal);
        return separator > 0 && string.Equals(
            account, host[..separator], StringComparison.Ordinal);
    }
}
