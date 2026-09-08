using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Core.ProjectAssets;
using FundingPlatform.Infrastructure.ProjectAssets.Configuration;
using FundingPlatform.Infrastructure.ProjectAssets.Cryptography;
using FundingPlatform.Infrastructure.ProjectAssets.Inspection;

namespace FundingPlatform.UnitTests;

public sealed class ProjectAssetSecurityTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 9, 8, 14, 30, 0, TimeSpan.Zero);
    private static readonly Guid UserId =
        Guid.Parse("11111111-1111-1111-1111-111111111111");
    private static readonly Guid OrganizationId =
        Guid.Parse("22222222-2222-2222-2222-222222222222");
    private static readonly Guid ProjectId =
        Guid.Parse("33333333-3333-3333-3333-333333333333");
    private static readonly Guid IntentId =
        Guid.Parse("44444444-4444-4444-4444-444444444444");
    private static readonly Guid AssetId =
        Guid.Parse("55555555-5555-5555-5555-555555555555");
    private static readonly byte[] RowVersion = Convert.FromHexString("0102030405060708");

    [Fact]
    public void Disabled_options_are_valid_without_a_blob_service_uri()
    {
        var options = ValidOptions(enabled: false);
        options.BlobServiceUri = string.Empty;

        Assert.True(ProjectAssetOptions.IsValid(options, "Production"));

        var policy = options.ToPolicy();
        Assert.False(policy.Enabled);
        Assert.Null(policy.BlobServiceUri);
    }

    [Theory]
    [InlineData("")]
    [InlineData("relative/path")]
    [InlineData("http://testing.blob.core.windows.net")]
    public void Enabled_options_require_an_absolute_https_blob_service_uri(string uri)
    {
        var options = ValidOptions(enabled: true);
        options.BlobServiceUri = uri;

        Assert.False(ProjectAssetOptions.IsValid(options, "Production"));
    }

    [Fact]
    public void Enabled_options_accept_an_https_blob_service_uri()
    {
        var options = ValidOptions(enabled: true);

        Assert.True(ProjectAssetOptions.IsValid(options, "Production"));
        Assert.Equal(
            new Uri("https://testing.blob.core.windows.net"),
            options.ToPolicy().BlobServiceUri);
    }

    [Fact]
    public void Options_reject_an_upload_ttl_longer_than_the_database_contract()
    {
        var options = ValidOptions(enabled: true);
        options.UploadTtlMinutes = 6;

        Assert.False(ProjectAssetOptions.IsValid(options, "Production"));
    }

    [Theory]
    [InlineData(262_143_999)]
    [InlineData(262_144_001)]
    public void Options_reject_a_project_byte_limit_that_the_database_cannot_enforce(long limit)
    {
        var options = ValidOptions(enabled: true);
        options.MaxProjectBytes = limit;

        Assert.False(ProjectAssetOptions.IsValid(options, "Production"));
    }

    [Theory]
    [InlineData("Production", false)]
    [InlineData("Staging", false)]
    [InlineData("Development", true)]
    [InlineData("Testing", true)]
    [InlineData("development", true)]
    public void Development_fake_scanning_is_restricted_to_safe_environments(
        string environment,
        bool expected)
    {
        var options = ValidOptions(enabled: true);
        options.ScanMode = "DevelopmentFake";

        Assert.Equal(expected, ProjectAssetOptions.IsValid(options, environment));
    }

    [Fact]
    public void Completion_tokens_are_url_safe_hashable_and_never_render_the_secret()
    {
        var service = new ProjectAssetCompletionTokenService();

        var secret = service.Create();

        Assert.Equal(43, secret.Token.Length);
        Assert.Matches(new Regex("^[A-Za-z0-9_-]{43}$"), secret.Token);
        Assert.True(service.TryHash(secret.Token, out var hash));
        Assert.Equal(secret.Hash, hash);
        Assert.Equal(
            SHA256.HashData(Encoding.UTF8.GetBytes(secret.Token)),
            secret.Hash);
        Assert.Equal(
            "[redacted project asset completion secret]",
            secret.ToString());
        Assert.DoesNotContain(secret.Token, secret.ToString(), StringComparison.Ordinal);

        Assert.False(service.TryHash(string.Empty, out _));
        Assert.False(service.TryHash(new string('a', 39), out _));
        Assert.False(service.TryHash(new string('a', 65), out _));
        Assert.False(service.TryHash(new string('a', 42) + "+", out _));
    }

    [Fact]
    public async Task Streaming_inspector_accepts_supported_files_and_calculates_hash_and_dimensions()
    {
        var inspector = new StreamingProjectAssetContentInspector();
        var cases = new[]
        {
            new InspectionCase(
                ProjectAssetKind.Image,
                "image/png",
                Png(width: 640, height: 480),
                640,
                480),
            new InspectionCase(
                ProjectAssetKind.Image,
                "image/jpeg",
                Jpeg(width: 1024, height: 768),
                1024,
                768),
            new InspectionCase(
                ProjectAssetKind.Image,
                "image/webp",
                Webp(width: 320, height: 240),
                320,
                240),
            new InspectionCase(
                ProjectAssetKind.Document,
                "application/pdf",
                Encoding.ASCII.GetBytes("%PDF-1.7\n1 0 obj\n<<>>\nendobj\n%%EOF\n"),
                null,
                null)
        };

        foreach (var testCase in cases)
        {
            await using var source = BlobRead(testCase.Bytes, testCase.MimeType);

            var result = await inspector.InspectAsync(
                testCase.Kind,
                source,
                testCase.Bytes.Length,
                1024 * 1024,
                25_000_000,
                CancellationToken.None);

            Assert.True(result.IsValid);
            Assert.Equal(ProjectAssetInspectionFailure.None, result.Failure);
            Assert.Equal(testCase.Bytes.Length, result.ActualLength);
            Assert.Equal(SHA256.HashData(testCase.Bytes), result.ContentHash);
            Assert.Equal(testCase.MimeType, result.VerifiedMimeType);
            Assert.Equal(testCase.Width, result.PixelWidth);
            Assert.Equal(testCase.Height, result.PixelHeight);
        }
    }

    [Fact]
    public async Task Streaming_inspector_rejects_mime_and_magic_mismatch()
    {
        var bytes = Png(width: 10, height: 10);
        await using var source = BlobRead(bytes, "image/jpeg");

        var result = await new StreamingProjectAssetContentInspector().InspectAsync(
            ProjectAssetKind.Image,
            source,
            bytes.Length,
            1024,
            25_000_000,
            CancellationToken.None);

        Assert.False(result.IsValid);
        Assert.Equal(ProjectAssetInspectionFailure.InvalidFile, result.Failure);
        Assert.Null(result.ContentHash);
    }

    [Fact]
    public async Task Streaming_inspector_rejects_declared_and_streamed_length_mismatch()
    {
        var bytes = Png(width: 10, height: 10);
        await using var source = BlobRead(
            bytes,
            "image/png",
            declaredLength: bytes.Length + 1);

        var result = await new StreamingProjectAssetContentInspector().InspectAsync(
            ProjectAssetKind.Image,
            source,
            bytes.Length + 1,
            1024,
            25_000_000,
            CancellationToken.None);

        Assert.False(result.IsValid);
        Assert.Equal(ProjectAssetInspectionFailure.LengthMismatch, result.Failure);
        Assert.Equal(bytes.Length, result.ActualLength);
        Assert.Null(result.ContentHash);
    }

    [Fact]
    public async Task Streaming_inspector_rejects_images_above_the_pixel_limit()
    {
        var bytes = Png(width: 5001, height: 5000);
        await using var source = BlobRead(bytes, "image/png");

        var result = await new StreamingProjectAssetContentInspector().InspectAsync(
            ProjectAssetKind.Image,
            source,
            bytes.Length,
            1024,
            25_000_000,
            CancellationToken.None);

        Assert.False(result.IsValid);
        Assert.Equal(ProjectAssetInspectionFailure.ImageTooLarge, result.Failure);
        Assert.Null(result.ContentHash);
    }

    [Fact]
    public async Task Streaming_inspector_rejects_an_axis_above_the_database_limit()
    {
        var bytes = Png(width: 32_769, height: 1);
        await using var source = BlobRead(bytes, "image/png");

        var result = await new StreamingProjectAssetContentInspector().InspectAsync(
            ProjectAssetKind.Image,
            source,
            bytes.Length,
            1024,
            25_000_000,
            CancellationToken.None);

        Assert.False(result.IsValid);
        Assert.Equal(ProjectAssetInspectionFailure.ImageTooLarge, result.Failure);
        Assert.Null(result.ContentHash);
    }

    [Fact]
    public async Task Streaming_inspector_rejects_video_content()
    {
        var bytes = Encoding.ASCII.GetBytes("....ftypmp42");
        await using var source = BlobRead(bytes, "video/mp4");

        var result = await new StreamingProjectAssetContentInspector().InspectAsync(
            ProjectAssetKind.Video,
            source,
            bytes.Length,
            1024,
            25_000_000,
            CancellationToken.None);

        Assert.False(result.IsValid);
        Assert.Equal(ProjectAssetInspectionFailure.InvalidContentType, result.Failure);
        Assert.Null(result.ContentHash);
    }

    [Fact]
    public async Task Disabled_service_short_circuits_every_entry_point_without_dependencies()
    {
        var repository = new RecordingRepository();
        var blobs = new RecordingBlobStore();
        var inspector = new RecordingInspector();
        var scanner = new RecordingScanner();
        var tokens = new RecordingTokenService();
        var service = CreateService(
            repository,
            blobs,
            enabled: false,
            inspector,
            scanner,
            tokens);

        var create = await service.CreateUploadIntentAsync(
            UserId,
            OrganizationId,
            ProjectId,
            RowVersion,
            ProjectAssetKind.Image,
            "photo.png",
            "image/png",
            100,
            CancellationToken.None);
        var complete = await service.CompleteUploadIntentAsync(
            UserId,
            OrganizationId,
            ProjectId,
            IntentId,
            "completion-token",
            CancellationToken.None);
        var list = await service.ListAsync(
            UserId, OrganizationId, ProjectId, CancellationToken.None);
        var intent = await service.GetUploadIntentAsync(
            UserId, OrganizationId, ProjectId, IntentId, CancellationToken.None);
        var metadata = await service.UpdateMetadataAsync(
            UserId,
            OrganizationId,
            ProjectId,
            AssetId,
            RowVersion,
            RowVersion,
            new ProjectAssetMetadata("Portada", "Descripción", null, true),
            CancellationToken.None);
        var reorder = await service.ReorderAsync(
            UserId,
            OrganizationId,
            ProjectId,
            RowVersion,
            [(AssetId, RowVersion)],
            CancellationToken.None);
        var delete = await service.DeleteAsync(
            UserId,
            OrganizationId,
            ProjectId,
            AssetId,
            RowVersion,
            RowVersion,
            CancellationToken.None);
        var content = await service.GetTrustedContentAsync(
            UserId,
            OrganizationId,
            ProjectId,
            AssetId,
            CancellationToken.None);

        Assert.All(
            new[]
            {
                create.Outcome,
                complete.Outcome,
                list.Outcome,
                intent.Outcome,
                metadata.Outcome,
                reorder.Outcome,
                delete.Outcome,
                content.Outcome
            },
            outcome => Assert.Equal(ProjectAssetOutcome.Disabled, outcome));
        Assert.Equal(0, repository.Calls);
        Assert.Equal(0, blobs.Calls);
        Assert.Equal(0, inspector.Calls);
        Assert.Equal(0, scanner.Calls);
        Assert.Equal(0, tokens.Calls);
    }

    [Fact]
    public async Task Completed_resume_maps_a_missing_blob_without_leaking_an_exception()
    {
        var repository = new RecordingRepository
        {
            FinalizeWork = new ProjectAssetFinalizeWork
            {
                Succeeded = true,
                Code = "completed",
                IntentPublicId = IntentId,
                IntentStatus = ProjectAssetUploadIntentStatus.Completed,
                AssetPublicId = AssetId,
                Kind = ProjectAssetKind.Image,
                IncomingLocation = new ProtectedProjectAssetBlobLocation("fp-project-incoming", "file.png"),
                QuarantineLocation = new ProtectedProjectAssetBlobLocation("fp-project-quarantine", "file.png"),
                TrustedLocation = new ProtectedProjectAssetBlobLocation("fp-project-trusted", "file.png"),
                ActualContentLength = 100,
                ContentHash = SHA256.HashData("content"u8.ToArray()),
                VerifiedMimeType = "image/png",
                StorageStatus = ProjectAssetStorageStatus.AwaitingQuarantine,
                ScanStatus = ProjectAssetScanStatus.Pending,
                AssetRowVersion = RowVersion,
                ProjectRowVersion = RowVersion
            }
        };
        var blobs = new RecordingBlobStore
        {
            OpenFailure = new ProjectAssetStorageException(
                "open-read", "blob-not-found", 404)
        };

        var result = await CreateService(repository, blobs).CompleteUploadIntentAsync(
            UserId,
            OrganizationId,
            ProjectId,
            IntentId,
            "test-completion-token",
            CancellationToken.None);

        Assert.Equal(ProjectAssetOutcome.Conflict, result.Outcome);
        Assert.Equal("blob-not-found", result.Code);
        Assert.Equal(IntentId, result.IntentPublicId);
    }

    [Fact]
    public async Task Invalid_upload_does_not_delete_the_blob_when_rejection_observes_completion()
    {
        var incoming = new ProtectedProjectAssetBlobLocation(
            "fp-project-incoming", "11111111-1111-1111-1111-111111111111/file.png");
        var repository = new RecordingRepository
        {
            FinalizeWorkFactory = leaseId => new ProjectAssetFinalizeWork
            {
                Succeeded = true,
                Code = "acquired",
                IntentPublicId = IntentId,
                IntentStatus = ProjectAssetUploadIntentStatus.Finalizing,
                Kind = ProjectAssetKind.Image,
                ExpectedContentLength = 100,
                MaxContentLength = 10_485_760,
                IncomingLocation = incoming,
                QuarantineLocation = new ProtectedProjectAssetBlobLocation(
                    "fp-project-quarantine", incoming.ObjectName),
                TrustedLocation = new ProtectedProjectAssetBlobLocation(
                    "fp-project-trusted", incoming.ObjectName),
                FinalizeLeaseId = leaseId,
                ProjectRowVersion = RowVersion
            },
            RejectMutation = new ProjectAssetMutation(
                true,
                "completed",
                IntentId,
                ProjectAssetUploadIntentStatus.Completed,
                AssetId,
                ProjectAssetStorageStatus.AwaitingQuarantine,
                ProjectAssetScanStatus.Pending,
                ProjectAssetScanProvider.MicrosoftDefender,
                RowVersion,
                RowVersion,
                RowVersion,
                WasReplay: true)
        };
        var blobs = new RecordingBlobStore
        {
            OpenResult = BlobRead(new byte[100], "image/png")
        };

        var result = await CreateService(repository, blobs).CompleteUploadIntentAsync(
            UserId,
            OrganizationId,
            ProjectId,
            IntentId,
            "test-completion-token",
            CancellationToken.None);

        Assert.Equal(ProjectAssetOutcome.Processing, result.Outcome);
        Assert.Equal("completed", result.Code);
        Assert.Empty(blobs.DeletedLocations);
    }

    public static TheoryData<byte[], ProjectAssetKind, string?, string?, long, string> InvalidCreateCases =>
        new()
        {
            { [], ProjectAssetKind.Image, "photo.png", "image/png", 100, "projectETag" },
            { RowVersion, ProjectAssetKind.Image, "photo.pdf", "image/png", 100, "mimeType" },
            { RowVersion, ProjectAssetKind.Image, "photo.png", "image/jpeg", 100, "mimeType" },
            { RowVersion, ProjectAssetKind.Image, "photo.png", "text/plain", 100, "mimeType" },
            { RowVersion, ProjectAssetKind.Image, "photo.png", "image/png", 0, "contentLength" },
            {
                RowVersion,
                ProjectAssetKind.Image,
                "photo.png",
                "image/png",
                10_485_761,
                "contentLength"
            },
            { RowVersion, ProjectAssetKind.Video, "clip.mp4", "video/mp4", 100, "kind" }
        };

    [Theory]
    [MemberData(nameof(InvalidCreateCases))]
    public async Task Create_intent_rejects_invalid_etag_extension_mime_size_and_video(
        byte[] projectRowVersion,
        ProjectAssetKind kind,
        string? fileName,
        string? mimeType,
        long contentLength,
        string expectedError)
    {
        var repository = new RecordingRepository();
        var blobs = new RecordingBlobStore();
        var service = CreateService(repository, blobs);

        var result = await service.CreateUploadIntentAsync(
            UserId,
            OrganizationId,
            ProjectId,
            projectRowVersion,
            kind,
            fileName,
            mimeType,
            contentLength,
            CancellationToken.None);

        Assert.Equal(ProjectAssetOutcome.ValidationFailed, result.Outcome);
        Assert.Equal("invalid-asset", result.Code);
        Assert.NotNull(result.Errors);
        Assert.True(result.Errors.ContainsKey(expectedError));
        Assert.Equal(0, repository.Calls);
        Assert.Equal(0, blobs.Calls);
    }

    [Fact]
    public async Task Create_intent_uses_a_random_non_identifying_path_and_propagates_sas_headers()
    {
        var repository = new RecordingRepository
        {
            CreateMutation = new ProjectAssetMutation(
                true,
                "upload-intent-created",
                IntentId,
                ProjectAssetUploadIntentStatus.Pending,
                IntentRowVersion: RowVersion,
                ProjectRowVersion: RowVersion,
                ExpiresAtUtc: Now.AddMinutes(5))
        };
        var blobs = new RecordingBlobStore();
        var service = CreateService(repository, blobs);

        var first = await service.CreateUploadIntentAsync(
            UserId,
            OrganizationId,
            ProjectId,
            RowVersion,
            ProjectAssetKind.Image,
            " Logo organización 2026.PNG ",
            " IMAGE/PNG ",
            512,
            CancellationToken.None);
        var second = await service.CreateUploadIntentAsync(
            UserId,
            OrganizationId,
            ProjectId,
            RowVersion,
            ProjectAssetKind.Image,
            "Logo organización 2026.png",
            "image/png",
            512,
            CancellationToken.None);

        Assert.Equal(ProjectAssetOutcome.Success, first.Outcome);
        Assert.Equal(IntentId, first.IntentPublicId);
        Assert.Equal("test-completion-token", first.CompletionToken);
        Assert.Equal(blobs.UploadUri, first.UploadUri);
        Assert.Equal(blobs.RequiredHeaders, first.RequiredHeaders);
        Assert.Equal("BlockBlob", first.RequiredHeaders!["x-ms-blob-type"]);
        Assert.Equal("image/png", first.RequiredHeaders["Content-Type"]);
        Assert.Equal("*", first.RequiredHeaders["If-None-Match"]);
        Assert.Equal(2, repository.Creates.Count);
        Assert.Equal(2, blobs.UploadDestinations.Count);

        var firstCreate = repository.Creates[0];
        var secondCreate = repository.Creates[1];
        Assert.Equal("Logo organización 2026.PNG", firstCreate.OriginalFileName);
        Assert.Equal("image/png", firstCreate.DeclaredMimeType);
        Assert.Equal("fp-project-incoming", firstCreate.Incoming.Container);
        Assert.Equal("fp-project-quarantine", firstCreate.Quarantine.Container);
        Assert.Equal("fp-project-trusted", firstCreate.Trusted.Container);
        Assert.Equal(firstCreate.Incoming.ObjectName, firstCreate.Quarantine.ObjectName);
        Assert.Equal(firstCreate.Incoming.ObjectName, firstCreate.Trusted.ObjectName);
        Assert.EndsWith(".png", firstCreate.Incoming.ObjectName, StringComparison.Ordinal);
        Assert.True(Guid.TryParseExact(
            Path.GetDirectoryName(firstCreate.Incoming.ObjectName),
            "D",
            out _));
        Assert.Matches(
            new Regex("^[0-9a-f]{32}$"),
            Path.GetFileNameWithoutExtension(firstCreate.Incoming.ObjectName));
        Assert.NotEqual(firstCreate.Incoming.ObjectName, secondCreate.Incoming.ObjectName);
        Assert.DoesNotContain("logo", firstCreate.Incoming.ObjectName, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(
            UserId.ToString("N"),
            firstCreate.Incoming.ObjectName,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(
            OrganizationId.ToString("N"),
            firstCreate.Incoming.ObjectName,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(
            ProjectId.ToString("N"),
            firstCreate.Incoming.ObjectName,
            StringComparison.OrdinalIgnoreCase);
        Assert.All(
            blobs.UploadDestinations,
            destination => Assert.Equal("fp-project-incoming", destination.Container));
        Assert.All(blobs.UploadContentTypes, value => Assert.Equal("image/png", value));
    }

    [Fact]
    public async Task Cover_metadata_requires_alt_text_before_repository_mutation()
    {
        var repository = new RecordingRepository();
        var service = CreateService(repository, new RecordingBlobStore());

        var result = await service.UpdateMetadataAsync(
            UserId,
            OrganizationId,
            ProjectId,
            AssetId,
            RowVersion,
            RowVersion,
            new ProjectAssetMetadata("Portada", "   ", null, IsCover: true),
            CancellationToken.None);

        Assert.Equal(ProjectAssetOutcome.ValidationFailed, result.Outcome);
        Assert.Equal("invalid-metadata", result.Code);
        Assert.NotNull(result.Errors);
        Assert.True(result.Errors.ContainsKey("altText"));
        Assert.Equal(0, repository.Calls);
    }

    [Fact]
    public async Task Reorder_rejects_duplicate_assets_and_invalid_project_or_asset_etags()
    {
        var repository = new RecordingRepository();
        var service = CreateService(repository, new RecordingBlobStore());

        var duplicate = await service.ReorderAsync(
            UserId,
            OrganizationId,
            ProjectId,
            RowVersion,
            [(AssetId, RowVersion), (AssetId, RowVersion)],
            CancellationToken.None);
        var invalidProjectETag = await service.ReorderAsync(
            UserId,
            OrganizationId,
            ProjectId,
            [],
            [(AssetId, RowVersion)],
            CancellationToken.None);
        var invalidAssetETag = await service.ReorderAsync(
            UserId,
            OrganizationId,
            ProjectId,
            RowVersion,
            [(AssetId, [])],
            CancellationToken.None);

        Assert.Equal(ProjectAssetOutcome.ValidationFailed, duplicate.Outcome);
        Assert.True(duplicate.Errors!.ContainsKey("items"));
        Assert.Equal(ProjectAssetOutcome.ValidationFailed, invalidProjectETag.Outcome);
        Assert.True(invalidProjectETag.Errors!.ContainsKey("projectETag"));
        Assert.Equal(ProjectAssetOutcome.ValidationFailed, invalidAssetETag.Outcome);
        Assert.True(invalidAssetETag.Errors!.ContainsKey("items"));
        Assert.Equal(0, repository.Calls);
    }

    private static ProjectAssetService CreateService(
        RecordingRepository repository,
        RecordingBlobStore blobs,
        bool enabled = true,
        IProjectAssetContentInspector? inspector = null,
        IProjectAssetScanner? scanner = null,
        IProjectAssetCompletionTokenService? tokens = null) => new(
        repository,
        blobs,
        inspector ?? new RecordingInspector(),
        scanner ?? new RecordingScanner(),
        tokens ?? new RecordingTokenService(),
        Policy(enabled),
        new FixedTimeProvider(Now));

    private static ProjectAssetPolicy Policy(bool enabled) => new(
        enabled,
        enabled ? new Uri("https://testing.blob.core.windows.net") : null,
        "fp-project-incoming",
        "fp-project-quarantine",
        "fp-project-trusted",
        10_485_760,
        26_214_400,
        262_144_000,
        25_000_000,
        TimeSpan.FromMinutes(5),
        TimeSpan.FromMinutes(2),
        TimeSpan.FromMinutes(5),
        ProjectAssetScanProvider.DevelopmentFake);

    private static ProjectAssetOptions ValidOptions(bool enabled) => new()
    {
        Enabled = enabled,
        BlobServiceUri = "https://testing.blob.core.windows.net",
        ScanMode = "MicrosoftDefender",
        DevelopmentFakeResult = "Clean"
    };

    private static ProjectAssetBlobRead BlobRead(
        byte[] bytes,
        string contentType,
        long? declaredLength = null) => new(
        new MemoryStream(bytes, writable: false),
        declaredLength ?? bytes.Length,
        contentType,
        "\"etag\"",
        "version-1");

    private static byte[] Png(int width, int height)
    {
        var bytes = new byte[24];
        new byte[] { 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a }
            .CopyTo(bytes, 0);
        BinaryPrimitives.WriteUInt32BigEndian(bytes.AsSpan(8, 4), 13);
        "IHDR"u8.CopyTo(bytes.AsSpan(12, 4));
        BinaryPrimitives.WriteInt32BigEndian(bytes.AsSpan(16, 4), width);
        BinaryPrimitives.WriteInt32BigEndian(bytes.AsSpan(20, 4), height);
        return bytes;
    }

    private static byte[] Jpeg(int width, int height)
    {
        var bytes = new byte[15];
        bytes[0] = 0xff;
        bytes[1] = 0xd8;
        bytes[2] = 0xff;
        bytes[3] = 0xc0;
        BinaryPrimitives.WriteUInt16BigEndian(bytes.AsSpan(4, 2), 11);
        bytes[6] = 8;
        BinaryPrimitives.WriteUInt16BigEndian(bytes.AsSpan(7, 2), checked((ushort)height));
        BinaryPrimitives.WriteUInt16BigEndian(bytes.AsSpan(9, 2), checked((ushort)width));
        bytes[11] = 1;
        bytes[12] = 1;
        bytes[13] = 0x11;
        bytes[14] = 0;
        return bytes;
    }

    private static byte[] Webp(int width, int height)
    {
        var bytes = new byte[30];
        "RIFF"u8.CopyTo(bytes.AsSpan(0, 4));
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(4, 4), 22);
        "WEBP"u8.CopyTo(bytes.AsSpan(8, 4));
        "VP8X"u8.CopyTo(bytes.AsSpan(12, 4));
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(16, 4), 10);
        WriteUInt24LittleEndian(bytes.AsSpan(24, 3), width - 1);
        WriteUInt24LittleEndian(bytes.AsSpan(27, 3), height - 1);
        return bytes;
    }

    private static void WriteUInt24LittleEndian(Span<byte> destination, int value)
    {
        destination[0] = (byte)value;
        destination[1] = (byte)(value >> 8);
        destination[2] = (byte)(value >> 16);
    }

    private sealed record InspectionCase(
        ProjectAssetKind Kind,
        string MimeType,
        byte[] Bytes,
        int? Width,
        int? Height);

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private sealed class RecordingTokenService : IProjectAssetCompletionTokenService
    {
        public int Calls { get; private set; }

        public ProjectAssetCompletionSecret Create()
        {
            Calls++;
            return new ProjectAssetCompletionSecret(
                "test-completion-token",
                SHA256.HashData("test-completion-token"u8));
        }

        public bool TryHash(string token, out byte[] hash)
        {
            Calls++;
            hash = SHA256.HashData(Encoding.UTF8.GetBytes(token));
            return token == "test-completion-token";
        }
    }

    private sealed class RecordingInspector : IProjectAssetContentInspector
    {
        public int Calls { get; private set; }

        public Task<ProjectAssetInspection> InspectAsync(
            ProjectAssetKind kind,
            ProjectAssetBlobRead source,
            long expectedLength,
            long maximumLength,
            int maximumImagePixels,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(new ProjectAssetInspection(
                false,
                ProjectAssetInspectionFailure.InvalidFile,
                source.ContentLength,
                null,
                null));
        }
    }

    private sealed class RecordingScanner : IProjectAssetScanner
    {
        public int Calls { get; private set; }

        public Task<ProjectAssetScanObservation> ObserveAsync(
            Guid assetPublicId,
            ProtectedProjectAssetBlobLocation quarantineLocation,
            string quarantineETag,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(new ProjectAssetScanObservation(
                ProjectAssetScanStatus.Pending,
                "pending",
                "test-observation",
                Now));
        }
    }

    private sealed class RecordingBlobStore : IProjectAssetBlobStore
    {
        public Uri UploadUri { get; } =
            new("https://testing.blob.core.windows.net/fp-project-incoming/file.png?sig=redacted");

        public IReadOnlyDictionary<string, string> RequiredHeaders { get; } =
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                ["x-ms-blob-type"] = "BlockBlob",
                ["Content-Type"] = "image/png",
                ["If-None-Match"] = "*"
            };

        public int Calls { get; private set; }
        public ProjectAssetStorageException? OpenFailure { get; init; }
        public ProjectAssetBlobRead? OpenResult { get; init; }
        public List<ProtectedProjectAssetBlobLocation> UploadDestinations { get; } = [];
        public List<string> UploadContentTypes { get; } = [];
        public List<ProtectedProjectAssetBlobLocation> DeletedLocations { get; } = [];

        public Task<ProjectAssetUploadGrant> CreateUploadGrantAsync(
            ProtectedProjectAssetBlobLocation destination,
            string contentType,
            DateTimeOffset expiresAtUtc,
            CancellationToken cancellationToken)
        {
            Calls++;
            UploadDestinations.Add(destination);
            UploadContentTypes.Add(contentType);
            return Task.FromResult(new ProjectAssetUploadGrant(
                UploadUri,
                expiresAtUtc,
                RequiredHeaders));
        }

        public Task<ProjectAssetBlobRead> OpenReadAsync(
            ProtectedProjectAssetBlobLocation source,
            string? expectedETag,
            CancellationToken cancellationToken)
        {
            Calls++;
            if (OpenFailure is not null) throw OpenFailure;
            if (OpenResult is not null) return Task.FromResult(OpenResult);
            throw new NotSupportedException();
        }

        public Task<ProjectAssetBlobReceipt> EnsureCopyAsync(
            ProtectedProjectAssetBlobLocation source,
            string sourceETag,
            ProtectedProjectAssetBlobLocation destination,
            string contentType,
            long expectedLength,
            byte[] expectedContentHash,
            CancellationToken cancellationToken)
        {
            Calls++;
            throw new NotSupportedException();
        }

        public Task DeleteIfMatchAsync(
            ProtectedProjectAssetBlobLocation location,
            string? expectedETag,
            CancellationToken cancellationToken)
        {
            Calls++;
            DeletedLocations.Add(location);
            return Task.CompletedTask;
        }
    }

    private sealed class RecordingRepository : IProjectAssetRepository
    {
        public int Calls { get; private set; }
        public ProjectAssetMutation CreateMutation { get; init; } =
            new(false, "unexpected-create");
        public ProjectAssetFinalizeWork FinalizeWork { get; init; } = new();
        public Func<Guid, ProjectAssetFinalizeWork>? FinalizeWorkFactory { get; init; }
        public ProjectAssetMutation RejectMutation { get; init; } =
            new(false, "unexpected-mutation");
        public List<CapturedCreate> Creates { get; } = [];

        public Task<ProjectAssetMutation> CreateUploadIntentAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            byte[] expectedProjectRowVersion,
            ProjectAssetKind kind,
            string originalFileName,
            string declaredMimeType,
            long expectedContentLength,
            long maxContentLength,
            ProtectedProjectAssetBlobLocation incomingLocation,
            ProtectedProjectAssetBlobLocation quarantineLocation,
            ProtectedProjectAssetBlobLocation trustedLocation,
            byte[] completionTokenHash,
            DateTimeOffset expiresAtUtc,
            CancellationToken cancellationToken)
        {
            Calls++;
            Creates.Add(new CapturedCreate(
                originalFileName,
                declaredMimeType,
                incomingLocation,
                quarantineLocation,
                trustedLocation));
            return Task.FromResult(CreateMutation);
        }

        public Task<ProjectAssetFinalizeWork> AcquireFinalizeAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid intentPublicId,
            byte[] completionTokenHash,
            Guid leaseId,
            DateTimeOffset leaseUntilUtc,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(FinalizeWorkFactory?.Invoke(leaseId) ?? FinalizeWork);
        }

        public Task<ProjectAssetMutation> ReleaseFinalizeAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid intentPublicId,
            Guid leaseId,
            string errorCode,
            CancellationToken cancellationToken) => Mutation();

        public Task<ProjectAssetMutation> RejectFinalizeAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid intentPublicId,
            Guid leaseId,
            string errorCode,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(RejectMutation);
        }

        public Task<ProjectAssetMutation> CompleteUploadIntentAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid intentPublicId,
            Guid leaseId,
            byte[] expectedProjectRowVersion,
            string verifiedMimeType,
            long actualContentLength,
            byte[] contentHash,
            int? pixelWidth,
            int? pixelHeight,
            ProjectAssetScanProvider scanProvider,
            CancellationToken cancellationToken) => Mutation();

        public Task<ProjectAssetMutation> MarkQuarantinedAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid assetPublicId,
            byte[] expectedAssetRowVersion,
            ProjectAssetBlobReceipt receipt,
            CancellationToken cancellationToken) => Mutation();

        public Task<ProjectAssetMutation> ApplyScanResultAsync(
            Guid assetPublicId,
            ProjectAssetScanProvider scanProvider,
            string providerEventId,
            byte[] payloadHash,
            string quarantineETag,
            byte[]? reportedContentHash,
            ProjectAssetScanStatus status,
            string resultCode,
            ProtectedProjectAssetBlobLocation? trustedLocation,
            ProjectAssetBlobReceipt? trustedReceipt,
            DateTimeOffset occurredAtUtc,
            CancellationToken cancellationToken) => Mutation();

        public Task<ProjectAssetCollection> ListAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(new ProjectAssetCollection(
                projectPublicId,
                0,
                RowVersion,
                []));
        }

        public Task<ProjectAssetUploadIntent?> GetUploadIntentAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid intentPublicId,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult<ProjectAssetUploadIntent?>(null);
        }

        public Task<ProjectAssetTrustedContent?> GetTrustedContentAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid assetPublicId,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult<ProjectAssetTrustedContent?>(null);
        }

        public Task<ProjectAssetMutation> UpdateMetadataAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid assetPublicId,
            byte[] expectedAssetRowVersion,
            byte[] expectedProjectRowVersion,
            ProjectAssetMetadata metadata,
            CancellationToken cancellationToken) => Mutation();

        public Task<ProjectAssetMutation> ReorderAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            byte[] expectedProjectRowVersion,
            IReadOnlyList<ProjectAssetOrderItem> items,
            CancellationToken cancellationToken) => Mutation();

        public Task<ProjectAssetMutation> DeleteAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid assetPublicId,
            byte[] expectedAssetRowVersion,
            byte[] expectedProjectRowVersion,
            CancellationToken cancellationToken) => Mutation();

        private Task<ProjectAssetMutation> Mutation()
        {
            Calls++;
            return Task.FromResult(new ProjectAssetMutation(false, "unexpected-mutation"));
        }
    }

    private sealed record CapturedCreate(
        string OriginalFileName,
        string DeclaredMimeType,
        ProtectedProjectAssetBlobLocation Incoming,
        ProtectedProjectAssetBlobLocation Quarantine,
        ProtectedProjectAssetBlobLocation Trusted);
}
