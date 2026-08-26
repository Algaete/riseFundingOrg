import { clearAuthSession, setAuthenticatedSession } from '@/features/auth/auth-session'
import { adminUsersApi } from '@/features/admin-users/admin-users-api'

describe('adminUsersApi', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    clearAuthSession()
  })

  it('usa una sola vez el prefijo API y conserva filtros y no-store', async () => {
    setAuthenticatedSession({
      status: 'authenticated',
      accessToken: 'admin-test-token',
      accessTokenExpiresAtUtc: '2027-08-26T12:00:00Z',
      user: {
        publicId: '11111111-1111-1111-1111-111111111111',
        email: 'admin@example.test',
        displayName: 'Admin',
        preferredLocale: 'es-CL',
        roles: ['Admin'],
        mfaEnabled: true,
      },
    })
    const fetchMock = vi.fn((_input: RequestInfo | URL, _init?: RequestInit) =>
      Promise.resolve(new Response(JSON.stringify({
        items: [], totalCount: 0, page: 2, pageSize: 25,
      }), { status: 200, headers: { 'Content-Type': 'application/json' } })))
    vi.stubGlobal('fetch', fetchMock)

    await adminUsersApi.list({
      q: 'Alfonso', status: 2, role: 'SuperAdmin', page: 2, pageSize: 25,
    })

    expect(fetchMock).toHaveBeenCalledOnce()
    const [input, init] = fetchMock.mock.calls[0]
    const url = String(input)
    expect(url).toContain('/api/v1/admin/users?')
    expect(url).not.toContain('/api/v1/api/v1/')
    expect(url).toContain('q=Alfonso')
    expect(url).toContain('status=2')
    expect(url).toContain('role=SuperAdmin')
    expect(url).toContain('page=2')
    expect(init?.cache).toBe('no-store')
    expect(new Headers(init?.headers).get('Authorization')).toBe('Bearer admin-test-token')
  })
})
