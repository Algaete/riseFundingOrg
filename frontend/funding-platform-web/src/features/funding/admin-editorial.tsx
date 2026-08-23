/* oxlint-disable react/only-export-components -- Editorial components and their shared display helpers form one cohesive module. */
import { useMutation } from '@tanstack/react-query'
import {
  Archive,
  CheckCircle2,
  CircleAlert,
  Clock3,
  LoaderCircle,
  PencilLine,
  RefreshCw,
  Send,
  XCircle,
} from 'lucide-react'
import { useEffect, useState } from 'react'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  type EditorialWorkflowResponse,
  type PublicationStatus,
  type ReviewDecision,
} from '@/features/funding/admin-funding-api'
import { executeEditorialCommand } from '@/features/funding/editorial-command-cache'

export const publicationStatusLabels: Record<PublicationStatus, string> = {
  0: 'Borrador',
  1: 'Pendiente de revisión',
  2: 'Publicado',
  3: 'Rechazado',
  4: 'Desactivado',
}

const statusStyles: Record<PublicationStatus, string> = {
  0: 'bg-muted text-foreground',
  1: 'bg-amber-100 text-amber-900 dark:bg-amber-950 dark:text-amber-100',
  2: 'bg-accent text-accent-foreground',
  3: 'bg-destructive/10 text-destructive',
  4: 'bg-slate-200 text-slate-700 dark:bg-slate-800 dark:text-slate-200',
}

export function PublicationStatusBadge({ status }: { status: PublicationStatus }) {
  return (
    <span className={`rounded-full px-3 py-1 text-xs font-semibold ${statusStyles[status]}`}>
      {publicationStatusLabels[status]}
    </span>
  )
}

export function adminErrorMessage(error: unknown) {
  return error instanceof ApiError
    ? error.problem.detail ?? error.problem.title
    : 'No fue posible completar la operación. Intenta nuevamente.'
}

export function adminValidationMessages(error: unknown) {
  if (!(error instanceof ApiError) || !error.problem.errors) return []
  return Array.from(new Set(Object.values(error.problem.errors).flat()))
}

export function isConcurrencyConflict(error: unknown) {
  return error instanceof ApiError && error.response.status === 412
}

export function formatAdminDate(value: string | null | undefined) {
  if (!value) return 'Sin fecha'
  const date = new Date(value)
  return Number.isNaN(date.getTime())
    ? 'Fecha no disponible'
    : new Intl.DateTimeFormat('es-CL', { dateStyle: 'medium', timeStyle: 'short' }).format(date)
}

interface EditorialCommands {
  submitReview(id: string, eTag: string, idempotencyKey: string): Promise<EditorialWorkflowResponse>
  review(
    id: string,
    eTag: string,
    idempotencyKey: string,
    decision: ReviewDecision,
    reason?: string,
  ): Promise<EditorialWorkflowResponse>
  deactivate(
    id: string,
    eTag: string,
    idempotencyKey: string,
    reason?: string,
  ): Promise<EditorialWorkflowResponse>
  startCorrection(
    id: string,
    eTag: string,
    idempotencyKey: string,
    reason: string,
  ): Promise<EditorialWorkflowResponse>
}

type EditorialCommand =
  | { action: 'submit' }
  | { action: 'approve' }
  | { action: 'reject'; reason: string }
  | { action: 'correction'; reason: string }
  | { action: 'deactivate'; reason?: string }

export function EditorialWorkflowPanel({
  commands,
  disabledReason,
  eTag,
  entityId,
  entityName,
  onChanged,
  publicVisibilityIssues = [],
  publicationStatus,
  rejectionReason,
}: {
  commands: EditorialCommands
  disabledReason?: string
  eTag: string
  entityId: string
  entityName: string
  onChanged: () => Promise<unknown>
  publicVisibilityIssues?: string[]
  publicationStatus: PublicationStatus
  rejectionReason?: string | null
}) {
  const [reason, setReason] = useState('')
  const [correctionReason, setCorrectionReason] = useState('')
  const [confirmCorrection, setConfirmCorrection] = useState(false)
  const [confirmDeactivate, setConfirmDeactivate] = useState(false)
  const command = useMutation({
    mutationFn: (input: EditorialCommand) => executeEditorialCommand(
      `workflow:${entityId}:${input.action}`,
      { eTag, ...input },
      (idempotencyKey) => {
        if (input.action === 'submit') {
          return commands.submitReview(entityId, eTag, idempotencyKey)
        }
        if (input.action === 'approve') {
          return commands.review(entityId, eTag, idempotencyKey, 'approve')
        }
        if (input.action === 'reject') {
          return commands.review(entityId, eTag, idempotencyKey, 'reject', input.reason)
        }
        if (input.action === 'correction') {
          return commands.startCorrection(entityId, eTag, idempotencyKey, input.reason)
        }
        return commands.deactivate(entityId, eTag, idempotencyKey, input.reason)
      },
    ),
    onSuccess: async () => {
      setReason('')
      setCorrectionReason('')
      setConfirmCorrection(false)
      setConfirmDeactivate(false)
      await onChanged()
    },
  })
  const validationMessages = adminValidationMessages(command.error)
  const conflict = isConcurrencyConflict(command.error)

  useEffect(() => {
    if (!confirmCorrection || command.isPending) return
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setConfirmCorrection(false)
        setCorrectionReason('')
      }
    }
    document.addEventListener('keydown', closeOnEscape)
    return () => document.removeEventListener('keydown', closeOnEscape)
  }, [command.isPending, confirmCorrection])

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <p className="text-xs font-bold uppercase tracking-[0.16em] text-primary">Flujo editorial</p>
            <CardTitle className="mt-1">{publicationStatusLabels[publicationStatus]}</CardTitle>
          </div>
          <PublicationStatusBadge status={publicationStatus} />
        </div>
      </CardHeader>
      <CardContent className="space-y-5">
        {publicationStatus === 0 && (
          <p className="text-sm leading-6 text-muted-foreground">
            Guarda el contenido y envía {entityName} a revisión cuando tenga procedencia y alcance suficientes.
          </p>
        )}
        {publicationStatus === 1 && !confirmDeactivate && (
          <p className="flex items-start gap-2 rounded-lg bg-amber-50 p-3 text-sm text-amber-950 dark:bg-amber-950/35 dark:text-amber-100">
            <Clock3 className="mt-0.5 size-4 shrink-0" /> La versión enviada está bloqueada hasta aprobarla o rechazarla.
          </p>
        )}
        {publicationStatus === 2 && publicVisibilityIssues.length === 0 && (
          <p className="flex items-start gap-2 rounded-lg bg-accent p-3 text-sm text-accent-foreground">
            <CheckCircle2 className="mt-0.5 size-4 shrink-0" /> Este contenido está visible en el catálogo público.
          </p>
        )}
        {publicationStatus === 2 && publicVisibilityIssues.length > 0 && (
          <div className="rounded-lg bg-amber-50 p-3 text-sm text-amber-950 dark:bg-amber-950/35 dark:text-amber-100" role="alert">
            <p className="flex items-start gap-2 font-semibold">
              <CircleAlert className="mt-0.5 size-4 shrink-0" /> Publicado, pero oculto del catálogo hasta completar estos datos:
            </p>
            <ul className="mt-2 list-disc space-y-1 pl-7">
              {publicVisibilityIssues.map((issue) => <li key={issue}>{issue}</li>)}
            </ul>
            <p className="mt-2">Usa “Corregir publicación”, completa los campos y vuelve a enviarla a revisión.</p>
          </div>
        )}
        {publicationStatus === 3 && (
          <p className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">
            <strong>Revisión rechazada.</strong>{' '}{rejectionReason ?? 'Corrige los datos y vuelve a enviarlos.'}
          </p>
        )}
        {publicationStatus === 4 && (
          <p className="rounded-lg bg-muted p-3 text-sm">Este contenido fue desactivado y ya no es público.</p>
        )}
        {disabledReason && (
          <p className="rounded-lg border p-3 text-sm text-muted-foreground">{disabledReason}</p>
        )}

        {publicationStatus === 1 && (
          <label className="grid gap-1.5 text-sm font-semibold">
            <span>Motivo si rechazas</span>
            <textarea
              className="min-h-24 rounded-lg border bg-background px-3 py-2 font-normal"
              maxLength={1000}
              onChange={(event) => setReason(event.target.value)}
              placeholder="Explica qué debe corregirse antes de volver a revisión."
              value={reason}
            />
          </label>
        )}

        {publicationStatus !== 4 && confirmDeactivate && (
          <label className="grid gap-1.5 text-sm font-semibold">
            <span>Motivo de desactivación (opcional)</span>
            <textarea
              className="min-h-20 rounded-lg border bg-background px-3 py-2 font-normal"
              maxLength={1000}
              onChange={(event) => setReason(event.target.value)}
              placeholder="Ej. La convocatoria cerró anticipadamente."
              value={reason}
            />
          </label>
        )}

        {command.isError && (
          <div className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive" role="alert">
            <p className="flex items-start gap-2">
              <CircleAlert className="mt-0.5 size-4 shrink-0" /> {adminErrorMessage(command.error)}
            </p>
            {validationMessages.length > 0 && (
              <ul className="mt-2 list-disc space-y-1 pl-7">
                {validationMessages.map((message) => <li key={message}>{message}</li>)}
              </ul>
            )}
            {conflict && (
              <Button className="mt-3" onClick={() => void onChanged()} size="sm" type="button" variant="outline">
                <RefreshCw className="size-4" /> Cargar versión vigente
              </Button>
            )}
          </div>
        )}

        {publicationStatus === 2 && confirmCorrection && (
          <div className="fixed inset-0 z-50 grid place-items-center bg-black/65 p-4">
            <div
              aria-describedby="correction-description"
              aria-labelledby="correction-title"
              aria-modal="true"
              className="w-full max-w-xl rounded-xl border border-amber-300 bg-amber-50 p-5 text-amber-950 shadow-2xl dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100"
              role="dialog"
            >
              <h3 className="text-lg font-bold" id="correction-title">Iniciar corrección editorial</h3>
              <p className="mt-2 text-sm leading-6" id="correction-description">
                Al confirmar, {entityName} se retirará temporalmente del catálogo público y volverá a borrador. Deberás guardar los cambios, enviarlos a revisión y aprobarlos nuevamente.
              </p>
              <label className="mt-4 grid gap-1.5 text-sm font-semibold">
                <span>Motivo de la corrección</span>
                <textarea
                  autoFocus
                  className="min-h-24 rounded-lg border bg-background px-3 py-2 font-normal text-foreground"
                  maxLength={1000}
                  onChange={(event) => setCorrectionReason(event.target.value)}
                  placeholder="Ej. Debemos reemplazar el enlace de postulación por el oficial."
                  value={correctionReason}
                />
                <span className="text-xs font-normal">Obligatorio, entre 3 y 1000 caracteres.</span>
              </label>
              <div className="mt-4 flex flex-wrap gap-2">
                <Button
                  disabled={command.isPending || correctionReason.trim().length < 3}
                  onClick={() => command.mutate({ action: 'correction', reason: correctionReason.trim() })}
                  type="button"
                >
                  {command.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <PencilLine className="size-4" />}
                  Retirar e iniciar corrección
                </Button>
                <Button
                  disabled={command.isPending}
                  onClick={() => { setConfirmCorrection(false); setCorrectionReason('') }}
                  type="button"
                  variant="ghost"
                >
                  Cancelar
                </Button>
              </div>
            </div>
          </div>
        )}

        <div className="flex flex-wrap gap-3">
          {(publicationStatus === 0 || publicationStatus === 3) && !confirmDeactivate && (
            <Button
              disabled={command.isPending || Boolean(disabledReason)}
              onClick={() => command.mutate({ action: 'submit' })}
              type="button"
            >
              {command.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Send className="size-4" />}
              Enviar a revisión
            </Button>
          )}
          {publicationStatus === 1 && !confirmDeactivate && (
            <>
              <Button
                disabled={command.isPending || Boolean(disabledReason)}
                onClick={() => command.mutate({ action: 'approve' })}
                type="button"
              >
                <CheckCircle2 className="size-4" /> Aprobar y publicar
              </Button>
              <Button
                disabled={command.isPending || Boolean(disabledReason) || reason.trim().length < 3}
                onClick={() => command.mutate({ action: 'reject', reason: reason.trim() })}
                type="button"
                variant="outline"
              >
                <XCircle className="size-4" /> Rechazar
              </Button>
            </>
          )}
          {publicationStatus === 2 && !confirmCorrection && !confirmDeactivate && (
            <Button
              disabled={command.isPending || Boolean(disabledReason)}
              onClick={() => setConfirmCorrection(true)}
              type="button"
              variant="outline"
            >
              <PencilLine className="size-4" /> Corregir publicación
            </Button>
          )}
          {publicationStatus !== 4 && !confirmDeactivate && (
            <Button disabled={Boolean(disabledReason) || confirmCorrection} onClick={() => setConfirmDeactivate(true)} type="button" variant="outline">
              <Archive className="size-4" /> Desactivar
            </Button>
          )}
          {publicationStatus !== 4 && confirmDeactivate && (
            <>
              <Button
                disabled={command.isPending}
                onClick={() => command.mutate({ action: 'deactivate', reason: reason.trim() || undefined })}
                type="button"
                variant="outline"
              >
                {command.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Archive className="size-4" />}
                Confirmar desactivación
              </Button>
              <Button onClick={() => { setConfirmDeactivate(false); setReason('') }} type="button" variant="ghost">Cancelar</Button>
            </>
          )}
        </div>
      </CardContent>
    </Card>
  )
}
