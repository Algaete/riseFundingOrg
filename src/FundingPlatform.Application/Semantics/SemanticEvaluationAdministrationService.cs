using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Core.Semantics;

namespace FundingPlatform.Application.Semantics;

public sealed class SemanticEvaluationAdministrationService(
    ISemanticEvaluationRepository repository,
    SemanticProcessingPolicy policy,
    TimeProvider timeProvider)
{
    public const int MinimumIdempotencyKeyLength = 16;
    public const int MaximumIdempotencyKeyLength = 128;
    public const int MaximumPageSize = 100;
    private const string RequestContractVersion = "semantic-evaluation-run-create-v1";

    public async Task<SemanticEvaluationResult<SemanticEvaluationRunMutation>> CreateAsync(
        Guid adminUserPublicId,
        string? evaluationSetVersion,
        string? semanticConfigurationVersion,
        string? idempotencyKey,
        CancellationToken cancellationToken)
    {
        var errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        if (adminUserPublicId == Guid.Empty)
            errors["adminUserId"] = ["El usuario administrador no es válido."];
        var evalSet = NormalizeVersion(evaluationSetVersion);
        if (evalSet is null)
            errors["evalSetVersion"] = ["La versión del conjunto de evaluación no es válida."];
        var configuration = NormalizeVersion(semanticConfigurationVersion);
        if (configuration is null)
            errors["semanticConfigurationVersion"] =
                ["La versión de configuración semántica no es válida."];
        var normalizedKey = idempotencyKey?.Trim() ?? string.Empty;
        if (normalizedKey.Length is < MinimumIdempotencyKeyLength or > MaximumIdempotencyKeyLength)
            errors["idempotencyKey"] =
                [$"Idempotency-Key debe tener entre {MinimumIdempotencyKeyLength} y {MaximumIdempotencyKeyLength} caracteres."];
        if (errors.Count > 0)
            return new SemanticEvaluationResult<SemanticEvaluationRunMutation>(
                SemanticEvaluationOutcome.Invalid, Errors: errors, Code: "invalid-request");

        policy.Validate();
        var keyHash = SHA256.HashData(Encoding.UTF8.GetBytes(normalizedKey));
        var requestHash = SHA256.HashData(Encoding.UTF8.GetBytes(string.Join('\n',
            RequestContractVersion, evalSet, configuration)));
        try
        {
            var mutation = await repository.CreateAsync(
                adminUserPublicId,
                evalSet!,
                configuration!,
                keyHash,
                requestHash,
                policy.Enabled,
                timeProvider.GetUtcNow(),
                cancellationToken);
            if (mutation.Succeeded && mutation.Run is not null &&
                IsSafeSummary(mutation.Run))
                return new SemanticEvaluationResult<SemanticEvaluationRunMutation>(
                    SemanticEvaluationOutcome.Success, mutation, mutation.Code);

            if (mutation.Succeeded)
                return new SemanticEvaluationResult<SemanticEvaluationRunMutation>(
                    SemanticEvaluationOutcome.Unavailable,
                    Code: "semantic-data-invalid");

            return new SemanticEvaluationResult<SemanticEvaluationRunMutation>(
                mutation.Code switch
                {
                    "forbidden" => SemanticEvaluationOutcome.Forbidden,
                    "not-found" => SemanticEvaluationOutcome.NotFound,
                    "idempotency-conflict" or "active-evaluation-exists" =>
                        SemanticEvaluationOutcome.Conflict,
                    "eval-set-not-ready" or "configuration-not-approved" or
                    "budget-insufficient" =>
                        SemanticEvaluationOutcome.Invalid,
                    "semantic-processing-disabled" => SemanticEvaluationOutcome.Unavailable,
                    _ => SemanticEvaluationOutcome.Unavailable
                },
                Code: NormalizeCode(mutation.Code));
        }
        catch (SemanticProcessingDataException exception)
        {
            return new SemanticEvaluationResult<SemanticEvaluationRunMutation>(
                exception.DatabaseErrorNumber switch
                {
                    51601 or 51602 => SemanticEvaluationOutcome.Forbidden,
                    54126 => SemanticEvaluationOutcome.Conflict,
                    54127 or 54129 => SemanticEvaluationOutcome.Invalid,
                    _ => SemanticEvaluationOutcome.Unavailable
                },
                Code: exception.DatabaseErrorNumber switch
                {
                    51601 or 51602 => "forbidden",
                    54126 => "idempotency-conflict",
                    54127 or 54129 => "eval-set-not-ready",
                    _ => "persistence-unavailable"
                });
        }
    }

    public async Task<SemanticEvaluationResult<SemanticEvaluationRunPage>> ListAsync(
        Guid adminUserPublicId,
        int page,
        int pageSize,
        CancellationToken cancellationToken)
    {
        var errors = ValidateQuery(adminUserPublicId, page, pageSize);
        if (errors.Count > 0)
            return new SemanticEvaluationResult<SemanticEvaluationRunPage>(
                SemanticEvaluationOutcome.Invalid, Errors: errors, Code: "invalid-query");
        try
        {
            var pageResult = await repository.ListAsync(
                adminUserPublicId, page, pageSize, cancellationToken);
            if (pageResult.Items.Any(run => !IsSafeSummary(run)))
                return new SemanticEvaluationResult<SemanticEvaluationRunPage>(
                    SemanticEvaluationOutcome.Unavailable,
                    Code: "semantic-data-invalid");
            return new SemanticEvaluationResult<SemanticEvaluationRunPage>(
                SemanticEvaluationOutcome.Success,
                pageResult);
        }
        catch (SemanticProcessingDataException exception)
        {
            return new SemanticEvaluationResult<SemanticEvaluationRunPage>(
                IsForbidden(exception)
                    ? SemanticEvaluationOutcome.Forbidden
                    : SemanticEvaluationOutcome.Unavailable,
                Code: IsForbidden(exception) ? "forbidden" : "persistence-unavailable");
        }
    }

    public async Task<SemanticEvaluationResult<SemanticEvaluationRunDetail>> GetAsync(
        Guid adminUserPublicId,
        Guid runPublicId,
        CancellationToken cancellationToken)
    {
        if (adminUserPublicId == Guid.Empty || runPublicId == Guid.Empty)
            return new SemanticEvaluationResult<SemanticEvaluationRunDetail>(
                SemanticEvaluationOutcome.Invalid,
                Code: "invalid-query",
                Errors: new Dictionary<string, string[]>
                {
                    [adminUserPublicId == Guid.Empty ? "adminUserId" : "runId"] =
                        ["El identificador no es válido."]
                });
        try
        {
            var detail = await repository.GetAsync(
                adminUserPublicId, runPublicId, cancellationToken);
            return detail is null
                ? new SemanticEvaluationResult<SemanticEvaluationRunDetail>(
                    SemanticEvaluationOutcome.NotFound, Code: "not-found")
                : !IsSafeSummary(detail.Run)
                    ? new SemanticEvaluationResult<SemanticEvaluationRunDetail>(
                        SemanticEvaluationOutcome.Unavailable,
                        Code: "semantic-data-invalid")
                : new SemanticEvaluationResult<SemanticEvaluationRunDetail>(
                    SemanticEvaluationOutcome.Success, detail);
        }
        catch (SemanticProcessingDataException exception)
        {
            return new SemanticEvaluationResult<SemanticEvaluationRunDetail>(
                IsForbidden(exception)
                    ? SemanticEvaluationOutcome.Forbidden
                    : SemanticEvaluationOutcome.Unavailable,
                Code: IsForbidden(exception) ? "forbidden" : "persistence-unavailable");
        }
    }

    public async Task<SemanticEvaluationResult<SemanticEvaluationRunReport>> GetReportAsync(
        Guid adminUserPublicId,
        Guid runPublicId,
        CancellationToken cancellationToken)
    {
        if (adminUserPublicId == Guid.Empty || runPublicId == Guid.Empty)
            return new SemanticEvaluationResult<SemanticEvaluationRunReport>(
                SemanticEvaluationOutcome.Invalid,
                Code: "invalid-query",
                Errors: new Dictionary<string, string[]>
                {
                    [adminUserPublicId == Guid.Empty ? "adminUserId" : "runId"] =
                        ["El identificador no es válido."]
                });
        try
        {
            var report = await repository.GetReportAsync(
                adminUserPublicId, runPublicId, cancellationToken);
            return report is null
                ? new SemanticEvaluationResult<SemanticEvaluationRunReport>(
                    SemanticEvaluationOutcome.NotFound, Code: "not-found")
                : !IsSafeSummary(report.Run)
                    ? new SemanticEvaluationResult<SemanticEvaluationRunReport>(
                        SemanticEvaluationOutcome.Unavailable,
                        Code: "semantic-data-invalid")
                : new SemanticEvaluationResult<SemanticEvaluationRunReport>(
                    SemanticEvaluationOutcome.Success, report);
        }
        catch (SemanticProcessingDataException exception)
        {
            return new SemanticEvaluationResult<SemanticEvaluationRunReport>(
                IsForbidden(exception)
                    ? SemanticEvaluationOutcome.Forbidden
                    : SemanticEvaluationOutcome.Unavailable,
                Code: IsForbidden(exception) ? "forbidden" : "persistence-unavailable");
        }
    }

    private static Dictionary<string, string[]> ValidateQuery(
        Guid userId, int page, int pageSize)
    {
        var errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        if (userId == Guid.Empty) errors["adminUserId"] = ["El usuario no es válido."];
        if (page is < 1 or > 10_000) errors["page"] = ["La página no es válida."];
        if (pageSize is < 1 or > MaximumPageSize)
            errors["pageSize"] = ["El tamaño de página debe estar entre 1 y 100."];
        return errors;
    }

    private static string? NormalizeVersion(string? value)
    {
        var normalized = value?.Trim().ToLowerInvariant();
        return normalized is { Length: >= 3 and <= 64 } &&
               char.IsAsciiLetterOrDigit(normalized[0]) &&
               normalized.All(character =>
                   char.IsAsciiLetterOrDigit(character) || character is '-' or '_' or '.')
            ? normalized
            : null;
    }

    private static bool IsForbidden(SemanticProcessingDataException exception) =>
        exception.DatabaseErrorNumber is 51601 or 51602;

    private static bool IsSafeSummary(SemanticEvaluationRunSummary run) =>
        !(run.Metrics.MeetsPromotionGate == true &&
          string.Equals(
              run.ProviderCode,
              "development-deterministic",
              StringComparison.Ordinal) &&
          string.Equals(
              run.ModelCode,
              "lexical-hash-1536-v1",
              StringComparison.Ordinal));

    private static string NormalizeCode(string? code) =>
        string.IsNullOrWhiteSpace(code) ? "operation-failed" : code.Trim().ToLowerInvariant();
}
