using System.Buffers;
using System.Buffers.Binary;
using System.Security.Cryptography;
using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Core.ProjectAssets;

namespace FundingPlatform.Infrastructure.ProjectAssets.Inspection;

public sealed class StreamingProjectAssetContentInspector : IProjectAssetContentInspector
{
    private const int MaximumImageDimension = 32_768;
    private const int HeaderCaptureBytes = 1024 * 1024;
    private const int TailCaptureBytes = 2048;
    private static ReadOnlySpan<byte> PdfHeader => "%PDF-"u8;
    private static ReadOnlySpan<byte> PdfEndMarker => "%%EOF"u8;
    private static ReadOnlySpan<byte> PngHeader =>
        [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

    public async Task<ProjectAssetInspection> InspectAsync(
        ProjectAssetKind kind,
        ProjectAssetBlobRead source,
        long expectedLength,
        long maximumLength,
        int maximumImagePixels,
        CancellationToken cancellationToken)
    {
        if (source.ContentLength > maximumLength)
            return Invalid(ProjectAssetInspectionFailure.TooLarge, source.ContentLength);
        if (source.ContentLength != expectedLength)
            return Invalid(ProjectAssetInspectionFailure.LengthMismatch, source.ContentLength);

        var normalizedMimeType = source.ContentType?.Trim().ToLowerInvariant();
        if (!IsAllowedMimeType(kind, normalizedMimeType))
            return Invalid(ProjectAssetInspectionFailure.InvalidContentType, source.ContentLength);
        if (normalizedMimeType is "text/plain" or "video/mp4")
            return await PrivateAttachmentInspector.InspectAsync(source, expectedLength, maximumLength, normalizedMimeType, cancellationToken);

        var rented = ArrayPool<byte>.Shared.Rent(64 * 1024);
        var header = new byte[(int)Math.Min(source.ContentLength, HeaderCaptureBytes)];
        var tail = kind == ProjectAssetKind.Document ? new byte[TailCaptureBytes] : [];
        var headerCount = 0;
        var tailCount = 0;
        var tailOffset = 0;
        long total = 0;
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        try
        {
            int read;
            while ((read = await source.Content.ReadAsync(
                       rented.AsMemory(0, rented.Length), cancellationToken)) > 0)
            {
                if (total + read > maximumLength)
                    return Invalid(ProjectAssetInspectionFailure.TooLarge, total + read);

                var headerRemaining = header.Length - headerCount;
                if (headerRemaining > 0)
                {
                    var copy = Math.Min(headerRemaining, read);
                    rented.AsSpan(0, copy).CopyTo(header.AsSpan(headerCount, copy));
                    headerCount += copy;
                }

                hash.AppendData(rented, 0, read);
                if (tail.Length > 0)
                {
                    for (var index = 0; index < read; index++)
                    {
                        tail[tailOffset] = rented[index];
                        tailOffset = (tailOffset + 1) % tail.Length;
                        tailCount = Math.Min(tailCount + 1, tail.Length);
                    }
                }
                total += read;
            }

            if (total != expectedLength)
                return Invalid(ProjectAssetInspectionFailure.LengthMismatch, total);

            if (kind == ProjectAssetKind.Document)
            {
                if (!IsPdf(header.AsSpan(0, headerCount), OrderedTail(tail, tailCount, tailOffset)))
                    return Invalid(ProjectAssetInspectionFailure.InvalidFile, total);
                return new ProjectAssetInspection(
                    true,
                    ProjectAssetInspectionFailure.None,
                    total,
                    hash.GetHashAndReset(),
                    normalizedMimeType);
            }

            if (kind != ProjectAssetKind.Image ||
                !TryReadImageDimensions(
                    normalizedMimeType!, header.AsSpan(0, headerCount), out var width, out var height))
                return Invalid(ProjectAssetInspectionFailure.InvalidFile, total);
            if (width > MaximumImageDimension || height > MaximumImageDimension ||
                (long)width * height > maximumImagePixels)
                return Invalid(ProjectAssetInspectionFailure.ImageTooLarge, total);

            return new ProjectAssetInspection(
                true,
                ProjectAssetInspectionFailure.None,
                total,
                hash.GetHashAndReset(),
                normalizedMimeType,
                width,
                height);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(rented.AsSpan(0, rented.Length));
            ArrayPool<byte>.Shared.Return(rented);
        }
    }

    private static bool IsAllowedMimeType(ProjectAssetKind kind, string? mimeType) =>
        kind switch
        {
            ProjectAssetKind.Image => mimeType is "image/jpeg" or "image/png" or "image/webp",
            ProjectAssetKind.Document => mimeType is "application/pdf" or "text/plain",
            ProjectAssetKind.Video => mimeType == "video/mp4",
            _ => false
        };

    private static bool IsPdf(ReadOnlySpan<byte> header, ReadOnlySpan<byte> tail)
    {
        if (!header.StartsWith(PdfHeader)) return false;
        for (var index = tail.Length - PdfEndMarker.Length; index >= 0; index--)
        {
            if (!tail.Slice(index, PdfEndMarker.Length).SequenceEqual(PdfEndMarker)) continue;
            for (var trailing = index + PdfEndMarker.Length; trailing < tail.Length; trailing++)
            {
                if (tail[trailing] is not (0 or 9 or 10 or 12 or 13 or 32)) return false;
            }
            return true;
        }
        return false;
    }

    private static byte[] OrderedTail(byte[] tail, int count, int offset)
    {
        if (count == 0) return [];
        var ordered = new byte[count];
        var start = count == tail.Length ? offset : 0;
        for (var index = 0; index < count; index++)
            ordered[index] = tail[(start + index) % tail.Length];
        return ordered;
    }

    private static bool TryReadImageDimensions(
        string mimeType,
        ReadOnlySpan<byte> header,
        out int width,
        out int height)
    {
        width = 0;
        height = 0;
        return mimeType switch
        {
            "image/png" => TryReadPngDimensions(header, out width, out height),
            "image/jpeg" => TryReadJpegDimensions(header, out width, out height),
            "image/webp" => TryReadWebpDimensions(header, out width, out height),
            _ => false
        };
    }

    private static bool TryReadPngDimensions(
        ReadOnlySpan<byte> header,
        out int width,
        out int height)
    {
        width = 0;
        height = 0;
        if (header.Length < 24 || !header[..8].SequenceEqual(PngHeader) ||
            !header.Slice(12, 4).SequenceEqual("IHDR"u8))
            return false;
        width = BinaryPrimitives.ReadInt32BigEndian(header.Slice(16, 4));
        height = BinaryPrimitives.ReadInt32BigEndian(header.Slice(20, 4));
        return width > 0 && height > 0;
    }

    private static bool TryReadJpegDimensions(
        ReadOnlySpan<byte> header,
        out int width,
        out int height)
    {
        width = 0;
        height = 0;
        if (header.Length < 4 || header[0] != 0xff || header[1] != 0xd8) return false;
        var offset = 2;
        while (offset + 3 < header.Length)
        {
            while (offset < header.Length && header[offset] != 0xff) offset++;
            while (offset < header.Length && header[offset] == 0xff) offset++;
            if (offset >= header.Length) return false;
            var marker = header[offset++];
            if (marker is 0xd8 or 0xd9 or 0x01 || marker is >= 0xd0 and <= 0xd7) continue;
            if (offset + 2 > header.Length) return false;
            var segmentLength = BinaryPrimitives.ReadUInt16BigEndian(header.Slice(offset, 2));
            if (segmentLength < 2 || offset + segmentLength > header.Length) return false;
            if (IsStartOfFrame(marker) && segmentLength >= 7)
            {
                height = BinaryPrimitives.ReadUInt16BigEndian(header.Slice(offset + 3, 2));
                width = BinaryPrimitives.ReadUInt16BigEndian(header.Slice(offset + 5, 2));
                return width > 0 && height > 0;
            }
            offset += segmentLength;
        }
        return false;
    }

    private static bool IsStartOfFrame(byte marker) =>
        marker is 0xc0 or 0xc1 or 0xc2 or 0xc3 or
            0xc5 or 0xc6 or 0xc7 or 0xc9 or 0xca or 0xcb or
            0xcd or 0xce or 0xcf;

    private static bool TryReadWebpDimensions(
        ReadOnlySpan<byte> header,
        out int width,
        out int height)
    {
        width = 0;
        height = 0;
        if (header.Length < 20 || !header[..4].SequenceEqual("RIFF"u8) ||
            !header.Slice(8, 4).SequenceEqual("WEBP"u8))
            return false;

        var offset = 12;
        while (offset + 8 <= header.Length)
        {
            var type = header.Slice(offset, 4);
            var length = BinaryPrimitives.ReadUInt32LittleEndian(header.Slice(offset + 4, 4));
            var payload = offset + 8;
            if (length > int.MaxValue || payload + (long)length > header.Length) return false;
            if (type.SequenceEqual("VP8X"u8) && length >= 10)
            {
                width = 1 + ReadUInt24LittleEndian(header.Slice(payload + 4, 3));
                height = 1 + ReadUInt24LittleEndian(header.Slice(payload + 7, 3));
                return width > 0 && height > 0;
            }
            if (type.SequenceEqual("VP8L"u8) && length >= 5 && header[payload] == 0x2f)
            {
                var bits = BinaryPrimitives.ReadUInt32LittleEndian(header.Slice(payload + 1, 4));
                width = 1 + (int)(bits & 0x3fff);
                height = 1 + (int)((bits >> 14) & 0x3fff);
                return width > 0 && height > 0;
            }
            if (type.SequenceEqual("VP8 "u8) && length >= 10 &&
                header.Slice(payload + 3, 3).SequenceEqual(new byte[] { 0x9d, 0x01, 0x2a }))
            {
                width = BinaryPrimitives.ReadUInt16LittleEndian(header.Slice(payload + 6, 2)) & 0x3fff;
                height = BinaryPrimitives.ReadUInt16LittleEndian(header.Slice(payload + 8, 2)) & 0x3fff;
                return width > 0 && height > 0;
            }
            offset = payload + (int)length + ((int)length & 1);
        }
        return false;
    }

    private static int ReadUInt24LittleEndian(ReadOnlySpan<byte> value) =>
        value[0] | value[1] << 8 | value[2] << 16;

    private static ProjectAssetInspection Invalid(
        ProjectAssetInspectionFailure failure,
        long actualLength) => new(false, failure, actualLength, null, null);
}
