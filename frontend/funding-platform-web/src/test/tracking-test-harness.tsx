import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { act, render } from '@testing-library/react'
import type { ReactElement } from 'react'
import { createMemoryRouter, RouterProvider } from 'react-router-dom'
import { ApiError } from '@/api/http-client'
import { setInterfaceLanguage } from '@/i18n'

export function trackingPage(element: ReactElement, entry: string) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false, staleTime: Infinity }, mutations: { retry: false } } })
  const router = createMemoryRouter([{ path: '*', element }], { initialEntries: [entry] })
  const view = render(<QueryClientProvider client={client}><RouterProvider router={router} /></QueryClientProvider>)
  return { client, router, ...view }
}
export function language(value: 'es' | 'en') {
  return act(() => setInterfaceLanguage(value))
}
export function problem(status: number, code = 'unknown') {
  return new ApiError({ status, type: 'https://fundingplatform.local/problems/' + code, title: 'PRIVATE-DIAGNOSTIC', detail: 'PRIVATE-DIAGNOSTIC' }, new Response(null, { status }))
}
export function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (error: unknown) => void
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no })
  return { promise, resolve, reject }
}
