import type { InvitationInput, ProfessionalData } from './collaboration-api'

export const blankProfessional: ProfessionalData = {
  displayName: '', headline: '', biography: null, countryId: null, skills: [], languageIds: [],
  categoryIds: [], isDiscoverable: false, allowsInvitations: false,
}
export function splitSkills(value: string) { return value.split(/[,\n]/).map(item => item.trim()).filter(Boolean) }
export function profileIssue(data: ProfessionalData): 'profileRequired' | 'profileLimits' | 'consentRequired' | null {
  if (data.displayName.trim().length < 2 || data.headline.trim().length < 2) return 'profileRequired'
  if (data.displayName.trim().length > 120 || data.headline.trim().length > 160
    || (data.biography?.trim().length ?? 0) > 2000 || data.skills.length > 20
    || data.skills.some(skill => skill.length < 2 || skill.length > 80)
    || data.languageIds.length > 20 || data.categoryIds.length > 30) return 'profileLimits'
  if (data.allowsInvitations && !data.isDiscoverable) return 'consentRequired'
  return null
}
export function consortiumIssue(name: string, summary: string): 'consortiumLimits' | null {
  return name.trim().length < 2 || name.trim().length > 160 || summary.trim().length > 1000 ? 'consortiumLimits' : null
}
export function invitationIssue(data: InvitationInput): 'invitationRequired' | 'messagePrivacy' | null {
  if (!data.targetId || data.contribution.trim().length < 2 || data.contribution.trim().length > 160
    || data.message.trim().length < 10 || data.message.trim().length > 500) return 'invitationRequired'
  return /@|https?:|www\.|\d{8}/i.test(data.message) ? 'messagePrivacy' : null
}

