using System.Text;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.ExtractionWorkers.Extraction;

namespace FundingPlatform.UnitTests;

public sealed class SecurePdfTextExtractorTests
{
    [Fact]
    public async Task Valid_pdf_without_extractable_text_is_completed_with_errors()
    {
        var bytes = BuildPdf(null);
        await using var source = Read(bytes);

        var result = await new SecurePdfTextExtractor().ExtractPdfAsync(
            source, Policy(bytes.Length), CancellationToken.None);

        Assert.Equal(string.Empty, result.Text);
        Assert.Equal(0, result.CharacterCount);
        Assert.True(result.CompletedWithErrors);
        Assert.Equal(1, result.PageCount);
    }

    [Fact]
    public async Task Extracted_text_is_bounded_after_pdf_materialization()
    {
        var bytes = BuildPdf("ABCDEFGHIJK");
        await using var source = Read(bytes);

        var result = await new SecurePdfTextExtractor().ExtractPdfAsync(
            source, Policy(bytes.Length) with { MaximumCharacters = 5 },
            CancellationToken.None);

        Assert.True(result.WasTruncated);
        Assert.True(result.CharacterCount <= 5);
        Assert.True(Encoding.UTF8.GetByteCount(result.Text) <= 64);
    }

    [Fact]
    public void Sanitizer_collapses_crlf_and_removes_controls_bidi_and_private_use()
    {
        var result = new StringBuilder();
        var truncated = false;

        SecurePdfTextExtractor.AppendSanitized(
            result, "A\r\nB\0\u0001C\u202E\u2066\uE000D", 100, ref truncated);
        var sanitized = SecurePdfTextExtractor.RemoveUnsafeUnicode(
            result.ToString().Normalize(NormalizationForm.FormKC));

        Assert.Equal("A\nBCD", sanitized);
        Assert.False(truncated);
    }

    [Fact]
    public async Task Cancellation_before_read_stops_before_opening_pdf()
    {
        var bytes = BuildPdf("text");
        await using var source = Read(bytes);
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            new SecurePdfTextExtractor().ExtractPdfAsync(
                source, Policy(bytes.Length), cancellation.Token));
    }

    private static byte[] BuildPdf(string? text)
    {
        var content = text is null
            ? string.Empty
            : $"BT /F1 12 Tf 40 760 Td ({text}) Tj ET";
        var objects = new[]
        {
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] " +
            "/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            $"<< /Length {Encoding.ASCII.GetByteCount(content)} >>\nstream\n{content}\nendstream"
        };
        var pdf = new StringBuilder("%PDF-1.4\n");
        var offsets = new List<int> { 0 };
        for (var index = 0; index < objects.Length; index++)
        {
            offsets.Add(Encoding.ASCII.GetByteCount(pdf.ToString()));
            pdf.Append(index + 1).Append(" 0 obj\n")
                .Append(objects[index]).Append("\nendobj\n");
        }
        var xrefOffset = Encoding.ASCII.GetByteCount(pdf.ToString());
        pdf.Append("xref\n0 6\n0000000000 65535 f \n");
        for (var index = 1; index <= 5; index++)
            pdf.Append(offsets[index].ToString("D10", System.Globalization.CultureInfo.InvariantCulture))
                .Append(" 00000 n \n");
        pdf.Append("trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n")
            .Append(xrefOffset).Append("\n%%EOF\n");
        return Encoding.ASCII.GetBytes(pdf.ToString());
    }

    private static SourceBlobRead Read(byte[] bytes) => new(
        new MemoryStream(bytes, writable: false),
        bytes.Length,
        "application/pdf",
        "\"etag\"",
        null);

    private static SourceDocumentExtractionPolicy Policy(long maximumBytes)
    {
        const string code = "fundingplatform-pdf-text";
        const string version = "1-pdfpig-0.1.15";
        const int maximumCharacters = 500;
        const int maximumPages = 10;
        const int maximumUtf8Bytes = 2_000;
        const int maximumStackDepth = 32;
        return new SourceDocumentExtractionPolicy(
            maximumBytes,
            maximumPages,
            maximumCharacters,
            maximumUtf8Bytes,
            maximumStackDepth,
            TimeSpan.FromMinutes(1),
            TimeSpan.FromMinutes(2),
            code,
            version,
            SourceDocumentExtractionSettings.ComputeHash(
                code, version, maximumCharacters, maximumPages,
                maximumUtf8Bytes, maximumStackDepth, maximumBytes));
    }
}
