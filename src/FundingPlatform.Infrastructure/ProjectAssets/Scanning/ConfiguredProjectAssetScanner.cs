using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Core.ProjectAssets;
using FundingPlatform.Infrastructure.ProjectAssets.Configuration;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Infrastructure.ProjectAssets.Scanning;

public sealed class ConfiguredProjectAssetScanner(
    IOptions<ProjectAssetOptions> options,
    TimeProvider timeProvider) : IProjectAssetScanner
{
    public Task<ProjectAssetScanObservation> ObserveAsync(
        Guid assetPublicId,
        ProtectedProjectAssetBlobLocation quarantineLocation,
        string quarantineETag,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var value = options.Value;
        var status = string.Equals(
            value.ScanMode, "DevelopmentFake", StringComparison.OrdinalIgnoreCase)
            ? Enum.Parse<ProjectAssetScanStatus>(value.DevelopmentFakeResult, ignoreCase: true)
            : ProjectAssetScanStatus.Pending;
        var result = status == ProjectAssetScanStatus.Pending
            ? "defender-result-pending"
            : $"development-fake-{status.ToString().ToLowerInvariant()}";
        var observationHash = SHA256.HashData(Encoding.UTF8.GetBytes(
            $"{assetPublicId:D}\n{quarantineETag}\n{result}"));
        return Task.FromResult(new ProjectAssetScanObservation(
            status,
            result,
            $"project-asset-{Convert.ToHexString(observationHash).ToLowerInvariant()}",
            timeProvider.GetUtcNow()));
    }
}
