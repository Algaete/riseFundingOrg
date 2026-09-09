import { dashboardApplications, dashboardCalendar } from './dashboard-workspace'
import { workspaceOrganizationId } from './project-workspace'

// Synthetic fixtures only; the purchasable sandbox price below is not real configuration.
export const trackingApplication = {
  ...dashboardApplications.items[0], status: 0 as const, notes: 'Notas Ñandú',
  applicationDate: '2027-02-15', resultDate: '2027-03-01', requestedAmount: 12500.5, currency: 'USD',
}
export const trackingApplications = { items: [trackingApplication], totalCount: 25, pageNumber: 2, pageSize: 12 }
export const trackingCalendar = {
  from: '2027-02-01', to: '2027-02-28',
  items: [
    { ...dashboardCalendar.items[0], eventDate: '2027-02-15', eventAtUtc: '2027-02-15T00:00:00Z', datePrecision: 2 },
    { ...dashboardCalendar.items[0], eventKey: 'approximate', eventType: 'project-end' as const, eventDate: '2027-02-15', datePrecision: 0, fundingApplicationPublicId: null, status: null },
  ],
}
export const savedSearchFilters = {
  name: 'Agua Ñandú', query: 'agua', sponsor: null, minimumAmount: 25000, maximumAmount: 100000,
  currency: 'USD', closingFrom: '2027-02-01', closingTo: '2027-02-28', onlyOpen: false,
  sort: 'amount-desc' as const, countryIds: [152], regionIds: [7], categoryIds: [1], tagIds: [],
  beneficiaryTypeIds: [], projectTypeIds: [], fundingTypeIds: [], organizationTypeIds: [], funderIds: [],
}
export const trackingSearch = {
  id: '99999999-9999-9999-9999-999999999999', name: savedSearchFilters.name,
  query: savedSearchFilters.query, onlyOpen: false, sort: savedSearchFilters.sort, hasActiveAlert: true,
  createdAtUtc: '2027-02-01T12:00:00Z', updatedAtUtc: '2027-02-01T12:00:00Z', eTag: '"synthetic-search"',
}
export const trackingSearchDetail = { ...trackingSearch, filters: savedSearchFilters, alert: null }
export const trackingSearches = { items: [trackingSearch], totalCount: 1, page: 1, pageSize: 50 }
export const trackingNotifications = {
  items: [{
    id: 'synthetic-notification', alertSubscriptionId: 'synthetic-alert', savedSearchId: trackingSearch.id,
    savedSearchName: trackingSearch.name, status: 'retry-scheduled' as const, itemCount: 1, wasTruncated: true,
    scheduledForUtc: '2027-02-01T12:00:00Z', sentAtUtc: null, errorCode: null, createdAtUtc: '2027-02-01T12:00:00Z',
  }], totalCount: 1, page: 1, pageSize: 20,
}
export const trackingFeature = { code: 'alerts.max', name: 'Límite de alertas', enabled: true, limitValue: 20, unit: 'items', usageValue: 1 }
export const trackingPlans = [
  { id: 1, code: 'FREE', name: 'Free', description: 'Plan gratuito inicial para validar el MVP.', purchasable: false,
    prices: [{ id: 1, interval: 'monthly' as const, currency: 'CLP', amount: 0, purchasable: false, provider: null }], features: [trackingFeature] },
  { id: 2, code: 'PROFESSIONAL', name: 'Professional', description: 'Automatización y límites ampliados. Precio sandbox pendiente de aprobación.', purchasable: true,
    prices: [{ id: 2, interval: 'monthly' as const, currency: 'USD', amount: 12500.5, purchasable: true, provider: 'synthetic-sandbox' }], features: [trackingFeature] },
  { id: 3, code: 'ORGANIZATION', name: 'Organization', description: 'Plan cotizado para equipos; contactar ventas.', purchasable: false, prices: [], features: [] },
]
export const trackingSubscription = {
  organizationId: workspaceOrganizationId, planCode: 'FREE', planName: 'Free', status: 'free' as const,
  billingInterval: null, currency: null, amount: null, currentPeriodStartUtc: null, currentPeriodEndUtc: null,
  cancelAtPeriodEnd: false, graceUntilUtc: null, freeFallback: true, features: [trackingFeature], eTag: '"synthetic-subscription"',
}
export const trackingCheckout = {
  id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', organizationId: workspaceOrganizationId, planPriceId: 2,
  planName: 'Professional', interval: 'monthly' as const, currency: 'USD', amount: 12500.5, status: 'pending' as const,
  provider: 'synthetic-sandbox', checkoutUrl: null, expiresAtUtc: '2027-02-02T12:00:00Z',
  createdAtUtc: '2027-02-01T12:00:00Z', updatedAtUtc: '2027-02-01T12:00:00Z', replayed: false,
}
export const trackingUsage = [{
  featureCode: trackingFeature.code, featureName: trackingFeature.name, enabled: true,
  limitValue: 20, usageValue: 1, unit: 'items', periodStartUtc: '2027-02-01T12:00:00Z', periodEndUtc: '2027-03-01T12:00:00Z',
}]
