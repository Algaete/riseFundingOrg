import { act, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { useTranslation } from 'react-i18next'
import type { ComponentProps } from 'react'
import { vi } from 'vitest'
import { EditorialWorkflowPanel } from './admin-editorial'
import type { EditorialWorkflowResponse, PublicationStatus } from './admin-funding-api'
import { deferred, language, problem, trackingPage } from '@/test/tracking-test-harness'

function panel(status: PublicationStatus, extra: Partial<ComponentProps<typeof EditorialWorkflowPanel>> = {}) {
  const commands = { submitReview: vi.fn(), review: vi.fn(), deactivate: vi.fn(), startCorrection: vi.fn() }
  const onChanged = vi.fn().mockResolvedValue(undefined)
  const entityId = crypto.randomUUID()
  function View() {
    const { t } = useTranslation()
    return <EditorialWorkflowPanel commands={commands} eTag='"v3"' entityId={entityId}
      entityName={t('editorial.opportunityEntity')} onChanged={onChanged} publicationStatus={status} {...extra} />
  }
  const view = trackingPage(<View />, '/admin/funding/' + entityId)
  return { ...view, commands, onChanged, entityId }
}

describe('editorial workflow language invariants', () => {
  it.each([
    [0, 'Draft', 'Submit for review'], [1, 'Pending review', 'Approve and publish'],
    [2, 'Published', 'Correct publication'], [3, 'Rejected', 'Submit for review'],
    [4, 'Deactivated', null],
  ] as const)('translates state %s without issuing a command', async (status, label, action) => {
    const { commands } = panel(status, { rejectionReason: 'Motivo original Ñandú' })
    await language('en')
    expect(screen.getAllByText(label)).toHaveLength(2)
    if (action) expect(screen.getByRole('button', { name: action })).toBeEnabled()
    else expect(screen.queryByRole('button')).not.toBeInTheDocument()
    if (status === 3) expect(screen.getByText(/Motivo original Ñandú/)).toBeInTheDocument()
    if (status === 0) expect(screen.getByText(/submit the opportunity for review/)).toBeInTheDocument()
    for (const command of Object.values(commands)) expect(command).not.toHaveBeenCalled()
  })

  it('keeps dirty content locked and published-but-hidden distinct from public', async () => {
    const { commands } = panel(2, { publicVisibilityIssues: ['Datos originales pendientes'], disabledReason: 'Cambios sin guardar' })
    await language('en')
    expect(screen.getByRole('alert')).toHaveTextContent('Published, but hidden')
    expect(screen.queryByText('This content is visible in the public catalog.')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Correct publication' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Deactivate' })).toBeDisabled()
    expect(commands.startCorrection).not.toHaveBeenCalled()
  })

  it('preserves a pending rejection across ES/EN and retries the same intention with the same key', async () => {
    const user = userEvent.setup()
    const { commands, entityId, onChanged } = panel(1)
    const pending = deferred<EditorialWorkflowResponse>()
    commands.review.mockReturnValueOnce(pending.promise).mockRejectedValueOnce(problem(503))
    await user.type(screen.getByRole('textbox'), 'Motivo original Ñandú')
    await user.click(screen.getByRole('button', { name: 'Rechazar' }))
    await waitFor(() => expect(commands.review).toHaveBeenCalledTimes(1))
    const original = commands.review.mock.calls[0]
    expect(original).toEqual([entityId, '"v3"', expect.any(String), 'reject', 'Motivo original Ñandú'])
    await language('en')
    expect(screen.getByRole('textbox', { name: 'Reason for rejection' })).toHaveValue('Motivo original Ñandú')
    expect(screen.getByRole('button', { name: 'Reject' })).toBeDisabled()
    expect(commands.review).toHaveBeenCalledTimes(1)
    await act(async () => pending.reject(problem(503)))
    expect(await screen.findByRole('alert')).toHaveTextContent('The service is unavailable.')
    await user.click(screen.getByRole('button', { name: 'Reject' }))
    await waitFor(() => expect(commands.review).toHaveBeenCalledTimes(2))
    expect(commands.review.mock.calls[1]).toEqual(original)
    expect(onChanged).not.toHaveBeenCalled()
  })

  it('requires explicit correction confirmation, preserves the reason and allows safe cancellation', async () => {
    const user = userEvent.setup()
    const { commands, entityId, onChanged } = panel(2)
    await user.click(screen.getByRole('button', { name: 'Corregir publicación' }))
    await user.type(within(screen.getByRole('dialog')).getByRole('textbox'), 'Corregir fuente Ñandú')
    await language('en')
    let dialog = screen.getByRole('dialog', { name: 'Start editorial correction' })
    expect(dialog).toHaveTextContent('temporarily remove the opportunity from the public catalog')
    expect(within(dialog).getByRole('textbox')).toHaveValue('Corregir fuente Ñandú')
    expect(commands.startCorrection).not.toHaveBeenCalled()
    await user.click(within(dialog).getByRole('button', { name: 'Cancel' }))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Correct publication' }))
    dialog = screen.getByRole('dialog')
    expect(within(dialog).getByRole('button', { name: 'Withdraw and start correction' })).toBeDisabled()
    await user.type(within(dialog).getByRole('textbox'), 'Corrección definitiva Ñandú')
    commands.startCorrection.mockResolvedValue({ entityId, publicationStatus: 0, contentVersion: 4, eTag: '"v4"', wasReplay: false })
    await user.click(within(dialog).getByRole('button', { name: 'Withdraw and start correction' }))
    await waitFor(() => expect(onChanged).toHaveBeenCalledTimes(1))
    expect(commands.startCorrection).toHaveBeenCalledWith(entityId, '"v3"', expect.any(String), 'Corrección definitiva Ñandú')
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('does not deactivate until confirmation and permits an empty optional reason', async () => {
    const user = userEvent.setup()
    const { commands, entityId } = panel(0)
    await user.click(screen.getByRole('button', { name: 'Desactivar' }))
    await language('en')
    expect(screen.getByRole('textbox', { name: 'Reason for deactivation (optional)' })).toHaveValue('')
    expect(commands.deactivate).not.toHaveBeenCalled()
    await user.click(screen.getByRole('button', { name: 'Confirm deactivation' }))
    await waitFor(() => expect(commands.deactivate).toHaveBeenCalledTimes(1))
    expect(commands.deactivate).toHaveBeenCalledWith(entityId, '"v3"', expect.any(String), undefined)
  })

  it('only reloads a conflicting version after an explicit click', async () => {
    const user = userEvent.setup()
    const { commands, onChanged } = panel(0)
    commands.submitReview.mockRejectedValue(problem(412))
    await user.click(screen.getByRole('button', { name: 'Enviar a revisión' }))
    await screen.findByRole('alert')
    await language('en')
    expect(screen.getByRole('alert')).not.toHaveTextContent('PRIVATE-DIAGNOSTIC')
    expect(onChanged).not.toHaveBeenCalled()
    await user.click(screen.getByRole('button', { name: 'Load current version' }))
    expect(onChanged).toHaveBeenCalledTimes(1)
    expect(commands.submitReview).toHaveBeenCalledTimes(1)
  })
})
