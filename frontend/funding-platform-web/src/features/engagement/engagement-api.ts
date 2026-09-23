import { apiClient } from '@/api/http-client'

export const storyKinds = ['organization', 'project', 'fieldwork', 'volunteers', 'team', 'learning', 'impact', 'news', 'beneficiaries'] as const
export interface StoryContent { title: string; summary: string | null; body: string; kind: string; projectId: string | null; categoryIds: number[]; goalIds: number[]; countryIds: number[]; containsPersonalExperiences: boolean }
export interface Story { id: string; organizationId: string; organizationName: string; projectTitle: string | null; projectSlug: string | null; content: StoryContent; status: number; revision: number; updatedAtUtc: string }
export interface Page<T> { items: T[]; totalCount: number; page: number }
export const serviceCodes = ['advisory', 'application-support', 'project-design', 'getting-started', 'partnerships', 'translation', 'proposal-review'] as const
export const contactTopics = ['funding', 'project', 'application', 'project-design', 'partnerships', 'service', 'platform', 'other'] as const
export interface InquiryInput { requestId: string; name: string; email: string; organization: string | null; countryId: number; topic: string; serviceCode: string | null; projectReference: string | null; fundingReference: string | null; deadline: string | null; description: string; consentToContact: boolean; website: string }
export interface Inquiry { requestId: string; data: InquiryInput; countryName: string; status: number; notificationStatus: number; revision: number; createdAtUtc: string }
const own = (organization: string) => `organizations/${encodeURIComponent(organization)}/stories`
function pageResult<T>(value: Page<T>): Page<T> {
  if (!value || !Number.isSafeInteger(value.page) || value.page < 1 || !Number.isSafeInteger(value.totalCount) || value.totalCount < 0)
    throw new Error('Invalid engagement page.')
  const items = value.items ?? []
  if (!Array.isArray(items) || items.some(item => item === null || typeof item !== 'object') || items.length === 0 && (value.page - 1) * 20 < value.totalCount)
    throw new Error('Incomplete engagement page.')
  return { ...value, items }
}
export const engagementApi = {
  stories(organization?: string, project?: string, page = 1, signal?: AbortSignal) {
    const params = new URLSearchParams({ page: String(page) })
    if (organization) params.set('organizationId', organization)
    if (project) params.set('projectId', project)
    return apiClient.get<Page<Story>>(`stories?${params}`, { signal, cache: 'no-store' }).then(pageResult)
  },
  story(id: string, signal?: AbortSignal) { return apiClient.get<Story>(`stories/${encodeURIComponent(id)}`, { signal, cache: 'no-store' }) },
  ownStories(organization: string, page: number, signal?: AbortSignal) { return apiClient.get<Page<Story>>(`${own(organization)}?page=${page}`, { signal, cache: 'no-store' }).then(pageResult) },
  saveStory(organization: string, id: string, expectedRevision: number, content: StoryContent) { return apiClient.put<void>(`${own(organization)}/${id}`, { expectedRevision, content }) },
  publishStory(organization: string, story: Story, publish: boolean, rightsConfirmed: boolean, personalConsentConfirmed: boolean) {
    return apiClient.post<void>(`${own(organization)}/${story.id}/publication`, { expectedRevision: story.revision, publish, rightsConfirmed, personalConsentConfirmed })
  },
  contact(input: InquiryInput) { return apiClient.post<{ requestId: string; wasReplay: boolean }>('inquiries', input) },
  inquiries(page: number, signal?: AbortSignal) { return apiClient.get<Page<Inquiry>>(`admin/inquiries?page=${page}`, { signal, cache: 'no-store' }).then(pageResult) },
  reviewInquiry(item: Inquiry, status: number) { return apiClient.put<void>(`admin/inquiries/${item.requestId}`, { expectedRevision: item.revision, status }) },
}
