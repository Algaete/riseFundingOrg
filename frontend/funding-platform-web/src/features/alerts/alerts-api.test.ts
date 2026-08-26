import { clearAuthSession, setAuthenticatedSession } from '@/features/auth/auth-session'
import { alertsApi, toFundingSearch, type SavedSearchWrite } from '@/features/alerts/alerts-api'

const organizationId = '51ea2f6f-b1af-4e09-856c-6dcbdcfc812f'
const savedSearchId = 'f5b75d2c-4c84-4ca3-91f7-e9c182fdff2c'

const savedSearch: SavedSearchWrite = {
  name: 'Fondos de agua', query: 'agua', sponsor: null,
  minimumAmount: null, maximumAmount: null, currency: null,
  closingFrom: null, closingTo: null, onlyOpen: true, sort: 'relevance',
  countryIds: [152], regionIds: [], categoryIds: [], tagIds: [],
  beneficiaryTypeIds: [], projectTypeIds: [], fundingTypeIds: [],
  organizationTypeIds: [], funderIds: [],
}

function authenticate() {
  setAuthenticatedSession({
    status: 'authenticated',
    accessToken: 'alert-test-token',
    accessTokenExpiresAtUtc: '2027-08-25T12:00:00Z',
    user: {
      publicId: '89b8d22a-472c-42e4-b034-c772ce3bb08e',
      email: 'member@example.test', displayName: 'Miembro demo',
      preferredLocale: 'es-CL', roles: ['Professional'], mfaEnabled: false,
    },
  })
}

describe('alertsApi', () => {
  afterEach(() => { vi.unstubAllGlobals(); clearAuthSession() })

  it('mantiene tenant, no-store, idempotencia, ETag y baja POST sin filtrar tokens', async () => {
    authenticate()
    const fetchMock = vi.fn((_input: RequestInfo | URL, init?: RequestInit) =>
      Promise.resolve(new Response(init?.method === 'DELETE' || String(_input).includes('/unsubscribe')
        ? null
        : JSON.stringify({}), {
        status: init?.method === 'DELETE' || String(_input).includes('/unsubscribe') ? 204 : 200,
        headers: { 'Content-Type': 'application/json' },
      })))
    vi.stubGlobal('fetch', fetchMock)

    await alertsApi.list(organizationId)
    await alertsApi.get(organizationId, savedSearchId)
    await alertsApi.create(organizationId, savedSearch, 'saved-search-command-001')
    await alertsApi.update(organizationId, savedSearchId, savedSearch, '"etag-1"')
    await alertsApi.putAlert(organizationId, savedSearchId, 8, 'America/Santiago')
    await alertsApi.deleteAlert(organizationId, savedSearchId)
    await alertsApi.notifications(organizationId)
    await alertsApi.unsubscribe('signed-one-purpose-token')

    for (const [input, init] of fetchMock.mock.calls.slice(0, 7)) {
      expect(String(input)).toContain(`/organizations/${organizationId}/`)
      expect(init?.cache).toBe('no-store')
      expect(new Headers(init?.headers).get('Authorization')).toBe('Bearer alert-test-token')
    }
    expect(new Headers(fetchMock.mock.calls[2][1]?.headers).get('Idempotency-Key'))
      .toBe('saved-search-command-001')
    expect(new Headers(fetchMock.mock.calls[3][1]?.headers).get('If-Match'))
      .toBe('"etag-1"')
    expect(String(fetchMock.mock.calls[7][0])).toContain('/alerts/unsubscribe')
    expect(fetchMock.mock.calls[7][1]?.method).toBe('POST')
    expect(String(fetchMock.mock.calls[7][1]?.body)).toContain('signed-one-purpose-token')
    expect(String(fetchMock.mock.calls[7][0])).not.toContain('signed-one-purpose-token')
  })

  it('convierte una búsqueda guardada al contrato de catálogo sin conservar paginación', () => {
    expect(toFundingSearch(savedSearch)).toEqual(expect.objectContaining({
      query: 'agua', onlyOpen: true, sort: 'relevance', countryIds: [152],
      pageNumber: 1, pageSize: 12,
    }))
  })
})
