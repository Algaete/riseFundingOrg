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
} from 'lucide-react'
import {
  useEffect,
  useRef,
  useState,
  type ChangeEvent,
} from 'react'

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

type UploadPhase = 'authorizing' | 'uploading' | 'analyzing' | 'ready' | 'error'

interface UploadTask {
  id: string
  fileName: string
  phase: UploadPhase
  detail: string
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
  return new Intl.NumberFormat('es-CL', {
    maximumFractionDigits: 1,
    style: 'unit',
    unit: value >= 1024 * 1024 ? 'megabyte' : 'kilobyte',
    unitDisplay: 'short',
  }).format(value >= 1024 * 1024 ? value / (1024 * 1024) : value / 1024)
}

function assetIsReady(asset: ProjectAsset) {
  return asset.isReady && asset.storageStatus === 2 && asset.scanStatus === 1
}

function isAssetStillProcessing(asset: ProjectAsset) {
  return asset.storageStatus < 2 && asset.storageStatus !== 3 && asset.scanStatus === 0
}

function fileKind(file: File): 0 | 1 | null {
  const name = file.name.toLocaleLowerCase('en-US')
  if (
    (file.type === 'image/jpeg' && (name.endsWith('.jpg') || name.endsWith('.jpeg'))) ||
    (file.type === 'image/png' && name.endsWith('.png')) ||
    (file.type === 'image/webp' && name.endsWith('.webp'))
  ) return 0
  if (file.type === 'application/pdf' && name.endsWith('.pdf')) return 1
  return null
}

function validateFiles(files: File[], current: ProjectAsset[]) {
  if (files.length === 0) return 'Selecciona al menos un archivo.'
  const kinds = files.map(fileKind)
  if (kinds.some(kind => kind === null)) {
    return 'Sólo se admiten imágenes JPG, PNG o WebP y documentos PDF.'
  }
  const oversized = files.find((file, index) => {
    const maximum = kinds[index] === 0
      ? projectAssetLimits.imageBytes
      : projectAssetLimits.documentBytes
    return file.size < 1 || file.size > maximum
  })
  if (oversized) {
    const maximum = fileKind(oversized) === 0
      ? projectAssetLimits.imageBytes
      : projectAssetLimits.documentBytes
    return `${oversized.name} debe pesar entre 1 byte y ${formatBytes(maximum)}.`
  }
  const currentImages = current.filter(item => item.kind === 0).length
  const currentDocuments = current.filter(item => item.kind === 1).length
  const newImages = kinds.filter(kind => kind === 0).length
  const newDocuments = kinds.filter(kind => kind === 1).length
  if (current.length + files.length > projectAssetLimits.totalPerProject) {
    return `Cada proyecto admite como máximo ${projectAssetLimits.totalPerProject} adjuntos.`
  }
  if (currentImages + newImages > projectAssetLimits.imagesPerProject) {
    return `Cada proyecto admite como máximo ${projectAssetLimits.imagesPerProject} imágenes.`
  }
  if (currentDocuments + newDocuments > projectAssetLimits.documentsPerProject) {
    return `Cada proyecto admite como máximo ${projectAssetLimits.documentsPerProject} documentos PDF.`
  }
  return null
}

function uploadPhaseLabel(task: UploadTask) {
  if (task.phase === 'authorizing') return 'Creando autorización segura'
  if (task.phase === 'uploading') return 'Transfiriendo al almacenamiento'
  if (task.phase === 'analyzing') return 'Verificando y analizando'
  if (task.phase === 'ready') return 'Listo'
  return 'No se pudo cargar'
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

  if (failed) return <p className="p-4 text-sm text-muted-foreground">No fue posible cargar la vista previa.</p>
  if (!source) return <p className="flex items-center gap-2 p-4 text-sm text-muted-foreground"><LoaderCircle aria-hidden className="size-4 animate-spin" /> Cargando vista previa segura…</p>
  return <img alt={asset.altText ?? ''} className="h-48 w-full object-cover" src={source} />
}

function AssetStatus({ asset }: { asset: ProjectAsset }) {
  if (assetIsReady(asset)) {
    return <span className="flex items-center gap-1 text-xs font-semibold text-primary"><CheckCircle2 aria-hidden className="size-4" /> Listo y verificado</span>
  }
  if (asset.scanStatus === 2) {
    return <span className="flex items-center gap-1 text-xs font-semibold text-destructive"><ShieldAlert aria-hidden className="size-4" /> Rechazado por seguridad</span>
  }
  if (asset.scanStatus >= 3 || asset.storageStatus === 3) {
    return <span className="flex items-center gap-1 text-xs font-semibold text-destructive"><ShieldAlert aria-hidden className="size-4" /> Verificación fallida</span>
  }
  return <span className="flex items-center gap-1 text-xs text-muted-foreground"><LoaderCircle aria-hidden className="size-4 animate-spin" /> En cuarentena y análisis</span>
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
      setMetadataError('Ingresa un nombre visible.')
      return
    }
    if (normalizedName.length > 200) {
      setMetadataError('El nombre visible admite hasta 200 caracteres.')
      return
    }
    if (altText.trim().length > 300) {
      setMetadataError('El texto alternativo admite hasta 300 caracteres.')
      return
    }
    if (caption.trim().length > 1000) {
      setMetadataError('La descripción admite hasta 1000 caracteres.')
      return
    }
    if (isCover && !altText.trim()) {
      setMetadataError('La portada necesita texto alternativo.')
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
      {asset.kind === 0 && !ready && <div className="flex h-32 items-center justify-center gap-2 text-sm text-muted-foreground"><ImageIcon aria-hidden className="size-5" /> Sin vista previa hasta completar el análisis</div>}
      {asset.kind === 1 && <div className="flex h-32 items-center justify-center gap-2 text-sm text-muted-foreground"><FileText aria-hidden className="size-7" /> Documento PDF</div>}
    </div>
    <div className="space-y-4 p-4">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0"><h3 className="truncate font-semibold">{asset.displayName}</h3><p className="truncate text-xs text-muted-foreground">{asset.fileName} · {formatBytes(asset.contentLength)}</p></div>
        <AssetStatus asset={asset} />
      </div>

      <div className="grid gap-3">
        <label className="grid gap-1 text-sm font-semibold">Nombre visible
          <Input disabled={!editable || busy} maxLength={200} onChange={event => setDisplayName(event.target.value)} value={displayName} />
        </label>
        {asset.kind === 0 && <label className="grid gap-1 text-sm font-semibold">Texto alternativo <span className="text-xs font-normal text-muted-foreground">Describe la imagen para personas que no pueden verla.</span>
          <Input disabled={!editable || busy} maxLength={300} onChange={event => setAltText(event.target.value)} value={altText} />
        </label>}
        <label className="grid gap-1 text-sm font-semibold">Descripción <span className="text-xs font-normal text-muted-foreground">Opcional</span>
          <textarea className={textareaClass} disabled={!editable || busy} maxLength={1000} onChange={event => setCaption(event.target.value)} value={caption} />
        </label>
        {asset.kind === 0 && <label className="flex items-start gap-2 text-sm">
          <input checked={isCover} disabled={!editable || busy || !ready} onChange={event => setIsCover(event.target.checked)} type="checkbox" />
          <span><span className="font-semibold">Usar como portada</span><span className="block text-xs text-muted-foreground">Sólo una imagen lista y con texto alternativo puede ser portada.</span></span>
        </label>}
      </div>

      {metadataError && <p className="text-sm text-destructive" role="alert">{metadataError}</p>}
      {downloadError && <p className="text-sm text-destructive" role="alert">{downloadError}</p>}
      <div className="flex flex-wrap gap-2">
        <Button aria-label={`Subir ${asset.displayName} en el orden`} disabled={!editable || busy || first} onClick={() => onMove(asset, -1)} size="icon" type="button" variant="outline"><ArrowUp aria-hidden className="size-4" /></Button>
        <Button aria-label={`Bajar ${asset.displayName} en el orden`} disabled={!editable || busy || last} onClick={() => onMove(asset, 1)} size="icon" type="button" variant="outline"><ArrowDown aria-hidden className="size-4" /></Button>
        <Button disabled={!editable || busy || !changed} onClick={saveMetadata} type="button" variant="outline"><Save aria-hidden className="size-4" /> Guardar datos</Button>
        {asset.kind === 1 && ready && <Button disabled={downloading} onClick={() => void downloadDocument()} type="button" variant="outline">{downloading ? <LoaderCircle aria-hidden className="size-4 animate-spin" /> : <Download aria-hidden className="size-4" />} Descargar PDF</Button>}
        {!deleting && <Button disabled={!editable || busy} onClick={() => onDelete(asset)} type="button" variant="ghost"><Trash2 aria-hidden className="size-4" /> Eliminar</Button>}
      </div>
    </div>
  </article>
}

export function ProjectAssetsPanel({
  organizationId,
  projectId,
  projectETag,
  publicationStatus,
  hasUnsavedChanges,
  onProjectChanged,
}: ProjectAssetsPanelProps) {
  const enabled = isProjectAssetsEnabled()
  const queryClient = useQueryClient()
  const currentProjectETag = useRef(projectETag)
  const [files, setFiles] = useState<File[]>([])
  const [fileInputVersion, setFileInputVersion] = useState(0)
  const [selectionError, setSelectionError] = useState<string | null>(null)
  const [operationError, setOperationError] = useState<string | null>(null)
  const [tasks, setTasks] = useState<UploadTask[]>([])
  const [pollIteration, setPollIteration] = useState(0)
  const [deleteCandidate, setDeleteCandidate] = useState<ProjectAsset | null>(null)
  const assets = useQuery({
    queryKey: projectAssetQueryKey(organizationId, projectId),
    queryFn: ({ signal }) => projectAssetApi.list(organizationId, projectId, signal),
    enabled,
    refetchInterval: query => query.state.data?.items.some(isAssetStillProcessing) ? 2_000 : false,
  })

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
    if (!pendingIntentIds) return
    const controller = new AbortController()
    const timer = window.setTimeout(() => {
      const intents = pendingIntentIds.split(',')
      void Promise.allSettled(intents.map(intentId =>
        projectAssetApi.getUploadIntent(
          organizationId,
          projectId,
          intentId,
          controller.signal,
        ),
      )).then(results => {
        if (controller.signal.aborted) return
        const byIntent = new Map(intents.map((intentId, index) => [intentId, results[index]]))
        setTasks(current => current.map(task => {
          if (!task.intentId || task.phase !== 'analyzing') return task
          const result = byIntent.get(task.intentId)
          if (!result || result.status === 'rejected') {
            return { ...task, detail: 'El análisis continúa; volveremos a consultar su estado.' }
          }
          const outcome = intentOutcome(result.value)
          if (outcome === 'ready') {
            return { ...task, phase: 'ready', detail: 'El archivo quedó limpio y disponible.' }
          }
          if (outcome === 'rejected') {
            return { ...task, phase: 'error', detail: 'El archivo fue rechazado o no superó la verificación.' }
          }
          return task
        }))
        void queryClient.invalidateQueries({
          queryKey: projectAssetQueryKey(organizationId, projectId),
        })
        setPollIteration(current => current + 1)
      })
    }, 2_000)
    return () => {
      window.clearTimeout(timer)
      controller.abort()
    }
  }, [organizationId, pendingIntentIds, pollIteration, projectId, queryClient])

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
        detail: 'Solicitando una autorización de corta duración.',
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
            detail: 'La transferencia es directa; la autorización no permite sobrescribir archivos.',
          })
          await uploadProjectAssetDirectly(created, file)
          recordTask(id, {
            phase: 'analyzing',
            detail: 'El archivo está aislado mientras se comprueba su tipo y seguridad.',
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
            recordTask(id, { phase: 'ready', detail: 'El archivo quedó limpio y disponible.' })
          } else if (
            completed.scanStatus === 2 ||
            completed.scanStatus === 3 ||
            completed.scanStatus === 4 ||
            completed.intentStatus === 3 ||
            completed.intentStatus === 4
          ) {
            recordTask(id, { phase: 'error', detail: 'El archivo fue rechazado o no superó la verificación.' })
          } else {
            recordTask(id, {
              intentId: created.intentId,
              assetId: completed.assetId ?? undefined,
              detail: 'El análisis continúa en segundo plano; la galería se actualizará automáticamente.',
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
      <p className="text-xs font-bold uppercase tracking-[0.16em] text-primary">Adjuntos del proyecto</p>
      <CardTitle>Fotos y documentos</CardTitle>
      <p className="text-sm text-muted-foreground">Las imágenes y PDF son opcionales. Permanecen aislados hasta superar la validación de tipo y el análisis de seguridad.</p>
    </CardHeader>
    <CardContent className="space-y-5">
      {!projectEditable && <p className="rounded-lg bg-muted p-3 text-sm">Los adjuntos están bloqueados mientras el proyecto no sea borrador o rechazado.</p>}
      {hasUnsavedChanges && <p className="rounded-lg bg-muted p-3 text-sm">Guarda primero los cambios del formulario para evitar conflictos de versión.</p>}

      {assets.isPending && <p className="flex items-center gap-2 text-sm text-muted-foreground"><LoaderCircle aria-hidden className="size-4 animate-spin" /> Cargando adjuntos…</p>}
      {assets.isError && <p className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive" role="alert">{projectAssetErrorMessage(assets.error)}</p>}

      {!assets.isError && <section className="space-y-3" aria-labelledby="project-assets-upload-title">
        <div><h2 className="font-semibold" id="project-assets-upload-title">Agregar archivos</h2><p className="mt-1 text-sm text-muted-foreground" id="project-assets-limits">JPG, PNG o WebP: máximo 10 MB, hasta 8 imágenes. PDF: máximo 25 MB, hasta 4 documentos. Máximo 12 adjuntos en total.</p></div>
        <label className="grid gap-1.5 text-sm font-semibold" htmlFor="project-assets-files">Seleccionar fotos o documentos</label>
        <Input accept={projectAssetAccept} aria-describedby="project-assets-limits" disabled={!editable || assets.isPending} id="project-assets-files" key={fileInputVersion} multiple onChange={selectFiles} type="file" />
        {files.length > 0 && <ul className="grid gap-1 text-sm">{files.map(file => <li key={`${file.name}-${file.size}`}>{file.name} · {formatBytes(file.size)}</li>)}</ul>}
        {selectionError && <p className="text-sm text-destructive" role="alert">{selectionError}</p>}
        <Button disabled={!editable || files.length === 0} onClick={() => upload.mutate(files)} type="button"><UploadCloud aria-hidden className="size-4" /> Cargar y verificar {files.length > 1 ? `${files.length} archivos` : 'archivo'}</Button>
      </section>}

      {tasks.length > 0 && <section aria-label="Estado de las cargas" aria-live="polite"><ul className="grid gap-2">{tasks.map(task => <li className="rounded-lg border p-3 text-sm" key={task.id}><div className="flex items-center gap-2 font-semibold">{task.phase === 'ready' ? <CheckCircle2 aria-hidden className="size-4 text-primary" /> : task.phase === 'error' ? <ShieldAlert aria-hidden className="size-4 text-destructive" /> : <LoaderCircle aria-hidden className="size-4 animate-spin" />}<span>{task.fileName}: {uploadPhaseLabel(task)}</span></div><p className="mt-1 text-xs text-muted-foreground">{task.detail}</p></li>)}</ul></section>}

      {operationError && <p className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive" role="alert">{operationError}</p>}

      {deleteCandidate && <div aria-describedby="delete-project-asset-description" aria-labelledby="delete-project-asset-title" className="rounded-lg border border-destructive/30 bg-destructive/5 p-4" role="alertdialog"><p className="font-semibold" id="delete-project-asset-title">¿Eliminar {deleteCandidate.displayName}?</p><p className="mt-1 text-sm text-muted-foreground" id="delete-project-asset-description">Esta acción quitará el archivo del proyecto.</p><div className="mt-3 flex gap-2"><Button disabled={remove.isPending} onClick={() => remove.mutate(deleteCandidate)} type="button" variant="outline">{remove.isPending ? <LoaderCircle aria-hidden className="size-4 animate-spin" /> : <Trash2 aria-hidden className="size-4" />} Confirmar eliminación</Button><Button disabled={remove.isPending} onClick={() => setDeleteCandidate(null)} type="button" variant="ghost">Cancelar</Button></div></div>}

      {items.length === 0 && !assets.isPending && !assets.isError && <p className="rounded-lg border border-dashed p-6 text-center text-sm text-muted-foreground">Este proyecto todavía no tiene fotos ni documentos.</p>}
      {items.length > 0 && <div className="grid gap-4 lg:grid-cols-2">{items.map((asset, index) => <AssetCard asset={asset} busy={busy} deleting={deleteCandidate?.assetId === asset.assetId} editable={editable} first={index === 0} key={asset.assetId} last={index === items.length - 1} onDelete={setDeleteCandidate} onMove={(item, direction) => reorder.mutate({ asset: item, direction })} onSave={(item, input) => metadata.mutate({ asset: item, input })} organizationId={organizationId} projectId={projectId} />)}</div>}

      <div className="rounded-lg border border-dashed p-4 text-sm text-muted-foreground"><strong className="text-foreground">Videos: próxima fase.</strong> Se habilitarán cuando exista validación y transcodificación aislada para ese formato.</div>
    </CardContent>
  </Card>
}
