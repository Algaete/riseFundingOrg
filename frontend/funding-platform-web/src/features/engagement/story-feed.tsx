import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { engagementApi } from './engagement-api'
import { panel, Paging } from './engagement-ui'

export function StoryFeed({ organizationId, projectId, compact = false }: { organizationId?: string; projectId?: string; compact?: boolean }) {
  const { t } = useTranslation()
  const [page, setPage] = useState(1)
  const query = useQuery({ queryKey: ['stories', organizationId, projectId, page], queryFn: ({ signal }) => engagementApi.stories(organizationId, projectId, page, signal), retry: false })
  const items = Array.isArray(query.data?.items) ? query.data.items : []
  return <section className="space-y-4"><h2 className="text-2xl font-bold">{t('engagement.stories')}</h2>
    {query.isPending && <p role="status">{t('engagement.loading')}</p>}
    {query.isError && <p role="status">{t('engagement.storiesUnavailable')}</p>}
    {query.isSuccess && items.length === 0 && <p>{t('engagement.noStories')}</p>}
    <div className={compact ? 'space-y-4' : 'grid gap-4 md:grid-cols-2'}>{items.map(story => <article key={story.id} className={panel}>
      <p className="text-sm text-primary">{story.organizationName} · {t(`engagement.kinds.${story.content.kind}`, { defaultValue: story.content.kind })}</p>
      <h3 className="text-xl font-bold"><Link to={`/stories/${story.id}`}>{story.content.title}</Link></h3>
      <p className="whitespace-pre-wrap">{story.content.summary || story.content.body.slice(0, 220)}</p>
      <Link className="text-primary underline" to={`/stories/${story.id}`}>{t('engagement.readStory')}</Link>
    </article>)}</div>
    {query.data && <Paging page={page} total={query.data.totalCount} onPage={setPage} disabled={query.isFetching} />}
  </section>
}
