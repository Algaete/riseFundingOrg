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
  return (
    <PagePlaceholder
      title="Usuarios"
      description="Consulta y administración de accesos a la plataforma."
      eyebrow="Administración"
    />
  )
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
  return (
    <PagePlaceholder
      title="Suscripciones"
      description="Operación de planes y estados de suscripción."
      eyebrow="Administración"
    />
  )
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
