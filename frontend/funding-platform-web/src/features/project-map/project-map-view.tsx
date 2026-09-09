import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Button } from '@/components/ui/button'
import { clusterPoints, viewport } from './map-geometry'
import type { MapPoint } from './project-map-api'
import world from './world-land.svg'

export function ProjectMapView({ points, select }: { points: MapPoint[]; select: (ids: string[]) => void }) {
  const { t } = useTranslation()
  const [zoom, setZoom] = useState(0)
  const [center, setCenter] = useState({ x: 360, y: 180 })
  const box = viewport(zoom, center)
  const pan = (dx: number, dy: number) => setCenter({ x: box.x + box.width * (.5 + dx), y: box.y + box.height * (.5 + dy) })
  return <section className="space-y-3" aria-label={t('projectMap.map')}>
    <div className="flex flex-wrap gap-2">
      <Button variant="outline" disabled={zoom === 5} onClick={() => setZoom(value => value + 1)}>{t('projectMap.zoomIn')}</Button>
      <Button variant="outline" disabled={zoom === 0} onClick={() => setZoom(value => value - 1)}>{t('projectMap.zoomOut')}</Button>
      <Button variant="outline" onClick={() => { setZoom(0); setCenter({ x: 360, y: 180 }); select([]) }}>{t('projectMap.reset')}</Button>
      {([['west', -.35, 0], ['east', .35, 0], ['north', 0, -.35], ['south', 0, .35]] as const).map(([key, x, y]) => <Button key={key} variant="outline" disabled={zoom === 0} onClick={() => pan(x, y)}>{t(`projectMap.${key}`)}</Button>)}
    </div>
    <div className="relative aspect-[2/1] overflow-hidden rounded-xl border bg-sky-50 dark:bg-slate-900">
      <svg className="absolute inset-0 size-full" viewBox={`${box.x} ${box.y} ${box.width} ${box.height}`} aria-hidden="true">
        <image href={world} width={720} height={360} />
      </svg>
      {clusterPoints(points, zoom).filter(c => c.x >= box.x && c.x <= box.x + box.width && c.y >= box.y && c.y <= box.y + box.height).map(cluster => <button key={cluster.key} type="button"
        className="absolute flex size-8 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full border-2 border-white bg-emerald-800 text-xs font-bold text-white shadow focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-black dark:focus-visible:outline-white"
        style={{ left: `${Math.max(3, Math.min(97, (cluster.x - box.x) / box.width * 100))}%`, top: `${Math.max(6, Math.min(94, (cluster.y - box.y) / box.height * 100))}%` }}
        aria-label={cluster.items.length === 1 ? t('projectMap.selectProject', { title: cluster.items[0].title }) : t('projectMap.cluster', { count: cluster.items.length })}
        onClick={() => { select(cluster.items.map(p => p.publicId)); if (cluster.items.length > 1) { setCenter({ x: cluster.x, y: cluster.y }); setZoom(value => Math.min(5, value + 1)) } }}>
        {cluster.items.length}
      </button>)}
    </div>
    <p className="text-xs text-muted-foreground">{t('projectMap.basemap')} · <a className="underline" href="https://www.naturalearthdata.com/about/terms-of-use/" target="_blank" rel="noreferrer">Natural Earth</a></p>
  </section>
}
