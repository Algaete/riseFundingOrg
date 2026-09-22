import { useState } from 'react'
import { act, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { setInterfaceLanguage } from '@/i18n'
import { SearchableCatalogChoices } from './searchable-catalog-choices'

const items = [{ id: 152, code: 'CL', name: 'Chile' }, { id: 604, code: 'PE', name: 'Perú' }, { id: 840, code: 'US', name: 'Estados Unidos de América' }]
function Harness() {
  const [selected, setSelected] = useState([152])
  return <SearchableCatalogChoices catalog="countries" label="Countries" items={items} selected={selected} onChange={setSelected} />
}

it('filters country names without accents and keeps selected countries removable', async () => {
  render(<Harness />)
  await userEvent.type(screen.getByRole('searchbox'), 'peru')
  expect(screen.getByRole('checkbox', { name: 'Perú' })).toBeVisible()
  expect(screen.queryByRole('checkbox', { name: 'Estados Unidos de América' })).not.toBeInTheDocument()
  expect(screen.getByRole('checkbox', { name: 'Chile' })).toBeChecked()
  await userEvent.click(screen.getByRole('checkbox', { name: 'Chile' }))
  expect(screen.queryByRole('checkbox', { name: 'Chile' })).not.toBeInTheDocument()
  await userEvent.click(screen.getByRole('checkbox', { name: 'Perú' }))
  expect(screen.getByRole('checkbox', { name: 'Perú' })).toBeChecked()
})

it('searches codes and translated country labels after changing interface language', async () => {
  render(<Harness />)
  await act(() => setInterfaceLanguage('en'))
  expect(within(screen.getByRole('group', { name: 'Selected countries' })).getByRole('checkbox', { name: 'Chile' })).toBeChecked()
  expect(within(screen.getByRole('group', { name: 'Available countries' })).getAllByRole('checkbox')).toHaveLength(2)
  await userEvent.type(screen.getByRole('searchbox', { name: 'Search countries' }), 'united')
  expect(screen.getByRole('checkbox', { name: 'United States of America' })).toBeVisible()
  await userEvent.clear(screen.getByRole('searchbox'))
  await userEvent.type(screen.getByRole('searchbox'), 'PE')
  expect(screen.getByRole('checkbox', { name: 'Peru' })).toBeVisible()
  await userEvent.clear(screen.getByRole('searchbox'))
  await userEvent.type(screen.getByRole('searchbox'), 'no-such-country')
  expect(screen.getByRole('status')).toHaveTextContent('No more countries match your search.')
  expect(screen.getByRole('checkbox', { name: 'Chile' })).toBeChecked()
})
