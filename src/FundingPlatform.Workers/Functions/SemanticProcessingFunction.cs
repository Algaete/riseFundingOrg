using FundingPlatform.Application.Semantics;
using FundingPlatform.Infrastructure.Configuration;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Workers.Functions;

public sealed class SemanticProcessingFunction(
    SemanticProcessingService service,
    IOptions<SemanticOptions> options,
    ILogger<SemanticProcessingFunction> logger)
{
    [Function(nameof(SemanticProcessingFunction))]
    public async Task RunAsync(
        [TimerTrigger("15 */1 * * * *")] TimerInfo timer,
        CancellationToken cancellationToken)
    {
        if (!options.Value.Enabled) return;
        var embeddings = await service.ProcessEmbeddingsAsync(cancellationToken);
        var evaluations = await service.ProcessShadowEvaluationsAsync(cancellationToken);
        logger.LogInformation(
            "Semantic shadow cycle completed: embedding claimed={EmbeddingClaimed}, completed={EmbeddingCompleted}, failed={EmbeddingFailed}, deferred={EmbeddingDeferred}, skipped={EmbeddingSkipped}; evaluation claimed={EvaluationClaimed}, completed={EvaluationCompleted}, failed={EvaluationFailed}, deferred={EvaluationDeferred}.",
            embeddings.ClaimedCount,
            embeddings.CompletedCount,
            embeddings.FailedCount,
            embeddings.DeferredCount,
            embeddings.SkippedCount,
            evaluations.ClaimedCount,
            evaluations.CompletedCount,
            evaluations.FailedCount,
            evaluations.DeferredCount);
    }
}
