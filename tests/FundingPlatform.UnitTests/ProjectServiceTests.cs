using FundingPlatform.Application.Projects;
using FundingPlatform.Core.Projects;
using FundingPlatform.Core.Validation;

namespace FundingPlatform.UnitTests;

public sealed class ProjectServiceTests
{
    [Fact]
    public async Task Validation_exposes_stable_codes_and_rule_bounds_without_submitted_text()
    {
        var repository = new StubRepository();
        var result = await new ProjectService(repository).CreateAsync(Guid.NewGuid(), Guid.NewGuid(),
            ValidProject() with { Title = "x", Summary = new string('x', 1001), BudgetTotal = -1 },
            CancellationToken.None);

        var errors = Assert.IsType<FieldValidationErrors>(result.Errors);
        Assert.Equal("project-title-length", Assert.Single(errors.Issues["title"]).Code);
        Assert.Equal(new FieldValidationIssue("text-max-length", Max: 1000), Assert.Single(errors.Issues["summary"]));
        Assert.Equal("Admite hasta 1000 caracteres.", Assert.Single(errors["summary"]));
        Assert.Equal("amount-negative", Assert.Single(errors.Issues["budgetTotal"]).Code);
        Assert.Equal(errors.Keys.Order(), errors.Issues.Keys.Order());
        Assert.Null(repository.WrittenProject);
    }

    [Fact]
    public async Task Create_normalizes_collections_currency_and_writes_snapshot()
    {
        var repository = new StubRepository();
        var service = new ProjectService(repository);

        var result = await service.CreateAsync(Guid.NewGuid(), Guid.NewGuid(), ValidProject() with
        {
            Title = "  Agua segura  ",
            Currency = " clp ",
            Status = ProjectStatus.Idea,
            CountryIds = [152, 152],
            CategoryIds = [2, 1, 2],
            SustainableDevelopmentGoalIds = [13, 1, 13]
        }, CancellationToken.None);

        Assert.Equal(ProjectWriteOutcome.Success, result.Outcome);
        Assert.Equal("Agua segura", repository.WrittenProject!.Title);
        Assert.Equal("CLP", repository.WrittenProject.Currency);
        Assert.Equal(ProjectStatus.SeekingFunding, repository.WrittenProject.Status);
        Assert.Equal(ProjectStage.Pilot, repository.WrittenProject.Stage);
        Assert.Equal([152], repository.WrittenProject.CountryIds);
        Assert.Equal([1, 2], repository.WrittenProject.CategoryIds);
        Assert.Equal([1, 13], repository.WrittenProject.SustainableDevelopmentGoalIds);
        Assert.StartsWith("agua-segura-", repository.Slug, StringComparison.Ordinal);
        Assert.Contains("\"title\":\"Agua segura\"", repository.SnapshotJson, StringComparison.Ordinal);
        Assert.Contains("\"projectStage\":1", repository.SnapshotJson, StringComparison.Ordinal);
        Assert.Contains("\"sustainableDevelopmentGoalIds\":[1,13]", repository.SnapshotJson,
            StringComparison.Ordinal);
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
    public async Task Update_maps_legacy_impact_guard_to_conflict()
    {
        var repository = new StubRepository { ErrorNumber = 51411 };
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
        Assert.Equal("project-data-invalid", Assert.IsType<FieldValidationErrors>(result.Errors).Issues["project"][0].Code);
    }

    [Fact]
    public async Task Update_rejects_invalid_stage_and_sdg_without_writing()
    {
        var repository = new StubRepository();
        var service = new ProjectService(repository);

        var result = await service.UpdateAsync(
            Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), new byte[8],
            ValidProject() with
            {
                Stage = (ProjectStage)6,
                SustainableDevelopmentGoalIds = [18]
            }, CancellationToken.None);

        Assert.Equal(ProjectWriteOutcome.ValidationFailed, result.Outcome);
        Assert.Contains("projectStage", result.Errors!.Keys);
        Assert.Contains("sustainableDevelopmentGoalIds", result.Errors.Keys);
        Assert.Null(repository.WrittenProject);
    }

    [Fact]
    public async Task Enrichment_is_normalized_and_included_in_the_atomic_content_hash()
    {
        var repository = new StubRepository();
        var result = await new ProjectService(repository).CreateAsync(Guid.NewGuid(), Guid.NewGuid(),
            ValidProject() with { Enrichment = new(Problem: "  Water access  ", BeneficiaryCount: 250,
                Latitude: -33.456789m, Longitude: -70.654321m, SeekingConsortium: true,
                ImpactIndicators: [new("Households", "people", 0, 250)]) }, CancellationToken.None);
        Assert.Equal(ProjectWriteOutcome.Success, result.Outcome);
        Assert.Equal("Water access", repository.WrittenProject!.Enrichment!.Problem);
        using var snapshot = System.Text.Json.JsonDocument.Parse(repository.SnapshotJson!);
        Assert.Equal(-33.456789m, snapshot.RootElement.GetProperty("enrichment").GetProperty("latitude").GetDecimal());
        Assert.Equal(250, snapshot.RootElement.GetProperty("enrichment").GetProperty("beneficiaryCount").GetInt32());
        Assert.Equal(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(repository.SnapshotJson!)), repository.ContentHash);
    }

    [Fact]
    public async Task Invalid_enrichment_never_reaches_persistence()
    {
        var repository = new StubRepository();
        var result = await new ProjectService(repository).CreateAsync(Guid.NewGuid(), Guid.NewGuid(),
            ValidProject() with { Enrichment = new(Latitude: 3) }, CancellationToken.None);
        Assert.Equal(ProjectWriteOutcome.ValidationFailed, result.Outcome);
        Assert.Null(repository.WrittenProject);
        Assert.Contains("enrichment.latitude", result.Errors!.Keys);
    }

    private static ProjectData ValidProject() => new(
        "Agua segura", "Resumen", "Descripción", ProjectStatus.SeekingFunding,
        ProjectStage.Pilot,
        new DateOnly(2027, 1, 1), new DateOnly(2027, 12, 31),
        100_000, 25_000, "CLP", [152], [7], [1], [1], [1], [1, 13]);

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
