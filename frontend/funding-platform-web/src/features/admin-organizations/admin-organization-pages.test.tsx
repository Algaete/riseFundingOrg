import { render, screen } from '@testing-library/react'
import { createMemoryRouter } from 'react-router-dom'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { adminErrorsApi } from '@/features/admin-errors/admin-errors-api'
import { adminOrganizationsApi } from '@/features/admin-organizations/admin-organizations-api'
import { setAuthenticatedSession } from '@/features/auth/auth-session'
import { appRoutes } from '@/router'

const organizationId = '22222222-2222-2222-2222-222222222222'

function authenticate() {
  setAuthenticatedSession({
    status: 'authenticated', accessToken: 'admin-operations-token',
    accessTokenExpiresAtUtc: '2027-08-26T13:00:00Z',
    user: {
      publicId: '11111111-1111-1111-1111-111111111111',
      email: 'admin@example.test', displayName: 'Administradora', preferredLocale: 'es-CL',
      roles: ['Admin'], mfaEnabled: true,
    },
  })
}

const summary = {
  publicId: organizationId, name: 'Fundación Agua Segura', countryCode: 'CL', countryName: 'Chile',
  organizationTypeName: 'Fundación', profileStatus: 2, profileCompleteness: 95,
  isActive: true, memberCount: 3, projectCount: 2, planCode: 'FREE', planName: 'Free',
  subscriptionStatus: null, createdAtUtc: '2026-08-01T12:00:00Z',
  updatedAtUtc: '2026-08-26T12:00:00Z',
}

describe('administración de organizaciones y errores', () => {
  beforeEach(() => {
    localStorage.clear()
    sessionStorage.clear()
    authenticate()
  })
  afterEach(() => vi.restoreAllMocks())

  it('muestra el listado de organizaciones real y su ficha sin datos tributarios', async () => {
    vi.spyOn(adminOrganizationsApi, 'list').mockResolvedValue({
      items: [summary], totalCount: 1, page: 1, pageSize: 25,
    })
    vi.spyOn(adminOrganizationsApi, 'get').mockResolvedValue({
      ...summary, legalName: 'Fundación Agua Segura', legalEntityTypeName: 'Fundación',
      organizationSizeName: 'Pequeña', establishedYear: 2020,
      websiteUrl: 'https://example.test', description: 'Agua para comunidades.',
      profileVersion: 4, adminMemberCount: 1, publishedProjectCount: 1,
      currentPeriodEndUtc: null,
    })

    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/organizations'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    expect(await screen.findByRole('heading', { name: 'Organizaciones' })).toBeInTheDocument()
    expect(await screen.findByText('Fundación Agua Segura')).toBeInTheDocument()
    expect(screen.queryByText('Módulo preparado')).not.toBeInTheDocument()
    await router.navigate(`/admin/organizations/${organizationId}`)
    expect(await screen.findByText('Agua para comunidades.')).toBeInTheDocument()
    expect(screen.getByText('3')).toBeInTheDocument()
    expect(screen.queryByText(/tribut/i)).not.toBeInTheDocument()
  })

  it('muestra incidentes sanitizados con vínculo al contexto permitido', async () => {
    vi.spyOn(adminErrorsApi, 'list').mockResolvedValue({
      items: [{
        id: 'import:1', category: 'import', severity: 1, code: 'provider-timeout',
        message: 'La fuente no respondió dentro del plazo.', isRetryable: true,
        occurredAtUtc: '2026-08-26T12:00:00Z',
        relatedResourcePublicId: '33333333-3333-3333-3333-333333333333',
        sourceName: 'Grants.gov',
      }],
      totalCount: 1, page: 1, pageSize: 25,
    })
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/errors'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    expect(await screen.findByRole('heading', { name: 'Errores operacionales' })).toBeInTheDocument()
    expect(await screen.findByText('provider-timeout')).toBeInTheDocument()
    expect(screen.getByText('La fuente no respondió dentro del plazo.')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Abrir contexto' })).toHaveAttribute(
      'href', '/admin/imports/33333333-3333-3333-3333-333333333333')
    expect(screen.queryByText('Módulo preparado')).not.toBeInTheDocument()
  })
})
