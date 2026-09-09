import { ApiError } from '@/api/http-client'
import type { ApplicationStatus } from '@/features/applications/application-api'
import i18n from '@/i18n'
import { alertsEs } from '@/i18n/alerts/es'
import { billingEs } from '@/i18n/billing/es'

export type TrackingFeedback = { key:
  | 'alerts.saved' | 'alerts.savedWithAlert' | 'alerts.savedEmailDisabled' | 'alerts.savedEmailUncertain'
  | 'alerts.removed' | 'alerts.disabled' | 'alerts.enabled'
  | 'billing.checkoutCreated' | 'billing.renewalUpdated'
} | { error: unknown }

const statusKeys = {
  0: 'dashboard.statusInterested', 1: 'dashboard.statusPreparing', 2: 'dashboard.statusSubmitted',
  3: 'dashboard.statusAwarded', 4: 'dashboard.statusNotAwarded', 5: 'dashboard.statusDiscarded',
} as const satisfies Record<ApplicationStatus, string>

function ownKey<T extends object>(object: T, key: string): key is Extract<keyof T, string> {
  return Object.prototype.hasOwnProperty.call(object, key)
}

export function applicationStatusLabel(status: ApplicationStatus) {
  return i18n.t(statusKeys[status] ?? 'tracking.unknown')
}

export function notificationStatusLabel(status: string) {
  return ownKey(alertsEs.statuses, status) ? i18n.t(`alerts.statuses.${status}`) : i18n.t('tracking.unknown')
}

export function subscriptionStatusLabel(status: string) {
  return ownKey(billingEs.statuses, status) ? i18n.t(`billing.statuses.${status}`) : i18n.t('tracking.unknown')
}

export function checkoutStatusLabel(status: string) {
  return ownKey(billingEs.checkoutStatuses, status) ? i18n.t(`billing.checkoutStatuses.${status}`) : i18n.t('tracking.unknown')
}

export function trackingErrorMessage(error: unknown, scope: 'applications' | 'calendar' | 'alerts' | 'billing', operation: 'read' | 'write' = 'read') {
  if (error instanceof ApiError) {
    const { status } = error.response
    const type = error.problem.type
    const base = 'https://fundingplatform.local/problems/'
    if (status === 401) return i18n.t('tracking.sessionExpired')
    if (status === 403) return i18n.t('tracking.forbidden')
    if ([404, 410].includes(status)) return i18n.t(scope === 'applications' ? 'applications.notFound' : 'tracking.notFound')
    if (status === 429) return i18n.t('tracking.rateLimited')
    if (status === 409 && type === base + 'idempotency-conflict') return i18n.t('tracking.idempotency')
    if (scope === 'applications') {
      if (status === 412) return i18n.t('applications.concurrency')
      if (status === 409 && type === base + 'funding-application-conflict') return i18n.t('applications.duplicate')
    }
    if (scope === 'alerts' && status === 503 && type === base + 'alerts-disabled') return i18n.t('alerts.emailDisabled')
    if (scope === 'billing') {
      if (status === 503 && type === base + 'billing-disabled') return i18n.t('billing.disabled')
      if (status === 503 && type === base + 'payment-provider-unavailable') return i18n.t('billing.providerUnavailable')
      if (status === 409 && type === base + 'checkout-already-open') return i18n.t('billing.alreadyOpen')
      if (status === 409 && type === base + 'subscription-invalid-transition') return i18n.t('billing.invalidTransition')
    }
    if ([400, 422].includes(status)) return i18n.t('tracking.invalid')
    if ([409, 412].includes(status)) return i18n.t('tracking.conflict')
    if (status === 428) return i18n.t('tracking.precondition')
    if (status >= 500) return i18n.t(operation === 'read' ? 'tracking.unavailable' : 'tracking.writeUncertain')
  }
  // API diagnostics and validation payloads are not presentation strings.
  return i18n.t(operation === 'read' ? 'tracking.loadHelp' : 'tracking.writeUncertain')
}
