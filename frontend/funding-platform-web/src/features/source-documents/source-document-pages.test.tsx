import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { setAuthenticatedSession } from '@/features/auth/auth-session'
import { appRoutes } from '@/router'

const intentId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
const documentId = 'cccccccc-cccc-cccc-cccc-cccccccccccc'

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': status >= 400 ? 'application/problem+json' : 'application/json' },
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

function intent() {
  return {
    intentId,
    fundingSourceId: 9,
    fundingSourceName: 'Boletín oficial',
    fileName: 'bases-oficiales.pdf',
    mimeType: 'application/pdf',
    expectedContentLength: 2048,
    maxContentLength: 26_214_400,
    status: 2,
    expiresAtUtc: '2026-08-22T12:05:00Z',
    sourceDocumentId: documentId,
    storageStatus: 2,
    scanStatus: 1,
    scanProvider: 0,
    scanResultCode: 'clean-development',
    createdAtUtc: '2026-08-22T12:00:00Z',
    completedAtUtc: '2026-08-22T12:00:03Z',
    updatedAtUtc: '2026-08-22T12:00:03Z',
    eTag: '"0102030405060708"',
    isDevelopmentScan: true,
  }
}

function sourceDocument(overrides: Record<string, unknown> = {}) {
  return {
    sourceDocumentId: documentId,
    fundingSourceId: 9,
    fundingSourceName: 'Boletín oficial',
    fileName: 'bases-oficiales.pdf',
    mimeType: 'application/pdf',
    contentLength: 2048,
    storageStatus: 2,
    scanStatus: 1,
    scanProvider: 0,
    isProductionScan: false,
    scanAttemptCount: 1,
    scanResultCode: 'clean-development',
    scanStartedAtUtc: '2026-08-22T12:00:01Z',
    scanCompletedAtUtc: '2026-08-22T12:00:02Z',
    extractionStatus: 0,
    extraction: null,
    uploadedByUserId: '89b8d22a-472c-42e4-b034-c772ce3bb08e',
    createdAtUtc: '2026-08-22T12:00:00Z',
    updatedAtUtc: '2026-08-22T12:00:03Z',
    eTag: '"0102030405060708"',
    ...overrides,
  }
}

function renderDetail() {
  const queryClient = createAppQueryClient()
  queryClient.setDefaultOptions({ queries: { retry: false } })
  const router = createMemoryRouter(appRoutes, {
    initialEntries: [`/admin/source-documents/${intentId}`],
  })
  render(<App queryClient={queryClient} router={router} />)
}

describe('extracción segura de documentos fuente', () => {
  beforeEach(() => {
    authenticateAdmin()
    sessionStorage.clear()
    localStorage.clear()
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
    sessionStorage.clear()
    localStorage.clear()
  })

  it('distingue el analizador local e inicia sólo desde Clean + Trusted', async () => {
    let document = sourceDocument()
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input)
      if (url.endsWith(`/admin/source-document-upload-intents/${intentId}`)) {
        return Promise.resolve(json(intent()))
      }
      if (url.endsWith(`/admin/source-documents/${documentId}`) && init?.method === 'GET') {
        return Promise.resolve(json(document))
      }
      if (url.endsWith(`/admin/source-documents/${documentId}/extractions`) && init?.method === 'POST') {
        document = sourceDocument({
          extractionStatus: 1,
          extraction: {
            jobPublicId: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
            status: 1,
            attemptCount: 0,
            maxAttempts: 3,
            pageCount: null,
            characterCount: null,
            resultCode: null,
            startedAtUtc: null,
            completedAtUtc: null,
          },
          updatedAtUtc: '2026-08-22T12:01:00Z',
          eTag: '"0203040506070809"',
        })
        return Promise.resolve(json({
          sourceDocumentId: documentId,
          jobId: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
          status: 1,
          eTag: '"0203040506070809"',
          wasReplay: false,
          statusUrl: `/api/v1/admin/source-documents/${documentId}`,
        }, 202))
      }
      return Promise.resolve(json({ title: 'No encontrado', status: 404 }, 404))
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    renderDetail()

    expect(await screen.findByText('Defender real pendiente de configuración')).toBeInTheDocument()
    expect(await screen.findByText(/Extrae texto verificable para una revisión posterior, sin interpretar ni publicar contenido/i)).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Iniciar extracción' }))

    expect(await screen.findByText('La extracción documental se inició correctamente.')).toBeInTheDocument()
    expect(await screen.findByText('La extracción de texto continúa en segundo plano.', { exact: false })).toBeInTheDocument()

    const request = fetchMock.mock.calls.find(([input, init]) =>
      String(input).endsWith(`/admin/source-documents/${documentId}/extractions`) && init?.method === 'POST')
    expect(request).toBeDefined()
    const options = request?.[1] as RequestInit
    const headers = new Headers(options.headers)
    expect(options.cache).toBe('no-store')
    expect(headers.get('If-Match')).toBe('"0102030405060708"')
    expect(headers.get('Idempotency-Key')).toMatch(/^[0-9a-f-]{36}$/i)
    expect(sessionStorage).toHaveLength(0)
    const persisted = Array.from(
      { length: localStorage.length },
      (_, index) => localStorage.getItem(localStorage.key(index) ?? ''),
    ).join('')
    expect(persisted).not.toContain('sig=')
    expect(persisted).not.toContain('completionToken')
  })

  it('bloquea la extracción si el archivo sigue en cuarentena', async () => {
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      const url = String(input)
      if (url.endsWith(`/admin/source-document-upload-intents/${intentId}`)) return Promise.resolve(json(intent()))
      if (url.endsWith(`/admin/source-documents/${documentId}`)) {
        return Promise.resolve(json(sourceDocument({ storageStatus: 1, scanStatus: 1 })))
      }
      return Promise.resolve(json({}, 404))
    }))
    renderDetail()

    expect(await screen.findByText('Sólo puedes iniciar la extracción cuando el análisis sea Limpio y el almacenamiento sea Trusted.')).toBeInTheDocument()
    await waitFor(() => expect(screen.queryByRole('button', { name: 'Iniciar extracción' })).not.toBeInTheDocument())
  })

  it('recarga el job tras un 412 y no duplica la solicitud', async () => {
    let document = sourceDocument()
    const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input)
      if (url.endsWith(`/admin/source-document-upload-intents/${intentId}`)) return Promise.resolve(json(intent()))
      if (url.endsWith(`/admin/source-documents/${documentId}`) && init?.method === 'GET') {
        return Promise.resolve(json(document))
      }
      if (url.endsWith(`/admin/source-documents/${documentId}/extractions`) && init?.method === 'POST') {
        document = sourceDocument({
          extractionStatus: 1,
          extraction: {
            jobPublicId: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
            status: 1,
            attemptCount: 0,
            maxAttempts: 3,
          },
          eTag: '"0203040506070809"',
        })
        return Promise.resolve(json({
          title: 'El documento cambió',
          detail: 'Recarga el estado.',
          status: 412,
        }, 412))
      }
      return Promise.resolve(json({}, 404))
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()
    renderDetail()

    await user.click(await screen.findByRole('button', { name: 'Iniciar extracción' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('La versión del documento cambió')
    expect(await screen.findByText('La extracción de texto continúa en segundo plano.', { exact: false })).toBeInTheDocument()
    expect(fetchMock.mock.calls.filter(([input, init]) =>
      String(input).endsWith('/extractions') && init?.method === 'POST')).toHaveLength(1)
  })

  it('no ofrece un retry manual para un job terminal', async () => {
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      const url = String(input)
      if (url.endsWith(`/admin/source-document-upload-intents/${intentId}`)) return Promise.resolve(json(intent()))
      if (url.endsWith(`/admin/source-documents/${documentId}`)) {
        return Promise.resolve(json(sourceDocument({
          extractionStatus: 5,
          extraction: {
            jobPublicId: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
            status: 5,
            attemptCount: 3,
            maxAttempts: 3,
            resultCode: 'extraction-timeout',
          },
        })))
      }
      return Promise.resolve(json({}, 404))
    }))
    renderDetail()

    expect(await screen.findByRole('alert')).toHaveTextContent('agotó sus reintentos')
    expect(screen.queryByRole('button', { name: /extracción/i })).not.toBeInTheDocument()
  })

  it('no finge un reescaneo de Defender cuando el servicio no está configurado', async () => {
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      const url = String(input)
      if (url.endsWith(`/admin/source-document-upload-intents/${intentId}`)) return Promise.resolve(json(intent()))
      if (url.endsWith(`/admin/source-documents/${documentId}`)) {
        return Promise.resolve(json(sourceDocument({
          scanStatus: 4,
          scanProvider: 1,
          isProductionScan: true,
        })))
      }
      return Promise.resolve(json({}, 404))
    }))
    renderDetail()

    expect(await screen.findByText(/reescaneo bajo demanda de Microsoft Defender no está habilitado/i)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Reintentar análisis' })).not.toBeInTheDocument()
  })

  it('muestra métricas seguras del job completado sin texto ni metadatos protegidos', async () => {
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      const url = String(input)
      if (url.endsWith(`/admin/source-document-upload-intents/${intentId}`)) return Promise.resolve(json(intent()))
      if (url.endsWith(`/admin/source-documents/${documentId}`)) {
        return Promise.resolve(json(sourceDocument({
          extractionStatus: 3,
          extraction: {
            jobPublicId: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
            status: 3,
            attemptCount: 1,
            maxAttempts: 3,
            pageCount: 12,
            characterCount: 48_250,
            evidenceCount: 7,
            errorCount: 0,
            resultCode: 'completed',
            startedAtUtc: '2026-08-22T12:01:00Z',
            completedAtUtc: '2026-08-22T12:01:10Z',
            extractedText: 'never-display-raw-text',
            extractedTextHash: 'never-display-hash',
            trustedBlobPath: 'never-display-path',
          },
        })))
      }
      return Promise.resolve(json({}, 404))
    }))
    renderDetail()

    expect(await screen.findByText('Extracción completada.')).toBeInTheDocument()
    expect(screen.getByText('12')).toBeInTheDocument()
    expect(screen.getByText('48.250')).toBeInTheDocument()
    expect(screen.getByText('7')).toBeInTheDocument()
    expect(screen.getByText('1 de 3')).toBeInTheDocument()
    expect(screen.queryByText(/never-display/)).not.toBeInTheDocument()
  })

  it('explica la eliminación por retención sin presentar el contenido como fallido', async () => {
    vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL) => {
      const url = String(input)
      if (url.endsWith(`/admin/source-document-upload-intents/${intentId}`)) return Promise.resolve(json(intent()))
      if (url.endsWith(`/admin/source-documents/${documentId}`)) {
        return Promise.resolve(json(sourceDocument({
          extractionStatus: 3,
          extraction: {
            jobPublicId: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
            status: 3,
            attemptCount: 1,
            maxAttempts: 3,
            pageCount: 0,
            characterCount: 0,
            evidenceCount: 0,
            errorCount: 0,
            resultCode: 'content-retention-redacted',
            isContentRedacted: true,
            redactedAtUtc: '2026-11-20T12:00:00Z',
          },
        })))
      }
      return Promise.resolve(json({}, 404))
    }))
    renderDetail()

    expect(await screen.findByText(/se eliminó al vencer la política de retención/i)).toBeInTheDocument()
    expect(screen.queryByText(/extracción.*falló/i)).not.toBeInTheDocument()
  })
})
