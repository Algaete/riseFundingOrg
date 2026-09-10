import { useQuery } from '@tanstack/react-query'
import { ArrowRight, Building2, Coins, Sprout, Target } from 'lucide-react'
import { Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { marketplaceApi, type MarketplaceProjectItem } from '@/features/marketplace/marketplace-api'
import { formatMoneyValue, formatNumber } from '@/i18n/formats'
import { fundingProgress, publishedHomeProjects } from './home-model'

function HomeProjectCard({ project }: { project: MarketplaceProjectItem }) {
  const { t } = useTranslation()
  const progress = fundingProgress(project)
  const url = `/marketplace/projects/${encodeURIComponent(project.slug)}`
  return <article className="home-project-card">
    {/* Project attachments are private. Never substitute a stock photo for an owner's image. */}
    <div className="home-project-art" aria-hidden="true"><Target size={44} strokeWidth={1.25} /><span>{t('home.featured.illustration')}</span></div>
    <div className="home-project-body">
      <h3><Link to={url}>{project.title}</Link></h3>
      <p className="home-project-summary">{project.summary}</p>
      <p className="home-project-meta"><Building2 size={15} aria-hidden="true" /><Link to={`/marketplace/organizations/${encodeURIComponent(project.organization.publicId)}`}>{project.organization.name}</Link></p>
      <p className="home-project-meta"><Coins size={15} aria-hidden="true" /><span>{formatMoneyValue(project.fundingGap, project.currency, t('home.featured.unknownAmount'))}{project.fundingGap !== null && project.currency ? ` ${t('home.featured.required')}` : ''}</span></p>
      {progress !== null ? <div className="home-progress-row"><progress max={100} value={progress} aria-label={t('home.featured.progress', { title: project.title })} /><span>{t('home.featured.funded', { percent: formatNumber(progress) })}</span></div>
        : <p className="home-project-meta">{t('home.featured.progressUnknown')}</p>}
      <Link className="home-text-link home-project-link" to={url}>{t('home.featured.view')}<ArrowRight size={15} aria-hidden="true" /></Link>
    </div>
  </article>
}

export function HomeProjects({ createUrl }: { createUrl: string }) {
  const { t } = useTranslation()
  const projects = useQuery({ queryKey: ['home', 'published-projects'], queryFn: ({ signal }) => marketplaceApi.search({ sort: 'newest', page: 1, pageSize: 3 }, signal), retry: false, staleTime: 60_000 })
  const items = publishedHomeProjects(projects.data?.items ?? [])
  return <section className="home-projects" aria-labelledby="home-projects-title">
    <div className="home-section-heading"><h2 id="home-projects-title">{t('home.featured.title')}</h2><Link className="home-text-link" to="/marketplace">{t('home.featured.all')}<ArrowRight size={15} aria-hidden="true" /></Link></div>
    <p className="sr-only">{t('home.featured.recent')}</p>
    {projects.isPending ? <div className="home-projects-state" role="status">{t('home.featured.loading')}</div>
      : projects.isError ? <div className="home-projects-state" role="status"><Target size={32} aria-hidden="true" /><p>{t('home.featured.error')}</p><button className="home-text-link" onClick={() => void projects.refetch()}>{t('home.featured.retry')}</button></div>
      : items.length > 0 ? <div className="home-project-grid">{items.map(project => <HomeProjectCard key={project.publicId} project={project} />)}</div>
      : <div className="home-projects-empty"><span className="home-empty-icon"><Sprout size={34} strokeWidth={1.5} aria-hidden="true" /></span><h3>{t('home.featured.emptyTitle')}</h3><p>{t('home.featured.emptyDescription')}</p><Link className="home-text-link" to={createUrl}>{t('home.featured.create')}<ArrowRight size={16} aria-hidden="true" /></Link></div>}
  </section>
}
