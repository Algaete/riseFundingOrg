import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  ArrowUpRight,
  Building2,
  CircleAlert,
  FileSearch,
  Landmark,
  LoaderCircle,
  RefreshCw,
  ServerCog,
  ShieldCheck,
  Upload,
  Users,
  WalletCards,
  type LucideIcon,
} from 'lucide-react'
import { Link } from 'react-router-dom'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { adminUsersApi } from '@/features/admin-users/admin-users-api'
import {
  adminFundersApi,
  adminFundingOpportunitiesApi,
} from '@/features/funding/admin-funding-api'
import { adminImportApi, type ImportRunStatus } from '@/features/imports/admin-import-api'
import { projectReviewApi } from '@/features/projects/project-api'

const queryRoot = ['admin-dashboard'] as const

const importStatusNames: Record<ImportRunStatus, string> = {
  queued: 'En cola',
  running: 'En ejecución',
  completed: 'Completada',
  'completed-with-errors': 'Terminó con errores',
  failed: 'Fallida',
  cancelled: 'Cancelada',
  unknown: 'Estado desconocido',
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat('es-CL', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

function MetricCard({
  title,
  value,
  detail,
  icon: Icon,
  to,
  pending,
  failed,
}: {
  title: string
  value: number | undefined
  detail: string
  icon: LucideIcon
  to: string
  pending: boolean
  failed: boolean
}) {
  return <Link className="group rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" to={to}>
    <Card className="h-full transition-colors group-hover:border-primary/50 group-hover:bg-accent/30">
      <CardContent className="flex h-full items-start justify-between gap-4 p-5">
        <div>
          <p className="text-sm font-medium text-muted-foreground">{title}</p>
          <p className="mt-2 text-3xl font-bold" data-testid={`metric-${title}`}>
            {pending ? '—' : failed ? '!' : value?.toLocaleString('es-CL') ?? '0'}
          </p>
          <p className="mt-1 text-xs text-muted-foreground">{failed ? 'No disponible; reintenta' : detail}</p>
        </div>
        <span className="rounded-xl bg-accent p-2.5 text-primary"><Icon className="size-5" /></span>
      </CardContent>
    </Card>
  </Link>
}

function SectionError({ children }: { children: string }) {
  return <p className="flex items-center gap-2 rounded-lg bg-destructive/10 p-3 text-sm text-destructive" role="status">
    <CircleAlert className="size-4 shrink-0" />{children}
  </p>
}

export function AdminDashboardWorkspacePage() {
  const queryClient = useQueryClient()
  const users = useQuery({
    queryKey: [...queryRoot, 'users'],
    queryFn: ({ signal }) => adminUsersApi.list({ page: 1, pageSize: 1 }, signal),
  })
  const projects = useQuery({
    queryKey: [...queryRoot, 'projects'],
    queryFn: ({ signal }) => projectReviewApi.list(1, 5, signal),
  })
  const opportunities = useQuery({
    queryKey: [...queryRoot, 'opportunities'],
    queryFn: ({ signal }) => adminFundingOpportunitiesApi.list({
      page: 1, pageSize: 1, includeInactive: true,
    }, signal),
  })
  const pendingOpportunities = useQuery({
    queryKey: [...queryRoot, 'pending-opportunities'],
    queryFn: ({ signal }) => adminFundingOpportunitiesApi.list({
      page: 1, pageSize: 1, status: 1,
    }, signal),
  })
  const funders = useQuery({
    queryKey: [...queryRoot, 'funders'],
    queryFn: ({ signal }) => adminFundersApi.list({
      page: 1, pageSize: 1, includeInactive: true,
    }, signal),
  })
  const imports = useQuery({
    queryKey: [...queryRoot, 'imports'],
    queryFn: ({ signal }) => adminImportApi.list({ page: 1, pageSize: 5 }, signal),
  })
  const sources = useQuery({
    queryKey: [...queryRoot, 'sources'],
    queryFn: ({ signal }) => adminImportApi.listSources(signal),
  })
  const queries = [
    users, projects, opportunities, pendingOpportunities, funders, imports, sources,
  ]
  const refreshing = queries.some(query => query.isFetching)
  const unavailable = queries.filter(query => query.isError).length
  const recentImportIssues = imports.data?.items.filter(item =>
    item.status === 'failed' || item.status === 'completed-with-errors').length ?? 0
  const activeImports = imports.data?.items.filter(item =>
    item.status === 'queued' || item.status === 'running').length ?? 0
  const activeSources = sources.data?.filter(source => source.isEnabled).length
  const sourceIssues = sources.data?.filter(source =>
    source.isEnabled && source.acquisitionReady === false).length ?? 0

  function refresh() {
    void queryClient.invalidateQueries({ queryKey: queryRoot })
  }

  return <div className="space-y-8">
    <header className="flex flex-wrap items-end justify-between gap-4">
      <div>
        <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Administración</p>
        <h1 className="mt-1 text-3xl font-bold">Panel de control</h1>
        <p className="mt-2 max-w-3xl text-muted-foreground">Estado operativo, tareas pendientes y accesos rápidos de la plataforma.</p>
      </div>
      <Button disabled={refreshing} onClick={refresh} variant="outline">
        {refreshing ? <LoaderCircle className="size-4 animate-spin" /> : <RefreshCw className="size-4" />}
        Actualizar
      </Button>
    </header>

    {unavailable > 0 && <SectionError>{unavailable === 1
      ? 'Un indicador no pudo actualizarse. Los demás datos siguen disponibles.'
      : `${unavailable} indicadores no pudieron actualizarse. Los demás datos siguen disponibles.`}</SectionError>}

    <section aria-labelledby="admin-summary-title" className="space-y-3">
      <h2 className="text-xl font-bold" id="admin-summary-title">Resumen</h2>
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard detail="esperando moderación" failed={projects.isError} icon={ShieldCheck} pending={projects.isPending} title="Proyectos pendientes" to="/admin/projects" value={projects.data?.totalCount} />
        <MetricCard detail="cuentas registradas" failed={users.isError} icon={Users} pending={users.isPending} title="Usuarios" to="/admin/users" value={users.data?.totalCount} />
        <MetricCard detail="oportunidades registradas" failed={opportunities.isError} icon={WalletCards} pending={opportunities.isPending} title="Fondos" to="/admin/funding" value={opportunities.data?.totalCount} />
        <MetricCard detail="esperando revisión editorial" failed={pendingOpportunities.isError} icon={Building2} pending={pendingOpportunities.isPending} title="Fondos pendientes" to="/admin/funding?status=1" value={pendingOpportunities.data?.totalCount} />
        <MetricCard detail="entidades registradas" failed={funders.isError} icon={Landmark} pending={funders.isPending} title="Financiadores" to="/admin/funders" value={funders.data?.totalCount} />
        <MetricCard detail={`${activeSources ?? 0} habilitadas`} failed={sources.isError} icon={ServerCog} pending={sources.isPending} title="Fuentes" to="/admin/sources" value={sources.data?.length} />
        <MetricCard detail="ejecuciones registradas" failed={imports.isError} icon={Upload} pending={imports.isPending} title="Importaciones" to="/admin/imports" value={imports.data?.totalCount} />
        <MetricCard detail="entre las últimas 5 ejecuciones" failed={imports.isError} icon={RefreshCw} pending={imports.isPending} title="Importaciones activas" to="/admin/imports" value={activeImports} />
      </div>
    </section>

    <section className="grid gap-6 xl:grid-cols-[1.35fr_1fr]">
      <Card>
        <CardHeader className="flex-row items-center justify-between gap-4">
          <div><CardTitle>Prioridades</CardTitle><p className="text-sm text-muted-foreground">Elementos que podrían requerir intervención.</p></div>
          <FileSearch className="size-5 text-primary" />
        </CardHeader>
        <CardContent className="space-y-3">
          <Link className="flex items-center justify-between gap-4 rounded-lg border p-4 hover:bg-accent/40" to="/admin/projects"><div><p className="font-semibold">Moderación de proyectos</p><p className="text-sm text-muted-foreground">Revisar antes de publicar en el marketplace.</p></div><strong>{projects.data?.totalCount ?? '—'}</strong></Link>
          <Link className="flex items-center justify-between gap-4 rounded-lg border p-4 hover:bg-accent/40" to="/admin/funding?status=1"><div><p className="font-semibold">Revisión editorial de fondos</p><p className="text-sm text-muted-foreground">Oportunidades enviadas para aprobación.</p></div><strong>{pendingOpportunities.isError ? '!' : pendingOpportunities.data?.totalCount ?? '—'}</strong></Link>
          <Link className="flex items-center justify-between gap-4 rounded-lg border p-4 hover:bg-accent/40" to="/admin/imports"><div><p className="font-semibold">Importaciones con incidentes</p><p className="text-sm text-muted-foreground">Detectadas entre las últimas cinco ejecuciones.</p></div><strong>{imports.isError ? '!' : recentImportIssues}</strong></Link>
          <Link className="flex items-center justify-between gap-4 rounded-lg border p-4 hover:bg-accent/40" to="/admin/sources"><div><p className="font-semibold">Fuentes que requieren atención</p><p className="text-sm text-muted-foreground">Fuentes habilitadas que aún no están listas para adquisición.</p></div><strong>{sources.isError ? '!' : sourceIssues}</strong></Link>
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle>Acciones rápidas</CardTitle><p className="text-sm text-muted-foreground">Atajos a las tareas administrativas frecuentes.</p></CardHeader>
        <CardContent className="grid gap-3 sm:grid-cols-2 xl:grid-cols-1">
          {[
            ['/admin/projects', 'Revisar proyectos', ShieldCheck],
            ['/admin/funding/new', 'Crear fondo', WalletCards],
            ['/admin/funders/new', 'Crear financiador', Landmark],
            ['/admin/imports', 'Ejecutar importación', Upload],
            ['/admin/users', 'Consultar usuarios', Users],
          ].map(([to, label, Icon]) => <Button asChild className="justify-between" key={String(to)} variant="outline"><Link to={String(to)}><span className="inline-flex items-center gap-2"><Icon className="size-4" />{String(label)}</span><ArrowUpRight className="size-4" /></Link></Button>)}
        </CardContent>
      </Card>
    </section>

    <section className="grid gap-6 lg:grid-cols-2">
      <Card>
        <CardHeader className="flex-row items-center justify-between"><div><CardTitle>Proyectos por revisar</CardTitle><p className="text-sm text-muted-foreground">Envíos más recientes.</p></div><Button asChild size="sm" variant="ghost"><Link to="/admin/projects">Ver todos</Link></Button></CardHeader>
        <CardContent className="space-y-2">
          {projects.isPending && <p className="text-sm text-muted-foreground">Cargando proyectos…</p>}
          {projects.isError && <SectionError>No se pudo cargar la cola de proyectos.</SectionError>}
          {projects.data?.items.length === 0 && <p className="rounded-lg bg-muted p-4 text-sm">La revisión de proyectos está al día.</p>}
          {projects.data?.items.map(item => <Link className="block rounded-lg border p-3 hover:bg-accent/40" key={item.projectId} to={`/admin/projects/${item.projectId}`}><p className="font-semibold">{item.title}</p><p className="mt-1 text-sm text-muted-foreground">{item.organizationName} · {item.completeness}% completo</p><p className="mt-1 text-xs text-muted-foreground">Enviado {formatDate(item.submittedAtUtc)}</p></Link>)}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex-row items-center justify-between"><div><CardTitle>Importaciones recientes</CardTitle><p className="text-sm text-muted-foreground">Últimas ejecuciones registradas.</p></div><Button asChild size="sm" variant="ghost"><Link to="/admin/imports">Ver todas</Link></Button></CardHeader>
        <CardContent className="space-y-2">
          {imports.isPending && <p className="text-sm text-muted-foreground">Cargando importaciones…</p>}
          {imports.isError && <SectionError>No se pudieron cargar las importaciones.</SectionError>}
          {imports.data?.items.length === 0 && <p className="rounded-lg bg-muted p-4 text-sm">Todavía no hay ejecuciones de importación.</p>}
          {imports.data?.items.map(item => <Link className="flex items-center justify-between gap-3 rounded-lg border p-3 hover:bg-accent/40" key={item.runId} to={`/admin/imports/${item.runId}`}><div><p className="font-semibold">{item.sourceName}</p><p className="mt-1 text-xs text-muted-foreground">{formatDate(item.createdAtUtc)} · {item.retrievedCount} recuperados</p></div><span className="rounded-full bg-muted px-2.5 py-1 text-xs font-semibold">{importStatusNames[item.status]}</span></Link>)}
        </CardContent>
      </Card>
    </section>
  </div>
}
