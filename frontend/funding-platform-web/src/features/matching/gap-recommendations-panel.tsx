import { useId, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { Link } from 'react-router-dom'
import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { useAuth } from '@/features/auth/use-auth'
import { formatDateValue } from '@/i18n/formats'
import { gapCandidateHref, gapEvidenceHref, gapRecommendationsApi } from './gap-recommendations-api'
import { PartnerGeographySummary, PartnerCountryEvidence } from './partner-geography-summary'

type Props = { projectId: string; opportunityId: string; hasHardGaps: boolean; historical: boolean }

export function GapRecommendationsPanel(props: Props) {
  const actor = useAuth().session?.user.publicId
  // Changing actor or either entity discards expansion state and any previous private result.
  return <RecommendationPanel key={`${actor}:${props.projectId}:${props.opportunityId}`} {...props} actor={actor} />
}

function RecommendationPanel({ projectId, opportunityId, hasHardGaps, historical, actor }: Props & { actor?: string }) {
  const { t } = useTranslation()
  const panelId = useId()
  const [opened, setOpened] = useState(false)
  const query = useQuery({
    queryKey: ['gap-recommendations', actor, projectId, opportunityId],
    queryFn: ({ signal }) => gapRecommendationsApi.read(projectId, opportunityId, signal),
    enabled: false, retry: false, gcTime: 0, staleTime: 0,
    refetchOnMount: false, refetchOnWindowFocus: false, refetchOnReconnect: false, refetchInterval: false,
  })
  const data = opened && !query.isFetching && !query.isError ? query.data : undefined
  const evidence = data ? gapEvidenceHref(data.evidenceUrl) : null
  const errorKey = query.error instanceof ApiError && [401, 403, 404].includes(query.error.response.status)
    ? 'unavailable' : query.error instanceof ApiError && query.error.response.status === 429 ? 'limit' : 'error'
  return <section className="space-y-3 rounded-lg border p-4" aria-label={t('matching.gaps.title')}>
    <h3 className="font-bold">{t('matching.gaps.title')}</h3>
    <p className="text-sm text-muted-foreground">{t('matching.gaps.intro')}</p>
    <Button type="button" variant="outline" className="h-auto min-h-10 max-w-full whitespace-normal text-center" disabled={!actor || query.isFetching} aria-controls={panelId} aria-expanded={opened}
      onClick={() => { setOpened(true); void query.refetch() }}>
      {query.isFetching ? t('matching.gaps.loading') : opened ? t('matching.gaps.refresh') : t('matching.gaps.load')}
    </Button>
    <div id={panelId} className="space-y-4">
      {opened && <>
        <p className="text-sm">{t('matching.gaps.disclaimer')}</p>
        {hasHardGaps && <p className="rounded-lg bg-amber-100 p-3 text-sm text-amber-950 dark:bg-amber-950 dark:text-amber-100">{t('matching.gaps.hardGaps')}</p>}
        {historical && <p className="text-sm">{t('matching.gaps.historical')}</p>}
      </>}
      {opened && query.isFetching && <p role="status">{t('matching.gaps.loading')}</p>}
      {opened && query.isError && <p role="alert">{t(`matching.gaps.${errorKey}`)}</p>}
      {data && <>
        <p className="text-xs text-muted-foreground">{t('matching.gaps.evaluated', {
          date: formatDateValue(data.evaluatedAtUtc, { dateStyle: 'medium', timeStyle: 'short' }), version: data.contentVersion,
        })}</p>
        {!data.classificationCurrent && <p role="status" className="rounded-lg bg-muted p-3 text-sm">{t('matching.gaps.unreviewed')}</p>}
        {evidence && <a className="text-sm font-semibold text-primary underline" href={evidence} target="_blank" rel="noopener noreferrer">{t('matching.gaps.evidence')}</a>}
        {data.items.length === 0 && <p>{t('matching.gaps.empty')}</p>}
        <PartnerGeographySummary data={data} />
        {data.items.map(item => <section key={item.code} className="space-y-3 rounded-lg bg-muted/40 p-3" aria-label={t(`matching.gaps.need.${item.code}`)}>
          <h4 className="font-semibold">{t(`matching.gaps.need.${item.code}`)}</h4>
          <p className="text-xs">{item.origins.map(origin => t(`matching.gaps.origin.${origin}`)).join(' · ')}</p>
          {item.declaredNeed && <p className="break-words text-sm">{item.declaredNeed}</p>}
          <p className="text-sm">{t(`matching.gaps.help.${item.code}`)}</p>
          {item.state !== 'suggestions' && <p role="status">{t(`matching.gaps.state.${item.state}`)}</p>}
          <ul className="grid gap-3">
            {item.candidates.map(candidate => {
              const href = gapCandidateHref(candidate, item.code)
              return <li key={candidate.id} className="min-w-0 space-y-2 rounded-lg border bg-background p-3">
                <h5 className="break-words font-semibold">{candidate.name}</h5>
                {candidate.summary && <p className="break-words text-sm text-muted-foreground">{candidate.summary}</p>}
                {candidate.sharedCategoryIds.length > 0 && <p className="text-sm">{t('matching.gaps.sharedAreas', { count: candidate.sharedCategoryIds.length })}</p>}
                {candidate.sharedSkills.length > 0 && <p className="break-words text-sm">{t('matching.gaps.sharedSkills', { skills: candidate.sharedSkills.join(', ') })}</p>}
                {item.code === 'international-partner' && <p className="text-sm">{t('matching.gaps.foreignCountry')}</p>}
                {item.code !== 'professionals' && data.geographyState && <PartnerCountryEvidence id={candidate.homeCountryId} />}
                {item.code !== 'professionals' && data.geographyState === 'specific' && <p className="text-sm">{t('matching.gaps.geography.matched')}</p>}
                {href && <Link className="inline-block text-sm font-semibold text-primary underline" to={href}>
                  {item.code === 'professionals' ? t('matching.gaps.considerProfessional') : t('matching.gaps.viewOrganization')}
                </Link>}
              </li>
            })}
          </ul>
          <p className="text-xs text-muted-foreground">{t('matching.gaps.corpus', { count: item.evaluatedCandidateCount, total: item.totalCandidateCount })}</p>
          {item.isTruncated && <p className="text-xs">{t('matching.gaps.truncated')}</p>}
        </section>)}
        <div className="flex flex-wrap gap-4 text-sm font-semibold text-primary underline">
          <Link to={`/projects/${encodeURIComponent(projectId)}`}>{t('matching.gaps.editProject')}</Link>
          <Link to="/collaboration/consortia">{t('matching.gaps.reviewTeam')}</Link>
        </div>
      </>}
    </div>
  </section>
}
