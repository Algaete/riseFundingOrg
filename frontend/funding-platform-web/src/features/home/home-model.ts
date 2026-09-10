import type { MarketplaceProjectItem } from '@/features/marketplace/marketplace-api'

export type HomeSearchScope = 'projects' | 'funding'
export function homeSearchUrl(scope: HomeSearchScope, query: string, country: string, category: string) {
  const params = new URLSearchParams()
  const term = query.trim().slice(0, 200)
  if (term) params.set(scope === 'projects' ? 'q' : 'query', term)
  for (const [key, value] of [['countryId', country], ['categoryId', category]]) {
    if (/^[1-9]\d*$/.test(value) && Number.isSafeInteger(Number(value))) params.set(key, value)
  }
  const path = scope === 'projects' ? '/marketplace' : '/funding/explore'
  return params.size ? `${path}?${params}` : path
}

export function publishedHomeProjects(items: MarketplaceProjectItem[]) {
  // Only consume the existing public projection; additionally reject explicit drafts.
  return items.filter(item => item.publicationStatus === undefined || item.publicationStatus === 2).slice(0, 3)
}

export function fundingProgress(project: Pick<MarketplaceProjectItem, 'budgetTotal' | 'confirmedFunding' | 'currency'>) {
  const { budgetTotal: budget, confirmedFunding: confirmed, currency } = project
  if (budget === null || confirmed === null || !Number.isFinite(budget) || !Number.isFinite(confirmed)
    || budget <= 0 || confirmed < 0 || !currency || !/^[A-Z]{3}$/.test(currency)) return null
  return Math.round(Math.min(1, confirmed / budget) * 100)
}
