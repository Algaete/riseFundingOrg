using System.Security.Cryptography;
using Azure;
using Azure.Core;
using Azure.Storage;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Sas;
using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Infrastructure.ProjectAssets.Configuration;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Infrastructure.ProjectAssets.Storage;

public sealed class AzureProjectAssetBlobStore : IProjectAssetBlobStore, IDisposable
{
    private const string ContentHashMetadata = "fp-content-sha256";
    private const string SourceHashMetadata = "fp-source-sha256";
    private const string ProcessingVersionMetadata = "fp-processing-version";
    private readonly BlobServiceClient? serviceClient;
    private readonly TimeProvider timeProvider;
    private readonly SemaphoreSlim delegationKeyLock = new(1, 1);
    private UserDelegationKey? delegationKey;

    public AzureProjectAssetBlobStore(
        TokenCredential credential,
        IOptions<ProjectAssetOptions> options,
        TimeProvider timeProvider)
    {
        this.timeProvider = timeProvider;
        if (options.Value.Enabled &&
            Uri.TryCreate(options.Value.BlobServiceUri, UriKind.Absolute, out var endpoint))
            serviceClient = new BlobServiceClient(endpoint, credential);
    }

    public async Task<ProjectAssetUploadGrant> CreateUploadGrantAsync(
        ProtectedProjectAssetBlobLocation destination,
        string contentType,
        DateTimeOffset expiresAtUtc,
        CancellationToken cancellationToken)
    {
        var client = RequireClient();
        try
        {
            var now = timeProvider.GetUtcNow();
            var key = await GetDelegationKeyAsync(client, now, expiresAtUtc, cancellationToken);
            var sasBuilder = new BlobSasBuilder
            {
                BlobContainerName = destination.Container,
                BlobName = destination.ObjectName,
                Resource = "b",
                StartsOn = now.AddMinutes(-5),
                ExpiresOn = expiresAtUtc,
                Protocol = SasProtocol.Https
            };
            sasBuilder.SetPermissions(BlobSasPermissions.Create);
            var query = sasBuilder.ToSasQueryParameters(key, client.AccountName);
            var blob = GetBlobClient(client, destination);
            return new ProjectAssetUploadGrant(
                new UriBuilder(blob.Uri) { Query = query.ToString() }.Uri,
                expiresAtUtc,
                new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
                {
                    ["x-ms-blob-type"] = "BlockBlob",
                    ["Content-Type"] = contentType,
                    ["If-None-Match"] = "*"
                });
        }
        catch (RequestFailedException exception)
        {
            throw StorageFailure("create-upload-grant", exception);
        }
    }

    public async Task<ProjectAssetBlobRead> OpenReadAsync(
        ProtectedProjectAssetBlobLocation source,
        string? expectedETag,
        CancellationToken cancellationToken)
    {
        var client = RequireClient();
        try
        {
            var blob = GetBlobClient(client, source);
            var conditions = Conditions(expectedETag);
            var properties = (await blob.GetPropertiesAsync(conditions, cancellationToken)).Value;
            var stream = await blob.OpenReadAsync(
                new BlobOpenReadOptions(allowModifications: false) { Conditions = conditions },
                cancellationToken);
            return new ProjectAssetBlobRead(
                new ProjectAssetSanitizedAzureReadStream(stream),
                properties.ContentLength,
                properties.ContentType,
                NormalizeETag(properties.ETag.ToString()),
                properties.VersionId);
        }
        catch (RequestFailedException exception)
        {
            throw StorageFailure("open-read", exception);
        }
    }

    public async Task<ProjectAssetBlobReceipt> EnsureCopyAsync(
        ProtectedProjectAssetBlobLocation source,
        string sourceETag,
        ProtectedProjectAssetBlobLocation destination,
        string contentType,
        long expectedLength,
        byte[] expectedContentHash,
        CancellationToken cancellationToken)
    {
        var client = RequireClient();
        var existing = await GetVerifiedReceiptAsync(
            client, destination, null, contentType, expectedLength, expectedContentHash,
            cancellationToken);
        if (existing is not null) return existing;

        await using var sourceRead = await OpenReadAsync(source, sourceETag, cancellationToken);
        if (sourceRead.ContentLength != expectedLength ||
            !string.Equals(sourceRead.ContentType, contentType, StringComparison.OrdinalIgnoreCase))
            throw new ProjectAssetStorageException("copy", "content-conflict", 409);

        try
        {
            var response = await GetBlobClient(client, destination).UploadAsync(
                sourceRead.Content,
                new BlobUploadOptions
                {
                    HttpHeaders = new BlobHttpHeaders
                    {
                        ContentType = contentType,
                        ContentDisposition = "attachment"
                    },
                    Metadata = new Dictionary<string, string>
                    {
                        [ContentHashMetadata] = Convert.ToHexString(expectedContentHash)
                    },
                    Conditions = new BlobRequestConditions { IfNoneMatch = ETag.All },
                    TransferOptions = new StorageTransferOptions
                    {
                        InitialTransferSize = 4 * 1024 * 1024,
                        MaximumTransferSize = 4 * 1024 * 1024,
                        MaximumConcurrency = 1
                    }
                },
                cancellationToken);
            return new ProjectAssetBlobReceipt(
                NormalizeETag(response.Value.ETag.ToString()),
                response.Value.VersionId);
        }
        catch (RequestFailedException exception) when (exception.Status is 409 or 412)
        {
            return await GetVerifiedReceiptAsync(
                       client, destination, null, contentType, expectedLength, expectedContentHash,
                       cancellationToken)
                   ?? throw new ProjectAssetStorageException("copy", "content-conflict", 409);
        }
        catch (RequestFailedException exception)
        {
            throw StorageFailure("copy", exception);
        }
    }

    public Task<ProjectAssetBlobReceipt?> GetVerifiedReceiptAsync(
        ProtectedProjectAssetBlobLocation location,
        string contentType,
        long expectedLength,
        byte[] expectedContentHash,
        CancellationToken cancellationToken) => GetVerifiedReceiptAsync(
        RequireClient(),
        location,
        null,
        contentType,
        expectedLength,
        expectedContentHash,
        cancellationToken);

    public async Task<ProjectAssetBlobReceipt> EnsureUploadAsync(
        ProtectedProjectAssetBlobLocation destination,
        ReadOnlyMemory<byte> content,
        string contentType,
        byte[] expectedContentHash,
        byte[] sourceContentHash,
        string processingVersion,
        CancellationToken cancellationToken)
    {
        if (content.Length < 1 || expectedContentHash is not { Length: 32 } ||
            sourceContentHash is not { Length: 32 } ||
            processingVersion.Length is < 1 or > 100 ||
            processingVersion.Any(character =>
                !(character is >= 'a' and <= 'z' or >= '0' and <= '9' or '-' or '.')))
            throw new ProjectAssetStorageException(
                "sanitized-upload", "invalid-sanitized-content", 409);

        var actualHash = SHA256.HashData(content.Span);
        if (!CryptographicOperations.FixedTimeEquals(actualHash, expectedContentHash))
            throw new ProjectAssetStorageException(
                "sanitized-upload", "sanitized-content-hash-mismatch", 409);

        var client = RequireClient();
        var existing = await GetVerifiedSanitizedReceiptAsync(
            client,
            destination,
            contentType,
            content.Length,
            expectedContentHash,
            sourceContentHash,
            processingVersion,
            cancellationToken);
        if (existing is not null) return existing;

        try
        {
            await using var stream = new MemoryStream(content.ToArray(), writable: false);
            var response = await GetBlobClient(client, destination).UploadAsync(
                stream,
                new BlobUploadOptions
                {
                    HttpHeaders = new BlobHttpHeaders
                    {
                        ContentType = contentType,
                        ContentDisposition = "attachment"
                    },
                    Metadata = new Dictionary<string, string>
                    {
                        [ContentHashMetadata] = Convert.ToHexString(expectedContentHash),
                        [SourceHashMetadata] = Convert.ToHexString(sourceContentHash),
                        [ProcessingVersionMetadata] = processingVersion
                    },
                    Conditions = new BlobRequestConditions { IfNoneMatch = ETag.All },
                    TransferOptions = new StorageTransferOptions
                    {
                        InitialTransferSize = 4 * 1024 * 1024,
                        MaximumTransferSize = 4 * 1024 * 1024,
                        MaximumConcurrency = 1
                    }
                },
                cancellationToken);
            return new ProjectAssetBlobReceipt(
                NormalizeETag(response.Value.ETag.ToString()),
                response.Value.VersionId);
        }
        catch (RequestFailedException exception) when (exception.Status is 409 or 412)
        {
            return await GetVerifiedSanitizedReceiptAsync(
                       client,
                       destination,
                       contentType,
                       content.Length,
                       expectedContentHash,
                       sourceContentHash,
                       processingVersion,
                       cancellationToken)
                   ?? throw new ProjectAssetStorageException(
                       "sanitized-upload", "content-conflict", 409);
        }
        catch (RequestFailedException exception)
        {
            throw StorageFailure("sanitized-upload", exception);
        }
    }

    public Task<ProjectAssetBlobReceipt?> GetVerifiedVersionReceiptAsync(
        ProtectedProjectAssetBlobLocation location,
        string versionId,
        string contentType,
        long expectedLength,
        byte[] expectedContentHash,
        CancellationToken cancellationToken) => GetVerifiedReceiptAsync(
        RequireClient(),
        location,
        RequireVersionId(versionId),
        contentType,
        expectedLength,
        expectedContentHash,
        cancellationToken);

    public async Task DeleteIfMatchAsync(
        ProtectedProjectAssetBlobLocation location,
        string? expectedETag,
        CancellationToken cancellationToken)
    {
        var client = RequireClient();
        try
        {
            await GetBlobClient(client, location).DeleteIfExistsAsync(
                DeleteSnapshotsOption.IncludeSnapshots,
                Conditions(expectedETag),
                cancellationToken);
        }
        catch (RequestFailedException exception) when (exception.Status is 404 or 412)
        {
            // Missing or concurrently replaced content is never deleted.
        }
        catch (RequestFailedException exception)
        {
            throw StorageFailure("delete", exception);
        }
    }

    public async Task DeleteVersionIfMatchAsync(
        ProtectedProjectAssetBlobLocation location,
        string versionId,
        string expectedETag,
        CancellationToken cancellationToken)
    {
        var client = RequireClient();
        try
        {
            await GetBlobClient(client, location)
                .WithVersion(RequireVersionId(versionId))
                .DeleteIfExistsAsync(
                    DeleteSnapshotsOption.None,
                    Conditions(expectedETag),
                    cancellationToken);
        }
        catch (RequestFailedException exception) when (exception.Status is 404 or 412)
        {
            // The caller verifies absence afterward. A changed immutable version is never
            // deleted using a broader condition.
        }
        catch (RequestFailedException exception)
        {
            throw StorageFailure("delete-version", exception);
        }
    }

    public void Dispose() => delegationKeyLock.Dispose();

    private BlobServiceClient RequireClient() => serviceClient ??
        throw new ProjectAssetStorageException("configuration", "project-assets-disabled", 503);

    private async Task<UserDelegationKey> GetDelegationKeyAsync(
        BlobServiceClient client,
        DateTimeOffset now,
        DateTimeOffset requiredExpiry,
        CancellationToken cancellationToken)
    {
        if (delegationKey is not null &&
            delegationKey.SignedExpiresOn > requiredExpiry.AddMinutes(1))
            return delegationKey;

        await delegationKeyLock.WaitAsync(cancellationToken);
        try
        {
            if (delegationKey is not null &&
                delegationKey.SignedExpiresOn > requiredExpiry.AddMinutes(1))
                return delegationKey;
            delegationKey = (await client.GetUserDelegationKeyAsync(
                now.AddMinutes(-5), now.AddHours(1), cancellationToken)).Value;
            return delegationKey;
        }
        finally
        {
            delegationKeyLock.Release();
        }
    }

    private static async Task<ProjectAssetBlobReceipt?> GetVerifiedReceiptAsync(
        BlobServiceClient client,
        ProtectedProjectAssetBlobLocation location,
        string? versionId,
        string contentType,
        long expectedLength,
        byte[] expectedContentHash,
        CancellationToken cancellationToken)
    {
        try
        {
            var blob = GetBlobClient(client, location);
            if (versionId is not null) blob = blob.WithVersion(versionId);
            var properties = (await blob.GetPropertiesAsync(
                cancellationToken: cancellationToken)).Value;
            var storedHash = properties.Metadata.FirstOrDefault(pair => string.Equals(
                pair.Key, ContentHashMetadata, StringComparison.OrdinalIgnoreCase)).Value;
            if (properties.ContentLength != expectedLength ||
                !string.Equals(properties.ContentType, contentType, StringComparison.OrdinalIgnoreCase) ||
                !TryReadHash(storedHash, out var actualHash) ||
                !CryptographicOperations.FixedTimeEquals(actualHash, expectedContentHash))
                throw new ProjectAssetStorageException("verify-copy", "content-conflict", 409);
            return new ProjectAssetBlobReceipt(
                NormalizeETag(properties.ETag.ToString()),
                properties.VersionId);
        }
        catch (RequestFailedException exception) when (exception.Status == 404)
        {
            return null;
        }
        catch (RequestFailedException exception)
        {
            throw StorageFailure("verify-copy", exception);
        }
    }

    private static async Task<ProjectAssetBlobReceipt?> GetVerifiedSanitizedReceiptAsync(
        BlobServiceClient client,
        ProtectedProjectAssetBlobLocation location,
        string contentType,
        long expectedLength,
        byte[] expectedContentHash,
        byte[] sourceContentHash,
        string processingVersion,
        CancellationToken cancellationToken)
    {
        try
        {
            var properties = (await GetBlobClient(client, location).GetPropertiesAsync(
                cancellationToken: cancellationToken)).Value;
            var storedHash = MetadataValue(properties.Metadata, ContentHashMetadata);
            var storedSourceHash = MetadataValue(properties.Metadata, SourceHashMetadata);
            var storedProcessingVersion = MetadataValue(
                properties.Metadata, ProcessingVersionMetadata);
            if (properties.ContentLength != expectedLength ||
                !string.Equals(
                    properties.ContentType, contentType, StringComparison.OrdinalIgnoreCase) ||
                !TryReadHash(storedHash, out var actualHash) ||
                !TryReadHash(storedSourceHash, out var actualSourceHash) ||
                !CryptographicOperations.FixedTimeEquals(actualHash, expectedContentHash) ||
                !CryptographicOperations.FixedTimeEquals(actualSourceHash, sourceContentHash) ||
                !string.Equals(
                    storedProcessingVersion, processingVersion, StringComparison.Ordinal))
                throw new ProjectAssetStorageException(
                    "verify-sanitized-upload", "content-conflict", 409);
            return new ProjectAssetBlobReceipt(
                NormalizeETag(properties.ETag.ToString()),
                properties.VersionId);
        }
        catch (RequestFailedException exception) when (exception.Status == 404)
        {
            return null;
        }
        catch (RequestFailedException exception)
        {
            throw StorageFailure("verify-sanitized-upload", exception);
        }
    }

    private static string? MetadataValue(
        IDictionary<string, string> metadata,
        string key) => metadata.FirstOrDefault(pair => string.Equals(
            pair.Key, key, StringComparison.OrdinalIgnoreCase)).Value;

    private static BlobClient GetBlobClient(
        BlobServiceClient client,
        ProtectedProjectAssetBlobLocation location) =>
        client.GetBlobContainerClient(location.Container).GetBlobClient(location.ObjectName);

    private static BlobRequestConditions? Conditions(string? expectedETag) =>
        string.IsNullOrWhiteSpace(expectedETag)
            ? null
            : new BlobRequestConditions { IfMatch = new ETag(NormalizeETag(expectedETag)) };

    private static string NormalizeETag(string value)
    {
        if (BlobETagNormalizer.TryNormalize(value, out var normalized)) return normalized;
        throw new ProjectAssetStorageException("etag", "invalid-blob-etag", 409);
    }

    private static string RequireVersionId(string value)
    {
        if (value.Length is < 1 or > 200 || value.Any(char.IsControl) ||
            value.Contains('&') || value.Contains('#') || value.Contains('?'))
            throw new ProjectAssetStorageException("version", "invalid-blob-version", 409);
        return value;
    }

    private static bool TryReadHash(string? value, out byte[] hash)
    {
        hash = [];
        try
        {
            if (value?.Length != 64) return false;
            hash = Convert.FromHexString(value);
            return hash.Length == 32;
        }
        catch (FormatException)
        {
            return false;
        }
    }

    private static ProjectAssetStorageException StorageFailure(
        string operation,
        RequestFailedException exception) => new(
            operation,
            exception.Status == 404 ? "blob-not-found" : "azure-storage-failed",
            exception.Status,
            exception);
}

internal sealed class ProjectAssetSanitizedAzureReadStream(Stream inner) : Stream
{
    public override bool CanRead => inner.CanRead;
    public override bool CanSeek => inner.CanSeek;
    public override bool CanWrite => false;
    public override long Length => inner.Length;
    public override long Position { get => inner.Position; set => inner.Position = value; }
    public override void Flush() => inner.Flush();
    public override int Read(byte[] buffer, int offset, int count)
    {
        try { return inner.Read(buffer, offset, count); }
        catch (RequestFailedException exception) { throw Failure(exception); }
    }
    public override int Read(Span<byte> buffer)
    {
        try { return inner.Read(buffer); }
        catch (RequestFailedException exception) { throw Failure(exception); }
    }
    public override ValueTask<int> ReadAsync(
        Memory<byte> buffer,
        CancellationToken cancellationToken = default) => ReadCoreAsync(buffer, cancellationToken);
    public override Task<int> ReadAsync(
        byte[] buffer,
        int offset,
        int count,
        CancellationToken cancellationToken) =>
        ReadArrayCoreAsync(buffer, offset, count, cancellationToken);
    public override long Seek(long offset, SeekOrigin origin) => inner.Seek(offset, origin);
    public override void SetLength(long value) => throw new NotSupportedException();
    public override void Write(byte[] buffer, int offset, int count) =>
        throw new NotSupportedException();
    protected override void Dispose(bool disposing)
    {
        if (disposing) inner.Dispose();
        base.Dispose(disposing);
    }
    public override async ValueTask DisposeAsync()
    {
        await inner.DisposeAsync();
        GC.SuppressFinalize(this);
    }

    private async ValueTask<int> ReadCoreAsync(
        Memory<byte> buffer,
        CancellationToken cancellationToken)
    {
        try { return await inner.ReadAsync(buffer, cancellationToken); }
        catch (RequestFailedException exception) { throw Failure(exception); }
    }

    private async Task<int> ReadArrayCoreAsync(
        byte[] buffer,
        int offset,
        int count,
        CancellationToken cancellationToken)
    {
        try { return await inner.ReadAsync(buffer, offset, count, cancellationToken); }
        catch (RequestFailedException exception) { throw Failure(exception); }
    }

    private static ProjectAssetStorageException Failure(RequestFailedException exception) =>
        new("stream-read", exception.Status == 404 ? "blob-not-found" : "azure-storage-failed",
            exception.Status, exception);
}
