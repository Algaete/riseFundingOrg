import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  BellRing, CalendarDays, CircleAlert, FolderKanban, LoaderCircle,
  RefreshCw, Send, type LucideIcon,
} from 'lucide-react'
import { Link, useSearchParams } from 'react-router-dom'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { alertsApi } from '@/features/alerts/alerts-api'
import { applicationApi, applicationStatusNames } from '@/features/applications/application-api'
import { calendarApi, type CalendarEvent } from '@/features/calendar/calendar-api'
import { organizationApi } from '@/features/organizations/organization-api'
import { projectApi } from '@/features/projects/project-api'

const queryRoot = ['user-dashboard'] as const
const selectClass = 'h-10 min-w-60 rounded-lg border bg-background px-3 text-sm'

function dateOnly(value: Date) {
  const year = value.getFullYear()
  const month = String(value.getMonth() + 1).padStart(2, '0')
  const day = String(value.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}
function formatDate(value: string) {
  const [year, month, day] = value.slice(0, 10).split('-').map(Number)
  return new Intl.DateTimeFormat('es-CL', { dateStyle: 'medium' })
    .format(new Date(year, month - 1, day, 12))
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
  return <Link className="group rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" to={to}><Card className="h-full transition-colors group-hover:border-primary/50 group-hover:bg-accent/30"><CardContent className="flex items-start justify-between gap-4 p-5"><div><p className="text-sm font-medium text-muted-foreground">{title}</p><p className="mt-2 text-3xl font-bold">{pending ? '—' : failed ? '!' : value?.toLocaleString('es-CL') ?? '0'}</p><p className="mt-1 text-xs text-muted-foreground">{failed ? 'No disponible; reintenta' : detail}</p></div><span className="rounded-xl bg-accent p-2.5 text-primary"><Icon className="size-5" /></span></CardContent></Card></Link>
}

export function DashboardWorkspacePage() {
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

  if (organizations.isPending) return <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" />Cargando tu resumen…</p>
  if (organizations.isError) return <Card className="border-destructive/40"><CardContent className="space-y-3 p-8" role="alert"><CircleAlert className="size-8 text-destructive" /><h1 className="text-xl font-bold">No pudimos cargar tus organizaciones</h1><Button onClick={() => void organizations.refetch()} variant="outline">Reintentar</Button></CardContent></Card>
  if (!organization) return <Card><CardContent className="space-y-4 p-10 text-center"><FolderKanban className="mx-auto size-10 text-primary" /><h1 className="text-2xl font-bold">Comienza creando tu organización</h1><p className="text-muted-foreground">El resumen reunirá aquí tus proyectos, postulaciones, fechas y alertas.</p><Button asChild><Link to="/onboarding">Crear organización</Link></Button></CardContent></Card>

  const contextQuery = `organizationId=${encodeURIComponent(organization.publicId)}`
  return <div className="space-y-8">
    <header className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Tu espacio</p><h1 className="mt-1 text-3xl font-bold">Resumen</h1><p className="mt-2 text-muted-foreground">Proyectos, postulaciones y próximos hitos de {organization.name}.</p></div><div className="flex flex-wrap items-end gap-3">{organizations.data!.length > 1 && <label className="grid gap-1 text-xs font-semibold">Organización<select aria-label="Organización del resumen" className={selectClass} onChange={event => selectOrganization(event.target.value)} value={organization.publicId}>{organizations.data!.map(item => <option key={item.publicId} value={item.publicId}>{item.name}</option>)}</select></label>}<Button disabled={refreshing} onClick={refresh} variant="outline">{refreshing ? <LoaderCircle className="size-4 animate-spin" /> : <RefreshCw className="size-4" />}Actualizar</Button></div></header>

    {unavailable > 0 && <p className="flex items-center gap-2 rounded-lg bg-destructive/10 p-3 text-sm text-destructive" role="status"><CircleAlert className="size-4" />{unavailable === 1 ? 'Un indicador no pudo actualizarse.' : `${unavailable} indicadores no pudieron actualizarse.`} Los demás datos siguen disponibles.</p>}

    <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4" aria-label="Indicadores de la organización">
      <Metric detail="registrados" failed={projects.isError} icon={FolderKanban} pending={projects.isPending} title="Proyectos" to={`/projects?${contextQuery}`} value={projects.data?.length} />
      <Metric detail="en seguimiento" failed={applications.isError} icon={Send} pending={applications.isPending} title="Postulaciones" to={`/applications?${contextQuery}`} value={applications.data?.totalCount} />
      <Metric detail="en los próximos 60 días" failed={calendar.isError} icon={CalendarDays} pending={calendar.isPending} title="Próximos hitos" to={`/calendar?${contextQuery}`} value={calendar.data?.items.length} />
      <Metric detail="búsquedas guardadas" failed={alerts.isError} icon={BellRing} pending={alerts.isPending} title="Alertas" to={`/alerts?${contextQuery}`} value={alerts.data?.totalCount} />
    </section>

    <section className="grid gap-6 xl:grid-cols-2">
      <Card><CardHeader><CardTitle>Próximos hitos</CardTitle><p className="text-sm text-muted-foreground">Fechas durante los próximos 60 días.</p></CardHeader><CardContent className="space-y-3">{calendar.isPending && <p className="text-sm text-muted-foreground">Cargando calendario…</p>}{calendar.isError && <p className="text-sm text-destructive">El calendario no está disponible.</p>}{calendar.data?.items.slice().sort((left, right) => left.eventDate.localeCompare(right.eventDate)).slice(0, 5).map(event => <Link className="flex items-center justify-between gap-4 rounded-lg border p-4 hover:bg-accent/40" key={event.eventKey} to={eventPath(event)}><div><p className="font-semibold">{event.title}</p><p className="text-sm text-muted-foreground">{formatDate(event.eventDate)}</p></div><CalendarDays className="size-4 shrink-0 text-primary" /></Link>)}{calendar.data?.items.length === 0 && <p className="text-sm text-muted-foreground">No hay hitos en este período.</p>}<Button asChild size="sm" variant="outline"><Link to={`/calendar?${contextQuery}`}>Ver calendario completo</Link></Button></CardContent></Card>

      <Card><CardHeader><CardTitle>Postulaciones recientes</CardTitle><p className="text-sm text-muted-foreground">Últimos seguimientos actualizados.</p></CardHeader><CardContent className="space-y-3">{applications.isPending && <p className="text-sm text-muted-foreground">Cargando postulaciones…</p>}{applications.isError && <p className="text-sm text-destructive">Las postulaciones no están disponibles.</p>}{applications.data?.items.slice(0, 5).map(item => <Link className="block rounded-lg border p-4 hover:bg-accent/40" key={item.publicId} to={`/applications?applicationId=${encodeURIComponent(item.publicId)}&${contextQuery}`}><p className="font-semibold">{item.fundingOpportunity.title}</p><p className="mt-1 text-sm text-muted-foreground">{item.project.title} · {applicationStatusNames[item.status]}</p></Link>)}{applications.data?.items.length === 0 && <p className="text-sm text-muted-foreground">Todavía no hay postulaciones en seguimiento.</p>}<Button asChild size="sm" variant="outline"><Link to={`/applications?${contextQuery}`}>Ver todas las postulaciones</Link></Button></CardContent></Card>
    </section>
  </div>
}
