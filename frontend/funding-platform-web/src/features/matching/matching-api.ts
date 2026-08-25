import { apiClient } from '@/api/http-client'

export const matchingRunStatuses = [0, 1, 2, 3] as const
export type MatchingRunStatus = typeof matchingRunStatuses[number]

export const matchClassifications = [0, 1, 2] as const
export type MatchClassification = typeof matchClassifications[number]

export const hardGateStatuses = [0, 1, 2] as const
export type HardGateStatus = typeof hardGateStatuses[number]

export const matchingRuleOutcomes = [0, 1, 2, 3] as const
export type MatchingRuleOutcome = typeof matchingRuleOutcomes[number]

export const matchingDataStates = [0, 1, 2] as const
export type MatchingDataState = typeof matchingDataStates[number]

export interface MatchingRunSummary {
  publicId: string
  project: {
    publicId: string
    slug: string
    title: string
  }
  status: MatchingRunStatus
  engineVersion: string
  matchingProfile: {
    name: string
    version: number
  }
  projectVersion: number
  organizationProfileVersion: number
  isCurrent: boolean
  candidateCount: number
  totalCandidateCount: number
  isTruncated: boolean
  compatibleCount: number
  incompatibleCount: number
  insufficientDataCount: number
  createdAtUtc: string
  completedAtUtc: string | null
  catalogSnapshotAtUtc: string
}

export interface MatchingRunPage {
  items: MatchingRunSummary[]
  totalCount: number
  pageNumber: number
  pageSize: number
}

export interface MatchingRuleEvidence {
  source: string
  fieldCode: string
  valueCodes: string[]
}

export interface MatchingRuleResult {
  code: string
  name: string
  isHardGate: boolean
  isWarning: boolean
  outcome: MatchingRuleOutcome
  dataState: MatchingDataState
  rawScore: number | null
  weight: number
  weightedPoints: number
  reasonCode: string
  reasonParameters: Record<string, string | null>
  evidence: MatchingRuleEvidence | null
}

export interface ProjectFundingMatch {
  fundingOpportunity: {
    publicId: string
    slug: string
    title: string
    sponsorName: string
    closeDate: string | null
    closeAtUtc: string | null
    deadlinePrecision: number
    contentVersion: number
  }
  classification: MatchClassification
  compatibilityScore: number | null
  evidenceCoverage: number
  hardGateStatus: HardGateStatus
  isCurrent: boolean
  ruleResults: MatchingRuleResult[]
}

export interface MatchingRunDetail {
  run: MatchingRunSummary
  items: ProjectFundingMatch[]
  disclaimer: string
}

export interface MatchingRunCreated {
  run: MatchingRunDetail
  wasReplay: boolean
}

function matchingRunsPath(
  organizationId: string,
  projectId: string,
  suffix = '',
) {
  return `organizations/${encodeURIComponent(organizationId)}/projects/${encodeURIComponent(projectId)}/matching-runs${suffix}`
}

export const matchingApi = {
  list(
    organizationId: string,
    projectId: string,
    page = 1,
    pageSize = 20,
    signal?: AbortSignal,
  ) {
    const query = new URLSearchParams({ page: String(page), pageSize: String(pageSize) })
    return apiClient.get<MatchingRunPage>(
      `${matchingRunsPath(organizationId, projectId)}?${query.toString()}`,
      { cache: 'no-store', signal },
    )
  },

  get(
    organizationId: string,
    projectId: string,
    matchingRunId: string,
    signal?: AbortSignal,
  ) {
    return apiClient.get<MatchingRunDetail>(
      matchingRunsPath(organizationId, projectId, `/${encodeURIComponent(matchingRunId)}`),
      { cache: 'no-store', signal },
    )
  },

  calculate(
    organizationId: string,
    projectId: string,
    idempotencyKey: string,
  ) {
    return apiClient.post<MatchingRunCreated>(
      matchingRunsPath(organizationId, projectId),
      undefined,
      {
        cache: 'no-store',
        headers: { 'Idempotency-Key': idempotencyKey },
      },
    )
  },
}

export function createMatchingCommandId() {
  return crypto.randomUUID()
}
