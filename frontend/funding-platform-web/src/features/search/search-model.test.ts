import { readSearchCriteria, searchRequest, searchSources, unifiedSearchUrl, type SearchCriteria } from './search-model'

const criteria: SearchCriteria = { scope: 'all', q: 'agua & salud', countryId: '152', categoryId: '4', page: 1 }

describe('unified search URL and endpoint contracts', () => {
  it('does not submit the bare route and round-trips shared filters', () => {
    expect(readSearchCriteria(new URLSearchParams())).toMatchObject({ valid: true, submitted: false })
    const url = unifiedSearchUrl('projects', ' agua & salud ', '152', '4', 2)
    expect(url).toBe('/search?scope=projects&q=agua+%26+salud&countryId=152&categoryId=4&page=2')
    expect(readSearchCriteria(new URLSearchParams(url.split('?')[1]))).toEqual({
      valid: true, submitted: true, criteria: { ...criteria, scope: 'projects', page: 2 },
    })
  })

  it.each(['scope=admin', 'q=' + 'x'.repeat(201), 'q=%00a', 'q=a%7F', 'q=a%0Ab',
    'countryId=-1', 'countryId=0', 'countryId=32768', 'countryId=01', 'countryId=1.5',
    'categoryId=2147483648', 'categoryId=Infinity', 'page=0', 'page=-1', 'page=1.5', 'page=01',
    'scope=projects&page=10001', 'scope=all&page=2', 'q=a&q=b', 'scope=all&scope=projects',
    'countryId=1&countryId=2', 'categoryId=1&categoryId=2', 'page=1&page=1'])('rejects malformed URL: %s', query => {
    expect(readSearchCriteria(new URLSearchParams(query)).valid).toBe(false)
  })

  it.each(searchSources)('maps %s to its existing read-only API with bounded previews', source => {
    const url = new URL(searchRequest(source, criteria, 'org/member'), 'https://example.invalid/')
    expect(url.pathname).toBe(source === 'projects' ? '/marketplace/projects' : source === 'funding' ? '/funding-discovery'
      : source === 'professionals' ? '/professionals' : '/organizations/org%2Fmember/network/directory')
    expect(url.searchParams.get(source === 'funding' ? 'query' : 'q')).toBe(criteria.q)
    expect(url.searchParams.get(source === 'projects' || source === 'organizations' ? 'countryIds' : 'countryId')).toBe('152')
    expect(url.searchParams.get(source === 'projects' || source === 'organizations' ? 'categoryIds' : 'categoryId')).toBe('4')
    expect(url.searchParams.get('pageSize')).toBe('6')
    expect(url.searchParams.get('page')).toBe('1')
    if (source === 'projects') expect(url.searchParams.get('sort')).toBe('newest')
    if (source === 'funding') expect(url.searchParams.get('onlyOpen')).toBe('true')
    const expanded = new URL(searchRequest(source, { ...criteria, scope: source, page: 3 }, 'member'), 'https://example.invalid/')
    expect(expanded.searchParams.get('pageSize')).toBe('20')
    expect(expanded.searchParams.get('page')).toBe('3')
  })

  it('refuses invalid direct requests and missing membership context', () => {
    for (const overrides of [{ q: '\n' }, { q: 'x'.repeat(201) }, { countryId: '-1' }, { page: 2 }, { page: NaN }]) {
      expect(() => searchRequest('projects', { ...criteria, ...overrides })).toThrow('Invalid search criteria')
    }
    expect(() => searchRequest('projects', { ...criteria, scope: 'funding' })).toThrow()
    expect(() => searchRequest('organizations', criteria)).toThrow('An organization membership is required')
  })
})
