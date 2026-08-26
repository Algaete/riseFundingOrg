namespace FundingPlatform.Workers.Configuration;

public sealed record AlertWorkerIdentity(Guid InstanceId)
{
    public static AlertWorkerIdentity Create() => new(Guid.NewGuid());
}
