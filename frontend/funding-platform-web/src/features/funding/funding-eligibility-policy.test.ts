import { describe, expect, it } from 'vitest'
import { eligibilityPolicySchema } from './funding-eligibility-policy'

const reviewed = {
  sourceUrl: 'https://example.org/criteria',
  projectBudgetLimit: { amount: 10000, currency: 'USD', inclusive: false },
  organizationAnnualBudgetLimit: null,
  requiredCategoryIds: [1], requiredBeneficiaryTypeIds: [1],
  manualRequirements: ['Volunteer led'],
}

describe('reviewed eligibility policy', () => {
  it('preserves unreviewed null and strict less-than boundaries', () => {
    expect(eligibilityPolicySchema.parse(null)).toBeNull()
    expect(eligibilityPolicySchema.parse(reviewed)?.projectBudgetLimit?.inclusive).toBe(false)
  })
  it.each([0, -1, Infinity, NaN, 1e15, 0.00001])('rejects invalid cap %s', amount => {
    expect(eligibilityPolicySchema.safeParse({ ...reviewed, projectBudgetLimit: { ...reviewed.projectBudgetLimit, amount } }).success).toBe(false)
  })
  it.each(['http://example.org', 'https://user:secret@example.org', 'javascript:alert(1)'])('rejects unsafe source %s', sourceUrl => {
    expect(eligibilityPolicySchema.safeParse({ ...reviewed, sourceUrl }).success).toBe(false)
  })
  it('rejects OTHER as mandatory evidence and blank manual requirements', () => {
    for (const bad of [{ requiredCategoryIds: [16] }, { requiredCategoryIds: [99] }, { requiredBeneficiaryTypeIds: [12] }, { manualRequirements: [' '] }]) {
      expect(eligibilityPolicySchema.safeParse({ ...reviewed, ...bad }).success).toBe(false)
    }
  })
  it('accepts a reviewed policy with no additional requirements', () => {
    expect(eligibilityPolicySchema.safeParse({ ...reviewed, projectBudgetLimit: null, requiredCategoryIds: [], requiredBeneficiaryTypeIds: [], manualRequirements: [] }).success).toBe(true)
  })
})
