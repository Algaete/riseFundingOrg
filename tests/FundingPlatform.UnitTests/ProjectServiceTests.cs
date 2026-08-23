using FundingPlatform.Application.Projects;
using FundingPlatform.Core.Projects;

namespace FundingPlatform.UnitTests;

public sealed class ProjectServiceTests
{
    [Fact]
    public async Task Create_normalizes_collections_currency_and_writes_snapshot()
    {
        var repository = new StubRepository();
        var service = new ProjectService(repository);

        var result = await service.CreateAsync(Guid.NewGuid(), Guid.NewGuid(), ValidProject() with
        {
            Title = "  Agua segura  ",
            Currency = " clp ",
            CountryIds = [152, 152],
            CategoryIds = [2, 1, 2]
        }, CancellationToken.None);

        Assert.Equal(ProjectWriteOutcome.Success, result.Outcome);
        Assert.Equal("Agua segura", repository.WrittenProject!.Title);
        Assert.Equal("CLP", repository.WrittenProject.Currency);
        Assert.Equal([152], repository.WrittenProject.CountryIds);
        Assert.Equal([1, 2], repository.WrittenProject.CategoryIds);
        Assert.StartsWith("agua-segura-", repository.Slug, StringComparison.Ordinal);
        Assert.Contains("\"title\":\"Agua segura\"", repository.SnapshotJson, StringComparison.Ordinal);
        Assert.Equal(32, repository.ContentHash!.Length);
    }

    [Fact]
    public async Task Create_rejects_inconsistent_budget_without_calling_repository()
    {
        var repository = new StubRepository();
        var service = new ProjectService(repository);

        var result = await service.CreateAsync(Guid.NewGuid(), Guid.NewGuid(), ValidProject() with
        {
            BudgetTotal = null,
            ConfirmedFunding = 100,
            Currency = "CLP"
        }, CancellationToken.None);

        Assert.Equal(ProjectWriteOutcome.ValidationFailed, result.Outcome);
        Assert.Contains("budgetTotal", result.Errors!.Keys);
        Assert.Null(repository.WrittenProject);
    }

    [Fact]
    public async Task Update_requires_a_valid_row_version()
    {
        var repository = new StubRepository();
        var service = new ProjectService(repository);

        var result = await service.UpdateAsync(
            Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), [1, 2], ValidProject(), CancellationToken.None);

        Assert.Equal(ProjectWriteOutcome.ValidationFailed, result.Outcome);
        Assert.Contains("ifMatch", result.Errors!.Keys);
        Assert.Null(repository.WrittenProject);
    }

    [Fact]
    public async Task Update_maps_concurrency_without_exposing_sql_message()
    {
        var repository = new StubRepository { ErrorNumber = 51407 };
        var service = new ProjectService(repository);

        var result = await service.UpdateAsync(
            Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), new byte[8], ValidProject(), CancellationToken.None);

        Assert.Equal(ProjectWriteOutcome.Conflict, result.Outcome);
    }

    [Fact]
    public async Task Update_maps_unknown_region_to_sanitized_validation_error()
    {
        var repository = new StubRepository { ErrorNumber = 51409 };
        var service = new ProjectService(repository);

        var result = await service.UpdateAsync(
            Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), new byte[8],
            ValidProject(), CancellationToken.None);

        Assert.Equal(ProjectWriteOutcome.ValidationFailed, result.Outcome);
        Assert.Equal(
            "El proyecto contiene relaciones o datos inválidos.",
            Assert.Single(result.Errors!["project"]));
    }

    private static ProjectData ValidProject() => new(
        "Agua segura", "Resumen", "Descripción", ProjectStatus.SeekingFunding,
        new DateOnly(2027, 1, 1), new DateOnly(2027, 12, 31),
        100_000, 25_000, "CLP", [152], [7], [1], [1], [1]);

    private sealed class StubRepository : IProjectRepository
    {
        public int? ErrorNumber { get; set; }
        public ProjectData? WrittenProject { get; private set; }
        public string? Slug { get; private set; }
        public string? SnapshotJson { get; private set; }
        public byte[]? ContentHash { get; private set; }

        public Task<IReadOnlyList<ProjectSummary>> ListAsync(Guid userPublicId, Guid organizationPublicId,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<ProjectDetails?> GetAsync(Guid userPublicId, Guid organizationPublicId,
            Guid projectPublicId, CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<PersistedProject> CreateAsync(Guid userPublicId, Guid organizationPublicId, string slug,
            ProjectData project, string snapshotJson, byte[] contentHash, CancellationToken cancellationToken)
        {
            Capture(project, snapshotJson, contentHash);
            Slug = slug;
            return Task.FromResult(new PersistedProject(Guid.NewGuid(), 1, new byte[8]));
        }

        public Task<PersistedProject> UpdateAsync(Guid userPublicId, Guid organizationPublicId,
            Guid projectPublicId, byte[] expectedRowVersion, ProjectData project, string snapshotJson,
            byte[] contentHash, CancellationToken cancellationToken)
        {
            if (ErrorNumber.HasValue)
                throw new ProjectDataException("update", ErrorNumber.Value, new Exception("sensitive sql detail"));
            Capture(project, snapshotJson, contentHash);
            return Task.FromResult(new PersistedProject(projectPublicId, 2, new byte[8]));
        }

        public Task<ProjectWorkflowMutation> RequestPublicationAsync(
            Guid userPublicId, Guid organizationPublicId, Guid projectPublicId,
            byte[] expectedRowVersion, byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<ProjectWorkflowMutation> ArchiveAsync(
            Guid userPublicId, Guid organizationPublicId, Guid projectPublicId,
            byte[] expectedRowVersion, byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<ProjectReviewQueuePage> ListReviewQueueAsync(
            Guid userPublicId, int pageNumber, int pageSize,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<ProjectReviewDetails?> GetReviewDetailsAsync(
            Guid userPublicId, Guid projectPublicId,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<ProjectWorkflowMutation> ReviewAsync(
            Guid userPublicId, Guid projectPublicId, ProjectReviewDecision decision,
            string? reason, byte[] expectedRowVersion, byte[] idempotencyKeyHash,
            byte[] requestHash, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<PublicProjectDetails?> GetPublishedBySlugAsync(
            string slug, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        private void Capture(ProjectData project, string snapshotJson, byte[] contentHash)
        {
            WrittenProject = project;
            SnapshotJson = snapshotJson;
            ContentHash = contentHash;
        }
    }
}
