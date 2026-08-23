namespace FundingPlatform.Infrastructure.Identity.Configuration;

public sealed class AzureSecurityOptions
{
    public const string SectionName = "AzureSecurity";

    public string KeyVaultUri { get; set; } = string.Empty;

    public string DataProtectionBlobUri { get; set; } = string.Empty;

    public string DataProtectionKeyUri { get; set; } = string.Empty;

    public static bool IsValid(AzureSecurityOptions options)
    {
        return IsHttpsUri(options.KeyVaultUri) &&
               IsHttpsUri(options.DataProtectionBlobUri) &&
               IsHttpsUri(options.DataProtectionKeyUri);
    }

    private static bool IsHttpsUri(string value)
    {
        return Uri.TryCreate(value, UriKind.Absolute, out var uri) &&
               string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase);
    }
}
