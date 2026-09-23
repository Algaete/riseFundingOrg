import { useEffect, useState, type FormEvent } from 'react'
import { Link, useBlocker, useParams, useSearchParams } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { Button } from '@/components/ui/button'
import { SearchableCatalogChoices } from '@/components/searchable-catalog-choices'
import { organizationApi } from '@/features/organizations/organization-api'
import { projectApi } from '@/features/projects/project-api'
import { marketplaceApi } from '@/features/marketplace/marketplace-api'
import { useAuth } from '@/features/auth/use-auth'
import { catalogName } from '@/i18n/catalog-labels'
import { engagementApi, storyKinds, type Story, type StoryContent } from './engagement-api'
import { container, control, panel, Failure, Field, Paging } from './engagement-ui'

import { StoryFeed } from './story-feed'
export function StoriesPage() {
  const { t } = useTranslation(); const [params] = useSearchParams()
  return <div className={container}><h1 className="text-3xl font-bold">{t('engagement.storiesTitle')}</h1><p>{t('engagement.storiesHelp')}</p><Button asChild variant="outline"><Link to="/organization/stories">{t('engagement.manageStories')}</Link></Button><StoryFeed key={params.toString()} organizationId={params.get('organizationId') || undefined} projectId={params.get('projectId') || undefined} /></div>
}
export function StoryDetailPage() {
  const { id = '' } = useParams(); const { t } = useTranslation()
  const story = useQuery({ queryKey: ['story', id], queryFn: ({ signal }) => engagementApi.story(id, signal), retry: false })
  const catalogs = useQuery({ queryKey: ['marketplace', 'catalogs'], queryFn: ({ signal }) => marketplaceApi.catalogs(signal) })
  if (story.isPending) return <p className={container} role="status">{t('engagement.loading')}</p>
  if (story.isError || !story.data?.content) return <p className={container} role="alert">{t('engagement.storyUnavailable')}</p>
  const s = story.data; const c = s.content
  return <article className={`${container} max-w-3xl`}><Link className="text-primary underline" to="/stories">{t('engagement.stories')}</Link><p>{t(`engagement.kinds.${c.kind}`, { defaultValue: c.kind })}</p><h1 className="text-4xl font-bold">{c.title}</h1>
    <Link className="text-primary underline" to={`/marketplace/organizations/${s.organizationId}`}>{s.organizationName}</Link>
    {s.projectSlug && <p><Link className="text-primary underline" to={`/marketplace/projects/${s.projectSlug}`}>{s.projectTitle}</Link></p>}
    {c.summary && <p className="text-lg whitespace-pre-wrap">{c.summary}</p>}<p className="whitespace-pre-wrap leading-8 break-words">{c.body}</p>
    <div className="flex flex-wrap gap-2">{catalogs.data && ([['fundingCategories', c.categoryIds], ['sustainableDevelopmentGoals', c.goalIds], ['countries', c.countryIds]] as const).flatMap(([key, ids]) => (ids ?? []).map(id => {
      const item = catalogs.data[key]?.find(option => option.id === id)
      return item ? <span className="rounded-full border px-3 py-1 text-sm" key={`${key}-${id}`}>{catalogName(key, item)}</span> : null
    }))}</div>
  </article>
}
const empty: StoryContent = { title: '', summary: null, body: '', kind: 'organization', projectId: null, categoryIds: [], goalIds: [], countryIds: [], containsPersonalExperiences: false }
function StoryEditor({ organizationId, story, onSaved, onCancel, onDirty }: { organizationId: string; story: Story | null; onSaved: () => void; onCancel: () => void; onDirty: (value: boolean) => void }) {
  const { t } = useTranslation(); const auth = useAuth()
  const [id] = useState(() => story?.id ?? crypto.randomUUID()); const [data, setData] = useState<StoryContent>(story?.content ?? empty)
  const catalogs = useQuery({ queryKey: ['marketplace', 'catalogs'], queryFn: ({ signal }) => marketplaceApi.catalogs(signal) })
  const projects = useQuery({ queryKey: ['stories-projects', auth.session?.user.publicId, organizationId], queryFn: ({ signal }) => projectApi.list(organizationId, signal) })
  const mutation = useMutation({ mutationFn: () => engagementApi.saveStory(organizationId, id, story?.revision ?? 0, data), onSuccess: onSaved, retry: false })
  const dirty = JSON.stringify(data) !== JSON.stringify(story?.content ?? empty)
  useEffect(() => onDirty(dirty || mutation.isPending), [dirty, mutation.isPending, onDirty])
  useEffect(() => { if (!dirty) return; const warn = (e: BeforeUnloadEvent) => { e.preventDefault(); e.returnValue = '' }; window.addEventListener('beforeunload', warn); return () => window.removeEventListener('beforeunload', warn) }, [dirty])
  function submit(e: FormEvent) { e.preventDefault(); mutation.mutate() }
  return <form onSubmit={submit} className={panel}><h2 className="text-xl font-bold">{t('engagement.editStory')}</h2><p>{t('engagement.draftWarning')}</p><p>{t('engagement.required')}</p>
    <fieldset className="space-y-4" disabled={mutation.isPending}>
      <Field label={`${t('engagement.title')} *`}><input className={control} required minLength={3} maxLength={200} value={data.title} onChange={e => setData({ ...data, title: e.target.value })} /></Field>
      <Field label={`${t('engagement.kind')} *`}><select className={control} value={data.kind} onChange={e => setData({ ...data, kind: e.target.value })}>{storyKinds.map(kind => <option key={kind} value={kind}>{t(`engagement.kinds.${kind}`)}</option>)}</select></Field>
      <Field label={t('engagement.summary')}><textarea className={control} maxLength={600} value={data.summary ?? ''} onChange={e => setData({ ...data, summary: e.target.value || null })} /></Field>
      <Field label={`${t('engagement.body')} *`}><textarea className={`${control} min-h-64`} required minLength={20} maxLength={15000} value={data.body} onChange={e => setData({ ...data, body: e.target.value })} /></Field>
      <Field label={t('engagement.project')}><select className={control} disabled={projects.isPending || projects.isError} value={data.projectId ?? ''} onChange={e => setData({ ...data, projectId: e.target.value || null })}><option value="">{t('engagement.noProject')}</option>{(projects.data ?? []).map(p => <option key={p.publicId} value={p.publicId}>{p.title}</option>)}</select></Field>
      <Failure error={projects.error || catalogs.error} />
      {catalogs.data && <><SearchableCatalogChoices label={t('engagement.countries')} catalog="countries" items={catalogs.data.countries} selected={data.countryIds} onChange={countryIds => setData({ ...data, countryIds })} />
        {(['fundingCategories', 'sustainableDevelopmentGoals'] as const).map(key => <fieldset key={key} className="space-y-2"><legend className="font-semibold">{t(key === 'fundingCategories' ? 'engagement.categories' : 'engagement.goals')}</legend><div className="grid max-h-60 gap-2 overflow-auto sm:grid-cols-2">{catalogs.data[key].map(item => {
          const values = key === 'fundingCategories' ? data.categoryIds : data.goalIds
          return <label key={item.id} className="flex gap-2"><input type="checkbox" checked={values.includes(item.id)} onChange={() => {
            const selected = values.includes(item.id) ? values.filter(id => id !== item.id) : [...values, item.id]
            setData({ ...data, [key === 'fundingCategories' ? 'categoryIds' : 'goalIds']: selected })
          }} />{catalogName(key, item)}</label>
        })}</div></fieldset>)}</>}
      <label className="flex gap-2"><input type="checkbox" checked={data.containsPersonalExperiences} onChange={e => setData({ ...data, containsPersonalExperiences: e.target.checked })} />{t('engagement.personal')}</label>
      <Failure error={mutation.error} /><div className="flex gap-3"><Button type="submit">{t('engagement.saveDraft')}</Button><Button type="button" variant="outline" onClick={() => { if (!dirty || window.confirm(t('engagement.discard'))) onCancel() }}>{t('engagement.cancel')}</Button></div>
    </fieldset>
  </form>
}
function StoryActions({ organizationId, story, onChanged, edit }: { organizationId: string; story: Story; onChanged: () => void; edit: () => void }) {
  const { t } = useTranslation(); const [rights, setRights] = useState(false); const [consent, setConsent] = useState(false)
  const personal = story.content.containsPersonalExperiences || story.content.kind === 'beneficiaries'
  const mutation = useMutation({ mutationFn: (publish: boolean) => engagementApi.publishStory(organizationId, story, publish, rights, consent), onSuccess: onChanged })
  return <div className="space-y-3"><p>{t(`engagement.status${story.status}`, { defaultValue: '—' })}</p>
    {story.status !== 1 && <><label className="flex gap-2"><input type="checkbox" checked={rights} onChange={e => setRights(e.target.checked)} />{t('engagement.rights')}</label>{personal && <label className="flex gap-2"><input type="checkbox" checked={consent} onChange={e => setConsent(e.target.checked)} />{t('engagement.consent')}</label>}</>}
    <Failure error={mutation.error} /><div className="flex gap-2"><Button variant="outline" disabled={mutation.isPending} onClick={edit}>{t('engagement.edit')}</Button>
      {story.status === 1 ? <Button variant="outline" disabled={mutation.isPending} onClick={() => mutation.mutate(false)}>{t('engagement.withdraw')}</Button> : <Button disabled={mutation.isPending || !rights || personal && !consent} onClick={() => mutation.mutate(true)}>{t('engagement.publish')}</Button>}</div>
  </div>
}
export function StoriesWorkspacePage() {
  const { t } = useTranslation(); const auth = useAuth(); const client = useQueryClient()
  const [organizationId, setOrganizationId] = useState(''); const [page, setPage] = useState(1)
  const [editing, setEditing] = useState<Story | 'new' | null>(null); const [dirty, setDirty] = useState(false)
  const blocker = useBlocker(dirty)
  useEffect(() => { if (blocker.state === 'blocked') { if (window.confirm(t('engagement.discard'))) blocker.proceed(); else blocker.reset() } }, [blocker, t])
  const organizations = useQuery({ queryKey: ['story-organizations', auth.session?.user.publicId], queryFn: ({ signal }) => organizationApi.list(signal) })
  const stories = useQuery({ queryKey: ['own-stories', auth.session?.user.publicId, organizationId, page], queryFn: ({ signal }) => engagementApi.ownStories(organizationId, page, signal), enabled: !!organizationId, retry: false })
  const reload = () => { setEditing(null); setDirty(false); void stories.refetch(); void client.invalidateQueries({ queryKey: ['stories'] }); void client.invalidateQueries({ queryKey: ['story'] }) }
  return <div className="space-y-6"><h1 className="text-3xl font-bold">{t('engagement.manageStories')}</h1><p>{t('engagement.optionalStories')}</p><Failure error={organizations.error || stories.error} />
    <Field label={t('engagement.storyOrganization')}><select className={control} disabled={dirty || editing !== null} value={organizationId} onChange={e => { setOrganizationId(e.target.value); setPage(1) }}><option value="">{t('engagement.choose')}</option>{(organizations.data ?? []).filter(o => o.membershipRole === 'admin').map(o => <option key={o.publicId} value={o.publicId}>{o.name}</option>)}</select></Field>
    {organizationId && !editing && <Button onClick={() => setEditing('new')}>{t('engagement.newStory')}</Button>}
    {editing ? <StoryEditor key={editing === 'new' ? 'new' : editing.id} organizationId={organizationId} story={editing === 'new' ? null : editing} onDirty={setDirty} onSaved={reload} onCancel={() => { setEditing(null); setDirty(false) }} /> : <>
      {organizationId && stories.isPending && <p role="status">{t('engagement.loading')}</p>}
      {stories.data?.items?.length === 0 && <p>{t('engagement.noStories')}</p>}
      {(stories.data?.items ?? []).map(s => <section key={`${s.id}:${s.revision}`} className={panel}><h2 className="text-xl font-bold">{s.content.title}</h2><StoryActions organizationId={organizationId} story={s} onChanged={reload} edit={() => setEditing(s)} /></section>)}
      {stories.data && <Paging page={page} total={stories.data.totalCount} onPage={setPage} disabled={stories.isFetching} />}
    </>}
  </div>
}
