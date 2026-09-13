import { apiClient } from '@/api/http-client'
import type { PartnerGeography } from '@/features/funding-discovery/funding-discovery-api'

export type GapCode = 'international-partner' | 'consortium' | 'partners' | 'professionals' | 'partner-geography'
export type GapCandidate = {
  id: string; name: string; summary: string | null; href: string
  sharedCategoryIds: number[]; sharedSkills: string[]; homeCountryId: number | null
}
export type GapRecommendation = {
  code: GapCode; origins: ('funding' | 'project')[]; declaredNeed: string | null
  state: 'suggestions' | 'no-evidence' | 'missing-home-country' | 'geography-needs-review'; candidates: GapCandidate[]
  evaluatedCandidateCount: number; totalCandidateCount: number; isTruncated: boolean
}
export type GapRecommendations = {
  engineVersion: string; projectTitle: string; opportunityTitle: string; contentVersion: number
  classificationCurrent: boolean; evidenceUrl: string | null; evaluatedAtUtc: string; items: GapRecommendation[]
  partnerGeography?: PartnerGeography | null; geographyState?: 'specific' | 'any' | 'unverified' | 'needs-review'
}
export const gapRecommendationsApi = {
  read: (projectId: string, opportunityId: string, signal?: AbortSignal) => apiClient.request<GapRecommendations>(
    'matching/gap-recommendations', { method: 'POST', body: { projectId, opportunityId }, cache: 'no-store', signal }),
}

// Recommendations can navigate only to the existing entity-specific review flows.
export function gapCandidateHref(candidate: GapCandidate, code: GapCode): string | null {
  if (!/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(candidate.id)) return null
  const expected = code === 'professionals'
    ? `/collaboration/consortia?professionalId=${candidate.id}`
    : `/marketplace/organizations/${candidate.id}`
  return candidate.href.toLowerCase() === expected.toLowerCase() ? expected : null
}

export function gapEvidenceHref(value: string | null): string | null {
  try {
    const url = new URL(value ?? '')
    return url.protocol === 'https:' && !url.username && !url.password && (!url.port || url.port === '443') ? url.href : null
  } catch { return null }
}
