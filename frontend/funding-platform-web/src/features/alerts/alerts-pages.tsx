import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Bell, BellOff, ExternalLink, LoaderCircle, Save, Trash2 } from 'lucide-react'
import { type FormEvent, useMemo, useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { workspaceLocale } from '@/i18n/workspace-messages'
import { trackingErrorMessage, notificationStatusLabel, type TrackingFeedback } from '@/i18n/tracking-messages'

import { Link, useLocation, useNavigate, useSearchParams } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { organizationApi } from '@/features/organizations/organization-api'
import { serializeFundingSearch, type FundingSort } from '@/features/funding/organization-funding-api'
import {
  alertsApi,
  toFundingSearch,
  type SavedSearchWrite,
} from '@/features/alerts/alerts-api'

function parseIds(value: string | null) {
  if (!value) return []
  return [...new Set(value.split(',').map(Number).filter((id) => Number.isSafeInteger(id) && id > 0))]
}

function parseGuids(value: string | null) {
  return value?.split(',').map((item) => item.trim()).filter(Boolean) ?? []
}

function parseAmount(value: string | null) {
  if (!value) return null
  const parsed = Number(value)
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null
}

function draftFromQuery(parameters: URLSearchParams, name: string): SavedSearchWrite {
  const query = parameters.get('q')?.trim() || null
  const sortText = parameters.get('sort')
  const allowed: FundingSort[] = ['relevance', 'closing-soon', 'newest', 'amount-asc', 'amount-desc']
  const sort = allowed.includes(sortText as FundingSort)
    ? sortText as FundingSort
    : query ? 'relevance' : 'closing-soon'
  return {
    name,
    query,
    sponsor: parameters.get('sponsor')?.trim() || null,
    minimumAmount: parseAmount(parameters.get('minAmount')),
    maximumAmount: parseAmount(parameters.get('maxAmount')),
    currency: parameters.get('currency')?.trim().toUpperCase() || null,
    closingFrom: parameters.get('closingFrom'),
    closingTo: parameters.get('closingTo'),
    onlyOpen: parameters.get('onlyOpen') !== 'false',
    sort,
    countryIds: parseIds(parameters.get('countryIds')),
    regionIds: parseIds(parameters.get('regionIds')),
    categoryIds: parseIds(parameters.get('categoryIds')),
    tagIds: parseIds(parameters.get('tagIds')),
    beneficiaryTypeIds: parseIds(parameters.get('beneficiaryTypeIds')),
    projectTypeIds: parseIds(parameters.get('projectTypeIds')),
    fundingTypeIds: parseIds(parameters.get('fundingTypeIds')),
    organizationTypeIds: parseIds(parameters.get('organizationTypeIds')),
    funderIds: parseGuids(parameters.get('funderIds')),
  }
}

function message(error: unknown, operation: 'read' | 'write' = 'write') {
  return trackingErrorMessage(error, 'alerts', operation)
}

function formatDate(value: string | null) {
  if (!value) return '—'
  if (Number.isNaN(new Date(value).getTime())) return '—'
  return new Intl.DateTimeFormat(workspaceLocale(), { dateStyle: 'medium', timeStyle: 'short' })
    .format(new Date(value))
}

export function AlertsWorkspacePage() {
  const { t } = useTranslation()
  const [searchParams, setSearchParams] = useSearchParams()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const organizations = useQuery({
    queryKey: ['organizations'],
    queryFn: ({ signal }) => organizationApi.list(signal),
  })
  const organization = organizations.data?.[0]
  const searches = useQuery({
    queryKey: ['saved-searches', organization?.publicId],
    queryFn: ({ signal }) => alertsApi.list(organization!.publicId, 1, 50, signal),
    enabled: Boolean(organization),
  })
  const notifications = useQuery({
    queryKey: ['notification-logs', organization?.publicId],
    queryFn: ({ signal }) => alertsApi.notifications(organization!.publicId, 1, 20, signal),
    enabled: Boolean(organization),
  })
  const [name, setName] = useState('')
  const [enableAlert, setEnableAlert] = useState(true)
  const [hour, setHour] = useState(8)
  const [feedback, setFeedback] = useState<TrackingFeedback | null>(null)
  const idempotencyKey = useRef<string | null>(null)
  const creating = searchParams.get('new') === 'true'
  const draft = useMemo(() => draftFromQuery(searchParams, name), [searchParams, name])

  const create = useMutation({
    mutationFn: async () => {
      const key = idempotencyKey.current ??= `saved-search-${crypto.randomUUID()}`
      const saved = await alertsApi.create(organization!.publicId, draft, key)
      if (enableAlert) {
        const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone
        try {
          await alertsApi.putAlert(organization!.publicId, saved.id, hour, timeZone)
        } catch (error) {
          return {
            saved, enabled: enableAlert,
            alertWarning: error instanceof ApiError && error.response.status === 503 && error.problem.type === 'https://fundingplatform.local/problems/alerts-disabled'
              ? 'alerts.savedEmailDisabled' as const
              : 'alerts.savedEmailUncertain' as const,
          }
        }
      }
      return { saved, alertWarning: null, enabled: enableAlert }
    },
    onSuccess: async ({ alertWarning, enabled }) => {
      idempotencyKey.current = null
      await queryClient.invalidateQueries({ queryKey: ['saved-searches', organization?.publicId] })
      setFeedback({ key: alertWarning ?? (enabled ? 'alerts.savedWithAlert' : 'alerts.saved') })
      setSearchParams({}, { replace: true })
      setName('')
    },
    onError: (error) => {
      if (error instanceof ApiError) idempotencyKey.current = null
      setFeedback({ error })
    },
  })
  const remove = useMutation({
    mutationFn: ({ id, eTag }: { id: string; eTag: string }) =>
      alertsApi.remove(organization!.publicId, id, eTag),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['saved-searches', organization?.publicId] })
      setFeedback({ key: 'alerts.removed' })
    },
    onError: (error) => setFeedback({ error }),
  })
  const toggle = useMutation({
    mutationFn: async ({ id, active }: { id: string; active: boolean }) => {
      if (active) return alertsApi.deleteAlert(organization!.publicId, id)
      return alertsApi.putAlert(
        organization!.publicId,
        id,
        8,
        Intl.DateTimeFormat().resolvedOptions().timeZone,
      )
    },
    onSuccess: async (_, variables) => {
      await queryClient.invalidateQueries({ queryKey: ['saved-searches', organization?.publicId] })
      setFeedback({ key: variables.active ? 'alerts.disabled' : 'alerts.enabled' })
    },
    onError: (error) => setFeedback({ error }),
  })
  const open = useMutation({
    mutationFn: (id: string) => alertsApi.get(organization!.publicId, id),
    onSuccess: (saved) => navigate(`/opportunities?${serializeFundingSearch(toFundingSearch(saved.filters))}`),
    onError: (error) => setFeedback({ error }),
  })

  function submit(event: FormEvent) {
    event.preventDefault()
    setFeedback(null)
    create.mutate()
  }

  if (organizations.isPending) return <p role="status">{t('tracking.organizationLoading')}</p>
  if (organizations.isError) return <Card><CardContent className="space-y-3 p-8" role="alert"><p>{t('tracking.organizationFailed')}</p><Button onClick={() => void organizations.refetch()} variant="outline">{t('tracking.retry')}</Button></CardContent></Card>
  if (!organization) return <Card><CardContent className="p-8 text-center"><h1 className="text-2xl font-bold">{t('tracking.organizationRequired')}</h1><Button asChild className="mt-4"><Link to="/onboarding">{t('tracking.start')}</Link></Button></CardContent></Card>

  return (
    <div className="space-y-6">
      <header><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{t('alerts.eyebrow')}</p><h1 className="mt-1 text-3xl font-bold">{t('alerts.title')}</h1><p className="mt-2 text-muted-foreground">{t('alerts.help')}</p></header>
      {feedback && <p className="rounded-lg bg-accent p-3 text-sm" role="status">{'key' in feedback ? t(feedback.key) : message(feedback.error)}</p>}
      {creating && <Card><CardHeader><CardTitle>{t('alerts.saveCurrent')}</CardTitle></CardHeader><CardContent><form className="grid gap-4" onSubmit={submit}><label className="grid gap-1 text-sm font-semibold">{t('alerts.name')}<input autoFocus className="h-10 rounded-lg border bg-background px-3" maxLength={150} onChange={(event) => setName(event.target.value)} required value={name} /></label><label className="flex items-center gap-2 text-sm"><input checked={enableAlert} onChange={(event) => setEnableAlert(event.target.checked)} type="checkbox" />{t('alerts.enableDaily')}</label>{enableAlert && <label className="grid max-w-xs gap-1 text-sm font-semibold">{t('alerts.hour')}<select className="h-10 rounded-lg border bg-background px-3" onChange={(event) => setHour(Number(event.target.value))} value={hour}>{Array.from({ length: 24 }, (_, value) => <option key={value} value={value}>{String(value).padStart(2, '0')}:00</option>)}</select></label>}<div className="flex gap-2"><Button disabled={create.isPending || !name.trim()} type="submit">{create.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Save className="size-4" />}{t('tracking.save')}</Button><Button onClick={() => setSearchParams({}, { replace: true })} type="button" variant="outline">{t('tracking.cancel')}</Button></div></form></CardContent></Card>}
      <section className="space-y-3"><div className="flex flex-wrap items-center justify-between gap-3"><h2 className="text-xl font-bold">{t('alerts.savedSearches')}</h2><Button asChild variant="outline"><Link to="/opportunities">{t('alerts.fromCatalog')}</Link></Button></div>{searches.isPending && <p role="status">{t('alerts.loading')}</p>}{searches.isError && <p className="text-destructive" role="alert">{message(searches.error, 'read')}</p>}{searches.data?.items.length === 0 && <Card><CardContent className="p-8 text-center"><Bell className="mx-auto size-8 text-muted-foreground" /><p className="mt-3 font-semibold">{t('alerts.empty')}</p><p className="mt-1 text-sm text-muted-foreground">{t('alerts.emptyHelp')}</p></CardContent></Card>}<div className="grid gap-3 lg:grid-cols-2">{searches.data?.items.map((item) => <Card key={item.id}><CardContent className="space-y-3 p-5"><div className="flex items-start justify-between gap-3"><div><h3 className="font-bold">{item.name}</h3><p className="text-sm text-muted-foreground">{item.query ? t('alerts.query', { query: item.query }) : t('alerts.allFiltered')}</p></div><span className="rounded-full bg-muted px-2 py-1 text-xs">{item.hasActiveAlert ? t('alerts.active') : t('alerts.inactive')}</span></div><div className="flex flex-wrap gap-2"><Button disabled={open.isPending} onClick={() => open.mutate(item.id)} size="sm"><ExternalLink className="size-4" />{t('tracking.open')}</Button><Button disabled={toggle.isPending} onClick={() => toggle.mutate({ id: item.id, active: item.hasActiveAlert })} size="sm" variant="outline">{item.hasActiveAlert ? <BellOff className="size-4" /> : <Bell className="size-4" />}{item.hasActiveAlert ? t('alerts.disable') : t('alerts.enable')}</Button><Button aria-label={t('alerts.deleteLabel', { name: item.name })} disabled={remove.isPending} onClick={() => remove.mutate({ id: item.id, eTag: item.eTag })} size="sm" variant="ghost"><Trash2 className="size-4" />{t('alerts.delete')}</Button></div></CardContent></Card>)}</div></section>
      <section className="space-y-3"><h2 className="text-xl font-bold">{t('alerts.history')}</h2>{notifications.isPending && <p role="status">{t('alerts.loadingHistory')}</p>}{notifications.isError && <p className="text-destructive" role="alert">{message(notifications.error, 'read')}</p>}{notifications.data?.items.length === 0 && <p className="text-sm text-muted-foreground">{t('alerts.emptyHistory')}</p>}<div className="space-y-2">{notifications.data?.items.map((item) => <Card key={item.id}><CardContent className="flex flex-wrap items-center justify-between gap-3 p-4"><div><p className="font-semibold">{item.savedSearchName ?? t('alerts.deletedSearch')}</p><p className="text-sm text-muted-foreground">{t('alerts.notification', { count: item.itemCount, date: formatDate(item.scheduledForUtc) })}{item.wasTruncated ? t('alerts.truncated') : ''}</p></div><span className="rounded-full bg-muted px-2 py-1 text-xs">{notificationStatusLabel(item.status)}</span></CardContent></Card>)}</div></section>
    </div>
  )
}

export function AlertUnsubscribePage() {
  const { t } = useTranslation()
  const location = useLocation()
  const token = new URLSearchParams(location.hash.slice(1)).get('token') ?? ''
  const unsubscribe = useMutation({
    mutationFn: () => alertsApi.unsubscribe(token),
  })
  return <div className="mx-auto max-w-lg py-16"><Card><CardContent className="space-y-4 p-8 text-center"><BellOff className="mx-auto size-10 text-primary" /><h1 className="text-2xl font-bold">{t('alerts.unsubscribeTitle')}</h1>{!token && <p role="alert">{t('alerts.incomplete')}</p>}{token && !unsubscribe.isSuccess && <p>{t('alerts.confirmHelp')}</p>}{token && unsubscribe.isSuccess && <p>{t('alerts.unsubscribed')}</p>}{token && unsubscribe.isError && <p role="alert">{t('alerts.unsubscribeFailed')}</p>}{token && !unsubscribe.isSuccess && <Button disabled={unsubscribe.isPending} onClick={() => unsubscribe.mutate()}>{unsubscribe.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <BellOff className="size-4" />}{unsubscribe.isError ? t('tracking.retry') : t('alerts.confirm')}</Button>}<Button asChild variant="outline"><Link to="/">{t('actions.backToHome')}</Link></Button></CardContent></Card></div>
}
