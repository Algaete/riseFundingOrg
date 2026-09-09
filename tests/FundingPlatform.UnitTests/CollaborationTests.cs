using FundingPlatform.Application.Collaboration;
using FundingPlatform.Core.Collaboration;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class CollaborationTests
{
    [Fact]
    public void Migration_parses_and_keeps_access_replay_and_audit_guards()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root).Single(s => s.Sequence == 43);
        foreach (var batch in migration.Batches)
        {
            using var reader = new StringReader(batch);
            _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(reader, out var errors);
            Assert.True(errors.Count == 0, string.Join("; ", errors.Select(e => $"{e.Line}:{e.Message}")));
        }
        var sql = string.Join("\n", migration.Batches);
        var smoke = SqlScriptCatalog.DiscoverTests(root).Single(s => s.Sequence == 43);
        foreach (var batch in smoke.Batches)
        {
            using var reader = new StringReader(batch);
            _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(reader, out var errors);
            Assert.True(errors.Count == 0, string.Join("; ", errors.Select(e => $"{e.Line}:{e.Message}")));
        }
        Assert.DoesNotContain("GRANT SELECT", sql);
        Assert.DoesNotContain("ALTER ROLE", sql);
        Assert.DoesNotContain("EXECUTE AS", sql);
        Assert.Contains("FundingPlatform_ifn_ProjectMarketplaceReady()", sql);
        Assert.Contains("profiles.IsDiscoverable = 1 AND profiles.AllowsInvitations = 1", sql);
        Assert.Contains("requests.Status = 4", sql);
        Assert.Contains("@Roster = 1 AND participants.Status = 1", sql);
        Assert.Contains("CASE WHEN @Manage = 1 OR recipient.IsRecipient = 1 THEN participants.Message ELSE N'' END", sql);
        foreach (var name in new[] { "ProfessionalProfile_Save", "Consortium_Create", "Consortium_Update", "Consortium_Invite", "Consortium_ParticipantAction" })
        {
            var command = migration.Batches.Single(b => b.Contains($"CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_{name}\n"));
            Assert.Contains("BEGIN TRANSACTION", command);
            Assert.Contains("ROLLBACK TRANSACTION", command);
            Assert.Contains("INSERT INTO dbo.FundingPlatform_CollaborationEvents", command);
            Assert.True(command.IndexOf("EXEC dbo.FundingPlatform_usp_Collaboration_User", StringComparison.Ordinal)
                < command.IndexOf("EXEC dbo.FundingPlatform_usp_Collaboration_Replay", StringComparison.Ordinal));
            if (name != "Consortium_Create") Assert.Contains("@ExpectedRowVersion", command);
        }
    }

    [Theory]
    [InlineData(0, 1, 0, false)]
    [InlineData(0, 1, 1, true)]
    [InlineData(1, 0, 1, false)]
    [InlineData(0, 2, 0, true)]
    [InlineData(1, 2, 1, true)]
    [InlineData(2, 2, 1, false)]
    [InlineData(2, 0, 1, false)]
    [InlineData(8, 1, 1, false)]
    public void Consortium_state_transitions_require_acceptance_and_closed_is_terminal(int current, int next, int accepted, bool allowed)
        => Assert.Equal(allowed, ConsortiumStateMachine.CanTransition((ConsortiumStatus)current, (ConsortiumStatus)next, accepted));

    [Theory]
    [InlineData(0, 1, true, false, false, false)]
    [InlineData(0, 1, false, true, false, true)]
    [InlineData(0, 1, false, true, true, false)]
    [InlineData(0, 2, false, true, false, true)]
    [InlineData(0, 3, true, false, false, true)]
    [InlineData(0, 3, false, true, false, false)]
    [InlineData(1, 4, false, true, true, true)]
    [InlineData(1, 5, true, false, false, true)]
    [InlineData(1, 5, false, true, false, false)]
    [InlineData(4, 1, false, true, false, false)]
    [InlineData(1, 1, true, true, false, false)]
    public void Participant_actions_never_substitute_coordinator_for_recipient(int current, int next, bool manager, bool recipient, bool closed, bool allowed)
        => Assert.Equal(allowed, ConsortiumStateMachine.CanAct((ConsortiumParticipantStatus)current, (ConsortiumParticipantStatus)next, manager, recipient, closed));

    [Fact]
    public void Optional_profile_fields_and_private_defaults_are_valid()
    {
        var profile = CollaborationRules.Normalize(new("Nombre", "Ingeniería", null, null, null, null, null));
        Assert.Empty(CollaborationRules.Validate(profile));
        Assert.False(profile.IsDiscoverable); Assert.False(profile.AllowsInvitations);
        Assert.Empty(profile.Skills!);
        Assert.NotEmpty(CollaborationRules.Validate(profile with { AllowsInvitations = true }));
        Assert.NotEmpty(CollaborationRules.Validate(profile with { Skills = Enumerable.Repeat("skill", 21).ToArray() }));
        Assert.NotEmpty(CollaborationRules.Validate(profile with { Biography = new string('a', 2001) }));
    }

    [Theory]
    [InlineData("Escribe a contacto@example.invalid")]
    [InlineData("Consulta HTTPS://example.invalid")]
    [InlineData("Consulta www.example.invalid")]
    [InlineData("Mi teléfono es 12345678")]
    [InlineData("Corto")]
    public void Invitations_reject_contact_payloads_or_insufficient_context(string message)
        => Assert.NotEmpty(CollaborationRules.ValidateInvitation(new(ConsortiumParticipantKind.Professional, Guid.NewGuid(), "Ingeniería", message)));

    [Theory]
    [InlineData(0, 20, false)]
    [InlineData(1, 51, false)]
    [InlineData(10001, 20, false)]
    [InlineData(10000, 50, true)]
    public void Pagination_is_bounded(int page, int size, bool valid) => Assert.Equal(valid, CollaborationRules.ValidPage(page, size));

    [Fact]
    public async Task Profile_service_normalizes_and_hashes_actor_version_and_payload()
    {
        var repo = new ProfileRepository();
        var service = new ProfessionalProfileService(repo);
        var actor = Guid.NewGuid();
        var input = new ProfessionalProfileData("  Nombre  ", "  Especialidad ", " ", null, ["SQL", "sql", "GIS"], [2, 1, 2], [1, 1]);
        await service.SaveAsync(actor, input, null, "collaboration-test-0001", default);
        Assert.Equal("Nombre", repo.Data!.DisplayName);
        Assert.Null(repo.Data.Biography);
        Assert.Equal(["GIS", "SQL"], repo.Data.Skills);
        Assert.Equal(new short[] { 1, 2 }, repo.Data.LanguageIds);
        Assert.Equal(32, repo.Key!.Length);
        var hash = repo.Hash;
        await service.SaveAsync(actor, input, null, "collaboration-test-0001", default);
        Assert.Equal(hash, repo.Hash);
        await service.SaveAsync(Guid.NewGuid(), input, null, "collaboration-test-0001", default);
        Assert.NotEqual(hash, repo.Hash);
        await Assert.ThrowsAsync<ArgumentException>(() => service.SaveAsync(actor, input, new byte[7], "collaboration-test-0001", default));
    }
    private sealed class ProfileRepository : IProfessionalProfileRepository
    {
        public ProfessionalProfileData? Data; public byte[]? Hash; public byte[]? Key;
        public Task<ProfessionalProfile?> GetOwnAsync(Guid userId, CancellationToken token) => Task.FromResult<ProfessionalProfile?>(null);
        public Task<CollaborationPage<ProfessionalDirectoryEntry>> SearchAsync(Guid userId, ProfessionalDirectoryFilters filters, CancellationToken token) => throw new NotSupportedException();
        public Task<CollaborationWriteResult> SaveAsync(Guid userId, ProfessionalProfileData data, byte[]? expected, byte[] keyHash, byte[] requestHash, CancellationToken token)
        {
            Data = data; Hash = requestHash; Key = keyHash;
            return Task.FromResult(new CollaborationWriteResult(Guid.NewGuid(), "\"0102030405060708\"", false));
        }
    }
}
