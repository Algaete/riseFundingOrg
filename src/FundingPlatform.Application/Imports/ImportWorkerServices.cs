using System.Text.Json;
using FundingPlatform.Core.Imports;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Core.SourceDocuments;

namespace FundingPlatform.Application.Imports;

public sealed class ImportSchedulerService(
    IImportRunRepository repository,
    TimeProvider timeProvider)
{
    public Task<IReadOnlyList<ScheduledImportRun>> RequeueStrandedAsync(
        int batchSize,
        CancellationToken cancellationToken)
    {
        ValidateBatchSize(batchSize);
        return repository.RequeueStrandedAsync(
            timeProvider.GetUtcNow(), batchSize, cancellationToken);
    }

    public Task<IReadOnlyList<ScheduledImportRun>> ScheduleDueAsync(
        int batchSize,
        CancellationToken cancellationToken)
    {
        ValidateBatchSize(batchSize);
        return repository.CreateDueScheduledAsync(
            timeProvider.GetUtcNow(), batchSize, cancellationToken);
    }

    private static void ValidateBatchSize(int batchSize)
    {
        if (batchSize is < 1 or > 100)
        {
            throw new ArgumentOutOfRangeException(
                nameof(batchSize), batchSize, "Batch size must be between 1 and 100.");
        }
    }
}

public sealed class ImportOutboxDispatcherService(
    IImportOutboxRepository outbox,
    IImportQueuePublisher queue,
    TimeProvider timeProvider,
    string workerInstanceId,
    TimeSpan leaseDuration,
    ISourceDocumentExtractionQueuePublisher? extractionQueue = null)
{
    public async Task<int> DispatchAsync(int batchSize, CancellationToken cancellationToken)
    {
        if (batchSize is < 1 or > 100)
        {
            throw new ArgumentOutOfRangeException(
                nameof(batchSize), batchSize, "Batch size must be between 1 and 100.");
        }

        var messages = await outbox.ClaimAsync(
            workerInstanceId,
            batchSize,
            leaseDuration,
            timeProvider.GetUtcNow(),
            cancellationToken);
        var dispatched = 0;

        foreach (var message in messages)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var isImport = string.Equals(
                message.MessageType, "ImportRunRequested", StringComparison.Ordinal);
            var isExtraction = string.Equals(
                message.MessageType, "SourceDocumentExtractionRequested", StringComparison.Ordinal);
            if ((!isImport && !isExtraction) ||
                (isImport && !ImportQueueMessageParser.TryParse(
                    message.PayloadJson, out _)) ||
                (isExtraction && (extractionQueue is null ||
                    !SourceDocumentExtractionQueueMessageParser.TryParse(
                        message.PayloadJson, out _))))
            {
                await outbox.ReleaseAsync(
                    message.MessageId,
                    workerInstanceId,
                    timeProvider.GetUtcNow().AddHours(1),
                    isExtraction
                        ? "invalid-document-extraction-outbox-message"
                        : "invalid-import-outbox-message",
                    cancellationToken);
                continue;
            }

            try
            {
                if (isImport)
                {
                    _ = ImportQueueMessageParser.TryParse(
                        message.PayloadJson, out var importMessage);
                    await queue.PublishAsync(importMessage, cancellationToken);
                }
                else
                {
                    _ = SourceDocumentExtractionQueueMessageParser.TryParse(
                        message.PayloadJson, out var extractionMessage);
                    await extractionQueue!.PublishAsync(
                        extractionMessage, cancellationToken);
                }
                await outbox.CompleteAsync(
                    message.MessageId,
                    workerInstanceId,
                    timeProvider.GetUtcNow(),
                    cancellationToken);
                dispatched++;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception)
            {
                var backoffSeconds = Math.Min(
                    900,
                    5 * (1 << Math.Min(message.AttemptCount, (short)7)));
                await outbox.ReleaseAsync(
                    message.MessageId,
                    workerInstanceId,
                    timeProvider.GetUtcNow().AddSeconds(backoffSeconds),
                    "queue-publish-failed",
                    cancellationToken);
            }
        }

        return dispatched;
    }
}

public static class SourceDocumentExtractionQueueMessageParser
{
    private static readonly HashSet<string> AllowedProperties = ["jobId", "version"];

    public static bool TryParse(
        string? payload,
        out SourceDocumentExtractionQueueMessage message)
    {
        message = default!;
        if (string.IsNullOrWhiteSpace(payload) || payload.Length > 512) return false;
        try
        {
            using var document = JsonDocument.Parse(payload, new JsonDocumentOptions
            {
                AllowTrailingCommas = false,
                CommentHandling = JsonCommentHandling.Disallow,
                MaxDepth = 4
            });
            if (document.RootElement.ValueKind != JsonValueKind.Object) return false;
            var properties = document.RootElement.EnumerateObject().ToArray();
            if (properties.Length != AllowedProperties.Count ||
                properties.Select(property => property.Name)
                    .Distinct(StringComparer.Ordinal).Count() != AllowedProperties.Count ||
                properties.Any(property => !AllowedProperties.Contains(property.Name)) ||
                !document.RootElement.TryGetProperty("jobId", out var idElement) ||
                !idElement.TryGetGuid(out var jobId) || jobId == Guid.Empty ||
                !document.RootElement.TryGetProperty("version", out var versionElement) ||
                !versionElement.TryGetInt32(out var version) || version != 1)
            {
                return false;
            }

            message = new SourceDocumentExtractionQueueMessage(jobId, version);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }
}

public static class ImportQueueMessageParser
{
    private static readonly HashSet<string> AllowedProperties =
        ["runId", "version"];

    public static bool TryParse(string? payload, out ImportRunQueueMessage message)
    {
        message = default!;
        if (string.IsNullOrWhiteSpace(payload) || payload.Length > 512)
        {
            return false;
        }

        try
        {
            using var document = JsonDocument.Parse(payload, new JsonDocumentOptions
            {
                AllowTrailingCommas = false,
                CommentHandling = JsonCommentHandling.Disallow,
                MaxDepth = 4
            });
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                return false;
            }

            var properties = document.RootElement.EnumerateObject().ToArray();
            if (properties.Length != AllowedProperties.Count ||
                properties.Select(property => property.Name).Distinct(StringComparer.Ordinal).Count() !=
                    AllowedProperties.Count ||
                properties.Any(property => !AllowedProperties.Contains(property.Name)) ||
                !document.RootElement.TryGetProperty("runId", out var runIdElement) ||
                !runIdElement.TryGetGuid(out var runId) ||
                runId == Guid.Empty ||
                !document.RootElement.TryGetProperty("version", out var versionElement) ||
                !versionElement.TryGetInt32(out var version) ||
                version != 1)
            {
                return false;
            }

            message = new ImportRunQueueMessage(runId, version);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }
}
