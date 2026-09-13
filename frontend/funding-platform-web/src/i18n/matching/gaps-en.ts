import type { TranslationShape } from '@/i18n/resource-types'
import type { matchingGapsEs } from './gaps-es'

import { partnerGeographyEn } from '../partner-geography/en'

export const matchingGapsEn = {
  geography: partnerGeographyEn,
  title: 'How to address requirements',
  intro: 'Explore potential partners and professionals for this project and opportunity. Data is requested only when you press the button.',
  load: 'Find support for this opportunity', refresh: 'Refresh suggestions', loading: 'Finding support…',
  disclaimer: 'These are suggestions to explore, not verified gaps or fulfilled requirements. Check whether your team already covers them, each participant’s eligibility and their consent. No invitations are sent and the matching score does not change.',
  hardGaps: 'This calculation has unmet exclusion conditions. Adding a partner does not automatically fix eligible country, entity type, experience or other requirements for the applicant organization.',
  historical: 'The displayed calculation is historical. These suggestions use current data; recalculate matching to review current compatibility.',
  evaluated: 'Checked: {{date}} · Current opportunity version: {{version}}',
  unreviewed: 'This opportunity has no current editorial classification of collaboration requirements. We do not infer these requirements from text; we can only guide you on needs declared by the project.',
  evidence: 'Review the requirements source',
  empty: 'No reviewed collaboration requirements or declared needs trigger suggestions. This does not mean the project meets all the terms.',
  unavailable: 'The project or opportunity is no longer available to this account. Check your permissions and whether the opportunity is still published.',
  limit: 'The query limit has been reached. Try again later.',
  error: 'We could not retrieve support suggestions. Retry using Refresh suggestions.',
  need: { 'partner-geography': 'Explore partners by country or region', 'international-partner': 'Explore an international partner', consortium: 'Review or form a consortium', partners: 'Explore partners for the project', professionals: 'Explore professional support' },
  origin: { funding: 'Source: reviewed opportunity requirement', project: 'Source: need declared by the project' },
  help: {
    'partner-geography': 'This condition applies if you add a partner organization; by itself it does not mean you must add another partner.',
    'international-partner': 'We look for organizations headquartered in another country with shared impact areas. The opportunity may require specific countries: check the terms; a different country does not mean an eligible partner.',
    consortium: 'These organizations share impact areas with your project. Review your existing team and confirm the opportunity’s composition rules before inviting anyone.',
    partners: 'Selection is based on shared impact areas; it does not certify that the organization provides the described type of partnership.',
    professionals: 'We compare words in declared needs with profile skills. Confirm experience, availability, conditions and consent.',
  },
  state: { 'geography-needs-review': 'The opportunity’s country or region selection is no longer valid. Request a new editorial review before looking for organizations.', 'missing-home-country': 'Your organization’s headquarters country is missing, so we cannot identify international candidates.', 'no-evidence': 'No candidates with sufficient evidence were found in the profiles examined. Review or complete your project’s impact areas and needs; no candidates are invented.' },
  sharedAreas_one: 'Shares {{count}} impact area with the project.', sharedAreas_other: 'Shares {{count}} impact areas with the project.',
  sharedSkills: 'Matching words in declared skills: {{skills}}.',
  foreignCountry: 'Headquartered in a different country from your organization.',
  considerProfessional: 'Consider for a consortium', viewOrganization: 'View organization',
  corpus: 'Profiles examined: {{count}} of {{total}} available.',
  truncated: 'Limited to the 200 most recently updated profiles. These are up to 3 suggestions per need within that sample, not the entire directory.',
  editProject: 'Review project needs', reviewTeam: 'Review my consortia',
} satisfies TranslationShape<typeof matchingGapsEs>
