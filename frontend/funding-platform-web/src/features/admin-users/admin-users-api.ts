import { apiClient } from '@/api/http-client'

export type AdminUserStatus =
  | 'PendingActivation'
  | 'PendingVerification'
  | 'Active'
  | 'Blocked'
  | 'Disabled'

export interface AdminUserSummary {
  publicId: string
  email: string
  displayName: string
  preferredLocale: string
  status: AdminUserStatus
  emailConfirmed: boolean
  mfaEnabled: boolean
  lastLoginAtUtc: string | null
  createdAtUtc: string
  roles: string[]
}

export interface AdminUserPage {
  items: AdminUserSummary[]
  totalCount: number
  page: number
  pageSize: number
}

export interface AdminUserFilters {
  q?: string
  status?: number
  role?: string
  page: number
  pageSize: number
}

export const adminUsersApi = {
  list(filters: AdminUserFilters, signal?: AbortSignal) {
    const parameters = new URLSearchParams({
      page: String(filters.page),
      pageSize: String(filters.pageSize),
    })
    if (filters.q?.trim()) parameters.set('q', filters.q.trim())
    if (filters.status !== undefined) parameters.set('status', String(filters.status))
    if (filters.role?.trim()) parameters.set('role', filters.role.trim())
    return apiClient.get<AdminUserPage>(`admin/users?${parameters}`, {
      cache: 'no-store',
      signal,
    })
  },
}
