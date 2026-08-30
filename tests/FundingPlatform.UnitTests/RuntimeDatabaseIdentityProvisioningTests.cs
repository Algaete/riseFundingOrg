using FundingPlatform.Infrastructure.Persistence.Migrations;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class RuntimeDatabaseIdentityProvisioningTests
{
    private static readonly Guid ApiClientId =
        Guid.Parse("00112233-4455-6677-8899-aabbccddeeff");
    private static readonly Guid GeneralClientId =
        Guid.Parse("11112233-4455-6677-8899-aabbccddeeff");
    private static readonly Guid ConsumerClientId =
        Guid.Parse("21112233-4455-6677-8899-aabbccddeeff");
    private static readonly Guid ExtractionHostClientId =
        Guid.Parse("31112233-4455-6677-8899-aabbccddeeff");
    private static readonly Guid SenderClientId =
        Guid.Parse("41112233-4455-6677-8899-aabbccddeeff");

    [Fact]
    public void Plan_maps_only_the_three_runtime_users_to_their_exact_roles()
    {
        var plan = ValidPlan();

        Assert.Collection(
            plan.DatabaseUsers,
            item =>
            {
                Assert.Equal("id-rf-dev-demo-api", item.UserName);
                Assert.Equal(ApiClientId, item.ClientId);
                Assert.Equal(RuntimeDatabaseIdentityPlan.ApiRuntimeRole, item.RoleName);
            },
            item => Assert.Equal(
                RuntimeDatabaseIdentityPlan.GeneralWorkerRole, item.RoleName),
            item => Assert.Equal(
                RuntimeDatabaseIdentityPlan.ExtractionWorkerRole, item.RoleName));
        Assert.Equal(2, plan.IdentitiesWithoutDatabaseAccess.Count);
        Assert.Contains(plan.IdentitiesWithoutDatabaseAccess,
            item => item.UserName == "id-func-rf-dev-demo-extract-host");
        Assert.Contains(plan.IdentitiesWithoutDatabaseAccess,
            item => item.UserName == "id-rf-dev-demo-extract-send");
    }

    [Fact]
    public void Client_id_matches_sql_convert_varbinary_uniqueidentifier_byte_order()
    {
        var sid = RuntimeDatabaseIdentityPlan.ClientIdToSid(ApiClientId);

        Assert.Equal("33221100554477668899AABBCCDDEEFF", Convert.ToHexString(sid));
    }

    [Fact]
    public void Plan_rejects_duplicate_names_or_client_ids_across_sql_and_no_sql_identities()
    {
        Assert.Throws<ArgumentException>(() => RuntimeDatabaseIdentityPlan.Create(
            "api", ApiClientId,
            "API", GeneralClientId,
            "consumer", ConsumerClientId,
            "host", ExtractionHostClientId,
            "sender", SenderClientId));
        Assert.Throws<ArgumentException>(() => RuntimeDatabaseIdentityPlan.Create(
            "api", ApiClientId,
            "general", GeneralClientId,
            "consumer", ConsumerClientId,
            "host", ExtractionHostClientId,
            "sender", ApiClientId));
    }

    [Theory]
    [InlineData("")]
    [InlineData(" leading")]
    [InlineData("trailing ")]
    [InlineData("line\nbreak")]
    public void Plan_rejects_unsafe_or_ambiguous_user_names(string userName)
    {
        Assert.Throws<ArgumentException>(() => RuntimeDatabaseIdentityPlan.Create(
            userName, ApiClientId,
            "general", GeneralClientId,
            "consumer", ConsumerClientId,
            "host", ExtractionHostClientId,
            "sender", SenderClientId));
    }

    [Fact]
    public void Provisioning_sql_uses_sid_without_graph_and_quotes_identifiers_server_side()
    {
        Assert.Contains("QUOTENAME(@UserName)",
            RuntimeDatabaseIdentityProvisioner.CreateUserSql, StringComparison.Ordinal);
        Assert.Contains("WITH SID =", RuntimeDatabaseIdentityProvisioner.CreateUserSql,
            StringComparison.Ordinal);
        Assert.Contains("TYPE = E", RuntimeDatabaseIdentityProvisioner.CreateUserSql,
            StringComparison.Ordinal);
        Assert.DoesNotContain("EXTERNAL PROVIDER",
            RuntimeDatabaseIdentityProvisioner.CreateUserSql,
            StringComparison.OrdinalIgnoreCase);
        Assert.Contains("QUOTENAME(@RoleName)",
            RuntimeDatabaseIdentityProvisioner.AddRoleMemberSql,
            StringComparison.Ordinal);
        Assert.Contains("DECLARE @AlterRoleSql nvarchar(max)",
            RuntimeDatabaseIdentityProvisioner.AddRoleMemberSql,
            StringComparison.Ordinal);
        Assert.Contains("EXEC sys.sp_executesql @AlterRoleSql",
            RuntimeDatabaseIdentityProvisioner.AddRoleMemberSql,
            StringComparison.Ordinal);
        Assert.DoesNotContain("EXEC sys.sp_executesql\n    N'ALTER ROLE '",
            RuntimeDatabaseIdentityProvisioner.AddRoleMemberSql,
            StringComparison.Ordinal);

        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var source = File.ReadAllText(Path.Combine(
            root,
            "src",
            "FundingPlatform.Infrastructure",
            "Persistence",
            "Migrations",
            "RuntimeDatabaseIdentityProvisioner.cs"));
        Assert.Contains("sys.database_permissions", source, StringComparison.Ordinal);
        Assert.Contains("permissions.permission_name = N'CONNECT'", source,
            StringComparison.Ordinal);
        Assert.Contains("permissions.state = N'G'", source, StringComparison.Ordinal);
        Assert.Contains("sys.schemas", source, StringComparison.Ordinal);
        Assert.Contains("owning_principal_id = @PrincipalId", source, StringComparison.Ordinal);
        Assert.Contains("runtime_identity_direct_privilege_or_ownership_detected", source,
            StringComparison.Ordinal);
        Assert.Contains("EnsureRuntimeRoleMembersExactAsync", source, StringComparison.Ordinal);
        Assert.Contains("roleMembers.Length != 1", source, StringComparison.Ordinal);
        Assert.Contains("runtime_identity_role_has_unexpected_members", source,
            StringComparison.Ordinal);
    }

    [Theory]
    [MemberData(nameof(RuntimeIdentityProvisioningBatches))]
    public void Runtime_identity_provisioning_batches_parse_as_azure_sql(
        string batchName,
        string sql)
    {
        AssertValidAzureSql(batchName, sql);
    }

    [Theory]
    [InlineData(
        "create-user",
        "CREATE USER [id-rf-dev-demo-api] WITH SID = " +
        "0x33221100554477668899AABBCCDDEEFF, TYPE = E;")]
    [InlineData(
        "alter-role",
        "ALTER ROLE [FundingPlatform_ApiRuntimeRole] " +
        "ADD MEMBER [id-rf-dev-demo-api];")]
    public void Runtime_identity_generated_ddl_parses_as_azure_sql(
        string statementName,
        string sql)
    {
        AssertValidAzureSql(statementName, sql);
    }

    [Fact]
    public void Azure_sql_gate_rejects_inline_sp_executesql_concatenation()
    {
        const string legacyInvalidSql = """
            EXEC sys.sp_executesql
                N'ALTER ROLE ' + @QuotedRoleName + N' ADD MEMBER ' + @QuotedUserName + N';';
            """;

        Assert.NotEmpty(ParseAzureSql(legacyInvalidSql));
    }

    [Fact]
    public void Runtime_provisioner_requires_both_explicit_database_and_azure_sql_server()
    {
        var missingDatabase = Assert.Throws<MigrationException>(() =>
            new RuntimeDatabaseIdentityProvisioner(
                new UnusedConnectionFactory(), null, null));
        Assert.Equal("runtime_identity_expected_database_required", missingDatabase.Code);

        var missingServer = Assert.Throws<MigrationException>(() =>
            new RuntimeDatabaseIdentityProvisioner(
                new UnusedConnectionFactory(), "risefunding-dev", null));
        Assert.Equal("expected_sql_server_fqdn_required", missingServer.Code);
    }

    [Theory]
    [InlineData("tcp:sql-rf-dev-demo.database.windows.net,1433",
        "sql-rf-dev-demo.database.windows.net")]
    [InlineData("SQL-RF-DEV-DEMO.database.windows.net",
        "sql-rf-dev-demo.database.windows.net")]
    [InlineData("tcp:sql-rf-dev-demo.database.windows.net,1444", "")]
    public void Sql_target_normalizes_only_the_expected_azure_sql_endpoint(
        string dataSource,
        string expected)
    {
        Assert.Equal(expected, SqlDeploymentTargetVerifier.NormalizeDataSource(dataSource));
    }

    [Fact]
    public void Sql_target_requires_serverproperty_to_match_the_same_logical_server()
    {
        const string fqdn = "sql-rf-dev-demo.database.windows.net";
        Assert.True(SqlDeploymentTargetVerifier.ServerPropertyMatches("sql-rf-dev-demo", fqdn));
        Assert.True(SqlDeploymentTargetVerifier.ServerPropertyMatches(fqdn, fqdn));
        Assert.False(SqlDeploymentTargetVerifier.ServerPropertyMatches("sql-rf-prod-demo", fqdn));
    }

    [Theory]
    [InlineData("-sql.database.windows.net")]
    [InlineData("sql dev.database.windows.net")]
    [InlineData("sql.extra.database.windows.net")]
    [InlineData("sql-rf-dev-demo.example.com")]
    [InlineData("tcp:sql-rf-dev-demo.database.windows.net,1433")]
    public void Sql_target_rejects_invalid_expected_server_fqdns(string server)
    {
        Assert.Throws<InvalidOperationException>(() =>
            MigrationSafety.ResolveExpectedServerFqdn(server));
    }

    [Fact]
    public void Migrator_and_admin_cli_share_the_guarded_target_verifier()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migrator = File.ReadAllText(Path.Combine(
            root, "tools", "FundingPlatform.DatabaseMigrator", "Program.cs"));
        var adminCli = File.ReadAllText(Path.Combine(
            root, "tools", "FundingPlatform.AdminCli", "Program.cs"));

        Assert.Contains("SqlDeploymentTargetVerifier", migrator, StringComparison.Ordinal);
        Assert.Contains("VerifyDeploymentTargetAsync", adminCli, StringComparison.Ordinal);
        Assert.Contains("Migrations:ExpectedServerFqdn",
            MigrationSafety.ExpectedServerConfigurationKey, StringComparison.Ordinal);
    }

    private static RuntimeDatabaseIdentityPlan ValidPlan() =>
        RuntimeDatabaseIdentityPlan.Create(
            "id-rf-dev-demo-api", ApiClientId,
            "id-func-rf-dev-demo-general-host", GeneralClientId,
            "id-rf-dev-demo-extract-consume", ConsumerClientId,
            "id-func-rf-dev-demo-extract-host", ExtractionHostClientId,
            "id-rf-dev-demo-extract-send", SenderClientId);

    public static TheoryData<string, string> RuntimeIdentityProvisioningBatches =>
        new()
        {
            {
                nameof(RuntimeDatabaseIdentityProvisioner.CreateUserSql),
                RuntimeDatabaseIdentityProvisioner.CreateUserSql
            },
            {
                nameof(RuntimeDatabaseIdentityProvisioner.AddRoleMemberSql),
                RuntimeDatabaseIdentityProvisioner.AddRoleMemberSql
            }
        };

    private static void AssertValidAzureSql(string statementName, string sql)
    {
        var errors = ParseAzureSql(sql);

        Assert.True(
            errors.Count == 0,
            $"{statementName} is not valid Azure SQL: " +
            string.Join(
                "; ",
                errors.Select(error =>
                    $"SQL{error.Number} line {error.Line}, column {error.Column}: " +
                    error.Message)));
    }

    private static IList<ParseError> ParseAzureSql(string sql)
    {
        var parser = new TSql170Parser(true, SqlEngineType.SqlAzure);
        using var reader = new StringReader(sql);
        _ = parser.Parse(reader, out var errors);
        return errors;
    }

    private sealed class UnusedConnectionFactory : ISqlConnectionFactory
    {
        public SqlConnection CreateConnection() =>
            throw new InvalidOperationException("The constructor must not open SQL.");
    }
}
