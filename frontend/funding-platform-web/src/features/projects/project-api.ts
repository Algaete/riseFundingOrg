import { apiClient } from '@/api/http-client'

export interface ProjectSummary {
  publicId: string
  slug: string
  title: string
  summary: string | null
  status: number
  publicationStatus: number
  startDate: string | null
  endDate: string | null
  budgetTotal: number | null
  confirmedFunding: number | null
  currency: string | null
  fundingGap: number | null
  projectVersion: number
  updatedAtUtc: string
}

export interface ProjectDetails extends ProjectSummary {
  description: string | null
  submittedAtUtc: string | null
  reviewedAtUtc: string | null
  rejectionReason: string | null
  publishedAtUtc: string | null
  eTag: string
  countryIds: number[]
  regionIds: number[]
  categoryIds: number[]
  beneficiaryTypeIds: number[]
  projectTypeIds: number[]
}

export interface ProjectWriteInput {
  title: string
  summary: string | null
  description: string | null
  status: number
  startDate: string | null
  endDate: string | null
  budgetTotal: number | null
  confirmedFunding: number | null
  currency: string | null
  countryIds: number[]
  regionIds: number[]
  categoryIds: number[]
  beneficiaryTypeIds: number[]
  projectTypeIds: number[]
}

export interface PersistedProject {
  publicId: string
  projectVersion: number
  eTag: string
}

export interface ProjectWorkflowResponse {
  projectId: string
  publicationStatus: number
  completeness: number
  eTag: string
  wasReplay: boolean
}

export interface ProjectReviewQueueItem {
  projectId: string
  slug: string
  title: string
  summary: string | null
  projectStatus: number
  publicationStatus: number
  organizationPublicId: string
  organizationName: string
  completeness: number
  submittedAtUtc: string
  updatedAtUtc: string
  eTag: string
}

export interface ProjectReviewQueue {
  items: ProjectReviewQueueItem[]
  totalCount: number
  page: number
  pageSize: number
}

export interface PublicProjectOrganization {
  publicId: string
  name: string
  websiteUrl: string | null
}

export interface PublicProjectCatalogItem {
  id: number
  code: string
  name: string
}

export interface PublicProjectRegion extends PublicProjectCatalogItem {
  countryId: number
}

export interface PublicProject {
  projectId: string
  slug: string
  title: string
  summary: string | null
  description: string | null
  projectStatus: number
  startDate: string | null
  endDate: string | null
  budgetTotal: number | null
  confirmedFunding: number | null
  currency: string | null
  fundingGap: number | null
  publishedAtUtc: string
  organization: PublicProjectOrganization
  countries: PublicProjectCatalogItem[]
  regions: PublicProjectRegion[]
  categories: PublicProjectCatalogItem[]
  beneficiaryTypes: PublicProjectCatalogItem[]
  projectTypes: PublicProjectCatalogItem[]
}

export interface ProjectReviewDetails extends Omit<PublicProject, 'publishedAtUtc'> {
  publicationStatus: number
  projectVersion: number
  completeness: number
  submittedAtUtc: string
  updatedAtUtc: string
  eTag: string
}

export type ProjectReviewDecision = 'approve' | 'reject'

function path(organizationId: string, suffix = '') {
  return `organizations/${encodeURIComponent(organizationId)}/projects${suffix}`
}

export const projectApi = {
  list(organizationId: string, signal?: AbortSignal) {
    return apiClient.get<ProjectSummary[]>(path(organizationId), { signal })
  },
  get(organizationId: string, projectId: string, signal?: AbortSignal) {
    return apiClient.get<ProjectDetails>(path(organizationId, `/${encodeURIComponent(projectId)}`), { signal })
  },
  create(organizationId: string, input: ProjectWriteInput) {
    return apiClient.post<PersistedProject>(path(organizationId), input)
  },
  update(organizationId: string, projectId: string, eTag: string, input: ProjectWriteInput) {
    return apiClient.put<ProjectDetails>(path(organizationId, `/${encodeURIComponent(projectId)}`), input, {
      headers: { 'If-Match': eTag },
    })
  },
  requestPublication(
    organizationId: string,
    projectId: string,
    eTag: string,
    idempotencyKey: string,
  ) {
    return apiClient.post<ProjectWorkflowResponse>(
      path(organizationId, `/${encodeURIComponent(projectId)}/publish`),
      undefined,
      { headers: { 'If-Match': eTag, 'Idempotency-Key': idempotencyKey } },
    )
  },
  archive(
    organizationId: string,
    projectId: string,
    eTag: string,
    idempotencyKey: string,
  ) {
    return apiClient.post<ProjectWorkflowResponse>(
      path(organizationId, `/${encodeURIComponent(projectId)}/archive`),
      undefined,
      { headers: { 'If-Match': eTag, 'Idempotency-Key': idempotencyKey } },
    )
  },
}

export const projectReviewApi = {
  list(page = 1, pageSize = 20, signal?: AbortSignal) {
    const query = new URLSearchParams({ page: String(page), pageSize: String(pageSize) })
    return apiClient.get<ProjectReviewQueue>(`admin/projects/review-queue?${query}`, { signal })
  },
  get(projectId: string, signal?: AbortSignal) {
    return apiClient.get<ProjectReviewDetails>(
      `admin/projects/${encodeURIComponent(projectId)}`,
      { signal },
    )
  },
  review(
    projectId: string,
    eTag: string,
    idempotencyKey: string,
    decision: ProjectReviewDecision,
    reason: string | null,
  ) {
    return apiClient.post<ProjectWorkflowResponse>(
      `admin/projects/${encodeURIComponent(projectId)}/reviews`,
      { decision, reason },
      { headers: { 'If-Match': eTag, 'Idempotency-Key': idempotencyKey } },
    )
  },
}

export const publicProjectApi = {
  get(slug: string, signal?: AbortSignal) {
    return apiClient.get<PublicProject>(`projects/${encodeURIComponent(slug)}`, { signal })
  },
}

export function createProjectCommandId() {
  return crypto.randomUUID()
}
