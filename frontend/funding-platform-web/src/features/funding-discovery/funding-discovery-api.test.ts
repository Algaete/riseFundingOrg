import { apiClient } from '@/api/http-client'
import { fundingDiscoveryApi } from './funding-discovery-api'

describe('funding discovery contracts', () => {
  afterEach(() => vi.restoreAllMocks())
  it('preserves explicit false filters and cancellation', async () => {
    const get = vi.spyOn(apiClient, 'get').mockResolvedValue({ items: [] })
    const signal = new AbortController().signal
    await fundingDiscoveryApi.search(new URLSearchParams({ requiresConsortium: 'false', languageId: '1' }), signal)
    expect(get).toHaveBeenCalledExactlyOnceWith('funding-discovery?requiresConsortium=false&languageId=1', { signal })
  })
  it.each([null, '"0102030405060708"'])('classification requires explicit version and stable command key %s', async tag => {
    const put = vi.spyOn(apiClient, 'put').mockResolvedValue({ eTag: tag })
    const data = { funderKind: 3, requiresConsortium: null, requiresInternationalPartner: false, evidenceUrl: 'https://official.example/fund' }
    await fundingDiscoveryApi.review('id', 4, data, tag, 'stable-review-key')
    expect(put).toHaveBeenCalledExactlyOnceWith('admin/funding-discovery/id', { contentVersion: 4, data }, { cache: 'no-store', headers: { ...(tag ? { 'If-Match': tag } : { 'If-None-Match': '*' }), 'Idempotency-Key': 'stable-review-key' } })
  })
})
