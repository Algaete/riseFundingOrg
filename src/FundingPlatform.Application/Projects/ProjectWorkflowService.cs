using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Core.Projects;

namespace FundingPlatform.Application.Projects;

public sealed class ProjectWorkflowService(IProjectRepository repository)
{
    public const int MinimumIdempotencyKeyLength = 16;
    public const int MaximumIdempotencyKeyLength = 128;
    public const int MaximumRejectionReasonLength = 1000;

    public async Task<ProjectWorkflowResult> RequestPublicationAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        byte[] expectedRowVersion,
        string idempotencyKey,
        CancellationToken cancellationToken)
    {
        if (!TryPrepareMutation(
                ProjectWorkflowAction.RequestPublication,
                organizationPublicId,
                projectPublicId,
                expectedRowVersion,
                idempotencyKey,
                payload: null,
                out var idempotencyKeyHash,
                out var requestHash,
                out var errors))
        {
            return ValidationFailure(projectPublicId, errors);
        }

        try
        {
            var mutation = await repository.RequestPublicationAsync(
                userPublicId,
                organizationPublicId,
                projectPublicId,
                expectedRowVersion,
                idempotencyKeyHash,
                requestHash,
                cancellationToken);
            return MapMutation(mutation);
        }
        catch (ProjectDataException exception) when (IsNotFound(exception.DatabaseErrorNumber))
        {
            return NotFound(projectPublicId);
        }
    }

    public async Task<ProjectWorkflowResult> ArchiveAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        byte[] expectedRowVersion,
        string idempotencyKey,
        CancellationToken cancellationToken)
    {
        if (!TryPrepareMutation(
                ProjectWorkflowAction.Archive,
                organizationPublicId,
                projectPublicId,
                expectedRowVersion,
                idempotencyKey,
                payload: null,
                out var idempotencyKeyHash,
                out var requestHash,
                out var errors))
        {
            return ValidationFailure(projectPublicId, errors);
        }

        try
        {
            var mutation = await repository.ArchiveAsync(
                userPublicId,
                organizationPublicId,
                projectPublicId,
                expectedRowVersion,
                idempotencyKeyHash,
                requestHash,
                cancellationToken);
            return MapMutation(mutation);
        }
        catch (ProjectDataException exception) when (IsNotFound(exception.DatabaseErrorNumber))
        {
            return NotFound(projectPublicId);
        }
    }

    public async Task<ProjectReviewQueueResult> ListReviewQueueAsync(
        Guid userPublicId,
        int pageNumber,
        int pageSize,
        CancellationToken cancellationToken)
    {
        if (pageNumber < 1)
        {
            throw new ArgumentOutOfRangeException(nameof(pageNumber));
        }

        if (pageSize is < 1 or > 100)
        {
            throw new ArgumentOutOfRangeException(nameof(pageSize));
        }

        try
        {
            var page = await repository.ListReviewQueueAsync(
                userPublicId,
                pageNumber,
                pageSize,
                cancellationToken);
            return new ProjectReviewQueueResult(ProjectWorkflowOutcome.Success, page);
        }
        catch (ProjectDataException exception) when (exception.DatabaseErrorNumber == 51503)
        {
            return new ProjectReviewQueueResult(ProjectWorkflowOutcome.Forbidden);
        }
    }

    public async Task<ProjectReviewDetailsResult> GetReviewDetailsAsync(
        Guid userPublicId,
        Guid projectPublicId,
        CancellationToken cancellationToken)
    {
        try
        {
            var project = await repository.GetReviewDetailsAsync(
                userPublicId, projectPublicId, cancellationToken);
            return project is null
                ? new ProjectReviewDetailsResult(ProjectWorkflowOutcome.NotFound)
                : new ProjectReviewDetailsResult(ProjectWorkflowOutcome.Success, project);
        }
        catch (ProjectDataException exception) when (exception.DatabaseErrorNumber == 51503)
        {
            return new ProjectReviewDetailsResult(ProjectWorkflowOutcome.Forbidden);
        }
        catch (ProjectDataException exception) when (IsNotFound(exception.DatabaseErrorNumber))
        {
            return new ProjectReviewDetailsResult(ProjectWorkflowOutcome.NotFound);
        }
    }

    public async Task<ProjectWorkflowResult> ReviewAsync(
        Guid userPublicId,
        Guid projectPublicId,
        ProjectReviewDecision decision,
        string? reason,
        byte[] expectedRowVersion,
        string idempotencyKey,
        CancellationToken cancellationToken)
    {
        var normalizedReason = NormalizeOptional(reason);
        var errors = ValidateReview(decision, normalizedReason);

        if (!TryPrepareMutation(
                decision == ProjectReviewDecision.Approve
                    ? ProjectWorkflowAction.Approve
                    : ProjectWorkflowAction.Reject,
                organizationPublicId: null,
                projectPublicId,
                expectedRowVersion,
                idempotencyKey,
                normalizedReason,
                out var idempotencyKeyHash,
                out var requestHash,
                out var mutationErrors))
        {
            Merge(errors, mutationErrors);
        }

        if (errors.Count > 0)
        {
            return ValidationFailure(projectPublicId, errors);
        }

        try
        {
            var mutation = await repository.ReviewAsync(
                userPublicId,
                projectPublicId,
                decision,
                normalizedReason,
                expectedRowVersion,
                idempotencyKeyHash,
                requestHash,
                cancellationToken);
            return MapMutation(mutation);
        }
        catch (ProjectDataException exception) when (IsNotFound(exception.DatabaseErrorNumber))
        {
            return NotFound(projectPublicId);
        }
    }

    public Task<PublicProjectDetails?> GetPublishedBySlugAsync(
        string slug,
        CancellationToken cancellationToken)
    {
        var normalized = slug?.Trim();
        return string.IsNullOrWhiteSpace(normalized) || normalized.Length > 180
            ? Task.FromResult<PublicProjectDetails?>(null)
            : repository.GetPublishedBySlugAsync(normalized, cancellationToken);
    }

    private static ProjectWorkflowResult MapMutation(ProjectWorkflowMutation mutation)
    {
        if (mutation.Succeeded)
        {
            return new ProjectWorkflowResult(
                ProjectWorkflowOutcome.Success,
                mutation.ProjectPublicId,
                mutation.Completeness,
                mutation.PublicationStatus,
                mutation.RowVersion,
                mutation.WasReplay,
                SubmittedAtUtc: mutation.SubmittedAtUtc,
                PublishedAtUtc: mutation.PublishedAtUtc,
                ReviewedAtUtc: mutation.ReviewedAtUtc,
                ReviewedByUserPublicId: mutation.ReviewedByUserPublicId,
                RejectionReason: mutation.RejectionReason);
        }

        var outcome = mutation.Code switch
        {
            "not-found" => ProjectWorkflowOutcome.NotFound,
            "forbidden" => ProjectWorkflowOutcome.Forbidden,
            "etag-conflict" => ProjectWorkflowOutcome.Conflict,
            "invalid-transition" => ProjectWorkflowOutcome.InvalidTransition,
            "project-not-ready" => ProjectWorkflowOutcome.NotReady,
            "organization-not-ready" => ProjectWorkflowOutcome.NotReady,
            "idempotency-conflict" => ProjectWorkflowOutcome.IdempotencyConflict,
            _ => ProjectWorkflowOutcome.Conflict
        };

        return new ProjectWorkflowResult(
            outcome,
            mutation.ProjectPublicId,
            mutation.Completeness,
            mutation.PublicationStatus,
            mutation.RowVersion,
            mutation.WasReplay,
            mutation.Code == "organization-not-ready" && mutation.Issues.Count == 0
                ? new Dictionary<string, string[]>
                {
                    ["organizationProfile"] =
                        ["La organización debe completar y publicar su perfil antes de aprobar el proyecto."]
                }
                : ToErrors(mutation.Issues),
            mutation.SubmittedAtUtc,
            mutation.PublishedAtUtc,
            mutation.ReviewedAtUtc,
            mutation.ReviewedByUserPublicId,
            mutation.RejectionReason);
    }

    private static bool TryPrepareMutation(
        ProjectWorkflowAction action,
        Guid? organizationPublicId,
        Guid projectPublicId,
        byte[] expectedRowVersion,
        string idempotencyKey,
        string? payload,
        out byte[] idempotencyKeyHash,
        out byte[] requestHash,
        out Dictionary<string, string[]> errors)
    {
        errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        idempotencyKeyHash = [];
        requestHash = [];

        if (expectedRowVersion is not { Length: 8 })
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
            action.ToString(),
            organizationPublicId?.ToString("D") ?? string.Empty,
            projectPublicId.ToString("D"),
            Convert.ToHexString(expectedRowVersion),
            payload ?? string.Empty);
        requestHash = SHA256.HashData(Encoding.UTF8.GetBytes(canonicalRequest));
        return true;
    }

    private static Dictionary<string, string[]> ValidateReview(
        ProjectReviewDecision decision,
        string? reason)
    {
        var errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        if (decision is not ProjectReviewDecision.Approve and not ProjectReviewDecision.Reject)
        {
            errors["decision"] = ["La decisión debe ser approve o reject."];
        }
        else if (decision == ProjectReviewDecision.Reject && string.IsNullOrWhiteSpace(reason))
        {
            errors["reason"] = ["El motivo es obligatorio al rechazar un proyecto."];
        }
        else if (decision == ProjectReviewDecision.Approve && reason is not null)
        {
            errors["reason"] = ["Una aprobación no admite motivo de rechazo."];
        }

        if (reason?.Length > MaximumRejectionReasonLength)
        {
            errors["reason"] = [$"El motivo admite hasta {MaximumRejectionReasonLength} caracteres."];
        }

        return errors;
    }

    private static IReadOnlyDictionary<string, string[]> ToErrors(
        IReadOnlyList<ProjectReadinessIssue> issues) =>
        issues
            .GroupBy(issue => string.IsNullOrWhiteSpace(issue.FieldPath) ? "project" : issue.FieldPath)
            .ToDictionary(
                group => group.Key,
                group => group.Select(issue => issue.Message).Distinct(StringComparer.Ordinal).ToArray(),
                StringComparer.OrdinalIgnoreCase);

    private static void Merge(
        IDictionary<string, string[]> target,
        IReadOnlyDictionary<string, string[]> source)
    {
        foreach (var (key, value) in source)
        {
            target[key] = value;
        }
    }

    private static ProjectWorkflowResult ValidationFailure(
        Guid projectPublicId,
        IReadOnlyDictionary<string, string[]> errors) =>
        new(ProjectWorkflowOutcome.ValidationFailed, projectPublicId, Errors: errors);

    private static ProjectWorkflowResult NotFound(Guid projectPublicId) =>
        new(ProjectWorkflowOutcome.NotFound, projectPublicId);

    private static bool IsNotFound(int databaseErrorNumber) =>
        databaseErrorNumber is 51401 or 51402 or 51405 or 51406;

    private static string? NormalizeOptional(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
