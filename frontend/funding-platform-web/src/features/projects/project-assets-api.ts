import { ApiError, apiClient } from '@/api/http-client'

export type ProjectAssetKind = 0 | 1
export type ProjectAssetUploadIntentStatus = 0 | 1 | 2 | 3 | 4
export type ProjectAssetStorageStatus = 0 | 1 | 2 | 3
export type ProjectAssetScanStatus = 0 | 1 | 2 | 3 | 4
export type ProjectAssetScanProvider = 0 | 1

export interface ProjectAsset {
  assetId: string
  kind: ProjectAssetKind
  fileName: string
  displayName: string
  mimeType: string
  contentLength: number
  pixelWidth: number | null
  pixelHeight: number | null
  storageStatus: ProjectAssetStorageStatus
  scanStatus: ProjectAssetScanStatus
  scanProvider: ProjectAssetScanProvider
  scanResultCode: string | null
  sortOrder: number
  isCover: boolean
  altText: string | null
  caption: string | null
  isReady: boolean
  contentUrl: string | null
  createdAtUtc: string
  updatedAtUtc: string
  eTag: string
}

export interface ProjectAssetCollection {
  projectId: string
  publicationStatus: number
  projectETag: string
  items: ProjectAsset[]
}

export interface ProjectAssetUploadIntentCreated {
  intentId: string
  kind: ProjectAssetKind
  status: ProjectAssetUploadIntentStatus
  expiresAtUtc: string
  maxContentLength: number
  uploadMethod: 'PUT'
  uploadUrl: string
  requiredHeaders: Record<string, string>
  completionToken: string
  statusUrl: string
  eTag: string
  projectETag: string
  securityNotice: string
}

export interface ProjectAssetUploadIntent {
  intentId: string
  projectId: string
  kind: ProjectAssetKind
  fileName: string
  declaredMimeType: string
  expectedContentLength: number
  maxContentLength: number
  status: ProjectAssetUploadIntentStatus
  expiresAtUtc: string
  assetId: string | null
  storageStatus: ProjectAssetStorageStatus | null
  scanStatus: ProjectAssetScanStatus | null
  scanProvider: ProjectAssetScanProvider | null
  createdAtUtc: string
  updatedAtUtc: string
  eTag: string
}

export interface ProjectAssetOperation {
  code: string
  intentId: string | null
  intentStatus: ProjectAssetUploadIntentStatus | null
  assetId: string | null
  storageStatus: ProjectAssetStorageStatus | null
  scanStatus: ProjectAssetScanStatus | null
  scanProvider: ProjectAssetScanProvider | null
  intentETag: string | null
  assetETag: string | null
  projectETag: string | null
  wasReplay: boolean
}

export interface ProjectAssetMetadataInput {
  displayName: string
  altText: string | null
  caption: string | null
  isCover: boolean
}

function projectPath(organizationId: string, projectId: string, suffix: string) {
  return `organizations/${encodeURIComponent(organizationId)}/projects/${encodeURIComponent(projectId)}${suffix}`
}

export const projectAssetQueryKey = (organizationId: string, projectId: string) =>
  ['project-assets', organizationId, projectId] as const

export const projectAssetApi = {
  list(organizationId: string, projectId: string, signal?: AbortSignal) {
    return apiClient.get<ProjectAssetCollection>(
      projectPath(organizationId, projectId, '/assets'),
      { cache: 'no-store', signal },
    )
  },
  createUploadIntent(
    organizationId: string,
    projectId: string,
    projectETag: string,
    file: File,
    kind: ProjectAssetKind,
  ) {
    return apiClient.post<ProjectAssetUploadIntentCreated>(
      projectPath(organizationId, projectId, '/asset-upload-intents'),
      {
        kind,
        fileName: file.name,
        mimeType: file.type,
        contentLength: file.size,
      },
      { cache: 'no-store', headers: { 'If-Match': projectETag } },
    )
  },
  getUploadIntent(
    organizationId: string,
    projectId: string,
    intentId: string,
    signal?: AbortSignal,
  ) {
    return apiClient.get<ProjectAssetUploadIntent>(
      projectPath(
        organizationId,
        projectId,
        `/asset-upload-intents/${encodeURIComponent(intentId)}`,
      ),
      { cache: 'no-store', signal },
    )
  },
  completeUploadIntent(
    organizationId: string,
    projectId: string,
    intentId: string,
    completionToken: string,
  ) {
    return apiClient.post<ProjectAssetOperation>(
      projectPath(
        organizationId,
        projectId,
        `/asset-upload-intents/${encodeURIComponent(intentId)}/complete`,
      ),
      { completionToken },
      { cache: 'no-store' },
    )
  },
  updateMetadata(
    organizationId: string,
    projectId: string,
    assetId: string,
    assetETag: string,
    projectETag: string,
    input: ProjectAssetMetadataInput,
  ) {
    return apiClient.patch<ProjectAssetOperation>(
      projectPath(organizationId, projectId, `/assets/${encodeURIComponent(assetId)}`),
      input,
      {
        cache: 'no-store',
        headers: {
          'If-Match': assetETag,
          'X-Project-If-Match': projectETag,
        },
      },
    )
  },
  reorder(
    organizationId: string,
    projectId: string,
    projectETag: string,
    items: Pick<ProjectAsset, 'assetId' | 'eTag'>[],
  ) {
    return apiClient.put<ProjectAssetOperation>(
      projectPath(organizationId, projectId, '/assets/order'),
      { items },
      { cache: 'no-store', headers: { 'If-Match': projectETag } },
    )
  },
  delete(
    organizationId: string,
    projectId: string,
    assetId: string,
    assetETag: string,
    projectETag: string,
  ) {
    return apiClient.delete<ProjectAssetOperation>(
      projectPath(organizationId, projectId, `/assets/${encodeURIComponent(assetId)}`),
      {
        cache: 'no-store',
        headers: {
          'If-Match': assetETag,
          'X-Project-If-Match': projectETag,
        },
      },
    )
  },
  getContent(
    organizationId: string,
    projectId: string,
    assetId: string,
    signal?: AbortSignal,
  ) {
    return apiClient.getBlob(
      projectPath(organizationId, projectId, `/assets/${encodeURIComponent(assetId)}/content`),
      { signal },
    )
  },
}

export async function uploadProjectAssetDirectly(
  grant: ProjectAssetUploadIntentCreated,
  file: File,
  signal?: AbortSignal,
) {
  const headers = new Headers()
  Object.entries(grant.requiredHeaders).forEach(([name, value]) => headers.set(name, value))
  const response = await fetch(grant.uploadUrl, {
    method: grant.uploadMethod,
    headers,
    body: file,
    credentials: 'omit',
    cache: 'no-store',
    redirect: 'error',
    referrerPolicy: 'no-referrer',
    signal,
  })
  if (!response.ok) throw new ProjectAssetDirectUploadError(response.status)
}

export class ProjectAssetDirectUploadError extends Error {
  readonly status: number

  constructor(status: number) {
    super('No fue posible transferir el archivo al almacenamiento seguro.')
    this.name = 'ProjectAssetDirectUploadError'
    this.status = status
  }
}

function safeProblemText(value: string) {
  return value
    .replace(/https?:\/\/[^\s]+/gi, '[URL protegida]')
    .replace(/\b(bearer|token|password|secret|signature|sig|key|sas)\b\s*[:=]\s*[^\s,;]+/gi, '$1=[protegido]')
    .slice(0, 500)
}

export function projectAssetErrorMessage(error: unknown) {
  if (error instanceof ApiError) {
    if (error.response.status === 401) return 'La sesión venció. Inicia sesión nuevamente.'
    if (error.response.status === 403) return 'Necesitas permisos de administración en esta organización.'
    if (error.response.status === 409) return 'El proyecto o adjunto cambió de estado. Recarga antes de continuar.'
    if (error.response.status === 410) return 'La autorización de carga venció. Selecciona el archivo nuevamente.'
    if (error.response.status === 412) return 'La versión cambió. Recargaremos los adjuntos para que puedas reintentar.'
    if (error.response.status === 422) {
      const firstValidation = Object.values(error.problem.errors ?? {}).flat()[0]
      return safeProblemText(firstValidation ?? error.problem.detail ?? 'Revisa el archivo e intenta nuevamente.')
    }
    if (error.response.status === 503) return 'Los adjuntos todavía no están habilitados en este entorno.'
    return safeProblemText(error.problem.detail ?? error.problem.title)
  }
  if (error instanceof ProjectAssetDirectUploadError) return error.message
  return 'No fue posible completar la operación con el adjunto. Intenta nuevamente.'
}
