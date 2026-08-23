using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.FundingOpportunities;

public sealed class SqlFundingOpportunityEditorialRepository(
    ISqlConnectionFactory connectionFactory) : IFundingOpportunityEditorialRepository
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<FundingOpportunityAdminPage> ListAdminAsync(
        Guid adminUserPublicId,
        string? query,
        FundingPublicationStatus? publicationStatus,
        bool includeInactive,
        int pageNumber,
        int pageSize,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_FundingOpportunity_Admin_List",
                new
                {
                    AdminUserPublicId = adminUserPublicId,
                    Query = query,
                    PublicationStatus = publicationStatus.HasValue
                        ? (byte?)publicationStatus.Value
                        : null,
                    IncludeInactive = includeInactive,
                    PageNumber = pageNumber,
                    PageSize = pageSize
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            var totalCount = await reader.ReadSingleAsync<long>();
            var rows = (await reader.ReadAsync<AdminOpportunityRow>()).AsList();
            return new FundingOpportunityAdminPage(
                rows.Select(MapAdminSummary).ToArray(), totalCount, pageNumber, pageSize);
        }
        catch (SqlException exception)
        {
            throw Wrap("list funding opportunities for administration", exception);
        }
    }

    public async Task<FundingOpportunityAdminDetails?> GetAdminAsync(
        Guid adminUserPublicId,
        Guid opportunityPublicId,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_FundingOpportunity_Admin_Get",
                new
                {
                    AdminUserPublicId = adminUserPublicId,
                    FundingOpportunityPublicId = opportunityPublicId
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            var row = await reader.ReadSingleOrDefaultAsync<AdminOpportunityDetailsRow>();
            if (row is null)
            {
                return null;
            }

            var countries = (await reader.ReadAsync<ShortIdRow>()).Select(item => item.Id).ToArray();
            var regions = (await reader.ReadAsync<IntIdRow>()).Select(item => item.Id).ToArray();
            var categories = (await reader.ReadAsync<IntIdRow>()).Select(item => item.Id).ToArray();
            var beneficiaries = (await reader.ReadAsync<IntIdRow>()).Select(item => item.Id).ToArray();
            var projectTypes = (await reader.ReadAsync<IntIdRow>()).Select(item => item.Id).ToArray();
            var funders = (await reader.ReadAsync<OpportunityFunderRow>())
                .Select(MapFunder)
                .ToArray();
            var evidence = (await reader.ReadAsync<EvidenceRow>())
                .Select(MapEvidence)
                .ToArray();
            var sources = (await reader.ReadAsync<SourceLinkRow>())
                .Select(MapSource)
                .ToArray();
            var primarySource = sources.FirstOrDefault(source => source.IsPrimary && source.IsActive)
                ?? sources.FirstOrDefault(source => source.IsActive)
                ?? sources.FirstOrDefault();

            var data = new FundingOpportunityEditorialData(
                row.Title,
                row.Summary,
                row.Description,
                row.SponsorName,
                row.SponsorUrl,
                row.ApplicationUrl,
                funders.Select(funder => new FundingOpportunityFunderLink(
                    funder.PublicId, funder.Role)).ToArray(),
                primarySource?.FundingSourceId ?? 0,
                primarySource?.ExternalId,
                primarySource?.SourceUrl ?? string.Empty,
                row.IssuerCountryId,
                row.FundingTypeId,
                row.Currency?.Trim(),
                row.MinAmount,
                row.MaxAmount,
                (FundingAmountStatus)row.AmountStatus,
                ToDateOnly(row.OpenDate),
                ToDateOnly(row.CloseDate),
                ToUtc(row.CloseAtUtc),
                row.DeadlineTimeZoneId,
                (FundingDeadlineType)row.DeadlineType,
                (FundingDeadlinePrecision)row.DeadlinePrecision,
                row.EligibilityDescription,
                row.Requirements,
                row.Objectives,
                row.AllowedActivities,
                row.ExcludedActivities,
                row.Restrictions,
                row.TargetOrganizationsDescription,
                row.TargetPopulationsDescription,
                row.MinimumOperatingYears,
                row.RequiresLegalEntity,
                row.RequiresPriorExperience,
                row.RequiresCofunding,
                row.CofundingPercentage,
                (FundingGeographicScope)row.GeographicScope,
                (FundingRemoteApplication)row.RemoteApplication,
                ToUtc(row.LastVerifiedAtUtc),
                countries,
                regions,
                categories,
                beneficiaries,
                projectTypes);

            return new FundingOpportunityAdminDetails(
                row.FundingOpportunityPublicId,
                row.Slug,
                data,
                (FundingPublicationStatus)row.PublicationStatus,
                row.IsActive,
                row.ContentVersion,
                row.DataQualityScore,
                ToUtc(row.CreatedAtUtc),
                ToUtc(row.UpdatedAtUtc),
                row.RowVersion,
                funders,
                evidence,
                sources,
                ToUtc(row.SubmittedAtUtc),
                ToUtc(row.ReviewedAtUtc),
                row.ReviewedByUserPublicId,
                ToUtc(row.PublishedAtUtc),
                row.RejectionReason);
        }
        catch (SqlException exception) when (exception.Number == 51608)
        {
            return null;
        }
        catch (SqlException exception)
        {
            throw Wrap("read funding opportunity for administration", exception);
        }
    }

    public Task<FundingEditorialMutation> CreateAsync(
        Guid adminUserPublicId,
        string slug,
        FundingOpportunityEditorialData data,
        string snapshotJson,
        byte[] contentHash,
        decimal dataQualityScore,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken) => ExecuteWriteAsync(
        "dbo.FundingPlatform_usp_FundingOpportunity_Create",
        "create funding opportunity",
        BuildWriteParameters(
            adminUserPublicId, null, null, slug, data, snapshotJson, contentHash,
            dataQualityScore, idempotencyKeyHash, requestHash),
        cancellationToken);

    public Task<FundingEditorialMutation> UpdateAsync(
        Guid adminUserPublicId,
        Guid opportunityPublicId,
        byte[] expectedRowVersion,
        FundingOpportunityEditorialData data,
        string snapshotJson,
        byte[] contentHash,
        decimal dataQualityScore,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken) => ExecuteWriteAsync(
        "dbo.FundingPlatform_usp_FundingOpportunity_Update",
        "update funding opportunity",
        BuildWriteParameters(
            adminUserPublicId, opportunityPublicId, expectedRowVersion, null, data,
            snapshotJson, contentHash, dataQualityScore, idempotencyKeyHash, requestHash),
        cancellationToken);

    public Task<FundingEditorialMutation> RequestPublicationAsync(
        Guid adminUserPublicId,
        Guid opportunityPublicId,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken) => ExecuteWorkflowAsync(
        "dbo.FundingPlatform_usp_FundingOpportunity_RequestPublication",
        "request funding opportunity publication",
        new
        {
            AdminUserPublicId = adminUserPublicId,
            FundingOpportunityPublicId = opportunityPublicId,
            ExpectedRowVersion = expectedRowVersion,
            IdempotencyKeyHash = idempotencyKeyHash,
            RequestHash = requestHash
        },
        readsIssues: true,
        cancellationToken);

    public Task<FundingEditorialMutation> ReviewAsync(
        Guid adminUserPublicId,
        Guid opportunityPublicId,
        FundingReviewDecision decision,
        string? reason,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken) => ExecuteWorkflowAsync(
        "dbo.FundingPlatform_usp_FundingOpportunity_AdminReview",
        "review funding opportunity",
        new
        {
            AdminUserPublicId = adminUserPublicId,
            FundingOpportunityPublicId = opportunityPublicId,
            ExpectedRowVersion = expectedRowVersion,
            Decision = (byte)decision,
            RejectionReason = reason,
            IdempotencyKeyHash = idempotencyKeyHash,
            RequestHash = requestHash
        },
        readsIssues: false,
        cancellationToken);

    public Task<FundingEditorialMutation> DeactivateAsync(
        Guid adminUserPublicId,
        Guid opportunityPublicId,
        string? reason,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken) => ExecuteWorkflowAsync(
        "dbo.FundingPlatform_usp_FundingOpportunity_Deactivate",
        "deactivate funding opportunity",
        new
        {
            AdminUserPublicId = adminUserPublicId,
            FundingOpportunityPublicId = opportunityPublicId,
            ExpectedRowVersion = expectedRowVersion,
            Reason = reason,
            IdempotencyKeyHash = idempotencyKeyHash,
            RequestHash = requestHash
        },
        readsIssues: false,
        cancellationToken);

    public Task<FundingEditorialMutation> StartCorrectionAsync(
        Guid adminUserPublicId,
        Guid opportunityPublicId,
        string reason,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken) => ExecuteWorkflowAsync(
        "dbo.FundingPlatform_usp_FundingOpportunity_StartCorrection",
        "start funding opportunity correction",
        new
        {
            AdminUserPublicId = adminUserPublicId,
            FundingOpportunityPublicId = opportunityPublicId,
            ExpectedRowVersion = expectedRowVersion,
            Reason = reason,
            IdempotencyKeyHash = idempotencyKeyHash,
            RequestHash = requestHash
        },
        readsIssues: false,
        cancellationToken);

    private async Task<FundingEditorialMutation> ExecuteWriteAsync(
        string procedure,
        string operation,
        DynamicParameters parameters,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<MutationRow>(new CommandDefinition(
                procedure,
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            return MapMutation(row, []);
        }
        catch (SqlException exception)
        {
            throw Wrap(operation, exception);
        }
    }

    private async Task<FundingEditorialMutation> ExecuteWorkflowAsync(
        string procedure,
        string operation,
        object parameters,
        bool readsIssues,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            MutationRow row;
            IReadOnlyList<FundingReadinessIssue> issues;
            if (readsIssues)
            {
                using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                    procedure,
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 30,
                    cancellationToken: cancellationToken));
                row = await reader.ReadSingleAsync<MutationRow>();
                issues = (await reader.ReadAsync<FundingReadinessIssue>()).AsList();
            }
            else
            {
                row = await connection.QuerySingleAsync<MutationRow>(new CommandDefinition(
                    procedure,
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 30,
                    cancellationToken: cancellationToken));
                issues = [];
            }

            return MapMutation(row, issues);
        }
        catch (SqlException exception)
        {
            throw Wrap(operation, exception);
        }
    }

    private static DynamicParameters BuildWriteParameters(
        Guid adminUserPublicId,
        Guid? opportunityPublicId,
        byte[]? expectedRowVersion,
        string? slug,
        FundingOpportunityEditorialData data,
        string snapshotJson,
        byte[] contentHash,
        decimal dataQualityScore,
        byte[] idempotencyKeyHash,
        byte[] requestHash)
    {
        var parameters = new DynamicParameters();
        parameters.Add("AdminUserPublicId", adminUserPublicId);
        if (opportunityPublicId.HasValue)
            parameters.Add("FundingOpportunityPublicId", opportunityPublicId.Value);
        if (expectedRowVersion is not null)
            parameters.Add("ExpectedRowVersion", expectedRowVersion, DbType.Binary, size: 8);
        if (slug is not null) parameters.Add("Slug", slug);
        parameters.Add("Title", data.Title);
        parameters.Add("Description", data.Description);
        parameters.Add("Summary", data.Summary);
        parameters.Add("SponsorName", data.SponsorName);
        parameters.Add("SponsorUrl", data.SponsorUrl);
        parameters.Add("ApplicationUrl", data.ApplicationUrl);
        parameters.Add("IssuerCountryId", data.IssuerCountryId);
        parameters.Add("FundingTypeId", data.FundingTypeId);
        parameters.Add("Currency", data.Currency, DbType.AnsiStringFixedLength, size: 3);
        parameters.Add("MinAmount", data.MinimumAmount);
        parameters.Add("MaxAmount", data.MaximumAmount);
        parameters.Add("AmountStatus", (byte)data.AmountStatus);
        parameters.Add("OpenDate", ToDateTime(data.OpenDate), DbType.Date);
        parameters.Add("CloseDate", ToDateTime(data.CloseDate), DbType.Date);
        parameters.Add("CloseAtUtc", data.CloseAtUtc?.UtcDateTime, DbType.DateTime2);
        parameters.Add("DeadlineTimeZoneId", data.DeadlineTimeZoneId);
        parameters.Add("DeadlineType", (byte)data.DeadlineType);
        parameters.Add("DeadlinePrecision", (byte)data.DeadlinePrecision);
        parameters.Add("EligibilityDescription", data.EligibilityDescription);
        parameters.Add("Requirements", data.Requirements);
        parameters.Add("Objectives", data.Objectives);
        parameters.Add("AllowedActivities", data.AllowedActivities);
        parameters.Add("ExcludedActivities", data.ExcludedActivities);
        parameters.Add("Restrictions", data.Restrictions);
        parameters.Add("TargetOrganizationsDescription", data.TargetOrganizationsDescription);
        parameters.Add("TargetPopulationsDescription", data.TargetPopulationsDescription);
        parameters.Add("MinimumOperatingYears", data.MinimumOperatingYears);
        parameters.Add("RequiresLegalEntity", data.RequiresLegalEntity);
        parameters.Add("RequiresPriorExperience", data.RequiresPriorExperience);
        parameters.Add("RequiresCofunding", data.RequiresCofunding);
        parameters.Add("CofundingPercentage", data.CofundingPercentage);
        parameters.Add("GeographicScope", (byte)data.GeographicScope);
        parameters.Add("RemoteApplication", (byte)data.RemoteApplication);
        parameters.Add("LastVerifiedAtUtc", data.LastVerifiedAtUtc?.UtcDateTime, DbType.DateTime2);
        parameters.Add("DataQualityScore", dataQualityScore);
        parameters.Add("FundingSourceId", data.FundingSourceId);
        parameters.Add("ExternalId", data.ExternalId);
        parameters.Add("SourceItemKeyHash", Hash(data.ExternalId ?? data.SourceUrl),
            DbType.Binary, size: 32);
        parameters.Add("SourceUrl", data.SourceUrl);
        parameters.Add("CanonicalUrlHash", Hash(data.SourceUrl), DbType.Binary, size: 32);
        parameters.Add("SnapshotJson", snapshotJson);
        parameters.Add("ContentHash", contentHash, DbType.Binary, size: 32);
        parameters.Add("CountryIds", ToIdTable(data.CountryIds)
            .AsTableValuedParameter("dbo.FundingPlatform_SmallIntIdList"));
        parameters.Add("RegionIds", ToIdTable(data.RegionIds)
            .AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));
        parameters.Add("CategoryIds", ToIdTable(data.CategoryIds)
            .AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));
        parameters.Add("BeneficiaryTypeIds", ToIdTable(data.BeneficiaryTypeIds)
            .AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));
        parameters.Add("ProjectTypeIds", ToIdTable(data.ProjectTypeIds)
            .AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));
        parameters.Add("FunderLinksJson", SerializeFunders(data.Funders));
        parameters.Add("EvidenceJson", "[]");
        parameters.Add("IdempotencyKeyHash", idempotencyKeyHash, DbType.Binary, size: 32);
        parameters.Add("RequestHash", requestHash, DbType.Binary, size: 32);
        return parameters;
    }

    private static FundingOpportunityAdminSummary MapAdminSummary(AdminOpportunityRow row) => new(
        row.FundingOpportunityPublicId,
        row.Slug,
        row.Title,
        row.Summary,
        row.SponsorName,
        (FundingPublicationStatus)row.PublicationStatus,
        row.IsActive,
        row.ContentVersion,
        ToDateOnly(row.OpenDate),
        ToDateOnly(row.CloseDate),
        row.Currency?.Trim(),
        row.MinAmount,
        row.MaxAmount,
        row.DataQualityScore,
        row.SourceName,
        row.SourceUrl,
        ToUtc(row.PublishedAtUtc),
        ToUtc(row.LastVerifiedAtUtc),
        ToUtc(row.UpdatedAtUtc),
        row.RowVersion);

    private static FundingOpportunityFunder MapFunder(OpportunityFunderRow row) => new(
        row.FunderPublicId,
        row.Slug,
        row.Name,
        (FunderOpportunityRole)row.Role);

    private static FundingFieldEvidence MapEvidence(EvidenceRow row) => new(
        row.EvidencePublicId,
        row.FieldPath,
        row.ValueJson,
        row.ExtractionMethod,
        row.EvidenceText,
        row.SourceLocator,
        row.Confidence,
        row.IsSelected,
        row.IsManualLock,
        row.CreatedByUserPublicId,
        ToUtc(row.CreatedAtUtc));

    private static FundingOpportunitySourceLink MapSource(SourceLinkRow row) => new(
        row.FundingSourceId,
        row.SourceName,
        row.ExternalId,
        row.SourceUrl,
        ToUtc(row.FirstSeenAtUtc),
        ToUtc(row.LastSeenAtUtc),
        row.IsPrimary,
        row.IsActive);

    private static FundingEditorialMutation MapMutation(
        MutationRow row,
        IReadOnlyList<FundingReadinessIssue> issues) => new(
        row.Succeeded,
        row.Code,
        row.FundingOpportunityPublicId ?? Guid.Empty,
        (FundingPublicationStatus)(row.PublicationStatus ?? 0),
        row.ContentVersion ?? 0,
        row.RowVersion ?? [],
        row.WasReplay,
        issues,
        ToUtc(row.SubmittedAtUtc),
        ToUtc(row.ReviewedAtUtc),
        row.ReviewedByUserPublicId,
        ToUtc(row.PublishedAtUtc),
        row.RejectionReason);

    private static string SerializeFunders(IReadOnlyList<FundingOpportunityFunderLink> funders) =>
        JsonSerializer.Serialize(
            funders.Select(funder => new
            {
                funderPublicId = funder.FunderPublicId,
                role = (byte)funder.Role
            }),
            JsonOptions);

    private static DataTable ToIdTable<T>(IEnumerable<T> ids)
    {
        var table = new DataTable();
        table.Columns.Add("Id", typeof(T));
        foreach (var id in ids) table.Rows.Add(id);
        return table;
    }

    private static byte[] Hash(string value) =>
        SHA256.HashData(Encoding.UTF8.GetBytes(value));

    private static DateTime? ToDateTime(DateOnly? value) =>
        value?.ToDateTime(TimeOnly.MinValue);

    private static DateOnly? ToDateOnly(DateTime? value) =>
        value.HasValue ? DateOnly.FromDateTime(value.Value) : null;

    private static DateTimeOffset ToUtc(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static DateTimeOffset? ToUtc(DateTime? value) =>
        value.HasValue ? ToUtc(value.Value) : null;

    private static FundingEditorialDataException Wrap(string operation, SqlException exception) =>
        new(operation, exception.Number, exception);

    private class AdminOpportunityRow
    {
        public Guid FundingOpportunityPublicId { get; init; }
        public string Slug { get; init; } = string.Empty;
        public string Title { get; init; } = string.Empty;
        public string? Summary { get; init; }
        public string SponsorName { get; init; } = string.Empty;
        public byte PublicationStatus { get; init; }
        public bool IsActive { get; init; }
        public DateTime? OpenDate { get; init; }
        public DateTime? CloseDate { get; init; }
        public string? Currency { get; init; }
        public decimal? MinAmount { get; init; }
        public decimal? MaxAmount { get; init; }
        public decimal DataQualityScore { get; init; }
        public int ContentVersion { get; init; }
        public DateTime? SubmittedAtUtc { get; init; }
        public DateTime? PublishedAtUtc { get; init; }
        public DateTime? ReviewedAtUtc { get; init; }
        public Guid? ReviewedByUserPublicId { get; init; }
        public string? RejectionReason { get; init; }
        public string? SourceName { get; init; }
        public string? SourceUrl { get; init; }
        public DateTime? LastVerifiedAtUtc { get; init; }
        public DateTime CreatedAtUtc { get; init; }
        public DateTime UpdatedAtUtc { get; init; }
        public byte[] RowVersion { get; init; } = [];
    }

    private sealed class AdminOpportunityDetailsRow : AdminOpportunityRow
    {
        public string? Description { get; init; }
        public string? SponsorUrl { get; init; }
        public string? ApplicationUrl { get; init; }
        public short? IssuerCountryId { get; init; }
        public short? FundingTypeId { get; init; }
        public byte AmountStatus { get; init; }
        public DateTime? CloseAtUtc { get; init; }
        public string? DeadlineTimeZoneId { get; init; }
        public byte DeadlineType { get; init; }
        public byte DeadlinePrecision { get; init; }
        public string? EligibilityDescription { get; init; }
        public string? Requirements { get; init; }
        public string? Objectives { get; init; }
        public string? AllowedActivities { get; init; }
        public string? ExcludedActivities { get; init; }
        public string? Restrictions { get; init; }
        public string? TargetOrganizationsDescription { get; init; }
        public string? TargetPopulationsDescription { get; init; }
        public short? MinimumOperatingYears { get; init; }
        public bool? RequiresLegalEntity { get; init; }
        public bool? RequiresPriorExperience { get; init; }
        public bool? RequiresCofunding { get; init; }
        public decimal? CofundingPercentage { get; init; }
        public byte GeographicScope { get; init; }
        public byte RemoteApplication { get; init; }
    }

    private sealed class ShortIdRow
    {
        public short Id { get; init; }
    }

    private sealed class IntIdRow
    {
        public int Id { get; init; }
    }

    private sealed class OpportunityFunderRow
    {
        public Guid FunderPublicId { get; init; }
        public string Slug { get; init; } = string.Empty;
        public string Name { get; init; } = string.Empty;
        public byte Role { get; init; }
    }

    private sealed class EvidenceRow
    {
        public Guid EvidencePublicId { get; init; }
        public string FieldPath { get; init; } = string.Empty;
        public string ValueJson { get; init; } = string.Empty;
        public byte ExtractionMethod { get; init; }
        public string? EvidenceText { get; init; }
        public string? SourceLocator { get; init; }
        public decimal? Confidence { get; init; }
        public bool IsSelected { get; init; }
        public bool IsManualLock { get; init; }
        public Guid? CreatedByUserPublicId { get; init; }
        public DateTime CreatedAtUtc { get; init; }
    }

    private sealed class SourceLinkRow
    {
        public int FundingSourceId { get; init; }
        public string SourceName { get; init; } = string.Empty;
        public string? ExternalId { get; init; }
        public string SourceUrl { get; init; } = string.Empty;
        public DateTime FirstSeenAtUtc { get; init; }
        public DateTime LastSeenAtUtc { get; init; }
        public bool IsPrimary { get; init; }
        public bool IsActive { get; init; }
    }

    private sealed class MutationRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = string.Empty;
        public Guid? FundingOpportunityPublicId { get; init; }
        public int? ContentVersion { get; init; }
        public byte? PublicationStatus { get; init; }
        public DateTime? SubmittedAtUtc { get; init; }
        public DateTime? PublishedAtUtc { get; init; }
        public DateTime? ReviewedAtUtc { get; init; }
        public Guid? ReviewedByUserPublicId { get; init; }
        public string? RejectionReason { get; init; }
        public byte[]? RowVersion { get; init; }
        public bool WasReplay { get; init; }
    }
}
