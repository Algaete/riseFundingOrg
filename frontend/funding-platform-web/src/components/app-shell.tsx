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
import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'

import { BrandMark } from '@/components/brand-mark'
import { ThemeToggle } from '@/components/theme/theme-toggle'
import { Button } from '@/components/ui/button'
import { authApi } from '@/features/auth/auth-api'
import { clearAuthSession } from '@/features/auth/auth-session'
import { useAuth } from '@/features/auth/use-auth'
import { cn } from '@/utils/cn'

interface NavigationItem {
  label: string
  to: string
  icon: LucideIcon
}

const memberNavigation: NavigationItem[] = [
  { label: 'Resumen', to: '/dashboard', icon: LayoutDashboard },
  { label: 'Concursos disponibles', to: '/opportunities', icon: Radar },
  { label: 'Compatibilidad', to: '/matching', icon: Gauge },
  { label: 'Favoritos', to: '/favorites', icon: Heart },
  { label: 'Postulaciones', to: '/applications', icon: ClipboardList },
  { label: 'Calendario', to: '/calendar', icon: CalendarDays },
  { label: 'Alertas', to: '/alerts', icon: Bell },
  { label: 'Conexiones', to: '/network', icon: Users },
  { label: 'Organización', to: '/organization/profile', icon: Building2 },
  { label: 'Proyectos', to: '/projects', icon: Target },
]

const adminNavigation: NavigationItem[] = [
  { label: 'Resumen', to: '/admin', icon: ShieldCheck },
  { label: 'Revisión de proyectos', to: '/admin/projects', icon: Target },
  { label: 'Fondos', to: '/admin/funding', icon: WalletCards },
  { label: 'Financiadores', to: '/admin/funders', icon: Building2 },
  { label: 'Importaciones', to: '/admin/imports', icon: Upload },
  { label: 'Fuentes', to: '/admin/sources', icon: Radar },
  { label: 'Usuarios', to: '/admin/users', icon: Users },
  { label: 'Organizaciones', to: '/admin/organizations', icon: Building2 },
  { label: 'Suscripciones', to: '/admin/subscriptions', icon: ClipboardList },
  { label: 'Errores', to: '/admin/errors', icon: Bell },
]

function NavigationLink({ item }: { item: NavigationItem }) {
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
      <span>{item.label}</span>
    </NavLink>
  )
}

export function AppShell({ mode = 'member' }: { mode?: 'member' | 'admin' }) {
  const navigation = mode === 'admin' ? adminNavigation : memberNavigation
  const auth = useAuth()
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
          aria-label={mode === 'admin' ? 'Administración' : 'Aplicación'}
        >
          {navigation.map((item) => (
            <NavigationLink item={item} key={item.to} />
          ))}
        </nav>
        <div className="border-t p-3">
          <NavigationLink
            item={{
              label: mode === 'admin' ? 'Volver a la plataforma' : 'Mi cuenta',
              to: mode === 'admin' ? '/dashboard' : '/account',
              icon: mode === 'admin' ? LayoutDashboard : CircleUserRound,
            }}
          />
          {mode === 'member' && (
            <NavigationLink
              item={{ label: 'Suscripción', to: '/subscription', icon: Settings }}
            />
          )}
        </div>
      </aside>

      <div className="md:pl-64">
        <header className="sticky top-0 z-10 flex h-16 items-center justify-between border-b bg-background/90 px-4 backdrop-blur sm:px-6">
          <div className="md:hidden">
            <BrandMark compact />
          </div>
          <p className="hidden text-sm text-muted-foreground md:block">
            {mode === 'admin' ? 'Consola administrativa' : 'Espacio de organización'}
          </p>
          <div className="flex items-center gap-2">
            <span className="hidden text-sm font-medium sm:inline">
              {auth.session?.user.displayName}
            </span>
            <ThemeToggle />
            <Button
              type="button"
              variant="ghost"
              size="icon"
              aria-label="Cerrar sesión"
              onClick={() => void logout()}
            >
              <LogOut className="size-4" aria-hidden="true" />
            </Button>
          </div>
        </header>

        <nav
          className="flex gap-1 overflow-x-auto border-b bg-card p-2 md:hidden"
          aria-label="Navegación móvil"
        >
          {navigation.map((item) => (
            <NavigationLink item={item} key={item.to} />
          ))}
        </nav>

        <main className="mx-auto w-full max-w-7xl p-4 sm:p-6 lg:p-8">
          <Outlet />
        </main>
      </div>
    </div>
  )
}
