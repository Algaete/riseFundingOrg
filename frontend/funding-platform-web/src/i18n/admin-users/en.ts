import type { adminUsersEs } from './es'
import type { TranslationShape } from '@/i18n/resource-types'

export const adminUsersEn = {
  "intro": "View accounts, access status, global roles and security.",
  "count": "{{count}} accounts",
  "pendingActivation": "Pending activation",
  "pendingVerification": "Pending verification",
  "blocked": "Blocked",
  "disabled": "Disabled",
  "globalRole": "Global role",
  "search": "Search users",
  "searchPlaceholder": "Name or email",
  "loading": "Loading users…",
  "failed": "We could not load users",
  "loadError": "Users could not be loaded. Check your connection and try again.",
  "empty": "No users match these filters",
  "emptyHelp": "Clear the search or change the selected status and role.",
  "user": "User",
  "security": "Security",
  "verified": "Email verified",
  "unverified": "Email not verified",
  "noRole": "No global role",
  "mfa": "MFA enabled",
  "noMfa": "MFA not configured",
  "locale": "Locale {{locale}}",
  "lastLogin": "Last sign-in: {{date}}",
  "pagination": "User pagination",
  "table": "Accounts and security"
} satisfies TranslationShape<typeof adminUsersEs>

