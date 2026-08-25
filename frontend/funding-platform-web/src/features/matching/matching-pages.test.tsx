import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter } from 'react-router-dom'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { clearAuthSession, setAuthenticatedSession } from '@/features/auth/auth-session'
import type { MatchingRunDetail } from '@/features/matching/matching-api'
import { appRoutes } from '@/router'

const organizationId = '51ea2f6f-b1af-4e09-856c-6dcbdcfc812f'
const projectId = 'bd351806-9139-4524-bc01-93c3676729cb'
const matchingRunId = 'f4299117-a4b5-4dfc-b89f-1a3942268f12'
const opportunityId = 'f5b75d2c-4c84-4ca3-91f7-e9c182fdff2c'

function json(value: unknown, status = 200) {
  return Promise.resolve(new Response(JSON.stringify(value), {
    status,
    statusText: status === 503 ? 'Service Unavailable' : undefined,
    headers: { 'Content-Type': 'application/json' },
  }))
}

function authenticate() {
  setAuthenticatedSession({
    status: 'authenticated',
    accessToken: 'matching-page-token',
    accessTokenExpiresAtUtc: '2027-08-24T12:00:00Z',
    user: {
      publicId: '89b8d22a-472c-42e4-b034-c772ce3bb08e',
      email: 'member@example.test',
      displayName: 'Miembro demo',
      preferredLocale: 'es-CL',
      roles: ['Professional'],
      mfaEnabled: false,
    },
  })
}

function organization() {
  return {
    publicId: organizationId,
    name: 'Fundación Demo',
    membershipRole: 'admin',
    profileStatus: 2,
    profileCompleteness: 100,
    profileVersion: 3,
    updatedAtUtc: '2026-08-24T10:00:00Z',
  }
}

function project(overrides: Record<string, unknown> = {}) {
  return {
    publicId: projectId,
    slug: 'agua-segura',
    title: 'Agua segura',
    summary: 'Acceso sostenible para comunidades rurales.',
    status: 2,
    publicationStatus: 2,
    startDate: '2027-01-01',
    endDate: '2027-12-31',
    budgetTotal: 100000,
    confirmedFunding: 25000,
    currency: 'USD',
    fundingGap: 75000,
    projectVersion: 4,
    updatedAtUtc: '2026-08-24T10:00:00Z',
    ...overrides,
  }
}

function run(overrides: Record<string, unknown> = {}) {
  return {
    publicId: matchingRunId,
    project: { publicId: projectId, slug: 'agua-segura', title: 'Agua segura' },
    status: 2,
    engineVersion: 'deterministic-v1',
    matchingProfile: { name: 'baseline', version: 1 },
    projectVersion: 4,
    organizationProfileVersion: 3,
    candidateCount: 200,
    compatibleCount: 1,
    incompatibleCount: 1,
    insufficientDataCount: 0,
    totalCandidateCount: 240,
    isTruncated: true,
    isCurrent: false,
    catalogSnapshotAtUtc: '2026-08-24T10:00:00Z',
    createdAtUtc: '2026-08-24T10:00:00Z',
    completedAtUtc: '2026-08-24T10:00:01Z',
    ...overrides,
  }
}

function detail(overrides: Record<string, unknown> = {}) {
  return {
    run: run(),
    items: [
      {
        fundingOpportunity: {
          publicId: opportunityId,
          slug: 'fondo-agua',
          title: 'Fondo para agua rural',
          sponsorName: 'Fundación Global',
          closeDate: '2027-02-15',
          closeAtUtc: null,
          deadlinePrecision: 1,
          contentVersion: 5,
        },
        classification: 2,
        compatibilityScore: 42.5,
        evidenceCoverage: 62.5,
        hardGateStatus: 2,
        isCurrent: false,
        ruleResults: [{
          code: 'geography',
          name: 'Geografía',
          isHardGate: true,
          isWarning: true,
          outcome: 3,
          dataState: 1,
          rawScore: null,
          weight: 20,
          weightedPoints: 0,
          reasonCode: 'geography.missing_project',
          reasonParameters: {},
          evidence: {
            source: 'versioned-snapshots',
            fieldCode: 'geography',
            valueCodes: ['private@example.test', 'internal-42'],
          },
          rawText: 'Texto privado de las bases',
        }],
      },
      {
        fundingOpportunity: {
          publicId: '5ae34208-a426-4ae2-ab17-3087db4f6fe2',
          slug: 'fondo-excluyente',
          title: 'Fondo con condición excluyente',
          sponsorName: 'Agencia Demo',
          closeDate: null,
          closeAtUtc: null,
          deadlinePrecision: 0,
          contentVersion: 2,
        },
        classification: 1,
        compatibilityScore: null,
        evidenceCoverage: 100,
        hardGateStatus: 1,
        isCurrent: true,
        ruleResults: [{
          code: 'organization_type',
          name: 'Tipo de organización',
          isHardGate: true,
          isWarning: false,
          outcome: 2,
          dataState: 0,
          rawScore: null,
          weight: 15,
          weightedPoints: 0,
          reasonCode: 'organization_type.not_allowed',
          reasonParameters: {},
          evidence: null,
        }],
      },
    ],
    disclaimer: 'Resultado orientativo basado en datos disponibles; no confirma elegibilidad ni reemplaza la revisión de las bases del fondo.',
    privateEmail: 'owner@example.test',
    ...overrides,
  }
}

describe('compatibilidad determinística por proyecto', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    clearAuthSession()
  })

  it('separa puntaje y condiciones excluyentes, muestra frescura y no expone datos fuera del contrato', async () => {
    authenticate()
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/organizations')) return json([organization()])
      if (url.pathname.endsWith(`/organizations/${organizationId}/projects`)) return json([project()])
      if (url.pathname.endsWith(`/matching-runs/${matchingRunId}`)) return json(detail())
      if (url.pathname.endsWith('/matching-runs')) {
        return json({ items: [run()], totalCount: 1, pageNumber: 1, pageSize: 10 })
      }
      throw new Error(`Unexpected request: ${url}`)
    }))
    const router = createMemoryRouter(appRoutes, {
      initialEntries: [`/matching?projectId=${projectId}&runId=${matchingRunId}`],
    })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    expect(await screen.findByRole('heading', { name: 'Compatibilidad por proyecto' })).toBeInTheDocument()
    expect(await screen.findByRole('heading', { name: 'Fondo para agua rural' })).toBeInTheDocument()
    expect(screen.getByLabelText('Puntaje orientativo 42,5 de 100')).toBeInTheDocument()
    expect(screen.getByText('No aplica')).toBeInTheDocument()
    expect(screen.getByText('Desconocido no cuenta como aprobado.')).toBeInTheDocument()
    expect(screen.getByText('El proyecto no tiene territorio suficiente para evaluar esta condición.')).toBeInTheDocument()
    expect(screen.getAllByText('Condición excluyente')).toHaveLength(2)
    expect(screen.getByText('Advertencia')).toBeInTheDocument()
    expect(screen.getByText('Contiene versiones anteriores')).toBeInTheDocument()
    expect(screen.getAllByText(/Comparación acotada/).length).toBeGreaterThan(0)
    expect(screen.getByText(/Catálogo considerado al/)).toBeInTheDocument()
    expect(screen.getByText(/no confirma elegibilidad/)).toBeInTheDocument()
    expect(screen.getByText(/Cierre publicado:/)).toBeInTheDocument()
    expect(screen.getByText('Convocatoria continua')).toBeInTheDocument()
    expect(screen.queryByText('private@example.test')).not.toBeInTheDocument()
    expect(screen.queryByText('Texto privado de las bases')).not.toBeInTheDocument()
    expect(screen.queryByText('owner@example.test')).not.toBeInTheDocument()
  })

  it('muestra la hora UTC cuando las bases publican un cierre exacto', async () => {
    authenticate()
    const exactDeadline = detail() as unknown as MatchingRunDetail
    exactDeadline.items = [{
      ...exactDeadline.items[0],
      fundingOpportunity: {
        ...exactDeadline.items[0].fundingOpportunity,
        closeAtUtc: '2027-02-15T21:30:00Z',
        deadlinePrecision: 2,
      },
    }]
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/organizations')) return json([organization()])
      if (url.pathname.endsWith(`/organizations/${organizationId}/projects`)) return json([project()])
      if (url.pathname.endsWith(`/matching-runs/${matchingRunId}`)) return json(exactDeadline)
      if (url.pathname.endsWith('/matching-runs')) {
        return json({ items: [run()], totalCount: 1, pageNumber: 1, pageSize: 10 })
      }
      throw new Error(`Unexpected request: ${url}`)
    }))
    const router = createMemoryRouter(appRoutes, {
      initialEntries: [`/matching?projectId=${projectId}&runId=${matchingRunId}`],
    })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    expect(await screen.findByText(/Cierre exacto:.*21:30.*UTC/)).toBeInTheDocument()
  })

  it('reintenta una respuesta incierta con la misma clave idempotente y luego muestra el resultado', async () => {
    authenticate()
    let created = false
    let postCalls = 0
    const idempotencyKeys: string[] = []
    const currentRun = run({
      candidateCount: 1,
      totalCandidateCount: 1,
      isTruncated: false,
      isCurrent: true,
      compatibleCount: 0,
      incompatibleCount: 0,
      insufficientDataCount: 1,
    })
    const currentDetail = detail({ run: currentRun, items: [] })
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/organizations')) return json([organization()])
      if (url.pathname.endsWith(`/organizations/${organizationId}/projects`)) return json([project()])
      if (url.pathname.endsWith('/matching-runs') && init?.method === 'POST') {
        postCalls += 1
        idempotencyKeys.push(new Headers(init.headers).get('Idempotency-Key') ?? '')
        if (postCalls === 1) {
          return json({ title: 'Servicio temporalmente no disponible', status: 503, detail: 'No sabemos si el servidor alcanzó a completar el cálculo.' }, 503)
        }
        created = true
        return json({ run: currentDetail, wasReplay: false }, 201)
      }
      if (url.pathname.endsWith(`/matching-runs/${matchingRunId}`)) return json(currentDetail)
      if (url.pathname.endsWith('/matching-runs')) {
        return json({ items: created ? [currentRun] : [], totalCount: created ? 1 : 0, pageNumber: 1, pageSize: 10 })
      }
      throw new Error(`Unexpected request: ${url}`)
    }))
    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/matching'] })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    await user.selectOptions(await screen.findByLabelText(/Proyecto a comparar/), projectId)
    expect(await screen.findByRole('heading', { name: 'Aún no hay cálculos para este proyecto' })).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Calcular compatibilidad' }))
    expect(await screen.findByRole('heading', { name: 'No pudimos completar el cálculo' })).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Reintentar cálculo' }))

    expect(await screen.findByText('El cálculo terminó correctamente.')).toBeInTheDocument()
    expect(await screen.findByRole('heading', { name: 'No hubo fondos para comparar' })).toBeInTheDocument()
    await waitFor(() => expect(postCalls).toBe(2))
    expect(idempotencyKeys[0]).toMatch(/^[0-9a-f-]{36}$/i)
    expect(idempotencyKeys[1]).toBe(idempotencyKeys[0])
  })

  it('mantiene la ruta anterior como redirección segura', async () => {
    authenticate()
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/organizations')) return json([organization()])
      if (url.pathname.endsWith(`/organizations/${organizationId}/projects`)) return json([project()])
      throw new Error(`Unexpected request: ${url}`)
    }))
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/recommended'] })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    expect(await screen.findByRole('heading', { name: 'Compatibilidad por proyecto' })).toBeInTheDocument()
    expect(router.state.location.pathname).toBe('/matching')
  })

  it('conserva accesible el historial de un proyecto archivado sin permitir recalcular', async () => {
    authenticate()
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/organizations')) return json([organization()])
      if (url.pathname.endsWith(`/organizations/${organizationId}/projects`)) {
        return json([project({ publicationStatus: 4 })])
      }
      if (url.pathname.endsWith(`/matching-runs/${matchingRunId}`)) return json(detail())
      if (url.pathname.endsWith('/matching-runs')) {
        return json({ items: [run({ isCurrent: false })], totalCount: 1, pageNumber: 1, pageSize: 10 })
      }
      throw new Error(`Unexpected request: ${url}`)
    }))
    const router = createMemoryRouter(appRoutes, {
      initialEntries: [`/matching?projectId=${projectId}&runId=${matchingRunId}`],
    })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    expect(await screen.findByRole('heading', { name: 'Fondo para agua rural' })).toBeInTheDocument()
    expect(screen.getByRole('option', { name: 'Agua segura (Archivado)' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Calcular versión actual' })).toBeDisabled()
    expect(screen.getByText(/Proyecto archivado: puedes consultar su historial/)).toBeInTheDocument()
  })
})
