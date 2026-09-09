import { useState, type FormEvent } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { useMutation, useQuery } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { organizationApi, type OrganizationSummary } from '@/features/organizations/organization-api'
import { projectApi } from '@/features/projects/project-api'
import { executeEditorialCommand } from '@/features/funding/editorial-command-cache'
import { collaborationApi } from './collaboration-api'
import { consortiumIssue } from './collaboration-validation'
import { button, control, panel, CollaborationHeader, consortiumStatuses, Feedback, Field, LoadState, Paging, useCollaborationActor, type CopyKey } from './collaboration-ui'

function CreateConsortium({ organizations }: { organizations: OrganizationSummary[] }) {
  const { t } = useTranslation()
  const actor = useCollaborationActor()
  const navigate = useNavigate()
  const [organizationId, setOrganizationId] = useState('')
  const [projectId, setProjectId] = useState('')
  const [name, setName] = useState('')
  const [summary, setSummary] = useState('')
  const [issue, setIssue] = useState<CopyKey | null>(null)
  const projects = useQuery({ queryKey: ['collaboration', actor, 'projects', organizationId], queryFn: ({ signal }) => projectApi.list(organizationId, signal), enabled: Boolean(organizationId) })
  const mutation = useMutation({ mutationFn: () => {
    const data = { projectId, name: name.trim(), summary: summary.trim() || null }
    return executeEditorialCommand(`collaboration:${actor}:create`, data, key => collaborationApi.create(data, key))
  }, onSuccess: result => navigate(`/collaboration/consortia/${result.entityId}`) })
  function create(event: FormEvent) {
    event.preventDefault()
    const found = consortiumIssue(name, summary) ?? (!projectId ? 'invalidData' : null)
    setIssue(found); if (!found) mutation.mutate()
  }
  if (organizations.length === 0) return <p className={panel}>{t('collaboration.noOrganization')}</p>
  return <form className={panel} onSubmit={create} noValidate><h2 className="text-xl font-semibold">{t('collaboration.create')}</h2>
    <p>{t('collaboration.createHelp')}</p><p className="text-sm">{t('collaboration.required')}</p>
    <fieldset disabled={mutation.isPending} className="space-y-4">
      <Field label={t('collaboration.organization')} required><select className={control} aria-required value={organizationId} onChange={e => { setOrganizationId(e.target.value); setProjectId('') }}><option value="">{t('collaboration.choose')}</option>{organizations.map(org => <option key={org.publicId} value={org.publicId}>{org.name}</option>)}</select></Field>
      {organizationId && <LoadState pending={projects.isPending} error={projects.error} retry={() => projects.refetch()} />}
      <Field label={t('collaboration.project')} required><select className={control} aria-required disabled={!organizationId || projects.isPending} value={projectId} onChange={e => setProjectId(e.target.value)}><option value="">{t('collaboration.choose')}</option>{projects.data?.filter(project => project.publicationStatus !== 4).map(project => <option key={project.publicId} value={project.publicId}>{project.title}</option>)}</select></Field>
      <Field label={t('collaboration.name')} required><input className={control} aria-required maxLength={160} value={name} onChange={e => setName(e.target.value)} /></Field>
      <Field label={t('collaboration.summary')}><textarea className={control} maxLength={1000} value={summary} onChange={e => setSummary(e.target.value)} /></Field>
      <Feedback issue={issue} error={mutation.error} /><button className={button} type="submit">{t('collaboration.create')}</button>
    </fieldset></form>
}
export function ConsortiumListPage() {
  const { t } = useTranslation()
  const actor = useCollaborationActor()
  const [parameters] = useSearchParams()
  const professionalId = parameters.get('professionalId')
  const [page, setPage] = useState(1)
  const query = useQuery({ queryKey: ['collaboration', actor, 'consortia', page], queryFn: ({ signal }) => collaborationApi.consortia(page, signal) })
  const organizations = useQuery({ queryKey: ['collaboration', actor, 'organizations'], queryFn: ({ signal }) => organizationApi.list(signal) })
  return <div className="space-y-6"><CollaborationHeader title="consortia" />
    {professionalId && <p role="status" className={panel}>{t('collaboration.selectedProfessional')}</p>}
    <LoadState pending={query.isPending} error={query.error} retry={() => query.refetch()} />
    {query.data && <><div className="grid gap-4 lg:grid-cols-2">{query.data.items.map(consortium => <article className={panel} key={consortium.consortiumId}>
      <h2 className="text-xl font-semibold">{consortium.name}</h2><p>{t('collaboration.lead', { name: consortium.leadOrganizationName })}</p>
      <p>{consortium.projectTitle ?? t('collaboration.privateProject')}</p><p>{t(`collaboration.${consortiumStatuses[consortium.status]}`)}</p>
      {consortium.hasPendingInvitation && <p className="font-semibold">{t('collaboration.pendingInvitation')}</p>}
      <Link className={button} to={`/collaboration/consortia/${consortium.consortiumId}${professionalId && consortium.canManage && consortium.status !== 2 && consortium.projectIsPublic ? `?professionalId=${encodeURIComponent(professionalId)}` : ''}`}>{t('collaboration.open')}</Link>
    </article>)}</div>{query.data.items.length === 0 && <p>{t('collaboration.empty')}</p>}
      <Paging page={page} total={query.data.totalCount} setPage={setPage} disabled={query.isFetching} /></>}
    <LoadState pending={organizations.isPending} error={organizations.error} retry={() => organizations.refetch()} />
    {organizations.data && <CreateConsortium organizations={organizations.data.filter(org => org.membershipRole === 'admin')} />}
  </div>
}

