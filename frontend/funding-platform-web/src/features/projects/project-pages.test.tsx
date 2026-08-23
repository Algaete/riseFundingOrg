import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter } from 'react-router-dom'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { clearAuthSession, setAuthenticatedSession } from '@/features/auth/auth-session'
import { appRoutes } from '@/router'

const organizationId = '51ea2f6f-b1af-4e09-856c-6dcbdcfc812f'

function json(value: unknown) {
  return Promise.resolve(new Response(JSON.stringify(value), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  }))
}

describe('proyectos', () => {
  afterEach(() => { vi.unstubAllGlobals(); clearAuthSession() })

  it('muestra proyectos aislados de la organización y su brecha financiera', async () => {
    setAuthenticatedSession({
      status: 'authenticated', accessToken: 'project-test-token',
      accessTokenExpiresAtUtc: '2026-08-21T12:00:00Z',
      user: { publicId: '89b8d22a-472c-42e4-b034-c772ce3bb08e', email: 'member@example.test', displayName: 'Miembro demo', preferredLocale: 'es-CL', roles: ['Professional'], mfaEnabled: false },
    })
    vi.stubGlobal('fetch', vi.fn((input: string | URL | Request) => {
      const url = String(input)
      if (url.endsWith('/organizations')) return json([{ publicId: organizationId, name: 'Fundación Demo', membershipRole: 'admin', profileStatus: 2, profileCompleteness: 100, profileVersion: 2, updatedAtUtc: '2026-08-21T04:00:00Z' }])
      if (url.endsWith('/catalogs')) return json({ countries: [], regions: [], currencies: [], fundingCategories: [], fundingTypes: [], organizationTypes: [], legalEntityTypes: [], organizationSizes: [], beneficiaryTypes: [], projectTypes: [], tags: [], languages: [] })
      if (url.endsWith(`/organizations/${organizationId}/projects`)) return json([{ publicId: 'bd351806-9139-4524-bc01-93c3676729cb', slug: 'agua-segura-demo', title: 'Agua segura', summary: 'Acceso rural sostenible', status: 2, publicationStatus: 0, startDate: null, endDate: null, budgetTotal: 100000, confirmedFunding: 25000, currency: 'CLP', fundingGap: 75000, projectVersion: 1, updatedAtUtc: '2026-08-21T04:00:00Z' }])
      throw new Error(`Unexpected request: ${url}`)
    }))

    const router = createMemoryRouter(appRoutes, { initialEntries: ['/projects'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    expect(await screen.findByRole('heading', { name: 'Agua segura' })).toBeInTheDocument()
    expect(screen.getByText(/75\.000 CLP/)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Editar' })).toHaveAttribute(
      'href', '/projects/bd351806-9139-4524-bc01-93c3676729cb',
    )
  })

  it('avisa junto a la fecha cuando el término es anterior al inicio', async () => {
    setAuthenticatedSession({
      status: 'authenticated', accessToken: 'project-date-test-token',
      accessTokenExpiresAtUtc: '2026-08-21T12:00:00Z',
      user: { publicId: '89b8d22a-472c-42e4-b034-c772ce3bb08e', email: 'member@example.test', displayName: 'Miembro demo', preferredLocale: 'es-CL', roles: ['Professional'], mfaEnabled: false },
    })
    let createRequests = 0
    vi.stubGlobal('fetch', vi.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = String(input)
      if (url.endsWith('/organizations')) return json([{ publicId: organizationId, name: 'Fundación Demo', membershipRole: 'admin', profileStatus: 2, profileCompleteness: 100, profileVersion: 2, updatedAtUtc: '2026-08-21T04:00:00Z' }])
      if (url.endsWith('/catalogs')) return json({ countries: [], regions: [], currencies: [], fundingCategories: [], fundingTypes: [], organizationTypes: [], legalEntityTypes: [], organizationSizes: [], beneficiaryTypes: [], projectTypes: [], tags: [], languages: [] })
      if (url.endsWith(`/organizations/${organizationId}/projects`) && init?.method === 'POST') {
        createRequests += 1
        return json({})
      }
      if (url.endsWith(`/organizations/${organizationId}/projects`)) return json([])
      throw new Error(`Unexpected request: ${url}`)
    }))

    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/projects'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    await user.click(await screen.findByRole('button', { name: 'Nuevo proyecto' }))
    await user.type(screen.getByLabelText('Título'), 'Proyecto con fechas')
    await user.type(screen.getByLabelText('Inicio'), '2027-12-31')
    await user.type(screen.getByLabelText('Término'), '2027-01-01')
    await user.click(screen.getByRole('button', { name: 'Crear proyecto' }))

    expect(await screen.findByText('La fecha de término no puede ser anterior al inicio.')).toBeInTheDocument()
    expect(createRequests).toBe(0)
  })

  it('muestra un perfil público publicado sin datos legales de la organización', async () => {
    setAuthenticatedSession({
      status: 'authenticated', accessToken: 'public-project-test-token',
      accessTokenExpiresAtUtc: '2026-08-21T12:00:00Z',
      user: { publicId: '89b8d22a-472c-42e4-b034-c772ce3bb08e', email: 'member@example.test', displayName: 'Miembro demo', preferredLocale: 'es-CL', roles: ['Professional'], mfaEnabled: false },
    })
    vi.stubGlobal('fetch', vi.fn((input: string | URL | Request) => {
      const url = String(input)
      if (url.endsWith('/projects/agua-segura-demo')) return json({
        projectId: 'bd351806-9139-4524-bc01-93c3676729cb', slug: 'agua-segura-demo',
        title: 'Agua segura', summary: 'Acceso rural sostenible',
        description: 'Soluciones comunitarias para el acceso seguro al agua.', projectStatus: 2,
        startDate: '2027-01-01', endDate: '2027-12-31', budgetTotal: 100000,
        confirmedFunding: 25000, currency: 'CLP', fundingGap: 75000,
        publishedAtUtc: '2026-08-21T10:00:00Z',
        organization: { publicId: organizationId, name: 'Fundación Demo', websiteUrl: 'https://example.test', taxIdentifier: 'NO-DEBE-VERSE' },
        countries: [{ id: 152, code: 'CL', name: 'Chile' }],
        regions: [{ id: 7, countryId: 152, code: 'CL-RM', name: 'Región Metropolitana' }],
        categories: [{ id: 1, code: 'water', name: 'Agua y saneamiento' }],
        beneficiaryTypes: [{ id: 1, code: 'rural', name: 'Comunidades rurales' }],
        projectTypes: [{ id: 1, code: 'infrastructure', name: 'Infraestructura comunitaria' }],
      })
      throw new Error(`Unexpected request: ${url}`)
    }))

    const router = createMemoryRouter(appRoutes, { initialEntries: ['/projects/public/agua-segura-demo'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    expect(await screen.findByRole('heading', { name: 'Agua segura', level: 1 })).toBeInTheDocument()
    expect(screen.getByText('Fundación Demo')).toBeInTheDocument()
    expect(screen.getByText('Agua y saneamiento')).toBeInTheDocument()
    expect(screen.queryByText('NO-DEBE-VERSE')).not.toBeInTheDocument()
  })

  it('permite a un administrador aprobar desde la cola de revisión', async () => {
    setAuthenticatedSession({
      status: 'authenticated', accessToken: 'admin-project-test-token',
      accessTokenExpiresAtUtc: '2026-08-21T12:00:00Z',
      user: { publicId: '89b8d22a-472c-42e4-b034-c772ce3bb08e', email: 'admin@example.test', displayName: 'Admin demo', preferredLocale: 'es-CL', roles: ['Admin'], mfaEnabled: true },
    })
    let listRequests = 0
    const fetchMock = vi.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = String(input)
      if (url.includes('/admin/projects/review-queue')) {
        listRequests += 1
        return json({
          items: listRequests === 1 ? [{
            projectId: 'bd351806-9139-4524-bc01-93c3676729cb', slug: 'agua-segura-demo',
            title: 'Agua segura', summary: 'Acceso rural sostenible', projectStatus: 2,
            publicationStatus: 1, organizationPublicId: organizationId,
            organizationName: 'Fundación Demo', completeness: 100,
            submittedAtUtc: '2026-08-21T10:00:00Z', updatedAtUtc: '2026-08-21T10:00:00Z',
            eTag: '"0000000000000001"',
          }] : [], totalCount: listRequests === 1 ? 1 : 0, page: 1, pageSize: 20,
        })
      }
      if (url.endsWith('/admin/projects/bd351806-9139-4524-bc01-93c3676729cb')) {
        return json({
          projectId: 'bd351806-9139-4524-bc01-93c3676729cb', slug: 'agua-segura-demo',
          title: 'Agua segura', summary: 'Acceso rural sostenible',
          description: 'Proyecto completo sometido a moderación.', projectStatus: 2,
          publicationStatus: 1, startDate: '2027-01-01', endDate: '2027-12-31',
          budgetTotal: 100000, confirmedFunding: 25000, currency: 'CLP', fundingGap: 75000,
          projectVersion: 2,
          completeness: 100, submittedAtUtc: '2026-08-21T10:00:00Z',
          updatedAtUtc: '2026-08-21T10:00:00Z', eTag: '"0000000000000001"',
          organization: { publicId: organizationId, name: 'Fundación Demo', websiteUrl: null },
          countries: [{ id: 152, code: 'CL', name: 'Chile' }], regions: [],
          categories: [{ id: 1, code: 'water', name: 'Agua y saneamiento' }],
          beneficiaryTypes: [{ id: 1, code: 'rural', name: 'Comunidades rurales' }],
          projectTypes: [{ id: 1, code: 'infrastructure', name: 'Infraestructura comunitaria' }],
        })
      }
      if (url.endsWith('/admin/projects/bd351806-9139-4524-bc01-93c3676729cb/reviews')) {
        expect(init?.method).toBe('POST')
        expect(new Headers(init?.headers).get('If-Match')).toBe('"0000000000000001"')
        expect(new Headers(init?.headers).get('Idempotency-Key')).toBeTruthy()
        expect(JSON.parse(String(init?.body))).toEqual({ decision: 'approve', reason: null })
        return json({ projectId: 'bd351806-9139-4524-bc01-93c3676729cb', publicationStatus: 2, completeness: 100, eTag: '"0000000000000002"', wasReplay: false })
      }
      throw new Error(`Unexpected request: ${url}`)
    })
    vi.stubGlobal('fetch', fetchMock)

    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/projects'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    const user = userEvent.setup()
    expect(await screen.findByRole('heading', { name: 'Agua segura' })).toBeInTheDocument()
    await user.click(screen.getByRole('link', { name: 'Revisar proyecto completo' }))
    expect(await screen.findByRole('heading', { name: 'Descripción presentada' })).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Aprobar y publicar' }))

    expect(await screen.findByRole('heading', { name: 'Revisión al día' })).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalled()
  })
})
