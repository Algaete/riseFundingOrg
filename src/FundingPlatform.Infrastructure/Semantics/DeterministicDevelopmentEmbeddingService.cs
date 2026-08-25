using System.Buffers.Binary;
using System.Diagnostics;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using FundingPlatform.Application.Semantics;
using FundingPlatform.Core.Semantics;

namespace FundingPlatform.Infrastructure.Semantics;

public sealed partial class DeterministicDevelopmentEmbeddingService : IEmbeddingService
{
    public const string ProviderCode = "development-deterministic";
    public const string ModelCode = "lexical-hash-1536-v1";

    public Task<SemanticEmbeddingGeneration> GenerateAsync(
        SemanticEmbeddingRequest request,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var utf8 = Encoding.UTF8.GetBytes(request.CanonicalInputJson);
        if (request.ProviderCode != ProviderCode || request.ModelCode != ModelCode ||
            request.Dimensions != SemanticProcessingPolicy.RequiredDimensions ||
            request.PurposeCode != "matching" || request.NormalizationVersion != "semantic-text-v1" ||
            request.TemplateVersion != (request.SubjectType == SemanticSubjectType.Project
                ? "project-semantic-v1"
                : "opportunity-semantic-v1") ||
            utf8.Length is < 2 or > SemanticProcessingPolicy.RequiredMaximumInputUtf8Bytes ||
            request.InputContentHash.Length != 32 ||
            !CryptographicOperations.FixedTimeEquals(
                SHA256.HashData(utf8), request.InputContentHash))
        {
            throw new SemanticEmbeddingException(
                "embedding-provider-unavailable",
                retryable: false,
                providerCallAccounting: SemanticProviderCallAccounting.NotInvoked);
        }

        var started = Stopwatch.GetTimestamp();
        var features = ExtractFeatures(request.CanonicalInputJson, cancellationToken);
        if (features.Count == 0)
        {
            throw new SemanticEmbeddingException(
                "embedding-provider-invalid-response",
                retryable: false,
                providerCallAccounting: SemanticProviderCallAccounting.NotInvoked);
        }

        var vector = new float[request.Dimensions];
        string? previous = null;
        foreach (var feature in features)
        {
            cancellationToken.ThrowIfCancellationRequested();
            AddFeature(vector, feature, 1f);
            if (previous is not null) AddFeature(vector, $"{previous}\u001f{feature}", .5f);
            previous = feature;
        }

        double normSquared = 0;
        foreach (var value in vector) normSquared += (double)value * value;
        if (!double.IsFinite(normSquared) || normSquared <= double.Epsilon)
        {
            throw new SemanticEmbeddingException(
                "embedding-provider-invalid-response",
                retryable: false,
                providerCallAccounting: SemanticProviderCallAccounting.NotInvoked);
        }

        var inverseNorm = 1d / Math.Sqrt(normSquared);
        for (var index = 0; index < vector.Length; index++)
            vector[index] = (float)(vector[index] * inverseNorm);

        var elapsed = Stopwatch.GetElapsedTime(started);
        var latencyMilliseconds = (int)Math.Clamp(
            Math.Ceiling(elapsed.TotalMilliseconds), 0, 30_000);
        return Task.FromResult(new SemanticEmbeddingGeneration(
            ProviderCode,
            ModelCode,
            request.TemplateVersion,
            request.Dimensions,
            vector,
            features.Count,
            null,
            0m,
            null,
            latencyMilliseconds));
    }

    private static List<string> ExtractFeatures(
        string canonicalInputJson,
        CancellationToken cancellationToken)
    {
        using var document = JsonDocument.Parse(canonicalInputJson, new JsonDocumentOptions
        {
            AllowTrailingCommas = false,
            CommentHandling = JsonCommentHandling.Disallow,
            MaxDepth = 8
        });
        var features = new List<string>(256);
        foreach (var property in document.RootElement.EnumerateObject())
        {
            if (property.Name is "schemaVersion" or "normalizationVersion") continue;
            Collect(property.Value, features, cancellationToken);
        }
        return features;
    }

    private static void Collect(
        JsonElement element,
        List<string> features,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        switch (element.ValueKind)
        {
            case JsonValueKind.String:
                var normalized = (element.GetString() ?? string.Empty)
                    .Normalize(NormalizationForm.FormKC)
                    .ToLower(CultureInfo.InvariantCulture);
                foreach (Match match in TokenPattern().Matches(normalized))
                {
                    if (features.Count >= 4096) return;
                    features.Add(match.Value);
                }
                break;
            case JsonValueKind.Number:
                if (features.Count < 4096) features.Add(element.GetRawText());
                break;
            case JsonValueKind.True:
            case JsonValueKind.False:
                if (features.Count < 4096) features.Add(element.GetBoolean() ? "true" : "false");
                break;
            case JsonValueKind.Array:
                foreach (var item in element.EnumerateArray())
                {
                    Collect(item, features, cancellationToken);
                    if (features.Count >= 4096) return;
                }
                break;
        }
    }

    private static void AddFeature(float[] vector, string feature, float weight)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(feature));
        var dimension = BinaryPrimitives.ReadUInt32LittleEndian(hash) % (uint)vector.Length;
        var sign = (hash[4] & 1) == 0 ? 1f : -1f;
        vector[dimension] += sign * weight;
    }

    [GeneratedRegex(@"[\p{L}\p{Nd}]+", RegexOptions.CultureInvariant)]
    private static partial Regex TokenPattern();
}

public sealed class UnavailableEmbeddingService : IEmbeddingService
{
    public Task<SemanticEmbeddingGeneration> GenerateAsync(
        SemanticEmbeddingRequest request,
        CancellationToken cancellationToken) => Task.FromException<SemanticEmbeddingGeneration>(
        new SemanticEmbeddingException(
            "embedding-provider-unavailable",
            retryable: true,
            providerCallAccounting: SemanticProviderCallAccounting.NotInvoked));
}
