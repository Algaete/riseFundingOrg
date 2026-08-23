import { zodResolver } from '@hookform/resolvers/zod'
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  ArrowLeft,
  CalendarDays,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  CircleAlert,
  CircleDollarSign,
  ExternalLink,
  FileSearch,
  LoaderCircle,
  Plus,
  RefreshCw,
  Save,
  Search,
} from 'lucide-react'
import { type FormEvent, useEffect, useState, type ReactNode } from 'react'
import { useForm } from 'react-hook-form'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { z } from 'zod'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import {
  adminErrorMessage,
  adminValidationMessages,
  EditorialWorkflowPanel,
  formatAdminDate,
  isConcurrencyConflict,
  PublicationStatusBadge,
  publicationStatusLabels,
} from '@/features/funding/admin-editorial'
import {
  adminFundersApi,
  adminFundingOpportunitiesApi,
  adminFundingSourcesApi,
  type AdminFundingOpportunityDetail,
  type AmountStatus,
  type DeadlinePrecision,
  type DeadlineType,
  type FundingOpportunityWriteInput,
  type GeographicScope,
  type PublicationStatus,
  type RemoteApplication,
} from '@/features/funding/admin-funding-api'
import { executeEditorialCommand } from '@/features/funding/editorial-command-cache'
import { organizationApi, type CatalogOption } from '@/features/organizations/organization-api'

const listPageSize = 20
const funderChoicePageSize = 20
const inputClass = 'h-10 w-full rounded-lg border bg-background px-3 text-sm'
const textareaClass = 'min-h-28 w-full rounded-lg border bg-background px-3 py-2 text-sm'
const optionalHttpUrl = z.string().trim().refine(
  (value) => value === '' || /^https?:\/\/[^\s]+$/i.test(value),
  'Ingresa una URL completa que comience con http:// o https://.',
)
const requiredHttpUrl = z.string().trim().refine(
  (value) => /^https?:\/\/[^\s]+$/i.test(value),
  'Ingresa la URL oficial completa que comience con http:// o https://.',
)
const optionalNonNegativeNumber = z.string().refine(
  (value) => value === '' || (Number.isFinite(Number(value)) && Number(value) >= 0),
  'Ingresa un número igual o mayor que cero.',
)
const optionalPositiveInteger = z.string().refine(
  (value) => value === '' || (Number.isInteger(Number(value)) && Number(value) > 0),
  'Ingresa un identificador entero válido.',
)
const optionalNonNegativeInteger = z.string().refine(
  (value) => value === '' || (Number.isInteger(Number(value)) && Number(value) >= 0),
  'Ingresa un número entero igual o mayor que cero.',
)
const optionalPercentage = z.string().refine(
  (value) => value === '' || (Number.isFinite(Number(value)) && Number(value) >= 0 && Number(value) <= 100),
  'Ingresa un porcentaje entre 0 y 100.',
)
const nullableBoolean = z.enum(['', 'true', 'false'])
const amountStatus = z.enum(['0', '1', '2'])
const deadlineType = z.enum(['0', '1', '2'])
const deadlinePrecision = z.enum(['0', '1', '2'])
const geographicScope = z.enum(['0', '1', '2'])
const remoteApplication = z.enum(['0', '1', '2'])

const opportunitySchema = z.object({
  title: z.string().trim().min(3, 'El título debe tener al menos 3 caracteres.').max(350),
  summary: z.string().trim().max(2000),
  description: z.string().trim().max(50_000),
  sponsorName: z.string().trim().min(2, 'Indica el organismo patrocinador.').max(300),
  sponsorUrl: optionalHttpUrl,
  applicationUrl: optionalHttpUrl,
  externalId: z.string().trim().max(250),
  fundingSourceId: z.string().refine((value) => Number.isInteger(Number(value)) && Number(value) > 0, 'Selecciona una fuente.'),
  issuerCountryId: optionalPositiveInteger,
  fundingTypeId: optionalPositiveInteger,
  currency: z.string().trim().refine((value) => value === '' || /^[A-Za-z]{3}$/.test(value), 'Usa un código ISO de tres letras.'),
  minimumAmount: optionalNonNegativeNumber,
  maximumAmount: optionalNonNegativeNumber,
  amountStatus,
  openDate: z.string(),
  closeDate: z.string(),
  closeAtUtc: z.string(),
  deadlineTimeZoneId: z.string().trim().max(100),
  deadlineType,
  deadlinePrecision,
  eligibilityDescription: z.string().trim().max(30_000),
  requirements: z.string().trim().max(30_000),
  objectives: z.string().trim().max(30_000),
  allowedActivities: z.string().trim().max(30_000),
  excludedActivities: z.string().trim().max(30_000),
  restrictions: z.string().trim().max(30_000),
  targetOrganizationsDescription: z.string().trim().max(2000),
  targetPopulationsDescription: z.string().trim().max(2000),
  minimumOperatingYears: optionalNonNegativeInteger,
  requiresLegalEntity: nullableBoolean,
  requiresPriorExperience: nullableBoolean,
  requiresCofunding: nullableBoolean,
  cofundingPercentage: optionalPercentage,
  geographicScope,
  remoteApplication,
  sourceUrl: requiredHttpUrl,
  lastVerifiedAtUtc: z.string(),
  funders: z.array(z.object({ funderId: z.string().uuid(), role: z.union([z.literal(1), z.literal(2), z.literal(3)]) })),
  countryIds: z.array(z.number().int().positive()),
  regionIds: z.array(z.number().int().positive()),
  categoryIds: z.array(z.number().int().positive()),
  beneficiaryTypeIds: z.array(z.number().int().positive()),
  projectTypeIds: z.array(z.number().int().positive()),
}).superRefine((values, context) => {
  if (values.minimumAmount && values.maximumAmount && Number(values.minimumAmount) > Number(values.maximumAmount)) {
    context.addIssue({ code: 'custom', message: 'El monto mínimo no puede superar al máximo.', path: ['maximumAmount'] })
  }
  if (values.openDate && values.closeDate && values.openDate > values.closeDate) {
    context.addIssue({ code: 'custom', message: 'El cierre no puede ser anterior a la apertura.', path: ['closeDate'] })
  }
  if (values.lastVerifiedAtUtc) {
    const verifiedAt = new Date(values.lastVerifiedAtUtc)
    if (Number.isNaN(verifiedAt.getTime())) {
      context.addIssue({ code: 'custom', message: 'Ingresa una fecha de verificación válida.', path: ['lastVerifiedAtUtc'] })
    } else if (verifiedAt.getTime() > Date.now() + 5 * 60_000) {
      context.addIssue({ code: 'custom', message: 'La última verificación no puede estar en el futuro.', path: ['lastVerifiedAtUtc'] })
    }
  }
  const hasAmount = Boolean(values.minimumAmount || values.maximumAmount)
  if (values.amountStatus === '1' && (!hasAmount || !values.currency)) {
    context.addIssue({ code: 'custom', message: 'Un monto especificado requiere moneda y al menos un valor.', path: ['amountStatus'] })
  }
  if (values.amountStatus !== '1' && (hasAmount || values.currency)) {
    context.addIssue({ code: 'custom', message: 'Los montos desconocidos o no informados no admiten moneda ni valores.', path: ['amountStatus'] })
  }
  const fixedDeadline = values.deadlineType === '1'
  if (!fixedDeadline && (values.deadlinePrecision !== '0' || values.closeDate || values.closeAtUtc)) {
    context.addIssue({ code: 'custom', message: 'Un cierre desconocido o continuo no admite fecha ni hora.', path: ['deadlineType'] })
  }
  if (fixedDeadline && values.deadlinePrecision === '0') {
    context.addIssue({ code: 'custom', message: 'Selecciona si el cierre tiene fecha o fecha y hora.', path: ['deadlinePrecision'] })
  }
  if (fixedDeadline && values.deadlinePrecision === '1' && (!values.closeDate || values.closeAtUtc)) {
    context.addIssue({ code: 'custom', message: 'El cierre por fecha requiere solo la fecha de cierre.', path: ['closeDate'] })
  }
  if (fixedDeadline && values.deadlinePrecision === '2') {
    if (!values.closeDate || !values.closeAtUtc || !values.deadlineTimeZoneId.trim()) {
      context.addIssue({ code: 'custom', message: 'La fecha, hora UTC y zona horaria son obligatorias.', path: ['closeAtUtc'] })
    } else {
      const dateAtZone = utcDateInTimeZone(values.closeAtUtc, values.deadlineTimeZoneId.trim())
      if (dateAtZone === null) {
        context.addIssue({ code: 'custom', message: 'Usa una zona IANA válida, por ejemplo America/Santiago.', path: ['deadlineTimeZoneId'] })
      } else if (dateAtZone !== values.closeDate) {
        context.addIssue({ code: 'custom', message: 'La hora UTC no corresponde a la fecha de cierre en la zona indicada.', path: ['closeAtUtc'] })
      }
    }
  }
  if (values.requiresCofunding === 'true' && (!values.cofundingPercentage || Number(values.cofundingPercentage) <= 0)) {
    context.addIssue({ code: 'custom', message: 'Indica un porcentaje mayor que cero cuando se exige cofinanciamiento.', path: ['cofundingPercentage'] })
  }
  if (values.requiresCofunding !== 'true' && values.cofundingPercentage !== '' && Number(values.cofundingPercentage) !== 0) {
    context.addIssue({ code: 'custom', message: 'El porcentaje solo corresponde cuando se exige cofinanciamiento.', path: ['cofundingPercentage'] })
  }
  if (values.geographicScope === '1' && values.countryIds.length === 0) {
    context.addIssue({ code: 'custom', message: 'El alcance específico requiere al menos un país.', path: ['countryIds'] })
  } else if (values.geographicScope !== '1' && (values.countryIds.length > 0 || values.regionIds.length > 0)) {
    context.addIssue({ code: 'custom', message: 'Solo el alcance específico admite países o regiones.', path: ['countryIds'] })
  }
  if (values.funders.filter((funder) => funder.role === 1).length !== 1) {
    context.addIssue({ code: 'custom', message: 'Selecciona exactamente un financiador principal.', path: ['funders'] })
  }
})

type OpportunityFormValues = z.infer<typeof opportunitySchema>

function Field({ children, error, hint, label }: { children: ReactNode; error?: string; hint?: string; label: string }) {
  return (
    <label className="grid gap-1.5 text-sm font-semibold">
      <span>{label}</span>
      {children}
      {hint && <span className="text-xs font-normal text-muted-foreground">{hint}</span>}
      {error && <span className="text-xs font-normal text-destructive">{error}</span>}
    </label>
  )
}

function MultiChoice({
  items,
  label,
  onChange,
  selected,
}: {
  items: CatalogOption<number>[]
  label: string
  onChange: (value: number[]) => void
  selected: number[]
}) {
  return (
    <fieldset className="space-y-2">
      <legend className="text-sm font-semibold">{label}</legend>
      {items.length === 0
        ? <p className="text-sm text-muted-foreground">No hay opciones configuradas.</p>
        : <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-3">
            {items.map((item) => (
              <label className="flex cursor-pointer items-center gap-2 rounded-lg border bg-background px-3 py-2 text-sm" key={item.id}>
                <input
                  checked={selected.includes(item.id)}
                  onChange={() => onChange(selected.includes(item.id) ? selected.filter((id) => id !== item.id) : [...selected, item.id])}
                  type="checkbox"
                />
                {item.name}
              </label>
            ))}
          </div>}
    </fieldset>
  )
}

function toUtcDateTimeInput(value: string | null) {
  if (!value) return ''
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  return date.toISOString().slice(0, 23)
}

function fromUtcDateTimeInput(value: string) {
  return value ? new Date(`${value}Z`).toISOString() : null
}

function toLocalDateTimeInput(value: string | null) {
  if (!value) return ''
  const instant = new Date(value)
  if (Number.isNaN(instant.getTime())) return ''
  const localTime = new Date(instant.getTime() - instant.getTimezoneOffset() * 60_000)
  return localTime.toISOString().slice(0, 23)
}

function fromLocalDateTimeInput(value: string) {
  if (!value) return null
  const instant = new Date(value)
  return Number.isNaN(instant.getTime()) ? null : instant.toISOString()
}

function currentLocalDateTimeInput() {
  return toLocalDateTimeInput(new Date().toISOString())
}

function utcDateInTimeZone(value: string, timeZone: string) {
  const instant = new Date(`${value}Z`)
  if (Number.isNaN(instant.getTime())) return null
  try {
    const parts = new Intl.DateTimeFormat('en-US', {
      day: '2-digit', month: '2-digit', timeZone, year: 'numeric',
    }).formatToParts(instant)
    const part = (type: Intl.DateTimeFormatPartTypes) => parts.find((valuePart) => valuePart.type === type)?.value
    const year = part('year')
    const month = part('month')
    const day = part('day')
    return year && month && day ? `${year}-${month}-${day}` : null
  } catch {
    return null
  }
}

function nullableBooleanValue(value: '' | 'true' | 'false') {
  return value === '' ? null : value === 'true'
}

function emptyOpportunity(): OpportunityFormValues {
  return {
    title: '', summary: '', description: '', sponsorName: '', sponsorUrl: '', applicationUrl: '',
    externalId: '', fundingSourceId: '', issuerCountryId: '', fundingTypeId: '', currency: '', minimumAmount: '',
    maximumAmount: '', amountStatus: '0', openDate: '', closeDate: '', closeAtUtc: '', deadlineTimeZoneId: '',
    deadlineType: '0', deadlinePrecision: '0', eligibilityDescription: '', requirements: '', objectives: '',
    allowedActivities: '', excludedActivities: '', restrictions: '', targetOrganizationsDescription: '',
    targetPopulationsDescription: '', minimumOperatingYears: '', requiresLegalEntity: '',
    requiresPriorExperience: '', requiresCofunding: '', cofundingPercentage: '', geographicScope: '0',
    remoteApplication: '0', sourceUrl: '', lastVerifiedAtUtc: '', funders: [],
    countryIds: [], regionIds: [], categoryIds: [], beneficiaryTypeIds: [], projectTypeIds: [],
  }
}

function toFormValues(item?: AdminFundingOpportunityDetail): OpportunityFormValues {
  if (!item) return emptyOpportunity()
  return {
    title: item.title,
    summary: item.summary ?? '',
    description: item.description ?? '',
    sponsorName: item.sponsorName,
    sponsorUrl: item.sponsorUrl ?? '',
    applicationUrl: item.applicationUrl ?? '',
    externalId: item.externalId ?? '',
    fundingSourceId: String(item.fundingSourceId),
    issuerCountryId: item.issuerCountryId?.toString() ?? '',
    fundingTypeId: item.fundingTypeId?.toString() ?? '',
    currency: item.currency ?? '',
    minimumAmount: item.minimumAmount?.toString() ?? '',
    maximumAmount: item.maximumAmount?.toString() ?? '',
    amountStatus: String(item.amountStatus) as `${AmountStatus}`,
    openDate: item.openDate ?? '',
    closeDate: item.closeDate ?? '',
    closeAtUtc: toUtcDateTimeInput(item.closeAtUtc),
    deadlineTimeZoneId: item.deadlineTimeZoneId ?? '',
    deadlineType: String(item.deadlineType) as `${DeadlineType}`,
    deadlinePrecision: String(item.deadlinePrecision) as `${DeadlinePrecision}`,
    eligibilityDescription: item.eligibilityDescription ?? '',
    requirements: item.requirements ?? '',
    objectives: item.objectives ?? '',
    allowedActivities: item.allowedActivities ?? '',
    excludedActivities: item.excludedActivities ?? '',
    restrictions: item.restrictions ?? '',
    targetOrganizationsDescription: item.targetOrganizationsDescription ?? '',
    targetPopulationsDescription: item.targetPopulationsDescription ?? '',
    minimumOperatingYears: item.minimumOperatingYears?.toString() ?? '',
    requiresLegalEntity: item.requiresLegalEntity === null ? '' : String(item.requiresLegalEntity) as 'true' | 'false',
    requiresPriorExperience: item.requiresPriorExperience === null ? '' : String(item.requiresPriorExperience) as 'true' | 'false',
    requiresCofunding: item.requiresCofunding === null ? '' : String(item.requiresCofunding) as 'true' | 'false',
    cofundingPercentage: item.cofundingPercentage?.toString() ?? '',
    geographicScope: String(item.geographicScope) as `${GeographicScope}`,
    remoteApplication: String(item.remoteApplication) as `${RemoteApplication}`,
    sourceUrl: item.sourceUrl ?? '',
    lastVerifiedAtUtc: toLocalDateTimeInput(item.lastVerifiedAtUtc),
    funders: item.funders.map(({ funderId, role }) => ({ funderId, role })),
    countryIds: item.countryIds,
    regionIds: item.regionIds,
    categoryIds: item.categoryIds,
    beneficiaryTypeIds: item.beneficiaryTypeIds,
    projectTypeIds: item.projectTypeIds,
  }
}

function nullableText(value: string) {
  return value.trim() || null
}

function nullableNumber(value: string) {
  return value === '' ? null : Number(value)
}

function hostname(value: string) {
  try {
    const parsed = new URL(value.trim())
    return parsed.protocol === 'https:' || parsed.protocol === 'http:'
      ? parsed.hostname.toLocaleLowerCase()
      : null
  } catch {
    return null
  }
}

function toWriteInput(values: OpportunityFormValues): FundingOpportunityWriteInput {
  return {
    title: values.title.trim(),
    summary: nullableText(values.summary),
    description: nullableText(values.description),
    sponsorName: values.sponsorName.trim(),
    sponsorUrl: nullableText(values.sponsorUrl),
    applicationUrl: nullableText(values.applicationUrl),
    externalId: nullableText(values.externalId),
    fundingSourceId: Number(values.fundingSourceId),
    issuerCountryId: nullableNumber(values.issuerCountryId),
    fundingTypeId: nullableNumber(values.fundingTypeId),
    currency: nullableText(values.currency)?.toUpperCase() ?? null,
    minimumAmount: nullableNumber(values.minimumAmount),
    maximumAmount: nullableNumber(values.maximumAmount),
    amountStatus: Number(values.amountStatus) as AmountStatus,
    openDate: nullableText(values.openDate),
    closeDate: nullableText(values.closeDate),
    closeAtUtc: fromUtcDateTimeInput(values.closeAtUtc),
    deadlineTimeZoneId: nullableText(values.deadlineTimeZoneId),
    deadlineType: Number(values.deadlineType) as DeadlineType,
    deadlinePrecision: Number(values.deadlinePrecision) as DeadlinePrecision,
    eligibilityDescription: nullableText(values.eligibilityDescription),
    requirements: nullableText(values.requirements),
    objectives: nullableText(values.objectives),
    allowedActivities: nullableText(values.allowedActivities),
    excludedActivities: nullableText(values.excludedActivities),
    restrictions: nullableText(values.restrictions),
    targetOrganizationsDescription: nullableText(values.targetOrganizationsDescription),
    targetPopulationsDescription: nullableText(values.targetPopulationsDescription),
    minimumOperatingYears: nullableNumber(values.minimumOperatingYears),
    requiresLegalEntity: nullableBooleanValue(values.requiresLegalEntity),
    requiresPriorExperience: nullableBooleanValue(values.requiresPriorExperience),
    requiresCofunding: nullableBooleanValue(values.requiresCofunding),
    cofundingPercentage: nullableNumber(values.cofundingPercentage),
    geographicScope: Number(values.geographicScope) as GeographicScope,
    remoteApplication: Number(values.remoteApplication) as RemoteApplication,
    sourceUrl: values.sourceUrl.trim(),
    lastVerifiedAtUtc: fromLocalDateTimeInput(values.lastVerifiedAtUtc),
    funders: values.funders,
    countryIds: values.countryIds,
    regionIds: values.regionIds,
    categoryIds: values.categoryIds,
    beneficiaryTypeIds: values.beneficiaryTypeIds,
    projectTypeIds: values.projectTypeIds,
  }
}

interface FunderChoice {
  funderId: string
  name: string
  publicationStatus?: PublicationStatus
}

function FundingPartnerChoices({
  error,
  funders,
  isFetching,
  onChange,
  onPageChange,
  onSearchChange,
  page,
  pageSize,
  search,
  selected,
  totalCount,
}: {
  funders: FunderChoice[]
  error?: string
  isFetching: boolean
  onChange: (value: OpportunityFormValues['funders']) => void
  onPageChange: (page: number) => void
  onSearchChange: (query: string) => void
  page: number
  pageSize: number
  search: string
  selected: OpportunityFormValues['funders']
  totalCount: number
}) {
  const lastPage = Math.max(1, Math.ceil(totalCount / pageSize))
  return (
    <fieldset className="space-y-3">
      <div><legend className="text-sm font-semibold">Financiadores asociados</legend><p className="mt-1 text-xs text-muted-foreground">Selecciona exactamente un financiador principal para guardar.</p></div>
      <label className="grid gap-1.5 text-sm font-semibold">
        Buscar financiador
        <span className="relative">
          <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            className="pl-9"
            onChange={(event) => onSearchChange(event.target.value)}
            placeholder="Busca por nombre o alias"
            value={search}
          />
        </span>
      </label>
      {isFetching && <p className="flex items-center gap-2 text-xs text-muted-foreground" role="status"><LoaderCircle className="size-3.5 animate-spin" /> Buscando financiadores…</p>}
      {funders.length === 0 ? (
        <p className="rounded-lg border p-3 text-sm">
          {search.trim()
            ? 'No encontramos financiadores para esta búsqueda.'
            : <>No hay financiadores disponibles. <Link className="font-semibold text-primary underline" to="/admin/funders/new">Crea uno</Link>.</>}
        </p>
      ) : (
        <div className="grid gap-2 lg:grid-cols-2">
          {funders.map((funder) => {
            const association = selected.find((value) => value.funderId === funder.funderId)
            return (
              <div className="rounded-lg border bg-background px-3 py-2" key={funder.funderId}>
                <label className="flex cursor-pointer items-center gap-2 text-sm">
                  <input
                    checked={Boolean(association)}
                    onChange={() => {
                      if (association) onChange(selected.filter((value) => value.funderId !== funder.funderId))
                      else onChange([...selected, { funderId: funder.funderId, role: selected.length === 0 ? 1 : 2 }])
                    }}
                    type="checkbox"
                  />
                  <span className="font-medium">{funder.name}</span>
                  {funder.publicationStatus !== undefined && <PublicationStatusBadge status={funder.publicationStatus} />}
                </label>
                {association && (
                  <label className="mt-2 grid gap-1 pl-6 text-xs font-semibold">
                    Rol
                    <select
                      className="h-9 rounded-lg border bg-background px-2 text-sm font-normal"
                      onChange={(event) => onChange(selected.map((value) => value.funderId === funder.funderId ? { ...value, role: Number(event.target.value) as 1 | 2 | 3 } : value))}
                      value={association.role}
                    >
                      <option value={1}>Principal</option>
                      <option value={2}>Cofinanciador</option>
                      <option value={3}>Administrador</option>
                    </select>
                  </label>
                )}
              </div>
            )
          })}
        </div>
      )}
      {(lastPage > 1 || page > 1) && (
        <nav aria-label="Páginas de financiadores" className="flex items-center justify-end gap-3">
          <Button disabled={page <= 1 || isFetching} onClick={() => onPageChange(page - 1)} size="sm" type="button" variant="outline"><ChevronLeft className="size-4" /> Anterior</Button>
          <span className="text-xs text-muted-foreground">Página {page} de {lastPage}</span>
          <Button disabled={page >= lastPage || isFetching} onClick={() => onPageChange(page + 1)} size="sm" type="button" variant="outline">Siguiente <ChevronRight className="size-4" /></Button>
        </nav>
      )}
      {error && <p className="text-xs text-destructive">{error}</p>}
    </fieldset>
  )
}

function AdminOpportunityForm({
  item,
  onDirtyChange,
}: {
  item?: AdminFundingOpportunityDetail
  onDirtyChange?: (dirty: boolean) => void
}) {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const [funderSearch, setFunderSearch] = useState('')
  const [debouncedFunderSearch, setDebouncedFunderSearch] = useState('')
  const [funderPage, setFunderPage] = useState(1)
  const [saveMessage, setSaveMessage] = useState<string | null>(null)
  const [knownFunders, setKnownFunders] = useState<FunderChoice[]>(() =>
    (item?.funders ?? []).map((funder) => ({ funderId: funder.funderId, name: funder.name })),
  )
  const catalogs = useQuery({ queryKey: ['organization-catalogs'], queryFn: ({ signal }) => organizationApi.catalogs(signal), staleTime: 60 * 60 * 1000 })
  const funders = useQuery({
    queryKey: ['admin-funders', 'editor-options', debouncedFunderSearch, funderPage],
    queryFn: ({ signal }) => adminFundersApi.list({ query: debouncedFunderSearch || undefined, page: funderPage, pageSize: funderChoicePageSize }, signal),
    placeholderData: keepPreviousData,
    staleTime: 30_000,
  })
  const sources = useQuery({ queryKey: ['admin-funding-sources'], queryFn: ({ signal }) => adminFundingSourcesApi.list(signal), staleTime: 60_000 })
  const form = useForm<OpportunityFormValues>({ resolver: zodResolver(opportunitySchema), defaultValues: toFormValues(item) })

  useEffect(() => { form.reset(toFormValues(item)) }, [form, item])
  useEffect(() => { onDirtyChange?.(form.formState.isDirty) }, [form.formState.isDirty, onDirtyChange])
  useEffect(() => {
    const timeout = window.setTimeout(() => {
      setDebouncedFunderSearch(funderSearch.trim())
      setFunderPage(1)
    }, 300)
    return () => window.clearTimeout(timeout)
  }, [funderSearch])
  useEffect(() => {
    if (!funders.data) return
    setKnownFunders((current) => {
      const merged = new Map(current.map((funder) => [funder.funderId, funder]))
      for (const funder of funders.data.items) merged.set(funder.funderId, funder)
      return Array.from(merged.values())
    })
  }, [funders.data])

  const save = useMutation({
    mutationFn: (values: OpportunityFormValues) => {
      setSaveMessage(null)
      const input = toWriteInput(values)
      const scope = item ? `opportunity:${item.opportunityId}:update` : 'opportunity:create'
      return executeEditorialCommand(scope, { eTag: item?.eTag, input }, (idempotencyKey) => (
        item
          ? adminFundingOpportunitiesApi.update(item.opportunityId, item.eTag, input, idempotencyKey)
          : adminFundingOpportunitiesApi.create(input, idempotencyKey)
      ))
    },
    onSuccess: async (result) => {
      await queryClient.invalidateQueries({ queryKey: ['admin-funding-opportunities'] })
      if (!item) {
        void navigate(`/admin/funding/${result.entityId}`, { replace: true })
        return
      }
      await queryClient.invalidateQueries({ queryKey: ['admin-funding-opportunity', item.opportunityId] })
      setSaveMessage('Cambios guardados correctamente.')
    },
    onError: error => {
      setSaveMessage(null)
      if (!(error instanceof ApiError)) return
      const serverFields = [
        'fundingSourceId',
        'externalId',
        'sourceUrl',
        'lastVerifiedAtUtc',
      ] as const
      for (const field of serverFields) {
        const message = error.problem.errors?.[field]?.[0]
        if (message) form.setError(field, { type: 'server', message })
      }
    },
  })

  useEffect(() => {
    if (!saveMessage) return
    const timeout = window.setTimeout(() => setSaveMessage(null), 6000)
    return () => window.clearTimeout(timeout)
  }, [saveMessage])

  if (catalogs.isPending || funders.isPending || sources.isPending) return <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" /> Preparando editor…</p>
  if (catalogs.isError || funders.isError || sources.isError || !catalogs.data || !funders.data || !sources.data) {
    return <Card><CardContent className="p-6 text-destructive" role="alert">No fue posible cargar catálogos, fuentes o financiadores para el editor.</CardContent></Card>
  }

  const locked = Boolean(item && [1, 2, 4].includes(item.publicationStatus))
  const countries = form.watch('countryIds')
  const regions = form.watch('regionIds')
  const categories = form.watch('categoryIds')
  const beneficiaries = form.watch('beneficiaryTypeIds')
  const projectTypes = form.watch('projectTypeIds')
  const selectedFunders = form.watch('funders')
  const selectedAmountStatus = form.watch('amountStatus')
  const selectedDeadlineType = form.watch('deadlineType')
  const selectedDeadlinePrecision = form.watch('deadlinePrecision')
  const selectedCofunding = form.watch('requiresCofunding')
  const selectedGeographicScope = form.watch('geographicScope')
  const sourceHostname = hostname(form.watch('sourceUrl'))
  const applicationHostname = hostname(form.watch('applicationUrl'))
  const visibleRegions = catalogs.data.regions.filter((region) => countries.includes(region.countryId))
  const currentFunderIds = new Set((funders.data?.items ?? []).map((funder) => funder.funderId))
  const selectedFunderIds = new Set(selectedFunders.map((funder) => funder.funderId))
  const visibleFunders = [
    ...knownFunders.filter((funder) => selectedFunderIds.has(funder.funderId) && !currentFunderIds.has(funder.funderId)),
    ...(funders.data?.items ?? []),
  ]
  const serverValidation = adminValidationMessages(save.error)

  function submit(values: OpportunityFormValues) {
    const eligibleRegionIds = new Set(
      (catalogs.data?.regions ?? [])
        .filter((region) => values.countryIds.includes(region.countryId))
        .map((region) => region.id),
    )
    if (values.regionIds.some((regionId) => !eligibleRegionIds.has(regionId))) {
      form.setError('regionIds', { message: 'Cada región debe pertenecer a uno de los países seleccionados.' })
      return
    }
    save.mutate(values)
  }

  return (
    <form className="space-y-5" noValidate onSubmit={form.handleSubmit(submit)}>
      <fieldset className="space-y-5 disabled:opacity-65" disabled={locked || save.isPending}>
        <Card>
          <CardHeader><CardTitle>Identidad y procedencia</CardTitle></CardHeader>
          <CardContent className="grid gap-5">
            <Field error={form.formState.errors.title?.message} label="Título"><Input {...form.register('title')} placeholder="Nombre oficial de la convocatoria" /></Field>
            <div className="grid gap-4 lg:grid-cols-2">
              <Field error={form.formState.errors.sponsorName?.message} label="Organismo patrocinador"><Input {...form.register('sponsorName')} placeholder="Entidad que convoca" /></Field>
              <Field error={form.formState.errors.sponsorUrl?.message} label="Sitio del patrocinador"><Input {...form.register('sponsorUrl')} inputMode="url" placeholder="https://..." /></Field>
            </div>
            <div className="grid gap-4 lg:grid-cols-2 xl:grid-cols-4">
              <Field error={form.formState.errors.fundingSourceId?.message} label="Fuente de datos">
                <select {...form.register('fundingSourceId')} className={inputClass}>
                  <option value="">Selecciona una fuente</option>
                  {sources.data.map((source) => <option disabled={!source.isEnabled} key={source.id} value={source.id}>{source.name}{source.isEnabled ? '' : ' (inactiva)'}</option>)}
                </select>
              </Field>
              <Field error={form.formState.errors.externalId?.message} label="ID en la fuente"><Input {...form.register('externalId')} placeholder="Identificador externo" /></Field>
              <Field error={form.formState.errors.issuerCountryId?.message} hint="País de la entidad que emite el fondo; no reemplaza los países elegibles." label="País emisor">
                <select {...form.register('issuerCountryId')} className={inputClass}>
                  <option value="">No informado</option>
                  {catalogs.data.countries.map((country) => <option key={country.id} value={country.id}>{country.name}</option>)}
                </select>
              </Field>
              <Field error={form.formState.errors.fundingTypeId?.message} label="Tipo de financiamiento">
                <select {...form.register('fundingTypeId')} className={inputClass}>
                  <option value="">No informado</option>
                  {catalogs.data.fundingTypes.map((type) => <option key={type.id} value={type.id}>{type.name}</option>)}
                </select>
              </Field>
            </div>
            <Field error={form.formState.errors.sourceUrl?.message} hint="Obligatoria para guardar y conservar la procedencia." label="URL oficial de la convocatoria"><Input {...form.register('sourceUrl')} inputMode="url" placeholder="https://..." /></Field>
            <Field error={form.formState.errors.applicationUrl?.message} label="URL de postulación"><Input {...form.register('applicationUrl')} inputMode="url" placeholder="https://..." /></Field>
            {sourceHostname && applicationHostname && sourceHostname !== applicationHostname && (
              <p className="flex items-start gap-2 rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-950 dark:border-amber-800 dark:bg-amber-950/35 dark:text-amber-100" role="alert">
                <CircleAlert className="mt-0.5 size-4 shrink-0" />
                El dominio de postulación (<strong>{applicationHostname}</strong>) difiere del dominio de la fuente oficial (<strong>{sourceHostname}</strong>). Confírmalo antes de publicar para reducir riesgo de phishing.
              </p>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>Contenido</CardTitle></CardHeader>
          <CardContent className="grid gap-5">
            <Field error={form.formState.errors.summary?.message} label="Resumen"><textarea {...form.register('summary')} className={textareaClass} placeholder="Síntesis visible en el catálogo" /></Field>
            <Field error={form.formState.errors.description?.message} label="Descripción completa"><textarea {...form.register('description')} className="min-h-48 w-full rounded-lg border bg-background px-3 py-2 text-sm" /></Field>
            <Field error={form.formState.errors.eligibilityDescription?.message} label="Elegibilidad"><textarea {...form.register('eligibilityDescription')} className={textareaClass} placeholder="Quiénes pueden postular" /></Field>
            <Field error={form.formState.errors.requirements?.message} label="Requisitos"><textarea {...form.register('requirements')} className={textareaClass} placeholder="Documentos y condiciones de postulación" /></Field>
            <Field error={form.formState.errors.objectives?.message} label="Objetivos o áreas financiables"><textarea {...form.register('objectives')} className={textareaClass} /></Field>
            <div className="grid gap-5 lg:grid-cols-2">
              <Field error={form.formState.errors.allowedActivities?.message} label="Actividades permitidas"><textarea {...form.register('allowedActivities')} className={textareaClass} /></Field>
              <Field error={form.formState.errors.excludedActivities?.message} label="Actividades excluidas"><textarea {...form.register('excludedActivities')} className={textareaClass} /></Field>
            </div>
            <Field error={form.formState.errors.restrictions?.message} label="Restricciones"><textarea {...form.register('restrictions')} className={textareaClass} /></Field>
            <div className="grid gap-5 lg:grid-cols-2">
              <Field error={form.formState.errors.targetOrganizationsDescription?.message} label="Organizaciones objetivo"><textarea {...form.register('targetOrganizationsDescription')} className={textareaClass} placeholder="Tipos o características de las organizaciones buscadas" /></Field>
              <Field error={form.formState.errors.targetPopulationsDescription?.message} label="Poblaciones objetivo"><textarea {...form.register('targetPopulationsDescription')} className={textareaClass} placeholder="Personas o comunidades beneficiarias" /></Field>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>Financiamiento y requisitos institucionales</CardTitle></CardHeader>
          <CardContent className="grid gap-5">
            <Field error={form.formState.errors.amountStatus?.message} label="Estado del monto">
              <select
                {...form.register('amountStatus', { onChange: (event) => {
                  if (event.target.value !== '1') {
                    form.setValue('currency', '', { shouldDirty: true })
                    form.setValue('minimumAmount', '', { shouldDirty: true })
                    form.setValue('maximumAmount', '', { shouldDirty: true })
                  }
                } })}
                className={inputClass}
              >
                <option value="0">Desconocido</option>
                <option value="1">Especificado</option>
                <option value="2">No divulgado</option>
              </select>
            </Field>
            {selectedAmountStatus === '1' && <div className="grid gap-4 sm:grid-cols-3">
              <Field error={form.formState.errors.currency?.message} label="Moneda">
                <select {...form.register('currency')} className={inputClass}>
                  <option value="">Selecciona una moneda</option>
                  {catalogs.data.currencies.map((currency) => <option key={currency.code} value={currency.code}>{currency.code} · {currency.name}</option>)}
                </select>
              </Field>
              <Field error={form.formState.errors.minimumAmount?.message} label="Monto mínimo"><Input {...form.register('minimumAmount')} min="0" step="0.01" type="number" /></Field>
              <Field error={form.formState.errors.maximumAmount?.message} label="Monto máximo"><Input {...form.register('maximumAmount')} min="0" step="0.01" type="number" /></Field>
            </div>}
            <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
              <Field error={form.formState.errors.minimumOperatingYears?.message} label="Años mínimos de operación"><Input {...form.register('minimumOperatingYears')} min="0" step="1" type="number" /></Field>
              <Field label="Entidad legal requerida"><select {...form.register('requiresLegalEntity')} className={inputClass}><option value="">No informado</option><option value="true">Sí</option><option value="false">No</option></select></Field>
              <Field label="Experiencia previa requerida"><select {...form.register('requiresPriorExperience')} className={inputClass}><option value="">No informado</option><option value="true">Sí</option><option value="false">No</option></select></Field>
              <Field label="Cofinanciamiento"><select {...form.register('requiresCofunding', { onChange: (event) => {
                if (event.target.value !== 'true') form.setValue('cofundingPercentage', '', { shouldDirty: true })
              } })} className={inputClass}><option value="">No informado</option><option value="true">Requerido</option><option value="false">No requerido</option></select></Field>
            </div>
            {selectedCofunding === 'true' && <Field error={form.formState.errors.cofundingPercentage?.message} hint="Porcentaje obligatorio, mayor que 0 y hasta 100." label="Porcentaje de cofinanciamiento"><Input {...form.register('cofundingPercentage')} max="100" min="0.01" step="0.01" type="number" /></Field>}
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>Calendario y cierre</CardTitle></CardHeader>
          <CardContent className="grid gap-5">
            <div className="grid gap-4 md:grid-cols-3">
              <Field label="Apertura"><Input {...form.register('openDate')} type="date" /></Field>
              <Field error={form.formState.errors.deadlineType?.message} label="Tipo de cierre">
                <select {...form.register('deadlineType', { onChange: (event) => {
                  if (event.target.value !== '1') {
                    form.setValue('deadlinePrecision', '0', { shouldDirty: true })
                    form.setValue('closeDate', '', { shouldDirty: true })
                    form.setValue('closeAtUtc', '', { shouldDirty: true })
                    form.setValue('deadlineTimeZoneId', '', { shouldDirty: true })
                  }
                } })} className={inputClass}>
                  <option value="0">Desconocido</option>
                  <option value="1">Fecha fija</option>
                  <option value="2">Convocatoria continua</option>
                </select>
              </Field>
              {selectedDeadlineType === '1' && <Field error={form.formState.errors.deadlinePrecision?.message} label="Precisión del cierre">
                <select {...form.register('deadlinePrecision', { onChange: (event) => {
                  if (event.target.value !== '2') {
                    form.setValue('closeAtUtc', '', { shouldDirty: true })
                    form.setValue('deadlineTimeZoneId', '', { shouldDirty: true })
                  }
                } })} className={inputClass}>
                  <option value="0">Selecciona una precisión</option>
                  <option value="1">Solo fecha</option>
                  <option value="2">Fecha y hora exactas</option>
                </select>
              </Field>}
            </div>
            {selectedDeadlineType === '1' && selectedDeadlinePrecision !== '0' && <Field error={form.formState.errors.closeDate?.message} label="Fecha de cierre"><Input {...form.register('closeDate')} type="date" /></Field>}
            {selectedDeadlineType === '1' && selectedDeadlinePrecision === '2' && <div className="grid gap-4 md:grid-cols-2">
              <Field error={form.formState.errors.closeAtUtc?.message} hint="Se conserva en UTC; debe corresponder a la fecha local en la zona indicada." label="Hora exacta de cierre (UTC)"><Input {...form.register('closeAtUtc')} step="0.001" type="datetime-local" /></Field>
              <Field error={form.formState.errors.deadlineTimeZoneId?.message} hint="Identificador IANA, por ejemplo America/Santiago." label="Zona horaria del cierre"><Input {...form.register('deadlineTimeZoneId')} placeholder="America/Santiago" /></Field>
            </div>}
            <Field error={form.formState.errors.lastVerifiedAtUtc?.message} hint="Usa la hora local real en que revisaste la fuente. La plataforma la convierte automáticamente a UTC." label="Última verificación">
              <span className="flex flex-col gap-2 sm:flex-row">
                <Input {...form.register('lastVerifiedAtUtc')} className="flex-1" max={currentLocalDateTimeInput()} step="0.001" type="datetime-local" />
                <Button onClick={() => {
                  form.setValue('lastVerifiedAtUtc', currentLocalDateTimeInput(), { shouldDirty: true, shouldValidate: true })
                  form.clearErrors('lastVerifiedAtUtc')
                }} type="button" variant="outline">Usar hora actual</Button>
              </span>
            </Field>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>Financiadores y alcance</CardTitle></CardHeader>
          <CardContent className="space-y-6">
            <FundingPartnerChoices
              error={form.formState.errors.funders?.message}
              funders={visibleFunders}
              isFetching={funders.isFetching}
              onChange={(value) => form.setValue('funders', value, { shouldDirty: true })}
              onPageChange={setFunderPage}
              onSearchChange={setFunderSearch}
              page={funders.data?.page ?? funderPage}
              pageSize={funders.data?.pageSize ?? funderChoicePageSize}
              search={funderSearch}
              selected={selectedFunders}
              totalCount={funders.data?.totalCount ?? 0}
            />
            <div className="grid gap-4 md:grid-cols-2">
              <Field error={form.formState.errors.geographicScope?.message} label="Alcance geográfico"><select {...form.register('geographicScope', { onChange: (event) => {
                if (event.target.value !== '1') {
                  form.setValue('countryIds', [], { shouldDirty: true })
                  form.setValue('regionIds', [], { shouldDirty: true })
                }
              } })} className={inputClass}><option value="0">Desconocido</option><option value="1">Países o regiones específicos</option><option value="2">Global</option></select></Field>
              <Field label="Postulación remota"><select {...form.register('remoteApplication')} className={inputClass}><option value="0">No informado</option><option value="1">No</option><option value="2">Sí</option></select></Field>
            </div>
            {selectedGeographicScope === '1' && <>
              <MultiChoice items={catalogs.data.countries} label="Países elegibles" onChange={(value) => {
                form.setValue('countryIds', value, { shouldDirty: true })
                const allowedRegionIds = catalogs.data.regions.filter((region) => value.includes(region.countryId)).map((region) => region.id)
                form.setValue('regionIds', regions.filter((regionId) => allowedRegionIds.includes(regionId)), { shouldDirty: true })
              }} selected={countries} />
              {form.formState.errors.countryIds?.message && <p className="text-xs text-destructive">{form.formState.errors.countryIds.message}</p>}
              {visibleRegions.length > 0 && <MultiChoice items={visibleRegions} label="Regiones" onChange={(value) => form.setValue('regionIds', value, { shouldDirty: true })} selected={regions} />}
              {form.formState.errors.regionIds?.message && <p className="text-xs text-destructive">{form.formState.errors.regionIds.message}</p>}
            </>}
            <MultiChoice items={catalogs.data.fundingCategories} label="Categorías" onChange={(value) => form.setValue('categoryIds', value, { shouldDirty: true })} selected={categories} />
            <MultiChoice items={catalogs.data.beneficiaryTypes} label="Poblaciones beneficiarias" onChange={(value) => form.setValue('beneficiaryTypeIds', value, { shouldDirty: true })} selected={beneficiaries} />
            <MultiChoice items={catalogs.data.projectTypes} label="Tipos de proyecto" onChange={(value) => form.setValue('projectTypeIds', value, { shouldDirty: true })} selected={projectTypes} />
          </CardContent>
        </Card>
      </fieldset>

      {locked && <p className="rounded-lg bg-muted p-3 text-sm">El contenido está bloqueado mientras permanece {publicationStatusLabels[item!.publicationStatus].toLowerCase()}.</p>}
      {saveMessage && item && (
        <p className="flex items-center gap-2 rounded-lg bg-accent p-3 text-sm font-medium text-accent-foreground" role="status">
          <CheckCircle2 className="size-4 shrink-0" /> {saveMessage}
        </p>
      )}
      {save.isError && (
        <div className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive" role="alert">
          <p>{adminErrorMessage(save.error)}</p>
          {serverValidation.length > 0 && <ul className="mt-2 list-disc pl-5">{serverValidation.map((message) => <li key={message}>{message}</li>)}</ul>}
          {isConcurrencyConflict(save.error) && item && <Button className="mt-3" onClick={() => void queryClient.invalidateQueries({ queryKey: ['admin-funding-opportunity', item.opportunityId] })} size="sm" type="button" variant="outline"><RefreshCw className="size-4" /> Cargar versión vigente</Button>}
        </div>
      )}
      {!locked && (
        <div className="flex justify-end">
          <Button disabled={save.isPending || (Boolean(item) && !form.formState.isDirty)} type="submit">
            {save.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Save className="size-4" />}
            {item ? 'Guardar cambios' : 'Crear oportunidad'}
          </Button>
        </div>
      )}
    </form>
  )
}

function formatAmount(minimum: number | null, maximum: number | null, currency: string | null) {
  if (!currency || (minimum === null && maximum === null)) return 'Monto no informado'
  const formatter = new Intl.NumberFormat('es-CL', { style: 'currency', currency, maximumFractionDigits: 0 })
  if (minimum !== null && maximum !== null) return `${formatter.format(minimum)} – ${formatter.format(maximum)}`
  return maximum !== null ? `Hasta ${formatter.format(maximum)}` : `Desde ${formatter.format(minimum!)}`
}

export function AdminFundingPage() {
  const [draftQuery, setDraftQuery] = useState('')
  const [query, setQuery] = useState('')
  const [status, setStatus] = useState<PublicationStatus | ''>('')
  const [page, setPage] = useState(1)
  const opportunities = useQuery({
    queryKey: ['admin-funding-opportunities', query, status, page],
    queryFn: ({ signal }) => adminFundingOpportunitiesApi.list({ query, status: status === '' ? null : status, includeInactive: true, page, pageSize: listPageSize }, signal),
    placeholderData: keepPreviousData,
  })

  function search(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setPage(1)
    setQuery(draftQuery.trim())
  }

  const lastPage = opportunities.data ? Math.max(1, Math.ceil(opportunities.data.totalCount / opportunities.data.pageSize)) : 1
  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Administración</p><h1 className="mt-1 text-3xl font-bold">Oportunidades</h1><p className="mt-2 max-w-3xl text-muted-foreground">Crea, verifica y modera cada convocatoria antes de hacerla pública.</p></div>
        <div className="flex flex-wrap gap-2"><Button asChild variant="outline"><Link to="/admin/funders"><Building2Icon /> Financiadores</Link></Button><Button asChild><Link to="/admin/funding/new"><Plus className="size-4" /> Nueva oportunidad</Link></Button></div>
      </div>
      <Card><CardContent className="p-4"><form className="grid gap-3 sm:grid-cols-[1fr_14rem_auto]" onSubmit={search}><label className="relative"><span className="sr-only">Buscar oportunidades</span><Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" /><Input className="pl-9" onChange={(event) => setDraftQuery(event.target.value)} placeholder="Título o patrocinador" value={draftQuery} /></label><label><span className="sr-only">Filtrar por estado</span><select className={inputClass} onChange={(event) => { setStatus(event.target.value === '' ? '' : Number(event.target.value) as PublicationStatus); setPage(1) }} value={status}><option value="">Todos los estados</option>{(Object.entries(publicationStatusLabels) as [string, string][]).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label><Button type="submit">Buscar</Button></form></CardContent></Card>

      {opportunities.isPending && <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" /> Cargando oportunidades…</p>}
      {opportunities.isError && <Card><CardContent className="space-y-3 p-6" role="alert"><p className="text-destructive">{adminErrorMessage(opportunities.error)}</p><Button onClick={() => void opportunities.refetch()} variant="outline">Reintentar</Button></CardContent></Card>}
      {opportunities.data && <section aria-busy={opportunities.isFetching} className="space-y-4"><p className="text-sm text-muted-foreground"><strong className="text-foreground">{opportunities.data.totalCount}</strong> oportunidades</p>{opportunities.data.items.length === 0 ? <Card><CardContent className="p-10 text-center"><FileSearch className="mx-auto size-10 text-primary" /><h2 className="mt-3 text-xl font-bold">No hay oportunidades</h2><p className="mt-2 text-muted-foreground">Crea una nueva o cambia los filtros.</p></CardContent></Card> : <div className="grid gap-4 lg:grid-cols-2">{opportunities.data.items.map((item) => <Card key={item.opportunityId}><CardContent className="space-y-4 p-5"><div className="flex items-start justify-between gap-3"><div><p className="text-xs font-bold uppercase tracking-wide text-primary">{item.sponsorName}</p><h2 className="mt-1 text-xl font-bold">{item.title}</h2></div><PublicationStatusBadge status={item.publicationStatus} /></div><p className="line-clamp-2 text-sm text-muted-foreground">{item.summary ?? 'Sin resumen.'}</p><div className="grid gap-2 text-xs text-muted-foreground sm:grid-cols-2"><p className="flex items-center gap-1.5"><CalendarDays className="size-3.5" /> Cierre {item.closeDate ?? 'sin fecha'}</p><p className="flex items-center gap-1.5"><CircleDollarSign className="size-3.5" /> {formatAmount(item.minimumAmount, item.maximumAmount, item.currency)}</p></div><div className="flex items-center justify-between gap-3 border-t pt-3"><p className="text-xs text-muted-foreground">v{item.contentVersion} · {formatAdminDate(item.updatedAtUtc)}</p><Button asChild size="sm" variant={item.publicationStatus === 1 ? 'default' : 'outline'}><Link to={`/admin/funding/${item.opportunityId}`}>{item.publicationStatus === 1 ? 'Revisar y publicar' : 'Gestionar'}</Link></Button></div></CardContent></Card>)}</div>}{opportunities.data.totalCount > opportunities.data.pageSize && <nav aria-label="Paginación administrativa de oportunidades" className="flex items-center justify-end gap-3"><Button disabled={page <= 1 || opportunities.isFetching} onClick={() => setPage((value) => value - 1)} variant="outline"><ChevronLeft className="size-4" />Anterior</Button><p className="text-sm">Página {opportunities.data.page} de {lastPage}</p><Button disabled={page >= lastPage || opportunities.isFetching} onClick={() => setPage((value) => value + 1)} variant="outline">Siguiente<ChevronRight className="size-4" /></Button></nav>}</section>}
    </div>
  )
}

function Building2Icon() {
  return <span aria-hidden="true" className="text-base leading-none">◎</span>
}

function ReadinessChecks({ item }: { item: AdminFundingOpportunityDetail }) {
  const geographyReady = item.geographicScope === 2
    ? item.countryIds.length === 0 && item.regionIds.length === 0
    : item.geographicScope === 1 && item.countryIds.length > 0
  const checks = [
    { label: 'Resumen y descripción', ready: Boolean(item.summary?.trim() && item.description?.trim()) },
    { label: 'Financiador principal', ready: item.funders.some((funder) => funder.role === 1) },
    { label: 'Alcance geográfico', ready: geographyReady },
    { label: 'Categoría', ready: item.categoryIds.length > 0 },
    { label: 'Fuente y URL oficial', ready: item.fundingSourceId > 0 && Boolean(item.sourceUrl?.trim()) },
    { label: 'Última verificación', ready: Boolean(item.lastVerifiedAtUtc) },
  ]
  return <Card><CardHeader><CardTitle>Preparación para publicar</CardTitle></CardHeader><CardContent><ul className="grid gap-2 sm:grid-cols-2">{checks.map((check) => <li className="flex items-start gap-2 text-sm" key={check.label}>{check.ready ? <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-primary" /> : <CircleAlert className="mt-0.5 size-4 shrink-0 text-muted-foreground" />}{check.label}</li>)}</ul></CardContent></Card>
}

function publicVisibilityIssues(item: AdminFundingOpportunityDetail) {
  const issues: string[] = []
  if (item.categoryIds.length === 0) {
    issues.push('Selecciona al menos un área o categoría de financiamiento.')
  }
  if (item.geographicScope === 0) {
    issues.push('Define el alcance geográfico como específico o global.')
  } else if (item.geographicScope === 1 && item.countryIds.length === 0) {
    issues.push('El alcance específico requiere al menos un país elegible.')
  } else if (item.geographicScope === 2 && (item.countryIds.length > 0 || item.regionIds.length > 0)) {
    issues.push('El alcance global no debe conservar países ni regiones específicas.')
  }
  return issues
}

function TraceabilityPanel({ item }: { item: AdminFundingOpportunityDetail }) {
  const evidence = item.evidence ?? []
  const sources = item.sources ?? []
  return (
    <Card>
      <CardHeader><CardTitle>Trazabilidad y calidad</CardTitle></CardHeader>
      <CardContent className="space-y-4 text-sm">
        <div className="grid gap-3 sm:grid-cols-3">
          <p><span className="text-muted-foreground">Calidad</span><strong className="mt-1 block text-lg">{Math.round(item.dataQualityScore)}/100</strong></p>
          <p><span className="text-muted-foreground">Última verificación</span><strong className="mt-1 block">{formatAdminDate(item.lastVerifiedAtUtc)}</strong></p>
          <p><span className="text-muted-foreground">Evidencias</span><strong className="mt-1 block text-lg">{evidence.length}</strong></p>
        </div>
        {sources.length > 0 && (
          <div className="border-t pt-4">
            <h2 className="font-semibold">Fuentes vinculadas</h2>
            <ul className="mt-2 grid gap-2">
              {sources.map((source) => (
                <li className="flex flex-wrap items-center justify-between gap-2 rounded-lg border px-3 py-2" key={`${source.fundingSourceId}-${source.sourceUrl}`}>
                  <span><strong>{source.sourceName}</strong>{source.externalId ? ` · ${source.externalId}` : ''}{source.isPrimary ? ' · Principal' : ''}</span>
                  <a className="inline-flex items-center gap-1 font-semibold text-primary underline" href={source.sourceUrl} rel="noopener noreferrer" target="_blank">Abrir <ExternalLink className="size-3.5" /></a>
                </li>
              ))}
            </ul>
          </div>
        )}
      </CardContent>
    </Card>
  )
}

export function AdminFundingDetailPage() {
  const { id = '' } = useParams()
  const creating = id === 'new'
  const [dirty, setDirty] = useState(false)
  const queryClient = useQueryClient()
  const opportunity = useQuery({ queryKey: ['admin-funding-opportunity', id], queryFn: ({ signal }) => adminFundingOpportunitiesApi.get(id, signal), enabled: Boolean(id) && !creating, retry: false })

  if (!creating && opportunity.isPending) return <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" /> Cargando oportunidad…</p>
  if (!creating && (opportunity.isError || !opportunity.data)) return <Card><CardContent className="space-y-4 p-8" role="alert"><h1 className="text-2xl font-bold">No pudimos abrir la oportunidad</h1><p className="text-destructive">{adminErrorMessage(opportunity.error)}</p><Button asChild variant="outline"><Link to="/admin/funding">Volver</Link></Button></CardContent></Card>

  const data = opportunity.data
  const visibilityIssues = data ? publicVisibilityIssues(data) : []
  return <div className="space-y-6"><Button asChild variant="ghost"><Link to="/admin/funding"><ArrowLeft className="size-4" /> Volver a oportunidades</Link></Button><div><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Administración</p><div className="mt-1 flex flex-wrap items-center gap-3"><h1 className="text-3xl font-bold">{creating ? 'Crear oportunidad' : data!.title}</h1>{data && <PublicationStatusBadge status={data.publicationStatus} />}</div>{data && <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-sm text-muted-foreground"><span>Versión {data.contentVersion}</span><span>Actualizado {formatAdminDate(data.updatedAtUtc)}</span>{data.publicationStatus === 2 && visibilityIssues.length === 0 && <Link className="inline-flex items-center gap-1 font-semibold text-primary underline" to={`/funding/${data.slug}`}>Ver público <ExternalLink className="size-3.5" /></Link>}</div>}</div>{data?.publicationStatus === 1 && <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm text-amber-950 dark:border-amber-800 dark:bg-amber-950/35 dark:text-amber-100" role="status"><p><strong>Este fondo está pendiente de revisión.</strong> Revisa sus datos y apruébalo para publicarlo.</p><Button asChild size="sm"><a href="#flujo-editorial">Ir a revisar y publicar</a></Button></div>}{data && <><ReadinessChecks item={data} /><TraceabilityPanel item={data} /><div className="scroll-mt-6" id="flujo-editorial"><EditorialWorkflowPanel commands={adminFundingOpportunitiesApi} disabledReason={dirty ? 'Guarda o descarta los cambios del formulario antes de ejecutar una acción editorial.' : undefined} eTag={data.eTag} entityId={data.opportunityId} entityName="la oportunidad" onChanged={async () => { await queryClient.invalidateQueries({ queryKey: ['admin-funding-opportunities'] }); await opportunity.refetch() }} publicVisibilityIssues={visibilityIssues} publicationStatus={data.publicationStatus} rejectionReason={data.rejectionReason} /></div></>}<AdminOpportunityForm item={data} onDirtyChange={setDirty} /></div>
}
