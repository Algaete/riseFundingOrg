namespace FundingPlatform.Infrastructure.Persistence.FundingOpportunities;

public sealed class FundingOpportunityDataException : Exception
{
    public FundingOpportunityDataException(string operation, int sqlErrorNumber, Exception innerException)
        : base($"The funding opportunity data operation '{operation}' failed (SQL {sqlErrorNumber}).", innerException)
    {
        Operation = operation;
        SqlErrorNumber = sqlErrorNumber;
    }

    public string Operation { get; }

    public int SqlErrorNumber { get; }
}
