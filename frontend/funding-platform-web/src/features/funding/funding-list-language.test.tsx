import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import type { ReactNode } from 'react'
import { vi } from 'vitest'
import { createAppQueryClient } from '@/api/query-client'
import { apiClient } from '@/api/http-client'
import { setInterfaceLanguage } from '@/i18n'
import { organizationApi } from '@/features/organizations/organization-api'
import { fundingOrganizations, organizationFundingCatalogs, organizationFundingResponse, organizationOpportunity } from '@/test/fixtures/organization-funding'
import { FundingCatalogPage } from './funding-pages'
import { fundingOpportunitiesApi } from './funding-opportunities-api'
import { organizationFundingApi } from './organization-funding-api'
import { OrganizationFavoritesPage, OrganizationFundingCatalogPage } from './organization-funding-pages'
import { FundingExplorerPage } from '@/features/funding-discovery/funding-discovery-pages'
import { fundingDiscoveryApi } from '@/features/funding-discovery/funding-discovery-api'
import { SearchResults } from '@/features/search/search-results'

function mount(node: ReactNode) {
  const client = createAppQueryClient()
  client.setDefaultOptions({ queries: { retry: false, staleTime: Infinity } })
  return render(<QueryClientProvider client={client}><MemoryRouter>{node}</MemoryRouter></QueryClientProvider>)
}
const info = (language: 'es' | 'en', translated = true) => ({ requestedLanguage: language, status: translated ? 'translated' as const : 'original' as const, revision: translated ? 1 : null })
const page = (language?: 'es' | 'en') => ({ items: [{ ...organizationOpportunity,
  title: language === 'es' ? 'Título revisado' : language === 'en' ? 'Reviewed title' : 'Original title',
  summary: 'Summary', coverKey: 'research-v1', localization: language ? info(language) : undefined }], totalCount: 25, pageNumber: 1, pageSize: 12 })

beforeEach(() => vi.stubEnv('VITE_FUNDING_TRANSLATIONS_ENABLED', 'true'))
afterEach(() => { vi.unstubAllEnvs(); vi.unstubAllGlobals(); vi.restoreAllMocks() })

it('serializes list locale separately from eligibility filters and disables HTTP caching', async () => {
  const get = vi.spyOn(apiClient, 'get').mockResolvedValue({ items: [] })
  const signal = new AbortController().signal
  await fundingOpportunitiesApi.search('water', 2, 12, signal, 'es')
  await organizationFundingApi.search('org', { pageNumber: 2, pageSize: 12, countryIds: [152] }, signal, 'en')
  await organizationFundingApi.favorites('org', 2, 12, signal, 'es')
  const criteria = new URLSearchParams({ query: 'water', languageId: '1', locale: 'fr' })
  await fundingDiscoveryApi.search(criteria, signal, 'en')
  expect(criteria.get('locale')).toBe('fr')
  for (const [, options] of get.mock.calls) expect(options).toEqual({ signal, cache: 'no-store' })
  expect(get.mock.calls.map(call => call[0])).toEqual([
    'funding-opportunities?pageNumber=2&pageSize=12&query=water&locale=es',
    'organizations/org/funding-opportunities?page=2&pageSize=12&countryIds=152&locale=en',
    'organizations/org/favorites?page=2&pageSize=12&locale=es',
    'funding-discovery?query=water&languageId=1&locale=en',
  ])
})

it('changes list language without losing unsent search, showing previous-language placeholders or changing links/covers', async () => {
  let finish!: (value: ReturnType<typeof page>) => void
  const pending = new Promise<ReturnType<typeof page>>(resolve => { finish = resolve })
  const search = vi.spyOn(fundingOpportunitiesApi, 'search').mockImplementation(async (_query, _page, _size, _signal, locale) => locale === 'en' ? pending : page(locale))
  mount(<FundingCatalogPage />)
  await screen.findByRole('heading', { name: 'Título revisado' })
  fireEvent.change(screen.getByRole('textbox', { name: 'Buscar oportunidades' }), { target: { value: 'borrador sin buscar' } })
  expect(screen.getByText('Traducción revisada')).toBeInTheDocument()
  const link = screen.getByRole('link', { name: 'Ver ficha completa' }).getAttribute('href')
  await act(() => setInterfaceLanguage('en'))
  expect(screen.queryByRole('heading', { name: 'Título revisado' })).not.toBeInTheDocument()
  expect(screen.getByRole('textbox', { name: 'Search opportunities' })).toHaveValue('borrador sin buscar')
  await act(async () => { finish(page('en')); await pending })
  await screen.findByRole('heading', { name: 'Reviewed title' })
  expect(screen.getByRole('link', { name: 'View full details' })).toHaveAttribute('href', link)
  expect(screen.getByRole('img', { name: 'Thematic cover illustration: Science and innovation' })).toBeInTheDocument()
  await userEvent.click(screen.getByRole('button', { name: 'View original text' }))
  await screen.findByRole('heading', { name: 'Original title' })
  expect(screen.queryByText('Reviewed translation')).not.toBeInTheDocument()
  expect(screen.getByText(/Showing original texts. Search also includes titles and summaries with a current reviewed Spanish or English translation/)).toBeInTheDocument()
  expect(search.mock.calls.map(call => call[4])).toEqual(['es', 'en', undefined])
})

it('labels fallback originals and explains that bilingual search requires current reviewed text', async () => {
  vi.spyOn(fundingOpportunitiesApi, 'search').mockResolvedValue({ ...page(), items: [{ ...page().items[0], localization: info('es', false) }] })
  mount(<FundingCatalogPage />)
  await screen.findByRole('heading', { name: 'Original title' })
  expect(screen.getByText('Texto original · traducción no disponible')).toBeInTheDocument()
  expect(screen.getByText(/La búsqueda incluye el texto original y los títulos y resúmenes con traducción revisada vigente/)).toBeInTheDocument()
})

it.each(['search', 'favorites'] as const)('localizes organization %s and retains favorite and page state', async area => {
  vi.spyOn(organizationApi, 'list').mockResolvedValue(fundingOrganizations)
  vi.spyOn(organizationApi, 'catalogs').mockResolvedValue(organizationFundingCatalogs)
  const response = (locale?: 'es' | 'en') => ({ ...organizationFundingResponse(true), items: [{ ...organizationOpportunity, ...page(locale).items[0], isFavorite: true }] })
  const search = vi.spyOn(organizationFundingApi, 'search').mockImplementation(async (_org, _criteria, _signal, locale) => response(locale))
  const favorites = vi.spyOn(organizationFundingApi, 'favorites').mockImplementation(async (_org, _page, _size, _signal, locale) => response(locale))
  const add = vi.spyOn(organizationFundingApi, 'addFavorite')
  mount(area === 'search' ? <OrganizationFundingCatalogPage /> : <OrganizationFavoritesPage />)
  await screen.findByRole('heading', { name: 'Título revisado' })
  expect(screen.getByRole('button', { name: 'Quitar de favoritos' })).toHaveAttribute('aria-pressed', 'true')
  await act(() => setInterfaceLanguage('en'))
  await screen.findByRole('heading', { name: 'Reviewed title' })
  expect(screen.getByRole('button', { name: 'Remove from favorites' })).toHaveAttribute('aria-pressed', 'true')
  expect(add).not.toHaveBeenCalled()
  expect(area === 'search' ? search.mock.calls.map(call => call[3]) : favorites.mock.calls.map(call => call[4])).toEqual(['es', 'en'])
})

it('requests language in advanced discovery while keeping the draft filters intact', async () => {
  vi.spyOn(fundingDiscoveryApi, 'catalogs').mockResolvedValue(organizationFundingCatalogs)
  const search = vi.spyOn(fundingDiscoveryApi, 'search').mockImplementation(async (_params, _signal, locale) => ({
    items: [{ id: 'test', slug: 'test', title: locale === 'es' ? 'Título revisado' : 'Reviewed title', summary: 'Summary',
      sourceName: 'Source', sourceUrl: 'https://example.invalid', lastVerifiedAtUtc: null, minimumAmount: null, maximumAmount: null,
      currency: null, closeDate: null, classification: null, localization: info(locale ?? 'es') }], totalCount: 1, page: 1, pageSize: 20,
  }))
  mount(<FundingExplorerPage />)
  await screen.findByRole('heading', { name: 'Título revisado' })
  const draft = document.querySelector('input[name="query"]')!
  fireEvent.change(draft, { target: { value: 'sin enviar' } })
  await act(() => setInterfaceLanguage('en'))
  await screen.findByRole('heading', { name: 'Reviewed title' })
  expect(document.querySelector('input[name="query"]')).toHaveValue('sin enviar')
  expect(search.mock.calls.map(call => call[2])).toEqual(['es', 'en'])
})

it('sends locale only to the funding source in unified search', async () => {
  const requests: string[] = []
  vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
    const url = String(input); requests.push(url)
    const locale = url.includes('locale=en') ? 'en' : 'es'
    return new Response(JSON.stringify({ items: [{ id: 'test', slug: 'test', title: locale === 'es' ? 'Título revisado' : 'Reviewed title',
      summary: 'Summary', sourceName: 'Source', localization: info(locale) }], totalCount: 1, page: 2, pageSize: 20 }),
      { headers: { 'Content-Type': 'application/json' } })
  }))
  mount(<SearchResults source="funding" criteria={{ scope: 'funding', q: 'agua', countryId: '152', categoryId: '', page: 2 }} actor="public" />)
  await screen.findByRole('heading', { name: 'Título revisado' })
  await act(() => setInterfaceLanguage('en'))
  await screen.findByRole('heading', { name: 'Reviewed title' })
  expect(requests).toHaveLength(2)
  for (const url of requests) {
    expect(url).toContain('funding-discovery?')
    expect(url).toContain('query=agua')
    expect(url).toContain('page=2')
    expect(url).toContain('countryId=152')
  }
  expect(requests[0]).toContain('locale=es')
  expect(requests[1]).toContain('locale=en')
})

it('keeps list localization disabled without extra reads or notices', async () => {
  vi.stubEnv('VITE_FUNDING_TRANSLATIONS_ENABLED', 'false')
  const search = vi.spyOn(fundingOpportunitiesApi, 'search').mockResolvedValue(page())
  mount(<FundingCatalogPage />)
  await screen.findByRole('heading', { name: 'Original title' })
  await act(() => setInterfaceLanguage('en'))
  await waitFor(() => expect(search).toHaveBeenCalledTimes(1))
  expect(search.mock.calls[0]).toHaveLength(4)
  expect(screen.queryByRole('button', { name: 'View original text' })).not.toBeInTheDocument()
})
