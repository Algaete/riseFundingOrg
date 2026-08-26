import { render, screen } from '@testing-library/react'
import { createMemoryRouter } from 'react-router-dom'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { setAuthenticatedSession } from '@/features/auth/auth-session'
import { adminUsersApi } from '@/features/admin-users/admin-users-api'
import { appRoutes } from '@/router'

function authenticate() {
  setAuthenticatedSession({
    status: 'authenticated',
    accessToken: 'admin-access-token',
    accessTokenExpiresAtUtc: '2026-08-26T13:00:00Z',
    user: {
      publicId: '11111111-1111-1111-1111-111111111111',
      email: 'admin@example.test',
      displayName: 'Administradora',
      preferredLocale: 'es-CL',
      roles: ['Admin'],
      mfaEnabled: true,
    },
  })
}

describe('administración de usuarios', () => {
  beforeEach(() => {
    localStorage.clear()
    sessionStorage.clear()
    authenticate()
  })

  afterEach(() => vi.restoreAllMocks())

  it('muestra las cuentas reales devueltas por la API administrativa', async () => {
    vi.spyOn(adminUsersApi, 'list').mockResolvedValue({
      items: [{
        publicId: '22222222-2222-2222-2222-222222222222',
        email: 'alfonso@example.test',
        displayName: 'Alfonso Gaete',
        preferredLocale: 'es-CL',
        status: 'Active',
        emailConfirmed: true,
        mfaEnabled: true,
        lastLoginAtUtc: '2026-08-26T12:00:00Z',
        createdAtUtc: '2026-08-01T12:00:00Z',
        roles: ['SuperAdmin'],
      }],
      totalCount: 1,
      page: 1,
      pageSize: 25,
    })
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/users'] })

    render(<App router={router} queryClient={createAppQueryClient()} />)

    expect(await screen.findByRole('heading', { name: 'Usuarios', level: 1 })).toBeInTheDocument()
    expect(await screen.findByText('Alfonso Gaete')).toBeInTheDocument()
    expect(screen.getByText('alfonso@example.test')).toBeInTheDocument()
    expect(screen.getAllByText('SuperAdmin')).toHaveLength(2)
    expect(screen.getByText('MFA activo')).toBeInTheDocument()
  })

  it('muestra un estado vacío útil cuando no hay coincidencias', async () => {
    vi.spyOn(adminUsersApi, 'list').mockResolvedValue({
      items: [],
      totalCount: 0,
      page: 1,
      pageSize: 25,
    })
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/users?role=Admin'] })

    render(<App router={router} queryClient={createAppQueryClient()} />)

    expect(await screen.findByText('No hay usuarios con estos filtros')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Limpiar filtros' })).toBeInTheDocument()
  })
})
