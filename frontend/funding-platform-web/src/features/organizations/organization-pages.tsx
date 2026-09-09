import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Building2, Check, ChevronLeft, ChevronRight, LoaderCircle, Plus, Save, X } from 'lucide-react'
import { useEffect, useRef, useState, type ReactNode } from 'react'
import { useForm, type FieldPath } from 'react-hook-form'
import { useTranslation } from 'react-i18next'
import { catalogName, catalogLanguage, catalogAliases, type CatalogKind } from '@/i18n/catalog-labels'
import { workspaceMessage, workspaceRequestError, type OrganizationTextKey } from '@/i18n/workspace-messages'

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

const steps = ['organization.stepsIdentity', 'organization.stepsImpact', 'organization.stepsFunding'] as const
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
  label: OrganizationTextKey
  minimum: number | null
  maximum: number | null
}

interface CreateOrganizationValues {
  name: string
  homeCountryId: number
  organizationTypeId: number
}

const desiredFundingPresets: FinancialPreset[] = [
  { key: 'up-to-25k', label: 'organization.upTo25', minimum: null, maximum: 25_000 },
  { key: '25k-100k', label: 'organization.range25to100', minimum: 25_000, maximum: 100_000 },
  { key: '100k-500k', label: 'organization.range100to500', minimum: 100_000, maximum: 500_000 },
  { key: 'over-500k', label: 'organization.over500', minimum: 500_000, maximum: null },
]

const annualBudgetPresets: FinancialPreset[] = [
  { key: 'up-to-50k', label: 'organization.upTo50', minimum: null, maximum: 50_000 },
  { key: '50k-250k', label: 'organization.range50to250', minimum: 50_000, maximum: 250_000 },
  { key: '250k-1m', label: 'organization.range250to1m', minimum: 250_000, maximum: 1_000_000 },
  { key: 'over-1m', label: 'organization.over1m', minimum: 1_000_000, maximum: null },
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
  customimpactareas: 'customImpactAreas',
  custombeneficiarytypes: 'customBeneficiaryTypes',
  customprojecttypes: 'customProjectTypes',
  customlanguages: 'customLanguages',
  customtaxonomyvalues: 'customImpactAreas',
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
  customimpactareas: 'organization-custom-impact-areas',
  custombeneficiarytypes: 'organization-custom-beneficiary-types',
  customprojecttypes: 'organization-custom-project-types',
  customlanguages: 'organization-custom-languages',
  customtaxonomyvalues: 'organization-custom-impact-areas',
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

function RequirementLabel({ requirement }: { requirement: FieldRequirement }) {
  const { t } = useTranslation()
  if (requirement === 'required') {
    return <><span aria-hidden="true" className="text-destructive"> *</span><span className="sr-only">{t('organization.required')}</span></>
  }

  return <span className="text-xs font-normal text-muted-foreground"> · {requirement === 'recommended' ? t('organization.recommended') : t('organization.optional')}</span>
}

function Field({ label, hint, error, requirement = 'optional', children }: {
  label: string
  hint?: string
  error?: string
  requirement?: FieldRequirement
  children: ReactNode
}) {
  useTranslation()
  return (
    <label className="grid gap-1.5 text-sm font-semibold">
      <span>{label}<RequirementLabel requirement={requirement} /></span>
      {children}
      {hint && <span className="text-xs font-normal text-muted-foreground">{hint}</span>}
      {error && <span className="text-xs font-normal text-destructive" role="alert">{workspaceMessage(error)}</span>}
    </label>
  )
}

function apiValidationEntries(error: unknown): ApiValidationEntry[] {
  if (!(error instanceof ApiError)) {
    return [{ key: 'request', message: 'organization.saveFailure' }]
  }

  const entries = Object.entries(error.problem.errors ?? {}).flatMap(([key, messages]) =>
    messages.map(message => ({ key, message })),
  )
  if (entries.length > 0) return entries

  return [{ key: 'request', message: workspaceRequestError(error, 'organization') }]
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
  const { t } = useTranslation()
  const entries = apiValidationEntries(error)
  return (
    <div className="rounded-lg border border-destructive/50 bg-destructive/10 p-4 text-sm text-foreground" id={id} role="alert" tabIndex={-1}>
      <p className="font-semibold">{t('organization.validationSummary')}</p>
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
                  >{workspaceMessage(entry.message)}</a>
                : workspaceMessage(entry.message)}
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
  if (['countryids', 'regionids', 'categoryids', 'beneficiarytypeids', 'projecttypeids',
    'customimpactareas', 'custombeneficiarytypes', 'customprojecttypes', 'customtaxonomyvalues'].includes(normalized)) return 1
  if (
    normalized.startsWith('annualbudget') ||
    normalized.startsWith('desiredfunding') ||
    ['previousfundingexperience', 'fundingexperiencetypeids', 'experiencesummary', 'languages', 'customlanguages'].includes(normalized)
  ) return 2
  return 0
}

function normalizeWebsiteUrl(value: string | null) {
  const normalized = value?.trim()
  if (!normalized) return null
  return /^[a-z][a-z\d+.-]*:/i.test(normalized) ? normalized : `https://${normalized}`
}

function LoadingCard() {
  const { t } = useTranslation()
  return (
    <Card><CardContent className="flex items-center gap-3 p-8 text-muted-foreground">
      <LoaderCircle className="size-5 animate-spin" /> {t('organization.loading')}
    </CardContent></Card>
  )
}

function CreateOrganization({ catalogs }: { catalogs: OrganizationCatalogs }) {
  const { t } = useTranslation()
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
        <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{t('organization.onboardingStep')}</p>
        <h1 className="text-3xl font-bold tracking-tight">{t('organization.createTitle')}</h1>
        <p className="leading-7 text-muted-foreground">
          {t('organization.createHelp')}
        </p>
      </div>
      <Card>
        <CardHeader><CardTitle>{t('organization.essentials')}</CardTitle></CardHeader>
        <CardContent>
          <form className="grid gap-5" noValidate onSubmit={handleSubmit((values) => create.mutate(values))}>
            <p className="text-sm text-muted-foreground"><span aria-hidden="true" className="font-semibold text-destructive">*</span> {t('organization.requiredGuide')}</p>
            <Field error={formState.errors.name?.message} label={t('organization.publicName')} requirement="required">
              <Input
                {...register('name', {
                  required: 'organization.nameRequired',
                  maxLength: { value: 250, message: 'organization.nameMax' },
                })}
                aria-invalid={Boolean(formState.errors.name)}
                aria-required="true"
                autoComplete="organization"
                id="create-organization-name"
                placeholder={t('organization.namePlaceholder')}
                required
              />
            </Field>
            <div className="grid gap-4 sm:grid-cols-2">
              <Field error={formState.errors.homeCountryId?.message} label={t('organization.homeCountry')} requirement="required">
                <select
                  {...register('homeCountryId', {
                    valueAsNumber: true,
                    validate: value => value > 0 || 'organization.countryValid',
                  })}
                  aria-invalid={Boolean(formState.errors.homeCountryId)}
                  aria-required="true"
                  className={selectClass}
                  id="create-organization-country"
                  required
                >
                  {catalogs.countries.map(item => <option lang={catalogLanguage('countries', item)} key={item.id} value={item.id}>{catalogName('countries', item)}</option>)}
                </select>
              </Field>
              <Field error={formState.errors.organizationTypeId?.message} label={t('organization.organizationType')} requirement="required">
                <select
                  {...register('organizationTypeId', {
                    valueAsNumber: true,
                    validate: value => value > 0 || 'organization.typeValid',
                  })}
                  aria-invalid={Boolean(formState.errors.organizationTypeId)}
                  aria-required="true"
                  className={selectClass}
                  id="create-organization-type"
                  required
                >
                  {catalogs.organizationTypes.map(item => <option lang={catalogLanguage('organizationTypes', item)} key={item.id} value={item.id}>{catalogName('organizationTypes', item)}</option>)}
                </select>
              </Field>
            </div>
            {create.isError && <ValidationSummary error={create.error} id="create-organization-error-summary" targets={createErrorTargets} />}
            <Button className="sm:justify-self-start" disabled={create.isPending || formState.isSubmitting} type="submit">
              {create.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Building2 className="size-4" />}
              {t('organization.create')}
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}

function MultiChoice({
  catalog,
  label,
  items,
  selected,
  onChange,
  error,
  id,
  requirement = 'optional',
}: {
  label: string
  catalog: CatalogKind
  items: (CatalogOption<number> & { legacy?: true })[]
  selected: number[]
  onChange: (value: number[]) => void
  error?: string
  id?: string
  requirement?: FieldRequirement
}) {
  useTranslation()
  function toggle(id: number) {
    onChange(selected.includes(id) ? selected.filter(value => value !== id) : [...selected, id])
  }
  return (
    <fieldset aria-invalid={Boolean(error)} className="space-y-2" id={id} tabIndex={-1}>
      <legend className="text-sm font-semibold">{label}<RequirementLabel requirement={requirement} /></legend>
      <div className="grid gap-2 sm:grid-cols-2">
        {items.map(item => (
          <label className="flex cursor-pointer items-center gap-2 rounded-lg border bg-background px-3 py-2 text-sm" key={item.id}>
            <input checked={selected.includes(item.id)} onChange={() => toggle(item.id)} type="checkbox" />
            <span lang={catalogLanguage(catalog, item)}>{catalogName(catalog, item)}</span>
          </label>
        ))}
      </div>
      {error && <span className="block text-xs text-destructive" role="alert">{workspaceMessage(error)}</span>}
    </fieldset>
  )
}

function customComparison(value: string) {
  return value.trim().replace(/\s+/g, ' ').normalize('NFD')
    .replace(/\p{M}/gu, '').toLocaleUpperCase('es')
}

function CustomTaxonomyChoice({
  catalog,
  label,
  items,
  selected,
  onSelectedChange,
  customValues,
  onCustomChange,
  officialError,
  customError,
  id,
  inputId,
  otherCode,
}: {
  label: string
  catalog: CatalogKind
  items: (CatalogOption<number> & { legacy?: true })[]
  selected: number[]
  onSelectedChange: (value: number[]) => void
  customValues: string[]
  onCustomChange: (value: string[]) => void
  officialError?: string
  customError?: string
  id: string
  inputId: string
  otherCode: string
}) {
  const { t } = useTranslation()
  const [draft, setDraft] = useState('')
  const [localError, setLocalError] = useState<string>()
  const [editorOpen, setEditorOpen] = useState(false)
  const input = useRef<HTMLInputElement>(null)
  const other = items.find(item => item.code.toLocaleLowerCase() === otherCode.toLocaleLowerCase())
  const otherSelected = other ? selected.includes(other.id) : false
  const showCustomEditor = editorOpen || customValues.length > 0 || otherSelected || Boolean(customError)
  const errorId = `${inputId}-error`

  function toggle(item: CatalogOption<number>) {
    if (item.id === other?.id) {
      if (selected.includes(item.id)) {
        onSelectedChange(selected.filter(value => value !== item.id))
        setEditorOpen(customValues.length > 0)
        return
      }
      setEditorOpen(value => !value)
      window.setTimeout(() => input.current?.focus(), 0)
      return
    }
    const willSelect = !selected.includes(item.id)
    onSelectedChange(willSelect ? [...selected, item.id] : selected.filter(value => value !== item.id))
  }

  function addCustom() {
    const name = draft.trim().replace(/\s+/g, ' ')
    if (name.length < 2 || name.length > 100) {
      setLocalError('organization.customLength')
      return
    }
    if (customValues.length >= 5) {
      setLocalError('organization.customLimit')
      return
    }
    const normalized = customComparison(name)
    if (customValues.some(value => customComparison(value) === normalized)) {
      setLocalError('organization.customDuplicate')
      return
    }
    if (items.some(item => catalogAliases(catalog, item).some(name => customComparison(name) === normalized))) {
      setLocalError('organization.customOfficial')
      return
    }
    onCustomChange([...customValues, name])
    if (other) onSelectedChange(selected.filter(value => value !== other.id))
    setEditorOpen(true)
    setDraft('')
    setLocalError(undefined)
  }

  return (
    <fieldset aria-invalid={Boolean(officialError || customError || localError)} className="space-y-2" id={id} tabIndex={-1}>
      <legend className="text-sm font-semibold">{label}<RequirementLabel requirement="recommended" /></legend>
      <div className="grid gap-2 sm:grid-cols-2">
        {items.map(item => item.id === other?.id && !otherSelected
          ? <button
              aria-controls={inputId}
              aria-expanded={showCustomEditor}
              className="flex items-center gap-2 rounded-lg border bg-background px-3 py-2 text-left text-sm"
              key={item.id}
              onClick={() => toggle(item)}
              type="button"
            ><Plus className="size-4" /> {t('organization.addOther')}</button>
          : <label className="flex cursor-pointer items-center gap-2 rounded-lg border bg-background px-3 py-2 text-sm" key={item.id}>
              <input checked={selected.includes(item.id)} onChange={() => toggle(item)} type="checkbox" />
              <span lang={catalogLanguage(catalog, item)}>{catalogName(catalog, item)}</span>{item.legacy ? t('organization.legacyType', { name: '' }) : ''}{item.id === other?.id ? t('organization.legacyValue') : ''}
            </label>)}
      </div>
      {officialError && <span className="block text-xs text-destructive" role="alert">{workspaceMessage(officialError)}</span>}
      {showCustomEditor && <div className="grid gap-2 rounded-lg border border-dashed bg-muted/30 p-3">
        {otherSelected && customValues.length === 0 &&
          <p className="text-xs font-medium text-muted-foreground">{t('organization.otherUnspecified')}</p>}
        <label className="text-xs font-semibold" htmlFor={inputId}>{t('organization.addIn', { label: label.toLocaleLowerCase() })}</label>
        <div className="flex flex-col gap-2 sm:flex-row">
          <Input
            aria-describedby={localError || customError ? errorId : undefined}
            aria-invalid={Boolean(localError || customError)}
            id={inputId}
            maxLength={100}
            onChange={event => {
              setDraft(event.target.value)
              setLocalError(undefined)
            }}
            onKeyDown={event => {
              if (event.key !== 'Enter') return
              event.preventDefault()
              addCustom()
            }}
            placeholder={t('organization.customPlaceholder')}
            ref={input}
            value={draft}
          />
          <Button disabled={!draft.trim() || customValues.length >= 5} onClick={addCustom} type="button" variant="outline">
            <Plus className="size-4" /> {t('organization.add')}
          </Button>
        </div>
        {customValues.length > 0 && <div aria-label={t('organization.customOptions', { label })} className="flex flex-wrap gap-2">
          {customValues.map(value => <span className="inline-flex items-center gap-1 rounded-full bg-primary/10 px-3 py-1 text-xs font-medium text-primary" key={value}>
            {value}
            <button
              aria-label={t('organization.remove', { value })}
              className="rounded-full p-0.5 hover:bg-primary/15"
              onClick={() => onCustomChange(customValues.filter(item => item !== value))}
              type="button"
            ><X className="size-3" /></button>
          </span>)}
        </div>}
      </div>}
      {(localError || customError) && <span className="block text-xs text-destructive" id={errorId} role="alert">{workspaceMessage(localError ?? customError)}</span>}
    </fieldset>
  )
}

function ProfileEditor({ profile, catalogs, onboarding }: {
  profile: OrganizationProfile
  catalogs: OrganizationCatalogs
  onboarding: boolean
}) {
  const { t } = useTranslation()
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
    defaultValues: {
      ...profile,
      fundingExperienceTypeIds: profile.fundingExperienceTypeIds ?? [],
      customImpactAreas: profile.customImpactAreas ?? [],
      customBeneficiaryTypes: profile.customBeneficiaryTypes ?? [],
      customProjectTypes: profile.customProjectTypes ?? [],
      customLanguages: profile.customLanguages ?? [],
    },
  })
  useEffect(() => {
    reset({
      ...profile,
      fundingExperienceTypeIds: profile.fundingExperienceTypeIds ?? [],
      customImpactAreas: profile.customImpactAreas ?? [],
      customBeneficiaryTypes: profile.customBeneficiaryTypes ?? [],
      customProjectTypes: profile.customProjectTypes ?? [],
      customLanguages: profile.customLanguages ?? [],
    })
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
  const customImpactAreas = watch('customImpactAreas') ?? []
  const customBeneficiaryTypes = watch('customBeneficiaryTypes') ?? []
  const customProjectTypes = watch('customProjectTypes') ?? []
  const customLanguages = watch('customLanguages') ?? []
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
        legacy: true as const,
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
          legacy: true as const,
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
        setError(minimumField, { type: 'validate', message: 'organization.minimumNegative' })
        firstTarget ??= `${targetPrefix}-min`
      }
      if (hasMaximum && maximum < 0) {
        setError(maximumField, { type: 'validate', message: 'organization.maximumNegative' })
        firstTarget ??= `${targetPrefix}-max`
      }
      if (hasMinimum && hasMaximum && maximum < minimum) {
        setError(maximumField, { type: 'validate', message: 'organization.rangeOrder' })
        firstTarget ??= `${targetPrefix}-max`
      }
      if ((hasMinimum || hasMaximum) && !currency) {
        setError(currencyField, { type: 'validate', message: 'organization.rangeCurrency' })
        firstTarget ??= `${targetPrefix}-currency`
      }
      if (!hasMinimum && !hasMaximum && currency) {
        setError(currencyField, { type: 'validate', message: 'organization.rangeEmpty' })
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
          <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{onboarding ? t('organization.onboarding') : t('organization.organization')}</p>
          <h1 className="mt-1 text-3xl font-bold tracking-tight">{t('organization.profileTitle', { name: profile.name })}</h1>
          <p className="mt-2 text-muted-foreground">{t('organization.profileVersion', { version: profile.profileVersion, percent: profile.profileCompleteness })}</p>
        </div>
        <div className="h-2 w-48 overflow-hidden rounded-full bg-muted" role="progressbar" aria-label={t('organization.profileCompletion')} aria-valuemin={0} aria-valuemax={100} aria-valuenow={profile.profileCompleteness} aria-valuetext={t('organization.completeness', { percent: profile.profileCompleteness })}>
          <div className="h-full bg-primary transition-all" style={{ width: `${profile.profileCompleteness}%` }} />
        </div>
      </div>

      <div className="grid grid-cols-1 gap-2 sm:grid-cols-3" role="group" aria-label={t('organization.profileSteps')}>
        {steps.map((label, index) => (
          <button className={`rounded-lg border px-3 py-3 text-sm font-semibold ${step === index ? 'border-primary bg-accent text-accent-foreground' : 'bg-card text-muted-foreground'}`} key={label} onClick={() => setStep(index)} type="button">
            <span className="hidden sm:inline">{index + 1}. </span>{t(label)}
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
              <span aria-hidden="true" className="font-semibold text-destructive">*</span> {t('organization.profileGuide')}
            </p>
            {step === 0 && <>
              <div className="grid gap-4 sm:grid-cols-2">
                <Field error={formState.errors.name?.message} label={t('organization.publicName')} requirement="required">
                  <Input
                    {...register('name', {
                      required: 'organization.nameRequired',
                      maxLength: { value: 250, message: 'organization.nameMax' },
                    })}
                    aria-invalid={Boolean(formState.errors.name)}
                    aria-required="true"
                    id="organization-name"
                    required
                  />
                </Field>
                <Field error={formState.errors.legalName?.message} label={t('organization.legalName')}>
                  <Input {...register('legalName')} aria-invalid={Boolean(formState.errors.legalName)} id="organization-legal-name" />
                </Field>
                <Field error={formState.errors.taxIdentifier?.message} label={t('organization.taxId')}>
                  <Input {...register('taxIdentifier')} aria-invalid={Boolean(formState.errors.taxIdentifier)} id="organization-tax-identifier" />
                </Field>
                <Field error={formState.errors.establishedYear?.message} label={t('organization.establishedYear')} requirement="recommended">
                  <Input
                    {...register('establishedYear', {
                      ...optionalNumber,
                      min: { value: 1800, message: 'organization.yearMin' },
                      max: { value: new Date().getFullYear(), message: 'organization.yearFuture' },
                    })}
                    aria-invalid={Boolean(formState.errors.establishedYear)}
                    id="organization-established-year"
                    max={new Date().getFullYear()}
                    min="1800"
                    type="number"
                  />
                </Field>
                <Field error={formState.errors.homeCountryId?.message} label={t('organization.homeCountry')} requirement="required">
                  <select
                    {...register('homeCountryId', {
                      valueAsNumber: true,
                      validate: value => value > 0 || 'organization.countryValid',
                    })}
                    aria-invalid={Boolean(formState.errors.homeCountryId)}
                    aria-required="true"
                    className={selectClass}
                    id="organization-home-country"
                    required
                  >{catalogs.countries.map(item => <option lang={catalogLanguage('countries', item)} key={item.id} value={item.id}>{catalogName('countries', item)}</option>)}</select>
                </Field>
                <Field error={formState.errors.organizationTypeId?.message} label={t('organization.organizationType')} requirement="required">
                  <select
                    {...register('organizationTypeId', {
                      valueAsNumber: true,
                      validate: value => value > 0 || 'organization.typeValid',
                    })}
                    aria-invalid={Boolean(formState.errors.organizationTypeId)}
                    aria-required="true"
                    className={selectClass}
                    id="organization-type"
                    required
                  >{catalogs.organizationTypes.map(item => <option lang={catalogLanguage('organizationTypes', item)} key={item.id} value={item.id}>{catalogName('organizationTypes', item)}</option>)}</select>
                </Field>
                <Field error={formState.errors.legalEntityTypeId?.message} label={t('organization.legalEntity')} requirement="recommended">
                  <select {...register('legalEntityTypeId', optionalNumber)} aria-invalid={Boolean(formState.errors.legalEntityTypeId)} className={selectClass} id="organization-legal-entity"><option value="">{t('organization.unspecified')}</option>{catalogs.legalEntityTypes.filter(item => item.countryId === null || item.countryId === watch('homeCountryId')).map(item => <option lang={catalogLanguage('legalEntityTypes', item)} key={item.id} value={item.id}>{catalogName('legalEntityTypes', item)}</option>)}</select>
                </Field>
                <Field
                  error={formState.errors.organizationSizeId?.message}
                  hint={t('organization.teamSizeHelp')}
                  label={t('organization.teamSize')}
                  requirement="recommended"
                >
                  <select {...register('organizationSizeId', optionalNumber)} aria-invalid={Boolean(formState.errors.organizationSizeId)} className={selectClass} id="organization-size"><option value="">{t('organization.unspecified')}</option>{visibleOrganizationSizes.map(item => <option lang={catalogLanguage('organizationSizes', item)} key={item.id} value={item.id}>{'legacy' in item && item.legacy ? t('organization.legacySize', { name: catalogName('organizationSizes', item) }) : catalogName('organizationSizes', item)}</option>)}</select>
                </Field>
              </div>
              <Field
                error={formState.errors.websiteUrl?.message}
                hint={t('organization.websiteHelp')}
                label={t('organization.website')}
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
              <Field error={formState.errors.description?.message} label={t('organization.description')} requirement="recommended"><textarea aria-invalid={Boolean(formState.errors.description)} className={textareaClass} id="organization-description" {...register('description')} placeholder={t('organization.descriptionPlaceholder')} /></Field>
            </>}

            {step === 1 && <>
              <MultiChoice error={formErrorMessage(formState.errors.countryIds)} id="organization-countries" label={t('organization.countries')} catalog="countries" items={catalogs.countries} requirement="recommended" selected={countries} onChange={value => {
                setValue('countryIds', value, { shouldDirty: true })
                clearErrors('countryIds')
                const validRegionIds = catalogs.regions.filter(region => value.includes(region.countryId)).map(region => region.id)
                setValue('regionIds', regions.filter(regionId => validRegionIds.includes(regionId)), { shouldDirty: true })
              }} />
              {visibleRegions.length > 0 && <MultiChoice error={formErrorMessage(formState.errors.regionIds)} id="organization-regions" label={t('organization.regions')} catalog="regions" items={visibleRegions} selected={regions} onChange={value => {
                setValue('regionIds', value, { shouldDirty: true })
                clearErrors('regionIds')
              }} />}
              <p className="rounded-lg bg-muted p-3 text-xs leading-5 text-muted-foreground">
                {t('organization.customHelp')}
              </p>
              <CustomTaxonomyChoice
                customValues={customImpactAreas}
                customError={formErrorMessage(formState.errors.customImpactAreas)}
                id="organization-categories"
                inputId="organization-custom-impact-areas"
                catalog="fundingCategories" items={catalogs.fundingCategories}
                label={t('organization.impactAreas')}
                officialError={formErrorMessage(formState.errors.categoryIds)}
                onCustomChange={value => {
                  setValue('customImpactAreas', value, { shouldDirty: true })
                  clearErrors('customImpactAreas')
                }}
                onSelectedChange={value => {
                  setValue('categoryIds', value, { shouldDirty: true })
                  clearErrors('categoryIds')
                }}
                otherCode="OTHER"
                selected={categories}
              />
              <CustomTaxonomyChoice
                customValues={customBeneficiaryTypes}
                customError={formErrorMessage(formState.errors.customBeneficiaryTypes)}
                id="organization-beneficiaries"
                inputId="organization-custom-beneficiary-types"
                catalog="beneficiaryTypes" items={catalogs.beneficiaryTypes}
                label={t('organization.beneficiaries')}
                officialError={formErrorMessage(formState.errors.beneficiaryTypeIds)}
                onCustomChange={value => {
                  setValue('customBeneficiaryTypes', value, { shouldDirty: true })
                  clearErrors('customBeneficiaryTypes')
                }}
                onSelectedChange={value => {
                  setValue('beneficiaryTypeIds', value, { shouldDirty: true })
                  clearErrors('beneficiaryTypeIds')
                }}
                otherCode="OTHER"
                selected={beneficiaries}
              />
              <CustomTaxonomyChoice
                customValues={customProjectTypes}
                customError={formErrorMessage(formState.errors.customProjectTypes)}
                id="organization-project-types"
                inputId="organization-custom-project-types"
                catalog="projectTypes" items={visibleProjectTypes}
                label={t('organization.projectTypes')}
                officialError={formErrorMessage(formState.errors.projectTypeIds)}
                onCustomChange={value => {
                  setValue('customProjectTypes', value, { shouldDirty: true })
                  clearErrors('customProjectTypes')
                }}
                onSelectedChange={value => {
                  setValue('projectTypeIds', value, { shouldDirty: true })
                  clearErrors('projectTypeIds')
                }}
                otherCode="OTHER"
                selected={projectTypes}
              />
            </>}

            {step === 2 && <>
              <Field error={formState.errors.previousFundingExperience?.message} label={t('organization.previousExperience')}>
                <select {...register('previousFundingExperience', { valueAsNumber: true, onChange: event => {
                  if (Number(event.target.value) !== 2) {
                    setValue('fundingExperienceTypeIds', [], { shouldDirty: true })
                    clearErrors('fundingExperienceTypeIds')
                  }
                } })} aria-invalid={Boolean(formState.errors.previousFundingExperience)} className={selectClass} id="organization-funding-experience">
                  <option value={0}>{t('organization.unspecified')}</option><option value={1}>{t('organization.noExperience')}</option><option value={2}>{t('organization.hasExperience')}</option>
                </select>
              </Field>
              {previousFundingExperience === 2 && (catalogs.fundingExperienceTypes ?? []).length > 0 &&
                <MultiChoice
                  error={formErrorMessage(formState.errors.fundingExperienceTypeIds)}
                  id="organization-funding-experience-types"
                  catalog="fundingExperienceTypes" items={catalogs.fundingExperienceTypes ?? []}
                  label={t('organization.experienceTypes')}
                  onChange={value => {
                    setValue('fundingExperienceTypeIds', value, { shouldDirty: true })
                    clearErrors('fundingExperienceTypeIds')
                  }}
                  selected={fundingExperienceTypeIds}
                />}

              <section className="grid gap-4 rounded-xl border p-4" aria-labelledby="desired-funding-heading">
                <div>
                  <h2 className="text-base font-semibold" id="desired-funding-heading">{t('organization.desiredFunding')} <span className="text-xs font-normal text-muted-foreground">· {t('organization.recommended')}</span></h2>
                  <p className="mt-1 text-xs leading-5 text-muted-foreground">{t('organization.desiredFundingHelp')}</p>
                </div>
                <Field label={t('organization.usualRange')} requirement="recommended">
                  <select className={selectClass} onChange={event => applyDesiredFundingPreset(event.target.value)} value={desiredFundingPreset}>
                    <option value="">{t('organization.unspecified')}</option>
                    {desiredFundingPresets.map(preset => <option key={preset.key} value={preset.key}>{t(preset.label)}</option>)}
                    <option value="custom">{t('organization.customRange')}</option>
                  </select>
                </Field>
                <div className="grid gap-4 sm:grid-cols-3">
                  <Field
                    error={formState.errors.desiredFundingCurrency?.message}
                    hint={t('organization.currencyHelp')}
                    label={t('organization.desiredCurrency')}
                    requirement={desiredFundingMin !== null || desiredFundingMax !== null ? 'required' : 'optional'}
                  >
                    <select
                      {...register('desiredFundingCurrency', { onChange: () => setDesiredFundingPreset('custom') })}
                      aria-invalid={Boolean(formState.errors.desiredFundingCurrency)}
                      aria-required={desiredFundingMin !== null || desiredFundingMax !== null}
                      className={selectClass}
                      id="organization-desired-funding-currency"
                    ><option value="">{t('organization.unspecified')}</option>{catalogs.currencies.map(item => <option lang={catalogLanguage('currencies', item)} key={item.code} value={item.code}>{item.code} · {catalogName('currencies', item)}</option>)}</select>
                  </Field>
                  <Field error={formState.errors.desiredFundingMin?.message} label={t('organization.fundingMinimum')}>
                    <Input
                      {...register('desiredFundingMin', { ...optionalNumber, onChange: () => setDesiredFundingPreset('custom') })}
                      aria-invalid={Boolean(formState.errors.desiredFundingMin)}
                      id="organization-desired-funding-min"
                      min="0"
                      step="1"
                      type="number"
                    />
                  </Field>
                  <Field error={formState.errors.desiredFundingMax?.message} label={t('organization.fundingMaximum')}>
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
                  <h2 className="text-base font-semibold" id="annual-budget-heading">{t('organization.annualBudget')} <span className="text-xs font-normal text-muted-foreground">· {t('organization.optional')}</span></h2>
                  <p className="mt-1 text-xs leading-5 text-muted-foreground">{t('organization.annualBudgetHelp')}</p>
                </div>
                <Field label={t('organization.annualRange')}>
                  <select className={selectClass} onChange={event => applyAnnualBudgetPreset(event.target.value)} value={annualBudgetPreset}>
                    <option value="">{t('organization.unspecified')}</option>
                    {annualBudgetPresets.map(preset => <option key={preset.key} value={preset.key}>{t(preset.label)}</option>)}
                    <option value="custom">{t('organization.customRange')}</option>
                  </select>
                </Field>
                <div className="grid gap-4 sm:grid-cols-3">
                  <Field
                    error={formState.errors.annualBudgetCurrency?.message}
                    hint={t('organization.currencyHelp')}
                    label={t('organization.annualCurrency')}
                    requirement={annualBudgetMin !== null || annualBudgetMax !== null ? 'required' : 'optional'}
                  >
                    <select
                      {...register('annualBudgetCurrency', { onChange: () => setAnnualBudgetPreset('custom') })}
                      aria-invalid={Boolean(formState.errors.annualBudgetCurrency)}
                      aria-required={annualBudgetMin !== null || annualBudgetMax !== null}
                      className={selectClass}
                      id="organization-annual-budget-currency"
                    ><option value="">{t('organization.unspecified')}</option>{catalogs.currencies.map(item => <option lang={catalogLanguage('currencies', item)} key={item.code} value={item.code}>{item.code} · {catalogName('currencies', item)}</option>)}</select>
                  </Field>
                  <Field error={formState.errors.annualBudgetMin?.message} label={t('organization.annualMinimum')}>
                    <Input
                      {...register('annualBudgetMin', { ...optionalNumber, onChange: () => setAnnualBudgetPreset('custom') })}
                      aria-invalid={Boolean(formState.errors.annualBudgetMin)}
                      id="organization-annual-budget-min"
                      min="0"
                      step="1"
                      type="number"
                    />
                  </Field>
                  <Field error={formState.errors.annualBudgetMax?.message} label={t('organization.annualMaximum')}>
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

              <Field error={formState.errors.experienceSummary?.message} label={t('organization.experienceSummary')}><textarea {...register('experienceSummary')} aria-invalid={Boolean(formState.errors.experienceSummary)} className={textareaClass} id="organization-experience-summary" placeholder={t('organization.experiencePlaceholder')} /></Field>
              <p className="rounded-lg bg-muted p-3 text-xs leading-5 text-muted-foreground">
                {t('organization.customLanguagesHelp')}
              </p>
              <CustomTaxonomyChoice
                customValues={customLanguages}
                customError={formErrorMessage(formState.errors.customLanguages)}
                id="organization-languages"
                inputId="organization-custom-languages"
                catalog="languages" items={catalogs.languages}
                label={t('organization.languages')}
                officialError={formErrorMessage(formState.errors.languages)}
                onCustomChange={value => {
                  setValue('customLanguages', value, { shouldDirty: true })
                  clearErrors('customLanguages')
                }}
                onSelectedChange={value => {
                  setValue('languages', value.map(languageId => ({ languageId, proficiency: null })), { shouldDirty: true })
                  clearErrors('languages')
                }}
                otherCode="und"
                selected={(watch('languages') ?? []).map(item => item.languageId)}
              />
            </>}

            {update.isError && <ValidationSummary
              error={update.error}
              id={errorSummaryId}
              onTargetClick={navigateToProfileError}
              targets={profileErrorTargets}
            />}
            {update.isSuccess && <p className="flex items-center gap-2 rounded-lg bg-accent p-3 text-sm font-medium text-accent-foreground"><Check className="size-4" /> {t('organization.saved')}</p>}
          </CardContent>
        </Card>
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
          <Button disabled={step === 0} onClick={() => setStep(value => value - 1)} type="button" variant="outline"><ChevronLeft className="size-4" /> {t('organization.previous')}</Button>
          <div className="flex gap-2">
            <Button disabled={!profile.canEdit || update.isPending || !formState.isDirty} type="submit">
              {update.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Save className="size-4" />} {t('organization.save')}
            </Button>
            {step < steps.length - 1 && <Button onClick={() => setStep(value => value + 1)} type="button" variant="outline">{t('organization.next')} <ChevronRight className="size-4" /></Button>}
          </div>
        </div>
      </form>
    </div>
  )
}

export function OrganizationWorkspacePage({ onboarding = false }: { onboarding?: boolean }) {
  const { t } = useTranslation()
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
    return <Card><CardContent className="p-8"><h1 className="text-xl font-bold">{t('organization.loadFailed')}</h1><p className="mt-2 text-sm text-muted-foreground">{t('organization.loadFailedHelp')}</p></CardContent></Card>
  }
  if (!organizationId) return <CreateOrganization catalogs={catalogs.data} />
  if (!profile.data) return <LoadingCard />
  return <ProfileEditor catalogs={catalogs.data} onboarding={onboarding} profile={profile.data} />
}
