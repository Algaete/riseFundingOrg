import { workspaceLocale } from '@/i18n/workspace-messages'
import { formatDateValue } from '@/i18n/formats'
import i18n from '@/i18n'
import { documentOperationsErrorKey, operationsMessage, operationStatus, type OperationsKey } from '@/i18n/operations-messages'
import { useTranslation } from 'react-i18next'
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
  type SourceDocumentOperation,
  type SourceDocumentStatusResponse,
  uploadFileDirectly,
} from '@/features/source-documents/source-document-api'

const maxPdfBytes = 26_214_400

const scanLabels = {
  0: 'sourceDocuments.scanPending',
  1: 'sourceDocuments.clean',
  2: 'sourceDocuments.malicious',
  3: 'sourceDocuments.scanFailed',
  4: 'sourceDocuments.scanTimeout',
} as const

const storageLabels = {
  0: 'sourceDocuments.awaitingQuarantine',
  1: 'sourceDocuments.quarantine',
  2: 'sourceDocuments.trusted',
  3: 'sourceDocuments.storageFailed',
} as const

const intentLabels = {
  0: 'sourceDocuments.awaitingFile',
  1: 'sourceDocuments.verifyingFile',
  2: 'sourceDocuments.uploadComplete',
  3: 'sourceDocuments.expired',
  4: 'sourceDocuments.rejected',
} as const

const extractionLabels = {
  0: 'sourceDocuments.notStarted',
  1: 'operations.queued',
  2: 'sourceDocuments.extracting',
  3: 'operations.completed',
  4: 'operations.observations',
  5: 'operations.failed',
  6: 'operations.cancelled',
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
  return new Intl.NumberFormat(workspaceLocale(), {
    maximumFractionDigits: 1,
    style: 'unit',
    unit: value >= 1024 * 1024 ? 'megabyte' : 'kilobyte',
    unitDisplay: 'short',
  }).format(value >= 1024 * 1024 ? value / (1024 * 1024) : value / 1024)
}

function StatusBadge({ document }: { document: SourceDocumentStatusResponse }) {
  useTranslation()
  const className = document.scanStatus === 1
    ? 'bg-accent text-accent-foreground'
    : document.scanStatus === 2
      ? 'bg-destructive/10 text-foreground'
      : document.scanStatus >= 3
        ? 'bg-amber-100 text-amber-900 dark:bg-amber-950 dark:text-amber-100'
        : 'bg-muted text-muted-foreground'
  return (
    <span className={`rounded-full px-3 py-1 text-xs font-semibold ${className}`}>
      {operationStatus(scanLabels, document.scanStatus)}
    </span>
  )
}

function DevelopmentWarning() {
  useTranslation()
  return (
    <div className="flex gap-3 rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm text-amber-950 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100" role="status">
      <AlertTriangle className="mt-0.5 size-5 shrink-0" aria-hidden />
      <div>
        <p className="font-semibold">{i18n.t('sourceDocuments.developmentTitle')}</p>
        <p className="mt-1">{i18n.t('sourceDocuments.developmentHelp')}</p>
      </div>
    </div>
  )
}

function ProductionScanNotice() {
  useTranslation()
  return (
    <div className="flex gap-3 rounded-xl border border-emerald-300 bg-emerald-50 p-4 text-sm text-emerald-950 dark:border-emerald-800 dark:bg-emerald-950 dark:text-emerald-100" role="status">
      <ShieldCheck className="mt-0.5 size-5 shrink-0" aria-hidden />
      <div>
        <p className="font-semibold">{i18n.t('sourceDocuments.productionTitle')}</p>
        <p className="mt-1">{i18n.t('sourceDocuments.productionHelp')}</p>
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
  extractionMessage?: OperationsKey | null
  onExtract: () => void
  retrying: boolean
  onRetry: () => void
}) {
  useTranslation()
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
            <p className="text-xs font-bold uppercase tracking-[0.16em] text-primary">{i18n.t('sourceDocuments.document')}</p>
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
          <div><dt className="text-muted-foreground">{i18n.t('sourceDocuments.verifiedSize')}</dt><dd className="font-semibold">{formatBytes(document.contentLength)}</dd></div>
          <div><dt className="text-muted-foreground">{i18n.t('sourceDocuments.storage')}</dt><dd className="font-semibold">{operationStatus(storageLabels, document.storageStatus)}</dd></div>
          <div><dt className="text-muted-foreground">{i18n.t('sourceDocuments.scanAttempt')}</dt><dd className="font-semibold">{document.scanAttemptCount}</dd></div>
          <div><dt className="text-muted-foreground">{i18n.t('operations.source')}</dt><dd className="font-semibold">{document.fundingSourceName}</dd></div>
        </dl>
        {document.scanStatus === 0 && (
          <p className="flex items-center gap-2 text-sm text-muted-foreground" role="status">
            <LoaderCircle className="size-4 animate-spin" aria-hidden />
            {i18n.t('sourceDocuments.isolated')}
          </p>
        )}
        {document.scanStatus === 2 && (
          <p className="flex items-center gap-2 text-sm font-semibold text-foreground" role="alert">
            <ShieldAlert className="size-4" aria-hidden />
            {i18n.t('sourceDocuments.blockedMalware')}
          </p>
        )}
        {document.scanStatus === 1 && (
          <p className="flex items-center gap-2 text-sm text-primary">
            <ShieldCheck className="size-4" aria-hidden />
            {i18n.t('sourceDocuments.cleanHelp')}
          </p>
        )}
        {retryable && (
          <Button disabled={retrying} onClick={onRetry} type="button" variant="outline">
            {retrying ? <LoaderCircle className="size-4 animate-spin" /> : <RefreshCw className="size-4" />}
            {i18n.t('sourceDocuments.retryScan')}
          </Button>
        )}
        {scanFailed && document.scanProvider === 1 && (
          <p className="flex items-start gap-2 rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-950 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100" role="status">
            <AlertTriangle className="mt-0.5 size-4 shrink-0" aria-hidden />
            {i18n.t('sourceDocuments.defenderRetryBlocked')}
          </p>
        )}

        <section className="space-y-4 border-t pt-4" aria-labelledby="document-extraction-title">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h3 className="flex items-center gap-2 font-semibold" id="document-extraction-title">
                <DatabaseZap className="size-4 text-primary" aria-hidden />
                {i18n.t('sourceDocuments.extraction')}
              </h3>
              <p className="mt-1 text-sm text-muted-foreground">{i18n.t('sourceDocuments.extractionHelp')}</p>
            </div>
            <span className="rounded-full bg-muted px-2.5 py-1 text-xs font-semibold">
              {operationStatus(extractionLabels, document.extractionStatus)}
            </span>
          </div>

          {!cleanAndTrusted && document.extractionStatus === 0 && (
            <p className="flex items-start gap-2 rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-950 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100" role="status">
              <AlertTriangle className="mt-0.5 size-4 shrink-0" aria-hidden />
              {i18n.t('sourceDocuments.trustedRequired')}
            </p>
          )}
          {extractionActive && (
            <p className="flex items-center gap-2 text-sm text-muted-foreground" role="status">
              <LoaderCircle className="size-4 animate-spin" aria-hidden />
              {i18n.t('sourceDocuments.backgroundExtraction')}
            </p>
          )}
          {(document.extractionStatus === 3 || document.extractionStatus === 4) && (
            <div className="space-y-3 rounded-lg border bg-muted/40 p-4">
              {document.isContentRedacted ? (
                <p className="flex items-start gap-2 text-sm font-semibold text-muted-foreground" role="status">
                  <FileClock className="mt-0.5 size-4 shrink-0" aria-hidden />
                  {i18n.t('sourceDocuments.redacted')}
                </p>
              ) : (
                <p className="flex items-center gap-2 text-sm font-semibold text-primary" role="status">
                  <CheckCircle2 className="size-4" aria-hidden />
                  {document.extractionStatus === 3 ? i18n.t('sourceDocuments.extractionComplete') : i18n.t('sourceDocuments.extractionObservations')}
                </p>
              )}
              <dl className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-3 xl:grid-cols-6">
                <div><dt className="text-muted-foreground">{i18n.t('sourceDocuments.pages')}</dt><dd className="font-semibold">{document.extractedPageCount ?? i18n.t('operations.noInfo')}</dd></div>
                <div><dt className="text-muted-foreground">{i18n.t('sourceDocuments.characters')}</dt><dd className="font-semibold">{document.extractedCharacterCount?.toLocaleString(workspaceLocale()) ?? i18n.t('operations.noInfo')}</dd></div>
                <div><dt className="text-muted-foreground">{i18n.t('adminFunding.evidence')}</dt><dd className="font-semibold">{document.extractionEvidenceCount}</dd></div>
                <div><dt className="text-muted-foreground">{i18n.t('sourceDocuments.safeErrors')}</dt><dd className="font-semibold">{document.extractionErrorCount}</dd></div>
                <div><dt className="text-muted-foreground">{i18n.t('sourceDocuments.attempts')}</dt><dd className="font-semibold">{document.extractionMaxAttempts > 0 ? i18n.t('operations.numberOf', { value: document.extractionAttemptCount, total: document.extractionMaxAttempts }) : document.extractionAttemptCount}</dd></div>
                <div><dt className="text-muted-foreground">{i18n.t('sourceDocuments.result')}</dt><dd className="font-semibold">{document.extractionResultCode ?? i18n.t('operations.itemCompleted')}</dd></div>
              </dl>
              {document.isContentRedacted && document.redactedAtUtc && (
                <p className="text-xs text-muted-foreground">
                  {i18n.t('sourceDocuments.redactedAt', { date: formatDateValue(document.redactedAtUtc, { dateStyle: 'medium', timeStyle: 'short' }) })}
                </p>
              )}
            </div>
          )}
          {document.extractionStatus === 5 && (
            <p className="text-sm text-foreground" role="alert">{i18n.t('sourceDocuments.extractionFailed', { code: document.extractionResultCode ? ` (${document.extractionResultCode})` : '' })}</p>
          )}
          {document.extractionStatus === 6 && (
            <p className="text-sm text-muted-foreground" role="status">{i18n.t('sourceDocuments.extractionCancelled')}</p>
          )}
          {extractionMessage && <p className={extractionError ? 'text-sm text-foreground' : 'text-sm'} role={extractionError ? 'alert' : 'status'}>{operationsMessage(extractionMessage)}</p>}
          <div className="flex flex-wrap gap-2">
            {canStartExtraction && (
              <Button disabled={extracting} onClick={onExtract} type="button">
                {extracting ? <LoaderCircle className="size-4 animate-spin" aria-hidden /> : <Play className="size-4" aria-hidden />}
                {i18n.t('sourceDocuments.startExtraction')}
              </Button>
            )}
          </div>
        </section>
      </CardContent>
    </Card>
  )
}

export function AdminSourceDocumentUploadPage() {
  useTranslation()
  const [file, setFile] = useState<File | null>(null)
  const [fundingSourceId, setFundingSourceId] = useState('')
  const [intentId, setIntentId] = useState<string | null>(null)
  const [completionToken, setCompletionToken] = useState<string | null>(null)
  const [operation, setOperation] = useState<SourceDocumentOperation | null>(null)
  const [message, setMessage] = useState<OperationsKey | null>(null)
  const [extractionMessage, setExtractionMessage] = useState<OperationsKey | null>(null)
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
        ? 'sourceDocuments.scanPendingMessage'
        : 'sourceDocuments.verifiedMessage')
    },
    onError: (error) => setMessage(documentOperationsErrorKey(error)),
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
      setMessage('sourceDocuments.verificationResumed')
    },
    onError: (error) => setMessage(documentOperationsErrorKey(error)),
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
        ? 'sourceDocuments.newScanPending'
        : 'sourceDocuments.newScanComplete')
      await documentQuery.refetch()
    },
    onError: (error) => setMessage(documentOperationsErrorKey(error)),
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
        ? 'sourceDocuments.extractionReplay'
        : 'sourceDocuments.extractionQueued')
      await documentQuery.refetch()
    },
    onError: async (error) => {
      setExtractionMessage(error instanceof Error && error.message === 'document-not-trusted'
        ? 'sourceDocuments.cleanTrustedRequired'
        : documentOperationsErrorKey(error))
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
      setMessage('sourceDocuments.choosePdf')
      return
    }
    if (file.type !== 'application/pdf' || !file.name.toLowerCase().endsWith('.pdf')) {
      setMessage('sourceDocuments.onlyPdf')
      return
    }
    if (file.size < 1 || file.size > maxPdfBytes) {
      setMessage('sourceDocuments.maxSize')
      return
    }
    setMessage('sourceDocuments.shortAuthorization')
    upload.mutate()
  }

  const busy = upload.isPending || resume.isPending
  const phase = upload.isPending
    ? uploadStage === 'authorizing'
      ? i18n.t('sourceDocuments.authorizing')
      : uploadStage === 'uploading'
        ? i18n.t('sourceDocuments.transferring')
        : i18n.t('sourceDocuments.verifying')
    : resume.isPending ? i18n.t('sourceDocuments.resuming') : null

  return (
    <div className="min-w-0 space-y-6">
      <header>
        <p className="text-sm font-semibold text-primary">{i18n.t('sourceDocuments.eyebrow')}</p>
        <h1 className="mt-1 text-3xl font-bold tracking-tight">{i18n.t('sourceDocuments.title')}</h1>
        <p className="mt-2 max-w-3xl text-muted-foreground">{i18n.t('sourceDocuments.intro')}</p>
      </header>

      <div className="grid gap-6 xl:grid-cols-[minmax(0,1.25fr)_minmax(20rem,0.75fr)]">
        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2"><UploadCloud className="size-5" />{i18n.t('sourceDocuments.new')}</CardTitle></CardHeader>
          <CardContent>
            {sources.isPending && <p className="mb-4 text-sm" role="status">{i18n.t('adminImports.loadingSources')}</p>}
            {sources.isError && <div className="mb-4 space-y-3 rounded-lg bg-destructive/10 p-4 text-sm text-foreground" role="alert">
              <p>{operationsMessage(documentOperationsErrorKey(sources.error))}</p>
              <Button onClick={() => void sources.refetch()} type="button" variant="outline">{i18n.t('editorial.retry')}</Button>
            </div>}
            <form className="space-y-5" onSubmit={submit}>
              <label className="grid gap-2 text-sm font-semibold">
                {i18n.t('sourceDocuments.source')}
                <select
                  className="h-11 rounded-lg border bg-background px-3 text-sm"
                  disabled={busy || sources.isPending}
                  onChange={(event) => setFundingSourceId(event.target.value)}
                  value={fundingSourceId}
                >
                  <option value="">{i18n.t('adminFunding.chooseSource')}</option>
                  {uploadSources.map((source) => <option key={source.id} value={source.id}>{source.name}</option>)}
                </select>
              </label>
              <label className="grid gap-2 text-sm font-semibold">
                {i18n.t('sourceDocuments.pdf')}
                <input
                  accept="application/pdf,.pdf"
                  className="min-w-0 w-full max-w-full rounded-lg border bg-background p-3 text-sm file:mr-3 file:rounded-md file:border-0 file:bg-accent file:px-3 file:py-2 file:font-semibold file:text-accent-foreground"
                  disabled={busy}
                  onChange={selectFile}
                  type="file"
                />
                <span className="text-xs font-normal text-muted-foreground">{i18n.t('sourceDocuments.maxHelp', { size: formatBytes(maxPdfBytes) })}</span>
              </label>
              {file && <p className="rounded-lg bg-muted p-3 text-sm"><span className="font-semibold">{file.name}</span> · {formatBytes(file.size)}</p>}
              <Button disabled={busy || !file || !fundingSourceId} type="submit">
                {busy ? <LoaderCircle className="size-4 animate-spin" /> : <UploadCloud className="size-4" />}
                {busy ? i18n.t('operations.processing') : i18n.t('sourceDocuments.upload')}
              </Button>
            </form>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2"><ShieldCheck className="size-5" />{i18n.t('sourceDocuments.controls')}</CardTitle></CardHeader>
          <CardContent className="space-y-3 text-sm text-muted-foreground">
            <p>{i18n.t('sourceDocuments.authorizationHelp')}</p>
            <p>{i18n.t('sourceDocuments.transferHelp')}</p>
            <p>{i18n.t('sourceDocuments.verificationHelp')}</p>
            <p>{i18n.t('sourceDocuments.quarantineHelp')}</p>
          </CardContent>
        </Card>
      </div>

      {(phase || message) && (
        <div className="flex items-center gap-3 rounded-xl border bg-card p-4 text-sm" role="status">
          {busy ? <LoaderCircle className="size-5 animate-spin text-primary" /> : <FileClock className="size-5 text-primary" />}
          <span>{phase ?? (message ? operationsMessage(message, { size: formatBytes(maxPdfBytes) }) : null)}</span>
        </div>
      )}

      {upload.isError && intentId && completionToken && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-amber-300 bg-amber-50 p-4 dark:border-amber-800 dark:bg-amber-950">
          <p className="text-sm">{i18n.t('sourceDocuments.resumeHelp')}</p>
          <Button disabled={resume.isPending} onClick={() => resume.mutate()} type="button" variant="outline">
            <RefreshCw className="size-4" />{i18n.t('sourceDocuments.resume')}
          </Button>
        </div>
      )}

      {documentId && documentQuery.isPending && (
        <p className="flex items-center gap-2 rounded-xl border bg-card p-4 text-sm text-muted-foreground" role="status"><LoaderCircle className="size-4 animate-spin" aria-hidden />{i18n.t('sourceDocuments.loadingVerification')}</p>
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
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm text-foreground" role="alert">
          <span>{operationsMessage(documentOperationsErrorKey(documentQuery.error))}</span>
          <Button onClick={() => void documentQuery.refetch()} type="button" variant="outline"><RefreshCw className="size-4" />{i18n.t('editorial.retry')}</Button>
        </div>
      )}
      {operation?.isDevelopmentScan && !documentQuery.data && <DevelopmentWarning />}
      {intentId && (
        <p className="text-xs text-muted-foreground">{i18n.t('sourceDocuments.memoryHelp')}</p>
      )}
    </div>
  )
}

export function AdminSourceDocumentDetailPage() {
  useTranslation()
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

  if (intent.isPending) return <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-4 animate-spin" />{i18n.t('sourceDocuments.loading')}</p>
  if (intent.isError || !value) return (
    <div className="space-y-4" role="alert">
      <h1 className="text-2xl font-bold">{i18n.t('sourceDocuments.openFailed')}</h1>
      <p className="text-muted-foreground">{operationsMessage(documentOperationsErrorKey(intent.error))}</p>
      <Button asChild variant="outline"><Link to="/admin/imports">{i18n.t('adminImports.back')}</Link></Button>
    </div>
  )

  return (
    <div className="min-w-0 space-y-6">
      <header>
        <p className="text-sm font-semibold text-primary">{i18n.t('sourceDocuments.traceability')}</p>
        <h1 className="mt-1 text-3xl font-bold tracking-tight">{value.fileName}</h1>
        <p className="mt-2 text-muted-foreground">{operationStatus(intentLabels, value.status)} · {formatBytes(value.expectedContentLength)}</p>
      </header>
      {value.isDevelopmentScan && !document.data && <DevelopmentWarning />}
      {value.sourceDocumentId && document.isPending && (
        <p className="flex items-center gap-2 rounded-xl border bg-card p-4 text-sm text-muted-foreground" role="status"><LoaderCircle className="size-4 animate-spin" aria-hidden />{i18n.t('sourceDocuments.loadingVerification')}</p>
      )}
      {document.data && !document.isError && (
        <DocumentStatusCard
            document={document.data}
            extracting={extraction.isPending}
            extractionError={extraction.isError}
            extractionMessage={extraction.isSuccess
              ? 'sourceDocuments.extractionStarted'
              : extraction.isError ? documentOperationsErrorKey(extraction.error) : null}
            onExtract={() => extraction.mutate()}
            onRetry={() => retry.mutate()}
            retrying={retry.isPending}
          />
      )}
      {!value.sourceDocumentId && (
        <Card><CardContent className="flex items-center gap-3 pt-6 text-sm text-muted-foreground"><FileClock className="size-5" />{i18n.t('sourceDocuments.noDocument')}</CardContent></Card>
      )}
      {document.isError && (
        <div className="space-y-3 rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm text-foreground" role="alert">
          <p>{operationsMessage(documentOperationsErrorKey(document.error))}</p>
          <Button onClick={() => void document.refetch()} type="button" variant="outline"><RefreshCw className="size-4" />{i18n.t('editorial.retry')}</Button>
        </div>
      )}
      {retry.isError && <p className="text-sm text-foreground" role="alert">{operationsMessage(documentOperationsErrorKey(retry.error))}</p>}
      <Button asChild variant="outline"><Link to="/admin/imports">{i18n.t('adminImports.back')}</Link></Button>
    </div>
  )
}
