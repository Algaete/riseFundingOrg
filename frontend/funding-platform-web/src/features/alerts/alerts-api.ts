import { apiClient } from '@/api/http-client'
import type { FundingSort, OrganizationFundingSearch } from '@/features/funding/organization-funding-api'

export interface SavedSearchWrite {
  name: string
  query: string | null
  sponsor: string | null
  minimumAmount: number | null
  maximumAmount: number | null
  currency: string | null
  closingFrom: string | null
  closingTo: string | null
  onlyOpen: boolean
  sort: FundingSort
  countryIds: number[]
  regionIds: number[]
  categoryIds: number[]
  tagIds: number[]
  beneficiaryTypeIds: number[]
  projectTypeIds: number[]
  fundingTypeIds: number[]
  organizationTypeIds: number[]
  funderIds: string[]
}

export interface SavedSearchListItem {
  id: string
  name: string
  query: string | null
  onlyOpen: boolean
  sort: FundingSort
  hasActiveAlert: boolean
  createdAtUtc: string
  updatedAtUtc: string
  eTag: string
}

export interface AlertSubscription {
  id: string
  preferredHourLocal: number
  timeZoneId: string
  nextRunAtUtc: string
  lastRunAtUtc: string | null
  isActive: boolean
  disabledReasonCode: string | null
  createdAtUtc: string
  updatedAtUtc: string
  eTag: string
}

export interface SavedSearchDetail {
  id: string
  name: string
  filters: SavedSearchWrite
  alert: AlertSubscription | null
  createdAtUtc: string
  updatedAtUtc: string
  eTag: string
}

export interface SavedSearchList {
  items: SavedSearchListItem[]
  totalCount: number
  page: number
  pageSize: number
}

export interface NotificationLogItem {
  id: string
  alertSubscriptionId: string | null
  savedSearchId: string | null
  savedSearchName: string | null
  status: 'pending' | 'processing' | 'sent' | 'retry-scheduled' | 'unknown' | 'permanent-failed' | 'skipped'
  itemCount: number
  wasTruncated: boolean
  scheduledForUtc: string
  sentAtUtc: string | null
  errorCode: string | null
  createdAtUtc: string
}

export interface NotificationLogList {
  items: NotificationLogItem[]
  totalCount: number
  page: number
  pageSize: number
}

function organizationPath(organizationId: string, suffix: string) {
  return `organizations/${encodeURIComponent(organizationId)}/${suffix}`
}

export const alertsApi = {
  list(organizationId: string, page = 1, pageSize = 20, signal?: AbortSignal) {
    return apiClient.get<SavedSearchList>(
      `${organizationPath(organizationId, 'saved-searches')}?page=${page}&pageSize=${pageSize}`,
      { cache: 'no-store', signal },
    )
  },
  get(organizationId: string, savedSearchId: string, signal?: AbortSignal) {
    return apiClient.get<SavedSearchDetail>(
      organizationPath(organizationId, `saved-searches/${encodeURIComponent(savedSearchId)}`),
      { cache: 'no-store', signal },
    )
  },
  create(organizationId: string, value: SavedSearchWrite, idempotencyKey: string) {
    return apiClient.post<SavedSearchDetail>(
      organizationPath(organizationId, 'saved-searches'),
      value,
      { cache: 'no-store', headers: { 'Idempotency-Key': idempotencyKey } },
    )
  },
  update(organizationId: string, savedSearchId: string, value: SavedSearchWrite, eTag: string) {
    return apiClient.patch<SavedSearchDetail>(
      organizationPath(organizationId, `saved-searches/${encodeURIComponent(savedSearchId)}`),
      value,
      { cache: 'no-store', headers: { 'If-Match': eTag } },
    )
  },
  remove(organizationId: string, savedSearchId: string, eTag: string) {
    return apiClient.delete<void>(
      organizationPath(organizationId, `saved-searches/${encodeURIComponent(savedSearchId)}`),
      { cache: 'no-store', headers: { 'If-Match': eTag } },
    )
  },
  putAlert(organizationId: string, savedSearchId: string, preferredHourLocal: number, timeZoneId: string) {
    return apiClient.put<AlertSubscription>(
      organizationPath(organizationId, `saved-searches/${encodeURIComponent(savedSearchId)}/alert`),
      { preferredHourLocal, timeZoneId },
      { cache: 'no-store' },
    )
  },
  deleteAlert(organizationId: string, savedSearchId: string) {
    return apiClient.delete<void>(
      organizationPath(organizationId, `saved-searches/${encodeURIComponent(savedSearchId)}/alert`),
      { cache: 'no-store' },
    )
  },
  notifications(organizationId: string, page = 1, pageSize = 20, signal?: AbortSignal) {
    return apiClient.get<NotificationLogList>(
      `${organizationPath(organizationId, 'notification-logs')}?page=${page}&pageSize=${pageSize}`,
      { cache: 'no-store', signal },
    )
  },
  unsubscribe(token: string) {
    return apiClient.post<void>('alerts/unsubscribe', { token }, { cache: 'no-store' })
  },
}

export function toFundingSearch(value: SavedSearchWrite): OrganizationFundingSearch {
  return {
    query: value.query ?? undefined,
    sponsor: value.sponsor ?? undefined,
    minimumAmount: value.minimumAmount ?? undefined,
    maximumAmount: value.maximumAmount ?? undefined,
    currency: value.currency ?? undefined,
    closingFrom: value.closingFrom ?? undefined,
    closingTo: value.closingTo ?? undefined,
    onlyOpen: value.onlyOpen,
    sort: value.sort,
    countryIds: value.countryIds,
    regionIds: value.regionIds,
    categoryIds: value.categoryIds,
    tagIds: value.tagIds,
    beneficiaryTypeIds: value.beneficiaryTypeIds,
    projectTypeIds: value.projectTypeIds,
    fundingTypeIds: value.fundingTypeIds,
    organizationTypeIds: value.organizationTypeIds,
    funderIds: value.funderIds,
    pageNumber: 1,
    pageSize: 12,
  }
}
