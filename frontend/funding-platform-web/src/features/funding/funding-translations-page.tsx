import { useEffect, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Link, useBlocker, useParams } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { adminFundingOpportunitiesApi, type AdminFundingOpportunityDetail } from './admin-funding-api'
import { fundingTranslationsApi, fundingTranslationsEnabled, translationFields, type FundingLanguage, type FundingTranslation, type FundingTranslationText, type TranslationField } from './funding-translations-api'

const labels = {
  title: 'title', summary: 'summary', description: 'description', eligibilityDescription: 'eligibility',
  requirements: 'requirements', objectives: 'objectives', allowedActivities: 'allowed',
  excludedActivities: 'excluded', restrictions: 'restrictions', targetOrganizationsDescription: 'targetOrganizations',
  targetPopulationsDescription: 'targetPopulations',
} as const satisfies Record<TranslationField, string>
const initialText = (translation: FundingTranslation | null) => Object.fromEntries(
  translationFields.map(([key]) => [key, translation?.text[key] ?? null]),
) as FundingTranslationText

export function FundingTranslationEditor({ original, translation, language, onDirtyChange, onReload }: {
  original: AdminFundingOpportunityDetail
  translation: FundingTranslation | null
  language: FundingLanguage
  onDirtyChange: (dirty: boolean) => void
  onReload: () => void
}) {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  // Keep the source and translation versions that were loaded together. Refetches
  // must never silently replace text currently being edited.
  const [source] = useState(original)
  const [saved, setSaved] = useState(translation)
  const [text, setText] = useState(() => initialText(translation))
  const [reviewed, setReviewed] = useState(false)
  const [message, setMessage] = useState(false)
  const dirty = JSON.stringify(text) !== JSON.stringify(initialText(saved)) || reviewed
  const stale = saved != null && saved.sourceContentVersion !== source.contentVersion
  const complete = translationFields.every(([key]) => Boolean(source[key]?.trim()) === Boolean(text[key]?.trim()))
  useEffect(() => {
    if (!dirty) return
    const warn = (event: BeforeUnloadEvent) => { event.preventDefault(); event.returnValue = '' }
    window.addEventListener('beforeunload', warn)
    return () => window.removeEventListener('beforeunload', warn)
  }, [dirty])
  const save = useMutation({
    mutationFn: (approve: boolean) => fundingTranslationsApi.save(source.opportunityId, language, source.eTag, {
      sourceContentVersion: source.contentVersion, expectedRevision: saved?.revision ?? 0,
      reviewed: approve, text: Object.fromEntries(translationFields.map(([key]) => [key, text[key]?.trim() || null])) as FundingTranslationText,
    }),
    onSuccess: (value) => {
      setSaved(value); setText(initialText(value)); setReviewed(false); setMessage(true)
      void queryClient.invalidateQueries({ queryKey: ['funding-opportunity'] })
      void queryClient.invalidateQueries({ queryKey: ['organization-funding'] })
    },
  })
  const conflict = save.error instanceof ApiError && save.error.response.status === 412
  useEffect(() => onDirtyChange(dirty || save.isPending), [dirty, save.isPending, onDirtyChange])
  return <section className="space-y-5">
    <p className="text-sm text-muted-foreground">{t('adminFunding.translationVersion', { version: source.contentVersion, revision: saved?.revision ?? 0 })}</p>
    {stale && <p role="status" className="rounded-xl border p-4">{t('adminFunding.translationStale')}</p>}
    <p role="status">{t(saved?.reviewed && !stale ? 'adminFunding.translationReviewed' : 'adminFunding.translationDraft')}</p>
    {translationFields.map(([key, max]) => <div className="grid gap-3 rounded-xl border bg-card p-4 md:grid-cols-2" key={key}>
      <div><h2 className="mb-2 font-semibold">{t(`adminFunding.${labels[key]}`)} · {t('adminFunding.translationOriginal')}</h2>
        <p className="max-h-72 overflow-auto whitespace-pre-wrap break-words text-sm text-muted-foreground">{source[key] || t('adminFunding.translationEmpty')}</p></div>
      <div><label className="mb-2 block font-semibold" htmlFor={`translation-${key}`}>{t(`adminFunding.${labels[key]}`)} · {language.toUpperCase()}</label>
        <textarea id={`translation-${key}`} className="min-h-28 w-full rounded-lg border bg-background p-3" maxLength={max} value={text[key] ?? ''} disabled={save.isPending}
          onChange={event => { setText({ ...text, [key]: event.target.value }); setReviewed(false); setMessage(false); save.reset() }} />
      </div>
    </div>)}
    <label className="flex items-start gap-3"><input type="checkbox" checked={reviewed} disabled={!complete || save.isPending} onChange={event => setReviewed(event.target.checked)} />
      <span>{t('adminFunding.translationConfirm')}</span></label>
    {!complete && <p className="text-sm">{t('adminFunding.translationCoverage')}</p>}
    {save.isError && <p role="alert">{t(conflict ? 'adminFunding.translationConflict' : 'adminFunding.translationFailed')}</p>}
    {message && <p role="status">{t('adminFunding.translationSaved')}</p>}
    <div className="flex flex-wrap gap-3">
      <Button variant="outline" disabled={save.isPending} onClick={() => save.mutate(false)}>{t('adminFunding.translationSaveDraft')}</Button>
      <Button disabled={!reviewed || !complete || save.isPending} onClick={() => save.mutate(true)}>{t('adminFunding.translationApprove')}</Button>
      <Button variant="ghost" disabled={save.isPending} onClick={() => {
        if (!dirty || window.confirm(t('adminFunding.translationDiscardConfirm'))) onReload()
      }}>{t('adminFunding.translationReload')}</Button>
    </div>
    <p className="text-sm text-muted-foreground">{t('adminFunding.translationDraftWarning')}</p>
  </section>
}

function TranslationWorkspace({ id }: { id: string }) {
  const { t } = useTranslation()
  const [language, setLanguage] = useState<FundingLanguage>('es')
  const [dirty, setDirty] = useState(false)
  const [load, setLoad] = useState(0)
  const blocker = useBlocker(dirty)
  useEffect(() => {
    if (blocker.state !== 'blocked') return
    if (window.confirm(t('adminFunding.translationDiscardConfirm'))) blocker.proceed()
    else blocker.reset()
  }, [blocker, t])
  const query = useQuery({
    queryKey: ['admin-funding-translation', id, language, load],
    queryFn: async ({ signal }) => {
      const [original, result] = await Promise.all([
        adminFundingOpportunitiesApi.get(id, signal), fundingTranslationsApi.get(id, language, signal),
      ])
      return { original, translation: result.translation }
    },
    retry: false, refetchOnWindowFocus: false, refetchOnReconnect: false, staleTime: Infinity,
  })
  return <div className="space-y-6">
    <Button variant="ghost" asChild><Link to={`/admin/funding/${id}`}>{t('adminFunding.back')}</Link></Button>
    <h1 className="text-3xl font-bold">{t('adminFunding.translations')}</h1>
    <p>{t('adminFunding.translationHelp')}</p>
    <label className="flex items-center gap-3">{t('adminFunding.translationLanguage')}
      <select disabled={dirty} value={language} className="rounded-lg border bg-background p-2" onChange={event => setLanguage(event.target.value as FundingLanguage)}>
        <option value="es">Español</option><option value="en">English</option>
      </select>
    </label>
    {dirty && <p role="status">{t('adminFunding.translationUnsaved')}</p>}
    {query.isPending ? <p role="status">{t('adminFunding.loadingDetail')}</p> : query.isError || !query.data ? <div role="alert">
      <p>{t('adminFunding.translationFailed')}</p><Button onClick={() => void query.refetch()}>{t('adminFunding.translationReload')}</Button>
    </div> : <FundingTranslationEditor key={`${id}:${language}:${load}`} {...query.data} language={language} onDirtyChange={setDirty} onReload={() => { setDirty(false); setLoad(value => value + 1) }} />}
  </div>
}

export function FundingTranslationsPage() {
  const { id = '' } = useParams()
  const { t } = useTranslation()
  if (!fundingTranslationsEnabled()) return <p role="status">{t('adminFunding.translationDisabled')}</p>
  return <TranslationWorkspace id={id} />
}
