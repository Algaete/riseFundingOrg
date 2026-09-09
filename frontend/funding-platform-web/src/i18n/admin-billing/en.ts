import type { adminBillingEs } from './es'
import type { TranslationShape } from '@/i18n/resource-types'

export const adminBillingEn = {
  "title": "Subscriptions",
  "intro": "Operational view without card details, secrets or provider payloads.",
  "activeOrgs": "Active NGOs",
  "activePaid": "Active paid subscriptions",
  "pastDue": "Past due",
  "pendingCheckouts": "Pending checkouts",
  "failedWebhooks": "Failed webhooks",
  "issues": "Some events require reconciliation or support.",
  "search": "Search organization",
  "free": "Free plan",
  "loadingDashboard": "Loading subscription indicators…",
  "dashboardFailed": "Subscription indicators could not be loaded.",
  "loading": "Loading subscriptions…",
  "failed": "Subscriptions could not be loaded.",
  "empty": "No subscriptions match this search."
} satisfies TranslationShape<typeof adminBillingEs>

