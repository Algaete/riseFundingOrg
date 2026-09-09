import { formatDateValue } from '@/i18n/formats'
import { useQuery } from '@tanstack/react-query'
import {
  ArrowRight,
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  CircleAlert,
  Clock3,
  LoaderCircle,
} from 'lucide-react'
import { useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { trackingErrorMessage, applicationStatusLabel } from '@/i18n/tracking-messages'

import { Link, useSearchParams } from 'react-router-dom'

import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { calendarApi, type CalendarEvent } from '@/features/calendar/calendar-api'
import { organizationApi } from '@/features/organizations/organization-api'


function pad(value: number) {
  return String(value).padStart(2, '0')
}

function toDateOnly(date: Date) {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
}

function parseMonth(value: string | null) {
  const match = /^(\d{4})-(\d{2})$/.exec(value ?? '')
  if (match) {
    const month = Number(match[2])
    if (month >= 1 && month <= 12) return new Date(Number(match[1]), month - 1, 1, 12)
  }
  const now = new Date()
  return new Date(now.getFullYear(), now.getMonth(), 1, 12)
}

function monthKey(date: Date) {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}`
}

function moveMonth(date: Date, offset: number) {
  return new Date(date.getFullYear(), date.getMonth() + offset, 1, 12)
}

function formatDateOnly(value: string) {
  return formatDateValue(value, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })
}

function formatUtcTime(value: string | null) {
  if (!value) return null
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return null
  return `${formatDateValue(date, {
    hour: '2-digit', minute: '2-digit', timeZone: 'UTC', hourCycle: 'h23',
  })} UTC`
}

function errorMessage(error: unknown) {
  return trackingErrorMessage(error, 'calendar', 'read')
}

function eventHref(event: CalendarEvent) {
  if (event.fundingApplicationPublicId) return `/applications?applicationId=${encodeURIComponent(event.fundingApplicationPublicId)}`
  if (event.projectPublicId) return `/projects/${encodeURIComponent(event.projectPublicId)}`
  if (event.fundingOpportunityPublicId) return `/opportunities/${encodeURIComponent(event.fundingOpportunityPublicId)}`
  return null
}

function EventRow({ event }: { event: CalendarEvent }) {
  const { t } = useTranslation()
  const href = eventHref(event)
  const time = formatUtcTime(event.eventAtUtc)
  return <li className="flex flex-col gap-3 rounded-lg border bg-background p-4 sm:flex-row sm:items-center sm:justify-between">
    <div>
      <div className="flex flex-wrap items-center gap-2"><span className="rounded-full bg-accent px-2.5 py-1 text-xs font-semibold text-accent-foreground">{t(`calendar.eventTypes.${event.eventType}`, { defaultValue: t('tracking.unknown') })}</span>{event.status !== null && <span className="text-xs text-muted-foreground">{applicationStatusLabel(event.status)}</span>}</div>
      <h3 className="mt-2 font-bold">{event.title}</h3>
      <p className="mt-1 flex items-center gap-1.5 text-xs text-muted-foreground"><Clock3 className="size-3.5" />{time ?? t('calendar.allDay')}{event.datePrecision === 0 && t('calendar.approximate')}</p>
    </div>
    {href && <Button asChild size="sm" variant="ghost"><Link to={href}>{t('tracking.open')} <ArrowRight className="size-4" /></Link></Button>}
  </li>
}

function OrganizationRequired() {
  const { t } = useTranslation()
  return <Card><CardContent className="space-y-4 p-8 text-center"><h1 className="text-2xl font-bold">{t('tracking.organizationRequired')}</h1><p className="text-sm text-muted-foreground">{t('calendar.organizationHelp')}</p><Button asChild><Link to="/onboarding">{t('tracking.createOrganization')}</Link></Button></CardContent></Card>
}

export function CalendarWorkspacePage() {
  const { t } = useTranslation()
  const [searchParams, setSearchParams] = useSearchParams()
  const month = parseMonth(searchParams.get('month'))
  const from = toDateOnly(new Date(month.getFullYear(), month.getMonth(), 1, 12))
  const to = toDateOnly(new Date(month.getFullYear(), month.getMonth() + 1, 0, 12))
  const organizations = useQuery({ queryKey: ['organizations'], queryFn: ({ signal }) => organizationApi.list(signal) })
  const organization = organizations.data?.[0]
  const calendar = useQuery({
    queryKey: ['calendar', organization?.publicId, from, to],
    queryFn: ({ signal }) => calendarApi.get(organization!.publicId, from, to, signal),
    enabled: Boolean(organization),
  })

  const groupedEvents = useMemo(() => {
    const groups = new Map<string, CalendarEvent[]>()
    for (const event of calendar.data?.items ?? []) {
      const values = groups.get(event.eventDate) ?? []
      values.push(event)
      groups.set(event.eventDate, values)
    }
    return [...groups.entries()]
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([date, items]) => ({
        date,
        items: items.sort((left, right) => (left.eventAtUtc ?? '').localeCompare(right.eventAtUtc ?? '')),
      }))
  }, [calendar.data])

  function setMonth(date: Date) {
    setSearchParams({ month: monthKey(date) }, { replace: true })
  }

  if (organizations.isPending) return <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" /> {t('calendar.loading')}</p>
  if (organizations.isError) return <Card><CardContent className="p-8" role="alert">{t('tracking.organizationFailed')}</CardContent></Card>
  if (!organization) return <OrganizationRequired />

  return <div className="space-y-6">
    <header><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{t('calendar.eyebrow')}</p><h1 className="mt-1 text-3xl font-bold">{t('calendar.title')}</h1><p className="mt-2 text-muted-foreground">{t('calendar.help', { name: organization.name })}</p></header>
    <nav aria-label={t('calendar.month')} className="flex flex-wrap items-center justify-between gap-3 rounded-xl border bg-card p-3"><Button onClick={() => setMonth(moveMonth(month, -1))} variant="outline"><ChevronLeft className="size-4" />{t('calendar.previousMonth')}</Button><h2 className="text-lg font-bold capitalize">{formatDateValue(month, { month: 'long', year: 'numeric' })}</h2><Button onClick={() => setMonth(moveMonth(month, 1))} variant="outline">{t('calendar.nextMonth')}<ChevronRight className="size-4" /></Button></nav>
    <p aria-live="polite" className="text-sm text-muted-foreground">{calendar.data ? t('calendar.count', { count: calendar.data.items.length }) : t('calendar.preparing')}{calendar.isFetching && <span>{t('tracking.updating')}</span>}</p>
    {calendar.isPending && <Card><CardContent className="flex items-center gap-2 p-8" role="status"><LoaderCircle className="size-5 animate-spin" /> {t('calendar.loadingEvents')}</CardContent></Card>}
    {calendar.isError && <Card className="border-destructive/40"><CardContent className="space-y-3 p-8" role="alert"><CircleAlert className="size-8 text-destructive" /><h2 className="text-xl font-bold">{t('calendar.loadFailed')}</h2><p className="text-sm text-muted-foreground">{errorMessage(calendar.error)}</p><Button onClick={() => void calendar.refetch()} variant="outline">{t('tracking.retry')}</Button></CardContent></Card>}
    {calendar.data && groupedEvents.length === 0 && <Card><CardContent className="space-y-3 p-10 text-center"><CalendarDays className="mx-auto size-9 text-muted-foreground" /><h2 className="text-xl font-bold">{t('calendar.empty')}</h2><p className="text-sm text-muted-foreground">{t('calendar.emptyHelp')}</p><div className="flex flex-wrap justify-center gap-2"><Button asChild variant="outline"><Link to="/applications">{t('calendar.viewApplications')}</Link></Button><Button asChild variant="outline"><Link to="/projects">{t('calendar.viewProjects')}</Link></Button></div></CardContent></Card>}
    {groupedEvents.map((group) => <section className="space-y-3" key={group.date}><h2 className="border-b pb-2 text-lg font-bold capitalize">{formatDateOnly(group.date)}</h2><ul className="grid gap-3">{group.items.map((event) => <EventRow event={event} key={event.eventKey} />)}</ul></section>)}
  </div>
}
