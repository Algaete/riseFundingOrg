import { useState } from 'react'
import { act, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { setInterfaceLanguage } from '@/i18n'
import type { FundingDiscoveryCatalogs, PartnerGeography } from './funding-discovery-api'
import { PartnerGeographyFields } from './partner-geography-fields'

const catalogs: FundingDiscoveryCatalogs = {
  countries: [{ id: 250, code: 'FR', name: 'Francia' }, { id: 826, code: 'GB', name: 'Reino Unido de Gran Bretaña e Irlanda del Norte' }],
  regions: [], currencies: [], fundingCategories: [], fundingTypes: [], organizationTypes: [], languages: [],
  partnerRegions: [{ code: 'M49-150' }, { code: 'EU' }], partnerGeographyVersion: 'partner-geography-2026-09-12',
}
function Editor({ initial, change }: { initial?: PartnerGeography; change: (value: PartnerGeography) => void }) {
  const [value, setValue] = useState(initial)
  return <PartnerGeographyFields value={value} catalogs={catalogs} onChange={next => { setValue(next); change(next) }} />
}
describe('reviewed partner geography editor', () => {
  it('does not infer geography and requires an explicit selection', async () => {
    const change = vi.fn(); render(<Editor change={change} />)
    expect(screen.getByRole('combobox')).toHaveValue('0'); expect(change).not.toHaveBeenCalled()
    await userEvent.selectOptions(screen.getByRole('combobox'), '2')
    expect(screen.getByRole('status')).toHaveTextContent('Selecciona al menos un país o región')
    expect(screen.getByRole('checkbox', { name: 'Europa (ONU M49)' })).not.toBeChecked()
    expect(screen.getByRole('checkbox', { name: 'Unión Europea (27 países)' })).not.toBeChecked()
  })
  it('unions selected countries/regions, preserves selection across search and language, clears only explicitly', async () => {
    const change = vi.fn(); render(<Editor change={change} />)
    await userEvent.selectOptions(screen.getByRole('combobox'), '2')
    await userEvent.click(screen.getByRole('checkbox', { name: 'Unión Europea (27 países)' }))
    await userEvent.click(screen.getByRole('checkbox', { name: /Reino Unido/ }))
    expect(change).toHaveBeenLastCalledWith({ scope: 2, countryIds: [826], regionCodes: ['EU'], catalogVersion: catalogs.partnerGeographyVersion })
    await userEvent.type(screen.getByRole('textbox'), 'Francia')
    expect(screen.getByRole('button', { name: /Quitar Reino Unido/ })).toBeVisible()
    const count = change.mock.calls.length
    await act(async () => setInterfaceLanguage('en'))
    expect(screen.getByRole('checkbox', { name: 'European Union (27 countries)' })).toBeChecked()
    expect(change).toHaveBeenCalledTimes(count)
    await userEvent.selectOptions(screen.getByRole('combobox'), '1')
    expect(change).toHaveBeenLastCalledWith({ scope: 1, countryIds: [], regionCodes: [], catalogVersion: catalogs.partnerGeographyVersion })
  })
  it('preserves missing catalog selections and allows explicitly removing an inactive country', async () => {
    const change = vi.fn(); const initial: PartnerGeography = { scope: 2, countryIds: [999], regionCodes: [], catalogVersion: null }
    const view = render(<PartnerGeographyFields value={initial} onChange={change} />)
    expect(screen.getByRole('combobox')).toBeDisabled(); expect(change).not.toHaveBeenCalled()
    view.rerender(<PartnerGeographyFields value={initial} catalogs={catalogs} onChange={change} />)
    await userEvent.click(screen.getByRole('button', { name: 'Quitar País no disponible (999)' }))
    expect(change).toHaveBeenLastCalledWith({ ...initial, countryIds: [], catalogVersion: catalogs.partnerGeographyVersion })
  })
  it('never silently upgrades an old regional snapshot', async () => {
    const change = vi.fn()
    render(<Editor change={change} initial={{ scope: 2, countryIds: [], regionCodes: ['EU'], catalogVersion: 'old' }} />)
    expect(change).not.toHaveBeenCalled()
    await userEvent.click(screen.getByRole('button', { name: 'He revisado la selección con el catálogo actual' }))
    expect(change).toHaveBeenLastCalledWith({ scope: 2, countryIds: [], regionCodes: ['EU'], catalogVersion: catalogs.partnerGeographyVersion })
  })
})
