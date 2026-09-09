// Complete resource shape for type checking and parity tests. Runtime loading
// imports individual modules via resource-loader.ts, never this aggregate.
import { coreEn } from './core/en'
import { validationEn } from './validation/en'
import { operationsEn } from './operations/en'
import { adminDashboardEn } from './admin-dashboard/en'
import { adminUsersEn } from './admin-users/en'
import { adminOrganizationsEn } from './admin-organizations/en'
import { adminIncidentsEn } from './admin-incidents/en'
import { adminBillingEn } from './admin-billing/en'
import { adminImportsEn } from './admin-imports/en'
import { sourceDocumentsEn } from './source-documents/en'
import { operationalLabelsEn } from './operational-labels/en'
import { editorialEn } from './editorial/en'
import { adminFundersEn } from './admin-funders/en'
import { adminFundingEn } from './admin-funding/en'
import { adminProjectsEn } from './admin-projects/en'
import { editorialValidationEn } from './editorial-validation/en'
import { authEn } from './auth/en'
import { catalogsEn } from './catalogs/en'
import { trackingEn } from './tracking/en'
import { applicationsEn } from './applications/en'
import { calendarEn } from './calendar/en'
import { alertsEn } from './alerts/en'
import { billingEn } from './billing/en'
import { matchingEn } from './matching/en'
import { networkEn } from './network/en'
import { collaborationFeedbackEn } from './collaboration-feedback/en'
import { organizationFundingEn } from './organization-funding/en'
import { fundingCatalogEn } from './funding-catalog/en'
import { marketplaceEn } from './marketplace/en'
import { discoveryFeedbackEn } from './discovery-feedback/en'
import { dashboardEn } from './dashboard/en'
import { accountEn } from './account/en'
import { organizationEn } from './organization/en'
import { projectsEn } from './projects/en'
import { projectAssetsEn } from './project-assets/en'
import { projectMapEn } from './project-map/en'
import { funderWorkspaceEn } from './funder-workspace/en'
import { workspaceFeedbackEn } from './workspace-feedback/en'

export const en = {
  translation: {
    ...coreEn,
    validation: validationEn,
    operations: operationsEn,
    adminDashboard: adminDashboardEn,
    adminUsers: adminUsersEn,
    adminOrganizations: adminOrganizationsEn,
    adminIncidents: adminIncidentsEn,
    adminBilling: adminBillingEn,
    adminImports: adminImportsEn,
    sourceDocuments: sourceDocumentsEn,
    operationalLabels: operationalLabelsEn,
    editorial: editorialEn,
    adminFunders: adminFundersEn,
    adminFunding: adminFundingEn,
    adminProjects: adminProjectsEn,
    editorialValidation: editorialValidationEn,
    auth: authEn,
    catalogs: catalogsEn,
    tracking: trackingEn,
    applications: applicationsEn,
    calendar: calendarEn,
    alerts: alertsEn,
    billing: billingEn,
    matching: matchingEn,
    network: networkEn,
    collaborationFeedback: collaborationFeedbackEn,
    organizationFunding: organizationFundingEn,
    fundingCatalog: fundingCatalogEn,
    marketplace: marketplaceEn,
    discoveryFeedback: discoveryFeedbackEn,
    dashboard: dashboardEn,
    account: accountEn,
    organization: organizationEn,
    projects: projectsEn,
    projectAssets: projectAssetsEn,
    projectMap: projectMapEn,
    funderWorkspace: funderWorkspaceEn,
    workspaceFeedback: workspaceFeedbackEn,
  },
} as const
