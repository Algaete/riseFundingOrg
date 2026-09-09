import { describe, expect, it } from 'vitest'
import { ApiError } from '@/api/http-client'
import { getAuthErrorKey, getExternalNoticeKey, type AuthOperation } from '@/features/auth/auth-feedback'
import { codeSchema, emailSchema, loginSchema, mfaSetupCodeSchema, registerSchema, resetSchema } from '@/features/auth/auth-validation'
import { en } from '@/i18n/en'
import { es } from '@/i18n/es'

describe('localized authentication protocol messages', () => {
  it.each([
    [401, 'invalid-credentials', 'login', 'auth.errors.invalidCredentials'],
    [401, 'invalid-credentials', 'challenge', 'auth.errors.invalidChallenge'],
    [403, 'email-verification-required', 'login', 'auth.errors.verificationRequired'],
    [401, 'invalid-session', 'setup', 'auth.errors.invalidSession'],
    [403, 'invalid-origin', 'login', 'auth.errors.invalidOrigin'],
    [503, 'identity-email-disabled', 'register', 'auth.errors.emailDisabled'],
    [503, 'identity-email-disabled', 'forgot', 'auth.errors.emailDisabled'],
    [400, 'invalid-security-token', 'verify', 'auth.errors.invalidVerifyToken'],
    [400, 'invalid-security-token', 'reset', 'auth.errors.invalidResetToken'],
    [401, 'invalid-external-handoff', 'external', 'auth.errors.invalidHandoff'],
    [404, 'external-provider-unavailable', 'external', 'auth.errors.providerUnavailable'],
    [429, 'anything', 'register', 'auth.errors.rateLimited'],
  ] as const)('maps HTTP %s / %s for %s without rendering server text', (status, code, operation, expected) => {
    const error = new ApiError({ status, type: `https://fundingplatform.local/problems/${code}`, title: 'Arbitrary server text', detail: '<script>not a translation</script>' }, new Response(null, { status }))
    expect(getAuthErrorKey(error, operation)).toBe(expected)
  })

  it.each([
    ['PasswordTooShort', 'register', 'auth.validation.passwordMin'],
    ['PasswordTooLong', 'reset', 'auth.validation.passwordMax'],
    ['PasswordRequiresUniqueChars', 'register', 'auth.validation.passwordUnique'],
    ['code', 'setup', 'auth.errors.invalidSetupCode'],
    ['UnknownValidation', 'register', 'auth.validation.invalid'],
  ] as const)('localizes validation code %s', (code, operation, expected) => {
    expect(getAuthErrorKey(new ApiError({ status: 400, title: 'Validation', errors: { [code]: ['Untranslated detail'] } }, new Response(null, { status: 400 })), operation)).toBe(expected)
  })

  it('does not match arbitrary origins, suffixes, wrong HTTP statuses or raw error text', () => {
    for (const [status, type] of [
      [401, 'https://example.invalid/problems/invalid-credentials'],
      [401, 'https://fundingplatform.local/problems/invalid-credentials?extra=true'],
      [500, 'https://fundingplatform.local/problems/invalid-credentials'],
    ] as const) {
      expect(getAuthErrorKey(new ApiError({ status: 401, type, title: 'Private detail' }, new Response(null, { status })), 'login')).toBe('auth.errors.generic')
    }
    expect(getAuthErrorKey(new Error('private network detail'), 'login')).toBe('auth.errors.generic')
  })

  it('keeps unknown SSO notices out of the page', () => {
    expect(getExternalNoticeKey(null)).toBeUndefined()
    expect(getExternalNoticeKey('__proto__')).toBeUndefined()
    expect(getExternalNoticeKey('constructor')).toBeUndefined()
    expect(getExternalNoticeKey('failed')).toBe('auth.external.failed')
  })

  it.each(['register', 'forgot'] satisfies AuthOperation[])('keeps generic account acceptance messages for %s', operation => {
    const key = operation === 'register' ? 'registrationAccepted' : 'recoveryAccepted'
    expect(es.translation.auth.notices[key]).toMatch(/^Si /)
    expect(en.translation.auth.notices[key]).toMatch(/^If /)
  })
})

describe('language-independent authentication validation', () => {
  const validRegistration = { displayName: 'Example', email: 'example@example.test', password: 'Example-password-2026', confirmPassword: 'Example-password-2026' }

  it.each([
    [loginSchema, { email: '', password: '' }, 'auth.validation.emailRequired'],
    [loginSchema, { email: 'a@example.test', password: 'a'.repeat(129) }, 'auth.validation.passwordMax'],
    [registerSchema, { ...validRegistration, displayName: 'a'.repeat(151) }, 'auth.validation.nameMax'],
    [emailSchema, { email: `${'a'.repeat(310)}@example.test` }, 'auth.validation.emailMax'],
    [resetSchema, { password: 'short', confirmPassword: 'short' }, 'auth.validation.passwordMin'],
    [resetSchema, { password: validRegistration.password, confirmPassword: 'different' }, 'auth.validation.passwordMatch'],
    [codeSchema, { code: '1' }, 'auth.validation.codeRequired'],
    [codeSchema, { code: 'a'.repeat(65) }, 'auth.validation.codeMax'],
    [mfaSetupCodeSchema, { code: 'abcdef' }, 'auth.validation.setupCode'],
  ] as const)('uses translation keys for every constraint (%#)', (schema, input, key) => {
    const result = schema.safeParse(input)
    expect(result.success).toBe(false)
    if (!result.success) expect(result.error.issues.map(issue => issue.message)).toContain(key)
  })

  it('preserves valid passwords, trimmed codes, recovery codes and schema limits', () => {
    expect(registerSchema.safeParse(validRegistration).success).toBe(true)
    expect(codeSchema.parse({ code: '  ABCD-EFGH-IJKL  ' }).code).toBe('ABCD-EFGH-IJKL')
    expect(mfaSetupCodeSchema.parse({ code: ' 123456 ' }).code).toBe('123456')
    expect(loginSchema.safeParse({ email: 'a@example.test', password: 'a'.repeat(128) }).success).toBe(true)
  })
})
