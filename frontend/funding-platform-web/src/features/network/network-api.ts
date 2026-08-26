import { apiClient } from '@/api/http-client'

export type ConnectionPurpose = 'partnership' | 'expertise' | 'geographic-reach' | 'consortium-exploration'
export type ConnectionStatus = 'pending' | 'accepted' | 'rejected' | 'cancelled' | 'blocked'
export type ConnectionDirection = 'all' | 'incoming' | 'outgoing'
export type ConnectionAction = 'accept' | 'reject' | 'cancel' | 'block'

export interface NetworkPreference {
  exists: boolean
  isDiscoverable: boolean
  allowRequests: boolean
  createdAtUtc: string | null
  updatedAtUtc: string | null
  eTag: string | null
}

export interface NetworkCatalogItem { id: number; code: string; name: string }

export interface NetworkDirectoryOrganization {
  id: string
  name: string
  description: string | null
  websiteUrl: string | null
  homeCountry: NetworkCatalogItem
  organizationType: NetworkCatalogItem
  visibleProjectCount: number
  allowsRequests: boolean
  connectionId: string | null
  connectionState: 'none' | 'pending-outgoing' | 'pending-incoming' | 'connected'
  categories: NetworkCatalogItem[]
  projectTypes: NetworkCatalogItem[]
}

export interface NetworkDirectoryPage {
  items: NetworkDirectoryOrganization[]
  totalCount: number
  page: number
  pageSize: number
}

export interface OrganizationConnection {
  id: string
  direction: 'incoming' | 'outgoing'
  status: ConnectionStatus
  purpose: ConnectionPurpose
  message: string
  counterpartyOrganizationId: string
  counterpartyOrganizationName: string
  counterpartyIsPublic: boolean
  requesterProjectId: string | null
  requesterProjectSlug: string | null
  requesterProjectTitle: string | null
  canRespond: boolean
  canCancel: boolean
  canBlock: boolean
  createdAtUtc: string
  updatedAtUtc: string
  actionedAtUtc: string | null
  eTag: string
}

export interface OrganizationConnectionPage {
  items: OrganizationConnection[]
  totalCount: number
  page: number
  pageSize: number
}

function root(organizationId: string) {
  return `organizations/${encodeURIComponent(organizationId)}/network`
}

export const networkApi = {
  settings(organizationId: string, signal?: AbortSignal) {
    return apiClient.get<NetworkPreference>(`${root(organizationId)}/settings`, { cache: 'no-store', signal })
  },
  putSettings(organizationId: string, input: Pick<NetworkPreference, 'isDiscoverable' | 'allowRequests'>, eTag?: string | null) {
    return apiClient.put<NetworkPreference>(`${root(organizationId)}/settings`, input, {
      cache: 'no-store', headers: eTag ? { 'If-Match': eTag } : undefined,
    })
  },
  directory(organizationId: string, query: string, page = 1, signal?: AbortSignal) {
    const parameters = new URLSearchParams({ page: String(page), pageSize: '20' })
    if (query.trim()) parameters.set('q', query.trim())
    return apiClient.get<NetworkDirectoryPage>(`${root(organizationId)}/directory?${parameters}`, { cache: 'no-store', signal })
  },
  connections(organizationId: string, direction: ConnectionDirection, signal?: AbortSignal) {
    const parameters = new URLSearchParams({ direction, page: '1', pageSize: '50' })
    return apiClient.get<OrganizationConnectionPage>(`${root(organizationId)}/connections?${parameters}`, { cache: 'no-store', signal })
  },
  create(organizationId: string, input: {
    recipientOrganizationId: string
    requesterProjectId: string | null
    purpose: ConnectionPurpose
    message: string
  }, idempotencyKey: string) {
    return apiClient.post<OrganizationConnection>(`${root(organizationId)}/connections`, input, {
      cache: 'no-store', headers: { 'Idempotency-Key': idempotencyKey },
    })
  },
  action(organizationId: string, connection: OrganizationConnection, action: ConnectionAction) {
    return apiClient.patch<OrganizationConnection>(
      `${root(organizationId)}/connections/${encodeURIComponent(connection.id)}`,
      { action }, { cache: 'no-store', headers: { 'If-Match': connection.eTag } },
    )
  },
}

export function createNetworkCommandId() {
  return `organization-connect-${crypto.randomUUID()}`
}
