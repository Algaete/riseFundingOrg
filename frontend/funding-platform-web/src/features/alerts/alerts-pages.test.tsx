import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter } from 'react-router-dom'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { clearAuthSession, setAuthenticatedSession } from '@/features/auth/auth-session'
import { appRoutes } from '@/router'

const organizationId = '51ea2f6f-b1af-4e09-856c-6dcbdcfc812f'
const savedSearchId = 'f5b75d2c-4c84-4ca3-91f7-e9c182fdff2c'

function json(value: unknown, status = 200) {
  return Promise.resolve(new Response(JSON.stringify(value), {
    status,
    headers: { 'Content-Type': 'application/json' },
  }))
}

function authenticate() {
  setAuthenticatedSession({
    status: 'authenticated', accessToken: 'alert-page-token',
    accessTokenExpiresAtUtc: '2027-08-25T12:00:00Z',
    user: {
      publicId: '89b8d22a-472c-42e4-b034-c772ce3bb08e',
      email: 'member@example.test', displayName: 'Miembro demo',
      preferredLocale: 'es-CL', roles: ['Professional'], mfaEnabled: false,
    },
  })
}

describe('búsquedas guardadas y alertas', () => {
  afterEach(() => { vi.unstubAllGlobals(); clearAuthSession() })

  it('conserva la búsqueda cuando el correo del ambiente aún está desactivado', async () => {
    authenticate()
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/organizations')) return json([{
        publicId: organizationId, name: 'Fundación Demo', membershipRole: 'admin',
        profileStatus: 2, profileCompleteness: 100, profileVersion: 2,
        updatedAtUtc: '2026-08-25T10:00:00Z',
      }])
      if (url.pathname.endsWith('/notification-logs')) return json({
        items: [], totalCount: 0, page: 1, pageSize: 20,
      })
      if (url.pathname.endsWith('/saved-searches') && init?.method === 'POST') return json({
        id: savedSearchId, name: 'Fondos de agua',
        filters: {
          name: 'Fondos de agua', query: 'agua', sponsor: null,
          minimumAmount: null, maximumAmount: null, currency: null,
          closingFrom: null, closingTo: null, onlyOpen: true, sort: 'relevance',
          countryIds: [152], regionIds: [], categoryIds: [], tagIds: [],
          beneficiaryTypeIds: [], projectTypeIds: [], fundingTypeIds: [],
          organizationTypeIds: [], funderIds: [],
        },
        alert: null, createdAtUtc: '2026-08-25T12:00:00Z',
        updatedAtUtc: '2026-08-25T12:00:00Z', eTag: '"etag-1"',
      }, 201)
      if (url.pathname.endsWith(`/saved-searches/${savedSearchId}/alert`) && init?.method === 'PUT') {
        return json({
          type: 'https://fundingplatform.local/problems/alerts-disabled',
          title: 'Alertas desactivadas', status: 503,
          detail: 'El envío de alertas todavía no está habilitado en este ambiente.',
        }, 503)
      }
      if (url.pathname.endsWith('/saved-searches')) return json({
        items: [], totalCount: 0, page: 1, pageSize: 50,
      })
      throw new Error(`Unexpected request: ${url.pathname} ${init?.method}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const router = createMemoryRouter(appRoutes, {
      initialEntries: ['/alerts?new=true&q=agua&countryIds=152'],
    })
    render(<App queryClient={createAppQueryClient()} router={router} />)
    const user = userEvent.setup()

    await user.type(await screen.findByRole('textbox', { name: 'Nombre' }), 'Fondos de agua')
    await user.click(screen.getByRole('button', { name: 'Guardar' }))

    expect(await screen.findByText(/La búsqueda quedó guardada; el envío de correo aún no está habilitado/i))
      .toBeInTheDocument()
    const createCall = fetchMock.mock.calls.find(([input, init]) =>
      String(input).endsWith('/saved-searches') && init?.method === 'POST')
    expect(createCall).toBeDefined()
    expect(new Headers(createCall?.[1]?.headers).get('Idempotency-Key'))
      .toMatch(/^saved-search-/)
    expect(String(createCall?.[1]?.body)).toContain('"countryIds":[152]')
    expect(new Headers(createCall?.[1]?.headers).get('Authorization'))
      .toBe('Bearer alert-page-token')
  })

  it('exige confirmación y procesa la baja por POST sin revelar si el token existía', async () => {
    const fetchMock = vi.fn((_input: RequestInfo | URL, _init?: RequestInit) =>
      Promise.resolve(new Response(null, { status: 204 })))
    vi.stubGlobal('fetch', fetchMock)
    const router = createMemoryRouter(appRoutes, {
      initialEntries: ['/alerts/unsubscribe#token=signed-token'],
    })
    render(<App queryClient={createAppQueryClient()} router={router} />)
    const user = userEvent.setup()

    expect(await screen.findByText(/Confirma que quieres dejar de recibir/i)).toBeInTheDocument()
    expect(fetchMock.mock.calls.some(([input]) =>
      String(input).includes('/alerts/unsubscribe'))).toBe(false)
    await user.click(screen.getByRole('button', { name: 'Confirmar baja' }))
    expect(await screen.findByText(/La alerta quedó desactivada/i)).toBeInTheDocument()
    await waitFor(() => expect(fetchMock.mock.calls.some(([input]) =>
      String(input).includes('/alerts/unsubscribe'))).toBe(true))
    const unsubscribeCalls = fetchMock.mock.calls.filter(([input]) =>
      String(input).includes('/alerts/unsubscribe'))
    expect(unsubscribeCalls.length).toBeGreaterThanOrEqual(1)
    for (const [input, init] of unsubscribeCalls) {
      expect(String(input)).toContain('/alerts/unsubscribe')
      expect(init?.method).toBe('POST')
      expect(String(input)).not.toContain('signed-token')
    }
  })
})
