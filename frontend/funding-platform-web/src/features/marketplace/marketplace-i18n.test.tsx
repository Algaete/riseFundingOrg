import { QueryClientProvider } from '@tanstack/react-query'
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter, RouterProvider } from 'react-router-dom'

import { createAppQueryClient } from '@/api/query-client'
import { marketplaceApi } from './marketplace-api'
import { MarketplacePage, MarketplaceOrganizationPage, MarketplaceProjectDetailPage } from './marketplace-pages'
import { setInterfaceLanguage } from '@/i18n'
import { discoveryOrganization, discoveryProject } from '@/test/fixtures/public-discovery'
import { workspaceCatalogs, workspacePublicProject } from '@/test/fixtures/project-workspace'

function renderMarketplace(path = '/marketplace') {
  const client = createAppQueryClient()
  client.setDefaultOptions({ queries: { retry: false, staleTime: 30_000 } })
  const router = createMemoryRouter([
    { path: '/marketplace', element: <MarketplacePage /> },
    { path: '/marketplace/organizations/:organizationId', element: <MarketplaceOrganizationPage /> },
    { path: '/marketplace/projects/:slug', element: <MarketplaceProjectDetailPage /> },
  ], { initialEntries: [path] })
  render(<QueryClientProvider client={client}><RouterProvider router={router} /></QueryClientProvider>)
  return router
}

describe('marketplace language changes', () => {
  beforeEach(() => {
    vi.spyOn(marketplaceApi, 'catalogs').mockResolvedValue(workspaceCatalogs)
    vi.spyOn(marketplaceApi, 'search').mockImplementation(async input => ({ items: [discoveryProject], totalCount: 25, pageNumber: input.page ?? 1, pageSize: input.pageSize ?? 12 }))
    vi.spyOn(marketplaceApi, 'getOrganization').mockResolvedValue(discoveryOrganization)
    vi.spyOn(marketplaceApi, 'getProject').mockResolvedValue(workspacePublicProject)
  })
  afterEach(() => vi.restoreAllMocks())

  it('preserves the query, all filters, order, page and catalog IDs without repeating reads', async () => {
    const query = '?q=Ñandú&countryId=152&categoryId=1&projectTypeId=4&status=2&currency=USD&sort=funding-gap-desc&page=2&keep=original'
    const router = renderMarketplace(`/marketplace${query}`)
    await screen.findByRole('heading', { name: discoveryProject.title })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('searchbox', { name: 'Search projects' })).toHaveValue('Ñandú')
    for (const [name, value] of [['Country', '152'], ['Impact area', '1'], ['Project type', '4'], ['Status', '2'], ['Currency', 'USD'], ['Sort by', 'funding-gap-desc']]) {
      expect(screen.getByRole('combobox', { name })).toHaveValue(value)
    }
    expect(screen.getByText('Page 2 of 3')).toBeVisible()
    expect(screen.getByText('$75,000.00')).toBeVisible()
    expect(screen.getByText('Jan 1, 2027 — Dec 31, 2027')).toBeVisible()
    expect(screen.getByRole('option', { name: 'Medio ambiente' })).toHaveAttribute('lang', 'es')
    expect(router.state.location.search).toBe(query)
    expect(marketplaceApi.catalogs).toHaveBeenCalledOnce()
    expect(marketplaceApi.search).toHaveBeenCalledExactlyOnceWith({ query: 'Ñandú', countryIds: [152], categoryIds: [1], projectTypeIds: [4], projectStatus: 2, currency: 'USD', sort: 'funding-gap-desc', page: 2, pageSize: 12 }, expect.any(AbortSignal))
    await userEvent.click(screen.getByRole('button', { name: 'Next' }))
    await screen.findByText('Page 3 of 3')
    expect(new URLSearchParams(router.state.location.search).get('keep')).toBe('original')
    expect(marketplaceApi.search).toHaveBeenCalledTimes(2)
  })

  it('preserves a pending search debounce across languages and resets only the page when it applies', async () => {
    const router = renderMarketplace('/marketplace?countryId=152&page=2')
    await screen.findByRole('heading', { name: discoveryProject.title })
    fireEvent.change(screen.getByRole('searchbox', { name: 'Buscar proyectos' }), { target: { value: '  Agua Ñandú  ' } })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('searchbox', { name: 'Search projects' })).toHaveValue('  Agua Ñandú  ')
    expect(marketplaceApi.search).toHaveBeenCalledOnce()
    await waitFor(() => expect(marketplaceApi.search).toHaveBeenCalledTimes(2))
    expect(marketplaceApi.search).toHaveBeenLastCalledWith(expect.objectContaining({ query: 'Agua Ñandú', countryIds: [152], page: 1 }), expect.any(AbortSignal))
    expect(new URLSearchParams(router.state.location.search).get('countryId')).toBe('152')
    await act(() => setInterfaceLanguage('es'))
    expect(marketplaceApi.search).toHaveBeenCalledTimes(2)
  })

  it('keeps financial ordering unavailable without a currency and clears filters only explicitly', async () => {
    const router = renderMarketplace('/marketplace?q=agua&sort=funding-gap-desc')
    await screen.findByRole('heading', { name: discoveryProject.title })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('option', { name: 'Largest reported gap (same currency)' })).toBeDisabled()
    expect(screen.getByRole('combobox', { name: 'Sort by' })).toHaveValue('newest')
    expect(marketplaceApi.search).toHaveBeenCalledOnce()
    await userEvent.click(screen.getByRole('button', { name: 'Clear filters' }))
    await waitFor(() => expect(marketplaceApi.search).toHaveBeenCalledTimes(2))
    expect(router.state.location.search).toBe('')
    expect(screen.getByRole('searchbox', { name: 'Search projects' })).toHaveValue('')
  })

  it('does not reveal drafts or projects under review after changing language', async () => {
    vi.mocked(marketplaceApi.search).mockResolvedValue({ items: [discoveryProject, ...[0, 1, 3, 4].map(status => ({ ...discoveryProject, publicId: `private-${status}`, title: `Private ${status}`, publicationStatus: status }))], totalCount: 1, pageNumber: 1, pageSize: 12 })
    renderMarketplace()
    await screen.findByRole('heading', { name: discoveryProject.title })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.queryByText(/Private [0134]/)).not.toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'View project' })).toHaveAttribute('href', `/marketplace/projects/${discoveryProject.slug}`)
  })

  it('preserves public organization content and excludes private fields and drafts', async () => {
    const response = { ...discoveryOrganization, contactEmail: 'private@example.invalid', taxIdentifier: 'private-tax-id', projects: [discoveryProject, { ...discoveryProject, title: 'Private draft', publicId: 'private', publicationStatus: 0 }] }
    vi.mocked(marketplaceApi.getOrganization).mockResolvedValue(response)
    renderMarketplace(`/marketplace/organizations/${discoveryOrganization.publicId}`)
    await screen.findByRole('heading', { name: discoveryOrganization.name, level: 1 })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByText(discoveryOrganization.description)).toBeVisible()
    expect(screen.getByText('Since 2010')).toBeVisible()
    expect(screen.getByRole('heading', { name: 'Projects by Fundación Ñandú' })).toBeVisible()
    expect(screen.queryByText(/private@example|private-tax-id|Private draft/)).not.toBeInTheDocument()
    expect(screen.getByText('Medio ambiente')).toHaveAttribute('lang', 'es')
    expect(marketplaceApi.getOrganization).toHaveBeenCalledOnce()
  })

  it('uses the already-translated canonical project view without a second detail request', async () => {
    renderMarketplace(`/marketplace/projects/${discoveryProject.slug}`)
    await screen.findByRole('heading', { name: discoveryProject.title, level: 1 })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('heading', { name: 'About the project' })).toBeVisible()
    expect(screen.getByText(workspacePublicProject.description)).toBeVisible()
    expect(marketplaceApi.getProject).toHaveBeenCalledOnce()
  })

  it('localizes failure and empty states without automatic retries', async () => {
    vi.mocked(marketplaceApi.search).mockRejectedValueOnce(new Error('private diagnostic')).mockResolvedValue({ items: [], totalCount: 0, pageNumber: 1, pageSize: 12 })
    renderMarketplace()
    await screen.findByRole('alert')
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('alert')).toHaveTextContent('Check your connection and try again.')
    expect(marketplaceApi.search).toHaveBeenCalledOnce()
    await userEvent.click(screen.getByRole('button', { name: 'Retry' }))
    expect(await screen.findByText('No projects found')).toBeVisible()
    expect(marketplaceApi.search).toHaveBeenCalledTimes(2)
  })

  it('localizes an unavailable public organization without exposing the server message', async () => {
    vi.mocked(marketplaceApi.getOrganization).mockRejectedValue(new Error('private diagnostic'))
    renderMarketplace(`/marketplace/organizations/${discoveryOrganization.publicId}`)
    await screen.findByRole('heading', { name: 'Organización no disponible' })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('heading', { name: 'Organization unavailable' })).toBeVisible()
    expect(screen.getByRole('link', { name: 'Back to marketplace' })).toHaveAttribute('href', '/marketplace')
    expect(screen.queryByText('private diagnostic')).not.toBeInTheDocument()
    expect(marketplaceApi.getOrganization).toHaveBeenCalledOnce()
  })
})
