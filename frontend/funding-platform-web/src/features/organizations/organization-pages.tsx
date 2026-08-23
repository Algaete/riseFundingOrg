import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Building2, Check, ChevronLeft, ChevronRight, LoaderCircle, Save } from 'lucide-react'
import { useEffect, useState, type ReactNode } from 'react'
import { useForm } from 'react-hook-form'

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

function Field({ label, hint, error, children }: { label: string; hint?: string; error?: string; children: ReactNode }) {
  return (
    <label className="grid gap-1.5 text-sm font-semibold">
      <span>{label}</span>
      {children}
      {hint && <span className="text-xs font-normal text-muted-foreground">{hint}</span>}
      {error && <span className="text-xs font-normal text-destructive" role="alert">{error}</span>}
    </label>
  )
}

function errorMessage(error: unknown) {
  return error instanceof ApiError
    ? Object.values(error.problem.errors ?? {}).flat()[0] ?? error.problem.detail ?? error.problem.title
    : 'No fue posible guardar. Revisa la conexión e intenta nuevamente.'
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
  const { register, handleSubmit, formState } = useForm<{
    name: string
    homeCountryId: number
    organizationTypeId: number
  }>({ defaultValues: { name: '', homeCountryId: catalogs.countries[0]?.id, organizationTypeId: catalogs.organizationTypes[0]?.id } })
  const create = useMutation({
    mutationFn: organizationApi.create,
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['organizations'] })
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
          <form className="grid gap-5" onSubmit={handleSubmit((values) => create.mutate(values))}>
            <Field label="Nombre público">
              <Input {...register('name', { required: true, maxLength: 250 })} autoComplete="organization" placeholder="Ej. Fundación Impacto Local" />
            </Field>
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="País principal">
                <select className={selectClass} {...register('homeCountryId', { valueAsNumber: true })}>
                  {catalogs.countries.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}
                </select>
              </Field>
              <Field label="Tipo de organización">
                <select className={selectClass} {...register('organizationTypeId', { valueAsNumber: true })}>
                  {catalogs.organizationTypes.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}
                </select>
              </Field>
            </div>
            {create.isError && <p className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">{errorMessage(create.error)}</p>}
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
}: {
  label: string
  items: CatalogOption<number>[]
  selected: number[]
  onChange: (value: number[]) => void
}) {
  function toggle(id: number) {
    onChange(selected.includes(id) ? selected.filter(value => value !== id) : [...selected, id])
  }
  return (
    <fieldset className="space-y-2">
      <legend className="text-sm font-semibold">{label}</legend>
      <div className="grid gap-2 sm:grid-cols-2">
        {items.map(item => (
          <label className="flex cursor-pointer items-center gap-2 rounded-lg border bg-background px-3 py-2 text-sm" key={item.id}>
            <input checked={selected.includes(item.id)} onChange={() => toggle(item.id)} type="checkbox" />
            {item.name}
          </label>
        ))}
      </div>
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
  const { register, handleSubmit, reset, watch, setValue, setError, clearErrors, formState } = useForm<OrganizationProfileUpdate>({
    defaultValues: profile,
  })
  useEffect(() => reset(profile), [profile, reset])
  const update = useMutation({
    mutationFn: (input: OrganizationProfileUpdate) => organizationApi.update(profile.publicId, profile.eTag, input),
    onSuccess: async (updated) => {
      reset(updated)
      await queryClient.invalidateQueries({ queryKey: ['organization-profile', profile.publicId] })
      await queryClient.invalidateQueries({ queryKey: ['organizations'] })
    },
    onError: error => {
      if (!(error instanceof ApiError)) return
      const websiteError = error.problem.errors?.websiteUrl?.[0]
      if (websiteError) setError('websiteUrl', { type: 'server', message: websiteError })
    },
  })
  const countries = watch('countryIds') ?? []
  const categories = watch('categoryIds') ?? []
  const beneficiaries = watch('beneficiaryTypeIds') ?? []
  const projectTypes = watch('projectTypeIds') ?? []
  const regions = watch('regionIds') ?? []
  const visibleRegions = catalogs.regions.filter(region => countries.includes(region.countryId))
  const optionalNumber = { setValueAs: (value: string) => value === '' ? null : Number(value) }

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

      <form onSubmit={handleSubmit(values => {
        clearErrors('websiteUrl')
        update.mutate({ ...values, websiteUrl: normalizeWebsiteUrl(values.websiteUrl) })
      })}>
        <Card>
          <CardContent className="grid gap-5 p-6">
            {step === 0 && <>
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label="Nombre público"><Input {...register('name', { required: true, maxLength: 250 })} /></Field>
                <Field label="Razón social"><Input {...register('legalName')} /></Field>
                <Field label="Identificador tributario"><Input {...register('taxIdentifier')} /></Field>
                <Field label="Año de constitución"><Input max={new Date().getFullYear()} min="1800" type="number" {...register('establishedYear', optionalNumber)} /></Field>
                <Field label="País principal">
                  <select className={selectClass} {...register('homeCountryId', { valueAsNumber: true })}>{catalogs.countries.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select>
                </Field>
                <Field label="Tipo de organización">
                  <select className={selectClass} {...register('organizationTypeId', { valueAsNumber: true })}>{catalogs.organizationTypes.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select>
                </Field>
                <Field label="Personalidad jurídica">
                  <select className={selectClass} {...register('legalEntityTypeId', optionalNumber)}><option value="">Sin informar</option>{catalogs.legalEntityTypes.filter(item => item.countryId === null || item.countryId === watch('homeCountryId')).map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select>
                </Field>
                <Field label="Tamaño">
                  <select className={selectClass} {...register('organizationSizeId', optionalNumber)}><option value="">Sin informar</option>{catalogs.organizationSizes.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select>
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
                  inputMode="url"
                  placeholder="onara.org"
                  type="text"
                />
              </Field>
              <Field label="Descripción"><textarea className={textareaClass} {...register('description')} placeholder="Propósito, experiencia y territorio de trabajo" /></Field>
            </>}

            {step === 1 && <>
              <MultiChoice label="Países donde trabaja" items={catalogs.countries} selected={countries} onChange={value => {
                setValue('countryIds', value, { shouldDirty: true })
                const validRegionIds = catalogs.regions.filter(region => value.includes(region.countryId)).map(region => region.id)
                setValue('regionIds', regions.filter(regionId => validRegionIds.includes(regionId)), { shouldDirty: true })
              }} />
              {visibleRegions.length > 0 && <MultiChoice label="Regiones" items={visibleRegions} selected={regions} onChange={value => setValue('regionIds', value, { shouldDirty: true })} />}
              <MultiChoice label="Áreas de impacto" items={catalogs.fundingCategories} selected={categories} onChange={value => setValue('categoryIds', value, { shouldDirty: true })} />
              <MultiChoice label="Poblaciones beneficiarias" items={catalogs.beneficiaryTypes} selected={beneficiaries} onChange={value => setValue('beneficiaryTypeIds', value, { shouldDirty: true })} />
              <MultiChoice label="Tipos de proyecto" items={catalogs.projectTypes} selected={projectTypes} onChange={value => setValue('projectTypeIds', value, { shouldDirty: true })} />
            </>}

            {step === 2 && <>
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label="Experiencia postulando a fondos">
                  <select className={selectClass} {...register('previousFundingExperience', { valueAsNumber: true })}>
                    <option value={0}>Sin informar</option><option value={1}>Aún no</option><option value={2}>Sí, tenemos experiencia</option>
                  </select>
                </Field>
                <Field label="Moneda objetivo"><select className={selectClass} {...register('desiredFundingCurrency')}><option value="">Sin informar</option>{catalogs.currencies.map(item => <option key={item.code} value={item.code}>{item.code} · {item.name}</option>)}</select></Field>
                <Field label="Financiamiento mínimo"><Input min="0" step="1" type="number" {...register('desiredFundingMin', optionalNumber)} /></Field>
                <Field label="Financiamiento máximo"><Input min="0" step="1" type="number" {...register('desiredFundingMax', optionalNumber)} /></Field>
                <Field label="Moneda presupuesto anual"><select className={selectClass} {...register('annualBudgetCurrency')}><option value="">Sin informar</option>{catalogs.currencies.map(item => <option key={item.code} value={item.code}>{item.code} · {item.name}</option>)}</select></Field>
                <Field label="Presupuesto anual mínimo"><Input min="0" step="1" type="number" {...register('annualBudgetMin', optionalNumber)} /></Field>
                <Field label="Presupuesto anual máximo"><Input min="0" step="1" type="number" {...register('annualBudgetMax', optionalNumber)} /></Field>
              </div>
              <Field label="Resumen de experiencia"><textarea className={textareaClass} {...register('experienceSummary')} /></Field>
              <MultiChoice label="Idiomas de trabajo" items={catalogs.languages} selected={(watch('languages') ?? []).map(item => item.languageId)} onChange={value => setValue('languages', value.map(languageId => ({ languageId, proficiency: null })), { shouldDirty: true })} />
            </>}

            {update.isError && <p className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">{errorMessage(update.error)}</p>}
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
