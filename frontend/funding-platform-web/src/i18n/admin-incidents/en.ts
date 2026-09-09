import type { adminIncidentsEs } from './es'
import type { TranslationShape } from '@/i18n/resource-types'

export const adminIncidentsEn = {
  "title": "Operational errors",
  "intro": "Sanitized view of ingestion, extraction, assisted processing and payment failures.",
  "import": "Import",
  "extraction": "Extraction",
  "semantic": "Semantic processing",
  "explanation": "Assisted explanation",
  "payment": "Payment",
  "loadError": "Operational incidents could not be retrieved.",
  "count": "{{count}} incidents",
  "search": "Search errors",
  "placeholder": "Code, message or source",
  "origin": "Origin",
  "retryablePlural": "Retryable",
  "permanentPlural": "Permanent",
  "loading": "Loading incidents…",
  "failed": "We could not load incidents",
  "empty": "No incidents match these filters",
  "emptyHelp": "This view only shows sanitized information, never payloads or credentials.",
  "permanent": "Permanent failure",
  "warning": "Warning",
  "noOrigin": "Origin not reported",
  "context": "Open context",
  "pagination": "Error pagination"
} satisfies TranslationShape<typeof adminIncidentsEs>
