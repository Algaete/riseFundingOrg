import {
  AdminOrganizationDetailPage as AdminOrganizationDetailWorkspacePage,
  AdminOrganizationsWorkspacePage,
} from '@/features/admin-organizations/admin-organization-pages'
import { AdminErrorsWorkspacePage } from '@/features/admin-errors/admin-error-pages'
import {
  AdminImportRunDetailPage,
  AdminImportRunsPage,
  AdminImportSourcesPage,
} from '@/features/imports/admin-import-pages'
import {
  AdminSourceDocumentDetailPage,
  AdminSourceDocumentUploadPage,
} from '@/features/source-documents/source-document-pages'
import { AdminBillingPage } from '@/features/billing/billing-pages'
import { AdminUsersWorkspacePage } from '@/features/admin-users/admin-user-pages'
import { AdminDashboardWorkspacePage } from '@/features/admin-dashboard/admin-dashboard-page'

export function AdminDashboardPage() {
  return <AdminDashboardWorkspacePage />
}

export function AdminImportsPage() {
  return <AdminImportRunsPage />
}

export function AdminImportDetailPage() {
  return <AdminImportRunDetailPage />
}

export function AdminSourcesPage() {
  return <AdminImportSourcesPage />
}

export function AdminSourceDocumentUploadRoutePage() {
  return <AdminSourceDocumentUploadPage />
}

export function AdminSourceDocumentDetailRoutePage() {
  return <AdminSourceDocumentDetailPage />
}

export function AdminUsersPage() {
  return <AdminUsersWorkspacePage />
}

export function AdminOrganizationsPage() {
  return <AdminOrganizationsWorkspacePage />
}

export function AdminOrganizationDetailPage() {
  return <AdminOrganizationDetailWorkspacePage />
}

export function AdminSubscriptionsPage() {
  return <AdminBillingPage />
}

export function AdminErrorsPage() {
  return <AdminErrorsWorkspacePage />
}
