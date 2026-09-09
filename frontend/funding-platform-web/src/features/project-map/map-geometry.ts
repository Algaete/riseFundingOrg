import type { MapPoint } from './project-map-api'

export function projectPoint(point: Pick<MapPoint, 'latitude' | 'longitude'>) {
  return { x: (point.longitude + 180) * 2, y: (90 - point.latitude) * 2 }
}
export function viewport(zoom: number, center = { x: 360, y: 180 }) {
  const width = 720 / 2 ** Math.max(0, Math.min(5, zoom)), height = width / 2
  const x = Math.max(0, Math.min(720 - width, center.x - width / 2))
  const y = Math.max(0, Math.min(360 - height, center.y - height / 2))
  return { x, y, width, height }
}
export function clusterPoints(points: MapPoint[], zoom: number) {
  const cells = new Map<string, MapPoint[]>()
  const size = 35 / 2 ** Math.max(0, Math.min(5, zoom))
  for (const point of points) {
    if (!Number.isFinite(point.latitude) || !Number.isFinite(point.longitude) || Math.abs(point.latitude) > 90 || Math.abs(point.longitude) > 180) continue
    const { x, y } = projectPoint(point)
    const key = `${Math.floor(x / size)}:${Math.floor(y / size)}`
    const cell = cells.get(key) ?? []; cell.push(point); cells.set(key, cell)
  }
  return [...cells].map(([key, items]) => ({ key, items,
    x: items.reduce((sum, point) => sum + projectPoint(point).x, 0) / items.length,
    y: items.reduce((sum, point) => sum + projectPoint(point).y, 0) / items.length }))
}
