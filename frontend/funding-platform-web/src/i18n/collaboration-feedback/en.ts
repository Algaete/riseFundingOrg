import type { collaborationFeedbackEs } from './es'
import type { TranslationShape } from '@/i18n/resource-types'

export const collaborationFeedbackEn = {
  "sessionExpired": "Your session expired. Sign in again.",
  "forbidden": "You do not have permission to perform this action in the organization.",
  "notFound": "The resource does not exist or is unavailable to your organization.",
  "rateLimited": "The request limit was reached. Try again later.",
  "unavailable": "The service is unavailable right now. Try again later.",
  "loadHelp": "Check your connection and try again.",
  "networkUncertain": "We could not confirm the operation. You can retry without duplicating it.",
  "matchingInvalid": "Review the project and organization profile before calculating again.",
  "networkInvalid": "Check the request details. The message must be between 10 and 500 characters and contain no contact details or links.",
  "conflict": "The data changed. Reload and review its state before retrying.",
  "matchingConflict": "The data or request changed. You can retry the calculation with a new key.",
  "precondition": "A request version or safety key is missing. Reload before retrying.",
  "alreadyExists": "An active connection with this organization already exists. Check the requests.",
  "networkDisabled": "Network visibility is disabled. An administrator must enable it before connecting.",
  "invalidTransition": "The request’s current state no longer allows that action. Reload to review it."
} as const satisfies TranslationShape<typeof collaborationFeedbackEs>
