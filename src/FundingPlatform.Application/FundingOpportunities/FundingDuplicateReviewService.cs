using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace FundingPlatform.Application.FundingOpportunities;

public sealed record FundingDuplicateCandidateSummary(
    Guid CandidateId,
    Guid CandidateOpportunityId,
    string CandidateTitle,
    string CandidateSponsor,
    Guid? SuggestedCanonicalOpportunityId,
    string? SuggestedCanonicalTitle,
    byte MatchKind,
    decimal Confidence,
    byte Status,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? DecidedAtUtc,
    byte[] RowVersion);

public sealed record FundingDuplicateCandidatePage(
    IReadOnlyList<FundingDuplicateCandidateSummary> Items,
    long TotalCount,
    int Page,
    int PageSize);

public sealed record FundingDuplicateOpportunityPreview(
    Guid OpportunityId,
    string Title,
    string Sponsor,
    byte PublicationStatus);

public sealed record FundingDuplicateDecisionView(
    Guid DecisionId,
    byte Decision,
    Guid? CanonicalOpportunityId,
    string Reason,
    DateTimeOffset CreatedAtUtc);

public sealed record FundingDuplicateCandidateDetails(
    Guid CandidateId,
    FundingDuplicateOpportunityPreview Candidate,
    FundingDuplicateOpportunityPreview? SuggestedCanonical,
    byte MatchKind,
    decimal Confidence,
    string MatchReasonCode,
    byte Status,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? DecidedAtUtc,
    FundingDuplicateDecisionView? Decision,
    byte[] RowVersion);

public sealed record FundingDuplicateDecisionMutation(
    bool Succeeded,
    string Code,
    Guid? CandidateId,
    Guid? DecisionId,
    byte? Status,
    byte? Decision,
    Guid? CanonicalOpportunityId,
    DateTimeOffset? DecidedAtUtc,
    byte[]? RowVersion,
    bool WasReplay);

public interface IFundingDuplicateReviewRepository
{
    Task<FundingDuplicateCandidatePage> ListAsync(
        Guid adminUserId,
        byte? status,
        int page,
        int pageSize,
        CancellationToken cancellationToken);

    Task<FundingDuplicateCandidateDetails?> GetAsync(
        Guid adminUserId,
        Guid candidateId,
        CancellationToken cancellationToken);

    Task<FundingDuplicateDecisionMutation> DecideAsync(
        Guid adminUserId,
        Guid candidateId,
        byte[] expectedRowVersion,
        byte decision,
        Guid? canonicalOpportunityId,
        string reason,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        DateTimeOffset decidedAtUtc,
        CancellationToken cancellationToken);
}

public enum FundingDuplicateReviewOutcome
{
    Success,
    Invalid,
    NotFound,
    Forbidden,
    PreconditionFailed,
    Conflict,
    Unavailable
}

public sealed record FundingDuplicateReviewResult<T>(
    FundingDuplicateReviewOutcome Outcome,
    string Code,
    T? Value = default,
    IReadOnlyDictionary<string, string[]>? Errors = null);

public sealed class FundingDuplicateReviewDataException(
    string operation,
    int databaseErrorNumber,
    Exception? innerException = null) : Exception(
        $"Funding duplicate review operation '{operation}' failed with database error {databaseErrorNumber}.",
        innerException);

public sealed class FundingDuplicateReviewService(
    IFundingDuplicateReviewRepository repository,
    TimeProvider timeProvider)
{
    public async Task<FundingDuplicateReviewResult<FundingDuplicateCandidatePage>> ListAsync(
        Guid adminUserId,
        byte? status,
        int page,
        int pageSize,
        CancellationToken cancellationToken)
    {
        if (adminUserId == Guid.Empty || status is > 1 || page < 1 || pageSize is < 1 or > 100)
            return Invalid<FundingDuplicateCandidatePage>("invalid-duplicate-filter", "filter",
                "Estado o paginación inválidos.");
        try
        {
            return new(FundingDuplicateReviewOutcome.Success, "retrieved",
                await repository.ListAsync(adminUserId, status, page, pageSize, cancellationToken));
        }
        catch (FundingDuplicateReviewDataException)
        {
            return new(FundingDuplicateReviewOutcome.Unavailable, "duplicate-review-unavailable");
        }
    }

    public async Task<FundingDuplicateReviewResult<FundingDuplicateCandidateDetails>> GetAsync(
        Guid adminUserId,
        Guid candidateId,
        CancellationToken cancellationToken)
    {
        if (adminUserId == Guid.Empty || candidateId == Guid.Empty)
            return Invalid<FundingDuplicateCandidateDetails>("invalid-candidate-id", "candidateId",
                "El identificador del candidato no es válido.");
        try
        {
            var value = await repository.GetAsync(adminUserId, candidateId, cancellationToken);
            return value is null
                ? new(FundingDuplicateReviewOutcome.NotFound, "duplicate-candidate-not-found")
                : new(FundingDuplicateReviewOutcome.Success, "retrieved", value);
        }
        catch (FundingDuplicateReviewDataException)
        {
            return new(FundingDuplicateReviewOutcome.Unavailable, "duplicate-review-unavailable");
        }
    }

    public async Task<FundingDuplicateReviewResult<FundingDuplicateDecisionMutation>> DecideAsync(
        Guid adminUserId,
        Guid candidateId,
        byte[] expectedRowVersion,
        string? action,
        Guid? canonicalOpportunityId,
        string? reason,
        string? idempotencyKey,
        CancellationToken cancellationToken)
    {
        var normalizedReason = reason?.Trim();
        var normalizedKey = idempotencyKey?.Trim();
        var decision = action switch
        {
            "keep-separate" => (byte)1,
            "mark-duplicate" => (byte)2,
            "ignored" => (byte)3,
            _ => (byte)0
        };
        var errors = new Dictionary<string, string[]>();
        if (adminUserId == Guid.Empty || candidateId == Guid.Empty)
            errors["candidateId"] = ["El candidato no es válido."];
        if (expectedRowVersion is not { Length: 8 })
            errors["ifMatch"] = ["Envía el ETag fuerte vigente."];
        if (decision == 0)
            errors["decision"] = ["Usa keep-separate, mark-duplicate o ignored."];
        if (string.IsNullOrWhiteSpace(normalizedReason) || normalizedReason.Length is < 3 or > 300 ||
            normalizedReason.Contains('\r') || normalizedReason.Contains('\n') ||
            normalizedReason.Contains('\0'))
            errors["reason"] = ["El motivo debe tener entre 3 y 300 caracteres y una sola línea."];
        if (decision == 2 && canonicalOpportunityId is null)
            errors["canonicalOpportunityId"] = ["Selecciona la oportunidad canónica."];
        if (decision is 1 or 3 && canonicalOpportunityId is not null)
            errors["canonicalOpportunityId"] = ["Esta decisión no admite una oportunidad canónica."];
        if (string.IsNullOrWhiteSpace(normalizedKey) || normalizedKey.Length is < 8 or > 128 ||
            normalizedKey.Contains('\r') || normalizedKey.Contains('\n'))
            errors["idempotencyKey"] = ["Idempotency-Key debe tener entre 8 y 128 caracteres."];
        if (errors.Count > 0)
            return new(FundingDuplicateReviewOutcome.Invalid, "invalid-duplicate-decision",
                Errors: errors);

        var keyHash = SHA256.HashData(Encoding.UTF8.GetBytes(normalizedKey!));
        var requestHash = SHA256.HashData(Encoding.UTF8.GetBytes(string.Join('\n',
            "FundingDuplicateDecision/v1",
            candidateId.ToString("D"),
            Convert.ToHexString(expectedRowVersion),
            decision.ToString(CultureInfo.InvariantCulture),
            canonicalOpportunityId?.ToString("D") ?? string.Empty,
            normalizedReason!)));
        try
        {
            var mutation = await repository.DecideAsync(
                adminUserId,
                candidateId,
                expectedRowVersion,
                decision,
                canonicalOpportunityId,
                normalizedReason!,
                keyHash,
                requestHash,
                timeProvider.GetUtcNow(),
                cancellationToken);
            return new(Map(mutation.Code, mutation.Succeeded), mutation.Code, mutation);
        }
        catch (FundingDuplicateReviewDataException)
        {
            return new(FundingDuplicateReviewOutcome.Unavailable, "duplicate-review-unavailable");
        }
    }

    private static FundingDuplicateReviewOutcome Map(string code, bool succeeded)
    {
        if (succeeded) return FundingDuplicateReviewOutcome.Success;
        return code switch
        {
            "not-found" or "canonical-not-found" => FundingDuplicateReviewOutcome.NotFound,
            "forbidden" => FundingDuplicateReviewOutcome.Forbidden,
            "etag-conflict" => FundingDuplicateReviewOutcome.PreconditionFailed,
            "idempotency-conflict" or "already-decided" or "invalid-canonical" =>
                FundingDuplicateReviewOutcome.Conflict,
            _ => FundingDuplicateReviewOutcome.Unavailable
        };
    }

    private static FundingDuplicateReviewResult<T> Invalid<T>(
        string code,
        string field,
        string message) => new(
            FundingDuplicateReviewOutcome.Invalid,
            code,
            Errors: new Dictionary<string, string[]> { [field] = [message] });
}
