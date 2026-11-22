using FundingPlatform.Infrastructure.Persistence.Sql;
using FundingPlatform.TestFixtures;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace FundingPlatform.UnitTests;

public sealed class SqlConnectionResilienceTests
{
    [Theory]
    [InlineData(40613, true)][InlineData(40197, true)][InlineData(40501, true)]
    [InlineData(-2, true)][InlineData(10928, true)][InlineData(49920, true)]
    [InlineData(18456, false)][InlineData(4060, false)][InlineData(547, false)]
    [InlineData(51601, false)][InlineData(1205, false)]
    public void Only_temporary_connection_failures_qualify(int number, bool expected)
    {
        var error = SqlExceptionFixture.Create(number);
        Assert.Equal(expected, SqlConnectionResilience.IsTemporarilyUnavailable(error));
        Assert.Equal(expected, SqlConnectionResilience.CreateProvider().RetryLogic.TransientPredicate(error));
    }

    [Fact]
    public void Exhausted_and_wrapped_attempts_are_recognized_but_mixed_or_cancelled_failures_are_not()
    {
        var paused = SqlExceptionFixture.Create(40613);
        Assert.True(SqlConnectionResilience.IsTemporarilyUnavailable(new AggregateException(paused, paused)));
        Assert.True(SqlConnectionResilience.IsTemporarilyUnavailable(new InvalidOperationException("wrapped", paused)));
        Assert.False(SqlConnectionResilience.IsTemporarilyUnavailable(new AggregateException(paused, SqlExceptionFixture.Create(18456))));
        Assert.False(SqlConnectionResilience.IsTemporarilyUnavailable(SqlExceptionFixture.Create(40613, 18456)));
        Assert.False(SqlConnectionResilience.IsTemporarilyUnavailable(new OperationCanceledException("cancelled", paused)));
    }

    [Fact]
    public void Managed_identity_factory_retries_connection_opening_but_not_commands()
    {
        var configuration = new ConfigurationManager();
        configuration["ConnectionStrings:DefaultConnection"] =
            "Server=tcp:unit.database.windows.net,1433;Database=unit;Encrypt=True;Authentication=Active Directory Default;";
        var factory = new UserAssignedManagedIdentitySqlConnectionFactory(configuration, Guid.NewGuid());
        using var first = factory.CreateConnection();
        using var second = factory.CreateConnection();
        Assert.NotSame(first.RetryLogicProvider, second.RetryLogicProvider);
        Assert.Equal(4, first.RetryLogicProvider.RetryLogic.NumberOfTries);
        using var command = first.CreateCommand();
        Assert.True(command.RetryLogicProvider is null ||
            !command.RetryLogicProvider.RetryLogic.TransientPredicate(SqlExceptionFixture.Create(40613)));
    }

    [Fact]
    public async Task Connection_operation_recovers_after_a_temporary_failure()
    {
        using var connection = new SqlConnection();
        var provider = SqlConnectionResilience.CreateProvider();
        var calls = 0;
        var result = await provider.ExecuteAsync(connection, () =>
            ++calls == 1 ? Task.FromException<int>(SqlExceptionFixture.Create(40613)) : Task.FromResult(7));
        Assert.Equal(7, result);
        Assert.Equal(2, calls);
    }

    [Fact]
    public async Task Cancelling_during_backoff_prevents_another_connection_attempt()
    {
        using var connection = new SqlConnection();
        using var cancellation = new CancellationTokenSource();
        var provider = SqlConnectionResilience.CreateProvider();
        var calls = 0;
        provider.Retrying += (_, _) => cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => provider.ExecuteAsync(connection, () =>
        {
            calls++;
            return Task.FromException<int>(SqlExceptionFixture.Create(40613));
        }, cancellation.Token));
        Assert.Equal(1, calls);
    }
}
