using System.Security.Cryptography;
using FundingPlatform.Core.ProjectAssets;

namespace FundingPlatform.Application.ProjectAssets;

/// <summary>
/// Defines the durable trusted-content contract shared by synchronous scans,
/// Defender processing and the image-processing implementation.
/// </summary>
public static class ProjectAssetTrustedContentRules
{
    public const string ImageProcessingVersion = "skia-4.151.2-image-v1";
    public const string PdfProcessingVersion = "pdf-copy-v1";
    public const int MaximumImageDimension = 32_768;
    public const long AbsoluteMaximumImagePixels = 25_000_000;

    public static bool IsValid(
        ProjectAssetKind kind,
        ProjectAssetTrustedContentManifest manifest,
        string sourceMimeType,
        long sourceContentLength,
        byte[] sourceContentHash,
        long maximumTrustedLength,
        int maximumImagePixels)
    {
        ArgumentNullException.ThrowIfNull(manifest);

        if (sourceContentLength < 1 || sourceContentLength > maximumTrustedLength ||
            sourceContentHash is not { Length: 32 } ||
            manifest.ContentLength < 1 ||
            manifest.ContentLength > maximumTrustedLength ||
            manifest.ContentHash is not { Length: 32 } ||
            !string.Equals(
                manifest.MimeType, sourceMimeType, StringComparison.OrdinalIgnoreCase))
            return false;

        if (kind == ProjectAssetKind.Document)
        {
            return string.Equals(
                       manifest.MimeType, "application/pdf", StringComparison.Ordinal) &&
                   manifest.ContentLength == sourceContentLength &&
                   CryptographicOperations.FixedTimeEquals(
                       manifest.ContentHash, sourceContentHash) &&
                   manifest.PixelWidth is null && manifest.PixelHeight is null &&
                   string.Equals(
                       manifest.ProcessingVersion,
                       PdfProcessingVersion,
                       StringComparison.Ordinal);
        }

        if (kind != ProjectAssetKind.Image ||
            manifest.MimeType is not ("image/jpeg" or "image/png" or "image/webp") ||
            manifest.PixelWidth is not > 0 || manifest.PixelHeight is not > 0 ||
            manifest.PixelWidth > MaximumImageDimension ||
            manifest.PixelHeight > MaximumImageDimension ||
            maximumImagePixels < 1)
            return false;

        var effectiveMaximumPixels = Math.Min(
            (long)maximumImagePixels,
            AbsoluteMaximumImagePixels);
        return checked((long)manifest.PixelWidth.Value * manifest.PixelHeight.Value) <=
                   effectiveMaximumPixels &&
               string.Equals(
                   manifest.ProcessingVersion,
                   ImageProcessingVersion,
                   StringComparison.Ordinal);
    }
}
