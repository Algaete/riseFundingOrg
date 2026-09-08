import { workspaceCatalogs, workspaceOrganizationId, workspaceProfile, workspaceProject, workspaceProjectId } from './project-workspace'

// Synthetic contracts shared by unit/browser tests. Never use real accounts or networking writes.
export const collaborationOrganizations = [
  { ...workspaceProfile, updatedAtUtc: '2026-09-01T12:00:00Z' },
  { ...workspaceProfile, publicId: '44444444-4444-4444-4444-444444444444', name: 'Otra organización', updatedAtUtc: '2026-09-01T12:00:00Z' },
]
export const matchingRunId = '55555555-5555-5555-5555-555555555555'
export const matchingRule = {
  code: 'geography', name: 'Geography', isHardGate: true, isWarning: true,
  outcome: 3 as const, dataState: 1 as const, rawScore: null, weight: 20, weightedPoints: 0,
  reasonCode: 'geography.missing_project', reasonParameters: {},
  evidence: { source: 'versioned-snapshots', fieldCode: 'geography', valueCodes: ['private@example.invalid', 'internal-01'] },
}
export const matchingDetail = {
  run: {
    publicId: matchingRunId, project: { publicId: workspaceProjectId, slug: workspaceProject.slug, title: workspaceProject.title },
    status: 2 as const, engineVersion: 'deterministic-v1', matchingProfile: { name: 'baseline', version: 1 },
    projectVersion: 4, organizationProfileVersion: 3, isCurrent: false, candidateCount: 200,
    totalCandidateCount: 240, isTruncated: true, compatibleCount: 1, incompatibleCount: 1, insufficientDataCount: 1,
    createdAtUtc: '2026-09-01T12:00:00Z', completedAtUtc: '2026-09-01T12:00:01Z', catalogSnapshotAtUtc: '2026-09-01T12:00:00Z',
  },
  items: [{
    fundingOpportunity: {
      publicId: '66666666-6666-6666-6666-666666666666', slug: 'fondo-nandu', title: 'Fondo Ñandú original', sponsorName: 'Financiador original',
      closeDate: '2030-12-31', closeAtUtc: '2030-12-31T20:30:00Z', deadlinePrecision: 2, contentVersion: 5,
    },
    classification: 2 as const, compatibilityScore: 42.5, evidenceCoverage: 62.5, hardGateStatus: 2 as const, isCurrent: false,
    ruleResults: [
      matchingRule,
      { ...matchingRule, code: 'amount', name: 'Funding amount', isHardGate: false, isWarning: false, outcome: 1 as const, dataState: 0 as const, rawScore: 50, weight: 10, weightedPoints: 5,
        reasonCode: 'amount.above_max_partial', reasonParameters: { projectCurrency: 'USD', opportunityCurrency: 'USD', matchCount: '2', requiredYears: '3', maximumPossibleYears: '8', minimumGuaranteedYears: '7', privateText: 'SECRET-PARAMETER' },
        evidence: null },
    ],
  }],
  disclaimer: 'Resultado orientativo basado en datos disponibles; no confirma elegibilidad ni reemplaza la revisión de las bases del fondo.',
}
export const matchingHistory = { items: [matchingDetail.run], totalCount: 21, pageNumber: 2, pageSize: 10 }

export const networkPreference = {
  exists: true, isDiscoverable: false, allowRequests: false,
  createdAtUtc: '2026-09-01T12:00:00Z', updatedAtUtc: '2026-09-01T12:00:00Z', eTag: '"0000000000000001"',
}
export const networkOrganization = {
  id: '77777777-7777-7777-7777-777777777777', name: 'Fundación Aliada Ñandú',
  description: 'Descripción original de la organización.', websiteUrl: 'https://example.invalid',
  homeCountry: workspaceCatalogs.countries[0], organizationType: workspaceCatalogs.organizationTypes[0],
  visibleProjectCount: 1, allowsRequests: true, connectionId: null, connectionState: 'none' as const,
  categories: [workspaceCatalogs.fundingCategories[0]], projectTypes: workspaceCatalogs.projectTypes,
}
export const networkDirectory = { items: [networkOrganization], totalCount: 1, page: 1, pageSize: 20 }
export const networkConnection = {
  id: '88888888-8888-8888-8888-888888888888', direction: 'incoming' as const, status: 'pending' as const, purpose: 'partnership' as const,
  message: 'Mensaje privado original para colaborar.', counterpartyOrganizationId: networkOrganization.id,
  counterpartyOrganizationName: 'Organización Invitante', counterpartyIsPublic: true,
  requesterProjectId: workspaceProjectId, requesterProjectSlug: workspaceProject.slug, requesterProjectTitle: 'Proyecto de colaboración original',
  canRespond: true, canCancel: false, canBlock: true, createdAtUtc: '2026-09-01T12:00:00Z',
  updatedAtUtc: '2026-09-01T12:00:00Z', actionedAtUtc: null, eTag: '"0000000000000002"',
}
export const networkConnections = { items: [networkConnection], totalCount: 1, page: 1, pageSize: 50 }
export { workspaceOrganizationId, workspaceProjectId, workspaceProject }
