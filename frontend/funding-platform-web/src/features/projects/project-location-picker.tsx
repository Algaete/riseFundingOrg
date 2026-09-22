import { useId, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Button } from '@/components/ui/button'
import { projectPoint, viewport } from '@/features/project-map/map-geometry'
import world from '@/features/project-map/world-land.svg'

export type ProjectLocation = { latitude: number; longitude: number }

// Shared basemap/projection with the public project map. No external geocoder,
// browser geolocation, or disclosure of the user's location is involved.
export function ProjectLocationPicker({ value, onChange }: {
  value: ProjectLocation | null; onChange: (point: ProjectLocation) => void
}) {
  const { t } = useTranslation()
  const helpId = useId()
  const [zoom, setZoom] = useState(value ? 2 : 0)
  const [center, setCenter] = useState(value ? projectPoint(value) : { x: 360, y: 180 })
  const box = viewport(zoom, center)
  const point = value ? projectPoint(value) : null
  const pan = (dx: number, dy: number) => setCenter({ x: box.x + box.width * (.5 + dx), y: box.y + box.height * (.5 + dy) })
  const choose = (x: number, y: number) => onChange({
    latitude: Math.round(Math.max(-90, Math.min(90, 90 - y / 2)) * 10000) / 10000,
    longitude: Math.round(Math.max(-180, Math.min(180, x / 2 - 180)) * 10000) / 10000,
  })
  return <div className="space-y-3">
    <p id={helpId} className="text-sm text-muted-foreground">{t('projects.enrichment.mapHelp')}</p>
    <div className="flex flex-wrap gap-2">
      <Button type="button" variant="outline" disabled={zoom === 5} onClick={() => setZoom(v => v + 1)}>{t('projects.enrichment.zoomIn')}</Button>
      <Button type="button" variant="outline" disabled={zoom === 0} onClick={() => setZoom(v => v - 1)}>{t('projects.enrichment.zoomOut')}</Button>
      {([['west', -.35, 0], ['east', .35, 0], ['north', 0, -.35], ['south', 0, .35]] as const).map(([key, x, y]) => <Button key={key} type="button" variant="outline" disabled={zoom === 0} onClick={() => pan(x, y)}>{t(`projects.enrichment.${key}`)}</Button>)}
    </div>
    <button type="button" aria-label={t('projects.enrichment.choosePoint')} aria-describedby={helpId}
      className="relative block aspect-[2/1] w-full cursor-crosshair overflow-hidden rounded-xl border bg-sky-50 focus-visible:outline-2 focus-visible:outline-primary dark:bg-slate-900"
      onClick={event => {
        const rect = event.currentTarget.getBoundingClientRect()
        if (event.detail === 0) choose(box.x + box.width / 2, box.y + box.height / 2)
        else if (rect.width > 0 && rect.height > 0) choose(box.x + (event.clientX - rect.left) / rect.width * box.width, box.y + (event.clientY - rect.top) / rect.height * box.height)
      }}>
      <svg className="absolute inset-0 size-full" viewBox={`${box.x} ${box.y} ${box.width} ${box.height}`} aria-hidden="true">
        <image href={world} width={720} height={360} />
        <path d={`M ${box.x + box.width / 2 - box.width * .018},${box.y + box.height / 2} h ${box.width * .036} M ${box.x + box.width / 2},${box.y + box.height / 2 - box.width * .018} v ${box.width * .036}`} stroke="#334155" strokeWidth={box.width / 500} />
        {point && <circle cx={point.x} cy={point.y} r={box.width * .012} fill="#047857" stroke="white" strokeWidth={box.width / 400} />}
      </svg>
    </button>
    <Button type="button" variant="outline" onClick={() => choose(box.x + box.width / 2, box.y + box.height / 2)}>{t('projects.enrichment.useCenter')}</Button>
    <p role="status" className="text-sm">{t(value ? 'projects.enrichment.pointSelected' : 'projects.enrichment.noPoint')}</p>
    <p className="text-xs text-muted-foreground">{t('projects.enrichment.basemap')} · <a className="underline" href="https://www.naturalearthdata.com/about/terms-of-use/" target="_blank" rel="noreferrer">Natural Earth</a></p>
  </div>
}
