import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Building2, Check, ChevronLeft, ChevronRight, LoaderCircle, Save } from 'lucide-react'
import { useEffect, useState, type ReactNode } from 'react'
import { useForm, type FieldPath } from 'react-hook-form'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import {
  organizationApi,
  type CatalogOption,
  type OrganizationCatalogs,
  type OrganizationProfile,
  type OrganizationProfileUpdate,
} from '@/features/organizations/organization-api'

const steps = ['Identidad', 'Impacto', 'Financiamiento'] as const
const selectClass = 'h-10 w-full rounded-lg border bg-background px-3 text-sm'
const textareaClass = 'min-h-28 w-full rounded-lg border bg-background px-3 py-2 text-sm'
const errorSummaryId = 'organization-profile-error-summary'

type FieldRequirement = 'required' | 'recommended' | 'optional'

interface ApiValidationEntry {
  key: string
  message: string
}

interface FinancialPreset {
  key: string
  label: string
  minimum: number | null
  maximum: number | null
}

interface CreateOrganizationValues {
  name: string
  homeCountryId: number
  organizationTypeId: number
}

const desiredFundingPresets: FinancialPreset[] = [
  { key: 'up-to-25k', label: 'Hasta USD 25.000', minimum: null, maximum: 25_000 },
  { key: '25k-100k', label: 'USD 25.000 – 100.000', minimum: 25_000, maximum: 100_000 },
  { key: '100k-500k', label: 'USD 100.000 – 500.000', minimum: 100_000, maximum: 500_000 },
  { key: 'over-500k', label: 'Más de USD 500.000', minimum: 500_000, maximum: null },
]

const annualBudgetPresets: FinancialPreset[] = [
  { key: 'up-to-50k', label: 'Hasta USD 50.000', minimum: null, maximum: 50_000 },
  { key: '50k-250k', label: 'USD 50.000 – 250.000', minimum: 50_000, maximum: 250_000 },
  { key: '250k-1m', label: 'USD 250.000 – 1 millón', minimum: 250_000, maximum: 1_000_000 },
  { key: 'over-1m', label: 'Más de USD 1 millón', minimum: 1_000_000, maximum: null },
]

const currentOrganizationSizeCodes = [
  'EMPLOYEES_1_10',
  'EMPLOYEES_11_50',
  'EMPLOYEES_51_100',
  'EMPLOYEES_101_PLUS',
] as const

const currentProjectTypeCodes = [
  'CAPACITY_BUILDING',
  'COMMUNITY_DEVELOPMENT',
  'TRAINING_CAPACITY_DEVELOPMENT',
  'ADVOCACY',
  'INFRASTRUCTURE',
  'RESEARCH',
  'INNOVATION_TECHNOLOGY',
  'ENTREPRENEURSHIP_PRODUCTIVE_DEVELOPMENT',
  'ENVIRONMENTAL_CONSERVATION_RESTORATION',
  'EMERGENCY_RESPONSE',
  'DISASTER_RISK_PREVENTION_REDUCTION',
  'OTHER',
] as const

const profileErrorFields: Record<string, FieldPath<OrganizationProfileUpdate>> = {
  name: 'name',
  homecountryid: 'homeCountryId',
  organizationtypeid: 'organizationTypeId',
  legalentitytypeid: 'legalEntityTypeId',
  organizationsizeid: 'organizationSizeId',
  establishedyear: 'establishedYear',
  websiteurl: 'websiteUrl',
  legalname: 'legalName',
  taxidentifier: 'taxIdentifier',
  description: 'description',
  previousfundingexperience: 'previousFundingExperience',
  fundingexperiencetypeids: 'fundingExperienceTypeIds',
  experiencesummary: 'experienceSummary',
  annualbudget: 'annualBudgetMax',
  annualbudgetmin: 'annualBudgetMin',
  annualbudgetmax: 'annualBudgetMax',
  annualbudgetcurrency: 'annualBudgetCurrency',
  desiredfunding: 'desiredFundingMax',
  desiredfundingmin: 'desiredFundingMin',
  desiredfundingmax: 'desiredFundingMax',
  desiredfundingcurrency: 'desiredFundingCurrency',
  countryids: 'countryIds',
  regionids: 'regionIds',
  categoryids: 'categoryIds',
  beneficiarytypeids: 'beneficiaryTypeIds',
  projecttypeids: 'projectTypeIds',
  languages: 'languages',
}

const profileErrorTargets: Record<string, string> = {
  name: 'organization-name',
  homecountryid: 'organization-home-country',
  organizationtypeid: 'organization-type',
  legalentitytypeid: 'organization-legal-entity',
  organizationsizeid: 'organization-size',
  establishedyear: 'organization-established-year',
  websiteurl: 'organization-website',
  legalname: 'organization-legal-name',
  taxidentifier: 'organization-tax-identifier',
  description: 'organization-description',
  previousfundingexperience: 'organization-funding-experience',
  fundingexperiencetypeids: 'organization-funding-experience-types',
  experiencesummary: 'organization-experience-summary',
  annualbudget: 'organization-annual-budget-max',
  annualbudgetmin: 'organization-annual-budget-min',
  annualbudgetmax: 'organization-annual-budget-max',
  annualbudgetcurrency: 'organization-annual-budget-currency',
  desiredfunding: 'organization-desired-funding-max',
  desiredfundingmin: 'organization-desired-funding-min',
  desiredfundingmax: 'organization-desired-funding-max',
  desiredfundingcurrency: 'organization-desired-funding-currency',
  countryids: 'organization-countries',
  regionids: 'organization-regions',
  categoryids: 'organization-categories',
  beneficiarytypeids: 'organization-beneficiaries',
  projecttypeids: 'organization-project-types',
  languages: 'organization-languages',
}

const createErrorFields: Record<string, FieldPath<CreateOrganizationValues>> = {
  name: 'name',
  homecountryid: 'homeCountryId',
  organizationtypeid: 'organizationTypeId',
}

const createErrorTargets: Record<string, string> = {
  name: 'create-organization-name',
  homecountryid: 'create-organization-country',
  organizationtypeid: 'create-organization-type',
}

function requirementLabel(requirement: FieldRequirement) {
  if (requirement === 'required') {
    return <><span aria-hidden="true" className="text-destructive"> *</span><span className="sr-only"> (obligatorio)</span></>
  }

  return <span className="text-xs font-normal text-muted-foreground"> · {requirement === 'recommended' ? 'Recomendado' : 'Opcional'}</span>
}

function Field({ label, hint, error, requirement = 'optional', children }: {
  label: string
  hint?: string
  error?: string
  requirement?: FieldRequirement
  children: ReactNode
}) {
  return (
    <label className="grid gap-1.5 text-sm font-semibold">
      <span>{label}{requirementLabel(requirement)}</span>
      {children}
      {hint && <span className="text-xs font-normal text-muted-foreground">{hint}</span>}
      {error && <span className="text-xs font-normal text-destructive" role="alert">{error}</span>}
    </label>
  )
}

function apiValidationEntries(error: unknown): ApiValidationEntry[] {
  if (!(error instanceof ApiError)) {
    return [{ key: 'request', message: 'No fue posible guardar. Revisa la conexión e intenta nuevamente.' }]
  }

  const entries = Object.entries(error.problem.errors ?? {}).flatMap(([key, messages]) =>
    messages.map(message => ({ key, message })),
  )
  if (entries.length > 0) return entries

  return [{ key: 'request', message: error.problem.detail ?? error.problem.title }]
}

function normalizedErrorKey(key: string) {
  return key.replace(/[^a-z\d]/gi, '').toLowerCase()
}

function formErrorMessage(value: unknown) {
  if (!value || typeof value !== 'object' || !('message' in value)) return undefined
  return typeof value.message === 'string' ? value.message : undefined
}

function ValidationSummary({ error, id, targets = {}, onTargetClick }: {
  error: unknown
  id: string
  targets?: Record<string, string>
  onTargetClick?: (errorKey: string, targetId: string) => void
}) {
  const entries = apiValidationEntries(error)
  return (
    <div className="rounded-lg bg-destructive/10 p-4 text-sm text-destructive" id={id} role="alert" tabIndex={-1}>
      <p className="font-semibold">No pudimos guardar. Revisa lo siguiente:</p>
      <ul className="mt-2 list-disc space-y-1 pl-5">
        {entries.map((entry, index) => {
          const target = targets[normalizedErrorKey(entry.key)]
          return (
            <li key={`${entry.key}-${index}`}>
              {target
                ? <a
                    className="underline underline-offset-2"
                    href={`#${target}`}
                    onClick={event => {
                      if (!onTargetClick) return
                      event.preventDefault()
                      onTargetClick(entry.key, target)
                    }}
                  >{entry.message}</a>
                : entry.message}
            </li>
          )
        })}
      </ul>
    </div>
  )
}

function focusErrorTarget(error: unknown, targets: Record<string, string>, summaryId: string) {
  const firstTarget = apiValidationEntries(error)
    .map(entry => targets[normalizedErrorKey(entry.key)])
    .find(Boolean)
  window.setTimeout(() => {
    const target = firstTarget ? document.getElementById(firstTarget) : null
    ;(target ?? document.getElementById(summaryId))?.focus()
  }, 0)
}

function selectedPreset(
  minimum: number | null,
  maximum: number | null,
  currency: string | null,
  presets: FinancialPreset[],
) {
  if (minimum === null && maximum === null && !currency) return ''
  if (currency !== 'USD') return 'custom'
  return presets.find(preset => preset.minimum === minimum && preset.maximum === maximum)?.key ?? 'custom'
}

function profileStepForError(key: string) {
  const normalized = normalizedErrorKey(key)
  if (['countryids', 'regionids', 'categoryids', 'beneficiarytypeids', 'projecttypeids'].includes(normalized)) return 1
  if (
    normalized.startsWith('annualbudget') ||
    normalized.startsWith('desiredfunding') ||
    ['previousfundingexperience', 'fundingexperiencetypeids', 'experiencesummary', 'languages'].includes(normalized)
  ) return 2
  return 0
}

function normalizeWebsiteUrl(value: string | null) {
  const normalized = value?.trim()
  if (!normalized) return null
  return /^[a-z][a-z\d+.-]*:/i.test(normalized) ? normalized : `https://${normalized}`
}

function LoadingCard() {
  return (
    <Card><CardContent className="flex items-center gap-3 p-8 text-muted-foreground">
      <LoaderCircle className="size-5 animate-spin" /> Cargando perfil de organización…
    </CardContent></Card>
  )
}

function CreateOrganization({ catalogs }: { catalogs: OrganizationCatalogs }) {
  const queryClient = useQueryClient()
  const { register, handleSubmit, setError, formState } = useForm<CreateOrganizationValues>({
    defaultValues: {
      name: '',
      homeCountryId: catalogs.countries[0]?.id,
      organizationTypeId: catalogs.organizationTypes[0]?.id,
    },
  })
  const create = useMutation({
    mutationFn: organizationApi.create,
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['organizations'] })
    },
    onError: error => {
      apiValidationEntries(error).forEach(entry => {
        const field = createErrorFields[normalizedErrorKey(entry.key)]
        if (field) setError(field, { type: 'server', message: entry.message })
      })
      focusErrorTarget(error, createErrorTargets, 'create-organization-error-summary')
    },
  })

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <div className="space-y-2">
        <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Onboarding · Paso inicial</p>
        <h1 className="text-3xl font-bold tracking-tight">Crea el espacio de tu organización</h1>
        <p className="leading-7 text-muted-foreground">
          Este espacio separa de forma segura los datos, miembros y futuras recomendaciones de tu ONG.
        </p>
      </div>
      <Card>
        <CardHeader><CardTitle>Datos esenciales</CardTitle></CardHeader>
        <CardContent>
          <form className="grid gap-5" noValidate onSubmit={handleSubmit((values) => create.mutate(values))}>
            <p className="text-sm text-muted-foreground"><span aria-hidden="true" className="font-semibold text-destructive">*</span> indica un campo obligatorio.</p>
            <Field error={formState.errors.name?.message} label="Nombre público" requirement="required">
              <Input
                {...register('name', {
                  required: 'Ingresa el nombre público de la organización.',
                  maxLength: { value: 250, message: 'El nombre admite hasta 250 caracteres.' },
                })}
                aria-invalid={Boolean(formState.errors.name)}
                aria-required="true"
                autoComplete="organization"
                id="create-organization-name"
                placeholder="Ej. Fundación Impacto Local"
                required
              />
            </Field>
            <div className="grid gap-4 sm:grid-cols-2">
              <Field error={formState.errors.homeCountryId?.message} label="País principal" requirement="required">
                <select
                  {...register('homeCountryId', {
                    valueAsNumber: true,
                    validate: value => value > 0 || 'Selecciona un país válido.',
                  })}
                  aria-invalid={Boolean(formState.errors.homeCountryId)}
                  aria-required="true"
                  className={selectClass}
                  id="create-organization-country"
                  required
                >
                  {catalogs.countries.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}
                </select>
              </Field>
              <Field error={formState.errors.organizationTypeId?.message} label="Tipo de organización" requirement="required">
                <select
                  {...register('organizationTypeId', {
                    valueAsNumber: true,
                    validate: value => value > 0 || 'Selecciona un tipo de organización válido.',
                  })}
                  aria-invalid={Boolean(formState.errors.organizationTypeId)}
                  aria-required="true"
                  className={selectClass}
                  id="create-organization-type"
                  required
                >
                  {catalogs.organizationTypes.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}
                </select>
              </Field>
            </div>
            {create.isError && <ValidationSummary error={create.error} id="create-organization-error-summary" targets={createErrorTargets} />}
            <Button className="sm:justify-self-start" disabled={create.isPending || formState.isSubmitting} type="submit">
              {create.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Building2 className="size-4" />}
              Crear organización
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}

function MultiChoice({
  label,
  items,
  selected,
  onChange,
  error,
  id,
  requirement = 'optional',
}: {
  label: string
  items: CatalogOption<number>[]
  selected: number[]
  onChange: (value: number[]) => void
  error?: string
  id?: string
  requirement?: FieldRequirement
}) {
  function toggle(id: number) {
    onChange(selected.includes(id) ? selected.filter(value => value !== id) : [...selected, id])
  }
  return (
    <fieldset aria-invalid={Boolean(error)} className="space-y-2" id={id} tabIndex={-1}>
      <legend className="text-sm font-semibold">{label}{requirementLabel(requirement)}</legend>
      <div className="grid gap-2 sm:grid-cols-2">
        {items.map(item => (
          <label className="flex cursor-pointer items-center gap-2 rounded-lg border bg-background px-3 py-2 text-sm" key={item.id}>
            <input checked={selected.includes(item.id)} onChange={() => toggle(item.id)} type="checkbox" />
            {item.name}
          </label>
        ))}
      </div>
      {error && <span className="block text-xs text-destructive" role="alert">{error}</span>}
    </fieldset>
  )
}

function ProfileEditor({ profile, catalogs, onboarding }: {
  profile: OrganizationProfile
  catalogs: OrganizationCatalogs
  onboarding: boolean
}) {
  const queryClient = useQueryClient()
  const [step, setStep] = useState(0)
  const [desiredFundingPreset, setDesiredFundingPreset] = useState(() => selectedPreset(
    profile.desiredFundingMin,
    profile.desiredFundingMax,
    profile.desiredFundingCurrency,
    desiredFundingPresets,
  ))
  const [annualBudgetPreset, setAnnualBudgetPreset] = useState(() => selectedPreset(
    profile.annualBudgetMin,
    profile.annualBudgetMax,
    profile.annualBudgetCurrency,
    annualBudgetPresets,
  ))
  const { register, handleSubmit, reset, watch, setValue, setError, clearErrors, formState } = useForm<OrganizationProfileUpdate>({
    defaultValues: { ...profile, fundingExperienceTypeIds: profile.fundingExperienceTypeIds ?? [] },
  })
  useEffect(() => {
    reset({ ...profile, fundingExperienceTypeIds: profile.fundingExperienceTypeIds ?? [] })
    setDesiredFundingPreset(selectedPreset(
      profile.desiredFundingMin,
      profile.desiredFundingMax,
      profile.desiredFundingCurrency,
      desiredFundingPresets,
    ))
    setAnnualBudgetPreset(selectedPreset(
      profile.annualBudgetMin,
      profile.annualBudgetMax,
      profile.annualBudgetCurrency,
      annualBudgetPresets,
    ))
  }, [profile, reset])
  const update = useMutation({
    mutationFn: (input: OrganizationProfileUpdate) => organizationApi.update(profile.publicId, profile.eTag, input),
    onSuccess: async (updated) => {
      reset(updated)
      setDesiredFundingPreset(selectedPreset(
        updated.desiredFundingMin,
        updated.desiredFundingMax,
        updated.desiredFundingCurrency,
        desiredFundingPresets,
      ))
      setAnnualBudgetPreset(selectedPreset(
        updated.annualBudgetMin,
        updated.annualBudgetMax,
        updated.annualBudgetCurrency,
        annualBudgetPresets,
      ))
      await queryClient.invalidateQueries({ queryKey: ['organization-profile', profile.publicId] })
      await queryClient.invalidateQueries({ queryKey: ['organizations'] })
    },
    onError: error => {
      const entries = apiValidationEntries(error)
      entries.forEach(entry => {
        const field = profileErrorFields[normalizedErrorKey(entry.key)]
        if (field) setError(field, { type: 'server', message: entry.message })
      })
      const firstTargetedEntry = entries.find(entry =>
        Boolean(profileErrorTargets[normalizedErrorKey(entry.key)]),
      )
      if (firstTargetedEntry) setStep(profileStepForError(firstTargetedEntry.key))
      focusErrorTarget(error, profileErrorTargets, errorSummaryId)
    },
  })
  const countries = watch('countryIds') ?? []
  const categories = watch('categoryIds') ?? []
  const beneficiaries = watch('beneficiaryTypeIds') ?? []
  const projectTypes = watch('projectTypeIds') ?? []
  const regions = watch('regionIds') ?? []
  const desiredFundingMin = watch('desiredFundingMin')
  const desiredFundingMax = watch('desiredFundingMax')
  const annualBudgetMin = watch('annualBudgetMin')
  const annualBudgetMax = watch('annualBudgetMax')
  const previousFundingExperience = watch('previousFundingExperience')
  const fundingExperienceTypeIds = watch('fundingExperienceTypeIds') ?? []
  const selectedOrganizationSizeId = watch('organizationSizeId')
  const visibleRegions = catalogs.regions.filter(region => countries.includes(region.countryId))
  const currentOrganizationSizes = currentOrganizationSizeCodes.flatMap(code => {
    const item = catalogs.organizationSizes.find(size => size.code === code)
    return item ? [item] : []
  })
  const sizeOptionsBase = currentOrganizationSizes.length > 0
    ? currentOrganizationSizes
    : catalogs.organizationSizes
  const selectedLegacyOrganizationSize = currentOrganizationSizes.length > 0
    ? catalogs.organizationSizes.find(size =>
        size.id === selectedOrganizationSizeId &&
        !currentOrganizationSizeCodes.includes(size.code as typeof currentOrganizationSizeCodes[number]),
      )
    : undefined
  const visibleOrganizationSizes = selectedLegacyOrganizationSize
    ? [...sizeOptionsBase, {
        ...selectedLegacyOrganizationSize,
        name: `${selectedLegacyOrganizationSize.name} (rango anterior; confirma uno nuevo)`,
      }]
    : sizeOptionsBase
  const currentProjectTypes = currentProjectTypeCodes.flatMap(code => {
    const item = catalogs.projectTypes.find(projectType => projectType.code === code)
    return item ? [item] : []
  })
  const hasExpandedProjectTypeCatalog = currentProjectTypes.length === currentProjectTypeCodes.length
  const selectedLegacyProgram = hasExpandedProjectTypeCatalog
    ? catalogs.projectTypes.find(projectType =>
        projectType.code === 'PROGRAM' && projectTypes.includes(projectType.id),
      )
    : undefined
  const visibleProjectTypes = hasExpandedProjectTypeCatalog
    ? [
        ...currentProjectTypes,
        ...(selectedLegacyProgram ? [{
          ...selectedLegacyProgram,
          name: `${selectedLegacyProgram.name} (valor anterior; confirma un tipo nuevo)`,
        }] : []),
      ]
    : catalogs.projectTypes
  const optionalNumber = {
    setValueAs: (value: string | null | undefined) => value === '' || value == null ? null : Number(value),
  }

  function applyDesiredFundingPreset(key: string) {
    setDesiredFundingPreset(key)
    if (key === 'custom') return
    const preset = desiredFundingPresets.find(item => item.key === key)
    setValue('desiredFundingMin', preset?.minimum ?? null, { shouldDirty: true })
    setValue('desiredFundingMax', preset?.maximum ?? null, { shouldDirty: true })
    setValue('desiredFundingCurrency', preset ? 'USD' : null, { shouldDirty: true })
    clearErrors(['desiredFundingMin', 'desiredFundingMax', 'desiredFundingCurrency'])
  }

  function applyAnnualBudgetPreset(key: string) {
    setAnnualBudgetPreset(key)
    if (key === 'custom') return
    const preset = annualBudgetPresets.find(item => item.key === key)
    setValue('annualBudgetMin', preset?.minimum ?? null, { shouldDirty: true })
    setValue('annualBudgetMax', preset?.maximum ?? null, { shouldDirty: true })
    setValue('annualBudgetCurrency', preset ? 'USD' : null, { shouldDirty: true })
    clearErrors(['annualBudgetMin', 'annualBudgetMax', 'annualBudgetCurrency'])
  }

  function validateFinancialRanges(values: OrganizationProfileUpdate) {
    let firstTarget: string | null = null
    const validate = (
      minimum: number | null,
      maximum: number | null,
      currency: string | null,
      minimumField: 'desiredFundingMin' | 'annualBudgetMin',
      maximumField: 'desiredFundingMax' | 'annualBudgetMax',
      currencyField: 'desiredFundingCurrency' | 'annualBudgetCurrency',
      targetPrefix: 'organization-desired-funding' | 'organization-annual-budget',
    ) => {
      const hasMinimum = minimum !== null && minimum !== undefined
      const hasMaximum = maximum !== null && maximum !== undefined
      if (hasMinimum && minimum < 0) {
        setError(minimumField, { type: 'validate', message: 'El monto mínimo no puede ser negativo.' })
        firstTarget ??= `${targetPrefix}-min`
      }
      if (hasMaximum && maximum < 0) {
        setError(maximumField, { type: 'validate', message: 'El monto máximo no puede ser negativo.' })
        firstTarget ??= `${targetPrefix}-max`
      }
      if (hasMinimum && hasMaximum && maximum < minimum) {
        setError(maximumField, { type: 'validate', message: 'El monto máximo debe ser igual o mayor al mínimo.' })
        firstTarget ??= `${targetPrefix}-max`
      }
      if ((hasMinimum || hasMaximum) && !currency) {
        setError(currencyField, { type: 'validate', message: 'Selecciona una moneda para el rango informado.' })
        firstTarget ??= `${targetPrefix}-currency`
      }
      if (!hasMinimum && !hasMaximum && currency) {
        setError(currencyField, { type: 'validate', message: 'Ingresa al menos un monto o selecciona “Sin informar”.' })
        firstTarget ??= `${targetPrefix}-currency`
      }
    }

    validate(
      values.desiredFundingMin,
      values.desiredFundingMax,
      values.desiredFundingCurrency,
      'desiredFundingMin',
      'desiredFundingMax',
      'desiredFundingCurrency',
      'organization-desired-funding',
    )
    validate(
      values.annualBudgetMin,
      values.annualBudgetMax,
      values.annualBudgetCurrency,
      'annualBudgetMin',
      'annualBudgetMax',
      'annualBudgetCurrency',
      'organization-annual-budget',
    )
    return firstTarget
  }

  function navigateToProfileError(errorKey: string, targetId: string) {
    setStep(profileStepForError(errorKey))
    window.setTimeout(() => {
      const target = document.getElementById(targetId)
      ;(target ?? document.getElementById(errorSummaryId))?.focus()
    }, 0)
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{onboarding ? 'Onboarding' : 'Organización'}</p>
          <h1 className="mt-1 text-3xl font-bold tracking-tight">Perfil de {profile.name}</h1>
          <p className="mt-2 text-muted-foreground">Versión {profile.profileVersion} · {profile.profileCompleteness}% completo</p>
        </div>
        <div className="h-2 w-48 overflow-hidden rounded-full bg-muted" aria-label={`${profile.profileCompleteness}% completo`}>
          <div className="h-full bg-primary transition-all" style={{ width: `${profile.profileCompleteness}%` }} />
        </div>
      </div>

      <div className="grid grid-cols-3 gap-2" aria-label="Pasos del perfil">
        {steps.map((label, index) => (
          <button className={`rounded-lg border px-3 py-3 text-sm font-semibold ${step === index ? 'border-primary bg-accent text-accent-foreground' : 'bg-card text-muted-foreground'}`} key={label} onClick={() => setStep(index)} type="button">
            <span className="hidden sm:inline">{index + 1}. </span>{label}
          </button>
        ))}
      </div>

      <form aria-describedby="organization-profile-field-guide" noValidate onSubmit={handleSubmit(
        values => {
          clearErrors()
          update.reset()
          const rangeErrorTarget = validateFinancialRanges(values)
          if (rangeErrorTarget) {
            setStep(2)
            window.setTimeout(() => document.getElementById(rangeErrorTarget)?.focus(), 0)
            return
          }
          update.mutate({ ...values, websiteUrl: normalizeWebsiteUrl(values.websiteUrl) })
        },
        errors => {
          const firstField = Object.keys(errors)[0]
          const normalized = normalizedErrorKey(firstField ?? '')
          setStep(profileStepForError(normalized))
          window.setTimeout(() => {
            document.getElementById(profileErrorTargets[normalized] ?? errorSummaryId)?.focus()
          }, 0)
        },
      )}>
        <Card>
          <CardContent className="grid gap-5 p-6">
            <p className="text-sm leading-6 text-muted-foreground" id="organization-profile-field-guide">
              <span aria-hidden="true" className="font-semibold text-destructive">*</span> Obligatorio para guardar. Los campos recomendados mejoran tu perfil y sus recomendaciones; los opcionales pueden quedar vacíos en el borrador.
            </p>
            {step === 0 && <>
              <div className="grid gap-4 sm:grid-cols-2">
                <Field error={formState.errors.name?.message} label="Nombre público" requirement="required">
                  <Input
                    {...register('name', {
                      required: 'Ingresa el nombre público de la organización.',
                      maxLength: { value: 250, message: 'El nombre admite hasta 250 caracteres.' },
                    })}
                    aria-invalid={Boolean(formState.errors.name)}
                    aria-required="true"
                    id="organization-name"
                    required
                  />
                </Field>
                <Field error={formState.errors.legalName?.message} label="Razón social">
                  <Input {...register('legalName')} aria-invalid={Boolean(formState.errors.legalName)} id="organization-legal-name" />
                </Field>
                <Field error={formState.errors.taxIdentifier?.message} label="Identificador tributario">
                  <Input {...register('taxIdentifier')} aria-invalid={Boolean(formState.errors.taxIdentifier)} id="organization-tax-identifier" />
                </Field>
                <Field error={formState.errors.establishedYear?.message} label="Año de constitución" requirement="recommended">
                  <Input
                    {...register('establishedYear', {
                      ...optionalNumber,
                      min: { value: 1800, message: 'El año debe ser 1800 o posterior.' },
                      max: { value: new Date().getFullYear(), message: 'El año no puede estar en el futuro.' },
                    })}
                    aria-invalid={Boolean(formState.errors.establishedYear)}
                    id="organization-established-year"
                    max={new Date().getFullYear()}
                    min="1800"
                    type="number"
                  />
                </Field>
                <Field error={formState.errors.homeCountryId?.message} label="País principal" requirement="required">
                  <select
                    {...register('homeCountryId', {
                      valueAsNumber: true,
                      validate: value => value > 0 || 'Selecciona un país válido.',
                    })}
                    aria-invalid={Boolean(formState.errors.homeCountryId)}
                    aria-required="true"
                    className={selectClass}
                    id="organization-home-country"
                    required
                  >{catalogs.countries.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select>
                </Field>
                <Field error={formState.errors.organizationTypeId?.message} label="Tipo de organización" requirement="required">
                  <select
                    {...register('organizationTypeId', {
                      valueAsNumber: true,
                      validate: value => value > 0 || 'Selecciona un tipo de organización válido.',
                    })}
                    aria-invalid={Boolean(formState.errors.organizationTypeId)}
                    aria-required="true"
                    className={selectClass}
                    id="organization-type"
                    required
                  >{catalogs.organizationTypes.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select>
                </Field>
                <Field error={formState.errors.legalEntityTypeId?.message} label="Personalidad jurídica" requirement="recommended">
                  <select {...register('legalEntityTypeId', optionalNumber)} aria-invalid={Boolean(formState.errors.legalEntityTypeId)} className={selectClass} id="organization-legal-entity"><option value="">Sin informar</option>{catalogs.legalEntityTypes.filter(item => item.countryId === null || item.countryId === watch('homeCountryId')).map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select>
                </Field>
                <Field
                  error={formState.errors.organizationSizeId?.message}
                  hint="Cantidad de personas activas que forman parte del equipo."
                  label="Tamaño del equipo"
                  requirement="recommended"
                >
                  <select {...register('organizationSizeId', optionalNumber)} aria-invalid={Boolean(formState.errors.organizationSizeId)} className={selectClass} id="organization-size"><option value="">Sin informar</option>{visibleOrganizationSizes.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select>
                </Field>
              </div>
              <Field
                error={formState.errors.websiteUrl?.message}
                hint="Puedes escribir solo el dominio; lo guardaremos de forma segura con https://."
                label="Sitio web"
              >
                <Input
                  {...register('websiteUrl')}
                  aria-invalid={Boolean(formState.errors.websiteUrl)}
                  id="organization-website"
                  inputMode="url"
                  placeholder="onara.org"
                  type="text"
                />
              </Field>
              <Field error={formState.errors.description?.message} label="Descripción" requirement="recommended"><textarea aria-invalid={Boolean(formState.errors.description)} className={textareaClass} id="organization-description" {...register('description')} placeholder="Propósito, experiencia y territorio de trabajo" /></Field>
            </>}

            {step === 1 && <>
              <MultiChoice error={formErrorMessage(formState.errors.countryIds)} id="organization-countries" label="Países donde trabaja" items={catalogs.countries} requirement="recommended" selected={countries} onChange={value => {
                setValue('countryIds', value, { shouldDirty: true })
                clearErrors('countryIds')
                const validRegionIds = catalogs.regions.filter(region => value.includes(region.countryId)).map(region => region.id)
                setValue('regionIds', regions.filter(regionId => validRegionIds.includes(regionId)), { shouldDirty: true })
              }} />
              {visibleRegions.length > 0 && <MultiChoice error={formErrorMessage(formState.errors.regionIds)} id="organization-regions" label="Regiones" items={visibleRegions} selected={regions} onChange={value => {
                setValue('regionIds', value, { shouldDirty: true })
                clearErrors('regionIds')
              }} />}
              <MultiChoice error={formErrorMessage(formState.errors.categoryIds)} id="organization-categories" label="Áreas de impacto" items={catalogs.fundingCategories} requirement="recommended" selected={categories} onChange={value => {
                setValue('categoryIds', value, { shouldDirty: true })
                clearErrors('categoryIds')
              }} />
              <MultiChoice error={formErrorMessage(formState.errors.beneficiaryTypeIds)} id="organization-beneficiaries" label="Poblaciones beneficiarias" items={catalogs.beneficiaryTypes} requirement="recommended" selected={beneficiaries} onChange={value => {
                setValue('beneficiaryTypeIds', value, { shouldDirty: true })
                clearErrors('beneficiaryTypeIds')
              }} />
              <MultiChoice error={formErrorMessage(formState.errors.projectTypeIds)} id="organization-project-types" label="Tipos de proyecto" items={visibleProjectTypes} requirement="recommended" selected={projectTypes} onChange={value => {
                setValue('projectTypeIds', value, { shouldDirty: true })
                clearErrors('projectTypeIds')
              }} />
            </>}

            {step === 2 && <>
              <Field error={formState.errors.previousFundingExperience?.message} label="¿La organización tiene experiencia previa con financiadores?">
                <select {...register('previousFundingExperience', { valueAsNumber: true, onChange: event => {
                  if (Number(event.target.value) !== 2) {
                    setValue('fundingExperienceTypeIds', [], { shouldDirty: true })
                    clearErrors('fundingExperienceTypeIds')
                  }
                } })} aria-invalid={Boolean(formState.errors.previousFundingExperience)} className={selectClass} id="organization-funding-experience">
                  <option value={0}>Sin informar</option><option value={1}>Aún no</option><option value={2}>Sí, tenemos experiencia</option>
                </select>
              </Field>
              {previousFundingExperience === 2 && (catalogs.fundingExperienceTypes ?? []).length > 0 &&
                <MultiChoice
                  error={formErrorMessage(formState.errors.fundingExperienceTypeIds)}
                  id="organization-funding-experience-types"
                  items={catalogs.fundingExperienceTypes ?? []}
                  label="Experiencia previa con financiadores"
                  onChange={value => {
                    setValue('fundingExperienceTypeIds', value, { shouldDirty: true })
                    clearErrors('fundingExperienceTypeIds')
                  }}
                  selected={fundingExperienceTypeIds}
                />}

              <section className="grid gap-4 rounded-xl border p-4" aria-labelledby="desired-funding-heading">
                <div>
                  <h2 className="text-base font-semibold" id="desired-funding-heading">Monto de financiamiento que busca habitualmente <span className="text-xs font-normal text-muted-foreground">· Recomendado</span></h2>
                  <p className="mt-1 text-xs leading-5 text-muted-foreground">Elige una referencia en USD o conserva un rango personalizado. Este dato describe a la organización, no reemplaza el monto de cada proyecto.</p>
                </div>
                <Field label="Rango habitual" requirement="recommended">
                  <select className={selectClass} onChange={event => applyDesiredFundingPreset(event.target.value)} value={desiredFundingPreset}>
                    <option value="">Sin informar</option>
                    {desiredFundingPresets.map(preset => <option key={preset.key} value={preset.key}>{preset.label}</option>)}
                    <option value="custom">Rango personalizado</option>
                  </select>
                </Field>
                <div className="grid gap-4 sm:grid-cols-3">
                  <Field
                    error={formState.errors.desiredFundingCurrency?.message}
                    hint="Es obligatoria solo cuando informas al menos un monto."
                    label="Moneda objetivo"
                    requirement={desiredFundingMin !== null || desiredFundingMax !== null ? 'required' : 'optional'}
                  >
                    <select
                      {...register('desiredFundingCurrency', { onChange: () => setDesiredFundingPreset('custom') })}
                      aria-invalid={Boolean(formState.errors.desiredFundingCurrency)}
                      aria-required={desiredFundingMin !== null || desiredFundingMax !== null}
                      className={selectClass}
                      id="organization-desired-funding-currency"
                    ><option value="">Sin informar</option>{catalogs.currencies.map(item => <option key={item.code} value={item.code}>{item.code} · {item.name}</option>)}</select>
                  </Field>
                  <Field error={formState.errors.desiredFundingMin?.message} label="Financiamiento mínimo">
                    <Input
                      {...register('desiredFundingMin', { ...optionalNumber, onChange: () => setDesiredFundingPreset('custom') })}
                      aria-invalid={Boolean(formState.errors.desiredFundingMin)}
                      id="organization-desired-funding-min"
                      min="0"
                      step="1"
                      type="number"
                    />
                  </Field>
                  <Field error={formState.errors.desiredFundingMax?.message} label="Financiamiento máximo">
                    <Input
                      {...register('desiredFundingMax', { ...optionalNumber, onChange: () => setDesiredFundingPreset('custom') })}
                      aria-invalid={Boolean(formState.errors.desiredFundingMax)}
                      id="organization-desired-funding-max"
                      min="0"
                      step="1"
                      type="number"
                    />
                  </Field>
                </div>
              </section>

              <section className="grid gap-4 rounded-xl border p-4" aria-labelledby="annual-budget-heading">
                <div>
                  <h2 className="text-base font-semibold" id="annual-budget-heading">Presupuesto anual de la organización <span className="text-xs font-normal text-muted-foreground">· Opcional</span></h2>
                  <p className="mt-1 text-xs leading-5 text-muted-foreground">Puedes elegir una referencia en USD, usar otra moneda o dejar el rango sin informar.</p>
                </div>
                <Field label="Rango de presupuesto anual">
                  <select className={selectClass} onChange={event => applyAnnualBudgetPreset(event.target.value)} value={annualBudgetPreset}>
                    <option value="">Sin informar</option>
                    {annualBudgetPresets.map(preset => <option key={preset.key} value={preset.key}>{preset.label}</option>)}
                    <option value="custom">Rango personalizado</option>
                  </select>
                </Field>
                <div className="grid gap-4 sm:grid-cols-3">
                  <Field
                    error={formState.errors.annualBudgetCurrency?.message}
                    hint="Es obligatoria solo cuando informas al menos un monto."
                    label="Moneda del presupuesto anual"
                    requirement={annualBudgetMin !== null || annualBudgetMax !== null ? 'required' : 'optional'}
                  >
                    <select
                      {...register('annualBudgetCurrency', { onChange: () => setAnnualBudgetPreset('custom') })}
                      aria-invalid={Boolean(formState.errors.annualBudgetCurrency)}
                      aria-required={annualBudgetMin !== null || annualBudgetMax !== null}
                      className={selectClass}
                      id="organization-annual-budget-currency"
                    ><option value="">Sin informar</option>{catalogs.currencies.map(item => <option key={item.code} value={item.code}>{item.code} · {item.name}</option>)}</select>
                  </Field>
                  <Field error={formState.errors.annualBudgetMin?.message} label="Presupuesto anual mínimo">
                    <Input
                      {...register('annualBudgetMin', { ...optionalNumber, onChange: () => setAnnualBudgetPreset('custom') })}
                      aria-invalid={Boolean(formState.errors.annualBudgetMin)}
                      id="organization-annual-budget-min"
                      min="0"
                      step="1"
                      type="number"
                    />
                  </Field>
                  <Field error={formState.errors.annualBudgetMax?.message} label="Presupuesto anual máximo">
                    <Input
                      {...register('annualBudgetMax', { ...optionalNumber, onChange: () => setAnnualBudgetPreset('custom') })}
                      aria-invalid={Boolean(formState.errors.annualBudgetMax)}
                      id="organization-annual-budget-max"
                      min="0"
                      step="1"
                      type="number"
                    />
                  </Field>
                </div>
              </section>

              <Field error={formState.errors.experienceSummary?.message} label="Resumen de experiencia"><textarea {...register('experienceSummary')} aria-invalid={Boolean(formState.errors.experienceSummary)} className={textareaClass} id="organization-experience-summary" placeholder="Cuéntanos brevemente sobre tu experiencia obteniendo financiamiento." /></Field>
              <MultiChoice error={formErrorMessage(formState.errors.languages)} id="organization-languages" label="Idiomas de trabajo" items={catalogs.languages} requirement="recommended" selected={(watch('languages') ?? []).map(item => item.languageId)} onChange={value => {
                setValue('languages', value.map(languageId => ({ languageId, proficiency: null })), { shouldDirty: true })
                clearErrors('languages')
              }} />
            </>}

            {update.isError && <ValidationSummary
              error={update.error}
              id={errorSummaryId}
              onTargetClick={navigateToProfileError}
              targets={profileErrorTargets}
            />}
            {update.isSuccess && <p className="flex items-center gap-2 rounded-lg bg-accent p-3 text-sm font-medium text-accent-foreground"><Check className="size-4" /> Perfil guardado correctamente.</p>}
          </CardContent>
        </Card>
        <div className="mt-4 flex items-center justify-between gap-3">
          <Button disabled={step === 0} onClick={() => setStep(value => value - 1)} type="button" variant="outline"><ChevronLeft className="size-4" /> Anterior</Button>
          <div className="flex gap-2">
            <Button disabled={!profile.canEdit || update.isPending || !formState.isDirty} type="submit">
              {update.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Save className="size-4" />} Guardar
            </Button>
            {step < steps.length - 1 && <Button onClick={() => setStep(value => value + 1)} type="button" variant="outline">Siguiente <ChevronRight className="size-4" /></Button>}
          </div>
        </div>
      </form>
    </div>
  )
}

export function OrganizationWorkspacePage({ onboarding = false }: { onboarding?: boolean }) {
  const catalogs = useQuery({ queryKey: ['organization-catalogs'], queryFn: ({ signal }) => organizationApi.catalogs(signal), staleTime: 60 * 60 * 1000 })
  const organizations = useQuery({ queryKey: ['organizations'], queryFn: ({ signal }) => organizationApi.list(signal) })
  const organizationId = organizations.data?.[0]?.publicId
  const profile = useQuery({
    queryKey: ['organization-profile', organizationId],
    queryFn: ({ signal }) => organizationApi.profile(organizationId!, signal),
    enabled: Boolean(organizationId),
  })

  if (catalogs.isPending || organizations.isPending || (organizationId && profile.isPending)) return <LoadingCard />
  if (catalogs.isError || organizations.isError || profile.isError || !catalogs.data) {
    return <Card><CardContent className="p-8"><h1 className="text-xl font-bold">No pudimos cargar la organización</h1><p className="mt-2 text-sm text-muted-foreground">Comprueba que la API y Azure SQL estén disponibles y vuelve a intentarlo.</p></CardContent></Card>
  }
  if (!organizationId) return <CreateOrganization catalogs={catalogs.data} />
  if (!profile.data) return <LoadingCard />
  return <ProfileEditor catalogs={catalogs.data} onboarding={onboarding} profile={profile.data} />
}
