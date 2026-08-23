import { useMutation, useQuery } from '@tanstack/react-query'
import {
  AlertTriangle,
  CheckCircle2,
  DatabaseZap,
  FileClock,
  FileText,
  LoaderCircle,
  Play,
  RefreshCw,
  ShieldAlert,
  ShieldCheck,
  UploadCloud,
} from 'lucide-react'
import { type ChangeEvent, type FormEvent, useEffect, useMemo, useState } from 'react'
import { Link, useParams } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { adminFundingSourcesApi } from '@/features/funding/admin-funding-api'
import { executeEditorialCommand } from '@/features/funding/editorial-command-cache'
import {
  sourceDocumentApi,
  sourceDocumentErrorMessage,
  type SourceDocumentOperation,
  type SourceDocumentStatusResponse,
  uploadFileDirectly,
} from '@/features/source-documents/source-document-api'

const maxPdfBytes = 26_214_400

const scanLabels = {
  0: 'Pendiente de análisis',
  1: 'Limpio',
  2: 'Contenido malicioso',
  3: 'Análisis fallido',
  4: 'Tiempo de análisis agotado',
} as const

const storageLabels = {
  0: 'Esperando cuarentena',
  1: 'En cuarentena',
  2: 'Trusted (confiable)',
  3: 'Almacenamiento fallido',
} as const

const intentLabels = {
  0: 'Esperando archivo',
  1: 'Verificando archivo',
  2: 'Carga completada',
  3: 'Autorización vencida',
  4: 'Archivo rechazado',
} as const

const extractionLabels = {
  0: 'Sin iniciar',
  1: 'En cola',
  2: 'Extrayendo contenido',
  3: 'Completada',
  4: 'Completada con observaciones',
  5: 'Fallida',
  6: 'Cancelada',
} as const

function isCleanAndTrusted(document: SourceDocumentStatusResponse) {
  return document.scanStatus === 1 && document.storageStatus === 2
}

function isExtractionActive(document: SourceDocumentStatusResponse) {
  return document.extractionStatus === 1 || document.extractionStatus === 2
}

function shouldPollDocument(document: SourceDocumentStatusResponse | undefined) {
  return document?.scanStatus === 0 || (document ? isExtractionActive(document) : false)
}

function formatBytes(value: number) {
  return new Intl.NumberFormat('es-CL', {
    maximumFractionDigits: 1,
    style: 'unit',
    unit: value >= 1024 * 1024 ? 'megabyte' : 'kilobyte',
    unitDisplay: 'short',
  }).format(value >= 1024 * 1024 ? value / (1024 * 1024) : value / 1024)
}

function StatusBadge({ document }: { document: SourceDocumentStatusResponse }) {
  const className = document.scanStatus === 1
    ? 'bg-accent text-accent-foreground'
    : document.scanStatus === 2
      ? 'bg-destructive/10 text-destructive'
      : document.scanStatus >= 3
        ? 'bg-amber-100 text-amber-900 dark:bg-amber-950 dark:text-amber-100'
        : 'bg-muted text-muted-foreground'
  return (
    <span className={`rounded-full px-3 py-1 text-xs font-semibold ${className}`}>
      {scanLabels[document.scanStatus]}
    </span>
  )
}

function DevelopmentWarning() {
  return (
    <div className="flex gap-3 rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm text-amber-950 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100" role="status">
      <AlertTriangle className="mt-0.5 size-5 shrink-0" aria-hidden />
      <div>
        <p className="font-semibold">Defender real pendiente de configuración</p>
        <p className="mt-1">Este entorno usa un analizador simulado para pruebas locales. No equivale a Microsoft Defender for Storage ni debe considerarse una validación de producción.</p>
      </div>
    </div>
  )
}

function ProductionScanNotice() {
  return (
    <div className="flex gap-3 rounded-xl border border-emerald-300 bg-emerald-50 p-4 text-sm text-emerald-950 dark:border-emerald-800 dark:bg-emerald-950 dark:text-emerald-100" role="status">
      <ShieldCheck className="mt-0.5 size-5 shrink-0" aria-hidden />
      <div>
        <p className="font-semibold">Microsoft Defender for Storage</p>
        <p className="mt-1">El resultado proviene del analizador productivo configurado para este almacenamiento.</p>
      </div>
    </div>
  )
}

function DocumentStatusCard({
  document,
  extracting,
  extractionError,
  extractionMessage,
  onExtract,
  retrying,
  onRetry,
}: {
  document: SourceDocumentStatusResponse
  extracting: boolean
  extractionError?: boolean
  extractionMessage?: string | null
  onExtract: () => void
  retrying: boolean
  onRetry: () => void
}) {
  const scanFailed = document.scanStatus === 3 || document.scanStatus === 4
  const retryable = scanFailed && document.scanProvider === 0
  const cleanAndTrusted = isCleanAndTrusted(document)
  const extractionActive = isExtractionActive(document)
  const canStartExtraction = cleanAndTrusted && document.extractionStatus === 0
  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <p className="text-xs font-bold uppercase tracking-[0.16em] text-primary">Documento fuente</p>
            <CardTitle className="mt-1 flex items-center gap-2">
              <FileText className="size-5" aria-hidden />
              {document.fileName}
            </CardTitle>
          </div>
          <StatusBadge document={document} />
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        {document.scanProvider === 0 && <DevelopmentWarning />}
        {document.scanProvider === 1 && document.isProductionScan && <ProductionScanNotice />}
        {document.scanProvider === 1 && !document.isProductionScan && <DevelopmentWarning />}
        <dl className="grid gap-3 text-sm sm:grid-cols-2">
          <div><dt className="text-muted-foreground">Tamaño verificado</dt><dd className="font-semibold">{formatBytes(document.contentLength)}</dd></div>
          <div><dt className="text-muted-foreground">Almacenamiento</dt><dd className="font-semibold">{storageLabels[document.storageStatus]}</dd></div>
          <div><dt className="text-muted-foreground">Intento de análisis</dt><dd className="font-semibold">{document.scanAttemptCount}</dd></div>
          <div><dt className="text-muted-foreground">Fuente</dt><dd className="font-semibold">{document.fundingSourceName}</dd></div>
        </dl>
        {document.scanStatus === 0 && (
          <p className="flex items-center gap-2 text-sm text-muted-foreground" role="status">
            <LoaderCircle className="size-4 animate-spin" aria-hidden />
            El documento permanece aislado mientras esperamos un resultado confiable.
          </p>
        )}
        {document.scanStatus === 2 && (
          <p className="flex items-center gap-2 text-sm font-semibold text-destructive" role="alert">
            <ShieldAlert className="size-4" aria-hidden />
            El documento seguirá en cuarentena y nunca se usará para extracción.
          </p>
        )}
        {document.scanStatus === 1 && (
          <p className="flex items-center gap-2 text-sm text-primary">
            <ShieldCheck className="size-4" aria-hidden />
            El PDF está limpio. La extracción sólo se habilita cuando además está en almacenamiento confiable.
          </p>
        )}
        {retryable && (
          <Button disabled={retrying} onClick={onRetry} type="button" variant="outline">
            {retrying ? <LoaderCircle className="size-4 animate-spin" /> : <RefreshCw className="size-4" />}
            Reintentar análisis
          </Button>
        )}
        {scanFailed && document.scanProvider === 1 && (
          <p className="flex items-start gap-2 rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-950 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100" role="status">
            <AlertTriangle className="mt-0.5 size-4 shrink-0" aria-hidden />
            El reescaneo bajo demanda de Microsoft Defender no está habilitado. El documento permanece bloqueado; vuelve a cargarlo como un documento nuevo si necesitas analizar otra versión.
          </p>
        )}

        <section className="space-y-4 border-t pt-4" aria-labelledby="document-extraction-title">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h3 className="flex items-center gap-2 font-semibold" id="document-extraction-title">
                <DatabaseZap className="size-4 text-primary" aria-hidden />
                Extracción documental
              </h3>
              <p className="mt-1 text-sm text-muted-foreground">Extrae texto verificable para una revisión posterior, sin interpretar ni publicar contenido.</p>
            </div>
            <span className="rounded-full bg-muted px-2.5 py-1 text-xs font-semibold">
              {extractionLabels[document.extractionStatus]}
            </span>
          </div>

          {!cleanAndTrusted && document.extractionStatus === 0 && (
            <p className="flex items-start gap-2 rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-950 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100" role="status">
              <AlertTriangle className="mt-0.5 size-4 shrink-0" aria-hidden />
              Sólo puedes iniciar la extracción cuando el análisis sea Limpio y el almacenamiento sea Trusted.
            </p>
          )}
          {extractionActive && (
            <p className="flex items-center gap-2 text-sm text-muted-foreground" role="status">
              <LoaderCircle className="size-4 animate-spin" aria-hidden />
              La extracción de texto continúa en segundo plano. Esta vista se actualiza automáticamente.
            </p>
          )}
          {(document.extractionStatus === 3 || document.extractionStatus === 4) && (
            <div className="space-y-3 rounded-lg border bg-muted/40 p-4">
              {document.isContentRedacted ? (
                <p className="flex items-start gap-2 text-sm font-semibold text-muted-foreground" role="status">
                  <FileClock className="mt-0.5 size-4 shrink-0" aria-hidden />
                  El contenido extraído se eliminó al vencer la política de retención. Se conservan únicamente la trazabilidad y los comprobantes técnicos.
                </p>
              ) : (
                <p className="flex items-center gap-2 text-sm font-semibold text-primary" role="status">
                  <CheckCircle2 className="size-4" aria-hidden />
                  {document.extractionStatus === 3 ? 'Extracción completada.' : 'Extracción completada con observaciones.'}
                </p>
              )}
              <dl className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-3 xl:grid-cols-6">
                <div><dt className="text-muted-foreground">Páginas procesadas</dt><dd className="font-semibold">{document.extractedPageCount ?? 'Sin información'}</dd></div>
                <div><dt className="text-muted-foreground">Caracteres extraídos</dt><dd className="font-semibold">{document.extractedCharacterCount?.toLocaleString('es-CL') ?? 'Sin información'}</dd></div>
                <div><dt className="text-muted-foreground">Evidencias</dt><dd className="font-semibold">{document.extractionEvidenceCount}</dd></div>
                <div><dt className="text-muted-foreground">Errores seguros</dt><dd className="font-semibold">{document.extractionErrorCount}</dd></div>
                <div><dt className="text-muted-foreground">Intentos</dt><dd className="font-semibold">{document.extractionAttemptCount}{document.extractionMaxAttempts > 0 ? ` de ${document.extractionMaxAttempts}` : ''}</dd></div>
                <div><dt className="text-muted-foreground">Resultado</dt><dd className="font-semibold">{document.extractionResultCode ?? 'Completado'}</dd></div>
              </dl>
              {document.isContentRedacted && document.redactedAtUtc && (
                <p className="text-xs text-muted-foreground">
                  Redacción aplicada: {new Date(document.redactedAtUtc).toLocaleString('es-CL')}.
                </p>
              )}
            </div>
          )}
          {document.extractionStatus === 5 && (
            <p className="text-sm text-destructive" role="alert">La extracción agotó sus reintentos o falló de forma segura{document.extractionResultCode ? ` (${document.extractionResultCode})` : ''}. No se interpretó ni publicó contenido.</p>
          )}
          {document.extractionStatus === 6 && (
            <p className="text-sm text-muted-foreground" role="status">La extracción fue cancelada. El texto no se interpretó ni se publicó.</p>
          )}
          {extractionMessage && <p className={extractionError ? 'text-sm text-destructive' : 'text-sm'} role={extractionError ? 'alert' : 'status'}>{extractionMessage}</p>}
          <div className="flex flex-wrap gap-2">
            {canStartExtraction && (
              <Button disabled={extracting} onClick={onExtract} type="button">
                {extracting ? <LoaderCircle className="size-4 animate-spin" aria-hidden /> : <Play className="size-4" aria-hidden />}
                Iniciar extracción
              </Button>
            )}
          </div>
        </section>
      </CardContent>
    </Card>
  )
}

export function AdminSourceDocumentUploadPage() {
  const [file, setFile] = useState<File | null>(null)
  const [fundingSourceId, setFundingSourceId] = useState('')
  const [intentId, setIntentId] = useState<string | null>(null)
  const [completionToken, setCompletionToken] = useState<string | null>(null)
  const [operation, setOperation] = useState<SourceDocumentOperation | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [extractionMessage, setExtractionMessage] = useState<string | null>(null)
  const [uploadStage, setUploadStage] = useState<'idle' | 'authorizing' | 'uploading' | 'completing'>('idle')
  const sources = useQuery({
    queryKey: ['admin', 'funding-sources', 'source-document-upload'],
    queryFn: ({ signal }) => adminFundingSourcesApi.list(signal),
    staleTime: 60_000,
  })
  const uploadSources = useMemo(
    () => (sources.data ?? []).filter((source) => source.isEnabled && [0, 4].includes(source.providerType)),
    [sources.data],
  )

  useEffect(() => {
    if (!fundingSourceId && uploadSources.length > 0) {
      const preferred = uploadSources.find((source) => source.providerType === 4) ?? uploadSources[0]
      setFundingSourceId(String(preferred.id))
    }
  }, [fundingSourceId, uploadSources])

  const documentId = operation?.sourceDocumentId ?? null
  const documentQuery = useQuery({
    queryKey: ['admin', 'source-document', documentId],
    queryFn: ({ signal }) => sourceDocumentApi.getDocument(documentId!, signal),
    enabled: Boolean(documentId),
    refetchInterval: (query) => shouldPollDocument(query.state.data) ? 2_000 : false,
  })

  const upload = useMutation({
    mutationFn: async () => {
      if (!file || !fundingSourceId) throw new Error('invalid-selection')
      setUploadStage('authorizing')
      const created = await sourceDocumentApi.createIntent(Number(fundingSourceId), file)
      setUploadStage('uploading')
      await uploadFileDirectly(created, file)
      // The completion secret exists only in memory and only after a successful PUT.
      setIntentId(created.intentId)
      setCompletionToken(created.completionToken)
      setUploadStage('completing')
      return sourceDocumentApi.complete(created.intentId, created.completionToken)
    },
    onSuccess: (result) => {
      setOperation(result)
      if (result.sourceDocumentId) setCompletionToken(null)
      setMessage(result.scanStatus === 0
        ? 'El PDF está aislado y su análisis sigue pendiente.'
        : 'La carga y verificación terminaron.')
    },
    onError: (error) => setMessage(sourceDocumentErrorMessage(error)),
    onSettled: () => setUploadStage('idle'),
  })

  const resume = useMutation({
    mutationFn: () => {
      if (!intentId || !completionToken) throw new Error('completion-secret-lost')
      return sourceDocumentApi.complete(intentId, completionToken)
    },
    onSuccess: (result) => {
      setOperation(result)
      if (result.sourceDocumentId) setCompletionToken(null)
      setMessage('La verificación se reanudó correctamente.')
    },
    onError: (error) => setMessage(sourceDocumentErrorMessage(error)),
  })

  const retry = useMutation({
    mutationFn: () => {
      const document = documentQuery.data
      if (!document) throw new Error('document-not-loaded')
      return executeEditorialCommand(
        `source-document-scan-retry:${document.sourceDocumentId}`,
        { action: 'retry-scan', eTag: document.eTag },
        (idempotencyKey) => sourceDocumentApi.retry(
          document.sourceDocumentId,
          document.eTag,
          idempotencyKey,
        ),
      )
    },
    onSuccess: async (result) => {
      setOperation(result)
      setMessage(result.scanStatus === 0
        ? 'El nuevo análisis quedó pendiente.'
        : 'El nuevo análisis terminó.')
      await documentQuery.refetch()
    },
    onError: (error) => setMessage(sourceDocumentErrorMessage(error)),
  })

  const extract = useMutation({
    mutationFn: () => {
      const document = documentQuery.data
      if (!document || !isCleanAndTrusted(document)) throw new Error('document-not-trusted')
      if (document.extractionStatus !== 0) throw new Error('extraction-already-started')
      return executeEditorialCommand(
        `source-document-extraction:${document.sourceDocumentId}`,
        { action: 'start-extraction', eTag: document.eTag },
        (idempotencyKey) => sourceDocumentApi.startExtraction(
          document.sourceDocumentId,
          document.eTag,
          idempotencyKey,
        ),
      )
    },
    onSuccess: async (result) => {
      setExtractionMessage(result.wasReplay
        ? 'La extracción ya estaba solicitada; retomamos su seguimiento.'
        : 'La extracción documental quedó en cola correctamente.')
      await documentQuery.refetch()
    },
    onError: async (error) => {
      setExtractionMessage(error instanceof Error && error.message === 'document-not-trusted'
        ? 'Sólo un documento Clean y Trusted puede iniciar una extracción.'
        : sourceDocumentErrorMessage(error))
      if (error instanceof ApiError && (error.response.status === 409 || error.response.status === 412)) {
        await documentQuery.refetch()
      }
    },
  })

  function selectFile(event: ChangeEvent<HTMLInputElement>) {
    const selected = event.target.files?.[0] ?? null
    setFile(selected)
    setMessage(null)
    setIntentId(null)
    setCompletionToken(null)
    setOperation(null)
    setExtractionMessage(null)
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    if (!file) {
      setMessage('Selecciona un PDF.')
      return
    }
    if (file.type !== 'application/pdf' || !file.name.toLowerCase().endsWith('.pdf')) {
      setMessage('Sólo se admiten archivos PDF.')
      return
    }
    if (file.size < 1 || file.size > maxPdfBytes) {
      setMessage(`El PDF debe pesar como máximo ${formatBytes(maxPdfBytes)}.`)
      return
    }
    setMessage('Creando una autorización de carga de corta duración…')
    upload.mutate()
  }

  const busy = upload.isPending || resume.isPending
  const phase = upload.isPending
    ? uploadStage === 'authorizing'
      ? 'Creando autorización segura…'
      : uploadStage === 'uploading'
        ? 'Transfiriendo el PDF directamente a Azure…'
        : 'Verificando y aislando el PDF…'
    : resume.isPending ? 'Reanudando verificación…' : null

  return (
    <div className="space-y-6">
      <header>
        <p className="text-sm font-semibold text-primary">Administración · Documentos fuente</p>
        <h1 className="mt-1 text-3xl font-bold tracking-tight">Carga documental segura</h1>
        <p className="mt-2 max-w-3xl text-muted-foreground">Carga un PDF oficial directamente al almacenamiento temporal. El backend valida tamaño, formato y huella antes de aislarlo.</p>
      </header>

      <div className="grid gap-6 xl:grid-cols-[minmax(0,1.25fr)_minmax(20rem,0.75fr)]">
        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2"><UploadCloud className="size-5" />Nueva carga</CardTitle></CardHeader>
          <CardContent>
            <form className="space-y-5" onSubmit={submit}>
              <label className="grid gap-2 text-sm font-semibold">
                Fuente de procedencia
                <select
                  className="h-11 rounded-lg border bg-background px-3 text-sm"
                  disabled={busy || sources.isPending}
                  onChange={(event) => setFundingSourceId(event.target.value)}
                  value={fundingSourceId}
                >
                  <option value="">Selecciona una fuente</option>
                  {uploadSources.map((source) => <option key={source.id} value={source.id}>{source.name}</option>)}
                </select>
              </label>
              <label className="grid gap-2 text-sm font-semibold">
                Documento PDF
                <input
                  accept="application/pdf,.pdf"
                  className="rounded-lg border bg-background p-3 text-sm file:mr-3 file:rounded-md file:border-0 file:bg-accent file:px-3 file:py-2 file:font-semibold file:text-accent-foreground"
                  disabled={busy}
                  onChange={selectFile}
                  type="file"
                />
                <span className="text-xs font-normal text-muted-foreground">Máximo {formatBytes(maxPdfBytes)}. El SAS no decide el tamaño: el servidor lo vuelve a verificar.</span>
              </label>
              {file && <p className="rounded-lg bg-muted p-3 text-sm"><span className="font-semibold">{file.name}</span> · {formatBytes(file.size)}</p>}
              <Button disabled={busy || !file || !fundingSourceId} type="submit">
                {busy ? <LoaderCircle className="size-4 animate-spin" /> : <UploadCloud className="size-4" />}
                {busy ? 'Procesando…' : 'Cargar y verificar'}
              </Button>
            </form>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2"><ShieldCheck className="size-5" />Controles aplicados</CardTitle></CardHeader>
          <CardContent className="space-y-3 text-sm text-muted-foreground">
            <p>Autorización HTTPS para crear un único blob, con vencimiento corto.</p>
            <p>Transferencia directa sin enviar el JWT de la plataforma a Azure.</p>
            <p>Validación streaming del encabezado, cierre PDF, longitud y SHA-256.</p>
            <p>Cuarentena obligatoria; sólo un resultado limpio permite copiar a trusted.</p>
          </CardContent>
        </Card>
      </div>

      {(phase || message) && (
        <div className="flex items-center gap-3 rounded-xl border bg-card p-4 text-sm" role="status">
          {busy ? <LoaderCircle className="size-5 animate-spin text-primary" /> : <FileClock className="size-5 text-primary" />}
          <span>{phase ?? message}</span>
        </div>
      )}

      {upload.isError && intentId && completionToken && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-amber-300 bg-amber-50 p-4 dark:border-amber-800 dark:bg-amber-950">
          <p className="text-sm">El archivo llegó, pero falta completar la verificación. Puedes reanudar mientras esta pantalla siga abierta.</p>
          <Button disabled={resume.isPending} onClick={() => resume.mutate()} type="button" variant="outline">
            <RefreshCw className="size-4" />Reanudar
          </Button>
        </div>
      )}

      {documentId && documentQuery.isPending && (
        <p className="flex items-center gap-2 rounded-xl border bg-card p-4 text-sm text-muted-foreground" role="status"><LoaderCircle className="size-4 animate-spin" aria-hidden />Cargando verificación y extracción…</p>
      )}
      {documentQuery.data && !documentQuery.isError && (
        <DocumentStatusCard
          document={documentQuery.data}
          extracting={extract.isPending}
          extractionError={extract.isError}
          extractionMessage={extractionMessage}
          onExtract={() => extract.mutate()}
          onRetry={() => retry.mutate()}
          retrying={retry.isPending}
        />
      )}
      {documentQuery.isError && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm text-destructive" role="alert">
          <span>{sourceDocumentErrorMessage(documentQuery.error)}</span>
          <Button onClick={() => void documentQuery.refetch()} type="button" variant="outline"><RefreshCw className="size-4" />Reintentar</Button>
        </div>
      )}
      {operation?.isDevelopmentScan && !documentQuery.data && <DevelopmentWarning />}
      {intentId && (
        <p className="text-xs text-muted-foreground">Si recargas antes de completar, la credencial en memoria se pierde: crea una carga nueva. La autorización anterior vencerá automáticamente.</p>
      )}
    </div>
  )
}

export function AdminSourceDocumentDetailPage() {
  const { id } = useParams()
  const intent = useQuery({
    queryKey: ['admin', 'source-document-upload-intent', id],
    queryFn: ({ signal }) => sourceDocumentApi.getIntent(id!, signal),
    enabled: Boolean(id),
    refetchInterval: (query) => query.state.data?.status === 1 ? 2_000 : false,
  })
  const value = intent.data
  const document = useQuery({
    queryKey: ['admin', 'source-document', value?.sourceDocumentId],
    queryFn: ({ signal }) => sourceDocumentApi.getDocument(value!.sourceDocumentId!, signal),
    enabled: Boolean(value?.sourceDocumentId),
    refetchInterval: (query) => shouldPollDocument(query.state.data) ? 2_000 : false,
  })
  const retry = useMutation({
    mutationFn: () => executeEditorialCommand(
      `source-document-scan-retry:${document.data!.sourceDocumentId}`,
      { action: 'retry-scan', eTag: document.data!.eTag },
      (idempotencyKey) => sourceDocumentApi.retry(
        document.data!.sourceDocumentId,
        document.data!.eTag,
        idempotencyKey,
      ),
    ),
    onSuccess: () => document.refetch(),
  })
  const extraction = useMutation({
    mutationFn: () => {
      const current = document.data
      if (!current || !isCleanAndTrusted(current)) throw new Error('document-not-trusted')
      if (current.extractionStatus !== 0) throw new Error('extraction-already-started')
      return executeEditorialCommand(
        `source-document-extraction:${current.sourceDocumentId}`,
        { action: 'start-extraction', eTag: current.eTag },
        (idempotencyKey) => sourceDocumentApi.startExtraction(
          current.sourceDocumentId,
          current.eTag,
          idempotencyKey,
        ),
      )
    },
    onSuccess: () => document.refetch(),
    onError: async (error) => {
      if (error instanceof ApiError && (error.response.status === 409 || error.response.status === 412)) {
        await document.refetch()
      }
    },
  })

  if (intent.isPending) return <p className="flex items-center gap-2"><LoaderCircle className="size-4 animate-spin" />Cargando estado…</p>
  if (intent.isError || !value) return (
    <div className="space-y-4" role="alert">
      <h1 className="text-2xl font-bold">No fue posible abrir la carga</h1>
      <p className="text-muted-foreground">{sourceDocumentErrorMessage(intent.error)}</p>
      <Button asChild variant="outline"><Link to="/admin/imports">Volver a importaciones</Link></Button>
    </div>
  )

  return (
    <div className="space-y-6">
      <header>
        <p className="text-sm font-semibold text-primary">Administración · Trazabilidad</p>
        <h1 className="mt-1 text-3xl font-bold tracking-tight">{value.fileName}</h1>
        <p className="mt-2 text-muted-foreground">{intentLabels[value.status]} · {formatBytes(value.expectedContentLength)}</p>
      </header>
      {value.isDevelopmentScan && !document.data && <DevelopmentWarning />}
      {value.sourceDocumentId && document.isPending && (
        <p className="flex items-center gap-2 rounded-xl border bg-card p-4 text-sm text-muted-foreground" role="status"><LoaderCircle className="size-4 animate-spin" aria-hidden />Cargando verificación y extracción…</p>
      )}
      {document.data && !document.isError && (
        <DocumentStatusCard
            document={document.data}
            extracting={extraction.isPending}
            extractionError={extraction.isError}
            extractionMessage={extraction.isSuccess
              ? 'La extracción documental se inició correctamente.'
              : extraction.isError ? sourceDocumentErrorMessage(extraction.error) : null}
            onExtract={() => extraction.mutate()}
            onRetry={() => retry.mutate()}
            retrying={retry.isPending}
          />
      )}
      {!value.sourceDocumentId && (
        <Card><CardContent className="flex items-center gap-3 pt-6 text-sm text-muted-foreground"><FileClock className="size-5" />Todavía no existe un documento verificado para esta carga.</CardContent></Card>
      )}
      {document.isError && (
        <div className="space-y-3 rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm text-destructive" role="alert">
          <p>{sourceDocumentErrorMessage(document.error)}</p>
          <Button onClick={() => void document.refetch()} type="button" variant="outline"><RefreshCw className="size-4" />Reintentar</Button>
        </div>
      )}
      {retry.isError && <p className="text-sm text-destructive" role="alert">{sourceDocumentErrorMessage(retry.error)}</p>}
      <Button asChild variant="outline"><Link to="/admin/imports">Volver a importaciones</Link></Button>
    </div>
  )
}
