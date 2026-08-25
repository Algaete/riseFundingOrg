/* oxlint-disable react/only-export-components -- Lazy route components intentionally live with the route table. */
import { lazy } from 'react'
import { createBrowserRouter, type RouteObject } from 'react-router-dom'

import { ProtectedRoute } from '@/features/auth/auth-provider'

const AppShell = lazy(() => import('@/components/app-shell').then((module) => ({ default: module.AppShell })))
const PublicLayout = lazy(() => import('@/components/public-layout').then((module) => ({ default: module.PublicLayout })))

const AccountPage = lazy(() => import('@/pages/app-pages').then((module) => ({ default: module.AccountPage })))
const AlertsPage = lazy(() => import('@/pages/app-pages').then((module) => ({ default: module.AlertsPage })))
const ApplicationsPage = lazy(() => import('@/features/applications/application-pages').then((module) => ({ default: module.ApplicationsWorkspacePage })))
const CalendarPage = lazy(() => import('@/features/calendar/calendar-pages').then((module) => ({ default: module.CalendarWorkspacePage })))
const DashboardPage = lazy(() => import('@/pages/app-pages').then((module) => ({ default: module.DashboardPage })))
const FundingDetailPage = lazy(() => import('@/features/funding/funding-pages').then((module) => ({ default: module.FundingOpportunityDetailPage })))
const FundingPage = lazy(() => import('@/features/funding/funding-pages').then((module) => ({ default: module.FundingCatalogPage })))
const OrganizationFavoritesPage = lazy(() => import('@/features/funding/organization-funding-pages').then((module) => ({ default: module.OrganizationFavoritesPage })))
const OrganizationFundingDetailPage = lazy(() => import('@/features/funding/organization-funding-pages').then((module) => ({ default: module.OrganizationFundingDetailPage })))
const OrganizationFundingPage = lazy(() => import('@/features/funding/organization-funding-pages').then((module) => ({ default: module.OrganizationFundingCatalogPage })))
const OnboardingPage = lazy(() => import('@/pages/app-pages').then((module) => ({ default: module.OnboardingPage })))
const OrganizationProfilePage = lazy(() => import('@/pages/app-pages').then((module) => ({ default: module.OrganizationProfilePage })))
const ProjectsPage = lazy(() => import('@/features/projects/project-pages').then((module) => ({ default: module.ProjectsPage })))
const ProjectDetailPage = lazy(() => import('@/features/projects/project-pages').then((module) => ({ default: module.ProjectDetailPage })))
const PublicProjectPage = lazy(() => import('@/features/projects/project-publication-pages').then((module) => ({ default: module.PublicProjectPage })))
const MarketplacePage = lazy(() => import('@/features/marketplace/marketplace-pages').then((module) => ({ default: module.MarketplacePage })))
const MarketplaceProjectDetailPage = lazy(() => import('@/features/marketplace/marketplace-pages').then((module) => ({ default: module.MarketplaceProjectDetailPage })))
const MarketplaceOrganizationPage = lazy(() => import('@/features/marketplace/marketplace-pages').then((module) => ({ default: module.MarketplaceOrganizationPage })))
const RecommendedPage = lazy(() => import('@/pages/app-pages').then((module) => ({ default: module.RecommendedPage })))
const SubscriptionPage = lazy(() => import('@/pages/app-pages').then((module) => ({ default: module.SubscriptionPage })))

const AdminDashboardPage = lazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminDashboardPage })))
const AdminProjectReviewPage = lazy(() => import('@/features/projects/project-publication-pages').then((module) => ({ default: module.AdminProjectReviewPage })))
const AdminProjectReviewDetailPage = lazy(() => import('@/features/projects/project-publication-pages').then((module) => ({ default: module.AdminProjectReviewDetailPage })))
const AdminErrorsPage = lazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminErrorsPage })))
const AdminFundingDetailPage = lazy(() => import('@/features/funding/admin-funding-pages').then((module) => ({ default: module.AdminFundingDetailPage })))
const AdminFundingPage = lazy(() => import('@/features/funding/admin-funding-pages').then((module) => ({ default: module.AdminFundingPage })))
const AdminFunderDetailPage = lazy(() => import('@/features/funding/admin-funder-pages').then((module) => ({ default: module.AdminFunderDetailPage })))
const AdminFundersPage = lazy(() => import('@/features/funding/admin-funder-pages').then((module) => ({ default: module.AdminFundersPage })))
const AdminImportDetailPage = lazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminImportDetailPage })))
const AdminImportsPage = lazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminImportsPage })))
const AdminOrganizationsPage = lazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminOrganizationsPage })))
const AdminSourceDocumentDetailRoutePage = lazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminSourceDocumentDetailRoutePage })))
const AdminSourceDocumentUploadRoutePage = lazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminSourceDocumentUploadRoutePage })))
const AdminSourcesPage = lazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminSourcesPage })))
const AdminSubscriptionsPage = lazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminSubscriptionsPage })))
const AdminUsersPage = lazy(() => import('@/pages/admin-pages').then((module) => ({ default: module.AdminUsersPage })))

const ForgotPasswordPage = lazy(() => import('@/pages/public-pages').then((module) => ({ default: module.ForgotPasswordPage })))
const ExternalAuthenticationCallbackPage = lazy(() => import('@/pages/public-pages').then((module) => ({ default: module.ExternalAuthenticationCallbackPage })))
const HomePage = lazy(() => import('@/pages/public-pages').then((module) => ({ default: module.HomePage })))
const LoginPage = lazy(() => import('@/pages/public-pages').then((module) => ({ default: module.LoginPage })))
const MfaChallengePage = lazy(() => import('@/pages/public-pages').then((module) => ({ default: module.MfaChallengePage })))
const MfaSetupPage = lazy(() => import('@/pages/public-pages').then((module) => ({ default: module.MfaSetupPage })))
const NotFoundPage = lazy(() => import('@/pages/public-pages').then((module) => ({ default: module.NotFoundPage })))
const PricingPage = lazy(() => import('@/pages/public-pages').then((module) => ({ default: module.PricingPage })))
const RegisterPage = lazy(() => import('@/pages/public-pages').then((module) => ({ default: module.RegisterPage })))
const ResetPasswordPage = lazy(() => import('@/pages/public-pages').then((module) => ({ default: module.ResetPasswordPage })))
const VerifyEmailPage = lazy(() => import('@/pages/public-pages').then((module) => ({ default: module.VerifyEmailPage })))

export const appRoutes: RouteObject[] = [
  {
    element: <PublicLayout />,
    children: [
      { path: '/', element: <HomePage /> },
      { path: '/pricing', element: <PricingPage /> },
      { path: '/funding', element: <FundingPage /> },
      { path: '/funding/:slug', element: <FundingDetailPage /> },
      { path: '/marketplace', element: <MarketplacePage /> },
      { path: '/marketplace/projects/:slug', element: <MarketplaceProjectDetailPage /> },
      { path: '/marketplace/organizations/:organizationId', element: <MarketplaceOrganizationPage /> },
      { path: '/login', element: <LoginPage /> },
      { path: '/register', element: <RegisterPage /> },
      { path: '/verify-email', element: <VerifyEmailPage /> },
      { path: '/forgot-password', element: <ForgotPasswordPage /> },
      { path: '/auth/external/callback', element: <ExternalAuthenticationCallbackPage /> },
      { path: '/projects/public/:slug', element: <PublicProjectPage /> },
      { path: '/reset-password', element: <ResetPasswordPage /> },
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
      { path: '/recommended', element: <RecommendedPage /> },
      { path: '/favorites', element: <OrganizationFavoritesPage /> },
      { path: '/applications', element: <ApplicationsPage /> },
      { path: '/calendar', element: <CalendarPage /> },
      { path: '/alerts', element: <AlertsPage /> },
      { path: '/organization/profile', element: <OrganizationProfilePage /> },
      { path: '/projects', element: <ProjectsPage /> },
      { path: '/projects/:projectId', element: <ProjectDetailPage /> },
      { path: '/account', element: <AccountPage /> },
      { path: '/subscription', element: <SubscriptionPage /> },
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
      { path: '/admin/funders', element: <AdminFundersPage /> },
      { path: '/admin/funders/:id', element: <AdminFunderDetailPage /> },
      { path: '/admin/imports', element: <AdminImportsPage /> },
      { path: '/admin/imports/upload-document', element: <AdminSourceDocumentUploadRoutePage /> },
      { path: '/admin/imports/:id', element: <AdminImportDetailPage /> },
      { path: '/admin/source-documents/:id', element: <AdminSourceDocumentDetailRoutePage /> },
      { path: '/admin/sources', element: <AdminSourcesPage /> },
      { path: '/admin/users', element: <AdminUsersPage /> },
      { path: '/admin/organizations', element: <AdminOrganizationsPage /> },
      { path: '/admin/subscriptions', element: <AdminSubscriptionsPage /> },
      { path: '/admin/errors', element: <AdminErrorsPage /> },
    ],
  },
  { path: '*', element: <NotFoundPage /> },
]

export const appRouter = createBrowserRouter(appRoutes)
