using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.Projects;
using FundingPlatform.Core.Projects;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Projects;

public sealed class SqlProjectRepository(ISqlConnectionFactory connectionFactory) : IProjectRepository
{
    private static readonly JsonSerializerOptions PublicJsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true
    };

    public async Task<IReadOnlyList<ProjectSummary>> ListAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var rows = await connection.QueryAsync<ProjectSummaryRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_Project_List",
                new { OrganizationPublicId = organizationPublicId, UserPublicId = userPublicId },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            return rows.Select(MapSummary).ToArray();
        }
        catch (SqlException exception)
        {
            throw Wrap("list projects", exception);
        }
    }

    public async Task<ProjectDetails?> GetAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_Project_Get",
                new
                {
                    OrganizationPublicId = organizationPublicId,
                    ProjectPublicId = projectPublicId,
                    UserPublicId = userPublicId
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            var row = await reader.ReadSingleAsync<ProjectDetailsRow>();
            var countries = (await reader.ReadAsync<ShortIdRow>()).Select(item => item.Id).ToArray();
            var regions = (await reader.ReadAsync<IntIdRow>()).Select(item => item.Id).ToArray();
            var categories = (await reader.ReadAsync<IntIdRow>()).Select(item => item.Id).ToArray();
            var beneficiaries = (await reader.ReadAsync<IntIdRow>()).Select(item => item.Id).ToArray();
            var projectTypes = (await reader.ReadAsync<IntIdRow>()).Select(item => item.Id).ToArray();
            return new ProjectDetails(
                row.PublicId, row.Slug, row.Title, row.Summary, row.Description,
                (ProjectStatus)row.ProjectStatus, (ProjectPublicationStatus)row.PublicationStatus,
                ToDateOnly(row.StartDate), ToDateOnly(row.EndDate), row.BudgetTotal,
                row.ConfirmedFunding, row.Currency?.Trim(), row.FundingGap, row.ProjectVersion,
                ToUtc(row.UpdatedAtUtc), row.RowVersion, countries, regions, categories,
                beneficiaries, projectTypes, ToUtc(row.SubmittedAtUtc), ToUtc(row.ReviewedAtUtc),
                row.RejectionReason, ToUtc(row.PublishedAtUtc));
        }
        catch (SqlException exception)
        {
            throw Wrap("read project", exception);
        }
    }

    public Task<PersistedProject> CreateAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        string slug,
        ProjectData project,
        string snapshotJson,
        byte[] contentHash,
        CancellationToken cancellationToken) =>
        WriteAsync("dbo.FundingPlatform_usp_Project_Create", "create project", userPublicId,
            organizationPublicId, null, null, slug, project, snapshotJson, contentHash, cancellationToken);

    public Task<PersistedProject> UpdateAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        byte[] expectedRowVersion,
        ProjectData project,
        string snapshotJson,
        byte[] contentHash,
        CancellationToken cancellationToken) =>
        WriteAsync("dbo.FundingPlatform_usp_Project_Update", "update project", userPublicId,
            organizationPublicId, projectPublicId, expectedRowVersion, null, project,
            snapshotJson, contentHash, cancellationToken);

    public Task<ProjectWorkflowMutation> RequestPublicationAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken) =>
        ExecuteWorkflowAsync(
            "dbo.FundingPlatform_usp_Project_RequestPublication",
            "request project publication",
            new
            {
                OrganizationPublicId = organizationPublicId,
                ProjectPublicId = projectPublicId,
                UserPublicId = userPublicId,
                ExpectedRowVersion = expectedRowVersion,
                IdempotencyKeyHash = idempotencyKeyHash,
                RequestHash = requestHash
            },
            readsIssues: true,
            cancellationToken);

    public Task<ProjectWorkflowMutation> ArchiveAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken) =>
        ExecuteWorkflowAsync(
            "dbo.FundingPlatform_usp_Project_Archive",
            "archive project",
            new
            {
                OrganizationPublicId = organizationPublicId,
                ProjectPublicId = projectPublicId,
                UserPublicId = userPublicId,
                ExpectedRowVersion = expectedRowVersion,
                Reason = (string?)null,
                IdempotencyKeyHash = idempotencyKeyHash,
                RequestHash = requestHash
            },
            readsIssues: false,
            cancellationToken);

    public async Task<ProjectReviewQueuePage> ListReviewQueueAsync(
        Guid userPublicId,
        int pageNumber,
        int pageSize,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_Project_AdminReviewQueue_List",
                new
                {
                    AdminUserPublicId = userPublicId,
                    PageNumber = pageNumber,
                    PageSize = pageSize
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            var totalCount = await reader.ReadSingleAsync<long>();
            var rows = (await reader.ReadAsync<ProjectReviewQueueRow>()).AsList();
            return new ProjectReviewQueuePage(
                rows.Select(row => new ProjectReviewQueueItem(
                    row.ProjectPublicId,
                    row.Slug,
                    row.Title,
                    row.Summary,
                    (ProjectStatus)row.ProjectStatus,
                    (ProjectPublicationStatus)row.PublicationStatus,
                    row.OrganizationPublicId,
                    row.OrganizationName,
                    row.Completeness,
                    ToUtc(row.SubmittedAtUtc),
                    ToUtc(row.UpdatedAtUtc),
                    row.RowVersion)).ToArray(),
                totalCount,
                pageNumber,
                pageSize);
        }
        catch (SqlException exception)
        {
            throw Wrap("list project review queue", exception);
        }
    }

    public async Task<ProjectReviewDetails?> GetReviewDetailsAsync(
        Guid userPublicId,
        Guid projectPublicId,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleOrDefaultAsync<ProjectReviewDetailRow>(
                new CommandDefinition(
                    "dbo.FundingPlatform_usp_Project_AdminReview_Get",
                    new
                    {
                        AdminUserPublicId = userPublicId,
                        ProjectPublicId = projectPublicId
                    },
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 15,
                    cancellationToken: cancellationToken));
            if (row is null)
            {
                return null;
            }

            return new ProjectReviewDetails(
                row.ProjectPublicId,
                row.Slug,
                row.Title,
                row.Summary,
                row.Description,
                (ProjectStatus)row.ProjectStatus,
                (ProjectPublicationStatus)row.PublicationStatus,
                ToDateOnly(row.StartDate),
                ToDateOnly(row.EndDate),
                row.BudgetTotal,
                row.ConfirmedFunding,
                row.Currency?.Trim(),
                row.FundingGap,
                row.ProjectVersion,
                row.Completeness,
                ToUtc(row.SubmittedAtUtc),
                ToUtc(row.UpdatedAtUtc),
                row.RowVersion,
                new PublicProjectOrganization(
                    row.OrganizationPublicId,
                    row.OrganizationName,
                    row.OrganizationWebsiteUrl),
                DeserializeTaxonomy(row.CountriesJson),
                DeserializeRegions(row.RegionsJson),
                DeserializeTaxonomy(row.CategoriesJson),
                DeserializeTaxonomy(row.BeneficiaryTypesJson),
                DeserializeTaxonomy(row.ProjectTypesJson));
        }
        catch (SqlException exception)
        {
            throw Wrap("read project review details", exception);
        }
        catch (JsonException exception)
        {
            throw new ProjectDataException("read project review details contract", -1, exception);
        }
    }

    public Task<ProjectWorkflowMutation> ReviewAsync(
        Guid userPublicId,
        Guid projectPublicId,
        ProjectReviewDecision decision,
        string? reason,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken) =>
        ExecuteWorkflowAsync(
            "dbo.FundingPlatform_usp_Project_AdminReview",
            "review project publication",
            new
            {
                AdminUserPublicId = userPublicId,
                ProjectPublicId = projectPublicId,
                Decision = (byte)decision,
                RejectionReason = reason,
                ExpectedRowVersion = expectedRowVersion,
                IdempotencyKeyHash = idempotencyKeyHash,
                RequestHash = requestHash
            },
            readsIssues: false,
            cancellationToken);

    public async Task<PublicProjectDetails?> GetPublishedBySlugAsync(
        string slug,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleOrDefaultAsync<PublicProjectRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_Project_Public_GetBySlug",
                new { Slug = slug },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            if (row is null)
            {
                return null;
            }

            return new PublicProjectDetails(
                row.ProjectPublicId,
                row.Slug,
                row.Title,
                row.Summary,
                row.Description,
                (ProjectStatus)row.ProjectStatus,
                ToDateOnly(row.StartDate),
                ToDateOnly(row.EndDate),
                row.BudgetTotal,
                row.ConfirmedFunding,
                row.Currency?.Trim(),
                row.FundingGap,
                ToUtc(row.PublishedAtUtc),
                new PublicProjectOrganization(
                    row.OrganizationPublicId,
                    row.OrganizationName,
                    row.OrganizationWebsiteUrl),
                DeserializeTaxonomy(row.CountriesJson),
                DeserializeRegions(row.RegionsJson),
                DeserializeTaxonomy(row.CategoriesJson),
                DeserializeTaxonomy(row.BeneficiaryTypesJson),
                DeserializeTaxonomy(row.ProjectTypesJson));
        }
        catch (SqlException exception)
        {
            throw Wrap("read published project", exception);
        }
        catch (JsonException exception)
        {
            throw new ProjectDataException("read published project contract", -1, exception);
        }
    }

    private async Task<PersistedProject> WriteAsync(
        string procedure,
        string operation,
        Guid userPublicId,
        Guid organizationPublicId,
        Guid? projectPublicId,
        byte[]? expectedRowVersion,
        string? slug,
        ProjectData project,
        string snapshotJson,
        byte[] contentHash,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("OrganizationPublicId", organizationPublicId);
        if (projectPublicId.HasValue) parameters.Add("ProjectPublicId", projectPublicId.Value);
        parameters.Add("UserPublicId", userPublicId);
        if (expectedRowVersion is not null)
            parameters.Add("ExpectedRowVersion", expectedRowVersion, DbType.Binary, size: 8);
        if (slug is not null) parameters.Add("Slug", slug);
        parameters.Add("Title", project.Title);
        parameters.Add("Summary", project.Summary);
        parameters.Add("Description", project.Description);
        parameters.Add("ProjectStatus", (byte)project.Status);
        parameters.Add("StartDate", ToDateTime(project.StartDate), DbType.Date);
        parameters.Add("EndDate", ToDateTime(project.EndDate), DbType.Date);
        parameters.Add("BudgetTotal", project.BudgetTotal);
        parameters.Add("ConfirmedFunding", project.ConfirmedFunding);
        parameters.Add("Currency", project.Currency, DbType.AnsiStringFixedLength, size: 3);
        parameters.Add("SnapshotJson", snapshotJson);
        parameters.Add("ContentHash", contentHash, DbType.Binary, size: 32);
        parameters.Add("CountryIds", ToIdTable(project.CountryIds).AsTableValuedParameter("dbo.FundingPlatform_SmallIntIdList"));
        parameters.Add("RegionIds", ToIdTable(project.RegionIds).AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));
        parameters.Add("CategoryIds", ToIdTable(project.CategoryIds).AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));
        parameters.Add("BeneficiaryTypeIds", ToIdTable(project.BeneficiaryTypeIds).AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));
        parameters.Add("ProjectTypeIds", ToIdTable(project.ProjectTypeIds).AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));

        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<PersistedProjectRow>(new CommandDefinition(
                procedure, parameters, commandType: CommandType.StoredProcedure,
                commandTimeout: 30, cancellationToken: cancellationToken));
            return new PersistedProject(row.PublicId, row.ProjectVersion, row.RowVersion);
        }
        catch (SqlException exception)
        {
            throw Wrap(operation, exception);
        }
    }

    private async Task<ProjectWorkflowMutation> ExecuteWorkflowAsync(
        string procedure,
        string operation,
        object parameters,
        bool readsIssues,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            WorkflowMutationRow row;
            IReadOnlyList<ProjectReadinessIssue> issues;
            if (readsIssues)
            {
                using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                    procedure,
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 30,
                    cancellationToken: cancellationToken));
                row = await reader.ReadSingleAsync<WorkflowMutationRow>();
                issues = (await reader.ReadAsync<ProjectReadinessIssue>()).AsList();
            }
            else
            {
                row = await connection.QuerySingleAsync<WorkflowMutationRow>(new CommandDefinition(
                    procedure,
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 30,
                    cancellationToken: cancellationToken));
                issues = [];
            }

            return new ProjectWorkflowMutation(
                row.Succeeded,
                row.Code,
                row.Completeness ?? 0,
                row.ProjectPublicId,
                (ProjectPublicationStatus)(row.PublicationStatus ?? 0),
                ToUtc(row.SubmittedAtUtc),
                ToUtc(row.PublishedAtUtc),
                ToUtc(row.ReviewedAtUtc),
                row.ReviewedByUserPublicId,
                row.RejectionReason,
                row.RowVersion ?? [],
                row.WasReplay,
                issues);
        }
        catch (SqlException exception)
        {
            throw Wrap(operation, exception);
        }
    }

    private static ProjectSummary MapSummary(ProjectSummaryRow row) => new(
        row.PublicId, row.Slug, row.Title, row.Summary, (ProjectStatus)row.ProjectStatus,
        (ProjectPublicationStatus)row.PublicationStatus, ToDateOnly(row.StartDate),
        ToDateOnly(row.EndDate), row.BudgetTotal, row.ConfirmedFunding, row.Currency?.Trim(),
        row.FundingGap, row.ProjectVersion, ToUtc(row.UpdatedAtUtc));

    private static DataTable ToIdTable<T>(IEnumerable<T> ids)
    {
        var table = new DataTable();
        table.Columns.Add("Id", typeof(T));
        foreach (var id in ids) table.Rows.Add(id);
        return table;
    }

    private static DateTime? ToDateTime(DateOnly? value) =>
        value?.ToDateTime(TimeOnly.MinValue);

    private static DateOnly? ToDateOnly(DateTime? value) =>
        value.HasValue ? DateOnly.FromDateTime(value.Value) : null;

    private static DateTimeOffset ToUtc(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static DateTimeOffset? ToUtc(DateTime? value) =>
        value.HasValue ? ToUtc(value.Value) : null;

    private static IReadOnlyList<PublicProjectTaxonomyItem> DeserializeTaxonomy(string json) =>
        JsonSerializer.Deserialize<PublicProjectTaxonomyItem[]>(json, PublicJsonOptions) ?? [];

    private static IReadOnlyList<PublicProjectRegion> DeserializeRegions(string json) =>
        JsonSerializer.Deserialize<PublicProjectRegion[]>(json, PublicJsonOptions) ?? [];

    private static ProjectDataException Wrap(string operation, SqlException exception) =>
        new(operation, exception.Number, exception);

    private sealed class ShortIdRow { public short Id { get; set; } }
    private sealed class IntIdRow { public int Id { get; set; } }
    private sealed class PersistedProjectRow { public Guid PublicId { get; set; } public int ProjectVersion { get; set; } public byte[] RowVersion { get; set; } = []; }
    private class ProjectSummaryRow
    {
        public Guid PublicId { get; set; }
        public string Slug { get; set; } = "";
        public string Title { get; set; } = "";
        public string? Summary { get; set; }
        public byte ProjectStatus { get; set; }
        public byte PublicationStatus { get; set; }
        public DateTime? StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        public decimal? BudgetTotal { get; set; }
        public decimal? ConfirmedFunding { get; set; }
        public string? Currency { get; set; }
        public decimal? FundingGap { get; set; }
        public int ProjectVersion { get; set; }
        public DateTime UpdatedAtUtc { get; set; }
    }
    private sealed class ProjectDetailsRow : ProjectSummaryRow
    {
        public string? Description { get; set; }
        public byte[] RowVersion { get; set; } = [];
        public DateTime? SubmittedAtUtc { get; set; }
        public DateTime? ReviewedAtUtc { get; set; }
        public string? RejectionReason { get; set; }
        public DateTime? PublishedAtUtc { get; set; }
    }

    private sealed class WorkflowMutationRow
    {
        public bool Succeeded { get; set; }
        public string Code { get; set; } = string.Empty;
        public decimal? Completeness { get; set; }
        public Guid ProjectPublicId { get; set; }
        public byte? PublicationStatus { get; set; }
        public DateTime? SubmittedAtUtc { get; set; }
        public DateTime? PublishedAtUtc { get; set; }
        public DateTime? ReviewedAtUtc { get; set; }
        public Guid? ReviewedByUserPublicId { get; set; }
        public string? RejectionReason { get; set; }
        public byte[]? RowVersion { get; set; }
        public bool WasReplay { get; set; }
    }

    private sealed class ProjectReviewQueueRow
    {
        public Guid ProjectPublicId { get; set; }
        public string Slug { get; set; } = string.Empty;
        public string Title { get; set; } = string.Empty;
        public string? Summary { get; set; }
        public byte ProjectStatus { get; set; }
        public byte PublicationStatus { get; set; }
        public DateTime SubmittedAtUtc { get; set; }
        public DateTime UpdatedAtUtc { get; set; }
        public byte[] RowVersion { get; set; } = [];
        public Guid OrganizationPublicId { get; set; }
        public string OrganizationName { get; set; } = string.Empty;
        public decimal Completeness { get; set; }
    }

    private sealed class PublicProjectRow
    {
        public Guid ProjectPublicId { get; set; }
        public string Slug { get; set; } = string.Empty;
        public string Title { get; set; } = string.Empty;
        public string? Summary { get; set; }
        public string? Description { get; set; }
        public byte ProjectStatus { get; set; }
        public DateTime? StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        public decimal? BudgetTotal { get; set; }
        public decimal? ConfirmedFunding { get; set; }
        public string? Currency { get; set; }
        public decimal? FundingGap { get; set; }
        public DateTime PublishedAtUtc { get; set; }
        public Guid OrganizationPublicId { get; set; }
        public string OrganizationName { get; set; } = string.Empty;
        public string? OrganizationWebsiteUrl { get; set; }
        public string CountriesJson { get; set; } = "[]";
        public string RegionsJson { get; set; } = "[]";
        public string CategoriesJson { get; set; } = "[]";
        public string BeneficiaryTypesJson { get; set; } = "[]";
        public string ProjectTypesJson { get; set; } = "[]";
    }

    private sealed class ProjectReviewDetailRow
    {
        public Guid ProjectPublicId { get; set; }
        public string Slug { get; set; } = string.Empty;
        public string Title { get; set; } = string.Empty;
        public string? Summary { get; set; }
        public string? Description { get; set; }
        public byte ProjectStatus { get; set; }
        public byte PublicationStatus { get; set; }
        public DateTime? StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        public decimal? BudgetTotal { get; set; }
        public decimal? ConfirmedFunding { get; set; }
        public string? Currency { get; set; }
        public decimal? FundingGap { get; set; }
        public int ProjectVersion { get; set; }
        public decimal Completeness { get; set; }
        public DateTime SubmittedAtUtc { get; set; }
        public DateTime UpdatedAtUtc { get; set; }
        public byte[] RowVersion { get; set; } = [];
        public Guid OrganizationPublicId { get; set; }
        public string OrganizationName { get; set; } = string.Empty;
        public string? OrganizationWebsiteUrl { get; set; }
        public string CountriesJson { get; set; } = "[]";
        public string RegionsJson { get; set; } = "[]";
        public string CategoriesJson { get; set; } = "[]";
        public string BeneficiaryTypesJson { get; set; } = "[]";
        public string ProjectTypesJson { get; set; } = "[]";
    }
}
