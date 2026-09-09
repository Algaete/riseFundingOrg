import { organizationFundingCatalogs, organizationOpportunity } from './organization-funding'
import { discoveryOrganization } from './public-discovery'
import { networkOrganization } from './matching-network'

// Synthetic catalogs mix reviewed seeds and unreviewed source labels. IDs and
// codes can coincide between catalog kinds; these are never database writes.
export const consumerCatalogs = {
  ...organizationFundingCatalogs,
  fundingCategories: [
    { id: 1, code: 'ENVIRONMENT', name: 'Medio ambiente y biodiversidad' },
    { id: 81, code: 'EDUCATION', name: 'Educación comunitaria Ñandú' },
    { id: 82, code: 'NEW_CATEGORY', name: 'Nueva área Ñandú' },
    { id: 16, code: 'OTHER', name: 'Otros' },
  ],
  projectTypes: [...organizationFundingCatalogs.projectTypes, { id: 16, code: 'OTHER', name: 'Otros' }],
  currencies: [...organizationFundingCatalogs.currencies, { code: 'EUR', name: 'Euro de prueba Ñandú', minorUnits: 2 }],
  languages: [...organizationFundingCatalogs.languages, { id: 2, code: 'en', name: 'Inglés' }],
  tags: [{ id: 9, code: 'ENVIRONMENT', name: 'Medio ambiente' }],
}

export const consumerOpportunity = {
  ...organizationOpportunity, categoryIds: [1, 81, 82, 16], projectTypeIds: [4, 16],
  languages: [{ id: 1, languagePurpose: 1 }, { id: 2, languagePurpose: 2 }],
}

export const consumerPublicOrganization = {
  ...discoveryOrganization, categories: consumerCatalogs.fundingCategories,
  projectTypes: consumerCatalogs.projectTypes,
}

export const consumerNetworkOrganization = {
  ...networkOrganization, categories: consumerCatalogs.fundingCategories,
  homeCountry: { id: 999, code: 'NEW_COUNTRY', name: 'Territorio Ñandú' },
}
