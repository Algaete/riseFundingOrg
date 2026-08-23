import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { setAuthenticatedSession } from '@/features/auth/auth-session'
import { appRoutes } from '@/router'

const runId = '9c50f0c1-1622-47e1-94f1-68ecf262db83'

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': status >= 400 ? 'application/problem+json' : 'application/json' },
  })
}

function source() {
  return {
    id: 12,
    name: 'Grants.gov',
    providerType: 1,
    providerCode: 'grants-gov',
    baseUrl: 'https://api.grants.gov',
    isEnabled: true,
    operationalStatus: 'Saludable',
    complianceStatus: 'approved',
    licenseName: 'Public Domain',
    licenseUrl: 'https://grants.gov/legal/terms',
    licenseStatus: 'reviewed',
    isAllowlisted: true,
    rateLimitPerMinute: 60,
    robotsPolicyStatus: 'Permitido',
    robotsReviewedAtUtc: '2026-08-21T10:00:00Z',
    acquisitionReady: true,
    rssFeedUrl: 'https://grants.gov/rss/opportunities.xml',
    lastSuccessfulRunAtUtc: '2026-08-22T11:00:00Z',
    nextScheduledRunAtUtc: '2026-08-22T13:00:00Z',
  }
}

function summary(overrides: Record<string, unknown> = {}) {
  return {
    runId,
    fundingSourceId: 12,
    sourceName: 'Grants.gov',
    providerCode: 'grants-gov',
    triggerType: 0,
    status: 2,
    keyword: 'climate resilience',
    maximumResults: 25,
    retrievedCount: 8,
    createdCount: 3,
    updatedCount: 1,
    unchangedCount: 2,
    stagedForReviewCount: 2,
    failedCount: 0,
    createdAtUtc: '2026-08-22T12:00:00Z',
    startedAtUtc: '2026-08-22T12:00:02Z',
    completedAtUtc: '2026-08-22T12:01:00Z',
    lastErrorCode: null,
    ...overrides,
  }
}

function detail(overrides: Record<string, unknown> = {}) {
  return {
    ...summary(),
    attemptCount: 1,
    items: [{
      itemId: '15d031fa-171c-4891-a5b1-7a8140ea5634',
      rawObservationId: 'ec2e2a7d-5b49-45d8-927e-655b69526c7a',
      opportunityId: '04b6d64c-3495-45af-9c73-a4ce4202dbb6',
      externalId: 'GRANT-2026-001',
      status: 2,
      outcomeCode: 'staged-for-review',
      createdAtUtc: '2026-08-22T12:00:05Z',
      completedAtUtc: '2026-08-22T12:00:06Z',
    }],
    errors: [{
      errorId: '75ebac8b-5571-4c1f-80cf-7d7e24eeb174',
      itemId: null,
      stage: 'normalize',
      code: 'missing-field',
      message: 'Un registro no indicó fecha de cierre.',
      isRetryable: false,
      occurredAtUtc: '2026-08-22T12:00:30Z',
    }],
    ...overrides,
  }
}

function authenticateAdmin() {
  setAuthenticatedSession({
    status: 'authenticated',
    accessToken: 'admin-access-token',
    accessTokenExpiresAtUtc: '2099-08-22T18:00:00Z',
    user: {
      publicId: '89b8d22a-472c-42e4-b034-c772ce3bb08e',
      email: 'admin@example.test',
      displayName: 'Administradora',
      preferredLocale: 'es-CL',
      roles: ['Admin'],
      mfaEnabled: true,
    },
  })
}

function renderRoute(path: string) {
  const queryClient = createAppQueryClient()
  queryClient.setDefaultOptions({ queries: { retry: false } })
  const router = createMemoryRouter(appRoutes, { initialEntries: [path] })
  render(<App router={router} queryClient={queryClient} />)
  return router
}

describe('consola administrativa de importaciones', () => {
  beforeEach(() => {
    authenticateAdmin()
    sessionStorage.clear()
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
    sessionStorage.clear()
  })

  it('muestra estados y navega desde el listado al detalle seguro', async () => {
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      const url = String(input)
      if (url.endsWith('/admin/funding-sources')) return Promise.resolve(json([source()]))
      if (url.includes('/admin/import-runs?')) return Promise.resolve(json({ items: [summary()], totalCount: 1, page: 1, pageSize: 20 }))
      if (url.endsWith(`/admin/import-runs/${runId}`)) return Promise.resolve(json(detail()))
      return Promise.resolve(json({ title: 'No encontrado', status: 404 }, 404))
    }))
    const user = userEvent.setup()
    const router = renderRoute('/admin/imports')

    expect(await screen.findByRole('heading', { name: 'Importaciones', level: 1 })).toBeInTheDocument()
    expect(await screen.findByText('Completada')).toBeInTheDocument()
    expect(screen.getByText('Cada candidato queda pendiente de revisión editorial', { exact: false })).toBeInTheDocument()
    await user.click(await screen.findByRole('link', { name: 'Ver detalle' }))

    expect(await screen.findByRole('heading', { name: 'Importación: climate resilience', level: 1 })).toBeInTheDocument()
    expect(screen.getByText('GRANT-2026-001')).toBeInTheDocument()
    expect(screen.getByText('Un registro no indicó fecha de cierre.')).toBeInTheDocument()
    expect(screen.getByText('Los resultados quedan en revisión editorial', { exact: false })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Abrir candidato/ })).toHaveAttribute(
      'href',
      '/admin/funding/04b6d64c-3495-45af-9c73-a4ce4202dbb6',
    )
    expect(router.state.location.pathname).toBe(`/admin/imports/${runId}`)
  })

  it('inicia Grants.gov, conserva el contrato HTTP y abre la ejecución aceptada', async () => {
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input)
      if (url.endsWith('/admin/funding-sources')) return Promise.resolve(json([source()]))
      if (url.includes('/admin/import-runs?')) return Promise.resolve(json({ items: [], totalCount: 0, page: 1, pageSize: 20 }))
      if (url.endsWith('/admin/funding-sources/12/import-runs') && init?.method === 'POST') {
        return Promise.resolve(json({
          runId,
          fundingSourceId: 12,
          sourceName: 'Grants.gov',
          status: 0,
          createdAtUtc: '2026-08-22T12:00:00Z',
          wasReplay: false,
          statusUrl: `/api/v1/admin/import-runs/${runId}`,
        }, 202))
      }
      if (url.endsWith(`/admin/import-runs/${runId}`)) return Promise.resolve(json(detail({ status: 0, items: [], errors: [] })))
      return Promise.resolve(json({ title: 'No encontrado', status: 404 }, 404))
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    const router = renderRoute('/admin/imports?sourceId=12')

    expect(await screen.findAllByRole('option', { name: 'Grants.gov' })).toHaveLength(2)
    await user.click(screen.getByRole('button', { name: 'Iniciar importación' }))

    await waitFor(() => expect(router.state.location.pathname).toBe(`/admin/imports/${runId}`))
    const createCall = fetchMock.mock.calls.find(([input, init]) =>
      String(input).endsWith('/admin/funding-sources/12/import-runs') && init?.method === 'POST')
    expect(createCall).toBeDefined()
    const options = createCall?.[1] as RequestInit
    expect(JSON.parse(String(options.body))).toEqual({ keyword: 'nonprofit', maximumResults: 25 })
    expect(new Headers(options.headers).get('Idempotency-Key')).toMatch(/^[0-9a-f-]{36}$/i)
    expect(await screen.findByText('Esta ejecución sigue activa.', { exact: false })).toBeInTheDocument()
  })

  it('rechaza en cliente un maximumResults mayor que 25', async () => {
    const fetchMock = vi.fn((input: RequestInfo | URL, _init?: RequestInit) => {
      const url = String(input)
      if (url.endsWith('/admin/funding-sources')) return Promise.resolve(json([source()]))
      if (url.includes('/admin/import-runs?')) return Promise.resolve(json({ items: [], totalCount: 0, page: 1, pageSize: 20 }))
      return Promise.resolve(json({}, 404))
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    renderRoute('/admin/imports')

    const maximum = await screen.findByLabelText('Máximo')
    await user.clear(maximum)
    await user.type(maximum, '26')
    await user.click(screen.getByRole('button', { name: 'Iniciar importación' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('La cantidad debe ser un entero entre 1 y 25.')
    expect(fetchMock.mock.calls.some(([input, init]) =>
      String(input).endsWith('/import-runs') && init?.method === 'POST')).toBe(false)
  })

  it('presenta un error recuperable sin reflejar payloads del servidor', async () => {
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      const url = String(input)
      if (url.endsWith('/admin/funding-sources')) return Promise.resolve(json([source()]))
      if (url.includes('/admin/import-runs?')) {
        return Promise.resolve(json({
          title: 'Servicio temporalmente no disponible',
          detail: 'Intenta nuevamente.',
          status: 503,
          rawPayload: 'secret-upstream-response',
        }, 503))
      }
      return Promise.resolve(json({}, 404))
    }))
    renderRoute('/admin/imports')

    expect(await screen.findByRole('alert')).toHaveTextContent('Intenta nuevamente.')
    expect(screen.getByRole('button', { name: 'Reintentar' })).toBeInTheDocument()
    expect(screen.queryByText(/secret-upstream-response/)).not.toBeInTheDocument()
  })

  it('muestra salud y cumplimiento y permite iniciar desde Fuentes', async () => {
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      if (String(input).endsWith('/admin/funding-sources')) return Promise.resolve(json([source()]))
      return Promise.resolve(json({}, 404))
    }))
    renderRoute('/admin/sources')

    expect(await screen.findByRole('heading', { name: 'Fuentes de importación', level: 1 })).toBeInTheDocument()
    expect(await screen.findByText('Saludable')).toBeInTheDocument()
    expect(screen.getByText('Aprobada')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Public Domain/ })).toHaveAttribute('href', 'https://grants.gov/legal/terms')
    expect(screen.getByText('Autorizada')).toBeInTheDocument()
    expect(screen.getByText('60 solicitudes/minuto')).toBeInTheDocument()
    expect(screen.getByText('Permitido')).toBeInTheDocument()
    expect(screen.getByText('Lista para adquirir')).toBeInTheDocument()
    expect(screen.getByText('RSS configurado · grants.gov')).toBeInTheDocument()
    expect(screen.getByText('esta pantalla no admite feeds arbitrarios', { exact: false })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Crear importación/ })).toHaveAttribute('href', '/admin/imports?sourceId=12')
  })

  it('compara un posible duplicado y exige confirmación humana sin publicar', async () => {
    const candidateId = '04b6d64c-3495-45af-9c73-a4ce4202dbb6'
    const duplicateCandidateId = '14b6d64c-3495-45af-9c73-a4ce4202dbb6'
    const existingId = '74b6d64c-3495-45af-9c73-a4ce4202dbb6'
    const itemId = '15d031fa-171c-4891-a5b1-7a8140ea5634'
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input)
      if (url.endsWith(`/admin/funding-duplicate-candidates/${duplicateCandidateId}`) && init?.method === 'GET') {
        return Promise.resolve(json({
          candidateId: duplicateCandidateId,
          candidate: {
            opportunityId: candidateId,
            title: 'Advancing Global Health 2026',
            sponsor: 'Global Health Office',
            publicationStatus: 0,
          },
          suggestedCanonical: {
            opportunityId: existingId,
            title: 'Advancing Global Health',
            sponsor: 'Global Health Office',
            publicationStatus: 1,
          },
          matchKind: 2,
          matchReasonCode: 'normalized-title-sponsor',
          confidence: 0.92,
          status: 0,
          decision: null,
          eTag: '"0102030405060708"',
          rawPayload: 'never-display',
        }))
      }
      if (url.endsWith(`/admin/funding-duplicate-candidates/${duplicateCandidateId}/decisions`) && init?.method === 'POST') {
        return Promise.resolve(json({
          candidateId: duplicateCandidateId,
          decisionId: '24b6d64c-3495-45af-9c73-a4ce4202dbb6',
          status: 1,
          decision: 2,
          canonicalOpportunityId: existingId,
          eTag: '"0203040506070809"',
          wasReplay: false,
        }))
      }
      if (url.endsWith(`/admin/import-runs/${runId}`)) {
        return Promise.resolve(json(detail({
          items: [{
            itemId,
            duplicateCandidateId,
            opportunityId: candidateId,
            candidateOpportunityId: candidateId,
            suggestedCanonicalOpportunityId: existingId,
            externalId: 'GRANT-2026-001',
            status: 2,
            outcomeCode: 'staged-for-review',
            duplicateCandidateStatus: 0,
            duplicateMatchKind: 2,
            duplicateConfidence: 0.92,
            requiresEditorialReview: true,
            isAutoPublished: false,
            createdAtUtc: '2026-08-22T12:00:05Z',
            completedAtUtc: '2026-08-22T12:00:06Z',
          }],
          errors: [],
        })))
      }
      return Promise.resolve(json({}, 404))
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    renderRoute(`/admin/imports/${runId}`)

    await user.click(await screen.findByRole('button', { name: 'Comparar duplicado' }))
    expect(await screen.findByText('Advancing Global Health 2026')).toBeInTheDocument()
    expect(screen.getByText('Advancing Global Health', { exact: true })).toBeInTheDocument()
    expect(screen.queryByText('never-display')).not.toBeInTheDocument()

    expect(screen.getByRole('button', { name: 'Ignorar sugerencia' })).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Marcar como duplicado' }))
    const dialog = screen.getByRole('dialog', { name: 'Confirmar decisión de duplicidad' })
    expect(dialog).toHaveTextContent('El candidato seguirá sin publicar.')
    await user.click(screen.getByRole('button', { name: 'Confirmar decisión' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Ingresa un motivo de al menos 3 caracteres.')
    expect(fetchMock.mock.calls.some(([input, init]) =>
      String(input).endsWith('/decisions') && init?.method === 'POST')).toBe(false)

    await user.type(screen.getByLabelText('Motivo obligatorio'), 'Coinciden organismo y fecha.')
    await user.click(screen.getByRole('button', { name: 'Confirmar decisión' }))

    expect(await screen.findByText('Decisión guardada correctamente. Ningún fondo fue publicado.')).toBeInTheDocument()
    const request = fetchMock.mock.calls.find(([input, init]) =>
      String(input).endsWith(`/admin/funding-duplicate-candidates/${duplicateCandidateId}/decisions`) && init?.method === 'POST')
    expect(request).toBeDefined()
    const options = request?.[1] as RequestInit
    expect(options.cache).toBe('no-store')
    expect(new Headers(options.headers).get('If-Match')).toBe('"0102030405060708"')
    expect(new Headers(options.headers).get('Idempotency-Key')).toMatch(/^[0-9a-f-]{36}$/i)
    expect(JSON.parse(String(options.body))).toEqual({
      decision: 'mark-duplicate',
      canonicalOpportunityId: existingId,
      reason: 'Coinciden organismo y fecha.',
    })
    const persisted = Array.from(
      { length: sessionStorage.length },
      (_, index) => sessionStorage.getItem(sessionStorage.key(index) ?? ''),
    ).join('')
    expect(persisted).not.toContain('Coinciden organismo y fecha.')
  })
})
