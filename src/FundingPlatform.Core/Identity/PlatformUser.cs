namespace FundingPlatform.Core.Identity;

public sealed class PlatformUser
{
    public long Id { get; set; }

    public Guid PublicId { get; set; }

    public string Email { get; set; } = string.Empty;

    public string NormalizedEmail { get; set; } = string.Empty;

    public string DisplayName { get; set; } = string.Empty;

    public string? PasswordHash { get; set; }

    public string SecurityStamp { get; set; } = string.Empty;

    public int SecurityVersion { get; set; } = 1;

    public bool EmailConfirmed { get; set; }

    public bool TwoFactorEnabled { get; set; }

    public UserStatus Status { get; set; }

    public int AccessFailedCount { get; set; }

    public DateTime? LockoutEndUtc { get; set; }

    public string PreferredLocale { get; set; } = "es-CL";

    public DateTime? LastLoginAtUtc { get; set; }

    public DateTime CreatedAtUtc { get; set; }

    public DateTime UpdatedAtUtc { get; set; }
}
