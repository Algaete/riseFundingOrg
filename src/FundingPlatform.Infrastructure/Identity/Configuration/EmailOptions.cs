namespace FundingPlatform.Infrastructure.Identity.Configuration;

public sealed class EmailOptions
{
    public const string SectionName = "Email";

    public string Endpoint { get; set; } = string.Empty;

    public string FromAddress { get; set; } = string.Empty;

    public string FrontendBaseUrl { get; set; } = string.Empty;

    public static bool IsValid(EmailOptions options)
    {
        return Uri.TryCreate(options.Endpoint, UriKind.Absolute, out var endpoint) &&
               endpoint.Scheme == Uri.UriSchemeHttps &&
               Uri.TryCreate(options.FrontendBaseUrl, UriKind.Absolute, out _) &&
               !string.IsNullOrWhiteSpace(options.FromAddress) &&
               options.FromAddress.Contains('@', StringComparison.Ordinal);
    }
}
