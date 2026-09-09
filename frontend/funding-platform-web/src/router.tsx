/* oxlint-disable react/only-export-components -- Lazy route components intentionally live with the route table. */
import { lazy, type ComponentType } from 'react'
import { ensureInterfaceResources } from '@/i18n'
import type { ResourceModule } from '@/i18n/resource-loader'
import { createBrowserRouter, Navigate, type RouteObject, useLocation } from 'react-router-dom'

import { ProtectedRoute } from '@/features/auth/auth-provider'

function localizedLazy<T extends ComponentType>(loader: () => Promise<{ default: T }>, modules: readonly ResourceModule[]) {
  return lazy(async () => {
    const [component] = await Promise.all([loader(), ensureInterfaceResources(modules)])
    return component
  })
}

const AppShell = localizedLazy(() => import('@/components/app-shell').then((module) => ({ default: module.AppShell })), [])
const PublicLayout = localizedLazy(() => import('@/components/public-layout').then((module) => ({ default: module.PublicLayout })), [])

const AccountPage = localizedLazy(() => import('@/pages/app-pages').then((module) => ({ default: module.AccountPage })), ["account","auth","workspaceFeedback","validation"])
const AlertsPage = localizedLazy(() => import('@/features/alerts/alerts-pages').then((module) => ({ default: module.AlertsWorkspacePage })), ["alerts","tracking","organizationFunding","fundingCatalog","catalogs","workspaceFeedback","validation"])
const AlertUnsubscribePage = localizedLazy(() => import('@/features/alerts/alerts-pages').then((module) => ({ default: module.AlertUnsubscribePage })), ["alerts","tracking","validation"])
const ApplicationsPage = localizedLazy(() => import('@/features/applications/application-pages').then((module) => ({ default: module.ApplicationsWorkspacePage })), ["applications","tracking","dashboard","projects","organizationFunding","catalogs","workspaceFeedback","validation"])
const CalendarPage = localizedLazy(() => import('@/features/calendar/calendar-pages').then((module) => ({ default: module.CalendarWorkspacePage })), ["calendar","tracking","dashboard","workspaceFeedback","validation"])
const DashboardPage = localizedLazy(() => import('@/pages/app-pages').then((module) => ({ default: module.DashboardPage })), ["dashboard","tracking","workspaceFeedback","validation"])
const FundingDetailPage = localizedLazy(() => import('@/features/funding/funding-pages').then((module) => ({ default: module.FundingOpportunityDetailPage })), ["fundingCatalog","catalogs","discoveryFeedback","workspaceFeedback","validation"])
const FundingPage = localizedLazy(() => import('@/features/funding/funding-pages').then((module) => ({ default: module.FundingCatalogPage })), ["fundingCatalog","catalogs","discoveryFeedback","workspaceFeedback","validation"])
const OrganizationFavoritesPage = localizedLazy(() => import('@/features/funding/organization-funding-pages').then((module) => ({ default: module.OrganizationFavoritesPage })), ["organizationFunding","fundingCatalog","catalogs","workspaceFeedback","validation"])
const OrganizationFundingDetailPage = localizedLazy(() => import('@/features/funding/organization-funding-pages').then((module) => ({ default: module.OrganizationFundingDetailPage })), ["organizationFunding","fundingCatalog","catalogs","workspaceFeedback","validation"])
const OrganizationFundingPage = localizedLazy(() => import('@/features/funding/organization-funding-pages').then((module) => ({ default: module.OrganizationFundingCatalogPage })), ["organizationFunding","fundingCatalog","catalogs","workspaceFeedback","validation"])
const OnboardingPage = localizedLazy(() => import('@/pages/app-pages').then((module) => ({ default: module.OnboardingPage })), ["organization","catalogs","workspaceFeedback","projectAssets","validation"])
const OrganizationProfilePage = localizedLazy(() => import('@/pages/app-pages').then((module) => ({ default: module.OrganizationProfilePage })), ["organization","catalogs","workspaceFeedback","projectAssets","validation"])
const ProjectsPage = localizedLazy(() => import('@/features/projects/project-pages').then((module) => ({ default: module.ProjectsPage })), ["projects","projectAssets","catalogs","workspaceFeedback","validation"])
const ProjectDetailPage = localizedLazy(() => import('@/features/projects/project-pages').then((module) => ({ default: module.ProjectDetailPage })), ["projects","projectAssets","catalogs","workspaceFeedback","validation"])
const PublicProjectPage = localizedLazy(() => import('@/features/projects/project-publication-pages').then((module) => ({ default: module.PublicProjectPage })), ["projects","projectAssets","catalogs","workspaceFeedback","validation"])
const MarketplacePage = localizedLazy(() => import('@/features/marketplace/marketplace-pages').then((module) => ({ default: module.MarketplacePage })), ["marketplace","projects","catalogs","discoveryFeedback","workspaceFeedback","validation"])
const MarketplaceProjectDetailPage = localizedLazy(() => import('@/features/marketplace/marketplace-pages').then((module) => ({ default: module.MarketplaceProjectDetailPage })), ["marketplace","projects","catalogs","discoveryFeedback","workspaceFeedback","validation"])
const MarketplaceOrganizationPage = localizedLazy(() => import('@/features/marketplace/marketplace-pages').then((module) => ({ default: module.MarketplaceOrganizationPage })), ["marketplace","projects","catalogs","discoveryFeedback","workspaceFeedback","validation"])
const MatchingPage = localizedLazy(() => import('@/features/matching/matching-pages').then((module) => ({ default: module.MatchingWorkspacePage })), ["matching","collaborationFeedback","catalogs","workspaceFeedback","validation"])
const NetworkPage = localizedLazy(() => import('@/features/network/network-pages').then((module) => ({ default: module.NetworkWorkspacePage })), ["network","collaborationFeedback","catalogs","workspaceFeedback","validation"])
const SubscriptionPage = localizedLazy(() => import('@/pages/app-pages').then((module) => ({ default: module.SubscriptionPage })), ["billing","tracking","workspaceFeedback","validation"])

const AdminDashboardPage = localizedLazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminDashboardPage })), ["adminDashboard","operations","operationalLabels","validation","editorial","editorialValidation","workspaceFeedback","adminProjects","adminFunders","adminIncidents"])
const AdminProjectReviewPage = localizedLazy(() => import('@/features/projects/project-publication-pages').then((module) => ({ default: module.AdminProjectReviewPage })), ["adminProjects","projects","projectAssets","editorial","editorialValidation","catalogs","workspaceFeedback","validation","adminFunding"])
const AdminProjectReviewDetailPage = localizedLazy(() => import('@/features/projects/project-publication-pages').then((module) => ({ default: module.AdminProjectReviewDetailPage })), ["adminProjects","projects","projectAssets","editorial","editorialValidation","catalogs","workspaceFeedback","validation","adminFunding"])
const AdminErrorsPage = localizedLazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminErrorsPage })), ["adminIncidents","operations","operationalLabels","validation","editorial","editorialValidation","workspaceFeedback"])
const AdminFundingDetailPage = localizedLazy(() => import('@/features/funding/admin-funding-pages').then((module) => ({ default: module.AdminFundingDetailPage })), ["adminFunding","adminFunders","editorial","editorialValidation","catalogs","validation","workspaceFeedback"])
const AdminFundingPage = localizedLazy(() => import('@/features/funding/admin-funding-pages').then((module) => ({ default: module.AdminFundingPage })), ["adminFunding","adminFunders","editorial","editorialValidation","catalogs","validation","workspaceFeedback"])
const AdminFunderDetailPage = localizedLazy(() => import('@/features/funding/admin-funder-pages').then((module) => ({ default: module.AdminFunderDetailPage })), ["adminFunders","editorial","editorialValidation","catalogs","validation","workspaceFeedback"])
const AdminFundersPage = localizedLazy(() => import('@/features/funding/admin-funder-pages').then((module) => ({ default: module.AdminFundersPage })), ["adminFunders","editorial","editorialValidation","catalogs","validation","workspaceFeedback"])
const AdminImportDetailPage = localizedLazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminImportDetailPage })), ["adminImports","operations","operationalLabels","validation","editorial","editorialValidation","workspaceFeedback","adminFunding"])
const AdminImportsPage = localizedLazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminImportsPage })), ["adminImports","operations","operationalLabels","validation","editorial","editorialValidation","workspaceFeedback","adminFunding"])
const AdminOrganizationsPage = localizedLazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminOrganizationsPage })), ["adminOrganizations","operations","operationalLabels","catalogs","validation","editorial","editorialValidation","workspaceFeedback","adminFunders"])
const AdminOrganizationDetailPage = localizedLazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminOrganizationDetailPage })), ["adminOrganizations","operations","operationalLabels","catalogs","validation","editorial","editorialValidation","workspaceFeedback","adminFunders"])
const AdminSourceDocumentDetailRoutePage = localizedLazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminSourceDocumentDetailRoutePage })), ["sourceDocuments","operations","operationalLabels","validation","editorial","editorialValidation","workspaceFeedback","adminFunding","adminImports"])
const AdminSourceDocumentUploadRoutePage = localizedLazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminSourceDocumentUploadRoutePage })), ["sourceDocuments","operations","operationalLabels","validation","editorial","editorialValidation","workspaceFeedback","adminFunding","adminImports"])
const AdminSourcesPage = localizedLazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminSourcesPage })), ["adminImports","operations","operationalLabels","validation","editorial","editorialValidation","workspaceFeedback","adminFunding"])
const AdminSubscriptionsPage = localizedLazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminSubscriptionsPage })), ["adminBilling","billing","tracking","operations","operationalLabels","validation","editorial","editorialValidation","workspaceFeedback"])
const AdminUsersPage = localizedLazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminUsersPage })), ["adminUsers","operations","operationalLabels","validation","editorial","editorialValidation","workspaceFeedback"])

const ForgotPasswordPage = localizedLazy(() => import('@/pages/public-pages').then((module) => ({ default: module.ForgotPasswordPage })), ["auth","validation"])
const ExternalAuthenticationCallbackPage = localizedLazy(() => import('@/pages/public-pages').then((module) => ({ default: module.ExternalAuthenticationCallbackPage })), ["auth","validation"])
const HomePage = localizedLazy(() => import('@/pages/public-pages').then((module) => ({ default: module.HomePage })), [])
const LoginPage = localizedLazy(() => import('@/pages/public-pages').then((module) => ({ default: module.LoginPage })), ["auth","validation"])
const MfaChallengePage = localizedLazy(() => import('@/pages/public-pages').then((module) => ({ default: module.MfaChallengePage })), ["auth","validation"])
const MfaSetupPage = localizedLazy(() => import('@/pages/public-pages').then((module) => ({ default: module.MfaSetupPage })), ["auth","validation"])
const NotFoundPage = localizedLazy(() => import('@/pages/public-pages').then((module) => ({ default: module.NotFoundPage })), [])
const PricingPage = localizedLazy(() => import('@/pages/public-pages').then((module) => ({ default: module.PricingPage })), ["billing","tracking","workspaceFeedback","validation"])
const RegisterPage = localizedLazy(() => import('@/pages/public-pages').then((module) => ({ default: module.RegisterPage })), ["auth","validation"])
const ResetPasswordPage = localizedLazy(() => import('@/pages/public-pages').then((module) => ({ default: module.ResetPasswordPage })), ["auth","validation"])
const VerifyEmailPage = localizedLazy(() => import('@/pages/public-pages').then((module) => ({ default: module.VerifyEmailPage })), ["auth","validation"])

const ProjectMapPage = localizedLazy(() => import('@/features/project-map/project-map-page').then(module => ({ default: module.ProjectMapPage })), ['projectMap', 'projects', 'catalogs', 'validation'])

function LegacyMatchingRedirect() {
  const location = useLocation()
  return <Navigate replace to={{ pathname: '/matching', search: location.search }} />
}

const FunderWorkspaceLayout = localizedLazy(() => import('@/features/funder-workspace/funder-workspace-layout').then(module => ({ default: module.FunderWorkspaceLayout })), ['funderWorkspace'])

const ProfessionalProfilePage = localizedLazy(() => import('@/features/collaboration/professional-profile-page').then(module => ({ default: module.ProfessionalProfilePage })), ['collaboration', 'catalogs', 'validation'])
const ProfessionalDirectoryPage = localizedLazy(() => import('@/features/collaboration/professional-directory-page').then(module => ({ default: module.ProfessionalDirectoryPage })), ['collaboration', 'catalogs', 'validation'])
const ConsortiumListPage = localizedLazy(() => import('@/features/collaboration/consortium-list-page').then(module => ({ default: module.ConsortiumListPage })), ['collaboration', 'validation'])
const ConsortiumDetailPage = localizedLazy(() => import('@/features/collaboration/consortium-detail-page').then(module => ({ default: module.ConsortiumDetailPage })), ['collaboration', 'validation'])

const DiscoveryMatchingPage = localizedLazy(() => import('@/features/matching/discovery-matching-page').then(module => ({ default: module.DiscoveryMatchingPage })), ['ecosystem', 'collaboration', 'projects', 'catalogs', 'validation'])

const FundingExplorerPage = localizedLazy(() => import('@/features/funding-discovery/funding-discovery-pages').then(module => ({ default: module.FundingExplorerPage })), ['fundingDiscovery', 'collaboration', 'catalogs', 'validation'])
const FundingClassificationPage = localizedLazy(() => import('@/features/funding-discovery/funding-discovery-pages').then(module => ({ default: module.FundingClassificationPage })), ['fundingDiscovery', 'collaboration', 'validation'])

export const appRoutes: RouteObject[] = [
  {
    element: <PublicLayout />,
    children: [
      { path: '/', element: <HomePage /> },
      { path: '/pricing', element: <PricingPage /> },
      { path: '/funding', element: <FundingPage /> },
      { path: '/funding/explore', element: <FundingExplorerPage /> },
      { path: '/funding/:slug', element: <FundingDetailPage /> },
      { path: '/marketplace', element: <MarketplacePage /> },
      { path: '/marketplace/map', element: <ProjectMapPage /> },
      { path: '/marketplace/projects/:slug', element: <MarketplaceProjectDetailPage /> },
      { path: '/marketplace/organizations/:organizationId', element: <MarketplaceOrganizationPage /> },
      { path: '/login', element: <LoginPage /> },
      { path: '/register', element: <RegisterPage /> },
      { path: '/verify-email', element: <VerifyEmailPage /> },
      { path: '/forgot-password', element: <ForgotPasswordPage /> },
      { path: '/auth/external/callback', element: <ExternalAuthenticationCallbackPage /> },
      { path: '/projects/public/:slug', element: <PublicProjectPage /> },
      { path: '/reset-password', element: <ResetPasswordPage /> },
      { path: '/alerts/unsubscribe', element: <AlertUnsubscribePage /> },
      { path: '/mfa', element: <MfaChallengePage /> },
      { path: '/mfa/setup', element: <MfaSetupPage /> },
    ],
  },
  {
    element: <ProtectedRoute><AppShell /></ProtectedRoute>,
    children: [
      { path: '/onboarding', element: <OnboardingPage /> },
      { path: '/dashboard', element: <DashboardPage /> },
      { path: '/opportunities', element: <OrganizationFundingPage /> },
      { path: '/opportunities/:slug', element: <OrganizationFundingDetailPage /> },
      { path: '/matching', element: <MatchingPage /> },
      { path: '/matching/ecosystem', element: <DiscoveryMatchingPage /> },
      { path: '/recommended', element: <LegacyMatchingRedirect /> },
      { path: '/favorites', element: <OrganizationFavoritesPage /> },
      { path: '/applications', element: <ApplicationsPage /> },
      { path: '/calendar', element: <CalendarPage /> },
      { path: '/alerts', element: <AlertsPage /> },
      { path: '/network', element: <NetworkPage /> },
      { path: '/professional/profile', element: <ProfessionalProfilePage /> },
      { path: '/professionals', element: <ProfessionalDirectoryPage /> },
      { path: '/collaboration/consortia', element: <ConsortiumListPage /> },
      { path: '/collaboration/consortia/:id', element: <ConsortiumDetailPage /> },
      { path: '/organization/profile', element: <OrganizationProfilePage /> },
      { path: '/projects', element: <ProjectsPage /> },
      { path: '/projects/:projectId', element: <ProjectDetailPage /> },
      { path: '/account', element: <AccountPage /> },
      { path: '/subscription', element: <SubscriptionPage /> },
      { path: '/funder-workspace', element: <FunderWorkspaceLayout />, children: [
        { index: true, element: <Navigate replace to="/funder-workspace/funders" /> },
        { path: 'funders', element: <AdminFundersPage /> },
        { path: 'funders/:id', element: <AdminFunderDetailPage /> },
        { path: 'funding', element: <AdminFundingPage /> },
        { path: 'funding/:id', element: <AdminFundingDetailPage /> },
      ] },
    ],
  },
  {
    element: <ProtectedRoute requireAdmin><AppShell mode="admin" /></ProtectedRoute>,
    children: [
      { path: '/admin', element: <AdminDashboardPage /> },
      { path: '/admin/projects', element: <AdminProjectReviewPage /> },
      { path: '/admin/projects/:projectId', element: <AdminProjectReviewDetailPage /> },
      { path: '/admin/funding', element: <AdminFundingPage /> },
      { path: '/admin/funding/:id', element: <AdminFundingDetailPage /> },
      { path: '/admin/funding/:id/discovery', element: <FundingClassificationPage /> },
      { path: '/admin/funders', element: <AdminFundersPage /> },
      { path: '/admin/funders/:id', element: <AdminFunderDetailPage /> },
      { path: '/admin/imports', element: <AdminImportsPage /> },
      { path: '/admin/imports/upload-document', element: <AdminSourceDocumentUploadRoutePage /> },
      { path: '/admin/imports/:id', element: <AdminImportDetailPage /> },
      { path: '/admin/source-documents/:id', element: <AdminSourceDocumentDetailRoutePage /> },
      { path: '/admin/sources', element: <AdminSourcesPage /> },
      { path: '/admin/users', element: <AdminUsersPage /> },
      { path: '/admin/organizations', element: <AdminOrganizationsPage /> },
      { path: '/admin/organizations/:organizationId', element: <AdminOrganizationDetailPage /> },
      { path: '/admin/subscriptions', element: <AdminSubscriptionsPage /> },
      { path: '/admin/errors', element: <AdminErrorsPage /> },
    ],
  },
  { path: '*', element: <NotFoundPage /> },
]

export const appRouter = createBrowserRouter(appRoutes)
