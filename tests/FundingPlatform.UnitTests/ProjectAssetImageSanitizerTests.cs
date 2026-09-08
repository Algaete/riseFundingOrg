using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Core.ProjectAssets;
using FundingPlatform.ImageProcessing.ProjectAssets;
using SkiaSharp;

namespace FundingPlatform.UnitTests;

public sealed class ProjectAssetImageSanitizerTests
{
    private static readonly ProtectedProjectAssetBlobLocation Quarantine =
        new("project-assets-quarantine", "tenant/project/asset/file");
    private static readonly ProtectedProjectAssetBlobLocation Trusted =
        new("project-assets-trusted", "tenant/project/asset/file");

    [Fact]
    public void Native_probe_exercises_encode_and_decode()
    {
        var probe = new ProjectAssetImageSanitizationProbe();

        Assert.True(probe.IsAvailable());
    }

    [Fact]
    public async Task Pdf_is_copied_with_an_explicit_identity_manifest()
    {
        var pdf = "%PDF-1.7\n%%EOF"u8.ToArray();
        var blobs = new FakeBlobStore(pdf, "application/pdf");
        using var promoter = new ProjectAssetTrustedContentPromoter(blobs);

        var result = await promoter.PromoteAsync(
            Request(ProjectAssetKind.Document, "application/pdf", pdf),
            CancellationToken.None);

        Assert.Equal(ProjectAssetTrustedPromotionOutcome.Promoted, result.Outcome);
        Assert.NotNull(result.Content);
        Assert.Same(Trusted, result.Content.Location);
        Assert.Equal("application/pdf", result.Content.Manifest.MimeType);
        Assert.Equal(pdf.Length, result.Content.Manifest.ContentLength);
        Assert.Equal(SHA256.HashData(pdf), result.Content.Manifest.ContentHash);
        Assert.Null(result.Content.Manifest.PixelWidth);
        Assert.Null(result.Content.Manifest.PixelHeight);
        Assert.Equal(
            ProjectAssetTrustedContentPromoter.PdfProcessingVersion,
            result.Content.Manifest.ProcessingVersion);
        Assert.Equal(1, blobs.CopyCalls);
        Assert.Empty(blobs.Uploads);
        Assert.Equal("\"quarantine-etag\"", blobs.LastOpenExpectedETag);
    }

    [Theory]
    [InlineData("image/jpeg", SKEncodedImageFormat.Jpeg)]
    [InlineData("image/png", SKEncodedImageFormat.Png)]
    [InlineData("image/webp", SKEncodedImageFormat.Webp)]
    public async Task Supported_still_formats_are_reencoded_in_the_same_container(
        string mimeType,
        SKEncodedImageFormat format)
    {
        var source = EncodePattern(format, 9, 7, includeAlpha: true);
        var blobs = new FakeBlobStore(source, mimeType);
        using var promoter = new ProjectAssetTrustedContentPromoter(blobs);

        var result = await promoter.PromoteAsync(
            Request(ProjectAssetKind.Image, mimeType, source),
            CancellationToken.None);

        Assert.Equal(ProjectAssetTrustedPromotionOutcome.Promoted, result.Outcome);
        Assert.NotNull(result.Content);
        Assert.Single(blobs.Uploads);
        var upload = blobs.Uploads[0];
        Assert.Equal(mimeType, upload.ContentType);
        Assert.Equal(format, ReadFormat(upload.Content));
        Assert.Equal(9, result.Content.Manifest.PixelWidth);
        Assert.Equal(7, result.Content.Manifest.PixelHeight);
        Assert.Equal(upload.Content.Length, result.Content.Manifest.ContentLength);
        Assert.Equal(SHA256.HashData(upload.Content), result.Content.Manifest.ContentHash);
        Assert.Equal(result.Content.Manifest.ContentHash, upload.ExpectedContentHash);
        Assert.Equal(SHA256.HashData(source), upload.SourceContentHash);
        Assert.Equal(
            ProjectAssetTrustedContentPromoter.ImageProcessingVersion,
            upload.ProcessingVersion);
        Assert.Equal(
            ProjectAssetTrustedContentPromoter.ImageProcessingVersion,
            result.Content.Manifest.ProcessingVersion);
    }

    [Theory]
    [InlineData("image/png")]
    [InlineData("image/webp")]
    public async Task Lossless_formats_preserve_alpha(string mimeType)
    {
        var format = mimeType == "image/png"
            ? SKEncodedImageFormat.Png
            : SKEncodedImageFormat.Webp;
        var source = EncodePixels(
            format,
            2,
            1,
            [new SKColor(210, 20, 40, 0), new SKColor(10, 80, 240, 117)]);
        var blobs = new FakeBlobStore(source, mimeType);
        using var promoter = new ProjectAssetTrustedContentPromoter(blobs);

        var result = await promoter.PromoteAsync(
            Request(ProjectAssetKind.Image, mimeType, source),
            CancellationToken.None);

        Assert.True(result.Succeeded);
        using var decoded = Decode(blobs.Uploads.Single().Content);
        Assert.Equal((byte)0, decoded.GetPixel(0, 0).Alpha);
        Assert.Equal((byte)117, decoded.GetPixel(1, 0).Alpha);
    }

    [Fact]
    public async Task Reencoding_is_deterministic_and_strips_original_metadata()
    {
        const string sentinel = "funding-platform-private-exif-sentinel";
        var original = EncodePattern(SKEncodedImageFormat.Jpeg, 40, 30);
        var withMetadata = AddJpegComment(original, sentinel);
        var blobs = new FakeBlobStore(withMetadata, "image/jpeg");
        using var promoter = new ProjectAssetTrustedContentPromoter(blobs);
        var request = Request(ProjectAssetKind.Image, "image/jpeg", withMetadata);

        var first = await promoter.PromoteAsync(
            request,
            CancellationToken.None);
        var second = await promoter.PromoteAsync(
            request,
            CancellationToken.None);

        Assert.True(first.Succeeded);
        Assert.True(second.Succeeded);
        Assert.Equal(blobs.Uploads[0].Content, blobs.Uploads[1].Content);
        Assert.DoesNotContain(
            sentinel,
            Encoding.ASCII.GetString(blobs.Uploads[0].Content),
            StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(1, 40, 30, "red", "green", "blue", "yellow")]
    [InlineData(2, 40, 30, "green", "red", "yellow", "blue")]
    [InlineData(3, 40, 30, "yellow", "blue", "green", "red")]
    [InlineData(4, 40, 30, "blue", "yellow", "red", "green")]
    [InlineData(5, 30, 40, "red", "blue", "green", "yellow")]
    [InlineData(6, 30, 40, "blue", "red", "yellow", "green")]
    [InlineData(7, 30, 40, "yellow", "green", "blue", "red")]
    [InlineData(8, 30, 40, "green", "yellow", "red", "blue")]
    public async Task All_exif_orientations_are_baked_into_fresh_pixels(
        ushort orientation,
        int expectedWidth,
        int expectedHeight,
        string topLeft,
        string topRight,
        string bottomLeft,
        string bottomRight)
    {
        var physical = EncodeQuadrantsAsJpeg();
        var source = AddJpegExifOrientation(physical, orientation);
        using (var data = SKData.CreateCopy(source))
        using (var codec = SKCodec.Create(data))
            Assert.Equal((SKEncodedOrigin)orientation, codec!.EncodedOrigin);
        var blobs = new FakeBlobStore(source, "image/jpeg");
        using var promoter = new ProjectAssetTrustedContentPromoter(blobs);

        var result = await promoter.PromoteAsync(
            Request(ProjectAssetKind.Image, "image/jpeg", source),
            CancellationToken.None);

        Assert.True(result.Succeeded);
        Assert.Equal(expectedWidth, result.Content!.Manifest.PixelWidth);
        Assert.Equal(expectedHeight, result.Content.Manifest.PixelHeight);
        using var output = Decode(blobs.Uploads.Single().Content);
        AssertClose(Color(topLeft), output.GetPixel(output.Width / 4, output.Height / 4));
        AssertClose(Color(topRight), output.GetPixel(output.Width * 3 / 4, output.Height / 4));
        AssertClose(Color(bottomLeft), output.GetPixel(output.Width / 4, output.Height * 3 / 4));
        AssertClose(Color(bottomRight), output.GetPixel(output.Width * 3 / 4, output.Height * 3 / 4));
    }

    [Fact]
    public async Task Animated_webp_is_rejected_before_decode()
    {
        var source = EncodeAnimatedWebp();
        var blobs = new FakeBlobStore(source, "image/webp");
        using var promoter = new ProjectAssetTrustedContentPromoter(blobs);

        var result = await promoter.PromoteAsync(
            Request(ProjectAssetKind.Image, "image/webp", source),
            CancellationToken.None);

        Assert.Equal(ProjectAssetTrustedPromotionOutcome.Rejected, result.Outcome);
        Assert.Equal("image-frame-count-rejected", result.Code);
        Assert.Null(result.Content);
        Assert.Empty(blobs.Uploads);
    }

    [Fact]
    public async Task Mime_and_codec_mismatch_is_rejected()
    {
        var png = EncodePattern(SKEncodedImageFormat.Png, 3, 2);
        var blobs = new FakeBlobStore(png, "image/jpeg");
        using var promoter = new ProjectAssetTrustedContentPromoter(blobs);

        var result = await promoter.PromoteAsync(
            Request(ProjectAssetKind.Image, "image/jpeg", png),
            CancellationToken.None);

        Assert.Equal(ProjectAssetTrustedPromotionOutcome.Rejected, result.Outcome);
        Assert.Equal("image-format-rejected", result.Code);
        Assert.Empty(blobs.Uploads);
    }

    [Fact]
    public async Task Content_hash_mismatch_is_rejected()
    {
        var png = EncodePattern(SKEncodedImageFormat.Png, 3, 2);
        var blobs = new FakeBlobStore(png, "image/png");
        using var promoter = new ProjectAssetTrustedContentPromoter(blobs);
        var request = Request(ProjectAssetKind.Image, "image/png", png) with
        {
            SourceContentHash = new byte[32]
        };

        var result = await promoter.PromoteAsync(
            request,
            CancellationToken.None);

        Assert.Equal(ProjectAssetTrustedPromotionOutcome.Rejected, result.Outcome);
        Assert.Equal("image-decode-rejected", result.Code);
        Assert.Empty(blobs.Uploads);
    }

    [Fact]
    public async Task Truncated_payload_is_rejected_even_when_its_hash_matches()
    {
        var png = EncodePattern(SKEncodedImageFormat.Png, 20, 20);
        var truncated = png[..(png.Length / 2)];
        var blobs = new FakeBlobStore(truncated, "image/png");
        using var promoter = new ProjectAssetTrustedContentPromoter(blobs);

        var result = await promoter.PromoteAsync(
            Request(ProjectAssetKind.Image, "image/png", truncated),
            CancellationToken.None);

        Assert.Equal(ProjectAssetTrustedPromotionOutcome.Rejected, result.Outcome);
        Assert.Equal("image-decode-rejected", result.Code);
        Assert.Empty(blobs.Uploads);
    }

    [Fact]
    public async Task Pixel_policy_is_enforced_before_pixel_allocation()
    {
        var png = EncodePattern(SKEncodedImageFormat.Png, 3, 2);
        var blobs = new FakeBlobStore(png, "image/png");
        using var promoter = new ProjectAssetTrustedContentPromoter(blobs);
        var request = Request(ProjectAssetKind.Image, "image/png", png) with
        {
            MaximumImagePixels = 5
        };

        var result = await promoter.PromoteAsync(
            request,
            CancellationToken.None);

        Assert.Equal(ProjectAssetTrustedPromotionOutcome.Rejected, result.Outcome);
        Assert.Equal("image-dimensions-rejected", result.Code);
        Assert.Empty(blobs.Uploads);
    }

    [Fact]
    public async Task Encoded_output_cannot_cross_the_requested_limit()
    {
        var png = EncodePattern(SKEncodedImageFormat.Png, 8, 8);
        var blobs = new FakeBlobStore(png, "image/png");
        using var promoter = new ProjectAssetTrustedContentPromoter(blobs);
        var request = Request(ProjectAssetKind.Image, "image/png", png) with
        {
            MaximumOutputLength = 1
        };

        var result = await promoter.PromoteAsync(
            request,
            CancellationToken.None);

        Assert.Equal(ProjectAssetTrustedPromotionOutcome.Rejected, result.Outcome);
        Assert.Equal("image-output-too-large", result.Code);
        Assert.Empty(blobs.Uploads);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task Storage_failures_are_retryable(bool failWhileOpening)
    {
        var png = EncodePattern(SKEncodedImageFormat.Png, 3, 2);
        var blobs = new FakeBlobStore(png, "image/png")
        {
            FailOpen = failWhileOpening,
            FailUpload = !failWhileOpening
        };
        using var promoter = new ProjectAssetTrustedContentPromoter(blobs);

        var result = await promoter.PromoteAsync(
            Request(ProjectAssetKind.Image, "image/png", png),
            CancellationToken.None);

        Assert.Equal(ProjectAssetTrustedPromotionOutcome.Retry, result.Outcome);
        Assert.Equal("image-storage-retry", result.Code);
        Assert.Null(result.Content);
    }

    private static ProjectAssetTrustedContentRequest Request(
        ProjectAssetKind kind,
        string mimeType,
        byte[] content) => new(
        kind,
        Quarantine,
        "\"quarantine-etag\"",
        Trusted,
        mimeType,
        content.Length,
        SHA256.HashData(content),
        10 * 1024 * 1024,
        25_000_000);

    private static byte[] EncodePattern(
        SKEncodedImageFormat format,
        int width,
        int height,
        bool includeAlpha = false)
    {
        using var bitmap = NewBitmap(width, height);
        for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++)
        {
            var alpha = includeAlpha ? (byte)(31 + (x * 17 + y * 13) % 225) : (byte)255;
            bitmap.SetPixel(x, y, new SKColor(
                (byte)(x * 23 % 256),
                (byte)(y * 37 % 256),
                (byte)((x + y) * 19 % 256),
                alpha));
        }
        return Encode(bitmap, format);
    }

    private static byte[] EncodePixels(
        SKEncodedImageFormat format,
        int width,
        int height,
        IReadOnlyList<SKColor> pixels)
    {
        using var bitmap = NewBitmap(width, height);
        for (var index = 0; index < pixels.Count; index++)
            bitmap.SetPixel(index % width, index / width, pixels[index]);
        return Encode(bitmap, format);
    }

    private static byte[] EncodeQuadrantsAsJpeg()
    {
        using var bitmap = NewBitmap(40, 30);
        for (var y = 0; y < bitmap.Height; y++)
        for (var x = 0; x < bitmap.Width; x++)
        {
            var color = (x < bitmap.Width / 2, y < bitmap.Height / 2) switch
            {
                (true, true) => SKColors.Red,
                (false, true) => SKColors.Lime,
                (true, false) => SKColors.Blue,
                _ => SKColors.Yellow
            };
            bitmap.SetPixel(x, y, color);
        }
        using var pixels = bitmap.PeekPixels();
        using var data = pixels.Encode(new SKJpegEncoderOptions(
            100,
            SKJpegEncoderDownsample.Downsample444,
            SKJpegEncoderAlphaOption.Ignore));
        return (data ?? throw new InvalidOperationException("JPEG encoding failed.")).ToArray();
    }

    private static byte[] Encode(SKBitmap bitmap, SKEncodedImageFormat format)
    {
        using var pixels = bitmap.PeekPixels();
        using var data = format switch
        {
            SKEncodedImageFormat.Jpeg => pixels.Encode(new SKJpegEncoderOptions(
                100,
                SKJpegEncoderDownsample.Downsample444,
                SKJpegEncoderAlphaOption.Ignore)),
            SKEncodedImageFormat.Png => pixels.Encode(
                new SKPngEncoderOptions(SKPngEncoderFilterFlags.AllFilters, 9)),
            SKEncodedImageFormat.Webp => pixels.Encode(
                new SKWebpEncoderOptions(SKWebpEncoderCompression.Lossless, 100)),
            _ => throw new ArgumentOutOfRangeException(nameof(format))
        };
        return (data ?? throw new InvalidOperationException("Image encoding failed.")).ToArray();
    }

    private static byte[] EncodeAnimatedWebp()
    {
        using var red = NewBitmap(2, 2);
        using var blue = NewBitmap(2, 2);
        red.Erase(SKColors.Red);
        blue.Erase(SKColors.Blue);
        SKWebpEncoderFrame[] frames =
        [
            new(red, TimeSpan.FromMilliseconds(100)),
            new(blue, TimeSpan.FromMilliseconds(100))
        ];
        using var data = SKWebpEncoder.EncodeAnimated(
            frames,
            new SKWebpEncoderOptions(SKWebpEncoderCompression.Lossless, 100));
        return (data ?? throw new InvalidOperationException("Animated WebP encoding failed.")).ToArray();
    }

    private static SKBitmap NewBitmap(int width, int height)
    {
        using var colorSpace = SKColorSpace.CreateSrgb();
        return new SKBitmap(new SKImageInfo(
            width,
            height,
            SKColorType.Rgba8888,
            SKAlphaType.Unpremul,
            colorSpace));
    }

    private static SKBitmap Decode(byte[] encoded)
    {
        using var data = SKData.CreateCopy(encoded);
        using var codec = SKCodec.Create(data) ?? throw new InvalidDataException();
        using var colorSpace = SKColorSpace.CreateSrgb();
        var bitmap = new SKBitmap(new SKImageInfo(
            codec.Info.Width,
            codec.Info.Height,
            SKColorType.Rgba8888,
            SKAlphaType.Unpremul,
            colorSpace));
        Assert.Equal(
            SKCodecResult.Success,
            codec.GetPixels(bitmap.Info, bitmap.GetPixels()));
        return bitmap;
    }

    private static SKEncodedImageFormat ReadFormat(byte[] encoded)
    {
        using var data = SKData.CreateCopy(encoded);
        using var codec = SKCodec.Create(data) ?? throw new InvalidDataException();
        return codec.EncodedFormat;
    }

    private static byte[] AddJpegComment(byte[] jpeg, string comment) =>
        InsertJpegSegment(jpeg, 0xfe, Encoding.ASCII.GetBytes(comment));

    private static byte[] AddJpegExifOrientation(byte[] jpeg, ushort orientation)
    {
        var payload = new byte[32];
        "Exif\0\0"u8.CopyTo(payload);
        // Little-endian TIFF header, followed by one SHORT Orientation entry.
        byte[] tiff =
        [
            0x49, 0x49, 0x2a, 0x00, 0x08, 0x00, 0x00, 0x00,
            0x01, 0x00,
            0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00,
            (byte)orientation, (byte)(orientation >> 8), 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00
        ];
        tiff.CopyTo(payload, 6);
        return InsertJpegSegment(jpeg, 0xe1, payload);
    }

    private static byte[] InsertJpegSegment(byte[] jpeg, byte marker, byte[] payload)
    {
        Assert.True(jpeg.Length > 2 && jpeg[0] == 0xff && jpeg[1] == 0xd8);
        var segmentLength = checked(payload.Length + 2);
        var result = new byte[checked(jpeg.Length + payload.Length + 4)];
        result[0] = 0xff;
        result[1] = 0xd8;
        result[2] = 0xff;
        result[3] = marker;
        result[4] = (byte)(segmentLength >> 8);
        result[5] = (byte)segmentLength;
        payload.CopyTo(result, 6);
        jpeg.AsSpan(2).CopyTo(result.AsSpan(payload.Length + 6));
        return result;
    }

    private static SKColor Color(string name) => name switch
    {
        "red" => SKColors.Red,
        "green" => SKColors.Lime,
        "blue" => SKColors.Blue,
        "yellow" => SKColors.Yellow,
        _ => throw new ArgumentOutOfRangeException(nameof(name))
    };

    private static void AssertClose(SKColor expected, SKColor actual)
    {
        static int Difference(byte left, byte right) => left - right;
        var squaredDistance =
            Difference(expected.Red, actual.Red) * Difference(expected.Red, actual.Red) +
            Difference(expected.Green, actual.Green) * Difference(expected.Green, actual.Green) +
            Difference(expected.Blue, actual.Blue) * Difference(expected.Blue, actual.Blue);
        Assert.True(
            squaredDistance < 2_500,
            $"Expected approximately {expected}, received {actual}.");
    }

    private sealed class FakeBlobStore(byte[] content, string contentType) : IProjectAssetBlobStore
    {
        public bool FailOpen { get; init; }
        public bool FailUpload { get; init; }
        public int CopyCalls { get; private set; }
        public string? LastOpenExpectedETag { get; private set; }
        public List<UploadObservation> Uploads { get; } = [];

        public Task<ProjectAssetBlobRead> OpenReadAsync(
            ProtectedProjectAssetBlobLocation source,
            string? expectedETag,
            CancellationToken cancellationToken)
        {
            LastOpenExpectedETag = expectedETag;
            if (FailOpen)
                throw StorageFailure("open");
            return Task.FromResult(new ProjectAssetBlobRead(
                new MemoryStream(content, writable: false),
                content.Length,
                contentType,
                "\"quarantine-etag\"",
                "quarantine-version"));
        }

        public Task<ProjectAssetBlobReceipt> EnsureCopyAsync(
            ProtectedProjectAssetBlobLocation source,
            string sourceETag,
            ProtectedProjectAssetBlobLocation destination,
            string requestedContentType,
            long expectedLength,
            byte[] expectedContentHash,
            CancellationToken cancellationToken)
        {
            CopyCalls++;
            LastOpenExpectedETag = sourceETag;
            return Task.FromResult(
                new ProjectAssetBlobReceipt("\"trusted-etag\"", "trusted-version"));
        }

        public Task<ProjectAssetBlobReceipt> EnsureUploadAsync(
            ProtectedProjectAssetBlobLocation destination,
            ReadOnlyMemory<byte> uploadedContent,
            string requestedContentType,
            byte[] expectedContentHash,
            byte[] sourceContentHash,
            string processingVersion,
            CancellationToken cancellationToken)
        {
            if (FailUpload)
                throw StorageFailure("upload");
            Uploads.Add(new UploadObservation(
                uploadedContent.ToArray(),
                requestedContentType,
                expectedContentHash.ToArray(),
                sourceContentHash.ToArray(),
                processingVersion));
            return Task.FromResult(
                new ProjectAssetBlobReceipt("\"trusted-etag\"", "trusted-version"));
        }

        public Task<ProjectAssetUploadGrant> CreateUploadGrantAsync(
            ProtectedProjectAssetBlobLocation destination,
            string requestedContentType,
            DateTimeOffset expiresAtUtc,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<ProjectAssetBlobReceipt?> GetVerifiedReceiptAsync(
            ProtectedProjectAssetBlobLocation location,
            string requestedContentType,
            long expectedLength,
            byte[] expectedContentHash,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<ProjectAssetBlobReceipt?> GetVerifiedVersionReceiptAsync(
            ProtectedProjectAssetBlobLocation location,
            string versionId,
            string requestedContentType,
            long expectedLength,
            byte[] expectedContentHash,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task DeleteIfMatchAsync(
            ProtectedProjectAssetBlobLocation location,
            string? expectedETag,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task DeleteVersionIfMatchAsync(
            ProtectedProjectAssetBlobLocation location,
            string versionId,
            string expectedETag,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        private static ProjectAssetStorageException StorageFailure(string operation) =>
            new(operation, "test-storage", 503);
    }

    private sealed record UploadObservation(
        byte[] Content,
        string ContentType,
        byte[] ExpectedContentHash,
        byte[] SourceContentHash,
        string ProcessingVersion);
}
