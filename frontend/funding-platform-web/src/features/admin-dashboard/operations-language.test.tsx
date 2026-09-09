import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { language } from '@/test/tracking-test-harness'
import { operationsJson, renderOperations } from '@/test/operations-test-harness'
import { operationsIds, operationsOrganization, operationsUser } from '@/test/fixtures/operations-workspace'

describe('I18N05D operational read views', () => {
  afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals() })

  it.each([
    ['/admin/users?q=consulta&status=1&role=Admin&page=2', 'Buscar usuarios', 'Search users', 'Usuarios', 'Users', 'Pending verification'],
    ['/admin/organizations?q=consulta&profileStatus=1&isActive=true&page=2', 'Buscar organizaciones', 'Search organizations', 'Organizaciones', 'Organizations', 'In progress'],
    ['/admin/errors?q=consulta&category=extraction&retryable=false&page=2', 'Buscar errores', 'Search errors', 'Errores operacionales', 'Operational errors', 'Permanent failure'],
  ])('retains URL, unsent search, codes and cache on %s', async (path, esSearch, enSearch, esTitle, enTitle, status) => {
    const user = userEvent.setup()
    const view = renderOperations(path)
    await screen.findByRole('heading', { name: esTitle, level: 1 })
    await waitFor(() => expect(view.client.isFetching()).toBe(0))
    await user.clear(screen.getByRole('textbox', { name: esSearch }))
    await user.type(screen.getByRole('textbox', { name: esSearch }), 'Borrador Ñandú')
    const before = view.requests.length
    const initialUrl = view.router.state.location.pathname + view.router.state.location.search
    const filters = screen.getAllByRole('combobox').map(node => (node as HTMLSelectElement).value)
    await language('en')
    expect(screen.getByRole('heading', { name: enTitle, level: 1 })).toBeInTheDocument()
    expect(screen.getByRole('textbox', { name: enSearch })).toHaveValue('Borrador Ñandú')
    expect(screen.getAllByText(status).length).toBeGreaterThan(0)
    expect(view.router.state.location.pathname + view.router.state.location.search).toBe(initialUrl)
    expect(screen.getAllByRole('combobox').slice(2).map(node => (node as HTMLSelectElement).value)).toEqual(filters.slice(2))
    expect(screen.getByRole('main')).not.toHaveAttribute('lang', 'es')
    expect(view.requests).toHaveLength(before)
    expect(view.requests.every(request => request.method === 'GET')).toBe(true)
    await language('es')
    expect(screen.getByRole('textbox', { name: esSearch })).toHaveValue('Borrador Ñandú')
    expect(view.unexpected).toEqual([])
  })

  it('keeps account locale, roles and original profile text separate from interface language', async () => {
    const view = renderOperations('/admin/users')
    await screen.findByText(operationsUser.displayName)
    await language('en')
    expect(screen.getByText('Locale pt-BR')).toBeInTheDocument()
    expect(screen.getByText('MFA enabled')).toBeInTheDocument()
    expect(screen.getByText('Last sign-in: Never')).toBeInTheDocument()
    expect(screen.getAllByText('Admin').length).toBeGreaterThan(0)
    expect(view.requests.every(request => request.method === 'GET')).toBe(true)
    expect(view.unexpected).toEqual([])
  })

  it('translates organization detail without inventing taxonomy codes or editing profile', async () => {
    const view = renderOperations('/admin/organizations/' + operationsIds.organization)
    await screen.findByRole('heading', { name: operationsOrganization.name })
    const before = view.requests.length
    await language('en')
    expect(screen.getByText('Institutional profile')).toBeInTheDocument()
    expect(screen.getByText('Active organization')).toBeInTheDocument()
    expect(screen.getByText(operationsOrganization.legalEntityTypeName)).toBeInTheDocument()
    expect(screen.getByText(operationsOrganization.description)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Open website' })).toHaveAttribute('href', operationsOrganization.websiteUrl)
    expect(view.requests).toHaveLength(before)
    expect(view.unexpected).toEqual([])
  })

  it('keeps dashboard totals and source readiness during partial failures', async () => {
    const view = renderOperations('/admin', {}, ({ url }) => url.pathname.endsWith('/admin/users')
      ? operationsJson({ title: 'PRIVATE-SQL-DETAIL' }, 500) : undefined)
    await screen.findByText('Un indicador no pudo actualizarse. Los demás datos siguen disponibles.')
    await waitFor(() => expect(view.client.isFetching()).toBe(0))
    const before = view.requests.length
    await language('en')
    expect(screen.getByText('One indicator could not be refreshed. Other information remains available.')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Sources needing attention/ })).toHaveTextContent('1')
    expect(screen.getByText(/3 retrieved/)).toBeInTheDocument()
    expect(screen.queryByText('PRIVATE-SQL-DETAIL')).not.toBeInTheDocument()
    expect(view.requests).toHaveLength(before)
    expect(view.unexpected).toEqual([])
  })

  it.each([
    ['/admin/users', '/admin/users', 'Users', 'No users match these filters', 'Search users'],
    ['/admin/organizations', '/admin/organizations', 'Organizations', 'No organizations match these filters', 'Search organizations'],
    ['/admin/errors', '/admin/operational-errors', 'Operational errors', 'No incidents match these filters', 'Search errors'],
  ])('translates empty state and clears filters explicitly on %s', async (path, api, title, empty, search) => {
    const user = userEvent.setup()
    const view = renderOperations(path + '?q=sin-resultados', { [api]: { items: [], page: 1, pageSize: 25, totalCount: 0 } })
    await waitFor(() => expect(view.client.isFetching()).toBe(0))
    await language('en')
    expect(screen.getByRole('heading', { name: title, level: 1 })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: empty })).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Clear filters' }))
    expect(screen.getByRole('textbox', { name: search })).toHaveValue('')
    expect(view.router.state.location.search).toBe('')
    expect(view.unexpected).toEqual([])
  })

  it.each([
    ['/admin/users', 'admin/users'], ['/admin/organizations', 'admin/organizations'],
    ['/admin/errors', 'admin/operational-errors'],
  ])('translates API errors without leaking details or auto-retrying %s', async (path, api) => {
    const view = renderOperations(path, {}, ({ url }) => url.pathname.endsWith(api)
      ? operationsJson({ detail: 'PRIVATE-DIAGNOSTIC token=private', title: 'PRIVATE-DIAGNOSTIC' }, 403) : undefined)
    await screen.findByRole('alert')
    const before = view.requests.length
    await language('en')
    expect(screen.getByRole('button', { name: 'Retry' })).toBeInTheDocument()
    expect(screen.getByRole('alert')).not.toHaveTextContent('PRIVATE-DIAGNOSTIC')
    expect(screen.getByRole('alert')).not.toHaveTextContent('No pudimos')
    expect(view.requests).toHaveLength(before)
    expect(view.unexpected).toEqual([])
  })

  it('keeps billing read-only with translated statuses and unsent search', async () => {
    const user = userEvent.setup()
    const view = renderOperations('/admin/subscriptions')
    await screen.findByText('Hay eventos que requieren reconciliación o soporte.')
    await user.type(screen.getByRole('textbox', { name: 'Buscar organización' }), 'Organización Ñandú')
    const before = view.requests.length
    await language('en')
    expect(screen.getByRole('textbox', { name: 'Search organization' })).toHaveValue('Organización Ñandú')
    expect(within(screen.getByRole('main')).getByText(/Plan original · Past due/)).toBeInTheDocument()
    expect(screen.queryByText('PRIVATE-PROVIDER-REFERENCE')).not.toBeInTheDocument()
    expect(view.requests).toHaveLength(before)
    expect(view.requests.every(request => request.method === 'GET')).toBe(true)
    expect(view.unexpected).toEqual([])
  })

  it('shows independent retryable billing reads', async () => {
    const view = renderOperations('/admin/subscriptions', {}, ({ url }) =>
      /\/admin\/(dashboard|subscriptions)$/.test(url.pathname) ? operationsJson({ title: 'PRIVATE-PAYMENT' }, 500) : undefined)
    await waitFor(() => expect(screen.getAllByRole('alert')).toHaveLength(2))
    await language('en')
    expect(screen.getByText('Subscription indicators could not be loaded.')).toBeInTheDocument()
    expect(screen.getByText('Subscriptions could not be loaded.')).toBeInTheDocument()
    expect(screen.getAllByRole('button', { name: 'Retry' })).toHaveLength(2)
    expect(screen.queryByText('PRIVATE-PAYMENT')).not.toBeInTheDocument()
    expect(view.unexpected).toEqual([])
  })
})
