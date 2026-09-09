using System.Reflection;
using Dapper;
using FundingPlatform.Infrastructure.Persistence.FundingOpportunities;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class FunderWorkspaceTests
{
    [Theory]
    [InlineData("Funder")]
    [InlineData("FundingOpportunity")]
    public void Every_owner_command_rechecks_access_inside_its_transaction_and_lists_filter_both_results(string entity)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root).Single(s => s.Sequence == 42);
        foreach (var action in new[] { "Create", "Update", "RequestPublication", "StartCorrection", "Deactivate" })
        {
            var batch = migration.Batches.Single(b => b.Contains($"CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_{entity}_{action}\n", StringComparison.Ordinal));
            Assert.Equal(2, System.Text.RegularExpressions.Regex.Matches(batch, "EXEC dbo.FundingPlatform_usp_FunderWorkspace_Assert").Count);
            Assert.Contains("EXEC dbo.FundingPlatform_usp_AdminActor_Lock", batch);
            Assert.Contains("BEGIN TRANSACTION", batch);
            Assert.Contains("ROLLBACK TRANSACTION", batch);
        }
        var list = migration.Batches.Single(b => b.Contains($"CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_{entity}_Admin_List\n", StringComparison.Ordinal));
        Assert.Equal(2, System.Text.RegularExpressions.Regex.Matches(list, "owners.UserId = @WorkspaceActorUserId").Count);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void Repository_scope_is_explicit_and_owner_review_fails_closed(bool funder)
    {
        object owner = funder ? new SqlFunderRepository(new NoConnection(), true) : new SqlFundingOpportunityEditorialRepository(new NoConnection(), true);
        object admin = funder ? new SqlFunderRepository(new NoConnection()) : new SqlFundingOpportunityEditorialRepository(new NoConnection());
        var method = owner.GetType().GetMethod("ScopeParameters", BindingFlags.NonPublic | BindingFlags.Instance)!;
        var userId = Guid.NewGuid();
        var payload = new DynamicParameters();
        payload.Add("AdminUserPublicId", userId);
        var scoped = Assert.IsType<DynamicParameters>(method.Invoke(owner, ["Entity_Update", payload]));
        Assert.True(scoped.Get<bool>("OwnerWorkspace"));
        Assert.Equal(userId, scoped.Get<Guid>("AdminUserPublicId"));
        Assert.Same(payload, method.Invoke(admin, ["Entity_Update", payload]));
        var exception = Assert.Throws<TargetInvocationException>(() => method.Invoke(owner, ["Entity_AdminReview", payload]));
        Assert.IsType<InvalidOperationException>(exception.InnerException);
    }

    [Fact]
    public void Migration_and_smoke_parse_and_reuse_editorial_atomicity_without_role_escalation()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root).Single(s => s.Sequence == 42);
        var smoke = SqlScriptCatalog.DiscoverTests(root).Single(s => s.Sequence == 42);
        foreach (var script in new[] { migration, smoke })
        foreach (var batch in script.Batches)
        {
            using var reader = new StringReader(batch);
            _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(reader, out var errors);
            Assert.True(errors.Count == 0, string.Join("; ", errors.Select(e => e.Message)));
        }
        var sql = File.ReadAllText(Path.Combine(root, "database", "Migrations", migration.FileName));
        Assert.Equal(14, System.Text.RegularExpressions.Regex.Matches(sql, @"@OwnerWorkspace BIT = 0").Count);
        Assert.DoesNotContain("CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Funder_AdminReview", sql);
        Assert.DoesNotContain("CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_AdminReview", sql);
        Assert.DoesNotContain("ALTER ROLE", sql);
        Assert.DoesNotContain("GRANT SELECT", sql);
        Assert.DoesNotContain("EXECUTE AS", sql);
        Assert.Contains("owners.UserId = @ActorUserId AND owners.IsActive = 1", sql);
        Assert.Contains("Workspace ownership cannot be transferred", sql);
        Assert.Contains("ProviderCode = N'funder-workspace'", sql);
        Assert.Contains("@CurrentRowVersion <> @ExpectedRowVersion", sql);
        Assert.Contains("FundingPlatform_FunderEditorialEvents", sql);
        Assert.Contains("FundingPlatform_FundingOpportunityEditorialEvents", sql);
        Assert.Contains("@ExistingRequestHash = @RequestHash", sql);
    }

    private sealed class NoConnection : ISqlConnectionFactory
    {
        public SqlConnection CreateConnection() => throw new InvalidOperationException("Tests must not connect to SQL.");
    }
}
