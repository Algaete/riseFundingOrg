import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Archive,
  ArrowLeft,
  CheckCircle2,
  CircleAlert,
  Clock3,
  Globe2,
  Gauge,
  LoaderCircle,
  Plus,
  Save,
  Send,
  Target,
} from 'lucide-react'
import { useEffect, useState, type ReactNode } from 'react'
import { useForm, type FieldPath } from 'react-hook-form'
import { ProjectEnrichmentFields } from './project-enrichment-fields'
import { enrichmentInput } from './project-enrichment'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { catalogName, catalogLanguage, type CatalogKind } from '@/i18n/catalog-labels'
import i18n from '@/i18n'
import { fieldValidationEntries } from '@/i18n/validation-issues'
import { workspaceMessage, workspaceRequestError, workspaceLocale, formatWorkspaceDate } from '@/i18n/workspace-messages'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { organizationApi, type CatalogOption, type OrganizationCatalogs } from '@/features/organizations/organization-api'
import {
  createProjectCommandId,
  projectApi,
  type ProjectDetails,
  type ProjectWriteInput,
} from '@/features/projects/project-api'
import { ProjectAssetsPanel } from '@/features/projects/project-assets-panel'
import { isProjectAssetsEnabled } from '@/features/projects/project-assets-config'

const selectClass = 'h-10 w-full rounded-lg border bg-background px-3 text-sm'
const textareaClass = 'min-h-28 w-full rounded-lg border bg-background px-3 py-2 text-sm'
const statusNames = ['projects.statusIdea', 'projects.statusDesign', 'projects.statusSeeking', 'projects.statusPartial', 'projects.statusFunded', 'projects.statusRunning', 'projects.statusFinished'] as const
const stageNames = ['projects.stageIdea', 'projects.stagePilot', 'projects.stageImplementation', 'projects.stageScaling', 'projects.stageConsolidation', 'projects.stageEvaluation'] as const
const publicationNames = ['projects.draft', 'projects.pending', 'projects.published', 'projects.rejected', 'projects.archived'] as const

function editableStatusOptions(currentStatus?: number) {
  const options = statusNames.map((name, value) => ({ name: workspaceMessage(name), value })).filter(option => option.value >= 2)
  return currentStatus !== undefined && currentStatus < 2
    ? [{ name: i18n.t('projects.legacyStatus', { name: workspaceMessage(statusNames[currentStatus]) }), value: currentStatus }, ...options]
    : options
}

function Field({ label, hint, required = false, error, children }: { label: string; hint?: string; required?: boolean; error?: string; children: ReactNode }) {
  const { t } = useTranslation()
  return <label className="grid gap-1.5 text-sm font-semibold"><span>{label}{required && <><span aria-hidden="true" className="text-destructive"> *</span><span className="sr-only">{t('projects.required')}</span></>}</span>{children}{hint && <span className="text-xs font-normal text-muted-foreground">{hint}</span>}{error && <span className="text-xs font-normal text-destructive" role="alert">{workspaceMessage(error)}</span>}</label>
}

function errorMessage(error: unknown) {
  return workspaceMessage(validationMessages(error)[0] ?? workspaceRequestError(error))
}

function validationMessages(error: unknown) {
  if (!(error instanceof ApiError)) return []
  return fieldValidationEntries(error.problem).map(entry => entry.message)
}

function formatDate(value: string | null) {
  return value
    ? formatWorkspaceDate(value)
    : null
}

function MultiChoice({ catalog, label, items, selected, onChange }: {
  label: string
  catalog: CatalogKind
  items: CatalogOption<number>[]
  selected: number[]
  onChange: (value: number[]) => void
}) {
  const { t } = useTranslation()
  return <fieldset className="space-y-2"><legend className="text-sm font-semibold">{label} <span className="text-xs font-normal text-muted-foreground">· {t('projects.optional')}</span></legend>
    <div className="grid gap-2 sm:grid-cols-2">
      {items.map(item => <label className="flex cursor-pointer items-center gap-2 rounded-lg border bg-background px-3 py-2 text-sm" key={item.id}>
        <input checked={selected.includes(item.id)} onChange={() => onChange(selected.includes(item.id) ? selected.filter(id => id !== item.id) : [...selected, item.id])} type="checkbox" />
        <span>{catalog === 'sustainableDevelopmentGoals' && <>{t('projects.sdgPrefix', { id: item.id })} · </>}<span lang={catalogLanguage(catalog, item)}>{catalogName(catalog, item)}</span></span>
      </label>)}
    </div>
  </fieldset>
}

function emptyProject(): ProjectWriteInput {
  return {
    title: '', summary: null, description: null, status: 2, projectStage: null,
    startDate: null, endDate: null,
    budgetTotal: null, confirmedFunding: null, currency: null, countryIds: [], regionIds: [],
    categoryIds: [], beneficiaryTypeIds: [], projectTypeIds: [],
    sustainableDevelopmentGoalIds: [], enrichment: enrichmentInput(),
  }
}

function toInput(project: ProjectDetails): ProjectWriteInput {
  return {
    title: project.title, summary: project.summary, description: project.description,
    status: project.status, projectStage: project.projectStage ?? null,
    startDate: project.startDate, endDate: project.endDate,
    budgetTotal: project.budgetTotal, confirmedFunding: project.confirmedFunding,
    currency: project.currency, countryIds: project.countryIds, regionIds: project.regionIds,
    categoryIds: project.categoryIds, beneficiaryTypeIds: project.beneficiaryTypeIds,
    projectTypeIds: project.projectTypeIds,
    sustainableDevelopmentGoalIds: project.sustainableDevelopmentGoalIds ?? [],
    enrichment: enrichmentInput(project.enrichment),
  }
}

function ProjectForm({ organizationId, catalogs, project, onDirtyChange }: {
  organizationId: string
  catalogs: OrganizationCatalogs
  project?: ProjectDetails
  onDirtyChange?: (dirty: boolean) => void
}) {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const form = useForm<ProjectWriteInput>({
    defaultValues: project ? toInput(project) : emptyProject(),
  })
  const { register, handleSubmit, watch, setValue, setError, clearErrors, reset, formState } = form
  useEffect(() => { if (project) reset(toInput(project)) }, [project, reset])
  useEffect(() => { onDirtyChange?.(formState.isDirty) }, [formState.isDirty, onDirtyChange])
  const save = useMutation({
    mutationFn: (input: ProjectWriteInput) => project
      ? projectApi.update(organizationId, project.publicId, project.eTag, input)
      : projectApi.create(organizationId, input),
    onSuccess: async result => {
      await queryClient.invalidateQueries({ queryKey: ['projects', organizationId] })
      await queryClient.invalidateQueries({ queryKey: ['project', organizationId, result.publicId] })
      if (!project) void navigate(`/projects/${result.publicId}`, { replace: true })
      else reset(toInput(result as ProjectDetails))
    },
    onError: error => {
      if (!(error instanceof ApiError)) return
      const serverErrors = fieldValidationEntries(error.problem)
      const applyServerError = (field: 'title' | 'summary' | 'description' | 'projectStage' | 'endDate' | 'budgetTotal' | 'confirmedFunding' | 'currency' | 'sustainableDevelopmentGoalIds') => {
        const message = serverErrors.find(entry => entry.key.toLowerCase() === field.toLowerCase())?.message
        if (message) setError(field, { type: 'server', message })
      }
      applyServerError('title')
      applyServerError('summary')
      applyServerError('description')
      applyServerError('projectStage')
      applyServerError('endDate')
      applyServerError('budgetTotal')
      applyServerError('confirmedFunding')
      applyServerError('currency')
      applyServerError('sustainableDevelopmentGoalIds')
      for (const entry of serverErrors) {
        if (/^enrichment\.(problem|solution|beneficiaryCount|locality|latitude|longitude|locationVisibility|soughtPartners|soughtProfessionals|seekingConsortium|impactIndicators(?:\.\d{1,2}(?:\.(name|unit|baseline|target))?)?)$/.test(entry.key)) {
          setError(entry.key as FieldPath<ProjectWriteInput>, { type: 'server', message: entry.message })
        }
      }
    },
  })
  const countries = watch('countryIds') ?? []
  const regions = watch('regionIds') ?? []
  const categories = watch('categoryIds') ?? []
  const beneficiaries = watch('beneficiaryTypeIds') ?? []
  const projectTypes = watch('projectTypeIds') ?? []
  const sustainableDevelopmentGoals = watch('sustainableDevelopmentGoalIds') ?? []
  const budgetTotal = watch('budgetTotal')
  const confirmedFunding = watch('confirmedFunding')
  const currency = watch('currency')
  const budgetRequired = (typeof confirmedFunding === 'number' && Number.isFinite(confirmedFunding)) || Boolean(currency)
  const currencyRequired = typeof budgetTotal === 'number' && Number.isFinite(budgetTotal)
  const visibleRegions = catalogs.regions.filter(region => countries.includes(region.countryId))
  const optionalNumber = { setValueAs: (value: string | null | undefined) => value == null || value === '' ? null : Number(value) }
  const contentLocked = Boolean(project && [1, 2, 4].includes(project.publicationStatus))

  return <form className="space-y-5" noValidate onSubmit={handleSubmit(input => {
    clearErrors('endDate')
    if (input.startDate && input.endDate && input.endDate < input.startDate) {
      setError('endDate', { type: 'validate', message: 'projects.endBeforeStart' }, { shouldFocus: true })
      return
    }
    save.mutate(input)
  })}>
    <Card><CardHeader><CardTitle>{project ? t('projects.editProject') : t('projects.newProject')}</CardTitle><p className="text-sm text-muted-foreground"><span aria-hidden="true" className="font-semibold text-destructive">*</span> {t('projects.requiredGuide')}</p></CardHeader>
      <CardContent><fieldset className="grid gap-5 disabled:opacity-70" disabled={contentLocked}>
        <Field error={formState.errors.title?.message} label={t('projects.title')} required><Input aria-invalid={Boolean(formState.errors.title)} aria-required="true" required {...register('title', { required: 'projects.titleRequired', minLength: { value: 3, message: 'projects.titleMin' }, maxLength: { value: 250, message: 'projects.titleMax' } })} placeholder={t('projects.titlePlaceholder')} /></Field>
        <Field error={formState.errors.summary?.message} label={t('projects.summary')}><textarea aria-invalid={Boolean(formState.errors.summary)} className={textareaClass} {...register('summary', { maxLength: { value: 1000, message: 'projects.summaryMax' } })} placeholder={t('projects.summaryPlaceholder')} /></Field>
        <Field error={formState.errors.description?.message} label={t('projects.description')}><textarea aria-invalid={Boolean(formState.errors.description)} className={textareaClass} {...register('description', { maxLength: { value: 5000, message: 'projects.descriptionMax' } })} placeholder={t('projects.descriptionPlaceholder')} /></Field>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {project
            ? <Field label={t('projects.status')} required><select aria-required="true" className={selectClass} required {...register('status', { valueAsNumber: true })}>{editableStatusOptions(project.status).map(option => <option key={option.value} value={option.value}>{option.name}</option>)}</select></Field>
            : <input type="hidden" {...register('status', { valueAsNumber: true })} />}
          <Field error={formState.errors.projectStage?.message} label={t('projects.stage')}><select aria-invalid={Boolean(formState.errors.projectStage)} className={selectClass} {...register('projectStage', { setValueAs: value => value === '' ? null : Number(value) })}><option value="">{t('projects.unspecified')}</option>{stageNames.map((name, value) => <option key={name} value={value}>{t(name)}</option>)}</select></Field>
          <Field label={t('projects.start')}><Input type="date" {...register('startDate', { setValueAs: value => value || null })} /></Field>
          <Field error={formState.errors.endDate?.message} label={t('projects.end')}><Input aria-invalid={Boolean(formState.errors.endDate)} type="date" {...register('endDate', { setValueAs: value => value || null })} /></Field>
        </div>
        <div className="grid gap-4 sm:grid-cols-3">
          <Field error={formState.errors.budgetTotal?.message} hint={t('projects.budgetHelp')} label={t('projects.budgetTotal')} required={budgetRequired}><Input aria-invalid={Boolean(formState.errors.budgetTotal)} aria-required={budgetRequired} min="0" required={budgetRequired} step="0.01" type="number" {...register('budgetTotal', { ...optionalNumber, validate: value => !budgetRequired || value !== null || 'projects.budgetRequired' })} /></Field>
          <Field error={formState.errors.confirmedFunding?.message} label={t('projects.confirmedFunding')}><Input aria-invalid={Boolean(formState.errors.confirmedFunding)} min="0" step="0.01" type="number" {...register('confirmedFunding', optionalNumber)} /></Field>
          <Field error={formState.errors.currency?.message} hint={t('projects.currencyHelp')} label={t('projects.currency')} required={currencyRequired}><select aria-invalid={Boolean(formState.errors.currency)} aria-required={currencyRequired} className={selectClass} required={currencyRequired} {...register('currency', { setValueAs: value => value || null, validate: value => !currencyRequired || Boolean(value) || 'projects.currencyRequired' })}><option value="">{t('projects.unspecified')}</option>{catalogs.currencies.map(item => <option lang={catalogLanguage('currencies', item)} key={item.code} value={item.code}>{item.code} · {catalogName('currencies', item)}</option>)}</select></Field>
        </div>
        <MultiChoice label={t('projects.countries')} catalog="countries" items={catalogs.countries} selected={countries} onChange={value => {
          setValue('countryIds', value, { shouldDirty: true })
          const allowed = catalogs.regions.filter(region => value.includes(region.countryId)).map(region => region.id)
          setValue('regionIds', regions.filter(id => allowed.includes(id)), { shouldDirty: true })
        }} />
        {visibleRegions.length > 0 && <MultiChoice label={t('projects.regions')} catalog="regions" items={visibleRegions} selected={regions} onChange={value => setValue('regionIds', value, { shouldDirty: true })} />}
        <MultiChoice label={t('projects.impactAreas')} catalog="fundingCategories" items={catalogs.fundingCategories} selected={categories} onChange={value => setValue('categoryIds', value, { shouldDirty: true })} />
        <MultiChoice label={t('projects.beneficiaries')} catalog="beneficiaryTypes" items={catalogs.beneficiaryTypes} selected={beneficiaries} onChange={value => setValue('beneficiaryTypeIds', value, { shouldDirty: true })} />
        <MultiChoice label={t('projects.projectType')} catalog="projectTypes" items={catalogs.projectTypes} selected={projectTypes} onChange={value => setValue('projectTypeIds', value, { shouldDirty: true })} />
        <MultiChoice label={t('projects.sdgs')} catalog="sustainableDevelopmentGoals" items={catalogs.sustainableDevelopmentGoals ?? []} selected={sustainableDevelopmentGoals} onChange={value => setValue('sustainableDevelopmentGoalIds', value, { shouldDirty: true, shouldValidate: true })} />
        {formState.errors.sustainableDevelopmentGoalIds?.message && <p className="text-xs text-destructive" role="alert">{workspaceMessage(formState.errors.sustainableDevelopmentGoalIds.message)}</p>}
        <ProjectEnrichmentFields form={form} />
        {contentLocked && <p className="rounded-lg bg-muted p-3 text-sm">{t('projects.contentLocked', { status: t(publicationNames[project!.publicationStatus]).toLocaleLowerCase() })}</p>}
        {save.isError && <p className="rounded-lg border border-destructive/50 bg-destructive/10 p-3 text-sm text-foreground">{errorMessage(save.error)}</p>}
        {save.isSuccess && project && <p className="rounded-lg bg-accent p-3 text-sm font-medium text-accent-foreground">{t('projects.saved')}</p>}
      </fieldset></CardContent>
    </Card>
    {!contentLocked && <div className="flex justify-end"><Button disabled={save.isPending || (Boolean(project) && !formState.isDirty)} type="submit">{save.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Save className="size-4" />}{project ? t('projects.saveChanges') : t('projects.create')}</Button></div>}
  </form>
}

function ProjectPublicationPanel({
  organizationId,
  organizationReady,
  project,
  hasUnsavedChanges,
  onChanged,
}: {
  organizationId: string
  organizationReady: boolean
  project: ProjectDetails
  hasUnsavedChanges: boolean
  onChanged: () => Promise<unknown>
}) {
  const { t } = useTranslation()
  const [confirmArchive, setConfirmArchive] = useState(false)
  const submit = useMutation({
    mutationFn: (idempotencyKey: string) => projectApi.requestPublication(
      organizationId,
      project.publicId,
      project.eTag,
      idempotencyKey,
    ),
    onSuccess: onChanged,
    retry: 1,
  })
  const archive = useMutation({
    mutationFn: (idempotencyKey: string) => projectApi.archive(
      organizationId,
      project.publicId,
      project.eTag,
      idempotencyKey,
    ),
    onSuccess: onChanged,
    retry: 1,
  })
  const checks = [
    { label: t('projects.checkOrganization'), ready: organizationReady },
    { label: t('projects.checkSummary'), ready: Boolean(project.summary?.trim()) },
    { label: t('projects.checkDescription'), ready: Boolean(project.description?.trim()) },
    { label: t('projects.checkBudget'), ready: Boolean(project.budgetTotal && project.budgetTotal > 0 && project.currency) },
    { label: t('projects.checkCountry'), ready: project.countryIds.length > 0 },
    { label: t('projects.checkImpact'), ready: project.categoryIds.length > 0 },
    { label: t('projects.beneficiaries'), ready: project.beneficiaryTypeIds.length > 0 },
    { label: t('projects.projectType'), ready: project.projectTypeIds.length > 0 },
  ]
  const canSubmit = project.publicationStatus === 0 || project.publicationStatus === 3
  const canArchive = project.publicationStatus !== 4
  const mutationError = submit.error ?? archive.error
  const serverIssues = validationMessages(mutationError)

  return <Card>
    <CardHeader className="sm:flex sm:flex-row sm:items-start sm:justify-between sm:space-y-0">
      <div><p className="text-xs font-bold uppercase tracking-[0.16em] text-primary">{t('projects.moderatedPublication')}</p><CardTitle className="mt-1">{t(publicationNames[project.publicationStatus])}</CardTitle></div>
      <span className="rounded-full bg-muted px-3 py-1 text-xs font-semibold">{t('projects.localCompleteness', { percent: Math.round(checks.filter(check => check.ready).length / checks.length * 100) })}</span>
    </CardHeader>
    <CardContent className="space-y-5">
      {project.publicationStatus === 1 && <p className="flex items-center gap-2 rounded-lg bg-accent p-3 text-sm"><Clock3 className="size-4" /> {t('projects.underReview', { date: formatDate(project.submittedAtUtc) ?? t('projects.today') })}</p>}
      {project.publicationStatus === 2 && <p className="flex items-center gap-2 rounded-lg bg-accent p-3 text-sm"><CheckCircle2 className="size-4" /> {t('projects.publishedOn', { date: formatDate(project.publishedAtUtc) ?? t('projects.approvalDay') })}</p>}
      {project.publicationStatus === 3 && <p className="rounded-lg border border-destructive/50 bg-destructive/10 p-3 text-sm text-foreground"><strong>{t('projects.reviewRejected')}</strong> {project.rejectionReason ?? t('projects.correctionHelp')}</p>}
      {project.publicationStatus === 4 && <p className="rounded-lg bg-muted p-3 text-sm">{t('projects.archivedHelp')}</p>}

      {canSubmit && <div><h2 className="text-sm font-bold">{t('projects.beforeSubmit')}</h2><ul className="mt-2 grid gap-2 sm:grid-cols-2">{checks.map(check => <li className="flex items-start gap-2 text-sm" key={check.label}>{check.ready ? <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-primary" /> : <CircleAlert className="mt-0.5 size-4 shrink-0 text-muted-foreground" />}<span>{check.label}</span></li>)}</ul></div>}
      {hasUnsavedChanges && <p className="rounded-lg bg-muted p-3 text-sm">{t('projects.unsavedHelp')}</p>}
      {mutationError && <div className="rounded-lg border border-destructive/50 bg-destructive/10 p-3 text-sm text-foreground"><p>{errorMessage(mutationError)}</p>{serverIssues.length > 0 && <ul className="mt-2 list-disc pl-5">{serverIssues.map(message => <li key={message}>{workspaceMessage(message)}</li>)}</ul>}</div>}

      <div className="flex flex-wrap gap-3">
        {canSubmit && <Button disabled={submit.isPending || archive.isPending || hasUnsavedChanges} onClick={() => submit.mutate(createProjectCommandId())} type="button">{submit.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Send className="size-4" />}{t('projects.submitReview')}</Button>}
        {project.publicationStatus === 2 && <Button asChild variant="outline"><Link to={`/marketplace/projects/${project.slug}`}><Globe2 className="size-4" />{t('projects.publicProfile')}</Link></Button>}
        {canArchive && !confirmArchive && <Button disabled={submit.isPending || archive.isPending} onClick={() => setConfirmArchive(true)} type="button" variant="ghost"><Archive className="size-4" />{t('projects.archive')}</Button>}
        {canArchive && confirmArchive && <><Button disabled={archive.isPending} onClick={() => archive.mutate(createProjectCommandId())} type="button" variant="outline">{archive.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Archive className="size-4" />}{t('projects.confirmArchive')}</Button><Button onClick={() => setConfirmArchive(false)} type="button" variant="ghost">{t('projects.cancel')}</Button></>}
      </div>
    </CardContent>
  </Card>
}

function useWorkspace() {
  const organizations = useQuery({ queryKey: ['organizations'], queryFn: ({ signal }) => organizationApi.list(signal) })
  const catalogs = useQuery({ queryKey: ['organization-catalogs'], queryFn: ({ signal }) => organizationApi.catalogs(signal), staleTime: 60 * 60 * 1000 })
  return { organizations, catalogs, organization: organizations.data?.[0] }
}

export function ProjectsPage() {
  const { t } = useTranslation()
  const [creating, setCreating] = useState(false)
  const { organizations, catalogs, organization } = useWorkspace()
  const projects = useQuery({
    queryKey: ['projects', organization?.publicId],
    queryFn: ({ signal }) => projectApi.list(organization!.publicId, signal),
    enabled: Boolean(organization),
  })
  if (organizations.isPending || catalogs.isPending || (organization && projects.isPending)) return <p className="flex items-center gap-2"><LoaderCircle className="size-5 animate-spin" /> {t('projects.loadingList')}</p>
  if (organizations.isError || catalogs.isError || projects.isError) return <p>{t('projects.loadFailed')}</p>
  if (!organization) return <Card><CardContent className="p-8"><h1 className="text-xl font-bold">{t('projects.organizationFirst')}</h1><Button asChild className="mt-4"><Link to="/onboarding">{t('projects.onboarding')}</Link></Button></CardContent></Card>

  return <div className="space-y-6">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{t('projects.phase')}</p><h1 className="mt-1 text-3xl font-bold">{t('projects.listTitle', { name: organization.name })}</h1><p className="mt-2 text-muted-foreground">{t('projects.listHelp')}</p></div><Button onClick={() => setCreating(value => !value)}><Plus className="size-4" />{creating ? t('projects.closeForm') : t('projects.newProject')}</Button></div>
    {creating && catalogs.data && <ProjectForm catalogs={catalogs.data} organizationId={organization.publicId} />}
    {!projects.data?.length && !creating && <Card><CardContent className="p-8 text-center"><Target className="mx-auto size-10 text-primary" /><h2 className="mt-3 text-xl font-bold">{t('projects.emptyTitle')}</h2><p className="mt-2 text-muted-foreground">{t('projects.emptyHelp')}</p></CardContent></Card>}
    <div className="grid gap-4 lg:grid-cols-2">{projects.data?.map(project => <Card key={project.publicId}><CardContent className="p-5"><div className="flex items-start justify-between gap-3"><div><p className="text-xs font-bold uppercase tracking-wide text-primary">{t(statusNames[project.status])}</p>{project.projectStage != null && <p className="mt-1 text-xs text-muted-foreground">{t('projects.stageLabel')} {t(stageNames[project.projectStage])}</p>}<h2 className="mt-1 text-xl font-bold">{project.title}</h2></div><div className="flex flex-col items-end gap-1"><span className="rounded-full bg-muted px-2.5 py-1 text-xs">{t(publicationNames[project.publicationStatus])}</span><span className="text-xs text-muted-foreground">v{project.projectVersion}</span></div></div><p className="mt-3 line-clamp-2 text-sm text-muted-foreground">{project.summary ?? t('projects.noSummary')}</p><div className="mt-4 flex items-center justify-between gap-3"><p className="text-sm">{t('projects.gapLabel')} <strong>{project.fundingGap === null ? t('projects.unspecified') : `${new Intl.NumberFormat(workspaceLocale()).format(project.fundingGap)} ${project.currency}`}</strong></p><Button asChild size="sm" variant="outline"><Link to={`/projects/${project.publicId}`}>{[1, 2, 4].includes(project.publicationStatus) ? t('projects.view') : t('projects.edit')}</Link></Button></div></CardContent></Card>)}</div>
  </div>
}

export function ProjectDetailPage() {
  const { t } = useTranslation()
  const { projectId } = useParams()
  const [hasUnsavedChanges, setHasUnsavedChanges] = useState(false)
  const { organizations, catalogs, organization } = useWorkspace()
  const project = useQuery({
    queryKey: ['project', organization?.publicId, projectId],
    queryFn: ({ signal }) => projectApi.get(organization!.publicId, projectId!, signal),
    enabled: Boolean(organization && projectId),
  })
  if (organizations.isPending || catalogs.isPending || project.isPending) return <p className="flex items-center gap-2"><LoaderCircle className="size-5 animate-spin" /> {t('projects.loading')}</p>
  if (!organization || !catalogs.data || project.isError || !project.data) return <p>{t('projects.notFound')}</p>
  return <div className="space-y-5">
    <Button asChild variant="ghost"><Link to="/projects"><ArrowLeft className="size-4" /> {t('projects.back')}</Link></Button>
    <div className="flex flex-wrap items-end justify-between gap-4">
      <div><p className="text-sm text-muted-foreground">{t('projects.version', { version: project.data.projectVersion })}</p><h1 className="text-3xl font-bold">{project.data.title}</h1>{project.data.fundingGap !== null && <p className="mt-2 text-muted-foreground">{t('projects.currentGap')} {new Intl.NumberFormat(workspaceLocale()).format(project.data.fundingGap)} {project.data.currency}</p>}</div>
      {project.data.publicationStatus !== 4 && <Button asChild variant="outline"><Link to={`/matching?projectId=${encodeURIComponent(project.data.publicId)}`}><Gauge className="size-4" />{t('projects.matching')}</Link></Button>}
    </div>
    <ProjectPublicationPanel hasUnsavedChanges={hasUnsavedChanges} onChanged={async () => { await project.refetch(); await organizations.refetch() }} organizationId={organization.publicId} organizationReady={organization.profileStatus === 2 && organization.profileCompleteness >= 80} project={project.data} />
    {isProjectAssetsEnabled() && <ProjectAssetsPanel
      hasUnsavedChanges={hasUnsavedChanges}
      onProjectChanged={async () => { await project.refetch() }}
      organizationId={organization.publicId}
      projectETag={project.data.eTag}
      projectId={project.data.publicId}
      publicationStatus={project.data.publicationStatus}
    />}
    <ProjectForm catalogs={catalogs.data} onDirtyChange={setHasUnsavedChanges} organizationId={organization.publicId} project={project.data} />
  </div>
}
