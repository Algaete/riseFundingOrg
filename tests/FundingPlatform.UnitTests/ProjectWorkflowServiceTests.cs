using System.Text;
using FundingPlatform.Application.Projects;
using FundingPlatform.Core.Projects;

namespace FundingPlatform.UnitTests;

public sealed class ProjectWorkflowServiceTests
{
    private static readonly Guid UserId = Guid.Parse("11111111-1111-1111-1111-111111111111");
    private static readonly Guid OrganizationId = Guid.Parse("22222222-2222-2222-2222-222222222222");
    private static readonly Guid ProjectId = Guid.Parse("33333333-3333-3333-3333-333333333333");
    private static readonly byte[] RowVersion = Convert.FromHexString("0102030405060708");

    [Fact]
    public async Task Request_publication_rejects_short_idempotency_key_without_repository_call()
    {
        var repository = new StubRepository();
        var service = new ProjectWorkflowService(repository);

        var result = await service.RequestPublicationAsync(
            UserId, OrganizationId, ProjectId, RowVersion, "too-short", CancellationToken.None);

        Assert.Equal(ProjectWorkflowOutcome.ValidationFailed, result.Outcome);
        Assert.Contains("idempotencyKey", result.Errors!.Keys);
        Assert.Equal(0, repository.RequestPublicationCalls);
    }

    [Fact]
    public async Task Request_publication_hashes_key_and_canonical_request_before_repository()
    {
        const string rawKey = "workflow-request-0001";
        var repository = new StubRepository { Mutation = SuccessfulMutation() };
        var service = new ProjectWorkflowService(repository);

        var result = await service.RequestPublicationAsync(
            UserId, OrganizationId, ProjectId, RowVersion, rawKey, CancellationToken.None);

        Assert.Equal(ProjectWorkflowOutcome.Success, result.Outcome);
        Assert.Equal(32, repository.IdempotencyKeyHash!.Length);
        Assert.Equal(32, repository.RequestHash!.Length);
        Assert.False(Encoding.UTF8.GetBytes(rawKey).SequenceEqual(repository.IdempotencyKeyHash));
        Assert.Equal(1, repository.RequestPublicationCalls);
    }

    [Fact]
    public async Task Request_publication_preserves_concrete_readiness_fields()
    {
        var repository = new StubRepository
        {
            Mutation = SuccessfulMutation() with
            {
                Succeeded = false,
                Code = "project-not-ready",
                Completeness = 80,
                Issues =
                [
                    new ProjectReadinessIssue("description-required", "description",
                        "Agrega una descripción."),
                    new ProjectReadinessIssue("country-required", "countryIds",
                        "Selecciona al menos un país.")
                ]
            }
        };
        var service = new ProjectWorkflowService(repository);

        var result = await service.RequestPublicationAsync(
            UserId, OrganizationId, ProjectId, RowVersion,
            "workflow-request-0002", CancellationToken.None);

        Assert.Equal(ProjectWorkflowOutcome.NotReady, result.Outcome);
        Assert.Equal(80, result.Completeness);
        Assert.Equal("Agrega una descripción.", Assert.Single(result.Errors!["description"]));
        Assert.Equal("Selecciona al menos un país.", Assert.Single(result.Errors["countryIds"]));
    }

    [Fact]
    public async Task Approval_maps_organization_not_ready_to_field_error()
    {
        var repository = new StubRepository
        {
            Mutation = SuccessfulMutation() with
            {
                Succeeded = false,
                Code = "organization-not-ready",
                Issues = []
            }
        };
        var service = new ProjectWorkflowService(repository);

        var result = await service.ReviewAsync(
            UserId, ProjectId, ProjectReviewDecision.Approve, null, RowVersion,
            "workflow-review-0001", CancellationToken.None);

        Assert.Equal(ProjectWorkflowOutcome.NotReady, result.Outcome);
        Assert.Contains("organizationProfile", result.Errors!.Keys);
    }

    [Fact]
    public async Task Rejection_requires_reason_without_repository_call()
    {
        var repository = new StubRepository();
        var service = new ProjectWorkflowService(repository);

        var result = await service.ReviewAsync(
            UserId, ProjectId, ProjectReviewDecision.Reject, "  ", RowVersion,
            "workflow-review-0002", CancellationToken.None);

        Assert.Equal(ProjectWorkflowOutcome.ValidationFailed, result.Outcome);
        Assert.Contains("reason", result.Errors!.Keys);
        Assert.Equal(0, repository.ReviewCalls);
    }

    [Fact]
    public async Task Public_slug_is_trimmed_and_oversized_slug_never_reaches_sql()
    {
        var repository = new StubRepository();
        var service = new ProjectWorkflowService(repository);

        await service.GetPublishedBySlugAsync("  agua-segura  ", CancellationToken.None);
        var invalid = await service.GetPublishedBySlugAsync(new string('x', 181), CancellationToken.None);

        Assert.Equal("agua-segura", repository.PublicSlug);
        Assert.Null(invalid);
        Assert.Equal(1, repository.PublicCalls);
    }

    [Fact]
    public async Task Admin_review_detail_maps_database_role_guard_to_forbidden()
    {
        var repository = new StubRepository { ReviewDetailsErrorNumber = 51503 };
        var service = new ProjectWorkflowService(repository);

        var result = await service.GetReviewDetailsAsync(UserId, ProjectId, CancellationToken.None);

        Assert.Equal(ProjectWorkflowOutcome.Forbidden, result.Outcome);
        Assert.Null(result.Project);
    }

    [Theory]
    [InlineData(ProjectPublicationStatus.Draft, true)]
    [InlineData(ProjectPublicationStatus.PendingReview, true)]
    [InlineData(ProjectPublicationStatus.Published, true)]
    [InlineData(ProjectPublicationStatus.Rejected, true)]
    [InlineData(ProjectPublicationStatus.Archived, false)]
    public void Archive_transition_matches_database_contract(
        ProjectPublicationStatus status,
        bool expected) =>
        Assert.Equal(expected, ProjectWorkflowStateMachine.CanArchive(status));

    private static ProjectWorkflowMutation SuccessfulMutation() => new(
        true,
        "publication-requested",
        100,
        ProjectId,
        ProjectPublicationStatus.PendingReview,
        DateTimeOffset.Parse("2026-08-21T12:00:00Z"),
        null,
        null,
        null,
        null,
        RowVersion,
        false,
        []);

    private sealed class StubRepository : IProjectRepository
    {
        public ProjectWorkflowMutation Mutation { get; set; } = SuccessfulMutation();
        public int RequestPublicationCalls { get; private set; }
        public int ReviewCalls { get; private set; }
        public int PublicCalls { get; private set; }
        public byte[]? IdempotencyKeyHash { get; private set; }
        public byte[]? RequestHash { get; private set; }
        public string? PublicSlug { get; private set; }
        public int? ReviewDetailsErrorNumber { get; init; }

        public Task<ProjectWorkflowMutation> RequestPublicationAsync(
            Guid userPublicId, Guid organizationPublicId, Guid projectPublicId,
            byte[] expectedRowVersion, byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken)
        {
            RequestPublicationCalls++;
            CaptureHashes(idempotencyKeyHash, requestHash);
            return Task.FromResult(Mutation);
        }

        public Task<ProjectWorkflowMutation> ArchiveAsync(
            Guid userPublicId, Guid organizationPublicId, Guid projectPublicId,
            byte[] expectedRowVersion, byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken)
        {
            CaptureHashes(idempotencyKeyHash, requestHash);
            return Task.FromResult(Mutation);
        }

        public Task<ProjectWorkflowMutation> ReviewAsync(
            Guid userPublicId, Guid projectPublicId, ProjectReviewDecision decision,
            string? reason, byte[] expectedRowVersion, byte[] idempotencyKeyHash,
            byte[] requestHash, CancellationToken cancellationToken)
        {
            ReviewCalls++;
            CaptureHashes(idempotencyKeyHash, requestHash);
            return Task.FromResult(Mutation);
        }

        public Task<ProjectReviewQueuePage> ListReviewQueueAsync(
            Guid userPublicId, int pageNumber, int pageSize,
            CancellationToken cancellationToken) =>
            Task.FromResult(new ProjectReviewQueuePage([], 0, pageNumber, pageSize));

        public Task<ProjectReviewDetails?> GetReviewDetailsAsync(
            Guid userPublicId, Guid projectPublicId,
            CancellationToken cancellationToken)
        {
            if (ReviewDetailsErrorNumber.HasValue)
            {
                throw new ProjectDataException(
                    "read review detail",
                    ReviewDetailsErrorNumber.Value,
                    new Exception("sensitive database detail"));
            }

            return Task.FromResult<ProjectReviewDetails?>(null);
        }

        public Task<PublicProjectDetails?> GetPublishedBySlugAsync(
            string slug, CancellationToken cancellationToken)
        {
            PublicCalls++;
            PublicSlug = slug;
            return Task.FromResult<PublicProjectDetails?>(null);
        }

        public Task<IReadOnlyList<ProjectSummary>> ListAsync(
            Guid userPublicId, Guid organizationPublicId,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<ProjectDetails?> GetAsync(
            Guid userPublicId, Guid organizationPublicId, Guid projectPublicId,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<PersistedProject> CreateAsync(
            Guid userPublicId, Guid organizationPublicId, string slug, ProjectData project,
            string snapshotJson, byte[] contentHash, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<PersistedProject> UpdateAsync(
            Guid userPublicId, Guid organizationPublicId, Guid projectPublicId,
            byte[] expectedRowVersion, ProjectData project, string snapshotJson,
            byte[] contentHash, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        private void CaptureHashes(byte[] idempotencyKeyHash, byte[] requestHash)
        {
            IdempotencyKeyHash = idempotencyKeyHash;
            RequestHash = requestHash;
        }
    }
}
