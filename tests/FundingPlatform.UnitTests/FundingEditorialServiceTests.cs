using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.UnitTests;

public sealed class FundingEditorialServiceTests
{
    private static readonly Guid AdminId = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid EntityId = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid FunderId = Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");
    private static readonly byte[] CurrentRowVersion = Convert.FromHexString("0102030405060708");
    private static readonly byte[] NextRowVersion = Convert.FromHexString("A1A2A3A4A5A6A7A8");

    [Theory]
    [InlineData(FundingPublicationStatus.Draft, true)]
    [InlineData(FundingPublicationStatus.PendingReview, false)]
    [InlineData(FundingPublicationStatus.Published, false)]
    [InlineData(FundingPublicationStatus.Rejected, true)]
    [InlineData(FundingPublicationStatus.Archived, false)]
    public void Editorial_state_machine_only_allows_editing_drafts_and_rejections(
        FundingPublicationStatus status,
        bool expected)
    {
        Assert.Equal(expected, FundingEditorialStateMachine.CanEdit(status));
    }

    [Theory]
    [InlineData(FundingPublicationStatus.Draft, false)]
    [InlineData(FundingPublicationStatus.PendingReview, false)]
    [InlineData(FundingPublicationStatus.Published, true)]
    [InlineData(FundingPublicationStatus.Rejected, false)]
    [InlineData(FundingPublicationStatus.Archived, false)]
    public void Editorial_state_machine_only_starts_correction_from_published(
        FundingPublicationStatus status,
        bool expected)
    {
        Assert.Equal(expected, FundingEditorialStateMachine.CanStartCorrection(status));
    }

    [Fact]
    public async Task Funder_create_uses_a_deterministic_slug_and_request_hash_for_retries()
    {
        var repository = new FakeFunderRepository();
        var service = new FunderEditorialService(repository);
        var input = new FunderData(
            "Fundación Acción Ñuble", null, "https://fundacion.example", 56,
            ["Acción Ñuble"]);

        var first = await service.CreateAsync(
            AdminId, input, "funder-create-key-0001", CancellationToken.None);
        var second = await service.CreateAsync(
            AdminId, input, "funder-create-key-0001", CancellationToken.None);

        Assert.Equal(FundingEditorialOutcome.Success, first.Outcome);
        Assert.Equal(FundingEditorialOutcome.Success, second.Outcome);
        Assert.Equal(2, repository.CreateCalls.Count);
        Assert.Equal(repository.CreateCalls[0].Slug, repository.CreateCalls[1].Slug);
        Assert.Equal(repository.CreateCalls[0].IdempotencyHash, repository.CreateCalls[1].IdempotencyHash);
        Assert.Equal(repository.CreateCalls[0].RequestHash, repository.CreateCalls[1].RequestHash);
        Assert.StartsWith("fundacion-accion-nuble-", repository.CreateCalls[0].Slug);
    }

    [Fact]
    public async Task Opportunity_write_requires_an_explicit_unique_primary_funder()
    {
        var repository = new FakeOpportunityEditorialRepository();
        var service = new FundingOpportunityEditorialService(repository, Clock);
        var input = CreateOpportunityData([]);

        var result = await service.CreateAsync(
            AdminId, input, "opportunity-create-0001", CancellationToken.None);

        Assert.Equal(FundingEditorialOutcome.ValidationFailed, result.Outcome);
        Assert.Contains("funders", result.Errors!.Keys);
        Assert.Equal(0, repository.CreateCalls);
    }

    [Fact]
    public async Task Opportunity_write_preserves_all_MVP_relations_and_primary_role()
    {
        var repository = new FakeOpportunityEditorialRepository();
        var service = new FundingOpportunityEditorialService(repository, Clock);
        var input = CreateOpportunityData(
            [new FundingOpportunityFunderLink(FunderId, FunderOpportunityRole.Primary)]);

        var result = await service.CreateAsync(
            AdminId, input, "opportunity-create-0002", CancellationToken.None);

        Assert.Equal(FundingEditorialOutcome.Success, result.Outcome);
        Assert.Equal(1, repository.CreateCalls);
        Assert.Equal([56], repository.LastData!.CountryIds);
        Assert.Equal([10], repository.LastData.CategoryIds);
        Assert.Equal([20], repository.LastData.BeneficiaryTypeIds);
        Assert.Equal([30], repository.LastData.ProjectTypeIds);
        Assert.Equal(FunderOpportunityRole.Primary, repository.LastData.Funders.Single().Role);
        Assert.Equal((short)56, repository.LastData.IssuerCountryId);
        Assert.Equal(FundingAmountStatus.Specified, repository.LastData.AmountStatus);
        Assert.Equal(FundingDeadlineType.Fixed, repository.LastData.DeadlineType);
        Assert.Equal(FundingDeadlinePrecision.Date, repository.LastData.DeadlinePrecision);
        Assert.Equal("Implementación y evaluación.", repository.LastData.AllowedActivities);
        Assert.Equal("No financia proselitismo.", repository.LastData.Restrictions);
        Assert.Equal((short)1, repository.LastData.MinimumOperatingYears);
        Assert.True(repository.LastData.RequiresLegalEntity);
        Assert.False(repository.LastData.RequiresPriorExperience);
        Assert.Equal(0m, repository.LastData.CofundingPercentage);
        Assert.Equal(FundingGeographicScope.Specified, repository.LastData.GeographicScope);
        Assert.Equal(FundingRemoteApplication.Yes, repository.LastData.RemoteApplication);
        Assert.Equal(32, repository.LastContentHash!.Length);
        Assert.Contains("fundacion", repository.LastSnapshotJson, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("allowedActivities", repository.LastSnapshotJson, StringComparison.Ordinal);
        Assert.Contains("cofundingPercentage", repository.LastSnapshotJson, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Reject_requires_a_reason_before_calling_the_repository()
    {
        var repository = new FakeFunderRepository();
        var service = new FunderEditorialService(repository);

        var result = await service.ReviewAsync(
            AdminId, EntityId, FundingReviewDecision.Reject, null,
            CurrentRowVersion, "funder-review-key-01", CancellationToken.None);

        Assert.Equal(FundingEditorialOutcome.ValidationFailed, result.Outcome);
        Assert.Contains("reason", result.Errors!.Keys);
        Assert.Equal(0, repository.ReviewCalls);
    }

    [Fact]
    public async Task Funder_correction_requires_and_normalizes_reason_before_persisting()
    {
        var repository = new FakeFunderRepository();
        var service = new FunderEditorialService(repository);

        var invalid = await service.StartCorrectionAsync(
            AdminId, EntityId, "  x ", CurrentRowVersion,
            "funder-correction-01", CancellationToken.None);
        var valid = await service.StartCorrectionAsync(
            AdminId, EntityId, "  Corregir URL oficial.  ", CurrentRowVersion,
            "funder-correction-02", CancellationToken.None);

        Assert.Equal(FundingEditorialOutcome.ValidationFailed, invalid.Outcome);
        Assert.Equal("El motivo debe tener entre 3 y 1000 caracteres.",
            invalid.Errors!["reason"].Single());
        Assert.Equal(FundingEditorialOutcome.Success, valid.Outcome);
        Assert.Equal("Corregir URL oficial.", repository.LastCorrectionReason);
        Assert.Equal(1, repository.CorrectionCalls);
    }

    [Fact]
    public async Task Opportunity_correction_calls_the_specific_port_and_maps_ETag_as_precondition()
    {
        var repository = new FakeOpportunityEditorialRepository
        {
            CorrectionResult = new FundingEditorialMutation(
                false, "etag-conflict", EntityId, FundingPublicationStatus.Published,
                4, CurrentRowVersion, false, [])
        };
        var service = new FundingOpportunityEditorialService(repository, Clock);

        var result = await service.StartCorrectionAsync(
            AdminId, EntityId, "Actualizar las bases oficiales.", CurrentRowVersion,
            "opportunity-correction-01", CancellationToken.None);

        Assert.Equal(FundingEditorialOutcome.PreconditionFailed, result.Outcome);
        Assert.Equal("Actualizar las bases oficiales.", repository.LastCorrectionReason);
        Assert.Equal(1, repository.CorrectionCalls);
    }

    [Fact]
    public async Task Readiness_issues_are_returned_without_exposing_database_details()
    {
        var repository = new FakeFunderRepository
        {
            RequestResult = new FundingEditorialMutation(
                false,
                "funder-not-ready",
                EntityId,
                FundingPublicationStatus.Draft,
                2,
                CurrentRowVersion,
                false,
                [new FundingReadinessIssue(
                    "website-required", "websiteUrl", "El sitio oficial es obligatorio.")])
        };
        var service = new FunderEditorialService(repository);

        var result = await service.RequestPublicationAsync(
            AdminId, EntityId, CurrentRowVersion,
            "funder-submit-key-01", CancellationToken.None);

        Assert.Equal(FundingEditorialOutcome.NotReady, result.Outcome);
        Assert.Equal("El sitio oficial es obligatorio.", result.Errors!["websiteUrl"].Single());
        Assert.Equal("funder-not-ready", result.Code);
    }

    [Theory]
    [InlineData("source-disabled", FundingEditorialOutcome.ValidationFailed)]
    [InlineData("source-link-conflict", FundingEditorialOutcome.Conflict)]
    public async Task Opportunity_source_failures_are_mapped_to_stable_sanitized_outcomes(
        string code,
        FundingEditorialOutcome expectedOutcome)
    {
        var repository = new FakeOpportunityEditorialRepository
        {
            CreateResult = new FundingEditorialMutation(
                false,
                code,
                EntityId,
                FundingPublicationStatus.Draft,
                0,
                [],
                false,
                [])
        };
        var service = new FundingOpportunityEditorialService(repository, Clock);

        var result = await service.CreateAsync(
            AdminId,
            CreateOpportunityData(
                [new FundingOpportunityFunderLink(FunderId, FunderOpportunityRole.Primary)]),
            "opportunity-source-0001",
            CancellationToken.None);

        Assert.Equal(expectedOutcome, result.Outcome);
        Assert.Equal(code, result.Code);
        if (code == "source-link-conflict")
        {
            Assert.Contains("fundingSourceId", result.Errors!.Keys);
            Assert.Contains("externalId", result.Errors.Keys);
            Assert.Contains("sourceUrl", result.Errors.Keys);
        }
    }

    private static FundingOpportunityEditorialData CreateOpportunityData(
        IReadOnlyList<FundingOpportunityFunderLink> funders) => new(
        "Fondo para innovación social",
        "Apoyo para iniciativas comunitarias.",
        "Convocatoria de demostración editorial.",
        "Fundación Ejemplo",
        "https://fundacion.example",
        "https://fundacion.example/postular",
        funders,
        1,
        "manual-001",
        "https://fundacion.example/fondo",
        56,
        1,
        "USD",
        1_000,
        10_000,
        FundingAmountStatus.Specified,
        new DateOnly(2026, 8, 1),
        new DateOnly(2026, 10, 1),
        null,
        null,
        FundingDeadlineType.Fixed,
        FundingDeadlinePrecision.Date,
        "Organizaciones sin fines de lucro.",
        "Formulario y presupuesto.",
        "Fortalecer el impacto social.",
        "Implementación y evaluación.",
        null,
        "No financia proselitismo.",
        "Fundaciones y corporaciones.",
        "Comunidades vulnerables.",
        1,
        true,
        false,
        false,
        0,
        FundingGeographicScope.Specified,
        FundingRemoteApplication.Yes,
        new DateTimeOffset(2026, 8, 21, 12, 0, 0, TimeSpan.Zero),
        [56],
        [1310],
        [10],
        [20],
        [30]);

    private static readonly TimeProvider Clock = new FixedTimeProvider(
        new DateTimeOffset(2026, 8, 21, 13, 0, 0, TimeSpan.Zero));

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private sealed class FakeFunderRepository : IFunderRepository
    {
        public List<(string Slug, byte[] IdempotencyHash, byte[] RequestHash)> CreateCalls { get; } = [];
        public int ReviewCalls { get; private set; }
        public int CorrectionCalls { get; private set; }
        public string? LastCorrectionReason { get; private set; }
        public FundingEditorialMutation? RequestResult { get; init; }

        public Task<FundingEditorialMutation> CreateAsync(
            Guid adminUserPublicId,
            string slug,
            FunderData data,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            CancellationToken cancellationToken)
        {
            CreateCalls.Add((slug, [.. idempotencyKeyHash], [.. requestHash]));
            return Task.FromResult(Success(EntityId));
        }

        public Task<FundingEditorialMutation> RequestPublicationAsync(
            Guid adminUserPublicId,
            Guid funderPublicId,
            byte[] expectedRowVersion,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            CancellationToken cancellationToken) =>
            Task.FromResult(RequestResult ?? Success(funderPublicId));

        public Task<FundingEditorialMutation> ReviewAsync(
            Guid adminUserPublicId,
            Guid funderPublicId,
            FundingReviewDecision decision,
            string? reason,
            byte[] expectedRowVersion,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            CancellationToken cancellationToken)
        {
            ReviewCalls++;
            return Task.FromResult(Success(funderPublicId));
        }

        public Task<FundingEditorialMutation> StartCorrectionAsync(
            Guid adminUserPublicId, Guid funderPublicId, string reason,
            byte[] expectedRowVersion, byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken)
        {
            CorrectionCalls++;
            LastCorrectionReason = reason;
            return Task.FromResult(Success(funderPublicId));
        }

        public Task<FunderPage> ListAdminAsync(Guid adminUserPublicId, string? query,
            FundingPublicationStatus? publicationStatus, bool includeInactive, int pageNumber,
            int pageSize, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<FunderDetails?> GetAdminAsync(Guid adminUserPublicId, Guid funderPublicId,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<FundingEditorialMutation> UpdateAsync(Guid adminUserPublicId,
            Guid funderPublicId, byte[] expectedRowVersion, FunderData data,
            byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<FundingEditorialMutation> DeactivateAsync(Guid adminUserPublicId,
            Guid funderPublicId, string? reason, byte[] expectedRowVersion,
            byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<PublicFunderPage> ListPublishedAsync(string? query, int pageNumber,
            int pageSize, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<PublicFunderDetails?> GetPublishedBySlugAsync(string slug,
            CancellationToken cancellationToken) => throw new NotSupportedException();
    }

    private sealed class FakeOpportunityEditorialRepository : IFundingOpportunityEditorialRepository
    {
        public int CreateCalls { get; private set; }
        public FundingOpportunityEditorialData? LastData { get; private set; }
        public string? LastSnapshotJson { get; private set; }
        public byte[]? LastContentHash { get; private set; }
        public FundingEditorialMutation? CreateResult { get; init; }
        public FundingEditorialMutation? CorrectionResult { get; init; }
        public int CorrectionCalls { get; private set; }
        public string? LastCorrectionReason { get; private set; }

        public Task<FundingEditorialMutation> CreateAsync(
            Guid adminUserPublicId,
            string slug,
            FundingOpportunityEditorialData data,
            string snapshotJson,
            byte[] contentHash,
            decimal dataQualityScore,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            CancellationToken cancellationToken)
        {
            CreateCalls++;
            LastData = data;
            LastSnapshotJson = snapshotJson;
            LastContentHash = [.. contentHash];
            return Task.FromResult(CreateResult ?? Success(EntityId));
        }

        public Task<FundingOpportunityAdminPage> ListAdminAsync(Guid adminUserPublicId,
            string? query, FundingPublicationStatus? publicationStatus, bool includeInactive,
            int pageNumber, int pageSize,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<FundingOpportunityAdminDetails?> GetAdminAsync(Guid adminUserPublicId,
            Guid opportunityPublicId,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<FundingEditorialMutation> UpdateAsync(Guid adminUserPublicId,
            Guid opportunityPublicId, byte[] expectedRowVersion,
            FundingOpportunityEditorialData data, string snapshotJson, byte[] contentHash,
            decimal dataQualityScore, byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<FundingEditorialMutation> RequestPublicationAsync(Guid adminUserPublicId,
            Guid opportunityPublicId, byte[] expectedRowVersion, byte[] idempotencyKeyHash,
            byte[] requestHash, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<FundingEditorialMutation> ReviewAsync(Guid adminUserPublicId,
            Guid opportunityPublicId, FundingReviewDecision decision, string? reason,
            byte[] expectedRowVersion, byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<FundingEditorialMutation> StartCorrectionAsync(Guid adminUserPublicId,
            Guid opportunityPublicId, string reason, byte[] expectedRowVersion,
            byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken)
        {
            CorrectionCalls++;
            LastCorrectionReason = reason;
            return Task.FromResult(CorrectionResult ?? Success(opportunityPublicId));
        }
        public Task<FundingEditorialMutation> DeactivateAsync(Guid adminUserPublicId,
            Guid opportunityPublicId, string? reason, byte[] expectedRowVersion,
            byte[] idempotencyKeyHash, byte[] requestHash,
            CancellationToken cancellationToken) => throw new NotSupportedException();
    }

    private static FundingEditorialMutation Success(Guid entityId) => new(
        true,
        "created",
        entityId,
        FundingPublicationStatus.Draft,
        1,
        NextRowVersion,
        false,
        []);
}
