import { apiClient } from '@/api/http-client'

export type OperationalErrorCategory = 'import' | 'extraction' | 'semantic' | 'explanation' | 'payment'

export interface AdminOperationalError {
  id: string
  category: OperationalErrorCategory
  severity: number
  code: string
  message: string
  isRetryable: boolean
  occurredAtUtc: string
  relatedResourcePublicId: string | null
  sourceName: string | null
}

export interface AdminOperationalErrorPage {
  items: AdminOperationalError[]
  totalCount: number
  page: number
  pageSize: number
}

export interface AdminOperationalErrorFilters {
  q?: string
  category?: OperationalErrorCategory
  retryable?: boolean
  page: number
  pageSize: number
}

export const adminErrorsApi = {
  list(filters: AdminOperationalErrorFilters, signal?: AbortSignal) {
    const parameters = new URLSearchParams({
      page: String(filters.page), pageSize: String(filters.pageSize),
    })
    if (filters.q?.trim()) parameters.set('q', filters.q.trim())
    if (filters.category) parameters.set('category', filters.category)
    if (filters.retryable !== undefined) parameters.set('retryable', String(filters.retryable))
    return apiClient.get<AdminOperationalErrorPage>(`admin/operational-errors?${parameters}`, {
      cache: 'no-store', signal,
    })
  },
}
