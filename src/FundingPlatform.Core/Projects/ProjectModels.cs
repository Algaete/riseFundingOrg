using System.Text.Json.Serialization;

namespace FundingPlatform.Core.Projects;

public enum ProjectStatus : byte
{
    Idea = 0,
    Design = 1,
    SeekingFunding = 2,
    PartiallyFunded = 3,
    Funded = 4,
    Implementing = 5,
    Completed = 6
}

public enum ProjectStage : byte
{
    IdeaOrDesign = 0,
    Pilot = 1,
    Implementation = 2,
    Scaling = 3,
    Consolidation = 4,
    Evaluation = 5
}

public enum ProjectPublicationStatus : byte
{
    Draft = 0,
    PendingReview = 1,
    Published = 2,
    Rejected = 3,
    Archived = 4
}

public sealed record ProjectSummary(
    Guid PublicId,
    string Slug,
    string Title,
    string? Summary,
    ProjectStatus Status,
    ProjectStage? Stage,
    ProjectPublicationStatus PublicationStatus,
    DateOnly? StartDate,
    DateOnly? EndDate,
    decimal? BudgetTotal,
    decimal? ConfirmedFunding,
    string? Currency,
    decimal? FundingGap,
    int ProjectVersion,
    DateTimeOffset UpdatedAtUtc);

public sealed record ProjectDetails(
    Guid PublicId,
    string Slug,
    string Title,
    string? Summary,
    string? Description,
    ProjectStatus Status,
    ProjectStage? Stage,
    ProjectPublicationStatus PublicationStatus,
    DateOnly? StartDate,
    DateOnly? EndDate,
    decimal? BudgetTotal,
    decimal? ConfirmedFunding,
    string? Currency,
    decimal? FundingGap,
    int ProjectVersion,
    DateTimeOffset UpdatedAtUtc,
    byte[] RowVersion,
    IReadOnlyList<short> CountryIds,
    IReadOnlyList<int> RegionIds,
    IReadOnlyList<int> CategoryIds,
    IReadOnlyList<int> BeneficiaryTypeIds,
    IReadOnlyList<int> ProjectTypeIds,
    IReadOnlyList<int> SustainableDevelopmentGoalIds,
    DateTimeOffset? SubmittedAtUtc = null,
    DateTimeOffset? ReviewedAtUtc = null,
    string? RejectionReason = null,
    DateTimeOffset? PublishedAtUtc = null,
    ProjectEnrichment? Enrichment = null);

public sealed record ProjectData(
    string Title,
    string? Summary,
    string? Description,
    ProjectStatus Status,
    [property: JsonPropertyName("projectStage")] ProjectStage? Stage,
    DateOnly? StartDate,
    DateOnly? EndDate,
    decimal? BudgetTotal,
    decimal? ConfirmedFunding,
    string? Currency,
    IReadOnlyList<short> CountryIds,
    IReadOnlyList<int> RegionIds,
    IReadOnlyList<int> CategoryIds,
    IReadOnlyList<int> BeneficiaryTypeIds,
    IReadOnlyList<int> ProjectTypeIds,
    IReadOnlyList<int> SustainableDevelopmentGoalIds,
    ProjectEnrichment? Enrichment = null);

public sealed record PersistedProject(Guid PublicId, int ProjectVersion, byte[] RowVersion);

public enum ProjectWriteOutcome
{
    Success,
    ValidationFailed,
    NotFound,
    Conflict,
    InvalidState
}

public sealed record ProjectWriteResult(
    ProjectWriteOutcome Outcome,
    PersistedProject? Project = null,
    IReadOnlyDictionary<string, string[]>? Errors = null);

public sealed record ProjectListResult(
    bool OrganizationFound,
    IReadOnlyList<ProjectSummary> Projects);

public enum ProjectReviewDecision : byte
{
    Approve = 2,
    Reject = 3
}

public enum ProjectWorkflowAction
{
    RequestPublication,
    Archive,
    Approve,
    Reject
}

public static class ProjectWorkflowStateMachine
{
    public static bool CanEdit(ProjectPublicationStatus status) =>
        status is ProjectPublicationStatus.Draft or ProjectPublicationStatus.Rejected;

    public static bool CanRequestPublication(ProjectPublicationStatus status) =>
        status is ProjectPublicationStatus.Draft or ProjectPublicationStatus.Rejected;

    public static bool CanArchive(ProjectPublicationStatus status) =>
        status is ProjectPublicationStatus.Draft or ProjectPublicationStatus.PendingReview or
            ProjectPublicationStatus.Published or ProjectPublicationStatus.Rejected;

    public static bool CanReview(ProjectPublicationStatus status) =>
        status == ProjectPublicationStatus.PendingReview;
}

public sealed record ProjectReadinessIssue(
    string Code,
    string FieldPath,
    string Message);

public sealed record ProjectWorkflowMutation(
    bool Succeeded,
    string Code,
    decimal Completeness,
    Guid ProjectPublicId,
    ProjectPublicationStatus PublicationStatus,
    DateTimeOffset? SubmittedAtUtc,
    DateTimeOffset? PublishedAtUtc,
    DateTimeOffset? ReviewedAtUtc,
    Guid? ReviewedByUserPublicId,
    string? RejectionReason,
    byte[] RowVersion,
    bool WasReplay,
    IReadOnlyList<ProjectReadinessIssue> Issues);

public enum ProjectWorkflowOutcome
{
    Success,
    ValidationFailed,
    NotFound,
    Forbidden,
    Conflict,
    InvalidTransition,
    NotReady,
    IdempotencyConflict
}

public sealed record ProjectWorkflowResult(
    ProjectWorkflowOutcome Outcome,
    Guid ProjectPublicId,
    decimal Completeness = 0,
    ProjectPublicationStatus PublicationStatus = ProjectPublicationStatus.Draft,
    byte[]? RowVersion = null,
    bool WasReplay = false,
    IReadOnlyDictionary<string, string[]>? Errors = null,
    DateTimeOffset? SubmittedAtUtc = null,
    DateTimeOffset? PublishedAtUtc = null,
    DateTimeOffset? ReviewedAtUtc = null,
    Guid? ReviewedByUserPublicId = null,
    string? RejectionReason = null);

public sealed record ProjectReviewQueueItem(
    Guid PublicId,
    string Slug,
    string Title,
    string? Summary,
    ProjectStatus Status,
    ProjectStage? Stage,
    ProjectPublicationStatus PublicationStatus,
    Guid OrganizationPublicId,
    string OrganizationName,
    decimal Completeness,
    DateTimeOffset SubmittedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    byte[] RowVersion);

public sealed record ProjectReviewQueuePage(
    IReadOnlyList<ProjectReviewQueueItem> Items,
    long TotalCount,
    int PageNumber,
    int PageSize);

public sealed record ProjectReviewQueueResult(
    ProjectWorkflowOutcome Outcome,
    ProjectReviewQueuePage? Page = null);

public sealed record ProjectReviewDetailsResult(
    ProjectWorkflowOutcome Outcome,
    ProjectReviewDetails? Project = null);

public sealed record ProjectReviewDetails(
    Guid PublicId,
    string Slug,
    string Title,
    string? Summary,
    string? Description,
    ProjectStatus Status,
    ProjectStage? Stage,
    ProjectPublicationStatus PublicationStatus,
    DateOnly? StartDate,
    DateOnly? EndDate,
    decimal? BudgetTotal,
    decimal? ConfirmedFunding,
    string? Currency,
    decimal? FundingGap,
    int ProjectVersion,
    decimal Completeness,
    DateTimeOffset SubmittedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    byte[] RowVersion,
    PublicProjectOrganization Organization,
    IReadOnlyList<PublicProjectTaxonomyItem> Countries,
    IReadOnlyList<PublicProjectRegion> Regions,
    IReadOnlyList<PublicProjectTaxonomyItem> Categories,
    IReadOnlyList<PublicProjectTaxonomyItem> BeneficiaryTypes,
    IReadOnlyList<PublicProjectTaxonomyItem> ProjectTypes,
    IReadOnlyList<PublicProjectTaxonomyItem> SustainableDevelopmentGoals,
    ProjectEnrichment? Enrichment = null);

public sealed record PublicProjectOrganization(
    Guid PublicId,
    string Name,
    string? WebsiteUrl);

public sealed record PublicProjectTaxonomyItem(
    int Id,
    string Code,
    string Name);

public sealed record PublicProjectRegion(
    int Id,
    short CountryId,
    string Code,
    string Name);

public sealed record PublicProjectDetails(
    Guid PublicId,
    string Slug,
    string Title,
    string? Summary,
    string? Description,
    ProjectStatus Status,
    ProjectStage? Stage,
    DateOnly? StartDate,
    DateOnly? EndDate,
    decimal? BudgetTotal,
    decimal? ConfirmedFunding,
    string? Currency,
    decimal? FundingGap,
    DateTimeOffset PublishedAtUtc,
    PublicProjectOrganization Organization,
    IReadOnlyList<PublicProjectTaxonomyItem> Countries,
    IReadOnlyList<PublicProjectRegion> Regions,
    IReadOnlyList<PublicProjectTaxonomyItem> Categories,
    IReadOnlyList<PublicProjectTaxonomyItem> BeneficiaryTypes,
    IReadOnlyList<PublicProjectTaxonomyItem> ProjectTypes,
    IReadOnlyList<PublicProjectTaxonomyItem> SustainableDevelopmentGoals,
    ProjectEnrichment? Enrichment = null);
