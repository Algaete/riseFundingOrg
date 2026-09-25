import { QueryClientProvider } from '@tanstack/react-query'
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'

import { ApiError } from '@/api/http-client'
import { createAppQueryClient } from '@/api/query-client'
import { setInterfaceLanguage } from '@/i18n'
import { adminOrganizationsApi, type OrganizationVerification } from './admin-organizations-api'
import { OrganizationVerificationPanel } from './organization-verification-panel'

const organizationId = '22222222-2222-2222-2222-222222222222'
const initial: OrganizationVerification = {
  organizationPublicId: organizationId, name: 'Organización de prueba', status: 0,
  recordedStatus: 0, revision: 0, profileVersion: 4, reviewedProfileVersion: null,
  reviewedAtUtc: null, reviewedByUserPublicId: null, reviewedByName: null,
  reason: null, needsReverification: false, history: [],
}
const saved: OrganizationVerification = {
  ...initial, status: 1, recordedStatus: 1, revision: 1, reviewedProfileVersion: 4,
  reviewedAtUtc: '2026-09-24T12:00:00Z', reviewedByUserPublicId: 'reviewer-id',
  reviewedByName: 'Editora de prueba', reason: 'Identidad y sitio revisados.',
  history: [{ revision: 1, status: 1, profileVersion: 4, reason: 'Identidad y sitio revisados.',
    reviewedAtUtc: '2026-09-24T12:00:00Z', reviewedByUserPublicId: 'reviewer-id', reviewedByName: 'Editora de prueba' }],
}

function apiError(status: number) {
  return new ApiError({ title: 'Private server diagnostic', status }, new Response(null, { status }))
}

function mount(profileVersion = 4, refreshProfile = vi.fn().mockResolvedValue(true)) {
  const queryClient = createAppQueryClient()
  const view = render(<QueryClientProvider client={queryClient}><OrganizationVerificationPanel
    organizationId={organizationId} profileVersion={profileVersion} refreshProfile={refreshProfile}
  /></QueryClientProvider>)
  return { ...view, queryClient, refreshProfile }
}

async function chooseDecision(label = 'Marcar como verificada', reason = 'Identidad y sitio revisados.') {
  const user = userEvent.setup()
  await screen.findByRole('button', { name: label })
  await user.type(screen.getByRole('textbox', { name: /Motivo de la nueva decisión/ }), reason)
  await user.click(screen.getByRole('button', { name: label }))
  return user
}

describe('verificación manual privada de organizaciones', () => {
  beforeEach(() => {
    vi.spyOn(adminOrganizationsApi, 'getVerification').mockResolvedValue(initial)
    vi.spyOn(adminOrganizationsApi, 'decideVerification').mockResolvedValue(saved)
  })
  afterEach(() => vi.restoreAllMocks())

  it('distingue verificación privada de completitud y no decide al abrir la ficha', async () => {
    mount()
    expect(await screen.findByText('Pendiente de verificación')).toBeInTheDocument()
    expect(screen.getByText(/independiente del porcentaje de perfil completo/)).toHaveTextContent('No constituye una certificación legal')
    expect(screen.getByText(/independiente del porcentaje de perfil completo/)).toHaveTextContent('no modifica el acceso, la publicación ni los contactos')
    expect(screen.getByRole('button', { name: 'Marcar como verificada' })).toBeDisabled()
    expect(adminOrganizationsApi.decideVerification).not.toHaveBeenCalled()
  })

  it('valida motivo obligatorio y longitud recortada antes de elegir', async () => {
    mount()
    const input = await screen.findByRole('textbox', { name: /Motivo de la nueva decisión/ })
    const approve = screen.getByRole('button', { name: 'Marcar como verificada' })
    fireEvent.change(input, { target: { value: '   abc   ' } })
    expect(approve).toBeDisabled()
    expect(input).toHaveAttribute('aria-invalid', 'true')
    fireEvent.change(input, { target: { value: 'x'.repeat(2001) } })
    expect(approve).toBeDisabled()
    fireEvent.change(input, { target: { value: '  abcde  ' } })
    expect(approve).toBeEnabled()
    expect(input).toHaveAttribute('maxlength', '2000')
    expect(adminOrganizationsApi.decideVerification).not.toHaveBeenCalled()
  })

  it('necesita una confirmación separada y guarda motivo recortado y ambas versiones', async () => {
    const { queryClient } = mount()
    const invalidate = vi.spyOn(queryClient, 'invalidateQueries')
    const user = await chooseDecision(undefined, '  Identidad y sitio revisados.  ')
    expect(adminOrganizationsApi.decideVerification).not.toHaveBeenCalled()
    expect(screen.getByRole('textbox')).toBeDisabled()
    expect(screen.getByRole('region', { name: 'Confirmación de la decisión' })).toHaveTextContent('Confirmar estado: Verificada')
    await user.click(screen.getByRole('button', { name: 'Confirmar decisión' }))
    expect(await screen.findByText('Decisión guardada en el historial privado.')).toBeInTheDocument()
    expect(adminOrganizationsApi.decideVerification).toHaveBeenCalledExactlyOnceWith(organizationId, {
      status: 1, reason: 'Identidad y sitio revisados.', expectedRevision: 0, expectedProfileVersion: 4,
    })
    expect(invalidate).toHaveBeenCalledWith({ queryKey: ['admin-organizations'] })
    expect(screen.getByRole('textbox')).toHaveValue('')
    expect(screen.getAllByText('Editora de prueba').length).toBeGreaterThan(0)
    await user.click(screen.getByText('Historial privado de decisiones'))
    expect(screen.getByRole('listitem')).toHaveTextContent('perfil v4')
    expect(screen.getByRole('listitem')).toHaveTextContent('Identidad y sitio revisados.')
  })

  it.each([['Rechazar verificación', 2], ['Devolver a pendiente', 0]] as const)(
    'requiere decisión explícita también para %s', async (label, status) => {
      mount()
      const user = await chooseDecision(label)
      expect(adminOrganizationsApi.decideVerification).not.toHaveBeenCalled()
      await user.click(screen.getByRole('button', { name: 'Confirmar decisión' }))
      await waitFor(() => expect(adminOrganizationsApi.decideVerification).toHaveBeenCalledExactlyOnceWith(
        organizationId, expect.objectContaining({ status, reason: 'Identidad y sitio revisados.' }),
      ))
    },
  )

  it('cancelar no escribe ni borra el motivo para poder corregirlo', async () => {
    mount()
    const user = await chooseDecision()
    await user.click(screen.getByRole('button', { name: 'Cancelar' }))
    expect(screen.queryByRole('button', { name: 'Confirmar decisión' })).not.toBeInTheDocument()
    expect(screen.getByRole('textbox')).toHaveValue('Identidad y sitio revisados.')
    expect(screen.getByRole('textbox')).toBeEnabled()
    expect(adminOrganizationsApi.decideVerification).not.toHaveBeenCalled()
  })

  it('deshabilita los controles mientras la decisión está en curso', async () => {
    let complete!: (value: OrganizationVerification) => void
    vi.mocked(adminOrganizationsApi.decideVerification).mockImplementation(() => new Promise(resolve => { complete = resolve }))
    mount()
    const user = await chooseDecision()
    await user.dblClick(screen.getByRole('button', { name: 'Confirmar decisión' }))
    expect(screen.getByRole('button', { name: 'Confirmar decisión' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Cancelar' })).toBeDisabled()
    expect(adminOrganizationsApi.decideVerification).toHaveBeenCalledTimes(1)
    complete(saved)
    expect(await screen.findByText('Decisión guardada en el historial privado.')).toBeInTheDocument()
  })

  it('en 409 no reenvía, exige releer ambos recursos y una nueva elección', async () => {
    vi.mocked(adminOrganizationsApi.decideVerification).mockRejectedValueOnce(apiError(409))
    vi.mocked(adminOrganizationsApi.getVerification).mockResolvedValueOnce(initial).mockResolvedValue({ ...initial, revision: 2 })
    const { refreshProfile } = mount()
    const user = await chooseDecision()
    await user.click(screen.getByRole('button', { name: 'Confirmar decisión' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Tu decisión no se ha reenviado')
    expect(adminOrganizationsApi.decideVerification).toHaveBeenCalledTimes(1)
    expect(adminOrganizationsApi.getVerification).toHaveBeenCalledTimes(1)
    expect(screen.getByRole('textbox')).toHaveValue('')
    expect(screen.getByRole('button', { name: 'Marcar como verificada' })).toBeDisabled()
    await user.click(screen.getByRole('button', { name: 'Recargar perfil y verificación' }))
    await waitFor(() => expect(screen.getByRole('textbox')).toBeEnabled())
    expect(refreshProfile).toHaveBeenCalledTimes(1)
    expect(adminOrganizationsApi.getVerification).toHaveBeenCalledTimes(2)
    expect(adminOrganizationsApi.decideVerification).toHaveBeenCalledTimes(1)
    expect(screen.queryByRole('button', { name: 'Confirmar decisión' })).not.toBeInTheDocument()
    await user.type(screen.getByRole('textbox'), 'Revisado de nuevo.')
    await user.click(screen.getByRole('button', { name: 'Marcar como verificada' }))
    await user.click(screen.getByRole('button', { name: 'Confirmar decisión' }))
    await waitFor(() => expect(adminOrganizationsApi.decideVerification).toHaveBeenCalledTimes(2))
    expect(adminOrganizationsApi.decideVerification).toHaveBeenLastCalledWith(organizationId, {
      status: 1, reason: 'Revisado de nuevo.', expectedRevision: 2, expectedProfileVersion: 4,
    })
  })

  it('no desbloquea un conflicto cuando falla recargar el perfil', async () => {
    vi.mocked(adminOrganizationsApi.decideVerification).mockRejectedValueOnce(apiError(409))
    const refreshProfile = vi.fn().mockResolvedValue(false)
    mount(4, refreshProfile)
    const user = await chooseDecision()
    await user.click(screen.getByRole('button', { name: 'Confirmar decisión' }))
    await user.click(await screen.findByRole('button', { name: 'Recargar perfil y verificación' }))
    expect(await screen.findByText('No pudimos actualizar la información de revisión. Recarga antes de decidir.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Marcar como verificada' })).toBeDisabled()
    expect(adminOrganizationsApi.decideVerification).toHaveBeenCalledTimes(1)
  })

  it('no permite decidir sobre un perfil distinto del que se está mostrando', async () => {
    vi.mocked(adminOrganizationsApi.getVerification).mockResolvedValue({ ...initial, profileVersion: 5 })
    mount(4)
    expect(await screen.findByRole('alert')).toHaveTextContent('El perfil o su revisión cambiaron')
    expect(screen.getByRole('textbox')).toBeDisabled()
    expect(adminOrganizationsApi.decideVerification).not.toHaveBeenCalled()
  })

  it('invalida la confirmación si cambió la revisión en caché antes de confirmar', async () => {
    const { queryClient } = mount()
    const user = await chooseDecision()
    queryClient.setQueryData(['admin-organization-verification', organizationId], { ...initial, revision: 1 })
    await waitFor(() => expect(screen.getByText('Revisión 1 · perfil v4')).toBeInTheDocument())
    await user.click(screen.getByRole('button', { name: 'Confirmar decisión' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Tu decisión no se ha reenviado')
    expect(adminOrganizationsApi.decideVerification).not.toHaveBeenCalled()
  })

  it('distingue una verificación anterior de un perfil cambiado pendiente', async () => {
    vi.mocked(adminOrganizationsApi.getVerification).mockResolvedValue({
      ...saved, status: 0, profileVersion: 5, needsReverification: true,
    })
    mount(5)
    expect(await screen.findByText('Pendiente de verificación')).toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('El perfil cambió después de la última decisión')
    expect(screen.getByText('Última decisión registrada').parentElement).toHaveTextContent('Verificada')
    expect(screen.getByText('Versión del perfil revisada').parentElement).toHaveTextContent('4')
  })

  it('tolera historial nulo sin llamar map sobre null', async () => {
    vi.mocked(adminOrganizationsApi.getVerification).mockResolvedValue({ ...initial, history: null })
    mount()
    const user = userEvent.setup()
    await user.click(await screen.findByText('Historial privado de decisiones'))
    expect(screen.getByText('Todavía no hay decisiones registradas.')).toBeVisible()
    expect(screen.queryAllByRole('listitem')).toHaveLength(0)
  })

  it('permite recuperar un fallo de lectura sin crear ninguna decisión', async () => {
    vi.mocked(adminOrganizationsApi.getVerification).mockRejectedValueOnce(apiError(503)).mockResolvedValue(initial)
    mount()
    const user = userEvent.setup()
    expect(await screen.findByRole('alert')).toHaveTextContent('No pudimos actualizar')
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Recargar perfil y verificación' }))
    expect(await screen.findByRole('textbox')).toBeEnabled()
    expect(adminOrganizationsApi.decideVerification).not.toHaveBeenCalled()
  })

  it.each([403, 400, 422, 503])('muestra error traducido para %i sin diagnóstico privado ni reintento', async status => {
    vi.mocked(adminOrganizationsApi.decideVerification).mockRejectedValue(apiError(status))
    mount()
    const user = await chooseDecision()
    await user.click(screen.getByRole('button', { name: 'Confirmar decisión' }))
    const alert = await screen.findByRole('alert')
    expect(alert).not.toHaveTextContent('Private server diagnostic')
    expect(within(alert).getByRole('button', { name: 'Recargar perfil y verificación' })).toBeEnabled()
    expect(screen.getByRole('button', { name: 'Marcar como verificada' })).toBeDisabled()
    expect(adminOrganizationsApi.decideVerification).toHaveBeenCalledTimes(1)
  })

  it('muestra las decisiones, ayuda y confirmación en inglés', async () => {
    await setInterfaceLanguage('en')
    mount()
    const user = userEvent.setup()
    expect(await screen.findByText('Pending verification')).toBeInTheDocument()
    expect(screen.getByText(/This is not legal certification/)).toBeInTheDocument()
    await user.type(screen.getByRole('textbox', { name: /Reason for the new decision/ }), 'Identity checked.')
    await user.click(screen.getByRole('button', { name: 'Mark as verified' }))
    expect(screen.getByRole('region', { name: 'Decision confirmation' })).toHaveTextContent('Confirm status: Verified')
    expect(screen.getByRole('button', { name: 'Confirm decision' })).toBeEnabled()
    expect(adminOrganizationsApi.decideVerification).not.toHaveBeenCalled()
  })
})
