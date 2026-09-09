using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Core.ProjectAssets;

namespace FundingPlatform.UnitTests;

public sealed class ProjectAssetTrustedContentRulesTests
{
    private const long MaximumTrustedLength = 10_000_000;
    private const int MaximumImagePixels = 25_000_000;

    private static readonly byte[] SourceHash =
        Convert.FromHexString("000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F");

    [Fact]
    public void Pdf_is_valid_only_when_trusted_content_is_an_exact_copy()
    {
        var manifest = PdfManifest(
            contentLength: 4_096,
            contentHash: SourceHash);

        var valid = ProjectAssetTrustedContentRules.IsValid(
            ProjectAssetKind.Document,
            manifest,
            sourceMimeType: "application/pdf",
            sourceContentLength: 4_096,
            sourceContentHash: SourceHash,
            maximumTrustedLength: MaximumTrustedLength,
            maximumImagePixels: MaximumImagePixels);

        Assert.True(valid);
    }

    [Fact]
    public void Pdf_rejects_a_different_hash_length_or_mime_type()
    {
        var manifest = PdfManifest(
            contentLength: 4_096,
            contentHash: SourceHash);
        var differentHash = (byte[])SourceHash.Clone();
        differentHash[0] ^= 0xFF;

        Assert.False(IsValidPdf(
            manifest with { ContentHash = differentHash },
            sourceContentLength: 4_096,
            sourceMimeType: "application/pdf"));
        Assert.False(IsValidPdf(
            manifest with { ContentLength = 4_095 },
            sourceContentLength: 4_096,
            sourceMimeType: "application/pdf"));
        Assert.False(IsValidPdf(
            manifest,
            sourceContentLength: 4_096,
            sourceMimeType: "application/octet-stream"));
    }

    [Fact]
    public void Sanitized_image_is_valid_with_its_derived_hash_and_length()
    {
        var trustedHash =
            Convert.FromHexString("FFEEDDCCBBAA99887766554433221100FFEEDDCCBBAA99887766554433221100");
        var manifest = ImageManifest(
            mimeType: "image/png",
            contentLength: 2_048,
            contentHash: trustedHash,
            pixelWidth: 1_920,
            pixelHeight: 1_080);

        var valid = ProjectAssetTrustedContentRules.IsValid(
            ProjectAssetKind.Image,
            manifest,
            sourceMimeType: "image/png",
            sourceContentLength: 4_096,
            sourceContentHash: SourceHash,
            maximumTrustedLength: MaximumTrustedLength,
            maximumImagePixels: MaximumImagePixels);

        Assert.True(valid);
    }

    [Theory]
    [InlineData(32_769, 1)]
    [InlineData(1, 32_769)]
    public void Image_rejects_an_axis_above_the_dimension_limit_even_with_few_pixels(
        int pixelWidth,
        int pixelHeight)
    {
        var manifest = ImageManifest(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight);

        Assert.False(IsValidImage(
            manifest,
            maximumImagePixels: MaximumImagePixels));
    }

    [Fact]
    public void Image_rejects_the_absolute_twenty_five_million_pixel_limit()
    {
        var manifest = ImageManifest(
            pixelWidth: 5_001,
            pixelHeight: 5_000);

        Assert.False(IsValidImage(
            manifest,
            maximumImagePixels: int.MaxValue));
    }

    [Fact]
    public void Image_rejects_the_configured_pixel_limit()
    {
        var manifest = ImageManifest(
            pixelWidth: 100,
            pixelHeight: 100);

        Assert.False(IsValidImage(
            manifest,
            maximumImagePixels: 9_999));
    }

    [Theory]
    [InlineData("image/gif", ProjectAssetTrustedContentRules.ImageProcessingVersion)]
    [InlineData("image/png", "skia-image-v0")]
    [InlineData("IMAGE/PNG", ProjectAssetTrustedContentRules.ImageProcessingVersion)]
    public void Image_rejects_an_invalid_mime_type_or_processing_version(
        string mimeType,
        string processingVersion)
    {
        var manifest = ImageManifest(
            mimeType: mimeType,
            processingVersion: processingVersion);

        Assert.False(ProjectAssetTrustedContentRules.IsValid(
            ProjectAssetKind.Image,
            manifest,
            sourceMimeType: mimeType,
            sourceContentLength: 4_096,
            sourceContentHash: SourceHash,
            maximumTrustedLength: MaximumTrustedLength,
            maximumImagePixels: MaximumImagePixels));
    }

    [Fact]
    public void Pdf_rejects_an_invalid_processing_version()
    {
        var manifest = PdfManifest(
            contentLength: 4_096,
            contentHash: SourceHash) with
        {
            ProcessingVersion = "pdf-copy-v0"
        };

        Assert.False(IsValidPdf(
            manifest,
            sourceContentLength: 4_096,
            sourceMimeType: "application/pdf"));
    }

    private static bool IsValidPdf(
        ProjectAssetTrustedContentManifest manifest,
        long sourceContentLength,
        string sourceMimeType)
    {
        return ProjectAssetTrustedContentRules.IsValid(
            ProjectAssetKind.Document,
            manifest,
            sourceMimeType,
            sourceContentLength,
            SourceHash,
            MaximumTrustedLength,
            MaximumImagePixels);
    }

    private static bool IsValidImage(
        ProjectAssetTrustedContentManifest manifest,
        int maximumImagePixels)
    {
        return ProjectAssetTrustedContentRules.IsValid(
            ProjectAssetKind.Image,
            manifest,
            manifest.MimeType,
            sourceContentLength: 4_096,
            sourceContentHash: SourceHash,
            maximumTrustedLength: MaximumTrustedLength,
            maximumImagePixels: maximumImagePixels);
    }

    private static ProjectAssetTrustedContentManifest PdfManifest(
        long contentLength,
        byte[] contentHash)
    {
        return new ProjectAssetTrustedContentManifest(
            MimeType: "application/pdf",
            ContentLength: contentLength,
            ContentHash: contentHash,
            PixelWidth: null,
            PixelHeight: null,
            ProcessingVersion: ProjectAssetTrustedContentRules.PdfProcessingVersion);
    }

    private static ProjectAssetTrustedContentManifest ImageManifest(
        string mimeType = "image/png",
        long contentLength = 2_048,
        byte[]? contentHash = null,
        int pixelWidth = 640,
        int pixelHeight = 480,
        string processingVersion = ProjectAssetTrustedContentRules.ImageProcessingVersion)
    {
        return new ProjectAssetTrustedContentManifest(
            MimeType: mimeType,
            ContentLength: contentLength,
            ContentHash: contentHash ?? SourceHash,
            PixelWidth: pixelWidth,
            PixelHeight: pixelHeight,
            ProcessingVersion: processingVersion);
    }
}
