using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Application.FundingOpportunities;

internal static class FundingEditorialServiceSupport
{
    internal const int MinimumIdempotencyKeyLength = 16;
    internal const int MaximumIdempotencyKeyLength = 128;
    internal const int MaximumReasonLength = 1000;
    internal static readonly JsonSerializerOptions SnapshotOptions = new(JsonSerializerDefaults.Web);

    internal static bool TryPrepareCommand(
        string action,
        Guid? entityPublicId,
        byte[]? expectedRowVersion,
        bool requiresRowVersion,
        string? idempotencyKey,
        object payload,
        out byte[] idempotencyKeyHash,
        out byte[] requestHash,
        out string canonicalPayload,
        out Dictionary<string, string[]> errors)
    {
        errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        idempotencyKeyHash = [];
        requestHash = [];
        canonicalPayload = JsonSerializer.Serialize(payload, SnapshotOptions);

        if (requiresRowVersion && expectedRowVersion is not { Length: 8 })
        {
            errors["ifMatch"] = ["If-Match no contiene una versión válida."];
        }

        var normalizedKey = idempotencyKey?.Trim() ?? string.Empty;
        if (normalizedKey.Length is < MinimumIdempotencyKeyLength or > MaximumIdempotencyKeyLength)
        {
            errors["idempotencyKey"] =
                [$"Idempotency-Key debe tener entre {MinimumIdempotencyKeyLength} y {MaximumIdempotencyKeyLength} caracteres."];
        }

        if (errors.Count > 0)
        {
            return false;
        }

        idempotencyKeyHash = SHA256.HashData(Encoding.UTF8.GetBytes(normalizedKey));
        var canonicalRequest = string.Join('\n',
            action,
            entityPublicId?.ToString("D") ?? string.Empty,
            expectedRowVersion is null ? string.Empty : Convert.ToHexString(expectedRowVersion),
            canonicalPayload);
        requestHash = SHA256.HashData(Encoding.UTF8.GetBytes(canonicalRequest));
        return true;
    }

    internal static FundingEditorialCommandResult MapMutation(FundingEditorialMutation mutation)
    {
        var errors = ToErrors(mutation.Issues);
        if (mutation.Code == "source-link-conflict" && errors is null)
        {
            errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
            {
                ["fundingSourceId"] =
                    ["La fuente seleccionada ya contiene otra oportunidad con la misma referencia de origen."],
                ["externalId"] =
                    ["El ID en la fuente debe identificar una única oportunidad. Revisa que corresponda al registro que estás editando."],
                ["sourceUrl"] =
                    ["Revisa que la URL oficial y el ID en la fuente correspondan al mismo registro del proveedor."]
            };
        }

        var outcome = mutation.Succeeded
            ? FundingEditorialOutcome.Success
            : mutation.Code switch
            {
                "not-found" => FundingEditorialOutcome.NotFound,
                "forbidden" => FundingEditorialOutcome.Forbidden,
                "etag-conflict" => FundingEditorialOutcome.PreconditionFailed,
                "slug-conflict" or "name-conflict" or "alias-conflict" or "source-link-conflict" =>
                    FundingEditorialOutcome.Conflict,
                "invalid-transition" => FundingEditorialOutcome.InvalidTransition,
                "funder-not-ready" or "opportunity-not-ready" => FundingEditorialOutcome.NotReady,
                "idempotency-conflict" => FundingEditorialOutcome.IdempotencyConflict,
                "rejection-reason-required" or "funder-not-found" or "source-disabled" or
                    "invalid-document" or "invalid-decision" =>
                    FundingEditorialOutcome.ValidationFailed,
                _ => FundingEditorialOutcome.Conflict
            };

        return new FundingEditorialCommandResult(
            outcome,
            mutation.EntityPublicId,
            mutation.PublicationStatus,
            mutation.ContentVersion,
            mutation.RowVersion,
            mutation.WasReplay,
            errors,
            NormalizeCode(mutation.Code));
    }

    internal static Dictionary<string, string[]> ValidateReview(
        FundingReviewDecision decision,
        string? reason)
    {
        var errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        if (decision is not FundingReviewDecision.Approve and not FundingReviewDecision.Reject)
        {
            errors["decision"] = ["La decisión debe ser approve o reject."];
        }
        else if (decision == FundingReviewDecision.Reject && string.IsNullOrWhiteSpace(reason))
        {
            errors["reason"] = ["El motivo es obligatorio al rechazar."];
        }
        else if (decision == FundingReviewDecision.Approve && reason is not null)
        {
            errors["reason"] = ["Una aprobación no admite motivo de rechazo."];
        }

        ValidateLength(reason, MaximumReasonLength, "reason", errors);
        return errors;
    }

    internal static Dictionary<string, string[]> ValidateCorrectionReason(string? reason)
    {
        var errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        if (reason is null || reason.Length is < 3 or > MaximumReasonLength)
        {
            errors["reason"] =
                [$"El motivo debe tener entre 3 y {MaximumReasonLength} caracteres."];
        }

        return errors;
    }

    internal static void ValidateLength(
        string? value,
        int maximum,
        string field,
        IDictionary<string, string[]> errors)
    {
        if (value?.Length > maximum)
        {
            errors[field] = [$"Admite hasta {maximum} caracteres."];
        }
    }

    internal static bool IsSafeHttpUrl(string? value)
    {
        if (value is null)
        {
            return true;
        }

        return value.Length <= 2048 &&
            Uri.TryCreate(value, UriKind.Absolute, out var uri) &&
            (uri.Scheme == Uri.UriSchemeHttps || uri.Scheme == Uri.UriSchemeHttp) &&
            string.IsNullOrEmpty(uri.UserInfo);
    }

    internal static string CreateSlug(string value, byte[] idempotencyKeyHash, int maximumLength)
    {
        var decomposed = value.Normalize(NormalizationForm.FormD);
        var slug = new string(decomposed
            .Where(character => CharUnicodeInfo.GetUnicodeCategory(character) !=
                UnicodeCategory.NonSpacingMark)
            .Select(character => char.IsLetterOrDigit(character)
                ? char.ToLowerInvariant(character)
                : '-')
            .ToArray());
        slug = string.Join('-', slug.Split('-', StringSplitOptions.RemoveEmptyEntries));
        if (slug.Length == 0)
        {
            slug = "registro";
        }

        var suffix = Convert.ToHexString(idempotencyKeyHash.AsSpan(0, 4)).ToLowerInvariant();
        var prefixLength = Math.Max(1, maximumLength - suffix.Length - 1);
        if (slug.Length > prefixLength)
        {
            slug = slug[..prefixLength].TrimEnd('-');
        }

        return $"{slug}-{suffix}";
    }

    internal static string? NormalizeOptional(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    internal static bool IsForbidden(FundingEditorialDataException exception) =>
        exception.DatabaseErrorNumber is 51503 or 51601 or 51602 or 51701;

    private static IReadOnlyDictionary<string, string[]>? ToErrors(
        IReadOnlyList<FundingReadinessIssue> issues)
    {
        if (issues.Count == 0)
        {
            return null;
        }

        return issues
            .GroupBy(issue => string.IsNullOrWhiteSpace(issue.FieldPath) ? "entity" : issue.FieldPath)
            .ToDictionary(
                group => group.Key,
                group => group.Select(issue => issue.Message)
                    .Distinct(StringComparer.Ordinal)
                    .ToArray(),
                StringComparer.OrdinalIgnoreCase);
    }

    private static string NormalizeCode(string code) => code switch
    {
        "created" or "updated" or "review-requested" or "published" or "rejected" or
        "deactivated" or "not-found" or "forbidden" or "etag-conflict" or
        "invalid-transition" or "idempotency-conflict" or "slug-conflict" or
        "name-conflict" or "alias-conflict" or "funder-not-found" or
        "opportunity-not-ready" or "funder-not-ready" or "rejection-reason-required" or
        "invalid-document" or "invalid-decision" or "source-disabled" or
        "source-link-conflict" => code,
        _ => "funding-editorial-conflict"
    };
}
