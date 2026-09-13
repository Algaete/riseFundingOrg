import { QueryClient, QueryClientProvider, focusManager, onlineManager } from '@tanstack/react-query'
import { act, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { setAuthenticatedSession } from '@/features/auth/auth-session'
import { setInterfaceLanguage } from '@/i18n'
import { gapRecommendations, gapOrganizationId } from '@/test/fixtures/gap-recommendations'
import { GapRecommendationsPanel } from './gap-recommendations-panel'
import { gapCandidateHref, gapEvidenceHref } from './gap-recommendations-api'

const projectId = '11111111-1111-1111-1111-111111111111'
const opportunityId = '22222222-2222-2222-2222-222222222222'
function session(actor = '33333333-3333-3333-3333-333333333333') {
  setAuthenticatedSession({ status: 'authenticated', accessToken: 'synthetic', accessTokenExpiresAtUtc: '2099-01-01T00:00:00Z',
    user: { publicId: actor, email: 'synthetic@example.invalid', displayName: 'Prueba', preferredLocale: 'es-CL', roles: ['Professional'], mfaEnabled: false } })
}
function setup(props = { projectId, opportunityId, hasHardGaps: true, historical: true }) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  const tree = (values = props) => <MemoryRouter><QueryClientProvider client={client}><GapRecommendationsPanel {...values} /></QueryClientProvider></MemoryRouter>
  const view = render(tree())
  return { ...view, client, changeProject: (next: string) => view.rerender(tree({ ...props, projectId: next })) }
}
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}

describe('actionable matching suggestions', () => {
  beforeEach(() => session())
  afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); focusManager.setFocused(undefined); onlineManager.setOnline(true) })

  it('loads only on explicit action, explains origins, navigates safely and never changes matching', async () => {
    const fetch = vi.fn().mockResolvedValue(json(gapRecommendations)); vi.stubGlobal('fetch', fetch)
    const { client } = setup()
    expect(fetch).not.toHaveBeenCalled()
    await userEvent.click(screen.getByRole('button', { name: 'Buscar apoyos para este fondo' }))
    expect(await screen.findByText('Fundación Aliada Ñandú')).toBeVisible()
    expect(screen.getByText(/Origen: requisito revisado del fondo/)).toBeVisible()
    expect(screen.getByText(/Origen: necesidad declarada por el proyecto/)).toBeVisible()
    expect(screen.getByText(/no corrige automáticamente/)).toBeVisible()
    expect(screen.getByText(/El cálculo mostrado es histórico/)).toBeVisible()
    expect(screen.getByRole('link', { name: 'Ver organización' })).toHaveAttribute('href', `/marketplace/organizations/${gapOrganizationId}`)
    expect(screen.getByText(/Consulta acotada a los 200/)).toBeVisible()
    expect(fetch).toHaveBeenCalledTimes(1)
    const [url, options] = fetch.mock.calls[0]
    expect(String(url)).toContain('/matching/gap-recommendations')
    expect(options).toMatchObject({ method: 'POST', cache: 'no-store', body: JSON.stringify({ projectId, opportunityId }) })
    await act(async () => { focusManager.setFocused(false); focusManager.setFocused(true); onlineManager.setOnline(false); onlineManager.setOnline(true); await client.invalidateQueries() })
    await act(async () => setInterfaceLanguage('en'))
    expect(screen.getByRole('heading', { name: 'How to address requirements' })).toBeVisible()
    expect(fetch).toHaveBeenCalledTimes(1)
  })

  it('discards old results after a failed explicit refresh', async () => {
    const fetch = vi.fn().mockResolvedValueOnce(json(gapRecommendations)).mockResolvedValueOnce(json({ title: 'Private detail', status: 404 }, 404))
    vi.stubGlobal('fetch', fetch); setup()
    await userEvent.click(screen.getByRole('button', { name: 'Buscar apoyos para este fondo' }))
    await screen.findByText('Fundación Aliada Ñandú')
    await userEvent.click(screen.getByRole('button', { name: 'Actualizar sugerencias' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('ya no están disponibles')
    expect(screen.queryByText('Fundación Aliada Ñandú')).not.toBeInTheDocument()
    expect(screen.queryByText('Private detail')).not.toBeInTheDocument()
    expect(fetch).toHaveBeenCalledTimes(2)
  })

  it('resets expansion and private content when the actor or project changes', async () => {
    const fetch = vi.fn().mockImplementation(() => Promise.resolve(json(gapRecommendations))); vi.stubGlobal('fetch', fetch)
    const view = setup()
    await userEvent.click(screen.getByRole('button', { name: 'Buscar apoyos para este fondo' }))
    await screen.findByText('Fundación Aliada Ñandú')
    act(() => session('44444444-4444-4444-4444-444444444444'))
    expect(screen.queryByText('Fundación Aliada Ñandú')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Buscar apoyos para este fondo' })).toHaveAttribute('aria-expanded', 'false')
    expect(fetch).toHaveBeenCalledTimes(1)
    await userEvent.click(screen.getByRole('button', { name: 'Buscar apoyos para este fondo' }))
    await screen.findByText('Fundación Aliada Ñandú')
    view.changeProject('55555555-5555-5555-5555-555555555555')
    expect(screen.queryByText('Fundación Aliada Ñandú')).not.toBeInTheDocument()
    expect(fetch).toHaveBeenCalledTimes(2)
  })

  it('shows missing reviewed data and no candidates without asserting eligibility', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(json({ ...gapRecommendations, classificationCurrent: false, evidenceUrl: null, items: [] })))
    setup()
    await userEvent.click(screen.getByRole('button', { name: 'Buscar apoyos para este fondo' }))
    expect(await screen.findByText(/no tiene una clasificación editorial vigente/)).toBeVisible()
    expect(screen.getByText(/Esto no significa que el proyecto cumpla/)).toBeVisible()
    expect(screen.queryByRole('link', { name: 'Revisar la fuente de los requisitos' })).not.toBeInTheDocument()
  })

  it('cancels an in-flight query on unmount', async () => {
    let signal: AbortSignal | undefined
    vi.stubGlobal('fetch', vi.fn((_url, options) => { signal = options.signal; return new Promise(() => {}) }))
    const view = setup()
    await userEvent.click(screen.getByRole('button', { name: 'Buscar apoyos para este fondo' }))
    await waitFor(() => expect(signal).toBeDefined())
    view.unmount(); expect(signal!.aborted).toBe(true)
  })

  it.each(['https://evil.example', '//evil.example', '/admin/users', '/marketplace/organizations/wrong', 'javascript:alert(1)'])('rejects an untrusted candidate action: %s', href => {
    expect(gapCandidateHref({ ...gapRecommendations.items[0].candidates[0], href }, 'international-partner')).toBeNull()
  })
  it('accepts SQL uppercase GUIDs without accepting arbitrary actions', () => {
    const candidate = gapRecommendations.items[0].candidates[0]
    expect(gapCandidateHref({ ...candidate, href: candidate.href.toUpperCase() }, 'international-partner')).toBe(candidate.href)
  })
  it.each(['http://example.invalid', 'javascript:alert(1)', 'https://user:password@example.invalid', 'https://example.invalid:1234'])('rejects unsafe evidence URL: %s', href => {
    expect(gapEvidenceHref(href)).toBeNull()
  })
})
