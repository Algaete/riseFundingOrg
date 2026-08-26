import { apiClient } from '@/api/http-client'

export type BillingInterval = 'monthly' | 'annual'
export type SubscriptionStatus = 'free' | 'pending' | 'trialing' | 'active' | 'pastdue' | 'canceled' | 'expired'

export interface SubscriptionFeature {
  code: string
  name: string
  enabled: boolean
  limitValue: number | null
  unit: string | null
  usageValue: number
}

export interface SubscriptionPlanPrice {
  id: number
  interval: BillingInterval
  currency: string
  amount: number
  purchasable: boolean
  provider: string | null
}

export interface SubscriptionPlan {
  id: number
  code: string
  name: string
  description: string | null
  purchasable: boolean
  prices: SubscriptionPlanPrice[]
  features: SubscriptionFeature[]
}

export interface CurrentSubscription {
  organizationId: string
  planCode: string
  planName: string
  status: SubscriptionStatus
  billingInterval: BillingInterval | null
  currency: string | null
  amount: number | null
  currentPeriodStartUtc: string | null
  currentPeriodEndUtc: string | null
  cancelAtPeriodEnd: boolean
  graceUntilUtc: string | null
  freeFallback: boolean
  features: SubscriptionFeature[]
  eTag: string | null
}

export interface SubscriptionCheckout {
  id: string
  organizationId: string
  planPriceId: number
  planName: string
  interval: BillingInterval
  currency: string
  amount: number
  status: 'creating' | 'pending' | 'completed' | 'failed' | 'expired'
  provider: string
  checkoutUrl: string | null
  expiresAtUtc: string
  createdAtUtc: string
  updatedAtUtc: string
  replayed: boolean
}

export interface SubscriptionUsage {
  featureCode: string
  featureName: string
  enabled: boolean
  limitValue: number | null
  usageValue: number
  unit: string | null
  periodStartUtc: string
  periodEndUtc: string
}

export interface AdminSubscriptionPage {
  items: Array<{
    organizationId: string
    organizationName: string
    planCode: string
    planName: string
    status: SubscriptionStatus
    currentPeriodEndUtc: string | null
    cancelAtPeriodEnd: boolean
    provider: string | null
    providerSubscriptionReference: string | null
    updatedAtUtc: string
  }>
  totalCount: number
  page: number
  pageSize: number
}

export interface AdminBillingDashboard {
  activeOrganizations: number
  activePaidSubscriptions: number
  pastDueSubscriptions: number
  pendingCheckouts: number
  failedWebhookEvents: number
  monthlyRecurringRevenueClp: number
  generatedAtUtc: string
}

export function billingCommandId() {
  return crypto.randomUUID().replaceAll('-', '')
}

export const billingApi = {
  plans(signal?: AbortSignal) {
    return apiClient.get<SubscriptionPlan[]>('subscription-plans', { signal })
  },
  current(organizationId: string, signal?: AbortSignal) {
    return apiClient.get<CurrentSubscription>(
      `organizations/${encodeURIComponent(organizationId)}/subscription`,
      { signal, cache: 'no-store' },
    )
  },
  usage(organizationId: string, signal?: AbortSignal) {
    return apiClient.get<SubscriptionUsage[]>(
      `organizations/${encodeURIComponent(organizationId)}/subscription/usage`,
      { signal, cache: 'no-store' },
    )
  },
  createCheckout(organizationId: string, planPriceId: number, key: string) {
    return apiClient.post<SubscriptionCheckout>(
      `organizations/${encodeURIComponent(organizationId)}/subscription-checkouts`,
      { planPriceId }, { headers: { 'Idempotency-Key': key }, cache: 'no-store' },
    )
  },
  checkout(organizationId: string, checkoutId: string, signal?: AbortSignal) {
    return apiClient.get<SubscriptionCheckout>(
      `organizations/${encodeURIComponent(organizationId)}/subscription-checkouts/${encodeURIComponent(checkoutId)}`,
      { signal, cache: 'no-store' },
    )
  },
  cancel(organizationId: string, eTag: string) {
    return apiClient.post<CurrentSubscription>(
      `organizations/${encodeURIComponent(organizationId)}/subscription/cancel`, undefined,
      { headers: { 'If-Match': eTag }, cache: 'no-store' },
    )
  },
  resume(organizationId: string, eTag: string) {
    return apiClient.post<CurrentSubscription>(
      `organizations/${encodeURIComponent(organizationId)}/subscription/resume`, undefined,
      { headers: { 'If-Match': eTag }, cache: 'no-store' },
    )
  },
  adminList(page = 1, q = '', status = '', signal?: AbortSignal) {
    const query = new URLSearchParams({ page: String(page), pageSize: '20' })
    if (q) query.set('q', q)
    if (status) query.set('status', status)
    return apiClient.get<AdminSubscriptionPage>(`admin/subscriptions?${query}`, { signal, cache: 'no-store' })
  },
  adminDashboard(signal?: AbortSignal) {
    return apiClient.get<AdminBillingDashboard>('admin/dashboard', { signal, cache: 'no-store' })
  },
}
