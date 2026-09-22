import { useFieldArray, useWatch, type UseFormReturn } from 'react-hook-form'
import { useTranslation } from 'react-i18next'
import type { ReactNode } from 'react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { workspaceMessage } from '@/i18n/workspace-messages'
import type { ProjectWriteInput } from './project-api'
import { ProjectLocationPicker } from './project-location-picker'

const selectClass = 'h-10 w-full rounded-lg border bg-background px-3 text-sm'
const optionalNumber = { setValueAs: (value: string | number | null | undefined) => value == null || value === '' ? null : Number(value) }
const optionalText = { setValueAs: (value: string | null | undefined) => value?.trim() || null }

function Field({ label, required, hint, error, children }: {
  label: string; required?: boolean; hint?: string; error?: string; children: ReactNode
}) {
  const { t } = useTranslation()
  return <label className="grid gap-1.5 text-sm font-semibold"><span>{label}{required && <><span aria-hidden="true"> *</span><span className="sr-only">{t('projects.required')}</span></>}</span>{children}{hint && <span className="text-xs font-normal text-muted-foreground">{hint}</span>}{error && <span className="text-xs text-destructive" role="alert">{workspaceMessage(error)}</span>}</label>
}

export function ProjectEnrichmentFields({ form }: { form: UseFormReturn<ProjectWriteInput> }) {
  const { t } = useTranslation()
  const { register, control, formState: { errors } } = form
  const { fields, append, remove } = useFieldArray({ control, name: 'enrichment.impactIndicators' })
  const visibility = useWatch({ control, name: 'enrichment.locationVisibility' }) ?? 0
  const latitude = useWatch({ control, name: 'enrichment.latitude' })
  const longitude = useWatch({ control, name: 'enrichment.longitude' })
  const coordinateRequired = visibility === 2 || latitude != null || longitude != null
  const issue = errors.enrichment
  const numberRules = { ...optionalNumber, validate: (value: number | null | undefined) => value == null || Number.isFinite(value) || 'projects.enrichment.numberInvalid' }
  return <div className="space-y-6 border-t pt-5">
    <section className="grid gap-4" aria-labelledby="project-impact-heading">
      <h2 className="text-lg font-bold" id="project-impact-heading">{t('projects.enrichment.impactTitle')}</h2>
      <p className="text-sm text-muted-foreground">{t('projects.enrichment.optionalHelp')}</p>
      {(['problem', 'solution'] as const).map(key => <Field key={key} label={t(`projects.enrichment.${key}`)} error={issue?.[key]?.message}>
        <textarea className="min-h-28 rounded-lg border bg-background px-3 py-2 text-sm" aria-invalid={Boolean(issue?.[key])} maxLength={3000} {...register(`enrichment.${key}`, optionalText)} />
      </Field>)}
      <Field label={t('projects.enrichment.beneficiaryCount')} error={issue?.beneficiaryCount?.message}>
        <Input type="number" min={0} step={1} aria-invalid={Boolean(issue?.beneficiaryCount)} {...register('enrichment.beneficiaryCount', { ...numberRules, validate: value => value == null || (Number.isInteger(value) && value >= 0 && value <= 2147483647) || 'projects.enrichment.countInvalid' })} />
      </Field>
      <fieldset className="space-y-3">
        <legend className="mb-2 font-semibold">{t('projects.enrichment.indicators')}</legend>
        <p className="text-sm text-muted-foreground">{t('projects.enrichment.indicatorHelp')}</p>
        {fields.map((field, index) => <fieldset key={field.id} className="space-y-3 rounded-lg border p-4">
          <legend className="px-1 text-sm font-semibold">{t('projects.enrichment.indicatorNumber', { number: index + 1 })}</legend>
          <div className="grid gap-3 sm:grid-cols-2">
            {(['name', 'unit'] as const).map(key => <Field key={key} label={t(`projects.enrichment.${key}`)} hint={t(`projects.enrichment.${key}Help`)} required error={issue?.impactIndicators?.[index]?.[key]?.message}>
              <Input aria-label={t(`projects.enrichment.${key}`)} required aria-required="true" placeholder={t(`projects.enrichment.${key}Example`)} maxLength={key === 'name' ? 200 : 80} {...register(`enrichment.impactIndicators.${index}.${key}`, { ...optionalText, required: 'projects.enrichment.indicatorRequired' })} />
            </Field>)}
            {(['baseline', 'target'] as const).map(key => <Field key={key} label={t(`projects.enrichment.${key}`)} hint={t(`projects.enrichment.${key}Help`)} error={issue?.impactIndicators?.[index]?.[key]?.message}>
              <Input aria-label={t(`projects.enrichment.${key}`)} type="number" step="any" min={-1e12} max={1e12} {...register(`enrichment.impactIndicators.${index}.${key}`, { ...numberRules, validate: value => value == null || (Number.isFinite(value) && Math.abs(value) <= 1e12) || 'projects.enrichment.measurementInvalid' })} />
            </Field>)}
          </div>
          {issue?.impactIndicators?.[index]?.message && <p role="alert" className="text-sm text-destructive">{workspaceMessage(issue.impactIndicators[index].message)}</p>}
          <Button type="button" variant="outline" onClick={() => remove(index)} aria-label={t('projects.enrichment.removeIndicatorNumber', { number: index + 1 })}>{t('projects.enrichment.removeIndicator')}</Button>
        </fieldset>)}
        {issue?.impactIndicators?.message && <p role="alert" className="text-sm text-destructive">{workspaceMessage(issue.impactIndicators.message)}</p>}
        <Button type="button" variant="outline" disabled={fields.length >= 20} onClick={() => append({ name: '', unit: '', baseline: null, target: null })}>{t('projects.enrichment.addIndicator')}</Button>
      </fieldset>
    </section>
    <section className="grid gap-4" aria-labelledby="project-location-heading">
      <h2 className="text-lg font-bold" id="project-location-heading">{t('projects.enrichment.locationTitle')}</h2>
      <p className="text-sm text-muted-foreground">{t('projects.enrichment.locationHelp')}</p>
      <Field label={t('projects.enrichment.locality')} required={visibility === 1} error={issue?.locality?.message}>
        <Input maxLength={200} required={visibility === 1} aria-required={visibility === 1} {...register('enrichment.locality', { ...optionalText, validate: value => visibility !== 1 || Boolean(value?.trim()) || 'projects.enrichment.localityRequired' })} />
      </Field>
      {(['latitude', 'longitude'] as const).map(key => <input key={key} type="hidden" {...register(`enrichment.${key}`, { ...numberRules, validate: value => value == null ? !coordinateRequired || 'projects.enrichment.coordinatesRequired' : (Number.isFinite(value) && Math.abs(value) <= (key === 'latitude' ? 90 : 180)) || 'projects.enrichment.coordinatesInvalid' })} />)}
      <Field label={t('projects.enrichment.visibility')} hint={t('projects.enrichment.privacyHelp')} error={issue?.locationVisibility?.message}>
        <select className={selectClass} {...register('enrichment.locationVisibility', { valueAsNumber: true })}>
          <option value={0}>{t('projects.enrichment.regionOnly')}</option>
          <option value={1}>{t('projects.enrichment.localityOnly')}</option>
          <option value={2}>{t('projects.enrichment.approximatePoint')}</option>
        </select>
      </Field>
      {visibility === 2 && <ProjectLocationPicker value={latitude != null && longitude != null ? { latitude, longitude } : null} onChange={point => {
        form.setValue('enrichment.latitude', point.latitude, { shouldDirty: true, shouldValidate: true })
        form.setValue('enrichment.longitude', point.longitude, { shouldDirty: true, shouldValidate: true })
      }} />}
      {(issue?.latitude || issue?.longitude) && <p role="alert" className="text-sm text-destructive">{workspaceMessage(issue.latitude?.message || issue.longitude?.message || 'projects.enrichment.coordinatesRequired')}</p>}
      {(latitude != null || longitude != null) && <Button type="button" variant="outline" onClick={() => {
        form.setValue('enrichment.latitude', null, { shouldDirty: true })
        form.setValue('enrichment.longitude', null, { shouldDirty: true })
        form.setValue('enrichment.locationVisibility', 0, { shouldDirty: true })
        form.clearErrors(['enrichment.latitude', 'enrichment.longitude'])
      }}>{t('projects.enrichment.removePoint')}</Button>}
      <a className="text-sm text-primary underline" href="/marketplace/map" target="_blank" rel="noreferrer">{t('projects.enrichment.openMap')}</a>
    </section>
    <section className="grid gap-4" aria-labelledby="project-background-heading">
      <h2 className="text-lg font-bold" id="project-background-heading">{t('projects.enrichment.backgroundTitle')}</h2>
      <p className="text-sm text-muted-foreground">{t('projects.enrichment.backgroundHelp')}</p>
      {(['additionalInformation', 'technicalInformation', 'existingPartnerships', 'previousResults'] as const).map(key => <Field key={key} label={t(`projects.enrichment.${key}`)} hint={t(`projects.enrichment.${key}Help`)} error={issue?.background?.[key]?.message}>
        <textarea className="min-h-28 rounded-lg border bg-background px-3 py-2 text-sm" maxLength={3000} aria-invalid={Boolean(issue?.background?.[key])} {...register(`enrichment.background.${key}`, { ...optionalText, maxLength: { value: 3000, message: 'projects.enrichment.backgroundMax' } })} />
      </Field>)}
    </section>
    <section className="grid gap-4" aria-labelledby="project-collaboration-heading">
      <h2 className="text-lg font-bold" id="project-collaboration-heading">{t('projects.enrichment.collaborationTitle')}</h2>
      <p className="text-sm text-muted-foreground">{t('projects.enrichment.collaborationHelp')}</p>
      {(['soughtPartners', 'soughtProfessionals'] as const).map(key => <Field key={key} label={t(`projects.enrichment.${key}`)} error={issue?.[key]?.message}>
        <textarea maxLength={2000} className="min-h-24 rounded-lg border bg-background px-3 py-2 text-sm" {...register(`enrichment.${key}`, optionalText)} />
      </Field>)}
      <Field label={t('projects.enrichment.seekingConsortium')}>
        <select className={selectClass} {...register('enrichment.seekingConsortium', { setValueAs: value => value === '' || value == null ? null : value === 'true' || value === true })}>
          <option value="">{t('projects.unspecified')}</option><option value="true">{t('projects.enrichment.yes')}</option><option value="false">{t('projects.enrichment.no')}</option>
        </select>
      </Field>
    </section>
  </div>
}
