import { QueryClientProvider } from '@tanstack/react-query'
import { act, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter, RouterProvider } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { createAppQueryClient } from '@/api/query-client'
import { organizationApi } from '@/features/organizations/organization-api'
import { projectApi } from '@/features/projects/project-api'
import { setInterfaceLanguage } from '@/i18n'
import { collaborationOrganizations, matchingDetail, matchingHistory, matchingRunId, workspaceOrganizationId, workspaceProject, workspaceProjectId } from '@/test/fixtures/matching-network'
import { matchingApi, type MatchingRunCreated } from './matching-api'
import { MatchingWorkspacePage } from './matching-pages'

function mount(path = `/matching?projectId=${workspaceProjectId}&runId=${matchingRunId}&page=2&context=original`) {
  const client = createAppQueryClient()
  client.setDefaultOptions({ queries: { retry: false, staleTime: 30_000 } })
  const router = createMemoryRouter([{ path: '/matching', element: <MatchingWorkspacePage /> }], { initialEntries: [path] })
  render(<QueryClientProvider client={client}><RouterProvider router={router} /></QueryClientProvider>)
  return router
}

function deferred<T>() {
  let resolve!: (value: T) => void
  const promise = new Promise<T>(yes => { resolve = yes })
  return { promise, resolve }
}

describe('matching ES/EN', () => {
  beforeEach(() => {
    vi.spyOn(organizationApi, 'list').mockResolvedValue(collaborationOrganizations)
    vi.spyOn(projectApi, 'list').mockResolvedValue([workspaceProject])
    vi.spyOn(matchingApi, 'list').mockImplementation(async (_org, _project, page) => ({ ...matchingHistory, pageNumber: page ?? 1 }))
    vi.spyOn(matchingApi, 'get').mockResolvedValue(matchingDetail)
    vi.spyOn(matchingApi, 'calculate').mockResolvedValue({ run: matchingDetail, wasReplay: false })
  })
  afterEach(() => vi.restoreAllMocks())

  it('preserves project/run/page, expanded rules, scores and private-evidence safeguards without recalculating', async () => {
    const router = mount()
    await screen.findByRole('heading', { name: matchingDetail.items[0].fundingOpportunity.title })
    await userEvent.click(screen.getByText('Ver desglose de 2 reglas'))
    const details = screen.getByText('Ver desglose de 2 reglas').closest('details')!
    const location = router.state.location.search
    await act(() => setInterfaceLanguage('en'))
    expect(router.state.location.search).toBe(location)
    expect(details.open).toBe(true)
    expect(screen.getByRole('combobox', { name: /Project to compare/ })).toHaveValue(workspaceProjectId)
    expect(screen.getByText('Page 2 of 3')).toBeVisible()
    expect(screen.getByLabelText('Indicative score 42.5 out of 100')).toBeVisible()
    expect(screen.getByRole('progressbar', { name: 'Data coverage 62.5%' })).toHaveAttribute('value', '62.5')
    expect(screen.getByText('Unknown does not count as passed.')).toBeVisible()
    expect(screen.getByText('Contains earlier versions')).toBeVisible()
    expect(screen.getByText('Outdated result')).toBeVisible()
    expect(screen.getByRole('heading', { name: 'Geography' })).toBeVisible()
    expect(screen.getByText('The project lacks enough territorial information to assess this condition.')).toBeVisible()
    expect(screen.getByText('Score contribution: 5 out of 10 possible points')).toBeVisible()
    expect(screen.getByText('Compared currencies: project USD · opportunity USD')).toBeVisible()
    expect(screen.getByText('Recorded matches: 2')).toBeVisible()
    expect(screen.getByText('Minimum verifiable years: 7')).toBeVisible()
    expect(screen.getByText('Maximum possible years: 8')).toBeVisible()
    expect(screen.getByText('Required years: 3')).toBeVisible()
    expect(screen.getByText(/Exact closing time:.*20:30 UTC/)).toBeVisible()
    expect(screen.getByText(/Indicative result based on available data/)).toBeVisible()
    expect(screen.queryByText(/private@example|internal-01|SECRET-PARAMETER/)).not.toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Review opportunity' })).toHaveAttribute('href', '/opportunities/fondo-nandu')
    expect(matchingApi.list).toHaveBeenCalledExactlyOnceWith(workspaceOrganizationId, workspaceProjectId, 2, 10, expect.any(AbortSignal))
    expect(matchingApi.get).toHaveBeenCalledExactlyOnceWith(workspaceOrganizationId, workspaceProjectId, matchingRunId, expect.any(AbortSignal))
    expect(matchingApi.calculate).not.toHaveBeenCalled()
    await userEvent.click(screen.getByRole('button', { name: 'Next history page' }))
    await screen.findByText('Page 3 of 3')
    expect(new URLSearchParams(router.state.location.search).get('context')).toBe('original')
    expect(matchingApi.list).toHaveBeenCalledTimes(2)
    expect(matchingApi.calculate).not.toHaveBeenCalled()
  })

  it.each([false, true])('does not repeat a pending calculation and translates its success/replay notice (%s)', async wasReplay => {
    const pending = deferred<MatchingRunCreated>()
    vi.mocked(matchingApi.calculate).mockImplementation(() => pending.promise)
    const router = mount()
    await screen.findByRole('heading', { name: matchingDetail.items[0].fundingOpportunity.title })
    await userEvent.click(screen.getByRole('button', { name: 'Calcular versión actual' }))
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('combobox', { name: /Project to compare/ })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Calculate current version' })).toBeDisabled()
    expect(matchingApi.calculate).toHaveBeenCalledExactlyOnceWith(workspaceOrganizationId, workspaceProjectId, expect.any(String))
    await act(async () => { pending.resolve({ run: matchingDetail, wasReplay }); await pending.promise })
    expect(await screen.findByText(wasReplay ? 'The same calculation was safely retrieved.' : 'The calculation completed successfully.')).toBeVisible()
    expect(new URLSearchParams(router.state.location.search).get('runId')).toBe(matchingRunId)
    expect(new URLSearchParams(router.state.location.search).has('page')).toBe(false)
    await act(() => setInterfaceLanguage('es'))
    expect(screen.getByText(wasReplay ? 'Se recuperó de forma segura el mismo cálculo.' : 'El cálculo terminó correctamente.')).toBeVisible()
    expect(matchingApi.calculate).toHaveBeenCalledOnce()
  })

  it.each([503, 409])('keeps idempotency retry rules across a translated HTTP %s error', async status => {
    vi.mocked(matchingApi.calculate).mockRejectedValueOnce(new ApiError({ status, title: 'SECRET-DIAGNOSTIC' }, new Response(null, { status })))
    mount()
    await screen.findByRole('heading', { name: matchingDetail.items[0].fundingOpportunity.title })
    await userEvent.click(screen.getByRole('button', { name: 'Calcular versión actual' }))
    await screen.findByRole('heading', { name: 'No pudimos completar el cálculo' })
    const firstKey = vi.mocked(matchingApi.calculate).mock.calls[0][2]
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('heading', { name: 'We could not complete the calculation' })).toBeVisible()
    expect(screen.queryByText('SECRET-DIAGNOSTIC')).not.toBeInTheDocument()
    expect(matchingApi.calculate).toHaveBeenCalledOnce()
    await userEvent.click(screen.getByRole('button', { name: 'Retry calculation' }))
    await screen.findByText('The calculation completed successfully.')
    const retryKey = vi.mocked(matchingApi.calculate).mock.calls[1][2]
    if (status === 503) expect(retryKey).toBe(firstKey)
    else expect(retryKey).not.toBe(firstKey)
    expect(matchingApi.calculate).toHaveBeenCalledTimes(2)
  })

  it('keeps archived projects read-only while translating history', async () => {
    vi.mocked(projectApi.list).mockResolvedValue([{ ...workspaceProject, publicationStatus: 4 }])
    mount()
    await screen.findByRole('heading', { name: matchingDetail.items[0].fundingOpportunity.title })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('option', { name: workspaceProject.title + ' (Archived)' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Calculate current version' })).toBeDisabled()
    expect(screen.getByText(/Archived project: you can view its history/)).toBeVisible()
    expect(matchingApi.calculate).not.toHaveBeenCalled()
  })

  it('translates read errors and retries only the requested read', async () => {
    vi.mocked(matchingApi.list).mockRejectedValueOnce(new Error('SECRET-DIAGNOSTIC'))
    mount()
    await screen.findByRole('heading', { name: 'No pudimos consultar el historial' })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByText('Check your connection and try again.')).toBeVisible()
    expect(matchingApi.list).toHaveBeenCalledOnce()
    await userEvent.click(screen.getByRole('button', { name: 'Retry' }))
    await screen.findByRole('heading', { name: 'Indicative compatibility' })
    expect(matchingApi.calculate).not.toHaveBeenCalled()
    expect(matchingApi.list).toHaveBeenCalledTimes(2)
  })

  it('preserves a custom source disclaimer and unknown rule names without leaking arbitrary evidence', async () => {
    vi.mocked(matchingApi.get).mockResolvedValue({ ...matchingDetail, disclaimer: 'Aviso original actualizado.',
      items: [{ ...matchingDetail.items[0], ruleResults: [{ ...matchingDetail.items[0].ruleResults[0], code: 'future-rule', name: 'Regla original futura', reasonCode: 'UNKNOWN_FUTURE_CODE', evidence: { source: 'SECRET-SOURCE', fieldCode: 'SECRET-FIELD', valueCodes: ['SECRET-VALUE'] } }] }],
    })
    mount()
    await screen.findByText('Aviso original actualizado.')
    await act(() => setInterfaceLanguage('en'))
    await userEvent.click(screen.getByText('View breakdown of 1 rule'))
    expect(screen.getByText('Aviso original actualizado.')).toHaveAttribute('lang', 'es')
    expect(screen.getByRole('heading', { name: 'Regla original futura' })).toHaveAttribute('lang', 'es')
    expect(screen.getByText('There is not enough data to assess “Regla original futura”.')).toBeVisible()
    expect(screen.getByText(/Versioned source · Structured field/)).toBeVisible()
    expect(screen.queryByText(/SECRET-/)).not.toBeInTheDocument()
  })
})
