using Azure;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Infrastructure.SourceDocuments.Storage;

namespace FundingPlatform.Infrastructure.SourceDocuments.Extraction;

public sealed class AzureTrustedSourceDocumentReader(
    BlobServiceClient serviceClient,
    string trustedContainer) : ISourceDocumentExtractionBlobReader
{
    private readonly string trustedContainer = ValidateContainer(trustedContainer);

    public async Task<SourceBlobRead> OpenTrustedReadAsync(
        ProtectedBlobLocation source,
        string expectedETag,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(source);
        if (!string.Equals(source.Container, trustedContainer, StringComparison.Ordinal) ||
            string.IsNullOrWhiteSpace(source.ObjectName) || source.ObjectName.Length > 1_024 ||
            source.ObjectName[0] == '/' || source.ObjectName.Contains('?') ||
            source.ObjectName.Contains('#') || source.ObjectName.Contains('\r') ||
            source.ObjectName.Contains('\n') || source.ObjectName.Contains('\0') ||
            !BlobETagNormalizer.TryNormalize(expectedETag, out var normalizedETag))
        {
            throw new SourceDocumentStorageException(
                "open-trusted-read", "trusted-location-rejected", 400);
        }

        try
        {
            var client = serviceClient.GetBlobContainerClient(trustedContainer)
                .GetBlobClient(source.ObjectName);
            var conditions = new BlobRequestConditions { IfMatch = new ETag(normalizedETag) };
            var properties = (await client.GetPropertiesAsync(
                conditions, cancellationToken)).Value;
            var stream = await client.OpenReadAsync(
                new BlobOpenReadOptions(allowModifications: false)
                {
                    Conditions = conditions
                },
                cancellationToken);
            return new SourceBlobRead(
                new SanitizedAzureReadStream(stream),
                properties.ContentLength,
                properties.ContentType,
                BlobETagNormalizer.NormalizeRequired(properties.ETag.ToString()),
                properties.VersionId);
        }
        catch (RequestFailedException exception)
        {
            throw new SourceDocumentStorageException(
                "open-trusted-read",
                exception.Status == 404 ? "trusted-blob-not-found" : "azure-storage-failed",
                exception.Status);
        }
    }

    private static string ValidateContainer(string value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Length is < 3 or > 63 ||
            !IsAlphaNumeric(value[0]) || !IsAlphaNumeric(value[^1]) ||
            value.Contains("--", StringComparison.Ordinal) ||
            value.Any(character => character != '-' &&
                (character < 'a' || character > 'z') &&
                (character < '0' || character > '9')))
        {
            throw new InvalidOperationException("The trusted extraction container is invalid.");
        }

        return value;
    }

    private static bool IsAlphaNumeric(char value) =>
        value is >= 'a' and <= 'z' or >= '0' and <= '9';
}
