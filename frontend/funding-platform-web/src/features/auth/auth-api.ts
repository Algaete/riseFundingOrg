import { getExternalAuthBaseUrl } from '@/api/api-config'
import { apiClient, HttpClient } from '@/api/http-client'
import { AUTH_SESSION_REQUEST_TIMEOUT_MS, withAuthSessionLock } from './auth-session-lock'
import type {
  AuthenticatedUser,
  AuthenticationResponse,
} from '@/features/auth/auth-session'

export interface AcceptedResponse {
  message: string
}

export interface MfaSetupResponse {
  sharedKey: string
  authenticatorUri: string
}

export interface MfaConfirmationResponse {
  recoveryCodes: string[]
}

export interface ExternalProvider {
  code: string
  displayName: string
  enabled: boolean
}

const externalAuthClient = new HttpClient(getExternalAuthBaseUrl())

export const authApi = {
  register(input: {
    email: string
    displayName: string
    password: string
    preferredLocale: string
  }) {
    return apiClient.post<AcceptedResponse>('auth/register', input)
  },
  login(input: { email: string; password: string }) {
    return withAuthSessionLock(() => apiClient.post<AuthenticationResponse>('auth/login', input, { signal: AbortSignal.timeout(AUTH_SESSION_REQUEST_TIMEOUT_MS) }))
  },
  completeMfa(input: { challengeToken: string; code: string }) {
    return withAuthSessionLock(() => apiClient.post<AuthenticationResponse>('auth/mfa/challenge', input, { signal: AbortSignal.timeout(AUTH_SESSION_REQUEST_TIMEOUT_MS) }))
  },
  verifyEmail(token: string) {
    return apiClient.post<AcceptedResponse>('auth/verify-email', { token })
  },
  resendVerification(email: string) {
    return apiClient.post<AcceptedResponse>('auth/resend-verification', { email })
  },
  forgotPassword(email: string) {
    return apiClient.post<AcceptedResponse>('auth/forgot-password', { email })
  },
  resetPassword(token: string, newPassword: string) {
    return apiClient.post<AcceptedResponse>('auth/reset-password', {
      token,
      newPassword,
    })
  },
  getCurrentUser() {
    return apiClient.get<AuthenticatedUser>('me')
  },
  logout() {
    return withAuthSessionLock(() => apiClient.post<void>('auth/logout', undefined, { signal: AbortSignal.timeout(AUTH_SESSION_REQUEST_TIMEOUT_MS) }))
  },
  logoutAll() {
    return withAuthSessionLock(() => apiClient.post<void>('auth/logout-all', undefined, { signal: AbortSignal.timeout(AUTH_SESSION_REQUEST_TIMEOUT_MS) }))
  },
  beginMfaSetup() {
    return apiClient.post<MfaSetupResponse>('me/mfa/setup')
  },
  confirmMfaSetup(code: string) {
    return apiClient.post<MfaConfirmationResponse>('me/mfa/confirm', { code })
  },
  externalProviders() {
    return apiClient.get<ExternalProvider[]>('auth/external/providers')
  },
  exchangeExternalHandoff(code: string) {
    return withAuthSessionLock(() => apiClient.post<AuthenticationResponse>('auth/external/exchange', { code }, { signal: AbortSignal.timeout(AUTH_SESSION_REQUEST_TIMEOUT_MS) }))
  },
  async createExternalLinkIntent() {
    const result = await externalAuthClient.post<{ startUrl: string }>('me/external/entra/link-intents')
    return {
      startUrl: new URL(result.startUrl, `${getExternalAuthBaseUrl()}/`).toString(),
    }
  },
}
