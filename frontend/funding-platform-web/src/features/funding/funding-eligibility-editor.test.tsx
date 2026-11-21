import { useState } from 'react'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import i18n from '@/i18n'
import { FundingEligibilityEditor } from './funding-eligibility-editor'
import type { FundingEligibilityPolicy } from './funding-eligibility-policy'

it('permite registrar una revisión, un límite estricto y condiciones manuales sin usar Otro', async () => {
  await i18n.changeLanguage('es')
  let saved: FundingEligibilityPolicy = null
  function Editor() {
    const [value, setValue] = useState<FundingEligibilityPolicy>(null)
    return <FundingEligibilityEditor value={value} onChange={next => { saved = next; setValue(next) }}
      sourceUrl="https://example.org/bases" invalid={false}
      categories={[{ id: 1, name: 'Medio ambiente' }, { id: 16, name: 'Otro' }]}
      beneficiaries={[{ id: 1, name: 'Niñez' }, { id: 12, name: 'Otros beneficiarios' }]}
      currencies={[{ code: 'USD', name: 'Dólar estadounidense' }]} />
  }
  render(<Editor />)
  const user = userEvent.setup()
  await user.click(screen.getByLabelText('Revisé los requisitos adicionales en la fuente oficial'))
  expect(screen.getByLabelText('Fuente oficial de los requisitos')).toHaveValue('https://example.org/bases')
  expect(screen.queryByLabelText('Otro')).not.toBeInTheDocument()
  expect(screen.queryByLabelText('Otros beneficiarios')).not.toBeInTheDocument()
  const projectBudget = within(screen.getByRole('group', { name: 'Presupuesto total máximo del proyecto' }))
  await user.click(projectBudget.getByLabelText('Las bases establecen este límite'))
  await user.clear(projectBudget.getByLabelText('Límite presupuestario'))
  await user.type(projectBudget.getByLabelText('Límite presupuestario'), '10000')
  await user.click(screen.getByLabelText('Medio ambiente'))
  await user.type(screen.getByLabelText('Otros requisitos que deben revisarse (uno por línea)'), 'Equipo voluntario\nSin fondos previos')
  await user.tab()
  expect(saved).toMatchObject({ projectBudgetLimit: { amount: 10000, currency: 'USD', inclusive: false },
    requiredCategoryIds: [1], manualRequirements: ['Equipo voluntario', 'Sin fondos previos'] })
  await user.selectOptions(projectBudget.getByLabelText('Comparación'), 'inclusive')
  expect(saved).toMatchObject({ projectBudgetLimit: { inclusive: true } })
})
