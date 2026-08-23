import { afterEach, describe, expect, it, vi } from 'vitest'

import {
  getAuthState,
  initializeAuthSession,
  setAuthenticatedSession,
} from '@/features/auth/auth-session'

const microsoftSession = {
  status: 'authenticated' as const,
  accessToken: 'microsoft-access-token',
  accessTokenExpiresAtUtc: '2026-08-21T17:00:00Z',
  user: {
    publicId: '11111111-1111-1111-1111-111111111111',
    email: 'user@example.com',
    displayName: 'Microsoft User',
    preferredLocale: 'es-CL',
    roles: ['User'],
    mfaEnabled: false,
  },
}

describe('auth session concurrency', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('does not erase a new Microsoft session when an older refresh fails later', async () => {
    let finishRefresh: ((response: Response) => void) | undefined
    const pendingRefresh = new Promise<Response>((resolve) => {
      finishRefresh = resolve
    })
    vi.stubGlobal('fetch', vi.fn().mockReturnValue(pendingRefresh))

    const initialization = initializeAuthSession()
    setAuthenticatedSession(microsoftSession)
    finishRefresh?.(new Response(null, { status: 401 }))

    await expect(initialization).resolves.toBeNull()
    expect(getAuthState()).toMatchObject({
      status: 'authenticated',
      session: { accessToken: 'microsoft-access-token' },
    })
  })

  it('does not overwrite a newer session while parsing a successful refresh', async () => {
    let finishJson: ((response: unknown) => void) | undefined
    const pendingJson = new Promise<unknown>((resolve) => {
      finishJson = resolve
    })
    const json = vi.fn().mockReturnValue(pendingJson)
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      status: 200,
      ok: true,
      json,
    }))

    const initialization = initializeAuthSession()
    await vi.waitFor(() => expect(json).toHaveBeenCalledOnce())
    setAuthenticatedSession(microsoftSession)
    finishJson?.({
      ...microsoftSession,
      accessToken: 'obsolete-refresh-token',
    })

    await expect(initialization).resolves.toBeNull()
    expect(getAuthState().session?.accessToken).toBe('microsoft-access-token')
  })
})
