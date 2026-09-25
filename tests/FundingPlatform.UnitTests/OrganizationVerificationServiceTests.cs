using System.Text.Json;
using FundingPlatform.Application.Organizations;
using FundingPlatform.Core.Organizations;

namespace FundingPlatform.UnitTests;

public sealed class OrganizationVerificationServiceTests
{
    private static readonly Guid Admin = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid Organization = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(2)]
    public async Task Every_decision_requires_trimmed_reason_and_both_versions(int status)
    {
        var repository = new FakeRepository();
        var service = new OrganizationVerificationService(repository);
        var result = await service.DecideAsync(Admin, Organization,
            new(status, "  Identidad y antecedentes revisados.  ", 0, 4), CancellationToken.None);

        Assert.Null(result.Errors);
        Assert.NotNull(result.Verification);
        Assert.Equal(Admin, repository.Actor);
        Assert.Equal(Organization, repository.OrganizationId);
        Assert.Equal(new(status, "Identidad y antecedentes revisados.", 0, 4), repository.Decision);
        Assert.Equal(1, repository.Writes);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("     ")]
    [InlineData("abcd")]
    [InlineData("  abcd  ")]
    public async Task Rejects_missing_or_short_reason_without_database_write(string? reason)
    {
        var repository = new FakeRepository();
        var result = await new OrganizationVerificationService(repository).DecideAsync(Admin,
            Organization, new(1, reason, 0, 1), CancellationToken.None);
        Assert.Null(result.Verification);
        Assert.True(result.Errors?.ContainsKey("reason"));
        Assert.Equal("organization-verification-reason", result.Errors!.Issues["reason"][0].Code);
        Assert.Equal(0, repository.Writes);
    }

    [Theory]
    [InlineData(5, true)]
    [InlineData(2000, true)]
    [InlineData(2001, false)]
    public async Task Reason_bounds_apply_after_trimming(int length, bool valid)
    {
        var repository = new FakeRepository();
        var result = await new OrganizationVerificationService(repository).DecideAsync(Admin,
            Organization, new(2, "  " + new string('a', length) + "  ", 0, 4), CancellationToken.None);
        Assert.Equal(valid, result.Errors is null);
        Assert.Equal(valid ? 1 : 0, repository.Writes);
    }

    [Theory]
    [InlineData(-1, 0, 1, "status")]
    [InlineData(3, 0, 1, "status")]
    [InlineData(1, -1, 1, "expectedRevision")]
    [InlineData(1, int.MaxValue, 1, "expectedRevision")]
    [InlineData(1, 0, 0, "expectedProfileVersion")]
    [InlineData(1, 0, -1, "expectedProfileVersion")]
    public async Task Rejects_invalid_decision_or_versions(int status, int revision, int profileVersion, string field)
    {
        var repository = new FakeRepository();
        var result = await new OrganizationVerificationService(repository).DecideAsync(Admin,
            Organization, new(status, "Revisión manual.", revision, profileVersion), CancellationToken.None);
        Assert.True(result.Errors?.ContainsKey(field));
        Assert.Equal(0, repository.Writes);
    }

    [Theory]
    [InlineData(1, 4, 4, 1, false)]
    [InlineData(2, 4, 4, 2, false)]
    [InlineData(1, 4, 5, 0, true)]
    [InlineData(2, 4, 5, 0, true)]
    [InlineData(1, null, 5, 0, true)]
    [InlineData(0, 4, 5, 0, false)]
    [InlineData(0, null, 5, 0, false)]
    public async Task Profile_changes_require_new_review_without_losing_recorded_status(
        byte recordedStatus, int? reviewedVersion, int profileVersion, byte effectiveStatus, bool stale)
    {
        var repository = new FakeRepository
        {
            Snapshot = Snapshot() with { Status = recordedStatus, RecordedStatus = recordedStatus,
                ProfileVersion = profileVersion, ReviewedProfileVersion = reviewedVersion }
        };
        var result = await new OrganizationVerificationService(repository).GetAsync(Admin,
            Organization, CancellationToken.None);
        Assert.NotNull(result);
        Assert.Equal(effectiveStatus, result.Status);
        Assert.Equal(recordedStatus, result.RecordedStatus);
        Assert.Equal(stale, result.NeedsReverification);
    }

    [Fact]
    public async Task Missing_organization_stays_null()
    {
        var repository = new FakeRepository { Snapshot = null };
        Assert.Null(await new OrganizationVerificationService(repository).GetAsync(Admin,
            Organization, CancellationToken.None));
    }

    [Fact]
    public void Null_SQL_history_is_normalized_to_empty_collection()
    {
        var json = """
            {"organizationPublicId":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","name":"Prueba",
             "status":0,"recordedStatus":0,"revision":0,"profileVersion":1,"history":null}
            """;
        var verification = JsonSerializer.Deserialize<OrganizationVerification>(json,
            new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Assert.NotNull(verification);
        Assert.Empty(verification.History);
    }

    [Fact]
    public async Task Conflict_does_not_retry_or_overwrite_decision()
    {
        var repository = new FakeRepository { FailureNumber = 56302 };
        var exception = await Assert.ThrowsAsync<OrganizationVerificationDataException>(() =>
            new OrganizationVerificationService(repository).DecideAsync(Admin,
                Organization, new(1, "Revisión manual.", 0, 4), CancellationToken.None));
        Assert.Equal(56302, exception.DatabaseErrorNumber);
        Assert.Equal(1, repository.Writes);
    }

    private static OrganizationVerification Snapshot() => new(Organization, "Organización de prueba",
        0, 0, 0, 4, null, null, null, null, null, false, []);

    private sealed class FakeRepository : IOrganizationVerificationRepository
    {
        public Guid Actor { get; private set; }
        public Guid OrganizationId { get; private set; }
        public int Writes { get; private set; }
        public OrganizationVerificationDecision? Decision { get; private set; }
        public OrganizationVerification? Snapshot { get; init; } = OrganizationVerificationServiceTests.Snapshot();
        public int? FailureNumber { get; init; }

        public Task<OrganizationVerification?> GetAsync(Guid adminUserPublicId,
            Guid organizationPublicId, CancellationToken cancellationToken) => Task.FromResult(Snapshot);

        public Task<OrganizationVerification> DecideAsync(Guid adminUserPublicId,
            Guid organizationPublicId, OrganizationVerificationDecision decision, CancellationToken cancellationToken)
        {
            Writes++;
            Actor = adminUserPublicId;
            OrganizationId = organizationPublicId;
            Decision = decision;
            if (FailureNumber is { } number)
                throw new OrganizationVerificationDataException(number, new InvalidOperationException("Private SQL details"));
            return Task.FromResult(Snapshot!);
        }
    }
}
