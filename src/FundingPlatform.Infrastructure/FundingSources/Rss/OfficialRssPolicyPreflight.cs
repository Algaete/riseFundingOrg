using FundingPlatform.Application.FundingOpportunities;

namespace FundingPlatform.Infrastructure.FundingSources.Rss;

public static class OfficialRssPolicyPreflight
{
    public static void ValidateEnabledPolicy(
        FundingSourceAcquisitionPolicyCommand command,
        OfficialRssOptions options)
    {
        ArgumentNullException.ThrowIfNull(command);
        ArgumentNullException.ThrowIfNull(options);
        if (!string.Equals(command.ProviderCode.Trim(),
                OfficialRssFundingSourceProvider.Code, StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException(
                "The local operator command currently supports only the official-rss provider.");
        if (!command.IsEnabled) return;
        if (!options.Enabled || !OfficialRssOptions.IsValid(options))
            throw new InvalidOperationException(
                "OfficialRss runtime configuration must be complete and enabled before the database policy is enabled.");

        var feed = new Uri(options.FeedUri, UriKind.Absolute).AbsoluteUri;
        var license = new Uri(options.LicenseUri, UriKind.Absolute).AbsoluteUri;
        var robots = new Uri(new Uri(options.FeedUri, UriKind.Absolute), "/robots.txt")
            .AbsoluteUri;
        var commandHosts = command.AllowedHosts
            .Select(static host => host.Trim().ToLowerInvariant())
            .Order(StringComparer.Ordinal)
            .ToArray();
        var configuredHosts = options.GetAllowedHosts()
            .Select(static host => host.ToLowerInvariant())
            .Order(StringComparer.Ordinal)
            .ToArray();
        var expectedRate = (60 + options.MinimumDelaySeconds - 1) /
            options.MinimumDelaySeconds;

        if (!SameAbsoluteUri(command.BaseUrl, feed) ||
            !SameAbsoluteUri(command.LicenseUrl, license) ||
            !string.Equals(command.LicenseName.Trim(), options.LicenseName.Trim(),
                StringComparison.Ordinal) ||
            !string.Equals(command.RobotsPolicyCode.Trim(), "enforce",
                StringComparison.OrdinalIgnoreCase) ||
            command.RobotsPolicyVersion != options.RobotsPolicyVersion ||
            !command.AllowedEndpoints.Any(endpoint =>
                endpoint.Kind == FundingSourceAcquisitionEndpointKind.Robots &&
                SameAbsoluteUri(endpoint.CanonicalUri, robots)) ||
            !commandHosts.SequenceEqual(configuredHosts, StringComparer.Ordinal) ||
            command.MaximumResponseBytes != options.MaximumBytes ||
            command.RequestRateLimitPerMinute != expectedRate ||
            !command.ComplianceApproved || !options.ComplianceApproved)
            throw new InvalidOperationException(
                "The requested database policy does not exactly match the enabled OfficialRss runtime boundary.");
    }

    private static bool SameAbsoluteUri(string? candidate, string expected) =>
        Uri.TryCreate(candidate, UriKind.Absolute, out var parsed) &&
        string.Equals(parsed.AbsoluteUri, expected, StringComparison.Ordinal);
}
