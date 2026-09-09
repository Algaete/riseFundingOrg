import { ArrowRight, Coins, FileText, UserRound, UsersRound } from 'lucide-react'
import { Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { useAuth } from '@/features/auth/use-auth'
import { HomeSearch } from './home-search'
import { HomeProjects } from './home-projects'
import { HomeMap } from './home-map'
import './home.css'

export function HomePage() {
  const { t } = useTranslation()
  const auth = useAuth()
  const authenticated = auth.status === 'authenticated' && auth.session !== null
  const admin = auth.session?.user.roles.some(role => role === 'Admin' || role === 'SuperAdmin')
  const createUrl = authenticated ? '/projects' : '/register'
  const shortcuts = [
    { key: 'publishFunding', icon: Coins, to: admin ? '/admin/funding' : '/funder-workspace/funding', color: 'mint' },
    { key: 'fundProjects', icon: FileText, to: '/marketplace', color: 'violet' },
    { key: 'partners', icon: UsersRound, to: '/network', color: 'blue' },
    { key: 'professionals', icon: UserRound, to: '/professionals', color: 'sand' },
  ] as const
  return <div className="impact-home">
    <section className="home-hero" aria-labelledby="home-title">
      <img className="home-hero-photo" src="/images/home-impact-hero.jpg" alt="" width={2172} height={724} fetchPriority="high" />
      <div className="home-hero-wash" />
      <div className="home-container home-hero-content">
        <p className="home-eyebrow">{t('home.eyebrow')}</p>
        <h1 id="home-title">{t('home.title')}</h1>
        <p className="home-description">{t('home.description')}</p>
        <div className="home-hero-actions"><Link className="home-primary" to="/funding">{t('actions.findFunding')}<ArrowRight size={18} aria-hidden="true" /></Link><Link className="home-secondary" to={createUrl}>{t('actions.publishProject')}</Link></div>
      </div>
    </section>
    <div className="home-container home-main-content">
      <HomeSearch />
      <nav className="home-shortcuts" aria-label={t('home.shortcuts.label')}>{shortcuts.map(({ key, icon: Icon, to, color }) => <Link key={key} to={to} className={`home-shortcut home-shortcut-${color}`}><span><Icon size={27} strokeWidth={1.6} aria-hidden="true" /></span><span>{t(`home.shortcuts.${key}`)}</span><ArrowRight className="home-shortcut-arrow" size={17} aria-hidden="true" /></Link>)}</nav>
      <div className="home-discovery-grid"><HomeProjects createUrl={createUrl} /><HomeMap /></div>
    </div>
  </div>
}
