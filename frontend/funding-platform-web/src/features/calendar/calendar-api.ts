import { apiClient } from '@/api/http-client'

import type { ApplicationStatus } from '@/features/applications/application-api'

export type CalendarEventType =
  | 'application-deadline'
  | 'planned-submission'
  | 'application-result'
  | 'project-start'
  | 'project-end'
  | 'favorite-deadline'

export interface CalendarEvent {
  eventKey: string
  eventType: CalendarEventType
  eventDate: string
  eventAtUtc: string | null
  datePrecision: number
  title: string
  status: ApplicationStatus | null
  fundingApplicationPublicId: string | null
  projectPublicId: string | null
  fundingOpportunityPublicId: string | null
}

export interface CalendarResponse {
  from: string
  to: string
  items: CalendarEvent[]
}

function dateRangePath(organizationId: string, from: string, to: string) {
  const parameters = new URLSearchParams({ from, to })
  return `organizations/${encodeURIComponent(organizationId)}/calendar?${parameters.toString()}`
}

export const calendarApi = {
  get(organizationId: string, from: string, to: string, signal?: AbortSignal) {
    return apiClient.get<CalendarResponse>(dateRangePath(organizationId, from, to), {
      cache: 'no-store',
      signal,
    })
  },
}
