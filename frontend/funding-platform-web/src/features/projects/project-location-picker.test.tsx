import { fireEvent, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ProjectLocationPicker } from './project-location-picker'

it('maps pointer coordinates to the same projection as the public map', () => {
  const changed = vi.fn()
  render(<ProjectLocationPicker value={null} onChange={changed} />)
  const map = screen.getByRole('button', { name: 'Elegir ubicación en el mapa' })
  vi.spyOn(map, 'getBoundingClientRect').mockReturnValue({ x: 10, y: 20, left: 10, top: 20, width: 720, height: 360, right: 730, bottom: 380, toJSON: () => ({}) })
  fireEvent.click(map, { detail: 1, clientX: 230, clientY: 266 })
  expect(changed).toHaveBeenCalledWith({ latitude: -33, longitude: -70 })
})

it('supports keyboard selection and zoom/pan without selecting anything automatically', async () => {
  const changed = vi.fn()
  render(<ProjectLocationPicker value={null} onChange={changed} />)
  await userEvent.click(screen.getByRole('button', { name: 'Acercar' }))
  await userEvent.click(screen.getByRole('button', { name: 'Mover al oeste' }))
  expect(changed).not.toHaveBeenCalled()
  screen.getByRole('button', { name: 'Elegir ubicación en el mapa' }).focus()
  await userEvent.keyboard('{Enter}')
  expect(changed).toHaveBeenCalledWith({ latitude: 0, longitude: -63 })
})

it('cannot change the point in a locked editorial form', async () => {
  const changed = vi.fn()
  render(<fieldset disabled><ProjectLocationPicker value={{ latitude: -33, longitude: -70 }} onChange={changed} /></fieldset>)
  for (const button of screen.getAllByRole('button')) expect(button).toBeDisabled()
  await userEvent.click(screen.getByRole('button', { name: 'Usar el centro del mapa' }))
  expect(changed).not.toHaveBeenCalled()
})
