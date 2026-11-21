import { z } from 'zod'

const budgetLimit = z.object({
  amount: z.number().positive().lt(1e15).refine(value => Number(value.toFixed(4)) === value),
  currency: z.string().regex(/^[A-Z]{3}$/),
  inclusive: z.boolean(),
})

export const eligibilityPolicySchema = z.object({
  sourceUrl: z.string().max(2048).url().refine(value => {
    try { const url = new URL(value); return url.protocol === 'https:' && !url.username && !url.password }
    catch { return false }
  }),
  projectBudgetLimit: budgetLimit.nullable(),
  organizationAnnualBudgetLimit: budgetLimit.nullable(),
  requiredCategoryIds: z.array(z.number().int().positive().max(15)).max(15),
  requiredBeneficiaryTypeIds: z.array(z.number().int().positive().max(11)).max(11),
  manualRequirements: z.array(z.string().trim().min(1).max(500)).max(12),
}).nullable()

export type FundingEligibilityPolicy = z.infer<typeof eligibilityPolicySchema>
