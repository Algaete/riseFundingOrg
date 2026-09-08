// Synthetic data only. Shared by unit and browser tests, never real accounts.
export const workspaceOrganizationId = '11111111-1111-1111-1111-111111111111'
export const workspaceProjectId = '22222222-2222-2222-2222-222222222222'
export const workspaceCatalogs = {
  countries: [{ id: 152, code: 'CL', name: 'Chile' }],
  regions: [{ id: 7, code: 'CL-RM', countryId: 152, name: 'Metropolitana' }],
  currencies: [{ code: 'USD', name: 'Dólar estadounidense', minorUnits: 2 }],
  organizationTypes: [{ id: 2, code: 'FOUNDATION', name: 'Fundación' }],
  legalEntityTypes: [{ id: 1, countryId: 152, code: 'CL_FOUNDATION', name: 'Fundación' }],
  organizationSizes: [{ id: 10, code: 'EMPLOYEES_1_10', name: '1–10 personas' }],
  fundingCategories: [{ id: 1, code: 'ENVIRONMENT', name: 'Medio ambiente' }, { id: 16, code: 'OTHER', name: 'Otros' }],
  beneficiaryTypes: [{ id: 1, code: 'CHILDREN', name: 'Niños, niñas y adolescentes' }],
  projectTypes: [{ id: 4, code: 'CAPACITY_BUILDING', name: 'Fortalecimiento institucional' }],
  sustainableDevelopmentGoals: [{ id: 6, code: 'SDG_06', name: 'Agua limpia y saneamiento' }, { id: 17, code: 'SDG_17', name: 'Alianzas para lograr los objetivos' }],
  languages: [{ id: 1, code: 'es', name: 'Español' }, { id: 5, code: 'und', name: 'Otro' }],
  fundingExperienceTypes: [{ id: 1, code: 'GOVERNMENTS_PUBLIC_FUNDS', name: 'Gobiernos / fondos públicos' }],
  fundingTypes: [], tags: [],
}

export const workspaceProfile = {
  publicId: workspaceOrganizationId, name: 'Fundación Ñandú', legalName: null, taxIdentifier: null,
  homeCountryId: 152, organizationTypeId: 2, legalEntityTypeId: null, organizationSizeId: 10,
  establishedYear: null, websiteUrl: null, description: 'Descripción original sin traducir',
  previousFundingExperience: 0, experienceSummary: null,
  annualBudgetMin: null, annualBudgetMax: null, annualBudgetCurrency: null,
  desiredFundingMin: null, desiredFundingMax: null, desiredFundingCurrency: null,
  profileStatus: 2, profileCompleteness: 100, profileVersion: 1, membershipRole: 'admin' as const, canEdit: true,
  eTag: '"0000000000000001"', countryIds: [152], regionIds: [7], categoryIds: [1],
  beneficiaryTypeIds: [1], projectTypeIds: [4], tagIds: [], languages: [{ languageId: 1, proficiency: null }],
  fundingExperienceTypeIds: [], customImpactAreas: ['Cultura Ñandú'], customBeneficiaryTypes: [], customProjectTypes: [], customLanguages: [],
}

export const workspaceProject = {
  publicId: workspaceProjectId, slug: 'proyecto-sintetico', title: 'Agua segura Ñandú',
  summary: 'Resumen original sin traducir', description: 'Descripción original del proyecto',
  status: 2, projectStage: 2, publicationStatus: 0, startDate: '2027-01-01', endDate: '2027-12-31',
  budgetTotal: 100000, confirmedFunding: 25000, currency: 'USD', fundingGap: 75000,
  projectVersion: 1, updatedAtUtc: '2026-09-01T12:00:00Z', eTag: '"0000000000000001"',
  countryIds: [152], regionIds: [7], categoryIds: [1], beneficiaryTypeIds: [1], projectTypeIds: [4],
  sustainableDevelopmentGoalIds: [6], submittedAtUtc: null, reviewedAtUtc: null, rejectionReason: null, publishedAtUtc: null,
}

export const workspacePublicProject = {
  projectId: workspaceProjectId, slug: workspaceProject.slug, title: workspaceProject.title,
  summary: workspaceProject.summary, description: workspaceProject.description,
  projectStatus: 2, projectStage: 2, startDate: '2027-01-01', endDate: '2027-12-31',
  budgetTotal: 100000, confirmedFunding: 25000, currency: 'USD', fundingGap: 75000,
  publishedAtUtc: '2026-09-01T12:00:00Z',
  organization: { publicId: workspaceOrganizationId, name: workspaceProfile.name, websiteUrl: 'https://example.invalid' },
  countries: workspaceCatalogs.countries, regions: workspaceCatalogs.regions,
  categories: [workspaceCatalogs.fundingCategories[0]], beneficiaryTypes: workspaceCatalogs.beneficiaryTypes,
  projectTypes: workspaceCatalogs.projectTypes, sustainableDevelopmentGoals: [workspaceCatalogs.sustainableDevelopmentGoals[0]],
}
