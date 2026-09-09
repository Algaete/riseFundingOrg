using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class ForwardReleaseRegressionTests
{
    [Fact]
    public void New_persistent_tables_name_every_constraint_under_the_application_prefix()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        foreach (var script in SqlScriptCatalog.DiscoverMigrations(root).Where(script => script.Sequence >= 31))
        foreach (var batch in script.Batches)
        {
            var fragment = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(new StringReader(batch), out var errors);
            Assert.Empty(errors);
            var visitor = new TableVisitor();
            fragment.Accept(visitor);
            foreach (var table in visitor.Tables.Where(table => table.SchemaObjectName.BaseIdentifier.Value.StartsWith("FundingPlatform_", StringComparison.Ordinal)))
            {
                var constraints = table.Definition.TableConstraints
                    .Concat(table.Definition.ColumnDefinitions.SelectMany(column => column.Constraints))
                    .Concat(table.Definition.ColumnDefinitions.Where(column => column.DefaultConstraint is not null).Select(column => column.DefaultConstraint));
                // NULL/NOT NULL is a column property, not a named sys.objects constraint.
                foreach (var constraint in constraints.Where(constraint => constraint is not NullableConstraintDefinition))
                    Assert.True(constraint.ConstraintIdentifier?.Value.StartsWith("FundingPlatform_", StringComparison.Ordinal) == true,
                        $"{script.FileName}: {table.SchemaObjectName.BaseIdentifier.Value} has an unnamed or unscoped constraint.");
            }
        }
    }

    [Fact]
    public void Incremental_dev_database_release_requires_exact_main_ci_recovery_and_preflight()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var script = File.ReadAllText(Path.Combine(root, "infra", "scripts", "check-dev-database.sh"));
        foreach (var guard in new[] { "DEPLOY-DEV-DATABASE", "RF_DEV_RELEASE_SHA", "ls-remote --heads origin main",
            "ci.yml/runs?branch=main&event=push", "retentionDays", "earliestRestoreDate", "--preflight --apply --apply --test",
            "trap cleanup EXIT", "--start-ip-address \"$task_client_ip\" --end-ip-address \"$task_client_ip\"" })
            Assert.Contains(guard, script, StringComparison.Ordinal);
        Assert.DoesNotContain("--provision-runtime-identities", script, StringComparison.Ordinal);
        Assert.DoesNotContain("RF_DEV_ADMIN_EMAIL", script, StringComparison.Ordinal);
    }

    private sealed class TableVisitor : TSqlFragmentVisitor
    {
        public List<CreateTableStatement> Tables { get; } = [];
        public override void ExplicitVisit(CreateTableStatement node) => Tables.Add(node);
    }
}
