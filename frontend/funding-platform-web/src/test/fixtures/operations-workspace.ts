import type { AdminOrganizationDetail } from '@/features/admin-organizations/admin-organizations-api'
import type { AdminUserSummary } from '@/features/admin-users/admin-users-api'
import type { AdminOperationalError } from '@/features/admin-errors/admin-errors-api'
import type { AdminBillingDashboard, AdminSubscriptionPage } from '@/features/billing/billing-api'
import type { SourceDocumentStatusResponse, UploadIntentStatusResponse } from '@/features/source-documents/source-document-api'
import { editorialFunder, editorialOpportunity, editorialProjectQueueItem } from './editorial-workspace'

// Synthetic, inert fixtures. No live accounts, scans, provider calls or secrets.
export const operationsIds = {
  organization: '11111111-1111-4111-8111-111111111111',
  user: '22222222-2222-4222-8222-222222222222',
  run: '33333333-3333-4333-8333-333333333333',
  item: '44444444-4444-4444-8444-444444444444',
  candidate: '55555555-5555-4555-8555-555555555555',
  document: '66666666-6666-4666-8666-666666666666',
  intent: '77777777-7777-4777-8777-777777777777',
} as const
export const operationsDate = '2026-09-01T12:00:00Z'
export const operationsETag = '"0000000000000007"'

export const operationsUser = {
  publicId: operationsIds.user, email: 'operator@example.invalid', displayName: 'Operadora Ñandú',
  preferredLocale: 'pt-BR', status: 'PendingVerification', emailConfirmed: false,
  mfaEnabled: true, lastLoginAtUtc: null, createdAtUtc: operationsDate, roles: ['Admin'],
} satisfies AdminUserSummary

export const operationsOrganization = {
  publicId: operationsIds.organization, name: 'Organización Ñandú', countryCode: 'CL', countryName: 'Chile',
  organizationTypeName: 'Fundación local', profileStatus: 1, profileCompleteness: 75,
  isActive: true, memberCount: 7, projectCount: 2, planCode: 'FREE', planName: 'Plan original',
  subscriptionStatus: 0, createdAtUtc: operationsDate, updatedAtUtc: operationsDate,
  legalName: 'Nombre legal original', legalEntityTypeName: 'Corporación original',
  organizationSizeName: '11-50', establishedYear: 2020, websiteUrl: 'https://organization.example.invalid',
  description: 'Descripción original de la organización.', profileVersion: 3,
  adminMemberCount: 2, publishedProjectCount: 1, currentPeriodEndUtc: null,
} satisfies AdminOrganizationDetail

export const operationsIncident = {
  id: 'incident-synthetic', category: 'extraction', severity: 2, code: 'pdf-invalid',
  message: 'Diagnóstico sanitizado original.', isRetryable: false, occurredAtUtc: operationsDate,
  relatedResourcePublicId: operationsIds.intent, sourceName: 'Boletín Ñandú',
} satisfies AdminOperationalError

export const operationsSource = {
  id: 9, name: 'Grants.gov Ñandú', providerType: 1, providerCode: 'grants-gov',
  baseUrl: 'https://grants.example.invalid', isEnabled: true,
  operationalStatus: 'Saludable', complianceStatus: 'approved', licenseName: 'Licencia original',
  licenseUrl: null, licenseStatus: 'reviewed', isAllowlisted: true, allowlistRequired: false,
  allowedHostCount: 1, rateLimitPerMinute: 10, minimumRequestIntervalSeconds: 2,
  robotsPolicyStatus: 'Permitido', robotsReviewedAtUtc: operationsDate, acquisitionReady: false,
  lastSuccessfulRunAtUtc: operationsDate, nextScheduledRunAtUtc: null, scheduleCron: null,
}
export const operationsPdfSource = { id: 10, name: 'Boletín Ñandú', providerType: 4, isEnabled: true, baseUrl: null }

export const operationsRun = {
  runId: operationsIds.run, fundingSourceId: 9, sourceName: operationsSource.name, providerCode: 'grants-gov',
  triggerType: 1, status: 2, keyword: 'agua Ñandú', maximumResults: 25, retrievedCount: 3,
  createdCount: 0, updatedCount: 0, unchangedCount: 1, stagedForReviewCount: 2, failedCount: 0,
  createdAtUtc: operationsDate, startedAtUtc: operationsDate, completedAtUtc: operationsDate, lastErrorCode: null,
}
export const operationsRunDetail = {
  ...operationsRun, attemptCount: 1,
  items: [{
    itemId: operationsIds.item, dedupeCandidateId: operationsIds.candidate,
    opportunityId: editorialOpportunity().opportunityId, externalId: 'GRANT-ÑANDÚ-001',
    status: 2, outcomeCode: 'staged-for-review', dedupeStatus: 'possible-duplicate',
    requiresEditorialReview: true, isAutoPublished: false, createdAtUtc: operationsDate, completedAtUtc: operationsDate,
  }],
  errors: [{
    errorId: 'synthetic-error', itemId: null, stage: 'normalize', code: 'missing-field',
    message: 'Diagnóstico sanitizado original.', isRetryable: false, occurredAtUtc: operationsDate,
  }],
}
export const operationsComparison = {
  candidateId: operationsIds.candidate, runId: operationsIds.run, itemId: operationsIds.item,
  dedupeStatus: 'possible-duplicate',
  candidate: { opportunityId: editorialOpportunity().opportunityId, title: 'Candidato Ñandú', sponsorName: 'Organismo original', closeDate: '2027-01-31', statusLabel: 'Borrador' },
  existing: { opportunityId: '88888888-8888-4888-8888-888888888888', title: 'Fondo existente', sponsorName: 'Organismo original', closeDate: '2027-01-31', statusLabel: 'Publicada' },
  decisionCode: null, decisionReason: null, matchKind: 'exact-content-fingerprint', confidence: 0.95,
  evidenceSummary: 'Evidencia original sanitizada.', eTag: operationsETag, canDecide: true,
}

export function operationsDocument(overrides: Partial<SourceDocumentStatusResponse> = {}): SourceDocumentStatusResponse {
  return {
    sourceDocumentId: operationsIds.document, fundingSourceId: 10, fundingSourceName: operationsPdfSource.name,
    fileName: 'bases-Ñandú.pdf', mimeType: 'application/pdf', contentLength: 2048,
    storageStatus: 2, scanStatus: 1, scanProvider: 0, isProductionScan: false, scanAttemptCount: 1,
    scanResultCode: 'clean-development', scanStartedAtUtc: operationsDate, scanCompletedAtUtc: operationsDate,
    extractionStatus: 0, extractionJobId: null, extractionAttemptCount: 0, extractionMaxAttempts: 3,
    extractedPageCount: null, extractedCharacterCount: null, extractionEvidenceCount: 0, extractionErrorCount: 0,
    extractionResultCode: null, isContentRedacted: false, redactedAtUtc: null,
    extractionStartedAtUtc: null, extractionCompletedAtUtc: null, uploadedByUserId: operationsIds.user,
    createdAtUtc: operationsDate, updatedAtUtc: operationsDate, eTag: operationsETag,
    ...overrides,
  }
}
export const operationsIntent = {
  intentId: operationsIds.intent, fundingSourceId: 10, fundingSourceName: operationsPdfSource.name,
  fileName: 'bases-Ñandú.pdf', mimeType: 'application/pdf', expectedContentLength: 2048,
  maxContentLength: 26_214_400, status: 2, expiresAtUtc: '2099-01-01T00:00:00Z',
  sourceDocumentId: operationsIds.document, storageStatus: 2, scanStatus: 1, scanProvider: 0,
  scanResultCode: 'clean-development', createdAtUtc: operationsDate, completedAtUtc: operationsDate,
  updatedAtUtc: operationsDate, eTag: operationsETag, isDevelopmentScan: true,
} satisfies UploadIntentStatusResponse

export const operationsBilling = {
  activeOrganizations: 12, activePaidSubscriptions: 4, pastDueSubscriptions: 1,
  pendingCheckouts: 2, failedWebhookEvents: 1, monthlyRecurringRevenueClp: 40000, generatedAtUtc: operationsDate,
} satisfies AdminBillingDashboard
export const operationsSubscriptions = {
  items: [{
    organizationId: operationsIds.organization, organizationName: operationsOrganization.name,
    planCode: 'PRO', planName: 'Plan original', status: 'pastdue',
    currentPeriodEndUtc: '2027-01-31T12:00:00Z', cancelAtPeriodEnd: false,
    provider: 'synthetic', providerSubscriptionReference: 'PRIVATE-PROVIDER-REFERENCE', updatedAtUtc: operationsDate,
  }], totalCount: 1, page: 1, pageSize: 20,
} satisfies AdminSubscriptionPage

export function operationsPage<T>(items: T[], page = 1, pageSize = 25, totalCount = 51) {
  return { items, page, pageSize, totalCount }
}

// Keys are exact URL pathnames; query parameters are tested separately.
export const operationsFixtures: Record<string, unknown> = {
  '/admin/users': operationsPage([operationsUser]),
  '/admin/organizations': operationsPage([operationsOrganization]),
  ['/admin/organizations/' + operationsIds.organization]: operationsOrganization,
  '/admin/operational-errors': operationsPage([operationsIncident]),
  '/admin/funding-sources': [operationsSource, operationsPdfSource],
  '/admin/import-runs': operationsPage([operationsRun], 1, 20),
  ['/admin/import-runs/' + operationsIds.run]: operationsRunDetail,
  ['/admin/funding-duplicate-candidates/' + operationsIds.candidate]: operationsComparison,
  ['/admin/source-document-upload-intents/' + operationsIds.intent]: operationsIntent,
  ['/admin/source-documents/' + operationsIds.document]: operationsDocument(),
  '/admin/dashboard': operationsBilling,
  '/admin/subscriptions': operationsSubscriptions,
  '/admin/funders': operationsPage([editorialFunder()], 1, 1),
  '/admin/funding-opportunities': operationsPage([editorialOpportunity()], 1, 1),
  '/admin/projects/review-queue': operationsPage([editorialProjectQueueItem], 1, 5),
}
