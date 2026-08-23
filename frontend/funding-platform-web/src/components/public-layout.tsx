import { LayoutDashboard, LogIn } from 'lucide-react'
import { Link, Outlet } from 'react-router-dom'
import { useTranslation } from 'react-i18next'

import { BrandMark } from '@/components/brand-mark'
import { ThemeToggle } from '@/components/theme/theme-toggle'
import { Button } from '@/components/ui/button'
import { useAuth } from '@/features/auth/use-auth'

export function PublicLayout() {
  const { t } = useTranslation()
  const auth = useAuth()
  const isAuthenticated = auth.status === 'authenticated' && auth.session !== null
  const workspaceUrl = auth.session?.user.roles.some(role => role === 'Admin' || role === 'SuperAdmin')
    ? '/admin'
    : '/dashboard'

  return (
    <div className="min-h-screen">
      <header className="sticky top-0 z-20 border-b bg-background/90 backdrop-blur">
        <div className="mx-auto flex h-16 max-w-7xl items-center justify-between px-4 sm:px-6">
          <BrandMark />
          <nav className="hidden items-center gap-1 sm:flex" aria-label="Principal">
            <Button variant="ghost" asChild>
              <Link to="/funding">Oportunidades</Link>
            </Button>
            <Button variant="ghost" asChild>
              <Link to="/pricing">Planes</Link>
            </Button>
            <ThemeToggle />
            {isAuthenticated ? <Button asChild><Link to={workspaceUrl}><LayoutDashboard className="size-4" />Ir a mi espacio</Link></Button> : <>
              <Button variant="ghost" asChild><Link to="/login">{t('actions.signIn')}</Link></Button>
              <Button asChild><Link to="/register">{t('actions.createAccount')}</Link></Button>
            </>}
          </nav>
          <div className="flex items-center gap-1 sm:hidden">
            <ThemeToggle />
            <Button size="icon" variant="ghost" asChild>
              <Link to={isAuthenticated ? workspaceUrl : '/login'} aria-label={isAuthenticated ? 'Ir a mi espacio' : t('actions.signIn')}>
                {isAuthenticated ? <LayoutDashboard className="size-5" /> : <LogIn className="size-5" />}
              </Link>
            </Button>
          </div>
        </div>
      </header>
      <main>
        <Outlet />
      </main>
      <footer className="border-t px-4 py-8 text-center text-sm text-muted-foreground">
        FundingPlatform · Base técnica del MVP
      </footer>
    </div>
  )
}
