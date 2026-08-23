using System.Buffers;
using System.Security.Cryptography;
using FundingPlatform.Application.SourceDocuments;

namespace FundingPlatform.Infrastructure.SourceDocuments.Inspection;

public sealed class StreamingPdfContentInspector : ISourceDocumentContentInspector
{
    private static ReadOnlySpan<byte> PdfHeader => "%PDF-"u8;
    private static ReadOnlySpan<byte> PdfEndMarker => "%%EOF"u8;

    public async Task<SourceDocumentInspection> InspectPdfAsync(
        SourceBlobRead source,
        long expectedLength,
        long maximumLength,
        CancellationToken cancellationToken)
    {
        if (source.ContentLength > maximumLength)
            return Invalid(SourceDocumentInspectionFailure.TooLarge, source.ContentLength);
        if (source.ContentLength != expectedLength)
            return Invalid(SourceDocumentInspectionFailure.LengthMismatch, source.ContentLength);
        if (!string.Equals(source.ContentType?.Trim(), "application/pdf",
                StringComparison.OrdinalIgnoreCase))
            return Invalid(SourceDocumentInspectionFailure.InvalidContentType, source.ContentLength);

        var rented = ArrayPool<byte>.Shared.Rent(64 * 1024);
        var header = new byte[PdfHeader.Length];
        var tail = new byte[2048];
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
                    return Invalid(SourceDocumentInspectionFailure.TooLarge, total + read);
                var headerRemaining = header.Length - (int)Math.Min(total, header.Length);
                if (headerRemaining > 0)
                {
                    var copy = Math.Min(headerRemaining, read);
                    rented.AsSpan(0, copy).CopyTo(header.AsSpan((int)total, copy));
                }

                hash.AppendData(rented, 0, read);
                for (var index = 0; index < read; index++)
                {
                    tail[tailOffset] = rented[index];
                    tailOffset = (tailOffset + 1) % tail.Length;
                    tailCount = Math.Min(tailCount + 1, tail.Length);
                }
                total += read;
            }

            if (total != expectedLength)
                return Invalid(SourceDocumentInspectionFailure.LengthMismatch, total);
            if (!header.AsSpan().SequenceEqual(PdfHeader))
                return Invalid(SourceDocumentInspectionFailure.InvalidPdf, total);

            var orderedTail = new byte[tailCount];
            var start = tailCount == tail.Length ? tailOffset : 0;
            for (var index = 0; index < tailCount; index++)
                orderedTail[index] = tail[(start + index) % tail.Length];
            if (!HasValidEndMarker(orderedTail))
                return Invalid(SourceDocumentInspectionFailure.InvalidPdf, total);

            return new SourceDocumentInspection(
                true,
                SourceDocumentInspectionFailure.None,
                total,
                hash.GetHashAndReset(),
                "application/pdf");
        }
        finally
        {
            CryptographicOperations.ZeroMemory(rented.AsSpan(0, rented.Length));
            ArrayPool<byte>.Shared.Return(rented);
        }
    }

    private static bool HasValidEndMarker(ReadOnlySpan<byte> tail)
    {
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

    private static SourceDocumentInspection Invalid(
        SourceDocumentInspectionFailure failure,
        long actualLength) => new(false, failure, actualLength, null, null);
}
