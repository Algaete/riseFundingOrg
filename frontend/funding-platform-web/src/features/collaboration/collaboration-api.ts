import { apiClient } from '@/api/http-client'
import type { OrganizationConnectionPage } from '@/features/network/network-api'
import { collaborationList, collaborationPage } from './collaboration-response'

export interface Page<T> { items: T[]; totalCount: number; page: number; pageSize: number }
export interface ProfessionalData {
  displayName: string; headline: string; biography: string | null; countryId: number | null
  skills: string[]; languageIds: number[]; categoryIds: number[]
  isDiscoverable: boolean; allowsInvitations: boolean
}
export interface Professional { profileId: string; data: ProfessionalData }
export interface OwnProfessional extends Professional { eTag: string; updatedAtUtc: string }
export interface Consortium {
  consortiumId: string; projectId: string; projectTitle: string | null; projectSlug: string | null
  projectIsPublic: boolean; name: string; summary: string | null; leadOrganizationId: string
  leadOrganizationName: string; status: 0 | 1 | 2; canManage: boolean; canViewRoster: boolean
  hasPendingInvitation: boolean; acceptedCount: number; eTag: string; updatedAtUtc: string
}
export interface Participant {
  participantId: string; kind: 1 | 2; targetId: string; displayName: string; contribution: string
  message: string; status: 0 | 1 | 2 | 3 | 4 | 5; canRespond: boolean; canLeave: boolean
  canCancel: boolean; canRemove: boolean; eTag: string; updatedAtUtc: string
}
export interface ConsortiumDetails { consortium: Consortium; participants: Participant[] }
export interface ConsortiumInput { name: string; summary: string | null }
export interface InvitationInput { kind: 1 | 2; targetId: string; contribution: string; message: string }
export interface WriteResult { entityId: string; eTag: string; wasReplay: boolean }
const options = (key: string, eTag?: string, createProfile = false) => ({
  cache: 'no-store' as const,
  headers: { 'Idempotency-Key': key, ...(eTag ? { 'If-Match': eTag } : createProfile ? { 'If-None-Match': '*' } : {}) },
})
const path = (id: string) => `consortia/${encodeURIComponent(id)}`
export const collaborationApi = {
  // Unlike the network workspace's first-page shortcut, this picker pages all accepted partners.
  connections: (organizationId: string, page = 1, signal?: AbortSignal) =>
    apiClient.get<OrganizationConnectionPage>(`organizations/${encodeURIComponent(organizationId)}/network/connections?direction=all&status=accepted&page=${page}&pageSize=20`, { signal, cache: 'no-store' }).then(collaborationPage),
  profile: (signal?: AbortSignal) => apiClient.get<OwnProfessional | null>('me/professional-profile', { signal, cache: 'no-store' }),
  saveProfile: (data: ProfessionalData, key: string, eTag?: string) =>
    apiClient.put<WriteResult>('me/professional-profile', data, options(key, eTag, true)),
  professionals: (q = '', countryId = '', categoryId = '', page = 1, signal?: AbortSignal) => {
    const params = new URLSearchParams({ page: String(page), pageSize: '20' })
    if (q.trim()) params.set('q', q.trim())
    if (countryId) params.set('countryId', countryId)
    if (categoryId) params.set('categoryId', categoryId)
    return apiClient.get<Page<Professional>>(`professionals?${params}`, { signal, cache: 'no-store' }).then(collaborationPage)
  },
  consortia: (page = 1, signal?: AbortSignal) => apiClient.get<Page<Consortium>>(`consortia?page=${page}&pageSize=20`, { signal, cache: 'no-store' }).then(collaborationPage),
  consortium: async (id: string, signal?: AbortSignal): Promise<ConsortiumDetails> => {
    const result = await apiClient.get<ConsortiumDetails>(path(id), { signal, cache: 'no-store' })
    if (!result?.consortium) throw new Error('Missing consortium response.')
    return { ...result, participants: collaborationList(result.participants) }
  },
  create: (data: ConsortiumInput & { projectId: string }, key: string) => apiClient.post<WriteResult>('consortia', data, options(key)),
  update: (id: string, data: ConsortiumInput & { status: number }, key: string, eTag: string) =>
    apiClient.put<WriteResult>(path(id), data, options(key, eTag)),
  invite: (id: string, data: InvitationInput, key: string, eTag: string) =>
    apiClient.post<WriteResult>(`${path(id)}/invitations`, data, options(key, eTag)),
  act: (id: string, participantId: string, action: number, key: string, eTag: string) =>
    apiClient.patch<WriteResult>(`${path(id)}/participants/${encodeURIComponent(participantId)}`, { action }, options(key, eTag)),
}
