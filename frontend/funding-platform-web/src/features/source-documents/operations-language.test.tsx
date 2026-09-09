import { act, fireEvent, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { deferred, language } from '@/test/tracking-test-harness'
import { operationsJson, renderOperations } from '@/test/operations-test-harness'
import { operationsDocument, operationsETag, operationsIds } from '@/test/fixtures/operations-workspace'
import type { SourceDocumentStatusResponse } from './source-document-api'

describe('I18N05D secure PDF language changes', () => {
  afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals() })

  it.each([
    [{ scanStatus: 0, storageStatus: 1 }, 'Scan pending'],
    [{ scanStatus: 1, storageStatus: 1 }, 'Clean'],
    [{ scanStatus: 2, storageStatus: 1 }, 'Malicious content'],
    [{ scanStatus: 3, storageStatus: 1, scanProvider: 1, isProductionScan: true }, 'Scan failed'],
    [{ scanStatus: 4, storageStatus: 1, scanProvider: 1, isProductionScan: true }, 'Scan timed out'],
  ] as const)('never enables extraction for an untrusted document: %j', async (overrides, status) => {
    const view = renderOperations('/admin/source-documents/' + operationsIds.intent, {
      ['/admin/source-documents/' + operationsIds.document]: operationsDocument(overrides),
    })
    await screen.findByText('Extracción documental')
    const before = view.requests.length
    await language('en')
    expect(screen.getByText(status)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Start extraction' })).not.toBeInTheDocument()
    if (overrides.scanStatus >= 3) expect(screen.queryByRole('button', { name: 'Retry scan' })).not.toBeInTheDocument()
    expect(view.requests).toHaveLength(before)
    expect(view.requests.every(request => request.method === 'GET')).toBe(true)
    expect(view.unexpected).toEqual([])
  })

  it('distinguishes simulated scanning from real Defender without changing production flags', async () => {
    const view = renderOperations('/admin/source-documents/' + operationsIds.intent)
    await screen.findByText('Defender real pendiente de configuración')
    await language('en')
    expect(screen.getByText('Real Defender configuration pending')).toBeInTheDocument()
    expect(screen.getByText(/must not be considered production validation/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Start extraction' })).toBeEnabled()
    expect(view.requests.every(request => request.method === 'GET')).toBe(true)
    expect(view.unexpected).toEqual([])
  })

  it('preserves selected File and in-memory completion token across a recoverable verification failure', async () => {
    const user = userEvent.setup()
    const authorized = deferred<Response>()
    let completions = 0
    const view = renderOperations('/admin/imports/upload-document', {}, request => {
      if (request.method === 'POST' && request.url.pathname.endsWith('/source-document-upload-intents')) return authorized.promise
      if (request.url.origin === 'https://blob.example.invalid') return new Response(null, { status: 201 })
      if (request.method === 'POST' && request.url.pathname.endsWith('/complete')) {
        completions++
        return completions === 1 ? operationsJson({ title: 'PRIVATE-VERIFICATION-DETAIL' }, 503)
          : operationsJson({ sourceDocumentId: operationsIds.document, scanStatus: 1, isDevelopmentScan: true })
      }
    })
    await screen.findByRole('option', { name: 'Boletín Ñandú' })
    const file = new File(['%PDF-1.7 synthetic %%EOF'], 'bases-Ñandú.pdf', { type: 'application/pdf' })
    const input = document.querySelector<HTMLInputElement>('input[type=file]')!
    await user.upload(input, file)
    await language('en')
    expect(input.files?.[0]).toBe(file)
    expect(screen.getByRole('combobox', { name: 'Origin source' })).toHaveValue('10')
    await user.click(screen.getByRole('button', { name: 'Upload and verify' }))
    await screen.findByText('Creating secure authorization…')
    await language('es')
    expect(input.files?.[0]).toBe(file)
    expect(view.requests.filter(request => request.method === 'POST')).toHaveLength(1)
    await act(async () => authorized.resolve(operationsJson({
      intentId: operationsIds.intent, status: 0, expiresAtUtc: '2099-01-01T00:00:00Z',
      maxContentLength: 26_214_400, uploadMethod: 'PUT', uploadUrl: 'https://blob.example.invalid/pdf?sig=synthetic-only',
      requiredHeaders: { 'x-ms-blob-type': 'BlockBlob', 'Content-Type': 'application/pdf' },
      completionToken: 'synthetic-memory-only', statusUrl: '', eTag: operationsETag, securityNotice: '',
    })))
    await screen.findByRole('button', { name: 'Reanudar' })
    await language('en')
    expect(screen.getByText('The upload could not be completed. Try again.')).toBeInTheDocument()
    expect(screen.queryByText('PRIVATE-VERIFICATION-DETAIL')).not.toBeInTheDocument()
    expect(completions).toBe(1)
    const transfer = view.requests.find(request => request.method === 'PUT')!
    expect(transfer.init.body).toBe(file)
    expect(transfer.init.credentials).toBe('omit')
    expect(new Headers(transfer.init.headers).has('Authorization')).toBe(false)
    expect(new Headers(transfer.init.headers).get('x-ms-blob-type')).toBe('BlockBlob')
    expect(JSON.stringify({ ...localStorage, ...sessionStorage })).not.toMatch(/synthetic-memory-only|sig=|completionToken/)
    await user.click(screen.getByRole('button', { name: 'Resume' }))
    await screen.findByText('Verification resumed successfully.')
    const completed = view.requests.filter(request => request.url.pathname.endsWith('/complete'))
    expect(completed).toHaveLength(2)
    expect(completed.map(request => JSON.parse(String(request.init.body)))).toEqual([
      { completionToken: 'synthetic-memory-only' }, { completionToken: 'synthetic-memory-only' },
    ])
    expect(view.requests.filter(request => request.method === 'PUT')).toHaveLength(1)
    expect(view.requests.filter(request => request.url.pathname.endsWith('/source-document-upload-intents') && request.method === 'POST')).toHaveLength(1)
    expect(JSON.stringify({ ...localStorage, ...sessionStorage })).not.toMatch(/synthetic-memory-only|sig=|completionToken/)
    expect(view.unexpected).toEqual([])
  })

  it.each([
    [new File(['bad'], 'invalid.txt', { type: 'text/plain' }), 'Only PDF files are accepted.'],
    [new File([], 'empty.pdf', { type: 'application/pdf' }), 'The PDF must be no larger than 25 MB.'],
  ])('translates file validation without uploading or discarding the selection', async (file, message) => {
    const view = renderOperations('/admin/imports/upload-document')
    await screen.findByRole('option', { name: 'Boletín Ñandú' })
    const input = document.querySelector<HTMLInputElement>('input[type=file]')!
    fireEvent.change(input, { target: { files: [file] } })
    await userEvent.click(screen.getByRole('button', { name: 'Cargar y verificar' }))
    await language('en')
    expect(screen.getByText(message)).toBeInTheDocument()
    expect(input.files?.[0]).toBe(file)
    expect(view.requests.every(request => request.method === 'GET')).toBe(true)
    expect(view.unexpected).toEqual([])
  })

  it('keeps extraction ETag/idempotency and translates a late conflict', async () => {
    const result = deferred<Response>()
    let reads = 0
    const view = renderOperations('/admin/source-documents/' + operationsIds.intent, {}, request => {
      if (request.method === 'POST' && request.url.pathname.endsWith('/extractions')) return result.promise
      if (request.method === 'GET' && request.url.pathname.endsWith('/source-documents/' + operationsIds.document)) {
        reads++
        return operationsJson(operationsDocument({ extractionStatus: reads === 1 ? 0 : 1 }))
      }
    })
    await userEvent.click(await screen.findByRole('button', { name: 'Iniciar extracción' }))
    await language('en')
    expect(screen.getByRole('button', { name: 'Start extraction' })).toBeDisabled()
    const write = view.requests.find(request => request.method === 'POST')!
    expect(new Headers(write.init.headers).get('If-Match')).toBe(operationsETag)
    expect(new Headers(write.init.headers).get('Idempotency-Key')).toMatch(/^[0-9a-f-]{36}$/i)
    await act(async () => result.resolve(operationsJson({ title: 'PRIVATE-DETAIL' }, 412)))
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('The document version changed. Reload and try again.'))
    expect(screen.queryByRole('button', { name: 'Start extraction' })).not.toBeInTheDocument()
    expect(screen.getByText(/Text extraction continues in the background/)).toBeInTheDocument()
    await language('es')
    expect(screen.getByRole('alert')).toHaveTextContent('La versión del documento cambió.')
    expect(view.requests.filter(request => request.method === 'POST')).toHaveLength(1)
    expect(view.unexpected).toEqual([])
  })

  it.each([
    [{ extractionStatus: 3, extractedCharacterCount: 48250, extractedPageCount: 12 }, 'Extraction completed.'],
    [{ extractionStatus: 3, isContentRedacted: true, redactedAtUtc: '2026-09-01T12:00:00Z' }, 'Extracted content was deleted'],
    [{ extractionStatus: 5, extractionResultCode: 'safe-failure' }, 'Extraction exhausted its retries'],
  ] satisfies [Partial<SourceDocumentStatusResponse>, string][])('translates terminal extraction states %j', async (overrides, expected) => {
    const view = renderOperations('/admin/source-documents/' + operationsIds.intent, {
      ['/admin/source-documents/' + operationsIds.document]: { ...operationsDocument(overrides), extractedText: 'PRIVATE-EXTRACTED-TEXT' },
    })
    await screen.findByText('Extracción documental')
    await language('en')
    expect(screen.getByText(expected, { exact: false })).toBeInTheDocument()
    expect(screen.queryByText('PRIVATE-EXTRACTED-TEXT')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Start extraction' })).not.toBeInTheDocument()
    expect(view.requests.every(request => request.method === 'GET')).toBe(true)
    expect(view.unexpected).toEqual([])
  })
})
