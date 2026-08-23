using System.Buffers;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Application.SourceDocuments;
using UglyToad.PdfPig;
using UglyToad.PdfPig.DocumentLayoutAnalysis.TextExtractor;

namespace FundingPlatform.ExtractionWorkers.Extraction;

/// <summary>
/// Extracts text only from a blob that has already passed the trusted-storage gate.
/// Pdf actions, attachments, links, scripts and embedded files are never executed or exported.
/// </summary>
public sealed class SecurePdfTextExtractor : ISourceDocumentTextExtractor
{
    public async Task<SourceDocumentTextExtraction> ExtractPdfAsync(
        SourceBlobRead source,
        SourceDocumentExtractionPolicy policy,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(source);
        ArgumentNullException.ThrowIfNull(policy);
        if (source.ContentLength is < 1 || source.ContentLength > policy.MaximumBytes ||
            source.ContentLength > int.MaxValue)
        {
            throw new InvalidDataException("The trusted PDF exceeds the extraction limit.");
        }

        var bytes = new byte[checked((int)source.ContentLength)];
        using var sourceHash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        var rented = ArrayPool<byte>.Shared.Rent(64 * 1024);
        var offset = 0;
        try
        {
            while (offset < bytes.Length)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var requested = Math.Min(rented.Length, bytes.Length - offset);
                var read = await source.Content.ReadAsync(
                    rented.AsMemory(0, requested), cancellationToken);
                if (read == 0) break;
                rented.AsSpan(0, read).CopyTo(bytes.AsSpan(offset, read));
                sourceHash.AppendData(rented, 0, read);
                offset += read;
            }
            if (offset != bytes.Length ||
                await source.Content.ReadAsync(rented.AsMemory(0, 1), cancellationToken) != 0)
            {
                throw new InvalidDataException("The trusted PDF length changed while reading.");
            }
        }
        finally
        {
            CryptographicOperations.ZeroMemory(rented.AsSpan());
            ArrayPool<byte>.Shared.Return(rented);
        }

        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            using var document = PdfDocument.Open(bytes, new ParsingOptions
            {
                MaxStackDepth = policy.MaximumStackDepth,
                SkipMissingFonts = true,
                UseActualText = false
            });
            if (document.NumberOfPages is < 1 || document.NumberOfPages > policy.MaximumPages)
            {
                throw new InvalidDataException("The PDF page count exceeds the extraction limit.");
            }

            var text = new StringBuilder(Math.Min(policy.MaximumCharacters, 64 * 1024));
            var truncated = false;
            for (var pageNumber = 1; pageNumber <= document.NumberOfPages; pageNumber++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var pageText = ContentOrderTextExtractor.GetText(document.GetPage(pageNumber));
                AppendSanitized(text, pageText, policy.MaximumCharacters, ref truncated);
                if (pageNumber < document.NumberOfPages && text.Length < policy.MaximumCharacters)
                {
                    text.Append('\n');
                }
            }

            var normalized = RemoveUnsafeUnicode(
                text.ToString().Normalize(NormalizationForm.FormKC));
            if (normalized.Length > policy.MaximumCharacters)
            {
                var length = policy.MaximumCharacters;
                if (length > 0 && length < normalized.Length &&
                    char.IsHighSurrogate(normalized[length - 1]) &&
                    char.IsLowSurrogate(normalized[length]))
                {
                    length--;
                }
                normalized = normalized[..length];
                truncated = true;
            }
            normalized = LimitUtf8(normalized, policy.MaximumUtf8Bytes, ref truncated);
            var textBytes = Encoding.UTF8.GetBytes(normalized);
            return new SourceDocumentTextExtraction(
                normalized,
                sourceHash.GetHashAndReset(),
                SHA256.HashData(textBytes),
                document.NumberOfPages,
                normalized.Length,
                truncated);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(bytes);
        }
    }

    private static string LimitUtf8(string value, int maximumBytes, ref bool truncated)
    {
        if (Encoding.UTF8.GetByteCount(value) <= maximumBytes) return value;
        var result = new StringBuilder(Math.Min(value.Length, maximumBytes));
        var byteCount = 0;
        foreach (var rune in value.EnumerateRunes())
        {
            var runeBytes = rune.Utf8SequenceLength;
            if (byteCount + runeBytes > maximumBytes) break;
            result.Append(rune.ToString());
            byteCount += runeBytes;
        }
        truncated = true;
        return result.ToString();
    }

    internal static string RemoveUnsafeUnicode(string value)
    {
        var result = new StringBuilder(value.Length);
        foreach (var rune in value.EnumerateRunes())
        {
            if (rune.Value is '\n' or '\t')
            {
                result.Append(rune.ToString());
                continue;
            }
            var category = Rune.GetUnicodeCategory(rune);
            if (category is UnicodeCategory.Control or UnicodeCategory.Format or
                UnicodeCategory.Surrogate or UnicodeCategory.PrivateUse or
                UnicodeCategory.OtherNotAssigned)
                continue;
            result.Append(rune.ToString());
        }
        return result.ToString();
    }

    internal static void AppendSanitized(
        StringBuilder target,
        string source,
        int maximumCharacters,
        ref bool truncated)
    {
        var previousWasCarriageReturn = false;
        foreach (var character in source)
        {
            if (target.Length >= maximumCharacters)
            {
                truncated = true;
                return;
            }

            if (character == '\r')
            {
                target.Append('\n');
                previousWasCarriageReturn = true;
            }
            else if (character == '\n')
            {
                if (!previousWasCarriageReturn) target.Append('\n');
                previousWasCarriageReturn = false;
            }
            else if (character == '\t')
            {
                target.Append(character);
                previousWasCarriageReturn = false;
            }
            else if (!char.IsControl(character) && character != '\0')
            {
                target.Append(character);
                previousWasCarriageReturn = false;
            }
            else previousWasCarriageReturn = false;
        }
    }
}
