import { workspaceCatalogs, workspaceProfile, workspaceProject, workspacePublicProject } from './project-workspace'

export const discoveryOpportunity = {
  publicId: '88888888-8888-8888-8888-888888888888', slug: 'fondo-salud-nandu',
  title: 'Fondo Salud Ñandú', summary: 'Resumen original del fondo.', sponsorName: 'Fundación de prueba Ñandú',
  currency: 'USD', minimumAmount: 25000, maximumAmount: 100000,
  openDate: '2026-01-01', closeDate: '2030-12-31', closeAtUtc: null, deadlineType: 1, deadlinePrecision: 1,
  sourceName: 'Portal oficial sintético', sourceUrl: 'https://source.example.invalid/fondo',
  sourceAttribution: 'Atribución original de la fuente.', publishedAtUtc: '2026-09-01T12:00:00Z',
  dataQualityScore: 96, description: 'Descripción original del fondo.', sponsorUrl: null,
  applicationUrl: 'https://apply.example.invalid/form?id=original#steps',
  eligibilityDescription: 'Organizaciones sin fines de lucro.', requirements: 'Estatutos y presupuesto.',
  objectives: 'Salud comunitaria.', requiresCofunding: false, externalId: 'SALUD-2026',
  lastVerifiedAtUtc: '2026-09-01T12:00:00Z', funders: [
    { funderId: '99999999-9999-9999-9999-999999999999', slug: 'fundacion-sintetica', name: 'Financiador Ñandú', role: 1 as const },
  ],
}

export const discoveryProject = {
  ...workspaceProject, organization: workspacePublicProject.organization,
  publishedAtUtc: '2026-09-01T12:00:00Z', publicationStatus: 2,
}
export const discoveryProjectDetail = {
  ...discoveryProject, countries: workspacePublicProject.countries, regions: workspacePublicProject.regions,
  categories: workspacePublicProject.categories, beneficiaryTypes: workspacePublicProject.beneficiaryTypes,
  projectTypes: workspacePublicProject.projectTypes, sustainableDevelopmentGoals: workspacePublicProject.sustainableDevelopmentGoals,
}
export const discoveryOrganization = {
  publicId: workspaceProfile.publicId, name: workspaceProfile.name, description: 'Descripción pública original Ñandú.',
  websiteUrl: 'https://organization.example.invalid', establishedYear: 2010,
  homeCountry: workspaceCatalogs.countries[0], organizationType: workspaceCatalogs.organizationTypes[0],
  organizationSize: workspaceCatalogs.organizationSizes[0], countries: workspaceCatalogs.countries,
  regions: workspaceCatalogs.regions, categories: [workspaceCatalogs.fundingCategories[0]],
  beneficiaryTypes: workspaceCatalogs.beneficiaryTypes, projectTypes: workspaceCatalogs.projectTypes,
  projects: [discoveryProject],
}
