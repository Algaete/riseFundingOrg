import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { setInterfaceLanguage } from '@/i18n'
import { workspaceCatalogs } from '@/test/fixtures/project-workspace'
import { ProfessionalDirectoryPage } from './professional-directory-page'

function setup(items: unknown, totalCount = 0, status = 200) {
  const requests: URL[] = []
  let responseStatus = status
  let responseItems = items
  const fetch = vi.fn((input: RequestInfo | URL, options?: RequestInit) => {
    if (options?.method !== 'GET') throw new Error('Unexpected write')
    const url = new URL(String(input), 'https://example.invalid')
    const catalogs = url.pathname.endsWith('/catalogs')
    if (!catalogs) requests.push(url)
    return Promise.resolve(new Response(JSON.stringify(catalogs ? workspaceCatalogs :
      { items: responseItems, totalCount, page: 1, pageSize: 20 }), {
      status: catalogs ? 200 : responseStatus, headers: { 'Content-Type': 'application/json' },
    }))
  })
  vi.stubGlobal('fetch', fetch)
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  render(<MemoryRouter><QueryClientProvider client={client}><ProfessionalDirectoryPage /></QueryClientProvider></MemoryRouter>)
  return { requests, recover: () => { responseStatus = 200; responseItems = [] } }
}

describe('directorio de profesionales con colecciones vacías', () => {
  afterEach(() => vi.unstubAllGlobals())

  for (const locale of ['es', 'en'] as const) {
    it.each([null, undefined, []])(`muestra el estado vacío y conserva búsqueda y filtros en ${locale}: %j`, async items => {
      await setInterfaceLanguage(locale)
      const { requests } = setup(items)
      const english = locale === 'en'
      const empty = english ? 'No results.' : 'No hay resultados.'
      expect(await screen.findByText(empty)).toBeVisible()
      await userEvent.selectOptions(screen.getByLabelText(english ? 'Country' : 'País'), '152')
      await userEvent.selectOptions(screen.getByLabelText(english ? 'Impact areas' : 'Áreas de impacto'), '1')
      await userEvent.type(screen.getByLabelText(english ? 'Name, specialty or skill' : 'Nombre, especialidad o competencia'), 'Datos')
      await userEvent.click(screen.getByRole('button', { name: english ? 'Search' : 'Buscar' }))
      await waitFor(() => expect(requests.at(-1)?.searchParams.get('q')).toBe('Datos'))
      expect(requests.at(-1)?.searchParams.get('countryId')).toBe('152')
      expect(requests.at(-1)?.searchParams.get('categoryId')).toBe('1')
      expect(await screen.findByText(empty)).toBeVisible()
      expect(screen.queryByRole('alert')).not.toBeInTheDocument()
      expect(screen.getByRole('button', { name: english ? 'Next' : 'Siguiente' })).toBeDisabled()
    })
  }

  it('mantiene visibles los profesionales presentes y su consentimiento', async () => {
    setup([{ profileId: 'test-professional', data: {
      displayName: 'TEST · Profesional', headline: 'Investigación', biography: null,
      countryId: null, skills: ['GIS'], languageIds: [], categoryIds: [],
      isDiscoverable: true, allowsInvitations: false,
    } }], 1)
    expect(await screen.findByRole('heading', { name: 'TEST · Profesional' })).toBeVisible()
    expect(screen.getByText('GIS')).toBeVisible()
    expect(screen.queryByRole('link', { name: 'Elegir consorcio para invitar' })).not.toBeInTheDocument()
  })

  it('permite reintentar un fallo de carga sin mostrarlo como una lista vacía', async () => {
    const { recover } = setup(null, 0, 503)
    expect(await screen.findByRole('alert')).toHaveTextContent('No fue posible completar la operación.')
    expect(screen.queryByText('No hay resultados.')).not.toBeInTheDocument()
    recover()
    await userEvent.click(screen.getByRole('button', { name: 'Volver a cargar' }))
    expect(await screen.findByText('No hay resultados.')).toBeVisible()
  })
})
