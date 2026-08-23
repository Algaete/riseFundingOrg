namespace FundingPlatform.Core.Identity;

public enum UserStatus : byte
{
    PendingActivation = 0,
    PendingVerification = 1,
    Active = 2,
    Blocked = 3,
    Disabled = 4
}
