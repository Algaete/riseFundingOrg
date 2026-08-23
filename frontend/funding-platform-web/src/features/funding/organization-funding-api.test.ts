import { clearAuthSession, setAuthenticatedSession } from '@/features/auth/auth-session'
import {
  organizationFundingApi,
  serializeFundingSearch,
} from '@/features/funding/organization-funding-api'

const organizationId = '51ea2f6f-b1af-4e09-856c-6dcbdcfc812f'
const opportunityId = 'f5b75d2c-4c84-4ca3-91f7-e9c182fdff2c'

function authenticate() {
  setAuthenticatedSession({
    status: 'authenticated',
    accessToken: 'workspace-funding-token',
    accessTokenExpiresAtUtc: '2026-08-23T12:00:00Z',
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

describe('organizationFundingApi', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    clearAuthSession()
  })

  it('serializa filtros allowlist con arrays CSV y nombres de contrato exactos', () => {
    const result = serializeFundingSearch({
      query: '  agua rural ',
      countryIds: [152, 32],
      regionIds: [7],
      categoryIds: [7],
      tagIds: [11, 12],
      beneficiaryTypeIds: [4, 9],
      projectTypeIds: [6],
      fundingTypeIds: [3],
      organizationTypeIds: [2],
      funderIds: ['2ff2809c-900c-49ea-8282-15f2c43716e8'],
      minimumAmount: 1000,
      maximumAmount: 5000,
      currency: 'USD',
      closingFrom: '2026-09-01',
      closingTo: '2027-02-15',
      onlyOpen: true,
      sort: 'closing-soon',
      pageNumber: 2,
      pageSize: 24,
    })

    expect(result.get('q')).toBe('agua rural')
    expect(result.get('countryIds')).toBe('152,32')
    expect(result.get('regionIds')).toBe('7')
    expect(result.get('categoryIds')).toBe('7')
    expect(result.get('tagIds')).toBe('11,12')
    expect(result.get('beneficiaryTypeIds')).toBe('4,9')
    expect(result.get('projectTypeIds')).toBe('6')
    expect(result.get('fundingTypeIds')).toBe('3')
    expect(result.get('organizationTypeIds')).toBe('2')
    expect(result.get('funderIds')).toBe('2ff2809c-900c-49ea-8282-15f2c43716e8')
    expect(result.get('minAmount')).toBe('1000')
    expect(result.get('maxAmount')).toBe('5000')
    expect(result.get('currency')).toBe('USD')
    expect(result.get('closingFrom')).toBe('2026-09-01')
    expect(result.get('closingTo')).toBe('2027-02-15')
    expect(result.get('onlyOpen')).toBe('true')
    expect(result.get('sort')).toBe('closing-soon')
    expect(result.get('page')).toBe('2')
    expect(result.has('pageNumber')).toBe(false)
  })

  it('aísla las operaciones por organización, usa bearer y evita caché HTTP', async () => {
    authenticate()
    const fetchMock = vi.fn((_input: RequestInfo | URL, _init?: RequestInit) =>
      Promise.resolve(new Response(null, { status: 204 })))
    vi.stubGlobal('fetch', fetchMock)

    await organizationFundingApi.addFavorite(organizationId, opportunityId)
    await organizationFundingApi.removeFavorite(organizationId, opportunityId)

    const [putUrl, putInit] = fetchMock.mock.calls[0]
    expect(String(putUrl)).toContain(`/organizations/${organizationId}/favorites/${opportunityId}`)
    expect(putInit?.method).toBe('PUT')
    expect(putInit?.cache).toBe('no-store')
    expect(new Headers(putInit?.headers).get('Authorization')).toBe('Bearer workspace-funding-token')

    const [, deleteInit] = fetchMock.mock.calls[1]
    expect(deleteInit?.method).toBe('DELETE')
    expect(deleteInit?.cache).toBe('no-store')
  })
})
