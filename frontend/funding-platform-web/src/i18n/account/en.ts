import type { accountEs } from './es'
import type { TranslationShape } from '@/i18n/resource-types'

export const accountEn = {
  "title": "My account",
  "description": "Security and sign-in methods.",
  "sso": "Single sign-on",
  "linked": "Your Microsoft account was linked successfully.",
  "alreadyLinked": "That Microsoft identity was already linked to this account.",
  "linkFailed": "We could not link Microsoft. Check whether you selected the correct personal or work account.",
  "prepareFailed": "We could not prepare account linking. Refresh your session and try again.",
  "activeAccount": "Active local account:",
  "help": "Microsoft will show its account chooser. Select the exact identity you want to link to the local account shown above; personal and work accounts with the same email address are different identities.",
  "preparing": "Preparing…",
  "linkMicrosoft": "Link Microsoft to {{email}}",
  "thisAccount": "this account",
  "disabled": "Microsoft SSO is prepared and awaiting configuration in Entra.",
  "providersLoading": "Checking sign-in methods…",
  "providersFailed": "We could not check whether Microsoft is enabled. Try again.",
  "retry": "Retry"
} as const satisfies TranslationShape<typeof accountEs>
