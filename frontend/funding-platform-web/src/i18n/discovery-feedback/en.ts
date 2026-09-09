import type { discoveryFeedbackEs } from './es'
import type { TranslationShape } from '@/i18n/resource-types'

export const discoveryFeedbackEn = {
  "notFound": "The requested information is not publicly available.",
  "rateLimited": "Too many requests. Wait a few minutes and try again.",
  "invalidFilters": "Check the search filters and try again.",
  "unavailable": "The service is unavailable right now. Try again later."
} as const satisfies TranslationShape<typeof discoveryFeedbackEs>
