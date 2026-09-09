import { QueryClientProvider } from '@tanstack/react-query'
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter, RouterProvider } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { createAppQueryClient } from '@/api/query-client'
import { organizationApi } from '@/features/organizations/organization-api'
import { setInterfaceLanguage } from '@/i18n'
import { consumerCatalogs, consumerOpportunity } from '@/test/fixtures/catalog-consumers'
import { fundingOrganizationId, fundingOrganizations, organizationFundingCatalogs, organizationFundingResponse, organizationOpportunity } from '@/test/fixtures/organization-funding'
import { organizationFundingApi } from './organization-funding-api'
import { OrganizationFavoritesPage, OrganizationFundingCatalogPage, OrganizationFundingDetailPage } from './organization-funding-pages'

function mount(path = '/opportunities', client = createAppQueryClient()) {
  client.setDefaultOptions({ queries: { retry: false, staleTime: 30_000 } })
  const router = createMemoryRouter([
    { path: '/opportunities', element: <OrganizationFundingCatalogPage /> },
    { path: '/opportunities/:slug', element: <OrganizationFundingDetailPage /> },
    { path: '/favorites', element: <OrganizationFavoritesPage /> },
  ], { initialEntries: [path] })
  render(<QueryClientProvider client={client}><RouterProvider router={router} /></QueryClientProvider>)
  return { router, client }
}

function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (reason: unknown) => void
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no })
  return { promise, resolve, reject }
}

describe('organization funding ES/EN', () => {
  beforeEach(() => {
    vi.spyOn(organizationApi, 'list').mockResolvedValue(fundingOrganizations)
    vi.spyOn(organizationApi, 'catalogs').mockResolvedValue(organizationFundingCatalogs)
    vi.spyOn(organizationFundingApi, 'search').mockResolvedValue(organizationFundingResponse())
    vi.spyOn(organizationFundingApi, 'getByIdOrSlug').mockResolvedValue(organizationOpportunity)
    vi.spyOn(organizationFundingApi, 'favorites').mockResolvedValue(organizationFundingResponse(true))
    vi.spyOn(organizationFundingApi, 'addFavorite').mockResolvedValue(undefined)
    vi.spyOn(organizationFundingApi, 'removeFavorite').mockResolvedValue(undefined)
  })
  afterEach(() => { vi.restoreAllMocks(); vi.useRealTimers() })

  it.each([false, true])('keeps a pending favorite command and its result stable across a language change (initial=%s)', async initial => {
    let favorite = initial
    vi.mocked(organizationFundingApi.search).mockImplementation(async () => organizationFundingResponse(favorite))
    const pending = deferred<void>()
    const command = initial ? organizationFundingApi.removeFavorite : organizationFundingApi.addFavorite
    vi.mocked(command).mockImplementation(() => pending.promise)
    mount()
    const button = await screen.findByRole('button', { name: initial ? 'Quitar de favoritos' : 'Guardar en favoritos' })
    await userEvent.click(button)
    await waitFor(() => expect(button).toHaveAttribute('aria-pressed', String(!initial)))
    expect(button).toBeDisabled()
    await act(() => setInterfaceLanguage('en'))
    expect(button).toHaveAccessibleName(initial ? 'Save to favorites' : 'Remove from favorites')
    expect(command).toHaveBeenCalledExactlyOnceWith(fundingOrganizationId, organizationOpportunity.publicId)
    expect(organizationFundingApi.search).toHaveBeenCalledOnce()
    favorite = !initial
    await act(async () => { pending.resolve(); await pending.promise })
    expect(await screen.findByText(initial ? 'Opportunity removed from favorites.' : 'Opportunity saved to favorites.')).toBeInTheDocument()
    await waitFor(() => expect(button).toBeEnabled())
    await act(() => setInterfaceLanguage('es'))
    expect(screen.getByText(initial ? 'Oportunidad eliminada de favoritos.' : 'Oportunidad guardada en favoritos.')).toBeInTheDocument()
    expect(command).toHaveBeenCalledOnce()
    expect(initial ? organizationFundingApi.addFavorite : organizationFundingApi.removeFavorite).not.toHaveBeenCalled()
  })

  it('preserves server filters, the existing organization, pagination and saved-search destination without a write', async () => {
    vi.mocked(organizationFundingApi.search).mockImplementation(async (_org, criteria) => organizationFundingResponse(false, criteria.pageNumber, 25))
    const initial = '/opportunities?q=agua&countryIds=152&regionIds=7&categoryIds=1&tagIds=9&beneficiaryTypeIds=1&projectTypeIds=4&fundingTypeIds=3&organizationTypeIds=2&sponsor=Ñandú&minAmount=25000&maxAmount=100000&currency=USD&closingFrom=2027-01-01&closingTo=2030-12-31&onlyOpen=false&sort=amount-desc&page=2&pageSize=12'
    const { router } = mount(initial)
    await screen.findByRole('heading', { name: organizationOpportunity.title })
    const location = router.state.location.search
    const saved = screen.getByRole('link', { name: 'Guardar búsqueda' }).getAttribute('href')
    const details = screen.getByText('Filtros avanzados').closest('details')!
    await userEvent.click(details.querySelector('summary')!)
    expect(details.open).toBe(false)
    await act(() => setInterfaceLanguage('en'))
    expect(details.open).toBe(false)
    expect(router.state.location.search).toBe(location)
    expect(screen.getByText('Page 2 of 3')).toBeVisible()
    expect(screen.getByRole('link', { name: 'Save search' })).toHaveAttribute('href', saved)
    const savedParams = new URL(saved!, 'http://localhost').searchParams
    expect(savedParams.get('new')).toBe('true')
    expect(savedParams.has('page')).toBe(false)
    expect(savedParams.has('pageSize')).toBe(false)
    expect(savedParams.get('countryIds')).toBe('152')
    expect(savedParams.get('sponsor')).toBe('Ñandú')
    expect(organizationFundingApi.search).toHaveBeenCalledExactlyOnceWith(fundingOrganizationId, {
      query: 'agua', countryIds: [152], regionIds: [7], categoryIds: [1], tagIds: [9],
      beneficiaryTypeIds: [1], projectTypeIds: [4], fundingTypeIds: [3], organizationTypeIds: [2],
      sponsor: 'Ñandú', minimumAmount: 25000, maximumAmount: 100000, currency: 'USD',
      closingFrom: '2027-01-01', closingTo: '2030-12-31', onlyOpen: false, sort: 'amount-desc', pageNumber: 2, pageSize: 12,
    }, expect.any(AbortSignal))
    await userEvent.click(details.querySelector('summary')!)
    expect(screen.getByRole('combobox', { name: 'Country' })).toHaveValue('152')
    expect(screen.getByRole('option', { name: 'Environment' })).toHaveAttribute('lang', 'en')
    expect(screen.getByRole('checkbox', { name: 'Open opportunities only' })).not.toBeChecked()
    await userEvent.click(screen.getByRole('button', { name: 'Next' }))
    await screen.findByText('Page 3 of 3')
    expect(router.state.location.search).toContain('countryIds=152')
    expect(organizationFundingApi.search).toHaveBeenCalledTimes(2)
    expect(organizationFundingApi.addFavorite).not.toHaveBeenCalled()
    expect(organizationFundingApi.removeFavorite).not.toHaveBeenCalled()
    expect(organizationApi.list).toHaveBeenCalledOnce()
  })

  it('keeps the unsent search text and its debounce when switching language', async () => {
    const { router } = mount('/opportunities?page=2')
    await screen.findByRole('heading', { name: organizationOpportunity.title })
    fireEvent.change(screen.getByRole('textbox', { name: 'Buscar oportunidades' }), { target: { value: '  Salud Ñandú  ' } })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('textbox', { name: 'Search opportunities' })).toHaveValue('  Salud Ñandú  ')
    expect(organizationFundingApi.search).toHaveBeenCalledOnce()
    await waitFor(() => expect(organizationFundingApi.search).toHaveBeenLastCalledWith(
      fundingOrganizationId, expect.objectContaining({ query: 'Salud Ñandú', sort: 'relevance', pageNumber: 1 }), expect.any(AbortSignal),
    ), { timeout: 2000 })
    expect(organizationFundingApi.search).toHaveBeenCalledTimes(2)
    expect(new URLSearchParams(router.state.location.search).has('page')).toBe(false)
    expect(organizationFundingApi.addFavorite).not.toHaveBeenCalled()
  })

  it.each([
    ['minAmount=20&maxAmount=10&currency=USD', 'El monto mínimo no puede superar al máximo.', 'The minimum amount cannot exceed the maximum.'],
    ['minAmount=20', 'Selecciona una moneda para filtrar por monto.', 'Select a currency to filter by amount.'],
    ['sort=amount-desc', 'Selecciona una moneda para ordenar por monto.', 'Select a currency to sort by amount.'],
    ['closingFrom=2030-12-31&closingTo=2027-01-01', 'La fecha inicial de cierre no puede ser posterior a la final.', 'The first closing date cannot be after the last.'],
  ])('keeps invalid criteria blocked in both languages (%s)', async (query, spanish, english) => {
    const { router } = mount('/opportunities?' + query)
    expect(await screen.findByRole('alert')).toHaveTextContent(spanish)
    expect(screen.queryByText('Buscando oportunidades…')).not.toBeInTheDocument()
    const details = screen.getByText('Filtros avanzados').closest('details')!
    expect(details.open).toBe(true)
    await userEvent.click(details.querySelector('summary')!)
    expect(screen.getByRole('alert')).toBeVisible()
    const location = router.state.location.search
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('alert')).toHaveTextContent(english)
    expect(screen.getByRole('alert')).toBeVisible()
    expect(screen.queryByText('Searching opportunities…')).not.toBeInTheDocument()
    expect(details.open).toBe(false)
    expect(router.state.location.search).toBe(location)
    expect(organizationFundingApi.search).not.toHaveBeenCalled()
    expect(organizationFundingApi.addFavorite).not.toHaveBeenCalled()
    expect(organizationFundingApi.removeFavorite).not.toHaveBeenCalled()
  })

  it('translates reviewed catalog names but keeps conditions, exact UTC deadline and application destination', async () => {
    mount('/opportunities/' + organizationOpportunity.slug)
    await screen.findByRole('heading', { name: 'Condiciones publicadas' })
    expect(screen.getByText('12,5%')).toBeVisible()
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('heading', { name: 'Published conditions' })).toBeVisible()
    expect(screen.getByText('12.5%')).toBeVisible()
    expect(screen.getByText('America/Santiago')).toBeVisible()
    const exact = screen.getByText('Exact closing time').nextElementSibling!
    expect(exact.textContent).toBe(new Intl.DateTimeFormat('en-US', {
      dateStyle: 'medium', timeStyle: 'short', timeZone: 'UTC',
    }).format(new Date(organizationOpportunity.closeAtUtc)) + ' UTC')
    expect(screen.getByText('Legal entity required').nextElementSibling).toHaveTextContent('Yes')
    expect(screen.getByText('Prior experience required').nextElementSibling).toHaveTextContent('Not reported')
    expect(screen.getByText('Remote application').nextElementSibling).toHaveTextContent('Yes')
    for (const value of [
      organizationOpportunity.allowedActivities, organizationOpportunity.excludedActivities,
      organizationOpportunity.restrictions, organizationOpportunity.targetOrganizationsDescription, organizationOpportunity.targetPopulationsDescription,
    ]) expect(screen.getByText(value)).toHaveAttribute('lang', 'es')
    const eligible = screen.getByRole('heading', { name: 'Organization types' }).parentElement!
    expect(eligible).toHaveTextContent('Foundation · eligible')
    expect(within(eligible).getByText('Foundation')).toHaveAttribute('lang', 'en')
    expect(screen.getByRole('heading', { name: 'Legal entity types' }).parentElement).toHaveTextContent('Foundation · excluded')
    for (const name of ['Grant', 'Children and adolescents', 'Institutional strengthening', 'Spanish']) {
      expect(screen.getByText(name, { exact: true })).toHaveAttribute('lang', 'en')
    }
    expect(screen.getByRole('link', { name: 'Start application' })).toHaveAttribute('href', '/applications?new=1&fundingOpportunityId=' + organizationOpportunity.publicId)
    expect(screen.getByRole('link', { name: 'Fuente vinculada Ñandú' })).toHaveAttribute('href', organizationOpportunity.sources[0].sourceUrl)
    expect(screen.getByText('Reference ORIGINAL-01')).toBeVisible()
    expect(screen.getByText('These details come from the terms and do not, by themselves, confirm your organization’s eligibility.')).toBeVisible()
    expect(organizationFundingApi.getByIdOrSlug).toHaveBeenCalledExactlyOnceWith(fundingOrganizationId, organizationOpportunity.slug, expect.any(AbortSignal))
    expect(organizationFundingApi.addFavorite).not.toHaveBeenCalled()
    expect(organizationFundingApi.removeFavorite).not.toHaveBeenCalled()
  })

  it('keeps unreviewed labels, topics, missing references and distinct classification IDs without rewriting the cache', async () => {
    const data = { ...consumerOpportunity, categoryIds: [...consumerOpportunity.categoryIds, 81, 999] }
    vi.mocked(organizationApi.catalogs).mockResolvedValue(consumerCatalogs)
    vi.mocked(organizationFundingApi.getByIdOrSlug).mockResolvedValue(data)
    const { client } = mount('/opportunities/' + data.slug)
    await screen.findByRole('heading', { name: 'Cobertura y clasificaciones de las bases' })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByText('Environment and biodiversity')).toHaveAttribute('lang', 'en')
    for (const name of ['Educación comunitaria Ñandú', 'Nueva área Ñandú', 'Medio ambiente']) {
      expect(screen.getByText(name, { exact: true })).toHaveAttribute('lang', 'es')
    }
    expect(screen.getAllByText('Other', { exact: true })).toHaveLength(2)
    expect(screen.queryByText('999')).not.toBeInTheDocument()
    expect(screen.getByText('English', { exact: true })).toHaveAttribute('lang', 'en')
    expect(client.getQueryData(['organization-catalogs'])).toBe(consumerCatalogs)
    expect(client.getQueryData(['organization-funding', fundingOrganizationId, 'detail', data.slug])).toBe(data)
    await act(() => setInterfaceLanguage('es'))
    expect(screen.getByText('Medio ambiente y biodiversidad')).toHaveAttribute('lang', 'es')
    expect(screen.getAllByText('Otros', { exact: true })).toHaveLength(2)
    expect(organizationApi.catalogs).toHaveBeenCalledOnce()
    expect(organizationFundingApi.getByIdOrSlug).toHaveBeenCalledOnce()
    expect(organizationFundingApi.addFavorite).not.toHaveBeenCalled()
    expect(organizationFundingApi.removeFavorite).not.toHaveBeenCalled()
  })

  it('renders a pending catalog in the current language without restarting either read', async () => {
    const pending = deferred<typeof consumerCatalogs>()
    vi.mocked(organizationApi.catalogs).mockReturnValue(pending.promise)
    mount('/opportunities/' + organizationOpportunity.slug)
    await screen.findByRole('heading', { name: 'Condiciones publicadas' })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.queryByText('Foundation · eligible')).not.toBeInTheDocument()
    await act(async () => pending.resolve(consumerCatalogs))
    const eligible = await screen.findByRole('heading', { name: 'Organization types' })
    expect(eligible.parentElement).toHaveTextContent('Foundation · eligible')
    expect(screen.getByText('Environment and biodiversity')).toHaveAttribute('lang', 'en')
    expect(organizationApi.catalogs).toHaveBeenCalledOnce()
    expect(organizationFundingApi.getByIdOrSlug).toHaveBeenCalledOnce()
    expect(organizationFundingApi.addFavorite).not.toHaveBeenCalled()
  })

  it('rolls back a failed favorite across this organization’s caches without touching another organization', async () => {
    const client = createAppQueryClient()
    const detailKey = ['organization-funding', fundingOrganizationId, 'detail', organizationOpportunity.slug]
    const favoritesKey = ['organization-funding', fundingOrganizationId, 'favorites', 1, 12]
    const otherKey = ['organization-funding', fundingOrganizations[1].publicId, 'detail', organizationOpportunity.slug]
    client.setQueryData(detailKey, organizationOpportunity)
    client.setQueryData(favoritesKey, organizationFundingResponse())
    client.setQueryData(otherKey, organizationOpportunity)
    const pending = deferred<void>()
    vi.mocked(organizationFundingApi.addFavorite).mockImplementation(() => pending.promise)
    mount('/opportunities', client)
    await userEvent.click(await screen.findByRole('button', { name: 'Guardar en favoritos' }))
    await waitFor(() => expect(client.getQueryData(detailKey)).toMatchObject({ isFavorite: true }))
    expect(client.getQueryData(favoritesKey)).toMatchObject({ items: [{ isFavorite: true }] })
    expect(client.getQueryData(otherKey)).toBe(organizationOpportunity)
    await act(() => setInterfaceLanguage('en'))
    await act(async () => { pending.reject(new Error('Private server diagnostic')); await pending.promise.catch(() => undefined) })
    expect(await screen.findByRole('alert')).toHaveTextContent('We could not update the favorite. Try again.')
    expect(screen.queryByText(/Private server/)).not.toBeInTheDocument()
    expect(client.getQueryData(detailKey)).toEqual(organizationOpportunity)
    expect(client.getQueryData(favoritesKey)).toEqual(organizationFundingResponse())
    expect(client.getQueryData(otherKey)).toBe(organizationOpportunity)
    await waitFor(() => expect(screen.getByRole('button', { name: 'Save to favorites' })).toBeEnabled())
    await act(() => setInterfaceLanguage('es'))
    expect(screen.getByRole('alert')).toHaveTextContent('No pudimos actualizar el favorito.')
    expect(organizationFundingApi.addFavorite).toHaveBeenCalledOnce()
  })

  it('returns to page one after removing the last favorite on page two, preserving other URL parameters', async () => {
    let removed = false
    const pending = deferred<void>()
    vi.mocked(organizationFundingApi.removeFavorite).mockImplementation(() => pending.promise)
    vi.mocked(organizationFundingApi.favorites).mockImplementation(async (_id, page) => ({
      ...organizationFundingResponse(true, page, removed ? 12 : 13),
      items: removed && page === 2 ? [] : [{ ...organizationOpportunity, isFavorite: true }],
    }))
    const { router } = mount('/favorites?page=2&context=original')
    await userEvent.click(await screen.findByRole('button', { name: 'Quitar de favoritos' }))
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByText('Page 2 of 2')).toBeVisible()
    removed = true
    await act(async () => { pending.resolve(); await pending.promise })
    await waitFor(() => expect(router.state.location.search).toBe('?context=original'))
    expect(organizationFundingApi.removeFavorite).toHaveBeenCalledExactlyOnceWith(fundingOrganizationId, organizationOpportunity.publicId)
    expect(organizationFundingApi.favorites).toHaveBeenLastCalledWith(fundingOrganizationId, 1, 12, expect.any(AbortSignal))
    expect(await screen.findByText(/saved favorites/)).toHaveTextContent('12 saved favorites')
    expect(screen.queryByText('You have not saved any opportunities yet')).not.toBeInTheDocument()
  })

  it.each(['/opportunities', '/favorites'])('translates loading, errors and empty results in %s without automatic refetch', async path => {
    const pending = deferred<ReturnType<typeof organizationFundingResponse>>()
    const load = path === '/favorites' ? organizationFundingApi.favorites : organizationFundingApi.search
    vi.mocked(load).mockImplementationOnce(() => pending.promise)
    mount(path)
    await screen.findByText(path === '/favorites' ? 'Cargando favoritos…' : 'Buscando oportunidades…')
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByText(path === '/favorites' ? 'Loading favorites…' : 'Searching opportunities…')).toBeVisible()
    await act(async () => {
      pending.reject(new ApiError({ title: 'Internal diagnostics', status: 503 }, new Response(null, { status: 503 })))
      await pending.promise.catch(() => undefined)
    })
    expect(await screen.findByRole('alert')).toHaveTextContent('The service is unavailable right now. Try again later.')
    expect(screen.queryByText('Internal diagnostics')).not.toBeInTheDocument()
    await act(() => setInterfaceLanguage('es'))
    expect(screen.getByRole('alert')).toHaveTextContent('El servicio no está disponible en este momento.')
    expect(load).toHaveBeenCalledOnce()
    vi.mocked(load).mockResolvedValue({ ...organizationFundingResponse(), items: [], totalCount: 0 })
    await userEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    await screen.findByText(path === '/favorites' ? 'Todavía no guardas concursos' : 'No encontramos concursos con esos criterios')
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('heading', { name: path === '/favorites' ? 'You have not saved any opportunities yet' : 'No opportunities match these criteria' })).toBeVisible()
    expect(load).toHaveBeenCalledTimes(2)
    expect(organizationFundingApi.addFavorite).not.toHaveBeenCalled()
    expect(organizationFundingApi.removeFavorite).not.toHaveBeenCalled()
  })

  it('translates the missing-organization CTA without loading organization funding', async () => {
    vi.mocked(organizationApi.list).mockResolvedValue([])
    mount()
    await screen.findByRole('heading', { name: 'Primero crea tu organización' })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('link', { name: 'Create organization' })).toHaveAttribute('href', '/onboarding')
    expect(organizationFundingApi.search).not.toHaveBeenCalled()
  })
})
