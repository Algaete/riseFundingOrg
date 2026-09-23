import { Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { Button } from '@/components/ui/button'
import { ApiError } from '@/api/http-client'
import type { ReactNode } from 'react'
import { requestValidationMessage } from '@/i18n/validation-issues'

export const control = 'w-full rounded-lg border bg-background px-3 py-2'
export const panel = 'space-y-4 rounded-2xl border bg-card p-5'
export const container = 'mx-auto max-w-6xl space-y-6 px-4 py-10'
export function Field({ label, children }: { label: string; children: ReactNode }) { return <label className="grid gap-2 text-sm font-semibold">{label}{children}</label> }
export function Failure({ error }: { error: unknown }) {
  const { t } = useTranslation()
  if (!error) return null
  const code = error instanceof ApiError ? error.response.status : 0
  const message = requestValidationMessage(error)
  return <div role="alert" className="rounded-lg border border-destructive p-3"><p>{t(code === 409 ? 'engagement.conflict' : code === 429 ? 'engagement.limit' : code === 422 ? 'engagement.notReady' : 'engagement.failed')}</p>
    {message && <p>{message}</p>}</div>
}
export function Paging({ page, total, onPage, disabled = false }: { page: number; total: number; onPage: (p: number) => void; disabled?: boolean }) {
  const { t } = useTranslation()
  return <div className="flex items-center gap-4"><Button variant="outline" disabled={disabled || page <= 1} onClick={() => onPage(page - 1)}>{t('engagement.previous')}</Button><span>{page}</span><Button variant="outline" disabled={disabled || page * 20 >= total} onClick={() => onPage(page + 1)}>{t('engagement.next')}</Button></div>
}
export function DonationComingSoon({ project = false }: { project?: boolean }) {
  const { t } = useTranslation()
  return <div className="space-y-2"><Button disabled type="button" variant="outline">{t(project ? 'navigation.donateProject' : 'navigation.donate')} — {t('navigation.comingSoon')}</Button><p className="text-xs text-muted-foreground">{t('navigation.donationUnavailable')}</p></div>
}
export function ContactLink() { const { t } = useTranslation(); return <Button asChild variant="outline"><Link to="/contact">{t('navigation.contact')}</Link></Button> }
