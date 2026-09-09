import { useState, type FormEvent } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { organizationApi, type OrganizationCatalogs } from '@/features/organizations/organization-api'
import { catalogName } from '@/i18n/catalog-labels'
import { executeEditorialCommand } from '@/features/funding/editorial-command-cache'
import { collaborationApi, type OwnProfessional, type ProfessionalData } from './collaboration-api'
import { blankProfessional, profileIssue, splitSkills } from './collaboration-validation'
import { button, control, panel, CollaborationHeader, Feedback, Field, LoadState, useCollaborationActor, type CopyKey } from './collaboration-ui'

function ProfileForm({ profile, catalogs, onSaved }: { profile: OwnProfessional | null; catalogs: OrganizationCatalogs; onSaved: () => Promise<unknown> }) {
  const { t } = useTranslation()
  const actor = useCollaborationActor()
  const [data, setData] = useState<ProfessionalData>(profile?.data ?? blankProfessional)
  const [skills, setSkills] = useState(data.skills.join(', '))
  const [issue, setIssue] = useState<CopyKey | null>(null)
  const mutation = useMutation({ mutationFn: (input: ProfessionalData) => executeEditorialCommand(
    `collaboration:${actor}:profile`, { input, eTag: profile?.eTag },
    key => collaborationApi.saveProfile(input, key, profile?.eTag)), onSuccess: onSaved })
  const update = <K extends keyof ProfessionalData>(key: K, value: ProfessionalData[K]) => setData(current => ({ ...current, [key]: value }))
  const toggle = (key: 'languageIds' | 'categoryIds', id: number, checked: boolean) => update(key, checked ? [...data[key], id] : data[key].filter(value => value !== id))
  function save(event: FormEvent) {
    event.preventDefault()
    const input = { ...data, displayName: data.displayName.trim(), headline: data.headline.trim(), biography: data.biography?.trim() || null, skills: splitSkills(skills) }
    const found = profileIssue(input); setIssue(found)
    if (!found) mutation.mutate(input)
  }
  return <form className={panel} onSubmit={save} noValidate>
    <p>{t('collaboration.privacy')}</p><p className="text-sm">{t('collaboration.required')}</p>
    <fieldset disabled={mutation.isPending} className="space-y-4">
      <Field label={t('collaboration.displayName')} required><input className={control} aria-required maxLength={120} value={data.displayName} onChange={e => update('displayName', e.target.value)} /></Field>
      <Field label={t('collaboration.headline')} required><input className={control} aria-required maxLength={160} value={data.headline} onChange={e => update('headline', e.target.value)} /></Field>
      <Field label={t('collaboration.biography')}><textarea className={control} rows={4} maxLength={2000} value={data.biography ?? ''} onChange={e => update('biography', e.target.value)} /></Field>
      <Field label={t('collaboration.country')}><select className={control} value={data.countryId ?? ''} onChange={e => update('countryId', e.target.value ? Number(e.target.value) : null)}><option value="">{t('collaboration.choose')}</option>{catalogs.countries.map(item => <option key={item.id} value={item.id}>{catalogName('countries', item)}</option>)}</select></Field>
      <Field label={t('collaboration.skills')}><textarea className={control} maxLength={1700} value={skills} onChange={e => setSkills(e.target.value)} /></Field>
      {(['languageIds', 'categoryIds'] as const).map(key => <fieldset key={key} className="space-y-2"><legend className="mb-2 font-medium">{t(key === 'languageIds' ? 'collaboration.languages' : 'collaboration.categories')}</legend>
        <div className="grid gap-2 sm:grid-cols-2">{(key === 'languageIds' ? catalogs.languages : catalogs.fundingCategories).map(item =>
          <label key={item.id} className="flex items-start gap-2 text-sm"><input type="checkbox" checked={data[key].includes(item.id)} onChange={e => toggle(key, item.id, e.target.checked)} />{catalogName(key === 'languageIds' ? 'languages' : 'fundingCategories', item)}</label>)}</div></fieldset>)}
      <label className="flex gap-2"><input type="checkbox" checked={data.isDiscoverable} onChange={e => setData(current => ({ ...current, isDiscoverable: e.target.checked, allowsInvitations: e.target.checked && current.allowsInvitations }))} />{t('collaboration.discoverable')}</label>
      <label className="flex gap-2"><input type="checkbox" disabled={!data.isDiscoverable} checked={data.allowsInvitations} onChange={e => update('allowsInvitations', e.target.checked)} />{t('collaboration.allowsInvitations')}</label>
      <p className="text-sm text-muted-foreground">{t('collaboration.optOut')}</p>
      <Feedback issue={issue} error={mutation.error} />
      <button className={button} type="submit">{t('collaboration.save')}</button>
    </fieldset>
  </form>
}
export function ProfessionalProfilePage() {
  const { t } = useTranslation()
  const actor = useCollaborationActor()
  const client = useQueryClient()
  const [saved, setSaved] = useState(false)
  const query = useQuery({ queryKey: ['collaboration', actor, 'profile'], queryFn: ({ signal }) => collaborationApi.profile(signal), refetchOnWindowFocus: false })
  const catalogs = useQuery({ queryKey: ['organization-catalogs'], queryFn: ({ signal }) => organizationApi.catalogs(signal) })
  return <div className="space-y-6"><CollaborationHeader title="profile" />
    <LoadState pending={query.isPending || catalogs.isPending} error={query.error ?? catalogs.error} retry={() => Promise.all([query.refetch(), catalogs.refetch()])} />
    {saved && <Feedback success="saved" />}
    {query.isSuccess && catalogs.data && <ProfileForm key={query.data?.eTag ?? 'new'} profile={query.data} catalogs={catalogs.data} onSaved={async () => { await client.invalidateQueries({ queryKey: ['collaboration', actor] }); setSaved(true) }} />}
    <button className={button} onClick={() => { void query.refetch() }}>{t('collaboration.refresh')}</button>
  </div>
}
