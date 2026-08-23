using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace FundingPlatform.Application.FundingOpportunities;

public enum FundingSourceAcquisitionEndpointKind : byte
{
    Acquisition = 1,
    License = 2,
    Robots = 3
}

public sealed record FundingSourceAcquisitionEndpoint(
    FundingSourceAcquisitionEndpointKind Kind,
    string CanonicalUri);

public sealed record FundingSourceAcquisitionPolicyCommand(
    Guid SuperAdminUserId,
    string ProviderCode,
    string BaseUrl,
    string LicenseName,
    string LicenseUrl,
    DateTimeOffset LicenseReviewedAtUtc,
    DateTimeOffset? LicenseExpiresAtUtc,
    string RobotsPolicyCode,
    int RobotsPolicyVersion,
    DateTimeOffset RobotsReviewedAtUtc,
    DateTimeOffset? RobotsExpiresAtUtc,
    IReadOnlyList<string> AllowedHosts,
    IReadOnlyList<FundingSourceAcquisitionEndpoint> AllowedEndpoints,
    int RequestRateLimitPerMinute,
    int MaximumResponseBytes,
    short ContentRetentionDays,
    int? ScheduleIntervalSeconds,
    bool IsEnabled,
    bool ComplianceApproved,
    string IdempotencyKey,
    string CorrelationId);

public sealed record FundingSourceAcquisitionPolicyMutation(
    bool Succeeded,
    string Code,
    int? FundingSourceId,
    Guid? PolicyId,
    int? PolicyVersion,
    byte[]? AcquisitionPolicyFingerprint,
    bool? IsEnabled,
    bool WasReplay);

public interface IFundingSourceAcquisitionPolicyRepository
{
    Task<FundingSourceAcquisitionPolicyMutation> UpsertAsync(
        FundingSourceAcquisitionPolicyCommand command,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);
}

public sealed class FundingSourceAcquisitionPolicyAdministrationService(
    IFundingSourceAcquisitionPolicyRepository repository,
    TimeProvider timeProvider)
{
    public async Task<FundingSourceAcquisitionPolicyMutation> UpsertAsync(
        FundingSourceAcquisitionPolicyCommand command,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(command);
        var nowUtc = timeProvider.GetUtcNow();
        var normalized = Normalize(command);
        Validate(normalized, nowUtc);
        var idempotencyKeyHash = SHA256.HashData(
            Encoding.UTF8.GetBytes(normalized.IdempotencyKey));
        var requestHash = SHA256.HashData(Encoding.UTF8.GetBytes(
            CanonicalRequestMaterial(normalized)));
        return await repository.UpsertAsync(
            normalized,
            idempotencyKeyHash,
            requestHash,
            nowUtc,
            cancellationToken);
    }

    private static FundingSourceAcquisitionPolicyCommand Normalize(
        FundingSourceAcquisitionPolicyCommand command)
    {
        var hosts = (command.AllowedHosts ?? [])
            .Select(static host => (host ?? string.Empty).Trim().ToLowerInvariant())
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal)
            .ToArray();
        var endpoints = (command.AllowedEndpoints ?? [])
            .Select(endpoint => new FundingSourceAcquisitionEndpoint(
                endpoint.Kind,
                CanonicalHttpsUri(endpoint.CanonicalUri)))
            .Distinct()
            .OrderBy(static endpoint => endpoint.Kind)
            .ThenBy(static endpoint => endpoint.CanonicalUri, StringComparer.Ordinal)
            .ToArray();
        return command with
        {
            ProviderCode = (command.ProviderCode ?? string.Empty).Trim().ToLowerInvariant(),
            BaseUrl = CanonicalHttpsUri(command.BaseUrl),
            LicenseName = (command.LicenseName ?? string.Empty).Trim(),
            LicenseUrl = CanonicalHttpsUri(command.LicenseUrl),
            RobotsPolicyCode =
                (command.RobotsPolicyCode ?? string.Empty).Trim().ToLowerInvariant(),
            AllowedHosts = hosts,
            AllowedEndpoints = endpoints,
            IdempotencyKey = (command.IdempotencyKey ?? string.Empty).Trim(),
            CorrelationId = (command.CorrelationId ?? string.Empty).Trim()
        };
    }

    private static void Validate(
        FundingSourceAcquisitionPolicyCommand value,
        DateTimeOffset nowUtc)
    {
        if (value.SuperAdminUserId == Guid.Empty ||
            !Regex.IsMatch(value.ProviderCode, "^[-a-z0-9._]{1,100}$",
                RegexOptions.CultureInvariant) ||
            value.LicenseName.Length is < 1 or > 200 || HasControl(value.LicenseName) ||
            value.LicenseReviewedAtUtc.Offset != TimeSpan.Zero ||
            value.LicenseReviewedAtUtc > nowUtc ||
            value.LicenseExpiresAtUtc.HasValue &&
                value.LicenseExpiresAtUtc.Value.Offset != TimeSpan.Zero ||
            value.LicenseExpiresAtUtc.HasValue &&
                value.LicenseExpiresAtUtc.Value <= nowUtc ||
            value.RobotsPolicyCode is not ("enforce" or "not-applicable") ||
            value.RobotsPolicyVersion is < 1 or > 1_000 ||
            value.RobotsReviewedAtUtc.Offset != TimeSpan.Zero ||
            value.RobotsReviewedAtUtc > nowUtc ||
            value.RobotsExpiresAtUtc.HasValue &&
                value.RobotsExpiresAtUtc.Value.Offset != TimeSpan.Zero ||
            value.RobotsExpiresAtUtc.HasValue &&
                value.RobotsExpiresAtUtc.Value <= nowUtc ||
            value.RobotsPolicyCode == "enforce" &&
                !value.RobotsExpiresAtUtc.HasValue ||
            value.AllowedHosts.Count is < 1 or > 5 ||
            value.AllowedHosts.Any(static host => !IsValidHost(host)) ||
            value.AllowedEndpoints.Count is < 2 or > 10 ||
            value.AllowedEndpoints.Any(endpoint =>
                !value.AllowedHosts.Contains(
                    new Uri(endpoint.CanonicalUri, UriKind.Absolute).IdnHost,
                    StringComparer.Ordinal)) ||
            !value.AllowedEndpoints.Any(endpoint =>
                endpoint.Kind == FundingSourceAcquisitionEndpointKind.Acquisition &&
                endpoint.CanonicalUri == value.BaseUrl) ||
            !value.AllowedEndpoints.Any(endpoint =>
                endpoint.Kind == FundingSourceAcquisitionEndpointKind.License &&
                endpoint.CanonicalUri == value.LicenseUrl) ||
            value.RobotsPolicyCode == "enforce" &&
                !value.AllowedEndpoints.Any(endpoint =>
                    endpoint.Kind == FundingSourceAcquisitionEndpointKind.Robots) ||
            value.RequestRateLimitPerMinute is < 1 or > 600 ||
            value.MaximumResponseBytes is < 4_096 or > 26_214_400 ||
            value.ContentRetentionDays is < 1 or > 3_650 ||
            value.ScheduleIntervalSeconds.HasValue &&
                (value.ScheduleIntervalSeconds.Value < 300 ||
                 value.ScheduleIntervalSeconds.Value > 604_800) ||
            value.IsEnabled && !value.ComplianceApproved ||
            value.IdempotencyKey.Length is < 8 or > 128 || HasControl(value.IdempotencyKey) ||
            value.CorrelationId.Length is < 1 or > 100 ||
            !Regex.IsMatch(value.CorrelationId, "^[-A-Za-z0-9:_.]+$",
                RegexOptions.CultureInvariant))
            throw new ArgumentException(
                "The funding-source acquisition policy is invalid or incomplete.");
    }

    private static string CanonicalRequestMaterial(
        FundingSourceAcquisitionPolicyCommand value)
    {
        var fields = new List<string>
        {
            "FundingSourceAcquisitionPolicy/v1",
            value.SuperAdminUserId.ToString("D"),
            value.ProviderCode,
            value.BaseUrl,
            value.LicenseName,
            value.LicenseUrl,
            value.LicenseReviewedAtUtc.UtcDateTime.ToString("O"),
            value.LicenseExpiresAtUtc?.UtcDateTime.ToString("O") ?? string.Empty,
            value.RobotsPolicyCode,
            value.RobotsPolicyVersion.ToString(
                System.Globalization.CultureInfo.InvariantCulture),
            value.RobotsReviewedAtUtc.UtcDateTime.ToString("O"),
            value.RobotsExpiresAtUtc?.UtcDateTime.ToString("O") ?? string.Empty,
            value.RequestRateLimitPerMinute.ToString(
                System.Globalization.CultureInfo.InvariantCulture),
            value.MaximumResponseBytes.ToString(
                System.Globalization.CultureInfo.InvariantCulture),
            value.ContentRetentionDays.ToString(
                System.Globalization.CultureInfo.InvariantCulture),
            value.ScheduleIntervalSeconds?.ToString(
                System.Globalization.CultureInfo.InvariantCulture) ?? string.Empty,
            value.IsEnabled ? "1" : "0",
            value.ComplianceApproved ? "1" : "0"
        };
        fields.AddRange(value.AllowedHosts.Select(static host => "host|" + host));
        fields.AddRange(value.AllowedEndpoints.Select(endpoint =>
            $"endpoint|{(byte)endpoint.Kind}|{endpoint.CanonicalUri}"));
        var builder = new StringBuilder();
        foreach (var field in fields)
        {
            builder.Append(field.Length.ToString(
                System.Globalization.CultureInfo.InvariantCulture));
            builder.Append(':');
            builder.Append(field);
            builder.Append('\n');
        }
        return builder.ToString();
    }

    private static string CanonicalHttpsUri(string? value)
    {
        if (!Uri.TryCreate(value?.Trim(), UriKind.Absolute, out var uri) ||
            uri.Scheme != Uri.UriSchemeHttps || uri.Port != 443 ||
            !string.IsNullOrEmpty(uri.UserInfo) || !string.IsNullOrEmpty(uri.Fragment) ||
            uri.AbsoluteUri.Length > 2_048 || HasControl(uri.AbsoluteUri) ||
            Uri.CheckHostName(uri.IdnHost) != UriHostNameType.Dns)
            throw new ArgumentException("Policy URLs must be canonical credential-free HTTPS URLs.");
        return uri.AbsoluteUri;
    }

    private static bool IsValidHost(string host) =>
        host.Length is >= 3 and <= 253 &&
        !HasControl(host) &&
        Uri.CheckHostName(host) == UriHostNameType.Dns &&
        host == host.ToLowerInvariant() &&
        host != "localhost" && !host.EndsWith(".local", StringComparison.Ordinal) &&
        Regex.IsMatch(host, "^[a-z0-9](?:[-a-z0-9.]*[a-z0-9])$",
            RegexOptions.CultureInvariant);

    private static bool HasControl(string value) =>
        value.Any(char.IsControl);
}

public sealed class FundingSourceAcquisitionPolicyDataException(
    string operation,
    int databaseErrorNumber,
    Exception? innerException = null) : Exception(
        $"Funding-source policy data operation '{operation}' failed with database error {databaseErrorNumber}.",
        innerException)
{
    public string Operation { get; } = operation;
    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}
