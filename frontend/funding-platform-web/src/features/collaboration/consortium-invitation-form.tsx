import { useState, type FormEvent } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useQuery, useMutation } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { executeEditorialCommand } from '@/features/funding/editorial-command-cache'
import { collaborationApi, type Consortium, type InvitationInput } from './collaboration-api'
import { invitationIssue } from './collaboration-validation'
import { button, control, panel, Feedback, Field, LoadState, Paging, useCollaborationActor, type CopyKey } from './collaboration-ui'

export function ConsortiumInvitationForm({ consortium, onSaved }: { consortium: Consortium; onSaved: () => Promise<unknown> }) {
  const { t } = useTranslation()
  const actor = useCollaborationActor()
  const [parameters] = useSearchParams()
  const [kind, setKind] = useState<1 | 2>(parameters.has('professionalId') ? 2 : 1)
  const [targetId, setTargetId] = useState(parameters.get('professionalId') ?? '')
  const [search, setSearch] = useState('')
  const [q, setQ] = useState('')
  const [page, setPage] = useState(1)
  const [contribution, setContribution] = useState('')
  const [message, setMessage] = useState('')
  const [issue, setIssue] = useState<CopyKey | null>(null)
  const candidates = useQuery({ queryKey: ['collaboration', actor, 'candidates', consortium.leadOrganizationId, kind, q, page], queryFn: async ({ signal }) => {
    if (kind === 2) {
      const result = await collaborationApi.professionals(q, '', '', page, signal)
      return { ...result, items: result.items.filter(item => item.data.allowsInvitations).map(item => ({ id: item.profileId, name: item.data.displayName })) }
    }
    const result = await collaborationApi.connections(consortium.leadOrganizationId, page, signal)
    return { ...result, items: result.items.filter(item => item.status === 'accepted' && item.counterpartyIsPublic).map(item => ({ id: item.counterpartyOrganizationId, name: item.counterpartyOrganizationName })) }
  } })
  const mutation = useMutation({ mutationFn: (input: InvitationInput) => executeEditorialCommand(
    `collaboration:${actor}:${consortium.consortiumId}:invite`, { input, eTag: consortium.eTag },
    key => collaborationApi.invite(consortium.consortiumId, input, key, consortium.eTag)),
    onSuccess: async () => { setTargetId(''); setContribution(''); setMessage(''); await onSaved() } })
  function submit(event: FormEvent) {
    event.preventDefault()
    const input = { kind, targetId, contribution: contribution.trim(), message: message.trim() }
    const found = invitationIssue(input); setIssue(found)
    if (!found) mutation.mutate(input)
  }
  return <section className={panel}><h2 className="text-xl font-semibold">{t('collaboration.invite')}</h2><p>{t('collaboration.inviteHelp')}</p>
    <fieldset disabled={mutation.isPending} className="space-y-4">
      <Field label={t('collaboration.target')}><select className={control} value={kind} onChange={e => { setKind(Number(e.target.value) as 1 | 2); setTargetId(''); setPage(1) }}>
        <option value={1}>{t('collaboration.organizationKind')}</option><option value={2}>{t('collaboration.professionalKind')}</option>
      </select></Field>
      {kind === 2 && <form className="flex items-end gap-2" onSubmit={e => { e.preventDefault(); setQ(search.trim()); setPage(1); setTargetId('') }}>
        <Field label={t('collaboration.searchHint')}><input className={control} maxLength={200} value={search} onChange={e => setSearch(e.target.value)} /></Field><button className={button}>{t('collaboration.search')}</button></form>}
      <LoadState pending={candidates.isPending} error={candidates.error} retry={() => candidates.refetch()} />
      <form className="space-y-4" onSubmit={submit} noValidate>
        <Field label={t('collaboration.target')} required><select className={control} aria-required value={targetId} onChange={e => setTargetId(e.target.value)}>
          <option value="">{t('collaboration.choose')}</option>
          {targetId && !candidates.data?.items.some(item => item.id === targetId) && <option value={targetId}>{t('collaboration.selectedProfessional')}</option>}
          {candidates.data?.items.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}
        </select></Field>
        {candidates.data && <><Paging page={page} total={candidates.data.totalCount} setPage={setPage} disabled={candidates.isFetching} />{candidates.data.items.length === 0 && <p>{t('collaboration.noCandidates')}</p>}</>}
        <Field label={t('collaboration.contribution')} required><input className={control} aria-required maxLength={160} value={contribution} onChange={e => setContribution(e.target.value)} /></Field>
        <Field label={t('collaboration.message')} required><textarea className={control} aria-required minLength={10} maxLength={500} rows={3} value={message} onChange={e => setMessage(e.target.value)} /></Field>
        <p className="text-sm">{t('collaboration.messagePrivacy')}</p><Feedback issue={issue} error={mutation.error} success={mutation.isSuccess ? 'sent' : null} />
        <button className={button} type="submit" disabled={candidates.isPending}>{t('collaboration.send')}</button>
      </form>
    </fieldset></section>
}
