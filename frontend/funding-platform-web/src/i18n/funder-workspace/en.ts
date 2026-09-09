import type { funderWorkspaceEs } from './es'
import type { TranslationShape } from '../resource-types'
export const funderWorkspaceEn = {
  title: 'Funder workspace',
  profiles: 'My funder profiles',
  opportunities: 'My opportunities',
  intro: 'Register a new profile and manage your opportunities. Each account can create up to three profiles; existing profiles cannot be claimed automatically. Changes are saved as drafts and require administrative review before publication.',
} as const satisfies TranslationShape<typeof funderWorkspaceEs>
