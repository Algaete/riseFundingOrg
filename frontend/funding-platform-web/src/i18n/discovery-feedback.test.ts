import { ApiError } from '@/api/http-client'
import { setInterfaceLanguage } from '@/i18n'
import { discoveryErrorMessage } from './discovery-feedback'

describe('public discovery errors', () => {
  it.each([
    [401, 'The requested information is not publicly available.'],
    [403, 'The requested information is not publicly available.'],
    [404, 'The requested information is not publicly available.'],
    [410, 'The requested information is not publicly available.'],
    [429, 'Too many requests. Wait a few minutes and try again.'],
    [400, 'Check the search filters and try again.'],
    [422, 'Check the search filters and try again.'],
    [503, 'The service is unavailable right now. Try again later.'],
  ])('uses stable HTTP semantics for %s without exposing diagnostics', async (status, message) => {
    await setInterfaceLanguage('en')
    const error = new ApiError({ title: 'Internal detail', detail: 'private diagnostics', status, errors: { query: ['arbitrary server text'] } }, new Response(null, { status }))
    expect(discoveryErrorMessage(error, 'fundingCatalog.loadHelp')).toBe(message)
    await setInterfaceLanguage('es')
    expect(discoveryErrorMessage(error, 'marketplace.loadHelp')).not.toMatch(/private|arbitrary|Internal/)
  })

  it('localizes unknown errors with a safe module fallback', async () => {
    const error = new Error('untrusted details')
    expect(discoveryErrorMessage(error, 'marketplace.loadHelp')).toBe('Comprueba la conexión e intenta nuevamente.')
    await setInterfaceLanguage('en')
    expect(discoveryErrorMessage(error, 'marketplace.loadHelp')).toBe('Check your connection and try again.')
  })
})
