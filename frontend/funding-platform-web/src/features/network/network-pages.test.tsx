import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { createMemoryRouter } from 'react-router-dom'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { clearAuthSession, setAuthenticatedSession } from '@/features/auth/auth-session'
import { appRoutes } from '@/router'

const organizationId = '51ea2f6f-b1af-4e09-856c-6dcbdcfc812f'
const recipientId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'

function json(value: unknown, status = 200) {
  return Promise.resolve(new Response(JSON.stringify(value), {
    status, headers: { 'Content-Type': 'application/json' },
  }))
}

function authenticate(role: 'admin' | 'member' = 'admin') {
  setAuthenticatedSession({ status: 'authenticated', accessToken: 'network-page-token',
    accessTokenExpiresAtUtc: '2027-08-25T12:00:00Z', user: {
      publicId: '89b8d22a-472c-42e4-b034-c772ce3bb08e', email: `${role}@example.test`,
      displayName: 'Miembro demo', preferredLocale: 'es-CL', roles: ['Professional'], mfaEnabled: false,
    } })
}

function fixtures(role: 'admin' | 'member' = 'admin') {
  return vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(String(input), 'http://localhost')
    if (url.pathname.endsWith('/organizations')) return json([{ publicId: organizationId,
      name: 'Fundación Demo', membershipRole: role, profileStatus: 2,
      profileCompleteness: 100, profileVersion: 2, updatedAtUtc: '2026-08-25T10:00:00Z' }])
    if (url.pathname.endsWith('/network/settings')) return json({ exists: true,
      isDiscoverable: true, allowRequests: true, createdAtUtc: '2026-08-25T10:00:00Z',
      updatedAtUtc: '2026-08-25T10:00:00Z', eTag: '"0102030405060708"' })
    if (url.pathname.endsWith('/network/directory')) return json({ items: [{ id: recipientId,
      name: 'Fundación Agua', description: 'Agua segura rural', websiteUrl: null,
      homeCountry: { id: 152, code: 'CL', name: 'Chile' },
      organizationType: { id: 1, code: 'foundation', name: 'Fundación' },
      visibleProjectCount: 1, allowsRequests: true, connectionId: null, connectionState: 'none',
      categories: [{ id: 2, code: 'water', name: 'Agua' }], projectTypes: [] }],
      totalCount: 1, page: 1, pageSize: 20 })
    if (url.pathname.endsWith('/network/connections')) return json({ items: [], totalCount: 0, page: 1, pageSize: 50 })
    if (url.pathname.endsWith('/projects')) return json([])
    if (url.pathname.endsWith('/network/connections') && init?.method === 'POST') return json({})
    throw new Error(`Unexpected request: ${url.pathname} ${init?.method}`)
  })
}

describe('networking entre organizaciones', () => {
  afterEach(() => { vi.unstubAllGlobals(); clearAuthSession() })

  it('muestra solo perfiles opt-in y permite a admin preparar una invitación sin PII', async () => {
    authenticate('admin')
    vi.stubGlobal('fetch', fixtures('admin'))
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/network'] })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    expect(await screen.findByRole('heading', { name: 'Conexiones' })).toBeInTheDocument()
    expect(await screen.findByText('Fundación Agua')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Conectar' }))
    expect(await screen.findByRole('heading', { name: 'Invitar a Fundación Agua' })).toBeInTheDocument()
    expect(screen.getByPlaceholderText(/sin incluir correos, teléfonos ni enlaces/i)).toBeInTheDocument()
    expect(screen.queryByText(/@example/i)).not.toBeInTheDocument()
  })

  it('miembro puede explorar pero no ve controles de administración ni conexión', async () => {
    authenticate('member')
    vi.stubGlobal('fetch', fixtures('member'))
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/network'] })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    expect(await screen.findByText('Fundación Agua')).toBeInTheDocument()
    expect(screen.getByText(/solo la administración de la ONG puede cambiar visibilidad/i)).toBeInTheDocument()
    await waitFor(() => expect(screen.queryByRole('button', { name: 'Conectar' })).not.toBeInTheDocument())
    expect(screen.getByRole('button', { name: /Salir del directorio/i })).toBeDisabled()
  })
})
