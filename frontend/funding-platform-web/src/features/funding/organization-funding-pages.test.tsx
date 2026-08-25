import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter } from 'react-router-dom'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { clearAuthSession, setAuthenticatedSession } from '@/features/auth/auth-session'
import { appRoutes } from '@/router'

const organizationId = '51ea2f6f-b1af-4e09-856c-6dcbdcfc812f'
const opportunityId = 'f5b75d2c-4c84-4ca3-91f7-e9c182fdff2c'

function json(value: unknown, status = 200) {
  return Promise.resolve(new Response(status === 204 ? null : JSON.stringify(value), {
    status,
    headers: status === 204 ? undefined : { 'Content-Type': 'application/json' },
  }))
}

function authenticate() {
  setAuthenticatedSession({
    status: 'authenticated',
    accessToken: 'workspace-ui-token',
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

function organization() {
  return {
    publicId: organizationId,
    name: 'Fundación Demo',
    membershipRole: 'admin',
    profileStatus: 2,
    profileCompleteness: 100,
    profileVersion: 2,
    updatedAtUtc: '2026-08-21T04:00:00Z',
  }
}

function catalogs() {
  return {
    countries: [{ id: 152, code: 'CL', name: 'Chile' }],
    regions: [{ id: 7, countryId: 152, code: 'CL-RM', name: 'Región Metropolitana' }],
    currencies: [{ code: 'USD', name: 'Dólar estadounidense', minorUnits: 2 }],
    fundingCategories: [{ id: 4, code: 'water', name: 'Agua y saneamiento' }],
    fundingTypes: [{ id: 3, code: 'grant', name: 'Subvención' }],
    organizationTypes: [{ id: 2, code: 'foundation', name: 'Fundación' }],
    legalEntityTypes: [{ id: 5, code: 'foundation', name: 'Fundación', countryId: 152 }],
    organizationSizes: [],
    beneficiaryTypes: [{ id: 8, code: 'rural', name: 'Comunidades rurales' }],
    projectTypes: [{ id: 6, code: 'infrastructure', name: 'Infraestructura' }],
    tags: [{ id: 9, code: 'climate', name: 'Cambio climático' }],
    languages: [{ id: 1, code: 'es', name: 'Español' }],
  }
}

function listItem(overrides: Record<string, unknown> = {}) {
  return {
    publicId: opportunityId,
    slug: 'agua-rural',
    title: 'Agua segura para comunidades rurales',
    summary: 'Financia soluciones sostenibles de acceso al agua.',
    sponsorName: 'Fundación Global',
    currency: 'USD',
    minimumAmount: 10000,
    maximumAmount: 50000,
    openDate: '2026-08-01',
    closeDate: '2027-02-15',
    closeAtUtc: '2027-02-15T20:30:00Z',
    deadlineType: 1,
    deadlinePrecision: 2,
    publishedAtUtc: '2026-08-20T10:00:00Z',
    dataQualityScore: 94,
    primaryFunderPublicId: '2ff2809c-900c-49ea-8282-15f2c43716e8',
    primaryFunderName: 'Fundación Global',
    sourceName: 'Portal oficial',
    sourceUrl: 'https://fundacion.example/fondo',
    isFavorite: false,
    ...overrides,
  }
}

function listResponse(itemOverrides: Record<string, unknown> = {}, totalCount = 1, pageNumber = 1) {
  return {
    items: [listItem(itemOverrides)],
    totalCount,
    pageNumber,
    pageSize: 12,
    searchMode: 'full-text',
  }
}

describe('oportunidades de la organización', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    clearAuthSession()
  })

  it('aplica búsqueda y filtros desde la URL en el servidor y conserva la ruta pública aparte', async () => {
    authenticate()
    const fetchMock = vi.fn((input: string | URL | Request, _init?: RequestInit) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/organizations')) return json([organization()])
      if (url.pathname.endsWith('/catalogs')) return json(catalogs())
      if (url.pathname.endsWith(`/organizations/${organizationId}/funding-opportunities`)) {
        return json(listResponse())
      }
      throw new Error(`Unexpected request: ${url}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const router = createMemoryRouter(appRoutes, {
      initialEntries: ['/opportunities?q=agua&countryIds=152&categoryIds=4&sort=relevance'],
    })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    expect(await screen.findByRole('heading', { name: 'Agua segura para comunidades rurales' })).toBeInTheDocument()
    screen.getAllByRole('link', { name: /Concursos disponibles/ })
      .forEach((link) => expect(link).toHaveAttribute('href', '/opportunities'))
    expect(screen.getByLabelText('País')).toHaveValue('152')
    expect(screen.getByLabelText('Categoría')).toHaveValue('4')

    const call = fetchMock.mock.calls.find(([input]) =>
      new URL(String(input), 'http://localhost').pathname.endsWith(`/organizations/${organizationId}/funding-opportunities`),
    )
    expect(call).toBeDefined()
    const requestUrl = new URL(String(call![0]), 'http://localhost')
    expect(requestUrl.searchParams.get('q')).toBe('agua')
    expect(requestUrl.searchParams.get('countryIds')).toBe('152')
    expect(requestUrl.searchParams.get('categoryIds')).toBe('4')
    expect(requestUrl.searchParams.get('sort')).toBe('relevance')
    expect(requestUrl.searchParams.get('page')).toBe('1')
    expect(new Headers(call?.[1]?.headers).get('Authorization')).toBe('Bearer workspace-ui-token')
  })

  it('debouncea el texto, usa un orden válido y guarda un favorito con feedback', async () => {
    authenticate()
    let favorite = false
    const fetchMock = vi.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/organizations')) return json([organization()])
      if (url.pathname.endsWith('/catalogs')) return json(catalogs())
      if (url.pathname.endsWith(`/favorites/${opportunityId}`) && init?.method === 'PUT') {
        favorite = true
        return json(null, 204)
      }
      if (url.pathname.endsWith(`/organizations/${organizationId}/funding-opportunities`)) {
        return json(listResponse({ isFavorite: favorite }))
      }
      throw new Error(`Unexpected request: ${url}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/opportunities'] })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    const search = await screen.findByLabelText('Buscar oportunidades')
    await user.type(search, 'salud')
    await waitFor(() => expect(fetchMock.mock.calls.some(([input]) => {
      const url = new URL(String(input), 'http://localhost')
      return url.searchParams.get('q') === 'salud' && url.searchParams.get('sort') === 'relevance'
    })).toBe(true), { timeout: 2000 })

    await user.click(screen.getByRole('button', { name: 'Guardar en favoritos' }))
    expect(await screen.findByText('Oportunidad guardada en favoritos.')).toBeInTheDocument()
    expect(fetchMock.mock.calls.some(([input, init]) =>
      String(input).endsWith(`/favorites/${opportunityId}`) && init?.method === 'PUT',
    )).toBe(true)
    expect(await screen.findByRole('button', { name: 'Quitar de favoritos' })).toHaveAttribute('aria-pressed', 'true')
  })

  it('bloquea orden por monto sin moneda y pagina mediante una nueva consulta', async () => {
    authenticate()
    const requestedPages: string[] = []
    const fetchMock = vi.fn((input: string | URL | Request) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/organizations')) return json([organization()])
      if (url.pathname.endsWith('/catalogs')) return json(catalogs())
      if (url.pathname.endsWith(`/organizations/${organizationId}/funding-opportunities`)) {
        requestedPages.push(url.searchParams.get('page') ?? '')
        const requestedPage = Number(url.searchParams.get('page') ?? 1)
        return json(listResponse(
          requestedPage === 2
            ? { publicId: '7af2f047-b84f-4284-8184-745134237521', slug: 'segunda-pagina', title: 'Resultado página dos' }
            : {},
          13,
          requestedPage,
        ))
      }
      throw new Error(`Unexpected request: ${url}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/opportunities'] })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    expect(await screen.findByRole('heading', { name: 'Agua segura para comunidades rurales' })).toBeInTheDocument()
    const requestsBeforeInvalidSort = requestedPages.length
    await user.selectOptions(screen.getByLabelText('Ordenar'), 'amount-desc')
    expect(await screen.findByText('Selecciona una moneda para ordenar por monto.')).toBeInTheDocument()
    expect(requestedPages).toHaveLength(requestsBeforeInvalidSort)

    await user.selectOptions(screen.getByLabelText('Moneda'), 'USD')
    await waitFor(() => expect(fetchMock.mock.calls.some(([input]) => {
      const url = new URL(String(input), 'http://localhost')
      return url.searchParams.get('sort') === 'amount-desc' && url.searchParams.get('currency') === 'USD'
    })).toBe(true))
    await user.click(screen.getByRole('button', { name: /Siguiente/ }))
    expect(await screen.findByRole('heading', { name: 'Resultado página dos' })).toBeInTheDocument()
    expect(requestedPages).toContain('2')
  })

  it('muestra el estado vacío real de favoritos y permite volver al catálogo', async () => {
    authenticate()
    vi.stubGlobal('fetch', vi.fn((input: string | URL | Request) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/organizations')) return json([organization()])
      if (url.pathname.endsWith(`/organizations/${organizationId}/favorites`)) {
        return json({ items: [], totalCount: 0, pageNumber: 1, pageSize: 12, searchMode: 'none' })
      }
      throw new Error(`Unexpected request: ${url}`)
    }))
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/favorites'] })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    expect(await screen.findByRole('heading', { name: 'Todavía no guardas concursos' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Explorar oportunidades' })).toHaveAttribute('href', '/opportunities')
  })

  it('vuelve a la página anterior al quitar el último favorito de una página', async () => {
    authenticate()
    let removed = false
    const fetchMock = vi.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/organizations')) return json([organization()])
      if (url.pathname.endsWith(`/favorites/${opportunityId}`) && init?.method === 'DELETE') {
        removed = true
        return json(null, 204)
      }
      if (url.pathname.endsWith(`/organizations/${organizationId}/favorites`)) {
        const page = Number(url.searchParams.get('page') ?? 1)
        if (page === 2 && removed) {
          return json({ items: [], totalCount: 12, pageNumber: 2, pageSize: 12, searchMode: 'none' })
        }
        if (page === 2) return json(listResponse({ isFavorite: true }, 13, 2))
        return json(listResponse({
          publicId: '7af2f047-b84f-4284-8184-745134237521',
          slug: 'favorito-anterior',
          title: 'Favorito de la primera página',
          isFavorite: true,
        }, 12, 1))
      }
      throw new Error(`Unexpected request: ${url}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/favorites?page=2'] })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    expect(await screen.findByRole('heading', { name: 'Agua segura para comunidades rurales' })).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Quitar de favoritos' }))

    expect(await screen.findByRole('heading', { name: 'Favorito de la primera página' })).toBeInTheDocument()
    expect(router.state.location.search).toBe('')
    expect(screen.queryByRole('heading', { name: 'Todavía no guardas concursos' })).not.toBeInTheDocument()
  })

  it('abre el detalle autenticado dentro del espacio de la organización', async () => {
    authenticate()
    const fetchMock = vi.fn((input: string | URL | Request) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/organizations')) return json([organization()])
      if (url.pathname.endsWith('/catalogs')) return json(catalogs())
      if (url.pathname.endsWith(`/organizations/${organizationId}/funding-opportunities/agua-rural`)) {
        return json({
          ...listItem(),
          description: 'Descripción completa y verificable.',
          sponsorUrl: 'https://fundacion.example',
          applicationUrl: null,
          issuerCountryId: 152,
          fundingTypeId: 3,
          amountStatus: 1,
          closeAtUtc: '2027-02-15T20:30:00Z',
          deadlineTimeZoneId: 'America/Santiago',
          deadlineType: 1,
          deadlinePrecision: 2,
          eligibilityDescription: 'Fundaciones constituidas.',
          requirements: 'Documentación vigente.',
          objectives: 'Acceso sostenible al agua.',
          allowedActivities: 'Construcción de sistemas de agua.',
          excludedActivities: 'Compra de vehículos.',
          restrictions: 'Solo ejecución en zonas rurales.',
          targetOrganizationsDescription: 'Fundaciones comunitarias.',
          targetPopulationsDescription: 'Comunidades rurales.',
          minimumOperatingYears: 3,
          requiresLegalEntity: true,
          requiresPriorExperience: true,
          requiresCofunding: true,
          cofundingPercentage: 20,
          geographicScope: 1,
          remoteApplication: 1,
          lastVerifiedAtUtc: '2026-08-20T10:00:00Z',
          contentVersion: 3,
          primaryFunderSlug: 'fundacion-global',
          externalId: 'EXT-9',
          countryIds: [152], regionIds: [7], categoryIds: [4], beneficiaryTypeIds: [8],
          projectTypeIds: [6], tagIds: [9], organizationTypes: [{ id: 2, eligibilityMode: 1 }],
          legalEntityTypes: [{ id: 5, eligibilityMode: 1 }], languages: [{ id: 1, languagePurpose: 1 }], funders: [],
          sources: [{ fundingSourceId: 1, sourceName: 'Portal oficial', externalId: 'EXT-9', sourceUrl: 'https://fundacion.example/fondo', firstSeenAtUtc: '2026-08-01T00:00:00Z', lastSeenAtUtc: '2026-08-20T00:00:00Z', isPrimary: true, isActive: true }],
        })
      }
      throw new Error(`Unexpected request: ${url}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/opportunities/agua-rural'] })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    expect(await screen.findByRole('heading', { name: 'Agua segura para comunidades rurales' })).toBeInTheDocument()
    expect(screen.getByText('Descripción completa y verificable.')).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Condiciones publicadas' })).toBeInTheDocument()
    expect(screen.getByText('Construcción de sistemas de agua.')).toBeInTheDocument()
    expect(screen.getByText('Solo ejecución en zonas rurales.')).toBeInTheDocument()
    expect(screen.getByText('20%')).toBeInTheDocument()
    expect(screen.getByText('Cierre exacto').parentElement).toHaveTextContent('UTC')
    expect(screen.getByText('America/Santiago')).toBeInTheDocument()
    expect(screen.getByText('Fundación · admitido')).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Fuentes vinculadas' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Guardar en favoritos' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Iniciar postulación' })).toHaveAttribute(
      'href',
      `/applications?new=1&fundingOpportunityId=${opportunityId}`,
    )
    expect(screen.getByText(/debes elegir uno de tus proyectos/i)).toBeInTheDocument()
    expect(fetchMock.mock.calls.some(([input]) => String(input).includes(`/organizations/${organizationId}/funding-opportunities/agua-rural`))).toBe(true)
  })
})
