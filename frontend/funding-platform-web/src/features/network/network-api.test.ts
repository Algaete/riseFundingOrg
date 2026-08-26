import { clearAuthSession, setAuthenticatedSession } from '@/features/auth/auth-session'
import { networkApi, type OrganizationConnection } from './network-api'

const organizationId = '51ea2f6f-b1af-4e09-856c-6dcbdcfc812f'
const connection: OrganizationConnection = {
  id: 'f4299117-a4b5-4dfc-b89f-1a3942268f12', direction: 'incoming', status: 'pending',
  purpose: 'partnership', message: 'Buscamos una alianza técnica segura.',
  counterpartyOrganizationId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  counterpartyOrganizationName: 'Fundación Agua', counterpartyIsPublic: true,
  requesterProjectId: null, requesterProjectSlug: null, requesterProjectTitle: null,
  canRespond: true, canCancel: false, canBlock: true,
  createdAtUtc: '2026-08-25T12:00:00Z', updatedAtUtc: '2026-08-25T12:00:00Z',
  actionedAtUtc: null, eTag: '"0102030405060708"',
}

describe('networkApi', () => {
  afterEach(() => { vi.unstubAllGlobals(); clearAuthSession() })

  it('mantiene tenant, no-store, idempotencia y ETag en toda la superficie privada', async () => {
    setAuthenticatedSession({ status: 'authenticated', accessToken: 'network-token',
      accessTokenExpiresAtUtc: '2027-08-25T12:00:00Z', user: {
        publicId: '89b8d22a-472c-42e4-b034-c772ce3bb08e', email: 'member@example.test',
        displayName: 'Miembro', preferredLocale: 'es-CL', roles: ['Professional'], mfaEnabled: false,
      } })
    const fetchMock = vi.fn((_input: RequestInfo | URL, _init?: RequestInit) => Promise.resolve(new Response(JSON.stringify({}), {
      status: 200, headers: { 'Content-Type': 'application/json' },
    })))
    vi.stubGlobal('fetch', fetchMock)

    await networkApi.settings(organizationId)
    await networkApi.putSettings(organizationId, { isDiscoverable: true, allowRequests: true }, connection.eTag)
    await networkApi.directory(organizationId, 'agua')
    await networkApi.connections(organizationId, 'incoming')
    await networkApi.create(organizationId, { recipientOrganizationId: connection.counterpartyOrganizationId,
      requesterProjectId: null, purpose: 'partnership', message: connection.message }, 'organization-connect-0001')
    await networkApi.action(organizationId, connection, 'accept')

    for (const [input, init] of fetchMock.mock.calls) {
      expect(String(input)).toContain(`/organizations/${organizationId}/network/`)
      expect(init?.cache).toBe('no-store')
      expect(new Headers(init?.headers).get('Authorization')).toBe('Bearer network-token')
    }
    expect(new Headers(fetchMock.mock.calls[1][1]?.headers).get('If-Match')).toBe(connection.eTag)
    expect(new Headers(fetchMock.mock.calls[4][1]?.headers).get('Idempotency-Key')).toBe('organization-connect-0001')
    expect(new Headers(fetchMock.mock.calls[5][1]?.headers).get('If-Match')).toBe(connection.eTag)
  })
})
