namespace FundingPlatform.Workers.Configuration;

public sealed record SemanticWorkerIdentity(string InstanceId)
{
    public static SemanticWorkerIdentity Create() =>
        new($"semantic-{Guid.NewGuid():N}");
}
