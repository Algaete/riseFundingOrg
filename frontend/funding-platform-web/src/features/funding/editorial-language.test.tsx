import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter } from 'react-router-dom'
import { vi } from 'vitest'
import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { appRoutes } from '@/router'
import { setAuthenticatedSession } from '@/features/auth/auth-session'
import { editorialCatalogs, editorialFunder, editorialOpportunity, editorialProject, editorialProjectQueueItem } from '@/test/fixtures/editorial-workspace'
import { deferred, language } from '@/test/tracking-test-harness'

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: { 'Content-Type': 'application/json' } })
}

type Handler = (url: URL, init?: RequestInit) => Response | Promise<Response> | undefined
let unexpected: string[] = []
function mount(path: string, custom: Handler = () => undefined) {
  setAuthenticatedSession({
    status: 'authenticated', accessToken: 'synthetic-ui-only', accessTokenExpiresAtUtc: '2099-01-01T00:00:00Z',
    user: { publicId: '33333333-3333-3333-3333-333333333333', email: 'synthetic@example.invalid', displayName: 'Admin Ñandú', roles: ['Admin'], mfaEnabled: false, preferredLocale: 'es-CL' },
  })
  const calls: { path: string; method: string; body: unknown; headers: Headers }[] = []
  vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(String(input), 'http://localhost')
    const method = init?.method ?? 'GET'
    calls.push({ path: url.pathname + url.search, method, body: init?.body ? JSON.parse(String(init.body)) : undefined, headers: new Headers(init?.headers) })
    const response = custom(url, init)
    if (response) return response
    if (method === 'GET') {
      if (url.pathname.endsWith('/catalogs')) return json(editorialCatalogs)
      if (url.pathname.endsWith('/admin/funding-sources')) return json([{ id: 7, name: 'Manual editorial', providerType: 0, isEnabled: true, baseUrl: null }])
      if (url.pathname.endsWith('/admin/funders/' + editorialFunder().funderId)) return json(editorialFunder())
      if (url.pathname.endsWith('/admin/funders')) return json({ items: [editorialFunder()], totalCount: 1, page: 1, pageSize: 20 })
      if (url.pathname.endsWith('/admin/funding-opportunities/' + editorialOpportunity().opportunityId)) return json(editorialOpportunity({ publicationStatus: 0 }))
      if (url.pathname.endsWith('/admin/funding-opportunities')) return json({ items: [editorialOpportunity()], totalCount: 41, page: Number(url.searchParams.get('page')), pageSize: 20 })
      if (url.pathname.endsWith('/admin/projects/' + editorialProject.projectId)) return json(editorialProject)
      if (url.pathname.endsWith('/admin/projects/review-queue')) return json({ items: [editorialProjectQueueItem], totalCount: 41, page: Number(url.searchParams.get('page')), pageSize: 20 })
    }
    unexpected.push(method + ' ' + url.pathname)
    throw new Error('Unexpected synthetic API request')
  }))
  const client = createAppQueryClient()
  client.setDefaultOptions({ queries: { retry: false, staleTime: Infinity }, mutations: { retry: false } })
  const router = createMemoryRouter(appRoutes, { initialEntries: [path] })
  return { ...render(<App router={router} queryClient={client} />), calls, client, router }
}

beforeEach(() => { unexpected = [] })
afterEach(() => { expect(unexpected).toEqual([]); vi.unstubAllGlobals() })

describe('editorial administration ES/EN', () => {
  it('keeps a new funder draft and already-visible validation when changing language', async () => {
    const user = userEvent.setup()
    const { calls } = mount('/admin/funders/new')
    await screen.findByRole('textbox', { name: 'Nombre' })
    await user.click(screen.getByRole('button', { name: 'Crear financiador' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('El nombre debe tener al menos 2 caracteres.')
    await user.type(screen.getByRole('textbox', { name: 'Alias conocidos' }), 'Alias original Ñandú')
    const before = calls.length
    await language('en')
    expect(screen.getByRole('alert')).toHaveTextContent('The name must contain at least 2 characters.')
    expect(screen.getByRole('textbox', { name: 'Known aliases' })).toHaveValue('Alias original Ñandú')
    expect(screen.getByRole('main')).not.toHaveAttribute('lang', 'es')
    expect(calls).toHaveLength(before)
    expect(calls.every(call => call.method === 'GET')).toBe(true)
  })

  it('localizes optional URL/max-length validation without requiring optional fields', async () => {
    const user = userEvent.setup()
    let written: unknown
    const { calls } = mount('/admin/funders/new', (url, init) => {
      if (init?.method === 'POST' && url.pathname.endsWith('/admin/funders')) {
        written = JSON.parse(String(init.body))
        return json({ entityId: editorialFunder().funderId, eTag: '"v1"', publicationStatus: 0, contentVersion: 1, wasReplay: false })
      }
    })
    await screen.findByRole('textbox', { name: 'Nombre' })
    fireEvent.change(screen.getByRole('textbox', { name: 'Nombre' }), { target: { value: 'N'.repeat(251) } })
    fireEvent.change(screen.getByRole('textbox', { name: 'Sitio web oficial' }), { target: { value: 'invalid' } })
    await user.click(screen.getByRole('button', { name: 'Crear financiador' }))
    await screen.findByText('Usa como máximo 250 caracteres.')
    await language('en')
    expect(screen.getByText('Use at most 250 characters.')).toBeInTheDocument()
    expect(screen.getByText('Enter a complete URL starting with http:// or https://.')).toBeInTheDocument()
    fireEvent.change(screen.getByRole('textbox', { name: /^Name/ }), { target: { value: 'Financiador Ñandú' } })
    fireEvent.change(screen.getByRole('textbox', { name: /^Official website/ }), { target: { value: '' } })
    await user.click(screen.getByRole('button', { name: 'Create funder' }))
    await waitFor(() => expect(written).toEqual({ name: 'Financiador Ñandú', aliases: [], description: null, countryId: null, websiteUrl: null }))
    const writes = calls.filter(call => call.method === 'POST')
    expect(writes).toHaveLength(1)
    expect(writes[0].headers.get('Idempotency-Key')).toMatch(/^[0-9a-f-]{36}$/i)
  })

  it('preserves funding form IDs, precision, draft and validation; language never clears conditional fields', async () => {
    const user = userEvent.setup()
    const { calls } = mount('/admin/funding/' + editorialOpportunity().opportunityId)
    await screen.findByRole('textbox', { name: 'Título' })
    fireEvent.change(screen.getByRole('textbox', { name: 'Título' }), { target: { value: 'Edición Ñandú' } })
    fireEvent.change(screen.getByRole('spinbutton', { name: 'Monto máximo' }), { target: { value: '10' } })
    await user.click(screen.getByRole('button', { name: 'Guardar cambios' }))
    await screen.findByText('El monto mínimo no puede superar al máximo.')
    const before = calls.length
    await language('en')
    expect(screen.getByRole('textbox', { name: 'Title' })).toHaveValue('Edición Ñandú')
    expect(screen.getByText('The minimum amount cannot exceed the maximum.')).toBeInTheDocument()
    expect(screen.getByRole('combobox', { name: 'Currency' })).toHaveValue('USD')
    expect(screen.getByRole('combobox', { name: 'Geographic scope' })).toHaveValue('1')
    expect(screen.getByRole('checkbox', { name: 'Chile' })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: 'Health' })).toBeChecked()
    expect(screen.getByRole('combobox', { name: 'Role' })).toHaveValue('1')
    expect(screen.getByLabelText(/Exact closing time/)).toHaveValue('2027-02-01T02:59:59.123')
    expect(screen.getByRole('button', { name: 'Submit for review' })).toBeDisabled()
    expect(calls).toHaveLength(before)
    expect(calls.every(call => call.method === 'GET')).toBe(true)
  })

  it('submits unchanged protocol fields from an English form and translates a visible save notice', async () => {
    const user = userEvent.setup()
    let current = editorialOpportunity({ publicationStatus: 0 })
    const { calls } = mount('/admin/funding/' + current.opportunityId, (url, init) => {
      if (url.pathname.endsWith('/admin/funding-opportunities/' + current.opportunityId)) {
        if (init?.method === 'PUT') {
          current = { ...current, ...JSON.parse(String(init.body)), contentVersion: 4, eTag: '"v4"' }
          return json({ entityId: current.opportunityId, publicationStatus: 0, contentVersion: 4, eTag: '"v4"', wasReplay: false })
        }
        return json(current)
      }
    })
    await screen.findByRole('textbox', { name: 'Título' })
    await language('en')
    fireEvent.change(screen.getByRole('textbox', { name: 'Title' }), { target: { value: 'Texto sin traducir Ñandú' } })
    await user.click(screen.getByRole('button', { name: 'Save changes' }))
    await screen.findByText('Changes saved successfully.')
    const writes = calls.filter(call => call.method === 'PUT')
    expect(writes).toHaveLength(1)
    const original = editorialOpportunity()
    expect(writes[0].body).toMatchObject({
      title: 'Texto sin traducir Ñandú', currency: 'USD', minimumAmount: 1000, maximumAmount: 5000,
      closeDate: original.closeDate, closeAtUtc: original.closeAtUtc, deadlineTimeZoneId: 'America/Santiago',
      lastVerifiedAtUtc: original.lastVerifiedAtUtc, countryIds: [152], regionIds: [13101], categoryIds: [1],
      funders: [{ funderId: editorialFunder().funderId, role: 1 }], fundingSourceId: 7, externalId: 'FS-2026',
    })
    expect(writes[0].headers.get('If-Match')).toBe(original.eTag)
    expect(writes[0].headers.get('Idempotency-Key')).toMatch(/^[0-9a-f-]{36}$/i)
    const before = calls.length
    await language('es')
    expect(screen.getByText('Cambios guardados correctamente.')).toBeInTheDocument()
    expect(calls).toHaveLength(before)
  })

  it('retains admin filters, search and pagination on language change', async () => {
    const user = userEvent.setup()
    const { calls } = mount('/admin/funding')
    await screen.findByRole('heading', { name: 'Fondo de salud comunitaria' })
    await user.type(screen.getByRole('textbox', { name: 'Buscar oportunidades' }), 'salud Ñandú')
    await user.selectOptions(screen.getByRole('combobox', { name: 'Filtrar por estado' }), '1')
    await user.click(screen.getByRole('button', { name: 'Buscar' }))
    await user.click(screen.getByRole('button', { name: 'Siguiente' }))
    await screen.findByText('Página 2 de 3')
    const before = calls.length
    await language('en')
    expect(screen.getByText('Page 2 of 3')).toBeInTheDocument()
    expect(screen.getByRole('textbox', { name: 'Search opportunities' })).toHaveValue('salud Ñandú')
    expect(screen.getByRole('combobox', { name: 'Filter by status' })).toHaveValue('1')
    expect(screen.getByRole('option', { name: 'Pending review' })).toHaveValue('1')
    expect(screen.getByText('Closing Jan 31, 2027')).toBeInTheDocument()
    expect(calls).toHaveLength(before)
  })

  it('renders project review taxonomy and financial amounts without translating author content', async () => {
    const { calls } = mount('/admin/projects/' + editorialProject.projectId)
    await screen.findByRole('heading', { name: editorialProject.title })
    await language('en')
    expect(screen.getByText('Seeking funding', { exact: true })).toBeInTheDocument()
    expect(screen.getByText('Implementation', { exact: true })).toBeInTheDocument()
    expect(screen.getByText(editorialProject.description!)).toBeInTheDocument()
    expect(screen.getByText('Environment', { exact: true })).toHaveAttribute('lang', 'en')
    expect(screen.getByText('Clean Water and Sanitation', { exact: true })).toBeInTheDocument()
    expect(screen.getByText('87% complete')).toBeInTheDocument()
    expect(calls).toHaveLength(1)
  })

  it('captures the project rejection body and ETag before retry even if the reason and language change', async () => {
    const user = userEvent.setup()
    const pending = deferred<Response>()
    let attempt = 0
    const { calls } = mount('/admin/projects/' + editorialProject.projectId, (url, init) => {
      if (init?.method === 'POST' && url.pathname.endsWith('/reviews')) {
        attempt++
        return attempt === 1 ? pending.promise : json({ title: 'PRIVATE', status: 503 }, 503)
      }
    })
    await screen.findByRole('textbox', { name: 'Motivo si solicitas correcciones' })
    await user.type(screen.getByRole('textbox'), 'Motivo aprobado Ñandú')
    await user.click(screen.getByRole('button', { name: 'Solicitar correcciones' }))
    await waitFor(() => expect(attempt).toBe(1))
    await language('en')
    fireEvent.change(screen.getByRole('textbox', { name: 'Reason for requesting corrections' }), { target: { value: 'Otro borrador no enviado' } })
    expect(screen.getByRole('button', { name: 'Request corrections' })).toBeDisabled()
    await act(async () => pending.resolve(json({ title: 'PRIVATE', status: 503 }, 503)))
    await waitFor(() => expect(attempt).toBe(2), { timeout: 3000 })
    const writes = calls.filter(call => call.method === 'POST')
    expect(writes[0].body).toEqual({ decision: 'reject', reason: 'Motivo aprobado Ñandú' })
    expect(writes[1].body).toEqual(writes[0].body)
    expect(writes[1].headers.get('If-Match')).toBe(editorialProject.eTag)
    expect(writes[1].headers.get('Idempotency-Key')).toBe(writes[0].headers.get('Idempotency-Key'))
    expect(await screen.findByRole('alert')).not.toHaveTextContent('PRIVATE')
    expect(screen.getByRole('textbox')).toHaveValue('Otro borrador no enviado')
  })

  it('publishes a project only on click, with a null rejection reason and captured version', async () => {
    const user = userEvent.setup()
    const { calls, router } = mount('/admin/projects/' + editorialProject.projectId, (url, init) => {
      if (init?.method === 'POST' && url.pathname.endsWith('/reviews')) {
        return json({ projectId: editorialProject.projectId, publicationStatus: 2, projectVersion: 4, eTag: '"v4"', wasReplay: false })
      }
    })
    await screen.findByRole('textbox', { name: 'Motivo si solicitas correcciones' })
    await user.type(screen.getByRole('textbox'), 'Borrador que no debe publicarse')
    await language('en')
    expect(calls.filter(call => call.method === 'POST')).toHaveLength(0)
    await user.click(screen.getByRole('button', { name: 'Approve and publish' }))
    await screen.findByRole('heading', { name: 'Pending projects' })
    const writes = calls.filter(call => call.method === 'POST')
    expect(writes).toHaveLength(1)
    expect(writes[0].body).toEqual({ decision: 'approve', reason: null })
    expect(writes[0].headers.get('If-Match')).toBe(editorialProject.eTag)
    expect(writes[0].headers.get('Idempotency-Key')).toMatch(/^[0-9a-f-]{36}$/i)
    expect(router.state.location.pathname).toBe('/admin/projects')
  })

  it('keeps a non-pending project read-only in English', async () => {
    const { calls } = mount('/admin/projects/' + editorialProject.projectId, url =>
      url.pathname.endsWith('/admin/projects/' + editorialProject.projectId) ? json({ ...editorialProject, publicationStatus: 2 }) : undefined)
    await screen.findByRole('heading', { name: editorialProject.title })
    await language('en')
    expect(screen.getByText(/This project is no longer pending/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Approve and publish' })).not.toBeInTheDocument()
    expect(calls).toHaveLength(1)
  })
})
