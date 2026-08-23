using System.Net.Mail;
using FundingPlatform.Application.Authentication;
using FundingPlatform.Core.Identity;
using FundingPlatform.Infrastructure.Identity.Configuration;
using FundingPlatform.Infrastructure.Identity.Cryptography;
using FundingPlatform.Infrastructure.Identity.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FundingPlatform.Infrastructure.Identity;

public sealed class AuthenticationService : IAuthenticationService
{
    private const byte VerifyEmailPurpose = 0;
    private const byte ResetPasswordPurpose = 1;
    private const byte RotatedReason = 0;
    private const byte LogoutReason = 1;
    private const byte CredentialChangeReason = 3;
    private static readonly string AuthenticatorProvider = TokenOptions.DefaultAuthenticatorProvider;

    private readonly UserManager<PlatformUser> _userManager;
    private readonly IPasswordHasher<PlatformUser> _passwordHasher;
    private readonly SqlAuthenticationRepository _repository;
    private readonly IIdentityEmailSender _emailSender;
    private readonly SecureTokenGenerator _tokenGenerator;
    private readonly JwtTokenIssuer _jwtTokenIssuer;
    private readonly AuthenticationOptions _options;
    private readonly TimeProvider _timeProvider;
    private readonly ILogger<AuthenticationService> _logger;
    private readonly string _dummyPasswordHash;

    public AuthenticationService(
        UserManager<PlatformUser> userManager,
        IPasswordHasher<PlatformUser> passwordHasher,
        SqlAuthenticationRepository repository,
        IIdentityEmailSender emailSender,
        SecureTokenGenerator tokenGenerator,
        JwtTokenIssuer jwtTokenIssuer,
        IOptions<AuthenticationOptions> options,
        TimeProvider timeProvider,
        ILogger<AuthenticationService> logger)
    {
        _userManager = userManager;
        _passwordHasher = passwordHasher;
        _repository = repository;
        _emailSender = emailSender;
        _tokenGenerator = tokenGenerator;
        _jwtTokenIssuer = jwtTokenIssuer;
        _options = options.Value;
        _timeProvider = timeProvider;
        _logger = logger;
        _dummyPasswordHash = passwordHasher.HashPassword(
            new PlatformUser(),
            SecureTokenGenerator.GenerateOpaqueToken());
    }

    public async Task<RegistrationResult> RegisterAsync(
        RegistrationInput input,
        ClientRequestContext context,
        CancellationToken cancellationToken)
    {
        var validationFailures = await ValidateRegistrationAsync(input, cancellationToken);
        if (validationFailures.Count > 0)
        {
            return new RegistrationResult(false, validationFailures);
        }

        var nowUtc = UtcNow();
        var normalizedEmail = _userManager.NormalizeEmail(input.Email.Trim());
        var rawToken = SecureTokenGenerator.GenerateOpaqueToken();
        var user = new PlatformUser
        {
            Email = input.Email.Trim(),
            NormalizedEmail = normalizedEmail,
            DisplayName = input.DisplayName.Trim(),
            SecurityStamp = Guid.NewGuid().ToString("N"),
            SecurityVersion = 1,
            Status = UserStatus.PendingVerification,
            PreferredLocale = input.PreferredLocale.Trim(),
            CreatedAtUtc = nowUtc,
            UpdatedAtUtc = nowUtc
        };
        user.PasswordHash = _passwordHasher.HashPassword(user, input.Password);

        var resultCode = await _repository.RegisterAsync(
            user,
            SecureTokenGenerator.HashOpaqueToken(rawToken),
            nowUtc.AddHours(_options.SecurityToken.VerificationHours),
            HashIp(context),
            nowUtc,
            cancellationToken);

        if (resultCode == 0)
        {
            await _emailSender.SendVerificationAsync(
                user.Email,
                user.DisplayName,
                rawToken,
                cancellationToken);
            await WriteEventAsync(0, 0, null, null, context, nowUtc, cancellationToken);
            return RegistrationResult.GenericAccepted;
        }

        await ResendVerificationInternalAsync(
            normalizedEmail,
            context,
            nowUtc,
            cancellationToken);
        await WriteEventAsync(0, 2, "generic_existing", null, context, nowUtc, cancellationToken);
        return RegistrationResult.GenericAccepted;
    }

    public async Task<bool> VerifyEmailAsync(
        string token,
        ClientRequestContext context,
        CancellationToken cancellationToken)
    {
        if (!IsPlausibleOpaqueToken(token))
        {
            return false;
        }

        var nowUtc = UtcNow();
        var succeeded = await _repository.VerifyEmailAsync(
            SecureTokenGenerator.HashOpaqueToken(token),
            nowUtc,
            cancellationToken);
        await WriteEventAsync(
            1,
            succeeded ? (byte)0 : (byte)1,
            succeeded ? null : "invalid_or_expired",
            null,
            context,
            nowUtc,
            cancellationToken);
        return succeeded;
    }

    public Task ResendVerificationAsync(
        string email,
        ClientRequestContext context,
        CancellationToken cancellationToken)
    {
        if (!IsValidEmail(email) || email.Length > 320)
        {
            return Task.CompletedTask;
        }

        return ResendVerificationInternalAsync(
            _userManager.NormalizeEmail(email.Trim()),
            context,
            UtcNow(),
            cancellationToken);
    }

    public async Task<LoginResult> LoginAsync(
        LoginInput input,
        ClientRequestContext context,
        CancellationToken cancellationToken)
    {
        var nowUtc = UtcNow();
        if (!IsValidEmail(input.Email) ||
            input.Email.Length > 320 ||
            string.IsNullOrEmpty(input.Password) ||
            input.Password.Length > 128)
        {
            VerifyDummyPassword(input.Password);
            await WriteEventAsync(2, 1, "invalid_credentials", null, context, nowUtc, cancellationToken);
            return new LoginResult(LoginOutcome.InvalidCredentials);
        }

        var normalizedEmail = _userManager.NormalizeEmail(input.Email.Trim());
        var user = await _repository.FindByNormalizedEmailAsync(normalizedEmail, cancellationToken);
        if (user is null || string.IsNullOrWhiteSpace(user.PasswordHash))
        {
            VerifyDummyPassword(input.Password);
            await WriteEventAsync(2, 1, "invalid_credentials", null, context, nowUtc, cancellationToken);
            return new LoginResult(LoginOutcome.InvalidCredentials);
        }

        if (user.Status is UserStatus.Blocked or UserStatus.Disabled ||
            user.LockoutEndUtc is not null && user.LockoutEndUtc > nowUtc)
        {
            VerifyDummyPassword(input.Password);
            await WriteEventAsync(2, 1, "account_unavailable", user.Id, context, nowUtc, cancellationToken);
            return new LoginResult(LoginOutcome.InvalidCredentials);
        }

        var passwordResult = _passwordHasher.VerifyHashedPassword(
            user,
            user.PasswordHash,
            input.Password);
        if (passwordResult == PasswordVerificationResult.Failed)
        {
            var lockoutOptions = _userManager.Options.Lockout;
            _ = await _repository.RecordFailedLoginAsync(
                user.Id,
                lockoutOptions.MaxFailedAccessAttempts,
                lockoutOptions.DefaultLockoutTimeSpan,
                nowUtc,
                cancellationToken);
            await WriteEventAsync(2, 1, "invalid_credentials", user.Id, context, nowUtc, cancellationToken);
            return new LoginResult(LoginOutcome.InvalidCredentials);
        }

        if (passwordResult == PasswordVerificationResult.SuccessRehashNeeded)
        {
            user.PasswordHash = _passwordHasher.HashPassword(user, input.Password);
            _ = await _userManager.UpdateAsync(user);
        }

        await _repository.RecordSuccessfulLoginAsync(user.Id, nowUtc, cancellationToken);

        if (!user.EmailConfirmed || user.Status == UserStatus.PendingVerification)
        {
            await WriteEventAsync(2, 2, "email_verification_required", user.Id, context, nowUtc, cancellationToken);
            return new LoginResult(LoginOutcome.EmailVerificationRequired);
        }

        if (user.Status != UserStatus.Active)
        {
            await WriteEventAsync(2, 1, "account_unavailable", user.Id, context, nowUtc, cancellationToken);
            return new LoginResult(LoginOutcome.InvalidCredentials);
        }

        var roles = await _repository.GetRolesAsync(user.Id, cancellationToken);
        var requiresMfa = roles.Any(PlatformRoles.RequiresMfa);
        if (requiresMfa && !user.TwoFactorEnabled)
        {
            var setupToken = _jwtTokenIssuer.Issue(
                user,
                roles,
                Guid.NewGuid(),
                mfaAuthenticated: false,
                authorizationLevel: "mfa_setup");
            await WriteEventAsync(2, 2, "mfa_setup_required", user.Id, context, nowUtc, cancellationToken);
            return new LoginResult(
                LoginOutcome.MfaSetupRequired,
                MfaSetupToken: setupToken.Token);
        }

        if (user.TwoFactorEnabled)
        {
            var rawChallenge = SecureTokenGenerator.GenerateOpaqueToken();
            var challengeExpiry = nowUtc.AddMinutes(_options.Mfa.ChallengeMinutes);
            await _repository.CreateMfaChallengeAsync(
                user.Id,
                user.SecurityVersion,
                SecureTokenGenerator.HashOpaqueToken(rawChallenge),
                challengeExpiry,
                checked((short)_options.Mfa.MaxAttempts),
                HashIp(context),
                nowUtc,
                cancellationToken);
            await WriteEventAsync(2, 2, "mfa_required", user.Id, context, nowUtc, cancellationToken);
            return new LoginResult(
                LoginOutcome.MfaRequired,
                MfaChallengeToken: rawChallenge,
                MfaChallengeExpiresAtUtc: challengeExpiry);
        }

        var result = await CreateSessionAsync(
            user,
            roles,
            false,
            context,
            nowUtc,
            cancellationToken);
        await WriteEventAsync(2, 0, null, user.Id, context, nowUtc, cancellationToken);
        return result;
    }

    public async Task<RefreshResult> RefreshAsync(
        string refreshToken,
        ClientRequestContext context,
        CancellationToken cancellationToken)
    {
        if (!IsPlausibleOpaqueToken(refreshToken))
        {
            return new RefreshResult(RefreshOutcome.Invalid);
        }

        var nowUtc = UtcNow();
        var replacementRawToken = SecureTokenGenerator.GenerateOpaqueToken();
        var replacementJwtId = Guid.NewGuid();
        var replacementExpires = nowUtc.AddDays(_options.RefreshToken.LifetimeDays);
        var record = await _repository.RotateRefreshTokenAsync(
            SecureTokenGenerator.HashOpaqueToken(refreshToken),
            SecureTokenGenerator.HashOpaqueToken(replacementRawToken),
            replacementJwtId,
            replacementExpires,
            HashIp(context),
            NormalizeUserAgent(context.UserAgent),
            nowUtc,
            nowUtc.AddSeconds(_options.RefreshToken.RotationGraceSeconds),
            cancellationToken);

        var outcome = record.ResultCode switch
        {
            1 => RefreshOutcome.Invalid,
            2 => RefreshOutcome.Expired,
            3 => RefreshOutcome.ReplayDetected,
            4 => RefreshOutcome.SessionInvalidated,
            5 => RefreshOutcome.Conflict,
            _ => RefreshOutcome.Success
        };
        if (outcome != RefreshOutcome.Success || record.UserId is null)
        {
            await WriteEventAsync(
                3,
                outcome == RefreshOutcome.Conflict ? (byte)2 : (byte)1,
                outcome.ToString().ToLowerInvariant(),
                record.UserId,
                context,
                nowUtc,
                cancellationToken);
            return new RefreshResult(outcome);
        }

        var user = await _repository.FindByIdAsync(record.UserId.Value, cancellationToken);
        if (user is null)
        {
            return new RefreshResult(RefreshOutcome.SessionInvalidated);
        }

        var roles = await _repository.GetRolesAsync(user.Id, cancellationToken);
        var mfaAuthenticated = record.MfaAuthenticated == true &&
                               record.MfaAuthenticatedAtUtc.HasValue;
        var mfaIsRecent = mfaAuthenticated &&
                          record.MfaAuthenticatedAtUtc <= nowUtc.AddSeconds(30) &&
                          record.MfaAuthenticatedAtUtc >= nowUtc.AddMinutes(
                              -_options.Mfa.AdminSessionMinutes);
        if (roles.Any(PlatformRoles.RequiresMfa) && !mfaIsRecent)
        {
            await _repository.RevokeRefreshFamilyAsync(
                SecureTokenGenerator.HashOpaqueToken(replacementRawToken),
                CredentialChangeReason,
                nowUtc,
                cancellationToken);
            return new RefreshResult(RefreshOutcome.SessionInvalidated);
        }

        var accessToken = _jwtTokenIssuer.Issue(
            user,
            roles,
            replacementJwtId,
            mfaAuthenticated,
            authenticationTimeUtc: record.MfaAuthenticatedAtUtc);
        var session = BuildSession(user, roles, accessToken);
        await WriteEventAsync(3, 0, null, user.Id, context, nowUtc, cancellationToken);
        return new RefreshResult(RefreshOutcome.Success, session, replacementRawToken);
    }

    public async Task LogoutAsync(
        string refreshToken,
        ClientRequestContext context,
        CancellationToken cancellationToken)
    {
        if (!IsPlausibleOpaqueToken(refreshToken))
        {
            return;
        }

        var nowUtc = UtcNow();
        await _repository.RevokeRefreshFamilyAsync(
            SecureTokenGenerator.HashOpaqueToken(refreshToken),
            LogoutReason,
            nowUtc,
            cancellationToken);
        await WriteEventAsync(4, 0, null, null, context, nowUtc, cancellationToken);
    }

    public async Task LogoutAllAsync(
        Guid publicUserId,
        ClientRequestContext context,
        CancellationToken cancellationToken)
    {
        var user = await _repository.FindByPublicIdAsync(publicUserId, cancellationToken);
        if (user is null)
        {
            return;
        }

        var nowUtc = UtcNow();
        await _repository.InvalidateSessionsAsync(
            user.Id,
            Guid.NewGuid().ToString("N"),
            LogoutReason,
            nowUtc,
            cancellationToken);
        await WriteEventAsync(4, 0, "logout_all", user.Id, context, nowUtc, cancellationToken);
    }

    public async Task ForgotPasswordAsync(
        string email,
        ClientRequestContext context,
        CancellationToken cancellationToken)
    {
        if (!IsValidEmail(email) || email.Length > 320)
        {
            return;
        }

        var nowUtc = UtcNow();
        var rawToken = SecureTokenGenerator.GenerateOpaqueToken();
        var record = await _repository.IssueSecurityTokenAsync(
            _userManager.NormalizeEmail(email.Trim()),
            ResetPasswordPurpose,
            SecureTokenGenerator.HashOpaqueToken(rawToken),
            nowUtc.AddMinutes(_options.SecurityToken.PasswordResetMinutes),
            HashIp(context),
            nowUtc,
            cancellationToken);

        if (record.ResultCode == 0 && record.Email is not null && record.DisplayName is not null)
        {
            await _emailSender.SendPasswordResetAsync(
                record.Email,
                record.DisplayName,
                rawToken,
                cancellationToken);
        }

        await WriteEventAsync(5, 0, "generic", record.UserId, context, nowUtc, cancellationToken);
    }

    public async Task<PasswordResetResult> ResetPasswordAsync(
        ResetPasswordInput input,
        ClientRequestContext context,
        CancellationToken cancellationToken)
    {
        var passwordFailures = await ValidatePasswordAsync(
            new PlatformUser(),
            input.NewPassword,
            cancellationToken);
        if (passwordFailures.Count > 0)
        {
            return new PasswordResetResult(false, passwordFailures);
        }

        if (!IsPlausibleOpaqueToken(input.Token))
        {
            return new PasswordResetResult(false, []);
        }

        var nowUtc = UtcNow();
        var passwordUser = new PlatformUser();
        var passwordHash = _passwordHasher.HashPassword(passwordUser, input.NewPassword);
        var succeeded = await _repository.ResetPasswordAsync(
            SecureTokenGenerator.HashOpaqueToken(input.Token),
            passwordHash,
            Guid.NewGuid().ToString("N"),
            nowUtc,
            cancellationToken);
        await WriteEventAsync(
            6,
            succeeded ? (byte)0 : (byte)1,
            succeeded ? null : "invalid_or_expired",
            null,
            context,
            nowUtc,
            cancellationToken);
        return new PasswordResetResult(succeeded, []);
    }

    public async Task<AuthenticatedUser?> GetCurrentUserAsync(
        Guid publicUserId,
        CancellationToken cancellationToken)
    {
        var user = await _repository.FindByPublicIdAsync(publicUserId, cancellationToken);
        if (user is null || user.Status != UserStatus.Active)
        {
            return null;
        }

        var roles = await _repository.GetRolesAsync(user.Id, cancellationToken);
        return BuildAuthenticatedUser(user, roles);
    }

    public async Task<LoginResult> CompleteMfaChallengeAsync(
        MfaChallengeInput input,
        ClientRequestContext context,
        CancellationToken cancellationToken)
    {
        if (!IsPlausibleOpaqueToken(input.ChallengeToken) ||
            string.IsNullOrWhiteSpace(input.Code) ||
            input.Code.Length > 64)
        {
            return new LoginResult(LoginOutcome.InvalidCredentials);
        }

        var nowUtc = UtcNow();
        var challenge = await _repository.GetMfaChallengeAsync(
            SecureTokenGenerator.HashOpaqueToken(input.ChallengeToken),
            cancellationToken);
        if (challenge is null ||
            challenge.ConsumedAtUtc is not null ||
            challenge.ExpiresAtUtc <= nowUtc ||
            challenge.AttemptCount >= challenge.MaxAttempts)
        {
            return new LoginResult(LoginOutcome.InvalidCredentials);
        }

        var user = await _repository.FindByIdAsync(challenge.UserId, cancellationToken);
        if (user is null ||
            user.Status != UserStatus.Active ||
            user.SecurityVersion != challenge.SecurityVersion ||
            !user.TwoFactorEnabled)
        {
            return new LoginResult(LoginOutcome.InvalidCredentials);
        }

        var normalizedCode = input.Code.Replace(" ", string.Empty, StringComparison.Ordinal)
            .Trim();
        var succeeded = normalizedCode.Length == 6 && normalizedCode.All(char.IsDigit)
            ? await _userManager.VerifyTwoFactorTokenAsync(user, AuthenticatorProvider, normalizedCode)
            : await _repository.TryConsumeRecoveryCodeAsync(
                user.Id,
                _options.SecurityHash.RecoveryCodePepperVersion,
                _tokenGenerator.HashRecoveryCode(normalizedCode),
                nowUtc,
                cancellationToken);

        var attemptRecorded = await _repository.CompleteMfaChallengeAttemptAsync(
            challenge.Id,
            succeeded,
            nowUtc,
            cancellationToken);
        if (!succeeded || !attemptRecorded)
        {
            await WriteEventAsync(7, 1, "invalid_mfa_code", user.Id, context, nowUtc, cancellationToken);
            return new LoginResult(LoginOutcome.InvalidCredentials);
        }

        var roles = await _repository.GetRolesAsync(user.Id, cancellationToken);
        var result = await CreateSessionAsync(
            user,
            roles,
            true,
            context,
            nowUtc,
            cancellationToken);
        await WriteEventAsync(7, 0, null, user.Id, context, nowUtc, cancellationToken);
        return result;
    }

    public async Task<MfaSetupResult> BeginMfaSetupAsync(
        Guid publicUserId,
        CancellationToken cancellationToken)
    {
        var user = await RequireActiveUserAsync(publicUserId, cancellationToken);
        var resetResult = await _userManager.ResetAuthenticatorKeyAsync(user);
        if (!resetResult.Succeeded)
        {
            throw new InvalidOperationException("The authenticator key could not be initialized.");
        }

        var sharedKey = await _userManager.GetAuthenticatorKeyAsync(user);
        if (string.IsNullOrWhiteSpace(sharedKey))
        {
            throw new InvalidOperationException("The authenticator key could not be loaded.");
        }

        var issuer = Uri.EscapeDataString("FundingPlatform");
        var account = Uri.EscapeDataString(user.Email);
        var uri = $"otpauth://totp/{issuer}:{account}?secret={sharedKey}&issuer={issuer}&digits=6";
        return new MfaSetupResult(sharedKey, uri);
    }

    public async Task<MfaConfirmationResult?> ConfirmMfaSetupAsync(
        Guid publicUserId,
        string code,
        CancellationToken cancellationToken)
    {
        var user = await RequireActiveUserAsync(publicUserId, cancellationToken);
        if (string.IsNullOrWhiteSpace(code) || code.Length > 32)
        {
            return null;
        }

        var normalizedCode = code.Replace(" ", string.Empty, StringComparison.Ordinal).Trim();
        if (normalizedCode.Length != 6 ||
            !normalizedCode.All(char.IsDigit) ||
            !await _userManager.VerifyTwoFactorTokenAsync(user, AuthenticatorProvider, normalizedCode))
        {
            return null;
        }

        var nowUtc = UtcNow();
        var recoveryCodes = Enumerable.Range(0, _options.Mfa.RecoveryCodeCount)
            .Select(_ => _tokenGenerator.GenerateRecoveryCode())
            .ToArray();
        await _repository.MarkMfaConfirmedAsync(user.Id, nowUtc, cancellationToken);
        await _repository.ReplaceRecoveryCodesAsync(
            user.Id,
            _options.SecurityHash.RecoveryCodePepperVersion,
            recoveryCodes.Select(_tokenGenerator.HashRecoveryCode).ToArray(),
            nowUtc,
            cancellationToken);
        await _repository.InvalidateSessionsAsync(
            user.Id,
            Guid.NewGuid().ToString("N"),
            CredentialChangeReason,
            nowUtc,
            cancellationToken);
        return new MfaConfirmationResult(recoveryCodes);
    }

    public async Task<ExternalIdentityCompletionResult> CompleteExternalIdentityAsync(
        ExternalIdentityInput input,
        ClientRequestContext context,
        CancellationToken cancellationToken)
    {
        if (!IsValidExternalIdentity(input))
        {
            return new ExternalIdentityCompletionResult(ExternalIdentityCompletionOutcome.InvalidIdentity);
        }

        var nowUtc = UtcNow();
        var rawHandoff = SecureTokenGenerator.GenerateOpaqueToken();
        var placeholderPassword = SecureTokenGenerator.GenerateOpaqueToken(48);
        var placeholderUser = new PlatformUser { Email = input.Email, DisplayName = input.DisplayName };
        var record = await _repository.CompleteExternalIdentityAsync(
            input with
            {
                Provider = input.Provider.Trim().ToLowerInvariant(),
                Issuer = input.Issuer.Trim(),
                Subject = input.Subject.Trim(),
                Email = input.Email.Trim(),
                DisplayName = input.DisplayName.Trim()
            },
            _userManager.NormalizeEmail(input.Email.Trim()),
            _passwordHasher.HashPassword(placeholderUser, placeholderPassword),
            Guid.NewGuid().ToString("N"),
            SecureTokenGenerator.HashOpaqueToken(rawHandoff),
            nowUtc.AddMinutes(_options.External.HandoffMinutes),
            HashIp(context),
            NormalizeUserAgent(context.UserAgent),
            nowUtc,
            cancellationToken);

        var outcome = record.ResultCode switch
        {
            0 or 1 => ExternalIdentityCompletionOutcome.Success,
            2 => ExternalIdentityCompletionOutcome.AccountLinkRequired,
            3 => ExternalIdentityCompletionOutcome.AccountUnavailable,
            _ => ExternalIdentityCompletionOutcome.InvalidIdentity
        };
        await WriteEventAsync(8, outcome == ExternalIdentityCompletionOutcome.Success ? (byte)0 : (byte)2,
            outcome.ToString().ToLowerInvariant(), record.UserId, context, nowUtc, cancellationToken);
        return new ExternalIdentityCompletionResult(
            outcome,
            outcome == ExternalIdentityCompletionOutcome.Success ? rawHandoff : null);
    }

    public async Task<ExternalIdentityLinkOutcome> LinkExternalIdentityAsync(
        Guid publicUserId,
        ExternalIdentityInput input,
        ClientRequestContext context,
        CancellationToken cancellationToken)
    {
        if (!IsValidExternalIdentity(input)) return ExternalIdentityLinkOutcome.InvalidIdentity;
        var nowUtc = UtcNow();
        var record = await _repository.LinkExternalIdentityAsync(
            publicUserId,
            input with
            {
                Provider = input.Provider.Trim().ToLowerInvariant(),
                Issuer = input.Issuer.Trim(),
                Subject = input.Subject.Trim(),
                Email = input.Email.Trim(),
                DisplayName = input.DisplayName.Trim()
            },
            nowUtc,
            cancellationToken);
        var outcome = record.ResultCode switch
        {
            0 => ExternalIdentityLinkOutcome.Success,
            1 => ExternalIdentityLinkOutcome.IdentityAlreadyLinked,
            2 => ExternalIdentityLinkOutcome.ProviderAlreadyLinked,
            3 => ExternalIdentityLinkOutcome.AccountUnavailable,
            4 => ExternalIdentityLinkOutcome.AlreadyLinkedToCurrentAccount,
            _ => ExternalIdentityLinkOutcome.InvalidIdentity
        };
        var accepted = outcome is ExternalIdentityLinkOutcome.Success or
            ExternalIdentityLinkOutcome.AlreadyLinkedToCurrentAccount;
        await WriteEventAsync(8, accepted ? (byte)0 : (byte)2,
            $"link_{outcome.ToString().ToLowerInvariant()}", record.UserId, context, nowUtc, cancellationToken);
        return outcome;
    }

    public async Task<LoginResult> ExchangeExternalHandoffAsync(
        string handoffCode,
        ClientRequestContext context,
        CancellationToken cancellationToken)
    {
        if (!IsPlausibleOpaqueToken(handoffCode)) return new LoginResult(LoginOutcome.InvalidCredentials);
        var nowUtc = UtcNow();
        var record = await _repository.ConsumeExternalHandoffAsync(
            SecureTokenGenerator.HashOpaqueToken(handoffCode), nowUtc, cancellationToken);
        if (record.ResultCode != 0 || record.UserId is null)
        {
            await WriteEventAsync(8, 1, "invalid_external_handoff", record.UserId, context, nowUtc, cancellationToken);
            return new LoginResult(LoginOutcome.InvalidCredentials);
        }

        var user = await _repository.FindByIdAsync(record.UserId.Value, cancellationToken);
        if (user is null || user.Status != UserStatus.Active)
            return new LoginResult(LoginOutcome.InvalidCredentials);

        await _repository.RecordSuccessfulLoginAsync(user.Id, nowUtc, cancellationToken);
        var roles = await _repository.GetRolesAsync(user.Id, cancellationToken);
        var result = await CompletePrimaryAuthenticationAsync(user, roles, context, nowUtc, cancellationToken);
        await WriteEventAsync(8, result.Outcome == LoginOutcome.Success ? (byte)0 : (byte)2,
            "external_exchange", user.Id, context, nowUtc, cancellationToken);
        return result;
    }

    private async Task<LoginResult> CompletePrimaryAuthenticationAsync(
        PlatformUser user,
        IReadOnlyCollection<string> roles,
        ClientRequestContext context,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        var requiresMfa = roles.Any(PlatformRoles.RequiresMfa);
        if (requiresMfa && !user.TwoFactorEnabled)
        {
            var setupToken = _jwtTokenIssuer.Issue(user, roles, Guid.NewGuid(), false, "mfa_setup");
            return new LoginResult(LoginOutcome.MfaSetupRequired, MfaSetupToken: setupToken.Token);
        }

        if (user.TwoFactorEnabled)
        {
            var rawChallenge = SecureTokenGenerator.GenerateOpaqueToken();
            var expiry = nowUtc.AddMinutes(_options.Mfa.ChallengeMinutes);
            await _repository.CreateMfaChallengeAsync(
                user.Id, user.SecurityVersion, SecureTokenGenerator.HashOpaqueToken(rawChallenge),
                expiry, checked((short)_options.Mfa.MaxAttempts), HashIp(context), nowUtc, cancellationToken);
            return new LoginResult(LoginOutcome.MfaRequired,
                MfaChallengeToken: rawChallenge, MfaChallengeExpiresAtUtc: expiry);
        }

        return await CreateSessionAsync(user, roles, false, context, nowUtc, cancellationToken);
    }

    private bool IsValidExternalIdentity(ExternalIdentityInput input)
    {
        if (!_options.External.Entra.Enabled ||
            !string.Equals(input.Provider, "entra", StringComparison.OrdinalIgnoreCase) ||
            !EntraAuthenticationOptions.IsSupportedTokenIssuer(input.Issuer))
            return false;
        return input.Subject.Length is > 0 and <= 255 && IsValidEmail(input.Email) && input.Email.Length <= 320 &&
               !string.IsNullOrWhiteSpace(input.DisplayName) && input.DisplayName.Length <= 150;
    }

    private async Task<LoginResult> CreateSessionAsync(
        PlatformUser user,
        IReadOnlyCollection<string> roles,
        bool mfaAuthenticated,
        ClientRequestContext context,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        var jwtId = Guid.NewGuid();
        var familyId = Guid.NewGuid();
        var rawRefreshToken = SecureTokenGenerator.GenerateOpaqueToken();
        var refreshExpiry = nowUtc.AddDays(_options.RefreshToken.LifetimeDays);
        var accessToken = _jwtTokenIssuer.Issue(
            user,
            roles,
            jwtId,
            mfaAuthenticated,
            authenticationTimeUtc: nowUtc);

        await _repository.CreateRefreshTokenAsync(
            new RefreshTokenDescriptor(
                user.Id,
                user.SecurityVersion,
                mfaAuthenticated,
                mfaAuthenticated ? nowUtc : null,
                familyId,
                SecureTokenGenerator.HashOpaqueToken(rawRefreshToken),
                jwtId,
                refreshExpiry,
                HashIp(context),
                NormalizeUserAgent(context.UserAgent)),
            nowUtc,
            cancellationToken);

        return new LoginResult(
            LoginOutcome.Success,
            BuildSession(user, roles, accessToken),
            rawRefreshToken);
    }

    private async Task ResendVerificationInternalAsync(
        string normalizedEmail,
        ClientRequestContext context,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        var rawToken = SecureTokenGenerator.GenerateOpaqueToken();
        var record = await _repository.IssueSecurityTokenAsync(
            normalizedEmail,
            VerifyEmailPurpose,
            SecureTokenGenerator.HashOpaqueToken(rawToken),
            nowUtc.AddHours(_options.SecurityToken.VerificationHours),
            HashIp(context),
            nowUtc,
            cancellationToken);

        if (record.ResultCode == 0 && record.Email is not null && record.DisplayName is not null)
        {
            await _emailSender.SendVerificationAsync(
                record.Email,
                record.DisplayName,
                rawToken,
                cancellationToken);
        }
    }

    private async Task<IReadOnlyCollection<PasswordValidationFailure>> ValidateRegistrationAsync(
        RegistrationInput input,
        CancellationToken cancellationToken)
    {
        var failures = new List<PasswordValidationFailure>();
        var email = input.Email?.Trim() ?? string.Empty;
        var displayName = input.DisplayName?.Trim() ?? string.Empty;
        var preferredLocale = input.PreferredLocale?.Trim() ?? string.Empty;

        if (!IsValidEmail(email) || email.Length > 320)
        {
            failures.Add(new PasswordValidationFailure("InvalidEmail", "El correo no es válido."));
        }

        if (string.IsNullOrWhiteSpace(displayName) || displayName.Length > 150)
        {
            failures.Add(new PasswordValidationFailure(
                "InvalidDisplayName",
                "El nombre debe contener entre 1 y 150 caracteres."));
        }

        if (string.IsNullOrWhiteSpace(preferredLocale) || preferredLocale.Length > 10)
        {
            failures.Add(new PasswordValidationFailure("InvalidLocale", "El idioma preferido no es válido."));
        }

        var user = new PlatformUser
        {
            Email = email,
            NormalizedEmail = IsValidEmail(email)
                ? _userManager.NormalizeEmail(email)
                : string.Empty,
            DisplayName = displayName
        };
        failures.AddRange(await ValidatePasswordAsync(user, input.Password, cancellationToken));
        return failures;
    }

    private async Task<IReadOnlyCollection<PasswordValidationFailure>> ValidatePasswordAsync(
        PlatformUser user,
        string password,
        CancellationToken cancellationToken)
    {
        if (password is null || password.Length > 128)
        {
            return
            [
                new PasswordValidationFailure(
                    "PasswordTooLong",
                    "La contraseña no puede superar 128 caracteres.")
            ];
        }

        var failures = new List<PasswordValidationFailure>();
        foreach (var validator in _userManager.PasswordValidators)
        {
            var result = await validator.ValidateAsync(_userManager, user, password);
            if (!result.Succeeded)
            {
                failures.AddRange(result.Errors.Select(error =>
                    new PasswordValidationFailure(error.Code, error.Description)));
            }
        }

        cancellationToken.ThrowIfCancellationRequested();
        return failures;
    }

    private async Task<PlatformUser> RequireActiveUserAsync(
        Guid publicUserId,
        CancellationToken cancellationToken)
    {
        var user = await _repository.FindByPublicIdAsync(publicUserId, cancellationToken);
        return user is { Status: UserStatus.Active }
            ? user
            : throw new InvalidOperationException("The authenticated account is unavailable.");
    }

    private AccessSession BuildSession(
        PlatformUser user,
        IReadOnlyCollection<string> roles,
        IssuedAccessToken accessToken)
    {
        return new AccessSession(
            accessToken.Token,
            accessToken.ExpiresAtUtc,
            BuildAuthenticatedUser(user, roles));
    }

    private static AuthenticatedUser BuildAuthenticatedUser(
        PlatformUser user,
        IReadOnlyCollection<string> roles)
    {
        return new AuthenticatedUser(
            user.PublicId,
            user.Email,
            user.DisplayName,
            user.PreferredLocale,
            roles,
            user.TwoFactorEnabled);
    }

    private byte[]? HashIp(ClientRequestContext context)
    {
        return _tokenGenerator.HashIpAddress(context.IpAddress);
    }

    private DateTime UtcNow()
    {
        return _timeProvider.GetUtcNow().UtcDateTime;
    }

    private void VerifyDummyPassword(string? password)
    {
        var boundedPassword = password is { Length: <= 128 } ? password : string.Empty;
        _ = _passwordHasher.VerifyHashedPassword(
            new PlatformUser(),
            _dummyPasswordHash,
            boundedPassword);
    }

    private async Task WriteEventAsync(
        byte eventType,
        byte outcome,
        string? reasonCode,
        long? userId,
        ClientRequestContext context,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        try
        {
            await _repository.WriteAuthenticationEventAsync(
                userId,
                eventType,
                outcome,
                reasonCode,
                HashIp(context),
                NormalizeUserAgent(context.UserAgent),
                context.CorrelationId,
                nowUtc,
                cancellationToken);
        }
        catch (AuthenticationDataException exception)
        {
            _logger.LogWarning(
                "Authentication audit persistence failed. Operation={Operation} SqlError={SqlError}",
                exception.Operation,
                exception.SqlErrorNumber);
        }
    }

    private static bool IsPlausibleOpaqueToken(string? token)
    {
        return !string.IsNullOrWhiteSpace(token) && token.Length is >= 32 and <= 200;
    }

    private static bool IsValidEmail(string? email)
    {
        return !string.IsNullOrWhiteSpace(email) &&
               MailAddress.TryCreate(email.Trim(), out var parsed) &&
               string.Equals(parsed.Address, email.Trim(), StringComparison.OrdinalIgnoreCase);
    }

    private static string? NormalizeUserAgent(string? userAgent)
    {
        if (string.IsNullOrWhiteSpace(userAgent))
        {
            return null;
        }

        var trimmed = userAgent.Trim();
        return trimmed.Length <= 300 ? trimmed : trimmed[..300];
    }
}
