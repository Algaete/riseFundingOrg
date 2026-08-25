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

public sealed class SemanticWorkerOptionsValidator(IHostEnvironment environment)
    : IValidateOptions<SemanticOptions>
{
    public ValidateOptionsResult Validate(string? name, SemanticOptions options)
    {
        var contract = new SemanticOptionsValidator().Validate(name, options);
        if (contract.Failed) return contract;

        var local = environment.IsDevelopment() || environment.IsEnvironment("Testing");
        return options.Enabled && !local
            ? ValidateOptionsResult.Fail(
                "Phase 9B-A has no approved hosted semantic provider; the deterministic adapter is restricted to Development and Testing.")
            : ValidateOptionsResult.Success;
    }
}
