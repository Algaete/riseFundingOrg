import { DirectUploadError } from '@/features/source-documents/source-document-api'
import { documentOperationsErrorKey, importOperationsErrorKey, operationalLabel, operationStatus, operationsMessage } from '@/i18n/operations-messages'
import { language, problem } from '@/test/tracking-test-harness'

describe('operational presentation boundaries', () => {
  it.each([400, 401, 403, 409, 412, 422, 429, 500])('keeps status %s diagnostics safe and language-independent', async status => {
    const error = problem(status)
    const importKey = importOperationsErrorKey(error)
    const documentKey = documentOperationsErrorKey(error)
    const spanish = [operationsMessage(importKey), operationsMessage(documentKey)]
    await language('en')
    expect(importOperationsErrorKey(error)).toBe(importKey)
    expect(documentOperationsErrorKey(error)).toBe(documentKey)
    const english = [operationsMessage(importKey), operationsMessage(documentKey)]
    expect(english).not.toEqual(spanish)
    expect(english.join(' ')).not.toMatch(/PRIVATE-DIAGNOSTIC|https:|operations\./)
  })

  it('only recognizes bundled feedback, never untrusted resource names or prototype properties', async () => {
    await language('en')
    for (const message of ['constructor', '__proto__', 'toString', 'adminImports.missing', 'PRIVATE SQL token=123']) {
      expect(operationsMessage(message)).toBe('The operation could not be completed. Try again.')
    }
    expect(operationStatus({ 0: 'operations.pending' }, '__proto__')).toBe('Unknown status')
    expect(operationStatus({ 0: 'operations.pending' }, 0)).toBe('Pending')
  })

  it('preserves unknown sanitized operational labels and translates only reviewed statuses', async () => {
    await language('en')
    expect(operationalLabel('Aprobada')).toBe('Approved')
    expect(operationalLabel('Licencia original Ñandú')).toBe('Licencia original Ñandú')
    expect(operationalLabel('constructor')).toBe('constructor')
  })

  it('keeps direct transfer failures and interpolated validation messages translatable', async () => {
    const key = documentOperationsErrorKey(new DirectUploadError(403))
    await language('en')
    expect(operationsMessage(key)).toBe('The PDF could not be transferred to secure storage.')
    expect(operationsMessage('sourceDocuments.maxSize', { size: '25 MB' })).toBe('The PDF must be no larger than 25 MB.')
    await language('es')
    expect(operationsMessage(key)).toBe('No fue posible transferir el PDF al almacenamiento seguro.')
  })
})
