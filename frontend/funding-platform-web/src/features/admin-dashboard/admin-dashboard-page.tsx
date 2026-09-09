import { formatDateValue } from '@/i18n/formats'
import { workspaceLocale } from '@/i18n/workspace-messages'
import i18n from '@/i18n'
import { operationStatus } from '@/i18n/operations-messages'
import { useTranslation } from 'react-i18next'
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
import { adminOrganizationsApi } from '@/features/admin-organizations/admin-organizations-api'
import { adminErrorsApi } from '@/features/admin-errors/admin-errors-api'
import {
  adminFundersApi,
  adminFundingOpportunitiesApi,
} from '@/features/funding/admin-funding-api'
import { adminImportApi, type ImportRunStatus } from '@/features/imports/admin-import-api'
import { projectReviewApi } from '@/features/projects/project-api'

const queryRoot = ['admin-dashboard'] as const

const importStatusNames: Record<ImportRunStatus, string> = {
  queued: 'operations.queued',
  running: 'operations.running',
  completed: 'operations.completed',
  'completed-with-errors': 'adminDashboard.completedErrors',
  failed: 'operations.failed',
  cancelled: 'operations.cancelled',
  unknown: 'operations.unknown',
}

function formatDate(value: string) {
  return formatDateValue(value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  })
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
  useTranslation()
  return <Link className="group rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" to={to}>
    <Card className="h-full transition-colors group-hover:border-primary/50 group-hover:bg-accent/30">
      <CardContent className="flex h-full items-start justify-between gap-4 p-5">
        <div>
          <p className="text-sm font-medium text-muted-foreground">{title}</p>
          <p className="mt-2 text-3xl font-bold" data-testid={`metric-${title}`}>
            {pending ? '—' : failed ? '!' : value?.toLocaleString(workspaceLocale()) ?? '0'}
          </p>
          <p className="mt-1 text-xs text-muted-foreground">{failed ? i18n.t('adminDashboard.unavailable') : detail}</p>
        </div>
        <span className="rounded-xl bg-accent p-2.5 text-primary"><Icon className="size-5" /></span>
      </CardContent>
    </Card>
  </Link>
}

function SectionError({ children }: { children: string }) {
  useTranslation()
  return <p className="flex items-center gap-2 rounded-lg bg-destructive/10 p-3 text-sm text-foreground" role="status">
    <CircleAlert className="size-4 shrink-0" />{children}
  </p>
}

export function AdminDashboardWorkspacePage() {
  useTranslation()
  const queryClient = useQueryClient()
  const users = useQuery({
    queryKey: [...queryRoot, 'users'],
    queryFn: ({ signal }) => adminUsersApi.list({ page: 1, pageSize: 1 }, signal),
  })
  const organizations = useQuery({
    queryKey: [...queryRoot, 'organizations'],
    queryFn: ({ signal }) => adminOrganizationsApi.list({ page: 1, pageSize: 1 }, signal),
  })
  const operationalErrors = useQuery({
    queryKey: [...queryRoot, 'operational-errors'],
    queryFn: ({ signal }) => adminErrorsApi.list({ page: 1, pageSize: 1 }, signal),
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
    users, organizations, operationalErrors, projects, opportunities,
    pendingOpportunities, funders, imports, sources,
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

  return <div className="min-w-0 space-y-8">
    <header className="flex flex-wrap items-end justify-between gap-4">
      <div>
        <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{i18n.t('editorial.administration')}</p>
        <h1 className="mt-1 text-3xl font-bold">{i18n.t('adminDashboard.title')}</h1>
        <p className="mt-2 max-w-3xl text-muted-foreground">{i18n.t('adminDashboard.intro')}</p>
      </div>
      <Button disabled={refreshing} onClick={refresh} variant="outline">
        {refreshing ? <LoaderCircle className="size-4 animate-spin" /> : <RefreshCw className="size-4" />}
        {i18n.t('operations.refresh')}
      </Button>
    </header>

    {unavailable > 0 && <SectionError>{unavailable === 1
      ? i18n.t('adminDashboard.partialOne')
      : i18n.t('adminDashboard.partialMany', { count: unavailable })}</SectionError>}

    <section aria-labelledby="admin-summary-title" className="space-y-3">
      <h2 className="text-xl font-bold" id="admin-summary-title">{i18n.t('adminDashboard.summary')}</h2>
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard detail={i18n.t('adminDashboard.awaitingModeration')} failed={projects.isError} icon={ShieldCheck} pending={projects.isPending} title={i18n.t('adminProjects.pending')} to="/admin/projects" value={projects.data?.totalCount} />
        <MetricCard detail={i18n.t('adminDashboard.registeredAccounts')} failed={users.isError} icon={Users} pending={users.isPending} title={i18n.t('operations.users')} to="/admin/users" value={users.data?.totalCount} />
        <MetricCard detail={i18n.t('adminDashboard.institutionalProfiles')} failed={organizations.isError} icon={Building2} pending={organizations.isPending} title={i18n.t('operations.organizations')} to="/admin/organizations" value={organizations.data?.totalCount} />
        <MetricCard detail={i18n.t('adminDashboard.sanitizedIncidents')} failed={operationalErrors.isError} icon={CircleAlert} pending={operationalErrors.isPending} title={i18n.t('adminDashboard.errors')} to="/admin/errors" value={operationalErrors.data?.totalCount} />
        <MetricCard detail={i18n.t('adminDashboard.registeredOpportunities')} failed={opportunities.isError} icon={WalletCards} pending={opportunities.isPending} title={i18n.t('adminDashboard.funds')} to="/admin/funding" value={opportunities.data?.totalCount} />
        <MetricCard detail={i18n.t('adminDashboard.awaitingEditorial')} failed={pendingOpportunities.isError} icon={Building2} pending={pendingOpportunities.isPending} title={i18n.t('adminDashboard.pendingFunds')} to="/admin/funding?status=1" value={pendingOpportunities.data?.totalCount} />
        <MetricCard detail={i18n.t('adminDashboard.registeredEntities')} failed={funders.isError} icon={Landmark} pending={funders.isPending} title={i18n.t('adminFunders.title')} to="/admin/funders" value={funders.data?.totalCount} />
        <MetricCard detail={i18n.t('adminDashboard.enabledSources', { count: activeSources ?? 0 })} failed={sources.isError} icon={ServerCog} pending={sources.isPending} title={i18n.t('adminDashboard.sources')} to="/admin/sources" value={sources.data?.length} />
        <MetricCard detail={i18n.t('adminDashboard.registeredRuns')} failed={imports.isError} icon={Upload} pending={imports.isPending} title={i18n.t('adminDashboard.imports')} to="/admin/imports" value={imports.data?.totalCount} />
        <MetricCard detail={i18n.t('adminDashboard.lastFive')} failed={imports.isError} icon={RefreshCw} pending={imports.isPending} title={i18n.t('adminDashboard.activeImports')} to="/admin/imports" value={activeImports} />
      </div>
    </section>

    <section className="grid gap-6 xl:grid-cols-[1.35fr_1fr]">
      <Card>
        <CardHeader className="flex-row items-center justify-between gap-4">
          <div><CardTitle>{i18n.t('adminDashboard.priorities')}</CardTitle><p className="text-sm text-muted-foreground">{i18n.t('adminDashboard.prioritiesHelp')}</p></div>
          <FileSearch className="size-5 text-primary" />
        </CardHeader>
        <CardContent className="space-y-3">
          <Link className="flex items-center justify-between gap-4 rounded-lg border p-4 hover:bg-accent/40" to="/admin/projects"><div><p className="font-semibold">{i18n.t('adminDashboard.projectModeration')}</p><p className="text-sm text-muted-foreground">{i18n.t('adminDashboard.projectHelp')}</p></div><strong>{projects.data?.totalCount ?? '—'}</strong></Link>
          <Link className="flex items-center justify-between gap-4 rounded-lg border p-4 hover:bg-accent/40" to="/admin/funding?status=1"><div><p className="font-semibold">{i18n.t('adminDashboard.fundReview')}</p><p className="text-sm text-muted-foreground">{i18n.t('adminDashboard.fundHelp')}</p></div><strong>{pendingOpportunities.isError ? '!' : pendingOpportunities.data?.totalCount ?? '—'}</strong></Link>
          <Link className="flex items-center justify-between gap-4 rounded-lg border p-4 hover:bg-accent/40" to="/admin/imports"><div><p className="font-semibold">{i18n.t('adminDashboard.importIssues')}</p><p className="text-sm text-muted-foreground">{i18n.t('adminDashboard.importIssuesHelp')}</p></div><strong>{imports.isError ? '!' : recentImportIssues}</strong></Link>
          <Link className="flex items-center justify-between gap-4 rounded-lg border p-4 hover:bg-accent/40" to="/admin/sources"><div><p className="font-semibold">{i18n.t('adminDashboard.sourceIssues')}</p><p className="text-sm text-muted-foreground">{i18n.t('adminDashboard.sourceIssuesHelp')}</p></div><strong>{sources.isError ? '!' : sourceIssues}</strong></Link>
          <Link className="flex items-center justify-between gap-4 rounded-lg border p-4 hover:bg-accent/40" to="/admin/errors"><div><p className="font-semibold">{i18n.t('adminIncidents.title')}</p><p className="text-sm text-muted-foreground">{i18n.t('adminDashboard.incidentsHelp')}</p></div><strong>{operationalErrors.isError ? '!' : operationalErrors.data?.totalCount ?? '—'}</strong></Link>
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle>{i18n.t('adminDashboard.shortcuts')}</CardTitle><p className="text-sm text-muted-foreground">{i18n.t('adminDashboard.shortcutsHelp')}</p></CardHeader>
        <CardContent className="grid gap-3 sm:grid-cols-2 xl:grid-cols-1">
          {[
            ['/admin/projects', i18n.t('adminDashboard.reviewProjects'), ShieldCheck],
            ['/admin/funding/new', i18n.t('adminDashboard.createFund'), WalletCards],
            ['/admin/funders/new', i18n.t('adminFunders.create'), Landmark],
            ['/admin/imports', i18n.t('adminDashboard.runImport'), Upload],
            ['/admin/users', i18n.t('adminDashboard.viewUsers'), Users],
          ].map(([to, label, Icon]) => <Button asChild className="justify-between" key={String(to)} variant="outline"><Link to={String(to)}><span className="inline-flex items-center gap-2"><Icon className="size-4" />{String(label)}</span><ArrowUpRight className="size-4" /></Link></Button>)}
        </CardContent>
      </Card>
    </section>

    <section className="grid gap-6 lg:grid-cols-2">
      <Card>
        <CardHeader className="flex-row items-center justify-between"><div><CardTitle>{i18n.t('adminDashboard.projectsToReview')}</CardTitle><p className="text-sm text-muted-foreground">{i18n.t('adminDashboard.latestSubmissions')}</p></div><Button asChild size="sm" variant="ghost"><Link to="/admin/projects">{i18n.t('adminDashboard.viewAll')}</Link></Button></CardHeader>
        <CardContent className="space-y-2">
          {projects.isPending && <p className="text-sm text-muted-foreground">{i18n.t('adminDashboard.loadingProjects')}</p>}
          {projects.isError && <SectionError>{i18n.t('adminDashboard.projectsFailed')}</SectionError>}
          {projects.data?.items.length === 0 && <p className="rounded-lg bg-muted p-4 text-sm">{i18n.t('adminDashboard.projectsClear')}</p>}
          {projects.data?.items.map(item => <Link className="block rounded-lg border p-3 hover:bg-accent/40" key={item.projectId} to={`/admin/projects/${item.projectId}`}><p className="font-semibold">{item.title}</p><p className="mt-1 text-sm text-muted-foreground">{item.organizationName} · {i18n.t('operations.complete', { value: item.completeness })}</p><p className="mt-1 text-xs text-muted-foreground">{i18n.t('adminDashboard.submitted', { date: formatDate(item.submittedAtUtc) })}</p></Link>)}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex-row items-center justify-between"><div><CardTitle>{i18n.t('adminDashboard.recentImports')}</CardTitle><p className="text-sm text-muted-foreground">{i18n.t('adminDashboard.latestRuns')}</p></div><Button asChild size="sm" variant="ghost"><Link to="/admin/imports">{i18n.t('adminDashboard.viewAllFeminine')}</Link></Button></CardHeader>
        <CardContent className="space-y-2">
          {imports.isPending && <p className="text-sm text-muted-foreground">{i18n.t('adminDashboard.loadingImports')}</p>}
          {imports.isError && <SectionError>{i18n.t('adminDashboard.importsFailed')}</SectionError>}
          {imports.data?.items.length === 0 && <p className="rounded-lg bg-muted p-4 text-sm">{i18n.t('adminDashboard.noRuns')}</p>}
          {imports.data?.items.map(item => <Link className="flex items-center justify-between gap-3 rounded-lg border p-3 hover:bg-accent/40" key={item.runId} to={`/admin/imports/${item.runId}`}><div><p className="font-semibold">{item.sourceName}</p><p className="mt-1 text-xs text-muted-foreground">{formatDate(item.createdAtUtc)} · {i18n.t('adminDashboard.retrieved', { count: item.retrievedCount })}</p></div><span className="rounded-full bg-muted px-2.5 py-1 text-xs font-semibold">{operationStatus(importStatusNames, item.status)}</span></Link>)}
        </CardContent>
      </Card>
    </section>
  </div>
}
