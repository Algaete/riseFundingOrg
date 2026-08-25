using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.Matching;
using FundingPlatform.Core.Matching;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Matching;

public sealed class SqlProjectMatchingRepository(
    ISqlConnectionFactory connectionFactory,
    TimeProvider timeProvider) : IProjectMatchingRepository
{
    private static readonly HashSet<string> AllowedReasonParameterKeys =
        new(StringComparer.Ordinal)
        {
            "matchCount",
            "projectCurrency",
            "opportunityCurrency",
            "minimumGuaranteedYears",
            "maximumPossibleYears",
            "requiredYears"
        };

    private static readonly HashSet<string> AllowedEvidenceSources =
        new(StringComparer.Ordinal)
        {
            "versioned-snapshots"
        };

    private static readonly HashSet<string> AllowedEvidenceFields =
        new(StringComparer.Ordinal)
        {
            "geography",
            "organization_type",
            "legal_entity",
            "operating_years",
            "prior_experience",
            "categories",
            "beneficiaries",
            "project_type",
            "amount"
        };

    private static readonly HashSet<string> AllowedEvidenceValueCodes =
        new(StringComparer.Ordinal)
        {
            "project-geography",
            "opportunity-geography",
            "organization-type",
            "opportunity-organization-types",
            "organization-legal-entity",
            "opportunity-legal-entity-requirement",
            "organization-established-year",
            "opportunity-minimum-years",
            "organization-funding-experience",
            "opportunity-prior-experience-requirement",
            "project-categories",
            "opportunity-categories",
            "project-beneficiaries",
            "opportunity-beneficiaries",
            "project-types",
            "opportunity-project-types",
            "project-funding-gap",
            "opportunity-amount-range"
        };

    private static readonly IReadOnlyDictionary<string, string> RuleNames =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["geography"] = "Geografía",
            ["organization_type"] = "Tipo de organización",
            ["legal_entity"] = "Personalidad jurídica",
            ["operating_years"] = "Antigüedad operativa",
            ["prior_experience"] = "Experiencia previa",
            ["categories"] = "Área temática",
            ["beneficiaries"] = "Beneficiarios",
            ["project_type"] = "Tipo de proyecto",
            ["amount"] = "Monto"
        };

    private static readonly HashSet<string> AllowedReasonCodes =
        new(StringComparer.Ordinal)
        {
            "geography.global",
            "geography.country_match",
            "geography.region_match",
            "geography.explicit_no_match",
            "geography.missing_project",
            "geography.missing_opportunity",
            "organization_type.allowed",
            "organization_type.excluded",
            "organization_type.not_allowed",
            "organization_type.not_restricted",
            "organization_type.missing_opportunity",
            "legal_entity.not_required",
            "legal_entity.allowed",
            "legal_entity.excluded",
            "legal_entity.not_allowed",
            "legal_entity.present",
            "legal_entity.missing_organization",
            "legal_entity.missing_opportunity",
            "operating_years.meets",
            "operating_years.not_required",
            "operating_years.minimum_not_met",
            "operating_years.boundary_unknown",
            "operating_years.missing_organization",
            "operating_years.missing_opportunity",
            "prior_experience.not_required",
            "prior_experience.has_experience",
            "prior_experience.no_experience",
            "prior_experience.missing_organization",
            "prior_experience.missing_opportunity",
            "categories.match",
            "categories.no_match",
            "categories.missing_project",
            "categories.missing_opportunity",
            "beneficiaries.match",
            "beneficiaries.no_match",
            "beneficiaries.missing_project",
            "beneficiaries.missing_opportunity",
            "project_type.match",
            "project_type.no_match",
            "project_type.missing_project",
            "project_type.missing_opportunity",
            "amount.within_range",
            "amount.above_max_partial",
            "amount.below_min",
            "amount.currency_mismatch",
            "amount.missing_project",
            "amount.missing_opportunity"
        };

    public async Task<ProjectMatchingRunPage> ListRunsAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        ProjectMatchingRunListFilters filters,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("UserPublicId", userPublicId, DbType.Guid);
        parameters.Add("OrganizationPublicId", organizationPublicId, DbType.Guid);
        parameters.Add("ProjectPublicId", projectPublicId, DbType.Guid);
        parameters.Add("PageNumber", filters.PageNumber, DbType.Int32);
        parameters.Add("PageSize", filters.PageSize, DbType.Int32);
        parameters.Add("NowUtc", timeProvider.GetUtcNow().UtcDateTime, DbType.DateTime2);

        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_ProjectMatchingRun_List",
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 20,
                cancellationToken: cancellationToken));
            var metadata = await reader.ReadSingleAsync<TotalCountRow>();
            var rows = await reader.ReadAsync<MatchingRunRow>();
            return new ProjectMatchingRunPage(
                rows.Select(Map).ToArray(),
                metadata.TotalCount,
                filters.PageNumber,
                filters.PageSize);
        }
        catch (SqlException exception)
        {
            throw Wrap("list matching runs", exception);
        }
    }

    public async Task<ProjectMatchingRunDetails?> GetRunAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid matchingRunPublicId,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("UserPublicId", userPublicId, DbType.Guid);
        parameters.Add("OrganizationPublicId", organizationPublicId, DbType.Guid);
        parameters.Add("ProjectPublicId", projectPublicId, DbType.Guid);
        parameters.Add("RunPublicId", matchingRunPublicId, DbType.Guid);
        parameters.Add("NowUtc", timeProvider.GetUtcNow().UtcDateTime, DbType.DateTime2);

        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_ProjectMatchingRun_Get",
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 20,
                cancellationToken: cancellationToken));
            var run = await reader.ReadSingleOrDefaultAsync<MatchingRunRow>();
            if (run is null)
            {
                return null;
            }

            var matches = (await reader.ReadAsync<MatchingResultRow>()).ToArray();
            var rules = (await reader.ReadAsync<MatchingRuleResultRow>())
                .GroupBy(row => row.MatchPublicId)
                .ToDictionary(
                    group => group.Key,
                    group => (IReadOnlyList<ProjectMatchingRuleResult>)group.Select(Map).ToArray());
            return new ProjectMatchingRunDetails(
                Map(run),
                matches.Select(match => Map(
                    match,
                    rules.GetValueOrDefault(match.MatchPublicId, []))).ToArray());
        }
        catch (SqlException exception)
        {
            throw Wrap("read matching run", exception);
        }
    }

    public async Task<ProjectMatchingRunMutation> CreateRunAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("UserPublicId", userPublicId, DbType.Guid);
        parameters.Add("OrganizationPublicId", organizationPublicId, DbType.Guid);
        parameters.Add("ProjectPublicId", projectPublicId, DbType.Guid);
        parameters.Add("IdempotencyKeyHash", idempotencyKeyHash, DbType.Binary, size: 32);
        parameters.Add("RequestHash", requestHash, DbType.Binary, size: 32);
        parameters.Add("NowUtc", timeProvider.GetUtcNow().UtcDateTime, DbType.DateTime2);

        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<MatchingRunRow>(
                new CommandDefinition(
                    "dbo.FundingPlatform_usp_ProjectMatchingRun_Create",
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 60,
                    cancellationToken: cancellationToken));
            return new ProjectMatchingRunMutation(
                true,
                row.WasReplay ? "replayed" : "created",
                row.RunPublicId,
                row.WasReplay);
        }
        catch (SqlException exception)
        {
            throw Wrap("create matching run", exception);
        }
    }

    private static ProjectMatchingRunSummary Map(MatchingRunRow row) => new(
        row.RunPublicId,
        new MatchingProjectReference(
            row.ProjectPublicId,
            row.ProjectSlug,
            row.ProjectTitle),
        (MatchingRunStatus)row.Status,
        row.EngineVersion,
        new MatchingProfileReference(row.MatchingProfileCode, row.MatchingProfileVersion),
        row.ProjectVersion,
        row.OrganizationProfileVersion,
        row.ProcessedCandidateCount,
        row.CompatibleCount,
        row.IncompatibleCount,
        row.InsufficientDataCount,
        row.TotalCandidateCount,
        row.IsTruncated,
        row.IsCurrent,
        ToUtc(row.CatalogSnapshotAtUtc),
        ToUtc(row.CreatedAtUtc),
        ToUtc(row.CompletedAtUtc));

    private static ProjectMatchingResult Map(
        MatchingResultRow row,
        IReadOnlyList<ProjectMatchingRuleResult> rules) => new(
            new MatchingFundingOpportunityReference(
                row.FundingOpportunityPublicId,
                row.Slug,
                row.Title,
                row.SponsorName,
                ToDateOnly(row.CloseDate),
                ToUtc(row.CloseAtUtc),
                row.DeadlinePrecision,
                row.FundingContentVersion),
            (MatchingClassification)row.Classification,
            row.CompatibilityScore,
            row.EvidenceCoverage,
            (MatchingHardGateStatus)row.HardGateStatus,
            row.IsCurrent,
            rules);

    private static ProjectMatchingRuleResult Map(MatchingRuleResultRow row) => new(
        NormalizeRuleCode(row.RuleCode),
        RuleNames.GetValueOrDefault(row.RuleCode, "Criterio de compatibilidad"),
        row.IsHardGate,
        (MatchingRuleOutcome)row.Outcome,
        (MatchingDataState)row.DataState,
        row.RawScore,
        row.AppliedWeight,
        row.WeightedPoints,
        NormalizeReasonCode(row.ReasonCode),
        ParseReasonParameters(row.ReasonParametersJson),
        row.DataState == (byte)MatchingDataState.Unknown
            ? null
            : ParseEvidence(row.EvidenceJson),
        row.IsWarning);

    private static string NormalizeRuleCode(string code) =>
        RuleNames.ContainsKey(code) ? code : "unknown";

    private static string NormalizeReasonCode(string code) =>
        AllowedReasonCodes.Contains(code) ? code : "matching.reason_unavailable";

    private static IReadOnlyDictionary<string, string?> ParseReasonParameters(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return new Dictionary<string, string?>();
        }

        using var document = JsonDocument.Parse(json);
        if (document.RootElement.ValueKind != JsonValueKind.Object)
        {
            return new Dictionary<string, string?>();
        }

        var result = new Dictionary<string, string?>(StringComparer.Ordinal);
        foreach (var property in document.RootElement.EnumerateObject())
        {
            if (!AllowedReasonParameterKeys.Contains(property.Name))
            {
                continue;
            }

            var value = property.Value.ValueKind switch
            {
                JsonValueKind.String => property.Value.GetString(),
                JsonValueKind.Number => property.Value.GetRawText(),
                JsonValueKind.Null => null,
                _ => null
            };
            if (value is null || IsAllowedReasonParameterValue(property.Name, value))
            {
                result[property.Name] = value;
            }
        }

        return result;
    }

    private static MatchingRuleEvidence? ParseEvidence(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return null;
        }

        using var document = JsonDocument.Parse(json);
        if (document.RootElement.ValueKind != JsonValueKind.Object ||
            !document.RootElement.TryGetProperty("source", out var sourceNode) ||
            !document.RootElement.TryGetProperty("fieldCode", out var fieldNode) ||
            !document.RootElement.TryGetProperty("valueCodes", out var valuesNode) ||
            sourceNode.ValueKind != JsonValueKind.String ||
            fieldNode.ValueKind != JsonValueKind.String ||
            valuesNode.ValueKind != JsonValueKind.Array)
        {
            return null;
        }

        var source = sourceNode.GetString();
        var field = fieldNode.GetString();
        if (source is null || field is null ||
            !AllowedEvidenceSources.Contains(source) ||
            !AllowedEvidenceFields.Contains(field))
        {
            return null;
        }

        var values = valuesNode.EnumerateArray()
            .Where(value => value.ValueKind == JsonValueKind.String)
            .Select(value => value.GetString())
            .Where(value => value is not null && AllowedEvidenceValueCodes.Contains(value))
            .Cast<string>()
            .Distinct(StringComparer.Ordinal)
            .Take(50)
            .ToArray();
        return values.Length == 0 ? null : new MatchingRuleEvidence(source, field, values);
    }

    private static bool IsAllowedReasonParameterValue(string key, string value) =>
        key switch
        {
            "projectCurrency" or "opportunityCurrency" =>
                value.Length == 3 && value.All(character => character is >= 'A' and <= 'Z'),
            "matchCount" =>
                value.Length is >= 1 and <= 10 && value.All(char.IsAsciiDigit),
            "minimumGuaranteedYears" or "maximumPossibleYears" or "requiredYears" =>
                value.Length is >= 1 and <= 3 && value.All(char.IsAsciiDigit),
            _ => false
        };

    private static DateOnly? ToDateOnly(DateTime? value) =>
        value.HasValue ? DateOnly.FromDateTime(value.Value) : null;

    private static DateTimeOffset ToUtc(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static DateTimeOffset? ToUtc(DateTime? value) =>
        value.HasValue ? ToUtc(value.Value) : null;

    private static ProjectMatchingDataException Wrap(
        string operation,
        SqlException exception) => new(operation, exception.Number, exception);

    private sealed class TotalCountRow
    {
        public long TotalCount { get; init; }
    }

    private sealed class MatchingRunRow
    {
        public Guid RunPublicId { get; init; }
        public Guid ProjectPublicId { get; init; }
        public string ProjectSlug { get; init; } = "";
        public string ProjectTitle { get; init; } = "";
        public byte Status { get; init; }
        public string EngineVersion { get; init; } = "";
        public string MatchingProfileCode { get; init; } = "";
        public int MatchingProfileVersion { get; init; }
        public int ProjectVersion { get; init; }
        public int OrganizationProfileVersion { get; init; }
        public int TotalCandidateCount { get; init; }
        public int ProcessedCandidateCount { get; init; }
        public int CompatibleCount { get; init; }
        public int IncompatibleCount { get; init; }
        public int InsufficientDataCount { get; init; }
        public bool IsTruncated { get; init; }
        public bool IsCurrent { get; init; }
        public DateTime CatalogSnapshotAtUtc { get; init; }
        public DateTime CreatedAtUtc { get; init; }
        public DateTime? CompletedAtUtc { get; init; }
        public bool WasReplay { get; init; }
    }

    private sealed class MatchingResultRow
    {
        public Guid MatchPublicId { get; init; }
        public Guid FundingOpportunityPublicId { get; init; }
        public string Slug { get; init; } = "";
        public string Title { get; init; } = "";
        public string SponsorName { get; init; } = "";
        public DateTime? CloseDate { get; init; }
        public DateTime? CloseAtUtc { get; init; }
        public byte DeadlinePrecision { get; init; }
        public int FundingContentVersion { get; init; }
        public byte Classification { get; init; }
        public decimal? CompatibilityScore { get; init; }
        public decimal EvidenceCoverage { get; init; }
        public byte HardGateStatus { get; init; }
        public bool IsCurrent { get; init; }
    }

    private sealed class MatchingRuleResultRow
    {
        public Guid MatchPublicId { get; init; }
        public string RuleCode { get; init; } = "";
        public string RuleName { get; init; } = "";
        public bool IsHardGate { get; init; }
        public byte Outcome { get; init; }
        public byte DataState { get; init; }
        public decimal? RawScore { get; init; }
        public decimal AppliedWeight { get; init; }
        public decimal WeightedPoints { get; init; }
        public string ReasonCode { get; init; } = "";
        public string? ReasonParametersJson { get; init; }
        public string? EvidenceJson { get; init; }
        public bool IsWarning { get; init; }
    }

}
