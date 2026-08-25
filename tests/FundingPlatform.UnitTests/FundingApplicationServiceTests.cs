using FundingPlatform.Application.Applications;
using FundingPlatform.Core.Applications;

namespace FundingPlatform.UnitTests;

public sealed class FundingApplicationServiceTests
{
    private static readonly Guid UserId = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid OrganizationId = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid ProjectId = Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");
    private static readonly Guid OpportunityId = Guid.Parse("dddddddd-dddd-dddd-dddd-dddddddddddd");
    private static readonly Guid ApplicationId = Guid.Parse("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee");

    [Fact]
    public async Task Create_is_normalized_hashed_and_replay_safe()
    {
        var repository = new FakeFundingApplicationRepository
        {
            Mutation = Mutation(succeeded: true, "replayed", wasReplay: true),
            Details = Details()
        };
        var service = new FundingApplicationService(repository);

        var result = await service.CreateAsync(
            UserId,
            OrganizationId,
            ProjectId,
            OpportunityId,
            "1234567890abcdef",
            new FundingApplicationData(
                FundingApplicationStatus.Won,
                "  nota  ",
                new DateOnly(2026, 9, 1),
                1500.25m,
                " usd ",
                new DateOnly(2026, 10, 1)),
            CancellationToken.None);

        Assert.Equal(FundingApplicationOutcome.Success, result.Outcome);
        Assert.True(result.WasReplay);
        Assert.Equal(FundingApplicationStatus.Interested, repository.LastApplication!.Status);
        Assert.Equal("nota", repository.LastApplication.Notes);
        Assert.Equal("USD", repository.LastApplication.Currency);
        Assert.Equal(32, repository.LastIdempotencyHash!.Length);
        Assert.Equal(32, repository.LastRequestHash!.Length);
        Assert.Equal(1, repository.GetCalls);
    }

    [Fact]
    public async Task Create_rejects_unsafe_or_inconsistent_mutable_fields_before_sql()
    {
        var repository = new FakeFundingApplicationRepository();
        var service = new FundingApplicationService(repository);

        var result = await service.CreateAsync(
            UserId,
            OrganizationId,
            ProjectId,
            OpportunityId,
            "short",
            new FundingApplicationData(
                FundingApplicationStatus.Interested,
                new string('x', 5001),
                new DateOnly(2026, 10, 2),
                0,
                "US1",
                new DateOnly(2026, 10, 1)),
            CancellationToken.None);

        Assert.Equal(FundingApplicationOutcome.ValidationFailed, result.Outcome);
        Assert.Contains("notes", result.Errors!);
        Assert.Contains("resultDate", result.Errors!);
        Assert.Contains("requestedAmount", result.Errors!);
        Assert.Contains("currency", result.Errors!);
        Assert.Contains("idempotencyKey", result.Errors!);
        Assert.Equal(0, repository.CreateCalls);
    }

    [Theory]
    [InlineData("etag-conflict", FundingApplicationOutcome.PreconditionFailed)]
    [InlineData("already-exists", FundingApplicationOutcome.Conflict)]
    [InlineData("idempotency-conflict", FundingApplicationOutcome.IdempotencyConflict)]
    [InlineData("not-found", FundingApplicationOutcome.NotFound)]
    public async Task Database_codes_map_to_stable_safe_outcomes(
        string code,
        FundingApplicationOutcome expected)
    {
        var repository = new FakeFundingApplicationRepository
        {
            Mutation = Mutation(succeeded: false, code)
        };
        var service = new FundingApplicationService(repository);

        var result = await service.UpdateAsync(
            UserId,
            OrganizationId,
            ApplicationId,
            new byte[8],
            ValidData(),
            CancellationToken.None);

        Assert.Equal(expected, result.Outcome);
        Assert.Equal(0, repository.GetCalls);
    }

    [Fact]
    public async Task Foreign_tenant_is_an_indistinguishable_not_found()
    {
        var repository = new FakeFundingApplicationRepository
        {
            ThrowNotFound = true
        };
        var service = new FundingApplicationService(repository);

        var result = await service.ListAsync(
            UserId,
            OrganizationId,
            new FundingApplicationListFilters(null, null, null, 1, 20),
            CancellationToken.None);

        Assert.Equal(FundingApplicationOutcome.NotFound, result.Outcome);
        Assert.Null(result.Errors);
    }

    [Fact]
    public async Task Calendar_allows_366_inclusive_days_and_rejects_more()
    {
        var repository = new FakeFundingApplicationRepository();
        var service = new FundingApplicationService(repository);
        var from = new DateOnly(2026, 1, 1);

        var accepted = await service.ListCalendarAsync(
            UserId,
            OrganizationId,
            from,
            from.AddDays(365),
            CancellationToken.None);
        var rejected = await service.ListCalendarAsync(
            UserId,
            OrganizationId,
            from,
            from.AddDays(366),
            CancellationToken.None);

        Assert.Equal(FundingApplicationOutcome.Success, accepted.Outcome);
        Assert.Equal(FundingApplicationOutcome.ValidationFailed, rejected.Outcome);
        Assert.Equal(1, repository.CalendarCalls);
    }

    private static FundingApplicationData ValidData() => new(
        FundingApplicationStatus.Applying,
        "En preparación",
        new DateOnly(2026, 9, 1),
        1000,
        "USD",
        null);

    private static FundingApplicationDetails Details() => new(
        ApplicationId,
        new FundingApplicationReference(ProjectId, "proyecto", "Proyecto"),
        new FundingApplicationOpportunityReference(
            OpportunityId,
            "fondo",
            "Fondo",
            "Patrocinador",
            new DateOnly(2026, 12, 1),
            null,
            1),
        FundingApplicationStatus.Interested,
        "nota",
        null,
        null,
        null,
        null,
        UserId,
        true,
        new DateTimeOffset(2026, 8, 24, 12, 0, 0, TimeSpan.Zero),
        new DateTimeOffset(2026, 8, 24, 12, 0, 0, TimeSpan.Zero),
        new byte[8]);

    private static FundingApplicationMutation Mutation(
        bool succeeded,
        string code,
        bool wasReplay = false) => new(
            succeeded,
            code,
            ApplicationId,
            FundingApplicationStatus.Interested,
            UserId,
            new byte[8],
            new DateTimeOffset(2026, 8, 24, 12, 0, 0, TimeSpan.Zero),
            new DateTimeOffset(2026, 8, 24, 12, 0, 0, TimeSpan.Zero),
            wasReplay);

    private sealed class FakeFundingApplicationRepository : IFundingApplicationRepository
    {
        public bool ThrowNotFound { get; init; }
        public FundingApplicationDetails? Details { get; init; }
        public FundingApplicationMutation Mutation { get; init; } =
            FundingApplicationServiceTests.Mutation(true, "created");
        public FundingApplicationData? LastApplication { get; private set; }
        public byte[]? LastIdempotencyHash { get; private set; }
        public byte[]? LastRequestHash { get; private set; }
        public int CreateCalls { get; private set; }
        public int GetCalls { get; private set; }
        public int CalendarCalls { get; private set; }

        public Task<FundingApplicationPage> ListAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            FundingApplicationListFilters filters,
            CancellationToken cancellationToken)
        {
            if (ThrowNotFound)
            {
                throw new FundingApplicationDataException("list", 52101, new Exception());
            }

            return Task.FromResult(new FundingApplicationPage(
                [], 0, filters.PageNumber, filters.PageSize));
        }

        public Task<FundingApplicationDetails?> GetAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid fundingApplicationPublicId,
            CancellationToken cancellationToken)
        {
            GetCalls++;
            return Task.FromResult(Details);
        }

        public Task<FundingApplicationMutation> CreateAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid projectPublicId,
            Guid fundingOpportunityPublicId,
            FundingApplicationData application,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            CancellationToken cancellationToken)
        {
            CreateCalls++;
            LastApplication = application;
            LastIdempotencyHash = idempotencyKeyHash;
            LastRequestHash = requestHash;
            return Task.FromResult(Mutation);
        }

        public Task<FundingApplicationMutation> UpdateAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            Guid fundingApplicationPublicId,
            byte[] expectedRowVersion,
            FundingApplicationData application,
            CancellationToken cancellationToken)
        {
            LastApplication = application;
            return Task.FromResult(Mutation);
        }

        public Task<IReadOnlyList<FundingCalendarItem>> ListCalendarAsync(
            Guid userPublicId,
            Guid organizationPublicId,
            DateOnly from,
            DateOnly to,
            CancellationToken cancellationToken)
        {
            CalendarCalls++;
            return Task.FromResult<IReadOnlyList<FundingCalendarItem>>([]);
        }
    }
}
