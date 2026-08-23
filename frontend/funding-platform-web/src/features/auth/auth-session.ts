import { getApiBaseUrl } from '@/api/api-config'

export interface AuthenticatedUser {
  publicId: string
  email: string
  displayName: string
  preferredLocale: string
  roles: string[]
  mfaEnabled: boolean
}

export interface AuthenticationResponse {
  status: 'authenticated' | 'mfa_required' | 'mfa_setup_required'
  accessToken?: string
  accessTokenExpiresAtUtc?: string
  user?: AuthenticatedUser
  mfaChallengeToken?: string
  mfaChallengeExpiresAtUtc?: string
  mfaSetupToken?: string
}

export interface AuthSession {
  accessToken: string
  accessTokenExpiresAtUtc: string
  user: AuthenticatedUser
}

export interface AuthState {
  status: 'initializing' | 'guest' | 'authenticated'
  session: AuthSession | null
}

let state: AuthState = { status: 'initializing', session: null }
let limitedAccessToken: string | null = null
let authStateVersion = 0
let initializePromise: Promise<AuthSession | null> | null = null
let refreshPromise: Promise<AuthSession | null> | null = null
const listeners = new Set<() => void>()

function emit() {
  listeners.forEach((listener) => listener())
}

export function subscribeToAuth(listener: () => void) {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function getAuthState() {
  return state
}

export function getAccessToken() {
  return state.session?.accessToken ?? limitedAccessToken
}

export function hasLimitedAccessToken() {
  return limitedAccessToken !== null && state.session === null
}

export function setLimitedAccessToken(token: string) {
  authStateVersion += 1
  limitedAccessToken = token
  state = { status: 'guest', session: null }
  emit()
}

export function setAuthenticatedSession(response: AuthenticationResponse): AuthSession {
  if (!response.accessToken || !response.accessTokenExpiresAtUtc || !response.user) {
    throw new Error('La API devolvió una sesión incompleta.')
  }

  const session: AuthSession = {
    accessToken: response.accessToken,
    accessTokenExpiresAtUtc: response.accessTokenExpiresAtUtc,
    user: response.user,
  }
  authStateVersion += 1
  limitedAccessToken = null
  state = {
    status: 'authenticated',
    session,
  }
  emit()
  return session
}

export function clearAuthSession() {
  authStateVersion += 1
  limitedAccessToken = null
  state = { status: 'guest', session: null }
  emit()
}

async function requestRefresh(): Promise<AuthSession | null> {
  const versionAtStart = authStateVersion
  const send = () => fetch(`${getApiBaseUrl()}/auth/refresh`, {
      method: 'POST',
      headers: { Accept: 'application/json' },
      credentials: 'include',
    })

  let response = await send()
  if (response.status === 409) {
    await new Promise((resolve) => window.setTimeout(resolve, 150))
    if (authStateVersion !== versionAtStart) return null
    response = await send()
  }

  // A login, logout or MFA transition completed while this refresh was in
  // flight. Its result is newer and must never be overwritten by this request.
  if (authStateVersion !== versionAtStart) return null

  if (!response.ok) {
    clearAuthSession()
    return null
  }

  const refreshedSession = (await response.json()) as AuthenticationResponse
  if (authStateVersion !== versionAtStart) return null

  return setAuthenticatedSession(refreshedSession)
}

export function refreshAuthSession() {
  if (!refreshPromise) {
    const pendingRefresh = requestRefresh().finally(() => {
      if (refreshPromise === pendingRefresh) {
        refreshPromise = null
      }
    })
    refreshPromise = pendingRefresh
  }
  return refreshPromise
}

export function initializeAuthSession() {
  if (state.session) {
    return Promise.resolve(state.session)
  }

  if (!initializePromise) {
    const versionAtStart = authStateVersion
    initializePromise = refreshAuthSession()
      .catch(() => {
        if (authStateVersion === versionAtStart) {
          clearAuthSession()
        }
        return state.session
      })
      .finally(() => {
        if (
          authStateVersion === versionAtStart &&
          state.status === 'initializing'
        ) {
          state = { status: 'guest', session: null }
          emit()
        }
      })
  }
  return initializePromise
}

export function resetAuthStateForTests() {
  authStateVersion += 1
  state = { status: 'initializing', session: null }
  limitedAccessToken = null
  initializePromise = null
  refreshPromise = null
  emit()
}
