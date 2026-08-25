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
import { Link, useSearchParams } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { applicationStatusNames } from '@/features/applications/application-api'
import { calendarApi, type CalendarEvent, type CalendarEventType } from '@/features/calendar/calendar-api'
import { organizationApi } from '@/features/organizations/organization-api'

const eventTypeNames: Record<CalendarEventType, string> = {
  'application-deadline': 'Cierre de fondo en postulación',
  'planned-submission': 'Envío planificado',
  'application-result': 'Resultado esperado',
  'project-start': 'Inicio de proyecto',
  'project-end': 'Término de proyecto',
  'favorite-deadline': 'Cierre de fondo favorito',
}

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
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value)
  if (!match) return value
  return new Intl.DateTimeFormat('es-CL', {
    weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
  }).format(new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]), 12))
}

function formatUtcTime(value: string | null) {
  if (!value) return null
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return null
  return `${new Intl.DateTimeFormat('es-CL', {
    hour: '2-digit', minute: '2-digit', timeZone: 'UTC', hour12: false,
  }).format(date)} UTC`
}

function errorMessage(error: unknown) {
  if (!(error instanceof ApiError)) return 'Comprueba la conexión e intenta nuevamente.'
  return Object.values(error.problem.errors ?? {}).flat()[0]
    ?? error.problem.detail
    ?? error.problem.title
}

function eventHref(event: CalendarEvent) {
  if (event.fundingApplicationPublicId) return `/applications?applicationId=${encodeURIComponent(event.fundingApplicationPublicId)}`
  if (event.projectPublicId) return `/projects/${encodeURIComponent(event.projectPublicId)}`
  if (event.fundingOpportunityPublicId) return `/opportunities/${encodeURIComponent(event.fundingOpportunityPublicId)}`
  return null
}

function EventRow({ event }: { event: CalendarEvent }) {
  const href = eventHref(event)
  const time = formatUtcTime(event.eventAtUtc)
  return <li className="flex flex-col gap-3 rounded-lg border bg-background p-4 sm:flex-row sm:items-center sm:justify-between">
    <div>
      <div className="flex flex-wrap items-center gap-2"><span className="rounded-full bg-accent px-2.5 py-1 text-xs font-semibold text-accent-foreground">{eventTypeNames[event.eventType]}</span>{event.status !== null && <span className="text-xs text-muted-foreground">{applicationStatusNames[event.status]}</span>}</div>
      <h3 className="mt-2 font-bold">{event.title}</h3>
      <p className="mt-1 flex items-center gap-1.5 text-xs text-muted-foreground"><Clock3 className="size-3.5" />{time ?? 'Durante el día'}{event.datePrecision === 0 && ' · Fecha aproximada'}</p>
    </div>
    {href && <Button asChild size="sm" variant="ghost"><Link to={href}>Abrir <ArrowRight className="size-4" /></Link></Button>}
  </li>
}

function OrganizationRequired() {
  return <Card><CardContent className="space-y-4 p-8 text-center"><h1 className="text-2xl font-bold">Primero crea tu organización</h1><p className="text-sm text-muted-foreground">El calendario reúne fechas de los proyectos, postulaciones y favoritos de tu organización.</p><Button asChild><Link to="/onboarding">Crear organización</Link></Button></CardContent></Card>
}

export function CalendarWorkspacePage() {
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

  if (organizations.isPending) return <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" /> Cargando calendario…</p>
  if (organizations.isError) return <Card><CardContent className="p-8" role="alert">No pudimos cargar tu organización.</CardContent></Card>
  if (!organization) return <OrganizationRequired />

  return <div className="space-y-6">
    <header><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Agenda de la organización</p><h1 className="mt-1 text-3xl font-bold">Calendario</h1><p className="mt-2 text-muted-foreground">Cierres e hitos registrados para {organization.name}. Confirma siempre las fechas en la fuente oficial del fondo.</p></header>
    <nav aria-label="Mes del calendario" className="flex flex-wrap items-center justify-between gap-3 rounded-xl border bg-card p-3"><Button onClick={() => setMonth(moveMonth(month, -1))} variant="outline"><ChevronLeft className="size-4" />Mes anterior</Button><h2 className="text-lg font-bold capitalize">{new Intl.DateTimeFormat('es-CL', { month: 'long', year: 'numeric' }).format(month)}</h2><Button onClick={() => setMonth(moveMonth(month, 1))} variant="outline">Mes siguiente<ChevronRight className="size-4" /></Button></nav>
    <p aria-live="polite" className="text-sm text-muted-foreground">{calendar.data ? <><strong className="text-foreground">{calendar.data.items.length}</strong> eventos en el mes</> : 'Preparando eventos…'}{calendar.isFetching && <span> · Actualizando…</span>}</p>
    {calendar.isPending && <Card><CardContent className="flex items-center gap-2 p-8" role="status"><LoaderCircle className="size-5 animate-spin" /> Cargando hitos…</CardContent></Card>}
    {calendar.isError && <Card className="border-destructive/40"><CardContent className="space-y-3 p-8" role="alert"><CircleAlert className="size-8 text-destructive" /><h2 className="text-xl font-bold">No pudimos cargar el calendario</h2><p className="text-sm text-muted-foreground">{errorMessage(calendar.error)}</p><Button onClick={() => void calendar.refetch()} variant="outline">Reintentar</Button></CardContent></Card>}
    {calendar.data && groupedEvents.length === 0 && <Card><CardContent className="space-y-3 p-10 text-center"><CalendarDays className="mx-auto size-9 text-muted-foreground" /><h2 className="text-xl font-bold">No hay hitos este mes</h2><p className="text-sm text-muted-foreground">Puedes revisar otro mes o agregar fechas a tus proyectos y postulaciones.</p><div className="flex flex-wrap justify-center gap-2"><Button asChild variant="outline"><Link to="/applications">Ver postulaciones</Link></Button><Button asChild variant="outline"><Link to="/projects">Ver proyectos</Link></Button></div></CardContent></Card>}
    {groupedEvents.map((group) => <section className="space-y-3" key={group.date}><h2 className="border-b pb-2 text-lg font-bold capitalize">{formatDateOnly(group.date)}</h2><ul className="grid gap-3">{group.items.map((event) => <EventRow event={event} key={event.eventKey} />)}</ul></section>)}
  </div>
}
