import {
  Bell,
  Building2,
  CalendarDays,
  CircleUserRound,
  ClipboardList,
  Gauge,
  Heart,
  LayoutDashboard,
  LogOut,
  Radar,
  Settings,
  ShieldCheck,
  Target,
  Upload,
  Users,
  WalletCards,
  type LucideIcon,
} from 'lucide-react'
import { Link, NavLink, Outlet, useNavigate, useLocation } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'

import { BrandMark } from '@/components/brand-mark'
import { LanguageSelector } from '@/components/language-selector'
import { ThemeToggle } from '@/components/theme/theme-toggle'
import { Button } from '@/components/ui/button'
import { authApi } from '@/features/auth/auth-api'
import { clearAuthSession } from '@/features/auth/auth-session'
import { useAuth } from '@/features/auth/use-auth'
import { cn } from '@/utils/cn'
import type { es } from '@/i18n/es'

interface NavigationItem {
  label: keyof typeof es.translation.navigation
  to: string
  icon: LucideIcon
}

const memberNavigation: NavigationItem[] = [
  { label: 'overview', to: '/dashboard', icon: LayoutDashboard },
  { label: 'availableFunding', to: '/opportunities', icon: Radar },
  { label: 'recommended', to: '/matching', icon: Gauge },
  { label: 'favorites', to: '/favorites', icon: Heart },
  { label: 'applications', to: '/applications', icon: ClipboardList },
  { label: 'calendar', to: '/calendar', icon: CalendarDays },
  { label: 'alerts', to: '/alerts', icon: Bell },
  { label: 'connections', to: '/network', icon: Users },
  { label: 'profile', to: '/organization/profile', icon: Building2 },
  { label: 'projects', to: '/projects', icon: Target },
]

const adminNavigation: NavigationItem[] = [
  { label: 'overview', to: '/admin', icon: ShieldCheck },
  { label: 'projectReview', to: '/admin/projects', icon: Target },
  { label: 'funds', to: '/admin/funding', icon: WalletCards },
  { label: 'funders', to: '/admin/funders', icon: Building2 },
  { label: 'imports', to: '/admin/imports', icon: Upload },
  { label: 'sources', to: '/admin/sources', icon: Radar },
  { label: 'users', to: '/admin/users', icon: Users },
  { label: 'organizations', to: '/admin/organizations', icon: Building2 },
  { label: 'subscriptions', to: '/admin/subscriptions', icon: ClipboardList },
  { label: 'errors', to: '/admin/errors', icon: Bell },
]

function NavigationLink({ item }: { item: NavigationItem }) {
  const { t } = useTranslation()
  const Icon = item.icon
  return (
    <NavLink
      to={item.to}
      end={item.to === '/admin'}
      className={({ isActive }) =>
        cn(
          'flex shrink-0 items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium text-muted-foreground transition-colors hover:bg-muted hover:text-foreground',
          isActive && 'bg-accent text-accent-foreground',
        )
      }
    >
      <Icon className="size-4" aria-hidden="true" />
      <span>{t(`navigation.${item.label}`)}</span>
    </NavLink>
  )
}

export function AppShell({ mode = 'member' }: { mode?: 'member' | 'admin' }) {
  const { t } = useTranslation()
  const { pathname } = useLocation()
  const translatedContent = /^\/(?:dashboard|account|onboarding|organization\/profile|projects(?:\/[^/]+)?|opportunities(?:\/[^/]+)?|favorites|matching|network)\/?$/i.test(pathname)
  const navigation = mode === 'admin' ? adminNavigation : memberNavigation
  const auth = useAuth()
  const isPlatformAdministrator = auth.session?.user.roles.some(
    role => role === 'Admin' || role === 'SuperAdmin',
  ) ?? false
  const navigate = useNavigate()
  const queryClient = useQueryClient()

  async function logout() {
    let serverLogoutIncomplete = false
    try {
      await authApi.logout()
    } catch {
      serverLogoutIncomplete = true
      window.sessionStorage.setItem('funding-platform-logout-incomplete', 'true')
    } finally {
      await queryClient.cancelQueries()
      queryClient.clear()
      void navigate(serverLogoutIncomplete ? '/login?logout=incomplete' : '/login', { replace: true })
      clearAuthSession()
    }
  }

  return (
    <div className="min-h-screen bg-muted/35">
      <aside className="fixed inset-y-0 left-0 z-20 hidden w-64 flex-col border-r bg-card md:flex">
        <div className="flex h-16 items-center border-b px-5">
          <BrandMark />
        </div>
        <nav
          className="flex flex-1 flex-col gap-1 overflow-y-auto p-3"
          aria-label={t(mode === 'admin' ? 'navigation.administration' : 'navigation.application')}
        >
          {navigation.map((item) => (
            <NavigationLink item={item} key={item.to} />
          ))}
        </nav>
        <div className="border-t p-3">
          <NavigationLink
            item={{
              label: mode === 'admin' ? 'backToPlatform' : 'account',
              to: mode === 'admin' ? '/dashboard' : '/account',
              icon: mode === 'admin' ? LayoutDashboard : CircleUserRound,
            }}
          />
          {mode === 'member' && (
            <NavigationLink
              item={{ label: 'subscription', to: '/subscription', icon: Settings }}
            />
          )}
        </div>
      </aside>

      <div className="md:pl-64">
        <header className="sticky top-0 z-10 flex h-16 items-center justify-between border-b bg-background/90 px-4 backdrop-blur sm:px-6">
          <div className="md:hidden">
            <BrandMark compact />
          </div>
          <p className="hidden text-sm text-muted-foreground xl:block">
            {t(mode === 'admin' ? 'layout.adminWorkspace' : 'layout.organizationWorkspace')}
          </p>
          <div className="ml-auto flex items-center gap-2">
            {mode === 'member' && isPlatformAdministrator && <Button asChild size="sm" variant="outline" className="hidden sm:inline-flex">
              <Link aria-label={t('actions.goToAdminPanel')} to="/admin"><ShieldCheck className="size-4" /><span className="hidden sm:inline">{t('actions.adminPanel')}</span></Link>
            </Button>}
            <span className="hidden max-w-40 truncate text-sm font-medium lg:inline">
              {auth.session?.user.displayName}
            </span>
            <LanguageSelector />
            <ThemeToggle />
            <Button
              type="button"
              variant="ghost"
              size="icon"
              aria-label={t('actions.signOut')}
              onClick={() => void logout()}
            >
              <LogOut className="size-4" aria-hidden="true" />
            </Button>
          </div>
        </header>

        <nav
          className="flex gap-1 overflow-x-auto border-b bg-card p-2 md:hidden"
          aria-label={t('navigation.mobile')}
        >
          {mode === 'member' && isPlatformAdministrator && (
            <div className="shrink-0 sm:hidden">
              <NavigationLink item={{ label: 'administration', to: '/admin', icon: ShieldCheck }} />
            </div>
          )}
          {navigation.map((item) => (
            <NavigationLink item={item} key={item.to} />
          ))}
        </nav>

        {/* Navigation is bilingual; workspace page translations follow in separate blocks. */}
        <main lang={translatedContent ? undefined : 'es'} className="mx-auto w-full max-w-7xl p-4 sm:p-6 lg:p-8">
          <Outlet />
        </main>
      </div>
    </div>
  )
}
