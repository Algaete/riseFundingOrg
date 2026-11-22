using System.Reflection;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.TestFixtures;

// SqlException has no public constructor. Build the actual driver exception so
// retry classification and HTTP sanitization are tested without a cloud outage.
internal static class SqlExceptionFixture
{
    internal static SqlException Create(params int[] numbers)
    {
        var errors = (SqlErrorCollection)Activator.CreateInstance(typeof(SqlErrorCollection), true)!;
        foreach (var number in numbers)
        {
            var error = (SqlError)typeof(SqlError).GetConstructor(
                BindingFlags.Instance | BindingFlags.NonPublic, null,
                [typeof(int), typeof(byte), typeof(byte), typeof(string), typeof(string), typeof(string), typeof(int), typeof(Exception)], null)!
                .Invoke([number, (byte)1, (byte)20, "private-server", "private SQL diagnostic", "private-procedure", 1, null]);
            typeof(SqlErrorCollection).GetMethod("Add", BindingFlags.Instance | BindingFlags.NonPublic)!
                .Invoke(errors, [error]);
        }
        return (SqlException)typeof(SqlException).GetConstructor(
            BindingFlags.Instance | BindingFlags.NonPublic, null,
            [typeof(string), typeof(SqlErrorCollection), typeof(Exception), typeof(Guid)], null)!
            .Invoke(["private SQL diagnostic", errors, null, Guid.NewGuid()]);
    }
}
