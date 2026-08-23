import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter, MemoryRouter } from 'react-router-dom'
import { vi } from 'vitest'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { FundingCard } from '@/features/funding/funding-pages'
import { appRoutes } from '@/router'

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

function listItem(overrides: Record<string, unknown> = {}) {
  return {
    publicId: 'f5b75d2c-4c84-4ca3-91f7-e9c182fdff2c',
    slug: 'global-health',
    title: 'Advancing Global Health',
    summary: 'A real opportunity imported from an official source.',
    sponsorName: 'Global Health Foundation',
    currency: 'USD',
    minimumAmount: 500000,
    maximumAmount: 250000000,
    openDate: '2026-08-18',
    closeDate: '2027-02-14',
    sourceName: 'Official Foundation Portal',
    sourceUrl: 'https://foundation.example/funds/global-health',
    sourceAttribution: 'Datos suministrados por el portal oficial de la fundación.',
    publishedAtUtc: '2026-08-18T14:00:00Z',
    dataQualityScore: 96,
    ...overrides,
  }
}

describe('catálogo público de oportunidades', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.useRealTimers()
  })

  it('mantiene vigente una convocatoria durante todo su día de apertura y cierre', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-08-22T23:30:00Z'))

    render(
      <MemoryRouter>
        <FundingCard opportunity={listItem({ openDate: '2026-08-22', closeDate: '2026-08-22' })} />
      </MemoryRouter>,
    )

    expect(screen.getByText('Vigente')).toBeInTheDocument()
    expect(screen.queryByText('Cerrada')).not.toBeInTheDocument()
    expect(screen.queryByText('Próximamente')).not.toBeInTheDocument()
  })

  it('respeta la hora exacta al mostrar el estado de una convocatoria', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-08-22T20:00:00Z'))

    render(
      <MemoryRouter>
        <FundingCard opportunity={listItem({
          closeAtUtc: '2026-08-22T19:59:59Z',
          deadlineType: 1,
          deadlinePrecision: 2,
          closeDate: '2026-08-22',
          title: 'Cierre ya vencido',
        })} />
        <FundingCard opportunity={listItem({
          publicId: 'd0e47508-a5c9-4e90-88c2-34be4661c25d',
          slug: 'cierre-futuro',
          closeAtUtc: '2026-08-22T20:00:01Z',
          deadlineType: 1,
          deadlinePrecision: 2,
          closeDate: '2026-08-22',
          title: 'Cierre aún vigente',
        })} />
      </MemoryRouter>,
    )

    expect(within(screen.getByTestId('funding-card-f5b75d2c-4c84-4ca3-91f7-e9c182fdff2c')).getByText('Cerrada')).toBeInTheDocument()
    expect(within(screen.getByTestId('funding-card-d0e47508-a5c9-4e90-88c2-34be4661c25d')).getByText('Vigente')).toBeInTheDocument()
  })

  it('no afirma que esté vigente cuando el plazo no está informado', () => {
    render(
      <MemoryRouter>
        <FundingCard opportunity={listItem({
          closeAtUtc: null,
          closeDate: null,
          deadlineType: 0,
          deadlinePrecision: 0,
        })} />
      </MemoryRouter>,
    )

    expect(screen.getByText('Plazo no informado')).toBeInTheDocument()
    expect(screen.queryByText('Vigente')).not.toBeInTheDocument()
  })

  it('es accesible sin sesión y muestra atribución específica por oportunidad', async () => {
    const fetchMock = vi.fn((input: RequestInfo | URL, _init?: RequestInit) => {
      const url = String(input)
      if (url.endsWith('/auth/refresh')) return Promise.resolve(json({}, 401))
      return Promise.resolve(json({ items: [listItem()], totalCount: 1, pageNumber: 1, pageSize: 12 }))
    })
    vi.stubGlobal('fetch', fetchMock)

    const router = createMemoryRouter(appRoutes, { initialEntries: ['/funding'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    expect(await screen.findByRole('heading', { name: 'Advancing Global Health' })).toBeInTheDocument()
    expect(screen.getByText(/Datos suministrados por el portal oficial/)).toBeInTheDocument()
    expect(screen.queryByText(/not endorsed or certified/)).not.toBeInTheDocument()
    expect(screen.getByText('Calidad 96/100')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Consultar fuente' })).toHaveAttribute(
      'href',
      'https://foundation.example/funds/global-health',
    )

    const catalogCall = fetchMock.mock.calls.find(([input]) => String(input).includes('/funding-opportunities?'))
    expect(catalogCall).toBeDefined()
    expect(new Headers(catalogCall?.[1]?.headers).has('Authorization')).toBe(false)
  })

  it('solicita la página siguiente al servidor cuando hay más de doce resultados', async () => {
    const fetchMock = vi.fn((input: RequestInfo | URL) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/auth/refresh')) return Promise.resolve(json({}, 401))
      const page = Number(url.searchParams.get('pageNumber') ?? 1)
      return Promise.resolve(json({
        items: [listItem(page === 1
          ? { title: 'Resultado de página uno', slug: 'pagina-uno' }
          : { publicId: 'd0e47508-a5c9-4e90-88c2-34be4661c25d', title: 'Resultado de página dos', slug: 'pagina-dos' })],
        totalCount: 13,
        pageNumber: page,
        pageSize: 12,
      }))
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/funding'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    expect(await screen.findByRole('heading', { name: 'Resultado de página uno' })).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /Siguiente/ }))
    expect(await screen.findByRole('heading', { name: 'Resultado de página dos' })).toBeInTheDocument()
    await waitFor(() => expect(fetchMock.mock.calls.some(([input]) => {
      const url = new URL(String(input), 'http://localhost')
      return url.searchParams.get('pageNumber') === '2' && url.searchParams.get('pageSize') === '12'
    })).toBe(true))
  })

  it('muestra requisitos, última verificación y calidad en la ficha pública', async () => {
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      const url = String(input)
      if (url.endsWith('/auth/refresh')) return Promise.resolve(json({}, 401))
      return Promise.resolve(json({
        ...listItem(),
        description: 'Descripción oficial completa.',
        sponsorUrl: 'https://foundation.example',
        applicationUrl: 'https://foundation.example/apply',
        eligibilityDescription: 'Fundaciones sin fines de lucro.',
        requirements: 'Estatutos vigentes\nPresupuesto detallado',
        objectives: 'Salud comunitaria',
        requiresCofunding: false,
        externalId: 'GH-2026',
        lastVerifiedAtUtc: '2026-08-20T15:30:00Z',
        funders: [],
      }))
    }))
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/funding/global-health'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    expect(await screen.findByRole('heading', { name: 'Requisitos de postulación' })).toBeInTheDocument()
    expect(screen.getByText(/Estatutos vigentes/)).toBeInTheDocument()
    expect(screen.getByText('96/100')).toBeInTheDocument()
    expect(screen.getByText((_, element) =>
      element?.tagName === 'P'
      && element.textContent?.includes('Última verificación:') === true
      && element.textContent.includes('2026'),
    )).toBeInTheDocument()
  })

  it('confirma explícitamente el hostname antes de abrir la postulación externa', async () => {
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      const url = String(input)
      if (url.endsWith('/auth/refresh')) return Promise.resolve(json({}, 401))
      return Promise.resolve(json({
        ...listItem(),
        description: 'Descripción oficial completa.',
        applicationUrl: 'https://apply.foundation.example/form?id=123',
        eligibilityDescription: null,
        requirements: null,
        objectives: null,
        requiresCofunding: null,
        externalId: null,
        lastVerifiedAtUtc: '2026-08-20T15:30:00Z',
        funders: [],
      }))
    }))
    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/funding/global-health'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    const applyButton = await screen.findByRole('button', { name: /Ir a postular/ })
    expect(screen.queryByRole('link', { name: /Continuar a apply\.foundation\.example/ })).not.toBeInTheDocument()
    await user.click(applyButton)

    const dialog = screen.getByRole('dialog', { name: 'Vas a salir de FundingPlatform' })
    expect(dialog).toHaveTextContent('apply.foundation.example')
    expect(screen.getByRole('link', { name: /Continuar a apply\.foundation\.example/ })).toHaveAttribute(
      'href',
      'https://apply.foundation.example/form?id=123',
    )
  })
})
