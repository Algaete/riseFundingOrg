import { ApiError, apiClient } from '@/api/http-client'

export type ImportRunStatus =
  | 'queued'
  | 'running'
  | 'completed'
  | 'completed-with-errors'
  | 'failed'
  | 'cancelled'
  | 'unknown'

export interface AdminFundingSourceView {
  id: number
  name: string
  providerType: number
  providerCode: string
  baseUrl: string | null
  isEnabled: boolean
  operationalStatus: string
  complianceStatus: string
  lastSuccessfulRunAtUtc: string | null
  nextScheduledRunAtUtc: string | null
  scheduleCron: string | null
  isGrantsGov: boolean
  licenseName: string
  licenseUrl: string | null
  licenseStatus: string
  isAllowlisted: boolean | null
  allowlistRequired: boolean | null
  allowedHostCount: number | null
  allowlistStatus: string
  rateLimitPerMinute: number | null
  minimumRequestIntervalSeconds: number | null
  robotsPolicyStatus: string
  robotsReviewedAtUtc: string | null
  acquisitionReady: boolean | null
  isRssProvider: boolean
  rssFeedHost: string | null
}

export interface ImportRunSummary {
  runId: string
  fundingSourceId: number
  sourceName: string
  providerCode: string
  triggerType: number
  statusCode: number
  status: ImportRunStatus
  keyword: string
  maximumResults: number
  retrievedCount: number
  createdCount: number
  updatedCount: number
  unchangedCount: number
  stagedForReviewCount: number
  failedCount: number
  createdAtUtc: string
  startedAtUtc: string | null
  completedAtUtc: string | null
  lastErrorCode: string | null
}

export interface ImportRunItem {
  itemId: string
  dedupeCandidateId: string | null
  opportunityId: string | null
  candidateOpportunityId: string | null
  duplicateOfOpportunityId: string | null
  externalId: string
  statusCode: number
  outcomeCode: string | null
  decisionCode: string | null
  decisionReasonCode: string | null
  dedupeStatus: ImportDedupeStatus
  requiresEditorialReview: boolean
  isAutoPublished: boolean
  createdAtUtc: string
  completedAtUtc: string | null
}

export type ImportDedupeStatus =
  | 'not-evaluated'
  | 'possible-duplicate'
  | 'keep-separate'
  | 'marked-duplicate'
  | 'ignored'
  | 'not-applicable'
  | 'unknown'

export type ImportDedupeDecision = 'keep-separate' | 'mark-duplicate' | 'ignored'

export interface ImportCandidatePreview {
  opportunityId: string | null
  title: string
  sponsorName: string
  closeDate: string | null
  statusLabel: string
}

export interface ImportDedupeComparison {
  candidateId: string
  runId: string
  itemId: string
  dedupeStatus: ImportDedupeStatus
  candidate: ImportCandidatePreview
  existing: ImportCandidatePreview
  decisionCode: string | null
  decisionReason: string | null
  matchKind: string
  confidence: number | null
  evidenceSummary: string | null
  eTag: string
  canDecide: boolean
}

export interface ImportDedupeDecisionResult {
  candidateId: string
  runId: string
  itemId: string
  dedupeStatus: ImportDedupeStatus
  decisionCode: string
  decisionReason: string | null
  eTag: string
  wasReplay: boolean
  isPublished: boolean
}

export interface DecideImportDedupeInput {
  decision: ImportDedupeDecision
  canonicalOpportunityId?: string
  reason: string
}

export interface ImportRunError {
  errorId: string
  itemId: string | null
  stage: string
  code: string
  message: string
  isRetryable: boolean
  occurredAtUtc: string
}

export interface ImportRunDetail extends ImportRunSummary {
  attemptCount: number
  items: ImportRunItem[]
  errors: ImportRunError[]
}

export interface ImportRunPage {
  items: ImportRunSummary[]
  totalCount: number
  page: number
  pageSize: number
}

export interface CreateImportRunInput {
  keyword: string
  maximumResults: number
}

export interface ImportRunAccepted {
  runId: string
  fundingSourceId: number
  sourceName: string
  statusCode: number
  status: ImportRunStatus
  createdAtUtc: string
  wasReplay: boolean
  statusUrl: string
}

export interface ImportRunFilters {
  sourceId?: number
  status?: number
  page: number
  pageSize: number
}

type JsonRecord = Record<string, unknown>

const statusNames: Record<number, ImportRunStatus> = {
  0: 'queued',
  1: 'running',
  2: 'completed',
  3: 'completed-with-errors',
  4: 'failed',
  5: 'cancelled',
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

function nullablePublicId(value: JsonRecord, aliases: string[]) {
  const candidate = nullableString(value, aliases)
  return candidate && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(candidate)
    ? candidate
    : null
}

function numberValue(value: JsonRecord, aliases: string[], fallback = 0) {
  const candidate = firstValue(value, aliases)
  return typeof candidate === 'number' && Number.isFinite(candidate)
    ? candidate
    : fallback
}

function booleanValue(value: JsonRecord, aliases: string[], fallback = false) {
  const candidate = firstValue(value, aliases)
  return typeof candidate === 'boolean' ? candidate : fallback
}

function nullableBoolean(value: JsonRecord, aliases: string[]) {
  const candidate = firstValue(value, aliases)
  return typeof candidate === 'boolean' ? candidate : null
}

function nullableNumber(value: JsonRecord, aliases: string[]) {
  const candidate = firstValue(value, aliases)
  return typeof candidate === 'number' && Number.isFinite(candidate)
    ? candidate
    : null
}

function recordValue(value: unknown, context: string): JsonRecord {
  if (!isRecord(value)) throw new Error(`invalid-${context}-response`)
  return value
}

function normalizeProviderCode(value: string) {
  return value.trim().toLowerCase().replace(/[^a-z0-9]+/g, '-')
}

function safeSourceUrl(value: string | null) {
  if (!value) return null
  try {
    const parsed = new URL(value)
    return parsed.protocol === 'https:' || parsed.protocol === 'http:'
      ? `${parsed.protocol}//${parsed.host}`
      : null
  } catch {
    return null
  }
}

function safePublicUrl(value: string | null) {
  if (!value) return null
  try {
    const parsed = new URL(value)
    if (parsed.protocol !== 'https:') return null
    parsed.username = ''
    parsed.password = ''
    parsed.search = ''
    parsed.hash = ''
    return parsed.toString().slice(0, 500)
  } catch {
    return null
  }
}

function safeHost(value: string | null) {
  const safe = safePublicUrl(value)
  if (!safe) return null
  return new URL(safe).host
}

function safeOperationalText(value: string, fallback: string) {
  if (!value) return fallback
  return value
    .replace(/https?:\/\/[^\s]+/gi, '[URL protegida]')
    .replace(/\b(bearer|token|password|secret|signature|sig|key)\b\s*[:=]\s*[^\s,;]+/gi, '$1=[protegido]')
    .slice(0, 300)
}

function complianceLabel(value: string, fallback: string) {
  const normalized = value.trim().toLowerCase().replace(/[_\s]+/g, '-')
  const labels: Record<string, string> = {
    approved: 'Aprobada',
    'needs-review': 'Pendiente de revisión',
    pending: 'Pendiente de revisión',
    rejected: 'Rechazada',
    blocked: 'Bloqueada',
    allowed: 'Permitido',
    disallowed: 'No permitido',
    reviewed: 'Revisada',
    'not-applicable': 'No aplica',
    unknown: 'Sin información',
  }
  return labels[normalized] ?? safeOperationalText(value, fallback)
}

function policyStatusLabel(value: unknown, fallback: string) {
  if (typeof value === 'number') {
    return ({
      0: 'Pendiente de revisión',
      1: 'Aprobada',
      2: 'Rechazada',
      3: 'No aplica',
    } as Record<number, string>)[value] ?? fallback
  }
  return typeof value === 'string' ? complianceLabel(value, fallback) : fallback
}

function publicationStatusLabel(value: unknown, fallback: string) {
  if (typeof value === 'number') {
    return ({
      0: 'Borrador',
      1: 'En revisión',
      2: 'Publicada',
      3: 'Rechazada',
      4: 'Desactivada',
    } as Record<number, string>)[value] ?? fallback
  }
  return typeof value === 'string' && value.trim()
    ? safeOperationalText(value, fallback)
    : fallback
}

function dedupeDecisionCode(value: JsonRecord) {
  const decision = firstValue(value, ['decisionCode', 'decision'])
  if (decision === 1) return 'keep-separate'
  if (decision === 2) return 'mark-duplicate'
  if (decision === 3) return 'ignored'
  return typeof decision === 'string'
    ? decision.trim().toLowerCase().replace(/[_\s]+/g, '-').slice(0, 100)
    : null
}

function matchKindLabel(value: JsonRecord) {
  const kind = firstValue(value, ['matchKind', 'matchType'])
  if (kind === 0) return 'Huella de contenido exacta'
  if (kind === 1) return 'URL canónica coincidente'
  if (kind === 2) return 'Título y organismo normalizados'
  return typeof kind === 'string' && kind.trim()
    ? safeOperationalText(kind, 'Coincidencia sugerida')
    : 'Coincidencia sugerida'
}

function dedupeStatus(value: JsonRecord): ImportDedupeStatus {
  const raw = firstValue(value, ['dedupeStatus', 'duplicateStatus', 'deduplicationStatus'])
  if (typeof raw === 'number') {
    const byCode: Record<number, ImportDedupeStatus> = {
      0: 'not-evaluated',
      1: 'possible-duplicate',
      2: 'keep-separate',
      3: 'marked-duplicate',
      4: 'not-applicable',
    }
    return byCode[raw] ?? 'unknown'
  }
  if (typeof raw !== 'string') return 'not-evaluated'
  const normalized = raw.trim().toLowerCase().replace(/[_\s]+/g, '-')
  const aliases: Record<string, ImportDedupeStatus> = {
    none: 'not-evaluated',
    pending: 'possible-duplicate',
    'not-evaluated': 'not-evaluated',
    'possible-duplicate': 'possible-duplicate',
    'candidate-duplicate': 'possible-duplicate',
    distinct: 'keep-separate',
    'keep-separate': 'keep-separate',
    duplicate: 'marked-duplicate',
    'confirmed-duplicate': 'marked-duplicate',
    'mark-duplicate': 'marked-duplicate',
    'marked-duplicate': 'marked-duplicate',
    ignored: 'ignored',
    ignore: 'ignored',
    'not-applicable': 'not-applicable',
  }
  return aliases[normalized] ?? 'unknown'
}

export function mapFundingSource(value: unknown): AdminFundingSourceView {
  const source = recordValue(value, 'funding-source')
  const id = numberValue(source, ['id', 'sourceId', 'fundingSourceId'])
  const name = stringValue(source, ['name', 'sourceName'], 'Fuente sin nombre')
  const providerType = numberValue(source, ['providerType'])
  const providerCode = normalizeProviderCode(
    stringValue(source, ['providerCode'], providerType === 1 ? 'api' : 'unknown'),
  )
  const baseUrl = safeSourceUrl(nullableString(source, ['baseUrl']))
  const isEnabled = booleanValue(source, ['isEnabled', 'enabled'])
  const suppliedStatus = stringValue(source, ['operationalStatus', 'status'])
  const termsReviewed = nullableString(source, ['termsReviewedAtUtc'])
  const robotsReviewed = nullableString(source, ['robotsReviewedAtUtc'])
  const suppliedCompliance = stringValue(source, ['complianceStatus', 'compliance'])
  const licenseName = stringValue(source, ['licenseName', 'licenseCode', 'license'], 'No informada')
  const suppliedLicenseStatus = firstValue(source, ['licenseStatus', 'licenseComplianceStatus'])
  const allowedHostCount = nullableNumber(source, ['allowedHostCount', 'enabledAllowedHostCount'])
  const suppliedAllowlisted = nullableBoolean(source, ['isAllowlisted', 'isHostAllowlisted', 'allowlisted'])
  const isAllowlisted = suppliedAllowlisted ?? (allowedHostCount === null ? null : allowedHostCount > 0)
  const allowlistRequired = nullableBoolean(source, ['allowlistRequired', 'allowedHostsRequired'])
  const suppliedAllowlistStatus = stringValue(source, ['allowlistStatus', 'hostAllowlistStatus'])
  const robotsStatus = firstValue(source, ['robotsPolicyStatus', 'robotsStatus'])
  const rssFeedUrl = nullableString(source, ['rssFeedUrl', 'feedUrl'])
  const grantsSignature = `${providerCode} ${name} ${baseUrl ?? ''}`.toLowerCase()
  const rssSignature = `${providerCode} ${name} ${rssFeedUrl ?? ''}`.toLowerCase()
  const isRssProvider = booleanValue(source, ['isRssProvider'])
    || providerType === 2
    || rssSignature.includes('rss')

  return {
    id,
    name,
    providerType,
    providerCode,
    baseUrl,
    isEnabled,
    operationalStatus: safeOperationalText(suppliedStatus, isEnabled ? 'Activa' : 'Pausada'),
    complianceStatus: complianceLabel(
      suppliedCompliance,
      termsReviewed && robotsReviewed ? 'Revisada' : 'Pendiente de revisión',
    ),
    lastSuccessfulRunAtUtc: nullableString(source, ['lastSuccessfulRunAtUtc', 'lastSuccessAtUtc']),
    nextScheduledRunAtUtc: nullableString(source, ['nextScheduledRunAtUtc', 'nextRunAtUtc']),
    scheduleCron: nullableString(source, ['scheduleCron']),
    isGrantsGov: grantsSignature.includes('grants-gov') || grantsSignature.includes('grants.gov'),
    licenseName: safeOperationalText(licenseName, 'No informada'),
    licenseUrl: safePublicUrl(nullableString(source, ['licenseUrl', 'termsUrl'])),
    licenseStatus: policyStatusLabel(suppliedLicenseStatus, 'Pendiente de revisión'),
    isAllowlisted,
    allowlistRequired,
    allowedHostCount,
    allowlistStatus: safeOperationalText(
      suppliedAllowlistStatus,
      allowlistRequired === false
        ? 'No requerida'
        : isAllowlisted === true ? 'Autorizada' : isAllowlisted === false ? 'No autorizada' : 'Sin información',
    ),
    rateLimitPerMinute: nullableNumber(source, ['rateLimitPerMinute', 'requestRateLimitPerMinute', 'maxRequestsPerMinute', 'requestsPerMinute']),
    minimumRequestIntervalSeconds: nullableNumber(source, ['minimumRequestIntervalSeconds', 'requestIntervalSeconds', 'minimumDelaySeconds']),
    robotsPolicyStatus: policyStatusLabel(robotsStatus, 'Pendiente de revisión'),
    robotsReviewedAtUtc: nullableString(source, ['robotsReviewedAtUtc', 'robotsCheckedAtUtc']),
    acquisitionReady: nullableBoolean(source, ['acquisitionReady']),
    isRssProvider,
    rssFeedHost: isRssProvider ? safeHost(rssFeedUrl ?? baseUrl) : null,
  }
}

export function mapImportRunStatus(statusCode: number): ImportRunStatus {
  return statusNames[statusCode] ?? 'unknown'
}

function mapRunSummary(value: unknown): ImportRunSummary {
  const run = recordValue(value, 'import-run')
  const statusCode = numberValue(run, ['status'])
  return {
    runId: stringValue(run, ['runId', 'id']),
    fundingSourceId: numberValue(run, ['fundingSourceId', 'sourceId']),
    sourceName: stringValue(run, ['sourceName'], 'Fuente'),
    providerCode: normalizeProviderCode(stringValue(run, ['providerCode'], 'unknown')),
    triggerType: numberValue(run, ['triggerType']),
    statusCode,
    status: mapImportRunStatus(statusCode),
    keyword: stringValue(run, ['keyword']),
    maximumResults: numberValue(run, ['maximumResults']),
    retrievedCount: numberValue(run, ['retrievedCount']),
    createdCount: numberValue(run, ['createdCount']),
    updatedCount: numberValue(run, ['updatedCount']),
    unchangedCount: numberValue(run, ['unchangedCount']),
    stagedForReviewCount: numberValue(run, ['stagedForReviewCount']),
    failedCount: numberValue(run, ['failedCount']),
    createdAtUtc: stringValue(run, ['createdAtUtc']),
    startedAtUtc: nullableString(run, ['startedAtUtc']),
    completedAtUtc: nullableString(run, ['completedAtUtc']),
    lastErrorCode: nullableString(run, ['lastErrorCode']),
  }
}

function mapRunItem(value: unknown): ImportRunItem {
  const item = recordValue(value, 'import-run-item')
  const opportunityId = nullablePublicId(item, ['opportunityId'])
  const duplicateOfOpportunityId = nullablePublicId(item, ['duplicateOfOpportunityId', 'suggestedCanonicalOpportunityId', 'suggestedCanonicalOpportunityPublicId', 'matchedOpportunityId', 'existingOpportunityId'])
  const dedupeCandidateId = nullablePublicId(item, ['dedupeCandidateId', 'duplicateCandidateId', 'duplicateCandidatePublicId'])
  const itemDedupeStatus = dedupeStatus(item)
  const itemDecision = dedupeDecisionCode(item) ?? dedupeDecisionCode({
    decision: firstValue(item, ['duplicateDecision']),
  })
  const inferredDedupeStatus = itemDecision === 'mark-duplicate'
    ? 'marked-duplicate'
    : itemDecision === 'keep-separate'
      ? 'keep-separate'
      : itemDecision === 'ignored'
        ? 'ignored'
        : dedupeCandidateId !== null
          || duplicateOfOpportunityId !== null
          || booleanValue(item, ['hasPossibleDuplicate'])
          ? 'possible-duplicate'
          : itemDedupeStatus
  return {
    itemId: stringValue(item, ['itemId']),
    dedupeCandidateId,
    opportunityId,
    candidateOpportunityId: nullablePublicId(item, ['candidateOpportunityId', 'candidateOpportunityPublicId', 'candidateId']) ?? opportunityId,
    duplicateOfOpportunityId,
    externalId: stringValue(item, ['externalId'], 'Sin referencia'),
    statusCode: numberValue(item, ['status']),
    outcomeCode: nullableString(item, ['outcomeCode']),
    decisionCode: itemDecision,
    decisionReasonCode: nullableString(item, ['decisionReasonCode', 'dedupeReasonCode']),
    dedupeStatus: inferredDedupeStatus,
    requiresEditorialReview: booleanValue(item, ['requiresEditorialReview'], true),
    isAutoPublished: booleanValue(item, ['isAutoPublished', 'autoPublished', 'isPublished'], false),
    createdAtUtc: stringValue(item, ['createdAtUtc']),
    completedAtUtc: nullableString(item, ['completedAtUtc']),
  }
}

function mapCandidatePreview(value: unknown, context: string): ImportCandidatePreview {
  const candidate = isRecord(value) ? value : {}
  const rawStatus = firstValue(candidate, ['statusLabel', 'publicationStatus'])
  return {
    opportunityId: nullablePublicId(candidate, ['opportunityId', 'opportunityPublicId', 'id']),
    title: safeOperationalText(stringValue(candidate, ['title'], 'Sin título informado'), 'Sin título informado'),
    sponsorName: safeOperationalText(stringValue(candidate, ['sponsorName', 'sponsor'], 'Sin organismo informado'), 'Sin organismo informado'),
    closeDate: nullableString(candidate, ['closeDate', 'closeAtUtc', 'deadline']),
    statusLabel: publicationStatusLabel(rawStatus, context),
  }
}

function mapFlatCandidatePreview(
  value: JsonRecord,
  kind: 'candidate' | 'existing',
): ImportCandidatePreview {
  const aliases = kind === 'candidate'
    ? {
        id: ['candidateOpportunityId', 'candidateOpportunityPublicId', 'opportunityId'],
        title: ['candidateTitle', 'opportunityTitle'],
        sponsor: ['candidateSponsorName', 'candidateSponsor'],
        close: ['candidateCloseDate', 'candidateCloseAtUtc'],
        status: ['candidateStatusLabel', 'candidatePublicationStatus'],
      }
    : {
        id: ['existingOpportunityId', 'suggestedCanonicalOpportunityId', 'suggestedCanonicalOpportunityPublicId', 'decidedCanonicalOpportunityPublicId', 'duplicateOfOpportunityId'],
        title: ['existingTitle', 'suggestedTitle', 'suggestedCanonicalTitle', 'canonicalTitle'],
        sponsor: ['existingSponsorName', 'suggestedSponsorName', 'suggestedCanonicalSponsor', 'canonicalSponsorName'],
        close: ['existingCloseDate', 'suggestedCloseDate', 'canonicalCloseDate'],
        status: ['existingStatusLabel', 'suggestedStatusLabel', 'suggestedCanonicalPublicationStatus', 'canonicalPublicationStatus'],
      }
  const rawStatus = firstValue(value, aliases.status)
  return {
    opportunityId: nullablePublicId(value, aliases.id),
    title: safeOperationalText(stringValue(value, aliases.title, 'Sin título informado'), 'Sin título informado'),
    sponsorName: safeOperationalText(stringValue(value, aliases.sponsor, 'Sin organismo informado'), 'Sin organismo informado'),
    closeDate: nullableString(value, aliases.close),
    statusLabel: publicationStatusLabel(rawStatus, kind === 'candidate' ? 'Candidato' : 'Existente'),
  }
}

export function mapImportDedupeComparison(value: unknown): ImportDedupeComparison {
  const comparison = recordValue(value, 'import-dedupe-comparison')
  const confidence = nullableNumber(comparison, ['confidence', 'matchConfidence'])
  const evidenceSummary = nullableString(comparison, ['evidenceSummary', 'matchSummary'])
  const candidateValue = firstValue(comparison, ['candidate', 'incoming', 'candidatePreview'])
  const existingValue = firstValue(comparison, ['existing', 'match', 'existingPreview', 'suggested', 'suggestedCanonical'])
  const decisionValue = firstValue(comparison, ['decisionView', 'decision'])
  const decisionRecord = isRecord(decisionValue) ? decisionValue : comparison
  const decision = dedupeDecisionCode(decisionRecord)
  const flatSuggestedId = nullablePublicId(comparison, ['existingOpportunityId', 'suggestedCanonicalOpportunityId', 'suggestedCanonicalOpportunityPublicId', 'duplicateOfOpportunityId'])
  const nestedSuggestedId = isRecord(existingValue)
    ? nullablePublicId(existingValue, ['opportunityId', 'opportunityPublicId', 'id'])
    : null
  const suggestedId = nestedSuggestedId ?? flatSuggestedId
  const mappedStatus = dedupeStatus(comparison)
  const inferredStatus = mappedStatus === 'not-evaluated'
    ? decision === 'mark-duplicate'
      ? 'marked-duplicate'
      : decision === 'keep-separate'
        ? 'keep-separate'
        : decision === 'ignored'
          ? 'ignored'
        : suggestedId ? 'possible-duplicate' : mappedStatus
    : mappedStatus
  return {
    candidateId: stringValue(comparison, ['candidateId', 'candidatePublicId']),
    runId: stringValue(comparison, ['runId']),
    itemId: stringValue(comparison, ['itemId']),
    dedupeStatus: inferredStatus,
    candidate: isRecord(candidateValue)
      ? mapCandidatePreview(candidateValue, 'Candidato')
      : mapFlatCandidatePreview(comparison, 'candidate'),
    existing: isRecord(existingValue)
      ? mapCandidatePreview(existingValue, 'Existente')
      : mapFlatCandidatePreview(comparison, 'existing'),
    decisionCode: decision,
    decisionReason: nullableString(decisionRecord, ['decisionReason', 'reason']),
    matchKind: matchKindLabel(comparison),
    confidence: confidence !== null && confidence >= 0 && confidence <= 1 ? confidence : null,
    evidenceSummary: evidenceSummary
      ? safeOperationalText(evidenceSummary, 'Evidencia disponible')
      : null,
    eTag: stringValue(comparison, ['eTag', 'etag']),
    canDecide: booleanValue(
      comparison,
      ['canDecide'],
      numberValue(comparison, ['status'], decision ? 1 : 0) === 0 && decision === null,
    ),
  }
}

function mapImportDedupeDecisionResult(value: unknown): ImportDedupeDecisionResult {
  const result = recordValue(value, 'import-dedupe-decision')
  const decisionCode = dedupeDecisionCode(result) ?? ''
  const mappedStatus = dedupeStatus(result)
  return {
    candidateId: stringValue(result, ['candidateId', 'candidatePublicId']),
    runId: stringValue(result, ['runId']),
    itemId: stringValue(result, ['itemId']),
    dedupeStatus: mappedStatus === 'not-evaluated'
      ? decisionCode === 'mark-duplicate'
        ? 'marked-duplicate'
        : decisionCode === 'keep-separate'
          ? 'keep-separate'
          : decisionCode === 'ignored' ? 'ignored' : mappedStatus
      : mappedStatus,
    decisionCode,
    decisionReason: nullableString(result, ['decisionReason', 'reason']),
    eTag: stringValue(result, ['eTag', 'etag']),
    wasReplay: booleanValue(result, ['wasReplay']),
    isPublished: booleanValue(result, ['isPublished', 'autoPublished'], false),
  }
}

function mapRunError(value: unknown): ImportRunError {
  const error = recordValue(value, 'import-run-error')
  return {
    errorId: stringValue(error, ['errorId']),
    itemId: nullableString(error, ['itemId']),
    stage: safeOperationalText(stringValue(error, ['stage']), 'Procesamiento'),
    code: safeOperationalText(stringValue(error, ['code']), 'import-error'),
    message: safeOperationalText(
      stringValue(error, ['message']),
      'La fuente no pudo procesar este registro.',
    ),
    isRetryable: booleanValue(error, ['isRetryable']),
    occurredAtUtc: stringValue(error, ['occurredAtUtc']),
  }
}

export function mapImportRunPage(value: unknown): ImportRunPage {
  const page = recordValue(value, 'import-run-list')
  const items = Array.isArray(page.items) ? page.items.map(mapRunSummary) : []
  return {
    items,
    totalCount: numberValue(page, ['totalCount'], items.length),
    page: numberValue(page, ['page'], 1),
    pageSize: numberValue(page, ['pageSize'], 20),
  }
}

export function mapImportRunDetail(value: unknown): ImportRunDetail {
  const detail = recordValue(value, 'import-run-detail')
  return {
    ...mapRunSummary(detail),
    attemptCount: numberValue(detail, ['attemptCount']),
    items: Array.isArray(detail.items) ? detail.items.map(mapRunItem) : [],
    errors: Array.isArray(detail.errors) ? detail.errors.map(mapRunError) : [],
  }
}

function mapAccepted(value: unknown): ImportRunAccepted {
  const accepted = recordValue(value, 'import-run-accepted')
  const statusCode = numberValue(accepted, ['status'])
  return {
    runId: stringValue(accepted, ['runId']),
    fundingSourceId: numberValue(accepted, ['fundingSourceId', 'sourceId']),
    sourceName: stringValue(accepted, ['sourceName'], 'Grants.gov'),
    statusCode,
    status: mapImportRunStatus(statusCode),
    createdAtUtc: stringValue(accepted, ['createdAtUtc']),
    wasReplay: booleanValue(accepted, ['wasReplay']),
    statusUrl: stringValue(accepted, ['statusUrl']),
  }
}

export const adminImportApi = {
  async listSources(signal?: AbortSignal) {
    const response = await apiClient.get<unknown>('admin/funding-sources', {
      cache: 'no-store',
      signal,
    })
    const values = Array.isArray(response)
      ? response
      : isRecord(response) && Array.isArray(response.items) ? response.items : []
    return values.map(mapFundingSource).filter((source) => source.id > 0)
  },

  async list(filters: ImportRunFilters, signal?: AbortSignal) {
    const query = new URLSearchParams({
      page: String(filters.page),
      pageSize: String(filters.pageSize),
    })
    if (filters.sourceId) query.set('sourceId', String(filters.sourceId))
    if (filters.status !== undefined) query.set('status', String(filters.status))
    const response = await apiClient.get<unknown>(`admin/import-runs?${query}`, {
      cache: 'no-store',
      signal,
    })
    return mapImportRunPage(response)
  },

  async create(sourceId: number, input: CreateImportRunInput, idempotencyKey: string) {
    const response = await apiClient.post<unknown>(
      `admin/funding-sources/${sourceId}/import-runs`,
      input,
      {
        cache: 'no-store',
        headers: { 'Idempotency-Key': idempotencyKey },
      },
    )
    return mapAccepted(response)
  },

  async get(runId: string, signal?: AbortSignal) {
    const response = await apiClient.get<unknown>(
      `admin/import-runs/${encodeURIComponent(runId)}`,
      { cache: 'no-store', signal },
    )
    return mapImportRunDetail(response)
  },

  async getDedupe(candidateId: string, signal?: AbortSignal) {
    const response = await apiClient.get<unknown>(
      `admin/funding-duplicate-candidates/${encodeURIComponent(candidateId)}`,
      { cache: 'no-store', signal },
    )
    return mapImportDedupeComparison(response)
  },

  async decideDedupe(
    candidateId: string,
    input: DecideImportDedupeInput,
    eTag: string,
    idempotencyKey: string,
  ) {
    const reason = input.reason.trim()
    if (reason.length < 3 || /[\r\n]/.test(reason)) {
      throw new Error('dedupe-reason-required')
    }
    if (reason.length > 300) throw new Error('dedupe-reason-too-long')
    if (input.decision === 'mark-duplicate' && !input.canonicalOpportunityId) {
      throw new Error('duplicate-target-required')
    }
    if (input.decision !== 'mark-duplicate' && input.canonicalOpportunityId) {
      throw new Error('unexpected-duplicate-target')
    }
    const response = await apiClient.post<unknown>(
      `admin/funding-duplicate-candidates/${encodeURIComponent(candidateId)}/decisions`,
      { ...input, reason },
      {
        cache: 'no-store',
        headers: { 'If-Match': eTag, 'Idempotency-Key': idempotencyKey },
      },
    )
    return mapImportDedupeDecisionResult(response)
  },
}

export function importAdminErrorMessage(error: unknown) {
  if (error instanceof ApiError) {
    if (error.response.status === 401) {
      return 'La sesión venció. Inicia sesión nuevamente.'
    }
    if (error.response.status === 403) {
      return 'Necesitas una sesión administrativa con MFA reciente para operar importaciones.'
    }
    if (error.response.status === 429) {
      return 'Se alcanzó el límite temporal de importaciones. Intenta nuevamente más tarde.'
    }
    if (error.response.status === 409 || error.response.status === 412) {
      return 'El contenido cambió mientras lo revisabas. Recarga la comparación e intenta nuevamente.'
    }
    if (error.response.status === 422) {
      return 'La solicitud no es válida para el estado actual. Revisa los datos e intenta nuevamente.'
    }
    return safeOperationalText(
      error.problem.detail ?? error.problem.title,
      'No fue posible completar la operación de importación.',
    )
  }
  return 'No fue posible completar la operación de importación.'
}

export function isImportRunActive(run: Pick<ImportRunSummary, 'status'>) {
  return run.status === 'queued' || run.status === 'running'
}

export function shouldPollImportRuns(items: Array<Pick<ImportRunSummary, 'status'>>) {
  return items.some(isImportRunActive)
}
