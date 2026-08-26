import { PagePlaceholder } from '@/components/page-placeholder'
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

export function AdminDashboardPage() {
  return (
    <PagePlaceholder
      title="Administración"
      description="Indicadores operacionales, ingestas recientes y tareas pendientes."
      eyebrow="Administración"
    />
  )
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
  return (
    <PagePlaceholder
      title="Organizaciones"
      description="Consulta y soporte de perfiles institucionales."
      eyebrow="Administración"
    />
  )
}

export function AdminSubscriptionsPage() {
  return <AdminBillingPage />
}

export function AdminErrorsPage() {
  return (
    <PagePlaceholder
      title="Errores operacionales"
      description="Diagnóstico de fallos de ingesta, IA e integraciones."
      eyebrow="Administración"
    />
  )
}
