using FundingPlatform.Application.Matching;
using FundingPlatform.Core.Matching;

namespace FundingPlatform.UnitTests;

public sealed class ProjectMatchingServiceTests
{
    private static readonly Guid UserId = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid OrganizationId = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid ProjectId = Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");
    private static readonly Guid RunId = Guid.Parse("dddddddd-dddd-dddd-dddd-dddddddddddd");

    [Fact]
    public async Task Create_hashes_server_owned_request_and_returns_durable_replay()
    {
        var repository = new FakeRepository
        {
            Mutation = new ProjectMatchingRunMutation(true, "replayed", RunId, true),
            Details = Details()
        };
        var service = new ProjectMatchingService(repository);

        var result = await service.CreateRunAsync(
            UserId,
            OrganizationId,
            ProjectId,
            " 1234567890abcdef ",
            CancellationToken.None);

        Assert.Equal(ProjectMatchingOutcome.Success, result.Outcome);
        Assert.True(result.WasReplay);
        Assert.Equal(32, repository.IdempotencyKeyHash!.Length);
        Assert.Equal(32, repository.RequestHash!.Length);
        Assert.Equal(1, repository.CreateCalls);
        Assert.Equal(1, repository.GetCalls);
        Assert.Equal(RunId, result.Details!.Run.PublicId);
    }

    [Fact]
    public async Task Create_rejects_client_preconditions_before_repository()
    {
        var repository = new FakeRepository();
        var service = new ProjectMatchingService(repository);

        var result = await service.CreateRunAsync(
            UserId,
            Guid.Empty,
            Guid.Empty,
            "short",
            CancellationToken.None);

        Assert.Equal(ProjectMatchingOutcome.ValidationFailed, result.Outcome);
        Assert.Contains("organizationId", result.Errors!);
        Assert.Contains("projectId", result.Errors!);
        Assert.Contains("idempotencyKey", result.Errors!);
        Assert.Equal(0, repository.CreateCalls);
    }

    [Theory]
    [InlineData("not-found", ProjectMatchingOutcome.NotFound)]
    [InlineData("project-not-ready", ProjectMatchingOutcome.NotReady)]
    [InlineData("profile-not-ready", ProjectMatchingOutcome.NotReady)]
    [InlineData("idempotency-conflict", ProjectMatchingOutcome.IdempotencyConflict)]
    [InlineData("unexpected", ProjectMatchingOutcome.Conflict)]
    public async Task Create_maps_safe_stable_mutation_codes(
        string code,
        ProjectMatchingOutcome expected)
    {
        var repository = new FakeRepository
        {
            Mutation = new ProjectMatchingRunMutation(false, code, Guid.Empty, false)
        };
        var service = new ProjectMatchingService(repository);

        var result = await service.CreateRunAsync(
            UserId,
            OrganizationId,
            ProjectId,
            "1234567890abcdef",
            CancellationToken.None);

        Assert.Equal(expected, result.Outcome);
        Assert.Equal(0, repository.GetCalls);
    }

    [Theory]
    [InlineData(52401, ProjectMatchingOutcome.NotFound)]
    [InlineData(52402, ProjectMatchingOutcome.ValidationFailed)]
    [InlineData(52403, ProjectMatchingOutcome.IdempotencyConflict)]
    [InlineData(52404, ProjectMatchingOutcome.Unavailable)]
    public async Task Create_maps_sql_errors_without_leaking_database_details(
        int databaseErrorNumber,
        ProjectMatchingOutcome expected)
    {
        var repository = new FakeRepository { ThrowCreateNumber = databaseErrorNumber };
        var service = new ProjectMatchingService(repository);

        var result = await service.CreateRunAsync(
            UserId,
            OrganizationId,
            ProjectId,
            "1234567890abcdef",
            CancellationToken.None);

        Assert.Equal(expected, result.Outcome);
        Assert.Equal(0, repository.GetCalls);
    }

    [Fact]
    public async Task List_is_bounded_and_foreign_tenant_is_indistinguishable_not_found()
    {
        var repository = new FakeRepository();
        var service = new ProjectMatchingService(repository);

        var invalid = await service.ListRunsAsync(
            UserId,
            OrganizationId,
            ProjectId,
            new ProjectMatchingRunListFilters(0, 51),
            CancellationToken.None);

        Assert.Equal(ProjectMatchingOutcome.ValidationFailed, invalid.Outcome);
        Assert.Equal(0, repository.ListCalls);

        repository.ThrowNotFound = true;
        var foreign = await service.ListRunsAsync(
            UserId,
            OrganizationId,
            ProjectId,
            new ProjectMatchingRunListFilters(1, 20),
            CancellationToken.None);

        Assert.Equal(ProjectMatchingOutcome.NotFound, foreign.Outcome);
        Assert.Null(foreign.Errors);
    }

    private static ProjectMatchingRunDetails Details() => new(
        new ProjectMatchingRunSummary(
            RunId,
            new MatchingProjectReference(ProjectId, "proyecto", "Proyecto"),
            MatchingRunStatus.Completed,
            "deterministic-v1",
            new MatchingProfileReference("deterministic", 1),
            3,
            4,
            1,
            1,
            0,
            0,
            1,
            false,
            true,
            new DateTimeOffset(2026, 8, 24, 12, 0, 0, TimeSpan.Zero),
            new DateTimeOffset(2026, 8, 24, 12, 0, 0, TimeSpan.Zero),
            new DateTimeOffset(2026, 8, 24, 12, 0, 1, TimeSpan.Zero)),
        []);

    private sealed class FakeRepository : IProjectMatchingRepository
    {
        public bool ThrowNotFound { get; set; }
        public int? ThrowCreateNumber { get; init; }
        public ProjectMatchingRunMutation Mutation { get; init; } =
            new(true, "created", RunId, false);
        public ProjectMatchingRunDetails? Details { get; init; } =
            ProjectMatchingServiceTests.Details();
        public byte[]? IdempotencyKeyHash { get; private set; }
        public byte[]? RequestHash { get; private set; }
        public int CreateCalls { get; private set; }
        public int GetCalls { get; private set; }
        public int ListCalls { get; private set; }

        public Task<ProjectMatchingRunPage> ListRunsAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            ProjectMatchingRunListFilters filters,
            CancellationToken cancellationToken)
        {
            ListCalls++;
            if (ThrowNotFound)
            {
                throw new ProjectMatchingDataException("list", 52401, new Exception());
            }

            return Task.FromResult(new ProjectMatchingRunPage(
                [], 0, filters.PageNumber, filters.PageSize));
        }

        public Task<ProjectMatchingRunDetails?> GetRunAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid matchingRunPublicId,
            CancellationToken cancellationToken)
        {
            GetCalls++;
            return Task.FromResult(Details);
        }

        public Task<ProjectMatchingRunMutation> CreateRunAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            CancellationToken cancellationToken)
        {
            CreateCalls++;
            if (ThrowCreateNumber.HasValue)
            {
                throw new ProjectMatchingDataException(
                    "create",
                    ThrowCreateNumber.Value,
                    new Exception("database detail must not escape"));
            }

            IdempotencyKeyHash = idempotencyKeyHash;
            RequestHash = requestHash;
            return Task.FromResult(Mutation);
        }
    }
}
