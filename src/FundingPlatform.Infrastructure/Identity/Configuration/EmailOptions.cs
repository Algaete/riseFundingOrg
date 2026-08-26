namespace FundingPlatform.Infrastructure.Identity.Configuration;

public sealed class EmailOptions
{
    public const string SectionName = "Email";

    public bool Enabled { get; set; } = true;

    public string Endpoint { get; set; } = string.Empty;

    public string FromAddress { get; set; } = string.Empty;

    public string FrontendBaseUrl { get; set; } = string.Empty;

    public static bool IsValid(EmailOptions options)
    {
        if (!options.Enabled)
        {
            return Uri.TryCreate(options.FrontendBaseUrl, UriKind.Absolute, out var disabledFrontend) &&
                   (disabledFrontend.Scheme == Uri.UriSchemeHttps ||
                    (disabledFrontend.Scheme == Uri.UriSchemeHttp && disabledFrontend.IsLoopback));
        }

        return Uri.TryCreate(options.Endpoint, UriKind.Absolute, out var endpoint) &&
               endpoint.Scheme == Uri.UriSchemeHttps &&
               Uri.TryCreate(options.FrontendBaseUrl, UriKind.Absolute, out var enabledFrontend) &&
               (enabledFrontend.Scheme == Uri.UriSchemeHttps ||
                (enabledFrontend.Scheme == Uri.UriSchemeHttp && enabledFrontend.IsLoopback)) &&
               !string.IsNullOrWhiteSpace(options.FromAddress) &&
               options.FromAddress.Contains('@', StringComparison.Ordinal);
    }
}
