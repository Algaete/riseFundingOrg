import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter } from 'react-router-dom'
import { vi } from 'vitest'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { setAuthenticatedSession } from '@/features/auth/auth-session'
import { appRoutes } from '@/router'

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': status >= 400 ? 'application/problem+json' : 'application/json' },
  })
}

function setAdminSession() {
  setAuthenticatedSession({
    status: 'authenticated',
    accessToken: 'admin-access-token',
    accessTokenExpiresAtUtc: '2099-08-21T12:10:00Z',
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

const catalogs = {
  countries: [{ id: 152, code: 'CL', name: 'Chile' }],
  regions: [{ id: 13_101, countryId: 152, code: 'CL-RM', name: 'Región Metropolitana' }],
  currencies: [{ code: 'USD', name: 'Dólar', minorUnits: 2 }],
  fundingCategories: [{ id: 1, code: 'HEALTH', name: 'Salud' }],
  fundingTypes: [{ id: 1, code: 'MATCHED_GRANT', name: 'Subvención con aporte' }],
  organizationTypes: [], legalEntityTypes: [], organizationSizes: [],
  beneficiaryTypes: [{ id: 2, code: 'CHILDREN', name: 'Niñez' }],
  projectTypes: [{ id: 3, code: 'TRAINING', name: 'Capacitación' }],
  tags: [], languages: [],
}

function opportunity(overrides: Record<string, unknown> = {}) {
  return {
    opportunityId: '04b6d64c-3495-45af-9c73-a4ce4202dbb6',
    slug: 'salud-comunitaria',
    title: 'Fondo de salud comunitaria',
    summary: 'Fortalece iniciativas locales.',
    description: 'Descripción completa del fondo.',
    sponsorName: 'Fundación Salud', sponsorUrl: 'https://foundation.example', applicationUrl: 'https://foundation.example/postular',
    externalId: 'FS-2026', fundingSourceId: 7, issuerCountryId: 152, fundingTypeId: 1,
    currency: 'USD', minimumAmount: 1000, maximumAmount: 5000,
    amountStatus: 1,
    openDate: '2026-08-01', closeDate: '2027-01-31',
    closeAtUtc: '2027-02-01T02:59:59.123Z', deadlineTimeZoneId: 'America/Santiago',
    deadlineType: 1, deadlinePrecision: 2,
    eligibilityDescription: 'ONG vigentes', requirements: 'Estatutos', objectives: 'Salud',
    allowedActivities: 'Talleres comunitarios', excludedActivities: 'Propaganda partidista',
    restrictions: 'Sin fines de lucro', targetOrganizationsDescription: 'ONG locales con personalidad jurídica',
    targetPopulationsDescription: 'Niñas y niños de comunidades rurales', minimumOperatingYears: 3,
    requiresLegalEntity: true, requiresPriorExperience: false, requiresCofunding: true,
    cofundingPercentage: 25, geographicScope: 1, remoteApplication: 2,
    sourceName: 'Manual editorial',
    sourceUrl: 'https://foundation.example/fondo', publishedAtUtc: null,
    lastVerifiedAtUtc: '2026-08-20T12:00:00.123Z', dataQualityScore: 90,
    publicationStatus: 1, contentVersion: 3, updatedAtUtc: '2026-08-20T12:00:00Z',
    eTag: '"0000000000000003"',
    funders: [{ funderId: '8fa6c73a-af02-4182-8b60-5bcef027ec5c', slug: 'fundacion-salud', name: 'Fundación Salud', role: 1 }],
    countryIds: [152], regionIds: [13_101], categoryIds: [1], beneficiaryTypeIds: [2], projectTypeIds: [3],
    evidence: [],
    sources: [{
      fundingSourceId: 7, sourceName: 'Manual editorial', externalId: 'FS-2026',
      sourceUrl: 'https://foundation.example/fondo', firstSeenAtUtc: '2026-08-01T10:00:00Z',
      lastSeenAtUtc: '2026-08-20T12:00:00Z', isPrimary: true, isActive: true,
    }],
    isActive: true, createdAtUtc: '2026-08-01T10:00:00Z',
    submittedAtUtc: '2026-08-20T12:00:00Z', reviewedAtUtc: null, reviewedByUserId: null,
    rejectionReason: null,
    ...overrides,
  }
}

function funder(overrides: Record<string, unknown> = {}) {
  return {
    funderId: '8fa6c73a-af02-4182-8b60-5bcef027ec5c',
    slug: 'fundacion-salud',
    name: 'Fundación Salud',
    description: null,
    websiteUrl: 'https://foundation.example',
    countryId: 152,
    countryCode: 'CL',
    countryName: 'Chile',
    publicationStatus: 2,
    isActive: true,
    contentVersion: 1,
    createdAtUtc: '2026-08-01T10:00:00Z',
    updatedAtUtc: '2026-08-20T12:00:00Z',
    eTag: '"0000000000000001"',
    aliases: ['Fundación Salud'],
    submittedAtUtc: '2026-08-19T12:00:00Z',
    reviewedAtUtc: '2026-08-20T12:00:00Z',
    reviewedByUserId: '89b8d22a-472c-42e4-b034-c772ce3bb08e',
    publishedAtUtc: '2026-08-20T12:00:00Z',
    rejectionReason: null,
    opportunities: [],
    ...overrides,
  }
}

function supportingResponse(url: string) {
  if (url.endsWith('/catalogs')) return json(catalogs)
  if (url.endsWith('/admin/funders/8fa6c73a-af02-4182-8b60-5bcef027ec5c')) return json(funder())
  if (url.includes('/admin/funders?')) return json({
    items: [funder()],
    totalCount: 1, page: 1, pageSize: 100,
  })
  if (url.endsWith('/admin/funding-sources')) return json([{ id: 7, name: 'Manual editorial', providerType: 0, baseUrl: null, isEnabled: true }])
  return null
}

describe('administración editorial de fondos', () => {
  beforeEach(setAdminSession)
  afterEach(() => vi.unstubAllGlobals())

  it('guarda categorías de un borrador importado sin exigir publicación ni inventar alcance', async () => {
    let current = opportunity({
      publicationStatus: 0, geographicScope: 0, countryIds: [], regionIds: [], categoryIds: [],
      issuerCountryId: null, sponsorUrl: null, requiresCofunding: false, cofundingPercentage: null,
      requiresLegalEntity: null, requiresPriorExperience: null, minimumOperatingYears: null,
      closeAtUtc: null, deadlineTimeZoneId: null, deadlinePrecision: 1,
    })
    const writes: unknown[] = []
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input)
      const support = supportingResponse(url)
      if (support) return Promise.resolve(support)
      if (url.endsWith(`/admin/funding-opportunities/${current.opportunityId}`)) {
        if (init?.method === 'PUT') {
          const payload = JSON.parse(String(init.body))
          writes.push(payload)
          current = opportunity({ ...current, ...payload, contentVersion: 4, eTag: '"0000000000000004"' })
          return Promise.resolve(json({ entityId: current.opportunityId, publicationStatus: 0, contentVersion: 4, eTag: current.eTag, wasReplay: false }))
        }
        return Promise.resolve(json(current))
      }
      return Promise.resolve(json({ title: 'Unexpected request', status: 404 }, 404))
    }))
    const user = userEvent.setup()
    render(<App router={createMemoryRouter(appRoutes, { initialEntries: [`/admin/funding/${current.opportunityId}`] })} queryClient={createAppQueryClient()} />)

    await user.click(await screen.findByRole('checkbox', { name: 'Salud' }))
    await user.click(screen.getByRole('button', { name: 'Guardar cambios' }))
    expect(await screen.findByText('Cambios guardados correctamente.')).toBeInTheDocument()
    expect(writes).toHaveLength(1)
    expect(writes[0]).toMatchObject({ categoryIds: [1], geographicScope: 0, countryIds: [], issuerCountryId: null })
    expect(screen.getByRole('checkbox', { name: 'Salud' })).toBeChecked()
    expect(screen.getByRole('button', { name: 'Guardar cambios' })).toBeDisabled()
  })

  it('explica junto a Guardar los errores anidados del financiador y enfoca el resumen', async () => {
    const current = opportunity({
      publicationStatus: 0, categoryIds: [],
      funders: [{ funderId: 'invalid-id', name: 'Financiador importado', role: 1 }],
    })
    let writes = 0
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      if (init?.method === 'PUT' || init?.method === 'POST') writes += 1
      const url = String(input)
      const support = supportingResponse(url)
      if (support) return Promise.resolve(support)
      if (url.endsWith(`/admin/funding-opportunities/${current.opportunityId}`)) return Promise.resolve(json(current))
      return Promise.resolve(json({ title: 'Not found', status: 404 }, 404))
    }))
    const user = userEvent.setup()
    render(<App router={createMemoryRouter(appRoutes, { initialEntries: [`/admin/funding/${current.opportunityId}`] })} queryClient={createAppQueryClient()} />)

    await user.click(await screen.findByRole('checkbox', { name: 'Salud' }))
    await user.click(screen.getByRole('button', { name: 'Guardar cambios' }))
    const summary = await screen.findByRole('alert', { name: 'No se guardaron los cambios. Revisa estos campos:' })
    expect(summary).toHaveFocus()
    expect(summary).toHaveTextContent('Financiadores asociados')
    expect(summary).not.toHaveTextContent('Invalid uuid')
    expect(writes).toBe(0)
    expect(screen.getByRole('checkbox', { name: 'Salud' })).toBeChecked()
    await user.click(within(summary).getByRole('button', { name: /Financiadores asociados/ }))
    expect(screen.getByLabelText('Buscar financiador')).toHaveFocus()
  })

  it('permite localizar y corregir un campo inválido sin perder las categorías elegidas', async () => {
    let current = opportunity({ publicationStatus: 0, categoryIds: [], summary: 'x'.repeat(2001) })
    let writes = 0
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input)
      const support = supportingResponse(url)
      if (support) return Promise.resolve(support)
      if (url.endsWith(`/admin/funding-opportunities/${current.opportunityId}`)) {
        if (init?.method === 'PUT') {
          writes += 1
          current = opportunity({ ...current, ...JSON.parse(String(init.body)), contentVersion: 4, eTag: '"0000000000000004"' })
          return Promise.resolve(json({ entityId: current.opportunityId, publicationStatus: 0, contentVersion: 4, eTag: current.eTag, wasReplay: false }))
        }
        return Promise.resolve(json(current))
      }
      return Promise.resolve(json({ title: 'Not found', status: 404 }, 404))
    }))
    const user = userEvent.setup()
    render(<App router={createMemoryRouter(appRoutes, { initialEntries: [`/admin/funding/${current.opportunityId}`] })} queryClient={createAppQueryClient()} />)

    await user.click(await screen.findByRole('checkbox', { name: 'Salud' }))
    await user.click(screen.getByRole('button', { name: 'Guardar cambios' }))
    const summary = await screen.findByRole('alert', { name: 'No se guardaron los cambios. Revisa estos campos:' })
    expect(writes).toBe(0)
    await user.click(within(summary).getByRole('button', { name: 'Resumen: Usa como máximo 2000 caracteres.' }))
    const field = screen.getByLabelText(/^Resumen/)
    expect(field).toHaveFocus()
    await user.clear(field)
    await user.type(field, 'Resumen corregido por la persona editora.')
    await user.click(screen.getByRole('button', { name: 'Guardar cambios' }))
    expect(await screen.findByText('Cambios guardados correctamente.')).toBeInTheDocument()
    expect(writes).toBe(1)
    expect(screen.queryByRole('alert', { name: 'No se guardaron los cambios. Revisa estos campos:' })).not.toBeInTheDocument()
    expect(screen.getByRole('checkbox', { name: 'Salud' })).toBeChecked()
  })

  it('publica una oportunidad pendiente usando ETag e Idempotency-Key', async () => {
    let current = opportunity()
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input)
      const support = supportingResponse(url)
      if (support) return Promise.resolve(support)
      if (url.endsWith('/admin/funding-opportunities/04b6d64c-3495-45af-9c73-a4ce4202dbb6/reviews')) {
        expect(init?.method).toBe('POST')
        expect(new Headers(init?.headers).get('If-Match')).toBe('"0000000000000003"')
        expect(new Headers(init?.headers).get('Idempotency-Key')).toMatch(/^[0-9a-f-]{36}$/i)
        expect(JSON.parse(String(init?.body))).toEqual({ decision: 'approve' })
        current = opportunity({ publicationStatus: 2, contentVersion: 4, eTag: '"0000000000000004"', publishedAtUtc: '2026-08-21T12:00:00Z' })
        return Promise.resolve(json({ entityId: current.opportunityId, publicationStatus: 2, contentVersion: 4, eTag: current.eTag, wasReplay: false }))
      }
      if (url.endsWith('/admin/funding-opportunities/04b6d64c-3495-45af-9c73-a4ce4202dbb6')) return Promise.resolve(json(current))
      return Promise.resolve(json({ title: 'Not found', status: 404 }, 404))
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/funding/04b6d64c-3495-45af-9c73-a4ce4202dbb6'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    expect(await screen.findByText('Este fondo está pendiente de revisión.')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Ir a revisar y publicar' })).toHaveAttribute('href', '#flujo-editorial')
    await user.click(await screen.findByRole('button', { name: 'Aprobar y publicar' }))
    expect(await screen.findByText('Este contenido está visible en el catálogo público.')).toBeInTheDocument()
  })

  it('destaca en el listado los fondos pendientes que se pueden publicar', async () => {
    const pending = opportunity()
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      const url = String(input)
      if (url.includes('/admin/funding-opportunities?')) {
        return Promise.resolve(json({
          items: [{
            opportunityId: pending.opportunityId,
            slug: pending.slug,
            title: pending.title,
            summary: pending.summary,
            sponsorName: pending.sponsorName,
            isActive: pending.isActive,
            currency: pending.currency,
            minimumAmount: pending.minimumAmount,
            maximumAmount: pending.maximumAmount,
            openDate: pending.openDate,
            closeDate: pending.closeDate,
            sourceName: pending.sourceName,
            sourceUrl: pending.sourceUrl,
            publishedAtUtc: pending.publishedAtUtc,
            lastVerifiedAtUtc: pending.lastVerifiedAtUtc,
            dataQualityScore: pending.dataQualityScore,
            publicationStatus: pending.publicationStatus,
            contentVersion: pending.contentVersion,
            updatedAtUtc: pending.updatedAtUtc,
            eTag: pending.eTag,
          }],
          totalCount: 1,
          page: 1,
          pageSize: 20,
        }))
      }
      return Promise.resolve(json({ title: 'Not found', status: 404 }, 404))
    }))
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/funding'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    expect(await screen.findByRole('link', { name: 'Revisar y publicar' })).toHaveAttribute(
      'href',
      `/admin/funding/${pending.opportunityId}`,
    )
  })

  it('envía ETag e idempotencia al editar y ofrece recargar ante conflicto', async () => {
    const current = opportunity({ publicationStatus: 0 })
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input)
      const support = supportingResponse(url)
      if (support) return Promise.resolve(support)
      if (url.endsWith('/admin/funding-opportunities/04b6d64c-3495-45af-9c73-a4ce4202dbb6') && init?.method === 'PUT') {
        expect(new Headers(init.headers).get('If-Match')).toBe('"0000000000000003"')
        expect(new Headers(init.headers).get('Idempotency-Key')).toBeTruthy()
        return Promise.resolve(json({
          type: 'https://fundingplatform.local/problems/funding-editorial-precondition-failed',
          title: 'La versión ya no está vigente', status: 412,
          detail: 'Otro administrador actualizó esta oportunidad.',
        }, 412))
      }
      if (url.endsWith('/admin/funding-opportunities/04b6d64c-3495-45af-9c73-a4ce4202dbb6')) return Promise.resolve(json(current))
      return Promise.resolve(json({ title: 'Not found', status: 404 }, 404))
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/funding/04b6d64c-3495-45af-9c73-a4ce4202dbb6'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    const title = await screen.findByLabelText('Título')
    expect(screen.getByRole('button', { name: 'Desactivar' })).toBeInTheDocument()
    await user.clear(title)
    await user.type(title, 'Fondo actualizado')
    await user.click(screen.getByRole('button', { name: 'Guardar cambios' }))

    expect(await screen.findByText('Otro administrador actualizó este contenido. Carga la versión vigente y revísala antes de volver a intentarlo.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Cargar versión vigente' })).toBeInTheDocument()
  })

  it('localiza el rechazo de readiness y guía hacia un financiador principal todavía en borrador', async () => {
    const current = opportunity({
      publicationStatus: 0,
      geographicScope: 0,
      countryIds: [],
      regionIds: [],
    })
    const draftFunder = funder({
      publicationStatus: 0,
      submittedAtUtc: null,
      reviewedAtUtc: null,
      reviewedByUserId: null,
      publishedAtUtc: null,
    })
    const fetchMock = vi.fn((input: RequestInfo | URL) => {
      const url = String(input)
      if (url.endsWith('/catalogs')) return Promise.resolve(json(catalogs))
      if (url.endsWith(`/admin/funders/${draftFunder.funderId}`)) {
        return Promise.resolve(json(draftFunder))
      }
      if (url.includes('/admin/funders?')) {
        return Promise.resolve(json({ items: [draftFunder], totalCount: 1, page: 1, pageSize: 20 }))
      }
      if (url.endsWith('/admin/funding-sources')) {
        return Promise.resolve(json([{ id: 7, name: 'Manual editorial', providerType: 0, baseUrl: null, isEnabled: true }]))
      }
      if (url.endsWith('/submit-review')) {
        return Promise.resolve(json({
          type: 'https://fundingplatform.local/problems/opportunity-not-ready',
          title: 'Oportunidad no está listo para revisión',
          status: 422,
          errors: {
            catalogs: ['Every catalog reference must be active and geography must remain consistent.'],
            funderLinks: ['A published primary funder is required.'],
            geographicScope: ['Unknown geographic scope cannot be published.'],
          },
        }, 422))
      }
      if (url.endsWith(`/admin/funding-opportunities/${current.opportunityId}`)) {
        return Promise.resolve(json(current))
      }
      return Promise.resolve(json({ title: 'Not found', status: 404 }, 404))
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, {
      initialEntries: [`/admin/funding/${current.opportunityId}`],
    })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    const funderReadiness = await screen.findByRole('link', { name: 'Financiador principal publicado' })
    expect(funderReadiness).toHaveAttribute('href', `/admin/funders/${draftFunder.funderId}`)
    await waitFor(() => expect(funderReadiness.closest('li')).toHaveTextContent('Borrador'))
    expect(screen.getByRole('button', { name: 'Enviar a revisión' })).toBeEnabled()
    expect(screen.getByRole('link', { name: 'Gestionar financiador Fundación Salud' })).toHaveAttribute(
      'href',
      `/admin/funders/${draftFunder.funderId}`,
    )

    await user.click(screen.getByRole('button', { name: 'Enviar a revisión' }))

    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent('Faltan datos para enviar esta oportunidad a revisión.')
    expect(alert).toHaveTextContent('Publica el financiador principal antes de enviar la oportunidad a revisión.')
    expect(alert).toHaveTextContent('Define el alcance geográfico como específico o global.')
    expect(alert).toHaveTextContent('Revisa la moneda, el tipo de financiamiento, el alcance, las categorías y el financiador principal. Alguna selección está inactiva o no es coherente.')
    expect(alert).not.toHaveTextContent('A published primary funder is required.')
    expect(alert).not.toHaveTextContent('Unknown geographic scope cannot be published.')
    expect(within(alert).getByRole('link', { name: 'Corregir financiador y alcance' })).toHaveAttribute(
      'href',
      '#financiadores-alcance',
    )
    expect(document.querySelector('#financiadores-alcance')).toBeInTheDocument()
  })

  it('muestra los campos concretos cuando la referencia de fuente está duplicada', async () => {
    const current = opportunity({ publicationStatus: 0 })
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input)
      const support = supportingResponse(url)
      if (support) return Promise.resolve(support)
      if (url.endsWith('/admin/funding-opportunities/04b6d64c-3495-45af-9c73-a4ce4202dbb6') && init?.method === 'PUT') {
        return Promise.resolve(json({
          type: 'https://fundingplatform.local/problems/source-link-conflict',
          title: 'La referencia de la fuente ya está vinculada',
          status: 409,
          errors: {
            fundingSourceId: ['La fuente seleccionada ya contiene otra oportunidad con la misma referencia de origen.'],
            externalId: ['El ID en la fuente debe identificar una única oportunidad.'],
            sourceUrl: ['Revisa que la URL oficial y el ID correspondan al mismo registro.'],
          },
        }, 409))
      }
      if (url.endsWith('/admin/funding-opportunities/04b6d64c-3495-45af-9c73-a4ce4202dbb6')) return Promise.resolve(json(current))
      return Promise.resolve(json({ title: 'Not found', status: 404 }, 404))
    }))
    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/funding/04b6d64c-3495-45af-9c73-a4ce4202dbb6'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    const title = await screen.findByLabelText('Título')
    await user.clear(title)
    await user.type(title, 'Fondo corregido')
    await user.click(screen.getByRole('button', { name: 'Guardar cambios' }))

    expect(await screen.findByText('La referencia de la fuente ya está vinculada')).toBeInTheDocument()
    expect(screen.getAllByText('El ID en la fuente debe identificar una única oportunidad.').length).toBeGreaterThan(0)
    expect(screen.getAllByText('Revisa que la URL oficial y el ID correspondan al mismo registro.').length).toBeGreaterThan(0)
  })

  it('preserva todos los campos canónicos de alcance global al editar únicamente el título', async () => {
    const current = opportunity({ publicationStatus: 0, geographicScope: 2, countryIds: [], regionIds: [] })
    let updateBody: unknown
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input)
      const support = supportingResponse(url)
      if (support) return Promise.resolve(support)
      if (url.endsWith('/admin/funding-opportunities/04b6d64c-3495-45af-9c73-a4ce4202dbb6') && init?.method === 'PUT') {
        updateBody = JSON.parse(String(init.body))
        return Promise.resolve(json({
          entityId: current.opportunityId,
          publicationStatus: 0,
          contentVersion: 4,
          eTag: '"0000000000000004"',
          wasReplay: false,
        }))
      }
      if (url.endsWith('/admin/funding-opportunities/04b6d64c-3495-45af-9c73-a4ce4202dbb6')) return Promise.resolve(json(current))
      return Promise.resolve(json({ title: 'Not found', status: 404 }, 404))
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/funding/04b6d64c-3495-45af-9c73-a4ce4202dbb6'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    const title = await screen.findByLabelText('Título')
    await user.clear(title)
    await user.type(title, 'Fondo de salud comunitaria actualizado')
    await user.click(screen.getByRole('button', { name: 'Guardar cambios' }))

    await waitFor(() => expect(updateBody).toEqual({
      title: 'Fondo de salud comunitaria actualizado',
      summary: 'Fortalece iniciativas locales.',
      description: 'Descripción completa del fondo.',
      sponsorName: 'Fundación Salud',
      sponsorUrl: 'https://foundation.example',
      applicationUrl: 'https://foundation.example/postular',
      externalId: 'FS-2026',
      fundingSourceId: 7,
      issuerCountryId: 152,
      fundingTypeId: 1,
      currency: 'USD',
      minimumAmount: 1000,
      maximumAmount: 5000,
      amountStatus: 1,
      openDate: '2026-08-01',
      closeDate: '2027-01-31',
      closeAtUtc: '2027-02-01T02:59:59.123Z',
      deadlineTimeZoneId: 'America/Santiago',
      deadlineType: 1,
      deadlinePrecision: 2,
      eligibilityDescription: 'ONG vigentes',
      requirements: 'Estatutos',
      objectives: 'Salud',
      allowedActivities: 'Talleres comunitarios',
      excludedActivities: 'Propaganda partidista',
      restrictions: 'Sin fines de lucro',
      targetOrganizationsDescription: 'ONG locales con personalidad jurídica',
      targetPopulationsDescription: 'Niñas y niños de comunidades rurales',
      minimumOperatingYears: 3,
      requiresLegalEntity: true,
      requiresPriorExperience: false,
      requiresCofunding: true,
      cofundingPercentage: 25,
      geographicScope: 2,
      remoteApplication: 2,
      sourceUrl: 'https://foundation.example/fondo',
      lastVerifiedAtUtc: '2026-08-20T12:00:00.123Z',
      funders: [{ funderId: '8fa6c73a-af02-4182-8b60-5bcef027ec5c', role: 1 }],
      countryIds: [],
      regionIds: [],
      categoryIds: [1],
      beneficiaryTypeIds: [2],
      projectTypeIds: [3],
    }))
    expect(await screen.findByText('Cambios guardados correctamente.')).toBeInTheDocument()
  })

  it('exige un país para el alcance geográfico específico', async () => {
    const current = opportunity({ publicationStatus: 0, geographicScope: 0, countryIds: [], regionIds: [] })
    let updateCalls = 0
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input)
      const support = supportingResponse(url)
      if (support) return Promise.resolve(support)
      if (url.endsWith('/admin/funding-opportunities/04b6d64c-3495-45af-9c73-a4ce4202dbb6') && init?.method === 'PUT') {
        updateCalls += 1
        return Promise.resolve(json({ title: 'Unexpected request', status: 500 }, 500))
      }
      if (url.endsWith('/admin/funding-opportunities/04b6d64c-3495-45af-9c73-a4ce4202dbb6')) return Promise.resolve(json(current))
      return Promise.resolve(json({ title: 'Not found', status: 404 }, 404))
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/funding/04b6d64c-3495-45af-9c73-a4ce4202dbb6'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    await user.selectOptions(await screen.findByLabelText('Alcance geográfico'), '1')
    await user.click(screen.getByRole('button', { name: 'Guardar cambios' }))

    expect(await screen.findByText('El alcance específico requiere al menos un país.')).toBeInTheDocument()
    expect(updateCalls).toBe(0)
  })

  it('bloquea una última verificación futura antes de llamar a la API', async () => {
    const current = opportunity({ publicationStatus: 0 })
    let updateCalls = 0
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input)
      const support = supportingResponse(url)
      if (support) return Promise.resolve(support)
      if (url.endsWith('/admin/funding-opportunities/04b6d64c-3495-45af-9c73-a4ce4202dbb6') && init?.method === 'PUT') {
        updateCalls += 1
        return Promise.resolve(json({ title: 'Unexpected request', status: 500 }, 500))
      }
      if (url.endsWith('/admin/funding-opportunities/04b6d64c-3495-45af-9c73-a4ce4202dbb6')) return Promise.resolve(json(current))
      return Promise.resolve(json({ title: 'Not found', status: 404 }, 404))
    }))
    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/funding/04b6d64c-3495-45af-9c73-a4ce4202dbb6'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    const verifiedAt = await screen.findByLabelText(/Última verificación/)
    fireEvent.change(verifiedAt, { target: { value: '2099-01-01T12:00' } })
    await user.click(screen.getByRole('button', { name: 'Guardar cambios' }))

    expect(await screen.findByText('La última verificación no puede estar en el futuro.')).toBeInTheDocument()
    expect(updateCalls).toBe(0)
    expect(screen.getByRole('button', { name: 'Usar hora actual' })).toBeInTheDocument()
  })

  it('rechaza una revisión con motivo, ETag e idempotencia', async () => {
    let current = opportunity()
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input)
      const support = supportingResponse(url)
      if (support) return Promise.resolve(support)
      if (url.endsWith('/admin/funding-opportunities/04b6d64c-3495-45af-9c73-a4ce4202dbb6/reviews')) {
        expect(new Headers(init?.headers).get('If-Match')).toBe('"0000000000000003"')
        expect(new Headers(init?.headers).get('Idempotency-Key')).toBeTruthy()
        expect(JSON.parse(String(init?.body))).toEqual({ decision: 'reject', reason: 'Falta confirmar las bases oficiales.' })
        current = opportunity({ publicationStatus: 3, contentVersion: 4, eTag: '"0000000000000004"', rejectionReason: 'Falta confirmar las bases oficiales.' })
        return Promise.resolve(json({ entityId: current.opportunityId, publicationStatus: 3, contentVersion: 4, eTag: current.eTag, wasReplay: false }))
      }
      if (url.endsWith('/admin/funding-opportunities/04b6d64c-3495-45af-9c73-a4ce4202dbb6')) return Promise.resolve(json(current))
      return Promise.resolve(json({ title: 'Not found', status: 404 }, 404))
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/funding/04b6d64c-3495-45af-9c73-a4ce4202dbb6'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    await user.type(await screen.findByLabelText('Motivo si rechazas'), 'Falta confirmar las bases oficiales.')
    await user.click(screen.getByRole('button', { name: 'Rechazar' }))
    expect(await screen.findByText(/Falta confirmar las bases oficiales/)).toBeInTheDocument()
  })

  it('retira temporalmente una publicación y la devuelve a borrador para corregirla', async () => {
    let current = opportunity({ publicationStatus: 2, publishedAtUtc: '2026-08-21T12:00:00Z' })
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input)
      const support = supportingResponse(url)
      if (support) return Promise.resolve(support)
      if (url.endsWith('/start-correction')) {
        expect(new Headers(init?.headers).get('If-Match')).toBe('"0000000000000003"')
        expect(new Headers(init?.headers).get('Idempotency-Key')).toMatch(/^[0-9a-f-]{36}$/i)
        expect(JSON.parse(String(init?.body))).toEqual({ reason: 'Corregir el dominio de postulación.' })
        current = opportunity({ publicationStatus: 0, contentVersion: 4, eTag: '"0000000000000004"' })
        return Promise.resolve(json({ entityId: current.opportunityId, publicationStatus: 0, contentVersion: 4, eTag: current.eTag, wasReplay: false }))
      }
      if (url.endsWith('/admin/funding-opportunities/04b6d64c-3495-45af-9c73-a4ce4202dbb6')) return Promise.resolve(json(current))
      return Promise.resolve(json({ title: 'Not found', status: 404 }, 404))
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/funding/04b6d64c-3495-45af-9c73-a4ce4202dbb6'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    await user.click(await screen.findByRole('button', { name: 'Corregir publicación' }))
    expect(screen.getByRole('dialog', { name: 'Iniciar corrección editorial' })).toHaveTextContent('se retirará temporalmente')
    await user.type(screen.getByRole('textbox', { name: /Motivo de la corrección/ }), 'Corregir el dominio de postulación.')
    await user.click(screen.getByRole('button', { name: 'Retirar e iniciar corrección' }))

    expect(await screen.findByText(/envía la oportunidad a revisión/i)).toBeInTheDocument()
  })

  it('avisa cuando una oportunidad publicada está oculta por categoría y geografía faltantes', async () => {
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      const url = String(input)
      const support = supportingResponse(url)
      if (support) return Promise.resolve(support)
      if (url.endsWith('/admin/funding-opportunities/04b6d64c-3495-45af-9c73-a4ce4202dbb6')) {
        return Promise.resolve(json(opportunity({
          publicationStatus: 2,
          publishedAtUtc: '2026-08-21T12:00:00Z',
          categoryIds: [],
          geographicScope: 0,
          countryIds: [],
          regionIds: [],
        })))
      }
      return Promise.resolve(json({ title: 'Not found', status: 404 }, 404))
    }))
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/funding/04b6d64c-3495-45af-9c73-a4ce4202dbb6'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    expect(await screen.findByRole('alert')).toHaveTextContent('Publicado, pero oculto del catálogo')
    expect(screen.getByRole('alert')).toHaveTextContent('Selecciona al menos un área o categoría')
    expect(screen.getByRole('alert')).toHaveTextContent('Define el alcance geográfico')
    expect(screen.queryByRole('link', { name: 'Ver público' })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Corregir publicación' })).toBeInTheDocument()
  })

  it('usa tipos de financiamiento del catálogo y alerta cuando los dominios difieren', async () => {
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      const url = String(input)
      const support = supportingResponse(url)
      if (support) return Promise.resolve(support)
      if (url.endsWith('/admin/funding-opportunities/04b6d64c-3495-45af-9c73-a4ce4202dbb6')) {
        return Promise.resolve(json(opportunity({ applicationUrl: 'https://postulaciones.example.net/formulario' })))
      }
      return Promise.resolve(json({ title: 'Not found', status: 404 }, 404))
    }))
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/funding/04b6d64c-3495-45af-9c73-a4ce4202dbb6'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    expect(await screen.findByRole('option', { name: 'Subvención con aporte' })).toBeInTheDocument()
    expect(screen.getByRole('alert')).toHaveTextContent('postulaciones.example.net')
    expect(screen.getByRole('alert')).toHaveTextContent('foundation.example')
  })

  it('busca funders en el servidor sin limitar el selector a la primera página', async () => {
    const remoteFunderId = '1375dfde-6504-44a2-a412-f5d7e73cb035'
    const fetchMock = vi.fn((input: RequestInfo | URL) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/catalogs')) return Promise.resolve(json(catalogs))
      if (url.pathname.endsWith('/admin/funding-sources')) return Promise.resolve(json([{ id: 7, name: 'Manual editorial', providerType: 0, baseUrl: null, isEnabled: true }]))
      if (url.pathname.endsWith('/admin/funders')) {
        const query = url.searchParams.get('query')
        return Promise.resolve(json({
          items: query === 'Fondo Remoto' ? [{
            funderId: remoteFunderId, slug: 'fondo-remoto', name: 'Fondo Remoto',
            description: null, websiteUrl: null, countryId: 152, publicationStatus: 2,
            contentVersion: 1, updatedAtUtc: '2026-08-20T12:00:00Z', eTag: '"0000000000000001"',
          }] : [],
          totalCount: query === 'Fondo Remoto' ? 1 : 125,
          page: Number(url.searchParams.get('page') ?? 1),
          pageSize: Number(url.searchParams.get('pageSize') ?? 20),
        }))
      }
      if (url.pathname.endsWith('/admin/funding-opportunities/04b6d64c-3495-45af-9c73-a4ce4202dbb6')) return Promise.resolve(json(opportunity({ publicationStatus: 0 })))
      return Promise.resolve(json({ title: 'Not found', status: 404 }, 404))
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/funding/04b6d64c-3495-45af-9c73-a4ce4202dbb6'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    await user.type(await screen.findByLabelText('Buscar financiador'), 'Fondo Remoto')
    const remoteChoice = await screen.findByRole('checkbox', { name: /Fondo Remoto/ })
    await user.click(remoteChoice)

    expect(remoteChoice).toBeChecked()
    expect(fetchMock.mock.calls.some(([input]) => new URL(String(input), 'http://localhost').searchParams.get('query') === 'Fondo Remoto')).toBe(true)
  })

  it('crea un financiador con clave idempotente y navega a su ficha', async () => {
    const createdId = '39e6830e-87c9-499d-a7b6-14b7b2c3b82e'
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input)
      if (url.endsWith('/catalogs')) return Promise.resolve(json(catalogs))
      if (url.endsWith('/admin/funders') && init?.method === 'POST') {
        expect(new Headers(init.headers).get('Idempotency-Key')).toBeTruthy()
        expect(JSON.parse(String(init.body))).toMatchObject({ name: 'Fondo Solidario', aliases: ['FS', 'Solidario'] })
        return Promise.resolve(json({ entityId: createdId, publicationStatus: 0, contentVersion: 1, eTag: '"0000000000000001"', wasReplay: false }))
      }
      if (url.endsWith(`/admin/funders/${createdId}`)) return Promise.resolve(json({
        funderId: createdId, slug: 'fondo-solidario', name: 'Fondo Solidario', description: null,
        websiteUrl: null, countryId: null, aliases: ['FS', 'Solidario'], publicationStatus: 0,
        contentVersion: 1, updatedAtUtc: '2026-08-21T12:00:00Z', eTag: '"0000000000000001"',
        submittedAtUtc: null, reviewedAtUtc: null, reviewedByUserId: null, publishedAtUtc: null, rejectionReason: null,
      }))
      return Promise.resolve(json({ title: 'Not found', status: 404 }, 404))
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin/funders/new'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    await user.type(await screen.findByLabelText('Nombre'), 'Fondo Solidario')
    await user.type(screen.getByLabelText('Alias conocidos'), 'FS\nSolidario')
    await user.click(screen.getByRole('button', { name: 'Crear financiador' }))

    await waitFor(() => expect(router.state.location.pathname).toBe(`/admin/funders/${createdId}`))
    expect(await screen.findByRole('heading', { name: 'Fondo Solidario', level: 1 })).toBeInTheDocument()
  })
})
