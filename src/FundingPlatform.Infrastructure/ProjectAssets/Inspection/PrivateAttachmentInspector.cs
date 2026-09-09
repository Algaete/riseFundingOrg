using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Application.ProjectAssets;

namespace FundingPlatform.Infrastructure.ProjectAssets.Inspection;

/// <summary>Bounded envelope validation, not video decoding or sanitization. Originals stay private.</summary>
internal static class PrivateAttachmentInspector
{
    internal const long TextLimit = 1_048_576;
    internal const long VideoLimit = 26_214_400;
    public static async Task<ProjectAssetInspection> InspectAsync(ProjectAssetBlobRead source, long expectedLength, long maximumLength, string mime, CancellationToken token)
    {
        var maximum = Math.Min(maximumLength, mime == "text/plain" ? TextLimit : VideoLimit);
        if (expectedLength < 1 || expectedLength > maximum)
            return Invalid(ProjectAssetInspectionFailure.TooLarge, expectedLength);
        var content = new byte[(int)expectedLength];
        try
        {
            var offset = 0;
            while (offset < content.Length)
            {
                var read = await source.Content.ReadAsync(content.AsMemory(offset, Math.Min(65536, content.Length - offset)), token);
                if (read == 0) return Invalid(ProjectAssetInspectionFailure.LengthMismatch, offset);
                offset += read;
            }
            var extra = new byte[1];
            if (await source.Content.ReadAsync(extra, token) != 0) return Invalid(ProjectAssetInspectionFailure.LengthMismatch, expectedLength + 1);
            var valid = mime == "text/plain" ? IsUtf8Text(content) : IsMp4(content);
            return valid ? new(true, ProjectAssetInspectionFailure.None, expectedLength, SHA256.HashData(content), mime)
                : Invalid(ProjectAssetInspectionFailure.InvalidFile, expectedLength);
        }
        finally { CryptographicOperations.ZeroMemory(content); }
    }
    private static bool IsUtf8Text(byte[] content)
    {
        try { return !new UTF8Encoding(false, true).GetString(content).Any(c => char.IsControl(c) && c is not ('\t' or '\r' or '\n')); }
        catch (DecoderFallbackException) { return false; }
    }
    private static bool IsMp4(ReadOnlySpan<byte> content)
    {
        var offset = 0; var boxes = 0; var fileType = false; var movie = false; var media = false;
        while (offset < content.Length)
        {
            if (++boxes > 4096 || !TryBox(content, offset, out var length, out var header)) return false;
            var type = content.Slice(offset + 4, 4); var body = content.Slice(offset + header, length - header);
            if (offset == 0 && !type.SequenceEqual("ftyp"u8)) return false;
            if (type.SequenceEqual("ftyp"u8))
            {
                if (fileType || body.Length is < 8 or > 1024 || body.Length % 4 != 0) return false;
                fileType = body[..4].SequenceEqual("isom"u8) || body[..4].SequenceEqual("iso2"u8) || body[..4].SequenceEqual("mp41"u8) || body[..4].SequenceEqual("mp42"u8) || body[..4].SequenceEqual("avc1"u8);
                if (!fileType) return false;
            }
            else if (type.SequenceEqual("moov"u8))
            {
                if (movie || !ValidMovie(body)) return false;
                movie = true;
            }
            else if (type.SequenceEqual("mdat"u8)) { if (body.IsEmpty) return false; media = true; }
            else if (!type.SequenceEqual("free"u8) && !type.SequenceEqual("skip"u8) && !type.SequenceEqual("wide"u8)) return false;
            offset += length;
        }
        return fileType && movie && media;
    }
    private static bool ValidMovie(ReadOnlySpan<byte> body)
    {
        var offset = 0; var count = 0; var movieHeader = false; var video = false;
        while (offset < body.Length)
        {
            if (++count > 4096 || !TryBox(body, offset, out var length, out var header)) return false;
            var type = body.Slice(offset + 4, 4); var payload = body.Slice(offset + header, length - header);
            if (type.SequenceEqual("mvhd"u8))
            {
                if (movieHeader || payload.Length < 100 || payload[0] > 1 || payload[0] == 1 && payload.Length < 112) return false;
                movieHeader = true;
            }
            if (type.SequenceEqual("trak"u8))
            {
                if (!ValidTrack(payload, 0, out var hasVideo)) return false;
                video |= hasVideo;
            }
            offset += length;
        }
        return movieHeader && video;
    }
    private static bool ValidTrack(ReadOnlySpan<byte> body, int depth, out bool hasVideo)
    {
        hasVideo = false;
        if (depth > 2) return false;
        var offset = 0; var count = 0;
        while (offset < body.Length)
        {
            if (++count > 4096 || !TryBox(body, offset, out var length, out var header)) return false;
            var type = body.Slice(offset + 4, 4); var payload = body.Slice(offset + header, length - header);
            if (type.SequenceEqual("hdlr"u8) && depth == 1)
            {
                if (payload.Length < 24) return false;
                hasVideo |= payload.Slice(8, 4).SequenceEqual("vide"u8);
            }
            if (type.SequenceEqual("mdia"u8) && depth == 0)
            {
                if (!ValidTrack(payload, depth + 1, out var nestedVideo)) return false;
                hasVideo |= nestedVideo;
            }
            offset += length;
        }
        return true;
    }
    private static bool TryBox(ReadOnlySpan<byte> content, int offset, out int length, out int header)
    {
        length = 0; header = 8;
        if (content.Length - offset < 8) return false;
        ulong size = BinaryPrimitives.ReadUInt32BigEndian(content.Slice(offset, 4));
        if (size == 1)
        {
            header = 16; if (content.Length - offset < header) return false;
            size = BinaryPrimitives.ReadUInt64BigEndian(content.Slice(offset + 8, 8));
        }
        else if (size == 0) size = (ulong)(content.Length - offset);
        if (size < (ulong)header || size > (ulong)(content.Length - offset)) return false;
        length = (int)size; return true;
    }
    private static ProjectAssetInspection Invalid(ProjectAssetInspectionFailure failure, long length) => new(false, failure, length, null, null);
}
