import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { LoaderCircle, ShieldCheck } from 'lucide-react'
import { useId, useState } from 'react'
import { useTranslation } from 'react-i18next'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { formatDateValue } from '@/i18n/formats'
import {
  adminOrganizationsApi,
  type OrganizationVerificationDecision,
  type OrganizationVerificationStatus,
} from './admin-organizations-api'
import { verificationNames } from './organization-verification-labels'

export function OrganizationVerificationBadge({ status = 0 }: { status?: number }) {
  const { t } = useTranslation()
  return <span className="rounded-full bg-muted px-2.5 py-1 text-xs font-semibold">
    {t(verificationNames[status] ?? 'operations.unknown')}
  </span>
}

interface Props {
  organizationId: string
  profileVersion: number
  refreshProfile: () => Promise<boolean>
}

export function OrganizationVerificationPanel({ organizationId, profileVersion, refreshProfile }: Props) {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const reasonId = useId()
  const [reason, setReason] = useState('')
  const [choice, setChoice] = useState<Omit<OrganizationVerificationDecision, 'reason'> | null>(null)
  const [conflict, setConflict] = useState(false)
  const [reloading, setReloading] = useState(false)
  const [notice, setNotice] = useState<'saved' | 'failed' | 'loadFailed' | 'forbidden' | 'invalid' | null>(null)
  const queryKey = ['admin-organization-verification', organizationId]
  const verification = useQuery({
    queryKey,
    queryFn: ({ signal }) => adminOrganizationsApi.getVerification(organizationId, signal),
    retry: false,
    refetchOnWindowFocus: false,
  })
  const decision = useMutation({
    mutationFn: (value: OrganizationVerificationDecision) => adminOrganizationsApi.decideVerification(organizationId, value),
    retry: false,
    onSuccess: value => {
      queryClient.setQueryData(queryKey, value)
      void queryClient.invalidateQueries({ queryKey: ['admin-organizations'] })
      setChoice(null)
      setReason('')
      setNotice('saved')
    },
    onError: error => {
      // Never repeat an editorial decision automatically, including after a stale-version response.
      setChoice(null)
      if (error instanceof ApiError && error.response.status === 409) {
        setConflict(true)
        setReason('')
        setNotice(null)
      } else {
        setNotice(error instanceof ApiError && [401, 403].includes(error.response.status)
          ? 'forbidden'
          : error instanceof ApiError && [400, 422].includes(error.response.status) ? 'invalid' : 'failed')
      }
    },
  })
  const value = verification.data
  const profileChanged = Boolean(value && value.profileVersion !== profileVersion)
  const busy = verification.isFetching || reloading || decision.isPending
  const needsReload = notice !== null && notice !== 'saved'
  const blocked = busy || conflict || profileChanged || needsReload || verification.isError || !value
  const trimmedReason = reason.trim()
  const reasonValid = trimmedReason.length >= 5 && trimmedReason.length <= 2000
  const reasonError = reason.length > 0 && !reasonValid

  async function reload() {
    if (busy) return
    setReloading(true)
    setChoice(null)
    setReason('')
    setNotice(null)
    try {
      const [profileLoaded, snapshot] = await Promise.all([refreshProfile(), verification.refetch()])
      if (!profileLoaded || snapshot.isError) {
        setNotice('loadFailed')
        return
      }
      setConflict(false)
    } catch {
      setNotice('loadFailed')
    } finally {
      setReloading(false)
    }
  }

  function select(status: OrganizationVerificationStatus) {
    if (blocked || !value || !reasonValid) return
    setNotice(null)
    setChoice({ status, expectedRevision: value.revision, expectedProfileVersion: value.profileVersion })
  }

  function confirm() {
    if (blocked || !choice || !value || !reasonValid) return
    if (choice.expectedRevision !== value.revision || choice.expectedProfileVersion !== value.profileVersion) {
      setConflict(true)
      setChoice(null)
      setReason('')
      return
    }
    decision.mutate({ ...choice, reason: trimmedReason })
  }

  const date = (utc: string) => formatDateValue(utc, { dateStyle: 'medium', timeStyle: 'short' })

  return <Card>
    <CardHeader><CardTitle className="flex items-center gap-2"><ShieldCheck className="size-5" />{t('adminOrganizations.verificationTitle')}</CardTitle></CardHeader>
    <CardContent className="space-y-5">
      <p className="text-sm text-muted-foreground">{t('adminOrganizations.verificationDisclaimer')}</p>
      {verification.isPending && <p className="flex items-center gap-2 text-sm" role="status"><LoaderCircle className="size-4 animate-spin" />{t('adminOrganizations.verificationLoading')}</p>}
      {(verification.isError || notice === 'loadFailed') && <div role="alert" className="space-y-2 rounded-lg border border-destructive/40 p-3">
        <p>{t('adminOrganizations.verificationLoadFailed')}</p>
      </div>}
      {(conflict || profileChanged) && <div role="alert" className="space-y-2 rounded-lg border border-destructive/40 p-3">
        <p>{t('adminOrganizations.verificationConflict')}</p>
      </div>}
      {(verification.isError || notice === 'loadFailed' || conflict || profileChanged) && <Button type="button" disabled={busy} onClick={() => void reload()} variant="outline">{t('adminOrganizations.verificationReload')}</Button>}
      {value && <>
        <div className="flex flex-wrap items-center gap-3"><OrganizationVerificationBadge status={value.status} /><span className="text-sm text-muted-foreground">{t('adminOrganizations.verificationVersions', { revision: value.revision, version: value.profileVersion })}</span></div>
        {value.needsReverification && <p role="status" className="rounded-lg bg-muted p-3 text-sm">{t('adminOrganizations.verificationProfileChanged')}</p>}
        {value.reviewedAtUtc && <dl className="grid gap-3 text-sm sm:grid-cols-2">
          <div><dt className="text-muted-foreground">{t('adminOrganizations.verificationLastDecision')}</dt><dd>{t(verificationNames[value.recordedStatus] ?? 'operations.unknown')}</dd></div>
          <div><dt className="text-muted-foreground">{t('adminOrganizations.verificationReviewedProfile')}</dt><dd>{value.reviewedProfileVersion ?? t('operations.notReported')}</dd></div>
          <div><dt className="text-muted-foreground">{t('adminOrganizations.verificationReviewer')}</dt><dd>{value.reviewedByName ?? value.reviewedByUserPublicId ?? t('operations.notReported')}</dd></div>
          <div><dt className="text-muted-foreground">{t('adminOrganizations.verificationDate')}</dt><dd>{date(value.reviewedAtUtc)}</dd></div>
          <div className="sm:col-span-2"><dt className="text-muted-foreground">{t('adminOrganizations.verificationLastReason')}</dt><dd className="whitespace-pre-wrap break-words">{value.reason ?? t('operations.notReported')}</dd></div>
        </dl>}
        <div className="space-y-2">
          <label className="block text-sm font-semibold" htmlFor={reasonId}>{t('adminOrganizations.verificationReason')} *</label>
          <textarea id={reasonId} aria-describedby={`${reasonId}-help`} aria-invalid={reasonError} className="min-h-28 w-full rounded-lg border bg-background px-3 py-2 text-sm disabled:opacity-50" disabled={blocked || choice !== null} maxLength={2000} onChange={event => { setReason(event.target.value); setNotice(null) }} value={reason} />
          <p id={`${reasonId}-help`} className={reasonError ? 'text-sm text-destructive' : 'text-sm text-muted-foreground'}>{t('adminOrganizations.verificationReasonHelp')}</p>
        </div>
        {!choice && <div className="flex flex-wrap gap-2">
          <Button type="button" disabled={blocked || !reasonValid} onClick={() => select(1)}>{t('adminOrganizations.verificationApprove')}</Button>
          <Button type="button" disabled={blocked || !reasonValid} onClick={() => select(2)} variant="outline">{t('adminOrganizations.verificationReject')}</Button>
          <Button type="button" disabled={blocked || !reasonValid} onClick={() => select(0)} variant="outline">{t('adminOrganizations.verificationReopen')}</Button>
        </div>}
        {choice && <section aria-label={t('adminOrganizations.verificationConfirmTitle')} className="space-y-3 rounded-lg border p-4">
          <p className="font-semibold">{t('adminOrganizations.verificationConfirm', { status: t(verificationNames[choice.status]) })}</p>
          <p className="whitespace-pre-wrap break-words text-sm">{trimmedReason}</p>
          <div className="flex flex-wrap gap-2"><Button type="button" disabled={blocked || !reasonValid} onClick={confirm}>{decision.isPending && <LoaderCircle className="size-4 animate-spin" />}{t('adminOrganizations.verificationConfirmAction')}</Button><Button type="button" disabled={decision.isPending} onClick={() => setChoice(null)} variant="outline">{t('adminOrganizations.verificationCancel')}</Button></div>
        </section>}
        {notice === 'saved' && <p role="status" className="text-sm text-primary">{t('adminOrganizations.verificationSaved')}</p>}
        {notice && ['failed', 'forbidden', 'invalid'].includes(notice) && <div role="alert" className="space-y-2"><p className="text-sm text-destructive">{t(notice === 'forbidden' ? 'adminOrganizations.verificationForbidden' : notice === 'invalid' ? 'adminOrganizations.verificationInvalid' : 'adminOrganizations.verificationFailed')}</p><Button type="button" disabled={busy} onClick={() => void reload()} variant="outline">{t('adminOrganizations.verificationReload')}</Button></div>}
        <details><summary className="cursor-pointer text-sm font-semibold">{t('adminOrganizations.verificationHistory')}</summary>
          {!(value.history?.length) && <p className="mt-3 text-sm text-muted-foreground">{t('adminOrganizations.verificationNoHistory')}</p>}
          <ol className="mt-3 space-y-3">{(value.history ?? []).map(entry => <li className="space-y-1 rounded-lg border p-3 text-sm" key={entry.revision}>
            <p className="font-semibold">{t(verificationNames[entry.status] ?? 'operations.unknown')} · {t('adminOrganizations.verificationVersions', { revision: entry.revision, version: entry.profileVersion })}</p>
            <p className="text-muted-foreground">{entry.reviewedByName ?? entry.reviewedByUserPublicId} · {date(entry.reviewedAtUtc)}</p>
            <p className="whitespace-pre-wrap break-words">{entry.reason}</p>
          </li>)}</ol>
        </details>
      </>}
    </CardContent>
  </Card>
}
