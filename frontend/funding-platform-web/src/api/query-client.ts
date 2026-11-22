import { QueryClient } from '@tanstack/react-query'
import { ApiError } from './http-client'

export function createAppQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 30_000,
        // The API already exhausted its bounded connection retries. Replaying
        // the whole request here would multiply the wait and load on recovery.
        retry: (failureCount, error) => error instanceof ApiError &&
          error.response.status === 503 &&
          error.problem.type === 'https://fundingplatform.local/problems/data-service-unavailable'
          ? false
          : failureCount < 1,
        refetchOnWindowFocus: false,
      },
      mutations: {
        retry: false,
      },
    },
  })
}

export const appQueryClient = createAppQueryClient()
