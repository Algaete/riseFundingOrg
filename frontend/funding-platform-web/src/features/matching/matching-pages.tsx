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
import { Link, useSearchParams } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  createMatchingCommandId,
  matchingApi,
  type HardGateStatus,
  type MatchClassification,
  type MatchingDataState,
  type MatchingRuleEvidence,
  type MatchingRuleOutcome,
  type MatchingRuleResult,
  type MatchingRunDetail,
  type MatchingRunStatus,
  type MatchingRunSummary,
  type ProjectFundingMatch,
} from '@/features/matching/matching-api'
import { organizationApi } from '@/features/organizations/organization-api'
import { projectApi, type ProjectSummary } from '@/features/projects/project-api'

const selectClass = 'h-11 w-full rounded-lg border bg-background px-3 text-sm'
const matchingDisclaimer = 'Resultado orientativo basado en datos disponibles; no confirma elegibilidad ni reemplaza la revisión de las bases del fondo.'

const classificationNames: Record<MatchClassification, string> = {
  0: 'Compatible',
  1: 'Incompatible',
  2: 'Datos insuficientes',
}

const hardGateNames: Record<HardGateStatus, string> = {
  0: 'Sin incompatibilidades detectadas',
  1: 'Incompatibilidad detectada',
  2: 'Datos insuficientes',
}

const runStatusNames: Record<MatchingRunStatus, string> = {
  0: 'Pendiente',
  1: 'En proceso',
  2: 'Completado',
  3: 'Fallido',
}

const outcomeNames: Record<MatchingRuleOutcome, string> = {
  0: 'Coincide',
  1: 'Coincide parcialmente',
  2: 'No coincide',
  3: 'No se puede determinar',
}

const dataStateNames: Record<MatchingDataState, string> = {
  0: 'Dato conocido',
  1: 'Dato desconocido',
  2: 'No aplica',
}

const evidenceSourceNames: Record<string, string> = {
  organization: 'Perfil institucional',
  organization_profile: 'Perfil institucional',
  project: 'Proyecto',
  funding_opportunity: 'Bases del fondo',
  opportunity: 'Bases del fondo',
  'versioned-snapshots': 'Versiones guardadas del proyecto, perfil y fondo',
}

const evidenceFieldNames: Record<string, string> = {
  organization_type: 'Tipo de organización',
  organization_country: 'País de la organización',
  legal_entity_type: 'Figura jurídica',
  established_year: 'Antigüedad institucional',
  project_country: 'País o territorio del proyecto',
  project_region: 'Región del proyecto',
  project_category: 'Área de impacto',
  project_beneficiary_type: 'Población beneficiaria',
  project_budget: 'Necesidad de financiamiento',
  project_currency: 'Moneda del proyecto',
  project_dates: 'Fechas del proyecto',
  opportunity_country: 'País admitido por el fondo',
  opportunity_category: 'Área financiada',
  opportunity_beneficiary_type: 'Población admitida',
  opportunity_project_type: 'Tipo de proyecto admitido',
  opportunity_amount: 'Monto financiable',
  opportunity_currency: 'Moneda del fondo',
  opportunity_deadline: 'Vigencia del fondo',
  geography: 'País o región',
  categories: 'Áreas de impacto',
  beneficiaries: 'Población beneficiaria',
  amount: 'Monto y moneda',
  legal_entity: 'Figura jurídica',
  operating_years: 'Años de operación',
  prior_experience: 'Experiencia previa',
  project_type: 'Tipo de proyecto',
}

const reasonMessages: Record<string, string> = {
  MATCH: 'Los datos disponibles coinciden con esta condición.',
  PARTIAL_MATCH: 'Los datos disponibles coinciden solo parcialmente con esta condición.',
  NO_MATCH: 'Los datos disponibles muestran una incompatibilidad con esta condición.',
  UNKNOWN: 'No hay datos suficientes para evaluar esta condición.',
  NOT_APPLICABLE: 'Esta condición no aplica a este caso.',
  COUNTRY_MATCH: 'El territorio del proyecto está contemplado por el fondo.',
  COUNTRY_NO_MATCH: 'El territorio del proyecto no está contemplado por el fondo.',
  COUNTRY_UNKNOWN: 'Falta información territorial para comparar este criterio.',
  CATEGORY_MATCH: 'El área de impacto del proyecto coincide con la convocatoria.',
  CATEGORY_NO_MATCH: 'El área de impacto declarada no coincide con la convocatoria.',
  CATEGORY_UNKNOWN: 'Falta información para comparar las áreas de impacto.',
  BENEFICIARY_MATCH: 'La población beneficiaria del proyecto está contemplada por el fondo.',
  BENEFICIARY_NO_MATCH: 'La población beneficiaria declarada no está contemplada por el fondo.',
  BENEFICIARY_UNKNOWN: 'Falta información para comparar la población beneficiaria.',
  PROJECT_TYPE_UNKNOWN: 'Falta información para comparar el tipo de proyecto.',
  AMOUNT_MATCH: 'La necesidad de financiamiento está dentro del rango publicado.',
  AMOUNT_PARTIAL: 'La necesidad de financiamiento coincide solo parcialmente con el rango publicado.',
  AMOUNT_NO_MATCH: 'La necesidad de financiamiento está fuera del rango publicado.',
  AMOUNT_UNKNOWN: 'Faltan monto o moneda para evaluar el rango de financiamiento.',
  ORGANIZATION_TYPE_MATCH: 'El tipo de organización está contemplado por el fondo.',
  ORGANIZATION_TYPE_NO_MATCH: 'El tipo de organización no está contemplado por el fondo.',
  ORGANIZATION_TYPE_UNKNOWN: 'Falta información para comparar el tipo de organización.',
  DEADLINE_OPEN: 'La fecha de cierre publicada aún no ha pasado.',
  DEADLINE_CLOSED: 'La fecha de cierre publicada ya pasó.',
  DEADLINE_UNKNOWN: 'La fuente no informa una fecha de cierre precisa.',
  GEOGRAPHY_GLOBAL: 'El fondo no restringe la comparación a un país o región específicos.',
  GEOGRAPHY_COUNTRY_MATCH: 'Al menos un país del proyecto coincide con el alcance publicado.',
  GEOGRAPHY_REGION_MATCH: 'Al menos una región del proyecto coincide con el alcance publicado.',
  GEOGRAPHY_EXPLICIT_NO_MATCH: 'El territorio declarado por el proyecto no coincide con el alcance publicado.',
  GEOGRAPHY_MISSING_PROJECT: 'El proyecto no tiene territorio suficiente para evaluar esta condición.',
  GEOGRAPHY_MISSING_OPPORTUNITY: 'Las bases estructuradas no informan suficiente alcance territorial.',
  ORGANIZATION_TYPE_ALLOWED: 'El tipo institucional figura entre los admitidos por las bases estructuradas.',
  ORGANIZATION_TYPE_EXCLUDED: 'El tipo institucional figura entre los excluidos por las bases estructuradas.',
  ORGANIZATION_TYPE_NOT_ALLOWED: 'El tipo institucional no figura entre los contemplados por las bases estructuradas.',
  ORGANIZATION_TYPE_NOT_RESTRICTED: 'Las bases estructuradas no restringen el tipo de organización.',
  ORGANIZATION_TYPE_MISSING_OPPORTUNITY: 'Las bases estructuradas no informan suficiente detalle sobre tipos de organización.',
  LEGAL_ENTITY_NOT_REQUIRED: 'Las bases estructuradas no exigen una figura jurídica específica.',
  LEGAL_ENTITY_ALLOWED: 'La figura jurídica declarada está contemplada por las bases estructuradas.',
  LEGAL_ENTITY_EXCLUDED: 'La figura jurídica declarada figura entre las excluidas por las bases estructuradas.',
  LEGAL_ENTITY_NOT_ALLOWED: 'La figura jurídica declarada no figura entre las contempladas por las bases estructuradas.',
  LEGAL_ENTITY_PRESENT: 'El perfil institucional contiene una figura jurídica para contrastar.',
  LEGAL_ENTITY_MISSING_ORGANIZATION: 'El perfil institucional no informa una figura jurídica suficiente para comparar.',
  LEGAL_ENTITY_MISSING_OPPORTUNITY: 'Las bases estructuradas no informan suficiente detalle sobre figura jurídica.',
  OPERATING_YEARS_MEETS: 'La antigüedad institucional comprobable alcanza el mínimo publicado.',
  OPERATING_YEARS_NOT_REQUIRED: 'Las bases estructuradas no exigen una antigüedad operativa mínima.',
  OPERATING_YEARS_MINIMUM_NOT_MET: 'La antigüedad institucional comprobable no alcanza el mínimo publicado.',
  OPERATING_YEARS_BOUNDARY_UNKNOWN: 'El año de constitución disponible no permite confirmar con precisión el mínimo requerido.',
  OPERATING_YEARS_MISSING_ORGANIZATION: 'El perfil institucional no informa un año de constitución suficiente para comparar.',
  OPERATING_YEARS_MISSING_OPPORTUNITY: 'Las bases estructuradas no informan un mínimo de antigüedad suficiente para comparar.',
  PRIOR_EXPERIENCE_NOT_REQUIRED: 'Las bases estructuradas no exigen experiencia previa.',
  PRIOR_EXPERIENCE_HAS_EXPERIENCE: 'El perfil institucional declara experiencia previa.',
  PRIOR_EXPERIENCE_NO_EXPERIENCE: 'El perfil institucional no declara la experiencia previa requerida.',
  PRIOR_EXPERIENCE_MISSING_ORGANIZATION: 'El perfil institucional no contiene información suficiente sobre experiencia previa.',
  PRIOR_EXPERIENCE_MISSING_OPPORTUNITY: 'Las bases estructuradas no informan si exigen experiencia previa.',
  CATEGORIES_MATCH: 'Al menos un área de impacto del proyecto coincide con las áreas publicadas.',
  CATEGORIES_NO_MATCH: 'Las áreas de impacto declaradas no coinciden con las áreas publicadas.',
  CATEGORIES_MISSING_PROJECT: 'El proyecto no tiene áreas de impacto suficientes para comparar.',
  CATEGORIES_MISSING_OPPORTUNITY: 'Las bases estructuradas no informan áreas de impacto suficientes para comparar.',
  BENEFICIARIES_MATCH: 'Al menos una población beneficiaria del proyecto coincide con las bases estructuradas.',
  BENEFICIARIES_NO_MATCH: 'La población beneficiaria declarada no coincide con las bases estructuradas.',
  BENEFICIARIES_MISSING_PROJECT: 'El proyecto no informa suficiente población beneficiaria para comparar.',
  BENEFICIARIES_MISSING_OPPORTUNITY: 'Las bases estructuradas no informan poblaciones beneficiarias suficientes para comparar.',
  PROJECT_TYPE_MATCH: 'Al menos un tipo de proyecto coincide con los contemplados por las bases estructuradas.',
  PROJECT_TYPE_NO_MATCH: 'El tipo de proyecto declarado no coincide con los contemplados por las bases estructuradas.',
  PROJECT_TYPE_MISSING_PROJECT: 'El proyecto no informa un tipo suficiente para comparar.',
  PROJECT_TYPE_MISSING_OPPORTUNITY: 'Las bases estructuradas no informan tipos de proyecto suficientes para comparar.',
  AMOUNT_WITHIN_RANGE: 'La necesidad de financiamiento está dentro del rango publicado.',
  AMOUNT_ABOVE_MAX_PARTIAL: 'El rango publicado cubre solo una parte de la necesidad de financiamiento.',
  AMOUNT_BELOW_MIN: 'La necesidad de financiamiento está por debajo del mínimo publicado.',
  AMOUNT_CURRENCY_MISMATCH: 'La moneda del proyecto no coincide con la moneda publicada por el fondo.',
  AMOUNT_MISSING_PROJECT: 'El proyecto no informa monto y moneda suficientes para comparar.',
  AMOUNT_MISSING_OPPORTUNITY: 'Las bases estructuradas no informan monto y moneda suficientes para comparar.',
}

function parsePage(value: string | null) {
  const parsed = Number(value)
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : 1
}

function clampPercent(value: number) {
  return Math.min(100, Math.max(0, value))
}

function formatPercent(value: number) {
  return new Intl.NumberFormat('es-CL', { maximumFractionDigits: 1 }).format(value)
}

function formatDateTime(value: string | null) {
  if (!value) return 'Sin fecha registrada'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value
  return new Intl.DateTimeFormat('es-CL', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(date)
}

function formatDateOnly(value: string | null) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value ?? '')
  if (!match) return value
  return new Intl.DateTimeFormat('es-CL', { dateStyle: 'medium' }).format(
    new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]), 12),
  )
}

function fundingDeadlineText(
  opportunity: ProjectFundingMatch['fundingOpportunity'],
) {
  if (opportunity.deadlinePrecision === 2 && opportunity.closeAtUtc) {
    const instant = new Date(opportunity.closeAtUtc)
    if (!Number.isNaN(instant.getTime())) {
      const formatted = new Intl.DateTimeFormat('es-CL', {
        dateStyle: 'medium',
        timeStyle: 'short',
        timeZone: 'UTC',
        hourCycle: 'h23',
      }).format(instant)
      return `Cierre exacto: ${formatted} UTC`
    }
  }

  if (opportunity.deadlinePrecision === 1 && opportunity.closeDate) {
    return `Cierre publicado: ${formatDateOnly(opportunity.closeDate)}`
  }

  if (opportunity.deadlinePrecision === 0 &&
      !opportunity.closeDate && !opportunity.closeAtUtc) {
    return 'Convocatoria continua'
  }

  return 'Cierre exacto no informado'
}

function apiErrorMessage(error: unknown, fallback: string) {
  if (!(error instanceof ApiError)) return fallback
  return Object.values(error.problem.errors ?? {}).flat()[0]
    ?? error.problem.detail
    ?? error.problem.title
}

function reasonText(rule: MatchingRuleResult) {
  const normalizedCode = rule.reasonCode.trim().toUpperCase().replace(/[.-]+/g, '_')
  const translated = reasonMessages[normalizedCode]
  if (translated) return translated
  if (rule.dataState === 2) return 'Esta condición no aplica a este caso.'
  return {
    0: `Los datos disponibles coinciden para “${rule.name}”.`,
    1: `Los datos disponibles coinciden parcialmente para “${rule.name}”.`,
    2: `Se detectó una incompatibilidad para “${rule.name}”.`,
    3: `No hay datos suficientes para evaluar “${rule.name}”.`,
  }[rule.outcome]
}

function reasonParameterText(parameters: Record<string, string | null>) {
  const messages: string[] = []
  if (/^\d{1,4}$/.test(parameters.matchCount ?? '')) {
    messages.push(`Coincidencias registradas: ${parameters.matchCount}`)
  }
  const projectCurrency = /^[A-Z]{3}$/.test(parameters.projectCurrency ?? '')
    ? parameters.projectCurrency
    : null
  const opportunityCurrency = /^[A-Z]{3}$/.test(parameters.opportunityCurrency ?? '')
    ? parameters.opportunityCurrency
    : null
  if (projectCurrency || opportunityCurrency) {
    messages.push(`Monedas comparadas: proyecto ${projectCurrency ?? 'sin dato'} · fondo ${opportunityCurrency ?? 'sin dato'}`)
  }
  const yearParameters = [
    ['Años mínimos comprobables', parameters.minimumGuaranteedYears],
    ['Años máximos posibles', parameters.maximumPossibleYears],
    ['Años requeridos', parameters.requiredYears],
  ] as const
  for (const [label, value] of yearParameters) {
    if (/^\d{1,3}$/.test(value ?? '')) messages.push(`${label}: ${value}`)
  }
  return messages
}

function Evidence({ evidence }: { evidence: MatchingRuleEvidence }) {
  const source = evidenceSourceNames[evidence.source.toLocaleLowerCase('es-CL')]
    ?? 'Fuente versionada'
  const field = evidenceFieldNames[evidence.fieldCode.toLocaleLowerCase('es-CL')]
    ?? 'Campo estructurado'
  return (
    <div className="rounded-lg bg-muted/70 p-3 text-xs text-muted-foreground">
      <p><strong className="text-foreground">Evidencia controlada:</strong> {source} · {field}</p>
      {evidence.valueCodes.length > 0 && (
        <p className="mt-1">{evidence.valueCodes.length} valores estructurados considerados.</p>
      )}
    </div>
  )
}

function RuleResult({ rule }: { rule: MatchingRuleResult }) {
  const parameterMessages = reasonParameterText(rule.reasonParameters)
  return (
    <li className="space-y-3 rounded-lg border bg-background p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="flex flex-wrap items-center gap-2">
            <h4 className="font-bold">{rule.name}</h4>
            {rule.isHardGate && (
              <span className="rounded-full bg-muted px-2.5 py-1 text-xs font-semibold">
                Condición excluyente
              </span>
            )}
            {rule.isWarning && (
              <span className="rounded-full bg-amber-100 px-2.5 py-1 text-xs font-semibold text-amber-900 dark:bg-amber-950 dark:text-amber-100">
                Advertencia
              </span>
            )}
          </div>
          <p className="mt-1 text-sm text-muted-foreground">{reasonText(rule)}</p>
        </div>
        <div className="text-right">
          <p className="text-sm font-semibold">{outcomeNames[rule.outcome]}</p>
          <p className="text-xs text-muted-foreground">{dataStateNames[rule.dataState]}</p>
        </div>
      </div>
      {!rule.isHardGate && (
        <p className="text-xs text-muted-foreground">
          Aporte al puntaje: <strong className="text-foreground">{formatPercent(rule.weightedPoints)}</strong>
          {' '}de {formatPercent(rule.weight)} puntos posibles
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
  if (classification === 1) return 'bg-destructive/10 text-destructive'
  return 'bg-muted text-foreground'
}

function MatchResultCard({ match }: { match: ProjectFundingMatch }) {
  const opportunity = match.fundingOpportunity
  return (
    <article aria-labelledby={`match-${opportunity.publicId}`}>
      <Card className={!match.isCurrent ? 'border-amber-500/60' : undefined}>
        <CardHeader className="gap-4 sm:flex sm:flex-row sm:items-start sm:justify-between sm:space-y-0">
          <div>
            <div className="flex flex-wrap items-center gap-2">
              <span className={`rounded-full px-3 py-1 text-xs font-bold ${classificationClass(match.classification)}`}>
                {classificationNames[match.classification]}
              </span>
              {!match.isCurrent && (
                <span className="rounded-full bg-amber-100 px-3 py-1 text-xs font-bold text-amber-900 dark:bg-amber-950 dark:text-amber-100">
                  Resultado desactualizado
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
              Revisar fondo <ArrowRight className="size-4" />
            </Link>
          </Button>
        </CardHeader>
        <CardContent className="space-y-5">
          <div className="grid gap-3 sm:grid-cols-3">
            <div className="rounded-lg border bg-background p-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Puntaje orientativo</p>
              {match.compatibilityScore === null
                ? <p className="mt-1 text-xl font-bold">No aplica</p>
                : <p aria-label={`Puntaje orientativo ${formatPercent(match.compatibilityScore)} de 100`} className="mt-1 text-2xl font-bold">{formatPercent(match.compatibilityScore)}<span className="text-sm text-muted-foreground">/100</span></p>}
            </div>
            <div className="rounded-lg border bg-background p-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Cobertura de datos</p>
              <p className="mt-1 text-2xl font-bold">{formatPercent(match.evidenceCoverage)}%</p>
              <progress aria-label={`Cobertura de datos ${formatPercent(match.evidenceCoverage)}%`} className="mt-2 h-2 w-full accent-primary" max="100" value={clampPercent(match.evidenceCoverage)} />
            </div>
            <div className="rounded-lg border bg-background p-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Condiciones excluyentes</p>
              <p className="mt-1 text-sm font-bold">{hardGateNames[match.hardGateStatus]}</p>
              {match.hardGateStatus === 2 && <p className="mt-1 text-xs text-muted-foreground">Desconocido no cuenta como aprobado.</p>}
            </div>
          </div>

          <div className="flex flex-wrap gap-x-5 gap-y-2 text-xs text-muted-foreground">
            <span>Versión de las bases: {opportunity.contentVersion}</span>
            <span>{fundingDeadlineText(opportunity)}</span>
          </div>

          <details className="group rounded-lg border bg-muted/30 p-4">
            <summary className="cursor-pointer font-bold">
              Ver desglose de {match.ruleResults.length} reglas
            </summary>
            <p className="mt-2 text-sm text-muted-foreground">
              Las condiciones excluyentes se evalúan por separado: un puntaje alto no anula una incompatibilidad ni un dato desconocido.
            </p>
            {match.ruleResults.length > 0 ? (
              <ul className="mt-4 grid gap-3">
                {match.ruleResults.map((rule) => <RuleResult key={rule.code} rule={rule} />)}
              </ul>
            ) : (
              <p className="mt-4 text-sm text-muted-foreground">No se registraron reglas para este resultado.</p>
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
          <span className="rounded-full bg-muted px-2 py-1 text-xs">{runStatusNames[run.status]}</span>
        </div>
        <p className="mt-2 text-xs text-muted-foreground">
          {run.candidateCount} de {run.totalCandidateCount} fondos evaluados · {run.compatibleCount} compatibles · {run.incompatibleCount} incompatibles · {run.insufficientDataCount} sin datos suficientes
        </p>
        {run.isTruncated && <p className="mt-2 text-xs font-semibold text-amber-800 dark:text-amber-200">Comparación acotada; no cubre todo el catálogo.</p>}
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
  const lastPage = Math.max(1, Math.ceil(runs.totalCount / runs.pageSize))
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2"><History className="size-5" /> Historial</CardTitle>
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
          <nav aria-label="Paginación del historial" className="flex items-center justify-between gap-2">
            <Button aria-label="Página anterior del historial" disabled={page <= 1} onClick={() => onPage(page - 1)} size="icon" variant="outline">
              <ChevronLeft className="size-4" />
            </Button>
            <span className="text-xs text-muted-foreground">Página {runs.pageNumber} de {lastPage}</span>
            <Button aria-label="Página siguiente del historial" disabled={page >= lastPage} onClick={() => onPage(page + 1)} size="icon" variant="outline">
              <ChevronRight className="size-4" />
            </Button>
          </nav>
        )}
      </CardContent>
    </Card>
  )
}

function MatchingResults({ detail }: { detail: MatchingRunDetail }) {
  const run = detail.run
  const current = run.isCurrent
  return (
    <section aria-labelledby="matching-results-title" className="space-y-5">
      <Card>
        <CardContent className="space-y-4 p-5">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p className="text-xs font-bold uppercase tracking-[0.16em] text-primary">Resultado reproducible</p>
              <h2 className="mt-1 text-2xl font-bold" id="matching-results-title">Compatibilidad orientativa</h2>
              <p className="mt-1 text-sm text-muted-foreground">Calculada {formatDateTime(run.completedAtUtc ?? run.createdAtUtc)}</p>
            </div>
            <span className={`rounded-full px-3 py-1 text-xs font-bold ${current ? 'bg-accent text-accent-foreground' : 'bg-amber-100 text-amber-900 dark:bg-amber-950 dark:text-amber-100'}`}>
              {current ? 'Versiones vigentes' : 'Contiene versiones anteriores'}
            </span>
          </div>
          <dl className="grid gap-3 rounded-lg bg-muted p-4 text-sm sm:grid-cols-3">
            <div><dt className="text-muted-foreground">Proyecto</dt><dd className="font-bold">v{run.projectVersion}</dd></div>
            <div><dt className="text-muted-foreground">Perfil institucional</dt><dd className="font-bold">v{run.organizationProfileVersion}</dd></div>
            <div><dt className="text-muted-foreground">Motor y reglas</dt><dd className="font-bold">{run.engineVersion} · {run.matchingProfile.name} v{run.matchingProfile.version}</dd></div>
          </dl>
          <p className="text-xs text-muted-foreground">Catálogo considerado al {formatDateTime(run.catalogSnapshotAtUtc)}.</p>
          {run.isTruncated && (
            <p className="flex items-start gap-2 rounded-lg bg-amber-100 p-3 text-sm text-amber-950 dark:bg-amber-950 dark:text-amber-100" role="status">
              <CircleAlert className="mt-0.5 size-4 shrink-0" />
              Comparación acotada: se evaluaron {run.candidateCount} de {run.totalCandidateCount} fondos candidatos. Este resultado no es una revisión exhaustiva del catálogo.
            </p>
          )}
          <p className="flex items-start gap-2 rounded-lg border p-3 text-sm text-muted-foreground">
            <Info className="mt-0.5 size-4 shrink-0 text-primary" aria-hidden="true" />
            {detail.disclaimer || matchingDisclaimer}
          </p>
        </CardContent>
      </Card>

      {detail.items.length === 0 ? (
        <Card>
          <CardContent className="space-y-3 p-10 text-center">
            <DatabaseZap className="mx-auto size-9 text-muted-foreground" />
            <h3 className="text-xl font-bold">No hubo fondos para comparar</h3>
            <p className="text-sm text-muted-foreground">No encontramos oportunidades publicadas y activas dentro del conjunto evaluable.</p>
            <Button asChild variant="outline"><Link to="/opportunities">Revisar catálogo</Link></Button>
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
  return (
    <Card>
      <CardContent className="space-y-4 p-8 text-center">
        <Target className="mx-auto size-9 text-primary" />
        <h1 className="text-2xl font-bold">Primero crea tu organización</h1>
        <p className="text-sm text-muted-foreground">El cálculo necesita un proyecto y el perfil institucional de su organización.</p>
        <Button asChild><Link to="/onboarding">Crear organización</Link></Button>
      </CardContent>
    </Card>
  )
}

function NoProjects() {
  return (
    <Card>
      <CardContent className="space-y-4 p-10 text-center">
        <Target className="mx-auto size-9 text-primary" />
        <h2 className="text-xl font-bold">Necesitas un proyecto</h2>
        <p className="text-sm text-muted-foreground">Crea un proyecto antes de calcular su compatibilidad con fondos.</p>
        <Button asChild><Link to="/projects">Ir a proyectos</Link></Button>
      </CardContent>
    </Card>
  )
}

export function MatchingWorkspacePage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const queryClient = useQueryClient()
  const command = useRef<{ projectId: string; key: string } | null>(null)
  const [calculationNotice, setCalculationNotice] = useState('')
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
        ? 'Se recuperó de forma segura el mismo cálculo.'
        : 'El cálculo terminó correctamente.')
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
    return <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" /> Cargando espacio de compatibilidad…</p>
  }
  if (organizations.isError) {
    return (
      <Card className="border-destructive/40">
        <CardContent className="space-y-3 p-8" role="alert">
          <CircleAlert className="size-8 text-destructive" />
          <h1 className="text-xl font-bold">No pudimos cargar tu organización</h1>
          <Button onClick={() => void organizations.refetch()} variant="outline">Reintentar</Button>
        </CardContent>
      </Card>
    )
  }
  if (!organization) return <OrganizationRequired />

  return (
    <div className="space-y-6">
      <header>
        <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">FASE 9A · Reglas determinísticas</p>
        <h1 className="mt-1 text-3xl font-bold">Compatibilidad por proyecto</h1>
        <p className="mt-2 max-w-3xl text-muted-foreground">
          Compara cada proyecto con las condiciones estructuradas de fondos activos. El cálculo es reproducible, no usa IA y no decide si puedes postular.
        </p>
      </header>

      <Card>
        <CardContent className="space-y-5 p-5 sm:p-6">
          <div className="flex items-start gap-3 rounded-lg bg-muted p-4 text-sm">
            <Scale className="mt-0.5 size-5 shrink-0 text-primary" aria-hidden="true" />
            <div>
              <p className="font-bold">Compatibilidad orientativa, no elegibilidad</p>
              <p className="mt-1 text-muted-foreground">Las condiciones excluyentes y los datos desconocidos se muestran separados del puntaje. Revisa siempre las bases y la fuente oficial.</p>
            </div>
          </div>

          {projects.isPending && <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-4 animate-spin" /> Cargando proyectos…</p>}
          {projects.isError && (
            <div className="space-y-3" role="alert">
              <p className="text-sm text-destructive">No pudimos cargar tus proyectos.</p>
              <Button onClick={() => void projects.refetch()} size="sm" variant="outline">Reintentar</Button>
            </div>
          )}
          {projects.data && availableProjects.length === 0 && <NoProjects />}
          {availableProjects.length > 0 && (
            <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-end">
              <label className="grid gap-1.5 text-sm font-semibold" htmlFor="matching-project">
                Proyecto a comparar
                <select
                  className={selectClass}
                  disabled={calculation.isPending}
                  id="matching-project"
                  onChange={(event) => selectProject(event.target.value)}
                  value={selectedProject?.publicId ?? ''}
                >
                  <option value="">Selecciona un proyecto</option>
                  {availableProjects.map((project) => (
                    <option key={project.publicId} value={project.publicId}>
                      {project.title}{project.publicationStatus === 4 ? ' (Archivado)' : ''}
                    </option>
                  ))}
                </select>
                <span className="text-xs font-normal text-muted-foreground">
                  {selectedProject?.publicationStatus === 4
                    ? 'Proyecto archivado: puedes consultar su historial, pero no iniciar cálculos nuevos.'
                    : 'Los proyectos archivados conservan su historial, pero no admiten cálculos nuevos.'}
                </span>
              </label>
              <Button
                disabled={!canCalculate || calculation.isPending}
                onClick={() => selectedProject && calculation.mutate(selectedProject)}
                type="button"
              >
                {calculation.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <RefreshCw className="size-4" />}
                {runs.data?.items.length ? 'Calcular versión actual' : 'Calcular compatibilidad'}
              </Button>
            </div>
          )}

          {calculation.isError && (
            <div className="space-y-3 rounded-lg bg-destructive/10 p-4 text-sm text-destructive" role="alert">
              <div className="flex items-start gap-2">
                <ShieldAlert className="mt-0.5 size-4 shrink-0" />
                <div>
                  <h2 className="font-bold">No pudimos completar el cálculo</h2>
                  <p className="mt-1">{apiErrorMessage(calculation.error, 'Comprueba la conexión e intenta nuevamente.')}</p>
                </div>
              </div>
              <div className="flex flex-wrap gap-2">
                {canCalculate && <Button onClick={retryCalculation} size="sm" variant="outline">Reintentar cálculo</Button>}
                <Button asChild size="sm" variant="ghost"><Link to="/organization/profile">Revisar perfil</Link></Button>
                {selectedProject && <Button asChild size="sm" variant="ghost"><Link to={`/projects/${selectedProject.publicId}`}>Revisar proyecto</Link></Button>}
              </div>
            </div>
          )}
          {calculationNotice && <p className="flex items-center gap-2 rounded-lg bg-accent p-3 text-sm font-medium text-accent-foreground" role="status"><CheckCircle2 className="size-4" /> {calculationNotice}</p>}
        </CardContent>
      </Card>

      {!selectedProject && availableProjects.length > 0 && (
        <Card>
          <CardContent className="space-y-3 p-10 text-center">
            <Target className="mx-auto size-9 text-muted-foreground" />
            <h2 className="text-xl font-bold">Elige un proyecto</h2>
            <p className="text-sm text-muted-foreground">Cada proyecto tiene territorios, beneficiarios y necesidades de financiamiento diferentes.</p>
          </CardContent>
        </Card>
      )}

      {selectedProject && runs.isPending && (
        <Card><CardContent className="flex items-center gap-2 p-8" role="status"><LoaderCircle className="size-5 animate-spin" /> Cargando cálculos anteriores…</CardContent></Card>
      )}
      {selectedProject && runs.isError && (
        <Card className="border-destructive/40">
          <CardContent className="space-y-3 p-8" role="alert">
            <CircleAlert className="size-8 text-destructive" />
            <h2 className="text-xl font-bold">No pudimos consultar el historial</h2>
            <p className="text-sm text-muted-foreground">{apiErrorMessage(runs.error, 'Comprueba la conexión e intenta nuevamente.')}</p>
            <Button onClick={() => void runs.refetch()} variant="outline">Reintentar</Button>
          </CardContent>
        </Card>
      )}
      {selectedProject && runs.data?.items.length === 0 && !calculation.isPending && !calculation.isSuccess && (
        <Card>
          <CardContent className="space-y-3 p-10 text-center">
            <Clock3 className="mx-auto size-9 text-muted-foreground" />
            <h2 className="text-xl font-bold">Aún no hay cálculos para este proyecto</h2>
            <p className="text-sm text-muted-foreground">
              {canCalculate
                ? 'Usa “Calcular compatibilidad” para crear un resultado con las versiones actuales.'
                : 'Este proyecto archivado no tiene cálculos históricos.'}
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
            {detail.isPending && <Card><CardContent className="flex items-center gap-2 p-8" role="status"><LoaderCircle className="size-5 animate-spin" /> Cargando desglose…</CardContent></Card>}
            {detail.isError && (
              <Card className="border-destructive/40">
                <CardContent className="space-y-3 p-8" role="alert">
                  <CircleAlert className="size-8 text-destructive" />
                  <h2 className="text-xl font-bold">No pudimos cargar este cálculo</h2>
                  <p className="text-sm text-muted-foreground">{apiErrorMessage(detail.error, 'Comprueba la conexión e intenta nuevamente.')}</p>
                  <Button onClick={() => void detail.refetch()} variant="outline">Reintentar</Button>
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
