namespace FundingPlatform.Application.SourceDocuments;

public static class BlobETagNormalizer
{
    public static bool TryNormalize(string? value, out string normalized)
    {
        normalized = string.Empty;
        var candidate = value?.Trim();
        if (string.IsNullOrEmpty(candidate)) return false;
        if (candidate.StartsWith("W/", StringComparison.OrdinalIgnoreCase))
            candidate = candidate[2..].Trim();
        if (candidate.Length >= 2 && candidate[0] == '"' && candidate[^1] == '"')
            candidate = candidate[1..^1];
        if (candidate.Length is < 1 or > 80 ||
            candidate.Any(character => character is < (char)0x21 or > (char)0x7e ||
                                       character is '"' or '\\' or ','))
            return false;
        normalized = $"\"{candidate}\"";
        return true;
    }

    public static string NormalizeRequired(string value) =>
        TryNormalize(value, out var normalized)
            ? normalized
            : throw new SourceDocumentStorageException(
                "normalize-etag", "invalid-blob-etag", 409);
}
