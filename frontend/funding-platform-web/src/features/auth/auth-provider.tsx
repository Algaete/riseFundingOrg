import { useEffect, type ReactNode } from 'react'
import { Navigate, useLocation } from 'react-router-dom'
import { useTranslation } from 'react-i18next'

import { initializeAuthSession } from '@/features/auth/auth-session'
import { useAuth } from '@/features/auth/use-auth'
import { SlowLoadingNotice } from '@/components/slow-loading-notice'

export function AuthProvider({ children }: { children: ReactNode }) {
  useEffect(() => {
    if (window.location.pathname !== '/auth/external/callback') {
      void initializeAuthSession()
    }
  }, [])

  return children
}

export function ProtectedRoute({
  children,
  requireAdmin = false,
}: {
  children: ReactNode
  requireAdmin?: boolean
}) {
  const { t } = useTranslation()
  const auth = useAuth()
  const location = useLocation()

  if (auth.status === 'initializing') {
    return (
      <div className="grid min-h-screen place-items-center" role="status">
        <div className="max-w-lg px-6 text-center">
          <p className="text-sm text-muted-foreground">{t('status.checkingSession')}</p>
          <SlowLoadingNotice />
        </div>
      </div>
    )
  }

  if (!auth.session) {
    return <Navigate replace to="/login" state={{ from: location.pathname }} />
  }

  const isAdmin = auth.session.user.roles.some((role) =>
    role === 'Admin' || role === 'SuperAdmin',
  )
  if (requireAdmin && !isAdmin) {
    return <Navigate replace to="/dashboard" />
  }

  return children
}
