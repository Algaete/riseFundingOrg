import { useTranslation } from 'react-i18next'
import { formatNumber as formatWorkspaceNumber } from '@/i18n/formats'
import type { ProjectEnrichment } from './project-enrichment'

export function ProjectEnrichmentSummary({ value, privateView = false }: { value?: ProjectEnrichment | null; privateView?: boolean }) {
  const { t } = useTranslation()
  if (!value) return null
  const showLocality = privateView || [1, 2].includes(value.locationVisibility)
  const showCoordinates = privateView || value.locationVisibility === 2
  const textFields = ['problem', 'solution', 'soughtPartners', 'soughtProfessionals'] as const
  return <section className="space-y-5" aria-label={t('projects.enrichment.impactTitle')}>
    {textFields.map(key => value[key] && <div key={key}><h3 className="font-semibold">{t(`projects.enrichment.${key}`)}</h3><p className="mt-2 whitespace-pre-line break-words leading-7 text-muted-foreground">{value[key]}</p></div>)}
    {value.beneficiaryCount != null && <p><strong>{t('projects.enrichment.beneficiaryCount')}: </strong>{formatWorkspaceNumber(value.beneficiaryCount)}</p>}
    {showLocality && value.locality && <p><strong>{t('projects.enrichment.locality')}: </strong>{value.locality}</p>}
    {showCoordinates && value.latitude != null && value.longitude != null && <p><strong>{t(privateView ? 'projects.enrichment.privateCoordinates' : 'projects.enrichment.approximateLocation')}: </strong>{formatWorkspaceNumber(value.latitude, { maximumFractionDigits: privateView ? 8 : 2 })}, {formatWorkspaceNumber(value.longitude, { maximumFractionDigits: privateView ? 8 : 2 })}</p>}
    {value.seekingConsortium != null && <p><strong>{t('projects.enrichment.seekingConsortium')}: </strong>{t(value.seekingConsortium ? 'projects.enrichment.yes' : 'projects.enrichment.no')}</p>}
    {(value.impactIndicators?.length ?? 0) > 0 && <div className="space-y-3"><h3 className="font-semibold">{t('projects.enrichment.indicators')}</h3><ul className="grid gap-3 sm:grid-cols-2">{value.impactIndicators.map((item, index) => <li className="rounded-lg border p-4" key={index}><p className="font-semibold">{item.name} · {item.unit}</p><dl className="mt-2 space-y-1 text-sm text-muted-foreground"><div><dt className="inline">{t('projects.enrichment.baseline')}: </dt><dd className="inline">{item.baseline == null ? t('projects.notReported') : formatWorkspaceNumber(item.baseline, { maximumFractionDigits: 6 })}</dd></div><div><dt className="inline">{t('projects.enrichment.target')}: </dt><dd className="inline">{item.target == null ? t('projects.notReported') : formatWorkspaceNumber(item.target, { maximumFractionDigits: 6 })}</dd></div></dl></li>)}</ul></div>}
  </section>
}
