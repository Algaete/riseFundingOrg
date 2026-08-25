import { clearAuthSession, setAuthenticatedSession } from '@/features/auth/auth-session'
import { matchingApi } from '@/features/matching/matching-api'

const organizationId = '51ea2f6f-b1af-4e09-856c-6dcbdcfc812f'
const projectId = 'bd351806-9139-4524-bc01-93c3676729cb'
const matchingRunId = 'f4299117-a4b5-4dfc-b89f-1a3942268f12'

function authenticate() {
  setAuthenticatedSession({
    status: 'authenticated',
    accessToken: 'matching-test-token',
    accessTokenExpiresAtUtc: '2027-08-24T12:00:00Z',
    user: {
      publicId: '89b8d22a-472c-42e4-b034-c772ce3bb08e',
      email: 'member@example.test',
      displayName: 'Miembro demo',
      preferredLocale: 'es-CL',
      roles: ['Professional'],
      mfaEnabled: false,
    },
  })
}

describe('matchingApi', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    clearAuthSession()
  })

  it('mantiene tenant y proyecto en la ruta, usa sesión completa y evita caché', async () => {
    authenticate()
    const fetchMock = vi.fn((_input: RequestInfo | URL, init?: RequestInit) =>
      Promise.resolve(new Response(JSON.stringify(init?.method === 'POST'
        ? { run: { run: {} }, wasReplay: false }
        : {}), {
        status: init?.method === 'POST' ? 201 : 200,
        headers: { 'Content-Type': 'application/json' },
      })))
    vi.stubGlobal('fetch', fetchMock)

    await matchingApi.list(organizationId, projectId, 2, 10)
    await matchingApi.get(organizationId, projectId, matchingRunId)
    await matchingApi.calculate(organizationId, projectId, 'stable-command-key-123456')

    const [listUrl, listInit] = fetchMock.mock.calls[0]
    expect(String(listUrl)).toContain(`/organizations/${organizationId}/projects/${projectId}/matching-runs?page=2&pageSize=10`)
    expect(listInit?.method).toBe('GET')
    expect(listInit?.cache).toBe('no-store')
    expect(new Headers(listInit?.headers).get('Authorization')).toBe('Bearer matching-test-token')

    const [detailUrl, detailInit] = fetchMock.mock.calls[1]
    expect(String(detailUrl)).toContain(`/matching-runs/${matchingRunId}`)
    expect(detailInit?.cache).toBe('no-store')

    const [createUrl, createInit] = fetchMock.mock.calls[2]
    expect(String(createUrl)).toContain(`/organizations/${organizationId}/projects/${projectId}/matching-runs`)
    expect(createInit?.method).toBe('POST')
    expect(createInit?.cache).toBe('no-store')
    expect(createInit?.body).toBeUndefined()
    expect(new Headers(createInit?.headers).get('Idempotency-Key')).toBe('stable-command-key-123456')
  })
})
