using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Core.ProjectAssets;

namespace FundingPlatform.Infrastructure.ProjectAssets.Storage;

public sealed class ProjectAssetTrustedContentPromoter(
    IProjectAssetBlobStore blobStore) : IProjectAssetTrustedContentPromoter
{
    public async Task<ProjectAssetTrustedContentPromotion> PromoteAsync(
        ProjectAssetKind kind,
        ProtectedProjectAssetBlobLocation quarantineLocation,
        string quarantineETag,
        ProtectedProjectAssetBlobLocation trustedLocation,
        string contentType,
        long expectedLength,
        byte[] expectedContentHash,
        CancellationToken cancellationToken)
    {
        if (kind == ProjectAssetKind.Image)
        {
            // Images cannot enter the trusted container until a decoder/re-encoder
            // strips metadata and rejects malformed payloads. Header inspection alone
            // is deliberately insufficient.
            return new ProjectAssetTrustedContentPromotion(
                false, "image-sanitization-unavailable");
        }
        if (kind != ProjectAssetKind.Document ||
            !string.Equals(contentType, "application/pdf", StringComparison.OrdinalIgnoreCase))
        {
            return new ProjectAssetTrustedContentPromotion(
                false, "trusted-promotion-not-supported");
        }

        var receipt = await blobStore.EnsureCopyAsync(
            quarantineLocation,
            quarantineETag,
            trustedLocation,
            "application/pdf",
            expectedLength,
            expectedContentHash,
            cancellationToken);
        return new ProjectAssetTrustedContentPromotion(true, "promoted", receipt);
    }
}
