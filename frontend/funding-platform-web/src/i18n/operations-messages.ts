import { ApiError } from '@/api/http-client'
import i18n from '@/i18n'
import { DirectUploadError } from '@/features/source-documents/source-document-api'
import { operationsEs } from '@/i18n/operations/es'
import { adminDashboardEs } from '@/i18n/admin-dashboard/es'
import { adminUsersEs } from '@/i18n/admin-users/es'
import { adminOrganizationsEs } from '@/i18n/admin-organizations/es'
import { adminIncidentsEs } from '@/i18n/admin-incidents/es'
import { adminBillingEs } from '@/i18n/admin-billing/es'
import { adminImportsEs } from '@/i18n/admin-imports/es'
import { sourceDocumentsEs } from '@/i18n/source-documents/es'
import { operationalLabelsEs } from '@/i18n/operational-labels/es'

export type OperationsKey = `operations.${keyof typeof operationsEs}`
  | `adminDashboard.${keyof typeof adminDashboardEs}`
  | `adminUsers.${keyof typeof adminUsersEs}`
  | `adminOrganizations.${keyof typeof adminOrganizationsEs}`
  | `adminIncidents.${keyof typeof adminIncidentsEs}`
  | `adminBilling.${keyof typeof adminBillingEs}`
  | `adminImports.${keyof typeof adminImportsEs}`
  | `sourceDocuments.${keyof typeof sourceDocumentsEs}`
const feedbackKeys = new Map<string, OperationsKey>()
for (const [namespace, resource] of Object.entries({ operations: operationsEs, adminDashboard: adminDashboardEs, adminUsers: adminUsersEs, adminOrganizations: adminOrganizationsEs, adminIncidents: adminIncidentsEs, adminBilling: adminBillingEs, adminImports: adminImportsEs, sourceDocuments: sourceDocumentsEs })) {
  for (const [key, value] of Object.entries(resource)) {
    const resourceKey = `${namespace}.${key}` as OperationsKey
    feedbackKeys.set(resourceKey, resourceKey)
    feedbackKeys.set(value, resourceKey)
  }
}

// Feedback stays language-independent in component state. Only bundled keys or
// recognized local messages are displayed; unknown HTTP diagnostics never leak.
export function operationsMessage(value: string, options: Record<string, string | number> = {}) {
  return i18n.t(feedbackKeys.get(value) ?? 'operations.genericError', {
    ...options, defaultValue: i18n.t('operations.genericError'),
  })
}

export function importOperationsErrorKey(error: unknown): OperationsKey {
  if (error instanceof ApiError) {
    switch (error.response.status) {
      case 401: return 'operations.expired'
      case 403: return 'operations.importsMfa'
      case 429: return 'operations.importRate'
      case 409: case 412: return 'operations.importConflict'
      case 400: case 422: return 'operations.invalidState'
    }
  }
  return 'operations.importError'
}

export function documentOperationsErrorKey(error: unknown): OperationsKey {
  if (error instanceof DirectUploadError) return 'operations.directUploadError'
  if (error instanceof ApiError) {
    switch (error.response.status) {
      case 401: return 'operations.expired'
      case 403: return 'operations.documentsMfa'
      case 409: return 'operations.documentChanged'
      case 412: return 'operations.documentVersion'
      case 400: case 422: return 'operations.documentInvalid'
    }
  }
  return 'operations.documentError'
}

const operationalKeys = new Map(Object.entries(operationalLabelsEs).map(([key, value]) =>
  [value as string, `operationalLabels.${key}` as `operationalLabels.${keyof typeof operationalLabelsEs}`] as const,
))

// These are sanitized status labels, not error responses or user-authored
// descriptions. Unknown labels remain in their source language, never inferred.
export function operationalLabel(value: string) {
  const key = operationalKeys.get(value)
  return key ? i18n.t(key) : value
}

export function operationStatus(labels: Readonly<Record<string | number, string>>, value: string | number) {
  return operationsMessage(Object.hasOwn(labels, value) ? labels[value] : 'operations.unknown')
}
