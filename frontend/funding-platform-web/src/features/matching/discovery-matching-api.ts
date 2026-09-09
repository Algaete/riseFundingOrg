import { apiClient } from '@/api/http-client'
export interface DiscoveryRequest {
  sourceKind: 1 | 2 | 3 | 4; sourceId: string; targetKind: 1 | 2 | 3; page: number; pageSize: number
  criteria?: { countryId?: number; categoryId?: number; minimumAmount?: number; maximumAmount?: number; currency?: string; projectStage?: number }
}
export type RuleCode = 'geography' | 'sector' | 'organization-type' | 'amount' | 'stage' | 'skills' | 'official-eligibility' | 'availability' | 'partnership-consent'
export interface DiscoveryResult {
  sourceName: string; engineVersion: string; evaluatedAtUtc: string; totalCount: number; totalCandidateCount: number; isTruncated: boolean; page: number; pageSize: number
  items: { id: string; name: string; summary: string | null; href: string; score: number | null; evidenceCoverage: number;
    classification: 'aligned' | 'gaps' | 'partial-evidence' | 'insufficient-data';
    reasons: { code: RuleCode; outcome: 'match' | 'gap' | 'unknown' | 'verify' | 'currency-mismatch'; evidence: string[]; weight: number }[] }[]
}
export const discoveryMatchingApi = {
  search: (request: DiscoveryRequest, signal?: AbortSignal) => apiClient.post<DiscoveryResult>('matching/discovery', request, { signal, cache: 'no-store' }),
}
export function validDiscoveryInput(request: DiscoveryRequest) {
  const criteria = request.criteria
  return Boolean(request.sourceId) && (!criteria ||
    ((criteria.minimumAmount === undefined || (Number.isFinite(criteria.minimumAmount) && criteria.minimumAmount >= 0 && criteria.minimumAmount <= 999999999999))
      && (criteria.maximumAmount === undefined || (Number.isFinite(criteria.maximumAmount) && criteria.maximumAmount >= 0 && criteria.maximumAmount <= 999999999999))
      && (criteria.minimumAmount === undefined || criteria.maximumAmount === undefined || criteria.minimumAmount <= criteria.maximumAmount)
      && ((criteria.minimumAmount === undefined && criteria.maximumAmount === undefined) || /^[A-Z]{3}$/.test(criteria.currency ?? ''))))
}
