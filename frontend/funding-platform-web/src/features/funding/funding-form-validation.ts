import type { adminFundingEs } from '@/i18n/admin-funding/es'

// Only known form fields become labels or focus targets. Never traverse RHF's DOM refs.
export const fundingFormFieldLabels = {
  title: 'title', summary: 'summary', description: 'description', sponsorName: 'sponsor',
  sponsorUrl: 'sponsorWebsite', applicationUrl: 'applicationUrl', externalId: 'externalId',
  fundingSourceId: 'source', issuerCountryId: 'issuerCountry', fundingTypeId: 'fundingType',
  currency: 'currency', minimumAmount: 'minimum', maximumAmount: 'maximum', amountStatus: 'amountStatus',
  openDate: 'opening', closeDate: 'closingDate', closeAtUtc: 'closingUtc', deadlineTimeZoneId: 'closingZone',
  deadlineType: 'deadlineType', deadlinePrecision: 'deadlinePrecision', eligibilityDescription: 'eligibility',
  requirements: 'requirements', objectives: 'objectives', allowedActivities: 'allowed',
  excludedActivities: 'excluded', restrictions: 'restrictions', targetOrganizationsDescription: 'targetOrganizations',
  targetPopulationsDescription: 'targetPopulations', minimumOperatingYears: 'minimumYears',
  requiresLegalEntity: 'legalRequired', requiresPriorExperience: 'experienceRequired', requiresCofunding: 'cofunding',
  cofundingPercentage: 'cofundingPercentage', geographicScope: 'geographicScope', remoteApplication: 'remote',
  sourceUrl: 'sourceUrl', lastVerifiedAtUtc: 'verified', funders: 'associatedFunders', countryIds: 'countries',
  regionIds: 'regions', categoryIds: 'categories', beneficiaryTypeIds: 'beneficiaries', projectTypeIds: 'projectTypes',
} as const satisfies Record<string, keyof typeof adminFundingEs>

export type FundingFormField = keyof typeof fundingFormFieldLabels
export interface FundingFormError { field: FundingFormField; message: string }

export function fundingFormErrors(errors: object): FundingFormError[] {
  const result: FundingFormError[] = []
  function visit(value: unknown, field: FundingFormField, depth = 0) {
    if (!value || typeof value !== 'object' || depth > 4) return
    const node = value as Record<string, unknown>
    if (typeof node.message === 'string') result.push({ field, message: node.message })
    for (const [key, child] of Object.entries(node)) {
      if (!['ref', 'message', 'type', 'types'].includes(key)) visit(child, field, depth + 1)
    }
  }
  for (const field of Object.keys(fundingFormFieldLabels) as FundingFormField[]) {
    visit((errors as Record<string, unknown>)[field], field)
  }
  return result.filter((entry, index) => result.findIndex(other => other.field === entry.field && other.message === entry.message) === index)
}

export function focusFundingFormField(form: HTMLFormElement | null, field: FundingFormField) {
  const nativeField = form?.elements.namedItem(field)
  if (nativeField instanceof HTMLElement && !nativeField.hasAttribute('disabled')) {
    nativeField.focus()
    return
  }
  const group = form?.querySelector<HTMLElement>(`#funding-field-${field}`)
  const control = group?.querySelector<HTMLElement>('input:not(:disabled), select:not(:disabled), textarea:not(:disabled), button:not(:disabled)')
  ;(control ?? group)?.focus()
}
