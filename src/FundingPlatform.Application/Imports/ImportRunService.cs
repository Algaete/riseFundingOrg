using FundingPlatform.Core.Validation;
using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Core.Imports;

namespace FundingPlatform.Application.Imports;

public sealed class ImportRunService(IImportRunRepository repository) : IImportRunService
{
    private const int MinimumIdempotencyKeyLength = 16;
    private const int MaximumIdempotencyKeyLength = 128;

    public async Task<ImportRunResult<ImportRunAccepted>> CreateManualAsync(
        Guid adminUserPublicId,
        int fundingSourceId,
        string keyword,
        int maximumResults,
        string idempotencyKey,
        string correlationId,
        CancellationToken cancellationToken)
    {
        var errors = ValidateCreate(
            adminUserPublicId, fundingSourceId, keyword, maximumResults,
            idempotencyKey, correlationId);
        if (errors.Count > 0)
        {
            return new ImportRunResult<ImportRunAccepted>(
                ImportRunOutcome.Invalid, Errors: errors, Code: "invalid-request");
        }

        var normalizedKeyword = keyword.Trim();
        var normalizedKey = idempotencyKey.Trim();
        var idempotencyKeyHash = SHA256.HashData(Encoding.UTF8.GetBytes(normalizedKey));
        var requestMaterial = string.Join('\n',
            "import-run:create-manual:v1",
            fundingSourceId.ToString(System.Globalization.CultureInfo.InvariantCulture),
            normalizedKeyword,
            maximumResults.ToString(System.Globalization.CultureInfo.InvariantCulture));
        var requestHash = SHA256.HashData(Encoding.UTF8.GetBytes(requestMaterial));

        try
        {
            var mutation = await repository.CreateManualAsync(
                adminUserPublicId,
                fundingSourceId,
                normalizedKeyword,
                maximumResults,
                idempotencyKeyHash,
                requestHash,
                correlationId.Trim(),
                cancellationToken);

            if (mutation.Succeeded && mutation.Run is not null)
            {
                return new ImportRunResult<ImportRunAccepted>(
                    ImportRunOutcome.Success, mutation.Run, Code: mutation.Code);
            }

            return new ImportRunResult<ImportRunAccepted>(
                mutation.Code switch
                {
                    "not-found" => ImportRunOutcome.NotFound,
                    "forbidden" => ImportRunOutcome.Forbidden,
                    "idempotency-conflict" => ImportRunOutcome.Conflict,
                    "source-disabled" or "compliance-required" or
                        "provider-not-allowlisted" or "provider-not-supported" =>
                        ImportRunOutcome.Invalid,
                    _ => ImportRunOutcome.Conflict
                },
                Code: NormalizeCode(mutation.Code));
        }
        catch (ImportRunDataException exception)
        {
            return new ImportRunResult<ImportRunAccepted>(
                IsForbidden(exception) ? ImportRunOutcome.Forbidden : ImportRunOutcome.Unavailable,
                Code: IsForbidden(exception) ? "forbidden" : "persistence-unavailable");
        }
    }

    public async Task<ImportRunResult<ImportRunPage>> ListAsync(
        Guid adminUserPublicId,
        int? fundingSourceId,
        ImportRunStatus? status,
        int page,
        int pageSize,
        CancellationToken cancellationToken)
    {
        var errors = ValidateQuery(adminUserPublicId, fundingSourceId, status, page, pageSize);
        if (errors.Count > 0)
        {
            return new ImportRunResult<ImportRunPage>(
                ImportRunOutcome.Invalid, Errors: errors, Code: "invalid-query");
        }

        try
        {
            return new ImportRunResult<ImportRunPage>(
                ImportRunOutcome.Success,
                await repository.ListAsync(
                    adminUserPublicId, fundingSourceId, status, page, pageSize, cancellationToken));
        }
        catch (ImportRunDataException exception)
        {
            return new ImportRunResult<ImportRunPage>(
                IsForbidden(exception) ? ImportRunOutcome.Forbidden : ImportRunOutcome.Unavailable,
                Code: IsForbidden(exception) ? "forbidden" : "persistence-unavailable");
        }
    }

    public async Task<ImportRunResult<ImportRunDetail>> GetAsync(
        Guid adminUserPublicId,
        Guid runId,
        CancellationToken cancellationToken)
    {
        if (adminUserPublicId == Guid.Empty || runId == Guid.Empty)
        {
            return new ImportRunResult<ImportRunDetail>(
                ImportRunOutcome.Invalid,
                Errors: new FieldValidationErrors
                {
                    { adminUserPublicId == Guid.Empty ? "adminUserId" : "runId", "api-validation-146", "El identificador no es válido." }
                },
                Code: "invalid-query");
        }

        try
        {
            var detail = await repository.GetAsync(adminUserPublicId, runId, cancellationToken);
            return detail is null
                ? new ImportRunResult<ImportRunDetail>(ImportRunOutcome.NotFound, Code: "not-found")
                : new ImportRunResult<ImportRunDetail>(ImportRunOutcome.Success, detail);
        }
        catch (ImportRunDataException exception)
        {
            return new ImportRunResult<ImportRunDetail>(
                IsForbidden(exception) ? ImportRunOutcome.Forbidden : ImportRunOutcome.Unavailable,
                Code: IsForbidden(exception) ? "forbidden" : "persistence-unavailable");
        }
    }

    private static FieldValidationErrors ValidateCreate(
        Guid adminUserPublicId,
        int fundingSourceId,
        string? keyword,
        int maximumResults,
        string? idempotencyKey,
        string? correlationId)
    {
        var errors = new FieldValidationErrors();
        if (adminUserPublicId == Guid.Empty)
        {
            errors.Set("adminUserId", "api-validation-143", "El usuario administrador no es válido.");
        }

        if (fundingSourceId <= 0)
        {
            errors.Set("fundingSourceId", "api-validation-161", "La fuente no es válida.");
        }

        var normalizedKeyword = keyword?.Trim() ?? string.Empty;
        if (normalizedKeyword.Length is < 2 or > 100)
        {
            errors.Set("keyword", "api-validation-162", "La búsqueda debe tener entre 2 y 100 caracteres.");
        }

        if (maximumResults is < 1 or > 25)
        {
            errors.Set("maximumResults", "api-validation-163", "La cantidad debe estar entre 1 y 25.");
        }

        var normalizedKey = idempotencyKey?.Trim() ?? string.Empty;
        if (normalizedKey.Length is < MinimumIdempotencyKeyLength or > MaximumIdempotencyKeyLength)
        {
            errors.Set("idempotencyKey", "api-validation-004", $"Idempotency-Key debe tener entre {MinimumIdempotencyKeyLength} y {MaximumIdempotencyKeyLength} caracteres.", min: MinimumIdempotencyKeyLength, max: MaximumIdempotencyKeyLength);
        }

        var normalizedCorrelationId = correlationId?.Trim() ?? string.Empty;
        if (normalizedCorrelationId.Length is < 1 or > 100 ||
            normalizedCorrelationId.Any(character =>
                !(char.IsAsciiLetterOrDigit(character) || character is '-' or '_' or '.' or ':')))
        {
            errors.Set("correlationId", "api-validation-164", "El identificador de correlación no es válido.");
        }

        return errors;
    }

    private static FieldValidationErrors ValidateQuery(
        Guid adminUserPublicId,
        int? fundingSourceId,
        ImportRunStatus? status,
        int page,
        int pageSize)
    {
        var errors = new FieldValidationErrors();
        if (adminUserPublicId == Guid.Empty)
        {
            errors.Set("adminUserId", "api-validation-143", "El usuario administrador no es válido.");
        }

        if (fundingSourceId is <= 0)
        {
            errors.Set("fundingSourceId", "api-validation-161", "La fuente no es válida.");
        }

        if (status.HasValue && !Enum.IsDefined(status.Value))
        {
            errors.Set("status", "api-validation-165", "El estado no es válido.");
        }

        if (page < 1)
        {
            errors.Set("page", "api-validation-166", "La página debe ser mayor o igual a 1.");
        }

        if (pageSize is < 1 or > 100)
        {
            errors.Set("pageSize", "api-validation-148", "El tamaño de página debe estar entre 1 y 100.");
        }

        return errors;
    }

    private static bool IsForbidden(ImportRunDataException exception) =>
        exception.DatabaseErrorNumber is 51001 or 51601 or 51602;

    private static string NormalizeCode(string? code) =>
        string.IsNullOrWhiteSpace(code) ? "operation-failed" : code.Trim().ToLowerInvariant();
}
