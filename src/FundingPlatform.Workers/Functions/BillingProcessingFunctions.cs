using FundingPlatform.Application.Billing;
using FundingPlatform.Infrastructure.Configuration;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Workers.Functions;

public sealed class BillingWebhookProcessingFunction(
    BillingProcessingService service,
    IOptions<BillingOptions> options,
    ILogger<BillingWebhookProcessingFunction> logger)
{
    [Function(nameof(BillingWebhookProcessingFunction))]
    public async Task RunAsync([TimerTrigger("20 */2 * * * *")] TimerInfo timer,
        CancellationToken cancellationToken)
    {
        if (!options.Value.Enabled) return;
        var cycle = await service.ProcessWebhooksAsync(options.Value.WebhookBatchSize,
            options.Value.WebhookLeaseSeconds, cancellationToken);
        logger.LogInformation(
            "Sandbox billing webhook cycle completed: claimed={Claimed}, completed={Completed}, retried={Retried}, failed={Failed}.",
            cycle.Claimed, cycle.Completed, cycle.Retried, cycle.Failed);
    }
}

public sealed class BillingReconciliationFunction(
    BillingProcessingService service,
    IOptions<BillingOptions> options,
    ILogger<BillingReconciliationFunction> logger)
{
    [Function(nameof(BillingReconciliationFunction))]
    public async Task RunAsync([TimerTrigger("40 */10 * * * *")] TimerInfo timer,
        CancellationToken cancellationToken)
    {
        if (!options.Value.Enabled) return;
        var completed = await service.ReconcileAsync(options.Value.ReconciliationBatchSize,
            cancellationToken);
        logger.LogInformation("Sandbox billing reconciliation cycle completed: reconciled={Reconciled}.",
            completed);
    }
}
