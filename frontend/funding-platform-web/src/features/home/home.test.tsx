import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter } from 'react-router-dom'
import { App } from '@/App'
import { createAppQueryClient } from '@/api/query-client'
import { PublicLayout } from '@/components/public-layout'
import { setAuthenticatedSession } from '@/features/auth/auth-session'
import { marketplaceApi, type MarketplaceProjectItem } from '@/features/marketplace/marketplace-api'
import { projectMapApi, type MapPoint } from '@/features/project-map/project-map-api'
import { HomePage } from './home-page'
import { fundingProgress, homeSearchUrl, publishedHomeProjects } from './home-model'

const project: MarketplaceProjectItem = {
  publicId: '11111111-2222-3333-4444-555555555555', slug: 'agua-segura', title: 'Agua segura', summary: 'Una iniciativa pública.',
  status: 3, projectStage: 2, startDate: null, endDate: null, budgetTotal: 100000, confirmedFunding: 25000,
  currency: 'USD', fundingGap: 75000, publishedAtUtc: '2026-09-01T00:00:00Z',
  organization: { publicId: '11111111-2222-3333-4444-666666666666', name: 'Organización comunitaria', websiteUrl: null },
}
const catalogs = { countries: [{ id: 152, code: 'CL', name: 'Chile' }], fundingCategories: [{ id: 4, code: 'water', name: 'Agua y saneamiento' }], projectTypes: [], sustainableDevelopmentGoals: [], currencies: [] }
function setup(path = '/') {
  const router = createMemoryRouter([{ element: <PublicLayout />, children: [{ path: '/', element: <HomePage /> }] },
    { path: '/marketplace', element: <p>Destination</p> }, { path: '/funding/explore', element: <p>Destination</p> },
  ], { initialEntries: [path] })
  render(<App router={router} queryClient={createAppQueryClient()} />)
  return router
}

describe('inicio basado en la referencia', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      if (String(input).endsWith('/auth/refresh')) return Promise.resolve(new Response('{}', { status: 401, headers: { 'Content-Type': 'application/json' } }))
      throw new Error(`Unexpected request: ${String(input)}`)
    }))
    vi.spyOn(marketplaceApi, 'catalogs').mockResolvedValue(catalogs)
    vi.spyOn(marketplaceApi, 'search').mockResolvedValue({ items: [], totalCount: 0, pageNumber: 1, pageSize: 3 })
    vi.spyOn(projectMapApi, 'search').mockResolvedValue({ items: [], totalCount: 0, withoutPublicLocationCount: 0, page: 1, pageSize: 100 })
  })
  afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals() })

  it('muestra la composición y estados vacíos, sin inventar proyectos ni ubicaciones', async () => {
    setup()
    expect(await screen.findByText('El próximo gran proyecto puede ser el tuyo')).toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Conecta tu proyecto')
    expect(document.querySelector('.home-hero-photo')).toHaveAttribute('src', '/images/home-impact-hero.jpg')
    expect(document.querySelector('.home-hero-photo')).toHaveAttribute('alt', '')
    expect(screen.getByRole('link', { name: 'Publicar mi proyecto' })).toHaveAttribute('href', '/register')
    expect(screen.getByRole('navigation', { name: 'Conecta con el ecosistema' }).querySelectorAll('a')).toHaveLength(4)
    expect(screen.getByText('Aquí aparecerán los proyectos con ubicación pública.')).toBeInTheDocument()
    expect(document.querySelectorAll('.home-project-card, .home-map-marker')).toHaveLength(0)
    expect(marketplaceApi.search).toHaveBeenCalledWith({ sort: 'newest', page: 1, pageSize: 3 }, expect.any(AbortSignal))
  })

  it('solo presenta la proyección publicada y distingue progreso conocido de desconocido', async () => {
    vi.mocked(marketplaceApi.search).mockResolvedValue({ items: [project,
      { ...project, publicId: 'second', slug: 'sin-presupuesto', title: 'Sin presupuesto', confirmedFunding: null },
      { ...project, publicId: 'draft', title: 'Borrador secreto', publicationStatus: 0 },
    ], totalCount: 2, pageNumber: 1, pageSize: 3 })
    setup()
    expect(await screen.findByRole('heading', { name: 'Agua segura' })).toBeInTheDocument()
    expect(screen.queryByText('Borrador secreto')).not.toBeInTheDocument()
    expect(screen.getByRole('progressbar')).toHaveAttribute('value', '25')
    expect(screen.getByText('25% financiado')).toBeInTheDocument()
    expect(screen.getByText('Avance de financiamiento no informado')).toBeInTheDocument()
    expect(screen.getAllByRole('link', { name: 'Ver proyecto' })[0]).toHaveAttribute('href', '/marketplace/projects/agua-segura')
    expect(document.querySelectorAll('.home-project-card img')).toHaveLength(0)
  })

  it.each(['projects', 'funding'] as const)('envía los filtros y búsqueda al destino %s', async scope => {
    const router = setup()
    const user = userEvent.setup()
    await screen.findByRole('option', { name: 'Chile' })
    if (scope === 'funding') await user.click(screen.getByRole('radio', { name: 'Oportunidades' }))
    await user.type(screen.getByRole('searchbox', { name: 'Término de búsqueda' }), '  agua & salud  ')
    await user.selectOptions(screen.getByRole('combobox', { name: 'País' }), '152')
    await user.selectOptions(screen.getByRole('combobox', { name: 'Área de impacto' }), '4')
    await user.click(screen.getByRole('button', { name: 'Buscar' }))
    await waitFor(() => expect(router.state.location.pathname).toBe(scope === 'projects' ? '/marketplace' : '/funding/explore'))
    const params = new URLSearchParams(router.state.location.search)
    expect(params.get(scope === 'projects' ? 'q' : 'query')).toBe('agua & salud')
    expect(params.get('countryId')).toBe('152')
    expect(params.get('categoryId')).toBe('4')
  })

  it('conserva criterios e idioma sin recargar datos al traducir', async () => {
    setup()
    const user = userEvent.setup()
    await screen.findByRole('option', { name: 'Chile' })
    await user.type(screen.getByRole('searchbox'), 'agua')
    await user.selectOptions(screen.getByRole('combobox', { name: 'País' }), '152')
    await user.selectOptions(screen.getAllByRole('combobox', { name: 'Idioma' })[0], 'en')
    expect(await screen.findByRole('heading', { name: 'Projects around the world' })).toBeInTheDocument()
    expect(screen.getByRole('searchbox')).toHaveValue('agua')
    expect(screen.getByRole('combobox', { name: 'Country' })).toHaveValue('152')
    expect(marketplaceApi.search).toHaveBeenCalledTimes(1)
    expect(marketplaceApi.catalogs).toHaveBeenCalledTimes(1)
    expect(projectMapApi.search).toHaveBeenCalledTimes(1)
  })

  it('separa errores, permite reintento y no bloquea la búsqueda por texto', async () => {
    vi.mocked(marketplaceApi.catalogs).mockRejectedValue(new Error('private diagnostic'))
    vi.mocked(marketplaceApi.search).mockRejectedValueOnce(new Error('internal error')).mockResolvedValueOnce({ items: [project], totalCount: 1, pageNumber: 1, pageSize: 3 })
    const router = setup()
    const user = userEvent.setup()
    await user.click(await screen.findByRole('button', { name: 'Reintentar proyectos' }))
    expect(await screen.findByRole('heading', { name: 'Agua segura' })).toBeInTheDocument()
    expect(screen.getByRole('combobox', { name: 'País' })).toBeDisabled()
    expect(screen.queryByText('private diagnostic')).not.toBeInTheDocument()
    expect(screen.getByText('Aquí aparecerán los proyectos con ubicación pública.')).toBeInTheDocument()
    await user.type(screen.getByRole('searchbox'), 'bosque')
    await user.click(screen.getByRole('button', { name: 'Buscar' }))
    await waitFor(() => expect(router.state.location.search).toBe('?q=bosque'))
  })

  it('agrupa solo ubicaciones públicas válidas y advierte el límite de la vista previa', async () => {
    const point: MapPoint = { publicId: project.publicId, slug: project.slug, title: project.title, summary: null, organizationName: 'Organización', latitude: -33.45, longitude: -70.66, projectStatus: 3, projectStage: null, fundingGap: null, currency: null }
    vi.mocked(projectMapApi.search).mockResolvedValue({ items: [point, { ...point, publicId: 'second' }], totalCount: 150, withoutPublicLocationCount: 8, page: 1, pageSize: 100 })
    setup()
    expect(await screen.findByRole('link', { name: 'Explorar 2 proyectos en el mapa' })).toHaveAttribute('href', '/marketplace/map')
    expect(screen.getByText('Vista previa: 2 de 150 proyectos con ubicación pública.')).toBeInTheDocument()
    expect(document.querySelectorAll('.home-map-marker')).toHaveLength(1)
  })

  it('el acceso de búsqueda enfoca el campo y el menú se cierra con Escape', async () => {
    setup('/#home-search')
    await waitFor(() => expect(screen.getByRole('searchbox')).toHaveFocus())
    const user = userEvent.setup()
    const trigger = screen.getByRole('button', { name: 'Más' })
    await user.click(trigger)
    const nav = screen.getByRole('navigation', { name: 'Explorar la plataforma' })
    expect(within(nav).getByRole('link', { name: 'Profesionales' })).toHaveAttribute('href', '/professionals')
    await user.keyboard('{Escape}')
    expect(screen.queryByRole('navigation', { name: 'Explorar la plataforma' })).not.toBeInTheDocument()
    expect(trigger).toHaveFocus()
  })

  it.each([['Admin', '/admin/funding'], ['Professional', '/funder-workspace/funding']])('respeta el destino del financiador para %s', async (role, target) => {
    setAuthenticatedSession({ status: 'authenticated', accessToken: 'synthetic-test-token', accessTokenExpiresAtUtc: new Date(Date.now() + 600000).toISOString(), user: { publicId: project.publicId, email: 'synthetic@example.invalid', displayName: 'Synthetic', preferredLocale: 'es', roles: [role], mfaEnabled: true } })
    setup()
    expect(await screen.findByRole('link', { name: 'Publicar una oportunidad' })).toHaveAttribute('href', target)
    expect(screen.getByRole('link', { name: 'Publicar mi proyecto' })).toHaveAttribute('href', '/projects')
  })
})

describe('contratos del inicio', () => {
  it('codifica texto, limita longitud y rechaza IDs no positivos', () => {
    expect(homeSearchUrl('projects', 'á & b', '-1', 'no')).toBe('/marketplace?q=%C3%A1+%26+b')
    expect(homeSearchUrl('funding', '', '', '')).toBe('/funding/explore')
    expect(new URLSearchParams(homeSearchUrl('funding', 'a'.repeat(250), '0', '').split('?')[1]).get('query')).toHaveLength(200)
  })
  it('no confunde desconocido con cero ni supera el cien por ciento', () => {
    expect(fundingProgress(project)).toBe(25)
    for (const override of [{ budgetTotal: 0 }, { confirmedFunding: null }, { confirmedFunding: -1 }, { budgetTotal: NaN }, { currency: null }]) expect(fundingProgress({ ...project, ...override })).toBeNull()
    expect(fundingProgress({ ...project, confirmedFunding: 0 })).toBe(0)
    expect(fundingProgress({ ...project, confirmedFunding: 150000 })).toBe(100)
  })
  it('limita el resumen a tres proyectos y nunca incluye un borrador explícito', () => {
    expect(publishedHomeProjects([project, { ...project, publicationStatus: 1 }, project, project, project])).toHaveLength(3)
  })
})
