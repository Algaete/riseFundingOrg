import type { MarketplaceProjectItem } from '@/features/marketplace/marketplace-api'
import { unifiedSearchUrl, type SearchScope } from '@/features/search/search-model'

export type HomeSearchScope = SearchScope
export function homeSearchUrl(scope: HomeSearchScope, query: string, country: string, category: string) {
  const id = (value: string, maximum: number) => /^[1-9]\d*$/.test(value) && Number(value) <= maximum ? value : ''
  return unifiedSearchUrl(scope, query, id(country, 32767), id(category, 2147483647))
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
