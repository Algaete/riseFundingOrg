import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter } from 'react-router-dom'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { adminErrorsApi } from '@/features/admin-errors/admin-errors-api'
import { adminOrganizationsApi } from '@/features/admin-organizations/admin-organizations-api'
import { setAuthenticatedSession } from '@/features/auth/auth-session'
import { appRoutes } from '@/router'
import { setInterfaceLanguage } from '@/i18n'

const organizationId = '22222222-2222-2222-2222-222222222222'

function authenticate(roles = ['Admin']) {
  setAuthenticatedSession({
    status: 'authenticated', accessToken: 'admin-operations-token',
    accessTokenExpiresAtUtc: '2027-08-26T13:00:00Z',
    user: {
      publicId: '11111111-1111-1111-1111-111111111111',
      email: 'admin@example.test', displayName: 'Administradora', preferredLocale: 'es-CL',
      roles, mfaEnabled: true,
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
    vi.spyOn(adminOrganizationsApi, 'getVerification').mockResolvedValue({
      organizationPublicId: organizationId, name: summary.name, status: 0, recordedStatus: 0,
      revision: 0, profileVersion: 4, reviewedProfileVersion: null, reviewedAtUtc: null,
      reviewedByUserPublicId: null, reviewedByName: null, reason: null,
      needsReverification: false, history: [],
    })
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
    expect(await screen.findByText('Verificación manual de la organización')).toBeInTheDocument()
    expect(screen.getByText('Datos suficientes')).toBeInTheDocument()
    expect(screen.getByText('Pendiente de verificación')).toBeInTheDocument()
  })

  it('filtra verificación sin perder filtros existentes y reinicia la página', async () => {
    const list = vi.spyOn(adminOrganizationsApi, 'list').mockResolvedValue({
      items: [{ ...summary, verificationStatus: 0 }], totalCount: 40, page: 2, pageSize: 25,
    })
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/organizations?q=Agua&profileStatus=2&isActive=true&page=2'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)
    const user = userEvent.setup()
    const filter = await screen.findByRole('combobox', { name: 'Verificación editorial' })
    await user.selectOptions(filter, '0')
    await waitFor(() => expect(list).toHaveBeenLastCalledWith({
      q: 'Agua', profileStatus: 2, verificationStatus: 0, isActive: true, page: 1, pageSize: 25,
    }, expect.any(AbortSignal)))
    const params = new URLSearchParams(router.state.location.search)
    expect(params.get('q')).toBe('Agua')
    expect(params.get('profileStatus')).toBe('2')
    expect(params.get('isActive')).toBe('true')
    expect(params.get('verificationStatus')).toBe('0')
    expect(params.has('page')).toBe(false)
    const row = screen.getByRole('row', { name: /Fundación Agua Segura/ })
    expect(within(row).getByText('Datos suficientes')).toBeInTheDocument()
    expect(within(row).getByText('Pendiente de verificación')).toBeInTheDocument()
  })

  it('tolera una colección nula y descarta estados de verificación fuera del contrato', async () => {
    const list = vi.spyOn(adminOrganizationsApi, 'list').mockResolvedValue({
      items: null as unknown as [], totalCount: 0, page: 1, pageSize: 25,
    })
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/organizations?verificationStatus=99'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)
    expect(await screen.findByText('No hay organizaciones con estos filtros')).toBeInTheDocument()
    expect(list).toHaveBeenLastCalledWith(expect.objectContaining({ verificationStatus: undefined }), expect.any(AbortSignal))
  })

  it('traduce filtros y estados independientes en inglés', async () => {
    await setInterfaceLanguage('en')
    vi.spyOn(adminOrganizationsApi, 'list').mockResolvedValue({
      items: [{ ...summary, verificationStatus: 1 }], totalCount: 1, page: 1, pageSize: 25,
    })
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/organizations'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)
    const row = await screen.findByRole('row', { name: /Fundación Agua Segura/ })
    expect(within(row).getByText('Sufficient information')).toBeInTheDocument()
    expect(within(row).getByText('Verified')).toBeInTheDocument()
    expect(screen.getByRole('combobox', { name: 'Editorial verification' })).toBeInTheDocument()
  })

  it('no consulta la ficha ni decisiones privadas para un usuario sin rol de administrador', async () => {
    authenticate(['OrgAdmin'])
    const get = vi.spyOn(adminOrganizationsApi, 'get')
    const decide = vi.spyOn(adminOrganizationsApi, 'decideVerification')
    const router = createMemoryRouter(appRoutes, { initialEntries: [`/admin/organizations/${organizationId}`] })
    render(<App router={router} queryClient={createAppQueryClient()} />)
    await waitFor(() => expect(router.state.location.pathname).toBe('/dashboard'))
    expect(get).not.toHaveBeenCalled()
    expect(adminOrganizationsApi.getVerification).not.toHaveBeenCalled()
    expect(decide).not.toHaveBeenCalled()
    expect(screen.queryByText('Historial privado de decisiones')).not.toBeInTheDocument()
  })

  it('descarta la confirmación y el motivo cuando se cambia a otra organización', async () => {
    const secondId = '33333333-3333-3333-3333-333333333333'
    vi.spyOn(adminOrganizationsApi, 'get').mockImplementation(async id => ({
      ...summary, publicId: id, name: id === secondId ? 'Otra organización' : summary.name,
      legalName: null, legalEntityTypeName: null, organizationSizeName: null,
      establishedYear: null, websiteUrl: null, description: null, profileVersion: 4,
      adminMemberCount: 1, publishedProjectCount: 0, currentPeriodEndUtc: null,
    }))
    const decide = vi.spyOn(adminOrganizationsApi, 'decideVerification')
    const router = createMemoryRouter(appRoutes, { initialEntries: [`/admin/organizations/${organizationId}`] })
    render(<App router={router} queryClient={createAppQueryClient()} />)
    const user = userEvent.setup()
    await user.type(await screen.findByRole('textbox', { name: /Motivo de la nueva decisión/ }), 'Revisión de la primera organización.')
    await user.click(screen.getByRole('button', { name: 'Marcar como verificada' }))
    expect(screen.getByRole('button', { name: 'Confirmar decisión' })).toBeEnabled()
    await router.navigate(`/admin/organizations/${secondId}`)
    expect(await screen.findByRole('heading', { name: 'Otra organización' })).toBeInTheDocument()
    await waitFor(() => expect(screen.getByRole('textbox', { name: /Motivo de la nueva decisión/ })).toBeEnabled())
    expect(screen.getByRole('textbox', { name: /Motivo de la nueva decisión/ })).toHaveValue('')
    expect(screen.queryByRole('button', { name: 'Confirmar decisión' })).not.toBeInTheDocument()
    expect(decide).not.toHaveBeenCalled()
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
