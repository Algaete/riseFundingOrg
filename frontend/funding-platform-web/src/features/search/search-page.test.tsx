import { act, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider, focusManager, onlineManager } from '@tanstack/react-query'
import { createMemoryRouter, RouterProvider } from 'react-router-dom'
import { clearAuthSession, setAuthenticatedSession } from '@/features/auth/auth-session'
import { marketplaceApi } from '@/features/marketplace/marketplace-api'
import { organizationApi, type OrganizationSummary } from '@/features/organizations/organization-api'
import { setInterfaceLanguage } from '@/i18n'
import * as api from './search-api'
import { UnifiedSearchPage } from './search-page'

const catalogs = { countries: [{ id: 152, code: 'CL', name: 'Chile' }], fundingCategories: [{ id: 4, code: 'water', name: 'Agua y saneamiento' }], projectTypes: [], sustainableDevelopmentGoals: [], currencies: [] }
const page: api.SearchPage = { items: [{ id: 'public', title: 'Proyecto público', summary: 'Resumen', href: '/marketplace/projects/agua' }], totalCount: 21, page: 1, pageSize: 20 }
const membership = (publicId: string): OrganizationSummary => ({ publicId, name: publicId, membershipRole: 'member', profileStatus: 1, profileCompleteness: 100, profileVersion: 1, updatedAtUtc: '2026-09-01T00:00:00Z' })
function signIn(id = 'actor-A') {
  setAuthenticatedSession({ status: 'authenticated', accessToken: 'synthetic-token', accessTokenExpiresAtUtc: new Date(Date.now() + 600000).toISOString(),
    user: { publicId: id, email: 'synthetic@example.invalid', displayName: id, preferredLocale: 'es', roles: ['User'], mfaEnabled: false } })
}
function setup(url = '/search?scope=all&q=agua&countryId=152&categoryId=4') {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  const router = createMemoryRouter([{ path: '/search', element: <UnifiedSearchPage /> }, { path: '/login', element: <p>Login</p> }], { initialEntries: [url] })
  render(<QueryClientProvider client={client}><RouterProvider router={router} /></QueryClientProvider>)
  return { router, client }
}

describe('unified search visibility and interaction', () => {
  beforeEach(() => {
    clearAuthSession()
    vi.spyOn(marketplaceApi, 'catalogs').mockResolvedValue(catalogs)
    vi.spyOn(organizationApi, 'list').mockResolvedValue([membership('org-A')])
    vi.spyOn(api, 'searchSource').mockImplementation(async source => source === 'projects' ? page : { items: [], totalCount: 0, page: 1, pageSize: 6 })
  })
  afterEach(() => { vi.restoreAllMocks(); focusManager.setFocused(undefined); onlineManager.setOnline(true) })

  it('only queries public sections as guest and preserves the login return path', async () => {
    const { router } = setup()
    expect(await screen.findByRole('link', { name: 'Proyecto público' })).toBeInTheDocument()
    expect(api.searchSource).toHaveBeenCalledTimes(2)
    expect(vi.mocked(api.searchSource).mock.calls.map(args => args[0])).toEqual(['projects', 'funding'])
    expect(organizationApi.list).not.toHaveBeenCalled()
    expect(screen.getAllByRole('link', { name: 'Ingresar' })).toHaveLength(2)
    await userEvent.click(screen.getAllByRole('link', { name: 'Ingresar' })[0])
    expect(router.state.location.state).toEqual({ from: '/search?scope=all&q=agua&countryId=152&categoryId=4' })
  })

  it('bare search waits for submission and typing does not send queries', async () => {
    setup('/search')
    const user = userEvent.setup()
    await user.type(screen.getByRole('searchbox'), 'agua')
    expect(api.searchSource).not.toHaveBeenCalled()
    await user.click(screen.getByRole('button', { name: 'Buscar' }))
    await screen.findByRole('link', { name: 'Proyecto público' })
    expect(api.searchSource).toHaveBeenCalledTimes(2)
  })

  it.each(['scope=all&page=2', 'q=%00', 'countryId=-1', 'scope=admin', 'q=a&q=b'])('rejects invalid URL without querying results: %s', async query => {
    signIn()
    setup(`/search?${query}`)
    expect(await screen.findByRole('alert')).toHaveTextContent('Revisa los filtros')
    expect(api.searchSource).not.toHaveBeenCalled()
    expect(organizationApi.list).not.toHaveBeenCalled()
  })

  it('isolates errors, does not show diagnostics and retries only the failed section', async () => {
    vi.mocked(api.searchSource).mockImplementation(async source => {
      if (source === 'funding') throw new Error('secret diagnostics')
      return page
    })
    setup()
    expect(await screen.findByRole('alert')).toHaveTextContent('No pudimos consultar esta sección')
    expect(screen.getByRole('link', { name: 'Proyecto público' })).toBeInTheDocument()
    expect(screen.queryByText('secret diagnostics')).not.toBeInTheDocument()
    vi.mocked(api.searchSource).mockResolvedValue({ ...page, items: [] })
    await userEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    await waitFor(() => expect(screen.queryByRole('alert')).not.toBeInTheDocument())
    expect(vi.mocked(api.searchSource).mock.calls.map(args => args[0])).toEqual(['projects', 'funding', 'funding'])
  })

  it('preserves selected IDs if catalogs fail and still permits a text-only search', async () => {
    vi.mocked(marketplaceApi.catalogs).mockRejectedValue(new Error('private catalog diagnostic'))
    const { router } = setup('/search?scope=projects&countryId=152&categoryId=4')
    await screen.findByRole('link', { name: 'Proyecto público' })
    expect(screen.getByRole('combobox', { name: 'País' })).toHaveValue('152')
    expect(screen.getByRole('combobox', { name: 'Área de impacto' })).toHaveValue('4')
    expect(screen.queryByText('private catalog diagnostic')).not.toBeInTheDocument()
    const user = userEvent.setup()
    await user.selectOptions(screen.getByRole('combobox', { name: 'País' }), '')
    await user.selectOptions(screen.getByRole('combobox', { name: 'Área de impacto' }), '')
    await user.type(screen.getByRole('searchbox'), 'agua')
    await user.click(screen.getByRole('button', { name: 'Buscar' }))
    expect(router.state.location.search).toBe('?scope=projects&q=agua')
  })

  it('never shows a late result for the previous submitted search', async () => {
    let finishFirst!: (result: api.SearchPage) => void
    vi.mocked(api.searchSource).mockImplementationOnce(() => new Promise(resolve => { finishFirst = resolve }))
      .mockResolvedValueOnce({ ...page, items: [{ id: 'new', title: 'Resultado actual', summary: null }] })
    const { router } = setup('/search?scope=projects&q=primero')
    await waitFor(() => expect(api.searchSource).toHaveBeenCalledTimes(1))
    const signal = vi.mocked(api.searchSource).mock.calls[0][2]
    await act(async () => { await router.navigate('/search?scope=projects&q=segundo') })
    await screen.findByText('Resultado actual')
    expect(signal.aborted).toBe(true)
    await act(async () => finishFirst(page))
    expect(screen.queryByText('Proyecto público')).not.toBeInTheDocument()
    expect(screen.getByText('Resultado actual')).toBeInTheDocument()
  })

  it('preserves filters across view-all, paging, history and language, resetting page on submit', async () => {
    const { router } = setup()
    const user = userEvent.setup()
    const projectSection = await screen.findByRole('region', { name: 'Proyectos' })
    await user.click(within(projectSection).getByRole('link', { name: 'Ver todos' }))
    expect(router.state.location.search).toBe('?scope=projects&q=agua&countryId=152&categoryId=4')
    await user.click(await screen.findByRole('link', { name: 'Siguiente' }))
    expect(router.state.location.search).toContain('&page=2')
    await screen.findByText('Página 2')
    const calls = vi.mocked(api.searchSource).mock.calls.length
    await user.type(screen.getByRole('searchbox'), ' pendiente')
    await act(async () => { await setInterfaceLanguage('en') })
    expect(screen.getByRole('searchbox')).toHaveValue('agua pendiente')
    expect(screen.getByRole('combobox', { name: 'Country' })).toHaveValue('152')
    expect(api.searchSource).toHaveBeenCalledTimes(calls)
    await user.click(screen.getByRole('button', { name: 'Search' }))
    expect(router.state.location.search).not.toContain('page=')
    expect(router.state.location.search).toContain('q=agua+pendiente')
    await act(async () => { await router.navigate(-1) })
    expect(screen.getByRole('searchbox')).toHaveValue('agua')
    expect(router.state.location.search).toContain('page=2')
  })

  it('never auto-selects among multiple memberships or trusts an organization ID in the URL', async () => {
    signIn()
    vi.mocked(organizationApi.list).mockResolvedValue([membership('org-A'), membership('org-B')])
    setup('/search?scope=organizations&organizationId=foreign')
    const picker = await screen.findByRole('combobox', { name: 'Buscar aliados desde mi organización' })
    expect(api.searchSource).not.toHaveBeenCalled()
    await userEvent.selectOptions(picker, 'org-B')
    await waitFor(() => expect(api.searchSource).toHaveBeenCalledExactlyOnceWith('organizations', expect.objectContaining({ scope: 'organizations' }), expect.any(AbortSignal), 'org-B'))
  })

  it('discards resolved results when switching organization', async () => {
    signIn()
    vi.mocked(organizationApi.list).mockResolvedValue([membership('org-A'), membership('org-B')])
    vi.mocked(api.searchSource).mockImplementation(async (_source, _criteria, _signal, org) => ({ ...page, items: [{ id: org!, title: `Aliado de ${org}`, summary: null }] }))
    const { client } = setup('/search?scope=organizations')
    const picker = await screen.findByRole('combobox', { name: 'Buscar aliados desde mi organización' })
    await userEvent.selectOptions(picker, 'org-A')
    await screen.findByText('Aliado de org-A')
    await userEvent.selectOptions(picker, 'org-B')
    await screen.findByText('Aliado de org-B')
    expect(screen.queryByText('Aliado de org-A')).not.toBeInTheDocument()
    await waitFor(() => expect(client.getQueryCache().findAll({ queryKey: ['unified-search', 'organizations', 'actor-A', 'org-A'] })).toHaveLength(0))
  })

  it.each(['empty', 'error'] as const)('does not query the organization directory when membership verification is %s', async state => {
    signIn()
    if (state === 'error') vi.mocked(organizationApi.list).mockRejectedValue(new Error('private diagnostics'))
    else vi.mocked(organizationApi.list).mockResolvedValue([])
    setup('/search?scope=organizations')
    if (state === 'error') expect(await screen.findByRole('alert')).toHaveTextContent('No pudimos comprobar')
    else expect(await screen.findByRole('link', { name: 'Crear mi organización' })).toBeInTheDocument()
    expect(api.searchSource).not.toHaveBeenCalled()
  })

  it('auto-selects the sole membership but does not require one for professionals', async () => {
    signIn()
    setup()
    await waitFor(() => expect(api.searchSource).toHaveBeenCalledWith('organizations', expect.anything(), expect.any(AbortSignal), 'org-A'))
    expect(api.searchSource).toHaveBeenCalledWith('professionals', expect.anything(), expect.any(AbortSignal), undefined)
  })

  it('clears private data and aborts pending requests across account changes and logout', async () => {
    signIn()
    vi.mocked(api.searchSource).mockResolvedValueOnce({ ...page, items: [{ id: 'A', title: 'Perfil para A', summary: null }] })
      .mockImplementationOnce((_s, _c, signal) => new Promise((_resolve, reject) => signal.addEventListener('abort', () => reject(new Error('cancelled')))))
    const { client } = setup('/search?scope=professionals')
    await screen.findByText('Perfil para A')
    act(() => signIn('actor-B'))
    expect(screen.queryByText('Perfil para A')).not.toBeInTheDocument()
    await waitFor(() => expect(api.searchSource).toHaveBeenCalledTimes(2))
    const signal = vi.mocked(api.searchSource).mock.calls[1][2]
    act(() => clearAuthSession())
    expect(signal.aborted).toBe(true)
    expect(screen.getByRole('link', { name: 'Ingresar' })).toBeInTheDocument()
    await waitFor(() => expect(client.getQueryCache().findAll({ queryKey: ['unified-search', 'professionals'] })).toHaveLength(0))
  })

  it('does not refetch on focus or reconnect and shows no invented profile link', async () => {
    signIn()
    vi.mocked(api.searchSource).mockResolvedValue({ ...page, items: [{ id: 'prof', title: 'Profesional', summary: 'Ingeniería', biography: 'Experiencia compartida', skills: ['GIS'] }] })
    setup('/search?scope=professionals')
    await screen.findByText('Profesional')
    expect(screen.queryByRole('link', { name: 'Profesional' })).not.toBeInTheDocument()
    await userEvent.click(screen.getByText('Ver perfil profesional'))
    expect(screen.getByText('Experiencia compartida')).toBeVisible()
    act(() => { focusManager.setFocused(false); onlineManager.setOnline(false) })
    act(() => { focusManager.setFocused(true); onlineManager.setOnline(true) })
    expect(api.searchSource).toHaveBeenCalledTimes(1)
    expect(organizationApi.list).not.toHaveBeenCalled()
  })
})
