import { formatDateValue } from '@/i18n/formats'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  ArrowRight,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  CircleAlert,
  Clock3,
  DatabaseZap,
  History,
  Info,
  LoaderCircle,
  RefreshCw,
  Scale,
  ShieldAlert,
  Target,
} from 'lucide-react'
import { useEffect, useMemo, useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Link, useSearchParams } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  createMatchingCommandId,
  matchingApi,
  type MatchClassification,
  type MatchingRuleEvidence,
  type MatchingRuleResult,
  type MatchingRunDetail,
  type MatchingRunSummary,
  type ProjectFundingMatch,
} from '@/features/matching/matching-api'
import { organizationApi } from '@/features/organizations/organization-api'
import { projectApi, type ProjectSummary } from '@/features/projects/project-api'
import i18n from '@/i18n'
import { collaborationErrorMessage, hasMatchingRuleLabel, isStandardMatchingDisclaimer, matchingEvidenceField, matchingEvidenceSource, matchingReasonText, matchingRuleName } from '@/i18n/collaboration-messages'
import { workspaceLocale } from '@/i18n/workspace-messages'

const selectClass = 'h-11 w-full rounded-lg border bg-background px-3 text-sm'

function parsePage(value: string | null) {
  const parsed = Number(value)
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : 1
}

function clampPercent(value: number) {
  return Math.min(100, Math.max(0, value))
}

function formatPercent(value: number) {
  return new Intl.NumberFormat(workspaceLocale(), { maximumFractionDigits: 1 }).format(value)
}

function formatDateTime(value: string | null) {
  return formatDateValue(value, { dateStyle: 'medium', timeStyle: 'short' }, i18n.t('matching.noDate'))
}

function formatDateOnly(value: string) {
  return formatDateValue(value)
}

function fundingDeadlineText(
  opportunity: ProjectFundingMatch['fundingOpportunity'],
) {
  if (opportunity.deadlinePrecision === 2 && opportunity.closeAtUtc) {
    const instant = new Date(opportunity.closeAtUtc)
    if (!Number.isNaN(instant.getTime())) {
      const formatted = formatDateValue(instant, {
        dateStyle: 'medium',
        timeStyle: 'short',
        timeZone: 'UTC',
        hourCycle: 'h23',
      })
      return i18n.t('matching.exactDeadline', { date: formatted })
    }
  }

  if (opportunity.deadlinePrecision === 1 && opportunity.closeDate) {
    return i18n.t('matching.publishedDeadline', { date: formatDateOnly(opportunity.closeDate) })
  }

  if (opportunity.deadlinePrecision === 0 &&
      !opportunity.closeDate && !opportunity.closeAtUtc) {
    return i18n.t('matching.rolling')
  }

  return i18n.t('matching.unknownDeadline')
}

function reasonParameterText(parameters: Record<string, string | null>) {
  const messages: string[] = []
  if (/^\d{1,4}$/.test(parameters.matchCount ?? '')) {
    messages.push(i18n.t('matching.matchCount', { count: Number(parameters.matchCount) }))
  }
  const projectCurrency = /^[A-Z]{3}$/.test(parameters.projectCurrency ?? '')
    ? parameters.projectCurrency
    : null
  const opportunityCurrency = /^[A-Z]{3}$/.test(parameters.opportunityCurrency ?? '')
    ? parameters.opportunityCurrency
    : null
  if (projectCurrency || opportunityCurrency) {
    messages.push(i18n.t('matching.currenciesCompared', { project: projectCurrency ?? i18n.t('matching.noData'), opportunity: opportunityCurrency ?? i18n.t('matching.noData') }))
  }
  const yearParameters = [
    [i18n.t('matching.minimumYears'), parameters.minimumGuaranteedYears],
    [i18n.t('matching.maximumYears'), parameters.maximumPossibleYears],
    [i18n.t('matching.requiredYears'), parameters.requiredYears],
  ] as const
  for (const [label, value] of yearParameters) {
    if (/^\d{1,3}$/.test(value ?? '')) messages.push(`${label}: ${value}`)
  }
  return messages
}

function Evidence({ evidence }: { evidence: MatchingRuleEvidence }) {
  const { t } = useTranslation()
  const source = matchingEvidenceSource(evidence.source)
  const field = matchingEvidenceField(evidence.fieldCode)
  return (
    <div className="rounded-lg bg-muted/70 p-3 text-xs text-muted-foreground">
      <p><strong className="text-foreground">{t('matching.controlledEvidence')}</strong> {source} · {field}</p>
      {evidence.valueCodes.length > 0 && (
        <p className="mt-1">{t('matching.evidenceValues', { count: evidence.valueCodes.length })}</p>
      )}
    </div>
  )
}

function RuleResult({ rule }: { rule: MatchingRuleResult }) {
  const { t } = useTranslation()
  const parameterMessages = reasonParameterText(rule.reasonParameters)
  return (
    <li className="space-y-3 rounded-lg border bg-background p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="flex flex-wrap items-center gap-2">
            <h4 className="font-bold" lang={hasMatchingRuleLabel(rule.code) ? undefined : 'es'}>{matchingRuleName(rule)}</h4>
            {rule.isHardGate && (
              <span className="rounded-full bg-muted px-2.5 py-1 text-xs font-semibold">
                {t('matching.hardCondition')}
              </span>
            )}
            {rule.isWarning && (
              <span className="rounded-full bg-amber-100 px-2.5 py-1 text-xs font-semibold text-amber-900 dark:bg-amber-950 dark:text-amber-100">
                {t('matching.warning')}
              </span>
            )}
          </div>
          <p className="mt-1 text-sm text-muted-foreground">{matchingReasonText(rule)}</p>
        </div>
        <div className="text-right">
          <p className="text-sm font-semibold">{t(`matching.outcome.${rule.outcome}`)}</p>
          <p className="text-xs text-muted-foreground">{t(`matching.dataState.${rule.dataState}`)}</p>
        </div>
      </div>
      {!rule.isHardGate && (
        <p className="text-xs text-muted-foreground">
          {t('matching.scoreContribution', { points: formatPercent(rule.weightedPoints), weight: formatPercent(rule.weight) })}
        </p>
      )}
      {parameterMessages.length > 0 && (
        <ul className="grid gap-1 text-xs text-muted-foreground">
          {parameterMessages.map((message) => <li key={message}>{message}</li>)}
        </ul>
      )}
      {rule.evidence && <Evidence evidence={rule.evidence} />}
    </li>
  )
}

function classificationClass(classification: MatchClassification) {
  if (classification === 0) return 'bg-accent text-accent-foreground'
  if (classification === 1) return 'bg-destructive/10 text-foreground'
  return 'bg-muted text-foreground'
}

function MatchResultCard({ match }: { match: ProjectFundingMatch }) {
  const { t } = useTranslation()
  const opportunity = match.fundingOpportunity
  return (
    <article aria-labelledby={`match-${opportunity.publicId}`}>
      <Card className={!match.isCurrent ? 'border-amber-500/60' : undefined}>
        <CardHeader className="gap-4 sm:flex sm:flex-row sm:items-start sm:justify-between sm:space-y-0">
          <div>
            <div className="flex flex-wrap items-center gap-2">
              <span className={`rounded-full px-3 py-1 text-xs font-bold ${classificationClass(match.classification)}`}>
                {t(`matching.classification.${match.classification}`)}
              </span>
              {!match.isCurrent && (
                <span className="rounded-full bg-amber-100 px-3 py-1 text-xs font-bold text-amber-900 dark:bg-amber-950 dark:text-amber-100">
                  {t('matching.staleResult')}
                </span>
              )}
            </div>
            <CardTitle className="mt-3 text-xl" id={`match-${opportunity.publicId}`}>
              {opportunity.title}
            </CardTitle>
            <p className="mt-1 text-sm text-muted-foreground">{opportunity.sponsorName}</p>
          </div>
          <Button asChild size="sm" variant="outline">
            <Link to={`/opportunities/${encodeURIComponent(opportunity.slug)}`}>
              {t('matching.reviewFunding')} <ArrowRight className="size-4" />
            </Link>
          </Button>
        </CardHeader>
        <CardContent className="space-y-5">
          <div className="grid gap-3 sm:grid-cols-3">
            <div className="rounded-lg border bg-background p-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{t('matching.score')}</p>
              {match.compatibilityScore === null
                ? <p className="mt-1 text-xl font-bold">{t('matching.notApplicable')}</p>
                : <p aria-label={t('matching.scoreLabel', { score: formatPercent(match.compatibilityScore) })} className="mt-1 text-2xl font-bold">{formatPercent(match.compatibilityScore)}<span className="text-sm text-muted-foreground">/100</span></p>}
            </div>
            <div className="rounded-lg border bg-background p-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{t('matching.coverage')}</p>
              <p className="mt-1 text-2xl font-bold">{formatPercent(match.evidenceCoverage)}%</p>
              <progress aria-label={t('matching.coverageLabel', { coverage: formatPercent(match.evidenceCoverage) })} className="mt-2 h-2 w-full accent-primary" max="100" value={clampPercent(match.evidenceCoverage)} />
            </div>
            <div className="rounded-lg border bg-background p-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{t('matching.hardConditions')}</p>
              <p className="mt-1 text-sm font-bold">{t(`matching.hardGate.${match.hardGateStatus}`)}</p>
              {match.hardGateStatus === 2 && <p className="mt-1 text-xs text-muted-foreground">{t('matching.unknownNotPassed')}</p>}
            </div>
          </div>

          <div className="flex flex-wrap gap-x-5 gap-y-2 text-xs text-muted-foreground">
            <span>{t('matching.termsVersion', { version: opportunity.contentVersion })}</span>
            <span>{fundingDeadlineText(opportunity)}</span>
          </div>

          <details className="group rounded-lg border bg-muted/30 p-4">
            <summary className="cursor-pointer font-bold">
              {t('matching.ruleCount', { count: match.ruleResults.length })}
            </summary>
            <p className="mt-2 text-sm text-muted-foreground">
              {t('matching.scoreHelp')}
            </p>
            {match.ruleResults.length > 0 ? (
              <ul className="mt-4 grid gap-3">
                {match.ruleResults.map((rule) => <RuleResult key={rule.code} rule={rule} />)}
              </ul>
            ) : (
              <p className="mt-4 text-sm text-muted-foreground">{t('matching.noRules')}</p>
            )}
          </details>
        </CardContent>
      </Card>
    </article>
  )
}

function RunSummaryButton({
  run,
  selected,
  onSelect,
}: {
  run: MatchingRunSummary
  selected: boolean
  onSelect: () => void
}) {
  const { t } = useTranslation()
  return (
    <li>
      <button
        aria-pressed={selected}
        className={`w-full rounded-lg border p-4 text-left transition-colors hover:bg-muted ${selected ? 'border-primary bg-accent/60' : 'bg-background'}`}
        onClick={onSelect}
        type="button"
      >
        <div className="flex items-start justify-between gap-2">
          <span className="font-bold">{formatDateTime(run.completedAtUtc ?? run.createdAtUtc)}</span>
          <span className="rounded-full bg-muted px-2 py-1 text-xs">{t(`matching.runStatus.${run.status}`)}</span>
        </div>
        <p className="mt-2 text-xs text-muted-foreground">
          {t('matching.runCounts', { candidate: run.candidateCount, total: run.totalCandidateCount, compatible: run.compatibleCount, incompatible: run.incompatibleCount, insufficient: run.insufficientDataCount })}
        </p>
        {run.isTruncated && <p className="mt-2 text-xs font-semibold text-amber-800 dark:text-amber-200">{t('matching.bounded')}</p>}
      </button>
    </li>
  )
}

function RunHistory({
  runs,
  selectedRunId,
  onSelect,
  page,
  onPage,
}: {
  runs: { items: MatchingRunSummary[]; totalCount: number; pageNumber: number; pageSize: number }
  selectedRunId: string | null
  onSelect: (runId: string) => void
  page: number
  onPage: (page: number) => void
}) {
  const { t } = useTranslation()
  const lastPage = Math.max(1, Math.ceil(runs.totalCount / runs.pageSize))
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2"><History className="size-5" /> {t('matching.history')}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <ul className="grid gap-3">
          {runs.items.map((run) => (
            <RunSummaryButton
              key={run.publicId}
              onSelect={() => onSelect(run.publicId)}
              run={run}
              selected={run.publicId === selectedRunId}
            />
          ))}
        </ul>
        {lastPage > 1 && (
          <nav aria-label={t('matching.historyPagination')} className="flex items-center justify-between gap-2">
            <Button aria-label={t('matching.historyPrevious')} disabled={page <= 1} onClick={() => onPage(page - 1)} size="icon" variant="outline">
              <ChevronLeft className="size-4" />
            </Button>
            <span className="text-xs text-muted-foreground">{t('matching.page', { page: runs.pageNumber, total: lastPage })}</span>
            <Button aria-label={t('matching.historyNext')} disabled={page >= lastPage} onClick={() => onPage(page + 1)} size="icon" variant="outline">
              <ChevronRight className="size-4" />
            </Button>
          </nav>
        )}
      </CardContent>
    </Card>
  )
}

function MatchingResults({ detail }: { detail: MatchingRunDetail }) {
  const { t } = useTranslation()
  const run = detail.run
  const current = run.isCurrent
  return (
    <section aria-labelledby="matching-results-title" className="space-y-5">
      <Card>
        <CardContent className="space-y-4 p-5">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p className="text-xs font-bold uppercase tracking-[0.16em] text-primary">{t('matching.reproducible')}</p>
              <h2 className="mt-1 text-2xl font-bold" id="matching-results-title">{t('matching.indicativeCompatibility')}</h2>
              <p className="mt-1 text-sm text-muted-foreground">{t('matching.calculated', { date: formatDateTime(run.completedAtUtc ?? run.createdAtUtc) })}</p>
            </div>
            <span className={`rounded-full px-3 py-1 text-xs font-bold ${current ? 'bg-accent text-accent-foreground' : 'bg-amber-100 text-amber-900 dark:bg-amber-950 dark:text-amber-100'}`}>
              {current ? t('matching.currentVersions') : t('matching.oldVersions')}
            </span>
          </div>
          <dl className="grid gap-3 rounded-lg bg-muted p-4 text-sm sm:grid-cols-3">
            <div><dt className="text-muted-foreground">{t('matching.project')}</dt><dd className="font-bold">v{run.projectVersion}</dd></div>
            <div><dt className="text-muted-foreground">{t('matching.profile')}</dt><dd className="font-bold">v{run.organizationProfileVersion}</dd></div>
            <div><dt className="text-muted-foreground">{t('matching.engineRules')}</dt><dd className="font-bold">{run.engineVersion} · {run.matchingProfile.name} v{run.matchingProfile.version}</dd></div>
          </dl>
          <p className="text-xs text-muted-foreground">{t('matching.snapshot', { date: formatDateTime(run.catalogSnapshotAtUtc) })}</p>
          {run.isTruncated && (
            <p className="flex items-start gap-2 rounded-lg bg-amber-100 p-3 text-sm text-amber-950 dark:bg-amber-950 dark:text-amber-100" role="status">
              <CircleAlert className="mt-0.5 size-4 shrink-0" />
              {t('matching.boundedHelp', { candidate: run.candidateCount, total: run.totalCandidateCount })}
            </p>
          )}
          <p className="flex items-start gap-2 rounded-lg border p-3 text-sm text-muted-foreground">
            <Info className="mt-0.5 size-4 shrink-0 text-primary" aria-hidden="true" />
            {isStandardMatchingDisclaimer(detail.disclaimer) ? t('matching.disclaimer') : <span lang="es">{detail.disclaimer}</span>}
          </p>
        </CardContent>
      </Card>

      {detail.items.length === 0 ? (
        <Card>
          <CardContent className="space-y-3 p-10 text-center">
            <DatabaseZap className="mx-auto size-9 text-muted-foreground" />
            <h3 className="text-xl font-bold">{t('matching.noFunding')}</h3>
            <p className="text-sm text-muted-foreground">{t('matching.noFundingHelp')}</p>
            <Button asChild variant="outline"><Link to="/opportunities">{t('matching.reviewCatalog')}</Link></Button>
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-5">
          {detail.items.map((match) => (
            <MatchResultCard key={match.fundingOpportunity.publicId} match={match} />
          ))}
        </div>
      )}
    </section>
  )
}

function OrganizationRequired() {
  const { t } = useTranslation()
  return (
    <Card>
      <CardContent className="space-y-4 p-8 text-center">
        <Target className="mx-auto size-9 text-primary" />
        <h1 className="text-2xl font-bold">{t('matching.organizationRequired')}</h1>
        <p className="text-sm text-muted-foreground">{t('matching.organizationRequiredHelp')}</p>
        <Button asChild><Link to="/onboarding">{t('matching.createOrganization')}</Link></Button>
      </CardContent>
    </Card>
  )
}

function NoProjects() {
  const { t } = useTranslation()
  return (
    <Card>
      <CardContent className="space-y-4 p-10 text-center">
        <Target className="mx-auto size-9 text-primary" />
        <h2 className="text-xl font-bold">{t('matching.projectRequired')}</h2>
        <p className="text-sm text-muted-foreground">{t('matching.projectRequiredHelp')}</p>
        <Button asChild><Link to="/projects">{t('matching.goProjects')}</Link></Button>
      </CardContent>
    </Card>
  )
}

export function MatchingWorkspacePage() {
  const { t } = useTranslation()
  const [searchParams, setSearchParams] = useSearchParams()
  const queryClient = useQueryClient()
  const command = useRef<{ projectId: string; key: string } | null>(null)
  const [calculationNotice, setCalculationNotice] = useState<'' | 'matching.replayed' | 'matching.calculationCompleted'>('')
  const requestedProjectId = searchParams.get('projectId')
  const requestedRunId = searchParams.get('runId')
  const page = parsePage(searchParams.get('page'))

  const organizations = useQuery({
    queryKey: ['organizations'],
    queryFn: ({ signal }) => organizationApi.list(signal),
  })
  const organization = organizations.data?.[0]
  const projects = useQuery({
    queryKey: ['projects', organization?.publicId],
    queryFn: ({ signal }) => projectApi.list(organization!.publicId, signal),
    enabled: Boolean(organization),
  })
  const availableProjects = useMemo(() => projects.data ?? [], [projects.data])
  const selectedProject = availableProjects.find((project) => project.publicId === requestedProjectId)
    ?? null
  const canCalculate = Boolean(selectedProject && selectedProject.publicationStatus !== 4)

  const runs = useQuery({
    queryKey: ['matching-runs', organization?.publicId, selectedProject?.publicId, page],
    queryFn: ({ signal }) => matchingApi.list(
      organization!.publicId,
      selectedProject!.publicId,
      page,
      10,
      signal,
    ),
    enabled: Boolean(organization && selectedProject),
  })
  const selectedRunId = requestedRunId
    ?? runs.data?.items[0]?.publicId
    ?? null
  const detail = useQuery({
    queryKey: ['matching-run', organization?.publicId, selectedProject?.publicId, selectedRunId],
    queryFn: ({ signal }) => matchingApi.get(
      organization!.publicId,
      selectedProject!.publicId,
      selectedRunId!,
      signal,
    ),
    enabled: Boolean(organization && selectedProject && selectedRunId),
  })

  useEffect(() => {
    if (requestedProjectId && projects.data && !selectedProject) {
      const next = new URLSearchParams(searchParams)
      next.delete('projectId')
      next.delete('runId')
      next.delete('page')
      setSearchParams(next, { replace: true })
    }
  }, [projects.data, requestedProjectId, searchParams, selectedProject, setSearchParams])

  const calculation = useMutation({
    mutationFn: async (project: ProjectSummary) => {
      if (!organization) throw new Error('organization-required')
      if (command.current?.projectId !== project.publicId) {
        command.current = { projectId: project.publicId, key: createMatchingCommandId() }
      }
      return matchingApi.calculate(organization.publicId, project.publicId, command.current.key)
    },
    onSuccess: async (response, project) => {
      if (!organization) return
      command.current = null
      const runId = response.run.run.publicId
      queryClient.setQueryData(
        ['matching-run', organization.publicId, project.publicId, runId],
        response.run,
      )
      setCalculationNotice(response.wasReplay
        ? 'matching.replayed'
        : 'matching.calculationCompleted')
      const next = new URLSearchParams(searchParams)
      next.set('projectId', project.publicId)
      next.set('runId', runId)
      next.delete('page')
      setSearchParams(next, { replace: true })
      await queryClient.invalidateQueries({
        queryKey: ['matching-runs', organization.publicId, project.publicId],
      })
    },
  })

  function selectProject(projectId: string) {
    command.current = null
    calculation.reset()
    setCalculationNotice('')
    const next = new URLSearchParams()
    if (projectId) next.set('projectId', projectId)
    setSearchParams(next)
  }

  function selectRun(runId: string) {
    const next = new URLSearchParams(searchParams)
    next.set('runId', runId)
    setSearchParams(next, { replace: true })
  }

  function setPage(nextPage: number) {
    const next = new URLSearchParams(searchParams)
    next.set('page', String(nextPage))
    next.delete('runId')
    setSearchParams(next, { replace: true })
  }

  function retryCalculation() {
    if (!selectedProject || !canCalculate) return
    if (calculation.error instanceof ApiError && calculation.error.response.status === 409) {
      command.current = null
    }
    calculation.mutate(selectedProject)
  }

  if (organizations.isPending) {
    return <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" /> {t('matching.loading')}</p>
  }
  if (organizations.isError) {
    return (
      <Card className="border-destructive/40">
        <CardContent className="space-y-3 p-8" role="alert">
          <CircleAlert className="size-8 text-destructive" />
          <h1 className="text-xl font-bold">{t('matching.organizationFailed')}</h1>
          <Button onClick={() => void organizations.refetch()} variant="outline">{t('matching.retry')}</Button>
        </CardContent>
      </Card>
    )
  }
  if (!organization) return <OrganizationRequired />

  return (
    <div className="space-y-6">
      <header>
        <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{t('matching.eyebrow')}</p>
        <h1 className="mt-1 text-3xl font-bold">{t('matching.title')}</h1>
        <p className="mt-2 max-w-3xl text-muted-foreground">
          {t('matching.description')}
        </p>
      </header>

      <Card>
        <CardContent className="space-y-5 p-5 sm:p-6">
          <div className="flex items-start gap-3 rounded-lg bg-muted p-4 text-sm">
            <Scale className="mt-0.5 size-5 shrink-0 text-primary" aria-hidden="true" />
            <div>
              <p className="font-bold">{t('matching.notEligibility')}</p>
              <p className="mt-1 text-muted-foreground">{t('matching.notEligibilityHelp')}</p>
            </div>
          </div>

          {projects.isPending && <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-4 animate-spin" /> {t('matching.loadingProjects')}</p>}
          {projects.isError && (
            <div className="space-y-3" role="alert">
              <p className="text-sm text-destructive">{t('matching.projectsFailed')}</p>
              <Button onClick={() => void projects.refetch()} size="sm" variant="outline">{t('matching.retry')}</Button>
            </div>
          )}
          {projects.data && availableProjects.length === 0 && <NoProjects />}
          {availableProjects.length > 0 && (
            <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-end">
              <label className="grid gap-1.5 text-sm font-semibold" htmlFor="matching-project">
                {t('matching.projectToCompare')}
                <select
                  className={selectClass}
                  disabled={calculation.isPending}
                  id="matching-project"
                  onChange={(event) => selectProject(event.target.value)}
                  value={selectedProject?.publicId ?? ''}
                >
                  <option value="">{t('matching.selectProject')}</option>
                  {availableProjects.map((project) => (
                    <option key={project.publicId} value={project.publicId}>
                      {project.title}{project.publicationStatus === 4 ? t('matching.archivedSuffix') : ''}
                    </option>
                  ))}
                </select>
                <span className="text-xs font-normal text-muted-foreground">
                  {selectedProject?.publicationStatus === 4
                    ? t('matching.archivedSelected')
                    : t('matching.archivedHelp')}
                </span>
              </label>
              <Button
                disabled={!canCalculate || calculation.isPending}
                onClick={() => selectedProject && calculation.mutate(selectedProject)}
                type="button"
              >
                {calculation.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <RefreshCw className="size-4" />}
                {runs.data?.items.length ? t('matching.calculateCurrent') : t('matching.calculate')}
              </Button>
            </div>
          )}

          {calculation.isError && (
            <div className="space-y-3 rounded-lg bg-destructive/10 p-4 text-sm text-foreground" role="alert">
              <div className="flex items-start gap-2">
                <ShieldAlert className="mt-0.5 size-4 shrink-0" />
                <div>
                  <h2 className="font-bold">{t('matching.calculationFailed')}</h2>
                  <p className="mt-1">{collaborationErrorMessage(calculation.error, 'matching')}</p>
                </div>
              </div>
              <div className="flex flex-wrap gap-2">
                {canCalculate && <Button onClick={retryCalculation} size="sm" variant="outline">{t('matching.retryCalculation')}</Button>}
                <Button asChild size="sm" variant="ghost"><Link to="/organization/profile">{t('matching.reviewProfile')}</Link></Button>
                {selectedProject && <Button asChild size="sm" variant="ghost"><Link to={`/projects/${selectedProject.publicId}`}>{t('matching.reviewProject')}</Link></Button>}
              </div>
            </div>
          )}
          {calculationNotice && <p className="flex items-center gap-2 rounded-lg bg-accent p-3 text-sm font-medium text-accent-foreground" role="status"><CheckCircle2 className="size-4" /> {t(calculationNotice)}</p>}
        </CardContent>
      </Card>

      {!selectedProject && availableProjects.length > 0 && (
        <Card>
          <CardContent className="space-y-3 p-10 text-center">
            <Target className="mx-auto size-9 text-muted-foreground" />
            <h2 className="text-xl font-bold">{t('matching.chooseProject')}</h2>
            <p className="text-sm text-muted-foreground">{t('matching.chooseProjectHelp')}</p>
          </CardContent>
        </Card>
      )}

      {selectedProject && runs.isPending && (
        <Card><CardContent className="flex items-center gap-2 p-8" role="status"><LoaderCircle className="size-5 animate-spin" /> {t('matching.loadingHistory')}</CardContent></Card>
      )}
      {selectedProject && runs.isError && (
        <Card className="border-destructive/40">
          <CardContent className="space-y-3 p-8" role="alert">
            <CircleAlert className="size-8 text-destructive" />
            <h2 className="text-xl font-bold">{t('matching.historyFailed')}</h2>
            <p className="text-sm text-muted-foreground">{collaborationErrorMessage(runs.error, 'matching')}</p>
            <Button onClick={() => void runs.refetch()} variant="outline">{t('matching.retry')}</Button>
          </CardContent>
        </Card>
      )}
      {selectedProject && runs.data?.items.length === 0 && !calculation.isPending && !calculation.isSuccess && (
        <Card>
          <CardContent className="space-y-3 p-10 text-center">
            <Clock3 className="mx-auto size-9 text-muted-foreground" />
            <h2 className="text-xl font-bold">{t('matching.noCalculations')}</h2>
            <p className="text-sm text-muted-foreground">
              {canCalculate
                ? t('matching.calculateHelp')
                : t('matching.archivedEmpty')}
            </p>
          </CardContent>
        </Card>
      )}

      {selectedProject && ((runs.data?.items.length ?? 0) > 0 || detail.data) && (
        <div className={(runs.data?.items.length ?? 0) > 0 ? 'grid items-start gap-6 xl:grid-cols-[20rem_minmax(0,1fr)]' : ''}>
          {runs.data && runs.data.items.length > 0 && <RunHistory
            onPage={setPage}
            onSelect={selectRun}
            page={page}
            runs={runs.data}
            selectedRunId={selectedRunId}
          />}
          <div>
            {detail.isPending && <Card><CardContent className="flex items-center gap-2 p-8" role="status"><LoaderCircle className="size-5 animate-spin" /> {t('matching.loadingBreakdown')}</CardContent></Card>}
            {detail.isError && (
              <Card className="border-destructive/40">
                <CardContent className="space-y-3 p-8" role="alert">
                  <CircleAlert className="size-8 text-destructive" />
                  <h2 className="text-xl font-bold">{t('matching.detailFailed')}</h2>
                  <p className="text-sm text-muted-foreground">{collaborationErrorMessage(detail.error, 'matching')}</p>
                  <Button onClick={() => void detail.refetch()} variant="outline">{t('matching.retry')}</Button>
                </CardContent>
              </Card>
            )}
            {detail.data && <MatchingResults detail={detail.data} />}
          </div>
        </div>
      )}
    </div>
  )
}
