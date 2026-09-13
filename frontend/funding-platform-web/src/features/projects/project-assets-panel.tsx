import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  ArrowDown,
  ArrowUp,
  CheckCircle2,
  Download,
  FileText,
  Image as ImageIcon,
  LoaderCircle,
  Save,
  ShieldAlert,
  Trash2,
  UploadCloud,
  RefreshCw,
} from 'lucide-react'
import {
  useEffect,
  useRef,
  useState,
  type ChangeEvent,
} from 'react'

import { useTranslation } from 'react-i18next'
import i18n from '@/i18n'
import { workspaceMessage, workspaceLocale } from '@/i18n/workspace-messages'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import {
  projectAssetApi,
  projectAssetErrorMessage,
  projectAssetQueryKey,
  type ProjectAsset,
  type ProjectAssetMetadataInput,
  type ProjectAssetUploadIntent,
  uploadProjectAssetDirectly,
} from '@/features/projects/project-assets-api'
import {
  isProjectAssetsEnabled,
  projectAssetAccept,
  projectAssetLimits,
} from '@/features/projects/project-assets-config'
import { projectAssetPollingIntervalMs, useProjectAssetPolling } from './use-project-asset-polling'

type AssetFeedback = string
  | { key: 'projectAssets.fileSize'; values: { name: string; maximum: number } }
  | { key: 'projectAssets.maxAttachments' | 'projectAssets.maxImages' | 'projectAssets.maxDocuments'; values: { count: number } }

type UploadPhase = 'authorizing' | 'uploading' | 'analyzing' | 'ready' | 'error'

interface UploadTask {
  id: string
  fileName: string
  phase: UploadPhase
  detail: AssetFeedback
  intentId?: string
  assetId?: string
}

interface ProjectAssetsPanelProps {
  organizationId: string
  projectId: string
  projectETag: string
  publicationStatus: number
  hasUnsavedChanges: boolean
  onProjectChanged: () => Promise<unknown>
}

const textareaClass = 'min-h-20 w-full rounded-lg border bg-background px-3 py-2 text-sm'

function formatBytes(value: number) {
  return new Intl.NumberFormat(workspaceLocale(), {
    maximumFractionDigits: 1,
    style: 'unit',
    unit: value >= 1024 * 1024 ? 'megabyte' : 'kilobyte',
    unitDisplay: 'short',
  }).format(value >= 1024 * 1024 ? value / (1024 * 1024) : value / 1024)
}

function displayAssetMessage(message: AssetFeedback) {
  if (typeof message === 'string') return workspaceMessage(message)
  if (message.key === 'projectAssets.fileSize') {
    return i18n.t(message.key, { name: message.values.name, maximum: formatBytes(message.values.maximum) })
  }
  return i18n.t(message.key, { count: message.values.count })
}

function assetIsReady(asset: ProjectAsset) {
  return asset.isReady && asset.storageStatus === 2 && asset.scanStatus === 1
}

function isAssetStillProcessing(asset: ProjectAsset) {
  return asset.storageStatus < 2 && asset.storageStatus !== 3 && asset.scanStatus === 0
}

function fileKind(file: File): 0 | 1 | 2 | null {
  const name = file.name.toLocaleLowerCase('en-US')
  if (
    (file.type === 'image/jpeg' && (name.endsWith('.jpg') || name.endsWith('.jpeg'))) ||
    (file.type === 'image/png' && name.endsWith('.png')) ||
    (file.type === 'image/webp' && name.endsWith('.webp'))
  ) return 0
  if (file.type === 'application/pdf' && name.endsWith('.pdf')) return 1
  if (file.type === 'text/plain' && name.endsWith('.txt')) return 1
  if (file.type === 'video/mp4' && name.endsWith('.mp4')) return 2
  return null
}

function validateFiles(files: File[], current: ProjectAsset[]): AssetFeedback | null {
  if (files.length === 0) return 'projectAssets.selectFile'
  const kinds = files.map(fileKind)
  if (kinds.some(kind => kind === null)) {
    return 'projectAssets.fileTypes'
  }
  const oversized = files.find((file, index) => {
    const maximum = kinds[index] === 0
      ? projectAssetLimits.imageBytes
      : file.type === 'text/plain' ? projectAssetLimits.textBytes : projectAssetLimits.documentBytes
    return file.size < 1 || file.size > maximum
  })
  if (oversized) {
    const maximum = fileKind(oversized) === 0
      ? projectAssetLimits.imageBytes
      : oversized.type === 'text/plain' ? projectAssetLimits.textBytes : projectAssetLimits.documentBytes
    return { key: 'projectAssets.fileSize', values: { name: oversized.name, maximum } }
  }
  const currentImages = current.filter(item => item.kind === 0).length
  const currentDocuments = current.filter(item => item.kind !== 0).length
  const newImages = kinds.filter(kind => kind === 0).length
  const newDocuments = kinds.filter(kind => kind !== 0).length
  if (current.length + files.length > projectAssetLimits.totalPerProject) {
    return { key: 'projectAssets.maxAttachments', values: { count: projectAssetLimits.totalPerProject } }
  }
  if (currentImages + newImages > projectAssetLimits.imagesPerProject) {
    return { key: 'projectAssets.maxImages', values: { count: projectAssetLimits.imagesPerProject } }
  }
  if (currentDocuments + newDocuments > projectAssetLimits.documentsPerProject) {
    return { key: 'projectAssets.maxDocuments', values: { count: projectAssetLimits.documentsPerProject } }
  }
  return null
}

function uploadPhaseLabel(task: UploadTask) {
  if (task.phase === 'authorizing') return 'projectAssets.authorizing'
  if (task.phase === 'uploading') return 'projectAssets.uploading'
  if (task.phase === 'analyzing') return 'projectAssets.analyzing'
  if (task.phase === 'ready') return 'projectAssets.ready'
  return 'projectAssets.error'
}

function intentOutcome(intent: ProjectAssetUploadIntent): 'pending' | 'ready' | 'rejected' {
  if (intent.status === 3 || intent.status === 4) return 'rejected'
  if (intent.scanStatus === 2 || intent.scanStatus === 3 || intent.scanStatus === 4) return 'rejected'
  if (intent.status === 2 && intent.storageStatus === 2 && intent.scanStatus === 1) return 'ready'
  return 'pending'
}

function SecureProjectImage({
  organizationId,
  projectId,
  asset,
}: {
  organizationId: string
  projectId: string
  asset: ProjectAsset
}) {
  const { t } = useTranslation()
  const [source, setSource] = useState<string | null>(null)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    const controller = new AbortController()
    let objectUrl: string | null = null
    setSource(null)
    setFailed(false)
    void projectAssetApi.getContent(
      organizationId,
      projectId,
      asset.assetId,
      controller.signal,
    ).then(({ blob }) => {
      if (controller.signal.aborted) return
      objectUrl = URL.createObjectURL(blob)
      setSource(objectUrl)
    }).catch(() => {
      if (!controller.signal.aborted) setFailed(true)
    })
    return () => {
      controller.abort()
      if (objectUrl) URL.revokeObjectURL(objectUrl)
    }
  }, [asset.assetId, asset.eTag, organizationId, projectId])

  if (failed) return <p className="p-4 text-sm text-muted-foreground">{t('projectAssets.previewFailed')}</p>
  if (!source) return <p className="flex items-center gap-2 p-4 text-sm text-muted-foreground"><LoaderCircle aria-hidden className="size-4 animate-spin" /> {t('projectAssets.previewLoading')}</p>
  return <img alt={asset.altText ?? ''} className="h-48 w-full object-cover" src={source} />
}

function AssetStatus({ asset }: { asset: ProjectAsset }) {
  const { t } = useTranslation()
  if (assetIsReady(asset)) {
    return <span className="flex items-center gap-1 text-xs font-semibold text-primary"><CheckCircle2 aria-hidden className="size-4" /> {t('projectAssets.verified')}</span>
  }
  if (asset.scanStatus === 2) {
    return <span className="flex items-center gap-1 text-xs font-semibold text-destructive"><ShieldAlert aria-hidden className="size-4" /> {t('projectAssets.rejected')}</span>
  }
  if (asset.scanStatus >= 3 || asset.storageStatus === 3) {
    return <span className="flex items-center gap-1 text-xs font-semibold text-destructive"><ShieldAlert aria-hidden className="size-4" /> {t('projectAssets.failedVerification')}</span>
  }
  return <span className="flex items-center gap-1 text-xs text-muted-foreground"><LoaderCircle aria-hidden className="size-4 animate-spin" /> {t('projectAssets.quarantined')}</span>
}

function AssetCard({
  asset,
  organizationId,
  projectId,
  editable,
  first,
  last,
  busy,
  deleting,
  onDelete,
  onMove,
  onSave,
}: {
  asset: ProjectAsset
  organizationId: string
  projectId: string
  editable: boolean
  first: boolean
  last: boolean
  busy: boolean
  deleting: boolean
  onDelete: (asset: ProjectAsset) => void
  onMove: (asset: ProjectAsset, direction: -1 | 1) => void
  onSave: (asset: ProjectAsset, input: ProjectAssetMetadataInput) => void
}) {
  const { t } = useTranslation()
  const [displayName, setDisplayName] = useState(asset.displayName)
  const [altText, setAltText] = useState(asset.altText ?? '')
  const [caption, setCaption] = useState(asset.caption ?? '')
  const [isCover, setIsCover] = useState(asset.isCover)
  const [metadataError, setMetadataError] = useState<string | null>(null)
  const [downloadError, setDownloadError] = useState<string | null>(null)
  const [downloading, setDownloading] = useState(false)
  const ready = assetIsReady(asset)

  useEffect(() => {
    setDisplayName(asset.displayName)
    setAltText(asset.altText ?? '')
    setCaption(asset.caption ?? '')
    setIsCover(asset.isCover)
  }, [asset.altText, asset.caption, asset.displayName, asset.eTag, asset.isCover])

  async function downloadDocument() {
    setDownloading(true)
    setDownloadError(null)
    try {
      const { blob } = await projectAssetApi.getContent(organizationId, projectId, asset.assetId)
      const objectUrl = URL.createObjectURL(blob)
      const anchor = document.createElement('a')
      anchor.href = objectUrl
      anchor.download = asset.fileName
      anchor.rel = 'noopener'
      anchor.hidden = true
      document.body.append(anchor)
      anchor.click()
      anchor.remove()
      window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0)
    } catch (error) {
      setDownloadError(projectAssetErrorMessage(error))
    } finally {
      setDownloading(false)
    }
  }

  function saveMetadata() {
    const normalizedName = displayName.trim()
    if (!normalizedName) {
      setMetadataError('projectAssets.nameRequired')
      return
    }
    if (normalizedName.length > 200) {
      setMetadataError('projectAssets.nameMax')
      return
    }
    if (altText.trim().length > 300) {
      setMetadataError('projectAssets.altMax')
      return
    }
    if (caption.trim().length > 1000) {
      setMetadataError('projectAssets.captionMax')
      return
    }
    if (isCover && !altText.trim()) {
      setMetadataError('projectAssets.coverNeedsAlt')
      return
    }
    setMetadataError(null)
    onSave(asset, {
      displayName: normalizedName,
      altText: altText.trim() || null,
      caption: caption.trim() || null,
      isCover: asset.kind === 0 && ready ? isCover : false,
    })
  }

  const changed = displayName !== asset.displayName ||
    altText !== (asset.altText ?? '') ||
    caption !== (asset.caption ?? '') ||
    isCover !== asset.isCover

  return <article className="overflow-hidden rounded-xl border bg-card">
    <div className="border-b bg-muted/30">
      {asset.kind === 0 && ready && <SecureProjectImage asset={asset} organizationId={organizationId} projectId={projectId} />}
      {asset.kind === 0 && !ready && <div className="flex h-32 items-center justify-center gap-2 text-sm text-muted-foreground"><ImageIcon aria-hidden className="size-5" /> {t('projectAssets.noPreview')}</div>}
      {asset.kind !== 0 && <div className="flex h-32 items-center justify-center gap-2 text-sm text-muted-foreground"><FileText aria-hidden className="size-7" /> {t(asset.kind === 2 ? 'projectAssets.video' : asset.mimeType === 'text/plain' ? 'projectAssets.text' : 'projectAssets.pdf')}</div>}
    </div>
    <div className="space-y-4 p-4">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0"><h3 className="truncate font-semibold">{asset.displayName}</h3><p className="truncate text-xs text-muted-foreground">{asset.fileName} · {formatBytes(asset.contentLength)}</p></div>
        <AssetStatus asset={asset} />
      </div>

      <div className="grid gap-3">
        <label className="grid gap-1 text-sm font-semibold">{t('projectAssets.displayName')}
          <Input disabled={!editable || busy} maxLength={200} onChange={event => setDisplayName(event.target.value)} value={displayName} />
        </label>
        {asset.kind === 0 && <label className="grid gap-1 text-sm font-semibold">{t('projectAssets.altText')} <span className="text-xs font-normal text-muted-foreground">{t('projectAssets.altHelp')}</span>
          <Input disabled={!editable || busy} maxLength={300} onChange={event => setAltText(event.target.value)} value={altText} />
        </label>}
        <label className="grid gap-1 text-sm font-semibold">{t('projectAssets.description')} <span className="text-xs font-normal text-muted-foreground">{t('projectAssets.optional')}</span>
          <textarea className={textareaClass} disabled={!editable || busy} maxLength={1000} onChange={event => setCaption(event.target.value)} value={caption} />
        </label>
        {asset.kind === 0 && <label className="flex items-start gap-2 text-sm">
          <input checked={isCover} disabled={!editable || busy || !ready} onChange={event => setIsCover(event.target.checked)} type="checkbox" />
          <span><span className="font-semibold">{t('projectAssets.useCover')}</span><span className="block text-xs text-muted-foreground">{t('projectAssets.coverHelp')}</span></span>
        </label>}
      </div>

      {metadataError && <p className="text-sm text-destructive" role="alert">{displayAssetMessage(metadataError)}</p>}
      {downloadError && <p className="text-sm text-destructive" role="alert">{displayAssetMessage(downloadError)}</p>}
      <div className="flex flex-wrap gap-2">
        <Button aria-label={t('projectAssets.moveUp', { name: asset.displayName })} disabled={!editable || busy || first} onClick={() => onMove(asset, -1)} size="icon" type="button" variant="outline"><ArrowUp aria-hidden className="size-4" /></Button>
        <Button aria-label={t('projectAssets.moveDown', { name: asset.displayName })} disabled={!editable || busy || last} onClick={() => onMove(asset, 1)} size="icon" type="button" variant="outline"><ArrowDown aria-hidden className="size-4" /></Button>
        <Button disabled={!editable || busy || !changed} onClick={saveMetadata} type="button" variant="outline"><Save aria-hidden className="size-4" /> {t('projectAssets.saveMetadata')}</Button>
        {asset.kind !== 0 && ready && <Button disabled={downloading} onClick={() => void downloadDocument()} type="button" variant="outline">{downloading ? <LoaderCircle aria-hidden className="size-4 animate-spin" /> : <Download aria-hidden className="size-4" />} {t(asset.mimeType === 'application/pdf' ? 'projectAssets.downloadPdf' : 'projectAssets.downloadFile')}</Button>}
        {!deleting && <Button disabled={!editable || busy} onClick={() => onDelete(asset)} type="button" variant="ghost"><Trash2 aria-hidden className="size-4" /> {t('projectAssets.delete')}</Button>}
      </div>
    </div>
  </article>
}

export function ProjectAssetsPanel(props: ProjectAssetsPanelProps) {
  // Never carry selected files, pending intent IDs or deadlines into another project.
  return <ProjectAssetsPanelForProject key={`${props.organizationId}:${props.projectId}`} {...props} />
}

function ProjectAssetsPanelForProject({
  organizationId,
  projectId,
  projectETag,
  publicationStatus,
  hasUnsavedChanges,
  onProjectChanged,
}: ProjectAssetsPanelProps) {
  const { t } = useTranslation()
  const enabled = isProjectAssetsEnabled()
  const queryClient = useQueryClient()
  const currentProjectETag = useRef(projectETag)
  const [files, setFiles] = useState<File[]>([])
  const [fileInputVersion, setFileInputVersion] = useState(0)
  const [selectionError, setSelectionError] = useState<AssetFeedback | null>(null)
  const [operationError, setOperationError] = useState<string | null>(null)
  const [tasks, setTasks] = useState<UploadTask[]>([])
  const [pollIteration, setPollIteration] = useState(0)
  const [deleteCandidate, setDeleteCandidate] = useState<ProjectAsset | null>(null)
  const polling = useProjectAssetPolling(enabled)
  const { active: pollingActive, canPollNow, restart: restartPolling } = polling
  const assets = useQuery({
    queryKey: projectAssetQueryKey(organizationId, projectId),
    queryFn: ({ signal }) => projectAssetApi.list(organizationId, projectId, signal),
    enabled,
    // A single bounded loop below refreshes intents and the gallery together.
    refetchOnWindowFocus: false,
    refetchOnReconnect: false,
    retry: false,
  })
  const { refetch: refetchAssets } = assets
  const hasPendingAssets = assets.data?.items.some(isAssetStillProcessing) ?? false

  useEffect(() => { currentProjectETag.current = projectETag }, [projectETag])
  useEffect(() => {
    if (assets.data?.projectETag) currentProjectETag.current = assets.data.projectETag
  }, [assets.data?.projectETag])

  const pendingIntentIds = tasks
    .filter(task => task.phase === 'analyzing' && task.intentId)
    .map(task => task.intentId!)
    .sort()
    .join(',')

  useEffect(() => {
    if (!pollingActive || (!pendingIntentIds && !hasPendingAssets)) return
    const controller = new AbortController()
    const timer = window.setTimeout(() => {
      if (!canPollNow()) return
      const intents = pendingIntentIds ? pendingIntentIds.split(',') : []
      void Promise.allSettled(intents.map(intentId =>
        projectAssetApi.getUploadIntent(
          organizationId,
          projectId,
          intentId,
          controller.signal,
        ),
      )).then(async results => {
        if (controller.signal.aborted) return
        const byIntent = new Map(intents.map((intentId, index) => [intentId, results[index]]))
        setTasks(current => current.map(task => {
          if (!task.intentId || task.phase !== 'analyzing') return task
          const result = byIntent.get(task.intentId)
          if (!result || result.status === 'rejected') {
            return { ...task, detail: 'projectAssets.scanContinues' }
          }
          const outcome = intentOutcome(result.value)
          if (outcome === 'ready') {
            return { ...task, phase: 'ready', detail: 'projectAssets.clean' }
          }
          if (outcome === 'rejected') {
            return { ...task, phase: 'error', detail: 'projectAssets.rejectedFile' }
          }
          return task
        }))
        if (canPollNow()) await refetchAssets()
        if (!controller.signal.aborted) setPollIteration(current => current + 1)
      })
    }, projectAssetPollingIntervalMs)
    return () => {
      window.clearTimeout(timer)
      controller.abort()
    }
  }, [organizationId, pendingIntentIds, hasPendingAssets, pollIteration, projectId,
    pollingActive, canPollNow, refetchAssets])

  function updateTask(id: string, patch: Partial<UploadTask>) {
    setTasks(current => current.map(task => task.id === id ? { ...task, ...patch } : task))
  }

  async function refreshAfterMutation(nextProjectETag?: string | null) {
    if (nextProjectETag) currentProjectETag.current = nextProjectETag
    const refreshed = await assets.refetch()
    if (refreshed.data?.projectETag) currentProjectETag.current = refreshed.data.projectETag
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ['project', organizationId, projectId] }),
      queryClient.invalidateQueries({ queryKey: ['projects', organizationId] }),
      onProjectChanged(),
    ])
  }

  const upload = useMutation({
    mutationFn: async (selectedFiles: File[]) => {
      const uploadTasks = selectedFiles.map(file => ({
        id: crypto.randomUUID(),
        file,
      }))
      const finalTasks: UploadTask[] = uploadTasks.map(({ id, file }) => ({
        id,
        fileName: file.name,
        phase: 'authorizing',
        detail: 'projectAssets.requesting',
      }))
      const recordTask = (id: string, patch: Partial<UploadTask>) => {
        const index = finalTasks.findIndex(task => task.id === id)
        if (index >= 0) finalTasks[index] = { ...finalTasks[index], ...patch }
        updateTask(id, patch)
      }
      setTasks(finalTasks)
      for (const { id, file } of uploadTasks) {
        try {
          const kind = fileKind(file)
          if (kind === null) throw new Error('unsupported-project-asset')
          const created = await projectAssetApi.createUploadIntent(
            organizationId,
            projectId,
            currentProjectETag.current,
            file,
            kind,
          )
          currentProjectETag.current = created.projectETag
          recordTask(id, {
            phase: 'uploading',
            detail: 'projectAssets.directTransfer',
          })
          await uploadProjectAssetDirectly(created, file)
          recordTask(id, {
            phase: 'analyzing',
            detail: 'projectAssets.isolated',
          })
          // El secreto vive únicamente en este alcance y se descarta después de completar.
          const completed = await projectAssetApi.completeUploadIntent(
            organizationId,
            projectId,
            created.intentId,
            created.completionToken,
          )
          if (completed.projectETag) currentProjectETag.current = completed.projectETag
          if (completed.storageStatus === 2 && completed.scanStatus === 1) {
            recordTask(id, { phase: 'ready', detail: 'projectAssets.clean' })
          } else if (
            completed.scanStatus === 2 ||
            completed.scanStatus === 3 ||
            completed.scanStatus === 4 ||
            completed.intentStatus === 3 ||
            completed.intentStatus === 4
          ) {
            recordTask(id, { phase: 'error', detail: 'projectAssets.rejectedFile' })
          } else {
            recordTask(id, {
              intentId: created.intentId,
              assetId: completed.assetId ?? undefined,
              detail: 'projectAssets.backgroundScan',
            })
          }
        } catch (error) {
          recordTask(id, { phase: 'error', detail: projectAssetErrorMessage(error) })
        }
      }
      return finalTasks
    },
    onSuccess: async finalTasks => {
      setTasks(finalTasks)
      setFiles([])
      setFileInputVersion(current => current + 1)
      restartPolling()
      await refreshAfterMutation(currentProjectETag.current)
    },
    onError: error => setOperationError(projectAssetErrorMessage(error)),
  })

  const metadata = useMutation({
    mutationFn: ({ asset, input }: { asset: ProjectAsset; input: ProjectAssetMetadataInput }) =>
      projectAssetApi.updateMetadata(
        organizationId,
        projectId,
        asset.assetId,
        asset.eTag,
        currentProjectETag.current,
        input,
      ),
    onSuccess: result => refreshAfterMutation(result.projectETag),
    onError: async error => {
      setOperationError(projectAssetErrorMessage(error))
      await refreshAfterMutation()
    },
  })

  const reorder = useMutation({
    mutationFn: ({ asset, direction }: { asset: ProjectAsset; direction: -1 | 1 }) => {
      const ordered = [...(assets.data?.items ?? [])].sort((left, right) => left.sortOrder - right.sortOrder)
      const index = ordered.findIndex(item => item.assetId === asset.assetId)
      const target = index + direction
      if (index < 0 || target < 0 || target >= ordered.length) throw new Error('invalid-project-asset-order')
      const [moved] = ordered.splice(index, 1)
      ordered.splice(target, 0, moved)
      return projectAssetApi.reorder(
        organizationId,
        projectId,
        currentProjectETag.current,
        ordered.map(item => ({ assetId: item.assetId, eTag: item.eTag })),
      )
    },
    onSuccess: result => refreshAfterMutation(result.projectETag),
    onError: async error => {
      setOperationError(projectAssetErrorMessage(error))
      await refreshAfterMutation()
    },
  })

  const remove = useMutation({
    mutationFn: (asset: ProjectAsset) => projectAssetApi.delete(
      organizationId,
      projectId,
      asset.assetId,
      asset.eTag,
      currentProjectETag.current,
    ),
    onSuccess: async result => {
      setDeleteCandidate(null)
      await refreshAfterMutation(result.projectETag)
    },
    onError: async error => {
      setOperationError(projectAssetErrorMessage(error))
      await refreshAfterMutation()
    },
  })

  if (!enabled) return null

  const items = [...(assets.data?.items ?? [])].sort((left, right) => left.sortOrder - right.sortOrder)
  const projectEditable = publicationStatus === 0 || publicationStatus === 3
  const busy = upload.isPending || metadata.isPending || reorder.isPending || remove.isPending
  const editable = projectEditable && !hasUnsavedChanges && !busy

  function selectFiles(event: ChangeEvent<HTMLInputElement>) {
    const selected = Array.from(event.target.files ?? [])
    const error = validateFiles(selected, items)
    setSelectionError(error)
    setFiles(error ? [] : selected)
    setTasks([])
    setOperationError(null)
  }

  return <Card>
    <CardHeader>
      <p className="text-xs font-bold uppercase tracking-[0.16em] text-primary">{t('projectAssets.eyebrow')}</p>
      <CardTitle>{t('projectAssets.title')}</CardTitle>
      <p className="text-sm text-muted-foreground">{t('projectAssets.help')}</p>
    </CardHeader>
    <CardContent className="space-y-5">
      {!projectEditable && <p className="rounded-lg bg-muted p-3 text-sm">{t('projectAssets.locked')}</p>}
      {hasUnsavedChanges && <p className="rounded-lg bg-muted p-3 text-sm">{t('projectAssets.unsaved')}</p>}

      {assets.isPending && <p className="flex items-center gap-2 text-sm text-muted-foreground"><LoaderCircle aria-hidden className="size-4 animate-spin" /> {t('projectAssets.loading')}</p>}
      {assets.isError && <p className="rounded-lg border border-destructive/50 bg-destructive/10 p-3 text-sm text-foreground" role="alert">{displayAssetMessage(projectAssetErrorMessage(assets.error))}</p>}

      <div className="flex flex-wrap items-center gap-3">
        <Button disabled={assets.isFetching || busy} onClick={() => {
          restartPolling()
          void refetchAssets()
        }} type="button" variant="outline"><RefreshCw aria-hidden className="size-4" /> {t('projectAssets.refreshStatus')}</Button>
        {!pollingActive && (hasPendingAssets || pendingIntentIds) && <p className="text-sm text-muted-foreground" role="status">{t('projectAssets.pollingPaused')}</p>}
      </div>

      {!assets.isError && <section className="space-y-3" aria-labelledby="project-assets-upload-title">
        <div><h2 className="font-semibold" id="project-assets-upload-title">{t('projectAssets.addFiles')}</h2><p className="mt-1 text-sm text-muted-foreground" id="project-assets-limits">{t('projectAssets.limits')}</p></div>
        <label className="grid gap-1.5 text-sm font-semibold" htmlFor="project-assets-files">{t('projectAssets.select')}</label>
        <Input accept={projectAssetAccept} aria-describedby="project-assets-limits" disabled={!editable || assets.isPending} id="project-assets-files" key={fileInputVersion} multiple onChange={selectFiles} type="file" />
        {files.length > 0 && <ul className="grid gap-1 text-sm">{files.map(file => <li key={`${file.name}-${file.size}`}>{file.name} · {formatBytes(file.size)}</li>)}</ul>}
        {selectionError && <p className="text-sm text-destructive" role="alert">{displayAssetMessage(selectionError)}</p>}
        <Button disabled={!editable || files.length === 0} onClick={() => upload.mutate(files)} type="button"><UploadCloud aria-hidden className="size-4" /> {files.length > 1 ? t('projectAssets.uploadMany', { count: files.length }) : t('projectAssets.uploadOne')}</Button>
      </section>}

      {tasks.length > 0 && <section aria-label={t('projectAssets.uploadStatus')} aria-live="polite"><ul className="grid gap-2">{tasks.map(task => <li className="rounded-lg border p-3 text-sm" key={task.id}><div className="flex items-center gap-2 font-semibold">{task.phase === 'ready' ? <CheckCircle2 aria-hidden className="size-4 text-primary" /> : task.phase === 'error' ? <ShieldAlert aria-hidden className="size-4 text-destructive" /> : <LoaderCircle aria-hidden className="size-4 animate-spin" />}<span>{task.fileName}: {displayAssetMessage(uploadPhaseLabel(task))}</span></div><p className="mt-1 text-xs text-muted-foreground">{displayAssetMessage(task.detail)}</p></li>)}</ul></section>}

      {operationError && <p className="rounded-lg border border-destructive/50 bg-destructive/10 p-3 text-sm text-foreground" role="alert">{displayAssetMessage(operationError)}</p>}

      {deleteCandidate && <div aria-describedby="delete-project-asset-description" aria-labelledby="delete-project-asset-title" className="rounded-lg border border-destructive/30 bg-destructive/5 p-4" role="alertdialog"><p className="font-semibold" id="delete-project-asset-title">{t('projectAssets.deleteTitle', { name: deleteCandidate.displayName })}</p><p className="mt-1 text-sm text-muted-foreground" id="delete-project-asset-description">{t('projectAssets.deleteHelp')}</p><div className="mt-3 flex flex-wrap gap-2"><Button disabled={remove.isPending} onClick={() => remove.mutate(deleteCandidate)} type="button" variant="outline">{remove.isPending ? <LoaderCircle aria-hidden className="size-4 animate-spin" /> : <Trash2 aria-hidden className="size-4" />} {t('projectAssets.confirmDelete')}</Button><Button disabled={remove.isPending} onClick={() => setDeleteCandidate(null)} type="button" variant="ghost">{t('projectAssets.cancel')}</Button></div></div>}

      {items.length === 0 && !assets.isPending && !assets.isError && <p className="rounded-lg border border-dashed p-6 text-center text-sm text-muted-foreground">{t('projectAssets.empty')}</p>}
      {items.length > 0 && <div className="grid gap-4 lg:grid-cols-2">{items.map((asset, index) => <AssetCard asset={asset} busy={busy} deleting={deleteCandidate?.assetId === asset.assetId} editable={editable} first={index === 0} key={asset.assetId} last={index === items.length - 1} onDelete={setDeleteCandidate} onMove={(item, direction) => reorder.mutate({ asset: item, direction })} onSave={(item, input) => metadata.mutate({ asset: item, input })} organizationId={organizationId} projectId={projectId} />)}</div>}

      <div className="rounded-lg border border-dashed p-4 text-sm text-muted-foreground"><strong className="text-foreground">{t('projectAssets.videoNext')}</strong> {t('projectAssets.videoHelp')}</div>
    </CardContent>
  </Card>
}
