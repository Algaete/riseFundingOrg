import { formatDateValue } from '@/i18n/formats'
import i18n from '@/i18n'
import { importOperationsErrorKey, operationsMessage, operationalLabel, operationStatus, type OperationsKey } from '@/i18n/operations-messages'
import { useTranslation } from 'react-i18next'
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
import { useImportPolling } from '@/features/imports/use-import-polling'
import {
  adminImportApi,
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
  queued: 'operations.queued',
  running: 'operations.running',
  completed: 'operations.completed',
  'completed-with-errors': 'operations.observations',
  failed: 'operations.failed',
  cancelled: 'operations.cancelled',
  unknown: 'operations.unknown',
}

const triggerLabels: Record<number, string> = {
  0: 'operations.manual',
  1: 'operations.scheduled',
  2: 'operations.retryTrigger',
}

const itemStatusLabels: Record<number, string> = {
  0: 'operations.pending',
  1: 'operations.itemProcessing',
  2: 'operations.itemCompleted',
  3: 'operations.itemFailed',
}

function formatDate(value: string | null) {
  if (!value) return i18n.t('operations.noInfo')
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return i18n.t('operations.noInfo')
  return formatDateValue(value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  })
}

function formatCandidateDate(value: string | null) {
  return formatDateValue(value, { dateStyle: 'medium', timeStyle: 'short' }, i18n.t('operations.noInfo'))
}

function StatusBadge({ status }: { status: ImportRunStatus }) {
  useTranslation()
  const color = status === 'completed'
    ? 'bg-emerald-100 text-emerald-900 dark:bg-emerald-950 dark:text-emerald-100'
    : status === 'running'
      ? 'bg-blue-100 text-blue-900 dark:bg-blue-950 dark:text-blue-100'
      : status === 'queued'
        ? 'bg-amber-100 text-amber-900 dark:bg-amber-950 dark:text-amber-100'
        : status === 'completed-with-errors'
          ? 'bg-orange-100 text-orange-900 dark:bg-orange-950 dark:text-orange-100'
          : status === 'failed'
            ? 'bg-destructive/10 text-foreground'
            : 'bg-muted text-muted-foreground'

  return (
    <span className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-semibold ${color}`}>
      {(status === 'queued' || status === 'running') && <LoaderCircle className="size-3.5 animate-spin" aria-hidden />}
      {operationStatus(statusLabels, status)}
    </span>
  )
}

function PageHeading({ actions, description, title }: { actions?: ReactNode; description: string; title: string }) {
  useTranslation()
  return (
    <div className="flex flex-col justify-between gap-4 lg:flex-row lg:items-start">
      <div>
        <p className="text-xs font-bold uppercase tracking-[0.18em] text-primary">{i18n.t('editorial.administration')}</p>
        <h1 className="mt-2 text-3xl font-bold tracking-tight">{title}</h1>
        <p className="mt-2 max-w-3xl text-sm text-muted-foreground">{description}</p>
      </div>
      {actions && <div className="flex flex-wrap gap-2">{actions}</div>}
    </div>
  )
}

function ErrorNotice({ children, retry }: { children: ReactNode; retry?: () => void }) {
  useTranslation()
  return (
    <div className="flex flex-col gap-3 rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm text-foreground sm:flex-row sm:items-center sm:justify-between" role="alert">
      <span className="flex items-start gap-2">
        <CircleAlert className="mt-0.5 size-4 shrink-0" aria-hidden />
        <span>{children}</span>
      </span>
      {retry && (
        <Button onClick={retry} size="sm" type="button" variant="outline">
          <RefreshCw className="size-4" aria-hidden /> {i18n.t('editorial.retry')}
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
  useTranslation()
  const processed = processedCount(run)
  const total = Math.max(run.retrievedCount, processed)
  const percentage = total > 0 ? Math.min(100, Math.round((processed / total) * 100)) : 0
  const active = isImportRunActive(run)
  return (
    <div className="space-y-1.5">
      <div className="flex justify-between text-xs text-muted-foreground">
        <span>{i18n.t('adminImports.processed', { count: processed })}</span>
        <span>{total > 0 ? `${percentage}%` : active ? i18n.t('adminImports.waiting') : i18n.t('adminImports.noResults')}</span>
      </div>
      <div
        aria-label={i18n.t('adminImports.progress')}
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
  useTranslation()
  return (
    <article className="min-w-0 rounded-xl border bg-background p-4">
      <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-start">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <StatusBadge status={run.status} />
            <span className="text-xs font-medium text-muted-foreground">{operationStatus(triggerLabels, run.triggerType)}</span>
          </div>
          <h3 className="mt-3 truncate font-semibold">{run.sourceName}</h3>
          <p className="mt-1 truncate text-sm text-muted-foreground">
            {run.keyword ? i18n.t('adminImports.search', { keyword: run.keyword }) : i18n.t('adminImports.noKeyword')} · {i18n.t('adminImports.created', { date: formatDate(run.createdAtUtc) })}
          </p>
        </div>
        <Button asChild size="sm" variant="outline">
          <Link to={`/admin/imports/${run.runId}`}>{i18n.t('operations.detail')}</Link>
        </Button>
      </div>
      <div className="mt-4">
        <RunProgress run={run} />
      </div>
      <dl className="mt-4 grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
        <div><dt className="text-muted-foreground">{i18n.t('adminImports.retrieved')}</dt><dd className="font-semibold">{run.retrievedCount}</dd></div>
        <div><dt className="text-muted-foreground">{i18n.t('adminImports.new')}</dt><dd className="font-semibold">{run.createdCount}</dd></div>
        <div><dt className="text-muted-foreground">{i18n.t('adminImports.review')}</dt><dd className="font-semibold">{run.stagedForReviewCount}</dd></div>
        <div><dt className="text-muted-foreground">{i18n.t('adminImports.failedItems')}</dt><dd className="font-semibold">{run.failedCount}</dd></div>
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
  useTranslation()
  const navigate = useNavigate()
  const polling = useImportPolling('list')
  const queryClient = useQueryClient()
  const [searchParams, setSearchParams] = useSearchParams()
  const [keyword, setKeyword] = useState('nonprofit')
  const [maximumResults, setMaximumResults] = useState('25')
  const [selectedSourceId, setSelectedSourceId] = useState('')
  const [formMessage, setFormMessage] = useState<OperationsKey | null>(null)
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
    refetchInterval: (query) => polling.enabled && shouldPollImportRuns(query.state.data?.items ?? []) ? 3_000 : false,
    refetchOnWindowFocus: false,
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
        ? 'adminImports.replayed'
        : 'adminImports.queuedMessage')
      await queryClient.invalidateQueries({ queryKey: ['admin', 'import-runs'] })
      void navigate(`/admin/imports/${accepted.runId}`)
    },
    onError: (error) => {
      if (error instanceof Error && error.message === 'source-required') {
        setFormMessage('adminImports.sourceRequired')
      } else if (error instanceof Error && error.message === 'keyword-invalid') {
        setFormMessage('adminImports.keywordInvalid')
      } else if (error instanceof Error && error.message === 'maximum-invalid') {
        setFormMessage('adminImports.maximumInvalid')
      } else {
        setFormMessage(importOperationsErrorKey(error))
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
  const isPolling = polling.enabled && shouldPollImportRuns(runs.data?.items ?? [])

  return (
    <div className="min-w-0 space-y-6">
      <PageHeading
        actions={(
          <>
            <Button asChild variant="outline"><Link to="/admin/sources"><ServerCog className="size-4" aria-hidden />{i18n.t('adminImports.viewSources')}</Link></Button>
            <Button asChild variant="outline"><Link to="/admin/imports/upload-document"><FileUp className="size-4" aria-hidden />{i18n.t('adminImports.safePdf')}</Link></Button>
          </>
        )}
        description={i18n.t('adminImports.intro')}
        title={i18n.t('adminImports.title')}
      />

      <Card>
        <CardHeader>
          <div className="flex items-start gap-3">
            <DatabaseZap className="mt-0.5 size-5 text-primary" aria-hidden />
            <div>
              <CardTitle>{i18n.t('adminImports.grantsTitle')}</CardTitle>
              <p className="mt-1 text-sm text-muted-foreground">{i18n.t('adminImports.backgroundHelp')}</p>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          {sources.isError && <ErrorNotice retry={() => void sources.refetch()}>{operationsMessage(importOperationsErrorKey(sources.error))}</ErrorNotice>}
          {!sources.isPending && !sources.isError && grantsSources.length === 0 && (
            <ErrorNotice>{i18n.t('adminImports.noEnabledSource')}</ErrorNotice>
          )}
          <form className="grid gap-4 xl:grid-cols-[minmax(12rem,1fr)_minmax(14rem,2fr)_10rem_auto] xl:items-end" noValidate onSubmit={submit}>
            <label className="grid gap-1.5 text-sm font-semibold">
              {i18n.t('operations.source')}
              <select
                className={inputClass}
                disabled={sources.isPending || grantsSources.length === 0 || createRun.isPending}
                onChange={(event) => setSelectedSourceId(event.target.value)}
                value={selectedSourceId}
              >
                <option value="">{i18n.t('adminFunding.chooseSource')}</option>
                {grantsSources.map((source) => <option key={source.id} value={source.id}>{source.name}</option>)}
              </select>
            </label>
            <label className="grid gap-1.5 text-sm font-semibold">
              {i18n.t('adminImports.keyword')}
              <Input
                autoComplete="off"
                disabled={createRun.isPending}
                maxLength={100}
                onChange={(event) => setKeyword(event.target.value)}
                placeholder={i18n.t('adminImports.keywordPlaceholder')}
                value={keyword}
              />
            </label>
            <label className="grid gap-1.5 text-sm font-semibold">
              {i18n.t('adminImports.maximum')}
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
              {createRun.isPending ? i18n.t('operations.sending') : i18n.t('adminImports.start')}
            </Button>
          </form>
          {formMessage && <p className="mt-4 text-sm" role={createRun.isError ? 'alert' : 'status'}>{operationsMessage(formMessage)}</p>}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <div className="flex flex-col justify-between gap-4 lg:flex-row lg:items-end">
            <div>
              <CardTitle>{i18n.t('adminImports.recentRuns')}</CardTitle>
              <p className="mt-1 flex items-center gap-2 text-sm text-muted-foreground" role="status">
                {isPolling && <><RefreshCw className="size-3.5 animate-spin" aria-hidden />{i18n.t('adminImports.polling')}</>}
                {!isPolling && i18n.t(polling.enabled ? 'adminImports.pollingHelp' : 'adminImports.pollingPaused')}
              </p>
              <Button className="mt-2" size="sm" type="button" variant="outline"
                onClick={() => { polling.restart(); void runs.refetch() }} disabled={runs.isFetching}>
                <RefreshCw className="size-4" aria-hidden />{i18n.t('adminImports.refresh')}
              </Button>
            </div>
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="grid gap-1 text-xs font-semibold">
                {i18n.t('operations.source')}
                <select className={inputClass} onChange={(event) => updateFilter('sourceId', event.target.value)} value={sourceId ?? ''}>
                  <option value="">{i18n.t('operations.allFeminine')}</option>
                  {(sources.data ?? []).map((source) => <option key={source.id} value={source.id}>{source.name}</option>)}
                </select>
              </label>
              <label className="grid gap-1 text-xs font-semibold">
                {i18n.t('operations.status')}
                <select className={inputClass} onChange={(event) => updateFilter('status', event.target.value)} value={status ?? ''}>
                  <option value="">{i18n.t('operations.all')}</option>
                  <option value="0">{i18n.t('operations.queued')}</option><option value="1">{i18n.t('operations.running')}</option><option value="2">{i18n.t('operations.completed')}</option>
                  <option value="3">{i18n.t('adminImports.withObservations')}</option><option value="4">{i18n.t('operations.failed')}</option><option value="5">{i18n.t('operations.cancelled')}</option>
                </select>
              </label>
            </div>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {runs.isError && <ErrorNotice retry={() => void runs.refetch()}>{operationsMessage(importOperationsErrorKey(runs.error))}</ErrorNotice>}
          {runs.isPending && (
            <p className="flex items-center gap-2 text-sm text-muted-foreground" role="status"><LoaderCircle className="size-4 animate-spin" aria-hidden />{i18n.t('adminImports.loading')}</p>
          )}
          {!runs.isPending && !runs.isError && runs.data?.items.length === 0 && (
            <div className="grid place-items-center rounded-xl border border-dashed p-10 text-center">
              <FileSearch className="size-8 text-muted-foreground" aria-hidden />
              <p className="mt-3 font-semibold">{i18n.t('adminImports.empty')}</p>
              <p className="mt-1 text-sm text-muted-foreground">{i18n.t('adminImports.emptyHelp')}</p>
            </div>
          )}
          <div className="grid gap-3">{runs.data?.items.map((run) => <RunCard key={run.runId} run={run} />)}</div>
          {(runs.data?.totalCount ?? 0) > 0 && (
            <div className="flex flex-col items-center justify-between gap-3 border-t pt-4 sm:flex-row">
              <p className="text-sm text-muted-foreground">{i18n.t('adminImports.pagination', { page, total: totalPages, count: runs.data?.totalCount ?? 0 })}</p>
              <div className="flex gap-2">
                <Button disabled={page <= 1 || runs.isFetching} onClick={() => changePage(page - 1)} size="sm" type="button" variant="outline"><ChevronLeft className="size-4" aria-hidden />{i18n.t('editorial.previous')}</Button>
                <Button disabled={page >= totalPages || runs.isFetching} onClick={() => changePage(page + 1)} size="sm" type="button" variant="outline">{i18n.t('editorial.next')}<ChevronRight className="size-4" aria-hidden /></Button>
              </div>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

function SourceCard({ source }: { source: AdminFundingSourceView }) {
  useTranslation()
  const requestPolicy = source.rateLimitPerMinute !== null
    ? i18n.t('adminImports.rate', { count: source.rateLimitPerMinute })
    : source.minimumRequestIntervalSeconds !== null
      ? i18n.t('adminImports.interval', { seconds: source.minimumRequestIntervalSeconds })
      : i18n.t('adminImports.noPublicInfo')
  return (
    <Card className="flex h-full flex-col">
      <CardHeader>
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="text-xs font-semibold uppercase tracking-wide text-primary">{source.providerCode || i18n.t('adminImports.sourceFallback')}</p>
            <CardTitle className="mt-1 truncate">{source.name}</CardTitle>
            {source.baseUrl && <p className="mt-1 truncate text-xs text-muted-foreground">{source.baseUrl}</p>}
          </div>
          <span className={`rounded-full px-2.5 py-1 text-xs font-semibold ${source.isEnabled ? 'bg-emerald-100 text-emerald-900 dark:bg-emerald-950 dark:text-emerald-100' : 'bg-muted text-muted-foreground'}`}>
            {source.isEnabled ? i18n.t('operations.enabled') : i18n.t('operations.paused')}
          </span>
        </div>
      </CardHeader>
      <CardContent className="flex flex-1 flex-col justify-between gap-5">
        <dl className="grid gap-3 text-sm sm:grid-cols-2">
          <div><dt className="text-muted-foreground">{i18n.t('adminImports.operationalStatus')}</dt><dd className="font-semibold">{operationalLabel(source.operationalStatus)}</dd></div>
          <div><dt className="text-muted-foreground">{i18n.t('adminImports.compliance')}</dt><dd className="font-semibold">{operationalLabel(source.complianceStatus)}</dd></div>
          <div className="sm:col-span-2">
            <dt className="text-muted-foreground">{i18n.t('adminImports.governance')}</dt>
            <dd className="font-semibold">
              {source.acquisitionReady === true
                ? i18n.t('adminImports.ready')
                : source.acquisitionReady === false ? i18n.t('adminImports.blocked') : i18n.t('adminImports.notEvaluated')}
            </dd>
          </div>
          <div>
            <dt className="flex items-center gap-1.5 text-muted-foreground"><BookOpen className="size-3.5" aria-hidden />{i18n.t('adminImports.license')}</dt>
            <dd className="font-semibold">
              {source.licenseUrl
                ? <a className="underline underline-offset-2" href={source.licenseUrl} rel="noreferrer" target="_blank">{source.licenseName}<ExternalLink className="ml-1 inline size-3" aria-hidden /></a>
                : source.licenseName === 'No informada' ? operationalLabel(source.licenseName) : source.licenseName}
            </dd>
            <dd className="text-xs text-muted-foreground">{operationalLabel(source.licenseStatus)}</dd>
          </div>
          <div><dt className="flex items-center gap-1.5 text-muted-foreground"><ShieldCheck className="size-3.5" aria-hidden />{i18n.t('adminImports.allowlist')}</dt><dd className="font-semibold">{operationalLabel(source.allowlistStatus)}{source.allowedHostCount !== null && source.allowedHostCount > 0 ? i18n.t(source.allowedHostCount === 1 ? 'adminImports.host' : 'adminImports.hosts', { count: source.allowedHostCount }) : ''}</dd></div>
          <div><dt className="flex items-center gap-1.5 text-muted-foreground"><Gauge className="size-3.5" aria-hidden />{i18n.t('adminImports.queryLimit')}</dt><dd className="font-semibold">{requestPolicy}</dd></div>
          <div><dt className="flex items-center gap-1.5 text-muted-foreground"><Globe2 className="size-3.5" aria-hidden />{i18n.t('adminImports.robots')}</dt><dd className="font-semibold">{operationalLabel(source.robotsPolicyStatus)}</dd><dd className="text-xs text-muted-foreground">{i18n.t('adminImports.reviewed', { date: formatDate(source.robotsReviewedAtUtc) })}</dd></div>
          {source.isRssProvider && (
            <div className="sm:col-span-2">
              <dt className="text-muted-foreground">{i18n.t('adminImports.rss')}</dt>
              <dd className="font-semibold">{i18n.t('adminImports.rssConfigured')}{source.rssFeedHost ? ` · ${source.rssFeedHost}` : ''}</dd>
              <dd className="text-xs text-muted-foreground">{i18n.t('adminImports.rssHelp')}</dd>
            </div>
          )}
          <div><dt className="text-muted-foreground">{i18n.t('adminImports.lastSuccess')}</dt><dd className="font-semibold">{formatDate(source.lastSuccessfulRunAtUtc)}</dd></div>
          <div><dt className="text-muted-foreground">{i18n.t('adminImports.nextRun')}</dt><dd className="font-semibold">{formatDate(source.nextScheduledRunAtUtc)}</dd></div>
        </dl>
        <div className="flex flex-wrap gap-2">
          <Button asChild size="sm" variant="outline"><Link to={`/admin/imports?sourceId=${source.id}`}><Clock3 className="size-4" aria-hidden />{i18n.t('adminImports.viewRuns')}</Link></Button>
          {source.isGrantsGov && source.isEnabled && (
            <Button asChild size="sm"><Link to={`/admin/imports?sourceId=${source.id}`}><Play className="size-4" aria-hidden />{i18n.t('adminImports.create')}</Link></Button>
          )}
        </div>
      </CardContent>
    </Card>
  )
}

export function AdminImportSourcesPage() {
  useTranslation()
  const sources = useQuery({
    queryKey: ['admin', 'import-sources'],
    queryFn: ({ signal }) => adminImportApi.listSources(signal),
    staleTime: 30_000,
  })

  return (
    <div className="min-w-0 space-y-6">
      <PageHeading
        actions={<Button asChild><Link to="/admin/imports"><Play className="size-4" aria-hidden />{i18n.t('adminImports.newImport')}</Link></Button>}
        description={i18n.t('adminImports.sourcesIntro')}
        title={i18n.t('adminImports.sourcesTitle')}
      />
      <div className="flex gap-3 rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm text-amber-950 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100" role="status">
        <AlertTriangle className="mt-0.5 size-5 shrink-0" aria-hidden />
        <p><span className="font-semibold">{i18n.t('adminImports.mandatoryReview')}</span> {i18n.t('adminImports.mandatoryReviewHelp')}</p>
      </div>
      {sources.isError && <ErrorNotice retry={() => void sources.refetch()}>{operationsMessage(importOperationsErrorKey(sources.error))}</ErrorNotice>}
      {sources.isPending && <p className="flex items-center gap-2 text-sm text-muted-foreground" role="status"><LoaderCircle className="size-4 animate-spin" aria-hidden />{i18n.t('adminImports.loadingSources')}</p>}
      {!sources.isPending && !sources.isError && sources.data?.length === 0 && (
        <Card><CardContent className="grid place-items-center p-10 text-center"><ServerCog className="size-8 text-muted-foreground" aria-hidden /><p className="mt-3 font-semibold">{i18n.t('adminImports.sourcesEmpty')}</p></CardContent></Card>
      )}
      <div className="grid gap-4 xl:grid-cols-2">{sources.data?.map((source) => <SourceCard key={source.id} source={source} />)}</div>
    </div>
  )
}

function Counter({ label, value }: { label: string; value: number }) {
  useTranslation()
  return <div className="rounded-lg border bg-background p-3"><dt className="text-xs text-muted-foreground">{label}</dt><dd className="mt-1 text-xl font-bold">{value}</dd></div>
}

const dedupeLabels = {
  'not-evaluated': 'adminImports.dedupeNotEvaluated',
  'possible-duplicate': 'adminImports.possibleDuplicate',
  'keep-separate': 'adminImports.keepSeparate',
  'marked-duplicate': 'adminImports.confirmedDuplicate',
  ignored: 'adminImports.ignored',
  'not-applicable': 'adminImports.notApplicable',
  unknown: 'adminImports.unknownDedupe',
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
  useTranslation()
  return (
    <article className="min-w-0 rounded-xl border bg-background p-4">
      <p className="text-xs font-bold uppercase tracking-[0.14em] text-primary">{label}</p>
      <h4 className="mt-2 font-semibold">{preview.title}</h4>
      <dl className="mt-4 grid gap-2 text-sm">
        <div><dt className="text-muted-foreground">{i18n.t('adminImports.sponsor')}</dt><dd className="font-medium">{preview.sponsorName}</dd></div>
        <div><dt className="text-muted-foreground">{i18n.t('adminImports.closing')}</dt><dd className="font-medium">{formatCandidateDate(preview.closeDate)}</dd></div>
        <div><dt className="text-muted-foreground">{i18n.t('adminImports.editorialStatus')}</dt><dd className="font-medium">{operationalLabel(preview.statusLabel)}</dd></div>
      </dl>
      {preview.opportunityId && (
        <Button asChild className="mt-4" size="sm" variant="outline">
          <Link to={`/admin/funding/${preview.opportunityId}`}>{i18n.t('adminImports.openRecord')}<ExternalLink className="size-3.5" aria-hidden /></Link>
        </Button>
      )}
    </article>
  )
}

export function AdminImportRunDetailPage() {
  useTranslation()
  const { id = '' } = useParams()
  const polling = useImportPolling(id)
  const queryClient = useQueryClient()
  const [selectedDedupeCandidateId, setSelectedDedupeCandidateId] = useState<string | null>(null)
  const [pendingDecision, setPendingDecision] = useState<ImportDedupeDecision | null>(null)
  const [decisionReason, setDecisionReason] = useState('')
  const [decisionMessage, setDecisionMessage] = useState<OperationsKey | null>(null)
  const [decisionMessageIsError, setDecisionMessageIsError] = useState(false)
  const run = useQuery({
    queryKey: ['admin', 'import-run', id],
    queryFn: ({ signal }) => adminImportApi.get(id, signal),
    enabled: Boolean(id),
    refetchInterval: (query) => polling.enabled && query.state.data && isImportRunActive(query.state.data) ? 2_000 : false,
    refetchOnWindowFocus: false,
  })
  const dispatchRun = useMutation({
    mutationKey: ['admin', 'import-dispatch', id],
    mutationFn: () => adminImportApi.dispatch(id),
    onSuccess: async () => {
      polling.restart()
      await queryClient.invalidateQueries({ queryKey: ['admin', 'import-run', id] })
      await queryClient.invalidateQueries({ queryKey: ['admin', 'import-runs'] })
    },
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
        ? 'adminImports.unexpectedPublication'
        : result.wasReplay
          ? 'adminImports.decisionReplay'
          : 'adminImports.decisionSaved')
      await Promise.all([
        comparison.refetch(),
        queryClient.invalidateQueries({ queryKey: ['admin', 'import-run', id] }),
      ])
    },
    onError: async (error) => {
      setDecisionMessageIsError(true)
      if (error instanceof Error && error.message === 'dedupe-reason-required') {
        setDecisionMessage('adminImports.reasonRequired')
      } else if (error instanceof Error && error.message === 'dedupe-reason-invalid-format') {
        setDecisionMessage('adminImports.reasonLine')
      } else if (error instanceof Error && error.message === 'dedupe-reason-too-long') {
        setDecisionMessage('adminImports.reasonLength')
      } else if (error instanceof Error && error.message === 'duplicate-target-required') {
        setDecisionMessage('adminImports.noTarget')
      } else {
        setDecisionMessage(importOperationsErrorKey(error))
      }
      if (error instanceof ApiError && (error.response.status === 409 || error.response.status === 412)) {
        await comparison.refetch()
      }
    },
  })
  const itemCount = run.data?.items.length ?? 0
  const errorCount = run.data?.errors.length ?? 0

  if (run.isPending) {
    return <p className="flex items-center gap-2 text-sm text-muted-foreground" role="status"><LoaderCircle className="size-4 animate-spin" aria-hidden />{i18n.t('adminImports.loadingDetail')}</p>
  }
  if (run.isError || !run.data) {
    return <ErrorNotice retry={() => void run.refetch()}>{operationsMessage(importOperationsErrorKey(run.error))}</ErrorNotice>
  }

  const detail = run.data
  const unsafePublicationReported = detail.items.some((item) => item.isAutoPublished)
  return (
    <div className="min-w-0 space-y-6">
      <Button asChild size="sm" variant="ghost"><Link to="/admin/imports"><ArrowLeft className="size-4" aria-hidden />{i18n.t('adminImports.back')}</Link></Button>
      <PageHeading
        actions={(
          <>
            <StatusBadge status={detail.status} />
            <Button size="sm" type="button" variant="outline" disabled={run.isFetching}
              onClick={() => { polling.restart(); void run.refetch() }}>
              <RefreshCw className="size-4" aria-hidden />{i18n.t('adminImports.refresh')}
            </Button>
            {isImportRunActive(detail) && (
              <Button size="sm" type="button" variant="outline" disabled={dispatchRun.isPending}
                onClick={() => dispatchRun.mutate()}>
                <Play className="size-4" aria-hidden />{i18n.t('adminImports.dispatch')}
              </Button>
            )}
          </>
        )}
        description={`${detail.sourceName} · ${operationStatus(triggerLabels, detail.triggerType)} · ${i18n.t('adminImports.created', { date: formatDate(detail.createdAtUtc) })}`}
        title={detail.keyword ? i18n.t('adminImports.importOf', { keyword: detail.keyword }) : i18n.t('adminImports.detailTitle')}
      />

      {isImportRunActive(detail) && (
        <p className="flex items-center gap-2 rounded-xl border bg-card p-4 text-sm" role="status">
          <RefreshCw className={`size-4 text-primary ${polling.enabled ? 'animate-spin' : ''}`} aria-hidden />
          {i18n.t(polling.enabled ? 'adminImports.activeRun' : 'adminImports.pollingPaused')}
        </p>
      )}
      {dispatchRun.isSuccess && <p role="status" className="text-sm">{i18n.t('adminImports.dispatched')}</p>}
      {dispatchRun.isError && <ErrorNotice>{operationsMessage(importOperationsErrorKey(dispatchRun.error))}</ErrorNotice>}
      {detail.status === 'failed' && (
        <ErrorNotice>{i18n.t('adminImports.failedRun', { code: detail.lastErrorCode ? ` (${detail.lastErrorCode})` : '' })}</ErrorNotice>
      )}
      {unsafePublicationReported && (
        <ErrorNotice>{i18n.t('adminImports.autoPublication')}</ErrorNotice>
      )}

      <Card>
        <CardHeader><CardTitle>{i18n.t('adminImports.results')}</CardTitle></CardHeader>
        <CardContent className="space-y-5">
          <RunProgress run={detail} />
          <dl className="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-6">
            <Counter label={i18n.t('adminImports.retrieved')} value={detail.retrievedCount} />
            <Counter label={i18n.t('adminImports.new')} value={detail.createdCount} />
            <Counter label={i18n.t('adminImports.updated')} value={detail.updatedCount} />
            <Counter label={i18n.t('adminImports.unchanged')} value={detail.unchangedCount} />
            <Counter label={i18n.t('adminImports.review')} value={detail.stagedForReviewCount} />
            <Counter label={i18n.t('adminImports.failedItems')} value={detail.failedCount} />
          </dl>
          <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg bg-muted/60 p-4 text-sm">
            <p><span className="font-semibold">{i18n.t('adminImports.attempts')}</span> {detail.attemptCount} · <span className="font-semibold">{i18n.t('adminImports.requestedMaximum')}</span> {detail.maximumResults}</p>
            {detail.stagedForReviewCount > 0 && <Button asChild size="sm"><Link to="/admin/funding"><Search className="size-4" aria-hidden />{i18n.t('adminImports.reviewCandidates')}</Link></Button>}
          </div>
          <p className="flex items-start gap-2 text-sm text-muted-foreground">
            <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-primary" aria-hidden />
            {i18n.t('adminImports.noPublication')}
          </p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle>{i18n.t('adminImports.items', { count: itemCount })}</CardTitle></CardHeader>
        <CardContent>
          {itemCount === 0
            ? <p className="text-sm text-muted-foreground">{i18n.t('adminImports.noItems')}</p>
            : <div className="grid gap-3">
                {detail.items.map((item) => (
                  <article className="flex flex-col justify-between gap-3 rounded-lg border bg-background p-3 lg:flex-row lg:items-center" key={item.itemId}>
                    <div className="min-w-0">
                      <p className="truncate font-mono text-sm font-semibold">{item.externalId}</p>
                      <p className="mt-1 text-xs text-muted-foreground">{operationStatus(itemStatusLabels, item.statusCode)} · {item.outcomeCode ?? i18n.t('adminImports.noOutcome')} · {formatDate(item.completedAtUtc ?? item.createdAtUtc)}</p>
                      <p className="mt-1 text-xs"><span className="font-semibold">{i18n.t('adminImports.dedupe')}</span> {operationStatus(dedupeLabels, item.dedupeStatus)}{item.decisionCode ? ` · ${item.decisionCode}` : ''}{item.decisionReasonCode ? ` · ${item.decisionReasonCode}` : ''}</p>
                      {item.requiresEditorialReview && <p className="mt-1 text-xs text-primary">{i18n.t('adminImports.requiresReview')}</p>}
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
                          <GitCompareArrows className="size-3.5" aria-hidden />{i18n.t('adminImports.compare')}
                        </Button>
                      )}
                      {item.dedupeStatus === 'marked-duplicate' && item.duplicateOfOpportunityId && (
                        <Button asChild size="sm" variant="outline"><Link to={`/admin/funding/${item.duplicateOfOpportunityId}`}>{i18n.t('adminImports.openMatch')}<ExternalLink className="size-3.5" aria-hidden /></Link></Button>
                      )}
                      {item.candidateOpportunityId && <Button asChild size="sm" variant="outline"><Link to={`/admin/funding/${item.candidateOpportunityId}`}>{i18n.t('adminImports.openCandidate')}<ExternalLink className="size-3.5" aria-hidden /></Link></Button>}
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
                <CardTitle className="flex items-center gap-2"><GitCompareArrows className="size-5 text-primary" aria-hidden />{i18n.t('adminImports.comparison')}</CardTitle>
                <p className="mt-1 text-sm text-muted-foreground">{i18n.t('adminImports.comparisonHelp')}</p>
              </div>
              <Button onClick={() => setSelectedDedupeCandidateId(null)} size="sm" type="button" variant="ghost">{i18n.t('operations.close')}</Button>
            </div>
          </CardHeader>
          <CardContent className="space-y-4">
            {comparison.isPending && <p className="flex items-center gap-2 text-sm text-muted-foreground" role="status"><LoaderCircle className="size-4 animate-spin" aria-hidden />{i18n.t('adminImports.loadingComparison')}</p>}
            {comparison.isError && <ErrorNotice retry={() => void comparison.refetch()}>{operationsMessage(importOperationsErrorKey(comparison.error))}</ErrorNotice>}
            {comparison.data && (
              <>
                <div className="grid gap-4 lg:grid-cols-2">
                  <CandidateComparisonCard label={i18n.t('adminImports.candidate')} preview={comparison.data.candidate} />
                  <CandidateComparisonCard label={i18n.t('adminImports.existing')} preview={comparison.data.existing} />
                </div>
                <div className="rounded-lg border bg-background p-3 text-sm">
                  <p><span className="font-semibold">{i18n.t('adminImports.matchType')}</span> {operationalLabel(comparison.data.matchKind)}</p>
                  <p className="mt-1"><span className="font-semibold">{i18n.t('adminImports.confidence')}</span> {comparison.data.confidence === null ? i18n.t('operations.noInfo') : `${Math.round(comparison.data.confidence * 100)}%`}</p>
                  {comparison.data.evidenceSummary && <p className="mt-2 text-muted-foreground">{comparison.data.evidenceSummary}</p>}
                </div>
                <p className="flex items-start gap-2 rounded-lg bg-muted/60 p-3 text-sm">
                  <ShieldCheck className="mt-0.5 size-4 shrink-0 text-primary" aria-hidden />
                  {i18n.t('adminImports.dedupeHelp', { status: operationStatus(dedupeLabels, comparison.data.dedupeStatus) })}
                </p>
                {decisionMessage && <p className={decideDedupe.isError || decisionMessageIsError ? 'text-sm text-foreground' : 'text-sm text-primary'} role={decideDedupe.isError || decisionMessageIsError ? 'alert' : 'status'}>{operationsMessage(decisionMessage)}</p>}
                {!pendingDecision && comparison.data.canDecide && (
                  <div className="flex flex-wrap gap-2">
                    <Button disabled={decideDedupe.isPending} onClick={() => { setDecisionReason(''); setPendingDecision('keep-separate') }} type="button" variant="outline">{i18n.t('adminImports.keepSeparateAction')}</Button>
                    <Button disabled={decideDedupe.isPending || !comparison.data.existing.opportunityId} onClick={() => { setDecisionReason(''); setPendingDecision('mark-duplicate') }} type="button">{i18n.t('adminImports.markDuplicate')}</Button>
                    <Button disabled={decideDedupe.isPending} onClick={() => { setDecisionReason(''); setPendingDecision('ignored') }} type="button" variant="ghost">{i18n.t('adminImports.ignore')}</Button>
                  </div>
                )}
                {pendingDecision && (
                  <div aria-labelledby="dedupe-confirmation-title" className="space-y-4 rounded-xl border border-amber-300 bg-amber-50 p-4 text-amber-950 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100" role="dialog">
                    <div>
                      <h3 className="font-semibold" id="dedupe-confirmation-title">{i18n.t('adminImports.confirmTitle')}</h3>
                      <p className="mt-1 text-sm">{i18n.t('adminImports.confirmHelp', { decision: pendingDecision === 'mark-duplicate' ? i18n.t('adminImports.markDuplicate') : pendingDecision === 'ignored' ? i18n.t('adminImports.ignore') : i18n.t('adminImports.keepSeparate') })}</p>
                    </div>
                    <label className="grid gap-1.5 text-sm font-semibold">
                      {i18n.t('adminImports.reason')}
                      <Input
                        maxLength={300}
                        onChange={(event) => setDecisionReason(event.target.value)}
                        placeholder={i18n.t('adminImports.reasonPlaceholder')}
                        value={decisionReason}
                      />
                    </label>
                    <div className="flex flex-wrap gap-2">
                      <Button disabled={decideDedupe.isPending} onClick={() => decideDedupe.mutate(pendingDecision)} type="button">
                        {decideDedupe.isPending && <LoaderCircle className="size-4 animate-spin" aria-hidden />}{i18n.t('adminImports.confirm')}
                      </Button>
                      <Button disabled={decideDedupe.isPending} onClick={() => setPendingDecision(null)} type="button" variant="ghost">{i18n.t('editorial.cancel')}</Button>
                    </div>
                  </div>
                )}
              </>
            )}
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader><CardTitle>{i18n.t('adminImports.errors', { count: errorCount })}</CardTitle></CardHeader>
        <CardContent>
          {errorCount === 0
            ? <p className="text-sm text-muted-foreground">{i18n.t('adminImports.noErrors')}</p>
            : <div className="grid gap-3">
                {detail.errors.map((error) => (
                  <article className="rounded-lg border border-destructive/25 bg-destructive/5 p-4" key={error.errorId}>
                    <div className="flex flex-wrap items-start justify-between gap-2">
                      <p className="font-semibold text-foreground">{error.code}</p>
                      <span className="text-xs text-muted-foreground">{formatDate(error.occurredAtUtc)}</span>
                    </div>
                    <p className="mt-2 text-sm">{error.message}</p>
                    <p className="mt-2 text-xs text-muted-foreground">{i18n.t('adminImports.stage', { stage: error.stage })} · {error.isRetryable ? i18n.t('operations.retryable') : i18n.t('operations.notRetryable')}</p>
                  </article>
                ))}
              </div>}
        </CardContent>
      </Card>
    </div>
  )
}
