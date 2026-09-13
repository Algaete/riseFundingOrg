import { describe, expect, it } from 'vitest'
import { mapQuery, mapReadPolicy, mapResultsUrl, readMapFilters } from './map-filters'

const first = '11111111-1111-1111-1111-111111111111'
const second = '22222222-2222-2222-2222-222222222222'
describe('advanced map filters', () => {
  it('preserves all filters and public selections across pagination without private context', () => {
    const input = new URLSearchParams(`q=agua&organizationTypeId=2&minimumFundingGap=0&maximumFundingGap=100.2500&currency=USD&seekingPartners=true&seekingProfessionals=true&seekingConsortium=true&seekingFunding=true&projectIds=${first}&projectIds=${second}&page=2&sourceId=private&token=private`)
    const result = readMapFilters(input)
    expect(result.valid).toBe(true)
    expect(result.query.get('minimumFundingGap')).toBe('0')
    expect(result.query.get('maximumFundingGap')).toBe('100.2500')
    expect(result.query.get('organizationTypeId')).toBe('2')
    expect(result.query.get('page')).toBe('2')
    expect(result.query.getAll('projectIds')).toEqual([first, second])
    expect(result.query.get('seekingConsortium')).toBe('true')
    expect(result.query.has('sourceId')).toBe(false)
    expect(result.query.has('token')).toBe(false)
  })
  it.each([
    'minimumFundingGap=10', 'maximumFundingGap=0', 'currency=usd', 'currency=USDX',
    'minimumFundingGap=-1&currency=USD', 'minimumFundingGap=1e3&currency=USD',
    'minimumFundingGap=NaN&currency=USD', 'minimumFundingGap=1.00001&currency=USD',
    'maximumFundingGap=1000000000000&currency=USD', 'minimumFundingGap=11&maximumFundingGap=10&currency=USD',
    'minimumFundingGap=999999999998.0002&maximumFundingGap=999999999998.0001&currency=USD',
    'organizationTypeId=0', 'organizationTypeId=32768', 'seekingPartners=yes',
    `projectIds=${first}&projectIds=${first}`, 'projectIds=not-a-guid', 'projectIds=',
    'projectIds=00000000-0000-0000-0000-000000000000', 'countryId=152&countryId=840',
    'q=uno&q=dos', 'page=0', 'page=2.5', 'seekingFunding=true&seekingFunding=false',
  ])('rejects malformed filters instead of silently broadening results: %s', input => {
    expect(readMapFilters(new URLSearchParams(input)).valid).toBe(false)
  })
  it('compares full decimal precision and keeps explicit zero', () => {
    expect(readMapFilters(new URLSearchParams('minimumFundingGap=999999999998.0001&maximumFundingGap=999999999998.0002&currency=USD')).valid).toBe(true)
    expect(readMapFilters(new URLSearchParams('maximumFundingGap=0&currency=USD')).valid).toBe(true)
    expect(mapQuery(new URLSearchParams('seekingPartners=false')).has('seekingPartners')).toBe(false)
  })
  it('caps public result selections and never opens an empty selection as all projects', () => {
    expect(mapResultsUrl([])).toBeNull()
    expect(mapResultsUrl(['private-source'])).toBeNull()
    expect(mapResultsUrl([first, first])).toBeNull()
    const ids = Array.from({ length: 50 }, (_, n) => `${String(n + 1).padStart(8, '0')}-1111-1111-1111-111111111111`)
    const url = mapResultsUrl(ids)!
    expect(readMapFilters(new URL(url, 'https://example.invalid').searchParams).valid).toBe(true)
    expect(mapResultsUrl([...ids, second])).toBeNull()
    expect(readMapFilters(new URLSearchParams([...ids, second].map(id => ['projectIds', id]))).valid).toBe(false)
  })
  it('does not refetch on focus or reconnection, poll or retry in the background', () => {
    expect(mapReadPolicy).toMatchObject({ retry: false, refetchOnWindowFocus: false, refetchOnReconnect: false, refetchOnMount: true, staleTime: 60_000 })
    expect(mapReadPolicy).not.toHaveProperty('refetchInterval')
  })
})
