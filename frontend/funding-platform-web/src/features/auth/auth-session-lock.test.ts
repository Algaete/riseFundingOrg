import { afterEach, describe, expect, it, vi } from 'vitest'
import { withAuthSessionLock } from './auth-session-lock'
import { clearAuthSession, getAuthState, initializeAuthSession, refreshAuthSession } from './auth-session'

afterEach(() => vi.unstubAllGlobals())

describe('cross-window session coordination', () => {
  it('uses the same exclusive lock for the API cookie and releases when complete', async () => {
    const request = vi.fn((_name: string, _options: unknown, operation: () => Promise<string>) => operation())
    vi.stubGlobal('navigator', { locks: { request } })
    await expect(withAuthSessionLock(async () => 'complete')).resolves.toBe('complete')
    expect(request).toHaveBeenCalledWith(expect.stringMatching(/^funding-platform:auth-cookie:https?:\/\//), { mode: 'exclusive' }, expect.any(Function))
  })

  it('keeps the existing single-window behavior when Web Locks is unavailable', async () => {
    vi.stubGlobal('navigator', {})
    await expect(withAuthSessionLock(async () => 'complete')).resolves.toBe('complete')
  })

  it('does not retry an operation without the lock if acquiring it fails', async () => {
    const operation = vi.fn()
    vi.stubGlobal('navigator', { locks: { request: vi.fn().mockRejectedValue(new Error('lock unavailable')) } })
    await expect(withAuthSessionLock(operation)).rejects.toThrow('lock unavailable')
    expect(operation).not.toHaveBeenCalled()
  })

  it('coalesces refresh calls while waiting for another window and cancels after local logout', async () => {
    let acquire: (() => void) | undefined
    const request = vi.fn((_name: string, _options: unknown, operation: () => Promise<unknown>) => new Promise(resolve => {
      acquire = () => { void operation().then(resolve) }
    }))
    const fetch = vi.fn()
    vi.stubGlobal('navigator', { locks: { request } })
    vi.stubGlobal('fetch', fetch)
    const initialized = initializeAuthSession()
    const refreshed = refreshAuthSession()
    expect(request).toHaveBeenCalledOnce()
    expect(fetch).not.toHaveBeenCalled()
    clearAuthSession()
    acquire!()
    await expect(initialized).resolves.toBeNull()
    await expect(refreshed).resolves.toBeNull()
    expect(fetch).not.toHaveBeenCalled()
    expect(getAuthState().status).toBe('guest')
  })

  it('bounds network waits so a stalled refresh does not hold every window indefinitely', async () => {
    vi.stubGlobal('navigator', {})
    const fetch = vi.fn().mockResolvedValue(new Response(null, { status: 401 }))
    vi.stubGlobal('fetch', fetch)
    await refreshAuthSession()
    expect(fetch).toHaveBeenCalledWith(expect.stringContaining('/auth/refresh'), expect.objectContaining({
      method: 'POST', credentials: 'include', signal: expect.any(AbortSignal),
    }))
  })
})
