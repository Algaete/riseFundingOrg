import { useQuery } from '@tanstack/react-query'
import { ArrowRight } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { Link } from 'react-router-dom'
import { clusterPoints } from '@/features/project-map/map-geometry'
import { projectMapApi } from '@/features/project-map/project-map-api'
import world from '@/features/project-map/world-land.svg'

export function HomeMap() {
  const { t } = useTranslation()
  const query = useQuery({ queryKey: ['home', 'public-map'], queryFn: ({ signal }) => projectMapApi.search(new URLSearchParams({ page: '1', pageSize: '100' }), signal), retry: false, staleTime: 60_000 })
  const clusters = query.isError ? [] : clusterPoints(query.data?.items ?? [], 0)
  return <section className="home-map" aria-labelledby="home-map-title">
    <div className="home-section-heading"><h2 id="home-map-title">{t('home.map.title')}</h2><Link className="home-text-link" to="/marketplace/map">{t('home.map.explore')}<ArrowRight size={15} aria-hidden="true" /></Link></div>
    <div className="home-map-canvas" role="group" aria-label={t('home.map.label')}>
      <img src={world} alt="" width={720} height={360} className="home-map-land" />
      {clusters.map(cluster => <Link key={cluster.key} to="/marketplace/map" className="home-map-marker" style={{ left: `${Math.max(4, Math.min(96, cluster.x / 720 * 100))}%`, top: `${Math.max(8, Math.min(92, cluster.y / 360 * 100))}%` }} aria-label={t('home.map.cluster', { count: cluster.items.length })}>{cluster.items.length}</Link>)}
      {(query.isPending || query.isError || clusters.length === 0) && <div className="home-map-notice" role="status"><p>{t(query.isPending ? 'home.map.loading' : query.isError ? 'home.map.error' : 'home.map.empty')}</p>{query.isError && <button className="home-text-link" onClick={() => void query.refetch()}>{t('home.map.retry')}</button>}</div>}
    </div>
    <p className="home-map-legend"><span aria-hidden="true" />{t('home.map.legend')}</p>
    {query.data && query.data.totalCount > query.data.items.length && <p className="home-map-caption">{t('home.map.partial', { count: query.data.items.length, total: query.data.totalCount })}</p>}
    <a className="home-map-attribution" href="https://www.naturalearthdata.com/about/terms-of-use/" target="_blank" rel="noreferrer">{t('home.map.attribution')}</a>
  </section>
}
