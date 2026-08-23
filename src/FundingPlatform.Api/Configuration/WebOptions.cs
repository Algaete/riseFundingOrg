namespace FundingPlatform.Api.Configuration;

public sealed class WebOptions
{
    public const string SectionName = "Web";

    public const string ValidationMessage =
        "Web:FrontendBaseUrl and Web:AllowedCorsOrigins must contain explicit HTTP(S) origins.";

    public string FrontendBaseUrl { get; set; } = string.Empty;

    public string[] AllowedCorsOrigins { get; set; } = [];

    public static bool IsValid(WebOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);

        return IsHttpOrigin(options.FrontendBaseUrl)
            && options.AllowedCorsOrigins.Length > 0
            && options.AllowedCorsOrigins.All(IsHttpOrigin)
            && options.AllowedCorsOrigins.Distinct(StringComparer.OrdinalIgnoreCase).Count()
                == options.AllowedCorsOrigins.Length;
    }

    private static bool IsHttpOrigin(string value)
    {
        return Uri.TryCreate(value, UriKind.Absolute, out var uri)
            && (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps)
            && string.IsNullOrEmpty(uri.UserInfo)
            && uri.AbsolutePath == "/"
            && string.IsNullOrEmpty(uri.Query)
            && string.IsNullOrEmpty(uri.Fragment);
    }
}
