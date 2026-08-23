using Azure;
using Azure.Storage;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Sas;
using System.Security.Cryptography;
using FundingPlatform.Application.SourceDocuments;

namespace FundingPlatform.Infrastructure.SourceDocuments.Storage;

public sealed class AzureSourceDocumentBlobStore(
    BlobServiceClient serviceClient,
    TimeProvider timeProvider) : ISourceDocumentBlobStore,
    ISourceDocumentRetentionBlobStore, IDisposable
{
    private const string ContentHashMetadata = "fp-content-sha256";
    private const int MaximumVersionDeletesPerAttempt = 500;
    private readonly SemaphoreSlim delegationKeyLock = new(1, 1);
    private UserDelegationKey? delegationKey;

    public async Task<SourceDocumentUploadGrant> CreateUploadGrantAsync(
        ProtectedBlobLocation destination,
        DateTimeOffset expiresAtUtc,
        CancellationToken cancellationToken)
    {
        try
        {
            var now = timeProvider.GetUtcNow();
            var key = await GetDelegationKeyAsync(now, expiresAtUtc, cancellationToken);
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
            var query = sasBuilder.ToSasQueryParameters(key, serviceClient.AccountName);
            var blob = GetBlobClient(destination);
            var uri = new UriBuilder(blob.Uri) { Query = query.ToString() }.Uri;
            return new SourceDocumentUploadGrant(
                uri,
                expiresAtUtc,
                new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
                {
                    ["x-ms-blob-type"] = "BlockBlob",
                    ["Content-Type"] = "application/pdf",
                    ["If-None-Match"] = "*"
                });
        }
        catch (RequestFailedException exception)
        {
            throw StorageFailure("create-upload-grant", exception);
        }
    }

    public async Task<SourceBlobRead> OpenReadAsync(
        ProtectedBlobLocation source,
        string? expectedETag,
        CancellationToken cancellationToken)
    {
        try
        {
            var client = GetBlobClient(source);
            var conditions = Conditions(expectedETag);
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
            throw StorageFailure("open-read", exception);
        }
    }

    public async Task<SourceBlobReceipt> EnsureCopyAsync(
        ProtectedBlobLocation source,
        string sourceETag,
        ProtectedBlobLocation destination,
        long expectedLength,
        byte[] expectedContentHash,
        CancellationToken cancellationToken)
    {
        var existing = await GetVerifiedReceiptAsync(
            destination, expectedLength, expectedContentHash, cancellationToken);
        if (existing is not null) return existing;

        await using var sourceRead = await OpenReadAsync(
            source, sourceETag, cancellationToken);
        if (sourceRead.ContentLength != expectedLength)
            throw new SourceDocumentStorageException("copy", "content-conflict", 409);

        try
        {
            var response = await GetBlobClient(destination).UploadAsync(
                sourceRead.Content,
                new BlobUploadOptions
                {
                    HttpHeaders = new BlobHttpHeaders { ContentType = "application/pdf" },
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
            return new SourceBlobReceipt(
                BlobETagNormalizer.NormalizeRequired(response.Value.ETag.ToString()),
                response.Value.VersionId);
        }
        catch (RequestFailedException exception) when (exception.Status is 409 or 412)
        {
            return await GetVerifiedReceiptAsync(
                       destination, expectedLength, expectedContentHash, cancellationToken)
                   ?? throw new SourceDocumentStorageException("copy", "content-conflict", 409);
        }
        catch (RequestFailedException exception)
        {
            throw StorageFailure("copy", exception);
        }
    }

    public async Task<SourceBlobReceipt?> GetVerifiedReceiptAsync(
        ProtectedBlobLocation location,
        long expectedLength,
        byte[] expectedContentHash,
        CancellationToken cancellationToken)
    {
        try
        {
            var properties = (await GetBlobClient(location).GetPropertiesAsync(
                cancellationToken: cancellationToken)).Value;
            var storedHash = properties.Metadata.FirstOrDefault(pair => string.Equals(
                pair.Key, ContentHashMetadata, StringComparison.OrdinalIgnoreCase)).Value;
            if (properties.ContentLength != expectedLength ||
                !string.Equals(properties.ContentType, "application/pdf",
                    StringComparison.OrdinalIgnoreCase) ||
                !TryReadHash(storedHash, out var actualHash) ||
                !CryptographicOperations.FixedTimeEquals(actualHash, expectedContentHash))
                throw new SourceDocumentStorageException(
                    "verify-copy", "content-conflict", 409);
            return new SourceBlobReceipt(
                BlobETagNormalizer.NormalizeRequired(properties.ETag.ToString()),
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

    public async Task DeleteIfMatchAsync(
        ProtectedBlobLocation location,
        string? expectedETag,
        CancellationToken cancellationToken)
    {
        try
        {
            await GetBlobClient(location).DeleteIfExistsAsync(
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

    public async Task<SourceBlobRetentionDeletion> RequestDeletionAsync(
        ProtectedBlobLocation location,
        string expectedETag,
        long expectedLength,
        byte[] expectedContentHash,
        CancellationToken cancellationToken)
    {
        if (expectedLength <= 0) throw new ArgumentOutOfRangeException(nameof(expectedLength));
        ArgumentNullException.ThrowIfNull(expectedContentHash);
        if (expectedContentHash.Length != 32)
            throw new ArgumentException(
                "The expected content hash must be SHA-256.", nameof(expectedContentHash));
        var normalizedETag = BlobETagNormalizer.NormalizeRequired(expectedETag);
        var container = serviceClient.GetBlobContainerClient(location.Container);
        var blob = container.GetBlobClient(location.ObjectName);

        try
        {
            BlobProperties? current = null;
            try
            {
                current = (await blob.GetPropertiesAsync(
                    Conditions(normalizedETag), cancellationToken)).Value;
            }
            catch (RequestFailedException exception) when (exception.Status == 404)
            {
                // A previous attempt can have removed the current version before its
                // durable lease was completed. Historical versions still need deletion.
            }
            catch (RequestFailedException exception) when (exception.Status == 412)
            {
                throw new SourceDocumentStorageException(
                    "request-retention-deletion", "content-conflict", 409);
            }

            if (current is not null)
            {
                VerifyRetainedContent(current, expectedLength, expectedContentHash);
                try
                {
                    await blob.DeleteIfExistsAsync(
                        DeleteSnapshotsOption.IncludeSnapshots,
                        Conditions(normalizedETag),
                        cancellationToken);
                }
                catch (RequestFailedException exception) when (exception.Status == 412)
                {
                    throw new SourceDocumentStorageException(
                        "request-retention-deletion", "content-conflict", 409);
                }
            }

            var deleted = 0;
            var options = new GetBlobsOptions
            {
                Prefix = location.ObjectName,
                States = BlobStates.Version | BlobStates.Snapshots |
                         BlobStates.Deleted | BlobStates.DeletedWithVersions
            };
            await foreach (var item in container.GetBlobsAsync(
                               options, cancellationToken).ConfigureAwait(false))
            {
                if (!string.Equals(item.Name, location.ObjectName, StringComparison.Ordinal) ||
                    item.Deleted == true)
                    continue;
                BlobClient? immutable = item.VersionId is { Length: > 0 }
                    ? blob.WithVersion(item.VersionId)
                    : item.Snapshot is { Length: > 0 }
                        ? blob.WithSnapshot(item.Snapshot)
                        : null;
                if (immutable is null) continue;
                await immutable.DeleteIfExistsAsync(
                    DeleteSnapshotsOption.None,
                    conditions: null,
                    cancellationToken);
                deleted++;
                if (deleted >= MaximumVersionDeletesPerAttempt) break;
            }

            return new SourceBlobRetentionDeletion(
                !await HasActiveContentAsync(container, blob, location, cancellationToken));
        }
        catch (SourceDocumentStorageException)
        {
            throw;
        }
        catch (RequestFailedException exception)
        {
            throw StorageFailure("request-retention-deletion", exception);
        }
    }

    public void Dispose() => delegationKeyLock.Dispose();

    private async Task<UserDelegationKey> GetDelegationKeyAsync(
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
            delegationKey = (await serviceClient.GetUserDelegationKeyAsync(
                now.AddMinutes(-5), now.AddHours(1), cancellationToken)).Value;
            return delegationKey;
        }
        finally
        {
            delegationKeyLock.Release();
        }
    }

    private BlobClient GetBlobClient(ProtectedBlobLocation location) =>
        serviceClient.GetBlobContainerClient(location.Container)
            .GetBlobClient(location.ObjectName);

    private static BlobRequestConditions? Conditions(string? expectedETag) =>
        string.IsNullOrWhiteSpace(expectedETag)
            ? null
            : new BlobRequestConditions
            {
                IfMatch = new ETag(BlobETagNormalizer.NormalizeRequired(expectedETag))
            };

    private static void VerifyRetainedContent(
        BlobProperties properties,
        long expectedLength,
        byte[] expectedContentHash)
    {
        var storedHash = properties.Metadata.FirstOrDefault(pair => string.Equals(
            pair.Key, ContentHashMetadata, StringComparison.OrdinalIgnoreCase)).Value;
        if (properties.ContentLength != expectedLength ||
            !TryReadHash(storedHash, out var actualHash) ||
            !CryptographicOperations.FixedTimeEquals(actualHash, expectedContentHash))
            throw new SourceDocumentStorageException(
                "request-retention-deletion", "content-conflict", 409);
    }

    private static async Task<bool> HasActiveContentAsync(
        BlobContainerClient container,
        BlobClient blob,
        ProtectedBlobLocation location,
        CancellationToken cancellationToken)
    {
        if ((await blob.ExistsAsync(cancellationToken)).Value) return true;
        var options = new GetBlobsOptions
        {
            Prefix = location.ObjectName,
            States = BlobStates.All
        };
        await foreach (var item in container.GetBlobsAsync(
                           options, cancellationToken).ConfigureAwait(false))
        {
            if (string.Equals(item.Name, location.ObjectName, StringComparison.Ordinal) &&
                item.Deleted != true &&
                (item.VersionId is { Length: > 0 } || item.Snapshot is { Length: > 0 }))
                return true;
        }
        return false;
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

    private static SourceDocumentStorageException StorageFailure(
        string operation,
        RequestFailedException exception) => new(
            operation,
            exception.Status == 404 ? "blob-not-found" : "azure-storage-failed",
            exception.Status);
}

internal sealed class SanitizedAzureReadStream(Stream inner) : Stream
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

    private static SourceDocumentStorageException Failure(RequestFailedException exception) =>
        new("stream-read", exception.Status == 404 ? "blob-not-found" : "azure-storage-failed",
            exception.Status);
}
