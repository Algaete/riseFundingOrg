// Complete resource shape for type checking and parity tests. Runtime loading
// imports individual modules via resource-loader.ts, never this aggregate.
import { coreEs } from './core/es'
import { validationEs } from './validation/es'
import { operationsEs } from './operations/es'
import { adminDashboardEs } from './admin-dashboard/es'
import { adminUsersEs } from './admin-users/es'
import { adminOrganizationsEs } from './admin-organizations/es'
import { adminIncidentsEs } from './admin-incidents/es'
import { adminBillingEs } from './admin-billing/es'
import { adminImportsEs } from './admin-imports/es'
import { sourceDocumentsEs } from './source-documents/es'
import { operationalLabelsEs } from './operational-labels/es'
import { editorialEs } from './editorial/es'
import { adminFundersEs } from './admin-funders/es'
import { adminFundingEs } from './admin-funding/es'
import { adminProjectsEs } from './admin-projects/es'
import { editorialValidationEs } from './editorial-validation/es'
import { authEs } from './auth/es'
import { catalogsEs } from './catalogs/es'
import { trackingEs } from './tracking/es'
import { applicationsEs } from './applications/es'
import { calendarEs } from './calendar/es'
import { alertsEs } from './alerts/es'
import { billingEs } from './billing/es'
import { matchingEs } from './matching/es'
import { networkEs } from './network/es'
import { collaborationFeedbackEs } from './collaboration-feedback/es'
import { organizationFundingEs } from './organization-funding/es'
import { fundingCatalogEs } from './funding-catalog/es'
import { marketplaceEs } from './marketplace/es'
import { discoveryFeedbackEs } from './discovery-feedback/es'
import { dashboardEs } from './dashboard/es'
import { accountEs } from './account/es'
import { organizationEs } from './organization/es'
import { projectsEs } from './projects/es'
import { projectAssetsEs } from './project-assets/es'
import { projectMapEs } from './project-map/es'
import { workspaceFeedbackEs } from './workspace-feedback/es'

export const es = {
  translation: {
    ...coreEs,
    validation: validationEs,
    operations: operationsEs,
    adminDashboard: adminDashboardEs,
    adminUsers: adminUsersEs,
    adminOrganizations: adminOrganizationsEs,
    adminIncidents: adminIncidentsEs,
    adminBilling: adminBillingEs,
    adminImports: adminImportsEs,
    sourceDocuments: sourceDocumentsEs,
    operationalLabels: operationalLabelsEs,
    editorial: editorialEs,
    adminFunders: adminFundersEs,
    adminFunding: adminFundingEs,
    adminProjects: adminProjectsEs,
    editorialValidation: editorialValidationEs,
    auth: authEs,
    catalogs: catalogsEs,
    tracking: trackingEs,
    applications: applicationsEs,
    calendar: calendarEs,
    alerts: alertsEs,
    billing: billingEs,
    matching: matchingEs,
    network: networkEs,
    collaborationFeedback: collaborationFeedbackEs,
    organizationFunding: organizationFundingEs,
    fundingCatalog: fundingCatalogEs,
    marketplace: marketplaceEs,
    discoveryFeedback: discoveryFeedbackEs,
    dashboard: dashboardEs,
    account: accountEs,
    organization: organizationEs,
    projects: projectsEs,
    projectAssets: projectAssetsEs,
    projectMap: projectMapEs,
    workspaceFeedback: workspaceFeedbackEs,
  },
} as const
