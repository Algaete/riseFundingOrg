import { apiClient } from '@/api/http-client'

export interface MapPoint {
  publicId: string; slug: string; title: string; summary: string | null; organizationName: string
  latitude: number; longitude: number; projectStatus: number; projectStage: number | null
  fundingGap: number | null; currency: string | null
}
export interface MapPage { items: MapPoint[]; totalCount: number; withoutPublicLocationCount: number; page: number; pageSize: number }
export const projectMapApi = {
  search(query: URLSearchParams, signal?: AbortSignal) {
    return apiClient.get<MapPage>(`marketplace/project-map?${query}`, { signal })
  },
}

export function mapQuery(search: URLSearchParams) {
  const query = new URLSearchParams()
  const q = search.get('q')?.trim().slice(0, 200)
  if (q) query.set('q', q)
  for (const [key, min, max] of [['countryId', 1, 32767], ['categoryId', 1, 2147483647], ['projectStage', 0, 5], ['sustainableDevelopmentGoalId', 1, 17], ['projectStatus', 0, 6], ['page', 1, 10000]] as const) {
    const raw = search.get(key)
    const value = Number(raw)
    if (raw !== null && raw !== '' && Number.isInteger(value) && value >= min && value <= max) query.set(key, String(value))
  }
  if (!query.has('page')) query.set('page', '1')
  query.set('pageSize', '100')
  return query
}
