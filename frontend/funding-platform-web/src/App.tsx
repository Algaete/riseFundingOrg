import { QueryClientProvider, type QueryClient } from '@tanstack/react-query'
import { Suspense } from 'react'
import { RouterProvider, type createBrowserRouter } from 'react-router-dom'
import { useTranslation } from 'react-i18next'

import { appQueryClient } from '@/api/query-client'
import { ThemeProvider } from '@/components/theme/theme-provider'
import { AuthProvider } from '@/features/auth/auth-provider'
import '@/i18n'
import { appRouter } from '@/router'

type DataRouter = ReturnType<typeof createBrowserRouter>

interface AppProps {
  router?: DataRouter
  queryClient?: QueryClient
}

function LoadingFallback() {
  const { t } = useTranslation()
  return <div className="grid min-h-screen place-items-center text-sm text-muted-foreground">{t('status.loading')}</div>
}

export function App({
  router = appRouter,
  queryClient = appQueryClient,
}: AppProps) {
  return (
    <QueryClientProvider client={queryClient}>
      <ThemeProvider>
        <AuthProvider>
          <Suspense fallback={<LoadingFallback />}>
            <RouterProvider router={router} />
          </Suspense>
        </AuthProvider>
      </ThemeProvider>
    </QueryClientProvider>
  )
}
