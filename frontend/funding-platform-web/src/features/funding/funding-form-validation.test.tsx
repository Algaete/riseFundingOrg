import { act, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { vi } from 'vitest'
import { setInterfaceLanguage } from '@/i18n'
import { fundingFormErrors } from './funding-form-validation'
import { FundingFormValidationSummary } from './funding-form-validation-summary'

describe('resumen de errores del editor de fondos', () => {
  it('recoge errores anidados y de arrays sin recorrer refs ni duplicar mensajes', () => {
    const ref: Record<string, unknown> = {}
    ref.ref = ref
    const funders = Object.assign([{ funderId: { type: 'invalid_string', message: 'Invalid uuid', ref } }], {
      root: { message: 'editorialValidation.primary' },
    })
    expect(fundingFormErrors({
      funders,
      categoryIds: [{ message: 'editorialValidation.positiveId' }, { message: 'editorialValidation.positiveId' }],
      unknown: { message: 'unexpected field' },
    })).toEqual([
      { field: 'funders', message: 'Invalid uuid' },
      { field: 'funders', message: 'editorialValidation.primary' },
      { field: 'categoryIds', message: 'editorialValidation.positiveId' },
    ])
  })

  it('no muestra un resumen vacío', () => {
    render(<FundingFormValidationSummary errors={[]} onSelectField={vi.fn()} summaryRef={null} />)
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })

  it('traduce el resumen y conserva el destino sin exponer diagnósticos desconocidos', async () => {
    const select = vi.fn()
    render(<FundingFormValidationSummary errors={[{ field: 'funders', message: 'PRIVATE DIAGNOSTIC' }]} onSelectField={select} summaryRef={null} />)
    expect(screen.getByRole('alert')).toHaveAccessibleName('No se guardaron los cambios. Revisa estos campos:')
    expect(screen.getByRole('alert')).not.toHaveTextContent('PRIVATE DIAGNOSTIC')
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('alert')).toHaveAccessibleName('Changes were not saved. Review these fields:')
    await userEvent.setup().click(screen.getByRole('button', { name: /Associated funders/ }))
    expect(select).toHaveBeenCalledExactlyOnceWith('funders')
  })
})
