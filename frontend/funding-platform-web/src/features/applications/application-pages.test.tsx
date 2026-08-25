import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter } from 'react-router-dom'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { clearAuthSession, setAuthenticatedSession } from '@/features/auth/auth-session'
import { appRoutes } from '@/router'

const organizationId = '51ea2f6f-b1af-4e09-856c-6dcbdcfc812f'
const projectId = 'bd351806-9139-4524-bc01-93c3676729cb'
const opportunityId = 'f5b75d2c-4c84-4ca3-91f7-e9c182fdff2c'
const applicationId = 'f4299117-a4b5-4dfc-b89f-1a3942268f12'

function json(value: unknown, status = 200) {
  return Promise.resolve(new Response(JSON.stringify(value), {
    status,
    statusText: status === 412 ? 'Precondition Failed' : undefined,
    headers: { 'Content-Type': 'application/json' },
  }))
}

function authenticate() {
  setAuthenticatedSession({
    status: 'authenticated',
    accessToken: 'applications-test-token',
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
  return { publicId: organizationId, name: 'Fundación Demo', membershipRole: 'admin', profileStatus: 2, profileCompleteness: 100, profileVersion: 2, updatedAtUtc: '2026-08-24T10:00:00Z' }
}

function project(overrides: Record<string, unknown> = {}) {
  return { publicId: projectId, slug: 'agua-segura', title: 'Agua segura', summary: 'Resumen', status: 2, publicationStatus: 2, startDate: null, endDate: null, budgetTotal: 100000, confirmedFunding: 25000, currency: 'USD', fundingGap: 75000, projectVersion: 2, updatedAtUtc: '2026-08-24T10:00:00Z', ...overrides }
}

function opportunity() {
  return { publicId: opportunityId, slug: 'fondo-agua', title: 'Fondo para agua rural', summary: 'Resumen', sponsorName: 'Fundación Global', primaryFunderName: 'Fundación Global', primaryFunderPublicId: '3e36e5f3-9150-4bfd-82ea-4b8b9f96063f', currency: 'USD', minimumAmount: 10000, maximumAmount: 50000, openDate: '2026-08-01', closeDate: '2027-02-15', closeAtUtc: null, deadlineType: 1, deadlinePrecision: 1, publishedAtUtc: '2026-08-20T10:00:00Z', dataQualityScore: 94, sourceName: 'Portal oficial', sourceUrl: 'https://example.test', isFavorite: false }
}

function catalogs() {
  return { countries: [], regions: [], currencies: [{ code: 'USD', name: 'Dólar estadounidense', minorUnits: 2 }], fundingCategories: [], fundingTypes: [], organizationTypes: [], legalEntityTypes: [], organizationSizes: [], beneficiaryTypes: [], projectTypes: [], tags: [], languages: [] }
}

function application(overrides: Record<string, unknown> = {}) {
  return {
    publicId: applicationId,
    project: { publicId: projectId, slug: 'agua-segura', title: 'Agua segura' },
    fundingOpportunity: { publicId: opportunityId, slug: 'fondo-agua', title: 'Fondo para agua rural', sponsorName: 'Fundación Global', closeDate: '2027-02-15', closeAtUtc: null, deadlinePrecision: 1 },
    status: 0,
    notes: null,
    applicationDate: null,
    requestedAmount: null,
    currency: null,
    resultDate: null,
    ownerUserPublicId: '89b8d22a-472c-42e4-b034-c772ce3bb08e',
    canEdit: true,
    createdAtUtc: '2026-08-24T10:00:00Z',
    updatedAtUtc: '2026-08-24T10:00:00Z',
    eTag: '"0000000000000001"',
    ...overrides,
  }
}

describe('postulaciones de la organización', () => {
  afterEach(() => { vi.unstubAllGlobals(); clearAuthSession() })

  it('exige proyecto, crea con idempotencia y muestra confirmación visible', async () => {
    authenticate()
    let created = false
    const idempotencyKeys: string[] = []
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/organizations')) return json([organization()])
      if (url.pathname.endsWith(`/organizations/${organizationId}/projects`)) return json([
        project(),
        project({ publicId: '62c0d893-3c59-49b3-8d7b-4c330f531441', title: 'Proyecto archivado', publicationStatus: 4 }),
      ])
      if (url.pathname.endsWith('/catalogs')) return json(catalogs())
      if (url.pathname.endsWith(`/organizations/${organizationId}/funding-opportunities`)) return json({ items: [opportunity()], totalCount: 1, pageNumber: 1, pageSize: 50, searchMode: 'filtered' })
      if (url.pathname.endsWith(`/organizations/${organizationId}/applications/${applicationId}`)) return json(application())
      if (url.pathname.endsWith(`/organizations/${organizationId}/applications`) && init?.method === 'POST') {
        idempotencyKeys.push(new Headers(init.headers).get('Idempotency-Key') ?? '')
        expect(idempotencyKeys.at(-1)).toMatch(/^[0-9a-f-]{36}$/i)
        const body = JSON.parse(String(init.body))
        expect(body).toMatchObject({
          projectId,
          fundingOpportunityId: opportunityId,
          notes: null,
          applicationDate: null,
        })
        expect(body).not.toHaveProperty('status')
        if (idempotencyKeys.length === 1) {
          return json({ title: 'Respuesta incierta', status: 503, detail: 'No sabemos si el servidor alcanzó a procesar la solicitud.' }, 503)
        }
        created = true
        return json(application(), 201)
      }
      if (url.pathname.endsWith(`/organizations/${organizationId}/applications`)) {
        expect(url.searchParams.has('status')).toBe(false)
        return json({ items: created ? [application()] : [], totalCount: created ? 1 : 0, pageNumber: 1, pageSize: 12 })
      }
      throw new Error(`Unexpected request: ${url}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: [`/applications?new=1&fundingOpportunityId=${opportunityId}`] })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    expect(await screen.findByRole('heading', { name: 'Vincula un proyecto con un fondo' })).toBeInTheDocument()
    const submit = screen.getByRole('button', { name: 'Iniciar postulación' })
    expect(submit).toBeDisabled()
    await waitFor(() => expect(screen.getByLabelText('Proyecto para postular')).toContainHTML('Agua segura'))
    expect(screen.getByLabelText('Proyecto para postular')).not.toContainHTML('Proyecto archivado')
    await user.selectOptions(screen.getByLabelText('Proyecto para postular'), projectId)
    expect(submit).toBeEnabled()
    await user.click(submit)
    expect(await screen.findByText(/No sabemos si el servidor/)).toBeInTheDocument()
    await user.click(submit)

    expect(await screen.findByText(/Postulación iniciada con éxito/)).toBeInTheDocument()
    expect(created).toBe(true)
    expect(idempotencyKeys).toHaveLength(2)
    expect(idempotencyKeys[1]).toBe(idempotencyKeys[0])
  })

  it('envía filtros por URL y recupera de forma segura un conflicto If-Match', async () => {
    authenticate()
    let detailReads = 0
    let patchCalls = 0
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/organizations')) return json([organization()])
      if (url.pathname.endsWith(`/organizations/${organizationId}/projects`)) return json([project()])
      if (url.pathname.endsWith('/catalogs')) return json(catalogs())
      if (url.pathname.endsWith(`/organizations/${organizationId}/applications/${applicationId}`) && init?.method === 'PATCH') {
        patchCalls += 1
        expect(new Headers(init.headers).get('If-Match')).toBe('"0000000000000001"')
        return json({ title: 'El contenido cambió', status: 412, detail: 'La postulación fue modificada por otra persona.' }, 412)
      }
      if (url.pathname.endsWith(`/organizations/${organizationId}/applications/${applicationId}`)) {
        detailReads += 1
        return json(application(detailReads > 1 ? { status: 1, notes: 'Versión actualizada', eTag: '"0000000000000002"' } : {}))
      }
      if (url.pathname.endsWith(`/organizations/${organizationId}/applications`)) {
        expect(url.searchParams.get('status')).toBe('0')
        expect(url.searchParams.get('projectId')).toBe(projectId)
        return json({ items: [application()], totalCount: 1, pageNumber: 1, pageSize: 12 })
      }
      throw new Error(`Unexpected request: ${url}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: [`/applications?status=0&projectId=${projectId}`] })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    await user.click(await screen.findByRole('button', { name: 'Ver y editar' }))
    expect((await screen.findAllByRole('heading', { name: 'Fondo para agua rural' })).length).toBeGreaterThan(1)
    await user.selectOptions(screen.getByLabelText('Estado de la postulación'), '1')
    await user.click(screen.getByRole('button', { name: 'Guardar cambios' }))

    expect(await screen.findByText(/Otra persona actualizó esta postulación/)).toBeInTheDocument()
    await waitFor(() => expect(detailReads).toBe(2))
    expect(screen.getByLabelText('Estado de la postulación')).toHaveValue('1')
    expect(screen.getByLabelText('Notas de la postulación')).toHaveValue('Versión actualizada')
    expect(patchCalls).toBe(1)
  })
})
