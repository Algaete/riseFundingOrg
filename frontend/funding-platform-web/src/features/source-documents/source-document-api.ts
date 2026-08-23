import { ApiError, apiClient } from '@/api/http-client'

export type UploadIntentStatus = 0 | 1 | 2 | 3 | 4
export type StorageStatus = 0 | 1 | 2 | 3
export type ScanStatus = 0 | 1 | 2 | 3 | 4
export type ScanProvider = 0 | 1
export type ExtractionStatus = 0 | 1 | 2 | 3 | 4 | 5 | 6

export interface UploadIntentCreated {
  intentId: string
  status: UploadIntentStatus
  expiresAtUtc: string
  maxContentLength: number
  uploadMethod: 'PUT'
  uploadUrl: string
  requiredHeaders: Record<string, string>
  completionToken: string
  statusUrl: string
  eTag: string
  securityNotice: string
}

export interface SourceDocumentOperation {
  intentId: string | null
  intentStatus: UploadIntentStatus | null
  sourceDocumentId: string | null
  storageStatus: StorageStatus | null
  scanStatus: ScanStatus | null
  scanProvider: ScanProvider | null
  scanAttemptCount: number | null
  eTag: string
  wasReplay: boolean
  isTerminal: boolean
  isDevelopmentScan: boolean
}

export interface UploadIntentStatusResponse {
  intentId: string
  fundingSourceId: number
  fundingSourceName: string
  fileName: string
  mimeType: string
  expectedContentLength: number
  maxContentLength: number
  status: UploadIntentStatus
  expiresAtUtc: string
  sourceDocumentId: string | null
  storageStatus: StorageStatus | null
  scanStatus: ScanStatus | null
  scanProvider: ScanProvider | null
  scanResultCode: string | null
  createdAtUtc: string
  completedAtUtc: string | null
  updatedAtUtc: string
  eTag: string
  isDevelopmentScan: boolean
}

export interface SourceDocumentStatusResponse {
  sourceDocumentId: string
  fundingSourceId: number
  fundingSourceName: string
  fileName: string
  mimeType: string
  contentLength: number
  storageStatus: StorageStatus
  scanStatus: ScanStatus
  scanProvider: ScanProvider
  isProductionScan: boolean
  scanAttemptCount: number
  scanResultCode: string | null
  scanStartedAtUtc: string | null
  scanCompletedAtUtc: string | null
  extractionStatus: ExtractionStatus
  extractionJobId: string | null
  extractionAttemptCount: number
  extractionMaxAttempts: number
  extractedPageCount: number | null
  extractedCharacterCount: number | null
  extractionEvidenceCount: number
  extractionErrorCount: number
  extractionResultCode: string | null
  isContentRedacted: boolean
  redactedAtUtc: string | null
  extractionStartedAtUtc: string | null
  extractionCompletedAtUtc: string | null
  uploadedByUserId: string
  createdAtUtc: string
  updatedAtUtc: string
  eTag: string
}

export interface SourceDocumentExtractionOperation {
  sourceDocumentId: string
  extractionJobId: string | null
  extractionStatus: ExtractionStatus
  eTag: string
  wasReplay: boolean
  statusUrl: string | null
}

type JsonRecord = Record<string, unknown>

const extractionStatusAliases: Record<string, ExtractionStatus> = {
  'not-started': 0,
  pending: 1,
  queued: 1,
  running: 2,
  processing: 2,
  completed: 3,
  'completed-with-errors': 4,
  'completed-with-warnings': 4,
  partial: 4,
  failed: 5,
  cancelled: 6,
  canceled: 6,
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function firstValue(value: JsonRecord, aliases: string[]) {
  for (const alias of aliases) {
    if (value[alias] !== undefined && value[alias] !== null) return value[alias]
  }
  return undefined
}

function stringValue(value: JsonRecord, aliases: string[], fallback = '') {
  const candidate = firstValue(value, aliases)
  return typeof candidate === 'string' ? candidate.slice(0, 500) : fallback
}

function nullableString(value: JsonRecord, aliases: string[]) {
  const candidate = firstValue(value, aliases)
  return typeof candidate === 'string' && candidate.length > 0
    ? candidate.slice(0, 500)
    : null
}

function numberValue(value: JsonRecord, aliases: string[], fallback = 0) {
  const candidate = firstValue(value, aliases)
  return typeof candidate === 'number' && Number.isFinite(candidate) ? candidate : fallback
}

function nullableNumber(value: JsonRecord, aliases: string[]) {
  const candidate = firstValue(value, aliases)
  return typeof candidate === 'number' && Number.isFinite(candidate) ? candidate : null
}

function boundedNumber(value: JsonRecord, aliases: string[], minimum: number, maximum: number) {
  const candidate = numberValue(value, aliases, minimum)
  return Number.isInteger(candidate) && candidate >= minimum && candidate <= maximum
    ? candidate
    : minimum
}

function booleanValue(value: JsonRecord, aliases: string[], fallback = false) {
  const candidate = firstValue(value, aliases)
  return typeof candidate === 'boolean' ? candidate : fallback
}

function safeCode(value: JsonRecord, aliases: string[]) {
  const candidate = nullableString(value, aliases)
  return candidate && /^[a-z0-9._-]{1,100}$/i.test(candidate) ? candidate : null
}

function extractionStatusValue(value: JsonRecord): ExtractionStatus {
  const candidate = firstValue(value, ['extractionStatus', 'status'])
  if (typeof candidate === 'number' && Number.isInteger(candidate) && candidate >= 0 && candidate <= 6) {
    return candidate as ExtractionStatus
  }
  if (typeof candidate === 'string') {
    const normalized = candidate.trim().toLowerCase().replace(/[_\s]+/g, '-')
    return extractionStatusAliases[normalized] ?? 0
  }
  return 0
}

export function mapSourceDocumentStatus(value: unknown): SourceDocumentStatusResponse {
  if (!isRecord(value)) throw new Error('invalid-source-document-response')
  const extractionValue = firstValue(value, ['extraction', 'extractionJob'])
  const extraction = isRecord(extractionValue) ? extractionValue : value
  return {
    sourceDocumentId: stringValue(value, ['sourceDocumentId', 'sourceDocumentPublicId', 'documentId']),
    fundingSourceId: numberValue(value, ['fundingSourceId', 'sourceId']),
    fundingSourceName: stringValue(value, ['fundingSourceName', 'sourceName'], 'Fuente'),
    fileName: stringValue(value, ['fileName', 'originalFileName'], 'Documento PDF'),
    mimeType: stringValue(value, ['mimeType'], 'application/pdf'),
    contentLength: numberValue(value, ['contentLength']),
    storageStatus: boundedNumber(value, ['storageStatus'], 0, 3) as StorageStatus,
    scanStatus: boundedNumber(value, ['scanStatus'], 0, 4) as ScanStatus,
    scanProvider: boundedNumber(value, ['scanProvider'], 0, 1) as ScanProvider,
    isProductionScan: booleanValue(value, ['isProductionScan']),
    scanAttemptCount: numberValue(value, ['scanAttemptCount']),
    scanResultCode: safeCode(value, ['scanResultCode']),
    scanStartedAtUtc: nullableString(value, ['scanStartedAtUtc']),
    scanCompletedAtUtc: nullableString(value, ['scanCompletedAtUtc']),
    extractionStatus: extractionStatusValue(extraction),
    extractionJobId: nullableString(extraction, ['extractionJobId', 'extractionJobPublicId', 'jobPublicId', 'jobId']),
    extractionAttemptCount: numberValue(extraction, ['extractionAttemptCount', 'extractionAttempts', 'attemptCount']),
    extractionMaxAttempts: numberValue(extraction, ['extractionMaxAttempts', 'maxAttempts']),
    extractedPageCount: nullableNumber(extraction, ['extractedPageCount', 'pageCount']),
    extractedCharacterCount: nullableNumber(extraction, ['extractedCharacterCount', 'characterCount']),
    extractionEvidenceCount: numberValue(extraction, ['extractionEvidenceCount', 'evidenceCount']),
    extractionErrorCount: numberValue(extraction, ['extractionErrorCount', 'errorCount']),
    extractionResultCode: safeCode(extraction, ['extractionResultCode', 'extractionCode', 'resultCode', 'lastErrorCode']),
    isContentRedacted: booleanValue(extraction, ['isContentRedacted', 'contentRedacted']),
    redactedAtUtc: nullableString(extraction, ['redactedAtUtc', 'contentRedactedAtUtc']),
    extractionStartedAtUtc: nullableString(extraction, ['extractionStartedAtUtc', 'startedAtUtc']),
    extractionCompletedAtUtc: nullableString(extraction, ['extractionCompletedAtUtc', 'completedAtUtc']),
    uploadedByUserId: stringValue(value, ['uploadedByUserId', 'uploadedByUserPublicId']),
    createdAtUtc: stringValue(value, ['createdAtUtc']),
    updatedAtUtc: stringValue(value, ['updatedAtUtc']),
    eTag: stringValue(value, ['eTag', 'etag']),
  }
}

function mapExtractionOperation(value: unknown): SourceDocumentExtractionOperation {
  if (!isRecord(value)) throw new Error('invalid-source-document-extraction-response')
  return {
    sourceDocumentId: stringValue(value, ['sourceDocumentId', 'sourceDocumentPublicId', 'documentId']),
    extractionJobId: nullableString(value, ['extractionJobId', 'extractionJobPublicId', 'jobPublicId', 'jobId']),
    extractionStatus: extractionStatusValue(value),
    eTag: stringValue(value, ['eTag', 'etag']),
    wasReplay: booleanValue(value, ['wasReplay']),
    statusUrl: nullableString(value, ['statusUrl']),
  }
}

const intentsPath = 'admin/source-document-upload-intents'
const documentsPath = 'admin/source-documents'

export const sourceDocumentApi = {
  createIntent(fundingSourceId: number, file: File) {
    return apiClient.post<UploadIntentCreated>(intentsPath, {
      fundingSourceId,
      fileName: file.name,
      mimeType: file.type,
      contentLength: file.size,
    }, { cache: 'no-store' })
  },
  complete(intentId: string, completionToken: string) {
    return apiClient.post<SourceDocumentOperation>(
      `${intentsPath}/${encodeURIComponent(intentId)}/complete`,
      { completionToken },
      { cache: 'no-store' },
    )
  },
  getIntent(intentId: string, signal?: AbortSignal) {
    return apiClient.get<UploadIntentStatusResponse>(
      `${intentsPath}/${encodeURIComponent(intentId)}`,
      { cache: 'no-store', signal },
    )
  },
  async getDocument(sourceDocumentId: string, signal?: AbortSignal) {
    const response = await apiClient.get<unknown>(
      `${documentsPath}/${encodeURIComponent(sourceDocumentId)}`,
      { cache: 'no-store', signal },
    )
    return mapSourceDocumentStatus(response)
  },
  retry(sourceDocumentId: string, eTag: string, idempotencyKey: string) {
    return apiClient.post<SourceDocumentOperation>(
      `${documentsPath}/${encodeURIComponent(sourceDocumentId)}/scan/retry`,
      undefined,
      { cache: 'no-store', headers: { 'If-Match': eTag, 'Idempotency-Key': idempotencyKey } },
    )
  },
  async startExtraction(sourceDocumentId: string, eTag: string, idempotencyKey: string) {
    const response = await apiClient.post<unknown>(
      `${documentsPath}/${encodeURIComponent(sourceDocumentId)}/extractions`,
      undefined,
      { cache: 'no-store', headers: { 'If-Match': eTag, 'Idempotency-Key': idempotencyKey } },
    )
    return mapExtractionOperation(response)
  },
}

export async function uploadFileDirectly(
  grant: UploadIntentCreated,
  file: File,
  signal?: AbortSignal,
) {
  const headers = new Headers()
  Object.entries(grant.requiredHeaders).forEach(([name, value]) => headers.set(name, value))
  const response = await fetch(grant.uploadUrl, {
    method: grant.uploadMethod,
    headers,
    body: file,
    credentials: 'omit',
    cache: 'no-store',
    redirect: 'error',
    referrerPolicy: 'no-referrer',
    signal,
  })
  if (!response.ok) {
    throw new DirectUploadError(response.status)
  }
}

export class DirectUploadError extends Error {
  readonly status: number

  constructor(status: number) {
    super('No fue posible transferir el PDF al almacenamiento seguro.')
    this.name = 'DirectUploadError'
    this.status = status
  }
}

function safeProblemText(value: string) {
  return value
    .replace(/https?:\/\/[^\s]+/gi, '[URL protegida]')
    .replace(/\b(bearer|token|password|secret|signature|sig|key|sas)\b\s*[:=]\s*[^\s,;]+/gi, '$1=[protegido]')
    .slice(0, 500)
}

export function sourceDocumentErrorMessage(error: unknown) {
  if (error instanceof ApiError) {
    if (error.response.status === 401) return 'La sesión venció. Inicia sesión nuevamente.'
    if (error.response.status === 403) return 'Necesitas una sesión administrativa con MFA reciente.'
    if (error.response.status === 409) return 'El documento cambió de estado. Recarga la información antes de continuar.'
    if (error.response.status === 412) return 'La versión del documento cambió. Recarga e intenta nuevamente.'
    if (error.response.status === 422) {
      return safeProblemText(
        error.problem.detail ?? 'Revisa los datos del documento e intenta nuevamente.',
      )
    }
    return safeProblemText(error.problem.detail ?? error.problem.title)
  }
  if (error instanceof DirectUploadError) return error.message
  return 'No fue posible completar la carga. Intenta nuevamente.'
}
