using FundingPlatform.Application.ProjectAssets;
using SkiaSharp;

namespace FundingPlatform.ImageProcessing.ProjectAssets;

/// <summary>
/// Exercises both native encoding and decoding. This catches missing native
/// assets as well as ABI mismatches before a Defender event is acknowledged.
/// </summary>
public sealed class ProjectAssetImageSanitizationProbe : IProjectAssetImageSanitizationProbe
{
    public bool IsAvailable()
    {
        try
        {
            using var colorSpace = SKColorSpace.CreateSrgb();
            using var bitmap = new SKBitmap(new SKImageInfo(
                1,
                1,
                SKColorType.Rgba8888,
                SKAlphaType.Unpremul,
                colorSpace));
            if (bitmap.GetPixels() == IntPtr.Zero)
                return false;
            bitmap.SetPixel(0, 0, new SKColor(23, 47, 89, 211));

            using var pixels = bitmap.PeekPixels();
            using var encoded = pixels?.Encode(
                new SKPngEncoderOptions(SKPngEncoderFilterFlags.AllFilters, 9));
            if (encoded is null || encoded.Size == 0)
                return false;

            using var codec = SKCodec.Create(encoded);
            if (codec is null || codec.Info.Width != 1 || codec.Info.Height != 1)
                return false;
            using var decoded = new SKBitmap(new SKImageInfo(
                1,
                1,
                SKColorType.Rgba8888,
                SKAlphaType.Unpremul,
                colorSpace));
            return decoded.GetPixels() != IntPtr.Zero &&
                   codec.GetPixels(decoded.Info, decoded.GetPixels()) == SKCodecResult.Success;
        }
        catch
        {
            return false;
        }
    }
}
