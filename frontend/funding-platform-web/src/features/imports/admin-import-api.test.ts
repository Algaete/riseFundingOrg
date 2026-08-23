import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { setAuthenticatedSession } from '@/features/auth/auth-session'
import {
  adminImportApi,
  mapFundingSource,
  mapImportDedupeComparison,
  mapImportRunDetail,
  shouldPollImportRuns,
} from '@/features/imports/admin-import-api'

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
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

describe('contrato HTTP de importaciones', () => {
  beforeEach(() => {
    authenticateAdmin()
    sessionStorage.clear()
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
    sessionStorage.clear()
  })

  it('crea una ejecución con body mínimo, Bearer e Idempotency-Key', async () => {
    const fetchMock = vi.fn().mockResolvedValue(json({
      runId: '9c50f0c1-1622-47e1-94f1-68ecf262db83',
      fundingSourceId: 12,
      sourceName: 'Grants.gov',
      status: 0,
      createdAtUtc: '2026-08-22T12:00:00Z',
      wasReplay: false,
      statusUrl: '/api/v1/admin/import-runs/9c50f0c1-1622-47e1-94f1-68ecf262db83',
    }, 202))
    vi.stubGlobal('fetch', fetchMock)

    const result = await adminImportApi.create(
      12,
      { keyword: 'climate resilience', maximumResults: 25 },
      '0207075b-ff57-4daa-90a3-bb42f2a15891',
    )

    expect(result.status).toBe('queued')
    expect(fetchMock).toHaveBeenCalledOnce()
    const [url, options] = fetchMock.mock.calls[0] as [string, RequestInit]
    const headers = new Headers(options.headers)
    expect(url).toBe('/api/v1/admin/funding-sources/12/import-runs')
    expect(options.method).toBe('POST')
    expect(options.cache).toBe('no-store')
    expect(JSON.parse(String(options.body))).toEqual({
      keyword: 'climate resilience',
      maximumResults: 25,
    })
    expect(headers.get('Idempotency-Key')).toBe('0207075b-ff57-4daa-90a3-bb42f2a15891')
    expect(headers.get('Authorization')).toBe('Bearer admin-access-token')
    expect(headers.get('Content-Type')).toBe('application/json')
  })

  it('envía filtros tipados y fuerza no-store al listar', async () => {
    const fetchMock = vi.fn().mockResolvedValue(json({ items: [], totalCount: 0, page: 2, pageSize: 20 }))
    vi.stubGlobal('fetch', fetchMock)

    await adminImportApi.list({ sourceId: 12, status: 1, page: 2, pageSize: 20 })

    const [url, options] = fetchMock.mock.calls[0] as [string, RequestInit]
    expect(url).toBe('/api/v1/admin/import-runs?page=2&pageSize=20&sourceId=12&status=1')
    expect(options.cache).toBe('no-store')
  })

  it('adapta aliases de fuente sin exponer configuración o secretos', () => {
    const source = mapFundingSource({
      sourceId: 12,
      sourceName: 'Grants.gov',
      providerType: 1,
      providerCode: 'grants.gov',
      baseUrl: 'https://api.grants.gov/v1?sig=never-display',
      enabled: true,
      status: 'Healthy',
      compliance: 'approved',
      lastSuccessAtUtc: '2026-08-22T11:00:00Z',
      nextRunAtUtc: '2026-08-22T13:00:00Z',
      licenseName: 'Public Domain',
      licenseUrl: 'https://grants.gov/legal/terms?sig=never-display',
      licenseStatus: 'approved',
      isAllowlisted: true,
      acquisitionReady: true,
      maxRequestsPerMinute: 60,
      robotsPolicyStatus: 'Permitido',
      robotsCheckedAtUtc: '2026-08-21T10:00:00Z',
      rssFeedUrl: 'https://grants.gov/rss/opportunities.xml?token=never-display',
      configJson: '{"clientSecret":"hidden"}',
      secretReference: 'vault-secret-name',
    })

    expect(source).toMatchObject({
      id: 12,
      name: 'Grants.gov',
      providerCode: 'grants-gov',
      baseUrl: 'https://api.grants.gov',
      isGrantsGov: true,
      complianceStatus: 'Aprobada',
      lastSuccessfulRunAtUtc: '2026-08-22T11:00:00Z',
      nextScheduledRunAtUtc: '2026-08-22T13:00:00Z',
      licenseName: 'Public Domain',
      licenseUrl: 'https://grants.gov/legal/terms',
      licenseStatus: 'Aprobada',
      isAllowlisted: true,
      acquisitionReady: true,
      rateLimitPerMinute: 60,
      robotsPolicyStatus: 'Permitido',
      rssFeedHost: 'grants.gov',
      isRssProvider: true,
    })
    expect(JSON.stringify(source)).not.toContain('clientSecret')
    expect(JSON.stringify(source)).not.toContain('vault-secret-name')
    expect(JSON.stringify(source)).not.toContain('never-display')
  })

  it('adapta el contrato gobernado 016 y reconoce RSS sin exponer la URL completa', () => {
    const source = mapFundingSource({
      id: 22,
      name: 'Boletín oficial RSS',
      providerType: 2,
      baseUrl: 'https://boletin.example.test/feed/private?sig=never-display',
      isEnabled: true,
      providerCode: 'official-rss',
      complianceStatus: 'approved',
      licenseStatus: 1,
      licenseName: 'Licencia oficial',
      licenseUrl: 'https://boletin.example.test/licencia?token=never-display',
      robotsPolicyStatus: 1,
      robotsReviewedAtUtc: '2026-08-21T10:00:00Z',
      requestRateLimitPerMinute: 12,
      allowedHostsRequired: true,
      enabledAllowedHostCount: 1,
      acquisitionReady: true,
      nextRunAtUtc: '2026-08-22T13:00:00Z',
    })

    expect(source).toMatchObject({
      providerCode: 'official-rss',
      baseUrl: 'https://boletin.example.test',
      complianceStatus: 'Aprobada',
      licenseStatus: 'Aprobada',
      allowlistRequired: true,
      allowedHostCount: 1,
      allowlistStatus: 'Autorizada',
      rateLimitPerMinute: 12,
      robotsPolicyStatus: 'Aprobada',
      acquisitionReady: true,
      isRssProvider: true,
      rssFeedHost: 'boletin.example.test',
      nextScheduledRunAtUtc: '2026-08-22T13:00:00Z',
    })
    expect(JSON.stringify(source)).not.toContain('never-display')
  })

  it('mapea sólo resúmenes seguros para comparar duplicados', () => {
    const comparison = mapImportDedupeComparison({
      runId: 'run-1',
      itemId: 'item-1',
      dedupeStatus: 'possible_duplicate',
      candidatePreview: {
        opportunityId: '04b6d64c-3495-45af-9c73-a4ce4202dbb6',
        title: 'Fondo de salud',
        sponsor: 'Fundación A',
        deadline: '2026-12-01',
        publicationStatus: 'Borrador',
        rawPayload: '{"secret":"hidden"}',
      },
      existingPreview: {
        id: '74b6d64c-3495-45af-9c73-a4ce4202dbb6',
        title: 'Fondo salud 2026',
        sponsorName: 'Fundación A',
        closeDate: '2026-12-01',
        statusLabel: 'Pendiente de revisión',
        contentHash: 'hidden-hash',
      },
      eTag: '"0102030405060708"',
      canDecide: true,
      blobPath: 'quarantine/private.pdf',
    })

    expect(comparison).toMatchObject({
      dedupeStatus: 'possible-duplicate',
      candidate: { opportunityId: '04b6d64c-3495-45af-9c73-a4ce4202dbb6', title: 'Fondo de salud' },
      existing: { opportunityId: '74b6d64c-3495-45af-9c73-a4ce4202dbb6', title: 'Fondo salud 2026' },
      canDecide: true,
    })
    expect(JSON.stringify(comparison)).not.toContain('rawPayload')
    expect(JSON.stringify(comparison)).not.toContain('hidden-hash')
    expect(JSON.stringify(comparison)).not.toContain('quarantine/private')
  })

  it('tolera el contrato HTTP candidate-centric y representa una decisión ignorada sin evidencia cruda', () => {
    const comparison = mapImportDedupeComparison({
      candidateId: '14b6d64c-3495-45af-9c73-a4ce4202dbb6',
      candidate: {
        opportunityId: '04b6d64c-3495-45af-9c73-a4ce4202dbb6',
        title: 'Fondo entrante', sponsor: 'Organismo A', publicationStatus: 0,
      },
      suggestedCanonical: {
        opportunityId: '74b6d64c-3495-45af-9c73-a4ce4202dbb6',
        title: 'Fondo existente', sponsor: 'Organismo A', publicationStatus: 1,
      },
      matchKind: 2,
      confidence: 0.91,
      status: 1,
      decision: { decision: 3, reason: 'No hay evidencia suficiente.' },
      evidenceJson: '{"raw":"must-not-appear"}',
      eTag: '"0102030405060708"',
    })

    expect(comparison).toMatchObject({
      dedupeStatus: 'ignored',
      decisionCode: 'ignored',
      candidate: { title: 'Fondo entrante', statusLabel: 'Borrador' },
      existing: { title: 'Fondo existente', statusLabel: 'En revisión' },
      matchKind: 'Título y organismo normalizados',
      confidence: 0.91,
      canDecide: false,
    })
    expect(JSON.stringify(comparison)).not.toContain('must-not-appear')
  })

  it('registra una decisión de dedupe con ETag, idempotencia y no-store', async () => {
    const fetchMock = vi.fn().mockResolvedValue(json({
      candidateId: '14b6d64c-3495-45af-9c73-a4ce4202dbb6',
      decisionId: '24b6d64c-3495-45af-9c73-a4ce4202dbb6',
      status: 1,
      decision: 2,
      canonicalOpportunityId: '74b6d64c-3495-45af-9c73-a4ce4202dbb6',
      eTag: '"0203040506070809"',
      wasReplay: false,
    }))
    vi.stubGlobal('fetch', fetchMock)

    const result = await adminImportApi.decideDedupe(
      '14b6d64c-3495-45af-9c73-a4ce4202dbb6',
      { decision: 'mark-duplicate', canonicalOpportunityId: 'existing-1', reason: 'Coincidencia verificada.' },
      '"0102030405060708"',
      '0207075b-ff57-4daa-90a3-bb42f2a15891',
    )

    expect(result.isPublished).toBe(false)
    const [url, options] = fetchMock.mock.calls[0] as [string, RequestInit]
    const headers = new Headers(options.headers)
    expect(url).toBe('/api/v1/admin/funding-duplicate-candidates/14b6d64c-3495-45af-9c73-a4ce4202dbb6/decisions')
    expect(options.cache).toBe('no-store')
    expect(headers.get('If-Match')).toBe('"0102030405060708"')
    expect(headers.get('Idempotency-Key')).toBe('0207075b-ff57-4daa-90a3-bb42f2a15891')
    expect(JSON.parse(String(options.body))).toEqual({
      decision: 'mark-duplicate',
      canonicalOpportunityId: 'existing-1',
      reason: 'Coincidencia verificada.',
    })
  })

  it('no emite una mutación de dedupe con motivo vacío', async () => {
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)

    await expect(adminImportApi.decideDedupe(
      '14b6d64c-3495-45af-9c73-a4ce4202dbb6',
      { decision: 'ignored', reason: '   ' },
      '"0102030405060708"',
      '0207075b-ff57-4daa-90a3-bb42f2a15891',
    )).rejects.toThrow('dedupe-reason-required')

    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('mantiene polling sólo para estados activos y sanea mensajes operacionales', () => {
    expect(shouldPollImportRuns([{ status: 'completed' }, { status: 'failed' }])).toBe(false)
    expect(shouldPollImportRuns([{ status: 'completed' }, { status: 'running' }])).toBe(true)

    const detail = mapImportRunDetail({
      runId: 'run-1', fundingSourceId: 12, sourceName: 'Grants.gov', providerCode: 'grants-gov',
      triggerType: 0, status: 4, keyword: 'health', maximumResults: 10,
      retrievedCount: 1, createdCount: 0, updatedCount: 0, unchangedCount: 0,
      stagedForReviewCount: 0, failedCount: 1, attemptCount: 1,
      createdAtUtc: '2026-08-22T12:00:00Z', startedAtUtc: null, completedAtUtc: '2026-08-22T12:01:00Z',
      lastErrorCode: 'upstream-error', items: [],
      errors: [{
        errorId: 'error-1', itemId: null, stage: 'fetch', code: 'upstream',
        message: 'token=top-secret https://vendor.example/path?sig=hidden',
        isRetryable: true, occurredAtUtc: '2026-08-22T12:00:30Z',
      }],
    })
    expect(detail.errors[0].message).toContain('[protegido]')
    expect(detail.errors[0].message).toContain('[URL protegida]')
    expect(detail.errors[0].message).not.toContain('top-secret')
    expect(detail.errors[0].message).not.toContain('hidden')
  })
})
