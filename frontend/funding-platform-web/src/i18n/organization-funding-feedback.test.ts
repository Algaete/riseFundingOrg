import { ApiError } from '@/api/http-client'
import { setInterfaceLanguage } from '@/i18n'
import { organizationFundingErrorMessage } from './organization-funding-feedback'

describe('organization funding request feedback', () => {
  it.each([
    [401, 'Tu sesión venció. Ingresa nuevamente.', 'Your session expired. Sign in again.'],
    [403, 'No tienes acceso a estas oportunidades en la organización.', 'You do not have access to these opportunities in this organization.'],
    [404, 'La oportunidad no existe o ya no está publicada.', 'The opportunity does not exist or is no longer published.'],
    [410, 'La oportunidad no existe o ya no está publicada.', 'The opportunity does not exist or is no longer published.'],
    [400, 'Revisa los filtros e intenta nuevamente.', 'Check the filters and try again.'],
    [422, 'Revisa los filtros e intenta nuevamente.', 'Check the filters and try again.'],
    [429, 'Se realizaron demasiadas consultas. Espera unos minutos e intenta nuevamente.', 'Too many requests. Wait a few minutes and try again.'],
    [503, 'El servicio no está disponible en este momento. Intenta nuevamente más tarde.', 'The service is unavailable right now. Try again later.'],
  ])('maps HTTP %s in ES/EN without exposing diagnostic content', async (status, spanish, english) => {
    const error = new ApiError({ status: Number(status), title: 'Diagnostic', detail: 'Internal detail', errors: { catalog: ['Internal rule'] } }, new Response(null, { status: Number(status) }))
    expect(organizationFundingErrorMessage(error, 'organizationFunding.loadHelp')).toBe(spanish)
    await setInterfaceLanguage('en')
    expect(organizationFundingErrorMessage(error, 'organizationFunding.loadHelp')).toBe(english)
  })

  it('uses translated fallbacks for unexpected errors', async () => {
    expect(organizationFundingErrorMessage(new Error('Internal'), 'organizationFunding.loadHelp')).toBe('Comprueba la conexión e intenta nuevamente.')
    await setInterfaceLanguage('en')
    expect(organizationFundingErrorMessage(undefined, 'organizationFunding.notAvailable')).toBe('The opportunity does not exist or is no longer published.')
  })
})
