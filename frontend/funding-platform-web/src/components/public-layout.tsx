import { ChevronDown, LayoutDashboard, LogIn, Menu, Search, X } from 'lucide-react'
import { useRef, useState } from 'react'
import { Link, Outlet, useLocation } from 'react-router-dom'
import { useTranslation } from 'react-i18next'

import { BrandMark } from '@/components/brand-mark'
import { LanguageSelector } from '@/components/language-selector'
import { ThemeToggle } from '@/components/theme/theme-toggle'
import { Button } from '@/components/ui/button'
import { useAuth } from '@/features/auth/use-auth'

// Only completed translation blocks inherit the chosen interface language.
const translatedPaths = new Set([
  '/', '/login', '/register', '/forgot-password', '/reset-password',
  '/verify-email', '/mfa', '/mfa/setup', '/auth/external/callback',
  '/pricing', '/alerts/unsubscribe', '/marketplace/map', '/search',
])

export function PublicLayout() {
  const { t } = useTranslation()
  const { pathname } = useLocation()
  const [menuOpen, setMenuOpen] = useState(false)
  const menuTrigger = useRef<HTMLButtonElement | null>(null)
  const isHome = pathname === '/'
  const translatedDiscovery = /^\/(?:funding(?:\/[^/]+)?|marketplace(?:\/(?:projects|organizations)\/[^/]+)?|projects\/public\/[^/]+)\/?$/i.test(pathname)
  const auth = useAuth()
  const isAuthenticated = auth.status === 'authenticated' && auth.session !== null
  const workspaceUrl = auth.session?.user.roles.some(role => role === 'Admin' || role === 'SuperAdmin')
    ? '/admin'
    : '/dashboard'
  const links = [
    { to: '/funding', key: 'opportunities' },
    { to: '/marketplace', key: 'projects' },
    { to: '/network', key: 'organizations', extra: true },
    { to: '/collaboration/consortia', key: 'alliances', extra: true },
    { to: '/professionals', key: 'professionals', extra: true },
    { to: '/pricing', key: 'plans' },
  ] as const
  function toggleMenu(event: React.MouseEvent<HTMLButtonElement>) {
    menuTrigger.current = event.currentTarget
    setMenuOpen(value => !value)
  }

  return (
    <div className={`min-h-screen ${isHome ? 'reference-home' : ''}`}>
      <header className="sticky top-0 z-20 border-b bg-background/95 backdrop-blur" onKeyDown={event => {
        if (event.key === 'Escape' && menuOpen) { setMenuOpen(false); menuTrigger.current?.focus() }
      }}>
        <div className="mx-auto flex min-h-16 max-w-7xl items-center justify-between gap-3 px-4 py-2 sm:px-6">
          <div className="hidden xl:block">
            <BrandMark />
          </div>
          <div className="shrink-0 xl:hidden">
            <BrandMark compact />
          </div>
          <nav className="hidden items-center gap-1 lg:flex" aria-label={t('navigation.main')}>
            {links.map(link => <Button key={link.key} variant="ghost" asChild className={`px-2 text-[13px] font-medium ${'extra' in link ? 'hidden 2xl:inline-flex' : ''}`}>
              <Link to={link.to}>{t(`navigation.${link.key}`)}</Link>
            </Button>)}
            <Button variant="ghost" className="px-2 2xl:hidden" aria-expanded={menuOpen} aria-controls="public-explore-menu" onClick={toggleMenu}>{t('navigation.more')}<ChevronDown className="size-3" aria-hidden="true" /></Button>
            <Button variant="ghost" size="icon" asChild><Link to="/search" aria-label={t('navigation.search')}><Search className="size-4" aria-hidden="true" /></Link></Button>
            <LanguageSelector />
            <ThemeToggle />
            {isAuthenticated ? <Button asChild><Link to={workspaceUrl}><LayoutDashboard className="size-4" />{t('actions.workspace')}</Link></Button> : <>
              <Button variant="ghost" asChild><Link to="/login">{t('actions.signIn')}</Link></Button>
              <Button asChild><Link to="/register">{t('actions.createAccount')}</Link></Button>
            </>}
          </nav>
          <div className="flex items-center gap-1 lg:hidden">
            <LanguageSelector />
            <ThemeToggle />
            <Button size="icon" variant="ghost" asChild>
              <Link to={isAuthenticated ? workspaceUrl : '/login'} aria-label={isAuthenticated ? t('actions.workspace') : t('actions.signIn')}>
                {isAuthenticated ? <LayoutDashboard className="size-5" /> : <LogIn className="size-5" />}
              </Link>
            </Button>
          </div>
        </div>
        <div className="border-t px-4 py-1.5 lg:hidden"><button type="button" className="flex min-h-8 w-full items-center justify-between gap-2 text-xs font-semibold" aria-expanded={menuOpen} aria-controls="public-explore-menu" onClick={toggleMenu}>{t('navigation.explore')}{menuOpen ? <X className="size-4" aria-hidden="true" /> : <Menu className="size-4" aria-hidden="true" />}</button></div>
        {menuOpen && <nav id="public-explore-menu" className="mx-auto grid max-w-7xl grid-cols-2 gap-2 border-t px-4 py-4 sm:px-6" aria-label={t('navigation.explore')}>
          {links.map(link => <Link key={link.key} to={link.to} onClick={() => setMenuOpen(false)} className="rounded-lg px-3 py-2 text-sm hover:bg-accent">{t(`navigation.${link.key}`)}</Link>)}
          <Link to="/search" onClick={() => setMenuOpen(false)} className="rounded-lg px-3 py-2 text-sm hover:bg-accent">{t('navigation.search')}</Link>
          {!isAuthenticated && <Link to="/register" onClick={() => setMenuOpen(false)} className="rounded-lg px-3 py-2 text-sm font-semibold text-primary hover:bg-accent">{t('actions.createAccount')}</Link>}
        </nav>}
      </header>
      {/* Until their translation block is complete, inner pages remain Spanish. */}
      <main lang={translatedDiscovery || translatedPaths.has(pathname.toLowerCase().replace(/\/+$/, '') || '/') ? undefined : 'es'}>
        <Outlet />
      </main>
      {isHome ? <footer className="home-footer"><strong>{t('home.footer.title')}</strong><span>{t('home.footer.subtitle')}</span></footer>
        : <footer className="border-t px-4 py-8 text-center text-sm text-muted-foreground">{t('layout.footer')}</footer>}
    </div>
  )
}
