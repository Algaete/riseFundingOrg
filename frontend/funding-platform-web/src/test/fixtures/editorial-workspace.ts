import type { AdminFundingOpportunityDetail, AdminFunderDetail } from '@/features/funding/admin-funding-api'
import type { ProjectReviewDetails, ProjectReviewQueueItem } from '@/features/projects/project-api'
import { workspacePublicProject } from './project-workspace'

// Synthetic fixtures only; no credentials or real editorial commands.
export const editorialCatalogs = {
  countries: [{ id: 152, code: 'CL', name: 'Chile' }],
  regions: [{ id: 13_101, countryId: 152, code: 'CL-RM', name: 'Región Metropolitana' }],
  currencies: [{ code: 'USD', name: 'Dólar', minorUnits: 2 }],
  fundingCategories: [{ id: 1, code: 'HEALTH', name: 'Salud' }],
  fundingTypes: [{ id: 1, code: 'MATCHED_GRANT', name: 'Subvención con aporte' }],
  organizationTypes: [], legalEntityTypes: [], organizationSizes: [],
  beneficiaryTypes: [{ id: 2, code: 'CHILDREN', name: 'Niñez' }],
  projectTypes: [{ id: 3, code: 'TRAINING', name: 'Capacitación' }],
  tags: [], languages: [],
}

export function editorialOpportunity(overrides: Partial<AdminFundingOpportunityDetail> = {}): AdminFundingOpportunityDetail {
  return {
    opportunityId: '04b6d64c-3495-45af-9c73-a4ce4202dbb6',
    slug: 'salud-comunitaria',
    title: 'Fondo de salud comunitaria',
    summary: 'Fortalece iniciativas locales.',
    description: 'Descripción completa del fondo.',
    sponsorName: 'Fundación Salud', sponsorUrl: 'https://foundation.example', applicationUrl: 'https://foundation.example/postular',
    externalId: 'FS-2026', fundingSourceId: 7, issuerCountryId: 152, fundingTypeId: 1,
    currency: 'USD', minimumAmount: 1000, maximumAmount: 5000,
    amountStatus: 1,
    openDate: '2026-08-01', closeDate: '2027-01-31',
    closeAtUtc: '2027-02-01T02:59:59.123Z', deadlineTimeZoneId: 'America/Santiago',
    deadlineType: 1, deadlinePrecision: 2,
    eligibilityDescription: 'ONG vigentes', requirements: 'Estatutos', objectives: 'Salud',
    allowedActivities: 'Talleres comunitarios', excludedActivities: 'Propaganda partidista',
    restrictions: 'Sin fines de lucro', targetOrganizationsDescription: 'ONG locales con personalidad jurídica',
    targetPopulationsDescription: 'Niñas y niños de comunidades rurales', minimumOperatingYears: 3,
    requiresLegalEntity: true, requiresPriorExperience: false, requiresCofunding: true,
    cofundingPercentage: 25, geographicScope: 1, remoteApplication: 2,
    sourceUrl: 'https://foundation.example/fondo', publishedAtUtc: null,
    lastVerifiedAtUtc: '2026-08-20T12:00:00.123Z', dataQualityScore: 90,
    publicationStatus: 1, contentVersion: 3, updatedAtUtc: '2026-08-20T12:00:00Z',
    eTag: '"0000000000000003"',
    funders: [{ funderId: '8fa6c73a-af02-4182-8b60-5bcef027ec5c', slug: 'fundacion-salud', name: 'Fundación Salud', role: 1 }],
    countryIds: [152], regionIds: [13_101], categoryIds: [1], beneficiaryTypeIds: [2], projectTypeIds: [3],
    evidence: [],
    sources: [{
      fundingSourceId: 7, sourceName: 'Manual editorial', externalId: 'FS-2026',
      sourceUrl: 'https://foundation.example/fondo', firstSeenAtUtc: '2026-08-01T10:00:00Z',
      lastSeenAtUtc: '2026-08-20T12:00:00Z', isPrimary: true, isActive: true,
    }],
    isActive: true, createdAtUtc: '2026-08-01T10:00:00Z',
    submittedAtUtc: '2026-08-20T12:00:00Z', reviewedAtUtc: null, reviewedByUserId: null,
    rejectionReason: null,
    ...overrides,
  }
}

export function editorialFunder(overrides: Partial<AdminFunderDetail> = {}): AdminFunderDetail {
  return {
    funderId: '8fa6c73a-af02-4182-8b60-5bcef027ec5c',
    slug: 'fundacion-salud',
    name: 'Fundación Salud',
    description: null,
    websiteUrl: 'https://foundation.example',
    countryId: 152,
    countryCode: 'CL',
    countryName: 'Chile',
    publicationStatus: 2,
    isActive: true,
    contentVersion: 1,
    createdAtUtc: '2026-08-01T10:00:00Z',
    updatedAtUtc: '2026-08-20T12:00:00Z',
    eTag: '"0000000000000001"',
    aliases: ['Fundación Salud'],
    submittedAtUtc: '2026-08-19T12:00:00Z',
    reviewedAtUtc: '2026-08-20T12:00:00Z',
    reviewedByUserId: '89b8d22a-472c-42e4-b034-c772ce3bb08e',
    publishedAtUtc: '2026-08-20T12:00:00Z',
    rejectionReason: null,
    opportunities: [],
    ...overrides,
  }
}


export const editorialProject: ProjectReviewDetails = {
  ...workspacePublicProject, publicationStatus: 1, projectVersion: 3, completeness: 87,
  submittedAtUtc: '2026-09-01T12:00:00Z', updatedAtUtc: '2026-09-01T12:00:00Z',
  eTag: '"editorial-project-v3"',
}
export const editorialProjectQueueItem: ProjectReviewQueueItem = {
  ...editorialProject, organizationPublicId: editorialProject.organization.publicId,
  organizationName: editorialProject.organization.name,
}
