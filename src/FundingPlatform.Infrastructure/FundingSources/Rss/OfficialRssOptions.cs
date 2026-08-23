using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Infrastructure.FundingSources.Rss;

public sealed class OfficialRssOptions
{
    public const string SectionName = "OfficialRss";

    public bool Enabled { get; set; }
    public string FeedUri { get; set; } = string.Empty;
    public string AllowedHosts { get; set; } = string.Empty;
    public string SourceName { get; set; } = string.Empty;
    public string SponsorName { get; set; } = string.Empty;
    public string LicenseName { get; set; } = string.Empty;
    public string LicenseUri { get; set; } = string.Empty;
    public bool ComplianceApproved { get; set; }
    public string RobotsPolicy { get; set; } = "Enforce";
    public int RobotsPolicyVersion { get; set; } = 1;
    public int MinimumDelaySeconds { get; set; } = 2;
    public int TimeoutSeconds { get; set; } = 15;
    public int MaximumBytes { get; set; } = 1_048_576;
    public int MaximumCharacters { get; set; } = 1_000_000;
    public int MaximumItems { get; set; } = 25;
    public string UserAgent { get; set; } = string.Empty;

    public IReadOnlySet<string> GetAllowedHosts() => AllowedHosts
        .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        .Select(host => host.ToLowerInvariant())
        .ToHashSet(StringComparer.OrdinalIgnoreCase);

    public static bool IsValid(OfficialRssOptions options)
    {
        if (!options.Enabled) return true;
        if (!TryHttpsUri(options.FeedUri, out var feed) ||
            !TryHttpsUri(options.LicenseUri, out _) ||
            !options.ComplianceApproved ||
            string.IsNullOrWhiteSpace(options.SourceName) || options.SourceName.Length > 150 ||
            string.IsNullOrWhiteSpace(options.SponsorName) || options.SponsorName.Length > 300 ||
            string.IsNullOrWhiteSpace(options.LicenseName) || options.LicenseName.Length > 150 ||
            HasControl(options.SourceName) || HasControl(options.SponsorName) ||
            HasControl(options.LicenseName) || HasControl(options.AllowedHosts) ||
            options.MinimumDelaySeconds is < 1 or > 60 ||
            options.TimeoutSeconds is < 5 or > 20 ||
            options.MaximumBytes is < 4_096 or > 1_048_576 ||
            options.MaximumCharacters is < 4_096 or > 1_000_000 ||
            options.MaximumItems is < 1 or > 25 ||
            options.UserAgent.Length is < 12 or > 200 ||
            !options.UserAgent.Contains('/', StringComparison.Ordinal) ||
            options.UserAgent.Contains('\r') || options.UserAgent.Contains('\n') ||
            options.RobotsPolicy != "Enforce" ||
            options.RobotsPolicyVersion is < 1 or > 1_000)
            return false;
        var hosts = options.GetAllowedHosts();
        return hosts.Count is >= 1 and <= 5 && hosts.Contains(feed!.Host) &&
               hosts.All(IsDnsHost);
    }

    private static bool TryHttpsUri(string value, out Uri? uri)
    {
        uri = null;
        if (!Uri.TryCreate(value, UriKind.Absolute, out var parsed) ||
            parsed.Scheme != Uri.UriSchemeHttps || parsed.Port != 443 ||
            !string.IsNullOrEmpty(parsed.UserInfo) || !string.IsNullOrEmpty(parsed.Query) ||
            !string.IsNullOrEmpty(parsed.Fragment) || parsed.AbsolutePath == "/")
            return false;
        uri = parsed;
        return true;
    }

    private static bool IsDnsHost(string host) =>
        Uri.CheckHostName(host) == UriHostNameType.Dns &&
        !host.Equals("localhost", StringComparison.OrdinalIgnoreCase) &&
        !host.EndsWith(".local", StringComparison.OrdinalIgnoreCase);

    private static bool HasControl(string value) =>
        value.Contains('\r') || value.Contains('\n') || value.Contains('\0');
}

internal static class OfficialRssPolicyFingerprint
{
    public static byte[] Compute(OfficialRssOptions options, int policyVersion)
    {
        if (policyVersion < 1 || options.RobotsPolicyVersion is < 1 or > 1_000)
            throw new InvalidOperationException("The RSS acquisition policy version is invalid.");
        var endpointHash = Hash(new Uri(options.FeedUri, UriKind.Absolute).AbsoluteUri);
        var licenseHash = Hash(new Uri(options.LicenseUri, UriKind.Absolute).AbsoluteUri);
        var hostMaterial = string.Join('\n', options.GetAllowedHosts()
            .Select(static host => host.ToLowerInvariant())
            .Order(StringComparer.Ordinal));
        var hostHash = Hash(hostMaterial);
        var material = string.Join('|',
            "v1",
            OfficialRssFundingSourceProvider.Code,
            Convert.ToHexString(endpointHash),
            Convert.ToHexString(licenseHash),
            "enforce",
            options.RobotsPolicyVersion.ToString(
                System.Globalization.CultureInfo.InvariantCulture),
            Convert.ToHexString(hostHash),
            policyVersion.ToString(System.Globalization.CultureInfo.InvariantCulture));
        return Hash(material);
    }

    private static byte[] Hash(string value) =>
        SHA256.HashData(Encoding.UTF8.GetBytes(value));
}

public sealed class OfficialRssOptionsValidator : IValidateOptions<OfficialRssOptions>
{
    public ValidateOptionsResult Validate(string? name, OfficialRssOptions options) =>
        OfficialRssOptions.IsValid(options)
            ? ValidateOptionsResult.Success
            : ValidateOptionsResult.Fail(
                "OfficialRss must remain disabled unless its fixed HTTPS endpoint, license, compliance and limits are configured.");
}
