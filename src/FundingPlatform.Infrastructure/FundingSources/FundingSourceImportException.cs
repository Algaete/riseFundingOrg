namespace FundingPlatform.Infrastructure.FundingSources;

public sealed class FundingSourceImportException : Exception
{
    public FundingSourceImportException(string message)
        : base(message)
    {
    }

    public FundingSourceImportException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
