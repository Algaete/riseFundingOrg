import { useTranslation } from 'react-i18next'
export function PilotGuide({ compact = false }: { compact?: boolean }) {
  const { t } = useTranslation()
  return <section className="rounded-2xl border border-border bg-card p-5" aria-label={t('pilot.stepsTitle')}>
    <h2 className="font-semibold">{t('pilot.stepsTitle')}</h2>
    <ol className={`mt-3 list-decimal space-y-2 pl-5 text-sm ${compact ? '' : 'md:grid md:grid-cols-3 md:gap-8 md:space-y-0'}`}>
      {(['stepsAccount', 'stepsOrg', 'stepsProject'] as const).map(step => <li key={step}>{t(`pilot.${step}`)}</li>)}
    </ol>
    <p className="mt-4 text-sm text-muted-foreground">{t('pilot.free')}</p>
    {!compact && <p className="mt-2 text-sm text-muted-foreground">{t('pilot.detail')}</p>}
  </section>
}
