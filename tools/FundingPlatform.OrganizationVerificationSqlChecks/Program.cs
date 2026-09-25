using System.Data;
using Dapper;
using FundingPlatform.Application.Organizations;
using FundingPlatform.Core.Organizations;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using FundingPlatform.Infrastructure.Persistence.Organizations;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

// Deliberately does not load .env or accept a cloud target. Synthetic committed fixtures
// are needed for two-connection races; use only a disposable, dedicated local server.
if (args.Length != 1 || args[0] is not ("--prepare" or "--verify") ||
    Environment.GetEnvironmentVariable("RF_ORG_SQL_TEST_CONFIRMATION") != "DISPOSABLE-LOCAL-SQL")
    return 64;
var connectionString = Environment.GetEnvironmentVariable("RF_ORG_SQL_TEST_CONNECTION");
var settings = new SqlConnectionStringBuilder(connectionString ?? "");
if (settings.DataSource is not ("127.0.0.1,14363" or "tcp:127.0.0.1,14363") ||
    settings.InitialCatalog != "res" || settings.IntegratedSecurity ||
    settings.Authentication != SqlAuthenticationMethod.NotSpecified)
    return 64;
var factory = new SqlConnectionFactory(new ConfigurationBuilder().AddInMemoryCollection(
    new Dictionary<string, string?> { [SqlConnectionFactory.ConfigurationKey] = connectionString }).Build());
try
{
    var root = SolutionRootLocator.Find();
    if (args[0] == "--prepare")
    {
        var master = new SqlConnectionStringBuilder(settings.ConnectionString) { InitialCatalog = "master" };
        await using (var server = new SqlConnection(master.ConnectionString))
        {
            await server.OpenAsync();
            await server.ExecuteAsync("IF DB_ID(N'res') IS NULL CREATE DATABASE res;");
        }
        var migrations = SqlScriptCatalog.DiscoverMigrations(root);
        var runner = new DatabaseMigrationRunner(factory, reportProgress: Console.WriteLine);
        // Reproduce the deployed SQL062 baseline before testing the pending SQL063.
        // Historical migrations are applied unchanged, never mocked or skipped.
        var status = await runner.GetStatusAsync(migrations);
        if (!status.Migrations.Any(x => x.Version == 63 && x.State == MigrationState.Applied))
        {
            var baseline = await runner.ApplyAsync(migrations.Where(x => x.Sequence < 63).ToArray());
            Console.WriteLine($"LOCAL baseline through SQL062: {baseline.ExecutedScripts} migrations applied.");
        }
        var preflight = await runner.PreflightAsync(migrations, SqlScriptCatalog.DiscoverTests(root));
        Console.WriteLine($"LOCAL preflight: {preflight.Migrations.ExecutedScripts} migrations, {preflight.Tests.ExecutedScripts} smokes, rolled back.");
        var first = await runner.ApplyAsync(migrations);
        var second = await runner.ApplyAsync(migrations);
        if (second.ExecutedScripts != 0) throw new InvalidOperationException("reapply_not_idempotent");
        var tests = await runner.TestAsync(migrations, SqlScriptCatalog.DiscoverTests(root));
        Console.WriteLine($"LOCAL apply: {first.ExecutedScripts}; reapply: 0; smokes: {tests.ExecutedScripts}.");
        return 0;
    }
    await new VerificationChecks(factory).RunAsync();
    return 0;
}
catch (SqlException error)
{
    Console.Error.WriteLine($"Local SQL check failed: {error.Number}, line {error.LineNumber}.");
    return 1;
}
catch (MigrationException error)
{
    Console.Error.WriteLine($"Local migration check failed: {error.Code}, {error.Item}, SQL {error.DatabaseErrorNumber}.");
    return 1;
}
catch (Exception error) when (error is InvalidOperationException or OrganizationVerificationDataException)
{
    Console.Error.WriteLine($"Local contract check failed: {error.GetType().Name}; {error.Message}");
    return 1;
}

sealed class VerificationChecks(SqlConnectionFactory factory)
{
    private readonly Guid actor = Guid.NewGuid();
    private readonly Guid organization = Guid.NewGuid();
    private readonly SqlOrganizationVerificationRepository repository = new(factory);
    private int passed;
    private const string ApiUser = "RF_OrgVerifyApiTest";
    private const string WorkerUser = "RF_OrgVerifyWorkerTest";

    public async Task RunAsync()
    {
        await using var connection = factory.CreateConnection();
        await connection.OpenAsync();
        try
        {
            await connection.ExecuteAsync("""
                INSERT dbo.FundingPlatform_Users
                    (PublicId,Email,NormalizedEmail,DisplayName,PasswordHash,SecurityStamp,EmailConfirmed,Status,PreferredLocale,TwoFactorEnabled)
                VALUES (@Actor, @Email, UPPER(@Email), N'Synthetic SQL reviewer', N'not-a-credential', CONVERT(nvarchar(36),@Actor),1,2,N'es-CL',1);
                DECLARE @ActorId bigint = SCOPE_IDENTITY();
                INSERT dbo.FundingPlatform_UserRoles(UserId,RoleId)
                    SELECT @ActorId,Id FROM dbo.FundingPlatform_Roles WHERE NormalizedName=N'ADMIN';
                INSERT dbo.FundingPlatform_Organizations
                    (PublicId,CreatedByUserId,Name,HomeCountryId,OrganizationTypeId,ProfileStatus,ProfileCompleteness)
                SELECT @Organization,@ActorId,@Email,152,MIN(Id),2,100 FROM dbo.FundingPlatform_OrganizationTypes WHERE IsActive=1;
                CREATE USER RF_OrgVerifyApiTest WITHOUT LOGIN;
                ALTER ROLE FundingPlatform_ApiRuntimeRole ADD MEMBER RF_OrgVerifyApiTest;
                CREATE USER RF_OrgVerifyWorkerTest WITHOUT LOGIN;
                ALTER ROLE FundingPlatform_GeneralWorkerRole ADD MEMBER RF_OrgVerifyWorkerTest;
                """, new { Actor = actor, Organization = organization, Email = $"orgverify-{actor:N}@example.invalid" });
            var initial = await Get();
            Check(initial.Revision == 0 && initial.Status == 0 && initial.History.Count == 0, "complete profile starts pending; repository JSON contract");
            Check(await repository.GetAsync(actor, Guid.NewGuid(), default) is null, "missing organization is null");
            await Expect(56301, () => repository.DecideAsync(actor, Guid.NewGuid(), Decision(0, 1), default), "missing decision target");
            await Expect(56303, () => repository.DecideAsync(actor, organization, Decision(0, 1) with { Reason = "short" + new string('x', 2000) }, default), "oversized reason is not silently truncated");
            await Expect(56302, () => Decide(1, 1), "stale revision");
            await Expect(56302, () => Decide(0, 2), "stale profile");
            Check((await Get()).Revision == 0, "rejected writes leave no history");

            // Hold the first decision uncommitted, then prove the competing connection
            // is waiting on THIS session before committing. No timing-only race assertion.
            await using (var first = factory.CreateConnection())
            {
                await first.OpenAsync();
                await using var transaction = (SqlTransaction)await first.BeginTransactionAsync();
                var firstId = await first.ExecuteScalarAsync<int>("SELECT @@SPID", transaction: transaction);
                await first.QuerySingleAsync<string>(new CommandDefinition(
                    "dbo.FundingPlatform_usp_OrganizationVerification_Decide", Parameters(0, 1), transaction,
                    commandType: CommandType.StoredProcedure));
                var contender = Decide(0, 1);
                await WaitBlocked(connection, firstId);
                await transaction.CommitAsync();
                await Expect(56302, () => contender, "concurrent reviewer cannot overwrite winner");
            }
            var approved = await Get();
            Check(approved.Revision == 1 && approved.History.Count == 1 && approved.ReviewedByUserPublicId == actor,
                "one attributed decision after concurrent review");
            Check(approved.ReviewedAtUtc?.Offset == TimeSpan.Zero, "timestamps deserialize as UTC");

            await using (var editor = factory.CreateConnection())
            {
                await editor.OpenAsync();
                await using var transaction = (SqlTransaction)await editor.BeginTransactionAsync();
                var editorId = await editor.ExecuteScalarAsync<int>("SELECT @@SPID", transaction: transaction);
                await editor.ExecuteAsync("UPDATE dbo.FundingPlatform_Organizations SET ProfileVersion=ProfileVersion+1 WHERE PublicId=@Organization",
                    new { Organization = organization }, transaction);
                var staleReview = Decide(1, 1);
                await WaitBlocked(connection, editorId);
                await transaction.CommitAsync();
                await Expect(56302, () => staleReview, "concurrent profile edit invalidates submitted version");
            }
            var changed = await Get();
            Check(changed.Status == 0 && changed.RecordedStatus == 1 && changed.NeedsReverification && changed.History.Count == 1,
                "profile update invalidates effective decision and preserves history");

            await connection.ExecuteAsync("UPDATE dbo.FundingPlatform_Users SET TwoFactorEnabled=0 WHERE PublicId=@Actor", new { Actor = actor });
            await Expect(51602, async () => { await Get(); }, "SQL read requires current MFA");
            await Expect(51602, () => Decide(1, 2), "SQL write requires current MFA");
            await connection.ExecuteAsync("UPDATE dbo.FundingPlatform_Users SET TwoFactorEnabled=1 WHERE PublicId=@Actor", new { Actor = actor });
            await using (var revoker = factory.CreateConnection())
            {
                await revoker.OpenAsync();
                await using var transaction = (SqlTransaction)await revoker.BeginTransactionAsync();
                var revokerId = await revoker.ExecuteScalarAsync<int>("SELECT @@SPID", transaction: transaction);
                await revoker.ExecuteAsync("DELETE r FROM dbo.FundingPlatform_UserRoles r JOIN dbo.FundingPlatform_Users u ON u.Id=r.UserId WHERE u.PublicId=@Actor",
                    new { Actor = actor }, transaction);
                var revoked = Decide(1, 2);
                await WaitBlocked(connection, revokerId);
                await transaction.CommitAsync();
                await Expect(51601, () => revoked, "concurrent role revocation blocks decision");
            }
            await Expect(51601, async () => { await Get(); }, "SQL read requires current admin role");
            await connection.ExecuteAsync("INSERT dbo.FundingPlatform_UserRoles(UserId,RoleId) SELECT u.Id,r.Id FROM dbo.FundingPlatform_Users u CROSS JOIN dbo.FundingPlatform_Roles r WHERE u.PublicId=@Actor AND r.NormalizedName=N'ADMIN'", new { Actor = actor });

            await CheckPermissions(connection);
            using var results = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_AdminOrganization_List", new { AdminUserPublicId = actor, Query = $"orgverify-{actor:N}", VerificationStatus = 0 },
                commandType: CommandType.StoredProcedure));
            var total = await results.ReadSingleAsync<long>();
            var rows = (await results.ReadAsync()).ToArray();
            Check(total == 1 && rows.Length == 1 && (byte)rows[0].VerificationStatus == 0, "list filter uses effective pending status");
            Check(await connection.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM dbo.FundingPlatform_OrganizationVerificationHistory h JOIN dbo.FundingPlatform_Organizations o ON o.Id=h.OrganizationId WHERE o.PublicId=@Organization", new { Organization = organization }) == 1,
                "all failed decisions preserve the single history row");
            Console.WriteLine($"Organization verification real SQL checks: {passed} passed.");
        }
        finally
        {
            // Exact synthetic identifiers only. Never touches other local rows.
            await connection.ExecuteAsync("""
                DELETE h FROM dbo.FundingPlatform_OrganizationVerificationHistory h JOIN dbo.FundingPlatform_Organizations o ON o.Id=h.OrganizationId WHERE o.PublicId=@Organization;
                DELETE v FROM dbo.FundingPlatform_OrganizationVerifications v JOIN dbo.FundingPlatform_Organizations o ON o.Id=v.OrganizationId WHERE o.PublicId=@Organization;
                DELETE dbo.FundingPlatform_Organizations WHERE PublicId=@Organization;
                DELETE r FROM dbo.FundingPlatform_UserRoles r JOIN dbo.FundingPlatform_Users u ON u.Id=r.UserId WHERE u.PublicId=@Actor;
                DELETE dbo.FundingPlatform_Users WHERE PublicId=@Actor;
                IF USER_ID('RF_OrgVerifyApiTest') IS NOT NULL DROP USER RF_OrgVerifyApiTest;
                IF USER_ID('RF_OrgVerifyWorkerTest') IS NOT NULL DROP USER RF_OrgVerifyWorkerTest;
                """, new { Actor = actor, Organization = organization });
            Console.WriteLine("Exact synthetic fixtures and test users removed.");
        }
    }

    private async Task CheckPermissions(SqlConnection connection)
    {
        foreach (var user in new[] { ApiUser, WorkerUser })
        {
            var permissions = await connection.QuerySingleAsync<Permissions>($"""
                EXECUTE AS USER = '{user}';
                SELECT HAS_PERMS_BY_NAME('dbo.FundingPlatform_usp_OrganizationVerification_Get','OBJECT','EXECUTE') AS CanRead,
                    HAS_PERMS_BY_NAME('dbo.FundingPlatform_usp_OrganizationVerification_Decide','OBJECT','EXECUTE') AS CanDecide,
                    HAS_PERMS_BY_NAME('dbo.FundingPlatform_OrganizationVerifications','OBJECT','SELECT') AS DirectRead,
                    HAS_PERMS_BY_NAME('dbo.FundingPlatform_OrganizationVerificationHistory','OBJECT','UPDATE') AS DirectWrite;
                REVERT;
                """);
            Check(permissions.CanRead == (user == ApiUser ? 1 : 0) && permissions.CanDecide == (user == ApiUser ? 1 : 0) &&
                permissions.DirectRead == 0 && permissions.DirectWrite == 0, $"effective least privileges: {user}");
        }
        var json = await connection.QuerySingleAsync<string>("""
            EXECUTE AS USER='RF_OrgVerifyApiTest';
            EXEC dbo.FundingPlatform_usp_OrganizationVerification_Get @Actor,@Organization;
            REVERT;
            """, new { Actor = actor, Organization = organization });
        Check(json.Contains(organization.ToString(), StringComparison.OrdinalIgnoreCase), "API role executes through ownership chain");
    }

    private static async Task WaitBlocked(SqlConnection observer, int blocker)
    {
        for (var attempt = 0; attempt < 100; attempt++)
        {
            if (await observer.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM sys.dm_exec_requests WHERE blocking_session_id=@Blocker", new { Blocker = blocker }) > 0) return;
            await Task.Delay(50);
        }
        throw new InvalidOperationException("competing_connection_not_observed_waiting");
    }
    private OrganizationVerificationDecision Decision(int revision, int version) => new(1, "Synthetic verification only.", revision, version);
    private object Parameters(int revision, int version) => new { AdminUserPublicId = actor, OrganizationPublicId = organization,
        Status = 1, Reason = "Synthetic verification only.", ExpectedRevision = revision, ExpectedProfileVersion = version };
    private Task<OrganizationVerification> Decide(int revision, int version) => repository.DecideAsync(actor, organization, Decision(revision, version), default);
    private async Task<OrganizationVerification> Get() => await repository.GetAsync(actor, organization, default)
        ?? throw new InvalidOperationException("missing_fixture");
    private async Task Expect(int number, Func<Task> operation, string name)
    {
        try { await operation(); }
        catch (OrganizationVerificationDataException error) when (error.DatabaseErrorNumber == number) { Check(true, name); return; }
        throw new InvalidOperationException($"expected_sql_{number}: {name}");
    }
    private void Check(bool valid, string name)
    {
        if (!valid) throw new InvalidOperationException(name);
        passed++;
        Console.WriteLine($"PASS {passed}: {name}");
    }
    private sealed record Permissions(int CanRead, int CanDecide, int DirectRead, int DirectWrite);
}
