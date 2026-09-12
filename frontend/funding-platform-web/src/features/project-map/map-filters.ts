const numericFilters = [
  ['countryId', 1, 32767], ['categoryId', 1, 2147483647], ['organizationTypeId', 1, 32767],
  ['projectStage', 0, 5], ['sustainableDevelopmentGoalId', 1, 17], ['projectStatus', 0, 6], ['page', 1, 10000],
] as const
export const mapNeeds = ['seekingFunding', 'seekingPartners', 'seekingProfessionals', 'seekingConsortium'] as const
const amounts = ['minimumFundingGap', 'maximumFundingGap'] as const
const guid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const validIds = (ids: string[]) => ids.length > 0 && ids.length <= 50 && ids.every(id => guid.test(id) && id !== '00000000-0000-0000-0000-000000000000') && new Set(ids.map(id => id.toLowerCase())).size === ids.length
function amountUnits(value: string): bigint | null {
  if (!/^(?:0|[1-9]\d{0,11})(?:\.\d{1,4})?$/.test(value)) return null
  const [whole, fraction = ''] = value.split('.')
  const units = BigInt(whole) * 10000n + BigInt(fraction.padEnd(4, '0'))
  return units <= 9999999999990000n ? units : null
}

/** Canonical, bounded URL for the public map. readMapFilters rejects invalid input before querying. */
export function mapQuery(search: URLSearchParams) {
  const query = new URLSearchParams()
  const q = search.get('q')?.trim().slice(0, 200)
  if (q) query.set('q', q)
  for (const [key, min, max] of numericFilters) {
    const raw = search.get(key)
    const value = Number(raw)
    if (raw !== null && raw !== '' && Number.isInteger(value) && value >= min && value <= max) query.set(key, String(value))
  }
  for (const key of amounts) { const value = search.get(key); if (value && amountUnits(value) !== null) query.set(key, value) }
  const currency = search.get('currency')
  if (currency && /^[A-Z]{3}$/.test(currency)) query.set('currency', currency)
  for (const key of mapNeeds) if (search.get(key) === 'true') query.set(key, 'true')
  const ids = search.getAll('projectIds')
  if (validIds(ids)) for (const id of ids) query.append('projectIds', id.toLowerCase())
  if (!query.has('page')) query.set('page', '1')
  query.set('pageSize', '100')
  return query
}

export function readMapFilters(search: URLSearchParams) {
  let valid = true
  const singleKeys = ['q', ...numericFilters.map(([key]) => key), ...amounts, 'currency', ...mapNeeds]
  if (singleKeys.some(key => search.getAll(key).length > 1)) valid = false
  if ((search.get('q')?.trim().length ?? 0) > 200) valid = false
  for (const [key, min, max] of numericFilters) {
    const raw = search.get(key)
    if (raw !== null && (!/^\d+$/.test(raw) || Number(raw) < min || Number(raw) > max)) valid = false
  }
  for (const key of amounts) if (search.has(key) && amountUnits(search.get(key)!) === null) valid = false
  const minimum = amountUnits(search.get('minimumFundingGap') ?? '')
  const maximum = amountUnits(search.get('maximumFundingGap') ?? '')
  if (minimum !== null && maximum !== null && minimum > maximum) valid = false
  if ((search.has('currency') || amounts.some(key => search.has(key))) && !/^[A-Z]{3}$/.test(search.get('currency') ?? '')) valid = false
  for (const key of mapNeeds) if (search.has(key) && !['true', 'false'].includes(search.get(key)!)) valid = false
  if (search.has('projectIds') && !validIds(search.getAll('projectIds'))) valid = false
  return { query: mapQuery(search), valid }
}

/** Only public result IDs: no private source identity, score, criteria or organization context in the URL. */
export function mapResultsUrl(ids: string[]) {
  if (!validIds(ids)) return null
  const query = new URLSearchParams()
  for (const id of ids) query.append('projectIds', id.toLowerCase())
  return `/marketplace/map?${query}`
}

// Returning to the map revalidates stale public data; no timer keeps SQL awake.
export const mapReadPolicy = { retry: false, refetchOnWindowFocus: false, refetchOnReconnect: false, refetchOnMount: true, staleTime: 60_000 } as const
