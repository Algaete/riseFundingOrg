using System.Security.Cryptography;
using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Core.ProjectAssets;
using SkiaSharp;

namespace FundingPlatform.ImageProcessing.ProjectAssets;

/// <summary>
/// Builds a trusted project asset from the exact quarantine blob scanned by the
/// malware provider. Documents are copied byte-for-byte; images cross a decode
/// and re-encode boundary so no original metadata or ancillary chunks survive.
/// </summary>
public sealed class ProjectAssetTrustedContentPromoter(
    IProjectAssetBlobStore blobStore) : IProjectAssetTrustedContentPromoter, IDisposable
{
    public const string ImageProcessingVersion =
        ProjectAssetTrustedContentRules.ImageProcessingVersion;
    public const string PdfProcessingVersion =
        ProjectAssetTrustedContentRules.PdfProcessingVersion;

    private const long MaximumDecodedBytes = 100_000_000;
    private const long AbsoluteMaximumEncodedBytes = 32L * 1024 * 1024;
    private const int BytesPerPixel = 4;
    private readonly SemaphoreSlim imageProcessingLock = new(1, 1);

    public async Task<ProjectAssetTrustedContentPromotion> PromoteAsync(
        ProjectAssetTrustedContentRequest request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (request.Kind is ProjectAssetKind.Document or ProjectAssetKind.Video)
            return await PromotePdfAsync(request, cancellationToken);
        if (request.Kind != ProjectAssetKind.Image)
            return Rejected("trusted-promotion-not-supported");

        await imageProcessingLock.WaitAsync(cancellationToken);
        try
        {
            return await PromoteImageAsync(request, cancellationToken);
        }
        catch (ImageRejectedException exception)
        {
            return Rejected(exception.Code);
        }
        catch (ProjectAssetStorageException)
        {
            return Retry("image-storage-retry");
        }
        catch (IOException)
        {
            return Retry("image-storage-retry");
        }
        catch (Exception exception) when (IsNativeFailure(exception))
        {
            return Retry("image-native-retry");
        }
        catch (ImageProcessingRetryException)
        {
            return Retry("image-processing-retry");
        }
        catch (OutOfMemoryException)
        {
            return Retry("image-processing-retry");
        }
        catch (TimeoutException)
        {
            return Retry("image-processing-retry");
        }
        finally
        {
            imageProcessingLock.Release();
        }
    }

    public void Dispose() => imageProcessingLock.Dispose();

    private async Task<ProjectAssetTrustedContentPromotion> PromotePdfAsync(
        ProjectAssetTrustedContentRequest request,
        CancellationToken cancellationToken)
    {
        var mime = request.SourceMimeType.ToLowerInvariant();
        var version = ProjectAssetTrustedContentRules.CopyVersion(request.Kind, mime);
        if (version is null ||
            request.SourceContentLength is < 1 ||
            request.SourceContentLength > 26_214_400 ||
            (mime == "text/plain" && request.SourceContentLength > 1_048_576) ||
            request.SourceContentHash is not { Length: 32 } ||
            request.SourceContentLength > request.MaximumOutputLength)
        {
            return Rejected("trusted-promotion-not-supported");
        }

        try
        {
            var sourceHash = request.SourceContentHash.ToArray();
            var receipt = await blobStore.EnsureCopyAsync(
                request.QuarantineLocation,
                request.QuarantineETag,
                request.TrustedLocation,
                mime,
                request.SourceContentLength,
                sourceHash,
                cancellationToken);
            return Promoted(
                request.TrustedLocation,
                receipt,
                new ProjectAssetTrustedContentManifest(
                    mime,
                    request.SourceContentLength,
                    sourceHash,
                    null,
                    null,
                    version));
        }
        catch (ProjectAssetStorageException)
        {
            return Retry("pdf-storage-retry");
        }
        catch (IOException)
        {
            return Retry("pdf-storage-retry");
        }
        catch (TimeoutException)
        {
            return Retry("pdf-storage-retry");
        }
    }

    private async Task<ProjectAssetTrustedContentPromotion> PromoteImageAsync(
        ProjectAssetTrustedContentRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetFormat(request.SourceMimeType, out var expectedFormat, out var mimeType))
            throw new ImageRejectedException("image-format-rejected");
        if (request.SourceContentHash is not { Length: 32 } ||
            request.SourceContentLength is < 1 or > AbsoluteMaximumEncodedBytes)
            throw new ImageRejectedException("image-decode-rejected");
        if (request.MaximumOutputLength < 1 ||
            request.SourceContentLength > request.MaximumOutputLength)
            throw new ImageRejectedException("image-output-too-large");
        var sourceHash = request.SourceContentHash.ToArray();

        await using var source = await blobStore.OpenReadAsync(
            request.QuarantineLocation,
            request.QuarantineETag,
            cancellationToken);

        if (source.ContentLength != request.SourceContentLength)
            throw new ImageRejectedException("image-decode-rejected");
        if (!TryGetFormat(source.ContentType, out var storedFormat, out _) ||
            storedFormat != expectedFormat)
            throw new ImageRejectedException("image-format-rejected");

        var encodedSource = await ReadAndVerifySourceAsync(
            source.Content,
            request.SourceContentLength,
            sourceHash,
            cancellationToken);

        var sanitized = Sanitize(
            encodedSource,
            expectedFormat,
            request.MaximumOutputLength,
            request.MaximumImagePixels);
        var trustedHash = SHA256.HashData(sanitized.Content.Span);
        var receipt = await blobStore.EnsureUploadAsync(
            request.TrustedLocation,
            sanitized.Content,
            mimeType,
            trustedHash,
            sourceHash,
            ImageProcessingVersion,
            cancellationToken);

        return Promoted(
            request.TrustedLocation,
            receipt,
            new ProjectAssetTrustedContentManifest(
                mimeType,
                sanitized.Content.Length,
                trustedHash,
                sanitized.Width,
                sanitized.Height,
                ImageProcessingVersion));
    }

    private static async Task<byte[]> ReadAndVerifySourceAsync(
        Stream source,
        long expectedLength,
        byte[] expectedHash,
        CancellationToken cancellationToken)
    {
        var content = GC.AllocateUninitializedArray<byte>(checked((int)expectedLength));
        var offset = 0;
        while (offset < content.Length)
        {
            var read = await source.ReadAsync(
                content.AsMemory(offset, content.Length - offset),
                cancellationToken);
            if (read == 0)
                throw new ImageRejectedException("image-decode-rejected");
            offset += read;
        }

        var trailing = new byte[1];
        if (await source.ReadAsync(trailing, cancellationToken) != 0)
            throw new ImageRejectedException("image-decode-rejected");

        var actualHash = SHA256.HashData(content);
        if (!CryptographicOperations.FixedTimeEquals(actualHash, expectedHash))
            throw new ImageRejectedException("image-decode-rejected");
        return content;
    }

    private static SanitizedImage Sanitize(
        byte[] encodedSource,
        SKEncodedImageFormat expectedFormat,
        long requestedMaximumOutputLength,
        int requestedMaximumPixels)
    {
        try
        {
            using var data = SKData.CreateCopy(encodedSource);
            using var codec = SKCodec.Create(data);
            if (codec is null)
                throw new ImageRejectedException("image-decode-rejected");
            if (codec.EncodedFormat != expectedFormat)
                throw new ImageRejectedException("image-format-rejected");

            // Skia reports zero frames for an ordinary still image and more than
            // one for animated formats. A one-frame animation is still accepted.
            if (codec.FrameCount > 1)
                throw new ImageRejectedException("image-frame-count-rejected");

            var sourceInfo = codec.Info;
            ValidateDimensions(
                sourceInfo.Width,
                sourceInfo.Height,
                requestedMaximumPixels);

            using var colorSpace = SKColorSpace.CreateSrgb();
            var decodeInfo = new SKImageInfo(
                sourceInfo.Width,
                sourceInfo.Height,
                SKColorType.Rgba8888,
                SKAlphaType.Unpremul,
                colorSpace);
            using var decoded = new SKBitmap(decodeInfo);
            if (decoded.GetPixels() == IntPtr.Zero ||
                codec.GetPixels(decodeInfo, decoded.GetPixels()) != SKCodecResult.Success)
                throw new ImageRejectedException("image-decode-rejected");

            if ((int)codec.EncodedOrigin is < 1 or > 8)
                throw new ImageRejectedException("image-decode-rejected");

            using var oriented = ApplyEncodedOrientation(decoded, codec.EncodedOrigin, colorSpace);
            ValidateDimensions(oriented.Width, oriented.Height, requestedMaximumPixels);

            var hardMaximum = Math.Min(requestedMaximumOutputLength, AbsoluteMaximumEncodedBytes);
            using var output = new BoundedWriteStream(hardMaximum);
            var encoded = EncodeFreshPixels(oriented, expectedFormat, output);
            // SKManagedWStream may convert a managed Stream exception into a false
            // encoder result, so retain the limit state independently as well.
            if (output.LimitExceeded)
                throw new ImageRejectedException("image-output-too-large");
            if (output.WriteFailed || !encoded)
                throw new ImageProcessingRetryException();

            return new SanitizedImage(
                output.ToArray(),
                oriented.Width,
                oriented.Height);
        }
        catch (ImageRejectedException)
        {
            throw;
        }
        catch (Exception exception) when (IsNativeFailure(exception))
        {
            throw;
        }
        catch (OutOfMemoryException)
        {
            throw;
        }
        catch (ImageProcessingRetryException)
        {
            throw;
        }
        catch (Exception exception) when (
            exception is ArgumentException or InvalidOperationException or OverflowException)
        {
            throw new ImageRejectedException("image-decode-rejected");
        }
    }

    private static void ValidateDimensions(
        int width,
        int height,
        int requestedMaximumPixels)
    {
        if (width is < 1 or > ProjectAssetTrustedContentRules.MaximumImageDimension ||
            height is < 1 or > ProjectAssetTrustedContentRules.MaximumImageDimension ||
            requestedMaximumPixels < 1)
            throw new ImageRejectedException("image-dimensions-rejected");

        var pixels = checked((long)width * height);
        var effectiveMaximumPixels = Math.Min(
            (long)requestedMaximumPixels,
            ProjectAssetTrustedContentRules.AbsoluteMaximumImagePixels);
        if (pixels > effectiveMaximumPixels ||
            checked(pixels * BytesPerPixel) > MaximumDecodedBytes)
            throw new ImageRejectedException("image-dimensions-rejected");
    }

    private static SKBitmap ApplyEncodedOrientation(
        SKBitmap source,
        SKEncodedOrigin origin,
        SKColorSpace colorSpace)
    {
        var swapsAxes = origin is
            SKEncodedOrigin.LeftTop or
            SKEncodedOrigin.RightTop or
            SKEncodedOrigin.RightBottom or
            SKEncodedOrigin.LeftBottom;
        var width = swapsAxes ? source.Height : source.Width;
        var height = swapsAxes ? source.Width : source.Height;
        var result = new SKBitmap(new SKImageInfo(
            width,
            height,
            SKColorType.Rgba8888,
            SKAlphaType.Unpremul,
            colorSpace));
        if (result.GetPixels() == IntPtr.Zero)
        {
            result.Dispose();
            throw new OutOfMemoryException("Unable to allocate oriented image pixels.");
        }

        CopyOrientedPixels(source, result, origin);
        return result;
    }

    private static void CopyOrientedPixels(
        SKBitmap source,
        SKBitmap destination,
        SKEncodedOrigin origin)
    {
        var sourcePixels = source.GetPixelSpan();
        var destinationPixels = destination.GetPixelSpan();
        for (var sourceY = 0; sourceY < source.Height; sourceY++)
        {
            for (var sourceX = 0; sourceX < source.Width; sourceX++)
            {
                var (destinationX, destinationY) = origin switch
                {
                    SKEncodedOrigin.TopRight =>
                        (source.Width - sourceX - 1, sourceY),
                    SKEncodedOrigin.BottomRight =>
                        (source.Width - sourceX - 1, source.Height - sourceY - 1),
                    SKEncodedOrigin.BottomLeft =>
                        (sourceX, source.Height - sourceY - 1),
                    SKEncodedOrigin.LeftTop =>
                        (sourceY, sourceX),
                    SKEncodedOrigin.RightTop =>
                        (source.Height - sourceY - 1, sourceX),
                    SKEncodedOrigin.RightBottom =>
                        (source.Height - sourceY - 1, source.Width - sourceX - 1),
                    SKEncodedOrigin.LeftBottom =>
                        (sourceY, source.Width - sourceX - 1),
                    _ => (sourceX, sourceY)
                };

                var sourceOffset = sourceY * source.RowBytes + sourceX * BytesPerPixel;
                var destinationOffset =
                    destinationY * destination.RowBytes + destinationX * BytesPerPixel;
                sourcePixels.Slice(sourceOffset, BytesPerPixel).CopyTo(
                    destinationPixels.Slice(destinationOffset, BytesPerPixel));
            }
        }
    }

    private static bool Encode(
        SKPixmap pixmap,
        SKEncodedImageFormat format,
        Stream output) => format switch
    {
        SKEncodedImageFormat.Jpeg => pixmap.Encode(
            output,
            new SKJpegEncoderOptions(
                90,
                SKJpegEncoderDownsample.Downsample420,
                SKJpegEncoderAlphaOption.Ignore)),
        SKEncodedImageFormat.Png => pixmap.Encode(
            output,
            new SKPngEncoderOptions(SKPngEncoderFilterFlags.AllFilters, 9)),
        SKEncodedImageFormat.Webp => pixmap.Encode(
            output,
            new SKWebpEncoderOptions(SKWebpEncoderCompression.Lossless, 100)),
        _ => false
    };

    private static bool EncodeFreshPixels(
        SKBitmap bitmap,
        SKEncodedImageFormat format,
        Stream output)
    {
        try
        {
            using var pixmap = bitmap.PeekPixels();
            return pixmap is not null && Encode(pixmap, format, output);
        }
        catch (Exception exception) when (IsNativeFailure(exception))
        {
            throw;
        }
        catch (OutOfMemoryException)
        {
            throw;
        }
        catch
        {
            throw new ImageProcessingRetryException();
        }
    }

    private static bool TryGetFormat(
        string? mimeType,
        out SKEncodedImageFormat format,
        out string normalizedMimeType)
    {
        normalizedMimeType = mimeType?.Trim().ToLowerInvariant() ?? string.Empty;
        switch (normalizedMimeType)
        {
            case "image/jpeg":
                format = SKEncodedImageFormat.Jpeg;
                return true;
            case "image/png":
                format = SKEncodedImageFormat.Png;
                return true;
            case "image/webp":
                format = SKEncodedImageFormat.Webp;
                return true;
            default:
                format = default;
                return false;
        }
    }

    private static bool IsNativeFailure(Exception exception)
    {
        for (Exception? current = exception; current is not null; current = current.InnerException)
        {
            if (current is DllNotFoundException or EntryPointNotFoundException or
                BadImageFormatException)
                return true;
        }
        return false;
    }

    private static ProjectAssetTrustedContentPromotion Promoted(
        ProtectedProjectAssetBlobLocation location,
        ProjectAssetBlobReceipt receipt,
        ProjectAssetTrustedContentManifest manifest) => new(
        ProjectAssetTrustedPromotionOutcome.Promoted,
        "promoted",
        new ProjectAssetTrustedBlob(location, receipt, manifest));

    private static ProjectAssetTrustedContentPromotion Rejected(string code) => new(
        ProjectAssetTrustedPromotionOutcome.Rejected,
        code);

    private static ProjectAssetTrustedContentPromotion Retry(string code) => new(
        ProjectAssetTrustedPromotionOutcome.Retry,
        code);

    private sealed record SanitizedImage(
        ReadOnlyMemory<byte> Content,
        int Width,
        int Height);

    private sealed class ImageRejectedException(string code) : Exception
    {
        public string Code { get; } = code;
    }

    private sealed class ImageProcessingRetryException : Exception;

    private sealed class BoundedWriteStream(long maximumLength) : Stream
    {
        private readonly MemoryStream inner = new();

        public bool LimitExceeded { get; private set; }
        public bool WriteFailed { get; private set; }

        public override bool CanRead => false;
        public override bool CanSeek => false;
        public override bool CanWrite => true;
        public override long Length => inner.Length;
        public override long Position
        {
            get => inner.Position;
            set => throw new NotSupportedException();
        }

        public byte[] ToArray() => inner.ToArray();

        public override void Flush()
        {
            // MemoryStream has nothing to flush. Keeping this callback a no-op also
            // guarantees no managed exception crosses the native encoder boundary.
        }

        public override void Write(byte[] buffer, int offset, int count)
        {
            if (!CanAccept(count)) return;
            try
            {
                inner.Write(buffer, offset, count);
            }
            catch
            {
                WriteFailed = true;
            }
        }

        public override void Write(ReadOnlySpan<byte> buffer)
        {
            if (!CanAccept(buffer.Length)) return;
            try
            {
                inner.Write(buffer);
            }
            catch
            {
                WriteFailed = true;
            }
        }

        public override Task WriteAsync(
            byte[] buffer,
            int offset,
            int count,
            CancellationToken cancellationToken)
        {
            Write(buffer, offset, count);
            return Task.CompletedTask;
        }

        public override ValueTask WriteAsync(
            ReadOnlyMemory<byte> buffer,
            CancellationToken cancellationToken = default)
        {
            Write(buffer.Span);
            return ValueTask.CompletedTask;
        }

        public override int Read(byte[] buffer, int offset, int count) =>
            throw new NotSupportedException();

        public override long Seek(long offset, SeekOrigin origin) =>
            throw new NotSupportedException();

        public override void SetLength(long value) => throw new NotSupportedException();

        protected override void Dispose(bool disposing)
        {
            if (disposing) inner.Dispose();
            base.Dispose(disposing);
        }

        private bool CanAccept(int additionalBytes)
        {
            if (additionalBytes < 0 || inner.Length > maximumLength - additionalBytes)
            {
                LimitExceeded = true;
                return false;
            }
            return !WriteFailed && !LimitExceeded;
        }
    }
}
