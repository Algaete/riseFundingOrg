namespace FundingPlatform.Core.Identity;

public static class PlatformRoles
{
    public const string SuperAdmin = "SuperAdmin";

    public const string Admin = "Admin";

    public static bool RequiresMfa(string role)
    {
        return string.Equals(role, SuperAdmin, StringComparison.OrdinalIgnoreCase) ||
               string.Equals(role, Admin, StringComparison.OrdinalIgnoreCase);
    }
}
