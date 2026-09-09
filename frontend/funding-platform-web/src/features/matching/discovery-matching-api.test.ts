import { discoveryMatchingApi, validDiscoveryInput, type DiscoveryRequest } from './discovery-matching-api'
import { apiClient } from '@/api/http-client'

describe('ecosystem matching', () => {
  const request: DiscoveryRequest = { sourceKind: 3, sourceId: 'funder', targetKind: 1, page: 1, pageSize: 20 }
  afterEach(() => vi.restoreAllMocks())
  it.each([
    [{ minimumAmount: -1 }, false], [{ minimumAmount: 20, maximumAmount: 10, currency: 'USD' }, false],
    [{ minimumAmount: 0 }, false], [{ minimumAmount: NaN, currency: 'USD' }, false],
    [{ minimumAmount: 0, maximumAmount: 100, currency: 'USD' }, true], [{}, true],
  ])('validates explicit funding priorities %o', (criteria, valid) => {
    expect(validDiscoveryInput({ ...request, criteria })).toBe(valid)
  })
  it('does not cache searches or send consent commands', async () => {
    const post = vi.spyOn(apiClient, 'post').mockResolvedValue({ items: [] })
    const controller = new AbortController()
    await discoveryMatchingApi.search(request, controller.signal)
    expect(post).toHaveBeenCalledExactlyOnceWith('matching/discovery', request, { signal: controller.signal, cache: 'no-store' })
    expect(validDiscoveryInput({ ...request, sourceId: '' })).toBe(false)
  })
})
