using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace FundingPlatform.Infrastructure.Persistence.Migrations;

public static partial class SqlScriptCatalog
{
    public static IReadOnlyList<SqlScript> DiscoverMigrations(string solutionRoot) =>
        Discover(Path.Combine(solutionRoot, "database", "Migrations"));

    public static IReadOnlyList<SqlScript> DiscoverTests(string solutionRoot) =>
        Discover(Path.Combine(solutionRoot, "database", "Tests"));

    public static IReadOnlyList<SqlScript> DiscoverProvisioning(string solutionRoot) =>
        Discover(Path.Combine(solutionRoot, "database", "Provisioning"));

    public static string ComputeChecksum(ReadOnlySpan<byte> contents) =>
        Convert.ToHexString(SHA256.HashData(contents)).ToLowerInvariant();

    private static IReadOnlyList<SqlScript> Discover(string directory)
    {
        if (!Directory.Exists(directory))
        {
            throw new MigrationException("script_directory_not_found", Path.GetFileName(directory));
        }

        var scripts = new List<SqlScript>();
        foreach (var path in Directory
                     .EnumerateFiles(directory, "*", SearchOption.TopDirectoryOnly)
                     .Where(path => string.Equals(
                         Path.GetExtension(path),
                         ".sql",
                         StringComparison.OrdinalIgnoreCase)))
        {
            var fileName = Path.GetFileName(path);
            var match = ScriptNamePattern().Match(fileName);
            if (!match.Success ||
                !int.TryParse(match.Groups["sequence"].Value, out var sequence) ||
                sequence <= 0)
            {
                throw new MigrationException("invalid_script_name", SanitizeFileName(fileName));
            }

            var contents = File.ReadAllBytes(path);
            string sql;
            try
            {
                sql = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true)
                    .GetString(contents);
            }
            catch (DecoderFallbackException)
            {
                throw new MigrationException("script_is_not_utf8", SanitizeFileName(fileName));
            }

            scripts.Add(new SqlScript(
                sequence,
                match.Groups["name"].Value,
                fileName,
                ComputeChecksum(contents),
                GoBatchSplitter.Split(sql)));
        }

        var duplicate = scripts
            .GroupBy(script => script.Sequence)
            .FirstOrDefault(group => group.Count() > 1);
        if (duplicate is not null)
        {
            throw new MigrationException("duplicate_script_sequence", duplicate.Key.ToString("D3"));
        }

        return scripts.OrderBy(script => script.Sequence).ToArray();
    }

    private static string SanitizeFileName(string value) =>
        new(value.Where(character => char.IsLetterOrDigit(character) || character is '_' or '-' or '.').Take(128).ToArray());

    [GeneratedRegex(@"^(?<sequence>\d{3})_(?<name>[A-Za-z0-9][A-Za-z0-9_-]*)\.sql$", RegexOptions.CultureInvariant)]
    private static partial Regex ScriptNamePattern();
}
