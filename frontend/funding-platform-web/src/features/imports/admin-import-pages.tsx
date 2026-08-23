import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  AlertTriangle,
  ArrowLeft,
  BookOpen,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  CircleAlert,
  Clock3,
  DatabaseZap,
  ExternalLink,
  FileSearch,
  FileUp,
  Gauge,
  GitCompareArrows,
  Globe2,
  LoaderCircle,
  Play,
  RefreshCw,
  Search,
  ServerCog,
  ShieldCheck,
} from 'lucide-react'
import { type FormEvent, type ReactNode, useEffect, useMemo, useState } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { executeEditorialCommand } from '@/features/funding/editorial-command-cache'
import {
  adminImportApi,
  importAdminErrorMessage,
  isImportRunActive,
  shouldPollImportRuns,
  type AdminFundingSourceView,
  type ImportDedupeDecision,
  type ImportDedupeComparison,
  type ImportRunItem,
  type ImportRunStatus,
  type ImportRunSummary,
} from '@/features/imports/admin-import-api'

const pageSize = 20
const inputClass = 'h-10 w-full rounded-lg border bg-background px-3 text-sm'

const statusLabels: Record<ImportRunStatus, string> = {
  queued: 'En cola',
  running: 'En ejecución',
  completed: 'Completada',
  'completed-with-errors': 'Completada con observaciones',
  failed: 'Fallida',
  cancelled: 'Cancelada',
  unknown: 'Estado desconocido',
}

const triggerLabels: Record<number, string> = {
  0: 'Manual',
  1: 'Programada',
  2: 'Reintento',
}

const itemStatusLabels: Record<number, string> = {
  0: 'Pendiente',
  1: 'Procesando',
  2: 'Completado',
  3: 'Fallido',
}

function formatDate(value: string | null) {
  if (!value) return 'Sin información'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return 'Sin información'
  return new Intl.DateTimeFormat('es-CL', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(date)
}

function formatCandidateDate(value: string | null) {
  if (!value) return 'Sin información'
  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value)
  if (!dateOnly) return formatDate(value)
  const [, year, month, day] = dateOnly
  return new Intl.DateTimeFormat('es-CL', { dateStyle: 'medium' }).format(
    new Date(Number(year), Number(month) - 1, Number(day)),
  )
}

function StatusBadge({ status }: { status: ImportRunStatus }) {
  const color = status === 'completed'
    ? 'bg-emerald-100 text-emerald-900 dark:bg-emerald-950 dark:text-emerald-100'
    : status === 'running'
      ? 'bg-blue-100 text-blue-900 dark:bg-blue-950 dark:text-blue-100'
      : status === 'queued'
        ? 'bg-amber-100 text-amber-900 dark:bg-amber-950 dark:text-amber-100'
        : status === 'completed-with-errors'
          ? 'bg-orange-100 text-orange-900 dark:bg-orange-950 dark:text-orange-100'
          : status === 'failed'
            ? 'bg-destructive/10 text-destructive'
            : 'bg-muted text-muted-foreground'

  return (
    <span className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-semibold ${color}`}>
      {(status === 'queued' || status === 'running') && <LoaderCircle className="size-3.5 animate-spin" aria-hidden />}
      {statusLabels[status]}
    </span>
  )
}

function PageHeading({ actions, description, title }: { actions?: ReactNode; description: string; title: string }) {
  return (
    <div className="flex flex-col justify-between gap-4 lg:flex-row lg:items-start">
      <div>
        <p className="text-xs font-bold uppercase tracking-[0.18em] text-primary">Administración</p>
        <h1 className="mt-2 text-3xl font-bold tracking-tight">{title}</h1>
        <p className="mt-2 max-w-3xl text-sm text-muted-foreground">{description}</p>
      </div>
      {actions && <div className="flex flex-wrap gap-2">{actions}</div>}
    </div>
  )
}

function ErrorNotice({ children, retry }: { children: ReactNode; retry?: () => void }) {
  return (
    <div className="flex flex-col gap-3 rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm text-destructive sm:flex-row sm:items-center sm:justify-between" role="alert">
      <span className="flex items-start gap-2">
        <CircleAlert className="mt-0.5 size-4 shrink-0" aria-hidden />
        <span>{children}</span>
      </span>
      {retry && (
        <Button onClick={retry} size="sm" type="button" variant="outline">
          <RefreshCw className="size-4" aria-hidden /> Reintentar
        </Button>
      )}
    </div>
  )
}

function processedCount(run: ImportRunSummary) {
  return run.createdCount
    + run.updatedCount
    + run.unchangedCount
    + run.stagedForReviewCount
    + run.failedCount
}

function RunProgress({ run }: { run: ImportRunSummary }) {
  const processed = processedCount(run)
  const total = Math.max(run.retrievedCount, processed)
  const percentage = total > 0 ? Math.min(100, Math.round((processed / total) * 100)) : 0
  const active = isImportRunActive(run)
  return (
    <div className="space-y-1.5">
      <div className="flex justify-between text-xs text-muted-foreground">
        <span>{processed} procesados</span>
        <span>{total > 0 ? `${percentage}%` : active ? 'Esperando resultados' : 'Sin resultados'}</span>
      </div>
      <div
        aria-label="Progreso de la importación"
        aria-valuemax={total || undefined}
        aria-valuemin={0}
        aria-valuenow={total ? processed : undefined}
        className="h-2 overflow-hidden rounded-full bg-muted"
        role="progressbar"
      >
        <div
          className={`h-full rounded-full bg-primary transition-[width] ${active && total === 0 ? 'w-1/3 animate-pulse' : ''}`}
          style={total > 0 ? { width: `${percentage}%` } : undefined}
        />
      </div>
    </div>
  )
}

function RunCard({ run }: { run: ImportRunSummary }) {
  return (
    <article className="rounded-xl border bg-background p-4">
      <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-start">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <StatusBadge status={run.status} />
            <span className="text-xs font-medium text-muted-foreground">{triggerLabels[run.triggerType] ?? 'Origen desconocido'}</span>
          </div>
          <h3 className="mt-3 truncate font-semibold">{run.sourceName}</h3>
          <p className="mt-1 truncate text-sm text-muted-foreground">
            {run.keyword ? `Búsqueda: ${run.keyword}` : 'Sin palabra clave'} · creada {formatDate(run.createdAtUtc)}
          </p>
        </div>
        <Button asChild size="sm" variant="outline">
          <Link to={`/admin/imports/${run.runId}`}>Ver detalle</Link>
        </Button>
      </div>
      <div className="mt-4">
        <RunProgress run={run} />
      </div>
      <dl className="mt-4 grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
        <div><dt className="text-muted-foreground">Recuperados</dt><dd className="font-semibold">{run.retrievedCount}</dd></div>
        <div><dt className="text-muted-foreground">Nuevos</dt><dd className="font-semibold">{run.createdCount}</dd></div>
        <div><dt className="text-muted-foreground">A revisión</dt><dd className="font-semibold">{run.stagedForReviewCount}</dd></div>
        <div><dt className="text-muted-foreground">Fallidos</dt><dd className="font-semibold">{run.failedCount}</dd></div>
      </dl>
    </article>
  )
}

function validPositiveInteger(value: string | null, fallback: number) {
  const parsed = Number(value)
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback
}

function validStatus(value: string | null) {
  if (value === null || value === '') return undefined
  const parsed = Number(value)
  return Number.isInteger(parsed) && parsed >= 0 && parsed <= 5 ? parsed : undefined
}

export function AdminImportRunsPage() {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const [searchParams, setSearchParams] = useSearchParams()
  const [keyword, setKeyword] = useState('nonprofit')
  const [maximumResults, setMaximumResults] = useState('25')
  const [selectedSourceId, setSelectedSourceId] = useState('')
  const [formMessage, setFormMessage] = useState<string | null>(null)
  const sourceId = validPositiveInteger(searchParams.get('sourceId'), 0) || undefined
  const status = validStatus(searchParams.get('status'))
  const page = validPositiveInteger(searchParams.get('page'), 1)

  const sources = useQuery({
    queryKey: ['admin', 'import-sources'],
    queryFn: ({ signal }) => adminImportApi.listSources(signal),
    staleTime: 30_000,
  })
  const grantsSources = useMemo(
    () => (sources.data ?? []).filter((source) => source.isGrantsGov && source.isEnabled),
    [sources.data],
  )

  useEffect(() => {
    if (selectedSourceId || grantsSources.length === 0) return
    const requested = grantsSources.find((source) => source.id === sourceId)
    setSelectedSourceId(String(requested?.id ?? grantsSources[0].id))
  }, [grantsSources, selectedSourceId, sourceId])

  const filters = { sourceId, status, page, pageSize }
  const runs = useQuery({
    queryKey: ['admin', 'import-runs', filters],
    queryFn: ({ signal }) => adminImportApi.list(filters, signal),
    placeholderData: keepPreviousData,
    refetchInterval: (query) => shouldPollImportRuns(query.state.data?.items ?? []) ? 3_000 : false,
  })

  const createRun = useMutation({
    mutationFn: async () => {
      const parsedSourceId = Number(selectedSourceId)
      const parsedMaximum = Number(maximumResults)
      const trimmedKeyword = keyword.trim()
      if (!Number.isInteger(parsedSourceId) || parsedSourceId <= 0) throw new Error('source-required')
      if (trimmedKeyword.length < 2 || trimmedKeyword.length > 100) throw new Error('keyword-invalid')
      if (!Number.isInteger(parsedMaximum) || parsedMaximum < 1 || parsedMaximum > 25) throw new Error('maximum-invalid')
      const payload = { keyword: trimmedKeyword, maximumResults: parsedMaximum }
      return executeEditorialCommand(
        `import-run:create:${parsedSourceId}`,
        payload,
        (idempotencyKey) => adminImportApi.create(parsedSourceId, payload, idempotencyKey),
      )
    },
    onSuccess: async (accepted) => {
      setFormMessage(accepted.wasReplay
        ? 'La solicitud ya existía; abrimos la ejecución original.'
        : 'La importación quedó en cola.')
      await queryClient.invalidateQueries({ queryKey: ['admin', 'import-runs'] })
      void navigate(`/admin/imports/${accepted.runId}`)
    },
    onError: (error) => {
      if (error instanceof Error && error.message === 'source-required') {
        setFormMessage('Selecciona una fuente Grants.gov habilitada.')
      } else if (error instanceof Error && error.message === 'keyword-invalid') {
        setFormMessage('La búsqueda debe tener entre 2 y 100 caracteres.')
      } else if (error instanceof Error && error.message === 'maximum-invalid') {
        setFormMessage('La cantidad debe ser un entero entre 1 y 25.')
      } else {
        setFormMessage(importAdminErrorMessage(error))
      }
    },
  })

  function updateFilter(name: 'sourceId' | 'status', value: string) {
    const next = new URLSearchParams(searchParams)
    if (value) next.set(name, value)
    else next.delete(name)
    next.delete('page')
    setSearchParams(next)
  }

  function changePage(nextPage: number) {
    const next = new URLSearchParams(searchParams)
    if (nextPage <= 1) next.delete('page')
    else next.set('page', String(nextPage))
    setSearchParams(next)
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    setFormMessage(null)
    createRun.mutate()
  }

  const totalPages = Math.max(1, Math.ceil((runs.data?.totalCount ?? 0) / pageSize))
  const isPolling = shouldPollImportRuns(runs.data?.items ?? [])

  return (
    <div className="space-y-6">
      <PageHeading
        actions={(
          <>
            <Button asChild variant="outline"><Link to="/admin/sources"><ServerCog className="size-4" aria-hidden />Ver fuentes</Link></Button>
            <Button asChild variant="outline"><Link to="/admin/imports/upload-document"><FileUp className="size-4" aria-hidden />Cargar PDF seguro</Link></Button>
          </>
        )}
        description="Inicia y supervisa búsquedas controladas. Cada candidato queda pendiente de revisión editorial: nunca se publica automáticamente."
        title="Importaciones"
      />

      <Card>
        <CardHeader>
          <div className="flex items-start gap-3">
            <DatabaseZap className="mt-0.5 size-5 text-primary" aria-hidden />
            <div>
              <CardTitle>Importar desde Grants.gov</CardTitle>
              <p className="mt-1 text-sm text-muted-foreground">La tarea se ejecuta en segundo plano y puede revisarse sin mantener esta página abierta.</p>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          {sources.isError && <ErrorNotice retry={() => void sources.refetch()}>{importAdminErrorMessage(sources.error)}</ErrorNotice>}
          {!sources.isPending && !sources.isError && grantsSources.length === 0 && (
            <ErrorNotice>No hay una fuente Grants.gov habilitada. Revisa su estado en Fuentes antes de importar.</ErrorNotice>
          )}
          <form className="grid gap-4 lg:grid-cols-[minmax(12rem,1fr)_minmax(14rem,2fr)_10rem_auto] lg:items-end" noValidate onSubmit={submit}>
            <label className="grid gap-1.5 text-sm font-semibold">
              Fuente
              <select
                className={inputClass}
                disabled={sources.isPending || grantsSources.length === 0 || createRun.isPending}
                onChange={(event) => setSelectedSourceId(event.target.value)}
                value={selectedSourceId}
              >
                <option value="">Selecciona una fuente</option>
                {grantsSources.map((source) => <option key={source.id} value={source.id}>{source.name}</option>)}
              </select>
            </label>
            <label className="grid gap-1.5 text-sm font-semibold">
              Palabra clave
              <Input
                autoComplete="off"
                disabled={createRun.isPending}
                maxLength={100}
                onChange={(event) => setKeyword(event.target.value)}
                placeholder="Ej.: climate resilience"
                value={keyword}
              />
            </label>
            <label className="grid gap-1.5 text-sm font-semibold">
              Máximo
              <Input
                disabled={createRun.isPending}
                inputMode="numeric"
                max={25}
                min={1}
                onChange={(event) => setMaximumResults(event.target.value)}
                type="number"
                value={maximumResults}
              />
            </label>
            <Button disabled={createRun.isPending || grantsSources.length === 0} type="submit">
              {createRun.isPending ? <LoaderCircle className="size-4 animate-spin" aria-hidden /> : <Play className="size-4" aria-hidden />}
              {createRun.isPending ? 'Enviando…' : 'Iniciar importación'}
            </Button>
          </form>
          {formMessage && <p className="mt-4 text-sm" role={createRun.isError ? 'alert' : 'status'}>{formMessage}</p>}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <div className="flex flex-col justify-between gap-4 lg:flex-row lg:items-end">
            <div>
              <CardTitle>Ejecuciones recientes</CardTitle>
              <p className="mt-1 flex items-center gap-2 text-sm text-muted-foreground" role="status">
                {isPolling && <><RefreshCw className="size-3.5 animate-spin" aria-hidden />Actualizando ejecuciones activas</>}
                {!isPolling && 'El seguimiento se actualiza al iniciar una tarea.'}
              </p>
            </div>
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="grid gap-1 text-xs font-semibold">
                Fuente
                <select className={inputClass} onChange={(event) => updateFilter('sourceId', event.target.value)} value={sourceId ?? ''}>
                  <option value="">Todas</option>
                  {(sources.data ?? []).map((source) => <option key={source.id} value={source.id}>{source.name}</option>)}
                </select>
              </label>
              <label className="grid gap-1 text-xs font-semibold">
                Estado
                <select className={inputClass} onChange={(event) => updateFilter('status', event.target.value)} value={status ?? ''}>
                  <option value="">Todos</option>
                  <option value="0">En cola</option><option value="1">En ejecución</option><option value="2">Completada</option>
                  <option value="3">Con observaciones</option><option value="4">Fallida</option><option value="5">Cancelada</option>
                </select>
              </label>
            </div>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {runs.isError && <ErrorNotice retry={() => void runs.refetch()}>{importAdminErrorMessage(runs.error)}</ErrorNotice>}
          {runs.isPending && (
            <p className="flex items-center gap-2 text-sm text-muted-foreground" role="status"><LoaderCircle className="size-4 animate-spin" aria-hidden />Cargando ejecuciones…</p>
          )}
          {!runs.isPending && !runs.isError && runs.data?.items.length === 0 && (
            <div className="grid place-items-center rounded-xl border border-dashed p-10 text-center">
              <FileSearch className="size-8 text-muted-foreground" aria-hidden />
              <p className="mt-3 font-semibold">No hay ejecuciones con estos filtros</p>
              <p className="mt-1 text-sm text-muted-foreground">Inicia una importación o cambia los filtros.</p>
            </div>
          )}
          <div className="grid gap-3">{runs.data?.items.map((run) => <RunCard key={run.runId} run={run} />)}</div>
          {(runs.data?.totalCount ?? 0) > 0 && (
            <div className="flex flex-col items-center justify-between gap-3 border-t pt-4 sm:flex-row">
              <p className="text-sm text-muted-foreground">Página {page} de {totalPages} · {runs.data?.totalCount} ejecuciones</p>
              <div className="flex gap-2">
                <Button disabled={page <= 1 || runs.isFetching} onClick={() => changePage(page - 1)} size="sm" type="button" variant="outline"><ChevronLeft className="size-4" aria-hidden />Anterior</Button>
                <Button disabled={page >= totalPages || runs.isFetching} onClick={() => changePage(page + 1)} size="sm" type="button" variant="outline">Siguiente<ChevronRight className="size-4" aria-hidden /></Button>
              </div>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

function SourceCard({ source }: { source: AdminFundingSourceView }) {
  const requestPolicy = source.rateLimitPerMinute !== null
    ? `${source.rateLimitPerMinute} solicitudes/minuto`
    : source.minimumRequestIntervalSeconds !== null
      ? `1 solicitud cada ${source.minimumRequestIntervalSeconds} s`
      : 'Sin información pública'
  return (
    <Card className="flex h-full flex-col">
      <CardHeader>
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="text-xs font-semibold uppercase tracking-wide text-primary">{source.providerCode || 'fuente'}</p>
            <CardTitle className="mt-1 truncate">{source.name}</CardTitle>
            {source.baseUrl && <p className="mt-1 truncate text-xs text-muted-foreground">{source.baseUrl}</p>}
          </div>
          <span className={`rounded-full px-2.5 py-1 text-xs font-semibold ${source.isEnabled ? 'bg-emerald-100 text-emerald-900 dark:bg-emerald-950 dark:text-emerald-100' : 'bg-muted text-muted-foreground'}`}>
            {source.isEnabled ? 'Habilitada' : 'Pausada'}
          </span>
        </div>
      </CardHeader>
      <CardContent className="flex flex-1 flex-col justify-between gap-5">
        <dl className="grid gap-3 text-sm sm:grid-cols-2">
          <div><dt className="text-muted-foreground">Estado operacional</dt><dd className="font-semibold">{source.operationalStatus}</dd></div>
          <div><dt className="text-muted-foreground">Cumplimiento</dt><dd className="font-semibold">{source.complianceStatus}</dd></div>
          <div className="sm:col-span-2">
            <dt className="text-muted-foreground">Gobernanza de adquisición</dt>
            <dd className="font-semibold">
              {source.acquisitionReady === true
                ? 'Lista para adquirir'
                : source.acquisitionReady === false ? 'Bloqueada por política' : 'Sin evaluación disponible'}
            </dd>
          </div>
          <div>
            <dt className="flex items-center gap-1.5 text-muted-foreground"><BookOpen className="size-3.5" aria-hidden />Licencia</dt>
            <dd className="font-semibold">
              {source.licenseUrl
                ? <a className="underline underline-offset-2" href={source.licenseUrl} rel="noreferrer" target="_blank">{source.licenseName}<ExternalLink className="ml-1 inline size-3" aria-hidden /></a>
                : source.licenseName}
            </dd>
            <dd className="text-xs text-muted-foreground">{source.licenseStatus}</dd>
          </div>
          <div><dt className="flex items-center gap-1.5 text-muted-foreground"><ShieldCheck className="size-3.5" aria-hidden />Allowlist</dt><dd className="font-semibold">{source.allowlistStatus}{source.allowedHostCount !== null && source.allowedHostCount > 0 ? ` · ${source.allowedHostCount} host${source.allowedHostCount === 1 ? '' : 's'}` : ''}</dd></div>
          <div><dt className="flex items-center gap-1.5 text-muted-foreground"><Gauge className="size-3.5" aria-hidden />Límite de consulta</dt><dd className="font-semibold">{requestPolicy}</dd></div>
          <div><dt className="flex items-center gap-1.5 text-muted-foreground"><Globe2 className="size-3.5" aria-hidden />Robots</dt><dd className="font-semibold">{source.robotsPolicyStatus}</dd><dd className="text-xs text-muted-foreground">Revisado: {formatDate(source.robotsReviewedAtUtc)}</dd></div>
          {source.isRssProvider && (
            <div className="sm:col-span-2">
              <dt className="text-muted-foreground">Proveedor RSS</dt>
              <dd className="font-semibold">RSS configurado{source.rssFeedHost ? ` · ${source.rssFeedHost}` : ''}</dd>
              <dd className="text-xs text-muted-foreground">Sólo se consulta la URL aprobada por allowlist; esta pantalla no admite feeds arbitrarios.</dd>
            </div>
          )}
          <div><dt className="text-muted-foreground">Último éxito</dt><dd className="font-semibold">{formatDate(source.lastSuccessfulRunAtUtc)}</dd></div>
          <div><dt className="text-muted-foreground">Próxima ejecución</dt><dd className="font-semibold">{formatDate(source.nextScheduledRunAtUtc)}</dd></div>
        </dl>
        <div className="flex flex-wrap gap-2">
          <Button asChild size="sm" variant="outline"><Link to={`/admin/imports?sourceId=${source.id}`}><Clock3 className="size-4" aria-hidden />Ver ejecuciones</Link></Button>
          {source.isGrantsGov && source.isEnabled && (
            <Button asChild size="sm"><Link to={`/admin/imports?sourceId=${source.id}`}><Play className="size-4" aria-hidden />Crear importación</Link></Button>
          )}
        </div>
      </CardContent>
    </Card>
  )
}

export function AdminImportSourcesPage() {
  const sources = useQuery({
    queryKey: ['admin', 'import-sources'],
    queryFn: ({ signal }) => adminImportApi.listSources(signal),
    staleTime: 30_000,
  })

  return (
    <div className="space-y-6">
      <PageHeading
        actions={<Button asChild><Link to="/admin/imports"><Play className="size-4" aria-hidden />Nueva importación</Link></Button>}
        description="Consulta disponibilidad, cumplimiento y calendario de las integraciones. La configuración sensible nunca se muestra en esta consola."
        title="Fuentes de importación"
      />
      <div className="flex gap-3 rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm text-amber-950 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100" role="status">
        <AlertTriangle className="mt-0.5 size-5 shrink-0" aria-hidden />
        <p><span className="font-semibold">Control editorial obligatorio.</span> Las fuentes sólo generan candidatos; un administrador debe revisarlos en Fondos antes de publicarlos.</p>
      </div>
      {sources.isError && <ErrorNotice retry={() => void sources.refetch()}>{importAdminErrorMessage(sources.error)}</ErrorNotice>}
      {sources.isPending && <p className="flex items-center gap-2 text-sm text-muted-foreground" role="status"><LoaderCircle className="size-4 animate-spin" aria-hidden />Cargando fuentes…</p>}
      {!sources.isPending && !sources.isError && sources.data?.length === 0 && (
        <Card><CardContent className="grid place-items-center p-10 text-center"><ServerCog className="size-8 text-muted-foreground" aria-hidden /><p className="mt-3 font-semibold">No hay fuentes configuradas</p></CardContent></Card>
      )}
      <div className="grid gap-4 xl:grid-cols-2">{sources.data?.map((source) => <SourceCard key={source.id} source={source} />)}</div>
    </div>
  )
}

function Counter({ label, value }: { label: string; value: number }) {
  return <div className="rounded-lg border bg-background p-3"><dt className="text-xs text-muted-foreground">{label}</dt><dd className="mt-1 text-xl font-bold">{value}</dd></div>
}

const dedupeLabels = {
  'not-evaluated': 'Sin evaluación de duplicidad',
  'possible-duplicate': 'Posible duplicado',
  'keep-separate': 'Conservar separado',
  'marked-duplicate': 'Duplicado confirmado',
  ignored: 'Sugerencia ignorada',
  'not-applicable': 'Sin comparación requerida',
  unknown: 'Estado de dedupe desconocido',
} as const

function canReviewDedupe(item: ImportRunItem) {
  return item.dedupeCandidateId !== null
}

function CandidateComparisonCard({
  label,
  preview,
}: {
  label: string
  preview: ImportDedupeComparison['candidate']
}) {
  return (
    <article className="rounded-xl border bg-background p-4">
      <p className="text-xs font-bold uppercase tracking-[0.14em] text-primary">{label}</p>
      <h4 className="mt-2 font-semibold">{preview.title}</h4>
      <dl className="mt-4 grid gap-2 text-sm">
        <div><dt className="text-muted-foreground">Organismo</dt><dd className="font-medium">{preview.sponsorName}</dd></div>
        <div><dt className="text-muted-foreground">Cierre</dt><dd className="font-medium">{formatCandidateDate(preview.closeDate)}</dd></div>
        <div><dt className="text-muted-foreground">Estado editorial</dt><dd className="font-medium">{preview.statusLabel}</dd></div>
      </dl>
      {preview.opportunityId && (
        <Button asChild className="mt-4" size="sm" variant="outline">
          <Link to={`/admin/funding/${preview.opportunityId}`}>Abrir ficha<ExternalLink className="size-3.5" aria-hidden /></Link>
        </Button>
      )}
    </article>
  )
}

export function AdminImportRunDetailPage() {
  const { id = '' } = useParams()
  const queryClient = useQueryClient()
  const [selectedDedupeCandidateId, setSelectedDedupeCandidateId] = useState<string | null>(null)
  const [pendingDecision, setPendingDecision] = useState<ImportDedupeDecision | null>(null)
  const [decisionReason, setDecisionReason] = useState('')
  const [decisionMessage, setDecisionMessage] = useState<string | null>(null)
  const [decisionMessageIsError, setDecisionMessageIsError] = useState(false)
  const run = useQuery({
    queryKey: ['admin', 'import-run', id],
    queryFn: ({ signal }) => adminImportApi.get(id, signal),
    enabled: Boolean(id),
    refetchInterval: (query) => query.state.data && isImportRunActive(query.state.data) ? 2_000 : false,
  })
  const comparison = useQuery({
    queryKey: ['admin', 'funding-duplicate-candidate', selectedDedupeCandidateId],
    queryFn: ({ signal }) => adminImportApi.getDedupe(selectedDedupeCandidateId!, signal),
    enabled: Boolean(selectedDedupeCandidateId),
    staleTime: 0,
  })
  const decideDedupe = useMutation({
    mutationFn: async (decision: ImportDedupeDecision) => {
      const current = comparison.data
      if (!current || !selectedDedupeCandidateId) throw new Error('dedupe-comparison-required')
      const reason = decisionReason.trim()
      if (reason.length < 3) throw new Error('dedupe-reason-required')
      if (/[\r\n]/.test(reason)) throw new Error('dedupe-reason-invalid-format')
      if (reason.length > 300) throw new Error('dedupe-reason-too-long')
      const canonicalOpportunityId = decision === 'mark-duplicate'
        ? current.existing.opportunityId ?? undefined
        : undefined
      if (decision === 'mark-duplicate' && !canonicalOpportunityId) {
        throw new Error('duplicate-target-required')
      }
      const payload = {
        decision,
        ...(canonicalOpportunityId ? { canonicalOpportunityId } : {}),
        reason,
      }
      return executeEditorialCommand(
        `funding-duplicate-candidate:${selectedDedupeCandidateId}:decision`,
        { ...payload, eTag: current.eTag },
        (idempotencyKey) => adminImportApi.decideDedupe(
          selectedDedupeCandidateId,
          payload,
          current.eTag,
          idempotencyKey,
        ),
      )
    },
    onSuccess: async (result) => {
      setPendingDecision(null)
      setDecisionReason('')
      setDecisionMessageIsError(result.isPublished)
      setDecisionMessage(result.isPublished
        ? 'El servicio reportó una publicación incompatible con esta decisión. Detén la revisión y solicita soporte.'
        : result.wasReplay
          ? 'La decisión ya estaba registrada. El candidato continúa en revisión editorial.'
          : 'Decisión guardada correctamente. Ningún fondo fue publicado.')
      await Promise.all([
        comparison.refetch(),
        queryClient.invalidateQueries({ queryKey: ['admin', 'import-run', id] }),
      ])
    },
    onError: async (error) => {
      setDecisionMessageIsError(true)
      if (error instanceof Error && error.message === 'dedupe-reason-required') {
        setDecisionMessage('Ingresa un motivo de al menos 3 caracteres.')
      } else if (error instanceof Error && error.message === 'dedupe-reason-invalid-format') {
        setDecisionMessage('El motivo debe escribirse en una sola línea.')
      } else if (error instanceof Error && error.message === 'dedupe-reason-too-long') {
        setDecisionMessage('El motivo debe tener como máximo 300 caracteres.')
      } else if (error instanceof Error && error.message === 'duplicate-target-required') {
        setDecisionMessage('No existe una ficha de destino válida para marcar como duplicado.')
      } else {
        setDecisionMessage(importAdminErrorMessage(error))
      }
      if (error instanceof ApiError && (error.response.status === 409 || error.response.status === 412)) {
        await comparison.refetch()
      }
    },
  })
  const itemCount = run.data?.items.length ?? 0
  const errorCount = run.data?.errors.length ?? 0

  if (run.isPending) {
    return <p className="flex items-center gap-2 text-sm text-muted-foreground" role="status"><LoaderCircle className="size-4 animate-spin" aria-hidden />Cargando detalle de importación…</p>
  }
  if (run.isError || !run.data) {
    return <ErrorNotice retry={() => void run.refetch()}>{importAdminErrorMessage(run.error)}</ErrorNotice>
  }

  const detail = run.data
  const unsafePublicationReported = detail.items.some((item) => item.isAutoPublished)
  return (
    <div className="space-y-6">
      <Button asChild size="sm" variant="ghost"><Link to="/admin/imports"><ArrowLeft className="size-4" aria-hidden />Volver a importaciones</Link></Button>
      <PageHeading
        actions={<StatusBadge status={detail.status} />}
        description={`${detail.sourceName} · ${triggerLabels[detail.triggerType] ?? 'Origen desconocido'} · creada ${formatDate(detail.createdAtUtc)}`}
        title={detail.keyword ? `Importación: ${detail.keyword}` : 'Detalle de importación'}
      />

      {isImportRunActive(detail) && (
        <p className="flex items-center gap-2 rounded-xl border bg-card p-4 text-sm" role="status">
          <RefreshCw className="size-4 animate-spin text-primary" aria-hidden />
          Esta ejecución sigue activa. El detalle se actualizará automáticamente.
        </p>
      )}
      {detail.status === 'failed' && (
        <ErrorNotice>La ejecución terminó con error{detail.lastErrorCode ? ` (${detail.lastErrorCode})` : ''}. Los candidatos ya procesados no se publicaron automáticamente.</ErrorNotice>
      )}
      {unsafePublicationReported && (
        <ErrorNotice>El servicio reportó una publicación automática incompatible con este flujo. Detén la revisión y solicita soporte administrativo.</ErrorNotice>
      )}

      <Card>
        <CardHeader><CardTitle>Progreso y resultados</CardTitle></CardHeader>
        <CardContent className="space-y-5">
          <RunProgress run={detail} />
          <dl className="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-6">
            <Counter label="Recuperados" value={detail.retrievedCount} />
            <Counter label="Nuevos" value={detail.createdCount} />
            <Counter label="Actualizados" value={detail.updatedCount} />
            <Counter label="Sin cambios" value={detail.unchangedCount} />
            <Counter label="A revisión" value={detail.stagedForReviewCount} />
            <Counter label="Fallidos" value={detail.failedCount} />
          </dl>
          <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg bg-muted/60 p-4 text-sm">
            <p><span className="font-semibold">Intentos:</span> {detail.attemptCount} · <span className="font-semibold">Máximo solicitado:</span> {detail.maximumResults}</p>
            {detail.stagedForReviewCount > 0 && <Button asChild size="sm"><Link to="/admin/funding"><Search className="size-4" aria-hidden />Revisar candidatos en Fondos</Link></Button>}
          </div>
          <p className="flex items-start gap-2 text-sm text-muted-foreground">
            <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-primary" aria-hidden />
            Los resultados quedan en revisión editorial; esta operación nunca los publica directamente.
          </p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle>Elementos ({itemCount})</CardTitle></CardHeader>
        <CardContent>
          {itemCount === 0
            ? <p className="text-sm text-muted-foreground">Aún no hay elementos procesados.</p>
            : <div className="grid gap-3">
                {detail.items.map((item) => (
                  <article className="flex flex-col justify-between gap-3 rounded-lg border bg-background p-3 lg:flex-row lg:items-center" key={item.itemId}>
                    <div className="min-w-0">
                      <p className="truncate font-mono text-sm font-semibold">{item.externalId}</p>
                      <p className="mt-1 text-xs text-muted-foreground">{itemStatusLabels[item.statusCode] ?? 'Estado desconocido'} · {item.outcomeCode ?? 'Sin resultado'} · {formatDate(item.completedAtUtc ?? item.createdAtUtc)}</p>
                      <p className="mt-1 text-xs"><span className="font-semibold">Dedupe:</span> {dedupeLabels[item.dedupeStatus]}{item.decisionCode ? ` · ${item.decisionCode}` : ''}{item.decisionReasonCode ? ` · ${item.decisionReasonCode}` : ''}</p>
                      {item.requiresEditorialReview && <p className="mt-1 text-xs text-primary">Requiere decisión editorial; no está publicado.</p>}
                    </div>
                    <div className="flex flex-wrap gap-2">
                      {canReviewDedupe(item) && (
                        <Button
                          onClick={() => {
                            setSelectedDedupeCandidateId(item.dedupeCandidateId)
                            setPendingDecision(null)
                            setDecisionMessage(null)
                            setDecisionMessageIsError(false)
                          }}
                          size="sm"
                          type="button"
                          variant="outline"
                        >
                          <GitCompareArrows className="size-3.5" aria-hidden />Comparar duplicado
                        </Button>
                      )}
                      {item.dedupeStatus === 'marked-duplicate' && item.duplicateOfOpportunityId && (
                        <Button asChild size="sm" variant="outline"><Link to={`/admin/funding/${item.duplicateOfOpportunityId}`}>Abrir coincidencia<ExternalLink className="size-3.5" aria-hidden /></Link></Button>
                      )}
                      {item.candidateOpportunityId && <Button asChild size="sm" variant="outline"><Link to={`/admin/funding/${item.candidateOpportunityId}`}>Abrir candidato<ExternalLink className="size-3.5" aria-hidden /></Link></Button>}
                    </div>
                  </article>
                ))}
              </div>}
        </CardContent>
      </Card>

      {selectedDedupeCandidateId && (
        <Card>
          <CardHeader>
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <CardTitle className="flex items-center gap-2"><GitCompareArrows className="size-5 text-primary" aria-hidden />Comparación de posible duplicado</CardTitle>
                <p className="mt-1 text-sm text-muted-foreground">Compara los datos normalizados y registra una decisión humana. Esta acción no publica ni elimina fondos.</p>
              </div>
              <Button onClick={() => setSelectedDedupeCandidateId(null)} size="sm" type="button" variant="ghost">Cerrar</Button>
            </div>
          </CardHeader>
          <CardContent className="space-y-4">
            {comparison.isPending && <p className="flex items-center gap-2 text-sm text-muted-foreground" role="status"><LoaderCircle className="size-4 animate-spin" aria-hidden />Cargando comparación segura…</p>}
            {comparison.isError && <ErrorNotice retry={() => void comparison.refetch()}>{importAdminErrorMessage(comparison.error)}</ErrorNotice>}
            {comparison.data && (
              <>
                <div className="grid gap-4 lg:grid-cols-2">
                  <CandidateComparisonCard label="Candidato importado" preview={comparison.data.candidate} />
                  <CandidateComparisonCard label="Posible coincidencia existente" preview={comparison.data.existing} />
                </div>
                <div className="rounded-lg border bg-background p-3 text-sm">
                  <p><span className="font-semibold">Tipo de coincidencia:</span> {comparison.data.matchKind}</p>
                  <p className="mt-1"><span className="font-semibold">Confianza de la sugerencia:</span> {comparison.data.confidence === null ? 'Sin información' : `${Math.round(comparison.data.confidence * 100)}%`}</p>
                  {comparison.data.evidenceSummary && <p className="mt-2 text-muted-foreground">{comparison.data.evidenceSummary}</p>}
                </div>
                <p className="flex items-start gap-2 rounded-lg bg-muted/60 p-3 text-sm">
                  <ShieldCheck className="mt-0.5 size-4 shrink-0 text-primary" aria-hidden />
                  Estado: {dedupeLabels[comparison.data.dedupeStatus]}. La decisión sólo organiza candidatos para la revisión editorial posterior.
                </p>
                {decisionMessage && <p className={decideDedupe.isError || decisionMessageIsError ? 'text-sm text-destructive' : 'text-sm text-primary'} role={decideDedupe.isError || decisionMessageIsError ? 'alert' : 'status'}>{decisionMessage}</p>}
                {!pendingDecision && comparison.data.canDecide && (
                  <div className="flex flex-wrap gap-2">
                    <Button disabled={decideDedupe.isPending} onClick={() => { setDecisionReason(''); setPendingDecision('keep-separate') }} type="button" variant="outline">Conservar como fondo separado</Button>
                    <Button disabled={decideDedupe.isPending || !comparison.data.existing.opportunityId} onClick={() => { setDecisionReason(''); setPendingDecision('mark-duplicate') }} type="button">Marcar como duplicado</Button>
                    <Button disabled={decideDedupe.isPending} onClick={() => { setDecisionReason(''); setPendingDecision('ignored') }} type="button" variant="ghost">Ignorar sugerencia</Button>
                  </div>
                )}
                {pendingDecision && (
                  <div aria-labelledby="dedupe-confirmation-title" className="space-y-4 rounded-xl border border-amber-300 bg-amber-50 p-4 text-amber-950 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100" role="dialog">
                    <div>
                      <h3 className="font-semibold" id="dedupe-confirmation-title">Confirmar decisión de duplicidad</h3>
                      <p className="mt-1 text-sm">Registrarás “{pendingDecision === 'mark-duplicate' ? 'Marcar como duplicado' : pendingDecision === 'ignored' ? 'Ignorar sugerencia' : 'Conservar separado'}”. El candidato seguirá sin publicar.</p>
                    </div>
                    <label className="grid gap-1.5 text-sm font-semibold">
                      Motivo obligatorio
                      <Input
                        maxLength={300}
                        onChange={(event) => setDecisionReason(event.target.value)}
                        placeholder="Explica brevemente la evidencia revisada."
                        value={decisionReason}
                      />
                    </label>
                    <div className="flex flex-wrap gap-2">
                      <Button disabled={decideDedupe.isPending} onClick={() => decideDedupe.mutate(pendingDecision)} type="button">
                        {decideDedupe.isPending && <LoaderCircle className="size-4 animate-spin" aria-hidden />}Confirmar decisión
                      </Button>
                      <Button disabled={decideDedupe.isPending} onClick={() => setPendingDecision(null)} type="button" variant="ghost">Cancelar</Button>
                    </div>
                  </div>
                )}
              </>
            )}
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader><CardTitle>Errores operacionales ({errorCount})</CardTitle></CardHeader>
        <CardContent>
          {errorCount === 0
            ? <p className="text-sm text-muted-foreground">No se registraron errores.</p>
            : <div className="grid gap-3">
                {detail.errors.map((error) => (
                  <article className="rounded-lg border border-destructive/25 bg-destructive/5 p-4" key={error.errorId}>
                    <div className="flex flex-wrap items-start justify-between gap-2">
                      <p className="font-semibold text-destructive">{error.code}</p>
                      <span className="text-xs text-muted-foreground">{formatDate(error.occurredAtUtc)}</span>
                    </div>
                    <p className="mt-2 text-sm">{error.message}</p>
                    <p className="mt-2 text-xs text-muted-foreground">Etapa: {error.stage} · {error.isRetryable ? 'Reintentable' : 'No reintentable'}</p>
                  </article>
                ))}
              </div>}
        </CardContent>
      </Card>
    </div>
  )
}
