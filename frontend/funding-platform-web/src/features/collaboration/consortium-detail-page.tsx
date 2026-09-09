import { useState, type FormEvent } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { executeEditorialCommand } from '@/features/funding/editorial-command-cache'
import { collaborationApi, type Consortium, type Participant } from './collaboration-api'
import { consortiumIssue } from './collaboration-validation'
import { ConsortiumInvitationForm } from './consortium-invitation-form'
import { button, control, panel, CollaborationHeader, consortiumStatuses, participantStatuses, Feedback, Field, LoadState, useCollaborationActor, type CopyKey } from './collaboration-ui'

function ConsortiumEditor({ consortium, onSaved }: { consortium: Consortium; onSaved: () => Promise<unknown> }) {
  const { t } = useTranslation()
  const actor = useCollaborationActor()
  const [name, setName] = useState(consortium.name)
  const [summary, setSummary] = useState(consortium.summary ?? '')
  const [status, setStatus] = useState<number>(consortium.status)
  const [confirm, setConfirm] = useState(false)
  const [issue, setIssue] = useState<CopyKey | null>(null)
  const mutation = useMutation({ mutationFn: () => {
    const data = { name: name.trim(), summary: summary.trim() || null, status }
    return executeEditorialCommand(`collaboration:${actor}:${consortium.consortiumId}:update`, { data, eTag: consortium.eTag },
      key => collaborationApi.update(consortium.consortiumId, data, key, consortium.eTag))
  }, onSuccess: onSaved })
  function submit(event: FormEvent) {
    event.preventDefault()
    const found = consortiumIssue(name, summary); setIssue(found)
    if (found) return
    if (status === 2 && !confirm) { setConfirm(true); return }
    mutation.mutate()
  }
  return <form className={panel} onSubmit={submit} noValidate>
    <fieldset disabled={mutation.isPending} className="space-y-4">
      <Field label={t('collaboration.name')} required><input className={control} aria-required maxLength={160} value={name} onChange={e => setName(e.target.value)} /></Field>
      <Field label={t('collaboration.summary')}><textarea className={control} maxLength={1000} value={summary} onChange={e => setSummary(e.target.value)} /></Field>
      <Field label={t('collaboration.status')}><select className={control} value={status} onChange={e => { setStatus(Number(e.target.value)); setConfirm(false) }}>
        {consortiumStatuses.map((key, value) => <option value={value} key={key} disabled={(value === 0 && consortium.status === 1) || (value === 1 && consortium.status === 0 && consortium.acceptedCount === 0)}>{t(`collaboration.${key}`)}</option>)}
      </select></Field>
      <p className="text-sm">{t('collaboration.activateHelp')}</p><Feedback issue={issue} error={mutation.error} />
      {confirm && <p role="alert">{t('collaboration.confirmation', { action: t('collaboration.closed') })}</p>}
      <button className={button} type="submit">{t(confirm ? 'collaboration.confirm' : 'collaboration.save')}</button>
      {confirm && <button className={button} type="button" onClick={() => { setConfirm(false); setStatus(consortium.status) }}>{t('collaboration.cancel')}</button>}
    </fieldset></form>
}
function ParticipantCard({ participant, consortium, onSaved }: { participant: Participant; consortium: Consortium; onSaved: () => Promise<unknown> }) {
  const { t } = useTranslation()
  const actor = useCollaborationActor()
  const navigate = useNavigate()
  const client = useQueryClient()
  const [confirmation, setConfirmation] = useState<number | null>(null)
  const actions = [
    { value: 1, key: 'accept', allowed: participant.canRespond && consortium.projectIsPublic },
    { value: 2, key: 'reject', allowed: participant.canRespond },
    { value: 3, key: 'cancelInvite', allowed: participant.canCancel },
    { value: 4, key: 'leave', allowed: participant.canLeave },
    { value: 5, key: 'remove', allowed: participant.canRemove },
  ] as const
  const mutation = useMutation({ mutationFn: (action: number) => executeEditorialCommand(
    `collaboration:${actor}:${participant.participantId}:act`, { action, eTag: participant.eTag },
    key => collaborationApi.act(consortium.consortiumId, participant.participantId, action, key, participant.eTag)),
    onSuccess: async (_, action) => {
      setConfirmation(null)
      if ([2, 4].includes(action) && !consortium.canManage) {
        client.removeQueries({ queryKey: ['collaboration', actor, 'consortium', consortium.consortiumId], exact: true })
        await client.invalidateQueries({ queryKey: ['collaboration', actor, 'consortia'] })
        await navigate('/collaboration/consortia')
      } else await onSaved()
    } })
  const chosen = actions.find(action => action.value === confirmation)
  return <article className={panel}><h3 className="font-semibold">{participant.displayName}</h3>
    <p>{t(participant.kind === 1 ? 'collaboration.organizationKind' : 'collaboration.professionalKind')} · {t(`collaboration.${participantStatuses[participant.status]}`)}</p>
    <p className="break-words">{participant.contribution}</p>{participant.message && <p className="whitespace-pre-wrap break-words">{participant.message}</p>}
    <Feedback error={mutation.error} success={mutation.isSuccess ? 'actionDone' : null} />
    {chosen ? <div className="space-y-2"><p role="alert">{t('collaboration.confirmation', { action: t(`collaboration.${chosen.key}`) })}</p>
      <button className={button} disabled={mutation.isPending} onClick={() => mutation.mutate(chosen.value)}>{t('collaboration.confirm')}</button>
      <button className={button} disabled={mutation.isPending} onClick={() => setConfirmation(null)}>{t('collaboration.cancel')}</button></div>
      : <div className="flex flex-wrap gap-2">{actions.filter(action => action.allowed).map(action => <button className={button} key={action.value} disabled={mutation.isPending} onClick={() => setConfirmation(action.value)}>{t(`collaboration.${action.key}`)}</button>)}</div>}
  </article>
}
export function ConsortiumDetailPage() {
  const { t } = useTranslation()
  const { id = '' } = useParams()
  const actor = useCollaborationActor()
  const client = useQueryClient()
  const query = useQuery({ queryKey: ['collaboration', actor, 'consortium', id], queryFn: ({ signal }) => collaborationApi.consortium(id, signal), refetchOnWindowFocus: false })
  const consortium = query.data?.consortium
  const refresh = () => client.invalidateQueries({ queryKey: ['collaboration', actor] })
  return <div className="space-y-6"><CollaborationHeader title="consortia" />
    <LoadState pending={query.isPending} error={query.error} retry={() => query.refetch()} />
    {consortium && query.data && !query.isError && <>
      <section className={panel}><h2 className="text-2xl font-bold">{consortium.name}</h2>
        <p>{t('collaboration.lead', { name: consortium.leadOrganizationName })}</p><p>{t(`collaboration.${consortiumStatuses[consortium.status]}`)}</p>
        {consortium.summary && <p className="whitespace-pre-wrap break-words">{consortium.summary}</p>}
        <p>{consortium.projectTitle ?? t('collaboration.privateProject')}</p>
        {consortium.projectSlug && <Link className={button} to={`/marketplace/projects/${encodeURIComponent(consortium.projectSlug)}`}>{t('collaboration.publicProject')}</Link>}
        {!consortium.projectIsPublic && consortium.status !== 2 && <p>{t('collaboration.publicationRequired')}</p>}
      </section>
      {consortium.canManage && consortium.status !== 2 && <ConsortiumEditor key={consortium.eTag} consortium={consortium} onSaved={refresh} />}
      <section className="space-y-4"><h2 className="text-xl font-semibold">{t('collaboration.roster')}</h2>
        <p>{consortium.canViewRoster ? t('collaboration.acceptedCount', { count: consortium.acceptedCount }) : t('collaboration.rosterPrivate')}</p>
        {query.data.participants.map(participant => <ParticipantCard key={participant.participantId + participant.eTag} participant={participant} consortium={consortium} onSaved={refresh} />)}
      </section>
      {consortium.canManage && consortium.projectIsPublic && consortium.status !== 2 && <ConsortiumInvitationForm consortium={consortium} onSaved={refresh} />}
    </>}
    <button className={button} onClick={() => { void query.refetch() }}>{t('collaboration.refresh')}</button>
  </div>
}
