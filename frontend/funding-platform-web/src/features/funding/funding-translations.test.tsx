import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter } from 'react-router-dom'
import { QueryClientProvider } from '@tanstack/react-query'
import { vi } from 'vitest'
import { App } from '@/App'
import { createAppQueryClient } from '@/api/query-client'
import { appRoutes } from '@/router'
import { setInterfaceLanguage } from '@/i18n'
import { setAuthenticatedSession } from '@/features/auth/auth-session'
import { FundingTranslationEditor } from './funding-translations-page'
import type { AdminFundingOpportunityDetail } from './admin-funding-api'
import { translationFields, type FundingTranslationText } from './funding-translations-api'

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
const source = {
  publicId: 'test-fund', opportunityId: 'test-fund', slug: 'test-fund', title: 'Original title', summary: 'Original summary',
  description: 'Original description', sponsorName: 'Original sponsor', sourceName: 'Source', sourceUrl: 'https://example.invalid/source',
  applicationUrl: 'https://example.invalid/apply', currency: 'AUD', minimumAmount: 1000, maximumAmount: 3000,
  openDate: '2026-01-01', closeDate: '2027-01-01', lastVerifiedAtUtc: '2026-09-01T12:00:00Z', funders: [], dataQualityScore: 100,
  contentVersion: 3, eTag: '"0000000000000003"',
} as unknown as AdminFundingOpportunityDetail
const translated = {
  ...source, title: 'Título traducido', summary: 'Resumen traducido', description: 'Descripción traducida',
  localization: { status: 'translated', requestedLanguage: 'es', revision: 1 },
}
const text = Object.fromEntries(translationFields.map(([key]) => [key, translated[key as keyof typeof translated] ?? null])) as FundingTranslationText

afterEach(() => { vi.unstubAllEnvs(); vi.unstubAllGlobals(); vi.restoreAllMocks() })
const openDetail = () => render(<App router={createMemoryRouter(appRoutes, { initialEntries: ['/funding/test-fund'] })} queryClient={createAppQueryClient()} />)

it('requests the selected language, preserves canonical values, toggles original and isolates language caches', async () => {
  vi.stubEnv('VITE_FUNDING_TRANSLATIONS_ENABLED', 'true')
  const urls: string[] = []
  vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
    const url = String(input); urls.push(url)
    if (url.includes('locale=es')) return json(translated)
    return json({ ...source, ...(url.includes('locale=en') ? { localization: { status: 'original', requestedLanguage: 'en', revision: null } } : {}) })
  }))
  const user = userEvent.setup()
  openDetail()
  expect(await screen.findByRole('heading', { name: 'Título traducido' })).toBeInTheDocument()
  expect(screen.getByText('Original sponsor')).toBeInTheDocument()
  expect(screen.getByText(/Traducción revisada/)).toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: 'Ver texto original' }))
  expect(await screen.findByRole('heading', { name: 'Original title' })).toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: 'Ver en mi idioma' }))
  expect(await screen.findByRole('heading', { name: 'Título traducido' })).toBeInTheDocument()
  await act(() => setInterfaceLanguage('en'))
  expect(await screen.findByText(/no reviewed translation is available/)).toBeInTheDocument()
  expect(screen.getByRole('heading', { name: 'Original title' })).toBeInTheDocument()
  expect(urls.some(url => url.endsWith('/test-fund?locale=es'))).toBe(true)
  expect(urls.some(url => url.endsWith('/test-fund?locale=en'))).toBe(true)
  expect(urls.some(url => url.endsWith('/test-fund'))).toBe(true)
})

it('does not request translations while the feature is disabled', async () => {
  vi.stubEnv('VITE_FUNDING_TRANSLATIONS_ENABLED', 'false')
  const fetch = vi.fn(async (_input: RequestInfo | URL) => json(source)); vi.stubGlobal('fetch', fetch)
  openDetail()
  expect(await screen.findByRole('heading', { name: 'Original title' })).toBeInTheDocument()
  expect(String(fetch.mock.calls[0]?.[0])).not.toContain('locale=')
  expect(screen.queryByRole('complementary', { name: 'Idioma del contenido' })).not.toBeInTheDocument()
})

it('requires full coverage and explicit review, resets approval on edits and keeps text after a 412', async () => {
  const requests: Array<{ input: unknown, options: RequestInit }> = []
  let fail = false
  vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL, options: RequestInit) => {
    requests.push({ input, options })
    if (fail) return json({ title: 'Conflict', status: 412 }, 412)
    const data = JSON.parse(String(options.body))
    return json({ language: 'es', sourceContentVersion: 3, revision: 1, reviewed: data.reviewed, text: data.text, updatedAtUtc: '2026-09-21T00:00:00Z' })
  }))
  const user = userEvent.setup()
  render(<QueryClientProvider client={createAppQueryClient()}><FundingTranslationEditor original={source} translation={null} language="es" onDirtyChange={vi.fn()} onReload={vi.fn()} /></QueryClientProvider>)
  const approve = screen.getByRole('button', { name: 'Guardar traducción revisada' })
  expect(approve).toBeDisabled()
  for (const [label, value] of [['Título · ES', 'Título'], ['Resumen · ES', 'Resumen'], ['Descripción completa · ES', 'Descripción']]) {
    fireEvent.change(screen.getByLabelText(label), { target: { value } })
  }
  await user.click(screen.getByRole('checkbox'))
  expect(approve).toBeEnabled()
  fireEvent.change(screen.getByLabelText('Título · ES'), { target: { value: 'Título corregido' } })
  expect(approve).toBeDisabled()
  await user.click(screen.getByRole('checkbox'))
  await user.click(approve)
  expect(await screen.findByText('Traducción guardada.')).toBeInTheDocument()
  const write = requests[0]
  expect(new Headers(write.options.headers).get('If-Match')).toBe(source.eTag)
  expect(JSON.parse(String(write.options.body))).toMatchObject({ sourceContentVersion: 3, expectedRevision: 0, reviewed: true, text: { title: 'Título corregido' } })
  fail = true
  fireEvent.change(screen.getByLabelText('Título · ES'), { target: { value: 'Conservar este texto' } })
  await user.click(screen.getByRole('button', { name: 'Guardar como borrador' }))
  expect(await screen.findByRole('alert')).toHaveTextContent('Conservamos tu texto')
  expect(screen.getByLabelText('Título · ES')).toHaveValue('Conservar este texto')
  expect(JSON.parse(String(requests[1].options.body))).toMatchObject({ expectedRevision: 1, reviewed: false })
})

it('shows outdated translations as drafts requiring review', () => {
  render(<QueryClientProvider client={createAppQueryClient()}><FundingTranslationEditor original={source} translation={{ language: 'es', sourceContentVersion: 2, revision: 5, reviewed: true, text, updatedAtUtc: '2026-09-01T00:00:00Z' }} language="es" onDirtyChange={vi.fn()} onReload={vi.fn()} /></QueryClientProvider>)
  expect(screen.getByText(/El original cambió/)).toBeInTheDocument()
  expect(screen.getByText(/Borrador: esta traducción/)).toBeInTheDocument()
  expect(screen.getByRole('button', { name: 'Guardar traducción revisada' })).toBeDisabled()
})

it('loads the admin route, prevents language switches with a draft and confirms navigation', async () => {
  vi.stubEnv('VITE_FUNDING_TRANSLATIONS_ENABLED', 'true')
  setAuthenticatedSession({ status: 'authenticated', accessToken: 'test-admin', accessTokenExpiresAtUtc: '2099-01-01T00:00:00Z', user: {
    publicId: 'admin', email: 'admin@example.invalid', displayName: 'Admin', preferredLocale: 'es-CL', roles: ['Admin'], mfaEnabled: true,
  } })
  vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => json(String(input).includes('/translations/') ? { translation: null } : source)))
  const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false)
  const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/funding/test-fund/translations'] })
  render(<App router={router} queryClient={createAppQueryClient()} />)
  fireEvent.change(await screen.findByLabelText('Título · ES'), { target: { value: 'Mi borrador' } })
  expect(screen.getByLabelText('Idioma de la traducción')).toBeDisabled()
  await act(() => router.navigate('/admin/funding'))
  await waitFor(() => expect(confirm).toHaveBeenCalled())
  expect(screen.getByLabelText('Título · ES')).toHaveValue('Mi borrador')
})

it('generates only on confirmation, freezes editing while pending, and requires explicit review before saving', async () => {
  let resolve: (response: Response) => void = () => {}
  const fetch = vi.fn((_input: RequestInfo | URL, _options: RequestInit) => new Promise<Response>(done => { resolve = done }))
  vi.stubGlobal('fetch', fetch)
  const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false)
  const dirty = vi.fn()
  const user = userEvent.setup()
  render(<QueryClientProvider client={createAppQueryClient()}><FundingTranslationEditor original={source} translation={null} language="es" generationAvailable onDirtyChange={dirty} onReload={vi.fn()} /></QueryClientProvider>)
  const generate = screen.getByRole('button', { name: 'Generar propuesta automática' })
  expect(fetch).not.toHaveBeenCalled()
  await user.click(generate)
  expect(fetch).not.toHaveBeenCalled()
  confirm.mockReturnValue(true)
  await user.click(generate)
  expect(screen.getByRole('button', { name: 'Generando propuesta…' })).toBeDisabled()
  expect(screen.getByLabelText('Título · ES')).toBeDisabled()
  expect(screen.getByRole('button', { name: 'Guardar como borrador' })).toBeDisabled()
  expect(dirty).toHaveBeenLastCalledWith(true)
  expect(fetch).toHaveBeenCalledTimes(1)
  const [url, options] = fetch.mock.calls[0]
  expect(String(url)).toContain('/translations/es/generate')
  expect(options.method).toBe('POST')
  expect(new Headers(options.headers).get('If-Match')).toBe(source.eTag)
  expect(JSON.parse(String(options.body))).toEqual({ sourceContentVersion: 3 })
  await act(async () => resolve(json({ generationId: 'proposal', language: 'es', sourceContentVersion: 3, text, reused: false })))
  expect(await screen.findByText(/Propuesta cargada/)).toBeInTheDocument()
  expect(screen.getByLabelText('Título · ES')).toHaveValue('Título traducido')
  const approve = screen.getByRole('button', { name: 'Guardar traducción revisada' })
  expect(approve).toBeDisabled()
  expect(screen.getByRole('button', { name: 'Generar propuesta automática' })).toBeDisabled()
  expect(fetch).toHaveBeenCalledTimes(1) // Generation did not trigger PUT or approval.
  await user.click(screen.getByRole('checkbox'))
  expect(approve).toBeEnabled()
})

it('does not replace an unsaved draft and exposes no generation action when unavailable', () => {
  const fetch = vi.fn(); vi.stubGlobal('fetch', fetch)
  const { rerender } = render(<QueryClientProvider client={createAppQueryClient()}><FundingTranslationEditor original={source} translation={null} language="es" onDirtyChange={vi.fn()} onReload={vi.fn()} /></QueryClientProvider>)
  expect(screen.queryByRole('button', { name: 'Generar propuesta automática' })).not.toBeInTheDocument()
  expect(screen.getByText(/Generación automática no habilitada/)).toBeInTheDocument()
  rerender(<QueryClientProvider client={createAppQueryClient()}><FundingTranslationEditor original={source} translation={null} language="es" generationAvailable onDirtyChange={vi.fn()} onReload={vi.fn()} /></QueryClientProvider>)
  fireEvent.change(screen.getByLabelText('Título · ES'), { target: { value: 'No borrar' } })
  expect(screen.getByRole('button', { name: 'Generar propuesta automática' })).toBeDisabled()
  expect(screen.getByLabelText('Título · ES')).toHaveValue('No borrar')
  expect(fetch).not.toHaveBeenCalled()
})

it.each([429, 409, 412, 422, 503, 502])('preserves the saved translation and does not retry a generation error %s', async (status) => {
  const fetch = vi.fn(async () => json({ title: 'Generation failed', status }, status))
  vi.stubGlobal('fetch', fetch); vi.spyOn(window, 'confirm').mockReturnValue(true)
  const user = userEvent.setup()
  render(<QueryClientProvider client={createAppQueryClient()}><FundingTranslationEditor original={source} translation={{ language: 'es', sourceContentVersion: 3, revision: 7, reviewed: true, text, updatedAtUtc: '2026-09-22T12:00:00Z' }} language="es" generationAvailable onDirtyChange={vi.fn()} onReload={vi.fn()} /></QueryClientProvider>)
  await user.click(screen.getByRole('button', { name: 'Generar propuesta automática' }))
  expect(await screen.findByRole('alert')).toBeInTheDocument()
  expect(screen.getByLabelText('Título · ES')).toHaveValue('Título traducido')
  expect(screen.getByRole('checkbox')).not.toBeChecked()
  expect(fetch).toHaveBeenCalledTimes(1)
})

it.each([null, { text: null }, { language: 'en', sourceContentVersion: 3, text }, { language: 'es', sourceContentVersion: 2, text }, { language: 'es', sourceContentVersion: 3, text: { title: 'Incompleta' } }])('rejects a malformed proposal without losing editor contents', async (proposal) => {
  vi.stubGlobal('fetch', vi.fn(async () => json(proposal))); vi.spyOn(window, 'confirm').mockReturnValue(true)
  const user = userEvent.setup()
  render(<QueryClientProvider client={createAppQueryClient()}><FundingTranslationEditor original={source} translation={{ language: 'es', sourceContentVersion: 3, revision: 7, reviewed: true, text, updatedAtUtc: '2026-09-22T12:00:00Z' }} language="es" generationAvailable onDirtyChange={vi.fn()} onReload={vi.fn()} /></QueryClientProvider>)
  await user.click(screen.getByRole('button', { name: 'Generar propuesta automática' }))
  expect(await screen.findByRole('alert')).toHaveTextContent('Conservamos tus textos')
  expect(screen.getByLabelText('Título · ES')).toHaveValue('Título traducido')
})
