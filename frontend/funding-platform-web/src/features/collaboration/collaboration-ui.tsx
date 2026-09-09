/* oxlint-disable react/only-export-components -- Shared feature components and keys. */
import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { ApiError } from '@/api/http-client'
import { useAuth } from '@/features/auth/use-auth'
import type { collaborationEs } from '@/i18n/collaboration/es'
import { requestValidationMessage } from '@/i18n/validation-issues'

export type CopyKey = keyof typeof collaborationEs
export const control = 'w-full rounded-lg border bg-background px-3 py-2 text-sm'
export const panel = 'space-y-4 rounded-xl border bg-card p-5'
export const button = 'inline-flex items-center justify-center rounded-lg border px-4 py-2 text-sm font-medium hover:bg-muted disabled:opacity-50 disabled:cursor-not-allowed'
export function useCollaborationActor() { return useAuth().session?.user.publicId ?? 'anonymous' }
export function Field({ label, required = false, children }: { label: string; required?: boolean; children: ReactNode }) {
  return <label className="grid gap-2 text-sm font-medium"><span>{label}{required && ' *'}</span>{children}</label>
}
export function CollaborationHeader({ title }: { title: CopyKey }) {
  const { t } = useTranslation()
  return <header className="space-y-3"><h1 className="text-2xl font-bold">{t(`collaboration.${title}`)}</h1>
    <p className="text-muted-foreground">{t('collaboration.intro')}</p>
    <nav className="flex flex-wrap gap-3" aria-label={t('collaboration.title')}>
      <Link className={button} to="/professional/profile">{t('collaboration.profile')}</Link>
      <Link className={button} to="/professionals">{t('collaboration.directory')}</Link>
      <Link className={button} to="/collaboration/consortia">{t('collaboration.consortia')}</Link>
      <Link className={button} to="/network">{t('collaboration.connections')}</Link>
    </nav></header>
}
export function Feedback({ issue, error, success }: { issue?: CopyKey | null; error?: unknown; success?: CopyKey | null }) {
  const { t } = useTranslation()
  let key: CopyKey = 'error'
  if (error instanceof ApiError) {
    const code = error.problem.type?.split('/').at(-1)
    if (error.response.status === 412) key = 'conflict'
    else if ([403, 404].includes(error.response.status)) key = 'unavailable'
    else if (error.response.status === 429) key = 'limit'
    else if (code === 'collaboration-invalid-transition') key = 'invalidTransition'
    else if (code === 'collaboration-already-exists') key = 'alreadyExists'
    else if (error.response.status === 422) key = 'invalidData'
  }
  if (issue || error) return <p role="alert" className="rounded-lg border border-destructive/30 p-3 text-destructive">
    {issue ? t(`collaboration.${issue}`) : requestValidationMessage(error) ?? t(`collaboration.${key}`)}</p>
  return success ? <p role="status">{t(`collaboration.${success}`)}</p> : null
}
export function Paging({ page, total, setPage, disabled = false, pageSize = 20 }: { page: number; total: number; setPage: (page: number) => void; disabled?: boolean; pageSize?: number }) {
  const { t } = useTranslation()
  return <div className="flex flex-wrap items-center gap-3">
    <button type="button" className={button} disabled={disabled || page <= 1} onClick={() => setPage(page - 1)}>{t('collaboration.previous')}</button>
    <span>{t('collaboration.page', { page, total })}</span>
    <button type="button" className={button} disabled={disabled || page * pageSize >= total || page >= 10000} onClick={() => setPage(page + 1)}>{t('collaboration.next')}</button>
  </div>
}
export function LoadState({ pending, error, retry }: { pending: boolean; error: unknown; retry: () => unknown }) {
  const { t } = useTranslation()
  return pending ? <p role="status">{t('collaboration.loading')}</p> : error ? <div><Feedback error={error} /><button className={button} onClick={() => { void retry() }}>{t('collaboration.retry')}</button></div> : null
}
export const consortiumStatuses = ['forming', 'active', 'closed'] as const
export const participantStatuses = ['invited', 'accepted', 'rejected', 'cancelled', 'left', 'removed'] as const
