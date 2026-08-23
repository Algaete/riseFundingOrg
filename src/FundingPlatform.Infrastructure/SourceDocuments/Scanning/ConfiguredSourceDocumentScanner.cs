using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Core.SourceDocuments;
using FundingPlatform.Infrastructure.SourceDocuments.Configuration;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Infrastructure.SourceDocuments.Scanning;

public sealed class ConfiguredSourceDocumentScanner(
    IOptions<SourceDocumentOptions> options,
    TimeProvider timeProvider) : ISourceDocumentScanner
{
    public Task<SourceDocumentScanObservation> ObserveAsync(
        Guid sourceDocumentPublicId,
        short scanAttemptCount,
        ProtectedBlobLocation quarantineLocation,
        string quarantineETag,
        CancellationToken cancellationToken)
    {
        var current = options.Value;
        if (string.Equals(current.ScanMode, "DevelopmentFake", StringComparison.OrdinalIgnoreCase))
        {
            var fakeStatus = Enum.Parse<SourceDocumentScanStatus>(
                current.DevelopmentFakeResult, ignoreCase: true);
            return Task.FromResult(new SourceDocumentScanObservation(
                fakeStatus,
                fakeStatus switch
                {
                    SourceDocumentScanStatus.Clean => "development-fake-clean",
                    SourceDocumentScanStatus.Malicious => "development-fake-malicious",
                    SourceDocumentScanStatus.TimedOut => "development-fake-timeout",
                    _ => "development-fake-failed"
                },
                $"development-fake-{scanAttemptCount}-{fakeStatus}",
                timeProvider.GetUtcNow()));
        }

        // FASE 6 is deliberately fail-closed in production. Defender events are not
        // trusted from mutable blob tags; the Entra-authenticated Event Grid receiver
        // and ETag/hash revalidation arrive in FASE 7.
        return Task.FromResult(new SourceDocumentScanObservation(
            SourceDocumentScanStatus.Pending,
            "defender-eventgrid-required",
            $"defender-eventgrid-required-{scanAttemptCount}",
            timeProvider.GetUtcNow()));
    }
}
