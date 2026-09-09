import { ApiError } from '@/api/http-client'
import type { authEs } from '@/i18n/auth/es'
import type { AuthValidationKey } from '@/features/auth/auth-validation'

export type AuthOperation = 'login' | 'register' | 'forgot' | 'reset' | 'verify' | 'external' | 'challenge' | 'setup'
export type AuthErrorKey = `auth.errors.${keyof typeof authEs.errors}` | AuthValidationKey
const problemBase = 'https://fundingplatform.local/problems/'

// Exact protocol identifiers only: never infer identity or display arbitrary
// server text. Unknown responses retain a safe, localized fallback.
const problemMessages: Record<string, { status: number; key: AuthErrorKey }> = {
  'email-verification-required': { status: 403, key: 'auth.errors.verificationRequired' },
  'invalid-session': { status: 401, key: 'auth.errors.invalidSession' },
  'invalid-origin': { status: 403, key: 'auth.errors.invalidOrigin' },
  'identity-email-disabled': { status: 503, key: 'auth.errors.emailDisabled' },
  'invalid-external-handoff': { status: 401, key: 'auth.errors.invalidHandoff' },
  'external-provider-unavailable': { status: 404, key: 'auth.errors.providerUnavailable' },
}

export function getAuthErrorKey(error: unknown, operation?: AuthOperation): AuthErrorKey {
  if (!(error instanceof ApiError)) return 'auth.errors.generic'
  const { status } = error.response
  const { type, errors } = error.problem
  if (status === 429) return 'auth.errors.rateLimited'
  if (type === `${problemBase}invalid-credentials` && status === 401) {
    return operation === 'challenge' ? 'auth.errors.invalidChallenge' : 'auth.errors.invalidCredentials'
  }
  if (type === `${problemBase}invalid-security-token` && status === 400) {
    if (operation === 'reset') return 'auth.errors.invalidResetToken'
    if (operation === 'verify') return 'auth.errors.invalidVerifyToken'
  }
  for (const [code, message] of Object.entries(problemMessages)) {
    if (type === `${problemBase}${code}` && status === message.status) return message.key
  }
  if (status === 400 && errors && typeof errors === 'object' && !Array.isArray(errors)) {
    if (operation === 'setup' && Object.hasOwn(errors, 'code')) return 'auth.errors.invalidSetupCode'
    if (operation === 'register' || operation === 'reset') {
      if (Object.hasOwn(errors, 'PasswordTooShort')) return 'auth.validation.passwordMin'
      if (Object.hasOwn(errors, 'PasswordTooLong')) return 'auth.validation.passwordMax'
      if (Object.hasOwn(errors, 'PasswordRequiresUniqueChars')) return 'auth.validation.passwordUnique'
    }
    return 'auth.validation.invalid'
  }
  return 'auth.errors.generic'
}

export function getExternalNoticeKey(status: string | null) {
  switch (status) {
    case 'failed': return 'auth.external.failed'
    case 'invalid_identity': return 'auth.external.invalidIdentity'
    case 'account_link_required': return 'auth.external.accountLinkRequired'
    default: return undefined
  }
}
