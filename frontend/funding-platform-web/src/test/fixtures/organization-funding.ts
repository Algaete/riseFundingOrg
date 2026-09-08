import { discoveryOpportunity } from './public-discovery'
import { workspaceCatalogs, workspaceOrganizationId, workspaceProfile } from './project-workspace'

// Synthetic source records; no real accounts, published funds, or external writes.
export const organizationFundingCatalogs = {
  ...workspaceCatalogs,
  fundingTypes: [{ id: 3, code: 'GRANT', name: 'Subvención' }],
  tags: [{ id: 9, code: 'CLIMATE', name: 'Cambio climático' }],
}

export const fundingOrganizations = [
  { ...workspaceProfile, updatedAtUtc: '2026-09-01T12:00:00Z' },
  { ...workspaceProfile, publicId: '44444444-4444-4444-4444-444444444444', name: 'Otra organización', updatedAtUtc: '2026-09-01T12:00:00Z' },
]

export const organizationOpportunity = {
  ...discoveryOpportunity,
  primaryFunderPublicId: discoveryOpportunity.funders[0].funderId,
  primaryFunderName: discoveryOpportunity.funders[0].name,
  primaryFunderSlug: discoveryOpportunity.funders[0].slug,
  isFavorite: false, issuerCountryId: 152, fundingTypeId: 3, amountStatus: 1,
  deadlineTimeZoneId: 'America/Santiago', closeAtUtc: '2030-12-31T20:30:00Z', deadlinePrecision: 2,
  allowedActivities: 'Actividades originales de la fuente.',
  excludedActivities: 'Exclusiones originales.', restrictions: 'Restricciones originales.',
  targetOrganizationsDescription: 'Organizaciones originales.',
  targetPopulationsDescription: 'Poblaciones originales.',
  minimumOperatingYears: 2, requiresLegalEntity: true, requiresPriorExperience: null,
  cofundingPercentage: 12.5, geographicScope: 1, remoteApplication: 2, contentVersion: 3,
  countryIds: [152], regionIds: [7], categoryIds: [1], beneficiaryTypeIds: [1], projectTypeIds: [4], tagIds: [9],
  organizationTypes: [{ id: 2, eligibilityMode: 1 }],
  legalEntityTypes: [{ id: 1, eligibilityMode: 2 }],
  languages: [{ id: 1, languagePurpose: 1 }],
  sources: [{
    fundingSourceId: 1, sourceName: 'Fuente vinculada Ñandú', externalId: 'ORIGINAL-01',
    sourceUrl: 'https://source.example.invalid/terms?id=1#original', isPrimary: true, isActive: true,
    firstSeenAtUtc: '2026-09-01T12:00:00Z', lastSeenAtUtc: '2026-09-01T12:00:00Z',
  }],
}

export function organizationFundingResponse(isFavorite = false, pageNumber = 1, totalCount = 1) {
  return { items: [{ ...organizationOpportunity, isFavorite }], totalCount, pageNumber, pageSize: 12, searchMode: 'filtered' as const }
}

export { workspaceOrganizationId as fundingOrganizationId }
