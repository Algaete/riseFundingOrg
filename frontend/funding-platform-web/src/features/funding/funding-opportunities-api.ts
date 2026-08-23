import { apiClient } from '@/api/http-client'

export interface FundingOpportunityListItem {
  publicId: string
  slug: string
  title: string
  summary: string | null
  sponsorName: string
  currency: string | null
  minimumAmount: number | null
  maximumAmount: number | null
  openDate: string | null
  closeDate: string | null
  closeAtUtc?: string | null
  deadlineType?: number
  deadlinePrecision?: number
  sourceName: string
  sourceUrl: string | null
  sourceAttribution?: string | null
  publishedAtUtc: string
  dataQualityScore: number
}

export interface FundingOpportunityListResponse {
  items: FundingOpportunityListItem[]
  totalCount: number
  pageNumber: number
  pageSize: number
}

export interface FundingOpportunityFunder {
  funderId: string
  slug: string
  name: string
  role: 1 | 2 | 3
}

export interface FundingOpportunityDetail extends FundingOpportunityListItem {
  description: string | null
  sponsorUrl: string | null
  applicationUrl: string | null
  eligibilityDescription: string | null
  requirements: string | null
  objectives: string | null
  requiresCofunding: boolean | null
  externalId: string | null
  lastVerifiedAtUtc: string
  funders: FundingOpportunityFunder[]
}

export const fundingOpportunitiesApi = {
  search(query: string, pageNumber = 1, pageSize = 12, signal?: AbortSignal) {
    const parameters = new URLSearchParams({
      pageNumber: String(pageNumber),
      pageSize: String(pageSize),
    })
    if (query.trim()) parameters.set('query', query.trim())

    return apiClient.get<FundingOpportunityListResponse>(
      `funding-opportunities?${parameters.toString()}`,
      { signal },
    )
  },

  getBySlug(slug: string, signal?: AbortSignal) {
    return apiClient.get<FundingOpportunityDetail>(
      `funding-opportunities/${encodeURIComponent(slug)}`,
      { signal },
    )
  },
}
