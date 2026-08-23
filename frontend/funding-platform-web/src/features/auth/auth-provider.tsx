import { useEffect, type ReactNode } from 'react'
import { Navigate, useLocation } from 'react-router-dom'

import { initializeAuthSession } from '@/features/auth/auth-session'
import { useAuth } from '@/features/auth/use-auth'

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
  const auth = useAuth()
  const location = useLocation()

  if (auth.status === 'initializing') {
    return (
      <div className="grid min-h-screen place-items-center" role="status">
        <p className="text-sm text-muted-foreground">Comprobando sesión…</p>
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
