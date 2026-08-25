using FundingPlatform.Application.Semantics;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Infrastructure.Configuration;

public sealed class SemanticOptions
{
    public const string SectionName = "Semantic";

    public bool Enabled { get; set; }
    public bool ShadowOnly { get; set; } = true;
    public int Dimensions { get; set; } = SemanticProcessingPolicy.RequiredDimensions;
    public int BatchSize { get; set; } = 8;
    public int LeaseSeconds { get; set; } = 300;
    public int TimeoutSeconds { get; set; } = 30;
    public int MaximumAttempts { get; set; } = 3;
    public int MaximumInputUtf8Bytes { get; set; } = 8192;
    public string PurposeCode { get; set; } = "matching";
    public string ProjectTemplateVersion { get; set; } = "project-semantic-v1";
    public string OpportunityTemplateVersion { get; set; } = "opportunity-semantic-v1";
    public string NormalizationVersion { get; set; } = "semantic-text-v1";
    public string CalibrationVersion { get; set; } = "cosine-linear-shadow-v1";

    public SemanticProcessingPolicy ToPolicy() => new(
        Enabled,
        ShadowOnly,
        Dimensions,
        BatchSize,
        TimeSpan.FromSeconds(LeaseSeconds),
        TimeSpan.FromSeconds(TimeoutSeconds),
        MaximumAttempts,
        MaximumInputUtf8Bytes,
        PurposeCode,
        ProjectTemplateVersion,
        OpportunityTemplateVersion,
        NormalizationVersion,
        CalibrationVersion);
}

public sealed class SemanticOptionsValidator : IValidateOptions<SemanticOptions>
{
    public ValidateOptionsResult Validate(string? name, SemanticOptions options)
    {
        try
        {
            options.ToPolicy().Validate();
        }
        catch (InvalidOperationException exception)
        {
            return ValidateOptionsResult.Fail(exception.Message);
        }

        return ValidateOptionsResult.Success;
    }
}

public sealed class SemanticWorkerOptionsValidator(
    IHostEnvironment environment,
    IOptions<OpenAiProviderOptions> openAiOptions)
    : IValidateOptions<SemanticOptions>
{
    public ValidateOptionsResult Validate(string? name, SemanticOptions options)
    {
        var contract = new SemanticOptionsValidator().Validate(name, options);
        if (contract.Failed) return contract;

        var local = environment.IsDevelopment() || environment.IsEnvironment("Testing");
        if (!options.Enabled || local) return ValidateOptionsResult.Success;
        var openAi = openAiOptions.Value;
        return openAi.Enabled && openAi.EmbeddingsEnabled
            ? ValidateOptionsResult.Success
            : ValidateOptionsResult.Fail(
                "Hosted semantic processing requires the governed OpenAI embedding adapter; the deterministic adapter remains local-only.");
    }
}

public sealed class AiExplanationOptions
{
    public const string SectionName = "AiExplanations";

    public bool Enabled { get; set; }
    public int BatchSize { get; set; } = 1;
    public int LeaseSeconds { get; set; } = 600;
    public int TimeoutSeconds { get; set; } = 60;

    public AiExplanationProcessingPolicy ToPolicy() => new(
        Enabled,
        BatchSize,
        TimeSpan.FromSeconds(LeaseSeconds),
        TimeSpan.FromSeconds(TimeoutSeconds));
}

public sealed class AiExplanationOptionsValidator : IValidateOptions<AiExplanationOptions>
{
    public ValidateOptionsResult Validate(string? name, AiExplanationOptions options)
    {
        try
        {
            options.ToPolicy().Validate();
        }
        catch (InvalidOperationException exception)
        {
            return ValidateOptionsResult.Fail(exception.Message);
        }

        return ValidateOptionsResult.Success;
    }
}

public sealed class AiExplanationWorkerOptionsValidator(
    IOptions<OpenAiProviderOptions> openAiOptions)
    : IValidateOptions<AiExplanationOptions>
{
    public ValidateOptionsResult Validate(string? name, AiExplanationOptions options)
    {
        var contract = new AiExplanationOptionsValidator().Validate(name, options);
        if (contract.Failed || !options.Enabled) return contract;
        var openAi = openAiOptions.Value;
        return openAi.Enabled && openAi.StructuredOutputsEnabled
            ? ValidateOptionsResult.Success
            : ValidateOptionsResult.Fail(
                "Structured explanations require the governed OpenAI Structured Outputs adapter.");
    }
}
