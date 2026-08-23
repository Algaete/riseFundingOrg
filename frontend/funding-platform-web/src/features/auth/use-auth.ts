import { useSyncExternalStore } from 'react'

import {
  getAuthState,
  subscribeToAuth,
} from '@/features/auth/auth-session'

export function useAuth() {
  return useSyncExternalStore(subscribeToAuth, getAuthState, getAuthState)
}
