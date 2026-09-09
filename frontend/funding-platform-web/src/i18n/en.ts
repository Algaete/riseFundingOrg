import type { es } from '@/i18n/es'
import { editorialEn } from '@/i18n/editorial/en'
import { adminFundersEn } from '@/i18n/admin-funders/en'
import { adminFundingEn } from '@/i18n/admin-funding/en'
import { adminProjectsEn } from '@/i18n/admin-projects/en'
import { editorialValidationEn } from '@/i18n/editorial-validation/en'
import { validationEn } from '@/i18n/validation/en'
import { authEn } from '@/i18n/auth/en'
import { catalogsEn } from '@/i18n/catalogs/en'
import { trackingEn } from '@/i18n/tracking/en'
import { applicationsEn } from '@/i18n/applications/en'
import { calendarEn } from '@/i18n/calendar/en'
import { alertsEn } from '@/i18n/alerts/en'
import { billingEn } from '@/i18n/billing/en'
import { matchingEn } from '@/i18n/matching/en'
import { networkEn } from '@/i18n/network/en'
import { collaborationFeedbackEn } from '@/i18n/collaboration-feedback/en'
import { organizationFundingEn } from '@/i18n/organization-funding/en'
import { fundingCatalogEn } from '@/i18n/funding-catalog/en'
import { marketplaceEn } from '@/i18n/marketplace/en'
import { discoveryFeedbackEn } from '@/i18n/discovery-feedback/en'
import { dashboardEn } from '@/i18n/dashboard/en'
import { accountEn } from '@/i18n/account/en'
import { organizationEn } from '@/i18n/organization/en'
import { projectsEn } from '@/i18n/projects/en'
import { projectAssetsEn } from '@/i18n/project-assets/en'
import { workspaceFeedbackEn } from '@/i18n/workspace-feedback/en'
import type { TranslationShape } from '@/i18n/resource-types'

export const en = {
  translation: {
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
    workspaceFeedback: workspaceFeedbackEn,
    appName: 'FundingPlatform',
    appTagline: 'Funding that finds good causes',
    language: { label: 'Language' },
    navigation: {
      home: 'Home',
      main: 'Main',
      application: 'Application',
      mobile: 'Mobile navigation',
      overview: 'Overview',
      opportunities: 'Opportunities',
      availableFunding: 'Available funding',
      projects: 'Projects',
      plans: 'Plans',
      recommended: 'Matching',
      favorites: 'Favorites',
      applications: 'Applications',
      calendar: 'Calendar',
      alerts: 'Alerts',
      profile: 'Organization',
      administration: 'Administration',
      connections: 'Connections',
      projectReview: 'Project review',
      funds: 'Funding opportunities',
      funders: 'Funders',
      imports: 'Imports',
      sources: 'Sources',
      users: 'Users',
      organizations: 'Organizations',
      subscriptions: 'Subscriptions',
      errors: 'Errors',
      backToPlatform: 'Back to the platform',
      account: 'My account',
      subscription: 'Subscription',
    },
    actions: {
      signIn: 'Sign in',
      createAccount: 'Create account',
      changeTheme: 'Change theme',
      workspace: 'Go to my workspace',
      signOut: 'Sign out',
      adminPanel: 'Admin panel',
      goToAdminPanel: 'Go to the admin panel',
      findFunding: 'Find funding',
      publishProject: 'Publish my project',
      backToHome: 'Back to home',
    },
    theme: { system: 'System', light: 'Light', dark: 'Dark' },
    layout: {
      adminWorkspace: 'Admin console',
      organizationWorkspace: 'Organization workspace',
      footer: 'FundingPlatform · MVP technical foundation',
    },
    status: { loading: 'Loading…', notFound: 'Page not found' },
    home: {
      eyebrow: 'Projects that find opportunities',
      title: 'Connect your project with the funding and partners it needs',
      description: 'Share your initiatives, discover matching funding opportunities and build partnerships to move from idea to implementation.',
      benefits: {
        projects: {
          title: 'Publish your project',
          description: 'Present its purpose, impact and needs clearly.',
        },
        funding: {
          title: 'Find funding',
          description: 'Explore opportunities and understand why they match your project.',
        },
        partners: {
          title: 'Connect with partners',
          description: 'Discover organizations and build connections to collaborate or form partnerships.',
        },
      },
    },
  },
} as const satisfies TranslationShape<typeof es>
import { operationsEn } from '@/i18n/operations/en'
import { adminDashboardEn } from '@/i18n/admin-dashboard/en'
import { adminUsersEn } from '@/i18n/admin-users/en'
import { adminOrganizationsEn } from '@/i18n/admin-organizations/en'
import { adminIncidentsEn } from '@/i18n/admin-incidents/en'
import { adminBillingEn } from '@/i18n/admin-billing/en'
import { adminImportsEn } from '@/i18n/admin-imports/en'
import { sourceDocumentsEn } from '@/i18n/source-documents/en'
import { operationalLabelsEn } from '@/i18n/operational-labels/en'
