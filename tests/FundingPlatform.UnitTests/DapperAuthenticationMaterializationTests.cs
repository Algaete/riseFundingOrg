using System.Data;
using Dapper;
using FundingPlatform.Application.Authentication;
using FundingPlatform.Infrastructure.Identity.Persistence;

namespace FundingPlatform.UnitTests;

public sealed class DapperAuthenticationMaterializationTests
{
    [Fact]
    public void OperationRecord_AcceptsRegisterResultShape()
    {
        var publicId = Guid.NewGuid();
        using var reader = CreateReader(
            ("ResultCode", typeof(byte), (object)(byte)0),
            ("UserId", typeof(long), 42L),
            ("PublicId", typeof(Guid), publicId));

        var result = ReadSingle<OperationRecord>(reader);

        Assert.Equal((byte)0, result.ResultCode);
        Assert.Equal(42L, result.UserId);
        Assert.Equal(publicId, result.PublicId);
    }

    [Fact]
    public void OperationRecord_AcceptsSingleColumnResultShape()
    {
        using var reader = CreateReader(("ResultCode", typeof(byte), (object)(byte)1));

        var result = ReadSingle<OperationRecord>(reader);

        Assert.Equal((byte)1, result.ResultCode);
        Assert.Null(result.UserId);
        Assert.Null(result.PublicId);
    }

    [Fact]
    public void RefreshRotationRecord_AcceptsFailureResultShape()
    {
        using var reader = CreateReader(("ResultCode", typeof(byte), (object)(byte)3));

        var result = ReadSingle<RefreshRotationRecord>(reader);

        Assert.Equal((byte)3, result.ResultCode);
        Assert.Null(result.UserId);
        Assert.Null(result.FamilyId);
    }

    private static T ReadSingle<T>(IDataReader reader)
    {
        Assert.True(reader.Read());
        return reader.GetRowParser<T>()(reader);
    }

    private static IDataReader CreateReader(
        params (string Name, Type Type, object Value)[] columns)
    {
        var table = new DataTable();
        foreach (var column in columns)
        {
            table.Columns.Add(column.Name, column.Type);
        }

        table.Rows.Add(columns.Select(column => column.Value).ToArray());
        return table.CreateDataReader();
    }
}
