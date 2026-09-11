import { getApiBaseUrl } from '@/api/api-config'

// Leave room for the on-demand SQL database to resume while bounding a held lock.
export const AUTH_SESSION_REQUEST_TIMEOUT_MS = 120_000

// Serialize cookie rotation/mutation across tabs without sharing tokens or writing storage.
export function withAuthSessionLock<T>(operation: () => Promise<T>): Promise<T> {
  const locks = globalThis.navigator?.locks
  if (!locks?.request) return operation()
  const apiOrigin = new URL(getApiBaseUrl(), window.location.href).origin
  return locks.request(`funding-platform:auth-cookie:${apiOrigin}`, { mode: 'exclusive' }, operation)
}
