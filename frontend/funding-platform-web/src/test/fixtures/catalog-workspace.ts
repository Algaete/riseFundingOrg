import { catalogsEs } from '../../i18n/catalogs/es'
import { workspaceCatalogs, workspaceProfile } from './project-workspace'

// Synthetic IDs, not a database seed or writable catalog. Browser tests import no API code.
function options(entries: Record<string, { current: string }>) {
  return Object.entries(entries).map(([code, value], index) => ({ id: index + 1, code, name: value.current }))
}

export const bilingualCatalogs = {
  ...workspaceCatalogs,
  organizationSizes: options(catalogsEs.organizationSizes),
  fundingCategories: options(catalogsEs.fundingCategories),
  beneficiaryTypes: options(catalogsEs.beneficiaryTypes),
  projectTypes: options(catalogsEs.projectTypes),
  languages: options(catalogsEs.languages),
  sustainableDevelopmentGoals: options(catalogsEs.sustainableDevelopmentGoals),
  fundingExperienceTypes: options(catalogsEs.fundingExperienceTypes),
}
export const bilingualProfile = {
  ...workspaceProfile, organizationSizeId: 2, projectTypeIds: [1, 4], previousFundingExperience: 2,
  fundingExperienceTypeIds: [1, 4], languages: [{ languageId: 1, proficiency: null }, { languageId: 2, proficiency: null }],
}
