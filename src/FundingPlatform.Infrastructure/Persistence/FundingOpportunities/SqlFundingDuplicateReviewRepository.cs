using System.Data;
using Dapper;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.FundingOpportunities;

public sealed class SqlFundingDuplicateReviewRepository(
    ISqlConnectionFactory connectionFactory) : IFundingDuplicateReviewRepository
{
    public async Task<FundingDuplicateCandidatePage> ListAsync(
        Guid adminUserId,
        byte? status,
        int page,
        int pageSize,
        CancellationToken cancellationToken)
    {
        var rows = await QueryAsync<ListRow>(
            "dbo.FundingPlatform_usp_FundingOpportunityDuplicateCandidate_AdminList",
            "list duplicate candidates",
            new
            {
                AdminUserPublicId = adminUserId,
                Status = status,
                Page = page,
                PageSize = pageSize
            }, cancellationToken);
        return new FundingDuplicateCandidatePage(
            rows.Select(row => new FundingDuplicateCandidateSummary(
                row.CandidatePublicId,
                row.CandidateOpportunityPublicId,
                row.CandidateTitle,
                row.CandidateSponsor,
                row.SuggestedCanonicalOpportunityPublicId,
                row.SuggestedCanonicalTitle,
                row.MatchKind,
                row.Confidence,
                row.Status,
                Utc(row.CreatedAtUtc),
                ToUtc(row.DecidedAtUtc),
                row.RowVersion)).ToArray(),
            rows.FirstOrDefault()?.TotalCount ?? 0,
            page,
            pageSize);
    }

    public async Task<FundingDuplicateCandidateDetails?> GetAsync(
        Guid adminUserId,
        Guid candidateId,
        CancellationToken cancellationToken)
    {
        var row = await QuerySingleOrDefaultAsync<DetailRow>(
            "dbo.FundingPlatform_usp_FundingOpportunityDuplicateCandidate_AdminGet",
            "get duplicate candidate",
            new
            {
                AdminUserPublicId = adminUserId,
                CandidatePublicId = candidateId
            }, cancellationToken);
        if (row is null) return null;
        var suggested = row.SuggestedCanonicalOpportunityPublicId.HasValue &&
                        row.SuggestedCanonicalTitle is not null &&
                        row.SuggestedCanonicalSponsor is not null &&
                        row.SuggestedCanonicalPublicationStatus.HasValue
            ? new FundingDuplicateOpportunityPreview(
                row.SuggestedCanonicalOpportunityPublicId.Value,
                row.SuggestedCanonicalTitle,
                row.SuggestedCanonicalSponsor,
                row.SuggestedCanonicalPublicationStatus.Value)
            : null;
        var decision = row.DecisionPublicId.HasValue && row.Decision.HasValue &&
                       row.DecisionReason is not null && row.DecisionCreatedAtUtc.HasValue
            ? new FundingDuplicateDecisionView(
                row.DecisionPublicId.Value,
                row.Decision.Value,
                row.DecidedCanonicalOpportunityPublicId,
                row.DecisionReason,
                Utc(row.DecisionCreatedAtUtc.Value))
            : null;
        return new FundingDuplicateCandidateDetails(
            row.CandidatePublicId,
            new FundingDuplicateOpportunityPreview(
                row.CandidateOpportunityPublicId,
                row.CandidateTitle,
                row.CandidateSponsor,
                row.CandidatePublicationStatus),
            suggested,
            row.MatchKind,
            row.Confidence,
            MatchReason(row.MatchKind),
            row.Status,
            Utc(row.CreatedAtUtc),
            ToUtc(row.DecidedAtUtc),
            decision,
            row.RowVersion);
    }

    public async Task<FundingDuplicateDecisionMutation> DecideAsync(
        Guid adminUserId,
        Guid candidateId,
        byte[] expectedRowVersion,
        byte decision,
        Guid? canonicalOpportunityId,
        string reason,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        DateTimeOffset decidedAtUtc,
        CancellationToken cancellationToken)
    {
        var row = await QuerySingleAsync<DecisionRow>(
            "dbo.FundingPlatform_usp_FundingOpportunityDuplicateCandidate_AdminDecide",
            "decide duplicate candidate",
            new
            {
                AdminUserPublicId = adminUserId,
                CandidatePublicId = candidateId,
                ExpectedRowVersion = expectedRowVersion,
                Decision = decision,
                CanonicalOpportunityPublicId = canonicalOpportunityId,
                Reason = reason,
                IdempotencyKeyHash = idempotencyKeyHash,
                RequestHash = requestHash,
                DecidedAtUtc = decidedAtUtc.UtcDateTime
            }, cancellationToken);
        return new FundingDuplicateDecisionMutation(
            row.Succeeded,
            row.Code,
            row.CandidatePublicId,
            row.DecisionPublicId,
            row.Status,
            row.Decision,
            row.CanonicalOpportunityPublicId,
            ToUtc(row.DecidedAtUtc),
            row.RowVersion,
            row.WasReplay);
    }

    private async Task<IReadOnlyList<T>> QueryAsync<T>(
        string procedure,
        string operation,
        object parameters,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            return (await connection.QueryAsync<T>(new CommandDefinition(
                procedure, parameters, commandType: CommandType.StoredProcedure,
                commandTimeout: 15, cancellationToken: cancellationToken))).AsList();
        }
        catch (SqlException exception)
        {
            throw new FundingDuplicateReviewDataException(operation, exception.Number, exception);
        }
    }

    private async Task<T> QuerySingleAsync<T>(
        string procedure,
        string operation,
        object parameters,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            return await connection.QuerySingleAsync<T>(new CommandDefinition(
                procedure, parameters, commandType: CommandType.StoredProcedure,
                commandTimeout: 15, cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw new FundingDuplicateReviewDataException(operation, exception.Number, exception);
        }
    }

    private async Task<T?> QuerySingleOrDefaultAsync<T>(
        string procedure,
        string operation,
        object parameters,
        CancellationToken cancellationToken) where T : class
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            return await connection.QuerySingleOrDefaultAsync<T>(new CommandDefinition(
                procedure, parameters, commandType: CommandType.StoredProcedure,
                commandTimeout: 15, cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw new FundingDuplicateReviewDataException(operation, exception.Number, exception);
        }
    }

    private static string MatchReason(byte matchKind) => matchKind switch
    {
        0 => "exact-content-fingerprint",
        1 => "exact-canonical-url",
        2 => "normalized-title-sponsor",
        _ => "unknown"
    };

    private static DateTimeOffset Utc(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));
    private static DateTimeOffset? ToUtc(DateTime? value) => value.HasValue ? Utc(value.Value) : null;

    private sealed class ListRow
    {
        public Guid CandidatePublicId { get; init; }
        public Guid CandidateOpportunityPublicId { get; init; }
        public string CandidateTitle { get; init; } = string.Empty;
        public string CandidateSponsor { get; init; } = string.Empty;
        public Guid? SuggestedCanonicalOpportunityPublicId { get; init; }
        public string? SuggestedCanonicalTitle { get; init; }
        public byte MatchKind { get; init; }
        public decimal Confidence { get; init; }
        public byte Status { get; init; }
        public DateTime CreatedAtUtc { get; init; }
        public DateTime? DecidedAtUtc { get; init; }
        public byte[] RowVersion { get; init; } = [];
        public long TotalCount { get; init; }
    }

    private sealed class DetailRow
    {
        public Guid CandidatePublicId { get; init; }
        public Guid CandidateOpportunityPublicId { get; init; }
        public string CandidateTitle { get; init; } = string.Empty;
        public string CandidateSponsor { get; init; } = string.Empty;
        public byte CandidatePublicationStatus { get; init; }
        public Guid? SuggestedCanonicalOpportunityPublicId { get; init; }
        public string? SuggestedCanonicalTitle { get; init; }
        public string? SuggestedCanonicalSponsor { get; init; }
        public byte? SuggestedCanonicalPublicationStatus { get; init; }
        public byte MatchKind { get; init; }
        public decimal Confidence { get; init; }
        public byte Status { get; init; }
        public DateTime CreatedAtUtc { get; init; }
        public DateTime? DecidedAtUtc { get; init; }
        public Guid? DecisionPublicId { get; init; }
        public byte? Decision { get; init; }
        public Guid? DecidedCanonicalOpportunityPublicId { get; init; }
        public string? DecisionReason { get; init; }
        public DateTime? DecisionCreatedAtUtc { get; init; }
        public byte[] RowVersion { get; init; } = [];
    }

    private sealed class DecisionRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = string.Empty;
        public Guid? CandidatePublicId { get; init; }
        public Guid? DecisionPublicId { get; init; }
        public byte? Status { get; init; }
        public byte? Decision { get; init; }
        public Guid? CanonicalOpportunityPublicId { get; init; }
        public DateTime? DecidedAtUtc { get; init; }
        public byte[]? RowVersion { get; init; }
        public bool WasReplay { get; init; }
    }
}
