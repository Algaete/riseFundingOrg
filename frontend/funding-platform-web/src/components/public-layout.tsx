import { LayoutDashboard, LogIn } from 'lucide-react'
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
])

export function PublicLayout() {
  const { t } = useTranslation()
  const { pathname } = useLocation()
  const auth = useAuth()
  const isAuthenticated = auth.status === 'authenticated' && auth.session !== null
  const workspaceUrl = auth.session?.user.roles.some(role => role === 'Admin' || role === 'SuperAdmin')
    ? '/admin'
    : '/dashboard'

  return (
    <div className="min-h-screen">
      <header className="sticky top-0 z-20 border-b bg-background/90 backdrop-blur">
        <div className="mx-auto flex h-16 max-w-7xl items-center justify-between gap-3 px-4 sm:px-6">
          <div className="hidden xl:block">
            <BrandMark />
          </div>
          <div className="xl:hidden">
            <BrandMark compact />
          </div>
          <nav className="hidden items-center gap-1 lg:flex" aria-label={t('navigation.main')}>
            <Button variant="ghost" asChild>
              <Link to="/funding">{t('navigation.opportunities')}</Link>
            </Button>
            <Button variant="ghost" asChild>
              <Link to="/marketplace">{t('navigation.projects')}</Link>
            </Button>
            <Button variant="ghost" asChild>
              <Link to="/pricing">{t('navigation.plans')}</Link>
            </Button>
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
      </header>
      {/* Until their translation block is complete, inner pages remain Spanish. */}
      <main lang={translatedPaths.has(pathname.toLowerCase().replace(/\/+$/, '') || '/') ? undefined : 'es'}>
        <Outlet />
      </main>
      <footer className="border-t px-4 py-8 text-center text-sm text-muted-foreground">
        {t('layout.footer')}
      </footer>
    </div>
  )
}
