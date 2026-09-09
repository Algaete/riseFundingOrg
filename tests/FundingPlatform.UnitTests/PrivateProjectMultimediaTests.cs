using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Core.ProjectAssets;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using FundingPlatform.Infrastructure.ProjectAssets.Inspection;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;
public sealed class PrivateProjectMultimediaTests
{
    [Theory]
    [InlineData("Informe Ñandú\nLínea\t2", true)]
    [InlineData("texto\0ejecutable", false)]
    [InlineData("", false)]
    public async Task Text_requires_nonempty_utf8_without_binary_controls(string value, bool expected)
    {
        var result = await Inspect(Encoding.UTF8.GetBytes(value), ProjectAssetKind.Document, "text/plain");
        Assert.Equal(expected, result.IsValid);
    }
    [Fact]
    public async Task Text_rejects_invalid_utf8_and_over_limit_before_exposing_a_hash()
    {
        Assert.False((await Inspect([0xff, 0xfe, 0xff], ProjectAssetKind.Document, "text/plain")).IsValid);
        var result = await Inspect(new byte[1_048_577], ProjectAssetKind.Document, "text/plain");
        Assert.Equal(ProjectAssetInspectionFailure.TooLarge, result.Failure); Assert.Null(result.ContentHash);
    }
    [Fact]
    public async Task Mp4_probe_requires_complete_file_type_movie_video_track_and_media_envelope()
    {
        var bytes = Envelope();
        var result = await Inspect(bytes, ProjectAssetKind.Video, "video/mp4");
        Assert.True(result.IsValid); Assert.Equal(SHA256.HashData(bytes), result.ContentHash);
        Assert.Null(result.PixelWidth); Assert.Null(result.PixelHeight);
        Assert.False((await Inspect(bytes[..^1], ProjectAssetKind.Video, "video/mp4")).IsValid);
        Assert.False((await Inspect([.. bytes, 0], ProjectAssetKind.Video, "video/mp4")).IsValid);
        Assert.False((await Inspect(bytes, ProjectAssetKind.Document, "video/mp4")).IsValid);
        Assert.False((await Inspect(Box("ftyp", "isom0000"u8.ToArray()), ProjectAssetKind.Video, "video/mp4")).IsValid);
    }
    [Theory]
    [InlineData(ProjectAssetKind.Video, "video/mp4", "mp4-copy-v1")]
    [InlineData(ProjectAssetKind.Document, "text/plain", "utf8-copy-v1")]
    public void Private_original_manifest_requires_exact_source_identity(ProjectAssetKind kind, string mime, string version)
    {
        var hash = SHA256.HashData("source"u8);
        var manifest = new ProjectAssetTrustedContentManifest(mime, 6, hash, null, null, version);
        bool Valid(ProjectAssetTrustedContentManifest candidate) => ProjectAssetTrustedContentRules.IsValid(kind, candidate, mime, 6, hash, 26_214_400, 25_000_000);
        Assert.True(Valid(manifest));
        Assert.False(Valid(manifest with { ProcessingVersion = "pdf-copy-v1" }));
        Assert.False(Valid(manifest with { ContentLength = 7 }));
        Assert.False(Valid(manifest with { ContentHash = new byte[32] }));
        Assert.False(Valid(manifest with { PixelWidth = 1 }));
    }
    [Fact]
    public void Sql_patches_compile_and_preserve_scan_quota_audit_and_retention_guards()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var scripts = SqlScriptCatalog.DiscoverMigrations(root);
        var migration = scripts.Single(script => script.Sequence == 46);
        var smoke = SqlScriptCatalog.DiscoverTests(root).Single(script => script.Sequence == 46);
        Assert.All(smoke.Batches, Parse);
        foreach (var batch in migration.Batches)
        {
            Parse(batch);
            var name = Regex.Match(batch, @"OBJECT_ID\(N'(?<name>dbo\.[^']+)'").Groups["name"].Value;
            if (name.Length == 0) continue;
            var originalName = name.EndsWith("_Pre038", StringComparison.Ordinal) ? name[..^7] : name;
            var sequence = name.EndsWith("_Pre038", StringComparison.Ordinal) ? 37 : name.Contains("UploadIntent", StringComparison.Ordinal) ? 36 : 38;
            var procedure = scripts.Single(script => script.Sequence == sequence).Batches.Single(b => Regex.IsMatch(b, @"CREATE(?: OR ALTER)? PROCEDURE " + Regex.Escape(originalName) + @"\s"));
            foreach (Match replacement in Regex.Matches(batch, @"SET @Definition = REPLACE\(@Definition, N'(?<from>(?:[^']|'')*)', N'(?<to>(?:[^']|'')*)'\);"))
            {
                var from = replacement.Groups["from"].Value.Replace("''", "'", StringComparison.Ordinal);
                var to = replacement.Groups["to"].Value.Replace("''", "'", StringComparison.Ordinal);
                if (!from.StartsWith("CREATE", StringComparison.Ordinal)) Assert.Contains(from, procedure);
                procedure = procedure.Replace(from, to, StringComparison.Ordinal);
            }
            Parse(procedure);
        }
        var sql = string.Join('\n', migration.Batches);
        Assert.Contains("mp4-copy-v1", sql); Assert.Contains("utf8-copy-v1", sql);
        Assert.Contains("ContentHash = ContentHash", sql);
        Assert.Contains("Kind IN (1, 2) AND IsDeleted = 0", sql);
        Assert.Contains("OutboxAuditEvents_Acknowledge_Pre038", sql);
        Assert.Contains("FundingPlatform_CK_ProjectAssetRetention_Manifest", sql);
        Assert.DoesNotContain("NOCHECK", sql); Assert.DoesNotContain("GRANT", sql);
    }
    private static void Parse(string sql)
    {
        _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(new StringReader(sql), out var errors);
        Assert.True(errors.Count == 0, string.Join(';', errors.Select(error => error.Message)));
    }
    private static async Task<ProjectAssetInspection> Inspect(byte[] bytes, ProjectAssetKind kind, string mime)
    {
        await using var read = new ProjectAssetBlobRead(new MemoryStream(bytes), bytes.Length, mime, "\"version\"", "version");
        return await new StreamingProjectAssetContentInspector().InspectAsync(kind, read, bytes.Length, 26_214_400, 25_000_000, default);
    }
    private static byte[] Envelope()
    {
        var handler = new byte[24]; "vide"u8.CopyTo(handler.AsSpan(8));
        return [.. Box("ftyp", "isom0000"u8.ToArray()), .. Box("moov", [.. Box("mvhd", new byte[100]), .. Box("trak", Box("mdia", Box("hdlr", handler)))]), .. Box("mdat", [1,2,3])];
    }
    private static byte[] Box(string name, byte[] body)
    {
        var result = new byte[body.Length + 8]; BinaryPrimitives.WriteInt32BigEndian(result, result.Length);
        Encoding.ASCII.GetBytes(name).CopyTo(result, 4); body.CopyTo(result, 8); return result;
    }
}
