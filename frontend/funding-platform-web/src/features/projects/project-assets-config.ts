export const projectAssetLimits = {
  imageBytes: 10 * 1024 * 1024,
  documentBytes: 25 * 1024 * 1024,
  textBytes: 1024 * 1024,
  imagesPerProject: 8,
  documentsPerProject: 4,
  totalPerProject: 12,
} as const

export const projectAssetAccept = [
  'image/jpeg',
  'image/png',
  'image/webp',
  'application/pdf',
  'text/plain',
  'video/mp4',
].join(',')

export function isProjectAssetsEnabled() {
  return import.meta.env.VITE_PROJECT_ASSETS_ENABLED === 'true'
}
