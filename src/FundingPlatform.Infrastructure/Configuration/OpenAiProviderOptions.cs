using Microsoft.Extensions.Options;

namespace FundingPlatform.Infrastructure.Configuration;

public sealed class OpenAiProviderOptions
{
    public const string SectionName = "OpenAI";
    public const string ProviderCode = "openai";
    public const string DefaultEndpointOrigin = "https://api.openai.com";

    private static readonly HashSet<string> AllowedHosts =
    [
        "api.openai.com", "us.api.openai.com", "eu.api.openai.com",
        "au.api.openai.com", "ca.api.openai.com", "jp.api.openai.com",
        "in.api.openai.com", "sg.api.openai.com", "kr.api.openai.com", "gb.api.openai.com",
        "ae.api.openai.com"
    ];

    public bool Enabled { get; set; }
    public bool EmbeddingsEnabled { get; set; }
    public bool StructuredOutputsEnabled { get; set; }
    public string EndpointOrigin { get; set; } = DefaultEndpointOrigin;
    public string ApiKey { get; set; } = string.Empty;
    public string? ProjectId { get; set; }
    public string RequiredEmbeddingGovernancePolicySha256 { get; set; } = string.Empty;
    public string RequiredStructuredOutputGovernancePolicySha256 { get; set; } = string.Empty;
    public int MaximumResponseBytes { get; set; } = 262_144;

    public Uri GetEndpointOrigin()
    {
        if (!Uri.TryCreate(EndpointOrigin, UriKind.Absolute, out var endpoint) ||
            endpoint.Scheme != Uri.UriSchemeHttps || endpoint.Port != 443 ||
            !AllowedHosts.Contains(endpoint.IdnHost) || endpoint.AbsolutePath != "/" ||
            !string.IsNullOrEmpty(endpoint.Query) || !string.IsNullOrEmpty(endpoint.Fragment) ||
            !string.IsNullOrEmpty(endpoint.UserInfo))
        {
            throw new InvalidOperationException(
                "OpenAI endpoint must be an allowlisted official HTTPS origin.");
        }

        return endpoint;
    }

    public byte[] GetRequiredEmbeddingGovernanceFingerprint() =>
        ParseFingerprint(
            RequiredEmbeddingGovernancePolicySha256,
            "OpenAI embedding governance policy SHA-256");

    public byte[] GetRequiredStructuredOutputGovernanceFingerprint() =>
        ParseFingerprint(
            RequiredStructuredOutputGovernancePolicySha256,
            "OpenAI Structured Outputs governance policy SHA-256");

    private static byte[] ParseFingerprint(string value, string label)
    {
        if (value.Length != 64 || !value.All(Uri.IsHexDigit))
        {
            throw new InvalidOperationException(
                $"{label} must contain exactly 64 hexadecimal characters.");
        }

        return Convert.FromHexString(value);
    }
}

public sealed class OpenAiProviderOptionsValidator : IValidateOptions<OpenAiProviderOptions>
{
    public ValidateOptionsResult Validate(string? name, OpenAiProviderOptions options)
    {
        try
        {
            _ = options.GetEndpointOrigin();
            if (options.MaximumResponseBytes is < 32_768 or > 1_048_576)
                throw new InvalidOperationException(
                    "OpenAI maximum response bytes must be between 32768 and 1048576.");
            if (!options.Enabled)
            {
                if (options.EmbeddingsEnabled || options.StructuredOutputsEnabled)
                    throw new InvalidOperationException(
                        "OpenAI capabilities cannot be enabled while the provider is disabled.");
                return ValidateOptionsResult.Success;
            }

            if (!options.EmbeddingsEnabled && !options.StructuredOutputsEnabled)
                throw new InvalidOperationException(
                    "At least one governed OpenAI capability must be enabled.");
            if (string.IsNullOrWhiteSpace(options.ApiKey) || options.ApiKey.Length is < 20 or > 512 ||
                options.ApiKey.Any(char.IsControl))
                throw new InvalidOperationException("A bounded OpenAI API key is required.");
            if (options.ProjectId is { } project &&
                (project.Length is < 3 or > 128 ||
                 project.Any(character => !char.IsAsciiLetterOrDigit(character) &&
                                          character is not '_' and not '-')))
                throw new InvalidOperationException("OpenAI project id has an invalid format.");
            if (options.EmbeddingsEnabled)
                _ = options.GetRequiredEmbeddingGovernanceFingerprint();
            if (options.StructuredOutputsEnabled)
                _ = options.GetRequiredStructuredOutputGovernanceFingerprint();
        }
        catch (InvalidOperationException exception)
        {
            return ValidateOptionsResult.Fail(exception.Message);
        }
        catch (FormatException)
        {
            return ValidateOptionsResult.Fail(
                "OpenAI governance policy SHA-256 is invalid.");
        }

        return ValidateOptionsResult.Success;
    }
}
