import { render, screen, waitFor } from '@testing-library/react'
import { createMemoryRouter } from 'react-router-dom'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { appRoutes } from '@/router'

const organizationId = '51ea2f6f-b1af-4e09-856c-6dcbdcfc812f'

function json(value: unknown, status = 200) {
  return Promise.resolve(new Response(JSON.stringify(value), {
    status,
    headers: { 'Content-Type': 'application/json' },
  }))
}

function project(overrides: Record<string, unknown> = {}) {
  return {
    publicId: 'bd351806-9139-4524-bc01-93c3676729cb',
    slug: 'agua-segura',
    title: 'Agua segura',
    summary: 'Acceso sostenible para comunidades rurales.',
    status: 2,
    startDate: '2027-01-01',
    endDate: '2027-12-31',
    budgetTotal: 100000,
    confirmedFunding: 25000,
    currency: 'USD',
    fundingGap: 75000,
    publishedAtUtc: '2026-08-22T10:00:00Z',
    organization: { publicId: organizationId, name: 'Fundación Demo', websiteUrl: 'https://example.test' },
    ...overrides,
  }
}

function catalogs() {
  return {
    countries: [{ id: 152, code: 'CL', name: 'Chile' }],
    currencies: [{ code: 'USD', name: 'Dólar estadounidense', minorUnits: 2 }],
    fundingCategories: [{ id: 4, code: 'water', name: 'Agua y saneamiento' }],
    projectTypes: [{ id: 6, code: 'infrastructure', name: 'Infraestructura' }],
  }
}

describe('marketplace público de proyectos', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('envía búsqueda, filtros, moneda, orden y página al servidor sin token', async () => {
    const fetchMock = vi.fn((input: RequestInfo | URL, _init?: RequestInit) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/auth/refresh')) return json({}, 401)
      if (url.pathname.endsWith('/marketplace/catalogs')) return json(catalogs())
      if (url.pathname.endsWith('/marketplace/projects')) {
        return json({ items: [project()], totalCount: 25, pageNumber: 2, pageSize: 12 })
      }
      throw new Error(`Unexpected request: ${url}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const router = createMemoryRouter(appRoutes, {
      initialEntries: ['/marketplace?q=agua&countryId=152&categoryId=4&projectTypeId=6&status=2&currency=USD&sort=funding-gap-desc&page=2'],
    })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    expect(await screen.findByRole('heading', { name: 'Agua segura' })).toBeInTheDocument()
    const request = fetchMock.mock.calls.find(([input]) => new URL(String(input), 'http://localhost').pathname.endsWith('/marketplace/projects'))
    expect(request).toBeDefined()
    const url = new URL(String(request![0]), 'http://localhost')
    expect(url.searchParams.get('q')).toBe('agua')
    expect(url.searchParams.get('countryIds')).toBe('152')
    expect(url.searchParams.get('categoryIds')).toBe('4')
    expect(url.searchParams.get('projectTypeIds')).toBe('6')
    expect(url.searchParams.get('projectStatus')).toBe('2')
    expect(url.searchParams.get('currency')).toBe('USD')
    expect(url.searchParams.get('sort')).toBe('funding-gap-desc')
    expect(url.searchParams.get('page')).toBe('2')
    expect(new Headers(request?.[1]?.headers).has('Authorization')).toBe(false)
  })

  it('no renderiza un borrador aunque una respuesta inválida lo incluya', async () => {
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/auth/refresh')) return json({}, 401)
      if (url.pathname.endsWith('/marketplace/catalogs')) return json(catalogs())
      if (url.pathname.endsWith('/marketplace/projects')) return json({
        items: [
          project(),
          project({ publicId: '7667f02f-92a7-4939-93ab-255d249e5b9b', slug: 'borrador-privado', title: 'Borrador privado', publicationStatus: 0 }),
        ],
        totalCount: 1,
        pageNumber: 1,
        pageSize: 12,
      })
      throw new Error(`Unexpected request: ${url}`)
    }))
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/marketplace'] })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    expect(await screen.findByRole('heading', { name: 'Agua segura' })).toBeInTheDocument()
    expect(screen.queryByText('Borrador privado')).not.toBeInTheDocument()
  })

  it('muestra el perfil público y nunca presenta PII adicional recibida por error', async () => {
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/auth/refresh')) return json({}, 401)
      if (url.pathname.endsWith(`/marketplace/organizations/${organizationId}`)) return json({
        publicId: organizationId,
        name: 'Fundación Demo',
        description: 'Trabajamos con comunidades rurales.',
        websiteUrl: 'https://example.test',
        establishedYear: 2010,
        homeCountry: { id: 152, code: 'CL', name: 'Chile' },
        organizationType: { id: 2, code: 'foundation', name: 'Fundación' },
        organizationSize: null,
        countries: [{ id: 152, code: 'CL', name: 'Chile' }],
        regions: [],
        categories: [{ id: 4, code: 'water', name: 'Agua y saneamiento' }],
        beneficiaryTypes: [],
        projectTypes: [{ id: 6, code: 'infrastructure', name: 'Infraestructura' }],
        projects: [project()],
        taxIdentifier: '76.123.456-7',
        legalName: 'Dato legal que no debe aparecer',
        contactEmail: 'private@example.test',
      })
      throw new Error(`Unexpected request: ${url}`)
    }))
    const router = createMemoryRouter(appRoutes, { initialEntries: [`/marketplace/organizations/${organizationId}`] })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    expect(await screen.findByRole('heading', { name: 'Fundación Demo', level: 1 })).toBeInTheDocument()
    expect(screen.getByText('Trabajamos con comunidades rurales.')).toBeInTheDocument()
    expect(screen.queryByText('76.123.456-7')).not.toBeInTheDocument()
    expect(screen.queryByText('Dato legal que no debe aparecer')).not.toBeInTheDocument()
    expect(screen.queryByText('private@example.test')).not.toBeInTheDocument()
  })

  it('usa el detalle canónico del marketplace', async () => {
    const fetchMock = vi.fn((input: RequestInfo | URL) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/auth/refresh')) return json({}, 401)
      if (url.pathname.endsWith('/marketplace/projects/agua-segura')) return json({
        ...project(),
        description: 'Descripción pública completa.',
        countries: [{ id: 152, code: 'CL', name: 'Chile' }],
        regions: [],
        categories: [{ id: 4, code: 'water', name: 'Agua y saneamiento' }],
        beneficiaryTypes: [],
        projectTypes: [{ id: 6, code: 'infrastructure', name: 'Infraestructura' }],
      })
      throw new Error(`Unexpected request: ${url}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/marketplace/projects/agua-segura'] })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    expect(await screen.findByRole('heading', { name: 'Agua segura', level: 1 })).toBeInTheDocument()
    expect(screen.getByText('Descripción pública completa.')).toBeInTheDocument()
    await waitFor(() => expect(fetchMock.mock.calls.some(([input]) => String(input).includes('/marketplace/projects/agua-segura'))).toBe(true))
  })
})
