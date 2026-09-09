import { act, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { deferred, language } from '@/test/tracking-test-harness'
import { operationsJson, renderOperations } from '@/test/operations-test-harness'
import { operationsComparison, operationsETag, operationsIds, operationsRun, operationsRunDetail } from '@/test/fixtures/operations-workspace'

describe('I18N05D import operations', () => {
  afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); vi.useRealTimers() })

  it('keeps input, source IDs, filters and pagination while validation changes language', async () => {
    const user = userEvent.setup()
    const view = renderOperations('/admin/imports?sourceId=9&status=2&page=2')
    await screen.findByText('3 procesados')
    await user.clear(screen.getByRole('textbox', { name: 'Palabra clave' }))
    await user.type(screen.getByRole('textbox', { name: 'Palabra clave' }), 'a')
    await user.click(screen.getByRole('button', { name: 'Iniciar importación' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('La búsqueda debe tener entre 2 y 100 caracteres.')
    const before = view.requests.length
    await language('en')
    expect(screen.getByRole('textbox', { name: 'Keyword' })).toHaveValue('a')
    expect(screen.getByRole('spinbutton', { name: 'Maximum' })).toHaveValue(25)
    expect(screen.getByRole('alert')).toHaveTextContent('The search must contain between 2 and 100 characters.')
    expect(view.router.state.location.search).toBe('?sourceId=9&status=2&page=2')
    expect(view.requests).toHaveLength(before)
    expect(view.requests.every(request => request.method === 'GET')).toBe(true)
    expect(view.unexpected).toEqual([])
  })

  it('does not restart an accepted import when switching language while its request is pending', async () => {
    const user = userEvent.setup()
    const accepted = deferred<Response>()
    const view = renderOperations('/admin/imports', {}, request => request.method === 'POST' && request.url.pathname.endsWith('/funding-sources/9/import-runs') ? accepted.promise : undefined)
    await screen.findByText('3 procesados')
    await user.clear(screen.getByRole('textbox', { name: 'Palabra clave' }))
    await user.type(screen.getByRole('textbox', { name: 'Palabra clave' }), 'agua Ñandú')
    await user.click(screen.getByRole('button', { name: 'Iniciar importación' }))
    await language('en')
    expect(screen.getByRole('button', { name: 'Sending…' })).toBeDisabled()
    const writes = view.requests.filter(request => request.method === 'POST')
    expect(writes).toHaveLength(1)
    expect(JSON.parse(String(writes[0].init.body))).toEqual({ keyword: 'agua Ñandú', maximumResults: 25 })
    expect(new Headers(writes[0].init.headers).get('Idempotency-Key')).toMatch(/^[0-9a-f-]{36}$/i)
    await act(async () => accepted.resolve(operationsJson({ ...operationsRun, wasReplay: false })))
    await screen.findByRole('heading', { name: 'Import: agua Ñandú' })
    expect(view.requests.filter(request => request.method === 'POST')).toHaveLength(1)
    expect(view.unexpected).toEqual([])
  })

  it.each([
    ['Conservar como fondo separado', 'Keep separate', 'keep-separate'],
    ['Marcar como duplicado', 'Mark as duplicate', 'mark-duplicate'],
    ['Ignorar sugerencia', 'Ignore suggestion', 'ignored'],
  ])('keeps confirmation/reason and explicit decision code for %s', async (esAction, enAction, decision) => {
    const user = userEvent.setup()
    const saved = deferred<Response>()
    const view = renderOperations('/admin/imports/' + operationsIds.run, {}, request =>
      request.method === 'POST' && request.url.pathname.endsWith('/decisions') ? saved.promise : undefined)
    await user.click(await screen.findByRole('button', { name: 'Comparar duplicado' }))
    await user.click(await screen.findByRole('button', { name: esAction }))
    const reason = 'Revisar evidencia original Ñandú'
    await user.type(within(screen.getByRole('dialog')).getByRole('textbox'), reason)
    const before = view.requests.length
    await language('en')
    const dialog = screen.getByRole('dialog')
    expect(within(dialog).getByRole('textbox')).toHaveValue(reason)
    expect(dialog).toHaveTextContent(enAction)
    expect(dialog).toHaveTextContent('The candidate will remain unpublished.')
    expect(view.requests).toHaveLength(before)
    await user.click(within(dialog).getByRole('button', { name: 'Confirm decision' }))
    await language('es')
    expect(within(screen.getByRole('dialog')).getByRole('button', { name: 'Confirmar decisión' })).toBeDisabled()
    const writes = view.requests.filter(request => request.method === 'POST')
    expect(writes).toHaveLength(1)
    expect(JSON.parse(String(writes[0].init.body))).toEqual({
      decision, reason, ...(decision === 'mark-duplicate' ? { canonicalOpportunityId: operationsComparison.existing.opportunityId } : {}),
    })
    expect(new Headers(writes[0].init.headers).get('If-Match')).toBe(operationsETag)
    expect(new Headers(writes[0].init.headers).get('Idempotency-Key')).toMatch(/^[0-9a-f-]{36}$/i)
    await act(async () => saved.resolve(operationsJson({ candidateId: operationsIds.candidate, decisionCode: decision, isPublished: false, wasReplay: false, eTag: operationsETag })))
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    await language('en')
    expect(screen.getByRole('status', { name: '' })).toHaveTextContent('Decision saved successfully. No fund was published.')
    expect(view.requests.filter(request => request.method === 'POST')).toHaveLength(1)
    expect(view.unexpected).toEqual([])
  })

  it('translates unsafe publication warnings without approving or merging anything', async () => {
    const view = renderOperations('/admin/imports/' + operationsIds.run, {
      ['/admin/import-runs/' + operationsIds.run]: { ...operationsRunDetail, items: [{ ...operationsRunDetail.items[0], isAutoPublished: true }] },
    })
    await screen.findByRole('alert')
    await language('en')
    expect(screen.getByRole('alert')).toHaveTextContent('automatic publication')
    expect(view.requests.every(request => request.method === 'GET')).toBe(true)
    expect(view.unexpected).toEqual([])
  })

  it('keeps source governance blocked even when the interface and known policy labels change', async () => {
    const view = renderOperations('/admin/sources')
    await screen.findByText('Grants.gov Ñandú')
    const before = view.requests.length
    await language('en')
    expect(screen.getByText('Healthy')).toBeInTheDocument()
    expect(screen.getByText('Blocked by policy')).toBeInTheDocument()
    expect(screen.getByText('Licencia original')).toBeInTheDocument()
    expect(screen.getByText('10 requests/minute')).toBeInTheDocument()
    expect(view.requests).toHaveLength(before)
    expect(view.unexpected).toEqual([])
  })

  it('retains the active-run polling cadence across language changes', async () => {
    const view = renderOperations('/admin/imports/' + operationsIds.run, {
      ['/admin/import-runs/' + operationsIds.run]: { ...operationsRunDetail, status: 1 },
    })
    await screen.findByText('En ejecución')
    vi.useFakeTimers()
    // Re-arm an existing query under the fake clock, then change only language.
    await act(async () => { await view.client.refetchQueries({ queryKey: ['admin', 'import-run', operationsIds.run] }) })
    const before = view.requests.length
    await language('en')
    expect(screen.getByText('Running')).toBeInTheDocument()
    expect(view.requests).toHaveLength(before)
    await act(async () => { await vi.advanceTimersByTimeAsync(1999) })
    expect(view.requests).toHaveLength(before)
    await act(async () => { await vi.advanceTimersByTimeAsync(1) })
    expect(view.requests).toHaveLength(before + 1)
    expect(view.unexpected).toEqual([])
  })
})
