import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  BellRing, CalendarDays, CircleAlert, FolderKanban, LoaderCircle,
  RefreshCw, Send, type LucideIcon,
} from 'lucide-react'
import { Link, useSearchParams } from 'react-router-dom'
import { useTranslation } from 'react-i18next'

import { formatWorkspaceDate, workspaceLocale } from '@/i18n/workspace-messages'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { alertsApi } from '@/features/alerts/alerts-api'
import { applicationApi, type ApplicationStatus } from '@/features/applications/application-api'
import { calendarApi, type CalendarEvent } from '@/features/calendar/calendar-api'
import { organizationApi } from '@/features/organizations/organization-api'
import { projectApi } from '@/features/projects/project-api'

const queryRoot = ['user-dashboard'] as const
const selectClass = 'h-10 w-full min-w-0 rounded-lg border bg-background px-3 text-sm sm:min-w-60'
const applicationStatusKeys = {
  0: 'dashboard.statusInterested',
  1: 'dashboard.statusPreparing',
  2: 'dashboard.statusSubmitted',
  3: 'dashboard.statusAwarded',
  4: 'dashboard.statusNotAwarded',
  5: 'dashboard.statusDiscarded',
} as const satisfies Record<ApplicationStatus, string>

function dateOnly(value: Date) {
  const year = value.getFullYear()
  const month = String(value.getMonth() + 1).padStart(2, '0')
  const day = String(value.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}
function formatDate(value: string) {
  return formatWorkspaceDate(value.slice(0, 10))
}
function eventPath(event: CalendarEvent) {
  if (event.fundingApplicationPublicId) return `/applications?applicationId=${encodeURIComponent(event.fundingApplicationPublicId)}`
  if (event.projectPublicId) return `/projects/${encodeURIComponent(event.projectPublicId)}`
  if (event.fundingOpportunityPublicId) return '/opportunities'
  return '/calendar'
}

function Metric({ title, value, detail, icon: Icon, to, pending, failed }: {
  title: string
  value: number | undefined
  detail: string
  icon: LucideIcon
  to: string
  pending: boolean
  failed: boolean
}) {
  const { t } = useTranslation()
  return <Link className="group rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" to={to}><Card className="h-full transition-colors group-hover:border-primary/50 group-hover:bg-accent/30"><CardContent className="flex items-start justify-between gap-4 p-5"><div><p className="text-sm font-medium text-muted-foreground">{title}</p><p className="mt-2 text-3xl font-bold">{pending ? '—' : failed ? '!' : value?.toLocaleString(workspaceLocale()) ?? '0'}</p><p className="mt-1 text-xs text-muted-foreground">{failed ? t('dashboard.metricFailed') : detail}</p></div><span className="rounded-xl bg-accent p-2.5 text-primary"><Icon className="size-5" /></span></CardContent></Card></Link>
}

export function DashboardWorkspacePage() {
  const { t } = useTranslation()
  const [searchParams, setSearchParams] = useSearchParams()
  const queryClient = useQueryClient()
  const organizations = useQuery({
    queryKey: ['organizations'], queryFn: ({ signal }) => organizationApi.list(signal),
  })
  const requestedId = searchParams.get('organizationId')
  const organization = organizations.data?.find(item => item.publicId === requestedId)
    ?? organizations.data?.[0]
  const now = new Date()
  const from = dateOnly(now)
  const horizon = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 60, 12)
  const to = dateOnly(horizon)
  const projects = useQuery({
    queryKey: [...queryRoot, organization?.publicId, 'projects'],
    queryFn: ({ signal }) => projectApi.list(organization!.publicId, signal),
    enabled: Boolean(organization),
  })
  const applications = useQuery({
    queryKey: [...queryRoot, organization?.publicId, 'applications'],
    queryFn: ({ signal }) => applicationApi.list(organization!.publicId, { page: 1, pageSize: 5 }, signal),
    enabled: Boolean(organization),
  })
  const calendar = useQuery({
    queryKey: [...queryRoot, organization?.publicId, 'calendar', from, to],
    queryFn: ({ signal }) => calendarApi.get(organization!.publicId, from, to, signal),
    enabled: Boolean(organization),
  })
  const alerts = useQuery({
    queryKey: [...queryRoot, organization?.publicId, 'alerts'],
    queryFn: ({ signal }) => alertsApi.list(organization!.publicId, 1, 1, signal),
    enabled: Boolean(organization),
  })
  const queries = [projects, applications, calendar, alerts]
  const refreshing = queries.some(query => query.isFetching)
  const unavailable = queries.filter(query => query.isError).length

  function selectOrganization(publicId: string) {
    const next = new URLSearchParams(searchParams)
    next.set('organizationId', publicId)
    setSearchParams(next, { replace: true })
  }
  function refresh() {
    void queryClient.invalidateQueries({ queryKey: queryRoot })
  }

  if (organizations.isPending) return <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" />{t('dashboard.loading')}</p>
  if (organizations.isError) return <Card className="border-destructive/40"><CardContent className="space-y-3 p-8" role="alert"><CircleAlert className="size-8 text-destructive" /><h1 className="text-xl font-bold">{t('dashboard.organizationsFailed')}</h1><Button onClick={() => void organizations.refetch()} variant="outline">{t('dashboard.retry')}</Button></CardContent></Card>
  if (!organization) return <Card><CardContent className="space-y-4 p-10 text-center"><FolderKanban className="mx-auto size-10 text-primary" /><h1 className="text-2xl font-bold">{t('dashboard.emptyTitle')}</h1><p className="text-muted-foreground">{t('dashboard.emptyHelp')}</p><Button asChild><Link to="/onboarding">{t('dashboard.createOrganization')}</Link></Button></CardContent></Card>

  const contextQuery = `organizationId=${encodeURIComponent(organization.publicId)}`
  return <div className="space-y-8">
    <header className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{t('dashboard.eyebrow')}</p><h1 className="mt-1 text-3xl font-bold">{t('dashboard.title')}</h1><p className="mt-2 text-muted-foreground">{t('dashboard.description', { name: organization.name })}</p></div><div className="flex w-full min-w-0 flex-wrap items-end gap-3 sm:w-auto">{organizations.data!.length > 1 && <label className="grid w-full min-w-0 gap-1 text-xs font-semibold sm:w-auto">{t('dashboard.organization')}<select aria-label={t('dashboard.organizationSelector')} className={selectClass} onChange={event => selectOrganization(event.target.value)} value={organization.publicId}>{organizations.data!.map(item => <option key={item.publicId} value={item.publicId}>{item.name}</option>)}</select></label>}<Button disabled={refreshing} onClick={refresh} variant="outline">{refreshing ? <LoaderCircle className="size-4 animate-spin" /> : <RefreshCw className="size-4" />}{t('dashboard.refresh')}</Button></div></header>

    {unavailable > 0 && <p className="flex items-center gap-2 rounded-lg bg-destructive/10 p-3 text-sm text-foreground" role="status"><CircleAlert className="size-4" />{t('dashboard.unavailable', { count: unavailable })}</p>}

    <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4" aria-label={t('dashboard.metrics')}>
      <Metric detail={t('dashboard.projectsDetail')} failed={projects.isError} icon={FolderKanban} pending={projects.isPending} title={t('dashboard.projects')} to={`/projects?${contextQuery}`} value={projects.data?.length} />
      <Metric detail={t('dashboard.applicationsDetail')} failed={applications.isError} icon={Send} pending={applications.isPending} title={t('dashboard.applications')} to={`/applications?${contextQuery}`} value={applications.data?.totalCount} />
      <Metric detail={t('dashboard.milestonesDetail')} failed={calendar.isError} icon={CalendarDays} pending={calendar.isPending} title={t('dashboard.milestones')} to={`/calendar?${contextQuery}`} value={calendar.data?.items.length} />
      <Metric detail={t('dashboard.alertsDetail')} failed={alerts.isError} icon={BellRing} pending={alerts.isPending} title={t('dashboard.alerts')} to={`/alerts?${contextQuery}`} value={alerts.data?.totalCount} />
    </section>

    <section className="grid gap-6 xl:grid-cols-2">
      <Card><CardHeader><CardTitle>{t('dashboard.milestones')}</CardTitle><p className="text-sm text-muted-foreground">{t('dashboard.calendarHelp')}</p></CardHeader><CardContent className="space-y-3">{calendar.isPending && <p className="text-sm text-muted-foreground">{t('dashboard.calendarLoading')}</p>}{calendar.isError && <p className="text-sm text-destructive">{t('dashboard.calendarFailed')}</p>}{calendar.data?.items.slice().sort((left, right) => left.eventDate.localeCompare(right.eventDate)).slice(0, 5).map(event => <Link className="flex items-center justify-between gap-4 rounded-lg border p-4 hover:bg-accent/40" key={event.eventKey} to={eventPath(event)}><div className="min-w-0 break-words"><p className="font-semibold">{event.title}</p><p className="text-sm text-muted-foreground">{formatDate(event.eventDate)}</p></div><CalendarDays className="size-4 shrink-0 text-primary" /></Link>)}{calendar.data?.items.length === 0 && <p className="text-sm text-muted-foreground">{t('dashboard.calendarEmpty')}</p>}<Button asChild size="sm" variant="outline"><Link to={`/calendar?${contextQuery}`}>{t('dashboard.calendarLink')}</Link></Button></CardContent></Card>

      <Card><CardHeader><CardTitle>{t('dashboard.recentApplications')}</CardTitle><p className="text-sm text-muted-foreground">{t('dashboard.applicationsHelp')}</p></CardHeader><CardContent className="space-y-3">{applications.isPending && <p className="text-sm text-muted-foreground">{t('dashboard.applicationsLoading')}</p>}{applications.isError && <p className="text-sm text-destructive">{t('dashboard.applicationsFailed')}</p>}{applications.data?.items.slice(0, 5).map(item => <Link className="block break-words rounded-lg border p-4 hover:bg-accent/40" key={item.publicId} to={`/applications?applicationId=${encodeURIComponent(item.publicId)}&${contextQuery}`}><p className="font-semibold">{item.fundingOpportunity.title}</p><p className="mt-1 text-sm text-muted-foreground">{item.project.title} · {t(applicationStatusKeys[item.status] ?? 'dashboard.statusUnknown')}</p></Link>)}{applications.data?.items.length === 0 && <p className="text-sm text-muted-foreground">{t('dashboard.applicationsEmpty')}</p>}<Button asChild size="sm" variant="outline"><Link to={`/applications?${contextQuery}`}>{t('dashboard.applicationsLink')}</Link></Button></CardContent></Card>
    </section>
  </div>
}
