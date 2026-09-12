import { apiClient } from '@/api/http-client'

export interface MapPoint {
  publicId: string; slug: string; title: string; summary: string | null; organizationName: string
  latitude: number; longitude: number; projectStatus: number; projectStage: number | null
  fundingGap: number | null; currency: string | null
}
export interface MapPage { items: MapPoint[]; totalCount: number; withoutPublicLocationCount: number; page: number; pageSize: number }
export const projectMapApi = {
  search(query: URLSearchParams, signal?: AbortSignal) {
    return apiClient.get<MapPage>(`marketplace/project-map?${query}`, { signal, cache: 'no-store' })
  },
}

export { mapQuery } from './map-filters'
