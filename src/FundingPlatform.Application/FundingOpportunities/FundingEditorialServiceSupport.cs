using FundingPlatform.Core.Validation;
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
        out FieldValidationErrors errors)
    {
        errors = new FieldValidationErrors();
        idempotencyKeyHash = [];
        requestHash = [];
        canonicalPayload = JsonSerializer.Serialize(payload, SnapshotOptions);

        if (requiresRowVersion && expectedRowVersion is not { Length: 8 })
        {
            errors.Set("ifMatch", "version-invalid", "If-Match no contiene una versión válida.");
        }

        var normalizedKey = idempotencyKey?.Trim() ?? string.Empty;
        if (normalizedKey.Length is < MinimumIdempotencyKeyLength or > MaximumIdempotencyKeyLength)
        {
            errors.Set("idempotencyKey", "api-validation-004", $"Idempotency-Key debe tener entre {MinimumIdempotencyKeyLength} y {MaximumIdempotencyKeyLength} caracteres.", min: MinimumIdempotencyKeyLength, max: MaximumIdempotencyKeyLength);
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
            errors = new FieldValidationErrors()
            {
                { "fundingSourceId", "api-validation-102", "La fuente seleccionada ya contiene otra oportunidad con la misma referencia de origen." },
                { "externalId", "api-validation-103", "El ID en la fuente debe identificar una única oportunidad. Revisa que corresponda al registro que estás editando." },
                { "sourceUrl", "api-validation-104", "Revisa que la URL oficial y el ID en la fuente correspondan al mismo registro del proveedor." }
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

    internal static FieldValidationErrors ValidateReview(
        FundingReviewDecision decision,
        string? reason)
    {
        var errors = new FieldValidationErrors();
        if (decision is not FundingReviewDecision.Approve and not FundingReviewDecision.Reject)
        {
            errors.Set("decision", "api-validation-105", "La decisión debe ser approve o reject.");
        }
        else if (decision == FundingReviewDecision.Reject && string.IsNullOrWhiteSpace(reason))
        {
            errors.Set("reason", "api-validation-106", "El motivo es obligatorio al rechazar.");
        }
        else if (decision == FundingReviewDecision.Approve && reason is not null)
        {
            errors.Set("reason", "api-validation-107", "Una aprobación no admite motivo de rechazo.");
        }

        ValidateLength(reason, MaximumReasonLength, "reason", errors);
        return errors;
    }

    internal static FieldValidationErrors ValidateCorrectionReason(string? reason)
    {
        var errors = new FieldValidationErrors();
        if (reason is null || reason.Length is < 3 or > MaximumReasonLength)
        {
            errors.Set("reason", "api-validation-108", $"El motivo debe tener entre 3 y {MaximumReasonLength} caracteres.", max: MaximumReasonLength);
        }

        return errors;
    }

    internal static void ValidateLength(
        string? value,
        int maximum,
        string field,
        FieldValidationErrors errors)
    {
        if (value?.Length > maximum)
        {
            errors.Set(field, "text-max-length", $"Admite hasta {maximum} caracteres.", max: maximum);
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

        var errors = new FieldValidationErrors();
        foreach (var issue in issues)
            errors.Add(string.IsNullOrWhiteSpace(issue.FieldPath) ? "entity" : issue.FieldPath,
                $"funding-ready-{issue.Code}", TranslateReadinessMessage(issue));
        return errors;
    }

    private static string TranslateReadinessMessage(FundingReadinessIssue issue) => issue.Code switch
    {
        "name" => "Ingresa el nombre del financiador.",
        "slug" =>
            "El financiador no tiene un identificador público válido. Contacta a soporte para corregirlo.",
        "websiteUrl" => "Agrega el sitio web oficial del financiador.",
        "primaryAlias" => "Agrega un nombre principal al financiador.",
        "title" => "Ingresa el título de la oportunidad.",
        "primaryFunder" =>
            "Publica el financiador principal antes de enviar la oportunidad a revisión.",
        "officialSource" =>
            "Selecciona una fuente principal habilitada con una URL oficial.",
        "geographicScope" =>
            "Define el alcance geográfico como específico o global.",
        "countries" =>
            "Selecciona al menos un país elegible para el alcance geográfico específico.",
        "globalGeography" =>
            "Elimina los países y regiones cuando el alcance geográfico sea global.",
        "categories" => "Selecciona al menos una categoría de financiamiento.",
        "inactiveCatalogReference" =>
            "Revisa la moneda, el tipo de financiamiento, el alcance, las categorías y el financiador principal. Alguna selección está inactiva o no es coherente.",
        "criticalEvidence" =>
            "Completa la evidencia del título, la descripción, la elegibilidad y el cierre, o marca expresamente el dato como desconocido.",
        _ => issue.Message
    };

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
