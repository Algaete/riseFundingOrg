namespace FundingPlatform.Application.Semantics;

public sealed record SemanticProcessingPolicy(
    bool Enabled,
    bool ShadowOnly,
    int Dimensions,
    int BatchSize,
    TimeSpan LeaseDuration,
    TimeSpan ItemTimeout,
    int MaximumAttempts,
    int MaximumInputUtf8Bytes,
    string PurposeCode,
    string ProjectTemplateVersion,
    string OpportunityTemplateVersion,
    string NormalizationVersion,
    string CalibrationVersion)
{
    public const int RequiredDimensions = 1536;
    public const int MaximumBatchSize = 64;
    public const int RequiredMaximumAttempts = 3;
    public const int RequiredMaximumInputUtf8Bytes = 8192;

    public void Validate()
    {
        if (!ShadowOnly || Dimensions != RequiredDimensions ||
            BatchSize is < 1 or > MaximumBatchSize ||
            LeaseDuration < TimeSpan.FromSeconds(60) ||
            LeaseDuration > TimeSpan.FromMinutes(30) ||
            ItemTimeout <= TimeSpan.Zero || ItemTimeout > TimeSpan.FromSeconds(30) ||
            MaximumAttempts != RequiredMaximumAttempts ||
            MaximumInputUtf8Bytes != RequiredMaximumInputUtf8Bytes ||
            PurposeCode != "matching" ||
            ProjectTemplateVersion != "project-semantic-v1" ||
            OpportunityTemplateVersion != "opportunity-semantic-v1" ||
            NormalizationVersion != "semantic-text-v1" ||
            CalibrationVersion != "cosine-linear-shadow-v1")
        {
            throw new InvalidOperationException(
                "Semantic processing policy is outside the Phase 9B-A shadow contract.");
        }

        // Jobs are claimed just in time and processed serially. A single lease must
        // still cover input loading, the provider timeout, an idempotent completion
        // replay and bounded persistence overhead.
        var minimumSafeLease = ItemTimeout.Add(TimeSpan.FromMinutes(3));
        if (LeaseDuration < minimumSafeLease)
        {
            throw new InvalidOperationException(
                "Semantic lease duration is too short for the configured serial batch.");
        }
    }
}
