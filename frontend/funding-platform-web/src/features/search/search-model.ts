export const searchSources = ['projects', 'funding', 'organizations', 'professionals'] as const
export type SearchSource = typeof searchSources[number]
export type SearchScope = 'all' | SearchSource
export interface SearchCriteria { q: string; scope: SearchScope; countryId: string; categoryId: string; page: number }

const validId = (value: string, maximum: number) => value === ''
  || (/^[1-9]\d*$/.test(value) && Number(value) <= maximum)

function validCriteria(criteria: SearchCriteria) {
  return (criteria.scope === 'all' || searchSources.includes(criteria.scope))
    && criteria.q.length <= 200 && !Array.from(criteria.q).some(char => char.charCodeAt(0) < 32 || char.charCodeAt(0) === 127)
    && validId(criteria.countryId, 32767) && validId(criteria.categoryId, 2147483647)
    && Number.isInteger(criteria.page) && criteria.page >= 1 && criteria.page <= 10000
    && (criteria.scope !== 'all' || criteria.page === 1)
}

export function readSearchCriteria(params: URLSearchParams) {
  const scope = params.get('scope') ?? 'all'
  const q = params.get('q') ?? ''
  const countryId = params.get('countryId') ?? ''
  const categoryId = params.get('categoryId') ?? ''
  const page = params.get('page') ?? '1'
  const scopeValid = scope === 'all' || searchSources.includes(scope as SearchSource)
  const raw: SearchCriteria = { q, scope: scope as SearchScope, countryId, categoryId, page: Number(page) }
  const valid = validCriteria(raw) && /^[1-9]\d*$/.test(page)
    && ['q', 'scope', 'countryId', 'categoryId', 'page'].every(key => params.getAll(key).length <= 1)
  const criteria: SearchCriteria = { q: q.trim(), scope: scopeValid ? scope as SearchScope : 'all', countryId, categoryId, page: Number(page) }
  return { criteria, valid, submitted: ['q', 'scope', 'countryId', 'categoryId', 'page'].some(key => params.has(key)) }
}

export function unifiedSearchUrl(scope: SearchScope, q = '', countryId = '', categoryId = '', page = 1) {
  const params = new URLSearchParams({ scope })
  if (q.trim()) params.set('q', q.trim().slice(0, 200))
  if (countryId) params.set('countryId', countryId)
  if (categoryId) params.set('categoryId', categoryId)
  if (scope !== 'all' && page > 1) params.set('page', String(page))
  return `/search?${params}`
}

export function searchRequest(source: SearchSource, criteria: SearchCriteria, organizationId?: string) {
  if (!validCriteria(criteria) || !searchSources.includes(source)
    || (criteria.scope !== 'all' && criteria.scope !== source)) throw new Error('Invalid search criteria')
  const plural = source === 'projects' || source === 'organizations'
  const params = new URLSearchParams({ page: String(criteria.scope === 'all' ? 1 : criteria.page), pageSize: criteria.scope === 'all' ? '6' : '20' })
  if (criteria.q) params.set(source === 'funding' ? 'query' : 'q', criteria.q)
  if (criteria.countryId) params.set(plural ? 'countryIds' : 'countryId', criteria.countryId)
  if (criteria.categoryId) params.set(plural ? 'categoryIds' : 'categoryId', criteria.categoryId)
  if (source === 'projects') params.set('sort', 'newest')
  if (source === 'funding') params.set('onlyOpen', 'true')
  if (source === 'organizations' && !organizationId) throw new Error('An organization membership is required')
  const path = source === 'projects' ? 'marketplace/projects'
    : source === 'funding' ? 'funding-discovery'
    : source === 'professionals' ? 'professionals'
    : `organizations/${encodeURIComponent(organizationId!)}/network/directory`
  return `${path}?${params}`
}

export const searchQueryPolicy = { retry: false, refetchOnWindowFocus: false, refetchOnReconnect: false,
  staleTime: 0, gcTime: 0 } as const
