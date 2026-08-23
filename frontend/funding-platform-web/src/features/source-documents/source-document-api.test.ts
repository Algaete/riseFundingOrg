import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { executeEditorialCommand } from '@/features/funding/editorial-command-cache'
import { setAuthenticatedSession } from '@/features/auth/auth-session'
import {
  DirectUploadError,
  mapSourceDocumentStatus,
  sourceDocumentApi,
  type UploadIntentCreated,
  uploadFileDirectly,
} from '@/features/source-documents/source-document-api'

const grant: UploadIntentCreated = {
  intentId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  status: 0,
  expiresAtUtc: '2026-08-21T12:05:00Z',
  maxContentLength: 26_214_400,
  uploadMethod: 'PUT',
  uploadUrl: 'https://testing.blob.core.windows.net/fp-source-incoming/file.pdf?sig=secret',
  requiredHeaders: {
    'x-ms-blob-type': 'BlockBlob',
    'Content-Type': 'application/pdf',
    'If-None-Match': '*',
  },
  completionToken: 'one-time-secret',
  statusUrl: '/api/v1/admin/source-document-upload-intents/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  eTag: '"0102030405060708"',
  securityNotice: 'server validates again',
}

describe('carga directa de documentos fuente', () => {
  beforeEach(() => {
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
    sessionStorage.clear()
    localStorage.clear()
  })

  afterEach(() => {
    sessionStorage.clear()
    localStorage.clear()
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
  })

  it('envía exactamente los headers exigidos sin JWT, cookies, persistencia ni redirects', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response(null, { status: 201 }))
    vi.stubGlobal('fetch', fetchMock)
    const file = new File(['%PDF-1.7\n%%EOF\n'], 'documento.pdf', {
      type: 'application/pdf',
    })

    await uploadFileDirectly(grant, file)

    expect(fetchMock).toHaveBeenCalledOnce()
    const [url, options] = fetchMock.mock.calls[0] as [string, RequestInit]
    const headers = options.headers as Headers
    expect(url).toBe(grant.uploadUrl)
    expect(options.method).toBe('PUT')
    expect(options.body).toBe(file)
    expect(options.credentials).toBe('omit')
    expect(options.redirect).toBe('error')
    expect(options.referrerPolicy).toBe('no-referrer')
    expect(headers.get('x-ms-blob-type')).toBe('BlockBlob')
    expect(headers.get('Content-Type')).toBe('application/pdf')
    expect(headers.get('If-None-Match')).toBe('*')
    expect(headers.has('Authorization')).toBe(false)
    expect([...headers.keys()]).toHaveLength(3)
    expect(sessionStorage).toHaveLength(0)
    expect(localStorage).toHaveLength(0)
  })

  it('no refleja el cuerpo de error de Azure ni la URL SAS', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(
      'https://testing.blob.core.windows.net/file.pdf?sig=secret',
      { status: 403 },
    )))

    await expect(uploadFileDirectly(
      grant,
      new File(['pdf'], 'documento.pdf', { type: 'application/pdf' }),
    )).rejects.toEqual(new DirectUploadError(403))
  })

  it('reutiliza Idempotency-Key si la respuesta de retry se pierde', async () => {
    const keys: string[] = []
    const execute = (key: string) => {
      keys.push(key)
      return Promise.reject(new TypeError('respuesta perdida'))
    }
    const scope = 'source-document-scan-retry:cccccccc-cccc-cccc-cccc-cccccccccccc'
    const fingerprint = { action: 'retry-scan', eTag: '"0102030405060708"' }

    await expect(executeEditorialCommand(scope, fingerprint, execute)).rejects.toThrow()
    await expect(executeEditorialCommand(scope, fingerprint, execute)).rejects.toThrow()

    expect(keys).toHaveLength(2)
    expect(keys[0]).toBe(keys[1])
    const stored = Array.from(
      { length: sessionStorage.length },
      (_, index) => sessionStorage.getItem(sessionStorage.key(index) ?? ''),
    ).join('')
    expect(stored).not.toContain('0102030405060708')
  })

  it('inicia extracción con precondición, idempotencia y no-store sin persistir credenciales', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({
      sourceDocumentPublicId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
      jobPublicId: 'dddddddd-dddd-dddd-dddd-dddddddddddd',
      extractionStatus: 1,
      eTag: '"0203040506070809"',
      wasReplay: false,
      statusUrl: '/api/v1/admin/source-documents/cccccccc-cccc-cccc-cccc-cccccccccccc',
    }), { status: 202, headers: { 'Content-Type': 'application/json' } }))
    vi.stubGlobal('fetch', fetchMock)

    const result = await sourceDocumentApi.startExtraction(
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      '"0102030405060708"',
      '0207075b-ff57-4daa-90a3-bb42f2a15891',
    )

    expect(result.extractionStatus).toBe(1)
    expect(result.sourceDocumentId).toBe('cccccccc-cccc-cccc-cccc-cccccccccccc')
    expect(result.extractionJobId).toBe('dddddddd-dddd-dddd-dddd-dddddddddddd')
    const [url, options] = fetchMock.mock.calls[0] as [string, RequestInit]
    const headers = new Headers(options.headers)
    expect(url).toBe('/api/v1/admin/source-documents/cccccccc-cccc-cccc-cccc-cccccccccccc/extractions')
    expect(options.method).toBe('POST')
    expect(options.cache).toBe('no-store')
    expect(headers.get('If-Match')).toBe('"0102030405060708"')
    expect(headers.get('Idempotency-Key')).toBe('0207075b-ff57-4daa-90a3-bb42f2a15891')
    expect(headers.get('Authorization')).toBe('Bearer admin-access-token')
    expect(sessionStorage).toHaveLength(0)
    expect(localStorage).toHaveLength(0)
  })

  it('tolera aliases del job y descarta rutas, hashes y payloads crudos', () => {
    const result = mapSourceDocumentStatus({
      documentId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
      sourceId: 9,
      sourceName: 'Boletín oficial',
      originalFileName: 'bases.pdf',
      mimeType: 'application/pdf',
      contentLength: 1200,
      storageStatus: 2,
      scanStatus: 1,
      scanProvider: 1,
      isProductionScan: true,
      scanAttemptCount: 1,
      extractionStatus: 2,
      extraction: {
        jobPublicId: 'dddddddd-dddd-dddd-dddd-dddddddddddd',
        status: 'running',
        attemptCount: 2,
        maxAttempts: 3,
        pageCount: 8,
        characterCount: 24_000,
        evidenceCount: 6,
        errorCount: 1,
        resultCode: 'extracting',
      },
      uploadedByUserPublicId: 'ffffffff-ffff-ffff-ffff-ffffffffffff',
      createdAtUtc: '2026-08-22T12:00:00Z',
      updatedAtUtc: '2026-08-22T12:01:00Z',
      etag: '"0102030405060708"',
      blobPath: 'quarantine/private/file.pdf',
      contentHash: 'secret-hash',
      rawEventPayload: '{"data":"secret"}',
    })

    expect(result).toMatchObject({
      extractionStatus: 2,
      extractionJobId: 'dddddddd-dddd-dddd-dddd-dddddddddddd',
      extractionAttemptCount: 2,
      extractionMaxAttempts: 3,
      extractedPageCount: 8,
      extractedCharacterCount: 24_000,
      extractionEvidenceCount: 6,
      extractionErrorCount: 1,
    })
    expect(JSON.stringify(result)).not.toContain('quarantine/private')
    expect(JSON.stringify(result)).not.toContain('secret-hash')
    expect(JSON.stringify(result)).not.toContain('rawEventPayload')
  })

  it('expone sólo el estado seguro cuando el contenido venció su retención', () => {
    const result = mapSourceDocumentStatus({
      sourceDocumentId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
      fundingSourceId: 9,
      storageStatus: 2,
      scanStatus: 1,
      scanProvider: 1,
      extraction: {
        status: 3,
        isContentRedacted: true,
        redactedAtUtc: '2026-11-20T12:00:00Z',
        resultCode: 'content-retention-redacted',
        extractedText: 'must-not-be-mapped',
      },
      eTag: '"0102030405060708"',
    })

    expect(result.isContentRedacted).toBe(true)
    expect(result.redactedAtUtc).toBe('2026-11-20T12:00:00Z')
    expect(result.extractionResultCode).toBe('content-retention-redacted')
    expect(JSON.stringify(result)).not.toContain('must-not-be-mapped')
  })
})
