namespace FundingPlatform.Infrastructure.Persistence.Migrations;

public sealed class MigrationException(
    string code,
    string? item = null,
    int? databaseErrorNumber = null,
    Exception? innerException = null) : Exception(code, innerException)
{
    public string Code { get; } = code;

    public string? Item { get; } = item;

    public int? DatabaseErrorNumber { get; } = databaseErrorNumber;
}
