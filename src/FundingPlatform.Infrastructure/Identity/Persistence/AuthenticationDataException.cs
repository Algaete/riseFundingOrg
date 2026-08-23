namespace FundingPlatform.Infrastructure.Identity.Persistence;

public sealed class AuthenticationDataException : Exception
{
    public AuthenticationDataException(
        string operation,
        int sqlErrorNumber,
        Exception innerException)
        : base($"Authentication data operation '{operation}' failed (SQL {sqlErrorNumber}).", innerException)
    {
        Operation = operation;
        SqlErrorNumber = sqlErrorNumber;
    }

    public string Operation { get; }

    public int SqlErrorNumber { get; }
}
