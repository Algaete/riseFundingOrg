import { formatDateValue } from '@/i18n/formats'
import i18n from '@/i18n'
import { useTranslation } from 'react-i18next'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { CircleAlert, FileWarning, LoaderCircle, RefreshCw, Search } from 'lucide-react'
import { type FormEvent, useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'

import { adminErrorMessage } from '@/i18n/editorial-messages'
import { operationStatus } from '@/i18n/operations-messages'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import {
  adminErrorsApi,
  type AdminOperationalError,
  type OperationalErrorCategory,
} from '@/features/admin-errors/admin-errors-api'

const categoryLabels: Record<OperationalErrorCategory, string> = {
  import: 'adminIncidents.import', extraction: 'adminIncidents.extraction', semantic: 'adminIncidents.semantic',
  explanation: 'adminIncidents.explanation', payment: 'adminIncidents.payment',
}
const categories = Object.keys(categoryLabels) as OperationalErrorCategory[]
const selectClass = 'h-10 rounded-lg border bg-background px-3 text-sm'

function positiveInteger(value: string | null, fallback: number) {
  const parsed = Number(value)
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback
}
function formatDate(value: string) {
  return formatDateValue(value, { dateStyle: 'medium', timeStyle: 'short' })
}
function message(error: unknown) {
  return adminErrorMessage(error)
}
function relatedPath(item: AdminOperationalError) {
  if (!item.relatedResourcePublicId) return null
  if (item.category === 'import') return `/admin/imports/${item.relatedResourcePublicId}`
  if (item.category === 'extraction') return `/admin/source-documents/${item.relatedResourcePublicId}`
  return null
}

export function AdminErrorsWorkspacePage() {
  useTranslation()
  const [searchParams, setSearchParams] = useSearchParams()
  const query = searchParams.get('q')?.trim() ?? ''
  const categoryText = searchParams.get('category')
  const category = categories.includes(categoryText as OperationalErrorCategory)
    ? categoryText as OperationalErrorCategory : undefined
  const retryableText = searchParams.get('retryable')
  const retryable = retryableText === 'true' ? true : retryableText === 'false' ? false : undefined
  const page = positiveInteger(searchParams.get('page'), 1)
  const pageSize = 25
  const [draft, setDraft] = useState(query)
  useEffect(() => setDraft(query), [query])

  const errors = useQuery({
    queryKey: ['admin-operational-errors', query, category, retryable, page, pageSize],
    queryFn: ({ signal }) => adminErrorsApi.list({
      q: query || undefined, category, retryable, page, pageSize,
    }, signal),
    placeholderData: keepPreviousData,
  })
  function replace(name: string, value?: string, resetPage = true) {
    const next = new URLSearchParams(searchParams)
    if (!value) next.delete(name)
    else next.set(name, value)
    if (resetPage) next.delete('page')
    setSearchParams(next, { replace: true })
  }
  function submit(event: FormEvent) {
    event.preventDefault()
    replace('q', draft.trim())
  }
  const lastPage = errors.data ? Math.max(1, Math.ceil(errors.data.totalCount / errors.data.pageSize)) : 1

  return <div className="min-w-0 space-y-6">
    <header className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{i18n.t('editorial.administration')}</p><h1 className="mt-1 text-3xl font-bold">{i18n.t('adminIncidents.title')}</h1><p className="mt-2 max-w-3xl text-muted-foreground">{i18n.t('adminIncidents.intro')}</p></div>{errors.data && <p className="rounded-full bg-muted px-3 py-1 text-sm">{i18n.t('adminIncidents.count', { count: errors.data.totalCount })}</p>}</header>

    <Card><CardContent className="grid gap-3 p-4 lg:grid-cols-[minmax(16rem,1fr)_auto_auto]">
      <form className="flex flex-wrap gap-2" onSubmit={submit}><Input aria-label={i18n.t('adminIncidents.search')} maxLength={200} onChange={event => setDraft(event.target.value)} placeholder={i18n.t('adminIncidents.placeholder')} value={draft} /><Button type="submit" variant="outline"><Search className="size-4" />{i18n.t('editorial.search')}</Button></form>
      <label className="grid gap-1 text-xs font-semibold">{i18n.t('adminIncidents.origin')}<select className={selectClass} onChange={event => replace('category', event.target.value)} value={category ?? ''}><option value="">{i18n.t('operations.all')}</option>{categories.map(value => <option key={value} value={value}>{operationStatus(categoryLabels, value)}</option>)}</select></label>
      <label className="grid gap-1 text-xs font-semibold">{i18n.t('operations.retryTrigger')}<select className={selectClass} onChange={event => replace('retryable', event.target.value)} value={retryableText ?? ''}><option value="">{i18n.t('operations.all')}</option><option value="true">{i18n.t('adminIncidents.retryablePlural')}</option><option value="false">{i18n.t('adminIncidents.permanentPlural')}</option></select></label>
    </CardContent></Card>

    {errors.isPending && <Card><CardContent className="flex items-center gap-2 p-8" role="status"><LoaderCircle className="size-5 animate-spin" />{i18n.t('adminIncidents.loading')}</CardContent></Card>}
    {errors.isError && <Card className="border-destructive/40"><CardContent className="space-y-3 p-8" role="alert"><CircleAlert className="size-8 text-foreground" /><h2 className="text-xl font-bold">{i18n.t('adminIncidents.failed')}</h2><p className="text-sm text-muted-foreground">{message(errors.error)}</p><Button onClick={() => void errors.refetch()} variant="outline">{i18n.t('editorial.retry')}</Button></CardContent></Card>}
    {errors.data?.items.length === 0 && <Card><CardContent className="space-y-3 p-10 text-center"><FileWarning className="mx-auto size-9 text-muted-foreground" /><h2 className="text-xl font-bold">{i18n.t('adminIncidents.empty')}</h2><p className="text-sm text-muted-foreground">{i18n.t('adminIncidents.emptyHelp')}</p><Button onClick={() => { setDraft(''); setSearchParams({}, { replace: true }) }} variant="outline">{i18n.t('operations.clear')}</Button></CardContent></Card>}

    {errors.data && errors.data.items.length > 0 && <div className="space-y-3">{errors.data.items.map(item => {
      const path = relatedPath(item)
      return <Card className={item.severity >= 2 ? 'border-destructive/35' : ''} key={item.id}><CardContent className="flex flex-col gap-4 p-5 lg:flex-row lg:items-start lg:justify-between"><div className="min-w-0 space-y-2"><div className="flex flex-wrap items-center gap-2"><span className="rounded-full bg-muted px-2.5 py-1 text-xs font-semibold">{operationStatus(categoryLabels, item.category)}</span><span className={item.severity >= 2 ? 'text-sm font-semibold text-foreground' : 'text-sm font-semibold text-amber-700 dark:text-amber-300'}>{item.severity >= 2 ? i18n.t('adminIncidents.permanent') : i18n.t('adminIncidents.warning')}</span>{item.isRetryable && <span className="inline-flex items-center gap-1 text-xs text-muted-foreground"><RefreshCw className="size-3" />{i18n.t('operations.retryable')}</span>}</div><p className="font-mono text-sm font-semibold">{item.code}</p><p className="text-sm text-muted-foreground">{item.message}</p><p className="text-xs text-muted-foreground">{item.sourceName ?? i18n.t('adminIncidents.noOrigin')} · {formatDate(item.occurredAtUtc)}</p></div>{path && <Button asChild className="shrink-0" size="sm" variant="outline"><Link to={path}>{i18n.t('adminIncidents.context')}</Link></Button>}</CardContent></Card>
    })}</div>}

    {errors.data && lastPage > 1 && <nav aria-label={i18n.t('adminIncidents.pagination')} className="flex flex-wrap items-center justify-end gap-3 rounded-xl border bg-card p-3"><Button disabled={page <= 1 || errors.isFetching} onClick={() => replace('page', String(page - 1), false)} variant="outline">{i18n.t('editorial.previous')}</Button><p className="text-sm text-muted-foreground">{i18n.t('operations.page', { page, total: lastPage })}</p><Button disabled={page >= lastPage || errors.isFetching} onClick={() => replace('page', String(page + 1), false)} variant="outline">{i18n.t('editorial.next')}</Button></nav>}
  </div>
}
